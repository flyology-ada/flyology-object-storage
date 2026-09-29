--  BACKEND-FILES-6: an opaque version identifier must never be reused for a
--  different object generation.  The files backend derives it from
--  max(existing publication)+1 (Next_Generation_Publication), so deleting the
--  newest generation lets the next PUT mint the deleted generation's exact
--  version ID.
--
--  Correct behaviour asserted: after PUT A -> V1, DELETE k?versionId=V1,
--  PUT B -> V2, the identifiers differ, and GET k?versionId=V1 does not
--  return the new bytes.  Control: the memory backend, run first with the
--  identical sequence.
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Files_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Files_6 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Memory renames Flyology.Object_Storage.Backends.Memory;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Files_Support;
   use type Storage.Status;

   Bucket  : constant String := "ver-bucket";
   Key     : constant String := "reused";
   Forever : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   procedure Exercise
     (Store : in out Backends.Backend'Class; Label : String)
   is
      Result   : Storage.Status;
      Info     : Storage.Object_Information;
      Identity : Backends.Version_Identity;
      Outcome  : Backends.Version_Delete_Outcome;
      First_ID : US.Unbounded_String;
      Second_ID : US.Unbounded_String;
   begin
      Store.Create_Bucket (Bucket, null, Forever, Result);
      Check (Result = Storage.Success, Label & " CreateBucket succeeds");
      Store.Put_Bucket_Versioning
        (Bucket,
         (Status     => Storage.Versioning_Enabled,
          MFA_Delete => Storage.MFA_Delete_Unconfigured),
         null, Forever, Result);
      Check (Result = Storage.Success, Label & " versioning enabled");

      declare
         Payload : Support.String_Source := Support.Source_Of ("AAAA");
      begin
         Store.Put_Object
           (Bucket, Key, Payload, Storage.Default_Put_Options, null,
            Forever, Info, Identity, Result);
         Check (Result = Storage.Success, Label & " first PUT succeeds");
         First_ID := Identity.Version_ID;
      end;
      Note (Label & " V1 = " & US.To_String (First_ID));

      Store.Delete_Selected_Object
        (Bucket, Key,
         (Kind => Backends.Exact_Version, ID => First_ID),
         Backends.No_Delete_Object_Conditions, False, null, Forever,
         Outcome, Result);
      Note (Label & " DELETE versionId=V1 -> " & Result'Image);
      Check (Result = Storage.Success, Label & " exact delete of V1 succeeds");

      declare
         Payload : Support.String_Source := Support.Source_Of ("BBBB");
      begin
         Store.Put_Object
           (Bucket, Key, Payload, Storage.Default_Put_Options, null,
            Forever, Info, Identity, Result);
         Check (Result = Storage.Success, Label & " second PUT succeeds");
         Second_ID := Identity.Version_ID;
      end;
      Note (Label & " V2 = " & US.To_String (Second_ID));

      Check (US.To_String (Second_ID) /= US.To_String (First_ID),
             Label & " the republished version ID differs from the deleted "
             & "one");

      declare
         Sink : Support.Collecting_Sink;
      begin
         Store.Get_Object
           (Bucket, Key, Storage.Whole_Object, Sink, null, Forever, Info,
            Result,
            Selector =>
              (Kind => Backends.Exact_Version, ID => First_ID));
         Note (Label & " GET versionId=V1 -> " & Result'Image &
               " body=""" & US.To_String (Sink.Data) & """");
         Check (US.To_String (Sink.Data) /= "BBBB",
                Label & " GET of the deleted version ID does not serve the "
                & "new bytes");
      end;
   end Exercise;

   Root : constant String := Support.Make_Root ("bf6");
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
end Repro_Backend_Files_6;
