--  S3-DOMAIN-A-7 (new, found while verifying S3-DOMAIN-A-1): a second,
--  independent rule in the same decoder makes EVERY untruncated
--  ListObjectVersions page from the pinned MinIO undecodable, whatever the
--  storage classes are.
--
--  src/flyology-object_storage-s3-versions.adb:1031-1039 (Validate):
--
--      elsif Value.Has_Next_Version_ID_Marker /=
--        Value.Has_Next_Key_Marker
--        or else Value.Is_Truncated /= Value.Has_Next_Key_Marker
--        ...
--      then
--         raise Malformed_Version_Listing with
--           "inconsistent ListObjectVersions next markers";
--
--  The pinned MinIO (RELEASE.2025-09-07T16-13-09Z, the image in
--  tests/scripts/test-minio.sh) emits an EMPTY <NextVersionIdMarker> on
--  every ?versions page, including untruncated ones, and emits
--  <NextKeyMarker> only when the page is truncated.  Observed on the wire:
--
--    <ListVersionsResult ...><Name>...</Name><Prefix></Prefix>
--    <KeyMarker></KeyMarker><NextVersionIdMarker></NextVersionIdMarker>
--    <VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys>
--    <IsTruncated>false</IsTruncated> ...
--
--  so Has_Next_Version_ID_Marker is True while Has_Next_Key_Marker is
--  False, the first disjunct holds, and the page is rejected.
--
--  The pinned model puts no cross-member constraint on either element
--  (review/baseline/service-2.json: ListObjectVersionsOutput has no
--  "required" list and both markers are plain optional strings), and the
--  AWS ListObjectVersions API Reference documents them only as
--  "When the number of responses exceeds the value of MaxKeys, ...".
--
--  Correct behaviour asserted here: an untruncated page carrying an empty
--  NextVersionIdMarker decodes, exactly as the same page without that
--  element does.  Every storage class in this program is STANDARD, so the
--  failure is attributable to the marker rule alone and not to
--  S3-DOMAIN-A-1.

with Ada.Exceptions;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_A_7 is

   package Versions renames Flyology.Object_Storage.S3.Versions;
   package XML renames Flyology.Object_Storage.S3.XML;

   NS : constant String := "http://s3.amazonaws.com/doc/2006-03-01/";

   --  One STANDARD version, exactly the element order and text MinIO emits.
   Entry_Text : constant String :=
     "<Version><Key>obj-standard</Key>" &
     "<LastModified>2026-09-07T06:33:59.195Z</LastModified>" &
     "<ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag>" &
     "<Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe" &
     "8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner>" &
     "<StorageClass>STANDARD</StorageClass><IsLatest>true</IsLatest>" &
     "<VersionId>2087b1c8-248b-4929-b9e0-f9e8b1cf3685</VersionId></Version>";

   --  MinIO's untruncated envelope, verbatim apart from the storage class.
   MinIO_Untruncated : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListVersionsResult xmlns=""" & NS & """>" &
     "<Name>flyology-review-domain-a-versions</Name><Prefix></Prefix>" &
     "<KeyMarker></KeyMarker>" &
     "<NextVersionIdMarker></NextVersionIdMarker>" &
     "<VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys>" &
     "<IsTruncated>false</IsTruncated>" & Entry_Text & "</ListVersionsResult>";

   --  Same page with the empty NextVersionIdMarker removed.
   Without_Marker : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListVersionsResult xmlns=""" & NS & """>" &
     "<Name>flyology-review-domain-a-versions</Name><Prefix></Prefix>" &
     "<KeyMarker></KeyMarker>" &
     "<VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys>" &
     "<IsTruncated>false</IsTruncated>" & Entry_Text & "</ListVersionsResult>";

   --  MinIO's truncated envelope, which carries both next markers non-empty
   --  and is accepted today.
   MinIO_Truncated : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListVersionsResult xmlns=""" & NS & """>" &
     "<Name>flyology-review-domain-a-versions</Name><Prefix></Prefix>" &
     "<KeyMarker></KeyMarker>" &
     "<NextKeyMarker>obj-standard[minio_cache:v2,return:]</NextKeyMarker>" &
     "<NextVersionIdMarker>2087b1c8-248b-4929-b9e0-f9e8b1cf3685" &
     "</NextVersionIdMarker>" &
     "<VersionIdMarker></VersionIdMarker><MaxKeys>1</MaxKeys>" &
     "<IsTruncated>true</IsTruncated>" & Entry_Text & "</ListVersionsResult>";

   procedure Try (Label, Document : String; Assert_Accepted : Boolean) is
   begin
      declare
         Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions (Document, XML.Default_Limits);
      begin
         Note (Label & ": decoded, versions=" &
               Image (Natural (Page.Versions.Length)) &
               " truncated=" & Boolean'Image (Page.Is_Truncated));
         if Assert_Accepted then
            Check (Natural (Page.Versions.Length) = 1,
                   Label & ": the page keeps its version");
         end if;
      end;
   exception
      when E : Versions.Malformed_Version_Listing =>
         Note (Label & ": REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False, Label & ": the page is accepted");
         end if;
   end Try;

begin
   --  Controls: both shapes the decoder is happy with today.
   Try ("untruncated, no NextVersionIdMarker", Without_Marker, True);
   Try ("truncated, both next markers set   ", MinIO_Truncated, True);

   --  The finding: MinIO's actual untruncated page.
   Try ("MinIO untruncated, empty NextVersionIdMarker",
        MinIO_Untruncated, True);

   Finish;
end Repro_S3_Domain_A_7;
