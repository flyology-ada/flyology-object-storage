--  BACKEND-FILES-2: the storage boundary admits object keys of up to 1,024
--  bytes (Flyology.Object_Storage.Valid_Object_Key,
--  src/flyology-object_storage.adb:479-489, documented in
--  flyology-object_storage.ads:667-670), and AWS S3 likewise accepts keys of
--  up to 1,024 bytes (from memory, unverified; the pinned botocore model's
--  ObjectKey shape only carries "min": 1 and no maximum).  The files backend
--  encodes each key byte as two hex characters split into 100-character
--  directory components, so a long key produces an absolute path beyond the
--  host's PATH_MAX and every operation on it fails.
--
--  Correct behaviour asserted: PutObject with a 1,024-byte key succeeds on
--  the files backend, as it does on the memory backend (control).  The
--  program also measures the exact largest key length this host accepts and
--  reports it.
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Files_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Files_2 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Memory renames Flyology.Object_Storage.Backends.Memory;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Files_Support;
   use type Storage.Status;

   Bucket  : constant String := "long-key-bucket";
   Forever : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   function Put_Key
     (Store  : in out Backends.Backend'Class;
      Length : Positive) return Storage.Status
   is
      Key      : constant String (1 .. Length) := [others => 'k'];
      Payload  : Support.String_Source := Support.Source_Of ("body");
      Info     : Storage.Object_Information;
      Identity : Backends.Version_Identity;
      Result   : Storage.Status;
   begin
      Store.Put_Object
        (Bucket, Key, Payload, Storage.Default_Put_Options, null, Forever,
         Info, Identity, Result);
      return Result;
   end Put_Key;

   Root : constant String := Support.Make_Root ("bf2");
   Result : Storage.Status;
begin
   Note ("files root " & Root & " (" & Image (Root'Length) & " bytes)");
   Check (Storage.Valid_Object_Key (String'(1 .. 1_024 => 'k')),
          "a 1,024-byte key satisfies the documented storage boundary");
   Check (not Storage.Valid_Object_Key (String'(1 .. 1_025 => 'k')),
          "1,024 bytes is the documented maximum");

   declare
      Control : Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1024 * 1024);
   begin
      Control.Create_Bucket (Bucket, null, Forever, Result);
      Check (Result = Storage.Success, "memory (control) CreateBucket");
      Result := Put_Key (Control, 1_024);
      Note ("memory (control) PUT 1024-byte key -> " & Result'Image);
      Check (Result = Storage.Success,
             "memory (control) accepts a 1,024-byte key");
   end;

   declare
      Subject : Files.Store := Files.Open (Root);
      Low     : Natural := 0;      --  known good (0 = none tried yet)
      High    : Natural := 1_025;  --  known bad
   begin
      Subject.Create_Bucket (Bucket, null, Forever, Result);
      Check (Result = Storage.Success, "files  (subject) CreateBucket");

      Result := Put_Key (Subject, 8);
      Note ("files  (subject) PUT 8-byte key -> " & Result'Image);
      Check (Result = Storage.Success,
             "files  (subject) accepts a short key (harness control)");

      Result := Put_Key (Subject, 1_024);
      Note ("files  (subject) PUT 1024-byte key -> " & Result'Image);
      Check (Result = Storage.Success,
             "files  (subject) accepts a 1,024-byte key");

      --  Measure the exact threshold on this host.
      Low := 8;
      while High - Low > 1 loop
         declare
            Middle : constant Positive := (Low + High) / 2;
         begin
            if Put_Key (Subject, Middle) = Storage.Success then
               Low := Middle;
            else
               High := Middle;
            end if;
         end;
      end loop;
      Note ("files  (subject) largest accepted key length on this host ="
            & Natural'Image (Low) & " bytes; " & Image (Low + 1)
            & " bytes already fails");
      Note ("files  (subject) status at" & Natural'Image (Low + 1)
            & " bytes -> " & Put_Key (Subject, Low + 1)'Image);
      Note ("the S3 adapter maps Backend_Unavailable to 503 SlowDown "
            & "(server-s3_applications.adb:1951-1954)");
   end;

   if Failures = 0 then
      Support.Drop_Root (Root);
   else
      Note ("files root retained for inspection: " & Root);
   end if;
   Finish;
end Repro_Backend_Files_2;
