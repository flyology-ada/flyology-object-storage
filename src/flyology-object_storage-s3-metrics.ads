with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 request-metrics configurations.
package Flyology.Object_Storage.S3.Metrics is

   --  Raised when a document violates the pinned metrics model.
   Malformed_Metrics : exception;

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text when present
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One required metrics tag.
   --  @field Key Required nonempty object-key text
   --  @field Value Required exact tag value
   type Metrics_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional direct metrics tag.
   --  @field Is_Set Whether Tag was present
   --  @field Value Complete required tag when present
   type Optional_Tag is record
      Is_Set : Boolean;
      Value  : Metrics_Tag;
   end record;

   --  Ordered And/Tag values bounded by caller-selected XML limits.
   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Metrics_Tag);

   --  Optional logical-And metrics filter. The model permits its members
   --  independently and encodes no additional cross-field rule.
   --  @field Is_Set Whether And was present
   --  @field Prefix Optional exact prefix
   --  @field Tags Direct Tag values in wire order
   --  @field Access_Point_ARN Optional exact access-point ARN
   type Metrics_And is record
      Is_Set           : Boolean;
      Prefix           : Optional_String;
      Tags             : Tag_Vectors.Vector;
      Access_Point_ARN : Optional_String;
   end record;

   --  Optional metrics filter with every model member preserved
   --  independently; this codec does not invent a one-of constraint.
   --  @field Is_Set Whether Filter was present
   --  @field Prefix Optional exact prefix
   --  @field Tag Optional direct required tag
   --  @field Access_Point_ARN Optional exact access-point ARN
   --  @field And_Predicates Optional logical-And structure
   type Metrics_Filter is record
      Is_Set           : Boolean;
      Prefix           : Optional_String;
      Tag              : Optional_Tag;
      Access_Point_ARN : Optional_String;
      And_Predicates   : Metrics_And;
   end record;

   --  Complete GetBucketMetricsConfiguration payload.
   --  @field ID Required exact configuration identifier
   --  @field Filter Optional complete modeled filter
   type Metrics_Configuration is record
      ID     : Ada.Strings.Unbounded.Unbounded_String;
      Filter : Metrics_Filter;
   end record;

   --  Metrics configurations in exact response order. The caller's shared
   --  XML document and element limits bound one decoded page; this vector does
   --  not introduce a separate client-side page-size policy.
   package Configuration_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Metrics_Configuration);

   --  Complete ListBucketMetricsConfigurations response payload. Optional
   --  scalars preserve absence independently from empty or false values, and
   --  no cross-field relationship is inferred beyond the pinned model.
   --  @field Has_Is_Truncated Whether IsTruncated was present
   --  @field Is_Truncated Exact modeled value when present
   --  @field Continuation_Token Optional echoed request cursor
   --  @field Next_Continuation_Token Optional next-page cursor
   --  @field Configurations Configuration values in wire order
   type Metrics_Configuration_Page is record
      Has_Is_Truncated        : Boolean;
      Is_Truncated            : Boolean;
      Continuation_Token      : Optional_String;
      Next_Continuation_Token : Optional_String;
      Configurations          : Configuration_Vectors.Vector;
   end record;

   --  Parse one exact nonempty GetBucketMetricsConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving metrics graph
   --  @exception Malformed_Metrics Document violates the pinned model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Metrics_Configuration;

   --  Parse one exact ListBucketMetricsConfigurations payload through the
   --  shared paginated REST/XML envelope and the same reviewed item decoder.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Presence-preserving metrics page
   --  @exception Malformed_Metrics Document violates the pinned model
   function Parse_List
     (Document : String; Limits : XML.Parse_Limits)
      return Metrics_Configuration_Page;

   --  Serialize one complete PutBucketMetricsConfiguration payload. The
   --  caller-selected XML limits bound the exact signed document; no new
   --  client-side policy or cross-field constraint is introduced.
   --  @param Value Complete presence-preserving metrics graph
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Exact S3 REST/XML request document
   --  @exception Malformed_Metrics Value or document violates the model
   function Serialize
     (Value : Metrics_Configuration; Limits : XML.Parse_Limits)
      return String;

end Flyology.Object_Storage.S3.Metrics;
