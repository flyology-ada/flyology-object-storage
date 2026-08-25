with Ada.Command_Line;
with Ada.Directories;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with GNAT.OS_Lib;
with Interfaces.C;
with Interfaces.C.Strings;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Files.Testing;
with Flyology.Object_Storage.Tags;
with GNAT.SHA256;

procedure Files_Conditional_Symlink_Probe is
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Files_Testing renames
     Flyology.Object_Storage.Backends.Files.Testing;
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Tags renames Flyology.Object_Storage.Tags;
   package C renames Interfaces.C;
   package CS renames Interfaces.C.Strings;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Streams.Stream_Element_Offset;
   use type C.int;
   use type Storage.Status;

   function Symlink
     (Target, Link_Path : CS.chars_ptr) return C.int
     with Import, Convention => C, External_Name => "symlink";

   type Buffer_Source is new Backends.Byte_Source with record
      Data     : Flyology.Bytes.Unbounded_Bytes;
      Position : Natural := 0;
   end record;

   type Null_Sink is new Backends.Byte_Sink with null record;

   overriding procedure Begin_Object
     (Item           : in out Null_Sink;
      Info           : Storage.Object_Information;
      First          : Storage.Byte_Count;
      Content_Length : Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time);

   overriding procedure Write
     (Item     : in out Null_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding function Declared_Length
     (Item : Buffer_Source) return Backends.Source_Length is
     (Kind => Backends.Known,
      Bytes => Storage.Byte_Count (Flyology.Bytes.Length (Item.Data)));

   overriding procedure Begin_Object
     (Item           : in out Null_Sink;
      Info           : Storage.Object_Information;
      First          : Storage.Byte_Count;
      Content_Length : Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced
        (Item, Info, First, Content_Length, Partial, Token, Deadline);
   begin
      null;
   end Begin_Object;

   overriding procedure Write
     (Item     : in out Null_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Item, Data, Token, Deadline);
   begin
      null;
   end Write;

   overriding procedure Read
     (Item     : in out Buffer_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
      Remaining : constant Natural :=
        Flyology.Bytes.Length (Item.Data) - Item.Position;
      Count : constant Natural := Natural'Min (Remaining, Data'Length);
   begin
      if Count > 0 then
         for Offset in 0 .. Count - 1 loop
            Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
              Flyology.Bytes.Element (Item.Data, Item.Position + Offset + 1);
         end loop;
      end if;
      Item.Position := Item.Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Finished := Item.Position = Flyology.Bytes.Length (Item.Data);
   end Read;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Create_Symlink
     (Target, Link_Path, Description : String)
   is
      Target_C : CS.chars_ptr := CS.New_String (Target);
      Link_C   : CS.chars_ptr := CS.New_String (Link_Path);
      Code     : C.int;
   begin
      Code := Symlink (Target_C, Link_C);
      CS.Free (Target_C);
      CS.Free (Link_C);
      Require (Code = 0, "could not create " & Description & " symlink");
   end Create_Symlink;

   function Join (Left, Right : String) return String is
     (Ada.Directories.Compose (Left, Right));

   function Entry_Count (Path : String) return Natural is
      Search : Ada.Directories.Search_Type;
      Directory_Entry : Ada.Directories.Directory_Entry_Type;
      Count : Natural := 0;
   begin
      Ada.Directories.Start_Search
        (Search, Path, "", (others => True));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Directory_Entry);
         declare
            Name : constant String :=
              Ada.Directories.Simple_Name (Directory_Entry);
         begin
            if Name /= "." and then Name /= ".." then
               Count := Count + 1;
            end if;
         end;
      end loop;
      Ada.Directories.End_Search (Search);
      return Count;
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Entry_Count;

   function A_Segment return String is
      Value : String (1 .. 100);
   begin
      for Index in 0 .. 49 loop
         Value (2 * Index + 1) := '6';
         Value (2 * Index + 2) := '1';
      end loop;
      return Value;
   end A_Segment;

   Root : constant String := Ada.Command_Line.Argument (1);
   Mode : constant String := Ada.Command_Line.Argument (2);
   Outside : constant String := Ada.Directories.Compose (Root, "outside");
   Sentinel : constant String := Ada.Directories.Compose (Outside, "sentinel");
   Missing : constant String := Ada.Directories.Compose (Outside, "missing");
   External_Directory : constant String :=
     Ada.Directories.Compose (Outside, "external-directory");
   External_Directory_Sentinel : constant String :=
     Ada.Directories.Compose (External_Directory, "sentinel");
   Missing_Directory : constant String :=
     Ada.Directories.Compose (Outside, "missing-directory");
   Bucket_Path : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Compose (Root, "buckets"), "symlink-bucket");
   Configuration_Path : constant String :=
     Ada.Directories.Compose (Bucket_Path, "configuration");
   Versioning_Path : constant String :=
     Ada.Directories.Compose (Configuration_Path, "versioning.fos");
   Tags_Path : constant String :=
     Ada.Directories.Compose (Configuration_Path, "tags.fos");
   Public_Access_Block_Path : constant String :=
     Ada.Directories.Compose
       (Configuration_Path, "public-access-block.fos");
   Policy_Path : constant String :=
     Ada.Directories.Compose (Configuration_Path, "policy.fos");
   Bucket_Link_Path : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Compose (Root, "buckets"), "root-link-bucket");
   Link_Path : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Compose (Root, "buckets"), "symlink-bucket"),
           "objects"),
        "6C696E6B.fos");
   Link_Target : constant String :=
     (if Mode = "live" then Sentinel else Missing);
   Copy_Source_Bucket : constant String := "safe-copy-source";
   Store : Files.Store := Files.Open (Root, Maximum_Object_Size => 64);
   Result : Storage.Status;
   Info   : Storage.Object_Information;
   Source : Buffer_Source :=
     (Data => Flyology.Bytes.From_Byte_String ("replacement"), Position => 0);
   Conditions : Storage.Write_Conditions := Storage.Default_Write_Conditions;
   Tag_Set : Tags.Tag_Set;

   procedure Put
     (Bucket, Key, Payload : String;
      Expected : Storage.Status := Storage.Success)
   is
      Local_Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String (Payload), Position => 0);
      Local_Info : Storage.Object_Information;
      Local_Result : Storage.Status;
   begin
      Store.Put_Object
        (Bucket, Key, Local_Source, Storage.Default_Put_Options,
         null, Ada.Real_Time.Time_Last, Local_Info, Local_Result);
      Require
        (Local_Result = Expected,
         "unexpected Put_Object result:" &
         Storage.Status'Image (Local_Result));
   end Put;

   procedure Prepare_Multipart
     (Bucket : String;
      Upload_ID, Part_ETag : out US.Unbounded_String)
   is
      Part_Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String ("part-body"),
         Position => 0);
      Local_Info : Storage.Object_Information;
      Local_Result : Storage.Status;
   begin
      Store.Create_Bucket
        (Bucket, null, Ada.Real_Time.Time_Last, Local_Result);
      Require (Local_Result = Storage.Success, "multipart bucket setup");
      Store.Create_Multipart_Upload
        (Bucket, "target", Backends.Default_Multipart_Options,
         null, Ada.Real_Time.Time_Last, Upload_ID, Local_Result);
      Require (Local_Result = Storage.Success, "multipart upload setup");
      Store.Put_Multipart_Part
        (Bucket, "target", US.To_String (Upload_ID), 1, Part_Source,
         null, Ada.Real_Time.Time_Last, Local_Info, Local_Result);
      Require (Local_Result = Storage.Success, "multipart part setup");
      Part_ETag := Local_Info.Entity_Tag;
   end Prepare_Multipart;

   procedure Expect_Upload_Namespace_Failure
     (Bucket, Upload_ID : String;
      Part_ETag : US.Unbounded_String;
      List_Uploads_Also : Boolean)
   is
      Part_Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String ("replacement"),
         Position => 0);
      Local_Info : Storage.Object_Information;
      Local_Result : Storage.Status;
      Part_Page : Backends.Multipart_Part_Page;
      Upload_Page : Backends.Multipart_Upload_Page;
      References : Backends.Multipart_Part_References;
   begin
      Store.Put_Multipart_Part
        (Bucket, "target", Upload_ID, 1, Part_Source,
         null, Ada.Real_Time.Time_Last, Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         "Put_Multipart_Part did not fail closed");
      Store.List_Multipart_Parts
        (Bucket, "target", Upload_ID, (others => <>), null,
         Ada.Real_Time.Time_Last, Part_Page, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         "List_Multipart_Parts did not fail closed");
      if List_Uploads_Also then
         Store.List_Multipart_Uploads
           (Bucket, (others => <>), null, Ada.Real_Time.Time_Last,
            Upload_Page, Local_Result);
         Require
           (Local_Result = Storage.Backend_Unavailable,
            "List_Multipart_Uploads did not fail closed");
      end if;
      Store.Copy_Multipart_Part
        (Copy_Source_Bucket, "source", Bucket, "target", Upload_ID, 1,
         Storage.Whole_Object, Backends.Default_Copy_Options.Conditions,
         null, Ada.Real_Time.Time_Last, Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         "Copy_Multipart_Part did not fail closed");
      References.Append
        (Backends.Multipart_Part_Reference'
           (Number => 1, Entity_Tag => Part_ETag, others => <>));
      Store.Complete_Multipart_Upload
        (Bucket, "target", Upload_ID, References, (others => <>),
         null, Ada.Real_Time.Time_Last, Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         "Complete_Multipart_Upload did not fail closed");
      Store.Abort_Multipart_Upload
        (Bucket, "target", Upload_ID,
         Backends.No_Abort_Multipart_Conditions,
         null, Ada.Real_Time.Time_Last, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         "Abort_Multipart_Upload did not fail closed");
   end Expect_Upload_Namespace_Failure;

   procedure Expect_Object_Namespace_Failure
     (Bucket, Key : String; Description : String)
   is
      Page : Backends.List_Page;
      Local_Info : Storage.Object_Information;
      Attributes : Backends.Object_Attribute_Snapshot;
      Sink : Null_Sink;
      Object_Tags : Storage.Object_Tag_Set;
      Local_Result : Storage.Status;
   begin
      Store.Head_Object
        (Bucket, Key, null, Ada.Real_Time.Time_Last,
         Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Head_Object did not fail closed");
      Store.Get_Object
        (Bucket, Key, Storage.Whole_Object, Sink, null,
         Ada.Real_Time.Time_Last, Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Get_Object did not fail closed");
      Store.Get_Object_Attributes
        (Bucket, Key, (others => <>), null, Ada.Real_Time.Time_Last,
         Attributes, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Get_Object_Attributes did not fail closed");
      Store.Get_Object_Tags
        (Bucket, Key, null, Ada.Real_Time.Time_Last,
         Object_Tags, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Get_Object_Tags did not fail closed");
      Store.Put_Object_Tags
        (Bucket, Key, Object_Tags, null, Ada.Real_Time.Time_Last,
         Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Put_Object_Tags did not fail closed");
      Store.Delete_Object_Tags
        (Bucket, Key, null, Ada.Real_Time.Time_Last, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Delete_Object_Tags did not fail closed");
      Store.Copy_Object
        (Bucket, Key, Copy_Source_Bucket, Description,
         Backends.Default_Copy_Options, null, Ada.Real_Time.Time_Last,
         Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Copy_Object source did not fail closed");
      Store.Copy_Object
        (Copy_Source_Bucket, "source", Bucket, Key,
         Backends.Default_Copy_Options, null, Ada.Real_Time.Time_Last,
         Local_Info, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Copy_Object destination did not fail closed");
      Put (Bucket, Key, "blocked", Storage.Backend_Unavailable);
      Store.Delete_Object
        (Bucket, Key, null, Ada.Real_Time.Time_Last, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " Delete_Object did not fail closed");
      Store.List_Objects
        (Bucket, (others => <>), null, Ada.Real_Time.Time_Last,
         Page, Local_Result);
      Require
        (Local_Result = Storage.Backend_Unavailable,
         Description & " List_Objects did not fail closed");
   end Expect_Object_Namespace_Failure;
begin
   Require (Mode in "live" | "dangling", "invalid probe mode");
   declare
      Existing_Temp : constant String :=
        Join (Join (Root, "tmp"), "preexisting-copy-snapshot.tmp");
   begin
      if Mode = "live" then
         declare
            File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Existing_Temp);
            Ada.Text_IO.Put_Line (File, "preexisting-temp-sentinel");
            Ada.Text_IO.Close (File);
         end;
      else
         Create_Symlink
           (Missing, Existing_Temp, "preexisting-copy-snapshot");
      end if;
      Require
        (Files_Testing.Rejects_Temp_Target (Store, Existing_Temp),
         "preexisting CopyObject snapshot target was accepted");
      if Mode = "live" then
         declare
            File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Existing_Temp);
            Require
              (Ada.Text_IO.Get_Line (File) = "preexisting-temp-sentinel",
               "temp-target validation modified the existing file");
            Ada.Text_IO.Close (File);
         end;
      else
         Require
           (GNAT.OS_Lib.Is_Symbolic_Link (Existing_Temp)
            and then not Ada.Directories.Exists (Missing),
            "temp-target validation followed or removed the symlink");
      end if;
      Ada.Directories.Delete_File (Existing_Temp);
   end;
   Store.Create_Bucket
     ("symlink-bucket", null, Ada.Real_Time.Time_Last, Result);
   Require (Result = Storage.Success, "could not create probe bucket");
   Store.Create_Bucket
     (Copy_Source_Bucket, null, Ada.Real_Time.Time_Last, Result);
   Require (Result = Storage.Success, "could not create copy-source bucket");
   Put (Copy_Source_Bucket, "source", "copy-source");
   Tag_Set.Append
     (Tags.Tag'
        (Key => US.To_Unbounded_String ("scope"),
         Value => US.To_Unbounded_String ("symlink")));
   Ada.Directories.Create_Path (Outside);
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Sentinel);
         Ada.Text_IO.Put_Line (File, "outside-sentinel");
         Ada.Text_IO.Close (File);
         Ada.Directories.Create_Directory (External_Directory);
         Ada.Text_IO.Create
           (File, Ada.Text_IO.Out_File, External_Directory_Sentinel);
         Ada.Text_IO.Put_Line (File, "outside-directory-sentinel");
         Ada.Text_IO.Close (File);
      end;
   end if;
   Create_Symlink (Link_Target, Link_Path, "object-path");
   Conditions.If_None_Match := US.To_Unbounded_String ("*");
   Store.Put_Object
     ("symlink-bucket", "link", Source, Storage.Default_Put_Options,
      null, Ada.Real_Time.Time_Last, Info, Result, Conditions);
   Require
     (Result = Storage.Backend_Unavailable,
      "conditional Put_Object accepted an object-path symlink");
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Link_Path),
      "failed conditional Put_Object replaced the symlink");
   Store.Delete_Object
     ("symlink-bucket", "link", null, Ada.Real_Time.Time_Last, Result,
      (Has_ETag => True,
       ETag => US.To_Unbounded_String ("*"),
       others => <>),
      (Require_Unversioned => True, others => <>));
   Require
     (Result = Storage.Backend_Unavailable,
      "conditional Delete_Object followed an object-path symlink: " &
      Storage.Status'Image (Result));
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Link_Path),
      "failed conditional Delete_Object removed the symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-sentinel",
            "conditional Put_Object modified the external sentinel");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing),
         "conditional Put_Object created the dangling-link target");
   end if;

   Ada.Directories.Delete_File (Link_Path);
   if Ada.Directories.Exists (Configuration_Path) then
      Ada.Directories.Delete_Tree (Configuration_Path);
   end if;
   Create_Symlink
     ((if Mode = "live" then External_Directory else Missing_Directory),
      Configuration_Path, "configuration-directory");
   Store.Delete_Object
     ("symlink-bucket", "absent", null, Ada.Real_Time.Time_Last, Result,
      Conditions =>
        (Has_ETag => True,
         ETag => US.To_Unbounded_String ("*"),
         others => <>),
      Requirements => (Require_Unversioned => True, others => <>));
   Require
     (Result = Storage.Backend_Unavailable,
      "Delete_Object accepted a configuration-directory symlink");
   declare
      Configuration : Storage.Bucket_Versioning_Configuration;
   begin
      Store.Get_Bucket_Versioning
        ("symlink-bucket", null, Ada.Real_Time.Time_Last,
         Configuration, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Versioning accepted a configuration symlink");
      Store.Put_Bucket_Versioning
        ("symlink-bucket",
         (Status => Storage.Versioning_Enabled, others => <>),
         null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Put_Bucket_Versioning accepted a configuration symlink");
      Store.Put_Bucket_Tags
        ("symlink-bucket", Tag_Set, null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Put_Bucket_Tags accepted a configuration symlink");
      declare
         Observed : Tags.Tag_Set;
      begin
         Store.Get_Bucket_Tags
           ("symlink-bucket", null, Ada.Real_Time.Time_Last,
            Observed, Result);
         Require
           (Result = Storage.Backend_Unavailable,
            "Get_Bucket_Tags accepted a configuration symlink");
      end;
   end;
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Configuration_Path),
      "versioning operations replaced the configuration symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open
           (File, Ada.Text_IO.In_File, External_Directory_Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-directory-sentinel",
            "versioning operations modified the external directory");
         Ada.Text_IO.Close (File);
         Require
           (not Ada.Directories.Exists
              (Ada.Directories.Compose
                 (External_Directory, "versioning.fos")),
            "versioning operations wrote through the configuration symlink");
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing_Directory),
         "versioning operations created a dangling configuration target");
   end if;

   Ada.Directories.Delete_File (Configuration_Path);
   Ada.Directories.Create_Directory (Configuration_Path);
   Create_Symlink (Link_Target, Versioning_Path, "versioning-file");
   Store.Delete_Object
     ("symlink-bucket", "absent", null, Ada.Real_Time.Time_Last, Result,
      Conditions =>
        (Has_ETag => True,
         ETag => US.To_Unbounded_String ("*"),
         others => <>),
      Requirements => (Require_Unversioned => True, others => <>));
   Require
     (Result = Storage.Backend_Unavailable,
      "Delete_Object accepted a versioning-file symlink");
   declare
      Configuration : Storage.Bucket_Versioning_Configuration;
   begin
      Store.Get_Bucket_Versioning
        ("symlink-bucket", null, Ada.Real_Time.Time_Last,
         Configuration, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Versioning accepted a versioning-file symlink");
      Store.Put_Bucket_Versioning
        ("symlink-bucket",
         (Status => Storage.Versioning_Enabled, others => <>),
         null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Put_Bucket_Versioning accepted a versioning-file symlink");
   end;
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Versioning_Path),
      "versioning operations replaced the versioning-file symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-sentinel",
            "versioning operations modified the external file");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing),
         "versioning operations created a dangling versioning-file target");
   end if;

   Create_Symlink (Link_Target, Tags_Path, "bucket-tags-file");
   Store.Put_Bucket_Tags
     ("symlink-bucket", Tag_Set, null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Put_Bucket_Tags accepted a bucket-tags-file symlink");
   declare
      Observed : Tags.Tag_Set;
   begin
      Store.Get_Bucket_Tags
        ("symlink-bucket", null, Ada.Real_Time.Time_Last, Observed, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Tags accepted a bucket-tags-file symlink");
   end;
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Tags_Path),
      "bucket tag operations replaced the bucket-tags-file symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-sentinel",
            "bucket tag operations modified the external file");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing),
         "bucket tag operations created a dangling tags-file target");
   end if;

   Ada.Directories.Delete_File (Tags_Path);
   Create_Symlink
     (Link_Target, Public_Access_Block_Path, "public-access-block-file");
   Store.Put_Bucket_Public_Access_Block
     ("symlink-bucket",
      (Block_Public_ACLs => (Is_Set => True, Value => True), others => <>),
      null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Put_Bucket_Public_Access_Block accepted a file symlink");
   declare
      Configuration : Storage.Bucket_Public_Access_Block_Configuration;
      Configured    : Boolean;
   begin
      Store.Get_Bucket_Public_Access_Block
        ("symlink-bucket", null, Ada.Real_Time.Time_Last,
         Configuration, Configured, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Public_Access_Block accepted a file symlink");
      Store.Delete_Bucket_Public_Access_Block
        ("symlink-bucket", null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Delete_Bucket_Public_Access_Block accepted a file symlink");
   end;
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Public_Access_Block_Path),
      "public access block operations replaced the file symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-sentinel",
            "public access block operations modified the external file");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing),
         "public access block operations created a dangling file target");
   end if;

   Ada.Directories.Delete_File (Public_Access_Block_Path);
   Create_Symlink (Link_Target, Policy_Path, "bucket-policy-file");
   Store.Put_Bucket_Policy
     ("symlink-bucket", "policy", null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Put_Bucket_Policy accepted a file symlink");
   declare
      Policy     : US.Unbounded_String;
      Configured : Boolean;
   begin
      Store.Get_Bucket_Policy
        ("symlink-bucket", null, Ada.Real_Time.Time_Last,
         Policy, Configured, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Policy accepted a file symlink");
      Store.Delete_Bucket_Policy
        ("symlink-bucket", null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Delete_Bucket_Policy accepted a file symlink");
   end;
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Policy_Path),
      "bucket policy operations replaced the file symlink");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-sentinel",
            "bucket policy operations modified the external file");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing),
         "bucket policy operations created a dangling file target");
   end if;

   --  A fresh long key spans multiple encoded directories. It must remain a
   --  supported normal target, while replacing any encoded ancestor with a
   --  live or dangling symlink makes every reader and mutator fail closed.
   declare
      Long_Key : constant String (1 .. 101) := (others => 'a');
      Long_Bucket : constant String := "long-ancestor-bucket";
      Objects : constant String :=
        Join (Join (Join (Root, "buckets"), Long_Bucket), "objects");
      First : constant String := Join (Objects, A_Segment);
      External_First : constant String :=
        Join (Outside, "external-encoded-ancestor");
      External_Record : constant String :=
        Join (Join (External_First, A_Segment), "61.fos");
   begin
      Store.Create_Bucket
        (Long_Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Storage.Success, "long-key bucket setup failed");
      Put (Long_Bucket, Long_Key, "long-key-record");
      Store.Head_Object
        (Long_Bucket, Long_Key, null, Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Storage.Success,
         "fresh multi-level long-key Put/Get layout regressed");
      if Mode = "live" then
         Ada.Directories.Rename (First, External_First);
      else
         Ada.Directories.Delete_Tree (First);
      end if;
      Create_Symlink
        ((if Mode = "live" then External_First else Missing_Directory),
         First, "encoded-object-ancestor");
      Expect_Object_Namespace_Failure
        (Long_Bucket, Long_Key, "encoded ancestor symlink");
      Require
        (GNAT.OS_Lib.Is_Symbolic_Link (First),
         "object operation replaced encoded ancestor symlink");
      if Mode = "live" then
         Require
           (Ada.Directories.Exists (External_Record),
            "object operation removed external valid FOS record");
      else
         Require
           (not Ada.Directories.Exists (Missing_Directory),
            "object operation materialized dangling encoded ancestor");
      end if;
   end;

   --  The objects directory is a required layout root, never an optional
   --  directory that Put_Object may recreate or traverse through a symlink.
   declare
      Object_Bucket : constant String := "objects-root-bucket";
      Objects : constant String :=
        Join (Join (Join (Root, "buckets"), Object_Bucket), "objects");
      External_Objects : constant String :=
        Join (Outside, "external-objects-root");
      External_Record : constant String :=
        Join (External_Objects, "65787465726E616C.fos");
   begin
      Store.Create_Bucket
        (Object_Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require (Result = Storage.Success, "objects-root bucket setup failed");
      Put (Object_Bucket, "external", "external-record");
      if Mode = "live" then
         Ada.Directories.Rename (Objects, External_Objects);
      else
         Ada.Directories.Delete_Tree (Objects);
      end if;
      Create_Symlink
        ((if Mode = "live" then External_Objects else Missing_Directory),
         Objects, "objects-root");
      Expect_Object_Namespace_Failure
        (Object_Bucket, "external", "objects-root symlink");
      Require
        (GNAT.OS_Lib.Is_Symbolic_Link (Objects),
         "object operation replaced objects-root symlink");
      if Mode = "live" then
         Require
           (Ada.Directories.Exists (External_Record),
            "object operation removed external objects-root record");
      else
         Require
           (not Ada.Directories.Exists (Missing_Directory),
            "object operation materialized dangling objects root");
      end if;
   end;

   if Mode = "live" then
      declare
         Missing_Bucket : constant String := "missing-objects-root";
         Wrong_Bucket : constant String := "wrong-objects-root";
         Missing_Objects : constant String :=
           Join (Join (Join (Root, "buckets"), Missing_Bucket), "objects");
         Wrong_Objects : constant String :=
           Join (Join (Join (Root, "buckets"), Wrong_Bucket), "objects");
         File : Ada.Text_IO.File_Type;
      begin
         Store.Create_Bucket
           (Missing_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require (Result = Storage.Success, "missing-root bucket setup");
         Ada.Directories.Delete_Tree (Missing_Objects);
         Expect_Object_Namespace_Failure
           (Missing_Bucket, "key", "missing objects root");
         Require
           (not Ada.Directories.Exists (Missing_Objects),
            "Put_Object silently repaired a missing objects root");

         Store.Create_Bucket
           (Wrong_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require (Result = Storage.Success, "wrong-root bucket setup");
         Ada.Directories.Delete_Tree (Wrong_Objects);
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Wrong_Objects);
         Ada.Text_IO.Put_Line (File, "not-a-directory");
         Ada.Text_IO.Close (File);
         Expect_Object_Namespace_Failure
           (Wrong_Bucket, "key", "non-directory objects root");
      end;
   end if;

   --  Multipart layout roots, upload directories, manifests, and parts are
   --  all owned namespace components. None may redirect an operation outside
   --  the store or be silently omitted by a listing.
   declare
      Multipart_Bucket : constant String := "multipart-root-bucket";
      Upload_ID, Part_ETag : US.Unbounded_String;
   begin
      Prepare_Multipart (Multipart_Bucket, Upload_ID, Part_ETag);
      declare
         Multipart : constant String :=
           Join (Join (Join (Root, "buckets"), Multipart_Bucket),
                 "multipart");
         External_Multipart : constant String :=
           Join (Outside, "external-multipart-root");
         External_Part : constant String :=
           Join
             (Join
                (External_Multipart,
                 GNAT.SHA256.Digest (US.To_String (Upload_ID))),
              "part-1.fos");
      begin
         if Mode = "live" then
            Ada.Directories.Rename (Multipart, External_Multipart);
         else
            Ada.Directories.Delete_Tree (Multipart);
         end if;
         Create_Symlink
           ((if Mode = "live" then
               External_Multipart
             else Missing_Directory),
            Multipart, "multipart-root");
         Expect_Upload_Namespace_Failure
           (Multipart_Bucket, US.To_String (Upload_ID), Part_ETag, True);
         Require
           (GNAT.OS_Lib.Is_Symbolic_Link (Multipart),
            "multipart operation replaced multipart-root symlink");
         if Mode = "live" then
            Require
              (Ada.Directories.Exists (External_Part),
               "multipart operation removed external staged part");
         else
            Require
              (not Ada.Directories.Exists (Missing_Directory),
               "multipart operation materialized dangling root");
         end if;
      end;
   end;

   declare
      Multipart_Bucket : constant String := "multipart-upload-bucket";
      Upload_ID, Part_ETag : US.Unbounded_String;
   begin
      Prepare_Multipart (Multipart_Bucket, Upload_ID, Part_ETag);
      declare
         Upload : constant String :=
           Join
             (Join
                (Join (Join (Root, "buckets"), Multipart_Bucket),
                 "multipart"),
              GNAT.SHA256.Digest (US.To_String (Upload_ID)));
         External_Upload : constant String :=
           Join (Outside, "external-upload-directory");
         External_Part : constant String :=
           Join (External_Upload, "part-1.fos");
      begin
         if Mode = "live" then
            Ada.Directories.Rename (Upload, External_Upload);
         else
            Ada.Directories.Delete_Tree (Upload);
         end if;
         Create_Symlink
           ((if Mode = "live" then External_Upload else Missing_Directory),
            Upload, "multipart-upload-directory");
         Expect_Upload_Namespace_Failure
           (Multipart_Bucket, US.To_String (Upload_ID), Part_ETag, True);
         if Mode = "live" then
            Require
              (Ada.Directories.Exists (External_Part),
               "multipart operation removed external upload part");
         else
            Require
              (not Ada.Directories.Exists (Missing_Directory),
               "multipart operation materialized dangling upload");
         end if;
      end;
   end;

   declare
      Multipart_Bucket : constant String := "multipart-manifest-bucket";
      Upload_ID, Part_ETag : US.Unbounded_String;
   begin
      Prepare_Multipart (Multipart_Bucket, Upload_ID, Part_ETag);
      declare
         Upload : constant String :=
           Join
             (Join
                (Join (Join (Root, "buckets"), Multipart_Bucket),
                 "multipart"),
              GNAT.SHA256.Digest (US.To_String (Upload_ID)));
         Manifest : constant String := Join (Upload, "upload.fos");
         External_Manifest : constant String :=
           Join (Outside, "external-upload-manifest");
      begin
         if Mode = "live" then
            Ada.Directories.Rename (Manifest, External_Manifest);
         else
            Ada.Directories.Delete_File (Manifest);
         end if;
         Create_Symlink
           ((if Mode = "live" then
               External_Manifest
             else Missing),
            Manifest, "multipart-manifest");
         Expect_Upload_Namespace_Failure
           (Multipart_Bucket, US.To_String (Upload_ID), Part_ETag, True);
         if Mode = "live" then
            Require
              (Ada.Directories.Exists (External_Manifest),
               "multipart operation removed external manifest");
         else
            Require
              (not Ada.Directories.Exists (Missing),
               "multipart operation materialized dangling manifest");
         end if;
      end;
   end;

   --  An existing upload directory without its required manifest is corrupt,
   --  not an unknown upload id.
   declare
      Multipart_Bucket : constant String := "multipart-missing-manifest";
      Upload_ID, Part_ETag : US.Unbounded_String;
   begin
      Prepare_Multipart (Multipart_Bucket, Upload_ID, Part_ETag);
      declare
         Upload : constant String :=
           Join
             (Join
                (Join (Join (Root, "buckets"), Multipart_Bucket),
                 "multipart"),
              GNAT.SHA256.Digest (US.To_String (Upload_ID)));
         Manifest : constant String := Join (Upload, "upload.fos");
         Saved_Manifest : constant String :=
           Join (Outside, "saved-missing-upload-manifest");
         Part : constant String := Join (Upload, "part-1.fos");
      begin
         Ada.Directories.Rename (Manifest, Saved_Manifest);
         Expect_Upload_Namespace_Failure
           (Multipart_Bucket, US.To_String (Upload_ID), Part_ETag, True);
         Require
           (Ada.Directories.Exists (Saved_Manifest),
            "multipart operation removed the saved missing manifest");
         Require
           (Ada.Directories.Exists (Part),
            "multipart operation mutated a corrupt upload");
      end;
   end;

   declare
      Multipart_Bucket : constant String := "multipart-part-bucket";
      Upload_ID, Part_ETag : US.Unbounded_String;
   begin
      Prepare_Multipart (Multipart_Bucket, Upload_ID, Part_ETag);
      declare
         Upload : constant String :=
           Join
             (Join
                (Join (Join (Root, "buckets"), Multipart_Bucket),
                 "multipart"),
              GNAT.SHA256.Digest (US.To_String (Upload_ID)));
         Part : constant String := Join (Upload, "part-1.fos");
         External_Part : constant String :=
           Join (Outside, "external-upload-part");
      begin
         if Mode = "live" then
            Ada.Directories.Rename (Part, External_Part);
         else
            Ada.Directories.Delete_File (Part);
         end if;
         Create_Symlink
           ((if Mode = "live" then External_Part else Missing),
            Part, "multipart-part");
         Expect_Upload_Namespace_Failure
           (Multipart_Bucket, US.To_String (Upload_ID), Part_ETag, False);
         if Mode = "live" then
            Require
              (Ada.Directories.Exists (External_Part),
               "multipart operation removed external part");
         else
            Require
              (not Ada.Directories.Exists (Missing),
               "multipart operation materialized dangling part");
         end if;
      end;
   end;

   if Mode = "live" then
      declare
         Multipart_Bucket : constant String := "multipart-part-kind";
         Upload_ID, Part_ETag : US.Unbounded_String;
      begin
         Prepare_Multipart (Multipart_Bucket, Upload_ID, Part_ETag);
         declare
            Upload : constant String :=
              Join
                (Join
                   (Join (Join (Root, "buckets"), Multipart_Bucket),
                    "multipart"),
                 GNAT.SHA256.Digest (US.To_String (Upload_ID)));
            Part : constant String := Join (Upload, "part-1.fos");
         begin
            Ada.Directories.Delete_File (Part);
            Ada.Directories.Create_Directory (Part);
            Expect_Upload_Namespace_Failure
              (Multipart_Bucket, US.To_String (Upload_ID),
               Part_ETag, False);
         end;
      end;
   end if;

   --  A created bucket always owns a configuration directory.  Its absence
   --  is corrupt layout, not an unconfigured-versioning state that permits a
   --  Require_Unversioned delete.
   declare
      Configuration_Bucket : constant String := "missing-configuration";
      Bucket_Directory : constant String :=
        Join (Join (Root, "buckets"), Configuration_Bucket);
      Configuration : constant String :=
        Join (Bucket_Directory, "configuration");
      Saved_Configuration : constant String :=
        Join (Outside, "saved-missing-configuration");
   begin
      Store.Create_Bucket
        (Configuration_Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Success, "missing-configuration bucket setup");
      Put (Configuration_Bucket, "preserved", "preserved-body");
      Store.Put_Bucket_Versioning
        (Configuration_Bucket,
         (Status => Storage.Versioning_Enabled, others => <>),
         null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Success, "missing-configuration versioning setup");
      Ada.Directories.Rename (Configuration, Saved_Configuration);
      declare
         Observed_Configuration : Storage.Bucket_Versioning_Configuration;
         Observed_Tags : Tags.Tag_Set;
      begin
         Store.Get_Bucket_Versioning
           (Configuration_Bucket, null, Ada.Real_Time.Time_Last,
            Observed_Configuration, Result);
         Require
           (Result = Storage.Backend_Unavailable,
            "Get_Bucket_Versioning accepted an absent configuration root");
         Store.Put_Bucket_Versioning
           (Configuration_Bucket,
            (Status => Storage.Versioning_Suspended, others => <>),
            null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Storage.Backend_Unavailable,
            "Put_Bucket_Versioning recreated an absent configuration root");
         Store.Get_Bucket_Tags
           (Configuration_Bucket, null, Ada.Real_Time.Time_Last,
            Observed_Tags, Result);
         Require
           (Result = Storage.Backend_Unavailable,
            "Get_Bucket_Tags accepted an absent configuration root");
         Store.Put_Bucket_Tags
           (Configuration_Bucket, Tag_Set, null,
            Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Storage.Backend_Unavailable,
            "Put_Bucket_Tags recreated an absent configuration root");
         Store.Delete_Bucket_Tags
           (Configuration_Bucket, null, Ada.Real_Time.Time_Last, Result);
         Require
           (Result = Storage.Backend_Unavailable,
            "Delete_Bucket_Tags accepted an absent configuration root");
         Require
           (not Ada.Directories.Exists (Configuration),
            "configuration consumer silently repaired corrupt layout");
         Require
           (Ada.Directories.Exists (Saved_Configuration),
            "configuration consumer removed the saved configuration");
      end;
      Store.Delete_Object
        (Configuration_Bucket, "preserved", null,
         Ada.Real_Time.Time_Last, Result,
         Requirements => (Require_Unversioned => True, others => <>));
      Require
        (Result = Storage.Backend_Unavailable,
         "Delete_Object accepted an absent configuration root");
      Store.Head_Object
        (Configuration_Bucket, "preserved", null,
         Ada.Real_Time.Time_Last, Info, Result);
      Require
        (Result = Storage.Success,
         "absent configuration root allowed object deletion");
   end;

   Create_Symlink
     ((if Mode = "live" then External_Directory else Missing_Directory),
      Bucket_Link_Path, "bucket-root");
   declare
      Blocked_Source : Buffer_Source :=
        (Data => Flyology.Bytes.From_Byte_String ("must-not-consume"),
         Position => 0);
      Blocked_Info : Storage.Object_Information;
   begin
      Store.Put_Object
        ("root-link-bucket", "blocked", Blocked_Source,
         Storage.Default_Put_Options, null, Ada.Real_Time.Time_Last,
         Blocked_Info, Result,
         Conditions =>
           (If_None_Match => US.To_Unbounded_String ("*"), others => <>));
      Require
        (Result = Storage.Backend_Unavailable,
         "conditional Put_Object accepted a bucket-root symlink");
      Require
        (Blocked_Source.Position = 0,
         "bucket-root preflight consumed the Put_Object source");
   end;
   Store.Delete_Object
     ("root-link-bucket", "absent", null, Ada.Real_Time.Time_Last, Result,
      Conditions =>
        (Has_ETag => True,
         ETag => US.To_Unbounded_String ("*"),
         others => <>),
      Requirements => (Require_Unversioned => True, others => <>));
   Require
     (Result = Storage.Backend_Unavailable,
      "Delete_Object accepted a bucket-root symlink");
   Require
     (GNAT.OS_Lib.Is_Symbolic_Link (Bucket_Link_Path),
      "Delete_Object replaced the bucket-root symlink");
   Store.Create_Bucket
     ("root-link-bucket", null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Create_Bucket accepted a bucket-target symlink");
   Store.Head_Bucket
     ("root-link-bucket", null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Head_Bucket accepted a bucket-root symlink");
   Store.Delete_Bucket
     ("root-link-bucket", null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Delete_Bucket accepted a bucket-root symlink");
   Store.Put_Bucket_Tags
     ("root-link-bucket", Tag_Set, null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Put_Bucket_Tags accepted a bucket-root symlink");
   declare
      Observed : Tags.Tag_Set;
      Configuration : Storage.Bucket_Versioning_Configuration;
   begin
      Store.Get_Bucket_Tags
        ("root-link-bucket", null, Ada.Real_Time.Time_Last, Observed, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Tags accepted a bucket-root symlink");
      Store.Get_Bucket_Versioning
        ("root-link-bucket", null, Ada.Real_Time.Time_Last,
         Configuration, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Get_Bucket_Versioning accepted a bucket-root symlink");
      Store.Put_Bucket_Versioning
        ("root-link-bucket",
         (Status => Storage.Versioning_Enabled, others => <>),
         null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "Put_Bucket_Versioning accepted a bucket-root symlink");
   end;
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open
           (File, Ada.Text_IO.In_File, External_Directory_Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-directory-sentinel",
            "Delete_Object modified the external bucket-root target");
         Ada.Text_IO.Close (File);
      end;
   else
      Require
        (not Ada.Directories.Exists (Missing_Directory),
         "Delete_Object created a dangling bucket-root target");
   end if;

   Store.Delete_Bucket
     ("symlink-bucket", null, Ada.Real_Time.Time_Last, Result);
   Require
     (Result = Storage.Backend_Unavailable,
      "Delete_Bucket traversed a poisoned configuration tree");
   if Mode = "live" then
      declare
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Open
           (File, Ada.Text_IO.In_File, External_Directory_Sentinel);
         Require
           (Ada.Text_IO.Get_Line (File) = "outside-directory-sentinel",
            "Delete_Bucket modified external configuration data");
         Ada.Text_IO.Close (File);
      end;
   end if;

   --  Required roots are revalidated on each operation, and the temp root is
   --  checked before any staging write that precedes publication admission.
   declare
      Buckets : constant String := Join (Root, "buckets");
      External_Buckets : constant String :=
        Join (Outside, "moved-required-buckets");
      Before_Count : Natural;
   begin
      Ada.Directories.Rename (Buckets, External_Buckets);
      Before_Count := Entry_Count (External_Buckets);
      Create_Symlink
        ((if Mode = "live" then External_Buckets else Missing_Directory),
         Buckets, "required-buckets-root");
      Store.Head_Bucket
        (Copy_Source_Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "read accepted replaced required buckets root");
      Store.Create_Bucket
        ("replacement-probe", null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "write accepted replaced required buckets root");
      Require
        (GNAT.OS_Lib.Is_Symbolic_Link (Buckets),
         "operation replaced required buckets-root symlink");
      Require
        (Entry_Count (External_Buckets) = Before_Count,
         "operation created an entry through live buckets root");
      if Mode = "dangling" then
         Require
           (not Ada.Directories.Exists (Missing_Directory),
            "operation materialized dangling buckets root");
      end if;
      Ada.Directories.Delete_File (Buckets);
      Ada.Directories.Rename (External_Buckets, Buckets);
   end;

   declare
      Temp : constant String := Join (Root, "tmp");
      External_Temp : constant String :=
        Join (Outside, "moved-required-tmp");
      External_Temp_Sentinel : constant String :=
        Join (External_Temp, "sentinel");
   begin
      Ada.Directories.Rename (Temp, External_Temp);
      if Mode = "live" then
         declare
            File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Create
              (File, Ada.Text_IO.Out_File, External_Temp_Sentinel);
            Ada.Text_IO.Put_Line (File, "tmp-sentinel");
            Ada.Text_IO.Close (File);
         end;
      end if;
      Create_Symlink
        ((if Mode = "live" then External_Temp else Missing_Directory),
         Temp, "required-tmp-root");
      Put
        (Copy_Source_Bucket, "tmp-root-write", "must-not-stage",
         Storage.Backend_Unavailable);
      Store.Head_Bucket
        (Copy_Source_Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "read accepted replaced required tmp root");
      if Mode = "live" then
         declare
            File : Ada.Text_IO.File_Type;
         begin
            Ada.Text_IO.Open
              (File, Ada.Text_IO.In_File, External_Temp_Sentinel);
            Require
              (Ada.Text_IO.Get_Line (File) = "tmp-sentinel",
               "pre-admission staging modified external tmp root");
            Ada.Text_IO.Close (File);
            Require
              (Entry_Count (External_Temp) = 1,
               "pre-admission staging created external tmp entries");
         end;
      else
         Require
           (not Ada.Directories.Exists (Missing_Directory),
            "pre-admission staging materialized dangling tmp root");
      end if;
      Ada.Directories.Delete_File (Temp);
      Ada.Directories.Rename (External_Temp, Temp);
   end;

   if Mode = "live" then
      declare
         Temp : constant String := Join (Root, "tmp");
         External_Temp : constant String :=
           Join (Outside, "moved-nondirectory-tmp");
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Directories.Rename (Temp, External_Temp);
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Temp);
         Ada.Text_IO.Put_Line (File, "not-a-directory");
         Ada.Text_IO.Close (File);
         Put
           (Copy_Source_Bucket, "wrong-tmp-kind", "must-not-stage",
            Storage.Backend_Unavailable);
         Ada.Directories.Delete_File (Temp);
         Ada.Directories.Rename (External_Temp, Temp);
      end;
   end if;

   declare
      External_Root : constant String := Root & "-moved-root";
   begin
      Ada.Directories.Rename (Root, External_Root);
      Create_Symlink
        ((if Mode = "live" then External_Root else Root & "-missing-root"),
         Root, "requested-store-root");
      Store.Head_Bucket
        (Copy_Source_Bucket, null, Ada.Real_Time.Time_Last, Result);
      Require
        (Result = Storage.Backend_Unavailable,
         "read accepted replaced requested store root");
      Put
        (Copy_Source_Bucket, "root-write", "must-not-stage",
         Storage.Backend_Unavailable);
      Require
        (GNAT.OS_Lib.Is_Symbolic_Link (Root),
         "operation replaced requested-root symlink");
      Ada.Directories.Delete_File (Root);
      Ada.Directories.Rename (External_Root, Root);
   end;
end Files_Conditional_Symlink_Probe;
