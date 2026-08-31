with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Typed S3 REST error documents shared by clients and servers.
package Flyology.Object_Storage.S3.Errors is

   --  Raised when an S3 error document violates the modeled XML contract.
   Malformed_Error : exception;

   --  Decoded fields from one S3 Error response document.
   --  @field Code Required nonempty service error code
   --  @field Message Required nonempty service error message
   --  @field Resource Optional resource text
   --  @field Request_ID Optional request identifier
   --  @field Host_ID Optional host identifier
   type Error_Response is record
      Code       : Ada.Strings.Unbounded.Unbounded_String;
      Message    : Ada.Strings.Unbounded.Unbounded_String;
      Resource   : Ada.Strings.Unbounded.Unbounded_String;
      Request_ID : Ada.Strings.Unbounded.Unbounded_String;
      Host_ID    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse one complete S3 Error response document.
   --  @param Document Complete same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Decoded required and optional error fields
   --  @exception Malformed_Error Document violates the modeled contract
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Error_Response;

   --  Serialize one S3 Error response with nonempty Code and Message fields.
   --  @param Value Required and optional error fields to encode
   --  @return Exact S3 Error XML document
   --  @exception Malformed_Error Code or Message is empty
   function Serialize (Value : Error_Response) return String;

end Flyology.Object_Storage.S3.Errors;
