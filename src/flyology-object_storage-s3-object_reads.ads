with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;

--  Strict query boundary shared by GetObject and HeadObject.
package Flyology.Object_Storage.S3.Object_Reads is

   type Read_Operation is (Get_Object, Head_Object);

   type Object_Read_Request is record
      Has_Part_Number        : Boolean := False;
      Part_Number            : S3.Core.Part_Number := 1;
      Has_Version_ID         : Boolean := False;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Response_Overrides : Boolean := False;
   end record;

   Malformed_Object_Read_Request : exception;

   --  Parse all documented object-read query members plus the SDK x-id.
   --  Escapes are strict, '+' remains literal, fields are unique and bounded,
   --  and response override values cannot contain header control bytes.
   function Parse_Query
     (Query : String; Operation : Read_Operation)
      return Object_Read_Request;

end Flyology.Object_Storage.S3.Object_Reads;
