# Correctness discovery: S3-DOMAIN-A (bucket-level typed codecs)

Scope: read in full, specification then body, against the pinned model:
`src/flyology-object_storage-s3-acl.ad?` (112+393), `-lifecycle.ad?` (256+1139), `-replication.ad?` (236+1154), `-notifications.ad?` (201+680), `-versioning.ad?` (54+234), `-versions.ad?` (207+1389), `-listings.ad?` (290+1275), `-buckets.ad?` (221+1123), `-bucket_controls.ad?` (264+946), `-encryption.ad?` (117+457), `-website.ad?` (126+512), `-logging.ad?` (98+501), `-inventory.ad?` (182+654), `-analytics.ad?` (176+813), `-metrics.ad?` (127+676), `-intelligent_tiering.ad?` (154+763), `-metadata_configurations.ad?` (312+1545), `-metadata_tables.ad?` (106+666), and the five generated units `-generated_{list_directory_buckets,put_bucket_acl,put_bucket_inventory_configuration,put_bucket_logging,put_bucket_website}_xml.ad?` with the generator regions `tools/s3_codegen.py:805-830` and `:1922-1990`. Shared infrastructure read once for behaviour the codecs depend on: `s3-xml.adb:55-125` (SAX dispatch), `:186-260` (`Escape`), `s3-xml_writers.adb` (all), `s3-paginated_rest_xml_reads.ads` and `.adb:120-145,275-300`, `s3-strict_xml_codecs.adb` (enforcement points). Reference: `review/baseline/service-2.json`, loaded with python3; for every codec the shape's member names, `locationName`, `flattened`, `xmlNamespace`, `required` lists, enumerations and min/max were dumped and compared with the decoder and encoder; `docs/compatibility/s3.md` rows 12-67; `docs/qualification/{list-objects-v1,list-object-versions,list-bucket-configurations,list-directory-buckets}.md`. Coverage inspected: `tests/src/object_storage_test_cases.adb` (listing and versioning regions), `tests/src/s3_list_object_versions_corpus.adb`, `tests/corpora/list-object-versions/*.tsv`, `tests/src/s3_implementation_corpus.adb:255-276,985-1045`, `tests/scripts/test-{minio,rustfs,seaweedfs}.sh`, `tests/src/s3_server_application_corpus.adb` (codec call sites), `tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb` and `s3_bucket_notification_configuration_corpus.adb` (searched). Callers: every codec in this area is consumed by `client-low_level`, `client-buckets` and `client-objects`; the server (`server-s3_applications.adb`) additionally calls `Versioning.Parse`, `Lifecycle.Parse`, `Notifications.Parse`, `Buckets.Parse_Create_Configuration`, and the four query parsers under renamed packages.

Severity rubric: P0 memory/aliasing unsafety, security-relevant, data loss or durability violation, hang or deadlock, or an interop-breaking protocol violation that a stock client or server rejects. P1 wrong result or unexpected exception on valid input via a reachable path, or a documented contract violated (`.ads` comment, README, compatibility matrix, qualification document). P2 edge-case incorrectness, wrong diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| S3-DOMAIN-A-1 | ListObjectVersions decoder rejects every `Version` whose `StorageClass` is not `STANDARD` | P1 | Medium |
| S3-DOMAIN-A-2 | ListObjects v1 decoder rejects a truncated page that carries `NextMarker` without a delimiter, which the three pinned third-party servers all emit | P1 | High |
| S3-DOMAIN-A-3 | Lifecycle and Notifications serializers reject U+007F in text values that XML 1.0, the shared escape boundary, their own parsers and the Replication serializer all accept | P2 | Medium |
| S3-DOMAIN-A-4 | The ListBucket{Inventory,Metrics,Analytics}Configurations and ListDirectoryBuckets decoders require the botocore output *shape* name as the XML root, which is not the element AWS S3 sends | P1 | Medium |
| S3-DOMAIN-A-5 | The server-side PutBucketVersioning body parser is the only request codec that rejects an unqualified root, so a stock client that omits `xmlns` on this body alone is refused | P2 | Medium |

---

### S3-DOMAIN-A-1: ListObjectVersions decoder rejects every `Version` whose `StorageClass` is not `STANDARD`

**Location:** `src/flyology-object_storage-s3-versions.adb:798-805` (decode), `:355-363` and `:365-382` (enumeration lookup), `:893-919` (`Finish_Version` makes `StorageClass` mandatory), `:1211-1214` (server-side serializer applies the same one-value domain).

**Severity:** P1. **Confidence:** Medium (the code path is certain; that real servers emit non-`STANDARD` classes in `ListObjectVersions` is from memory, unverified, with a concrete check path given below).

**Evidence:**

`src/flyology-object_storage-s3-versions.adb:355-363`
```ada
   function Version_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Version_List : constant Model.Shape_Index := Output_Member_Shape (6);
      Version_Shape : constant Model.Shape_Index := Model.Shape_Index
        (Model.List_Member_Shape (Version_List));
   begin
      return Model.Member_Shape (Version_Shape, Member);
   end Version_Member_Shape;
```

`src/flyology-object_storage-s3-versions.adb:798-805`
```ada
         when Storage_Class_Field =>
            Require_Name ("StorageClass");
            if not Valid_Enumeration (Value, Version_Member_Shape (5)) then
               raise Malformed_Version_Listing with
                 "invalid ObjectVersion storage class";
            end if;
            Item.Current_Version.Storage_Class := Item.Text_Value;
            Item.Current_Version.Has_Storage_Class := True;
```

