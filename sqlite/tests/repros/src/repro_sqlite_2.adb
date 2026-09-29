--  BACKEND-SQLITE-2: the annotation copy lease is created with refs=1 under
--  CHECK(refs>0) but released with "SET refs=refs-1", so the first
--  Copy_Object of an annotated source violates the constraint after the
--  destination has already been published.
--
--  Asserts the CORRECT behaviour: Copy_Object of an annotated source returns
--  Success without raising, and the destination carries the copied
--  annotation.  A control copy of an UNannotated source runs first and must
--  succeed, so the program shows the harness works.
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.SQLite;
with Repro_Support; use Repro_Support;
with Repro_SQLite_Support; use Repro_SQLite_Support;

procedure Repro_SQLite_2 is
   use type Flyology.Object_Storage.Status;
   use type Flyology.Object_Storage.Object_Annotation_Presence;
   package OSS renames Flyology.Object_Storage;
   package OSB renames Flyology.Object_Storage.Backends;
   package SQL_Backend renames Flyology.Object_Storage.Backends.SQLite;

   Root   : constant String := Fresh_Root ("annotation-copy");
   Bucket : constant String := "annotation-bucket";
   Never  : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Annotation_Name : constant String := "note";
   Annotation_Body : constant String := "annotation payload bytes";

   Store  : SQL_Backend.Store := SQL_Backend.Open (Root);
   Result : OSS.Status;

   procedure Put (Key : String; Content : String) is
      Source   : Buffer_Source := Source_Of (Content);
      Info     : OSS.Object_Information;
      Identity : OSB.Version_Identity;
   begin
      Store.Put_Object
        (Bucket, Key, Source, OSS.Default_Put_Options, null, Never,
         Info, Identity, Result);
      Check (Result = OSS.Success, "Put_Object " & Key & " succeeds");
   end Put;

   procedure Annotate (Key : String) is
      Source   : Buffer_Source := Source_Of (Annotation_Body);
      Info     : OSS.Object_Annotation_Information;
      Identity : OSB.Version_Identity;
      Options  : constant OSB.Put_Object_Annotation_Options :=
        (Expected_Checksum => <>,
         Conditions =>
           (Has_Object_ETag => False,
            Object_ETag     => Ada.Strings.Unbounded.Null_Unbounded_String));
   begin
      Store.Put_Object_Annotation
        (Bucket, Key, Annotation_Name, Source, Options, null, Never,
         Info, Identity, Result);
      Note ("Put_Object_Annotation on " & Key & " " & Image (Result) &
            " size " & Image_64 (Long_Long_Integer (Info.Size)));
      Check (Result = OSS.Success,
             "Put_Object_Annotation on " & Key & " succeeds");
   end Annotate;

   procedure Copy
     (From, To : String; Label : String;
      Directive : OSB.Copy_Annotation_Directive := OSB.Copy_Annotations)
   is
      Options : OSB.Copy_Options := OSB.Default_Copy_Options;
      Info    : OSS.Object_Information;
      Source_Identity      : OSB.Version_Identity;
      Destination_Identity : OSB.Version_Identity;
      Raised  : Boolean := False;
   begin
      Result := OSS.Backend_Unavailable;
      Options.Annotation_Directive := Directive;
      begin
         Store.Copy_Object
           (Bucket, From, Bucket, To, Options, null, Never,
            Info, Source_Identity, Destination_Identity, Result);
      exception
         when E : others =>
            Raised := True;
            Note (Label & ": Copy_Object raised " &
                  Ada.Exceptions.Exception_Name (E) & " -- " &
                  Ada.Exceptions.Exception_Message (E));
      end;
      if not Raised then
         Note (Label & ": Copy_Object returned " & Image (Result));
      end if;
      Check (not Raised, Label & ": Copy_Object does not raise");
      Check (Result = OSS.Success, Label & ": Copy_Object returns Success");
   end Copy;

begin
   Note ("root " & Root);
   Store.Create_Bucket (Bucket, null, Never, Result);
   Check (Result = OSS.Success, "Create_Bucket succeeds");

   --  Control: an unannotated source copies cleanly.
   Put ("plain-src", "plain body");
   Copy ("plain-src", "plain-dst", "control (no annotation)");

   --  Subject: the same copy with one annotation on the source.
   Put ("annotated-src", "annotated body");
   Annotate ("annotated-src");
   Copy ("annotated-src", "annotated-dst", "subject (one annotation)");

   --  The destination must carry the copied annotation.
   declare
      Sink     : Annotation_Sink;
      Presence : OSS.Object_Annotation_Presence;
      Info     : OSS.Object_Annotation_Information;
      Identity : OSB.Version_Identity;
   begin
      Store.Get_Object_Annotation
        (Bucket, "annotated-dst", Annotation_Name, Sink, null, Never,
         Presence, Info, Identity, Result);
      Note ("Get_Object_Annotation on the copy " & Image (Result) &
            " presence " & OSS.Object_Annotation_Presence'Image (Presence) &
            " bytes " & Image (Ada.Strings.Unbounded.Length (Sink.Data)));
      Check (Result = OSS.Success,
             "Get_Object_Annotation on the copy succeeds");
      Check (Presence = OSS.Annotation_Present,
             "the copied annotation is present on the destination");
      Check (Ada.Strings.Unbounded.To_String (Sink.Data) = Annotation_Body,
             "the copied annotation payload round-trips");
   end;

   --  Evidence that the destination was published despite the raise.
   declare
      Info : OSS.Object_Information;
   begin
      Store.Head_Object
        (Bucket, "annotated-dst", null, Never, Info, Result);
      Note ("Head_Object on the copy afterwards " & Image (Result) &
            " size " & Image_64 (Long_Long_Integer (Info.Size)));
   end;

   --  The directive does not matter: Find_Selected_Object takes the leases
   --  unconditionally, so EXCLUDE fails the same way on a fresh source.
   Put ("excluded-src", "excluded body");
   Annotate ("excluded-src");
   Copy ("excluded-src", "excluded-dst", "subject (EXCLUDE directive)",
         OSB.Exclude_Annotations);

   --  A second copy of the same annotated source: the lease is at 1 again
   --  after the first (failed) release left it held, so refs 1 -> 2 -> 1
   --  and this one succeeds, masking the defect.
   Copy ("annotated-src", "annotated-dst-2", "second copy of same source");

   Finish;
end Repro_SQLite_2;
