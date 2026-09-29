Title: Four list decoders require the botocore output shape name as the XML root, not the element AWS sends
Labels: bug
Refs: none

## Summary

The ListBucketInventoryConfigurations, ListBucketMetricsConfigurations, ListBucketAnalyticsConfigurations and ListDirectoryBuckets decoders compare the response root element against the botocore output shape name and raise when it differs. The AWS S3 API Reference documents a different root for each of those four operations, and AWS is the only provider that implements them, so every 200 response fails to decode. The pinned model carries no root name for any list output, so the comment that says the names come from the model is not supported by the model. The in-house server emits the same four names on the other side, which is why every in-repository round-trip passes.

## Problem

Commit `5fe6e3e`.

Each decoder pins the shape name as the root, under a comment naming the model as the authority (`src/flyology-object_storage-s3-inventory.adb:608-614`):

```ada
   --  Both element names are fixed by the pinned Botocore operation/output
   --  model. Changing either changes accepted S3 wire documents.
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                   =>
        "ListBucketInventoryConfigurationsOutput",
      Item_Container_Name         => "",
      Item_Name                   => "InventoryConfiguration",
```

`src/flyology-object_storage-s3-metrics.adb:470-472`:

```ada
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                  =>
        "ListBucketMetricsConfigurationsOutput",
```

`src/flyology-object_storage-s3-analytics.adb:574-576`:

```ada
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                   =>
        "ListBucketAnalyticsConfigurationsOutput",
```

and the generated ListDirectoryBuckets decoder (`src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:9-13`):

```ada
   function Element_Name (Element : Element_Id) return String is
   begin
      case Element is
         when Root =>
            return "ListDirectoryBucketsOutput";
```

The comparison is exact, on open and on close (`src/flyology-object_storage-s3-paginated_rest_xml_reads.adb:133-136`):

```ada
      elsif Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= Root_Name then
            raise Malformed_Page with "invalid configuration-list root";
         end if;
```

and `:283-286`:

```ada
      elsif Item.Depth = 1 then
         if Local_Name /= Root_Name then
            raise Malformed_Page with
              "mismatched configuration-list root close";
```

The generated decoder's runtime does the same (`src/flyology-object_storage-s3-strict_xml_codecs.adb:312-315`):

```ada
      if Item.Frames.Is_Empty then
         Element := Root_Element;
         if Local_Name /= Element_Name (Root_Element) then
            raise Malformed_Document with "invalid XML root";
```

The names come from one generator rule, not from the model (`tools/s3_codegen.py:815-816`):

```python
    root_shape = payload_shape(model, operation, entry)
    root_name = shapes[root_shape].get("locationName", root_shape)
```

The same rule is applied to request payloads at `tools/s3_codegen.py:1932`, where it is right, because every request payload member carries a `locationName`. Output shapes carry nothing, so the rule silently falls back to the shape name. Printed from the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```
ListBucketInventoryConfigurationsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListBucketMetricsConfigurationsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListBucketAnalyticsConfigurationsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListBucketIntelligentTieringConfigurationsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListDirectoryBucketsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListBucketsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListObjectVersionsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
ListObjectsOutput locationName= None resultWrapper= None xmlNamespace= None payload= None
```

The model is silent for every one of them, including the three whose wire roots the crate already hard-codes correctly, so the model cannot be the authority the four comments claim. Those three are `src/flyology-object_storage-s3-buckets.adb:913-916`:

```ada
      if Item.Depth = 1 then
         if Local_Name /= "ListAllMyBucketsResult" then
            raise Malformed_Bucket_Listing with
              "unexpected ListBuckets root";
```

`src/flyology-object_storage-s3-listings.adb:689-692`:

```ada
      if Item.Depth = 1 then
         if Local_Name /= "ListBucketResult" then
            raise Malformed_Listing with
              "S3 listing root is not ListBucketResult";
```

and `src/flyology-object_storage-s3-versions.adb:527-530`:

```ada
      elsif Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "ListVersionsResult" then
            raise Malformed_Version_Listing with
              "invalid ListObjectVersions response root";
```

The two metadata reads do the same at `src/flyology-object_storage-s3-metadata_configurations.adb:209-213` and `src/flyology-object_storage-s3-metadata_tables.adb:293-297`.

The AWS S3 API Reference, read from each operation's Response Syntax block and from the root-level-tag entry in its Response Elements section, shows a different root for each of the four:

