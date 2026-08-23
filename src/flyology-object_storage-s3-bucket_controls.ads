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

   --  Pinned S3 model contract: Payer is optional and has exactly the two
   --  external values below; changing the set changes response compatibility.
   --  @enum Payer_Absent Payer member was absent
   --  @enum Requester Exact external Requester value
   --  @enum Bucket_Owner Exact external BucketOwner value
   type Payer is (Payer_Absent, Requester, Bucket_Owner);

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

end Flyology.Object_Storage.S3.Bucket_Controls;
