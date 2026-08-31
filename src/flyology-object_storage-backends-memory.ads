with Ada.Finalization;
with Ada.Containers.Indefinite_Ordered_Maps;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Streams;
with Flyology.Cancellation;
with Flyology.Object_Storage.Tags;

--  Provides a bounded concurrent in-memory backend. Object_Capacity
--  independently bounds retained object generations (including markers),
--  uploads, and parts; retaining history therefore consumes object slots.
--  Byte_Capacity covers retained committed, staged, and in-progress object
--  payload buffers plus retained opaque bucket-configuration bytes, including
--  policy, CORS, encryption, ownership controls, lifecycle, logging,
--  analytics, and metrics; atomic replacement and multipart assembly
--  therefore require coexistence headroom.
--  It implements the same contract as durable backends and is the reference
--  oracle for conformance tests; capacity exhaustion is an ordinary reported
--  outcome.
package Flyology.Object_Storage.Backends.Memory is

   type Store
     (Bucket_Capacity : Positive;
      Object_Capacity : Positive;
      Byte_Capacity   : Byte_Count)
   is limited new Backend with private;

   overriding procedure Create_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure List_Buckets
     (Item     : in out Store;
      Options  : List_Buckets_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out Bucket_Page;
      Result   : out Status);

   overriding procedure Delete_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Head_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Value    : Tags.Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Tags.Tag_Set;
      Result   : out Status);

   overriding procedure Delete_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_CORS
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_CORS
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   overriding procedure Delete_Bucket_CORS
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Retain one bounded encryption override in memory.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Document Canonical encryption bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Encryption
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic in-memory encryption-override snapshot.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether an override is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Encryption
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove the retained in-memory encryption override.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Encryption
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Retain one bounded ownership-controls document in memory.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Document Canonical ownership-controls bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Ownership_Controls
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic in-memory ownership-controls snapshot.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether ownership controls are retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Ownership_Controls
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove retained in-memory ownership controls.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Ownership_Controls
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Retain one bounded lifecycle document in memory.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Document Canonical lifecycle bytes
   --  @param Transition_Default_Minimum_Object_Size Exact optional response
   --  header value, or the empty string when absent
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Lifecycle
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Transition_Default_Minimum_Object_Size : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic in-memory lifecycle snapshot.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Transition_Default_Minimum_Object_Size Exact retained optional
   --  response-header value, or the empty string when absent
   --  @param Configured Whether lifecycle state is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Lifecycle
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Transition_Default_Minimum_Object_Size :
        out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove retained in-memory lifecycle state.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Lifecycle
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Retain one bounded logging document in memory.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Document Canonical logging bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Logging
     (Item     : in out Store;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic in-memory logging snapshot.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether explicit logging state is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Logging
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Retain one analytics configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Document Canonical analytics-configuration bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Analytics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Read one analytics configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether the selected configuration is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Analytics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove one analytics configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Analytics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Retain one metrics configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Document Canonical metrics-configuration bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Metrics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Read one metrics configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether the selected configuration is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Metrics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove one metrics configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Metrics_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Retain one Intelligent-Tiering configuration by its exact request
   --  identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Document Canonical Intelligent-Tiering configuration bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Intelligent_Tiering_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Read one Intelligent-Tiering configuration by its exact request
   --  identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether the selected configuration is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Intelligent_Tiering_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove one Intelligent-Tiering configuration by its exact request
   --  identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Intelligent_Tiering_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Retain one inventory configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Document Canonical inventory-configuration bytes
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Inventory_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   --  Read one inventory configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Retained canonical bytes
   --  @param Configured Whether the selected configuration is retained
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Inventory_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Remove one inventory configuration by its exact request identifier.
   --  @param Item In-memory backend
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Delete_Bucket_Inventory_Configuration
     (Item       : in out Store;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status);

   overriding procedure Put_Bucket_Public_Access_Block
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Public_Access_Block_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status);

   overriding procedure Get_Bucket_Public_Access_Block
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Public_Access_Block_Configuration;
      Configured    : out Boolean;
      Result        : out Status);

   overriding procedure Delete_Bucket_Public_Access_Block
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Policy
     (Item     : in out Store;
      Bucket   : String;
      Policy   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_Policy
     (Item       : in out Store;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Policy     : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   overriding procedure Delete_Bucket_Policy
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Configuration : Bucket_Versioning_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status;
      MFA_Validated : Boolean := False);

   overriding procedure Get_Bucket_Versioning
     (Item          : in out Store;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status);

   --  Replace the ABAC state in the protected in-memory catalog.
   --  @param Item In-memory store
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving ABAC state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_ABAC
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_ABAC_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic ABAC snapshot from the in-memory catalog.
   --  @param Item In-memory store
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete presence-preserving ABAC snapshot
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_ABAC
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_ABAC_Status;
      Result   : out Status);

   --  Replace the acceleration state in the protected in-memory catalog.
   --  @param Item In-memory store
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving acceleration state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Acceleration
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_Acceleration_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic acceleration snapshot from the in-memory catalog.
   --  @param Item In-memory store
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete presence-preserving acceleration snapshot
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Acceleration
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Acceleration_Status;
      Result   : out Status);

   --  Replace the request-payment state in the protected catalog.
   --  @param Item In-memory store
   --  @param Bucket Existing bucket name
   --  @param Value Complete request-payment state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   overriding procedure Put_Bucket_Request_Payment
     (Item     : in out Store;
      Bucket   : String;
      Value    : Bucket_Request_Payment_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   --  Read one atomic request-payment snapshot from the in-memory catalog.
   --  @param Item In-memory store
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete request-payment snapshot
   --  @param Result Storage outcome
   overriding procedure Get_Bucket_Request_Payment
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Request_Payment_Status;
      Result   : out Status);

   --  Publish one buffered generation and return its version identity from
   --  the same protected-state commit.
   --  @param Item In-memory store
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Source One-shot body source consumed synchronously
   --  @param Options Complete object publication options
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata published on success
   --  @param Identity Omitted, opaque, or null identity on success only
   --  @param Result Publication result
   --  @param Conditions Atomic destination ETag predicates
   overriding procedure Put_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Identity : out Version_Identity;
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions);

   --  Copy one selected in-memory generation and return both atomic
   --  identities on success.
   --  @param Item Memory backend instance
   --  @param Source_Bucket Source bucket name
   --  @param Source_Key Source key
   --  @param Destination_Bucket Destination bucket name
   --  @param Destination_Key Destination key
   --  @param Options Source selection and copy policy
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Published destination metadata on success
   --  @param Source_Identity Selected source generation on success
   --  @param Destination_Identity Published destination generation on success
   --  @param Result Storage-domain outcome
   overriding procedure Copy_Object
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Copy_Options;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Source_Identity    : out Version_Identity;
      Destination_Identity : out Version_Identity;
      Result             : out Status);

   --  Read one selected in-memory metadata generation.
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Head_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector);

   --  Stream one selected in-memory object generation.
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Get_Object
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Requested : Byte_Range;
      Sink      : in out Byte_Sink'Class;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector);

   --  Read attributes from one selected in-memory generation.
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Get_Object_Attributes
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Options  : Object_Attribute_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Snapshot : out Object_Attribute_Snapshot;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector);

   overriding procedure Delete_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status;
      Conditions : Delete_Object_Conditions :=
        No_Delete_Object_Conditions;
      Requirements : Delete_Objects_Requirements := (others => <>));

   --  Delete or mark one selected in-memory generation atomically.
   --  @param Item Memory backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Selector Current, null, or exact deletion target
   --  @param Conditions Optional selected-generation predicates
   --  @param MFA_Validated Caller authorization attestation for MFA Delete
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Outcome Exact publication effect and generation identity
   --  @param Result Storage-domain outcome
   overriding procedure Delete_Selected_Object
     (Item          : in out Store;
      Bucket        : String;
      Key           : String;
      Selector      : Version_Selector;
      Conditions    : Delete_Object_Conditions;
      MFA_Validated : Boolean;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Outcome       : out Version_Delete_Outcome;
      Result        : out Status);

   overriding procedure Delete_Objects
     (Item     : in out Store;
      Bucket   : String;
      Entries  : Delete_Object_Entries;
      Requirements : Delete_Objects_Requirements;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Outcomes : out Delete_Object_Outcomes;
      Result   : out Status);

   --  Replace tags on one selected in-memory generation.
   --  @param Identity Selected generation from the mutation snapshot
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Read tags from one selected in-memory generation.
   --  @param Identity Selected generation from the read snapshot
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Clear tags on one selected in-memory generation.
   --  @param Identity Selected generation from the mutation snapshot
   --  @param Selector Current, null, or exact generation selection
   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   overriding procedure List_Objects
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Page;
      Result   : out Status);

   --  Return one bounded, atomically ordered in-memory generation page.
   --  @param Item Memory backend instance
   --  @param Bucket Bucket name
   --  @param Options Prefix, delimiter, paired cursor, and page bound
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Page Atomic bounded result page
   --  @param Result Storage-domain outcome
   overriding procedure List_Object_Versions
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Versions_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Versions_Page;
      Result   : out Status);

   overriding procedure Create_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Options   : Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
      Result    : out Status);

   overriding procedure Put_Multipart_Part
     (Item        : in out Store;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Options     : Multipart_Part_Options;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status);

   overriding procedure List_Multipart_Parts
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : List_Multipart_Parts_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Part_Page;
      Result    : out Status);

   overriding procedure List_Multipart_Uploads
     (Item      : in out Store;
      Bucket    : String;
      Options   : List_Multipart_Uploads_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Upload_Page;
      Result    : out Status);

   overriding procedure Copy_Multipart_Part
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Upload_ID          : String;
      Part_Number        : Multipart_Part_Number;
      Requested          : Byte_Range;
      Conditions         : Copy_Conditions;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status);

   overriding procedure Complete_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Options   : Complete_Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status);

   overriding procedure Abort_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Conditions : Abort_Multipart_Conditions;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Result    : out Status);

   --  Return the current retained byte total, including committed objects,
   --  bucket policies, staged multipart parts, and reserved in-progress input
   --  and immutable outbound snapshot buffer capacity.
   function Bytes_Used (Item : Store) return Byte_Count;

