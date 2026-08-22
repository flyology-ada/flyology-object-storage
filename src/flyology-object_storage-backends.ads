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

   --  Source validators evaluated against the same immutable snapshot that
   --  is copied. Values use the HTTP entity-tag list syntax.
   type Copy_Conditions is record
      If_Match      : Ada.Strings.Unbounded.Unbounded_String;
      If_None_Match : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Copy_Metadata_Directive is (Copy_Metadata, Replace_Metadata);

   type Copy_Options is record
      Metadata_Directive : Copy_Metadata_Directive := Copy_Metadata;
      Content_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Conditions         : Copy_Conditions;
   end record;

   Default_Copy_Options : constant Copy_Options;

   --  Evaluate If-Match and If-None-Match against an unquoted stored ETag.
   function Copy_Conditions_Accept
     (Conditions : Copy_Conditions; Entity_Tag : String) return Boolean;

   --  Evaluate If-Match and If-None-Match for an atomic object publication.
   --  A missing destination never satisfies If-Match and always satisfies a
   --  syntactically valid If-None-Match. Failures are Precondition_Failed;
   --  malformed entity-tag lists are Invalid_Request.
   function Evaluate_Write_Conditions
     (Conditions : Copy_Conditions;
      Exists     : Boolean;
      Entity_Tag : String) return Status;

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

   Maximum_Multipart_Part_Size : constant Byte_Count :=
     5 * 1_024 * 1_024 * 1_024;

   type Multipart_Options is record
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Default_Multipart_Options : constant Multipart_Options;

   --  Predicates and exact assembled size checked in the same publication
   --  boundary that replaces the destination and retires the upload.
   type Complete_Multipart_Options is record
      Conditions    : Copy_Conditions;
      Expected_Size : Source_Length;
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
   end record;

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
   end record;

   --  Completed multipart metadata retained with a committed object. The
   --  values are HTTP-independent and refer to the exact immutable object
   --  generation described by Object_Attribute_Snapshot.Info.
   type Completed_Object_Part is record
      Number : Multipart_Part_Number := Multipart_Part_Number'First;
      Size   : Byte_Count := 0;
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
   --  changed independently. This does not create object versions or change
   --  object mutation semantics.
   procedure Put_Bucket_Versioning
     (Item          : in out Backend;
      Bucket        : String;
      Configuration : Bucket_Versioning_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status) is abstract;

   --  Return one atomic configuration snapshot. A newly created bucket
   --  returns both fields Unconfigured.
   procedure Get_Bucket_Versioning
     (Item          : in out Backend;
      Bucket        : String;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Configuration : out Bucket_Versioning_Configuration;
      Result        : out Status) is abstract;

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

   procedure Put_Object
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status) is abstract;
   --  A successful implementation consumes Source through Finished, validates
   --  its declared length, and publishes the object only after all source
   --  validation succeeds. A failed call does not expose a partial object.

   --  Copy one immutable source snapshot to the destination. Source absence
   --  is Source_Not_Found; destination-bucket absence remains Not_Found.
   --  Conditions are evaluated atomically against the copied snapshot.
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
      Result             : out Status) is abstract;

   procedure Head_Object
     (Item   : in out Backend;
      Bucket : String;
      Key    : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info   : out Object_Information;
      Result : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions) is abstract;
   --  Conditions are evaluated against the exact immutable metadata snapshot
   --  returned in Info. Conditional failures retain that snapshot in Info.

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
      Conditions : Read_Conditions := Default_Read_Conditions) is abstract;
   --  A successful implementation calls Begin_Object exactly once, then
   --  writes exactly its announced Content_Length. When Result is
   --  Invalid_Range, Info is the immutable object snapshot against which
   --  Requested was resolved and no sink callback has occurred.

   --  Return object metadata and a bounded page of retained completed-part
   --  metadata from one atomic object-generation snapshot. Ordinary PUT and
   --  COPY objects report Is_Multipart false and no parts. A successful
   --  multipart completion reports its total selected part count even when
   --  the requested page is empty.
   procedure Get_Object_Attributes
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Options  : Object_Attribute_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Snapshot : out Object_Attribute_Snapshot;
      Result   : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions) is abstract;
   --  Conditions are evaluated against Snapshot.Info within the same atomic
   --  metadata boundary used to collect the completed-part snapshot.

   procedure Delete_Object
     (Item   : in out Backend;
      Bucket : String;
      Key    : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status) is abstract;

   --  Atomically replace, read, or clear the complete tag set associated with
   --  one current object. Missing buckets and objects remain distinguishable.
   procedure Put_Object_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Tags     : Object_Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;

   procedure Get_Object_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags     : out Object_Tag_Set;
      Result   : out Status) is abstract;

   procedure Delete_Object_Tags
     (Item     : in out Backend;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is abstract;
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
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status) is abstract;

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
   Default_Multipart_Options : constant Multipart_Options :=
     (Content_Type =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"));

   Default_Complete_Multipart_Options : constant Complete_Multipart_Options :=
     (Conditions    => (others => <>),
      Expected_Size => (Kind => Unknown));

   No_Abort_Multipart_Conditions : constant Abort_Multipart_Conditions :=
     (others => <>);

   Default_Copy_Options : constant Copy_Options :=
     (Metadata_Directive => Copy_Metadata,
      Content_Type       =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"),
      Conditions         => (others => <>));

   Default_Read_Conditions : constant Read_Conditions :=
     (If_Match            => Ada.Strings.Unbounded.Null_Unbounded_String,
      If_Modified_Since   => (Is_Set => False),
      If_None_Match       => Ada.Strings.Unbounded.Null_Unbounded_String,
      If_Unmodified_Since => (Is_Set => False));

end Flyology.Object_Storage.Backends;
