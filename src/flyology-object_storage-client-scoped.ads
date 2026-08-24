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
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Multipart;
with Flyology.Operations;

--  Composable S3 operations driven by a caller-owned Flyology completion set.
package Flyology.Object_Storage.Client.Scoped is

   --  What is known about publication after a conditional complete-object
   --  mutation. Outcome_Unknown always requires a generation-bound read
   --  before any caller-selected retry.
   --  @enum Published Complete validated success proves publication
   --  @enum Precondition_Failed Complete modeled response proves no mutation
   --  @enum Definitely_Not_Published Admission or modeled response proves no
   --     mutation
   --  @enum Outcome_Unknown Publication must be reconciled by a bound read
   --  @enum Cancelled_Before_Publication Cancellation preceded admission
   type Publication_Disposition is
     (Published,
      Precondition_Failed,
      Definitely_Not_Published,
      Outcome_Unknown,
      Cancelled_Before_Publication);

   --  Stable reason domain for expected conditional-put terminal outcomes.
   --  @enum No_Failure Successful or conclusively failed condition
   --  @enum Authentication_Failed Modeled authentication rejection
   --  @enum Authorization_Failed Modeled authorization rejection
   --  @enum Invalid_Request Local or modeled service request rejection
   --  @enum Not_Found Modeled missing destination
   --  @enum Cancelled Caller cancellation completed its drain
   --  @enum Timed_Out Absolute exchange deadline expired
   --  @enum Client_Unavailable Client could not admit or continue work
   --  @enum Connection_Failed Resolution or connection establishment failed
   --  @enum Transport_Failed Established exchange transport failed
   --  @enum Request_Source_Failed Request source violated its contract
   --  @enum Response_Too_Large Bounded Get destination was too small
   --  @enum Unavailable_Or_Retryable Modeled transient service response
   --  @enum Corrupt_Or_Invalid_Response Response was not conclusive or valid
   type Failure_Reason is
     (No_Failure,
      Authentication_Failed,
      Authorization_Failed,
      Invalid_Request,
      Not_Found,
      Cancelled,
      Timed_Out,
      Client_Unavailable,
      Connection_Failed,
      Transport_Failed,
      Request_Source_Failed,
      Response_Too_Large,
      Unavailable_Or_Retryable,
      Corrupt_Or_Invalid_Response);

   --  Shape of a terminal complete-object PUT result.
   --  @enum Put_Response_Available Complete modeled S3 response is available
   --  @enum Put_Exchange_Failed No complete modeled S3 response is available
   type Conditional_Put_Result_Kind is
     (Put_Response_Available, Put_Exchange_Failed);

   --  Typed publication certainty plus either the exact modeled S3 response
   --  or the composable HTTP failure that prevented response decoding.
   --  @field Kind Result shape
   --  @field Disposition Publication certainty independent of failure reason
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Required_Body_Length Exact known capacity requirement
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Conditional_Put_Result
     (Kind : Conditional_Put_Result_Kind := Put_Exchange_Failed) is record
      Disposition : Publication_Disposition := Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Response_Available =>
            Response : Low_Level.Put_Object_Outcome;
         when Put_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Required_Body_Length : Flyology.HTTP.Client.Length_Requirement :=
              (others => <>);
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  Complete-object PUT operation. The input buffer token moves into this
   --  object until Finish; no borrowed request bytes are retained. The
   --  conditional constructors are restricted projections of this same
   --  operation and certainty model.
   type Conditional_Put_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: Region, addressing style, empty optional
   --  fields, and cancellation defaults below mirror the established
   --  Client.Objects PutObject surfaces. Changing them would make the
   --  synchronous and composable forms select different wire behavior.

   --  Start or restart a complete modeled PutObject in an established
   --  operation. Validation and signing complete before the payload token
   --  moves. The exact prepared parameters bind any requested checksum and
   --  requester-pays response. No request is retried.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Parameters Complete modeled non-body PutObject inputs
   --  @param Payload_Buffer Acquired complete-object bytes moved until Finish
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Put_Object
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Put_Object_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one complete modeled PutObject operation. Ownership,
   --  certainty, request binding, and retry behavior match Start_Put_Object.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Parameters Complete modeled non-body PutObject inputs
   --  @param Payload_Buffer Acquired complete-object bytes moved until Finish
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started complete-object publication operation
   function Put_Object
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Put_Object_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Start or restart immutable publication in an established operation.
   --  Parameters and ownership match the constructor overload.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Payload_Buffer Acquired complete-object bytes moved until Finish
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Put_If_Absent
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Start or restart compare-and-swap publication in an established
   --  operation. Parameters and ownership match the constructor overload.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Expected_Entity_Tag Exact strong opaque generation validator
   --  @param Payload_Buffer Acquired complete-object bytes moved until Finish
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Put_If_Matches
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Start immutable publication with If-None-Match: *. Signing and all
   --  request validation finish before Body ownership moves. Body must remain
   --  vacant until Finish restores the exact token. No request is retried.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Payload_Buffer Acquired complete-object bytes moved until Finish
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Token Optional cancellation source retained through drain
   --  @return Started conditional publication operation
   function Put_If_Absent
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Start compare-and-swap publication with one exact strong opaque ETag.
   --  Ownership, certainty, deadline, and retry behavior match Put_If_Absent.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Expected_Entity_Tag Exact strong opaque generation validator
   --  @param Payload_Buffer Acquired complete-object bytes moved until Finish
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Token Optional cancellation source retained through drain
   --  @return Started conditional publication operation
   function Put_If_Matches
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Consume one terminal complete-object PUT and restore its input token.
   --  Result is typed for every expected HTTP/S3 outcome. An unexpected local
   --  provider exception is re-raised only after Body ownership is restored.
   --  @param Operation Terminal complete-object publication
   --  @param Result Publication certainty and modeled terminal result
   --  @param Payload_Buffer Vacant same-pool handle receiving the moved token
   procedure Finish
     (Operation : in out Conditional_Put_Operation;
      Result    : out Conditional_Put_Result;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer)
     with Pre => Flyology.Operations.Is_Terminal (Operation)
       and then not Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Shape of a terminal bounded whole-Get result.
   --  @enum Whole_Get_Response_Available Complete modeled S3 response exists
   --  @enum Whole_Get_Exchange_Failed No complete modeled S3 response exists
   type Whole_Get_Result_Kind is
     (Whole_Get_Response_Available, Whole_Get_Exchange_Failed);

   --  Typed same-response GetObject metadata. On Object_Opened, the exact
   --  bytes and this metadata come from one complete HTTP response snapshot.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Required_Body_Length Exact known capacity requirement
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Whole_Get_Result
     (Kind : Whole_Get_Result_Kind := Whole_Get_Exchange_Failed) is record
      Failure : Failure_Reason := Corrupt_Or_Invalid_Response;
      case Kind is
         when Whole_Get_Response_Available =>
            Response : Low_Level.Get_Object_Head_Outcome;
         when Whole_Get_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Required_Body_Length : Flyology.HTTP.Client.Length_Requirement :=
              (others => <>);
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  Resolved single response interval from Content-Range. Total_Length is
   --  the immutable representation size against which suffix and open-ended
   --  requests were resolved.
   --  @field First First returned byte offset
   --  @field Last Last returned byte offset
   --  @field Total_Length Complete representation length
   type Resolved_Byte_Range is record
      First        : Byte_Count := 0;
      Last         : Byte_Count := 0;
      Total_Length : Byte_Count := 0;
   end record;

   --  Shape of a terminal generation-bound range result.
   --  @enum Range_Get_Response_Available Complete modeled S3 response exists
   --  @enum Range_Get_Exchange_Failed No complete modeled S3 response exists
   type Range_Get_Result_Kind is
     (Range_Get_Response_Available, Range_Get_Exchange_Failed);

   --  Typed generation-bound range result. A modeled rejection has a complete
   --  Response with Has_Resolved_Range false. Successful 206 responses carry
   --  the exact interval after request/response binding.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Response Complete modeled S3 response
   --  @field Has_Resolved_Range Whether a successful interval is present
   --  @field Resolved Exact returned interval and representation length
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Required_Body_Length Exact known capacity requirement
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Range_Get_Result
     (Kind : Range_Get_Result_Kind := Range_Get_Exchange_Failed) is record
      Failure : Failure_Reason := Corrupt_Or_Invalid_Response;
      case Kind is
         when Range_Get_Response_Available =>
            Response : Low_Level.Get_Object_Head_Outcome;
            Has_Resolved_Range : Boolean := False;
            Resolved : Resolved_Byte_Range;
         when Range_Get_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Required_Body_Length : Flyology.HTTP.Client.Length_Requirement :=
              (others => <>);
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  Same-response bounded whole GetObject operation. Destination is an
   --  explicit retained handle borrow: it must outlive terminal Finish and
   --  must not be inspected while the operation is active. Initiation moves
   --  its exact token into HTTP; terminalization restores it. Non-success
   --  outcomes restore readable length zero.
   type Whole_Get_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation with private;

   --  Compatibility contract: the read selectors and their defaults below
   --  mirror the established Client.Objects whole-Get surface. This keeps a
   --  synchronous wait and a directly composed operation wire-identical.

   --  Start or restart a same-response whole GET in an established operation.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Destination Acquired retained output handle
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Expected_Entity_Tag Optional exact strong ETag validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Get_Whole
     (Operation : in out Whole_Get_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Destination.all)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Start one complete GetObject, optionally bound to an exact ETag and/or
   --  version identifier. Destination capacity is the response body bound.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Destination Acquired retained output handle
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Expected_Entity_Tag Optional exact strong ETag validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Token Optional cancellation source retained through drain
   --  @return Started bounded same-response read
   function Get_Whole
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
      return Whole_Get_Operation
     with Pre => Flyology.Buffers.Has_Buffer (Destination.all);

   --  Consume one terminal whole GET. Destination already owns its exact
   --  token; a successful result leaves complete object bytes readable.
   --  @param Operation Terminal same-response read
   --  @param Result Typed response or transport/capacity failure
   procedure Finish
     (Operation : in out Whole_Get_Operation;
      Result    : out Whole_Get_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  A distinct range type prevents a caller from consuming the operation
   --  through whole-Get Finish while retaining the same owner-driven shape.
   type Range_Get_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation with private;

   --  Start or restart a generation-bound single-range GET. Requested must be
   --  bounded, open-ended, or suffix; the response interval is resolved and
   --  bound to it against one immutable representation length. The exact
   --  quoted entity tag prevents bytes from another generation being
   --  accepted. Destination ownership matches Start_Get_Whole.
   --  @param Operation Fresh or consumed established range operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Requested Typed non-whole single range
   --  @param Destination Acquired retained output handle
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Expected_Entity_Tag Exact strong generation validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Get_Range
     (Operation : in out Range_Get_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Destination.all)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one generation-bound single-range GET operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Requested Typed non-whole single range
   --  @param Destination Acquired retained output handle
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Expected_Entity_Tag Exact strong generation validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Token Optional cancellation source retained through drain
   --  @return Started bounded same-response range read
   function Get_Range
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
      return Range_Get_Operation
     with Pre => Flyology.Buffers.Has_Buffer (Destination.all);

   --  Consume one terminal range GET and return its bound interval.
   --  @param Operation Terminal same-response range read
   --  @param Result Typed response, resolved interval, or bounded failure
   procedure Finish
     (Operation : in out Range_Get_Operation;
      Result    : out Range_Get_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal bodyless HeadObject result.
   --  @enum Head_Response_Available Complete modeled S3 response exists
   --  @enum Head_Exchange_Failed No complete modeled S3 response exists
   type Head_Result_Kind is
     (Head_Response_Available, Head_Exchange_Failed);

   --  Typed bodyless HeadObject result or bounded HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Head_Result
     (Kind : Head_Result_Kind := Head_Exchange_Failed) is record
      Failure : Failure_Reason := Corrupt_Or_Invalid_Response;
      case Kind is
         when Head_Response_Available =>
            Response : Low_Level.Head_Object_Outcome;
         when Head_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  Bodyless HeadObject parent with one hidden HTTP child. Parameters is the
   --  complete pinned HeadObject input surface and is copied into the signed
   --  request before initiation returns.
   type Head_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart a bodyless HeadObject operation.
   --  @param Operation Fresh or consumed established HeadObject operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled HeadObject controls
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Head_Object
     (Operation : in out Head_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bodyless HeadObject operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled HeadObject controls
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started bodyless HeadObject operation
   function Head_Object
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Operation;

   --  Consume one terminal HeadObject operation.
   --  @param Operation Terminal bodyless metadata request
   --  @param Result Typed modeled response or bounded failure
   procedure Finish
     (Operation : in out Head_Operation;
      Result    : out Head_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one DeleteObject mutation after terminal drain.
   --  Deletion_Outcome_Unknown requires an exact read before any
   --  caller-selected retry.
   --  @enum Deletion_Completed Complete validated 204 proves acceptance
   --  @enum Definitely_Not_Deleted Admission or modeled rejection proves no
   --     deletion
   --  @enum Deletion_Outcome_Unknown Deletion must be reconciled by a bound
   --     read
   --  @enum Deletion_Cancelled_Before_Admission Cancellation preceded
   --     possible server admission
   type Deletion_Disposition is
     (Deletion_Completed,
      Definitely_Not_Deleted,
      Deletion_Outcome_Unknown,
      Deletion_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteObject result.
   --  @enum Delete_Response_Available Complete modeled S3 response exists
   --  @enum Delete_Exchange_Failed No complete modeled S3 response exists
   type Delete_Result_Kind is
     (Delete_Response_Available, Delete_Exchange_Failed);

   --  Typed deletion certainty plus either the exact modeled S3 response or
   --  the composable HTTP failure that prevented response decoding.
   --  @field Kind Result shape
   --  @field Disposition Deletion certainty independent of failure reason
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Result
     (Kind : Delete_Result_Kind := Delete_Exchange_Failed) is record
      Disposition : Deletion_Disposition := Deletion_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Response_Available =>
            Response : Low_Level.Delete_Object_Outcome;
         when Delete_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteObject parent with one hidden HTTP child. Parameters is
   --  the complete pinned DeleteObject input surface and is copied before
   --  initiation returns. The operation supplies a non-replayable empty body
   --  so a reused-transport failure cannot transparently repeat the mutation.
   type Delete_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one DeleteObject operation.
   --  @param Operation Fresh or consumed established deletion operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled DeleteObject controls
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Delete_Object
     (Operation : in out Delete_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one DeleteObject operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled DeleteObject controls
   --  @param Identity Credentials used only during synchronous signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started non-replaying deletion operation
   function Delete_Object
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Operation;

   --  Consume one terminal DeleteObject operation.
   --  @param Operation Terminal deletion request
   --  @param Result Typed modeled response or bounded ambiguous failure
   procedure Finish
     (Operation : in out Delete_Operation;
      Result    : out Delete_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one DeleteObjects batch after terminal drain. A
   --  validated 200 proves that the server processed the batch, while each
   --  per-entry Deleted/Error result remains authoritative. Unknown outcomes
   --  require read-only reconciliation of every requested generation before
   --  any caller-selected retry.
   --  @enum Batch_Processed Complete validated response proves processing
   --  @enum Batch_Definitely_Not_Processed Exact rejection or non-admission
   --     proves the batch was not processed
   --  @enum Batch_Outcome_Unknown Some entries may have been durably applied
   --  @enum Batch_Cancelled_Before_Admission Cancellation preceded admission
   type Delete_Objects_Disposition is
     (Batch_Processed,
      Batch_Definitely_Not_Processed,
      Batch_Outcome_Unknown,
      Batch_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteObjects result.
   --  @enum Delete_Objects_Response_Available Complete modeled response exists
   --  @enum Delete_Objects_Exchange_Failed No complete response exists
   type Delete_Objects_Result_Kind is
     (Delete_Objects_Response_Available, Delete_Objects_Exchange_Failed);

   --  Typed batch-processing certainty plus either the exact per-entry S3
   --  response or the composable HTTP failure that prevented decoding.
   --  @field Kind Result shape
   --  @field Disposition Batch-processing certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Objects_Result
     (Kind : Delete_Objects_Result_Kind := Delete_Objects_Exchange_Failed)
   is record
      Disposition : Delete_Objects_Disposition := Batch_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Objects_Response_Available =>
            Response : Low_Level.Delete_Objects_Outcome;
         when Delete_Objects_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteObjects parent with one hidden HTTP child. The exact
   --  serialized request XML is owned by the operation and cannot be replayed
   --  after possible server admission.
   type Delete_Objects_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded non-replaying DeleteObjects operation.
   --  Request validation, serialization, and signing finish before start.
   --  @param Operation Fresh or consumed established batch operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose selected entries are deleted
   --  @param Request Bounded ordered delete request copied before start
   --  @param Parameters Complete modeled DeleteObjects controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Start_Delete_Objects
     (Operation : in out Delete_Objects_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded non-replaying DeleteObjects operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose selected entries are deleted
   --  @param Request Bounded ordered delete request copied before start
   --  @param Parameters Complete modeled DeleteObjects controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven batch deletion operation
   function Delete_Objects
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Objects_Operation;

   --  Consume one terminal DeleteObjects operation.
   --  @param Operation Terminal batch deletion request
   --  @param Result Typed per-entry response or bounded ambiguous failure
   procedure Finish
     (Operation : in out Delete_Objects_Operation;
      Result    : out Delete_Objects_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

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
   procedure Start_Create_Multipart_Upload
     (Operation : in out Create_Multipart_Operation;
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
   procedure Start_Upload_Part
     (Operation : in out Upload_Part_Operation;
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
   procedure Start_Complete_Multipart_Upload
     (Operation : in out Complete_Multipart_Operation;
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
   procedure Start_Abort_Multipart_Upload
     (Operation : in out Abort_Multipart_Operation;
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

   --  Shape of a terminal ListObjectsV2 read.
   --  @enum List_Objects_V2_Response_Available Modeled S3 response exists
   --  @enum List_Objects_V2_Exchange_Failed No complete response exists
   type List_Objects_V2_Result_Kind is
     (List_Objects_V2_Response_Available,
      List_Objects_V2_Exchange_Failed);

   --  Typed bounded ListObjectsV2 response or composable HTTP failure.
   --  Admission is retained for diagnostics; listing is read-only and each
   --  page remains an independent service snapshot.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Objects_V2_Result
     (Kind : List_Objects_V2_Result_Kind :=
        List_Objects_V2_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when List_Objects_V2_Response_Available =>
            Response : Low_Level.List_Objects_V2_Outcome;
         when List_Objects_V2_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded ListObjectsV2 parent with one hidden HTTP child. The
   --  operation owns its prepared request and retained response bytes through
   --  terminal Finish; no borrowed request input is retained.
   type List_Objects_V2_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: parameters, region, addressing style, and
   --  cancellation defaults match the established synchronous ListObjectsV2
   --  API. The response buffer bound is derived from the shared XML limits.

   --  Start or restart one bounded ListObjectsV2 operation. Request
   --  validation and signing finish before start.
   --  @param Operation Fresh or consumed established listing operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose current objects are listed
   --  @param Parameters Complete modeled listing scope and cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Start_List_Objects_V2
     (Operation : in out List_Objects_V2_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded ListObjectsV2 operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose current objects are listed
   --  @param Parameters Complete modeled listing scope and cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ListObjectsV2 operation
   function List_Objects_V2
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_V2_Operation;

   --  Consume one terminal ListObjectsV2 operation.
   --  @param Operation Terminal ListObjectsV2 request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Objects_V2_Operation;
      Result    : out List_Objects_V2_Result)
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
   procedure Start_List_Parts
     (Operation : in out List_Parts_Operation;
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
   function List_Parts
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
   procedure Start_List_Multipart_Uploads
     (Operation : in out List_Multipart_Uploads_Operation;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
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
   function List_Multipart_Uploads
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
   procedure Start_Copy_Object
     (Operation          : in out Copy_Operation;
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

private
   --  @exclude
   type Conditional_Put_Operation
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
      Final_Result : Conditional_Put_Result;
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
   type List_Objects_V2_Operation
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
      Final_Result : List_Objects_V2_Result;
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
   type Whole_Get_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Expected_Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Final_Result : Whole_Get_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Range_Get_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Expected_Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
      Requested_Range : Byte_Range := Whole_Object;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Final_Result : Range_Get_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Head_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Final_Result : Head_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Operation
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
      Final_Result : Delete_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Objects_Operation
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
      Final_Result : Delete_Objects_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   --  @param Item Internal request source
   --  @return Stable complete-object length
   overriding function Declared_Length
     (Item : Conditional_Put_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal request source
   --  @param Data Caller-provided output slice
   --  @param Last Last produced element
   --  @param Result Immediate source result
   overriding procedure Read_Now
     (Item   : in out Conditional_Put_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal request source
   --  @param Required Requested readiness direction
   --  @param Descriptor Ignored immediate-source descriptor
   --  @param Ready_Now Always true for the retained buffer
   overriding procedure Source_Wait_Source
     (Item       : in out Conditional_Put_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal request source
   overriding procedure Release_Source
     (Item : in out Conditional_Put_Operation);
   --  @exclude
   --  @param Item Internal bounded response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out Conditional_Put_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal complete-object PUT parent
   --  @param Event Owner-stack driver event
   overriding procedure Drive
     (Item : in out Conditional_Put_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal complete-object PUT parent
   overriding procedure Request_Cancellation
     (Item : in out Conditional_Put_Operation);
   --  @exclude
   --  @param Item Internal complete-object PUT parent
   overriding procedure Finalize (Item : in out Conditional_Put_Operation);

   --  @exclude
   --  @param Item Internal whole-Get parent
   --  @param Event Owner-stack driver event
   overriding procedure Drive
     (Item : in out Whole_Get_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal whole-Get parent
   overriding procedure Request_Cancellation
     (Item : in out Whole_Get_Operation);
   --  @exclude
   --  @param Item Internal whole-Get parent
   overriding procedure Finalize (Item : in out Whole_Get_Operation);

   --  @exclude
   --  @param Item Internal range-Get parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Range_Get_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal range-Get parent
   overriding procedure Request_Cancellation
     (Item : in out Range_Get_Operation);
   --  @exclude
   --  @param Item Internal range-Get parent
   overriding procedure Finalize (Item : in out Range_Get_Operation);

   --  @exclude
   --  @param Item Internal HeadObject parent
   --  @param Data Response-body octets, which are forbidden for HEAD
   overriding procedure Write
     (Item : in out Head_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal HeadObject parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Head_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal HeadObject parent
   overriding procedure Request_Cancellation
     (Item : in out Head_Operation);
   --  @exclude
   --  @param Item Internal HeadObject parent
   overriding procedure Finalize (Item : in out Head_Operation);

   --  @exclude
   --  @param Item Internal empty DeleteObject request source
   --  @return Stable zero request-body length
   overriding function Declared_Length
     (Item : Delete_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal empty DeleteObject request source
   --  @param Data Caller-provided output slice
   --  @param Last Empty result boundary
   --  @param Result Immediate finished result
   overriding procedure Read_Now
     (Item   : in out Delete_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal empty DeleteObject request source
   --  @param Required Requested readiness direction
   --  @param Descriptor Ignored immediate-source descriptor
   --  @param Ready_Now Always true for the empty source
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal empty DeleteObject request source
   overriding procedure Release_Source (Item : in out Delete_Operation);
   --  @exclude
   --  @param Item Internal bounded DeleteObject response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out Delete_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal DeleteObject parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Delete_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal DeleteObject parent
   overriding procedure Request_Cancellation
     (Item : in out Delete_Operation);
   --  @exclude
   --  @param Item Internal DeleteObject parent
   overriding procedure Finalize (Item : in out Delete_Operation);

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Objects_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Objects_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Objects_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Objects_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Objects_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Objects_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Objects_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Objects_Operation);

   --  @exclude
   --  @param Item Internal empty CreateMultipartUpload request source
   --  @return Stable zero request-body length
   overriding function Declared_Length
     (Item : Create_Multipart_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal empty CreateMultipartUpload request source
   --  @param Data Caller-provided output slice
   --  @param Last Empty result boundary
   --  @param Result Immediate finished result
   overriding procedure Read_Now
     (Item   : in out Create_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal empty CreateMultipartUpload request source
   --  @param Required Requested readiness direction
   --  @param Descriptor Ignored immediate-source descriptor
   --  @param Ready_Now Always true for the empty source
   overriding procedure Source_Wait_Source
     (Item       : in out Create_Multipart_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal empty CreateMultipartUpload request source
   overriding procedure Release_Source
     (Item : in out Create_Multipart_Operation);
   --  @exclude
   --  @param Item Internal bounded CreateMultipartUpload response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out Create_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal CreateMultipartUpload parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Create_Multipart_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal CreateMultipartUpload parent
   overriding procedure Request_Cancellation
     (Item : in out Create_Multipart_Operation);
   --  @exclude
   --  @param Item Internal CreateMultipartUpload parent
   overriding procedure Finalize
     (Item : in out Create_Multipart_Operation);

   --  @exclude
   --  @param Item Internal one-shot UploadPart source
   --  @return Stable acquired part length
   overriding function Declared_Length
     (Item : Upload_Part_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal one-shot UploadPart source
   --  @param Data Caller-provided output slice
   --  @param Last Last produced byte
   --  @param Result Progress or completion
   overriding procedure Read_Now
     (Item   : in out Upload_Part_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal immediate UploadPart source
   --  @param Required Requested readiness direction
   --  @param Descriptor Ignored immediate-source descriptor
   --  @param Ready_Now Always true for the acquired buffer
   overriding procedure Source_Wait_Source
     (Item       : in out Upload_Part_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal one-shot UploadPart source
   overriding procedure Release_Source
     (Item : in out Upload_Part_Operation);
   --  @exclude
   --  @param Item Internal bounded UploadPart response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out Upload_Part_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal UploadPart parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Upload_Part_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal UploadPart parent
   overriding procedure Request_Cancellation
     (Item : in out Upload_Part_Operation);
   --  @exclude
   --  @param Item Internal UploadPart parent
   overriding procedure Finalize
     (Item : in out Upload_Part_Operation);

   --  @exclude
   --  @param Item Internal one-shot completion XML source
   --  @return Stable serialized completion length
   overriding function Declared_Length
     (Item : Complete_Multipart_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal one-shot completion XML source
   --  @param Data Caller-provided output slice
   --  @param Last Last produced byte
   --  @param Result Progress or completion
   overriding procedure Read_Now
     (Item   : in out Complete_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal immediate completion source
   --  @param Required Requested readiness direction
   --  @param Descriptor Ignored immediate-source descriptor
   --  @param Ready_Now Always true for owned XML
   overriding procedure Source_Wait_Source
     (Item       : in out Complete_Multipart_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal one-shot completion source
   overriding procedure Release_Source
     (Item : in out Complete_Multipart_Operation);
   --  @exclude
   --  @param Item Internal bounded completion response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out Complete_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal completion parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Complete_Multipart_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal completion parent
   overriding procedure Request_Cancellation
     (Item : in out Complete_Multipart_Operation);
   --  @exclude
   --  @param Item Internal completion parent
   overriding procedure Finalize
     (Item : in out Complete_Multipart_Operation);

   --  @exclude
   --  @param Item Internal empty AbortMultipartUpload request source
   --  @return Stable zero request-body length
   overriding function Declared_Length
     (Item : Abort_Multipart_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal empty AbortMultipartUpload request source
   --  @param Data Caller-provided output slice
   --  @param Last Empty result boundary
   --  @param Result Immediate finished result
   overriding procedure Read_Now
     (Item   : in out Abort_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal empty AbortMultipartUpload request source
   --  @param Required Requested readiness direction
   --  @param Descriptor Ignored immediate-source descriptor
   --  @param Ready_Now Always true for the empty source
   overriding procedure Source_Wait_Source
     (Item       : in out Abort_Multipart_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal empty AbortMultipartUpload request source
   overriding procedure Release_Source
     (Item : in out Abort_Multipart_Operation);
   --  @exclude
   --  @param Item Internal bounded AbortMultipartUpload response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out Abort_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal AbortMultipartUpload parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out Abort_Multipart_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal AbortMultipartUpload parent
   overriding procedure Request_Cancellation
     (Item : in out Abort_Multipart_Operation);
   --  @exclude
   --  @param Item Internal AbortMultipartUpload parent
   overriding procedure Finalize
     (Item : in out Abort_Multipart_Operation);

   --  @exclude
   --  @param Item Internal bounded ListObjectsV2 response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out List_Objects_V2_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal ListObjectsV2 parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out List_Objects_V2_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal ListObjectsV2 parent
   overriding procedure Request_Cancellation
     (Item : in out List_Objects_V2_Operation);
   --  @exclude
   --  @param Item Internal ListObjectsV2 parent
   overriding procedure Finalize
     (Item : in out List_Objects_V2_Operation);

   --  @exclude
   --  @param Item Internal bounded ListParts response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out List_Parts_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal ListParts parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out List_Parts_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal ListParts parent
   overriding procedure Request_Cancellation
     (Item : in out List_Parts_Operation);
   --  @exclude
   --  @param Item Internal ListParts parent
   overriding procedure Finalize
     (Item : in out List_Parts_Operation);

   --  @exclude
   --  @param Item Internal bounded ListMultipartUploads response sink
   --  @param Data Complete-response fragment
   overriding procedure Write
     (Item : in out List_Multipart_Uploads_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal ListMultipartUploads parent
   --  @param Event Owner-driver event
   overriding procedure Drive
     (Item : in out List_Multipart_Uploads_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal ListMultipartUploads parent
   overriding procedure Request_Cancellation
     (Item : in out List_Multipart_Uploads_Operation);
   --  @exclude
   --  @param Item Internal ListMultipartUploads parent
   overriding procedure Finalize
     (Item : in out List_Multipart_Uploads_Operation);

   --  @exclude
   --  @param Item Internal one-shot empty CopyObject request source
   --  @return Exact zero request-body length
   overriding function Declared_Length
     (Item : Copy_Operation) return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Copy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Copy_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source (Item : in out Copy_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Copy_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Copy_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation (Item : in out Copy_Operation);
   --  @exclude
   overriding procedure Finalize (Item : in out Copy_Operation);

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized complete-object PUT result
   function Normalize_Put_Response
     (Value     : Low_Level.Put_Object_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Conditional_Put_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Required Exact known response capacity requirement
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized complete-object PUT failure
   function Normalize_Put_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Required  : Flyology.HTTP.Client.Length_Requirement := (others => <>);
      Detail    : String := "") return Conditional_Put_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized DeleteObject result
   function Normalize_Delete_Response
     (Value     : Low_Level.Delete_Object_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized DeleteObject failure
   function Normalize_Delete_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized CreateMultipartUpload result
   function Normalize_Create_Multipart_Response
     (Value     : Low_Level.Create_Multipart_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Create_Multipart_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized CreateMultipartUpload failure
   function Normalize_Create_Multipart_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Create_Multipart_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized UploadPart result
   function Normalize_Upload_Part_Response
     (Value     : Low_Level.Upload_Part_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Upload_Part_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized UploadPart failure
   function Normalize_Upload_Part_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Upload_Part_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized CompleteMultipartUpload result
   function Normalize_Complete_Multipart_Response
     (Value     : Low_Level.Complete_Multipart_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Multipart_Completion_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   function Normalize_Delete_Objects_Response
     (Value     : Low_Level.Delete_Objects_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Objects_Result;

   --  @exclude
   function Normalize_Delete_Objects_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Objects_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized CompleteMultipartUpload failure
   function Normalize_Complete_Multipart_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Completion_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized AbortMultipartUpload result
   function Normalize_Abort_Multipart_Response
     (Value     : Low_Level.Abort_Multipart_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Multipart_Abort_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized AbortMultipartUpload failure
   function Normalize_Abort_Multipart_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Abort_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized ListObjectsV2 response
   function Normalize_List_Objects_V2_Response
     (Value     : Low_Level.List_Objects_V2_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Objects_V2_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized ListObjectsV2 exchange failure
   function Normalize_List_Objects_V2_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Objects_V2_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized ListParts response
   function Normalize_List_Parts_Response
     (Value     : Low_Level.List_Parts_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Parts_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized ListParts exchange failure
   function Normalize_List_Parts_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Parts_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized ListMultipartUploads response
   function Normalize_List_Multipart_Uploads_Response
     (Value     : Low_Level.List_Multipart_Uploads_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Multipart_Uploads_Result;

   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission Terminal HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Normalized ListMultipartUploads exchange failure
   function Normalize_List_Multipart_Uploads_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Multipart_Uploads_Result;

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   function Normalize_Copy_Response
     (Value     : Low_Level.Copy_Object_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Copy_Result;

   --  @exclude
   function Normalize_Copy_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Copy_Result;

end Flyology.Object_Storage.Client.Scoped;
