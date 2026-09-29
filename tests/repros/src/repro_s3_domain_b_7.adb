--  S3-DOMAIN-B-7: Attributes.Validate infers "this object is multipart" from
--  the mere presence of the <ObjectParts> container and then applies the
--  narrow multipart checksum policy (Policy.Supported, CRC only) instead of
--  the ordinary-object policy the same package documents
--  (Checksum_Policy.Ordinary_Object_Supported, any algorithm as one
--  full-object digest).  A single-PUT object whose server also reports the
--  parts container is therefore rejected with Malformed_Attributes and the
--  client reports Invalid_Response.
--
--  The Checksum and ObjectParts elements below are the bytes MinIO
--  RELEASE.2025-09-07T16-13-09Z actually returns for a one-PUT object stored
--  with x-amz-checksum-sha256 (captured against the image pinned in
--  tests/scripts/test-minio.sh), re-rooted under the AWS response root that
--  this decoder requires.
with Ada.Exceptions;
with Flyology.Bytes;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_S3_Domain_B_7 is

   package Attributes renames Flyology.Object_Storage.S3.Attributes;
   package Checksums renames Flyology.Object_Storage.S3.Checksums;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;

   Payload : constant String := "hello world";

   function Digest (Algorithm : Core.Checksum_Algorithm) return String is
     (Checksums.Encode_Base64
        (Checksums.Compute
           (Algorithm,
            Flyology.Bytes.To_Array
              (Flyology.Bytes.From_Byte_String (Payload)))));

   --  What MinIO returns for the parts container of a one-PUT object, with
   --  its <MaxParts>10000</MaxParts> lowered to 1000 so that only the
   --  checksum rule is exercised here; the 10000 echo is S3-DOMAIN-B-8.
   Object_Parts : constant String :=
     "<ObjectParts><IsTruncated>false</IsTruncated>" &
     "<MaxParts>1000</MaxParts>" &
     "<NextPartNumberMarker>1</NextPartNumberMarker>" &
     "<PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount>" &
     "<Part><PartNumber>1</PartNumber><Size>11</Size></Part></ObjectParts>";

   function Response_Body
     (Checksum : String; With_Parts : Boolean := True) return String
   is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<GetObjectAttributesResponse " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<ETag>""5eb63bbbe01eeed093cb22bb8f5acdc3""</ETag>" &
      "<Checksum>" & Checksum & "</Checksum>" &
      (if With_Parts then Object_Parts else "") &
      "<StorageClass>STANDARD</StorageClass>" &
      "<ObjectSize>11</ObjectSize>" &
      "</GetObjectAttributesResponse>");

   procedure Decode (Label, Document : String; Must_Work : Boolean) is
   begin
      Note (Label);
      begin
         declare
            Parsed : constant Attributes.Get_Object_Attributes_Result :=
              Attributes.Parse_Result (Document);
         begin
            Note ("    S3.Attributes.Parse_Result: accepted, Has_Checksum=" &
                  Boolean'Image (Parsed.Has_Checksum) &
                  " Has_Object_Parts=" &
                  Boolean'Image (Parsed.Has_Object_Parts));
         end;
      exception
         when Error : others =>
            Note ("    S3.Attributes.Parse_Result: " &
                  Ada.Exceptions.Exception_Name (Error) & ": " &
                  Ada.Exceptions.Exception_Message (Error));
      end;
      begin
         declare
            Outcome : constant Low_Level.Get_Object_Attributes_Outcome :=
              Low_Level.Decode_Get_Object_Attributes_Response
                (Status => 200, Payload => Document);
         begin
            Note ("    Client.Low_Level: accepted, kind=" &
                  Low_Level.Get_Object_Attributes_Outcome_Kind'Image
                    (Outcome.Kind));
            if Must_Work then
               Check (True, Label);
            end if;
         end;
      exception
         when Error : others =>
            Note ("    Client.Low_Level: " &
                  Ada.Exceptions.Exception_Name (Error) & ": " &
                  Ada.Exceptions.Exception_Message (Error));
            if Must_Work then
               Check (False, Label);
            end if;
      end;
   end Decode;

   Bucket : constant String := "/domain-b7";

begin
   Note ("=== controls: shapes the decoder accepts today ===");
   Decode ("FULL_OBJECT CRC32, parts container present   ",
           Response_Body
             ("<ChecksumCRC32>" & Digest (Core.CRC32) & "</ChecksumCRC32>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>"),
           False);
   Decode ("FULL_OBJECT SHA256, no parts container       ",
           Response_Body
             ("<ChecksumSHA256>" & Digest (Core.SHA256) &
              "</ChecksumSHA256>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>",
              With_Parts => False),
           False);

   Note ("");
   Note ("=== the modeled combinations the decoder rejects ===");
   Decode ("FULL_OBJECT SHA256 + parts (MinIO's answer)  ",
           Response_Body
             ("<ChecksumSHA256>" & Digest (Core.SHA256) &
              "</ChecksumSHA256>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>"),
           True);
   Decode ("FULL_OBJECT MD5 + parts                      ",
           Response_Body
             ("<ChecksumMD5>" & Digest (Core.MD5) & "</ChecksumMD5>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>"),
           True);
   Decode ("FULL_OBJECT XXHASH64 + parts                 ",
           Response_Body
             ("<ChecksumXXHASH64>" & Digest (Core.XXHASH64) &
              "</ChecksumXXHASH64>" &
              "<ChecksumType>FULL_OBJECT</ChecksumType>"),
           True);
   Decode ("untyped raw SHA256 + parts (type omitted)    ",
           Response_Body
             ("<ChecksumSHA256>" & Digest (Core.SHA256) &
              "</ChecksumSHA256>"),
           True);

   Note ("");
   Note ("=== self-interop: what this crate's own server emits ===");
   Check (Status_Code (Run (Signed_Request ("PUT", Bucket))) = 200,
          "CreateBucket " & Bucket & " is 200");
   Check (Status_Code
            (Run (Signed_Request
                    ("PUT", Bucket & "/single", Payload,
                     "x-amz-sdk-checksum-algorithm: SHA256" & CRLF &
                     "x-amz-checksum-sha256: " & Digest (Core.SHA256) &
                     CRLF))) = 200,
          "PutObject with x-amz-checksum-sha256 is 200");
   declare
      Response : constant String :=
        Run (Signed_Request
               ("GET", Bucket & "/single", "",
                "x-amz-object-attributes: ETag,Checksum,ObjectParts," &
                "StorageClass,ObjectSize" & CRLF,
                [SigV4.Pair ("attributes", "")]));
   begin
      Note ("GetObjectAttributes status=" & Image (Status_Code (Response)));
      Note ("    body=" & Escape (Body_Of (Response)));
      Check (Status_Code (Response) = 200,
             "control: the crate's own GetObjectAttributes is 200");
      Decode ("this crate's own answer, read by its own client",
              Body_Of (Response), True);
   end;

   Finish;
end Repro_S3_Domain_B_7;
