with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Flyology.Buffers;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.Analytics;
with Flyology.Object_Storage.S3.Annotations;
with Flyology.Object_Storage.S3.Intelligent_Tiering;
with Flyology.Object_Storage.S3.Inventory;
with Flyology.Object_Storage.S3.Logging;
with Flyology.Object_Storage.S3.Website;
with Flyology.Object_Storage.S3.Copies;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Encryption;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.Metadata_Configurations;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.Metrics;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Notifications;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.Replication;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;

--  Prepared model-driven S3 operations over a caller-owned Flyology client.
package Flyology.Object_Storage.Client.Low_Level is

   --  Raised when supplied request inputs or a prepared operation are invalid.
   Invalid_Request : exception;

   --  Supported S3 request-target addressing forms.
   --  @enum Path_Style Bucket name carried in the request path
   --  @enum Virtual_Hosted_Style Bucket name required in the origin authority
   type Addressing_Style is (Path_Style, Virtual_Hosted_Style);

   --  Signing identity for prepared S3 requests.
   type Credentials is limited private;

   --  Construct one signing identity.
   --  @param Access_Key Access-key identifier
   --  @param Secret_Key Secret signing key
   --  @param Session_Token Optional session token
   --  @return Retained signing identity
   function Make_Credentials
     (Access_Key, Secret_Key : String;
      Session_Token         : String := "") return Credentials;

   --  Every non-bucket member in the pinned ListObjects v1 input shape.
   --  Include_Restore_Status represents the model's sole
   --  OptionalObjectAttributes list value, RestoreStatus.
   --  @field Prefix Requested key prefix
   --  @field Has_Prefix Whether Prefix is present even when empty
   --  @field Delimiter Requested grouping delimiter
   --  @field Has_Delimiter Whether Delimiter is present even when empty
   --  @field Marker Key after which listing starts
   --  @field Has_Marker Whether Marker is present even when empty
   --  @field Max_Keys Requested maximum page size
   --  @field Has_Max_Keys Whether Max_Keys is present
   --  @field URL_Encoding Whether URL encoding is requested
   --  @field Request_Payer Request-payer header value
   --  @field Expected_Bucket_Owner Expected bucket-owner identifier
   --  @field Include_Restore_Status Whether restore status is requested
   type List_Objects_Parameters is record
      Prefix                  : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix              : Boolean := False;
      Delimiter               : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter           : Boolean := False;
      Marker                  : Ada.Strings.Unbounded.Unbounded_String;
      Has_Marker              : Boolean := False;
      Max_Keys                : S3.Core.Page_Size := 1_000;
      Has_Max_Keys            : Boolean := True;
      URL_Encoding            : Boolean := False;
      Request_Payer           : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner   : Ada.Strings.Unbounded.Unbounded_String;
      Include_Restore_Status  : Boolean := False;
   end record;

   --  Complete non-bucket ListObjectsV2 request controls.
   --  @field Prefix Requested key prefix
   --  @field Delimiter Requested grouping delimiter
   --  @field Continuation_Token Opaque listing continuation token
   --  @field Has_Continuation_Token Whether presence includes an empty token
   --  @field Start_After Key after which listing starts
   --  @field Max_Keys Requested maximum page size
   --  @field Fetch_Owner Whether owner data is requested
   --  @field Has_Fetch_Owner Whether Fetch_Owner is present even when false
   --  @field URL_Encoding Whether URL encoding is requested
   --  @field Request_Payer Request-payer header value
   --  @field Expected_Bucket_Owner Expected bucket-owner identifier
   --  @field Include_Restore_Status Whether restore status is requested
   type List_Objects_V2_Parameters is record
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter          : Ada.Strings.Unbounded.Unbounded_String;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Start_After        : Ada.Strings.Unbounded.Unbounded_String;
      Max_Keys           : S3.Core.Page_Size := 1_000;
      Fetch_Owner        : Boolean := False;
      Has_Fetch_Owner    : Boolean := False;
      URL_Encoding       : Boolean := False;
      Request_Payer      : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Include_Restore_Status : Boolean := False;
   end record;

   --  Prepared HTTP request and signing state.
   type Prepared_Request is private;

   --  Optional boolean wire value that preserves absent versus explicit false.
   --  @field Is_Set Whether the wire value is present
   --  @field Value Present boolean value
   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Optional nonnegative 64-bit byte count.
   --  @field Is_Set Whether the byte count is present
   --  @field Value Present byte count
   type Optional_Byte_Count is record
      Is_Set : Boolean := False;
      Value  : Byte_Count := 0;
   end record;

   --  Optional natural-number wire value.
   --  @field Is_Set Whether the number is present
   --  @field Value Present natural-number value
   type Optional_Natural is record
      Is_Set : Boolean := False;
      Value  : Natural := 0;
   end record;

   --  Optional modeled multipart part number.
   --  @field Is_Set Whether the part number is present
   --  @field Value Present part number
   type Optional_Part_Number is record
      Is_Set : Boolean := False;
      Value  : S3.Core.Part_Number := S3.Core.Part_Number'First;
   end record;

   --  Return the prepared HTTP request target.
   --  @param Item Prepared request
   --  @return Exact request-target text
   function Target (Item : Prepared_Request) return String;
   --  Return the prepared HTTP authority.
   --  @param Item Prepared request
   --  @return Exact authority text
   function Authority (Item : Prepared_Request) return String;
   --  Return the SigV4 canonical request.
   --  @param Item Prepared request
   --  @return Exact canonical-request text
   function Canonical_Request (Item : Prepared_Request) return String;
   --  Return the signed-header inventory.
   --  @param Item Prepared request
   --  @return Exact signed-header text
   function Signed_Headers (Item : Prepared_Request) return String;

   --  One top-level member supplied to the generated model-driven request
   --  projector. Map_Key is used only by `headers` map members such as S3
   --  user metadata. Body members are represented by the raw REST/XML
   --  payload parameters of Prepare_Model_Request.
   --  @field Member_Name Modeled top-level member name
   --  @field Map_Key Header-map key when the member is a map
   --  @field Value Modeled member value before request encoding
   type Model_Value is record
      Member_Name : Ada.Strings.Unbounded.Unbounded_String;
      Map_Key     : Ada.Strings.Unbounded.Unbounded_String;
      Value       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Ordered top-level values for model-driven request preparation.
   type Model_Value_Array is array (Positive range <>) of Model_Value;

   --  Empty model-value inventory.
   No_Model_Values : constant Model_Value_Array (1 .. 0) :=
     (others => <>);

   --  Prepare any operation in the pinned 116-operation S3 model. The
   --  projector validates member names, locations, required top-level
   --  members, duplicate scalar members, header-map keys, addressing, and
   --  the signed payload hash. Structured body serialization remains a
   --  separate codec concern; Payload_Is_Set distinguishes an absent body
   --  from an explicitly empty REST/XML or blob payload.
   --  @param Operation Pinned S3 operation
   --  @param Origin Exact configured HTTP origin
   --  @param Style Path or virtual-hosted addressing
   --  @param Values Top-level modeled member values
   --  @param Payload Exact request-body bytes
   --  @param Payload_Is_Set Whether the request body is present
   --  @param Payload_SHA256 Optional explicit payload hash or UNSIGNED-PAYLOAD
   --  @param Identity Signing credentials
   --  @param Region SigV4 region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Prepared model-driven request
   function Prepare_Model_Request
     (Operation      : S3.Model.Operation_Id;
      Origin         : Flyology.HTTP.Origin;
      Style          : Addressing_Style;
      Values         : Model_Value_Array;
      Payload        : String;
      Payload_Is_Set : Boolean;
      Payload_SHA256 : String;
      Identity       : Credentials;
      Region         : String;
      Timestamp      : String) return Prepared_Request;

   --  Prepare a generated-model request whose body will be borrowed from a
   --  Flyology HTTP Request_Body_Source during Execute_Model_Request. The
   --  operation must model a request body. Payload_SHA256 must be an exact
   --  lowercase digest, or UNSIGNED-PAYLOAD over HTTPS. Omit the modeled
   --  ContentLength member: the source's Declared_Length owns HTTP framing.
   --  @param Operation Pinned S3 operation
   --  @param Origin Exact configured HTTP client origin
   --  @param Style Path or virtual-hosted addressing
   --  @param Values Non-body top-level modeled members
   --  @param Payload_SHA256 Digest of the future source or UNSIGNED-PAYLOAD
   --  @param Identity Signing credentials retained only for this call
   --  @param Region SigV4 region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Prepared metadata with no retained body bytes
   function Prepare_Model_Streaming_Request
     (Operation      : S3.Model.Operation_Id;
      Origin         : Flyology.HTTP.Origin;
      Style          : Addressing_Style;
      Values         : Model_Value_Array;
      Payload_SHA256 : String;
      Identity       : Credentials;
      Region         : String;
      Timestamp      : String) return Prepared_Request;

   --  Execute a prepared generated-model request without retaining its
   --  response body. The returned Flyology response preserves status,
   --  repeated headers, trailers, negotiated protocol, the original
   --  exchange deadline, and streaming body backpressure for operation-
   --  specific decoders and sinks.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Request produced by Prepare_Model_Request
   --  @param Timeout Whole-exchange timeout, including later response reads
   --  @param Token Optional cancellation source
   --  @return Limited streaming HTTP response
   --  @exception Invalid_Request Prepared is not model-driven
   function Execute_Model_Request
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response;

   --  Execute a generated-model request while borrowing its body source.
   --  Source is never retained after this function returns; its declared
   --  length controls HTTP framing and its read exceptions propagate after
   --  the affected exchange is discarded.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Request from Prepare_Model_Streaming_Request
   --  @param Source Borrowed streaming request body
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @return Limited streaming HTTP response
   function Execute_Model_Request
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response;

   --  Build and sign one bodyless ListObjects v1 request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose objects are requested
   --  @param Parameters Presence-preserving filters, cursor, and headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared ListObjects v1 request
   function Prepare_List_Objects
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request;

   --  Raised when a received S3 response violates its modeled contract.
   Invalid_Response : exception;

   --  Terminal object-listing response classification.
   --  @enum Listed The decoded listing is present
   --  @enum Rejected A structured S3 rejection is present
   type List_Outcome_Kind is (Listed, Rejected);

   --  Every member in the pinned ListObjects v1 output shape. The XML
   --  members are grouped in Listing; RequestCharged is an HTTP header.
   --  @field Listing Decoded ListObjects v1 page
   --  @field Request_Charged Optional requester-pays response value
   type List_Objects_Result is record
      Listing         : S3.Listings.List_Objects_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Completed ListObjects v1 response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful listing result
   --  @field Error Structured S3 rejection
   type List_Objects_Outcome
     (Kind : List_Outcome_Kind := Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Listed =>
            Result : List_Objects_Result;
         when Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded ListObjects v1 HTTP result.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_Charged Optional requester-pays response value
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed page or structured S3 rejection
   function Decode_List_Objects_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_Outcome;

   --  Decode one complete ListObjects v1 HTTP response. Physical singleton
   --  headers, Requester Pays consistency, and the successful response's
   --  echoed bucket, scope, marker, maximum, and encoding are bound to the
   --  exact prepared request before the page is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared ListObjects v1 request
   --  @param Limits Bounded XML parser limits
   --  @return Typed page or S3 rejection
   --  @exception Invalid_Request Prepared is not ListObjects v1
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_List_Objects_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_Outcome;

   --  Execute one prepared ListObjects v1 request and decode its response.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared ListObjects v1 request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed page or structured S3 rejection
   function Execute_List_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_Outcome;

   --  Build and sign one bodyless ListObjectsV2 request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose objects are requested
   --  @param Parameters Filters, cursor, maximum, and request headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared ListObjectsV2 request
   function Prepare_List_Objects_V2
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_V2_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request;

   --  Completed ListObjectsV2 response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Listing Successful decoded page
   --  @field Request_Charged Optional requester-pays response value
   --  @field Error Structured S3 rejection
   type List_Objects_V2_Outcome
     (Kind : List_Outcome_Kind := Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Listed =>
            Listing : S3.Listings.List_Objects_V2_Result;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded ListObjectsV2 HTTP result.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Request_Charged Optional requester-pays response value
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed page or structured S3 rejection
   function Decode_List_Objects_V2_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Request_Charged : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome;

   --  Decode one complete ListObjectsV2 HTTP response. Physical singleton
   --  headers, Requester Pays consistency, and the successful response's
   --  echoed bucket, scope, cursor, maximum, and encoding are bound to the
   --  exact prepared request before the page is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared ListObjectsV2 request
   --  @param Limits Bounded XML parser limits
   --  @return Typed page or S3 rejection
   --  @exception Invalid_Request Prepared is not ListObjectsV2
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_List_Objects_V2_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome;

   --  Execute one prepared ListObjectsV2 request and decode its response.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared ListObjectsV2 request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed page or structured S3 rejection
   function Execute_List_Objects_V2
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome;

   --  Every non-bucket member in the pinned ListObjectVersions request.
   --  Presence flags preserve explicit empty markers and filters. The model's
   --  OptionalObjectAttributes list currently has one value, RestoreStatus.
   --  @field Delimiter Delimiter value when present
   --  @field Has_Delimiter Whether Delimiter is present
   --  @field URL_Encoding Whether URL encoding is requested
   --  @field Key_Marker Key cursor value when present
   --  @field Has_Key_Marker Whether Key_Marker is present
   --  @field Max_Keys Requested page maximum when present
   --  @field Has_Max_Keys Whether Max_Keys is present
   --  @field Prefix Prefix filter when present
   --  @field Has_Prefix Whether Prefix is present
   --  @field Version_ID_Marker Version cursor value when present
   --  @field Has_Version_ID_Marker Whether Version_ID_Marker is present
   --  @field Expected_Bucket_Owner Optional bucket-owner precondition
   --  @field Request_Payer Optional requester-pays request value
   --  @field Include_Restore_Status Whether restore status is requested
   type List_Object_Versions_Parameters is record
      Delimiter               : Ada.Strings.Unbounded.Unbounded_String;
      Has_Delimiter           : Boolean := False;
      URL_Encoding            : Boolean := False;
      Key_Marker              : Ada.Strings.Unbounded.Unbounded_String;
      Has_Key_Marker          : Boolean := False;
      Max_Keys                : S3.Core.Page_Size := 1_000;
      Has_Max_Keys            : Boolean := True;
      Prefix                  : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix              : Boolean := False;
      Version_ID_Marker       : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID_Marker   : Boolean := False;
      Expected_Bucket_Owner   : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer           : Ada.Strings.Unbounded.Unbounded_String;
      Include_Restore_Status  : Boolean := False;
   end record;

   --  Build and sign one bodyless ListObjectVersions request. A present
   --  Version_ID_Marker requires a present Key_Marker. When Has_Max_Keys is
   --  false, the request omits max-keys and response binding uses the modeled
   --  S3 default of Page_Size'Last.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose versions are requested
   --  @param Parameters Presence-preserving filters, cursor, and headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request with response-binding context
   function Prepare_List_Object_Versions
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Object_Versions_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request;

   --  Every output member in the pinned ListObjectVersions response. The 13
   --  XML members are grouped in Listing; RequestCharged is its sole header.
   --  @field Listing Decoded ListObjectVersions page
   --  @field Request_Charged Optional requester-pays response value
   type List_Object_Versions_Result is record
      Listing         : S3.Versions.List_Object_Versions_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Completed ListObjectVersions response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful version-listing result
   --  @field Error Structured S3 rejection
   type List_Object_Versions_Outcome
     (Kind : List_Outcome_Kind := Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Listed =>
            Result : List_Object_Versions_Result;
         when Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded ListObjectVersions HTTP result. This helper
   --  validates payload structure and typed S3 errors but cannot bind success
   --  echoes to a prepared request; Execute_List_Object_Versions performs that
   --  additional check.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_Charged Optional modeled response header
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed page or structured S3 rejection
   function Decode_List_Object_Versions_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Object_Versions_Outcome;

   --  Decode one complete ListObjectVersions HTTP response and bind every
   --  successful echoed scope/cursor field plus requester-pays admission to
   --  the exact prepared request.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared ListObjectVersions request
   --  @param Limits Bounded XML parser limits
   --  @return Typed version page or S3 rejection
   --  @exception Invalid_Request Prepared is not ListObjectVersions
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_List_Object_Versions_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Object_Versions_Outcome;

   --  Execute one prepared synchronous request, bind the returned page to its
   --  bucket/filter/cursor context, and release the response before return.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_List_Object_Versions
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed page or structured S3 rejection
   function Execute_List_Object_Versions
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Object_Versions_Outcome;

   --  Every member of the pinned ListBuckets request shape. Presence flags
   --  preserve omission independently from default or empty scalar values.
   --  @field Max_Buckets Requested page maximum when present
   --  @field Has_Max_Buckets Whether Max_Buckets is present
   --  @field Continuation_Token Opaque page cursor when present
   --  @field Has_Continuation_Token Whether presence includes an empty token
   --  @field Prefix Bucket-name prefix when present
   --  @field Has_Prefix Whether presence includes an empty prefix
   --  @field Bucket_Region Optional bucket-region filter
   type List_Buckets_Parameters is record
      Max_Buckets        : S3.Buckets.Max_Buckets_Value := 10_000;
      Has_Max_Buckets    : Boolean := False;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix         : Boolean := False;
      Bucket_Region      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one bodyless ListBuckets request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style S3 addressing style
   --  @param Parameters Presence-preserving page controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared ListBuckets request
   function Prepare_List_Buckets
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Parameters : List_Buckets_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal ListBuckets response classification.
   --  @enum Buckets_Listed The decoded bucket page is present
   --  @enum List_Buckets_Rejected A structured S3 rejection is present
   type List_Buckets_Outcome_Kind is
     (Buckets_Listed, List_Buckets_Rejected);

   --  Completed ListBuckets response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful decoded bucket page
   --  @field Error Structured S3 rejection
   type List_Buckets_Outcome
     (Kind : List_Buckets_Outcome_Kind := List_Buckets_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Buckets_Listed =>
            Result : S3.Buckets.List_Buckets_Result;
         when List_Buckets_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded ListBuckets HTTP result.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier for an S3 rejection
   --  @param Host_ID Optional host identifier for an S3 rejection
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed bucket page or structured S3 rejection
   function Decode_List_Buckets_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;

   --  Decode one complete ListBuckets response and bind the bounded page to
   --  the exact prefix, region, and maximum of its prepared request.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared ListBuckets request
   --  @param Limits Bounded XML parser limits
   --  @return Typed bucket page or S3 rejection
   --  @exception Invalid_Request Prepared is not ListBuckets
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_List_Buckets_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;

   --  Execute one prepared ListBuckets request and bind its response.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared ListBuckets request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Typed bucket page or structured S3 rejection
   function Execute_List_Buckets
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;

   --  Every input member in the pinned CreateBucket request shape.
   --  @field ACL Optional canned access-control policy
   --  @field Configuration Complete create-bucket configuration
   --  @field Grant_Full_Control Optional full-control grant header
   --  @field Grant_Read Optional read grant header
   --  @field Grant_Read_ACP Optional access-control read grant header
   --  @field Grant_Write Optional write grant header
   --  @field Grant_Write_ACP Optional access-control write grant header
   --  @field Object_Lock_Enabled Optional object-lock enablement flag
   --  @field Object_Ownership Optional object-ownership selector
   --  @field Bucket_Namespace Optional bucket-namespace selector
   type Create_Bucket_Parameters is record
      ACL                     : Ada.Strings.Unbounded.Unbounded_String;
      Configuration           : S3.Buckets.Create_Bucket_Configuration;
      Grant_Full_Control      : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read              : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read_ACP          : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write             : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write_ACP         : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Enabled     : Optional_Boolean;
      Object_Ownership        : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Namespace        : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one CreateBucket request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Exact bucket name to create
   --  @param Parameters Configuration and optional request headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared request with its serialized one-shot body
   function Prepare_Create_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Create_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every output member in the pinned CreateBucket response shape.
   --  @field Location Optional Location response-header value
   --  @field Bucket_ARN Optional bucket-ARN response-header value
   type Create_Bucket_Result is record
      Location   : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_ARN : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal CreateBucket response classification.
   --  @enum Bucket_Created The modeled creation result is present
   --  @enum Create_Bucket_Rejected A structured S3 rejection is present
   type Create_Bucket_Outcome_Kind is
     (Bucket_Created, Create_Bucket_Rejected);

   --  Completed CreateBucket response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful creation metadata
   --  @field Error Structured S3 rejection
   type Create_Bucket_Outcome
     (Kind : Create_Bucket_Outcome_Kind := Create_Bucket_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Created =>
            Result : Create_Bucket_Result;
         when Create_Bucket_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one CreateBucket status, whitespace-only success body, and
   --  modeled header set.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled CreateBucket response headers
   --  @param Request_ID Optional request identifier for an S3 rejection
   --  @param Host_ID Optional host identifier for an S3 rejection
   --  @param Limits Bounded S3 error parsing limits
   --  @return Modeled creation result or structured S3 rejection
   function Decode_Create_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Create_Bucket_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Bucket_Outcome;

   --  Decode one fully received CreateBucket exchange. Physical singleton
   --  response headers are validated identically for synchronous and
   --  composable callers.
   --  @param Response Complete HTTP response metadata
   --  @param Payload Complete bounded response body
   --  @param Limits Bounded XML parser limits
   --  @return Modeled creation response or S3 rejection
   --  @exception Invalid_Response Response headers or payload are invalid
   function Decode_Create_Bucket_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Bucket_Outcome;

   --  Execute one prepared CreateBucket request with its owned one-shot body.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared CreateBucket request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Modeled creation result or structured S3 rejection
   function Execute_Create_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Bucket_Outcome;

   --  Modeled GetBucketLocation input outside the bucket path.
   --  @field Expected_Bucket_Owner Optional bucket-owner precondition
   type Get_Bucket_Location_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one bodyless GetBucketLocation request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose location is requested
   --  @param Parameters Optional request headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared GetBucketLocation request
   function Prepare_Get_Bucket_Location
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Location_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Successful GetBucketLocation result.
   --  @field Location_Constraint Parsed legacy constraint including empty text
   type Get_Bucket_Location_Result is record
      Location_Constraint : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal GetBucketLocation response classification.
   --  @enum Bucket_Location_Found The decoded location is present
   --  @enum Get_Bucket_Location_Rejected An S3 rejection is present
   type Get_Bucket_Location_Outcome_Kind is
     (Bucket_Location_Found, Get_Bucket_Location_Rejected);

   --  Completed GetBucketLocation response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful location result
   --  @field Error Structured S3 rejection
   type Get_Bucket_Location_Outcome
     (Kind : Get_Bucket_Location_Outcome_Kind :=
       Get_Bucket_Location_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Location_Found =>
            Result : Get_Bucket_Location_Result;
         when Get_Bucket_Location_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded GetBucketLocation HTTP result.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier for an S3 rejection
   --  @param Host_ID Optional host identifier for an S3 rejection
   --  @param Limits XML document, depth, element, and text limits
   --  @return Modeled location or structured S3 rejection
   function Decode_Get_Bucket_Location_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Location_Outcome;

   --  Execute one prepared GetBucketLocation request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared GetBucketLocation request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Modeled location or structured S3 rejection
   function Execute_Get_Bucket_Location
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Location_Outcome;

   --  Every modeled PutBucketTagging control. Content_MD5 is generated from
   --  the serialized tag document when omitted. A selected SDK checksum
   --  algorithm emits both the algorithm and matching checksum headers.
   --  Request_Payer is retained for source compatibility with 0.1.0-dev but
   --  is not modeled by S3 and any nonempty value is rejected.
   --  @field Content_MD5 Optional exact digest or generated document digest
   --  @field Checksum_Algorithm Optional modeled SDK checksum algorithm
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Request_Payer Compatibility field rejected when nonempty
   type Put_Bucket_Tagging_Parameters is record
      Content_MD5            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm     : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner  : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one nonreplaying PutBucketTagging request.
   --  @param Origin Exact request origin
   --  @param Style Path or virtual-hosted addressing
   --  @param Bucket Bucket whose complete tag set is replaced
   --  @param Value Complete validated bucket tag set
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Signed request owning the serialized tag document
   function Prepare_Put_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Value      : Tags.Tag_Set;
      Parameters : Put_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Modeled PutBucketTagging response metadata.
   --  @field Request_Charged Compatibility field rejected when nonempty
   type Put_Bucket_Tagging_Result is record
      --  Retained for source compatibility. PutBucketTagging has no modeled
      --  request-charging output and a nonempty response value is rejected.
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Shape of one decoded PutBucketTagging response.
   --  @enum Bucket_Tags_Replaced Completed replacement and exact status
   --  @enum Put_Bucket_Tagging_Rejected Exact status and structured S3 error
   type Put_Bucket_Tagging_Outcome_Kind is
     (Bucket_Tags_Replaced, Put_Bucket_Tagging_Rejected);

   --  Completed replacement or structured S3 rejection.
   --  @field Kind Result shape
   --  @field Status Exact response status
   --  @field Result Modeled compatibility response metadata
   --  @field Error Structured S3 rejection
   type Put_Bucket_Tagging_Outcome
     (Kind : Put_Bucket_Tagging_Outcome_Kind :=
       Put_Bucket_Tagging_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Tags_Replaced =>
            Result : Put_Bucket_Tagging_Result;
         when Put_Bucket_Tagging_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode exact HTTP 200 or 204 as a payload-free completed replacement.
   --  Whitespace-only success payload is tolerated for compatibility.
   --  @param Status Exact response status
   --  @param Payload Complete bounded response payload
   --  @param Headers Modeled response metadata
   --  @param Request_ID Request identifier fallback for structured errors
   --  @param Host_ID Host identifier fallback for structured errors
   --  @param Limits Caller-selected XML parser limits
   --  @return Completed replacement or structured S3 rejection
   --  @exception Invalid_Response Response metadata or payload is invalid
   function Decode_Put_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Bucket_Tagging_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Tagging_Outcome;

   --  Execute one prepared PutBucketTagging exchange synchronously.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact prepared PutBucketTagging request
   --  @param Timeout Whole-exchange budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and XML limits
   --  @return Completed replacement or structured S3 rejection
   function Execute_Put_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Tagging_Outcome;

   --  Complete modeled GetBucketTagging request controls.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Request_Payer Compatibility field rejected when nonempty
   type Get_Bucket_Tagging_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      --  Retained for source compatibility; any nonempty value is rejected.
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one signed GetBucketTagging request.
   --  @param Origin Exact HTTP origin
   --  @param Style S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp SigV4 basic-format timestamp
   --  @return Owned signed request ready for execution
   function Prepare_Get_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Complete modeled GetBucketTagging success fields.
   --  @field Value Complete decoded bucket tag set
   --  @field Request_Charged Compatibility field rejected when nonempty
   type Get_Bucket_Tagging_Result is record
      Value           : Tags.Tag_Set;
      --  Retained for source compatibility. GetBucketTagging has no modeled
      --  request-charging output and a nonempty response value is rejected.
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Result shape for one completed GetBucketTagging exchange.
   --  @enum Bucket_Tags_Found Complete tag snapshot exists
   --  @enum Get_Bucket_Tagging_Rejected Structured S3 rejection exists
   type Get_Bucket_Tagging_Outcome_Kind is
     (Bucket_Tags_Found, Get_Bucket_Tagging_Rejected);

   --  Complete GetBucketTagging response or structured S3 rejection.
   --  @field Kind Result shape
   --  @field Status Exact HTTP response status
   --  @field Result Complete modeled successful response
   --  @field Error Structured S3 rejection
   type Get_Bucket_Tagging_Outcome
     (Kind : Get_Bucket_Tagging_Outcome_Kind :=
       Get_Bucket_Tagging_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Tags_Found =>
            Result : Get_Bucket_Tagging_Result;
         when Get_Bucket_Tagging_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded GetBucketTagging response.
   --  @param Status Exact HTTP response status
   --  @param Payload Complete retained response body
   --  @param Headers Complete modeled response headers
   --  @param Request_ID Optional S3 request identifier
   --  @param Host_ID Optional S3 host identifier
   --  @param Limits Caller-selected XML parsing limits
   --  @return Complete modeled response or structured S3 rejection
   function Decode_Get_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Get_Bucket_Tagging_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Tagging_Outcome;

   --  Execute one prepared GetBucketTagging request synchronously.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Owned request prepared for GetBucketTagging
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Complete modeled response or structured S3 rejection
   function Execute_Get_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Tagging_Outcome;

   --  Complete modeled DeleteBucketTagging request controls.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Delete_Bucket_Tagging_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one nonreplaying DeleteBucketTagging request.
   --  @param Origin Exact request origin
   --  @param Style Path or virtual-hosted addressing
   --  @param Bucket Bucket whose complete tag set is deleted
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Signed request with an empty payload
   function Prepare_Delete_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Shape of one decoded DeleteBucketTagging response.
   --  @enum Bucket_Tags_Deleted Completed deletion and exact status
   --  @enum Delete_Bucket_Tagging_Rejected Exact status and S3 error
   type Delete_Bucket_Tagging_Outcome_Kind is
     (Bucket_Tags_Deleted, Delete_Bucket_Tagging_Rejected);

   --  Payload-free completed deletion or structured S3 rejection.
   --  @field Kind Result shape
   --  @field Status Exact response status
   --  @field Error Structured S3 rejection
   type Delete_Bucket_Tagging_Outcome
     (Kind : Delete_Bucket_Tagging_Outcome_Kind :=
       Delete_Bucket_Tagging_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Tags_Deleted =>
            null;
         when Delete_Bucket_Tagging_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode exact HTTP 204 with an exactly empty response body.
   --  Completion does not assert that a tag set was previously present.
   --  @param Status Exact response status
   --  @param Payload Complete bounded response payload
   --  @param Request_ID Request identifier fallback for structured errors
   --  @param Host_ID Host identifier fallback for structured errors
   --  @param Limits Caller-selected XML parser limits
   --  @return Completed deletion or structured S3 rejection
   --  @exception Invalid_Response Response payload is invalid
   function Decode_Delete_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Tagging_Outcome;

   --  Execute one prepared DeleteBucketTagging exchange synchronously.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact prepared DeleteBucketTagging request
   --  @param Timeout Whole-exchange budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and XML limits
   --  @return Completed deletion or structured S3 rejection
   function Execute_Delete_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Tagging_Outcome;

   --  Every modeled PutBucketVersioning input outside the bucket path. An
   --  empty Content_MD5 asks the client to generate the required digest from
   --  the exact serialized configuration document.
   --  @field Content_MD5 Supplied digest or empty for generated MD5
   --  @field Checksum_Algorithm Optional generated-checksum algorithm
   --  @field MFA Optional exact multifactor-authentication value
   --  @field Configuration Complete bucket-versioning configuration
   --  @field Expected_Bucket_Owner Optional bucket-owner precondition
   type Put_Bucket_Versioning_Parameters is record
      Content_MD5          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm   : Ada.Strings.Unbounded.Unbounded_String;
      MFA                  : Ada.Strings.Unbounded.Unbounded_String;
      Configuration        : Bucket_Versioning_Configuration;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one PutBucketVersioning request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose versioning is updated
   --  @param Parameters Configuration, integrity, and request headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared PutBucketVersioning request
   function Prepare_Put_Bucket_Versioning
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Put_Bucket_Versioning_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal PutBucketVersioning response classification.
   --  @enum Bucket_Versioning_Updated The update completed
   --  @enum Put_Bucket_Versioning_Rejected An S3 rejection is present
   type Put_Bucket_Versioning_Outcome_Kind is
     (Bucket_Versioning_Updated, Put_Bucket_Versioning_Rejected);

   --  Completed PutBucketVersioning response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Error Structured S3 rejection
   type Put_Bucket_Versioning_Outcome
     (Kind : Put_Bucket_Versioning_Outcome_Kind :=
       Put_Bucket_Versioning_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Versioning_Updated =>
            null;
         when Put_Bucket_Versioning_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded PutBucketVersioning HTTP result.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Completed update or structured S3 rejection
   function Decode_Put_Bucket_Versioning_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Put_Bucket_Versioning_Outcome;

   --  Execute one prepared PutBucketVersioning request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared PutBucketVersioning request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Completed update or structured S3 rejection
   function Execute_Put_Bucket_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Put_Bucket_Versioning_Outcome;

   --  Modeled GetBucketVersioning input outside the bucket path.
   --  @field Expected_Bucket_Owner Optional bucket-owner precondition
   type Get_Bucket_Versioning_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one bodyless GetBucketVersioning request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose versioning is requested
   --  @param Parameters Optional request headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared GetBucketVersioning request
   function Prepare_Get_Bucket_Versioning
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Versioning_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal GetBucketVersioning response classification.
   --  @enum Bucket_Versioning_Found Modeled configuration result is available
   --  @enum Get_Bucket_Versioning_Rejected An S3 rejection is present
   type Get_Bucket_Versioning_Outcome_Kind is
     (Bucket_Versioning_Found, Get_Bucket_Versioning_Rejected);

   --  Completed GetBucketVersioning response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Configuration Presence-preserving versioning configuration
   --  @field Error Structured S3 rejection
   type Get_Bucket_Versioning_Outcome
     (Kind : Get_Bucket_Versioning_Outcome_Kind :=
       Get_Bucket_Versioning_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Versioning_Found =>
            Configuration : Bucket_Versioning_Configuration;
         when Get_Bucket_Versioning_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one already bounded GetBucketVersioning HTTP result.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Versioning configuration or structured S3 rejection
   function Decode_Get_Bucket_Versioning_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Get_Bucket_Versioning_Outcome;

   --  Execute one prepared GetBucketVersioning request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared GetBucketVersioning request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Versioning configuration or structured S3 rejection
   function Execute_Get_Bucket_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Get_Bucket_Versioning_Outcome;

   --  Modeled HeadBucket input outside the bucket path.
   --  @field Expected_Bucket_Owner Optional bucket-owner precondition
   type Head_Bucket_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one bodyless HeadBucket request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose availability is checked
   --  @param Parameters Optional request headers
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared HeadBucket request
   function Prepare_Head_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Head_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every output member in the pinned HeadBucket response shape.
   --  @field Bucket_ARN Optional exact bucket resource name
   --  @field Bucket_Location_Type Optional location classification
   --  @field Bucket_Location_Name Optional exact location name
   --  @field Bucket_Region Optional exact bucket region
   --  @field Access_Point_Alias Optional access-point-alias flag
   type Head_Bucket_Result is record
      Bucket_ARN           : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Location_Type : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Location_Name : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region        : Ada.Strings.Unbounded.Unbounded_String;
      Access_Point_Alias   : Optional_Boolean;
   end record;

   --  Terminal HeadBucket response classification.
   --  @enum Bucket_Found The modeled success metadata is present
   --  @enum Head_Bucket_Rejected A bodyless rejection is present
   type Head_Bucket_Outcome_Kind is
     (Bucket_Found, Head_Bucket_Rejected);

   --  Completed HeadBucket response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful bucket metadata
   --  @field Error Synthesized bodyless rejection
   type Head_Bucket_Outcome
     (Kind : Head_Bucket_Outcome_Kind := Head_Bucket_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Found =>
            Result : Head_Bucket_Result;
         when Head_Bucket_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one HeadBucket status, body, and modeled header set.
   --  @param Status HTTP response status
   --  @param Payload Complete response body
   --  @param Headers Modeled HeadBucket response headers
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @return Modeled success metadata or bodyless rejection
   function Decode_Head_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Head_Bucket_Result;
      Request_ID : String := "";
      Host_ID    : String := "") return Head_Bucket_Outcome;

   --  Decode a fully received HeadBucket exchange. Physical singleton and
   --  transfer-framing checks are identical for blocking and composable
   --  callers; Payload must contain every received response-body octet.
   --  @param Response Complete HTTP response metadata
   --  @param Payload Every response-body octet retained by the caller
   --  @return Modeled HeadBucket success or bodyless rejection
   function Decode_Head_Bucket_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String) return Head_Bucket_Outcome;

   --  Execute one prepared HeadBucket request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared HeadBucket request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @return Modeled success metadata or bodyless rejection
   function Execute_Head_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Outcome;

   --  Every input member in the pinned HeadObject request shape.
   --  @field If_Match Optional exact entity-tag precondition
   --  @field If_Modified_Since Optional modified-since precondition
   --  @field If_None_Match Optional negative entity-tag precondition
   --  @field If_Unmodified_Since Optional unmodified-since precondition
   --  @field Byte_Range_Header Optional exact byte-range request
   --  @field Response_Cache_Control Optional cache-control override
   --  @field Response_Content_Disposition Optional disposition override
   --  @field Response_Content_Encoding Optional encoding override
   --  @field Response_Content_Language Optional language override
   --  @field Response_Content_Type Optional media-type override
   --  @field Response_Expires Optional expiry override
   --  @field Version_ID Optional exact object-version selector
   --  @field SSE_Customer_Algorithm Optional customer-key algorithm
   --  @field SSE_Customer_Key Optional base64 customer key
   --  @field SSE_Customer_Key_MD5 Optional base64 customer-key digest
   --  @field Request_Payer Optional requester-pays admission value
   --  @field Part_Number Optional retained multipart part selector
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Checksum_Mode Whether modeled checksum headers are requested
   type Head_Object_Parameters is record
      If_Match                 : Ada.Strings.Unbounded.Unbounded_String;
      If_Modified_Since        : Ada.Strings.Unbounded.Unbounded_String;
      If_None_Match            : Ada.Strings.Unbounded.Unbounded_String;
      If_Unmodified_Since      : Ada.Strings.Unbounded.Unbounded_String;
      Byte_Range_Header        : Ada.Strings.Unbounded.Unbounded_String;
      Response_Cache_Control   : Ada.Strings.Unbounded.Unbounded_String;
      Response_Content_Disposition :
        Ada.Strings.Unbounded.Unbounded_String;
      Response_Content_Encoding : Ada.Strings.Unbounded.Unbounded_String;
      Response_Content_Language : Ada.Strings.Unbounded.Unbounded_String;
      Response_Content_Type    : Ada.Strings.Unbounded.Unbounded_String;
      Response_Expires         : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID               : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm   : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key         : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5     : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer            : Ada.Strings.Unbounded.Unbounded_String;
      Part_Number              : Optional_Part_Number;
      Expected_Bucket_Owner    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Mode            : Boolean := False;
   end record;

   --  Prepare one modeled HeadObject request.
   --  @param Origin Exact HTTP origin
   --  @param Style S3 addressing style
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Signed request with retained response-binding values
   function Prepare_Head_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Head_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  One modeled object metadata name and value.
   --  @field Name Metadata name without the x-amz-meta prefix
   --  @field Value Exact metadata value
   type Metadata_Entry is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Ordered collection of modeled object metadata entries.
   package Metadata_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Metadata_Entry);

   --  Every output member in the pinned HeadObject response shape.
   --  @field Delete_Marker Optional delete-marker response value
   --  @field Accept_Ranges Optional accepted range unit
   --  @field Expiration Optional object-expiration metadata
   --  @field Restore Optional archive-restore metadata
   --  @field Archive_Status Optional archive access state
   --  @field Last_Modified Exact last-modified response value
   --  @field Content_Length Exact selected representation length
   --  @field Checksum_CRC32 Optional CRC32 checksum
   --  @field Checksum_CRC32C Optional CRC32C checksum
   --  @field Checksum_CRC64NVME Optional CRC64NVME checksum
   --  @field Checksum_SHA1 Optional SHA1 checksum
   --  @field Checksum_SHA256 Optional SHA256 checksum
   --  @field Checksum_SHA512 Optional SHA512 checksum
   --  @field Checksum_MD5 Optional MD5 checksum
   --  @field Checksum_XXHASH64 Optional XXHASH64 checksum
   --  @field Checksum_XXHASH3 Optional XXHASH3 checksum
   --  @field Checksum_XXHASH128 Optional XXHASH128 checksum
   --  @field Checksum_Type Optional full-object or composite checksum kind
   --  @field Entity_Tag Exact opaque entity tag
   --  @field Missing_Meta Optional omitted metadata count
   --  @field Version_ID Optional selected object-version response value
   --  @field Cache_Control Optional cache-control metadata
   --  @field Content_Disposition Optional content disposition
   --  @field Content_Encoding Optional content encoding
   --  @field Content_Language Optional content language
   --  @field Content_Type Optional media type
   --  @field Content_Range Optional resolved byte range
   --  @field Expires Optional expiry metadata
   --  @field Website_Redirect_Location Optional website redirect target
   --  @field Server_Side_Encryption Optional server encryption algorithm
   --  @field Metadata Complete modeled user metadata
   --  @field SSE_Customer_Algorithm Optional customer-key algorithm
   --  @field SSE_Customer_Key_MD5 Optional customer-key digest
   --  @field SSE_KMS_Key_ID Optional KMS key identifier
   --  @field Bucket_Key_Enabled Optional bucket-key state
   --  @field Storage_Class Optional exact storage class
   --  @field Request_Charged Optional requester-pays response value
   --  @field Replication_Status Optional replication state
   --  @field Parts_Count Optional retained multipart part count
   --  @field Tag_Count Optional object tag count
   --  @field Object_Lock_Mode Optional retention mode
   --  @field Object_Lock_Retain_Until_Date Optional retention deadline
   --  @field Object_Lock_Legal_Hold_Status Optional legal-hold state
   type Head_Object_Result is record
      Delete_Marker             : Optional_Boolean;
      Accept_Ranges             : Ada.Strings.Unbounded.Unbounded_String;
      Expiration                : Ada.Strings.Unbounded.Unbounded_String;
      Restore                   : Ada.Strings.Unbounded.Unbounded_String;
      Archive_Status            : Ada.Strings.Unbounded.Unbounded_String;
      Last_Modified             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Length            : Byte_Count := 0;
      Checksum_CRC32            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1             : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5              : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type             : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag                : Ada.Strings.Unbounded.Unbounded_String;
      Missing_Meta              : Optional_Natural;
      Version_ID                : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Control             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Disposition       : Ada.Strings.Unbounded.Unbounded_String;
      Content_Encoding          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Language          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type              : Ada.Strings.Unbounded.Unbounded_String;
      Content_Range             : Ada.Strings.Unbounded.Unbounded_String;
      Expires                   : Ada.Strings.Unbounded.Unbounded_String;
      Website_Redirect_Location : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption    : Ada.Strings.Unbounded.Unbounded_String;
      Metadata                  : Metadata_Entry_Vectors.Vector;
      SSE_Customer_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5      : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled        : Optional_Boolean;
      Storage_Class             : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged           : Ada.Strings.Unbounded.Unbounded_String;
      Replication_Status        : Ada.Strings.Unbounded.Unbounded_String;
      Parts_Count               : Optional_Natural;
      Tag_Count                 : Optional_Natural;
      Object_Lock_Mode          : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Retain_Until_Date :
        Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Legal_Hold_Status :
        Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Shape of a completed HeadObject response.
   --  @enum Object_Found Complete modeled metadata is available
   --  @enum Head_Object_Rejected The service rejected the read
   type Head_Object_Outcome_Kind is
     (Object_Found, Head_Object_Rejected);

   --  Complete modeled HeadObject metadata or structured S3 rejection.
   --  @field Kind Selects the success or rejection variant
   --  @field Status Exact HTTP response status
   --  @field Result Complete validated object metadata
   --  @field Error Structured S3 rejection
   type Head_Object_Outcome
     (Kind : Head_Object_Outcome_Kind := Head_Object_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Found =>
            Result : Head_Object_Result;
         when Head_Object_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  AWS returns 200 for successful Range and partNumber HEAD requests; only
   --  Content_Length is narrowed and Content_Range remains absent. The decoder
   --  also accepts a coherent 206 plus Content_Range from pinned compatible
   --  implementations whose wire behavior diverges from AWS.
   --  @param Status Exact HTTP response status
   --  @param Payload Complete response body, which must be empty
   --  @param Headers Complete modeled response metadata
   --  @param Request_ID Optional S3 request identifier
   --  @param Host_ID Optional S3 host identifier
   --  @return Modeled HeadObject success or rejection
   function Decode_Head_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Head_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "") return Head_Object_Outcome;

   --  Decode a fully received HeadObject exchange. Physical singleton and
   --  transfer-framing checks are identical for blocking and composable
   --  callers; Payload must contain every received response-body octet.
   --  @param Response Complete HTTP response metadata
   --  @param Payload Every response-body octet retained by the caller
   --  @return Modeled HeadObject success or rejection
   function Decode_Head_Object_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String) return Head_Object_Outcome;

   --  Execute one prepared HeadObject request and bind its response.
   --  @param Client Configured HTTP client
   --  @param Prepared Exact signed HeadObject request
   --  @param Timeout Complete exchange timeout
   --  @param Token Optional cancellation source
   --  @return Modeled response bound to the prepared request
   function Execute_Head_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Object_Outcome;

   --  GetObject has the same 21 modeled request members as HeadObject.
   subtype Get_Object_Parameters is Head_Object_Parameters;

   --  Prepare one modeled GetObject request.
   --  @param Origin Exact HTTP origin
   --  @param Style S3 addressing style
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Signed request with retained response-binding values
   function Prepare_Get_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every modeled GetObject response-head member. Body is represented by
   --  the limited streaming HTTP response returned from Execute_Get_Object.
   --  @field Delete_Marker Whether the selected version is a delete marker
   --  @field Accept_Ranges Advertised accepted byte-range unit
   --  @field Expiration Modeled expiration response value
   --  @field Restore Modeled archive-restore response value
   --  @field Last_Modified Modeled last-modified response value
   --  @field Content_Length Declared response-body length
   --  @field Entity_Tag Exact opaque entity tag
   --  @field Checksum_CRC32 Modeled CRC32 checksum value
   --  @field Checksum_CRC32C Modeled CRC32C checksum value
   --  @field Checksum_CRC64NVME Modeled CRC64NVME checksum value
   --  @field Checksum_SHA1 Modeled SHA1 checksum value
   --  @field Checksum_SHA256 Modeled SHA256 checksum value
   --  @field Checksum_SHA512 Modeled SHA512 checksum value
   --  @field Checksum_MD5 Modeled MD5 checksum value
   --  @field Checksum_XXHASH64 Modeled XXHASH64 checksum value
   --  @field Checksum_XXHASH3 Modeled XXHASH3 checksum value
   --  @field Checksum_XXHASH128 Modeled XXHASH128 checksum value
   --  @field Checksum_Type Empty, FULL_OBJECT, or COMPOSITE
   --  @field Missing_Meta Count of metadata entries not returned
   --  @field Version_ID Exact provider version response value
   --  @field Cache_Control Modeled cache-control response value
   --  @field Content_Disposition Modeled content-disposition response value
   --  @field Content_Encoding Modeled content-encoding response value
   --  @field Content_Language Modeled content-language response value
   --  @field Content_Range Modeled returned byte interval
   --  @field Content_Type Modeled content-type response value
   --  @field Expires Modeled expires response value
   --  @field Website_Redirect_Location Modeled website redirect value
   --  @field Server_Side_Encryption Modeled server-side encryption value
   --  @field Metadata Ordered user metadata entries
   --  @field SSE_Customer_Algorithm Modeled customer-key algorithm value
   --  @field SSE_Customer_Key_MD5 Modeled customer-key MD5 value
   --  @field SSE_KMS_Key_ID Modeled KMS key identifier
   --  @field Bucket_Key_Enabled Whether an S3 bucket key was used
   --  @field Storage_Class Modeled storage-class response value
   --  @field Request_Charged Empty or the sole modeled requester value
   --  @field Replication_Status Modeled replication-status response value
   --  @field Parts_Count Number of parts in the selected object
   --  @field Tag_Count Number of tags on the selected object
   --  @field Object_Lock_Mode Modeled object-lock mode
   --  @field Object_Lock_Retain_Until_Date Modeled retention timestamp
   --  @field Object_Lock_Legal_Hold_Status Modeled legal-hold status
   type Get_Object_Result is record
      Delete_Marker             : Optional_Boolean;
      Accept_Ranges             : Ada.Strings.Unbounded.Unbounded_String;
      Expiration                : Ada.Strings.Unbounded.Unbounded_String;
      Restore                   : Ada.Strings.Unbounded.Unbounded_String;
      Last_Modified             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Length            : Optional_Byte_Count;
      Entity_Tag                : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1             : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5              : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type             : Ada.Strings.Unbounded.Unbounded_String;
      Missing_Meta              : Optional_Natural;
      Version_ID                : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Control             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Disposition       : Ada.Strings.Unbounded.Unbounded_String;
      Content_Encoding          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Language          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Range             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type              : Ada.Strings.Unbounded.Unbounded_String;
      Expires                   : Ada.Strings.Unbounded.Unbounded_String;
      Website_Redirect_Location : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption    : Ada.Strings.Unbounded.Unbounded_String;
      Metadata                  : Metadata_Entry_Vectors.Vector;
      SSE_Customer_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5      : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled        : Optional_Boolean;
      Storage_Class             : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged           : Ada.Strings.Unbounded.Unbounded_String;
      Replication_Status        : Ada.Strings.Unbounded.Unbounded_String;
      Parts_Count               : Optional_Natural;
      Tag_Count                 : Optional_Natural;
      Object_Lock_Mode          : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Retain_Until_Date :
        Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Legal_Hold_Status :
        Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Shape of a decoded GetObject response head.
   --  @enum Object_Opened Modeled success metadata is available
   --  @enum Get_Object_Rejected The service returned an S3 rejection
   type Get_Object_Head_Outcome_Kind is
     (Object_Opened, Get_Object_Rejected);

   --  Decoded GetObject response metadata or structured rejection.
   --  @field Kind Selects the opened or rejected variant
   --  @field Status HTTP status returned by the completed exchange
   --  @field Result Complete modeled success metadata
   --  @field Error Structured S3 rejection
   type Get_Object_Head_Outcome
     (Kind : Get_Object_Head_Outcome_Kind := Get_Object_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Opened =>
            Result : Get_Object_Result;
         when Get_Object_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Execute a typed GetObject request and return its unconsumed limited
   --  response. The caller must decode the head and then consume or finalize
   --  the body before reusing the associated exchange lease.
   --  @param Client Configured origin client
   --  @param Prepared Exact prepared GetObject request
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Unconsumed limited HTTP response
   function Execute_Get_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response;

   --  Every non-resource member in the pinned GetObjectAcl request.
   --  @field Version_ID Optional exact generation selector
   --  @field Request_Payer Empty or the sole modeled requester value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Get_Object_ACL_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed GetObjectAcl request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Object key whose access-control policy is requested
   --  @param Parameters Optional version, payer, and owner selectors
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request bound to GetObjectAcl
   function Prepare_Get_Object_ACL
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_ACL_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Complete modeled GetObjectAcl success output.
   --  @field Policy Presence-preserving ACL response body
   --  @field Request_Charged Empty or the sole modeled requester value
   type Get_Object_ACL_Result is record
      Policy          : S3.ACL.Access_Control_Policy;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal interpretation of one GetObjectAcl response.
   --  @enum Object_ACL_Found Exact 200 response decoded successfully
   --  @enum Get_Object_ACL_Rejected Bounded non-200 S3 rejection
   type Get_Object_ACL_Outcome_Kind is
     (Object_ACL_Found, Get_Object_ACL_Rejected);

   --  Presence-preserving object ACL result or structured rejection.  The
   --  500 default is the established deterministic aggregate sentinel only.
   --  @field Kind Whether ACL state or an S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Result Complete modeled success output
   --  @field Error Structured bounded S3 rejection
   type Get_Object_ACL_Outcome
     (Kind : Get_Object_ACL_Outcome_Kind := Get_Object_ACL_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_ACL_Found =>
            Result : Get_Object_ACL_Result;
         when Get_Object_ACL_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded GetObjectAcl response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_Charged Optional modeled requester-charged header
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed ACL state or strict S3 rejection
   function Decode_Get_Object_ACL_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_ACL_Outcome;

   --  Execute and fully decode one exact prepared GetObjectAcl request.  The
   --  30-second default is the established low-level synchronous-client
   --  compatibility budget; callers may select a different absolute budget.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_Get_Object_ACL
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed ACL state or strict S3 rejection
   function Execute_Get_Object_ACL
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_ACL_Outcome;

   --  Every non-resource member in the pinned GetObjectTorrent request.
   --  @field Request_Payer Empty or the sole modeled value, requester
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Get_Object_Torrent_Parameters is record
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed GetObjectTorrent request.  Successful torrent
   --  bytes are not retained in the prepared request or response metadata.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket containing the requested object
   --  @param Key Object key whose torrent representation is requested
   --  @param Parameters Optional payer and owner preconditions
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request with no retained body bytes
   function Prepare_Get_Object_Torrent
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Torrent_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  The sole non-body member in the pinned GetObjectTorrent output.
   --  @field Request_Charged Empty or the modeled requester value
   type Get_Object_Torrent_Result is record
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal interpretation of GetObjectTorrent response metadata.
   --  @enum Torrent_Opened Exact 200 response with caller-owned body bytes
   --  @enum Get_Object_Torrent_Rejected Bounded non-200 S3 rejection
   type Get_Object_Torrent_Outcome_Kind is
     (Torrent_Opened, Get_Object_Torrent_Rejected);

   --  Typed response metadata. Torrent_Opened deliberately carries no body;
   --  the executing API documents whether bytes remain in an HTTP response or
   --  have moved into a caller-owned bounded buffer.
   --  Status defaults to the established low-level rejection initializer;
   --  the value is local state and is never transmitted as an HTTP status.
   --  @field Kind Whether the response opened a body or returned an S3 error
   --  @field Status Exact HTTP response status
   --  @field Result Successful response-head metadata
   --  @field Error Structured rejected-response diagnostics
   type Get_Object_Torrent_Outcome
     (Kind : Get_Object_Torrent_Outcome_Kind :=
        Get_Object_Torrent_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Torrent_Opened =>
            Result : Get_Object_Torrent_Result;
         when Get_Object_Torrent_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a complete response head plus a bounded error body.  On 200,
   --  Error_Payload must be empty because the successful torrent body remains
   --  owned by the streaming HTTP response.
   --  @param Status Exact HTTP response status
   --  @param Error_Payload Empty on success or complete bounded error body
   --  @param Request_Charged Optional modeled response header
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Validated response head or structured S3 rejection
   function Decode_Get_Object_Torrent_Response_Head
     (Status          : Flyology.HTTP.Status_Code;
      Error_Payload   : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Torrent_Outcome;

   --  Execute one exact typed request and return its unconsumed response.  The
   --  timeout default is the established synchronous low-level client default;
   --  retaining it preserves cross-operation behavior and caller
   --  compatibility.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_Get_Object_Torrent
   --  @param Timeout Whole-exchange timeout including later response reads
   --  @param Token Optional cancellation source
   --  @return Limited streaming HTTP response with an unread body
   function Execute_Get_Object_Torrent
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Flyology.HTTP.Client.Response;

   --  Validate physical response-header multiplicity.  Successful body bytes
   --  remain unread; rejected bodies are consumed only within Limits.
   --  @param Response Limited HTTP response returned by the matching executor
   --  @param Token Optional cancellation source for bounded error-body reads
   --  @param Limits XML document, depth, element, and text limits
   --  @return Validated response head or structured S3 rejection
   function Decode_Get_Object_Torrent_Response_Head
     (Response : in out Flyology.HTTP.Client.Response;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Torrent_Outcome;

   --  Decode response metadata after a bounded exchange has retained the
   --  complete body. On 200, Payload is caller-owned torrent data and is not
   --  interpreted. On other statuses it is the bounded S3 error document.
   --  @param Response Complete lease-free HTTP response metadata
   --  @param Payload Complete torrent bytes or bounded S3 error document
   --  @param Limits XML document, depth, element, and text limits
   --  @return Validated response metadata or structured S3 rejection
   function Decode_Get_Object_Torrent_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Torrent_Outcome;

   --  Every non-resource member in the pinned GetObjectLegalHold request.
   --  @field Version_ID Optional exact generation selector
   --  @field Request_Payer Empty or the sole modeled value, requester
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Get_Object_Legal_Hold_Parameters is record
      Version_ID               : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed GetObjectLegalHold request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Object key whose legal-hold state is requested
   --  @param Parameters Optional version, payer, and owner selectors
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request
   function Prepare_Get_Object_Legal_Hold
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Legal_Hold_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal interpretation of a GetObjectLegalHold response.
   --  @enum Object_Legal_Hold_Found Exact 200 response decoded successfully
   --  @enum Get_Object_Legal_Hold_Rejected Bounded non-200 S3 rejection
   type Get_Object_Legal_Hold_Outcome_Kind is
     (Object_Legal_Hold_Found, Get_Object_Legal_Hold_Rejected);

   --  Presence-preserving legal-hold result or structured rejection.  Status
   --  uses the established low-level local rejection initializer and is never
   --  transmitted as an HTTP value.
   --  @field Kind Whether legal-hold state or an S3 error was returned
   --  @field Status Exact HTTP response status
   --  @field Legal_Hold Optional outer payload and nested status
   --  @field Error Structured rejected-response diagnostics
   type Get_Object_Legal_Hold_Outcome
     (Kind : Get_Object_Legal_Hold_Outcome_Kind :=
        Get_Object_Legal_Hold_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Legal_Hold_Found =>
            Legal_Hold : S3.Object_Lock.Legal_Hold;
         when Get_Object_Legal_Hold_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a complete bounded legal-hold or structured S3 error body.
   --  @param Status Exact HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Presence-preserving legal hold or structured S3 rejection
   function Decode_Get_Object_Legal_Hold_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Legal_Hold_Outcome;

   --  Execute and fully decode one matching request within caller-selected
   --  XML limits.  The timeout is the established synchronous client default.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_Get_Object_Legal_Hold
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Presence-preserving legal hold or structured S3 rejection
   function Execute_Get_Object_Legal_Hold
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Legal_Hold_Outcome;

   --  Every physical control in the pinned PutObjectLegalHold request.
   --  @field Request_Payer Empty or the sole modeled value, requester
   --  @field Version_ID Optional exact generation selector
   --  @field Content_MD5 Optional exact caller-supplied 16-byte digest
   --  @field Checksum_Algorithm Optional exact pinned SDK checksum algorithm
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Object_Legal_Hold_Parameters is record
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed PutObjectLegalHold request.  The payload is
   --  copied into prepared owned storage and is never retained by reference.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Object key whose legal-hold state is updated
   --  @param Value Presence-preserving legal-hold payload
   --  @param Parameters Optional checksum, generation, payer, and owner
   --  controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @param Limits XML document, depth, element, and text limits
   --  @return Immutable prepared request with owned serialized bytes
   function Prepare_Put_Object_Legal_Hold
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Legal_Hold;
      Parameters : Put_Object_Legal_Hold_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String;
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Every modeled PutObjectLegalHold success member.
   --  @field Request_Charged Optional exact requester-pays result
   type Put_Object_Legal_Hold_Result is record
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal PutObjectLegalHold response classification.
   --  @enum Object_Legal_Hold_Updated Exact bodyless 200 response
   --  @enum Put_Object_Legal_Hold_Rejected Bounded non-200 S3 rejection
   type Put_Object_Legal_Hold_Outcome_Kind is
     (Object_Legal_Hold_Updated, Put_Object_Legal_Hold_Rejected);

   --  Exact legal-hold mutation success or structured rejection.
   --  @field Kind Response classification
   --  @field Status Exact HTTP status
   --  @field Result Modeled success headers
   --  @field Error Bounded structured provider rejection
   type Put_Object_Legal_Hold_Outcome
     (Kind : Put_Object_Legal_Hold_Outcome_Kind :=
       Put_Object_Legal_Hold_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Legal_Hold_Updated =>
            Result : Put_Object_Legal_Hold_Result;
         when Put_Object_Legal_Hold_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded PutObjectLegalHold response.
   --  @param Status Exact HTTP status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled singleton success headers
   --  @param Request_ID Optional provider request diagnostic
   --  @param Host_ID Optional provider host diagnostic
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Decode_Put_Object_Legal_Hold_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Object_Legal_Hold_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Legal_Hold_Outcome;

   --  Execute exactly once with an owned non-replayable body source.  Any
   --  exception after blocking call entry leaves publication unknown and
   --  requires read-only reconciliation; callers must not automatically retry.
   --  The 30-second default preserves the established low-level client timeout
   --  policy and remains caller-overridable.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_Put_Object_Legal_Hold
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Execute_Put_Object_Legal_Hold
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Legal_Hold_Outcome;

   --  Every non-resource member in the pinned GetObjectRetention request.
   --  @field Version_ID Optional exact generation selector
   --  @field Request_Payer Empty or the sole modeled value, requester
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Get_Object_Retention_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed GetObjectRetention request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Object key whose retention state is requested
   --  @param Parameters Optional version, payer, and owner selectors
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request
   function Prepare_Get_Object_Retention
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Retention_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal interpretation of a GetObjectRetention response.
   --  @enum Object_Retention_Found Exact 200 response decoded successfully
   --  @enum Get_Object_Retention_Rejected Bounded non-200 S3 rejection
   type Get_Object_Retention_Outcome_Kind is
     (Object_Retention_Found, Get_Object_Retention_Rejected);

   --  Presence-preserving retention result or structured rejection.  Status
   --  uses the established low-level local rejection initializer and is never
   --  transmitted as an HTTP value.
   --  @field Kind Whether retention state or an S3 error was returned
   --  @field Status Exact HTTP response status
   --  @field Retention Optional outer payload and independent nested members
   --  @field Error Structured rejected-response diagnostics
   type Get_Object_Retention_Outcome
     (Kind : Get_Object_Retention_Outcome_Kind :=
        Get_Object_Retention_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Retention_Found =>
            Retention : S3.Object_Lock.Retention;
         when Get_Object_Retention_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a complete bounded retention or structured S3 error body.
   --  @param Status Exact HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Presence-preserving retention or structured S3 rejection
   function Decode_Get_Object_Retention_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Retention_Outcome;

   --  Execute and fully decode one matching request within caller-selected
   --  XML limits.  The timeout is the established synchronous client default.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_Get_Object_Retention
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Presence-preserving retention or structured S3 rejection
   function Execute_Get_Object_Retention
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Retention_Outcome;

   --  Every physical control in the pinned PutObjectRetention request.
   --  @field Request_Payer Empty or the sole modeled value, requester
   --  @field Version_ID Optional exact generation selector
   --  @field Bypass_Governance_Retention Optional explicit true or false
   --  @field Content_MD5 Optional exact caller-supplied 16-byte digest
   --  @field Checksum_Algorithm Optional exact pinned SDK checksum algorithm
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Object_Retention_Parameters is record
      Request_Payer               : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID                  : Ada.Strings.Unbounded.Unbounded_String;
      Bypass_Governance_Retention : Optional_Boolean;
      Content_MD5                 : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm          : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed PutObjectRetention request.  The payload is
   --  copied into prepared owned storage and is never retained by reference.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Object key whose retention state is updated
   --  @param Value Presence-preserving retention payload
   --  @param Parameters Optional checksum, generation, payer, governance,
   --  and owner controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @param Limits XML document, depth, element, and text limits
   --  @return Immutable prepared request with owned serialized bytes
   function Prepare_Put_Object_Retention
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Retention;
      Parameters : Put_Object_Retention_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String;
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Every modeled PutObjectRetention success member.
   --  @field Request_Charged Optional exact requester-pays result
   type Put_Object_Retention_Result is record
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal PutObjectRetention response classification.
   --  @enum Object_Retention_Updated Exact bodyless 200 response
   --  @enum Put_Object_Retention_Rejected Bounded non-200 S3 rejection
   type Put_Object_Retention_Outcome_Kind is
     (Object_Retention_Updated, Put_Object_Retention_Rejected);

   --  Exact retention mutation success or structured rejection.
   --  @field Kind Response classification
   --  @field Status Exact HTTP status
   --  @field Result Modeled success headers
   --  @field Error Bounded structured provider rejection
   type Put_Object_Retention_Outcome
     (Kind : Put_Object_Retention_Outcome_Kind :=
       Put_Object_Retention_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Retention_Updated =>
            Result : Put_Object_Retention_Result;
         when Put_Object_Retention_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded PutObjectRetention response.
   --  @param Status Exact HTTP status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled singleton success headers
   --  @param Request_ID Optional provider request diagnostic
   --  @param Host_ID Optional provider host diagnostic
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Decode_Put_Object_Retention_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Object_Retention_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Retention_Outcome;

   --  Execute exactly once with an owned non-replayable body source.  Any
   --  exception after blocking call entry leaves publication unknown and
   --  requires read-only reconciliation; callers must not automatically retry.
   --  The 30-second default preserves the established low-level client timeout
   --  policy and remains caller-overridable.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Request returned by Prepare_Put_Object_Retention
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Execute_Put_Object_Retention
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Retention_Outcome;

   --  Every non-resource member in the pinned
   --  GetObjectLockConfiguration request.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Get_Object_Lock_Configuration_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed GetObjectLockConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose Object Lock configuration is requested
   --  @param Parameters Optional owner selector
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request
   function Prepare_Get_Object_Lock_Configuration
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Object_Lock_Configuration_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal interpretation of a GetObjectLockConfiguration response.
   --  @enum Object_Lock_Configuration_Found Exact 200 response decoded
   --  @enum Get_Object_Lock_Configuration_Rejected Bounded non-200 rejection
   type Get_Object_Lock_Configuration_Outcome_Kind is
     (Object_Lock_Configuration_Found,
      Get_Object_Lock_Configuration_Rejected);

   --  Presence-preserving configuration result or structured rejection.
   --  Status uses the established low-level local rejection initializer and
   --  is never transmitted as an HTTP value.
   --  @field Kind Whether configuration or an S3 error was returned
   --  @field Status Exact HTTP response status
   --  @field Configuration Optional outer and nested configuration members
   --  @field Error Structured rejected-response diagnostics
   type Get_Object_Lock_Configuration_Outcome
     (Kind : Get_Object_Lock_Configuration_Outcome_Kind :=
        Get_Object_Lock_Configuration_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Lock_Configuration_Found =>
            Configuration : S3.Object_Lock.Object_Lock_Configuration;
         when Get_Object_Lock_Configuration_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a complete bounded configuration or structured S3 error body.
   --  @param Status Exact HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits XML document, depth, element, and text limits
   --  @return Presence-preserving configuration or structured S3 rejection
   function Decode_Get_Object_Lock_Configuration_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Lock_Configuration_Outcome;

   --  Execute and fully decode one matching request within caller-selected
   --  XML limits.  The timeout is the established synchronous client default.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Matching prepared request
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits XML document, depth, element, and text limits
   --  @return Presence-preserving configuration or structured S3 rejection
   function Execute_Get_Object_Lock_Configuration
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Lock_Configuration_Outcome;

   --  Every physical control in the pinned PutObjectLockConfiguration
   --  request.  Token is the modeled Object Lock mutation token header.
   --  @field Request_Payer Empty or the sole modeled value, requester
   --  @field Token Optional exact Object Lock mutation token
   --  @field Content_MD5 Optional exact caller-supplied 16-byte digest
   --  @field Checksum_Algorithm Optional exact pinned SDK checksum algorithm
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Object_Lock_Configuration_Parameters is record
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Token                 : Ada.Strings.Unbounded.Unbounded_String;
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed PutObjectLockConfiguration request.  The
   --  serialized payload is copied into prepared owned storage and is never
   --  retained by reference.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose Object Lock configuration is replaced
   --  @param Value Presence-preserving Object Lock configuration payload
   --  @param Parameters Optional checksum, token, payer, and owner controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @param Limits XML document, depth, element, and text limits
   --  @return Immutable prepared request with owned serialized bytes
   function Prepare_Put_Object_Lock_Configuration
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Value      : S3.Object_Lock.Object_Lock_Configuration;
      Parameters : Put_Object_Lock_Configuration_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String;
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Every modeled PutObjectLockConfiguration success member.
   --  @field Request_Charged Optional exact requester-pays result
   type Put_Object_Lock_Configuration_Result is record
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal PutObjectLockConfiguration response classification.
   --  @enum Object_Lock_Configuration_Updated Exact bodyless 200 response
   --  @enum Put_Object_Lock_Configuration_Rejected Bounded non-200 rejection
   type Put_Object_Lock_Configuration_Outcome_Kind is
     (Object_Lock_Configuration_Updated,
      Put_Object_Lock_Configuration_Rejected);

   --  Exact configuration mutation success or structured rejection.
   --  @field Kind Response classification
   --  @field Status Exact HTTP status
   --  @field Result Modeled success headers
   --  @field Error Bounded structured provider rejection
   type Put_Object_Lock_Configuration_Outcome
     (Kind : Put_Object_Lock_Configuration_Outcome_Kind :=
       Put_Object_Lock_Configuration_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Lock_Configuration_Updated =>
            Result : Put_Object_Lock_Configuration_Result;
         when Put_Object_Lock_Configuration_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded PutObjectLockConfiguration response.
   --  @param Status Exact HTTP status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled singleton success headers
   --  @param Request_ID Optional provider request diagnostic
   --  @param Host_ID Optional provider host diagnostic
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Decode_Put_Object_Lock_Configuration_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Object_Lock_Configuration_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Lock_Configuration_Outcome;

   --  Execute exactly once with an owned non-replayable body source.  Any
   --  exception after blocking call entry leaves publication unknown and
   --  requires read-only reconciliation; callers must not automatically retry.
   --  The 30-second default preserves the established low-level client timeout
   --  policy and remains caller-overridable.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Matching prepared request
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Execute_Put_Object_Lock_Configuration
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Lock_Configuration_Outcome;

   --  Every non-resource member in the pinned GetObjectAttributes request.
   --  Presence flags preserve omission for optional numeric headers.
   --  An explicitly present Max_Parts value of zero requests an empty parts
   --  page while retaining the total count and a terminal pagination shape.
   --  @field Version_ID Optional exact object-version selector
   --  @field Max_Parts Requested object-parts page size
   --  @field Has_Max_Parts Whether Max_Parts is present on the wire
   --  @field Part_Number_Marker Exclusive completed-part marker
   --  @field Has_Part_Number_Marker Whether the marker is present
   --  @field SSE_Customer_Algorithm Optional SSE-C algorithm
   --  @field SSE_Customer_Key Optional base64 SSE-C key
   --  @field SSE_Customer_Key_MD5 Required digest for the SSE-C key
   --  @field Request_Payer Optional requester-pays admission token
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field Attributes Exact requested result groups
   type Get_Object_Attributes_Parameters is record
      Version_ID               : Ada.Strings.Unbounded.Unbounded_String;
      Max_Parts                : S3.Core.Page_Size := 1_000;
      Has_Max_Parts            : Boolean := False;
      Part_Number_Marker       : S3.Attributes.Part_Marker_Value := 0;
      Has_Part_Number_Marker   : Boolean := False;
      SSE_Customer_Algorithm   : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key         : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5     : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner    : Ada.Strings.Unbounded.Unbounded_String;
      Attributes               : S3.Attributes.Attribute_Selection;
   end record;

   --  Validate and sign one typed GetObjectAttributes request. Optional
   --  numeric members are emitted only when their presence flag is true.
   --  @param Origin Exact configured HTTP origin
   --  @param Style Path or virtual-hosted addressing
   --  @param Bucket Exact target bucket
   --  @param Key Exact target object key
   --  @param Parameters Complete modeled selection and controls
   --  @param Identity Credentials borrowed only while signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Signed request with retained response-binding facts
   function Prepare_Get_Object_Attributes
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Get_Object_Attributes_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every member in the pinned output shape. REST/XML members are grouped
   --  in Attributes; the remaining four values are response headers.
   --  @field Delete_Marker Optional delete-marker response header
   --  @field Last_Modified Optional last-modified response header
   --  @field Version_ID Optional selected-version response header
   --  @field Request_Charged Optional requester-pays response header
   --  @field Attributes Parsed bounded REST/XML response members
   type Get_Object_Attributes_Result is record
      Delete_Marker   : Optional_Boolean;
      Last_Modified   : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
      Attributes      : S3.Attributes.Get_Object_Attributes_Result;
   end record;

   --  Shape of a complete GetObjectAttributes response.
   --  @enum Object_Attributes_Found Modeled response is available
   --  @enum Get_Object_Attributes_Rejected Structured S3 rejection exists
   type Get_Object_Attributes_Outcome_Kind is
     (Object_Attributes_Found, Get_Object_Attributes_Rejected);

   --  Exact modeled success or bounded structured rejection.
   --  @field Kind Response classification
   --  @field Status Exact HTTP status
   --  @field Result Modeled response headers and REST/XML members
   --  @field Error Bounded structured provider rejection
   type Get_Object_Attributes_Outcome
     (Kind : Get_Object_Attributes_Outcome_Kind :=
        Get_Object_Attributes_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Attributes_Found =>
            Result : Get_Object_Attributes_Result;
         when Get_Object_Attributes_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a bounded REST/XML success or structured S3 error document.
   --  Optional output headers retain their modeled omission semantics.
   --  @param Status Exact HTTP status
   --  @param Payload Complete bounded response body
   --  @param Delete_Marker Optional delete-marker response header
   --  @param Last_Modified Optional last-modified response header
   --  @param Version_ID Optional selected-version response header
   --  @param Request_Charged Optional requester-pays response header
   --  @param Request_ID Optional provider request diagnostic
   --  @param Host_ID Optional provider host diagnostic
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Decode_Get_Object_Attributes_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Delete_Marker   : String := "";
      Last_Modified   : String := "";
      Version_ID      : String := "";
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Attributes_Outcome;

   --  Decode one complete GetObjectAttributes HTTP response and bind its
   --  singleton headers, requester-pays admission, and any exact requested
   --  version to the prepared request.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared GetObjectAttributes request
   --  @param Limits Bounded XML parser limits
   --  @return Typed object attributes or S3 rejection
   --  @exception Invalid_Request Prepared is not GetObjectAttributes
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_Get_Object_Attributes_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Attributes_Outcome;

   --  Execute a matching typed request, bind the complete response body,
   --  and decode every modeled output member.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Matching signed GetObjectAttributes request
   --  @param Timeout Whole-operation timeout
   --  @param Token Optional cancellation source
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Execute_Get_Object_Attributes
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Attributes_Outcome;

   --  Validate all modeled response-head fields. Successful response bodies
   --  remain unread. Rejected responses are consumed within Limits and
   --  decoded as S3 errors; bodyless conditional errors retain request IDs.
   --  @param Response Unconsumed limited HTTP response
   --  @param Token Optional cancellation source used while reading rejection
   --  @param Limits Bounded S3 error parsing limits
   --  @return Validated success metadata or structured S3 rejection
   function Decode_Get_Object_Response_Head
     (Response : in out Flyology.HTTP.Client.Response;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Head_Outcome;

   --  Decode complete GetObject response metadata after a scoped exchange has
   --  already retained the full response body. Error_Payload is decoded only
   --  for rejected statuses; successful object bytes remain caller-owned.
   --  @param Response Complete lease-free HTTP response metadata
   --  @param Error_Payload Bounded complete body for a rejected response
   --  @param Limits Structured S3 error parsing limits
   --  @return Validated success metadata or structured S3 rejection
   function Decode_Get_Object_Complete_Response
     (Response      : Flyology.HTTP.Client.Response;
      Error_Payload : String;
      Limits        : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Object_Head_Outcome;

   --  Every non-body, non-ContentLength member in the pinned PutObject input
   --  shape. The borrowed request source supplies Body and ContentLength.
   --  @field ACL Optional canned access-control policy
   --  @field Cache_Control Optional cache-control metadata
   --  @field Content_Disposition Optional content-disposition metadata
   --  @field Content_Encoding Optional content-encoding metadata
   --  @field Content_Language Optional content-language metadata
   --  @field Content_MD5 Optional caller-supplied content MD5
   --  @field Content_Type Optional content-type metadata
   --  @field Checksum_Algorithm Optional checksum algorithm selector
   --  @field Checksum_CRC32 Optional caller-supplied CRC32 checksum
   --  @field Checksum_CRC32C Optional caller-supplied CRC32C checksum
   --  @field Checksum_CRC64NVME Optional caller-supplied CRC64NVME checksum
   --  @field Checksum_SHA1 Optional caller-supplied SHA1 checksum
   --  @field Checksum_SHA256 Optional caller-supplied SHA256 checksum
   --  @field Checksum_SHA512 Optional caller-supplied SHA512 checksum
   --  @field Checksum_MD5 Optional caller-supplied MD5 checksum
   --  @field Checksum_XXHASH64 Optional caller-supplied XXHASH64 checksum
   --  @field Checksum_XXHASH3 Optional caller-supplied XXHASH3 checksum
   --  @field Checksum_XXHASH128 Optional caller-supplied XXHASH128 checksum
   --  @field Expires Optional expiration metadata
   --  @field If_Match Optional exact entity-tag precondition
   --  @field If_None_Match Optional negative entity-tag precondition
   --  @field Grant_Full_Control Optional full-control grant header
   --  @field Grant_Read Optional read grant header
   --  @field Grant_Read_ACP Optional access-control read grant header
   --  @field Grant_Write_ACP Optional access-control write grant header
   --  @field Write_Offset_Bytes Optional exact write offset
   --  @field Metadata Ordered user metadata entries
   --  @field Server_Side_Encryption Optional server encryption selector
   --  @field Storage_Class Optional storage-class selector
   --  @field Website_Redirect_Location Optional website redirect metadata
   --  @field SSE_Customer_Algorithm Optional customer-key algorithm
   --  @field SSE_Customer_Key Optional encoded customer key
   --  @field SSE_Customer_Key_MD5 Optional customer-key MD5
   --  @field SSE_KMS_Key_ID Optional KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional encoded KMS context
   --  @field Bucket_Key_Enabled Optional bucket-key selection
   --  @field Request_Payer Optional requester-pays request value
   --  @field Tagging Optional encoded object tag set
   --  @field Object_Lock_Mode Optional object-lock mode
   --  @field Object_Lock_Retain_Until_Date Optional retention timestamp
   --  @field Object_Lock_Legal_Hold_Status Optional legal-hold status
   --  @field Expected_Bucket_Owner Optional bucket-owner precondition
   type Put_Object_Parameters is record
      ACL                       : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Control             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Disposition       : Ada.Strings.Unbounded.Unbounded_String;
      Content_Encoding          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Language          : Ada.Strings.Unbounded.Unbounded_String;
      Content_MD5               : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type              : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1             : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5              : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128        : Ada.Strings.Unbounded.Unbounded_String;
      Expires                   : Ada.Strings.Unbounded.Unbounded_String;
      If_Match                  : Ada.Strings.Unbounded.Unbounded_String;
      If_None_Match             : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Full_Control        : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read                : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read_ACP            : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write_ACP           : Ada.Strings.Unbounded.Unbounded_String;
      Write_Offset_Bytes        : Optional_Byte_Count;
      Metadata                  : Metadata_Entry_Vectors.Vector;
      Server_Side_Encryption    : Ada.Strings.Unbounded.Unbounded_String;
      Storage_Class             : Ada.Strings.Unbounded.Unbounded_String;
      Website_Redirect_Location : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key          : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5      : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID            : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled        : Optional_Boolean;
      Request_Payer             : Ada.Strings.Unbounded.Unbounded_String;
      Tagging                   : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Mode          : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Retain_Until_Date :
        Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Legal_Hold_Status :
        Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare all 46 modeled PutObject inputs. Bucket and Key are explicit;
   --  Body and ContentLength are supplied later by the borrowed source.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Destination bucket
   --  @param Key Exact destination object key
   --  @param Parameters Complete modeled non-body request controls
   --  @param Payload_SHA256 Digest of future source or UNSIGNED-PAYLOAD
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Signed request prepared for a borrowed body source
   function Prepare_Put_Object
     (Origin         : Flyology.HTTP.Origin;
      Style          : Addressing_Style;
      Bucket         : String;
      Key            : String;
      Parameters     : Put_Object_Parameters;
      Payload_SHA256 : String;
      Identity       : Credentials;
      Region         : String;
      Timestamp      : String) return Prepared_Request;

   --  Every member in the pinned PutObject output shape.
   --  @field Expiration Optional modeled expiration value
   --  @field Entity_Tag Validated strong quoted entity tag
   --  @field Checksum_CRC32 Optional CRC32 checksum value
   --  @field Checksum_CRC32C Optional CRC32C checksum value
   --  @field Checksum_CRC64NVME Optional CRC64NVME checksum value
   --  @field Checksum_SHA1 Optional SHA1 checksum value
   --  @field Checksum_SHA256 Optional SHA256 checksum value
   --  @field Checksum_SHA512 Optional SHA512 checksum value
   --  @field Checksum_MD5 Optional MD5 checksum value
   --  @field Checksum_XXHASH64 Optional XXHASH64 checksum value
   --  @field Checksum_XXHASH3 Optional XXHASH3 checksum value
   --  @field Checksum_XXHASH128 Optional XXHASH128 checksum value
   --  @field Checksum_Type Empty or full-object checksum classification
   --  @field Server_Side_Encryption Optional server encryption value
   --  @field Version_ID Optional exact version response value
   --  @field SSE_Customer_Algorithm Optional customer-key algorithm
   --  @field SSE_Customer_Key_MD5 Optional customer-key MD5
   --  @field SSE_KMS_Key_ID Optional KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional encoded KMS context
   --  @field Bucket_Key_Enabled Optional bucket-key response flag
   --  @field Size Optional reported object size
   --  @field Request_Charged Optional requester-pays response value
   type Put_Object_Result is record
      Expiration                 : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag                 : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32             : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1              : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5               : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type              : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID                 : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID             : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
      Size                       : Optional_Byte_Count;
      Request_Charged            : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal PutObject response classification.
   --  @enum Object_Put Validated response metadata is present
   --  @enum Put_Object_Rejected A structured S3 rejection is present
   type Put_Object_Outcome_Kind is (Object_Put, Put_Object_Rejected);

   --  Completed PutObject response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful response metadata
   --  @field Error Structured S3 rejection
   type Put_Object_Outcome
     (Kind : Put_Object_Outcome_Kind := Put_Object_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Put =>
            Result : Put_Object_Result;
         when Put_Object_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a PutObject result after the transport has projected its
   --  singleton headers. A 200 response must have an exactly empty body, one
   --  strong quoted ETag, at most one canonical full-object checksum, and a
   --  coherent bounded encryption tuple. An omitted ChecksumType accompanying
   --  one checksum is normalized to FULL_OBJECT, the only PutObject type.
   --  Other statuses return a bounded, structured S3 error.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled PutObject response headers
   --  @param Request_ID Optional physical request identifier
   --  @param Host_ID Optional physical host identifier
   --  @param Limits Bounded S3 error parsing limits
   --  @return Validated response metadata or structured S3 rejection
   function Decode_Put_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome;

   --  Project and validate all PutObject response headers after a scoped
   --  exchange has already retained the bounded complete response body.
   --  @param Response Complete lease-free HTTP response metadata
   --  @param Payload Bounded complete response representation
   --  @param Limits Structured S3 error parsing limits
   --  @return Validated PutObject result or structured S3 rejection
   function Decode_Put_Object_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome;

   --  Decode a complete PutObject response and bind request-dependent output
   --  fields to the exact prepared request. This additive overload preserves
   --  the established transport-only decoder above for direct callers.
   --  @param Response Complete lease-free HTTP response metadata
   --  @param Payload Bounded complete response representation
   --  @param Prepared Exact request used to bind checksum and payer outputs
   --  @param Limits Structured S3 error parsing limits
   --  @return Request-bound PutObject result or structured S3 rejection
   function Decode_Put_Object_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome;

   --  Execute a prepared PutObject request and enforce physical singleton and
   --  present-nonempty semantics for all 22 modeled response headers before
   --  decoding them. Object size remains optional and accepts canonical zero.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared PutObject request
   --  @param Source Borrowed streaming object body
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Validated response metadata or structured S3 rejection
   function Execute_Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome;

   --  Modeled DeleteBucket request headers.
   --  @field Expected_Bucket_Owner Optional expected-owner header
   type Delete_Bucket_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact bodyless DeleteBucket request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Optional expected-owner header
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact DeleteBucket request
   function Prepare_Delete_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal DeleteBucket response category.
   --  @enum Bucket_Deleted The deletion completed with status 204
   --  @enum Delete_Bucket_Rejected A structured S3 rejection is present
   type Delete_Bucket_Outcome_Kind is
     (Bucket_Deleted, Delete_Bucket_Rejected);

   --  Terminal DeleteBucket result.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Error Structured S3 error on rejection
   type Delete_Bucket_Outcome
     (Kind : Delete_Bucket_Outcome_Kind := Delete_Bucket_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Deleted =>
            null;
         when Delete_Bucket_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a whitespace-only 204 or bounded S3 rejection.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier for an S3 rejection
   --  @param Host_ID Optional host identifier for an S3 rejection
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed deletion or structured S3 rejection
   function Decode_Delete_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Outcome;

   --  Execute one exact prepared DeleteBucket request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared DeleteBucket request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed deletion or structured S3 rejection
   function Execute_Delete_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Outcome;

   --  Every member in the pinned DeleteBucketCors request shape.
   --  @field Expected_Bucket_Owner Optional owner precondition header
   type Delete_Bucket_CORS_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Owner-precondition parameters for no-ID configuration deletions.
   subtype Delete_Bucket_Configuration_Parameters is
     Delete_Bucket_CORS_Parameters;

   --  Build and sign one bodyless DeleteBucketCors request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose complete CORS configuration is removed
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Immutable prepared request
   function Prepare_Delete_Bucket_CORS
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_CORS_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Terminal response category for DeleteBucketCors.
   --  @enum Bucket_CORS_Deleted Exact empty 204 response
   --  @enum Delete_Bucket_CORS_Rejected Structured non-204 S3 response
   type Delete_Bucket_CORS_Outcome_Kind is
     (Bucket_CORS_Deleted, Delete_Bucket_CORS_Rejected);

   --  Typed DeleteBucketCors result retained as the compatibility base for
   --  the shared bodyless bucket-configuration response family.
   --  @field Kind Terminal response category
   --  @field Status Exact HTTP response status
   --  @field Error Structured S3 error for a rejected response
   type Delete_Bucket_CORS_Outcome
     (Kind : Delete_Bucket_CORS_Outcome_Kind :=
       Delete_Bucket_CORS_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_CORS_Deleted =>
            null;
         when Delete_Bucket_CORS_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Shared aliases preserve the original CORS type and literals while the
   --  exact operation-specific executors reuse one response implementation.
   subtype Delete_Bucket_Configuration_Outcome_Kind is
     Delete_Bucket_CORS_Outcome_Kind;
   --  Exact alias for Bucket_CORS_Deleted.
   Configuration_Deleted : constant
     Delete_Bucket_Configuration_Outcome_Kind := Bucket_CORS_Deleted;
   --  Exact alias for Delete_Bucket_CORS_Rejected.
   Delete_Configuration_Rejected : constant
     Delete_Bucket_Configuration_Outcome_Kind :=
       Delete_Bucket_CORS_Rejected;
   --  Alias of the shared CORS outcome record.
   subtype Delete_Bucket_Configuration_Outcome is
     Delete_Bucket_CORS_Outcome;

   --  Decode the common exact-empty 204 or bounded S3 rejection.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed configuration deletion or S3 rejection
   function Decode_Delete_Bucket_Configuration_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;

   --  DeleteBucketCors uses the common exact-empty 204 response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed CORS deletion or structured S3 rejection
   function Decode_Delete_Bucket_CORS_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_CORS_Outcome
      renames Decode_Delete_Bucket_Configuration_Response;

   --  Execute one prepared synchronous DeleteBucketCors request and release
   --  its response before return.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared DeleteBucketCors request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed CORS deletion or structured S3 rejection
   function Execute_Delete_Bucket_CORS
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_CORS_Outcome;

   --  Parameters for a named bodyless bucket-configuration delete.
   --  @field ID Required generated Id query value
   --  @field Expected_Bucket_Owner Optional owner precondition header
   type Delete_Bucket_Configuration_With_ID_Parameters is record
      ID                    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one exact DeleteBucketAnalyticsConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Required nonempty Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Analytics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketEncryption request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Encryption
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketIntelligentTieringConfiguration
   --  request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Required nonempty Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Intelligent_Tiering_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketInventoryConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Required nonempty Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Inventory_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketLifecycle request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Lifecycle
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketMetadataConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Metadata_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketMetadataTableConfiguration
   --  request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Metadata_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketMetricsConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Required nonempty Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Metrics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketOwnershipControls request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Ownership_Controls
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketPolicy request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Policy
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketReplication request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Replication
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketWebsite request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Bucket_Website
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeletePublicAccessBlock request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Delete_Public_Access_Block
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Execute one exact prepared DeleteBucketAnalyticsConfiguration request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketEncryption request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketIntelligentTieringConfiguration
   --  request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketInventoryConfiguration request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketLifecycle request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Lifecycle
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketMetadataConfiguration request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketMetadataTableConfiguration
   --  request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketMetricsConfiguration request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketOwnershipControls request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketPolicy request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketReplication request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketWebsite request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Bucket_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeletePublicAccessBlock request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Exact-empty 204 completion or structured S3 rejection
   function Execute_Delete_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;

   --  Common owner precondition for simple bucket-control reads.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Get_Bucket_Control_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete request parameters for a named bucket-control read.
   --  @field ID Required modeled Id query value
   --  @field Expected_Bucket_Owner Optional owner precondition header
   type Get_Bucket_Control_With_ID_Parameters is record
      ID                    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete shared request shape for paginated bucket-configuration
   --  reads. Presence preserves an explicitly empty continuation token
   --  independently from omission; no page-size policy is client-selected.
   --  @field Continuation_Token Exact optional request cursor
   --  @field Has_Continuation_Token Whether the cursor member is present
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type List_Bucket_Configuration_Parameters is record
      Continuation_Token     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean;
      Expected_Bucket_Owner  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete GetBucketAccelerateConfiguration request parameters.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Request_Payer Optional exact requester-pays admission value
   type Get_Bucket_Accelerate_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exactly bound GetBucketAccelerateConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner and requester-pays request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact acceleration request
   function Prepare_Get_Bucket_Accelerate_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Accelerate_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketAbac request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketAbac request
   function Prepare_Get_Bucket_Abac
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketPolicy request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketPolicy request
   function Prepare_Get_Bucket_Policy
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketPolicyStatus request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketPolicyStatus request
   function Prepare_Get_Bucket_Policy_Status
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketRequestPayment request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketRequestPayment request
   function Prepare_Get_Bucket_Request_Payment
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetPublicAccessBlock request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetPublicAccessBlock request
   function Prepare_Get_Public_Access_Block
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketOwnershipControls request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketOwnershipControls request
   function Prepare_Get_Bucket_Ownership_Controls
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketCors request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to GetBucketCors
   function Prepare_Get_Bucket_CORS
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketEncryption request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to GetBucketEncryption
   function Prepare_Get_Bucket_Encryption
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketLifecycleConfiguration request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to the lifecycle operation
   function Prepare_Get_Bucket_Lifecycle_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketNotificationConfiguration request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to the current notification read
   function Prepare_Get_Bucket_Notification_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketReplication request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to the current replication read
   function Prepare_Get_Bucket_Replication
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketLogging request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketLogging request
   function Prepare_Get_Bucket_Logging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketWebsite request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact GetBucketWebsite request
   function Prepare_Get_Bucket_Website
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketMetadataConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Owner-precondition request parameters
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact operation request
   function Prepare_Get_Bucket_Metadata_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketMetricsConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Modeled Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact metrics-configuration request
   function Prepare_Get_Bucket_Metrics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound ListBucketMetricsConfigurations request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Presence-preserving cursor and optional owner
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact metrics-configurations list request
   function Prepare_List_Bucket_Metrics_Configurations
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : List_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound ListBucketAnalyticsConfigurations request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Presence-preserving cursor and optional owner
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact analytics-configurations list request
   function Prepare_List_Bucket_Analytics_Configurations
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : List_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketAnalyticsConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Modeled Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact analytics-configuration request
   function Prepare_Get_Bucket_Analytics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketIntelligentTieringConfiguration
   --  request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Modeled Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact Intelligent-Tiering request
   function Prepare_Get_Bucket_Intelligent_Tiering_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound ListBucketIntelligentTieringConfigurations
   --  request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Presence-preserving cursor and optional owner
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact Intelligent-Tiering list request
   function Prepare_List_Bucket_Intelligent_Tiering_Configurations
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : List_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketInventoryConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Modeled Id and optional owner precondition
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact inventory-configuration request
   function Prepare_Get_Bucket_Inventory_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound ListBucketInventoryConfigurations request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Presence-preserving cursor and optional owner
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact inventory-configurations list request
   function Prepare_List_Bucket_Inventory_Configurations
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : List_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketAcl request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to GetBucketAcl
   function Prepare_Get_Bucket_ACL
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketMetadataTableConfiguration request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Parameters Optional modeled owner precondition
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to the metadataTable operation
   function Prepare_Get_Bucket_Metadata_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Shared terminal classification for strict bucket-control reads.
   --  @enum Bucket_Control_Found Exact 200 response decoded successfully
   --  @enum Get_Bucket_Control_Rejected Bounded non-200 S3 rejection
   type Get_Bucket_Control_Outcome_Kind is
     (Bucket_Control_Found, Get_Bucket_Control_Rejected);

   --  Existing API-policy classification: 500 is only the deterministic
   --  default-aggregate sentinel. Actual decoded outcomes always preserve the
   --  physical status; changing the default affects source-level aggregates.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Configuration Optional acceleration status on success
   --  @field Request_Charged Optional modeled response header on success
   --  @field Error Structured S3 error on rejection
   type Get_Bucket_Accelerate_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
       Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration : S3.Bucket_Controls.Accelerate_Status;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketAbac outcome.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Configuration Optional modeled ABAC status on success
   --  @field Error Structured S3 error on rejection
   type Get_Bucket_Abac_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
       Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration : S3.Bucket_Controls.Abac_Status;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Complete same-response GetBucketPolicy outcome.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Policy Exact bounded response payload on success
   --  @field Error Structured S3 error on rejection
   type Get_Bucket_Policy_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
       Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Policy : Ada.Strings.Unbounded.Unbounded_String;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketPolicyStatus outcome.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Is_Public Optional modeled Boolean on success
   --  @field Error Structured S3 error on rejection
   type Get_Bucket_Policy_Status_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
       Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Is_Public : S3.Bucket_Controls.Optional_Boolean;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketRequestPayment outcome.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Payment Optional modeled payer value on success
   --  @field Error Structured S3 error on rejection
   type Get_Bucket_Request_Payment_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
       Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Payment : S3.Bucket_Controls.Payer;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetPublicAccessBlock outcome.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Configuration Four optional modeled Booleans on success
   --  @field Error Structured S3 error on rejection
   type Get_Public_Access_Block_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
       Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration :
              S3.Bucket_Controls.Public_Access_Block_Configuration;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketOwnershipControls outcome.  The shared
   --  500 default is only the established deterministic aggregate sentinel.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Optional outer payload and required decoded rules
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Ownership_Controls_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
        Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration :
              S3.Bucket_Controls.Ownership_Controls_Configuration;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketCors outcome.  The 500 default is only
   --  the established deterministic aggregate sentinel.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Optional payload and decoded flattened rule lists
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_CORS_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
        Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration : S3.Bucket_Controls.CORS_Configuration;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketEncryption outcome.  The 500 default is
   --  the established deterministic aggregate sentinel only.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Optional typed encryption configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Encryption_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
        Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration : S3.Encryption.Encryption_Configuration;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving GetBucketLifecycleConfiguration outcome. The 500
   --  default is the established deterministic aggregate sentinel only.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Optional typed lifecycle configuration
   --  @field Transition_Default_Minimum_Object_Size Optional exact header
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Lifecycle_Configuration_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
        Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration : S3.Lifecycle.Lifecycle_Configuration;
            Transition_Default_Minimum_Object_Size :
              S3.Lifecycle.Transition_Default_Minimum_Size :=
                S3.Lifecycle.Transition_Minimum_Absent;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Strict GetBucketNotificationConfiguration outcome with no public
   --  aggregate defaults. Kind determines whether Configuration or Error is
   --  present; every decoded status is the physical response status.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current notification configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Notification_Configuration_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Notifications.Notification_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketReplication outcome with physical status preserved.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current replication configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Replication_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Replication.Replication_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketMetricsConfiguration outcome with physical status.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current metrics configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Metrics_Configuration_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Metrics.Metrics_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Shape of one strict ListBucketMetricsConfigurations response.
   --  @enum Bucket_Metrics_Configurations_Listed Complete page exists
   --  @enum List_Bucket_Metrics_Configurations_Rejected S3 rejected the read
   type List_Bucket_Metrics_Configurations_Outcome_Kind is
     (Bucket_Metrics_Configurations_Listed,
      List_Bucket_Metrics_Configurations_Rejected);

   --  Strict metrics-configuration page or structured S3 rejection. Kind
   --  determines which payload is meaningful; no public sentinel is chosen.
   --  @field Kind Whether a complete page or rejection exists
   --  @field Status Exact physical HTTP status
   --  @field Result Complete presence-preserving page
   --  @field Error Structured bounded S3 rejection
   type List_Bucket_Metrics_Configurations_Outcome is record
      Kind   : List_Bucket_Metrics_Configurations_Outcome_Kind;
      Status : Flyology.HTTP.Status_Code;
      Result : S3.Metrics.Metrics_Configuration_Page;
      Error  : S3.Errors.Error_Response;
   end record;

   --  Shape of one strict ListBucketAnalyticsConfigurations response.
   --  @enum Bucket_Analytics_Configurations_Listed Complete page exists
   --  @enum List_Bucket_Analytics_Configurations_Rejected S3 rejected read
   type List_Bucket_Analytics_Configurations_Outcome_Kind is
     (Bucket_Analytics_Configurations_Listed,
      List_Bucket_Analytics_Configurations_Rejected);

   --  Strict analytics-configuration page or structured S3 rejection. Kind
   --  determines which payload is meaningful; no public sentinel is chosen.
   --  @field Kind Whether a complete page or rejection exists
   --  @field Status Exact physical HTTP status
   --  @field Result Complete presence-preserving page
   --  @field Error Structured bounded S3 rejection
   type List_Bucket_Analytics_Configurations_Outcome is record
      Kind   : List_Bucket_Analytics_Configurations_Outcome_Kind;
      Status : Flyology.HTTP.Status_Code;
      Result : S3.Analytics.Analytics_Configuration_Page;
      Error  : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketAnalyticsConfiguration outcome with physical status.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current analytics configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Analytics_Configuration_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Analytics.Analytics_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;
   --  Strict GetBucketIntelligentTieringConfiguration outcome with physical
   --  status.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current Intelligent-Tiering configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Intelligent_Tiering_Configuration_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Intelligent_Tiering.Intelligent_Tiering_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Shape of one strict ListBucketIntelligentTieringConfigurations response.
   --  @enum Bucket_Intelligent_Tiering_Configurations_Listed Complete page
   --  @enum List_Bucket_Intelligent_Tiering_Configurations_Rejected Rejected
   type List_Bucket_Intelligent_Tiering_Configurations_Outcome_Kind is
     (Bucket_Intelligent_Tiering_Configurations_Listed,
      List_Bucket_Intelligent_Tiering_Configurations_Rejected);

   --  Strict Intelligent-Tiering page or structured S3 rejection. Kind
   --  determines which payload is meaningful; no public sentinel is chosen.
   --  @field Kind Whether a complete page or rejection exists
   --  @field Status Exact physical HTTP status
   --  @field Result Complete presence-preserving page
   --  @field Error Structured bounded S3 rejection
   type List_Bucket_Intelligent_Tiering_Configurations_Outcome is record
      Kind   : List_Bucket_Intelligent_Tiering_Configurations_Outcome_Kind;
      Status : Flyology.HTTP.Status_Code;
      Result :
        S3.Intelligent_Tiering.Intelligent_Tiering_Configuration_Page;
      Error  : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketInventoryConfiguration outcome with physical status.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current inventory configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Inventory_Configuration_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Inventory.Inventory_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Shape of one strict ListBucketInventoryConfigurations response.
   --  @enum Bucket_Inventory_Configurations_Listed Complete page exists
   --  @enum List_Bucket_Inventory_Configurations_Rejected S3 rejected read
   type List_Bucket_Inventory_Configurations_Outcome_Kind is
     (Bucket_Inventory_Configurations_Listed,
      List_Bucket_Inventory_Configurations_Rejected);

   --  Strict inventory-configuration page or structured S3 rejection. Kind
   --  determines which payload is meaningful; no public sentinel is chosen.
   --  @field Kind Whether a complete page or rejection exists
   --  @field Status Exact physical HTTP status
   --  @field Result Complete presence-preserving page
   --  @field Error Structured bounded S3 rejection
   type List_Bucket_Inventory_Configurations_Outcome is record
      Kind   : List_Bucket_Inventory_Configurations_Outcome_Kind;
      Status : Flyology.HTTP.Status_Code;
      Result : S3.Inventory.Inventory_Configuration_Page;
      Error  : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketLogging outcome with physical status preserved.
   --  @field Kind Whether logging status or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Presence-preserving logging status
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Logging_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Logging.Logging_Status;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketWebsite outcome with physical status preserved.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete presence-preserving website configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Website_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Website.Website_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Strict GetBucketMetadataConfiguration outcome with physical status.
   --  @field Kind Whether configuration or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Complete current metadata configuration
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Metadata_Configuration_Outcome is record
      Kind          : Get_Bucket_Control_Outcome_Kind;
      Status        : Flyology.HTTP.Status_Code;
      Configuration : S3.Metadata_Configurations.Metadata_Configuration;
      Error         : S3.Errors.Error_Response;
   end record;

   --  Presence-preserving GetBucketAcl outcome.  The 500 default is the
   --  established deterministic aggregate sentinel only.
   --  @field Kind Whether policy or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Policy Optional typed access-control policy
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_ACL_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
        Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Policy : S3.ACL.Access_Control_Policy;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Presence-preserving metadata-table configuration outcome.  The 500
   --  default is the established deterministic aggregate sentinel only.
   --  @field Kind Whether a result or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Configuration Optional typed metadata-table result
   --  @field Error Structured bounded S3 rejection
   type Get_Bucket_Metadata_Table_Configuration_Outcome
     (Kind : Get_Bucket_Control_Outcome_Kind :=
        Get_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Found =>
            Configuration :
              S3.Metadata_Tables.Metadata_Table_Configuration_Result;
         when Get_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded GetBucketAccelerateConfiguration response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Request_Charged Optional requester-pays response value
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving acceleration status or S3 rejection
   function Decode_Get_Bucket_Accelerate_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Request_Charged : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Accelerate_Outcome;
   --  Decode one complete bounded GetBucketAbac XML response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving ABAC status or S3 rejection
   function Decode_Get_Bucket_Abac_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Abac_Outcome;
   --  Decode one complete bounded raw GetBucketPolicy response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Response byte and S3 error parsing limits
   --  @return Exact bounded policy bytes or S3 rejection
   function Decode_Get_Bucket_Policy_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Outcome;
   --  Decode one complete bounded GetBucketPolicyStatus XML response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving public-status value or S3 rejection
   function Decode_Get_Bucket_Policy_Status_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Status_Outcome;
   --  Decode one complete bounded GetBucketRequestPayment XML response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving payer value or S3 rejection
   function Decode_Get_Bucket_Request_Payment_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Request_Payment_Outcome;
   --  Decode one complete bounded GetPublicAccessBlock XML response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving block settings or S3 rejection
   function Decode_Get_Public_Access_Block_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Public_Access_Block_Outcome;
   --  Decode one complete bounded GetBucketOwnershipControls response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier
   --  @param Host_ID Optional host identifier
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Typed configuration or structured S3 rejection
   function Decode_Get_Bucket_Ownership_Controls_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Ownership_Controls_Outcome;
   --  Decode one complete bounded GetBucketCors response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed CORS configuration or strict S3 rejection
   function Decode_Get_Bucket_CORS_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_CORS_Outcome;
   --  Decode one complete bounded GetBucketEncryption response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed encryption configuration or strict S3 rejection
   function Decode_Get_Bucket_Encryption_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Encryption_Outcome;
   --  Decode one complete bounded GetBucketLifecycleConfiguration response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Transition_Default_Minimum_Object_Size Optional exact header
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed lifecycle configuration or strict S3 rejection
   function Decode_Get_Bucket_Lifecycle_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Transition_Default_Minimum_Object_Size : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Lifecycle_Configuration_Outcome;
   --  Decode one complete bounded GetBucketNotificationConfiguration response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed notification configuration or strict S3 rejection
   function Decode_Get_Bucket_Notification_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Notification_Configuration_Outcome;
   --  Decode one complete bounded GetBucketReplication response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed replication configuration or strict S3 rejection
   function Decode_Get_Bucket_Replication_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Replication_Outcome;
   --  Decode one complete bounded GetBucketMetricsConfiguration response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete metrics configuration or structured S3 rejection
   function Decode_Get_Bucket_Metrics_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Metrics_Configuration_Outcome;
   --  Decode one complete bounded ListBucketMetricsConfigurations response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving metrics page or structured S3 rejection
   function Decode_List_Bucket_Metrics_Configurations_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Metrics_Configurations_Outcome;
   --  Decode one complete bounded ListBucketAnalyticsConfigurations response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving analytics page or structured S3 rejection
   function Decode_List_Bucket_Analytics_Configurations_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Analytics_Configurations_Outcome;
   --  Decode one complete bounded GetBucketAnalyticsConfiguration response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete analytics configuration or structured S3 rejection
   function Decode_Get_Bucket_Analytics_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Analytics_Configuration_Outcome;
   --  Decode one complete bounded GetBucketIntelligentTieringConfiguration
   --  response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete Intelligent-Tiering configuration or S3 rejection
   function Decode_Get_Bucket_Intelligent_Tiering_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Intelligent_Tiering_Configuration_Outcome;
   --  Decode one complete bounded
   --  ListBucketIntelligentTieringConfigurations response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving Intelligent-Tiering page or S3 rejection
   function Decode_List_Bucket_Intelligent_Tiering_Configurations_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Intelligent_Tiering_Configurations_Outcome;
   --  Decode one complete bounded GetBucketInventoryConfiguration response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete inventory configuration or structured S3 rejection
   function Decode_Get_Bucket_Inventory_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Inventory_Configuration_Outcome;
   --  Decode one complete bounded ListBucketInventoryConfigurations response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving inventory page or structured S3 rejection
   function Decode_List_Bucket_Inventory_Configurations_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Inventory_Configurations_Outcome;
   --  Decode one complete bounded GetBucketLogging response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Typed logging status or structured S3 rejection
   function Decode_Get_Bucket_Logging_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Logging_Outcome;
   --  Decode one complete bounded GetBucketWebsite response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Typed website configuration or structured S3 rejection
   function Decode_Get_Bucket_Website_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Website_Outcome;
   --  Decode one complete bounded GetBucketMetadataConfiguration response.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Typed metadata configuration or structured S3 rejection
   function Decode_Get_Bucket_Metadata_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Metadata_Configuration_Outcome;
   --  Decode one complete bounded GetBucketAcl response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed access-control policy or strict S3 rejection
   function Decode_Get_Bucket_ACL_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_ACL_Outcome;
   --  Decode one complete bounded metadata-table configuration response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed metadata-table result or strict S3 rejection
   function Decode_Get_Bucket_Metadata_Table_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Metadata_Table_Configuration_Outcome;

   --  Execute one exact prepared GetBucketAccelerateConfiguration request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving acceleration status or S3 rejection
   function Execute_Get_Bucket_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Accelerate_Outcome;
   --  Execute one exact prepared GetBucketAbac request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving ABAC status or S3 rejection
   function Execute_Get_Bucket_Abac
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Abac_Outcome;
   --  Execute one exact prepared GetBucketPolicy request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Response byte and S3 error parsing limits
   --  @return Exact bounded policy bytes or S3 rejection
   function Execute_Get_Bucket_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Outcome;
   --  Execute one exact prepared GetBucketPolicyStatus request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving public-status value or S3 rejection
   function Execute_Get_Bucket_Policy_Status
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Status_Outcome;
   --  Execute one exact prepared GetBucketRequestPayment request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving payer value or S3 rejection
   function Execute_Get_Bucket_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Request_Payment_Outcome;
   --  Execute one exact prepared GetPublicAccessBlock request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Presence-preserving block settings or S3 rejection
   function Execute_Get_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Public_Access_Block_Outcome;
   --  Execute one exact prepared GetBucketOwnershipControls request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded XML and S3 error parsing limits
   --  @return Typed configuration or structured S3 rejection
   function Execute_Get_Bucket_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Ownership_Controls_Outcome;
   --  Execute one exact prepared GetBucketCors request.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request returned by Prepare_Get_Bucket_CORS
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed CORS configuration or strict S3 rejection
   function Execute_Get_Bucket_CORS
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_CORS_Outcome;
   --  Execute one exact prepared GetBucketEncryption request.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request returned by Prepare_Get_Bucket_Encryption
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed encryption configuration or strict S3 rejection
   function Execute_Get_Bucket_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Encryption_Outcome;
   --  Execute one prepared GetBucketLifecycleConfiguration exchange. The
   --  30-second default is the established low-level synchronous-client
   --  compatibility budget; callers may select another whole-call budget.
   --  @param Client Configured caller-owned synchronous HTTP client
   --  @param Prepared Request returned by the exact lifecycle preparer
   --  @param Timeout Whole blocking exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed configuration or bounded S3 rejection
   function Execute_Get_Bucket_Lifecycle_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Lifecycle_Configuration_Outcome;
   --  Execute one prepared GetBucketNotificationConfiguration exchange.
   --  @param Client Configured caller-owned synchronous HTTP client
   --  @param Prepared Request returned by the exact notification preparer
   --  @param Timeout Caller-selected whole blocking exchange budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed configuration or bounded S3 rejection
   function Execute_Get_Bucket_Notification_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Notification_Configuration_Outcome;
   --  Execute one exact prepared GetBucketReplication exchange.
   --  @param Client Configured caller-owned synchronous HTTP client
   --  @param Prepared Request returned by the exact replication preparer
   --  @param Timeout Caller-selected whole blocking exchange budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed configuration or bounded S3 rejection
   function Execute_Get_Bucket_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Replication_Outcome;
   --  Execute one exact prepared GetBucketMetricsConfiguration exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete metrics configuration or structured S3 rejection
   function Execute_Get_Bucket_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Metrics_Configuration_Outcome;
   --  Execute one exact prepared ListBucketMetricsConfigurations exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving metrics page or structured S3 rejection
   function Execute_List_Bucket_Metrics_Configurations
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Metrics_Configurations_Outcome;
   --  Execute one exact prepared ListBucketAnalyticsConfigurations exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving analytics page or structured S3 rejection
   function Execute_List_Bucket_Analytics_Configurations
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Analytics_Configurations_Outcome;
   --  Execute one exact prepared GetBucketAnalyticsConfiguration exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete analytics configuration or structured S3 rejection
   function Execute_Get_Bucket_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Analytics_Configuration_Outcome;
   --  Execute one exact prepared GetBucketIntelligentTieringConfiguration
   --  exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete Intelligent-Tiering configuration or S3 rejection
   function Execute_Get_Bucket_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Intelligent_Tiering_Configuration_Outcome;
   --  Execute one exact prepared
   --  ListBucketIntelligentTieringConfigurations exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving Intelligent-Tiering page or S3 rejection
   function Execute_List_Bucket_Intelligent_Tiering_Configurations
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Intelligent_Tiering_Configurations_Outcome;
   --  Execute one exact prepared GetBucketInventoryConfiguration exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Complete inventory configuration or structured S3 rejection
   function Execute_Get_Bucket_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Inventory_Configuration_Outcome;
   --  Execute one exact prepared ListBucketInventoryConfigurations exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Presence-preserving inventory page or structured S3 rejection
   function Execute_List_Bucket_Inventory_Configurations
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return List_Bucket_Inventory_Configurations_Outcome;
   --  Execute one exact prepared GetBucketLogging exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Typed logging status or structured S3 rejection
   function Execute_Get_Bucket_Logging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Logging_Outcome;
   --  Execute one exact prepared GetBucketWebsite exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Typed website configuration or structured S3 rejection
   function Execute_Get_Bucket_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Website_Outcome;
   --  Execute one exact prepared GetBucketMetadataConfiguration exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Typed metadata configuration or structured S3 rejection
   function Execute_Get_Bucket_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Get_Bucket_Metadata_Configuration_Outcome;
   --  Execute one exact prepared GetBucketAcl request.
   --  The 30-second default is the established low-level synchronous-client
   --  compatibility budget; callers may select a different absolute budget.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request returned by Prepare_Get_Bucket_ACL
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed access-control policy or strict S3 rejection
   function Execute_Get_Bucket_ACL
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_ACL_Outcome;
   --  Execute one exact prepared metadata-table configuration request.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching prepare operation
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed metadata-table result or strict S3 rejection
   function Execute_Get_Bucket_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Metadata_Table_Configuration_Outcome;

   --  Shared physical controls for small bucket-configuration mutations.
   --  Empty Content_MD5 requests automatic generation where the model admits
   --  that member; accelerate rejects a supplied value because it has none.
   --  @field Content_MD5 Optional exact base64 MD5 override
   --  @field Checksum_Algorithm Optional one of the ten modeled algorithms
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Bucket_Control_Mutation_Parameters is record
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Compatibility name retained for the established PUT APIs.
   subtype Put_Bucket_Control_Parameters is
     Bucket_Control_Mutation_Parameters;

   --  Complete physical controls for PutBucketLifecycleConfiguration.
   --  The transition field is empty for absence or one exact modeled wire
   --  value; callers therefore select presence explicitly rather than inherit
   --  a library lifecycle policy.
   --  @field Checksum_Algorithm Required one of the ten modeled algorithms
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Transition_Default_Minimum_Object_Size Empty or exact header
   type Put_Bucket_Lifecycle_Configuration_Parameters is record
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Transition_Default_Minimum_Object_Size :
        Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete physical controls for current
   --  PutBucketNotificationConfiguration.
   --  Both optional headers preserve absence versus an exact caller value.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Skip_Destination_Validation Optional explicit Boolean header
   type Put_Bucket_Notification_Configuration_Parameters is record
      Expected_Bucket_Owner       : Ada.Strings.Unbounded.Unbounded_String;
      Skip_Destination_Validation : Optional_Boolean;
   end record;

   --  Complete physical controls for current PutBucketReplication. Empty
   --  Content_MD5 requests automatic generation over the exact owned XML;
   --  the checksum algorithm remains a required caller selection.
   --  @field Content_MD5 Optional exact base64 MD5 override
   --  @field Checksum_Algorithm Required one of the ten modeled algorithms
   --  @field Token Optional exact object-lock enablement token
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_Replication_Parameters is record
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Token                 : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete modeled non-body members for
   --  PutBucketAnalyticsConfiguration. The identifier is the required `id`
   --  query value; the configuration body retains its independently modeled
   --  required Id member without an inferred equality constraint.
   --  @field ID Required generated Id query value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_Analytics_Configuration_Parameters is record
      ID                    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete modeled non-body members for
   --  PutBucketIntelligentTieringConfiguration. The identifier is the
   --  required `id` query value; the configuration body retains its
   --  independently modeled required Id member without an inferred equality
   --  constraint.
   --  @field ID Required generated Id query value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_Intelligent_Tiering_Configuration_Parameters is record
      ID                    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete modeled non-body members for
   --  PutBucketMetricsConfiguration. The identifier is the required `id`
   --  query value; the configuration body retains its independently modeled
   --  required Id member without an inferred equality constraint.
   --  @field ID Required generated Id query value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_Metrics_Configuration_Parameters is record
      ID                    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact CreateBucketMetadataTableConfiguration request.
   --  The request is a signed POST with the required Content-MD5, optional
   --  modeled SDK checksum, and one bounded REST/XML destination payload.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required S3 Tables destination strings
   --  @param Parameters Optional MD5 override, SDK checksum, and owner control
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed request bound to the modeled create operation
   function Prepare_Create_Bucket_Metadata_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Metadata_Tables.S3_Tables_Destination;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Prepare one exact PutBucketAbac request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose ABAC status is replaced
   --  @param Value Required modeled ABAC status
   --  @param Parameters Optional integrity and owner controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared request owning the exact one-shot ABAC body
   function Prepare_Put_Bucket_Abac
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Value : S3.Bucket_Controls.Abac_Status;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutBucketAccelerateConfiguration request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose acceleration status is replaced
   --  @param Value Required modeled acceleration status
   --  @param Parameters Checksum and owner controls with no Content-MD5
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared request owning the exact one-shot acceleration body
   function Prepare_Put_Bucket_Accelerate_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Value : S3.Bucket_Controls.Accelerate_Status;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutBucketRequestPayment request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose payer setting is replaced
   --  @param Value Required modeled payer setting
   --  @param Parameters Optional integrity and owner controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared request owning the exact one-shot payer body
   function Prepare_Put_Bucket_Request_Payment
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Value : S3.Bucket_Controls.Payer;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutPublicAccessBlock request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose public-access block is replaced
   --  @param Value Required public-access-block configuration
   --  @param Parameters Optional integrity and owner controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared request owning the exact one-shot access-block body
   function Prepare_Put_Public_Access_Block
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Bucket_Controls.Public_Access_Block_Configuration;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutBucketOwnershipControls request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required nonempty ownership-control rules
   --  @param Parameters Optional MD5, SDK checksum, and owner controls
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed request bound to PutBucketOwnershipControls
   function Prepare_Put_Bucket_Ownership_Controls
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Bucket_Controls.Ownership_Controls_Configuration;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Prepare one exact PutBucketEncryption request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required nonempty encryption-rule configuration
   --  @param Parameters Optional MD5, SDK checksum, and owner controls
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed request bound to PutBucketEncryption
   function Prepare_Put_Bucket_Encryption
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Encryption.Encryption_Configuration;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Prepare one exact PutBucketLifecycleConfiguration request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Absent body or present nonempty lifecycle-rule graph
   --  @param Parameters Complete checksum, owner, and transition controls
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed request bound to the current lifecycle operation
   function Prepare_Put_Bucket_Lifecycle_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Lifecycle.Lifecycle_Configuration;
      Parameters : Put_Bucket_Lifecycle_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Prepare one exactly bound PutBucketNotificationConfiguration request.
   --  The current model has no request-checksum or Content-MD5 member; SigV4
   --  still signs the exact owned serialized payload hash.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required complete current notification configuration
   --  @param Parameters Optional owner and destination-validation headers
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed one-shot request owning its exact body
   function Prepare_Put_Bucket_Notification_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Notifications.Notification_Configuration;
      Parameters : Put_Bucket_Notification_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Prepare one exactly bound PutBucketReplication request. The exact XML
   --  and signed checksums are owned by the returned one-shot request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required complete replication configuration
   --  @param Parameters MD5, required checksum, token, and owner controls
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed one-shot request bound to replication replacement
   function Prepare_Put_Bucket_Replication
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Replication.Replication_Configuration;
      Parameters : Put_Bucket_Replication_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Prepare one exactly bound PutBucketAnalyticsConfiguration request. The
   --  returned request owns the exact serialized and signed one-shot XML.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required analytics configuration payload
   --  @param Parameters Required query identifier and optional owner header
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed one-shot request bound to the modeled operation
   function Prepare_Put_Bucket_Analytics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Analytics.Analytics_Configuration;
      Parameters : Put_Bucket_Analytics_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Prepare one exactly bound
   --  PutBucketIntelligentTieringConfiguration request. The returned request
   --  owns the exact serialized and signed one-shot XML.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required Intelligent-Tiering configuration payload
   --  @param Parameters Required query identifier and optional owner header
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed one-shot request bound to the modeled operation
   function Prepare_Put_Bucket_Intelligent_Tiering_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Intelligent_Tiering.Intelligent_Tiering_Configuration;
      Parameters : Put_Bucket_Intelligent_Tiering_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Prepare one exactly bound PutBucketMetricsConfiguration request. The
   --  returned request owns the exact serialized and signed one-shot XML.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required metrics configuration payload
   --  @param Parameters Required query identifier and optional owner header
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed one-shot request bound to the modeled operation
   function Prepare_Put_Bucket_Metrics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Metrics.Metrics_Configuration;
      Parameters : Put_Bucket_Metrics_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Prepare one exact PutBucketCors request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Value Required nonempty CORS-rule configuration
   --  @param Parameters Optional MD5, SDK checksum, and owner controls
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @param Limits Caller-selected XML serialization limits
   --  @return Fully signed request bound to PutBucketCors
   function Prepare_Put_Bucket_CORS
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Bucket_Controls.CORS_Configuration;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Terminal body-only bucket-control response classification.
   --  @enum Bucket_Control_Updated The control update completed
   --  @enum Put_Bucket_Control_Rejected A structured rejection is present
   type Put_Bucket_Control_Outcome_Kind is
     (Bucket_Control_Updated, Put_Bucket_Control_Rejected);

   --  Terminal result shared by body-only bucket-control updates.
   --  Existing API-policy classification: 500 is the aggregate sentinel;
   --  decoded outcomes preserve the physical status.
   --  @field Kind Active response variant
   --  @field Status Physical HTTP status
   --  @field Error Structured S3 error on rejection
   type Put_Bucket_Control_Outcome
     (Kind : Put_Bucket_Control_Outcome_Kind :=
       Put_Bucket_Control_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Control_Updated =>
            null;
         when Put_Bucket_Control_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Terminal result for PutBucketLifecycleConfiguration. The same response
   --  preserves the physical status, optional exact transition header, and
   --  structured error storage. Kind determines which fields are meaningful;
   --  no public initialization or lifecycle default is selected.
   --  @field Kind Whether the update or a strict S3 error was returned
   --  @field Status Exact physical HTTP status
   --  @field Transition_Default_Minimum_Object_Size Optional exact header
   --  @field Error Structured bounded S3 rejection when Kind is rejected
   type Put_Bucket_Lifecycle_Configuration_Outcome is record
      Kind : Put_Bucket_Control_Outcome_Kind;
      Status : Flyology.HTTP.Status_Code;
      Transition_Default_Minimum_Object_Size :
        S3.Lifecycle.Transition_Default_Minimum_Size;
      Error : S3.Errors.Error_Response;
   end record;

   --  Decode a whitespace-only 200 or bounded S3 rejection.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Request_ID Optional request identifier for an S3 rejection
   --  @param Host_ID Optional host identifier for an S3 rejection
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed update or structured S3 rejection
   function Decode_Put_Bucket_Control_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Decode one complete PutBucketLifecycleConfiguration response.
   --  @param Status Exact physical response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Optional bounded S3 request identifier
   --  @param Host_ID Optional bounded S3 host identifier
   --  @param Transition_Default_Minimum_Object_Size Optional exact header
   --  @param Limits Caller-selected error XML limits
   --  @return Typed update success or strict S3 rejection
   function Decode_Put_Bucket_Lifecycle_Configuration_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String; Host_ID : String;
      Transition_Default_Minimum_Object_Size : String;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Lifecycle_Configuration_Outcome;

   --  Execute one exact prepared CreateBucketMetadataTableConfiguration
   --  request.  The 30-second default is the established low-level
   --  synchronous-client compatibility budget; callers may select another
   --  absolute budget.  Exceptions after entering the blocking HTTP call do
   --  not establish whether the provider published the mutation; callers
   --  requiring certainty must reconcile with a read and must not auto-retry.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching prepare operation
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Create_Bucket_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketAbac request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared PutBucketAbac request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed update or structured S3 rejection
   function Execute_Put_Bucket_Abac
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;
   --  Execute one exact prepared PutBucketAccelerateConfiguration request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared acceleration request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed update or structured S3 rejection
   function Execute_Put_Bucket_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;
   --  Execute one exact prepared PutBucketRequestPayment request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared request-payment request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed update or structured S3 rejection
   function Execute_Put_Bucket_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;
   --  Execute one exact prepared PutPublicAccessBlock request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared PutPublicAccessBlock request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed update or structured S3 rejection
   function Execute_Put_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketOwnershipControls request.  The
   --  30-second default is the established low-level synchronous-client
   --  compatibility budget; callers may select a different absolute budget.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from Prepare_Put_Bucket_Ownership_Controls
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketEncryption request. The 30-second
   --  default is the established low-level synchronous-client compatibility
   --  budget; callers may select a different absolute budget. No request is
   --  replayed after possible admission.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from Prepare_Put_Bucket_Encryption
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketLifecycleConfiguration request.
   --  Every resource and cancellation choice is caller-supplied. No request
   --  is replayed after possible admission.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching lifecycle preparer
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Lifecycle_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Lifecycle_Configuration_Outcome;

   --  Execute one exact prepared PutBucketNotificationConfiguration request.
   --  No request is replayed after possible admission.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching notification preparer
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Notification_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketReplication request. No request is
   --  replayed after possible admission.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching replication preparer
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketAnalyticsConfiguration request.
   --  Exceptions after entering the HTTP call do not establish application;
   --  callers must reconcile read-only and must not replay automatically.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching analytics preparer
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared
   --  PutBucketIntelligentTieringConfiguration request. Exceptions after
   --  entering the HTTP call do not establish application; callers must
   --  reconcile read-only and must not replay automatically.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching Intelligent-Tiering preparer
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketMetricsConfiguration request.
   --  Exceptions after entering the HTTP call do not establish application;
   --  callers must reconcile read-only and must not replay automatically.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from the matching metrics preparer
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Execute one exact prepared PutBucketCors request. The 30-second default
   --  is the established low-level synchronous-client compatibility budget;
   --  callers may select a different absolute budget. No request is replayed
   --  after possible admission.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request from Prepare_Put_Bucket_CORS
   --  @param Timeout Caller-selected absolute operation budget
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed update success or strict S3 rejection
   function Execute_Put_Bucket_CORS
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Complete physical controls for PutBucketPolicy.
   --  @field Content_MD5 Optional canonical MD5 override
   --  @field Checksum_Algorithm Optional one of the ten modeled algorithms
   --  @field Confirm_Remove_Self_Access Optional modeled safety confirmation
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_Policy_Parameters is record
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Confirm_Remove_Self_Access : Optional_Boolean;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact bounded PutBucketPolicy request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Bucket whose policy is replaced
   --  @param Policy Raw policy bytes bounded only by Limits
   --  @param Parameters Integrity, safety, and owner controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @param Limits Policy byte bound
   --  @return Prepared request owning the exact one-shot policy body
   function Prepare_Put_Bucket_Policy
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Policy : String;
      Parameters : Put_Bucket_Policy_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Execute one exact prepared PutBucketPolicy request.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact prepared PutBucketPolicy request
   --  @param Timeout Whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Bounded S3 error parsing limits
   --  @return Completed update or structured S3 rejection
   function Execute_Put_Bucket_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Every input member in the pinned DeleteObject request shape.
   --  @field MFA Optional exact multi-factor authentication value
   --  @field Version_ID Optional exact object-version selector
   --  @field Request_Payer Optional exact requester-pays admission value
   --  @field Bypass_Governance_Retention Optional exact governance bypass
   --  value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field If_Match Optional exact entity-tag precondition
   --  @field If_Match_Last_Modified_Time Optional exact last-modified-time
   --  precondition
   --  @field If_Match_Size Optional exact object-size precondition
   type Delete_Object_Parameters is record
      MFA                         : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID                  : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer               : Ada.Strings.Unbounded.Unbounded_String;
      Bypass_Governance_Retention : Optional_Boolean;
      Expected_Bucket_Owner       : Ada.Strings.Unbounded.Unbounded_String;
      If_Match                    : Ada.Strings.Unbounded.Unbounded_String;
      If_Match_Last_Modified_Time : Ada.Strings.Unbounded.Unbounded_String;
      If_Match_Size               : Optional_Byte_Count;
   end record;

   --  Prepare one exact signed DeleteObject request.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Key Required exact target object key
   --  @param Parameters Complete modeled non-resource request inputs
   --  @param Identity Credentials borrowed only while signing
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @return Prepared signed DeleteObject request
   function Prepare_Delete_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Delete_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every output member in the pinned DeleteObject response shape.
   --  @field Delete_Marker Optional parsed delete-marker indication
   --  @field Version_ID Optional exact returned version identifier
   --  @field Request_Charged Optional exact requester-pays response value
   type Delete_Object_Result is record
      Delete_Marker   : Optional_Boolean;
      Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Shape of a completed DeleteObject response.
   --  @enum Object_Deleted Exact 204 deletion response decoded
   --  @enum Delete_Object_Rejected Structured S3 rejection decoded
   type Delete_Object_Outcome_Kind is
     (Object_Deleted, Delete_Object_Rejected);

   --  Completed DeleteObject response selected by Kind.
   --  @field Kind Selects the meaningful response payload
   --  @field Status Exact HTTP response status
   --  @field Result Response headers when Kind is Object_Deleted
   --  @field Error Structured S3 error when Kind is rejected
   type Delete_Object_Outcome
     (Kind : Delete_Object_Outcome_Kind := Delete_Object_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Deleted =>
            Result : Delete_Object_Result;
         when Delete_Object_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode supplied DeleteObject response fields and body.
   --  @param Status Exact HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled response header values
   --  @param Request_ID Optional exact S3 request identifier
   --  @param Host_ID Optional exact S3 host identifier
   --  @param Limits Caller-selected XML parsing limits
   --  @return Typed deletion result or structured S3 rejection
   function Decode_Delete_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Delete_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Outcome;

   --  Decode one body-complete DeleteObject response, including strict
   --  singleton validation for every modeled response header.
   --  @param Response Complete HTTP response metadata
   --  @param Payload Complete bounded response body
   --  @param Limits Shared bounded XML parse policy
   --  @return Typed deletion result or structured S3 rejection
   function Decode_Delete_Object_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Outcome;

   --  Execute and decode one prepared DeleteObject request.
   --  @param Client HTTP client that owns the synchronous exchange
   --  @param Prepared Exact prepared DeleteObject request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and XML parsing limits
   --  @return Typed deletion result or structured S3 rejection
   function Execute_Delete_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Outcome;
   --  DeleteObject is never transparently replayed, including after a reused
   --  HTTP transport is lost before a response.  A transport, timeout, or
   --  cancellation exception may therefore mean that deletion was published;
   --  callers must reconcile the exact key/generation before retrying.

   --  Every non-resource member in the pinned DeleteObjectAnnotation input.
   --  @field Version_ID Optional exact generation selector
   --  @field Request_Payer Optional exact requester-pays admission value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Object_If_Match Optional exact object-generation precondition
   type Delete_Object_Annotation_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Object_If_Match       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact conditional DeleteObjectAnnotation request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Key Required object key
   --  @param Annotation_Name Required opaque annotation query value
   --  @param Parameters Optional generation, payer, owner, and CAS controls
   --  @param Identity Signing credentials
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to DeleteObjectAnnotation
   function Prepare_Delete_Object_Annotation
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key, Annotation_Name : String;
      Parameters : Delete_Object_Annotation_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Every output member in the pinned DeleteObjectAnnotation response.
   --  @field Object_Version_ID Optional exact affected object generation
   --  @field Request_Charged Optional exact requester-pays result
   type Delete_Object_Annotation_Result is record
      Object_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal DeleteObjectAnnotation response classification.
   --  @enum Object_Annotation_Deleted Exact empty 204 response
   --  @enum Delete_Object_Annotation_Rejected Bounded non-204 S3 rejection
   type Delete_Object_Annotation_Outcome_Kind is
     (Object_Annotation_Deleted, Delete_Object_Annotation_Rejected);

   --  Terminal exact deletion success or bounded S3 rejection.
   --  @field Kind Response classification
   --  @field Status Exact HTTP status
   --  @field Result Modeled success headers
   --  @field Error Bounded structured provider rejection
   type Delete_Object_Annotation_Outcome
     (Kind : Delete_Object_Annotation_Outcome_Kind :=
       Delete_Object_Annotation_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Annotation_Deleted =>
            Result : Delete_Object_Annotation_Result;
         when Delete_Object_Annotation_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one exact bounded DeleteObjectAnnotation response.
   --  @param Status Exact HTTP status
   --  @param Payload Complete bounded response body
   --  @param Headers Modeled singleton response headers
   --  @param Request_ID Optional provider request diagnostic
   --  @param Host_ID Optional provider host diagnostic
   --  @param Limits Shared XML error-response limits
   --  @return Typed exact success or structured rejection
   function Decode_Delete_Object_Annotation_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Headers : Delete_Object_Annotation_Result;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Annotation_Outcome;

   --  Execute without transparent replay.  Any exception after entering the
   --  blocking provider call leaves deletion unknown and requires read-only
   --  reconciliation; callers must not automatically retry.
   --  @param Client Caller-owned synchronous HTTP client
   --  @param Prepared Request bound to DeleteObjectAnnotation
   --  @param Timeout Established blocking call deadline
   --  @param Token Optional cooperative cancellation token
   --  @param Limits Shared response and XML error limits
   --  @return Typed exact success or structured rejection
   function Execute_Delete_Object_Annotation
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Annotation_Outcome;

   --  Every non-resource member in the pinned ListObjectAnnotations input.
   --  Presence flags preserve explicitly empty optional query values. The
   --  caller selects every page-size value; this record defines no default.
   --  @field Version_ID Exact optional object version text
   --  @field Has_Version_ID Whether to send Version_ID, including empty text
   --  @field Max_Annotation_Results Caller-selected modeled page size
   --  @field Has_Max_Annotation_Results Whether to send the page size
   --  @field Annotation_Prefix Exact optional annotation-name prefix
   --  @field Has_Annotation_Prefix Whether to send the prefix, including empty
   --  @field Continuation_Token Exact optional next-page cursor
   --  @field Has_Continuation_Token Whether to send cursor, including empty
   --  @field Request_Payer Empty or requester for Requester Pays buckets
   --  @field Expected_Bucket_Owner Empty or exact owner precondition
   type List_Object_Annotations_Parameters is record
      Version_ID                 : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID             : Boolean;
      Max_Annotation_Results     : S3.Annotations.Annotation_Result_Limit;
      Has_Max_Annotation_Results : Boolean;
      Annotation_Prefix          : Ada.Strings.Unbounded.Unbounded_String;
      Has_Annotation_Prefix      : Boolean;
      Continuation_Token         : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token     : Boolean;
      Request_Payer              : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Build and sign one exact ListObjectAnnotations request.
   --  @param Origin Parsed HTTP origin
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Required bucket name
   --  @param Key Complete object key; slashes remain path separators
   --  @param Parameters Complete modeled optional request values
   --  @param Identity Signing credentials borrowed during construction
   --  @param Region SigV4 signing region
   --  @param Timestamp Basic ISO SigV4 timestamp
   --  @return Fully signed request bound to ListObjectAnnotations
   function Prepare_List_Object_Annotations
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : List_Object_Annotations_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Complete modeled ListObjectAnnotations success representation.
   --  @field Page Strict same-response REST/XML annotation page
   --  @field Object_Version_ID Optional exact selected object generation
   --  @field Request_Charged Optional exact requester-pays result
   type List_Object_Annotations_Result is record
      Page              : S3.Annotations.Annotation_Page;
      Object_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Terminal ListObjectAnnotations response classification.
   --  @enum Object_Annotations_Listed Exact 200 response decoded successfully
   --  @enum List_Object_Annotations_Rejected Bounded non-200 S3 rejection
   type List_Object_Annotations_Outcome_Kind is
     (Object_Annotations_Listed, List_Object_Annotations_Rejected);

   --  Terminal exact listing success or bounded S3 rejection. The rejected
   --  kind and status 500 are deterministic scratch values required by the
   --  shared owner-driven state before terminal decoding; they are not an
   --  operational default or a provider compatibility claim.
   --  @field Kind Selects the meaningful terminal payload
   --  @field Status Exact physical HTTP status
   --  @field Result Complete success graph when Kind is listed
   --  @field Error Structured bounded S3 error when Kind is rejected
   type List_Object_Annotations_Outcome
     (Kind : List_Object_Annotations_Outcome_Kind :=
       List_Object_Annotations_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Annotations_Listed =>
            Result : List_Object_Annotations_Result;
         when List_Object_Annotations_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one complete bounded ListObjectAnnotations response. Singleton
   --  modeled headers are validated from the same HTTP response snapshot.
   --  @param Response Complete same-response status and header snapshot
   --  @param Payload Complete bounded same-response body
   --  @param Limits Caller-selected shared XML resource limits
   --  @return Typed exact listing or structured S3 rejection
   function Decode_List_Object_Annotations_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload : String;
      Limits : S3.XML.Parse_Limits)
      return List_Object_Annotations_Outcome;

   --  Execute one exact prepared read using the synchronous HTTP adapter.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Exact ListObjectAnnotations prepared request
   --  @param Timeout Whole synchronous exchange budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed exact listing or structured S3 rejection
   function Execute_List_Object_Annotations
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return List_Object_Annotations_Outcome;

   --  Complete modeled inputs for PutObjectTagging.
   --  @field Version_ID Optional exact object-version query value
   --  @field Checksum_Algorithm Optional modeled request checksum selection
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Request_Payer Optional requester-pays admission value
   type Put_Object_Tagging_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete modeled inputs for GetObjectTagging.
   --  @field Version_ID Optional exact object-version query value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Request_Payer Optional requester-pays admission value
   type Get_Object_Tagging_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete modeled inputs for DeleteObjectTagging.
   --  @field Version_ID Optional exact object-version query value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Delete_Object_Tagging_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed PutObjectTagging request.
   --  @param Origin Parsed request origin
   --  @param Style S3 addressing style
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Tags Complete tag set copied during preparation
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used while signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format timestamp
   --  @return Signed request owning the exact serialized tag document
   function Prepare_Put_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Tags : Object_Tag_Set;
      Parameters : Put_Object_Tagging_Parameters; Identity : Credentials;
      Region, Timestamp : String) return Prepared_Request;

   --  Prepare one exact signed GetObjectTagging request.
   --  @param Origin Parsed request origin
   --  @param Style S3 addressing style
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used while signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format timestamp
   --  @return Signed request for the selected object version
   function Prepare_Get_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : Get_Object_Tagging_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact signed DeleteObjectTagging request.
   --  @param Origin Parsed request origin
   --  @param Style S3 addressing style
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used while signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format timestamp
   --  @return Signed nonreplaying request for the selected object version
   function Prepare_Delete_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : Delete_Object_Tagging_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Complete modeled object-tagging response value.
   --  @field Tags Complete decoded tag set, or empty for mutations
   --  @field Version_ID Exact modeled response version header
   type Object_Tagging_Result is record
      Tags       : Object_Tag_Set;
      Version_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Shape of a completed object-tagging exchange.
   --  @enum Tags_Put PutObjectTagging completed successfully
   --  @enum Tags_Gotten GetObjectTagging returned a tag snapshot
   --  @enum Tags_Deleted DeleteObjectTagging completed successfully
   --  @enum Object_Tagging_Rejected Service returned a structured rejection
   type Object_Tagging_Outcome_Kind is
     (Tags_Put, Tags_Gotten, Tags_Deleted, Object_Tagging_Rejected);

   --  Typed object-tagging response or structured S3 rejection.
   --  @field Kind Selects the modeled success or rejection variant
   --  @field Status Exact completed HTTP status
   --  @field Result Operation-specific modeled response value
   --  @field Error Structured S3 rejection
   type Object_Tagging_Outcome
     (Kind : Object_Tagging_Outcome_Kind := Object_Tagging_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Put | Tags_Gotten | Tags_Deleted =>
            Result : Object_Tagging_Result;
         when Object_Tagging_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode a complete PutObjectTagging response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Version_ID Optional selected object version response header
   --  @param Request_ID Optional S3 request identifier
   --  @param Host_ID Optional S3 host identifier
   --  @param Limits Shared XML/error parsing limits
   --  @return Typed exact success or structured rejection
   function Decode_Put_Object_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Version_ID : String := "";
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   --  Decode a complete GetObjectTagging response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Version_ID Optional selected object version response header
   --  @param Request_ID Optional S3 request identifier
   --  @param Host_ID Optional S3 host identifier
   --  @param Limits Shared XML/error parsing limits
   --  @return Typed exact tag snapshot or structured rejection
   function Decode_Get_Object_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Version_ID : String := "";
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   --  Decode a complete DeleteObjectTagging response.
   --  @param Status HTTP response status
   --  @param Payload Complete bounded response body
   --  @param Version_ID Optional selected object version response header
   --  @param Request_ID Optional S3 request identifier
   --  @param Host_ID Optional S3 host identifier
   --  @param Limits Shared XML/error parsing limits
   --  @return Typed exact success or structured rejection
   function Decode_Delete_Object_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Version_ID : String := "";
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   --  Execute one exact prepared PutObjectTagging request.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact signed PutObjectTagging request
   --  @param Timeout Whole synchronous exchange budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or structured S3 rejection
   function Execute_Put_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   --  Execute one exact prepared GetObjectTagging request.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact signed GetObjectTagging request
   --  @param Timeout Whole synchronous exchange budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or structured S3 rejection
   function Execute_Get_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   --  Execute one exact prepared DeleteObjectTagging request.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact signed DeleteObjectTagging request
   --  @param Timeout Whole synchronous exchange budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or structured S3 rejection
   function Execute_Delete_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   --  Every non-Bucket/Delete member in the pinned DeleteObjects input shape.
   --  Content-MD5 is always generated over the exact serialized document.
   --  When Checksum_Algorithm is present, the client also generates the
   --  matching algorithm-specific checksum header over those same bytes.
   --  @field MFA Optional root-owner MFA device and credential value
   --  @field Request_Payer Empty or requester for Requester Pays buckets
   --  @field Bypass_Governance_Retention Optional governance bypass request
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field Checksum_Algorithm Optional maintained checksum algorithm
   type Delete_Objects_Parameters is record
      MFA                         : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer               : Ada.Strings.Unbounded.Unbounded_String;
      Bypass_Governance_Retention : Optional_Boolean;
      Expected_Bucket_Owner       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed DeleteObjects request and retain its body.
   --  @param Origin Exact HTTP origin
   --  @param Style S3 addressing style
   --  @param Bucket Bucket whose selected entries are deleted
   --  @param Request Bounded ordered delete request
   --  @param Parameters Complete modeled DeleteObjects controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Timestamp SigV4 basic-format timestamp
   --  @return Signed request with an owned one-shot XML payload
   --  @exception Invalid_Request Request or controls are invalid
   function Prepare_Delete_Objects
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Request    : S3.Deletions.Delete_Objects_Request;
      Parameters : Delete_Objects_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Modeled per-entry DeleteObjects result and Requester Pays metadata.
   --  @field Result Exact Deleted and Error entry collections
   --  @field Request_Charged Empty or requester from the response
   type Delete_Objects_Result is record
      Result          : S3.Deletions.Delete_Objects_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Shape of a decoded DeleteObjects response.
   --  @enum Objects_Deleted A modeled batch response is available
   --  @enum Delete_Objects_Rejected The service rejected the batch request
   type Delete_Objects_Outcome_Kind is
     (Objects_Deleted, Delete_Objects_Rejected);

   --  Complete modeled DeleteObjects response or structured S3 rejection.
   --  @field Kind Selects the processed or rejected response variant
   --  @field Status HTTP status returned by the completed exchange
   --  @field Result Modeled per-entry batch result and response metadata
   --  @field Error Structured S3 rejection
   type Delete_Objects_Outcome
     (Kind : Delete_Objects_Outcome_Kind := Delete_Objects_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Objects_Deleted =>
            Result : Delete_Objects_Result;
         when Delete_Objects_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one syntactically complete DeleteObjects response document.
   --  Request binding requires Decode_Delete_Objects_Complete_Response.
   --  @param Status HTTP status returned by the completed exchange
   --  @param Payload Complete bounded response body
   --  @param Request_Charged Empty or requester response metadata
   --  @param Request_ID Optional S3 request identifier
   --  @param Host_ID Optional S3 host identifier
   --  @param Limits Caller-selected bounded XML limits
   --  @return Modeled per-entry result or structured S3 rejection
   --  @exception Invalid_Response Response XML or metadata is invalid
   function Decode_Delete_Objects_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Objects_Outcome;

   --  Decode one complete DeleteObjects HTTP response. Physical singleton
   --  headers and Requester Pays consistency are validated before exposing
   --  the modeled per-entry result.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared DeleteObjects request
   --  @param Limits Bounded XML parser limits
   --  @return Typed batch result or S3 rejection
   --  @exception Invalid_Request Prepared is not DeleteObjects
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_Delete_Objects_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Objects_Outcome;

   --  Execute one exact prepared DeleteObjects request synchronously.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact signed DeleteObjects request
   --  @param Timeout Whole synchronous exchange budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed per-entry response or structured S3 rejection
   --  @exception Invalid_Request Prepared is not DeleteObjects
   --  @exception Invalid_Response Complete response is inconsistent
   function Execute_Delete_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Objects_Outcome;

   --  Every non-resource member in the pinned CreateSession input. Empty
   --  strings preserve omission; Bucket_Key_Enabled preserves absent versus
   --  explicit false.
   --  @field Session_Mode Optional modeled session mode
   --  @field Server_Side_Encryption Optional encryption algorithm
   --  @field SSE_KMS_Key_ID Optional KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional canonical Base64 KMS context
   --  @field Bucket_Key_Enabled Presence-preserving bucket-key request flag
   type Create_Session_Parameters is record
      Session_Mode               : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID              : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
   end record;

   --  Prepare one exactly bound CreateSession request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Bucket addressing style
   --  @param Bucket Target directory bucket
   --  @param Parameters Complete modeled non-resource input
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact CreateSession request
   function Prepare_Create_Session
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Create_Session_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Caller-supplied response metadata for compatibility decoding.
   --  @field Server_Side_Encryption Returned encryption algorithm
   --  @field SSE_KMS_Key_ID Returned KMS key identifier
   --  @field SSE_KMS_Encryption_Context Returned KMS encryption context
   --  @field Bucket_Key_Enabled Presence-preserving returned bucket-key flag
   type Create_Session_Response_Headers is record
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID              : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
   end record;

   --  All five top-level output members and all four nested credential
   --  members. Access key, secret, and token are held by the zeroizing
   --  Credentials type; expiration remains separately observable. Requests
   --  prepared with the returned identity use x-amz-s3session-token rather
   --  than the generic x-amz-security-token header.
   --  @field Server_Side_Encryption Returned encryption algorithm
   --  @field SSE_KMS_Key_ID Returned KMS key identifier
   --  @field SSE_KMS_Encryption_Context Returned KMS encryption context
   --  @field Bucket_Key_Enabled Presence-preserving returned bucket-key flag
   --  @field Identity Zeroizing session credentials
   --  @field Expiration Returned credential-expiration text
   type Create_Session_Result is limited record
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID              : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
      Identity                   : Credentials;
      Expiration                 : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish completed session creation from structured S3 rejection.
   --  @enum Session_Created Complete session credentials were decoded
   --  @enum Create_Session_Rejected S3 rejected the operation
   type Create_Session_Outcome_Kind is
     (Session_Created, Create_Session_Rejected);

   --  Result of decoding or executing one CreateSession operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Credentials and response metadata on success
   --  @field Error Structured S3 error on rejection
   type Create_Session_Outcome
     (Kind : Create_Session_Outcome_Kind := Create_Session_Rejected)
   is limited record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Session_Created =>
            Result : Create_Session_Result;
         when Create_Session_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded CreateSession response from supplied metadata.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Headers Caller-supplied modeled response headers
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Session credentials or structured S3 rejection
   function Decode_Create_Session_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Create_Session_Response_Headers := (others => <>);
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Session_Outcome;

   --  Complete physically validated CreateSession response metadata. Header
   --  absence remains distinct from a present-empty value, which is rejected
   --  while capturing this value. The private representation prevents callers
   --  from fabricating metadata that bypasses physical header validation.
   type Create_Session_Response_Metadata is private;

   --  Capture and validate every physical CreateSession response header.
   --  @param Response Complete HTTP response head
   --  @return Bounded metadata safe to retain after releasing Response
   --  @exception Invalid_Response A header is duplicate, empty, overlong,
   --     control-bearing, or otherwise malformed
   function Read_Create_Session_Response_Metadata
     (Response : Flyology.HTTP.Client.Response)
      return Create_Session_Response_Metadata;

   --  Decode one complete CreateSession response against its signed request.
   --  @param Metadata Physically validated response status and headers
   --  @param Payload Complete bounded response document
   --  @param Prepared Exact prepared CreateSession request
   --  @param Limits Caller-selected XML limits
   --  @return Zeroizing session credentials or structured S3 rejection
   --  @exception Invalid_Request Prepared is not CreateSession
   --  @exception Invalid_Response Response is malformed or conflicts with the
   --     signed request
   function Decode_Create_Session_Complete_Response
     (Metadata : Create_Session_Response_Metadata;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits)
      return Create_Session_Outcome;

   --  Execute one exact prepared CreateSession exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Session credentials or structured S3 rejection
   function Execute_Create_Session
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Session_Outcome;

   --  Every non-resource member in the pinned CreateMultipartUpload input.
   --  Empty optional strings preserve omission; Bucket_Key_Enabled preserves
   --  absent versus explicit false. Metadata entries project as x-amz-meta-*
   --  headers and are rejected on a case-insensitive duplicate name.
   --  @field ACL Optional canned access-control policy
   --  @field Cache_Control Optional cache-control metadata
   --  @field Content_Disposition Optional content-disposition metadata
   --  @field Content_Encoding Optional content-encoding metadata
   --  @field Content_Language Optional content-language metadata
   --  @field Content_Type Optional content-type metadata
   --  @field Expires Optional IMF-date expiration metadata
   --  @field Grant_Full_Control Optional full-control grant
   --  @field Grant_Read Optional read grant
   --  @field Grant_Read_ACP Optional ACL-read grant
   --  @field Grant_Write_ACP Optional ACL-write grant
   --  @field Metadata Caller-supplied object metadata entries
   --  @field Server_Side_Encryption Optional destination encryption algorithm
   --  @field Storage_Class Optional destination storage class
   --  @field Website_Redirect_Location Optional redirect metadata
   --  @field SSE_Customer_Algorithm Optional customer-key algorithm
   --  @field SSE_Customer_Key Optional customer encryption key
   --  @field SSE_Customer_Key_MD5 Optional customer-key MD5
   --  @field SSE_KMS_Key_ID Optional KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional KMS context
   --  @field Bucket_Key_Enabled Presence-preserving destination choice
   --  @field Request_Payer Optional requester-pays header value
   --  @field Tagging Optional encoded destination tag set
   --  @field Object_Lock_Mode Optional retention mode
   --  @field Object_Lock_Retain_Until_Date Optional retention timestamp
   --  @field Object_Lock_Legal_Hold_Status Optional legal-hold status
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field Checksum_Algorithm Optional initiation checksum policy
   --  @field Checksum_Type Optional requested checksum aggregation type
   type Create_Multipart_Parameters is record
      ACL                       : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Control             : Ada.Strings.Unbounded.Unbounded_String;
      Content_Disposition       : Ada.Strings.Unbounded.Unbounded_String;
      Content_Encoding          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Language          : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type              : Ada.Strings.Unbounded.Unbounded_String;
      Expires                   : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Full_Control        : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read                : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read_ACP            : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write_ACP           : Ada.Strings.Unbounded.Unbounded_String;
      Metadata                  : Metadata_Entry_Vectors.Vector;
      Server_Side_Encryption    : Ada.Strings.Unbounded.Unbounded_String;
      Storage_Class             : Ada.Strings.Unbounded.Unbounded_String;
      Website_Redirect_Location : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key          : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5      : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID            : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled        : Optional_Boolean;
      Request_Payer             : Ada.Strings.Unbounded.Unbounded_String;
      Tagging                   : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Mode          : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Retain_Until_Date :
        Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Legal_Hold_Status :
        Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type             : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare a bodyless CreateMultipartUpload request with content type.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @param Content_Type Optional content-type metadata
   --  @return Prepared bodyless multipart-initiation request
   function Prepare_Create_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String;
      Content_Type : String := "") return Prepared_Request;

   --  Prepare CreateMultipartUpload with explicit modeled checksum policy.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Parameters Complete modeled initiation controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless multipart-initiation request
   function Prepare_Create_Multipart_Upload
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Create_Multipart_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Distinguish created multipart upload from structured S3 rejection.
   --  @enum Created Validated multipart initiation was decoded
   --  @enum Create_Rejected Structured S3 error was decoded
   type Create_Multipart_Outcome_Kind is (Created, Create_Rejected);

   --  Every member in the pinned CreateMultipartUpload output shape.
   --  @field Bucket Returned bucket identity
   --  @field Key Returned object-key identity
   --  @field Upload_ID New multipart upload identifier
   --  @field Abort_Date Optional returned abort timestamp
   --  @field Abort_Rule_ID Optional returned abort-rule identifier
   --  @field Server_Side_Encryption Optional returned encryption algorithm
   --  @field SSE_Customer_Algorithm Optional returned customer algorithm
   --  @field SSE_Customer_Key_MD5 Optional returned customer-key MD5
   --  @field SSE_KMS_Key_ID Optional returned KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional returned KMS context
   --  @field Bucket_Key_Enabled Presence-preserving returned bucket-key value
   --  @field Request_Charged Optional returned requester-charge value
   --  @field Checksum_Algorithm Optional returned checksum algorithm
   --  @field Checksum_Type Optional returned checksum aggregation type
   type Create_Multipart_Result is record
      Bucket                     : Ada.Strings.Unbounded.Unbounded_String;
      Key                        : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID                  : Ada.Strings.Unbounded.Unbounded_String;
      Abort_Date                 : Ada.Strings.Unbounded.Unbounded_String;
      Abort_Rule_ID              : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID             : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
      Request_Charged            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type              : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Physical response headers supplied to the pure decoder. Empty strings
   --  and an unset boolean mean absent; Execute enforces physical presence,
   --  multiplicity, and present-empty distinctions before constructing this.
   --  @field Abort_Date Supplied abort timestamp
   --  @field Abort_Rule_ID Supplied abort-rule identifier
   --  @field Server_Side_Encryption Supplied encryption value
   --  @field SSE_Customer_Algorithm Supplied customer-key algorithm
   --  @field SSE_Customer_Key_MD5 Supplied customer-key MD5
   --  @field SSE_KMS_Key_ID Supplied KMS key identifier
   --  @field SSE_KMS_Encryption_Context Supplied KMS context
   --  @field Bucket_Key_Enabled Supplied bucket-key choice
   --  @field Request_Charged Supplied requester-charge value
   --  @field Checksum_Algorithm Supplied checksum algorithm
   --  @field Checksum_Type Supplied checksum aggregation type
   type Create_Multipart_Response_Headers is record
      Abort_Date                 : Ada.Strings.Unbounded.Unbounded_String;
      Abort_Rule_ID              : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID             : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
      Request_Charged            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type              : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Result of decoding or executing one CreateMultipartUpload operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Validated multipart initiation on success
   --  @field Error Structured S3 error on rejection
   type Create_Multipart_Outcome
     (Kind : Create_Multipart_Outcome_Kind := Create_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Created =>
            Result : Create_Multipart_Result;
         when Create_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded initiation response from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @param Headers Caller-supplied modeled response headers
   --  @return Multipart initiation or structured S3 rejection
   function Decode_Create_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits;
      Headers    : Create_Multipart_Response_Headers :=
        (others => <>))
      return Create_Multipart_Outcome;

   --  Decode one body-complete CreateMultipartUpload response and bind every
   --  modeled success identity and echoed policy field to Prepared.
   --  @param Response Complete HTTP response metadata
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared CreateMultipartUpload request
   --  @param Limits Shared bounded XML parse policy
   --  @return Typed initiation result or structured S3 rejection
   --  @exception Invalid_Request Prepared is not CreateMultipartUpload
   --  @exception Invalid_Response Physical headers, XML, identity, or echoed
   --     policy are invalid
   function Decode_Create_Multipart_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Multipart_Outcome;

   --  Execute one bodyless initiation attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Prepared CreateMultipartUpload request metadata
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Multipart initiation or structured S3 rejection
   function Execute_Create_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Multipart_Outcome;

   --  Every non-resource and non-body member in the pinned
   --  CompleteMultipartUpload input shape. Completion supplies the modeled
   --  MultipartUpload body. Mpu_Object_Size preserves absent versus zero.
   --  @field Checksum_CRC32 Optional CRC-32 checksum value
   --  @field Checksum_CRC32C Optional CRC-32C checksum value
   --  @field Checksum_CRC64NVME Optional CRC-64/NVME checksum value
   --  @field Checksum_SHA1 Optional SHA-1 checksum value
   --  @field Checksum_SHA256 Optional SHA-256 checksum value
   --  @field Checksum_SHA512 Optional SHA-512 checksum value
   --  @field Checksum_MD5 Optional MD5 checksum value
   --  @field Checksum_XXHASH64 Optional XXH64 checksum value
   --  @field Checksum_XXHASH3 Optional XXH3 checksum value
   --  @field Checksum_XXHASH128 Optional XXH128 checksum value
   --  @field Checksum_Type Optional modeled checksum type
   --  @field Mpu_Object_Size Presence-preserving modeled object size
   --  @field Request_Payer Optional request-payer value
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field If_Match Optional matching entity-tag precondition
   --  @field If_None_Match Optional nonmatching entity-tag precondition
   --  @field SSE_Customer_Algorithm Optional customer encryption algorithm
   --  @field SSE_Customer_Key Optional customer-provided encryption key
   --  @field SSE_Customer_Key_MD5 Optional customer-key MD5 value
   type Complete_Multipart_Parameters is record
      Checksum_CRC32       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type        : Ada.Strings.Unbounded.Unbounded_String;
      Mpu_Object_Size      : Optional_Byte_Count;
      Request_Payer        : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      If_Match             : Ada.Strings.Unbounded.Unbounded_String;
      If_None_Match        : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exactly bound CompleteMultipartUpload request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Upload_ID Multipart upload identifier
   --  @param Completion Ordered completed-part manifest
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact multipart-completion request
   function Prepare_Complete_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String) return Prepared_Request;

   --  Prepare one parameterized CompleteMultipartUpload request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Upload_ID Multipart upload identifier
   --  @param Completion Ordered completed-part manifest
   --  @param Parameters Complete modeled non-body input
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact multipart-completion request
   function Prepare_Complete_Multipart_Upload
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Upload_ID  : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Complete_Multipart_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every member in the pinned CompleteMultipartUpload output shape.
   --  @field Location Returned object location
   --  @field Bucket Returned bucket identity
   --  @field Key Returned object-key identity
   --  @field Expiration Returned expiration metadata
   --  @field Entity_Tag Returned entity tag
   --  @field Checksum_CRC32 Returned CRC-32 checksum
   --  @field Checksum_CRC32C Returned CRC-32C checksum
   --  @field Checksum_CRC64NVME Returned CRC-64/NVME checksum
   --  @field Checksum_SHA1 Returned SHA-1 checksum
   --  @field Checksum_SHA256 Returned SHA-256 checksum
   --  @field Checksum_SHA512 Returned SHA-512 checksum
   --  @field Checksum_MD5 Returned MD5 checksum
   --  @field Checksum_XXHASH64 Returned XXH64 checksum
   --  @field Checksum_XXHASH3 Returned XXH3 checksum
   --  @field Checksum_XXHASH128 Returned XXH128 checksum
   --  @field Checksum_Type Returned modeled checksum type
   --  @field Server_Side_Encryption Returned encryption algorithm
   --  @field Version_ID Returned object-version identifier
   --  @field SSE_KMS_Key_ID Returned KMS key identifier
   --  @field Bucket_Key_Enabled Presence-preserving returned bucket-key flag
   --  @field Request_Charged Returned requester-charge value
   type Complete_Multipart_Result is record
      Location               : Ada.Strings.Unbounded.Unbounded_String;
      Bucket                 : Ada.Strings.Unbounded.Unbounded_String;
      Key                    : Ada.Strings.Unbounded.Unbounded_String;
      Expiration             : Ada.Strings.Unbounded.Unbounded_String;
      Entity_Tag             : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32         : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type          : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled     : Optional_Boolean;
      Request_Charged        : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Caller-supplied headers for compatibility response decoding.
   --  @field Expiration Returned expiration metadata
   --  @field Server_Side_Encryption Returned encryption algorithm
   --  @field Version_ID Returned object-version identifier
   --  @field SSE_KMS_Key_ID Returned KMS key identifier
   --  @field Bucket_Key_Enabled Presence-preserving returned bucket-key flag
   --  @field Request_Charged Returned requester-charge value
   type Complete_Multipart_Response_Headers is record
      Expiration             : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled     : Optional_Boolean;
      Request_Charged        : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish completed multipart assembly from structured S3 rejection.
   --  @enum Completed Complete response metadata was decoded
   --  @enum Complete_Rejected S3 rejected the operation or embedded an error
   type Complete_Multipart_Outcome_Kind is
     (Completed, Complete_Rejected);

   --  Result of decoding or executing one CompleteMultipartUpload operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Completion metadata on success
   --  @field Error Structured S3 error on rejection
   type Complete_Multipart_Outcome
     (Kind : Complete_Multipart_Outcome_Kind := Complete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Completed =>
            Result : Complete_Multipart_Result;
         when Complete_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded CompleteMultipartUpload response without headers.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Completion metadata or structured S3 rejection
   function Decode_Complete_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome;

   --  Decode one complete CompleteMultipartUpload HTTP response. Header
   --  multiplicity, bounded values, embedded 200 error XML, and the complete
   --  success representation are validated as one response snapshot.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared CompleteMultipartUpload request
   --  @param Limits Bounded XML parser limits
   --  @return Typed completion success or S3 rejection
   --  @exception Invalid_Request Prepared is not CompleteMultipartUpload
   --  @exception Invalid_Response if the complete response is inconsistent
   function Decode_Complete_Multipart_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome;

   --  Decode one bounded response from caller-supplied modeled headers.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Headers Caller-supplied modeled response headers
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Completion metadata or structured S3 rejection
   function Decode_Complete_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Complete_Multipart_Response_Headers;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome;

   --  Execute one exact prepared CompleteMultipartUpload exchange.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Completion metadata or structured S3 rejection
   function Execute_Complete_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome;

   --  Prepare one signed bodyless AbortMultipartUpload request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Upload_ID Required multipart upload identifier
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless abort request metadata
   function Prepare_Abort_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String) return Prepared_Request;

   --  Every non-resource member in the pinned AbortMultipartUpload input
   --  shape. If_Match_Initiated_Time is an RFC 822 HTTP date.
   --  @field Request_Payer Optional requester-pays header value
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field If_Match_Initiated_Time Optional initiation-time precondition
   type Abort_Multipart_Parameters is record
      Request_Payer           : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner   : Ada.Strings.Unbounded.Unbounded_String;
      If_Match_Initiated_Time : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one controlled bodyless AbortMultipartUpload request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Upload_ID Required multipart upload identifier
   --  @param Parameters Complete modeled abort controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless abort request metadata
   function Prepare_Abort_Multipart_Upload
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Upload_ID  : String;
      Parameters : Abort_Multipart_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  The sole member in the pinned AbortMultipartUpload output shape.
   --  @field Request_Charged Optional returned requester-charge value
   type Abort_Multipart_Result is record
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish validated abort response from structured S3 rejection.
   --  @enum Aborted Validated HTTP-204 abort response was decoded
   --  @enum Abort_Rejected Structured S3 error was decoded
   type Abort_Multipart_Outcome_Kind is (Aborted, Abort_Rejected);

   --  Result of decoding or executing one AbortMultipartUpload operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Validated abort response metadata
   --  @field Error Structured S3 error on rejection
   type Abort_Multipart_Outcome
     (Kind : Abort_Multipart_Outcome_Kind := Abort_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Aborted =>
            Result : Abort_Multipart_Result;
         when Abort_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded abort response without modeled headers.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Abort response or structured S3 rejection
   function Decode_Abort_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

   --  Decode one bounded abort response from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Headers Caller-supplied modeled response headers
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Abort response or structured S3 rejection
   function Decode_Abort_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Abort_Multipart_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

   --  Decode one complete AbortMultipartUpload HTTP response. Physical
   --  singleton headers and bounded values are validated before the modeled
   --  response is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared AbortMultipartUpload request
   --  @param Limits Bounded XML parser limits
   --  @return Typed abort success or S3 rejection
   --  @exception Invalid_Request Prepared is not AbortMultipartUpload
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_Abort_Multipart_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

   --  Execute one bodyless abort attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Abort response or structured S3 rejection
   function Execute_Abort_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

   --  Every non-resource member in the pinned ListParts input shape.
   --  @field Max_Parts Maximum parts requested in one page
   --  @field Part_Number_Marker Exclusive starting part marker
   --  @field Upload_ID Required multipart upload identifier
   --  @field Request_Payer Optional requester-pays header value
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field SSE_Customer_Algorithm Optional customer-key algorithm
   --  @field SSE_Customer_Key Optional customer encryption key
   --  @field SSE_Customer_Key_MD5 Optional customer-key MD5
   type List_Parts_Parameters is record
      Max_Parts              : S3.Core.Page_Size := 1_000;
      Part_Number_Marker     : S3.Multipart.Part_Marker_Value := 0;
      Upload_ID              : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer          : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner  : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one signed bodyless ListParts request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Parameters Complete modeled listing controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless ListParts request metadata
   function Prepare_List_Parts
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : List_Parts_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every member in the pinned ListParts output shape. The REST/XML body
   --  members are grouped in Listing; the remaining values are HTTP headers.
   --  @field Listing Parsed multipart-parts page
   --  @field Abort_Date Optional returned abort timestamp
   --  @field Abort_Rule_ID Optional returned abort-rule identifier
   --  @field Request_Charged Optional returned requester-charge value
   type List_Parts_Result is record
      Listing         : S3.Multipart.List_Parts_Result;
      Abort_Date      : Ada.Strings.Unbounded.Unbounded_String;
      Abort_Rule_ID   : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish validated parts page from structured S3 rejection.
   --  @enum Parts_Listed Validated HTTP-200 parts page was decoded
   --  @enum List_Parts_Rejected Structured S3 error was decoded
   type List_Parts_Outcome_Kind is (Parts_Listed, List_Parts_Rejected);

   --  Result of decoding or executing one ListParts operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Validated parts page on success
   --  @field Error Structured S3 error on rejection
   type List_Parts_Outcome
     (Kind : List_Parts_Outcome_Kind := List_Parts_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Parts_Listed =>
            Result : List_Parts_Result;
         when List_Parts_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded parts page from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Abort_Date Supplied abort timestamp, possibly empty
   --  @param Abort_Rule_ID Supplied abort-rule identifier, possibly empty
   --  @param Request_Charged Supplied requester-charge value, possibly empty
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Parts page or structured S3 rejection
   function Decode_List_Parts_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Abort_Date      : String := "";
      Abort_Rule_ID   : String := "";
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Parts_Outcome;

   --  Decode one complete ListParts HTTP response. Physical singleton
   --  headers, bounded values, and the successful response's echoed request
   --  identity are validated before the modeled response is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared ListParts request
   --  @param Limits Bounded XML parser limits
   --  @return Typed page or S3 rejection
   --  @exception Invalid_Request Prepared is not ListParts
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_List_Parts_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Parts_Outcome;

   --  Execute one bodyless ListParts attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Parts page or structured S3 rejection
   function Execute_List_Parts
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Parts_Outcome;

   --  Every non-resource member in the pinned ListMultipartUploads input
   --  shape.  An upload-id marker without a key marker is preserved exactly;
   --  S3 defines it as ignored rather than malformed.
   --  @field Delimiter Optional common-prefix delimiter
   --  @field URL_Encoding Whether encoding-type=url is requested
   --  @field Key_Marker Exclusive starting key marker
   --  @field Max_Uploads Maximum uploads requested in one page
   --  @field Prefix Optional key-prefix filter
   --  @field Upload_ID_Marker Starting upload identifier within a key
   --  @field Expected_Bucket_Owner Optional owner precondition
   --  @field Request_Payer Optional requester-pays header value
   type List_Multipart_Uploads_Parameters is record
      Delimiter             : Ada.Strings.Unbounded.Unbounded_String;
      URL_Encoding          : Boolean := False;
      Key_Marker            : Ada.Strings.Unbounded.Unbounded_String;
      Max_Uploads           : S3.Core.Page_Size := 1_000;
      Prefix                : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID_Marker      : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one signed bodyless ListMultipartUploads request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Parameters Complete modeled page selectors
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless upload-listing request metadata
   function Prepare_List_Multipart_Uploads
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : List_Multipart_Uploads_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every output member in the pinned shape: REST/XML members are grouped
   --  in Listing and RequestCharged is the sole operation response header.
   --  @field Listing Parsed multipart-upload page
   --  @field Request_Charged Optional returned requester-charge value
   type List_Multipart_Uploads_Result is record
      Listing : S3.Multipart_Uploads.List_Multipart_Uploads_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish validated upload page from structured S3 rejection.
   --  @enum Multipart_Uploads_Listed Validated HTTP-200 page was decoded
   --  @enum List_Multipart_Uploads_Rejected Structured S3 error was decoded
   type List_Multipart_Uploads_Outcome_Kind is
     (Multipart_Uploads_Listed, List_Multipart_Uploads_Rejected);

   --  Result of decoding or executing one ListMultipartUploads operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Validated multipart-upload page on success
   --  @field Error Structured S3 error on rejection
   type List_Multipart_Uploads_Outcome
     (Kind : List_Multipart_Uploads_Outcome_Kind :=
        List_Multipart_Uploads_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Multipart_Uploads_Listed =>
            Result : List_Multipart_Uploads_Result;
         when List_Multipart_Uploads_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded upload page from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Request_Charged Supplied requester-charge value, possibly empty
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Multipart-upload page or structured S3 rejection
   function Decode_List_Multipart_Uploads_Response
     (Status          : Flyology.HTTP.Status_Code;
      Payload         : String;
      Request_Charged : String := "";
      Request_ID      : String := "";
      Host_ID         : String := "";
      Limits          : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Multipart_Uploads_Outcome;

   --  Decode one complete ListMultipartUploads HTTP response. Physical
   --  singleton headers, bounded values, Requester Pays consistency, and the
   --  successful response's echoed request scope are validated before the
   --  modeled response is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared ListMultipartUploads request
   --  @param Limits Bounded XML parser limits
   --  @return Typed page or S3 rejection
   --  @exception Invalid_Request Prepared is not ListMultipartUploads
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_List_Multipart_Uploads_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Multipart_Uploads_Outcome;

   --  Execute one bodyless listing attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Multipart-upload page or structured S3 rejection
   function Execute_List_Multipart_Uploads
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Multipart_Uploads_Outcome;

   --  Complete modeled UploadPart request metadata outside the body stream.
   --  @field Part_Number Target multipart part number
   --  @field Upload_ID Required multipart upload identifier
   --  @field Payload_SHA256 Caller-supplied hash or UNSIGNED-PAYLOAD
   --  @field Content_MD5 Optional caller-supplied content MD5
   --  @field Checksum_Algorithm Optional modeled checksum algorithm
   --  @field Checksum_CRC32 Optional caller-supplied CRC-32 checksum
   --  @field Checksum_CRC32C Optional caller-supplied CRC-32C checksum
   --  @field Checksum_CRC64NVME Optional caller-supplied CRC-64/NVME checksum
   --  @field Checksum_SHA1 Optional caller-supplied SHA-1 checksum
   --  @field Checksum_SHA256 Optional caller-supplied SHA-256 checksum
   --  @field Checksum_SHA512 Optional caller-supplied SHA-512 checksum
   --  @field Checksum_MD5 Optional caller-supplied MD5 checksum
   --  @field Checksum_XXHASH64 Optional caller-supplied XXH64 checksum
   --  @field Checksum_XXHASH3 Optional caller-supplied XXH3 checksum
   --  @field Checksum_XXHASH128 Optional caller-supplied XXH128 checksum
   --  @field SSE_Customer_Algorithm Optional customer encryption algorithm
   --  @field SSE_Customer_Key Optional customer-provided encryption key
   --  @field SSE_Customer_Key_MD5 Optional customer-key MD5 value
   --  @field Request_Payer Optional request-payer value
   --  @field Expected_Bucket_Owner Optional owner precondition
   type Upload_Part_Parameters is record
      Part_Number       : S3.Core.Part_Number := S3.Core.Part_Number'First;
      Upload_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Payload_SHA256    : Ada.Strings.Unbounded.Unbounded_String;
      Content_MD5       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64 : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128 : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5   : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer          : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed UploadPart request metadata.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Target bucket
   --  @param Key Target object key
   --  @param Parameters Complete modeled request metadata
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared exact UploadPart request metadata
   function Prepare_Upload_Part
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Upload_Part_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Modeled response headers returned by a successful UploadPart request.
   --  @field Entity_Tag Required returned entity tag
   --  @field Checksum_CRC32 Optional returned CRC-32 checksum
   --  @field Checksum_CRC32C Optional returned CRC-32C checksum
   --  @field Checksum_CRC64NVME Optional returned CRC-64/NVME checksum
   --  @field Checksum_SHA1 Optional returned SHA-1 checksum
   --  @field Checksum_SHA256 Optional returned SHA-256 checksum
   --  @field Checksum_SHA512 Optional returned SHA-512 checksum
   --  @field Checksum_MD5 Optional returned MD5 checksum
   --  @field Checksum_XXHASH64 Optional returned XXH64 checksum
   --  @field Checksum_XXHASH3 Optional returned XXH3 checksum
   --  @field Checksum_XXHASH128 Optional returned XXH128 checksum
   --  @field Server_Side_Encryption Optional returned encryption algorithm
   --  @field SSE_Customer_Algorithm Optional returned customer algorithm
   --  @field SSE_Customer_Key_MD5 Optional returned customer-key MD5
   --  @field SSE_KMS_Key_ID Optional returned KMS key identifier
   --  @field Bucket_Key_Enabled Optional returned bucket-key header text
   --  @field Request_Charged Optional returned requester-charge value
   type Upload_Part_Result is record
      Entity_Tag          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32      : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC32C     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_CRC64NVME  : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA1       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA256     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_SHA512     : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_MD5        : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH64   : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH3    : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_XXHASH128  : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5   : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled     : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged        : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish completed part upload from structured S3 rejection.
   --  @enum Part_Uploaded UploadPart success metadata was decoded
   --  @enum Upload_Rejected S3 rejected the operation
   type Upload_Part_Outcome_Kind is (Part_Uploaded, Upload_Rejected);

   --  Result of decoding or executing one UploadPart operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Response metadata on success
   --  @field Error Structured S3 error on rejection
   type Upload_Part_Outcome
     (Kind : Upload_Part_Outcome_Kind := Upload_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Part_Uploaded =>
            Result : Upload_Part_Result;
         when Upload_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded UploadPart response from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete body; exactly empty on status 200
   --  @param Headers Caller-supplied modeled response headers
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Uploaded-part metadata or structured S3 rejection
   function Decode_Upload_Part_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Upload_Part_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Outcome;

   --  Decode one complete UploadPart HTTP response. Header multiplicity,
   --  success-body emptiness, modeled output values, requested-checksum
   --  binding, and bounded S3 error XML are validated as one snapshot.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact UploadPart request whose checksum is bound
   --  @param Limits Bounded XML parser limits for modeled error responses
   --  @return Typed UploadPart success or S3 rejection
   --  @exception Invalid_Request if Prepared is not UploadPart
   --  @exception Invalid_Response if the complete response is inconsistent
   function Decode_Upload_Part_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Outcome;

   --  Execute one prepared UploadPart request without replay. Source must be
   --  forward-only and is borrowed only until this call returns.
   --  Invalid_Request is raised before HTTP admission; every other exception
   --  is conservatively publication-ambiguous and must be reconciled using
   --  the prepared upload
   --  ID and part number before any retry or completion decision.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Source Forward-only part body source borrowed for this call
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Uploaded-part metadata or structured S3 rejection
   function Execute_Upload_Part
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Outcome;

   --  Presence-preserving inclusive source-byte range.
   --  @field Is_Set Whether the range is supplied
   --  @field First Inclusive first source-byte offset
   --  @field Last Inclusive last source-byte offset
   type Optional_Copy_Source_Range is record
      Is_Set : Boolean := False;
      First  : Byte_Count := 0;
      Last   : Byte_Count := 0;
   end record;

   --  Every modeled UploadPartCopy request member. Copy_Source is the exact
   --  x-amz-copy-source value, including any caller-selected version query.
   --  @field Part_Number Required destination part number
   --  @field Upload_ID Required multipart upload identifier
   --  @field Copy_Source Required source-object wire value
   --  @field Copy_Source_If_Match Optional source tag precondition
   --  @field Copy_Source_If_Modified_Since Optional source time precondition
   --  @field Copy_Source_If_None_Match Optional source nonmatch precondition
   --  @field Copy_Source_If_Unmodified_Since Optional source time condition
   --  @field Source_Range Optional inclusive source-byte range
   --  @field SSE_Customer_Algorithm Optional destination key algorithm
   --  @field SSE_Customer_Key Optional destination customer key
   --  @field SSE_Customer_Key_MD5 Optional destination key MD5
   --  @field Copy_Source_SSE_Customer_Algorithm Optional source decryption
   --  @field Copy_Source_SSE_Customer_Key Optional source customer key
   --  @field Copy_Source_SSE_Customer_Key_MD5 Optional source key MD5
   --  @field Request_Payer Optional requester-pays header value
   --  @field Expected_Bucket_Owner Optional destination-owner precondition
   --  @field Expected_Source_Bucket_Owner Optional source-owner precondition
   type Upload_Part_Copy_Parameters is record
      Part_Number       : S3.Core.Part_Number := S3.Core.Part_Number'First;
      Upload_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source       : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Match : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Modified_Since : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_None_Match : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Unmodified_Since :
        Ada.Strings.Unbounded.Unbounded_String;
      Source_Range      : Optional_Copy_Source_Range;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key       : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5   : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_SSE_Customer_Algorithm :
        Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_SSE_Customer_Key :
        Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_SSE_Customer_Key_MD5 :
        Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Source_Bucket_Owner :
        Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one signed bodyless UploadPartCopy request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled part-copy controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless UploadPartCopy request metadata
   function Prepare_Upload_Part_Copy
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Upload_Part_Copy_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Modeled UploadPartCopy success metadata.
   --  @field Copy_Source_Version_ID Optional returned source version
   --  @field Copy_Part Parsed copied-part result document
   --  @field Server_Side_Encryption Optional returned encryption algorithm
   --  @field SSE_Customer_Algorithm Optional returned customer algorithm
   --  @field SSE_Customer_Key_MD5 Optional returned customer-key MD5
   --  @field SSE_KMS_Key_ID Optional returned KMS key identifier
   --  @field Bucket_Key_Enabled Optional returned bucket-key header text
   --  @field Request_Charged Optional returned requester-charge value
   type Upload_Part_Copy_Result is record
      Copy_Source_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Part              : S3.Multipart.Copy_Part_Result;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5   : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled     : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged        : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish copied part from structured S3 rejection.
   --  @enum Part_Copied Validated HTTP-200 copied-part result was decoded
   --  @enum Copy_Part_Rejected Structured S3 error was decoded
   type Upload_Part_Copy_Outcome_Kind is
     (Part_Copied, Copy_Part_Rejected);

   --  Result of decoding or executing one UploadPartCopy operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Validated copied-part metadata on success
   --  @field Error Structured S3 error on rejection
   type Upload_Part_Copy_Outcome
     (Kind : Upload_Part_Copy_Outcome_Kind := Copy_Part_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Part_Copied =>
            Result : Upload_Part_Copy_Result;
         when Copy_Part_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded part-copy response from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Headers Caller-supplied modeled response headers
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Copied-part metadata or structured S3 rejection
   function Decode_Upload_Part_Copy_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Upload_Part_Copy_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome;

   --  Decode one complete UploadPartCopy HTTP response. Physical singleton
   --  headers, bounded values, embedded HTTP-200 errors, and Requester Pays
   --  consistency are validated before the modeled response is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared UploadPartCopy request
   --  @param Limits Bounded XML parser limits
   --  @return Typed copied-part success or S3 rejection
   --  @exception Invalid_Request Prepared is not UploadPartCopy
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_Upload_Part_Copy_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome;

   --  Execute one bodyless UploadPartCopy attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Copied-part metadata or structured S3 rejection
   function Execute_Upload_Part_Copy
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome;

   --  Every modeled CopyObject request member other than the destination
   --  bucket and key, which are explicit Prepare_Copy_Object parameters.
   --  @field ACL Optional canned access-control policy
   --  @field Cache_Control Optional cache-control metadata
   --  @field Checksum_Algorithm Optional requested result-checksum algorithm
   --  @field Content_Disposition Optional content-disposition metadata
   --  @field Content_Encoding Optional content-encoding metadata
   --  @field Content_Language Optional content-language metadata
   --  @field Copy_Source Required source-object wire value
   --  @field Content_Type Optional content-type metadata
   --  @field Copy_Source_If_Match Optional source entity-tag precondition
   --  @field Copy_Source_If_Modified_Since Optional source time precondition
   --  @field Copy_Source_If_None_Match Optional source tag precondition
   --  @field Copy_Source_If_Unmodified_Since Optional source time condition
   --  @field Expires Optional expiration metadata
   --  @field Grant_Full_Control Optional full-control grant
   --  @field Grant_Read Optional read grant
   --  @field Grant_Read_ACP Optional ACL-read grant
   --  @field Grant_Write_ACP Optional ACL-write grant
   --  @field If_Match Optional destination entity-tag precondition
   --  @field If_None_Match Optional destination nonmatching precondition
   --  @field Metadata Caller-supplied object metadata entries
   --  @field Metadata_Directive Optional metadata copy directive
   --  @field Tagging_Directive Optional tagging copy directive
   --  @field Annotation_Directive Optional annotation copy directive
   --  @field Server_Side_Encryption Optional destination encryption value
   --  @field Storage_Class Optional destination storage class
   --  @field Website_Redirect_Location Optional redirect metadata
   --  @field SSE_Customer_Algorithm Optional destination key algorithm
   --  @field SSE_Customer_Key Optional destination customer key
   --  @field SSE_Customer_Key_MD5 Optional destination key MD5
   --  @field SSE_KMS_Key_ID Optional destination KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional destination KMS context
   --  @field Bucket_Key_Enabled Presence-preserving destination flag
   --  @field Copy_Source_SSE_Customer_Algorithm Optional source decryption
   --  @field Copy_Source_SSE_Customer_Key Optional source customer key
   --  @field Copy_Source_SSE_Customer_Key_MD5 Optional source key MD5
   --  @field Request_Payer Optional requester-pays header value
   --  @field Tagging Optional destination tag-set encoding
   --  @field Object_Lock_Mode Optional destination retention mode
   --  @field Object_Lock_Retain_Until_Date Optional retention timestamp
   --  @field Object_Lock_Legal_Hold_Status Optional legal-hold status
   --  @field Expected_Bucket_Owner Optional destination-owner precondition
   --  @field Expected_Source_Bucket_Owner Optional source-owner precondition
   type Copy_Object_Parameters is record
      ACL : Ada.Strings.Unbounded.Unbounded_String;
      Cache_Control : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      Content_Disposition : Ada.Strings.Unbounded.Unbounded_String;
      Content_Encoding : Ada.Strings.Unbounded.Unbounded_String;
      Content_Language : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Match : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Modified_Since : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_None_Match : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Unmodified_Since :
        Ada.Strings.Unbounded.Unbounded_String;
      Expires : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Full_Control : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read_ACP : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write_ACP : Ada.Strings.Unbounded.Unbounded_String;
      If_Match : Ada.Strings.Unbounded.Unbounded_String;
      If_None_Match : Ada.Strings.Unbounded.Unbounded_String;
      Metadata : Metadata_Entry_Vectors.Vector;
      Metadata_Directive : Ada.Strings.Unbounded.Unbounded_String;
      Tagging_Directive : Ada.Strings.Unbounded.Unbounded_String;
      Annotation_Directive : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      Storage_Class : Ada.Strings.Unbounded.Unbounded_String;
      Website_Redirect_Location :
        Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5 : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context :
        Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled : Optional_Boolean;
      Copy_Source_SSE_Customer_Algorithm :
        Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_SSE_Customer_Key :
        Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_SSE_Customer_Key_MD5 :
        Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer : Ada.Strings.Unbounded.Unbounded_String;
      Tagging : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Mode : Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Retain_Until_Date :
        Ada.Strings.Unbounded.Unbounded_String;
      Object_Lock_Legal_Hold_Status :
        Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Source_Bucket_Owner :
        Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact signed bodyless CopyObject request.
   --  @param Origin Exact HTTP origin used by the caller-owned client
   --  @param Style Path or virtual-hosted bucket addressing
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled CopyObject controls
   --  @param Identity Credentials borrowed only for signing
   --  @param Region SigV4 signing region
   --  @param Timestamp SigV4 basic-format UTC timestamp
   --  @return Prepared bodyless CopyObject request metadata
   function Prepare_Copy_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Copy_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every modeled CopyObject output member.
   --  @field Copy_Result Parsed copy-result document
   --  @field Expiration Optional returned expiration metadata
   --  @field Copy_Source_Version_ID Optional returned source version
   --  @field Version_ID Optional returned destination version
   --  @field Server_Side_Encryption Optional returned encryption value
   --  @field SSE_Customer_Algorithm Optional returned customer algorithm
   --  @field SSE_Customer_Key_MD5 Optional returned customer-key MD5
   --  @field SSE_KMS_Key_ID Optional returned KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional returned KMS context
   --  @field Bucket_Key_Enabled Optional returned bucket-key header text
   --  @field Request_Charged Optional returned requester-charge value
   type Copy_Object_Result is record
      Copy_Result : S3.Copies.Copy_Object_Result;
      Expiration : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      SSE_Customer_Key_MD5 : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Distinguish completed object copy from structured S3 rejection.
   --  @enum Object_Copied Validated HTTP-200 copy result was decoded
   --  @enum Copy_Object_Rejected Structured S3 error was decoded
   type Copy_Object_Outcome_Kind is (Object_Copied, Copy_Object_Rejected);

   --  Result of decoding or executing one CopyObject operation.
   --  @field Kind Outcome discriminator
   --  @field Status Exact HTTP response status
   --  @field Result Validated copy metadata on success
   --  @field Error Structured S3 error on rejection
   type Copy_Object_Outcome
     (Kind : Copy_Object_Outcome_Kind := Copy_Object_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Copied =>
            Result : Copy_Object_Result;
         when Copy_Object_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Decode one bounded CopyObject response from supplied header values.
   --  @param Status HTTP response status
   --  @param Payload Complete same-response body
   --  @param Headers Caller-supplied modeled response headers
   --  @param Request_ID Supplied request identifier, possibly empty
   --  @param Host_ID Supplied host identifier, possibly empty
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Copy metadata or structured S3 rejection
   function Decode_Copy_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Copy_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Copy_Object_Outcome;

   --  Decode one complete CopyObject HTTP response. Physical singleton
   --  headers, bounded values, embedded HTTP-200 errors, and Requester Pays
   --  consistency are validated before the modeled response is exposed.
   --  @param Response Complete HTTP response head
   --  @param Payload Complete bounded response body
   --  @param Prepared Exact prepared CopyObject request
   --  @param Limits Bounded XML parser limits
   --  @return Typed copy success or S3 rejection
   --  @exception Invalid_Request Prepared is not CopyObject
   --  @exception Invalid_Response Complete response is inconsistent
   function Decode_Copy_Object_Complete_Response
     (Response : Flyology.HTTP.Client.Response;
      Payload  : String;
      Prepared : Prepared_Request;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Copy_Object_Outcome;

   --  Execute one bodyless CopyObject attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Exact matching prepared request
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Copy metadata or structured S3 rejection
   function Execute_Copy_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Copy_Object_Outcome;

   --  Release request-owned storage after its composable HTTP child drains.
   --  @param Prepared Drained request whose retained storage is released
   procedure Clear_Prepared_Request (Prepared : in out Prepared_Request);

   --  @exclude
   --  @param Prepared Prepared request with owned payload storage
   --  @return Owned request-payload length
   function Owned_Payload_Length
     (Prepared : Prepared_Request) return Natural;

   --  @exclude
   --  @param Prepared Prepared request with owned payload storage
   --  @param Index One-based owned payload position
   --  @return Character at the requested payload position
   function Owned_Payload_Element
     (Prepared : Prepared_Request;
      Index    : Positive) return Character;

   --  Start a prepared PutObject exchange in an established HTTP operation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Source One-shot request source retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Object
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetObject exchange into an acquired bounded buffer.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Destination Acquired response buffer retained through drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object
     (Client      : not null access Flyology.HTTP.Client.Client;
      Prepared    : not null access constant Prepared_Request;
      Destination : in out Flyology.Buffers.Unique_Buffer;
      Deadline    : Flyology.HTTP.Client.Monotonic_Deadline;
      Token       : access Flyology.Cancellation.Token := null;
      Operation   : in out Flyology.HTTP.Client.Exchange_Operation)
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Start a prepared GetObjectTorrent exchange into an acquired buffer.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Exact prepared GetObjectTorrent request
   --  @param Destination Acquired caller-owned bounded output handle
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @param Operation Fresh HTTP exchange operation
   procedure Get_Object_Torrent
     (Client      : not null access Flyology.HTTP.Client.Client;
      Prepared    : not null access constant Prepared_Request;
      Destination : in out Flyology.Buffers.Unique_Buffer;
      Deadline    : Flyology.HTTP.Client.Monotonic_Deadline;
      Token       : access Flyology.Cancellation.Token := null;
      Operation   : in out Flyology.HTTP.Client.Exchange_Operation)
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Start an exact prepared GetObjectTorrent exchange into a bounded sink.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Prepared Exact prepared GetObjectTorrent request
   --  @param Sink Caller-owned bounded response-body sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @param Operation Fresh HTTP exchange operation
   procedure Get_Object_Torrent
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListObjects v1 exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Objects
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared service-level ListBuckets exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Buckets
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared CreateBucket exchange with its one-shot body source.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Source One-shot request source retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Create_Bucket
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared bodyless HeadBucket exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Head_Bucket
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetBucketLocation exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Location
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetBucketVersioning exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Versioning
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared CreateSession exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Create_Session
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetBucketPolicy exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Policy
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketPolicyStatus exchange into a bounded
   --  sink. A prepared request for another bucket-control read is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Policy_Status
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketRequestPayment exchange into a bounded
   --  sink. A prepared request for another bucket-control read is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Request_Payment
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketAccelerateConfiguration exchange into
   --  a bounded sink. A prepared request for another bucket-control read is
   --  rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Accelerate_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketAbac exchange into a bounded sink. A
   --  prepared request for another bucket-control read is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_ABAC
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketAcl exchange into a bounded sink. A
   --  prepared request for another bucket-control read is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_ACL
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketMetadataTableConfiguration exchange
   --  into a bounded sink. Another prepared operation is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Metadata_Table_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketPolicy exchange with its one-shot
   --  policy source. The prepared request must be bound to PutBucketPolicy;
   --  another bucket-control mutation is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Policy
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketPolicy exchange with a deliberately
   --  non-replayable empty source. A prepared request for another bucket
   --  configuration deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Policy
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetPublicAccessBlock exchange into a bounded
   --  sink. A prepared request for another bucket-control read is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Public_Access_Block
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketOwnershipControls exchange into a
   --  bounded sink. A prepared request for another bucket-control read is
   --  rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Ownership_Controls
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketCors exchange into a bounded sink.
   --  A prepared request for another bucket-control read is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_CORS
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketEncryption exchange into a bounded
   --  sink. A prepared request for another bucket-control read is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Encryption
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketLifecycleConfiguration exchange into
   --  a bounded sink. Another bucket-control read is rejected before HTTP
   --  admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Lifecycle_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketNotificationConfiguration exchange
   --  into a bounded sink. Any other prepared operation is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Notification_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketReplication exchange into a bounded
   --  sink. Any other prepared operation is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Bucket_Replication
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketMetricsConfiguration exchange into a
   --  bounded sink. Another prepared operation is rejected before admission.
   procedure Get_Bucket_Metrics_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared ListBucketMetricsConfigurations exchange into
   --  a bounded sink. Another prepared operation is rejected pre-admission.
   procedure List_Bucket_Metrics_Configurations
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared ListBucketAnalyticsConfigurations exchange into
   --  a bounded sink. Another prepared operation is rejected pre-admission.
   procedure List_Bucket_Analytics_Configurations
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketAnalyticsConfiguration exchange into
   --  a bounded sink. Another prepared operation is rejected pre-admission.
   procedure Get_Bucket_Analytics_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);
   --  Start an exact prepared GetBucketIntelligentTieringConfiguration
   --  exchange into a bounded sink. Another prepared operation is rejected
   --  pre-admission.
   procedure Get_Bucket_Intelligent_Tiering_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);
   --  Start an exact prepared ListBucketIntelligentTieringConfigurations
   --  exchange into a bounded sink. Another operation is rejected
   --  pre-admission.
   procedure List_Bucket_Intelligent_Tiering_Configurations
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);
   --  Start an exact prepared GetBucketInventoryConfiguration exchange into
   --  a bounded sink. Another prepared operation is rejected pre-admission.
   procedure Get_Bucket_Inventory_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start one exact prepared ListBucketInventoryConfigurations exchange.
   --  Another prepared operation is rejected before HTTP admission.
   procedure List_Bucket_Inventory_Configurations
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketLogging exchange into a bounded sink.
   --  Another prepared operation is rejected before HTTP admission.
   procedure Get_Bucket_Logging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketWebsite exchange into a bounded sink.
   --  Another prepared operation is rejected before HTTP admission.
   procedure Get_Bucket_Website
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetBucketMetadataConfiguration exchange into a
   --  bounded sink. Another prepared operation is rejected pre-admission.
   procedure Get_Bucket_Metadata_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared CreateBucketMetadataTableConfiguration
   --  exchange with its one-shot destination source. Another bucket-control
   --  mutation is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Create_Bucket_Metadata_Table_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketRequestPayment exchange with its
   --  one-shot payer source. Another bucket-control mutation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Request_Payment
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketAbac exchange with its one-shot ABAC
   --  status source. Another bucket-control mutation is rejected before HTTP
   --  admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_ABAC
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketAccelerateConfiguration exchange with
   --  its one-shot acceleration-status source. Another bucket-control
   --  mutation is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Accelerate_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutPublicAccessBlock exchange with its one-shot
   --  configuration source. Another bucket-control mutation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Public_Access_Block
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketOwnershipControls exchange with its
   --  one-shot configuration source. Another bucket-control mutation is
   --  rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Ownership_Controls
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketEncryption exchange with its one-shot
   --  configuration source. Another bucket-control mutation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Encryption
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketLifecycleConfiguration exchange with
   --  its one-shot configuration source. Any other prepared operation is
   --  rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Lifecycle_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketNotificationConfiguration exchange
   --  with its one-shot source. Any other prepared operation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Notification_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketReplication exchange with its
   --  non-rewindable source. Any other prepared operation is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Replication
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketAnalyticsConfiguration exchange with
   --  its non-rewindable source. Any other prepared operation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Analytics_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketIntelligentTieringConfiguration
   --  exchange with its non-rewindable source. Any other prepared operation
   --  is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Intelligent_Tiering_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketMetricsConfiguration exchange with
   --  its non-rewindable source. Any other prepared operation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Metrics_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutBucketCors exchange with its one-shot
   --  configuration source. Another bucket-control mutation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_CORS
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeletePublicAccessBlock exchange with a
   --  deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Public_Access_Block
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketCors exchange with a deliberately
   --  non-replayable empty source. Another configuration deletion is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_CORS
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketEncryption exchange with a
   --  deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Encryption
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketLifecycle exchange with a
   --  deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Lifecycle
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketReplication exchange with a
   --  deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Replication
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketWebsite exchange with a
   --  deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Website
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketMetricsConfiguration
   --  exchange with a deliberately non-replayable empty source. Another
   --  configuration deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Metrics_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketMetadataConfiguration
   --  exchange with a deliberately non-replayable empty source. Another
   --  configuration deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Metadata_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketMetadataTableConfiguration
   --  exchange with a deliberately non-replayable empty source. Another
   --  configuration deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Metadata_Table_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketAnalyticsConfiguration
   --  exchange with a deliberately non-replayable empty source. Another
   --  configuration deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Analytics_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketIntelligentTieringConfiguration
   --  exchange with a deliberately non-replayable empty source. Another
   --  configuration deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Intelligent_Tiering_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketInventoryConfiguration exchange
   --  with a deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Inventory_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteBucketOwnershipControls exchange with a
   --  deliberately non-replayable empty source. Another configuration
   --  deletion is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Ownership_Controls
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared PutBucketVersioning exchange with its one-shot body.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Bucket_Versioning
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteBucket exchange with a deliberately
   --  non-replayable empty request source.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    :
        not null access
          Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListObjectsV2 exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Objects_V2
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListObjectVersions exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Object_Versions
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetObjectAttributes exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object_Attributes
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared HeadObject exchange into a bodyless sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Sink Bodyless response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Head_Object
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteObject exchange without replaying its source.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Object
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteObjects batch exchange.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact signed DeleteObjects request
   --  @param Source One-shot request body source retained through drain
   --  @param Sink Bounded response sink retained through drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Delete_Objects
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared CreateMultipartUpload exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Source One-shot empty source retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Create_Multipart_Upload
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared CompleteMultipartUpload exchange.
   --  @param Client Configured caller-owned HTTP client
   --  @param Prepared Exact signed multipart-completion request
   --  @param Source One-shot request body source retained through drain
   --  @param Sink Bounded response sink retained through drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Complete_Multipart_Upload
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared AbortMultipartUpload exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Source One-shot request source retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Abort_Multipart_Upload
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListParts exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Parts
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListMultipartUploads exchange into a bounded sink.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Multipart_Uploads
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared CopyObject exchange without replaying its source.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Source One-shot empty source retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Copy_Object
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared UploadPartCopy exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed bodyless request retained through terminal drain
   --  @param Source One-shot empty source retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Upload_Part_Copy
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared UploadPart exchange with its one-shot part source.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Source One-shot part body source retained through drain
   --  @param Sink Bounded response sink retained through drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Upload_Part
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared PutBucketTagging exchange.
   procedure Put_Bucket_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetBucketTagging exchange.
   procedure Get_Bucket_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteBucketTagging exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Empty request source retained through terminal drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Bucket_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared PutObjectTagging exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Serialized tag document retained through terminal drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Object_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetObjectTagging exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded tag-document sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteObjectTagging exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Object_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared DeleteObjectAnnotation exchange with a
   --  non-replayable empty source. Another modeled operation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable empty source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Delete_Object_Annotation
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared ListObjectAnnotations exchange into a bounded
   --  response sink. Another modeled operation is rejected pre-admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Exact prepared request retained through terminal drain
   --  @param Sink Caller-owned bounded response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Object_Annotations
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetObjectAcl exchange into a bounded response
   --  sink. Another prepared operation is rejected before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object_ACL
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetObjectLegalHold exchange into a bounded
   --  response sink. Another prepared operation is rejected before HTTP
   --  admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object_Legal_Hold
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutObjectLegalHold exchange with its owned,
   --  one-shot request body. Another prepared operation is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Object_Legal_Hold
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetObjectRetention exchange into a bounded
   --  response sink. Another prepared operation is rejected before HTTP
   --  admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object_Retention
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutObjectRetention exchange with its owned,
   --  one-shot request body. Another prepared operation is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Object_Retention
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared GetObjectLockConfiguration exchange into a
   --  bounded response sink. Another prepared operation is rejected before
   --  HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Get_Object_Lock_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start an exact prepared PutObjectLockConfiguration exchange with its
   --  owned one-shot request body. Another prepared operation is rejected
   --  before HTTP admission.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Prepared Owned signed request retained by the parent operation
   --  @param Source Non-rewindable request source retained through drain
   --  @param Sink Bounded response sink retained by the parent operation
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure Put_Object_Lock_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

--  BEGIN S3 OPERATION GENERATOR: LOW_LEVEL_VISIBLE
--  Generated by tools/s3-operation.py; do not edit this region.

   --  Complete model-derived ListDirectoryBuckets inputs. Presence
   --  remains independent from an empty cursor or numeric zero. The caller
   --  selects the page size; this record supplies no default.
   --  @field Continuation_Token Exact continuation token when present
   --  @field Has_Continuation_Token Whether Continuation_Token is present
   --  @field Max_Directory_Buckets Exact page size when present
   --  @field Has_Max_Directory_Buckets Whether Max_Directory_Buckets is
   --  present
   type List_Directory_Buckets_Parameters is record
      Continuation_Token        : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token    : Boolean;
      Max_Directory_Buckets     : Natural;
      Has_Max_Directory_Buckets : Boolean;
   end record;

   --  Build and sign one exact ListDirectoryBuckets request. Origin must be
   --  the caller-selected S3 Express control endpoint.
   --  @param Origin Exact S3 Express control endpoint
   --  @param Parameters Complete modeled request inputs
   --  @param Identity Credentials borrowed only while signing
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @return Prepared signed ListDirectoryBuckets request
   function Prepare_List_Directory_Buckets
     (Origin     : Flyology.HTTP.Origin;
      Parameters : List_Directory_Buckets_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Shape of a completed ListDirectoryBuckets response.
   --  @enum Directory_Buckets_Listed A modeled directory-bucket page exists
   --  @enum List_Directory_Buckets_Rejected A structured S3 rejection exists
   type List_Directory_Buckets_Outcome_Kind is
     (Directory_Buckets_Listed, List_Directory_Buckets_Rejected);

   --  Kind selects the meaningful payload. All fields remain explicit so the
   --  low-level result is definite without inventing a status or discriminant
   --  default for an exchange that has not occurred.
   --  @field Kind Selects the meaningful response payload
   --  @field Status Exact HTTP response status
   --  @field Result Decoded page when Kind is Directory_Buckets_Listed
   --  @field Error Structured S3 error when Kind is rejected
   type List_Directory_Buckets_Outcome is record
      Kind   : List_Directory_Buckets_Outcome_Kind;
      Status : Flyology.HTTP.Status_Code;
      Result : S3.Buckets.List_Buckets_Result;
      Error  : S3.Errors.Error_Response;
   end record;

   --  Decode one complete ListDirectoryBuckets HTTP response.
   --  @param Response Complete response head providing status and headers
   --  @param Payload Complete response body bytes
   --  @param Limits Caller-selected XML parsing limits
   --  @param Collection_Limit Caller-selected decoded collection limit
   --  @return Decoded directory-bucket page or structured S3 rejection
   function Decode_List_Directory_Buckets_Complete_Response
     (Response         : Flyology.HTTP.Client.Response;
      Payload          : String;
      Limits           : S3.XML.Parse_Limits;
      Collection_Limit : Positive)
      return List_Directory_Buckets_Outcome;

   --  Execute and decode one prepared ListDirectoryBuckets request.
   --  @param Client HTTP client that owns the synchronous exchange
   --  @param Prepared Exact prepared ListDirectoryBuckets request
   --  @param Timeout Caller-selected whole-exchange timeout
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and XML parsing limits
   --  @param Collection_Limit Caller-selected decoded collection limit
   --  @return Decoded directory-bucket page or structured S3 rejection
   function Execute_List_Directory_Buckets
     (Client           : aliased in out Flyology.HTTP.Client.Client;
      Prepared         : Prepared_Request;
      Timeout          : Duration;
      Token            : access Flyology.Cancellation.Token;
      Limits           : S3.XML.Parse_Limits;
      Collection_Limit : Positive)
      return List_Directory_Buckets_Outcome;

   --  Start one prepared composable ListDirectoryBuckets exchange.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Signed request retained through terminal drain
   --  @param Sink Bounded response sink retained through terminal drain
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established HTTP exchange
   procedure List_Directory_Buckets
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Complete modeled non-resource inputs for PutBucketAcl.
   --  Empty strings preserve member absence. Access_Control_Policy.Is_Set
   --  selects the body mode; otherwise exactly one canned-ACL or explicit
   --  grant-header group is required by the reviewed S3 cross-field rule.
   --  Empty Content_MD5 derives the externally required digest from the
   --  exact generated body; it does not select a retry or resource policy.
   --  @field ACL Optional exact canned ACL header
   --  @field Content_MD5 Optional exact base64 MD5 override
   --  @field Checksum_Algorithm Optional exact modeled checksum algorithm
   --  @field Grant_Full_Control Optional exact grant header
   --  @field Grant_Read Optional exact grant header
   --  @field Grant_Read_ACP Optional exact grant header
   --  @field Grant_Write Optional exact grant header
   --  @field Grant_Write_ACP Optional exact grant header
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_ACL_Parameters is record
      ACL                       : Ada.Strings.Unbounded.Unbounded_String;
      Content_MD5               : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm        : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Full_Control        : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read                : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Read_ACP            : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write               : Ada.Strings.Unbounded.Unbounded_String;
      Grant_Write_ACP           : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Complete non-body inputs for generated named configuration
   --  replacements. The query identifier and body identifier remain
   --  independent because the pinned model encodes no equality constraint.
   --  @field ID Required exact `id` query value
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   type Put_Bucket_Inventory_Configuration_Parameters is record
      ID                    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exact CreateBucketMetadataConfiguration request. The
   --  returned request owns its exact serialized and signed one-shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Bucket metadata configuration value serialized before
   --  admission
   --  @param Parameters Complete modeled non-resource
   --  CreateBucketMetadataConfiguration controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Create_Bucket_Metadata_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Metadata_Configurations.Metadata_Configuration_Request;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared CreateBucketMetadataConfiguration request
   --  without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Create_Bucket_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared CreateBucketMetadataConfiguration exchange. A
   --  differently bound request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Create_Bucket_Metadata_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact UpdateBucketMetadataInventoryTableConfiguration
   --  request. The returned request owns its exact serialized and signed one-
   --  shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Metadata inventory-table configuration value serialized
   --  before admission
   --  @param Parameters Complete modeled non-resource
   --  UpdateBucketMetadataInventoryTableConfiguration controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Set_Metadata_Inventory_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Metadata_Configurations.Inventory_Table_Configuration;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared
   --  UpdateBucketMetadataInventoryTableConfiguration request without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Set_Metadata_Inventory_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared UpdateBucketMetadataInventoryTableConfiguration
   --  exchange. A differently bound request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Set_Metadata_Inventory_Table_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact UpdateBucketMetadataJournalTableConfiguration request.
   --  The returned request owns its exact serialized and signed one-shot XML
   --  body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Metadata journal-table configuration value serialized
   --  before admission
   --  @param Parameters Complete modeled non-resource
   --  UpdateBucketMetadataJournalTableConfiguration controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Set_Metadata_Journal_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Metadata_Configurations.Record_Expiration;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared UpdateBucketMetadataJournalTableConfiguration
   --  request without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Set_Metadata_Journal_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared UpdateBucketMetadataJournalTableConfiguration
   --  exchange. A differently bound request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Set_Metadata_Journal_Table_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact UpdateBucketMetadataAnnotationTableConfiguration
   --  request. The returned request owns its exact serialized and signed one-
   --  shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Metadata annotation-table configuration value serialized
   --  before admission
   --  @param Parameters Complete modeled non-resource
   --  UpdateBucketMetadataAnnotationTableConfiguration controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Set_Metadata_Annotation_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Metadata_Configurations.Annotation_Table_Configuration;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared
   --  UpdateBucketMetadataAnnotationTableConfiguration request without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Set_Metadata_Annotation_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared
   --  UpdateBucketMetadataAnnotationTableConfiguration exchange. A differently
   --  bound request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Set_Metadata_Annotation_Table_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact PutBucketAcl request. The returned request owns its
   --  exact serialized and signed one-shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Bucket access-control policy value serialized before
   --  admission
   --  @param Parameters Complete modeled non-resource PutBucketAcl controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Put_Bucket_ACL
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.ACL.Access_Control_Policy;
      Parameters : Put_Bucket_ACL_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared PutBucketAcl request without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Put_Bucket_ACL
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared PutBucketAcl exchange. A differently bound
   --  request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Put_Bucket_ACL
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact PutBucketInventoryConfiguration request. The returned
   --  request owns its exact serialized and signed one-shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Inventory configuration value serialized before admission
   --  @param Parameters Complete modeled non-resource
   --  PutBucketInventoryConfiguration controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Put_Bucket_Inventory_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Inventory.Inventory_Configuration;
      Parameters : Put_Bucket_Inventory_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared PutBucketInventoryConfiguration request
   --  without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Put_Bucket_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared PutBucketInventoryConfiguration exchange. A
   --  differently bound request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Put_Bucket_Inventory_Configuration
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact PutBucketLogging request. The returned request owns
   --  its exact serialized and signed one-shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Bucket logging configuration value serialized before
   --  admission
   --  @param Parameters Complete modeled non-resource PutBucketLogging
   --  controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Put_Bucket_Logging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Logging.Logging_Status;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared PutBucketLogging request without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Put_Bucket_Logging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared PutBucketLogging exchange. A differently bound
   --  request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Put_Bucket_Logging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Prepare one exact PutBucketWebsite request. The returned request owns
   --  its exact serialized and signed one-shot XML body.
   --  @param Origin Exact HTTP origin used for routing and signing
   --  @param Style Caller-selected S3 addressing style
   --  @param Bucket Required exact target bucket
   --  @param Value Bucket website configuration value serialized before
   --  admission
   --  @param Parameters Complete modeled non-resource PutBucketWebsite
   --  controls
   --  @param Identity Credentials borrowed only while signing the request
   --  @param Region Exact SigV4 signing region
   --  @param Timestamp Exact SigV4 signing timestamp
   --  @param Limits Caller-selected bounded XML limits
   --  @return Prepared signed request with an owned one-shot body
   function Prepare_Put_Bucket_Website
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Value : S3.Website.Website_Configuration;
      Parameters : Bucket_Control_Mutation_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits)
      return Prepared_Request;

   --  Execute one exact prepared PutBucketWebsite request without replay.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request and owned body
   --  @param Timeout Whole request and drain budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected bounded response XML limits
   --  @return Complete modeled response or structured rejection
   function Execute_Put_Bucket_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration;
      Token : access Flyology.Cancellation.Token;
      Limits : S3.XML.Parse_Limits)
      return Put_Bucket_Control_Outcome;

   --  Start one exact prepared PutBucketWebsite exchange. A differently bound
   --  request is rejected before HTTP admission.
   --  @param Client HTTP client retained through terminal drain
   --  @param Prepared Exact prepared request retained through drain
   --  @param Source One-shot request body source
   --  @param Sink Bounded response body sink
   --  @param Deadline Absolute admission, exchange, and drain limit
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Caller-owned HTTP exchange operation
   procedure Put_Bucket_Website
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);
--  END S3 OPERATION GENERATOR: LOW_LEVEL_VISIBLE

private
   Maximum_Credential_Bytes : constant := 1_024;
   Maximum_Session_Token_Bytes : constant := 8_192;

   type Create_Session_Response_Metadata is record
      --  Private validity sentinel: only the physical response reader sets
      --  this, so default-declared opaque values cannot bypass validation.
      Validated  : Boolean := False;
      --  This derived placeholder is ignored unless Validated is true.
      Status     : Flyology.HTTP.Status_Code :=
        Flyology.HTTP.Status_Code'First;
      Headers    : Create_Session_Response_Headers := (others => <>);
      Request_ID : Ada.Strings.Unbounded.Unbounded_String;
      Host_ID    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Session_Token_Kind is (Security_Token, S3_Session_Token);

   type Credentials is new Ada.Finalization.Limited_Controlled with record
      Access_Key_Length : Natural range 0 .. Maximum_Credential_Bytes := 0;
      Secret_Key_Length : Natural range 0 .. Maximum_Credential_Bytes := 0;
      Session_Token_Length :
        Natural range 0 .. Maximum_Session_Token_Bytes := 0;
      Access_Key_Data : String (1 .. Maximum_Credential_Bytes) :=
        (others => Character'Val (0));
      Secret_Key_Data : String (1 .. Maximum_Credential_Bytes) :=
        (others => Character'Val (0));
      Session_Token_Data : String (1 .. Maximum_Session_Token_Bytes) :=
        (others => Character'Val (0));
      Token_Kind : Session_Token_Kind := Security_Token;
   end record;

   --  @exclude
   --  @param Item Credential storage wiped during finalization
   overriding procedure Finalize (Item : in out Credentials);

   type Operation_Kind is
     (List_Objects_V2_Operation,
      List_Objects_Operation,
      List_Object_Versions_Operation,
      List_Buckets_Operation,
      Model_Driven_Operation,
      Create_Bucket_Operation,
      Get_Bucket_Location_Operation,
      Put_Bucket_Tagging_Operation,
      Get_Bucket_Tagging_Operation,
      Delete_Bucket_Tagging_Operation,
      Put_Bucket_Versioning_Operation,
      Get_Bucket_Versioning_Operation,
      Head_Bucket_Operation,
      Head_Object_Operation,
      Get_Object_Operation,
      Get_Object_Attributes_Operation,
      Put_Object_Operation,
      Delete_Bucket_Operation,
      Delete_Bucket_Configuration_Operation,
      Get_Bucket_Control_Operation,
      Bucket_Control_Mutation_Operation,
      Get_Object_ACL_Operation,
      Get_Object_Torrent_Operation,
      Get_Object_Legal_Hold_Operation,
      Put_Object_Legal_Hold_Operation,
      Get_Object_Retention_Operation,
      Put_Object_Retention_Operation,
      Get_Object_Lock_Configuration_Operation,
      Put_Object_Lock_Configuration_Operation,
      Delete_Object_Operation,
      Delete_Objects_Operation,
      Create_Multipart_Operation,
      Complete_Multipart_Operation,
      Abort_Multipart_Operation,
      List_Parts_Operation,
      List_Multipart_Uploads_Operation,
      Upload_Part_Operation,
      Upload_Part_Copy_Operation,
      Copy_Object_Operation,
      Create_Session_Operation);

   type Prepared_Request is record
      Operation : Operation_Kind := List_Objects_V2_Operation;
      Modeled_Operation : S3.Model.Operation_Id :=
        S3.Model.Operation_Id'First;
      Message   : aliased Flyology.HTTP.Client.Request;
      Target_Value    : Ada.Strings.Unbounded.Unbounded_String;
      Authority_Value : Ada.Strings.Unbounded.Unbounded_String;
      Signing   : S3.SigV4.Signing_Result;
      --  Derived request/response binding: a requested PutObject checksum
      --  must be echoed exactly by a successful response. The retained value
      --  is public checksum material, never a caller-owned body borrow.
      Requested_Put_Checksum_Algorithm : Checksum_Algorithm := No_Checksum;
      Requested_Put_Checksum_Value :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Derived request/response binding: a charged PutObject response is
      --  valid only when the exact prepared request admitted requester pays.
      Requested_Put_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Upload_Checksum_Algorithm : Checksum_Algorithm :=
        No_Checksum;
      Requested_Upload_Checksum_Value :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Bucket : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Key : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Part_Number_Marker : S3.Multipart.Part_Marker_Value := 0;
      Requested_Max_Parts : S3.Core.Page_Size := 0;
      Requested_Key_Marker : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Upload_ID_Marker : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Prefix : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Delimiter : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Continuation_Token :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Start_After : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Has_Continuation_Token : Boolean := False;
      Requested_Has_Start_After : Boolean := False;
      --  Derived request/response binding: a charged listing response is
      --  valid only when the exact prepared request admitted requester pays.
      Requested_List_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Derived GetObjectAttributes response binding: a charged response is
      --  valid only when the exact request admitted requester pays, and a
      --  requested version must be echoed by a successful response.
      Requested_Get_Attributes_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Get_Attributes_Version_ID :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Get_Attributes_Selection :
        S3.Attributes.Attribute_Selection := (others => False);
      Requested_Get_Attributes_Has_Max_Parts : Boolean := False;
      Requested_Get_Attributes_Max_Parts : S3.Core.Page_Size := 0;
      Requested_Get_Attributes_Has_Part_Marker : Boolean := False;
      Requested_Get_Attributes_Part_Marker :
        S3.Attributes.Part_Marker_Value := 0;
      --  Derived GetObject response binding: an explicit version selector
      --  must be echoed by a successful response, and a charged response is
      --  valid only when the exact request admitted requester pays.
      Requested_Get_Object_Version_ID :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Get_Object_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Derived HeadObject response binding: an explicit version selector
      --  must be echoed by a successful response, and a charged response is
      --  valid only when the exact request admitted requester pays.
      Requested_Head_Object_Version_ID :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Head_Object_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      --  A successful explicit-version tagging response must echo this exact
      --  selector. Empty means the request selected the current version, so
      --  any returned version remains an observation rather than proof.
      Requested_Object_Tagging_Version_ID :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Derived request/response binding: a charged CopyObject response is
      --  valid only when the exact prepared request admitted requester pays.
      Requested_Copy_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Derived request/response binding: a charged UploadPartCopy response
      --  is valid only when the exact prepared request admitted requester
      --  pays.
      Requested_Upload_Part_Copy_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Derived request/response binding: a charged DeleteObjects response
      --  is valid only when the exact prepared request admitted requester
      --  pays.
      Requested_Delete_Objects_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      --  Owned immutable bytes for prepared one-shot mutation bodies; this
      --  private storage prevents retaining caller-borrowed input.
      Owned_Request_Payload : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Max_Uploads : S3.Core.Page_Size := 0;
      Requested_URL_Encoding : Boolean := False;
      Requested_Has_Key_Marker : Boolean := False;
      Requested_Version_ID_Marker :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Has_Version_ID_Marker : Boolean := False;
      Requested_Has_Prefix : Boolean := False;
      Requested_Has_Delimiter : Boolean := False;
      Requested_Max_Keys : S3.Core.Page_Size := 0;
      Requested_List_Buckets_Max : S3.Buckets.Max_Buckets_Value :=
        S3.Buckets.Max_Buckets_Value'Last;
      Requested_List_Buckets_Prefix :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_List_Buckets_Has_Prefix : Boolean := False;
      Requested_List_Buckets_Region :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_Server_Side_Encryption :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_SSE_Customer_Algorithm :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_SSE_Customer_Key_MD5 :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_SSE_KMS_Key_ID :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_SSE_KMS_Encryption_Context :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_Bucket_Key_Enabled : Optional_Boolean;
      Requested_Create_Request_Payer :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_Checksum_Algorithm :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Create_Checksum_Type :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Session_Server_Side_Encryption :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Session_SSE_KMS_Key_ID :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Session_SSE_KMS_Encryption_Context :
        Ada.Strings.Unbounded.Unbounded_String;
      Requested_Session_Bucket_Key_Enabled : Optional_Boolean;
   end record;

end Flyology.Object_Storage.Client.Low_Level;
