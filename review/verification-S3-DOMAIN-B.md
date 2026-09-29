# Adversarial verification: S3-DOMAIN-B (object-level typed codecs and shared vocabulary)

Scope verified by reading: `src/flyology-object_storage-s3-deletions.ad?`,
`-tagging.ad?`, `-annotations.adb`, `-multipart_uploads.adb`,
`-attributes.adb`, `-checksum_policy.ads`, `-sigv4_encoding.ad?`,
`-core.ad?`, `-xml.ads`, `-model.ads`, the generated descriptor
`src/flyology-object_storage-s3-model.adb:45580-45605`,
`src/flyology-object_storage-tags.ads`,
`src/flyology-object_storage-server-s3_applications.adb` (DeleteObjects,
PutBucketTagging, PutObjectTagging, `x-amz-tagging`, ListMultipartUploads,
GetObjectAttributes, annotation routing and the authentication error map),
`src/flyology-object_storage-client-low_level.ad?` (annotation request
builder, model query emission, GetObjectAttributes and GetBucketTagging
decoders), the pinned model `review/baseline/service-2.json` (dumped with
python3), `docs/compatibility/s3.md`, `docs/qualification/copy-object.md`,
`tests/src/s3_implementation_corpus.adb:300-340`,
`tests/src/s3_server_application_corpus.adb:13400-13600`,
`tests/src/s3_server_harness.adb` and `tests/src/s3_memory_server.adb`.

Harness programs added: `tests/repros/src/repro_s3_domain_b_1.adb` ..
`repro_s3_domain_b_9.adb`. Nothing tracked was modified
(`git status --short` shows only untracked `review/`, `tests/repros/`,
`sqlite/tests/repros/`).

External servers used: the prebuilt, tracked `tests/bin/s3_memory_server`
(started by hand on 127.0.0.1, stopped afterwards — no `alr` or `gprbuild`
run) and one MinIO container started by hand from the image pinned in
`tests/scripts/test-minio.sh`
(`quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`,
`RELEASE.2025-09-07T16-13-09Z`). **`tests/scripts/test-minio.sh` itself was
not run** (it would have invoked `alr -n build`). The container was stopped
and removed at the end; a one-off `minio/mc` container
(`minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727`,
not pinned by the repository) was run with `--rm`.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| S3-DOMAIN-B-1 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_s3_domain_b_1.adb` |
| S3-DOMAIN-B-2 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_s3_domain_b_2.adb` |
| S3-DOMAIN-B-3 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_s3_domain_b_3.adb` |
| S3-DOMAIN-B-4 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_s3_domain_b_4.adb` |
| S3-DOMAIN-B-5 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_s3_domain_b_5.adb` |
| S3-DOMAIN-B-6 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_s3_domain_b_6.adb` |
| S3-DOMAIN-B-7 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_s3_domain_b_7.adb` |
| S3-DOMAIN-B-8 | NEW, CONFIRMED | P2 (—) | `tests/repros/src/repro_s3_domain_b_8.adb` |
| S3-DOMAIN-B-9 | NEW, CONFIRMED | P2 (—) | `tests/repros/src/repro_s3_domain_b_9.adb` |

---

## Stock client probe

All clients were pointed at the prebuilt `tests/bin/s3_memory_server`
(`AWS_ACCESS_KEY_ID=AKIDEXAMPLE`,
`AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY`,
`AWS_REGION=us-east-1`; it printed `PORT 62942`). Bodies marked "captured on
the wire" were read out of a logging TCP proxy on `0.0.0.0:62943` that
forwards to that port byte-for-byte; the proxy also let the Docker `mc`
container reach the loopback-only listener via `host.docker.internal`.

| Client | Version | Operation | Root element sent | Flyology server answer |
|--------|---------|-----------|-------------------|------------------------|
| boto3 | 1.43.89 / botocore 1.43.89 (uv, CPython 3.13.7) | DeleteObjects | `<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/">` | 400 `InvalidRequest` "DeleteObjects requires one valid Content-MD5 header" (SERVER-1, **not** the namespace) |
| boto3 | 1.43.89 | PutBucketTagging | `<Tagging xmlns="http://s3.amazonaws.com/doc/2006-03-01/">` | 400 `InvalidRequest` "PutBucketTagging requires a valid Content-MD5" (SERVER-1) |
| aws-cli v2 | aws-cli/2.36.34 Python/3.14.7 | `s3api delete-objects` | `<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/">` | 400 `InvalidRequest` "DeleteObjects requires one valid Content-MD5 header" |
| aws-cli v2 | 2.36.34 | `s3api put-bucket-tagging` | `<Tagging xmlns="http://s3.amazonaws.com/doc/2006-03-01/">` | 400 `InvalidRequest` "PutBucketTagging requires a valid Content-MD5" |
| s3cmd | 2.4.0 (uv, CPython 3.13) | `rm --recursive --force` | `<Delete>` — **no xmlns**, `Content-MD5` present (captured on the wire: `<Delete><Object><Key>k1</Key></Object><Object><Key>k2</Key></Object></Delete>`) | **400 `MalformedXML`** |
| s3cmd | 2.4.0 | `settagging` (bucket) | `<Tagging xmlns="http://s3.amazonaws.com/doc/2006-03-01/">` | 200 OK |
| mc (minio-go) | RELEASE.2025-08-13T08-35-41Z, minio-go v7.0.90, image `minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727` | `rm --recursive --force` | `<Delete>` — **no xmlns**, `Content-Md5: 31pfUAHQbxJHn3iLLTGlGg==` (captured on the wire: `<Delete><Quiet>false</Quiet><Object><Key>m1</Key></Object><Object><Key>m2</Key></Object><Object><Key>m3</Key></Object></Delete>`) | **400 `MalformedXML`** |
| mc (minio-go) | same | `tag set` (bucket **and** object) | `<Tagging>` — **no xmlns** (captured on the wire: `<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>`) | 400 `InvalidRequest` "UNSIGNED-PAYLOAD requires a secure transport" — minio-go signs this body as `UNSIGNED-PAYLOAD`, which the crate refuses on plain HTTP (`s3_applications.adb:1903-1906`), so the namespace check is not reached over this test endpoint. See the replay below. |

**Isolating the namespace.** The same bodies were replayed over plain HTTP
against the same server with a correct SigV4 header signature, a real payload
hash and `Content-MD5` (botocore `SigV4Auth`), so neither SERVER-1 nor the
UNSIGNED-PAYLOAD rule applies:

```
PutBucketTagging  mc body (no xmlns)   : 400 <Code>MalformedXML</Code>
PutBucketTagging  same body + xmlns    : 200
DeleteObjects     mc body (no xmlns)   : 400 <Code>MalformedXML</Code>
DeleteObjects     same body + xmlns    : 200 <DeleteResult ...><Deleted><Key>m1</Key></Deleted></DeleteResult>
s3cmd DeleteObjects body (no xmlns)    : 400 <Code>MalformedXML</Code>
```

**Oracle.** The same two namespace-free bodies sent to MinIO
`RELEASE.2025-09-07T16-13-09Z`:

```
DeleteObjects, namespace-free body (mc/s3cmd form): 200
  <DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>single-crc</Key></Deleted></DeleteResult>
PutBucketTagging, namespace-free body (mc form): 200
```

Conclusion: the `xmlns` attribute is a *serializer* trait on the request
member in the pinned model, not a receiver-side rule; the two AWS-generated
clients happen to emit it, and the two Go/Python third-party clients do not.

---

### S3-DOMAIN-B-1: DeleteObjects rejects a namespace-free `<Delete>` body

**Verdict:** CONFIRMED, including the interop sub-claim the discovery marked
"from memory, unverified". Both named clients were driven at the real
application and both are broken.

**Severity:** P0 (discovery said P1 with Medium confidence about which clients
omit `xmlns`). Corrected upward because two stock clients — minio `mc`
(minio-go, also the engine behind `mc rb --force`) and `s3cmd` — send a
namespace-free `<Delete>` **with a correct Content-MD5** by default and are
answered `400 MalformedXML`, while MinIO answers `200` for the identical
bytes. This is the rubric's "interop-breaking protocol violation"; batch
delete is completely unavailable from these clients and nothing is deleted.

