with Ada.Strings.Unbounded;

--  Defines storage-domain values shared by S3 clients, servers and backends.
--  Wire DTOs and HTTP state intentionally do not cross this package boundary.
package Flyology.Object_Storage
  with SPARK_Mode => On
is

   --  Nonnegative byte count used for object and multipart sizes.
   subtype Byte_Count is Long_Long_Integer range 0 .. Long_Long_Integer'Last;
   subtype Unix_Time is Long_Long_Integer range 0 .. Long_Long_Integer'Last;

   --  Storage operation outcome.
   type Status is
     (Success,
      Not_Found,
      Bucket_Not_Found,
      Tag_Set_Not_Found,
      Already_Exists,
      Bucket_Not_Empty,
      Capacity_Exceeded,
      Invalid_Request,
      Invalid_Range,
      Invalid_Part,
      Invalid_Part_Order,
      Entity_Too_Small,
      Entity_Too_Large,
      Source_Not_Found,
      Precondition_Failed,
      Not_Modified,
      Conflict,
      Not_Implemented,
      Backend_Unavailable);

   --  Evaluate HTTP entity-tag predicates for one atomic object publication.
   --  Missing objects never satisfy If-Match and always satisfy a valid
   --  If-None-Match. Malformed or excessively large fields are rejected.
   function Evaluate_Object_Write_Conditions
     (If_Match, If_None_Match : String;
      Exists                  : Boolean;
      Entity_Tag              : String) return Status;

   --  Validate one If-Match or If-None-Match field for an object read.
   --  Weak entity tags are valid syntax; comparison semantics are selected by
   --  Evaluate_Object_Read_Conditions. Oversized fields are rejected.
   function Valid_Object_Read_Entity_Tag_Condition
     (Value : String) return Boolean;

   --  Evaluate S3 conditional-read precedence against one immutable metadata
   --  snapshot. Entity_Tag is the stored unquoted opaque tag. The two Boolean
   --  arguments distinguish an absent date condition from every signed HTTP
   --  date value, including dates before the Unix epoch.
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

   --  Validate the S3 DeleteObjects ETag condition. The wildcard, an exact
   --  unquoted opaque tag, and the corresponding quoted form are accepted;
   --  lists, weak validators, whitespace decoration, and controls are not.
   function Valid_Object_Delete_ETag_Condition
     (Value : String) return Boolean;

   --  Evaluate every conditional DeleteObjects member against one catalog
   --  snapshot. An unconditioned missing key is an idempotent success, while
   --  a conditioned missing key is Not_Found. Last_Modified_Time is already
   --  parsed to signed Unix seconds by the protocol boundary.
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
   type Bucket_Versioning_Status is
     (Versioning_Unconfigured, Versioning_Enabled, Versioning_Suspended);

   --  Persisted MFA-delete state. The storage contract can preserve this
   --  value, but an S3 boundary must not accept a change without independently
   --  enforcing its MFA policy.
   type MFA_Delete_Status is
     (MFA_Delete_Unconfigured, MFA_Delete_Enabled, MFA_Delete_Disabled);

   --  Atomic configuration associated with one bucket. This controls only
   --  configuration reporting until version creation and retrieval are
   --  implemented separately.
   type Bucket_Versioning_Configuration is record
      Status     : Bucket_Versioning_Status := Versioning_Unconfigured;
      MFA_Delete : MFA_Delete_Status := MFA_Delete_Unconfigured;
   end record;

   --  Merge independently optional configuration fields. An Unconfigured
   --  update field preserves the current field.
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
   function Listing_Matches_Prefix
     (Key, Prefix : String) return Boolean;

   function Listing_Follows_Cursor
     (Projected_Key, After : String) return Boolean;

   --  Requested object byte interval. Backends resolve this request against
   --  the same immutable object snapshot that they stream, including suffix
   --  requests, so callers never need a racy Head_Object/Get_Object pair.
   type Byte_Range_Kind is
     (Whole_Range, Bounded_Range, Open_Ended_Range, Suffix_Range);

   type Byte_Range is record
      Kind  : Byte_Range_Kind := Whole_Range;
      First : Byte_Count := 0;
      Last  : Byte_Count := 0;
      Count : Byte_Count := 0;
   end record;

   --  Complete object body range.
   Whole_Object : constant Byte_Range := (others => <>);

   type Range_Resolution_Kind is
     (Empty_Object_Range, Satisfied_Range, Unsatisfiable_Range);

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

   --  Metadata retained with one committed object version.
   type Object_Information is record
      Size          : Byte_Count := 0;
      Modified      : Unix_Time := 0;
      Entity_Tag    : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type  : Ada.Strings.Unbounded.Unbounded_String;
      Version       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One S3 object tag. The wire boundary validates the documented UTF-8
   --  character repertoire and byte limits before a value reaches a backend.
   Maximum_Object_Tags : constant := 10;
   subtype Object_Tag_Count is Natural range 0 .. Maximum_Object_Tags;
   subtype Object_Tag_Index is Positive range 1 .. Maximum_Object_Tags;

   type Object_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Object_Tag_Array is array (Object_Tag_Index) of Object_Tag;

   --  Fixed-capacity representation keeps the backend contract bounded and
   --  permits an entire tag set to be copied under one publication boundary.
   type Object_Tag_Set is record
      Length : Object_Tag_Count := 0;
      Items  : Object_Tag_Array;
   end record;

   Empty_Object_Tags : constant Object_Tag_Set;

   --  Backend-safe byte bounds shared by all protocol adapters. This does not
   --  replace S3's stricter Unicode repertoire validation.
   function Valid_Object_Tag_Set (Tags : Object_Tag_Set) return Boolean;

   --  Metadata supplied when committing an object. An empty Entity_Tag asks
   --  the backend to generate the ordinary single-part S3 MD5 entity tag.
   --  This identifier is not a collision-resistant integrity checksum.
   type Put_Options is record
      Entity_Tag   : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
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
   Empty_Object_Tags : constant Object_Tag_Set := (others => <>);
   Default_Put_Options : constant Put_Options :=
     (Entity_Tag   => Ada.Strings.Unbounded.Null_Unbounded_String,
      Content_Type =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"));
end Flyology.Object_Storage;
