with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with Flyology.IO;
with Flyology.Object_Storage.Backends.Bucket_Listing;
with Flyology.Object_Storage.Backends.Listing;
with Flyology.Object_Storage.Backends.Multipart_Listing;
with GNAT.MD5;
with GNAT.SHA256;

package body Flyology.Object_Storage.Backends.Memory is

   use type Ada.Calendar.Time;
   use type Ada.Real_Time.Time;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Strings.Unbounded.Unbounded_String;

   Empty_Info : constant Object_Information := (others => <>);
   Epoch : constant Ada.Calendar.Time :=
     Ada.Calendar.Formatting.Time_Of
       (1970, 1, 1, 0, 0, 0, Time_Zone => 0);

   procedure Free is new Ada.Unchecked_Deallocation
     (Ada.Streams.Stream_Element_Array, Byte_Array_Access);

   overriding procedure Adjust (Data : in out Owned_Bytes) is
      Original : constant Byte_Array_Access := Data.Value;
   begin
      if Original /= null then
         Data.Value := null;
         Data.Capacity := Data.Length;
         Data.Value := new Ada.Streams.Stream_Element_Array
           (1 .. Ada.Streams.Stream_Element_Offset (Data.Capacity));
         if Data.Length > 0 then
            Data.Value
              (1 .. Ada.Streams.Stream_Element_Offset (Data.Length)) :=
                Original
                  (1 .. Ada.Streams.Stream_Element_Offset (Data.Length));
         end if;
      end if;
   end Adjust;

   overriding procedure Finalize (Data : in out Owned_Bytes) is
   begin
      Free (Data.Value);
      Data.Length := 0;
      Data.Capacity := 0;
   end Finalize;

   procedure Reserve_Capacity
     (Data : in out Owned_Bytes; Capacity : Natural)
   is
      Replacement : Byte_Array_Access;
   begin
      if Capacity <= Data.Capacity then
         return;
      end if;
      Replacement := new Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Capacity));
      if Data.Length > 0 then
         Replacement (1 .. Ada.Streams.Stream_Element_Offset (Data.Length)) :=
           Data.Value (1 .. Ada.Streams.Stream_Element_Offset (Data.Length));
      end if;
      Free (Data.Value);
      Data.Value := Replacement;
      Data.Capacity := Capacity;
   end Reserve_Capacity;

   function Growth_Capacity
     (Data : Owned_Bytes; Required : Natural) return Natural
   is
      Growth : Natural;
   begin
      if Required <= Data.Capacity then
         return Data.Capacity;
      end if;
      Growth := Natural'Max
        (Required, Natural'Max (4_096, Data.Capacity));
      if Growth > Natural'Last / 2 then
         return Required;
      else
         return Natural'Max (Required, Growth * 2);
      end if;
   end Growth_Capacity;

   procedure Append
     (Data  : in out Owned_Bytes;
      Value : Ada.Streams.Stream_Element_Array)
   is
      Required : Natural;
   begin
      if Value'Length > Natural'Last - Data.Length then
         raise Constraint_Error with "memory object exceeds addressable size";
      end if;
      Required := Data.Length + Value'Length;
      if Required > Data.Capacity then
         Reserve_Capacity (Data, Growth_Capacity (Data, Required));
      end if;
      if Value'Length > 0 then
         Data.Value
           (Ada.Streams.Stream_Element_Offset (Data.Length + 1) ..
              Ada.Streams.Stream_Element_Offset (Required)) := Value;
         Data.Length := Required;
      end if;
   end Append;

   procedure Append (Data : in out Owned_Bytes; Value : Owned_Bytes) is
   begin
      if Value.Length > 0 then
         Append
           (Data,
            Value.Value
              (1 .. Ada.Streams.Stream_Element_Offset (Value.Length)));
      end if;
   end Append;

   procedure Move (Target : in out Owned_Bytes; Source : in out Owned_Bytes) is
   begin
      Free (Target.Value);
      Target.Value := Source.Value;
      Target.Length := Source.Length;
      Target.Capacity := Source.Capacity;
      Source.Value := null;
      Source.Length := 0;
      Source.Capacity := 0;
   end Move;

   function Element
     (Data : Owned_Bytes; Index : Positive)
      return Ada.Streams.Stream_Element is
     (Data.Value (Ada.Streams.Stream_Element_Offset (Index)));

   function Current_Unix_Time return Unix_Time is
     (Unix_Time (Long_Long_Integer (Ada.Calendar.Clock - Epoch)));

   function Hex_Nibble (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 16);

   procedure Include_Part_Digest
     (Hash : in out GNAT.MD5.Context; Entity_Tag : String)
   is
      Digest : String (1 .. 16);
   begin
      if Entity_Tag'Length /= 32 then
         raise Constraint_Error;
      end if;
      for Index in Digest'Range loop
         declare
            High : constant Natural := Hex_Nibble
              (Entity_Tag (Entity_Tag'First + 2 * (Index - 1)));
            Low  : constant Natural := Hex_Nibble
              (Entity_Tag (Entity_Tag'First + 2 * (Index - 1) + 1));
         begin
            if High > 15 or else Low > 15 then
               raise Constraint_Error;
            end if;
            Digest (Index) := Character'Val (16 * High + Low);
         end;
      end loop;
      GNAT.MD5.Update (Hash, Digest);
   end Include_Part_Digest;

   procedure Check_Context
     (Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
   begin
      if Token /= null and then Token.Requested then
         raise Flyology.Cancellation.Operation_Cancelled;
      end if;
      if Deadline /= Ada.Real_Time.Time_Last
        and then Ada.Real_Time.Clock >= Deadline
      then
         raise Flyology.IO.Timeout_Error;
      end if;
   end Check_Context;

   protected body Memory_State is
      function Bucket_Index (Name : String) return Natural is
      begin
         for Index in Buckets'Range loop
            if Buckets (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Buckets (Index).Name) = Name
            then
               return Index;
            end if;
         end loop;
         return 0;
      end Bucket_Index;

      function Object_Index
        (Bucket : String; Key : String) return Natural
      is
      begin
         for Index in 1 .. Highest_Object loop
            if Objects (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Bucket) = Bucket
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Key) = Key
            then
               return Index;
            end if;
         end loop;
         return 0;
      end Object_Index;

      function Upload_Index
        (Bucket : String; Key : String; Upload_ID : String) return Natural
      is
      begin
         for Index in Uploads'Range loop
            if Uploads (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Uploads (Index).Bucket) = Bucket
              and then Ada.Strings.Unbounded.To_String
                (Uploads (Index).Key) = Key
              and then Ada.Strings.Unbounded.To_String
                (Uploads (Index).ID) = Upload_ID
            then
               return Index;
            end if;
         end loop;
         return 0;
      end Upload_Index;

      function Part_Index
        (Upload_ID : String;
         Part_Number : Multipart_Part_Number) return Natural
      is
      begin
         for Index in 1 .. Highest_Part loop
            if Parts (Index).Used
              and then Parts (Index).Number = Part_Number
              and then Ada.Strings.Unbounded.To_String
                (Parts (Index).Upload_ID) = Upload_ID
            then
               return Index;
            end if;
         end loop;
         return 0;
      end Part_Index;

      procedure Create_Bucket
        (Name : String; Created : Unix_Time; Result : out Status)
      is
      begin
         if Bucket_Index (Name) /= 0 then
            Result := Already_Exists;
            return;
         end if;
         for Index in Buckets'Range loop
            if not Buckets (Index).Used then
               Buckets (Index).Used := True;
               Buckets (Index).Name :=
                 Ada.Strings.Unbounded.To_Unbounded_String (Name);
               Buckets (Index).Created := Created;
               Result := Success;
               return;
            end if;
         end loop;
         Result := Capacity_Exceeded;
      end Create_Bucket;

      procedure List_Buckets
        (Options : List_Buckets_Options;
         Page    : out Bucket_Page;
         Result  : out Status)
      is
         Builder : Bucket_Listing.Builder;
      begin
         Bucket_Listing.Initialize (Builder, Options);
         for Bucket of Buckets loop
            if Bucket.Used then
               Bucket_Listing.Consider
                 (Builder,
                  Ada.Strings.Unbounded.To_String (Bucket.Name),
                  Bucket.Created);
            end if;
         end loop;
         Page := Bucket_Listing.Finish (Builder);
         Result := Success;
      end List_Buckets;

      procedure Head_Bucket (Name : String; Result : out Status) is
      begin
         Result := (if Bucket_Index (Name) = 0 then Not_Found else Success);
      end Head_Bucket;

      procedure Delete_Bucket (Name : String; Result : out Status) is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         end if;
         for Index in 1 .. Highest_Object loop
            if Objects (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Bucket) = Name
            then
               Result := Bucket_Not_Empty;
               return;
            end if;
         end loop;
         for Upload of Uploads loop
            if Upload.Used
              and then Ada.Strings.Unbounded.To_String (Upload.Bucket) = Name
            then
               Result := Bucket_Not_Empty;
               return;
            end if;
         end loop;
         Buckets (Index) := (others => <>);
         Result := Success;
      end Delete_Bucket;

      procedure Reserve_Transient
        (Amount : Byte_Count; Result : out Status) is
      begin
         if Amount > Byte_Limit - Bytes
           or else Reserved_Bytes > Byte_Limit - Bytes - Amount
         then
            Result := Capacity_Exceeded;
         else
            Reserved_Bytes := Reserved_Bytes + Amount;
            Result := Success;
         end if;
      end Reserve_Transient;

      procedure Release_Transient (Amount : Byte_Count) is
      begin
         if Amount > Reserved_Bytes then
            raise Program_Error with "memory reservation underflow";
         end if;
         Reserved_Bytes := Reserved_Bytes - Amount;
      end Release_Transient;

      procedure Commit
        (Bucket : String;
         Key    : String;
         Data   : in out Owned_Bytes;
         Info   : Object_Information;
         Stored : out Object_Information;
         Result : out Status)
      is
         Index        : Natural := Object_Index (Bucket, Key);
         Existing     : Byte_Count := 0;
         Incoming     : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Reservation  : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Available    : Byte_Count;
      begin
         Stored := Empty_Info;
         if Bucket_Index (Bucket) = 0 then
            Result := Not_Found;
            return;
         end if;
         if Index /= 0 then
            Existing := Byte_Count (Objects (Index).Data.Capacity);
         else
            for Candidate in 1 .. Highest_Object loop
               if not Objects (Candidate).Used then
                  Index := Candidate;
                  exit;
               end if;
            end loop;
            if Index = 0 and then Highest_Object < Object_Limit then
               Highest_Object := Highest_Object + 1;
               Index := Highest_Object;
            elsif Index = 0 then
               Result := Capacity_Exceeded;
               return;
            end if;
         end if;

         Available := Byte_Limit - (Bytes - Existing);
         if Incoming > Available then
            Result := Capacity_Exceeded;
            return;
         end if;

         if Reservation > Reserved_Bytes then
            raise Program_Error with "unreserved memory object commit";
         end if;

         declare
            Stored_Bucket : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Bucket);
            Stored_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Key);
         begin
            Objects (Index).Bucket := Stored_Bucket;
            Objects (Index).Key := Stored_Key;
            Objects (Index).Info := Info;
            Stored := Info;
            Move (Objects (Index).Data, Data);
            Reserved_Bytes := Reserved_Bytes - Reservation;
            Bytes := Bytes - Existing + Incoming;
            Objects (Index).Used := True;
            Result := Success;
         end;
      end Commit;

      procedure Fetch
        (Bucket : String;
         Key    : String;
         Data   : out Owned_Bytes;
         Info   : out Object_Information;
         Result : out Status)
      is
         Index : constant Natural := Object_Index (Bucket, Key);
         Snapshot : Byte_Count := 0;
         Copied : Boolean := False;
      begin
         Data := (Ada.Finalization.Controlled with others => <>);
         Info := Empty_Info;
         if Index = 0 then
            Result := Not_Found;
         else
            Snapshot := Byte_Count (Objects (Index).Data.Length);
            if Snapshot > Byte_Limit - Bytes
              or else Reserved_Bytes > Byte_Limit - Bytes - Snapshot
            then
               Result := Capacity_Exceeded;
               return;
            end if;
            Reserved_Bytes := Reserved_Bytes + Snapshot;
            Data := Objects (Index).Data;
            Copied := True;
            Info := Objects (Index).Info;
            Result := Success;
         end if;
      exception
         when others =>
            if not Copied and then Snapshot > 0 then
               Reserved_Bytes := Reserved_Bytes - Snapshot;
            end if;
            raise;
      end Fetch;

      procedure Fetch_Range
        (Bucket    : String;
         Key       : String;
         Requested : Byte_Range;
         Data      : out Owned_Bytes;
         Info      : out Object_Information;
         Result    : out Status)
      is
         Index : constant Natural := Object_Index (Bucket, Key);
         Resolution : Range_Resolution;
         Snapshot : Byte_Count := 0;
         Copied : Boolean := False;
      begin
         Data := (Ada.Finalization.Controlled with others => <>);
         Info := Empty_Info;
         if Index = 0 then
            Result := Not_Found;
            return;
         end if;
         Info := Objects (Index).Info;
         if Requested.Kind not in Whole_Range | Bounded_Range then
            Result := Invalid_Request;
            return;
         elsif Requested.Kind = Bounded_Range
           and then
             (Requested.First > Requested.Last
              or else Requested.Last >= Info.Size)
         then
            Result := Invalid_Range;
            return;
         end if;
         Resolution := Resolve_Range (Info.Size, Requested);
         if Resolution.Kind = Unsatisfiable_Range then
            Result := Invalid_Range;
            return;
         elsif Resolution.Kind = Empty_Object_Range then
            Result := Success;
            return;
         end if;
         Snapshot := Resolution.Length;
         if Snapshot > Maximum_Multipart_Part_Size then
            Result := Entity_Too_Large;
            return;
         end if;
         if Snapshot > Byte_Limit - Bytes
           or else Reserved_Bytes > Byte_Limit - Bytes - Snapshot
         then
            Result := Capacity_Exceeded;
            return;
         end if;
         Reserved_Bytes := Reserved_Bytes + Snapshot;
         Reserve_Capacity (Data, Natural (Snapshot));
         Append
           (Data,
            Objects (Index).Data.Value
              (Ada.Streams.Stream_Element_Offset (Resolution.First + 1) ..
               Ada.Streams.Stream_Element_Offset (Resolution.Last + 1)));
         Copied := True;
         Result := Success;
      exception
         when others =>
            if not Copied and then Snapshot > 0 then
               Reserved_Bytes := Reserved_Bytes - Snapshot;
            end if;
            raise;
      end Fetch_Range;

      procedure Head
        (Bucket : String;
         Key    : String;
         Info   : out Object_Information;
         Result : out Status)
      is
         Index : constant Natural := Object_Index (Bucket, Key);
      begin
         Info := Empty_Info;
         if Index = 0 then
            Result := Not_Found;
         else
            Info := Objects (Index).Info;
            Result := Success;
         end if;
      end Head;

      procedure Delete
        (Bucket : String;
         Key    : String;
         Result : out Status)
      is
         Index : constant Natural := Object_Index (Bucket, Key);
      begin
         if Bucket_Index (Bucket) = 0 then
            Result := Bucket_Not_Found;
         elsif Index = 0 then
            Result := Not_Found;
         else
            Bytes := Bytes - Byte_Count (Objects (Index).Data.Capacity);
            Objects (Index) := (others => <>);
            while Highest_Object > 0
              and then not Objects (Highest_Object).Used
            loop
               Highest_Object := Highest_Object - 1;
            end loop;
            Result := Success;
         end if;
      end Delete;

      procedure List
        (Bucket  : String;
         Options : List_Options;
         Page    : out List_Page;
         Result  : out Status)
      is
         Builder : Listing.Builder;
      begin
         Page := (others => <>);
         if Bucket_Index (Bucket) = 0 then
            Result := Not_Found;
            return;
         end if;
         Listing.Initialize (Builder, Options);
         for Index in 1 .. Highest_Object loop
            if Objects (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Bucket) = Bucket
            then
               Listing.Consider
                 (Builder,
                  Ada.Strings.Unbounded.To_String (Objects (Index).Key),
                  Objects (Index).Info);
            end if;
         end loop;
         Page := Listing.Finish (Builder);
         Result := Success;
      end List;

      procedure Start_Multipart
        (Bucket    : String;
         Key       : String;
         Options   : Multipart_Options;
         Created   : Unix_Time;
         Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
         Result    : out Status)
      is
         Slot : Natural := 0;
      begin
         Upload_ID := Ada.Strings.Unbounded.Null_Unbounded_String;
         if Bucket_Index (Bucket) = 0 then
            Result := Not_Found;
            return;
         end if;
         for Index in Uploads'Range loop
            if not Uploads (Index).Used then
               Slot := Index;
               exit;
            end if;
         end loop;
         if Slot = 0 or else Next_Upload = Long_Long_Integer'Last then
            Result := Capacity_Exceeded;
            return;
         end if;
         Next_Upload := Next_Upload + 1;
         Upload_ID := Ada.Strings.Unbounded.To_Unbounded_String
           (GNAT.SHA256.Digest
              (Bucket & Character'Val (0) & Key & Character'Val (0) &
               Long_Long_Integer'Image (Next_Upload)));
         Uploads (Slot) :=
           (Used    => True,
            ID      => Upload_ID,
            Bucket  => Ada.Strings.Unbounded.To_Unbounded_String (Bucket),
            Key     => Ada.Strings.Unbounded.To_Unbounded_String (Key),
            Options => Options,
            Created => Created);
         Result := Success;
      end Start_Multipart;

      procedure List_Uploads
        (Bucket  : String;
         Options : List_Multipart_Uploads_Options;
         Page    : out Multipart_Upload_Page;
         Result  : out Status)
      is
         Builder : Multipart_Listing.Builder;
      begin
         Page := (others => <>);
         if Bucket_Index (Bucket) = 0 then
            Result := Not_Found;
            return;
         end if;
         Multipart_Listing.Initialize (Builder, Options);
         for Upload of Uploads loop
            if Upload.Used
              and then Ada.Strings.Unbounded.To_String (Upload.Bucket) =
                Bucket
            then
               Multipart_Listing.Consider
                 (Builder, Ada.Strings.Unbounded.To_String (Upload.Key),
                  Ada.Strings.Unbounded.To_String (Upload.ID),
                  Upload.Created, Upload.Options);
            end if;
         end loop;
         Page := Multipart_Listing.Finish (Builder);
         Result := Success;
      end List_Uploads;

      procedure Commit_Part
        (Bucket      : String;
         Key         : String;
         Upload_ID   : String;
         Part_Number : Multipart_Part_Number;
         Data        : in out Owned_Bytes;
         Info        : Object_Information;
         Stored      : out Object_Information;
         Result      : out Status)
      is
         Index     : Natural := Part_Index (Upload_ID, Part_Number);
         Existing  : Byte_Count := 0;
         Incoming  : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Reservation : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Available : Byte_Count;
      begin
         Stored := Empty_Info;
         if Upload_Index (Bucket, Key, Upload_ID) = 0 then
            Result := Not_Found;
            return;
         end if;
         if Index /= 0 then
            Existing := Byte_Count (Parts (Index).Data.Capacity);
         else
            for Candidate in 1 .. Highest_Part loop
               if not Parts (Candidate).Used then
                  Index := Candidate;
                  exit;
               end if;
            end loop;
            if Index = 0 and then Highest_Part < Object_Limit then
               Highest_Part := Highest_Part + 1;
               Index := Highest_Part;
            elsif Index = 0 then
               Result := Capacity_Exceeded;
               return;
            end if;
         end if;
         Available := Byte_Limit - (Bytes - Existing);
         if Incoming > Available then
            Result := Capacity_Exceeded;
            return;
         end if;
         if Reservation > Reserved_Bytes then
            raise Program_Error with "unreserved memory part commit";
         end if;
         declare
            Stored_Upload_ID : constant
              Ada.Strings.Unbounded.Unbounded_String :=
                Ada.Strings.Unbounded.To_Unbounded_String (Upload_ID);
         begin
            Parts (Index).Upload_ID := Stored_Upload_ID;
            Parts (Index).Number := Part_Number;
            Parts (Index).Info := Info;
            Stored := Info;
            Move (Parts (Index).Data, Data);
            Reserved_Bytes := Reserved_Bytes - Reservation;
            Bytes := Bytes - Existing + Incoming;
            Parts (Index).Used := True;
            Result := Success;
         end;
      end Commit_Part;

      procedure List_Parts
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Options   : List_Multipart_Parts_Options;
         Page      : out Multipart_Part_Page;
         Result    : out Status)
      is
         type Part_Index_Array is
           array (Multipart_Part_Number) of Natural;
         Index_By_Number : Part_Index_Array := (others => 0);
      begin
         Page := (others => <>);
         if Upload_Index (Bucket, Key, Upload_ID) = 0 then
            Result := Not_Found;
            return;
         elsif Options.Maximum = 0
           or else Options.After = Multipart_Part_Marker'Last
         then
            Result := Success;
            return;
         end if;
         for Index in 1 .. Highest_Part loop
            if Parts (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Parts (Index).Upload_ID) = Upload_ID
              and then Parts (Index).Number > Options.After
            then
               Index_By_Number (Parts (Index).Number) := Index;
            end if;
         end loop;
         for Number in
           Multipart_Part_Number (Options.After + 1) ..
             Multipart_Part_Number'Last
         loop
            if Index_By_Number (Number) /= 0 then
               if Page.Parts.Length <
                 Ada.Containers.Count_Type (Options.Maximum)
               then
                  declare
                     Part : constant Part_Slot :=
                       Parts (Index_By_Number (Number));
                  begin
                     Page.Parts.Append
                       (Listed_Multipart_Part'
                          (Number => Number, Info => Part.Info));
                  end;
               else
                  Page.Is_Truncated := True;
                  Page.Next_After :=
                    Multipart_Part_Marker (Page.Parts.Last_Element.Number);
                  exit;
               end if;
            end if;
         end loop;
         Result := Success;
      end List_Parts;

      procedure Complete_Multipart
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Completion : Multipart_Part_References;
         Modified  : Unix_Time;
         Info      : out Object_Information;
         Result    : out Status)
      is
         Upload_At : constant Natural :=
           Upload_Index (Bucket, Key, Upload_ID);
         Object_At : Natural := Object_Index (Bucket, Key);
         Previous  : Multipart_Part_Number := Multipart_Part_Number'First;
         First     : Boolean := True;
         Final_Data : Owned_Bytes;
         Final_Size : Byte_Count := 0;
         Staged_Size : Byte_Count := 0;
         Existing_Size : Byte_Count := 0;
         Hash : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
         Assembly_Reserved : Boolean := False;
      begin
         Info := Empty_Info;
         if Upload_At = 0 then
            Result := Not_Found;
            return;
         elsif Completion.Is_Empty then
            Result := Invalid_Request;
            return;
         end if;

         for Reference of Completion loop
            if not First and then Reference.Number <= Previous then
               Result := Invalid_Part_Order;
               return;
            end if;
            Previous := Reference.Number;
            First := False;
         end loop;
         Previous := Multipart_Part_Number'First;
         First := True;

         for Index in Completion.First_Index .. Completion.Last_Index loop
            declare
               Reference : constant Multipart_Part_Reference :=
                 Completion (Index);
               Stored_At : constant Natural :=
                 Part_Index (Upload_ID, Reference.Number);
            begin
               if Stored_At = 0
                 or else Ada.Strings.Unbounded.To_String
                   (Reference.Entity_Tag) /=
                     Ada.Strings.Unbounded.To_String
                       (Parts (Stored_At).Info.Entity_Tag)
               then
                  Result := Invalid_Part;
                  return;
               elsif Index /= Completion.Last_Index
                 and then Parts (Stored_At).Info.Size < 5 * 1_024 * 1_024
               then
                  Result := Entity_Too_Small;
                  return;
               end if;
               if Parts (Stored_At).Info.Size >
                 Byte_Count'Last - Final_Size
               then
                  Result := Capacity_Exceeded;
                  return;
               end if;
               Final_Size := Final_Size +
                 Parts (Stored_At).Info.Size;
               Include_Part_Digest
                 (Hash, Ada.Strings.Unbounded.To_String
                    (Parts (Stored_At).Info.Entity_Tag));
               Previous := Reference.Number;
               First := False;
            end;
         end loop;

         if Final_Size > Byte_Count (Natural'Last) then
            Result := Capacity_Exceeded;
            return;
         end if;
         if Final_Size > Byte_Limit - Bytes
           or else Reserved_Bytes > Byte_Limit - Bytes - Final_Size
         then
            Result := Capacity_Exceeded;
            return;
         end if;
         if Final_Size > 0 then
            Reserved_Bytes := Reserved_Bytes + Final_Size;
            Assembly_Reserved := True;
         end if;
         Reserve_Capacity (Final_Data, Natural (Final_Size));
         for Reference of Completion loop
            declare
               Stored_At : constant Natural :=
                 Part_Index (Upload_ID, Reference.Number);
            begin
               Append (Final_Data, Parts (Stored_At).Data);
            end;
         end loop;

         if Object_At /= 0 then
            Existing_Size := Byte_Count (Objects (Object_At).Data.Capacity);
         else
            for Candidate in 1 .. Highest_Object loop
               if not Objects (Candidate).Used then
                  Object_At := Candidate;
                  exit;
               end if;
            end loop;
            if Object_At = 0 and then Highest_Object < Object_Limit then
               Highest_Object := Highest_Object + 1;
               Object_At := Highest_Object;
            elsif Object_At = 0 then
               Final_Data :=
                 (Ada.Finalization.Controlled with others => <>);
               if Assembly_Reserved then
                  Reserved_Bytes := Reserved_Bytes - Final_Size;
                  Assembly_Reserved := False;
               end if;
               Result := Capacity_Exceeded;
               return;
            end if;
         end if;
         for Index in 1 .. Highest_Part loop
            if Parts (Index).Used
              and then Parts (Index).Upload_ID = Upload_ID
            then
               Staged_Size := Staged_Size +
                 Byte_Count (Parts (Index).Data.Capacity);
            end if;
         end loop;

         declare
            Completed_Info : constant Object_Information :=
              (Size         => Final_Size,
               Modified     => Modified,
               Entity_Tag   => Ada.Strings.Unbounded.To_Unbounded_String
                 (GNAT.MD5.Digest (Hash) & "-" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (Completion.Length)),
                     Ada.Strings.Both)),
               Content_Type => Uploads (Upload_At).Options.Content_Type,
               Version      => Ada.Strings.Unbounded.Null_Unbounded_String);
            Stored_Bucket : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Bucket);
            Stored_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Key);
         begin
            --  Finish every allocating metadata operation before consuming
            --  the staged upload or publishing its assembled payload.
            Objects (Object_At).Bucket := Stored_Bucket;
            Objects (Object_At).Key := Stored_Key;
            Objects (Object_At).Info := Completed_Info;
            Info := Completed_Info;

            Bytes := Bytes - Staged_Size - Existing_Size + Final_Size;
            for Index in 1 .. Highest_Part loop
               if Parts (Index).Used
                 and then Parts (Index).Upload_ID = Upload_ID
               then
                  Parts (Index) := (others => <>);
               end if;
            end loop;
            while Highest_Part > 0
              and then not Parts (Highest_Part).Used
            loop
               Highest_Part := Highest_Part - 1;
            end loop;
            Uploads (Upload_At) := (others => <>);
            Move (Objects (Object_At).Data, Final_Data);
            if Assembly_Reserved then
               Reserved_Bytes := Reserved_Bytes - Final_Size;
               Assembly_Reserved := False;
            end if;
            Objects (Object_At).Used := True;
            Result := Success;
         end;
      exception
         when others =>
            if Assembly_Reserved then
               Reserved_Bytes := Reserved_Bytes - Final_Size;
            end if;
            raise;
      end Complete_Multipart;

      procedure Abort_Multipart
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Result    : out Status)
      is
         Upload_At : constant Natural :=
           Upload_Index (Bucket, Key, Upload_ID);
      begin
         if Upload_At = 0 then
            Result := Not_Found;
            return;
         end if;
         for Index in 1 .. Highest_Part loop
            if Parts (Index).Used
              and then Parts (Index).Upload_ID = Upload_ID
            then
               Bytes := Bytes - Byte_Count (Parts (Index).Data.Capacity);
               Parts (Index) := (others => <>);
            end if;
         end loop;
         while Highest_Part > 0
           and then not Parts (Highest_Part).Used
         loop
            Highest_Part := Highest_Part - 1;
         end loop;
         Uploads (Upload_At) := (others => <>);
         Result := Success;
      end Abort_Multipart;

      function Used_Bytes return Byte_Count is (Bytes + Reserved_Bytes);
   end Memory_State;

   procedure Reserve_Buffer_Capacity
     (State  : in out Memory_State;
      Data   : in out Owned_Bytes;
      Target : Natural;
      Result : out Status)
   is
      Previous : constant Byte_Count := Byte_Count (Data.Capacity);
      Replacement : constant Byte_Count := Byte_Count (Target);
   begin
      if Target <= Data.Capacity then
         Result := Success;
         return;
      end if;
      State.Reserve_Transient (Replacement, Result);
      if Result /= Success then
         return;
      end if;
      begin
         Reserve_Capacity (Data, Target);
      exception
         when others =>
            State.Release_Transient (Replacement);
            raise;
      end;
      if Previous > 0 then
         State.Release_Transient (Previous);
      end if;
   end Reserve_Buffer_Capacity;

   procedure Release_Buffer
     (State : in out Memory_State; Data : in out Owned_Bytes)
   is
      Reserved : constant Byte_Count := Byte_Count (Data.Capacity);
   begin
      if Reserved > 0 then
         Data := (Ada.Finalization.Controlled with others => <>);
         State.Release_Transient (Reserved);
      end if;
   end Release_Buffer;

   overriding procedure Create_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Create_Bucket (Bucket, Current_Unix_Time, Result);
      end if;
   end Create_Bucket;

   overriding procedure List_Buckets
     (Item     : in out Store;
      Options  : List_Buckets_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out Bucket_Page;
      Result   : out Status)
   is
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      Item.State.List_Buckets (Options, Page, Result);
   end List_Buckets;

   overriding procedure Head_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Head_Bucket (Bucket, Result);
      end if;
   end Head_Bucket;

   overriding procedure Delete_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Delete_Bucket (Bucket, Result);
      end if;
   end Delete_Bucket;

   overriding procedure Put_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status)
   is
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
      Last     : Ada.Streams.Stream_Element_Offset;
      Finished : Boolean := False;
      Data     : Owned_Bytes;
      Declared : constant Source_Length := Source.Declared_Length;
      Stored   : Object_Information;
      Hash     : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
         return;
      end if;
      if Declared.Kind = Known
        and then (Declared.Bytes > Item.Byte_Capacity
                  or else Declared.Bytes > Byte_Count (Natural'Last))
      then
         Result := Capacity_Exceeded;
         return;
      end if;
      if Declared.Kind = Known then
         Reserve_Buffer_Capacity
           (Item.State, Data, Natural (Declared.Bytes), Result);
         if Result /= Success then
            return;
         end if;
      end if;

      while not Finished loop
         Check_Context (Token, Deadline);
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         if Last < Buffer'First - 1 or else Last > Buffer'Last then
            Result := Invalid_Request;
            Release_Buffer (Item.State, Data);
            return;
         end if;
         if Last >= Buffer'First then
            declare
               Chunk_Length : constant Byte_Count :=
                 Byte_Count (Last - Buffer'First + 1);
            begin
               if Chunk_Length > Item.Byte_Capacity
                 or else Byte_Count (Data.Length)
                   > Item.Byte_Capacity - Chunk_Length
                 or else Chunk_Length >
                   Byte_Count (Natural'Last - Data.Length)
               then
                  Result := Capacity_Exceeded;
                  Release_Buffer (Item.State, Data);
                  return;
               end if;
               declare
                  Required : constant Natural :=
                    Data.Length + Natural (Chunk_Length);
                  Target : constant Natural :=
                    Growth_Capacity (Data, Required);
               begin
                  Reserve_Buffer_Capacity
                    (Item.State, Data, Target, Result);
                  if Result = Capacity_Exceeded and then Target > Required
                  then
                     Reserve_Buffer_Capacity
                       (Item.State, Data, Required, Result);
                  end if;
                  if Result /= Success then
                     Release_Buffer (Item.State, Data);
                     return;
                  end if;
               end;
            end;
            GNAT.MD5.Update (Hash, Buffer (Buffer'First .. Last));
            Append (Data, Buffer (Buffer'First .. Last));
         elsif not Finished then
            Result := Invalid_Request;
            Release_Buffer (Item.State, Data);
            return;
         end if;
      end loop;

      if Declared.Kind = Known
        and then Declared.Bytes /= Byte_Count (Data.Length)
      then
         Result := Invalid_Request;
         Release_Buffer (Item.State, Data);
         return;
      end if;

      Stored :=
        (Size         => Byte_Count (Data.Length),
         Modified     => Current_Unix_Time,
         Entity_Tag   =>
           (if Ada.Strings.Unbounded.Length (Options.Entity_Tag) > 0
            then Options.Entity_Tag
            else Ada.Strings.Unbounded.To_Unbounded_String
              (GNAT.MD5.Digest (Hash))),
         Content_Type => Options.Content_Type,
         Version      => Ada.Strings.Unbounded.Null_Unbounded_String);
      Item.State.Commit
        (Bucket => Bucket,
         Key    => Key,
         Data   => Data,
         Info   => Stored,
         Stored => Info,
         Result => Result);
      Release_Buffer (Item.State, Data);
   exception
      when others =>
         Release_Buffer (Item.State, Data);
         raise;
   end Put_Object;

   overriding procedure Copy_Object
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Copy_Options;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status)
   is
      type Snapshot_Source is limited new Byte_Source with record
         Data     : access constant Owned_Bytes;
         Position : Natural := 0;
      end record;

      overriding function Declared_Length
        (Source : Snapshot_Source) return Source_Length is
        (Kind => Known, Bytes => Byte_Count (Source.Data.Length));

      overriding procedure Read
        (Source   : in out Snapshot_Source;
         Buffer   : out Ada.Streams.Stream_Element_Array;
         Last     : out Ada.Streams.Stream_Element_Offset;
         Finished : out Boolean;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time)
      is
         Remaining : constant Natural := Source.Data.Length - Source.Position;
         Count     : constant Natural :=
           Natural'Min (Remaining, Natural (Buffer'Length));
      begin
         Check_Context (Token, Deadline);
         if Count = 0 then
            Last := Buffer'First - 1;
         else
            for Offset in 0 .. Count - 1 loop
               Buffer
                 (Buffer'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
                   Element (Source.Data.all, Source.Position + Offset + 1);
            end loop;
            Source.Position := Source.Position + Count;
            Last := Buffer'First +
              Ada.Streams.Stream_Element_Offset (Count) - 1;
         end if;
         Finished := Source.Position = Source.Data.Length;
      end Read;

      Snapshot      : aliased Owned_Bytes;
      Source_Info   : Object_Information;
      Put_Options_Value : Put_Options;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Source_Bucket)
        or else not Valid_Object_Key (Source_Key)
        or else not Valid_Bucket_Name (Destination_Bucket)
        or else not Valid_Object_Key (Destination_Key)
      then
         Result := Invalid_Request;
         return;
      elsif Source_Bucket = Destination_Bucket
        and then Source_Key = Destination_Key
        and then Options.Metadata_Directive = Copy_Metadata
      then
         Result := Invalid_Request;
         return;
      end if;

      Item.State.Fetch
        (Source_Bucket, Source_Key, Snapshot, Source_Info, Result);
      if Result = Not_Found then
         Result := Source_Not_Found;
         return;
      elsif Result /= Success then
         return;
      elsif not Copy_Conditions_Accept
        (Options.Conditions,
         Ada.Strings.Unbounded.To_String (Source_Info.Entity_Tag))
      then
         Result := Precondition_Failed;
         Release_Buffer (Item.State, Snapshot);
         return;
      end if;

      Put_Options_Value :=
        (Entity_Tag   => Ada.Strings.Unbounded.Null_Unbounded_String,
         Content_Type =>
           (if Options.Metadata_Directive = Copy_Metadata
            then Source_Info.Content_Type
            else Options.Content_Type));
      declare
         Source : Snapshot_Source :=
           (Data => Snapshot'Access, Position => 0);
      begin
         Item.Put_Object
           (Destination_Bucket, Destination_Key, Source,
            Put_Options_Value, Token, Deadline, Info, Result);
      end;
      Release_Buffer (Item.State, Snapshot);
   exception
      when others =>
         Release_Buffer (Item.State, Snapshot);
         raise;
   end Copy_Object;

   overriding procedure Head_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Info := Empty_Info;
         Result := Invalid_Request;
      else
         Item.State.Head (Bucket, Key, Info, Result);
      end if;
   end Head_Object;

   overriding procedure Get_Object
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Requested : Byte_Range;
      Sink      : in out Byte_Sink'Class;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions)
   is
      Data       : Owned_Bytes;
      Resolution : Range_Resolution;
      Send_Count : Byte_Count := 0;
      First      : Byte_Count := 0;
      Sent       : Byte_Count := 0;
      Buffer     : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Info := Empty_Info;
         Result := Invalid_Request;
         return;
      end if;
      Item.State.Fetch (Bucket, Key, Data, Info, Result);
      if Result /= Success then
         return;
      end if;

      Result := Evaluate_Read_Conditions
        (Conditions, Ada.Strings.Unbounded.To_String (Info.Entity_Tag),
         Info.Modified);
      if Result /= Success then
         Release_Buffer (Item.State, Data);
         return;
      end if;

      Resolution := Resolve_Range (Info.Size, Requested);
      if Resolution.Kind = Unsatisfiable_Range then
         Result := Invalid_Range;
         Release_Buffer (Item.State, Data);
         return;
      elsif Resolution.Kind = Empty_Object_Range then
         Sink.Begin_Object
           (Info, 0, 0, False, Token, Deadline);
         Result := Success;
         Release_Buffer (Item.State, Data);
         return;
      end if;
      First := Resolution.First;
      Send_Count := Resolution.Length;
      Sink.Begin_Object
        (Info,
         First,
         Send_Count,
         Requested.Kind /= Whole_Range,
         Token,
         Deadline);
      while Sent < Send_Count loop
         declare
            Chunk_Length : constant Natural := Natural
              (Byte_Count'Min
                 (Send_Count - Sent, Byte_Count (Buffer'Length)));
         begin
            for Offset in 0 .. Chunk_Length - 1 loop
               Buffer
                 (Buffer'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
                   Element
                      (Data,
                      Positive
                        (First + Sent + Byte_Count (Offset) + 1));
            end loop;
            Check_Context (Token, Deadline);
            Sink.Write
              (Buffer
                 (Buffer'First ..
                    Buffer'First
                      + Ada.Streams.Stream_Element_Offset (Chunk_Length) - 1),
               Token,
               Deadline);
            Sent := Sent + Byte_Count (Chunk_Length);
         end;
      end loop;
      Result := Success;
      Release_Buffer (Item.State, Data);
   exception
      when others =>
         Release_Buffer (Item.State, Data);
         raise;
   end Get_Object;

   overriding procedure Delete_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
      else
         Item.State.Delete (Bucket, Key, Result);
      end if;
   end Delete_Object;

   overriding procedure List_Objects
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Page;
      Result   : out Status)
   is
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.List (Bucket, Options, Page, Result);
      end if;
      Check_Context (Token, Deadline);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Page := (others => <>);
         Result := Backend_Unavailable;
   end List_Objects;

   overriding procedure Create_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Options   : Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
      Result    : out Status)
   is
   begin
      Upload_ID := Ada.Strings.Unbounded.Null_Unbounded_String;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
      else
         Item.State.Start_Multipart
           (Bucket, Key, Options, Current_Unix_Time, Upload_ID, Result);
      end if;
   end Create_Multipart_Upload;

   overriding procedure Put_Multipart_Part
     (Item        : in out Store;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status)
   is
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
      Last     : Ada.Streams.Stream_Element_Offset;
      Finished : Boolean := False;
      Data     : Owned_Bytes;
      Declared : Source_Length := (Kind => Unknown);
      Stored   : Object_Information;
      Hash     : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;
      Declared := Source.Declared_Length;
      if Declared.Kind = Known
        and then Declared.Bytes > Maximum_Multipart_Part_Size
      then
         Result := Entity_Too_Large;
         return;
      elsif Declared.Kind = Known
        and then (Declared.Bytes > Item.Byte_Capacity
                  or else Declared.Bytes > Byte_Count (Natural'Last))
      then
         Result := Capacity_Exceeded;
         return;
      end if;
      if Declared.Kind = Known then
         Reserve_Buffer_Capacity
           (Item.State, Data, Natural (Declared.Bytes), Result);
         if Result /= Success then
            return;
         end if;
      end if;
      while not Finished loop
         Check_Context (Token, Deadline);
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         if Last < Buffer'First - 1 or else Last > Buffer'Last then
            Result := Invalid_Request;
            Release_Buffer (Item.State, Data);
            return;
         elsif Last >= Buffer'First then
            declare
               Count : constant Byte_Count :=
                 Byte_Count (Last - Buffer'First + 1);
            begin
               if Count > Maximum_Multipart_Part_Size
                 or else Byte_Count (Data.Length) >
                   Maximum_Multipart_Part_Size - Count
               then
                  Result := Entity_Too_Large;
                  Release_Buffer (Item.State, Data);
                  return;
               elsif Count > Item.Byte_Capacity
                 or else Byte_Count (Data.Length) >
                   Item.Byte_Capacity - Count
                 or else Count > Byte_Count (Natural'Last - Data.Length)
               then
                  Result := Capacity_Exceeded;
                  Release_Buffer (Item.State, Data);
                  return;
               end if;
               declare
                  Required : constant Natural :=
                    Data.Length + Natural (Count);
                  Target : constant Natural :=
                    Growth_Capacity (Data, Required);
               begin
                  Reserve_Buffer_Capacity
                    (Item.State, Data, Target, Result);
                  if Result = Capacity_Exceeded and then Target > Required
                  then
                     Reserve_Buffer_Capacity
                       (Item.State, Data, Required, Result);
                  end if;
                  if Result /= Success then
                     Release_Buffer (Item.State, Data);
                     return;
                  end if;
               end;
               Append (Data, Buffer (Buffer'First .. Last));
               GNAT.MD5.Update (Hash, Buffer (Buffer'First .. Last));
            end;
         elsif not Finished then
            Result := Invalid_Request;
            Release_Buffer (Item.State, Data);
            return;
         end if;
      end loop;
      if Declared.Kind = Known
        and then Declared.Bytes /= Byte_Count (Data.Length)
      then
         Result := Invalid_Request;
         Release_Buffer (Item.State, Data);
         return;
      end if;
      Stored :=
        (Size         => Byte_Count (Data.Length),
         Modified     => Current_Unix_Time,
         Entity_Tag   => Ada.Strings.Unbounded.To_Unbounded_String
           (GNAT.MD5.Digest (Hash)),
         Content_Type => Ada.Strings.Unbounded.Null_Unbounded_String,
         Version      => Ada.Strings.Unbounded.Null_Unbounded_String);
      Item.State.Commit_Part
        (Bucket      => Bucket,
         Key         => Key,
         Upload_ID   => Upload_ID,
         Part_Number => Part_Number,
         Data        => Data,
         Info        => Stored,
         Stored      => Info,
         Result      => Result);
      Release_Buffer (Item.State, Data);
   exception
      when others =>
         Release_Buffer (Item.State, Data);
         raise;
   end Put_Multipart_Part;

   overriding procedure List_Multipart_Parts
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : List_Multipart_Parts_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Part_Page;
      Result    : out Status)
   is
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
      else
         Item.State.List_Parts
           (Bucket, Key, Upload_ID, Options, Page, Result);
      end if;
   end List_Multipart_Parts;

   overriding procedure List_Multipart_Uploads
     (Item      : in out Store;
      Bucket    : String;
      Options   : List_Multipart_Uploads_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Upload_Page;
      Result    : out Status)
   is
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.List_Uploads (Bucket, Options, Page, Result);
      end if;
   end List_Multipart_Uploads;

   overriding procedure Copy_Multipart_Part
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Upload_ID          : String;
      Part_Number        : Multipart_Part_Number;
      Requested          : Byte_Range;
      Conditions         : Copy_Conditions;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status)
   is
      type Snapshot_Source is limited new Byte_Source with record
         Data        : access constant Owned_Bytes;
         Position    : Natural := 0;
         End_Position : Natural := 0;
      end record;

      overriding function Declared_Length
        (Source : Snapshot_Source) return Source_Length is
        (Kind => Known,
         Bytes => Byte_Count (Source.End_Position - Source.Position));

      overriding procedure Read
        (Source   : in out Snapshot_Source;
         Buffer   : out Ada.Streams.Stream_Element_Array;
         Last     : out Ada.Streams.Stream_Element_Offset;
         Finished : out Boolean;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time)
      is
         Remaining : constant Natural :=
           Source.End_Position - Source.Position;
         Count : constant Natural :=
           Natural'Min (Remaining, Natural (Buffer'Length));
      begin
         Check_Context (Token, Deadline);
         if Count = 0 then
            Last := Buffer'First - 1;
         else
            for Offset in 0 .. Count - 1 loop
               Buffer
                 (Buffer'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
                   Element (Source.Data.all, Source.Position + Offset + 1);
            end loop;
            Source.Position := Source.Position + Count;
            Last := Buffer'First +
              Ada.Streams.Stream_Element_Offset (Count) - 1;
         end if;
         Finished := Source.Position = Source.End_Position;
      end Read;

      Snapshot    : aliased Owned_Bytes;
      Source_Info : Object_Information;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Source_Bucket)
        or else not Valid_Object_Key (Source_Key)
        or else not Valid_Bucket_Name (Destination_Bucket)
        or else not Valid_Object_Key (Destination_Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;

      Item.State.Fetch_Range
        (Source_Bucket, Source_Key, Requested,
         Snapshot, Source_Info, Result);
      if Result = Not_Found then
         Result := Source_Not_Found;
         return;
      elsif Result /= Success then
         return;
      elsif not Copy_Conditions_Accept
        (Conditions,
         Ada.Strings.Unbounded.To_String (Source_Info.Entity_Tag))
      then
         Result := Precondition_Failed;
         Release_Buffer (Item.State, Snapshot);
         return;
      end if;
      declare
         Source : Snapshot_Source :=
           (Data         => Snapshot'Access,
            Position     => 0,
            End_Position => Snapshot.Length);
      begin
         Item.Put_Multipart_Part
           (Destination_Bucket, Destination_Key, Upload_ID, Part_Number,
            Source, Token, Deadline, Info, Result);
      end;
      Release_Buffer (Item.State, Snapshot);
   exception
      when others =>
         Release_Buffer (Item.State, Snapshot);
         raise;
   end Copy_Multipart_Part;

   overriding procedure Complete_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status)
   is
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.State.Complete_Multipart
        (Bucket, Key, Upload_ID, Parts, Current_Unix_Time, Info, Result);
   end Complete_Multipart_Upload;

   overriding procedure Abort_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Result    : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.State.Abort_Multipart (Bucket, Key, Upload_ID, Result);
   end Abort_Multipart_Upload;

   function Bytes_Used (Item : Store) return Byte_Count is
     (Item.State.Used_Bytes);

end Flyology.Object_Storage.Backends.Memory;