Verified by reading:

- `src/flyology-object_storage-s3-deletions.adb:66-79` —
  `Start_Element_Details` raises `Malformed_Delete` unless
  `Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"`; it is an
  override on `Delete_Handler`, so it runs for **every** element, not just
  the root.
- `src/flyology-object_storage-s3-deletions.adb:380-393` — `Parse_Request`
  calls `XML.Parse` then `Validate`; handler exceptions surface through the
  `when XML.XML_Error` branch as `Malformed_Delete "malformed DeleteObjects
  XML"`.
- `src/flyology-object_storage-server-s3_applications.adb:17730-17741` — the
  request body is passed verbatim to `Deletions.Parse_Request`; no
  namespace normalisation anywhere in between.
- `src/flyology-object_storage-server-s3_applications.adb:17959-17964` —
  `when Deletions.Malformed_Delete => Send_Error (X, 400, "MalformedXML", ...)`.
- `review/baseline/service-2.json` — the `Delete` shape carries no
  `xmlNamespace`; only `DeleteObjectsRequest.Delete` (the member) does.
- `src/flyology-object_storage-s3-deletions.ads:76-82` — the `Parse_Request`
  contract says only "Parse one bounded DeleteObjects request document"; it
  does not promise namespace enforcement.

Refutation attempts that failed:

- Looked for a tolerant request-side entry point analogous to
  `Tagging.Parse_Bucket_Response`: `Deletions` has none.
- Checked whether the XML layer supplies the S3 namespace implicitly for an
  unqualified document: repro 1's unit-level call shows it does not.
- Checked whether the discovery's client claim was wrong: it is not.
  Captured `mc`'s and `s3cmd`'s bodies off the wire; both are namespace-free
  and both carry Content-MD5, so SERVER-1 is not what stops them.
- Checked whether the rejection could be some other property of those bodies
  (`<Quiet>` first, no `<Quiet>` at all): adding only `xmlns` to each body
  turns the same request into `200` (replay table above, and the control in
  repro 1).
- Checked `docs/qualification/delete-objects.md`: the strictness is
  documented, so it is deliberate — but it is not an S3 protocol rule, and
  MinIO accepts what this server refuses, so DOCUMENTED LIMITATION does not
  apply.

**Repro:** `tests/repros/src/repro_s3_domain_b_1.adb`. Creates a bucket and
`k1`/`k2`/`k3`, calls `Deletions.Parse_Request` on `mc`'s captured document,
then sends `mc`'s and `s3cmd`'s captured bodies as signed `POST /bucket?delete`
requests with a correct `Content-MD5`, asserting `200` and a `<Deleted>` entry
for each. The boto3/aws-cli namespaced body is the control.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_1`, exit status **1**):

```
  -- === fixtures ===
  ok: CreateBucket /domain-b1 is 200
  ok: PutObject k1 is 200
  ok: PutObject k2 is 200
  ok: PutObject k3 is 200
  -- 
  -- === unit level: Deletions.Parse_Request ===
  -- Parse_Request raised Malformed_Delete: malformed DeleteObjects XML
  FAILED: Deletions.Parse_Request accepts a namespace-free <Delete>
  -- 
  -- === server: stock-client bodies (must be accepted) ===
  -- mc (minio-go) DeleteObjects    body=<Delete><Quiet>false</Quiet><Object><Key>k1</Key></Object></Delete>
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-b1?delete</Resource></Error>
  FAILED: mc (minio-go) DeleteObjects    is answered 200
  FAILED: mc (minio-go) DeleteObjects    reports k1 as deleted
  -- s3cmd DeleteObjects            body=<Delete><Object><Key>k2</Key></Object></Delete>
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-b1?delete</Resource></Error>
  FAILED: s3cmd DeleteObjects            is answered 200
  FAILED: s3cmd DeleteObjects            reports k2 as deleted
  -- 
  -- === control: the same request with xmlns (passes today) ===
  -- boto3/aws-cli DeleteObjects    body=<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>k3</Key></Object><Quiet>false</Quiet></Delete>
  --     status=200 body=<?xml version="1.0" encoding="UTF-8"?><DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>k3</Key></Deleted></DeleteResult>
  ok: boto3/aws-cli DeleteObjects    is answered 200
  ok: boto3/aws-cli DeleteObjects    reports k3 as deleted
BUG REPRODUCED: 5 failed expectation(s)
```

**Description:** `Delete_Handler.Start_Element_Details`
(`deletions.adb:66-79`) requires the exact S3 namespace URI on every element
of a DeleteObjects request body. In the pinned model the namespace is a
serializer trait on the `DeleteObjectsRequest.Delete` *member*, not a
constraint on the `Delete` shape, so receivers must not demand it — AWS and
MinIO do not. minio-go marshals `<Delete><Quiet>…</Quiet><Object>…` and s3cmd
concatenates `<Delete><Object>…`; both were captured off the wire against
this server and both are answered `400 MalformedXML`, deterministically, for
every batch. `mc rm --recursive`, `mc rb --force` and `s3cmd rm --recursive`
therefore cannot delete anything from a Flyology endpoint, while the same
commands work against MinIO and AWS. Note that boto3 and aws-cli are stopped
one step earlier by SERVER-1 (they now send `x-amz-checksum-crc32` instead of
`Content-MD5`), so today no client can batch-delete at all; fixing SERVER-1
alone would still leave `mc` and `s3cmd` broken here.
`tests/src/object_storage_test_cases.adb:11450-11452` pins the wrong
behaviour with `Must_Reject_Request ("<Delete><Object><Key>k</Key></Object></Delete>", …)`
and would have to be inverted. A fix needs a maintainer decision equivalent
to the one already taken for bucket tagging: either accept an absent
namespace on request parsing (the `Allow_Empty_Namespace` pattern of
`tagging.adb:434-448`, which would be a new public parameter or a second
entry point) or accept it unconditionally.

---

### S3-DOMAIN-B-2: PutBucketTagging rejects a namespace-free `<Tagging>` body that PutObjectTagging accepts

**Verdict:** CONFIRMED, including the client sub-claim: minio-go really does
marshal `<Tagging>` with no namespace, captured off the wire from `mc tag set`
for both the bucket and the object form.

**Severity:** P0 (discovery said P1, Medium confidence). Corrected upward for
the same reason as B-1 and under the same instruction: `mc`'s default
PutBucketTagging body is rejected *for the namespace*, proven by replaying
its exact bytes with a valid signature and `Content-MD5` (400 `MalformedXML`)
and then adding only `xmlns` (200). Caveat, stated plainly: over the plain-HTTP
test endpoint `mc` is stopped one step earlier because minio-go signs this
body as `UNSIGNED-PAYLOAD`, which the crate refuses without TLS
(`s3_applications.adb:1903-1906`); on the HTTPS endpoint a real deployment
uses, that gate passes and the namespace check is what remains. MinIO accepts
the identical body with `200`.

Verified by reading:

- `src/flyology-object_storage-s3-tagging.adb:434-448` —
  `Bucket_Tagging_Handler.Start_Element_Details` rejects an empty
  `Namespace_URI` unless `Allow_Empty_Namespace` is set.
- `src/flyology-object_storage-s3-tagging.adb:574-586` — `Parse_Bucket` uses
  `Allow_Empty_Namespace => False`; `Parse_Bucket_Response` uses `True`.
- `src/flyology-object_storage-server-s3_applications.adb:8261-8271` — the
  server calls the strict `Tagging.Parse_Bucket`; `:8284-8294` maps
  `Malformed_Tagging` to `400 MalformedXML` and `Invalid_Tag` to
  `400 InvalidTag`.
- `src/flyology-object_storage-s3-tagging.adb:43-89` — the object
  `Tagging_Handler` overrides no `Start_Element_Details`, so
  `PutObjectTagging` accepts any namespace, including none.
- `src/flyology-object_storage-s3-tagging.ads:48-52` — the tolerance is
  granted to the *response* decoder only.
- `review/baseline/service-2.json` — the `Tagging` shape carries no
  `xmlNamespace`.

Refutation attempts that failed:

- Searched for a tolerant request path: `Parse_Bucket_Response` is called
  only from `client-low_level.adb:392` (`Decode_Get_Bucket_Tagging_Response`).
- Checked whether the object path also enforces a namespace, which would at
  least make the server self-consistent: it does not (repro 2 shows the same
  document accepted on `PUT /bucket/k?tagging` and refused on
  `PUT /bucket?tagging`).
- Checked whether some other property of `mc`'s body is at fault: adding only
  `xmlns` turns the request into `200`.
- Checked whether `docs/qualification/bucket-tagging.md` makes it a
  documented limitation: it documents "strict namespace-aware XML", but the
  model imposes no such rule and MinIO accepts the body, so the same
  reasoning as B-1 applies.

**Repro:** `tests/repros/src/repro_s3_domain_b_2.adb`. Compares
`Parse_Bucket` with `Parse_Bucket_Response` on `mc`'s captured document, then
sends that document as a signed `PUT …?tagging` to both the object and the
bucket resource with a correct `Content-MD5`, asserting `200` for both.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_2`, exit status **1**):

