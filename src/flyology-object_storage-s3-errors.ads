with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Typed S3 REST error documents shared by clients and servers.
package Flyology.Object_Storage.S3.Errors is

   Malformed_Error : exception;

   type Error_Response is record
      Code       : Ada.Strings.Unbounded.Unbounded_String;
      Message    : Ada.Strings.Unbounded.Unbounded_String;
      Resource   : Ada.Strings.Unbounded.Unbounded_String;
      Request_ID : Ada.Strings.Unbounded.Unbounded_String;
      Host_ID    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Error_Response;

   function Serialize (Value : Error_Response) return String;

end Flyology.Object_Storage.S3.Errors;
