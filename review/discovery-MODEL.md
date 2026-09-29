# Correctness discovery: MODEL (pinned botocore model, generator, descriptor, registry tools)

Scope:

- `tools/generate-s3-model.py` (all 962 lines): `ada_name` (304), `quote` (312),
  `generate` (474-928: SHA pin, operation/shape numbering, every emitted
  function including the `locations` map at 851 and `member_functions` at
  870-920), `main` with the `--check` path (931-961).
- `src/flyology-object_storage-s3-model.ads` (all 578 lines). Sampled regions
  of the 78,882-line generated body: `Operation_Name`/`Method`/`Request_URI`/
  `Response_Code` cases for SelectObjectContent and DeleteObject (226-227,
  464-465, 532-533, 702-703, 770-771), `Pattern` (10737, 11407, 11655, 11749),
  `Enumeration_Value` shape 666 StorageClass (27189-27223), and
  `Member_Location_Name` shape 299 Grantee (44897-44910). The whole body and
  spec were regenerated from `review/baseline/service-2.json` into the
  scratch directory with `tools/generate-s3-model.py` and are byte-identical
  to the committed files; `--check --output-dir src` exits 0.
- `review/baseline/service-2.json` (sha256 429763d6..., 116 operations, 718
  shapes) loaded with python3 and enumerated for every trait class in the
  brief: shape types, member locations, `locationName`/`xmlName`,
  `required`, `contextParam`, `staticContextParams`, `httpChecksum`,
  `authtype`, `unsignedPayload`, `endpoint.hostPrefix`/`hostLabel`,
  `payload`, `streaming`, `xmlNamespace`, `xmlAttribute`, `flattened`,
  `timestampFormat`, `min`/`max`, `pattern`, `sensitive`, `box`, `union`,
  `eventstream`, `idempotencyToken`, `deprecated`, `error`/`exception`,
  `responseCode`, greedy URI labels and query literals, list-member and
  map-key/value `locationName`, enum duplicates (exact and
  case-insensitive), and non-ASCII or control characters in every non-
  documentation string.
- `tools/s3_operation.py`: registry loading and invariants (61-301),
  `load_model`/`verify_registry_model_inventory`/`reachable_shapes`/
  `member_record`/`operation_audit` (494-676), `xml_member_specs`/
  `output_payload_shape`/`negative_xml_cases` head (707-830),
  `signed_socket_exchange`/`signed_socket_text` (1165-1347),
  `camel_to_ada`/`ledger_text`/`check_ledger` (1734-1772),
  `generated_outputs`/`validate_committed_*`/`check_generated_outputs`
  (1899-2037).
- `tools/s3_codegen.py`: `SUPPORTED_PATTERNS`/`XML_Node`/region
  materializers (1-127), `ada_identifier`/`ada_string`/`payload_shape`/
  `xml_nodes`/`codec_plan` (790-1042), `codec_descriptor_text` head
  (1042-1200), `Mutation_Serializer` table head and PutBucketAcl body
  (1455-1560), `mutation_serializer_text` (1893-1994),
  `mutation_http_contract_for_operation` (2178-2249),
  `_generated_mutation_low_level_body` (2736-2990),
  `generated_ada_outputs`/`check_generated_ada_outputs` (4380-4640).
- `tools/s3-operation.py` (all), `tools/test-s3-operation-registry.py`
  (head, structure, tail), `tools/verify-botocore-model.sh`,
  `tools/verify-coverage.sh`, `tools/test-coverage-verifier.sh`,
  `tools/verify-corpora-lock.sh` (head), `tools/ci/check-repository.sh`,
  `tools/ci/run-tests.sh`, `.github/workflows/ci.yml` (model fetch and gate
  wiring), `tests/generated/s3-operation-tests.sh` (head),
  `docs/architecture/s3-operation-automation.md` (all).
- `coverage/aws-s3-operations.tsv` (all 117 lines),
  `coverage/s3-operation-counts.json`, `coverage/s3-generation-canaries.json`
  (head), `coverage/s3-operation-inventory.json` (head),
  `coverage/s3-operations.toml` (head 120).
- Sampled preparation verifiers: `verify-list-objects-v2-preparation.py`
  (list), `verify-put-object-preparation.py` (header-heavy),
  `verify-put-bucket-lifecycle-configuration-preparation.py` (XML payload,
  regex over the generated body), `verify-head-bucket-preparation.py`
  (error shape), `verify-write-get-object-response-preparation.py`
  (hostPrefix/unsignedPayload).
