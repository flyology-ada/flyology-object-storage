with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML documents returned by S3 copy operations.
package Flyology.Object_Storage.S3.Copies is

   Malformed_Copy : exception;

   --  Every body member in the pinned CopyObjectResult shape.
   type Copy_Object_Result is record
      Entity_Tag         : Ada.Strings.Unbounded.Unbounded_String;
      Last_Modified      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type      : Ada.Strings.Unbounded.Unbounded_String;
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

   function Parse_Copy_Object_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Copy_Object_Result;

end Flyology.Object_Storage.S3.Copies;
