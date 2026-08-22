with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Flyology.IO;
with GNAT.Lock_Files;
with GNAT.MD5;
with GNAT.OS_Lib;
with GNAT.SHA256;
with Interfaces.C;
with Interfaces.C.Strings;

package body Flyology.Object_Storage.Backends.SQLite is

   use type Ada.Calendar.Time;
   use type Ada.Directories.File_Kind;
   use type Ada.Directories.File_Size;
   use type Ada.Real_Time.Time;
   use type Ada.Streams.Stream_Element;
   use type Ada.Streams.Stream_Element_Offset;
   use type Ada.Streams.Stream_IO.Count;
   use type GNAT.OS_Lib.File_Descriptor;
   use type Interfaces.C.int;
   use type Interfaces.C.Strings.chars_ptr;

   package Catalogs renames Flyology.Object_Storage.SQLite.Catalogs;
   package SIO renames Ada.Streams.Stream_IO;
   package US renames Ada.Strings.Unbounded;

   Epoch : constant Ada.Calendar.Time :=
     Ada.Calendar.Formatting.Time_Of
       (1970, 1, 1, 0, 0, 0, Time_Zone => 0);
   Empty_Info : constant Object_Information := (others => <>);
   Maximum_Metadata_Length : constant Natural := 8 * 1_024;

   function Sync_File_C
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "flyology_object_storage_sync_file";

   function Sync_Directory_C
     (Path : Interfaces.C.Strings.chars_ptr) return Interfaces.C.int
     with Import, Convention => C,
          External_Name => "flyology_object_storage_sync_directory";

   procedure Sync_Path (Path : String; Directory : Boolean := False) is
      package CS renames Interfaces.C.Strings;
      Value : CS.chars_ptr := CS.New_String (Path);
      Code  : Interfaces.C.int;
   begin
      Code := (if Directory then Sync_Directory_C (Value)
               else Sync_File_C (Value));
      CS.Free (Value);
      if Code /= 0 then
         raise Ada.IO_Exceptions.Device_Error with
           "could not make object payload durable";
      end if;
   exception
      when others =>
         if Value /= CS.Null_Ptr then
            CS.Free (Value);
         end if;
         raise;
   end Sync_Path;

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

   Lock_Name : constant String := ".flyology-object-storage.lock";

   overriding procedure Finalize (Item : in out Root_Lock) is
   begin
      if Item.Locked then
         GNAT.Lock_Files.Unlock_File (US.To_String (Item.Root), Lock_Name);
         Item.Locked := False;
      end if;
   end Finalize;

   function Join (Left, Right : String) return String is
     (Ada.Directories.Compose (Left, Right));

   function Root_Directory (Item : Store) return String is
     (US.To_String (Item.Root_Path));

   function Objects_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "objects"));

   function Staging_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "staging"));

   function Catalog_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "catalog.sqlite3"));

   function Unix_Seconds (Value : Ada.Calendar.Time) return Unix_Time is
     (Unix_Time (Long_Long_Integer (Value - Epoch)));

   function Valid_Options (Options : Put_Options) return Boolean is
     (US.Length (Options.Entity_Tag) <= Maximum_Metadata_Length
      and then US.Length (Options.Content_Type) <= Maximum_Metadata_Length);

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

   function Is_Payload_Name (Name : String) return Boolean is
   begin
      if Name'Length /= 69 or else Name (Name'Last - 4 .. Name'Last) /= ".blob"
      then
         return False;
      end if;
      for Index in Name'First .. Name'Last - 5 loop
         if Name (Index) not in '0' .. '9'
           and then Name (Index) not in 'a' .. 'f'
           and then Name (Index) not in 'A' .. 'F'
         then
            return False;
         end if;
      end loop;
      return True;
   end Is_Payload_Name;

   function Hex_Nibble (Value : Character) return Ada.Streams.Stream_Element is
     (if Value in '0' .. '9'
      then Ada.Streams.Stream_Element
        (Character'Pos (Value) - Character'Pos ('0'))
      elsif Value in 'a' .. 'f'
      then Ada.Streams.Stream_Element
        (10 + Character'Pos (Value) - Character'Pos ('a'))
      else Ada.Streams.Stream_Element
        (10 + Character'Pos (Value) - Character'Pos ('A')));

   procedure Include_Part_Digest
     (Hash : in out GNAT.MD5.Context; Entity_Tag : String)
   is
      Raw : Ada.Streams.Stream_Element_Array (1 .. 16);
   begin
      for Index in Raw'Range loop
         declare
            Offset : constant Natural := Natural (Index - Raw'First) * 2;
         begin
            Raw (Index) :=
              Ada.Streams.Stream_Element (16) *
              Hex_Nibble (Entity_Tag (Entity_Tag'First + Offset)) +
              Hex_Nibble (Entity_Tag (Entity_Tag'First + Offset + 1));
         end;
      end loop;
      GNAT.MD5.Update (Hash, Raw);
   end Include_Part_Digest;

   procedure Delete_Payload_If_Present (Item : Store; Name : String) is
      Path : constant String := Join (Objects_Path (Item), Name);
   begin
      if Is_Payload_Name (Name) and then Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   exception
      when others =>
         null;
   end Delete_Payload_If_Present;

   procedure Clean_Directory
     (Item : in out Store; Directory : String; Check_References : Boolean)
   is
      Search : Ada.Directories.Search_Type;
      Directory_Entry : Ada.Directories.Directory_Entry_Type;
      Filter : constant Ada.Directories.Filter_Type :=
        (Ada.Directories.Ordinary_File => True,
         Ada.Directories.Directory     => False,
         Ada.Directories.Special_File  => False);
   begin
      Ada.Directories.Start_Search (Search, Directory, "", Filter);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Directory_Entry);
         declare
            Name : constant String :=
              Ada.Directories.Simple_Name (Directory_Entry);
         begin
            if not Check_References
              or else not Is_Payload_Name (Name)
              or else not Catalogs.Payload_Referenced (Item.Catalog, Name)
            then
               Ada.Directories.Delete_File
                 (Ada.Directories.Full_Name (Directory_Entry));
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Clean_Directory;

   function Open
     (Root                : String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last) return Store
   is
      Full : US.Unbounded_String;
   begin
      if Root'Length = 0 then
         raise Configuration_Error with "SQLite backend root is empty";
      end if;
      if not Ada.Directories.Exists (Root) then
         Ada.Directories.Create_Path (Root);
      elsif Ada.Directories.Kind (Root) /= Ada.Directories.Directory then
         raise Configuration_Error with
           "SQLite backend root is not a directory";
      end if;
      Full := US.To_Unbounded_String (Ada.Directories.Full_Name (Root));
      return Result : Store do
         Result.Root_Path := Full;
         Result.Maximum_Object_Size := Maximum_Object_Size;
         Ada.Directories.Create_Path (Objects_Path (Result));
         Ada.Directories.Create_Path (Staging_Path (Result));
         GNAT.Lock_Files.Lock_File
           (US.To_String (Full), Lock_Name, Wait => 0.0, Retries => 0);
         Result.Lock.Root := Full;
         Result.Lock.Locked := True;
         Catalogs.Open (Result.Catalog, Catalog_Path (Result));
         Clean_Directory (Result, Staging_Path (Result), False);
         Clean_Directory (Result, Objects_Path (Result), True);
         Sync_Path (Staging_Path (Result), Directory => True);
         Sync_Path (Objects_Path (Result), Directory => True);
      end return;
   exception
      when Configuration_Error =>
         raise;
      when GNAT.Lock_Files.Lock_Error =>
         raise Configuration_Error with "SQLite backend root is already open";
      when others =>
         raise Configuration_Error with "could not open SQLite backend";
   end Open;

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
         Catalogs.Create_Bucket
           (Item.Catalog, Bucket, Unix_Seconds (Ada.Calendar.Clock), Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
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
      procedure Check is
      begin
         Check_Context (Token, Deadline);
      end Check;
   begin
      Check;
      Catalogs.List_Buckets
        (Item.Catalog, Options, Check'Access, Page, Result);
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
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
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
      else
         Catalogs.Head_Bucket (Item.Catalog, Bucket, Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
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
         Catalogs.Delete_Bucket (Item.Catalog, Bucket, Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
   end Delete_Bucket;

   procedure Create_Staging_File
     (Item    : in out Store;
      Bucket  : String;
      Key     : String;
      File    : in out SIO.File_Type;
      Staging : out US.Unbounded_String;
      Payload : out US.Unbounded_String)
   is
      Number : Long_Long_Integer;
      FD     : GNAT.OS_Lib.File_Descriptor := GNAT.OS_Lib.Invalid_FD;
      Attempts : Natural := 0;
   begin
      loop
         Attempts := Attempts + 1;
         Item.Temp_Sequence.Next (Number);
         declare
            Name : constant String := GNAT.SHA256.Digest
              (Bucket & Character'Val (0) & Key &
               Long_Long_Integer'Image (Number) &
               Integer'Image
                 (GNAT.OS_Lib.Pid_To_Integer
                    (GNAT.OS_Lib.Current_Process_Id)) &
               Duration'Image (Ada.Calendar.Clock - Epoch));
         begin
            Payload := US.To_Unbounded_String (Name & ".blob");
            Staging := US.To_Unbounded_String
              (Join (Staging_Path (Item), Name & ".part"));
            FD := GNAT.OS_Lib.Create_New_File
              (US.To_String (Staging), GNAT.OS_Lib.Binary);
         end;
         exit when FD /= GNAT.OS_Lib.Invalid_FD;
         if Attempts = 100 then
            raise Ada.IO_Exceptions.Use_Error with
              "could not create a unique SQLite staging file";
         end if;
      end loop;
      GNAT.OS_Lib.Close (FD);
      SIO.Open (File, SIO.Out_File, US.To_String (Staging));
   end Create_Staging_File;

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
      Buffer    : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last      : Ada.Streams.Stream_Element_Offset;
      Finished  : Boolean := False;
      Total     : Byte_Count := 0;
      Declared  : Source_Length := (Kind => Unknown);
      File      : SIO.File_Type;
      Opened    : Boolean := False;
      Published : Boolean := False;
      In_Callback : Boolean := False;
      Staging   : US.Unbounded_String;
      Payload   : US.Unbounded_String;
      Previous  : US.Unbounded_String;
      Renamed   : Boolean;
      Hash      : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else not Valid_Options (Options)
      then
         Result := Invalid_Request;
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
      Create_Staging_File (Item, Bucket, Key, File, Staging, Payload);
      Opened := True;
      while not Finished loop
         Check_Context (Token, Deadline);
         In_Callback := True;
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         In_Callback := False;
         if Last < Buffer'First - 1 or else Last > Buffer'Last then
            Result := Invalid_Request;
            SIO.Close (File);
            Opened := False;
            Ada.Directories.Delete_File (US.To_String (Staging));
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
                  Ada.Directories.Delete_File (US.To_String (Staging));
                  return;
               elsif Count > Item.Maximum_Object_Size
                 or else Total > Item.Maximum_Object_Size - Count
               then
                  Result := Capacity_Exceeded;
                  SIO.Close (File);
                  Opened := False;
                  Ada.Directories.Delete_File (US.To_String (Staging));
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
            Ada.Directories.Delete_File (US.To_String (Staging));
            return;
         end if;
      end loop;
      SIO.Close (File);
      Opened := False;
      if Declared.Kind = Known and then Declared.Bytes /= Total then
         Result := Invalid_Request;
         Ada.Directories.Delete_File (US.To_String (Staging));
         return;
      end if;
      Sync_Path (US.To_String (Staging));
      Info :=
        (Size         => Total,
         Modified     => Unix_Seconds (Ada.Calendar.Clock),
         Entity_Tag   =>
           (if US.Length (Options.Entity_Tag) > 0
            then Options.Entity_Tag
            else US.To_Unbounded_String (GNAT.MD5.Digest (Hash))),
         Content_Type => Options.Content_Type,
         Version      => US.Null_Unbounded_String);
      Check_Context (Token, Deadline);
      GNAT.OS_Lib.Rename_File
        (US.To_String (Staging),
         Join (Objects_Path (Item), US.To_String (Payload)),
         Renamed);
      if not Renamed then
         Result := Backend_Unavailable;
         Ada.Directories.Delete_File (US.To_String (Staging));
         return;
      end if;
      Published := True;
      Sync_Path (Objects_Path (Item), Directory => True);
      Catalogs.Put_Object
        (Item.Catalog, Bucket, Key, US.To_String (Payload), Info,
         Previous, Result);
      if Result /= Success then
         Ada.Directories.Delete_File
           (Join (Objects_Path (Item), US.To_String (Payload)));
         Sync_Path (Objects_Path (Item), Directory => True);
         Published := False;
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if US.Length (Staging) > 0
           and then Ada.Directories.Exists (US.To_String (Staging))
         then
            Ada.Directories.Delete_File (US.To_String (Staging));
         end if;
         if Published then
            Ada.Directories.Delete_File
              (Join (Objects_Path (Item), US.To_String (Payload)));
         end if;
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if US.Length (Staging) > 0
           and then Ada.Directories.Exists (US.To_String (Staging))
         then
            Ada.Directories.Delete_File (US.To_String (Staging));
         end if;
         if Published then
            Ada.Directories.Delete_File
              (Join (Objects_Path (Item), US.To_String (Payload)));
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

      Payload     : US.Unbounded_String;
      File        : aliased SIO.File_Type;
      Source_Info : Object_Information;
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

      Catalogs.Find_Object
        (Item.Catalog, Source_Bucket, Source_Key,
         Payload, Source_Info, Result);
      if Result = Not_Found then
         Result := Source_Not_Found;
         return;
      elsif Result /= Success then
         return;
      elsif not Is_Payload_Name (US.To_String (Payload)) then
         raise Ada.IO_Exceptions.Data_Error;
      elsif not Copy_Conditions_Accept
        (Options.Conditions, US.To_String (Source_Info.Entity_Tag))
      then
         Result := Precondition_Failed;
         return;
      end if;

      SIO.Open
        (File, SIO.In_File,
         Join (Objects_Path (Item), US.To_String (Payload)));
      if SIO.Size (File) /= SIO.Count (Source_Info.Size) then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
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
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
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
      Payload : US.Unbounded_String;
      Path    : US.Unbounded_String;
   begin
      Info := Empty_Info;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) or else not Valid_Object_Key (Key) then
         Result := Invalid_Request;
         return;
      end if;
      Catalogs.Find_Object (Item.Catalog, Bucket, Key, Payload, Info, Result);
      if Result /= Success then
         return;
      end if;
      if not Is_Payload_Name (US.To_String (Payload)) then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Path := US.To_Unbounded_String
        (Join (Objects_Path (Item), US.To_String (Payload)));
      if not Ada.Directories.Exists (US.To_String (Path))
        or else Ada.Directories.Kind (US.To_String (Path)) /=
          Ada.Directories.Ordinary_File
        or else Ada.Directories.Size (US.To_String (Path)) /=
          Ada.Directories.File_Size (Info.Size)
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
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
      Payload   : US.Unbounded_String;
      File      : SIO.File_Type;
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
      end if;
      Catalogs.Find_Object (Item.Catalog, Bucket, Key, Payload, Info, Result);
      if Result /= Success then
         return;
      elsif not Is_Payload_Name (US.To_String (Payload)) then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Result := Evaluate_Read_Conditions
        (Conditions, US.To_String (Info.Entity_Tag), Info.Modified);
      if Result /= Success then
         return;
      end if;
      SIO.Open
        (File, SIO.In_File,
         Join (Objects_Path (Item), US.To_String (Payload)));
      if SIO.Size (File) /= SIO.Count (Info.Size) then
         raise Ada.IO_Exceptions.Data_Error;
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
      SIO.Set_Index (File, SIO.Positive_Count (First + 1));
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
      Payload : US.Unbounded_String;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) or else not Valid_Object_Key (Key) then
         Result := Invalid_Request;
      else
         Catalogs.Delete_Object (Item.Catalog, Bucket, Key, Payload, Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
   end Delete_Object;

   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token; Deadline : Ada.Real_Time.Time;
      Result : out Status) is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) or else not Valid_Object_Key (Key)
        or else not Valid_Object_Tag_Set (Tags)
      then
         Result := Invalid_Request;
      else
         Catalogs.Put_Object_Tags (Item.Catalog, Bucket, Key, Tags, Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
   end Put_Object_Tags;

   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token; Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Result : out Status) is
   begin
      Tags := Empty_Object_Tags;
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
      else
         Catalogs.Get_Object_Tags (Item.Catalog, Bucket, Key, Tags, Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Tags := Empty_Object_Tags;
         Result := Backend_Unavailable;
   end Get_Object_Tags;

   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token; Deadline : Ada.Real_Time.Time;
      Result : out Status) is
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
      then
         Result := Invalid_Request;
      else
         Catalogs.Delete_Object_Tags (Item.Catalog, Bucket, Key, Result);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled
         | Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
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
      procedure Check is
      begin
         Check_Context (Token, Deadline);
      end Check;
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Catalogs.List_Objects
        (Item.Catalog, Bucket, Options, Check'Access, Page, Result);
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
      Number : Long_Long_Integer;
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
            Duration'Image (Ada.Calendar.Clock - Epoch)));
      Catalogs.Create_Multipart_Upload
        (Item.Catalog, Bucket, Key, US.To_String (Upload_ID),
         US.To_String (Options.Content_Type),
         Unix_Seconds (Ada.Calendar.Clock), Result);
      if Result /= Success then
         Upload_ID := US.Null_Unbounded_String;
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         raise;
      when others =>
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
      Buffer      : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last        : Ada.Streams.Stream_Element_Offset;
      Finished    : Boolean := False;
      Total       : Byte_Count := 0;
      Declared    : Source_Length := (Kind => Unknown);
      File        : SIO.File_Type;
      Opened      : Boolean := False;
      Published   : Boolean := False;
      In_Callback : Boolean := False;
      Staging     : US.Unbounded_String;
      Payload     : US.Unbounded_String;
      Previous    : US.Unbounded_String;
      Content_Type : US.Unbounded_String;
      Renamed     : Boolean;
      Hash        : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
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
      Catalogs.Find_Multipart_Upload
        (Item.Catalog, Bucket, Key, Upload_ID, Content_Type, Result);
      if Result /= Success then
         return;
      end if;
      In_Callback := True;
      Declared := Source.Declared_Length;
      In_Callback := False;
      if Declared.Kind = Known
        and then Declared.Bytes > Item.Maximum_Object_Size
      then
         Result := Capacity_Exceeded;
         return;
      end if;
      Create_Staging_File
        (Item, Bucket, Key & Upload_ID, File, Staging, Payload);
      Opened := True;
      while not Finished loop
         Check_Context (Token, Deadline);
         In_Callback := True;
         Source.Read (Buffer, Last, Finished, Token, Deadline);
         In_Callback := False;
         if Last < Buffer'First - 1 or else Last > Buffer'Last then
            Result := Invalid_Request;
            SIO.Close (File);
            Opened := False;
            Ada.Directories.Delete_File (US.To_String (Staging));
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
                  Ada.Directories.Delete_File (US.To_String (Staging));
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
            Ada.Directories.Delete_File (US.To_String (Staging));
            return;
         end if;
      end loop;
      SIO.Close (File);
      Opened := False;
      if Declared.Kind = Known and then Declared.Bytes /= Total then
         Result := Invalid_Request;
         Ada.Directories.Delete_File (US.To_String (Staging));
         return;
      end if;
      Sync_Path (US.To_String (Staging));
      Info :=
        (Size         => Total,
         Modified     => Unix_Seconds (Ada.Calendar.Clock),
         Entity_Tag   => US.To_Unbounded_String (GNAT.MD5.Digest (Hash)),
         Content_Type => US.Null_Unbounded_String,
         Version      => US.Null_Unbounded_String);
      Check_Context (Token, Deadline);
      GNAT.OS_Lib.Rename_File
        (US.To_String (Staging),
         Join (Objects_Path (Item), US.To_String (Payload)), Renamed);
      if not Renamed then
         Result := Backend_Unavailable;
         Ada.Directories.Delete_File (US.To_String (Staging));
         return;
      end if;
      Published := True;
      Sync_Path (Objects_Path (Item), Directory => True);
      Catalogs.Put_Multipart_Part
        (Item.Catalog, Bucket, Key, Upload_ID, Part_Number,
         US.To_String (Payload), Info, Previous, Result);
      if Result /= Success then
         Delete_Payload_If_Present (Item, US.To_String (Payload));
         Published := False;
         Sync_Path (Objects_Path (Item), Directory => True);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Opened then
            SIO.Close (File);
         end if;
         if US.Length (Staging) > 0
           and then Ada.Directories.Exists (US.To_String (Staging))
         then
            Ada.Directories.Delete_File (US.To_String (Staging));
         end if;
         if Published then
            Delete_Payload_If_Present (Item, US.To_String (Payload));
         end if;
         raise;
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if US.Length (Staging) > 0
           and then Ada.Directories.Exists (US.To_String (Staging))
         then
            Ada.Directories.Delete_File (US.To_String (Staging));
         end if;
         if Published then
            Delete_Payload_If_Present (Item, US.To_String (Payload));
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
      Catalogs.List_Multipart_Parts
        (Item.Catalog, Bucket, Key, Upload_ID, Options, Page, Result);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         Page := (others => <>);
         raise;
      when others =>
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
      procedure Check is
      begin
         Check_Context (Token, Deadline);
      end Check;
   begin
      Page := (others => <>);
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket) then
         Result := Invalid_Request;
         return;
      end if;
      Catalogs.List_Multipart_Uploads
        (Item.Catalog, Bucket, Options, Check'Access, Page, Result);
      Check_Context (Token, Deadline);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         Page := (others => <>);
         raise;
      when others =>
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

      Payload     : US.Unbounded_String;
      File        : aliased SIO.File_Type;
      Source_Info : Object_Information;
      Resolution  : Range_Resolution;
      First       : Byte_Count := 0;
      Length      : Byte_Count := 0;
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

      Catalogs.Find_Object
        (Item.Catalog, Source_Bucket, Source_Key,
         Payload, Source_Info, Result);
      if Result = Not_Found then
         Result := Source_Not_Found;
         return;
      elsif Result /= Success then
         return;
      elsif not Is_Payload_Name (US.To_String (Payload)) then
         raise Ada.IO_Exceptions.Data_Error;
      elsif not Copy_Conditions_Accept
        (Conditions, US.To_String (Source_Info.Entity_Tag))
      then
         Result := Precondition_Failed;
         return;
      elsif Requested.Kind not in Whole_Range | Bounded_Range then
         Result := Invalid_Request;
         return;
      elsif Requested.Kind = Bounded_Range
        and then
          (Requested.First > Requested.Last
           or else Requested.Last >= Source_Info.Size)
      then
         Result := Invalid_Range;
         return;
      end if;

      Resolution := Resolve_Range (Source_Info.Size, Requested);
      if Resolution.Kind = Unsatisfiable_Range then
         Result := Invalid_Range;
         return;
      elsif Resolution.Kind = Satisfied_Range then
         First := Resolution.First;
         Length := Resolution.Length;
      end if;
      if Length > Maximum_Multipart_Part_Size then
         Result := Entity_Too_Large;
         return;
      end if;

      SIO.Open
        (File, SIO.In_File,
         Join (Objects_Path (Item), US.To_String (Payload)));
      if SIO.Size (File) /= SIO.Count (Source_Info.Size) then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      SIO.Set_Index (File, SIO.Positive_Count (First + 1));
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
         raise;
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
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
      Records     : Catalogs.Multipart_Part_Records;
      Retired     : Catalogs.Payloads;
      Content_Type : US.Unbounded_String;
      Previous    : US.Unbounded_String;
      Total       : Byte_Count := 0;
      Hash        : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
      Prior       : Multipart_Part_Number := Multipart_Part_Number'First;
      First       : Boolean := True;
      File        : SIO.File_Type;
      Part_File   : SIO.File_Type;
      Opened      : Boolean := False;
      Part_Opened : Boolean := False;
      Published   : Boolean := False;
      Staging     : US.Unbounded_String;
      Payload     : US.Unbounded_String;
      Renamed     : Boolean;
      Buffer      : Ada.Streams.Stream_Element_Array (1 .. 64 * 1_024);
      Last        : Ada.Streams.Stream_Element_Offset;
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
         if not First and then Reference.Number <= Prior then
            Result := Invalid_Part_Order;
            return;
         end if;
         Prior := Reference.Number;
         First := False;
      end loop;
      Catalogs.Find_Multipart_Upload
        (Item.Catalog, Bucket, Key, Upload_ID, Content_Type, Result);
      if Result /= Success then
         return;
      end if;
      Catalogs.Read_Multipart_Parts
        (Item.Catalog, Bucket, Key, Upload_ID, Parts, Records, Result);
      if Result /= Success then
         return;
      end if;
      for Index in Records.First_Index .. Records.Last_Index loop
         declare
            Record_Value : constant Catalogs.Multipart_Part_Record :=
              Records (Index);
         begin
            if Index /= Records.Last_Index
              and then Record_Value.Info.Size < 5 * 1_024 * 1_024
            then
               Result := Entity_Too_Small;
               return;
            elsif Record_Value.Info.Size >
              Item.Maximum_Object_Size - Total
            then
               Result := Capacity_Exceeded;
               return;
            end if;
            Total := Total + Record_Value.Info.Size;
            Include_Part_Digest
              (Hash, US.To_String (Record_Value.Info.Entity_Tag));
         end;
      end loop;
      if Options.Expected_Size.Kind = Known
        and then Options.Expected_Size.Bytes /= Total
      then
         Result := Invalid_Request;
         return;
      end if;
      Info :=
        (Size         => Total,
         Modified     => Unix_Seconds (Ada.Calendar.Clock),
         Entity_Tag   => US.To_Unbounded_String
           (GNAT.MD5.Digest (Hash) & "-" &
            Ada.Strings.Fixed.Trim
              (Natural'Image (Natural (Records.Length)), Ada.Strings.Both)),
         Content_Type => Content_Type,
         Version      => US.Null_Unbounded_String);
      Create_Staging_File
        (Item, Bucket, Key & Upload_ID, File, Staging, Payload);
      Opened := True;
      for Record_Value of Records loop
         if not Is_Payload_Name (US.To_String (Record_Value.Payload)) then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         SIO.Open
           (Part_File, SIO.In_File,
            Join (Objects_Path (Item), US.To_String (Record_Value.Payload)));
         Part_Opened := True;
         if SIO.Size (Part_File) /= SIO.Count (Record_Value.Info.Size) then
            raise Ada.IO_Exceptions.Data_Error;
         end if;
         declare
            Remaining : Byte_Count := Record_Value.Info.Size;
         begin
            while Remaining > 0 loop
               Check_Context (Token, Deadline);
               declare
                  Count : constant Ada.Streams.Stream_Element_Offset :=
                    Ada.Streams.Stream_Element_Offset
                      (Byte_Count'Min
                         (Remaining, Byte_Count (Buffer'Length)));
               begin
                  SIO.Read (Part_File, Buffer (1 .. Count), Last);
                  if Last /= Count then
                     raise Ada.IO_Exceptions.End_Error;
                  end if;
                  SIO.Write (File, Buffer (1 .. Count));
                  Remaining := Remaining - Byte_Count (Count);
               end;
            end loop;
         end;
         SIO.Close (Part_File);
         Part_Opened := False;
      end loop;
      SIO.Close (File);
      Opened := False;
      Sync_Path (US.To_String (Staging));
      Check_Context (Token, Deadline);
      GNAT.OS_Lib.Rename_File
        (US.To_String (Staging),
         Join (Objects_Path (Item), US.To_String (Payload)), Renamed);
      if not Renamed then
         Result := Backend_Unavailable;
         Ada.Directories.Delete_File (US.To_String (Staging));
         return;
      end if;
      Published := True;
      Sync_Path (Objects_Path (Item), Directory => True);
      Catalogs.Complete_Multipart_Upload
        (Item.Catalog, Bucket, Key, Upload_ID, Records,
         US.To_String (Payload), Info, Options.Conditions, Previous, Retired,
         Result);
      if Result /= Success then
         Delete_Payload_If_Present (Item, US.To_String (Payload));
         Published := False;
         Sync_Path (Objects_Path (Item), Directory => True);
         return;
      end if;
      Published := False;
      if US.Length (Previous) > 0 then
         Delete_Payload_If_Present (Item, US.To_String (Previous));
      end if;
      for Name of Retired loop
         Delete_Payload_If_Present (Item, US.To_String (Name));
      end loop;
      Sync_Path (Objects_Path (Item), Directory => True);
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         if Part_Opened then
            SIO.Close (Part_File);
         end if;
         if Opened then
            SIO.Close (File);
         end if;
         if US.Length (Staging) > 0
           and then Ada.Directories.Exists (US.To_String (Staging))
         then
            Ada.Directories.Delete_File (US.To_String (Staging));
         end if;
         if Published then
            Delete_Payload_If_Present (Item, US.To_String (Payload));
         end if;
         raise;
      when others =>
         if Part_Opened then
            SIO.Close (Part_File);
         end if;
         if Opened then
            SIO.Close (File);
         end if;
         if US.Length (Staging) > 0
           and then Ada.Directories.Exists (US.To_String (Staging))
         then
            Ada.Directories.Delete_File (US.To_String (Staging));
         end if;
         if Published then
            Delete_Payload_If_Present (Item, US.To_String (Payload));
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
      Retired : Catalogs.Payloads;
   begin
      Check_Context (Token, Deadline);
      if not Valid_Bucket_Name (Bucket)
        or else not Valid_Object_Key (Key)
        or else Upload_ID'Length not in 1 .. 1_024
      then
         Result := Invalid_Request;
         return;
      end if;
      Catalogs.Abort_Multipart_Upload
        (Item.Catalog, Bucket, Key, Upload_ID, Conditions, Retired, Result);
      if Result = Success then
         for Name of Retired loop
            Delete_Payload_If_Present (Item, US.To_String (Name));
         end loop;
         Sync_Path (Objects_Path (Item), Directory => True);
      end if;
   exception
      when Flyology.Cancellation.Operation_Cancelled |
           Flyology.IO.Timeout_Error =>
         raise;
      when others =>
         Result := Backend_Unavailable;
   end Abort_Multipart_Upload;

end Flyology.Object_Storage.Backends.SQLite;
