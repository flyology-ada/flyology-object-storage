with Flyology.Object_Storage.S3.XML;

--  Shared strict envelope decoder for paginated S3 configuration reads.
private
generic
   Root_Name : String;
   Item_Container_Name : String;
   Item_Name : String;
   Allow_Is_Truncated : Boolean;
   Allow_Continuation_Token : Boolean;
   Allow_Next_Continuation_Token : Boolean;

   type Item_Type is private;
   type Item_Handler_Type is new XML.Event_Handler with private;
   with procedure Reset_Item (Item : in out Item_Handler_Type);
   with function Read_Item (Item : Item_Handler_Type) return Item_Type;

   type Result_Type is private;
   with function Empty_Result return Result_Type;
   with procedure Set_Is_Truncated
     (Result : in out Result_Type; Value : Boolean);
   with procedure Set_Continuation_Token
     (Result : in out Result_Type; Value : String);
   with procedure Set_Next_Continuation_Token
     (Result : in out Result_Type; Value : String);
   with procedure Set_Extra_Scalar
     (Result : in out Result_Type; Name : String; Value : String);
   with procedure Set_Item_Container_Present
     (Result : in out Result_Type);
   with procedure Append_Item
     (Result : in out Result_Type; Value : Item_Type);
package Flyology.Object_Storage.S3.Paginated_REST_XML_Reads is

   --  Raised when the common page envelope violates the pinned REST/XML
   --  model. Item-specific validation exceptions remain owned by the
   --  operation codec and propagate unchanged.
   Malformed_Page : exception;

   --  Parse one complete bounded configuration-list response. The caller's
   --  shared XML limits bound document bytes, text, depth, and element count;
   --  the family introduces no independent item or page-size policy.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving page with items in wire order
   --  @exception Malformed_Page Common page envelope violates the model
   function Parse
     (Document : String; Limits : XML.Parse_Limits) return Result_Type;

end Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;
