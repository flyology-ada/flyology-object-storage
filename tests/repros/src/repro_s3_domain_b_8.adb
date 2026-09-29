--  S3-DOMAIN-B-8 (found while verifying B-7): the GetObjectAttributes
--  decoder bounds the response's <MaxParts> echo by Core.Page_Size'Last
--  (1000).  The pinned model types GetObjectAttributesParts.MaxParts as a
--  plain integer with no min/max, and MinIO RELEASE.2025-09-07T16-13-09Z
--  really answers <MaxParts>10000</MaxParts> for every GetObjectAttributes
--  request that selects ObjectParts.  The value is rejected inside the SAX
--  handler ("invalid object part scalar"), so the whole response is reported
--  as malformed XML and the client raises Invalid_Response.
--
--  Every checksum below is FULL_OBJECT CRC32, which the multipart policy
--  accepts, so S3-DOMAIN-B-7 is not involved.
with Ada.Exceptions;
with Flyology.Bytes;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Checksums;
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_B_8 is

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

   function Response_Body (Max_Parts : String) return String is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<GetObjectAttributesResponse " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<Checksum><ChecksumCRC32>" & Digest (Core.CRC32) &
      "</ChecksumCRC32><ChecksumType>FULL_OBJECT</ChecksumType></Checksum>" &
      "<ObjectParts><IsTruncated>false</IsTruncated>" &
      "<MaxParts>" & Max_Parts & "</MaxParts>" &
      "<NextPartNumberMarker>1</NextPartNumberMarker>" &
      "<PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount>" &
      "<Part><PartNumber>1</PartNumber><Size>11</Size></Part>" &
      "</ObjectParts>" &
      "<ObjectSize>11</ObjectSize>" &
      "</GetObjectAttributesResponse>");

   procedure Decode (Label, Max_Parts : String; Must_Work : Boolean) is
      Document : constant String := Response_Body (Max_Parts);
   begin
      Note (Label & " (MaxParts=" & Max_Parts & ")");
      begin
         declare
            Parsed : constant Attributes.Get_Object_Attributes_Result :=
              Attributes.Parse_Result (Document);
         begin
            Note ("    S3.Attributes.Parse_Result: accepted, MaxParts=" &
                  Image (Parsed.Object_Parts.Max_Parts.Value));
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

begin
   Note ("Core.Page_Size'Last  = " & Image (Integer (Core.Page_Size'Last)));
   Note ("Core.Part_Number'Last= " & Image (Integer (Core.Part_Number'Last)));
   Note ("");
   Note ("=== control: a MaxParts echo inside the crate's bound ===");
   Decode ("control: MaxParts within Page_Size", "1000", False);
   Note ("");
   Note ("=== MinIO's actual MaxParts echo ===");
   Decode ("MinIO's GetObjectAttributes answer", "10000", True);
   Finish;
end Repro_S3_Domain_B_8;
