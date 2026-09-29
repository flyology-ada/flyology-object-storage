--  SERVER-5: an unsupported streaming payload sentinel is reported as
--  "AuthorizationHeaderMalformed" instead of "NotImplemented".
--
--  `Verify_Request` (server-authentication.adb:139-140) folds "the payload
--  hash is neither UNSIGNED-PAYLOAD nor 64 hex digits" into the same
--  Malformed_Credentials verdict it uses for a broken Authorization header,
--  and `Send_Authentication_Error` (s3_applications.adb:1889-1892) maps that
--  to `400 AuthorizationHeaderMalformed / "The authorization header is
--  malformed"`.  Since AWS enabled default integrity protection, aws-cli v2
--  and boto3 send `x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER`
--  with `Content-Encoding: aws-chunked` for PutObject and UploadPart over
--  HTTPS (captured from aws-cli/2.36.34 for this review), so an operator who
--  puts this server behind a TLS terminator is told their credentials are
--  malformed when the real cause is an unimplemented payload encoding, which
--  the server already reports correctly on the neighbouring path.
--
--  This program asserts the diagnostic the server itself uses for the same
--  situation with an ordinary payload hash: 501 NotImplemented.  Controls:
--  the aws-chunked route with an ordinary hash is 501, and an ordinary
--  PutObject still succeeds.
with Ada.Strings.Fixed;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Server_5 is

   function Index_Of (Haystack, Needle : String) return Natural is
     (Ada.Strings.Fixed.Index (Haystack, Needle));

   --  Build an ordinary signed request, then substitute the streaming
   --  sentinel into x-amz-content-sha256.  The payload-hash shape is rejected
   --  at server-authentication.adb:139-140, which is evaluated before any
   --  signature verification, so this reaches exactly the verdict a correctly
   --  signed stock client reaches.
   function With_Sentinel (Base, Sentinel : String) return String is
      Marker      : constant String := "x-amz-content-sha256: ";
      At_Header   : constant Natural := Index_Of (Base, Marker);
      Value_First : constant Natural := At_Header + Marker'Length;
      Value_Last  : constant Natural :=
        Index_Of (Base (Value_First .. Base'Last), CRLF) - 1;
   begin
      return Base (Base'First .. Value_First - 1) & Sentinel &
        Base (Value_Last + 1 .. Base'Last);
   end With_Sentinel;

   Chunked_Headers : constant String :=
     "Content-Encoding: aws-chunked" & CRLF &
     "x-amz-decoded-content-length: 15" & CRLF &
     "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
     "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF;

begin
   Check (Status_Code (Run (Signed_Request ("PUT", "/stream-bucket"))) = 200,
          "fixture: CreateBucket /stream-bucket");

   declare
      Base : constant String :=
        Signed_Request
          ("PUT", "/stream-bucket/o", "", Extra_Headers => Chunked_Headers);
      Response : constant String :=
        Run (With_Sentinel (Base, "STREAMING-UNSIGNED-PAYLOAD-TRAILER"));
   begin
      Note ("PutObject with STREAMING-UNSIGNED-PAYLOAD-TRAILER + " &
            "aws-chunked: status " & Image (Status_Code (Response)));
      Note ("   body " & Escape (Body_Of (Response)));
      Check (not Contains (Body_Of (Response),
                           "<Code>AuthorizationHeaderMalformed</Code>"),
             "an unimplemented streaming payload encoding is not reported " &
             "as a malformed authorization header");
      Check (Status_Code (Response) = 501
               and then Contains (Body_Of (Response),
                                  "<Code>NotImplemented</Code>"),
             "PutObject with STREAMING-UNSIGNED-PAYLOAD-TRAILER is " &
             "501 NotImplemented, like the aws-chunked path it belongs to");
   end;

   declare
      Base : constant String :=
        Signed_Request
          ("PUT", "/stream-bucket/o", "",
           Extra_Headers => Chunked_Headers,
           Query =>
             (SigV4.Pair ("partNumber", "1"),
              SigV4.Pair ("uploadId", "0123456789abcdef")));
      Response : constant String :=
        Run (With_Sentinel (Base, "STREAMING-UNSIGNED-PAYLOAD-TRAILER"));
   begin
      Note ("UploadPart with STREAMING-UNSIGNED-PAYLOAD-TRAILER + " &
            "aws-chunked: status " & Image (Status_Code (Response)));
      Note ("   body " & Escape (Body_Of (Response)));
      Check (not Contains (Body_Of (Response),
                           "<Code>AuthorizationHeaderMalformed</Code>"),
             "UploadPart does not report the streaming sentinel as a " &
             "malformed authorization header");
   end;

   --  Controls: the server already answers the same situation correctly when
   --  the payload hash has an ordinary shape.
   declare
      Response : constant String :=
        Run (Signed_Request
               ("PUT", "/stream-bucket/o", "hello",
                Extra_Headers =>
                  "Content-Encoding: aws-chunked" & CRLF &
                  "x-amz-decoded-content-length: 5" & CRLF &
                  "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
                  "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF));
   begin
      Note ("CONTROL aws-chunked with an ordinary signed payload hash: " &
            "status " & Image (Status_Code (Response)) & " body " &
            Escape (Body_Of (Response)));
      Check (Status_Code (Response) = 501
               and then Contains (Body_Of (Response),
                                  "aws-chunked payloads are not implemented"),
             "CONTROL: aws-chunked with an ordinary hash is 501 " &
             "NotImplemented");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request ("PUT", "/stream-bucket/plain", "hello"));
   begin
      Check (Status_Code (Response) = 200,
             "CONTROL: an ordinary PutObject still succeeds");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request ("PUT", "/stream-bucket/bad", "hello",
                             Hash_Override =>
                               "0000000000000000000000000000000000" &
                               "000000000000000000000000000000"));
   begin
      Note ("CONTROL a genuinely wrong (but well-shaped) payload hash: " &
            "status " & Image (Status_Code (Response)) & " body " &
            Escape (Body_Of (Response)));
      Check (Status_Code (Response) in 400 | 403,
             "CONTROL: a wrong payload hash is still rejected");
   end;

   Finish;
end Repro_Server_5;
