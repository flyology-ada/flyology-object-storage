with Ada.Containers.Indefinite_Vectors;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Streams;
with Flyology.Cancellation;

--  Dispatches an authenticated WriteGetObjectResponse callback to a
--  caller-owned Object Lambda coordinator. The server validates and copies
--  all modeled response controls before calling the provider. Route, token,
--  principal, response, source, cancellation, and deadline values are
--  borrowed only for the synchronous call. Implementations must copy retained
--  values and must not retain or outlive the body source.
--
--  Providers own token authenticity, expiry, route binding, atomic single-use
--  consumption, and delivery to the pending GetObject response. Delivered
--  means that the complete body and response controls reached that caller.
--  Field identity is structurally typed; field values remain exact validated
--  text. Cancellation and timeout propagate; after possible
--  admission their delivery outcome remains provider-reconciled unknown.
--  Other provider exceptions map to an internal error after a best-effort
--  body drain. The server never retries a callback automatically.
package Flyology.Object_Storage.Server.Object_Lambda_Responses is

   --  Presence-preserving body length supplied by the callback.
   --  @field Is_Known Whether the callback supplied Content-Length
   --  @field Bytes Exact body length when known
   type Body_Length (Is_Known : Boolean := False) is record
      case Is_Known is
         when False =>
            null;
         when True =>
            Bytes : Byte_Count;
      end case;
   end record;

   --  Presence-preserving exact modeled header value.
   --  @field Is_Set Whether the modeled field was supplied
   --  @field Value Exact validated field value when supplied
   type Optional_Text is record
      Is_Set : Boolean := False;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Modeled GetObject response control carried by the callback.
   --  @enum Status_Code Forwarded HTTP status
   --  @enum Error_Code Forwarded S3 error code
   --  @enum Error_Message Forwarded S3 error message
   --  @enum Accept_Ranges Forwarded Accept-Ranges value
   --  @enum Cache_Control Forwarded Cache-Control value
   --  @enum Content_Disposition Forwarded Content-Disposition value
   --  @enum Content_Encoding Forwarded Content-Encoding value
   --  @enum Content_Language Forwarded Content-Language value
   --  @enum Content_Range Forwarded Content-Range value
   --  @enum Content_Type Forwarded Content-Type value
   --  @enum Checksum_CRC32 Forwarded CRC32 checksum
   --  @enum Checksum_CRC32C Forwarded CRC32C checksum
   --  @enum Checksum_CRC64NVME Forwarded CRC64NVME checksum
   --  @enum Checksum_SHA1 Forwarded SHA1 checksum
   --  @enum Checksum_SHA256 Forwarded SHA256 checksum
   --  @enum Checksum_SHA512 Forwarded SHA512 checksum
   --  @enum Checksum_MD5 Forwarded MD5 checksum
   --  @enum Checksum_XXHASH64 Forwarded XXHASH64 checksum
   --  @enum Checksum_XXHASH3 Forwarded XXHASH3 checksum
   --  @enum Checksum_XXHASH128 Forwarded XXHASH128 checksum
   --  @enum Delete_Marker Forwarded delete-marker state
   --  @enum Entity_Tag Forwarded entity tag
   --  @enum Expires Forwarded cache expiry timestamp
   --  @enum Expiration Forwarded lifecycle expiration value
   --  @enum Last_Modified Forwarded modification timestamp
   --  @enum Missing_Metadata Forwarded missing-metadata count
   --  @enum Object_Lock_Mode Forwarded Object Lock mode
   --  @enum Object_Lock_Legal_Hold Forwarded legal-hold state
   --  @enum Object_Lock_Retain_Until Forwarded retention timestamp
   --  @enum Parts_Count Forwarded multipart count
   --  @enum Replication_Status Forwarded replication state
   --  @enum Request_Charged Forwarded requester-charged state
   --  @enum Restore Forwarded restore state
   --  @enum Server_Side_Encryption Forwarded encryption algorithm
   --  @enum SSE_Customer_Algorithm Forwarded SSE-C algorithm
   --  @enum SSE_KMS_Key_ID Forwarded sensitive KMS key identifier
   --  @enum SSE_Customer_Key_MD5 Forwarded SSE-C key digest
   --  @enum Storage_Class Forwarded storage class
   --  @enum Tag_Count Forwarded tag count
   --  @enum Version_ID Forwarded object version identifier
   --  @enum Bucket_Key_Enabled Forwarded bucket-key state
   type Forwarded_Field is
     (Status_Code,
      Error_Code,
      Error_Message,
      Accept_Ranges,
      Cache_Control,
      Content_Disposition,
      Content_Encoding,
      Content_Language,
      Content_Range,
      Content_Type,
      Checksum_CRC32,
      Checksum_CRC32C,
      Checksum_CRC64NVME,
      Checksum_SHA1,
      Checksum_SHA256,
      Checksum_SHA512,
      Checksum_MD5,
      Checksum_XXHASH64,
      Checksum_XXHASH3,
      Checksum_XXHASH128,
      Delete_Marker,
      Entity_Tag,
      Expires,
      Expiration,
      Last_Modified,
      Missing_Metadata,
      Object_Lock_Mode,
      Object_Lock_Legal_Hold,
      Object_Lock_Retain_Until,
      Parts_Count,
      Replication_Status,
      Request_Charged,
      Restore,
      Server_Side_Encryption,
      SSE_Customer_Algorithm,
      SSE_KMS_Key_ID,
      SSE_Customer_Key_MD5,
      Storage_Class,
      Tag_Count,
      Version_ID,
      Bucket_Key_Enabled);

   --  Presence-preserving complete modeled control set.
   type Forwarded_Field_Set is array (Forwarded_Field) of Optional_Text;

   --  One exact user metadata association without the x-amz-meta prefix.
   --  @field Name Exact validated metadata name
   --  @field Value Exact validated metadata value
   type Metadata_Entry is record
      Name  : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Ordered caller-supplied user metadata associations.
   package Metadata_Entry_Vectors is new Ada.Containers.Indefinite_Vectors
     (Index_Type => Positive, Element_Type => Metadata_Entry);

   --  Complete validated response description and streaming body length.
   --  @field Content_Length Presence-preserving request and response length
   --  @field Fields Complete modeled non-metadata response controls
   --  @field Metadata Ordered case-fold-unique user metadata
   type Response_Description is record
      Content_Length : Body_Length := (Is_Known => False);
      Fields          : Forwarded_Field_Set := (others => <>);
      Metadata        : Metadata_Entry_Vectors.Vector;
   end record;

   --  Terminal outcome of one synchronous callback dispatch.
   --  @enum Delivered Complete response reached the pending GetObject caller
   --  @enum Invalid_Token Token was rejected before consumption, pending
   --  response admission, and any body read
   --  @enum Delivery_Failed Delivery did not complete and its outcome is
   --  unknown; the server does not retry the single-use token
   type Delivery_Result is (Delivered, Invalid_Token, Delivery_Failed);

   --  Caller-owned Object Lambda callback dispatcher. Implementations must be
   --  safe for concurrent calls made by the bound server application.
   type Provider is limited interface;

   --  Caller-owned provider reference borrowed by one server application.
   --  The object must remain alive until every application request finishes.
   type Provider_Access is access all Provider'Class;

   --  Non-rewindable response body borrowed for one synchronous dispatch.
   type Response_Body_Source is limited interface;

   --  Produce the next response bytes or report completion.
   --  @param Item Borrowed response body source
   --  @param Data Caller-owned destination buffer
   --  @param Last Last produced element or before Data'First when empty
   --  @param Finished Whether the source reached EOF
   --  @param Cancellation Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   procedure Read
     (Item         : in out Response_Body_Source;
      Data         : out Ada.Streams.Stream_Element_Array;
      Last         : out Ada.Streams.Stream_Element_Offset;
      Finished     : out Boolean;
      Cancellation : access Flyology.Cancellation.Token;
      Deadline     : Ada.Real_Time.Time) is abstract;

   --  Deliver one authenticated callback to its pending GetObject response.
   --  The provider must atomically consume a valid token and read Body through
   --  EOF before returning Delivered. It may not retain borrowed inputs or
   --  allow a task using them to outlive this call. Invalid_Token may be
   --  returned only before token consumption, pending-response admission, and
   --  any Source read. Cancellation or timeout propagates without retry; when
   --  admission may have occurred, the provider owns reconciliation.
   --  @param Item Provider dispatching the callback
   --  @param Principal Borrowed authenticated tenant principal
   --  @param Request_Route Borrowed exact validated routing value
   --  @param Request_Token Borrowed exact opaque single-use token
   --  @param Response Borrowed complete validated response controls
   --  @param Source Borrowed transformed response body pull source
   --  @param Cancellation Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Complete terminal delivery outcome
   procedure Deliver
     (Item          : in out Provider;
      Principal     : String;
      Request_Route : String;
      Request_Token : String;
      Response      : Response_Description;
      Source        : in out Response_Body_Source'Class;
      Cancellation  : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Delivery_Result) is abstract;

end Flyology.Object_Storage.Server.Object_Lambda_Responses;
