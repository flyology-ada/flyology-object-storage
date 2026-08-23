with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Versions;
with Flyology.Object_Storage.S3.XML;

procedure S3_List_Object_Versions_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Versions renames Flyology.Object_Storage.S3.Versions;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type Low_Level.List_Outcome_Kind;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   Namespace : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";
   Complete_Page : constant String :=
     "<ListVersionsResult xmlns=""" & Namespace & """>" &
     "<IsTruncated>true</IsTruncated>" &
     "<KeyMarker>logs%2Fbefore</KeyMarker>" &
     "<VersionIdMarker>version-before</VersionIdMarker>" &
     "<NextKeyMarker>logs%2Fnext</NextKeyMarker>" &
     "<NextVersionIdMarker>version-next</NextVersionIdMarker>" &
     "<Version><ETag>&quot;etag&quot;</ETag>" &
     "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
     "<ChecksumAlgorithm>CRC32C</ChecksumAlgorithm>" &
     "<ChecksumType>FULL_OBJECT</ChecksumType><Size>4294967297</Size>" &
     "<StorageClass>STANDARD</StorageClass>" &
     "<Key>logs%2Fobject</Key><VersionId>version-1</VersionId>" &
     "<IsLatest>false</IsLatest>" &
     "<LastModified>2026-08-23T01:02:03.123Z</LastModified>" &
     "<Owner><DisplayName>owner</DisplayName><ID>owner-id</ID></Owner>" &
     "<RestoreStatus><IsRestoreInProgress>false</IsRestoreInProgress>" &
     "<RestoreExpiryDate>2026-08-24T01:02:03+00:00</RestoreExpiryDate>" &
     "</RestoreStatus></Version>" &
     "<DeleteMarker><Owner><ID>owner-id</ID></Owner>" &
     "<Key>logs%2Fdeleted</Key><VersionId>delete-1</VersionId>" &
     "<IsLatest>true</IsLatest>" &
     "<LastModified>2026-08-23T02:03:04Z</LastModified>" &
     "</DeleteMarker>" &
     "<Name>example-bucket</Name><Prefix>logs%2F</Prefix>" &
     "<Delimiter>%2F</Delimiter><MaxKeys>3</MaxKeys>" &
     "<CommonPrefixes><Prefix>logs%2Fgroup%2F</Prefix>" &
     "</CommonPrefixes><EncodingType>url</EncodingType>" &
     "</ListVersionsResult>";

   function Page
     (Contents     : String;
      Is_Truncated : String := "false";
      Maximum      : String := "10";
      Markers      : String := "") return String is
     ("<ListVersionsResult><Name>bucket</Name><MaxKeys>" & Maximum &
      "</MaxKeys><IsTruncated>" & Is_Truncated & "</IsTruncated>" &
      Markers & Contents & "</ListVersionsResult>");

   Version : constant String :=
     "<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
     "<Key>key</Key><VersionId>v1</VersionId>" &
     "<IsLatest>true</IsLatest>" &
     "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>";
   Delete : constant String :=
     "<DeleteMarker><Key>key</Key><VersionId>d1</VersionId>" &
     "<IsLatest>false</IsLatest>" &
     "<LastModified>2026-08-23T01:02:03Z</LastModified>" &
     "</DeleteMarker>";

   procedure Expect_Bad
     (Document : String;
      Message  : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits) is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Versions.List_Object_Versions_Result :=
              Versions.Parse_List_Object_Versions (Document, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Versions.Malformed_Version_Listing =>
            Raised := True;
      end;
      Require (Raised, Message);
   end Expect_Bad;

   function Version_With
     (Extra         : String := "";
      Size          : String := "1";
      Last_Modified : String := "2026-08-23T01:02:03Z") return String is
     ("<Version>" & Extra & "<Size>" & Size & "</Size>" &
      "<StorageClass>STANDARD</StorageClass><Key>key</Key>" &
      "<VersionId>v1</VersionId><IsLatest>true</IsLatest>" &
      "<LastModified>" & Last_Modified & "</LastModified></Version>");

begin
   declare
      Value : constant Versions.List_Object_Versions_Result :=
        Versions.Parse_List_Object_Versions (Complete_Page);
   begin
      Require
        (Value.Has_Name
         and then US.To_String (Value.Name) = "example-bucket"
         and then Value.Has_Max_Keys
         and then Value.Max_Keys = 3
         and then Value.Has_Is_Truncated
         and then Value.Is_Truncated
         and then Value.Has_Key_Marker
         and then Value.Has_Version_ID_Marker
         and then Value.Has_Next_Key_Marker
         and then Value.Has_Next_Version_ID_Marker
         and then Value.Versions.Length = 1
         and then Value.Delete_Markers.Length = 1
         and then Value.Common_Prefixes.Length = 1,
         "complete ListObjectVersions top-level projection");
      Require
        (Value.Versions (1).Has_Entity_Tag
         and then Value.Versions (1).Checksum_Algorithms.Length = 2
         and then Value.Versions (1).Has_Checksum_Type
         and then Value.Versions (1).Size = 4_294_967_297
         and then Value.Versions (1).Has_Owner
         and then Value.Versions (1).Has_Restore_Status
         and then Value.Versions (1).Restore_Status.
           Has_Is_Restore_In_Progress,
         "complete ObjectVersion projection");
      Require
        (Value.Delete_Markers (1).Has_Owner
         and then Value.Delete_Markers (1).Has_Key
         and then Value.Delete_Markers (1).Has_Version_ID
         and then Value.Delete_Markers (1).Has_Is_Latest
         and then Value.Delete_Markers (1).Is_Latest,
         "complete DeleteMarker projection");
   end;

   Expect_Bad ("<Wrong/>", "accepted wrong root");
   Expect_Bad
     ("<ListVersionsResult xmlns=""urn:foreign""/>",
      "accepted foreign namespace");
   Expect_Bad
     ("<ListVersionsResult bad=""1""/>", "accepted attributes");
   Expect_Bad (Page ("<Unknown/>"), "accepted unknown top-level field");
   Expect_Bad
     ("<ListVersionsResult><Name>a</Name><Name>b</Name>" &
      "<MaxKeys>1</MaxKeys><IsTruncated>false</IsTruncated>" &
      "</ListVersionsResult>", "accepted duplicate singleton");
   Expect_Bad
     ("<ListVersionsResult><MaxKeys>1</MaxKeys>" &
      "<IsTruncated>false</IsTruncated></ListVersionsResult>",
      "accepted missing name");
   Expect_Bad
     ("<ListVersionsResult><Name>bucket</Name>" &
      "<IsTruncated>false</IsTruncated></ListVersionsResult>",
      "accepted missing MaxKeys");
   Expect_Bad
     ("<ListVersionsResult><Name>bucket</Name><MaxKeys>1</MaxKeys>" &
      "</ListVersionsResult>", "accepted missing IsTruncated");
   Expect_Bad
     (Page (Version & Delete, Maximum => "1"), "accepted excessive page");
   Expect_Bad
     (Page ("", Is_Truncated => "true"),
      "accepted truncated page without markers");
   Expect_Bad
     (Page
        ("", Markers =>
           "<NextKeyMarker>key</NextKeyMarker>" &
           "<NextVersionIdMarker>version</NextVersionIdMarker>"),
      "accepted final page with next markers");
   Expect_Bad
     (Page ("<VersionIdMarker>version</VersionIdMarker>"),
      "accepted unpaired request marker echo");
   Expect_Bad
     (Page
        ("<CommonPrefixes><Prefix>a/</Prefix></CommonPrefixes>" &
         "<CommonPrefixes><Prefix>a/</Prefix></CommonPrefixes>"),
      "accepted duplicate common prefix");
   Expect_Bad
     (Page ("<CommonPrefixes><Prefix/></CommonPrefixes>"),
      "accepted empty common prefix");
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<VersionId>v</VersionId><IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted version without key");
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted version without ID");
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted version without IsLatest");
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest></Version>"),
      "accepted version without timestamp");
   Expect_Bad
     (Page
        ("<Version><Size>-1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted negative size");
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>GLACIER</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted unmodeled storage class");
   Expect_Bad
     (Page
        ("<Version><ChecksumAlgorithm>BOGUS</ChecksumAlgorithm>" &
         "<Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted unknown checksum algorithm");
   Expect_Bad
     (Page
        ("<Version><ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
         "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
         "<Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted duplicate checksum algorithm");
   Expect_Bad
     (Page
        ("<Version><ChecksumType>FULL_OBJECT</ChecksumType>" &
         "<Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted checksum type without algorithm");
   Expect_Bad
     (Page
        ("<DeleteMarker><Key>key</Key><VersionId>d</VersionId>" &
         "<IsLatest>yes</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified>" &
         "</DeleteMarker>"), "accepted invalid delete-marker boolean");
   Expect_Bad
     (Page
        ("<DeleteMarker><Key>key</Key><VersionId>d</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-02-30T01:02:03Z</LastModified>" &
         "</DeleteMarker>"), "accepted invalid timestamp");
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>STANDARD</StorageClass>" &
         "<Key><Nested/></Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted nested scalar");
   Expect_Bad (Page (Version & Version), "accepted duplicate version");
   Expect_Bad
     (Page
        (Version &
         "<DeleteMarker><Key>key</Key><VersionId>v1</VersionId>" &
         "<IsLatest>false</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified>" &
         "</DeleteMarker>"), "accepted conflicting entry identities");
   Expect_Bad
     ("<!DOCTYPE ListVersionsResult [<!ENTITY x 'bad'>]>" & Page (""),
      "accepted DTD");
   Expect_Bad
     (Page
        (Version_With
           (Extra => "<ChecksumAlgorithm>SHA256</ChecksumAlgorithm>" &
              "<ChecksumType>UNKNOWN</ChecksumType>")),
      "accepted unknown checksum type");
   Expect_Bad
     (Page
        ("<Version><ETag>a</ETag><ETag>b</ETag><Size>1</Size>" &
         "<StorageClass>STANDARD</StorageClass><Key>key</Key>" &
         "<VersionId>v</VersionId><IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted duplicate ObjectVersion scalar");
   Expect_Bad
     (Page
        (Version_With
           (Extra => "<Owner><ID>a</ID><ID>b</ID></Owner>")),
      "accepted duplicate owner member");
   Expect_Bad
     (Page
        (Version_With
           (Extra => "<Owner><Unknown>x</Unknown></Owner>")),
      "accepted unknown owner member");
   Expect_Bad
     (Page
        (Version_With
           (Extra => "<RestoreStatus><IsRestoreInProgress>true" &
              "</IsRestoreInProgress><IsRestoreInProgress>false" &
              "</IsRestoreInProgress></RestoreStatus>")),
      "accepted duplicate restore member");
   Expect_Bad
     (Page
        ("<CommonPrefixes><Prefix>a/</Prefix><Unknown/>" &
         "</CommonPrefixes>"),
      "accepted unknown common-prefix member");

   declare
      Algorithms : constant array (Positive range <>) of
        US.Unbounded_String :=
          (US.To_Unbounded_String ("CRC32"),
           US.To_Unbounded_String ("CRC32C"),
           US.To_Unbounded_String ("SHA1"),
           US.To_Unbounded_String ("SHA256"),
           US.To_Unbounded_String ("CRC64NVME"),
           US.To_Unbounded_String ("SHA512"),
           US.To_Unbounded_String ("MD5"),
           US.To_Unbounded_String ("XXHASH64"),
           US.To_Unbounded_String ("XXHASH3"),
           US.To_Unbounded_String ("XXHASH128"));
   begin
      for Algorithm of Algorithms loop
         declare
            Value : constant Versions.List_Object_Versions_Result :=
              Versions.Parse_List_Object_Versions
                (Page
                   (Version_With
                      (Extra => "<ChecksumAlgorithm>" &
                         US.To_String (Algorithm) &
                         "</ChecksumAlgorithm><ChecksumType>COMPOSITE" &
                         "</ChecksumType>")));
         begin
            Require
              (Value.Versions.First_Element.Checksum_Algorithms.Length = 1
               and then US.To_String
                 (Value.Versions.First_Element.Checksum_Algorithms.
                    First_Element) = US.To_String (Algorithm),
               "pinned checksum algorithm did not round-trip");
         end;
      end loop;
   end;

   declare
      Value : constant Versions.List_Object_Versions_Result :=
        Versions.Parse_List_Object_Versions
          (Page (Version_With (Size => "9223372036854775807")));
   begin
      Require
        (Value.Versions.First_Element.Size = 9_223_372_036_854_775_807,
         "maximum 64-bit object size did not round-trip");
   end;
   Expect_Bad
     (Page (Version_With (Size => "9223372036854775808")),
      "accepted overflowing 64-bit object size");

   declare
      Valid_Document : constant String := Page ("");
      Value : constant Versions.List_Object_Versions_Result :=
        Versions.Parse_List_Object_Versions
          (Valid_Document,
           (Maximum_Document_Bytes => Valid_Document'Length,
            Maximum_Depth          => 2,
            Maximum_Elements       => 4,
            Maximum_Text_Bytes     => 13));
      pragma Unreferenced (Value);
   begin
      Expect_Bad
        (Valid_Document, "accepted document one byte past limit",
         (Maximum_Document_Bytes => Valid_Document'Length - 1,
          Maximum_Depth          => 2,
          Maximum_Elements       => 4,
          Maximum_Text_Bytes     => 13));
      Expect_Bad
        (Valid_Document, "accepted depth one past limit",
         (Maximum_Document_Bytes => Valid_Document'Length,
          Maximum_Depth          => 1,
          Maximum_Elements       => 4,
          Maximum_Text_Bytes     => 13));
      Expect_Bad
        (Valid_Document, "accepted element one past limit",
         (Maximum_Document_Bytes => Valid_Document'Length,
          Maximum_Depth          => 2,
          Maximum_Elements       => 3,
          Maximum_Text_Bytes     => 13));
      Expect_Bad
        (Valid_Document, "accepted text one byte past limit",
         (Maximum_Document_Bytes => Valid_Document'Length,
          Maximum_Depth          => 2,
          Maximum_Elements       => 4,
          Maximum_Text_Bytes     => 12));
   end;

   declare
      Identity : constant Low_Level.Credentials :=
        Low_Level.Make_Credentials ("AKID", "SECRET");
      Parameters : Low_Level.List_Object_Versions_Parameters;
   begin
      Parameters.Delimiter := US.To_Unbounded_String ("/");
      Parameters.Has_Delimiter := True;
      Parameters.URL_Encoding := True;
      Parameters.Key_Marker := US.To_Unbounded_String ("logs/a");
      Parameters.Has_Key_Marker := True;
      Parameters.Max_Keys := 2;
      Parameters.Has_Max_Keys := True;
      Parameters.Prefix := US.To_Unbounded_String ("logs/");
      Parameters.Has_Prefix := True;
      Parameters.Version_ID_Marker := US.To_Unbounded_String ("v+1");
      Parameters.Has_Version_ID_Marker := True;
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String ("123456789012");
      Parameters.Request_Payer := US.To_Unbounded_String ("requester");
      Parameters.Include_Restore_Status := True;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Object_Versions
             (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
              Low_Level.Path_Style, "example-bucket", Parameters,
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Low_Level.Target (Prepared) =
              "/example-bucket?delimiter=%2F&encoding-type=url&" &
              "key-marker=logs%2Fa&max-keys=2&prefix=logs%2F&" &
              "version-id-marker=v%2B1&versions"
            and then Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               "x-amz-expected-bucket-owner") > 0
            and then Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               "x-amz-optional-object-attributes") > 0
            and then Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               "x-amz-request-payer") > 0,
            "complete request projection mismatch");
      end;

      Parameters.Has_Key_Marker := False;
      Parameters.Key_Marker := US.Null_Unbounded_String;
      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_List_Object_Versions
                   (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
                    Low_Level.Path_Style, "example-bucket", Parameters,
                    Identity, "us-east-1", "20130524T000000Z");
               pragma Unreferenced (Prepared);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Require (Raised, "accepted unpaired request version marker");
      end;
   end;

   declare
      Outcome : constant Low_Level.List_Object_Versions_Outcome :=
        Low_Level.Decode_List_Object_Versions_Response
          (200, Page ("", Maximum => "2"), Request_Charged => "requester");
   begin
      Require
        (Outcome.Kind = Low_Level.Listed
         and then Outcome.Status = 200
         and then US.To_String (Outcome.Result.Listing.Name) = "bucket"
         and then US.To_String (Outcome.Result.Request_Charged) = "requester",
         "typed success decode mismatch");
   end;

   declare
      Outcome : constant Low_Level.List_Object_Versions_Outcome :=
        Low_Level.Decode_List_Object_Versions_Response
          (403,
           "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>",
           Request_ID => "request-id", Host_ID => "host-id");
   begin
      Require
        (Outcome.Kind = Low_Level.Rejected
         and then US.To_String (Outcome.Error.Code) = "AccessDenied"
         and then US.To_String (Outcome.Error.Request_ID) = "request-id"
         and then US.To_String (Outcome.Error.Host_ID) = "host-id",
         "typed error decode mismatch");
   end;

   declare
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant Low_Level.List_Object_Versions_Outcome :=
              Low_Level.Decode_List_Object_Versions_Response
                (200, Page (""), Request_Charged => "owner");
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "accepted invalid request-charged header");
   end;
end S3_List_Object_Versions_Corpus;
