with Ada.Containers;
with Flyology.Object_Storage.Backends.Listing;
with Flyology.Object_Storage.Backends.Multipart_Listing;
with Flyology.Object_Storage.Checksum_Engine;

package body Flyology.Object_Storage.SQLite.Catalogs is

   package DB renames Flyology.Object_Storage.SQLite.Databases;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type DB.Step_Result;

   Application_ID : constant Long_Long_Integer := 1_179_603_761;
   Schema_Version : constant Long_Long_Integer := 8;
   Empty_Info : constant Object_Information := (others => <>);
   Object_Tags_Schema : constant String :=
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
     ") WITHOUT ROWID;";
   Object_Parts_Schema : constant String :=
     "CREATE TABLE object_parts (" &
     "bucket_name TEXT NOT NULL COLLATE BINARY," &
     "object_key BLOB NOT NULL," &
     "part_number INTEGER NOT NULL " &
     "CHECK(part_number BETWEEN 1 AND 10000)," &
     "size INTEGER NOT NULL CHECK(size >= 0)," &
     "PRIMARY KEY(bucket_name,object_key,part_number)," &
     "FOREIGN KEY(bucket_name,object_key) " &
     "REFERENCES objects(bucket_name,object_key) ON DELETE CASCADE" &
     ") WITHOUT ROWID;";
   Object_Parts_Schema_V8 : constant String :=
     "CREATE TABLE object_parts (" &
     "bucket_name TEXT NOT NULL COLLATE BINARY," &
     "object_key BLOB NOT NULL," &
     "part_number INTEGER NOT NULL " &
     "CHECK(part_number BETWEEN 1 AND 10000)," &
     "size INTEGER NOT NULL CHECK(size >= 0)," &
     "checksum_algorithm INTEGER NOT NULL DEFAULT 0 " &
     "CHECK(checksum_algorithm BETWEEN 0 AND 10)," &
     "checksum_method INTEGER NOT NULL DEFAULT 0 " &
     "CHECK(checksum_method BETWEEN 0 AND 2)," &
     "checksum_value BLOB NOT NULL DEFAULT X'' " &
     "CHECK(length(checksum_value) <= 96)," &
     "PRIMARY KEY(bucket_name,object_key,part_number)," &
     "FOREIGN KEY(bucket_name,object_key) " &
     "REFERENCES objects(bucket_name,object_key) ON DELETE CASCADE" &
     ") WITHOUT ROWID;";
   Bucket_Tags_Schema : constant String :=
     "CREATE TABLE bucket_tags (" &
     "bucket_name TEXT NOT NULL COLLATE BINARY," &
     "ordinal INTEGER NOT NULL CHECK(ordinal BETWEEN 1 AND 50)," &
     "tag_key BLOB NOT NULL CHECK(length(tag_key) BETWEEN 1 AND 512)," &
     "tag_value BLOB NOT NULL CHECK(length(tag_value) <= 1024)," &
     "PRIMARY KEY(bucket_name,tag_key)," &
     "UNIQUE(bucket_name,ordinal)," &
     "FOREIGN KEY(bucket_name) REFERENCES buckets(name) ON DELETE CASCADE" &
     ") WITHOUT ROWID;";
   Versioning_Columns_Schema : constant String :=
     "ALTER TABLE buckets ADD COLUMN versioning_status INTEGER NOT NULL " &
     "DEFAULT 0 CHECK(versioning_status BETWEEN 0 AND 2);" &
     "ALTER TABLE buckets ADD COLUMN mfa_delete_status INTEGER NOT NULL " &
     "DEFAULT 0 CHECK(mfa_delete_status BETWEEN 0 AND 2);";
   Checksum_Columns_Schema : constant String :=
     "ALTER TABLE objects ADD COLUMN checksum_algorithm INTEGER NOT NULL " &
     "DEFAULT 0 CHECK(checksum_algorithm BETWEEN 0 AND 10);" &
     "ALTER TABLE objects ADD COLUMN checksum_method INTEGER NOT NULL " &
     "DEFAULT 0 CHECK(checksum_method BETWEEN 0 AND 2);" &
     "ALTER TABLE objects ADD COLUMN checksum_value BLOB NOT NULL " &
     "DEFAULT X'' CHECK(length(checksum_value) <= 96);" &
     "ALTER TABLE multipart_uploads ADD COLUMN checksum_algorithm INTEGER " &
     "NOT NULL DEFAULT 0 CHECK(checksum_algorithm BETWEEN 0 AND 10);" &
     "ALTER TABLE multipart_uploads ADD COLUMN checksum_method INTEGER " &
     "NOT NULL DEFAULT 0 CHECK(checksum_method BETWEEN 0 AND 2);" &
     "ALTER TABLE multipart_parts ADD COLUMN checksum_algorithm INTEGER " &
     "NOT NULL DEFAULT 0 CHECK(checksum_algorithm BETWEEN 0 AND 10);" &
     "ALTER TABLE multipart_parts ADD COLUMN checksum_method INTEGER " &
     "NOT NULL DEFAULT 0 CHECK(checksum_method BETWEEN 0 AND 2);" &
     "ALTER TABLE multipart_parts ADD COLUMN checksum_value BLOB NOT NULL " &
     "DEFAULT X'' CHECK(length(checksum_value) <= 96);" &
     "ALTER TABLE object_parts ADD COLUMN checksum_algorithm INTEGER " &
     "NOT NULL DEFAULT 0 CHECK(checksum_algorithm BETWEEN 0 AND 10);" &
     "ALTER TABLE object_parts ADD COLUMN checksum_method INTEGER NOT NULL " &
     "DEFAULT 0 CHECK(checksum_method BETWEEN 0 AND 2);" &
     "ALTER TABLE object_parts ADD COLUMN checksum_value BLOB NOT NULL " &
     "DEFAULT X'' CHECK(length(checksum_value) <= 96);";

   function Checksum_From_Columns
     (Query        : DB.Statement;
      First_Column : Natural;
      Has_Value    : Boolean := True;
      Is_Object    : Boolean := False;
      Part_Count   : Natural := 0) return Checksum_Information
   is
      Algorithm : constant Long_Long_Integer :=
        DB.Column (Query, First_Column);
      Method : constant Long_Long_Integer :=
        DB.Column (Query, First_Column + 1);
      Result : Checksum_Information;
   begin
      if Algorithm not in 0 .. 10 or else Method not in 0 .. 2 then
         raise Catalog_Error with "invalid checksum catalog value";
      end if;
      Result.Algorithm := Checksum_Algorithm'Val (Natural (Algorithm));
      Result.Method := Checksum_Method'Val (Natural (Method));
      if Has_Value then
         Result.Value :=
           US.To_Unbounded_String (DB.Column_Bytes (Query, First_Column + 2));
      end if;
      if (Result.Algorithm = No_Checksum) /=
           (Result.Method = No_Checksum_Method)
        or else
          (Result.Algorithm = No_Checksum
           and then US.Length (Result.Value) /= 0)
      then
         raise Catalog_Error with "inconsistent checksum catalog value";
      elsif not Has_Value
        and then not Checksum_Engine.Valid_Configuration (Result)
      then
         raise Catalog_Error with "invalid checksum catalog configuration";
      elsif Has_Value and then Result.Algorithm /= No_Checksum
        and then not Is_Object
        and then not Checksum_Engine.Valid_Digest
          (US.To_String (Result.Value), Result.Algorithm)
      then
         raise Catalog_Error with "invalid part checksum catalog value";
      elsif Has_Value and then Result.Algorithm /= No_Checksum
        and then Is_Object
        and then Result.Method = Composite_Checksum
        and then Part_Count = 0
      then
         raise Catalog_Error with "checksum object has no completed parts";
      elsif Has_Value and then Result.Algorithm /= No_Checksum
        and then Is_Object
        and then not Checksum_Engine.Valid_Object_Digest
          (US.To_String (Result.Value), Result.Algorithm, Result.Method,
           Positive'Max (1, Part_Count))
      then
         raise Catalog_Error with "invalid object checksum catalog value";
      end if;
      return Result;
   end Checksum_From_Columns;

   procedure Bind_Checksum
     (Query        : in out DB.Statement;
      First_Index  : Positive;
      Value        : Checksum_Information;
      Include_Value : Boolean := True) is
   begin
      DB.Bind
        (Query, First_Index,
         Long_Long_Integer (Checksum_Algorithm'Pos (Value.Algorithm)));
      DB.Bind
        (Query, First_Index + 1,
         Long_Long_Integer (Checksum_Method'Pos (Value.Method)));
      if Include_Value then
         DB.Bind_Bytes (Query, First_Index + 2, US.To_String (Value.Value));
      end if;
   end Bind_Checksum;

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

   function Valid_Checksum_Columns
     (Item      : in out Catalog;
      Table_Name : String;
      Has_Value : Boolean) return Boolean
   is
      Expected : constant Long_Long_Integer := (if Has_Value then 3 else 2);
      Prefix : constant String :=
        "SELECT count(*) FROM pragma_table_info('" & Table_Name & "') ";
   begin
      return Scalar (Item, Prefix & "WHERE name LIKE 'checksum_%'") = Expected
        and then Scalar
          (Item, Prefix & "WHERE name='checksum_algorithm'") = 1
        and then Scalar
          (Item, Prefix & "WHERE name='checksum_method'") = 1
        and then
          (if Has_Value
           then Scalar (Item, Prefix & "WHERE name='checksum_value'") = 1
           else Scalar (Item, Prefix & "WHERE name='checksum_value'") = 0);
   end Valid_Checksum_Columns;

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
         "name TEXT PRIMARY KEY COLLATE BINARY NOT NULL," &
         "created INTEGER NOT NULL CHECK(created >= 0)," &
         "versioning_status INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(versioning_status BETWEEN 0 AND 2)," &
         "mfa_delete_status INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(mfa_delete_status BETWEEN 0 AND 2)" &
         ") WITHOUT ROWID;" &
         "CREATE TABLE objects (" &
         "bucket_name TEXT NOT NULL COLLATE BINARY," &
         "object_key BLOB NOT NULL," &
         "payload TEXT NOT NULL UNIQUE," &
         "size INTEGER NOT NULL CHECK(size >= 0)," &
         "modified INTEGER NOT NULL CHECK(modified >= 0)," &
         "entity_tag BLOB NOT NULL," &
         "content_type BLOB NOT NULL," &
         "checksum_algorithm INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(checksum_algorithm BETWEEN 0 AND 10)," &
         "checksum_method INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(checksum_method BETWEEN 0 AND 2)," &
         "checksum_value BLOB NOT NULL DEFAULT X'' " &
         "CHECK(length(checksum_value) <= 96)," &
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
         "checksum_algorithm INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(checksum_algorithm BETWEEN 0 AND 10)," &
         "checksum_method INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(checksum_method BETWEEN 0 AND 2)," &
         "FOREIGN KEY(bucket_name) REFERENCES buckets(name) " &
         "ON DELETE RESTRICT" &
         ") WITHOUT ROWID;" &
         Object_Tags_Schema &
         "CREATE TABLE multipart_parts (" &
         "upload_id TEXT NOT NULL COLLATE BINARY," &
         "part_number INTEGER NOT NULL " &
         "CHECK(part_number BETWEEN 1 AND 10000)," &
         "payload TEXT NOT NULL UNIQUE," &
         "size INTEGER NOT NULL CHECK(size >= 0)," &
         "modified INTEGER NOT NULL CHECK(modified >= 0)," &
         "entity_tag BLOB NOT NULL," &
         "checksum_algorithm INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(checksum_algorithm BETWEEN 0 AND 10)," &
         "checksum_method INTEGER NOT NULL DEFAULT 0 " &
         "CHECK(checksum_method BETWEEN 0 AND 2)," &
         "checksum_value BLOB NOT NULL DEFAULT X'' " &
         "CHECK(length(checksum_value) <= 96)," &
         "PRIMARY KEY(upload_id,part_number)," &
         "FOREIGN KEY(upload_id) REFERENCES multipart_uploads(upload_id) " &
         "ON DELETE CASCADE" &
         ") WITHOUT ROWID;" &
         Object_Parts_Schema_V8 &
         Bucket_Tags_Schema &
         "PRAGMA application_id=1179603761;" &
         "PRAGMA user_version=8;");
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
         "ALTER TABLE buckets ADD COLUMN created INTEGER NOT NULL " &
         "DEFAULT 0 CHECK(created >= 0);" &
         Object_Tags_Schema &
         Object_Parts_Schema &
         Bucket_Tags_Schema &
         Versioning_Columns_Schema &
         "PRAGMA user_version=7;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V1;

   procedure Upgrade_From_V2 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
   begin
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      DB.Execute
        (Item.Database,
         "ALTER TABLE buckets ADD COLUMN created INTEGER NOT NULL " &
         "DEFAULT 0 CHECK(created >= 0);" &
         Object_Tags_Schema &
         Object_Parts_Schema &
         Bucket_Tags_Schema &
         Versioning_Columns_Schema &
         "PRAGMA user_version=7;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V2;

   procedure Upgrade_From_V3 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
   begin
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      DB.Execute
        (Item.Database,
         Object_Tags_Schema & Object_Parts_Schema & Bucket_Tags_Schema &
         Versioning_Columns_Schema & "PRAGMA user_version=7;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V3;

   procedure Upgrade_From_V4 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
      Object_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name='object_tags'");
      Bucket_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name='bucket_tags'");
      Parts_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name='object_parts'");
      Versioning_Columns : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM pragma_table_info('buckets') " &
           "WHERE name IN ('versioning_status','mfa_delete_status')");
   begin
      if Object_Tables not in 0 .. 1
        or else Bucket_Tables not in 0 .. 1
        or else Parts_Tables /= 0
        or else Versioning_Columns not in 0 | 2
        or else
          (Object_Tables + Bucket_Tables = 0 and then Versioning_Columns = 0)
      then
         raise Catalog_Error with "unsupported SQLite schema version 4";
      end if;
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      if Object_Tables = 0 then
         DB.Execute (Item.Database, Object_Tags_Schema);
      end if;
      if Bucket_Tables = 0 then
         DB.Execute (Item.Database, Bucket_Tags_Schema);
      end if;
      if Versioning_Columns = 0 then
         DB.Execute (Item.Database, Versioning_Columns_Schema);
      end if;
      DB.Execute
        (Item.Database, Object_Parts_Schema & "PRAGMA user_version=7;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V4;

   procedure Upgrade_From_V5 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
      Object_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name='object_tags'");
      Bucket_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name='bucket_tags'");
      Parts_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name='object_parts'");
      Versioning_Columns : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM pragma_table_info('buckets') " &
           "WHERE name IN ('versioning_status','mfa_delete_status')");
   begin
      if Object_Tables /= 1
        or else Bucket_Tables not in 0 .. 1
        or else Parts_Tables not in 0 .. 1
        or else Bucket_Tables + Parts_Tables = 0
        or else Versioning_Columns not in 0 | 2
      then
         raise Catalog_Error with "unsupported SQLite schema version 5";
      end if;
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      if Bucket_Tables = 0 then
         DB.Execute (Item.Database, Bucket_Tags_Schema);
      end if;
      if Parts_Tables = 0 then
         DB.Execute (Item.Database, Object_Parts_Schema);
      end if;
      if Versioning_Columns = 0 then
         DB.Execute (Item.Database, Versioning_Columns_Schema);
      end if;
      DB.Execute (Item.Database, "PRAGMA user_version=7;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V5;

   procedure Upgrade_From_V6 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
      Existing_Tables : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM sqlite_schema WHERE type='table' " &
           "AND name IN ('object_tags','object_parts','bucket_tags')");
      Versioning_Columns : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT count(*) FROM pragma_table_info('buckets') " &
           "WHERE name IN ('versioning_status','mfa_delete_status')");
   begin
      if Existing_Tables /= 3 or else Versioning_Columns /= 0 then
         raise Catalog_Error with "unsupported SQLite schema version 6";
      end if;
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      DB.Execute
        (Item.Database,
         Versioning_Columns_Schema & "PRAGMA user_version=7;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V6;

   procedure Upgrade_From_V7 (Item : in out Catalog) is
      In_Transaction : Boolean := False;
      Existing_Columns : constant Long_Long_Integer :=
        Scalar
          (Item,
           "SELECT " &
           "(SELECT count(*) FROM pragma_table_info('objects') " &
           " WHERE name LIKE 'checksum_%') + " &
           "(SELECT count(*) FROM pragma_table_info('multipart_uploads') " &
           " WHERE name LIKE 'checksum_%') + " &
           "(SELECT count(*) FROM pragma_table_info('multipart_parts') " &
           " WHERE name LIKE 'checksum_%') + " &
           "(SELECT count(*) FROM pragma_table_info('object_parts') " &
           " WHERE name LIKE 'checksum_%')");
   begin
      if Existing_Columns /= 0 then
         raise Catalog_Error with "unsupported SQLite schema version 7";
      end if;
      DB.Begin_Transaction (Item.Database, DB.Exclusive);
      In_Transaction := True;
      DB.Execute
        (Item.Database,
         Checksum_Columns_Schema & "PRAGMA user_version=8;");
      DB.Commit (Item.Database);
      In_Transaction := False;
   exception
      when others =>
         if In_Transaction then
            Safe_Rollback (Item);
         end if;
         raise;
   end Upgrade_From_V7;

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
         Version := Schema_Version;
      elsif App_ID /= Application_ID then
         raise Catalog_Error with "unsupported or unrelated SQLite database";
      else
         case Version is
            when 1 => Upgrade_From_V1 (Item); Version := 7;
            when 2 => Upgrade_From_V2 (Item); Version := 7;
            when 3 => Upgrade_From_V3 (Item); Version := 7;
            when 4 => Upgrade_From_V4 (Item); Version := 7;
            when 5 => Upgrade_From_V5 (Item); Version := 7;
            when 6 => Upgrade_From_V6 (Item); Version := 7;
            when 7 => null;
            when 8 => null;
            when others =>
               raise Catalog_Error with
                 "unsupported or unrelated SQLite database";
         end case;
         if Version = 7 then
            Upgrade_From_V7 (Item);
            Version := 8;
         end if;
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
         "('buckets','objects','object_tags','multipart_uploads'," &
         "'multipart_parts','object_parts','bucket_tags')") /= 7
      then
         raise Catalog_Error with "SQLite catalog schema is incomplete";
      elsif not Valid_Checksum_Columns (Item, "objects", True)
        or else not Valid_Checksum_Columns
          (Item, "multipart_uploads", False)
        or else not Valid_Checksum_Columns (Item, "multipart_parts", True)
        or else not Valid_Checksum_Columns (Item, "object_parts", True)
      then
         raise Catalog_Error with "SQLite checksum schema is incomplete";
      elsif Scalar
        (Item,
         "SELECT count(*) FROM pragma_table_info('buckets') " &
         "WHERE name IN ('versioning_status','mfa_delete_status')") /= 2
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
     (Item    : in out Catalog;
      Name    : String;
      Created : Unix_Time;
      Result  : out Status)
   is
      Insert : DB.Statement;
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Insert, Item.Database,
         "INSERT OR IGNORE INTO buckets(name,created) VALUES(?1,?2)");
      DB.Bind (Insert, 1, Name);
      DB.Bind (Insert, 2, Long_Long_Integer (Created));
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

   procedure List_Buckets
     (Item    : in out Catalog;
      Options : Backends.List_Buckets_Options;
      Check   : not null access procedure;
      Page    : out Backends.Bucket_Page;
      Result  : out Status)
   is
      Query  : DB.Statement;
      Locked : Boolean := False;
   begin
      Page := (others => <>);
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT name,created FROM buckets " &
         "WHERE name > ?1 AND substr(name,1,length(?2)) = ?2 " &
         "ORDER BY name COLLATE BINARY LIMIT ?3");
      DB.Bind (Query, 1, US.To_String (Options.After));
      DB.Bind (Query, 2, US.To_String (Options.Prefix));
      DB.Bind
        (Query, 3, Long_Long_Integer (Options.Maximum) + 1);
      while DB.Step (Query) = DB.Row loop
         Check.all;
         if Page.Buckets.Length <
           Ada.Containers.Count_Type (Options.Maximum)
         then
            Page.Buckets.Append
              (Backends.Listed_Bucket'
                 (Name    => US.To_Unbounded_String (DB.Column (Query, 0)),
                  Created => Unix_Time'(DB.Column (Query, 1))));
         else
            Page.Is_Truncated := True;
            Page.Next_After := Page.Buckets.Last_Element.Name;
            exit;
         end if;
      end loop;
      Item.Gate.Release;
      Locked := False;
      Result := Success;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end List_Buckets;

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

   procedure Put_Bucket_Versioning
     (Item          : in out Catalog;
      Name          : String;
      Configuration : Bucket_Versioning_Configuration;
      Result        : out Status;
      MFA_Validated : Boolean := False)
   is
      Query  : DB.Statement;
      Update : DB.Statement;
      Locked : Boolean := False;
      Step   : DB.Step_Result;
      Current_MFA : Long_Long_Integer := 0;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT mfa_delete_status FROM buckets WHERE name=?1");
      DB.Bind (Query, 1, Name);
      Step := DB.Step (Query);
      if Step /= DB.Row then
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      Current_MFA := DB.Column (Query, 0);
      if Current_MFA not in 0 .. 2 then
         raise Catalog_Error with
           "bucket MFA-delete catalog value is invalid";
      elsif not MFA_Validated
        and then
          (Current_MFA =
             Long_Long_Integer (MFA_Delete_Status'Pos (MFA_Delete_Enabled))
           or else Configuration.MFA_Delete /= MFA_Delete_Unconfigured)
      then
         Result := Access_Denied;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Update, Item.Database,
         "UPDATE buckets SET " &
         "versioning_status=CASE WHEN ?2=0 THEN versioning_status " &
         "ELSE ?2 END," &
         "mfa_delete_status=CASE WHEN ?3=0 THEN mfa_delete_status " &
         "ELSE ?3 END " &
         "WHERE name=?1");
      DB.Bind (Update, 1, Name);
      DB.Bind
        (Update, 2,
         Long_Long_Integer
           (Bucket_Versioning_Status'Pos (Configuration.Status)));
      DB.Bind
        (Update, 3,
         Long_Long_Integer
           (MFA_Delete_Status'Pos (Configuration.MFA_Delete)));
      if DB.Step (Update) /= DB.Done then
         raise Catalog_Error with
           "bucket versioning update returned a row";
      end if;
      Result :=
        (if DB.Changes (Item.Database) = 1 then Success else Not_Found);
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Put_Bucket_Versioning;

   procedure Get_Bucket_Versioning
     (Item          : in out Catalog;
      Name          : String;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status)
   is
      Query  : DB.Statement;
      Locked : Boolean := False;
      Step   : DB.Step_Result;
      Raw_Status     : Long_Long_Integer;
      Raw_MFA_Delete : Long_Long_Integer;
   begin
      Configuration := (others => <>);
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT versioning_status,mfa_delete_status " &
         "FROM buckets WHERE name=?1");
      DB.Bind (Query, 1, Name);
      Step := DB.Step (Query);
      if Step = DB.Row then
         Raw_Status := DB.Column (Query, 0);
         Raw_MFA_Delete := DB.Column (Query, 1);
         if Raw_Status not in 0 .. 2 or else Raw_MFA_Delete not in 0 .. 2 then
            raise Catalog_Error with
              "bucket versioning catalog value is invalid";
         end if;
         Configuration :=
           (Status =>
              Bucket_Versioning_Status'Val
                (Natural (Raw_Status)),
            MFA_Delete =>
              MFA_Delete_Status'Val
                (Natural (Raw_MFA_Delete)));
         Result := Success;
      else
         Result := Not_Found;
      end if;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Get_Bucket_Versioning;

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

   procedure Put_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Tags.Tag_Set;
      Result : out Status)
   is
      Query          : DB.Statement;
      Delete         : DB.Statement;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
      Ordinal        : Positive := 1;
   begin
      if not Tags.Valid_Bucket_Tag_Set (Value) then
         Result := Invalid_Request;
         return;
      end if;
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      DB.Prepare
        (Query, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Query, 1, Bucket);
      if DB.Step (Query) /= DB.Row then
         raise Catalog_Error with "bucket tag existence query returned no row";
      elsif DB.Column (Query, 0) = 0 then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM bucket_tags WHERE bucket_name=?1");
      DB.Bind (Delete, 1, Bucket);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "bucket tag delete returned a row";
      end if;
      for Tag of Value loop
         declare
            Insert : DB.Statement;
         begin
            DB.Prepare
              (Insert, Item.Database,
               "INSERT INTO bucket_tags" &
               "(bucket_name,ordinal,tag_key,tag_value) " &
               "VALUES(?1,?2,?3,?4)");
            DB.Bind (Insert, 1, Bucket);
            DB.Bind (Insert, 2, Long_Long_Integer (Ordinal));
            DB.Bind_Bytes (Insert, 3, US.To_String (Tag.Key));
            DB.Bind_Bytes (Insert, 4, US.To_String (Tag.Value));
            if DB.Step (Insert) /= DB.Done then
               raise Catalog_Error with "bucket tag insert returned a row";
            end if;
            Ordinal := Ordinal + 1;
         end;
      end loop;
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
   end Put_Bucket_Tags;

   procedure Delete_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status)
   is
      Exists         : DB.Statement;
      Delete         : DB.Statement;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      DB.Prepare
        (Exists, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Exists, 1, Bucket);
      if DB.Step (Exists) /= DB.Row then
         raise Catalog_Error with
           "bucket tag deletion existence query returned no row";
      elsif DB.Column (Exists, 0) = 0 then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM bucket_tags WHERE bucket_name=?1");
      DB.Bind (Delete, 1, Bucket);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "bucket tag deletion returned a row";
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
   end Delete_Bucket_Tags;

   procedure Get_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Tags.Tag_Set;
      Result : out Status)
   is
      Exists : DB.Statement;
      Query  : DB.Statement;
      Locked : Boolean := False;
   begin
      Value.Clear;
      Item.Gate.Acquire;
      Locked := True;
      DB.Prepare
        (Exists, Item.Database,
         "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
      DB.Bind (Exists, 1, Bucket);
      if DB.Step (Exists) /= DB.Row then
         raise Catalog_Error with "bucket tag existence query returned no row";
      elsif DB.Column (Exists, 0) = 0 then
         Result := Not_Found;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Query, Item.Database,
         "SELECT tag_key,tag_value FROM bucket_tags " &
         "WHERE bucket_name=?1 ORDER BY ordinal");
      DB.Bind (Query, 1, Bucket);
      while DB.Step (Query) = DB.Row loop
         if Value.Length =
           Ada.Containers.Count_Type (Tags.Maximum_Bucket_Tags)
         then
            raise Catalog_Error with "bucket tag row limit exceeded";
         end if;
         Value.Append
           (Tags.Tag'
              (Key   => US.To_Unbounded_String (DB.Column_Bytes (Query, 0)),
               Value => US.To_Unbounded_String
                 (DB.Column_Bytes (Query, 1))));
      end loop;
      if Value.Is_Empty then
         Result := Tag_Set_Not_Found;
      elsif not Tags.Valid_Bucket_Tag_Set (Value) then
         raise Catalog_Error with "invalid bucket tag catalog data";
      else
         Result := Success;
      end if;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         Value.Clear;
         raise;
   end Get_Bucket_Tags;

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
         "SELECT payload,size,modified,entity_tag,content_type," &
         "checksum_algorithm,checksum_method,checksum_value," &
         "(SELECT count(*) FROM object_parts WHERE bucket_name=objects." &
         "bucket_name AND object_key=objects.object_key) " &
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
         Version      => US.Null_Unbounded_String,
         Checksum     => Checksum_From_Columns
           (Query, 5, Is_Object => True,
            Part_Count =>
              Natural (Long_Long_Integer'(DB.Column (Query, 8)))));
      Result := Success;
   end Find_Object_Internal;

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out US.Unbounded_String;
      Info    : out Object_Information;
      Result  : out Status;
      Check   : access procedure
        (Payload : String; Info : Object_Information) := null)
   is
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      Find_Object_Internal (Item, Bucket, Key, Payload, Info, Result);
      if Result = Success and then Check /= null then
         Check.all (US.To_String (Payload), Info);
      end if;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Find_Object;

   procedure Get_Object_Attributes
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Options  : Backends.Object_Attribute_Options;
      Conditions : Backends.Read_Conditions;
      Check    : not null access procedure;
      Snapshot : out Backends.Object_Attribute_Snapshot;
      Result   : out Status)
   is
      Payload : US.Unbounded_String;
      Count_Query : DB.Statement;
      Parts_Query : DB.Statement;
      Locked : Boolean := False;
   begin
      Snapshot := (others => <>);
      Item.Gate.Acquire;
      Locked := True;
      Check.all;
      Find_Object_Internal
        (Item, Bucket, Key, Payload, Snapshot.Info, Result);
      if Result /= Success then
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      Result := Backends.Evaluate_Read_Conditions
        (Conditions, US.To_String (Snapshot.Info.Entity_Tag),
         Snapshot.Info.Modified);
      if Result /= Success then
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Count_Query, Item.Database,
         "SELECT count(*) FROM object_parts " &
         "WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Count_Query, 1, Bucket);
      DB.Bind_Bytes (Count_Query, 2, Key);
      if DB.Step (Count_Query) /= DB.Row
        or else Long_Long_Integer'(DB.Column (Count_Query, 0))
          not in 0 .. 10_000
      then
         raise Catalog_Error with "invalid completed object part count";
      end if;
      Snapshot.Total_Parts :=
        Natural (Long_Long_Integer'(DB.Column (Count_Query, 0)));
      Snapshot.Is_Multipart := Snapshot.Total_Parts > 0;
      if Options.Maximum > 0 and then Snapshot.Is_Multipart then
         DB.Prepare
           (Parts_Query, Item.Database,
            "SELECT part_number,size,checksum_algorithm,checksum_method," &
            "checksum_value FROM object_parts " &
            "WHERE bucket_name=?1 AND object_key=?2 " &
            "AND part_number>?3 ORDER BY part_number LIMIT ?4");
         DB.Bind (Parts_Query, 1, Bucket);
         DB.Bind_Bytes (Parts_Query, 2, Key);
         DB.Bind
           (Parts_Query, 3, Long_Long_Integer (Options.After));
         DB.Bind
           (Parts_Query, 4,
            Long_Long_Integer (Options.Maximum) + 1);
         while DB.Step (Parts_Query) = DB.Row loop
            Check.all;
            if Snapshot.Parts.Length <
              Ada.Containers.Count_Type (Options.Maximum)
            then
               Snapshot.Parts.Append
                 (Backends.Completed_Object_Part'
                    (Number => Backends.Multipart_Part_Number
                       (Long_Long_Integer'
                          (DB.Column (Parts_Query, 0))),
                     Size => Byte_Count
                       (Long_Long_Integer'
                          (DB.Column (Parts_Query, 1))),
                     Checksum => Checksum_From_Columns (Parts_Query, 2)));
            else
               Snapshot.Is_Truncated := True;
               Snapshot.Next_After :=
                 Backends.Multipart_Part_Marker
                   (Snapshot.Parts.Last_Element.Number);
               exit;
            end if;
         end loop;
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
   end Get_Object_Attributes;

   procedure Put_Object
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out US.Unbounded_String;
      Result           : out Status;
      Conditions       : Write_Conditions := Default_Write_Conditions)
   is
      In_Transaction : Boolean := False;
      Bucket_Query : DB.Statement;
      Existing : Object_Information;
      Upsert : DB.Statement;
      Clear_Tags : DB.Statement;
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
      if Result not in Success | Not_Found then
         raise Catalog_Error with "object lookup returned unexpected status";
      end if;
      declare
         Exists : constant Boolean := Result = Success;
         Current_Entity_Tag : constant String :=
           (if Exists then US.To_String (Existing.Entity_Tag) else "");
      begin
         Result := Backends.Evaluate_Write_Conditions
           (Conditions,
            Exists     => Exists,
            Entity_Tag => Current_Entity_Tag);
      end;
      if Result /= Success then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Upsert, Item.Database,
         "INSERT INTO objects(" &
         "bucket_name,object_key,payload,size,modified," &
         "entity_tag,content_type,checksum_algorithm,checksum_method," &
         "checksum_value" &
         ") VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10) " &
         "ON CONFLICT(bucket_name,object_key) DO UPDATE SET " &
         "payload=excluded.payload,size=excluded.size," &
         "modified=excluded.modified,entity_tag=excluded.entity_tag," &
         "content_type=excluded.content_type," &
         "checksum_algorithm=excluded.checksum_algorithm," &
         "checksum_method=excluded.checksum_method," &
         "checksum_value=excluded.checksum_value");
      DB.Bind (Upsert, 1, Bucket);
      DB.Bind_Bytes (Upsert, 2, Key);
      DB.Bind (Upsert, 3, Payload);
      DB.Bind (Upsert, 4, Long_Long_Integer (Info.Size));
      DB.Bind (Upsert, 5, Long_Long_Integer (Info.Modified));
      DB.Bind_Bytes (Upsert, 6, US.To_String (Info.Entity_Tag));
      DB.Bind_Bytes (Upsert, 7, US.To_String (Info.Content_Type));
      Bind_Checksum (Upsert, 8, Info.Checksum);
      if DB.Step (Upsert) /= DB.Done then
         raise Catalog_Error with "object upsert returned a row";
      end if;
      DB.Prepare
        (Clear_Tags, Item.Database,
         "DELETE FROM object_tags WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Clear_Tags, 1, Bucket);
      DB.Bind_Bytes (Clear_Tags, 2, Key);
      if DB.Step (Clear_Tags) /= DB.Done then
         raise Catalog_Error with "object tag reset returned a row";
      end if;
      declare
         Delete_Parts : DB.Statement;
      begin
         DB.Prepare
           (Delete_Parts, Item.Database,
            "DELETE FROM object_parts " &
            "WHERE bucket_name=?1 AND object_key=?2");
         DB.Bind (Delete_Parts, 1, Bucket);
         DB.Bind_Bytes (Delete_Parts, 2, Key);
         if DB.Step (Delete_Parts) /= DB.Done then
            raise Catalog_Error with "object part delete returned a row";
         end if;
      end;
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

   procedure Delete_Objects
     (Item     : in out Catalog;
      Bucket   : String;
      Entries  : Backends.Delete_Object_Entries;
      Requirements : Backends.Delete_Objects_Requirements;
      Retired  : out Payloads;
      Outcomes : out Backends.Delete_Object_Outcomes;
      Result   : out Status)
   is
      Bucket_Query   : DB.Statement;
      Delete         : DB.Statement;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Retired.Clear;
      Outcomes.Clear;
      if Entries.Is_Empty
        or else Entries.Length > Backends.Maximum_Delete_Objects
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
      Retired.Reserve_Capacity (Entries.Length);
      Outcomes.Reserve_Capacity (Entries.Length);

      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      DB.Prepare
        (Bucket_Query, Item.Database,
         "SELECT versioning_status,mfa_delete_status " &
         "FROM buckets WHERE name=?1");
      DB.Bind (Bucket_Query, 1, Bucket);
      declare
         Step : constant DB.Step_Result := DB.Step (Bucket_Query);
      begin
         if Step = DB.Done then
            DB.Rollback (Item.Database);
            In_Transaction := False;
            Result := Bucket_Not_Found;
            Item.Gate.Release;
            Locked := False;
            return;
         elsif Requirements.Require_Unversioned
           and then
             (DB.Column (Bucket_Query, 0) /= 0
              or else DB.Column (Bucket_Query, 1) = 1)
         then
            DB.Rollback (Item.Database);
            In_Transaction := False;
            Result := Not_Implemented;
            Item.Gate.Release;
            Locked := False;
            return;
         end if;
      end;

      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM objects WHERE bucket_name=?1 AND object_key=?2");
      for Request_Entry of Entries loop
         declare
            Payload      : US.Unbounded_String;
            Existing     : Object_Information := (others => <>);
            Lookup       : Status;
            Entry_Result : Status;
            Key          : constant String := US.To_String (Request_Entry.Key);
         begin
            Find_Object_Internal
              (Item, Bucket, Key, Payload, Existing, Lookup);
            Entry_Result :=
              Backends.Evaluate_Delete_Object_Conditions
                (Request_Entry.Conditions, Lookup = Success, Existing);
            Outcomes.Append
              (Backends.Delete_Object_Outcome'(Result => Entry_Result));
            if Entry_Result = Success and then Lookup = Success then
               Retired.Append (Payload);
               DB.Bind (Delete, 1, Bucket);
               DB.Bind_Bytes (Delete, 2, Key);
               if DB.Step (Delete) /= DB.Done then
                  raise Catalog_Error with
                    "object batch delete returned a row";
               elsif DB.Changes (Item.Database) /= 1 then
                  raise Catalog_Error with
                    "object batch delete changed an unexpected row count";
               end if;
               DB.Reset (Delete);
            end if;
         end;
      end loop;
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
         Retired.Clear;
         Outcomes.Clear;
         raise;
   end Delete_Objects;

   procedure Put_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : Object_Tag_Set; Result : out Status)
   is
      Existing       : Object_Information;
      Payload        : US.Unbounded_String;
      Delete         : DB.Statement;
      Insert         : DB.Statement;
      Locked         : Boolean := False;
      In_Transaction : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      DB.Begin_Transaction (Item.Database);
      In_Transaction := True;
      Find_Object_Internal (Item, Bucket, Key, Payload, Existing, Result);
      if Result /= Success then
         declare
            Bucket_Query : DB.Statement;
         begin
            DB.Prepare
              (Bucket_Query, Item.Database,
               "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
            DB.Bind (Bucket_Query, 1, Bucket);
            if DB.Step (Bucket_Query) /= DB.Row then
               raise Catalog_Error with
                 "bucket existence query returned no row";
            elsif DB.Column (Bucket_Query, 0) = 0 then
               Result := Bucket_Not_Found;
            end if;
         end;
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Delete, Item.Database,
         "DELETE FROM object_tags WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Delete, 1, Bucket);
      DB.Bind_Bytes (Delete, 2, Key);
      if DB.Step (Delete) /= DB.Done then
         raise Catalog_Error with "object tag delete returned a row";
      end if;
      DB.Prepare
        (Insert, Item.Database,
         "INSERT INTO object_tags(" &
         "bucket_name,object_key,tag_index,tag_key,tag_value" &
         ") VALUES(?1,?2,?3,?4,?5)");
      for Index in 1 .. Tags.Length loop
         if Index > 1 then
            DB.Reset (Insert);
         end if;
         DB.Bind (Insert, 1, Bucket);
         DB.Bind_Bytes (Insert, 2, Key);
         DB.Bind (Insert, 3, Long_Long_Integer (Index));
         DB.Bind_Bytes (Insert, 4, US.To_String (Tags.Items (Index).Key));
         DB.Bind_Bytes (Insert, 5, US.To_String (Tags.Items (Index).Value));
         if DB.Step (Insert) /= DB.Done then
            raise Catalog_Error with "object tag insert returned a row";
         end if;
      end loop;
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
   end Put_Object_Tags;

   procedure Get_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : out Object_Tag_Set; Result : out Status)
   is
      Existing : Object_Information;
      Payload  : US.Unbounded_String;
      Query    : DB.Statement;
      Locked   : Boolean := False;
   begin
      Tags := Empty_Object_Tags;
      Item.Gate.Acquire;
      Locked := True;
      Find_Object_Internal (Item, Bucket, Key, Payload, Existing, Result);
      if Result /= Success then
         declare
            Bucket_Query : DB.Statement;
         begin
            DB.Prepare
              (Bucket_Query, Item.Database,
               "SELECT EXISTS(SELECT 1 FROM buckets WHERE name=?1)");
            DB.Bind (Bucket_Query, 1, Bucket);
            if DB.Step (Bucket_Query) /= DB.Row then
               raise Catalog_Error with
                 "bucket existence query returned no row";
            elsif DB.Column (Bucket_Query, 0) = 0 then
               Result := Bucket_Not_Found;
            end if;
         end;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Query, Item.Database,
         "SELECT tag_index,tag_key,tag_value FROM object_tags " &
         "WHERE bucket_name=?1 AND object_key=?2 ORDER BY tag_index");
      DB.Bind (Query, 1, Bucket);
      DB.Bind_Bytes (Query, 2, Key);
      while DB.Step (Query) = DB.Row loop
         if Tags.Length = Maximum_Object_Tags
           or else DB.Column (Query, 0) /= Long_Long_Integer (Tags.Length + 1)
         then
            raise Catalog_Error with "invalid object tag ordering";
         end if;
         Tags.Length := Tags.Length + 1;
         Tags.Items (Tags.Length) :=
           (Key   => US.To_Unbounded_String (DB.Column_Bytes (Query, 1)),
            Value => US.To_Unbounded_String (DB.Column_Bytes (Query, 2)));
      end loop;
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         Tags := Empty_Object_Tags;
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end Get_Object_Tags;

   procedure Delete_Object_Tags
     (Item : in out Catalog; Bucket, Key : String; Result : out Status)
   is
      Tags : constant Object_Tag_Set := Empty_Object_Tags;
   begin
      Put_Object_Tags (Item, Bucket, Key, Tags, Result);
   end Delete_Object_Tags;

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
         "SELECT object_key,size,modified,entity_tag,content_type," &
         "checksum_algorithm,checksum_method,checksum_value," &
         "(SELECT count(*) FROM object_parts WHERE bucket_name=objects." &
         "bucket_name AND object_key=objects.object_key) " &
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
             Version      => US.Null_Unbounded_String,
             Checksum     => Checksum_From_Columns
               (Query, 5, Is_Object => True,
                Part_Count =>
                  Natural (Long_Long_Integer'(DB.Column (Query, 8))))));
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
      Options      : out Backends.Multipart_Options;
      Result       : out Status)
   is
      Query : DB.Statement;
   begin
      Options := Backends.Default_Multipart_Options;
      DB.Prepare
        (Query, Item.Database,
         "SELECT content_type,checksum_algorithm,checksum_method " &
         "FROM multipart_uploads " &
         "WHERE upload_id=?1 AND bucket_name=?2 AND object_key=?3");
      DB.Bind (Query, 1, Upload_ID);
      DB.Bind (Query, 2, Bucket);
      DB.Bind_Bytes (Query, 3, Key);
      if DB.Step (Query) = DB.Done then
         Result := Not_Found;
      else
         Options.Content_Type :=
           US.To_Unbounded_String (DB.Column_Bytes (Query, 0));
         Options.Checksum := Checksum_From_Columns (Query, 1, False);
         Result := Success;
      end if;
   end Find_Multipart_Upload_Internal;

   procedure Create_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Options      : Backends.Multipart_Options;
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
         "upload_id,bucket_name,object_key,content_type,created," &
         "checksum_algorithm,checksum_method" &
         ") VALUES(?1,?2,?3,?4,?5,?6,?7)");
      DB.Bind (Insert, 1, Upload_ID);
      DB.Bind (Insert, 2, Bucket);
      DB.Bind_Bytes (Insert, 3, Key);
      DB.Bind_Bytes (Insert, 4, US.To_String (Options.Content_Type));
      DB.Bind (Insert, 5, Long_Long_Integer (Created));
      Bind_Checksum (Insert, 6, Options.Checksum, False);
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
      Options      : out Backends.Multipart_Options;
      Result       : out Status)
   is
      Locked : Boolean := False;
   begin
      Item.Gate.Acquire;
      Locked := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Options, Result);
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
      Upload_Options : Backends.Multipart_Options;
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
        (Item, Bucket, Key, Upload_ID, Upload_Options, Result);
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
         "upload_id,part_number,payload,size,modified,entity_tag," &
         "checksum_algorithm,checksum_method,checksum_value" &
         ") VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9) " &
         "ON CONFLICT(upload_id,part_number) DO UPDATE SET " &
         "payload=excluded.payload,size=excluded.size," &
         "modified=excluded.modified,entity_tag=excluded.entity_tag," &
         "checksum_algorithm=excluded.checksum_algorithm," &
         "checksum_method=excluded.checksum_method," &
         "checksum_value=excluded.checksum_value");
      DB.Bind (Upsert, 1, Upload_ID);
      DB.Bind (Upsert, 2, Long_Long_Integer (Part_Number));
      DB.Bind (Upsert, 3, Payload);
      DB.Bind (Upsert, 4, Long_Long_Integer (Info.Size));
      DB.Bind (Upsert, 5, Long_Long_Integer (Info.Modified));
      DB.Bind_Bytes (Upsert, 6, US.To_String (Info.Entity_Tag));
      Bind_Checksum (Upsert, 7, Info.Checksum);
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

   procedure List_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : Backends.List_Multipart_Parts_Options;
      Page      : out Backends.Multipart_Part_Page;
      Result    : out Status)
   is
      Upload_Options : Backends.Multipart_Options;
      Query        : DB.Statement;
      Locked       : Boolean := False;
   begin
      Page := (others => <>);
      Item.Gate.Acquire;
      Locked := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Upload_Options, Result);
      if Result /= Success then
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      Page.Checksum := Upload_Options.Checksum;
      if Options.Maximum = 0
        or else Options.After = Backends.Multipart_Part_Marker'Last
      then
         Item.Gate.Release;
         Locked := False;
         Result := Success;
         return;
      end if;
      DB.Prepare
        (Query, Item.Database,
         "SELECT part_number,size,modified,entity_tag," &
         "checksum_algorithm,checksum_method,checksum_value " &
         "FROM multipart_parts WHERE upload_id=?1 AND part_number>?2 " &
         "ORDER BY part_number LIMIT ?3");
      DB.Bind (Query, 1, Upload_ID);
      DB.Bind (Query, 2, Long_Long_Integer (Options.After));
      DB.Bind (Query, 3, Long_Long_Integer (Options.Maximum) + 1);
      while DB.Step (Query) = DB.Row loop
         declare
            Number_Value : constant Long_Long_Integer := DB.Column (Query, 0);
         begin
            if Page.Parts.Length <
              Ada.Containers.Count_Type (Options.Maximum)
            then
               Page.Parts.Append
                 (Backends.Listed_Multipart_Part'
                    (Number =>
                       Backends.Multipart_Part_Number (Number_Value),
                     Info =>
                       (Size => Byte_Count'(DB.Column (Query, 1)),
                        Modified => Unix_Time'(DB.Column (Query, 2)),
                        Entity_Tag =>
                          US.To_Unbounded_String
                            (DB.Column_Bytes (Query, 3)),
                        Content_Type => US.Null_Unbounded_String,
                        Version => US.Null_Unbounded_String,
                        Checksum => Checksum_From_Columns (Query, 4))));
            else
               Page.Is_Truncated := True;
               Page.Next_After := Backends.Multipart_Part_Marker
                 (Page.Parts.Last_Element.Number);
               exit;
            end if;
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
         Page := (others => <>);
         raise;
   end List_Multipart_Parts;

   procedure List_Multipart_Uploads
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Multipart_Uploads_Options;
      Check   : not null access procedure;
      Page    : out Backends.Multipart_Upload_Page;
      Result  : out Status)
   is
      Bucket_Query : DB.Statement;
      Query        : DB.Statement;
      Builder      : Backends.Multipart_Listing.Builder;
      Locked       : Boolean := False;
   begin
      Page := (others => <>);
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
      Backends.Multipart_Listing.Initialize (Builder, Options);
      DB.Prepare
        (Query, Item.Database,
         "SELECT object_key,upload_id,created,content_type," &
         "checksum_algorithm,checksum_method " &
         "FROM multipart_uploads WHERE bucket_name=?1");
      DB.Bind (Query, 1, Bucket);
      loop
         Check.all;
         case DB.Step (Query) is
            when DB.Done =>
               exit;
            when DB.Row =>
               Backends.Multipart_Listing.Consider
                 (Builder,
                  DB.Column_Bytes (Query, 0),
                  DB.Column (Query, 1),
                  Unix_Time
                    (Long_Long_Integer'(DB.Column (Query, 2))),
                  Backends.Multipart_Options'
                     (Content_Type => US.To_Unbounded_String
                       (DB.Column_Bytes (Query, 3)),
                     Checksum => Checksum_From_Columns (Query, 4, False)));
         end case;
      end loop;
      Page := Backends.Multipart_Listing.Finish (Builder);
      Result := Success;
      Item.Gate.Release;
      Locked := False;
   exception
      when others =>
         if Locked then
            Item.Gate.Release;
         end if;
         raise;
   end List_Multipart_Uploads;

   procedure Read_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Backends.Multipart_Part_References;
      Records   : out Multipart_Part_Records;
      Result    : out Status)
   is
      Upload_Options : Backends.Multipart_Options;
      Locked       : Boolean := False;
   begin
      Records.Clear;
      Item.Gate.Acquire;
      Locked := True;
      Find_Multipart_Upload_Internal
        (Item, Bucket, Key, Upload_ID, Upload_Options, Result);
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
               "SELECT payload,size,modified,entity_tag," &
               "checksum_algorithm,checksum_method,checksum_value " &
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
                   Version      => US.Null_Unbounded_String,
                   Checksum     => Checksum_From_Columns (Query, 4))));
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
      Conditions       : Backends.Copy_Conditions;
      Previous_Payload : out US.Unbounded_String;
      Retired_Payloads : out Payloads;
      Result           : out Status)
   is
      Upload_Options : Backends.Multipart_Options;
      Upsert         : DB.Statement;
      Clear_Tags     : DB.Statement;
      Delete         : DB.Statement;
      Existing       : Object_Information;
      Existing_Found : Boolean;
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
        (Item, Bucket, Key, Upload_ID, Upload_Options, Result);
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
               "SELECT payload,size,modified,entity_tag," &
               "checksum_algorithm,checksum_method,checksum_value " &
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
              or else Checksum_From_Columns (Query, 4) /=
                Record_Value.Info.Checksum
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
      Existing_Found := Result = Success;
      if Result not in Success | Not_Found then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      Result := Backends.Evaluate_Write_Conditions
        (Conditions, Existing_Found,
         US.To_String (Existing.Entity_Tag));
      if Result /= Success then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      DB.Prepare
        (Upsert, Item.Database,
         "INSERT INTO objects(" &
         "bucket_name,object_key,payload,size,modified," &
         "entity_tag,content_type,checksum_algorithm,checksum_method," &
         "checksum_value" &
         ") VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10) " &
         "ON CONFLICT(bucket_name,object_key) DO UPDATE SET " &
         "payload=excluded.payload,size=excluded.size," &
         "modified=excluded.modified,entity_tag=excluded.entity_tag," &
         "content_type=excluded.content_type," &
         "checksum_algorithm=excluded.checksum_algorithm," &
         "checksum_method=excluded.checksum_method," &
         "checksum_value=excluded.checksum_value");
      DB.Bind (Upsert, 1, Bucket);
      DB.Bind_Bytes (Upsert, 2, Key);
      DB.Bind (Upsert, 3, Payload);
      DB.Bind (Upsert, 4, Long_Long_Integer (Info.Size));
      DB.Bind (Upsert, 5, Long_Long_Integer (Info.Modified));
      DB.Bind_Bytes (Upsert, 6, US.To_String (Info.Entity_Tag));
      DB.Bind_Bytes (Upsert, 7, US.To_String (Info.Content_Type));
      Bind_Checksum (Upsert, 8, Info.Checksum);
      if DB.Step (Upsert) /= DB.Done then
         raise Catalog_Error with "multipart object upsert returned a row";
      end if;
      declare
         Delete_Parts : DB.Statement;
      begin
         DB.Prepare
           (Delete_Parts, Item.Database,
            "DELETE FROM object_parts " &
            "WHERE bucket_name=?1 AND object_key=?2");
         DB.Bind (Delete_Parts, 1, Bucket);
         DB.Bind_Bytes (Delete_Parts, 2, Key);
         if DB.Step (Delete_Parts) /= DB.Done then
            raise Catalog_Error with
              "completed object part delete returned a row";
         end if;
      end;
      for Record_Value of Selected loop
         declare
            Insert_Part : DB.Statement;
         begin
            DB.Prepare
              (Insert_Part, Item.Database,
               "INSERT INTO object_parts(" &
               "bucket_name,object_key,part_number,size," &
               "checksum_algorithm,checksum_method,checksum_value) " &
               "VALUES(?1,?2,?3,?4,?5,?6,?7)");
            DB.Bind (Insert_Part, 1, Bucket);
            DB.Bind_Bytes (Insert_Part, 2, Key);
            DB.Bind
              (Insert_Part, 3, Long_Long_Integer (Record_Value.Number));
            DB.Bind
              (Insert_Part, 4,
               Long_Long_Integer (Record_Value.Info.Size));
            Bind_Checksum (Insert_Part, 5, Record_Value.Info.Checksum);
            if DB.Step (Insert_Part) /= DB.Done then
               raise Catalog_Error with
                 "completed object part insert returned a row";
            end if;
         end;
      end loop;
      DB.Prepare
        (Clear_Tags, Item.Database,
         "DELETE FROM object_tags WHERE bucket_name=?1 AND object_key=?2");
      DB.Bind (Clear_Tags, 1, Bucket);
      DB.Bind_Bytes (Clear_Tags, 2, Key);
      if DB.Step (Clear_Tags) /= DB.Done then
         raise Catalog_Error with "multipart object tag reset returned a row";
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
      Conditions       : Backends.Abort_Multipart_Conditions;
      Retired_Payloads : out Payloads;
      Result           : out Status)
   is
      Upload_Options : Backends.Multipart_Options;
      Created_Query  : DB.Statement;
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
        (Item, Bucket, Key, Upload_ID, Upload_Options, Result);
      if Result /= Success then
         DB.Rollback (Item.Database);
         In_Transaction := False;
         Item.Gate.Release;
         Locked := False;
         return;
      end if;
      if Conditions.Has_Initiated_Time then
         DB.Prepare
           (Created_Query, Item.Database,
            "SELECT created FROM multipart_uploads WHERE upload_id=?1");
         DB.Bind (Created_Query, 1, Upload_ID);
         if DB.Step (Created_Query) /= DB.Row then
            raise Catalog_Error with
              "multipart initiation-time query returned no row";
         elsif Long_Long_Integer'(DB.Column (Created_Query, 0)) /=
           Long_Long_Integer (Conditions.Initiated_Time)
         then
            DB.Rollback (Item.Database);
            In_Transaction := False;
            Result := Precondition_Failed;
            Item.Gate.Release;
            Locked := False;
            return;
         end if;
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
