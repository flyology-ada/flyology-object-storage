with Ada.Strings.Unbounded;
with Flyology.Buffers;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Scoped;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Multipart;

--  Defines bounded multi-subject transfer policy shared by convenience client
--  operations. The execution implementation uses structured Flyology tasks.
package Flyology.Object_Storage.Client.Transfers is

   Minimum_Multipart_Part_Size : constant Byte_Count :=
     Flyology.Object_Storage.S3.Core.Minimum_Part_Size;
   Maximum_Multipart_Part_Size : constant Byte_Count :=
     Flyology.Object_Storage.S3.Core.Maximum_Part_Size;
   Default_Multipart_Threshold : constant Byte_Count := 64 * 1_024 * 1_024;
   Default_Multipart_Part_Size : constant Byte_Count := 16 * 1_024 * 1_024;

   package Checksum_Policy renames
     Flyology.Object_Storage.S3.Checksum_Policy;

   --  Optional explicit upload checksum policy. Disabled preserves the
   --  service default; enabled selections are validated before network I/O.
   type Upload_Checksum_Selection is record
      Enabled   : Boolean := False;
      Algorithm : Checksum_Policy.Algorithm :=
        Checksum_Policy.Core.CRC64NVME;
      Kind      : Checksum_Policy.Checksum_Type :=
        Checksum_Policy.Full_Object;
   end record;

   Default_Upload_Checksum : constant Upload_Checksum_Selection :=
     (others => <>);

   --  Execute CreateMultipartUpload by waiting on the composable operation.
   --  This result-type overload preserves HTTP admission and upload-creation
   --  certainty. Selecting the established low-level outcome overload retains
   --  its raising transport contract. Parameters and defaults are identical.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Parameters Complete modeled initiation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed upload-creation certainty and terminal response or failure
   function Create_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Create_Multipart_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Scoped.Create_Multipart_Result;

   --  Create one multipart upload through the synchronous no-body path.
   --  Parameters exposes all non-resource members in the pinned input shape;
   --  the result preserves all modeled body and response-header members and
   --  is rejected unless its bucket, key, encryption, payer, and explicit
   --  checksum policy are coherent with the prepared request. This operation
   --  is never transparently retried. Invalid_Request raised before HTTP
   --  admission is definite non-creation; every exception after Execute is
   --  entered is ambiguous and must be reconciled with ListMultipartUploads.
   function Create_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Create_Multipart_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.Create_Multipart_Outcome;

   --  Abort one multipart upload by waiting on the composable owner-driven
   --  one-shot operation. This result-type overload preserves admission and
   --  abort certainty. Selecting the established low-level outcome overload
   --  retains its raising transport contract; parameters and defaults match.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param If_Match_Initiated_Time Optional RFC 822 initiation predicate
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed abort certainty and terminal response or failure
   function Abort_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Request_Payer : String := "";
      Expected_Bucket_Owner : String := "";
      If_Match_Initiated_Time : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Scoped.Multipart_Abort_Result;

   --  Abort one active multipart upload without constructing a modeled
   --  request record. Optional advanced members map directly to the pinned
   --  S3 input shape; If_Match_Initiated_Time is an RFC 822 HTTP date.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param If_Match_Initiated_Time Optional RFC 822 initiation predicate
   --  @param Timeout Whole synchronous operation budget
   --  @param Token Optional cancellation source
   --  @return Modeled abort success or S3 rejection
   function Abort_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Request_Payer : String := "";
      Expected_Bucket_Owner : String := "";
      If_Match_Initiated_Time : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.Abort_Multipart_Outcome;

   --  Fetch one bounded ListParts page by waiting on the composable
   --  owner-driven operation. This result-type overload preserves typed HTTP
   --  failure and admission information; selecting the established low-level
   --  outcome overload retains its raising transport contract.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Source S3 bucket
   --  @param Key Source S3 object key
   --  @param Parameters Exact upload, cursor, page bound, and access controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function List_Parts_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.List_Parts_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Scoped.List_Parts_Result;

   --  Fetch one bounded ListParts page. Parameters carries the exact upload
   --  ID, marker, maximum, payer, owner and SSE-C scope. A truncated result's
   --  Next_Part_Number_Marker may be supplied as the next call's marker, but
   --  separate calls do not share a service snapshot. The response is
   --  rejected unless its echoed bucket, key, upload ID, marker and maximum
   --  match this request exactly.
   function List_Parts_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.List_Parts_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.List_Parts_Outcome;

   --  Fetch one bounded ListMultipartUploads page by waiting on the
   --  composable owner-driven operation. Key_Marker and Upload_ID_Marker form
   --  one cursor and separate calls do not share a service snapshot. This
   --  result-type overload preserves typed HTTP failure and admission data.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Source S3 bucket
   --  @param Parameters Exact listing scope and paired continuation cursor
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function List_Multipart_Uploads_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Parameters   : Low_Level.List_Multipart_Uploads_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Scoped.List_Multipart_Uploads_Result;

   --  Fetch one bounded ListMultipartUploads page through the established
   --  raising transport contract. The paired cursor must advance together,
   --  and every echoed scope and cursor field must match the exact request.
   function List_Multipart_Uploads_Page
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Parameters   : Low_Level.List_Multipart_Uploads_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.List_Multipart_Uploads_Outcome;

   --  Upload one multipart part through the synchronous one-shot path. The
   --  source is borrowed only until this call returns and must not implement
   --  Rewindable_Request_Body_Source; UploadPart is never transparently
   --  replayed after possible service admission. Parameters exposes every
   --  modeled UploadPart control and the result preserves all 17 modeled
   --  response headers. Invalid_Request raised by this wrapper occurs before
   --  HTTP admission. Every other exception is conservatively publication-
   --  ambiguous because it may follow service admission, including an
   --  Invalid_Response raised while validating the reply. Reconcile the exact
   --  UploadId and PartNumber with ListParts before retrying or completing the
   --  upload.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign the request
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Parameters Complete typed UploadPart controls
   --  @param Source Borrowed forward-only request body source
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole synchronous request budget
   --  @param Token Optional cancellation source
   --  @return Typed UploadPart success or S3 rejection
   --  @exception Low_Level.Invalid_Request if Source is rewindable or any
   --     modeled request member is invalid; this exception is pre-admission
   function Upload_Part
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Upload_Part_Parameters;
      Source       : in out
        Flyology.HTTP.Client.Request_Body_Source'Class;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Low_Level.Upload_Part_Outcome;

   --  Upload one bounded multipart part by waiting on the composable
   --  owner-driven operation. Payload_Buffer ownership moves during the call
   --  and the exact token is restored before return or re-raising an
   --  unexpected provider exception. The result preserves admission and
   --  publication certainty; no request is replayed.
   --  Region, Style, Timeout, and Token defaults are deliberately identical
   --  to the established borrowed-source overload above; changing either
   --  overload independently would be a compatibility break.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign the request
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Parameters Complete typed UploadPart controls
   --  @param Payload_Buffer Acquired complete part bytes restored on return
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed part-publication certainty and terminal response
   function Upload_Part
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Parameters   : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Scoped.Upload_Part_Result
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Complete one multipart upload by waiting on the composable owner-driven
   --  one-shot operation. The exact serialized XML is never replayed. The
   --  typed result preserves admission and publication certainty; unknown
   --  outcomes require read-only destination/upload reconciliation.
   --  Region, Style, Timeout, and Token retain the established transfer API
   --  defaults so synchronous and directly composed requests are identical.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign the request
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Completion Ordered completed-part request
   --  @param Parameters Complete modeled completion controls
   --  @param Identity Credentials borrowed only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed completion-publication certainty and terminal response
   function Complete_Multipart_Upload
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Completion   :
        Flyology.Object_Storage.S3.Multipart.
          Complete_Multipart_Upload_Request;
      Parameters   : Low_Level.Complete_Multipart_Parameters;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null)
      return Scoped.Multipart_Completion_Result;

   type Upload_Outcome_Kind is (File_Uploaded, Upload_Rejected);

   type Upload_Outcome
     (Kind : Upload_Outcome_Kind := Upload_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when File_Uploaded =>
            Bytes      : Byte_Count := 0;
            Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
            Checksum   : Ada.Strings.Unbounded.Unbounded_String;
            Checksum_Type : Ada.Strings.Unbounded.Unbounded_String;
         when Upload_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Hash and upload one local file without retaining its contents. A single
   --  monotonic deadline is established before opening the file and is shared
   --  by hashing and HTTP execution. Open and Close are metadata syscalls, and
   --  a native positional read cannot be interrupted after entry, so timeout
   --  or cancellation delivery may be delayed by those operating-system calls.
   --  The same open descriptor is hashed and streamed, so replacement of the
   --  path cannot substitute a different file between those phases. The
   --  caller must prevent mutation of that file for the duration of the call;
   --  mutations affecting streamed bytes are rejected by S3 payload-hash
   --  validation. Client must already be configured for Origin. Files at or
   --  above Multipart_Threshold are split automatically. Parts for one file
   --  are sent sequentially through one open descriptor; Transfer_Many
   --  supplies bounded parallelism across independent subjects.
   --
   --  A timeout, cancellation, or transport failure after an UploadPart or
   --  CompleteMultipartUpload request enters HTTP is ambiguous: S3 may have
   --  published the part or committed the object even though no success
   --  response arrived. No part is transparently replayed. The implementation
   --  attempts AbortMultipartUpload on failure, but that is cleanup rather
   --  than a transactional rollback and may itself fail. Applications that
   --  need to reconcile a part before deciding how to proceed must call the
   --  direct Upload_Part API and retain its upload ID and part number.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Local_Path Local file to hash and stream
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Content_Type Optional Content-Type request field
   --  @param Timeout Whole-operation budget; metadata syscalls may delay
   --     delivery after the deadline
   --  @param Token Optional cancellation source
   --  @param Multipart_Threshold Nonempty files at or above this size use
   --     multipart upload
   --  @param Multipart_Part_Size Multipart range size, from 5 MiB through
   --     5 GiB; a plan requiring more than 10,000 parts is rejected
   --  @param Checksum Optional explicit upload checksum policy; COMPOSITE
   --     forces a nonempty file through multipart even below the threshold
   --  @return Typed successful upload or S3 rejection
   function Upload_File
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Local_Path   : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null;
      Multipart_Threshold : Byte_Count := Default_Multipart_Threshold;
      Multipart_Part_Size : Byte_Count := Default_Multipart_Part_Size;
      Checksum : Upload_Checksum_Selection := Default_Upload_Checksum)
      return Upload_Outcome;

   type Copy_Outcome_Kind is (Object_Copied, Copy_Rejected);

   type Copy_Outcome
     (Kind : Copy_Outcome_Kind := Copy_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Copied =>
            Details                : Low_Level.Copy_Object_Result;
            Entity_Tag             : Ada.Strings.Unbounded.Unbounded_String;
            Last_Modified          : Ada.Strings.Unbounded.Unbounded_String;
            Version_ID             : Ada.Strings.Unbounded.Unbounded_String;
            Copy_Source_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
         when Copy_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Copy one S3 object without downloading it. Source_Bucket and Source_Key
   --  are raw application strings; this operation owns the required
   --  x-amz-copy-source URI encoding and signs the resulting header. Client
   --  must already be configured for Origin. Advanced metadata, tagging,
   --  ACL, encryption, lock, metadata, and tagging controls are carried by
   --  Options. This overload always replaces Options.Copy_Source with the
   --  encoded Source_Bucket and Source_Key; use Low_Level directly for a raw
   --  version-specific copy-source value. The successful Details value
   --  preserves every modeled CopyObject output position.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Source_Bucket Source S3 bucket, before URI encoding
   --  @param Source_Key Source S3 object key, before URI encoding
   --  @param Destination_Bucket Destination S3 bucket
   --  @param Destination_Key Destination S3 object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Source_If_Match Optional source entity-tag precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Compact successful copy metadata or the S3 rejection
   --  @exception Low_Level.Invalid_Request if the source bucket/key is
   --     invalid or its encoded representation exceeds the supported bound
   function Copy_Object
     (Client             : aliased in out Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout            : Duration := 30.0;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Outcome;

   --  Compact compatibility overload for the common conditional source copy.
   function Copy_Object
     (Client             : aliased in out Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Identity           : Low_Level.Credentials;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Source_If_Match    : String := "";
      Timeout            : Duration := 30.0;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Outcome;

   type Head_Outcome_Kind is (Object_Found, Head_Rejected);

   type Head_Outcome
     (Kind : Head_Outcome_Kind := Head_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Found =>
            Details        : Low_Level.Head_Object_Result;
            Bytes          : Byte_Count := 0;
            Entity_Tag     : Ada.Strings.Unbounded.Unbounded_String;
            Last_Modified  : Ada.Strings.Unbounded.Unbounded_String;
            Content_Type   : Ada.Strings.Unbounded.Unbounded_String;
            Version_ID     : Ada.Strings.Unbounded.Unbounded_String;
            Checksum_CRC32 : Ada.Strings.Unbounded.Unbounded_String;
            Checksum_CRC32C : Ada.Strings.Unbounded.Unbounded_String;
            Checksum_SHA1  : Ada.Strings.Unbounded.Unbounded_String;
            Checksum_SHA256 : Ada.Strings.Unbounded.Unbounded_String;
            Checksum_Type  : Ada.Strings.Unbounded.Unbounded_String;
         when Head_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Retrieve compact object metadata without a response body. This is the
   --  convenience reconciliation primitive for ambiguous multipart or copy
   --  outcomes. Checksum_Mode requests S3 checksum response fields when the
   --  implementation supports them. Bodyless HEAD errors are returned as a
   --  synthetic HTTP-status S3 error while preserving request identifiers.
   --  The original version/match/checksum arguments remain in place for
   --  source compatibility; the trailing named arguments expose every other
   --  modeled HeadObject control. Details preserves the complete validated
   --  low-level result while the sibling fields provide common shortcuts.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Source S3 bucket
   --  @param Key Source S3 object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Optional exact object version
   --  @param If_Match Optional strong entity-tag precondition
   --  @param Checksum_Mode Request stored checksum response fields
   --  @param Timeout Whole-operation monotonic budget
   --  @param Token Optional cancellation source
   --  @param If_Modified_Since Optional HTTP-date precondition
   --  @param If_None_Match Optional weak entity-tag precondition
   --  @param If_Unmodified_Since Optional HTTP-date precondition
   --  @param Byte_Range_Header Optional single bytes range; AWS returns 200
   --  with the selected Content-Length and no Content-Range
   --  @param Response_Cache_Control Optional response header override
   --  @param Response_Content_Disposition Optional response header override
   --  @param Response_Content_Encoding Optional response header override
   --  @param Response_Content_Language Optional response header override
   --  @param Response_Content_Type Optional response header override
   --  @param Response_Expires Optional response Expires override
   --  @param SSE_Customer_Algorithm Optional SSE-C algorithm
   --  @param SSE_Customer_Key Optional Base64 SSE-C key; HTTPS only
   --  @param SSE_Customer_Key_MD5 Optional Base64 SSE-C key digest
   --  @param Request_Payer Empty or requester
   --  @param Part_Number Optional one-based multipart part selection
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @return Complete successful metadata or structured rejection
   function Head_Object
     (Client        : aliased in out Flyology.HTTP.Client.Client;
      Origin        : Flyology.HTTP.Origin;
      Bucket        : String;
      Key           : String;
      Identity      : Low_Level.Credentials;
      Region        : String := "us-east-1";
      Style         : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID    : String := "";
      If_Match      : String := "";
      Checksum_Mode : Boolean := False;
      Timeout       : Duration := 30.0;
      Token         : access Flyology.Cancellation.Token := null;
      If_Modified_Since : String := "";
      If_None_Match : String := "";
      If_Unmodified_Since : String := "";
      Byte_Range_Header : String := "";
      Response_Cache_Control : String := "";
      Response_Content_Disposition : String := "";
      Response_Content_Encoding : String := "";
      Response_Content_Language : String := "";
      Response_Content_Type : String := "";
      Response_Expires : String := "";
      SSE_Customer_Algorithm : String := "";
      SSE_Customer_Key : String := "";
      SSE_Customer_Key_MD5 : String := "";
      Request_Payer : String := "";
      Part_Number : Low_Level.Optional_Part_Number :=
        (Is_Set => False, Value => 1);
      Expected_Bucket_Owner : String := "")
      return Head_Outcome;

   type Download_Outcome_Kind is (File_Downloaded, Download_Rejected);

   type Download_Outcome
     (Kind : Download_Outcome_Kind := Download_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when File_Downloaded =>
            Bytes      : Byte_Count := 0;
            Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
         when Download_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Stream one object into a same-directory temporary file, then atomically
   --  replace Local_Path only after the complete response is written and the
   --  temporary descriptor closes successfully. A failed request or transfer
   --  leaves an existing destination unchanged. Concurrent calls targeting
   --  the same Local_Path require caller synchronization, and the destination
   --  directory must not be concurrently writable by untrusted principals.
   --  One monotonic HTTP
   --  deadline covers the response head and body; local metadata syscalls and
   --  an in-progress native positional write can delay timeout or cancellation
   --  delivery. Client must already be configured for Origin.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Source S3 bucket
   --  @param Key Source S3 object key
   --  @param Local_Path Destination file atomically replaced on success
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget; local syscalls may delay delivery
   --  @param Token Optional cancellation source
   --  @param Version_ID Optional exact object version; null addresses the
   --  unversioned object
   --  @param If_Match Optional strong entity-tag precondition
   --  @param If_Modified_Since Optional HTTP-date precondition
   --  @param If_None_Match Optional weak entity-tag precondition
   --  @param If_Unmodified_Since Optional HTTP-date precondition
   --  @param Byte_Range_Header Optional single bytes range; a successful 206
   --  atomically publishes the selected interval as the destination file
   --  @param Expected_Bucket_Owner Optional bucket-owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Request stored checksum response fields
   --  @return Typed successful download or S3 rejection
   function Download_File
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Local_Path : String;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Version_ID : String := "";
      If_Match   : String := "";
      If_Modified_Since : String := "";
      If_None_Match : String := "";
      If_Unmodified_Since : String := "";
      Byte_Range_Header : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False)
      return Download_Outcome;

   type Failure_Mode is (Continue_After_Failure, Cancel_Remaining);

   type Batch_Options is record
      Maximum_Concurrent_Objects  : Positive := 16;
      Maximum_Concurrent_Requests : Positive := 32;
      Maximum_In_Flight_Bytes     : Byte_Count := 256 * 1_024 * 1_024;
      On_Failure                  : Failure_Mode := Continue_After_Failure;
      Multipart_Threshold         : Byte_Count :=
        Default_Multipart_Threshold;
      Multipart_Part_Size         : Byte_Count :=
        Default_Multipart_Part_Size;
   end record;

   type Transfer_Kind is (Upload, Download);

   type Subject is record
      Kind       : Transfer_Kind := Upload;
      Bucket     : Ada.Strings.Unbounded.Unbounded_String;
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Local_Path : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Subject_Array is array (Positive range <>) of Subject;

   type Transfer_Status is (Completed, Rejected, Failed, Cancelled);

   type Transfer_Result is record
      State      : Transfer_Status := Failed;
      Status     : Flyology.HTTP.Status_Code := 500;
      Bytes      : Byte_Count := 0;
      Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
      Error_Code : Ada.Strings.Unbounded.Unbounded_String;
      Message    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Transfer_Result_Array is array (Positive range <>) of Transfer_Result;

   --  Execute Subjects in bounded structured waves. Each wave is a Flyology
   --  task scope and is fully joined before this call advances or returns.
   --  The effective worker count is the minimum of both concurrency caps and
   --  Maximum_In_Flight_Bytes / 64 KiB. The byte cap covers file-transfer
   --  buffers owned by this package; Flyology HTTP applies its own bounded
   --  protocol storage and the configured Client capacity remains an
   --  additional request-admission bound. Timeout is one shared batch budget,
   --  not a fresh budget per subject. Results retain input order.
   --  Cancel_Remaining requests the scope token after the first rejected or
   --  failed operation, joins every admitted sibling, and marks later waves
   --  cancelled. Parent cancellation is never propagated upward.
   --  Client and Identity are borrowed only until the fully joined return;
   --  callers must not concurrently finalize or otherwise mutate them. Each
   --  large upload automatically uses multipart, but its parts remain ordered
   --  and sequential; the runtime multiplexes and applies backpressure among
   --  the concurrently admitted subjects rather than spawning one task per
   --  part.
   --  @param Client Configured shared Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Subjects Ordered upload and download subjects
   --  @param Results Per-subject terminal results in matching index positions
   --  @param Identity Aliased credentials borrowed until the joined return
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Options Independent concurrency, buffer, and failure policy
   --  @param Timeout One whole-batch monotonic budget
   --  @param Token Optional parent cancellation source
   procedure Transfer_Many
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Subjects : Subject_Array;
      Results  : out Transfer_Result_Array;
      Identity : aliased Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Options  : Batch_Options := (others => <>);
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
   with Pre => Subjects'First = Results'First
     and then Subjects'Last = Results'Last;

end Flyology.Object_Storage.Client.Transfers;
