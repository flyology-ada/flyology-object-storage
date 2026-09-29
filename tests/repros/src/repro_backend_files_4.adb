--  BACKEND-FILES-4: Delete_One removes the annotation sidecar durably
--  (Remove_Annotation_Generation -> Remove_Tree -> Delete_Tree +
--  Sync_Directory, files.adb:1034-1046 and :338-346) BEFORE it unlinks the
--  object record (Remove_Path, files.adb:8430-8435), and any failure in
--  Remove_Path propagates to Delete_Objects' "when others" handler, which
--  clears the outcomes and reports Backend_Unavailable
--  (files.adb:8536-8541).  A delete that is reported as failed, and that
--  left the object in place, has therefore already destroyed the object's
--  acknowledged annotations.
--
--  The failure is injected deterministically by making the bucket's
--  objects/ directory read-only between the two steps' preconditions:
--  the sidecar removal only needs annotations/, the unlink needs write
--  permission on objects/.
--
--  Correct behaviour asserted: after a DeleteObject that reports failure and
--  left the object readable, the object's annotation is still readable.
--  Controls: the same sequence with no injection deletes both, and the
--  annotation is verified present before the injected delete.
with Ada.Directories;
with Ada.Containers;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with GNAT.OS_Lib;
with Repro_Backend_Files_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Files_4 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Files_Support;
   use type Storage.Status;
   use type Storage.Object_Annotation_Presence;
   use type Ada.Containers.Count_Type;

   Bucket  : constant String := "delete-bucket";
   Forever : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Root : constant String := Support.Make_Root ("bf4");
   Objects_Directory : constant String :=
     Ada.Directories.Compose
       (Ada.Directories.Compose
          (Ada.Directories.Compose (Root, "buckets"), Bucket),
        "objects");

   procedure Chmod (Mode : String; Path : String) is
      Arguments : constant GNAT.OS_Lib.Argument_List :=
        [new String'(Mode), new String'(Path)];
      Status : constant Integer :=
        GNAT.OS_Lib.Spawn ("/bin/chmod", Arguments);
   begin
      Check (Status = 0, "chmod " & Mode & " " & Path & " succeeds");
   end Chmod;

   Subject : Files.Store := Files.Open (Root);
   Result  : Storage.Status;

   procedure Seed (Key : String) is
      Payload  : Support.String_Source := Support.Source_Of ("body");
      Info     : Storage.Object_Information;
      Identity : Backends.Version_Identity;
      Note_Info : Storage.Object_Annotation_Information;
      Annotation : Support.String_Source := Support.Source_Of ("kept");
   begin
      Subject.Put_Object
        (Bucket, Key, Payload, Storage.Default_Put_Options, null, Forever,
         Info, Identity, Result);
      Check (Result = Storage.Success, "PutObject " & Key);
      Backends.Put_Object_Annotation_If_Supported
        (Subject, Bucket, Key, "alpha", Annotation,
         (Expected_Checksum => Storage.No_Checksum_Information,
          Conditions        =>
            (Has_Object_ETag => False,
             Object_ETag     => US.Null_Unbounded_String)),
         null, Forever, Note_Info, Identity, Result);
      Check (Result = Storage.Success, "PutObjectAnnotation " & Key
             & "/alpha");
   end Seed;

   function Annotation_Count (Key : String) return Natural is
      Page     : Backends.Object_Annotation_Page;
      Identity : Backends.Version_Identity;
      Listing  : Storage.Status;
   begin
      Backends.List_Object_Annotations_If_Supported
        (Subject, Bucket, Key,
         (Prefix    => US.Null_Unbounded_String,
          Has_After => False,
          After     => US.Null_Unbounded_String,
          Maximum   => Backends.List_Limit'Last),
         null, Forever, Page, Identity, Listing);
      if Listing /= Storage.Success then
         return 0;
      end if;
      return Natural (Page.Annotations.Length);
   end Annotation_Count;

   function Object_Present (Key : String) return Boolean is
      Info : Storage.Object_Information;
      Head : Storage.Status;
   begin
      Subject.Head_Object (Bucket, Key, null, Forever, Info, Head);
      return Head = Storage.Success;
   end Object_Present;

begin
   Note ("files root " & Root);
   Subject.Create_Bucket (Bucket, null, Forever, Result);
   Check (Result = Storage.Success, "CreateBucket");

   --  Control: an uninjected delete removes the object and its annotation.
   Seed ("control-key");
   Check (Annotation_Count ("control-key") = 1,
          "control: the annotation is listed before the delete");
   Subject.Delete_Object (Bucket, "control-key", null, Forever, Result);
   Note ("control: DeleteObject -> " & Result'Image);
   Check (Result = Storage.Success, "control: the uninjected delete succeeds");
   Check (not Object_Present ("control-key"),
          "control: the object is gone after a successful delete");

   --  Subject: the unlink fails, the sidecar removal has already committed.
   Seed ("doomed-key");
   Check (Annotation_Count ("doomed-key") = 1,
          "the annotation is listed before the injected delete");
   Chmod ("0500", Objects_Directory);
   Subject.Delete_Object (Bucket, "doomed-key", null, Forever, Result);
   Note ("injected: DeleteObject -> " & Result'Image);
   Chmod ("0700", Objects_Directory);

   Check (Result /= Storage.Success,
          "the injected delete is reported as failed");
   Check (Object_Present ("doomed-key"),
          "the object survives the failed delete");
   Note ("annotations listed for the surviving object ="
         & Natural'Image (Annotation_Count ("doomed-key")));
   Check (Annotation_Count ("doomed-key") = 1,
          "the surviving object keeps the annotation that no request ever "
          & "asked to delete");

   declare
      Presence : Storage.Object_Annotation_Presence;
      Info     : Storage.Object_Annotation_Information;
      Identity : Backends.Version_Identity;
      Sink     : Support.Collecting_Annotation_Sink;
      Fetch    : Storage.Status;
   begin
      Backends.Get_Object_Annotation_If_Supported
        (Subject, Bucket, "doomed-key", "alpha", Sink, null, Forever,
         Presence, Info, Identity, Fetch);
      Note ("GetObjectAnnotation(doomed-key/alpha) -> " & Fetch'Image
            & " presence " & Presence'Image);
      Check (Fetch = Storage.Success
             and then Presence = Storage.Annotation_Present
             and then US.To_String (Sink.Data) = "kept",
             "the annotation payload is still readable after the failed "
             & "delete");
   end;

   if Failures = 0 then
      Support.Drop_Root (Root);
   else
      Note ("files root retained for inspection: " & Root);
   end if;
   Finish;
end Repro_Backend_Files_4;
