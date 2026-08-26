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
with Flyology.Object_Storage.S3.Copies;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Encryption;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;

--  Prepared model-driven S3 operations over a caller-owned Flyology client.
package Flyology.Object_Storage.Client.Low_Level is

   Invalid_Request : exception;

   type Addressing_Style is (Path_Style, Virtual_Hosted_Style);

   type Credentials is limited private;

   function Make_Credentials
     (Access_Key, Secret_Key : String;
      Session_Token         : String := "") return Credentials;

   --  Every non-bucket member in the pinned ListObjects v1 input shape.
   --  Include_Restore_Status represents the model's sole
   --  OptionalObjectAttributes list value, RestoreStatus.
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

   type Prepared_Request is private;

   --  Optional boolean wire value that preserves absent versus explicit false.
   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Optional nonnegative 64-bit byte count.
   type Optional_Byte_Count is record
      Is_Set : Boolean := False;
      Value  : Byte_Count := 0;
   end record;

   type Optional_Natural is record
      Is_Set : Boolean := False;
      Value  : Natural := 0;
   end record;

   type Optional_Part_Number is record
      Is_Set : Boolean := False;
      Value  : S3.Core.Part_Number := S3.Core.Part_Number'First;
   end record;

   function Target (Item : Prepared_Request) return String;
   function Authority (Item : Prepared_Request) return String;
   function Canonical_Request (Item : Prepared_Request) return String;
   function Signed_Headers (Item : Prepared_Request) return String;

   --  One top-level member supplied to the generated model-driven request
   --  projector. Map_Key is used only by `headers` map members such as S3
   --  user metadata. Body members are represented by the raw REST/XML
   --  payload parameters of Prepare_Model_Request.
   type Model_Value is record
      Member_Name : Ada.Strings.Unbounded.Unbounded_String;
      Map_Key     : Ada.Strings.Unbounded.Unbounded_String;
      Value       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Model_Value_Array is array (Positive range <>) of Model_Value;

   No_Model_Values : constant Model_Value_Array (1 .. 0) :=
     (others => <>);

   --  Prepare any operation in the pinned 116-operation S3 model. The
   --  projector validates member names, locations, required top-level
   --  members, duplicate scalar members, header-map keys, addressing, and
   --  the signed payload hash. Structured body serialization remains a
   --  separate codec concern; Payload_Is_Set distinguishes an absent body
   --  from an explicitly empty REST/XML or blob payload.
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

   function Prepare_List_Objects
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request;

   Invalid_Response : exception;

   type List_Outcome_Kind is (Listed, Rejected);

   --  Every member in the pinned ListObjects v1 output shape. The XML
   --  members are grouped in Listing; RequestCharged is an HTTP header.
   type List_Objects_Result is record
      Listing         : S3.Listings.List_Objects_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

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

   function Execute_List_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_Outcome;

   function Prepare_List_Objects_V2
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_V2_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request;

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
   type List_Object_Versions_Result is record
      Listing         : S3.Versions.List_Object_Versions_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

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
   type List_Buckets_Parameters is record
      Max_Buckets        : S3.Buckets.Max_Buckets_Value := 10_000;
      Has_Max_Buckets    : Boolean := False;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix         : Boolean := False;
      Bucket_Region      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_List_Buckets
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Parameters : List_Buckets_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type List_Buckets_Outcome_Kind is
     (Buckets_Listed, List_Buckets_Rejected);

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

   function Execute_List_Buckets
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Buckets_Outcome;

   --  Every input member in the pinned CreateBucket request shape.
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

   function Prepare_Create_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Create_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every output member in the pinned CreateBucket response shape.
   type Create_Bucket_Result is record
      Location   : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_ARN : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Create_Bucket_Outcome_Kind is
     (Bucket_Created, Create_Bucket_Rejected);

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

   function Execute_Create_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Bucket_Outcome;

   type Get_Bucket_Location_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Get_Bucket_Location
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Location_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Get_Bucket_Location_Result is record
      Location_Constraint : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Get_Bucket_Location_Outcome_Kind is
     (Bucket_Location_Found, Get_Bucket_Location_Rejected);

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

   function Decode_Get_Bucket_Location_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Location_Outcome;

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
   type Put_Bucket_Tagging_Parameters is record
      Content_MD5            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm     : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner  : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Put_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Value      : Tags.Tag_Set;
      Parameters : Put_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Put_Bucket_Tagging_Result is record
      --  Retained for source compatibility. PutBucketTagging has no modeled
      --  request-charging output and a nonempty response value is rejected.
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Put_Bucket_Tagging_Outcome_Kind is
     (Bucket_Tags_Replaced, Put_Bucket_Tagging_Rejected);

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

   function Decode_Put_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Bucket_Tagging_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Tagging_Outcome;

   function Execute_Put_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Tagging_Outcome;

   type Get_Bucket_Tagging_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      --  Retained for source compatibility; any nonempty value is rejected.
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Get_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Get_Bucket_Tagging_Result is record
      Value           : Tags.Tag_Set;
      --  Retained for source compatibility. GetBucketTagging has no modeled
      --  request-charging output and a nonempty response value is rejected.
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Get_Bucket_Tagging_Outcome_Kind is
     (Bucket_Tags_Found, Get_Bucket_Tagging_Rejected);

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

   function Decode_Get_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Get_Bucket_Tagging_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Tagging_Outcome;

   function Execute_Get_Bucket_Tagging
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Tagging_Outcome;

   type Delete_Bucket_Tagging_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Delete_Bucket_Tagging
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_Tagging_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Delete_Bucket_Tagging_Outcome_Kind is
     (Bucket_Tags_Deleted, Delete_Bucket_Tagging_Rejected);

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

   function Decode_Delete_Bucket_Tagging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Tagging_Outcome;

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
   type Put_Bucket_Versioning_Parameters is record
      Content_MD5          : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm   : Ada.Strings.Unbounded.Unbounded_String;
      MFA                  : Ada.Strings.Unbounded.Unbounded_String;
      Configuration        : Bucket_Versioning_Configuration;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Put_Bucket_Versioning
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Put_Bucket_Versioning_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Put_Bucket_Versioning_Outcome_Kind is
     (Bucket_Versioning_Updated, Put_Bucket_Versioning_Rejected);

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

   function Decode_Put_Bucket_Versioning_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Put_Bucket_Versioning_Outcome;

   function Execute_Put_Bucket_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Put_Bucket_Versioning_Outcome;

   type Get_Bucket_Versioning_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Get_Bucket_Versioning
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Get_Bucket_Versioning_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Get_Bucket_Versioning_Outcome_Kind is
     (Bucket_Versioning_Found, Get_Bucket_Versioning_Rejected);

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

   function Decode_Get_Bucket_Versioning_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Get_Bucket_Versioning_Outcome;

   function Execute_Get_Bucket_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.Versioning.Default_Limits)
      return Get_Bucket_Versioning_Outcome;

   type Head_Bucket_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Head_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Head_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   --  Every output member in the pinned HeadBucket response shape.
   type Head_Bucket_Result is record
      Bucket_ARN           : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Location_Type : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Location_Name : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region        : Ada.Strings.Unbounded.Unbounded_String;
      Access_Point_Alias   : Optional_Boolean;
   end record;

   type Head_Bucket_Outcome_Kind is
     (Bucket_Found, Head_Bucket_Rejected);

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

   function Execute_Head_Bucket
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Outcome;

   --  Every input member in the pinned HeadObject request shape.
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

   function Prepare_Head_Object
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Head_Object_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Metadata_Entry is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Metadata_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Metadata_Entry);

   --  Every output member in the pinned HeadObject response shape.
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

   type Head_Object_Outcome_Kind is
     (Object_Found, Head_Object_Rejected);

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

   function Execute_Head_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Object_Outcome;

   --  GetObject has the same 21 modeled request members as HeadObject.
   subtype Get_Object_Parameters is Head_Object_Parameters;

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

   type Get_Object_Head_Outcome_Kind is
     (Object_Opened, Get_Object_Rejected);

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

   --  Terminal interpretation of a GetObjectTorrent response head.
   --  @enum Torrent_Opened Exact 200 response with an unread streaming body
   --  @enum Get_Object_Torrent_Rejected Bounded non-200 S3 rejection
   type Get_Object_Torrent_Outcome_Kind is
     (Torrent_Opened, Get_Object_Torrent_Rejected);

   --  Typed response head.  Torrent_Opened deliberately carries no body:
   --  the caller consumes the still-open limited HTTP response incrementally.
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
   type Get_Object_Attributes_Result is record
      Delete_Marker   : Optional_Boolean;
      Last_Modified   : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
      Attributes      : S3.Attributes.Get_Object_Attributes_Result;
   end record;

   type Get_Object_Attributes_Outcome_Kind is
     (Object_Attributes_Found, Get_Object_Attributes_Rejected);

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

   --  Execute a matching typed request, bound the complete response body,
   --  and decode every modeled output member.
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

   type Put_Object_Outcome_Kind is (Object_Put, Put_Object_Rejected);

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
   function Execute_Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome;

   --  Modeled DeleteBucket request headers.
   type Delete_Bucket_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Delete_Bucket
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Delete_Bucket_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Delete_Bucket_Outcome_Kind is
     (Bucket_Deleted, Delete_Bucket_Rejected);

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

   function Decode_Delete_Bucket_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Outcome;

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
   Configuration_Deleted : constant
     Delete_Bucket_Configuration_Outcome_Kind := Bucket_CORS_Deleted;
   Delete_Configuration_Rejected : constant
     Delete_Bucket_Configuration_Outcome_Kind :=
       Delete_Bucket_CORS_Rejected;
   subtype Delete_Bucket_Configuration_Outcome is
     Delete_Bucket_CORS_Outcome;

   --  Decode the common generated 204/no-output response shape.
   function Decode_Delete_Bucket_Configuration_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;

   --  DeleteBucketCors uses the common bodyless configuration response.
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
   function Prepare_Delete_Bucket_Analytics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketEncryption request.
   function Prepare_Delete_Bucket_Encryption
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketIntelligentTieringConfiguration
   --  request.
   function Prepare_Delete_Bucket_Intelligent_Tiering_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketInventoryConfiguration request.
   function Prepare_Delete_Bucket_Inventory_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketLifecycle request.
   function Prepare_Delete_Bucket_Lifecycle
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketMetadataConfiguration request.
   function Prepare_Delete_Bucket_Metadata_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketMetadataTableConfiguration
   --  request.
   function Prepare_Delete_Bucket_Metadata_Table_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketMetricsConfiguration request.
   function Prepare_Delete_Bucket_Metrics_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String;
      Parameters : Delete_Bucket_Configuration_With_ID_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketOwnershipControls request.
   function Prepare_Delete_Bucket_Ownership_Controls
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketPolicy request.
   function Prepare_Delete_Bucket_Policy
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketReplication request.
   function Prepare_Delete_Bucket_Replication
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeleteBucketWebsite request.
   function Prepare_Delete_Bucket_Website
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Build and sign one exact DeletePublicAccessBlock request.
   function Prepare_Delete_Public_Access_Block
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Delete_Bucket_Configuration_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Execute one exact prepared DeleteBucketAnalyticsConfiguration request.
   function Execute_Delete_Bucket_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketEncryption request.
   function Execute_Delete_Bucket_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketIntelligentTieringConfiguration
   --  request.
   function Execute_Delete_Bucket_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketInventoryConfiguration request.
   function Execute_Delete_Bucket_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketLifecycle request.
   function Execute_Delete_Bucket_Lifecycle
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketMetadataConfiguration request.
   function Execute_Delete_Bucket_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketMetadataTableConfiguration
   --  request.
   function Execute_Delete_Bucket_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketMetricsConfiguration request.
   function Execute_Delete_Bucket_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketOwnershipControls request.
   function Execute_Delete_Bucket_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketPolicy request.
   function Execute_Delete_Bucket_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketReplication request.
   function Execute_Delete_Bucket_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeleteBucketWebsite request.
   function Execute_Delete_Bucket_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Bucket_Configuration_Outcome;
   --  Execute one exact prepared DeletePublicAccessBlock request.
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

   --  Complete GetBucketAccelerateConfiguration request parameters.
   --  @field Expected_Bucket_Owner Optional exact owner precondition
   --  @field Request_Payer Optional exact requester-pays admission value
   type Get_Bucket_Accelerate_Parameters is record
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Prepare one exactly bound GetBucketAccelerateConfiguration request.
   function Prepare_Get_Bucket_Accelerate_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Accelerate_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketAbac request.
   function Prepare_Get_Bucket_Abac
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketPolicy request.
   function Prepare_Get_Bucket_Policy
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketPolicyStatus request.
   function Prepare_Get_Bucket_Policy_Status
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketRequestPayment request.
   function Prepare_Get_Bucket_Request_Payment
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetPublicAccessBlock request.
   function Prepare_Get_Public_Access_Block
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Parameters : Get_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;
   --  Prepare one exactly bound GetBucketOwnershipControls request.
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
   function Decode_Get_Bucket_Accelerate_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Request_Charged : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Accelerate_Outcome;
   --  Decode one complete bounded GetBucketAbac XML response.
   function Decode_Get_Bucket_Abac_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Abac_Outcome;
   --  Decode one complete bounded raw GetBucketPolicy response.
   function Decode_Get_Bucket_Policy_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Outcome;
   --  Decode one complete bounded GetBucketPolicyStatus XML response.
   function Decode_Get_Bucket_Policy_Status_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Status_Outcome;
   --  Decode one complete bounded GetBucketRequestPayment XML response.
   function Decode_Get_Bucket_Request_Payment_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Request_Payment_Outcome;
   --  Decode one complete bounded GetPublicAccessBlock XML response.
   function Decode_Get_Public_Access_Block_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Public_Access_Block_Outcome;
   --  Decode one complete bounded GetBucketOwnershipControls response.
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
   function Execute_Get_Bucket_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Accelerate_Outcome;
   --  Execute one exact prepared GetBucketAbac request.
   function Execute_Get_Bucket_Abac
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Abac_Outcome;
   --  Execute one exact prepared GetBucketPolicy request.
   function Execute_Get_Bucket_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Outcome;
   --  Execute one exact prepared GetBucketPolicyStatus request.
   function Execute_Get_Bucket_Policy_Status
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Policy_Status_Outcome;
   --  Execute one exact prepared GetBucketRequestPayment request.
   function Execute_Get_Bucket_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Bucket_Request_Payment_Outcome;
   --  Execute one exact prepared GetPublicAccessBlock request.
   function Execute_Get_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Get_Public_Access_Block_Outcome;
   --  Execute one exact prepared GetBucketOwnershipControls request.
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
   function Prepare_Put_Bucket_Abac
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Value : S3.Bucket_Controls.Abac_Status;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutBucketAccelerateConfiguration request.
   function Prepare_Put_Bucket_Accelerate_Configuration
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Value : S3.Bucket_Controls.Accelerate_Status;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutBucketRequestPayment request.
   function Prepare_Put_Bucket_Request_Payment
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Value : S3.Bucket_Controls.Payer;
      Parameters : Put_Bucket_Control_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   --  Prepare one exact PutPublicAccessBlock request.
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

   type Put_Bucket_Control_Outcome_Kind is
     (Bucket_Control_Updated, Put_Bucket_Control_Rejected);

   --  Terminal result shared by body-only bucket-control updates.
   --  Existing API-policy classification: 500 is the aggregate sentinel;
   --  decoded outcomes preserve the physical status.
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

   --  Decode one bounded bodyless bucket-control mutation response.
   function Decode_Put_Bucket_Control_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

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
   function Execute_Put_Bucket_Abac
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;
   --  Execute one exact prepared PutBucketAccelerateConfiguration request.
   function Execute_Put_Bucket_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;
   --  Execute one exact prepared PutBucketRequestPayment request.
   function Execute_Put_Bucket_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;
   --  Execute one exact prepared PutPublicAccessBlock request.
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
   function Prepare_Put_Bucket_Policy
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket : String; Policy : String;
      Parameters : Put_Bucket_Policy_Parameters;
      Identity : Credentials; Region, Timestamp : String;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Prepared_Request;

   --  Execute one exact prepared PutBucketPolicy request.
   function Execute_Put_Bucket_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Bucket_Control_Outcome;

   --  Every input member in the pinned DeleteObject request shape.
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
   type Delete_Object_Result is record
      Delete_Marker   : Optional_Boolean;
      Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Delete_Object_Outcome_Kind is
     (Object_Deleted, Delete_Object_Rejected);

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

   --  Complete modeled inputs for the three object-tagging operations.
   type Put_Object_Tagging_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm    : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Get_Object_Tagging_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer         : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Delete_Object_Tagging_Parameters is record
      Version_ID            : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Put_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Tags : Object_Tag_Set;
      Parameters : Put_Object_Tagging_Parameters; Identity : Credentials;
      Region, Timestamp : String) return Prepared_Request;

   function Prepare_Get_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : Get_Object_Tagging_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   function Prepare_Delete_Object_Tagging
     (Origin : Flyology.HTTP.Origin; Style : Addressing_Style;
      Bucket, Key : String; Parameters : Delete_Object_Tagging_Parameters;
      Identity : Credentials; Region, Timestamp : String)
      return Prepared_Request;

   type Object_Tagging_Result is record
      Tags       : Object_Tag_Set;
      Version_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Object_Tagging_Outcome_Kind is
     (Tags_Put, Tags_Gotten, Tags_Deleted, Object_Tagging_Rejected);

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

   function Execute_Put_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

   function Execute_Get_Object_Tagging
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Object_Tagging_Outcome;

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
   type Delete_Objects_Parameters is record
      MFA                         : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer               : Ada.Strings.Unbounded.Unbounded_String;
      Bypass_Governance_Retention : Optional_Boolean;
      Expected_Bucket_Owner       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   function Prepare_Delete_Objects
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Request    : S3.Deletions.Delete_Objects_Request;
      Parameters : Delete_Objects_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Delete_Objects_Result is record
      Result          : S3.Deletions.Delete_Objects_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Delete_Objects_Outcome_Kind is
     (Objects_Deleted, Delete_Objects_Rejected);

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
   type Create_Session_Parameters is record
      Session_Mode               : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID              : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
   end record;

   function Prepare_Create_Session
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Parameters : Create_Session_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

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
   type Create_Session_Result is limited record
      Server_Side_Encryption     : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID              : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Encryption_Context : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled         : Optional_Boolean;
      Identity                   : Credentials;
      Expiration                 : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Create_Session_Outcome_Kind is
     (Session_Created, Create_Session_Rejected);

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

   function Decode_Create_Session_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Create_Session_Response_Headers := (others => <>);
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Session_Outcome;

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
   function Prepare_Create_Multipart_Upload
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Create_Multipart_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

   type Create_Multipart_Outcome_Kind is (Created, Create_Rejected);

   --  Every member in the pinned CreateMultipartUpload output shape.
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

   type Complete_Multipart_Response_Headers is record
      Expiration             : Ada.Strings.Unbounded.Unbounded_String;
      Server_Side_Encryption : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
      SSE_KMS_Key_ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Key_Enabled     : Optional_Boolean;
      Request_Charged        : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Complete_Multipart_Outcome_Kind is
     (Completed, Complete_Rejected);

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

   function Decode_Complete_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Complete_Multipart_Response_Headers;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome;

   function Execute_Complete_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Complete_Multipart_Outcome;

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
   type Abort_Multipart_Parameters is record
      Request_Payer           : Ada.Strings.Unbounded.Unbounded_String;
      Expected_Bucket_Owner   : Ada.Strings.Unbounded.Unbounded_String;
      If_Match_Initiated_Time : Ada.Strings.Unbounded.Unbounded_String;
   end record;

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
   type Abort_Multipart_Result is record
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Abort_Multipart_Outcome_Kind is (Aborted, Abort_Rejected);

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

   function Decode_Abort_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

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

   function Execute_Abort_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

   --  Every non-resource member in the pinned ListParts input shape.
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
   type List_Parts_Result is record
      Listing         : S3.Multipart.List_Parts_Result;
      Abort_Date      : Ada.Strings.Unbounded.Unbounded_String;
      Abort_Rule_ID   : Ada.Strings.Unbounded.Unbounded_String;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type List_Parts_Outcome_Kind is (Parts_Listed, List_Parts_Rejected);

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
   type List_Multipart_Uploads_Result is record
      Listing : S3.Multipart_Uploads.List_Multipart_Uploads_Result;
      Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type List_Multipart_Uploads_Outcome_Kind is
     (Multipart_Uploads_Listed, List_Multipart_Uploads_Rejected);

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

   function Execute_List_Multipart_Uploads
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Multipart_Uploads_Outcome;

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

   function Prepare_Upload_Part
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Upload_Part_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

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

   type Upload_Part_Outcome_Kind is (Part_Uploaded, Upload_Rejected);

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
   function Execute_Upload_Part
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Outcome;

   type Optional_Copy_Source_Range is record
      Is_Set : Boolean := False;
      First  : Byte_Count := 0;
      Last   : Byte_Count := 0;
   end record;

   --  Every modeled UploadPartCopy request member. Copy_Source is the exact
   --  x-amz-copy-source value, including any caller-selected version query.
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

   function Prepare_Upload_Part_Copy
     (Origin     : Flyology.HTTP.Origin;
      Style      : Addressing_Style;
      Bucket     : String;
      Key        : String;
      Parameters : Upload_Part_Copy_Parameters;
      Identity   : Credentials;
      Region     : String;
      Timestamp  : String) return Prepared_Request;

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

   type Upload_Part_Copy_Outcome_Kind is
     (Part_Copied, Copy_Part_Rejected);

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

   function Execute_Upload_Part_Copy
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome;

   --  Every modeled CopyObject request member other than the destination
   --  bucket and key, which are explicit Prepare_Copy_Object parameters.
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

   type Copy_Object_Outcome_Kind is (Object_Copied, Copy_Object_Rejected);

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
   function Owned_Payload_Length
     (Prepared : Prepared_Request) return Natural;

   --  @exclude
   function Owned_Payload_Element
     (Prepared : Prepared_Request;
      Index    : Positive) return Character;

   --  Start a prepared PutObject exchange in an established HTTP operation.
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
   procedure Get_Object
     (Client      : not null access Flyology.HTTP.Client.Client;
      Prepared    : not null access constant Prepared_Request;
      Destination : in out Flyology.Buffers.Unique_Buffer;
      Deadline    : Flyology.HTTP.Client.Monotonic_Deadline;
      Token       : access Flyology.Cancellation.Token := null;
      Operation   : in out Flyology.HTTP.Client.Exchange_Operation)
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Start a prepared ListObjects v1 exchange into a bounded sink.
   procedure List_Objects
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared service-level ListBuckets exchange.
   procedure List_Buckets
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared CreateBucket exchange with its one-shot body source.
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
   procedure List_Objects_V2
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListObjectVersions exchange into a bounded sink.
   procedure List_Object_Versions
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared GetObjectAttributes exchange into a bounded sink.
   procedure Get_Object_Attributes
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared HeadObject exchange into a bodyless sink.
   procedure Head_Object
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteObject exchange without replaying its source.
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
   procedure List_Parts
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared ListMultipartUploads exchange into a bounded sink.
   procedure List_Multipart_Uploads
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared CopyObject exchange without replaying its source.
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
   procedure Get_Object_Tagging
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Start a prepared DeleteObjectTagging exchange.
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

private
   Maximum_Credential_Bytes : constant := 1_024;
   Maximum_Session_Token_Bytes : constant := 8_192;

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
