with Flyology.Object_Storage.S3.XML;

--  Strict bounded REST/XML codec for bucket-versioning configuration.
package Flyology.Object_Storage.S3.Versioning is

   Malformed_Configuration : exception;
   Maximum_Document_Bytes : constant := 4 * 1_024;
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

   --  Serialize exactly the configured members in model order beneath the
   --  AWS S3 namespace. An entirely unconfigured value emits an empty root,
   --  as GetBucketVersioning does for a bucket never configured.
   --  @param Value Configuration to serialize
   --  @return Complete REST/XML document
   function Serialize (Value : Bucket_Versioning_Configuration) return String;

end Flyology.Object_Storage.S3.Versioning;
