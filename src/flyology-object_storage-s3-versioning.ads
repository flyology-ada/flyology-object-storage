with Flyology.Object_Storage.S3.XML;

--  Strict bounded REST/XML codec for bucket-versioning configuration.
package Flyology.Object_Storage.S3.Versioning is

   --  Raised when a versioning document violates the modeled XML contract.
   Malformed_Configuration : exception;

   --  Maximum versioning-document size accepted by the default limits.
   Maximum_Document_Bytes : constant := 4 * 1_024;

   --  Default bounded parser limits for versioning documents.
   Default_Limits : constant XML.Parse_Limits :=
     (Maximum_Document_Bytes => Maximum_Document_Bytes,
      Maximum_Depth          => 2,
      Maximum_Elements       => 3,
      Maximum_Text_Bytes     => 64);

   --  Parse an exact VersioningConfiguration document. The two modeled
   --  members are independently optional; unknown, duplicate, nested, or
   --  invalid values fail closed.
   --  @param Document Complete REST/XML document
   --  @param Limits XML resource bounds
   --  @return Presence-preserving storage-domain configuration
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration;

   --  Parse an implementation response. AWS responses use the S3 namespace,
   --  while a few otherwise compatible implementations omit it; foreign
   --  namespaces and all element attributes still fail closed.
   --  @param Document Complete REST/XML response document
   --  @param Limits XML resource bounds
   --  @return Presence-preserving storage-domain configuration
   function Parse_Response
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration;

   --  Serialize exactly the configured members in PutBucketVersioning input
   --  model order beneath the AWS S3 namespace.
   --  @param Value Configuration to serialize
   --  @return Complete REST/XML document
   function Serialize (Value : Bucket_Versioning_Configuration) return String;

   --  Serialize exactly the configured members in GetBucketVersioning output
   --  model order. An entirely unconfigured value emits an empty root.
   --  @param Value Configuration snapshot to serialize
   --  @return Complete REST/XML response document
   function Serialize_Response
     (Value : Bucket_Versioning_Configuration) return String;

end Flyology.Object_Storage.S3.Versioning;
