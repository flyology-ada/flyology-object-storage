with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Bytes;
with Flyology.IO;
with Flyology.Operations;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Errors;
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

   --  Remove one named intelligent-tiering configuration.
   function Delete_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

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

   --  Remove the complete metadata-table configuration.
   function Delete_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

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

   --  Remove the complete replication configuration.
   function Delete_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete website configuration.
   function Delete_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

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
   function Normalize_Head_Bucket_Response
     (Value     : Low_Level.Head_Bucket_Outcome;
      Admission : Flyology.HTTP.Client.Admission_Certainty)
      return Head_Bucket_Result;
   function Normalize_Head_Bucket_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String := "") return Head_Bucket_Result;
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
