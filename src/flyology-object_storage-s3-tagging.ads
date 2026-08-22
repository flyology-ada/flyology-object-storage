with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;

--  Strict, bounded REST/XML boundaries for S3 object and bucket tagging.
package Flyology.Object_Storage.S3.Tagging is

   Malformed_Tagging : exception;
   Malformed_Tagging_Query : exception;
   Invalid_Tag : exception;

   Maximum_Document_Bytes : constant := 16 * 1_024;
   Maximum_Bucket_Document_Bytes : constant := 1_024 * 1_024;
   Maximum_Query_Bytes : constant := 8 * 1_024;

   type Tagging_Operation is
     (Put_Object_Tagging, Get_Object_Tagging, Delete_Object_Tagging);

   type Tagging_Query is record
      Has_Version_ID : Boolean := False;
      Version_ID     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Parse_Query
     (Query : String; Operation : Tagging_Operation) return Tagging_Query;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits) return Object_Tag_Set;

   function Serialize (Tags : Object_Tag_Set) return String;

   function Parse_Bucket
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set;

   --  Parse a bucket-tagging response from S3-compatible implementations.
   --  The official S3 namespace and an absent namespace are accepted;
   --  foreign namespaces and attributes remain invalid.
   function Parse_Bucket_Response
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set;

   function Serialize_Bucket (Value : Tags.Tag_Set) return String;

   --  Validate AWS's Unicode-character count and allowed repertoire.
   function Valid_S3_Tags (Tags : Object_Tag_Set) return Boolean;

end Flyology.Object_Storage.S3.Tagging;
