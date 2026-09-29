--  BACKEND-MEMORY-3 (backend half of the same defect as SERVER-2): the
--  backend read contract cannot report that a selected generation is a delete
--  marker, so an adapter has no source for x-amz-delete-marker or for the
--  405 an exact marker read must produce.
--
--  src/flyology-object_storage-backends-memory.adb:318-329 folds a delete
--  marker into "no object" for every read, and Head (:1729-1746), Fetch
--  (:1543-1594) and Attributes (:1748-1794) return Not_Found with
--  Empty_Info.  Storage.Status (src/flyology-object_storage.ads:39-52) has no
--  delete-marker value and Object_Information (:554-562) has no marker field,
--  so the information is unreachable through Head_Object / Get_Object /
--  Get_Object_Attributes.
--
--  This program asserts the CORRECT behaviour: the read surface must let a
--  caller tell "the current generation is a delete marker" apart from "this
--  key does not exist", and "this exact version is a delete marker" apart
--  from "this version id does not exist" -- through the read call itself, not
--  through a separate ListObjectVersions.  The control that must pass shows
--  the store does know: List_Object_Versions reports the marker.
--
--  The pinned model requires exactly that distinction.  service-2.json,
--  GetObjectOutput.DeleteMarker: "If the current version of the object is a
--  delete marker, Amazon S3 behaves as if the object was deleted and includes
--  x-amz-delete-marker: true in the response.  If the specified version in
--  the request is a delete marker, the response returns a 405 Method Not
--  Allowed error and the Last-Modified: timestamp response header."
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Memory_Support;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Memory_3 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Memory_Support;

   use type Storage.Status;
   use type Storage.Byte_Count;
   use type Storage.Unix_Time;
   use type Backends.Version_Delete_Kind;

   Deadline : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Enabled : constant Storage.Bucket_Versioning_Configuration :=
     (Status     => Storage.Versioning_Enabled,
      MFA_Delete => Storage.MFA_Delete_Unconfigured);

   Store : Flyology.Object_Storage.Backends.Memory.Store
     (Bucket_Capacity => 4,
      Object_Capacity => 64,
      Byte_Capacity   => 1_048_576);

   Bucket : constant String := "bkt";
   Key    : constant String := "k";

   Result   : Storage.Status;
   Info     : Storage.Object_Information;
   Identity : Backends.Version_Identity;
   Outcome  : Backends.Version_Delete_Outcome;
   Marker   : US.Unbounded_String;
   Live     : US.Unbounded_String;

   function Describe (Result : Storage.Status;
                      Info   : Storage.Object_Information) return String is
     (Storage.Status'Image (Result)
      & " size " & Image_64 (Long_Long_Integer (Info.Size))
      & " modified " & Image_64 (Info.Modified)
      & " version '" & US.To_String (Info.Version) & "'");

   Absent_Status, Marker_Status, Bad_ID_Status : Storage.Status;
   Absent_Info, Marker_Info, Bad_ID_Info : Storage.Object_Information;

