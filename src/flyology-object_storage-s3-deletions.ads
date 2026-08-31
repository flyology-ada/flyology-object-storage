with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Typed, bounded REST/XML documents for S3 DeleteObjects.
package Flyology.Object_Storage.S3.Deletions is

   --  Raised when a DeleteObjects document violates the modeled shape.
   Malformed_Delete : exception;
   --  Maximum number of entries in one DeleteObjects document.
   Maximum_Objects : constant := 1_000;
   --  Maximum accepted version identifier length.
   Maximum_Version_ID_Length : constant := 1_024;
   --  Maximum serialized DeleteObjects request length in bytes.
   Maximum_Document_Bytes : constant := 2 * 1_024 * 1_024;
   --  Element ceiling for a maximum-size DeleteObjects request.
   Maximum_Request_Elements : constant := 2 + 6 * Maximum_Objects;

   --  Raised when a DeleteObject query violates the modeled shape.
   Malformed_Delete_Object_Request : exception;

   --  Decoded version selection for one DeleteObject request.
   --  @field Has_Version_ID Whether an explicit version was selected
   --  @field Version_ID Exact selected version identifier, when present
   type Delete_Object_Request is record
      Has_Version_ID : Boolean := False;
      Version_ID     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse the exact DeleteObject query shape. Empty is the ordinary
   --  unversioned request; versionId and the optional SDK x-id are decoded
   --  strictly, bounded, unique, and no other parameter is accepted.
   --  @param Query Raw DeleteObject query string
   --  @return Decoded version selection
   function Parse_Delete_Object_Query
     (Query : String) return Delete_Object_Request;

   --  Shared bound for request queries, multi-delete entries, and response
   --  headers. Empty represents an absent optional version ID.
   --  @param Item Version identifier to validate
   --  @return True when the value is bounded and contains no NUL byte
   function Valid_Version_ID (Item : String) return Boolean;

   --  One modeled DeleteObjects request entry.
   --  @field Key Exact object key
   --  @field Version_ID Optional exact version identifier
   --  @field Has_ETag Whether an entity-tag condition is present
   --  @field ETag Exact entity-tag condition, when present
   --  @field Has_Last_Modified_Time Whether a time condition is present
   --  @field Last_Modified_Time Exact time condition, when present
   --  @field Has_Size Whether a size condition is present
   --  @field Size Exact byte-count condition, when present
   type Object_Identifier is record
      Key                    : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      Has_ETag               : Boolean := False;
      ETag                   : Ada.Strings.Unbounded.Unbounded_String;
      Has_Last_Modified_Time : Boolean := False;
      Last_Modified_Time     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Size               : Boolean := False;
      Size                   : Byte_Count := 0;
   end record;

   --  Vector storage for modeled DeleteObjects request entries.
   package Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Identifier);

   --  One modeled DeleteObjects request body.
   --  @field Objects Object identifiers to delete
   --  @field Quiet Whether successful entries are omitted from the result
   type Delete_Objects_Request is record
      Objects : Object_Vectors.Vector;
      Quiet   : Boolean := False;
   end record;

   --  Parse one bounded DeleteObjects request document.
   --  @param Document DeleteObjects request XML
   --  @param Limits XML parsing limits
   --  @return Decoded DeleteObjects request body
   function Parse_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Request;

   --  Serialize one DeleteObjects request document.
   --  @param Value DeleteObjects request body to serialize
   --  @return Namespaced DeleteObjects request XML
   function Serialize_Request (Value : Delete_Objects_Request) return String;

   --  One modeled DeleteObjects error entry.
   --  @field Key Exact object key
   --  @field Version_ID Optional exact version identifier
   --  @field Code S3 error code
   --  @field Message Modeled S3 error message
   type Delete_Error is record
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Code       : Ada.Strings.Unbounded.Unbounded_String;
      Message    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Vector storage for modeled DeleteObjects error entries.
   package Delete_Error_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Delete_Error);

   --  Presence-preserving modeled Boolean value.
   --  @field Is_Set Whether the source member is present
   --  @field Value Decoded value when present
   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Every modeled member of one DeleteObjects Deleted result entry.
   --  @field Key Exact object key
   --  @field Version_ID Optional exact version identifier
   --  @field Delete_Marker Presence-preserving delete-marker value
   --  @field Delete_Marker_Version_ID Optional delete-marker version
   type Deleted_Object is record
      Key                      : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID               : Ada.Strings.Unbounded.Unbounded_String;
      Delete_Marker            : Optional_Boolean;
      Delete_Marker_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Vector storage for modeled successful deletion entries.
   package Deleted_Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Deleted_Object);

   --  One modeled DeleteObjects result body.
   --  @field Deleted Successful deletion entries
   --  @field Errors Per-object error entries
   type Delete_Objects_Result is record
      Deleted : Deleted_Object_Vectors.Vector;
      Errors  : Delete_Error_Vectors.Vector;
   end record;

   --  Parse one bounded DeleteObjects result document.
   --  @param Document DeleteObjects result XML
   --  @param Limits XML parsing limits
   --  @return Decoded DeleteObjects result body
   function Parse_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Result;

   --  Serialize one DeleteObjects result document.
   --  @param Value DeleteObjects result body to serialize
   --  @return Namespaced DeleteObjects result XML
   function Serialize_Result (Value : Delete_Objects_Result) return String;

end Flyology.Object_Storage.S3.Deletions;