```
  -- === fixtures ===
  ok: CreateBucket /domain-b2 is 200
  ok: PutObject k is 200
  -- 
  -- === unit level: the two bucket entry points on one document ===
  -- Parse_Bucket_Response accepted it, tags=1
  ok: control: Parse_Bucket_Response decodes the mc document
  -- Parse_Bucket raised FLYOLOGY.OBJECT_STORAGE.S3.TAGGING.MALFORMED_TAGGING: malformed bucket tagging XML
  FAILED: Tagging.Parse_Bucket accepts a namespace-free <Tagging>
  -- 
  -- === server: the same document on both tagging paths ===
  -- PutObjectTagging, mc document (accepted today)
  --     PUT /domain-b2/k?tagging body=<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
  --     status=200 body=
  ok: PutObjectTagging, mc document (accepted today) is answered 200
  -- PutBucketTagging, mc document                 
  --     PUT /domain-b2?tagging body=<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-b2?tagging</Resource></Error>
  FAILED: PutBucketTagging, mc document                  is answered 200
  -- 
  -- === control: PutBucketTagging with xmlns (passes today) ===
  -- PutBucketTagging, boto3/aws-cli document      
  --     PUT /domain-b2?tagging body=<Tagging xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
  --     status=200 body=
  ok: PutBucketTagging, boto3/aws-cli document       is answered 200
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** the crate already has the tolerant behaviour — the
`Allow_Empty_Namespace` flag threaded through `Parse_Bucket_Document`
(`tagging.adb:550-586`) — and grants it only to the response decoder. The
result is a server that accepts a document on `PUT /bucket/key?tagging` and
rejects the identical document on `PUT /bucket?tagging`, deterministically,
for any client that does not emit `xmlns`; minio-go is such a client, on both
resources. `tests/src/object_storage_test_cases.adb:11268-11270` pins the
rejection and `:11233-11243` pins the acceptance of the same string by the
response decoder, so the suite currently asserts the inconsistency. A fix is
one Boolean: flipping `Parse_Bucket`'s `Allow_Empty_Namespace` to `True`
brings the request path in line with the response path and with the object
path, and needs no new public declaration. The maintainer decision is whether
"foreign namespaces remain invalid" should stay (it can — only the *empty*
namespace is at issue).

---

### S3-DOMAIN-B-3: ListObjectAnnotations query codec binds names the model, the descriptor and this crate's own client do not use

**Verdict:** CONFIRMED. This is a self-interop failure: the crate's own
client cannot use a prefix, a result limit, or pagination against the crate's
own server.

**Severity:** P1 (unchanged). Not P0: `ListObjectAnnotations` is a Flyology
extension operation, so no third-party SDK is involved; it is a wrong result
on valid input via a reachable path.

Verified by reading:

- `src/flyology-object_storage-s3-annotations.adb:137-172` — the codec
  matches `annotationPrefix`, `maxAnnotationResults`, `continuationToken`,
  and falls through to
  `raise Malformed_Annotation_Request with "unsupported annotation query parameter"`.
- `review/baseline/service-2.json`, `ListObjectAnnotationsRequest`
  querystring members: `VersionId → versionId`,
  `MaxAnnotationResults → max-annotation-results`,
  `AnnotationPrefix → annotation-prefix`,
  `ContinuationToken → continuation-token`.
- `src/flyology-object_storage-s3-model.adb:45588-45599` — the generated
  descriptor carries the same hyphenated names.
- `src/flyology-object_storage-client-low_level.adb:11605-11624` —
  `Prepare_List_Object_Annotations` adds `MaxAnnotationResults`,
  `AnnotationPrefix` and `ContinuationToken` by member name; `:1216-1222`
  emits `SigV4.Pair (Model.Member_Location_Name (Input_Shape, Member), …)`,
  i.e. the hyphenated spelling.
- `src/flyology-object_storage-server-s3_applications.adb:6505-6529` — the
  route sniff uses the model-conformant `&annotationName=`, but any
  `Malformed_Annotation_Request` sets `Annotation_Query_Invalid`;
  `:7015-7019` answers `400 InvalidArgument`.

Refutation attempts that failed:

- Checked whether the generated descriptor came from a different model
  revision: repro 3 reads the location names out of the *compiled* model and
  prints the hyphenated forms, so descriptor and pinned JSON agree.
- Searched for a second parser that accepts the hyphenated spellings:
  `continuation-token` appears only in the ListObjectsV2 and ListBuckets
  parsers.
- Checked whether the optional members are unreachable in practice: repro 3
  drives them end to end, and
  `tests/src/s3_server_application_corpus.adb:13540-13600` uses the
  camelCase spellings, so the in-tree gate asserts the non-model names.

**Repro:** `tests/repros/src/repro_s3_domain_b_3.adb`. Prints the compiled
model's query location names for the operation, creates an object with two
annotations, then issues signed `GET …?annotation&<name>=<value>` requests in
both spellings and asserts that the model's spelling is accepted, including a
second page driven by a real `NextContinuationToken`.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_3`, exit status **1**):

```
  -- === the pinned model's ListObjectAnnotations query names ===
  ok: control: the model has a ListObjectAnnotations input shape
  --     VersionId -> "versionId" (what Client.Low_Level puts on the wire)
  --     MaxAnnotationResults -> "max-annotation-results" (what Client.Low_Level puts on the wire)
  --     AnnotationPrefix -> "annotation-prefix" (what Client.Low_Level puts on the wire)
  --     ContinuationToken -> "continuation-token" (what Client.Low_Level puts on the wire)
  -- 
  -- === fixtures ===
  ok: CreateBucket /domain-b3 is 200
  ok: PutObject obj is 200
  ok: PutObjectAnnotation alpha is 200
  ok: PutObjectAnnotation beta is 200
  -- 
  -- === control: the codec's camelCase spellings (accepted today) ===
  -- control  GET /domain-b3/obj?annotation&maxAnnotationResults=1
  --     status=200 body=<ListObjectAnnotationsOutput xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Annotations><AnnotationEntry><AnnotationName>alpha</AnnotationName>...<NextContinuationToken>fos1.5073ca3abd4a8ffc65e51385fca7513b2c3a2c5015c9debcaa3ecaf577636496.616c706861</NextContinuationToken></ListObjectAnnotationsOutput>
  -- control  GET /domain-b3/obj?annotation&annotationPrefix=al
  --     status=200 body=<ListObjectAnnotationsOutput ...><AnnotationPrefix>al</AnnotationPrefix><AnnotationCount>1</AnnotationCount></ListObjectAnnotationsOutput>
  -- 
  -- === the model's spellings, as the crate's own client sends ===
  -- model    GET /domain-b3/obj?annotation&max-annotation-results=1
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The object annotation request query is invalid</Message><Resource>/domain-b3/obj?annotation&amp;max-annotation-results=1</Resource></Error>
  FAILED: the model's spelling "max-annotation-results" is accepted
  -- model    GET /domain-b3/obj?annotation&annotation-prefix=al
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The object annotation request query is invalid</Message><Resource>/domain-b3/obj?annotation&amp;annotation-prefix=al</Resource></Error>
  FAILED: the model's spelling "annotation-prefix" is accepted
  -- 
  -- === pagination with the model's continuation-token ===
  -- first page (camelCase) status=200
  ok: control: the first page returns a continuation token
  -- token=fos1.5073ca3abd4a8ffc65e51385fca7513b2c3a2c5015c9debcaa3ecaf577636496.616c706861
  -- model    GET /domain-b3/obj?annotation&continuation-token=fos1.5073ca3abd4a8ffc65e51385fca7513b2c3a2c5015c9debcaa3ecaf577636496.616c706861
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The object annotation request query is invalid</Message><Resource>/domain-b3/obj?annotation&amp;continuation-token=fos1...</Resource></Error>
  FAILED: the model's spelling "continuation-token" is accepted
BUG REPRODUCED: 3 failed expectation(s)
```

