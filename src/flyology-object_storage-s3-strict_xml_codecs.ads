with Flyology.Object_Storage.S3.XML;

--  Shared strict runtime for model-generated REST/XML wire codecs.
private
generic
   type Element_Id is (<>);
   No_Element   : Element_Id;
   Root_Element : Element_Id;
   with function Element_Name (Element : Element_Id) return String;
   with function Parent (Element : Element_Id) return Element_Id;
   with function Is_Scalar (Element : Element_Id) return Boolean;
   with function Is_Attribute (Element : Element_Id) return Boolean;
   with function Attribute_Namespace
     (Element : Element_Id) return String;
   with function Is_Repeated (Element : Element_Id) return Boolean;
   with function Is_Required (Element : Element_Id) return Boolean;
   with function Is_Boolean (Element : Element_Id) return Boolean;
   with function Is_Integer (Element : Element_Id) return Boolean;
   with function Is_Timestamp (Element : Element_Id) return Boolean;
   with function Minimum_Length (Element : Element_Id) return Natural;
   with function Has_Maximum_Length (Element : Element_Id) return Boolean;
   with function Maximum_Length (Element : Element_Id) return Natural;
   with function Enumeration_Count (Element : Element_Id) return Natural;
   with function Enumeration_Value
     (Element : Element_Id; Index : Positive) return String;
   with function Matches_Pattern
     (Element : Element_Id; Value : String) return Boolean;
   type Result_Type is limited private;
   with procedure Start_Node
     (Result : in out Result_Type; Element : Element_Id);
   with procedure Set_Scalar
     (Result : in out Result_Type; Element : Element_Id; Value : String);
   with procedure End_Node
     (Result : in out Result_Type; Element : Element_Id);
package Flyology.Object_Storage.S3.Strict_XML_Codecs is

   Malformed_Document : exception;

   --  Parse one generated strict wire shape. Collection_Limit is supplied by
   --  the caller because this shared runtime does not select resource policy.
   procedure Parse
     (Document         : String;
      Limits           : XML.Parse_Limits;
      Collection_Limit : Positive;
      Result           : aliased in out Result_Type);

end Flyology.Object_Storage.S3.Strict_XML_Codecs;
