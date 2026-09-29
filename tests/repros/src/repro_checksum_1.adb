--  CHECKSUM-1: PutObject answers 400 InvalidRequest where the pinned botocore
--  model documents BadDigest for an x-amz-sdk-checksum-algorithm /
--  x-amz-checksum-<alg> algorithm mismatch.
--
--  review/baseline/service-2.json, shape PutObjectRequest, member
--  ChecksumAlgorithm (header x-amz-sdk-checksum-algorithm), documentation:
--  "If the individual checksum value you provide through
--   x-amz-checksum-algorithm doesn't match the checksum algorithm you set
--   through x-amz-sdk-checksum-algorithm, Amazon S3 fails the request with a
--   BadDigest error."
--
--  The request below is otherwise well formed: the CRC32 value header carries
--  the true canonical CRC32 of the body (computed here with the crate's own
--  Flyology.Object_Storage.S3.Checksums API), the payload hash is correct, and
--  only the SDK selector names a different algorithm (SHA256).
--
--  Asserted (correct) behaviour: 400 with <Code>BadDigest</Code>.
--  Current sources answer 400 <Code>InvalidRequest</Code>
--  (src/flyology-object_storage-server-s3_applications.adb:14809-14821), which
--  tests/src/s3_server_application_corpus.adb:6428 pins.
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Checksum_1 is
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Policy renames Flyology.Object_Storage.S3.Checksum_Policy;

   Bucket : constant String := "checksum1-bucket";
   Key    : constant String := "mismatch-key";
   Body_Text : constant String := "bad";

   function Canonical_CRC32 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Policy.Core.CRC32,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   CRC32_Value : constant String := Canonical_CRC32 (Body_Text);
begin
   Note ("canonical CRC32 of """ & Body_Text & """ = " & CRC32_Value);

   declare
      Created : constant String := Run (Signed_Request ("PUT", "/" & Bucket));
   begin
      Note ("CreateBucket status " & Image (Status_Code (Created)));
      Check (Status_Code (Created) = 200, "control: CreateBucket is 200");
   end;

   --  Control 1: the same CRC32 value header with a matching SDK selector is
   --  accepted, so the request shape and the computed value are valid.
   declare
      Matching : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket & "/" & Key & "-ok", Body_Text,
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
              "x-amz-checksum-crc32: " & CRC32_Value & CRLF));
   begin
      Note ("matching selector status " & Image (Status_Code (Matching)));
      Check (Status_Code (Matching) = 200,
             "control: matching sdk-algorithm/value header is accepted");
   end;

   --  Control 2: a value header that is well formed but does not match the
   --  body is answered BadDigest, so the server does emit that code.
   declare
      Wrong_Value : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket & "/" & Key & "-wrong", Body_Text,
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
              "x-amz-checksum-crc32: " & Canonical_CRC32 ("other") & CRLF));
   begin
      Note ("value/content mismatch status " &
            Image (Status_Code (Wrong_Value)));
      Note ("value/content mismatch body: " &
            Escape (Body_Of (Wrong_Value)));
      Check (Contains (Body_Of (Wrong_Value), "<Code>BadDigest</Code>"),
             "control: a value/content mismatch is answered BadDigest");
   end;

   --  The finding: SDK selector SHA256, value header x-amz-checksum-crc32
   --  carrying the true CRC32 of the body.
   declare
      Mismatch : constant String := Run
        (Signed_Request
           ("PUT", "/" & Bucket & "/" & Key, Body_Text,
            Extra_Headers =>
              "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
              "x-amz-checksum-crc32: " & CRC32_Value & CRLF));
   begin
      Note ("algorithm-name mismatch status " &
            Image (Status_Code (Mismatch)));
      Note ("algorithm-name mismatch body: " & Escape (Body_Of (Mismatch)));
      Check (Status_Code (Mismatch) = 400,
             "algorithm-name mismatch is a 400");
      Check (Contains (Body_Of (Mismatch), "<Code>BadDigest</Code>"),
             "model documents BadDigest for an sdk-algorithm/value mismatch");
      Check (not Contains (Body_Of (Mismatch), "<Code>InvalidRequest</Code>"),
             "algorithm-name mismatch is not answered InvalidRequest");
   end;

   Finish;
end Repro_Checksum_1;
