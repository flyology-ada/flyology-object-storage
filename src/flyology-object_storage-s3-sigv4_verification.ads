with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.SigV4;

--  Strict parsing and verification of SigV4 Authorization request fields.
--  HTTP adapters collect only the header names declared by SignedHeaders;
--  credential providers can keep secret material internal and call Verify.
package Flyology.Object_Storage.S3.SigV4_Verification is

   type Parse_Status is
     (Parsed,
      Missing_Authorization,
      Unsupported_Algorithm,
      Malformed_Authorization,
      Invalid_Credential_Scope,
      Invalid_Signed_Headers,
      Invalid_Signature);

   type Authorization_Data is private;

   type Parse_Result is record
      Status : Parse_Status := Missing_Authorization;
      Data   : Authorization_Data;
   end record;

   --  Parse one Authorization field with bounded credential and header lists.
   --  Attribute order and optional whitespace after commas are accepted;
   --  missing, duplicate, or unknown attributes are rejected.
   --  @param Value Complete Authorization field value
   --  @return Parsed scope and signed-header declaration, or exact failure
   function Parse (Value : String) return Parse_Result;

   function Access_Key (Item : Authorization_Data) return String;
   function Scope_Date (Item : Authorization_Data) return String;
   function Region (Item : Authorization_Data) return String;
   function Service (Item : Authorization_Data) return String;
   function Signature (Item : Authorization_Data) return String;
   function Signed_Header_Count
     (Item : Authorization_Data) return Natural;
   function Signed_Header_Name
     (Item : Authorization_Data; Index : Positive) return String
   with Pre => Index <= Signed_Header_Count (Item);
   function Header_Is_Signed
     (Item : Authorization_Data; Name : String) return Boolean;

   --  Verify a parsed header against the exact origin-form target and the
   --  physical signed request fields. Query percent escapes are decoded and
   --  canonicalized with plus retained as a literal plus. Headers must match
   --  the declared sorted SignedHeaders set exactly. The comparison is
   --  constant-time with respect to the two signature strings.
   --  @param Item Parsed Authorization data
   --  @param Method Uppercase HTTP method
   --  @param Target Exact origin-form request target
   --  @param Headers Physical fields named by SignedHeaders
   --  @param Payload_Hash x-amz-content-sha256 value
   --  @param Secret_Key Credential-provider-owned secret borrowed for call
   --  @return True only for a complete matching S3 SigV4 signature
   function Verify
     (Item         : Authorization_Data;
      Method       : String;
      Target       : String;
      Headers      : SigV4.Name_Value_Array;
      Payload_Hash : String;
      Secret_Key   : String) return Boolean;

private
   --  A PutObject request can carry the full 64-entry user-metadata map in
   --  addition to the required SigV4 and modeled control headers.
   Maximum_Signed_Headers : constant := 128;
   Maximum_Header_Name    : constant := 128;

   subtype Header_Length is Natural range 0 .. Maximum_Header_Name;
   type Bounded_Header is record
      Length : Header_Length := 0;
      Data   : String (1 .. Maximum_Header_Name) :=
        (others => Character'Val (0));
   end record;
   type Bounded_Header_Array is
     array (Positive range 1 .. Maximum_Signed_Headers) of Bounded_Header;

   type Authorization_Data is record
      Access_Key_Value : Ada.Strings.Unbounded.Unbounded_String;
      Date_Value       : Ada.Strings.Unbounded.Unbounded_String;
      Region_Value     : Ada.Strings.Unbounded.Unbounded_String;
      Service_Value    : Ada.Strings.Unbounded.Unbounded_String;
      Signature_Value  : Ada.Strings.Unbounded.Unbounded_String;
      Header_Count     : Natural range 0 .. Maximum_Signed_Headers := 0;
      Headers          : Bounded_Header_Array;
   end record;
end Flyology.Object_Storage.S3.SigV4_Verification;
