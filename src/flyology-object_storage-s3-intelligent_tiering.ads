with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 Intelligent-Tiering configurations.
package Flyology.Object_Storage.S3.Intelligent_Tiering is

   --  Raised when a document violates the pinned Intelligent-Tiering model.
   Malformed_Intelligent_Tiering : exception;

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text when present
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One required Intelligent-Tiering tag.
   --  @field Key Required nonempty object-key text
   --  @field Value Required exact tag value
   type Intelligent_Tiering_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional direct Intelligent-Tiering tag.
   --  @field Is_Set Whether Tag was present
   --  @field Value Complete required tag when present
   type Optional_Tag is record
      Is_Set : Boolean;
      Value  : Intelligent_Tiering_Tag;
   end record;

   --  Ordered flattened And/Tag values bounded by caller XML limits.
   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Intelligent_Tiering_Tag);

   --  Optional logical-And filter. The pinned structural model permits its
   --  members independently and encodes no additional cross-field rule.
   --  @field Is_Set Whether And was present
   --  @field Prefix Optional exact prefix
   --  @field Tags Direct Tag values in wire order
   type Intelligent_Tiering_And is record
      Is_Set : Boolean;
      Prefix : Optional_String;
      Tags   : Tag_Vectors.Vector;
   end record;

   --  Optional filter with every modeled member preserved independently;
   --  this codec does not invent a one-of constraint.
   --  @field Is_Set Whether Filter was present
   --  @field Prefix Optional exact prefix
   --  @field Tag Optional direct required tag
   --  @field And_Predicates Optional logical-And structure
   type Intelligent_Tiering_Filter is record
      Is_Set         : Boolean;
      Prefix         : Optional_String;
      Tag            : Optional_Tag;
      And_Predicates : Intelligent_Tiering_And;
   end record;

   --  Pinned IntelligentTieringStatus wire domain.
   --  @enum Enabled Configuration is active
   --  @enum Disabled Configuration is inactive
   type Configuration_Status is (Enabled, Disabled);

   --  Pinned IntelligentTieringAccessTier wire domain.
   --  @enum Archive_Access ARCHIVE_ACCESS
   --  @enum Deep_Archive_Access DEEP_ARCHIVE_ACCESS
   type Access_Tier_Kind is (Archive_Access, Deep_Archive_Access);

   --  One required Intelligent-Tiering transition. Days remains validated
   --  signed decimal text because the pinned integer shape has no bound.
   --  @field Days Exact required signed decimal wire text
   --  @field Access_Tier Exact required access tier
   type Tiering is record
      Days        : Ada.Strings.Unbounded.Unbounded_String;
      Access_Tier : Access_Tier_Kind;
   end record;

   --  Ordered required flattened Tiering values bounded by caller XML limits.
   package Tiering_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Tiering);

   --  Complete GetBucketIntelligentTieringConfiguration payload.
   --  @field ID Required exact configuration identifier
   --  @field Filter Optional complete modeled filter
   --  @field Status Required exact configuration status
   --  @field Tierings Required nonempty transitions in wire order
   type Intelligent_Tiering_Configuration is record
      ID       : Ada.Strings.Unbounded.Unbounded_String;
      Filter   : Intelligent_Tiering_Filter;
      Status   : Configuration_Status;
      Tierings : Tiering_Vectors.Vector;
   end record;

   --  XML document and element limits bound one decoded page; this vector does
   --  not introduce a separate client-side page-size policy.
   package Configuration_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Intelligent_Tiering_Configuration);

   --  Complete ListBucketIntelligentTieringConfigurations response payload.
   --  Optional scalars preserve absence independently from empty or false
   --  values, and no cross-field relationship is inferred beyond the pinned
   --  model.
   --  @field Has_Is_Truncated Whether IsTruncated was present
   --  @field Is_Truncated Exact modeled value when present
   --  @field Continuation_Token Optional echoed request cursor
   --  @field Next_Continuation_Token Optional next-page cursor
   --  @field Configurations Configuration values in wire order
   type Intelligent_Tiering_Configuration_Page is record
      Has_Is_Truncated        : Boolean;
      Is_Truncated            : Boolean;
      Continuation_Token      : Optional_String;
      Next_Continuation_Token : Optional_String;
      Configurations          : Configuration_Vectors.Vector;
   end record;

   --  Parse one exact nonempty GetBucketIntelligentTieringConfiguration
   --  payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving Intelligent-Tiering graph
   --  @exception Malformed_Intelligent_Tiering Document violates the model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Intelligent_Tiering_Configuration;

   --  Parse one exact ListBucketIntelligentTieringConfigurations payload
   --  through the shared paginated REST/XML envelope and the same reviewed
   --  item decoder.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving Intelligent-Tiering page
   --  @exception Malformed_Intelligent_Tiering Document violates the model
   function Parse_List
     (Document : String; Limits : XML.Parse_Limits)
      return Intelligent_Tiering_Configuration_Page;

end Flyology.Object_Storage.S3.Intelligent_Tiering;
