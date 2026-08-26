with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for current S3 bucket-lifecycle configurations.
package Flyology.Object_Storage.S3.Lifecycle is

   --  Raised when a response violates the pinned lifecycle model.
   Malformed_Lifecycle : exception;

   --  Exact pinned lifecycle rule status wire domain.
   --  @enum Rule_Enabled Exact Enabled wire value
   --  @enum Rule_Disabled Exact Disabled wire value
   type Rule_Status is (Rule_Enabled, Rule_Disabled);

   --  Exact pinned transition storage-class wire domain.
   --  @enum Glacier Exact GLACIER wire value
   --  @enum Standard_IA Exact STANDARD_IA wire value
   --  @enum One_Zone_IA Exact ONEZONE_IA wire value
   --  @enum Intelligent_Tiering Exact INTELLIGENT_TIERING wire value
   --  @enum Deep_Archive Exact DEEP_ARCHIVE wire value
   --  @enum Glacier_Instant_Retrieval Exact GLACIER_IR wire value
   type Transition_Storage_Class is
     (Glacier, Standard_IA, One_Zone_IA, Intelligent_Tiering,
      Deep_Archive, Glacier_Instant_Retrieval);

   --  Presence-preserving pinned response-header domain.
   --  @enum Transition_Minimum_Absent Header was absent
   --  @enum Varies_By_Storage_Class Exact varies_by_storage_class value
   --  @enum All_Storage_Classes_128K Exact all_storage_classes_128K value
   type Transition_Default_Minimum_Size is
     (Transition_Minimum_Absent, Varies_By_Storage_Class,
      All_Storage_Classes_128K);

   --  Presence-preserving optional string. Empty text remains distinct from
   --  absence because the pinned string shapes have no minimum length.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text
   type Optional_String is record
      Is_Set : Boolean := False;
      Value  : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Presence-preserving arbitrary-precision signed decimal text. The
   --  pinned integer and long shapes establish no machine-sized bound.
   --  @field Is_Set Whether the modeled member was present
   --  @field Text Exact validated signed decimal wire text
   type Optional_Integer_Text is record
      Is_Set : Boolean := False;
      Text   : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Presence-preserving exact ISO-8601 timestamp text.
   --  @field Is_Set Whether the modeled Date member was present
   --  @field Text Exact validated timestamp
   type Optional_Timestamp is record
      Is_Set : Boolean := False;
      Text   : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Presence-preserving optional Boolean.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded value, meaningful only when present
   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  One required Key/Value lifecycle tag.
   --  @field Key Exact required key text
   --  @field Value Exact required value text
   type Lifecycle_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional lifecycle tag wrapper.
   --  @field Is_Set Whether the Tag structure was present
   --  @field Value Complete required Key/Value pair when present
   type Optional_Lifecycle_Tag is record
      Is_Set : Boolean := False;
      Value  : Lifecycle_Tag;
   end record;

   --  Dynamically sized tag storage bounded by caller-selected XML limits.
   package Lifecycle_Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Lifecycle_Tag);

   --  Optional logical-And lifecycle filter.
   --  @field Is_Set Whether the And structure was present
   --  @field Prefix Optional exact prefix
   --  @field Tags Direct Tag values in wire order
   --  @field Object_Size_Greater_Than Optional arbitrary-precision bound
   --  @field Object_Size_Less_Than Optional arbitrary-precision bound
   type Lifecycle_And is record
      Is_Set                   : Boolean := False;
      Prefix                   : Optional_String;
      Tags                     : Lifecycle_Tag_Vectors.Vector;
      Object_Size_Greater_Than : Optional_Integer_Text;
      Object_Size_Less_Than    : Optional_Integer_Text;
   end record;

   --  Optional exact lifecycle rule filter. Empty Filter is distinct from
   --  absence and denotes the model's all-objects form.
   --  @field Is_Set Whether Filter was present
   --  @field Prefix Optional exact prefix
   --  @field Tag Optional required Key/Value tag
   --  @field Object_Size_Greater_Than Optional arbitrary-precision bound
   --  @field Object_Size_Less_Than Optional arbitrary-precision bound
   --  @field And_Predicates Optional logical-And predicate structure
   type Lifecycle_Filter is record
      Is_Set                   : Boolean := False;
      Prefix                   : Optional_String;
      Tag                      : Optional_Lifecycle_Tag;
      Object_Size_Greater_Than : Optional_Integer_Text;
      Object_Size_Less_Than    : Optional_Integer_Text;
      And_Predicates           : Lifecycle_And;
   end record;

   --  Optional current-version expiration action.
   --  @field Is_Set Whether Expiration was present
   --  @field Date Optional exact ISO-8601 date-time
   --  @field Days Optional arbitrary-precision day count
   --  @field Expired_Object_Delete_Marker Optional exact Boolean
   type Lifecycle_Expiration is record
      Is_Set                       : Boolean := False;
      Date                         : Optional_Timestamp;
      Days                         : Optional_Integer_Text;
      Expired_Object_Delete_Marker : Optional_Boolean;
   end record;

   --  One current-version transition action.
   --  The Glacier initializer is parser scratch only; Storage_Class_Is_Set
   --  determines whether the optional member existed.
   --  @field Date Optional exact ISO-8601 date-time
   --  @field Days Optional arbitrary-precision day count
   --  @field Storage_Class_Is_Set Whether StorageClass was present
   --  @field Storage_Class Exact transition class when present
   type Lifecycle_Transition is record
      Date                 : Optional_Timestamp;
      Days                 : Optional_Integer_Text;
      Storage_Class_Is_Set : Boolean := False;
      Storage_Class        : Transition_Storage_Class := Glacier;
   end record;

   --  Dynamically sized current-transition storage bounded by caller-selected
   --  shared XML limits.
   package Lifecycle_Transition_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Lifecycle_Transition);

   --  One noncurrent-version transition action.
   --  @field Noncurrent_Days Optional arbitrary-precision day count
   --  @field Storage_Class_Is_Set Whether StorageClass was present
   --  @field Storage_Class Exact transition class when present
   --  @field Newer_Noncurrent_Versions Optional arbitrary-precision count
   type Noncurrent_Transition is record
      Noncurrent_Days             : Optional_Integer_Text;
      Storage_Class_Is_Set        : Boolean := False;
      Storage_Class               : Transition_Storage_Class := Glacier;
      Newer_Noncurrent_Versions   : Optional_Integer_Text;
   end record;

   --  Dynamically sized noncurrent-transition storage bounded by
   --  caller-selected shared XML limits.
   package Noncurrent_Transition_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Noncurrent_Transition);

   --  Optional noncurrent-version expiration action.
   --  @field Is_Set Whether NoncurrentVersionExpiration was present
   --  @field Noncurrent_Days Optional arbitrary-precision day count
   --  @field Newer_Noncurrent_Versions Optional arbitrary-precision count
   type Noncurrent_Expiration_Action is record
      Is_Set                       : Boolean := False;
      Noncurrent_Days              : Optional_Integer_Text;
      Newer_Noncurrent_Versions    : Optional_Integer_Text;
   end record;

   --  Optional incomplete-multipart abort action.
   --  @field Is_Set Whether AbortIncompleteMultipartUpload was present
   --  @field Days_After_Initiation Optional arbitrary-precision day count
   type Abort_Incomplete_Multipart is record
      Is_Set                : Boolean := False;
      Days_After_Initiation : Optional_Integer_Text;
   end record;

   --  One exact LifecycleRule. Status is required whenever a Rule is present;
   --  Rule_Disabled is deterministic parser scratch until Status is decoded.
   --  @field Expiration Optional current-version expiration action
   --  @field ID Optional exact rule identifier
   --  @field Prefix Optional deprecated exact prefix member
   --  @field Filter Optional current filter structure
   --  @field Status Required exact Enabled/Disabled value
   --  @field Transitions Flattened Transition values in wire order
   --  @field Noncurrent_Transitions Flattened noncurrent transitions
   --  @field Noncurrent_Expiration Optional noncurrent expiration action
   --  @field Abort_Incomplete Optional incomplete multipart abort action
   type Lifecycle_Rule is record
      Expiration             : Lifecycle_Expiration;
      ID                     : Optional_String;
      Prefix                 : Optional_String;
      Filter                 : Lifecycle_Filter;
      Status                 : Rule_Status := Rule_Disabled;
      Transitions            : Lifecycle_Transition_Vectors.Vector;
      Noncurrent_Transitions : Noncurrent_Transition_Vectors.Vector;
      Noncurrent_Expiration  : Noncurrent_Expiration_Action;
      Abort_Incomplete       : Abort_Incomplete_Multipart;
   end record;

   --  Dynamically sized rule storage bounded by caller-selected shared XML
   --  limits.
   package Lifecycle_Rule_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Lifecycle_Rule);

   --  Presence-preserving GetBucketLifecycleConfiguration XML payload.
   --  @field Is_Set Whether a LifecycleConfiguration document was present
   --  @field Rules Flattened Rule values in wire order
   type Lifecycle_Configuration is record
      Is_Set : Boolean := False;
      Rules  : Lifecycle_Rule_Vectors.Vector;
   end record;

   --  Parse one exact nonempty GetBucketLifecycleConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present configuration with modeled presence preserved
   --  @exception Malformed_Lifecycle Document violates the pinned model
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Lifecycle_Configuration;

   --  Serialize one exact PutBucketLifecycleConfiguration payload.
   --  An absent configuration emits an empty body. When configuration is
   --  present, its required flattened Rule member is nonempty. Structural
   --  constraints come from the pinned service model; no prose-only
   --  lifecycle policy is selected here.
   --  @param Value Complete presence-sensitive lifecycle configuration
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Lifecycle Value violates the pinned input model
   function Serialize
     (Value  : Lifecycle_Configuration;
      Limits : XML.Parse_Limits) return String;

   --  Parse the optional exact
   --  x-amz-transition-default-minimum-object-size response header.
   --  @param Value Empty for absence or one exact pinned wire value
   --  @return Presence-preserving header value
   --  @exception Malformed_Lifecycle Value is not in the pinned domain
   function Parse_Transition_Default_Minimum_Size
     (Value : String) return Transition_Default_Minimum_Size;

end Flyology.Object_Storage.S3.Lifecycle;
