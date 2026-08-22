with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Containers;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Flyology.IO;
with Flyology.Object_Storage.Backends.Bucket_Listing;
with Flyology.Object_Storage.Backends.Listing;
with Flyology.Object_Storage.Backends.Multipart_Listing;
with Flyology.Object_Storage.Durability;
with GNAT.MD5;
with GNAT.OS_Lib;
with GNAT.SHA256;

package body Flyology.Object_Storage.Backends.Files is

   use type Ada.Directories.File_Kind;
   use type Ada.Calendar.Time;
   use type Ada.Real_Time.Time;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;

   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   Epoch : constant Ada.Calendar.Time :=
     Ada.Calendar.Formatting.Time_Of
       (1970, 1, 1, 0, 0, 0, Time_Zone => 0);
   Legacy_Magic : constant String := "FOSOBJ01";
   Magic : constant String := "FOSOBJ02";
   Maximum_Metadata_Length : constant Natural := 8 * 1_024;
   Maximum_Object_Path_Depth : constant Natural := 32;
   Body_Size_Position : constant SIO.Positive_Count := 29;
   Metadata_Position  : constant SIO.Positive_Count := 37;
   Empty_Info : constant Object_Information := (others => <>);

   protected body Sequence is
      procedure Next (Value : out Long_Long_Integer) is
      begin
         if Sequence.Value = Long_Long_Integer'Last then
            Sequence.Value := 1;
         else
            Sequence.Value := Sequence.Value + 1;
         end if;
         Value := Sequence.Value;
      end Next;
   end Sequence;

   protected body Publication_Gate is
      entry Acquire when not Held is
      begin
         Held := True;
      end Acquire;

      procedure Release is
      begin
         Held := False;
      end Release;
   end Publication_Gate;

   function Join (Left, Right : String) return String is
     (Ada.Directories.Compose (Left, Right));

   procedure Sync_Directory (Item : Store; Path : String) is
   begin
      if Item.Commit = Power_Loss_Durable then
         Durability.Sync_Directory (Path);
      end if;
   end Sync_Directory;

   procedure Sync_File (Item : Store; Path : String) is
   begin
      if Item.Commit = Power_Loss_Durable then
         Durability.Sync_File (Path);
      end if;
   end Sync_File;

   procedure Ensure_Directory (Item : Store; Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         if GNAT.OS_Lib.Is_Symbolic_Link (Path)
           or else Ada.Directories.Kind (Path) /= Ada.Directories.Directory
         then
            raise Ada.IO_Exceptions.Name_Error;
         end if;
         return;
      end if;
      declare
         Parent : constant String := Ada.Directories.Containing_Directory
           (Path);
      begin
         if Parent = Path or else Parent'Length = 0 then
            raise Ada.IO_Exceptions.Name_Error;
         end if;
         Ensure_Directory (Item, Parent);
         Ada.Directories.Create_Directory (Path);
         Sync_Directory (Item, Path);
         Sync_Directory (Item, Parent);
      end;
   end Ensure_Directory;

   procedure Remove_Tree (Item : Store; Path : String) is
      Parent : constant String := Ada.Directories.Containing_Directory (Path);
   begin
      if GNAT.OS_Lib.Is_Symbolic_Link (Path) then
         raise Ada.IO_Exceptions.Name_Error;
      end if;
      Ada.Directories.Delete_Tree (Path);
      Sync_Directory (Item, Parent);
   end Remove_Tree;

   function Root_Directory (Item : Store) return String is
     (US.To_String (Item.Root_Path));

   function Buckets_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "buckets"));

   function Bucket_Path (Item : Store; Bucket : String) return String is
     (Join (Buckets_Path (Item), Bucket));

   function Objects_Path (Item : Store; Bucket : String) return String is
     (Join (Bucket_Path (Item, Bucket), "objects"));

   function Temp_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "tmp"));

   function Multipart_Path (Item : Store; Bucket : String) return String is
     (Join (Bucket_Path (Item, Bucket), "multipart"));

   function Upload_Path
     (Item : Store; Bucket : String; Upload_ID : String) return String is
     (Join (Multipart_Path (Item, Bucket), GNAT.SHA256.Digest (Upload_ID)));

   function Manifest_Path
     (Item : Store; Bucket : String; Upload_ID : String) return String is
     (Join (Upload_Path (Item, Bucket, Upload_ID), "upload.fos"));

   function Part_Path
     (Item        : Store;
      Bucket      : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number) return String is
     (Join
        (Upload_Path (Item, Bucket, Upload_ID),
         "part-" & Ada.Strings.Fixed.Trim
           (Multipart_Part_Number'Image (Part_Number), Ada.Strings.Both) &
         ".fos"));

   function Part_Number_From_Name
     (Name : String) return Multipart_Part_Number
   is
      Prefix : constant String := "part-";
      Suffix : constant String := ".fos";
      First  : constant Integer := Name'First + Prefix'Length;
      Last   : constant Integer := Name'Last - Suffix'Length;
      Value  : Natural := 0;
   begin
      if Name'Length <= Prefix'Length + Suffix'Length
        or else Name (Name'First .. First - 1) /= Prefix
        or else Name (Last + 1 .. Name'Last) /= Suffix
        or else (Last > First and then Name (First) = '0')
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      for Index in First .. Last loop
         if Name (Index) not in '0' .. '9'
           or else Value >
             (Multipart_Part_Number'Last -
                (Character'Pos (Name (Index)) - Character'Pos ('0'))) / 10
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         Value := Value * 10 +
           (Character'Pos (Name (Index)) - Character'Pos ('0'));
      end loop;
      if Value not in Multipart_Part_Number'Range then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      return Multipart_Part_Number (Value);
   end Part_Number_From_Name;

   function Part_Before
     (Left, Right : Listed_Multipart_Part) return Boolean is
     (Left.Number < Right.Number);

   package Multipart_Part_Sorting is new
     Listed_Multipart_Part_Vectors.Generic_Sorting ("<" => Part_Before);

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

   procedure Acquire_Publication
     (Item     : in out Store;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      Wake     : Ada.Real_Time.Time;
      Acquired : Boolean := False;
   begin
      loop
         Check_Context (Token, Deadline);
         Wake := Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (10);
         if Deadline /= Ada.Real_Time.Time_Last and then Deadline < Wake then
            Wake := Deadline;
         end if;
         select
            Item.Publication.Acquire;
            Acquired := True;
            Check_Context (Token, Deadline);
            return;
         or
            delay until Wake;
         end select;
      end loop;
   exception
      when others =>
         if Acquired then
            Item.Publication.Release;
         end if;
         raise;
   end Acquire_Publication;

   function Hex (Value : Natural) return Character is
      Hexadecimal : constant String := "0123456789ABCDEF";
   begin
      return Hexadecimal (Value + 1);
   end Hex;

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
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      for Index in Digest'Range loop
         declare
            High : constant Natural := Hex_Nibble
              (Entity_Tag (Entity_Tag'First + 2 * (Index - 1)));
            Low : constant Natural := Hex_Nibble
              (Entity_Tag (Entity_Tag'First + 2 * (Index - 1) + 1));
         begin
            if High > 15 or else Low > 15 then
               raise Ada.IO_Exceptions.Data_Error;
            end if;
            Digest (Index) := Character'Val (16 * High + Low);
         end;
      end loop;
      GNAT.MD5.Update (Hash, Digest);
   end Include_Part_Digest;

   function Object_Path
     (Item : Store; Bucket : String; Key : String) return String
   is
      Result  : US.Unbounded_String :=
        US.To_Unbounded_String (Objects_Path (Item, Bucket));
      Segment : String (1 .. 100);
      Used    : Natural := 0;
   begin
      for Character_Value of Key loop
         Segment (Used + 1) :=
           Hex (Character'Pos (Character_Value) / 16);
         Segment (Used + 2) :=
           Hex (Character'Pos (Character_Value) mod 16);
         Used := Used + 2;
         if Used = Segment'Length then
            US.Set_Unbounded_String
              (Result, Join (US.To_String (Result), Segment));
            Used := 0;
         end if;
      end loop;
      if Used = 0 then
         return US.To_String (Result) & ".fos";
      else
         return Join
           (US.To_String (Result), Segment (1 .. Used) & ".fos");
      end if;
   end Object_Path;

   function Valid_Options (Options : Put_Options) return Boolean is
     (US.Length (Options.Entity_Tag) <= Maximum_Metadata_Length
      and then US.Length (Options.Content_Type) <= Maximum_Metadata_Length);

   procedure Write_Bytes
     (File : in out SIO.File_Type;
      Data : Ada.Streams.Stream_Element_Array)
   is
   begin
      if Data'Length > 0 then
         SIO.Write (File, Data);
      end if;
   end Write_Bytes;

   procedure Write_String (File : in out SIO.File_Type; Value : String) is
      Data : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Value'Length));
      Position : Ada.Streams.Stream_Element_Offset := Data'First;
   begin
      for Character_Value of Value loop
         Data (Position) :=
           Ada.Streams.Stream_Element (Character'Pos (Character_Value));
         Position := Position + 1;
      end loop;
      Write_Bytes (File, Data);
   end Write_String;

   procedure Write_U32 (File : in out SIO.File_Type; Value : Natural) is
      Data : Ada.Streams.Stream_Element_Array (1 .. 4);
      Work : Long_Long_Integer := Long_Long_Integer (Value);
   begin
      for Index in reverse Data'Range loop
         Data (Index) := Ada.Streams.Stream_Element (Work mod 256);
         Work := Work / 256;
      end loop;
      SIO.Write (File, Data);
   end Write_U32;

   procedure Write_U64
     (File : in out SIO.File_Type; Value : Long_Long_Integer)
   is
      Data : Ada.Streams.Stream_Element_Array (1 .. 8);
      Work : Long_Long_Integer := Value;
   begin
      if Value < 0 then
         raise Constraint_Error;
      end if;
      for Index in reverse Data'Range loop
         Data (Index) := Ada.Streams.Stream_Element (Work mod 256);
         Work := Work / 256;
      end loop;
      SIO.Write (File, Data);
   end Write_U64;

   procedure Read_Exact
     (File : in out SIO.File_Type;
      Data : out Ada.Streams.Stream_Element_Array)
   is
      Last : Ada.Streams.Stream_Element_Offset;
   begin
      if Data'Length = 0 then
         return;
      end if;
      SIO.Read (File, Data, Last);
      if Last /= Data'Last then
         raise Ada.IO_Exceptions.End_Error;
      end if;
   end Read_Exact;

   function Read_U32 (File : in out SIO.File_Type) return Natural is
      Data   : Ada.Streams.Stream_Element_Array (1 .. 4);
      Result : Long_Long_Integer := 0;
   begin
      Read_Exact (File, Data);
      for Value of Data loop
         Result := Result * 256 + Long_Long_Integer (Value);
      end loop;
      if Result > Long_Long_Integer (Natural'Last) then
         raise Constraint_Error;
      end if;
      return Natural (Result);
   end Read_U32;

   function Read_U64
     (File : in out SIO.File_Type) return Long_Long_Integer
   is
      Data   : Ada.Streams.Stream_Element_Array (1 .. 8);
      Result : Long_Long_Integer := 0;
   begin
      Read_Exact (File, Data);
      for Value of Data loop
         if Result > (Long_Long_Integer'Last - Long_Long_Integer (Value)) / 256
         then
            raise Constraint_Error;
         end if;
         Result := Result * 256 + Long_Long_Integer (Value);
      end loop;
      return Result;
   end Read_U64;

   function Read_String
     (File : in out SIO.File_Type; Length : Natural) return String
   is
      Result : String (1 .. Length);
      Data   : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Length));
   begin
      Read_Exact (File, Data);
      for Index in Result'Range loop
         Result (Index) := Character'Val
           (Data
              (Data'First
               + Ada.Streams.Stream_Element_Offset (Index - Result'First)));
      end loop;
      return Result;
   end Read_String;

   function Unix_Seconds
     (Value : Ada.Calendar.Time) return Long_Long_Integer is
     (Long_Long_Integer (Value - Epoch));

   procedure Write_Header
     (File : in out SIO.File_Type;
      Key  : String;
      Info : Object_Information;
      Tags : Object_Tag_Set := Empty_Object_Tags)
   is
      ETag : constant String := US.To_String (Info.Entity_Tag);
      Kind : constant String := US.To_String (Info.Content_Type);
   begin
      Write_String (File, Magic);
      Write_U32 (File, Key'Length);
      Write_U32 (File, ETag'Length);
      Write_U32 (File, Kind'Length);
      Write_U64 (File, Long_Long_Integer (Info.Modified));
      Write_U64 (File, Long_Long_Integer (Info.Size));
      Write_String (File, Key);
      Write_String (File, ETag);
      Write_String (File, Kind);
      Write_U32 (File, Tags.Length);
      for Index in 1 .. Tags.Length loop
         declare
            Tag_Key : constant String := US.To_String (Tags.Items (Index).Key);
            Tag_Value : constant String :=
              US.To_String (Tags.Items (Index).Value);
         begin
            Write_U32 (File, Tag_Key'Length);
            Write_U32 (File, Tag_Value'Length);
            Write_String (File, Tag_Key);
            Write_String (File, Tag_Value);
         end;
      end loop;
   end Write_Header;

   procedure Read_Header_Any_With_Tags
     (File      : in out SIO.File_Type;
      Key       : out US.Unbounded_String;
      Info      : out Object_Information;
      Tags      : out Object_Tag_Set;
      Body_At   : out SIO.Positive_Count)
   is
      File_Magic : constant String := Read_String (File, Magic'Length);
      Key_Length : constant Natural := Read_U32 (File);
      ETag_Length : constant Natural := Read_U32 (File);
      Kind_Length : constant Natural := Read_U32 (File);
      Modified : constant Long_Long_Integer := Read_U64 (File);
      Size : constant Long_Long_Integer := Read_U64 (File);
   begin
      Tags := Empty_Object_Tags;
      if File_Magic not in Magic | Legacy_Magic
        or else Key_Length not in 1 .. 1_024
        or else ETag_Length > Maximum_Metadata_Length
        or else Kind_Length > Maximum_Metadata_Length
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      declare
         Key_Value : constant String := Read_String (File, Key_Length);
         ETag : constant String := Read_String (File, ETag_Length);
         Kind : constant String := Read_String (File, Kind_Length);
      begin
         Key := US.To_Unbounded_String (Key_Value);
         Info :=
           (Size         => Byte_Count (Size),
            Modified     => Unix_Time (Modified),
            Entity_Tag   => US.To_Unbounded_String (ETag),
            Content_Type => US.To_Unbounded_String (Kind),
            Version      => US.Null_Unbounded_String);
         if File_Magic = Magic then
            declare
               Tag_Count : constant Natural := Read_U32 (File);
            begin
               if Tag_Count > Maximum_Object_Tags then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
               Tags.Length := Object_Tag_Count (Tag_Count);
               for Index in 1 .. Tags.Length loop
                  declare
                     Key_Size : constant Natural := Read_U32 (File);
                     Value_Size : constant Natural := Read_U32 (File);
                  begin
                     if Key_Size not in 1 .. 512
                       or else Value_Size > 1_024
                     then
                        raise Ada.IO_Exceptions.Data_Error;
                     end if;
                     Tags.Items (Index) :=
                       (Key => US.To_Unbounded_String
                          (Read_String (File, Key_Size)),
                        Value => US.To_Unbounded_String
                          (Read_String (File, Value_Size)));
                  end;
               end loop;
               if not Valid_Object_Tag_Set (Tags) then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
            end;
         end if;
         Body_At := SIO.Index (File);
         if SIO.Count (Info.Size) > SIO.Count'Last - (Body_At - 1)
           or else SIO.Size (File) /= Body_At - 1 + SIO.Count (Info.Size)
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
      end;
   end Read_Header_Any_With_Tags;

   procedure Read_Header_Any
     (File      : in out SIO.File_Type;
      Key       : out US.Unbounded_String;
      Info      : out Object_Information;
      Body_At   : out SIO.Positive_Count)
   is
      Tags : Object_Tag_Set;
   begin
      Read_Header_Any_With_Tags (File, Key, Info, Tags, Body_At);
   end Read_Header_Any;

   procedure Read_Header_With_Tags
     (File      : in out SIO.File_Type;
      Expected  : String;
      Info      : out Object_Information;
      Tags      : out Object_Tag_Set;
      Body_At   : out SIO.Positive_Count)
   is
      Key : US.Unbounded_String;
   begin
      Read_Header_Any_With_Tags (File, Key, Info, Tags, Body_At);
      if US.To_String (Key) /= Expected then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
   end Read_Header_With_Tags;

   procedure Read_Header
     (File      : in out SIO.File_Type;
      Expected  : String;
      Info      : out Object_Information;
      Body_At   : out SIO.Positive_Count)
   is
      Key : US.Unbounded_String;
   begin
      Read_Header_Any (File, Key, Info, Body_At);
      if US.To_String (Key) /= Expected then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
   end Read_Header;

   procedure Read_Manifest
     (Item      : Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : out Multipart_Options;
      Created   : out Unix_Time)
   is
      File    : SIO.File_Type;
      Info    : Object_Information;
      Body_At : SIO.Positive_Count;
   begin
      SIO.Open (File, SIO.In_File, Manifest_Path (Item, Bucket, Upload_ID));
      Read_Header (File, Key, Info, Body_At);
      SIO.Close (File);
      if Info.Size /= 0
        or else US.To_String (Info.Entity_Tag) /= Upload_ID
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Options.Content_Type := Info.Content_Type;
      Created := Info.Modified;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_Manifest;

   procedure Read_Manifest
     (Item      : Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : out Multipart_Options)
   is
      Created : Unix_Time;
   begin
      Read_Manifest (Item, Bucket, Key, Upload_ID, Options, Created);
   end Read_Manifest;

   function Has_Objects
     (Directory : String; Depth : Natural := 0) return Boolean
   is
      Search : Ada.Directories.Search_Type;
      Directory_Entry : Ada.Directories.Directory_Entry_Type;
      Filter : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => True,
         Ada.Directories.Special_File  => False);
   begin
      if Depth > Maximum_Object_Path_Depth then
         raise Ada.IO_Exceptions.Data_Error;
      elsif not Ada.Directories.Exists (Directory) then
         return False;
      elsif Ada.Directories.Kind (Directory) /= Ada.Directories.Directory then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Ada.Directories.Start_Search (Search, Directory, "", Filter);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Directory_Entry);
         declare
            Name : constant String :=
              Ada.Directories.Simple_Name (Directory_Entry);
            Full : constant String :=
              Ada.Directories.Full_Name (Directory_Entry);
         begin
            if Ada.Directories.Kind (Directory_Entry)
              = Ada.Directories.Ordinary_File
            then
               Ada.Directories.End_Search (Search);
               return True;
            elsif Name /= "." and then Name /= ".."
              and then Has_Objects (Full, Depth + 1)
            then
               Ada.Directories.End_Search (Search);
               return True;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      return False;
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Has_Objects;

   function Open
     (Root                : String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last;
      Commit              : Commit_Policy := Power_Loss_Durable) return Store
   is
      Full : US.Unbounded_String;
   begin
      if Root'Length = 0 then
         raise Configuration_Error;
      end if;
      return Result : Store do
         Result.Commit := Commit;
         Ensure_Directory (Result, Root);
         Full := US.To_Unbounded_String (Ada.Directories.Full_Name (Root));
         Result.Root_Path := Full;
         Result.Maximum_Object_Size := Maximum_Object_Size;
         Ensure_Directory (Result, Join (US.To_String (Full), "buckets"));
         if Ada.Directories.Exists (Join (US.To_String (Full), "tmp")) then
            if GNAT.OS_Lib.Is_Symbolic_Link
              (Join (US.To_String (Full), "tmp"))
              or else Ada.Directories.Kind
                (Join (US.To_String (Full), "tmp")) /=
                  Ada.Directories.Directory
            then
               raise Configuration_Error;
            end if;
            Ada.Directories.Delete_Tree (Join (US.To_String (Full), "tmp"));
            Sync_Directory (Result, US.To_String (Full));
         end if;
         Ensure_Directory (Result, Join (US.To_String (Full), "tmp"));
         Sync_Directory (Result, US.To_String (Full));
      end return;
   exception
      when Configuration_Error =>
         raise;
      when others =>
         raise Configuration_Error;
   end Open;

   overriding procedure Create_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
      Path    : constant String := Bucket_Path (Item, Bucket);
      Locked  : Boolean := False;
      Staged  : US.Unbounded_String;
      Number  : Long_Long_Integer;
      Renamed : Boolean := False;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if Ada.Directories.Exists (Path) then
         Result := Already_Exists;
      else
         Item.Temp_Sequence.Next (Number);
         Staged := US.To_Unbounded_String
           (Join
              (Temp_Path (Item),
               "bucket-" & GNAT.SHA256.Digest
                 (Bucket & Long_Long_Integer'Image (Number) &
                  Ada.Calendar.Time'Image (Ada.Calendar.Clock))));
         Ensure_Directory
           (Item,
            Join (US.To_String (Staged), "objects"));
         Ensure_Directory
           (Item,
            Join (US.To_String (Staged), "multipart"));
         GNAT.OS_Lib.Rename_File (US.To_String (Staged), Path, Renamed);
         if Renamed then
            Sync_Directory (Item, Buckets_Path (Item));
            Sync_Directory (Item, Temp_Path (Item));
            Result := Success;
         else
            Ada.Directories.Delete_Tree (US.To_String (Staged));
            Sync_Directory (Item, Temp_Path (Item));
            Staged := US.Null_Unbounded_String;
            Result := Backend_Unavailable;
         end if;
      end if;
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Locked then
            Item.Publication.Release;
         end if;
         begin
            if US.Length (Staged) > 0
              and then Ada.Directories.Exists (US.To_String (Staged))
            then
               Ada.Directories.Delete_Tree (US.To_String (Staged));
            end if;
         exception
            when others => null;
         end;
         raise;
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
         begin
            if US.Length (Staged) > 0
              and then Ada.Directories.Exists (US.To_String (Staged))
            then
               Ada.Directories.Delete_Tree (US.To_String (Staged));
            end if;
         exception
            when others => null;
         end;
         Result := Backend_Unavailable;
   end Create_Bucket;

   overriding procedure List_Buckets
     (Item     : in out Store;
      Options  : List_Buckets_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out Bucket_Page;
      Result   : out Status)
   is
      Builder        : Bucket_Listing.Builder;
      Search         : Ada.Directories.Search_Type;
      Directory_Item : Ada.Directories.Directory_Entry_Type;
      Searching      : Boolean := False;
      Locked         : Boolean := False;
      Filter         : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => False,
         Ada.Directories.Directory     => True,
         Ada.Directories.Special_File  => False);
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      Bucket_Listing.Initialize (Builder, Options);
      Ada.Directories.Start_Search
        (Search, Buckets_Path (Item), "*", Filter);
      Searching := True;
      while Ada.Directories.More_Entries (Search) loop
         Check_Context (Token, Deadline);
         Ada.Directories.Get_Next_Entry (Search, Directory_Item);
         declare
            Name : constant String :=
              Ada.Directories.Simple_Name (Directory_Item);
            Full : constant String :=
              Ada.Directories.Full_Name (Directory_Item);
            Created : constant Long_Long_Integer := Unix_Seconds
              (Ada.Directories.Modification_Time (Directory_Item));
         begin
            if Name /= "." and then Name /= ".." then
               if not Valid_Bucket_Name (Name)
                 or else Created < 0
                 or else not Ada.Directories.Exists (Join (Full, "objects"))
                 or else Ada.Directories.Kind (Join (Full, "objects")) /=
                   Ada.Directories.Directory
                 or else not Ada.Directories.Exists
                   (Join (Full, "multipart"))
                 or else Ada.Directories.Kind (Join (Full, "multipart")) /=
                   Ada.Directories.Directory
               then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
               Bucket_Listing.Consider
                 (Builder, Name, Unix_Time (Created));
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      Searching := False;
      Page := Bucket_Listing.Finish (Builder);
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Searching then
            Ada.Directories.End_Search (Search);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Searching then
            Ada.Directories.End_Search (Search);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Page := (others => <>);
         Result := Backend_Unavailable;
   end List_Buckets;

   overriding procedure Head_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
      Path : constant String := Bucket_Path (Item, Bucket);
      Locked : Boolean := False;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      Result :=
        (if Ada.Directories.Exists (Path)
           and then Ada.Directories.Kind (Path) = Ada.Directories.Directory
         then Success else Not_Found);
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
         Result := Backend_Unavailable;
   end Head_Bucket;

   overriding procedure Delete_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
      Path : constant String := Bucket_Path (Item, Bucket);
      Locked : Boolean := False;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Path) then
         Result := Not_Found;
      elsif Has_Objects (Join (Path, "objects"))
        or else Has_Objects (Join (Path, "multipart"))
      then
         Result := Bucket_Not_Empty;
      else
         Ada.Directories.Delete_Tree (Path);
         Sync_Directory (Item, Buckets_Path (Item));
         Result := Success;
      end if;
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
         Result := Backend_Unavailable;
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
      Buffer   : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last     : Ada.Streams.Stream_Element_Offset;
      Finished : Boolean := False;
      Total    : Byte_Count := 0;
      File     : SIO.File_Type;
      Opened   : Boolean := False;
      Published : Boolean := False;
      Number   : Long_Long_Integer;
      Declared : Source_Length := (Kind => Unknown);
      Target   : constant String := Object_Path (Item, Bucket, Key);
      Temp     : US.Unbounded_String;
      Rename_Succeeded : Boolean;
      Locked   : Boolean := False;
      In_Callback : Boolean := False;
      Generate_ETag : constant Boolean := US.Length (Options.Entity_Tag) = 0;
      Hash : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Options (Options)
      then
         Result := Invalid_Request;
         return;
      elsif not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Not_Found;
         return;
      end if;
      In_Callback := True;
      Declared := Source.Declared_Length;
      In_Callback := False;
      if Declared.Kind = Known
        and then Declared.Bytes > Maximum_Multipart_Part_Size
      then
         Result := Entity_Too_Large;
         return;
      elsif Declared.Kind = Known
        and then Declared.Bytes > Item.Maximum_Object_Size
      then
         Result := Capacity_Exceeded;
         return;
      end if;

      Item.Temp_Sequence.Next (Number);
      Temp := US.To_Unbounded_String
        (Join
           (Temp_Path (Item),
            GNAT.SHA256.Digest
              (Bucket & Character'Val (0) & Key
               & Long_Long_Integer'Image (Number)
               & Ada.Calendar.Time'Image (Ada.Calendar.Clock))
            & ".tmp"));
      SIO.Create (File, SIO.Out_File, US.To_String (Temp));
      Opened := True;
      Info :=
        (Size         => 0,
         Modified     => Unix_Time (Unix_Seconds (Ada.Calendar.Clock)),
         Entity_Tag   =>
           (if Generate_ETag
            then US.To_Unbounded_String (String'(1 .. 32 => '0'))
            else Options.Entity_Tag),
         Content_Type => Options.Content_Type,
         Version      => US.Null_Unbounded_String);
      Write_Header (File, Key, Info);

      while not Finished loop
         Check_Context (Token, Deadline);
         In_Callback := True;
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         In_Callback := False;
         if Last < Buffer'First - 1 or else Last > Buffer'Last then
            Result := Invalid_Request;
            SIO.Close (File);
            Opened := False;
            Ada.Directories.Delete_File (US.To_String (Temp));
            return;
         elsif Last >= Buffer'First then
            declare
               Count : constant Byte_Count :=
                 Byte_Count (Last - Buffer'First + 1);
            begin
               if Count > Maximum_Multipart_Part_Size
                 or else Total > Maximum_Multipart_Part_Size - Count
               then
                  Result := Entity_Too_Large;
                  SIO.Close (File);
                  Opened := False;
                  Ada.Directories.Delete_File (US.To_String (Temp));
                  return;
               elsif Count > Item.Maximum_Object_Size
                 or else Total > Item.Maximum_Object_Size - Count
               then
                  Result := Capacity_Exceeded;
                  SIO.Close (File);
                  Opened := False;
                  Ada.Directories.Delete_File (US.To_String (Temp));
                  return;
               end if;
               SIO.Write (File, Buffer (Buffer'First .. Last));
               GNAT.MD5.Update (Hash, Buffer (Buffer'First .. Last));
               Total := Total + Count;
            end;
         elsif not Finished then
            Result := Invalid_Request;
            SIO.Close (File);
            Opened := False;
            Ada.Directories.Delete_File (US.To_String (Temp));
            return;
         end if;
      end loop;
      if Declared.Kind = Known and then Declared.Bytes /= Total then
         Result := Invalid_Request;
         SIO.Close (File);
         Opened := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         return;
      end if;

      Info.Size := Total;
      if Generate_ETag then
         Info.Entity_Tag := US.To_Unbounded_String (GNAT.MD5.Digest (Hash));
         SIO.Set_Index
           (File, Metadata_Position + SIO.Count (Key'Length));
         Write_String (File, US.To_String (Info.Entity_Tag));
      end if;
      SIO.Set_Index (File, Body_Size_Position);
      Write_U64 (File, Long_Long_Integer (Total));
      SIO.Close (File);
      Opened := False;
      Sync_File (Item, US.To_String (Temp));
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         Result := Not_Found;
         return;
      end if;
      Ensure_Directory
        (Item, Ada.Directories.Containing_Directory (Target));
      GNAT.OS_Lib.Rename_File
        (US.To_String (Temp), Target, Rename_Succeeded);
      if not Rename_Succeeded then
         Item.Publication.Release;
         Locked := False;
         Result := Backend_Unavailable;
         Ada.Directories.Delete_File (US.To_String (Temp));
         return;
      end if;
      Published := True;
      Sync_Directory
        (Item, Ada.Directories.Containing_Directory (Target));
      Sync_Directory (Item, Temp_Path (Item));
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         Info := Empty_Info;
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
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
      type File_Source is limited new Byte_Source with record
         File      : access SIO.File_Type;
         Total     : Byte_Count := 0;
         Remaining : Byte_Count := 0;
      end record;

      overriding function Declared_Length
        (Source : File_Source) return Source_Length is
        (Kind => Known, Bytes => Source.Total);

      overriding procedure Read
        (Source   : in out File_Source;
         Buffer   : out Ada.Streams.Stream_Element_Array;
         Last     : out Ada.Streams.Stream_Element_Offset;
         Finished : out Boolean;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time)
      is
         Count : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset
             (Byte_Count'Min
                (Source.Remaining, Byte_Count (Buffer'Length)));
      begin
         Check_Context (Token, Deadline);
         if Count = 0 then
            Last := Buffer'First - 1;
         else
            declare
               Slice_Last : constant Ada.Streams.Stream_Element_Offset :=
                 Buffer'First + Count - 1;
            begin
               SIO.Read
                 (Source.File.all, Buffer (Buffer'First .. Slice_Last), Last);
               if Last /= Slice_Last then
                  raise Ada.IO_Exceptions.End_Error;
               end if;
            end;
            Source.Remaining := Source.Remaining - Byte_Count (Count);
         end if;
         Finished := Source.Remaining = 0;
      end Read;

      File        : aliased SIO.File_Type;
      Source_Info : Object_Information;
      Body_At     : SIO.Positive_Count;
      Source_Path : US.Unbounded_String;
      Locked      : Boolean := False;
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

      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      Source_Path := US.To_Unbounded_String
        (Object_Path (Item, Source_Bucket, Source_Key));
      if not Ada.Directories.Exists (US.To_String (Source_Path)) then
         Item.Publication.Release;
         Locked := False;
         Result := Source_Not_Found;
         return;
      end if;

      SIO.Open (File, SIO.In_File, US.To_String (Source_Path));
      Read_Header (File, Source_Key, Source_Info, Body_At);
      Item.Publication.Release;
      Locked := False;
      if not Copy_Conditions_Accept
        (Options.Conditions, US.To_String (Source_Info.Entity_Tag))
      then
         SIO.Close (File);
         Result := Precondition_Failed;
         return;
      end if;
      SIO.Set_Index (File, Body_At);
      Put_Options_Value :=
        (Entity_Tag   => US.Null_Unbounded_String,
         Content_Type =>
           (if Options.Metadata_Directive = Copy_Metadata
            then Source_Info.Content_Type
            else Options.Content_Type));
      declare
         Source : File_Source :=
           (File      => File'Access,
            Total     => Source_Info.Size,
            Remaining => Source_Info.Size);
      begin
         Item.Put_Object
           (Destination_Bucket, Destination_Key, Source,
            Put_Options_Value, Token, Deadline, Info, Result);
      end;
      SIO.Close (File);
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Info := Empty_Info;
         Result := Backend_Unavailable;
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
      File : SIO.File_Type;
      Body_At : SIO.Positive_Count;
      Path : constant String := Object_Path (Item, Bucket, Key);
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
      elsif not Ada.Directories.Exists (Path) then
         Result := Not_Found;
      else
         SIO.Open (File, SIO.In_File, Path);
         Read_Header (File, Key, Info, Body_At);
         SIO.Close (File);
         Result := Success;
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Info := Empty_Info;
         Result := Backend_Unavailable;
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
      File      : SIO.File_Type;
      Body_At   : SIO.Positive_Count;
      Path      : constant String := Object_Path (Item, Bucket, Key);
      Resolution : Range_Resolution;
      First      : Byte_Count := 0;
      Remaining : Byte_Count;
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      In_Callback : Boolean := False;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) or else not Valid_Object_Key (Key) then
         Result := Invalid_Request;
         return;
      elsif not Ada.Directories.Exists (Path) then
         Result := Not_Found;
         return;
      end if;
      SIO.Open (File, SIO.In_File, Path);
      Read_Header (File, Key, Info, Body_At);
      Result := Evaluate_Read_Conditions
        (Conditions, US.To_String (Info.Entity_Tag), Info.Modified);
      if Result /= Success then
         SIO.Close (File);
         return;
      end if;
      Resolution := Resolve_Range (Info.Size, Requested);
      if Resolution.Kind = Empty_Object_Range then
         SIO.Close (File);
         In_Callback := True;
         Sink.Begin_Object (Info, 0, 0, False, Token, Deadline);
         In_Callback := False;
         Result := Success;
         return;
      elsif Resolution.Kind = Unsatisfiable_Range then
         SIO.Close (File);
         Result := Invalid_Range;
         return;
      end if;
      First := Resolution.First;
      Remaining := Resolution.Length;
      In_Callback := True;
      Sink.Begin_Object
        (Info,
         First,
         Remaining,
         Requested.Kind /= Whole_Range,
         Token,
         Deadline);
      In_Callback := False;
      SIO.Set_Index
        (File, Body_At + SIO.Count (First));
      while Remaining > 0 loop
         Check_Context (Token, Deadline);
         declare
            Count : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset
                (Byte_Count'Min (Remaining, Byte_Count (Buffer'Length)));
            Last : Ada.Streams.Stream_Element_Offset;
         begin
            SIO.Read (File, Buffer (1 .. Count), Last);
            if Last /= Count then
               raise Ada.IO_Exceptions.End_Error;
            end if;
            In_Callback := True;
            Sink.Write (Buffer (1 .. Count), Token, Deadline);
            In_Callback := False;
            Remaining := Remaining - Byte_Count (Count);
         end;
      end loop;
      SIO.Close (File);
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         Info := Empty_Info;
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
   end Get_Object;

   overriding procedure Delete_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
      Path : constant String := Object_Path (Item, Bucket, Key);
      Locked : Boolean := False;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Bucket_Not_Found;
      elsif not Ada.Directories.Exists (Path) then
         Result := Not_Found;
      else
         Ada.Directories.Delete_File (Path);
         Sync_Directory
           (Item, Ada.Directories.Containing_Directory (Path));
         Result := Success;
      end if;
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
         Result := Backend_Unavailable;
   end Delete_Object;

   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status)
   is
      Path      : constant String := Object_Path (Item, Bucket, Key);
      Source    : SIO.File_Type;
      Staged    : SIO.File_Type;
      Source_Open : Boolean := False;
      Staged_Open : Boolean := False;
      Locked    : Boolean := False;
      Published : Boolean := False;
      Temp      : US.Unbounded_String;
      Number    : Long_Long_Integer;
      Info      : Object_Information;
      Old_Tags  : Object_Tag_Set;
      Body_At   : SIO.Positive_Count;
      Remaining : Byte_Count;
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last      : Ada.Streams.Stream_Element_Offset;
      Renamed   : Boolean;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) or else not Valid_Object_Key (Key)
        or else not Valid_Object_Tag_Set (Tags)
      then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Bucket_Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      elsif not Ada.Directories.Exists (Path) then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;

      SIO.Open (Source, SIO.In_File, Path);
      Source_Open := True;
      Read_Header_With_Tags (Source, Key, Info, Old_Tags, Body_At);
      Item.Temp_Sequence.Next (Number);
      Temp := US.To_Unbounded_String
        (Join
           (Temp_Path (Item),
            GNAT.SHA256.Digest
              (Bucket & Character'Val (0) & Key & ".tags" &
               Long_Long_Integer'Image (Number) &
               Ada.Calendar.Time'Image (Ada.Calendar.Clock)) & ".tmp"));
      SIO.Create (Staged, SIO.Out_File, US.To_String (Temp));
      Staged_Open := True;
      Write_Header (Staged, Key, Info, Tags);
      SIO.Set_Index (Source, Body_At);
      Remaining := Info.Size;
      while Remaining > 0 loop
         Check_Context (Token, Deadline);
         declare
            Count : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset
                (Byte_Count'Min (Remaining, Byte_Count (Buffer'Length)));
         begin
            SIO.Read (Source, Buffer (1 .. Count), Last);
            if Last /= Count then
               raise Ada.IO_Exceptions.End_Error;
            end if;
            SIO.Write (Staged, Buffer (1 .. Count));
            Remaining := Remaining - Byte_Count (Count);
         end;
      end loop;
      SIO.Close (Source);
      Source_Open := False;
      SIO.Close (Staged);
      Staged_Open := False;
      Sync_File (Item, US.To_String (Temp));
      GNAT.OS_Lib.Rename_File (US.To_String (Temp), Path, Renamed);
      if not Renamed then
         Ada.Directories.Delete_File (US.To_String (Temp));
         Item.Publication.Release;
         Locked := False;
         Result := Backend_Unavailable;
         return;
      end if;
      Published := True;
      Sync_Directory (Item, Ada.Directories.Containing_Directory (Path));
      Sync_Directory (Item, Temp_Path (Item));
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Source_Open then
            SIO.Close (Source);
         end if;
         if Staged_Open then
            SIO.Close (Staged);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         raise;
      when others =>
         if Source_Open then
            SIO.Close (Source);
         end if;
         if Staged_Open then
            SIO.Close (Staged);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         Result := Backend_Unavailable;
   end Put_Object_Tags;

   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Result : out Status)
   is
      Path    : constant String := Object_Path (Item, Bucket, Key);
      File    : SIO.File_Type;
      Key_In_File : US.Unbounded_String;
      Info    : Object_Information;
      Body_At : SIO.Positive_Count;
      Locked  : Boolean := False;
   begin
      Tags := Empty_Object_Tags;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Bucket_Not_Found;
      elsif not Ada.Directories.Exists (Path) then
         Result := Not_Found;
      else
         SIO.Open (File, SIO.In_File, Path);
         Read_Header_Any_With_Tags (File, Key_In_File, Info, Tags, Body_At);
         SIO.Close (File);
         if US.To_String (Key_In_File) /= Key then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         Result := Success;
      end if;
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Tags := Empty_Object_Tags;
         Result := Backend_Unavailable;
   end Get_Object_Tags;

   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status)
   is
   begin
      Put_Object_Tags
        (Item, Bucket, Key, Empty_Object_Tags, Token, Deadline, Result);
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
      Builder : Listing.Builder;
      Locked  : Boolean := False;

      procedure Consider_File (Path : String) is
         File    : SIO.File_Type;
         Key     : US.Unbounded_String;
         Info    : Object_Information;
         Body_At : SIO.Positive_Count;
      begin
         SIO.Open (File, SIO.In_File, Path);
         Read_Header_Any (File, Key, Info, Body_At);
         SIO.Close (File);
         if not Valid_Object_Key (US.To_String (Key))
           or else Path /= Object_Path (Item, Bucket, US.To_String (Key))
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         Listing.Consider (Builder, US.To_String (Key), Info);
      exception
         when others =>
            if SIO.Is_Open (File) then
               SIO.Close (File);
            end if;
            raise;
      end Consider_File;

      procedure Visit (Directory : String; Depth : Natural := 0) is
         Search          : Ada.Directories.Search_Type;
         Directory_Entry : Ada.Directories.Directory_Entry_Type;
         Started         : Boolean := False;
         Filter          : constant Ada.Directories.Filter_Type :=
           (Ada.Directories.Ordinary_File => True,
            Ada.Directories.Directory     => True,
            Ada.Directories.Special_File  => False);
      begin
         if Depth > Maximum_Object_Path_Depth then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         Ada.Directories.Start_Search (Search, Directory, "", Filter);
         Started := True;
         while Ada.Directories.More_Entries (Search) loop
            Check_Context (Token, Deadline);
            Ada.Directories.Get_Next_Entry (Search, Directory_Entry);
            declare
               Name : constant String :=
                 Ada.Directories.Simple_Name (Directory_Entry);
               Full : constant String :=
                 Ada.Directories.Full_Name (Directory_Entry);
               Kind : constant Ada.Directories.File_Kind :=
                 Ada.Directories.Kind (Directory_Entry);
            begin
               if Kind = Ada.Directories.Directory
                 and then Name /= "." and then Name /= ".."
               then
                  Visit (Full, Depth + 1);
               elsif Kind = Ada.Directories.Ordinary_File
                 and then Name'Length >= 4
                 and then Name (Name'Last - 3 .. Name'Last) = ".fos"
               then
                  Consider_File (Full);
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Started := False;
      exception
         when others =>
            if Started then
               Ada.Directories.End_Search (Search);
            end if;
            raise;
      end Visit;
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Not_Found;
      else
         Listing.Initialize (Builder, Options);
         Visit (Objects_Path (Item, Bucket));
         Page := Listing.Finish (Builder);
         Result := Success;
      end if;
      Item.Publication.Release;
      Locked := False;
      Check_Context (Token, Deadline);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
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
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      Locked    : Boolean := False;
      Published : Boolean := False;
      Renamed   : Boolean := False;
      Number    : Long_Long_Integer;
      Directory : US.Unbounded_String;
      Staged    : US.Unbounded_String;
      Manifest  : US.Unbounded_String;
      Manifest_Info : Object_Information;
   begin
      Upload_ID := US.Null_Unbounded_String;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else US.Length (Options.Content_Type) > Maximum_Metadata_Length
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.Temp_Sequence.Next (Number);
      Upload_ID := US.To_Unbounded_String
        (GNAT.SHA256.Digest
           (Bucket & Character'Val (0) & Key & Character'Val (0) &
            Long_Long_Integer'Image (Number) &
            Ada.Calendar.Time'Image (Ada.Calendar.Clock)));
      Directory := US.To_Unbounded_String
        (Upload_Path (Item, Bucket, US.To_String (Upload_ID)));
      Staged := US.To_Unbounded_String
        (Join (Temp_Path (Item), "upload-" & US.To_String (Upload_ID)));
      Manifest := US.To_Unbounded_String
        (Join (US.To_String (Staged), "upload.fos"));
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      elsif Ada.Directories.Exists (US.To_String (Directory)) then
         Result := Conflict;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Ensure_Directory (Item, US.To_String (Staged));
      Manifest_Info :=
        (Size         => 0,
         Modified     => Unix_Time (Unix_Seconds (Ada.Calendar.Clock)),
         Entity_Tag   => Upload_ID,
         Content_Type => Options.Content_Type,
         Version      => US.Null_Unbounded_String);
      SIO.Create (File, SIO.Out_File, US.To_String (Manifest));
      Opened := True;
      Write_Header (File, Key, Manifest_Info);
      SIO.Close (File);
      Opened := False;
      Sync_File (Item, US.To_String (Manifest));
      Sync_Directory (Item, US.To_String (Staged));
      GNAT.OS_Lib.Rename_File
        (US.To_String (Staged), US.To_String (Directory), Renamed);
      if not Renamed then
         Item.Publication.Release;
         Locked := False;
         Remove_Tree (Item, US.To_String (Staged));
         Staged := US.Null_Unbounded_String;
         Upload_ID := US.Null_Unbounded_String;
         Result := Backend_Unavailable;
         return;
      end if;
      Published := True;
      Sync_Directory (Item, Multipart_Path (Item, Bucket));
      Sync_Directory (Item, Temp_Path (Item));
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Staged) > 0
           and then Ada.Directories.Exists (US.To_String (Staged))
         then
            Remove_Tree (Item, US.To_String (Staged));
         end if;
         Upload_ID := US.Null_Unbounded_String;
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Staged) > 0
           and then Ada.Directories.Exists (US.To_String (Staged))
         then
            Remove_Tree (Item, US.To_String (Staged));
         end if;
         Upload_ID := US.Null_Unbounded_String;
         Result := Backend_Unavailable;
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
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last      : Ada.Streams.Stream_Element_Offset;
      Finished  : Boolean := False;
      Total     : Byte_Count := 0;
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      Published : Boolean := False;
      Locked    : Boolean := False;
      In_Callback : Boolean := False;
      Number    : Long_Long_Integer;
      Declared  : Source_Length := (Kind => Unknown);
      Temp      : US.Unbounded_String;
      Target    : US.Unbounded_String;
      Renamed   : Boolean;
      Hash      : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
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
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists
        (Manifest_Path (Item, Bucket, Upload_ID))
      then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Read_Manifest (Item, Bucket, Key, Upload_ID, Upload_Options);
      Item.Publication.Release;
      Locked := False;

      In_Callback := True;
      Declared := Source.Declared_Length;
      In_Callback := False;
      if Declared.Kind = Known
        and then Declared.Bytes > Item.Maximum_Object_Size
      then
         Result := Capacity_Exceeded;
         return;
      end if;
      Item.Temp_Sequence.Next (Number);
      Temp := US.To_Unbounded_String
        (Join
           (Temp_Path (Item),
            GNAT.SHA256.Digest
              (Upload_ID & Multipart_Part_Number'Image (Part_Number) &
               Long_Long_Integer'Image (Number) &
               Ada.Calendar.Time'Image (Ada.Calendar.Clock)) & ".part"));
      Target := US.To_Unbounded_String
        (Part_Path (Item, Bucket, Upload_ID, Part_Number));
      SIO.Create (File, SIO.Out_File, US.To_String (Temp));
      Opened := True;
      Info :=
        (Size         => 0,
         Modified     => Unix_Time (Unix_Seconds (Ada.Calendar.Clock)),
         Entity_Tag   => US.To_Unbounded_String (String'(1 .. 32 => '0')),
         Content_Type => US.Null_Unbounded_String,
         Version      => US.Null_Unbounded_String);
      Write_Header (File, Key, Info);
      while not Finished loop
         Check_Context (Token, Deadline);
         In_Callback := True;
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         In_Callback := False;
         if Last < Buffer'First - 1 or else Last > Buffer'Last then
            Result := Invalid_Request;
            SIO.Close (File);
            Opened := False;
            Ada.Directories.Delete_File (US.To_String (Temp));
            return;
         elsif Last >= Buffer'First then
            declare
               Count : constant Byte_Count :=
                 Byte_Count (Last - Buffer'First + 1);
            begin
               if Count > Item.Maximum_Object_Size
                 or else Total > Item.Maximum_Object_Size - Count
               then
                  Result := Capacity_Exceeded;
                  SIO.Close (File);
                  Opened := False;
                  Ada.Directories.Delete_File (US.To_String (Temp));
                  return;
               end if;
               SIO.Write (File, Buffer (Buffer'First .. Last));
               GNAT.MD5.Update (Hash, Buffer (Buffer'First .. Last));
               Total := Total + Count;
            end;
         elsif not Finished then
            Result := Invalid_Request;
            SIO.Close (File);
            Opened := False;
            Ada.Directories.Delete_File (US.To_String (Temp));
            return;
         end if;
      end loop;
      if Declared.Kind = Known and then Declared.Bytes /= Total then
         Result := Invalid_Request;
         SIO.Close (File);
         Opened := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         return;
      end if;
      Info.Size := Total;
      Info.Entity_Tag := US.To_Unbounded_String (GNAT.MD5.Digest (Hash));
      SIO.Set_Index (File, Metadata_Position + SIO.Count (Key'Length));
      Write_String (File, US.To_String (Info.Entity_Tag));
      SIO.Set_Index (File, Body_Size_Position);
      Write_U64 (File, Long_Long_Integer (Total));
      SIO.Close (File);
      Opened := False;
      Sync_File (Item, US.To_String (Temp));

      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists
        (Manifest_Path (Item, Bucket, Upload_ID))
      then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         Result := Not_Found;
         return;
      end if;
      Read_Manifest (Item, Bucket, Key, Upload_ID, Upload_Options);
      GNAT.OS_Lib.Rename_File
        (US.To_String (Temp), US.To_String (Target), Renamed);
      if not Renamed then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         Result := Backend_Unavailable;
         return;
      end if;
      Published := True;
      Sync_Directory
        (Item, Ada.Directories.Containing_Directory (US.To_String (Target)));
      Sync_Directory (Item, Temp_Path (Item));
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         Info := Empty_Info;
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
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
      Upload_Options : Multipart_Options;
      Search         : Ada.Directories.Search_Type;
      Directory_Item : Ada.Directories.Directory_Entry_Type;
      Filter         : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => False,
         Ada.Directories.Special_File  => False);
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      Searching : Boolean := False;
      Locked    : Boolean := False;
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists
        (Manifest_Path (Item, Bucket, Upload_ID))
      then
         Item.Publication.Release;
         Locked := False;
         Result := Not_Found;
         return;
      end if;
      Read_Manifest (Item, Bucket, Key, Upload_ID, Upload_Options);
      if Options.Maximum = 0
        or else Options.After = Multipart_Part_Marker'Last
      then
         Item.Publication.Release;
         Locked := False;
         Result := Success;
         return;
      end if;
      Ada.Directories.Start_Search
        (Search, Upload_Path (Item, Bucket, Upload_ID), "part-*.fos", Filter);
      Searching := True;
      while Ada.Directories.More_Entries (Search) loop
         Check_Context (Token, Deadline);
         Ada.Directories.Get_Next_Entry (Search, Directory_Item);
         declare
            Number : constant Multipart_Part_Number :=
              Part_Number_From_Name
                (Ada.Directories.Simple_Name (Directory_Item));
         begin
            if Number > Options.After then
               declare
                  Info    : Object_Information;
                  Body_At : SIO.Positive_Count;
               begin
                  SIO.Open
                    (File, SIO.In_File,
                     Ada.Directories.Full_Name (Directory_Item));
                  Opened := True;
                  Read_Header (File, Key, Info, Body_At);
                  SIO.Close (File);
                  Opened := False;
                  Page.Parts.Append
                    (Listed_Multipart_Part'
                       (Number => Number, Info => Info));
               end;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      Searching := False;
      Multipart_Part_Sorting.Sort (Page.Parts);
      if Page.Parts.Length > Ada.Containers.Count_Type (Options.Maximum) then
         Page.Is_Truncated := True;
         while Page.Parts.Length >
           Ada.Containers.Count_Type (Options.Maximum)
         loop
            Page.Parts.Delete_Last;
         end loop;
         Page.Next_After :=
           Multipart_Part_Marker (Page.Parts.Last_Element.Number);
      end if;
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if Searching then
            Ada.Directories.End_Search (Search);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Page := (others => <>);
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Searching then
            Ada.Directories.End_Search (Search);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Page := (others => <>);
         Result := Backend_Unavailable;
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
      Builder        : Multipart_Listing.Builder;
      Search         : Ada.Directories.Search_Type;
      Directory_Item : Ada.Directories.Directory_Entry_Type;
      Filter         : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => False,
         Ada.Directories.Directory     => True,
         Ada.Directories.Special_File  => False);
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      Searching : Boolean := False;
      Locked    : Boolean := False;
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Item.Publication.Release;
         Locked := False;
         Result := Not_Found;
         return;
      end if;
      Multipart_Listing.Initialize (Builder, Options);
      if Ada.Directories.Exists (Multipart_Path (Item, Bucket)) then
         Ada.Directories.Start_Search
           (Search, Multipart_Path (Item, Bucket), "*", Filter);
         Searching := True;
         while Ada.Directories.More_Entries (Search) loop
            Check_Context (Token, Deadline);
            Ada.Directories.Get_Next_Entry (Search, Directory_Item);
            declare
               Manifest : constant String := Join
                 (Ada.Directories.Full_Name (Directory_Item), "upload.fos");
            begin
               if Ada.Directories.Exists (Manifest) then
                  declare
                     Key     : US.Unbounded_String;
                     Info    : Object_Information;
                     Body_At : SIO.Positive_Count;
                  begin
                     SIO.Open (File, SIO.In_File, Manifest);
                     Opened := True;
                     Read_Header_Any (File, Key, Info, Body_At);
                     SIO.Close (File);
                     Opened := False;
                     if Info.Size /= 0
                       or else US.Length (Info.Entity_Tag) = 0
                       or else Ada.Directories.Simple_Name (Directory_Item) /=
                         GNAT.SHA256.Digest
                           (US.To_String (Info.Entity_Tag))
                     then
                        raise Ada.IO_Exceptions.Data_Error;
                     end if;
                     Multipart_Listing.Consider
                       (Builder, US.To_String (Key),
                        US.To_String (Info.Entity_Tag), Info.Modified,
                        Multipart_Options'
                          (Content_Type => Info.Content_Type));
                  end;
               end if;
            end;
         end loop;
         Ada.Directories.End_Search (Search);
         Searching := False;
      end if;
      Page := Multipart_Listing.Finish (Builder);
      Item.Publication.Release;
      Locked := False;
      Result := Success;
      Check_Context (Token, Deadline);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if Searching then
            Ada.Directories.End_Search (Search);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Page := (others => <>);
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Searching then
            Ada.Directories.End_Search (Search);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Page := (others => <>);
         Result := Backend_Unavailable;
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
      type File_Source is limited new Byte_Source with record
         File      : access SIO.File_Type;
         Total     : Byte_Count := 0;
         Remaining : Byte_Count := 0;
      end record;

      overriding function Declared_Length
        (Source : File_Source) return Source_Length is
        (Kind => Known, Bytes => Source.Total);

      overriding procedure Read
        (Source   : in out File_Source;
         Buffer   : out Ada.Streams.Stream_Element_Array;
         Last     : out Ada.Streams.Stream_Element_Offset;
         Finished : out Boolean;
         Token    : access Flyology.Cancellation.Token;
         Deadline : Ada.Real_Time.Time)
      is
         Count : constant Ada.Streams.Stream_Element_Offset :=
           Ada.Streams.Stream_Element_Offset
             (Byte_Count'Min
                (Source.Remaining, Byte_Count (Buffer'Length)));
      begin
         Check_Context (Token, Deadline);
         if Count = 0 then
            Last := Buffer'First - 1;
         else
            declare
               Slice_Last : constant Ada.Streams.Stream_Element_Offset :=
                 Buffer'First + Count - 1;
            begin
               SIO.Read
                 (Source.File.all, Buffer (Buffer'First .. Slice_Last), Last);
               if Last /= Slice_Last then
                  raise Ada.IO_Exceptions.End_Error;
               end if;
            end;
            Source.Remaining := Source.Remaining - Byte_Count (Count);
         end if;
         Finished := Source.Remaining = 0;
      end Read;

      File        : aliased SIO.File_Type;
      Source_Info : Object_Information;
      Body_At     : SIO.Positive_Count;
      Source_Path : US.Unbounded_String;
      Resolution  : Range_Resolution;
      First       : Byte_Count := 0;
      Length      : Byte_Count := 0;
      Locked      : Boolean := False;
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

      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      Source_Path := US.To_Unbounded_String
        (Object_Path (Item, Source_Bucket, Source_Key));
      if not Ada.Directories.Exists (US.To_String (Source_Path)) then
         Item.Publication.Release;
         Locked := False;
         Result := Source_Not_Found;
         return;
      end if;
      SIO.Open (File, SIO.In_File, US.To_String (Source_Path));
      Read_Header (File, Source_Key, Source_Info, Body_At);
      Item.Publication.Release;
      Locked := False;

      if not Copy_Conditions_Accept
        (Conditions, US.To_String (Source_Info.Entity_Tag))
      then
         SIO.Close (File);
         Result := Precondition_Failed;
         return;
      elsif Requested.Kind not in Whole_Range | Bounded_Range then
         SIO.Close (File);
         Result := Invalid_Request;
         return;
      elsif Requested.Kind = Bounded_Range
        and then
          (Requested.First > Requested.Last
           or else Requested.Last >= Source_Info.Size)
      then
         SIO.Close (File);
         Result := Invalid_Range;
         return;
      end if;
      Resolution := Resolve_Range (Source_Info.Size, Requested);
      if Resolution.Kind = Unsatisfiable_Range then
         SIO.Close (File);
         Result := Invalid_Range;
         return;
      elsif Resolution.Kind = Satisfied_Range then
         First := Resolution.First;
         Length := Resolution.Length;
      end if;
      if Length > Maximum_Multipart_Part_Size then
         SIO.Close (File);
         Result := Entity_Too_Large;
         return;
      end if;

      SIO.Set_Index (File, Body_At + SIO.Count (First));
      declare
         Source : File_Source :=
           (File => File'Access, Total => Length, Remaining => Length);
      begin
         Item.Put_Multipart_Part
           (Destination_Bucket, Destination_Key, Upload_ID, Part_Number,
            Source, Token, Deadline, Info, Result);
      end;
      SIO.Close (File);
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Info := Empty_Info;
         Result := Backend_Unavailable;
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
      Buffer      : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last        : Ada.Streams.Stream_Element_Offset;
      File        : SIO.File_Type;
      Part_File   : SIO.File_Type;
      Opened      : Boolean := False;
      Part_Opened : Boolean := False;
      Locked      : Boolean := False;
      Published   : Boolean := False;
      Number      : Long_Long_Integer;
      Temp        : US.Unbounded_String;
      Target      : constant String := Object_Path (Item, Bucket, Key);
      Upload_Options : Multipart_Options;
      Previous    : Multipart_Part_Number := Multipart_Part_Number'First;
      First       : Boolean := True;
      Total       : Byte_Count := 0;
      Hash        : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
      Renamed     : Boolean;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      elsif Parts.Is_Empty then
         Result := Invalid_Request;
         return;
      end if;
      for Reference of Parts loop
         if not First and then Reference.Number <= Previous then
            Result := Invalid_Part_Order;
            return;
         end if;
         Previous := Reference.Number;
         First := False;
      end loop;
      Previous := Multipart_Part_Number'First;
      First := True;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists
        (Manifest_Path (Item, Bucket, Upload_ID))
      then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Read_Manifest (Item, Bucket, Key, Upload_ID, Upload_Options);
      for Index in Parts.First_Index .. Parts.Last_Index loop
         declare
            Reference : constant Multipart_Part_Reference := Parts (Index);
            Path : constant String :=
              Part_Path (Item, Bucket, Upload_ID, Reference.Number);
            Part_Info : Object_Information;
            Body_At : SIO.Positive_Count;
         begin
            if not Ada.Directories.Exists (Path) then
               Result := Invalid_Part;
               Item.Publication.Release;
               Locked := False;
               return;
            end if;
            SIO.Open (Part_File, SIO.In_File, Path);
            Part_Opened := True;
            Read_Header (Part_File, Key, Part_Info, Body_At);
            SIO.Close (Part_File);
            Part_Opened := False;
            if US.To_String (Part_Info.Entity_Tag) /=
              US.To_String (Reference.Entity_Tag)
            then
               Result := Invalid_Part;
               Item.Publication.Release;
               Locked := False;
               return;
            elsif Index /= Parts.Last_Index
              and then Part_Info.Size < 5 * 1_024 * 1_024
            then
               Result := Entity_Too_Small;
               Item.Publication.Release;
               Locked := False;
               return;
            elsif Part_Info.Size > Item.Maximum_Object_Size - Total then
               Result := Capacity_Exceeded;
               Item.Publication.Release;
               Locked := False;
               return;
            end if;
            Total := Total + Part_Info.Size;
            Include_Part_Digest
              (Hash, US.To_String (Part_Info.Entity_Tag));
            Previous := Reference.Number;
            First := False;
         end;
      end loop;

      Info :=
        (Size         => Total,
         Modified     => Unix_Time (Unix_Seconds (Ada.Calendar.Clock)),
         Entity_Tag   => US.To_Unbounded_String
           (GNAT.MD5.Digest (Hash) & "-" &
            Ada.Strings.Fixed.Trim
              (Natural'Image (Natural (Parts.Length)), Ada.Strings.Both)),
         Content_Type => Upload_Options.Content_Type,
         Version      => US.Null_Unbounded_String);
      Item.Temp_Sequence.Next (Number);
      Temp := US.To_Unbounded_String
        (Join
           (Temp_Path (Item),
            GNAT.SHA256.Digest
              (Upload_ID & Long_Long_Integer'Image (Number) &
               Ada.Calendar.Time'Image (Ada.Calendar.Clock)) & ".complete"));
      SIO.Create (File, SIO.Out_File, US.To_String (Temp));
      Opened := True;
      Write_Header (File, Key, Info);
      for Reference of Parts loop
         declare
            Part_Info : Object_Information;
            Body_At   : SIO.Positive_Count;
            Remaining : Byte_Count;
         begin
            SIO.Open
              (Part_File, SIO.In_File,
               Part_Path (Item, Bucket, Upload_ID, Reference.Number));
            Part_Opened := True;
            Read_Header (Part_File, Key, Part_Info, Body_At);
            SIO.Set_Index (Part_File, Body_At);
            Remaining := Part_Info.Size;
            while Remaining > 0 loop
               Check_Context (Token, Deadline);
               declare
                  Count : constant Ada.Streams.Stream_Element_Offset :=
                    Ada.Streams.Stream_Element_Offset
                      (Byte_Count'Min
                         (Remaining, Byte_Count (Buffer'Length)));
               begin
                  SIO.Read
                    (Part_File,
                     Buffer (Buffer'First .. Buffer'First + Count - 1), Last);
                  if Last /= Buffer'First + Count - 1 then
                     raise Ada.IO_Exceptions.End_Error;
                  end if;
                  SIO.Write (File, Buffer (Buffer'First .. Last));
                  Remaining := Remaining - Byte_Count (Count);
               end;
            end loop;
            SIO.Close (Part_File);
            Part_Opened := False;
         end;
      end loop;
      SIO.Close (File);
      Opened := False;
      Sync_File (Item, US.To_String (Temp));
      Ensure_Directory
        (Item, Ada.Directories.Containing_Directory (Target));
      GNAT.OS_Lib.Rename_File (US.To_String (Temp), Target, Renamed);
      if not Renamed then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         Result := Backend_Unavailable;
         return;
      end if;
      Published := True;
      Sync_Directory
        (Item, Ada.Directories.Containing_Directory (Target));
      Sync_Directory (Item, Temp_Path (Item));
      Remove_Tree (Item, Upload_Path (Item, Bucket, Upload_ID));
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Part_Opened then
            SIO.Close (Part_File);
         end if;
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         raise;
      when others =>
         if Part_Opened then
            SIO.Close (Part_File);
         end if;
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         if not Published and then US.Length (Temp) > 0
           and then Ada.Directories.Exists (US.To_String (Temp))
         then
            Ada.Directories.Delete_File (US.To_String (Temp));
         end if;
         Info := Empty_Info;
         Result := Backend_Unavailable;
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
      Options : Multipart_Options;
      Created : Unix_Time;
      Locked  : Boolean := False;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists
        (Manifest_Path (Item, Bucket, Upload_ID))
      then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Read_Manifest (Item, Bucket, Key, Upload_ID, Options, Created);
      if Conditions.Has_Initiated_Time
        and then Created /= Conditions.Initiated_Time
      then
         Result := Precondition_Failed;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Remove_Tree (Item, Upload_Path (Item, Bucket, Upload_ID));
      Item.Publication.Release;
      Locked := False;
      Result := Success;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Locked then
            Item.Publication.Release;
         end if;
         Result := Backend_Unavailable;
   end Abort_Multipart_Upload;

end Flyology.Object_Storage.Backends.Files;