- Descriptor consumers: `src/flyology-object_storage-client-low_level.adb`
  600-1338 (`Find_Model_Member`, `Fixed_Query_Count`, `Append_Fixed_Query`,
  `Model_Path_Template`, `Expand_Model_Path`, `Valid_Model_Scalar`,
  `Prepare_Model_Request_Internal`) and every literal member-ordinal lookup
  (2715-2737, 3190-3282, 5549-5632, 5913-6009, 7570-7683, 11661-11673,
  13912-14006, 14353-14356, 14715-14735); `s3-listings.adb` 519-551,
  633-649, 895-910; `s3-versions.adb` 346-380, 760-810, 1214-1254;
  `s3-multipart_uploads.adb` 500-712; `s3-multipart.adb` 1526-1543,
  1636-1660; `server-s3_applications.adb` 11356-11371, 11809-12016,
  13977-14350, 14663-14968; generated request serializer
  `s3-generated_put_bucket_logging_xml.adb` (all) compared with the model;
  `s3-strict_xml_codecs.adb` 72-185 and 313-315; `s3-sigv4.adb` 128-200.
- Existing coverage inspected: `tests/src/object_storage_test_cases.adb`
  `Check_Generated_S3_Model` (17945-18062), `Check_Put_Object_Required_
  Disposition` (18843-18968), `Check_Model_Request_Projection`
  (18970-19160); the CI integrity job (`check-repository.sh` with the
  fetched model, `verify-botocore-model.sh`, `generate --check`,
  `test-s3-operation-registry.py`).

Severity rubric: P0 = memory/aliasing unsafety, security (signature bypass,
path traversal, secret exposure, authorisation bypass), data loss/durability,
hang/deadlock, or interop-breaking protocol violation a stock client or
server rejects. P1 = wrong result or unexpected exception on valid input via
a reachable path, or a documented contract violated. P2 = edge-case
incorrectness, wrong diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| (none) | The sweep found no actionable P0, P1 or P2 finding in this area | - | - |

---

No numbered finding is recorded. Every candidate that survived the first
pass was refuted by a guard, by the pinned model's actual contents, by the
absence of a consumer, or by an existing gate; the refutations and the
residual latent items are recorded below so a later model bump or a new
consumer can be checked against them.

## Areas reviewed with no findings

- **SHA pin and counts** (`generate-s3-model.py:474-486`,
  `s3_operation.py:494-505`, `verify-botocore-model.sh`,
  `s3-operations.toml` header): the digest, 116 operations and 718 shapes
  are checked in the generator, the registry loader, the shell verifier and
  the registry TOML; a changed JSON cannot regenerate silently. CI fetches
  botocore commit 36c34f15 and passes it to `check-repository.sh`
  (`ci.yml:34-48`, `:79-119`), so `verify-botocore-model.sh` and
  `generate --check` run with the model on every CI run.
- **`--check` completeness** (`generate-s3-model.py:942-950`): compares the
  full regenerated text of both `.ads` and `.adb` against the committed
  files, not a subset. Regeneration into the scratch directory reproduces
  the committed files byte for byte.
- **Operation identifiers** (`ada_name`, 304-309): CamelCase split, non-
  alphanumerics collapsed, leading-digit guard, `_Operation` suffix (so no
  reserved word can result), case-insensitive collision check (491-495).
  All 116 literals in the spec (203-319) were compared with the JSON keys.
- **Shape numbering**: `sorted(shapes)` codepoint order, deterministic; the
  same order is used for every case function; `verify-botocore-model.sh`
  diffs `jq keys` (also codepoint order) against the ledger column.
- **Kind and location mappings** (`kind_literal` 780-790, `locations`
  851-857): the model uses exactly the nine shape types and five locations
  mapped (`statusCode` does not occur; a future occurrence raises KeyError
  in the generator rather than emitting a wrong descriptor).
- **Enumerations**: 75 enum shapes; no exact or case-insensitive duplicate
  values, no `"`, no non-ASCII or control characters anywhere in the model
  outside `documentation`; values are emitted verbatim as Ada string
  literals and compared exactly by every consumer (`Valid_Model_Scalar`
  931-941, `Valid_*_Enum` helpers, server `Valid_Enumeration`). Sampled
  StorageClass (shape 666) matches the JSON order and content.
