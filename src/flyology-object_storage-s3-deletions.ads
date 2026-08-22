with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Typed, bounded REST/XML documents for S3 DeleteObjects.
package Flyology.Object_Storage.S3.Deletions is

   Malformed_Delete : exception;
   Maximum_Objects : constant := 1_000;
   Maximum_Version_ID_Length : constant := 1_024;
   Maximum_Document_Bytes : constant := 2 * 1_024 * 1_024;

   Malformed_Delete_Object_Request : exception;

   type Delete_Object_Request is record
      Has_Version_ID : Boolean := False;
      Version_ID     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse the exact DeleteObject query shape. Empty is the ordinary
   --  unversioned request; versionId and the optional SDK x-id are decoded
   --  strictly, bounded, unique, and no other parameter is accepted.
   function Parse_Delete_Object_Query
     (Query : String) return Delete_Object_Request;

   --  Shared bound for request queries, multi-delete entries, and response
   --  headers. Empty represents an absent optional version ID.
   function Valid_Version_ID (Item : String) return Boolean;

   type Object_Identifier is record
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Identifier);

   type Delete_Objects_Request is record
      Objects : Object_Vectors.Vector;
      Quiet   : Boolean := False;
   end record;

   function Parse_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Request;

   function Serialize_Request (Value : Delete_Objects_Request) return String;

   type Delete_Error is record
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Code       : Ada.Strings.Unbounded.Unbounded_String;
      Message    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Delete_Error_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Delete_Error);

   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Every modeled member of one DeleteObjects Deleted result entry.
   type Deleted_Object is record
      Key                      : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID               : Ada.Strings.Unbounded.Unbounded_String;
      Delete_Marker            : Optional_Boolean;
      Delete_Marker_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Deleted_Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Deleted_Object);

   type Delete_Objects_Result is record
      Deleted : Deleted_Object_Vectors.Vector;
      Errors  : Delete_Error_Vectors.Vector;
   end record;

   function Parse_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Result;

   function Serialize_Result (Value : Delete_Objects_Result) return String;

end Flyology.Object_Storage.S3.Deletions;
