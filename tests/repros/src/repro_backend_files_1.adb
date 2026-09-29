--  BACKEND-FILES-1: publishing a new object generation must not expose the
--  replaced generation's annotations, and must not orphan the replaced
--  generation's annotation sidecar directory.
--
--  In an unversioned bucket the files backend writes a
--  CompleteMultipartUpload record without an annotation generation ID, so
--  Stored_Annotation_Generation_ID falls back to SHA256(object path), which
--  is identical for every generation published at that fixed path.  The
--  completion also never removes the previous generation's sidecar (ordinary
--  PUT does, at Put_Object_Internal).
--
--  Correct behaviour asserted (matching the memory backend, which clears the
--  annotation map on completion):
--    A. after PUT-with-annotation then COMPLETE, the new object has no
--       annotations, and no orphan generation- directory survives;
--    B. after COMPLETE, annotate, COMPLETE again, the new object has no
--       annotations.
--  Control: the memory backend runs the identical sequence first.
with Ada.Containers;
with Ada.Directories;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Files;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Files_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Files_1 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package Files renames Flyology.Object_Storage.Backends.Files;
   package Memory renames Flyology.Object_Storage.Backends.Memory;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Files_Support;
   use type Storage.Status;
   use type Storage.Object_Annotation_Presence;
   use type Ada.Containers.Count_Type;

   Bucket  : constant String := "anno-bucket";
   Forever : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   procedure Complete_One_Part_Upload
     (Store : in out Backends.Backend'Class;
      Key   : String;
      Body_Text : String;
      Label : String)
   is
      Result    : Storage.Status;
      Upload_ID : US.Unbounded_String;
      Info      : Storage.Object_Information;
      Parts     : Backends.Multipart_Part_References;
   begin
      Store.Create_Multipart_Upload
        (Bucket, Key, Backends.Default_Multipart_Options, null, Forever,
         Upload_ID, Result);
      Check (Result = Storage.Success,
             Label & " CreateMultipartUpload " & Key);
      declare
         Payload : Support.String_Source := Support.Source_Of (Body_Text);
      begin
         Store.Put_Multipart_Part
           (Bucket, Key, US.To_String (Upload_ID), 1, Payload, null,
            Forever, Info, Result);
         Check (Result = Storage.Success, Label & " UploadPart " & Key);
      end;
      Parts.Append
        (Backends.Multipart_Part_Reference'
           (Number     => 1,
            Entity_Tag => Info.Entity_Tag,
            Checksum   => Storage.No_Checksum_Information));
      Store.Complete_Multipart_Upload
        (Bucket, Key, US.To_String (Upload_ID), Parts, null, Forever, Info,
         Result);
      Check (Result = Storage.Success,
             Label & " CompleteMultipartUpload " & Key);
   end Complete_One_Part_Upload;

   procedure Annotate
     (Store : in out Backends.Backend'Class;
      Key   : String;
      Name  : String;
      Label : String)
   is
      Result   : Storage.Status;
      Info     : Storage.Object_Annotation_Information;
      Identity : Backends.Version_Identity;
      Payload  : Support.String_Source := Support.Source_Of ("annotated");
   begin
      Backends.Put_Object_Annotation_If_Supported
        (Store, Bucket, Key, Name, Payload,
         (Expected_Checksum => Storage.No_Checksum_Information,
          Conditions        =>
            (Has_Object_ETag => False,
             Object_ETag     => US.Null_Unbounded_String)),
         null, Forever, Info, Identity, Result);
      Check (Result = Storage.Success,
             Label & " PutObjectAnnotation " & Key & '/' & Name);
   end Annotate;

   function Annotation_Count
     (Store : in out Backends.Backend'Class;
      Key   : String;
      Label : String) return Natural
   is
      Result   : Storage.Status;
      Page     : Backends.Object_Annotation_Page;
      Identity : Backends.Version_Identity;
   begin
      Backends.List_Object_Annotations_If_Supported
        (Store, Bucket, Key,
         (Prefix    => US.Null_Unbounded_String,
          Has_After => False,
          After     => US.Null_Unbounded_String,
          Maximum   => Backends.List_Limit'Last),
         null, Forever, Page, Identity, Result);
      Check (Result = Storage.Success,
             Label & " ListObjectAnnotations " & Key & " succeeds");
      return Natural (Page.Annotations.Length);
   end Annotation_Count;

   function Annotation_Present
     (Store : in out Backends.Backend'Class;
      Key   : String;
      Name  : String) return Boolean
   is
      Result   : Storage.Status;
      Info     : Storage.Object_Annotation_Information;
      Identity : Backends.Version_Identity;
      Presence : Storage.Object_Annotation_Presence;
      Sink     : Support.Collecting_Annotation_Sink;
   begin
      Backends.Get_Object_Annotation_If_Supported
        (Store, Bucket, Key, Name, Sink, null, Forever, Presence, Info,
         Identity, Result);
      return Result = Storage.Success
        and then Presence = Storage.Annotation_Present;
   end Annotation_Present;

   procedure Exercise
     (Store : in out Backends.Backend'Class; Label : String)
   is
      Result : Storage.Status;
      Info   : Storage.Object_Information;
      Identity : Backends.Version_Identity;
   begin
      Store.Create_Bucket (Bucket, null, Forever, Result);
      Check (Result = Storage.Success, Label & " CreateBucket succeeds");

      --  Scenario A: ordinary PUT, annotate, then replace by completion.
      declare
         Payload : Support.String_Source := Support.Source_Of ("put-body");
      begin
         Store.Put_Object
           (Bucket, "put-then-complete", Payload,
            Storage.Default_Put_Options, null, Forever, Info, Identity,
            Result);
         Check (Result = Storage.Success, Label & " PutObject succeeds");
      end;
      Annotate (Store, "put-then-complete", "alpha", Label);
      Check (Annotation_Count (Store, "put-then-complete", Label) = 1,
             Label & " the annotation is visible before replacement");
      Complete_One_Part_Upload
        (Store, "put-then-complete", "mp-body-1", Label);
      Note (Label & " A: annotations after COMPLETE replaced a PUT ="
            & Natural'Image
              (Annotation_Count (Store, "put-then-complete", Label)));
      Check (Annotation_Count (Store, "put-then-complete", Label) = 0,
             Label & " A: the completed object starts with no annotations");
      Check (not Annotation_Present (Store, "put-then-complete", "alpha"),
             Label & " A: GetObjectAnnotation reports the annotation absent");

      --  Scenario B: completion, annotate, completion again.
      Complete_One_Part_Upload (Store, "complete-twice", "mp-body-2", Label);
      Annotate (Store, "complete-twice", "beta", Label);
      Check (Annotation_Count (Store, "complete-twice", Label) = 1,
             Label & " the annotation is visible before the second "
             & "completion");
      Complete_One_Part_Upload (Store, "complete-twice", "mp-body-3", Label);
      Note (Label & " B: annotations after the second COMPLETE ="
            & Natural'Image
              (Annotation_Count (Store, "complete-twice", Label)));
      Check (Annotation_Count (Store, "complete-twice", Label) = 0,
             Label & " B: the second completed object starts with no "
             & "annotations");
      Check (not Annotation_Present (Store, "complete-twice", "beta"),
             Label & " B: GetObjectAnnotation reports the annotation absent");
   end Exercise;

   Root : constant String := Support.Make_Root ("bf1");
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
   declare
      Annotations : constant String :=
        Ada.Directories.Compose
          (Ada.Directories.Compose
             (Ada.Directories.Compose (Root, "buckets"), Bucket),
           "annotations");

      function Hex (Value : Natural) return Character is
        (if Value < 10 then Character'Val (Character'Pos ('0') + Value)
         else Character'Val (Character'Pos ('A') + Value - 10));

      function Key_Directory (Key : String) return String is
         Encoded : String (1 .. 2 * Key'Length);
         Cursor  : Natural := 0;
      begin
         for Byte of Key loop
            Encoded (Cursor + 1) := Hex (Character'Pos (Byte) / 16);
            Encoded (Cursor + 2) := Hex (Character'Pos (Byte) mod 16);
            Cursor := Cursor + 2;
         end loop;
         return Ada.Directories.Compose
           (Annotations, Encoded & ".annotations");
      end Key_Directory;

      Orphaned : constant Natural := Support.Count_Generation_Directories
        (Key_Directory ("put-then-complete"));
      Inherited : constant Natural := Support.Count_Generation_Directories
        (Key_Directory ("complete-twice"));
   begin
      Note ("files A: sidecar generation- directories left under "
            & Key_Directory ("put-then-complete") & " ="
            & Natural'Image (Orphaned));
      Check (Orphaned = 0,
             "files  (subject) A: the PUT generation's sidecar directory is "
             & "removed by the completion that replaced it (no orphan)");
      Note ("files B: sidecar generation- directories left under "
            & Key_Directory ("complete-twice") & " ="
            & Natural'Image (Inherited));
      Check (Inherited = 0,
             "files  (subject) B: the replaced completion's sidecar "
             & "directory is removed by the second completion");
   end;
   if Failures = 0 then
      Support.Drop_Root (Root);
   else
      Note ("files root retained for inspection: " & Root);
   end if;
   Finish;
end Repro_Backend_Files_1;
