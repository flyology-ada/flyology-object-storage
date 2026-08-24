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
   --  Optional structural metadata hook. Handlers that need exact schema
   --  validation can reject foreign namespaces or unexpected attributes;
   --  existing forward-compatible codecs inherit the no-op default.
   procedure Start_Element_Details
     (Item            : in out Event_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural) is null;
   --  Optional exact physical-attribute hook.  Values are copied from the
   --  XMLAda callback before it returns; handlers must not retain borrowed
   --  parser symbols.
   --  @param Item Caller-owned event receiver
   --  @param Element_Local_Name Local name of the owning element
   --  @param Namespace_URI Exact resolved attribute namespace, or empty
   --  @param Local_Name Exact local attribute name
   --  @param Value Exact normalized attribute value
   procedure Element_Attribute
     (Item               : in out Event_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String) is null;
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
