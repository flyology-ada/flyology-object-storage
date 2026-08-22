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
with Flyology.Object_Storage.Checksum_Engine;
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
   Tag_Magic : constant String := "FOSOBJ02";
   Part_Magic : constant String := "FOSOBJ03";
   Magic : constant String := "FOSOBJ04";
   Bucket_Tag_Magic : constant String := "FOSTAG01";
   Versioning_Magic : constant String := "FOSVER01";
   Maximum_Metadata_Length : constant Natural := 8 * 1_024;
   Maximum_Checksum_Length : constant Natural := 96;
   Maximum_Tag_Key_Bytes : constant Natural :=
     4 * Tags.Maximum_Key_Characters;
   Maximum_Tag_Value_Bytes : constant Natural :=
     4 * Tags.Maximum_Value_Characters;
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

   function Configuration_Path
     (Item : Store; Bucket : String) return String is
     (Join (Bucket_Path (Item, Bucket), "configuration"));

   function Tags_Path (Item : Store; Bucket : String) return String is
     (Join (Configuration_Path (Item, Bucket), "tags.fos"));

   function Versioning_Path (Item : Store; Bucket : String) return String is
     (Join (Configuration_Path (Item, Bucket), "versioning.fos"));

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

   procedure Write_Tags
     (File : in out SIO.File_Type; Value : Tags.Tag_Set)
   is
   begin
      Write_String (File, Bucket_Tag_Magic);
      Write_U32 (File, Natural (Value.Length));
      for Item of Value loop
         declare
            Key  : constant String := US.To_String (Item.Key);
            Text : constant String := US.To_String (Item.Value);
         begin
            Write_U32 (File, Key'Length);
            Write_U32 (File, Text'Length);
            Write_String (File, Key);
            Write_String (File, Text);
         end;
      end loop;
   end Write_Tags;

   procedure Read_Tags
     (File : in out SIO.File_Type; Value : out Tags.Tag_Set)
   is
      File_Magic : constant String :=
        Read_String (File, Bucket_Tag_Magic'Length);
      Count      : constant Natural := Read_U32 (File);
   begin
      Value.Clear;
      if File_Magic /= Bucket_Tag_Magic
        or else Count not in 1 .. Tags.Maximum_Bucket_Tags
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      for Index in 1 .. Count loop
         pragma Unreferenced (Index);
         declare
            Key_Length   : constant Natural := Read_U32 (File);
            Value_Length : constant Natural := Read_U32 (File);
         begin
            if Key_Length not in 1 .. Maximum_Tag_Key_Bytes
              or else Value_Length > Maximum_Tag_Value_Bytes
            then
               raise Ada.IO_Exceptions.Data_Error;
            end if;
            Value.Append
              (Tags.Tag'
                 (Key   => US.To_Unbounded_String
                    (Read_String (File, Key_Length)),
                  Value => US.To_Unbounded_String
                    (Read_String (File, Value_Length))));
         end;
      end loop;
      if SIO.Index (File) /= SIO.Size (File) + 1
        or else not Tags.Valid_Bucket_Tag_Set (Value)
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
   end Read_Tags;

   function Read_Versioning
     (Item : Store; Bucket : String) return Bucket_Versioning_Configuration
   is
      Path : constant String := Versioning_Path (Item, Bucket);
      File : SIO.File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return (others => <>);
      elsif GNAT.OS_Lib.Is_Symbolic_Link (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      SIO.Open (File, SIO.In_File, Path);
      if SIO.Size (File) /= SIO.Count (Versioning_Magic'Length + 2)
        or else Read_String (File, Versioning_Magic'Length) /=
          Versioning_Magic
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      declare
         State : constant String := Read_String (File, 2);
         Value : Bucket_Versioning_Configuration;
      begin
         SIO.Close (File);
         Value.Status :=
           (case State (1) is
               when 'U' => Versioning_Unconfigured,
               when 'E' => Versioning_Enabled,
               when 'S' => Versioning_Suspended,
               when others =>
                  raise Ada.IO_Exceptions.Data_Error);
         Value.MFA_Delete :=
           (case State (2) is
               when 'U' => MFA_Delete_Unconfigured,
               when 'E' => MFA_Delete_Enabled,
               when 'D' => MFA_Delete_Disabled,
               when others =>
                  raise Ada.IO_Exceptions.Data_Error);
         return Value;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_Versioning;

   function Unix_Seconds
     (Value : Ada.Calendar.Time) return Long_Long_Integer is
     (Long_Long_Integer (Value - Epoch));

   procedure Write_Header
     (File : in out SIO.File_Type;
      Key  : String;
      Info : Object_Information;
      Tags : Object_Tag_Set := Empty_Object_Tags;
      Parts : Completed_Object_Part_List :=
        Completed_Object_Part_Vectors.Empty_Vector)
   is
      ETag : constant String := US.To_String (Info.Entity_Tag);
      Kind : constant String := US.To_String (Info.Content_Type);

      procedure Write_Checksum (Value : Checksum_Information) is
         Text : constant String := US.To_String (Value.Value);
         Algorithm_Code : constant Character :=
           (case Value.Algorithm is
              when No_Checksum        => 'N',
              when Checksum_CRC32     => 'A',
              when Checksum_CRC32C    => 'B',
              when Checksum_CRC64NVME => 'C',
              when Checksum_SHA1      => 'D',
              when Checksum_SHA256    => 'E',
              when Checksum_SHA512    => 'F',
              when Checksum_MD5       => 'G',
              when Checksum_XXHASH64  => 'H',
              when Checksum_XXHASH3   => 'I',
              when Checksum_XXHASH128 => 'J');
         Method_Code : constant Character :=
           (case Value.Method is
              when No_Checksum_Method  => 'N',
              when Composite_Checksum  => 'C',
              when Full_Object_Checksum => 'F');
      begin
         if Text'Length > Maximum_Checksum_Length then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         Write_String (File, String'(1 => Algorithm_Code));
         Write_String (File, String'(1 => Method_Code));
         Write_U32 (File, Text'Length);
         Write_String (File, Text);
      end Write_Checksum;
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
      Write_U32 (File, Natural (Parts.Length));
      for Part of Parts loop
         Write_U32 (File, Natural (Part.Number));
         Write_U64 (File, Long_Long_Integer (Part.Size));
         Write_Checksum (Part.Checksum);
      end loop;
      Write_Checksum (Info.Checksum);
   end Write_Header;

   procedure Read_Header_Any_With_Metadata
     (File      : in out SIO.File_Type;
      Key       : out US.Unbounded_String;
      Info      : out Object_Information;
      Tags      : out Object_Tag_Set;
      Parts     : out Completed_Object_Part_List;
      Body_At   : out SIO.Positive_Count)
   is
      File_Magic : constant String := Read_String (File, Magic'Length);
      Key_Length : constant Natural := Read_U32 (File);
      ETag_Length : constant Natural := Read_U32 (File);
      Kind_Length : constant Natural := Read_U32 (File);
      Modified : constant Long_Long_Integer := Read_U64 (File);
      Size : constant Long_Long_Integer := Read_U64 (File);

      function Read_Checksum return Checksum_Information is
         Algorithm_Code : constant Character := Read_String (File, 1) (1);
         Method_Code : constant Character := Read_String (File, 1) (1);
         Length : constant Natural := Read_U32 (File);
         Value : Checksum_Information;
      begin
         if Length > Maximum_Checksum_Length then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         Value.Algorithm :=
           (case Algorithm_Code is
              when 'N' => No_Checksum,
              when 'A' => Checksum_CRC32,
              when 'B' => Checksum_CRC32C,
              when 'C' => Checksum_CRC64NVME,
              when 'D' => Checksum_SHA1,
              when 'E' => Checksum_SHA256,
              when 'F' => Checksum_SHA512,
              when 'G' => Checksum_MD5,
              when 'H' => Checksum_XXHASH64,
              when 'I' => Checksum_XXHASH3,
              when 'J' => Checksum_XXHASH128,
              when others => raise Ada.IO_Exceptions.Data_Error);
         Value.Method :=
           (case Method_Code is
              when 'N' => No_Checksum_Method,
              when 'C' => Composite_Checksum,
              when 'F' => Full_Object_Checksum,
              when others => raise Ada.IO_Exceptions.Data_Error);
         Value.Value := US.To_Unbounded_String (Read_String (File, Length));
         if (Value.Algorithm = No_Checksum) /=
              (Value.Method = No_Checksum_Method)
           or else
             (Value.Algorithm = No_Checksum and then Length /= 0)
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         return Value;
      end Read_Checksum;
   begin
      Tags := Empty_Object_Tags;
      Parts.Clear;
      if File_Magic not in Magic | Part_Magic | Tag_Magic | Legacy_Magic
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
            Version      => US.Null_Unbounded_String,
            Checksum     => (others => <>));
         if File_Magic /= Legacy_Magic then
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
         if File_Magic in Magic | Part_Magic then
            declare
               Count : constant Natural := Read_U32 (File);
               Previous : Multipart_Part_Marker := 0;
               Total : Byte_Count := 0;
            begin
               if Count > Multipart_Part_Number'Last then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
               for Index in 1 .. Count loop
                  declare
                     Number : constant Natural := Read_U32 (File);
                     Size_Value : constant Long_Long_Integer :=
                       Read_U64 (File);
                  begin
                     if Number not in Multipart_Part_Number'Range
                       or else Number <= Previous
                       or else Size_Value < 0
                       or else Byte_Count (Size_Value) >
                         Byte_Count'Last - Total
                     then
                        raise Ada.IO_Exceptions.Data_Error;
                     end if;
                     declare
                        Checksum : constant Checksum_Information :=
                          (if File_Magic = Magic then Read_Checksum
                           else No_Checksum_Information);
                     begin
                        if Checksum.Algorithm /= No_Checksum
                          and then
                            (US.Length (Checksum.Value) = 0
                             or else not Checksum_Engine.Valid_Digest
                               (US.To_String (Checksum.Value),
                                Checksum.Algorithm))
                        then
                           raise Ada.IO_Exceptions.Data_Error;
                        end if;
                        Parts.Append
                          (Completed_Object_Part'
                             (Number => Multipart_Part_Number (Number),
                              Size   => Byte_Count (Size_Value),
                              Checksum => Checksum));
                     end;
                     Previous := Multipart_Part_Marker (Number);
                     Total := Total + Byte_Count (Size_Value);
                  end;
               end loop;
               if Count > 0 and then Total /= Info.Size then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
            end;
         end if;
         if File_Magic = Magic then
            Info.Checksum := Read_Checksum;
            if Info.Checksum.Algorithm /= No_Checksum then
               if Parts.Length > 0 then
                  if US.Length (Info.Checksum.Value) = 0
                    or else not Checksum_Engine.Valid_Object_Digest
                      (US.To_String (Info.Checksum.Value),
                       Info.Checksum.Algorithm, Info.Checksum.Method,
                       Positive (Parts.Length))
                  then
                     raise Ada.IO_Exceptions.Data_Error;
                  end if;
               elsif US.Length (Info.Checksum.Value) = 0 then
                  if not Checksum_Engine.Valid_Configuration (Info.Checksum)
                  then
                     raise Ada.IO_Exceptions.Data_Error;
                  end if;
               elsif not Checksum_Engine.Valid_Digest
                 (US.To_String (Info.Checksum.Value),
                  Info.Checksum.Algorithm)
               then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
            end if;
            for Part of Parts loop
               if
                 (Info.Checksum.Algorithm = No_Checksum
                  and then Part.Checksum /= No_Checksum_Information)
                 or else
                   (Info.Checksum.Algorithm /= No_Checksum
                    and then
                      (Part.Checksum.Algorithm /= Info.Checksum.Algorithm
                       or else Part.Checksum.Method /= Info.Checksum.Method))
               then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
            end loop;
         end if;
         Body_At := SIO.Index (File);
         if SIO.Count (Info.Size) > SIO.Count'Last - (Body_At - 1)
           or else SIO.Size (File) /= Body_At - 1 + SIO.Count (Info.Size)
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
      end;
   end Read_Header_Any_With_Metadata;

   procedure Read_Header_Any
     (File      : in out SIO.File_Type;
      Key       : out US.Unbounded_String;
      Info      : out Object_Information;
      Body_At   : out SIO.Positive_Count)
   is
      Tags : Object_Tag_Set;
      Parts : Completed_Object_Part_List;
   begin
      Read_Header_Any_With_Metadata
        (File, Key, Info, Tags, Parts, Body_At);
   end Read_Header_Any;

   procedure Read_Header_Any_With_Tags
     (File      : in out SIO.File_Type;
      Key       : out US.Unbounded_String;
      Info      : out Object_Information;
      Tags      : out Object_Tag_Set;
      Body_At   : out SIO.Positive_Count)
   is
      Parts : Completed_Object_Part_List;
   begin
      Read_Header_Any_With_Metadata
        (File, Key, Info, Tags, Parts, Body_At);
   end Read_Header_Any_With_Tags;

   procedure Read_Header_With_Tags
     (File      : in out SIO.File_Type;
      Expected  : String;
      Info      : out Object_Information;
      Tags      : out Object_Tag_Set;
      Parts     : out Completed_Object_Part_List;
      Body_At   : out SIO.Positive_Count)
   is
      Key : US.Unbounded_String;
   begin
      Read_Header_Any_With_Metadata
        (File, Key, Info, Tags, Parts, Body_At);
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

   procedure Read_Header_With_Parts
     (File      : in out SIO.File_Type;
      Expected  : String;
      Info      : out Object_Information;
      Parts     : out Completed_Object_Part_List;
      Body_At   : out SIO.Positive_Count)
   is
      Key : US.Unbounded_String;
      Tags : Object_Tag_Set;
   begin
      Read_Header_Any_With_Metadata
        (File, Key, Info, Tags, Parts, Body_At);
      if US.To_String (Key) /= Expected then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
   end Read_Header_With_Parts;

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
        or else not Checksum_Engine.Valid_Configuration (Info.Checksum)
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Options.Content_Type := Info.Content_Type;
      Options.Checksum := Info.Checksum;
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
         Ensure_Directory
           (Item,
            Join (US.To_String (Staged), "configuration"));
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
           and then not GNAT.OS_Lib.Is_Symbolic_Link (Path)
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
      elsif GNAT.OS_Lib.Is_Symbolic_Link (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Directory
      then
         raise Ada.IO_Exceptions.Data_Error;
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

   overriding procedure Put_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Value    : Tags.Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      Locked    : Boolean := False;
      Published : Boolean := False;
      Temp      : US.Unbounded_String;
      Number    : Long_Long_Integer;
      Renamed   : Boolean := False;
      Target    : constant String := Tags_Path (Item, Bucket);
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Tags.Valid_Bucket_Tag_Set (Value)
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.Temp_Sequence.Next (Number);
      Temp := US.To_Unbounded_String
        (Join
           (Temp_Path (Item),
            "tags-" & GNAT.SHA256.Digest
              (Bucket & Long_Long_Integer'Image (Number) &
               Ada.Calendar.Time'Image (Ada.Calendar.Clock))));
      SIO.Create (File, SIO.Out_File, US.To_String (Temp));
      Opened := True;
      Write_Tags (File, Value);
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
      Ensure_Directory (Item, Configuration_Path (Item, Bucket));
      GNAT.OS_Lib.Rename_File (US.To_String (Temp), Target, Renamed);
      if not Renamed then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         Result := Backend_Unavailable;
         return;
      end if;
      Published := True;
      Sync_Directory (Item, Configuration_Path (Item, Bucket));
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
         Result := Backend_Unavailable;
   end Put_Bucket_Tags;

   overriding procedure Get_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Tags.Tag_Set;
      Result   : out Status)
   is
      File   : SIO.File_Type;
      Opened : Boolean := False;
      Locked : Boolean := False;
      Path   : constant String := Tags_Path (Item, Bucket);
   begin
      Value.Clear;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Not_Found;
      elsif not Ada.Directories.Exists (Path) then
         Result := Tag_Set_Not_Found;
      elsif GNAT.OS_Lib.Is_Symbolic_Link
          (Configuration_Path (Item, Bucket))
        or else GNAT.OS_Lib.Is_Symbolic_Link (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
      then
         raise Ada.IO_Exceptions.Data_Error;
      else
         SIO.Open (File, SIO.In_File, Path);
         Opened := True;
         Read_Tags (File, Value);
         SIO.Close (File);
         Opened := False;
         Result := Success;
      end if;
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Value.Clear;
         Result := Backend_Unavailable;
   end Get_Bucket_Tags;

   overriding procedure Delete_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status)
   is
      Locked : Boolean := False;
      Bucket_Directory : constant String := Bucket_Path (Item, Bucket);
      Configuration_Directory : constant String :=
        Configuration_Path (Item, Bucket);
      Target : constant String := Tags_Path (Item, Bucket);
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if GNAT.OS_Lib.Is_Symbolic_Link (Bucket_Directory) then
         raise Ada.IO_Exceptions.Data_Error;
      elsif not Ada.Directories.Exists (Bucket_Directory) then
         Result := Not_Found;
      elsif Ada.Directories.Kind (Bucket_Directory) /=
          Ada.Directories.Directory
      then
         raise Ada.IO_Exceptions.Data_Error;
      elsif GNAT.OS_Lib.Is_Symbolic_Link (Configuration_Directory) then
         raise Ada.IO_Exceptions.Data_Error;
      elsif not Ada.Directories.Exists (Configuration_Directory) then
         Result := Success;
      elsif Ada.Directories.Kind (Configuration_Directory) /=
        Ada.Directories.Directory
      then
         raise Ada.IO_Exceptions.Data_Error;
      elsif GNAT.OS_Lib.Is_Symbolic_Link (Target) then
         raise Ada.IO_Exceptions.Data_Error;
      elsif not Ada.Directories.Exists (Target) then
         Result := Success;
      elsif Ada.Directories.Kind (Target) /=
          Ada.Directories.Ordinary_File
      then
         raise Ada.IO_Exceptions.Data_Error;
      else
         Ada.Directories.Delete_File (Target);
         Sync_Directory (Item, Configuration_Directory);
         Result := Success;
      end if;
      Item.Publication.Release;
      Locked := False;
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
   end Delete_Bucket_Tags;

   overriding procedure Put_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Versioning_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status;
      MFA_Validated : Boolean := False)
   is
      Bucket_Directory : constant String := Bucket_Path (Item, Bucket);
      Target           : constant String := Versioning_Path (Item, Bucket);
      Temp             : US.Unbounded_String;
      Number           : Long_Long_Integer;
      File             : SIO.File_Type;
      Locked           : Boolean := False;
      Renamed          : Boolean := False;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Directory)
        or else GNAT.OS_Lib.Is_Symbolic_Link (Bucket_Directory)
        or else Ada.Directories.Kind (Bucket_Directory) /=
          Ada.Directories.Directory
      then
         Result := Not_Found;
      else
         declare
            Value : Bucket_Versioning_Configuration :=
              Read_Versioning (Item, Bucket);
         begin
            if not MFA_Validated
              and then
                (Value.MFA_Delete = MFA_Delete_Enabled
                 or else
                   Configuration.MFA_Delete /= MFA_Delete_Unconfigured)
            then
               Result := Access_Denied;
               Item.Publication.Release;
               Locked := False;
               return;
            end if;
            Value := Merge_Bucket_Versioning (Value, Configuration);
            Item.Temp_Sequence.Next (Number);
            Temp := US.To_Unbounded_String
              (Join
                 (Temp_Path (Item),
                  "versioning-" & GNAT.SHA256.Digest
                    (Bucket & Long_Long_Integer'Image (Number) &
                     Ada.Calendar.Time'Image (Ada.Calendar.Clock))));
            SIO.Create (File, SIO.Out_File, US.To_String (Temp));
            Write_String (File, Versioning_Magic);
            Write_String
              (File,
               (case Value.Status is
                   when Versioning_Unconfigured => "U",
                   when Versioning_Enabled      => "E",
                   when Versioning_Suspended    => "S"));
            Write_String
              (File,
               (case Value.MFA_Delete is
                   when MFA_Delete_Unconfigured => "U",
                   when MFA_Delete_Enabled      => "E",
                   when MFA_Delete_Disabled     => "D"));
            SIO.Close (File);
            Sync_File (Item, US.To_String (Temp));
            Ensure_Directory (Item, Configuration_Path (Item, Bucket));
            GNAT.OS_Lib.Rename_File
              (US.To_String (Temp), Target, Renamed);
            if not Renamed then
               raise Ada.IO_Exceptions.Use_Error;
            end if;
            Sync_Directory (Item, Configuration_Path (Item, Bucket));
            Sync_Directory (Item, Temp_Path (Item));
            Temp := US.Null_Unbounded_String;
            Result := Success;
         end;
      end if;
      Item.Publication.Release;
      Locked := False;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         begin
            if US.Length (Temp) > 0
              and then Ada.Directories.Exists (US.To_String (Temp))
            then
               Ada.Directories.Delete_File (US.To_String (Temp));
            end if;
         exception
            when others => null;
         end;
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         begin
            if US.Length (Temp) > 0
              and then Ada.Directories.Exists (US.To_String (Temp))
            then
               Ada.Directories.Delete_File (US.To_String (Temp));
            end if;
         exception
            when others => null;
         end;
         Result := Backend_Unavailable;
   end Put_Bucket_Versioning;

   overriding procedure Get_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status)
   is
      Path   : constant String := Bucket_Path (Item, Bucket);
      Locked : Boolean := False;
   begin
      Configuration := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Path)
        or else GNAT.OS_Lib.Is_Symbolic_Link (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Directory
      then
         Result := Not_Found;
      elsif Ada.Directories.Exists (Configuration_Path (Item, Bucket))
        and then
          (GNAT.OS_Lib.Is_Symbolic_Link
             (Configuration_Path (Item, Bucket))
           or else Ada.Directories.Kind (Configuration_Path (Item, Bucket)) /=
             Ada.Directories.Directory)
      then
         raise Ada.IO_Exceptions.Data_Error;
      else
         Configuration := Read_Versioning (Item, Bucket);
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
         Configuration := (others => <>);
         Result := Backend_Unavailable;
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
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions)
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
      elsif Evaluate_Write_Conditions
        (Conditions, Exists => False, Entity_Tag => "") = Invalid_Request
      then
         Result := Invalid_Request;
         return;
      elsif not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Not_Found;
         return;
      end if;
      Check_Context (Token, Deadline);
      In_Callback := True;
      Declared := Source.Declared_Length;
      In_Callback := False;
      Check_Context (Token, Deadline);
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
         Version      => US.Null_Unbounded_String,
         Checksum     => (others => <>));
      Write_Header (File, Key, Info);

      while not Finished loop
         Check_Context (Token, Deadline);
         In_Callback := True;
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         In_Callback := False;
         Check_Context (Token, Deadline);
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
      Check_Context (Token, Deadline);
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
         Result := Not_Found;
         return;
      end if;
      declare
         Existing_Info : Object_Information := Empty_Info;
         Existing_File : SIO.File_Type;
         Body_At       : SIO.Positive_Count;
         Is_Link       : constant Boolean :=
           GNAT.OS_Lib.Is_Symbolic_Link (Target);
         Exists        : constant Boolean := Ada.Directories.Exists (Target);
      begin
         if Is_Link
           or else
             (Exists
              and then Ada.Directories.Kind (Target) /=
                Ada.Directories.Ordinary_File)
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         if Exists then
            SIO.Open (Existing_File, SIO.In_File, Target);
            Read_Header (Existing_File, Key, Existing_Info, Body_At);
            SIO.Close (Existing_File);
         end if;
         Result := Evaluate_Write_Conditions
           (Conditions, Exists,
            (if Exists then US.To_String (Existing_Info.Entity_Tag)
             else ""));
      exception
         when others =>
            if SIO.Is_Open (Existing_File) then
               SIO.Close (Existing_File);
            end if;
            raise;
      end;
      if Result /= Success then
         Item.Publication.Release;
         Locked := False;
         Ada.Directories.Delete_File (US.To_String (Temp));
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
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions)
   is
      File : SIO.File_Type;
      Body_At : SIO.Positive_Count;
      Path : constant String := Object_Path (Item, Bucket, Key);
      Locked : Boolean := False;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.Publication.Acquire;
      Locked := True;
      Check_Context (Token, Deadline);
      if not Ada.Directories.Exists (Path) then
         Result := Not_Found;
      else
         SIO.Open (File, SIO.In_File, Path);
         Read_Header (File, Key, Info, Body_At);
         SIO.Close (File);
         Result := Evaluate_Read_Conditions
           (Conditions, US.To_String (Info.Entity_Tag), Info.Modified);
      end if;
      Item.Publication.Release;
      Locked := False;
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
      Conditions : Read_Conditions := Default_Read_Conditions)
   is
      File    : SIO.File_Type;
      Body_At : SIO.Positive_Count;
      All_Parts : Completed_Object_Part_List;
      Path : constant String := Object_Path (Item, Bucket, Key);
      Locked : Boolean := False;
   begin
      Snapshot := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
         return;
      end if;
      Item.Publication.Acquire;
      Locked := True;
      Check_Context (Token, Deadline);
      if not Ada.Directories.Exists (Path) then
         Result := Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      SIO.Open (File, SIO.In_File, Path);
      Read_Header_With_Parts
        (File, Key, Snapshot.Info, All_Parts, Body_At);
      SIO.Close (File);
      Result := Evaluate_Read_Conditions
        (Conditions, US.To_String (Snapshot.Info.Entity_Tag),
         Snapshot.Info.Modified);
      if Result /= Success then
         Item.Publication.Release;
         Locked := False;
         return;
      end if;
      Snapshot.Is_Multipart := not All_Parts.Is_Empty;
      Snapshot.Total_Parts := Natural (All_Parts.Length);
      if Options.Maximum > 0 then
         for Part of All_Parts loop
            Check_Context (Token, Deadline);
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
         Snapshot := (others => <>);
         Result := Backend_Unavailable;
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
      Result   : out Status;
      Conditions : Delete_Object_Conditions :=
        No_Delete_Object_Conditions;
      Requirements : Delete_Objects_Requirements := (others => <>))
   is
      Entries  : Delete_Object_Entries;
      Outcomes : Delete_Object_Outcomes;
   begin
      Entries.Append
        (Delete_Object_Entry'
           (Key => US.To_Unbounded_String (Key), Conditions => Conditions));
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
      Locked   : Boolean := False;
      Removals : Delete_Object_Entries;
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
         if not Valid_Object_Key (US.To_String (Request_Entry.Key))
           or else
             (Request_Entry.Conditions.Has_ETag
              and then not Valid_Object_Delete_ETag_Condition
                (US.To_String (Request_Entry.Conditions.ETag)))
         then
            Result := Invalid_Request;
            return;
         end if;
      end loop;
      Outcomes.Reserve_Capacity (Entries.Length);
      Removals.Reserve_Capacity (Entries.Length);

      Acquire_Publication (Item, Token, Deadline);
      Locked := True;
      if not Ada.Directories.Exists (Bucket_Path (Item, Bucket)) then
         Result := Bucket_Not_Found;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;

      if Requirements.Require_Unversioned then
         if Ada.Directories.Exists (Configuration_Path (Item, Bucket))
           and then
             (GNAT.OS_Lib.Is_Symbolic_Link
                (Configuration_Path (Item, Bucket))
              or else Ada.Directories.Kind
                (Configuration_Path (Item, Bucket)) /=
                  Ada.Directories.Directory)
         then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         declare
            Configuration : constant Bucket_Versioning_Configuration :=
              Read_Versioning (Item, Bucket);
         begin
            if Configuration.Status /= Versioning_Unconfigured
              or else Configuration.MFA_Delete = MFA_Delete_Enabled
            then
               Result := Not_Implemented;
               Item.Publication.Release;
               Locked := False;
               return;
            end if;
         end;
      end if;

      for Request_Entry of Entries loop
         Check_Context (Token, Deadline);
         declare
            Key  : constant String := US.To_String (Request_Entry.Key);
            Path : constant String := Object_Path (Item, Bucket, Key);
            Removed_Earlier : Boolean := False;
            Physical_Exists : constant Boolean :=
              Ada.Directories.Exists (Path);
            Info : Object_Information := Empty_Info;
         begin
            for Removal of Removals loop
               if US.To_String (Removal.Key) = Key then
                  Removed_Earlier := True;
                  exit;
               end if;
            end loop;
            declare
               Exists : constant Boolean :=
                 Physical_Exists and then not Removed_Earlier;
            begin
               if Exists then
                  if GNAT.OS_Lib.Is_Symbolic_Link (Path)
                    or else Ada.Directories.Kind (Path) /=
                      Ada.Directories.Ordinary_File
                  then
                     raise Ada.IO_Exceptions.Data_Error;
                  end if;
                  declare
                     File    : SIO.File_Type;
                     Body_At : SIO.Positive_Count;
                  begin
                     SIO.Open (File, SIO.In_File, Path);
                     Read_Header (File, Key, Info, Body_At);
                     SIO.Close (File);
                  exception
                     when others =>
                        if SIO.Is_Open (File) then
                           SIO.Close (File);
                        end if;
                        raise;
                  end;
               end if;
               declare
                  Entry_Result : constant Status :=
                    Evaluate_Delete_Object_Conditions
                      (Request_Entry.Conditions, Exists, Info);
               begin
                  Outcomes.Append
                    (Delete_Object_Outcome'(Result => Entry_Result));
                  if Entry_Result = Success and then Exists then
                     Removals.Append (Request_Entry);
                  end if;
               end;
            end;
         end;
      end loop;
      for Removal of Removals loop
         Check_Context (Token, Deadline);
         declare
            Path : constant String :=
              Object_Path (Item, Bucket, US.To_String (Removal.Key));
         begin
            Ada.Directories.Delete_File (Path);
            Sync_Directory
              (Item, Ada.Directories.Containing_Directory (Path));
         end;
      end loop;
      Result := Success;
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
         Outcomes.Clear;
         Result := Backend_Unavailable;
   end Delete_Objects;

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
      Completed_Parts : Completed_Object_Part_List;
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
      Read_Header_With_Tags
        (Source, Key, Info, Old_Tags, Completed_Parts, Body_At);
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
      Write_Header
        (Staged, Key, Info, Tags => Tags, Parts => Completed_Parts);
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
      elsif not Checksum_Engine.Valid_Configuration (Options.Checksum) then
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
         Version      => US.Null_Unbounded_String,
         Checksum     => Options.Checksum);
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
      Options     : Multipart_Part_Options;
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

      if Options.Expected_Checksum.Algorithm /= No_Checksum
        and then
          (Options.Expected_Checksum.Algorithm /=
             Upload_Options.Checksum.Algorithm
           or else Options.Expected_Checksum.Method /=
             Upload_Options.Checksum.Method
           or else not Checksum_Engine.Valid_Digest
             (US.To_String (Options.Expected_Checksum.Value),
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
         Actual_Checksum : US.Unbounded_String;
      begin

         Check_Context (Token, Deadline);
         In_Callback := True;
         Declared := Source.Declared_Length;
         In_Callback := False;
         Check_Context (Token, Deadline);
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
            Version      => US.Null_Unbounded_String,
            Checksum     =>
              (if Upload_Options.Checksum.Algorithm = No_Checksum
               then No_Checksum_Information
               else
                 (Algorithm => Upload_Options.Checksum.Algorithm,
                  Method    => Upload_Options.Checksum.Method,
                  Value     => US.To_Unbounded_String
                    (Checksum_Engine.Finish (Digest_Hash)))));
         Write_Header (File, Key, Info);
         while not Finished loop
            Check_Context (Token, Deadline);
            In_Callback := True;
            Source.Read (Buffer, Last, Finished, Token, Deadline);
            In_Callback := False;
            Check_Context (Token, Deadline);
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
                  if Upload_Options.Checksum.Algorithm /= No_Checksum then
                     Checksum_Engine.Update
                       (Digest_Hash, Buffer (Buffer'First .. Last));
                  end if;
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
         if Upload_Options.Checksum.Algorithm /= No_Checksum then
            Actual_Checksum := US.To_Unbounded_String
              (Checksum_Engine.Finish (Digest_Hash));
            if Options.Expected_Checksum.Algorithm /= No_Checksum
              and then US.To_String (Options.Expected_Checksum.Value) /=
                US.To_String (Actual_Checksum)
            then
               Result := Bad_Digest;
               SIO.Close (File);
               Opened := False;
               Ada.Directories.Delete_File (US.To_String (Temp));
               return;
            end if;
            --  Write_Header initially reserved Finish (empty)'s Base64 value.
            --  Every digest for one algorithm has that fixed encoded width.
            --  Finish does not invalidate the running checksum context.  Guard
            --  the in-place rewrite so a future encoding change cannot shift
            --  the body or silently corrupt the staged part.
            if US.Length (Actual_Checksum) /=
              US.Length (Info.Checksum.Value)
            then
               raise Program_Error with
                 "multipart checksum encoding changed width";
            end if;
            Info.Checksum.Value := Actual_Checksum;
         end if;
         SIO.Set_Index (File, 1);
         Write_Header (File, Key, Info);
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
         if Info.Checksum.Algorithm /= Upload_Options.Checksum.Algorithm
           or else Info.Checksum.Method /= Upload_Options.Checksum.Method
         then
            Item.Publication.Release;
            Locked := False;
            Ada.Directories.Delete_File (US.To_String (Temp));
            Result := Backend_Unavailable;
            return;
         end if;
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
           (Item,
            Ada.Directories.Containing_Directory (US.To_String (Target)));
         Sync_Directory (Item, Temp_Path (Item));
         Item.Publication.Release;
         Locked := False;
         Result := Success;
      end;
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
      Page.Checksum := Upload_Options.Checksum;
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
                  if
                    (Upload_Options.Checksum.Algorithm = No_Checksum
                     and then Info.Checksum /= No_Checksum_Information)
                    or else
                      (Upload_Options.Checksum.Algorithm /= No_Checksum
                       and then
                         (Info.Checksum.Algorithm /=
                            Upload_Options.Checksum.Algorithm
                          or else Info.Checksum.Method /=
                            Upload_Options.Checksum.Method
                          or else not Checksum_Engine.Valid_Digest
                            (US.To_String (Info.Checksum.Value),
                             Info.Checksum.Algorithm)))
                  then
                     raise Ada.IO_Exceptions.Data_Error;
                  end if;
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
                          (Content_Type => Info.Content_Type,
                           Checksum => Info.Checksum));
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
      Options   : Complete_Multipart_Options;
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
      Completed_Parts : Completed_Object_Part_List;
      Completed_Checksum : Checksum_Information;
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
      if Upload_Options.Checksum.Method = Composite_Checksum then
         Previous := Multipart_Part_Number'First;
         First := True;
         for Reference of Parts loop
            if (First and then Reference.Number /= 1)
              or else
                (not First and then Reference.Number /= Previous + 1)
            then
               Result := Invalid_Part_Order;
               Item.Publication.Release;
               Locked := False;
               return;
            end if;
            Previous := Reference.Number;
            First := False;
         end loop;
      end if;
      declare
         Exists : constant Boolean := Ada.Directories.Exists (Target);
         Existing : Object_Information := Empty_Info;
         Body_At : SIO.Positive_Count;
         Condition_Result : Status;
      begin
         if Exists then
            SIO.Open (Part_File, SIO.In_File, Target);
            Part_Opened := True;
            Read_Header (Part_File, Key, Existing, Body_At);
            SIO.Close (Part_File);
            Part_Opened := False;
         end if;
         Condition_Result := Evaluate_Write_Conditions
           (Options.Conditions, Exists,
            US.To_String (Existing.Entity_Tag));
         if Condition_Result /= Success then
            Result := Condition_Result;
            Item.Publication.Release;
            Locked := False;
            return;
         end if;
      end;
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
            if
              (Upload_Options.Checksum.Algorithm = No_Checksum
               and then Part_Info.Checksum /= No_Checksum_Information)
              or else
                (Upload_Options.Checksum.Algorithm /= No_Checksum
                 and then
                   (Part_Info.Checksum.Algorithm /=
                      Upload_Options.Checksum.Algorithm
                    or else Part_Info.Checksum.Method /=
                      Upload_Options.Checksum.Method
                    or else not Checksum_Engine.Valid_Digest
                      (US.To_String (Part_Info.Checksum.Value),
                       Part_Info.Checksum.Algorithm)))
            then
               Result := Backend_Unavailable;
               Item.Publication.Release;
               Locked := False;
               return;
            elsif US.To_String (Part_Info.Entity_Tag) /=
              US.To_String (Reference.Entity_Tag)
              or else
                (Upload_Options.Checksum.Method = Composite_Checksum
                 and then Reference.Checksum /= Part_Info.Checksum)
              or else
                (Reference.Checksum.Algorithm /= No_Checksum
                 and then Reference.Checksum /= Part_Info.Checksum)
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
            Completed_Parts.Append
              (Completed_Object_Part'
                 (Number => Reference.Number, Size => Part_Info.Size,
                  Checksum => Part_Info.Checksum));
            Include_Part_Digest
              (Hash, US.To_String (Part_Info.Entity_Tag));
            Previous := Reference.Number;
            First := False;
         end;
      end loop;

      if Upload_Options.Checksum.Algorithm /= No_Checksum then
         declare
            Values : Checksum_Engine.Part_Value_Array
              (1 .. Natural (Completed_Parts.Length));
            Position : Positive := Values'First;
         begin
            for Part of Completed_Parts loop
               Values (Position) :=
                 (Value => Part.Checksum, Length => Part.Size);
               Position := Position + 1;
            end loop;
            Completed_Checksum := Upload_Options.Checksum;
            Completed_Checksum.Value := US.To_Unbounded_String
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
         Item.Publication.Release;
         Locked := False;
         return;
      elsif Options.Expected_Checksum.Algorithm /= No_Checksum
        and then not Checksum_Engine.Matches_Stored_Object_Digest
          (US.To_String (Options.Expected_Checksum.Value),
           US.To_String (Completed_Checksum.Value),
           Options.Expected_Checksum.Algorithm,
           Options.Expected_Checksum.Method, Positive (Parts.Length))
      then
         Result := Bad_Digest;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;

      if Options.Expected_Size.Kind = Known
        and then Options.Expected_Size.Bytes /= Total
      then
         Result := Invalid_Request;
         Item.Publication.Release;
         Locked := False;
         return;
      end if;

      Info :=
        (Size         => Total,
         Modified     => Unix_Time (Unix_Seconds (Ada.Calendar.Clock)),
         Entity_Tag   => US.To_Unbounded_String
           (GNAT.MD5.Digest (Hash) & "-" &
            Ada.Strings.Fixed.Trim
              (Natural'Image (Natural (Parts.Length)), Ada.Strings.Both)),
         Content_Type => Upload_Options.Content_Type,
         Version      => US.Null_Unbounded_String,
         Checksum     => Completed_Checksum);
      Item.Temp_Sequence.Next (Number);
      Temp := US.To_Unbounded_String
        (Join
           (Temp_Path (Item),
            GNAT.SHA256.Digest
              (Upload_ID & Long_Long_Integer'Image (Number) &
               Ada.Calendar.Time'Image (Ada.Calendar.Clock)) & ".complete"));
      SIO.Create (File, SIO.Out_File, US.To_String (Temp));
      Opened := True;
      Write_Header (File, Key, Info, Parts => Completed_Parts);
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
