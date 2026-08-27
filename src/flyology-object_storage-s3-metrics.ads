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

   --  Parse one exact nonempty GetBucketMetricsConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving metrics graph
   --  @exception Malformed_Metrics Document violates the pinned model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Metrics_Configuration;

end Flyology.Object_Storage.S3.Metrics;