- **Member names, location names, required flags**: `Member_Location_Name`
  defaults to the member name (`generate-s3-model.py:872-876`), which is
  the REST-XML rule; `Member_Required` is `name in shape["required"]`
  (877-881) with no parent-propagation; every `required` entry names an
  existing member (checked over all 188 `required` lists). Grantee `Type`
  (`xsi:type`, attribute) and the `x-amz-meta-` header-map prefix are
  emitted verbatim (sampled at 44897-44910 and consumed at
  `low_level.adb:1240-1250`).
- **HTTP bindings**: methods, `requestUri` (30 greedy `{Key+}` templates,
  99 query-literal templates, `?select&select-type=2`), `responseCode`
  (20 operations at 204, default 200) all match; every `{label}` in a
  `requestUri` corresponds to exactly one `uri` member whose
  `locationName` equals the label, and every `uri` member has a label
  (checked over all 116 operations). `Expand_Model_Path` (736-806)
  encodes `/` for ordinary labels and preserves it for greedy labels;
  `Append_Fixed_Query`/`Fixed_Query_Count` (656-712) split query literals
  on `&` and `=`.
- **Errors**: 20 operations carry `errors`; all 20 error shapes are
  `exception: true` structures with `error.httpStatusCode` in {400, 403,
  404, 409, 415}; `Error_Count`/`Error_Shape` are correct and tested by
  `Check_Generated_S3_Model`. No `src/` consumer reads them (see
  observations).
- **Checksum and auth traits**: `httpChecksum` present on 35 operations
  (33 `requestAlgorithmMember`, 33 `requestChecksumRequired`, 2
  `requestValidationModeMember`, 2 `responseAlgorithms`); `authtype`
  `v4-unsigned-body` and `unsignedPayload` only on WriteGetObjectResponse;
  emitted correctly and asserted by `Check_Generated_S3_Model`
  (18051-18060). `mutation_http_contract_for_operation` (2192-2246)
  refuses a required checksum without a modeled algorithm member and a
  `ContentMD5` member not bound to the `Content-MD5` header.
- **Numeric and string constraints**: 8 shapes carry `min`/`max` (all
  integers), 4 carry `pattern`; `Minimum`/`Maximum` are emitted as decimal
  images and consumed through `Long_Long_Integer'Value` (64-bit) for both
  `integer` and `long` kinds, so no 32-bit truncation exists in the
  descriptor path. `Pattern` literals round-trip exactly (10737, 11749) and
  the only patterns on request-serialized scalars are the two source-path
  patterns handled by `Matches_Pattern` (912-930); the ARN pattern occurs
  only on body members and on HeadBucket/CreateBucket response headers,
  which the client validates by length (`low_level.adb:4893`), not by
  `Valid_Model_Scalar`.
- **Timestamps**: 8 shapes carry an explicit `timestampFormat`; the
  descriptor emits `""` for the rest. No `src/` consumer reads
  `Timestamp_Format`; the client applies the REST-XML defaults itself
  (IMF-fixdate for `x-amz-abort-date` and `Expires`, `low_level.adb:3257`
  and `13159`; ISO-8601 for `x-amz-object-lock-retain-until-date`, `3086`,
  which the model marks `iso8601`; ISO-8601 for body timestamps in
  `strict_xml_codecs.adb:175-176`).
- **Header maps, header lists, header booleans**: the six `headers`
  members are all `Metadata` with prefix `x-amz-meta-`; the four header
  lists are enum lists consumed as comma-separated values
  (`Valid_Model_Scalar` 966-991); 26 header booleans are validated as
  `true`/`false`; there are no header blobs in the model.
- **Streaming and payload traits**: 63 `payload` shapes (3 streaming blobs
  on outputs, 4 on inputs, one `string` policy payload, the rest
  structures); `Member_Streaming` and `Payload_Member` are emitted
  correctly; `Prepare_Model_Request_Internal` treats body members as the
  raw payload and requires `Payload_Is_Set` for a required body member
  (1140-1160).
