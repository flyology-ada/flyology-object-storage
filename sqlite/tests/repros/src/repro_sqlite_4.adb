--  BACKEND-SQLITE-4: Delete_Bucket only consults the `objects` mirror and
--  `multipart_uploads`, never `object_versions`.  A versioning-enabled
--  bucket whose only key ends in a delete marker has no mirror row, so the
--  DELETE hits the ON DELETE RESTRICT foreign key on object_versions, the
--  SQLite error is rewrapped as Backend_Unavailable, and the S3 boundary
--  answers 503 SlowDown instead of the defined Bucket_Not_Empty status.
--
--  Asserts the CORRECT behaviour: the SQLite backend reports
--  Bucket_Not_Empty, the same status the memory backend reports for the
--  identical sequence (the memory store is the control and must pass).
with Ada.Real_Time;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with Repro_S3_Server;
with Repro_Support; use Repro_Support;
with Repro_SQLite_Support; use Repro_SQLite_Support;

procedure Repro_SQLite_4 is
   use type Flyology.Object_Storage.Status;
   package OSS renames Flyology.Object_Storage;
   package OSB renames Flyology.Object_Storage.Backends;
   package SQL_Backend renames Flyology.Object_Storage.Backends.SQLite;

   Root   : constant String := Fresh_Root ("delete-bucket");
   Bucket : constant String := "marker-bucket";
   Never  : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Versioned : constant OSS.Bucket_Versioning_Configuration :=
     (Status     => OSS.Versioning_Enabled,
      MFA_Delete => OSS.MFA_Delete_Unconfigured);

   procedure Exercise
     (Store : in out OSB.Backend'Class; Label : String; Control : Boolean)
   is
      Result : OSS.Status;
   begin
      Store.Create_Bucket (Bucket, null, Never, Result);
      Check (Result = OSS.Success, Label & ": Create_Bucket succeeds");

      Store.Put_Bucket_Versioning (Bucket, Versioned, null, Never, Result);
      Check (Result = OSS.Success,
             Label & ": Put_Bucket_Versioning Enabled succeeds");

      declare
         Source   : Buffer_Source := Source_Of ("one");
         Info     : OSS.Object_Information;
         Identity : OSB.Version_Identity;
      begin
         Store.Put_Object
           (Bucket, "k", Source, OSS.Default_Put_Options, null, Never,
            Info, Identity, Result);
         Check (Result = OSS.Success, Label & ": Put_Object succeeds");
      end;

      Store.Delete_Object (Bucket, "k", null, Never, Result);
      Note (Label & ": Delete_Object (publishes a delete marker) " &
            Image (Result));
      Check (Result = OSS.Success, Label & ": Delete_Object succeeds");

      --  The key is now absent from the current view.
      declare
         Info : OSS.Object_Information;
      begin
         Store.Head_Object (Bucket, "k", null, Never, Info, Result);
         Note (Label & ": Head_Object after the marker " & Image (Result));
      end;

      --  Two retained generations remain (data + marker), so DeleteBucket
      --  must report the bucket as not empty.
      Store.Delete_Bucket (Bucket, null, Never, Result);
      Note (Label & ": Delete_Bucket " & Image (Result));
      Check (Result = OSS.Bucket_Not_Empty,
             Label & ": Delete_Bucket reports Bucket_Not_Empty" &
             (if Control then " (control)" else ""));
   end Exercise;

begin
   Note ("root " & Root);
   Exercise (Repro_S3_Server.Store, "memory", Control => True);
   declare
      Store : SQL_Backend.Store := SQL_Backend.Open (Root);
   begin
      Exercise (Store, "sqlite", Control => False);
   end;
   Finish;
end Repro_SQLite_4;
