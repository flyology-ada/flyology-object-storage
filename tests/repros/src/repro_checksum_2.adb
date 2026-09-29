--  CHECKSUM-2: operations the pinned model marks
--  httpChecksum.requestChecksumRequired = true reject a stock SDK's default
--  request, because the server demands Content-MD5 and never accepts the
--  x-amz-checksum-<alg> group that modern SDKs send instead.
--
--  Since botocore 1.36 the default request_checksum_calculation is
--  "when_supported", so boto3 satisfies requestChecksumRequired with
--    x-amz-sdk-checksum-algorithm: CRC32
--    x-amz-checksum-crc32: <base64 CRC32 of the body>
--  and sends NO Content-MD5 at all.  Observed on the wire against
--  tests/bin/s3_memory_server with boto3/botocore 1.43.89; see
--  tests/repros/python/checksum_boto3_probe.py.
--
--  The server's preflight requires exactly one valid Content-MD5
--  (PutBucketVersioning: src/flyology-object_storage-server-s3_applications.adb
--  :10352-10370; PutBucketTagging: 8013-8019) before it ever reaches
--  Verify_Document_Checksum (5033-5140), which does understand the checksum
--  group.  So a stock boto3 client cannot call these operations at all.
--
--  Asserted (correct) behaviour: a request carrying a valid checksum group and
--  no Content-MD5 is accepted.  Current sources answer 400 InvalidRequest.
--  Controls below send the same bodies with a legacy Content-MD5 and must be
--  accepted, so the failure is isolated to the integrity-header choice.
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Checksum_2 is
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Policy renames Flyology.Object_Storage.S3.Checksum_Policy;

   Bucket : constant String := "checksum2-bucket";

   Versioning_Body : constant String :=
     "<VersioningConfiguration xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"
     & """><Status>Enabled</Status></VersioningConfiguration>";
   Tagging_Body : constant String :=
     "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<TagSet><Tag><Key>team</Key><Value>one</Value></Tag></TagSet></Tagging>";

   function Digest_Base64
     (Algorithm : Policy.Algorithm; Value : String) return String
   is (Checksums.Encode_Base64
         (Checksums.Compute
            (Algorithm,
             Flyology.Bytes.To_Array
               (Flyology.Bytes.From_Byte_String (Value)))));

   function MD5_Header (Value : String) return String is
     ("Content-MD5: " & Digest_Base64 (Policy.Core.MD5, Value) & CRLF);

   --  Exactly the two integrity headers boto3 1.43.89 puts on the wire.
   function Stock_Headers (Value : String) return String is
     ("x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
      "x-amz-checksum-crc32: " & Digest_Base64 (Policy.Core.CRC32, Value) &
      CRLF);
begin
   declare
      Created : constant String := Run (Signed_Request ("PUT", "/" & Bucket));
   begin
      Check (Status_Code (Created) = 200, "control: CreateBucket is 200");
   end;

   --  PutBucketVersioning, legacy Content-MD5 form (control).
   declare
      Legacy : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket, Versioning_Body,
            Extra_Headers => MD5_Header (Versioning_Body),
            Query => [1 => SigV4.Pair ("versioning", "")]));
   begin
      Note ("PutBucketVersioning with Content-MD5: status " &
            Image (Status_Code (Legacy)));
      Check (Status_Code (Legacy) = 200,
             "control: PutBucketVersioning with Content-MD5 is accepted");
   end;

   --  PutBucketVersioning exactly as stock boto3 sends it.
   declare
      Stock : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket, Versioning_Body,
            Extra_Headers => Stock_Headers (Versioning_Body),
            Query => [1 => SigV4.Pair ("versioning", "")]));
   begin
      Note ("PutBucketVersioning, boto3 default headers: status " &
            Image (Status_Code (Stock)));
      Note ("body: " & Escape (Body_Of (Stock)));
      Check (Status_Code (Stock) = 200,
             "stock boto3 PutBucketVersioning (CRC32, no Content-MD5) " &
             "is accepted");
   end;

   --  PutBucketTagging, legacy Content-MD5 form (control).
   declare
      Legacy : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket, Tagging_Body,
            Extra_Headers => MD5_Header (Tagging_Body),
            Query => [1 => SigV4.Pair ("tagging", "")]));
   begin
      Note ("PutBucketTagging with Content-MD5: status " &
            Image (Status_Code (Legacy)));
      Check (Status_Code (Legacy) = 200,
             "control: PutBucketTagging with Content-MD5 is accepted");
   end;

   --  PutBucketTagging exactly as stock boto3 sends it.
   declare
      Stock : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket, Tagging_Body,
            Extra_Headers => Stock_Headers (Tagging_Body),
            Query => [1 => SigV4.Pair ("tagging", "")]));
   begin
      Note ("PutBucketTagging, boto3 default headers: status " &
            Image (Status_Code (Stock)));
      Note ("body: " & Escape (Body_Of (Stock)));
      Check (Status_Code (Stock) = 200,
             "stock boto3 PutBucketTagging (CRC32, no Content-MD5) " &
             "is accepted");
   end;

   Finish;
end Repro_Checksum_2;
