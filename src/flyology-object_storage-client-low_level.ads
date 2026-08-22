with Ada.Finalization;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Copies;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.SigV4;
with Flyology.Object_Storage.S3.XML;

--  Prepared model-driven S3 operations over a caller-owned Flyology client.
package Flyology.Object_Storage.Client.Low_Level is

   Invalid_Request : exception;

   type Addressing_Style is (Path_Style, Virtual_Hosted_Style);

   type Credentials is limited private;

   function Make_Credentials
     (Access_Key, Secret_Key : String;
      Session_Token         : String := "") return Credentials;

   type List_Objects_V2_Parameters is record
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter          : Ada.Strings.Unbounded.Unbounded_String;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Start_After        : Ada.Strings.Unbounded.Unbounded_String;
      Max_Keys           : S3.Core.Page_Size := 1_000;
      Fetch_Owner        : Boolean := False;
      URL_Encoding       : Boolean := False;
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

   function Prepare_List_Objects_V2
     (Origin      : Flyology.HTTP.Origin;
      Style       : Addressing_Style;
      Bucket      : String;
      Parameters  : List_Objects_V2_Parameters;
      Identity    : Credentials;
      Region      : String;
      Timestamp   : String) return Prepared_Request;

   Invalid_Response : exception;

   type List_Outcome_Kind is (Listed, Rejected);

   type List_Objects_V2_Outcome
     (Kind : List_Outcome_Kind := Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Listed =>
            Listing : S3.Listings.List_Objects_V2_Result;
         when Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   function Decode_List_Objects_V2_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome;

   function Execute_List_Objects_V2
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return List_Objects_V2_Outcome;

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

   function Prepare_Create_Multipart_Upload
     (Origin    : Flyology.HTTP.Origin;
      Style     : Addressing_Style;
      Bucket    : String;
      Key       : String;
      Identity  : Credentials;
      Region    : String;
      Timestamp : String;
      Content_Type : String := "") return Prepared_Request;

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

   type Complete_Multipart_Outcome_Kind is
     (Completed, Complete_Rejected);

   type Complete_Multipart_Outcome
     (Kind : Complete_Multipart_Outcome_Kind := Complete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Completed =>
            Result : S3.Multipart.Complete_Multipart_Upload_Result;
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

   type Abort_Multipart_Outcome_Kind is (Aborted, Abort_Rejected);

   type Abort_Multipart_Outcome
     (Kind : Abort_Multipart_Outcome_Kind := Abort_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Aborted =>
            null;
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

   function Execute_Abort_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Abort_Multipart_Outcome;

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
      Model_Driven_Operation,
      Create_Bucket_Operation,
      Head_Bucket_Operation,
      Delete_Bucket_Operation,
      Delete_Object_Operation,
      Create_Multipart_Operation,
      Complete_Multipart_Operation,
      Abort_Multipart_Operation,
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
