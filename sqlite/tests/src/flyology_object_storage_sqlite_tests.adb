with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Conditional_Put_Conformance;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.IO;
with Flyology.Object_Storage.SQLite;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with Flyology.Object_Storage.SQLite.Catalogs;
with Flyology.Object_Storage.SQLite.Databases;
with Flyology.Object_Storage.Tags;

procedure Flyology_Object_Storage_Sqlite_Tests is
   package Databases renames Flyology.Object_Storage.SQLite.Databases;
   package Catalogs renames Flyology.Object_Storage.SQLite.Catalogs;
   package US renames Ada.Strings.Unbounded;
   use type Databases.Step_Result;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Flyology.Object_Storage.Status;
   use type Flyology.Object_Storage.Bucket_Versioning_Status;
   use type Flyology.Object_Storage.MFA_Delete_Status;
   use type Flyology.Object_Storage.Object_Tag_Set;
   use type Flyology.Object_Storage.Tags.Tag_Vectors.Vector;

   package Storage_Tags renames Flyology.Object_Storage.Tags;

   function Tag_Item (Key, Value : String) return Storage_Tags.Tag is
     ((Key   => US.To_Unbounded_String (Key),
       Value => US.To_Unbounded_String (Value)));

   Expected_Source : constant String :=
     "2026-07-24 19:02:57 " &
     "bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc";

   Database_Path : constant String := "obj/database-wrapper.sqlite";
   Backend_Root : constant String := "obj/sqlite-backend";
   Conditional_Root : constant String := "obj/sqlite-conditional-backend";
   SQLite_Upload_ID : US.Unbounded_String;
   SQLite_Part_ETag : US.Unbounded_String;
   SQLite_Abort_ID  : US.Unbounded_String;
   SQLite_Bucket_Created : Flyology.Object_Storage.Unix_Time := 0;

   procedure Assert (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Assert;

   procedure Delete_Database is
   begin
      if Ada.Directories.Exists (Database_Path) then
         Ada.Directories.Delete_File (Database_Path);
      end if;
      if Ada.Directories.Exists (Database_Path & "-wal") then
         Ada.Directories.Delete_File (Database_Path & "-wal");
      end if;
      if Ada.Directories.Exists (Database_Path & "-shm") then
         Ada.Directories.Delete_File (Database_Path & "-shm");
      end if;
   end Delete_Database;

   function Regular_File_Count (Directory : String) return Natural is
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Count  : Natural := 0;
   begin
      Ada.Directories.Start_Search
        (Search, Directory, "*",
         (Ada.Directories.Ordinary_File => True, others => False));
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Count := Count + 1;
      end loop;
      Ada.Directories.End_Search (Search);
      return Count;
   exception
      when others =>
         Ada.Directories.End_Search (Search);
         raise;
   end Regular_File_Count;

   procedure Create_V2_Database is
      Legacy : Databases.Database;
   begin
      Databases.Open (Legacy, Database_Path);
      Databases.Execute
        (Legacy,
         "CREATE TABLE buckets (" &
         "name TEXT PRIMARY KEY COLLATE BINARY NOT NULL" &
         ") WITHOUT ROWID;" &
         "CREATE TABLE objects (" &
         "bucket_name TEXT NOT NULL COLLATE BINARY," &
         "object_key BLOB NOT NULL," &
         "payload TEXT NOT NULL UNIQUE," &
         "size INTEGER NOT NULL CHECK(size >= 0)," &
         "modified INTEGER NOT NULL CHECK(modified >= 0)," &
         "entity_tag BLOB NOT NULL," &
         "content_type BLOB NOT NULL," &
         "PRIMARY KEY(bucket_name, object_key)," &
         "FOREIGN KEY(bucket_name) REFERENCES buckets(name) " &
         "ON DELETE RESTRICT" &
         ") WITHOUT ROWID;" &
         "CREATE TABLE multipart_uploads (" &
         "upload_id TEXT PRIMARY KEY COLLATE BINARY NOT NULL," &
         "bucket_name TEXT NOT NULL COLLATE BINARY," &
         "object_key BLOB NOT NULL," &
         "content_type BLOB NOT NULL," &
         "created INTEGER NOT NULL CHECK(created >= 0)," &
         "FOREIGN KEY(bucket_name) REFERENCES buckets(name) " &
         "ON DELETE RESTRICT" &
         ") WITHOUT ROWID;" &
         "CREATE TABLE multipart_parts (" &
         "upload_id TEXT NOT NULL COLLATE BINARY," &
         "part_number INTEGER NOT NULL " &
         "CHECK(part_number BETWEEN 1 AND 10000)," &
         "payload TEXT NOT NULL UNIQUE," &
         "size INTEGER NOT NULL CHECK(size >= 0)," &
         "modified INTEGER NOT NULL CHECK(modified >= 0)," &
         "entity_tag BLOB NOT NULL," &
         "PRIMARY KEY(upload_id,part_number)," &
         "FOREIGN KEY(upload_id) REFERENCES multipart_uploads(upload_id) " &
         "ON DELETE CASCADE" &
         ") WITHOUT ROWID;" &
         "INSERT INTO buckets(name) VALUES('legacy-bucket');" &
         "PRAGMA application_id=1179603761;" &
         "PRAGMA user_version=2;");
      Databases.Close (Legacy);
   exception
      when others =>
         if Databases.Is_Open (Legacy) then
            Databases.Close (Legacy);
         end if;
         raise;
   end Create_V2_Database;

   procedure Create_V1_Database is
      Legacy : Databases.Database;
   begin
      Create_V2_Database;
      Databases.Open (Legacy, Database_Path);
      Databases.Execute
        (Legacy,
         "DROP TABLE multipart_parts;" &
         "DROP TABLE multipart_uploads;" &
         "PRAGMA user_version=1;");
      Databases.Close (Legacy);
   exception
      when others =>
         if Databases.Is_Open (Legacy) then
            Databases.Close (Legacy);
         end if;
         raise;
   end Create_V1_Database;

   procedure Create_V3_Database is
      Legacy : Databases.Database;
   begin
      Create_V2_Database;
      Databases.Open (Legacy, Database_Path);
      Databases.Execute
        (Legacy,
         "ALTER TABLE buckets ADD COLUMN created INTEGER NOT NULL " &
         "DEFAULT 0 CHECK(created >= 0);" &
         "PRAGMA user_version=3;");
      Databases.Close (Legacy);
   exception
      when others =>
         if Databases.Is_Open (Legacy) then
            Databases.Close (Legacy);
         end if;
         raise;
   end Create_V3_Database;

   type V4_Tag_Layout is
     (Object_Tags_Only, Bucket_Tags_Only, Versioning_Only);

   procedure Create_V4_Database (Layout : V4_Tag_Layout) is
      Legacy : Databases.Database;
   begin
      Create_V3_Database;
      Databases.Open (Legacy, Database_Path);
      case Layout is
         when Object_Tags_Only =>
            Databases.Execute
              (Legacy,
               "CREATE TABLE object_tags (" &
            "bucket_name TEXT NOT NULL COLLATE BINARY," &
            "object_key BLOB NOT NULL," &
            "tag_index INTEGER NOT NULL CHECK(tag_index BETWEEN 1 AND 10)," &
            "tag_key BLOB NOT NULL," &
            "tag_value BLOB NOT NULL," &
            "PRIMARY KEY(bucket_name,object_key,tag_index)," &
            "UNIQUE(bucket_name,object_key,tag_key)," &
            "FOREIGN KEY(bucket_name,object_key) " &
            "REFERENCES objects(bucket_name,object_key) ON DELETE CASCADE" &
            ") WITHOUT ROWID;" &
            "INSERT INTO objects VALUES" &
            "('legacy-bucket',X'6B','legacy-payload',1,1," &
            "X'65',X'74');" &
            "INSERT INTO object_tags VALUES" &
            "('legacy-bucket',X'6B',1,X'7374617465',X'6F6C64');");
         when Bucket_Tags_Only =>
            Databases.Execute
              (Legacy,
               "CREATE TABLE bucket_tags (" &
            "bucket_name TEXT NOT NULL COLLATE BINARY," &
            "ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 1 AND 50)," &
            "tag_key BLOB NOT NULL CHECK(length(tag_key) BETWEEN 1 AND 512)," &
            "tag_value BLOB NOT NULL CHECK(length(tag_value) <= 1024)," &
            "PRIMARY KEY(bucket_name,tag_key)," &
            "UNIQUE(bucket_name,ordinal)," &
            "FOREIGN KEY(bucket_name) " &
            "REFERENCES buckets(name) ON DELETE CASCADE" &
            ") WITHOUT ROWID;" &
            "INSERT INTO bucket_tags VALUES" &
            "('legacy-bucket',1,X'7374617465',X'6F6C64');");
         when Versioning_Only =>
            Databases.Execute
              (Legacy,
               "ALTER TABLE buckets ADD COLUMN versioning_status INTEGER " &
               "NOT NULL DEFAULT 0 CHECK(versioning_status BETWEEN 0 AND 2);" &
               "ALTER TABLE buckets ADD COLUMN mfa_delete_status INTEGER " &
               "NOT NULL DEFAULT 0 " &
               "CHECK(mfa_delete_status BETWEEN 0 AND 2);" &
               "UPDATE buckets SET versioning_status=1," &
               "mfa_delete_status=2 WHERE name='legacy-bucket';");
      end case;
      Databases.Execute (Legacy, "PRAGMA user_version=4;");
      Databases.Close (Legacy);
   exception
      when others =>
         if Databases.Is_Open (Legacy) then
            Databases.Close (Legacy);
         end if;
         raise;
   end Create_V4_Database;

   type V5_Layout is (Attributes_Layout, Bucket_Tags_Layout);

   procedure Create_V5_Database (Layout : V5_Layout) is
      Legacy : Databases.Database;
   begin
      Create_V4_Database (Object_Tags_Only);
      Databases.Open (Legacy, Database_Path);
      case Layout is
         when Attributes_Layout =>
            Databases.Execute
              (Legacy,
               "CREATE TABLE object_parts (" &
               "bucket_name TEXT NOT NULL COLLATE BINARY," &
               "object_key BLOB NOT NULL," &
               "part_number INTEGER NOT NULL " &
               "CHECK(part_number BETWEEN 1 AND 10000)," &
               "size INTEGER NOT NULL CHECK(size >= 0)," &
               "PRIMARY KEY(bucket_name,object_key,part_number)," &
               "FOREIGN KEY(bucket_name,object_key) " &
               "REFERENCES objects(bucket_name,object_key) ON DELETE CASCADE" &
               ") WITHOUT ROWID;" &
               "INSERT INTO object_parts VALUES" &
               "('legacy-bucket',X'6B',1,1);");
         when Bucket_Tags_Layout =>
            Databases.Execute
              (Legacy,
               "CREATE TABLE bucket_tags (" &
               "bucket_name TEXT NOT NULL COLLATE BINARY," &
               "ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 1 AND 50)," &
               "tag_key BLOB NOT NULL " &
               "CHECK(length(tag_key) BETWEEN 1 AND 512)," &
               "tag_value BLOB NOT NULL CHECK(length(tag_value) <= 1024)," &
               "PRIMARY KEY(bucket_name,tag_key)," &
               "UNIQUE(bucket_name,ordinal)," &
               "FOREIGN KEY(bucket_name) " &
               "REFERENCES buckets(name) ON DELETE CASCADE" &
               ") WITHOUT ROWID;" &
               "INSERT INTO bucket_tags VALUES" &
               "('legacy-bucket',1,X'70726F6A656374',X'666C796F6C6F6779');");
      end case;
      Databases.Execute (Legacy, "PRAGMA user_version=5;");
      Databases.Close (Legacy);
   exception
      when others =>
         if Databases.Is_Open (Legacy) then
            Databases.Close (Legacy);
         end if;
         raise;
   end Create_V5_Database;

   procedure Create_V6_Database is
      Legacy : Databases.Database;
   begin
      Create_V5_Database (Attributes_Layout);
      Databases.Open (Legacy, Database_Path);
      Databases.Execute
        (Legacy,
         "CREATE TABLE bucket_tags (" &
         "bucket_name TEXT NOT NULL COLLATE BINARY," &
         "ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 1 AND 50)," &
         "tag_key BLOB NOT NULL CHECK(length(tag_key) BETWEEN 1 AND 512)," &
         "tag_value BLOB NOT NULL CHECK(length(tag_value) <= 1024)," &
         "PRIMARY KEY(bucket_name,tag_key)," &
         "UNIQUE(bucket_name,ordinal)," &
         "FOREIGN KEY(bucket_name) " &
         "REFERENCES buckets(name) ON DELETE CASCADE" &
         ") WITHOUT ROWID;" &
         "INSERT INTO bucket_tags VALUES" &
         "('legacy-bucket',1,X'70726F6A656374',X'666C796F6C6F6779');" &
         "PRAGMA user_version=6;");
      Databases.Close (Legacy);
   exception
      when others =>
         if Databases.Is_Open (Legacy) then
            Databases.Close (Legacy);
         end if;
         raise;
   end Create_V6_Database;

   procedure Assert_Unconfigured_Versioning
     (Catalog : in out Catalogs.Catalog;
      Bucket  : String;
      Label   : String)
   is
      Configuration : Flyology.Object_Storage.
        Bucket_Versioning_Configuration;
      Result : Flyology.Object_Storage.Status;
   begin
      Catalogs.Get_Bucket_Versioning
        (Catalog, Bucket, Configuration, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Configuration.Status =
           Flyology.Object_Storage.Versioning_Unconfigured
         and then Configuration.MFA_Delete =
           Flyology.Object_Storage.MFA_Delete_Unconfigured,
         Label);
   end Assert_Unconfigured_Versioning;

   type Buffer_Source is new
     Flyology.Object_Storage.Backends.Byte_Source with
   record
      Data     : Flyology.Bytes.Unbounded_Bytes;
      Position : Natural := 0;
      Length   : Flyology.Object_Storage.Backends.Source_Length :=
        (Kind => Flyology.Object_Storage.Backends.Unknown);
   end record;

   overriding function Declared_Length
     (Item : Buffer_Source)
      return Flyology.Object_Storage.Backends.Source_Length is (Item.Length);

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

   type Buffer_Sink is new Flyology.Object_Storage.Backends.Byte_Sink with
   record
      Data               : Flyology.Bytes.Unbounded_Bytes;
      Begun              : Boolean := False;
      Begin_Count        : Natural := 0;
      First              : Flyology.Object_Storage.Byte_Count := 0;
      Content_Length     : Flyology.Object_Storage.Byte_Count := 0;
      Partial            : Boolean := False;
      Snapshot           : Flyology.Object_Storage.Object_Information;
      Write_Before_Begin : Boolean := False;
   end record;

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Begin_Object
     (Item           : in out Buffer_Sink;
      Info           : Flyology.Object_Storage.Object_Information;
      First          : Flyology.Object_Storage.Byte_Count;
      Content_Length : Flyology.Object_Storage.Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      Item.Begun := True;
      Item.Begin_Count := Item.Begin_Count + 1;
      Item.First := First;
      Item.Content_Length := Content_Length;
      Item.Partial := Partial;
      Item.Snapshot := Info;
   end Begin_Object;

   procedure Exercise_Conditional_Read
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String;
      Key    : String)
   is
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      Snapshot   : Object_Information;
      Result     : Status;
      Conditions : Read_Conditions := Default_Read_Conditions;

      procedure Read_And_Require
        (Expected : Status; Expected_Begins : Natural; Message : String)
      is
         Sink : Buffer_Sink;
         Info : Object_Information;
         Head_Info : Object_Information;
         Head_Result : Status;
      begin
         Store.Get_Object
           (Bucket, Key, Whole_Object, Sink, null,
            Ada.Real_Time.Time_Last, Info, Result, Conditions);
         Assert
           (Result = Expected
            and then Sink.Begin_Count = Expected_Begins
            and then (if Expected /= Success
                      then Info.Size = Snapshot.Size
                        and then Info.Modified = Snapshot.Modified
                        and then US.To_String (Info.Entity_Tag) =
                          US.To_String (Snapshot.Entity_Tag)),
            Message);
         Store.Head_Object
           (Bucket, Key, null, Ada.Real_Time.Time_Last, Head_Info,
            Head_Result, Conditions);
         Assert
           (Head_Result = Expected
            and then Head_Info.Size = Snapshot.Size
            and then Head_Info.Modified = Snapshot.Modified
            and then US.To_String (Head_Info.Entity_Tag) =
              US.To_String (Snapshot.Entity_Tag),
            "SQLite atomic HeadObject: " & Message);
      end Read_And_Require;
   begin
      Store.Head_Object
        (Bucket, Key, null, Ada.Real_Time.Time_Last, Snapshot, Result);
      Assert (Result = Success, "SQLite conditional-read setup head");

      Conditions.If_Match := US.To_Unbounded_String
        ('"' & US.To_String (Snapshot.Entity_Tag) & '"');
      Conditions.If_Unmodified_Since :=
        (Is_Set => True, Value => Long_Long_Integer (Snapshot.Modified) - 1);
      Read_And_Require
        (Success, 1, "SQLite If-Match precedence failed");

      Conditions := Default_Read_Conditions;
      Conditions.If_Match := US.To_Unbounded_String ("""wrong""");
      Read_And_Require
        (Precondition_Failed, 0,
         "SQLite failed If-Match reached the response sink");

      Conditions := Default_Read_Conditions;
      Conditions.If_None_Match := US.To_Unbounded_String
        ("W/""" & US.To_String (Snapshot.Entity_Tag) & """");
      Read_And_Require
        (Not_Modified, 0,
         "SQLite weak If-None-Match emitted an object body");

      Conditions.If_None_Match := US.To_Unbounded_String ("""other""");
      Conditions.If_Modified_Since :=
        (Is_Set => True, Value => Long_Long_Integer'Last);
      Read_And_Require
        (Success, 1, "SQLite If-None-Match precedence failed");

      Conditions := Default_Read_Conditions;
      Conditions.If_Modified_Since :=
        (Is_Set => True, Value => Long_Long_Integer (Snapshot.Modified));
      Read_And_Require
        (Not_Modified, 0,
         "SQLite equal If-Modified-Since emitted an object body");

      Conditions := Default_Read_Conditions;
      Conditions.If_Unmodified_Since :=
        (Is_Set => True, Value => Long_Long_Integer (Snapshot.Modified) - 1);
      Read_And_Require
        (Precondition_Failed, 0,
         "SQLite failed If-Unmodified-Since reached the response sink");

      Conditions := Default_Read_Conditions;
      Conditions.If_None_Match := US.To_Unbounded_String ("*, ""other""");
      Read_And_Require
        (Invalid_Request, 0,
         "SQLite accepted a mixed wildcard entity-tag list");
   end Exercise_Conditional_Read;

   overriding procedure Write
     (Item     : in out Buffer_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Token, Deadline);
   begin
      if not Item.Begun then
         Item.Write_Before_Begin := True;
      end if;
      Flyology.Bytes.Append (Item.Data, Data);
   end Write;

   type Raising_Sink is new Flyology.Object_Storage.Backends.Byte_Sink
     with null record;

   overriding procedure Write
     (Item     : in out Raising_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time);

   overriding procedure Begin_Object
     (Item           : in out Raising_Sink;
      Info           : Flyology.Object_Storage.Object_Information;
      First          : Flyology.Object_Storage.Byte_Count;
      Content_Length : Flyology.Object_Storage.Byte_Count;
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
     (Item     : in out Raising_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time)
   is
      pragma Unreferenced (Item, Data, Token, Deadline);
   begin
      raise Program_Error with "sink sentinel";
   end Write;

   Database : Databases.Database;
   Catalog : aliased Catalogs.Catalog;

   type Catalog_Access is access all Catalogs.Catalog;

   protected Monitor is
      procedure Record_Failure;
      function Failures return Natural;
   private
      Count : Natural := 0;
   end Monitor;

   protected body Monitor is
      procedure Record_Failure is
      begin
         Count := Count + 1;
      end Record_Failure;

      function Failures return Natural is (Count);
   end Monitor;

   task type Catalog_Worker
     (Item : Catalog_Access; Identifier : Positive);

   task body Catalog_Worker is
      Result : Flyology.Object_Storage.Status;
      Name   : constant String := "worker" & Positive'Image (Identifier);
   begin
      for Iteration in 1 .. 50 loop
         Catalogs.Create_Bucket (Item.all, Name, 1, Result);
         if Result /= Flyology.Object_Storage.Success then
            Monitor.Record_Failure;
            exit;
         end if;
         Catalogs.Delete_Bucket (Item.all, Name, Result);
         if Result /= Flyology.Object_Storage.Success then
            Monitor.Record_Failure;
            exit;
         end if;
      end loop;
   exception
      when others =>
         Monitor.Record_Failure;
   end Catalog_Worker;
begin
   if Flyology.Object_Storage.SQLite.SQLite_Version /= "3.53.4" then
      raise Program_Error with "unexpected SQLite version";
   end if;
   if Flyology.Object_Storage.SQLite.SQLite_Source_ID /= Expected_Source then
      raise Program_Error with "unexpected SQLite source ID";
   end if;
   if not Flyology.Object_Storage.SQLite.SQLite_Threadsafe then
      raise Program_Error with "SQLite must be threadsafe";
   end if;

   Delete_Database;
   Databases.Open (Database, Database_Path);

   declare
      Unprepared : Databases.Statement;
   begin
      begin
         Assert (Databases.Step (Unprepared) = Databases.Done, "unreachable");
         raise Program_Error with "unprepared statement could step";
      exception
         when Databases.SQLite_Error => null;
      end;
   end;

   Databases.Execute
     (Database,
      "CREATE TABLE records (" &
      "id INTEGER PRIMARY KEY, label TEXT NOT NULL, amount INTEGER, " &
      "absent TEXT, opaque BLOB)");

   Databases.Begin_Transaction (Database);
   declare
      Insert : Databases.Statement;
      Value  : constant String := "O'Brien" & Character'Val (0) & "tail";
   begin
      Databases.Prepare
        (Insert, Database,
         "INSERT INTO records(label, amount, absent, opaque) " &
         "VALUES(?1, ?2, ?3, ?4)");
      Databases.Bind (Insert, 1, Value);
      Databases.Bind (Insert, 2, Long_Long_Integer'First);
      Databases.Bind_Null (Insert, 3);
      Databases.Bind_Bytes
        (Insert, 4, Character'Val (255) & Character'Val (0) & "bytes");
      Assert
        (Databases.Step (Insert) = Databases.Done, "insert did not finish");
      Assert (Databases.Changes (Database) = 1, "unexpected insert count");

      begin
         Assert (Databases.Step (Insert) = Databases.Done, "unreachable");
         raise Program_Error with "completed statement could step again";
      exception
         when Databases.SQLite_Error => null;
      end;
   end;
   Databases.Commit (Database);

   declare
      Select_Row : Databases.Statement;
      Expected   : constant String := "O'Brien" & Character'Val (0) & "tail";
   begin
      Databases.Prepare
        (Select_Row, Database,
         "SELECT label, amount, absent, opaque FROM records ORDER BY id");
      Assert
        (Databases.Step (Select_Row) = Databases.Row, "row was not found");
      Assert (Databases.Column (Select_Row, 0) = Expected,
              "embedded NUL text did not round-trip");
      Assert
        (Databases.Column (Select_Row, 1) = Long_Long_Integer'First,
         "64-bit integer did not round-trip");
      Assert
        (Databases.Column_Is_Null (Select_Row, 2), "NULL was not preserved");
      Assert
        (Databases.Column_Bytes (Select_Row, 3) =
           Character'Val (255) & Character'Val (0) & "bytes",
         "opaque BLOB did not round-trip");
      begin
         Assert (Databases.Column_Is_Null (Select_Row, 4), "unreachable");
         raise Program_Error with "out-of-range column was readable";
      exception
         when Databases.SQLite_Error => null;
      end;
      Assert (Databases.Step (Select_Row) = Databases.Done,
              "select returned an extra row");

      begin
         Assert (Databases.Column_Is_Null (Select_Row, 0), "unreachable");
         raise Program_Error with "column was readable after completion";
      exception
         when Databases.SQLite_Error => null;
      end;

      Databases.Reset (Select_Row);
      Assert (Databases.Step (Select_Row) = Databases.Row,
              "reset statement did not return its row");
   end;

   Databases.Begin_Transaction (Database, Databases.Exclusive);
   Databases.Execute
     (Database,
      "INSERT INTO records(label, amount) VALUES('rolled back', 1)");
   Databases.Rollback (Database);
   declare
      Count : Databases.Statement;
   begin
      Databases.Prepare (Count, Database, "SELECT count(*) FROM records");
      Assert
        (Databases.Step (Count) = Databases.Row, "count row was not found");
      Assert
        (Databases.Column (Count, 0) = 1, "rollback did not restore state");
   end;

   begin
      Databases.Execute (Database, "THIS IS NOT SQL");
      raise Program_Error with "invalid SQL was accepted";
   exception
      when Databases.SQLite_Error => null;
   end;

   declare
      Empty : Databases.Statement;
   begin
      begin
         Databases.Prepare (Empty, Database, " -- comment only");
         raise Program_Error with "empty SQL prepared a statement";
      exception
         when Databases.SQLite_Error => null;
      end;
   end;

   Databases.Close (Database);
   begin
      Databases.Execute (Database, "SELECT 1");
      raise Program_Error with "closed database accepted SQL";
   exception
      when Databases.SQLite_Error => null;
   end;
   Delete_Database;

   Catalogs.Open (Catalog, Database_Path);
   declare
      Result   : Flyology.Object_Storage.Status;
      Payload  : US.Unbounded_String;
      Previous : US.Unbounded_String;
      Info     : Flyology.Object_Storage.Object_Information;
      Found    : Flyology.Object_Storage.Object_Information;
      Key      : constant String := Character'Val (255) & "/opaque-key";
      Wanted   : Flyology.Object_Storage.Object_Tag_Set :=
        Flyology.Object_Storage.Empty_Object_Tags;
      Tags     : Flyology.Object_Storage.Object_Tag_Set;
      Versioning : Flyology.Object_Storage.Bucket_Versioning_Configuration;
   begin
      Catalogs.Create_Bucket (Catalog, "catalog-bucket", 1_234_500, Result);
      Assert (Result = Flyology.Object_Storage.Success,
              "catalog bucket was not created");
      Catalogs.Head_Bucket (Catalog, "catalog-bucket", Result);
      Assert (Result = Flyology.Object_Storage.Success,
              "catalog bucket was not found by head");
      Catalogs.Create_Bucket (Catalog, "catalog-bucket", 9_999_999, Result);
      Assert (Result = Flyology.Object_Storage.Already_Exists,
              "duplicate catalog bucket was accepted");

      declare
         Value    : Storage_Tags.Tag_Set;
         Observed : Storage_Tags.Tag_Set;
      begin
         Catalogs.Get_Bucket_Tags
           (Catalog, "catalog-bucket", Observed, Result);
         Assert
           (Result = Flyology.Object_Storage.Tag_Set_Not_Found
            and then Observed.Is_Empty,
            "new catalog bucket unexpectedly had tags");
         Value.Append (Tag_Item ("project", "flyology"));
         Value.Append (Tag_Item ("environment", "test"));
         Catalogs.Put_Bucket_Tags
           (Catalog, "catalog-bucket", Value, Result);
         Catalogs.Get_Bucket_Tags
           (Catalog, "catalog-bucket", Observed, Result);
         Assert
           (Result = Flyology.Object_Storage.Success
            and then Observed = Value,
            "catalog bucket tags did not round trip");
         Value.Clear;
         Value.Append (Tag_Item ("replacement", "complete"));
         Catalogs.Put_Bucket_Tags
           (Catalog, "catalog-bucket", Value, Result);
         Catalogs.Get_Bucket_Tags
           (Catalog, "catalog-bucket", Observed, Result);
         Assert
           (Result = Flyology.Object_Storage.Success
            and then Observed = Value,
            "catalog bucket tag replacement retained old rows");
      end;

      Catalogs.Get_Bucket_Versioning
        (Catalog, "catalog-bucket", Versioning, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Versioning.Status =
           Flyology.Object_Storage.Versioning_Unconfigured
         and then Versioning.MFA_Delete =
           Flyology.Object_Storage.MFA_Delete_Unconfigured,
         "new catalog bucket invented versioning configuration");
      Catalogs.Put_Bucket_Versioning
        (Catalog, "catalog-bucket",
         (Status => Flyology.Object_Storage.Versioning_Enabled,
          MFA_Delete => Flyology.Object_Storage.MFA_Delete_Unconfigured),
         Result);
      Catalogs.Put_Bucket_Versioning
        (Catalog, "catalog-bucket",
         (Status => Flyology.Object_Storage.Versioning_Unconfigured,
          MFA_Delete => Flyology.Object_Storage.MFA_Delete_Disabled),
         Result);
      Catalogs.Get_Bucket_Versioning
        (Catalog, "catalog-bucket", Versioning, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Versioning.Status =
           Flyology.Object_Storage.Versioning_Enabled
         and then Versioning.MFA_Delete =
           Flyology.Object_Storage.MFA_Delete_Disabled,
         "catalog versioning fields were not merged atomically");

      Info :=
        (Size         => 42,
         Modified     => 1_234_567,
         Entity_Tag   => US.To_Unbounded_String
           (Character'Val (0) & Character'Val (255) & "etag"),
         Content_Type => US.To_Unbounded_String ("application/test"),
         Version      => US.Null_Unbounded_String);
      Catalogs.Put_Object
        (Catalog, "catalog-bucket", Key, "payload-one", Info,
         Previous, Result);
      Assert (Result = Flyology.Object_Storage.Success,
              "catalog object was not inserted");
      Assert (US.Length (Previous) = 0,
              "new catalog object had a previous payload");
      Catalogs.Find_Object
        (Catalog, "catalog-bucket", Key, Payload, Found, Result);
      Assert (Result = Flyology.Object_Storage.Success,
              "catalog object was not found");
      Assert (US.To_String (Payload) = "payload-one",
              "catalog payload name changed");
      Assert
        (Found.Size = Info.Size and then Found.Modified = Info.Modified,
         "catalog numeric metadata changed");
      Assert
        (US.To_String (Found.Entity_Tag) = US.To_String (Info.Entity_Tag),
         "catalog opaque metadata changed");

      Wanted.Length := 2;
      Wanted.Items (1) :=
        (Key => US.To_Unbounded_String ("environment"),
         Value => US.To_Unbounded_String ("production"));
      Wanted.Items (2) :=
        (Key => US.To_Unbounded_String ("team"),
         Value => US.To_Unbounded_String ("storage/core"));
      Catalogs.Put_Object_Tags
        (Catalog, "catalog-bucket", Key, Wanted, Result);
      Catalogs.Get_Object_Tags
        (Catalog, "catalog-bucket", Key, Tags, Result);
      Assert
        (Result = Flyology.Object_Storage.Success and then Tags = Wanted,
         "catalog object tags did not round-trip atomically");

      Catalogs.Delete_Bucket (Catalog, "catalog-bucket", Result);
      Assert (Result = Flyology.Object_Storage.Bucket_Not_Empty,
              "nonempty catalog bucket was deleted");

      Info.Size := 7;
      Catalogs.Put_Object
        (Catalog, "catalog-bucket", Key, "payload-two", Info,
         Previous, Result);
      Assert
        (Result = Flyology.Object_Storage.Success and then
         US.To_String (Previous) = "payload-one",
         "catalog replacement did not return the old payload");
      Catalogs.Get_Object_Tags
        (Catalog, "catalog-bucket", Key, Tags, Result);
      Assert
        (Result = Flyology.Object_Storage.Success and then Tags.Length = 0,
         "catalog object replacement retained stale tags");
      Catalogs.Put_Object_Tags
        (Catalog, "catalog-bucket", Key, Wanted, Result);
      Assert
        (Result = Flyology.Object_Storage.Success,
         "catalog persisted tag setup failed");
      declare
         use Flyology.Object_Storage;
         use Flyology.Object_Storage.Backends;
         Upload_ID : constant String := "catalog-multipart-upload";
         Part_Info : Object_Information :=
           (Size         => 5 * 1_024 * 1_024,
            Modified     => 99,
            Entity_Tag   => US.To_Unbounded_String
              ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            Content_Type => US.Null_Unbounded_String,
            Version      => US.Null_Unbounded_String);
         Part_Previous : US.Unbounded_String;
         References : Multipart_Part_References;
         Records : Catalogs.Multipart_Part_Records;
         Retired : Catalogs.Payloads;
      begin
         Catalogs.Create_Multipart_Upload
           (Catalog, "catalog-bucket", "multipart-key", Upload_ID,
            "application/test", 98, Result);
         Assert (Result = Success, "catalog multipart create failed");
         Catalogs.Put_Multipart_Part
           (Catalog, "catalog-bucket", "multipart-key", Upload_ID, 1,
            "part-payload-one", Part_Info, Part_Previous, Result);
         Assert
           (Result = Success and then US.Length (Part_Previous) = 0,
            "catalog first multipart part failed");
         Part_Info.Size := 4;
         Part_Info.Entity_Tag :=
           US.To_Unbounded_String ("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb");
         Catalogs.Put_Multipart_Part
           (Catalog, "catalog-bucket", "multipart-key", Upload_ID, 2,
            "part-payload-two", Part_Info, Part_Previous, Result);
         Assert (Result = Success, "catalog second multipart part failed");
         declare
            Page : Multipart_Part_Page;
            Options : List_Multipart_Parts_Options :=
              (After => 0, Maximum => 1);
         begin
            Catalogs.List_Multipart_Parts
              (Catalog, "catalog-bucket", "multipart-key", Upload_ID,
               Options, Page, Result);
            Assert
              (Result = Success and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Number = 1
               and then Page.Parts.First_Element.Info.Size =
                 5 * 1_024 * 1_024
               and then Page.Is_Truncated and then Page.Next_After = 1,
               "catalog ListParts first page failed");
            Options.After := Page.Next_After;
            Catalogs.List_Multipart_Parts
              (Catalog, "catalog-bucket", "multipart-key", Upload_ID,
               Options, Page, Result);
            Assert
              (Result = Success and then Page.Parts.Length = 1
               and then Page.Parts.First_Element.Number = 2
               and then Page.Parts.First_Element.Info.Size = 4
               and then not Page.Is_Truncated,
               "catalog ListParts continuation failed");
         end;
         References.Append
           (Multipart_Part_Reference'
              (Number => 1,
               Entity_Tag => US.To_Unbounded_String
                 ("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")));
         References.Append
           (Multipart_Part_Reference'
              (Number => 2,
               Entity_Tag => US.To_Unbounded_String
                 ("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")));
         Catalogs.Read_Multipart_Parts
           (Catalog, "catalog-bucket", "multipart-key", Upload_ID,
            References, Records, Result);
         Assert
           (Result = Success and then Records.Length = 2,
            "catalog could not read two multipart parts");
         Info :=
           (Size         => 5 * 1_024 * 1_024 + 4,
            Modified     => 100,
            Entity_Tag   => US.To_Unbounded_String
              ("cccccccccccccccccccccccccccccccc-2"),
            Content_Type => US.To_Unbounded_String ("application/test"),
            Version      => US.Null_Unbounded_String);
         Catalogs.Complete_Multipart_Upload
           (Catalog, "catalog-bucket", "multipart-key", Upload_ID, Records,
            "multipart-final-payload", Info, (others => <>), Previous,
            Retired, Result);
         Assert
           (Result = Success and then Retired.Length = 2
            and then US.Length (Previous) = 0,
            "catalog two-part completion failed");
      end;
   end;

   declare
      Worker_1 : Catalog_Worker (Catalog'Access, 1);
      Worker_2 : Catalog_Worker (Catalog'Access, 2);
      Worker_3 : Catalog_Worker (Catalog'Access, 3);
      Worker_4 : Catalog_Worker (Catalog'Access, 4);
   begin
      null;
   end;
   Assert (Monitor.Failures = 0,
           "concurrent catalog operations were not serialized safely");
   Catalogs.Close (Catalog);

   Catalogs.Open (Catalog, Database_Path);
   declare
      Result  : Flyology.Object_Storage.Status;
      Payload : US.Unbounded_String;
      Key     : constant String := Character'Val (255) & "/opaque-key";
      Wanted  : Flyology.Object_Storage.Object_Tag_Set :=
        Flyology.Object_Storage.Empty_Object_Tags;
      Tags    : Flyology.Object_Storage.Object_Tag_Set;
      Versioning : Flyology.Object_Storage.Bucket_Versioning_Configuration;
   begin
      Wanted.Length := 2;
      Wanted.Items (1) :=
        (Key => US.To_Unbounded_String ("environment"),
         Value => US.To_Unbounded_String ("production"));
      Wanted.Items (2) :=
        (Key => US.To_Unbounded_String ("team"),
         Value => US.To_Unbounded_String ("storage/core"));
      Catalogs.Get_Object_Tags
        (Catalog, "catalog-bucket", Key, Tags, Result);
      Assert
        (Result = Flyology.Object_Storage.Success and then Tags = Wanted,
         "catalog object tags did not persist across reopen");
      Catalogs.Delete_Object_Tags
        (Catalog, "catalog-bucket", Key, Result);
      Catalogs.Get_Object_Tags
        (Catalog, "catalog-bucket", Key, Tags, Result);
      Assert
        (Result = Flyology.Object_Storage.Success and then Tags.Length = 0,
         "catalog tag deletion did not clear the complete set");
      declare
         Expected : Storage_Tags.Tag_Set;
         Observed : Storage_Tags.Tag_Set;
      begin
         Expected.Append (Tag_Item ("replacement", "complete"));
         Catalogs.Get_Bucket_Tags
           (Catalog, "catalog-bucket", Observed, Result);
         Assert
           (Result = Flyology.Object_Storage.Success
            and then Observed = Expected,
            "catalog bucket tags did not survive reopen");
      end;
      Catalogs.Get_Bucket_Versioning
        (Catalog, "catalog-bucket", Versioning, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Versioning.Status =
           Flyology.Object_Storage.Versioning_Enabled
         and then Versioning.MFA_Delete =
           Flyology.Object_Storage.MFA_Delete_Disabled,
         "catalog versioning configuration did not survive reopen");
      declare
         use Flyology.Object_Storage.Backends;
         Entries  : Delete_Object_Entries;
         Outcomes : Delete_Object_Outcomes;
         Retired  : Catalogs.Payloads;
         Injector : Databases.Database;
         Raised   : Boolean := False;
         Found    : Flyology.Object_Storage.Object_Information;
      begin
         Entries.Append
           (Delete_Object_Entry'
              (Key        => US.To_Unbounded_String (Key),
               Conditions => No_Delete_Object_Conditions));
         Entries.Append
           (Delete_Object_Entry'
              (Key        => US.To_Unbounded_String ("multipart-key"),
               Conditions => No_Delete_Object_Conditions));
         Databases.Open (Injector, Database_Path);
         Databases.Execute
           (Injector,
            "CREATE TRIGGER fail_delete_objects BEFORE DELETE ON objects " &
            "WHEN OLD.object_key=CAST('multipart-key' AS BLOB) BEGIN " &
            "SELECT RAISE(ABORT,'delete-objects failpoint'); END;");
         Databases.Close (Injector);
         begin
            Catalogs.Delete_Objects
              (Catalog, "catalog-bucket", Entries, (others => <>),
               Retired, Outcomes, Result);
         exception
            when others => Raised := True;
         end;
         Assert
           (Raised and then Retired.Is_Empty and then Outcomes.Is_Empty,
            "DeleteObjects catalog failpoint did not roll back outputs");
         Catalogs.Find_Object
           (Catalog, "catalog-bucket", Key, Payload, Found, Result);
         Assert
           (Result = Flyology.Object_Storage.Success,
            "DeleteObjects rollback lost the first catalog row");
         Catalogs.Find_Object
           (Catalog, "catalog-bucket", "multipart-key",
            Payload, Found, Result);
         Assert
           (Result = Flyology.Object_Storage.Success,
            "DeleteObjects rollback lost the triggering catalog row");
         Databases.Open (Injector, Database_Path);
         Databases.Execute (Injector, "DROP TRIGGER fail_delete_objects;");
         Databases.Close (Injector);
         Catalogs.Delete_Objects
           (Catalog, "catalog-bucket", Entries, (others => <>), Retired,
            Outcomes, Result);
         Assert
           (Result = Flyology.Object_Storage.Success
            and then Outcomes.Length = 2
            and then Outcomes (1).Result = Flyology.Object_Storage.Success
            and then Outcomes (2).Result = Flyology.Object_Storage.Success
            and then Retired.Length = 2
            and then US.To_String (Retired (0)) = "payload-two"
            and then US.To_String (Retired (1)) =
              "multipart-final-payload",
            "transactional catalog DeleteObjects result ordering");
      end;
      Catalogs.Delete_Bucket (Catalog, "catalog-bucket", Result);
      Assert (Result = Flyology.Object_Storage.Success,
              "empty catalog bucket was not deleted");
      Catalogs.Delete_Bucket (Catalog, "catalog-bucket", Result);
      Assert (Result = Flyology.Object_Storage.Not_Found,
              "missing catalog bucket did not report not-found");
   end;
   Catalogs.Close (Catalog);
   Delete_Database;

   Create_V1_Database;
   Catalogs.Open (Catalog, Database_Path);
   Assert_Unconfigured_Versioning
     (Catalog, "legacy-bucket",
      "schema-v1 migration invented versioning configuration");
   declare
      use Flyology.Object_Storage.Backends;
      Result : Flyology.Object_Storage.Status;
      Entries : Delete_Object_Entries;
      Outcomes : Delete_Object_Outcomes;
      Retired : Catalogs.Payloads;
   begin
      Catalogs.Head_Bucket (Catalog, "legacy-bucket", Result);
      Assert
        (Result = Flyology.Object_Storage.Success,
         "schema-v1 migration did not preserve the bucket namespace");
      Entries.Append
        (Delete_Object_Entry'
           (Key        => US.To_Unbounded_String ("migration-missing"),
            Conditions => No_Delete_Object_Conditions));
      Catalogs.Delete_Objects
        (Catalog, "legacy-bucket", Entries, (others => <>), Retired,
         Outcomes, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Outcomes.Length = 1
         and then Outcomes.First_Element.Result =
           Flyology.Object_Storage.Success
         and then Retired.Is_Empty,
         "schema-v1 migration did not support DeleteObjects");
   end;
   Catalogs.Close (Catalog);
   Databases.Open (Database, Database_Path);
   declare
      Version : Databases.Statement;
      Tables  : Databases.Statement;
   begin
      Databases.Prepare (Version, Database, "PRAGMA user_version");
      Assert
        (Databases.Step (Version) = Databases.Row
         and then Databases.Column (Version, 0) = 7,
         "schema-v1 migration did not publish version 7");
      Databases.Prepare
        (Tables, Database,
         "SELECT count(*) FROM sqlite_master WHERE type='table' " &
         "AND name IN ('buckets','objects','object_tags'," &
         "'multipart_uploads','multipart_parts','object_parts'," &
         "'bucket_tags')");
      Assert
        (Databases.Step (Tables) = Databases.Row
         and then Databases.Column (Tables, 0) = 7,
         "schema-v1 migration did not create the complete schema");
   end;
   Databases.Close (Database);
   Delete_Database;

   Create_V2_Database;
   Catalogs.Open (Catalog, Database_Path);
   declare
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      Options : List_Buckets_Options;
      Page    : Bucket_Page;
      Result  : Status;
      Value   : Storage_Tags.Tag_Set;
      Observed : Storage_Tags.Tag_Set;

      procedure Check is null;
   begin
      Catalogs.Create_Bucket (Catalog, "new-bucket", 42, Result);
      Assert (Result = Success, "post-migration bucket create failed");
      Catalogs.List_Buckets
        (Catalog, Options, Check'Access, Page, Result);
      Assert
        (Result = Success and then Page.Buckets.Length = 2
         and then US.To_String (Page.Buckets (1).Name) = "legacy-bucket"
         and then Page.Buckets (1).Created = 0
         and then US.To_String (Page.Buckets (2).Name) = "new-bucket"
         and then Page.Buckets (2).Created = 42,
         "schema-v2 bucket migration did not preserve timestamps");
      Assert_Unconfigured_Versioning
        (Catalog, "legacy-bucket",
         "schema-v2 migration invented versioning configuration");
      Catalogs.Get_Bucket_Tags
        (Catalog, "legacy-bucket", Observed, Result);
      Assert
        (Result = Tag_Set_Not_Found and then Observed.Is_Empty,
         "schema-v2 migration fabricated a legacy tag set");
      Value.Append (Tag_Item ("migrated", "yes"));
      Catalogs.Put_Bucket_Tags
        (Catalog, "legacy-bucket", Value, Result);
      Catalogs.Get_Bucket_Tags
        (Catalog, "legacy-bucket", Observed, Result);
      Assert
        (Result = Success and then Observed = Value,
         "schema-v2 migration did not install the bucket tag table");
      Catalogs.Delete_Bucket_Tags
        (Catalog, "legacy-bucket", Result);
      Catalogs.Get_Bucket_Tags
        (Catalog, "legacy-bucket", Observed, Result);
      Assert
        (Result = Tag_Set_Not_Found and then Observed.Is_Empty,
         "schema-v2 migration did not support bucket tag deletion");
      Catalogs.Delete_Bucket (Catalog, "legacy-bucket", Result);
      Assert (Result = Success, "legacy bucket cleanup failed");
      Catalogs.Delete_Bucket (Catalog, "new-bucket", Result);
      Assert (Result = Success, "post-migration bucket cleanup failed");
   end;
   Catalogs.Close (Catalog);
   Databases.Open (Database, Database_Path);
   declare
      Version : Databases.Statement;
   begin
      Databases.Prepare (Version, Database, "PRAGMA user_version");
      Assert
        (Databases.Step (Version) = Databases.Row
         and then Databases.Column (Version, 0) = 7,
         "schema-v2 migration did not publish version 7");
   end;
   declare
      Tables : Databases.Statement;
   begin
      Databases.Prepare
         (Tables, Database,
         "SELECT count(*) FROM sqlite_master WHERE type='table' " &
         "AND name IN ('object_tags','object_parts','bucket_tags')");
      Assert
        (Databases.Step (Tables) = Databases.Row
         and then Databases.Column (Tables, 0) = 3,
         "schema-v2 migration did not create attribute and tag tables");
   end;
   Databases.Close (Database);
   Delete_Database;

   Create_V3_Database;
   Catalogs.Open (Catalog, Database_Path);
   Assert_Unconfigured_Versioning
     (Catalog, "legacy-bucket",
      "schema-v3 migration invented versioning configuration");
   Catalogs.Close (Catalog);
   Databases.Open (Database, Database_Path);
   declare
      Version : Databases.Statement;
      Table_Count : Databases.Statement;
   begin
      Databases.Prepare (Version, Database, "PRAGMA user_version");
      Databases.Prepare
        (Table_Count, Database,
         "SELECT count(*) FROM sqlite_schema " &
         "WHERE type='table' " &
         "AND name IN ('object_tags','object_parts','bucket_tags')");
      Assert
        (Databases.Step (Version) = Databases.Row
         and then Databases.Column (Version, 0) = 7
         and then Databases.Step (Table_Count) = Databases.Row
         and then Databases.Column (Table_Count, 0) = 3,
         "schema-v3 migration did not publish schema 7 tables");
   end;
   Databases.Close (Database);
   Delete_Database;

   for Layout in V4_Tag_Layout loop
      Create_V4_Database (Layout);
      Catalogs.Open (Catalog, Database_Path);
      declare
         Result : Flyology.Object_Storage.Status;
      begin
         case Layout is
            when Object_Tags_Only =>
               declare
                  Observed : Flyology.Object_Storage.Object_Tag_Set;
               begin
                  Catalogs.Get_Object_Tags
                    (Catalog, "legacy-bucket", "k", Observed, Result);
                  Assert
                    (Result = Flyology.Object_Storage.Success
                     and then Observed.Length = 1
                     and then US.To_String (Observed.Items (1).Key) = "state"
                     and then US.To_String (Observed.Items (1).Value) = "old",
                     "schema-v4 object tags were not preserved");
               end;
            when Bucket_Tags_Only =>
               declare
                  Observed : Storage_Tags.Tag_Set;
               begin
                  Catalogs.Get_Bucket_Tags
                    (Catalog, "legacy-bucket", Observed, Result);
                  Assert
                    (Result = Flyology.Object_Storage.Success
                     and then Observed.Length = 1
                     and then
                       US.To_String (Observed.First_Element.Key) = "state"
                     and then
                       US.To_String (Observed.First_Element.Value) = "old",
                     "schema-v4 bucket tags were not preserved");
               end;
            when Versioning_Only =>
               declare
                  Configuration : Flyology.Object_Storage.
                    Bucket_Versioning_Configuration;
               begin
                  Catalogs.Get_Bucket_Versioning
                    (Catalog, "legacy-bucket", Configuration, Result);
                  Assert
                    (Result = Flyology.Object_Storage.Success
                     and then Configuration.Status =
                       Flyology.Object_Storage.Versioning_Enabled
                     and then Configuration.MFA_Delete =
                       Flyology.Object_Storage.MFA_Delete_Disabled,
                     "schema-v4 versioning values were not preserved");
               end;
         end case;
         if Layout /= Versioning_Only then
            Assert_Unconfigured_Versioning
              (Catalog, "legacy-bucket",
               "schema-v4 tag migration invented versioning configuration");
         end if;
      end;
      Catalogs.Close (Catalog);
      Databases.Open (Database, Database_Path);
      declare
         Version : Databases.Statement;
         Tables  : Databases.Statement;
      begin
         Databases.Prepare (Version, Database, "PRAGMA user_version");
         Assert
           (Databases.Step (Version) = Databases.Row
            and then Databases.Column (Version, 0) = 7,
            "schema-v4 migration did not publish version 7");
         Databases.Prepare
            (Tables, Database,
             "SELECT count(*) FROM sqlite_master WHERE type='table' " &
            "AND name IN ('object_tags','object_parts','bucket_tags')");
         Assert
           (Databases.Step (Tables) = Databases.Row
            and then Databases.Column (Tables, 0) = 3,
            "schema-v4 migration did not publish the complete schema");
      end;
      Databases.Close (Database);
      Delete_Database;
   end loop;

   for Layout in V5_Layout loop
      Create_V5_Database (Layout);
      Catalogs.Open (Catalog, Database_Path);
      declare
         Result : Flyology.Object_Storage.Status;
         Observed_Tags : Flyology.Object_Storage.Object_Tag_Set;
      begin
         Catalogs.Get_Object_Tags
           (Catalog, "legacy-bucket", "k", Observed_Tags, Result);
         Assert
           (Result = Flyology.Object_Storage.Success
            and then Observed_Tags.Length = 1
            and then US.To_String (Observed_Tags.Items (1).Key) = "state"
            and then US.To_String (Observed_Tags.Items (1).Value) = "old",
            "schema-v5 migration did not preserve object tags");
         Assert_Unconfigured_Versioning
           (Catalog, "legacy-bucket",
            "schema-v5 migration invented versioning configuration");
         if Layout = Bucket_Tags_Layout then
            declare
               Observed : Storage_Tags.Tag_Set;
            begin
               Catalogs.Get_Bucket_Tags
                 (Catalog, "legacy-bucket", Observed, Result);
               Assert
                 (Result = Flyology.Object_Storage.Success
                  and then Observed.Length = 1
                  and then
                    US.To_String (Observed.First_Element.Key) = "project"
                  and then
                    US.To_String (Observed.First_Element.Value) = "flyology",
                  "schema-v5 migration did not preserve bucket tags");
            end;
         end if;
      end;
      Catalogs.Close (Catalog);
      Databases.Open (Database, Database_Path);
      declare
         Version : Databases.Statement;
         Tables  : Databases.Statement;
         Part_Rows : Databases.Statement;
      begin
         Databases.Prepare (Version, Database, "PRAGMA user_version");
         Databases.Prepare
           (Tables, Database,
            "SELECT count(*) FROM sqlite_master WHERE type='table' " &
            "AND name IN ('object_tags','object_parts','bucket_tags')");
         Databases.Prepare
           (Part_Rows, Database,
            "SELECT count(*) FROM object_parts WHERE " &
            "bucket_name='legacy-bucket' AND object_key=X'6B'");
         Assert
           (Databases.Step (Version) = Databases.Row
            and then Databases.Column (Version, 0) = 7
            and then Databases.Step (Tables) = Databases.Row
            and then Databases.Column (Tables, 0) = 3
            and then Databases.Step (Part_Rows) = Databases.Row
            and then Databases.Column (Part_Rows, 0) =
              (if Layout = Attributes_Layout then 1 else 0),
            "schema-v5 migration did not preserve the historical layout");
      end;
      Databases.Close (Database);
      Delete_Database;
   end loop;

   Create_V6_Database;
   Catalogs.Open (Catalog, Database_Path);
   declare
      Result : Flyology.Object_Storage.Status;
      Object_Tags : Flyology.Object_Storage.Object_Tag_Set;
      Bucket_Tags : Storage_Tags.Tag_Set;
      Configuration : Flyology.Object_Storage.
        Bucket_Versioning_Configuration;
   begin
      Catalogs.Get_Object_Tags
        (Catalog, "legacy-bucket", "k", Object_Tags, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Object_Tags.Length = 1
         and then US.To_String (Object_Tags.Items (1).Key) = "state",
         "schema-v6 migration did not preserve object tags");
      Catalogs.Get_Bucket_Tags
        (Catalog, "legacy-bucket", Bucket_Tags, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Bucket_Tags.Length = 1
         and then US.To_String (Bucket_Tags.First_Element.Key) = "project",
         "schema-v6 migration did not preserve bucket tags");
      Assert_Unconfigured_Versioning
        (Catalog, "legacy-bucket",
         "schema-v6 migration invented versioning configuration");
      Catalogs.Put_Bucket_Versioning
        (Catalog, "legacy-bucket",
         (Status => Flyology.Object_Storage.Versioning_Suspended,
          MFA_Delete => Flyology.Object_Storage.MFA_Delete_Disabled),
         Result);
      Catalogs.Get_Bucket_Versioning
        (Catalog, "legacy-bucket", Configuration, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Configuration.Status =
           Flyology.Object_Storage.Versioning_Suspended
         and then Configuration.MFA_Delete =
           Flyology.Object_Storage.MFA_Delete_Disabled,
         "schema-v6 migration could not persist versioning configuration");
   end;
   Catalogs.Close (Catalog);
   Catalogs.Open (Catalog, Database_Path);
   declare
      Configuration : Flyology.Object_Storage.
        Bucket_Versioning_Configuration;
      Result : Flyology.Object_Storage.Status;
   begin
      Catalogs.Get_Bucket_Versioning
        (Catalog, "legacy-bucket", Configuration, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then Configuration.Status =
           Flyology.Object_Storage.Versioning_Suspended
         and then Configuration.MFA_Delete =
           Flyology.Object_Storage.MFA_Delete_Disabled,
         "schema-v6 migrated versioning configuration did not survive reopen");
   end;
   Catalogs.Close (Catalog);
   Databases.Open (Database, Database_Path);
   declare
      Version : Databases.Statement;
   begin
      Databases.Prepare (Version, Database, "PRAGMA user_version");
      Assert
        (Databases.Step (Version) = Databases.Row
         and then Databases.Column (Version, 0) = 7,
         "schema-v6 migration did not publish version 7");
   end;
   Databases.Close (Database);
   Delete_Database;

   if Ada.Directories.Exists (Conditional_Root) then
      Ada.Directories.Delete_Tree (Conditional_Root);
   end if;
   declare
      package Backend renames Flyology.Object_Storage.Backends.SQLite;
      Store : Backend.Store :=
        Backend.Open (Conditional_Root, Maximum_Object_Size => 64);
   begin
      Conditional_Put_Conformance.Exercise
        (Store, "sqlite-conditional-bucket");
   end;
   Assert
     (Regular_File_Count (Conditional_Root & "/objects") = 33,
      "SQLite conditional failures leaked or retired live payloads");
   declare
      package Backend renames Flyology.Object_Storage.Backends.SQLite;
      use Flyology.Object_Storage;
      Store : Backend.Store := Backend.Open (Conditional_Root, 64);
      Info   : Object_Information;
      Result : Status;
      Sink   : Buffer_Sink;
   begin
      Store.Get_Object
        ("sqlite-conditional-bucket", "conditional-object", Whole_Object,
         Sink, null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Success
         and then Flyology.Bytes.To_Byte_String (Sink.Data) = "third"
         and then US.To_String (Info.Entity_Tag) = "generation-3"
         and then US.To_String (Info.Content_Type) = "application/test",
         "SQLite conditional publication did not survive reopen");
      Store.Head_Object
        ("sqlite-conditional-bucket", "conditional-race-32", null,
         Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Success and then Info.Size = 1,
         "SQLite concurrent conditional winner did not survive reopen");
   end;
   Ada.Directories.Delete_Tree (Conditional_Root);

   if Ada.Directories.Exists (Backend_Root) then
      Ada.Directories.Delete_Tree (Backend_Root);
   end if;
   declare
      package Backend renames Flyology.Object_Storage.Backends.SQLite;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      Store : Backend.Store :=
        Backend.Open (Backend_Root, Maximum_Object_Size => 64);
      Source : Buffer_Source :=
        (Data     => Flyology.Bytes.From_Byte_String ("first body"),
         Position => 0,
         Length   => (Kind => Flyology.Object_Storage.Backends.Known,
                      Bytes => 10));
      Info   : Object_Information;
      Result : Status;
      Key    : constant String := Character'Val (255) & "../../opaque/key";
      Wanted : Object_Tag_Set := Empty_Object_Tags;
      Tags   : Object_Tag_Set;

      function Listing_Bucket_Name (Index : Positive) return String is
        (case Index is
           when 1 => "list-zeta",
           when 2 => "list-alpha",
           when 3 => "unrelated-bucket",
           when others => raise Program_Error);
   begin
      declare
         Rejected : Boolean := False;
      begin
         begin
            declare
               Other : Backend.Store := Backend.Open (Backend_Root, 64);
               pragma Unreferenced (Other);
            begin
               null;
            end;
         exception
            when Backend.Configuration_Error =>
               Rejected := True;
         end;
         Assert (Rejected, "SQLite backend allowed a second root owner");
      end;
      Store.Delete_Object
        ("missing-bucket", "key", null, Ada.Real_Time.Time_Last, Result);
      Assert
        (Result = Bucket_Not_Found,
         "SQLite object delete did not distinguish an absent bucket");
      Store.Create_Bucket
        ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite backend bucket create failed");
      declare
         Value    : Storage_Tags.Tag_Set;
         Observed : Storage_Tags.Tag_Set;
         Cancel   : aliased Flyology.Cancellation.Token;
         Raised   : Boolean := False;
      begin
         Store.Get_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Observed, Result);
         Assert
           (Result = Tag_Set_Not_Found and then Observed.Is_Empty,
            "SQLite new bucket unexpectedly had tags");
         Store.Put_Bucket_Tags
           ("sqlite-bucket", Value, null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Invalid_Request,
            "SQLite accepted an empty bucket tag set");
         Value.Append (Tag_Item ("project", "flyology"));
         Value.Append (Tag_Item ("environment", "test"));
         Store.Put_Bucket_Tags
           ("sqlite-bucket", Value, null, Ada.Real_Time.Time_Last, Result);
         Store.Get_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Observed, Result);
         Assert
           (Result = Success and then Observed = Value,
            "SQLite backend bucket tags did not round trip");
         Value.Clear;
         Value.Append (Tag_Item ("replacement", "complete"));
         Store.Put_Bucket_Tags
           ("sqlite-bucket", Value, null, Ada.Real_Time.Time_Last, Result);
         Store.Get_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Observed, Result);
         Assert
           (Result = Success and then Observed = Value,
            "SQLite backend bucket tags were not atomically replaced");
         Store.Delete_Bucket_Tags
           ("missing-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Not_Found,
            "SQLite bucket tag delete lost missing-bucket status");
         Store.Delete_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "SQLite bucket tag deletion failed");
         Store.Get_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Observed, Result);
         Assert
           (Result = Tag_Set_Not_Found and then Observed.Is_Empty,
            "SQLite bucket tag deletion retained rows");
         Store.Delete_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success,
            "SQLite bucket tag deletion was not idempotent");
         Store.Put_Bucket_Tags
           ("sqlite-bucket", Value, null, Ada.Real_Time.Time_Last, Result);
         Assert
           (Result = Success,
            "SQLite bucket tags could not be restored after deletion");
         Cancel.Request;
         begin
            Store.Get_Bucket_Tags
              ("sqlite-bucket", Cancel'Access, Ada.Real_Time.Time_Last,
               Observed, Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled =>
               Raised := True;
         end;
         Assert (Raised, "SQLite bucket tag get ignored cancellation");
         Raised := False;
         begin
            Store.Delete_Bucket_Tags
              ("sqlite-bucket", Cancel'Access, Ada.Real_Time.Time_Last,
               Result);
         exception
            when Flyology.Cancellation.Operation_Cancelled =>
               Raised := True;
         end;
         Assert (Raised, "SQLite bucket tag delete ignored cancellation");
         Raised := False;
         begin
            Store.Delete_Bucket_Tags
              ("sqlite-bucket", null, Ada.Real_Time.Time_First, Result);
         exception
            when Flyology.IO.Timeout_Error =>
               Raised := True;
         end;
         Assert (Raised, "SQLite bucket tag delete ignored deadline");
      end;
      for Index in 1 .. 3 loop
         Store.Create_Bucket
           (Listing_Bucket_Name (Index), null, Ada.Real_Time.Time_Last,
            Result);
         Assert (Result = Success, "SQLite listing bucket create failed");
      end loop;
      declare
         Options : List_Buckets_Options :=
           (Prefix  => US.To_Unbounded_String ("list-"),
            After   => US.Null_Unbounded_String,
            Maximum => 1);
         Page : Bucket_Page;
      begin
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success and then Page.Buckets.Length = 1
            and then US.To_String (Page.Buckets.First_Element.Name) =
              "list-alpha"
            and then Page.Buckets.First_Element.Created > 0
            and then Page.Is_Truncated
            and then US.To_String (Page.Next_After) = "list-alpha",
            "SQLite backend bucket listing first page failed");
         Options.After := Page.Next_After;
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success and then Page.Buckets.Length = 1
            and then US.To_String (Page.Buckets.First_Element.Name) =
              "list-zeta"
            and then not Page.Is_Truncated,
            "SQLite backend bucket listing continuation failed");
         declare
            Cancel : aliased Flyology.Cancellation.Token;
            Raised : Boolean := False;
         begin
            Cancel.Request;
            begin
               Store.List_Buckets
                 (Options, Cancel'Access, Ada.Real_Time.Time_Last,
                  Page, Result);
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Raised := True;
            end;
            Assert (Raised, "SQLite bucket listing ignored cancellation");
         end;
      end;
      for Index in 1 .. 3 loop
         Store.Delete_Bucket
           (Listing_Bucket_Name (Index), null, Ada.Real_Time.Time_Last,
            Result);
         Assert (Result = Success, "SQLite listing bucket cleanup failed");
      end loop;
      declare
         Options : List_Buckets_Options;
         Page    : Bucket_Page;
      begin
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success and then Page.Buckets.Length = 1
            and then US.To_String (Page.Buckets.First_Element.Name) =
              "sqlite-bucket",
            "SQLite bucket listing cleanup snapshot failed");
         SQLite_Bucket_Created := Page.Buckets.First_Element.Created;
      end;
      Store.Head_Bucket
        ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite backend bucket head failed");
      declare
         Configuration : Bucket_Versioning_Configuration;
      begin
         Store.Get_Bucket_Versioning
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Configuration, Result);
         Assert
           (Result = Success
            and then Configuration.Status = Versioning_Unconfigured
            and then Configuration.MFA_Delete = MFA_Delete_Unconfigured,
            "SQLite backend invented initial versioning configuration");
         Store.Put_Bucket_Versioning
           ("sqlite-bucket",
            (Status => Versioning_Enabled,
             MFA_Delete => MFA_Delete_Unconfigured),
            null, Ada.Real_Time.Time_Last, Result);
         Store.Put_Bucket_Versioning
           ("sqlite-bucket",
            (Status => Versioning_Unconfigured,
             MFA_Delete => MFA_Delete_Disabled),
            null, Ada.Real_Time.Time_Last, Result);
         Store.Get_Bucket_Versioning
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Configuration, Result);
         Assert
           (Result = Success
            and then Configuration.Status = Versioning_Enabled
            and then Configuration.MFA_Delete = MFA_Delete_Disabled,
            "SQLite backend versioning fields did not merge atomically");
         Store.Get_Bucket_Versioning
           ("missing-bucket", null, Ada.Real_Time.Time_Last,
            Configuration, Result);
         Assert
           (Result = Not_Found,
            "SQLite versioning did not distinguish a missing bucket");
      end;
      Store.Put_Object
        ("sqlite-bucket", Key, Source,
         (Entity_Tag   => US.To_Unbounded_String ("etag-1"),
          Content_Type => US.To_Unbounded_String ("text/plain")),
         null, Ada.Real_Time.Time_Last, Info, Result);
      Assert (Result = Success and then Info.Size = 10,
              "SQLite backend put failed");
      Store.Get_Object_Tags
        ("missing-bucket", Key, null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Bucket_Not_Found,
         "SQLite tagging did not distinguish an absent bucket");
      Store.Get_Object_Tags
        ("sqlite-bucket", "missing", null, Ada.Real_Time.Time_Last,
         Tags, Result);
      Assert
        (Result = Not_Found,
         "SQLite tagging did not distinguish an absent object");
      Wanted.Length := 2;
      Wanted.Items (1) :=
        (Key => US.To_Unbounded_String ("environment"),
         Value => US.To_Unbounded_String ("production"));
      Wanted.Items (2) :=
        (Key => US.To_Unbounded_String ("team"),
         Value => US.To_Unbounded_String ("storage/core"));
      Store.Put_Object_Tags
        ("sqlite-bucket", Key, Wanted, null, Ada.Real_Time.Time_Last,
         Result);
      Store.Get_Object_Tags
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags = Wanted,
         "SQLite backend object tags did not round-trip");
      declare
         Replacement : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("second body"),
            Position => 0,
            Length   => (Kind => Flyology.Object_Storage.Backends.Known,
                         Bytes => 11));
      begin
         Store.Put_Object
           ("sqlite-bucket", Key, Replacement,
            (Entity_Tag   => US.To_Unbounded_String ("etag-2"),
             Content_Type => US.To_Unbounded_String ("text/plain")),
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success, "SQLite backend overwrite failed");
      end;
      Store.Get_Object_Tags
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags.Length = 0,
         "SQLite backend overwrite retained stale tags");
      Store.Put_Object_Tags
        ("sqlite-bucket", Key, Wanted, null, Ada.Real_Time.Time_Last,
         Result);
      Assert
        (Result = Success, "SQLite persisted tag setup failed");
      declare
         Empty_Source : Buffer_Source :=
           (Data     => Flyology.Bytes.Empty,
            Position => 0,
            Length   => (Kind => Flyology.Object_Storage.Backends.Known,
                         Bytes => 0));
      begin
         Store.Put_Object
           ("sqlite-bucket", "empty", Empty_Source, Default_Put_Options,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Success, "SQLite backend empty put failed");
      end;
      Store.Create_Multipart_Upload
        ("sqlite-bucket", "multipart-target",
         (Content_Type =>
            US.To_Unbounded_String ("application/x-multipart-test")),
         null, Ada.Real_Time.Time_Last, SQLite_Upload_ID, Result);
      Assert (Result = Success, "SQLite multipart create failed");
      declare
         Part_Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("multipart body"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 14));
      begin
         Store.Put_Multipart_Part
           ("sqlite-bucket", "multipart-target",
            US.To_String (SQLite_Upload_ID), 1, Part_Source, null,
            Ada.Real_Time.Time_Last, Info, Result);
         SQLite_Part_ETag := Info.Entity_Tag;
         Assert
           (Result = Success and then Info.Size = 14,
            "SQLite multipart part upload failed");
      end;
      declare
         Part_Source : Buffer_Source :=
           (Data     => Flyology.Bytes.From_Byte_String ("later"),
            Position => 0,
            Length   => (Kind => Known, Bytes => 5));
      begin
         Store.Put_Multipart_Part
           ("sqlite-bucket", "multipart-target",
            US.To_String (SQLite_Upload_ID), 3, Part_Source, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Info.Size = 5,
            "SQLite sparse multipart part upload failed");
      end;
      Store.Create_Multipart_Upload
        ("sqlite-bucket", "aborted-target", Default_Multipart_Options,
         null, Ada.Real_Time.Time_Last, SQLite_Abort_ID, Result);
      Assert (Result = Success, "SQLite second multipart create failed");
      declare
         Page    : Multipart_Upload_Page;
         Options : List_Multipart_Uploads_Options;
      begin
         Options.Maximum := 1;
         Store.List_Multipart_Uploads
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Uploads.Length = 1
            and then US.To_String (Page.Uploads.First_Element.Key) =
              "aborted-target"
            and then Page.Is_Truncated
            and then US.To_String (Page.Next_After.Key) = "aborted-target"
            and then US.To_String (Page.Next_After.Upload_ID) =
              US.To_String (SQLite_Abort_ID),
            "SQLite multipart upload listing first page failed");
         Options.After := Page.Next_After;
         Store.List_Multipart_Uploads
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Uploads.Length = 1
            and then US.To_String (Page.Uploads.First_Element.Key) =
              "multipart-target"
            and then US.To_String
              (Page.Uploads.First_Element.Options.Content_Type) =
                "application/x-multipart-test"
            and then not Page.Is_Truncated,
            "SQLite multipart upload listing continuation failed");
         Options := (others => <>);
         Options.Prefix := US.To_Unbounded_String ("multipart-");
         Store.List_Multipart_Uploads
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Uploads.Length = 1
            and then Page.Uploads.First_Element.Initiated > 0,
            "SQLite multipart upload listing metadata failed");
      end;
      declare
         Page    : List_Page;
         Options : List_Options;

         procedure Put_Listing_Key (Object_Key : String) is
            Listing_Source : Buffer_Source :=
              (Data     => Flyology.Bytes.From_Byte_String ("x"),
               Position => 0,
               Length   => (Kind => Known, Bytes => 1));
         begin
            Store.Put_Object
              ("sqlite-bucket", Object_Key, Listing_Source,
               Default_Put_Options, null, Ada.Real_Time.Time_Last,
               Info, Result);
            Assert
              (Result = Success,
               "SQLite ListObjects v1/v2 key setup failed");
         end Put_Listing_Key;

         procedure Delete_Listing_Key (Object_Key : String) is
         begin
            Store.Delete_Object
              ("sqlite-bucket", Object_Key, null,
               Ada.Real_Time.Time_Last, Result);
            Assert
              (Result = Success,
               "SQLite ListObjects v1/v2 key cleanup failed");
         end Delete_Listing_Key;
      begin
         Options.Maximum := 1;
         Store.List_Objects
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Objects.Length = 1
            and then US.To_String (Page.Objects.First_Element.Key) = "empty"
            and then Page.Is_Truncated
            and then US.To_String (Page.Next_After) = "empty",
            "SQLite ListObjects v1/v2 first page failed");
         declare
            Cursor : constant US.Unbounded_String := Page.Next_After;
         begin
            Put_Listing_Key ("aardvark");
            Put_Listing_Key ("empty0");
            Options.After := Cursor;
            Store.List_Objects
              ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
               Page, Result);
            Assert
              (Result = Success and then Page.Objects.Length = 1
               and then US.To_String (Page.Objects.First_Element.Key) =
                 "empty0",
               "SQLite ListObjects v1/v2 mutation-safe continuation failed");
            Delete_Listing_Key ("aardvark");
            Delete_Listing_Key ("empty0");
            Options.After := Cursor;
         end;
         Store.List_Objects
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Objects.Length = 1
            and then US.To_String (Page.Objects.First_Element.Key) = Key
            and then not Page.Is_Truncated,
            "SQLite ListObjects v1/v2 continuation failed");
         Options := (others => <>);
         Options.Delimiter := US.To_Unbounded_String ("/");
         Store.List_Objects
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Objects.Length = 1
            and then Page.Common_Prefixes.Length = 1
            and then US.To_String (Page.Common_Prefixes.First_Element) =
              Character'Val (255) & "../",
            "SQLite ListObjects v1/v2 delimiter listing failed");
         Put_Listing_Key ("multi/a--x");
         Put_Listing_Key ("multi/a--y");
         Put_Listing_Key ("multi/b");
         Options := (others => <>);
         Options.Prefix := US.To_Unbounded_String ("multi/");
         Options.Delimiter := US.To_Unbounded_String ("--");
         Options.Maximum := 1;
         Store.List_Objects
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success
            and then Page.Objects.Is_Empty
            and then Page.Common_Prefixes.Length = 1
            and then US.To_String (Page.Common_Prefixes.First_Element) =
              "multi/a--"
            and then Page.Is_Truncated
            and then US.To_String (Page.Next_After) = "multi/a--",
            "SQLite ListObjects v1/v2 multi-delimiter projection failed");
         Options.After := Page.Next_After;
         Store.List_Objects
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Objects.Length = 1
            and then US.To_String (Page.Objects.First_Element.Key) =
              "multi/b"
            and then Page.Common_Prefixes.Is_Empty
            and then not Page.Is_Truncated,
            "SQLite ListObjects v1/v2 projected continuation failed");
         Delete_Listing_Key ("multi/a--x");
         Delete_Listing_Key ("multi/a--y");
         Delete_Listing_Key ("multi/b");
         declare
            Cancel : aliased Flyology.Cancellation.Token;
            Raised : Boolean := False;
         begin
            Cancel.Request;
            begin
               Store.List_Objects
                 ("sqlite-bucket", Options, Cancel'Access,
                  Ada.Real_Time.Time_Last, Page, Result);
            exception
               when Flyology.Cancellation.Operation_Cancelled =>
                  Raised := True;
            end;
            Assert (Raised, "SQLite listing ignored cancellation");
         end;
         declare
            Raised : Boolean := False;
         begin
            begin
               Store.List_Objects
                 ("sqlite-bucket", Options, null,
                  Ada.Real_Time.Time_First, Page, Result);
            exception
               when Flyology.IO.Timeout_Error =>
                  Raised := True;
            end;
            Assert (Raised, "SQLite listing ignored an expired deadline");
         end;
      end;
      Store.Delete_Bucket
        ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Bucket_Not_Empty,
              "SQLite backend deleted a nonempty bucket");
   end;

   declare
      Orphan : Ada.Streams.Stream_IO.File_Type;
   begin
      Ada.Streams.Stream_IO.Create
        (Orphan, Ada.Streams.Stream_IO.Out_File,
         Ada.Directories.Compose
           (Backend_Root & "/objects", (1 .. 64 => 'a') & ".blob"));
      Ada.Streams.Stream_IO.Close (Orphan);
      Ada.Streams.Stream_IO.Create
        (Orphan, Ada.Streams.Stream_IO.Out_File,
         Ada.Directories.Compose (Backend_Root & "/staging", "crash.part"));
      Ada.Streams.Stream_IO.Close (Orphan);
   end;

   declare
      package Backend renames Flyology.Object_Storage.Backends.SQLite;
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      Store : Backend.Store := Backend.Open (Backend_Root, 64);
      Info   : Object_Information;
      Result : Status;
      Sink   : Buffer_Sink;
      Key    : constant String := Character'Val (255) & "../../opaque/key";
      Wanted : Object_Tag_Set := Empty_Object_Tags;
      Tags   : Object_Tag_Set;
      Orphan_Path : constant String := Ada.Directories.Compose
        (Backend_Root & "/objects", (1 .. 64 => 'a') & ".blob");
   begin
      Assert (not Ada.Directories.Exists (Orphan_Path),
              "SQLite backend did not remove an orphan payload");
      Assert
        (not Ada.Directories.Exists
           (Ada.Directories.Compose
              (Backend_Root & "/staging", "crash.part")),
         "SQLite backend did not remove an incomplete staging file");
      declare
         Options : List_Buckets_Options;
         Page    : Bucket_Page;
      begin
         Store.List_Buckets
           (Options, null, Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success and then Page.Buckets.Length = 1
            and then Page.Buckets.First_Element.Created =
              SQLite_Bucket_Created,
            "SQLite bucket creation time did not survive reopen");
      end;
      declare
         Configuration : Bucket_Versioning_Configuration;
      begin
         Store.Get_Bucket_Versioning
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Configuration, Result);
         Assert
           (Result = Success
            and then Configuration.Status = Versioning_Enabled
            and then Configuration.MFA_Delete = MFA_Delete_Disabled,
            "SQLite backend versioning configuration did not survive reopen");
      end;
      Store.Head_Object
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Success and then Info.Size = 11 and then
         US.To_String (Info.Entity_Tag) = "etag-2",
         "SQLite backend metadata did not persist");
      declare
         Snapshot : Object_Attribute_Snapshot;
      begin
         Store.Get_Object_Attributes
           ("sqlite-bucket", Key, (others => <>), null,
            Ada.Real_Time.Time_Last, Snapshot, Result);
         Assert
           (Result = Success and then not Snapshot.Is_Multipart
            and then Snapshot.Total_Parts = 0
            and then Snapshot.Parts.Is_Empty
            and then Snapshot.Info.Size = 11,
            "ordinary SQLite object exposed multipart attributes");
      end;
      Exercise_Conditional_Read (Store, "sqlite-bucket", Key);
      Wanted.Length := 2;
      Wanted.Items (1) :=
        (Key => US.To_Unbounded_String ("environment"),
         Value => US.To_Unbounded_String ("production"));
      Wanted.Items (2) :=
        (Key => US.To_Unbounded_String ("team"),
         Value => US.To_Unbounded_String ("storage/core"));
      Store.Get_Object_Tags
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags = Wanted,
         "SQLite backend object tags did not persist across reopen");
      Store.Delete_Object_Tags
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Result);
      Store.Get_Object_Tags
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Tags, Result);
      Assert
        (Result = Success and then Tags.Length = 0,
         "SQLite backend tag deletion did not clear the complete set");
      declare
         Expected : Storage_Tags.Tag_Set;
         Observed : Storage_Tags.Tag_Set;
      begin
         Expected.Append (Tag_Item ("replacement", "complete"));
         Store.Get_Bucket_Tags
           ("sqlite-bucket", null, Ada.Real_Time.Time_Last,
            Observed, Result);
         Assert
           (Result = Success and then Observed = Expected,
            "SQLite backend bucket tags did not survive reopen");
      end;
      declare
         Page    : Multipart_Upload_Page;
         Options : List_Multipart_Uploads_Options;
      begin
         Store.List_Multipart_Uploads
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Uploads.Length = 2
            and then US.To_String (Page.Uploads (1).Key) = "aborted-target"
            and then US.To_String (Page.Uploads (2).Key) =
              "multipart-target",
            "SQLite multipart upload listing did not persist across reopen");
      end;
      declare
         Page : Multipart_Part_Page;
         Options : List_Multipart_Parts_Options :=
           (After => 0, Maximum => 1);
      begin
         Store.List_Multipart_Parts
           ("sqlite-bucket", "multipart-target",
            US.To_String (SQLite_Upload_ID), Options, null,
            Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success and then Page.Parts.Length = 1
            and then Page.Parts.First_Element.Number = 1
            and then Page.Parts.First_Element.Info.Size = 14
            and then Page.Is_Truncated and then Page.Next_After = 1,
            "SQLite persisted ListParts first page failed");
         Options.After := Page.Next_After;
         Store.List_Multipart_Parts
           ("sqlite-bucket", "multipart-target",
            US.To_String (SQLite_Upload_ID), Options, null,
            Ada.Real_Time.Time_Last, Page, Result);
         Assert
           (Result = Success and then Page.Parts.Length = 1
            and then Page.Parts.First_Element.Number = 3
            and then Page.Parts.First_Element.Info.Size = 5
            and then not Page.Is_Truncated,
            "SQLite persisted ListParts continuation failed");
      end;
      declare
         Options : Copy_Options := Default_Copy_Options;
         Copy_Sink : Buffer_Sink;
      begin
         Options.Conditions.If_Match :=
           US.To_Unbounded_String
             ('"' & US.To_String (Info.Entity_Tag) & '"');
         Store.Copy_Object
           ("sqlite-bucket", Key, "sqlite-bucket", "copied", Options,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success and then Info.Size = 11
            and then US.To_String (Info.Content_Type) = "text/plain",
            "SQLite copy did not preserve content metadata");
         Store.Get_Object
           ("sqlite-bucket", "copied", Whole_Object, Copy_Sink,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Copy_Sink.Data) =
              "second body",
            "SQLite copy body mismatch");
         Options.Conditions.If_Match := US.To_Unbounded_String ("wrong");
         Store.Copy_Object
           ("sqlite-bucket", Key, "sqlite-bucket", "copied", Options,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Precondition_Failed,
                 "SQLite copy accepted a failed source condition");
         Store.Copy_Object
           ("sqlite-bucket", "missing", "sqlite-bucket", "copied",
            Default_Copy_Options, null, Ada.Real_Time.Time_Last,
            Info, Result);
         Assert (Result = Source_Not_Found,
                 "SQLite copy source absence was ambiguous");
      end;
      declare
         Copy_ID : US.Unbounded_String;
         Copy_ETag : US.Unbounded_String;
         Completion : Multipart_Part_References;
         Copy_Sink : Buffer_Sink;
      begin
         Store.Create_Multipart_Upload
           ("sqlite-bucket", "copy-part-target",
            Default_Multipart_Options, null,
            Ada.Real_Time.Time_Last, Copy_ID, Result);
         Assert (Result = Success, "SQLite copy-part create failed");
         Store.Copy_Multipart_Part
           ("sqlite-bucket", Key, "sqlite-bucket", "copy-part-target",
            US.To_String (Copy_ID), 1,
            (Kind => Bounded_Range, First => 7, Last => 10, Count => 0),
            (others => <>), null, Ada.Real_Time.Time_Last, Info, Result);
         Copy_ETag := Info.Entity_Tag;
         Assert
           (Result = Success and then Info.Size = 4,
            "SQLite ranged copy-part failed");
         Store.Copy_Multipart_Part
           ("sqlite-bucket", "missing", "sqlite-bucket",
            "copy-part-target", US.To_String (Copy_ID), 2, Whole_Object,
            (others => <>), null, Ada.Real_Time.Time_Last, Info, Result);
         Assert (Result = Source_Not_Found,
                 "SQLite copy-part source absence was ambiguous");
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1, Entity_Tag => Copy_ETag));
         Store.Complete_Multipart_Upload
           ("sqlite-bucket", "copy-part-target", US.To_String (Copy_ID),
            Completion, null, Ada.Real_Time.Time_Last, Info, Result);
         Store.Get_Object
           ("sqlite-bucket", "copy-part-target", Whole_Object, Copy_Sink,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Copy_Sink.Data) = "body",
            "SQLite copied-part completion body mismatch");
         Store.Delete_Object
           ("sqlite-bucket", "copy-part-target", null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "SQLite copied-part cleanup failed");
      end;
      declare
         Completion : Multipart_Part_References;
         Multipart_Sink : Buffer_Sink;
      begin
         Completion.Append
           (Multipart_Part_Reference'
              (Number => 1, Entity_Tag => SQLite_Part_ETag));
         declare
            Options : Complete_Multipart_Options :=
              Default_Complete_Multipart_Options;
         begin
            Options.Expected_Size := (Kind => Known, Bytes => 15);
            Store.Complete_Multipart_Upload
              ("sqlite-bucket", "multipart-target",
               US.To_String (SQLite_Upload_ID), Completion, Options, null,
               Ada.Real_Time.Time_Last, Info, Result);
            Assert
              (Result = Invalid_Request,
               "SQLite wrong multipart object size consumed upload");
            Options.Expected_Size.Bytes := 14;
            Options.Conditions.If_None_Match :=
              US.To_Unbounded_String ("*");
            Store.Complete_Multipart_Upload
              ("sqlite-bucket", "multipart-target",
               US.To_String (SQLite_Upload_ID), Completion, Options, null,
               Ada.Real_Time.Time_Last, Info, Result);
         end;
         Assert
           (Result = Success
            and then Info.Size = 14
            and then US.To_String (Info.Content_Type) =
              "application/x-multipart-test",
            "SQLite multipart completion did not persist");
         declare
            Retained_Tags : Object_Tag_Set := Empty_Object_Tags;
         begin
            Retained_Tags.Length := 1;
            Retained_Tags.Items (1) :=
              (Key   => US.To_Unbounded_String ("generation"),
               Value => US.To_Unbounded_String ("multipart"));
            Store.Put_Object_Tags
              ("sqlite-bucket", "multipart-target", Retained_Tags, null,
               Ada.Real_Time.Time_Last, Result);
            Assert
              (Result = Success,
               "SQLite multipart object tag update failed");
         end;
         declare
            Snapshot : Object_Attribute_Snapshot;
         begin
            Store.Get_Object_Attributes
              ("sqlite-bucket", "multipart-target", (others => <>), null,
               Ada.Real_Time.Time_Last, Snapshot, Result);
            Assert
              (Result = Success and then Snapshot.Is_Multipart
               and then Snapshot.Total_Parts = 1
               and then Snapshot.Parts.Length = 1
               and then Snapshot.Parts.First_Element.Number = 1
               and then Snapshot.Parts.First_Element.Size = 14
               and then US.To_String (Snapshot.Info.Entity_Tag) =
                 US.To_String (Info.Entity_Tag),
               "SQLite completed object attributes mismatch");
         end;
         Store.Get_Object
           ("sqlite-bucket", "multipart-target", Whole_Object,
            Multipart_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String
              (Multipart_Sink.Data) = "multipart body",
            "SQLite multipart completion body changed");
         declare
            Page : Multipart_Upload_Page;
            Options : constant List_Multipart_Uploads_Options :=
              (Prefix => US.To_Unbounded_String ("aborted-target"),
               others => <>);
            Conditions : Abort_Multipart_Conditions;
         begin
            Store.List_Multipart_Uploads
              ("sqlite-bucket", Options, null,
               Ada.Real_Time.Time_Last, Page, Result);
            Assert
              (Result = Success and then Page.Uploads.Length = 1
               and then US.To_String (Page.Uploads.First_Element.Upload_ID) =
                 US.To_String (SQLite_Abort_ID),
               "SQLite abort initiation lookup failed");
            Conditions :=
              (Has_Initiated_Time => True,
               Initiated_Time => Page.Uploads.First_Element.Initiated + 1);
            Store.Abort_Multipart_Upload
              ("sqlite-bucket", "aborted-target",
               US.To_String (SQLite_Abort_ID), Conditions, null,
               Ada.Real_Time.Time_Last, Result);
            Assert
              (Result = Precondition_Failed,
               "SQLite failed abort condition retired upload");
            Conditions.Initiated_Time :=
              Page.Uploads.First_Element.Initiated;
            Store.Abort_Multipart_Upload
              ("sqlite-bucket", "aborted-target",
               US.To_String (SQLite_Abort_ID), Conditions, null,
               Ada.Real_Time.Time_Last, Result);
         end;
         Assert (Result = Success, "SQLite persisted multipart abort failed");
         Store.Abort_Multipart_Upload
           ("sqlite-bucket", "aborted-target",
            US.To_String (SQLite_Abort_ID),
            No_Abort_Multipart_Conditions, null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Not_Found, "SQLite missing upload was not reported");
      end;
      Store.Get_Object
        ("sqlite-bucket", Key,
         (Kind  => Bounded_Range,
          First => 7,
          Last  => 10,
          Count => 0), Sink,
         null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Success and then
         Flyology.Bytes.To_Byte_String (Sink.Data) = "body",
         "SQLite backend range read failed");
      Assert
        (Sink.Begin_Count = 1
         and then not Sink.Write_Before_Begin
         and then Sink.First = 7
         and then Sink.Content_Length = 4
         and then Sink.Partial
         and then Sink.Snapshot.Size = 11,
         "SQLite backend did not announce the resolved range first");
      declare
         Suffix_Sink : Buffer_Sink;
      begin
         Store.Get_Object
           ("sqlite-bucket", Key,
            (Kind  => Suffix_Range,
             First => 0,
             Last  => 0,
             Count => 4),
            Suffix_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String (Suffix_Sink.Data) = "body"
            and then Suffix_Sink.Begin_Count = 1
            and then Suffix_Sink.First = 7
            and then Suffix_Sink.Content_Length = 4
            and then Suffix_Sink.Partial,
            "SQLite backend did not resolve the suffix atomically");
      end;
      declare
         Empty_Sink : Buffer_Sink;
      begin
         Store.Get_Object
           ("sqlite-bucket", "empty", Whole_Object, Empty_Sink,
            null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Empty_Sink.Begin_Count = 1
            and then Empty_Sink.Content_Length = 0
            and then not Empty_Sink.Partial
            and then US.To_String (Empty_Sink.Snapshot.Entity_Tag) =
              "d41d8cd98f00b204e9800998ecf8427e"
            and then Flyology.Bytes.Length (Empty_Sink.Data) = 0,
            "SQLite backend did not announce an empty object");
      end;
      declare
         Bad_Sink : Raising_Sink;
         Propagated : Boolean := False;
      begin
         begin
            Store.Get_Object
              ("sqlite-bucket", Key, Whole_Object, Bad_Sink,
               null, Ada.Real_Time.Time_Last, Info, Result);
         exception
            when Program_Error =>
               Propagated := True;
         end;
         Assert (Propagated, "SQLite backend swallowed a sink exception");
      end;
      declare
         Entries  : Delete_Object_Entries;
         Outcomes : Delete_Object_Outcomes;
         Keys : constant array (Positive range 1 .. 5) of
           US.Unbounded_String :=
             (1 => US.To_Unbounded_String (Key),
              2 => US.To_Unbounded_String ("empty"),
              3 => US.To_Unbounded_String ("multipart-target"),
              4 => US.To_Unbounded_String ("copied"),
              5 => US.To_Unbounded_String ("already-missing"));
      begin
         for Object_Key of Keys loop
            Entries.Append
              (Delete_Object_Entry'
                 (Key        => Object_Key,
                  Conditions => No_Delete_Object_Conditions));
         end loop;
         Store.Delete_Objects
           ("sqlite-bucket", Entries, (Require_Unversioned => True), null,
            Ada.Real_Time.Time_Last, Outcomes, Result);
         Assert
           (Result = Not_Implemented and then Outcomes.Is_Empty,
            "SQLite DeleteObjects raced past versioning publication");
         Store.Head_Object
           ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last,
            Info, Result);
         Assert
           (Result = Success,
            "SQLite versioning race removed current object data");
         Store.Delete_Objects
           ("sqlite-bucket", Entries, (others => <>), null,
            Ada.Real_Time.Time_Last,
            Outcomes, Result);
         Assert
           (Result = Success and then Outcomes.Length = Entries.Length
            and then (for all Outcome of Outcomes =>
              Outcome.Result = Success),
            "SQLite backend DeleteObjects ordered batch failed");
      end;
   end;
   declare
      package Backend renames Flyology.Object_Storage.Backends.SQLite;
      use Flyology.Object_Storage;
      Key : constant String := Character'Val (255) & "../../opaque/key";
      Store : Backend.Store := Backend.Open (Backend_Root);
      Info  : Object_Information;
      Result : Status;
   begin
      Store.Head_Bucket
        ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert
        (Result = Success, "SQLite DeleteObjects bucket did not reopen");
      Store.Head_Object
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Not_Found,
         "SQLite DeleteObjects row survived crash-recovery reopen");
      Store.Delete_Bucket
        ("sqlite-bucket", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite backend bucket delete failed");
   end;
   Ada.Directories.Delete_Tree (Backend_Root);
   Ada.Text_IO.Put_Line ("SQLite wrapper, catalog, and backend: OK");
exception
   when Failure : others =>
      if Databases.Is_Open (Database) then
         Databases.Close (Database);
      end if;
      begin
         Catalogs.Close (Catalog);
      exception
         when others => null;
      end;
      Delete_Database;
      if Ada.Directories.Exists (Backend_Root) then
         Ada.Directories.Delete_Tree (Backend_Root);
      end if;
      if Ada.Directories.Exists (Conditional_Root) then
         Ada.Directories.Delete_Tree (Conditional_Root);
      end if;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "SQLite wrapper failure: " &
         Ada.Exceptions.Exception_Information (Failure));
      raise;
end Flyology_Object_Storage_Sqlite_Tests;