`src/flyology-object_storage-s3-versions.adb:893-902`
```ada
   procedure Finish_Version (Item : in out Version_Listing_Handler) is
      Value : Object_Version renames Item.Current_Version;
   begin
      if not Value.Has_Key or else US.Length (Value.Key) = 0
        or else not Value.Has_Version_ID
        or else US.Length (Value.Version_ID) = 0
        or else not Value.Has_Is_Latest
        or else not Value.Has_Last_Modified
        or else not Value.Has_Size
        or else not Value.Has_Storage_Class
```

Member 5 of `ObjectVersion` is `StorageClass` whose shape is `ObjectVersionStorageClass`; the pinned model (`review/baseline/service-2.json`) defines that enumeration as exactly `['STANDARD']`, whereas the `Object` shape used by ListObjects v1/v2 uses `ObjectStorageClass` with fifteen values (`STANDARD, REDUCED_REDUNDANCY, GLACIER, STANDARD_IA, ONEZONE_IA, INTELLIGENT_TIERING, DEEP_ARCHIVE, OUTPOSTS, GLACIER_IR, SNOW, EXPRESS_ONEZONE, FSX_OPENZFS, FSX_ONTAP, AWS_BACKUP_WARM, AWS_BACKUP_LOW_COST_WARM`). The Listings codec accepts all fifteen (`src/flyology-object_storage-s3-listings.adb:648-653`, member 7 of `Object`), so the same object that ListObjectsV2 decodes with `StorageClass=STANDARD_IA` makes ListObjectVersions raise.

The `ObjectVersionStorageClass` one-value enumeration is a documentation artifact of the botocore model; botocore does not validate output enumerations and AWS S3 returns the version's actual class (`STANDARD_IA`, `GLACIER`, `INTELLIGENT_TIERING`, ...) in `ListVersionsResult/Version/StorageClass` for objects uploaded to or transitioned into another class (from memory, unverified). MinIO reports `REDUCED_REDUNDANCY` for objects uploaded with `x-amz-storage-class: REDUCED_REDUNDANCY` (from memory, unverified).

The qualification document states this as the contract (`docs/qualification/list-object-versions.md:90-91`: "Every ObjectVersion has ... exact pinned storage class"), and `tests/corpora/list-object-versions/members.tsv:30` says "Require exactly one pinned ObjectVersion storage class value." The contract is documented, but it makes valid responses undecodable.

**Failure scenario:** A caller lists versions of a bucket in which at least one object version is in any class other than `STANDARD` (an object uploaded with `x-amz-storage-class: STANDARD_IA`, or one transitioned by a lifecycle rule). The server returns a valid `ListVersionsResult` whose `<Version>` carries `<StorageClass>STANDARD_IA</StorageClass>`. `Finish_Field` at `:800` calls `Valid_Enumeration` against the one-value enumeration, which returns False, and `Malformed_Version_Listing` is raised at `:801`. `Parse_List_Object_Versions` (`:1126-1150`) propagates it; `Client.Low_Level` maps it to an invalid-response outcome (the `S3.Versions.Malformed_Version_Listing` handler in `client-low_level.adb`) and `Client.Objects.List_Versions_Page` returns no page. The whole listing is lost because of one entry; there is no way to page past it.

**Reproduction test sketch:** Pure codec: call `S3.Versions.Parse_List_Object_Versions` on
`<ListVersionsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>b</Name><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Version><Key>k</Key><VersionId>v1</VersionId><IsLatest>true</IsLatest><LastModified>2026-01-01T00:00:00.000Z</LastModified><ETag>"e"</ETag><Size>1</Size><StorageClass>STANDARD_IA</StorageClass></Version></ListVersionsResult>`.
Expected (correct): one version with `Storage_Class = "STANDARD_IA"`. Actual: `Malformed_Version_Listing` "invalid ObjectVersion storage class". Live check: against the pinned MinIO (`tests/scripts/test-minio.sh` image) enable versioning, `PutObject` with `x-amz-storage-class: REDUCED_REDUNDANCY`, then GET `?versions` and feed the body to the parser (or run `Client.Objects.List_Versions_Page`). The Flyology memory server cannot show it because its serializer (`:1211-1214`) refuses to emit anything but `STANDARD`.

**Existing coverage:** `tests/src/s3_list_object_versions_corpus.adb:335-341` asserts the wrong behaviour: `Expect_Bad (Page ("<Version><Size>1</Size><StorageClass>GLACIER</StorageClass>...")), "accepted unmodeled storage class")`. `tests/corpora/list-object-versions/vectors.tsv:12` (LOV-RS-006) pins "exact pinned storage class".

**Refutation attempts:** Checked whether `Valid_Enumeration` falls back to accepting any string when the shape has an enumeration; it returns False for any value outside the list (`:373-381`). Checked whether a caller could pre-filter or tolerate the exception: `Parse_List_Object_Versions` is the only decode path and the exception is raised before any entry is returned. Checked whether the Flyology server ever emits another class: `Validate_Version` in the serializer (`:1211-1214`) uses the same one-value enumeration, so the in-house server round-trips, which is why the corpus passes. Checked the ListObjects codec for the same object: it validates against the fifteen-value `ObjectStorageClass` (`listings.adb:648-653`), so the crate is internally inconsistent about which storage classes an object may report.

