--  S3-DOMAIN-A-1: the ListObjectVersions decoder validates every
--  <Version>/<StorageClass> against the pinned one-value
--  ObjectVersionStorageClass enumeration
--  (review/baseline/service-2.json: {"type":"string","enum":["STANDARD"]}),
--  so a page in which any single version carries another class raises
--  Malformed_Version_Listing and the whole listing is lost.
--
--  The pinned MinIO image used by tests/scripts/test-minio.sh
--  (RELEASE.2025-09-07T16-13-09Z) accepts
--  "x-amz-storage-class: REDUCED_REDUNDANCY" on PutObject and echoes it
--  inside <Version> of a valid ListVersionsResult; the exact body it
--  returned during this review is replayed below verbatim, so this
--  in-process program needs no server.  repro_s3_domain_a_1_probe.adb runs
--  the same case against a live MinIO through the crate's own high-level
--  client.
--
--  Correct behaviour asserted here: the page decodes and reports the two
--  versions with their own storage classes, exactly as
--  S3.Listings.Parse_List_Objects_V2 already does for the fifteen-value
--  ObjectStorageClass enumeration.

with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_A_1 is

   package US renames Ada.Strings.Unbounded;
   package Versions renames Flyology.Object_Storage.S3.Versions;
   package Listings renames Flyology.Object_Storage.S3.Listings;
   package XML renames Flyology.Object_Storage.S3.XML;

   NS : constant String := "http://s3.amazonaws.com/doc/2006-03-01/";

   --  Byte-for-byte the ListVersionsResult body the pinned MinIO returned
   --  for GET /domain-a-probe?versions after PutObject with
   --  x-amz-storage-class: REDUCED_REDUNDANCY on a versioned bucket
   --  (line breaks added only to fit the source line limit).
   MinIO_Page : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListVersionsResult xmlns=""" & NS & """>" &
     "<Name>domain-a-probe</Name><Prefix></Prefix><KeyMarker></KeyMarker>" &
     "<NextVersionIdMarker></NextVersionIdMarker>" &
     "<VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys>" &
     "<IsTruncated>false</IsTruncated>" &
     "<Version><Key>obj-reduced_redundancy</Key>" &
     "<LastModified>2026-09-07T06:20:32.829Z</LastModified>" &
     "<ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag>" &
     "<Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe" &
     "8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner>" &
     "<StorageClass>REDUCED_REDUNDANCY</StorageClass>" &
     "<IsLatest>true</IsLatest>" &
     "<VersionId>13720619-9a80-4d11-82e1-ef8c05998374</VersionId></Version>" &
     "<Version><Key>obj-standard</Key>" &
     "<LastModified>2026-09-07T06:20:32.840Z</LastModified>" &
     "<ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag>" &
     "<Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe" &
     "8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner>" &
     "<StorageClass>STANDARD</StorageClass><IsLatest>true</IsLatest>" &
     "<VersionId>280036eb-f469-442e-b696-e29a51f80b54</VersionId></Version>" &
     "</ListVersionsResult>";

   function Versions_Page (Storage_Class : String) return String is
     ("<ListVersionsResult xmlns=""" & NS & """>" &
      "<Name>b</Name><MaxKeys>1000</MaxKeys>" &
      "<IsTruncated>false</IsTruncated>" &
      "<Version><Key>k</Key><VersionId>v1</VersionId>" &
      "<IsLatest>true</IsLatest>" &
      "<LastModified>2026-01-01T00:00:00.000Z</LastModified>" &
      "<ETag>&quot;e&quot;</ETag><Size>1</Size>" &
      "<StorageClass>" & Storage_Class & "</StorageClass>" &
      "</Version></ListVersionsResult>");

   function Objects_Page (Storage_Class : String) return String is
     ("<ListBucketResult xmlns=""" & NS & """>" &
      "<Name>b</Name><MaxKeys>1000</MaxKeys>" &
      "<IsTruncated>false</IsTruncated>" &
      "<Contents><Key>k</Key>" &
      "<LastModified>2026-01-01T00:00:00.000Z</LastModified>" &
      "<ETag>&quot;e&quot;</ETag><Size>1</Size>" &
      "<StorageClass>" & Storage_Class & "</StorageClass>" &
      "</Contents></ListBucketResult>");

   procedure Try_Version_Class (Storage_Class : String) is
   begin
      declare
         Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions (Versions_Page (Storage_Class));
      begin
         Note ("ListObjectVersions <StorageClass>" & Storage_Class &
               "</StorageClass>: decoded, versions=" &
               Image (Natural (Page.Versions.Length)));
         Check (Natural (Page.Versions.Length) = 1,
                "ListObjectVersions keeps the " & Storage_Class & " version");
         if Natural (Page.Versions.Length) = 1 then
            Check (US.To_String (Page.Versions.First_Element.Storage_Class) =
                     Storage_Class,
                   "ListObjectVersions preserves " & Storage_Class);
         end if;
      end;
   exception
      when E : Versions.Malformed_Version_Listing =>
         Note ("ListObjectVersions <StorageClass>" & Storage_Class &
               "</StorageClass>: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         Check (False,
                "ListObjectVersions accepts a " & Storage_Class & " version");
   end Try_Version_Class;

   procedure Show_Objects_Class (Storage_Class : String) is
   begin
      declare
         Page : constant Listings.List_Objects_Result :=
           Listings.Parse_List_Objects (Objects_Page (Storage_Class));
      begin
         Note ("  ListObjects v1 <StorageClass>" & Storage_Class &
               "</StorageClass>: decoded, objects=" &
               Image (Natural (Page.Contents.Length)));
      end;
   exception
      when E : Listings.Malformed_Listing =>
         Note ("  ListObjects v1 <StorageClass>" & Storage_Class &
               "</StorageClass>: REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
   end Show_Objects_Class;

   procedure Try_MinIO_Page is
   begin
      declare
         Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions
             (MinIO_Page, XML.Default_Limits);
      begin
         Note ("MinIO page decoded, versions=" &
               Image (Natural (Page.Versions.Length)));
         Check (Natural (Page.Versions.Length) = 2,
                "the MinIO ListVersionsResult decodes with both versions");
      end;
   exception
      when E : Versions.Malformed_Version_Listing =>
         Note ("MinIO page REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         Check (False,
                "the MinIO ListVersionsResult decodes with both versions");
   end Try_MinIO_Page;

begin
   --  Control: the same decoder on the same page shape with STANDARD must
   --  succeed, so a failure below is about the enumeration and not the
   --  harness or the document.
   Try_Version_Class ("STANDARD");

   --  The classes that matter.  REDUCED_REDUNDANCY is the one the pinned
   --  MinIO actually emits; the others are what AWS returns for objects
   --  uploaded into or lifecycle-transitioned to another class.
   Try_Version_Class ("REDUCED_REDUNDANCY");
   Try_Version_Class ("STANDARD_IA");
   Try_Version_Class ("GLACIER");
   Try_Version_Class ("INTELLIGENT_TIERING");

   --  The crate is internally inconsistent: the ListObjects codec accepts
   --  every one of these for the very same object.
   Note ("--- same classes through the ListObjects v1 decoder ---");
   Show_Objects_Class ("STANDARD");
   Show_Objects_Class ("REDUCED_REDUNDANCY");
   Show_Objects_Class ("STANDARD_IA");
   Show_Objects_Class ("GLACIER");
   Show_Objects_Class ("INTELLIGENT_TIERING");

   Note ("--- verbatim MinIO RELEASE.2025-09-07T16-13-09Z body ---");
   Note ("body bytes " & Image (MinIO_Page'Length));
   Try_MinIO_Page;

   Finish;
end Repro_S3_Domain_A_1;
