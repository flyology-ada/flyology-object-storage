--  SERVER-1: the pinned model satisfies `requestChecksumRequired: true` with
--  the flexible checksum named by `requestAlgorithmMember`
--  (`x-amz-sdk-checksum-algorithm` + `x-amz-checksum-<alg>`), and for
--  DeleteObjects the input shape has no ContentMD5 member at all.  The server
--  nevertheless demands a Content-MD5 header on DeleteObjects,
--  PutBucketVersioning and PutObjectTagging, so a model-driven client that
--  sends only the flexible checksum is rejected.
--
--  This program asserts the model-conformant behaviour: a correct
--  x-amz-checksum-crc32 with x-amz-sdk-checksum-algorithm: CRC32 and no
--  Content-MD5 must be accepted (200).  Every assertion has a Content-MD5
--  control that must pass on the current sources, so the output shows the
--  harness works.
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Server_1 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;

   function Bytes_Of (Value : String) return Ada.Streams.Stream_Element_Array
   is (Flyology.Bytes.To_Array (Flyology.Bytes.From_Byte_String (Value)));

   function CRC32_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute (Core.CRC32, Bytes_Of (Value))));

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute (Core.MD5, Bytes_Of (Value))));

   function Flexible_Checksum_Headers (Payload : String) return String is
     ("x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
      "x-amz-checksum-crc32: " & CRC32_Base64 (Payload) & CRLF);

   function MD5_Headers (Payload : String) return String is
     ("Content-MD5: " & MD5_Base64 (Payload) & CRLF);

   function Delete_Document (Key : String) return String is
     ("<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<Object><Key>" & Key & "</Key></Object>" &
      "</Delete>");

   Versioning_Document : constant String :=
     "<VersioningConfiguration " &
     "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Status>Enabled</Status></VersioningConfiguration>";

   Tagging_Document : constant String :=
     "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag>" &
     "</TagSet></Tagging>";

   Delete_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("delete", ""));
   Versioning_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("versioning", ""));
   Tagging_Query : constant SigV4.Name_Value_Array :=
     (1 => SigV4.Pair ("tagging", ""));

   procedure Report (Label : String; Response : String) is
   begin
      Note (Label & ": status " & Image (Status_Code (Response)) &
            "  body " & Escape (Body_Of (Response)));
   end Report;

begin
   --  Fixtures.
   Check (Status_Code (Run (Signed_Request ("PUT", "/md5-bucket"))) = 200,
          "fixture: CreateBucket /md5-bucket");
   Check (Status_Code (Run (Signed_Request ("PUT", "/md5-control"))) = 200,
          "fixture: CreateBucket /md5-control");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/md5-bucket/modelled", "payload"))) = 200,
          "fixture: PutObject /md5-bucket/modelled");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/md5-bucket/control", "payload"))) = 200,
          "fixture: PutObject /md5-bucket/control");

   ------------------------------------------------------------------
   --  DeleteObjects: the model has no ContentMD5 member at all.
   ------------------------------------------------------------------
   declare
      Payload : constant String := Delete_Document ("modelled");
      Response : constant String :=
        Run (Signed_Request
               ("POST", "/md5-bucket", Payload,
                Extra_Headers => Flexible_Checksum_Headers (Payload),
                Query         => Delete_Query));
   begin
      Note ("DeleteObjects flexible checksum headers: " &
            Escape (Flexible_Checksum_Headers (Payload)));
      Report ("DeleteObjects CRC32 only, no Content-MD5", Response);
      Check (Status_Code (Response) = 200,
             "DeleteObjects with a valid x-amz-checksum-crc32 and " &
             "x-amz-sdk-checksum-algorithm: CRC32 and no Content-MD5 is 200");
      Check (Contains (Body_Of (Response), "<Key>modelled</Key>"),
             "DeleteObjects CRC32-only response reports the deleted key");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request ("GET", "/md5-bucket/modelled"));
   begin
      Report ("GET /md5-bucket/modelled after the CRC32-only batch", Response);
      Check (Status_Code (Response) = 404,
             "the CRC32-only DeleteObjects actually removed the key");
   end;

   --  Control: the same batch with Content-MD5 must succeed today.
   declare
      Payload : constant String := Delete_Document ("control");
      Response : constant String :=
        Run (Signed_Request
               ("POST", "/md5-bucket", Payload,
                Extra_Headers => MD5_Headers (Payload),
                Query         => Delete_Query));
   begin
      Report ("CONTROL DeleteObjects with Content-MD5", Response);
      Check (Status_Code (Response) = 200,
             "CONTROL: DeleteObjects with Content-MD5 is 200");
   end;

   ------------------------------------------------------------------
   --  PutBucketVersioning: ContentMD5 is an optional member.
   ------------------------------------------------------------------
   declare
      Response : constant String :=
        Run (Signed_Request
               ("PUT", "/md5-bucket", Versioning_Document,
                Extra_Headers =>
                  Flexible_Checksum_Headers (Versioning_Document),
                Query         => Versioning_Query));
   begin
      Report ("PutBucketVersioning CRC32 only, no Content-MD5", Response);
      Check (Status_Code (Response) = 200,
             "PutBucketVersioning with a valid flexible checksum and no " &
             "Content-MD5 is 200");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request
               ("PUT", "/md5-control", Versioning_Document,
                Extra_Headers => MD5_Headers (Versioning_Document),
                Query         => Versioning_Query));
   begin
      Report ("CONTROL PutBucketVersioning with Content-MD5", Response);
      Check (Status_Code (Response) = 200,
             "CONTROL: PutBucketVersioning with Content-MD5 is 200");
   end;

   ------------------------------------------------------------------
   --  PutObjectTagging: ContentMD5 is an optional member; the flexible
   --  checksum is answered with 501 rather than accepted.
   ------------------------------------------------------------------
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/md5-control/tagged", "payload"))) = 200,
          "fixture: PutObject /md5-control/tagged");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", "/md5-control/tagged-control", "payload"))) = 200,
          "fixture: PutObject /md5-control/tagged-control");
   declare
      Response : constant String :=
        Run (Signed_Request
               ("PUT", "/md5-control/tagged", Tagging_Document,
                Extra_Headers => Flexible_Checksum_Headers (Tagging_Document),
                Query         => Tagging_Query));
   begin
      Report ("PutObjectTagging CRC32 only, no Content-MD5", Response);
      Check (Status_Code (Response) = 200,
             "PutObjectTagging with a valid flexible checksum and no " &
             "Content-MD5 is 200");
   end;
   declare
      Response : constant String :=
        Run (Signed_Request
               ("PUT", "/md5-control/tagged-control", Tagging_Document,
                Extra_Headers => MD5_Headers (Tagging_Document),
                Query         => Tagging_Query));
   begin
      Report ("CONTROL PutObjectTagging with Content-MD5", Response);
      Check (Status_Code (Response) = 200,
             "CONTROL: PutObjectTagging with Content-MD5 is 200");
   end;

   Finish;
end Repro_Server_1;
