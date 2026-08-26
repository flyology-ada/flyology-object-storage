with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for current S3 bucket-replication configurations.
package Flyology.Object_Storage.S3.Replication is

   --  Raised when a document violates the pinned replication model.
   Malformed_Replication : exception;

   --  Exact Enabled/Disabled wire domain shared by replication controls.
   --  @enum Enabled Exact Enabled wire value
   --  @enum Disabled Exact Disabled wire value
   type Status_Kind is (Enabled, Disabled);

   --  Exact destination storage-class wire domain from the pinned model.
   --  @enum Standard STANDARD
   --  @enum Reduced_Redundancy REDUCED_REDUNDANCY
   --  @enum Standard_IA STANDARD_IA
   --  @enum One_Zone_IA ONEZONE_IA
   --  @enum Intelligent_Tiering INTELLIGENT_TIERING
   --  @enum Glacier GLACIER
   --  @enum Deep_Archive DEEP_ARCHIVE
   --  @enum Outposts OUTPOSTS
   --  @enum Glacier_Instant_Retrieval GLACIER_IR
   --  @enum Snow SNOW
   --  @enum Express_One_Zone EXPRESS_ONEZONE
   --  @enum FSX_OpenZFS FSX_OPENZFS
   --  @enum FSX_ONTAP FSX_ONTAP
   --  @enum AWS_Backup_Warm AWS_BACKUP_WARM
   --  @enum AWS_Backup_Low_Cost_Warm AWS_BACKUP_LOW_COST_WARM
   type Storage_Class_Kind is
     (Standard, Reduced_Redundancy, Standard_IA, One_Zone_IA,
      Intelligent_Tiering, Glacier, Deep_Archive, Outposts,
      Glacier_Instant_Retrieval, Snow, Express_One_Zone, FSX_OpenZFS,
      FSX_ONTAP, AWS_Backup_Warm, AWS_Backup_Low_Cost_Warm);

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the member was present
   --  @field Value Exact decoded text
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Presence-preserving arbitrary-precision signed decimal text.
   --  @field Is_Set Whether the member was present
   --  @field Text Exact validated decimal wire text
   type Optional_Integer_Text is record
      Is_Set : Boolean;
      Text   : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One required replication tag.
   --  @field Key Exact required key
   --  @field Value Exact required value
   type Replication_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional replication tag wrapper.
   --  @field Is_Set Whether Tag was present
   --  @field Value Complete required tag when present
   type Optional_Tag is record
      Is_Set : Boolean;
      Value  : Replication_Tag;
   end record;

   --  Ordered tags bounded by the caller-selected XML limits.
   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Replication_Tag);

   --  Optional logical-And replication filter.
   --  @field Is_Set Whether And was present
   --  @field Prefix Optional exact prefix
   --  @field Tags Direct Tag values in wire order
   type Replication_And is record
      Is_Set : Boolean;
      Prefix : Optional_String;
      Tags   : Tag_Vectors.Vector;
   end record;

   --  Optional exact replication rule filter.
   --  @field Is_Set Whether Filter was present
   --  @field Prefix Optional exact prefix
   --  @field Tag Optional exact required tag
   --  @field And_Predicates Optional logical-And structure
   type Replication_Filter is record
      Is_Set         : Boolean;
      Prefix         : Optional_String;
      Tag            : Optional_Tag;
      And_Predicates : Replication_And;
   end record;

   --  Presence-preserving optional status structure. Some enclosing model
   --  shapes require Status when present; DeleteMarkerReplication does not.
   --  @field Is_Set Whether the enclosing structure was present
   --  @field Status_Is_Set Whether Status was present in that structure
   --  @field Status Exact Enabled/Disabled value when present
   type Optional_Status is record
      Is_Set        : Boolean;
      Status_Is_Set : Boolean;
      Status        : Status_Kind;
   end record;

   --  Optional source-selection criteria.
   --  @field Is_Set Whether SourceSelectionCriteria was present
   --  @field SSE_KMS_Encrypted_Objects Optional required-status member
   --  @field Replica_Modifications Optional required-status member
   type Source_Selection_Criteria is record
      Is_Set                    : Boolean;
      SSE_KMS_Encrypted_Objects : Optional_Status;
      Replica_Modifications     : Optional_Status;
   end record;

   --  Optional destination access-control translation. The pinned Owner
   --  domain has one exact value, Destination, so presence proves that value.
   --  @field Is_Set Whether AccessControlTranslation was present
   type Access_Control_Translation is record
      Is_Set : Boolean;
   end record;

   --  Optional destination encryption configuration.
   --  @field Is_Set Whether EncryptionConfiguration was present
   --  @field Replica_KMS_Key_ID Optional exact key identifier
   type Encryption_Configuration is record
      Is_Set             : Boolean;
      Replica_KMS_Key_ID : Optional_String;
   end record;

   --  Presence-preserving replication-time value.
   --  @field Is_Set Whether the structure was present
   --  @field Minutes Optional arbitrary-precision minute count
   type Replication_Time_Value is record
      Is_Set  : Boolean;
      Minutes : Optional_Integer_Text;
   end record;

   --  Optional replication-time control; Status and Time are required when
   --  the enclosing structure is present.
   --  @field Is_Set Whether ReplicationTime was present
   --  @field Status Required Enabled/Disabled value
   --  @field Time Required time structure
   type Replication_Time is record
      Is_Set : Boolean;
      Status : Status_Kind;
      Time   : Replication_Time_Value;
   end record;

   --  Optional replication metrics; Status is required when present.
   --  @field Is_Set Whether Metrics was present
   --  @field Status Required Enabled/Disabled value
   --  @field Event_Threshold Optional threshold structure
   type Replication_Metrics is record
      Is_Set          : Boolean;
      Status          : Status_Kind;
      Event_Threshold : Replication_Time_Value;
   end record;

   --  Required destination plus all optional modeled destination controls.
   --  @field Bucket Required exact destination bucket ARN/name text
   --  @field Account Optional exact account identifier
   --  @field Storage_Class_Is_Set Whether StorageClass was present
   --  @field Storage_Class Exact storage class when present
   --  @field Access_Control Optional owner translation
   --  @field Encryption Optional replica KMS configuration
   --  @field Time Optional replication-time control
   --  @field Metrics Optional replication metrics
   type Destination is record
      Bucket               : Ada.Strings.Unbounded.Unbounded_String;
      Account              : Optional_String;
      Storage_Class_Is_Set : Boolean;
      Storage_Class        : Storage_Class_Kind;
      Access_Control       : Access_Control_Translation;
      Encryption           : Encryption_Configuration;
      Time                 : Replication_Time;
      Metrics              : Replication_Metrics;
   end record;

   --  One exact replication rule. Status and Destination are required.
   --  @field ID Optional exact rule identifier
   --  @field Priority Optional arbitrary-precision priority
   --  @field Prefix Optional legacy prefix
   --  @field Filter Optional current filter
   --  @field Status Required rule status
   --  @field Source_Selection Optional source-selection criteria
   --  @field Existing_Object_Replication Optional required-status structure
   --  @field Target Required destination
   --  @field Delete_Marker_Replication Optional structure whose Status is
   --     independently optional in the pinned model
   type Replication_Rule is record
      ID                          : Optional_String;
      Priority                    : Optional_Integer_Text;
      Prefix                      : Optional_String;
      Filter                      : Replication_Filter;
      Status                      : Status_Kind;
      Source_Selection            : Source_Selection_Criteria;
      Existing_Object_Replication : Optional_Status;
      Target                      : Destination;
      Delete_Marker_Replication   : Optional_Status;
   end record;

   --  Ordered rules bounded by caller-selected XML limits.
   package Rule_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Replication_Rule);

   --  Complete current replication configuration.
   --  @field Role Required exact IAM role text
   --  @field Rules Required nonempty flattened Rule values in wire order
   type Replication_Configuration is record
      Role  : Ada.Strings.Unbounded.Unbounded_String;
      Rules : Rule_Vectors.Vector;
   end record;

   --  Parse one exact nonempty GetBucketReplication response payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving replication graph
   --  @exception Malformed_Replication Document violates the pinned model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Replication_Configuration;

   --  Serialize one exact PutBucketReplication payload. Required structural
   --  members and presence wrappers come from the pinned service model; the
   --  serializer does not select prose-only cross-field policy.
   --  @param Value Complete presence-sensitive replication configuration
   --  @param Limits Caller-selected XML serialization limits
   --  @return Exact namespaced REST/XML request payload
   --  @exception Malformed_Replication Value violates the pinned input model
   function Serialize
     (Value  : Replication_Configuration;
      Limits : XML.Parse_Limits) return String;

end Flyology.Object_Storage.S3.Replication;
