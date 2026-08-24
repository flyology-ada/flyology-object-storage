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

   --  Shape of a terminal conditional-PUT result.
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

   --  Conditional complete-object PUT operation. The input buffer token moves
   --  into this object until Finish; no borrowed request bytes are retained.
   type Conditional_Put_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: Region, addressing style, empty optional
   --  fields, and cancellation defaults below mirror the established
   --  Client.Objects conditional-PUT surface. Changing them would make the
   --  synchronous and composable forms select different wire behavior.

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

   --  Consume one terminal conditional PUT and restore its exact input token.
   --  Result is typed for every expected HTTP/S3 outcome. An unexpected local
   --  provider exception is re-raised only after Body ownership is restored.
   --  @param Operation Terminal conditional publication
   --  @param Result Publication certainty and modeled terminal result
   --  @param Payload_Buffer Vacant original same-pool input handle
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
   --  @param Item Internal conditional-PUT parent
   --  @param Event Owner-stack driver event
   overriding procedure Drive
     (Item : in out Conditional_Put_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal conditional-PUT parent
   overriding procedure Request_Cancellation
     (Item : in out Conditional_Put_Operation);
   --  @exclude
   --  @param Item Internal conditional-PUT parent
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

   --  Private normalization boundary shared with the strict test child.
   --  @exclude
   --  @param Value Complete decoded S3 response
   --  @param Admission Terminal HTTP admission certainty
   --  @return Normalized conditional-PUT result
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
   --  @return Normalized conditional-PUT failure
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

end Flyology.Object_Storage.Client.Scoped;
