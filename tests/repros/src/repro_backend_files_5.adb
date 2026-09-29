--  BACKEND-FILES-5: a multipart operation carrying a valid upload ID but the
--  wrong object key must report Not_Found (S3 NoSuchUpload), as the memory
--  backend does.  The files backend locates the manifest by upload ID alone,
--  then Read_Manifest raises Data_Error on the key mismatch and the
--  "when others" handler reports Backend_Unavailable (HTTP 503 SlowDown).
--
--  Correct behaviour asserted: every multipart entry point reports Not_Found
--  for a mismatched key on BOTH backends.  Control: the memory backend, run
--  first in the same program with the identical sequence.
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Files_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Files_5 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Memory renames Flyology.Object_Storage.Backends.Memory;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Files_Support;
   use type Storage.Status;

   Bucket     : constant String := "mp-bucket";
   Right_Key  : constant String := "alpha";
   Wrong_Key  : constant String := "beta";
   Forever    : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   procedure Exercise
     (Store : in out Backends.Backend'Class; Label : String)
   is
      Result    : Storage.Status;
      Upload_ID : US.Unbounded_String;
      Info      : Storage.Object_Information;
      Page      : Backends.Multipart_Part_Page;
      Parts     : Backends.Multipart_Part_References;
   begin
      Store.Create_Bucket (Bucket, null, Forever, Result);
      Check (Result = Storage.Success, Label & " CreateBucket succeeds");
      Store.Create_Multipart_Upload
        (Bucket, Right_Key, Backends.Default_Multipart_Options, null,
         Forever, Upload_ID, Result);
      Check (Result = Storage.Success,
             Label & " CreateMultipartUpload succeeds");
      Note (Label & " upload id length" &
            Natural'Image (US.Length (Upload_ID)));

      --  A part for the RIGHT key still works (sanity control).
      declare
         Payload : Support.String_Source := Support.Source_Of ("abc");
      begin
         Store.Put_Multipart_Part
           (Bucket, Right_Key, US.To_String (Upload_ID), 1, Payload,
            null, Forever, Info, Result);
         Note (Label & " UploadPart(correct key) -> " & Result'Image);
         Check (Result = Storage.Success,
                Label & " UploadPart with the correct key succeeds");
      end;

      declare
         Payload : Support.String_Source := Support.Source_Of ("abc");
      begin
         Store.Put_Multipart_Part
           (Bucket, Wrong_Key, US.To_String (Upload_ID), 1, Payload,
            null, Forever, Info, Result);
         Note (Label & " UploadPart(wrong key) -> " & Result'Image);
         Check (Result = Storage.Not_Found,
                Label & " UploadPart with a mismatched key is Not_Found");
      end;

      Store.List_Multipart_Parts
        (Bucket, Wrong_Key, US.To_String (Upload_ID),
         (After => 0, Maximum => Backends.List_Limit'Last), null, Forever,
         Page, Result);
      Note (Label & " ListParts(wrong key) -> " & Result'Image);
      Check (Result = Storage.Not_Found,
             Label & " ListParts with a mismatched key is Not_Found");

      Parts.Append
        (Backends.Multipart_Part_Reference'
           (Number     => 1,
            Entity_Tag => Info.Entity_Tag,
            Checksum   => Storage.No_Checksum_Information));
      Store.Complete_Multipart_Upload
        (Bucket, Wrong_Key, US.To_String (Upload_ID), Parts, null, Forever,
         Info, Result);
      Note (Label & " CompleteMultipartUpload(wrong key) -> " &
            Result'Image);
      Check (Result = Storage.Not_Found,
             Label & " Complete with a mismatched key is Not_Found");

      Store.Abort_Multipart_Upload
        (Bucket, Wrong_Key, US.To_String (Upload_ID),
         Backends.No_Abort_Multipart_Conditions, null, Forever, Result);
      Note (Label & " AbortMultipartUpload(wrong key) -> " & Result'Image);
      Check (Result = Storage.Not_Found,
             Label & " Abort with a mismatched key is Not_Found");
   end Exercise;

   Root : constant String := Support.Make_Root ("bf5");
begin
   Note ("files root " & Root);
   declare
      Control : Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1024 * 1024);
   begin
      Exercise (Control, "memory (control)");
   end;
   declare
      Subject : Files.Store := Files.Open (Root);
   begin
      Exercise (Subject, "files  (subject)");
   end;
   if Failures = 0 then
      Support.Drop_Root (Root);
   else
      Note ("files root retained for inspection: " & Root);
   end if;
   Finish;
end Repro_Backend_Files_5;
