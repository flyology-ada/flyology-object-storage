--  S3-DOMAIN-B-2: Tagging.Parse_Bucket rejects a namespace-free <Tagging>
--  document, so PutBucketTagging answers 400 MalformedXML for the body that
--  minio-go (mc tag set alias/bucket) sends, while PutObjectTagging accepts
--  the identical document and Parse_Bucket_Response decodes it.  The body
--  below was captured off the wire from mc RELEASE.2025-08-13T08-35-41Z.
--  This program asserts the AWS/MinIO behaviour and the internal consistency
--  of the two request paths.
with Ada.Containers;
with Ada.Exceptions;
with Flyology.Bytes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.Tags;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_B_2 is

   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Tagging renames Flyology.Object_Storage.S3.Tagging;
   package Tags renames Flyology.Object_Storage.Tags;

   use type Ada.Containers.Count_Type;

   function MD5_Base64 (Value : String) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Core.MD5,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Value)))));

   Tagging_Query : constant SigV4.Name_Value_Array (1 .. 1) :=
     [SigV4.Pair ("tagging", "")];

   Bucket : constant String := "/domain-b2";

   --  Captured from mc RELEASE.2025-08-13T08-35-41Z (minio-go v7.0.90),
   --  `mc tag set repro/probe-mc team=storage`.
   MC_Body : constant String :=
     "<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value>" &
     "</Tag></TagSet></Tagging>";
   --  Captured from boto3 1.43.89 / aws-cli 2.36.34 / s3cmd 2.4.0.
   SDK_Body : constant String :=
     "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet>" &
     "</Tagging>";

   function Tagging_Request (Target, Document : String) return String is
     (Signed_Request
        ("PUT", Target, Document,
         "Content-MD5: " & MD5_Base64 (Document) & CRLF &
         "Content-Type: application/xml" & CRLF,
         Tagging_Query));

   procedure Exchange (Label, Target, Document : String) is
      Response : constant String := Run (Tagging_Request (Target, Document));
   begin
      Note (Label);
      Note ("    PUT " & Target & "?tagging body=" & Document);
      Note ("    status=" & Image (Status_Code (Response)) &
            " body=" & Escape (Body_Of (Response)));
      Check (Status_Code (Response) = 200, Label & " is answered 200");
   end Exchange;

begin
   Note ("=== fixtures ===");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket))) = 200,
          "CreateBucket " & Bucket & " is 200");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket & "/k", "x")))
            = 200,
          "PutObject k is 200");

   Note ("");
   Note ("=== unit level: the two bucket entry points on one document ===");
   declare
      Decoded : Tags.Tag_Set;
   begin
      Decoded := Tagging.Parse_Bucket_Response (MC_Body);
      Note ("Parse_Bucket_Response accepted it, tags=" &
            Image (Integer (Decoded.Length)));
      Check (Decoded.Length = 1,
             "control: Parse_Bucket_Response decodes the mc document");
   exception
      when Error : others =>
         Note ("Parse_Bucket_Response raised " &
               Ada.Exceptions.Exception_Name (Error) & ": " &
               Ada.Exceptions.Exception_Message (Error));
         Check (False,
                "control: Parse_Bucket_Response decodes the mc document");
   end;
   declare
      Decoded : Tags.Tag_Set;
   begin
      Decoded := Tagging.Parse_Bucket (MC_Body);
      Note ("Parse_Bucket accepted it, tags=" &
            Image (Integer (Decoded.Length)));
      Check (Decoded.Length = 1,
             "Tagging.Parse_Bucket accepts a namespace-free <Tagging>");
   exception
      when Error : others =>
         Note ("Parse_Bucket raised " &
               Ada.Exceptions.Exception_Name (Error) & ": " &
               Ada.Exceptions.Exception_Message (Error));
         Check (False,
                "Tagging.Parse_Bucket accepts a namespace-free <Tagging>");
   end;

   Note ("");
   Note ("=== server: the same document on both tagging paths ===");
   Exchange ("PutObjectTagging, mc document (accepted today)",
             Bucket & "/k", MC_Body);
   Exchange ("PutBucketTagging, mc document                 ",
             Bucket, MC_Body);

   Note ("");
   Note ("=== control: PutBucketTagging with xmlns (passes today) ===");
   Exchange ("PutBucketTagging, boto3/aws-cli document      ",
             Bucket, SDK_Body);

   Finish;
end Repro_S3_Domain_B_2;
