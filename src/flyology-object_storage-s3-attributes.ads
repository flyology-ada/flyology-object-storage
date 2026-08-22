with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Typed GetObjectAttributes request values and bounded REST/XML documents.
package Flyology.Object_Storage.S3.Attributes is

   Malformed_Attributes : exception;

   subtype Part_Marker_Value is Natural range 0 .. Core.Part_Number'Last;

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
   function Parse_Selection (Value : String) return Attribute_Selection;

   --  Canonical comma-list used by the typed client projector.
   function Image (Value : Attribute_Selection) return String;

   type Attributes_Query is record
      Has_Version_ID : Boolean := False;
      Version_ID     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse the exact attributes marker, optional versionId, and optional
   --  SDK x-id. Percent escapes are strict, '+' remains literal, duplicates
   --  are rejected, and the total query is bounded.
   function Parse_Query (Query : String) return Attributes_Query;

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

   type Optional_Natural is record
      Is_Set : Boolean := False;
      Value  : Natural := 0;
   end record;

   type Optional_Byte_Count is record
      Is_Set : Boolean := False;
      Value  : Byte_Count := 0;
   end record;

   type Object_Part is record
      Number    : Optional_Natural;
      Size      : Optional_Byte_Count;
      Checksums : Checksum_Values;
   end record;

   package Object_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Part);

   subtype Object_Part_List is Object_Part_Vectors.Vector;

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

   function Parse_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Get_Object_Attributes_Result;

   function Serialize_Result
     (Value : Get_Object_Attributes_Result) return String;

end Flyology.Object_Storage.S3.Attributes;
