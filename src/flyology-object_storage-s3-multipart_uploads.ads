with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.XML;

--  Typed ListMultipartUploads REST/XML documents shared by clients and
--  servers.  The wire model is kept separate from uploaded-part documents so
--  each bounded SAX state machine remains small enough to audit.
package Flyology.Object_Storage.S3.Multipart_Uploads is

   --  Raised when a ListMultipartUploads result violates the modeled shape.
   Malformed_Upload_Listing : exception;
   --  Raised when a ListMultipartUploads query violates the modeled shape.
   Malformed_List_Request : exception;

   --  Decoded parameters for one ListMultipartUploads request.
   --  @field Delimiter Optional grouping delimiter
   --  @field URL_Encoding Whether encoding-type=url was requested
   --  @field Key_Marker Key marker for the requested page
   --  @field Max_Uploads Maximum number of entries requested
   --  @field Prefix Optional key prefix
   --  @field Upload_ID_Marker Upload identifier marker for the requested page
   type List_Multipart_Uploads_Request is record
      Delimiter        : Ada.Strings.Unbounded.Unbounded_String;
      URL_Encoding     : Boolean := False;
      Key_Marker       : Ada.Strings.Unbounded.Unbounded_String;
      Max_Uploads      : Core.Page_Size := Core.Page_Size'Last;
      Prefix           : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID_Marker : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Parse a bucket-level ListMultipartUploads query. The uploads marker is
   --  required, percent escapes are strict, '+' remains literal, duplicates
   --  and unknown fields are rejected, and max-uploads is in 1 .. 1_000.
   --  @param Query Raw ListMultipartUploads query string
   --  @return Decoded request parameters
   function Parse_List_Multipart_Uploads_Query
     (Query : String) return List_Multipart_Uploads_Request;

   --  One modeled multipart upload entry.
   --  @field Upload_ID Multipart upload identifier
   --  @field Key Object key
   --  @field Initiated Modeled initiation timestamp
   --  @field Storage_Class Optional modeled storage class
   --  @field Has_Owner Whether owner information is present
   --  @field Owner Modeled owner information
   --  @field Has_Initiator Whether initiator information is present
   --  @field Initiator Modeled initiator information
   --  @field Checksum_Algorithm Optional modeled checksum algorithm
   --  @field Checksum_Type Optional modeled checksum type
   type Upload_Entry is record
      Upload_ID          : Ada.Strings.Unbounded.Unbounded_String;
      Key                : Ada.Strings.Unbounded.Unbounded_String;
      Initiated          : Ada.Strings.Unbounded.Unbounded_String;
      Storage_Class      : Ada.Strings.Unbounded.Unbounded_String;
      Has_Owner          : Boolean := False;
      Owner              : Multipart.Multipart_Identity;
      Has_Initiator      : Boolean := False;
      Initiator          : Multipart.Multipart_Identity;
      Checksum_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Vector storage for modeled multipart upload entries.
   package Upload_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Upload_Entry);

   --  Collection of modeled multipart upload entries.
   subtype Upload_List is Upload_Vectors.Vector;

   --  Vector storage for modeled common prefixes.
   package Prefix_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   --  Collection of modeled common prefixes.
   subtype Prefix_List is Prefix_Vectors.Vector;

   --  All REST/XML body members in the pinned ListMultipartUploads output
   --  shape.  RequestCharged is an HTTP response header and belongs to the
   --  operation layer.
   --  @field Bucket Bucket name
   --  @field Key_Marker Request key marker returned in the result
   --  @field Upload_ID_Marker Request upload marker returned in the result
   --  @field Next_Key_Marker Key marker for the next result page
   --  @field Next_Upload_ID_Marker Upload marker for the next result page
   --  @field Prefix Modeled key prefix
   --  @field Delimiter Modeled grouping delimiter
   --  @field Max_Uploads Maximum number of entries for this page
   --  @field Is_Truncated Whether another result page is available
   --  @field Uploads Modeled multipart upload entries
   --  @field Common_Prefixes Modeled grouped key prefixes
   --  @field Encoding_Type Optional modeled encoding type
   type List_Multipart_Uploads_Result is record
      Bucket                : Ada.Strings.Unbounded.Unbounded_String;
      Key_Marker            : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID_Marker      : Ada.Strings.Unbounded.Unbounded_String;
      Next_Key_Marker       : Ada.Strings.Unbounded.Unbounded_String;
      Next_Upload_ID_Marker : Ada.Strings.Unbounded.Unbounded_String;
      Prefix                : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter             : Ada.Strings.Unbounded.Unbounded_String;
      Max_Uploads           : Core.Page_Size := 0;
      Is_Truncated          : Boolean := False;
      Uploads               : Upload_List;
      Common_Prefixes       : Prefix_List;
      Encoding_Type         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Decode through the shared entity-disabled, depth/element/text-bounded
   --  S3 XML boundary.  The result is validated before it is returned.
   --  @param Document ListMultipartUploads result XML
   --  @param Limits XML parsing limits
   --  @return Decoded ListMultipartUploads result body
   function Parse_List_Multipart_Uploads
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Multipart_Uploads_Result;

   --  Serialize one ListMultipartUploads result document.
   --  @param Value ListMultipartUploads result body to serialize
   --  @return Namespaced ListMultipartUploads result XML
   function Serialize_List_Multipart_Uploads
     (Value : List_Multipart_Uploads_Result) return String;

end Flyology.Object_Storage.S3.Multipart_Uploads;
