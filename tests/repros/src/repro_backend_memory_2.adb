--  BACKEND-MEMORY-2: same-key CopyObject with an exact or null source
--  selector (the S3 "restore a previous version" operation) is rejected as
--  Invalid_Request.
--
--  src/flyology-object_storage-backends-memory.adb:4977-4986 rejects any copy
--  whose source bucket and key equal the destination under the default
--  directives, without ever consulting Options.Source_Selector.  The same
--  predicate is duplicated in src/flyology-object_storage-backends-files.adb:
--  7602-7611 and sqlite/src/flyology-object_storage-backends-sqlite.adb:
--  2436-2445.
--
--  This program asserts the CORRECT behaviour: a same-key copy whose source
--  names an exact (or null) generation succeeds and publishes that
--  generation's bytes as the new current version, while a same-key copy with
--  no source selector remains Invalid_Request.  The reference server MinIO
--  RELEASE.2025-09-07T16-13-09Z behaves exactly that way (see the report).
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.Backends.Memory;
with Repro_Backend_Memory_Support;
with Repro_S3_Server; use Repro_S3_Server;
with Repro_Support; use Repro_Support;

procedure Repro_Backend_Memory_2 is
   package Storage renames Flyology.Object_Storage;
   package Backends renames Flyology.Object_Storage.Backends;
   package US renames Ada.Strings.Unbounded;
   package Support renames Repro_Backend_Memory_Support;

   use type Storage.Status;

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   Versioning_Document : constant String :=
     "<VersioningConfiguration "
     & "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">"
     & "<Status>Enabled</Status></VersioningConfiguration>";

   Deadline : constant Ada.Real_Time.Time := Ada.Real_Time.Time_Last;

   Enabled : constant Storage.Bucket_Versioning_Configuration :=
     (Status     => Storage.Versioning_Enabled,
      MFA_Delete => Storage.MFA_Delete_Unconfigured);

   function Fetch
     (Store : in out Flyology.Object_Storage.Backends.Memory.Store;
      Bucket, Key : String) return String
   is
      Sink   : Support.Collecting_Sink;
      Info   : Storage.Object_Information;
      Result : Storage.Status;
   begin
      Store.Get_Object
        (Bucket, Key, Storage.Whole_Object, Sink, null, Deadline,
         Info, Result);
      if Result /= Storage.Success then
         return "<" & Storage.Status'Image (Result) & ">";
      end if;
      return US.To_String (Sink.Data);
   end Fetch;

   procedure Put
     (Store : in out Flyology.Object_Storage.Backends.Memory.Store;
      Bucket, Key, Payload : String;
      Version : out US.Unbounded_String;
      Result  : out Storage.Status)
   is
      Source   : Support.String_Source := Support.Source_Of (Payload);
      Info     : Storage.Object_Information;
      Identity : Backends.Version_Identity;
   begin
      Store.Put_Object
        (Bucket, Key, Source, Storage.Default_Put_Options, null, Deadline,
         Info, Identity, Result);
      Version := Identity.Version_ID;
   end Put;

   ------------------------------------------------------------------
   --  1. Exact-version restore onto the same key, backend interface.
   ------------------------------------------------------------------

   procedure Exact_Restore is
      Store : Flyology.Object_Storage.Backends.Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1_048_576);
      Bucket : constant String := "bkt";
      Key    : constant String := "k";
      V1, V2 : US.Unbounded_String;
      Result : Storage.Status;
      Options : Backends.Copy_Options;
      Info    : Storage.Object_Information;
      Source_Identity, Destination_Identity : Backends.Version_Identity;
   begin
      Store.Create_Bucket (Bucket, null, Deadline, Result);
      Check (Result = Storage.Success, "exact: bucket created");
      Store.Put_Bucket_Versioning (Bucket, Enabled, null, Deadline, Result);
      Check (Result = Storage.Success, "exact: versioning enabled");
      Put (Store, Bucket, Key, "v1", V1, Result);
      Check (Result = Storage.Success, "exact: first PUT published");
      Put (Store, Bucket, Key, "v2", V2, Result);
      Check (Result = Storage.Success, "exact: second PUT published");
      Note ("exact: v1 " & US.To_String (V1) & " v2 " & US.To_String (V2));
      Check (Fetch (Store, Bucket, Key) = "v2", "exact: current body is v2");

      --  Control: a same-key copy with NO source selector must stay
      --  Invalid_Request (this is what AWS and MinIO reject).
      Options := Backends.Default_Copy_Options;
      Store.Copy_Object
        (Bucket, Key, Bucket, Key, Options, null, Deadline,
         Info, Source_Identity, Destination_Identity, Result);
      Note ("control: same-key copy without a selector -> "
            & Storage.Status'Image (Result));
      Check (Result = Storage.Invalid_Request,
             "control: unselected same-key copy is still Invalid_Request");

      --  Under test: restore v1 onto the same key.
      Options := Backends.Default_Copy_Options;
      Options.Source_Selector :=
        (Kind => Backends.Exact_Version, ID => V1);
      Store.Copy_Object
        (Bucket, Key, Bucket, Key, Options, null, Deadline,
         Info, Source_Identity, Destination_Identity, Result);
      Note ("exact: same-key copy with Source_Selector = (Exact_Version, v1)"
            & " -> " & Storage.Status'Image (Result));
      Check (Result = Storage.Success,
             "exact: same-key copy of an exact source generation succeeds");
      Check (US.To_String (Source_Identity.Version_ID) = US.To_String (V1),
             "exact: Source_Identity names the selected generation");
      Note ("exact: destination identity "
            & US.To_String (Destination_Identity.Version_ID));
      Note ("exact: current body after restore '"
            & Fetch (Store, Bucket, Key) & "'");
      Check (Fetch (Store, Bucket, Key) = "v1",
             "exact: restore republished the v1 bytes as current");
   end Exact_Restore;

   ------------------------------------------------------------------
   --  2. Null-generation restore onto the same key.
   ------------------------------------------------------------------

   procedure Null_Restore is
      Store : Flyology.Object_Storage.Backends.Memory.Store
        (Bucket_Capacity => 4,
         Object_Capacity => 64,
         Byte_Capacity   => 1_048_576);
      Bucket : constant String := "nul";
      Key    : constant String := "k";
      Ignored : US.Unbounded_String;
      Result  : Storage.Status;
      Options : Backends.Copy_Options;
      Info    : Storage.Object_Information;
      Source_Identity, Destination_Identity : Backends.Version_Identity;
   begin
      Store.Create_Bucket (Bucket, null, Deadline, Result);
      Check (Result = Storage.Success, "null: bucket created");
      Put (Store, Bucket, Key, "n0", Ignored, Result);
      Check (Result = Storage.Success,
             "null: unconfigured PUT published the null generation");
      Store.Put_Bucket_Versioning (Bucket, Enabled, null, Deadline, Result);
      Check (Result = Storage.Success, "null: versioning enabled");
      Put (Store, Bucket, Key, "e1", Ignored, Result);
      Check (Result = Storage.Success, "null: enabled PUT published");
      Check (Fetch (Store, Bucket, Key) = "e1", "null: current body is e1");

      Options := Backends.Default_Copy_Options;
      Options.Source_Selector := Backends.Null_Version_Selector;
      Store.Copy_Object
        (Bucket, Key, Bucket, Key, Options, null, Deadline,
         Info, Source_Identity, Destination_Identity, Result);
      Note ("null: same-key copy with Null_Version_Selector -> "
            & Storage.Status'Image (Result));
      Check (Result = Storage.Success,
             "null: same-key copy of the null generation succeeds");
      Note ("null: current body after restore '"
            & Fetch (Store, Bucket, Key) & "'");
      Check (Fetch (Store, Bucket, Key) = "n0",
             "null: restore republished the null-generation bytes");
   end Null_Restore;

   ------------------------------------------------------------------
   --  3. Same restore over the in-process S3 application.
   ------------------------------------------------------------------

   procedure Wire_Restore is
      Bucket : constant String := "copy-restore";
      Key    : constant String := "k";
      V1 : US.Unbounded_String;
   begin
      Check (Status_Code (Run (Signed_Request ("PUT", "/" & Bucket))) = 200,
             "wire: CreateBucket is 200");
      Check (Status_Code
               (Run (Signed_Request
                  ("PUT", "/" & Bucket, Versioning_Document,
                   Extra_Headers =>
                     "Content-MD5: " & MD5_Base64 (Versioning_Document)
                     & CRLF,
                   Query => [SigV4.Pair ("versioning", "")]))) = 200,
             "wire: PutBucketVersioning is 200");
      declare
         First : constant String :=
           Run (Signed_Request ("PUT", "/" & Bucket & "/" & Key, "v1"));
      begin
         Check (Status_Code (First) = 200, "wire: first PUT is 200");
         V1 := US.To_Unbounded_String (Header_Value (First, "x-amz-version-id"));
         Note ("wire: v1 version id " & US.To_String (V1));
      end;
      declare
         Second : constant String :=
           Run (Signed_Request ("PUT", "/" & Bucket & "/" & Key, "v2"));
      begin
         Check (Status_Code (Second) = 200, "wire: second PUT is 200");
         Note ("wire: v2 version id "
               & Header_Value (Second, "x-amz-version-id"));
      end;
      declare
         Current : constant String :=
           Run (Signed_Request ("GET", "/" & Bucket & "/" & Key));
      begin
         Check (Body_Of (Current) = "v2", "wire: current body is v2");
      end;

      --  Control: unselected same-key copy stays a 400 InvalidRequest.
      declare
         Plain : constant String := Run
           (Signed_Request
              ("PUT", "/" & Bucket & "/" & Key,
               Extra_Headers =>
                 "x-amz-copy-source: /" & Bucket & "/" & Key & CRLF));
      begin
         Note ("control: wire same-key copy without versionId -> "
               & Image (Status_Code (Plain)));
         Check (Status_Code (Plain) = 400,
                "control: wire unselected same-key copy is still 400");
      end;

      --  Under test: restore v1 through x-amz-copy-source ?versionId=.
      declare
         Restore : constant String := Run
           (Signed_Request
              ("PUT", "/" & Bucket & "/" & Key,
               Extra_Headers =>
                 "x-amz-copy-source: /" & Bucket & "/" & Key
                 & "?versionId=" & US.To_String (V1) & CRLF));
      begin
         Note ("wire: CopyObject /" & Bucket & "/" & Key & "?versionId="
               & US.To_String (V1) & " -> " & Image (Status_Code (Restore)));
         Note ("wire: response body " & Escape (Body_Of (Restore)));
         Check (Status_Code (Restore) = 200,
                "wire: versioned same-key CopyObject is 200");
         Check (Header_Value (Restore, "x-amz-copy-source-version-id") =
                  US.To_String (V1),
                "wire: response names the selected source generation");
      end;
      declare
         After : constant String :=
           Run (Signed_Request ("GET", "/" & Bucket & "/" & Key));
      begin
         Note ("wire: current body after restore '" & Body_Of (After) & "'");
         Check (Body_Of (After) = "v1",
                "wire: restore republished the v1 bytes as current");
      end;
   end Wire_Restore;

begin
   Exact_Restore;
   Null_Restore;
   Wire_Restore;
   Finish;
end Repro_Backend_Memory_2;
