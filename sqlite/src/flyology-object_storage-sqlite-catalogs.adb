with Ada.Containers;
with Flyology.Object_Storage.Backends.Listing;

package body Flyology.Object_Storage.SQLite.Catalogs is

   package DB renames Flyology.Object_Storage.SQLite.Databases;
   package US renames Ada.Strings.Unbounded;
   use type DB.Step_Result;

   Application_ID : constant Long_Long_Integer := 1_179_603_761;
   Schema_Version : constant Long_Long_Integer := 2;
   Empty_Info : constant Object_Information := (others => <>);

   protected body Operation_Gate is
      entry Acquire when not Held is
      begin
         Held := True;
      end Acquire;

      procedure Release is
      begin
         Held := False;
      end Release;
   end Operation_Gate;

   function Scalar (Item : in out Catalog; SQL : String)
      return Long_Long_Integer
   is
      Query : DB.Statement;
   begin
      DB.Prepare (Query, Item.Database, SQL);
      if DB.Step (Query) /= DB.Row then
         raise Catalog_Error with "SQLite scalar query returned no row";
      end if;
      return DB.Column (Query, 0);
   end Scalar;

   function Text_Scalar (Item : in out Catalog; SQL : String) return String is
      Query : DB.Statement;
   begin
      DB.Prepare (Query, Item.Database, SQL);
      if DB.Step (Query) /= DB.Row then
         raise Catalog_Error with "SQLite text query returned no row";
      end if;
      return DB.Column (Query, 0);
   end Text_Scalar;

   procedure Safe_Rollback (Item : in out Catalog) is
   begin
      DB.Rollback (Item.Database);
   exception
      when others => null;
   end Safe_Rollback;

   procedure Create_Schema (Item : in out Catalog) is
      In_Transaction : Boolean := False;
   begin
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      DB.Execute
        (Item.Database,
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
         "PRAGMA application_id=1179603761;" &
         "PRAGMA user_version=2;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Create_Schema;

   procedure Upgrade_From_V1 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
   begin
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      DB.Execute
        (Item.Database,
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
         "PRAGMA user_version=2;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V1;

   procedure Open (Item : in out Catalog; Path : String) is
      App_ID : Long_Long_Integer;
      Version : Long_Long_Integer;
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Open (Item.Database, Path);
      DB.Execute (Item.Database, "PRAGMA trusted_schema=OFF");
      DB.Execute (Item.Database, "PRAGMA foreign_keys=ON");
      if Scalar (Item, "PRAGMA foreign_keys") /= 1 then
         raise Catalog_Error with "SQLite foreign keys could not be enabled";
      end if;
      App_ID := Scalar (Item, "PRAGMA application_id");
      Version := Scalar (Item, "PRAGMA user_version");
      if App_ID = 0 and then Version = 0 then
         if Scalar
           (Item,
            "SELECT count(*) FROM sqlite_schema " &
            "WHERE name NOT LIKE 'sqlite_%'") /= 0
         then
            raise Catalog_Error with
              "refusing a nonempty unrecognized database";
         end if;
         Create_Schema (Item);
      elsif App_ID = Application_ID and then Version = 1 then
         Upgrade_From_V1 (Item);
      elsif App_ID /= Application_ID or else Version /= Schema_Version then
         raise Catalog_Error with "unsupported or unrelated SQLite database";
      end if;
      DB.Execute (Item.Database, "PRAGMA journal_mode=WAL");
      if Text_Scalar (Item, "PRAGMA journal_mode") /= "wal" then
         raise Catalog_Error with "SQLite WAL mode is unavailable";
      end if;
      DB.Execute (Item.Database, "PRAGMA synchronous=FULL");
      if Scalar (Item, "PRAGMA synchronous") /= 2 then
         raise Catalog_Error with "SQLite FULL synchronization is unavailable";
      elsif Scalar
        (Item,
         "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
         "AND name IN " &
         "('buckets','objects','multipart_uploads','multipart_parts')") /= 4
      then
         raise Catalog_Error with "SQLite catalog schema is incomplete";
      elsif Text_Scalar (Item, "PRAGMA quick_check(1)") /= "ok" then
         raise Catalog_Error with "SQLite catalog integrity check failed";
      end if;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if DB.Is_Open (Item.Database) then
            DB.Close (Item.Database);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Open;

   procedure Close (Item : in out Catalog) is
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Close (Item.Database);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Close;

   procedure Create_Bucket
     (Item : in out Catalog; Name : String; Result : out Status)
   is
      Insert : DB.Statement;
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Insert, Item.Database,
         "INSERT OR IGNORE INTO buckets(name) VALUES(?1)");
      DB.Bind (Insert, 1, Name);
      if DB.Step (Insert) /= DB.Done then
         raise Catalog_Error with "bucket insert returned a row";
      end if;
      Result := (if DB.Changes (Item.Database) = 1 then Success
                 else Already_Exists);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Create_Bucket;

   procedure Head_Bucket
     (Item : in out Catalog; Name : String; Result : out Status)
   is
      Query : DB.Statement;
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Query, 1, Name);
      if DB.Step (Query) /= DB.Row then
         raise Catalog_Error with "bucket existence query returned no row";
      end if;
      Result := (if DB.Column (Query, 0) = 0 then Not_Found else Success);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Head_Bucket;

   procedure Delete_Bucket
     (Item : in out Catalog; Name : String; Result : out Status)
   is
      Query : DB.Statement;
      Delete : DB.Statement;
      Locked : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1), " &
         "EXISTS(SELECT 1 FROM objects WHERE bucket_name=?1), " &
         "EXISTS(SELECT 1 FROM multipart_uploads WHERE bucket_name=?1)");
      DB.Bind (Query, 1, Name);
      if DB.Step (Query) /= DB.Row then
         raise Catalog_Error with "bucket query returned no row";
      elsif DB.Column (Query, 0) = 0 then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      elsif DB.Column (Query, 1) /= 0 or else DB.Column (Query, 2) /= 0 then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Result := Bucket_Not_Empty;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare (Delete, Item.Database, "DELETE FROM buckets WHERE name=?1");
      DB.Bind (Delete, 1, Name);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "bucket delete returned a row";
      end if;
      DB.Commit (Item.Database);
      In_Transaction := False;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Delete_Bucket;

   procedure Find_Object_Internal
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out US.Unbounded_String;
      Info    : out Object_Information;
      Result  : out Status)
   is
      Query : DB.Statement;
   begin
      Payload := US.Null_Unbounded_String;
      Info := Empty_Info;
      DB.Prepare
        (Query, Item.Database,
         "SELECT payload,size,modified,entity_tag,content_type " &
         "FROM objects WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Query, 1, Bucket);
      DB.Bind_Bytes (Query, 2, Key);
      if DB.Step (Query) = DB.Done then
         Result := Not_Found;
         return;
      end if;
      Payload := US.To_Unbounded_String (DB.Column (Query, 0));
      Info :=
        (Size         => Byte_Count'(DB.Column (Query, 1)),
         Modified     => Unix_Time'(DB.Column (Query, 2)),
         Entity_Tag   => US.To_Unbounded_String (DB.Column_Bytes (Query, 3)),
         Content_Type => US.To_Unbounded_String (DB.Column_Bytes (Query, 4)),
         Version      => US.Null_Unbounded_String);
      Result := Success;
   end Find_Object_Internal;

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out US.Unbounded_String;
      Info    : out Object_Information;
      Result  : out Status)
   is
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      Find_Object_Internal (Item, Bucket, Key, Payload, Info, Result);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Find_Object;

   procedure Put_Object
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out US.Unbounded_String;
      Result           : out Status)
   is
      In_Transaction : Boolean := False;
      Bucket_Query : DB.Statement;
      Existing : Object_Information;
      Upsert : DB.Statement;
      Locked : Boolean := False;
   begin
      Previous_Payload := US.Null_Unbounded_String;
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      DB.Prepare
        (Bucket_Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Bucket_Query, 1, Bucket);
      if DB.Step (Bucket_Query) /= DB.Row then
         raise Catalog_Error with "bucket existence query returned no row";
      elsif DB.Column (Bucket_Query, 0) = 0 then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      Find_Object_Internal
        (Item, Bucket, Key, Previous_Payload, Existing, Result);
      DB.Prepare
        (Upsert, Item.Database,
         "INSERT INTO objects(" &
         "bucket_name,object_key,payload,size,modified," &
         "entity_tag,content_type" &
         ") VALUES(?1,?2,?3,?4,?5,?6,?7) " &
         "ON CONFLICT(bucket_name,object_key) DO UPDATE SET " &
         "payload=excluded.payload,size=excluded.size," &
         "modified=excluded.modified,entity_tag=excluded.entity_tag," &
         "content_type=excluded.content_type");
      DB.Bind (Upsert, 1, Bucket);
      DB.Bind_Bytes (Upsert, 2, Key);
      DB.Bind (Upsert, 3, Payload);
      DB.Bind (Upsert, 4, Long_Long_Integer (Info.Size));
      DB.Bind (Upsert, 5, Long_Long_Integer (Info.Modified));
      DB.Bind_Bytes (Upsert, 6, US.To_String (Info.Entity_Tag));
      DB.Bind_Bytes (Upsert, 7, US.To_String (Info.Content_Type));
      if DB.Step (Upsert) /= DB.Done then
         raise Catalog_Error with "object upsert returned a row";
      end if;
      DB.Commit (Item.Database);
      In_Transaction := False;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Put_Object;

   procedure Delete_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out US.Unbounded_String;
      Result  : out Status)
   is
      Existing : Object_Information;
      Delete : DB.Statement;
      Locked : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      Find_Object_Internal (Item, Bucket, Key, Payload, Existing, Result);
      if Result /= Success then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM objects WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Delete, 1, Bucket);
      DB.Bind_Bytes (Delete, 2, Key);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "object delete returned a row";
      end if;
      DB.Commit (Item.Database);
      In_Transaction := False;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Delete_Object;

   procedure List_Objects
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Options;
      Check   : not null access procedure;
      Page    : out Backends.List_Page;
      Result  : out Status)
   is
      Bucket_Query : DB.Statement;
      Query        : DB.Statement;
      Builder      : Backends.Listing.Builder;
      Locked       : Boolean := False;
   begin
      Page := (others => <>);
      Item.Gate.Acquire;
      Locked := True;
      Check.all;
      DB.Prepare
        (Bucket_Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Bucket_Query, 1, Bucket);
      if DB.Step (Bucket_Query) /= DB.Row then
         raise Catalog_Error with "bucket existence query returned no row";
      elsif DB.Column (Bucket_Query, 0) = 0 then
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;

      Backends.Listing.Initialize (Builder, Options);
      DB.Prepare
        (Query, Item.Database,
         "SELECT object_key,size,modified,entity_tag,content_type " &
         "FROM objects WHERE bucket_name=?1 ORDER BY object_key");
      DB.Bind (Query, 1, Bucket);
      while DB.Step (Query) = DB.Row loop
         Check.all;
         Backends.Listing.Consider
           (Builder,
            DB.Column_Bytes (Query, 0),
            (Size         => Byte_Count'(DB.Column (Query, 1)),
             Modified     => Unix_Time'(DB.Column (Query, 2)),
             Entity_Tag   =>
               US.To_Unbounded_String (DB.Column_Bytes (Query, 3)),
             Content_Type =>
               US.To_Unbounded_String (DB.Column_Bytes (Query, 4)),
             Version      => US.Null_Unbounded_String));
      end loop;
      Page := Backends.Listing.Finish (Builder);
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end List_Objects;

   procedure Find_Multipart_Upload_Internal
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Content_Type : out US.Unbounded_String;
      Result       : out Status)
   is
      Query : DB.Statement;
   begin
      Content_Type := US.Null_Unbounded_String;
      DB.Prepare
        (Query, Item.Database,
         "SELECT content_type FROM multipart_uploads " &
         "WHERE upload_id=?1 AND bucket_name=?2 AND object_key=?3");
      DB.Bind (Query, 1, Upload_ID);
      DB.Bind (Query, 2, Bucket);
      DB.Bind_Bytes (Query, 3, Key);
      if DB.Step (Query) = DB.Done then
         Result := Not_Found;
      else
         Content_Type :=
           US.To_Unbounded_String (DB.Column_Bytes (Query, 0));
         Result := Success;
      end if;
   end Find_Multipart_Upload_Internal;

   procedure Create_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Content_Type : String;
      Created      : Unix_Time;
      Result       : out Status)
   is
      Bucket_Query : DB.Statement;
      Insert       : DB.Statement;
      Locked       : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Bucket_Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Bucket_Query, 1, Bucket);
      if DB.Step (Bucket_Query) /= DB.Row then
         raise Catalog_Error with "bucket existence query returned no row";
      elsif DB.Column (Bucket_Query, 0) = 0 then
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Insert, Item.Database,
         "INSERT INTO multipart_uploads(" &
         "upload_id,bucket_name,object_key,content_type,created" &
         ") VALUES(?1,?2,?3,?4,?5)");
      DB.Bind (Insert, 1, Upload_ID);
      DB.Bind (Insert, 2, Bucket);
      DB.Bind_Bytes (Insert, 3, Key);
      DB.Bind_Bytes (Insert, 4, Content_Type);
      DB.Bind (Insert, 5, Long_Long_Integer (Created));
      if DB.Step (Insert) /= DB.Done then
         raise Catalog_Error with "multipart upload insert returned a row";
      end if;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Create_Multipart_Upload;

   procedure Find_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Content_Type : out US.Unbounded_String;
      Result       : out Status)
   is
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Content_Type, Result);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Find_Multipart_Upload;

   procedure Put_Multipart_Part
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Part_Number      : Backends.Multipart_Part_Number;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out US.Unbounded_String;
      Result           : out Status)
   is
      Content_Type   : US.Unbounded_String;
      Existing       : DB.Statement;
      Upsert         : DB.Statement;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Previous_Payload := US.Null_Unbounded_String;
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Content_Type, Result);
      if Result /= Success then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Existing, Item.Database,
         "SELECT payload FROM multipart_parts " &
         "WHERE upload_id=?1 AND part_number=?2");
      DB.Bind (Existing, 1, Upload_ID);
      DB.Bind (Existing, 2, Long_Long_Integer (Part_Number));
      if DB.Step (Existing) = DB.Row then
         Previous_Payload :=
           US.To_Unbounded_String (DB.Column (Existing, 0));
      end if;
      DB.Prepare
        (Upsert, Item.Database,
         "INSERT INTO multipart_parts(" &
         "upload_id,part_number,payload,size,modified,entity_tag" &
         ") VALUES(?1,?2,?3,?4,?5,?6) " &
         "ON CONFLICT(upload_id,part_number) DO UPDATE SET " &
         "payload=excluded.payload,size=excluded.size," &
         "modified=excluded.modified,entity_tag=excluded.entity_tag");
      DB.Bind (Upsert, 1, Upload_ID);
      DB.Bind (Upsert, 2, Long_Long_Integer (Part_Number));
      DB.Bind (Upsert, 3, Payload);
      DB.Bind (Upsert, 4, Long_Long_Integer (Info.Size));
      DB.Bind (Upsert, 5, Long_Long_Integer (Info.Modified));
      DB.Bind_Bytes (Upsert, 6, US.To_String (Info.Entity_Tag));
      if DB.Step (Upsert) /= DB.Done then
         raise Catalog_Error with "multipart part upsert returned a row";
      end if;
      DB.Commit (Item.Database);
      In_Transaction := False;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Put_Multipart_Part;

   procedure Read_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Backends.Multipart_Part_References;
      Records   : out Multipart_Part_Records;
      Result    : out Status)
   is
      Content_Type : US.Unbounded_String;
      Locked       : Boolean := False;
   begin
      Records.Clear;
      Item.Gate.Acquire;
      Locked := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Content_Type, Result);
      if Result /= Success then
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      for Reference of Parts loop
         declare
            Query : DB.Statement;
         begin
            DB.Prepare
              (Query, Item.Database,
               "SELECT payload,size,modified,entity_tag " &
               "FROM multipart_parts " &
               "WHERE upload_id=?1 AND part_number=?2");
            DB.Bind (Query, 1, Upload_ID);
            DB.Bind (Query, 2, Long_Long_Integer (Reference.Number));
            if DB.Step (Query) = DB.Done
              or else DB.Column_Bytes (Query, 3) /=
                US.To_String (Reference.Entity_Tag)
            then
               Records.Clear;
               Result := Invalid_Part;
               Item.Gate.Release;
               Locked := False;
               return;
            end if;
            Records.Append
              ((Number  => Reference.Number,
                Payload => US.To_Unbounded_String (DB.Column (Query, 0)),
                Info    =>
                  (Size         => Byte_Count'(DB.Column (Query, 1)),
                   Modified     => Unix_Time'(DB.Column (Query, 2)),
                   Entity_Tag   =>
                     US.To_Unbounded_String (DB.Column_Bytes (Query, 3)),
                   Content_Type => US.Null_Unbounded_String,
                   Version      => US.Null_Unbounded_String)));
         end;
      end loop;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Read_Multipart_Parts;

   procedure Collect_Multipart_Payloads
     (Item      : in out Catalog;
      Upload_ID : String;
      Values    : out Payloads)
   is
      Query : DB.Statement;
   begin
      Values.Clear;
      DB.Prepare
        (Query, Item.Database,
         "SELECT payload FROM multipart_parts WHERE upload_id=?1 " &
         "ORDER BY part_number");
      DB.Bind (Query, 1, Upload_ID);
      while DB.Step (Query) = DB.Row loop
         Values.Append (US.To_Unbounded_String (DB.Column (Query, 0)));
      end loop;
   end Collect_Multipart_Payloads;

   procedure Complete_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Selected         : Multipart_Part_Records;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out US.Unbounded_String;
      Retired_Payloads : out Payloads;
      Result           : out Status)
   is
      Content_Type   : US.Unbounded_String;
      Upsert         : DB.Statement;
      Delete         : DB.Statement;
      Existing       : Object_Information;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Previous_Payload := US.Null_Unbounded_String;
      Retired_Payloads.Clear;
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Content_Type, Result);
      if Result /= Success or else Selected.Is_Empty then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         if Result = Success then
            Result := Invalid_Request;
         end if;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      for Record_Value of Selected loop
         declare
            Query : DB.Statement;
         begin
            DB.Prepare
              (Query, Item.Database,
               "SELECT payload,size,modified,entity_tag " &
               "FROM multipart_parts " &
               "WHERE upload_id=?1 AND part_number=?2");
            DB.Bind (Query, 1, Upload_ID);
            DB.Bind (Query, 2, Long_Long_Integer (Record_Value.Number));
            if DB.Step (Query) = DB.Done
              or else DB.Column (Query, 0) /=
                US.To_String (Record_Value.Payload)
              or else DB.Column (Query, 1) /=
                Long_Long_Integer (Record_Value.Info.Size)
              or else DB.Column (Query, 2) /=
                Long_Long_Integer (Record_Value.Info.Modified)
              or else DB.Column_Bytes (Query, 3) /=
                US.To_String (Record_Value.Info.Entity_Tag)
            then
               DB.Rollback (Item.Database);
               In_Transaction := False;
               Result := Conflict;
               Item.Gate.Release;
               Locked := False;
               return;
            end if;
         end;
      end loop;
      Collect_Multipart_Payloads (Item, Upload_ID, Retired_Payloads);
      Find_Object_Internal
        (Item, Bucket, Key, Previous_Payload, Existing, Result);
      DB.Prepare
        (Upsert, Item.Database,
         "INSERT INTO objects(" &
         "bucket_name,object_key,payload,size,modified," &
         "entity_tag,content_type" &
         ") VALUES(?1,?2,?3,?4,?5,?6,?7) " &
         "ON CONFLICT(bucket_name,object_key) DO UPDATE SET " &
         "payload=excluded.payload,size=excluded.size," &
         "modified=excluded.modified,entity_tag=excluded.entity_tag," &
         "content_type=excluded.content_type");
      DB.Bind (Upsert, 1, Bucket);
      DB.Bind_Bytes (Upsert, 2, Key);
      DB.Bind (Upsert, 3, Payload);
      DB.Bind (Upsert, 4, Long_Long_Integer (Info.Size));
      DB.Bind (Upsert, 5, Long_Long_Integer (Info.Modified));
      DB.Bind_Bytes (Upsert, 6, US.To_String (Info.Entity_Tag));
      DB.Bind_Bytes (Upsert, 7, US.To_String (Info.Content_Type));
      if DB.Step (Upsert) /= DB.Done then
         raise Catalog_Error with "multipart object upsert returned a row";
      end if;
      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM multipart_uploads WHERE upload_id=?1");
      DB.Bind (Delete, 1, Upload_ID);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "multipart upload delete returned a row";
      end if;
      DB.Commit (Item.Database);
      In_Transaction := False;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Complete_Multipart_Upload;

   procedure Abort_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Retired_Payloads : out Payloads;
      Result           : out Status)
   is
      Content_Type   : US.Unbounded_String;
      Delete         : DB.Statement;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Retired_Payloads.Clear;
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Content_Type, Result);
      if Result /= Success then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      Collect_Multipart_Payloads (Item, Upload_ID, Retired_Payloads);
      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM multipart_uploads WHERE upload_id=?1");
      DB.Bind (Delete, 1, Upload_ID);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "multipart abort delete returned a row";
      end if;
      DB.Commit (Item.Database);
      In_Transaction := False;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Abort_Multipart_Upload;

   function Payload_Referenced
     (Item : in out Catalog; Payload : String) return Boolean
   is
      Query  : DB.Statement;
      Result : Boolean;
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM objects WHERE payload=?1), " &
         "EXISTS(SELECT 1 FROM multipart_parts WHERE payload=?1)");
      DB.Bind (Query, 1, Payload);
      if DB.Step (Query) /= DB.Row then
         raise Catalog_Error with "payload reference query returned no row";
      end if;
      Result := DB.Column (Query, 0) /= 0 or else DB.Column (Query, 1) /= 0;
      Item.Gate.Release;
      Locked := False;
      return Result;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Payload_Referenced;

end Flyology.Object_Storage.SQLite.Catalogs;
