with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 bucket logging status reads.
package Flyology.Object_Storage.S3.Logging is

   --  Raised when a document violates the pinned logging model.
   Malformed_Logging : exception;

   --  Exact pinned BucketLogsPermission wire domain.
   --  @enum Full_Control Exact FULL_CONTROL wire value
   --  @enum Read Exact READ wire value
   --  @enum Write Exact WRITE wire value
   type Logging_Permission is (Full_Control, Read, Write);

   --  Presence-preserving optional logging permission.
   --  @field Is_Set Whether Permission was present
   --  @field Value Exact permission when present
   type Optional_Permission is record
      Is_Set : Boolean;
      Value  : Logging_Permission;
   end record;

   --  One TargetGrants member. Both members are independently optional in
   --  the pinned structural model.
   --  @field Principal Optional exact shared S3 grantee
   --  @field Permission Optional exact logging permission
   type Target_Grant is record
      Principal  : S3.ACL.Grantee;
      Permission : Optional_Permission;
   end record;

   --  Ordered TargetGrant values bounded by caller-selected XML limits.
   package Target_Grant_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Target_Grant);

   --  Optional TargetGrants wrapper and ordered Grant values.
   --  @field Is_Set Whether TargetGrants was present
   --  @field Grants Exact grants in wire order
   type Target_Grants is record
      Is_Set : Boolean;
      Grants : Target_Grant_Vectors.Vector;
   end record;

   --  Exact pinned PartitionDateSource wire domain.
   --  @enum Event_Time Exact EventTime wire value
   --  @enum Delivery_Time Exact DeliveryTime wire value
   type Partition_Date_Source is (Event_Time, Delivery_Time);

   --  Presence-preserving optional partition date source.
   --  @field Is_Set Whether PartitionDateSource was present
   --  @field Value Exact source when present
   type Optional_Partition_Date_Source is record
      Is_Set : Boolean;
      Value  : Partition_Date_Source;
   end record;

   --  Optional target-key format. The pinned structural model permits the
   --  empty SimplePrefix and PartitionedPrefix members independently and does
   --  not encode an additional one-of rule.
   --  @field Is_Set Whether TargetObjectKeyFormat was present
   --  @field Simple_Prefix Whether the empty SimplePrefix member was present
   --  @field Partitioned_Prefix Whether PartitionedPrefix was present
   --  @field Date_Source Optional partition date source
   type Target_Object_Key_Format is record
      Is_Set             : Boolean;
      Simple_Prefix      : Boolean;
      Partitioned_Prefix : Boolean;
      Date_Source        : Optional_Partition_Date_Source;
   end record;

   --  Presence-preserving GetBucketLogging payload. An absent LoggingEnabled
   --  member is the modeled successful disabled state, not a missing resource.
   --  @field Is_Enabled Whether LoggingEnabled was present
   --  @field Target_Bucket Required target bucket when enabled
   --  @field Grants Optional ordered target grants
   --  @field Target_Prefix Required target prefix when enabled
   --  @field Key_Format Optional modeled target-key format
   type Logging_Status is record
      Is_Enabled    : Boolean;
      Target_Bucket : Ada.Strings.Unbounded.Unbounded_String;
      Grants        : Target_Grants;
      Target_Prefix : Ada.Strings.Unbounded.Unbounded_String;
      Key_Format    : Target_Object_Key_Format;
   end record;

   --  Parse one exact nonempty GetBucketLogging payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving bucket logging status
   --  @exception Malformed_Logging Document violates the pinned model
   function Parse
     (Document : String; Limits : S3.XML.Parse_Limits)
      return Logging_Status;

end Flyology.Object_Storage.S3.Logging;
