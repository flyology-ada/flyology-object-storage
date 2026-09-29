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
with Flyology.Object_Storage.Client.Bounded_REST_XML_Reads;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

--  High-level object and object-listing operations over a configured Flyology
--  HTTP client.
package Flyology.Object_Storage.Client.Objects is

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
   procedure Put_Object
     (Client   : not null access Flyology.HTTP.Client.Client;
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
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Conditional_Put_Operation)
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer)
       and then not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one complete modeled PutObject operation. Ownership,
   --  certainty, request binding, and retry behavior match Put_Object.
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
   procedure Put_If_Absent
     (Client   : not null access Flyology.HTTP.Client.Client;
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
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Conditional_Put_Operation)
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
   procedure Put_If_Matches
     (Client   : not null access Flyology.HTTP.Client.Client;
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
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Conditional_Put_Operation)
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
   procedure Get_Whole
     (Client   : not null access Flyology.HTTP.Client.Client;
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
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Whole_Get_Operation)
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
   --  accepted. Destination ownership matches Get_Whole.
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
   procedure Get_Range
     (Client   : not null access Flyology.HTTP.Client.Client;
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
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Range_Get_Operation)
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
   procedure Head_Object
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Head_Operation)
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
   procedure Delete
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Delete_Operation)
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
   function Delete
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
   procedure Delete_Objects
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Delete_Objects_Operation)
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

   --  Shape of a terminal ListObjects v1 read.
   --  @enum List_Objects_Response_Available Modeled S3 response exists
   --  @enum List_Objects_Exchange_Failed No complete response exists
   type List_Objects_Result_Kind is
     (List_Objects_Response_Available, List_Objects_Exchange_Failed);

   --  Typed bounded ListObjects v1 response or composable HTTP failure.
   --  Admission is retained for diagnostics; listing is read-only and each
   --  page remains an independent service snapshot.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Objects_Result
     (Kind : List_Objects_Result_Kind := List_Objects_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when List_Objects_Response_Available =>
            Response : Low_Level.List_Objects_Outcome;
         when List_Objects_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded ListObjects v1 parent with one hidden HTTP child. The
   --  operation owns its prepared request and retained response bytes through
   --  terminal Finish; no borrowed request input is retained.
   type List_Objects_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded ListObjects v1 operation. Request
   --  validation and signing finish before start.
   --  @param Operation Fresh or consumed established listing operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose current objects are listed
   --  @param Parameters Complete modeled v1 listing scope and marker
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure List_V1_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Objects_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded ListObjects v1 operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose current objects are listed
   --  @param Parameters Complete modeled v1 listing scope and marker
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ListObjects v1 operation
   function List_V1_Page
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_Operation;

   --  Consume one terminal ListObjects v1 operation.
   --  @param Operation Terminal ListObjects v1 request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Objects_Operation;
      Result    : out List_Objects_Result)
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
   --  validation and signing finish before start. The operation retains its
   --  HTTP client and optional cancellation owner through terminal drain;
   --  each completed page is an independent read-only service snapshot.
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
   procedure List_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Objects_V2_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded ListObjectsV2 operation. The result owns its
   --  prepared request and bounded response bytes through terminal Finish;
   --  each completed page is an independent read-only service snapshot.
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
   function List_Page
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

   --  Shape of a terminal ListObjectVersions read.
   --  @enum List_Object_Versions_Response_Available Modeled response exists
   --  @enum List_Object_Versions_Exchange_Failed No complete response exists
   type List_Object_Versions_Result_Kind is
     (List_Object_Versions_Response_Available,
      List_Object_Versions_Exchange_Failed);

   --  Typed bounded version-listing response or composable HTTP failure.
   --  Each page is a read-only service snapshot. Version identifiers remain
   --  opaque; URL-encoded key markers must be decoded before a later Start.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Object_Versions_Result
     (Kind : List_Object_Versions_Result_Kind :=
        List_Object_Versions_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when List_Object_Versions_Response_Available =>
            Response : Low_Level.List_Object_Versions_Outcome;
         when List_Object_Versions_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded ListObjectVersions parent with one hidden HTTP child. It
   --  owns the prepared request and response bytes through terminal Finish;
   --  no caller request value is borrowed after Start returns.
   type List_Object_Versions_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded ListObjectVersions operation. Request
   --  validation and signing finish before start.
   --  @param Operation Fresh or consumed established listing operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose retained generations are listed
   --  @param Parameters Complete modeled scope and paired cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure List_Versions_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Object_Versions_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded ListObjectVersions operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose retained generations are listed
   --  @param Parameters Complete modeled scope and paired cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ListObjectVersions operation
   function List_Versions_Page
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Object_Versions_Operation;

   --  Consume one terminal ListObjectVersions operation.
   --  @param Operation Terminal ListObjectVersions request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Object_Versions_Operation;
      Result    : out List_Object_Versions_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal GetObjectAttributes read.
   --  @enum Get_Object_Attributes_Response_Available Modeled response exists
   --  @enum Get_Object_Attributes_Exchange_Failed No complete response exists
   type Get_Object_Attributes_Result_Kind is
     (Get_Object_Attributes_Response_Available,
      Get_Object_Attributes_Exchange_Failed);

   --  Typed bounded object-attributes response or composable HTTP failure.
   --  The operation is read-only; admission is retained for diagnostics and
   --  no retry policy is implied.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Object_Attributes_Result
     (Kind : Get_Object_Attributes_Result_Kind :=
        Get_Object_Attributes_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Object_Attributes_Response_Available =>
            Response : Low_Level.Get_Object_Attributes_Outcome;
         when Get_Object_Attributes_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetObjectAttributes parent with one hidden HTTP child. It
   --  owns the prepared request and response bytes through terminal Finish;
   --  no caller parameter or credential value is borrowed after Start.
   type Get_Object_Attributes_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetObjectAttributes operation. Request
   --  validation and signing finish before start.
   --  @param Operation Fresh or consumed established attributes operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled selection and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Get_Attributes
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Get_Object_Attributes_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetObjectAttributes operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled selection and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven GetObjectAttributes operation
   function Get_Attributes
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Object_Attributes_Operation;

   --  Consume one terminal GetObjectAttributes operation.
   --  @param Operation Terminal GetObjectAttributes request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Object_Attributes_Operation;
      Result    : out Get_Object_Attributes_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal GetObjectAcl read.
   --  @enum Get_Object_ACL_Response_Available Modeled response exists
   --  @enum Get_Object_ACL_Exchange_Failed No complete response exists
   type Get_Object_ACL_Result_Kind is
     (Get_Object_ACL_Response_Available,
      Get_Object_ACL_Exchange_Failed);

   --  Typed GetObjectAcl response or composable HTTP failure. Admission is
   --  retained for diagnostics; this operation is read-only. Default
   --  initialization is the conservative inert exchange-failed shape used by
   --  operation storage before terminal assignment.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Object_ACL_Result
     (Kind : Get_Object_ACL_Result_Kind := Get_Object_ACL_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Object_ACL_Response_Available =>
            Response : Low_Level.Get_Object_ACL_Outcome;
         when Get_Object_ACL_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetObjectAcl parent with one hidden HTTP child. The
   --  operation owns its signed request and retained response bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Object_ACL_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetObjectAcl read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version, payer, and owner controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established ACL read
   procedure Get_ACL
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Object_ACL_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetObjectAcl read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version, payer, and owner controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ACL read
   function Get_ACL
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Object_ACL_Operation;

   --  Consume one terminal GetObjectAcl operation.
   --  @param Operation Terminal ACL read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Object_ACL_Operation;
      Result    : out Get_Object_ACL_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one object ACL by waiting on the provider-owned composable
   --  operation. Existing region, addressing, timeout, and XML-limit defaults
   --  are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version, payer, and owner controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_ACL
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Object_ACL_Result;

   --  Shape of a terminal GetObjectLegalHold read.
   --  @enum Get_Legal_Hold_Response_Available Modeled response exists
   --  @enum Get_Legal_Hold_Exchange_Failed No modeled response exists
   type Get_Legal_Hold_Result_Kind is
     (Get_Legal_Hold_Response_Available, Get_Legal_Hold_Exchange_Failed);

   --  Typed bounded GetObjectLegalHold response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Legal_Hold_Result
     (Kind : Get_Legal_Hold_Result_Kind := Get_Legal_Hold_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Legal_Hold_Response_Available =>
            Response : Low_Level.Get_Object_Legal_Hold_Outcome;
         when Get_Legal_Hold_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded read-only GetObjectLegalHold parent with one HTTP child.
   type Get_Legal_Hold_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the package's established object-read defaults:
   --  us-east-1, path-style addressing, the shared S3 XML document limit,
   --  no cancellation source, and a 30-second synchronous wait.  They
   --  preserve existing client policy rather than adding legal-hold limits.
   --  Start or restart one bounded GetObjectLegalHold read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established operation
   procedure Get_Legal_Hold
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Legal_Hold_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetObjectLegalHold read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven legal-hold read
   function Get_Legal_Hold
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Legal_Hold_Operation;

   --  Consume one terminal GetObjectLegalHold operation.
   --  @param Operation Terminal legal-hold read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Legal_Hold_Operation;
      Result    : out Get_Legal_Hold_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one legal-hold mutation after terminal drain.
   --  Unknown outcomes require caller-selected GetObjectLegalHold
   --  reconciliation for the exact object version before any retry.
   --  @enum Legal_Hold_Mutation_Completed Complete response proves mutation
   --  @enum Legal_Hold_Mutation_Definitely_Not_Applied Exact rejection or
   --     non-admission proves the requested mutation was not applied
   --  @enum Legal_Hold_Mutation_Outcome_Unknown State must be reconciled
   --  @enum Legal_Hold_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Legal_Hold_Mutation_Disposition is
     (Legal_Hold_Mutation_Completed,
      Legal_Hold_Mutation_Definitely_Not_Applied,
      Legal_Hold_Mutation_Outcome_Unknown,
      Legal_Hold_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutObjectLegalHold mutation.
   --  @enum Put_Legal_Hold_Response_Available Modeled response exists
   --  @enum Put_Legal_Hold_Exchange_Failed No modeled response exists
   type Put_Legal_Hold_Result_Kind is
     (Put_Legal_Hold_Response_Available, Put_Legal_Hold_Exchange_Failed);

   --  Typed PutObjectLegalHold certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Legal_Hold_Result
     (Kind : Put_Legal_Hold_Result_Kind := Put_Legal_Hold_Exchange_Failed)
   is record
      Disposition : Legal_Hold_Mutation_Disposition :=
        Legal_Hold_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Legal_Hold_Response_Available =>
            Response : Low_Level.Put_Object_Legal_Hold_Outcome;
         when Put_Legal_Hold_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutObjectLegalHold parent owning its serialized XML document.
   type Put_Legal_Hold_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the package's established object-mutation
   --  defaults: us-east-1, path-style addressing, the shared S3 XML document
   --  limit, no cancellation source, and a 30-second synchronous wait.  They
   --  preserve existing client policy rather than adding legal-hold limits.
   --  Start or restart one nonreplaying PutObjectLegalHold mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Value Presence-preserving legal-hold document
   --  @param Parameters Complete modeled version, checksum, and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established operation
   procedure Put_Legal_Hold
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Legal_Hold_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutObjectLegalHold mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Value Presence-preserving legal-hold document
   --  @param Parameters Complete modeled version, checksum, and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven legal-hold mutation
   function Put_Legal_Hold
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Legal_Hold_Operation;

   --  Consume one terminal PutObjectLegalHold operation.
   --  @param Operation Terminal legal-hold mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Legal_Hold_Operation;
      Result    : out Put_Legal_Hold_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal GetObjectRetention read.
   --  @enum Get_Retention_Response_Available Modeled response exists
   --  @enum Get_Retention_Exchange_Failed No modeled response exists
   type Get_Retention_Result_Kind is
     (Get_Retention_Response_Available, Get_Retention_Exchange_Failed);

   --  Typed bounded GetObjectRetention response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Retention_Result
     (Kind : Get_Retention_Result_Kind := Get_Retention_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Retention_Response_Available =>
            Response : Low_Level.Get_Object_Retention_Outcome;
         when Get_Retention_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded read-only GetObjectRetention parent with one HTTP child.
   type Get_Retention_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the package's established object-read defaults:
   --  us-east-1, path-style addressing, the shared S3 XML document limit,
   --  no cancellation source, and a 30-second synchronous wait. They
   --  preserve existing client policy rather than adding retention limits.
   --  Start or restart one bounded GetObjectRetention read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established operation
   procedure Get_Retention
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Retention_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetObjectRetention read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven retention read
   function Get_Retention
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Retention_Operation;

   --  Consume one terminal GetObjectRetention operation.
   --  @param Operation Terminal retention read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Retention_Operation;
      Result    : out Get_Retention_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one retention mutation after terminal drain.
   --  Unknown outcomes require caller-selected GetObjectRetention
   --  reconciliation for the exact object version before any retry.
   --  @enum Retention_Mutation_Completed Complete response proves mutation
   --  @enum Retention_Mutation_Definitely_Not_Applied Exact rejection or
   --     non-admission proves the requested mutation was not applied
   --  @enum Retention_Mutation_Outcome_Unknown State must be reconciled
   --  @enum Retention_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Retention_Mutation_Disposition is
     (Retention_Mutation_Completed,
      Retention_Mutation_Definitely_Not_Applied,
      Retention_Mutation_Outcome_Unknown,
      Retention_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutObjectRetention mutation.
   --  @enum Put_Retention_Response_Available Modeled response exists
   --  @enum Put_Retention_Exchange_Failed No modeled response exists
   type Put_Retention_Result_Kind is
     (Put_Retention_Response_Available, Put_Retention_Exchange_Failed);

   --  Typed PutObjectRetention certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Retention_Result
     (Kind : Put_Retention_Result_Kind := Put_Retention_Exchange_Failed)
   is record
      Disposition : Retention_Mutation_Disposition :=
        Retention_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Retention_Response_Available =>
            Response : Low_Level.Put_Object_Retention_Outcome;
         when Put_Retention_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutObjectRetention parent owning its serialized XML document.
   type Put_Retention_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the package's established object-mutation
   --  defaults: us-east-1, path-style addressing, the shared S3 XML document
   --  limit, no cancellation source, and a 30-second synchronous wait. They
   --  preserve existing client policy rather than adding retention limits.
   --  Start or restart one nonreplaying PutObjectRetention mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Value Presence-preserving retention document
   --  @param Parameters Complete modeled checksum, bypass, and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established operation
   procedure Put_Retention
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Retention_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutObjectRetention mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Value Presence-preserving retention document
   --  @param Parameters Complete modeled checksum, bypass, and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven retention mutation
   function Put_Retention
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Retention_Operation;

   --  Consume one terminal PutObjectRetention operation.
   --  @param Operation Terminal retention mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Retention_Operation;
      Result    : out Put_Retention_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one conditional annotation deletion after terminal
   --  drain. Unknown outcomes require caller-selected read-only
   --  reconciliation for the exact object generation before any retry.
   --  @enum Annotation_Deletion_Completed Complete response proves deletion
   --  @enum Annotation_Deletion_Definitely_Not_Applied Exact rejection or
   --     non-admission proves the requested deletion was not applied
   --  @enum Annotation_Deletion_Outcome_Unknown State must be reconciled
   --  @enum Annotation_Deletion_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Object_Annotation_Deletion_Disposition is
     (Annotation_Deletion_Completed,
      Annotation_Deletion_Definitely_Not_Applied,
      Annotation_Deletion_Outcome_Unknown,
      Annotation_Deletion_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteObjectAnnotation mutation.
   --  @enum Delete_Object_Annotation_Response_Available Modeled response
   --     exists
   --  @enum Delete_Object_Annotation_Exchange_Failed No modeled response
   --     exists
   type Delete_Object_Annotation_Result_Kind is
     (Delete_Object_Annotation_Response_Available,
      Delete_Object_Annotation_Exchange_Failed);

   --  Typed DeleteObjectAnnotation certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Object_Annotation_Result
     (Kind : Delete_Object_Annotation_Result_Kind :=
        Delete_Object_Annotation_Exchange_Failed)
   is record
      Disposition : Object_Annotation_Deletion_Disposition :=
        Annotation_Deletion_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Object_Annotation_Response_Available =>
            Response : Low_Level.Delete_Object_Annotation_Outcome;
         when Delete_Object_Annotation_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteObjectAnnotation parent. The prepared request owns the
   --  exact annotation, version, requester, owner, and object-CAS values
   --  through Finish; its empty request source is never replayed.
   type Delete_Object_Annotation_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established low-level DeleteObjectAnnotation and provider defaults.
   --  Changing them would select different wire or resource behavior between
   --  the synchronous and composable forms.

   --  Start or restart one nonreplaying conditional annotation deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Annotation_Name Exact opaque annotation selector
   --  @param Parameters Complete generation, payer, owner, and CAS controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Annotation
     (Client          : not null access Flyology.HTTP.Client.Client;
      Origin          : Flyology.HTTP.Origin;
      Bucket          : String;
      Key             : String;
      Annotation_Name : String;
      Parameters      : Low_Level.Delete_Object_Annotation_Parameters;
      Identity        : Low_Level.Credentials;
      Deadline        : Flyology.HTTP.Client.Monotonic_Deadline;
      Region          : String := "us-east-1";
      Style           : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits          : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token           : access Flyology.Cancellation.Token := null;
      Operation       : in out Delete_Object_Annotation_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying conditional annotation deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Annotation_Name Exact opaque annotation selector
   --  @param Parameters Complete generation, payer, owner, and CAS controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Annotation
     (Set             : not null access
        Flyology.Operations.Completion_Set'Class;
      Client          : not null access Flyology.HTTP.Client.Client;
      Origin          : Flyology.HTTP.Origin;
      Bucket          : String;
      Key             : String;
      Annotation_Name : String;
      Parameters      : Low_Level.Delete_Object_Annotation_Parameters;
      Identity        : Low_Level.Credentials;
      Deadline        : Flyology.HTTP.Client.Monotonic_Deadline;
      Region          : String := "us-east-1";
      Style           : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits          : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token           : access Flyology.Cancellation.Token := null)
      return Delete_Object_Annotation_Operation;

   --  Consume one terminal DeleteObjectAnnotation operation.
   --  @param Operation Terminal annotation deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Object_Annotation_Operation;
      Result    : out Delete_Object_Annotation_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete one annotation by waiting on the same provider-owned operation
   --  used by composable callers. The request is never replayed.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Annotation_Name Exact opaque annotation selector
   --  @param Parameters Complete generation, payer, owner, and CAS controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Annotation
     (Client          : aliased in out Flyology.HTTP.Client.Client;
      Origin          : Flyology.HTTP.Origin;
      Bucket          : String;
      Key             : String;
      Annotation_Name : String;
      Parameters      : Low_Level.Delete_Object_Annotation_Parameters;
      Identity        : Low_Level.Credentials;
      Region          : String := "us-east-1";
      Style           : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout         : Duration := 30.0;
      Token           : access Flyology.Cancellation.Token := null;
      Limits          : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Object_Annotation_Result;

   --  What is known about one object-tag mutation after terminal drain.
   --  An explicit version permits same-version current-state observation;
   --  omission observes only the current version. Neither proves causation,
   --  upgrades mutation certainty, nor authorizes automatic replay.
   --  @enum Object_Tag_Mutation_Completed Complete response proves mutation
   --  @enum Object_Tag_Mutation_Definitely_Not_Applied Exact rejection or
   --     non-admission proves the requested mutation was not applied
   --  @enum Object_Tag_Mutation_Outcome_Unknown State must be reconciled
   --  @enum Object_Tag_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Object_Tag_Mutation_Disposition is
     (Object_Tag_Mutation_Completed,
      Object_Tag_Mutation_Definitely_Not_Applied,
      Object_Tag_Mutation_Outcome_Unknown,
      Object_Tag_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutObjectTagging mutation.
   --  @enum Put_Object_Tagging_Response_Available Modeled response exists
   --  @enum Put_Object_Tagging_Exchange_Failed No modeled response exists
   type Put_Object_Tagging_Result_Kind is
     (Put_Object_Tagging_Response_Available,
      Put_Object_Tagging_Exchange_Failed);

   --  Typed PutObjectTagging certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Object_Tagging_Result
     (Kind : Put_Object_Tagging_Result_Kind :=
        Put_Object_Tagging_Exchange_Failed)
   is record
      Disposition : Object_Tag_Mutation_Disposition :=
        Object_Tag_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Object_Tagging_Response_Available =>
            Response : Low_Level.Object_Tagging_Outcome;
         when Put_Object_Tagging_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutObjectTagging parent owning its serialized tag document.
   type Put_Object_Tagging_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying PutObjectTagging mutation.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Tags Complete validated tag set copied during preparation
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Put_Tags
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Tags       : Flyology.Object_Storage.Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Object_Tagging_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutObjectTagging mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Tags Complete validated tag set copied during preparation
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Put_Tags
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Tags       : Flyology.Object_Storage.Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Object_Tagging_Operation;

   --  Consume one terminal PutObjectTagging operation.
   --  @param Operation Terminal object-tag replacement
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Object_Tagging_Operation;
      Result    : out Put_Object_Tagging_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal GetObjectTagging read.
   --  @enum Get_Object_Tagging_Response_Available Modeled response exists
   --  @enum Get_Object_Tagging_Exchange_Failed No modeled response exists
   type Get_Object_Tagging_Result_Kind is
     (Get_Object_Tagging_Response_Available,
      Get_Object_Tagging_Exchange_Failed);

   --  Typed bounded GetObjectTagging response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Object_Tagging_Result
     (Kind : Get_Object_Tagging_Result_Kind :=
        Get_Object_Tagging_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Object_Tagging_Response_Available =>
            Response : Low_Level.Object_Tagging_Outcome;
         when Get_Object_Tagging_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded read-only GetObjectTagging parent with one HTTP child.
   type Get_Object_Tagging_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetObjectTagging read.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Get_Tags
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Object_Tagging_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetObjectTagging read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven read
   function Get_Tags
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Object_Tagging_Operation;

   --  Consume one terminal GetObjectTagging operation.
   --  @param Operation Terminal object-tag read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Object_Tagging_Operation;
      Result    : out Get_Object_Tagging_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal DeleteObjectTagging mutation.
   --  @enum Delete_Object_Tagging_Response_Available Modeled response exists
   --  @enum Delete_Object_Tagging_Exchange_Failed No modeled response exists
   type Delete_Object_Tagging_Result_Kind is
     (Delete_Object_Tagging_Response_Available,
      Delete_Object_Tagging_Exchange_Failed);

   --  Typed DeleteObjectTagging certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Object_Tagging_Result
     (Kind : Delete_Object_Tagging_Result_Kind :=
        Delete_Object_Tagging_Exchange_Failed)
   is record
      Disposition : Object_Tag_Mutation_Disposition :=
        Object_Tag_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Object_Tagging_Response_Available =>
            Response : Low_Level.Object_Tagging_Outcome;
         when Delete_Object_Tagging_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteObjectTagging parent with nonreplayable empty source.
   type Delete_Object_Tagging_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying DeleteObjectTagging mutation.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Delete_Tags
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Object_Tagging_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteObjectTagging mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Tags
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Object_Tagging_Operation;

   --  Consume one terminal DeleteObjectTagging operation.
   --  @param Operation Terminal object-tag deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Object_Tagging_Operation;
      Result    : out Delete_Object_Tagging_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   type List_Outcome_Kind is (Page_Available, List_Rejected);

   type List_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : S3.Listings.List_Objects_V2_Result;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when List_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   type List_V1_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : S3.Listings.List_Objects_Result;
            --  Exclusive marker for the next page. For delimiter listings it
            --  is the modeled NextMarker; otherwise it is the last object
            --  key, as required by ListObjects v1.
            Next_Marker : Ada.Strings.Unbounded.Unbounded_String;
            Has_Next_Marker : Boolean := False;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when List_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page with the backward-compatible S3 ListObjects v1
   --  operation. When Has_Next_Marker is true, pass Next_Marker as Marker to
   --  continue. The helper derives the marker from the final object when an
   --  S3 response is truncated without delimiter grouping.
   function List_V1_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Prefix   : String := "";
      Delimiter : String := "";
      Maximum  : S3.Core.Page_Size := 1_000;
      Marker   : String := "";
      URL_Encoding : Boolean := False;
      Include_Restore_Status : Boolean := False;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_V1_Outcome;

   --  List one bounded ListObjects v1 page by waiting on the composable
   --  owner-driven operation. This parameter-record overload preserves typed
   --  HTTP failure and admission information; the convenience overload above
   --  retains its established raising transport contract and marker fallback.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose current objects are listed
   --  @param Parameters Complete modeled v1 listing scope and marker
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function List_V1_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_Result;

   --  List one bounded page of current objects with S3 ListObjectsV2. Each
   --  completed page is an independent read-only service snapshot.
   --  Pass Page.Next_Continuation_Token from a truncated result to continue
   --  the same prefix/delimiter scope. Continuation tokens remain opaque;
   --  Start_After is an exclusive key used to select an initial page.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose current objects are listed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Prefix Optional byte prefix filter
   --  @param Delimiter Optional byte delimiter for CommonPrefixes grouping
   --  @param Maximum Maximum combined objects and prefixes in this page
   --  @param Continuation_Token Opaque token returned by the prior page
   --  @param Start_After Exclusive initial key; ignored by S3 when continuing
   --  @param Fetch_Owner Request an Owner structure for every object
   --  @param URL_Encoding Percent-encode returned keys, prefixes and delimiter
   --  @param Include_Restore_Status Request RestoreStatus where it exists
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return One typed page or a structured S3 rejection
   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Prefix   : String := "";
      Delimiter : String := "";
      Maximum  : S3.Core.Page_Size := 1_000;
      Continuation_Token : String := "";
      Start_After : String := "";
      Fetch_Owner : Boolean := False;
      URL_Encoding : Boolean := False;
      Include_Restore_Status : Boolean := False;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Outcome;

   --  List one bounded ListObjectsV2 page by waiting on the composable
   --  owner-driven operation. The operation retains its HTTP client and
   --  optional cancellation owner through terminal drain. This overload
   --  preserves typed HTTP failure and admission information; each completed
   --  page is an independent read-only service snapshot.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose current objects are listed
   --  @param Parameters Complete modeled listing scope and cursor
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_V2_Result;

   --  One complete typed version-listing page or structured S3 rejection.
   type List_Versions_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : S3.Versions.List_Object_Versions_Result;
            Next_Key_Marker : Ada.Strings.Unbounded.Unbounded_String;
            Next_Version_ID_Marker : Ada.Strings.Unbounded.Unbounded_String;
            Has_Next_Markers : Boolean := False;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when List_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page of object versions and delete markers. A
   --  Version_ID_Marker is valid only together with Key_Marker. When
   --  Has_Next_Markers is true, pass the outcome's Next_Key_Marker and
   --  Next_Version_ID_Marker to continue the same prefix/delimiter scope.
   --  Next_Key_Marker is decoded from the url response representation;
   --  version identifiers remain opaque.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose versions are listed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Prefix Optional byte prefix filter
   --  @param Delimiter Optional byte delimiter for CommonPrefixes grouping
   --  @param Maximum Maximum combined entries and prefixes in this page
   --  @param Key_Marker Key component of the paired pagination cursor
   --  @param Version_ID_Marker Version component of the paired cursor
   --  @param URL_Encoding Percent-encode returned keys, prefixes and delimiter
   --  @param Include_Restore_Status Request RestoreStatus where it exists
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return One typed page or a structured S3 rejection
   function List_Versions_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Prefix   : String := "";
      Delimiter : String := "";
      Maximum  : S3.Core.Page_Size := 1_000;
      Key_Marker : String := "";
      Version_ID_Marker : String := "";
      URL_Encoding : Boolean := False;
      Include_Restore_Status : Boolean := False;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Versions_Outcome;

   --  List one bounded ListObjectVersions page by waiting on the composable
   --  owner-driven operation. This parameter-record overload preserves typed
   --  HTTP failure and admission information; paired cursors remain in the
   --  modeled response for an explicit later Start.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose retained generations are listed
   --  @param Parameters Complete modeled scope and paired cursor
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function List_Versions_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Object_Versions_Result;

   subtype Complete_Put_Outcome is Low_Level.Put_Object_Outcome;
   subtype Conditional_Put_Outcome is Complete_Put_Outcome;

   --  Semantically bounded, backend-neutral controls supported by the
   --  complete-object S3 convenience call. Every dynamic field is validated
   --  against the shared/model wire limits before request admission.
   --  Checksum, when present, must be a direct
   --  Full_Object_Checksum with one canonical encoded digest. Tags and
   --  metadata retain the shared backend limits.
   type Complete_Put_Options is record
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type          : Ada.Strings.Unbounded.Unbounded_String;
      Metadata              : Object_Metadata;
      Tags                  : Object_Tag_Set;
      Checksum              : Checksum_Information;
      Conditions            : Write_Conditions;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Default_Complete_Put_Options : constant Complete_Put_Options :=
     (Content_MD5           => Ada.Strings.Unbounded.Null_Unbounded_String,
      Content_Type          => Ada.Strings.Unbounded.Null_Unbounded_String,
      Metadata              => Empty_Object_Metadata,
      Tags                  => Empty_Object_Tags,
      Checksum              => No_Checksum_Information,
      Conditions            => Default_Write_Conditions,
      Expected_Bucket_Owner => Ada.Strings.Unbounded.Null_Unbounded_String);

   --  Publish one complete object through the typed PutObject client. Source
   --  must be one-shot: this call never opts into the blocking HTTP client's
   --  stale-connection replay path. Expected S3 rejections are returned;
   --  after execution begins any propagated timeout, cancellation, transport,
   --  or invalid-response exception is conservatively an unknown publication
   --  outcome and must be reconciled by a generation-bound read. No mutation
   --  is retried by this helper.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination bucket
   --  @param Key Exact destination object key
   --  @param Source One-shot complete request body, borrowed for this call
   --  @param Payload_SHA256 Exact lowercase body digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only while signing this request
   --  @param Options Bounded metadata, tags, checksum, conditions, and owner
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Blocking HTTP exchange budget
   --  @param Token Optional cancellation source
   --  @return Complete PutObject result or structured S3 rejection
   --  @exception Low_Level.Invalid_Request Source or options are invalid
   function Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Options  : Complete_Put_Options := Default_Complete_Put_Options;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Complete_Put_Outcome;

   --  Publish one complete object by waiting on the composable PutObject
   --  state machine. The payload token moves for the duration of the exchange
   --  and is restored before return or propagation of an unexpected local
   --  exception. Expected transport and service outcomes retain typed
   --  publication certainty; this helper never retries.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination bucket
   --  @param Key Exact destination object key
   --  @param Payload_Buffer Acquired complete-object bytes moved until return
   --  @param Payload_SHA256 Exact lowercase body digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only while signing this request
   --  @param Options Bounded metadata, tags, checksum, conditions, and owner
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Blocking wait budget projected to one absolute deadline
   --  @param Token Optional cancellation source
   --  @return Typed publication certainty and terminal PutObject result
   function Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Options  : Complete_Put_Options := Default_Complete_Put_Options;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Result
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Publish a complete object only when no current object exists. Source
   --  must be a one-shot Request_Body_Source, not a rewindable source; this
   --  prevents the blocking HTTP client from replaying an ambiguous
   --  conditional mutation. Expected rejections, including HTTP 412, are
   --  returned in the typed low-level outcome. Once execution begins, any
   --  propagated exception must conservatively be treated as an unknown
   --  publication outcome and reconciled with Get_Whole; this function does
   --  not classify admission certainty.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination bucket
   --  @param Key Exact destination object key
   --  @param Source One-shot complete request body, borrowed for this call
   --  @param Payload_SHA256 Exact lowercase body digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Content_Type Optional object content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Blocking HTTP exchange budget
   --  @param Token Optional cancellation source
   --  @return Complete PutObject result or structured S3 rejection
   --  @exception Low_Level.Invalid_Request Source is rewindable or invalid
   function Put_If_Absent
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Outcome;

   --  Blocking buffer-owned conditional PUT implemented by waiting on the
   --  composable operation. Unlike the legacy one-shot source overload, its
   --  result preserves HTTP admission and publication certainty. Its defaults
   --  intentionally match the established source-based overload; changing
   --  them would be a source and wire-compatibility change.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Payload_Buffer Acquired bytes restored before return
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed publication certainty and terminal result
   function Put_If_Absent
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Result
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Replace a complete current object only when its opaque HTTP entity tag
   --  exactly matches Expected_Entity_Tag. Pass the quoted ETag returned by
   --  Put_If_Absent, Put_If_Matches, Get_Whole, or HeadObject unchanged.
   --  Source and exception certainty follow Put_If_Absent.
   function Put_If_Matches
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Outcome;

   --  Blocking buffer-owned compare-and-swap PUT implemented by waiting on
   --  the composable operation and preserving its exact certainty mapping.
   --  Defaults match the established source-based overload so buffer
   --  ownership does not select different wire policy.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Expected_Entity_Tag Exact strong opaque generation validator
   --  @param Payload_Buffer Acquired bytes restored before return
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed publication certainty and terminal result
   function Put_If_Matches
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Result
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   type Whole_Get_Outcome_Kind is (Whole_Object_Read, Whole_Get_Rejected);

   --  A complete GetObject body and its response metadata from one HTTP
   --  exchange. Result.Entity_Tag and Result.Version_ID remain separate,
   --  opaque provider generation values.
   type Whole_Get_Outcome
     (Kind : Whole_Get_Outcome_Kind := Whole_Get_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Whole_Object_Read =>
            Result : Low_Level.Get_Object_Result;
            Object_Bytes : Flyology.Bytes.Unbounded_Bytes;
         when Whole_Get_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Read one complete object and its exact metadata from the same immutable
   --  S3 response. Expected_Entity_Tag binds reconciliation to an opaque ETag;
   --  Version_ID independently selects a provider version when supported.
   --  Maximum bounds retained bytes. A larger or malformed successful body
   --  raises Response_Too_Large or Low_Level.Invalid_Response respectively.
   function Get_Whole
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Maximum  : Natural;
      Identity : Low_Level.Credentials;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Whole_Get_Outcome;

   --  Blocking bounded same-response GET implemented by waiting on the
   --  composable operation. Destination contains bytes only for Object_Opened.
   --  Defaults match the established owned-bytes overload so the bounded
   --  representation does not select different wire policy.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Destination Acquired bounded output buffer
   --  @param Identity Credentials used only during signing
   --  @param Expected_Entity_Tag Optional exact strong ETag validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed same-response metadata or bounded exchange failure
   function Get_Whole
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : aliased in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Whole_Get_Result
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Read exactly one generation-bound byte interval by waiting on the
   --  composable range operation. Requested may be bounded, open-ended, or a
   --  suffix range. A successful response returns both the bytes and the
   --  resolved interval from the same 206 response; Destination is empty for
   --  every rejection or exchange failure.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Requested Typed single byte range
   --  @param Destination Acquired bounded output buffer
   --  @param Identity Credentials used only during signing
   --  @param Expected_Entity_Tag Required exact strong generation validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed response and resolved interval or bounded failure
   function Get_Range
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : aliased in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Range_Get_Result
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Execute one bodyless HeadObject by waiting on the composable operation.
   --  Parameters is the complete modeled HeadObject control surface and is
   --  copied before the operation starts.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled HeadObject controls
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed complete response or bounded exchange failure
   function Head_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Result;

   type Delete_Outcome_Kind is (Object_Removed, Delete_Rejected);

   type Delete_Outcome
     (Kind : Delete_Outcome_Kind := Delete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Removed =>
            Delete_Marker   : Low_Level.Optional_Boolean;
            Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when Delete_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Execute one DeleteObject by waiting on the composable operation. This
   --  result-type overload preserves HTTP admission and deletion certainty;
   --  selecting the established Delete_Outcome overload preserves its
   --  existing raising transport contract. All parameters and defaults are
   --  identical so composition does not select different S3 wire policy.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Optional exact version to delete permanently
   --  @param If_Match Optional entity-tag precondition
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @param MFA Optional root-owner MFA device and credential value
   --  @param Bypass_Governance_Retention Optional governance bypass request
   --  @param If_Match_Last_Modified_Time Optional directory-bucket predicate
   --  @param If_Match_Size Optional directory-bucket size predicate
   --  @return Typed deletion certainty and terminal response or failure
   function Delete
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := "";
      If_Match : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      MFA      : String := "";
      Bypass_Governance_Retention : Low_Level.Optional_Boolean :=
        (Is_Set => False, Value => False);
      If_Match_Last_Modified_Time : String := "";
      If_Match_Size : Low_Level.Optional_Byte_Count :=
        (Is_Set => False, Value => 0))
      return Delete_Result;

   --  Execute one DeleteObjects request by waiting on the composable
   --  operation. Request is serialized and copied before admission; the
   --  resulting one-shot body is never replayed. A processed result retains
   --  the complete per-entry Deleted/Error response. Unknown outcomes require
   --  read-only reconciliation of every requested generation before retry.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose selected entries are deleted
   --  @param Request Bounded ordered delete request
   --  @param Parameters Complete modeled DeleteObjects controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed batch certainty and per-entry response or failure
   function Delete_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Objects_Result;

   --  Delete one object or a specific object version. S3 treats a missing
   --  unversioned key as a successful idempotent deletion. Every modeled
   --  DeleteObject control is available here; optional boolean/count values
   --  distinguish an omitted header from an explicitly supplied false or
   --  zero value. Transport, timeout, and cancellation exceptions after
   --  request admission may mean the deletion was published. The call is not
   --  transparently replayed; reconcile the exact key/generation before any
   --  conditional retry.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Optional exact version to delete permanently
   --  @param If_Match Optional entity-tag precondition
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @param MFA Optional root-owner MFA device and credential value
   --  @param Bypass_Governance_Retention Optional governance bypass request
   --  @param If_Match_Last_Modified_Time Optional directory-bucket predicate
   --  @param If_Match_Size Optional directory-bucket size predicate
   --  @return Modeled deletion headers or structured S3 rejection
   function Delete
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := "";
      If_Match : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      MFA      : String := "";
      Bypass_Governance_Retention : Low_Level.Optional_Boolean :=
        (Is_Set => False, Value => False);
      If_Match_Last_Modified_Time : String := "";
      If_Match_Size : Low_Level.Optional_Byte_Count :=
        (Is_Set => False, Value => 0))
      return Delete_Outcome;

   --  Read the selected generation's legal hold by waiting on the same
   --  bounded owner-driven operation exposed above.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Legal_Hold
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Legal_Hold_Result;

   --  Replace the selected generation's legal hold exactly once by waiting
   --  on the same nonreplaying owner-driven operation exposed above.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Value Presence-preserving legal-hold document copied at start
   --  @param Parameters Complete modeled version, checksum, and controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Put_Legal_Hold
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Legal_Hold_Result;

   --  Read the selected generation's retention state by waiting on the same
   --  bounded owner-driven operation exposed above.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Retention
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Retention_Result;

   --  Replace the selected generation's retention state exactly once by
   --  waiting on the same nonreplaying owner-driven operation exposed above.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object generation
   --  @param Key Exact object key
   --  @param Value Presence-preserving retention document copied at start
   --  @param Parameters Complete modeled checksum, bypass, and controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Put_Retention
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Retention_Result;

   --  Shape of a completed synchronous object-tagging call.
   --  @enum Tags_Replaced The complete tag set was replaced
   --  @enum Tags_Read The selected object-version tag set was read
   --  @enum Tags_Cleared The selected object-version tag set was cleared
   --  @enum Tagging_Rejected The service returned a structured S3 rejection
   type Tagging_Outcome_Kind is
     (Tags_Replaced, Tags_Read, Tags_Cleared, Tagging_Rejected);

   --  Synchronous object-tagging response or structured S3 rejection.
   --  @field Kind Selects the successful or rejected variant
   --  @field Status HTTP status returned by the completed exchange
   --  @field Result Complete modeled object-tagging response
   --  @field Error Structured S3 rejection
   type Tagging_Outcome
     (Kind : Tagging_Outcome_Kind := Tagging_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Replaced | Tags_Read | Tags_Cleared =>
            Result : Low_Level.Object_Tagging_Result;
         when Tagging_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Replace the complete tag set. Empty Tags clears the set, while
   --  Delete_Tags provides the explicit S3 deletion operation.
   --  This parameter-record overload waits on the same owner-driven
   --  composable operation and preserves admission and mutation certainty.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Tags Complete validated tag set copied during preparation
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Put_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Tags : Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Put_Object_Tagging_Result;

   --  Replace the complete selected object-version tag set synchronously.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Tags Complete validated tag set copied during preparation
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Exact object-version selector, or current if empty
   --  @param Expected_Bucket_Owner Required bucket-owner account, if any
   --  @param Request_Payer Requester-pays acknowledgement, if any
   --  @param Checksum_Algorithm Optional modeled SDK checksum algorithm
   --  @param Timeout Whole synchronous operation budget
   --  @param Token Optional cancellation source
   --  @return Completed modeled response or structured S3 rejection
   function Put_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Tags : Object_Tag_Set; Identity : Low_Level.Credentials;
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Request_Payer : String := ""; Checksum_Algorithm : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome;

   --  Read the exact selected object-version tag snapshot by waiting on the
   --  bounded composable operation.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Get_Object_Tagging_Result;

   --  Read the selected object-version tag set synchronously.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Exact object-version selector, or current if empty
   --  @param Expected_Bucket_Owner Required bucket-owner account, if any
   --  @param Request_Payer Requester-pays acknowledgement, if any
   --  @param Timeout Whole synchronous operation budget
   --  @param Token Optional cancellation source
   --  @return Completed modeled response or structured S3 rejection
   function Get_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Request_Payer : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome;

   --  Delete the exact selected object-version tag set by waiting on the
   --  nonreplaying composable mutation. The result preserves admission and
   --  mutation certainty; no outcome authorizes automatic retry.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled version and request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Object_Tagging_Result;

   --  Clear the selected object-version tag set synchronously.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the selected object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Exact object-version selector, or current if empty
   --  @param Expected_Bucket_Owner Required bucket-owner account, if any
   --  @param Timeout Whole synchronous operation budget
   --  @param Token Optional cancellation source
   --  @return Completed modeled response or structured S3 rejection
   function Delete_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome;

   subtype Get_Attributes_Outcome is
     Low_Level.Get_Object_Attributes_Outcome;

   --  Retrieve selected object metadata by waiting on the composable
   --  owner-driven operation. This parameter-record overload preserves typed
   --  HTTP failure and admission information and is restart-compatible with
   --  the corresponding owner-driven operation in this provider.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Parameters Complete modeled selection and controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Attributes
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Object_Attributes_Result;

   --  Retrieve selected object metadata without downloading the body. By
   --  default all five root attribute groups are requested. Numeric presence
   --  flags allow callers to omit pagination headers independently of their
   --  values.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Attributes Requested root-level result groups
   --  @param Version_ID Optional exact object version
   --  @param Max_Parts Object-parts page size when Has_Max_Parts is true
   --  @param Has_Max_Parts Whether to send Max_Parts
   --  @param Part_Number_Marker Exclusive completed-part marker
   --  @param Has_Part_Number_Marker Whether to send Part_Number_Marker
   --  @param SSE_Customer_Algorithm Optional SSE-C algorithm
   --  @param SSE_Customer_Key Optional base64 SSE-C key; HTTPS only
   --  @param SSE_Customer_Key_MD5 Optional base64 SSE-C key digest
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled result or structured S3 rejection
   function Get_Attributes
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Attributes : S3.Attributes.Attribute_Selection := (others => True);
      Version_ID : String := "";
      Max_Parts : S3.Core.Page_Size := 1_000;
      Has_Max_Parts : Boolean := False;
      Part_Number_Marker : S3.Attributes.Part_Marker_Value := 0;
      Has_Part_Number_Marker : Boolean := False;
      SSE_Customer_Algorithm : String := "";
      SSE_Customer_Key : String := "";
      SSE_Customer_Key_MD5 : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Attributes_Outcome;

   --  Shape of a terminal ListObjectAnnotations read.
   --  @enum List_Object_Annotations_Response_Available Modeled response exists
   --  @enum List_Object_Annotations_Exchange_Failed No complete response
   type List_Object_Annotations_Result_Kind is
     (List_Object_Annotations_Response_Available,
      List_Object_Annotations_Exchange_Failed);

   --  Typed annotation page response or bounded composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Object_Annotations_Result is record
      Kind        : List_Object_Annotations_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.List_Object_Annotations_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded ListObjectAnnotations read with one hidden HTTP child. It
   --  owns its signed request and response through typed Finish.
   type List_Object_Annotations_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one object-annotation page read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the annotated object
   --  @param Key Complete object key
   --  @param Parameters Complete modeled pagination and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established annotation read
   procedure List_Annotations
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.List_Object_Annotations_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out List_Object_Annotations_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one owner-driven object-annotation page read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the annotated object
   --  @param Key Complete object key
   --  @param Parameters Complete modeled pagination and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven annotation read
   function List_Annotations
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.List_Object_Annotations_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return List_Object_Annotations_Operation;

   --  Consume one terminal object-annotation page read.
   --  @param Operation Terminal annotation read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Object_Annotations_Operation;
      Result    : out List_Object_Annotations_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one object-annotation page by waiting on the same owner-driven
   --  state machine exposed to composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket containing the annotated object
   --  @param Key Complete object key
   --  @param Parameters Complete modeled pagination and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function List_Annotations
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.List_Object_Annotations_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return List_Object_Annotations_Result;

private

   --  @exclude
   type Get_Object_ACL_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Object_ACL_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Object_ACL_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Object_ACL_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Object_ACL_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Object_ACL_Operation);

   type Get_Legal_Hold_Operation
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
      Final_Result : Get_Legal_Hold_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Legal_Hold_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Legal_Hold_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Legal_Hold_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Legal_Hold_Operation);

   type Put_Legal_Hold_Operation
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
      Final_Result : Put_Legal_Hold_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Put_Legal_Hold_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Legal_Hold_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Legal_Hold_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Legal_Hold_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Legal_Hold_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Legal_Hold_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Legal_Hold_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Legal_Hold_Operation);

   type Get_Retention_Operation
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
      Final_Result : Get_Retention_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Retention_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Retention_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Retention_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Retention_Operation);

   type Put_Retention_Operation
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
      Final_Result : Put_Retention_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Put_Retention_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Retention_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Retention_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Retention_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Retention_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Retention_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Retention_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Retention_Operation);

   --  @exclude
   type Put_Object_Tagging_Operation
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
      Requested_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Final_Result : Put_Object_Tagging_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Put_Object_Tagging_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Object_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Object_Tagging_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Object_Tagging_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Object_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Object_Tagging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Object_Tagging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Object_Tagging_Operation);

   --  @exclude
   type Get_Object_Tagging_Operation
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
      Requested_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Final_Result : Get_Object_Tagging_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Object_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Object_Tagging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Object_Tagging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Object_Tagging_Operation);

   --  @exclude
   type Delete_Object_Tagging_Operation
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
      Requested_Version_ID : Ada.Strings.Unbounded.Unbounded_String;
      Final_Result : Delete_Object_Tagging_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Object_Tagging_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Object_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Object_Tagging_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Object_Tagging_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Object_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Object_Tagging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Object_Tagging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Object_Tagging_Operation);

   --  @exclude
   type Delete_Object_Annotation_Operation
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
      XML_Limits : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Final_Result : Delete_Object_Annotation_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Object_Annotation_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Object_Annotation_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Object_Annotation_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Object_Annotation_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Object_Annotation_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Object_Annotation_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Object_Annotation_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Object_Annotation_Operation);

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
   type List_Objects_Operation
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
      Final_Result : List_Objects_Result;
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
   type List_Object_Versions_Operation
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
      Final_Result : List_Object_Versions_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Object_Attributes_Operation
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
      Final_Result : Get_Object_Attributes_Result;
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
   overriding function Declared_Length
     (Item : Conditional_Put_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Conditional_Put_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Conditional_Put_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Conditional_Put_Operation);
   overriding procedure Write
     (Item : in out Conditional_Put_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Conditional_Put_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Conditional_Put_Operation);
   overriding procedure Finalize (Item : in out Conditional_Put_Operation);
   overriding procedure Drive
     (Item : in out Whole_Get_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Whole_Get_Operation);
   overriding procedure Finalize (Item : in out Whole_Get_Operation);
   overriding procedure Drive
     (Item : in out Range_Get_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Range_Get_Operation);
   overriding procedure Finalize (Item : in out Range_Get_Operation);
   overriding procedure Write
     (Item : in out Head_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Head_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Head_Operation);
   overriding procedure Finalize (Item : in out Head_Operation);
   overriding function Declared_Length
     (Item : Delete_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source (Item : in out Delete_Operation);
   overriding procedure Write
     (Item : in out Delete_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Operation);
   overriding procedure Finalize (Item : in out Delete_Operation);
   overriding function Declared_Length
     (Item : Delete_Objects_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Objects_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Objects_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Delete_Objects_Operation);
   overriding procedure Write
     (Item : in out Delete_Objects_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Objects_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Objects_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Objects_Operation);
   overriding procedure Write
     (Item : in out List_Objects_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out List_Objects_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out List_Objects_Operation);
   overriding procedure Finalize
     (Item : in out List_Objects_Operation);
   overriding procedure Write
     (Item : in out List_Objects_V2_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out List_Objects_V2_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out List_Objects_V2_Operation);
   overriding procedure Finalize
     (Item : in out List_Objects_V2_Operation);
   overriding procedure Write
     (Item : in out List_Object_Versions_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out List_Object_Versions_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out List_Object_Versions_Operation);
   overriding procedure Finalize
     (Item : in out List_Object_Versions_Operation);
   overriding procedure Write
     (Item : in out Get_Object_Attributes_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Object_Attributes_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Object_Attributes_Operation);
   overriding procedure Finalize
     (Item : in out Get_Object_Attributes_Operation);

   --  @exclude
   function Decode_List_Object_Annotations_Response
     (Status     : Flyology.HTTP.Status_Code;
      Response   : Flyology.HTTP.Client.Response;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return List_Object_Annotations_Result;

   --  @exclude
   function Normalize_List_Object_Annotations_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return List_Object_Annotations_Result;

   --  @exclude
   package List_Object_Annotation_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => List_Object_Annotations_Result,
        Operation_Name    => "ListObjectAnnotations",
        Start_Exchange    => Low_Level.List_Object_Annotations,
        Decode_Response   => Decode_List_Object_Annotations_Response,
        Normalize_Failure => Normalize_List_Object_Annotations_Failure);

   --  @exclude
   type List_Object_Annotations_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : List_Object_Annotation_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out List_Object_Annotations_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out List_Object_Annotations_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out List_Object_Annotations_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out List_Object_Annotations_Operation);

   function Normalize_List_Objects_Response
     (Value     : Low_Level.List_Objects_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Objects_Result;
   function Normalize_List_Objects_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Objects_Result;
   function Normalize_Put_Response
     (Value     : Low_Level.Put_Object_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Conditional_Put_Result;
   function Normalize_Put_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Required  : Flyology.HTTP.Client.Length_Requirement := (others => <>);
      Detail    : String := "") return Conditional_Put_Result;
   function Normalize_Delete_Response
     (Value     : Low_Level.Delete_Object_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Result;
   function Normalize_Delete_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Result;
   function Normalize_Delete_Objects_Response
     (Value     : Low_Level.Delete_Objects_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Objects_Result;
   function Normalize_Delete_Objects_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Objects_Result;
   function Normalize_List_Objects_V2_Response
     (Value     : Low_Level.List_Objects_V2_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Objects_V2_Result;
   function Normalize_List_Objects_V2_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Objects_V2_Result;
   function Normalize_List_Object_Versions_Response
     (Value     : Low_Level.List_Object_Versions_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Object_Versions_Result;
   function Normalize_List_Object_Versions_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Object_Versions_Result;
   function Normalize_Get_Object_Attributes_Response
     (Value     : Low_Level.Get_Object_Attributes_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Object_Attributes_Result;
   function Normalize_Get_Object_Attributes_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Object_Attributes_Result;
   --  @exclude
   function Normalize_Get_Object_ACL_Response
     (Value     : Low_Level.Get_Object_ACL_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Object_ACL_Result;
   --  @exclude
   function Normalize_Get_Object_ACL_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Object_ACL_Result;
   function Normalize_Get_Legal_Hold_Response
     (Value     : Low_Level.Get_Object_Legal_Hold_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Legal_Hold_Result;
   function Normalize_Get_Legal_Hold_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Legal_Hold_Result;
   function Normalize_Put_Legal_Hold_Response
     (Value     : Low_Level.Put_Object_Legal_Hold_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Legal_Hold_Result;
   function Normalize_Put_Legal_Hold_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Legal_Hold_Result;
   function Normalize_Get_Retention_Response
     (Value     : Low_Level.Get_Object_Retention_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Retention_Result;
   function Normalize_Get_Retention_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Retention_Result;
   function Normalize_Put_Retention_Response
     (Value     : Low_Level.Put_Object_Retention_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Retention_Result;
   function Normalize_Put_Retention_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Retention_Result;
   --  @exclude
   function Normalize_Put_Object_Tagging_Response
     (Value     : Low_Level.Object_Tagging_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Object_Tagging_Result;
   --  @exclude
   function Normalize_Put_Object_Tagging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Object_Tagging_Result;
   --  @exclude
   function Normalize_Get_Object_Tagging_Response
     (Value     : Low_Level.Object_Tagging_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Object_Tagging_Result;
   --  @exclude
   function Normalize_Get_Object_Tagging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Object_Tagging_Result;
   --  @exclude
   function Normalize_Delete_Object_Tagging_Response
     (Value     : Low_Level.Object_Tagging_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Object_Tagging_Result;
   --  @exclude
   function Normalize_Delete_Object_Tagging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Object_Tagging_Result;
   --  @exclude
   function Normalize_Delete_Object_Annotation_Response
     (Value     : Low_Level.Delete_Object_Annotation_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Object_Annotation_Result;
   --  @exclude
   function Normalize_Delete_Object_Annotation_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Object_Annotation_Result;

end Flyology.Object_Storage.Client.Objects;
