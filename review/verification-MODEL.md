# Adversarial verification: MODEL (pinned botocore model, generator, descriptor, registry tools)

Scope verified by reading: `review/baseline/service-2.json` (all 116 operations,
718 shapes, 1699 structure members, 279 enumeration values, parsed with a
duplicate-key-aware loader), `src/flyology-object_storage-s3-model.ads` (all 578
lines: header constants, the four enumeration types, and every one of the 41
visible accessors with its `Pre`), `src/flyology-object_storage-s3-model.adb`
(every one of the 33 910 `return` statements, via a parser that raises on any
unrecognised line), `tools/generate-s3-model.py:290-330` (`ada_name`, `quote`,
`bool_image`), `:391-470` (`line_case_function`, `nested_case_function`,
`operation_nested_function`), `:474-928` (the whole `generate` body, including
the `kind_literal` and `locations` maps and the `member_functions` table),
`tools/s3_operation.py:1205-1240` (`signed_socket_exchange` URI/query branches),
`tools/s3_codegen.py:955-985` (`add_list` item-name fallback),
`tools/verify-botocore-model.sh` (all 26 lines),
`coverage/aws-s3-operations.tsv` (all 117 lines),
`coverage/s3-operation-counts.json`, `coverage/s3-operations.toml:1-8`,
`src/flyology-object_storage-client-low_level.adb:895-1160`
(`Valid_Model_Scalar`, `Prepare_Model_Request_Internal`), `:2704-2745`,
`:3192-3290`, `:5550-5640`, `:5915-6010`, `:7570-7690`, `:11660-11690`,
`:13915-14010`, `:14340-14375`, `:14705-14740`,
`src/flyology-object_storage-s3-listings.adb:515-560`, `:620-660`, `:890-935`,
`src/flyology-object_storage-s3-versions.adb:340-385`, `:755-812`, `:1210-1258`,
`src/flyology-object_storage-s3-multipart.adb:1520-1665`,
`src/flyology-object_storage-s3-multipart_uploads.adb:488-530`, `:690-715`,
`src/flyology-object_storage-server-s3_applications.adb:11350-11375`,
`:13970-14000`, `:14300-14345`, `:14655-14690`, `:14905-14925`, and the five
committed generated XML serializers `src/flyology-object_storage-s3-generated_*.adb`.
Harness programs added: `tests/repros/python/model_differential.py` (finished
from the interrupted draft; standard library only, no build). Nothing tracked
was modified.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| (none) | The differential found no mismatch; the discovery's "no actionable finding" is UPHELD | - | `tests/repros/python/model_differential.py` (exit 0 = no mismatch) |

The discovery recorded no numbered finding. This verification tried to refute
that with an exhaustive, generator-independent differential rather than with
spot checks, and could not. The differential is the evidence; its exact
command, counts and output tail are below, together with the mutation control
that proves the checker is not vacuous, and the independent re-derivation of
each observation the discovery left latent.

---

## Differential check

**Command** (from the worktree root; python3 standard library only, no Alire
build, nothing tracked touched):

```
python3 tests/repros/python/model_differential.py
```

Exit status **0** (0 = no mismatch, 1 = at least one mismatch, 2 = missing
input). Runs in ~1 s and is byte-for-byte deterministic across repeated runs.

The program deliberately does **not** call `tools/generate-s3-model.py`.
Regenerating with the generator and diffing (what `generate --check` and the
discovery did) only proves the generator is a function of its input; it cannot
detect a rule the generator itself gets wrong. This program instead parses the
committed Ada text directly, re-derives every expected value from the pinned
JSON with the REST-XML rules written out in the source, and compares the two.

### What it reads and how

- `review/baseline/service-2.json` with an `object_pairs_hook` that reports
  duplicate object keys (none exist), preserving member insertion order — the
  order the descriptor's ordinals and every consumer literal depend on.
- `src/flyology-object_storage-s3-model.adb` with a line-exact parser for the
  two emitted shapes (`when KEY => return VALUE;` and the nested
  `case Member/Index is`). Any line it does not recognise raises, so a layout
  change cannot be silently mis-read as agreement. Ada string literals are
  decoded properly, including `""` escapes.
