--  Pure byte canonicalization rules shared by SigV4 signing and verification.
package Flyology.Object_Storage.S3.SigV4_Encoding
  with SPARK_Mode => On
is
   function URI_Encode
     (Value : String; Encode_Slash : Boolean) return String
   with Pre => Value'Length <= Natural'Last / 3;

   function Lowercase (Value : String) return String
   with Post => Lowercase'Result'Length = Value'Length;

   function Normalize_Header_Value (Value : String) return String
   with Post => Normalize_Header_Value'Result'Length <= Value'Length;

   function Valid_Header_Name (Value : String) return Boolean;
   function Valid_SHA256_Hex (Value : String) return Boolean;
   function Valid_Timestamp (Value : String) return Boolean;
   function Valid_Scope_Segment (Value : String) return Boolean;
   function Valid_Access_Key (Value : String) return Boolean;
   function Valid_Method (Value : String) return Boolean;
end Flyology.Object_Storage.S3.SigV4_Encoding;
