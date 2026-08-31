with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Typed multipart REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Multipart is

   --  Raised when multipart query or REST/XML data is malformed.
   Malformed_Multipart : exception;

   --  Part-number marker including zero for no previous part.
   subtype Part_Marker_Value is Natural range 0 .. Core.Part_Number'Last;

   --  Multipart query shape selected by its required members.
   --  @enum Create_Upload_Query CreateMultipartUpload query
   --  @enum Upload_Part_Query UploadPart or UploadPartCopy query
   --  @enum Existing_Upload_Query Existing-upload mutation query
   --  @enum List_Parts_Query ListParts query
   type Multipart_Query_Kind is
     (Create_Upload_Query, Upload_Part_Query, Existing_Upload_Query,
      List_Parts_Query);

   --  Parsed multipart query parameters.
   --  @field Kind Selected multipart query shape
   --  @field Operation_ID Optional modeled x-id operation name
   --  @field Upload_ID Upload identifier for an uploaded part
   --  @field Part_Number Uploaded part number
   --  @field Existing_Upload_ID Upload identifier for an existing-upload query
   --  @field Listed_Upload_ID Upload identifier for a ListParts query
   --  @field Part_Number_Marker Exclusive completed-part marker
   --  @field Max_Parts Requested maximum ListParts result count
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
         when List_Parts_Query =>
            Listed_Upload_ID   : Ada.Strings.Unbounded.Unbounded_String;
            Part_Number_Marker : Part_Marker_Value := 0;
            Max_Parts          : Core.Page_Size := Core.Page_Size'Last;
      end case;
   end record;

   --  Parse the exact query shapes used by CreateMultipartUpload, UploadPart,
   --  CompleteMultipartUpload, AbortMultipartUpload, and ListParts. Names and
   --  values use strict URI percent decoding; '+' remains a literal plus byte.
   --  @param Query Raw query bytes after the question mark
   --  @return Parsed multipart query shape and values
   function Parse_Query (Query : String) return Multipart_Query;

   --  One requested completed multipart part.
   --  @field Number Multipart part number
   --  @field Entity_Tag Modeled part entity tag
   --  @field Checksum_CRC32 Optional CRC-32 checksum value
   --  @field Checksum_CRC32C Optional CRC-32C checksum value
   --  @field Checksum_CRC64NVME Optional CRC-64/NVME checksum value
   --  @field Checksum_SHA1 Optional SHA-1 checksum value
   --  @field Checksum_SHA256 Optional SHA-256 checksum value
   --  @field Checksum_SHA512 Optional SHA-512 checksum value
   --  @field Checksum_MD5 Optional MD5 checksum value
   --  @field Checksum_XXHASH64 Optional XXH64 checksum value
   --  @field Checksum_XXHASH3 Optional XXH3 64-bit checksum value
   --  @field Checksum_XXHASH128 Optional XXH3 128-bit checksum value
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

   --  Vector implementation used for completed multipart parts.
   package Completed_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Completed_Part);

   --  Ordered completed multipart part collection.
   subtype Completed_Part_List is Completed_Part_Vectors.Vector;

   --  CompleteMultipartUpload request body.
   --  @field Parts Ordered completed multipart parts
   type Complete_Multipart_Upload_Request is record
      Parts : Completed_Part_List;
   end record;

   --  Parse one bounded CompleteMultipartUpload request document.
   --  @param Document CompleteMultipartUpload request XML
   --  @param Limits XML parsing limits
   --  @return Decoded completion request
   function Parse_Complete_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Complete_Multipart_Upload_Request;

   --  Serialize one CompleteMultipartUpload request document.
   --  @param Value Completion request to serialize
   --  @return Namespaced CompleteMultipartUpload request XML
   function Serialize_Complete_Request
     (Value : Complete_Multipart_Upload_Request) return String;

   --  Body fields returned by CreateMultipartUpload.
   --  @field Bucket Bucket name
   --  @field Key Object key
   --  @field Upload_ID New multipart upload identifier
   type Create_Multipart_Upload_Result is record
      Bucket    : Ada.Strings.Unbounded.Unbounded_String;
      Key       : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse one bounded CreateMultipartUpload result document.
   --  @param Document CreateMultipartUpload result XML
   --  @param Limits XML parsing limits
   --  @return Decoded create result
   function Parse_Create_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Create_Multipart_Upload_Result;

   --  Serialize one CreateMultipartUpload result document.
   --  @param Value Create result to serialize
   --  @return Namespaced CreateMultipartUpload result XML
   function Serialize_Create_Result
     (Value : Create_Multipart_Upload_Result) return String;

   --  Body fields returned by CompleteMultipartUpload. Header fields remain
   --  the responsibility of the HTTP operation layer.
   --  @field Location Modeled completed-object location
   --  @field Bucket Bucket name
   --  @field Key Object key
   --  @field Entity_Tag Modeled completed-object entity tag
   --  @field Checksum_CRC32 Optional CRC-32 checksum value
   --  @field Checksum_CRC32C Optional CRC-32C checksum value
   --  @field Checksum_CRC64NVME Optional CRC-64/NVME checksum value
   --  @field Checksum_SHA1 Optional SHA-1 checksum value
   --  @field Checksum_SHA256 Optional SHA-256 checksum value
   --  @field Checksum_SHA512 Optional SHA-512 checksum value
   --  @field Checksum_MD5 Optional MD5 checksum value
   --  @field Checksum_XXHASH64 Optional XXH64 checksum value
   --  @field Checksum_XXHASH3 Optional XXH3 64-bit checksum value
   --  @field Checksum_XXHASH128 Optional XXH3 128-bit checksum value
   --  @field Checksum_Type Optional modeled checksum type
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

   --  Parse one bounded CompleteMultipartUpload result document.
   --  @param Document CompleteMultipartUpload result XML
   --  @param Limits XML parsing limits
   --  @return Decoded completion result body
   function Parse_Complete_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Complete_Multipart_Upload_Result;

   --  Serialize one CompleteMultipartUpload result document.
   --  @param Value Completion result body to serialize
   --  @return Namespaced CompleteMultipartUpload result XML
   function Serialize_Complete_Result
     (Value : Complete_Multipart_Upload_Result) return String;

   --  Body fields returned by UploadPartCopy. Header fields remain the
   --  responsibility of the HTTP operation layer.
   --  @field Entity_Tag Modeled copied-part entity tag
   --  @field Last_Modified Modeled copied-part modification time
   --  @field Checksum_CRC32 Optional CRC-32 checksum value
   --  @field Checksum_CRC32C Optional CRC-32C checksum value
   --  @field Checksum_CRC64NVME Optional CRC-64/NVME checksum value
   --  @field Checksum_SHA1 Optional SHA-1 checksum value
   --  @field Checksum_SHA256 Optional SHA-256 checksum value
   --  @field Checksum_SHA512 Optional SHA-512 checksum value
   --  @field Checksum_MD5 Optional MD5 checksum value
   --  @field Checksum_XXHASH64 Optional XXH64 checksum value
   --  @field Checksum_XXHASH3 Optional XXH3 64-bit checksum value
   --  @field Checksum_XXHASH128 Optional XXH3 128-bit checksum value
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

   --  Parse one bounded UploadPartCopy result document.
   --  @param Document UploadPartCopy result XML
   --  @param Limits XML parsing limits
   --  @return Decoded copied-part result body
   function Parse_Copy_Part_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Copy_Part_Result;

   --  Serialize one UploadPartCopy result document.
   --  @param Value Copied-part result body to serialize
   --  @return Namespaced UploadPartCopy result XML
   function Serialize_Copy_Part_Result
     (Value : Copy_Part_Result) return String;

   --  Identity information modeled in a ListParts result body.
   --  @field ID Modeled identity identifier
   --  @field Display_Name Modeled identity display name
   type Multipart_Identity is record
      ID           : Ada.Strings.Unbounded.Unbounded_String;
      Display_Name : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Every member in the pinned ListParts Part structure.
   --  @field Number Part number
   --  @field Last_Modified Modeled part modification time
   --  @field Entity_Tag Modeled part entity tag
   --  @field Size Part size in bytes
   --  @field Checksum_CRC32 Optional CRC-32 checksum value
   --  @field Checksum_CRC32C Optional CRC-32C checksum value
   --  @field Checksum_CRC64NVME Optional CRC-64/NVME checksum value
   --  @field Checksum_SHA1 Optional SHA-1 checksum value
   --  @field Checksum_SHA256 Optional SHA-256 checksum value
   --  @field Checksum_SHA512 Optional SHA-512 checksum value
   --  @field Checksum_MD5 Optional MD5 checksum value
   --  @field Checksum_XXHASH64 Optional XXH64 checksum value
   --  @field Checksum_XXHASH3 Optional XXH3 64-bit checksum value
   --  @field Checksum_XXHASH128 Optional XXH3 128-bit checksum value
   type Listed_Part is record
      Number             : Core.Part_Number := Core.Part_Number'First;
      Last_Modified      : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag         : Ada.Strings.Unbounded.Unbounded_String;
      Size               : Byte_Count := 0;
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

   --  Vector storage for modeled ListParts part entries.
   package Listed_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Part);

   --  Collection of modeled ListParts part entries.
   subtype Listed_Part_List is Listed_Part_Vectors.Vector;

   --  All REST/XML body members in the pinned ListParts output shape.
   --  AbortDate, AbortRuleId, and RequestCharged are HTTP headers handled by
   --  the operation layer.
   --  @field Bucket Bucket name
   --  @field Key Object key
   --  @field Upload_ID Multipart upload identifier
   --  @field Part_Number_Marker Request marker returned in the result
   --  @field Next_Part_Number_Marker Marker for the next result page
   --  @field Max_Parts Requested maximum number of returned parts
   --  @field Is_Truncated Whether another result page is available
   --  @field Parts Modeled part entries
   --  @field Has_Initiator Whether initiator information is present
   --  @field Initiator Modeled initiator information
   --  @field Has_Owner Whether owner information is present
   --  @field Owner Modeled owner information
   --  @field Storage_Class Optional modeled storage class
   --  @field Checksum_Algorithm Optional modeled checksum algorithm
   --  @field Checksum_Type Optional modeled checksum type
   type List_Parts_Result is record
      Bucket                  : Ada.Strings.Unbounded.Unbounded_String;
      Key                     : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID               : Ada.Strings.Unbounded.Unbounded_String;
      Part_Number_Marker      : Part_Marker_Value := 0;
      Next_Part_Number_Marker : Part_Marker_Value := 0;
      Max_Parts               : Core.Page_Size := 0;
      Is_Truncated            : Boolean := False;
      Parts                   : Listed_Part_List;
      Has_Initiator           : Boolean := False;
      Initiator               : Multipart_Identity;
      Has_Owner               : Boolean := False;
      Owner                   : Multipart_Identity;
      Storage_Class           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse one bounded ListParts result document.
   --  @param Document ListParts result XML
   --  @param Limits XML parsing limits
   --  @return Decoded ListParts result body
   function Parse_List_Parts_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Parts_Result;

   --  Serialize one ListParts result document.
   --  @param Value ListParts result body to serialize
   --  @return Namespaced ListParts result XML
   function Serialize_List_Parts_Result
     (Value : List_Parts_Result) return String;

end Flyology.Object_Storage.S3.Multipart;
