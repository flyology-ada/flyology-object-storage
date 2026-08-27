with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  @exclude
--  Internal bounded XML writer for generated S3 request codecs. Callers own
--  every resource limit; this package supplies no defaults or wire policy.
package Flyology.Object_Storage.S3.XML_Writers is

   Encoding_Error : exception;

   type Writer is limited private;

   procedure Initialize
     (Item   : out Writer;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits);

   procedure Start_Document
     (Item          : in out Writer;
      Root_Name     : String;
      Namespace_URI : String);

   procedure Start_Element (Item : in out Writer; Name : String);

   procedure End_Element (Item : in out Writer; Name : String);

   procedure Empty_Element (Item : in out Writer; Name : String);

   procedure Text_Element
     (Item : in out Writer;
      Name : String;
      Text : String);

   procedure Attribute
     (Item          : in out Writer;
      Name          : String;
      Value         : String;
      Namespace_URI : String;
      Prefix        : String);

   function Finish (Item : in out Writer; Root_Name : String) return String;

private

   type Writer is limited record
      Limits        : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Data          : Ada.Strings.Unbounded.Unbounded_String;
      Depth         : Natural;
      Elements      : Natural;
      Text_Bytes    : Natural;
      Start_Is_Open : Boolean;
      Started       : Boolean;
      Finished      : Boolean;
   end record;

end Flyology.Object_Storage.S3.XML_Writers;