- `API_ListBucketInventoryConfigurations.html` shows `<ListInventoryConfigurationsResult>`.
- `API_ListBucketMetricsConfigurations.html` shows `<ListMetricsConfigurationsResult>`.
- `API_ListBucketAnalyticsConfigurations.html` shows `<ListBucketAnalyticsConfigurationResult>`, with `Configuration` singular.
- `API_ListDirectoryBuckets.html` shows `<ListAllMyDirectoryBucketsResult>`.

`API_ListBucketIntelligentTieringConfigurations.html` shows `<ListBucketIntelligentTieringConfigurationsOutput>`, that is, the shape name really is the AWS root for that one operation, which is presumably why the pattern looked safe. That fifth decoder (`src/flyology-object_storage-s3-intelligent_tiering.adb:530-532`) is correct and is used below as the control.

Four public entry points reach the affected decoders: `src/flyology-object_storage-client-low_level.adb:9277` (`Metrics.Parse_List`), `:9319` (`Analytics.Parse_List`), `:9577` (`Inventory.Parse_List`) and `:16793` (`Generated_List_Directory_Buckets_XML.Parse`).

No pinned third-party server can settle it. The pinned MinIO image, `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` from `tests/scripts/test-minio.sh:5`, whose `--version` prints `minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`, answered signed `GET /bucket?inventory`, `?metrics`, `?analytics` and `?intelligent-tiering` with 501 and an `<Error>` root in all four cases. AWS is the only provider that implements them.

No in-repository test can catch it either, because the server emits the same four names. `src/flyology-object_storage-server-s3_applications.adb:9599-9608`:

```ada
                  function Root_Name return String is
                    (case Family is
                        when Analytics_Family =>
                          "ListBucketAnalyticsConfigurationsOutput",
                        when Metrics_Family =>
                          "ListBucketMetricsConfigurationsOutput",
                        when Intelligent_Tiering_Family =>
                          "ListBucketIntelligentTieringConfigurationsOutput",
                        when Inventory_Family =>
                          "ListBucketInventoryConfigurationsOutput");
```

and `:7235-7237`:

```ada
                        Apps.Respond
                          (X, 200, "application/xml",
                           "<ListDirectoryBucketsOutput/>");
```

One of the four is documented as the server's contract, `docs/qualification/list-directory-buckets.md:12-14`:

```
existing List_Buckets backend operation only to preserve cancellation,
deadline, and backend-availability behavior, discards the general-purpose
page, and returns an empty `<ListDirectoryBucketsOutput/>` document.
```

so client, generator, server and that sentence disagree with AWS together and agree with each other, and every round-trip in the repository passes.

Separately, the generated decoder re-raises with no message, so its caller sees a source location instead of a reason (`src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:272-274`):

```ada
   exception
      when Typed_Decoder.Malformed_Document =>
         raise Malformed_Document;
```

## What happens now

Spike: the program below feeds each of `Inventory.Parse_List`, `Metrics.Parse_List`, `Analytics.Parse_List`, `Intelligent_Tiering.Parse_List` and `Generated_List_Directory_Buckets_XML.Parse` two documents that differ only in the root element name: the shape name the crate pins today, recorded but not asserted, and the root the AWS API Reference documents, asserted. Intelligent-Tiering, where the two coincide, is the passing control.

```ada
   function Empty_List (Root : String) return String is
     ("<" & Root & " xmlns=""" & NS & """>" &
      "<IsTruncated>false</IsTruncated>" &
      "</" & Root & ">");
...
   Try_Inventory ("ListInventoryConfigurationsResult", True);
   Try_Metrics ("ListMetricsConfigurationsResult", True);
   Try_Analytics ("ListBucketAnalyticsConfigurationResult", True);
   Try_Directory_Buckets ("ListAllMyDirectoryBucketsResult", True);
```

Output, exit status 1:

```
  -- --- controls: the shape-name roots the crate pins today ---
  -- Inventory.Parse_List <ListBucketInventoryConfigurationsOutput>: accepted, has_is_truncated=TRUE
  -- Metrics.Parse_List <ListBucketMetricsConfigurationsOutput>: accepted, has_is_truncated=TRUE
  -- Analytics.Parse_List <ListBucketAnalyticsConfigurationsOutput>: accepted, has_is_truncated=TRUE
  -- ListDirectoryBuckets <ListDirectoryBucketsOutput>: accepted, buckets=1
  -- --- control: Intelligent-Tiering, where AWS really does document the shape name as the root ---
  -- Intelligent_Tiering.Parse_List <ListBucketIntelligentTieringConfigurationsOutput>: accepted, has_is_truncated=TRUE
  ok: Intelligent_Tiering.Parse_List accepts <ListBucketIntelligentTieringConfigurationsOutput>
  -- --- the finding: the roots the AWS API Reference documents ---
  -- Inventory.Parse_List <ListInventoryConfigurationsResult>: REJECTED, malformed inventory-list XML
  FAILED: Inventory.Parse_List accepts <ListInventoryConfigurationsResult>
  -- Metrics.Parse_List <ListMetricsConfigurationsResult>: REJECTED, malformed metrics-list XML
  FAILED: Metrics.Parse_List accepts <ListMetricsConfigurationsResult>
  -- Analytics.Parse_List <ListBucketAnalyticsConfigurationResult>: REJECTED, malformed analytics-list XML
  FAILED: Analytics.Parse_List accepts <ListBucketAnalyticsConfigurationResult>
  -- ListDirectoryBuckets <ListAllMyDirectoryBucketsResult>: REJECTED, flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:274
  FAILED: ListDirectoryBuckets decoder accepts <ListAllMyDirectoryBucketsResult>
BUG REPRODUCED: 4 failed expectation(s)
```