begin
   Store.Create_Bucket (Bucket, null, Deadline, Result);
   Check (Result = Storage.Success, "setup: bucket created");
   Store.Put_Bucket_Versioning (Bucket, Enabled, null, Deadline, Result);
   Check (Result = Storage.Success, "setup: versioning enabled");
   declare
      Source : Support.String_Source := Support.Source_Of ("payload");
   begin
      Store.Put_Object
        (Bucket, Key, Source, Storage.Default_Put_Options, null, Deadline,
         Info, Identity, Result);
      Live := Identity.Version_ID;
   end;
   Check (Result = Storage.Success, "setup: object published");
   Note ("setup: live version " & US.To_String (Live));

   Store.Delete_Selected_Object
     (Bucket, Key, Backends.Current_Version_Selector,
      Backends.No_Delete_Object_Conditions, False, null, Deadline,
      Outcome, Result);
   Check (Result = Storage.Success and then
            Outcome.Kind = Backends.Delete_Marker_Created,
          "setup: simple delete published a delete marker");
   Marker := Outcome.Version_ID;
   Note ("setup: marker version " & US.To_String (Marker));

   --  Control that must pass: the store does record the marker, and
   --  List_Object_Versions can say so.
   declare
      Options : Backends.List_Versions_Options;
      Page    : Backends.List_Versions_Page;
      Markers : Natural := 0;
   begin
      Options.Maximum := 100;
      Store.List_Object_Versions
        (Bucket, Options, null, Deadline, Page, Result);
      Check (Result = Storage.Success, "control: List_Object_Versions works");
      for Entry_Value of Page.Entries loop
         Note ("control: listed version '"
               & US.To_String (Entry_Value.Version_ID)
               & "' is_latest " & Boolean'Image (Entry_Value.Is_Latest)
               & " is_delete_marker "
               & Boolean'Image (Entry_Value.Is_Delete_Marker));
         if Entry_Value.Is_Delete_Marker then
            Markers := Markers + 1;
         end if;
      end loop;
      Check (Markers = 1,
             "control: the listing surface reports the marker generation");
   end;

   --  (a) Current read of a marker-hidden key must be distinguishable from a
   --  key that never existed.
   Store.Head_Object
     (Bucket, "never-existed", null, Deadline, Absent_Info, Absent_Status);
   Store.Head_Object (Bucket, Key, null, Deadline, Marker_Info, Marker_Status);
   Note ("head absent key          : " & Describe
           (Absent_Status, Absent_Info));
   Note ("head marker-hidden key   : " & Describe
           (Marker_Status, Marker_Info));
   Check (Marker_Status /= Absent_Status
            or else US.To_String (Marker_Info.Version) /=
              US.To_String (Absent_Info.Version)
            or else Marker_Info.Modified /= Absent_Info.Modified,
          "current HEAD distinguishes a delete marker from an absent key");

   --  (b) Exact read of the marker generation must be distinguishable from an
   --  exact read of a version id that does not exist.
   Store.Head_Object
     (Bucket, Key, null, Deadline, Bad_ID_Info, Bad_ID_Status,
      Selector =>
        (Kind => Backends.Exact_Version,
         ID   => US.To_Unbounded_String
           ("0000000000000000000000000000000000000000000000000000000000000000")));
   Store.Head_Object
     (Bucket, Key, null, Deadline, Marker_Info, Marker_Status,
      Selector => (Kind => Backends.Exact_Version, ID => Marker));
   Note ("head unknown version id  : " & Describe
           (Bad_ID_Status, Bad_ID_Info));
   Note ("head exact marker version: " & Describe
           (Marker_Status, Marker_Info));
   Check (Marker_Status /= Bad_ID_Status
            or else Marker_Info.Modified /= Bad_ID_Info.Modified,
          "exact HEAD distinguishes a delete marker from an unknown version");
   Check (Marker_Info.Modified /= 0,
          "exact HEAD of a marker carries the marker's Last-Modified time");

   --  (c) Control: an exact read of the live generation still works, and a
   --  current read of a live key still works.
   Store.Head_Object
     (Bucket, Key, null, Deadline, Info, Result,
      Selector => (Kind => Backends.Exact_Version, ID => Live));
   Note ("head exact live version  : " & Describe (Result, Info));
   Check (Result = Storage.Success and then Info.Size = 7,
          "control: exact HEAD of the retained live generation succeeds");

   --  (d) The same hole on the attribute surface.
   declare
      Snapshot : Backends.Object_Attribute_Snapshot;
      Options  : Backends.Object_Attribute_Options;
   begin
      Store.Get_Object_Attributes
        (Bucket, Key, Options, null, Deadline, Snapshot, Result,
         Selector => (Kind => Backends.Exact_Version, ID => Marker));
      Note ("attributes exact marker  : " & Storage.Status'Image (Result));
      Check (Result /= Storage.Not_Found,
             "GetObjectAttributes on a marker generation is not plain "
             & "Not_Found");
   end;

   Finish;
end Repro_Backend_Memory_3;
