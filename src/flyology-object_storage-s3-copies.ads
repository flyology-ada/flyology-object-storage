with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML documents returned by S3 copy operations.
package Flyology.Object_Storage.S3.Copies is

   --  Raised when a CopyObject result violates the modeled document shape.
   Malformed_Copy : exception;

   --  Every body member in the pinned CopyObjectResult shape.
   --  @field Entity_Tag Strong copied-object entity tag
   --  @field Last_Modified Modeled copied-object modification time
   --  @field Checksum_Type Optional modeled checksum type
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

   --  Parse one bounded CopyObject result document.
   --  @param Document CopyObject result XML
   --  @param Limits XML parsing limits
   --  @return Decoded CopyObject result body
   function Parse_Copy_Object_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Copy_Object_Result;

end Flyology.Object_Storage.S3.Copies;
