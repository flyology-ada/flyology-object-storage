with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.IO;
with Flyology.Operations;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Bounded_REST_XML_Reads;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Encryption;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.Notifications;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.Replication;
with Flyology.Object_Storage.S3.XML;
with Flyology.Object_Storage.Tags;

--  High-level bucket operations over a configured Flyology HTTP client.
package Flyology.Object_Storage.Client.Buckets is

   --  Shape of a terminal service-level ListBuckets read.
   --  @enum List_Buckets_Response_Available Modeled S3 response exists
   --  @enum List_Buckets_Exchange_Failed No complete response exists
   type List_Buckets_Result_Kind is
     (List_Buckets_Response_Available, List_Buckets_Exchange_Failed);

   --  Typed bounded ListBuckets response or composable HTTP failure.
   --  Admission is retained for diagnostics; bucket discovery is read-only
   --  and each page remains an independent service snapshot.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Buckets_Result
     (Kind : List_Buckets_Result_Kind := List_Buckets_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when List_Buckets_Response_Available =>
            Response : Low_Level.List_Buckets_Outcome;
         when List_Buckets_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded ListBuckets parent with one hidden HTTP child. The
   --  operation owns its prepared request and retained response bytes through
   --  terminal Finish; no borrowed request input is retained.
   type List_Buckets_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded service-level ListBuckets operation.
   --  Request validation and signing finish before start.
   --  @param Operation Fresh or consumed established listing operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Parameters Complete modeled bucket listing scope and cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  Region and addressing defaults preserve the established synchronous
   --  ListBuckets request policy and source compatibility.
   procedure List_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Buckets_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded service-level ListBuckets operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Parameters Complete modeled bucket listing scope and cursor
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ListBuckets operation
   --  Region and addressing defaults preserve the established synchronous
   --  ListBuckets request policy and source compatibility.
   function List_Page
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Buckets_Operation;

   --  Consume one terminal ListBuckets operation.
   --  @param Operation Terminal service-level listing request
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Buckets_Operation;
      Result    : out List_Buckets_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one CreateBucket mutation after terminal drain.
   --  Unknown creation requires caller-selected HeadBucket reconciliation of
   --  ownership and location before any retry.
   --  @enum Bucket_Creation_Completed Complete validated 200 proves creation
   --  @enum Bucket_Definitely_Not_Created Non-admission or exact rejection
   --  @enum Bucket_Creation_Outcome_Unknown Creation must be reconciled
   --  @enum Bucket_Creation_Cancelled_Before_Admission Cancellation preceded
   --     possible server admission
   type Bucket_Creation_Disposition is
     (Bucket_Creation_Completed,
      Bucket_Definitely_Not_Created,
      Bucket_Creation_Outcome_Unknown,
      Bucket_Creation_Cancelled_Before_Admission);

   --  Shape of a terminal CreateBucket mutation.
   --  @enum Create_Bucket_Response_Available Complete modeled response exists
   --  @enum Create_Bucket_Exchange_Failed No complete modeled response exists
   type Create_Bucket_Result_Kind is
     (Create_Bucket_Response_Available, Create_Bucket_Exchange_Failed);

   --  Typed bucket-creation certainty plus the modeled S3 response or exact
   --  composable HTTP failure. No outcome authorizes automatic retry.
   --  @field Kind Result shape
   --  @field Disposition Bucket-creation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Create_Bucket_Result
     (Kind : Create_Bucket_Result_Kind := Create_Bucket_Exchange_Failed)
   is record
      Disposition : Bucket_Creation_Disposition :=
        Bucket_Creation_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Create_Bucket_Response_Available =>
            Response : Low_Level.Create_Bucket_Outcome;
         when Create_Bucket_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot CreateBucket parent with one hidden HTTP child. Serialized
   --  configuration and signing inputs are copied into the prepared request
   --  before start returns; the source cannot be replayed after admission.
   type Create_Bucket_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded non-replaying CreateBucket mutation.
   --  @param Operation Fresh or consumed established creation operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket New bucket name
   --  @param Parameters Complete modeled CreateBucket controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Create
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Create_Bucket_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded non-replaying CreateBucket mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket New bucket name
   --  @param Parameters Complete modeled CreateBucket controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven CreateBucket mutation
   function Create
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Bucket_Operation;

   --  Consume one terminal CreateBucket mutation.
   --  @param Operation Terminal bucket creation request
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Create_Bucket_Operation;
      Result    : out Create_Bucket_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one DeleteBucket mutation after terminal drain.
   --  An unknown result requires caller-selected HeadBucket reconciliation
   --  before any retry.
   --  @enum Bucket_Deletion_Completed Complete validated 204 proves deletion
   --  @enum Bucket_Definitely_Not_Deleted Exact non-admission or rejection
   --     proves this request did not delete the bucket
   --  @enum Bucket_Deletion_Outcome_Unknown State must be reconciled
   --  @enum Bucket_Deletion_Cancelled_Before_Admission Cancellation preceded
   --     possible server admission
   type Bucket_Deletion_Disposition is
     (Bucket_Deletion_Completed,
      Bucket_Definitely_Not_Deleted,
      Bucket_Deletion_Outcome_Unknown,
      Bucket_Deletion_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucket mutation.
   --  @enum Delete_Bucket_Response_Available Complete modeled response exists
   --  @enum Delete_Bucket_Exchange_Failed No complete modeled response exists
   type Delete_Bucket_Result_Kind is
     (Delete_Bucket_Response_Available, Delete_Bucket_Exchange_Failed);

   --  Typed bucket-deletion certainty plus the modeled S3 response or exact
   --  composable HTTP failure. No outcome authorizes automatic retry.
   --  @field Kind Result shape
   --  @field Disposition Bucket-deletion certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Result
     (Kind : Delete_Bucket_Result_Kind := Delete_Bucket_Exchange_Failed)
   is record
      Disposition : Bucket_Deletion_Disposition :=
        Bucket_Deletion_Outcome_Unknown;
      Failure     : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission   : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Response_Available =>
            Response : Low_Level.Delete_Bucket_Outcome;

         when Delete_Bucket_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucket parent with one hidden HTTP child. The operation
   --  owns its prepared request and supplies a non-replayable empty source so
   --  a reused-transport failure cannot transparently repeat the mutation.
   --  Compatibility contract: region and addressing defaults match the
   --  established synchronous Delete overload. The composable forms replace
   --  its established 30-second timeout only with a caller-supplied deadline.
   type Delete_Bucket_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token)
   is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one non-replaying DeleteBucket mutation.
   --  @param Operation Fresh or consumed established deletion operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Empty bucket to delete
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Delete
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one non-replaying DeleteBucket mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Empty bucket to delete
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven bucket deletion
   function Delete
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Operation;

   --  Consume one terminal DeleteBucket operation.
   --  @param Operation Terminal bucket deletion request
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Operation;
      Result    : out Delete_Bucket_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal bodyless HeadBucket read.
   --  @enum Head_Bucket_Response_Available Modeled S3 response exists
   --  @enum Head_Bucket_Exchange_Failed No complete response exists
   type Head_Bucket_Result_Kind is
     (Head_Bucket_Response_Available, Head_Bucket_Exchange_Failed);

   --  Typed bodyless HeadBucket response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Head_Bucket_Result
     (Kind : Head_Bucket_Result_Kind := Head_Bucket_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Head_Bucket_Response_Available =>
            Response : Low_Level.Head_Bucket_Outcome;
         when Head_Bucket_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bodyless HeadBucket parent with one hidden HTTP child. The operation
   --  owns its signed request through terminal Finish and retains no borrowed
   --  request input.
   type Head_Bucket_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bodyless HeadBucket operation.
   --  @param Operation Fresh or consumed established HeadBucket operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose availability is probed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Head
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Head_Bucket_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bodyless HeadBucket operation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose availability is probed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven HeadBucket operation
   function Head
     (Set      : not null access Flyology.Operations.Completion_Set'Class;
      Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Operation;

   --  Consume one terminal HeadBucket operation.
   --  @param Operation Terminal bodyless bucket probe
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Head_Bucket_Operation;
      Result    : out Head_Bucket_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal GetBucketLocation read.
   --  @enum Get_Bucket_Location_Response_Available Modeled response exists
   --  @enum Get_Bucket_Location_Exchange_Failed No complete response exists
   type Get_Bucket_Location_Result_Kind is
     (Get_Bucket_Location_Response_Available,
      Get_Bucket_Location_Exchange_Failed);

   --  Typed GetBucketLocation response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Location_Result
     (Kind : Get_Bucket_Location_Result_Kind :=
        Get_Bucket_Location_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Location_Response_Available =>
            Response : Low_Level.Get_Bucket_Location_Outcome;
         when Get_Bucket_Location_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketLocation parent with one hidden HTTP child. The
   --  operation owns its signed request and retained XML through terminal
   --  Finish, with no borrowed request input after signing.
   --  Compatibility contract: region and addressing defaults match the
   --  established synchronous Get_Location overload. Composable forms replace
   --  its established 30-second timeout with a caller-supplied deadline.
   type Get_Bucket_Location_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one GetBucketLocation read.
   --  @param Operation Fresh or consumed established location operation
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose location is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Get_Location
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Location_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one GetBucketLocation read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose location is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven location read
   function Get_Location
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Location_Operation;

   --  Consume one terminal GetBucketLocation operation.
   --  @param Operation Terminal bucket-location read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Location_Operation;
      Result    : out Get_Bucket_Location_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  What is known about one bucket-tag mutation after terminal drain.
   --  An unknown outcome requires a caller-selected GetBucketTagging
   --  reconciliation before any retry.
   --  @enum Bucket_Tag_Mutation_Completed Complete response proves mutation
   --  @enum Bucket_Tag_Mutation_Definitely_Not_Applied Non-admission or exact
   --     rejection proves the requested mutation was not applied
   --  @enum Bucket_Tag_Mutation_Outcome_Unknown State must be reconciled
   --  @enum Bucket_Tag_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Bucket_Tag_Mutation_Disposition is
     (Bucket_Tag_Mutation_Completed,
      Bucket_Tag_Mutation_Definitely_Not_Applied,
      Bucket_Tag_Mutation_Outcome_Unknown,
      Bucket_Tag_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketTagging mutation.
   --  @enum Put_Bucket_Tagging_Response_Available Modeled response exists
   --  @enum Put_Bucket_Tagging_Exchange_Failed No modeled response exists
   type Put_Bucket_Tagging_Result_Kind is
     (Put_Bucket_Tagging_Response_Available,
      Put_Bucket_Tagging_Exchange_Failed);

   --  Typed PutBucketTagging certainty and modeled response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Tagging_Result
     (Kind : Put_Bucket_Tagging_Result_Kind :=
        Put_Bucket_Tagging_Exchange_Failed)
   is record
      Disposition : Bucket_Tag_Mutation_Disposition :=
        Bucket_Tag_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Tagging_Response_Available =>
            Response : Low_Level.Put_Bucket_Tagging_Outcome;
         when Put_Bucket_Tagging_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketTagging parent. Serialized tags and signing inputs
   --  are owned by the prepared request through terminal Finish.
   type Put_Bucket_Tagging_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying PutBucketTagging mutation.
   --  Defaults preserve the established synchronous request policy.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete tag set is replaced
   --  @param Value Complete validated bucket tag set copied during prepare
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Put_Tags
     (Client    : not null access Flyology.HTTP.Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Value     : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Put_Bucket_Tagging_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketTagging mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete tag set is replaced
   --  @param Value Complete validated bucket tag set copied during prepare
   --  @param Parameters Complete modeled request controls
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
      Value      : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Tagging_Operation;

   --  Consume one terminal PutBucketTagging operation.
   --  @param Operation Terminal bucket-tag replacement
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Tagging_Operation;
      Result    : out Put_Bucket_Tagging_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal GetBucketTagging read.
   --  @enum Get_Bucket_Tagging_Response_Available Modeled response exists
   --  @enum Get_Bucket_Tagging_Exchange_Failed No modeled response exists
   type Get_Bucket_Tagging_Result_Kind is
     (Get_Bucket_Tagging_Response_Available,
      Get_Bucket_Tagging_Exchange_Failed);

   --  Typed bounded GetBucketTagging response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Tagging_Result
     (Kind : Get_Bucket_Tagging_Result_Kind :=
        Get_Bucket_Tagging_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Tagging_Response_Available =>
            Response : Low_Level.Get_Bucket_Tagging_Outcome;
         when Get_Bucket_Tagging_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded read-only GetBucketTagging parent with one HTTP child.
   type Get_Bucket_Tagging_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketTagging read.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose tag set is fetched
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Get_Tags
     (Client    : not null access Flyology.HTTP.Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Get_Bucket_Tagging_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketTagging read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose tag set is fetched
   --  @param Parameters Complete modeled request controls
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
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Tagging_Operation;

   --  Consume one terminal GetBucketTagging operation.
   --  @param Operation Terminal bucket-tag read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Tagging_Operation;
      Result    : out Get_Bucket_Tagging_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Shape of a terminal DeleteBucketTagging mutation.
   --  @enum Delete_Bucket_Tagging_Response_Available Modeled response exists
   --  @enum Delete_Bucket_Tagging_Exchange_Failed No modeled response exists
   type Delete_Bucket_Tagging_Result_Kind is
     (Delete_Bucket_Tagging_Response_Available,
      Delete_Bucket_Tagging_Exchange_Failed);

   --  Typed DeleteBucketTagging certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Tagging_Result
     (Kind : Delete_Bucket_Tagging_Result_Kind :=
        Delete_Bucket_Tagging_Exchange_Failed)
   is record
      Disposition : Bucket_Tag_Mutation_Disposition :=
        Bucket_Tag_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Tagging_Response_Available =>
            Response : Low_Level.Delete_Bucket_Tagging_Outcome;
         when Delete_Bucket_Tagging_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketTagging parent with a deliberately nonreplayable
   --  empty source and one hidden HTTP child.
   type Delete_Bucket_Tagging_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation and
       Flyology.HTTP.Client.Operation_Request_Body_Source and
       Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying DeleteBucketTagging mutation.
   --  @param Operation Fresh or consumed established operation
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose tag set is deleted
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   procedure Delete_Tags
     (Client    : not null access Flyology.HTTP.Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Delete_Bucket_Tagging_Operation)
     with Pre => not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteBucketTagging mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose tag set is deleted
   --  @param Parameters Complete modeled request controls
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
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Tagging_Operation;

   --  Consume one terminal DeleteBucketTagging operation.
   --  @param Operation Terminal bucket-tag deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Tagging_Operation;
      Result    : out Delete_Bucket_Tagging_Result)
     with Pre => Flyology.Operations.Is_Terminal (Operation);

   type List_Outcome_Kind is (Page_Available, List_Rejected);

   type List_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : Flyology.Object_Storage.S3.Buckets.List_Buckets_Result;
         when List_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page of general-purpose buckets. Pagination is enabled
   --  by default with a 1,000-bucket page, following AWS's recommendation.
   --  Pass the returned continuation token to obtain the next page.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Maximum Maximum number of buckets returned in this page
   --  @param Continuation_Token Opaque token returned by the prior page
   --  @param Prefix Optional bucket-name prefix filter
   --  @param Bucket_Region Optional bucket-region filter
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return One typed page or a structured S3 rejection
   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Maximum  : Flyology.Object_Storage.S3.Buckets.Max_Buckets_Value :=
        1_000;
      Continuation_Token : String := "";
      Prefix   : String := "";
      Bucket_Region : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Outcome;

   --  List one bounded ListBuckets page by waiting on the composable
   --  owner-driven operation. This parameter-record overload preserves typed
   --  HTTP failure and admission information.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Parameters Complete modeled bucket listing scope and cursor
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   --  Region, addressing, and timeout defaults mirror the established
   --  convenience overload; changing them changes source-visible client
   --  request policy and compatibility.
   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Buckets_Result;

   type Create_Outcome_Kind is (Creation_Completed, Create_Rejected);

   type Create_Outcome
     (Kind : Create_Outcome_Kind := Create_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Creation_Completed =>
            Location   : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_ARN : Ada.Strings.Unbounded.Unbounded_String;
         when Create_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Create one bucket by waiting on the composable non-replaying operation.
   --  This parameter-record overload preserves mutation certainty, exact HTTP
   --  admission state, and every modeled request member.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket New bucket name
   --  @param Parameters Complete modeled CreateBucket controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the CreateBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded ambiguous exchange failure
   --  Region, addressing, and timeout defaults mirror the established
   --  convenience overload; changing them changes source-visible policy.
   function Create
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Bucket_Result;

   --  Create a general-purpose bucket. Unless explicitly supplied,
   --  Location_Constraint follows Region and is omitted for us-east-1.
   --  Advanced ACL, Object Lock, tagging, namespace, and directory-bucket
   --  inputs remain available through the typed Low_Level API.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket New general-purpose bucket name
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the CreateBucket request
   --  @param Location_Constraint Optional explicit legacy region constraint
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Modeled creation headers or structured S3 rejection
   function Create
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Location_Constraint : String := "";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Outcome;

   type Delete_Outcome_Kind is (Deletion_Completed, Delete_Rejected);

   type Delete_Outcome
     (Kind : Delete_Outcome_Kind := Delete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Deletion_Completed =>
            null;
         when Delete_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Delete one bucket by waiting on the owner-driven composable operation.
   --  This parameter-record overload preserves typed admission and deletion
   --  certainty for caller-directed HeadBucket reconciliation.
   --  Compatibility contract: its region, addressing, and 30-second timeout
   --  defaults are the established synchronous Delete policy; changing one
   --  overload independently would break shared-state-machine equivalence.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Empty bucket to delete
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the DeleteBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded ambiguous exchange failure
   function Delete
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Result;

   --  Delete one empty bucket. S3 rejects buckets that still contain objects
   --  or active multipart state; callers receive that rejection unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Empty bucket to delete
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the DeleteBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Shape of a terminal GetBucketCors read.
   --  @enum Get_Bucket_CORS_Response_Available Modeled response exists
   --  @enum Get_Bucket_CORS_Exchange_Failed No complete response exists
   type Get_Bucket_CORS_Result_Kind is
     (Get_Bucket_CORS_Response_Available,
      Get_Bucket_CORS_Exchange_Failed);

   --  Typed GetBucketCors response or composable HTTP failure. Admission is
   --  retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_CORS_Result
     (Kind : Get_Bucket_CORS_Result_Kind := Get_Bucket_CORS_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_CORS_Response_Available =>
            Response : Low_Level.Get_Bucket_CORS_Outcome;
         when Get_Bucket_CORS_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketCors parent with one hidden HTTP child. The
   --  operation owns its signed request and retained response bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_CORS_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketCors read. Defaults preserve the
   --  package's established bucket-control signing and XML-limit policy.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established CORS read
   procedure Get_CORS
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_CORS_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketCors read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven CORS read
   function Get_CORS
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_CORS_Operation;

   --  Consume one terminal GetBucketCors operation.
   --  @param Operation Terminal CORS read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_CORS_Operation;
      Result    : out Get_Bucket_CORS_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one CORS snapshot by waiting on the same provider-owned operation
   --  used by composable callers. Existing region, addressing, 30-second
   --  timeout, shared XML-limit, and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_CORS
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_CORS_Result;

   --  What is known about a CORS mutation after terminal drain.
   --  Outcome unknown requires caller-selected read reconciliation before
   --  any retry.
   --  @enum Bucket_CORS_Mutation_Completed Complete response proves the
   --     requested mutation completed
   --  @enum Bucket_CORS_Mutation_Definitely_Not_Applied Exact rejection or
   --     non-admission proves no mutation occurred
   --  @enum Bucket_CORS_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Bucket_CORS_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Bucket_CORS_Mutation_Disposition is
     (Bucket_CORS_Mutation_Completed,
      Bucket_CORS_Mutation_Definitely_Not_Applied,
      Bucket_CORS_Mutation_Outcome_Unknown,
      Bucket_CORS_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketCors mutation.
   --  @enum Put_Bucket_CORS_Response_Available Modeled response exists
   --  @enum Put_Bucket_CORS_Exchange_Failed No complete response exists
   type Put_Bucket_CORS_Result_Kind is
     (Put_Bucket_CORS_Response_Available,
      Put_Bucket_CORS_Exchange_Failed);

   --  Typed PutBucketCors certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_CORS_Result
     (Kind : Put_Bucket_CORS_Result_Kind := Put_Bucket_CORS_Exchange_Failed)
   is record
      Disposition : Bucket_CORS_Mutation_Disposition :=
        Bucket_CORS_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_CORS_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_CORS_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketCors parent. The prepared request owns the exact
   --  serialized configuration and signing inputs through Finish. The
   --  operation never rewinds or replays its body.
   type Put_Bucket_CORS_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying PutBucketCors mutation. Region,
   --  addressing, XML-limit, and cancellation defaults preserve the existing
   --  bucket-control client policy.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete CORS configuration is replaced
   --  @param Value Complete CORS configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established CORS mutation
   procedure Set_CORS
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        CORS_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_CORS_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketCors mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete CORS configuration is replaced
   --  @param Value Complete CORS configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven CORS mutation
   function Set_CORS
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        CORS_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_CORS_Operation;

   --  Consume one terminal PutBucketCors operation.
   --  @param Operation Terminal CORS mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_CORS_Operation;
      Result    : out Put_Bucket_CORS_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the CORS document by waiting on the same nonreplaying
   --  provider-owned operation used by composable callers. The established
   --  region, addressing, 30-second timeout, shared XML-limit, and null-
   --  cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete CORS configuration is replaced
   --  @param Value Complete CORS configuration
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_CORS
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        CORS_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_CORS_Result;

   --  Shape of a terminal DeleteBucketCors mutation.
   --  @enum Delete_Bucket_CORS_Response_Available Modeled response exists
   --  @enum Delete_Bucket_CORS_Exchange_Failed No complete response exists
   type Delete_Bucket_CORS_Result_Kind is
     (Delete_Bucket_CORS_Response_Available,
      Delete_Bucket_CORS_Exchange_Failed);

   --  Typed DeleteBucketCors certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_CORS_Result
     (Kind : Delete_Bucket_CORS_Result_Kind :=
        Delete_Bucket_CORS_Exchange_Failed)
   is record
      Disposition : Bucket_CORS_Mutation_Disposition :=
        Bucket_CORS_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_CORS_Response_Available =>
            Response : Low_Level.Delete_Bucket_CORS_Outcome;
         when Delete_Bucket_CORS_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketCors parent. Its signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_CORS_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying DeleteBucketCors mutation. Defaults
   --  preserve the existing synchronous Delete_CORS policy.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose CORS configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established CORS deletion
   procedure Delete_CORS
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_CORS_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_CORS_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteBucketCors mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose CORS configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven CORS deletion
   function Delete_CORS
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_CORS_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_CORS_Operation;

   --  Consume one terminal DeleteBucketCors operation.
   --  @param Operation Terminal CORS deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_CORS_Operation;
      Result    : out Delete_Bucket_CORS_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the CORS configuration by waiting on the same nonreplaying
   --  provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose CORS configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_CORS
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_CORS_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_CORS_Result;

   --  Remove the complete CORS configuration from one bucket. Deleting an
   --  absent configuration follows the endpoint's S3 status unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose CORS configuration is removed
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the DeleteBucketCors request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_CORS
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove one named analytics configuration.
   function Delete_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete default encryption configuration.
   function Delete_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  What is known about a DeleteBucketAnalyticsConfiguration
   --  mutation after terminal drain. Unknown outcomes require caller-selected
   --  read-only reconciliation before any retry.
   --  @enum Bucket_Analytics_Configuration_Mutation_Completed
   --     Complete response proves deletion
   --  @enum Bucket_Analytics_Configuration_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Analytics_Configuration_Mutation_Outcome_Unknown
   --     State must be reconciled
   --  @enum Bucket_Analytics_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Analytics_Configuration_Mutation_Disposition is
     (Bucket_Analytics_Configuration_Mutation_Completed,
      Bucket_Analytics_Configuration_Mutation_Definitely_Not_Applied,
      Bucket_Analytics_Configuration_Mutation_Outcome_Unknown,
      Bucket_Analytics_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketAnalyticsConfiguration
   --  mutation.
   --  @enum Delete_Bucket_Analytics_Response_Available
   --     Modeled response exists
   --  @enum Delete_Bucket_Analytics_Exchange_Failed
   --     No modeled response exists
   type Delete_Bucket_Analytics_Result_Kind is
     (Delete_Bucket_Analytics_Response_Available,
      Delete_Bucket_Analytics_Exchange_Failed);

   --  Typed DeleteBucketAnalyticsConfiguration certainty and
   --  response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Analytics_Result
     (Kind : Delete_Bucket_Analytics_Result_Kind :=
        Delete_Bucket_Analytics_Exchange_Failed)
   is record
      Disposition :
        Bucket_Analytics_Configuration_Mutation_Disposition :=
          Bucket_Analytics_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Analytics_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Analytics_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketAnalyticsConfiguration parent. Its signed
   --  request and empty nonreplayable source remain owned through Finish.
   type Delete_Bucket_Analytics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketAnalyticsConfiguration defaults.

   --  Start or restart one nonreplaying analytics deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Analytics_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  :
        in out Delete_Bucket_Analytics_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying analytics deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Analytics_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Analytics_Operation;

   --  Consume one terminal DeleteBucketAnalyticsConfiguration.
   --  @param Operation Terminal analytics deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation :
        in out Delete_Bucket_Analytics_Operation;
      Result : out Delete_Bucket_Analytics_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the analytics configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose analytics configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Analytics_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Analytics_Result;

   --  What is known about a DeleteBucketIntelligentTieringConfiguration
   --  mutation after terminal drain. Unknown outcomes require caller-selected
   --  read-only reconciliation before any retry.
   --  @enum Bucket_Tiering_Configuration_Mutation_Completed
   --     Complete response proves deletion
   --  @enum Bucket_Tiering_Configuration_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Tiering_Configuration_Mutation_Outcome_Unknown
   --     State must be reconciled
   --  @enum Bucket_Tiering_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Tiering_Configuration_Mutation_Disposition is
     (Bucket_Tiering_Configuration_Mutation_Completed,
      Bucket_Tiering_Configuration_Mutation_Definitely_Not_Applied,
      Bucket_Tiering_Configuration_Mutation_Outcome_Unknown,
      Bucket_Tiering_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketIntelligentTieringConfiguration
   --  mutation.
   --  @enum Delete_Bucket_Tiering_Response_Available
   --     Modeled response exists
   --  @enum Delete_Bucket_Tiering_Exchange_Failed
   --     No modeled response exists
   type Delete_Bucket_Tiering_Result_Kind is
     (Delete_Bucket_Tiering_Response_Available,
      Delete_Bucket_Tiering_Exchange_Failed);

   --  Typed DeleteBucketIntelligentTieringConfiguration certainty and
   --  response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Tiering_Result
     (Kind : Delete_Bucket_Tiering_Result_Kind :=
        Delete_Bucket_Tiering_Exchange_Failed)
   is record
      Disposition :
        Bucket_Tiering_Configuration_Mutation_Disposition :=
          Bucket_Tiering_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Tiering_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Tiering_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketIntelligentTieringConfiguration parent. Its signed
   --  request and empty nonreplayable source remain owned through Finish.
   type Delete_Bucket_Tiering_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketIntelligentTieringConfiguration defaults.

   --  Start or restart one nonreplaying intelligent-tiering deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose intelligent-tiering policy is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Intelligent_Tiering_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  :
        in out Delete_Bucket_Tiering_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying intelligent-tiering deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose intelligent-tiering policy is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Intelligent_Tiering_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Tiering_Operation;

   --  Consume one terminal DeleteBucketIntelligentTieringConfiguration.
   --  @param Operation Terminal intelligent-tiering deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation :
        in out Delete_Bucket_Tiering_Operation;
      Result : out Delete_Bucket_Tiering_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the intelligent-tiering configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose intelligent-tiering policy is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Intelligent_Tiering_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Tiering_Result;

   --  Remove one named intelligent-tiering configuration.
   function Delete_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  What is known about a DeleteBucketInventoryConfiguration mutation
   --  after terminal drain. Unknown outcomes require caller-selected read-only
   --  reconciliation before any retry.
   --  @enum Bucket_Inventory_Configuration_Mutation_Completed Complete
   --     response proves deletion
   --  @enum Bucket_Inventory_Configuration_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Inventory_Configuration_Mutation_Outcome_Unknown State
   --     must be reconciled
   --  @enum Bucket_Inventory_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Inventory_Configuration_Mutation_Disposition is
     (Bucket_Inventory_Configuration_Mutation_Completed,
      Bucket_Inventory_Configuration_Mutation_Definitely_Not_Applied,
      Bucket_Inventory_Configuration_Mutation_Outcome_Unknown,
      Bucket_Inventory_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketInventoryConfiguration mutation.
   --  @enum Delete_Bucket_Inventory_Configuration_Response_Available
   --     Modeled response exists
   --  @enum Delete_Bucket_Inventory_Configuration_Exchange_Failed No
   --     modeled response exists
   type Delete_Bucket_Inventory_Configuration_Result_Kind is
     (Delete_Bucket_Inventory_Configuration_Response_Available,
      Delete_Bucket_Inventory_Configuration_Exchange_Failed);

   --  Typed DeleteBucketInventoryConfiguration certainty and response or
   --  HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Inventory_Configuration_Result
     (Kind : Delete_Bucket_Inventory_Configuration_Result_Kind :=
        Delete_Bucket_Inventory_Configuration_Exchange_Failed)
   is record
      Disposition : Bucket_Inventory_Configuration_Mutation_Disposition :=
        Bucket_Inventory_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Inventory_Configuration_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Inventory_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketInventoryConfiguration parent. Its signed request
   --  and empty nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_Inventory_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketInventoryConfiguration defaults.

   --  Start or restart one nonreplaying inventory-configuration deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Inventory_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Inventory_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying inventory-configuration deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Inventory_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Inventory_Configuration_Operation;

   --  Consume one terminal DeleteBucketInventoryConfiguration operation.
   --  @param Operation Terminal inventory-configuration deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Inventory_Configuration_Operation;
      Result    : out Delete_Bucket_Inventory_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the inventory configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose inventory configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Inventory_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Inventory_Configuration_Result;

   --  Remove one named inventory configuration.
   function Delete_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete lifecycle configuration.
   function Delete_Lifecycle
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete metadata configuration.
   function Delete_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  What is known about a DeleteBucketMetadataConfiguration
   --  mutation after terminal drain. Unknown outcomes require caller-selected
   --  read-only reconciliation before any retry.
   --  @enum Bucket_Metadata_Configuration_Mutation_Completed
   --     Complete response proves deletion
   --  @enum Bucket_Metadata_Configuration_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Metadata_Configuration_Mutation_Outcome_Unknown
   --     State must be reconciled
   --  @enum Bucket_Metadata_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Metadata_Configuration_Mutation_Disposition is
     (Bucket_Metadata_Configuration_Mutation_Completed,
      Bucket_Metadata_Configuration_Mutation_Definitely_Not_Applied,
      Bucket_Metadata_Configuration_Mutation_Outcome_Unknown,
      Bucket_Metadata_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketMetadataConfiguration
   --  mutation.
   --  @enum Delete_Bucket_Metadata_Response_Available
   --     Modeled response exists
   --  @enum Delete_Bucket_Metadata_Exchange_Failed
   --     No modeled response exists
   type Delete_Bucket_Metadata_Result_Kind is
     (Delete_Bucket_Metadata_Response_Available,
      Delete_Bucket_Metadata_Exchange_Failed);

   --  Typed DeleteBucketMetadataConfiguration certainty and
   --  response or HTTP failure.
   --  Record defaults are deterministic aggregate sentinels only and never
   --  classify a decoded terminal result.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Metadata_Result
     (Kind : Delete_Bucket_Metadata_Result_Kind :=
        Delete_Bucket_Metadata_Exchange_Failed)
   is record
      Disposition :
        Bucket_Metadata_Configuration_Mutation_Disposition :=
          Bucket_Metadata_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Metadata_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Metadata_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketMetadataConfiguration parent. Its signed
   --  request and empty nonreplayable source remain owned through Finish.
   type Delete_Bucket_Metadata_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketMetadataConfiguration defaults.

   --  Start or restart one nonreplaying metadata deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Metadata_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  :
        in out Delete_Bucket_Metadata_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying metadata deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Metadata_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Metadata_Operation;

   --  Consume one terminal DeleteBucketMetadataConfiguration.
   --  @param Operation Terminal metadata deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation :
        in out Delete_Bucket_Metadata_Operation;
      Result : out Delete_Bucket_Metadata_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the metadata configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose metadata configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Metadata_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Metadata_Result;

   --  What is known about a DeleteBucketMetadataTableConfiguration
   --  mutation after terminal drain. Unknown outcomes require caller-selected
   --  read-only reconciliation before any retry.
   --  @enum Bucket_Metadata_Table_Mutation_Completed
   --     Complete response proves deletion
   --  @enum Bucket_Metadata_Table_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Metadata_Table_Mutation_Outcome_Unknown
   --     State must be reconciled
   --  @enum Bucket_Metadata_Table_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Metadata_Table_Mutation_Disposition is
     (Bucket_Metadata_Table_Mutation_Completed,
      Bucket_Metadata_Table_Mutation_Definitely_Not_Applied,
      Bucket_Metadata_Table_Mutation_Outcome_Unknown,
      Bucket_Metadata_Table_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketMetadataTableConfiguration
   --  mutation.
   --  @enum Delete_Bucket_Metadata_Table_Response_Available
   --     Modeled response exists
   --  @enum Delete_Bucket_Metadata_Table_Exchange_Failed
   --     No modeled response exists
   type Delete_Bucket_Metadata_Table_Result_Kind is
     (Delete_Bucket_Metadata_Table_Response_Available,
      Delete_Bucket_Metadata_Table_Exchange_Failed);

   --  Typed DeleteBucketMetadataTableConfiguration certainty and
   --  response or HTTP failure.
   --  Record defaults are deterministic aggregate sentinels only and never
   --  classify a decoded terminal result.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Metadata_Table_Result
     (Kind : Delete_Bucket_Metadata_Table_Result_Kind :=
        Delete_Bucket_Metadata_Table_Exchange_Failed)
   is record
      Disposition :
        Bucket_Metadata_Table_Mutation_Disposition :=
          Bucket_Metadata_Table_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Metadata_Table_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Metadata_Table_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketMetadataTableConfiguration parent. Its signed
   --  request and empty nonreplayable source remain owned through Finish.
   type Delete_Bucket_Metadata_Table_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketMetadataTableConfiguration defaults.

   --  Start or restart one nonreplaying metadata-table deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata-table configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Metadata_Table_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  :
        in out Delete_Bucket_Metadata_Table_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying metadata-table deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata-table configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Metadata_Table_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Metadata_Table_Operation;

   --  Consume one terminal DeleteBucketMetadataTableConfiguration.
   --  @param Operation Terminal metadata-table deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation :
        in out Delete_Bucket_Metadata_Table_Operation;
      Result : out Delete_Bucket_Metadata_Table_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the metadata-table configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose metadata-table configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Metadata_Table_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Metadata_Table_Result;

   --  Remove the complete metadata-table configuration.
   function Delete_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  What is known about a DeleteBucketMetricsConfiguration
   --  mutation after terminal drain. Unknown outcomes require caller-selected
   --  read-only reconciliation before any retry.
   --  @enum Bucket_Metrics_Configuration_Mutation_Completed
   --     Complete response proves deletion
   --  @enum Bucket_Metrics_Configuration_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Metrics_Configuration_Mutation_Outcome_Unknown
   --     State must be reconciled
   --  @enum Bucket_Metrics_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Metrics_Configuration_Mutation_Disposition is
     (Bucket_Metrics_Configuration_Mutation_Completed,
      Bucket_Metrics_Configuration_Mutation_Definitely_Not_Applied,
      Bucket_Metrics_Configuration_Mutation_Outcome_Unknown,
      Bucket_Metrics_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketMetricsConfiguration
   --  mutation.
   --  @enum Delete_Bucket_Metrics_Response_Available
   --     Modeled response exists
   --  @enum Delete_Bucket_Metrics_Exchange_Failed
   --     No modeled response exists
   type Delete_Bucket_Metrics_Result_Kind is
     (Delete_Bucket_Metrics_Response_Available,
      Delete_Bucket_Metrics_Exchange_Failed);

   --  Typed DeleteBucketMetricsConfiguration certainty and
   --  response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Metrics_Result
     (Kind : Delete_Bucket_Metrics_Result_Kind :=
        Delete_Bucket_Metrics_Exchange_Failed)
   is record
      Disposition :
        Bucket_Metrics_Configuration_Mutation_Disposition :=
          Bucket_Metrics_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Metrics_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Metrics_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketMetricsConfiguration parent. Its signed
   --  request and empty nonreplayable source remain owned through Finish.
   type Delete_Bucket_Metrics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketMetricsConfiguration defaults.

   --  Start or restart one nonreplaying metrics deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Metrics_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  :
        in out Delete_Bucket_Metrics_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying metrics deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Metrics_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Metrics_Operation;

   --  Consume one terminal DeleteBucketMetricsConfiguration.
   --  @param Operation Terminal metrics deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation :
        in out Delete_Bucket_Metrics_Operation;
      Result : out Delete_Bucket_Metrics_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the metrics configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose metrics configuration is removed
   --  @param Parameters Complete modeled identifier and owner preconditions
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Metrics_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Metrics_Result;

   --  Remove one named metrics configuration.
   function Delete_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete ownership-controls configuration.
   function Delete_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete bucket policy.
   function Delete_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  What is known about a bucket-replication mutation after terminal
   --  drain. Unknown outcomes require caller-selected read-only
   --  reconciliation before any retry.
   --  @enum Bucket_Replication_Mutation_Completed Complete response proves
   --     deletion
   --  @enum Bucket_Replication_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Replication_Mutation_Outcome_Unknown State must be
   --     reconciled
   --  @enum Bucket_Replication_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Replication_Mutation_Disposition is
     (Bucket_Replication_Mutation_Completed,
      Bucket_Replication_Mutation_Definitely_Not_Applied,
      Bucket_Replication_Mutation_Outcome_Unknown,
      Bucket_Replication_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketReplication mutation.
   --  @enum Delete_Bucket_Replication_Response_Available Modeled response
   --     exists
   --  @enum Delete_Bucket_Replication_Exchange_Failed No modeled response
   --     exists
   type Delete_Bucket_Replication_Result_Kind is
     (Delete_Bucket_Replication_Response_Available,
      Delete_Bucket_Replication_Exchange_Failed);

   --  Typed DeleteBucketReplication certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Replication_Result
     (Kind : Delete_Bucket_Replication_Result_Kind :=
        Delete_Bucket_Replication_Exchange_Failed)
   is record
      Disposition : Bucket_Replication_Mutation_Disposition :=
        Bucket_Replication_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Replication_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Replication_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketReplication parent. Its signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_Replication_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketReplication defaults.

   --  Start or restart one nonreplaying replication-configuration deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose replication configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Replication
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Replication_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying replication-configuration deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose replication configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Replication
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Replication_Operation;

   --  Consume one terminal DeleteBucketReplication operation.
   --  @param Operation Terminal replication-configuration deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Replication_Operation;
      Result    : out Delete_Bucket_Replication_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the replication configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose replication configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Replication
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Replication_Result;

   --  Remove the complete replication configuration.
   function Delete_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  What is known about a DeleteBucketWebsite mutation after terminal
   --  drain. Unknown outcomes require caller-selected read-only
   --  reconciliation before any retry.
   --  @enum Bucket_Website_Mutation_Completed Complete response proves
   --     deletion
   --  @enum Bucket_Website_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Website_Mutation_Outcome_Unknown State must be
   --     reconciled
   --  @enum Bucket_Website_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Website_Mutation_Disposition is
     (Bucket_Website_Mutation_Completed,
      Bucket_Website_Mutation_Definitely_Not_Applied,
      Bucket_Website_Mutation_Outcome_Unknown,
      Bucket_Website_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal DeleteBucketWebsite mutation.
   --  @enum Delete_Bucket_Website_Response_Available Modeled response
   --     exists
   --  @enum Delete_Bucket_Website_Exchange_Failed No modeled response
   --     exists
   type Delete_Bucket_Website_Result_Kind is
     (Delete_Bucket_Website_Response_Available,
      Delete_Bucket_Website_Exchange_Failed);

   --  Typed DeleteBucketWebsite certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Website_Result
     (Kind : Delete_Bucket_Website_Result_Kind :=
        Delete_Bucket_Website_Exchange_Failed)
   is record
      Disposition : Bucket_Website_Mutation_Disposition :=
        Bucket_Website_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Website_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Website_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketWebsite parent. Its signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_Website_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: region, path-style addressing, the shared XML
   --  limits, cancellation, and the 30-second synchronous timeout preserve
   --  the established DeleteBucketWebsite defaults.

   --  Start or restart one nonreplaying website-configuration deletion.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose website configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Delete_Website
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Website_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying website-configuration deletion.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose website configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven mutation
   function Delete_Website
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Website_Operation;

   --  Consume one terminal DeleteBucketWebsite operation.
   --  @param Operation Terminal website-configuration deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Website_Operation;
      Result    : out Delete_Bucket_Website_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the website configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose website configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Website
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Website_Result;

   --  Remove the complete website configuration.
   function Delete_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Shape of a terminal GetObjectLockConfiguration read.
   --  @enum Get_Object_Lock_Configuration_Response_Available Modeled
   --     response exists
   --  @enum Get_Object_Lock_Configuration_Exchange_Failed No complete
   --     response exists
   type Get_Object_Lock_Configuration_Result_Kind is
     (Get_Object_Lock_Configuration_Response_Available,
      Get_Object_Lock_Configuration_Exchange_Failed);

   --  Typed bounded Object Lock configuration or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Object_Lock_Configuration_Result
     (Kind : Get_Object_Lock_Configuration_Result_Kind :=
        Get_Object_Lock_Configuration_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Object_Lock_Configuration_Response_Available =>
            Response : Low_Level.Get_Object_Lock_Configuration_Outcome;
         when Get_Object_Lock_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded bucket-scoped Object Lock configuration read.
   type Get_Object_Lock_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the package's established bucket-read defaults:
   --  us-east-1, path-style addressing, caller-selected shared XML limits,
   --  no cancellation source, and a 30-second synchronous wait.
   --  Start or restart one bounded Object Lock configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Object Lock configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established operation
   procedure Get_Object_Lock_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Object_Lock_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Object_Lock_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded Object Lock configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Object Lock configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration read
   function Get_Object_Lock_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Object_Lock_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Object_Lock_Configuration_Operation;

   --  Consume one terminal Object Lock configuration read.
   --  @param Operation Terminal configuration read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Object_Lock_Configuration_Operation;
      Result    : out Get_Object_Lock_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read Object Lock configuration by waiting on the same provider-owned
   --  operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose Object Lock configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Object_Lock_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Object_Lock_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Object_Lock_Configuration_Result;

   --  What is known about an Object Lock configuration mutation after drain.
   --  Unknown outcomes require caller-selected read reconciliation before
   --  any retry.
   --  @enum Object_Lock_Configuration_Mutation_Completed Complete response
   --     proves the requested mutation completed
   --  @enum Object_Lock_Configuration_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Object_Lock_Configuration_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Object_Lock_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Object_Lock_Configuration_Mutation_Disposition is
     (Object_Lock_Configuration_Mutation_Completed,
      Object_Lock_Configuration_Mutation_Definitely_Not_Applied,
      Object_Lock_Configuration_Mutation_Outcome_Unknown,
      Object_Lock_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutObjectLockConfiguration mutation.
   --  @enum Put_Object_Lock_Configuration_Response_Available Modeled response
   --     exists
   --  @enum Put_Object_Lock_Configuration_Exchange_Failed No complete
   --     response exists
   type Put_Object_Lock_Configuration_Result_Kind is
     (Put_Object_Lock_Configuration_Response_Available,
      Put_Object_Lock_Configuration_Exchange_Failed);

   --  Typed Object Lock configuration certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Object_Lock_Configuration_Result
     (Kind : Put_Object_Lock_Configuration_Result_Kind :=
        Put_Object_Lock_Configuration_Exchange_Failed)
   is record
      Disposition : Object_Lock_Configuration_Mutation_Disposition :=
        Object_Lock_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Object_Lock_Configuration_Response_Available =>
            Response : Low_Level.Put_Object_Lock_Configuration_Outcome;
         when Put_Object_Lock_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot bucket-scoped Object Lock configuration mutation. The parent
   --  owns its serialized document and never rewinds or replays it.
   type Put_Object_Lock_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the established bucket-mutation defaults:
   --  us-east-1, path-style addressing, caller-selected shared XML limits,
   --  no cancellation source, and a 30-second synchronous wait.
   --  Start or restart one nonreplaying Object Lock configuration mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Object Lock configuration is replaced
   --  @param Value Presence-preserving configuration copied at start
   --  @param Parameters Complete modeled checksum, token, and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established operation
   procedure Put_Object_Lock_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.
        Object_Lock_Configuration;
      Parameters : Low_Level.Put_Object_Lock_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Object_Lock_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying Object Lock configuration mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Object Lock configuration is replaced
   --  @param Value Presence-preserving configuration copied at start
   --  @param Parameters Complete modeled checksum, token, and controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration mutation
   function Put_Object_Lock_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.
        Object_Lock_Configuration;
      Parameters : Low_Level.Put_Object_Lock_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Object_Lock_Configuration_Operation;

   --  Consume one terminal Object Lock configuration mutation.
   --  @param Operation Terminal configuration mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Object_Lock_Configuration_Operation;
      Result    : out Put_Object_Lock_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace Object Lock configuration by waiting on the same nonreplaying
   --  provider-owned operation used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose Object Lock configuration is replaced
   --  @param Value Presence-preserving configuration copied at start
   --  @param Parameters Complete modeled checksum, token, and controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Put_Object_Lock_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.
        Object_Lock_Configuration;
      Parameters : Low_Level.Put_Object_Lock_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Object_Lock_Configuration_Result;

   --  Shape of a terminal GetBucketEncryption read.
   --  @enum Get_Bucket_Encryption_Response_Available Modeled
   --     response exists
   --  @enum Get_Bucket_Encryption_Exchange_Failed No complete response
   --     exists
   type Get_Bucket_Encryption_Result_Kind is
     (Get_Bucket_Encryption_Response_Available,
      Get_Bucket_Encryption_Exchange_Failed);

   --  Typed GetBucketEncryption response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Encryption_Result
     (Kind : Get_Bucket_Encryption_Result_Kind :=
        Get_Bucket_Encryption_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Encryption_Response_Available =>
            Response : Low_Level.Get_Bucket_Encryption_Outcome;
         when Get_Bucket_Encryption_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketEncryption parent with one hidden HTTP
   --  child. The operation owns its signed request and retained response
   --  bytes through terminal Finish, with no borrowed request input after
   --  signing.
   type Get_Bucket_Encryption_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads use the package's established bucket-control defaults:
   --  us-east-1, path-style addressing, shared XML limits, and no
   --  cancellation source. The values preserve existing request-signing
   --  policy rather than introducing new operation-specific policy.
   --  Start or restart one bounded GetBucketEncryption read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration read
   procedure Get_Encryption
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Encryption_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketEncryption read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration read
   function Get_Encryption
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Encryption_Operation;

   --  Consume one terminal GetBucketEncryption operation.
   --  @param Operation Terminal bucket-encryption read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Encryption_Operation;
      Result    : out Get_Bucket_Encryption_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket-encryption snapshot by waiting on the provider-owned
   --  composable operation. The established region, addressing, 30-second
   --  timeout, shared XML-limit, and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Encryption
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Encryption_Result;

   --  Shape of a terminal GetBucketLifecycleConfiguration read.
   --  @enum Get_Bucket_Lifecycle_Response_Available Modeled response exists
   --  @enum Get_Bucket_Lifecycle_Exchange_Failed No complete response exists
   type Get_Bucket_Lifecycle_Result_Kind is
     (Get_Bucket_Lifecycle_Response_Available,
      Get_Bucket_Lifecycle_Exchange_Failed);

   --  Typed GetBucketLifecycleConfiguration response or composable HTTP
   --  failure. Admission is retained for diagnostics; this call is read-only.
   --  Record defaults are conservative inert operation-storage sentinels.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Lifecycle_Result
     (Kind : Get_Bucket_Lifecycle_Result_Kind :=
        Get_Bucket_Lifecycle_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Lifecycle_Response_Available =>
            Response :
              Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome;
         when Get_Bucket_Lifecycle_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketLifecycleConfiguration parent with one hidden
   --  HTTP child. It owns the signed request and bounded response through
   --  typed Finish and retains no borrowed request input after signing.
   type Get_Bucket_Lifecycle_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: these overloads preserve the package's
   --  established us-east-1, path-style, shared XML-limit, null-cancellation,
   --  and 30-second synchronous defaults.
   --  Start or restart one bounded lifecycle-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose lifecycle configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration read
   procedure Get_Lifecycle_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Lifecycle_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded lifecycle-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose lifecycle configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration read
   function Get_Lifecycle_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Lifecycle_Operation;

   --  Consume one terminal GetBucketLifecycleConfiguration operation.
   --  @param Operation Terminal lifecycle-configuration read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Lifecycle_Operation;
      Result    : out Get_Bucket_Lifecycle_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one lifecycle-configuration snapshot by waiting on the same
   --  provider-owned composable state machine.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose lifecycle configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Lifecycle_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Lifecycle_Result;

   --  Shape of a terminal GetBucketAcl read.
   --  @enum Get_Bucket_ACL_Response_Available Modeled response exists
   --  @enum Get_Bucket_ACL_Exchange_Failed No complete response exists
   type Get_Bucket_ACL_Result_Kind is
     (Get_Bucket_ACL_Response_Available,
      Get_Bucket_ACL_Exchange_Failed);

   --  Typed GetBucketAcl response or composable HTTP failure. Admission is
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
   type Get_Bucket_ACL_Result
     (Kind : Get_Bucket_ACL_Result_Kind := Get_Bucket_ACL_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_ACL_Response_Available =>
            Response : Low_Level.Get_Bucket_ACL_Outcome;
         when Get_Bucket_ACL_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketAcl parent with one hidden HTTP child. The
   --  operation owns its signed request and retained response bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_ACL_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketAcl read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose access-control policy is requested
   --  @param Parameters Complete modeled owner precondition
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
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_ACL_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketAcl read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose access-control policy is requested
   --  @param Parameters Complete modeled owner precondition
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
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_ACL_Operation;

   --  Consume one terminal GetBucketAcl operation.
   --  @param Operation Terminal ACL read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_ACL_Operation;
      Result    : out Get_Bucket_ACL_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket ACL by waiting on the provider-owned composable
   --  operation. Existing region, addressing, timeout, and XML-limit defaults
   --  are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose access-control policy is requested
   --  @param Parameters Complete modeled owner precondition
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
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_ACL_Result;

   --  Shape of a terminal GetBucketMetadataTableConfiguration read.
   --  @enum Get_Bucket_Metadata_Table_Configuration_Response_Available
   --     Modeled response exists
   --  @enum Get_Bucket_Metadata_Table_Configuration_Exchange_Failed
   --     No complete response exists
   type Get_Bucket_Metadata_Table_Configuration_Result_Kind is
     (Get_Bucket_Metadata_Table_Configuration_Response_Available,
      Get_Bucket_Metadata_Table_Configuration_Exchange_Failed);

   --  Typed metadata-table configuration response or composable HTTP
   --  failure. Admission is retained for diagnostics; this operation is
   --  read-only. Default initialization is the conservative inert failure
   --  shape used before terminal assignment.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Metadata_Table_Configuration_Result
     (Kind : Get_Bucket_Metadata_Table_Configuration_Result_Kind :=
       Get_Bucket_Metadata_Table_Configuration_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Metadata_Table_Configuration_Response_Available =>
            Response :
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome;
         when Get_Bucket_Metadata_Table_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded metadata-table read with one hidden HTTP child. The
   --  operation owns its signed request and retained response bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_Metadata_Table_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded metadata-table configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata-table state is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established read
   procedure Get_Metadata_Table_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Metadata_Table_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded metadata-table configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata-table state is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven metadata-table read
   function Get_Metadata_Table_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Metadata_Table_Configuration_Operation;

   --  Consume one terminal metadata-table configuration read.
   --  @param Operation Terminal metadata-table read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Metadata_Table_Configuration_Operation;
      Result    : out Get_Bucket_Metadata_Table_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one metadata-table configuration by waiting on the provider-owned
   --  composable operation. Existing defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose metadata-table state is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Metadata_Table_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Metadata_Table_Configuration_Result;

   --  What is known about a CreateBucketMetadataTableConfiguration mutation
   --  after terminal drain. Outcome unknown requires caller-selected
   --  read-only reconciliation before any retry.
   --  @enum Metadata_Table_Configuration_Mutation_Completed Complete
   --     response proves the requested mutation completed
   --  @enum Metadata_Table_Configuration_Mutation_Definitely_Not_Applied
   --     Exact rejection or non-admission proves no mutation occurred
   --  @enum Metadata_Table_Configuration_Mutation_Outcome_Unknown State
   --     requires caller-selected read reconciliation
   --  @enum Metadata_Table_Configuration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Metadata_Table_Configuration_Mutation_Disposition is
     (Metadata_Table_Configuration_Mutation_Completed,
      Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
      Metadata_Table_Configuration_Mutation_Outcome_Unknown,
      Metadata_Table_Configuration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal CreateBucketMetadataTableConfiguration mutation.
   --  @enum Create_Bucket_Metadata_Table_Configuration_Response_Available
   --     Modeled response exists
   --  @enum Create_Bucket_Metadata_Table_Configuration_Exchange_Failed
   --     No complete response exists
   type Create_Bucket_Metadata_Table_Configuration_Result_Kind is
     (Create_Bucket_Metadata_Table_Configuration_Response_Available,
      Create_Bucket_Metadata_Table_Configuration_Exchange_Failed);

   --  Typed CreateBucketMetadataTableConfiguration certainty and response or
   --  HTTP failure. Default initialization is the conservative unknown
   --  failure shape used before terminal assignment.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Create_Bucket_Metadata_Table_Configuration_Result
     (Kind : Create_Bucket_Metadata_Table_Configuration_Result_Kind :=
       Create_Bucket_Metadata_Table_Configuration_Exchange_Failed)
   is record
      Disposition : Metadata_Table_Configuration_Mutation_Disposition :=
        Metadata_Table_Configuration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Create_Bucket_Metadata_Table_Configuration_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Create_Bucket_Metadata_Table_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot CreateBucketMetadataTableConfiguration parent. The prepared
   --  request owns the exact serialized destination and signing inputs
   --  through Finish. The operation never rewinds or replays its body.
   type Create_Bucket_Metadata_Table_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying metadata-table configuration create.
   --  Established region, addressing, XML-limit, and cancellation defaults
   --  are preserved unchanged.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata-table destination is created
   --  @param Value Complete destination configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established mutation
   procedure Create_Metadata_Table_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Metadata_Tables.
        S3_Tables_Destination;
      Parameters : Low_Level.Bucket_Control_Mutation_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out
        Create_Bucket_Metadata_Table_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying metadata-table configuration create.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metadata-table destination is created
   --  @param Value Complete destination configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven metadata-table mutation
   function Create_Metadata_Table_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Metadata_Tables.
        S3_Tables_Destination;
      Parameters : Low_Level.Bucket_Control_Mutation_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Create_Bucket_Metadata_Table_Configuration_Operation;

   --  Consume one terminal metadata-table configuration mutation.
   --  @param Operation Terminal metadata-table mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out
        Create_Bucket_Metadata_Table_Configuration_Operation;
      Result    : out Create_Bucket_Metadata_Table_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Create one metadata-table configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers.
   --  Existing defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose metadata-table destination is created
   --  @param Value Complete destination configuration
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Create_Metadata_Table_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Metadata_Tables.
        S3_Tables_Destination;
      Parameters : Low_Level.Bucket_Control_Mutation_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Create_Bucket_Metadata_Table_Configuration_Result;

   --  What is known about a bucket-encryption mutation after terminal drain.
   --  Outcome unknown requires caller-selected read reconciliation before
   --  any retry.
   --  @enum Bucket_Encryption_Mutation_Completed Complete response proves
   --     the requested mutation completed
   --  @enum Bucket_Encryption_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Encryption_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Bucket_Encryption_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Encryption_Mutation_Disposition is
     (Bucket_Encryption_Mutation_Completed,
      Bucket_Encryption_Mutation_Definitely_Not_Applied,
      Bucket_Encryption_Mutation_Outcome_Unknown,
      Bucket_Encryption_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketEncryption mutation.
   --  @enum Put_Bucket_Encryption_Response_Available Modeled response exists
   --  @enum Put_Bucket_Encryption_Exchange_Failed No complete response exists
   type Put_Bucket_Encryption_Result_Kind is
     (Put_Bucket_Encryption_Response_Available,
      Put_Bucket_Encryption_Exchange_Failed);

   --  Typed PutBucketEncryption certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Encryption_Result
     (Kind : Put_Bucket_Encryption_Result_Kind :=
        Put_Bucket_Encryption_Exchange_Failed)
   is record
      Disposition : Bucket_Encryption_Mutation_Disposition :=
        Bucket_Encryption_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Encryption_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_Encryption_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketEncryption parent. The prepared request owns the
   --  exact serialized configuration and signing inputs through Finish. The
   --  operation never rewinds or replays its body.
   type Put_Bucket_Encryption_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads use the package's established bucket-control defaults:
   --  us-east-1, path-style addressing, shared XML limits, and no
   --  cancellation source. The values preserve existing request-signing
   --  policy rather than introducing new operation-specific policy.
   --  Start or restart one nonreplaying PutBucketEncryption mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Set_Encryption
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Encryption.
        Encryption_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Encryption_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketEncryption mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration mutation
   function Set_Encryption
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Encryption.
        Encryption_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Encryption_Operation;

   --  Consume one terminal PutBucketEncryption operation.
   --  @param Operation Terminal bucket-encryption mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Encryption_Operation;
      Result    : out Put_Bucket_Encryption_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the bucket-encryption document by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected request, response, and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Encryption
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Encryption.
        Encryption_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_Encryption_Result;

   --  Shape of a terminal DeleteBucketEncryption mutation.
   --  @enum Delete_Bucket_Encryption_Response_Available Modeled response
   --     exists
   --  @enum Delete_Bucket_Encryption_Exchange_Failed No complete response
   --     exists
   type Delete_Bucket_Encryption_Result_Kind is
     (Delete_Bucket_Encryption_Response_Available,
      Delete_Bucket_Encryption_Exchange_Failed);

   --  Typed DeleteBucketEncryption certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Encryption_Result
     (Kind : Delete_Bucket_Encryption_Result_Kind :=
        Delete_Bucket_Encryption_Exchange_Failed)
   is record
      Disposition : Bucket_Encryption_Mutation_Disposition :=
        Bucket_Encryption_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Encryption_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Encryption_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketEncryption parent. Its signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_Encryption_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the existing Delete_Encryption defaults:
   --  us-east-1, path-style addressing, shared XML limits, and no
   --  cancellation source. The values preserve existing signing and timeout
   --  policy rather than introducing operation-specific policy.
   --  Start or restart one nonreplaying DeleteBucketEncryption mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose encryption configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Delete_Encryption
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Encryption_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteBucketEncryption mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose encryption configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration deletion
   function Delete_Encryption
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Encryption_Operation;

   --  Consume one terminal DeleteBucketEncryption operation.
   --  @param Operation Terminal bucket-encryption deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Encryption_Operation;
      Result    : out Delete_Bucket_Encryption_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the bucket-encryption configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose encryption configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Encryption
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Encryption_Result;

   --  What is known about a lifecycle-configuration mutation after terminal
   --  drain. Outcome unknown requires caller-selected Get_Lifecycle_
   --  Configuration reconciliation before any retry.
   --  @enum Bucket_Lifecycle_Mutation_Completed Complete response proves the
   --     requested replacement or deletion completed
   --  @enum Bucket_Lifecycle_Mutation_Definitely_Not_Applied Exact rejection
   --     or non-admission proves no mutation occurred
   --  @enum Bucket_Lifecycle_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Bucket_Lifecycle_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Bucket_Lifecycle_Mutation_Disposition is
     (Bucket_Lifecycle_Mutation_Completed,
      Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
      Bucket_Lifecycle_Mutation_Outcome_Unknown,
      Bucket_Lifecycle_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketLifecycleConfiguration mutation.
   --  @enum Put_Bucket_Lifecycle_Response_Available Complete modeled response
   --  @enum Put_Bucket_Lifecycle_Exchange_Failed No complete response exists
   type Put_Bucket_Lifecycle_Result_Kind is
     (Put_Bucket_Lifecycle_Response_Available,
      Put_Bucket_Lifecycle_Exchange_Failed);

   --  Typed lifecycle replacement result. Kind determines whether Response
   --  or the HTTP failure fields are meaningful; all public policy and
   --  resource choices remain caller-supplied.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response when available
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Lifecycle_Result is record
      Kind        : Put_Bucket_Lifecycle_Result_Kind;
      Disposition : Bucket_Lifecycle_Mutation_Disposition;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    :
        Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One-shot lifecycle replacement with one hidden HTTP child. The
   --  operation owns the exact serialized body and signed request through
   --  typed Finish; it never replays or retains caller input.
   type Put_Bucket_Lifecycle_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying lifecycle replacement. Every
   --  deadline, addressing, checksum, header, and XML-limit choice is
   --  explicit; Operation is last for reusable composition.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Absent body or present complete lifecycle rule graph
   --  @param Parameters Required checksum plus owner/transition controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request/response XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established lifecycle mutation
   procedure Set_Lifecycle_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Lifecycle.
        Lifecycle_Configuration;
      Parameters :
        Low_Level.Put_Bucket_Lifecycle_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Put_Bucket_Lifecycle_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying lifecycle replacement.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Absent body or present complete lifecycle rule graph
   --  @param Parameters Required checksum plus owner/transition controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request/response XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven lifecycle mutation
   function Set_Lifecycle_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Lifecycle.
        Lifecycle_Configuration;
      Parameters :
        Low_Level.Put_Bucket_Lifecycle_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Put_Bucket_Lifecycle_Operation;

   --  Consume one terminal PutBucketLifecycleConfiguration operation.
   --  @param Operation Terminal lifecycle replacement
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Lifecycle_Operation;
      Result    : out Put_Bucket_Lifecycle_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the lifecycle configuration by waiting on the same owner-driven
   --  state machine. Every timeout and policy choice is caller-supplied.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Absent body or present complete lifecycle rule graph
   --  @param Parameters Required checksum plus owner/transition controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected request/response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Lifecycle_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Lifecycle.
        Lifecycle_Configuration;
      Parameters :
        Low_Level.Put_Bucket_Lifecycle_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Put_Bucket_Lifecycle_Result;

   --  Shape of a terminal GetBucketReplication read.
   --  @enum Get_Bucket_Replication_Response_Available Modeled response
   --     exists
   --  @enum Get_Bucket_Replication_Exchange_Failed No complete response
   --     exists
   type Get_Bucket_Replication_Result_Kind is
     (Get_Bucket_Replication_Response_Available,
      Get_Bucket_Replication_Exchange_Failed);

   --  Typed replication configuration response or composable HTTP failure.
   --  Kind selects the meaningful response/failure fields; no public default
   --  timeout, resource limit, or result classification is introduced.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Replication_Result is record
      Kind        : Get_Bucket_Replication_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Get_Bucket_Replication_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded current replication-configuration read with one hidden
   --  HTTP child. It owns its signed request and response through Finish.
   type Get_Bucket_Replication_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded current replication-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose replication configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established replication read
   procedure Get_Replication_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Replication_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded current replication-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose replication configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven replication read
   function Get_Replication_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Replication_Operation;

   --  Consume one terminal GetBucketReplication operation.
   --  @param Operation Terminal replication read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Replication_Operation;
      Result    : out Get_Bucket_Replication_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one current replication configuration by waiting on the same
   --  owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose replication configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Replication_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Replication_Result;

   --  Shape of a terminal GetBucketMetricsConfiguration read.
   --  @enum Get_Bucket_Metrics_Response_Available Modeled response exists
   --  @enum Get_Bucket_Metrics_Exchange_Failed No complete response exists
   type Get_Bucket_Metrics_Result_Kind is
     (Get_Bucket_Metrics_Response_Available,
      Get_Bucket_Metrics_Exchange_Failed);

   --  Typed metrics configuration response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Metrics_Result is record
      Kind        : Get_Bucket_Metrics_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Get_Bucket_Metrics_Configuration_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded named metrics-configuration read with one hidden HTTP
   --  child. It owns its signed request and response through Finish.
   type Get_Bucket_Metrics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one named metrics-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configuration is requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established metrics read
   procedure Get_Metrics_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Metrics_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one named metrics-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configuration is requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven metrics read
   function Get_Metrics_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Metrics_Operation;

   --  Consume one terminal GetBucketMetricsConfiguration operation.
   --  @param Operation Terminal metrics read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Metrics_Operation;
      Result    : out Get_Bucket_Metrics_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one named metrics configuration by waiting on the same
   --  owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configuration is requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Metrics_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Metrics_Result;

   --  Shape of a terminal ListBucketMetricsConfigurations read.
   --  @enum List_Bucket_Metrics_Response_Available Modeled page exists
   --  @enum List_Bucket_Metrics_Exchange_Failed No complete response exists
   type List_Bucket_Metrics_Result_Kind is
     (List_Bucket_Metrics_Response_Available,
      List_Bucket_Metrics_Exchange_Failed);

   --  Typed metrics-configuration page or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Bucket_Metrics_Result is record
      Kind        : List_Bucket_Metrics_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.List_Bucket_Metrics_Configurations_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded metrics-configuration page read with one hidden HTTP child.
   --  It owns its signed request and response through typed Finish; callers
   --  decide whether and when to submit any returned continuation token.
   type List_Bucket_Metrics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one metrics-configuration page read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configurations are requested
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established page read
   procedure List_Metrics_Configurations
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out List_Bucket_Metrics_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one metrics-configuration page read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose metrics configurations are requested
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven metrics page read
   function List_Metrics_Configurations
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return List_Bucket_Metrics_Operation;

   --  Consume one terminal ListBucketMetricsConfigurations operation.
   --  @param Operation Terminal metrics page read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Bucket_Metrics_Operation;
      Result    : out List_Bucket_Metrics_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one metrics-configuration page by waiting on the same owner-driven
   --  state machine used by composable callers. Continuation remains explicit
   --  in Parameters; the wrapper never starts a hidden next-page request.
   function List_Metrics_Configurations
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return List_Bucket_Metrics_Result;

   --  Shape of a terminal ListBucketAnalyticsConfigurations read.
   --  @enum List_Bucket_Analytics_Response_Available Modeled page exists
   --  @enum List_Bucket_Analytics_Exchange_Failed No complete response exists
   type List_Bucket_Analytics_Result_Kind is
     (List_Bucket_Analytics_Response_Available,
      List_Bucket_Analytics_Exchange_Failed);

   --  Typed analytics-configuration page or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Bucket_Analytics_Result is record
      Kind        : List_Bucket_Analytics_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.List_Bucket_Analytics_Configurations_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded analytics-configuration page read with one hidden HTTP
   --  child. It owns its signed request and response through typed Finish;
   --  callers decide whether and when to submit a returned continuation.
   type List_Bucket_Analytics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one analytics-configuration page read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configurations are requested
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established page read
   procedure List_Analytics_Configurations
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out List_Bucket_Analytics_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one analytics-configuration page read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configurations are requested
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven analytics page read
   function List_Analytics_Configurations
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return List_Bucket_Analytics_Operation;

   --  Consume one terminal ListBucketAnalyticsConfigurations operation.
   --  @param Operation Terminal analytics page read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Bucket_Analytics_Operation;
      Result    : out List_Bucket_Analytics_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one analytics-configuration page by waiting on the same
   --  owner-driven state machine used by composable callers. Continuation is
   --  explicit in Parameters; no hidden next-page request is started.
   function List_Analytics_Configurations
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return List_Bucket_Analytics_Result;

   --  Shape of a terminal GetBucketAnalyticsConfiguration read.
   --  @enum Get_Bucket_Analytics_Response_Available Modeled response exists
   --  @enum Get_Bucket_Analytics_Exchange_Failed No complete response exists
   type Get_Bucket_Analytics_Result_Kind is
     (Get_Bucket_Analytics_Response_Available,
      Get_Bucket_Analytics_Exchange_Failed);

   --  Typed analytics configuration response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Analytics_Result is record
      Kind        : Get_Bucket_Analytics_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Get_Bucket_Analytics_Configuration_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded named analytics-configuration read with one hidden HTTP
   --  child. It owns its signed request and response through Finish.
   type Get_Bucket_Analytics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one named analytics-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configuration is requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established analytics read
   procedure Get_Analytics_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Analytics_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one named analytics-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configuration is requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven analytics read
   function Get_Analytics_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Analytics_Operation;

   --  Consume one terminal GetBucketAnalyticsConfiguration operation.
   --  @param Operation Terminal analytics read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Analytics_Operation;
      Result    : out Get_Bucket_Analytics_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one named analytics configuration by waiting on the same
   --  owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose analytics configuration is requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Analytics_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Analytics_Result;
   --  Shape of a terminal GetBucketIntelligentTieringConfiguration read.
   --  @enum Get_Bucket_Intelligent_Tiering_Response_Available Modeled
   --  response exists
   --  @enum Get_Bucket_Intelligent_Tiering_Exchange_Failed No complete
   --  response exists
   type Get_Bucket_Intelligent_Tiering_Result_Kind is
     (Get_Bucket_Intelligent_Tiering_Response_Available,
      Get_Bucket_Intelligent_Tiering_Exchange_Failed);

   --  Typed Intelligent-Tiering configuration response or composable HTTP
   --  failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Intelligent_Tiering_Result is record
      Kind        : Get_Bucket_Intelligent_Tiering_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    :
        Low_Level.Get_Bucket_Intelligent_Tiering_Configuration_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded named Intelligent-Tiering-configuration read with one
   --  hidden HTTP child. It owns its signed request and response through
   --  Finish.
   type Get_Bucket_Intelligent_Tiering_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one named Intelligent-Tiering-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Intelligent-Tiering configuration is
   --  requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established Intelligent-Tiering
   --  read
   procedure Get_Intelligent_Tiering_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Intelligent_Tiering_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one named Intelligent-Tiering-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Intelligent-Tiering configuration is
   --  requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven Intelligent-Tiering read
   function Get_Intelligent_Tiering_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Intelligent_Tiering_Operation;

   --  Consume one terminal GetBucketIntelligentTieringConfiguration
   --  operation.
   --  @param Operation Terminal Intelligent-Tiering read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Intelligent_Tiering_Operation;
      Result    : out Get_Bucket_Intelligent_Tiering_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one named Intelligent-Tiering configuration by waiting on the same
   --  owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Intelligent-Tiering configuration is
   --  requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Intelligent_Tiering_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Intelligent_Tiering_Result;

   --  Shape of a terminal ListBucketIntelligentTieringConfigurations read.
   --  @enum List_Bucket_Intelligent_Tiering_Response_Available Page exists
   --  @enum List_Bucket_Intelligent_Tiering_Exchange_Failed No response
   type List_Bucket_Intelligent_Tiering_Result_Kind is
     (List_Bucket_Intelligent_Tiering_Response_Available,
      List_Bucket_Intelligent_Tiering_Exchange_Failed);

   --  Typed Intelligent-Tiering page or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Bucket_Intelligent_Tiering_Result is record
      Kind        : List_Bucket_Intelligent_Tiering_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    :
        Low_Level.List_Bucket_Intelligent_Tiering_Configurations_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded Intelligent-Tiering page read with one hidden HTTP child.
   --  It owns its signed request and response through typed Finish; callers
   --  decide whether and when to submit a returned continuation.
   type List_Bucket_Intelligent_Tiering_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one Intelligent-Tiering page read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Intelligent-Tiering configurations are read
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established page read
   procedure List_Intelligent_Tiering_Configurations
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out List_Bucket_Intelligent_Tiering_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one Intelligent-Tiering page read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose Intelligent-Tiering configurations are read
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven Intelligent-Tiering page read
   function List_Intelligent_Tiering_Configurations
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return List_Bucket_Intelligent_Tiering_Operation;

   --  Consume one terminal ListBucketIntelligentTieringConfigurations
   --  operation.
   --  @param Operation Terminal Intelligent-Tiering page read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Bucket_Intelligent_Tiering_Operation;
      Result    : out List_Bucket_Intelligent_Tiering_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one Intelligent-Tiering page by waiting on the same owner-driven
   --  state machine used by composable callers. Continuation is explicit in
   --  Parameters; no hidden next-page request is started.
   function List_Intelligent_Tiering_Configurations
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return List_Bucket_Intelligent_Tiering_Result;

   --  Shape of a terminal ListBucketInventoryConfigurations read.
   --  @enum List_Bucket_Inventory_Response_Available Modeled page exists
   --  @enum List_Bucket_Inventory_Exchange_Failed No complete response exists
   type List_Bucket_Inventory_Result_Kind is
     (List_Bucket_Inventory_Response_Available,
      List_Bucket_Inventory_Exchange_Failed);

   --  Typed inventory-configuration page or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type List_Bucket_Inventory_Result is record
      Kind        : List_Bucket_Inventory_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.List_Bucket_Inventory_Configurations_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded inventory-configuration page read with one hidden HTTP
   --  child. It owns its signed request and response through typed Finish;
   --  callers decide whether and when to submit a returned continuation.
   type List_Bucket_Inventory_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one inventory-configuration page read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configurations are read
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established page read
   procedure List_Inventory_Configurations
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out List_Bucket_Inventory_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one inventory-configuration page read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configurations are read
   --  @param Parameters Complete modeled cursor and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven inventory page read
   function List_Inventory_Configurations
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return List_Bucket_Inventory_Operation;

   --  Consume one terminal ListBucketInventoryConfigurations operation.
   --  @param Operation Terminal inventory page read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out List_Bucket_Inventory_Operation;
      Result    : out List_Bucket_Inventory_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one inventory page by waiting on the same owner-driven state
   --  machine used by composable callers. Continuation is explicit in
   --  Parameters; no hidden next-page request is started.
   function List_Inventory_Configurations
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.List_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return List_Bucket_Inventory_Result;

   --  Shape of a terminal GetBucketInventoryConfiguration read.
   --  @enum Get_Bucket_Inventory_Response_Available Modeled
   --  response exists
   --  @enum Get_Bucket_Inventory_Exchange_Failed No complete
   --  response exists
   type Get_Bucket_Inventory_Result_Kind is
     (Get_Bucket_Inventory_Response_Available,
      Get_Bucket_Inventory_Exchange_Failed);

   --  Typed inventory configuration response or composable HTTP
   --  failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Inventory_Result is record
      Kind        : Get_Bucket_Inventory_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    :
        Low_Level.Get_Bucket_Inventory_Configuration_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded named inventory-configuration read with one
   --  hidden HTTP child. It owns its signed request and response through
   --  Finish.
   type Get_Bucket_Inventory_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one named inventory-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configuration is
   --  requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established inventory
   --  read
   procedure Get_Inventory_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Inventory_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one named inventory-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configuration is
   --  requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven inventory read
   function Get_Inventory_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Inventory_Operation;

   --  Consume one terminal GetBucketInventoryConfiguration
   --  operation.
   --  @param Operation Terminal inventory read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Inventory_Operation;
      Result    : out Get_Bucket_Inventory_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one named inventory configuration by waiting on the same
   --  owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose inventory configuration is
   --  requested
   --  @param Parameters Complete modeled identifier and owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Inventory_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_With_ID_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Inventory_Result;

   --  Shape of a terminal GetBucketLogging read.
   --  @enum Get_Bucket_Logging_Response_Available Modeled response exists
   --  @enum Get_Bucket_Logging_Exchange_Failed No complete response exists
   type Get_Bucket_Logging_Result_Kind is
     (Get_Bucket_Logging_Response_Available,
      Get_Bucket_Logging_Exchange_Failed);

   --  Typed logging status response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Logging_Result is record
      Kind        : Get_Bucket_Logging_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Get_Bucket_Logging_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded logging-status read with one hidden HTTP child. It owns its
   --  signed request and response through Finish.
   type Get_Bucket_Logging_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bucket logging-status read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose logging status is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established logging read
   procedure Get_Logging
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Logging_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bucket logging-status read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose logging status is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven logging read
   function Get_Logging
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Logging_Operation;

   --  Consume one terminal GetBucketLogging operation.
   --  @param Operation Terminal logging read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Logging_Operation;
      Result    : out Get_Bucket_Logging_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read current logging status by waiting on the same owner-driven state
   --  machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose logging status is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Logging
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Logging_Result;

   --  Shape of a terminal GetBucketWebsite read.
   --  @enum Get_Bucket_Website_Response_Available Modeled response exists
   --  @enum Get_Bucket_Website_Exchange_Failed No complete response exists
   type Get_Bucket_Website_Result_Kind is
     (Get_Bucket_Website_Response_Available,
      Get_Bucket_Website_Exchange_Failed);

   --  Typed website configuration response or composable HTTP failure.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Website_Result is record
      Kind        : Get_Bucket_Website_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Get_Bucket_Website_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded website-configuration read with one hidden HTTP child. It
   --  owns its signed request and response through Finish.
   type Get_Bucket_Website_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bucket website-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose website configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established website read
   procedure Get_Website
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Website_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bucket website-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose website configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven website read
   function Get_Website
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Website_Operation;

   --  Consume one terminal GetBucketWebsite operation.
   --  @param Operation Terminal website read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Website_Operation;
      Result    : out Get_Bucket_Website_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read current website configuration by waiting on the same owner-driven
   --  state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose website configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Website
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Website_Result;

   --  Shape of a terminal PutBucketReplication mutation.
   --  @enum Put_Bucket_Replication_Response_Available Modeled response exists
   --  @enum Put_Bucket_Replication_Exchange_Failed No complete response exists
   type Put_Bucket_Replication_Result_Kind is
     (Put_Bucket_Replication_Response_Available,
      Put_Bucket_Replication_Exchange_Failed);

   --  Typed replication replacement response and application certainty.
   --  Every checksum, resource, and deadline choice remains caller-supplied.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Replication_Result is record
      Kind        : Put_Bucket_Replication_Result_Kind;
      Disposition : Bucket_Replication_Mutation_Disposition;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Put_Bucket_Control_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One-shot replication replacement with one hidden HTTP child. The
   --  operation owns the exact serialized and signed body through Finish; it
   --  never rewinds, replays, or retains caller input.
   type Put_Bucket_Replication_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying replication replacement.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive replication graph
   --  @param Parameters MD5, required checksum, token, and owner controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request/response XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established replication mutation
   procedure Set_Replication_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Replication.
        Replication_Configuration;
      Parameters : Low_Level.Put_Bucket_Replication_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Put_Bucket_Replication_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying replication replacement.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive replication graph
   --  @param Parameters MD5, required checksum, token, and owner controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request/response XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven replication mutation
   function Set_Replication_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Replication.
        Replication_Configuration;
      Parameters : Low_Level.Put_Bucket_Replication_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Put_Bucket_Replication_Operation;

   --  Consume one terminal PutBucketReplication operation.
   --  @param Operation Terminal replication replacement
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Replication_Operation;
      Result    : out Put_Bucket_Replication_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the replication configuration by waiting on the same
   --  nonreplaying owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive replication graph
   --  @param Parameters MD5, required checksum, token, and owner controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected request/response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Replication_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Replication.
        Replication_Configuration;
      Parameters : Low_Level.Put_Bucket_Replication_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Put_Bucket_Replication_Result;

   --  Shape of a terminal GetBucketNotificationConfiguration read.
   --  @enum Get_Bucket_Notification_Response_Available Modeled response
   --     exists
   --  @enum Get_Bucket_Notification_Exchange_Failed No complete response
   --     exists
   type Get_Bucket_Notification_Result_Kind is
     (Get_Bucket_Notification_Response_Available,
      Get_Bucket_Notification_Exchange_Failed);

   --  Typed notification configuration response or composable HTTP failure.
   --  Kind selects the meaningful response/failure fields; no public default
   --  timeout, resource limit, or result classification is introduced.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Notification_Result is record
      Kind        : Get_Bucket_Notification_Result_Kind;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    :
        Low_Level.Get_Bucket_Notification_Configuration_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One bounded current notification-configuration read with one hidden
   --  HTTP child. It owns its signed request and response through Finish.
   type Get_Bucket_Notification_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded current notification-configuration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose notification configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established notification read
   procedure Get_Notification_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Get_Bucket_Notification_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded current notification-configuration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose notification configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven notification read
   function Get_Notification_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Get_Bucket_Notification_Operation;

   --  Consume one terminal GetBucketNotificationConfiguration operation.
   --  @param Operation Terminal notification read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Notification_Operation;
      Result    : out Get_Bucket_Notification_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one current notification configuration by waiting on the same
   --  owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose notification configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Notification_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Get_Bucket_Notification_Result;

   --  Mutation certainty for one current notification-configuration replace.
   --  @enum Bucket_Notification_Mutation_Completed Provider accepted the
   --     replacement
   --  @enum Bucket_Notification_Mutation_Definitely_Not_Applied Provider
   --     conclusively rejected the replacement
   --  @enum Bucket_Notification_Mutation_Outcome_Unknown Admission or
   --     publication cannot be determined from the terminal exchange
   --  @enum Bucket_Notification_Mutation_Cancelled_Before_Admission
   --     Cancellation completed before request admission
   type Bucket_Notification_Mutation_Disposition is
     (Bucket_Notification_Mutation_Completed,
      Bucket_Notification_Mutation_Definitely_Not_Applied,
      Bucket_Notification_Mutation_Outcome_Unknown,
      Bucket_Notification_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketNotificationConfiguration mutation.
   --  @enum Put_Bucket_Notification_Response_Available A modeled response
   --     exists
   --  @enum Put_Bucket_Notification_Exchange_Failed No complete response
   --     exists
   type Put_Bucket_Notification_Result_Kind is
     (Put_Bucket_Notification_Response_Available,
      Put_Bucket_Notification_Exchange_Failed);

   --  Typed notification replacement response and admission certainty.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Notification_Result is record
      Kind        : Put_Bucket_Notification_Result_Kind;
      Disposition : Bucket_Notification_Mutation_Disposition;
      Failure     : Failure_Reason;
      Admission   : Flyology.HTTP.Client.Admission_Certainty;
      Response    : Low_Level.Put_Bucket_Control_Outcome;
      HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
      HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
      Detail      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One nonreplaying notification replacement with one hidden HTTP child.
   type Put_Bucket_Notification_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying notification replacement.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose notification graph is replaced
   --  @param Value Complete configuration copied into the owned request body
   --  @param Parameters Complete owner and destination-validation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @param Operation Fresh or consumed established notification mutation
   procedure Set_Notification_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Notifications.
        Notification_Configuration;
      Parameters :
        Low_Level.Put_Bucket_Notification_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token;
      Operation  : in out Put_Bucket_Notification_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying notification replacement.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose notification graph is replaced
   --  @param Value Complete configuration copied into the owned request body
   --  @param Parameters Complete owner and destination-validation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected request and error XML limits
   --  @param Token Caller-selected cancellation source or null
   --  @return Started owner-driven notification mutation
   function Set_Notification_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Notifications.
        Notification_Configuration;
      Parameters :
        Low_Level.Put_Bucket_Notification_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token)
      return Put_Bucket_Notification_Operation;

   --  Consume one terminal PutBucketNotificationConfiguration operation.
   --  @param Operation Terminal notification replacement
   --  @param Result Typed response and mutation certainty
   procedure Finish
     (Operation : in out Put_Bucket_Notification_Operation;
      Result    : out Put_Bucket_Notification_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the notification configuration by waiting on the same
   --  nonreplaying owner-driven state machine used by composable callers.
   --  @param Client Configured caller-owned Flyology HTTP client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose notification graph is replaced
   --  @param Value Complete configuration copied into the owned request body
   --  @param Parameters Complete owner and destination-validation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Caller-selected cancellation source or null
   --  @param Limits Caller-selected request and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Notification_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Notifications.
        Notification_Configuration;
      Parameters :
        Low_Level.Put_Bucket_Notification_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Put_Bucket_Notification_Result;

   --  Shape of a terminal DeleteBucketLifecycle mutation.
   --  @enum Delete_Bucket_Lifecycle_Response_Available Modeled response
   --     exists
   --  @enum Delete_Bucket_Lifecycle_Exchange_Failed No complete response
   --     exists
   type Delete_Bucket_Lifecycle_Result_Kind is
     (Delete_Bucket_Lifecycle_Response_Available,
      Delete_Bucket_Lifecycle_Exchange_Failed);

   --  Typed DeleteBucketLifecycle certainty and response or HTTP failure.
   --  Record defaults are deterministic aggregate sentinels only and never
   --  classify a decoded terminal result.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Lifecycle_Result
     (Kind : Delete_Bucket_Lifecycle_Result_Kind :=
        Delete_Bucket_Lifecycle_Exchange_Failed)
   is record
      Disposition : Bucket_Lifecycle_Mutation_Disposition :=
        Bucket_Lifecycle_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Lifecycle_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Lifecycle_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketLifecycle parent. Its signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_Lifecycle_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads retain the existing Delete_Lifecycle defaults:
   --  us-east-1, path-style addressing, shared XML limits, and no
   --  cancellation source. The values preserve existing signing and timeout
   --  policy rather than introducing operation-specific policy.
   --  Start or restart one nonreplaying DeleteBucketLifecycle mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose lifecycle configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Delete_Lifecycle
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Lifecycle_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteBucketLifecycle mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose lifecycle configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven lifecycle deletion
   function Delete_Lifecycle
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Lifecycle_Operation;

   --  Consume one terminal DeleteBucketLifecycle operation.
   --  @param Operation Terminal bucket-lifecycle deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Lifecycle_Operation;
      Result    : out Delete_Bucket_Lifecycle_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the bucket lifecycle configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose lifecycle configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Lifecycle
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Lifecycle_Result;

   --  Shape of a terminal GetBucketOwnershipControls read.
   --  @enum Get_Bucket_Ownership_Controls_Response_Available Modeled
   --     response exists
   --  @enum Get_Bucket_Ownership_Controls_Exchange_Failed No complete response
   --     exists
   type Get_Bucket_Ownership_Controls_Result_Kind is
     (Get_Bucket_Ownership_Controls_Response_Available,
      Get_Bucket_Ownership_Controls_Exchange_Failed);

   --  Typed GetBucketOwnershipControls response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Ownership_Controls_Result
     (Kind : Get_Bucket_Ownership_Controls_Result_Kind :=
        Get_Bucket_Ownership_Controls_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Ownership_Controls_Response_Available =>
            Response : Low_Level.Get_Bucket_Ownership_Controls_Outcome;
         when Get_Bucket_Ownership_Controls_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketOwnershipControls parent with one hidden HTTP
   --  child. The operation owns its signed request and retained response
   --  bytes through terminal Finish, with no borrowed request input after
   --  signing.
   type Get_Bucket_Ownership_Controls_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads use the package's established bucket-control defaults:
   --  us-east-1, path-style addressing, shared XML limits, and no
   --  cancellation source. The values preserve existing request-signing
   --  policy rather than introducing new operation-specific policy.
   --  Start or restart one bounded GetBucketOwnershipControls read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration read
   procedure Get_Ownership_Controls
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Ownership_Controls_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketOwnershipControls read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration read
   function Get_Ownership_Controls
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Ownership_Controls_Operation;

   --  Consume one terminal GetBucketOwnershipControls operation.
   --  @param Operation Terminal ownership-controls read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Ownership_Controls_Operation;
      Result    : out Get_Bucket_Ownership_Controls_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one ownership-controls snapshot by waiting on the provider-owned
   --  composable operation. The established region, addressing, 30-second
   --  timeout, shared XML-limit, and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Ownership_Controls
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Ownership_Controls_Result;

   --  Shape of a terminal GetPublicAccessBlock read.
   --  @enum Get_Public_Access_Block_Response_Available Modeled response exists
   --  @enum Get_Public_Access_Block_Exchange_Failed No complete response
   --     exists
   type Get_Public_Access_Block_Result_Kind is
     (Get_Public_Access_Block_Response_Available,
      Get_Public_Access_Block_Exchange_Failed);

   --  Typed GetPublicAccessBlock response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Public_Access_Block_Result
     (Kind : Get_Public_Access_Block_Result_Kind :=
        Get_Public_Access_Block_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Public_Access_Block_Response_Available =>
            Response : Low_Level.Get_Public_Access_Block_Outcome;
         when Get_Public_Access_Block_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetPublicAccessBlock parent with one hidden HTTP child. The
   --  operation owns its signed request and retained response bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Public_Access_Block_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Get_Public_Access_Block defaults (us-east-1, path-style addressing,
   --  shared XML limits, and no cancellation source). They preserve source
   --  compatibility and request signing rather than introducing new policy.
   --  Start or restart one bounded GetPublicAccessBlock read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration read
   procedure Get_Public_Access_Block
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Public_Access_Block_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetPublicAccessBlock read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration read
   function Get_Public_Access_Block
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Public_Access_Block_Operation;

   --  Consume one terminal GetPublicAccessBlock operation.
   --  @param Operation Terminal public-access-block read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Public_Access_Block_Operation;
      Result    : out Get_Public_Access_Block_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one public-access-block snapshot by waiting on the provider-owned
   --  composable operation. The established region, addressing, 30-second
   --  timeout, shared XML-limit, and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Public_Access_Block
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Public_Access_Block_Result;

   --  What is known about an ownership-controls mutation after terminal
   --  drain. Outcome unknown requires caller-selected read reconciliation
   --  before any retry.
   --  @enum Bucket_Ownership_Controls_Mutation_Completed Complete response
   --     proves
   --     the requested mutation completed
   --  @enum Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Bucket_Ownership_Controls_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Bucket_Ownership_Controls_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Bucket_Ownership_Controls_Mutation_Disposition is
     (Bucket_Ownership_Controls_Mutation_Completed,
      Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied,
      Bucket_Ownership_Controls_Mutation_Outcome_Unknown,
      Bucket_Ownership_Controls_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketOwnershipControls mutation.
   --  @enum Put_Bucket_Ownership_Controls_Response_Available Modeled response
   --     exists
   --  @enum Put_Bucket_Ownership_Controls_Exchange_Failed No complete response
   --     exists
   type Put_Bucket_Ownership_Controls_Result_Kind is
     (Put_Bucket_Ownership_Controls_Response_Available,
      Put_Bucket_Ownership_Controls_Exchange_Failed);

   --  Typed PutBucketOwnershipControls certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Ownership_Controls_Result
     (Kind : Put_Bucket_Ownership_Controls_Result_Kind :=
        Put_Bucket_Ownership_Controls_Exchange_Failed)
   is record
      Disposition : Bucket_Ownership_Controls_Mutation_Disposition :=
        Bucket_Ownership_Controls_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Ownership_Controls_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_Ownership_Controls_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketOwnershipControls parent. The prepared request owns
   --  the exact serialized configuration and signing inputs through Finish.
   --  The operation never rewinds or replays its body.
   type Put_Bucket_Ownership_Controls_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  These overloads use the package's established bucket-control defaults:
   --  us-east-1, path-style addressing, shared XML limits, and no
   --  cancellation source. The values preserve existing request-signing
   --  policy rather than introducing new operation-specific policy.
   --  Start or restart one nonreplaying PutBucketOwnershipControls mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Set_Ownership_Controls
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Ownership_Controls_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Ownership_Controls_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketOwnershipControls mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration mutation
   function Set_Ownership_Controls
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Ownership_Controls_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Ownership_Controls_Operation;

   --  Consume one terminal PutBucketOwnershipControls operation.
   --  @param Operation Terminal ownership-controls mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Ownership_Controls_Operation;
      Result    : out Put_Bucket_Ownership_Controls_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the ownership-controls document by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Ownership_Controls
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Ownership_Controls_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_Ownership_Controls_Result;

   --  Shape of a terminal DeleteBucketOwnershipControls mutation.
   --  @enum Delete_Ownership_Controls_Response_Available Modeled response
   --     exists
   --  @enum Delete_Ownership_Controls_Exchange_Failed No complete response
   --     exists
   type Delete_Ownership_Controls_Result_Kind is
     (Delete_Ownership_Controls_Response_Available,
      Delete_Ownership_Controls_Exchange_Failed);

   --  Typed DeleteBucketOwnershipControls certainty and response or HTTP
   --  failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Ownership_Controls_Result
     (Kind : Delete_Ownership_Controls_Result_Kind :=
        Delete_Ownership_Controls_Exchange_Failed)
   is record
      Disposition : Bucket_Ownership_Controls_Mutation_Disposition :=
        Bucket_Ownership_Controls_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Ownership_Controls_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Ownership_Controls_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketOwnershipControls parent. Its signed request and
   --  empty nonreplayable source remain owned through terminal Finish.
   type Delete_Ownership_Controls_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Delete_Ownership_Controls defaults (us-east-1, path-style addressing,
   --  shared XML limits, and no cancellation source). They preserve source
   --  compatibility and request signing rather than introducing new policy.
   --  Start or restart one nonreplaying DeleteBucketOwnershipControls
   --  mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Delete_Ownership_Controls
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Ownership_Controls_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteBucketOwnershipControls mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration deletion
   function Delete_Ownership_Controls
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Ownership_Controls_Operation;

   --  Consume one terminal DeleteBucketOwnershipControls operation.
   --  @param Operation Terminal ownership-controls deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Ownership_Controls_Operation;
      Result    : out Delete_Ownership_Controls_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the ownership-controls configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Ownership_Controls
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Ownership_Controls_Result;

   --  What is known about an ABAC mutation after terminal drain. Outcome
   --  unknown requires caller-selected read reconciliation before any retry.
   --  @enum ABAC_Mutation_Completed Complete response proves
   --     the requested mutation completed
   --  @enum ABAC_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum ABAC_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum ABAC_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type ABAC_Mutation_Disposition is
     (ABAC_Mutation_Completed,
      ABAC_Mutation_Definitely_Not_Applied,
      ABAC_Mutation_Outcome_Unknown,
      ABAC_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketAbac mutation.
   --  @enum Put_Bucket_ABAC_Response_Available Modeled response
   --     exists
   --  @enum Put_Bucket_ABAC_Exchange_Failed No complete response
   --     exists
   type Put_Bucket_ABAC_Result_Kind is
     (Put_Bucket_ABAC_Response_Available,
      Put_Bucket_ABAC_Exchange_Failed);

   --  Typed PutBucketAbac certainty and response or HTTP failure.
   --  Default initialization is the conservative inert exchange-failed
   --  shape used by operation storage before a terminal result is assigned;
   --  it never claims mutation completion.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_ABAC_Result
     (Kind : Put_Bucket_ABAC_Result_Kind :=
        Put_Bucket_ABAC_Exchange_Failed)
   is record
      Disposition : ABAC_Mutation_Disposition :=
        ABAC_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_ABAC_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_ABAC_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketAbac parent. The prepared request owns the exact
   --  serialized ABAC status document and signing inputs through Finish. The
   --  operation never rewinds or replays its body.
   type Put_Bucket_ABAC_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Set_ABAC defaults (us-east-1, path-style addressing,
   --  shared XML limits, and no cancellation source). They preserve source
   --  compatibility and request signing rather than introducing new policy.
   --  Start or restart one nonreplaying PutBucketAbac mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose ABAC setting is replaced
   --  @param Value Presence-preserving ABAC status copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established ABAC mutation
   procedure Set_ABAC
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Abac_Status;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_ABAC_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketAbac mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose ABAC setting is replaced
   --  @param Value Presence-preserving ABAC status copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ABAC mutation
   function Set_ABAC
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Abac_Status;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_ABAC_Operation;

   --  Consume one terminal PutBucketAbac operation.
   --  @param Operation Terminal ABAC mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_ABAC_Operation;
      Result    : out Put_Bucket_ABAC_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the ABAC document by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose ABAC setting is replaced
   --  @param Value Presence-preserving ABAC status
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_ABAC
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Abac_Status;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_ABAC_Result;

   --  What is known about an acceleration mutation after terminal drain.
   --  Outcome unknown requires caller-selected read reconciliation before
   --  any retry.
   --  @enum Acceleration_Mutation_Completed Complete response proves
   --     the requested mutation completed
   --  @enum Acceleration_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Acceleration_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Acceleration_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Acceleration_Mutation_Disposition is
     (Acceleration_Mutation_Completed,
      Acceleration_Mutation_Definitely_Not_Applied,
      Acceleration_Mutation_Outcome_Unknown,
      Acceleration_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketAccelerateConfiguration mutation.
   --  @enum Put_Bucket_Accelerate_Configuration_Response_Available
   --     Modeled response exists
   --  @enum Put_Bucket_Accelerate_Configuration_Exchange_Failed
   --     No complete response exists
   type Put_Bucket_Accelerate_Configuration_Result_Kind is
     (Put_Bucket_Accelerate_Configuration_Response_Available,
      Put_Bucket_Accelerate_Configuration_Exchange_Failed);

   --  Typed PutBucketAccelerateConfiguration certainty and response or HTTP
   --  failure. Default initialization is the conservative inert
   --  exchange-failed shape used by operation storage before a terminal
   --  result is assigned; it never claims mutation completion.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Accelerate_Configuration_Result
     (Kind : Put_Bucket_Accelerate_Configuration_Result_Kind :=
        Put_Bucket_Accelerate_Configuration_Exchange_Failed)
   is record
      Disposition : Acceleration_Mutation_Disposition :=
        Acceleration_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Accelerate_Configuration_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_Accelerate_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketAccelerateConfiguration parent. The prepared request
   --  owns the exact serialized acceleration status and signing inputs
   --  through Finish. The operation never rewinds or replays its body.
   type Put_Bucket_Accelerate_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Set_Accelerate_Configuration defaults (us-east-1, path-style
   --  addressing, shared XML limits, and no cancellation source). They
   --  preserve source compatibility and request signing rather than
   --  introducing new policy. Start or restart one nonreplaying
   --  PutBucketAccelerateConfiguration mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose acceleration setting is replaced
   --  @param Value Presence-preserving acceleration status copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established acceleration mutation
   procedure Set_Accelerate_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Accelerate_Status;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Accelerate_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketAccelerateConfiguration mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose acceleration setting is replaced
   --  @param Value Presence-preserving acceleration status copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven acceleration mutation
   function Set_Accelerate_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Accelerate_Status;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Accelerate_Configuration_Operation;

   --  Consume one terminal PutBucketAccelerateConfiguration operation.
   --  @param Operation Terminal acceleration mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Accelerate_Configuration_Operation;
      Result    : out Put_Bucket_Accelerate_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the acceleration status document by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose acceleration setting is replaced
   --  @param Value Presence-preserving acceleration status
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Accelerate_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Accelerate_Status;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_Accelerate_Configuration_Result;

   --  What is known about a requester-payment mutation after terminal
   --  drain. Outcome unknown requires caller-selected read reconciliation
   --  before any retry.
   --  @enum Request_Payment_Mutation_Completed Complete response proves
   --     the requested mutation completed
   --  @enum Request_Payment_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Request_Payment_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Request_Payment_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Request_Payment_Mutation_Disposition is
     (Request_Payment_Mutation_Completed,
      Request_Payment_Mutation_Definitely_Not_Applied,
      Request_Payment_Mutation_Outcome_Unknown,
      Request_Payment_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketRequestPayment mutation.
   --  @enum Put_Bucket_Request_Payment_Response_Available Modeled response
   --     exists
   --  @enum Put_Bucket_Request_Payment_Exchange_Failed No complete response
   --     exists
   type Put_Bucket_Request_Payment_Result_Kind is
     (Put_Bucket_Request_Payment_Response_Available,
      Put_Bucket_Request_Payment_Exchange_Failed);

   --  Typed PutBucketRequestPayment certainty and response or HTTP failure.
   --  Default initialization is the conservative inert exchange-failed
   --  shape used by operation storage before a terminal result is assigned;
   --  it never claims mutation completion.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Request_Payment_Result
     (Kind : Put_Bucket_Request_Payment_Result_Kind :=
        Put_Bucket_Request_Payment_Exchange_Failed)
   is record
      Disposition : Request_Payment_Mutation_Disposition :=
        Request_Payment_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Request_Payment_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_Request_Payment_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketRequestPayment parent. The prepared request owns the
   --  exact serialized payer document and signing inputs through Finish. The
   --  operation never rewinds or replays its body.
   type Put_Bucket_Request_Payment_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Set_Request_Payment defaults (us-east-1, path-style addressing,
   --  shared XML limits, and no cancellation source). They preserve source
   --  compatibility and request signing rather than introducing new policy.
   --  Start or restart one nonreplaying PutBucketRequestPayment mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose requester-payment setting is replaced
   --  @param Value Required payer value copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established requester-payment
   --     mutation
   procedure Set_Request_Payment
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Payer;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Request_Payment_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketRequestPayment mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose requester-payment setting is replaced
   --  @param Value Required payer value copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven requester-payment mutation
   function Set_Request_Payment
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Payer;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Request_Payment_Operation;

   --  Consume one terminal PutBucketRequestPayment operation.
   --  @param Operation Terminal requester-payment mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Request_Payment_Operation;
      Result    : out Put_Bucket_Request_Payment_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the requester-payment document by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose requester-payment setting is replaced
   --  @param Value Required payer value
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Request_Payment
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Payer;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_Request_Payment_Result;

   --  What is known about a public-access-block mutation after terminal
   --  drain. Outcome unknown requires caller-selected read reconciliation
   --  before any retry.
   --  @enum Public_Access_Block_Mutation_Completed Complete response proves
   --     the requested mutation completed
   --  @enum Public_Access_Block_Mutation_Definitely_Not_Applied Exact
   --     rejection or non-admission proves no mutation occurred
   --  @enum Public_Access_Block_Mutation_Outcome_Unknown State requires
   --     caller-selected read reconciliation
   --  @enum Public_Access_Block_Mutation_Cancelled_Before_Admission
   --     Cancellation preceded possible server admission
   type Public_Access_Block_Mutation_Disposition is
     (Public_Access_Block_Mutation_Completed,
      Public_Access_Block_Mutation_Definitely_Not_Applied,
      Public_Access_Block_Mutation_Outcome_Unknown,
      Public_Access_Block_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutPublicAccessBlock mutation.
   --  @enum Put_Public_Access_Block_Response_Available Modeled response
   --     exists
   --  @enum Put_Public_Access_Block_Exchange_Failed No complete response
   --     exists
   type Put_Public_Access_Block_Result_Kind is
     (Put_Public_Access_Block_Response_Available,
      Put_Public_Access_Block_Exchange_Failed);

   --  Typed PutPublicAccessBlock certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Public_Access_Block_Result
     (Kind : Put_Public_Access_Block_Result_Kind :=
        Put_Public_Access_Block_Exchange_Failed)
   is record
      Disposition : Public_Access_Block_Mutation_Disposition :=
        Public_Access_Block_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Public_Access_Block_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Public_Access_Block_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutPublicAccessBlock parent. The prepared request owns the
   --  exact serialized configuration and signing inputs through Finish. The
   --  operation never rewinds or replays its body.
   type Put_Public_Access_Block_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Set_Public_Access_Block defaults (us-east-1, path-style addressing,
   --  shared XML limits, and no cancellation source). They preserve source
   --  compatibility and request signing rather than introducing new policy.
   --  Start or restart one nonreplaying PutPublicAccessBlock mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Set_Public_Access_Block
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Public_Access_Block_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Public_Access_Block_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutPublicAccessBlock mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration copied at start
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration mutation
   function Set_Public_Access_Block
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Public_Access_Block_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Public_Access_Block_Operation;

   --  Consume one terminal PutPublicAccessBlock operation.
   --  @param Operation Terminal public-access-block mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Public_Access_Block_Operation;
      Result    : out Put_Public_Access_Block_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace the public-access-block document by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete configuration is replaced
   --  @param Value Complete presence-sensitive configuration
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response and error XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Public_Access_Block
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.S3.Bucket_Controls.
        Public_Access_Block_Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Public_Access_Block_Result;

   --  Shape of a terminal DeletePublicAccessBlock mutation.
   --  @enum Delete_Public_Access_Block_Response_Available Modeled response
   --     exists
   --  @enum Delete_Public_Access_Block_Exchange_Failed No complete response
   --     exists
   type Delete_Public_Access_Block_Result_Kind is
     (Delete_Public_Access_Block_Response_Available,
      Delete_Public_Access_Block_Exchange_Failed);

   --  Typed DeletePublicAccessBlock certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Public_Access_Block_Result
     (Kind : Delete_Public_Access_Block_Result_Kind :=
        Delete_Public_Access_Block_Exchange_Failed)
   is record
      Disposition : Public_Access_Block_Mutation_Disposition :=
        Public_Access_Block_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Public_Access_Block_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Public_Access_Block_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeletePublicAccessBlock parent. Its signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Public_Access_Block_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Delete_Public_Access_Block defaults (us-east-1, path-style addressing,
   --  shared XML limits, and no cancellation source). They preserve source
   --  compatibility and request signing rather than introducing new policy.
   --  Start or restart one nonreplaying DeletePublicAccessBlock mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established configuration mutation
   procedure Delete_Public_Access_Block
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Public_Access_Block_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeletePublicAccessBlock mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven configuration deletion
   function Delete_Public_Access_Block
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Public_Access_Block_Operation;

   --  Consume one terminal DeletePublicAccessBlock operation.
   --  @param Operation Terminal public-access-block deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Public_Access_Block_Operation;
      Result    : out Delete_Public_Access_Block_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete the public-access-block configuration by waiting on the same
   --  nonreplaying provider-owned operation used by composable callers. The
   --  established region, addressing, 30-second timeout, shared XML-limit,
   --  and null-cancellation defaults are preserved.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete configuration is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response XML limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Public_Access_Block
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Public_Access_Block_Result;

   --  Remove the complete public-access-block configuration.
   function Delete_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Existing project-policy classification: the following synchronous
   --  Buckets calls retain the established us-east-1, path-style,
   --  absent-owner, and 30-second defaults. Changing them is source- and
   --  behavior-incompatible across this package.
   --  Read the optional transfer-acceleration status and requester-charged
   --  response header for one bucket.
   --  @param Limits Caller-selected shared S3 XML and byte limits
   function Get_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Request_Payer : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Accelerate_Outcome;

   --  Shape of a terminal GetBucketAccelerateConfiguration read.
   --  @enum Get_Bucket_Accelerate_Configuration_Response_Available
   --     Modeled response exists
   --  @enum Get_Bucket_Accelerate_Configuration_Exchange_Failed
   --     No complete response exists
   type Get_Bucket_Accelerate_Configuration_Result_Kind is
     (Get_Bucket_Accelerate_Configuration_Response_Available,
      Get_Bucket_Accelerate_Configuration_Exchange_Failed);

   --  Typed GetBucketAccelerateConfiguration response or composable HTTP
   --  failure. Admission is retained for diagnostics; this operation is
   --  read-only. Default initialization is the conservative inert
   --  exchange-failed shape used by operation storage before terminal
   --  assignment.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Accelerate_Configuration_Result
     (Kind : Get_Bucket_Accelerate_Configuration_Result_Kind :=
       Get_Bucket_Accelerate_Configuration_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Accelerate_Configuration_Response_Available =>
            Response : Low_Level.Get_Bucket_Accelerate_Outcome;
         when Get_Bucket_Accelerate_Configuration_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketAccelerateConfiguration parent with one hidden
   --  HTTP child. The operation owns its signed request and retained response
   --  bytes through terminal Finish, with no borrowed request input after
   --  signing.
   type Get_Bucket_Accelerate_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketAccelerateConfiguration read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose acceleration setting is requested
   --  @param Parameters Complete modeled owner and requester-pays controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established acceleration read
   procedure Get_Accelerate_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Accelerate_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Accelerate_Configuration_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketAccelerateConfiguration read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose acceleration setting is requested
   --  @param Parameters Complete modeled owner and requester-pays controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven acceleration read
   function Get_Accelerate_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Accelerate_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Accelerate_Configuration_Operation;

   --  Consume one terminal GetBucketAccelerateConfiguration operation.
   --  @param Operation Terminal acceleration read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Accelerate_Configuration_Operation;
      Result    : out Get_Bucket_Accelerate_Configuration_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket acceleration setting by waiting on the provider-owned
   --  composable operation. Existing region, addressing, timeout, and XML
   --  limit defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose acceleration setting is requested
   --  @param Parameters Complete modeled owner and requester-pays controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Accelerate_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Accelerate_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Accelerate_Configuration_Result;

   --  Read the optional bucket ABAC status.
   function Get_ABAC
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Abac_Outcome;

   --  Shape of a terminal GetBucketAbac read.
   --  @enum Get_Bucket_ABAC_Response_Available Modeled response exists
   --  @enum Get_Bucket_ABAC_Exchange_Failed No complete response exists
   type Get_Bucket_ABAC_Result_Kind is
     (Get_Bucket_ABAC_Response_Available,
      Get_Bucket_ABAC_Exchange_Failed);

   --  Typed GetBucketAbac response or composable HTTP failure. Admission is
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
   type Get_Bucket_ABAC_Result
     (Kind : Get_Bucket_ABAC_Result_Kind := Get_Bucket_ABAC_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_ABAC_Response_Available =>
            Response : Low_Level.Get_Bucket_Abac_Outcome;
         when Get_Bucket_ABAC_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketAbac parent with one hidden HTTP child. The
   --  operation owns its signed request and retained response bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_ABAC_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketAbac read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose ABAC setting is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established ABAC read
   procedure Get_ABAC
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_ABAC_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketAbac read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose ABAC setting is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven ABAC read
   function Get_ABAC
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_ABAC_Operation;

   --  Consume one terminal GetBucketAbac operation.
   --  @param Operation Terminal ABAC read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_ABAC_Operation;
      Result    : out Get_Bucket_ABAC_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket ABAC setting by waiting on the provider-owned
   --  composable operation. Existing region, addressing, timeout, and XML
   --  limit defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose ABAC setting is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_ABAC
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_ABAC_Result;

   --  Shape of a terminal GetBucketPolicy read.
   --  @enum Get_Bucket_Policy_Response_Available Modeled response exists
   --  @enum Get_Bucket_Policy_Exchange_Failed No complete response exists
   type Get_Bucket_Policy_Result_Kind is
     (Get_Bucket_Policy_Response_Available,
      Get_Bucket_Policy_Exchange_Failed);

   --  Typed GetBucketPolicy response or composable HTTP failure. Admission is
   --  retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Policy_Result
     (Kind : Get_Bucket_Policy_Result_Kind :=
        Get_Bucket_Policy_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Policy_Response_Available =>
            Response : Low_Level.Get_Bucket_Policy_Outcome;
         when Get_Bucket_Policy_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketPolicy parent with one hidden HTTP child. The
   --  operation owns its signed request and retained policy bytes through
   --  terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_Policy_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketPolicy read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose policy is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established policy read
   procedure Get_Policy
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Policy_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketPolicy read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose policy is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven policy read
   function Get_Policy
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Policy_Operation;

   --  Consume one terminal GetBucketPolicy operation.
   --  @param Operation Terminal bucket-policy read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Policy_Operation;
      Result    : out Get_Bucket_Policy_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one complete raw bucket policy by waiting on the provider-owned
   --  composable operation. Existing region, addressing, timeout, and XML
   --  limit defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose policy is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Policy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Policy_Result;

   --  Read the complete raw bucket-policy document.
   --  @param Limits Caller-selected response byte limit
   function Get_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Policy_Outcome;

   --  Shape of a terminal GetBucketPolicyStatus read.
   --  @enum Get_Bucket_Policy_Status_Response_Available Modeled response
   --     exists
   --  @enum Get_Bucket_Policy_Status_Exchange_Failed No complete response
   --     exists
   type Get_Bucket_Policy_Status_Result_Kind is
     (Get_Bucket_Policy_Status_Response_Available,
      Get_Bucket_Policy_Status_Exchange_Failed);

   --  Typed GetBucketPolicyStatus response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Policy_Status_Result
     (Kind : Get_Bucket_Policy_Status_Result_Kind :=
        Get_Bucket_Policy_Status_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Policy_Status_Response_Available =>
            Response : Low_Level.Get_Bucket_Policy_Status_Outcome;
         when Get_Bucket_Policy_Status_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketPolicyStatus parent with one hidden HTTP child.
   --  The operation owns its signed request and retained response bytes
   --  through terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_Policy_Status_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketPolicyStatus read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose policy status is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established policy-status read
   procedure Get_Policy_Status
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Policy_Status_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketPolicyStatus read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose policy status is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven policy-status read
   function Get_Policy_Status
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Policy_Status_Operation;

   --  Consume one terminal GetBucketPolicyStatus operation.
   --  @param Operation Terminal bucket-policy-status read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Policy_Status_Operation;
      Result    : out Get_Bucket_Policy_Status_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket policy status by waiting on the provider-owned
   --  composable operation. Existing region, addressing, timeout, and XML
   --  limit defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose policy status is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Policy_Status
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Policy_Status_Result;

   --  Shape of a terminal GetBucketRequestPayment read.
   --  @enum Get_Bucket_Request_Payment_Response_Available Modeled response
   --     exists
   --  @enum Get_Bucket_Request_Payment_Exchange_Failed No complete response
   --     exists
   type Get_Bucket_Request_Payment_Result_Kind is
     (Get_Bucket_Request_Payment_Response_Available,
      Get_Bucket_Request_Payment_Exchange_Failed);

   --  Typed GetBucketRequestPayment response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Request_Payment_Result
     (Kind : Get_Bucket_Request_Payment_Result_Kind :=
        Get_Bucket_Request_Payment_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Request_Payment_Response_Available =>
            Response : Low_Level.Get_Bucket_Request_Payment_Outcome;
         when Get_Bucket_Request_Payment_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketRequestPayment parent with one hidden HTTP child.
   --  The operation owns its signed request and retained response bytes
   --  through terminal Finish, with no borrowed request input after signing.
   type Get_Bucket_Request_Payment_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one bounded GetBucketRequestPayment read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose requester-payment setting is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established requester-payment read
   procedure Get_Request_Payment
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Request_Payment_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded GetBucketRequestPayment read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose requester-payment setting is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected response byte and error XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven requester-payment read
   function Get_Request_Payment
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Request_Payment_Operation;

   --  Consume one terminal GetBucketRequestPayment operation.
   --  @param Operation Terminal requester-payment read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Request_Payment_Operation;
      Result    : out Get_Bucket_Request_Payment_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket requester-payment setting by waiting on the
   --  provider-owned composable operation. Existing region, addressing,
   --  timeout, and XML limit defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose requester-payment setting is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response byte and error XML limits
   --  @return Typed modeled response or bounded exchange failure
   function Get_Request_Payment
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Request_Payment_Result;

   --  What is known about one bucket-policy replacement after terminal
   --  drain. An unknown outcome requires caller-selected Get_Policy
   --  reconciliation before any retry.
   --  @enum Bucket_Policy_Mutation_Completed Complete response proves update
   --  @enum Bucket_Policy_Mutation_Definitely_Not_Applied Non-admission or an
   --     exact rejection proves the requested policy was not applied
   --  @enum Bucket_Policy_Mutation_Outcome_Unknown State must be reconciled
   --  @enum Bucket_Policy_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Bucket_Policy_Mutation_Disposition is
     (Bucket_Policy_Mutation_Completed,
      Bucket_Policy_Mutation_Definitely_Not_Applied,
      Bucket_Policy_Mutation_Outcome_Unknown,
      Bucket_Policy_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketPolicy mutation.
   --  @enum Put_Bucket_Policy_Response_Available Modeled response exists
   --  @enum Put_Bucket_Policy_Exchange_Failed No complete response exists
   type Put_Bucket_Policy_Result_Kind is
     (Put_Bucket_Policy_Response_Available,
      Put_Bucket_Policy_Exchange_Failed);

   --  Typed PutBucketPolicy certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Policy_Result
     (Kind : Put_Bucket_Policy_Result_Kind :=
        Put_Bucket_Policy_Exchange_Failed)
   is record
      Disposition : Bucket_Policy_Mutation_Disposition :=
        Bucket_Policy_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Policy_Response_Available =>
            Response : Low_Level.Put_Bucket_Control_Outcome;
         when Put_Bucket_Policy_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketPolicy parent. The prepared request owns the exact
   --  raw policy bytes, controls, and signing inputs through terminal Finish.
   --  The operation never rewinds or replays its body.
   type Put_Bucket_Policy_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Set_Policy defaults (us-east-1, path-style addressing, the shared XML
   --  limits, and no cancellation source). Changing them would change source
   --  compatibility and request-signing behavior; they are not new policy.
   --  Start or restart one nonreplaying PutBucketPolicy mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete policy is replaced
   --  @param Policy Raw policy bytes copied during bounded preparation
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected policy and error-response byte limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established policy mutation
   procedure Set_Policy
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Policy_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketPolicy mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete policy is replaced
   --  @param Policy Raw policy bytes copied during bounded preparation
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected policy and error-response byte limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven policy mutation
   function Set_Policy
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Policy_Operation;

   --  Consume one terminal PutBucketPolicy operation.
   --  @param Operation Terminal bucket-policy mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Policy_Operation;
      Result    : out Put_Bucket_Policy_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace one complete raw bucket policy by waiting on the provider-owned
   --  nonreplaying operation. The established region, addressing, timeout,
   --  and XML-limit defaults are preserved unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete policy is replaced
   --  @param Policy Raw policy bytes copied during bounded preparation
   --  @param Parameters Complete modeled mutation controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected policy and error-response byte limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Policy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_Policy_Result;

   --  Shape of a terminal DeleteBucketPolicy mutation.
   --  @enum Delete_Bucket_Policy_Response_Available Modeled response exists
   --  @enum Delete_Bucket_Policy_Exchange_Failed No complete response exists
   type Delete_Bucket_Policy_Result_Kind is
     (Delete_Bucket_Policy_Response_Available,
      Delete_Bucket_Policy_Exchange_Failed);

   --  Typed DeleteBucketPolicy certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Delete_Bucket_Policy_Result
     (Kind : Delete_Bucket_Policy_Result_Kind :=
        Delete_Bucket_Policy_Exchange_Failed)
   is record
      Disposition : Bucket_Policy_Mutation_Disposition :=
        Bucket_Policy_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Delete_Bucket_Policy_Response_Available =>
            Response : Low_Level.Delete_Bucket_Configuration_Outcome;
         when Delete_Bucket_Policy_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot DeleteBucketPolicy parent. The signed request and empty
   --  nonreplayable source remain owned through terminal Finish.
   type Delete_Bucket_Policy_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Existing provider contract: these overloads retain the synchronous
   --  Delete_Policy defaults (us-east-1, path-style addressing, the shared
   --  XML limits, and no cancellation source). Changing them would change
   --  source compatibility and request-signing behavior.
   --  Start or restart one nonreplaying DeleteBucketPolicy mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete policy is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response byte limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established policy mutation
   procedure Delete_Policy
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Policy_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying DeleteBucketPolicy mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose complete policy is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Limits Caller-selected error-response byte limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven policy deletion
   function Delete_Policy
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Policy_Operation;

   --  Consume one terminal DeleteBucketPolicy operation.
   --  @param Operation Terminal bucket-policy deletion
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Delete_Bucket_Policy_Operation;
      Result    : out Delete_Bucket_Policy_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Delete one complete bucket policy by waiting on the provider-owned
   --  nonreplaying operation. The existing Delete_Policy region, addressing,
   --  30-second timeout, XML-limit, and null-cancellation defaults remain the
   --  public compatibility contract; this overload introduces no new limit.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete policy is removed
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected error-response byte limits
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Policy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Policy_Result;

   --  Read the optional public-policy assessment for one bucket.
   --  @param Limits Caller-selected shared S3 XML limits
   function Get_Policy_Status
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Policy_Status_Outcome;

   --  Read the optional requester-pays configuration for one bucket.
   --  @param Limits Caller-selected shared S3 XML limits
   function Get_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Request_Payment_Outcome;

   --  Read the presence-preserving four-field public-access block.
   --  @param Limits Caller-selected shared S3 XML limits
   function Get_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Public_Access_Block_Outcome;

   --  Replace the optional bucket ABAC status document.
   function Set_ABAC
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Flyology.Object_Storage.S3.Bucket_Controls.Abac_Status;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome;

   --  Replace the optional transfer-acceleration status document.
   function Set_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Flyology.Object_Storage.S3.Bucket_Controls.Accelerate_Status;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome;

   --  Replace the required requester-payment configuration.
   function Set_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Flyology.Object_Storage.S3.Bucket_Controls.Payer;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome;

   --  Replace the four-field public-access-block document.
   function Set_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value :
        Flyology.Object_Storage.S3.Bucket_Controls.
          Public_Access_Block_Configuration;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome;

   --  Replace the complete bounded raw bucket-policy document.
   function Set_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String; Policy : String;
      Identity : Low_Level.Credentials;
      Confirm_Remove_Self_Access : Low_Level.Optional_Boolean :=
        (others => <>);
      Checksum_Algorithm : String := ""; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome;

   type Head_Outcome_Kind is (Bucket_Available, Head_Rejected);

   type Head_Outcome
     (Kind : Head_Outcome_Kind := Head_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Available =>
            Bucket_ARN           : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_Location_Type : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_Location_Name : Ada.Strings.Unbounded.Unbounded_String;
            Region               : Ada.Strings.Unbounded.Unbounded_String;
            Access_Point_Alias   : Low_Level.Optional_Boolean;
         when Head_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Probe one bucket by waiting on the composable owner-driven HeadBucket
   --  operation. This parameter-record overload preserves typed HTTP failure
   --  and admission information.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose availability is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the HeadBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   --  Region, addressing, and timeout defaults mirror the established
   --  convenience overload; changing them changes source-visible client
   --  request policy and compatibility.
   function Head
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Result;

   --  Probe one bucket without downloading a response body. Successful
   --  results preserve every modeled HeadBucket response header and expose
   --  the bucket region under the convenience-level Region name. If a
   --  compatible server omits the optional response header, Region falls
   --  back to the region used to sign the request.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose availability and region are requested
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the HeadBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Modeled HeadBucket headers or structured bodyless rejection
   function Head
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Outcome;

   type Location_Outcome_Kind is (Location_Found, Location_Rejected);

   type Location_Outcome
     (Kind : Location_Outcome_Kind := Location_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Location_Found =>
            --  Normalized AWS signing region: an empty legacy constraint is
            --  us-east-1 and EU is eu-west-1.
            Region : Ada.Strings.Unbounded.Unbounded_String;
            Legacy_Constraint : Ada.Strings.Unbounded.Unbounded_String;
         when Location_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Resolve one bucket location by waiting on the provider-owned composable
   --  operation. Compatibility contract: region, addressing, and 30-second
   --  timeout defaults are inherited from the established convenience call.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose location is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the location request
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Location
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Location_Result;

   --  Resolve one bucket's legacy GetBucketLocation value into a usable
   --  signing region while preserving the raw constraint for callers that
   --  need wire-level compatibility diagnostics.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose location is requested
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the location request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional 12-digit owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Normalized signing region or structured S3 rejection
   function Get_Location
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Location_Outcome;

   type Put_Tags_Outcome_Kind is (Tags_Replaced, Put_Tags_Rejected);

   type Put_Tags_Outcome
     (Kind : Put_Tags_Outcome_Kind := Put_Tags_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Replaced =>
            null;
         when Put_Tags_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Replace one bucket tag set by waiting on the owner-driven composable
   --  operation. The result preserves HTTP admission and mutation certainty;
   --  no outcome authorizes automatic retry.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete tag set is replaced
   --  @param Value Complete bucket tag set copied during request preparation
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Put_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Value    : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Tagging_Result;

   --  Atomically replace the complete tag set of one bucket. Content-MD5 and
   --  the strict S3 XML body are generated automatically. This unreleased
   --  strict surface intentionally omits RequestPayer, which is absent from
   --  the pinned PutBucketTagging model.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete tag set is replaced
   --  @param Value Nonempty, unique, AWS-valid bucket tag set
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed replacement or structured S3 rejection
   function Put_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Value    : Flyology.Object_Storage.Tags.Tag_Set;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Put_Tags_Outcome;

   type Get_Tags_Outcome_Kind is (Tags_Found, Get_Tags_Rejected);

   type Get_Tags_Outcome
     (Kind : Get_Tags_Outcome_Kind := Get_Tags_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Found =>
            Value : Flyology.Object_Storage.Tags.Tag_Set;
         when Get_Tags_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Fetch one bucket tag snapshot by waiting on the bounded composable
   --  read. The typed result preserves the causal HTTP failure when no
   --  complete modeled response exists.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose tag snapshot is requested
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Tagging_Result;

   --  Fetch one atomic bucket tag snapshot. An untagged bucket is returned as
   --  the structured NoSuchTagSet S3 rejection. This unreleased strict surface
   --  intentionally omits the non-modeled RequestPayer control and charged
   --  response metadata.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose tag snapshot is requested
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed tag snapshot or structured S3 rejection
   function Get_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Tags_Outcome;

   type Delete_Tags_Outcome_Kind is
     (Tags_Deleted, Delete_Tags_Rejected);

   type Delete_Tags_Outcome
     (Kind : Delete_Tags_Outcome_Kind := Delete_Tags_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Deleted =>
            null;
         when Delete_Tags_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Delete one bucket tag set by waiting on the nonreplaying composable
   --  mutation. The result preserves admission and mutation certainty.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose tag set is removed
   --  @param Parameters Complete modeled request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Delete_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Tagging_Result;

   --  Remove the complete tag set of one bucket. Deleting an already absent
   --  tag set remains successful when the bucket exists.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose tag set is removed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Tags_Outcome;

   --  Shape of a terminal GetBucketVersioning read.
   --  @enum Get_Bucket_Versioning_Response_Available Modeled response exists
   --  @enum Get_Bucket_Versioning_Exchange_Failed No complete response exists
   type Get_Bucket_Versioning_Result_Kind is
     (Get_Bucket_Versioning_Response_Available,
      Get_Bucket_Versioning_Exchange_Failed);

   --  Typed GetBucketVersioning response or composable HTTP failure.
   --  Admission is retained for diagnostics; this operation is read-only.
   --  @field Kind Result shape
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty at terminal completion
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Get_Bucket_Versioning_Result
     (Kind : Get_Bucket_Versioning_Result_Kind :=
        Get_Bucket_Versioning_Exchange_Failed)
   is record
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Get_Bucket_Versioning_Response_Available =>
            Response : Low_Level.Get_Bucket_Versioning_Outcome;
         when Get_Bucket_Versioning_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One bounded GetBucketVersioning parent with one hidden HTTP child. The
   --  operation owns its signed request and retained XML through terminal
   --  Finish, with no borrowed request input after signing.
   --  Compatibility contract: region and addressing defaults match the
   --  established synchronous Get_Versioning overload. Composable forms
   --  replace its established 30-second timeout with a supplied deadline.
   type Get_Bucket_Versioning_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one GetBucketVersioning read.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established versioning operation
   procedure Get_Versioning
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Versioning_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one GetBucketVersioning read.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is requested
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven versioning read
   function Get_Versioning
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Versioning_Operation;

   --  Consume one terminal GetBucketVersioning operation.
   --  @param Operation Terminal bucket-versioning read
   --  @param Result Typed modeled response or bounded exchange failure
   procedure Finish
     (Operation : in out Get_Bucket_Versioning_Operation;
      Result    : out Get_Bucket_Versioning_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Read one bucket versioning configuration by waiting on the
   --  provider-owned composable operation. Compatibility contract: region,
   --  addressing, and 30-second timeout defaults are inherited unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is read
   --  @param Parameters Complete modeled owner precondition
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled response or bounded exchange failure
   function Get_Versioning
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Versioning_Result;

   --  What is known about one bucket-versioning mutation after terminal
   --  drain. An unknown outcome requires caller-selected Get_Versioning
   --  reconciliation before any retry.
   --  @enum Bucket_Versioning_Mutation_Completed Complete response proves it
   --  @enum Bucket_Versioning_Mutation_Definitely_Not_Applied Exact evidence
   --     proves the requested configuration was not applied
   --  @enum Bucket_Versioning_Mutation_Outcome_Unknown State needs a read
   --  @enum Bucket_Versioning_Mutation_Cancelled_Before_Admission Cancellation
   --     preceded possible server admission
   type Bucket_Versioning_Mutation_Disposition is
     (Bucket_Versioning_Mutation_Completed,
      Bucket_Versioning_Mutation_Definitely_Not_Applied,
      Bucket_Versioning_Mutation_Outcome_Unknown,
      Bucket_Versioning_Mutation_Cancelled_Before_Admission);

   --  Shape of a terminal PutBucketVersioning mutation.
   --  @enum Put_Bucket_Versioning_Response_Available Modeled response exists
   --  @enum Put_Bucket_Versioning_Exchange_Failed No complete response exists
   type Put_Bucket_Versioning_Result_Kind is
     (Put_Bucket_Versioning_Response_Available,
      Put_Bucket_Versioning_Exchange_Failed);

   --  Typed PutBucketVersioning certainty and response or HTTP failure.
   --  @field Kind Result shape
   --  @field Disposition Mutation certainty
   --  @field Failure Bounded expected failure reason
   --  @field Admission HTTP admission certainty
   --  @field Response Complete modeled S3 response
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Put_Bucket_Versioning_Result
     (Kind : Put_Bucket_Versioning_Result_Kind :=
        Put_Bucket_Versioning_Exchange_Failed)
   is record
      Disposition : Bucket_Versioning_Mutation_Disposition :=
        Bucket_Versioning_Mutation_Outcome_Unknown;
      Failure   : Failure_Reason := Corrupt_Or_Invalid_Response;
      Admission : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      case Kind is
         when Put_Bucket_Versioning_Response_Available =>
            Response : Low_Level.Put_Bucket_Versioning_Outcome;
         when Put_Bucket_Versioning_Exchange_Failed =>
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
              Flyology.HTTP.Client.Response_Invalid;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase :=
              Flyology.HTTP.Client.Not_Started;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  One-shot PutBucketVersioning parent. The prepared request owns its
   --  serialized configuration, headers, and signing inputs through terminal
   --  Finish. The operation never rewinds or replays its body.
   type Put_Bucket_Versioning_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Start or restart one nonreplaying PutBucketVersioning mutation.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is replaced
   --  @param Parameters Complete modeled configuration and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established versioning mutation
   procedure Set_Versioning_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Versioning_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one nonreplaying PutBucketVersioning mutation.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Bucket whose configuration is replaced
   --  @param Parameters Complete modeled configuration and request controls
   --  @param Identity Credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven versioning mutation
   function Set_Versioning_Configuration
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Versioning_Operation;

   --  Consume one terminal PutBucketVersioning operation.
   --  @param Operation Terminal bucket-versioning mutation
   --  @param Result Typed response or bounded ambiguous exchange failure
   procedure Finish
     (Operation : in out Put_Bucket_Versioning_Operation;
      Result    : out Put_Bucket_Versioning_Result)
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Replace one complete bucket-versioning configuration by waiting on the
   --  provider-owned composable mutation. Compatibility contract: region,
   --  addressing, and 30-second timeout defaults are inherited unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is replaced
   --  @param Parameters Complete modeled configuration and request controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @return Typed response or bounded ambiguous exchange failure
   function Set_Versioning_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Versioning_Result;

   subtype Configurable_Versioning_Status is Bucket_Versioning_Status range
     Versioning_Enabled .. Versioning_Suspended;

   type Set_Versioning_Outcome_Kind is
     (Versioning_Updated, Set_Versioning_Rejected);

   type Set_Versioning_Outcome
     (Kind : Set_Versioning_Outcome_Kind := Set_Versioning_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Versioning_Updated =>
            null;
         when Set_Versioning_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Enable or suspend bucket versioning configuration. This convenience
   --  call does not expose MFA-delete because safe use requires a separately
   --  verified MFA policy. It does not imply that object version creation or
   --  ListObjectVersions is implemented by a compatible endpoint.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is changed
   --  @param Versioning Enabled or Suspended
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed configuration update or structured S3 rejection
   function Set_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Versioning : Configurable_Versioning_Status;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Set_Versioning_Outcome;

   --  Apply the complete modeled bucket-versioning configuration. Changing
   --  MFA Delete requires an explicit versioning status, an MFA credential,
   --  and a secure HTTPS origin. The credential is retained only while the
   --  synchronous request is signed and executed. This configures the bucket;
   --  it does not claim object-version publication or listing support.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact secure origin used to configure and sign requests
   --  @param Bucket Bucket whose configuration is changed
   --  @param Configuration Presence-preserving Status and MfaDelete members
   --  @param Identity Credentials used only while signing this request
   --  @param MFA Optional physical-device header; required for MFA Delete
   --  @param Checksum_Algorithm Optional modeled request checksum algorithm
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed configuration update or structured S3 rejection
   function Set_Versioning_Configuration
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Configuration : Bucket_Versioning_Configuration;
      Identity : Low_Level.Credentials;
      MFA      : String := "";
      Checksum_Algorithm : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Set_Versioning_Outcome;

   type Get_Versioning_Outcome_Kind is
     (Versioning_Found, Get_Versioning_Rejected);

   type Get_Versioning_Outcome
     (Kind : Get_Versioning_Outcome_Kind := Get_Versioning_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Versioning_Found =>
            Configuration : Bucket_Versioning_Configuration;
         when Get_Versioning_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Read the presence-preserving bucket versioning configuration.
   --  Unconfigured is distinct from Suspended.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is read
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Configuration snapshot or structured S3 rejection
   function Get_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Versioning_Outcome;

   --  Shape of a terminal CreateSession exchange.
   --  @enum Create_Session_Response_Available Complete modeled response
   --  @enum Create_Session_Exchange_Failed No modeled response exists
   type Create_Session_Result_Kind is
     (Create_Session_Response_Available, Create_Session_Exchange_Failed);

   --  Typed CreateSession response or bounded HTTP failure. The successful
   --  credentials branch is limited and zeroizing; it is constructed only by
   --  Finish and is never copied into operation storage.
   --  @field Kind Result shape
   --  @field Admission HTTP admission certainty
   --  @field Response Zeroizing modeled session response
   --  @field Failure Bounded expected failure reason
   --  @field HTTP_Result Typed HTTP terminal outcome
   --  @field HTTP_Phase Causal HTTP phase
   --  @field Detail Bounded sanitized HTTP diagnostic
   type Create_Session_Result
     (Kind : Create_Session_Result_Kind) is limited record
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      case Kind is
         when Create_Session_Response_Available =>
            Response : Low_Level.Create_Session_Outcome;
         when Create_Session_Exchange_Failed =>
            Failure     : Failure_Reason;
            HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind;
            HTTP_Phase  : Flyology.HTTP.Client.Exchange_Phase;
            Detail      : Ada.Strings.Unbounded.Unbounded_String;
      end case;
   end record;

   --  Owner-driven bounded CreateSession exchange. The signed request and raw
   --  bounded response remain owned until typed Finish constructs the limited
   --  zeroizing credentials result.
   type Create_Session_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation
     and Flyology.HTTP.Client.Response_Body_Sink with private;

   --  Compatibility contract: the existing virtual-hosted style, signing
   --  region, XML limits, cancellation, and synchronous timeout defaults are
   --  preserved by every overload below.

   --  Start or restart one bounded CreateSession exchange.
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Secure zonal endpoint used to configure and sign Client
   --  @param Bucket Directory bucket encoded in Origin's virtual host
   --  @param Parameters Complete modeled session policy
   --  @param Identity Long-term credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 signing region
   --  @param Style Must remain virtual-hosted for CreateSession
   --  @param Limits Caller-selected response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @param Operation Fresh or consumed established exchange
   procedure Create_Session
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Create_Session_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style :=
        Low_Level.Virtual_Hosted_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Create_Session_Operation)
   with
     Pre =>
       not Flyology.Operations.Is_Active (Operation)
       and then not Flyology.Operations.Is_Terminal (Operation);

   --  Construct one bounded CreateSession exchange.
   --  @param Set Caller-owned completion set
   --  @param Client Configured origin client retained through terminal drain
   --  @param Origin Secure zonal endpoint used to configure and sign Client
   --  @param Bucket Directory bucket encoded in Origin's virtual host
   --  @param Parameters Complete modeled session policy
   --  @param Identity Long-term credentials borrowed only during signing
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Region SigV4 signing region
   --  @param Style Must remain virtual-hosted for CreateSession
   --  @param Limits Caller-selected response XML limits
   --  @param Token Optional cancellation source retained through drain
   --  @return Started owner-driven session exchange
   function Create_Session
     (Set        : not null access Flyology.Operations.Completion_Set'Class;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Create_Session_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style :=
        Low_Level.Virtual_Hosted_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Create_Session_Operation;

   --  Consume one terminal CreateSession operation and construct its limited
   --  credentials result exactly once.
   --  @param Operation Terminal session exchange
   --  @return Zeroizing response or bounded exchange failure
   function Finish
     (Operation : in out Create_Session_Operation)
      return Create_Session_Result
   with Pre => Flyology.Operations.Is_Terminal (Operation);

   --  Create a session by waiting on the same provider-owned state machine
   --  used by composable callers.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Secure zonal endpoint used to configure and sign Client
   --  @param Bucket Directory bucket encoded in Origin's virtual host
   --  @param Parameters Complete modeled session policy
   --  @param Identity Long-term credentials used only while signing
   --  @param Region SigV4 signing region
   --  @param Style Must remain virtual-hosted for CreateSession
   --  @param Timeout Whole owner-driven operation budget
   --  @param Token Optional cancellation source
   --  @param Limits Caller-selected response XML limits
   --  @return Zeroizing response or bounded exchange failure
   function Create_Session
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Create_Session_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style :=
        Low_Level.Virtual_Hosted_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Create_Session_Result;

   --  Create one five-minute directory-bucket authorization session through
   --  the secure virtual-hosted CreateSession endpoint. Returned access,
   --  secret, and token values remain inside the zeroizing low-level
   --  Credentials object; the outcome cannot be copied. This layer creates no
   --  refresh task and retains no session state after the call. Transport
   --  retry behavior remains the configured Flyology HTTP client's policy.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Secure zonal endpoint used to configure and sign Client
   --  @param Bucket Directory bucket encoded in Origin's virtual host
   --  @param Identity Long-term credentials used only for this request
   --  @param Session_Mode Optional ReadOnly or ReadWrite mode
   --  @param Server_Side_Encryption Optional modeled encryption selection
   --  @param SSE_KMS_Key_ID Required customer key for an explicit KMS mode
   --  @param SSE_KMS_Encryption_Context Optional canonical base64 context
   --  @param Bucket_Key_Enabled Absent or explicit true for a KMS session
   --  @param Region SigV4 signing region
   --  @param Style Must remain virtual-hosted for CreateSession
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Zeroizing temporary identity, expiration, policy, or S3 error
   function Create_Session
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Session_Mode : String := "";
      Server_Side_Encryption : String := "";
      SSE_KMS_Key_ID : String := "";
      SSE_KMS_Encryption_Context : String := "";
      Bucket_Key_Enabled : Low_Level.Optional_Boolean := (others => <>);
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Virtual_Hosted_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Low_Level.Create_Session_Outcome;

private

   --  @exclude
   type Create_Session_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline       : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared       : aliased Low_Level.Prepared_Request;
      Child          : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits         : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data  : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit : Natural := 0;
      Metadata       : Low_Level.Create_Session_Response_Metadata;
      --  Private preterminal state sentinels are reset on every Start and
      --  guarded by Has_Final_Result; they never select external retry policy.
      Admission      : Flyology.HTTP.Client.Admission_Certainty :=
        Flyology.HTTP.Client.Not_Admitted;
      Final_HTTP_Result : Flyology.HTTP.Client.Exchange_Result_Kind :=
        Flyology.HTTP.Client.Client_Unavailable;
      Final_HTTP_Phase : Flyology.HTTP.Client.Exchange_Phase :=
        Flyology.HTTP.Client.Not_Started;
      Final_Detail    : Ada.Strings.Unbounded.Unbounded_String;
      Has_Response    : Boolean := False;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error     : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Create_Session_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item  : in out Create_Session_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Create_Session_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Create_Session_Operation);

   --  @exclude
   procedure Start_Create_Session
     (Operation  : in out Create_Session_Operation;
      Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Create_Session_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Token      : access Flyology.Cancellation.Token);

   --  @exclude
   function Finish_Create_Session_Response
     (Operation : in out Create_Session_Operation)
      return Low_Level.Create_Session_Outcome;

   --  @exclude
   type Get_Bucket_CORS_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_CORS_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   function Decode_Get_Bucket_Replication_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Replication_Result;

   --  @exclude
   function Normalize_Get_Bucket_Replication_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Replication_Result;

   --  @exclude
   package Get_Bucket_Replication_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Replication_Result,
        Operation_Name    => "GetBucketReplication",
        Start_Exchange    => Low_Level.Get_Bucket_Replication,
        Decode_Response   => Decode_Get_Bucket_Replication_Response,
        Normalize_Failure => Normalize_Get_Bucket_Replication_Failure);

   --  @exclude
   type Get_Bucket_Replication_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Replication_Reads.State (Set);
   end record;

   --  @exclude
   function Decode_Get_Bucket_Metrics_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Metrics_Result;

   --  @exclude
   function Normalize_Get_Bucket_Metrics_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Metrics_Result;

   --  @exclude
   package Get_Bucket_Metrics_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Metrics_Result,
        Operation_Name    => "GetBucketMetricsConfiguration",
        Start_Exchange    => Low_Level.Get_Bucket_Metrics_Configuration,
        Decode_Response   => Decode_Get_Bucket_Metrics_Response,
        Normalize_Failure => Normalize_Get_Bucket_Metrics_Failure);

   --  @exclude
   type Get_Bucket_Metrics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Metrics_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Metrics_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Metrics_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Metrics_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Metrics_Operation);

   --  @exclude
   function Decode_List_Bucket_Metrics_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return List_Bucket_Metrics_Result;

   --  @exclude
   function Normalize_List_Bucket_Metrics_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return List_Bucket_Metrics_Result;

   --  @exclude
   package List_Bucket_Metrics_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => List_Bucket_Metrics_Result,
        Operation_Name    => "ListBucketMetricsConfigurations",
        Start_Exchange    => Low_Level.List_Bucket_Metrics_Configurations,
        Decode_Response   => Decode_List_Bucket_Metrics_Response,
        Normalize_Failure => Normalize_List_Bucket_Metrics_Failure);

   --  @exclude
   type List_Bucket_Metrics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : List_Bucket_Metrics_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out List_Bucket_Metrics_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out List_Bucket_Metrics_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out List_Bucket_Metrics_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out List_Bucket_Metrics_Operation);

   --  @exclude
   function Decode_List_Bucket_Analytics_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return List_Bucket_Analytics_Result;

   --  @exclude
   function Normalize_List_Bucket_Analytics_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return List_Bucket_Analytics_Result;

   --  @exclude
   package List_Bucket_Analytics_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => List_Bucket_Analytics_Result,
        Operation_Name    => "ListBucketAnalyticsConfigurations",
        Start_Exchange    => Low_Level.List_Bucket_Analytics_Configurations,
        Decode_Response   => Decode_List_Bucket_Analytics_Response,
        Normalize_Failure => Normalize_List_Bucket_Analytics_Failure);

   --  @exclude
   type List_Bucket_Analytics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : List_Bucket_Analytics_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out List_Bucket_Analytics_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out List_Bucket_Analytics_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out List_Bucket_Analytics_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out List_Bucket_Analytics_Operation);

   --  @exclude
   function Decode_Get_Bucket_Analytics_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Analytics_Result;

   --  @exclude
   function Normalize_Get_Bucket_Analytics_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Analytics_Result;

   --  @exclude
   package Get_Bucket_Analytics_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Analytics_Result,
        Operation_Name    => "GetBucketAnalyticsConfiguration",
        Start_Exchange    => Low_Level.Get_Bucket_Analytics_Configuration,
        Decode_Response   => Decode_Get_Bucket_Analytics_Response,
        Normalize_Failure => Normalize_Get_Bucket_Analytics_Failure);

   --  @exclude
   type Get_Bucket_Analytics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Analytics_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Analytics_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Analytics_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Analytics_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Analytics_Operation);
   --  @exclude
   function Decode_Get_Bucket_Intelligent_Tiering_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Intelligent_Tiering_Result;

   --  @exclude
   function Normalize_Get_Bucket_Intelligent_Tiering_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Intelligent_Tiering_Result;

   --  @exclude
   package Get_Bucket_Intelligent_Tiering_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Intelligent_Tiering_Result,
        Operation_Name    => "GetBucketIntelligentTieringConfiguration",
        Start_Exchange    =>
          Low_Level.Get_Bucket_Intelligent_Tiering_Configuration,
        Decode_Response   => Decode_Get_Bucket_Intelligent_Tiering_Response,
        Normalize_Failure => Normalize_Get_Bucket_Intelligent_Tiering_Failure);

   --  @exclude
   type Get_Bucket_Intelligent_Tiering_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Intelligent_Tiering_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Intelligent_Tiering_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Intelligent_Tiering_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Intelligent_Tiering_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Intelligent_Tiering_Operation);

   --  @exclude
   function Decode_List_Bucket_Intelligent_Tiering_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return List_Bucket_Intelligent_Tiering_Result;

   --  @exclude
   function Normalize_List_Bucket_Intelligent_Tiering_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return List_Bucket_Intelligent_Tiering_Result;

   --  @exclude
   package List_Bucket_Intelligent_Tiering_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => List_Bucket_Intelligent_Tiering_Result,
        Operation_Name    =>
          "ListBucketIntelligentTieringConfigurations",
        Start_Exchange    =>
          Low_Level.List_Bucket_Intelligent_Tiering_Configurations,
        Decode_Response   =>
          Decode_List_Bucket_Intelligent_Tiering_Response,
        Normalize_Failure =>
          Normalize_List_Bucket_Intelligent_Tiering_Failure);

   --  @exclude
   type List_Bucket_Intelligent_Tiering_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : List_Bucket_Intelligent_Tiering_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out List_Bucket_Intelligent_Tiering_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out List_Bucket_Intelligent_Tiering_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out List_Bucket_Intelligent_Tiering_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out List_Bucket_Intelligent_Tiering_Operation);

   --  @exclude
   function Decode_List_Bucket_Inventory_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return List_Bucket_Inventory_Result;

   --  @exclude
   function Normalize_List_Bucket_Inventory_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return List_Bucket_Inventory_Result;

   --  @exclude
   package List_Bucket_Inventory_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => List_Bucket_Inventory_Result,
        Operation_Name    => "ListBucketInventoryConfigurations",
        Start_Exchange    =>
          Low_Level.List_Bucket_Inventory_Configurations,
        Decode_Response   => Decode_List_Bucket_Inventory_Response,
        Normalize_Failure => Normalize_List_Bucket_Inventory_Failure);

   --  @exclude
   type List_Bucket_Inventory_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : List_Bucket_Inventory_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out List_Bucket_Inventory_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out List_Bucket_Inventory_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out List_Bucket_Inventory_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out List_Bucket_Inventory_Operation);

   --  @exclude
   function Decode_Get_Bucket_Inventory_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Inventory_Result;

   --  @exclude
   function Normalize_Get_Bucket_Inventory_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Inventory_Result;

   --  @exclude
   package Get_Bucket_Inventory_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Inventory_Result,
        Operation_Name    => "GetBucketInventoryConfiguration",
        Start_Exchange    =>
          Low_Level.Get_Bucket_Inventory_Configuration,
        Decode_Response   => Decode_Get_Bucket_Inventory_Response,
        Normalize_Failure => Normalize_Get_Bucket_Inventory_Failure);

   --  @exclude
   type Get_Bucket_Inventory_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Inventory_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Inventory_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Inventory_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Inventory_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Inventory_Operation);

   --  @exclude
   function Decode_Get_Bucket_Logging_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Logging_Result;

   --  @exclude
   function Normalize_Get_Bucket_Logging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Logging_Result;

   --  @exclude
   package Get_Bucket_Logging_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Logging_Result,
        Operation_Name    => "GetBucketLogging",
        Start_Exchange    => Low_Level.Get_Bucket_Logging,
        Decode_Response   => Decode_Get_Bucket_Logging_Response,
        Normalize_Failure => Normalize_Get_Bucket_Logging_Failure);

   --  @exclude
   type Get_Bucket_Logging_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Logging_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Logging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Logging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Logging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Logging_Operation);

   --  @exclude
   function Decode_Get_Bucket_Website_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Website_Result;

   --  @exclude
   function Normalize_Get_Bucket_Website_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Website_Result;

   --  @exclude
   package Get_Bucket_Website_Reads is new
     Flyology.Object_Storage.Client.Bounded_REST_XML_Reads
       (Result_Type       => Get_Bucket_Website_Result,
        Operation_Name    => "GetBucketWebsite",
        Start_Exchange    => Low_Level.Get_Bucket_Website,
        Decode_Response   => Decode_Get_Bucket_Website_Response,
        Normalize_Failure => Normalize_Get_Bucket_Website_Failure);

   --  @exclude
   type Get_Bucket_Website_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      State : Get_Bucket_Website_Reads.State (Set);
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Website_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Website_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Website_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Website_Operation);

   --  @exclude
   type Put_Bucket_Replication_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural;
      Final_Result     : Put_Bucket_Replication_Result;
      Has_Final_Result : Boolean;
      Has_Saved_Error  : Boolean;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Notification_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural;
      Final_Result     : Get_Bucket_Notification_Result;
      Has_Final_Result : Boolean;
      Has_Saved_Error  : Boolean;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Notification_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural;
      Final_Result     : Put_Bucket_Notification_Result;
      Has_Final_Result : Boolean;
      Has_Saved_Error  : Boolean;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_ACL_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_ACL_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Metadata_Table_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Metadata_Table_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Create_Bucket_Metadata_Table_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     :
        Create_Bucket_Metadata_Table_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Lifecycle_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Lifecycle_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Lifecycle_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Lifecycle_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Replication_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Replication_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Website_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Website_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Metrics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     :
        Delete_Bucket_Metrics_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Metadata_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     :
        Delete_Bucket_Metadata_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Metadata_Table_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     :
        Delete_Bucket_Metadata_Table_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Analytics_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     :
        Delete_Bucket_Analytics_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Tiering_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     :
        Delete_Bucket_Tiering_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Inventory_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Inventory_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_CORS_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_CORS_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Object_Lock_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Object_Lock_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Object_Lock_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Object_Lock_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Encryption_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Encryption_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Lifecycle_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Lifecycle_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Encryption_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Encryption_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Encryption_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Encryption_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Ownership_Controls_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Ownership_Controls_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Ownership_Controls_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Ownership_Controls_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_CORS_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_CORS_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Ownership_Controls_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Ownership_Controls_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Public_Access_Block_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Public_Access_Block_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_ABAC_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_ABAC_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Accelerate_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Accelerate_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Request_Payment_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Request_Payment_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Public_Access_Block_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Public_Access_Block_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Public_Access_Block_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Public_Access_Block_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Accelerate_Configuration_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Accelerate_Configuration_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_ABAC_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_ABAC_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Policy_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Policy_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Policy_Status_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Policy_Status_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Request_Payment_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Request_Payment_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Policy_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Policy_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Policy_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Policy_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   type Put_Bucket_Tagging_Operation
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
      Final_Result : Put_Bucket_Tagging_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Location_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Location_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Put_Bucket_Versioning_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Source_Position  : Natural := 0;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Put_Bucket_Versioning_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Get_Bucket_Versioning_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Get_Bucket_Versioning_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Put_Bucket_Tagging_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Tagging_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Tagging_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Bucket_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Bucket_Tagging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Tagging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Bucket_Tagging_Operation);

   --  @exclude
   type Get_Bucket_Tagging_Operation
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
      Final_Result : Get_Bucket_Tagging_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Tagging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Tagging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Tagging_Operation);

   --  @exclude
   type Delete_Bucket_Tagging_Operation
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
      Final_Result : Delete_Bucket_Tagging_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Tagging_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Tagging_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Tagging_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Bucket_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Bucket_Tagging_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Tagging_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Tagging_Operation);

   --  @exclude
   type List_Buckets_Operation
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
      Final_Result : List_Buckets_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Create_Bucket_Operation
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
      Final_Result : Create_Bucket_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Delete_Bucket_Operation
     (Set          : not null access Flyology.Operations.Completion_Set'Class;
      HTTP         : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set)
     and Flyology.HTTP.Client.Operation_Request_Body_Source
     and Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural := 0;
      Final_Result     : Delete_Bucket_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error  : Boolean := False;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   type Head_Bucket_Operation
     (Set : not null access Flyology.Operations.Completion_Set'Class;
      HTTP : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token) is
     new Flyology.Operations.Operation (Set) and
       Flyology.HTTP.Client.Response_Body_Sink
   with record
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared   : aliased Low_Level.Prepared_Request;
      Child      : Flyology.HTTP.Client.Exchange_Operation (Set);
      Final_Result : Head_Bucket_Result;
      Has_Final_Result : Boolean := False;
      Has_Saved_Error : Boolean := False;
      Saved_Error : Ada.Exceptions.Exception_Occurrence;
   end record;

   --  @exclude
   overriding procedure Write
     (Item : in out List_Buckets_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out List_Buckets_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out List_Buckets_Operation);
   overriding procedure Finalize
     (Item : in out List_Buckets_Operation);
   overriding function Declared_Length
     (Item : Create_Bucket_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Create_Bucket_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Create_Bucket_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Create_Bucket_Operation);
   overriding procedure Write
     (Item : in out Create_Bucket_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Create_Bucket_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Create_Bucket_Operation);
   overriding procedure Finalize
     (Item : in out Create_Bucket_Operation);
   overriding
   function Declared_Length
     (Item : Delete_Bucket_Operation) return Flyology.HTTP.Client.Body_Length;
   overriding
   procedure Read_Now
     (Item   : in out Delete_Bucket_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding
   procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding
   procedure Release_Source (Item : in out Delete_Bucket_Operation);
   overriding procedure Write
     (Item : in out Delete_Bucket_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Bucket_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Operation);
   overriding procedure Write
     (Item : in out Head_Bucket_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Head_Bucket_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Head_Bucket_Operation);
   overriding procedure Finalize
     (Item : in out Head_Bucket_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_CORS_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_CORS_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_CORS_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_CORS_Operation);
   overriding function Declared_Length
     (Item : Delete_Bucket_CORS_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_CORS_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_CORS_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_CORS_Operation);
   overriding procedure Write
     (Item : in out Delete_Bucket_CORS_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Bucket_CORS_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_CORS_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Bucket_CORS_Operation);
   overriding procedure Write
     (Item : in out Get_Object_Lock_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Object_Lock_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Object_Lock_Configuration_Operation);
   overriding procedure Finalize
     (Item : in out Get_Object_Lock_Configuration_Operation);
   overriding function Declared_Length
     (Item : Put_Object_Lock_Configuration_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Object_Lock_Configuration_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Object_Lock_Configuration_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Object_Lock_Configuration_Operation);
   overriding procedure Write
     (Item : in out Put_Object_Lock_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Object_Lock_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Object_Lock_Configuration_Operation);
   overriding procedure Finalize
     (Item : in out Put_Object_Lock_Configuration_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Encryption_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Encryption_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Encryption_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Encryption_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Lifecycle_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Lifecycle_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Replication_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Replication_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Replication_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Replication_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Put_Bucket_Replication_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Replication_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Replication_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Replication_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Bucket_Replication_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Bucket_Replication_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Replication_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Bucket_Replication_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Notification_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Notification_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Notification_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Notification_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_ACL_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_ACL_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_ACL_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_ACL_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Get_Bucket_Metadata_Table_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Get_Bucket_Metadata_Table_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Metadata_Table_Configuration_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Get_Bucket_Metadata_Table_Configuration_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Create_Bucket_Metadata_Table_Configuration_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Create_Bucket_Metadata_Table_Configuration_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out
        Create_Bucket_Metadata_Table_Configuration_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Create_Bucket_Metadata_Table_Configuration_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Create_Bucket_Metadata_Table_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item  : in out Create_Bucket_Metadata_Table_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Create_Bucket_Metadata_Table_Configuration_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Create_Bucket_Metadata_Table_Configuration_Operation);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   --  @return Exact serialized request-body length
   overriding function Declared_Length
     (Item : Put_Bucket_Encryption_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   --  @param Data Caller-provided source window
   --  @param Last Last produced source element
   --  @param Result Immediate source progress
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Encryption_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   --  @param Required Requested source readiness
   --  @param Descriptor No descriptor for the memory source
   --  @param Ready_Now Always true for the memory source
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Encryption_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Encryption_Operation);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   --  @param Data Response-body bytes to append within the caller limit
   overriding procedure Write
     (Item : in out Put_Bucket_Encryption_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   --  @param Event Owner-driven scheduling event
   overriding procedure Drive
     (Item : in out Put_Bucket_Encryption_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Encryption_Operation);
   --  @exclude
   --  @param Item Internal nonreplaying encryption mutation
   overriding procedure Finalize
     (Item : in out Put_Bucket_Encryption_Operation);
   overriding function Declared_Length
     (Item : Delete_Bucket_Encryption_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Encryption_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Encryption_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Encryption_Operation);
   overriding procedure Write
     (Item : in out Delete_Bucket_Encryption_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Bucket_Encryption_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Encryption_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Encryption_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Put_Bucket_Lifecycle_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Lifecycle_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Lifecycle_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Bucket_Lifecycle_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Bucket_Lifecycle_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Put_Bucket_Notification_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Notification_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Notification_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Notification_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Put_Bucket_Notification_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Put_Bucket_Notification_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Notification_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Put_Bucket_Notification_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Lifecycle_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Lifecycle_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Lifecycle_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Bucket_Lifecycle_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Bucket_Lifecycle_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Lifecycle_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Replication_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Replication_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Replication_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Replication_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Bucket_Replication_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Bucket_Replication_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Replication_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Replication_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Website_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Website_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Website_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Website_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Bucket_Website_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Bucket_Website_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Website_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Website_Operation);
   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Metadata_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   :
        in out Delete_Bucket_Metadata_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       :
        in out Delete_Bucket_Metadata_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item :
        in out Delete_Bucket_Metadata_Operation);
   --  @exclude
   overriding procedure Write
     (Item :
        in out Delete_Bucket_Metadata_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item :
        in out Delete_Bucket_Metadata_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item :
        in out Delete_Bucket_Metadata_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item :
        in out Delete_Bucket_Metadata_Operation);

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Metadata_Table_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   :
        in out Delete_Bucket_Metadata_Table_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       :
        in out Delete_Bucket_Metadata_Table_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item :
        in out Delete_Bucket_Metadata_Table_Operation);
   --  @exclude
   overriding procedure Write
     (Item :
        in out Delete_Bucket_Metadata_Table_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item :
        in out Delete_Bucket_Metadata_Table_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item :
        in out Delete_Bucket_Metadata_Table_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item :
        in out Delete_Bucket_Metadata_Table_Operation);

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Metrics_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   :
        in out Delete_Bucket_Metrics_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       :
        in out Delete_Bucket_Metrics_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item :
        in out Delete_Bucket_Metrics_Operation);
   --  @exclude
   overriding procedure Write
     (Item :
        in out Delete_Bucket_Metrics_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item :
        in out Delete_Bucket_Metrics_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item :
        in out Delete_Bucket_Metrics_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item :
        in out Delete_Bucket_Metrics_Operation);

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Analytics_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   :
        in out Delete_Bucket_Analytics_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       :
        in out Delete_Bucket_Analytics_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item :
        in out Delete_Bucket_Analytics_Operation);
   --  @exclude
   overriding procedure Write
     (Item :
        in out Delete_Bucket_Analytics_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item :
        in out Delete_Bucket_Analytics_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item :
        in out Delete_Bucket_Analytics_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item :
        in out Delete_Bucket_Analytics_Operation);

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Tiering_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   :
        in out Delete_Bucket_Tiering_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       :
        in out Delete_Bucket_Tiering_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item :
        in out Delete_Bucket_Tiering_Operation);
   --  @exclude
   overriding procedure Write
     (Item :
        in out Delete_Bucket_Tiering_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item :
        in out Delete_Bucket_Tiering_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item :
        in out Delete_Bucket_Tiering_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item :
        in out Delete_Bucket_Tiering_Operation);

   --  @exclude
   overriding function Declared_Length
     (Item : Delete_Bucket_Inventory_Configuration_Operation)
      return Flyology.HTTP.Client.Body_Length;
   --  @exclude
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Inventory_Configuration_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   --  @exclude
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Inventory_Configuration_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   --  @exclude
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Inventory_Configuration_Operation);
   --  @exclude
   overriding procedure Write
     (Item : in out Delete_Bucket_Inventory_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   --  @exclude
   overriding procedure Drive
     (Item : in out Delete_Bucket_Inventory_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   --  @exclude
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Inventory_Configuration_Operation);
   --  @exclude
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Inventory_Configuration_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Ownership_Controls_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Ownership_Controls_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Ownership_Controls_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Ownership_Controls_Operation);
   overriding function Declared_Length
     (Item : Put_Bucket_CORS_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_CORS_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_CORS_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_CORS_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_CORS_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_CORS_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_CORS_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_CORS_Operation);
   overriding function Declared_Length
     (Item : Put_Bucket_Ownership_Controls_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Ownership_Controls_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Ownership_Controls_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Ownership_Controls_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_Ownership_Controls_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_Ownership_Controls_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Ownership_Controls_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_Ownership_Controls_Operation);
   overriding function Declared_Length
     (Item : Delete_Ownership_Controls_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Ownership_Controls_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Ownership_Controls_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Delete_Ownership_Controls_Operation);
   overriding procedure Write
     (Item : in out Delete_Ownership_Controls_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Ownership_Controls_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Ownership_Controls_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Ownership_Controls_Operation);
   overriding procedure Write
     (Item : in out Get_Public_Access_Block_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Public_Access_Block_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Public_Access_Block_Operation);
   overriding procedure Finalize
     (Item : in out Get_Public_Access_Block_Operation);
   overriding function Declared_Length
     (Item : Put_Bucket_ABAC_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_ABAC_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_ABAC_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_ABAC_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_ABAC_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_ABAC_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_ABAC_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_ABAC_Operation);

   overriding function Declared_Length
     (Item : Put_Bucket_Accelerate_Configuration_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Accelerate_Configuration_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Accelerate_Configuration_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Accelerate_Configuration_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_Accelerate_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_Accelerate_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Accelerate_Configuration_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_Accelerate_Configuration_Operation);

   overriding function Declared_Length
     (Item : Put_Bucket_Request_Payment_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Request_Payment_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Request_Payment_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Request_Payment_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_Request_Payment_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_Request_Payment_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Request_Payment_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_Request_Payment_Operation);
   overriding function Declared_Length
     (Item : Put_Public_Access_Block_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Public_Access_Block_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Public_Access_Block_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Public_Access_Block_Operation);
   overriding procedure Write
     (Item : in out Put_Public_Access_Block_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Public_Access_Block_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Public_Access_Block_Operation);
   overriding procedure Finalize
     (Item : in out Put_Public_Access_Block_Operation);
   overriding function Declared_Length
     (Item : Delete_Public_Access_Block_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Public_Access_Block_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Public_Access_Block_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Delete_Public_Access_Block_Operation);
   overriding procedure Write
     (Item : in out Delete_Public_Access_Block_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Public_Access_Block_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Public_Access_Block_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Public_Access_Block_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Accelerate_Configuration_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Accelerate_Configuration_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Accelerate_Configuration_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Accelerate_Configuration_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_ABAC_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_ABAC_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_ABAC_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_ABAC_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Policy_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Policy_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Policy_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Policy_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Policy_Status_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Policy_Status_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Policy_Status_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Policy_Status_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Request_Payment_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Request_Payment_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Request_Payment_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Request_Payment_Operation);
   overriding function Declared_Length
     (Item : Put_Bucket_Policy_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Policy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Policy_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Policy_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_Policy_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_Policy_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Policy_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_Policy_Operation);
   overriding function Declared_Length
     (Item : Delete_Bucket_Policy_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Policy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Policy_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Policy_Operation);
   overriding procedure Write
     (Item : in out Delete_Bucket_Policy_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Delete_Bucket_Policy_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Policy_Operation);
   overriding procedure Finalize
     (Item : in out Delete_Bucket_Policy_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Location_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Location_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Location_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Location_Operation);
   overriding procedure Write
     (Item : in out Get_Bucket_Versioning_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Get_Bucket_Versioning_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Versioning_Operation);
   overriding procedure Finalize
     (Item : in out Get_Bucket_Versioning_Operation);
   overriding function Declared_Length
     (Item : Put_Bucket_Versioning_Operation)
      return Flyology.HTTP.Client.Body_Length;
   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Versioning_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);
   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Versioning_Operation;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);
   overriding procedure Release_Source
     (Item : in out Put_Bucket_Versioning_Operation);
   overriding procedure Write
     (Item : in out Put_Bucket_Versioning_Operation;
      Data : Ada.Streams.Stream_Element_Array);
   overriding procedure Drive
     (Item : in out Put_Bucket_Versioning_Operation;
      Event : Flyology.Operations.Driver_Event);
   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Versioning_Operation);
   overriding procedure Finalize
     (Item : in out Put_Bucket_Versioning_Operation);
   function Normalize_List_Buckets_Response
     (Value     : Low_Level.List_Buckets_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return List_Buckets_Result;
   function Normalize_List_Buckets_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return List_Buckets_Result;
   function Normalize_Create_Bucket_Response
     (Value     : Low_Level.Create_Bucket_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Create_Bucket_Result;
   function Normalize_Create_Bucket_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Create_Bucket_Result;
   function Normalize_Delete_Bucket_Response
     (Value     : Low_Level.Delete_Bucket_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Result;
   function Normalize_Delete_Bucket_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Result;
   function Normalize_Head_Bucket_Response
     (Value     : Low_Level.Head_Bucket_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Head_Bucket_Result;
   function Normalize_Head_Bucket_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Head_Bucket_Result;
   function Normalize_Get_Bucket_Location_Response
     (Value     : Low_Level.Get_Bucket_Location_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Location_Result;
   function Normalize_Get_Bucket_Location_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Location_Result;
   function Normalize_Get_Public_Access_Block_Response
     (Value     : Low_Level.Get_Public_Access_Block_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Public_Access_Block_Result;
   function Normalize_Get_Public_Access_Block_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Public_Access_Block_Result;
   function Normalize_Get_Bucket_Ownership_Controls_Response
     (Value     : Low_Level.Get_Bucket_Ownership_Controls_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Ownership_Controls_Result;
   function Normalize_Get_Bucket_Ownership_Controls_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Ownership_Controls_Result;
   function Normalize_Get_Bucket_CORS_Response
     (Value     : Low_Level.Get_Bucket_CORS_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_CORS_Result;
   function Normalize_Get_Bucket_CORS_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_CORS_Result;
   function Normalize_Delete_Bucket_CORS_Response
     (Value     : Low_Level.Delete_Bucket_CORS_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_CORS_Result;
   function Normalize_Delete_Bucket_CORS_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_CORS_Result;
   function Normalize_Get_Object_Lock_Configuration_Response
     (Value     : Low_Level.Get_Object_Lock_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Object_Lock_Configuration_Result;
   function Normalize_Get_Object_Lock_Configuration_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Get_Object_Lock_Configuration_Result;
   function Normalize_Put_Object_Lock_Configuration_Response
     (Value     : Low_Level.Put_Object_Lock_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Object_Lock_Configuration_Result;
   function Normalize_Put_Object_Lock_Configuration_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Put_Object_Lock_Configuration_Result;
   function Normalize_Get_Bucket_Encryption_Response
     (Value     : Low_Level.Get_Bucket_Encryption_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Encryption_Result;
   function Normalize_Get_Bucket_Encryption_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Encryption_Result;
   --  @exclude
   function Normalize_Get_Bucket_Lifecycle_Response
     (Value : Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Lifecycle_Result;
   --  @exclude
   function Normalize_Get_Bucket_Lifecycle_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Lifecycle_Result;
   --  @exclude
   function Normalize_Get_Bucket_Replication_Response
     (Value : Low_Level.Get_Bucket_Replication_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Replication_Result;
   --  @exclude
   function Normalize_Put_Bucket_Replication_Response
     (Value : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase : Flyology.HTTP.Client.Exchange_Phase)
      return Put_Bucket_Replication_Result;
   --  @exclude
   function Normalize_Put_Bucket_Replication_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Put_Bucket_Replication_Result;
   --  @exclude
   function Normalize_Get_Bucket_Notification_Response
     (Value : Low_Level.Get_Bucket_Notification_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase : Flyology.HTTP.Client.Exchange_Phase)
      return Get_Bucket_Notification_Result;
   --  @exclude
   function Normalize_Get_Bucket_Notification_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Get_Bucket_Notification_Result;
   --  @exclude
   function Normalize_Get_Bucket_ACL_Response
     (Value     : Low_Level.Get_Bucket_ACL_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_ACL_Result;
   --  @exclude
   function Normalize_Get_Bucket_ACL_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_ACL_Result;
   --  @exclude
   function Normalize_Get_Metadata_Table_Response
     (Value : Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Metadata_Table_Configuration_Result;
   --  @exclude
   function Normalize_Get_Metadata_Table_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Get_Bucket_Metadata_Table_Configuration_Result;
   --  @exclude
   function Normalize_Create_Metadata_Table_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Create_Bucket_Metadata_Table_Configuration_Result;
   --  @exclude
   function Normalize_Create_Metadata_Table_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Create_Bucket_Metadata_Table_Configuration_Result;
   --  @exclude
   --  @param Value Complete decoded PutBucketEncryption response
   --  @param Admission HTTP admission certainty for that response
   --  @return Provider-level mutation result
   function Normalize_Put_Bucket_Encryption_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Encryption_Result;
   --  @exclude
   --  @param Kind Typed HTTP failure
   --  @param Admission HTTP admission certainty
   --  @param Phase Causal HTTP phase
   --  @param Detail Bounded sanitized HTTP diagnostic
   --  @return Provider-level ambiguous or pre-admission result
   function Normalize_Put_Bucket_Encryption_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Encryption_Result;
   function Normalize_Delete_Bucket_Encryption_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Encryption_Result;
   function Normalize_Delete_Bucket_Encryption_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Encryption_Result;
   --  @exclude
   function Normalize_Put_Bucket_Lifecycle_Response
     (Value     : Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase)
      return Put_Bucket_Lifecycle_Result;
   --  @exclude
   function Normalize_Put_Bucket_Lifecycle_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Put_Bucket_Lifecycle_Result;
   --  @exclude
   function Normalize_Put_Bucket_Notification_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase)
      return Put_Bucket_Notification_Result;
   --  @exclude
   function Normalize_Put_Bucket_Notification_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Put_Bucket_Notification_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Lifecycle_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Lifecycle_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Lifecycle_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Lifecycle_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Replication_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Replication_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Replication_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Replication_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Website_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Website_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Website_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Website_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Metadata_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Metadata_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Metadata_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Metadata_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Metadata_Table_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Metadata_Table_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Metadata_Table_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Metadata_Table_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Metrics_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Metrics_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Metrics_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Metrics_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Analytics_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Analytics_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Analytics_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Analytics_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Tiering_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Tiering_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Tiering_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Tiering_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Inventory_Configuration_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Inventory_Configuration_Result;
   --  @exclude
   function Normalize_Delete_Bucket_Inventory_Configuration_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Delete_Bucket_Inventory_Configuration_Result;
   function Normalize_Put_Bucket_CORS_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_CORS_Result;
   function Normalize_Put_Bucket_CORS_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_CORS_Result;
   function Normalize_Put_Bucket_Ownership_Controls_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Ownership_Controls_Result;
   function Normalize_Put_Bucket_Ownership_Controls_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Ownership_Controls_Result;
   function Normalize_Delete_Ownership_Controls_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Ownership_Controls_Result;
   function Normalize_Delete_Ownership_Controls_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Ownership_Controls_Result;
   function Normalize_Put_Bucket_ABAC_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_ABAC_Result;
   function Normalize_Put_Bucket_ABAC_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_ABAC_Result;
   function Normalize_Put_Bucket_Accelerate_Configuration_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Accelerate_Configuration_Result;
   function Normalize_Put_Bucket_Accelerate_Configuration_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Put_Bucket_Accelerate_Configuration_Result;
   function Normalize_Put_Bucket_Request_Payment_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Request_Payment_Result;
   function Normalize_Put_Bucket_Request_Payment_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Request_Payment_Result;
   function Normalize_Put_Public_Access_Block_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Public_Access_Block_Result;
   function Normalize_Put_Public_Access_Block_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Public_Access_Block_Result;
   function Normalize_Delete_Public_Access_Block_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Public_Access_Block_Result;
   function Normalize_Delete_Public_Access_Block_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Public_Access_Block_Result;
   function Normalize_Get_Bucket_Accelerate_Configuration_Response
     (Value     : Low_Level.Get_Bucket_Accelerate_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Accelerate_Configuration_Result;
   function Normalize_Get_Bucket_Accelerate_Configuration_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "")
      return Get_Bucket_Accelerate_Configuration_Result;
   function Normalize_Get_Bucket_ABAC_Response
     (Value     : Low_Level.Get_Bucket_Abac_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_ABAC_Result;
   function Normalize_Get_Bucket_ABAC_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_ABAC_Result;
   function Normalize_Get_Bucket_Policy_Response
     (Value     : Low_Level.Get_Bucket_Policy_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Policy_Result;
   function Normalize_Get_Bucket_Policy_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Policy_Result;
   function Normalize_Get_Bucket_Policy_Status_Response
     (Value     : Low_Level.Get_Bucket_Policy_Status_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Policy_Status_Result;
   function Normalize_Get_Bucket_Policy_Status_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Policy_Status_Result;
   function Normalize_Get_Bucket_Request_Payment_Response
     (Value     : Low_Level.Get_Bucket_Request_Payment_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Request_Payment_Result;
   function Normalize_Get_Bucket_Request_Payment_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Request_Payment_Result;
   function Normalize_Put_Bucket_Policy_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Policy_Result;
   function Normalize_Put_Bucket_Policy_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Policy_Result;
   function Normalize_Delete_Bucket_Policy_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Policy_Result;
   function Normalize_Delete_Bucket_Policy_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Policy_Result;
   function Normalize_Get_Bucket_Versioning_Response
     (Value     : Low_Level.Get_Bucket_Versioning_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Versioning_Result;
   function Normalize_Get_Bucket_Versioning_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Versioning_Result;
   function Normalize_Put_Bucket_Versioning_Response
     (Value     : Low_Level.Put_Bucket_Versioning_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Versioning_Result;
   function Normalize_Put_Bucket_Versioning_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Versioning_Result;
   function Normalize_Put_Bucket_Tagging_Response
     (Value     : Low_Level.Put_Bucket_Tagging_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Put_Bucket_Tagging_Result;
   function Normalize_Put_Bucket_Tagging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Tagging_Result;
   function Normalize_Get_Bucket_Tagging_Response
     (Value     : Low_Level.Get_Bucket_Tagging_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Get_Bucket_Tagging_Result;
   function Normalize_Get_Bucket_Tagging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Tagging_Result;
   function Normalize_Delete_Bucket_Tagging_Response
     (Value     : Low_Level.Delete_Bucket_Tagging_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Delete_Bucket_Tagging_Result;
   function Normalize_Delete_Bucket_Tagging_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Tagging_Result;

end Flyology.Object_Storage.Client.Buckets;