---

### S3-DOMAIN-A-2: ListObjects v1 decoder rejects a truncated page that carries `NextMarker` without a delimiter, which the three pinned third-party servers all emit

**Location:** `src/flyology-object_storage-s3-listings.adb:1087-1116` (`Validate` for `List_Objects_Result`), `:1144-1163` (`Parse_List_Objects`), consumer `src/flyology-object_storage-client-objects.adb:403-422` (`List_V1_Page`).

**Severity:** P1. **Confidence:** High (the repository's own qualification document records the server behaviour and the oracle exclusion).

**Evidence:**

`src/flyology-object_storage-s3-listings.adb:1093-1094`
```ada
      Effective_Delimiter : constant Boolean :=
        Value.Has_Delimiter and then US.Length (Value.Delimiter) > 0;
```

`src/flyology-object_storage-s3-listings.adb:1108-1116`
```ada
      elsif Value.Has_Next_Marker /=
        (Value.Is_Truncated and then Effective_Delimiter)
        or else
          (Value.Has_Next_Marker and then US.Length (Value.Next_Marker) = 0)
        or else
          (not Value.Has_Next_Marker
           and then US.Length (Value.Next_Marker) > 0)
      then
         raise Malformed_Listing with "inconsistent S3 next marker";
```

The pinned model (`ListObjectsOutput.NextMarker`, `review/baseline/service-2.json`) is an optional string with no cross-member constraint; the "only with a delimiter" rule is AWS-documented behaviour, not a wire rule other servers follow.

`docs/qualification/list-objects-v1.md:54-59`
```
Flyology memory, files, and SQLite. All 18 lanes passed on 2026-08-22. Pinned
RustFS, SeaweedFS, and MinIO each emit a non-model NextMarker on a truncated
v1 page without a delimiter. Their strict no-delimiter continuation subcase is
excluded explicitly; the basic v1 path remains enabled, while every Flyology
backend passes the complete two-page AWS fallback rule.
```

`tests/src/s3_implementation_corpus.adb:258-274` returns False from `Check_List_Objects_V1_Pagination` when `FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE` is `rustfs-rc3-next-marker-without-delimiter`, `seaweedfs-4.43-next-marker-without-delimiter` or `minio-2025-next-marker-without-delimiter`, and `tests/scripts/test-minio.sh:66-67` (likewise `test-rustfs.sh:71`, `test-seaweedfs.sh:78`) sets exactly that variable. The compatibility matrix row (`docs/compatibility/s3.md:65`) nevertheless claims "native/lightweight six-server oracle" for ListObjects v1.

The client already knows how to continue without `NextMarker` (`client-objects.adb:404-411` derives the marker from the last key when the element is absent), so accepting the element would cost nothing.

**Failure scenario:** A Flyology client pages a v1 listing of a bucket with more than `max-keys` objects and no delimiter against MinIO, RustFS or SeaweedFS. The first page is `IsTruncated=true` with `<NextMarker>last-key</NextMarker>` and no `<Delimiter>`. `Finish_Field` sets `Has_Next_Marker` (`:600-602`); `Validate` evaluates `True /= (True and then False)` at `:1108-1109` and raises `Malformed_Listing`. `Parse_List_Objects` propagates it (`:1158`), the low-level client reports an invalid response, and `List_V1_Page` never returns the first page. The convenience pagination and every caller above it fail on any non-trivial bucket.

**Reproduction test sketch:** Pure codec: `S3.Listings.Parse_List_Objects ("<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/2006-03-01/""><Name>b</Name><MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated><NextMarker>a</NextMarker><Contents><Key>a</Key><Size>1</Size></Contents></ListBucketResult>")`. Expected (correct): a page with one object, `Is_Truncated = True`, `Has_Next_Marker = True`, `Next_Marker = "a"`. Actual: `Malformed_Listing` "inconsistent S3 next marker". Live: run `tests/scripts/test-minio.sh` with `FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE` unset (the gate then runs the two-page v1 exchange, `s3_implementation_corpus.adb:1006-1040`) and observe the failure the scripts currently suppress. The Flyology memory server cannot show it because its own serializer omits `NextMarker` in that case (`docs/qualification/list-objects-v1.md:22-24`).

**Existing coverage:** `tests/src/object_storage_test_cases.adb:9597-9599` asserts the wrong behaviour for the final-page variant (`Must_Reject_Document (Empty_Listing ("<NextMarker>unexpected</NextMarker>"), "ListObjects marker on final page was accepted")`); the truncated no-delimiter variant is covered only by the excluded oracle subcase above. `tests/src/s3_http_socket_corpus.adb:11893-11945` asserts against the Flyology server that `Page.Has_Next_Marker` is False without a delimiter, which does not exercise the failing branch.

**Refutation attempts:** Checked whether the Docker matrix would have caught it: the three scripts set the oracle-mode variable that disables the subcase, so no lane exercises it. Checked whether `Has_Delimiter` with an empty echoed `<Delimiter/>` rescues the MinIO case: `Effective_Delimiter` requires a non-empty delimiter, so it does not. Checked whether the model supports the rule: `NextMarker` is an unconstrained optional string. Checked whether the client's low-level decode path bypasses `Validate`: `Parse_List_Objects` always calls it (`:1158`).

---

### S3-DOMAIN-A-3: Lifecycle and Notifications serializers reject U+007F in text values that XML 1.0, the shared escape boundary, their own parsers and the Replication serializer all accept

**Location:** `src/flyology-object_storage-s3-lifecycle.adb:774-824` (`Valid_XML_UTF8`, first-byte range at `:789-790`), `:852-863` (`Add_Text`); `src/flyology-object_storage-s3-notifications.adb:488-538` (`:503-504`), `:566-577`; compare `src/flyology-object_storage-s3-replication.adb:828-829` and `src/flyology-object_storage-s3-xml.adb:221-226`.

**Severity:** P2. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage-s3-lifecycle.adb:789-792`
```ada
               if First in 16#20# .. 16#7E#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
```

`src/flyology-object_storage-s3-notifications.adb:503-506`
```ada
               if First in 16#20# .. 16#7E#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
```

`src/flyology-object_storage-s3-replication.adb:828-831`
```ada
               if First in 16#20# .. 16#7F#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
```

`src/flyology-object_storage-s3-xml.adb:221-226` (the shared boundary every other codec uses)
```ada
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise XML_Error with "invalid XML character";
```

XML 1.0 `Char ::= #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] | [#x10000-#x10FFFF]` includes #x7F. The lifecycle comment at `:771-773` says the validator "keeps the serializer from emitting bytes the matching parser must reject", but the matching parser (XMLAda through `S3.XML.Parse`) accepts DEL, so a lifecycle rule read from a server (`Lifecycle.Parse`) whose `ID`, `Prefix`, tag `Key`/`Value` contains DEL cannot be written back (`Lifecycle.Serialize` raises "invalid lifecycle XML text" at `:855`). S3 object keys may contain DEL (the crate's own `Valid_Object_Key`, `src/flyology-object_storage.adb:479-490`, rejects only NUL), so a lifecycle `Prefix` or tag containing it is a legal, if unusual, configuration.

**Failure scenario:** `Lifecycle.Parse` decodes a rule with `<Prefix>logs&#x7F;</Prefix>` (or the caller builds one with a DEL in `ID`). `Client.Buckets` typed `PutBucketLifecycleConfiguration` calls `Lifecycle.Serialize`; `Add_Text` (`:854`) returns False from `Valid_XML_UTF8` and `Malformed_Lifecycle` is raised before any request is sent. The same configuration serializes through `Replication.Serialize` (same byte set) and through every `XML_Writers`/`Escape_Text` based codec.

**Reproduction test sketch:** `Lifecycle.Serialize (Lifecycle.Parse ("<LifecycleConfiguration><Rule><ID>a" & Character'Val (16#7F#) & "</ID><Status>Enabled</Status><Expiration><Days>1</Days></Expiration></Rule></LifecycleConfiguration>"), XML.Default_Limits)`. Expected (correct): the document with the same ID. Actual: `Malformed_Lifecycle` "invalid lifecycle XML text". Same shape with `Notifications` (`Id` text) fails the same way; `Replication.Serialize (Replication.Parse (...ID with DEL...))` succeeds.

**Existing coverage:** none for U+007F; `tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb` and `tests/src/s3_bucket_notification_configuration_corpus.adb` exercise C0 controls and invalid UTF-8 only (searched for `7F`/`127`, none).

**Refutation attempts:** Checked whether `S3.XML.Escape_Text` rejects DEL so that the validators merely front-run it: it only rejects bytes below 32 other than TAB/LF/CR. Checked whether the crate's key domain excludes DEL so the input could be called invalid: `Valid_Object_Key` excludes only NUL. Checked whether the three validators were meant to differ: all three carry the same comment about "raw C0 controls", and DEL is not a C0 control.

---

### S3-DOMAIN-A-4: The ListBucket{Inventory,Metrics,Analytics}Configurations and ListDirectoryBuckets decoders require the botocore output *shape* name as the XML root, which is not the element AWS S3 sends

**Location:** `src/flyology-object_storage-s3-inventory.adb:608-614`, `src/flyology-object_storage-s3-metrics.adb:468-474`, `src/flyology-object_storage-s3-analytics.adb:572-578` (and `src/flyology-object_storage-s3-intelligent_tiering.adb:528-534` for completeness); enforcement in `src/flyology-object_storage-s3-paginated_rest_xml_reads.adb:134` and `:284`. Generated: `src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:12-13` from `tools/s3_codegen.py:815-816`, enforced by `src/flyology-object_storage-s3-strict_xml_codecs.adb:313-315`.

**Severity:** P1. **Confidence:** Medium (the enforcement is certain; the AWS wire root names are from memory, unverified, and cannot be checked against the pinned MinIO/RustFS/SeaweedFS because none of them implements these operations; the check path is the AWS S3 API Reference "Response Syntax" section of each operation, or the aws-sdk-java v1 `XmlResponsesSaxParser` handlers, which match on the root element).

**Evidence:**

`src/flyology-object_storage-s3-inventory.adb:608-614`
```ada
   --  Both element names are fixed by the pinned Botocore operation/output
   --  model. Changing either changes accepted S3 wire documents.
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                   =>
        "ListBucketInventoryConfigurationsOutput",
      Item_Container_Name         => "",
      Item_Name                   => "InventoryConfiguration",
```

`src/flyology-object_storage-s3-paginated_rest_xml_reads.adb:133-136`
```ada
      elsif Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= Root_Name then
            raise Malformed_Page with "invalid configuration-list root";
         end if;
```

`src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:9-13`
```ada
   function Element_Name (Element : Element_Id) return String is
   begin
      case Element is
         when Root =>
            return "ListDirectoryBucketsOutput";
```

`tools/s3_codegen.py:815-816` (generator rule; the output shapes carry no `locationName`, so the shape name becomes the root)
```python
    root_shape = payload_shape(model, operation, entry)
    root_name = shapes[root_shape].get("locationName", root_shape)
```

`src/flyology-object_storage-s3-strict_xml_codecs.adb:313-315`
```ada
         Element := Root_Element;
         if Local_Name /= Element_Name (Root_Element) then
            raise Malformed_Document with "invalid XML root";
```

The pinned model gives no root name for these outputs (`ListBucketInventoryConfigurationsOutput`, `ListBucketMetricsConfigurationsOutput`, `ListBucketAnalyticsConfigurationsOutput`, `ListDirectoryBucketsOutput` have no `locationName` and no `resultWrapper`; checked with python3), because botocore's rest-xml parser ignores the root element name. The AWS S3 API Reference documents the wire roots as `<ListInventoryConfigurationsResult>` (ListBucketInventoryConfigurations), `<ListMetricsConfigurationsResult>` (ListBucketMetricsConfigurations), `<ListBucketAnalyticsConfigurationResult>` (ListBucketAnalyticsConfigurations) and `<ListAllMyDirectoryBucketsResult>` (ListDirectoryBuckets), while `<ListBucketIntelligentTieringConfigurationsOutput>` is the documented root for the Intelligent-Tiering listing (all from memory, unverified). The same crate already uses the wire names where they differ from the shape names for older operations (`ListVersionsResult`, `ListAllMyBucketsResult`, `ListBucketResult`) and for the metadata reads (`GetBucketMetadataConfigurationResult`, `GetBucketMetadataTableConfigurationResult`, `metadata_configurations.adb:211`, `metadata_tables.adb:100-101`), which shows the model shape name was not intended as the wire root.

The in-house server emits the same shape names (`server-s3_applications.adb:9599-9608` and `:7237`), and `docs/qualification/list-directory-buckets.md:14` documents "an empty `<ListDirectoryBucketsOutput/>` document" as the server's wire contract, so every in-repository test round-trips while both sides disagree with AWS. `docs/compatibility/s3.md:37-40` claims a "complete provider-owned composable and typed synchronous one-page client" for the four listings and the ListDirectoryBuckets qualification claims the same for that operation.

**Failure scenario:** A Flyology client calls `ListBucketInventoryConfigurations` (or metrics, analytics, or `ListDirectoryBuckets`) against AWS S3, the only provider that implements these operations. The 200 response begins `<ListInventoryConfigurationsResult xmlns="...">`. `Page_Handler.Start_Element` compares the local name with `Root_Name` at `paginated_rest_xml_reads.adb:134` and raises `Malformed_Page`; `Inventory.Parse_List` converts it to `Malformed_Inventory` "malformed inventory-list XML" (`inventory.adb:644-652`), and the typed client reports an invalid response. For `ListDirectoryBuckets`, `strict_xml_codecs.adb:314` raises `Malformed_Document` on `<ListAllMyDirectoryBucketsResult>`. No response from the real provider is ever decodable.

**Reproduction test sketch:** Pure codec: `S3.Inventory.Parse_List ("<ListInventoryConfigurationsResult xmlns=""http://s3.amazonaws.com/doc/2006-03-01/""><IsTruncated>false</IsTruncated></ListInventoryConfigurationsResult>", XML.Default_Limits)`. Expected (correct, if the AWS root is as documented): an empty page with `Has_Is_Truncated = True`. Actual: `Malformed_Inventory`. Same for `Metrics.Parse_List` with `<ListMetricsConfigurationsResult>`, `Analytics.Parse_List` with `<ListBucketAnalyticsConfigurationResult>`, and `Generated_List_Directory_Buckets_XML.Parse` with `<ListAllMyDirectoryBucketsResult><Buckets/></ListAllMyDirectoryBucketsResult>`. No pinned Docker server can show it; the verifier must settle the root names from the AWS API Reference (or an AWS account).

**Existing coverage:** `tests/src/s3_list_bucket_{inventory,metrics,analytics}_configurations_qualification.adb` and `tests/src/s3_list_directory_buckets_qualification.adb` drive the Flyology server, which emits the shape names, so they pass without touching the question. No test or document in the repository mentions any of the AWS root names (searched `src/`, `docs/`, `tests/`).

**Refutation attempts:** Checked whether the paginated reader could be lenient about the root: it compares the exact `Root_Name` on open and close (`:134`, `:284`). Checked whether the model carries the wire root anywhere (`locationName` on the output shape or payload member, `resultWrapper`): it does not, for any of the five operations, nor for `ListObjectVersions`/`ListBuckets` whose codecs nevertheless use the wire names. Checked whether the generator has a root-name override table: `tools/s3_codegen.py:816` and `:1932` use `locationName` or the shape name only, which is correct for request payloads (every PUT payload member carries a `locationName`) and wrong for responses.

---

### S3-DOMAIN-A-5: The server-side PutBucketVersioning body parser is the only request codec that rejects an unqualified root, so a stock client that omits `xmlns` on this body alone is refused

**Location:** `src/flyology-object_storage-s3-versioning.adb:41-55` (`Start_Element_Details`), `:171-183` (`Parse` versus `Parse_Response`); caller `src/flyology-object_storage-server-s3_applications.adb:10423-10425`.

**Severity:** P2 by the evidence in the repository; P0 by the rubric if a stock client is confirmed to send the body without `xmlns` (the rubric's "interop-breaking protocol violation that a stock client ... rejects"). **Confidence:** Medium (the code and the inconsistency with the sibling request codecs are certain; the claim that MinIO's `mc`/minio-go marshals `VersioningConfiguration` without a namespace, while marshalling `CreateBucketConfiguration` with one, is from memory, unverified; check path: run `mc version enable` or `mc mb` followed by minio-go `SetBucketVersioning` against the Flyology memory server through `tests/src/s3_server_harness.adb`, or inspect minio-go's `BucketVersioningConfiguration` struct tags).

**Evidence:**

`src/flyology-object_storage-s3-versioning.adb:47-54`
```ada
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then
            (not Item.Allow_Empty_Namespace or else Namespace_URI'Length > 0))
        or else Attribute_Count /= 0
      then
         raise Malformed_Configuration with
           "bucket versioning namespace or attributes are invalid";
      end if;
```

`src/flyology-object_storage-s3-versioning.adb:171-183`
```ada
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration is
     (Parse_Document
        (Document, Limits, Allow_Empty_Namespace => False));

   function Parse_Response
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration is
     (Parse_Document
        (Document, Limits, Allow_Empty_Namespace => True));
```

`src/flyology-object_storage-server-s3_applications.adb:10423-10425`
```ada
                                 Configuration : constant
                                   Bucket_Versioning_Configuration :=
                                     Versioning.Parse (Document);
```

Every other request-body codec the server calls accepts an unqualified root: `Lifecycle.Parse` (`lifecycle.adb:70-84`, `Unqualified` allowed), `Notifications.Parse` (`notifications.adb:166-181`), `Buckets.Parse_Create_Configuration` (no namespace check at all, `buckets.adb:531-611`), and the metadata request parsers (`metadata_configurations.adb:750-765`). The model marks the payload with `xmlNamespace` (`PutBucketVersioningRequest.VersioningConfiguration`), which botocore-derived SDKs emit, but the model does not make the namespace a wire precondition, and the same crate's `Parse_Response` documents that "a few otherwise compatible implementations omit it" (`versioning.ads:30-32`). The compatibility matrix row (`docs/compatibility/s3.md:57`) claims an "authenticated path-style server" for Put/Get bucket versioning.

**Failure scenario:** A client sends `PUT /bucket?versioning` with a valid Content-MD5 and body `<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>`. The server passes the Content-MD5 and checksum gates (`:10399-10420`), calls `Versioning.Parse` at `:10425`, `Start_Element_Details` raises `Malformed_Configuration` at `:52`, and the server answers 400 `MalformedXML` (the handler that follows the `Versioning.Malformed_Configuration` branch). The same client's lifecycle and notification PUTs, sent the same way, succeed.

**Reproduction test sketch:** Over the in-process loopback (`tests/src/s3_server_harness.adb`, `s3_memory_server.adb`): signed `PUT /b?versioning` with `Content-MD5` of the body above and no `xmlns`. Expected (consistent with the sibling codecs and with a namespace-agnostic server): 200 and a subsequent `GET ?versioning` reporting `Enabled`. Actual: 400. Pure codec: `Versioning.Parse ("<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>")` raises `Malformed_Configuration`, while `Lifecycle.Parse ("<LifecycleConfiguration><Rule><Status>Enabled</Status></Rule></LifecycleConfiguration>")` succeeds.

**Existing coverage:** `tests/src/object_storage_test_cases.adb:21868-21871` asserts the rejection (`Expect_Malformed ("<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>", "namespace-free versioning request accepted")`) and `:21879-21886` asserts that `Parse_Response` accepts the same document; `tests/src/s3_server_application_corpus.adb:10375-10391` sends only namespaced bodies.

**Refutation attempts:** Checked whether the server calls the lenient `Parse_Response` for requests: it calls `Parse` (`:10425`). Checked whether aws-cli/boto3 and aws-sdk-go (s5cmd) omit the namespace: they serialize the model's `xmlNamespace`, so they are unaffected; the CI's s5cmd lanes never send this body. Checked whether the strictness is documented as a limitation: the `.ads` documents "fail closed" for `Parse`, but neither the matrix row nor `docs/qualification/put-bucket-versioning.md` names the namespace as a client requirement (searched for `xmlns`/`namespace`).

---

## Areas reviewed with no findings

- `S3.ACL` (`acl.ad?`): `AccessControlPolicy/Owner{DisplayName,ID}/AccessControlList/Grant{Grantee[xsi:type]{DisplayName,EmailAddress,ID,URI},Permission}` matches the model member for member; all three `Type` values and five `Permission` values decode; `xsi:type` is required exactly once in the XML-Schema-instance namespace; unqualified and S3-qualified roots accepted consistently; duplicates and unknown members rejected; `Grantee_Type_Seen` (`:193`, `:324`) is always True and therefore a dead check (harmless).
- `S3.Lifecycle` decoder and encoder: all nine `Rule` members, `Filter{Prefix,Tag,ObjectSizeGreaterThan,ObjectSizeLessThan,And{Prefix,Tag*,sizes}}`, `Expiration`, flattened `Transition`/`NoncurrentVersionTransition`, `NoncurrentVersionExpiration`, `AbortIncompleteMultipartUpload`; `Status` required per rule; all six `TransitionStorageClass` values; arbitrary-precision integers; ISO-8601 with fraction and offset, no exception paths on short input; encoder emits model order, escapes every text, omits unset optionals, refuses inconsistent absent members, round-trips `Filter/And/Tag`; `Parse_Transition_Default_Minimum_Size` exact.
- `S3.Replication` decoder and encoder: `Role` and non-empty `Rule` list required; `Status` and `Destination{Bucket}` required per rule; nested `Status` required exactly where the model requires it (`SseKmsEncryptedObjects`, `ReplicaModifications`, `ExistingObjectReplication`, `ReplicationTime`+`Time`, `Metrics`) and optional in `DeleteMarkerReplication`; `AccessControlTranslation/Owner` fixed to `Destination`; all fifteen storage classes; encoder order and presence guards consistent; round-trips.
- `S3.Notifications` decoder and encoder: `TopicConfiguration`/`QueueConfiguration`/`CloudFunctionConfiguration` with `Id`, destination (`Topic`/`Queue`/`CloudFunction`), required non-empty `Event` list, `Filter/S3Key/FilterRule{Name,Value}`; all 30 `Event` values and both `FilterRuleName` values; `EventBridgeConfiguration` as an empty presence element; empty configuration valid.
- `S3.Versioning`: both members optional, both enumerations exact, response parser accepts unqualified roots; request strictness is S3-DOMAIN-A-5.
- `S3.Versions` (other than S3-DOMAIN-A-1): query parser accepts exactly the eight modeled members, rejects `version-id-marker` without `key-marker`; decoder covers all 13 body members, interleaved `Version`/`DeleteMarker`, `Owner`, `RestoreStatus`, `ChecksumAlgorithm` list with model enumeration, `EncodingType=url` only, duplicate-identity rejection, `IsLatest` booleans, timestamps; serializer presence-consistent.
- `S3.Listings` (other than S3-DOMAIN-A-2): v1 and v2 query parsers strict-percent decode with literal `+`, exact member sets, `list-type=2` required; decoders forward-compatible (unknown elements skipped), `Key` and `Size` required per object, enumerations for `StorageClass`/`ChecksumAlgorithm`/`ChecksumType` from the model, `KeyCount = Contents + CommonPrefixes`, `NextContinuationToken` iff truncated; continuation tokens bound to bucket/prefix/delimiter with SHA-256; serializers escape and preserve presence.
- `S3.Buckets`: `ListBuckets` query parser (`max-buckets` 1..10000, token 1024, region scope segment), forward-compatible `ListAllMyBucketsResult` decoder with `Owner` presence and the four `Bucket` members, 10,000-entry cap; `GetBucketLocation` legacy empty root plus `us-east-1` and the SeaweedFS wrapper; `CreateBucketConfiguration` parser and serializer cover `LocationConstraint`, `Location{Type,Name}`, `Bucket{DataRedundancy,Type}`, `Tags/Tag{Key,Value}` with the AWS tag limits.
- `S3.Bucket_Controls`: five scalar documents (`AbacStatus`, `AccelerateConfiguration`, `PolicyStatus`, `RequestPaymentConfiguration`, `PublicAccessBlockConfiguration`) with exact enumerations and `true`/`false` booleans; `OwnershipControls/Rule/ObjectOwnership` (all three values, non-empty rules required); `CORSConfiguration/CORSRule` with required `AllowedMethod`/`AllowedOrigin` lists and arbitrary-precision `MaxAgeSeconds`; serializers bounded, model order.
- `S3.Encryption`: `Rule{ApplyServerSideEncryptionByDefault{SSEAlgorithm required,KMSMasterKeyID},BucketKeyEnabled,BlockedEncryptionTypes/EncryptionType*}`; all five `ServerSideEncryption` values and both `EncryptionType` values; non-empty rules required; serializer presence-consistent.
- `S3.Website`: `RedirectAllRequestsTo{HostName required,Protocol}`, `IndexDocument{Suffix required}`, `ErrorDocument{Key required, non-empty}`, non-flattened `RoutingRules/RoutingRule{Condition{HttpErrorCodeReturnedEquals,KeyPrefixEquals},Redirect required{HostName,HttpRedirectCode,Protocol,ReplaceKeyPrefixWith,ReplaceKeyWith}}`; `http`/`https` only.
- `S3.Logging`: `LoggingEnabled{TargetBucket required,TargetGrants/Grant{Grantee[xsi:type],Permission},TargetPrefix required,TargetObjectKeyFormat{SimplePrefix,PartitionedPrefix{PartitionDateSource}}}`; disabled state when `LoggingEnabled` absent; all three permissions and both date sources.
- `S3.Inventory`: single and paged decoders cover `Destination/S3BucketDestination{AccountId,Bucket required,Format required,Prefix,Encryption{SSE-S3,SSE-KMS/KeyId required}}`, `IsEnabled`, `Filter/Prefix required`, `Id`, `IncludedObjectVersions`, `OptionalFields/Field*` (all 16 values), `Schedule/Frequency`; the five required members enforced at close; page root is S3-DOMAIN-A-4.
- `S3.Analytics`: `Id` and `StorageClassAnalysis` required; `Filter{Prefix,Tag,And{Prefix,Tag*}}`; `DataExport{OutputSchemaVersion=V_1,Destination/S3BucketDestination{Format=CSV,BucketAccountId,Bucket required,Prefix}}`; tag `Key` min 1 enforced; serializer re-parses its own output; page root is S3-DOMAIN-A-4.
- `S3.Metrics`: `Id` required; `Filter{Prefix,Tag,AccessPointArn,And{Prefix,Tag*,AccessPointArn}}` in model order; serializer re-parses; page root is S3-DOMAIN-A-4.
- `S3.Intelligent_Tiering`: `Id`, `Status` and non-empty flattened `Tiering{Days,AccessTier}` required; both status and both access-tier values; filter as above; page root uses the model name, which is also the documented AWS root for this operation (from memory).
- `S3.Metadata_Configurations`: result decoder (`GetBucketMetadataConfigurationResult/MetadataConfigurationResult{DestinationResult required,Journal{TableStatus,TableName,RecordExpiration required},Inventory{ConfigurationState required},Annotation{ConfigurationState required,Role}}`), create and the three update request parsers restricted to the modeled `...Updates` members, `EncryptionConfiguration{SseAlgorithm required,KmsKeyArn}`; all writers through `XML_Writers` in model order with presence invariants.
- `S3.Metadata_Tables`: `GetBucketMetadataTableConfigurationResult{MetadataTableConfigurationResult/S3TablesDestinationResult{four required strings},Status required,Error{ErrorCode,ErrorMessage}}`; create request `MetadataTableConfiguration/S3TablesDestination{TableBucketArn,TableName}`; serializers escape and bound.
- Generated request encoders (`Generated_Put_Bucket_{ACL,Inventory_Configuration,Logging,Website}_XML`): roots from the payload `locationName`, S3 namespace on the root, `xsi:type` written with its `xmlns:xsi` declaration (`xml_writers.adb:123-137`), every text through `Escape_Text`, optionals omitted when unset, required members always written; `SimplePrefix` and `SSE-S3` as empty elements.
- Generated `List_Directory_Buckets` decoder (other than the root name): `Buckets/Bucket{Name,CreationDate(timestamp),BucketRegion,BucketArn(min 1, max 128, `arn:*:s3|s3express:` pattern)}`, `ContinuationToken` (max 1024), unknown members and foreign namespaces rejected by the strict runtime.

## Observations not counted

- `Listings.Parse_List_Objects_Query`/`_V2_Query` and `Versions.Parse_List_Object_Versions_Query` reject `max-keys` above `Core.Page_Size'Last` (1000) with 400 `InvalidArgument` (`listings.adb:111-118`, `:223-230`, `versions.adb:134-141`, server mapping `s3_applications.adb:10764-10767`), where AWS and MinIO clamp the value to 1000 (from memory, unverified). A stock `aws s3api list-objects-v2 --max-keys 2000` therefore fails against the Flyology server; documented policy value, so not counted, but worth a decision.
- `Listings` object entries require `Size` (`listings.adb:862-868`) although the model makes it optional; every known server emits it. `Key` must be non-empty (model min 1). Low interop risk.
- `Versions` rejects unknown elements anywhere in `ListVersionsResult` (`versions.adb:578-580`, `:632-634`) while `Listings` and `Buckets` skip them (`Ignore_Depth`); a server extension element inside `<Version>` would fail ListObjectVersions but not ListObjects. Design inconsistency, no known server affected.
- `Versions.Validate` requires a non-empty `NextVersionIdMarker` whenever `NextKeyMarker` is present (`versions.adb:1031-1041`). If a page ends on a `CommonPrefixes` entry AWS may emit an empty `NextVersionIdMarker` (from memory, low confidence); left as an observation.
- `Replication.Valid_Integer` rejects a leading `+` (`replication.adb:504-505`) while `Lifecycle`, `Bucket_Controls`, `Intelligent_Tiering` and `Metadata_Configurations` accept it; harmless.
- `Lifecycle` and `Replication` do not enforce the model's `Tag.Key` minimum length 1, while `Analytics`, `Metrics` and `Intelligent_Tiering` do; harmless drift.
- `Buckets.Parse_Create_Configuration` rejects any `LocationConstraint` outside the pinned AWS region enumeration, including the literal `us-east-1` and self-hosted region names, and requires `Location` and `Bucket` together (`buckets.adb:444-471`); mirrors AWS's own rejection of `us-east-1`, so a policy choice, but clients configured with a non-AWS region name are refused at CreateBucket.
- `Buckets.Serialize_List_Buckets` emits `<Bucket></Bucket>` for an entry with an empty `Name` (server-side only).
- `Generated_Put_Bucket_ACL_XML` writes `Owner` before `AccessControlList` while the model orders `Grants` first; S3 request parsers are order-insensitive here (from memory).
- `ACL.Grantee_Type_Seen` is set unconditionally (`acl.adb:193`), so the `not Item.Grantee_Type_Seen` check at `:324` is dead; the attribute requirement is enforced at `:138-144` instead.
- Versioning `Default_Limits` (4 KiB, depth 2, 3 elements, 64 text bytes) and the 10,000-bucket cap in `Buckets` are documented policy values.
- The server-side emitters for the four configuration listings and ListDirectoryBuckets (`s3_applications.adb:9599-9608`, `:7237`) share the root names in S3-DOMAIN-A-4; a fix must change both sides together (SERVER area).
