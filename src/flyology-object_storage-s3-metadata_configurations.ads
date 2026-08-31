with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 bucket metadata configurations.
package Flyology.Object_Storage.S3.Metadata_Configurations is

   --  Raised when a response violates the pinned metadata model.
   Malformed_Metadata_Configuration : exception;

   --  Presence-preserving optional string. Empty text remains distinct from
   --  absence because the pinned string shapes have no minimum length.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence-preserving arbitrary-precision signed decimal text. The
   --  pinned integer shape establishes no machine-sized bound.
   --  @field Is_Set Whether the modeled member was present
   --  @field Text Exact validated signed decimal wire text
   type Optional_Integer_Text is record
      Is_Set : Boolean;
      Text   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Exact pinned annotation-table configuration state wire domain.
   --  @enum Annotation_Enabled Exact ENABLED wire value
   --  @enum Annotation_Disabled Exact DISABLED wire value
   type Annotation_Configuration_State is
     (Annotation_Enabled, Annotation_Disabled);

   --  Exact pinned inventory-table configuration state wire domain.
   --  @enum Inventory_Enabled Exact ENABLED wire value
   --  @enum Inventory_Disabled Exact DISABLED wire value
   type Inventory_Configuration_State is
     (Inventory_Enabled, Inventory_Disabled);

   --  Exact pinned record-expiration state wire domain.
   --  @enum Expiration_Enabled Exact ENABLED wire value
   --  @enum Expiration_Disabled Exact DISABLED wire value
   type Expiration_State is (Expiration_Enabled, Expiration_Disabled);

   --  Exact pinned S3 Tables bucket ownership wire domain.
   --  @enum AWS_Table_Bucket Exact aws wire value
   --  @enum Customer_Table_Bucket Exact customer wire value
   type S3_Tables_Bucket_Type is (AWS_Table_Bucket, Customer_Table_Bucket);

   --  Presence-preserving optional S3 Tables bucket ownership value.
   --  @field Is_Set Whether TableBucketType was present
   --  @field Value Exact decoded wire value when present
   type Optional_S3_Tables_Bucket_Type is record
      Is_Set : Boolean;
      Value  : S3_Tables_Bucket_Type;
   end record;

   --  Optional provider error nested in a successful table result.
   --  @field Is_Set Whether Error was present
   --  @field Code Optional exact provider error code
   --  @field Message Optional exact provider error message
   type Error_Details is record
      Is_Set  : Boolean;
      Code    : Optional_String;
      Message : Optional_String;
   end record;

   --  Required metadata destination with optional model members preserved.
   --  @field Table_Bucket_Type Optional exact table-bucket ownership value
   --  @field Table_Bucket_ARN Optional exact table-bucket ARN
   --  @field Table_Namespace Optional exact table namespace
   type Destination_Result is record
      Table_Bucket_Type : Optional_S3_Tables_Bucket_Type;
      Table_Bucket_ARN  : Optional_String;
      Table_Namespace   : Optional_String;
   end record;

   --  Required journal-table record-expiration policy.
   --  @field Expiration Exact required expiration state
   --  @field Days Optional validated arbitrary-precision day count
   type Record_Expiration is record
      Expiration : Expiration_State;
      Days       : Optional_Integer_Text;
   end record;

   --  Presence-preserving journal-table result.
   --  @field Is_Set Whether JournalTableConfigurationResult was present
   --  @field Table_Status Exact required opaque provider status
   --  @field Error Optional nested provider error
   --  @field Table_Name Exact required opaque table name
   --  @field Table_ARN Optional exact table ARN
   --  @field Expiration Required record-expiration policy when present
   type Journal_Table_Result is record
      Is_Set       : Boolean;
      Table_Status : Ada.Strings.Unbounded.Unbounded_String;
      Error        : Error_Details;
      Table_Name   : Ada.Strings.Unbounded.Unbounded_String;
      Table_ARN    : Optional_String;
      Expiration   : Record_Expiration;
   end record;

   --  Presence-preserving inventory-table result.
   --  @field Is_Set Whether InventoryTableConfigurationResult was present
   --  @field Configuration_State Exact required configuration state
   --  @field Table_Status Optional opaque provider status
   --  @field Error Optional nested provider error
   --  @field Table_Name Optional exact table name
   --  @field Table_ARN Optional exact table ARN
   type Inventory_Table_Result is record
      Is_Set              : Boolean;
      Configuration_State : Inventory_Configuration_State;
      Table_Status        : Optional_String;
      Error               : Error_Details;
      Table_Name          : Optional_String;
      Table_ARN           : Optional_String;
   end record;

   --  Presence-preserving annotation-table result.
   --  @field Is_Set Whether AnnotationTableConfigurationResult was present
   --  @field Configuration_State Exact required configuration state
   --  @field Table_Status Optional opaque provider status
   --  @field Error Optional nested provider error
   --  @field Table_Name Optional exact table name
   --  @field Table_ARN Optional exact table ARN
   --  @field Role Optional exact role identifier
   type Annotation_Table_Result is record
      Is_Set              : Boolean;
      Configuration_State : Annotation_Configuration_State;
      Table_Status        : Optional_String;
      Error               : Error_Details;
      Table_Name          : Optional_String;
      Table_ARN           : Optional_String;
      Role                : Optional_String;
   end record;

   --  Complete required GetBucketMetadataConfiguration result.
   --  @field Destination Required destination result
   --  @field Journal Optional journal-table result
   --  @field Inventory Optional inventory-table result
   --  @field Annotation Optional annotation-table result
   type Metadata_Configuration is record
      Destination : Destination_Result;
      Journal     : Journal_Table_Result;
      Inventory   : Inventory_Table_Result;
      Annotation  : Annotation_Table_Result;
   end record;

   --  Exact pinned server-side-encryption algorithm for metadata tables.
   --  @enum Metadata_SSE_KMS Exact aws:kms wire value
   --  @enum Metadata_SSE_S3 Exact AES256 wire value
   type Metadata_Table_SSE_Algorithm is
     (Metadata_SSE_KMS, Metadata_SSE_S3);

   --  Presence-preserving metadata-table encryption configuration.
   --  @field Is_Set Whether EncryptionConfiguration is present
   --  @field Algorithm Required algorithm when present
   --  @field KMS_Key_ARN Optional exact KMS key ARN
   type Metadata_Table_Encryption is record
      Is_Set      : Boolean;
      Algorithm   : Metadata_Table_SSE_Algorithm;
      KMS_Key_ARN : Optional_String;
   end record;

   --  Required journal-table configuration for metadata creation.
   --  @field Expiration Required record-expiration policy
   --  @field Encryption Optional exact table-encryption configuration
   type Journal_Table_Configuration is record
      Expiration : Record_Expiration;
      Encryption : Metadata_Table_Encryption;
   end record;

   --  Optional inventory-table configuration for metadata creation.
   --  @field Is_Set Whether InventoryTableConfiguration is present
   --  @field Configuration_State Required state when present
   --  @field Encryption Optional exact table-encryption configuration
   type Inventory_Table_Configuration is record
      Is_Set              : Boolean;
      Configuration_State : Inventory_Configuration_State;
      Encryption          : Metadata_Table_Encryption;
   end record;

   --  Optional annotation-table configuration for metadata creation.
   --  @field Is_Set Whether AnnotationTableConfiguration is present
   --  @field Configuration_State Required state when present
   --  @field Encryption Optional exact table-encryption configuration
   --  @field Role Optional exact role identifier
   type Annotation_Table_Configuration is record
      Is_Set              : Boolean;
      Configuration_State : Annotation_Configuration_State;
      Encryption          : Metadata_Table_Encryption;
      Role                : Optional_String;
   end record;

   --  Complete CreateBucketMetadataConfiguration request payload.
   --  @field Journal Required journal-table configuration
   --  @field Inventory Optional inventory-table configuration
   --  @field Annotation Optional annotation-table configuration
   type Metadata_Configuration_Request is record
      Journal    : Journal_Table_Configuration;
      Inventory  : Inventory_Table_Configuration;
      Annotation : Annotation_Table_Configuration;
   end record;

   --  Parse one exact nonempty GetBucketMetadataConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving metadata configuration
   --  @exception Malformed_Metadata_Configuration Document violates model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Metadata_Configuration;

   --  Serialize one exact CreateBucketMetadataConfiguration payload.
   --  @param Value Complete caller-selected metadata configuration
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Metadata_Configuration Value violates the model
   function Serialize_Create
     (Value  : Metadata_Configuration_Request;
      Limits : XML.Parse_Limits) return String;

   --  Serialize one exact UpdateBucketMetadataInventoryTableConfiguration
   --  payload. Value.Is_Set must be true because the model requires the
   --  payload member; the flag remains presence-preserving for create calls.
   --  @param Value Complete caller-selected inventory-table update
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Metadata_Configuration Value violates the model
   function Serialize_Update_Inventory
     (Value  : Inventory_Table_Configuration;
      Limits : XML.Parse_Limits) return String;

   --  Serialize one exact UpdateBucketMetadataJournalTableConfiguration
   --  payload.
   --  @param Value Complete caller-selected record-expiration update
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Metadata_Configuration Value violates the model
   function Serialize_Update_Journal
     (Value  : Record_Expiration;
      Limits : XML.Parse_Limits) return String;

   --  Serialize one exact UpdateBucketMetadataAnnotationTableConfiguration
   --  payload. Value.Is_Set must be true because the model requires the
   --  payload member; the flag remains presence-preserving for create calls.
   --  @param Value Complete caller-selected annotation-table update
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Metadata_Configuration Value violates the model
   function Serialize_Update_Annotation
     (Value  : Annotation_Table_Configuration;
      Limits : XML.Parse_Limits) return String;

end Flyology.Object_Storage.S3.Metadata_Configurations;