- `src/flyology-object_storage-s3-model.ads` for `Model_SHA256`,
  `Operation_Count`, `Shape_Count`, the four enumeration types, and the
  declaration text of every visible function.

### Coverage accounting (the exhaustiveness claim, printed by the program)

```
descriptor case functions parsed    : 41 (29 flat, 12 indexed)
descriptor case arms compared       : 30303 value arms + 3607 'when others' defaults = 33910 of the 33910 return statements in the body
```

41 is the complete set of accessors declared in the `.ads`; 30 303 + 3 607 is
every `return` statement in the 78 882-line body. The program asserts that
identity and reports a mismatch if the parser ever reads fewer arms than the
file contains, so "no mismatch" cannot mean "did not look".

### Counts checked

```
operations checked        : 116
shapes checked            : 718 (718 reachable from operation input/output/errors)
structure members checked : 1699
enumeration values checked: 279 in 75 shapes
error shape links checked : 38 (20 distinct error shapes)
operations with httpChecksum        : 35
operations using responseCode 200 default: 96
requestUri with a query literal     : 99
requestUri with a greedy label      : 30
shapes with min / max / pattern     : 8 / 7 / 4
shapes with timestampFormat         : 8
shapes with xmlNamespace / flattened: 1 / 35
payload shapes / streaming members / header maps: 63 / 7 / 6
strings screened for non-ASCII      : 7615 (0 unsafe)
```

`sha256 = 429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`
matches the `.ads` constant, `tools/generate-s3-model.py:15-19` (`EXPECTED_SHA256`, `EXPECTED_OPERATIONS`, `EXPECTED_SHAPES`),
`tools/verify-botocore-model.sh:12` and `coverage/s3-operations.toml:5`.

### Attributes compared, per element

- Per operation: `Operation_Name`, `Method`, `Request_URI`, `Response_Code`
  (with the 200 default re-derived, not copied), `Input_Shape`, `Output_Shape`,
  `Error_Count`, the whole `Error_Shape` list, `Unsigned_Payload`,
  `Authentication_Type`, `Request_Checksum_Required`,
  `Request_Checksum_Algorithm_Member`, `Request_Validation_Mode_Member`,
  `Response_Checksum_Algorithms` (including the check that no algorithm name
  contains the `;` used as the join separator, which would make the image
  ambiguous). Independently of the descriptor it also checks that every
  `{label}` in a `requestUri` corresponds to exactly one `uri` member whose
  `locationName` is that label, that no label repeats, and that every
  `httpChecksum` member name is an actual member of the input shape.
- Per shape: `Shape_Name`, `Kind`, `Location_Name`, `Payload_Member`,
  `Timestamp_Format`, `Pattern`, `Minimum`, `Maximum`, `Is_Flattened`,
  `Is_Sensitive`, `XML_Namespace`, `List_Member_Shape`, `Map_Key_Shape`,
  `Map_Value_Shape`, `Enumeration_Count`, the whole `Enumeration_Value` list,
  `Member_Count`; plus the model-side invariants that a `payload` names a
  member with no `location`, that `required` names existing members, that a
  list has a `member` and a map has `key`/`value`, that no enum list contains a
  duplicate, and that members appear only on structures.
