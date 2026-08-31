with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Typed CreateBucket REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Buckets is

   --  Raised when a modeled bucket configuration is internally inconsistent.
   Invalid_Bucket_Configuration : exception;

   --  Raised when a CreateBucket configuration document is malformed.
   Malformed_Bucket_Configuration : exception;

   --  Raised for a malformed or unsupported bucket-location value or document.
   Malformed_Bucket_Location : exception;

   --  Accepted max-buckets query value.
   subtype Max_Buckets_Value is Positive range 1 .. 10_000;

   --  Maximum accepted bucket-region query bytes.
   Maximum_Bucket_Region_Length : constant := 63;

   --  Maximum accepted ListBuckets continuation-token bytes.
   Maximum_Continuation_Token_Length : constant := 1_024;

   --  Parsed ListBuckets query parameters.
   --  @field Max_Buckets Requested maximum result count
   --  @field Has_Max_Buckets Whether max-buckets was supplied
   --  @field Continuation_Token Opaque continuation token
   --  @field Has_Continuation_Token Whether continuation-token was supplied
   --  @field Prefix Optional bucket-name prefix
   --  @field Has_Prefix Whether prefix was supplied
   --  @field Bucket_Region Optional exact bucket-region filter
   type List_Buckets_Request is record
      Max_Buckets            : Max_Buckets_Value := Max_Buckets_Value'Last;
      Has_Max_Buckets        : Boolean := False;
      Continuation_Token     : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix                 : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix             : Boolean := False;
      Bucket_Region          : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Raised when a ListBuckets query is malformed or exceeds its bounds.
   Malformed_List_Buckets_Request : exception;

   --  Parse raw query bytes after '?'. Empty is valid; percent escapes are
   --  strict, '+' stays literal, duplicates/unknowns fail, and x-id is
   --  accepted only as ListBuckets.
   --  @param Query Raw query bytes after the question mark
   --  @return Parsed bounded ListBuckets request
   function Parse_List_Buckets_Query
     (Query : String) return List_Buckets_Request;

   --  Result of validating and decoding a continuation token.
   --  @field Valid Whether the token matches the request and envelope
   --  @field After Exclusive bucket-name cursor when valid
   type Continuation_Result is record
      Valid : Boolean := False;
      After : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Encode a continuation token bound to the listing filters.
   --  @param Prefix Bucket-name prefix bound into the token
   --  @param Bucket_Region Bucket-region filter bound into the token
   --  @param After Exclusive bucket-name cursor
   --  @return Opaque continuation token bound to all three inputs
   function Encode_Continuation
     (Prefix, Bucket_Region, After : String) return String;

   --  Decode and validate a continuation token against listing filters.
   --  @param Token Candidate continuation token
   --  @param Prefix Expected bucket-name prefix
   --  @param Bucket_Region Expected bucket-region filter
   --  @return Validation result and decoded exclusive cursor
   function Decode_Continuation
     (Token, Prefix, Bucket_Region : String) return Continuation_Result;

   --  One CreateBucket tag.
   --  @field Key Tag key bytes
   --  @field Value Tag value bytes
   type Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Vector implementation used for CreateBucket tags.
   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Tag);

   --  Ordered CreateBucket tag collection.
   subtype Tag_List is Tag_Vectors.Vector;

   --  Every member of the pinned CreateBucketConfiguration shape. Empty
   --  paired fields mean that their containing XML structure is absent.
   --  @field Location_Constraint Legacy location constraint
   --  @field Location_Type Location structure type
   --  @field Location_Name Location structure name
   --  @field Data_Redundancy Bucket data-redundancy selection
   --  @field Bucket_Type Bucket type selection
   --  @field Tags Ordered CreateBucket tags
   type Create_Bucket_Configuration is record
      Location_Constraint : Ada.Strings.Unbounded.Unbounded_String;
      Location_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Location_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Data_Redundancy     : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Type         : Ada.Strings.Unbounded.Unbounded_String;
      Tags                : Tag_List;
   end record;

   --  Test whether a CreateBucket configuration has no present members.
   --  @param Value Candidate configuration
   --  @return True when every scalar is empty and Tags is empty
   function Is_Empty (Value : Create_Bucket_Configuration) return Boolean;

   --  Returns an empty string when the configuration is absent; otherwise
   --  emits the namespaced CreateBucketConfiguration document.
   --  @param Value Configuration to serialize
   --  @return Empty text or a namespaced configuration document
   function Serialize_Create_Configuration
     (Value : Create_Bucket_Configuration) return String;

   --  Parse the exact CreateBucketConfiguration shape. Empty input means the
   --  configuration member is absent. Unknown, duplicate, misplaced, or
   --  incomplete elements fail, as do documents outside the supplied limits.
   --  @param Document CreateBucket configuration XML or empty text
   --  @param Limits XML parsing limits
   --  @return Decoded configuration, empty when Document is empty
   function Parse_Create_Configuration
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Create_Bucket_Configuration;

   --  Legacy GetBucketLocation represents us-east-1 as an empty root value;
   --  EU remains the legacy spelling for eu-west-1. Other values follow the
   --  pinned AWS BucketLocationConstraint enumeration.
   --  @param Value Candidate legacy location-constraint value
   --  @return True when Value is an accepted location constraint
   function Valid_Location_Constraint (Value : String) return Boolean;

   --  The parser additionally accepts literal us-east-1 from compatible
   --  servers and the exact single-field CreateBucketConfiguration wrapper
   --  emitted by SeaweedFS 4.43. Serialization retains AWS's null scalar.
   --  @param Document GetBucketLocation response XML
   --  @param Limits XML parsing limits
   --  @return Decoded location constraint with legacy compatibility applied
   function Parse_Location_Constraint
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits) return String;

   --  Serialize one legacy GetBucketLocation response document.
   --  @param Region Canonical bucket region or legacy EU value
   --  @return Namespaced location-constraint XML
   function Serialize_Location_Constraint (Region : String) return String;

   --  Every member of the pinned ListBuckets Bucket structure. Empty values
   --  preserve optional-member absence exactly as received.
   --  @field Name Bucket name
   --  @field Creation_Date Modeled creation-date text
   --  @field Bucket_Region Optional bucket region
   --  @field Bucket_ARN Optional bucket ARN
   type Bucket_Entry is record
      Name          : Ada.Strings.Unbounded.Unbounded_String;
      Creation_Date : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Region : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_ARN    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Vector implementation used for listed bucket entries.
   package Bucket_Entry_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Bucket_Entry);

   --  Ordered list of bucket entries.
   subtype Bucket_List is Bucket_Entry_Vectors.Vector;

   --  ListBuckets owner structure.
   --  @field Display_Name Optional owner display name
   --  @field ID Owner identifier
   type Bucket_Owner is record
      Display_Name : Ada.Strings.Unbounded.Unbounded_String;
      ID           : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Every member of the pinned ListBuckets output shape. Presence flags
   --  distinguish absent structures/scalars from empty present values.
   --  @field Buckets Ordered bucket entries
   --  @field Has_Owner Whether the owner structure is present
   --  @field Owner Owner structure when present
   --  @field Continuation_Token Optional next-page token
   --  @field Has_Continuation_Token Whether the next-page token is present
   --  @field Prefix Optional echoed bucket-name prefix
   --  @field Has_Prefix Whether the echoed prefix is present
   type List_Buckets_Result is record
      Buckets            : Bucket_List;
      Has_Owner          : Boolean := False;
      Owner              : Bucket_Owner;
      Continuation_Token : Ada.Strings.Unbounded.Unbounded_String;
      Has_Continuation_Token : Boolean := False;
      Prefix             : Ada.Strings.Unbounded.Unbounded_String;
      Has_Prefix         : Boolean := False;
   end record;

   --  Raised when a ListBuckets result document is malformed.
   Malformed_Bucket_Listing : exception;

   --  Parse one bounded ListBuckets result document.
   --  @param Document ListBuckets result XML
   --  @param Limits XML parsing limits
   --  @return Decoded ListBuckets result
   function Parse_List_Buckets
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Buckets_Result;

   --  Serialize one ListBuckets result document.
   --  @param Value Result value to serialize
   --  @return Namespaced ListBuckets result XML
   function Serialize_List_Buckets
     (Value : List_Buckets_Result) return String;

end Flyology.Object_Storage.S3.Buckets;
