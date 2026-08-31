with Ada.Strings.Unbounded;

--  AWS Signature Version 4 canonical requests and Authorization headers.
package Flyology.Object_Storage.S3.SigV4 is

   --  Raised when canonical signing input violates SigV4 requirements.
   Invalid_Signing_Input : exception;

   --  One name and value pair used by SigV4 canonicalization.
   --  @field Name Pair name
   --  @field Value Pair value
   type Name_Value is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Ordered collection of SigV4 name and value pairs.
   type Name_Value_Array is array (Positive range <>) of Name_Value;

   --  Construct one SigV4 name and value pair.
   --  @param Name Pair name
   --  @param Value Pair value
   --  @return Pair containing copies of both values
   function Pair (Name, Value : String) return Name_Value;

   --  Intermediate and final values produced by SigV4 signing.
   --  @field Canonical_Request Canonical request text
   --  @field String_To_Sign String-to-sign text
   --  @field Signed_Headers Semicolon-separated signed header names
   --  @field Signature Lowercase hexadecimal request signature
   --  @field Authorization Authorization header value
   type Signing_Result is record
      Canonical_Request : Ada.Strings.Unbounded.Unbounded_String;
      String_To_Sign    : Ada.Strings.Unbounded.Unbounded_String;
      Signed_Headers    : Ada.Strings.Unbounded.Unbounded_String;
      Signature         : Ada.Strings.Unbounded.Unbounded_String;
      Authorization     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  SigV4 lowercase SHA-256 digest for an empty payload.
   Empty_Payload_Hash : constant String :=
     "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
   --  SigV4 sentinel for a payload excluded from content hashing.
   Unsigned_Payload : constant String := "UNSIGNED-PAYLOAD";

   --  Compute the lowercase hexadecimal SHA-256 digest of one value.
   --  @param Value Value to hash
   --  @return Lowercase hexadecimal SHA-256 digest
   function SHA256_Hex (Value : String) return String;

   --  Encode and sort query pairs exactly as SigV4 uses them.
   --  @param Query Query pairs to encode and sort
   --  @return Canonical SigV4 query string
   function Canonical_Query (Query : Name_Value_Array) return String;

   --  Construct an AWS Signature Version 4 result.
   --  @param Method Nonempty uppercase ASCII method token
   --  @param Path Absolute request path to canonicalize
   --  @param Query Query pairs to canonicalize
   --  @param Headers Header pairs including exactly one host entry
   --  @param Payload_Hash Lowercase SHA-256 hex or unsigned-payload sentinel
   --  @param Access_Key AWS access key identifier
   --  @param Secret_Key AWS secret access key
   --  @param Region SigV4 credential-scope region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @param Service SigV4 credential-scope service
   --  @return Canonical request, string-to-sign, signed headers, signature,
   --    and authorization values
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

   --  Compare two strings without content-dependent early return.
   --  @param Left First string
   --  @param Right Second string
   --  @return True when both strings have identical bytes and length
   function Constant_Time_Equal (Left, Right : String) return Boolean;

end Flyology.Object_Storage.S3.SigV4;
