with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 analytics configurations.
package Flyology.Object_Storage.S3.Analytics is

   --  Raised when a document violates the pinned analytics model.
   Malformed_Analytics : exception;

   --  Presence-preserving optional string.
   --  @field Is_Set Whether the modeled member was present
   --  @field Value Exact decoded text when present
   type Optional_String is record
      Is_Set : Boolean;
      Value  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  One required analytics tag.
   --  @field Key Required nonempty object-key text
   --  @field Value Required exact tag value
   type Analytics_Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional direct analytics tag.
   --  @field Is_Set Whether Tag was present
   --  @field Value Complete required tag when present
   type Optional_Tag is record
      Is_Set : Boolean;
      Value  : Analytics_Tag;
   end record;

   --  Ordered flattened And/Tag values bounded by caller XML limits.
   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Analytics_Tag);

   --  Optional logical-And analytics filter. The pinned model permits its
   --  members independently and encodes no additional cross-field rule.
   --  @field Is_Set Whether And was present
   --  @field Prefix Optional exact prefix
   --  @field Tags Direct Tag values in wire order
   type Analytics_And is record
      Is_Set : Boolean;
      Prefix : Optional_String;
      Tags   : Tag_Vectors.Vector;
   end record;

   --  Optional analytics filter with every modeled member preserved
   --  independently; this codec does not invent a one-of constraint.
   --  @field Is_Set Whether Filter was present
   --  @field Prefix Optional exact prefix
   --  @field Tag Optional direct required tag
   --  @field And_Predicates Optional logical-And structure
   type Analytics_Filter is record
      Is_Set         : Boolean;
      Prefix         : Optional_String;
      Tag            : Optional_Tag;
      And_Predicates : Analytics_And;
   end record;

   --  Pinned AnalyticsS3ExportFileFormat domain. These literals are the
   --  external S3 wire contract; adding one changes response compatibility.
   --  @enum CSV CSV analytics export
   type Export_File_Format is (CSV);

   --  Pinned StorageClassAnalysisSchemaVersion domain. This literal is the
   --  external S3 wire contract; adding one changes response compatibility.
   --  @enum V_1 Version-one storage-class analysis schema
   type Schema_Version is (V_1);

   --  Complete required analytics S3 export destination.
   --  @field Format Exact modeled export format
   --  @field Bucket_Account_ID Optional destination account identifier
   --  @field Bucket Required exact destination bucket
   --  @field Prefix Optional destination prefix
   type S3_Bucket_Destination is record
      Format            : Export_File_Format;
      Bucket_Account_ID : Optional_String;
      Bucket            : Ada.Strings.Unbounded.Unbounded_String;
      Prefix            : Optional_String;
   end record;

   --  Complete required analytics export destination wrapper.
   --  @field S3_Bucket Complete required S3 destination
   type Export_Destination is record
      S3_Bucket : S3_Bucket_Destination;
   end record;

   --  Complete storage-class-analysis export configuration.
   --  @field Output_Schema_Version Exact modeled schema version
   --  @field Destination Complete required export destination
   type Data_Export is record
      Output_Schema_Version : Schema_Version;
      Destination           : Export_Destination;
   end record;

   --  Presence-preserving optional data export.
   --  @field Is_Set Whether DataExport was present
   --  @field Value Complete required data export when present
   type Optional_Data_Export is record
      Is_Set : Boolean;
      Value  : Data_Export;
   end record;

   --  Complete modeled storage-class analysis. The pinned model permits an
   --  empty structure and makes DataExport optional.
   --  @field Data_Export Optional complete export configuration
   type Storage_Class_Analysis is record
      Data_Export : Optional_Data_Export;
   end record;

   --  Complete GetBucketAnalyticsConfiguration payload.
   --  @field ID Required exact configuration identifier
   --  @field Filter Optional complete modeled filter
   --  @field Storage_Class_Analysis Required complete modeled analysis
   type Analytics_Configuration is record
      ID                     : Ada.Strings.Unbounded.Unbounded_String;
      Filter                 : Analytics_Filter;
      Storage_Class_Analysis : Analytics.Storage_Class_Analysis;
   end record;

   --  Parse one exact nonempty GetBucketAnalyticsConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Complete presence-preserving analytics graph
   --  @exception Malformed_Analytics Document violates the pinned model
   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Analytics_Configuration;

end Flyology.Object_Storage.S3.Analytics;
