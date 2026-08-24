with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;

--  Strict REST/XML codec for S3 bucket metadata-table configuration reads.
package Flyology.Object_Storage.S3.Metadata_Tables is

   --  Raised when a response violates the pinned metadata-table model.
   Malformed_Metadata_Table : exception;

   --  Presence-preserving optional string.  Empty text remains distinct from
   --  absence because the pinned string shapes have no minimum.
   --  @field Is_Set Whether the modeled string was present
   --  @field Value Exact decoded string
   type Optional_String is record
      Is_Set : Boolean := False;
      Value  : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.Null_Unbounded_String;
   end record;

   --  Required S3 Tables destination returned by the provider.  Every string
   --  is opaque and may be empty because the pinned shapes specify no minimum.
   --  @field Table_Bucket_ARN Exact required table-bucket ARN
   --  @field Table_Name Exact required table name
   --  @field Table_ARN Exact required table ARN
   --  @field Table_Namespace Exact required table namespace
   type S3_Tables_Destination_Result is record
      Table_Bucket_ARN : Ada.Strings.Unbounded.Unbounded_String;
      Table_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Table_ARN        : Ada.Strings.Unbounded.Unbounded_String;
      Table_Namespace  : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Optional provider error details nested inside a successful result.
   --  @field Is_Set Whether the Error structure was present
   --  @field Code Optional exact provider error code
   --  @field Message Optional exact provider error message
   type Error_Details is record
      Is_Set  : Boolean := False;
      Code    : Optional_String;
      Message : Optional_String;
   end record;

   --  Presence-preserving GetBucketMetadataTableConfiguration payload.
   --  Status remains an opaque required provider string; this codec does not
   --  invent a local lifecycle enum or normalize provider state.
   --  @field Is_Set Whether the outer result payload was present
   --  @field Destination Required exact S3 Tables destination when present
   --  @field Status Required exact opaque provider status when present
   --  @field Error Optional nested provider error details
   type Metadata_Table_Configuration_Result is record
      Is_Set      : Boolean := False;
      Destination : S3_Tables_Destination_Result;
      Status      : Ada.Strings.Unbounded.Unbounded_String;
      Error       : Error_Details;
   end record;

   --  Parse one exact nonempty GetBucketMetadataTableConfiguration payload.
   --  @param Document Complete same-response XML document
   --  @param Limits Caller-selected shared S3 XML resource limits
   --  @return Present result with every modeled member preserved
   --  @exception Malformed_Metadata_Table Document violates the pinned model
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Metadata_Table_Configuration_Result;

end Flyology.Object_Storage.S3.Metadata_Tables;