Each pair of documents differs by the root name and nothing else, and the Intelligent-Tiering leg passes with the same document shape, so the body content and the harness are not what fires. The last line prints a source location rather than a diagnostic because of the message-less re-raise quoted above.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image, which answers 501 for all four operations. Shapes checked against the pinned botocore S3 model.

## What should happen

Each of the four decoders must accept the root element that the AWS S3 API Reference documents for its operation: `<ListInventoryConfigurationsResult>`, `<ListMetricsConfigurationsResult>`, `<ListBucketAnalyticsConfigurationResult>` and `<ListAllMyDirectoryBucketsResult>`. The pinned model records no root name for any list output, so it cannot be the source for these values, and the crate already hard-codes the true wire root wherever it differs from the shape name for the older listings.

## Suggested treatment

One change across the generator, the three hand-written decoders and the server emitters, since the two sides must agree:

- Give `tools/s3_codegen.py` an explicit response-root table keyed by operation, consulted before the `locationName`-or-shape-name fallback at `:815-816`, and regenerate `src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb`.
- Set the three `Root_Name` actuals to the documented roots at `src/flyology-object_storage-s3-inventory.adb:611-612`, `src/flyology-object_storage-s3-metrics.adb:471-472` and `src/flyology-object_storage-s3-analytics.adb:575-576`, and correct the comment above each, which currently names the model as the authority.
- Change the server emitters to match, at `src/flyology-object_storage-server-s3_applications.adb:9599-9608` and `:7235-7237`, and reword `docs/qualification/list-directory-buckets.md:12-14`, which documents the wrong root as the server's contract.
- Leave `src/flyology-object_storage-s3-intelligent_tiering.adb:530-532` alone.

This needs a maintainer decision on where the four names live and how their authority is recorded. They are externally mandated protocol values with no source in the pinned model, which the "Decision authority" section of `AGENTS.md` requires be recorded at the declaration:

- An operation-keyed response-root table in `tools/s3_codegen.py` with the AWS API Reference cited beside it, so the generated and hand-written decoders draw on one recorded source.
- Four hand-written string literals in the four bodies, each with its own citation, matching how `ListAllMyBucketsResult`, `ListBucketResult` and `ListVersionsResult` are handled today.

While the generated decoder is being regenerated, its message-less re-raise at `src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:272-274` should carry the inner diagnostic, so a root mismatch reports a reason rather than a source location.

The regression tests belong in `tests/src/s3_http_socket_corpus.adb`, beside the existing socket cases for the four operations: serve each documented root and require the page to decode, and keep one case per operation asserting that a foreign root is still refused. The spike is the test. No existing test asserts the current roots as client behaviour, but the four qualification suites drive the in-house server and will start failing the moment the client changes without the server, which is why both sides belong in one change.

## Severity

Every 200 response from AWS for ListBucketInventoryConfigurations, ListBucketMetricsConfigurations, ListBucketAnalyticsConfigurations and ListDirectoryBuckets fails to decode, so the four operations do not work against the only provider that implements them. The caller sees `Malformed_Inventory`, `Malformed_Metrics`, `Malformed_Analytics` or a bare `Malformed_Document`, and there is no workaround at the call site. It is a comparison of two strings, so it is total and involves no timing or server state. The matrix rows for the three configuration listings, `docs/compatibility/s3.md:37`, `:38` and `:40`, each end with "external interoperability are not claimed", so no documented promise is broken on the client side, and a caller that only drives the in-house server never sees it. ListDirectoryBuckets has no matrix row at all, and `docs/qualification/list-directory-buckets.md:12-14` positively documents the non-AWS root as the server's contract. Deterministic; not reproduced against a live AWS endpoint, since no pinned third-party server implements the operations.
