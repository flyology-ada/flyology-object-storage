--  Exploration probe for the SERVER discovery observations (a)-(e).  Not an
--  assertion program: it prints what the application actually answers so the
--  verifier can decide which observations are findings.  It always exits 0.
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Server_Probe is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   function Index_Of (Haystack, Needle : String) return Natural is
     (Ada.Strings.Fixed.Index (Haystack, Needle));

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   procedure Show (Label : String; Response : String) is
   begin
      Note (Label);
      Note ("    status=" & Image (Status_Code (Response)) &
            "  Location=[" & Header_Value (Response, "Location") &
            "]  x-amz-version-id=[" &
            Header_Value (Response, "x-amz-version-id") & "]");
      Note ("    body=" & Escape (Body_Of (Response)));
   end Show;

   function Unsigned (Method, Target : String) return String is
     (Method & " " & Target & " HTTP/1.1" & CRLF &
      "Host: " & Host & CRLF & "Content-Length: 0" & CRLF &
      "Connection: close" & CRLF & CRLF);

   Port : Natural;

begin
   Note ("=== fixtures ===");
   Note ("CreateBucket /probe status " &
         Image (Status_Code (Run (Signed_Request ("PUT", "/probe")))));
   Note ("PutObject /probe/k status " &
         Image (Status_Code
                  (Run (Signed_Request ("PUT", "/probe/k", "payload")))));

   ------------------------------------------------------------------
   Note ("");
   Note ("=== (a) pre-authentication classification ===");
   Show ("unauthenticated GET /probe (bucket EXISTS)",
         Run (Unsigned ("GET", "/probe")));
   Show ("unauthenticated GET /absent-bucket (bucket ABSENT)",
         Run (Unsigned ("GET", "/absent-bucket")));
   Show ("unauthenticated HEAD /probe", Run (Unsigned ("HEAD", "/probe")));
   Show ("unauthenticated GET /probe/k (key EXISTS)",
         Run (Unsigned ("GET", "/probe/k")));
   Show ("unauthenticated GET /probe/absent (key ABSENT)",
         Run (Unsigned ("GET", "/probe/absent")));
   Show ("unauthenticated GET /probe?unknown-subresource",
         Run (Unsigned ("GET", "/probe?unknown-subresource")));
   Show ("unauthenticated GET /probe?versioning (implemented)",
         Run (Unsigned ("GET", "/probe?versioning")));
   Show ("unauthenticated GET /probe?accelerate (maybe unimplemented)",
         Run (Unsigned ("GET", "/probe?accelerate")));
   Show ("unauthenticated GET /probe/" & Repeat ('z', 1100) &
         " (key over 1024 bytes)  [target elided]",
         Run (Unsigned ("GET", "/probe/" & Repeat ('z', 1100))));
   Show ("unauthenticated GET //%00 style: /probe/a%00b",
         Run (Unsigned ("GET", "/probe/a%00b")));
   Show ("unauthenticated OPTIONS /probe", Run (Unsigned ("OPTIONS", "/probe")));
   Show ("unauthenticated PATCH /probe/k", Run (Unsigned ("PATCH", "/probe/k")));
   Show ("unauthenticated GET /probe?uploads&unknown=1",
         Run (Unsigned ("GET", "/probe?uploads&unknown=1")));
   Show ("unauthenticated GET /probe?torrent (object-only subresource)",
         Run (Unsigned ("GET", "/probe?torrent")));
   Show ("unauthenticated POST /probe/k?restore",
         Run (Unsigned ("POST", "/probe/k?restore")));

   ------------------------------------------------------------------
   Note ("");
   Note ("=== (b) x-amz-version-id on a never-versioned bucket ===");
   Show ("HEAD /probe/k", Run (Signed_Request ("HEAD", "/probe/k")));
   Show ("GET /probe/k", Run (Signed_Request ("GET", "/probe/k")));
   Show ("GET /probe/k?versionId=null (round-tripping HEAD's value)",
         Run (Signed_Request
                ("GET", "/probe/k",
                 Query => (1 => SigV4.Pair ("versionId", "null")))));
   Show ("HEAD /probe/k?versionId=null",
         Run (Signed_Request
                ("HEAD", "/probe/k",
                 Query => (1 => SigV4.Pair ("versionId", "null")))));

   ------------------------------------------------------------------
   Note ("");
   Note ("=== (c) CompleteMultipartUpload Location ===");
   declare
      Created : constant String :=
        Run (Signed_Request
               ("POST", "/probe/multi",
                Query => (1 => SigV4.Pair ("uploads", ""))));
      Upload  : String (1 .. 512);
      Last    : Natural := 0;
      First   : Natural;
      Stop    : Natural;
   begin
      Note ("CreateMultipartUpload status " & Image (Status_Code (Created)));
      declare
         Doc : constant String := Body_Of (Created);
         Open : constant Natural := Index_Of (Doc, "<UploadId>");
      begin
         if Open = 0 then
            Note ("   no UploadId in " & Escape (Doc));
         else
            First := Open + 10;
            Stop := Index_Of (Doc (First .. Doc'Last), "</UploadId>");
            if Stop = 0 then
               Note ("   unterminated UploadId");
            else
               Last := Stop - First;
               Upload (1 .. Last) := Doc (First .. Stop - 1);
               Note ("   UploadId=" & Upload (1 .. Last));
            end if;
         end if;
      end;
      if Last > 0 then
         declare
            Part : constant String :=
              Run (Signed_Request
                     ("PUT", "/probe/multi", Repeat ('x', 16),
                      Query =>
                        (SigV4.Pair ("partNumber", "1"),
                         SigV4.Pair ("uploadId", Upload (1 .. Last)))));
            ETag : constant String := Header_Value (Part, "ETag");
            Manifest : constant String :=
              "<CompleteMultipartUpload " &
              "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
              "<Part><PartNumber>1</PartNumber><ETag>" & ETag &
              "</ETag></Part></CompleteMultipartUpload>";
         begin
            Note ("   UploadPart status " & Image (Status_Code (Part)) &
                  " ETag=" & ETag);
            Show ("CompleteMultipartUpload",
                  Run (Signed_Request
                         ("POST", "/probe/multi", Manifest,
                          Query =>
                            (1 => SigV4.Pair
                               ("uploadId", Upload (1 .. Last))))));
         end;
      end if;
   end;

   ------------------------------------------------------------------
   Note ("");
   Note ("=== (d) aws-chunked / streaming payload sentinels ===");
   declare
      --  Build an ordinary signed request, then substitute the streaming
      --  sentinel into x-amz-content-sha256.  The server decides the payload
      --  hash is unusable in authentication.adb:139-140, which is evaluated
      --  before any signature verification, so the substitution reaches the
      --  same verdict a correctly signed stock client would.
      function With_Sentinel
        (Base : String; Sentinel : String) return String
      is
         Marker : constant String := "x-amz-content-sha256: ";
         At_Header : constant Natural := Index_Of (Base, Marker);
         Value_First : constant Natural := At_Header + Marker'Length;
         Value_Last : constant Natural :=
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
      Base : constant String :=
        Signed_Request
          ("PUT", "/probe/streamed", "", Extra_Headers => Chunked_Headers);
   begin
      Show ("PutObject, x-amz-content-sha256: " &
            "STREAMING-UNSIGNED-PAYLOAD-TRAILER + Content-Encoding: " &
            "aws-chunked (the aws-cli v2 default over HTTPS)",
            Run (With_Sentinel (Base, "STREAMING-UNSIGNED-PAYLOAD-TRAILER")));
      Show ("PutObject, x-amz-content-sha256: " &
            "STREAMING-AWS4-HMAC-SHA256-PAYLOAD + aws-chunked",
            Run (With_Sentinel
                   (Base, "STREAMING-AWS4-HMAC-SHA256-PAYLOAD")));
      Show ("UploadPart, STREAMING-UNSIGNED-PAYLOAD-TRAILER + aws-chunked",
            Run (With_Sentinel
                   (Signed_Request
                      ("PUT", "/probe/streamed", "",
                       Extra_Headers => Chunked_Headers,
                       Query =>
                         (SigV4.Pair ("partNumber", "1"),
                          SigV4.Pair ("uploadId", "deadbeef"))),
                    "STREAMING-UNSIGNED-PAYLOAD-TRAILER")));
   end;
   Show ("PutObject with aws-chunked and an ORDINARY signed payload hash " &
         "(the documented 501 path)",
         Run (Signed_Request
                ("PUT", "/probe/streamed", "hello",
                 Extra_Headers =>
                   "Content-Encoding: aws-chunked" & CRLF &
                   "x-amz-decoded-content-length: 5" & CRLF &
                   "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
                   "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF)));
   Show ("PutObject with UNSIGNED-PAYLOAD over plain HTTP",
         Run (Signed_Request
                ("PUT", "/probe/unsigned", "hello",
                 Hash_Override => "UNSIGNED-PAYLOAD")));
   Note ("   (Content-MD5 of an empty document, for reference: " &
         MD5_Base64 ("") & ")");

   ------------------------------------------------------------------
   Note ("");
   Note ("=== (e) exception containment ===");
   Start_Loopback (Port);
   Note ("loopback on port " & Image (Port));
   declare
      Full : constant String :=
        Signed_Request ("PUT", "/probe/truncated", "0123456789ABCDEF");
      Head_End : constant Natural := Index_Of (Full, CRLF & CRLF);
      Truncated : constant String :=
        Full (Full'First .. Head_End + 3) & "0123";   --  4 of 16 bytes
      Response : constant String :=
        Exchange_Over_Socket (Port, Truncated, Timeout => 5.0);
   begin
      Note ("truncated body (4 of 16 declared bytes) then close:");
      Note ("    received " & Image (Response'Length) & " bytes, status " &
            Image (Status_Code (Response)));
      Note ("    body=" & Escape (Body_Of (Response)));
   end;
   declare
      Response : constant String := Exchange_Over_Socket
        (Port, Signed_Request ("GET", "/probe/k"), Timeout => 5.0);
   begin
      Note ("CONTROL after the truncated request, listener still serves: " &
            "status " & Image (Status_Code (Response)) &
            " body=" & Escape (Body_Of (Response)));
   end;
   declare
      --  Content-Length larger than the bytes actually present, in process.
      Full : constant String :=
        Signed_Request ("PUT", "/probe/short", "0123456789ABCDEF");
      Head_End : constant Natural := Index_Of (Full, CRLF & CRLF);
      Short : constant String :=
        Full (Full'First .. Head_End + 3) & "0123";
   begin
      Show ("in-process: Content-Length 16 but only 4 body bytes present",
            Run (Short));
   end;
   Stop_Loopback;

   Ada.Text_IO.Put_Line ("PROBE COMPLETE");
exception
   when E : others =>
      Ada.Text_IO.Put_Line
        ("PROBE RAISED " & Ada.Exceptions.Exception_Name (E) & ": " &
         Ada.Exceptions.Exception_Message (E));
end Repro_Server_Probe;
