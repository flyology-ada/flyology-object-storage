with Ada.Containers.Vectors;
with Ada.Finalization;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Copies;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Multipart_Uploads;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.Versioning;
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

   function Execute_List_Objects_V2
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome;

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

   function Decode_Put_Object_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Headers    : Put_Object_Result;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Put_Object_Outcome;

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

   function Execute_Delete_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Object_Outcome;

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

   function Execute_Delete_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Delete_Objects_Outcome;

   --  Checksum policy subset of the pinned CreateMultipartUpload input.
   --  Empty algorithm and type preserve AWS's server-selected default.
   type Create_Multipart_Parameters is record
      Content_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Algorithm : Ada.Strings.Unbounded.Unbounded_String;
      Checksum_Type      : Ada.Strings.Unbounded.Unbounded_String;
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

   type Create_Multipart_Outcome
     (Kind : Create_Multipart_Outcome_Kind := Create_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Created =>
            Result : S3.Multipart.Create_Multipart_Upload_Result;
         when Create_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   function Decode_Create_Multipart_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
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

   function Execute_Upload_Part_Copy
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Upload_Part_Copy_Outcome;

   --  Typed core CopyObject parameters. Advanced ACL, tagging, encryption,
   --  lock, and user-metadata members remain available through the exhaustive
   --  generated-model request boundary until their policies are qualified.
   type Copy_Object_Parameters is record
      Copy_Source : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Match : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Modified_Since : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_None_Match : Ada.Strings.Unbounded.Unbounded_String;
      Copy_Source_If_Unmodified_Since :
        Ada.Strings.Unbounded.Unbounded_String;
      Metadata_Directive : Ada.Strings.Unbounded.Unbounded_String;
      Request_Payer : Ada.Strings.Unbounded.Unbounded_String;
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

   function Execute_Copy_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Copy_Object_Outcome;

private
   Maximum_Credential_Bytes : constant := 1_024;
   Maximum_Session_Token_Bytes : constant := 8_192;

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
   end record;

   overriding procedure Finalize (Item : in out Credentials);

   type Operation_Kind is
     (List_Objects_V2_Operation,
      List_Objects_Operation,
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
      Delete_Object_Operation,
      Delete_Objects_Operation,
      Create_Multipart_Operation,
      Complete_Multipart_Operation,
      Abort_Multipart_Operation,
      List_Parts_Operation,
      List_Multipart_Uploads_Operation,
      Upload_Part_Operation,
      Upload_Part_Copy_Operation,
      Copy_Object_Operation);

   type Prepared_Request is record
      Operation : Operation_Kind := List_Objects_V2_Operation;
      Modeled_Operation : S3.Model.Operation_Id :=
        S3.Model.Operation_Id'First;
      Message   : Flyology.HTTP.Client.Request;
      Target_Value    : Ada.Strings.Unbounded.Unbounded_String;
      Authority_Value : Ada.Strings.Unbounded.Unbounded_String;
      Signing   : S3.SigV4.Signing_Result;
   end record;

end Flyology.Object_Storage.Client.Low_Level;
