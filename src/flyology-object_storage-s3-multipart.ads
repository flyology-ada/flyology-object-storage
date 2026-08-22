with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Typed multipart REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Multipart is

   Malformed_Multipart : exception;

   type Multipart_Query_Kind is
     (Create_Upload_Query, Upload_Part_Query, Existing_Upload_Query);

   type Multipart_Query (Kind : Multipart_Query_Kind := Create_Upload_Query)
   is record
      Operation_ID : Ada.Strings.Unbounded.Unbounded_String;
      case Kind is
         when Create_Upload_Query =>
            null;
         when Upload_Part_Query =>
            Upload_ID   : Ada.Strings.Unbounded.Unbounded_String;
            Part_Number : Core.Part_Number := Core.Part_Number'First;
         when Existing_Upload_Query =>
            Existing_Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  Parse the exact query shapes used by CreateMultipartUpload, UploadPart,
   --  CompleteMultipartUpload, and AbortMultipartUpload. Names and values use
   --  strict URI percent decoding; '+' remains a literal plus byte.
   function Parse_Query (Query : String) return Multipart_Query;

   type Completed_Part is record
      Number           : Core.Part_Number := Core.Part_Number'First;
      Entity_Tag       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64 : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128 : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Completed_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Completed_Part);

   subtype Completed_Part_List is Completed_Part_Vectors.Vector;

   type Complete_Multipart_Upload_Request is record
      Parts : Completed_Part_List;
   end record;

   function Parse_Complete_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Complete_Multipart_Upload_Request;

   function Serialize_Complete_Request
     (Value : Complete_Multipart_Upload_Request) return String;

   --  Body fields returned by CreateMultipartUpload.
   type Create_Multipart_Upload_Result is record
      Bucket    : Ada.Strings.Unbounded.Unbounded_String;
      Key       : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse_Create_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Create_Multipart_Upload_Result;

   function Serialize_Create_Result
     (Value : Create_Multipart_Upload_Result) return String;

   --  Body fields returned by CompleteMultipartUpload. Header fields remain
   --  the responsibility of the HTTP operation layer.
   type Complete_Multipart_Upload_Result is record
      Location           : Ada.Strings.Unbounded.Unbounded_String;
      Bucket             : Ada.Strings.Unbounded.Unbounded_String;
      Key                : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128 : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse_Complete_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Complete_Multipart_Upload_Result;

   function Serialize_Complete_Result
     (Value : Complete_Multipart_Upload_Result) return String;

   --  Body fields returned by UploadPartCopy. Header fields remain the
   --  responsibility of the HTTP operation layer.
   type Copy_Part_Result is record
      Entity_Tag         : Ada.Strings.Unbounded.Unbounded_String;
      Last_Modified      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128 : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse_Copy_Part_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Copy_Part_Result;

   function Serialize_Copy_Part_Result
     (Value : Copy_Part_Result) return String;

end Flyology.Object_Storage.S3.Multipart;
