with Ada.Strings.Unbounded;

--  Defines storage-domain values shared by S3 clients, servers and backends.
--  Wire DTOs and HTTP state intentionally do not cross this package boundary.
package Flyology.Object_Storage
  with SPARK_Mode => On
is

   --  Nonnegative byte count used for object and multipart sizes.
   subtype Byte_Count is Long_Long_Integer range 0 .. Long_Long_Integer'Last;

   --  Nonnegative Unix timestamp retained with stored object metadata.
   subtype Unix_Time is Long_Long_Integer range 0 .. Long_Long_Integer'Last;

   --  Storage operation outcome.
   --  @enum Success Operation completed successfully
   --  @enum Not_Found Requested resource was not found
   --  @enum Bucket_Not_Found Requested bucket was not found
   --  @enum Tag_Set_Not_Found Requested tag set was not found
   --  @enum Already_Exists Requested resource already exists
   --  @enum Bucket_Not_Empty Bucket still contains objects
   --  @enum Capacity_Exceeded Bounded backend capacity was exceeded
   --  @enum Configuration_Limit_Exceeded Modeled configuration count reached
   --  @enum Invalid_Request Request did not satisfy the storage contract
   --  @enum Invalid_Range Requested byte range is invalid
   --  @enum Invalid_Part Multipart part is invalid
   --  @enum Invalid_Part_Order Multipart parts are not in valid order
   --  @enum Bad_Digest Supplied content digest does not match the content
   --  @enum Entity_Too_Small Supplied entity is below the accepted size
   --  @enum Entity_Too_Large Supplied entity exceeds the accepted size
   --  @enum Source_Bucket_Not_Found Copy source bucket was not found
   --  @enum Source_Not_Found Copy source object was not found
   --  @enum Precondition_Failed A requested condition was not satisfied
   --  @enum Not_Modified Conditional read found no modification
   --  @enum Conflict Operation conflicts with current storage state
   --  @enum Access_Denied Operation is not permitted
   --  @enum Not_Implemented Backend does not implement the operation
   --  @enum Backend_Unavailable Backend cannot currently serve the operation
   type Status is
     (Success,
      Not_Found,
      Bucket_Not_Found,
      Tag_Set_Not_Found,
      Already_Exists,
      Bucket_Not_Empty,
      Capacity_Exceeded,
      Configuration_Limit_Exceeded,
      Invalid_Request,
      Invalid_Range,
      Invalid_Part,
      Invalid_Part_Order,
      Bad_Digest,
      Entity_Too_Small,
      Entity_Too_Large,
      Source_Bucket_Not_Found,
      Source_Not_Found,
      Precondition_Failed,
      Not_Modified,
      Conflict,
      Access_Denied,
      Not_Implemented,
      Backend_Unavailable);

   --  Storage-domain checksum metadata. Wire spelling and Base64 validation
   --  remain in the S3 boundary; backends retain the selected algorithm,
   --  checksum method, and canonical encoded value with the object or part.
   --  @enum No_Checksum No checksum metadata is present
   --  @enum Checksum_CRC32 CRC-32 checksum
   --  @enum Checksum_CRC32C CRC-32C checksum
   --  @enum Checksum_CRC64NVME CRC-64/NVME checksum
   --  @enum Checksum_SHA1 SHA-1 checksum
   --  @enum Checksum_SHA256 SHA-256 checksum
   --  @enum Checksum_SHA512 SHA-512 checksum
   --  @enum Checksum_MD5 MD5 checksum
   --  @enum Checksum_XXHASH64 XXH64 checksum
   --  @enum Checksum_XXHASH3 XXH3 64-bit checksum
   --  @enum Checksum_XXHASH128 XXH3 128-bit checksum
   type Checksum_Algorithm is
     (No_Checksum,
      Checksum_CRC32,
      Checksum_CRC32C,
      Checksum_CRC64NVME,
      Checksum_SHA1,
      Checksum_SHA256,
      Checksum_SHA512,
      Checksum_MD5,
      Checksum_XXHASH64,
      Checksum_XXHASH3,
      Checksum_XXHASH128);

   --  Method used to calculate stored checksum metadata.
   --  @enum No_Checksum_Method No checksum calculation method is present
   --  @enum Composite_Checksum Checksum is composed from part checksums
   --  @enum Full_Object_Checksum Checksum covers the complete object
   type Checksum_Method is
     (No_Checksum_Method, Composite_Checksum, Full_Object_Checksum);

   --  Checksum metadata retained with an object or multipart part.
   --  @field Algorithm Selected checksum algorithm
   --  @field Method Method used to calculate the checksum
   --  @field Value Canonical encoded checksum value
   type Checksum_Information is record
      Algorithm : Checksum_Algorithm := No_Checksum;
      Method    : Checksum_Method := No_Checksum_Method;
      Value     : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Checksum metadata representing the absence of a checksum.
   No_Checksum_Information : constant Checksum_Information;

   --  Evaluate HTTP entity-tag predicates for one atomic object publication.
   --  Missing objects never satisfy If-Match and always satisfy a valid
   --  If-None-Match. Malformed or excessively large fields are rejected.
   --  @param If_Match Optional If-Match field value
   --  @param If_None_Match Optional If-None-Match field value
   --  @param Exists Whether the destination object exists
   --  @param Entity_Tag Stored unquoted entity tag when the object exists
   --  @return Condition evaluation outcome
   function Evaluate_Object_Write_Conditions
     (If_Match, If_None_Match : String;
      Exists                  : Boolean;
      Entity_Tag              : String) return Status;

   --  Validate one If-Match or If-None-Match field for an object read.
   --  Weak entity tags are valid syntax; comparison semantics are selected by
   --  Evaluate_Object_Read_Conditions. Oversized fields are rejected.
   --  @param Value Entity-tag condition field value
   --  @return True when Value has valid bounded entity-tag list syntax
   function Valid_Object_Read_Entity_Tag_Condition
     (Value : String) return Boolean;

   --  Validate both optional entity-tag predicates before an operation
   --  acquires a snapshot or other bounded backend resources.
   --  @param If_Match Optional If-Match field value
   --  @param If_None_Match Optional If-None-Match field value
   --  @return True when both fields have valid bounded syntax
   function Valid_Object_Write_Conditions
     (If_Match, If_None_Match : String) return Boolean;

   --  Evaluate S3 conditional-read precedence against one immutable metadata
   --  snapshot. Entity_Tag is the stored unquoted opaque tag. The two Boolean
   --  arguments distinguish an absent date condition from every signed HTTP
   --  date value, including dates before the Unix epoch.
   --  @param If_Match Optional If-Match field value
   --  @param If_None_Match Optional If-None-Match field value
   --  @param Has_If_Modified_Since Whether the modified-since date is present
   --  @param If_Modified_Since Modified-since date in signed Unix seconds
   --  @param Has_If_Unmodified_Since Whether the unmodified date is present
   --  @param If_Unmodified_Since Unmodified-since date in signed Unix seconds
   --  @param Entity_Tag Stored unquoted entity tag
   --  @param Modified Stored nonnegative modification time
   --  @return Conditional-read outcome
   function Evaluate_Object_Read_Conditions
     (If_Match, If_None_Match : String;
      Has_If_Modified_Since   : Boolean;
      If_Modified_Since       : Long_Long_Integer;
      Has_If_Unmodified_Since : Boolean;
      If_Unmodified_Since     : Long_Long_Integer;
      Entity_Tag              : String;
      Modified                : Unix_Time) return Status
   with Post => Evaluate_Object_Read_Conditions'Result in
     Success | Precondition_Failed | Not_Modified | Invalid_Request;

   --  Evaluate CopyObject source validators against one immutable metadata
   --  snapshot. Entity-tag predicates take precedence over their paired date
   --  predicates. A failed If-None-Match is a 412 copy precondition rather
   --  than the 304 result used by GetObject and HeadObject.
   --  @param If_Match Optional copy-source If-Match field value
   --  @param If_None_Match Optional copy-source If-None-Match field value
   --  @param Has_If_Modified_Since Whether the modified-since date is present
   --  @param If_Modified_Since Modified-since date in signed Unix seconds
   --  @param Has_If_Unmodified_Since Whether the unmodified date is present
   --  @param If_Unmodified_Since Unmodified-since date in signed Unix seconds
   --  @param Entity_Tag Stored unquoted source entity tag
   --  @param Modified Stored nonnegative source modification time
   --  @return Copy-source condition outcome
   function Evaluate_Object_Copy_Conditions
     (If_Match, If_None_Match : String;
      Has_If_Modified_Since   : Boolean;
      If_Modified_Since       : Long_Long_Integer;
      Has_If_Unmodified_Since : Boolean;
      If_Unmodified_Since     : Long_Long_Integer;
      Entity_Tag              : String;
      Modified                : Unix_Time) return Status
   with Post => Evaluate_Object_Copy_Conditions'Result in
     Success | Precondition_Failed | Invalid_Request;

   --  Validate the S3 DeleteObjects ETag condition. The wildcard, an exact
   --  unquoted opaque tag, and the corresponding quoted form are accepted;
   --  lists, weak validators, whitespace decoration, and controls are not.
   --  @param Value DeleteObjects ETag condition value
   --  @return True when Value is a valid DeleteObjects ETag condition
   function Valid_Object_Delete_ETag_Condition
     (Value : String) return Boolean;

   --  Evaluate every conditional DeleteObjects member against one catalog
   --  snapshot. An unconditioned missing key is an idempotent success, while
   --  a conditioned missing key is Not_Found. Last_Modified_Time is already
   --  parsed to signed Unix seconds by the protocol boundary.
   --  @param Has_ETag Whether the ETag condition is present
   --  @param ETag ETag condition value
   --  @param Has_Last_Modified_Time Whether the time condition is present
   --  @param Last_Modified_Time Expected modification time in Unix seconds
   --  @param Has_Size Whether the size condition is present
   --  @param Expected_Size Expected object size
   --  @param Exists Whether the object exists in the catalog snapshot
   --  @param Entity_Tag Stored unquoted entity tag when the object exists
   --  @param Modified Stored nonnegative modification time
   --  @param Size Stored object size
   --  @return DeleteObjects member condition outcome
   function Evaluate_Object_Delete_Conditions
     (Has_ETag               : Boolean;
      ETag                   : String;
      Has_Last_Modified_Time : Boolean;
      Last_Modified_Time     : Long_Long_Integer;
      Has_Size               : Boolean;
      Expected_Size          : Byte_Count;
      Exists                 : Boolean;
      Entity_Tag             : String;
      Modified               : Unix_Time;
      Size                   : Byte_Count) return Status
   with Post => Evaluate_Object_Delete_Conditions'Result in
     Success | Not_Found | Precondition_Failed | Invalid_Request;

   --  Persisted bucket-versioning state. Unconfigured denotes that no value
   --  has ever been supplied; it is distinct from Suspended on the S3 wire.
   --  @enum Versioning_Unconfigured No versioning value has been supplied
   --  @enum Versioning_Enabled Versioning is enabled
   --  @enum Versioning_Suspended Versioning is suspended
   type Bucket_Versioning_Status is
     (Versioning_Unconfigured, Versioning_Enabled, Versioning_Suspended);

   --  Persisted MFA-delete state. The storage contract can preserve this
   --  value, but an S3 boundary must not accept a change without independently
   --  enforcing its MFA policy.
   --  @enum MFA_Delete_Unconfigured No MFA-delete value has been supplied
   --  @enum MFA_Delete_Enabled MFA delete is enabled
   --  @enum MFA_Delete_Disabled MFA delete is disabled
   type MFA_Delete_Status is
     (MFA_Delete_Unconfigured, MFA_Delete_Enabled, MFA_Delete_Disabled);

   --  Atomic configuration associated with one bucket. Version-aware
   --  backends apply Status to object publication and selection under the
   --  same backend state boundary; a backend that has not qualified those
   --  semantics returns Not_Implemented from its version-specific surface.
   --  @field Status Persisted versioning status
   --  @field MFA_Delete Persisted MFA-delete status
   type Bucket_Versioning_Configuration is record
      Status     : Bucket_Versioning_Status := Versioning_Unconfigured;
      MFA_Delete : MFA_Delete_Status := MFA_Delete_Unconfigured;
   end record;

   --  Persisted attribute-based access-control state for a general purpose
   --  bucket. AWS defines newly created general purpose buckets as disabled;
   --  HTTP and XML spelling remain at the S3 boundary.
   --  @enum Bucket_ABAC_Disabled Bucket tags do not participate in access
   --    control
   --  @enum Bucket_ABAC_Enabled Bucket tags may participate in access control
   --  @enum Bucket_ABAC_Unconfigured An explicit configuration omitted Status
   type Bucket_ABAC_Status is
     (Bucket_ABAC_Disabled,
      Bucket_ABAC_Enabled,
      Bucket_ABAC_Unconfigured);

   --  Persisted transfer-acceleration state. Unconfigured is distinct from
   --  Suspended because GetBucketAccelerateConfiguration omits Status until
   --  the bucket has received an explicit acceleration configuration.
   --  @enum Bucket_Acceleration_Unconfigured No state has been supplied
   --  @enum Bucket_Acceleration_Enabled Transfer acceleration is enabled
   --  @enum Bucket_Acceleration_Suspended Transfer acceleration is suspended
   type Bucket_Acceleration_Status is
     (Bucket_Acceleration_Unconfigured,
      Bucket_Acceleration_Enabled,
      Bucket_Acceleration_Suspended);

   --  Persisted request-payment state. AWS defines bucket-owner payment as
   --  the initial state of a newly created bucket.
   --  @enum Bucket_Owner_Pays The bucket owner pays request and transfer fees
   --  @enum Requester_Pays The requester pays request and transfer fees
   type Bucket_Request_Payment_Status is
     (Bucket_Owner_Pays, Requester_Pays);

   --  Presence-preserving Boolean storage used by bucket configuration
   --  records.  The value has no meaning while Is_Set is False.  This is a
   --  storage-domain representation; XML spelling remains at the S3 boundary.
   --  @field Is_Set Whether the configuration member is present
   --  @field Value Member value when present
   type Optional_Configuration_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Atomic persisted PublicAccessBlock configuration.  Every member is
   --  independently optional in the pinned S3 model, including a present
   --  configuration with no members.  Overall configuration absence is
   --  returned separately by backend reads.
   --  @field Block_Public_ACLs BlockPublicAcls member and presence
   --  @field Ignore_Public_ACLs IgnorePublicAcls member and presence
   --  @field Block_Public_Policy BlockPublicPolicy member and presence
   --  @field Restrict_Public_Buckets RestrictPublicBuckets member and presence
   type Bucket_Public_Access_Block_Configuration is record
      Block_Public_ACLs       : Optional_Configuration_Boolean;
      Ignore_Public_ACLs      : Optional_Configuration_Boolean;
      Block_Public_Policy     : Optional_Configuration_Boolean;
      Restrict_Public_Buckets : Optional_Configuration_Boolean;
   end record;

   --  Merge independently optional configuration fields. An Unconfigured
   --  update field preserves the current field.
   --  @param Current Existing versioning configuration
   --  @param Update Presence-preserving configuration update
   --  @return Configuration with supplied fields merged into Current
   function Merge_Bucket_Versioning
     (Current, Update : Bucket_Versioning_Configuration)
      return Bucket_Versioning_Configuration
   with
     Post =>
       Merge_Bucket_Versioning'Result.Status =
         (if Update.Status = Versioning_Unconfigured
          then Current.Status else Update.Status)
       and then Merge_Bucket_Versioning'Result.MFA_Delete =
         (if Update.MFA_Delete = MFA_Delete_Unconfigured
          then Current.MFA_Delete else Update.MFA_Delete);

   --  Bytewise prefix and exclusive-cursor predicates shared by every
   --  ListObjects backend. Delimiter projection is applied before the cursor
   --  predicate so a collapsed CommonPrefixes entry counts as one item.
   --  @param Key Candidate object key
   --  @param Prefix Required bytewise prefix
   --  @return True when Key begins with Prefix
   function Listing_Matches_Prefix
     (Key, Prefix : String) return Boolean;

   --  Test whether a projected listing key follows an exclusive cursor.
   --  @param Projected_Key Object key or collapsed common prefix
   --  @param After Exclusive bytewise cursor
   --  @return True when Projected_Key sorts after After
   function Listing_Follows_Cursor
     (Projected_Key, After : String) return Boolean;

   --  Requested object byte interval. Backends resolve this request against
   --  the same immutable object snapshot that they stream, including suffix
   --  requests, so callers never need a racy Head_Object/Get_Object pair.
   --  @enum Whole_Range Complete object body
   --  @enum Bounded_Range Inclusive first and last byte positions
   --  @enum Open_Ended_Range First byte position through the object end
   --  @enum Suffix_Range Requested number of trailing bytes
   type Byte_Range_Kind is
     (Whole_Range, Bounded_Range, Open_Ended_Range, Suffix_Range);

   --  Requested object byte interval.
   --  @field Kind Form of range request
   --  @field First First requested byte for bounded or open-ended ranges
   --  @field Last Last requested byte for bounded ranges
   --  @field Count Requested trailing byte count for suffix ranges
   type Byte_Range is record
      Kind  : Byte_Range_Kind := Whole_Range;
      First : Byte_Count := 0;
      Last  : Byte_Count := 0;
      Count : Byte_Count := 0;
   end record;

   --  Complete object body range.
   Whole_Object : constant Byte_Range := (others => <>);

   --  Outcome of resolving a range against an immutable object size.
   --  @enum Empty_Object_Range Whole-body request for an empty object
   --  @enum Satisfied_Range Nonempty resolved byte interval
   --  @enum Unsatisfiable_Range Request cannot be satisfied for the object
   type Range_Resolution_Kind is
     (Empty_Object_Range, Satisfied_Range, Unsatisfiable_Range);

   --  Resolved object byte interval.
   --  @field Kind Resolution outcome
   --  @field First First resolved byte position when satisfied
   --  @field Last Last resolved byte position when satisfied
   --  @field Length Number of resolved bytes when satisfied
   type Range_Resolution
     (Kind : Range_Resolution_Kind := Unsatisfiable_Range)
   is record
      case Kind is
         when Satisfied_Range =>
            First  : Byte_Count;
            Last   : Byte_Count;
            Length : Byte_Count;
         when Empty_Object_Range | Unsatisfiable_Range =>
            null;
      end case;
   end record;

   --  Resolve a request against one immutable object size.
   --  @param Size Immutable object size
   --  @param Request Requested byte interval
   --  @return Resolved interval or an empty/unsatisfiable outcome
   function Resolve_Range
     (Size : Byte_Count; Request : Byte_Range) return Range_Resolution
   with
     Post =>
       (if Resolve_Range'Result.Kind = Satisfied_Range then
          Resolve_Range'Result.First <= Resolve_Range'Result.Last
          and then Resolve_Range'Result.Last < Size
          and then Resolve_Range'Result.Length > 0
          and then Resolve_Range'Result.Length =
            Resolve_Range'Result.Last - Resolve_Range'Result.First + 1);

   --  Maximum entries retained in the bounded user-metadata set.
   Maximum_User_Metadata_Entries : constant := 64;

   --  Maximum byte length of a canonical user-metadata key suffix.
   Maximum_User_Metadata_Key_Bytes : constant := 117;

   --  Aggregate byte budget for user-metadata keys and values.
   Maximum_User_Metadata_Bytes : constant := 2 * 1_024;

   --  Aggregate byte budget for modeled system-metadata names and values.
   Maximum_System_Metadata_Bytes : constant := 2 * 1_024;

   --  Per-value byte limit for modeled system metadata.
   Maximum_System_Metadata_Value_Bytes : constant := 2 * 1_024;

   --  Presence-preserving string metadata value.
   --  @field Is_Set Whether the metadata value is present
   --  @field Value Metadata value when present
   type Optional_Metadata_Value is record
      Is_Set : Boolean := False;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  A typed S3 Expires value spanning canonical four-digit years 0001
   --  through 9999; wire parsing and rendering remain in the S3 layer.
   type Metadata_Time is range -62_135_596_800 .. 253_402_300_799;

   --  Presence-preserving typed metadata time.
   --  @field Is_Set Whether the metadata time is present
   --  @field Value Metadata time when present
   type Optional_Metadata_Time is record
      Is_Set : Boolean := False;
      Value  : Metadata_Time := 0;
   end record;

   --  One canonical user-metadata entry.
   --  @field Key Lowercase HTTP token suffix without the x-amz-meta prefix
   --  @field Value Exact user-metadata value
   type User_Metadata_Entry is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Number of entries in a bounded user-metadata set.
   subtype User_Metadata_Count is
     Natural range 0 .. Maximum_User_Metadata_Entries;

   --  Index into the fixed-capacity user-metadata array.
   subtype User_Metadata_Index is
     Positive range 1 .. Maximum_User_Metadata_Entries;

   --  Fixed-capacity storage for user-metadata entries.
   type User_Metadata_Array is
     array (User_Metadata_Index) of User_Metadata_Entry;

   --  Bounded collection of user-metadata entries.
   --  @field Length Number of populated entries
   --  @field Items Fixed-capacity entry storage
   type User_Metadata_Set is record
      Length : User_Metadata_Count := 0;
      Items  : User_Metadata_Array;
   end record;

   --  User-metadata set with no populated entries.
   Empty_User_Metadata : constant User_Metadata_Set;

   --  User-configurable S3 system and user metadata retained with an object.
   --  Content-Type remains in Object_Information for API compatibility and
   --  participates in the same system-metadata byte budget.
   --  @field Cache_Control Optional Cache-Control value
   --  @field Content_Disposition Optional Content-Disposition value
   --  @field Content_Encoding Optional Content-Encoding value
   --  @field Content_Language Optional Content-Language value
   --  @field Expires Optional typed Expires value
   --  @field Website_Redirect_Location Optional website redirect value
   --  @field User Bounded user-metadata entries
   type Object_Metadata is record
      Cache_Control             : Optional_Metadata_Value;
      Content_Disposition       : Optional_Metadata_Value;
      Content_Encoding          : Optional_Metadata_Value;
      Content_Language          : Optional_Metadata_Value;
      Expires                   : Optional_Metadata_Time;
      Website_Redirect_Location : Optional_Metadata_Value;
      User                      : User_Metadata_Set;
   end record;

   --  Object metadata with no configured system or user values.
   Empty_Object_Metadata : constant Object_Metadata;

   --  Validate exact S3 metadata budgets. User bytes are the UTF-8 bytes of
   --  every key and value. System bytes are the US-ASCII bytes of each
   --  present wire name and value, including Content-Type when nonempty.
   --  User keys are canonical lowercase HTTP token suffixes and unique.
   --  @param Metadata Candidate modeled metadata
   --  @param Content_Type Candidate Content-Type value
   --  @return True when every value and aggregate budget is valid
   function Valid_Object_Metadata
     (Metadata : Object_Metadata; Content_Type : String) return Boolean;

   --  Metadata retained with one committed object version.
   --  @field Size Object body size in bytes
   --  @field Modified Nonnegative Unix modification time
   --  @field Entity_Tag Stored unquoted entity tag
   --  @field Content_Type Stored Content-Type value
   --  @field Version Storage version identifier
   --  @field Checksum Stored checksum metadata
   --  @field Metadata Stored system and user metadata
   type Object_Information is record
      Size          : Byte_Count := 0;
      Modified      : Unix_Time := 0;
      Entity_Tag    : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type  : Ada.Strings.Unbounded.Unbounded_String;
      Version       : Ada.Strings.Unbounded.Unbounded_String;
      Checksum      : Checksum_Information;
      Metadata      : Object_Metadata;
   end record;

   --  Maximum tags retained in one bounded object-tag set.
   Maximum_Object_Tags : constant := 10;

   --  Number of tags in a bounded object tag set.
   subtype Object_Tag_Count is Natural range 0 .. Maximum_Object_Tags;

   --  Index into the fixed-capacity object tag array.
   subtype Object_Tag_Index is Positive range 1 .. Maximum_Object_Tags;

   --  One object-tag key and value pair.
   --  @field Key Object-tag key bytes
   --  @field Value Object-tag value bytes
   type Object_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Fixed-capacity storage for object tags.
   type Object_Tag_Array is array (Object_Tag_Index) of Object_Tag;

   --  Fixed-capacity representation keeps the backend contract bounded and
   --  permits an entire tag set to be copied under one publication boundary.
   --  @field Length Number of populated tags
   --  @field Items Fixed-capacity tag storage
   type Object_Tag_Set is record
      Length : Object_Tag_Count := 0;
      Items  : Object_Tag_Array;
   end record;

   --  Object tag set with no populated tags.
   Empty_Object_Tags : constant Object_Tag_Set;

   --  Backend-safe byte bounds shared by all protocol adapters. This does not
   --  replace S3's stricter Unicode repertoire validation.
   --  @param Tags Candidate bounded object tag set
   --  @return True when each populated tag satisfies backend-safe bounds
   function Valid_Object_Tag_Set (Tags : Object_Tag_Set) return Boolean;

   --  Destination validators evaluated against the same publication boundary
   --  that makes a complete object visible. Values use HTTP entity-tag list
   --  syntax; the storage contract remains independent of HTTP request types.
   --  @field If_Match Optional If-Match destination predicate
   --  @field If_None_Match Optional If-None-Match destination predicate
   type Write_Conditions is record
      If_Match      : Ada.Strings.Unbounded.Unbounded_String;
      If_None_Match : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  No destination predicates.
   Default_Write_Conditions : constant Write_Conditions;

   --  Metadata supplied when committing an object. An empty Entity_Tag asks
   --  the backend to generate the ordinary single-part S3 MD5 entity tag.
   --  This identifier is not a collision-resistant integrity checksum.
   --  @field Entity_Tag Requested entity tag or empty for backend generation
   --  @field Content_Type Stored Content-Type value
   --  @field Metadata Stored system and user metadata
   --  @field Tags Initial object tag set
   --  @field Checksum Checksum metadata retained with the object
   type Put_Options is record
      Entity_Tag   : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
      Metadata     : Object_Metadata;
      Tags         : Object_Tag_Set;
      Checksum     : Checksum_Information;
   end record;

   --  Default metadata for an opaque binary object.
   Default_Put_Options : constant Put_Options;

   --  Validate an ordinary general-purpose S3 bucket name.
   --  @param Value Candidate bucket name
   --  @return True when Value is safe for the shared backend namespace
   function Valid_Bucket_Name (Value : String) return Boolean;

   --  Validate an object key at the storage boundary.
   --  @param Value Candidate object key
   --  @return True for a nonempty key of at most 1,024 bytes without NUL
   function Valid_Object_Key (Value : String) return Boolean;

   --  Maximum decoded Unicode scalar count accepted by tag validation.
   subtype Tag_Character_Limit is Positive range 1 .. 256;

   --  Validate one UTF-8 S3 tag scalar using AWS's Unicode character set.
   --  @param Value UTF-8 encoded tag key or value
   --  @param Maximum Maximum decoded Unicode scalar count
   --  @param Empty_Allowed Whether the empty byte string is valid
   --  @return True for canonical UTF-8 within the AWS L/Z/N and symbol set
   function Valid_Tag_Text
     (Value         : String;
      Maximum       : Tag_Character_Limit;
      Empty_Allowed : Boolean) return Boolean;

private
   No_Checksum_Information : constant Checksum_Information := (others => <>);
   Empty_User_Metadata : constant User_Metadata_Set := (others => <>);
   Empty_Object_Metadata : constant Object_Metadata := (others => <>);
   Empty_Object_Tags : constant Object_Tag_Set := (others => <>);
   Default_Write_Conditions : constant Write_Conditions := (others => <>);
   Default_Put_Options : constant Put_Options :=
     (Entity_Tag   => Ada.Strings.Unbounded.Null_Unbounded_String,
      Content_Type =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"),
      Metadata     => (others => <>),
      Tags         => (others => <>),
      Checksum     => (others => <>));
end Flyology.Object_Storage;
