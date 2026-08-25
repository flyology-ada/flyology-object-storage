with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Buffers;
with Flyology.Buffers.Drivers;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Operations;

--  Defines bounded multi-subject transfer policy shared by convenience client
--  operations. The execution implementation uses structured Flyology tasks.
package Flyology.Object_Storage.Client.Transfers is

   --  What is known about one CreateMultipartUpload mutation after terminal
   --  drain. Creation_Outcome_Unknown requires a bounded upload listing or
   --  another caller-selected reconciliation step before any retry.
   --  @enum Multipart_Upload_Created Complete validated 200 proves creation
   --  @enum Definitely_Not_Created Admission or exact modeled rejection
   --     proves no upload was created
   --  @enum Creation_Outcome_Unknown Creation must be reconciled before retry
   --  @enum Creation_Cancelled_Before_Admission Cancellation preceded
   --     possible server admission
   type Multipart_Creation_Disposition is
     (Multipart_Upload_Created,
      Definitely_Not_Created,
      Creation_Outcome_Unknown,
      Creation_Cancelled_Before_Admission);

   --  Shape of a terminal CreateMultipartUpload result.
   --  @enum Create_Multipart_Response_Available Complete modeled S3 response
   --     exists
   --  @enum Create_Multipart_Exchange_Failed No complete modeled S3 response
   --     exists
   type Create_Multipart_Result_Kind is
     (Create_Multipart_Response_Available,
      Create_Multipart_Exchange_Failed);

   --  Typed initiation certainty plus either the exact modeled S3 response
   --  or the composable HTTP failure that prevented response decoding.
   --  @field Kind Result shape
   --  @field Disposition Upload-creation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Create_Multipart_Result
     (Kind : Create_Multipart_Result_Kind :=
        Create_Multipart_Exchange_Failed)
   is record
      Disposition : Multipart_Creation_Disposition :=
        Creation_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Create_Multipart_Response_Available =>
            Response : Low_Level.Create_Multipart_Outcome;
         when Create_Multipart_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot CreateMultipartUpload parent with one hidden HTTP child. The
   --  complete modeled Parameters value is copied into the prepared request
   --  before initiation returns. The operation supplies a non-replayable
   --  empty body, so transport reuse cannot repeat initiation transparently.
   type Create_Multipart_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one CreateMultipartUpload operation.
   --  @param Operation Fresh or consumed established initiation operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled initiation controls
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Create_Multipart_Upload
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Create_Multipart_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one CreateMultipartUpload operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled initiation controls
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started non-replaying multipart initiation operation
   function Create_Multipart_Upload
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Multipart_Operation;

   --  Consume one terminal CreateMultipartUpload operation.
   --  @param Operation Terminal multipart initiation request
   --  @param Result Typed modeled response or bounded ambiguous failure
   procedure Finish
     (Operation : in out Create_Multipart_Operation;
      Result    : out Create_Multipart_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one UploadPart publication. Unknown results require
   --  ListParts reconciliation for the exact upload ID and part number before
   --  any caller-selected retry or completion decision.
   --  @enum Part_Published Complete validated success proves staging
   --  @enum Definitely_Not_Staged Admission proves no request was sent
   --  @enum Part_Outcome_Unknown Staging must be reconciled read-only
   --  @enum Part_Cancelled_Before_Admission Cancellation preceded admission
   type Part_Upload_Disposition is
     (Part_Published,
      Definitely_Not_Staged,
      Part_Outcome_Unknown,
      Part_Cancelled_Before_Admission);

   --  Shape of a terminal UploadPart result.
   --  @enum Upload_Part_Response_Available Complete modeled S3 response exists
   --  @enum Upload_Part_Exchange_Failed No complete modeled S3 response exists
   type Upload_Part_Result_Kind is
     (Upload_Part_Response_Available, Upload_Part_Exchange_Failed);

   --  Typed part-publication certainty plus the exact modeled response or
   --  composable HTTP failure. A complete rejection is conservatively
   --  ambiguous unless request admission was definitively absent.
   --  @field Kind Result shape
   --  @field Disposition Part-publication certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Upload_Part_Result
     (Kind : Upload_Part_Result_Kind := Upload_Part_Exchange_Failed)
   is record
      Disposition : Part_Upload_Disposition := Part_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Upload_Part_Response_Available =>
            Response : Low_Level.Upload_Part_Outcome;
         when Upload_Part_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot UploadPart parent with one hidden HTTP child. The acquired
   --  input token moves into the operation until Finish, so no borrowed body
   --  outlives initiation and the forward-only source cannot be replayed.
   type Upload_Part_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: Region, addressing style, and cancellation
   --  defaults below are the established Transfers.Upload_Part values. Their
   --  reuse keeps synchronous and directly composed requests wire-identical.

   --  Start or restart one UploadPart operation. Request validation and
   --  signing finish before Payload_Buffer ownership moves.
   --  @param Operation Fresh or consumed established UploadPart operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled UploadPart controls
   --  @param Payload_Buffer Acquired part bytes moved until Finish
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Upload_Part
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Upload_Part_Operation)
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one non-replaying UploadPart operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled UploadPart controls
   --  @param Payload_Buffer Acquired part bytes moved until Finish
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven UploadPart operation
   function Upload_Part
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Upload_Part_Operation
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Consume one terminal UploadPart and restore the exact input token.
   --  @param Operation Terminal part upload
   --  @param Result Typed modeled response or bounded ambiguous failure
   --  @param Payload_Buffer Vacant same-pool handle receiving the moved token
   procedure Finish
     (Operation : in out Upload_Part_Operation;
      Result    : out Upload_Part_Result;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer)
     with Pre => Flyology.Operations.Is_Terminal (Operation)
       and then not Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  What is known about one CompleteMultipartUpload publication. Unknown
   --  results require read-only reconciliation of the destination object and
   --  exact upload before any caller-selected retry or abort.
   --  @enum Multipart_Completed Complete validated success proves publication
   --  @enum Definitely_Not_Completed Admission proves no request was sent
   --  @enum Completion_Outcome_Unknown Publication must be reconciled
   --  @enum Completion_Cancelled_Before_Admission Cancellation was earlier
   type Multipart_Completion_Disposition is
     (Multipart_Completed,
      Definitely_Not_Completed,
      Completion_Outcome_Unknown,
      Completion_Cancelled_Before_Admission);

   --  Shape of a terminal CompleteMultipartUpload result.
   --  @enum Complete_Multipart_Response_Available Modeled response exists
   --  @enum Complete_Multipart_Exchange_Failed No complete response exists
   type Multipart_Completion_Result_Kind is
     (Complete_Multipart_Response_Available,
      Complete_Multipart_Exchange_Failed);

   --  Typed completion-publication certainty plus the exact modeled response
   --  or composable HTTP failure. Every complete rejection remains
   --  conservative after admission, including an error embedded in HTTP 200.
   --  @field Kind Result shape
   --  @field Disposition Completion-publication certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Multipart_Completion_Result
     (Kind : Multipart_Completion_Result_Kind :=
        Complete_Multipart_Exchange_Failed)
   is record
      Disposition : Multipart_Completion_Disposition :=
        Completion_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Complete_Multipart_Response_Available =>
            Response : Low_Level.Complete_Multipart_Outcome;
         when Complete_Multipart_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot CompleteMultipartUpload parent with one hidden HTTP child. Its
   --  exact serialized XML is owned by the operation and cannot be replayed.
   type Complete_Multipart_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: Region, addressing style, and cancellation
   --  defaults match the established synchronous S3 transfer APIs.

   --  Start or restart one non-replaying CompleteMultipartUpload operation.
   --  Request validation, serialization, and signing finish before start.
   --  @param Operation Fresh or consumed established completion operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Completion Ordered completed-part request
   --  @param Parameters Complete modeled completion controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Complete_Multipart_Upload
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Complete_Multipart_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one non-replaying CompleteMultipartUpload operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Completion Ordered completed-part request
   --  @param Parameters Complete modeled completion controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven completion operation
   function Complete_Multipart_Upload
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Complete_Multipart_Operation;

   --  Consume one terminal CompleteMultipartUpload operation.
   --  @param Operation Terminal multipart completion request
   --  @param Result Typed modeled response or bounded ambiguous failure
   procedure Finish
     (Operation : in out Complete_Multipart_Operation;
      Result    : out Multipart_Completion_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one AbortMultipartUpload mutation after terminal
   --  drain. Unknown results require exact-upload reconciliation before any
   --  caller-selected retry or completion decision.
   --  @enum Multipart_Aborted Complete validated 204 proves acceptance
   --  @enum Definitely_Not_Aborted Admission proves no request was sent
   --  @enum Abort_Outcome_Unknown Abort state must be reconciled
   --  @enum Abort_Cancelled_Before_Admission Cancellation was earlier
   type Multipart_Abort_Disposition is
     (Multipart_Aborted,
      Definitely_Not_Aborted,
      Abort_Outcome_Unknown,
      Abort_Cancelled_Before_Admission);

   --  Shape of a terminal AbortMultipartUpload result.
   --  @enum Abort_Multipart_Response_Available Modeled response exists
   --  @enum Abort_Multipart_Exchange_Failed No complete response exists
   type Multipart_Abort_Result_Kind is
     (Abort_Multipart_Response_Available,
      Abort_Multipart_Exchange_Failed);

   --  Typed abort certainty plus the exact modeled response or composable
   --  HTTP failure. A service rejection does not prove whether an upload was
   --  already absent, completed, or concurrently aborted.
   --  @field Kind Result shape
   --  @field Disposition Abort certainty independent of failure reason
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Multipart_Abort_Result
     (Kind : Multipart_Abort_Result_Kind := Abort_Multipart_Exchange_Failed)
   is record
      Disposition : Multipart_Abort_Disposition := Abort_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Abort_Multipart_Response_Available =>
            Response : Low_Level.Abort_Multipart_Outcome;
         when Abort_Multipart_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot AbortMultipartUpload parent with one hidden HTTP child. The
   --  operation supplies a non-replayable empty request source.
   type Abort_Multipart_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: Region, addressing style, and cancellation
   --  defaults match the established synchronous S3 transfer APIs.

   --  Start or restart one non-replaying AbortMultipartUpload operation.
   --  Request validation and signing finish before start.
   --  @param Operation Fresh or consumed established abort operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Parameters Complete modeled abort controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Abort_Multipart_Upload
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Abort_Multipart_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one non-replaying AbortMultipartUpload operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Upload_ID Exact multipart upload identifier
   --  @param Parameters Complete modeled abort controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven abort operation
   function Abort_Multipart_Upload
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Abort_Multipart_Operation;

   --  Consume one terminal AbortMultipartUpload operation.
   --  @param Operation Terminal abort request
   --  @param Result Typed modeled response or bounded ambiguous failure
   procedure Finish
     (Operation : in out Abort_Multipart_Operation;
      Result    : out Multipart_Abort_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal ListParts read.
   --  @enum List_Parts_Response_Available Modeled S3 response exists
   --  @enum List_Parts_Exchange_Failed No complete response exists
   type List_Parts_Result_Kind is
     (List_Parts_Response_Available,
      List_Parts_Exchange_Failed);

   --  Typed bounded ListParts response or composable HTTP failure. Admission
   --  is retained for diagnostics; this operation is read-only and therefore
   --  has no publication disposition.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Parts_Result
     (Kind : List_Parts_Result_Kind := List_Parts_Exchange_Failed) is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when List_Parts_Response_Available =>
            Response : Low_Level.List_Parts_Outcome;
         when List_Parts_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded ListParts parent with one hidden HTTP child. The operation
   --  owns its prepared request and retained response bytes through terminal
   --  Finish; no borrowed request input is retained.
   type List_Parts_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: parameters, region, addressing style, and
   --  cancellation defaults match the established synchronous ListParts API.

   --  Start or restart one bounded ListParts operation. Request validation
   --  and signing finish before start.
   --  @param Operation Fresh or consumed established ListParts operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled ListParts selectors
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure List_Parts_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Parts_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded ListParts operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled ListParts selectors
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ListParts operation
   function List_Parts_Page
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Parts_Operation;

   --  Consume one terminal ListParts operation.
   --  @param Operation Terminal ListParts request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Parts_Operation;
      Result    : out List_Parts_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal ListMultipartUploads read.
   --  @enum Multipart_Uploads_Response_Available Modeled S3 response exists
   --  @enum List_Multipart_Uploads_Exchange_Failed No complete response exists
   type List_Multipart_Uploads_Result_Kind is
     (Multipart_Uploads_Response_Available,
      List_Multipart_Uploads_Exchange_Failed);

   --  Typed bounded ListMultipartUploads response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only and
   --  therefore has no publication disposition.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Multipart_Uploads_Result
     (Kind : List_Multipart_Uploads_Result_Kind :=
        List_Multipart_Uploads_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Multipart_Uploads_Response_Available =>
            Response : Low_Level.List_Multipart_Uploads_Outcome;
         when List_Multipart_Uploads_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded ListMultipartUploads parent with one hidden HTTP child. The
   --  operation owns its prepared request and retained response bytes through
   --  terminal Finish; no borrowed request input is retained.
   type List_Multipart_Uploads_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: parameters, region, addressing style, and
   --  cancellation defaults match the established synchronous
   --  ListMultipartUploads API.

   --  Start or restart one bounded ListMultipartUploads operation. Request
   --  validation and signing finish before start.
   --  @param Operation Fresh or consumed established listing operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Parameters Complete modeled listing scope and paired cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure List_Multipart_Uploads_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Multipart_Uploads_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded ListMultipartUploads operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Parameters Complete modeled listing scope and paired cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ListMultipartUploads operation
   function List_Multipart_Uploads_Page
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Multipart_Uploads_Operation;

   --  Consume one terminal ListMultipartUploads operation.
   --  @param Operation Terminal ListMultipartUploads request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Multipart_Uploads_Operation;
      Result    : out List_Multipart_Uploads_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal UploadPartCopy mutation.
   --  @enum Upload_Part_Copy_Response_Available Complete modeled response
   --  @enum Upload_Part_Copy_Exchange_Failed No complete modeled response
   type Upload_Part_Copy_Result_Kind is
     (Upload_Part_Copy_Response_Available,
      Upload_Part_Copy_Exchange_Failed);

   --  Typed copied-part publication certainty plus the modeled S3 response
   --  or composable HTTP failure. An unknown result requires ListParts for
   --  the exact upload ID and part number before retry or completion.
   --  @field Kind Result shape
   --  @field Disposition Part-publication certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Upload_Part_Copy_Result
     (Kind : Upload_Part_Copy_Result_Kind :=
        Upload_Part_Copy_Exchange_Failed)
   is record
      Disposition : Publication_Disposition := Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Upload_Part_Copy_Response_Available =>
            Response : Low_Level.Upload_Part_Copy_Outcome;
         when Upload_Part_Copy_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot UploadPartCopy parent with one hidden HTTP child. Complete
   --  parameters are copied into the prepared request before start returns;
   --  no borrowed request input is retained.
   type Upload_Part_Copy_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded non-replaying UploadPartCopy operation.
   --  Request validation and signing finish before start.
   --  @param Operation Fresh or consumed established copy-part operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled UploadPartCopy controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @exception Low_Level.Invalid_Request Parameters are invalid
   --  @exception Program_Error Restart changes Client or Token ownership
   procedure Upload_Part_Copy
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Upload_Part_Copy_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded non-replaying UploadPartCopy operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled UploadPartCopy controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven UploadPartCopy operation
   --  @exception Low_Level.Invalid_Request Parameters are invalid
   function Upload_Part_Copy
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Upload_Part_Copy_Operation;

   --  Consume one terminal UploadPartCopy operation.
   --  @param Operation Terminal copied-part mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Upload_Part_Copy_Operation;
      Result    : out Upload_Part_Copy_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal CopyObject mutation.
   --  @enum Copy_Response_Available Complete modeled S3 response exists
   --  @enum Copy_Exchange_Failed No complete modeled S3 response exists
   type Copy_Result_Kind is
     (Copy_Response_Available, Copy_Exchange_Failed);

   --  Typed CopyObject publication certainty plus the modeled S3 response or
   --  composable HTTP failure. Outcome_Unknown requires a generation-bound
   --  destination read before any caller-selected retry.
   --  @field Kind Result shape
   --  @field Disposition Destination publication certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Copy_Result
     (Kind : Copy_Result_Kind := Copy_Exchange_Failed) is record
      Disposition : Publication_Disposition := Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Copy_Response_Available =>
            Response : Low_Level.Copy_Object_Outcome;
         when Copy_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot CopyObject parent with one hidden HTTP child. Raw source and
   --  destination strings are encoded and copied into the prepared request
   --  before start returns; no borrowed request input is retained.
   type Copy_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: source encoding, complete Options projection,
   --  region, addressing style, and cancellation defaults match the
   --  established synchronous Client.Transfers.Copy_Object API.

   --  Start or restart one bounded non-replaying CopyObject mutation.
   --  @param Operation Fresh or consumed established copy operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Source_Bucket Raw source bucket before URI encoding
   --  @param Source_Key Raw source key before URI encoding
   --  @param Destination_Bucket Destination bucket
   --  @param Destination_Key Destination key
   --  @param Options Complete modeled CopyObject controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @exception Low_Level.Invalid_Request Source or options are invalid
   procedure Copy_Object
     (Client             : not null access Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Deadline           : Flyology.HTTP.Client.Monotonic_Deadline;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token              : access Flyology.Cancellation.Token := null;
      Operation          : in out Copy_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded non-replaying CopyObject mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Source_Bucket Raw source bucket before URI encoding
   --  @param Source_Key Raw source key before URI encoding
   --  @param Destination_Bucket Destination bucket
   --  @param Destination_Key Destination key
   --  @param Options Complete modeled CopyObject controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven CopyObject mutation
   function Copy_Object
     (Set                : not null access
        Flyology.Operations.Completion_Set'Class;
      Client             : not null access Flyology.HTTP.Client.Client;
      Origin             : Flyology.HTTP.Origin;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Low_Level.Copy_Object_Parameters;
      Identity           : Low_Level.Credentials;
      Deadline           : Flyology.HTTP.Client.Monotonic_Deadline;
      Region             : String := "us-east-1";
      Style              : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token              : access Flyology.Cancellation.Token := null)
      return Copy_Operation;

   --  Consume one terminal CopyObject operation.
   --  @param Operation Terminal CopyObject mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Copy_Operation;
      Result    : out Copy_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

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
      return Create_Multipart_Result;

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
      return Multipart_Abort_Result;

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
      return List_Parts_Result;

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
      return List_Multipart_Uploads_Result;

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
      return Upload_Part_Result
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
      return Multipart_Completion_Result;

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

   --  Copy one source range into an established multipart upload by waiting
   --  on the composable owner-driven mutation. The complete parameter record
   --  supplies the raw x-amz-copy-source value, upload ID, part number,
   --  conditions, encryption controls, payer, and expected owners.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination bucket
   --  @param Key Destination object key
   --  @param Parameters Complete modeled UploadPartCopy controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed part-publication certainty and response or exchange error
   --  @exception Low_Level.Invalid_Request Parameters are invalid
   function Upload_Part_Copy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Upload_Part_Copy_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Upload_Part_Copy_Result;

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

   --  Copy one S3 object by waiting on the composable owner-driven mutation.
   --  This result-type overload preserves exact publication and HTTP
   --  admission certainty. Selecting the established Copy_Outcome overload
   --  retains its raising transport contract; arguments and defaults match.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Source_Bucket Source S3 bucket before URI encoding
   --  @param Source_Key Source S3 key before URI encoding
   --  @param Destination_Bucket Destination S3 bucket
   --  @param Destination_Key Destination S3 key
   --  @param Options Complete modeled CopyObject controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed publication certainty and response or exchange failure
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
      return Copy_Result;

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

private

   type Upload_Part_Copy_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : Upload_Part_Copy_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Abort_Multipart_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : Multipart_Abort_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type List_Parts_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : List_Parts_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type List_Multipart_Uploads_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : List_Multipart_Uploads_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Copy_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : Copy_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Create_Multipart_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : Create_Multipart_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Upload_Part_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Source     : Flyology.Buffers.Drivers.Detached_Buffer;
      Source_Position : Natural := 0;
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : Upload_Part_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Complete_Multipart_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Source_Position : Natural := 0;
      Response_Data : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Final_Result : Multipart_Completion_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Create_Multipart_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Create_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Create_Multipart_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Create_Multipart_Operation);
   overriding procedure Write
     (Item : in out Create_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Create_Multipart_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Create_Multipart_Operation);
   overriding procedure Finalize
     (Item : in out Create_Multipart_Operation);
   overriding function Declared_Length
     (Item : Upload_Part_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Upload_Part_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Upload_Part_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Upload_Part_Operation);
   overriding procedure Write
     (Item : in out Upload_Part_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Upload_Part_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Upload_Part_Operation);
   overriding procedure Finalize
     (Item : in out Upload_Part_Operation);
   overriding function Declared_Length
     (Item : Complete_Multipart_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Complete_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Complete_Multipart_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Complete_Multipart_Operation);
   overriding procedure Write
     (Item : in out Complete_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Complete_Multipart_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Complete_Multipart_Operation);
   overriding procedure Finalize
     (Item : in out Complete_Multipart_Operation);
   overriding function Declared_Length
     (Item : Abort_Multipart_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Abort_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Abort_Multipart_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Abort_Multipart_Operation);
   overriding procedure Write
     (Item : in out Abort_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Abort_Multipart_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Abort_Multipart_Operation);
   overriding procedure Finalize
     (Item : in out Abort_Multipart_Operation);
   overriding procedure Write
     (Item : in out List_Parts_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out List_Parts_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out List_Parts_Operation);
   overriding procedure Finalize
     (Item : in out List_Parts_Operation);
   overriding procedure Write
     (Item : in out List_Multipart_Uploads_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out List_Multipart_Uploads_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out List_Multipart_Uploads_Operation);
   overriding procedure Finalize
     (Item : in out List_Multipart_Uploads_Operation);
   overriding function Declared_Length
     (Item : Copy_Operation) return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Copy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Copy_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source (Item : in out Copy_Operation);
   overriding procedure Write
     (Item : in out Copy_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Copy_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation (Item : in out Copy_Operation);
   overriding procedure Finalize (Item : in out Copy_Operation);
   overriding function Declared_Length
     (Item : Upload_Part_Copy_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Upload_Part_Copy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Upload_Part_Copy_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Upload_Part_Copy_Operation);
   overriding procedure Write
     (Item : in out Upload_Part_Copy_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Upload_Part_Copy_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Upload_Part_Copy_Operation);
   overriding procedure Finalize
     (Item : in out Upload_Part_Copy_Operation);
   function Normalize_Create_Multipart_Response
     (Value     : Low_Level.Create_Multipart_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Create_Multipart_Result;
   function Normalize_Create_Multipart_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Create_Multipart_Result;
   function Normalize_Upload_Part_Response
     (Value     : Low_Level.Upload_Part_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Upload_Part_Result;
   function Normalize_Upload_Part_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Upload_Part_Result;
   function Normalize_Complete_Multipart_Response
     (Value     : Low_Level.Complete_Multipart_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Multipart_Completion_Result;
   function Normalize_Complete_Multipart_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Completion_Result;
   function Normalize_Abort_Multipart_Response
     (Value     : Low_Level.Abort_Multipart_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Multipart_Abort_Result;
   function Normalize_Abort_Multipart_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Abort_Result;
   function Normalize_List_Parts_Response
     (Value     : Low_Level.List_Parts_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Parts_Result;
   function Normalize_List_Parts_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Parts_Result;
   function Normalize_List_Multipart_Uploads_Response
     (Value     : Low_Level.List_Multipart_Uploads_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Multipart_Uploads_Result;
   function Normalize_List_Multipart_Uploads_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Multipart_Uploads_Result;
   function Normalize_Copy_Response
     (Value     : Low_Level.Copy_Object_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Copy_Result;
   function Normalize_Copy_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Copy_Result;
   function Normalize_Upload_Part_Copy_Response
     (Value     : Low_Level.Upload_Part_Copy_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Upload_Part_Copy_Result;
   function Normalize_Upload_Part_Copy_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Upload_Part_Copy_Result;

end Flyology.Object_Storage.Client.Transfers;
