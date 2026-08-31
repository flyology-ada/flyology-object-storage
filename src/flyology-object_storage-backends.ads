with Ada.Containers.Vectors;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Streams;
with Flyology.Cancellation;
with Flyology.Object_Storage.Tags;

--  Defines the HTTP-independent streaming contract implemented by storage
--  backends. Calls are synchronous and may be made from either Flyology lane.
package Flyology.Object_Storage.Backends is

   --  Bounded, HTTP-independent object-listing values.
   subtype List_Limit is Natural range 0 .. 1_000;

   type List_Options is record
      Prefix    : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter : Ada.Strings.Unbounded.Unbounded_String;
      After     : Ada.Strings.Unbounded.Unbounded_String;
      Maximum   : List_Limit := List_Limit'Last;
   end record;

   type Listed_Object is record
      Key  : Ada.Strings.Unbounded.Unbounded_String;
      Info : Object_Information;
   end record;

   package Listed_Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Object);

   package Common_Prefix_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");

   type List_Page is record
      Objects         : Listed_Object_Vectors.Vector;
      Common_Prefixes : Common_Prefix_Vectors.Vector;
      Is_Truncated    : Boolean := False;
      --  Internal lexical cursor; the S3 boundary encodes it opaquely.
      Next_After      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  AWS defines object-version identifiers as opaque, URL-ready UTF-8
   --  strings no longer than 1,024 bytes.  The storage boundary keeps that
   --  externally fixed limit even though Flyology-generated identifiers use
   --  a smaller private representation.
   Maximum_Version_ID_Length : constant := 1_024;

   --  Kind of retained generation selected by a read or metadata operation.
   --  @enum Current_Version Select the newest visible non-delete generation
   --  @enum Null_Version Select the distinguished S3 null generation
   --  @enum Exact_Version Select one generated opaque version identifier
   type Version_Selector_Kind is
     (Current_Version, Null_Version, Exact_Version);

   --  Select the current generation, the distinguished S3 null generation,
   --  or one exact non-null opaque version.  Keeping Null_Version distinct
   --  prevents protocol adapters from leaking the wire literal "null" into
   --  backend lookup policy.
   --  @field Kind Selection mode
   --  @field ID Exact opaque ID only when Kind is Exact_Version
   type Version_Selector is record
      Kind : Version_Selector_Kind := Current_Version;
      ID   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Canonical selector for the newest visible generation.
   Current_Version_Selector : constant Version_Selector;
   --  Canonical selector for the distinguished null generation.
   Null_Version_Selector    : constant Version_Selector;

   --  Check selector structure and the externally fixed version-ID bound.
   --  @param Selector Candidate selector
   --  @return True only for a canonical current, null, or exact selector
   function Valid_Version_Selector
     (Selector : Version_Selector) return Boolean;

   --  Version identity selected by one atomic metadata operation.  On
   --  Success, a present null identity is kept distinct from an omitted
   --  identity so protocol adapters can emit S3's `null` sentinel only when
   --  it is authoritative.  Non-success outcomes return the default record.
   --  A present non-null identity has a nonempty Version_ID; all other forms
   --  have an empty Version_ID.
   --  @field Has_Version_ID Whether the selected object exposes an identity
   --  @field Is_Null_Version Whether that identity is the distinguished null
   --  @field Version_ID Opaque non-null identity when present and non-null
   type Version_Identity is record
      Has_Version_ID  : Boolean := False;
      Is_Null_Version : Boolean := False;
      Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One retained object generation or delete marker in listing order.
   --  @field Key Exact object key
   --  @field Version_ID Opaque identifier or the S3 value `null`
   --  @field Info Immutable metadata for this generation
   --  @field Is_Latest Whether this is the newest retained generation
   --  @field Is_Delete_Marker Whether the entry has no object body
   type Listed_Version is record
      Key              : Ada.Strings.Unbounded.Unbounded_String;
      Version_ID       : Ada.Strings.Unbounded.Unbounded_String;
      Info             : Object_Information;
      Is_Latest        : Boolean := False;
      Is_Delete_Marker : Boolean := False;
   end record;

   --  Bounded by backend capacity before exposure in a page.
   package Listed_Version_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Version);

   --  HTTP-independent ListObjectVersions selection and paired cursor.
   --  @field Prefix Required bytewise key prefix
   --  @field Delimiter Optional common-prefix delimiter
   --  @field Has_Key_Marker Whether Key_Marker was supplied
   --  @field Key_Marker Key component of the exclusive cursor
   --  @field Has_Version_ID_Marker Whether Version_ID_Marker was supplied
   --  @field Version_ID_Marker Version component of the exclusive cursor
   --  @field Maximum Combined version, marker, and prefix page bound
   type List_Versions_Options is record
      Prefix                : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Key_Marker        : Boolean := False;
      Key_Marker            : Ada.Strings.Unbounded.Unbounded_String;
      Has_Version_ID_Marker : Boolean := False;
      Version_ID_Marker     : Ada.Strings.Unbounded.Unbounded_String;
      Maximum               : List_Limit := List_Limit'Last;
   end record;

   --  One bounded retained-generation page from an atomic backend snapshot.
   --  @field Entries Ordered object versions and delete markers
   --  @field Common_Prefixes Ordered delimiter projections
   --  @field Is_Truncated Whether additional results remain
   --  @field Next_Key_Marker Key component for the next request
   --  @field Next_Version_ID_Marker Version component for the next request
   type List_Versions_Page is record
      Entries                : Listed_Version_Vectors.Vector;
      Common_Prefixes        : Common_Prefix_Vectors.Vector;
      Is_Truncated           : Boolean := False;
      Next_Key_Marker        : Ada.Strings.Unbounded.Unbounded_String;
      Next_Version_ID_Marker : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Account-level bucket listing is independently bounded by the pinned S3
   --  MaxBuckets range. After is an exclusive internal lexical cursor; the
   --  S3 boundary is responsible for opaque continuation tokens.
   subtype Bucket_List_Limit is Positive range 1 .. 10_000;

   type List_Buckets_Options is record
      Prefix  : Ada.Strings.Unbounded.Unbounded_String;
      After   : Ada.Strings.Unbounded.Unbounded_String;
      Maximum : Bucket_List_Limit := Bucket_List_Limit'Last;
   end record;

   type Listed_Bucket is record
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Created : Unix_Time := 0;
   end record;

   package Listed_Bucket_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Bucket);

   type Bucket_Page is record
      Buckets      : Listed_Bucket_Vectors.Vector;
      Is_Truncated : Boolean := False;
      Next_After   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence of a signed source-condition timestamp. The S3 boundary parses
   --  HTTP dates before crossing this HTTP-independent contract.
   type Optional_Copy_Condition_Time (Is_Set : Boolean := False) is record
      case Is_Set is
         when True =>
            Value : Long_Long_Integer;
         when False =>
            null;
      end case;
   end record;

   --  CopyObject source validators evaluated against the exact immutable
   --  metadata snapshot whose bytes are copied.
   type Copy_Conditions is record
      If_Match             : Ada.Strings.Unbounded.Unbounded_String;
      If_Modified_Since    : Optional_Copy_Condition_Time;
      If_None_Match        : Ada.Strings.Unbounded.Unbounded_String;
      If_Unmodified_Since  : Optional_Copy_Condition_Time;
   end record;

   Default_Copy_Conditions : constant Copy_Conditions;

   --  Return whether every supplied CopyObject entity-tag field is a
   --  bounded canonical HTTP entity-tag list. Date fields are already typed.
   function Valid_Copy_Conditions
     (Conditions : Copy_Conditions) return Boolean;

   type Copy_Metadata_Directive is (Copy_Metadata, Replace_Metadata);
   type Copy_Tagging_Directive is (Copy_Tags, Replace_Tags);

   --  HTTP-independent atomic copy policy.
   --  @field Source_Selector Current, null, or exact source generation
   --  @field Metadata_Directive Copy or replace source metadata
   --  @field Content_Type Replacement content type
   --  @field Metadata Replacement system and user metadata
   --  @field Tagging_Directive Copy or replace source tags
   --  @field Tags Replacement tag set
   --  @field Selected_Checksum Destination full-object checksum algorithm
   --  @field Conditions Predicates on the selected source snapshot
   --  @field Destination_Conditions Atomic destination ETag predicates
   type Copy_Options is record
      Source_Selector    : Version_Selector := Current_Version_Selector;
      Metadata_Directive : Copy_Metadata_Directive := Copy_Metadata;
      Content_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Metadata           : Object_Metadata;
      Tagging_Directive  : Copy_Tagging_Directive := Copy_Tags;
      Tags               : Object_Tag_Set;
      Selected_Checksum  : Checksum_Algorithm := No_Checksum;
      Conditions         : Copy_Conditions;
      Destination_Conditions : Write_Conditions;
   end record;

   Default_Copy_Options : constant Copy_Options;

   --  Evaluate all source conditions against an exact object snapshot.
   --  Malformed entity-tag lists are Invalid_Request; every false predicate
   --  is Precondition_Failed.
   function Evaluate_Copy_Conditions
     (Conditions : Copy_Conditions;
      Entity_Tag : String;
      Modified   : Unix_Time) return Status;

   --  Evaluate If-Match and If-None-Match for an atomic object publication.
   --  A missing destination never satisfies If-Match and always satisfies a
   --  syntactically valid If-None-Match. Failures are Precondition_Failed;
   --  malformed entity-tag lists are Invalid_Request.
   function Evaluate_Write_Conditions
     (Conditions : Write_Conditions;
      Exists     : Boolean;
      Entity_Tag : String) return Status;

   --  Return whether every supplied destination entity-tag predicate is a
   --  bounded canonical HTTP entity-tag list.
   function Valid_Write_Conditions
     (Conditions : Write_Conditions) return Boolean;

   --  HTTP-independent predicates for one DeleteObjects entry. The protocol
   --  adapter parses Last_Modified_Time before crossing this boundary.
   type Delete_Object_Conditions is record
      Has_ETag               : Boolean := False;
      ETag                   : Ada.Strings.Unbounded.Unbounded_String;
      Has_Last_Modified_Time : Boolean := False;
      Last_Modified_Time     : Long_Long_Integer := 0;
      Has_Size               : Boolean := False;
      Size                   : Byte_Count := 0;
   end record;

   No_Delete_Object_Conditions : constant Delete_Object_Conditions;

   --  Evaluate one entry against an exact catalog snapshot.
   function Evaluate_Delete_Object_Conditions
     (Conditions : Delete_Object_Conditions;
      Exists     : Boolean;
      Info       : Object_Information) return Status;

   Maximum_Delete_Objects : constant := 1_000;

   --  Catalog predicates that must remain true through batch publication.
   --  Require_Unversioned rejects a bucket whose versioning status is no
   --  longer Unconfigured, or whose MFA Delete status is Enabled.
   --  MFA_Validated carries the same caller authorization attestation as the
   --  single generation-aware delete primitive.
   type Delete_Objects_Requirements is record
      Require_Unversioned : Boolean := False;
      MFA_Validated       : Boolean := False;
   end record;

   --  One ordered generation-aware batch deletion request.
   --  @field Key Exact object key
   --  @field Selector Current, null, or exact generation target
   --  @field Conditions Predicates evaluated against the selected generation
   type Delete_Object_Entry is record
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      --  Preserve the established VersionId-absent batch behavior: callers
      --  that do not select a generation continue to target Current.
      Selector   : Version_Selector :=
        (Kind => Current_Version,
         ID   => Ada.Strings.Unbounded.Null_Unbounded_String);
      Conditions : Delete_Object_Conditions;
   end record;

   package Delete_Object_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Delete_Object_Entry);
   subtype Delete_Object_Entries is Delete_Object_Entry_Vectors.Vector;

   --  Publication effect of one generation-aware deletion.
   --  @enum No_Version_Removed The selected generation did not exist
   --  @enum Object_Version_Removed One retained payload generation was removed
   --  @enum Delete_Marker_Created A simple versioned delete published a marker
   --  @enum Delete_Marker_Removed One exact retained marker was removed
   type Version_Delete_Kind is
     (No_Version_Removed,
      Object_Version_Removed,
      Delete_Marker_Created,
      Delete_Marker_Removed);

   --  Exact result of one generation-aware delete publication.  Null version
   --  identity remains typed and never uses the S3 wire spelling `null`.
   --  @field Kind Publication effect
   --  @field Has_Version_ID Whether the response identifies a generation
   --  @field Is_Null_Version Whether that identity is the distinguished null
   --  @field Version_ID Opaque non-null identity when present and non-null
   type Version_Delete_Outcome is record
      Kind            : Version_Delete_Kind := No_Version_Removed;
      Has_Version_ID  : Boolean := False;
      Is_Null_Version : Boolean := False;
      Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Ordered result of one generation-aware batch entry.
   --  Publication is populated only when Result is Success.
   --  @field Result Storage-domain outcome for this entry
   --  @field Publication Exact generation or marker effect on success
   type Delete_Object_Outcome is record
      Result      : Status := Backend_Unavailable;
      Publication : Version_Delete_Outcome;
   end record;

   package Delete_Object_Outcome_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Delete_Object_Outcome);
   subtype Delete_Object_Outcomes is Delete_Object_Outcome_Vectors.Vector;

   --  Conditional-read timestamps are signed so valid HTTP dates before the
   --  Unix epoch can be compared without lossy clamping.
   type Optional_Condition_Time (Is_Set : Boolean := False) is record
      case Is_Set is
         when True =>
            Value : Long_Long_Integer;
         when False =>
            null;
      end case;
   end record;

   --  Validators evaluated against the exact immutable snapshot streamed by
   --  Get_Object. Entity-tag values use HTTP list syntax. If-Match takes
   --  precedence over If-Unmodified-Since, and If-None-Match takes precedence
   --  over If-Modified-Since, matching S3 conditional-read behavior.
   type Read_Conditions is record
      If_Match           : Ada.Strings.Unbounded.Unbounded_String;
      If_Modified_Since  : Optional_Condition_Time;
      If_None_Match      : Ada.Strings.Unbounded.Unbounded_String;
      If_Unmodified_Since : Optional_Condition_Time;
   end record;

   Default_Read_Conditions : constant Read_Conditions;

   --  Validate one If-Match or If-None-Match field value. Weak tags are valid
   --  syntax; they never satisfy If-Match and do satisfy If-None-Match by weak
   --  comparison. Bare, empty, mixed-wildcard, and malformed lists are
   --  invalid.
   function Valid_Read_Entity_Tag_Condition
     (Value : String) return Boolean;

   --  Return only Success, Precondition_Failed, Not_Modified, or
   --  Invalid_Request. Entity_Tag is the stored unquoted opaque tag.
   function Evaluate_Read_Conditions
     (Conditions : Read_Conditions;
      Entity_Tag : String;
      Modified   : Unix_Time) return Status;

   --  Presence of an exact source length.
   type Length_Kind is (Unknown, Known);

   --  Type-safe declared body length.
   type Source_Length (Kind : Length_Kind := Unknown) is record
      case Kind is
         when Unknown =>
            null;
         when Known =>
            Bytes : Byte_Count;
      end case;
   end record;

   --  Pull source for one object body. A call must produce bytes or finish.
   type Byte_Source is limited interface;

   --  Declared source length.
   function Declared_Length
     (Item : Byte_Source) return Source_Length is abstract;

   --  Produce the next source bytes.
   procedure Read
     (Item     : in out Byte_Source;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Finished : out Boolean;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time) is abstract;

   --  Push sink for a streamed object body.
   type Byte_Sink is limited interface;

   --  Announce the immutable object snapshot and resolved response interval.
   --  Backends call this exactly once after all validation succeeds and before
   --  the first Write, including for an empty object.  Partial is true when
   --  the caller supplied a range rather than requesting the whole object.
   procedure Begin_Object
     (Item           : in out Byte_Sink;
      Info           : Object_Information;
      First          : Byte_Count;
      Content_Length : Byte_Count;
      Partial        : Boolean;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time) is abstract;

   --  Consume one nonempty body fragment.
   procedure Write
     (Item     : in out Byte_Sink;
      Data     : Ada.Streams.Stream_Element_Array;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time) is abstract;

   --  Pluggable object storage contract.
   type Backend is limited interface;

   subtype Multipart_Part_Number is Positive range 1 .. 10_000;

   --  Maximum source size accepted by one atomic S3 CopyObject request.
   Maximum_Copy_Object_Size : constant Byte_Count :=
     5 * 1_024 * 1_024 * 1_024;

   --  Check the AWS binary 5 GiB single-copy boundary without reading the
   --  source body.
   function Valid_Copy_Object_Size (Size : Byte_Count) return Boolean is
     (Size <= Maximum_Copy_Object_Size);

   Maximum_Multipart_Part_Size : constant Byte_Count :=
     5 * 1_024 * 1_024 * 1_024;

   type Multipart_Options is record
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
      Checksum     : Checksum_Information;
   end record;

   Default_Multipart_Options : constant Multipart_Options;

   --  Predicates and exact assembled size checked in the same publication
   --  boundary that replaces the destination and retires the upload.
   type Complete_Multipart_Options is record
      Conditions    : Write_Conditions;
      Expected_Size : Source_Length;
      Expected_Checksum : Checksum_Information;
   end record;

   Default_Complete_Multipart_Options : constant Complete_Multipart_Options;

   --  Atomic predicates for retiring an active multipart upload. The
   --  initiation time is compared with the upload record under the same
   --  publication boundary that removes its parts.
   type Abort_Multipart_Conditions is record
      Has_Initiated_Time : Boolean := False;
      Initiated_Time     : Unix_Time := 0;
   end record;

   No_Abort_Multipart_Conditions : constant Abort_Multipart_Conditions;

   type Multipart_Part_Reference is record
      Number     : Multipart_Part_Number := Multipart_Part_Number'First;
      Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
      Checksum   : Checksum_Information;
   end record;

   --  Optional caller-supplied digest for one staged part. The backend always
   --  computes and stores the upload's selected checksum before publication.
   type Multipart_Part_Options is record
      Expected_Checksum : Checksum_Information;
   end record;

   Default_Multipart_Part_Options : constant Multipart_Part_Options;

   package Multipart_Part_Reference_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Multipart_Part_Reference);

   subtype Multipart_Part_References is
     Multipart_Part_Reference_Vectors.Vector;

   subtype Multipart_Part_Marker is
     Natural range 0 .. Multipart_Part_Number'Last;

   type List_Multipart_Parts_Options is record
      After   : Multipart_Part_Marker := 0;
      Maximum : List_Limit := List_Limit'Last;
   end record;

   type Listed_Multipart_Part is record
      Number : Multipart_Part_Number := Multipart_Part_Number'First;
      Info   : Object_Information;
   end record;

   package Listed_Multipart_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Multipart_Part);

   type Multipart_Part_Page is record
      Parts        : Listed_Multipart_Part_Vectors.Vector;
      Is_Truncated : Boolean := False;
      Next_After   : Multipart_Part_Marker := 0;
      Checksum     : Checksum_Information;
   end record;

   --  Completed multipart metadata retained with a committed object. The
   --  values are HTTP-independent and refer to the exact immutable object
   --  generation described by Object_Attribute_Snapshot.Info.
   type Completed_Object_Part is record
      Number : Multipart_Part_Number := Multipart_Part_Number'First;
      Size   : Byte_Count := 0;
      Checksum : Checksum_Information;
   end record;

   package Completed_Object_Part_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Completed_Object_Part);

   subtype Completed_Object_Part_List is
     Completed_Object_Part_Vectors.Vector;

   type Object_Attribute_Options is record
      After   : Multipart_Part_Marker := 0;
      Maximum : List_Limit := List_Limit'Last;
   end record;

   type Object_Attribute_Snapshot is record
      Info         : Object_Information;
      Is_Multipart : Boolean := False;
      Total_Parts  : Natural range 0 .. Multipart_Part_Number'Last := 0;
      Parts        : Completed_Object_Part_List;
      Is_Truncated : Boolean := False;
      Next_After   : Multipart_Part_Marker := 0;
   end record;

   --  Exclusive S3 marker pair for active-upload listing.  Upload_ID may be
   --  empty to skip every upload whose key equals Key.
   type Multipart_Upload_Marker is record
      Key       : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type List_Multipart_Uploads_Options is record
      Prefix    : Ada.Strings.Unbounded.Unbounded_String;
      Delimiter : Ada.Strings.Unbounded.Unbounded_String;
      After     : Multipart_Upload_Marker;
      Maximum   : List_Limit := List_Limit'Last;
   end record;

   type Listed_Multipart_Upload is record
      Key       : Ada.Strings.Unbounded.Unbounded_String;
      Upload_ID : Ada.Strings.Unbounded.Unbounded_String;
      Initiated : Unix_Time := 0;
      Options   : Multipart_Options;
   end record;

   package Listed_Multipart_Upload_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Listed_Multipart_Upload);

   type Multipart_Upload_Page is record
      Uploads         : Listed_Multipart_Upload_Vectors.Vector;
      Common_Prefixes : Common_Prefix_Vectors.Vector;
      Is_Truncated    : Boolean := False;
      Next_After      : Multipart_Upload_Marker;
   end record;

   procedure Create_Bucket
     (Item   : in out Backend;
      Bucket : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status) is abstract;

   procedure List_Buckets
     (Item     : in out Backend;
      Options  : List_Buckets_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out Bucket_Page;
      Result   : out Status) is abstract;

   procedure Head_Bucket
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Atomically apply one bucket's versioning configuration. Unconfigured
   --  fields are left unchanged, allowing status and MFA-delete policy to be
   --  changed independently. Qualified version-aware backends apply the new
   --  status to subsequent object mutations without rewriting retained
   --  generations. MFA_Validated is a fail-closed attestation
   --  from the caller's authorization policy. False rejects any MFA-delete
   --  change and every status change while current MFA Delete is enabled;
   --  the check and configuration publication are one atomic boundary.
   procedure Put_Bucket_Versioning
     (Item          : in out Backend;
      Bucket        : String;
      Configuration : Bucket_Versioning_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status;
      MFA_Validated : Boolean := False) is abstract;

   --  Return one atomic configuration snapshot. A newly created bucket
   --  returns both fields Unconfigured.
   procedure Get_Bucket_Versioning
     (Item          : in out Backend;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status) is abstract;

   --  Atomically replace the ABAC state of an existing bucket.
   --  @param Item Backend that owns the bucket
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving ABAC state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   procedure Put_Bucket_ABAC
     (Item     : in out Backend;
      Bucket   : String;
      Value    : Bucket_ABAC_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic ABAC snapshot. Newly created buckets are disabled.
   --  @param Item Backend that owns the bucket
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete presence-preserving ABAC snapshot
   --  @param Result Storage outcome
   procedure Get_Bucket_ABAC
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_ABAC_Status;
      Result   : out Status) is abstract;

   --  Atomically replace the transfer-acceleration state of an existing
   --  bucket.
   --  @param Item Backend that owns the bucket
   --  @param Bucket Existing bucket name
   --  @param Value Complete presence-preserving acceleration state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   procedure Put_Bucket_Acceleration
     (Item     : in out Backend;
      Bucket   : String;
      Value    : Bucket_Acceleration_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic acceleration snapshot, retaining Unconfigured as
   --  distinct from Suspended.
   --  @param Item Backend that owns the bucket
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete presence-preserving acceleration snapshot
   --  @param Result Storage outcome
   procedure Get_Bucket_Acceleration
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Acceleration_Status;
      Result   : out Status) is abstract;

   --  Atomically replace the request-payment state of an existing bucket.
   --  @param Item Backend that owns the bucket
   --  @param Bucket Existing bucket name
   --  @param Value Complete request-payment state
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage outcome
   procedure Put_Bucket_Request_Payment
     (Item     : in out Backend;
      Bucket   : String;
      Value    : Bucket_Request_Payment_Status;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic request-payment snapshot. Newly created buckets use
   --  bucket-owner payment.
   --  @param Item Backend that owns the bucket
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Value Complete request-payment snapshot
   --  @param Result Storage outcome
   procedure Get_Bucket_Request_Payment
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Bucket_Request_Payment_Status;
      Result   : out Status) is abstract;

   procedure Delete_Bucket
     (Item   : in out Backend;
      Bucket : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status) is abstract;

   --  Atomically replace the complete tag set of an existing bucket.
   procedure Put_Bucket_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Value    : Tags.Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic tag-set snapshot. Tag_Set_Not_Found distinguishes an
   --  existing untagged bucket from an absent bucket.
   procedure Get_Bucket_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Tags.Tag_Set;
      Result   : out Status) is abstract;

   --  Atomically remove the complete tag set of an existing bucket. This is
   --  idempotent for an existing untagged bucket; an absent bucket remains
   --  Not_Found.
   procedure Delete_Bucket_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Check the shared persistence bound for one canonical CORS document.
   --  XML parsing and semantic validation remain above this HTTP-independent
   --  boundary; every admitted document has already been normalized by the
   --  S3 adapter.
   --  @param Document Exact canonical CORSConfiguration bytes
   --  @return True when every backend can retain the document
   function Valid_Bucket_CORS_Document (Document : String) return Boolean;

   --  Check the shared persistence bound for one canonical bucket-encryption
   --  document. XML parsing and semantic validation remain at the S3 boundary.
   --  @param Document Exact canonical encryption-configuration bytes
   --  @return True when every backend can retain the document
   function Valid_Bucket_Encryption_Document
     (Document : String) return Boolean;

   --  Check the shared persistence bound for one canonical ownership-controls
   --  document. XML parsing and semantic validation remain at the S3 boundary.
   --  @param Document Exact canonical ownership-controls bytes
   --  @return True when every backend can retain the document
   function Valid_Bucket_Ownership_Controls_Document
     (Document : String) return Boolean;

   --  Check the shared persistence bound for one canonical lifecycle
   --  document. XML parsing and semantic validation remain at the S3 boundary.
   --  @param Document Exact canonical lifecycle-configuration bytes
   --  @return True when every backend can retain the document
   function Valid_Bucket_Lifecycle_Document
     (Document : String) return Boolean;

   --  Check the shared persistence bound for one canonical lifecycle
   --  document and its exact optional response-header value.
   --  @param Document Exact canonical lifecycle-configuration bytes
   --  @param Transition_Default_Minimum_Object_Size Exact optional response
   --  header value, or the empty string when absent
   --  @return True when every backend can retain the complete state
   function Valid_Bucket_Lifecycle_Document
     (Document : String;
      Transition_Default_Minimum_Object_Size : String) return Boolean;

   --  Check the shared persistence bound for one canonical logging document.
   --  XML parsing and semantic validation remain at the S3 boundary.
   --  @param Document Exact canonical logging-status bytes
   --  @return True when every backend can retain the document
   function Valid_Bucket_Logging_Document
     (Document : String) return Boolean;

   --  Atomically replace one analytics configuration selected by the exact
   --  request identifier. Identifier and the canonical payload's modeled Id
   --  remain independent; the backend does not execute analytics reports.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Document Validated canonical analytics-configuration bytes
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_Analytics_Configuration
     (Item       : in out Backend;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is abstract;

   --  Return one atomic analytics-configuration snapshot selected by the
   --  exact request identifier.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Configured Whether the selected configuration is retained
   --  @param Result Read result
   procedure Get_Bucket_Analytics_Configuration
     (Item       : in out Backend;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove one analytics configuration. Deletion is idempotent
   --  for an existing bucket without the selected identifier.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Delete_Bucket_Analytics_Configuration
     (Item       : in out Backend;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is abstract;

   --  Atomically replace one request-metrics configuration selected by the
   --  exact request identifier. The backend does not emit CloudWatch metrics.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Document Validated canonical metrics-configuration bytes
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_Metrics_Configuration
     (Item       : in out Backend;
      Bucket     : String;
      Identifier : String;
      Document   : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is abstract;

   --  Return one atomic request-metrics configuration snapshot selected by
   --  the exact request identifier.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Configured Whether the selected configuration is retained
   --  @param Result Read result
   procedure Get_Bucket_Metrics_Configuration
     (Item       : in out Backend;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove one request-metrics configuration. Deletion is
   --  idempotent for an existing bucket without the selected identifier.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Identifier Exact request query identifier
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Delete_Bucket_Metrics_Configuration
     (Item       : in out Backend;
      Bucket     : String;
      Identifier : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Result     : out Status) is abstract;

   --  Atomically replace the complete canonical CORS document of an existing
   --  bucket.  The backend treats Document as bounded opaque bytes and does
   --  not depend on S3 XML or request types.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Document Validated canonical CORSConfiguration bytes
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_CORS
     (Item     : in out Backend;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic canonical CORS-document snapshot. Configured is False
   --  for an existing bucket with no CORS state and is reset together with
   --  Document on every failure.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Configured Whether the existing bucket has a CORS configuration
   --  @param Result Read result
   procedure Get_Bucket_CORS
     (Item       : in out Backend;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove CORS state. Deletion is idempotent for an existing
   --  bucket with no CORS configuration.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Delete_Bucket_CORS
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Atomically replace the complete canonical bucket-encryption document.
   --  The backend treats Document as bounded opaque bytes.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Document Validated canonical encryption-configuration bytes
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_Encryption
     (Item     : in out Backend;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic canonical bucket-encryption override snapshot.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Configured Whether the bucket has a retained encryption override
   --  @param Result Read result
   procedure Get_Bucket_Encryption
     (Item       : in out Backend;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove the retained bucket-encryption override. The S3
   --  boundary maps an absent override to its established SSE-S3 default;
   --  deletion is idempotent when no override is retained.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Delete_Bucket_Encryption
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Atomically replace the complete canonical ownership-controls document.
   --  The backend treats Document as bounded opaque bytes.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Document Validated canonical ownership-controls bytes
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_Ownership_Controls
     (Item     : in out Backend;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic canonical ownership-controls snapshot.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Configured Whether the existing bucket has ownership controls
   --  @param Result Read result
   procedure Get_Bucket_Ownership_Controls
     (Item       : in out Backend;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove ownership-controls state. Deletion is idempotent for
   --  an existing bucket without ownership controls.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Delete_Bucket_Ownership_Controls
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Atomically replace the complete canonical lifecycle document. The
   --  backend retains configuration state but does not execute lifecycle
   --  actions.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Document Validated canonical lifecycle-configuration bytes
   --  @param Transition_Default_Minimum_Object_Size Exact optional response
   --  header value, or the empty string when absent
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_Lifecycle
     (Item     : in out Backend;
      Bucket   : String;
      Document : String;
      Transition_Default_Minimum_Object_Size : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic canonical lifecycle-document snapshot.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Transition_Default_Minimum_Object_Size Exact retained optional
   --  response-header value, or the empty string when absent
   --  @param Configured Whether the existing bucket has lifecycle state
   --  @param Result Read result
   procedure Get_Bucket_Lifecycle
     (Item       : in out Backend;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Transition_Default_Minimum_Object_Size :
        out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove lifecycle state. Deletion is idempotent for an
   --  existing bucket without a lifecycle configuration.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Delete_Bucket_Lifecycle
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Atomically replace the complete canonical logging document. The
   --  backend retains configuration state but does not deliver access logs.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Document Validated canonical logging-status bytes
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Mutation result
   procedure Put_Bucket_Logging
     (Item     : in out Backend;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic canonical logging-document snapshot. Configured is
   --  False for the successful disabled/default state of an existing bucket.
   --  @param Item Backend that owns the bucket configuration
   --  @param Bucket Existing bucket name
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Document Exact retained canonical bytes when configured
   --  @param Configured Whether explicit logging state is retained
   --  @param Result Read result
   procedure Get_Bucket_Logging
     (Item       : in out Backend;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically replace the complete PublicAccessBlock configuration of an
   --  existing bucket.  A configuration whose four members are absent is a
   --  present empty configuration, not a deletion.
   procedure Put_Bucket_Public_Access_Block
     (Item          : in out Backend;
      Bucket        : String;
      Configuration : Bucket_Public_Access_Block_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status) is abstract;

   --  Return one atomic PublicAccessBlock snapshot.  Configured is False for
   --  an existing bucket with no configuration and is also reset on failure.
   procedure Get_Bucket_Public_Access_Block
     (Item          : in out Backend;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Public_Access_Block_Configuration;
      Configured    : out Boolean;
      Result        : out Status) is abstract;

   --  Atomically remove PublicAccessBlock state.  Deletion is idempotent for
   --  an existing unconfigured bucket.
   procedure Delete_Bucket_Public_Access_Block
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Check the repository's established bounded raw bucket-policy contract.
   --  The exact ceiling remains private so the backend API does not create a
   --  caller-visible resource-policy constant.
   --  @param Policy Exact raw policy bytes
   --  @return True when the policy can be persisted by every backend
   function Valid_Bucket_Policy (Policy : String) return Boolean;

   --  Atomically replace the exact raw policy document of an existing bucket.
   --  Policy bytes are opaque at this HTTP-independent boundary; the S3
   --  adapter owns wire admission, while policy interpretation remains a
   --  separate capability.
   procedure Put_Bucket_Policy
     (Item     : in out Backend;
      Bucket   : String;
      Policy   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  Return one atomic raw-policy snapshot. Configured is False for an
   --  existing bucket with no policy and is reset together with Policy on
   --  every failure.
   procedure Get_Bucket_Policy
     (Item       : in out Backend;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Policy     : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is abstract;

   --  Atomically remove bucket-policy state. Deletion is idempotent for an
   --  existing bucket with no policy.
   procedure Delete_Bucket_Policy
     (Item     : in out Backend;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   --  A successful implementation consumes Source through Finished, validates
   --  its declared length, and publishes the object only after all source
   --  validation succeeds. Conditions are evaluated atomically against the
   --  destination generation at publication. No outcome exposes a partial
   --  object. Invalid input, failed predicates, source failure, cancellation,
   --  timeout, and capacity failure before publication leave the prior object
   --  unchanged. Backend_Unavailable is not a publication-certainty signal:
   --  a backend can publish atomically and then fail while confirming durable
   --  metadata. Callers that lose this result must reconcile with one atomic
   --  Get_Object body-and-information snapshot before any conditional retry.
   --  Identity is returned from the same publication boundary as Info. It is
   --  omitted for an unversioned bucket, contains the opaque retained version
   --  for enabled versioning, and represents S3's `null` identity for
   --  suspended versioning. Every non-success outcome returns its default
   --  value.
   --  @param Item Backend that owns the publication boundary
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Source One-shot body source consumed synchronously
   --  @param Options Complete object metadata, tags, and checksum policy
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata of the object generation published on success
   --  @param Identity Version identity published by the same atomic mutation
   --  @param Result Publication result; Backend_Unavailable is ambiguous
   --  @param Conditions Atomic destination ETag predicates
   procedure Put_Object
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Identity : out Version_Identity;
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions) is abstract;

   --  Compatibility convenience when the publication identity is not needed.
   --  This drives the same primitive and discards only its atomic identity.
   --  @param Item Backend that owns the publication boundary
   --  @param Bucket Destination bucket name
   --  @param Key Destination object key
   --  @param Source One-shot body source consumed synchronously
   --  @param Options Complete object metadata, tags, and checksum policy
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata of the object generation published on success
   --  @param Result Publication result; Backend_Unavailable is ambiguous
   --  @param Conditions Atomic destination ETag predicates
   procedure Put_Object
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions);

   --  Copy one immutable source snapshot to the destination. The snapshot
   --  contains the exact body, Object_Information, metadata, and tags from one
   --  source generation; source predicates are evaluated against that same
   --  generation. Source_Bucket_Not_Found and Source_Not_Found remain
   --  distinct, while destination-bucket absence is Not_Found.
   --
   --  Copy_Metadata preserves source Content_Type and metadata except that
   --  Website_Redirect_Location always comes from Options and is therefore
   --  inherited only when explicitly supplied. Replace_Metadata uses the
   --  complete Content_Type and Metadata in Options. Copy_Tags preserves the
   --  source tag set; Replace_Tags uses the complete Options.Tags set.
   --  Selected_Checksum chooses the destination full-object checksum. When it
   --  is No_Checksum, the source algorithm is inherited, or CRC64NVME is used
   --  for an unchecksummed source. A multipart composite value or method is
   --  never transplanted: the destination digest is recomputed over the exact
   --  copied bytes and its method is Full_Object_Checksum.
   --
   --  Destination_Conditions are evaluated in the atomic publication boundary
   --  that publishes the complete body/information/metadata/tags/checksum
   --  tuple. Validation, source-condition failure, source read failure, and
   --  rejection before that boundary leave the prior destination unchanged.
   --  Source_Identity and Destination_Identity are returned only on Success
   --  and describe the selected source snapshot and published destination
   --  generation without a follow-up read. Backend_Unavailable, cancellation,
   --  or timeout after publication may be
   --  ambiguous; callers must not infer nonpublication from those outcomes.
   --  @param Item Backend instance
   --  @param Source_Bucket Source bucket name
   --  @param Source_Key Source object key
   --  @param Destination_Bucket Destination bucket name
   --  @param Destination_Key Destination object key
   --  @param Options Source selection, predicates, metadata, tags, and
   --    checksum
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata of the destination generation published on success
   --  @param Source_Identity Selected source generation on success
   --  @param Destination_Identity Published destination generation on success
   --  @param Result Copy result; Backend_Unavailable may be ambiguous
   procedure Copy_Object
     (Item               : in out Backend;
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
      Result             : out Status) is abstract;

   --  Compatibility convenience when version identities are not needed.
   --  @param Item Backend instance
   --  @param Source_Bucket Source bucket name
   --  @param Source_Key Source object key
   --  @param Destination_Bucket Destination bucket name
   --  @param Destination_Key Destination object key
   --  @param Options Source selection, predicates, metadata, tags, and
   --    checksum
   --  @param Token Optional cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Metadata of the destination generation published on success
   --  @param Result Copy result; Backend_Unavailable may be ambiguous
   procedure Copy_Object
     (Item               : in out Backend'Class;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Copy_Options;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status);

   --  Return one selected immutable metadata snapshot. Conditions are
   --  evaluated against the same snapshot and retained on conditional failure.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Selected metadata snapshot
   --  @param Result Storage-domain outcome
   --  @param Conditions Conditional-read predicates
   --  @param Selector Current, null, or exact generation selection
   procedure Head_Object
     (Item   : in out Backend;
      Bucket : String;
      Key    : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info   : out Object_Information;
      Result : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector) is abstract;

   --  Stream one selected immutable object snapshot through Sink.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Requested Whole or partial byte selection
   --  @param Sink Destination for the selected bytes
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Info Selected metadata snapshot
   --  @param Result Storage-domain outcome
   --  @param Conditions Conditional-read predicates
   --  @param Selector Current, null, or exact generation selection
   procedure Get_Object
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Sink     : in out Byte_Sink'Class;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector) is abstract;
   --  A successful implementation calls Begin_Object exactly once, then
   --  writes exactly its announced Content_Length. When Result is
   --  Invalid_Range, Info is the immutable object snapshot against which
   --  Requested was resolved and no sink callback has occurred.

   --  Return object metadata and a bounded page of retained completed-part
   --  metadata from one atomic object-generation snapshot. Ordinary PUT and
   --  COPY objects report Is_Multipart false and no parts. A successful
   --  multipart completion reports its total selected part count even when
   --  the requested page is empty.
   --  @param Selector Current, null, or exact generation selection
   procedure Get_Object_Attributes
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Options  : Object_Attribute_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Snapshot : out Object_Attribute_Snapshot;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions;
      Selector : Version_Selector := Current_Version_Selector) is abstract;
   --  Conditions are evaluated against Snapshot.Info within the same atomic
   --  metadata boundary used to collect the completed-part snapshot.

   procedure Delete_Object
     (Item   : in out Backend;
      Bucket : String;
      Key    : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status;
      Conditions : Delete_Object_Conditions :=
        No_Delete_Object_Conditions;
      Requirements : Delete_Objects_Requirements := (others => <>))
      is abstract;
   --  Conditions and Requirements are evaluated against the same object and
   --  bucket-versioning snapshot used to publish the deletion. An
   --  unconditioned missing key is an idempotent success; a missing key with
   --  an ETag condition is Not_Found. Require_Unversioned returns
   --  Not_Implemented without mutation once versioning is configured or MFA
   --  Delete is enabled. For a pure-files backend, Backend_Unavailable,
   --  cancellation, timeout, or an exception after unlink is not proof that
   --  the deletion was not published: a directory durability confirmation
   --  can fail after the name is gone. Callers requiring certainty must
   --  reconcile with Head_Object or Get_Object before retrying.

   --  Delete one selected generation or publish the bucket-versioning delete
   --  marker required by a Current selector.  Current preserves legacy
   --  unversioned physical deletion, appends an opaque marker when enabled,
   --  and replaces any null generation with a null marker when suspended.
   --  Null and Exact permanently remove only that selected generation.  A
   --  missing unconditioned selection is an idempotent success.  When bucket
   --  MFA Delete is enabled, permanent Null or Exact deletion requires the
   --  caller's atomic MFA_Validated attestation.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Selector Current, null, or exact deletion target
   --  @param Conditions Optional selected-generation predicates
   --  @param MFA_Validated Caller authorization attestation for MFA Delete
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Outcome Exact publication effect and generation identity
   --  @param Result Storage-domain outcome
   procedure Delete_Selected_Object
     (Item          : in out Backend;
      Bucket        : String;
      Key           : String;
      Selector      : Version_Selector;
      Conditions    : Delete_Object_Conditions;
      MFA_Validated : Boolean;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Outcome       : out Version_Delete_Outcome;
      Result        : out Status) is abstract;

   --  Evaluate and publish a bounded ordered batch under one backend batch
   --  boundary. Outcomes align one-for-one with Entries when Result is
   --  Success. Each entry selects Current, Null, or Exact generation semantics
   --  and returns its exact publication effect on success. Missing
   --  unconditioned selections are reported as Success; conditioned missing
   --  selections remain Not_Found. Backends must validate the complete request
   --  before mutating catalog state. Requirements are evaluated under
   --  the same protected, locked, or transactional boundary as deletion, so a
   --  concurrent versioning change cannot race current-object semantics. If
   --  MFA Delete is enabled, any Null or Exact entry without MFA_Validated
   --  rejects the complete batch before publication. This
   --  contract does not promise cross-file power-loss atomicity for a pure
   --  filesystem implementation. A pure-files failure, cancellation, or
   --  exception can expose a deleted prefix of the ordered batch, including
   --  when directory durability confirmation fails after one or more unlinks;
   --  Backend_Unavailable is not a no-deletion certainty signal. Callers must
   --  reconcile every requested key before retrying an indeterminate batch.
   procedure Delete_Objects
     (Item     : in out Backend;
      Bucket   : String;
      Entries  : Delete_Object_Entries;
      Requirements : Delete_Objects_Requirements;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Outcomes : out Delete_Object_Outcomes;
      Result   : out Status) is abstract;

   --  Atomically replace the complete tag set associated with one selected
   --  object generation. Missing buckets and objects remain distinguishable.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Tags Complete replacement tag set
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Identity Selected generation from the mutation snapshot on
   --    success
   --  @param Result Storage-domain outcome
   --  @param Selector Current, null, or exact generation selection
   procedure Put_Object_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Tags     : Object_Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector) is abstract;

   --  Compatibility convenience when the selected version identity is not
   --  needed by the caller.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Tags Complete replacement tag set
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage-domain outcome
   --  @param Selector Current, null, or exact generation selection
   procedure Put_Object_Tags
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Tags     : Object_Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Return the complete tag set for one selected generation.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Tags Complete selected tag set
   --  @param Identity Selected generation from the read snapshot on success
   --  @param Result Storage-domain outcome
   --  @param Selector Current, null, or exact generation selection
   procedure Get_Object_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags     : out Object_Tag_Set;
      Identity : out Version_Identity;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector) is abstract;

   --  Compatibility convenience when the selected version identity is not
   --  needed by the caller.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Tags Complete selected tag set
   --  @param Result Storage-domain outcome
   --  @param Selector Current, null, or exact generation selection
   procedure Get_Object_Tags
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags     : out Object_Tag_Set;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector);

   --  Clear the complete tag set for one selected generation.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Identity Selected generation from the mutation snapshot on
   --    success
   --  @param Result Storage-domain outcome
   --  @param Selector Current, null, or exact generation selection
   procedure Delete_Object_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Identity : out Version_Identity;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector) is abstract;

   --  Compatibility convenience when the selected version identity is not
   --  needed by the caller.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Key Object key
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Storage-domain outcome
   --  @param Selector Current, null, or exact generation selection
   procedure Delete_Object_Tags
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector);
   --  Not_Found means the bucket exists but the key does not.
   --  Bucket_Not_Found means the bucket itself does not exist. Backends must
   --  classify and delete under one namespace-publication boundary.

   --  Return at most Options.Maximum combined objects and common prefixes.
   --  Items and the exclusive After cursor use unsigned bytewise lexical
   --  ordering; each collapsed common prefix counts as one item.
   procedure List_Objects
     (Item     : in out Backend;
      Bucket   : String;
      Options  : List_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Page;
      Result   : out Status) is abstract;

   --  Return at most Options.Maximum combined versions, delete markers, and
   --  common prefixes.  Keys use unsigned bytewise lexical order; retained
   --  generations of one key use newest-publication-first order.  A version
   --  marker is valid only with a key marker and resumes after that exact
   --  generation of the marked key.
   --  @param Item Backend instance
   --  @param Bucket Bucket name
   --  @param Options Prefix, delimiter, paired cursor, and page bound
   --  @param Token Optional cooperative-cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Page Atomic bounded result page
   --  @param Result Storage-domain outcome
   procedure List_Object_Versions
     (Item     : in out Backend;
      Bucket   : String;
      Options  : List_Versions_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Versions_Page;
      Result   : out Status) is abstract;

   --  Start one upload. Upload identifiers are backend-generated, opaque,
   --  nonempty, and scoped to the exact bucket and key. Backends that do not
   --  override multipart primitives inherit a Not_Implemented result.
   procedure Create_Multipart_Upload
     (Item      : in out Backend;
      Bucket    : String;
      Key       : String;
      Options   : Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
      Result    : out Status) is abstract;

   --  Replace one staged part atomically after consuming and validating the
   --  complete source. Part bytes count against backend capacity.
   procedure Put_Multipart_Part
     (Item        : in out Backend;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Options     : Multipart_Part_Options;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status) is abstract;

   --  Compatibility convenience without a caller-supplied checksum.
   procedure Put_Multipart_Part
     (Item        : in out Backend'Class;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status);

   --  Return committed staged parts strictly after Options.After, ordered by
   --  part number. A truncated nonempty page resumes from Next_After.
   procedure List_Multipart_Parts
     (Item      : in out Backend;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : List_Multipart_Parts_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Part_Page;
      Result    : out Status) is abstract;

   --  Return one atomic snapshot of active uploads after the exclusive marker.
   --  Keys use unsigned bytewise lexical order. Uploads with the same key use
   --  initiation-time order and upload ID breaks equal-time ties; marker
   --  filtering independently follows S3's lexical upload-ID rule.
   --  Delimiter-collapsed prefixes count toward Maximum like returned uploads.
   procedure List_Multipart_Uploads
     (Item      : in out Backend;
      Bucket    : String;
      Options   : List_Multipart_Uploads_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Upload_Page;
      Result    : out Status) is abstract;

   --  Copy one immutable source-object interval into a staged part. Source
   --  conditions and range resolution apply to the same snapshot. The
   --  selected interval may not exceed Maximum_Multipart_Part_Size.
   procedure Copy_Multipart_Part
     (Item               : in out Backend;
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
      Result             : out Status) is abstract;

   --  Validate an ascending, nonempty completion list and exact part ETags,
   --  require every nonfinal part to be at least 5 MiB, then atomically
   --  replace the target object and retire the upload.
   procedure Complete_Multipart_Upload
     (Item      : in out Backend;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Options   : Complete_Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status) is abstract;

   --  Compatibility convenience using no destination predicates and no
   --  exact assembled-size assertion.
   procedure Complete_Multipart_Upload
     (Item      : in out Backend'Class;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status);

   --  Retire an upload and every staged part atomically with Conditions. A
   --  missing upload is Not_Found; a mismatched initiation time is
   --  Precondition_Failed and leaves the upload and all parts unchanged.
   procedure Abort_Multipart_Upload
     (Item      : in out Backend;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Conditions : Abort_Multipart_Conditions;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Result    : out Status) is abstract;

private
   Maximum_Bucket_Policy_Bytes : constant Byte_Count := 16 * 1_024 * 1_024;
   --  Private project-policy ceiling shared by backend persistence paths. It
   --  preserves the established S3.XML.Default_Limits document admission
   --  budget without exposing a new caller-visible constant or coupling the
   --  HTTP-independent backend boundary to the S3 wire package. Changing it
   --  changes accepted and persisted bucket-policy compatibility.

   Maximum_Bucket_CORS_Bytes : constant Byte_Count :=
     Maximum_Bucket_Policy_Bytes;
   --  Derived from the same S3.XML.Default_Limits document admission budget
   --  as bucket policy.  This private project-policy value bounds persisted
   --  canonical CORS bytes without creating a caller-visible resource limit;
   --  changing it changes accepted and durable CORS compatibility.

   Maximum_Bucket_Configuration_Bytes : constant Byte_Count :=
     Maximum_Bucket_CORS_Bytes;
   --  Derived from the same established XML resource budget as CORS. This
   --  private value bounds canonical singleton bucket-configuration bytes,
   --  including encryption, ownership, lifecycle, and logging, without
   --  exposing a caller-visible resource-policy constant.

   Maximum_Bucket_Named_Configurations : constant Positive := 1_000;
   --  The pinned S3 analytics and request-metrics contracts fix this
   --  per-family bucket limit. It remains private because it is provider wire
   --  compatibility, not a caller-selected backend capacity.

   function Valid_Bucket_Named_Configuration
     (Identifier : String; Document : String) return Boolean;

   --  Monotonic publication order is backend-private metadata, not a wire or
   --  caller-visible value.  It disambiguates generations that share a
   --  one-second timestamp without expanding the listing API.
   subtype Version_Publication_Order is
     Long_Long_Integer range 0 .. Long_Long_Integer'Last;

   Current_Version_Selector : constant Version_Selector :=
     (Kind => Current_Version,
      ID   => Ada.Strings.Unbounded.Null_Unbounded_String);

   Null_Version_Selector : constant Version_Selector :=
     (Kind => Null_Version,
      ID   => Ada.Strings.Unbounded.Null_Unbounded_String);

   Default_Multipart_Options : constant Multipart_Options :=
     (Content_Type =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"),
      Checksum => (others => <>));

   Default_Multipart_Part_Options : constant Multipart_Part_Options :=
     (Expected_Checksum => (others => <>));

   Default_Complete_Multipart_Options : constant Complete_Multipart_Options :=
     (Conditions    => (others => <>),
      Expected_Size => (Kind => Unknown),
      Expected_Checksum => (others => <>));

   No_Abort_Multipart_Conditions : constant Abort_Multipart_Conditions :=
     (others => <>);

   Default_Copy_Options : constant Copy_Options :=
     (Source_Selector    => Current_Version_Selector,
      Metadata_Directive => Copy_Metadata,
      Content_Type       =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"),
      Metadata           => (others => <>),
      Tagging_Directive  => Copy_Tags,
      Tags               => (others => <>),
      Selected_Checksum  => No_Checksum,
      Conditions         => (others => <>),
      Destination_Conditions => (others => <>));

   Default_Copy_Conditions : constant Copy_Conditions := (others => <>);

   Default_Read_Conditions : constant Read_Conditions :=
     (If_Match            => Ada.Strings.Unbounded.Null_Unbounded_String,
      If_Modified_Since   => (Is_Set => False),
      If_None_Match       => Ada.Strings.Unbounded.Null_Unbounded_String,
      If_Unmodified_Since => (Is_Set => False));

   No_Delete_Object_Conditions : constant Delete_Object_Conditions :=
     (others => <>);

end Flyology.Object_Storage.Backends;
