with Ada.Containers;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.IO;
with Flyology.Object_Storage.SQLite;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with Flyology.Object_Storage.SQLite.Catalogs;
with Flyology.Object_Storage.SQLite.Databases;

procedure Flyology_Object_Storage_Sqlite_Tests is
   package Databases renames Flyology.Object_Storage.SQLite.Databases;
   package Catalogs renames Flyology.Object_Storage.SQLite.Catalogs;
   package US renames Ada.Strings.Unbounded;
   use type Databases.Step_Result;
   use type Ada.Containers.Count_Type;
   use type Ada.Streams.Stream_Element_Offset;
   use type Flyology.Object_Storage.Status;
   use type Flyology.Object_Storage.Object_Tag_Set;

   Expected_Source : constant String :=
     "2026-07-24 19:02:57 " &
     "bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc";

   Database_Path : constant String := "obj/database-wrapper.sqlite";
   Backend_Root : constant String := "obj/sqlite-backend";
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
            "multipart-final-payload", Info, Previous, Retired, Result);
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
      Catalogs.Delete_Object
        (Catalog, "catalog-bucket", Key, Payload, Result);
      Assert
        (Result = Flyology.Object_Storage.Success and then
         US.To_String (Payload) = "payload-two",
         "persisted catalog object was not deleted");
      Catalogs.Delete_Object
        (Catalog, "catalog-bucket", "multipart-key", Payload, Result);
      Assert
        (Result = Flyology.Object_Storage.Success
         and then US.To_String (Payload) = "multipart-final-payload",
         "persisted catalog multipart object was not deleted");
      Catalogs.Delete_Bucket (Catalog, "catalog-bucket", Result);
      Assert (Result = Flyology.Object_Storage.Success,
              "empty catalog bucket was not deleted");
      Catalogs.Delete_Bucket (Catalog, "catalog-bucket", Result);
      Assert (Result = Flyology.Object_Storage.Not_Found,
              "missing catalog bucket did not report not-found");
   end;
   Catalogs.Close (Catalog);
   Delete_Database;

   Create_V2_Database;
   Catalogs.Open (Catalog, Database_Path);
   declare
      use Flyology.Object_Storage;
      use Flyology.Object_Storage.Backends;
      Options : List_Buckets_Options;
      Page    : Bucket_Page;
      Result  : Status;

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
         and then Databases.Column (Version, 0) = 4,
         "schema-v2 migration did not publish version 4");
   end;
   declare
      Tags_Table : Databases.Statement;
   begin
      Databases.Prepare
        (Tags_Table, Database,
         "SELECT count(*) FROM sqlite_master WHERE type='table' " &
         "AND name='object_tags'");
      Assert
        (Databases.Step (Tags_Table) = Databases.Row
         and then Databases.Column (Tags_Table, 0) = 1,
         "schema-v2 migration did not create object_tags");
   end;
   Databases.Close (Database);
   Delete_Database;

   Create_V3_Database;
   Catalogs.Open (Catalog, Database_Path);
   Catalogs.Close (Catalog);
   Databases.Open (Database, Database_Path);
   declare
      Version : Databases.Statement;
      Tags_Table : Databases.Statement;
   begin
      Databases.Prepare (Version, Database, "PRAGMA user_version");
      Assert
        (Databases.Step (Version) = Databases.Row
         and then Databases.Column (Version, 0) = 4,
         "schema-v3 migration did not publish version 4");
      Databases.Prepare
        (Tags_Table, Database,
         "SELECT count(*) FROM sqlite_master WHERE type='table' " &
         "AND name='object_tags'");
      Assert
        (Databases.Step (Tags_Table) = Databases.Row
         and then Databases.Column (Tags_Table, 0) = 1,
         "schema-v3 migration did not create object_tags");
   end;
   Databases.Close (Database);
   Delete_Database;

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
            "SQLite backend listing first page failed");
         Options.After := Page.Next_After;
         Store.List_Objects
           ("sqlite-bucket", Options, null, Ada.Real_Time.Time_Last,
            Page, Result);
         Assert
           (Result = Success and then Page.Objects.Length = 1
            and then US.To_String (Page.Objects.First_Element.Key) = Key
            and then not Page.Is_Truncated,
            "SQLite backend listing continuation failed");
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
            "SQLite backend delimiter listing failed");
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
      Store.Head_Object
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Info, Result);
      Assert
        (Result = Success and then Info.Size = 11 and then
         US.To_String (Info.Entity_Tag) = "etag-2",
         "SQLite backend metadata did not persist");
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
         Store.Complete_Multipart_Upload
           ("sqlite-bucket", "multipart-target",
            US.To_String (SQLite_Upload_ID), Completion, null,
            Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Info.Size = 14
            and then US.To_String (Info.Content_Type) =
              "application/x-multipart-test",
            "SQLite multipart completion did not persist");
         Store.Get_Object
           ("sqlite-bucket", "multipart-target", Whole_Object,
            Multipart_Sink, null, Ada.Real_Time.Time_Last, Info, Result);
         Assert
           (Result = Success
            and then Flyology.Bytes.To_Byte_String
              (Multipart_Sink.Data) = "multipart body",
            "SQLite multipart completion body changed");
         Store.Abort_Multipart_Upload
           ("sqlite-bucket", "aborted-target",
            US.To_String (SQLite_Abort_ID), null,
            Ada.Real_Time.Time_Last, Result);
         Assert (Result = Success, "SQLite persisted multipart abort failed");
         Store.Abort_Multipart_Upload
           ("sqlite-bucket", "aborted-target",
            US.To_String (SQLite_Abort_ID), null,
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
      Store.Delete_Object
        ("sqlite-bucket", Key, null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite backend object delete failed");
      Store.Delete_Object
        ("sqlite-bucket", "empty", null, Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite backend empty delete failed");
      Store.Delete_Object
        ("sqlite-bucket", "multipart-target", null,
         Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite multipart object delete failed");
      Store.Delete_Object
        ("sqlite-bucket", "copied", null,
         Ada.Real_Time.Time_Last, Result);
      Assert (Result = Success, "SQLite copied object delete failed");
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
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "SQLite wrapper failure: " &
         Ada.Exceptions.Exception_Information (Failure));
      raise;
end Flyology_Object_Storage_Sqlite_Tests;