(The three long response bodies above are elided at `...`; the program prints
them in full.)

**Description:** `Annotations.Parse_Query` (`annotations.adb:137-172`) hard-codes
camelCase names for the three list-only query members, while every other part
of the crate — the pinned model, the generated descriptor
`Model.Member_Location_Name`, and `Client.Low_Level.Prepare_List_Object_Annotations`
which reads that descriptor — uses the hyphenated names. A Flyology client
that asks for a prefix, a page size, or the next page therefore gets
`400 InvalidArgument` from a Flyology server, deterministically; only the
degenerate "list everything, one page" call works. The two operations are
correct for the singular annotation verbs (`annotationName`, `versionId`), so
only these three names need changing. The in-tree gate
`tests/src/s3_server_application_corpus.adb:13552` and `:13588` sends the
camelCase names and would have to be updated with the fix; the qualification
lane `tests/src/s3_list_object_annotations_qualification.adb:50-83` only adds
the optional members when environment inputs are set, which is why the
default lane never noticed. No new public declaration is needed — the fix is
to compare against `Model.Member_Location_Name` (as
`multipart_uploads.adb` already does for enumerations) or to correct the
three literals.

---

### S3-DOMAIN-B-4: URL-encoded ListMultipartUploads cursors are compared bytewise, so a valid truncated page becomes 500 InternalError