- Per member: `Member_Name`, `Member_Shape`, `Location` (with the `body`
  default re-derived), `Member_Location_Name` (with the REST-XML "member name
  when absent" default re-derived), `Member_Required`, `Member_Flattened`,
  `Member_Streaming`, `Member_XML_Attribute`, `Member_XML_Namespace`,
  `Member_Context_Parameter`.
- Structural: every flat function must have exactly one arm per operation or
  per shape 1..718 with no extras; every indexed function must have no arm
  outside its domain; the emitted function set must equal the declared set;
  every indexed accessor must carry a `Pre` bounding the index (so the
  `when others` defaults, listed in the program's notes — notably
  `Member_Shape => Shape_Index'First`, which would otherwise silently answer
  shape #1 — are unreachable under the contract); every emitted string must be
  printable ASCII; any JSON attribute the checker does not classify is
  reported (the only one is `synthetic`, new to this run, on `AccessDenied`).

### Mutation control (proof the checker is not vacuous)

Twenty single-token mutations were applied to a copy of `src/` under the
scratch directory (`/private/tmp/claude-501/.../scratchpad/mut`, never the
worktree) and the program was rerun against each. All twenty were caught with
exit 1 and a first-line diagnosis naming the right element:

```
Request_URI of DeleteBucket             MISMATCH operation DeleteBucket :: Request_URI: json='/{Bucket}' ada='/{Bucket}/'
Response_Code of DeleteBucket           MISMATCH operation DeleteBucket :: Response_Code: json=204 ada=200
HTTP method of DeleteBucket             MISMATCH operation DeleteBucket :: Method: json='Delete_Method' ada='Post_Method'
one member locationName                 MISMATCH shape #134 CreateMultipartUploadOutput member 6 ServerSideEncryption :: Member_Location_Name
one enum value                          MISMATCH shape #490 ObjectStorageClass :: Enumeration_Value list
spec SHA pin                            MISMATCH <spec> :: Model_SHA256
spec Shape_Count                        MISMATCH <spec> :: Shape_Count: json=718 ada=719
Minimum '0' -> '1'                      MISMATCH shape #181 DirectoryBucketToken :: Minimum: json='0' ada='1'
Is_Flattened True -> False              MISMATCH shape #18 AllowedHeaders :: Is_Flattened: json=True ada=False
Timestamp_Format iso8601 -> other       MISMATCH shape #140 Date :: Timestamp_Format
Request_Checksum_Required True->False   MISMATCH operation CreateBucketMetadataConfiguration :: Request_Checksum_Required
delete one Shape_Name case arm          MISMATCH shape #500 OwnerOverride :: Shape_Name: ada='<no case arm>'
swap two adjacent Member_Name values    MISMATCH shape #5 AbortMultipartUploadRequest member 1 Bucket :: Member_Name
Member_Required True -> False           MISMATCH shape #5 AbortMultipartUploadRequest member 1 Bucket :: Member_Required
Member_Shape 48 -> 49                   MISMATCH shape #1 AbacStatus member 1 Status :: Member_Shape: json=48 ada=49
Error_Shape 453 -> 454                  MISMATCH operation AbortMultipartUpload :: Error_Shape list
Location Header -> Query                MISMATCH shape #4 AbortMultipartUploadOutput member 1 RequestCharged :: Location
consumer ordinal HeadObject 36 -> 35    MISMATCH consumer ...low_level.adb:5620: Valid_Head_Object_Enum(35) ...
consumer ordinal HeadObject 36 -> 44    MISMATCH consumer ...low_level.adb:5620: ordinal 44 out of range
consumer ordinal CopyObject 11 -> 12    MISMATCH consumer ...low_level.adb:14734: Valid ordinal 12 out of range
```

### Consumer ordinal cross-check

The program resolves each consumer's Ada shape expression against the JSON
(`Model.Input_Shape`/`Output_Shape` of a named operation, `Model.Member_Shape`
with a literal ordinal, `Model.List_Member_Shape`, `Model.Map_*_Shape`,
`Model.Shape_Index` conversions, and local helper functions that take a
`Positive` member index — including the three same-named nested
`Valid_Enumeration` helpers in `server-s3_applications.adb`, which are
disambiguated by nearest preceding declaration). It then prints one table row
per literal ordinal with the member the ordinal actually names, that member's
wire name, whether the member's shape (or list item shape) carries enumeration
values, and the identifier or header name the call site uses.

```
(74 literal ordinals resolved in 6 consumer file(s); 57 feed an enumeration lookup; 0 without a call-site name to compare; 'E' marks a member whose shape carries enumeration values)
```

All 74 rows are `OK`: the call-site name agrees with the member or wire name in
every case, and every one of the 57 ordinals that reaches an
`Enumeration_Count`/`Enumeration_Value` lookup lands on a member whose shape
does carry enumeration values (an off-by-one onto a non-enum member would make
the validator reject every non-empty value, so this invariant is load-bearing,
not cosmetic). Representative rows, one per consumer:

```
file                                          line via                         shape                            # member                      wire name                         E call site                  verdict
flyology-object_storage-client-low_level.adb  2735 Valid_Optional              CreateSessionOutput              1 ServerSideEncryption        x-amz-server-side-encryption      E Server_Side_Encryption     OK
flyology-object_storage-client-low_level.adb  5620 Valid_Head_Object_Enum      HeadObjectOutput                36 StorageClass                x-amz-storage-class               E Storage_Class              OK
flyology-object_storage-client-low_level.adb 14356 <direct>                    UploadPartCopyOutput             3 ServerSideEncryption        x-amz-server-side-encryption      E Encryption                 OK
flyology-object_storage-client-low_level.adb 14734 Valid                       CopyObjectOutput                11 RequestCharged              x-amz-request-charged             E Request_Charged            OK
flyology-object_storage-s3-listings.adb        525 <direct>                    ListObjectsOutput                4 Contents                    Contents                          - Contents                   OK
flyology-object_storage-s3-multipart.adb      1654 Valid_List_Parts_Enumeration ListPartsOutput                 16 ChecksumType                ChecksumType                      E Checksum_Type              OK
flyology-object_storage-s3-multipart_uploads.adb   704 Upload_Member_Shape     MultipartUpload                  8 ChecksumType                ChecksumType                      E Checksum_Type              OK
flyology-object_storage-s3-versions.adb        800 Version_Member_Shape        ObjectVersion                    5 StorageClass                StorageClass                      E StorageClass               OK
flyology-object_storage-server-s3_applications.adb 14348 Valid_Enumeration     CopyObjectRequest               25 AnnotationDirective         x-amz-object-annotation-directive E x-amz-object-annotation-directive OK
```

The resolved set is a superset of the discovery's list. Two ordinals the
discovery did not enumerate are also correct: `PutObjectOutput` 14
(`ServerSideEncryption`, `low_level.adb:7661`) and `UploadPartOutput` 1
(`ServerSideEncryption`, `low_level.adb:13982`). The discovery's
`CreateMultipartUploadOutput` list (12, 14) is likewise incomplete — 6 and 13
are also passed, and both are correct.

### Omitted attributes (present in the JSON, absent from the descriptor)

Reported as a summary, not as mismatches, with the consumer each would need.
Complete list, with counts:

| JSON attribute | Instances | A consumer would need it for |
|---|---|---|
| `operation.endpoint` (`hostPrefix`) | 1 (WriteGetObjectResponse `{RequestRoute}.`) | endpoint host-prefix expansion; the client lane is `partial` and the server reads `x-amz-request-route` directly |
| `member.hostLabel` | 1 (`WriteGetObjectResponseRequest.RequestRoute`) | the same host-prefix expansion |
| `shape.error.httpStatusCode` | 38 links / 20 shapes | mapping a modeled error shape to an HTTP status without a hand-written table; no `src/` consumer reads `Error_Shape` |
| `shape.error` / `shape.exception` | 20 / 20 | a generic modeled-error dispatcher |
| `shape.member.locationName` (list item names) | 9 (`AnnotationEntry`, `Bucket`, `EncryptionType`, `Grant` ×2, `Field`, `RoutingRule`, `Tag`, `MetadataEntry`) | a descriptor-driven XML codec; `tools/s3_codegen.py` reads the pinned JSON directly instead |
| `shape.xmlNamespace.prefix` | 1 (`Grantee` → `xsi`) | a serializer emitting a prefixed attribute name from the descriptor; the generated serializers resolve `xsi` from the JSON at generation time |
| `operation.input.locationName` / `.xmlNamespace` | 1 / 1 (SelectObjectContent) | a descriptor-driven request-body root element name and namespace |
| `operation.staticContextParams` | 77 | endpoint-rule evaluation |
| `operation.deprecated` / `member.deprecated` | 4 / 5 | a deprecation diagnostic |
| `shape.box` / `member.box` | 43 / 1 | a boxed-primitive-aware codec |
| `shape.union` | 1 (`ObjectEncryption`) | a union-aware codec |
| `shape.event` / `eventstream` / `member.eventpayload` | 5 / 1 / 3 | an event-stream codec (SelectObjectContent) |
| `member.idempotencyToken` | 1 (`RenameObjectRequest.ClientToken`) | a client that auto-fills an idempotency token |
| `shape.synthetic` | 1 (`AccessDenied`) | nothing; botocore marks it synthesised rather than modeled |

Map key/value `locationName`, member `xmlName`, `queryName`, `requiresLength`,
`eventheader`, `jsonvalue` and per-member `timestampFormat` do not occur in
this model at all, so their absence from the descriptor cannot matter. None of
the omissions above has a `src/` consumer at this commit, so none can propagate
a wrong value into the client or the server today; each becomes a real gap only
if the named consumer is written against the descriptor rather than the JSON.

### Output tail (verbatim)

```
--------------------------------------------------------------------------
notes
--------------------------------------------------------------------------
  indexed-accessor 'when others' defaults (unreachable under the declared preconditions): Enumeration_Value='', Error_Shape='No_Shape', Location='Body_Location', Member_Context_Parameter='', Member_Flattened=False, Member_Location_Name='', Member_Name='', Member_Required=False, Member_Shape="Shape_Index'First", Member_Streaming=False, Member_XML_Attribute=False, Member_XML_Namespace=''

--------------------------------------------------------------------------
result
--------------------------------------------------------------------------
no mismatch: the committed descriptor agrees with the pinned model on every operation, shape, member, enumeration value and trait checked above, and every literal member ordinal in src/*.adb names the member its call site expects.
```

---

## Refutation attempts that failed to produce a finding

Each of these was an attempt to turn a discovery observation into a numbered
finding by re-deriving its reachability from the pinned JSON and the sources,
not from the discovery's prose.

- **O-1, the dead `querystring` branch** (`tools/s3_operation.py:1228-1231`).
  Confirmed verbatim by reading: the `querystring` branch does
  `target = target.replace(marker, encoded)` while `encoded` is bound only in
  the `uri` branch at `:1219` and `:1222`. Refuted as a finding by enumerating
  all 116 operations: no `requestUri` contains `{<locationName>}` for any
  member whose `location` is `querystring`, so the branch cannot execute. It
  is a latent `UnboundLocalError` in a test tool, not a product defect.
- **O-5, the ARN pattern on a header member** (`low_level.adb:927-929`). All
  four pattern-carrying shapes were enumerated with their uses:
  `CopySource` and `RenameSource` (the `\/?.+\/.+` source-path pattern) are the
  only ones on request-serialized non-body members;
  `S3RegionalOrS3ExpressBucketArnString` is a `header` member of
  `CreateBucketOutput` and `HeadBucketOutput`, and `NonEmptyKmsKeyArnString`
  and `Bucket.BucketArn` are body members. `Prepare_Model_Request_Internal`
  raises `Invalid_Request` on any body member (`low_level.adb:1072-1074`), so
  the request path never reaches those two; the exhaustive ordinal table above
  shows `Valid_Model_Scalar` is applied to response headers only for
  CreateSession (`:2735-2737`) and CopyObject (`:14725-14734`), never to
  HeadBucket or CreateBucket. Refuted: unreachable, and the residual behaviour
  is a fail-closed `return False`, not a wrong accept.
- **O-6, the XML list item-name fallback** (`tools/s3_codegen.py:967-969`).
  Confirmed verbatim: `member.get("locationName", item.get("locationName",
  item_shape))` falls back to the item shape name where REST-XML uses
  `member`. Refuted: the only two non-flattened lists whose member lacks
  `locationName` are `ObjectAttributesList` and `OptionalObjectAttributesList`,
  used exclusively as `header` members of `GetObjectAttributesRequest`,
  `ListObjectVersionsRequest`, `ListObjectsRequest` and `ListObjectsV2Request`,
  so neither ever appears in an XML body.
- **The hand-typed element names in the generated serializers** (the
  discovery's closing residual). Every string literal in all five committed
  generated serializers was extracted and matched against the reachable shape
  closure of that operation's input and output in the pinned JSON: element
  names, member names, `locationName`s and enumeration values. Every literal is
  a name the model actually contains (`PutBucketAcl`, `PutBucketLogging`,
  `PutBucketWebsite`, `PutBucketInventoryConfiguration`: zero unmatched;
  `ListDirectoryBuckets`: only the ARN prefixes `arn:`, `s3:`, `s3express:`,
  which are validation text, not element names). This refutes "a typo in an
  element name would not change the closure digest" for the sources as
  committed. It does not prove the converse (a *missing* element would not be
  detected by this check); that remains gated by the signed-socket bodies and
  the server corpora.
- **Registry and ledger drift.** Re-derived independently of
  `tools/s3_operation.py`: `coverage/aws-s3-operations.tsv` has 117 lines whose
  116 operation names are exactly `sorted(model["operations"])` in `LC_ALL=C`
  order; `coverage/s3-operation-counts.json` reports `operations: 116`;
  `coverage/s3-operations.toml:4-5` pins botocore revision
  `36c34f15391da01cd717c73c0fffa747c9889768` and the same SHA-256 as the
  generator, the `.ads` and `tools/verify-botocore-model.sh:12`. No drift.
  Limit of this check: it establishes internal consistency of the pin, not the
  pinned file's fidelity to upstream botocore at revision `36c34f15`. No
  network fetch was made, so "the pinned JSON is the right JSON" rests on the
  CI job that fetches that commit and re-runs `verify-botocore-model.sh`
  (`.github/workflows/ci.yml`), not on this verification.
- **Descriptor "fail-open" defaults.** `Member_Shape`'s `when others` default
  is `Shape_Index'First`, i.e. shape #1, which would answer for an
  out-of-range member instead of raising. Refuted as a finding: the program
  checks that all twelve indexed accessors carry a `Pre` bounding the index
  against the matching count accessor (`Error_Shape`, `Enumeration_Value`, and
  the ten `Member_*`/`Location` accessors), and they do
  (`.ads:397-400`, `:499-501`, `:511-576`), so under the declared contract the
  defaults are unreachable and SPARK proves the callers.
- **Non-ASCII or quote characters in emitted literals.** All 7 615 strings the
  descriptor emits (operation names, request URIs, authtypes, shape names,
  location names, payload members, timestamp formats, patterns, enumeration
  values, member names, member location names) were screened: every character
  is printable ASCII, so no literal can be mangled by `quote`'s `"` doubling or
  by a source encoding assumption.

## Observations carried forward (not findings)

- **O-3 (fragility) is upheld and now bounded.** The 74 literal member ordinals
  are bound to the JSON insertion order of `members`. They are all correct
  today; the SHA pin plus the full-text `generate --check` make silent drift
  impossible for *this* model. The residual risk is a future model bump that
  inserts a member before one of them, which would compile and validate against
  the wrong shape. `low_level.adb:11669-11673` already shows the name-based
  alternative (`Find_Model_Member (Output, "ObjectVersionId")`).
  `tests/repros/python/model_differential.py` is a ready regression gate for
  exactly that bump: it is standard-library-only, needs no build, and its
  consumer table fails closed on an ordinal that moves.
- **O-2 (diagnostic precision)** and **O-8 (unread checksum traits)** are
  outside what a JSON-versus-descriptor differential can settle and were not
  re-litigated; nothing in this verification contradicts the discovery's
  disposition of either. O-8 belongs to the CHECKSUM area by the discovery's
  own routing.
- **O-7 (`Long_Long_Integer'Value` leniency)** is a `Valid_Model_Scalar`
  behaviour, not a descriptor question; it is recorded in the CLIENT-LOW area.
  Confirmed present at `low_level.adb:949-963` (the `'Value` call is at `:955`); the descriptor supplies the
  bounds correctly (`Minimum`/`Maximum` compared as 64-bit values for both
  `integer` and `long` kinds), so no model-side defect contributes to it.

## Verdict

**The discovery's "no actionable finding" for MODEL is UPHELD.** The committed
descriptor is a faithful, complete and exact projection of the pinned model on
every attribute it exposes, over 116 operations, 718 shapes, 1 699 members and
279 enumeration values — 30 303 compared values covering every `return` in the
generated body — and every one of the 74 hard-coded member ordinals in
`src/*.adb` names the member its call site expects. No P0, P1 or P2 finding was
produced, and the twenty-mutation control shows the checker would have reported
one had it existed.
