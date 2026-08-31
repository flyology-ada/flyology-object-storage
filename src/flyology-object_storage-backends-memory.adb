with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Containers.Vectors;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;
with Flyology.IO;
with Flyology.Object_Storage.Backends.Bucket_Listing;
with Flyology.Object_Storage.Backends.Listing;
with Flyology.Object_Storage.Backends.Multipart_Listing;
with Flyology.Object_Storage.Checksum_Engine;
with GNAT.MD5;
with GNAT.SHA256;

package body Flyology.Object_Storage.Backends.Memory is

   function Canonical
     (Value : Optional_Configuration_Boolean)
      return Optional_Configuration_Boolean is
     (Is_Set => Value.Is_Set, Value => Value.Is_Set and then Value.Value);

   function Canonical
     (Value : Bucket_Public_Access_Block_Configuration)
      return Bucket_Public_Access_Block_Configuration is
     (Block_Public_ACLs       => Canonical (Value.Block_Public_ACLs),
      Ignore_Public_ACLs      => Canonical (Value.Ignore_Public_ACLs),
      Block_Public_Policy     => Canonical (Value.Block_Public_Policy),
      Restrict_Public_Buckets =>
        Canonical (Value.Restrict_Public_Buckets));

   use type Ada.Calendar.Time;
   use type Ada.Real_Time.Time;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Strings.Unbounded.Unbounded_String;
   package Checksum_Engine renames
     Flyology.Object_Storage.Checksum_Engine;

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
         Selected : constant Natural :=
           Selected_Generation_Index
             (Bucket, Key, Current_Version_Selector);
      begin
         return
           (if Selected /= 0 and then not Objects (Selected).Is_Delete_Marker
            then Selected else 0);
      end Object_Index;

      function Selected_Generation_Index
        (Bucket : String; Key : String; Selector : Version_Selector)
         return Natural
      is
         Selected : Natural := 0;
         ID : constant String :=
           Ada.Strings.Unbounded.To_String (Selector.ID);
      begin
         for Index in 1 .. Highest_Object loop
            if Objects (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Bucket) = Bucket
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Key) = Key
              and then
                (Selector.Kind = Current_Version
                 or else
                   (if Selector.Kind = Null_Version
                    then Objects (Index).Is_Null_Version
                    else not Objects (Index).Is_Null_Version
                      and then Ada.Strings.Unbounded.To_String
                        (Objects (Index).Info.Version) = ID))
            then
               if Selected = 0
                 or else Objects (Index).Publication >
                   Objects (Selected).Publication
               then
                  Selected := Index;
               end if;
            end if;
         end loop;
         return Selected;
      end Selected_Generation_Index;

      function Selected_Object_Index
        (Bucket : String; Key : String; Selector : Version_Selector)
         return Natural
      is
         Selected : constant Natural :=
           Selected_Generation_Index (Bucket, Key, Selector);
      begin
         return
           (if Selected /= 0
              and then not Objects (Selected).Is_Delete_Marker
            then Selected else 0);
      end Selected_Object_Index;

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
               Buckets (Index).Tags.Clear;
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

      procedure Put_Bucket_Versioning
        (Name          : String;
         Configuration : Bucket_Versioning_Configuration;
         Result        : out Status;
         MFA_Validated : Boolean := False)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         elsif not MFA_Validated
           and then
             (Buckets (Index).Versioning.MFA_Delete = MFA_Delete_Enabled
              or else Configuration.MFA_Delete /= MFA_Delete_Unconfigured)
         then
            Result := Access_Denied;
         else
            Buckets (Index).Versioning :=
              Merge_Bucket_Versioning
                (Buckets (Index).Versioning, Configuration);
            Result := Success;
         end if;
      end Put_Bucket_Versioning;

      procedure Get_Bucket_Versioning
        (Name          : String;
         Configuration : out Bucket_Versioning_Configuration;
         Result        : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Configuration := (others => <>);
         if Index = 0 then
            Result := Not_Found;
         else
            Configuration := Buckets (Index).Versioning;
            Result := Success;
         end if;
      end Get_Bucket_Versioning;

      procedure Put_Bucket_ABAC
        (Name : String; Value : Bucket_ABAC_Status; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).ABAC := Value;
            Result := Success;
         end if;
      end Put_Bucket_ABAC;

      procedure Get_Bucket_ABAC
        (Name : String; Value : out Bucket_ABAC_Status; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Value := Bucket_ABAC_Disabled;
         if Index = 0 then
            Result := Not_Found;
         else
            Value := Buckets (Index).ABAC;
            Result := Success;
         end if;
      end Get_Bucket_ABAC;

      procedure Put_Bucket_Acceleration
        (Name : String;
         Value : Bucket_Acceleration_Status;
         Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).Acceleration := Value;
            Result := Success;
         end if;
      end Put_Bucket_Acceleration;

      procedure Get_Bucket_Acceleration
        (Name : String;
         Value : out Bucket_Acceleration_Status;
         Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Value := Bucket_Acceleration_Unconfigured;
         if Index = 0 then
            Result := Not_Found;
         else
            Value := Buckets (Index).Acceleration;
            Result := Success;
         end if;
      end Get_Bucket_Acceleration;

      procedure Put_Bucket_Request_Payment
        (Name : String;
         Value : Bucket_Request_Payment_Status;
         Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).Request_Payment := Value;
            Result := Success;
         end if;
      end Put_Bucket_Request_Payment;

      procedure Get_Bucket_Request_Payment
        (Name : String;
         Value : out Bucket_Request_Payment_Status;
         Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Value := Bucket_Owner_Pays;
         if Index = 0 then
            Result := Not_Found;
         else
            Value := Buckets (Index).Request_Payment;
            Result := Success;
         end if;
      end Get_Bucket_Request_Payment;

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
         Bytes := Bytes - Byte_Count
           (Ada.Strings.Unbounded.Length (Buckets (Index).Policy)) -
           Byte_Count
             (Ada.Strings.Unbounded.Length
                (Buckets (Index).CORS_Document)) -
           Byte_Count
             (Ada.Strings.Unbounded.Length
                (Buckets (Index).Encryption_Document)) -
           Byte_Count
             (Ada.Strings.Unbounded.Length
                (Buckets (Index).Ownership_Controls_Document)) -
           Byte_Count
             (Ada.Strings.Unbounded.Length
                (Buckets (Index).Configuration_Documents
                   (Lifecycle_Configuration))) -
           Byte_Count
             (Ada.Strings.Unbounded.Length
                (Buckets (Index).Configuration_Documents
                   (Logging_Configuration)));
         Bytes := Bytes - Byte_Count
           (Ada.Strings.Unbounded.Length
              (Buckets (Index).Configuration_Metadata
                 (Lifecycle_Configuration)));
         for Kind in Named_Configuration_Kind loop
            for Position in
              Buckets (Index).Named_Configurations (Kind).Iterate
            loop
               Bytes := Bytes - Byte_Count
                 (Named_Configuration_Maps.Key (Position)'Length) -
                 Byte_Count
                   (Ada.Strings.Unbounded.Length
                      (Named_Configuration_Maps.Element (Position)));
            end loop;
         end loop;
         Buckets (Index) := (others => <>);
         Result := Success;
      end Delete_Bucket;

      procedure Put_Bucket_Tags
        (Name : String; Value : Tags.Tag_Set; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).Tags := Value;
            Result := Success;
         end if;
      end Put_Bucket_Tags;

      procedure Get_Bucket_Tags
        (Name : String; Value : out Tags.Tag_Set; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Value.Clear;
         if Index = 0 then
            Result := Not_Found;
         elsif Buckets (Index).Tags.Is_Empty then
            Result := Tag_Set_Not_Found;
         else
            Value := Buckets (Index).Tags;
            Result := Success;
         end if;
      end Get_Bucket_Tags;

      procedure Delete_Bucket_Tags
        (Name : String; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).Tags.Clear;
            Result := Success;
         end if;
      end Delete_Bucket_Tags;

      procedure Put_Bucket_CORS
        (Name : String; Document : String; Result : out Status)
      is
         Index    : constant Natural := Bucket_Index (Name);
         Incoming : constant Byte_Count := Byte_Count (Document'Length);
         Existing : Byte_Count := 0;
         Base     : Byte_Count;
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         elsif not Valid_Bucket_CORS_Document (Document) then
            Result := Entity_Too_Large;
            return;
         end if;
         Existing := Byte_Count
           (Ada.Strings.Unbounded.Length
              (Buckets (Index).CORS_Document));
         Base := Bytes - Existing;
         if Incoming > Byte_Limit - Base
           or else Reserved_Bytes > Byte_Limit - Base - Incoming
         then
            Result := Capacity_Exceeded;
         else
            Buckets (Index).CORS_Document :=
              Ada.Strings.Unbounded.To_Unbounded_String (Document);
            Buckets (Index).CORS_Configured := True;
            Bytes := Base + Incoming;
            Result := Success;
         end if;
      end Put_Bucket_CORS;

      procedure Get_Bucket_CORS
        (Name       : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Document := Ada.Strings.Unbounded.Null_Unbounded_String;
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         else
            Document := Buckets (Index).CORS_Document;
            Configured := Buckets (Index).CORS_Configured;
            Result := Success;
         end if;
      end Get_Bucket_CORS;

      procedure Delete_Bucket_CORS
        (Name : String; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Bytes := Bytes - Byte_Count
              (Ada.Strings.Unbounded.Length
                 (Buckets (Index).CORS_Document));
            Buckets (Index).CORS_Document :=
              Ada.Strings.Unbounded.Null_Unbounded_String;
            Buckets (Index).CORS_Configured := False;
            Result := Success;
         end if;
      end Delete_Bucket_CORS;

      procedure Put_Bucket_Encryption
        (Name : String; Document : String; Result : out Status)
      is
         Index    : constant Natural := Bucket_Index (Name);
         Incoming : constant Byte_Count := Byte_Count (Document'Length);
         Existing : Byte_Count := 0;
         Base     : Byte_Count;
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         elsif not Valid_Bucket_Encryption_Document (Document) then
            Result := Entity_Too_Large;
            return;
         end if;
         Existing := Byte_Count
           (Ada.Strings.Unbounded.Length
              (Buckets (Index).Encryption_Document));
         Base := Bytes - Existing;
         if Incoming > Byte_Limit - Base
           or else Reserved_Bytes > Byte_Limit - Base - Incoming
         then
            Result := Capacity_Exceeded;
         else
            Buckets (Index).Encryption_Document :=
              Ada.Strings.Unbounded.To_Unbounded_String (Document);
            Buckets (Index).Encryption_Configured := True;
            Bytes := Base + Incoming;
            Result := Success;
         end if;
      end Put_Bucket_Encryption;

      procedure Get_Bucket_Encryption
        (Name       : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Document := Ada.Strings.Unbounded.Null_Unbounded_String;
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         else
            Document := Buckets (Index).Encryption_Document;
            Configured := Buckets (Index).Encryption_Configured;
            Result := Success;
         end if;
      end Get_Bucket_Encryption;

      procedure Delete_Bucket_Encryption
        (Name : String; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Bytes := Bytes - Byte_Count
              (Ada.Strings.Unbounded.Length
                 (Buckets (Index).Encryption_Document));
            Buckets (Index).Encryption_Document :=
              Ada.Strings.Unbounded.Null_Unbounded_String;
            Buckets (Index).Encryption_Configured := False;
            Result := Success;
         end if;
      end Delete_Bucket_Encryption;

      procedure Put_Bucket_Ownership_Controls
        (Name : String; Document : String; Result : out Status)
      is
         Index    : constant Natural := Bucket_Index (Name);
         Incoming : constant Byte_Count := Byte_Count (Document'Length);
         Existing : Byte_Count := 0;
         Base     : Byte_Count;
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         elsif not Valid_Bucket_Ownership_Controls_Document (Document) then
            Result := Entity_Too_Large;
            return;
         end if;
         Existing := Byte_Count
           (Ada.Strings.Unbounded.Length
              (Buckets (Index).Ownership_Controls_Document));
         Base := Bytes - Existing;
         if Incoming > Byte_Limit - Base
           or else Reserved_Bytes > Byte_Limit - Base - Incoming
         then
            Result := Capacity_Exceeded;
         else
            Buckets (Index).Ownership_Controls_Document :=
              Ada.Strings.Unbounded.To_Unbounded_String (Document);
            Buckets (Index).Ownership_Controls_Configured := True;
            Bytes := Base + Incoming;
            Result := Success;
         end if;
      end Put_Bucket_Ownership_Controls;

      procedure Get_Bucket_Ownership_Controls
        (Name       : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Document := Ada.Strings.Unbounded.Null_Unbounded_String;
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         else
            Document := Buckets (Index).Ownership_Controls_Document;
            Configured := Buckets (Index).Ownership_Controls_Configured;
            Result := Success;
         end if;
      end Get_Bucket_Ownership_Controls;

      procedure Delete_Bucket_Ownership_Controls
        (Name : String; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Bytes := Bytes - Byte_Count
              (Ada.Strings.Unbounded.Length
                 (Buckets (Index).Ownership_Controls_Document));
            Buckets (Index).Ownership_Controls_Document :=
              Ada.Strings.Unbounded.Null_Unbounded_String;
            Buckets (Index).Ownership_Controls_Configured := False;
            Result := Success;
         end if;
      end Delete_Bucket_Ownership_Controls;

      procedure Put_Bucket_Configuration
        (Name     : String;
         Kind     : Singleton_Configuration_Kind;
         Document : String;
         Metadata : String;
         Result   : out Status)
      is
         Index    : constant Natural := Bucket_Index (Name);
         Incoming : constant Byte_Count :=
           Byte_Count (Document'Length) + Byte_Count (Metadata'Length);
         Existing : Byte_Count := 0;
         Base     : Byte_Count;
         Valid    : constant Boolean :=
           (case Kind is
               when Lifecycle_Configuration =>
                 Valid_Bucket_Lifecycle_Document (Document, Metadata),
               when Logging_Configuration =>
                 Metadata'Length = 0
                   and then Valid_Bucket_Logging_Document (Document));
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         elsif not Valid then
            Result := Entity_Too_Large;
            return;
         end if;
         Existing := Byte_Count
           (Ada.Strings.Unbounded.Length
              (Buckets (Index).Configuration_Documents (Kind))) +
           Byte_Count
             (Ada.Strings.Unbounded.Length
                (Buckets (Index).Configuration_Metadata (Kind)));
         Base := Bytes - Existing;
         if Incoming > Byte_Limit - Base
           or else Reserved_Bytes > Byte_Limit - Base - Incoming
         then
            Result := Capacity_Exceeded;
         else
            Buckets (Index).Configuration_Documents (Kind) :=
              Ada.Strings.Unbounded.To_Unbounded_String (Document);
            Buckets (Index).Configuration_Metadata (Kind) :=
              Ada.Strings.Unbounded.To_Unbounded_String (Metadata);
            Buckets (Index).Configuration_Configured (Kind) := True;
            Bytes := Base + Incoming;
            Result := Success;
         end if;
      end Put_Bucket_Configuration;

      procedure Get_Bucket_Configuration
        (Name       : String;
         Kind       : Singleton_Configuration_Kind;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Metadata   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Document := Ada.Strings.Unbounded.Null_Unbounded_String;
         Metadata := Ada.Strings.Unbounded.Null_Unbounded_String;
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         else
            Document := Buckets (Index).Configuration_Documents (Kind);
            Metadata := Buckets (Index).Configuration_Metadata (Kind);
            Configured := Buckets (Index).Configuration_Configured (Kind);
            Result := Success;
         end if;
      end Get_Bucket_Configuration;

      procedure Delete_Bucket_Configuration
        (Name   : String;
         Kind   : Singleton_Configuration_Kind;
         Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Bytes := Bytes - Byte_Count
              (Ada.Strings.Unbounded.Length
                 (Buckets (Index).Configuration_Documents (Kind))) -
              Byte_Count
                (Ada.Strings.Unbounded.Length
                   (Buckets (Index).Configuration_Metadata (Kind)));
            Buckets (Index).Configuration_Documents (Kind) :=
              Ada.Strings.Unbounded.Null_Unbounded_String;
            Buckets (Index).Configuration_Metadata (Kind) :=
              Ada.Strings.Unbounded.Null_Unbounded_String;
            Buckets (Index).Configuration_Configured (Kind) := False;
            Result := Success;
         end if;
      end Delete_Bucket_Configuration;

      procedure Put_Named_Bucket_Configuration
        (Name       : String;
         Kind       : Named_Configuration_Kind;
         Identifier : String;
         Document   : String;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
         Incoming : constant Byte_Count :=
           Byte_Count (Identifier'Length) + Byte_Count (Document'Length);
         Present : Boolean := False;
         Existing : Byte_Count := 0;
         Base : Byte_Count;
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         elsif not Valid_Bucket_Named_Configuration
           (Identifier, Document)
         then
            Result := Entity_Too_Large;
            return;
         elsif Buckets (Index).Named_Configurations (Kind).Contains
           (Identifier)
         then
            Present := True;
            Existing := Byte_Count (Identifier'Length) + Byte_Count
              (Ada.Strings.Unbounded.Length
                 (Buckets (Index).Named_Configurations (Kind).Element
                    (Identifier)));
         elsif Buckets (Index).Named_Configurations (Kind).Length >=
           Ada.Containers.Count_Type (Maximum_Bucket_Named_Configurations)
         then
            Result := Configuration_Limit_Exceeded;
            return;
         end if;
         Base := Bytes - Existing;
         if Incoming > Byte_Limit - Base
           or else Reserved_Bytes > Byte_Limit - Base - Incoming
         then
            Result := Capacity_Exceeded;
         elsif Present then
            Buckets (Index).Named_Configurations (Kind).Replace
              (Identifier,
               Ada.Strings.Unbounded.To_Unbounded_String (Document));
            Bytes := Base + Incoming;
            Result := Success;
         else
            Buckets (Index).Named_Configurations (Kind).Insert
              (Identifier,
               Ada.Strings.Unbounded.To_Unbounded_String (Document));
            Bytes := Base + Incoming;
            Result := Success;
         end if;
      end Put_Named_Bucket_Configuration;

      procedure Get_Named_Bucket_Configuration
        (Name       : String;
         Kind       : Named_Configuration_Kind;
         Identifier : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Document := Ada.Strings.Unbounded.Null_Unbounded_String;
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         elsif Buckets (Index).Named_Configurations (Kind).Contains
           (Identifier)
         then
            Document := Buckets (Index).Named_Configurations (Kind).Element
              (Identifier);
            Configured := True;
            Result := Success;
         else
            Result := Success;
         end if;
      end Get_Named_Bucket_Configuration;

      procedure Delete_Named_Bucket_Configuration
        (Name       : String;
         Kind       : Named_Configuration_Kind;
         Identifier : String;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         elsif Buckets (Index).Named_Configurations (Kind).Contains
           (Identifier)
         then
            Bytes := Bytes - Byte_Count (Identifier'Length) - Byte_Count
              (Ada.Strings.Unbounded.Length
                 (Buckets (Index).Named_Configurations (Kind).Element
                    (Identifier)));
            Buckets (Index).Named_Configurations (Kind).Delete (Identifier);
            Result := Success;
         else
            Result := Success;
         end if;
      end Delete_Named_Bucket_Configuration;

      procedure Put_Bucket_Public_Access_Block
        (Name          : String;
         Configuration : Bucket_Public_Access_Block_Configuration;
         Result        : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).Public_Access_Block := Canonical (Configuration);
            Buckets (Index).Public_Access_Block_Configured := True;
            Result := Success;
         end if;
      end Put_Bucket_Public_Access_Block;

      procedure Get_Bucket_Public_Access_Block
        (Name          : String;
         Configuration : out Bucket_Public_Access_Block_Configuration;
         Configured    : out Boolean;
         Result        : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Configuration := (others => <>);
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         else
            Configuration := Buckets (Index).Public_Access_Block;
            Configured := Buckets (Index).Public_Access_Block_Configured;
            Result := Success;
         end if;
      end Get_Bucket_Public_Access_Block;

      procedure Delete_Bucket_Public_Access_Block
        (Name : String; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Buckets (Index).Public_Access_Block := (others => <>);
            Buckets (Index).Public_Access_Block_Configured := False;
            Result := Success;
         end if;
      end Delete_Bucket_Public_Access_Block;

      procedure Put_Bucket_Policy
        (Name : String; Policy : String; Result : out Status)
      is
         Index    : constant Natural := Bucket_Index (Name);
         Incoming : constant Byte_Count := Byte_Count (Policy'Length);
         Existing : Byte_Count := 0;
      begin
         if Index = 0 then
            Result := Not_Found;
            return;
         elsif not Valid_Bucket_Policy (Policy) then
            Result := Entity_Too_Large;
            return;
         end if;
         Existing := Byte_Count
           (Ada.Strings.Unbounded.Length (Buckets (Index).Policy));
         if Incoming > Byte_Limit - Bytes
           or else Reserved_Bytes > Byte_Limit - Bytes - Incoming
         then
            Result := Capacity_Exceeded;
         else
            Buckets (Index).Policy :=
              Ada.Strings.Unbounded.To_Unbounded_String (Policy);
            Buckets (Index).Policy_Configured := True;
            Bytes := Bytes - Existing + Incoming;
            Result := Success;
         end if;
      end Put_Bucket_Policy;

      procedure Get_Bucket_Policy
        (Name       : String;
         Policy     : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         Policy := Ada.Strings.Unbounded.Null_Unbounded_String;
         Configured := False;
         if Index = 0 then
            Result := Not_Found;
         else
            Policy := Buckets (Index).Policy;
            Configured := Buckets (Index).Policy_Configured;
            Result := Success;
         end if;
      end Get_Bucket_Policy;

      procedure Delete_Bucket_Policy
        (Name : String; Result : out Status)
      is
         Index : constant Natural := Bucket_Index (Name);
      begin
         if Index = 0 then
            Result := Not_Found;
         else
            Bytes := Bytes - Byte_Count
              (Ada.Strings.Unbounded.Length (Buckets (Index).Policy));
            Buckets (Index).Policy :=
              Ada.Strings.Unbounded.Null_Unbounded_String;
            Buckets (Index).Policy_Configured := False;
            Result := Success;
         end if;
      end Delete_Bucket_Policy;

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
         Tags   : Object_Tag_Set;
         Conditions : Write_Conditions;
         Stored : out Object_Information;
         Identity : out Version_Identity;
         Result : out Status)
      is
         Bucket_At    : constant Natural := Bucket_Index (Bucket);
         Current_At   : constant Natural := Object_Index (Bucket, Key);
         Index        : Natural := 0;
         Existing     : Byte_Count := 0;
         Incoming     : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Reservation  : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Available    : Byte_Count;
         New_Order    : Version_Publication_Order;
         New_Info     : Object_Information := Info;
         Is_Null      : Boolean := True;
      begin
         Stored := Empty_Info;
         Identity := (others => <>);
         if Bucket_At = 0 then
            Result := Not_Found;
            return;
         end if;
         Result := Evaluate_Write_Conditions
           (Conditions,
            Exists     => Current_At /= 0,
            Entity_Tag =>
              (if Current_At = 0 then ""
               else Ada.Strings.Unbounded.To_String
                 (Objects (Current_At).Info.Entity_Tag)));
         if Result /= Success then
            return;
         end if;

         if Next_Version = Version_Publication_Order'Last then
            Result := Capacity_Exceeded;
            return;
         end if;
         New_Order := Next_Version + 1;

         case Buckets (Bucket_At).Versioning.Status is
            when Versioning_Unconfigured =>
               Index := Current_At;
               New_Info.Version :=
                 Ada.Strings.Unbounded.Null_Unbounded_String;
            when Versioning_Enabled =>
               Is_Null := False;
               New_Info.Version := Ada.Strings.Unbounded.To_Unbounded_String
                 (GNAT.SHA256.Digest
                    ("flyology-object-version" & Character'Val (0) &
                     Bucket & Character'Val (0) & Key & Character'Val (0) &
                     Version_Publication_Order'Image (New_Order)));
            when Versioning_Suspended =>
               New_Info.Version :=
                 Ada.Strings.Unbounded.Null_Unbounded_String;
               for Candidate in 1 .. Highest_Object loop
                  if Objects (Candidate).Used
                    and then Objects (Candidate).Is_Null_Version
                    and then Ada.Strings.Unbounded.To_String
                      (Objects (Candidate).Bucket) = Bucket
                    and then Ada.Strings.Unbounded.To_String
                      (Objects (Candidate).Key) = Key
                  then
                     Index := Candidate;
                     exit;
                  end if;
               end loop;
         end case;

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
            --  Burn publication orders before the first target mutation so
            --  an allocation exception can skip an ID but can never reuse it.
            Next_Version := New_Order;
            Objects (Index).Bucket := Stored_Bucket;
            Objects (Index).Key := Stored_Key;
            Objects (Index).Info := New_Info;
            Objects (Index).Tags := Tags;
            Objects (Index).Completed_Parts.Clear;
            Objects (Index).Is_Null_Version := Is_Null;
            Objects (Index).Is_Delete_Marker := False;
            Objects (Index).Publication := New_Order;
            Stored := New_Info;
            Identity.Has_Version_ID :=
              Buckets (Bucket_At).Versioning.Status /=
                Versioning_Unconfigured;
            Identity.Is_Null_Version :=
              Buckets (Bucket_At).Versioning.Status = Versioning_Suspended;
            Identity.Version_ID := New_Info.Version;
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
         Selector : Version_Selector;
         Data   : out Owned_Bytes;
         Info   : out Object_Information;
         Tags   : out Object_Tag_Set;
         Identity : out Version_Identity;
         Result : out Status)
      is
         Index : constant Natural :=
           Selected_Object_Index (Bucket, Key, Selector);
         Snapshot : Byte_Count := 0;
         Copied : Boolean := False;
      begin
         Data := (Ada.Finalization.Controlled with others => <>);
         Info := Empty_Info;
         Tags := Empty_Object_Tags;
         Identity := (others => <>);
         if Bucket_Index (Bucket) = 0 then
            Result := Bucket_Not_Found;
         elsif Index = 0 then
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
            Tags := Objects (Index).Tags;
            Identity.Has_Version_ID :=
              Selector.Kind /= Current_Version
              or else Buckets (Bucket_Index (Bucket)).Versioning.Status /=
                Versioning_Unconfigured;
            Identity.Is_Null_Version :=
              Identity.Has_Version_ID and then Objects (Index).Is_Null_Version;
            Identity.Version_ID := Objects (Index).Info.Version;
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
         if Bucket_Index (Bucket) = 0 then
            Result := Bucket_Not_Found;
            return;
         elsif Index = 0 then
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
         Selector : Version_Selector;
         Info   : out Object_Information;
         Result : out Status)
      is
         Index : constant Natural :=
           Selected_Object_Index (Bucket, Key, Selector);
      begin
         Info := Empty_Info;
         if Index = 0 then
            Result := Not_Found;
         else
            Info := Objects (Index).Info;
            Result := Success;
         end if;
      end Head;

      procedure Attributes
        (Bucket   : String;
         Key      : String;
         Selector : Version_Selector;
         Options  : Object_Attribute_Options;
         Conditions : Read_Conditions;
         Snapshot : out Object_Attribute_Snapshot;
         Result   : out Status)
      is
         Index : constant Natural :=
           Selected_Object_Index (Bucket, Key, Selector);
      begin
         Snapshot := (others => <>);
         if Index = 0 then
            Result := Not_Found;
            return;
         end if;
         Snapshot.Info := Objects (Index).Info;
         Result := Evaluate_Read_Conditions
           (Conditions,
            Ada.Strings.Unbounded.To_String (Snapshot.Info.Entity_Tag),
            Snapshot.Info.Modified);
         if Result /= Success then
            return;
         end if;
         Snapshot.Is_Multipart := not Objects (Index).Completed_Parts.Is_Empty;
         Snapshot.Total_Parts :=
           Natural (Objects (Index).Completed_Parts.Length);
         if Options.Maximum > 0 then
            for Part of Objects (Index).Completed_Parts loop
               if Part.Number > Options.After then
                  if Snapshot.Parts.Length <
                    Ada.Containers.Count_Type (Options.Maximum)
                  then
                     Snapshot.Parts.Append (Part);
                  else
                     Snapshot.Is_Truncated := True;
                     Snapshot.Next_After :=
                       Multipart_Part_Marker
                         (Snapshot.Parts.Last_Element.Number);
                     exit;
                  end if;
               end if;
            end loop;
         end if;
         Result := Success;
      end Attributes;

      procedure Delete_Many
        (Bucket   : String;
         Entries  : Delete_Object_Entries;
         Requirements : Delete_Objects_Requirements;
         Modified : Unix_Time;
         Outcomes : in out Delete_Object_Outcomes;
         Result   : out Status)
      is
         Bucket_Position : constant Natural := Bucket_Index (Bucket);
      begin
         Outcomes.Clear;
         if Bucket_Position = 0 then
            Result := Bucket_Not_Found;
            return;
         elsif Requirements.Require_Unversioned
           and then
             (Buckets (Bucket_Position).Versioning.Status /=
                Versioning_Unconfigured
              or else Buckets (Bucket_Position).Versioning.MFA_Delete =
                MFA_Delete_Enabled)
         then
            Result := Not_Implemented;
            return;
         end if;
         if Buckets (Bucket_Position).Versioning.MFA_Delete =
              MFA_Delete_Enabled
           and then not Requirements.MFA_Validated
         then
            for Request_Entry of Entries loop
               if Request_Entry.Selector.Kind /= Current_Version then
                  Result := Access_Denied;
                  return;
               end if;
            end loop;
         end if;
         for Request_Entry of Entries loop
            declare
               Entry_Result : Status;
               Publication  : Version_Delete_Outcome;
            begin
               Delete_Selected
                 (Bucket, Ada.Strings.Unbounded.To_String (Request_Entry.Key),
                  Request_Entry.Selector, Request_Entry.Conditions,
                  Requirements.MFA_Validated, Modified, Publication,
                  Entry_Result);
               Outcomes.Append
                 (Delete_Object_Outcome'
                    (Result => Entry_Result, Publication => Publication));
            end;
         end loop;
         Result := Success;
      end Delete_Many;

      procedure Delete_Selected
        (Bucket        : String;
         Key           : String;
         Selector      : Version_Selector;
         Conditions    : Delete_Object_Conditions;
         MFA_Validated : Boolean;
         Modified      : Unix_Time;
         Outcome       : out Version_Delete_Outcome;
         Result        : out Status)
      is
         Bucket_Position : constant Natural := Bucket_Index (Bucket);
         Condition_At    : Natural := 0;
         Target_At       : Natural := 0;
         Existing        : Byte_Count := 0;

         procedure Shrink_Highest is
         begin
            while Highest_Object > 0
              and then not Objects (Highest_Object).Used
            loop
               Highest_Object := Highest_Object - 1;
            end loop;
         end Shrink_Highest;

         procedure Remove_Selected is
         begin
            if Target_At = 0 then
               Outcome.Kind := No_Version_Removed;
               Result := Success;
               return;
            end if;
            Outcome.Kind :=
              (if Objects (Target_At).Is_Delete_Marker
               then Delete_Marker_Removed else Object_Version_Removed);
            Outcome.Has_Version_ID := Selector.Kind /= Current_Version;
            Outcome.Is_Null_Version :=
              Outcome.Has_Version_ID
              and then Objects (Target_At).Is_Null_Version;
            Outcome.Version_ID := Objects (Target_At).Info.Version;
            Bytes := Bytes - Byte_Count (Objects (Target_At).Data.Capacity);
            Objects (Target_At) := (others => <>);
            Shrink_Highest;
            Result := Success;
         end Remove_Selected;

         procedure Publish_Marker (Null_Marker : Boolean) is
            New_Order : Version_Publication_Order;
            New_Info  : Object_Information := Empty_Info;
            Stored_Bucket : constant
              Ada.Strings.Unbounded.Unbounded_String :=
                Ada.Strings.Unbounded.To_Unbounded_String (Bucket);
            Stored_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Key);
         begin
            if Next_Version = Version_Publication_Order'Last then
               Result := Capacity_Exceeded;
               return;
            end if;
            if Null_Marker then
               Target_At := Selected_Generation_Index
                 (Bucket, Key, Null_Version_Selector);
            end if;
            if Target_At = 0 then
               for Candidate in 1 .. Highest_Object loop
                  if not Objects (Candidate).Used then
                     Target_At := Candidate;
                     exit;
                  end if;
               end loop;
               if Target_At = 0 and then Highest_Object < Object_Limit then
                  Highest_Object := Highest_Object + 1;
                  Target_At := Highest_Object;
               elsif Target_At = 0 then
                  Result := Capacity_Exceeded;
                  return;
               end if;
            else
               Existing := Byte_Count (Objects (Target_At).Data.Capacity);
            end if;
            New_Order := Next_Version + 1;
            New_Info.Modified := Modified;
            if not Null_Marker then
               New_Info.Version := Ada.Strings.Unbounded.To_Unbounded_String
                 (GNAT.SHA256.Digest
                    ("flyology-object-version" & Character'Val (0) &
                     Bucket & Character'Val (0) & Key & Character'Val (0) &
                     Version_Publication_Order'Image (New_Order)));
            end if;

            Next_Version := New_Order;
            Objects (Target_At) := (others => <>);
            Objects (Target_At).Bucket := Stored_Bucket;
            Objects (Target_At).Key := Stored_Key;
            Objects (Target_At).Is_Null_Version := Null_Marker;
            Objects (Target_At).Is_Delete_Marker := True;
            Objects (Target_At).Publication := New_Order;
            Objects (Target_At).Info := New_Info;
            Objects (Target_At).Used := True;
            Bytes := Bytes - Existing;
            Outcome :=
              (Kind            => Delete_Marker_Created,
               Has_Version_ID  => True,
               Is_Null_Version => Null_Marker,
               Version_ID      => New_Info.Version);
            Result := Success;
         end Publish_Marker;
      begin
         Outcome := (others => <>);
         if Bucket_Position = 0 then
            Result := Bucket_Not_Found;
            return;
         elsif Selector.Kind /= Current_Version
           and then Buckets (Bucket_Position).Versioning.MFA_Delete =
             MFA_Delete_Enabled
           and then not MFA_Validated
         then
            Result := Access_Denied;
            return;
         end if;

         Condition_At :=
           (if Selector.Kind = Current_Version
            then Object_Index (Bucket, Key)
            else Selected_Generation_Index (Bucket, Key, Selector));
         Result := Evaluate_Delete_Object_Conditions
           (Conditions,
            Exists => Condition_At /= 0,
            Info =>
              (if Condition_At = 0
               then Empty_Info else Objects (Condition_At).Info));
         if Result /= Success then
            return;
         end if;

         if Selector.Kind /= Current_Version then
            Target_At := Condition_At;
            Outcome.Has_Version_ID := True;
            Outcome.Is_Null_Version := Selector.Kind = Null_Version;
            Outcome.Version_ID := Selector.ID;
            Remove_Selected;
         else
            case Buckets (Bucket_Position).Versioning.Status is
               when Versioning_Unconfigured =>
                  Target_At := Condition_At;
                  Remove_Selected;
               when Versioning_Enabled =>
                  Publish_Marker (Null_Marker => False);
               when Versioning_Suspended =>
                  Publish_Marker (Null_Marker => True);
            end case;
         end if;
      end Delete_Selected;

      procedure Put_Tags
        (Bucket : String; Key : String; Selector : Version_Selector;
         Tags : Object_Tag_Set;
         Identity : out Version_Identity;
         Result : out Status)
      is
         Index : constant Natural :=
           Selected_Object_Index (Bucket, Key, Selector);
         Bucket_Position : constant Natural := Bucket_Index (Bucket);
      begin
         Identity := (others => <>);
         if Bucket_Position = 0 then
            Result := Bucket_Not_Found;
         elsif Index = 0 then
            Result := Not_Found;
         else
            Objects (Index).Tags := Tags;
            Identity.Has_Version_ID :=
              Selector.Kind /= Current_Version
              or else Ada.Strings.Unbounded.Length
                (Objects (Index).Info.Version) > 0
              or else Buckets (Bucket_Position).Versioning.Status /=
                Versioning_Unconfigured;
            Identity.Is_Null_Version :=
              Identity.Has_Version_ID and then Objects (Index).Is_Null_Version;
            Identity.Version_ID := Objects (Index).Info.Version;
            Result := Success;
         end if;
      end Put_Tags;

      procedure Get_Tags
        (Bucket : String; Key : String; Selector : Version_Selector;
         Tags : out Object_Tag_Set;
         Identity : out Version_Identity;
         Result : out Status)
      is
         Index : constant Natural :=
           Selected_Object_Index (Bucket, Key, Selector);
         Bucket_Position : constant Natural := Bucket_Index (Bucket);
      begin
         Tags := Empty_Object_Tags;
         Identity := (others => <>);
         if Bucket_Position = 0 then
            Result := Bucket_Not_Found;
         elsif Index = 0 then
            Result := Not_Found;
         else
            Tags := Objects (Index).Tags;
            Identity.Has_Version_ID :=
              Selector.Kind /= Current_Version
              or else Ada.Strings.Unbounded.Length
                (Objects (Index).Info.Version) > 0
              or else Buckets (Bucket_Position).Versioning.Status /=
                Versioning_Unconfigured;
            Identity.Is_Null_Version :=
              Identity.Has_Version_ID and then Objects (Index).Is_Null_Version;
            Identity.Version_ID := Objects (Index).Info.Version;
            Result := Success;
         end if;
      end Get_Tags;

      procedure Delete_Tags
        (Bucket : String; Key : String; Selector : Version_Selector;
         Identity : out Version_Identity;
         Result : out Status)
      is
         Index : constant Natural :=
           Selected_Object_Index (Bucket, Key, Selector);
         Bucket_Position : constant Natural := Bucket_Index (Bucket);
      begin
         Identity := (others => <>);
         if Bucket_Position = 0 then
            Result := Bucket_Not_Found;
         elsif Index = 0 then
            Result := Not_Found;
         else
            Objects (Index).Tags := Empty_Object_Tags;
            Identity.Has_Version_ID :=
              Selector.Kind /= Current_Version
              or else Ada.Strings.Unbounded.Length
                (Objects (Index).Info.Version) > 0
              or else Buckets (Bucket_Position).Versioning.Status /=
                Versioning_Unconfigured;
            Identity.Is_Null_Version :=
              Identity.Has_Version_ID and then Objects (Index).Is_Null_Version;
            Identity.Version_ID := Objects (Index).Info.Version;
            Result := Success;
         end if;
      end Delete_Tags;

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
              and then Object_Index
                (Bucket, Ada.Strings.Unbounded.To_String
                   (Objects (Index).Key)) = Index
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

      procedure List_Versions
        (Bucket  : String;
         Options : List_Versions_Options;
         Page    : out List_Versions_Page;
         Result  : out Status)
      is
         type Candidate is record
            Value       : Listed_Version;
            Publication : Version_Publication_Order;
         end record;

         package Candidate_Vectors is new Ada.Containers.Vectors
           (Index_Type => Positive, Element_Type => Candidate);

         type Page_Candidate is record
            Is_Prefix      : Boolean := False;
            Value          : Listed_Version;
            Common_Prefix  : Ada.Strings.Unbounded.Unbounded_String;
            Cursor_Key     : Ada.Strings.Unbounded.Unbounded_String;
            Cursor_Version : Ada.Strings.Unbounded.Unbounded_String;
         end record;

         package Page_Candidate_Vectors is new Ada.Containers.Vectors
           (Index_Type => Positive, Element_Type => Page_Candidate);

         Candidates : Candidate_Vectors.Vector;
         Projected  : Page_Candidate_Vectors.Vector;
         Start_At   : Natural := 1;
         Marker_At  : Natural := 0;
         Returned   : Natural := 0;

         function Before (Left, Right : Candidate) return Boolean is
            Left_Key  : constant String :=
              Ada.Strings.Unbounded.To_String (Left.Value.Key);
            Right_Key : constant String :=
              Ada.Strings.Unbounded.To_String (Right.Value.Key);
         begin
            return Left_Key < Right_Key
              or else
                (Left_Key = Right_Key
                 and then Left.Publication > Right.Publication);
         end Before;

         procedure Insert (Value : Candidate) is
            Position : Natural := 0;
         begin
            if not Candidates.Is_Empty then
               for Index in Candidates.First_Index .. Candidates.Last_Index
               loop
                  if Before (Value, Candidates (Index)) then
                     Position := Index;
                     exit;
                  end if;
               end loop;
            end if;
            if Position = 0 then
               Candidates.Append (Value);
            else
               Candidates.Insert (Position, Value);
            end if;
         end Insert;

         function Is_Latest (Index : Positive) return Boolean is
         begin
            for Other in 1 .. Highest_Object loop
               if Objects (Other).Used
                 and then Objects (Other).Bucket = Objects (Index).Bucket
                 and then Objects (Other).Key = Objects (Index).Key
                 and then Objects (Other).Publication >
                   Objects (Index).Publication
               then
                  return False;
               end if;
            end loop;
            return True;
         end Is_Latest;
      begin
         Page := (others => <>);
         if Bucket_Index (Bucket) = 0 then
            Result := Not_Found;
            return;
         elsif Options.Has_Version_ID_Marker and then
           not Options.Has_Key_Marker
         then
            Result := Invalid_Request;
            return;
         elsif Options.Has_Version_ID_Marker
           and then
             (Ada.Strings.Unbounded.Length (Options.Version_ID_Marker) = 0
              or else Ada.Strings.Unbounded.Length
                (Options.Version_ID_Marker) > Maximum_Version_ID_Length)
         then
            Result := Invalid_Request;
            return;
         end if;

         Candidates.Reserve_Capacity
           (Ada.Containers.Count_Type (Highest_Object));
         for Index in 1 .. Highest_Object loop
            if Objects (Index).Used
              and then Ada.Strings.Unbounded.To_String
                (Objects (Index).Bucket) = Bucket
              and then Listing_Matches_Prefix
                (Ada.Strings.Unbounded.To_String (Objects (Index).Key),
                 Ada.Strings.Unbounded.To_String (Options.Prefix))
            then
               Insert
                  ((Value =>
                      (Key              => Objects (Index).Key,
                       Version_ID       =>
                         (if Objects (Index).Is_Null_Version
                          then Ada.Strings.Unbounded.To_Unbounded_String
                            ("null")
                          else Objects (Index).Info.Version),
                       Info             => Objects (Index).Info,
                       Is_Latest        => Is_Latest (Index),
                       Is_Delete_Marker => Objects (Index).Is_Delete_Marker),
                    Publication => Objects (Index).Publication));
            end if;
         end loop;

         if Options.Has_Key_Marker then
            if Options.Has_Version_ID_Marker then
               for Index in 1 .. Natural (Candidates.Length) loop
                  if Candidates (Index).Value.Key = Options.Key_Marker
                    and then Candidates (Index).Value.Version_ID =
                      Options.Version_ID_Marker
                  then
                     Marker_At := Index;
                     exit;
                  end if;
               end loop;
               if Marker_At = 0 then
                  Result := Invalid_Request;
                  return;
               end if;
               Start_At := Marker_At + 1;
            else
               Start_At := Natural (Candidates.Length) + 1;
               for Index in 1 .. Natural (Candidates.Length) loop
                  if Ada.Strings.Unbounded.To_String
                    (Candidates (Index).Value.Key) >
                      Ada.Strings.Unbounded.To_String (Options.Key_Marker)
                  then
                     Start_At := Index;
                     exit;
                  end if;
               end loop;
            end if;
         end if;

         if Start_At <= Natural (Candidates.Length) then
            declare
               Prefix : constant String :=
                 Ada.Strings.Unbounded.To_String (Options.Prefix);
               Delimiter : constant String :=
                 Ada.Strings.Unbounded.To_String (Options.Delimiter);
            begin
               for Index in Start_At .. Natural (Candidates.Length) loop
                  declare
                     Key : constant String :=
                       Ada.Strings.Unbounded.To_String
                         (Candidates (Index).Value.Key);
                     Delimiter_At : constant Natural :=
                       (if Delimiter'Length = 0 or else Prefix'Length >=
                           Key'Length
                        then 0
                        else Ada.Strings.Fixed.Index
                          (Key, Delimiter,
                           From => Key'First + Prefix'Length));
                  begin
                     if Delimiter_At = 0 then
                        Projected.Append
                          (Page_Candidate'
                           (Is_Prefix      => False,
                            Value          => Candidates (Index).Value,
                            Common_Prefix  =>
                              Ada.Strings.Unbounded.Null_Unbounded_String,
                            Cursor_Key     => Candidates (Index).Value.Key,
                            Cursor_Version =>
                              Candidates (Index).Value.Version_ID));
                     else
                        declare
                           Common : constant String :=
                             Key
                               (Key'First .. Delimiter_At +
                                  Delimiter'Length - 1);
                        begin
                           if Options.Has_Key_Marker
                             and then not Listing_Follows_Cursor
                               (Common,
                                Ada.Strings.Unbounded.To_String
                                  (Options.Key_Marker))
                           then
                              null;
                           elsif not Projected.Is_Empty
                             and then Projected.Last_Element.Is_Prefix
                             and then Ada.Strings.Unbounded.To_String
                               (Projected.Last_Element.Common_Prefix) = Common
                           then
                              Projected.Reference (Projected.Last_Index).
                                Cursor_Key := Candidates (Index).Value.Key;
                              Projected.Reference (Projected.Last_Index).
                                Cursor_Version :=
                                  Candidates (Index).Value.Version_ID;
                           else
                              Projected.Append
                                (Page_Candidate'
                                 (Is_Prefix      => True,
                                  Value          => (others => <>),
                                  Common_Prefix  =>
                                    Ada.Strings.Unbounded.To_Unbounded_String
                                      (Common),
                                  Cursor_Key     =>
                                    Candidates (Index).Value.Key,
                                  Cursor_Version =>
                                    Candidates (Index).Value.Version_ID));
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end;
         end if;

         if Options.Maximum > 0
           and then not Projected.Is_Empty
         then
            Returned := Natural'Min
              (Natural (Options.Maximum),
               Natural (Projected.Length));
            for Index in 1 .. Returned loop
               if Projected (Index).Is_Prefix then
                  Page.Common_Prefixes.Append
                    (Projected (Index).Common_Prefix);
               else
                  Page.Entries.Append (Projected (Index).Value);
               end if;
            end loop;
            Page.Is_Truncated :=
              Returned < Natural (Projected.Length);
            if Page.Is_Truncated then
               Page.Next_Key_Marker := Projected (Returned).Cursor_Key;
               Page.Next_Version_ID_Marker :=
                 Projected (Returned).Cursor_Version;
            end if;
         end if;
         Result := Success;
      end List_Versions;

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

      procedure Multipart_Configuration
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Options   : out Multipart_Options;
         Result    : out Status)
      is
         Index : constant Natural := Upload_Index (Bucket, Key, Upload_ID);
      begin
         Options := Default_Multipart_Options;
         if Index = 0 then
            Result := Not_Found;
         else
            Options := Uploads (Index).Options;
            Result := Success;
         end if;
      end Multipart_Configuration;

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
         Upload_At : constant Natural :=
           Upload_Index (Bucket, Key, Upload_ID);
         Index     : Natural := Part_Index (Upload_ID, Part_Number);
         Existing  : Byte_Count := 0;
         Incoming  : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Reservation : constant Byte_Count :=
           Byte_Count (Data.Capacity);
         Available : Byte_Count;
      begin
         Stored := Empty_Info;
         if Upload_At = 0 then
            Result := Not_Found;
            return;
         elsif not Checksum_Engine.Valid_Configuration
           (Uploads (Upload_At).Options.Checksum)
           or else
             (Uploads (Upload_At).Options.Checksum.Algorithm = No_Checksum
              and then Info.Checksum /= No_Checksum_Information)
           or else
             (Uploads (Upload_At).Options.Checksum.Algorithm /= No_Checksum
              and then
                (Info.Checksum.Algorithm /=
                   Uploads (Upload_At).Options.Checksum.Algorithm
                 or else Info.Checksum.Method /=
                   Uploads (Upload_At).Options.Checksum.Method
                 or else not Checksum_Engine.Valid_Digest
                   (Ada.Strings.Unbounded.To_String (Info.Checksum.Value),
                    Info.Checksum.Algorithm)))
         then
            Result := Backend_Unavailable;
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
         Upload_At : constant Natural :=
           Upload_Index (Bucket, Key, Upload_ID);
      begin
         Page := (others => <>);
         if Upload_At = 0 then
            Result := Not_Found;
            return;
         end if;
         Page.Checksum := Uploads (Upload_At).Options.Checksum;
         if Options.Maximum = 0
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
         Options   : Complete_Multipart_Options;
         Modified  : Unix_Time;
         Info      : out Object_Information;
         Result    : out Status)
      is
         Upload_At : constant Natural :=
           Upload_Index (Bucket, Key, Upload_ID);
         Bucket_At : constant Natural := Bucket_Index (Bucket);
         Current_At : constant Natural := Object_Index (Bucket, Key);
         Object_At : Natural := 0;
         Previous  : Multipart_Part_Number := Multipart_Part_Number'First;
         First     : Boolean := True;
         Final_Data : Owned_Bytes;
         Final_Size : Byte_Count := 0;
         Staged_Size : Byte_Count := 0;
         Existing_Size : Byte_Count := 0;
         Hash : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
         Assembly_Reserved : Boolean := False;
         Completed_Parts : Completed_Object_Part_List;
         Completed_Checksum : Checksum_Information;
         New_Order : Version_Publication_Order;
         Is_Null : Boolean := True;
      begin
         Info := Empty_Info;
         if Upload_At = 0 then
            Result := Not_Found;
            return;
         elsif Completion.Is_Empty then
            Result := Invalid_Request;
            return;
         elsif not Checksum_Engine.Valid_Configuration
           (Uploads (Upload_At).Options.Checksum)
         then
            Result := Backend_Unavailable;
            return;
         end if;

         for Reference of Completion loop
            if (not First and then Reference.Number <= Previous)
              or else
                (Uploads (Upload_At).Options.Checksum.Method =
                   Composite_Checksum
                 and then
                   ((First and then Reference.Number /= 1)
                    or else
                      (not First and then Reference.Number /= Previous + 1)))
            then
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
               if Stored_At = 0 then
                  Result := Invalid_Part;
                  return;
               elsif
                 (Uploads (Upload_At).Options.Checksum.Algorithm = No_Checksum
                  and then Parts (Stored_At).Info.Checksum /=
                    No_Checksum_Information)
                 or else
                   (Uploads (Upload_At).Options.Checksum.Algorithm /=
                      No_Checksum
                    and then
                      (Parts (Stored_At).Info.Checksum.Algorithm /=
                         Uploads (Upload_At).Options.Checksum.Algorithm
                       or else Parts (Stored_At).Info.Checksum.Method /=
                         Uploads (Upload_At).Options.Checksum.Method
                       or else not Checksum_Engine.Valid_Digest
                         (Ada.Strings.Unbounded.To_String
                            (Parts (Stored_At).Info.Checksum.Value),
                          Parts (Stored_At).Info.Checksum.Algorithm)))
               then
                  Result := Backend_Unavailable;
                  return;
               elsif Ada.Strings.Unbounded.To_String
                   (Reference.Entity_Tag) /=
                     Ada.Strings.Unbounded.To_String
                       (Parts (Stored_At).Info.Entity_Tag)
                 or else
                   (Uploads (Upload_At).Options.Checksum.Method =
                      Composite_Checksum
                    and then Reference.Checksum /=
                      Parts (Stored_At).Info.Checksum)
                 or else
                   (Reference.Checksum.Algorithm /= No_Checksum
                    and then Reference.Checksum /=
                      Parts (Stored_At).Info.Checksum)
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
               Completed_Parts.Append
                 (Completed_Object_Part'
                    (Number => Reference.Number,
                     Size   => Parts (Stored_At).Info.Size,
                     Checksum => Parts (Stored_At).Info.Checksum));
               Previous := Reference.Number;
               First := False;
            end;
         end loop;

         if Uploads (Upload_At).Options.Checksum.Algorithm /= No_Checksum
         then
            declare
               Values : Checksum_Engine.Part_Value_Array
                 (1 .. Natural (Completion.Length));
               Position : Positive := Values'First;
            begin
               for Reference of Completion loop
                  declare
                     Stored_At : constant Natural :=
                       Part_Index (Upload_ID, Reference.Number);
                  begin
                     Values (Position) :=
                       (Value  => Parts (Stored_At).Info.Checksum,
                        Length => Parts (Stored_At).Info.Size);
                     Position := Position + 1;
                  end;
               end loop;
               Completed_Checksum := Uploads (Upload_At).Options.Checksum;
               Completed_Checksum.Value :=
                 Ada.Strings.Unbounded.To_Unbounded_String
                   (Checksum_Engine.Multipart_Object_Value
                      (Completed_Checksum.Algorithm,
                       Completed_Checksum.Method, Values));
            end;
         end if;

         if Options.Expected_Checksum.Algorithm /= No_Checksum
           and then
             (Options.Expected_Checksum.Algorithm /=
                Completed_Checksum.Algorithm
              or else Options.Expected_Checksum.Method /=
                Completed_Checksum.Method)
         then
            Result := Invalid_Request;
            return;
         elsif Options.Expected_Checksum.Algorithm /= No_Checksum
           and then not Checksum_Engine.Matches_Stored_Object_Digest
             (Ada.Strings.Unbounded.To_String
                (Options.Expected_Checksum.Value),
              Ada.Strings.Unbounded.To_String (Completed_Checksum.Value),
              Options.Expected_Checksum.Algorithm,
              Options.Expected_Checksum.Method,
              Positive (Completion.Length))
         then
            Result := Bad_Digest;
            return;
         end if;

         if Final_Size > Byte_Count (Natural'Last) then
            Result := Capacity_Exceeded;
            return;
         end if;
         if Options.Expected_Size.Kind = Known
           and then Options.Expected_Size.Bytes /= Final_Size
         then
            Result := Invalid_Request;
            return;
         end if;
         declare
            Condition_Result : constant Status := Evaluate_Write_Conditions
              (Options.Conditions, Current_At /= 0,
               (if Current_At = 0 then ""
                else Ada.Strings.Unbounded.To_String
                  (Objects (Current_At).Info.Entity_Tag)));
         begin
            if Condition_Result /= Success then
               Result := Condition_Result;
               return;
            end if;
         end;
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

         if Next_Version = Version_Publication_Order'Last then
            Final_Data :=
              (Ada.Finalization.Controlled with others => <>);
            if Assembly_Reserved then
               Reserved_Bytes := Reserved_Bytes - Final_Size;
               Assembly_Reserved := False;
            end if;
            Result := Capacity_Exceeded;
            return;
         end if;
         New_Order := Next_Version + 1;
         case Buckets (Bucket_At).Versioning.Status is
            when Versioning_Unconfigured =>
               Object_At := Current_At;
            when Versioning_Enabled =>
               Is_Null := False;
            when Versioning_Suspended =>
               Object_At := Selected_Generation_Index
                 (Bucket, Key, Null_Version_Selector);
         end case;

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
            Completed_Info : Object_Information :=
              (Size         => Final_Size,
               Modified     => Modified,
               Entity_Tag   => Ada.Strings.Unbounded.To_Unbounded_String
                 (GNAT.MD5.Digest (Hash) & "-" &
                  Ada.Strings.Fixed.Trim
                    (Natural'Image (Natural (Completion.Length)),
                     Ada.Strings.Both)),
               Content_Type => Uploads (Upload_At).Options.Content_Type,
               Version      => Ada.Strings.Unbounded.Null_Unbounded_String,
               Checksum     => Completed_Checksum,
               Metadata     => (others => <>));
            Stored_Bucket : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Bucket);
            Stored_Key : constant Ada.Strings.Unbounded.Unbounded_String :=
              Ada.Strings.Unbounded.To_Unbounded_String (Key);
         begin
            if not Is_Null then
               Completed_Info.Version :=
                 Ada.Strings.Unbounded.To_Unbounded_String
                   (GNAT.SHA256.Digest
                      ("flyology-object-version" & Character'Val (0) &
                       Bucket & Character'Val (0) & Key & Character'Val (0) &
                       Version_Publication_Order'Image (New_Order)));
            end if;
            --  Finish every allocating metadata operation before consuming
            --  the staged upload or publishing its assembled payload.
            Next_Version := New_Order;
            Objects (Object_At).Bucket := Stored_Bucket;
            Objects (Object_At).Key := Stored_Key;
            Objects (Object_At).Info := Completed_Info;
            Objects (Object_At).Tags := Empty_Object_Tags;
            Objects (Object_At).Is_Null_Version := Is_Null;
            Objects (Object_At).Is_Delete_Marker := False;
            Objects (Object_At).Publication := New_Order;
            Completed_Object_Part_Vectors.Move
              (Objects (Object_At).Completed_Parts, Completed_Parts);
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
         Conditions : Abort_Multipart_Conditions;
         Result    : out Status)
      is
         Upload_At : constant Natural :=
           Upload_Index (Bucket, Key, Upload_ID);
      begin
         if Upload_At = 0 then
            Result := Not_Found;
            return;
         elsif Conditions.Has_Initiated_Time
           and then Uploads (Upload_At).Created /= Conditions.Initiated_Time
         then
            Result := Precondition_Failed;
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

   overriding procedure Put_Bucket_ABAC
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_ABAC_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_ABAC (Bucket, Value, Result);
      end if;
   end Put_Bucket_ABAC;

   overriding procedure Get_Bucket_ABAC
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_ABAC_Status;
      Result   : out Status)
   is
   begin
      Value := Bucket_ABAC_Disabled;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_ABAC (Bucket, Value, Result);
      end if;
   end Get_Bucket_ABAC;

   overriding procedure Put_Bucket_Acceleration
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_Acceleration_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_Acceleration (Bucket, Value, Result);
      end if;
   end Put_Bucket_Acceleration;

   overriding procedure Get_Bucket_Acceleration
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Acceleration_Status;
      Result   : out Status)
   is
   begin
      Value := Bucket_Acceleration_Unconfigured;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Acceleration (Bucket, Value, Result);
      end if;
   end Get_Bucket_Acceleration;

   overriding procedure Put_Bucket_Request_Payment
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_Request_Payment_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_Request_Payment (Bucket, Value, Result);
      end if;
   end Put_Bucket_Request_Payment;

   overriding procedure Get_Bucket_Request_Payment
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Request_Payment_Status;
      Result   : out Status)
   is
   begin
      Value := Bucket_Owner_Pays;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Request_Payment (Bucket, Value, Result);
      end if;
   end Get_Bucket_Request_Payment;

   overriding procedure Put_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Value    : Tags.Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Tags.Valid_Bucket_Tag_Set (Value)
      then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_Tags (Bucket, Value, Result);
      end if;
   end Put_Bucket_Tags;

   overriding procedure Get_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Tags.Tag_Set;
      Result   : out Status)
   is
   begin
      Value.Clear;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Tags (Bucket, Value, Result);
      end if;
   end Get_Bucket_Tags;

   overriding procedure Delete_Bucket_Tags
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
         Item.State.Delete_Bucket_Tags (Bucket, Result);
      end if;
   end Delete_Bucket_Tags;

   overriding procedure Put_Bucket_CORS
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      elsif not Valid_Bucket_CORS_Document (Document) then
         Result := Entity_Too_Large;
      else
         Item.State.Put_Bucket_CORS (Bucket, Document, Result);
      end if;
   end Put_Bucket_CORS;

   overriding procedure Get_Bucket_CORS
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_CORS
           (Bucket, Document, Configured, Result);
      end if;
   end Get_Bucket_CORS;

   overriding procedure Delete_Bucket_CORS
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
         Item.State.Delete_Bucket_CORS (Bucket, Result);
      end if;
   end Delete_Bucket_CORS;

   overriding procedure Put_Bucket_Encryption
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      elsif not Valid_Bucket_Encryption_Document (Document) then
         Result := Entity_Too_Large;
      else
         Item.State.Put_Bucket_Encryption (Bucket, Document, Result);
      end if;
   end Put_Bucket_Encryption;

   overriding procedure Get_Bucket_Encryption
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Encryption
           (Bucket, Document, Configured, Result);
      end if;
   end Get_Bucket_Encryption;

   overriding procedure Delete_Bucket_Encryption
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
         Item.State.Delete_Bucket_Encryption (Bucket, Result);
      end if;
   end Delete_Bucket_Encryption;

   overriding procedure Put_Bucket_Ownership_Controls
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      elsif not Valid_Bucket_Ownership_Controls_Document (Document) then
         Result := Entity_Too_Large;
      else
         Item.State.Put_Bucket_Ownership_Controls (Bucket, Document, Result);
      end if;
   end Put_Bucket_Ownership_Controls;

   overriding procedure Get_Bucket_Ownership_Controls
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Ownership_Controls
           (Bucket, Document, Configured, Result);
      end if;
   end Get_Bucket_Ownership_Controls;

   overriding procedure Delete_Bucket_Ownership_Controls
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
         Item.State.Delete_Bucket_Ownership_Controls (Bucket, Result);
      end if;
   end Delete_Bucket_Ownership_Controls;

   overriding procedure Put_Bucket_Lifecycle
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Transition_Default_Minimum_Object_Size : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      elsif not Valid_Bucket_Lifecycle_Document
        (Document, Transition_Default_Minimum_Object_Size)
      then
         Result := Entity_Too_Large;
      else
         Item.State.Put_Bucket_Configuration
           (Bucket, Lifecycle_Configuration, Document,
            Transition_Default_Minimum_Object_Size, Result);
      end if;
   end Put_Bucket_Lifecycle;

   overriding procedure Get_Bucket_Lifecycle
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Transition_Default_Minimum_Object_Size :
        out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Transition_Default_Minimum_Object_Size :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Configuration
           (Bucket, Lifecycle_Configuration, Document,
            Transition_Default_Minimum_Object_Size, Configured, Result);
      end if;
   end Get_Bucket_Lifecycle;

   overriding procedure Delete_Bucket_Lifecycle
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
         Item.State.Delete_Bucket_Configuration
           (Bucket, Lifecycle_Configuration, Result);
      end if;
   end Delete_Bucket_Lifecycle;

   overriding procedure Put_Bucket_Logging
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      elsif not Valid_Bucket_Logging_Document (Document) then
         Result := Entity_Too_Large;
      else
         Item.State.Put_Bucket_Configuration
           (Bucket, Logging_Configuration, Document, "", Result);
      end if;
   end Put_Bucket_Logging;

   overriding procedure Get_Bucket_Logging
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
      Ignored_Metadata : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Configuration
           (Bucket, Logging_Configuration, Document, Ignored_Metadata,
            Configured, Result);
      end if;
   end Get_Bucket_Logging;

   procedure Put_Named_Bucket_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Kind       : Named_Configuration_Kind;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Bucket_Named_Configuration (Identifier, "")
      then
         Result := Invalid_Request;
      elsif not Valid_Bucket_Named_Configuration (Identifier, Document) then
         Result := Entity_Too_Large;
      else
         Item.State.Put_Named_Bucket_Configuration
           (Bucket, Kind, Identifier, Document, Result);
      end if;
   end Put_Named_Bucket_Configuration;

   procedure Get_Named_Bucket_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Kind       : Named_Configuration_Kind;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Bucket_Named_Configuration (Identifier, "")
      then
         Result := Invalid_Request;
      else
         Item.State.Get_Named_Bucket_Configuration
           (Bucket, Kind, Identifier, Document, Configured, Result);
      end if;
   end Get_Named_Bucket_Configuration;

   procedure Delete_Named_Bucket_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Kind       : Named_Configuration_Kind;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Bucket_Named_Configuration (Identifier, "")
      then
         Result := Invalid_Request;
      else
         Item.State.Delete_Named_Bucket_Configuration
           (Bucket, Kind, Identifier, Result);
      end if;
   end Delete_Named_Bucket_Configuration;

   overriding procedure Put_Bucket_Analytics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is
   begin
      Put_Named_Bucket_Configuration
        (Item, Bucket, Analytics_Configuration, Identifier, Document,
         Token, Deadline, Result);
   end Put_Bucket_Analytics_Configuration;

   overriding procedure Get_Bucket_Analytics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is
   begin
      Get_Named_Bucket_Configuration
        (Item, Bucket, Analytics_Configuration, Identifier, Token, Deadline,
         Document, Configured, Result);
   end Get_Bucket_Analytics_Configuration;

   overriding procedure Delete_Bucket_Analytics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is
   begin
      Delete_Named_Bucket_Configuration
        (Item, Bucket, Analytics_Configuration, Identifier, Token, Deadline,
         Result);
   end Delete_Bucket_Analytics_Configuration;

   overriding procedure Put_Bucket_Metrics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is
   begin
      Put_Named_Bucket_Configuration
        (Item, Bucket, Metrics_Configuration, Identifier, Document,
         Token, Deadline, Result);
   end Put_Bucket_Metrics_Configuration;

   overriding procedure Get_Bucket_Metrics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is
   begin
      Get_Named_Bucket_Configuration
        (Item, Bucket, Metrics_Configuration, Identifier, Token, Deadline,
         Document, Configured, Result);
   end Get_Bucket_Metrics_Configuration;

   overriding procedure Delete_Bucket_Metrics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is
   begin
      Delete_Named_Bucket_Configuration
        (Item, Bucket, Metrics_Configuration, Identifier, Token, Deadline,
         Result);
   end Delete_Bucket_Metrics_Configuration;

   overriding procedure Put_Bucket_Public_Access_Block
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Public_Access_Block_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_Public_Access_Block
           (Bucket, Configuration, Result);
      end if;
   end Put_Bucket_Public_Access_Block;

   overriding procedure Get_Bucket_Public_Access_Block
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Public_Access_Block_Configuration;
      Configured    : out Boolean;
      Result        : out Status)
   is
   begin
      Configuration := (others => <>);
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Public_Access_Block
           (Bucket, Configuration, Configured, Result);
      end if;
   end Get_Bucket_Public_Access_Block;

   overriding procedure Delete_Bucket_Public_Access_Block
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
         Item.State.Delete_Bucket_Public_Access_Block (Bucket, Result);
      end if;
   end Delete_Bucket_Public_Access_Block;

   overriding procedure Put_Bucket_Policy
     (Item     : in out Store;
      Bucket   : String;
      Policy   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_Policy (Bucket, Policy, Result);
      end if;
   end Put_Bucket_Policy;

   overriding procedure Get_Bucket_Policy
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Policy     : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status)
   is
   begin
      Policy := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Policy
           (Bucket, Policy, Configured, Result);
      end if;
   end Get_Bucket_Policy;

   overriding procedure Delete_Bucket_Policy
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
         Item.State.Delete_Bucket_Policy (Bucket, Result);
      end if;
   end Delete_Bucket_Policy;

   overriding procedure Put_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Versioning_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status;
      MFA_Validated : Boolean := False)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Put_Bucket_Versioning
           (Bucket, Configuration, Result, MFA_Validated);
      end if;
   end Put_Bucket_Versioning;

   overriding procedure Get_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status)
   is
   begin
      Configuration := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.Get_Bucket_Versioning
           (Bucket, Configuration, Result);
      end if;
   end Get_Bucket_Versioning;

   overriding procedure Put_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Identity : out Version_Identity;
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions)
   is
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
      Last     : Ada.Streams.Stream_Element_Offset;
      Finished : Boolean := False;
      Data     : Owned_Bytes;
      Declared : Source_Length := (Kind => Unknown);
      Stored   : Object_Information;
      Hash     : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
      Direct_Hash : Checksum_Engine.Context
        (Checksum_Engine.Algorithm_Value
           (if Options.Checksum.Algorithm = No_Checksum
            then Checksum_CRC64NVME else Options.Checksum.Algorithm));
   begin
      Info := Empty_Info;
      Identity := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Object_Metadata
          (Options.Metadata, Ada.Strings.Unbounded.To_String
             (Options.Content_Type))
        or else not Valid_Object_Tag_Set (Options.Tags)
        or else
          (Options.Checksum /= No_Checksum_Information
           and then not Checksum_Engine.Valid_Direct_Configuration
             (Options.Checksum))
      then
         Result := Invalid_Request;
         return;
      elsif Evaluate_Write_Conditions
        (Conditions, Exists => False, Entity_Tag => "") = Invalid_Request
      then
         Result := Invalid_Request;
         return;
      end if;
      Check_Context (Token, Deadline);
      Declared := Source.Declared_Length;
      Check_Context (Token, Deadline);
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
         Check_Context (Token, Deadline);
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
            if Options.Checksum.Algorithm /= No_Checksum then
               Checksum_Engine.Update
                 (Direct_Hash, Buffer (Buffer'First .. Last));
            end if;
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
         Version      => Ada.Strings.Unbounded.Null_Unbounded_String,
         Checksum     =>
           (if Options.Checksum.Algorithm = No_Checksum
            then No_Checksum_Information
            else
              (Algorithm => Options.Checksum.Algorithm,
               Method    => Full_Object_Checksum,
               Value     => Ada.Strings.Unbounded.To_Unbounded_String
                 (Checksum_Engine.Finish (Direct_Hash)))),
         Metadata     => Options.Metadata);
      Item.State.Commit
        (Bucket => Bucket,
         Key    => Key,
         Data   => Data,
         Info   => Stored,
         Tags   => Options.Tags,
         Conditions => Conditions,
         Stored => Info,
         Identity => Identity,
         Result => Result);
      Release_Buffer (Item.State, Data);
   exception
      when others =>
         Release_Buffer (Item.State, Data);
         Identity := (others => <>);
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
      Source_Identity    : out Version_Identity;
      Destination_Identity : out Version_Identity;
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
      Source_Tags   : Object_Tag_Set;
      Selected_Source : Version_Identity;
      Published_Destination : Version_Identity;
      Put_Options_Value : Put_Options;
   begin
      Info := Empty_Info;
      Source_Identity := (others => <>);
      Destination_Identity := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Source_Bucket)
        or else not Valid_Object_Key (Source_Key)
        or else not Valid_Bucket_Name (Destination_Bucket)
        or else not Valid_Object_Key (Destination_Key)
        or else not Valid_Version_Selector (Options.Source_Selector)
        or else not Valid_Copy_Conditions (Options.Conditions)
        or else not Valid_Write_Conditions (Options.Destination_Conditions)
        or else not Valid_Object_Metadata
          (Options.Metadata, Ada.Strings.Unbounded.To_String
             (Options.Content_Type))
        or else not Valid_Object_Tag_Set (Options.Tags)
      then
         Result := Invalid_Request;
         return;
      elsif Source_Bucket = Destination_Bucket
        and then Source_Key = Destination_Key
        and then Options.Metadata_Directive = Copy_Metadata
        and then Options.Tagging_Directive = Copy_Tags
        and then Options.Selected_Checksum = No_Checksum
        and then not Options.Metadata.Website_Redirect_Location.Is_Set
      then
         Result := Invalid_Request;
         return;
      end if;

      Item.State.Fetch
        (Source_Bucket, Source_Key, Options.Source_Selector, Snapshot,
         Source_Info, Source_Tags, Selected_Source, Result);
      if Result = Bucket_Not_Found then
         Result := Source_Bucket_Not_Found;
         return;
      elsif Result = Not_Found then
         Result := Source_Not_Found;
         return;
      elsif Result /= Success then
         return;
      elsif not Valid_Copy_Object_Size (Source_Info.Size) then
         Result := Entity_Too_Large;
         Release_Buffer (Item.State, Snapshot);
         return;
      end if;
      Result := Evaluate_Copy_Conditions
        (Options.Conditions,
         Ada.Strings.Unbounded.To_String (Source_Info.Entity_Tag),
         Source_Info.Modified);
      if Result /= Success then
         Release_Buffer (Item.State, Snapshot);
         return;
      end if;

      Put_Options_Value :=
        (Entity_Tag   => Ada.Strings.Unbounded.Null_Unbounded_String,
         Content_Type =>
           (if Options.Metadata_Directive = Copy_Metadata
            then Source_Info.Content_Type
            else Options.Content_Type),
         Metadata =>
           (if Options.Metadata_Directive = Copy_Metadata
            then Source_Info.Metadata else Options.Metadata),
         Tags     =>
           (if Options.Tagging_Directive = Copy_Tags
            then Source_Tags else Options.Tags),
         Checksum =>
           (Algorithm =>
              (if Options.Selected_Checksum /= No_Checksum
               then Options.Selected_Checksum
               elsif Source_Info.Checksum.Algorithm /= No_Checksum
               then Source_Info.Checksum.Algorithm
               else Checksum_CRC64NVME),
            Method => Full_Object_Checksum,
            Value  => Ada.Strings.Unbounded.Null_Unbounded_String));
      if Options.Metadata_Directive = Copy_Metadata then
         Put_Options_Value.Metadata.Website_Redirect_Location :=
           Options.Metadata.Website_Redirect_Location;
      end if;
      declare
         Source : Snapshot_Source :=
           (Data => Snapshot'Access, Position => 0);
      begin
         Item.Put_Object
           (Destination_Bucket, Destination_Key, Source,
            Put_Options_Value, Token, Deadline, Info, Published_Destination,
            Result,
            Options.Destination_Conditions);
      end;
      if Result = Success then
         Source_Identity := Selected_Source;
         Destination_Identity := Published_Destination;
      end if;
      Release_Buffer (Item.State, Snapshot);
   exception
      when others =>
         Release_Buffer (Item.State, Snapshot);
         Source_Identity := (others => <>);
         Destination_Identity := (others => <>);
         raise;
   end Copy_Object;

   overriding procedure Head_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector)
   is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Version_Selector (Selector)
      then
         Info := Empty_Info;
         Result := Invalid_Request;
      else
         Item.State.Head (Bucket, Key, Selector, Info, Result);
         Check_Context (Token, Deadline);
         if Result = Success then
            Result := Evaluate_Read_Conditions
              (Conditions,
               Ada.Strings.Unbounded.To_String (Info.Entity_Tag),
               Info.Modified);
         end if;
      end if;
   end Head_Object;

   overriding procedure Get_Object_Attributes
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Options  : Object_Attribute_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Snapshot : out Object_Attribute_Snapshot;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector)
   is
   begin
      Snapshot := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Version_Selector (Selector)
      then
         Result := Invalid_Request;
      else
         Item.State.Attributes
           (Bucket, Key, Selector, Options, Conditions, Snapshot, Result);
         Check_Context (Token, Deadline);
      end if;
   end Get_Object_Attributes;

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
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector)
   is
      Data       : Owned_Bytes;
      Resolution : Range_Resolution;
      Send_Count : Byte_Count := 0;
      First      : Byte_Count := 0;
      Sent       : Byte_Count := 0;
      Buffer     : Ada.Streams.Stream_Element_Array (1 .. 16 * 1_024);
      Ignored_Tags : Object_Tag_Set;
      Ignored_Identity : Version_Identity;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Version_Selector (Selector)
      then
         Info := Empty_Info;
         Result := Invalid_Request;
         return;
      end if;
      Item.State.Fetch
        (Bucket, Key, Selector, Data, Info, Ignored_Tags, Ignored_Identity,
         Result);
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
      Result   : out Status;
      Conditions : Delete_Object_Conditions :=
        No_Delete_Object_Conditions;
      Requirements : Delete_Objects_Requirements := (others => <>))
   is
      Entries  : Delete_Object_Entries;
      Outcomes : Delete_Object_Outcomes;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else
          ((not Conditions.Has_ETag
            and then Ada.Strings.Unbounded.Length (Conditions.ETag) > 0)
           or else
             (Conditions.Has_ETag
              and then not Valid_Object_Delete_ETag_Condition
                (Ada.Strings.Unbounded.To_String (Conditions.ETag))))
      then
         Result := Invalid_Request;
         return;
      end if;
      Entries.Append
        (Delete_Object_Entry'
           (Key => Ada.Strings.Unbounded.To_Unbounded_String (Key),
            Selector => Current_Version_Selector,
            Conditions => Conditions));
      Item.Delete_Objects
        (Bucket, Entries, Requirements, Token, Deadline, Outcomes, Result);
      if Result = Success then
         if Outcomes.Length /= 1 then
            raise Program_Error with
              "single delete returned an invalid outcome count";
         end if;
         Result := Outcomes.First_Element.Result;
      end if;
   end Delete_Object;

   overriding procedure Delete_Selected_Object
     (Item          : in out Store;
      Bucket        : String;
      Key           : String;
      Selector      : Version_Selector;
      Conditions    : Delete_Object_Conditions;
      MFA_Validated : Boolean;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Outcome       : out Version_Delete_Outcome;
      Result        : out Status)
   is
   begin
      Outcome := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Version_Selector (Selector)
        or else
          ((not Conditions.Has_ETag
            and then Ada.Strings.Unbounded.Length (Conditions.ETag) > 0)
           or else
             (Conditions.Has_ETag
              and then not Valid_Object_Delete_ETag_Condition
                (Ada.Strings.Unbounded.To_String (Conditions.ETag))))
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.State.Delete_Selected
        (Bucket, Key, Selector, Conditions, MFA_Validated,
         Current_Unix_Time, Outcome, Result);
   end Delete_Selected_Object;

   overriding procedure Delete_Objects
     (Item     : in out Store;
      Bucket   : String;
      Entries  : Delete_Object_Entries;
      Requirements : Delete_Objects_Requirements;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Outcomes : out Delete_Object_Outcomes;
      Result   : out Status)
   is
   begin
      Outcomes.Clear;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else Entries.Is_Empty
        or else Entries.Length > Maximum_Delete_Objects
      then
         Result := Invalid_Request;
         return;
      end if;
      for Request_Entry of Entries loop
         if not Valid_Object_Key
           (Ada.Strings.Unbounded.To_String (Request_Entry.Key))
           or else not Valid_Version_Selector (Request_Entry.Selector)
           or else
             ((not Request_Entry.Conditions.Has_ETag
               and then Ada.Strings.Unbounded.Length
                 (Request_Entry.Conditions.ETag) > 0)
              or else
                (Request_Entry.Conditions.Has_ETag
                 and then not Valid_Object_Delete_ETag_Condition
                   (Ada.Strings.Unbounded.To_String
                      (Request_Entry.Conditions.ETag))))
         then
            Result := Invalid_Request;
            return;
         end if;
      end loop;
      Outcomes.Reserve_Capacity (Entries.Length);
      Item.State.Delete_Many
        (Bucket, Entries, Requirements, Current_Unix_Time, Outcomes, Result);
   end Delete_Objects;

   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector) is
   begin
      Identity := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) or else not Valid_Object_Key (Key)
        or else not Valid_Object_Tag_Set (Tags)
        or else not Valid_Version_Selector (Selector)
      then
         Result := Invalid_Request;
      else
         Item.State.Put_Tags
           (Bucket, Key, Selector, Tags, Identity, Result);
      end if;
   end Put_Object_Tags;

   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector) is
   begin
      Tags := Empty_Object_Tags;
      Identity := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Version_Selector (Selector)
      then
         Result := Invalid_Request;
      else
         Item.State.Get_Tags
           (Bucket, Key, Selector, Tags, Identity, Result);
      end if;
   end Get_Object_Tags;

   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector) is
   begin
      Identity := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Version_Selector (Selector)
      then
         Result := Invalid_Request;
      else
         Item.State.Delete_Tags
           (Bucket, Key, Selector, Identity, Result);
      end if;
   end Delete_Object_Tags;

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

   overriding procedure List_Object_Versions
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Versions_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Versions_Page;
      Result   : out Status)
   is
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Item.State.List_Versions (Bucket, Options, Page, Result);
      end if;
      Check_Context (Token, Deadline);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Page := (others => <>);
         Result := Backend_Unavailable;
   end List_Object_Versions;

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
        or else not Checksum_Engine.Valid_Configuration (Options.Checksum)
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
      Options     : Multipart_Part_Options;
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
      ETag_Hash : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
      Upload_Options : Multipart_Options;
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
      Item.State.Multipart_Configuration
        (Bucket, Key, Upload_ID, Upload_Options, Result);
      if Result /= Success then
         return;
      elsif not Checksum_Engine.Valid_Configuration
        (Upload_Options.Checksum)
      then
         Result := Backend_Unavailable;
         return;
      elsif Options.Expected_Checksum.Algorithm /= No_Checksum
        and then
          (Options.Expected_Checksum.Algorithm /=
             Upload_Options.Checksum.Algorithm
           or else Options.Expected_Checksum.Method /=
             Upload_Options.Checksum.Method
           or else not Checksum_Engine.Valid_Digest
             (Ada.Strings.Unbounded.To_String
                (Options.Expected_Checksum.Value),
              Options.Expected_Checksum.Algorithm))
      then
         Result := Invalid_Request;
         return;
      end if;
      declare
         Effective_Algorithm : constant Checksum_Algorithm :=
           (if Upload_Options.Checksum.Algorithm = No_Checksum
            then Checksum_CRC64NVME
            else Upload_Options.Checksum.Algorithm);
         Digest_Hash : Checksum_Engine.Context
           (Checksum_Engine.Algorithm_Value (Effective_Algorithm));
         Actual_Checksum : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Check_Context (Token, Deadline);
         Declared := Source.Declared_Length;
         Check_Context (Token, Deadline);
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
            Check_Context (Token, Deadline);
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
                  GNAT.MD5.Update (ETag_Hash, Buffer (Buffer'First .. Last));
                  if Upload_Options.Checksum.Algorithm /= No_Checksum then
                     Checksum_Engine.Update
                       (Digest_Hash, Buffer (Buffer'First .. Last));
                  end if;
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
         if Upload_Options.Checksum.Algorithm /= No_Checksum then
            Actual_Checksum := Ada.Strings.Unbounded.To_Unbounded_String
              (Checksum_Engine.Finish (Digest_Hash));
         end if;
         if Options.Expected_Checksum.Algorithm /= No_Checksum
           and then Options.Expected_Checksum.Value /= Actual_Checksum
         then
            Result := Bad_Digest;
            Release_Buffer (Item.State, Data);
            return;
         end if;
         Stored :=
           (Size         => Byte_Count (Data.Length),
            Modified     => Current_Unix_Time,
            Entity_Tag   => Ada.Strings.Unbounded.To_Unbounded_String
              (GNAT.MD5.Digest (ETag_Hash)),
            Content_Type => Ada.Strings.Unbounded.Null_Unbounded_String,
            Version      => Ada.Strings.Unbounded.Null_Unbounded_String,
            Checksum     =>
              (if Upload_Options.Checksum.Algorithm = No_Checksum
               then No_Checksum_Information
               else (Algorithm => Upload_Options.Checksum.Algorithm,
                     Method    => Upload_Options.Checksum.Method,
                     Value     => Actual_Checksum)),
            Metadata     => (others => <>));
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
      end;
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
        or else not Valid_Copy_Conditions (Conditions)
      then
         Result := Invalid_Request;
         return;
      end if;

      Item.State.Fetch_Range
        (Source_Bucket, Source_Key, Requested,
         Snapshot, Source_Info, Result);
      if Result = Bucket_Not_Found then
         Result := Source_Bucket_Not_Found;
         return;
      elsif Result = Not_Found then
         Result := Source_Not_Found;
         return;
      elsif Result /= Success then
         return;
      end if;
      Result := Evaluate_Copy_Conditions
        (Conditions,
         Ada.Strings.Unbounded.To_String (Source_Info.Entity_Tag),
         Source_Info.Modified);
      if Result /= Success then
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
      Options   : Complete_Multipart_Options;
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
        (Bucket, Key, Upload_ID, Parts, Options, Current_Unix_Time, Info,
         Result);
   end Complete_Multipart_Upload;

   overriding procedure Abort_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Conditions : Abort_Multipart_Conditions;
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
      Item.State.Abort_Multipart
        (Bucket, Key, Upload_ID, Conditions, Result);
   end Abort_Multipart_Upload;

   function Bytes_Used (Item : Store) return Byte_Count is
     (Item.State.Used_Bytes);

end Flyology.Object_Storage.Backends.Memory;