private
   type Singleton_Configuration_Kind is
     (Lifecycle_Configuration, Logging_Configuration);
   type Configuration_Document_Array is array
     (Singleton_Configuration_Kind) of
       Ada.Strings.Unbounded.Unbounded_String;
   type Configuration_Presence_Array is array
     (Singleton_Configuration_Kind) of Boolean;
   type Named_Configuration_Kind is
     (Analytics_Configuration,
      Metrics_Configuration,
      Intelligent_Tiering_Configuration,
      Inventory_Configuration);
   package Named_Configuration_Maps is new
     Ada.Containers.Indefinite_Ordered_Maps
       (Key_Type     => String,
        Element_Type => Ada.Strings.Unbounded.Unbounded_String,
        "="          => Ada.Strings.Unbounded."=");
   type Named_Configuration_Map_Array is array
     (Named_Configuration_Kind) of Named_Configuration_Maps.Map;

   type Byte_Array_Access is access Ada.Streams.Stream_Element_Array;

   type Owned_Bytes is new Ada.Finalization.Controlled with record
      Value    : Byte_Array_Access := null;
      Length   : Natural := 0;
      Capacity : Natural := 0;
   end record;

   overriding procedure Adjust (Data : in out Owned_Bytes);
   overriding procedure Finalize (Data : in out Owned_Bytes);
   procedure Append
     (Data  : in out Owned_Bytes;
      Value : Ada.Streams.Stream_Element_Array);
   procedure Append (Data : in out Owned_Bytes; Value : Owned_Bytes);
   procedure Reserve_Capacity
     (Data : in out Owned_Bytes; Capacity : Natural);
   procedure Move (Target : in out Owned_Bytes; Source : in out Owned_Bytes);
   function Element
     (Data : Owned_Bytes; Index : Positive)
      return Ada.Streams.Stream_Element;

   type Bucket_Slot is record
      Used    : Boolean := False;
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Created : Unix_Time := 0;
      Tags    : Flyology.Object_Storage.Tags.Tag_Set;
      Versioning : Bucket_Versioning_Configuration := (others => <>);
      ABAC : Bucket_ABAC_Status := Bucket_ABAC_Disabled;
      Acceleration : Bucket_Acceleration_Status :=
        Bucket_Acceleration_Unconfigured;
      Request_Payment : Bucket_Request_Payment_Status := Bucket_Owner_Pays;
      CORS_Configured : Boolean := False;
      CORS_Document : Ada.Strings.Unbounded.Unbounded_String;
      Encryption_Configured : Boolean := False;
      Encryption_Document : Ada.Strings.Unbounded.Unbounded_String;
      Ownership_Controls_Configured : Boolean := False;
      Ownership_Controls_Document :
        Ada.Strings.Unbounded.Unbounded_String;
      Configuration_Configured : Configuration_Presence_Array :=
        (others => False);
      Configuration_Documents : Configuration_Document_Array;
      Configuration_Metadata : Configuration_Document_Array;
      Named_Configurations : Named_Configuration_Map_Array;
      Public_Access_Block_Configured : Boolean := False;
      Public_Access_Block : Bucket_Public_Access_Block_Configuration :=
        (others => <>);
      Policy_Configured : Boolean := False;
      Policy : Ada.Strings.Unbounded.Unbounded_String;
   end record;
   type Bucket_Array is array (Positive range <>) of Bucket_Slot;

   type Object_Slot is record
      Used   : Boolean := False;
      Bucket : Ada.Strings.Unbounded.Unbounded_String;
      Key    : Ada.Strings.Unbounded.Unbounded_String;
      --  Null generations are distinct from generated opaque versions even
      --  though legacy current-object APIs expose both through the same
      --  Object_Information.Version string representation.
      Is_Null_Version : Boolean := True;
      Is_Delete_Marker : Boolean := False;
      Publication : Version_Publication_Order := 0;
      Info   : Object_Information;
      Tags   : Object_Tag_Set;
      Completed_Parts : Completed_Object_Part_List;
      Data   : Owned_Bytes;
   end record;
   type Object_Array is array (Positive range <>) of Object_Slot;

   type Upload_Slot is record
      Used       : Boolean := False;
      ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket     : Ada.Strings.Unbounded.Unbounded_String;
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Options    : Multipart_Options := Default_Multipart_Options;
      Created    : Unix_Time := 0;
   end record;
   type Upload_Array is array (Positive range <>) of Upload_Slot;

   type Part_Slot is record
      Used       : Boolean := False;
      Upload_ID  : Ada.Strings.Unbounded.Unbounded_String;
      Number     : Multipart_Part_Number := Multipart_Part_Number'First;
      Info       : Object_Information;
      Data       : Owned_Bytes;
   end record;
   type Part_Array is array (Positive range <>) of Part_Slot;

   protected type Memory_State
     (Bucket_Limit : Positive;
      Object_Limit : Positive;
      Byte_Limit   : Byte_Count)
   is
      procedure Create_Bucket
        (Name : String; Created : Unix_Time; Result : out Status);
      procedure List_Buckets
        (Options : List_Buckets_Options;
         Page    : out Bucket_Page;
         Result  : out Status);
      procedure Head_Bucket (Name : String; Result : out Status);
      procedure Put_Bucket_Versioning
        (Name          : String;
         Configuration : Bucket_Versioning_Configuration;
         Result        : out Status;
         MFA_Validated : Boolean := False);
      procedure Get_Bucket_Versioning
        (Name          : String;
         Configuration : out Bucket_Versioning_Configuration;
         Result        : out Status);
      procedure Put_Bucket_ABAC
        (Name : String; Value : Bucket_ABAC_Status; Result : out Status);
      procedure Get_Bucket_ABAC
        (Name : String; Value : out Bucket_ABAC_Status; Result : out Status);
      procedure Put_Bucket_Acceleration
        (Name : String;
         Value : Bucket_Acceleration_Status;
         Result : out Status);
      procedure Get_Bucket_Acceleration
        (Name : String;
         Value : out Bucket_Acceleration_Status;
         Result : out Status);
      procedure Put_Bucket_Request_Payment
        (Name : String;
         Value : Bucket_Request_Payment_Status;
         Result : out Status);
      procedure Get_Bucket_Request_Payment
        (Name : String;
         Value : out Bucket_Request_Payment_Status;
         Result : out Status);
      procedure Delete_Bucket (Name : String; Result : out Status);
      procedure Put_Bucket_Tags
        (Name : String; Value : Tags.Tag_Set; Result : out Status);
      procedure Get_Bucket_Tags
        (Name : String; Value : out Tags.Tag_Set; Result : out Status);
      procedure Delete_Bucket_Tags (Name : String; Result : out Status);
      procedure Put_Bucket_CORS
        (Name : String; Document : String; Result : out Status);
      procedure Get_Bucket_CORS
        (Name       : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status);
      procedure Delete_Bucket_CORS
        (Name : String; Result : out Status);
      procedure Put_Bucket_Encryption
        (Name : String; Document : String; Result : out Status);
      procedure Get_Bucket_Encryption
        (Name       : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status);
      procedure Delete_Bucket_Encryption
        (Name : String; Result : out Status);
      procedure Put_Bucket_Ownership_Controls
        (Name : String; Document : String; Result : out Status);
      procedure Get_Bucket_Ownership_Controls
        (Name       : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status);
      procedure Delete_Bucket_Ownership_Controls
        (Name : String; Result : out Status);
      procedure Put_Bucket_Configuration
        (Name     : String;
         Kind     : Singleton_Configuration_Kind;
         Document : String;
         Metadata : String;
         Result   : out Status);
      procedure Get_Bucket_Configuration
        (Name       : String;
         Kind       : Singleton_Configuration_Kind;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Metadata   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status);
      procedure Delete_Bucket_Configuration
        (Name   : String;
         Kind   : Singleton_Configuration_Kind;
         Result : out Status);
      procedure Put_Named_Bucket_Configuration
        (Name       : String;
         Kind       : Named_Configuration_Kind;
         Identifier : String;
         Document   : String;
         Result     : out Status);
      procedure Get_Named_Bucket_Configuration
        (Name       : String;
         Kind       : Named_Configuration_Kind;
         Identifier : String;
         Document   : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status);
      procedure Delete_Named_Bucket_Configuration
        (Name       : String;
         Kind       : Named_Configuration_Kind;
         Identifier : String;
         Result     : out Status);
      procedure Put_Bucket_Public_Access_Block
        (Name          : String;
         Configuration : Bucket_Public_Access_Block_Configuration;
         Result        : out Status);
      procedure Get_Bucket_Public_Access_Block
        (Name          : String;
         Configuration : out Bucket_Public_Access_Block_Configuration;
         Configured    : out Boolean;
         Result        : out Status);
      procedure Delete_Bucket_Public_Access_Block
        (Name : String; Result : out Status);
      procedure Put_Bucket_Policy
        (Name : String; Policy : String; Result : out Status);
      procedure Get_Bucket_Policy
        (Name       : String;
         Policy     : out Ada.Strings.Unbounded.Unbounded_String;
         Configured : out Boolean;
         Result     : out Status);
      procedure Delete_Bucket_Policy
        (Name : String; Result : out Status);
      procedure Reserve_Transient
        (Amount : Byte_Count; Result : out Status);
      procedure Release_Transient (Amount : Byte_Count);
      procedure Commit
        (Bucket : String;
         Key    : String;
         Data   : in out Owned_Bytes;
         Info   : Object_Information;
         Tags   : Object_Tag_Set;
         Conditions : Write_Conditions;
         Stored : out Object_Information;
         Identity : out Version_Identity;
         Result : out Status);
      procedure Fetch
        (Bucket : String;
         Key    : String;
         Selector : Version_Selector;
         Data   : out Owned_Bytes;
         Info   : out Object_Information;
         Tags   : out Object_Tag_Set;
         Identity : out Version_Identity;
         Result : out Status);
      procedure Fetch_Range
        (Bucket    : String;
         Key       : String;
         Requested : Byte_Range;
         Data      : out Owned_Bytes;
         Info      : out Object_Information;
         Result    : out Status);
      procedure Head
        (Bucket : String;
         Key    : String;
         Selector : Version_Selector;
         Info   : out Object_Information;
         Result : out Status);
      procedure Attributes
        (Bucket   : String;
         Key      : String;
         Selector : Version_Selector;
         Options  : Object_Attribute_Options;
         Conditions : Read_Conditions;
         Snapshot : out Object_Attribute_Snapshot;
         Result   : out Status);
      procedure Delete_Many
        (Bucket   : String;
         Entries  : Delete_Object_Entries;
         Requirements : Delete_Objects_Requirements;
         Modified : Unix_Time;
         Outcomes : in out Delete_Object_Outcomes;
         Result   : out Status);
      procedure Delete_Selected
        (Bucket        : String;
         Key           : String;
         Selector      : Version_Selector;
         Conditions    : Delete_Object_Conditions;
         MFA_Validated : Boolean;
         Modified      : Unix_Time;
         Outcome       : out Version_Delete_Outcome;
         Result        : out Status);
      procedure Put_Tags
        (Bucket : String; Key : String; Selector : Version_Selector;
         Tags : Object_Tag_Set;
         Identity : out Version_Identity;
         Result : out Status);
      procedure Get_Tags
        (Bucket : String; Key : String; Selector : Version_Selector;
         Tags : out Object_Tag_Set;
         Identity : out Version_Identity;
         Result : out Status);
      procedure Delete_Tags
        (Bucket : String; Key : String; Selector : Version_Selector;
         Identity : out Version_Identity;
         Result : out Status);
      procedure List
        (Bucket  : String;
         Options : List_Options;
         Page    : out List_Page;
         Result  : out Status);
      procedure List_Versions
        (Bucket  : String;
         Options : List_Versions_Options;
         Page    : out List_Versions_Page;
         Result  : out Status);
      procedure Start_Multipart
        (Bucket    : String;
         Key       : String;
         Options   : Multipart_Options;
         Created   : Unix_Time;
         Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
         Result    : out Status);
      procedure List_Uploads
        (Bucket  : String;
         Options : List_Multipart_Uploads_Options;
         Page    : out Multipart_Upload_Page;
         Result  : out Status);
      procedure Multipart_Configuration
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Options   : out Multipart_Options;
         Result    : out Status);
      procedure Commit_Part
        (Bucket      : String;
         Key         : String;
         Upload_ID   : String;
         Part_Number : Multipart_Part_Number;
         Data        : in out Owned_Bytes;
         Info        : Object_Information;
         Stored      : out Object_Information;
         Result      : out Status);
      procedure List_Parts
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Options   : List_Multipart_Parts_Options;
         Page      : out Multipart_Part_Page;
         Result    : out Status);
      procedure Complete_Multipart
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Completion : Multipart_Part_References;
         Options   : Complete_Multipart_Options;
         Modified  : Unix_Time;
         Info      : out Object_Information;
         Result    : out Status);
      procedure Abort_Multipart
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Conditions : Abort_Multipart_Conditions;
         Result    : out Status);
      function Used_Bytes return Byte_Count;
   private
      function Bucket_Index (Name : String) return Natural;
      function Object_Index
        (Bucket : String; Key : String) return Natural;
      function Selected_Generation_Index
        (Bucket : String; Key : String; Selector : Version_Selector)
         return Natural;
      function Selected_Object_Index
        (Bucket : String; Key : String; Selector : Version_Selector)
         return Natural;
      function Upload_Index
        (Bucket : String; Key : String; Upload_ID : String) return Natural;
      function Part_Index
        (Upload_ID : String;
         Part_Number : Multipart_Part_Number) return Natural;
      Buckets : Bucket_Array (1 .. Bucket_Limit);
      Objects : Object_Array (1 .. Object_Limit);
      Uploads : Upload_Array (1 .. Object_Limit);
      Parts   : Part_Array (1 .. Object_Limit);
      Highest_Object : Natural := 0;
      Highest_Part   : Natural := 0;
      Bytes   : Byte_Count := 0;
      Reserved_Bytes : Byte_Count := 0;
      Next_Upload : Long_Long_Integer := 0;
      --  Every retained generation receives one strictly increasing order.
      --  Exhaustion fails closed rather than reusing a version identity.
      Next_Version : Version_Publication_Order := 0;
   end Memory_State;

   type Store
     (Bucket_Capacity : Positive;
      Object_Capacity : Positive;
      Byte_Capacity   : Byte_Count)
   is limited new Backend with record
      State : Memory_State
        (Bucket_Capacity, Object_Capacity, Byte_Capacity);
   end record;

end Flyology.Object_Storage.Backends.Memory;
