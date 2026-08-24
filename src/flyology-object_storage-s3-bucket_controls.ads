with Ada.Containers.Vectors;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codecs for small bucket-control configurations.
package Flyology.Object_Storage.S3.Bucket_Controls is

   Malformed_Configuration : exception;

   --  Pinned S3 model contract: absent preserves the optional output member;
   --  Enabled and Suspended are the two external wire values.
   --  @enum Accelerate_Status_Absent Status member was absent
   --  @enum Accelerate_Enabled Exact external Enabled value
   --  @enum Accelerate_Suspended Exact external Suspended value
   type Accelerate_Status is
     (Accelerate_Status_Absent, Accelerate_Enabled, Accelerate_Suspended);

   --  Pinned S3 model contract for the optional Get/PutBucketAbac Status.
   --  @enum Abac_Status_Absent Status member was absent
   --  @enum Abac_Enabled Exact external Enabled value
   --  @enum Abac_Disabled Exact external Disabled value
   type Abac_Status is (Abac_Status_Absent, Abac_Enabled, Abac_Disabled);

   --  Pinned S3 model contract: Payer is optional and has exactly the two
   --  external values below; changing the set changes response compatibility.
   --  @enum Payer_Absent Payer member was absent
   --  @enum Requester Exact external Requester value
   --  @enum Bucket_Owner Exact external BucketOwner value
   type Payer is (Payer_Absent, Requester, Bucket_Owner);

   --  Pinned ObjectOwnership enumeration.  Every decoded Rule requires one
   --  exact external value, so this type intentionally has no absent member.
   --  @enum Bucket_Owner_Preferred Exact BucketOwnerPreferred wire value
   --  @enum Object_Writer Exact ObjectWriter wire value
   --  @enum Bucket_Owner_Enforced Exact BucketOwnerEnforced wire value
   type Object_Ownership is
     (Bucket_Owner_Preferred, Object_Writer, Bucket_Owner_Enforced);

   --  One required member of the flattened OwnershipControls Rules list.
   --  @field Ownership Required exact object-ownership mode
   type Ownership_Control_Rule is record
      Ownership : Object_Ownership;
   end record;

   --  Dynamically sized rule storage bounded during decoding by the caller's
   --  shared XML element limit rather than by an invented list ceiling.
   package Ownership_Control_Rule_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Ownership_Control_Rule);

   --  Presence-preserving GetBucketOwnershipControls payload.  The vector is
   --  dynamically sized because the pinned list has no independent maximum;
   --  the caller-selected XML element limit bounds decoded population.
   --  @field Is_Set Whether the outer OwnershipControls payload was present
   --  @field Rules Required nonempty flattened Rule list when present
   type Ownership_Controls_Configuration is record
      Is_Set : Boolean := False;
      Rules  : Ownership_Control_Rule_Vectors.Vector;
   end record;

   --  Representation classification: presence is authoritative. Value is
   --  initialized only to keep default aggregates deterministic and has no
   --  meaning while Is_Set is false; changing the defaults breaks aggregates.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Decoded Boolean, meaningful only when Is_Set is true
   type Optional_Boolean is record
      Is_Set : Boolean := False;
      Value  : Boolean := False;
   end record;

   --  Presence-preserving GetPublicAccessBlock response configuration.
   --  @field Block_Public_ACLs BlockPublicAcls member and presence
   --  @field Ignore_Public_ACLs IgnorePublicAcls member and presence
   --  @field Block_Public_Policy BlockPublicPolicy member and presence
   --  @field Restrict_Public_Buckets RestrictPublicBuckets member and presence
   type Public_Access_Block_Configuration is record
      Block_Public_ACLs       : Optional_Boolean;
      Ignore_Public_ACLs      : Optional_Boolean;
      Block_Public_Policy     : Optional_Boolean;
      Restrict_Public_Buckets : Optional_Boolean;
   end record;

   --  The default is the shared caller-overridable S3 XML resource policy;
   --  these codecs introduce no independent document ceiling.
   --  Parse one exact GetBucketAccelerateConfiguration response document.
   --  @param Document Complete same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving acceleration status
   --  @exception Malformed_Configuration Document violates the exact model
   function Parse_Accelerate
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Accelerate_Status;

   --  Parse one exact GetBucketAbac response document.
   --  @param Document Complete same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving ABAC status
   --  @exception Malformed_Configuration Document violates the exact model
   function Parse_Abac
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Abac_Status;

   --  Parse one exact GetBucketPolicyStatus response document. Absence of
   --  IsPublic is preserved rather than treated as false.
   --  @param Document Complete same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving IsPublic value
   --  @exception Malformed_Configuration Document violates the exact model
   function Parse_Policy_Status
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Optional_Boolean;

   --  Parse one exact GetBucketRequestPayment response document. Absence of
   --  Payer is preserved rather than assigned a provider policy.
   --  @param Document Complete same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving payer configuration
   --  @exception Malformed_Configuration Document violates the exact model
   function Parse_Request_Payment
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Payer;

   --  Parse one exact GetPublicAccessBlock response document, preserving
   --  presence independently for all four modeled booleans.
   --  @param Document Complete same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Four presence-preserving public-access-block values
   --  @exception Malformed_Configuration Document violates the exact model
   function Parse_Public_Access_Block
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Public_Access_Block_Configuration;

   --  Parse one exact GetBucketOwnershipControls response document.
   --  @param Document Complete nonempty same-response XML payload
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present configuration with every required Rule decoded
   --  @exception Malformed_Configuration Document violates the pinned model
   function Parse_Ownership_Controls
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Ownership_Controls_Configuration;

   --  Serialize one exact PutBucketAbac request document.
   function Serialize_Abac (Value : Abac_Status) return String;

   --  Serialize one exact PutBucketAccelerateConfiguration request document.
   function Serialize_Accelerate (Value : Accelerate_Status) return String;

   --  Serialize one exact PutBucketRequestPayment request document.
   --  @exception Malformed_Configuration Payer is absent
   function Serialize_Request_Payment (Value : Payer) return String;

   --  Serialize one exact PutPublicAccessBlock request document.
   function Serialize_Public_Access_Block
     (Value : Public_Access_Block_Configuration) return String;

end Flyology.Object_Storage.S3.Bucket_Controls;
