with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.SQLite.Databases;
with Flyology.Object_Storage.Tags;

--  Transactional namespace and object metadata for the SQLite backend.
--  Payloads are immutable external files named by the backend.
package Flyology.Object_Storage.SQLite.Catalogs is

   Catalog_Error : exception;

   type Catalog is limited private;

   procedure Open (Item : in out Catalog; Path : String);
   procedure Close (Item : in out Catalog);

   procedure Create_Bucket
     (Item    : in out Catalog;
      Name    : String;
      Created : Unix_Time;
      Result  : out Status);

   procedure List_Buckets
     (Item    : in out Catalog;
      Options : Backends.List_Buckets_Options;
      Check   : not null access procedure;
      Page    : out Backends.Bucket_Page;
      Result  : out Status);

   procedure Head_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Put_Bucket_Versioning
     (Item          : in out Catalog;
      Name          : String;
      Configuration : Bucket_Versioning_Configuration;
      Result        : out Status;
      MFA_Validated : Boolean := False);

   procedure Get_Bucket_Versioning
     (Item          : in out Catalog;
      Name          : String;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status);

   --  Replace the ABAC state in one catalog transaction.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving ABAC state
   --  @param Result Storage outcome
   procedure Put_Bucket_ABAC
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Bucket_ABAC_Status;
      Result : out Status);

   --  Read one ABAC snapshot from a catalog transaction.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving ABAC snapshot
   --  @param Result Storage outcome
   procedure Get_Bucket_ABAC
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Bucket_ABAC_Status;
      Result : out Status);

   --  Replace the acceleration state in one catalog transaction.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving acceleration state
   --  @param Result Storage outcome
   procedure Put_Bucket_Acceleration
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Bucket_Acceleration_Status;
      Result : out Status);

   --  Read one acceleration snapshot from a catalog transaction.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving acceleration snapshot
   --  @param Result Storage outcome
   procedure Get_Bucket_Acceleration
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Bucket_Acceleration_Status;
      Result : out Status);

   --  Replace request-payment state in one catalog transaction.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Value Complete request-payment state
   --  @param Result Storage outcome
   procedure Put_Bucket_Request_Payment
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Bucket_Request_Payment_Status;
      Result : out Status);

   --  Read one request-payment snapshot from a catalog transaction.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Value Complete request-payment snapshot
   --  @param Result Storage outcome
   procedure Get_Bucket_Request_Payment
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Bucket_Request_Payment_Status;
      Result : out Status);

   procedure Delete_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Put_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Tags.Tag_Set;
      Result : out Status);

   procedure Get_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Tags.Tag_Set;
      Result : out Status);

   procedure Delete_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   procedure Put_Bucket_CORS
     (Item     : in out Catalog;
      Bucket   : String;
      Document : String;
      Result   : out Status);

   procedure Get_Bucket_CORS
     (Item       : in out Catalog;
      Bucket     : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   procedure Delete_Bucket_CORS
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   --  Transactionally retain one encryption override.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Canonical encryption bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Encryption
     (Item     : in out Catalog;
      Bucket   : String;
      Document : String;
      Result   : out Status);

   --  Read one transactional encryption-override snapshot.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Retained canonical bytes
   --  @param Configured Whether an override is retained
   --  @param Result Storage outcome
   procedure Get_Bucket_Encryption
     (Item       : in out Catalog;
      Bucket     : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove the retained encryption override.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Result Storage outcome
   procedure Delete_Bucket_Encryption
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   --  Transactionally retain one ownership-controls document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Canonical ownership-controls bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Ownership_Controls
     (Item     : in out Catalog;
      Bucket   : String;
      Document : String;
      Result   : out Status);

   --  Read one transactional ownership-controls snapshot.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Retained canonical bytes
   --  @param Configured Whether ownership controls are retained
   --  @param Result Storage outcome
   procedure Get_Bucket_Ownership_Controls
     (Item       : in out Catalog;
      Bucket     : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove retained ownership controls.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Result Storage outcome
   procedure Delete_Bucket_Ownership_Controls
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   --  Transactionally retain one lifecycle document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Canonical lifecycle bytes
   --  @param Transition_Default_Minimum_Object_Size Exact optional header
   --  @param Result Storage outcome
   procedure Put_Bucket_Lifecycle
     (Item                                   : in out Catalog;
      Bucket                                 : String;
      Document                               : String;
      Transition_Default_Minimum_Object_Size : String;
      Result                                 : out Status);

   --  Read one transactional lifecycle snapshot.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Retained canonical bytes
   --  @param Transition_Default_Minimum_Object_Size Retained optional header
   --  @param Configured Whether lifecycle state is retained
   --  @param Result Storage outcome
   procedure Get_Bucket_Lifecycle
     (Item       : in out Catalog;
      Bucket     : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Transition_Default_Minimum_Object_Size :
        out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove retained lifecycle state.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Result Storage outcome
   procedure Delete_Bucket_Lifecycle
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   --  Transactionally retain one logging document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Canonical logging bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Logging
     (Item     : in out Catalog;
      Bucket   : String;
      Document : String;
      Result   : out Status);

   --  Read one transactional logging snapshot.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Document Retained canonical bytes
   --  @param Configured Whether explicit logging state is retained
   --  @param Result Storage outcome
   procedure Get_Bucket_Logging
     (Item       : in out Catalog;
      Bucket     : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally replace one query-keyed analytics document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Canonical analytics XML bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Analytics_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Result     : out Status);

   --  Read one query-keyed analytics document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Retained canonical XML bytes
   --  @param Configured Whether the selected configuration exists
   --  @param Result Storage outcome
   procedure Get_Bucket_Analytics_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove one query-keyed analytics document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Result Storage outcome
   procedure Delete_Bucket_Analytics_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Result     : out Status);

   --  Transactionally replace one query-keyed metrics document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Canonical metrics XML bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Metrics_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Result     : out Status);

   --  Read one query-keyed metrics document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Retained canonical XML bytes
   --  @param Configured Whether the selected configuration exists
   --  @param Result Storage outcome
   procedure Get_Bucket_Metrics_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove one query-keyed metrics document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Result Storage outcome
   procedure Delete_Bucket_Metrics_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Result     : out Status);

   --  Transactionally replace one query-keyed intelligent-tiering document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Canonical intelligent-tiering XML bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Intelligent_Tiering_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Result     : out Status);

   --  Read one query-keyed intelligent-tiering document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Retained canonical XML bytes
   --  @param Configured Whether the selected configuration exists
   --  @param Result Storage outcome
   procedure Get_Bucket_Intelligent_Tiering_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove one query-keyed intelligent-tiering document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Result Storage outcome
   procedure Delete_Bucket_Intelligent_Tiering_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Result     : out Status);

   --  Transactionally replace one query-keyed inventory document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Canonical inventory XML bytes
   --  @param Result Storage outcome
   procedure Put_Bucket_Inventory_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Result     : out Status);

   --  Read one query-keyed inventory document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Document Retained canonical XML bytes
   --  @param Configured Whether the selected configuration exists
   --  @param Result Storage outcome
   procedure Get_Bucket_Inventory_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   --  Transactionally remove one query-keyed inventory document.
   --  @param Item Open catalog
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request-query identifier
   --  @param Result Storage outcome
   procedure Delete_Bucket_Inventory_Configuration
     (Item       : in out Catalog;
      Bucket     : String;
      Identifier : String;
      Result     : out Status);

   procedure Put_Bucket_Public_Access_Block
     (Item          : in out Catalog;
      Bucket        : String;
      Configuration : Bucket_Public_Access_Block_Configuration;
      Result        : out Status);

   procedure Get_Bucket_Public_Access_Block
     (Item          : in out Catalog;
      Bucket        : String;
      Configuration : out Bucket_Public_Access_Block_Configuration;
      Configured    : out Boolean;
      Result        : out Status);

   procedure Delete_Bucket_Public_Access_Block
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   procedure Put_Bucket_Policy
     (Item   : in out Catalog;
      Bucket : String;
      Policy : String;
      Result : out Status);

   procedure Get_Bucket_Policy
     (Item       : in out Catalog;
      Bucket     : String;
      Policy     : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status);

   procedure Delete_Bucket_Policy
     (Item   : in out Catalog;
      Bucket : String;
      Result : out Status);

   --  Commit object state, retained-generation state, and Identity in one
   --  transaction. Identity has its default value on every non-success path.
   --  @param Item Catalog transaction owner
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Payload Immutable external payload identifier
   --  @param Info Metadata committed and assigned its version on success
   --  @param Tags Complete object tag set
   --  @param Previous_Payload Replaced payload eligible for reclamation
   --  @param Identity Omitted, opaque, or null publication identity
   --  @param Result Publication result
   --  @param Conditions Atomic destination ETag predicates
   procedure Put_Object
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Payload          : String;
      Info             : in out Object_Information;
      Tags             : Object_Tag_Set;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Identity         : out Backends.Version_Identity;
      Result           : out Status;
      Conditions       : Write_Conditions := Default_Write_Conditions);

   --  Compatibility form when the publication identity is not needed.
   --  @param Item Catalog transaction owner
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Payload Immutable external payload identifier
   --  @param Info Metadata committed and assigned its version on success
   --  @param Tags Complete object tag set
   --  @param Previous_Payload Replaced payload eligible for reclamation
   --  @param Result Publication result
   --  @param Conditions Atomic destination ETag predicates
   procedure Put_Object
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Payload          : String;
      Info             : in out Object_Information;
      Tags             : Object_Tag_Set;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result           : out Status;
      Conditions       : Write_Conditions := Default_Write_Conditions);

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Info    : out Object_Information;
      Result  : out Status;
      Check   : access procedure
        (Payload : String; Info : Object_Information) := null);
   --  When present, Check runs after a successful lookup while the catalog
   --  operation gate is still held. It may validate the immutable external
   --  payload before a concurrent publication retires the previous file.

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Info    : out Object_Information;
      Tags    : out Object_Tag_Set;
      Result  : out Status;
      Check   : access procedure
        (Payload : String;
         Info    : Object_Information;
         Tags    : Object_Tag_Set) := null);
   --  Return tags from the same protected catalog snapshot as Info. When
   --  present, Check runs while that snapshot and external payload lifetime
   --  remain protected by the catalog operation gate.

   --  Select one retained data generation from an atomic catalog snapshot.
   --  Delete markers are reported as absent object data.
   --  @param Item Open catalog
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Selector Current, null, or exact retained generation
   --  @param Payload Immutable external payload name
   --  @param Info Metadata bound to the selected payload
   --  @param Result Operation status
   --  @param Check Optional payload validation while the gate is held
   procedure Find_Selected_Object
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Selector : Backends.Version_Selector;
      Payload  : out Ada.Strings.Unbounded.Unbounded_String;
      Info     : out Object_Information;
      Result   : out Status;
      Check    : access procedure
        (Payload : String; Info : Object_Information) := null);

   --  Select body, metadata, tags, and version identity from one protected
   --  retained-generation snapshot.
   --  @param Item Open catalog
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Selector Current, null, or exact retained generation
   --  @param Payload Immutable external payload name
   --  @param Info Metadata bound to the selected payload
   --  @param Tags Tags bound to the selected generation
   --  @param Identity Selected generation identity
   --  @param Result Operation status
   --  @param Check Optional payload validation while the gate is held
   procedure Find_Selected_Object
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Selector : Backends.Version_Selector;
      Payload  : out Ada.Strings.Unbounded.Unbounded_String;
      Info     : out Object_Information;
      Tags     : out Object_Tag_Set;
      Identity : out Backends.Version_Identity;
      Result   : out Status;
      Check    : access procedure
        (Payload : String;
         Info    : Object_Information;
         Tags    : Object_Tag_Set) := null);

   procedure Get_Object_Attributes
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Selector : Backends.Version_Selector;
      Options  : Backends.Object_Attribute_Options;
      Conditions : Backends.Read_Conditions;
      Check    : not null access procedure;
      Snapshot : out Backends.Object_Attribute_Snapshot;
      Result   : out Status);

   package Payload_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");
   subtype Payloads is Payload_Vectors.Vector;

   --  Delete one ordered batch in a single SQLite transaction. Retired
   --  payload names become unreferenced only after the transaction commits.
   --  @param Modified Shared commit timestamp for newly published markers
   procedure Delete_Objects
     (Item     : in out Catalog;
      Bucket   : String;
      Entries  : Backends.Delete_Object_Entries;
      Requirements : Backends.Delete_Objects_Requirements;
      Modified : Unix_Time;
      Retired  : out Payloads;
      Outcomes : out Backends.Delete_Object_Outcomes;
      Result   : out Status);

   --  Remove one selected generation or publish the versioning-mode marker.
   --  @param Item Open catalog
   --  @param Bucket Bucket containing the key
   --  @param Key Exact object key
   --  @param Selector Current, null, or exact generation selection
   --  @param Conditions Atomic object deletion predicates
   --  @param MFA_Validated Caller authorization attestation for MFA Delete
   --  @param Modified Commit timestamp for a newly published marker
   --  @param Retired_Payload Payload made unreachable by this transaction
   --  @param Outcome Exact generation-aware deletion effect
   --  @param Result Operation status
   procedure Delete_Selected_Object
     (Item            : in out Catalog;
      Bucket          : String;
      Key             : String;
      Selector        : Backends.Version_Selector;
      Conditions      : Backends.Delete_Object_Conditions;
      MFA_Validated   : Boolean;
      Modified        : Unix_Time;
      Retired_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Outcome         : out Backends.Version_Delete_Outcome;
      Result          : out Status);

   --  Replace tags and return the selected generation from one transaction.
   procedure Put_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : Object_Tag_Set; Identity : out Backends.Version_Identity;
      Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Compatibility form when the selected identity is not needed.
   procedure Put_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : Object_Tag_Set; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Read tags and identity from one serialized catalog snapshot.
   procedure Get_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : out Object_Tag_Set; Identity : out Backends.Version_Identity;
      Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Compatibility form when the selected identity is not needed.
   procedure Get_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : out Object_Tag_Set; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Clear tags and return the selected generation from one transaction.
   procedure Delete_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Identity : out Backends.Version_Identity; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   --  Compatibility form when the selected identity is not needed.
   procedure Delete_Object_Tags
     (Item : in out Catalog; Bucket, Key : String; Result : out Status;
      Selector : Backends.Version_Selector :=
        Backends.Current_Version_Selector);

   procedure List_Objects
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Options;
      Check   : not null access procedure;
      Page    : out Backends.List_Page;
      Result  : out Status);

   --  Return one bounded retained-generation page from the catalog snapshot.
   --  @param Item Open catalog
   --  @param Bucket Bucket whose generations are listed
   --  @param Options Prefix, delimiter, paired cursor, and page bound
   --  @param Check Cancellation/deadline check run while the gate is held
   --  @param Page Ordered versions, delete markers, and common prefixes
   --  @param Result Operation status
   procedure List_Object_Versions
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Versions_Options;
      Check   : not null access procedure;
      Page    : out Backends.List_Versions_Page;
      Result  : out Status);

   function Payload_Referenced
     (Item : in out Catalog; Payload : String) return Boolean;

   type Multipart_Part_Record is record
      Number  : Backends.Multipart_Part_Number :=
        Backends.Multipart_Part_Number'First;
      Payload : Ada.Strings.Unbounded.Unbounded_String;
      Info    : Object_Information;
   end record;

   package Multipart_Part_Record_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Multipart_Part_Record);
   subtype Multipart_Part_Records is Multipart_Part_Record_Vectors.Vector;

   procedure Create_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Options      : Backends.Multipart_Options;
      Created      : Unix_Time;
      Result       : out Status);

   procedure Find_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Options      : out Backends.Multipart_Options;
      Result       : out Status);

   procedure Put_Multipart_Part
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Part_Number      : Backends.Multipart_Part_Number;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result           : out Status);

   procedure List_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : Backends.List_Multipart_Parts_Options;
      Page      : out Backends.Multipart_Part_Page;
      Result    : out Status);

   procedure List_Multipart_Uploads
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Multipart_Uploads_Options;
      Check   : not null access procedure;
      Page    : out Backends.Multipart_Upload_Page;
      Result  : out Status);

   procedure Read_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Backends.Multipart_Part_References;
      Records   : out Multipart_Part_Records;
      Result    : out Status);

   procedure Complete_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Selected         : Multipart_Part_Records;
      Payload          : String;
      Info             : in out Object_Information;
      Conditions       : Write_Conditions;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Retired_Payloads : out Payloads;
      Result           : out Status);

   procedure Abort_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Conditions       : Backends.Abort_Multipart_Conditions;
      Retired_Payloads : out Payloads;
      Result           : out Status);

private
   protected type Operation_Gate is
      entry Acquire;
      procedure Release;
   private
      Held : Boolean := False;
   end Operation_Gate;

   type Catalog is limited record
      Database : Flyology.Object_Storage.SQLite.Databases.Database;
      Gate     : Operation_Gate;
   end record;

end Flyology.Object_Storage.SQLite.Catalogs;