**Verdict:** CONFIRMED, and cheaper to hit than the discovery estimated: no
non-ASCII key is needed. Keys `a9` and `a:` are enough, because `%` (16#25#)
sorts below every unreserved byte.

**Severity:** P1 (unchanged). A valid, backend-answered request ends as
`500 InternalError`; the crate's own client maps the same exception to
`Invalid_Response`. Not P0: no data is lost and nothing hangs.

Verified by reading:

- `src/flyology-object_storage-s3-multipart_uploads.adb:655-667` — the
  "next cursor does not advance" predicate compares
  `US.To_String (Value.Next_Key_Marker) < US.To_String (Value.Key_Marker)`.
- `:773-795` and `:823-828` — `Validate` runs inside both
  `Parse_List_Multipart_Uploads` (client) and
  `Serialize_List_Multipart_Uploads` (server).
- `src/flyology-object_storage-server-s3_applications.adb:11199-11204` — the
  local `Encoded` function applies `Encoding.URI_Encode (Value, Encode_Slash => False)`
  when `Request.URL_Encoding`; `:11218-11220` and `:11240-11244` fill
  `Key_Marker` and `Next_Key_Marker` with `Encoded (...)`, while
  `Upload_ID_Marker` and `Next_Upload_ID_Marker` stay raw.
- `src/flyology-object_storage-server-s3_applications.adb:11279-11286` — the
  handler catches only `Multipart_Uploads.Malformed_List_Request`, so
  `Malformed_Upload_Listing` escapes to the final `when others` and becomes
  `500 InternalError`.
- `src/flyology-object_storage-s3-sigv4_encoding.adb:10-46` — `Unreserved`
  is `A-Z a-z 0-9 - . _ ~` (plus `/` when `Encode_Slash => False`); every one
  of those bytes is above `%`, so percent-encoding inverts the order of any
  pair whose first divergent byte is reserved-above-unreserved.
- `src/flyology-object_storage-client-low_level.adb:13405`, `:13423-13426` —
  the client maps `Malformed_Upload_Listing` to `Invalid_Response`.

Refutation attempts that failed:

- Checked whether the server compares decoded values: it does not; the
  `Response` record is built from `Encoded (...)`.
- Checked whether the client can avoid requesting URL encoding: it is a
  supported parameter (`client-low_level.adb:13477-13484`), and a conforming
  server that encodes `NextKeyMarker` produces the same rejection in the
  client decoder even if the server is not Flyology (first block of repro 4).
- Checked whether the inversion needs non-ASCII: it does not. `a9` < `a:`
  raw, `a%3A` < `a9` encoded.
- Checked whether sibling listing codecs share the predicate: `rg "does not
  advance" src/*.adb` matches only this file.

**Repro:** `tests/repros/src/repro_s3_domain_b_4.adb`. Creates multipart
uploads for `a9`, `a:` and `az`, decodes a conforming truncated URL-encoded
page through the client decoder, then pages the real server with
`encoding-type=url&max-uploads=1` and asserts `200` on page 2. The same paging
without `encoding-type` is the control.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_4`, exit status **1**):

```
  -- === fixtures ===
  ok: CreateBucket /domain-b4 is 200
  -- CreateMultipartUpload key=[a9] status=200 uploadId=4fb6a2da4e6e6bdcf9f54177bb76c1f3d8d1b2bf182692ac255249bf1d4e006b
  ok: CreateMultipartUpload for key [a9] is 200
  -- CreateMultipartUpload key=[a:] status=200 uploadId=59ac7c6c3e2d4b00fcf084f9785a4153804a8fd2ff79d2806000c02cc61391ad
  ok: CreateMultipartUpload for key [a:] is 200
  -- CreateMultipartUpload key=[az] status=200 uploadId=113f3b58679a9186d5e447368e08eb4422e85e1e144467160063ae57c71a5d10
  ok: CreateMultipartUpload for key [az] is 200
  -- 
  -- === client decoder: a conforming truncated url-encoded page ===
  -- Parse_List_Multipart_Uploads raised Malformed_Upload_Listing: ListMultipartUploads next cursor does not advance
  FAILED: client decodes an encoded truncated page
  -- 
  -- === server: paging with encoding-type=url&max-uploads=1 ===
  -- page 1 status=200
  --     body=<?xml version="1.0" encoding="UTF-8"?><ListMultipartUploadsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Bucket>domain-b4</Bucket><NextKeyMarker>a9</NextKeyMarker><NextUploadIdMarker>4fb6a2da...</NextUploadIdMarker><MaxUploads>1</MaxUploads><IsTruncated>true</IsTruncated><Upload>...<Key>a9</Key>...</Upload><EncodingType>url</EncodingType></ListMultipartUploadsResult>
  ok: page 1 is 200
  ok: page 1 NextKeyMarker is a9
  -- page 2 (key-marker=a9) status=500
  --     body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error</Message><Resource>/domain-b4?uploads&amp;encoding-type=url&amp;max-uploads=1&amp;key-marker=a9&amp;upload-id-marker=4fb6a2da...</Resource></Error>
  FAILED: page 2 of a url-encoded listing is 200
  FAILED: page 2 reports the encoded next key marker a%3A
  -- 
  -- === control: the same paging without encoding-type ===
  -- plain page 2 status=200
  --     body=<?xml version="1.0" encoding="UTF-8"?><ListMultipartUploadsResult ...><KeyMarker>a9</KeyMarker><NextKeyMarker>a:</NextKeyMarker>...<IsTruncated>true</IsTruncated><Upload>...<Key>a:</Key>...</Upload></ListMultipartUploadsResult>
  ok: control: page 2 without encoding-type is 200
BUG REPRODUCED: 3 failed expectation(s)
```

(Upload identifiers and repeated `<Upload>` bodies are elided at `...`; the
program prints them in full.)

**Description:** `Multipart_Uploads.Validate` treats `Next_Key_Marker <
Key_Marker` as proof that a page's cursor went backwards, but the server has
already percent-encoded both markers when `encoding-type=url` was requested
(`s3_applications.adb:11199-11244`), and percent-encoding is not
order-preserving. Any truncated page whose next key first differs from the
previous marker at a byte that encodes — `:` `[` `=` `&` `?` `#`, a space, or
any non-ASCII byte — trips the check inside
`Serialize_List_Multipart_Uploads`, and because the handler only catches
`Malformed_List_Request` the exception escapes to the generic handler and the
caller sees `500 InternalError` for a request the backend answered correctly.
Keys containing `:` are ordinary (timestamps, URNs, `a:b` namespacing), so
this is deterministic and not exotic. The client decoder is affected
symmetrically: any conforming server that URL-encodes `NextKeyMarker` makes
`Parse_List_Multipart_Uploads` raise `Invalid_Response`
(`client-low_level.adb:13423-13426`), so this also breaks Flyology against
AWS. No existing test produces the combination
(`tests/src/s3_http_socket_corpus.adb:12666-12694` uses URL encoding only to
check echo mismatches). A fix must compare the *decoded* markers — the server
has them in `Request.Key_Marker` and `Page.Next_After.Key` before encoding —
which means either validating before encoding or carrying the decoded cursor
alongside; that is an internal change, but the codec's `Validate` is shared
with the client decoder, so the maintainer must decide whether `Validate`
should decode `Key_Marker`/`Next_Key_Marker` when `Encoding_Type = "url"`
(the only choice that also fixes the client) or drop the ordering predicate
for encoded pages.

---

### S3-DOMAIN-B-5: GetObjectAttributes rejects the two AWS Backup storage classes

**Verdict:** CONFIRMED.

**Severity:** P2 (unchanged). Needs an object in one of two uncommon storage
classes, and only affects the client decoder.

Verified by reading:

- `src/flyology-object_storage-s3-attributes.adb:756-760` —
  `Valid_Storage_Class` lists thirteen literals.
- `:775-779` — `Validate` raises `Malformed_Attributes "invalid storage class"`
  whenever the member is present and unlisted.
- `review/baseline/service-2.json` — `StorageClass` has fifteen values;
  repro 5 prints the same fifteen straight out of the compiled model.
- `src/flyology-object_storage-client-low_level.adb:5324-5333` — the client
  maps `Malformed_Attributes` to `Invalid_Response "malformed
  GetObjectAttributes response"`.
- `src/flyology-object_storage-s3-multipart_uploads.adb:687-689` — the
  sibling codec validates the same shape *dynamically* against the model
  (`Valid_Enumeration (…, Upload_Member_Shape (4))`), so the crate already
  has the mechanism that would have avoided this.

Refutation attempts that failed:

- Checked whether `StorageClass` is only validated when selected: it is
  validated whenever present, and it is present exactly when the caller
  selects it — which the convenience clients expose.
- Checked whether the pinned model is the limitation: it is not; the model
  has both values and `s3-replication.adb:483-487` already decodes both.

**Repro:** `tests/repros/src/repro_s3_domain_b_5.adb`. Prints the compiled
model's `StorageClass` enumeration, then decodes a `GetObjectAttributes`
response body for each class through `S3.Attributes.Parse_Result` and through
`Client.Low_Level.Decode_Get_Object_Attributes_Response`.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_5`, exit status **1**):

```
  -- === the pinned model's StorageClass enumeration ===
  ok: control: the model has a GetObjectAttributes output shape
  ok: control: the output shape has a StorageClass member
  -- model StorageClass values (15):
  --     STANDARD
  --     REDUCED_REDUNDANCY
  --     STANDARD_IA
  --     ONEZONE_IA
  --     INTELLIGENT_TIERING
  --     GLACIER
  --     DEEP_ARCHIVE
  --     OUTPOSTS
  --     GLACIER_IR
  --     SNOW
  --     EXPRESS_ONEZONE
  --     FSX_OPENZFS
  --     FSX_ONTAP
  --     AWS_BACKUP_WARM
  --     AWS_BACKUP_LOW_COST_WARM
  -- 
  -- === control: a class the codec knows ===
  -- STANDARD
  --   S3.Attributes.Parse_Result: accepted, StorageClass=[STANDARD]
  --   Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- GLACIER_IR
  --   S3.Attributes.Parse_Result: accepted, StorageClass=[GLACIER_IR]
  --   Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- 
  -- === the two modeled classes the codec does not know ===
  -- AWS_BACKUP_WARM
  --   S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid storage class
  --   Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: client decodes StorageClass AWS_BACKUP_WARM
  -- AWS_BACKUP_LOW_COST_WARM
  --   S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid storage class
  --   Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: client decodes StorageClass AWS_BACKUP_LOW_COST_WARM
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** `Attributes.Valid_Storage_Class` (`attributes.adb:756-760`)
duplicates the model's `StorageClass` enumeration as thirteen string literals
and has drifted two values behind it. An AWS object materialised by AWS
Backup answers `200` with `<StorageClass>AWS_BACKUP_WARM</StorageClass>`, and
every typed and convenience GetObjectAttributes client then reports
`Invalid_Response "malformed GetObjectAttributes response"` for a valid,
modelled answer. No test pins the list (`rg AWS_BACKUP tests/src` matches only
the replication corpus), and the crate's own server only ever emits
`STANDARD`, which is why no lane sees it. The compatibility matrix row
(`docs/compatibility/s3.md:60`) claims a "complete typed" client for this
operation, so the drift also contradicts a maintained document. The fix
should replace the literal list with the model-driven check the sibling codec
already uses, so it cannot drift again; no new public declaration is needed.

---

### S3-DOMAIN-B-6: PutObjectTagging reports tag failures as MalformedXML while the two other tag paths report InvalidTag

**Verdict:** CONFIRMED. The internal inconsistency is exact, and MinIO
confirms `InvalidTag` for two of the three cases.

**Severity:** P2 (unchanged) — wrong diagnostics, no wrong data.

Verified by reading:

- `src/flyology-object_storage-s3-tagging.adb:61-64` — the eleventh `<Tag>`
  raises `Malformed_Tagging "invalid object tag entry"`.
- `:161-166` — `Parse` folds `not Valid_S3_Tags (Handler.Tags)` (repertoire
  and duplicate-key failures) into
  `Malformed_Tagging "invalid object tagging document"`; the package's own
  `Invalid_Tag` exception (`tagging.ads:10`) is never raised on this path.
- `src/flyology-object_storage-server-s3_applications.adb:15956-15962` —
  `when Tagging.Malformed_Tagging => Send_Error (X, 400, "MalformedXML", "The
  XML provided did not validate against the object tagging schema", …)`.
- `:15072-15080` (`x-amz-tagging` on PutObject) and `:11987-11999`
  (CreateMultipartUpload) — the same `Valid_S3_Tags` failure yields
  `400 InvalidTag`.
- `:8284-8294` (PutBucketTagging) — `Invalid_Tag` and `Malformed_Tagging` are
  kept apart, giving `InvalidTag` and `MalformedXML` respectively.
- `review/baseline/service-2.json` — **the model names no error shape at all
  for `PutObjectTagging`, `PutBucketTagging` or `DeleteObjects`** (their
  `errors` lists are empty), and there is no `InvalidTag` exception shape
  anywhere in the model. The model therefore does not settle the code; the
  crate's own other two paths do.

Oracle (MinIO `RELEASE.2025-09-07T16-13-09Z`, same three documents):

```
PutObjectTagging with key a#b:          400 <Code>InvalidTag</Code>  "The TagKey you have provided is invalid"
PutObjectTagging with a duplicate key:  400 <Code>InvalidTag</Code>  "Cannot provide multiple Tags with the same key"
PutObjectTagging with eleven tags:      400 <Code>BadRequest</Code>  "Tags cannot be more than 10"
```

Refutation attempts that failed:

- Looked for an `Invalid_Tag` raise anywhere on the object XML path: there is
  none; `tagging.adb:161-174` collapses everything.
- Checked whether the server re-validates the parsed set before storage and
  could emit `InvalidTag` there: `s3_applications.adb:15940-15954` stores the
  parsed set directly.
- Checked whether the documents were rejected for the namespace instead
  (B-2): every document in the repro carries `xmlns`, and the bucket control
  with the identical body reaches `InvalidTag`.

**Repro:** `tests/repros/src/repro_s3_domain_b_6.adb`. Sends three namespaced
`PUT /bucket/k?tagging` documents with correct `Content-MD5` — an
out-of-repertoire key, a duplicate key, eleven tags — and asserts the
`<Code>` is `InvalidTag`; the `x-amz-tagging` header path and
PutBucketTagging with the same bad key are the controls.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_6`, exit status **1**):

```
  -- === fixtures ===
  ok: CreateBucket /domain-b6 is 200
  ok: PutObject k is 200
  -- 
  -- === the same tag failures on the object XML path ===
  -- PutObjectTagging  outside the AWS repertoire (key a#b)
  --     status=400 code=MalformedXML
  FAILED: PutObjectTagging reports InvalidTag for outside the AWS repertoire (key a#b)
  -- PutObjectTagging  duplicate key                       
  --     status=400 code=MalformedXML
  FAILED: PutObjectTagging reports InvalidTag for duplicate key                       
  -- PutObjectTagging  eleven tags                         
  --     status=400 code=MalformedXML
  FAILED: PutObjectTagging reports InvalidTag for eleven tags                         
  -- 
  -- === controls: the other two paths on the same server ===
  -- control PutObject x-amz-tagging with key a#b
  --     status=400 code=InvalidTag
  ok: control: PutObject x-amz-tagging with key a#b already reports InvalidTag
  -- control PutBucketTagging with key a#b       
  --     status=400 code=InvalidTag
  ok: control: PutBucketTagging with key a#b        already reports InvalidTag
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** the object tagging XML parser has no way to signal "the XML
was fine, the tags were not": `Tagging.Parse` (`tagging.adb:163-166`) raises
`Malformed_Tagging` for a structural error, a repertoire violation, a
duplicate key and an eleventh tag alike, and the server maps that one
exception to `MalformedXML` with a message about the schema. A caller whose
tag key contains `#`, or who repeats a key, or who sends eleven tags, is told
its XML is malformed; the identical tag set sent as `x-amz-tagging` on
PutObject, or as a bucket tag set, is told `InvalidTag`. This is
deterministic and confusing rather than harmful.
`tests/src/s3_server_application_corpus.adb:6420-6422` already asserts
`InvalidTag` on the header path, and `:14400-14495` covers PutObjectTagging
admission without asserting any code for an invalid tag, so no test would
have to be inverted for the two cases MinIO confirms. The maintainer decision
is the code for the count case: the crate's own header path says `InvalidTag`
(which is what this repro asserts), MinIO says `BadRequest`, and the pinned
model names neither — so the count case needs an explicit choice, whereas the
repertoire and duplicate cases are settled by both the crate's own other
paths and MinIO. A fix means raising `Tagging.Invalid_Tag` (already declared
at `tagging.ads:10`) from the `Valid_S3_Tags` and tag-count failures and
adding one `when Tagging.Invalid_Tag` arm at `s3_applications.adb:15956`; no
new public declaration is needed.

---

### S3-DOMAIN-B-7: GetObjectAttributes infers "multipart" from the presence of `<ObjectParts>` and rejects valid full-object SHA/MD5/xxHash checksums

**Verdict:** CONFIRMED, and the "concrete stock-server trigger" the discovery
could not verify is now captured: MinIO really returns
`<Checksum><ChecksumSHA256>…</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum>`
together with `<ObjectParts><PartsCount>1</PartsCount>…</ObjectParts>` for an
object stored with a single PUT.

**Severity:** P2 (unchanged). It needs a non-Flyology server that reports the
parts container for a single-part object; the crate's own server never does
(shown in the repro), so there is no self-interop failure and the severity is
not raised.

Verified by reading:

- `src/flyology-object_storage-s3-attributes.adb:422-428` —
  `Has_Object_Parts` is set on the `<ObjectParts>` start tag alone.
- `:771-774` — `Validate_Object_Checksum (Value.Checksum, Is_Multipart =>
  Value.Has_Object_Parts)`.
- `:731-738` — the `FULL_OBJECT` branch requires
  `Policy.Supported (Algorithm, Policy.Full_Object)` whenever `Is_Multipart`.
- `src/flyology-object_storage-s3-checksum_policy.ads:68-75` — `Supported`
  is documented as "whether AWS permits the algorithm/type pair **for
  multipart use**" and allows only `CRC32 | CRC32C | CRC64NVME`.
- `src/flyology-object_storage-s3-checksum_policy.ads:76-83` — the package
  already has the right predicate for the other case,
  `Ordinary_Object_Supported (Kind) = (Kind = Full_Object)`, documented as
  "PutObject and CopyObject accept every concrete algorithm in the pinned
  model, always as one full-object digest". The decoder never reaches it,
  because it decides which world it is in from the container's presence.
- `src/flyology-object_storage-s3-attributes.adb:857-877` — an absent
  `ChecksumType` with a plain Base64 digest is *inferred* as `FULL_OBJECT`,
  so servers that omit the type hit the same branch.
- `review/baseline/service-2.json` — `GetObjectAttributesParts` is an
  ordinary optional member of `GetObjectAttributesOutput`; nothing ties its
  presence to a multipart upload, and the request enum lets a caller select
  `ObjectParts` for any object.
- `src/flyology-object_storage-server-s3_applications.adb:16314-16317` — the
  Flyology server emits `ObjectParts` only when `Snapshot.Is_Multipart`.

Oracle (MinIO `RELEASE.2025-09-07T16-13-09Z`, object written with one
`PUT` carrying `x-amz-checksum-sha256`):

```
GET /probe-b7/single?attributes  (x-amz-object-attributes: ETag,Checksum,ObjectParts,StorageClass,ObjectSize) : 200
<getObjectAttributesResponse><ETag>5eb63bbbe01eeed093cb22bb8f5acdc3</ETag><Checksum><ChecksumSHA256>uU0nuZNNPgilLlLX2n2r+sSE7+N6U4DukIj3rOLvzek=</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum><ObjectParts><IsTruncated>false</IsTruncated><MaxParts>10000</MaxParts><NextPartNumberMarker>1</NextPartNumberMarker><PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount><Part><PartNumber>1</PartNumber><Size>11</Size></Part></ObjectParts><StorageClass>STANDARD</StorageClass><ObjectSize>11</ObjectSize></getObjectAttributesResponse>
```

Refutation attempts that failed:

- Looked for a stronger multipart signal the decoder could use
  (`PartsCount > 1`, a `-N` composite ETag suffix, a multipart ETag): none is
  consulted.
- Checked whether `Has_Object_Parts` could be false for an empty container:
  no, `:426-427` sets it on the start tag.
- Checked whether the Flyology server can produce the combination itself: it
  cannot (repro 7's last block shows it omits `ObjectParts` for a single-PUT
  object even when the attribute is selected, and its own client reads its
  own answer).
- Checked whether MinIO's response would fail for some other reason first:
  it does — MinIO uses the lowercase root `getObjectAttributesResponse`,
  which `attributes.adb:405-408` rejects, and that deviation is already a
  *documented* exclusion (`tests/scripts/test-minio.sh:64,74` sets
  `FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE=minio-2025-lowercase-root`,
  "a non-AWS lowercase root element"), so it is not a new finding — but it
  is why the checksum rule was never exercised in-tree. The repro therefore
  re-roots MinIO's exact `Checksum`/`ObjectParts` bytes under the AWS root.

**Repro:** `tests/repros/src/repro_s3_domain_b_7.adb`. Decodes MinIO's
captured checksum/parts combination (plus MD5, xxHash64 and the
type-omitted variant) through `S3.Attributes.Parse_Result` and
`Client.Low_Level.Decode_Get_Object_Attributes_Response`, with a
`FULL_OBJECT CRC32` page and a parts-free SHA-256 page as controls, then
checks what the crate's own server emits and that its own client reads it.
MinIO's `<MaxParts>10000</MaxParts>` is lowered to `1000` here so only the
checksum rule is exercised — the 10000 echo is S3-DOMAIN-B-8.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_7`, exit status **1**):

```
  -- === controls: shapes the decoder accepts today ===
  -- FULL_OBJECT CRC32, parts container present   
  --     S3.Attributes.Parse_Result: accepted, Has_Checksum=TRUE Has_Object_Parts=TRUE
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- FULL_OBJECT SHA256, no parts container       
  --     S3.Attributes.Parse_Result: accepted, Has_Checksum=TRUE Has_Object_Parts=FALSE
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- 
  -- === the modeled combinations the decoder rejects ===
  -- FULL_OBJECT SHA256 + parts (MinIO's answer)  
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: FULL_OBJECT SHA256 + parts (MinIO's answer)  
  -- FULL_OBJECT MD5 + parts                      
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: FULL_OBJECT MD5 + parts                      
  -- FULL_OBJECT XXHASH64 + parts                 
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: FULL_OBJECT XXHASH64 + parts                 
  -- untyped raw SHA256 + parts (type omitted)    
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: untyped raw SHA256 + parts (type omitted)    
  -- 
  -- === self-interop: what this crate's own server emits ===
  ok: CreateBucket /domain-b7 is 200
  ok: PutObject with x-amz-checksum-sha256 is 200
  -- GetObjectAttributes status=200
  --     body=<?xml version="1.0" encoding="UTF-8"?><GetObjectAttributesResponse xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><ETag>5eb63bbbe01eeed093cb22bb8f5acdc3</ETag><Checksum><ChecksumSHA256>uU0nuZNNPgilLlLX2n2r+sSE7+N6U4DukIj3rOLvzek=</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum><ObjectSize>11</ObjectSize></GetObjectAttributesResponse>
  ok: control: the crate's own GetObjectAttributes is 200
  -- this crate's own answer, read by its own client
  --     S3.Attributes.Parse_Result: accepted, Has_Checksum=TRUE Has_Object_Parts=FALSE
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  ok: this crate's own answer, read by its own client
BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** `Attributes.Validate` (`attributes.adb:771-774`) passes
`Is_Multipart => Value.Has_Object_Parts` into `Validate_Object_Checksum`,
using the presence of the requested `<ObjectParts>` attribute group as
evidence that the object was uploaded in parts. It then applies the narrow
multipart policy (`Checksum_Policy.Supported`, CRC only) instead of the
ordinary-object policy the same package documents
(`Ordinary_Object_Supported`, any modelled algorithm as one full-object
digest). A caller that selects `Checksum,ObjectParts` on a single-PUT object
whose server reports a one-part container — MinIO does exactly this, captured
above — gets `Invalid_Response` for a valid, modelled `200`. The same branch
fires when the server omits `ChecksumType` and the decoder infers
`FULL_OBJECT` (`:857-877`), so it is not limited to servers that emit the
type. It is deterministic and affects only the client side; the Flyology
server never produces the combination, which is why the codec and server
corpora do not see it, and `tests/src/s3_implementation_corpus.adb:1675-1700`
only pairs `ObjectParts` with CRC-family checksums on completed multipart
objects. A fix needs a maintainer decision on what "multipart" means to this
decoder: the available signals are `TotalPartsCount > 1`, a composite `-N`
ETag suffix, or `ChecksumType = COMPOSITE` — or, simplest, applying
`Ordinary_Object_Supported` unless the checksum is explicitly `COMPOSITE`.
No new public declaration is required; `Checksum_Policy` already exports both
predicates.

---

### S3-DOMAIN-B-8 (new): the GetObjectAttributes decoder bounds the response's `MaxParts` echo by `Core.Page_Size'Last`

**Verdict:** CONFIRMED. Found while verifying B-7 — MinIO's real response was
rejected before the checksum rule was even reached.

**Severity:** P2. A valid, modelled response is rejected, but only from a
server that echoes a `MaxParts` above 1000, and against MinIO specifically it
is masked by the already-documented lowercase-root exclusion.

Verified by reading:

- `src/flyology-object_storage-s3-attributes.adb:551-576` — `Finish_Field`
  raises `Malformed_Attributes "invalid object part scalar"` when
  `Item.Field = Max_Parts_Field and then Parsed.Value > Core.Page_Size'Last`.
  Because this runs inside the SAX handler, `Parse_Result`'s
  `when XML.XML_Error` arm rewrites it to the misleading
  "malformed GetObjectAttributes XML".
- `src/flyology-object_storage-s3-attributes.adb:786-790` — `Validate`
  applies the same `Core.Page_Size'Last` bound a second time.
- `src/flyology-object_storage-s3-core.ads:28` —
  `subtype Page_Size is Natural range 0 .. 1_000;`
- `review/baseline/service-2.json` —
  `GetObjectAttributesParts.MaxParts` has shape `MaxParts`, which is
  `{'type': 'integer'}` with **no** `min` or `max`. The request-side member is
  the `x-amz-max-parts` header, also unbounded in the model.
- Captured MinIO response (above): `<MaxParts>10000</MaxParts>` on **every**
  GetObjectAttributes request that selects `ObjectParts`, regardless of the
  requested value.

Refutation attempts that failed:

- Checked whether the crate simply reuses a request-side bound that the model
  does impose: it does not; neither `MaxParts` shape carries a bound.
- Checked whether an in-tree oracle already covers it: it does not.
  `tests/src/s3_implementation_corpus.adb:303-340` disables the
  GetObjectAttributes assertions entirely under
  `FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE=minio-2025-lowercase-root`, so
  MinIO's `MaxParts` never reaches the decoder in CI.
- Checked whether B-7 explains it: no. The repro uses a `FULL_OBJECT CRC32`
  checksum, which the multipart policy accepts, and the only difference
  between pass and fail is the `MaxParts` value.

**Repro:** `tests/repros/src/repro_s3_domain_b_8.adb`. Decodes the same
response body twice, with `<MaxParts>1000</MaxParts>` and MinIO's real
`<MaxParts>10000</MaxParts>`, through the codec and the client decoder.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_8`, exit status **1**):

```
  -- Core.Page_Size'Last  = 1000
  -- Core.Part_Number'Last= 10000
  -- 
  -- === control: a MaxParts echo inside the crate's bound ===
  -- control: MaxParts within Page_Size (MaxParts=1000)
  --     S3.Attributes.Parse_Result: accepted, MaxParts=1000
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- 
  -- === MinIO's actual MaxParts echo ===
  -- MinIO's GetObjectAttributes answer (MaxParts=10000)
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: malformed GetObjectAttributes XML
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** the decoder constrains the *response's* `MaxParts` echo to
`Core.Page_Size'Last` (1000), a bound that exists for Flyology's own
pagination policy and that the pinned model does not place on this member.
MinIO answers `<MaxParts>10000</MaxParts>` for every GetObjectAttributes
request that selects `ObjectParts`, so a Flyology client talking to a
MinIO-compatible server gets `Invalid_Response` for a well-formed `200`. The
diagnostic is also wrong: because the check runs inside the SAX handler it is
rewritten to "malformed GetObjectAttributes XML", pointing a maintainer at
the parser rather than at a range. Against MinIO itself the failure is
currently masked by the documented lowercase-root exclusion, which is why no
lane sees it. The maintainer decision is what bound, if any, an echoed
`MaxParts` should have on the receive side — `Core.Part_Number'Last` (10000)
would accept MinIO, no bound at all would follow the model, and either choice
is a change to a validation rule rather than to a public declaration.

---

### S3-DOMAIN-B-9 (new): the GetBucketTagging response decoder rejects an empty `<TagSet/>`

**Verdict:** CONFIRMED. Promoted from the discovery's "empty TagSet"
observation, which said "the tested servers answer `NoSuchTagSet` instead of
an empty set". MinIO answers `NoSuchTagSet` only when no tag set was ever
stored; if a client stores an *empty* tag set — which MinIO accepts with
`200` — MinIO then serves `<Tagging><TagSet></TagSet></Tagging>` with `200`,
so the state is reachable.

**Severity:** P2. It needs a bucket whose tag set was deliberately stored
empty by some other client, and it produces a wrong error rather than wrong
data.

Verified by reading:

- `src/flyology-object_storage-s3-tagging.adb:565-566` —
  `Parse_Bucket_Document` raises
  `Invalid_Tag "invalid bucket tag set"` when
  `not Tags.Valid_Bucket_Tag_Set (Handler.Result)`; this runs for both
  `Parse_Bucket` and `Parse_Bucket_Response`.
- `src/flyology-object_storage-tags.ads:34-40` —
  `Valid_Bucket_Tag_Set` is documented as validating "a **nonempty** bucket
  tag set". It is a *publication* predicate, applied here to a decoded
  response.
- `src/flyology-object_storage-client-low_level.adb:375-405` —
  `Decode_Get_Bucket_Tagging_Response` calls `Parse_Bucket_Response` and maps
  `Invalid_Tag` to `Invalid_Response "malformed GetBucketTagging response"`.
- `review/baseline/service-2.json` — `Tagging.TagSet` is a plain list with no
  `min`, so an empty set is modelled.

Oracle (MinIO `RELEASE.2025-09-07T16-13-09Z`):

```
DeleteBucketTagging:                                       204
GetBucketTagging after delete:                             404 <Code>NoSuchTagSet</Code>
PutBucketTagging with an empty TagSet:                     200
GetBucketTagging after PUT with an empty TagSet:           200  <Tagging><TagSet></TagSet></Tagging>
```

Refutation attempts that failed:

- Checked whether the client leaves the exception unmapped (which would be
  worse): it does not; `Invalid_Tag` is caught and re-raised as
  `Invalid_Response`.
- Checked whether the empty state is only reachable through Flyology's own
  client: it is not reachable that way at all —
  `Tagging.Serialize_Bucket` (`tagging.adb:591-595`) refuses to serialize an
  empty set — which is exactly why the decoder never sees it in-tree; another
  client has to create the state.
- Checked whether `Parse_Bucket_Response`'s contract permits the rejection:
  `tagging.ads:48-52` only promises namespace tolerance and says nothing
  about emptiness.

**Repro:** `tests/repros/src/repro_s3_domain_b_9.adb`. Decodes MinIO's exact
`<Tagging><TagSet></TagSet></Tagging>` bytes through
`S3.Tagging.Parse_Bucket_Response` and
`Client.Low_Level.Decode_Get_Bucket_Tagging_Response`, with a one-tag body as
the control.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_b_9`, exit status **1**):

```
  -- === control: a one-tag GetBucketTagging response ===
  -- control: one tag                     body=<Tagging><TagSet><Tag><Key>k</Key><Value>v</Value></Tag></TagSet></Tagging>
  --     S3.Tagging.Parse_Bucket_Response: accepted, tags=1
  --     Client.Low_Level: accepted, kind=BUCKET_TAGS_FOUND
  -- 
  -- === MinIO's empty-TagSet GetBucketTagging response ===
  -- client decodes an empty bucket TagSet body=<Tagging><TagSet></TagSet></Tagging>
  --     S3.Tagging.Parse_Bucket_Response: FLYOLOGY.OBJECT_STORAGE.S3.TAGGING.INVALID_TAG: invalid bucket tag set
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetBucketTagging response
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** `Parse_Bucket_Document` runs the same
`Tags.Valid_Bucket_Tag_Set` predicate on the way in and on the way out, and
that predicate's documented meaning is "a tag set that may be published" —
which requires at least one tag. The pinned model puts no minimum on
`Tagging.TagSet`, and MinIO really serves an empty one for a bucket whose tag
set was stored empty, so a Flyology client reports `Invalid_Response` for a
well-formed `200`. The failure is deterministic given that bucket state and
unreachable through Flyology's own writer, which is why nothing in-tree
covers it. A fix means splitting the receive-side check from the publication
check — accepting an empty decoded set in `Parse_Bucket_Response` while
`Serialize_Bucket` and `Parse_Bucket` keep the nonempty rule — which is a
maintainer decision about the meaning of `Tags.Tag_Set` at the boundary
(`tags.ads:34-40`) rather than a new public declaration.

---

## The twelve observations, assessed

1. **`Copies.Validate` requires both `ETag` and `LastModified`** though every
   `CopyObjectResult` member is optional in the model. Confirmed as stated,
   and confirmed to be deliberate: `docs/qualification/copy-object.md:215`
   says "the production decoder continues to require one strong quoted
   entity-tag". **DOCUMENTED LIMITATION**, no finding.
2. **Object `Tagging.Parse` requires `<Key>` before `<Value>`**
   (`tagging.adb:78`: the `Value` arm tests `Item.Seen_Key`), while the
   bucket parser accepts either order (`tagging.adb:485`: the `Value` arm
   tests only `not Item.Seen_Value`). Re-derived from source and confirmed as
   an internal inconsistency. Every SDK serialises in model order (Key then
   Value) and every captured client body above does, so no reachable client
   is affected. Observation, no finding.
3. **`Tagging.Parse_Header` keeps `+` literal.** The discovery asked for an
   oracle; here it is. MinIO decodes `+` as a space:
   `PUT /obj` with `x-amz-tagging: a+b=c+d` then `GET /obj?tagging` returns
   `<Tag><Key>a b</Key><Value>c d</Value></Tag>` (and `a%20b=c%20d` gives the
   same result). Flyology stores the key `a+b`. This is explicitly documented
   policy (`tagging.ads:27-30`: "unlike HTML form encoding, a plus sign is
   not decoded as a space"), so under the rubric it is a **DOCUMENTED
   LIMITATION**, not a numbered finding — but it is the one observation whose
   consequence is *silently different data* rather than an error, and any
   client that builds `x-amz-tagging` with a form encoder (the usual
   `urlencode(...)` recipe) will store different tags on Flyology than on
   MinIO or AWS. Recommend an explicit maintainer decision.
4. **`Parse_Bucket_Response` rejects an empty `<TagSet/>`.** Promoted to
   **S3-DOMAIN-B-9** above, because MinIO does produce that response.
5. **`Object_Reads.Parse_Conditional_Date` and `Ada.Calendar` limits.**
   Accepted as harmless: out-of-range values yield `Valid => False`, which
   callers treat as an ignorable invalid HTTP-date per RFC 9110. No finding.
6. **`max-uploads` outside 1 .. 1000 is rejected with `InvalidArgument`.**
   Documented in `multipart_uploads.ads:33-35` ("max-uploads is in
   1 .. 1_000"). MinIO accepts and echoes both `0` and `5000`
   (`<MaxUploads>0</MaxUploads>`, `<MaxUploads>5000</MaxUploads>`, both
   `200`), so the divergence is real, but no captured client sends such a
   value. **DOCUMENTED LIMITATION**, no finding.
7. **`Multipart_Uploads.Validate:642-654` rejects a non-truncated page with
   next markers, and a truncated ungrouped page without
   `NextUploadIdMarker`.** Not reproducible against MinIO: MinIO emits
   *empty* `<NextKeyMarker></NextKeyMarker>` elements on a non-truncated
   page, which decode to zero-length strings and pass. Observation stands, no
   finding. Separately noted: MinIO answered `max-uploads=1` with three
   `<Upload>` entries and `<MaxUploads>1</MaxUploads><IsTruncated>false</IsTruncated>`,
   which `Validate`'s first branch (`Uploads.Length > Max_Uploads`) correctly
   rejects — that is a MinIO defect, not a crate defect, but it does mean the
   crate's client cannot list multipart uploads against this MinIO release.
8. **`Annotations.Parse_List` requires the root `ListObjectAnnotationsOutput`
   although the model gives the output no `locationName`.** Confirmed as
   stated. Both sides of the crate agree on that root, so it is consistent
   today; B-3 shows that agreement on the root is not evidence of general
   model conformance for this operation. Observation, no finding.
9. **`Annotations.Decode_Continuation:246-250` `Constraint_Error` on short
   tokens.** Refutation re-verified:
   `Core.Valid_Listing_Continuation_Syntax` (`s3-core.adb:8-23`) rejects any
   token shorter than the 70-byte header before the slices are taken. No
   finding.
10. **`Deletions.Serialize_Request` emits `ETag` before `Key`**
    (`deletions.adb:407-412`), out of model member order. Re-derived from
    source. Receivers are order-insensitive — the crate's own
    `Parse_Request` is, and MinIO accepted `mc`'s body whose `<Quiet>` comes
    first. Observation, no finding.
11. **Mandatory `Content-MD5` on DeleteObjects.** Out of area (SERVER-1), and
    independently re-observed here: current boto3 and aws-cli send
    `x-amz-checksum-crc32` instead and are answered
    `400 InvalidRequest`. The same gate applies to PutBucketTagging
    ("PutBucketTagging requires a valid Content-MD5"), which the SERVER report
    may want to note.
12. **Eleventh-tag and repertoire diagnostics on the object XML path.**
    Covered by B-6 above, with a MinIO oracle.
