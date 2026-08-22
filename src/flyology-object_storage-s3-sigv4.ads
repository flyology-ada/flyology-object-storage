with Ada.Strings.Unbounded;

--  AWS Signature Version 4 canonical requests and Authorization headers.
package Flyology.Object_Storage.S3.SigV4 is

   Invalid_Signing_Input : exception;

   type Name_Value is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Name_Value_Array is array (Positive range <>) of Name_Value;

   function Pair (Name, Value : String) return Name_Value;

   type Signing_Result is record
      Canonical_Request : Ada.Strings.Unbounded.Unbounded_String;
      String_To_Sign    : Ada.Strings.Unbounded.Unbounded_String;
      Signed_Headers    : Ada.Strings.Unbounded.Unbounded_String;
      Signature         : Ada.Strings.Unbounded.Unbounded_String;
      Authorization     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Empty_Payload_Hash : constant String :=
     "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
   Unsigned_Payload : constant String := "UNSIGNED-PAYLOAD";

   function SHA256_Hex (Value : String) return String;

   --  Encode and sort query pairs exactly as SigV4 uses them.
   function Canonical_Query (Query : Name_Value_Array) return String;

   function Sign
     (Method             : String;
      Path               : String;
      Query              : Name_Value_Array;
      Headers            : Name_Value_Array;
      Payload_Hash       : String;
      Access_Key         : String;
      Secret_Key         : String;
      Region             : String;
      Timestamp          : String;
      Service            : String := "s3") return Signing_Result;

   function Constant_Time_Equal (Left, Right : String) return Boolean;

end Flyology.Object_Storage.S3.SigV4;
