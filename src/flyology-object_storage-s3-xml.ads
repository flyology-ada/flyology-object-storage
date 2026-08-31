--  Bounded, entity-safe SAX boundary for S3 XML documents.
package Flyology.Object_Storage.S3.XML is

   --  Raised when S3 XML parsing or escaping rejects malformed, unsafe, or
   --  over-limit data.
   XML_Error : exception;

   --  Caller-selectable limits for one S3 XML parse.
   --  @field Maximum_Document_Bytes Maximum accepted document length
   --  @field Maximum_Depth Maximum accepted element nesting depth
   --  @field Maximum_Elements Maximum accepted element count
   --  @field Maximum_Text_Bytes Maximum accepted cumulative text bytes
   type Parse_Limits is record
      Maximum_Document_Bytes : Positive := 16 * 1_024 * 1_024;
      Maximum_Depth          : Positive := 64;
      Maximum_Elements       : Positive := 100_000;
      Maximum_Text_Bytes     : Positive := 16 * 1_024 * 1_024;
   end record;

   --  Default S3 XML parser limits defined by Parse_Limits.
   Default_Limits : constant Parse_Limits := (others => <>);

   --  Caller-owned receiver for bounded S3 XML parse events.
   type Event_Handler is limited interface;

   --  Receive the start of one element.
   --  @param Item Caller-owned event receiver
   --  @param Local_Name Resolved local element name
   procedure Start_Element
     (Item : in out Event_Handler; Local_Name : String) is abstract;
   --  Optional structural metadata hook. Handlers that need exact schema
   --  validation can reject foreign namespaces or unexpected attributes;
   --  existing forward-compatible codecs inherit the no-op default.
   --  @param Item Caller-owned event receiver
   --  @param Namespace_URI Exact resolved element namespace, or empty
   --  @param Attribute_Count Number of physical attributes on the element
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
   --  Receive one text fragment.
   --  @param Item Caller-owned event receiver
   --  @param Value Exact parser-provided text fragment
   procedure Text
     (Item : in out Event_Handler; Value : String) is abstract;
   --  Receive the end of one element.
   --  @param Item Caller-owned event receiver
   --  @param Local_Name Resolved local element name
   procedure End_Element
     (Item : in out Event_Handler; Local_Name : String) is abstract;

   --  Parse one bounded, entity-safe S3 XML document.
   --  @param Document Complete XML document bytes
   --  @param Receiver Receiver borrowed for this parse and not retained
   --  @param Limits Limits applied to this parse
   procedure Parse
     (Document : String;
      Receiver : aliased in out Event_Handler'Class;
      Limits   : Parse_Limits := Default_Limits);

   --  Escape one value for XML text content.
   --  @param Value Unescaped text value
   --  @return XML text with reserved characters escaped
   function Escape_Text (Value : String) return String;

   --  Escape one value for an XML attribute.
   --  @param Value Unescaped attribute value
   --  @return XML attribute text with reserved characters escaped
   function Escape_Attribute (Value : String) return String;

end Flyology.Object_Storage.S3.XML;