- **Flattened lists and XML names in the codegen** (`xml_nodes`
  810-990): flattened lists use the enclosing member's `locationName`
  as the repeated element name; non-flattened lists use the list member's
  `locationName`; attributes resolve the `xsi` prefix through the shape
  namespace; `blob`/`map` bodies and recursive shapes are refused. The
  generated PutBucketLogging serializer was compared element by element
  with `BucketLoggingStatus`/`LoggingEnabled`/`TargetGrants`/`Grantee`/
  `TargetObjectKeyFormat` in the model and matches names, nesting, the
  `Grant` item name, the `xsi:type` attribute and the S3 namespace.
- **Registry and ledger tools**: `load_registry` (72-262) rejects a
  duplicate `[[operation]]` name, a count other than 116, invalid states,
  provenance/mode mismatches and evidence-less covered cells;
  `verify_registry_model_inventory` (507-518) rejects any name set
  differing from the model and is invoked by `audit`, `scaffold` and by
  `generate` whenever a model is available; `verify-coverage.sh`
  independently checks the ledger header, `LC_ALL=C sort -c`, `uniq -d`,
  116 rows and state vocabulary; `verify-botocore-model.sh` diffs the
  ledger names against `jq '.operations | keys[]'`; `test-coverage-
  verifier.sh` is a negative oracle proving a ledger-only promotion is
  rejected. A duplicated, renamed or missing operation is caught at three
  independent layers.
- **Hard-coded member ordinals in consumers**: every literal ordinal
  passed to a descriptor-backed enum validator (HeadObjectOutput 5, 18,
  30, 36, 37, 38, 41, 43; GetObjectOutput 19, 30, 36, 37, 38, 41, 43;
  PutObjectOutput 22; UploadPartOutput 17; UploadPartCopyOutput 3;
  CopyObjectOutput 2-11; CreateSessionOutput 1-3;
  CreateMultipartUploadOutput 12, 14; ListObjectsOutput 4 and Object 4, 5,
  7; ListObjectVersionsOutput 6, 13 and ObjectVersion 2, 3, 5;
  ListMultipartUploadsOutput 10, 12 and MultipartUpload 4, 7, 8;
  ListPartsOutput 13, 15, 16; CreateMultipartUploadRequest 1, 15, 16, 24,
  26, 28; CopyObjectRequest 1, 23, 24, 25, 26, 27, 40, 42; PutObjectRequest
  1, 32, 33, 41, 43, 45) was cross-checked against the JSON member order
  and names the intended member.
- **Sampled preparation verifiers**: they are static source and registry
  oracles (region digests, ordered fragments, exact member inventories);
  the model assertions they make (HeadBucket HTTP/shape/header geometry,
  PutObject 46/22 member inventories and location names, lifecycle shape
  numbers 55/372/374/377/531/532/533/621/622/693 and enum domains,
  WriteGetObjectResponse `hostPrefix`/`RequestRoute`) agree with the
  pinned JSON.

## Observations not counted

- **O-1 (latent, unreachable with the pinned model)**
  `tools/s3_operation.py:1228-1231`: the `querystring` branch of
  `signed_socket_exchange` substitutes `encoded` into a `{marker}` found in
  the request URI, but `encoded` is only bound in the `uri` branch
  (1219, 1222). No S3 `requestUri` contains a marker named after a
  `querystring` member (checked over all 116 operations), so the branch is
  dead today; a future model with such a marker would raise
  `UnboundLocalError` or reuse the previous URI value. Fix is a one-line
  `encoded = urllib.parse.quote(value, safe="-_.~")` before the replace.
- **O-2 (diagnostic precision)** `tools/s3-operation.py:237-247`:
  `generate --check` without `--model` or `FLYOLOGY_S3_SERVICE_MODEL`
  skips `check_generated_ada_outputs`, the GetBucketWebsite canary and the
  negative-XML/signed-socket regeneration comparisons (only their structure
  is validated) yet prints "S3 operation generated outputs: current". CI
  always supplies the model, and the full `tests/scripts/test.sh` gate
  fails closed through the model verifiers that assert the variable, so a
  stale generated Ada file cannot reach `main`; a developer running
  `tools/verify-coverage.sh` alone without the variable gets a narrower
  check than the message suggests.
