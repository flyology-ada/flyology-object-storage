with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.XML;

--  Typed ListMultipartUploads REST/XML documents shared by clients and
--  servers.  The wire model is kept separate from uploaded-part documents so
--  each bounded SAX state machine remains small enough to audit.
package Flyology.Object_Storage.S3.Multipart_Uploads is

   Malformed_Upload_Listing : exception;
   Malformed_List_Request : exception;

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
   function Parse_List_Multipart_Uploads_Query
     (Query : String) return List_Multipart_Uploads_Request;

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

   package Upload_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Upload_Entry);

   subtype Upload_List is Upload_Vectors.Vector;

   package Prefix_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   subtype Prefix_List is Prefix_Vectors.Vector;

   --  All REST/XML body members in the pinned ListMultipartUploads output
   --  shape.  RequestCharged is an HTTP response header and belongs to the
   --  operation layer.
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
   function Parse_List_Multipart_Uploads
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Multipart_Uploads_Result;

   function Serialize_List_Multipart_Uploads
     (Value : List_Multipart_Uploads_Result) return String;

end Flyology.Object_Storage.S3.Multipart_Uploads;
