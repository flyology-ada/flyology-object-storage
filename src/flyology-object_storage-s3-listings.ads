with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Typed ListObjects REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Listings is

   Malformed_Listing : exception;
   Malformed_List_Request : exception;

   type List_Objects_Request is record
      Prefix       : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix   : Boolean := False;
      Delimiter    : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter : Boolean := False;
      Marker       : Ada.Strings.Unbounded.Unbounded_String;
      Has_Marker   : Boolean := False;
      Max_Keys     : Core.Page_Size := Core.Page_Size'Last;
      Has_Max_Keys : Boolean := False;
      URL_Encoding : Boolean := False;
   end record;

   --  Parse the raw ListObjects v1 query bytes after '?'. An empty query is a
   --  valid request. Percent escapes are strict, '+' remains literal,
   --  duplicates and unsupported parameters are rejected, and an optional
   --  x-id must identify ListObjects.
   function Parse_List_Objects_Query
     (Query : String) return List_Objects_Request;

   --  Decode one encoding-type=url response value. Escapes are strict and
   --  '+' is a literal byte, matching S3 query and listing rules.
   function Decode_URL_Value (Value : String) return String;

   type List_Objects_V2_Request is record
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter      : Boolean := False;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Start_After        : Ada.Strings.Unbounded.Unbounded_String;
      Has_Start_After    : Boolean := False;
      Max_Keys           : Core.Page_Size := Core.Page_Size'Last;
      Fetch_Owner        : Boolean := False;
      Has_Fetch_Owner    : Boolean := False;
      URL_Encoding       : Boolean := False;
   end record;

   --  Parse the raw query bytes after '?'. Percent escapes are strict, '+'
   --  remains literal, duplicates and unsupported parameters are rejected,
   --  and list-type=2 is required.
   function Parse_List_Objects_V2_Query
     (Query : String) return List_Objects_V2_Request;

   type Continuation_Result is record
      Valid : Boolean := False;
      After : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Continuation tokens are opaque at the wire boundary and are bound to
   --  the bucket, prefix, delimiter, and emitted-item cursor.
   function Encode_Continuation
     (Bucket, Prefix, Delimiter, After : String) return String;

   function Decode_Continuation
     (Token, Bucket, Prefix, Delimiter : String)
      return Continuation_Result;

   package Checksum_Algorithm_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   subtype Checksum_Algorithm_List is Checksum_Algorithm_Vectors.Vector;

   type Object_Owner is record
      Display_Name : Ada.Strings.Unbounded.Unbounded_String;
      ID           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Object_Restore_Status is record
      Has_Is_Restore_In_Progress : Boolean := False;
      Is_Restore_In_Progress : Boolean := False;
      Restore_Expiry_Date    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Every member in the pinned S3 model's Object structure used by both
   --  ListObjects response versions. Presence flags preserve absent nested
   --  structures independently from their optional members.
   type Object_Entry is record
      Key                 : Ada.Strings.Unbounded.Unbounded_String;
      Last_Modified       : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithms : Checksum_Algorithm_List;
      Checksum_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Size                : Byte_Count := 0;
      Storage_Class       : Ada.Strings.Unbounded.Unbounded_String;
      Has_Owner           : Boolean := False;
      Owner               : Object_Owner;
      Has_Restore_Status  : Boolean := False;
      Restore_Status      : Object_Restore_Status;
   end record;

   package Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Entry);

   subtype Object_List is Object_Vectors.Vector;

   package Prefix_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   subtype Prefix_List is Prefix_Vectors.Vector;

   type List_Objects_Result is record
      Name            : Ada.Strings.Unbounded.Unbounded_String;
      Prefix          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix      : Boolean := False;
      Delimiter       : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter   : Boolean := False;
      Encoding_Type   : Ada.Strings.Unbounded.Unbounded_String;
      Has_Encoding_Type : Boolean := False;
      Marker          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Marker      : Boolean := False;
      Next_Marker     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Next_Marker : Boolean := False;
      Max_Keys        : Natural := 0;
      Is_Truncated    : Boolean := False;
      Contents        : Object_List;
      Common_Prefixes : Prefix_List;
   end record;

   --  Decode a ListObjects v1 REST/XML response through the bounded shared
   --  S3 XML boundary. Required scalars, counts, object entries, delimiter
   --  pagination, and encoding-type semantics are validated before return.
   function Parse_List_Objects
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Objects_Result;

   function Serialize_List_Objects
     (Value : List_Objects_Result) return String;

   type List_Objects_V2_Result is record
      Name                    : Ada.Strings.Unbounded.Unbounded_String;
      Prefix                  : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter               : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter           : Boolean := False;
      Encoding_Type           : Ada.Strings.Unbounded.Unbounded_String;
      Has_Encoding_Type       : Boolean := False;
      Continuation_Token      : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token  : Boolean := False;
      Next_Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Next_Continuation_Token : Boolean := False;
      Start_After             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Start_After         : Boolean := False;
      Key_Count               : Natural := 0;
      Max_Keys                : Natural := 0;
      Is_Truncated            : Boolean := False;
      Contents                : Object_List;
      Common_Prefixes         : Prefix_List;
   end record;

   function Parse_List_Objects_V2
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Objects_V2_Result;

   function Serialize_List_Objects_V2
     (Value : List_Objects_V2_Result) return String;

end Flyology.Object_Storage.S3.Listings;