- **O-3 (fragility, not a defect today)**: the literal member ordinals
  listed above are bound to the JSON insertion order of `members`. The SHA
  pin and full-text `--check` make silent drift impossible for this model,
  and `Check_Put_Object_Required_Disposition` plus the sampled verifiers
  pin PutObject, GetObject, ListParts, ListObjectVersions,
  ListMultipartUploads, CreateSession, CreateMultipartUpload and UploadPart
  inventories by name; HeadObjectOutput, CopyObjectOutput,
  ListObjectsOutput/Object and UploadPartCopyOutput ordinals have no
  by-name drift guard, so a model bump that inserts a member before them
  would validate against the wrong shape without a compile error.
  `low_level.adb:11669-11673` shows the name-based alternative
  (`Find_Model_Member`) already used for ListObjectAnnotations.
- **O-4 (descriptor omissions, no consumer affected)**: the descriptor
  does not expose `endpoint.hostPrefix`/`hostLabel` (WriteGetObjectResponse
  only; its client lane is `partial` and the server side reads
  `x-amz-request-route` directly), `error.httpStatusCode` (no `src/`
  consumer reads `Error_Shape`), list-member and map key/value
  `locationName` (the XML codegen reads the JSON directly; the descriptor's
  `List_Member_Shape` is used only to reach item enumerations),
  member-level `xmlName`, `idempotencyToken` (RenameObject `ClientToken`),
  `deprecated`, `box`, `union`, `eventstream`/`event`/`eventpayload`,
  `staticContextParams`, or per-member `timestampFormat` (none exist in
  the model). None of these can propagate an error into a consumer at this
  commit.
- **O-5 (comment precision)** `low_level.adb:927-929`: the fail-closed
  comment says the pinned model has only the source-path pattern on a
  serialized non-body scalar. That is true for request-serialized members
  (CopySource, RenameSource), but `S3RegionalOrS3ExpressBucketArnString`
  (ARN pattern, min 1, max 128) is also a `header` member of
  `HeadBucketOutput` and `CreateBucketOutput`. Because `Valid_Model_Scalar`
  is applied to response headers only for CopyObject (14719-14735) and
  CreateSession (2718-2722), HeadBucket is unaffected; applying it to
  HeadBucket output in future would reject every `x-amz-bucket-arn`.
- **O-6 (XML item-name fallback, unreachable)** `s3_codegen.py:967-969`:
  a non-flattened list whose member lacks `locationName` gets the item
  shape name as element name; REST-XML uses `member`. The only two such
  lists (`ObjectAttributesList`, `OptionalObjectAttributesList`) are
  header lists and never appear in an XML body.
- **O-7 (consumer leniency, CLIENT-LOW scope)** `low_level.adb:955`:
  `Long_Long_Integer'Value` accepts Ada literal syntax (`1_0`, `16#A#`,
  surrounding blanks, 64-bit magnitudes for `integer` shapes) and the
  accepted text is sent verbatim in a query or header, so a caller of the
  public `Prepare_Model_Request` can produce a request a stock server
  rejects with 400. Typed wrappers format integers themselves; the model
  constraint is honoured numerically. Also, Smithy `min`/`max` on strings
  count code points while `Within_Length_Bounds` (900-910) counts bytes;
  only server-issued ASCII tokens reach that check today.
- **O-8 (policy, by design)**: `Request_Checksum_Required`,
  `Request_Validation_Mode_Member` and `Response_Checksum_Algorithms` are
  emitted but no `src/` consumer reads them; handwritten and generated
  mutations decide Content-MD5/x-amz-checksum emission per operation
  (`mutation_http_contract_for_operation`, `Prepare_Bucket_Control_
  Mutation`). The CHECKSUM area owns whether every `requestChecksumRequired`
  operation actually sends one.
- **O-9 (test-harness ordering)** `s3_operation.py:1273-1279`: the
  expected request target sorts encoded `name=value` strings lexically
  rather than by (name, value) as SigV4 does; the two orders differ only
  when one name is a prefix of another followed by a byte below `=`
  (for example `prefix-x` versus `prefix`). No reviewed fixture contains
  such a pair, and a mismatch would fail the signed-socket test rather than
  ship, since the client signs with `SigV4.Canonical_Query`
  (`sigv4.adb:128-154`).
- **Generated serializer element names** (`s3_codegen.py:1464-1893`) are
  hand-typed Python string literals bound to a digest of the model's
  reachable shape closure (`closure_sha256`, 1915); a typo in an element
  name would not change the digest and is caught only by the reviewed
  signed-socket bodies and server corpora. The PutBucketAcl and
  PutBucketLogging serializers were checked against the model and are
  correct.
