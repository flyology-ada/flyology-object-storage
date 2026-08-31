with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Typed GetObjectAttributes request values and bounded REST/XML documents.
package Flyology.Object_Storage.S3.Attributes is

   --  Raised when an attributes request or result violates the modeled shape.
   Malformed_Attributes : exception;

   --  Nonnegative object-parts marker bounded by the modeled part number.
   subtype Part_Marker_Value is Natural range 0 .. Core.Part_Number'Last;

   --  Requested GetObjectAttributes result sections.
   --  @field Entity_Tag Whether the entity tag was selected
   --  @field Checksum Whether checksums were selected
   --  @field Object_Parts Whether object-parts information was selected
   --  @field Storage_Class Whether the storage class was selected
   --  @field Object_Size Whether the object size was selected
   type Attribute_Selection is record
      Entity_Tag    : Boolean := False;
      Checksum      : Boolean := False;
      Object_Parts  : Boolean := False;
      Storage_Class : Boolean := False;
      Object_Size   : Boolean := False;
   end record;

   --  Parse the required x-amz-object-attributes comma-list. Values are
   --  unique, case-sensitive model enumeration values; optional HTTP OWS is
   --  accepted around each value. Empty lists and unknown values are invalid.
   --  @param Value Raw x-amz-object-attributes value
   --  @return Decoded attribute selection
   function Parse_Selection (Value : String) return Attribute_Selection;

   --  Canonical comma-list used by the typed client projector.
   --  @param Value Attribute selection to encode
   --  @return Canonical x-amz-object-attributes value
   function Image (Value : Attribute_Selection) return String;

   --  Decoded version selection for one GetObjectAttributes request.
   --  @field Has_Version_ID Whether an explicit version was selected
   --  @field Version_ID Exact selected version identifier, when present
   type Attributes_Query is record
      Has_Version_ID : Boolean := False;
      Version_ID     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse the exact attributes marker, optional versionId, and optional
   --  SDK x-id. Percent escapes are strict, '+' remains literal, duplicates
   --  are rejected, and the total query is bounded.
   --  @param Query Raw GetObjectAttributes query string
   --  @return Decoded version selection
   function Parse_Query (Query : String) return Attributes_Query;

   --  Modeled checksum values for one object or part.
   --  @field CRC32 Optional CRC-32 checksum value
   --  @field CRC32C Optional CRC-32C checksum value
   --  @field CRC64NVME Optional CRC-64/NVME checksum value
   --  @field SHA1 Optional SHA-1 checksum value
   --  @field SHA256 Optional SHA-256 checksum value
   --  @field SHA512 Optional SHA-512 checksum value
   --  @field MD5 Optional MD5 checksum value
   --  @field XXHASH64 Optional XXH64 checksum value
   --  @field XXHASH3 Optional XXH3 64-bit checksum value
   --  @field XXHASH128 Optional XXH3 128-bit checksum value
   --  @field Kind Optional modeled checksum type
   type Checksum_Values is record
      CRC32     : Ada.Strings.Unbounded.Unbounded_String;
      CRC32C    : Ada.Strings.Unbounded.Unbounded_String;
      CRC64NVME : Ada.Strings.Unbounded.Unbounded_String;
      SHA1      : Ada.Strings.Unbounded.Unbounded_String;
      SHA256    : Ada.Strings.Unbounded.Unbounded_String;
      SHA512    : Ada.Strings.Unbounded.Unbounded_String;
      MD5       : Ada.Strings.Unbounded.Unbounded_String;
      XXHASH64  : Ada.Strings.Unbounded.Unbounded_String;
      XXHASH3   : Ada.Strings.Unbounded.Unbounded_String;
      XXHASH128 : Ada.Strings.Unbounded.Unbounded_String;
      Kind      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence-preserving natural value.
   --  @field Is_Set Whether the source member is present
   --  @field Value Decoded value when present
   type Optional_Natural is record
      Is_Set : Boolean := False;
      Value  : Natural := 0;
   end record;

   --  Presence-preserving byte count.
   --  @field Is_Set Whether the source member is present
   --  @field Value Decoded byte count when present
   type Optional_Byte_Count is record
      Is_Set : Boolean := False;
      Value  : Byte_Count := 0;
   end record;

   --  One modeled object-part entry.
   --  @field Number Presence-preserving part number
   --  @field Size Presence-preserving part size in bytes
   --  @field Checksums Modeled checksum values for the part
   type Object_Part is record
      Number    : Optional_Natural;
      Size      : Optional_Byte_Count;
      Checksums : Checksum_Values;
   end record;

   --  Vector storage for modeled object-part entries.
   package Object_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Part);

   --  Collection of modeled object-part entries.
   subtype Object_Part_List is Object_Part_Vectors.Vector;

   --  Modeled object-parts section of a GetObjectAttributes result.
   --  @field Total_Parts_Count Presence-preserving total part count
   --  @field Part_Number_Marker Presence-preserving request marker
   --  @field Next_Part_Number_Marker Presence-preserving next-page marker
   --  @field Max_Parts Presence-preserving page bound
   --  @field Has_Is_Truncated Whether the truncation flag is present
   --  @field Is_Truncated Whether another parts page is available
   --  @field Parts Modeled object-part entries
   type Object_Parts_Result is record
      Total_Parts_Count       : Optional_Natural;
      Part_Number_Marker      : Optional_Natural;
      Next_Part_Number_Marker : Optional_Natural;
      Max_Parts               : Optional_Natural;
      Has_Is_Truncated        : Boolean := False;
      Is_Truncated            : Boolean := False;
      Parts                   : Object_Part_List;
   end record;

   --  Every REST/XML body member in the pinned output shape. Presence flags
   --  retain the distinction between an omitted member and its zero value.
   --  @field Has_Entity_Tag Whether the entity tag is present
   --  @field Entity_Tag Modeled object entity tag
   --  @field Has_Checksum Whether object checksums are present
   --  @field Checksum Modeled object checksum values
   --  @field Has_Object_Parts Whether object-parts information is present
   --  @field Object_Parts Modeled object-parts information
   --  @field Has_Storage_Class Whether the storage class is present
   --  @field Storage_Class Modeled storage class
   --  @field Object_Size Presence-preserving object size in bytes
   type Get_Object_Attributes_Result is record
      Has_Entity_Tag    : Boolean := False;
      Entity_Tag        : Ada.Strings.Unbounded.Unbounded_String;
      Has_Checksum      : Boolean := False;
      Checksum          : Checksum_Values;
      Has_Object_Parts  : Boolean := False;
      Object_Parts      : Object_Parts_Result;
      Has_Storage_Class : Boolean := False;
      Storage_Class     : Ada.Strings.Unbounded.Unbounded_String;
      Object_Size       : Optional_Byte_Count;
   end record;

   --  Parse one bounded GetObjectAttributes result document.
   --  @param Document GetObjectAttributes result XML
   --  @param Limits XML parsing limits
   --  @return Decoded GetObjectAttributes result body
   function Parse_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Get_Object_Attributes_Result;

   --  Serialize one GetObjectAttributes result document.
   --  @param Value GetObjectAttributes result body to serialize
   --  @return Namespaced GetObjectAttributes result XML
   function Serialize_Result
     (Value : Get_Object_Attributes_Result) return String;

end Flyology.Object_Storage.S3.Attributes;
