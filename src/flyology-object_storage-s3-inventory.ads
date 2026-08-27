with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 inventory configurations.
package Flyology.Object_Storage.S3.Inventory is

   --  Raised when a document violates the pinned inventory model.
   Malformed_Inventory : exception;

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text when present
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Pinned InventoryFormat wire domain.
   --  @enum CSV CSV inventory output
   --  @enum ORC ORC inventory output
   --  @enum Parquet Parquet inventory output
   type Inventory_Format is (CSV, ORC, Parquet);

   --  Pinned InventoryFrequency wire domain.
   --  @enum Daily Daily inventory generation
   --  @enum Weekly Weekly inventory generation
   type Inventory_Frequency is (Daily, Weekly);

   --  Pinned InventoryIncludedObjectVersions wire domain. Ada's reserved
   --  word `all` requires descriptive literals while comments retain the
   --  exact external values.
   --  @enum All_Versions Exact All wire value
   --  @enum Current_Versions Exact Current wire value
   type Included_Object_Versions is (All_Versions, Current_Versions);

   --  Pinned InventoryOptionalField wire domain.
   --  @enum Size Size
   --  @enum Last_Modified_Date LastModifiedDate
   --  @enum Storage_Class StorageClass
   --  @enum ETag ETag
   --  @enum Is_Multipart_Uploaded IsMultipartUploaded
   --  @enum Replication_Status ReplicationStatus
   --  @enum Encryption_Status EncryptionStatus
   --  @enum Object_Lock_Retain_Until_Date ObjectLockRetainUntilDate
   --  @enum Object_Lock_Mode ObjectLockMode
   --  @enum Object_Lock_Legal_Hold_Status ObjectLockLegalHoldStatus
   --  @enum Intelligent_Tiering_Access_Tier IntelligentTieringAccessTier
   --  @enum Bucket_Key_Status BucketKeyStatus
   --  @enum Checksum_Algorithm ChecksumAlgorithm
   --  @enum Object_Access_Control_List ObjectAccessControlList
   --  @enum Object_Owner ObjectOwner
   --  @enum Lifecycle_Expiration_Date LifecycleExpirationDate
   type Optional_Field_Kind is
     (Size,
      Last_Modified_Date,
      Storage_Class,
      ETag,
      Is_Multipart_Uploaded,
      Replication_Status,
      Encryption_Status,
      Object_Lock_Retain_Until_Date,
      Object_Lock_Mode,
      Object_Lock_Legal_Hold_Status,
      Intelligent_Tiering_Access_Tier,
      Bucket_Key_Status,
      Checksum_Algorithm,
      Object_Access_Control_List,
      Object_Owner,
      Lifecycle_Expiration_Date);

   --  Ordered InventoryOptionalFields values bounded by caller XML limits.
   package Optional_Field_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Optional_Field_Kind);

   --  Optional inventory prefix filter. Prefix is required when Filter is
   --  present by the pinned structural model.
   --  @field Is_Set Whether Filter was present
   --  @field Prefix Exact required prefix when present
   type Inventory_Filter is record
      Is_Set : Boolean;
      Prefix : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence-preserving inventory encryption. The pinned model permits
   --  SSE-S3 and SSE-KMS independently and encodes no one-of constraint.
   --  @field Is_Set Whether Encryption was present
   --  @field SSE_S3 Whether the empty SSE-S3 member was present
   --  @field SSE_KMS_Key_ID Optional required KeyId within SSE-KMS
   type Inventory_Encryption is record
      Is_Set         : Boolean;
      SSE_S3         : Boolean;
      SSE_KMS_Key_ID : Optional_String;
   end record;

   --  Complete required inventory S3 destination.
   --  @field Account_ID Optional destination account identifier
   --  @field Bucket Required exact destination bucket ARN
   --  @field Format Exact modeled report format
   --  @field Prefix Optional destination prefix
   --  @field Encryption Optional complete modeled encryption structure
   type S3_Bucket_Destination is record
      Account_ID : Optional_String;
      Bucket     : Ada.Strings.Unbounded.Unbounded_String;
      Format     : Inventory_Format;
      Prefix     : Optional_String;
      Encryption : Inventory_Encryption;
   end record;

   --  Complete required inventory destination wrapper.
   --  @field S3_Bucket Complete required S3 destination
   type Inventory_Destination is record
      S3_Bucket : S3_Bucket_Destination;
   end record;

   --  Complete required inventory schedule.
   --  @field Frequency Exact modeled report frequency
   type Inventory_Schedule is record
      Frequency : Inventory_Frequency;
   end record;

   --  Complete inventory-configuration payload used by the single read and
   --  by each item in the paginated list response.
   --  @field Destination Required report destination
   --  @field Is_Enabled Required generation state
   --  @field Filter Optional exact prefix filter
   --  @field ID Required exact configuration identifier
   --  @field Versions Required object-version selection
   --  @field Optional_Fields Optional fields in wire order
   --  @field Schedule Required generation schedule
   type Inventory_Configuration is record
      Destination     : Inventory_Destination;
      Is_Enabled      : Boolean;
      Filter          : Inventory_Filter;
      ID              : Ada.Strings.Unbounded.Unbounded_String;
      Versions        : Included_Object_Versions;
      Optional_Fields : Optional_Field_Vectors.Vector;
      Schedule        : Inventory_Schedule;
   end record;

   --  Inventory configurations in exact response order. The caller's shared
   --  XML document and element limits bound one decoded page; this vector does
   --  not introduce a separate client-side page-size policy.
   package Configuration_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Inventory_Configuration);

   --  Complete ListBucketInventoryConfigurations response payload. Optional
   --  scalars preserve absence independently from empty or false values, and
   --  no cross-field relationship is inferred beyond the pinned model.
   --  @field Has_Is_Truncated Whether IsTruncated was present
   --  @field Is_Truncated Exact modeled value when present
   --  @field Continuation_Token Optional echoed request cursor
   --  @field Next_Continuation_Token Optional next-page cursor
   --  @field Configurations Configuration values in wire order
   type Inventory_Configuration_Page is record
      Has_Is_Truncated        : Boolean;
      Is_Truncated            : Boolean;
      Continuation_Token      : Optional_String;
      Next_Continuation_Token : Optional_String;
      Configurations          : Configuration_Vectors.Vector;
   end record;

   --  Parse one exact nonempty GetBucketInventoryConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving inventory graph
   --  @exception Malformed_Inventory Document violates the pinned model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Inventory_Configuration;

   --  Parse one exact ListBucketInventoryConfigurations payload through the
   --  shared paginated REST/XML envelope and the same reviewed item decoder.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving inventory page
   --  @exception Malformed_Inventory Document violates the pinned model
   function Parse_List
     (Document : String; Limits : XML.Parse_Limits)
      return Inventory_Configuration_Page;

end Flyology.Object_Storage.S3.Inventory;
