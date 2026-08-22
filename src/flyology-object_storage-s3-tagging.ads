with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict, bounded REST/XML and query boundary for S3 object tagging.
package Flyology.Object_Storage.S3.Tagging is

   Malformed_Tagging : exception;
   Malformed_Tagging_Query : exception;

   Maximum_Document_Bytes : constant := 16 * 1_024;
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

   --  Validate AWS's Unicode-character count and allowed repertoire.
   function Valid_S3_Tags (Tags : Object_Tag_Set) return Boolean;

end Flyology.Object_Storage.S3.Tagging;
