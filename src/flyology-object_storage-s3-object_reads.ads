with Ada.Calendar;
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
      Has_Response_Cache_Control : Boolean := False;
      Response_Cache_Control : Ada.Strings.Unbounded.Unbounded_String;
      Has_Response_Content_Disposition : Boolean := False;
      Response_Content_Disposition :
        Ada.Strings.Unbounded.Unbounded_String;
      Has_Response_Content_Encoding : Boolean := False;
      Response_Content_Encoding : Ada.Strings.Unbounded.Unbounded_String;
      Has_Response_Content_Language : Boolean := False;
      Response_Content_Language : Ada.Strings.Unbounded.Unbounded_String;
      Has_Response_Content_Type : Boolean := False;
      Response_Content_Type : Ada.Strings.Unbounded.Unbounded_String;
      Has_Response_Expires : Boolean := False;
      Response_Expires      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Conditional_Date_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Seconds_Since_Epoch : Long_Long_Integer;
         when False =>
            null;
      end case;
   end record;

   Malformed_Object_Read_Request : exception;

   --  Parse all documented object-read query members plus the SDK x-id.
   --  Escapes are strict, '+' remains literal, fields are unique and bounded,
   --  and response override values cannot contain header control bytes.
   function Parse_Query
     (Query : String; Operation : Read_Operation)
      return Object_Read_Request;

   --  Parse all three HTTP-date formats required of HTTP recipients. The
   --  obsolete two-digit year form follows the RFC 9110 fifty-year rule.
   function Parse_Conditional_Date
     (Value : String;
      Now   : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Conditional_Date_Result;

end Flyology.Object_Storage.S3.Object_Reads;
