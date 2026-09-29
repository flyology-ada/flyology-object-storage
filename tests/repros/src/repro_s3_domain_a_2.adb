--  S3-DOMAIN-A-2: S3.Listings.Validate makes <NextMarker> on a truncated
--  ListObjects v1 page conditional on a nonempty <Delimiter>
--  (src/flyology-object_storage-s3-listings.adb:1108-1116,
--   Has_Next_Marker /= (Is_Truncated and then Effective_Delimiter)), so a
--  truncated no-delimiter page that carries NextMarker raises
--  Malformed_Listing and the very first page of the listing is lost.
--
--  The pinned model (review/baseline/service-2.json,
--  ListObjectsOutput.NextMarker) states the delimiter rule only as AWS
--  behaviour prose -- "This element is returned only if you have the
--  delimiter request parameter specified" -- and imposes no constraint:
--  NextMarker is an unconstrained optional string and ListObjectsOutput has
--  no required list.  docs/qualification/list-objects-v1.md:54-59 records
--  that the three pinned third-party servers all emit it anyway, and the
--  Docker scripts disable the subcase through
--  FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE rather than accepting the page.
--
--  The bodies below are byte-for-byte what the pinned MinIO image used by
--  tests/scripts/test-minio.sh (RELEASE.2025-09-07T16-13-09Z) returned for
--  a three-key bucket with max-keys=1, with and without a delimiter, so
--  this program needs no server.  repro_s3_domain_a_2_probe.adb runs the
--  same case against a live MinIO through the crate's high-level client.
--
--  Correct behaviour asserted here: the truncated no-delimiter page decodes
--  and reports Is_Truncated, one object, and the marker.  Nothing is lost by
--  accepting it: Client.Objects.List_V1_Page already derives the marker from
--  the last key when NextMarker is absent
--  (src/flyology-object_storage-client-objects.adb:403-415).

with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;

procedure Repro_S3_Domain_A_2 is

   package US renames Ada.Strings.Unbounded;
   package Listings renames Flyology.Object_Storage.S3.Listings;
   package XML renames Flyology.Object_Storage.S3.XML;

   NS : constant String := "http://s3.amazonaws.com/doc/2006-03-01/";

   MinIO_Marker : constant String := "k1[minio_cache:v2,return:]";

   --  Verbatim MinIO body for GET /domain-a-v1?max-keys=1 (no delimiter),
   --  bucket holding k1, k2, k3.
   MinIO_No_Delimiter : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListBucketResult xmlns=""" & NS & """>" &
     "<Name>domain-a-v1</Name><Prefix></Prefix><Marker></Marker>" &
     "<NextMarker>" & MinIO_Marker & "</NextMarker>" &
     "<MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>" &
     "<Contents><Key>k1</Key>" &
     "<LastModified>2026-09-07T06:20:32.863Z</LastModified>" &
     "<ETag>&#34;415290769594460e2e485922904f345d&#34;</ETag>" &
     "<Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe" &
     "8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner>" &
     "<StorageClass>STANDARD</StorageClass></Contents></ListBucketResult>";

   --  Verbatim MinIO body for the same request with delimiter=/.  The only
   --  difference is the echoed <Delimiter>, and that single element is what
   --  decides whether the crate accepts the page.
   MinIO_With_Delimiter : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListBucketResult xmlns=""" & NS & """>" &
     "<Name>domain-a-v1</Name><Prefix></Prefix><Marker></Marker>" &
     "<NextMarker>" & MinIO_Marker & "</NextMarker>" &
     "<MaxKeys>1</MaxKeys><Delimiter>/</Delimiter>" &
     "<IsTruncated>true</IsTruncated>" &
     "<Contents><Key>k1</Key>" &
     "<LastModified>2026-09-07T06:20:32.863Z</LastModified>" &
     "<ETag>&#34;415290769594460e2e485922904f345d&#34;</ETag>" &
     "<Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe" &
     "8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner>" &
     "<StorageClass>STANDARD</StorageClass></Contents></ListBucketResult>";

   --  Minimal synthetic form of the same page, so the finding does not rest
   --  on any MinIO-specific element.
   Minimal_No_Delimiter : constant String :=
     "<ListBucketResult xmlns=""" & NS & """>" &
     "<Name>b</Name><MaxKeys>1</MaxKeys>" &
     "<IsTruncated>true</IsTruncated><NextMarker>a</NextMarker>" &
     "<Contents><Key>a</Key><Size>1</Size></Contents></ListBucketResult>";

   procedure Try_Page
     (Label            : String;
      Document         : String;
      Expected_Marker  : String;
      Assert_Accepted  : Boolean)
   is
   begin
      declare
         Page : constant Listings.List_Objects_Result :=
           Listings.Parse_List_Objects (Document, XML.Default_Limits);
      begin
         Note (Label & ": decoded, objects=" &
               Image (Natural (Page.Contents.Length)) &
               " truncated=" & Boolean'Image (Page.Is_Truncated) &
               " has_next_marker=" & Boolean'Image (Page.Has_Next_Marker) &
               " next_marker=""" & US.To_String (Page.Next_Marker) & """");
         if Assert_Accepted then
            Check (Natural (Page.Contents.Length) = 1,
                   Label & ": the page keeps its one object");
            Check (Page.Is_Truncated, Label & ": the page is truncated");
            Check (Page.Has_Next_Marker,
                   Label & ": the page keeps NextMarker");
            Check (US.To_String (Page.Next_Marker) = Expected_Marker,
                   Label & ": NextMarker text is preserved");
         end if;
      end;
   exception
      when E : Listings.Malformed_Listing =>
         Note (Label & ": REJECTED, " &
               Ada.Exceptions.Exception_Message (E));
         if Assert_Accepted then
            Check (False, Label & ": the page is accepted");
         end if;
   end Try_Page;

begin
   --  Control 1: the same MinIO page with the delimiter echoed back is
   --  accepted today, so the decoder and the harness both work.
   Try_Page ("MinIO max-keys=1 delimiter=/  ",
             MinIO_With_Delimiter, MinIO_Marker, True);

   --  Control 2: a truncated no-delimiter page WITHOUT NextMarker (what the
   --  Flyology server itself emits) is accepted today.
   Try_Page ("Flyology-shaped page, no NextMarker",
             "<ListBucketResult xmlns=""" & NS & """>" &
             "<Name>b</Name><MaxKeys>1</MaxKeys>" &
             "<IsTruncated>true</IsTruncated>" &
             "<Contents><Key>a</Key><Size>1</Size></Contents>" &
             "</ListBucketResult>",
             "", False);

   --  The finding.
   Try_Page ("MinIO max-keys=1 no delimiter   ",
             MinIO_No_Delimiter, MinIO_Marker, True);
   Try_Page ("minimal truncated no-delimiter  ",
             Minimal_No_Delimiter, "a", True);

   Finish;
end Repro_S3_Domain_A_2;
