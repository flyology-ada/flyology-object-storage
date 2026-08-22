--  Bounded, entity-safe SAX boundary for S3 XML documents.
package Flyology.Object_Storage.S3.XML is

   XML_Error : exception;

   type Parse_Limits is record
      Maximum_Document_Bytes : Positive := 16 * 1_024 * 1_024;
      Maximum_Depth          : Positive := 64;
      Maximum_Elements       : Positive := 100_000;
      Maximum_Text_Bytes     : Positive := 16 * 1_024 * 1_024;
   end record;

   Default_Limits : constant Parse_Limits := (others => <>);

   type Event_Handler is limited interface;

   procedure Start_Element
     (Item : in out Event_Handler; Local_Name : String) is abstract;
   procedure Text
     (Item : in out Event_Handler; Value : String) is abstract;
   procedure End_Element
     (Item : in out Event_Handler; Local_Name : String) is abstract;

   procedure Parse
     (Document : String;
      Receiver : aliased in out Event_Handler'Class;
      Limits   : Parse_Limits := Default_Limits);

   function Escape_Text (Value : String) return String;
   function Escape_Attribute (Value : String) return String;

end Flyology.Object_Storage.S3.XML;
