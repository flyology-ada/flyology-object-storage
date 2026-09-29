--  SERVER-3: HeadObject and GetObject disagree about x-amz-version-id for the
--  same object.  HeadObject's Set_Common_Headers
--  (s3_applications.adb:16619-16622) ALWAYS emits the header, substituting the
--  literal "null" when the object has no version; GetObject's
--  Response_IO.Begin_Object (:4189-4194) emits it only when a version exists
--  or when the request selected one.  The two reads of one object therefore
--  report different version metadata.
--
--  This program asserts the invariant that does not depend on which of the two
--  is right: GET and HEAD of the same object must report the same
--  x-amz-version-id.  Controls: a versioned object where both agree, and the
--  explicit ?versionId=null selection where both emit "null".
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;

procedure Repro_Server_3 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   Versioning_Document : constant String :=
     "<VersioningConfiguration " &
     "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Status>Enabled</Status></VersioningConfiguration>";

begin
   Check (Status_Code (Run (Signed_Request ("PUT", "/plain-bucket"))) = 200,
          "fixture: CreateBucket /plain-bucket (never versioned)");
   declare
      Put : constant String :=
        Run (Signed_Request ("PUT", "/plain-bucket/k", "payload"));
   begin
      Check (Status_Code (Put) = 200, "fixture: PutObject /plain-bucket/k");
      --  docs/compatibility/s3.md:446-450 states the crate's own rule:
      --  "The server omits the header for unversioned publication ... and
      --  emits x-amz-version-id: null for suspended ... publication."
      Note ("PutObject on the never-versioned bucket: x-amz-version-id " &
            "header count " &
            Image (Header_Count (Put, "x-amz-version-id")) & " value [" &
            Header_Value (Put, "x-amz-version-id") & "]");
      Check (Header_Count (Put, "x-amz-version-id") = 0,
             "CONTROL: PutObject omits x-amz-version-id for unversioned " &
             "publication, as docs/compatibility/s3.md:446-450 states");
   end;
   Check (Status_Code (Run (Signed_Request ("PUT", "/versioned-bucket"))) = 200,
          "fixture: CreateBucket /versioned-bucket");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/versioned-bucket", Versioning_Document,
                     Extra_Headers =>
                       "Content-MD5: " & MD5_Base64 (Versioning_Document) &
                       CRLF,
                     Query =>
                       (1 => SigV4.Pair ("versioning", ""))))) = 200,
          "fixture: PutBucketVersioning Enabled");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/versioned-bucket/k", "payload"))) = 200,
          "fixture: PutObject /versioned-bucket/k");

   --  The finding: a never-versioned bucket.
   declare
      Got  : constant String := Run (Signed_Request ("GET", "/plain-bucket/k"));
      Head : constant String := Run (Signed_Request ("HEAD", "/plain-bucket/k"));
      G    : constant String := Header_Value (Got, "x-amz-version-id");
      H    : constant String := Header_Value (Head, "x-amz-version-id");
   begin
      Note ("never-versioned bucket: GET status " & Image (Status_Code (Got)) &
            " x-amz-version-id=[" & G & "] (header count " &
            Image (Header_Count (Got, "x-amz-version-id")) & ")");
      Note ("never-versioned bucket: HEAD status " &
            Image (Status_Code (Head)) & " x-amz-version-id=[" & H &
            "] (header count " &
            Image (Header_Count (Head, "x-amz-version-id")) & ")");
      Check (Status_Code (Got) = 200 and then Status_Code (Head) = 200,
             "CONTROL: both reads of the unversioned object are 200");
      Check (G = H,
             "GET and HEAD report the same x-amz-version-id for the same " &
             "unversioned object");
      Check (Header_Count (Head, "x-amz-version-id") = 0,
             "HEAD of an object in a never-versioned bucket omits " &
             "x-amz-version-id, as GetObject already does");
   end;

   --  Controls that must pass today.
   declare
      Got  : constant String :=
        Run (Signed_Request ("GET", "/versioned-bucket/k"));
      Head : constant String :=
        Run (Signed_Request ("HEAD", "/versioned-bucket/k"));
      G    : constant String := Header_Value (Got, "x-amz-version-id");
      H    : constant String := Header_Value (Head, "x-amz-version-id");
   begin
      Note ("CONTROL versioned bucket: GET x-amz-version-id=[" & G &
            "]  HEAD x-amz-version-id=[" & H & "]");
      Check (G /= "" and then G = H,
             "CONTROL: in a versioned bucket GET and HEAD agree on a real " &
             "version id");
   end;
   declare
      Got  : constant String :=
        Run (Signed_Request
               ("GET", "/plain-bucket/k",
                Query => (1 => SigV4.Pair ("versionId", "null"))));
      Head : constant String :=
        Run (Signed_Request
               ("HEAD", "/plain-bucket/k",
                Query => (1 => SigV4.Pair ("versionId", "null"))));
   begin
      Note ("CONTROL explicit ?versionId=null: GET x-amz-version-id=[" &
            Header_Value (Got, "x-amz-version-id") &
            "]  HEAD x-amz-version-id=[" &
            Header_Value (Head, "x-amz-version-id") & "]");
      Check (Header_Value (Got, "x-amz-version-id") = "null"
               and then Header_Value (Head, "x-amz-version-id") = "null",
             "CONTROL: an explicit versionId=null selection reports null " &
             "on both reads");
   end;

   Finish;
end Repro_Server_3;
