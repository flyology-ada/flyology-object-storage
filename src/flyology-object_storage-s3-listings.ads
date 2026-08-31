with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;

--  Typed ListObjects REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Listings is

   --  Raised when ListObjects response data is malformed.
   Malformed_Listing : exception;

   --  Raised when a ListObjects query is malformed or unsupported.
   Malformed_List_Request : exception;

   --  Parsed ListObjects v1 query parameters.
   --  @field Prefix Optional object-key prefix
   --  @field Has_Prefix Whether prefix was supplied
   --  @field Delimiter Optional grouping delimiter
   --  @field Has_Delimiter Whether delimiter was supplied
   --  @field Marker Optional exclusive object-key marker
   --  @field Has_Marker Whether marker was supplied
   --  @field Max_Keys Requested maximum result count
   --  @field Has_Max_Keys Whether max-keys was supplied
   --  @field URL_Encoding Whether encoding-type=url was requested
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
   --  @param Query Raw query bytes after the question mark
   --  @return Parsed bounded ListObjects v1 request
   function Parse_List_Objects_Query
     (Query : String) return List_Objects_Request;

   --  Decode one encoding-type=url response value. Escapes are strict and
   --  '+' is a literal byte, matching S3 query and listing rules.
   --  @param Value Percent-encoded listing response value
   --  @return Strictly decoded response bytes
   function Decode_URL_Value (Value : String) return String;

   --  Parsed ListObjectsV2 query parameters.
   --  @field Prefix Optional object-key prefix
   --  @field Delimiter Optional grouping delimiter
   --  @field Has_Delimiter Whether delimiter was supplied
   --  @field Continuation_Token Optional opaque continuation token
   --  @field Has_Continuation_Token Whether the token was supplied
   --  @field Start_After Optional exclusive starting object key
   --  @field Has_Start_After Whether start-after was supplied
   --  @field Max_Keys Requested maximum result count
   --  @field Fetch_Owner Whether object owners are requested
   --  @field Has_Fetch_Owner Whether fetch-owner was supplied
   --  @field URL_Encoding Whether encoding-type=url was requested
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
   --  @param Query Raw query bytes after the question mark
   --  @return Parsed bounded ListObjectsV2 request
   function Parse_List_Objects_V2_Query
     (Query : String) return List_Objects_V2_Request;

   --  Result of validating and decoding a continuation token.
   --  @field Valid Whether the token matches the request and envelope
   --  @field After Exclusive emitted-item cursor when valid
   type Continuation_Result is record
      Valid : Boolean := False;
      After : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Continuation tokens are opaque at the wire boundary and are bound to
   --  the bucket, prefix, delimiter, and emitted-item cursor.
   --  @param Bucket Bucket bound into the token
   --  @param Prefix Object-key prefix bound into the token
   --  @param Delimiter Grouping delimiter bound into the token
   --  @param After Exclusive emitted-item cursor
   --  @return Opaque continuation token bound to all four inputs
   function Encode_Continuation
     (Bucket, Prefix, Delimiter, After : String) return String;

   --  Decode and validate a continuation token against listing inputs.
   --  @param Token Candidate continuation token
   --  @param Bucket Expected bucket
   --  @param Prefix Expected object-key prefix
   --  @param Delimiter Expected grouping delimiter
   --  @return Validation result and decoded exclusive cursor
   function Decode_Continuation
     (Token, Bucket, Prefix, Delimiter : String)
      return Continuation_Result;

   --  Vector implementation used for listed checksum algorithm names.
   package Checksum_Algorithm_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   --  Ordered checksum algorithm names reported for one object.
   subtype Checksum_Algorithm_List is Checksum_Algorithm_Vectors.Vector;

   --  Optional owner structure reported for one listed object.
   --  @field Display_Name Modeled owner display name
   --  @field ID Owner identifier
   type Object_Owner is record
      Display_Name : Ada.Strings.Unbounded.Unbounded_String;
      ID           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional archive-restore details reported for one listed object.
   --  @field Has_Is_Restore_In_Progress Whether progress state is present
   --  @field Is_Restore_In_Progress Restore progress state when present
   --  @field Restore_Expiry_Date Optional modeled restore-expiry date
   type Object_Restore_Status is record
      Has_Is_Restore_In_Progress : Boolean := False;
      Is_Restore_In_Progress : Boolean := False;
      Restore_Expiry_Date    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Every member in the pinned S3 model's Object structure used by both
   --  ListObjects response versions. Presence flags preserve absent nested
   --  structures independently from their optional members.
   --  @field Key Object key
   --  @field Last_Modified Modeled last-modified timestamp
   --  @field Entity_Tag Modeled entity tag
   --  @field Checksum_Algorithms Reported checksum algorithm names
   --  @field Checksum_Type Optional modeled checksum type
   --  @field Size Object size in bytes
   --  @field Storage_Class Modeled storage class
   --  @field Has_Owner Whether the owner structure is present
   --  @field Owner Owner structure when present
   --  @field Has_Restore_Status Whether restore details are present
   --  @field Restore_Status Restore details when present
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

   --  Vector implementation used for listed object entries.
   package Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Object_Entry);

   --  Ordered list of object entries.
   subtype Object_List is Object_Vectors.Vector;

   --  Vector implementation used for listed common prefixes.
   package Prefix_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   --  Ordered list of common-prefix values.
   subtype Prefix_List is Prefix_Vectors.Vector;

   --  Decoded ListObjects v1 response.
   --  @field Name Bucket name
   --  @field Prefix Optional echoed object-key prefix
   --  @field Has_Prefix Whether Prefix is present
   --  @field Delimiter Optional echoed grouping delimiter
   --  @field Has_Delimiter Whether Delimiter is present
   --  @field Encoding_Type Optional echoed encoding type
   --  @field Has_Encoding_Type Whether Encoding_Type is present
   --  @field Marker Optional echoed request marker
   --  @field Has_Marker Whether Marker is present
   --  @field Next_Marker Next-page marker for a truncated delimited result
   --  @field Has_Next_Marker Whether Next_Marker is present
   --  @field Max_Keys Echoed maximum result count
   --  @field Is_Truncated Whether another result page remains
   --  @field Contents Ordered object entries
   --  @field Common_Prefixes Ordered collapsed prefix entries
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
   --  @param Document ListObjects v1 result XML
   --  @param Limits XML parsing limits
   --  @return Decoded and validated v1 result
   function Parse_List_Objects
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Objects_Result;

   --  Serialize one ListObjects v1 result document.
   --  @param Value Result value to serialize
   --  @return Namespaced ListObjects v1 result XML
   function Serialize_List_Objects
     (Value : List_Objects_Result) return String;

   --  Decoded ListObjectsV2 response.
   --  @field Name Bucket name
   --  @field Prefix Echoed object-key prefix, empty when absent
   --  @field Delimiter Optional echoed grouping delimiter
   --  @field Has_Delimiter Whether Delimiter is present
   --  @field Encoding_Type Optional echoed encoding type
   --  @field Has_Encoding_Type Whether Encoding_Type is present
   --  @field Continuation_Token Optional echoed continuation token
   --  @field Has_Continuation_Token Whether Continuation_Token is present
   --  @field Next_Continuation_Token Next-page token when Is_Truncated is true
   --  @field Has_Next_Continuation_Token Whether the next-page token
   --    is present
   --  @field Start_After Optional echoed exclusive starting key
   --  @field Has_Start_After Whether Start_After is present
   --  @field Key_Count Number of returned entries
   --  @field Max_Keys Echoed maximum result count
   --  @field Is_Truncated Whether another result page remains
   --  @field Contents Ordered object entries
   --  @field Common_Prefixes Ordered collapsed prefix entries
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

   --  Parse one bounded ListObjectsV2 result document.
   --  @param Document ListObjectsV2 result XML
   --  @param Limits XML parsing limits
   --  @return Decoded and validated v2 result
   function Parse_List_Objects_V2
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Objects_V2_Result;

   --  Serialize one ListObjectsV2 result document.
   --  @param Value Result value to serialize
   --  @return Namespaced ListObjectsV2 result XML
   function Serialize_List_Objects_V2
     (Value : List_Objects_V2_Result) return String;

end Flyology.Object_Storage.S3.Listings;
