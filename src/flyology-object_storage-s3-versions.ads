with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.XML;

--  Strict typed ListObjectVersions REST/XML response documents.
package Flyology.Object_Storage.S3.Versions is

   --  Raised when a ListObjectVersions request query is malformed.
   Malformed_Version_Request : exception;
   --  Raised when a ListVersionsResult document or value is malformed.
   Malformed_Version_Listing : exception;

   --  Presence-preserving ListObjectVersions REST query.  Max_Keys uses the
   --  modeled S3 default when the wire member is absent.
   --  @field Delimiter Optional common-prefix delimiter
   --  @field Has_Delimiter Whether delimiter was present, including empty
   --  @field URL_Encoding Whether encoding-type=url was requested
   --  @field Key_Marker Exclusive key cursor
   --  @field Has_Key_Marker Whether key-marker was present, including empty
   --  @field Max_Keys Requested combined result bound
   --  @field Has_Max_Keys Whether max-keys was present
   --  @field Prefix Optional key prefix
   --  @field Has_Prefix Whether prefix was present, including empty
   --  @field Version_ID_Marker Exclusive generation cursor for Key_Marker
   --  @field Has_Version_ID_Marker Whether version-id-marker was present
   type List_Object_Versions_Request is record
      Delimiter                : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter            : Boolean := False;
      URL_Encoding             : Boolean := False;
      Key_Marker               : Ada.Strings.Unbounded.Unbounded_String;
      Has_Key_Marker           : Boolean := False;
      Max_Keys                 : Core.Page_Size := Core.Page_Size'Last;
      Has_Max_Keys             : Boolean := False;
      Prefix                   : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix               : Boolean := False;
      Version_ID_Marker        : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID_Marker    : Boolean := False;
   end record;

   --  Decode the exact ListObjectVersions query surface.  Duplicate,
   --  unsupported, malformed, and unpaired cursor members are rejected.
   --  The optional x-id member is accepted only as ListObjectVersions.
   --  @param Query Raw request-target query without the leading question mark
   --  @return Presence-preserving validated request
   function Parse_List_Object_Versions_Query
     (Query : String) return List_Object_Versions_Request;

   --  Every member in the pinned ObjectVersion response structure. Presence
   --  flags retain the distinction between an absent modeled member and its
   --  scalar default.
   type Object_Version is record
      Entity_Tag             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Entity_Tag         : Boolean := False;
      Checksum_Algorithms    : Listings.Checksum_Algorithm_List;
      Checksum_Type          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Checksum_Type      : Boolean := False;
      Size                   : Byte_Count := 0;
      Has_Size               : Boolean := False;
      Storage_Class          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Storage_Class      : Boolean := False;
      Key                    : Ada.Strings.Unbounded.Unbounded_String;
      Has_Key                : Boolean := False;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID         : Boolean := False;
      Is_Latest              : Boolean := False;
      Has_Is_Latest          : Boolean := False;
      Last_Modified          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Last_Modified      : Boolean := False;
      Has_Owner              : Boolean := False;
      Owner                  : Listings.Object_Owner;
      Has_Restore_Status     : Boolean := False;
      Restore_Status         : Listings.Object_Restore_Status;
   end record;

   package Object_Version_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Version);

   subtype Object_Version_List is Object_Version_Vectors.Vector;

   --  Every member in the pinned DeleteMarkerEntry response structure.
   type Delete_Marker is record
      Has_Owner         : Boolean := False;
      Owner             : Listings.Object_Owner;
      Key               : Ada.Strings.Unbounded.Unbounded_String;
      Has_Key           : Boolean := False;
      Version_ID        : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID    : Boolean := False;
      Is_Latest         : Boolean := False;
      Has_Is_Latest     : Boolean := False;
      Last_Modified     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Last_Modified : Boolean := False;
   end record;

   package Delete_Marker_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Delete_Marker);

   subtype Delete_Marker_List is Delete_Marker_Vectors.Vector;

   --  All 13 REST/XML body members in the pinned ListObjectVersions output.
   --  RequestCharged is an HTTP response header and belongs to the operation
   --  client result.
   type List_Object_Versions_Result is record
      Is_Truncated              : Boolean := False;
      Has_Is_Truncated          : Boolean := False;
      Key_Marker                : Ada.Strings.Unbounded.Unbounded_String;
      Has_Key_Marker            : Boolean := False;
      Version_ID_Marker         : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID_Marker     : Boolean := False;
      Next_Key_Marker           : Ada.Strings.Unbounded.Unbounded_String;
      Has_Next_Key_Marker       : Boolean := False;
      Next_Version_ID_Marker    : Ada.Strings.Unbounded.Unbounded_String;
      Has_Next_Version_ID_Marker : Boolean := False;
      Versions                  : Object_Version_List;
      Delete_Markers            : Delete_Marker_List;
      Name                      : Ada.Strings.Unbounded.Unbounded_String;
      Has_Name                  : Boolean := False;
      Prefix                    : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix                : Boolean := False;
      Delimiter                 : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter             : Boolean := False;
      Max_Keys                  : Core.Page_Size := 0;
      Has_Max_Keys              : Boolean := False;
      Common_Prefixes           : Listings.Prefix_List;
      Encoding_Type             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Encoding_Type         : Boolean := False;
   end record;

   --  Decode a ListVersionsResult document through the shared entity-disabled
   --  XML boundary. Unknown, duplicate, misplaced, incomplete, oversized, and
   --  cross-field-inconsistent members are rejected before return.
   function Parse_List_Object_Versions
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Object_Versions_Result;

   --  Encode one validated ListVersionsResult document.  Presence flags are
   --  preserved and all scalar content passes through the shared XML escape
   --  boundary.
   --  @param Value Complete typed response document
   --  @return UTF-8 XML document
   function Serialize_List_Object_Versions
     (Value : List_Object_Versions_Result) return String;

end Flyology.Object_Storage.S3.Versions;
