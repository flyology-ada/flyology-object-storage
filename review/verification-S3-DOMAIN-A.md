# Adversarial verification: S3-DOMAIN-A (bucket-level typed codecs)

Scope verified by reading: `src/flyology-object_storage-s3-versions.ad?`,
`-listings.ad?`, `-lifecycle.ad?`, `-notifications.ad?`, `-replication.ad?`,
`-versioning.ad?`, `-buckets.ad?`, `-inventory.ad?`, `-metrics.ad?`,
`-analytics.ad?`, `-intelligent_tiering.ad?`, `-acl.adb`, `-core.ads`,
`-paginated_rest_xml_reads.adb`, `-strict_xml_codecs.adb`, `-xml.adb`,
`-generated_list_directory_buckets_xml.ad?`, `tools/s3_codegen.py:805-830`
and `:1922-1990`, `src/flyology-object_storage-server-s3_applications.adb`
(`:6218-6250`, `:7233-7240`, `:8801-9100`, `:9595-9610`, `:10395-10440`,
`:10758-10772`), `src/flyology-object_storage-client-objects.ad?`
(`:395-430`, `:2672-2775`, `:2855-2946`),
`src/flyology-object_storage-client-low_level.adb:1690-1700,2220-2230,9277,9319,9577,16793`,
`review/baseline/service-2.json` (all shapes named below, dumped with
python3), `docs/compatibility/s3.md`, `docs/qualification/list-objects-v1.md`,
`docs/qualification/list-object-versions.md`,
`docs/qualification/list-directory-buckets.md`,
`tests/src/s3_implementation_corpus.adb`,
`tests/src/s3_list_object_versions_corpus.adb`,
`tests/corpora/list-object-versions/members.tsv`,
`tests/scripts/test-minio.sh`. External authority: the AWS S3 API Reference
pages named per finding, fetched 2026-09-06.

Harness programs added: `tests/repros/src/repro_s3_domain_a_1.adb`,
`_2.adb`, `_3.adb`, `_4.adb`, `_5.adb`, `_5_live.adb` (loopback holder, not
an assertion), `_6.adb`, `_7.adb`, `repro_s3_domain_a_minio_probe.adb`.
Nothing tracked was modified (`git status --short` shows only untracked
`review/`, `tests/repros/`, `sqlite/tests/repros/`).

I started one MinIO container by hand from the digest pinned in
`tests/scripts/test-minio.sh` and stopped it at the end; I did not run any
repository test script and never invoked `alr` or `gprbuild` directly.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| S3-DOMAIN-A-1 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_s3_domain_a_1.adb` + `repro_s3_domain_a_minio_probe.adb` |
| S3-DOMAIN-A-2 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_s3_domain_a_2.adb` + `repro_s3_domain_a_minio_probe.adb` |
| S3-DOMAIN-A-3 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_s3_domain_a_3.adb` |
| S3-DOMAIN-A-4 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_s3_domain_a_4.adb` |
| S3-DOMAIN-A-5 | CONFIRMED | P0 (P2/P0 conditional) | `tests/repros/src/repro_s3_domain_a_5.adb` (+ `_5_live.adb`) |
| S3-DOMAIN-A-6 | CONFIRMED (new) | P1 (uncounted observation) | `tests/repros/src/repro_s3_domain_a_6.adb` |
| S3-DOMAIN-A-7 | CONFIRMED (new) | P1 (uncounted observation) | `tests/repros/src/repro_s3_domain_a_7.adb` + `repro_s3_domain_a_minio_probe.adb` |

---

## MinIO probe

Image: `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`,
the exact digest pinned in `tests/scripts/test-minio.sh:5`. `docker run --rm
"$IMG" --version` printed `minio version RELEASE.2025-09-07T16-13-09Z
(commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`, which is the
provenance string that script checks at `:21-24`. Container
`flyology-review-domain-a-8289`, started by hand with
`--publish 127.0.0.1::9000` and the same root credentials the script uses;
stopped and removed at the end (`docker ps -a --filter
name=flyology-review-domain-a` is empty). No repository script was run.

Findings from the probe:

- **PutObject storage classes.** MinIO accepts `x-amz-storage-class:
  REDUCED_REDUNDANCY` (200) and rejects `STANDARD_IA`, `GLACIER`,
  `ONEZONE_IA` and `INTELLIGENT_TIERING` with `InvalidStorageClass`. So on
  MinIO the reachable non-`STANDARD` version class is `REDUCED_REDUNDANCY`.
- **ListObjectVersions on the wire.** With versioning enabled and one
  `REDUCED_REDUNDANCY` object, `GET /bucket?versions` returns 200 with
  `<StorageClass>REDUCED_REDUNDANCY</StorageClass>` inside `<Version>`
  (S3-DOMAIN-A-1), and every untruncated page carries an empty
  `<NextVersionIdMarker></NextVersionIdMarker>` with no `<NextKeyMarker>`
  (S3-DOMAIN-A-7).
- **ListObjects v1 on the wire.** Three keys, `max-keys=1`, no delimiter:
  200 with `<IsTruncated>true</IsTruncated>` and
  `<NextMarker>k1[minio_cache:v2,return:]</NextMarker>` and no
  `<Delimiter>` (S3-DOMAIN-A-2). With `delimiter=/` MinIO emits the same
  `NextMarker` plus `<Delimiter>/</Delimiter>`.
- **max-keys above 1000.** `GET /bucket?max-keys=2000` and
  `?list-type=2&max-keys=2000` both return 200 and echo
  `<MaxKeys>2000</MaxKeys>` (S3-DOMAIN-A-6).
- **Configuration listings.** `GET /bucket?inventory`, `?metrics`,
  `?analytics` and `?intelligent-tiering` all return **501
  `NotImplemented`** with an `<Error>` root. MinIO cannot settle the
  S3-DOMAIN-A-4 root names; the AWS API Reference is the only authority and
  is quoted in that finding.

Verbatim probe output (`FLYOLOGY_REPRO_MINIO_PORT=32805
AWS_ACCESS_KEY_ID=FLYOLOGYS3ORACLE
AWS_SECRET_ACCESS_KEY=flyology-s3-oracle-secret-key-tests
./run.sh repro_s3_domain_a_minio_probe 300`, exit status **1**):

```
  -- MinIO endpoint http://127.0.0.1:32805
  -- --- fixture setup over raw signed HTTP ---
  -- CreateBucket flyology-review-domain-a-versions -> 409
  -- PutBucketVersioning Enabled -> 200
  -- PutObject x-amz-storage-class: REDUCED_REDUNDANCY -> 200
  ok: MinIO accepts REDUCED_REDUNDANCY on PutObject
  -- PutObject x-amz-storage-class: STANDARD_IA -> 400 (recorded, not asserted)
  -- PutObject obj-standard -> 200
  -- CreateBucket flyology-review-domain-a-standard -> 200
  -- PutBucketVersioning Enabled -> 200
  -- PutObject only-standard (default class) -> 200
  -- CreateBucket flyology-review-domain-a-v1 -> 409
  --   PutObject k1 -> 200
  --   PutObject k2 -> 200
  --   PutObject k3 -> 200
  -- --- what MinIO puts on the wire for GET ?versions ---
  -- status 200, root <ListVersionsResult>, 2009 bytes
  -- <?xml version="1.0" encoding="UTF-8"?>
<ListVersionsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>flyology-review-domain-a-versions</Name><Prefix></Prefix><KeyMarker></KeyMarker><NextVersionIdMarker></NextVersionIdMarker><VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Version><Key>obj-reduced-redundancy</Key><LastModified>2026-09-07T06:37:51.459Z</LastModified><ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag><Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner><StorageClass>REDUCED_REDUNDANCY</StorageClass><IsLatest>true</IsLatest><VersionId>d2d35353-d5ab-49e4-8c7d-d9705eefce9f</VersionId></Version><Version><Key>obj-reduced-redundancy</Key><LastModified>2026-09-07T06:33:59.191Z</LastModified><ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag><Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner><StorageClass>REDUCED_REDUNDANCY</StorageClass><IsLatest>false</IsLatest><VersionId>310970e3-5880-4836-b58e-9be8fa8ca02c</VersionId></Version><Version><Key>obj-standard</Key><LastModified>2026-09-07T06:37:51.465Z</LastModified><ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag><Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner><StorageClass>STANDARD</StorageClass><IsLatest>true</IsLatest><VersionId>2978cc49-16b8-4a96-a524-27fed4519104</VersionId></Version><Version><Key>obj-standard</Key><LastModified>2026-09-07T06:33:59.195Z</LastModified><ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag><Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner><StorageClass>STANDARD</StorageClass><IsLatest>false</IsLatest><VersionId>2087b1c8-248b-4929-b9e0-f9e8b1cf3685</VersionId></Version></ListVersionsResult>
  ok: MinIO reports REDUCED_REDUNDANCY inside <Version>
  -- --- Client.Objects.List_Versions_Page against MinIO ---
  -- List_Versions_Page flyology-review-domain-a-versions: raised Invalid_Response: malformed ListObjectVersions response
  FAILED: List_Versions_Page returns a page for a MinIO bucket holding a REDUCED_REDUNDANCY version
  -- List_Versions_Page flyology-review-domain-a-standard: raised Invalid_Response: malformed ListObjectVersions response
  FAILED: List_Versions_Page returns a page for a MinIO bucket holding only STANDARD versions
  -- --- Client.Objects.List_V1_Page against MinIO ---
  -- List_V1_Page max-keys=1 delimiter=/: kind PAGE_AVAILABLE status 200
  ok: List_V1_Page returns the first page (delimiter=/)
  --   objects 1 truncated TRUE next_marker "k1[minio_cache:v2,return:]"
  -- List_V1_Page max-keys=1 no delimiter: raised Invalid_Response: ListObjects response is invalid or exceeds the XML limit
  FAILED: List_V1_Page returns the first page (no delimiter)
  -- --- S3-DOMAIN-A-4: does MinIO implement the configuration listings at all? (recorded, not asserted) ---
  -- GET /flyology-review-domain-a-versions?inventory -> 501, root <Error>
  -- GET /flyology-review-domain-a-versions?metrics -> 501, root <Error>
  -- GET /flyology-review-domain-a-versions?analytics -> 501, root <Error>
  -- GET /flyology-review-domain-a-versions?intelligent-tiering -> 501, root <Error>
BUG REPRODUCED: 3 failed expectation(s)
```

---

## Stock client probe

Target: the in-process S3 application behind
`Repro_S3_Server.Start_Loopback`, held open by
`tests/repros/src/repro_s3_domain_a_5_live.adb`. `mc` runs inside Docker, so
it reached the loopback listener through a plain logging TCP relay on
`0.0.0.0`; the bytes below are the relay's capture of the real socket.

Three clients, `PutBucketVersioning` with `Status=Enabled`:

| Client | Version | Body it sent | Server answer |
|--------|---------|--------------|---------------|
| boto3 / botocore | 1.43.89 | `<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Status>Enabled</Status></VersioningConfiguration>` | 400 `InvalidRequest` — but for the *checksum* reason (`requires one valid Content-MD5 header`), not the namespace; unaffected by S3-DOMAIN-A-5 |
| aws-cli v2 | 2.36.34 (Python 3.14.7) | same, with `xmlns` | same checksum rejection; unaffected by S3-DOMAIN-A-5 |
| MinIO `mc` | RELEASE.2025-08-13T08-35-41Z, minio-go/v7.0.90, image `minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727` | `<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>` (75 bytes, **no `xmlns`**) | **400 `MalformedXML`** — S3-DOMAIN-A-5 |

The `mc` exchange on the wire (relay capture, credentials as issued by
`Repro_S3_Server`):

```
PUT /stock-versioning-3/?versioning= HTTP/1.1
Host: host.docker.internal:58080
User-Agent: MinIO (linux; arm64) minio-go/v7.0.90 mc/RELEASE.2025-08-13T08-35-41Z
Content-Length: 75
Accept-Encoding: zstd,gzip
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=content-md5;host;x-amz-content-sha256;x-amz-date, Signature=288f4807165b37be5cc4445778b32d2e5aeed6db3f28f5574848f8636d31677e
Content-Md5: 8qj8HSeDu3APPMQZVG06WQ==
X-Amz-Content-Sha256: dd6f6f21cc8680cc5c32bba98d4297e37552279d7e326a35df847ed2713f2d6a
X-Amz-Date: 20260907T063040Z

<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>
===== SERVER -> CLIENT =====
HTTP/1.1 400 Bad Request
Date: Mon, 07 Sep 2026 06:30:40 GMT
Content-Length: 235
Content-Type: application/xml
Connection: keep-alive

<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/stock-versioning-3/?versioning=</Resource></Error>
```

`mc` reports `mc: <ERROR> Unable to enable versioning. The XML provided was
not well-formed or did not validate against the published schema`. Note that
`mc` supplied a correct `Content-MD5`, so it cleared every checksum gate; the
only reason for the rejection is the absent namespace.

Also captured on the same listener, for S3-DOMAIN-A-6, with aws-cli 2.36.34:

```
aws s3api list-objects-v2 --bucket stock-versioning --max-keys 2000
  -> An error occurred (InvalidArgument) when calling the ListObjectsV2
     operation: The ListObjectsV2 request is invalid
aws s3api list-objects      --bucket stock-versioning --max-keys 5000
  -> An error occurred (InvalidArgument) when calling the ListObjects ...
aws s3api list-object-versions --bucket stock-versioning --max-keys 2000
  -> An error occurred (InvalidArgument) when calling the ListObjectVersions ...
aws s3api list-objects-v2 --bucket stock-versioning --max-keys 1000
  -> 200, "MaxKeys": 1000
```

The same three commands against the pinned MinIO return 200.

---

### S3-DOMAIN-A-1: ListObjectVersions decoder rejects every `Version` whose `StorageClass` is not `STANDARD`

**Verdict:** CONFIRMED. Every sub-claim held, and the part the discovery
marked "from memory, unverified" is now settled against a real server: the
pinned MinIO does emit `REDUCED_REDUNDANCY` in `<Version>`.

**Severity:** P1 (discovery said P1). It is a wrong result — an exception —
on valid input through a reachable path. It is *not* P0 because
`docs/compatibility/s3.md:67` ends the ListObjectVersions row with "no
external interoperability claim", so no documented contract is broken; were
that disclaimer absent this would be P0 by the interop clause, since a stock
server's valid 200 response is refused outright.

Verified by reading:

- `src/flyology-object_storage-s3-versions.adb:798-805` — `Storage_Class_Field`
  calls `Valid_Enumeration (Value, Version_Member_Shape (5))` and raises
  `Malformed_Version_Listing "invalid ObjectVersion storage class"`.
- `src/flyology-object_storage-s3-versions.adb:354-361` —
  `Version_Member_Shape` resolves output member 6 (`Versions`), then that
  list's member shape, then member N of `ObjectVersion`.
- `review/baseline/service-2.json`, dumped with python3: `ObjectVersion`
  member 5 is `StorageClass` with shape `ObjectVersionStorageClass`, and
  `ObjectVersionStorageClass` is `{"type": "string", "enum": ["STANDARD"]}`.
  `ObjectStorageClass`, used by `Object` member 7, has fifteen values.
  `ListObjectVersionsOutput` member 6 is `Versions`, so the index arithmetic
  is right.
- `src/flyology-object_storage-s3-versions.adb:364-380` — `Valid_Enumeration`
  returns False for anything outside the list and False when the shape has no
  enumeration; there is no permissive fallback.
- `src/flyology-object_storage-s3-versions.adb:893-918` — `Finish_Version`
  additionally makes `Has_Storage_Class` mandatory, although AWS documents
  `ObjectVersion.StorageClass` as `Required: No`.
- `src/flyology-object_storage-s3-versions.adb:1202-1216` — the server-side
  `Validate_Version` applies the same one-value enumeration, so the in-house
  server can never produce a page that would trip the decoder.
- `src/flyology-object_storage-s3-listings.adb:648-653` — the ListObjects
  codec validates against the fifteen-value enumeration for the same object.
- `src/flyology-object_storage-client-low_level.adb:2226-2229` — the client
  maps the exception to `Invalid_Response "malformed ListObjectVersions
  response"`; no page is returned and there is no way to page past the entry.
- External: AWS S3 API Reference, `API_ObjectVersion.html`, StorageClass
  entry — "Type: String / Valid Values: `STANDARD`". So the one-value
  enumeration is not a botocore artifact; AWS documents it too. The finding
  therefore rests on the pinned MinIO's actual behaviour, not on AWS.

Refutation attempts that failed:

- Looked for a permissive branch in `Valid_Enumeration` — none.
- Looked for a caller that pre-filters or tolerates the exception —
  `Parse_List_Object_Versions` (`:1126-1150`) is the only decode path and
  `Validate`/`Finish_Field` raise before any entry escapes.
- Checked whether the AWS reference contradicts the model — it agrees with it,
  which weakens the "documentation artifact" framing in the discovery. I
  therefore replaced that argument with a live server.
- Checked whether the repository's six-server matrix would have caught it:
  `tests/src/s3_implementation_corpus.adb:3310-3333`
  (`Require_Durable_Version_Routing`) returns immediately unless
  `FLYOLOGY_S3_IMPLEMENTATION` is `flyology-files` or `flyology-sqlite`, and
  it is the only place in that corpus that calls
  `Client_Objects.List_Versions_Page` (`:3708`, `:3780`, `:3805`, `:3993`).
  No MinIO/RustFS/SeaweedFS lane runs ListObjectVersions at all.
- Checked the documented contract: `docs/qualification/list-object-versions.md:90-91`
  ("exact pinned storage class") and
  `tests/corpora/list-object-versions/members.tsv:30` ("Require exactly one
  pinned ObjectVersion storage class value.") state the strictness as
  intended, so this is contract drift the maintainer chose — but the matrix
  row's "no external interoperability claim" is the only place it is
  disclosed to a user, and it does not name storage classes.

**Repro:** `tests/repros/src/repro_s3_domain_a_1.adb`. It decodes a minimal
`ListVersionsResult` with one version, once per storage class, through
`S3.Versions.Parse_List_Object_Versions`; runs the same five classes through
`S3.Listings.Parse_List_Objects` to show the crate accepts them there; then
replays the exact `ListVersionsResult` body the pinned MinIO returned (1157
bytes, verbatim) and asserts both versions decode. Control: the `STANDARD`
case passes.
`tests/repros/src/repro_s3_domain_a_minio_probe.adb` runs the same case live
through `Client.Objects.List_Versions_Page`.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_1`, exit status
**1**):

```
  -- ListObjectVersions <StorageClass>STANDARD</StorageClass>: decoded, versions=1
  ok: ListObjectVersions keeps the STANDARD version
  ok: ListObjectVersions preserves STANDARD
  -- ListObjectVersions <StorageClass>REDUCED_REDUNDANCY</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a REDUCED_REDUNDANCY version
  -- ListObjectVersions <StorageClass>STANDARD_IA</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a STANDARD_IA version
  -- ListObjectVersions <StorageClass>GLACIER</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a GLACIER version
  -- ListObjectVersions <StorageClass>INTELLIGENT_TIERING</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a INTELLIGENT_TIERING version
  -- --- same classes through the ListObjects v1 decoder ---
  --   ListObjects v1 <StorageClass>STANDARD</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>REDUCED_REDUNDANCY</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>STANDARD_IA</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>GLACIER</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>INTELLIGENT_TIERING</StorageClass>: decoded, objects=1
  -- --- verbatim MinIO RELEASE.2025-09-07T16-13-09Z body ---
  -- body bytes 1157
  -- MinIO page REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: the MinIO ListVersionsResult decodes with both versions
BUG REPRODUCED: 5 failed expectation(s)
```

**Description:** `Finish_Field` validates every `<Version>/<StorageClass>`
against the pinned one-value `ObjectVersionStorageClass` enumeration
(`versions.adb:798-805`), so a page in which any single version reports a
different class raises `Malformed_Version_Listing` and the client turns that
into `Invalid_Response` (`client-low_level.adb:2226-2229`): the entire page
is lost, not just the offending entry, and there is no cursor with which to
skip it. The pinned MinIO image used by the repository's own Docker matrix
accepts `x-amz-storage-class: REDUCED_REDUNDANCY` and reports it back inside
`<Version>`, so anyone using `Client.Objects.List_Versions_Page` against
MinIO loses every listing of a bucket containing such an object; on AWS the
same happens to lifecycle-transitioned versions, though AWS's own reference
still documents `STANDARD` as the only valid value. It is fully
deterministic. The same crate accepts all fifteen classes for the same object
through `S3.Listings` (`listings.adb:648-653`), which is the internal
inconsistency. `tests/src/s3_list_object_versions_corpus.adb:335-341` asserts
the wrong behaviour (`Expect_Bad (Page ("...<StorageClass>GLACIER</StorageClass>..."),
"accepted unmodeled storage class")`), and
`tests/corpora/list-object-versions/members.tsv:30` pins it, so a fix must
change the corpus and the vector table too. A fix needs a maintainer
decision: either the decoder accepts any non-empty `StorageClass` text (as
the discovery's failure scenario implies), or it validates against the
fifteen-value `ObjectStorageClass` used by the sibling codec; either choice
widens a publicly observable acceptance domain, and the second also affects
`Validate_Version` on the server side. `Finish_Version`'s requirement that
`StorageClass` be present at all (`:900`) is a second, smaller drift from the
model, which marks the member optional.

---

### S3-DOMAIN-A-2: ListObjects v1 decoder rejects a truncated page that carries `NextMarker` without a delimiter

**Verdict:** CONFIRMED. Every cited location, the qualification sentence, the
oracle-mode plumbing and the server behaviour are as reported.

**Severity:** P0 (discovery said P1; corrected upward). Unlike
ListObjectVersions, `docs/compatibility/s3.md:65` makes an explicit external
interoperability claim for ListObjects v1 — "native/lightweight **six-server
oracle**" — while the crate cannot read the first page of an ordinary
undelimited listing from any of the three pinned third-party servers. That is
an interop-breaking protocol violation of a claimed contract, and the CI lane
that would have caught it is switched off rather than fixed.

Verified by reading:

- `src/flyology-object_storage-s3-listings.adb:1093-1094` —
  `Effective_Delimiter : constant Boolean := Value.Has_Delimiter and then
  US.Length (Value.Delimiter) > 0;` (so an echoed empty `<Delimiter/>` does
  not rescue the case).
- `src/flyology-object_storage-s3-listings.adb:1108-1116` — the raise:
  `Value.Has_Next_Marker /= (Value.Is_Truncated and then Effective_Delimiter)`
  … `raise Malformed_Listing with "inconsistent S3 next marker";`
- `src/flyology-object_storage-s3-listings.adb:1144-1163` —
  `Parse_List_Objects` always calls `Validate`; there is no bypass.
- `docs/qualification/list-objects-v1.md:54-58`, quoted exactly: "Pinned
  RustFS, SeaweedFS, and MinIO each emit a non-model NextMarker on a truncated
  v1 page without a delimiter. Their strict no-delimiter continuation subcase
  is excluded explicitly; the basic v1 path remains enabled, while every
  Flyology backend passes the complete two-page AWS fallback rule."
- `tests/src/s3_implementation_corpus.adb:258-274` —
  `Check_List_Objects_V1_Pagination` returns `False` for the three
  `*-next-marker-without-delimiter` oracle modes and `True` when the variable
  is unset.
- `tests/scripts/test-minio.sh:66-67` sets
  `FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE=minio-2025-next-marker-without-delimiter`;
  `test-rustfs.sh:71` and `test-seaweedfs.sh:78` set the matching values.
- `docs/compatibility/s3.md:65` claims the six-server oracle for ListObjects v1.
- `review/baseline/service-2.json`, `ListObjectsOutput`: no `required` list;
  `NextMarker` is `{"shape": "NextMarker", "documentation": …}` with no
  constraint. Its documentation carries the AWS rule as prose — "This element
  is returned only if you have the `delimiter` request parameter specified.
  If the response does not include the `NextMarker` element and it is
  truncated, you can use the value of the last `Key` element … as the
  `marker` parameter" — i.e. AWS tells a *client* what it may rely on, not
  what a server may send. The AWS API Reference for ListObjects says the same
  and lists no error for it.
- `src/flyology-object_storage-client-objects.adb:403-415` — the client
  already derives the marker from the last key when `NextMarker` is absent,
  so accepting the element costs nothing.

Refutation attempts that failed:

- Checked whether an echoed empty `<Delimiter/>` would satisfy
  `Effective_Delimiter` — it requires non-empty, so no.
- Checked whether the model imposes the rule — it does not.
- Checked whether the Docker matrix already covers it — the three scripts set
  the variable that disables exactly this subcase.
- Checked whether the failure is confined to a later page — no: the *first*
  page of a three-key bucket with `max-keys=1` is already rejected, so
  pagination never starts.

**Repro:** `tests/repros/src/repro_s3_domain_a_2.adb`. Four documents through
`S3.Listings.Parse_List_Objects`: the verbatim MinIO page with `delimiter=/`
(control, must pass), a truncated no-delimiter page without `NextMarker`
(what the Flyology server emits, control), the verbatim MinIO page without a
delimiter, and a minimal synthetic equivalent. The two MinIO bodies differ by
exactly one element.
`tests/repros/src/repro_s3_domain_a_minio_probe.adb` runs the live case
through `Client.Objects.List_V1_Page` against the pinned MinIO.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_2`, exit status
**1**):

```
  -- MinIO max-keys=1 delimiter=/  : decoded, objects=1 truncated=TRUE has_next_marker=TRUE next_marker="k1[minio_cache:v2,return:]"
  ok: MinIO max-keys=1 delimiter=/  : the page keeps its one object
  ok: MinIO max-keys=1 delimiter=/  : the page is truncated
  ok: MinIO max-keys=1 delimiter=/  : the page keeps NextMarker
  ok: MinIO max-keys=1 delimiter=/  : NextMarker text is preserved
  -- Flyology-shaped page, no NextMarker: decoded, objects=1 truncated=TRUE has_next_marker=FALSE next_marker=""
  -- MinIO max-keys=1 no delimiter   : REJECTED, inconsistent S3 next marker
  FAILED: MinIO max-keys=1 no delimiter   : the page is accepted
  -- minimal truncated no-delimiter  : REJECTED, inconsistent S3 next marker
  FAILED: minimal truncated no-delimiter  : the page is accepted
BUG REPRODUCED: 2 failed expectation(s)
```

The live half (probe output above): `List_V1_Page max-keys=1 delimiter=/:
kind PAGE_AVAILABLE status 200` versus `List_V1_Page max-keys=1 no
delimiter: raised Invalid_Response: ListObjects response is invalid or
exceeds the XML limit`.

**Description:** `Listings.Validate` treats "AWS only sends `NextMarker` when
a delimiter was requested" as a *wire* rule and raises `Malformed_Listing`
when a truncated page carries the element without a non-empty `<Delimiter>`
(`listings.adb:1108-1116`). The AWS API Reference states that rule as advice
to the client — the element may be absent, in which case use the last key —
and the pinned botocore model imposes no constraint at all. MinIO, RustFS and
SeaweedFS all emit `NextMarker` unconditionally, so a Flyology client paging
any bucket with more than `max-keys` objects and no delimiter against those
servers loses the very first page: `Parse_List_Objects` raises,
`Decode_List_Objects_Response` converts it to `Invalid_Response`
(`client-low_level.adb:1694-1695`) and `List_V1_Page` never returns. This
affects the common case, not an edge case, and it is deterministic. The
repository already knows: `docs/qualification/list-objects-v1.md:54-58`
records the behaviour and the three Docker scripts set
`FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE` so
`tests/src/s3_implementation_corpus.adb:262-270` skips the subcase, while
`docs/compatibility/s3.md:65` still advertises a six-server oracle for the
operation. The wrong behaviour is also asserted for the final-page variant at
`tests/src/object_storage_test_cases.adb:9597-9599`. A fix is a one-line
relaxation — accept `NextMarker` whenever the page is truncated, keep
rejecting it on a final page — and needs no new public value; the client's
existing fallback at `client-objects.adb:403-415` already handles both
shapes. The oracle-mode entries and the qualification paragraph should be
retired with it.

---

### S3-DOMAIN-A-3: Lifecycle and Notifications serializers reject U+007F that XML 1.0, their own parsers and the Replication serializer accept

**Verdict:** CONFIRMED.

**Severity:** P2 (discovery said P2). It needs an unusual byte in a
configuration value and produces a clean exception before any request is
sent; no data is lost and no server sees a bad document. I found no reachable
caller that would hit it accidentally.

Verified by reading:

- `src/flyology-object_storage-s3-lifecycle.adb:789-790` —
  `if First in 16#20# .. 16#7E# or else First in 16#09# | 16#0A# | 16#0D#`.
- `src/flyology-object_storage-s3-notifications.adb:503-504` — identical range.
- `src/flyology-object_storage-s3-replication.adb:828-829` —
  `if First in 16#20# .. 16#7F# …`, i.e. one byte wider.
- `src/flyology-object_storage-s3-xml.adb:221-226` — the shared escape
  boundary rejects only `Character'Pos (Item) < 32` other than TAB/LF/CR.
- `src/flyology-object_storage-s3-lifecycle.adb:852-863` and
  `-notifications.adb:566-577` — `Add_Text` raises `Malformed_Lifecycle
  "invalid lifecycle XML text"` / `Malformed_Notification "invalid
  bucket-notification XML text"` before escaping.
- `src/flyology-object_storage-s3-lifecycle.adb:770-773` — the comment that
  justifies the range: XML 1.0 text "excludes raw C0 controls other than tab,
  line feed, and carriage return … keeps the serializer from emitting bytes
  the matching parser must reject". U+007F is not a C0 control, and the
  matching parser accepts it, so neither half of the justification applies.

Refutation attempts that failed:

- Checked whether `S3.XML.Escape_Text` would reject DEL anyway, making the
  validator a harmless front-run — it does not.
- Checked whether the crate's key domain excludes DEL so the input could be
  called invalid — `Valid_Object_Key` (`flyology-object_storage.adb:479-490`)
  rejects only NUL.
- Checked whether the three ranges were meant to differ — all three carry the
  same "raw C0 controls" comment.
- Checked whether the parsers really accept DEL — the repro shows all three
  `Parse` calls accepting it (`Parse accepted (139 bytes)` etc.).
- Tested U+0080, an actual C1 control, to see whether the rule is about
  control characters at all — the lifecycle serializer accepts it, so the
  boundary is exactly "one-byte forms above 0x7E", not "controls".

**Repro:** `tests/repros/src/repro_s3_domain_a_3.adb`. For each of Lifecycle,
Notifications and Replication it parses a minimal valid configuration and
hands the parsed value straight back to `Serialize`, once with a plain ASCII
`ID`/`Id` (controls) and once with U+007F. Replication with U+007F is the
key control: identical shape, identical byte, accepted. A final case uses
U+0080 to show the boundary is not about control characters.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_3`, exit status
**1**):

```
  -- DEL byte value 127
  -- lifecycle plain ASCII ID: Parse accepted (140 bytes)
  -- lifecycle plain ASCII ID: Serialize produced 188 bytes
  ok: lifecycle plain ASCII ID: Serialize round-trips Parse
  -- notifications plain ASCII Id: Parse accepted (196 bytes)
  -- notifications plain ASCII Id: Serialize produced 244 bytes
  ok: notifications plain ASCII Id: Serialize round-trips Parse
  -- replication plain ASCII ID: Parse accepted (211 bytes)
  -- replication plain ASCII ID: Serialize produced 259 bytes
  ok: replication plain ASCII ID: Serialize round-trips Parse
  -- replication ID with U+007F: Parse accepted (210 bytes)
  -- replication ID with U+007F: Serialize produced 258 bytes
  ok: replication ID with U+007F: Serialize round-trips Parse
  -- lifecycle ID with U+007F: Parse accepted (139 bytes)
  -- lifecycle ID with U+007F: Serialize REJECTED, invalid lifecycle XML text
  FAILED: lifecycle ID with U+007F: Serialize round-trips Parse
  -- notifications Id with U+007F: Parse accepted (195 bytes)
  -- notifications Id with U+007F: Serialize REJECTED, invalid bucket-notification XML text
  FAILED: notifications Id with U+007F: Serialize round-trips Parse
  -- lifecycle ID with U+0080: Parse accepted (140 bytes)
  -- lifecycle ID with U+0080: Serialize produced 188 bytes
  ok: lifecycle ID with U+0080: Serialize round-trips Parse
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** Two of three otherwise identical UTF-8 validators stop the
single-byte range one code point early, at 0x7E instead of 0x7F, so a
lifecycle or notification configuration containing DEL in any text member
(`ID`, `Prefix`, tag `Key`/`Value`, `Id`, filter values) can be read from a
server but never written back: `Lifecycle.Serialize` raises
`Malformed_Lifecycle` at `lifecycle.adb:854` before the request is built. The
same value survives `Replication.Serialize` and every `XML_Writers`-based
codec, and the same document parses through `Lifecycle.Parse`, so the stated
rationale — matching the parser's acceptance — is not met. Whoever hits it is
a caller round-tripping a configuration whose prefix or tag came from an
object key containing DEL, which `Valid_Object_Key` permits. It is
deterministic. No existing test covers U+007F
(`tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb` and
`s3_bucket_notification_configuration_corpus.adb` exercise C0 controls and
invalid UTF-8 only). The fix is to change `16#7E#` to `16#7F#` in the two
bodies, matching `replication.adb:828`; no public value changes.

---

### S3-DOMAIN-A-4: four response decoders require the botocore output *shape* name as the XML root

**Verdict:** CONFIRMED. The discovery's four AWS root names are correct, and
the "Intelligent-Tiering is not affected" aside is correct too.

**Severity:** P1 (discovery said P1). The decoders cannot read a response
from the only provider that implements the operations, which is a wrong
result on valid input through a reachable path
(`client-low_level.adb:9277`, `:9319`, `:9577`, `:16793`). It is not P0
because `docs/compatibility/s3.md:36-40` ends each of those rows with
"external interoperability are not claimed", so nothing documented is
violated on the client side — although
`docs/qualification/list-directory-buckets.md:14` positively documents the
non-AWS root `<ListDirectoryBucketsOutput/>` as the Flyology server's
contract.

Verified by reading:

- `src/flyology-object_storage-s3-inventory.adb:607-613`,
  `-metrics.adb:468-472`, `-analytics.adb:572-576`,
  `-intelligent_tiering.adb:528-532` — the four `Root_Name` generic actuals,
  each preceded by the comment "Both element names are fixed by the pinned
  Botocore operation/output model."
- `src/flyology-object_storage-s3-paginated_rest_xml_reads.adb:133-136` and
  `:283-286` — exact comparison with `Root_Name` on open and on close.
- `src/flyology-object_storage-s3-generated_list_directory_buckets_xml.adb:9-13`
  — `when Root => return "ListDirectoryBucketsOutput";`.
- `src/flyology-object_storage-s3-strict_xml_codecs.adb:312-315` —
  `if Local_Name /= Element_Name (Root_Element) then raise
  Malformed_Document with "invalid XML root";`.
- `tools/s3_codegen.py:815-816` —
  `root_name = shapes[root_shape].get("locationName", root_shape)`; the same
  rule at `:1932` for request payloads, where every payload member does carry
  a `locationName`, which is why it is right for requests and wrong for
  responses.
- `review/baseline/service-2.json`, dumped with python3: none of
  `ListBucketInventoryConfigurationsOutput`,
  `ListBucketMetricsConfigurationsOutput`,
  `ListBucketAnalyticsConfigurationsOutput`,
  `ListBucketIntelligentTieringConfigurationsOutput`,
  `ListDirectoryBucketsOutput`, `ListBucketsOutput`,
  `ListObjectVersionsOutput` or `ListObjectsOutput` carries a `locationName`,
  a `resultWrapper`, an `xmlNamespace` or a `payload`. **The model is silent
  for every one of them**, including the three whose wire roots the crate
  already hard-codes correctly, so the model cannot be the authority the
  comments claim it is.
- The crate hard-codes the true wire root wherever it differs from the shape
  name for the older operations: `buckets.adb:914` `ListAllMyBucketsResult`,
  `listings.adb:690` `ListBucketResult`, `versions.adb:528`
  `ListVersionsResult`, `metadata_configurations.adb:211`
  `GetBucketMetadataConfigurationResult`, `metadata_tables.adb:295`
  `GetBucketMetadataTableConfigurationResult`.
- `src/flyology-object_storage-server-s3_applications.adb:9599-9608` and
  `:7237` — the in-house server emits the same shape names on both sides, so
  every in-repository round-trip passes.
- External authority (AWS S3 API Reference, "Response Syntax" and the
  "Root level tag" entry in "Response Elements", fetched 2026-09-06):
  - `API_ListBucketInventoryConfigurations.html` → `<ListInventoryConfigurationsResult>`
    ("Root level tag for the ListInventoryConfigurationsResult parameters.");
    the sample response shows
    `<ListInventoryConfigurationsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">`.
  - `API_ListBucketMetricsConfigurations.html` → `<ListMetricsConfigurationsResult>`,
    with the same sample-response confirmation.
  - `API_ListBucketAnalyticsConfigurations.html` → `<ListBucketAnalyticsConfigurationResult>`
    (singular "Configuration"), with the same sample-response confirmation.
  - `API_ListDirectoryBuckets.html` → `<ListAllMyDirectoryBucketsResult>`.
  - `API_ListBucketIntelligentTieringConfigurations.html` →
    `<ListBucketIntelligentTieringConfigurationsOutput>`, i.e. AWS really does
    use the shape name there. The crate is right for that one operation, which
    is presumably why the pattern looked safe.
  I am certain of these four names: each was read from both the Response
  Syntax block and the Response Elements root-level-tag entry, and three of
  the four also appear in a worked sample response on the same page.

Refutation attempts that failed:

- Looked for leniency in the paginated reader — it compares the exact name on
  open (`:134`) and on close (`:284`).
- Looked for a `locationName`, a `resultWrapper`, or a payload member that
  could supply the wire root — the model has none for any of the five, nor
  for the three the crate already handles by hard-coded wire name.
- Looked for a root-name override table in the generator — `s3_codegen.py`
  has only the `locationName`-or-shape-name rule.
- Tried the pinned MinIO: `GET /bucket?inventory`, `?metrics`, `?analytics`
  and `?intelligent-tiering` all answer **501 `NotImplemented`** with an
  `<Error>` root (probe output above), so no pinned third-party server can
  confirm or refute; the AWS reference is the only authority and it is
  unambiguous.
- Checked whether Intelligent-Tiering shares the defect — it does not, and the
  repro uses it as a passing control.

**Repro:** `tests/repros/src/repro_s3_domain_a_4.adb`. It feeds each of
`Inventory.Parse_List`, `Metrics.Parse_List`, `Analytics.Parse_List`,
`Intelligent_Tiering.Parse_List` and `Generated_List_Directory_Buckets_XML.Parse`
two documents that differ only in the root element name: the shape name the
crate pins today (recorded, not asserted) and the root the AWS API Reference
documents (asserted). Intelligent-Tiering, where the two coincide, is the
passing control.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_4`, exit status
**1**):

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

**Description:** The generator's rule "root element = payload shape's
`locationName`, else the shape name" (`tools/s3_codegen.py:815-816`) is right
for request payloads, whose members carry a `locationName`, and wrong for
responses, whose output shapes carry nothing — botocore's rest-xml parser
simply ignores the root element name, so the model has never needed to record
it. Four decoders therefore insist on `…Output` roots that AWS never sends,
and reject the documented ones with `Malformed_Page` →
`Malformed_Inventory`/`Malformed_Metrics`/`Malformed_Analytics`
(`paginated_rest_xml_reads.adb:134`) or `Malformed_Document`
(`strict_xml_codecs.adb:314`). Anyone calling
`ListBucketInventoryConfigurations`, `ListBucketMetricsConfigurations`,
`ListBucketAnalyticsConfigurations` or `ListDirectoryBuckets` against AWS —
the only provider that implements them; the pinned MinIO answers 501 — gets
an invalid-response failure on every 200. It is deterministic and total. No
in-repository test can catch it because the in-house server emits the same
wrong names (`server-s3_applications.adb:9599-9608`, `:7237`) and
`docs/qualification/list-directory-buckets.md:14` documents
`<ListDirectoryBucketsOutput/>` as the server's contract, so a fix must change
the generator's response-root rule, the four decoders, the server emitters
(SERVER area) and that qualification sentence together. It needs a maintainer
decision on where the four wire root names live: they are externally mandated
protocol values with no model source, so under the repository's
decision-authority rule their authority must be recorded at the declaration
— most plausibly an explicit response-root table in `tools/s3_codegen.py`
citing the AWS API Reference, rather than four more hand-written string
literals. Separately, `Generated_List_Directory_Buckets_XML.Parse`
re-raises its inner exception with no message
(`generated_list_directory_buckets_xml.adb:272-274`: `raise
Malformed_Document;`), which is why the repro prints a source location where
the other three print a diagnostic.

---

### S3-DOMAIN-A-5: the server-side PutBucketVersioning body parser is the only request codec that rejects an unqualified root

**Verdict:** CONFIRMED, including the part the discovery could not check: a
stock client really does send the body without `xmlns`, and the Flyology
server really does refuse it.

**Severity:** P0 (discovery said P2 by repository evidence, P0 if a stock
client were confirmed). The condition it named is met. `mc version enable`
— MinIO's own CLI, the default way to turn on versioning against any S3
endpoint — sends `<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>`
with a correct `Content-MD5` and is answered 400 `MalformedXML`. That is an
interop-breaking protocol violation that a stock client's default request
hits, against a row (`docs/compatibility/s3.md:57`) that claims an
"authenticated path-style server" and a "configuration-only six-server
oracle". There is no client-side workaround: `mc` does not offer to add a
namespace.

Verified by reading:

- `src/flyology-object_storage-s3-versioning.adb:41-55` —
  `Start_Element_Details` raises `Malformed_Configuration "bucket versioning
  namespace or attributes are invalid"` when the namespace is not the S3 one
  and `Allow_Empty_Namespace` is False.
- `src/flyology-object_storage-s3-versioning.adb:171-186` — `Parse` passes
  `Allow_Empty_Namespace => False`, `Parse_Response` passes `True`.
- `src/flyology-object_storage-server-s3_applications.adb:10421-10425` — the
  server calls `Versioning.Parse (Document)`, the strict one, after the
  Content-MD5 and checksum gates at `:10395-10420`.
- Sibling request parsers, all lenient:
  `lifecycle.adb:63-85` (`Unqualified` is an accepted `Namespace_Style`),
  `notifications.adb:161-181` (identical), `buckets.adb:531-545`
  (`Parse_Create_Configuration` has no namespace check at all — `grep -n
  Namespace_URI src/flyology-object_storage-s3-buckets.adb` returns nothing).
- `src/flyology-object_storage-s3-versioning.ads:29-32` — the crate's own
  documentation for `Parse_Response`: "AWS responses use the S3 namespace,
  while a few otherwise compatible implementations omit it".
- `review/baseline/service-2.json` — `PutBucketVersioningRequest`'s
  `VersioningConfiguration` payload member carries `xmlNamespace`, which is
  what a serializer emits; nothing marks it a parsing precondition.
- `tests/src/object_storage_test_cases.adb:21868-21871` asserts the rejection
  (`Expect_Malformed ("<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>",
  "namespace-free versioning request accepted")`) and `:21879-21886` asserts
  that `Parse_Response` accepts the same bytes.

Refutation attempts that failed:

- Checked whether the server actually calls the lenient `Parse_Response` for
  requests — it calls `Parse` (`:10425`).
- Checked boto3 1.43.89 and aws-cli 2.36.34 on the wire: both emit the
  namespace (table above), so they are unaffected; the discovery was right
  that botocore-derived SDKs serialize `xmlNamespace`.
- Checked whether `mc` was failing for some other reason — it supplied
  `Content-Md5: 8qj8HSeDu3APPMQZVG06WQ==`, cleared the MD5 and checksum
  gates, and got `MalformedXML`, which is the branch that follows
  `Versioning.Malformed_Configuration`. The same server accepts the same
  request from `mc` if the body carries `xmlns` (the repro's control PUT with
  the namespaced body returns 200).
- Checked whether the strictness is documented as a limitation — the `.ads`
  documents "fail closed" for `Parse` but neither `docs/compatibility/s3.md:57`
  nor `docs/qualification/put-bucket-versioning.md` names the namespace as a
  client requirement.

**Repro:** `tests/repros/src/repro_s3_domain_a_5.adb`. Part 1 runs the four
namespace-free request bodies through their own parsers side by side
(`Lifecycle.Parse`, `Notifications.Parse`,
`Buckets.Parse_Create_Configuration`, `Versioning.Parse_Response` — all
accept; `Versioning.Parse` — rejects). Part 2 sends signed requests through
the in-process application: the namespaced `?versioning` body (control, 200),
a plain `CreateBucket` for a second bucket (control, 200), then the exact
75-byte body `mc` puts on the wire, then `GET ?versioning` on that second
bucket. `tests/repros/src/repro_s3_domain_a_5_live.adb` is the loopback
holder used for the stock-client capture; it asserts nothing.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_5`, exit status
**1**):

```
  -- --- unqualified request bodies through their own parsers ---
  --   codec Lifecycle.Parse: accepted
  --   codec Notifications.Parse: accepted
  --   codec Buckets.Parse_Create_Configuration: accepted
  --   codec Versioning.Parse_Response: accepted
  --   codec Versioning.Parse: REJECTED
  --     malformed bucket versioning XML
  FAILED: Versioning.Parse accepts an unqualified root
  -- --- signed requests through the S3 application ---
  -- CreateBucket /domain-a-5 status 200
  -- PUT /domain-a-5?versioning  (xmlns present) -> 200
  ok: namespaced PutBucketVersioning is accepted
  -- CreateBucket /domain-a-5-other status 200
  ok: the second bucket is created
  -- PUT /domain-a-5-other?versioning (no xmlns) -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-a-5-other?versioning</Resource></Error>
  FAILED: namespace-free PutBucketVersioning is accepted
  -- GET /domain-a-5-other?versioning -> 200 body <?xml version="1.0" encoding="UTF-8"?><VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"></VersioningConfiguration>
  FAILED: the bucket ends up with versioning enabled
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** `Versioning.Parse` is the only request-body codec in the
crate that treats the S3 namespace as a wire precondition
(`versioning.adb:47-54` with `Allow_Empty_Namespace => False`), and the
server calls exactly that one at `server-s3_applications.adb:10425`, so a
`PUT /bucket?versioning` whose body omits `xmlns` gets 400 `MalformedXML`
while the same client's lifecycle, notification and CreateBucket bodies —
whose parsers accept an unqualified root — succeed. MinIO's `mc`
(minio-go v7.0.90) sends precisely that body, so `mc version enable
alias/bucket` cannot enable versioning on a Flyology server at all; the
capture above is the full exchange. It is deterministic and affects every
minio-go-based tool, which is the largest non-AWS S3 client family. The
crate's own `Parse_Response` already documents that "a few otherwise
compatible implementations omit" the namespace
(`versioning.ads:29-32`), so the leniency exists and is simply not wired to
the server path. `tests/src/object_storage_test_cases.adb:21868-21871`
asserts the current rejection and must change with the fix. The minimal fix
is to let the request parser accept an unqualified root the way
`Lifecycle.Parse` and `Notifications.Parse` do — which requires a maintainer
decision only in the sense that it widens the server's accepted request
domain; it introduces no new public value, since `Parse_Document` already
takes `Allow_Empty_Namespace`.

---

### S3-DOMAIN-A-6 (new): the listing query parsers reject `max-keys` above 1000 instead of capping the page

**Verdict:** CONFIRMED. The discovery listed this under "Observations not
counted" as a documented policy value whose interop consequence was "from
memory, unverified". It is neither documented as a wire rule nor consistent
with AWS or MinIO, and a stock client hits it.

**Severity:** P1. A valid request from a stock client is refused, but the
caller can work around it by asking for 1000 or fewer, and the refusal is an
honest 400 with a correct error code — no data is lost. It is not P0 because
no default client invocation hits it: the user must explicitly ask for more
than 1000.

Verified by reading:

- `src/flyology-object_storage-s3-listings.adb:111-118` (v1),
  `:223-230` (v2) and `src/flyology-object_storage-s3-versions.adb:134-141` —
  `if Seen_Max_Keys or else not Number.Valid or else Number.Value >
  Core.Page_Size'Last then raise Malformed_List_Request with "invalid …
  max-keys";`
- `src/flyology-object_storage-s3-core.ads:28` —
  `subtype Page_Size is Natural range 0 .. 1_000;` (a visible subtype, so
  widening it is an interface decision).
- `src/flyology-object_storage-server-s3_applications.adb:10763-10767` and
  the two neighbouring handlers — `Malformed_List_Request` becomes
  400 `InvalidArgument`.
- `docs/compatibility/s3.md:863` mentions "max-keys 0..1000" as a backend page
  contract, not as a request-validity rule, and neither the compatibility
  matrix nor any qualification document says an oversized `max-keys` is
  rejected.
- External: AWS S3 API Reference, `API_ListObjectsV2.html`, URI request
  parameters, `max-keys`: "Sets the maximum number of keys returned in the
  response. By default, the action returns up to 1,000 key names. The response
  might contain fewer keys but will never contain more." The same wording
  appears for ListObjects and ListObjectVersions. The `Errors` section of
  ListObjectsV2 lists only `NoSuchBucket`. The parameter is a ceiling on the
  response, not a constraint on the request.
- Live: the pinned MinIO answers `?max-keys=2000` and
  `?list-type=2&max-keys=2000` with 200, echoing `<MaxKeys>2000</MaxKeys>`
  (probe section above).
- Live: aws-cli 2.36.34 against this same application's loopback listener —
  `aws s3api list-objects-v2 --bucket b --max-keys 2000` →
  `An error occurred (InvalidArgument) … The ListObjectsV2 request is
  invalid`; the identical command against MinIO returns 200.

Refutation attempts that failed:

- Looked for a clamp before the range check — there is none; the comparison
  against `Core.Page_Size'Last` raises directly.
- Looked for a documented policy statement that would make this a
  DOCUMENTED LIMITATION — `docs/compatibility/s3.md:863` describes the
  *backend page* contract, not the accepted request domain, and the two
  listing qualification documents mention 1000 only as the modeled default.
- Checked whether the client is affected too — it is not, in the sense that
  `Low_Level.List_Objects_Parameters.Max_Keys` is `S3.Core.Page_Size`, so a
  Flyology client cannot even express the value; only the server side refuses.

**Repro:** `tests/repros/src/repro_s3_domain_a_6.adb`. Six signed GETs
through the in-process application: `?max-keys=1000`,
`?list-type=2&max-keys=1000` and `?versions&max-keys=1000` (controls, must
pass), then the same three at 2000.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_6`, exit status
**1**):

```
  -- CreateBucket /domain-a-6 status 200
  -- PutObject /domain-a-6/k1 status 200
  -- GET ?max-keys=1000                  -> 200
  ok: GET ?max-keys=1000                  is accepted
  -- GET ?list-type=2&max-keys=1000      -> 200
  ok: GET ?list-type=2&max-keys=1000      is accepted
  -- GET ?versions&max-keys=1000         -> 200
  ok: GET ?versions&max-keys=1000         is accepted
  -- GET ?max-keys=2000                  -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjects request is invalid</Message><Resource>/domain-a-6?max-keys=2000</Resource></Error>
  FAILED: GET ?max-keys=2000                  is accepted
  -- GET ?list-type=2&max-keys=2000      -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjectsV2 request is invalid</Message><Resource>/domain-a-6?list-type=2&amp;max-keys=2000</Resource></Error>
  FAILED: GET ?list-type=2&max-keys=2000      is accepted
  -- GET ?versions&max-keys=2000         -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjectVersions request is invalid</Message><Resource>/domain-a-6?max-keys=2000&amp;versions</Resource></Error>
  FAILED: GET ?versions&max-keys=2000         is accepted
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** The three listing query parsers reuse the *response* page
bound `S3.Core.Page_Size'Last` as a *request* validity bound, so a request
that AWS documents as valid and MinIO answers with 200 is refused with 400
`InvalidArgument` by the Flyology server. Anyone pointing a stock tool at a
Flyology endpoint with an explicit large page hint — `aws s3api
list-objects-v2 --max-keys 2000` is the plainest case, and SDK paginators
that pass a caller-supplied `MaxKeys` through do the same — gets a hard
failure instead of a 1000-key page. It is deterministic and affects the
server only; the typed client cannot express the value. A fix needs a
maintainer decision because `S3.Core.Page_Size` is a visible subtype
(`core.ads:28`): either the three query parsers clamp an oversized `max-keys`
to `Page_Size'Last` and leave the subtype alone — which keeps every response
bound and every backend contract intact and is what AWS's own wording
describes — or the request-side bound becomes a separate, wider type. I
recommend the clamp; it changes no public declaration. No existing test
asserts the current rejection for values above 1000 that I could find in
`tests/src/object_storage_test_cases.adb`, but the change should gain one.

---

### S3-DOMAIN-A-7 (new): `Versions.Validate` rejects every untruncated MinIO ListObjectVersions page, whatever the storage classes

**Verdict:** CONFIRMED. Found while checking S3-DOMAIN-A-1 against a real
server. The discovery raised the neighbouring shape ("`Versions.Validate`
requires a non-empty `NextVersionIdMarker` whenever `NextKeyMarker` is
present … left as an observation") but not this one, which is the mirror case
and is far more reachable.

**Severity:** P1, for the same reason as S3-DOMAIN-A-1: valid input raises
through a reachable path, but `docs/compatibility/s3.md:67` disclaims
external interoperability for ListObjectVersions. In reach it is strictly
worse than A-1 — **100 % of untruncated MinIO pages fail**, not only buckets
containing a non-`STANDARD` version.

Verified by reading:

- `src/flyology-object_storage-s3-versions.adb:1031-1041`:
  ```ada
        elsif Value.Has_Next_Version_ID_Marker /=
          Value.Has_Next_Key_Marker
          or else Value.Is_Truncated /= Value.Has_Next_Key_Marker
          or else
            (Value.Has_Next_Key_Marker
             and then
               (US.Length (Value.Next_Key_Marker) = 0
                or else US.Length (Value.Next_Version_ID_Marker) = 0))
        then
           raise Malformed_Version_Listing with
             "inconsistent ListObjectVersions next markers";
  ```
  The first disjunct alone rejects a page that has one next marker without the
  other, regardless of emptiness or truncation.
- `review/baseline/service-2.json`, `ListObjectVersionsOutput`: no `required`
  list; `NextKeyMarker` and `NextVersionIdMarker` are plain optional strings
  with no cross-member constraint.
- External: AWS S3 API Reference, `API_ListObjectVersions.html`, Response
  Elements — both are documented only as "When the number of responses exceeds
  the value of `MaxKeys`, … specifies the first … not returned"; no rule
  forbids emitting one, or an empty one, on an untruncated page.
- Live: the pinned MinIO's untruncated `?versions` page (probe output above)
  contains `<NextVersionIdMarker></NextVersionIdMarker>` and no
  `<NextKeyMarker>`, so `Has_Next_Version_ID_Marker` is True and
  `Has_Next_Key_Marker` is False. Its *truncated* page carries both, non-empty,
  and is accepted.
- `src/flyology-object_storage-client-low_level.adb:2226-2229` — the same
  `Invalid_Response` mapping as A-1.

Refutation attempts that failed:

- Checked whether the storage-class rule (A-1) was the only reason MinIO fails:
  no. `repro_s3_domain_a_minio_probe` lists a second MinIO bucket holding only
  a default-class (`STANDARD`) object, and
  `List_Versions_Page flyology-review-domain-a-standard` still raises
  `Invalid_Response`. The in-process repro isolates it further: every
  `StorageClass` in `repro_s3_domain_a_7.adb` is `STANDARD`.
- Checked whether an empty element even sets the `Has_` flag — it does; the
  repro's control without the element decodes, the one with it does not.
- Checked whether the six-server matrix would have caught it — as for A-1, the
  only implementation-corpus caller of `List_Versions_Page` is inside
  `Require_Durable_Version_Routing`, which returns unless
  `FLYOLOGY_S3_IMPLEMENTATION` is `flyology-files` or `flyology-sqlite`
  (`tests/src/s3_implementation_corpus.adb:3318-3333`).

**Repro:** `tests/repros/src/repro_s3_domain_a_7.adb`. Three documents
through `S3.Versions.Parse_List_Object_Versions`, all with
`<StorageClass>STANDARD</StorageClass>`: MinIO's untruncated envelope with
the empty `NextVersionIdMarker` removed (control), MinIO's truncated envelope
with both next markers non-empty (control), and MinIO's actual untruncated
envelope.

**Output** (`cd tests/repros && ./run.sh repro_s3_domain_a_7`, exit status
**1**):

```
  -- untruncated, no NextVersionIdMarker: decoded, versions=1 truncated=FALSE
  ok: untruncated, no NextVersionIdMarker: the page keeps its version
  -- truncated, both next markers set   : decoded, versions=1 truncated=TRUE
  ok: truncated, both next markers set   : the page keeps its version
  -- MinIO untruncated, empty NextVersionIdMarker: REJECTED, inconsistent ListObjectVersions next markers
  FAILED: MinIO untruncated, empty NextVersionIdMarker: the page is accepted
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** `Versions.Validate` requires the two next-page markers to be
present together and to match `IsTruncated`
(`versions.adb:1031-1039`), a pairing the pinned model does not express and
the AWS reference does not require. MinIO emits an empty
`<NextVersionIdMarker>` on every `?versions` response, including untruncated
ones, and omits `<NextKeyMarker>` there, so the first disjunct fires and
`Malformed_Version_Listing` is raised for **every** page; the client turns it
into `Invalid_Response` and `Client.Objects.List_Versions_Page` returns
nothing. In practice this means ListObjectVersions is completely unusable
against MinIO through the crate's high-level client, independently of
S3-DOMAIN-A-1, and it is deterministic. Nothing in the repository catches it,
because no third-party lane runs ListObjectVersions at all
(`tests/src/s3_implementation_corpus.adb:3318-3333` gates the only caller on
`FLYOLOGY_S3_IMPLEMENTATION in flyology-files | flyology-sqlite`) and the
in-house server never emits a lone marker. A fix needs a maintainer decision
about how much presence structure the decoder should require of a foreign
server: the narrowest change that admits MinIO is to key the rule on
truncation and non-emptiness — require both markers non-empty when
`IsTruncated` is true, and ignore a present-but-empty marker otherwise — but
that relaxes a documented invariant
(`docs/qualification/list-object-versions.md:87-89`: "truncated pages require
both nonempty next markers, while final pages reject either one"), so the
qualification text and
`tests/src/s3_list_object_versions_corpus.adb` must change with it. Fixing
A-1 without A-7 leaves ListObjectVersions just as broken against MinIO.

---

## Observations from the discovery, assessed

The discovery's "Observations not counted" list, checked against the source
at this commit. Two of them turned out to be findings (S3-DOMAIN-A-6 and, by
way of its neighbour, S3-DOMAIN-A-7); the rest stand as observations.

1. **`max-keys` above 1000 rejected** — promoted to **S3-DOMAIN-A-6**. The
   discovery's "documented policy value" framing does not hold: nothing
   documents it as a request rule, and the interop consequence it guessed at
   is now confirmed with aws-cli and MinIO.
2. **`Listings` requires `Size` on every object entry**
   (`listings.adb:862-868`, `if not Item.Seen_Object_Key or else not
   Item.Seen_Object_Size … raise Malformed_Listing`) while the model and the
   AWS `Object` data type make it optional. Confirmed by reading. Not
   promoted: MinIO always emits `<Size>`, and I found no server that omits
   it. Low interop risk, as the discovery said.
3. **`Versions` rejects unknown elements anywhere in `ListVersionsResult`**
   (`versions.adb:578-580` "unknown ListObjectVersions response field",
   `:632-634` inside `<Version>`) while `Listings` and `Buckets` skip them.
   Confirmed by reading. Not triggered by MinIO, whose page uses only modeled
   elements. It does mean any future server extension inside `<Version>`
   would fail the whole listing, the same total-loss mode as A-1 and A-7.
4. **`Versions.Validate` marker pairing** — the discovery raised the
   "`NextKeyMarker` present, `NextVersionIdMarker` empty" direction; the
   opposite direction is real and reachable, and is **S3-DOMAIN-A-7**. The
   direction the discovery named is not reproducible against MinIO: its
   truncated pages always carry both markers non-empty.
5. **`Replication.Valid_Integer` rejects a leading `+`**
   (`replication.adb:504-505`) while `Lifecycle`, `Bucket_Controls`,
   `Intelligent_Tiering` and `Metadata_Configurations` accept it. Confirmed
   by reading. Harmless: no server emits `+1`.
6. **`Lifecycle` and `Replication` do not enforce `Tag.Key` minimum length 1**
   while `Analytics`, `Metrics` and `Intelligent_Tiering` do. Confirmed by
   reading. Harmless drift.
7. **`Buckets.Parse_Create_Configuration` rejects any `LocationConstraint`
   outside the pinned AWS enumeration** (`buckets.adb:444-446` via
   `Valid_Location_Constraint`, plus the `Location`/`Bucket` pairing rules at
   `:447-467`). Confirmed by reading. Mirrors AWS's own rejection of
   `us-east-1` in a CreateBucketConfiguration, so it is a defensible policy;
   it does refuse self-hosted region names, which is worth a maintainer
   decision but is not a defect against AWS.
8. **`Buckets.Serialize_List_Buckets` emits `<Bucket></Bucket>` for an empty
   `Name`** — server-side only, and the server never stores an empty bucket
   name. Observation.
9. **`Generated_Put_Bucket_ACL_XML` writes `Owner` before
   `AccessControlList`** while the model orders `Grants` first. Confirmed by
   reading the generated body. S3's ACL request parser is order-insensitive
   here; I did not verify that against a server, so it stays an observation
   with the discovery's "from memory" caveat intact.
10. **`ACL.Grantee_Type_Seen` is dead** — set unconditionally at
    `acl.adb:193`, so `not Item.Grantee_Type_Seen` at `:324` can never be
    True. Confirmed by reading. Harmless; the attribute requirement is
    enforced at `:138-144`.
11. **Versioning `Default_Limits` (4 KiB / depth 2 / 3 elements / 64 text
    bytes, `versioning.ads:10-17`) and the 10,000-bucket cap in `Buckets`**
    are documented policy values. Confirmed. Note that the 64-byte text limit
    is comfortably above anything the two modeled members can contain, so it
    is not reachable in practice.
12. **The server-side emitters share the S3-DOMAIN-A-4 root names**
    (`server-s3_applications.adb:9599-9608` for the four configuration
    listings, `:7237` for `<ListDirectoryBucketsOutput/>`). Confirmed by
    reading, and `docs/qualification/list-directory-buckets.md:14` documents
    the wrong root as the server's contract. Cross-reference for the SERVER
    area: a fix must change both sides and that sentence together.

### Additional observations found while verifying

- **Codec diagnostics are erased by the shared XML boundary.**
  `S3.XML.Parse` catches `others` and re-raises as `XML_Error "malformed S3
  XML document"` (`s3-xml.adb:203-207`), so a `Malformed_Version_Listing`
  raised inside a SAX callback — "invalid ObjectVersion storage class",
  "unknown ListObjectVersions response field", "incomplete ObjectVersion
  entry" — reaches the caller as `malformed ListObjectVersions XML: malformed
  S3 XML document` (visible in the S3-DOMAIN-A-1 output). Exceptions raised
  from `Validate`, which runs after parsing, keep their message (S3-DOMAIN-A-2
  and A-7 show that). The result is that the least diagnosable failures are
  exactly the per-entry ones. Wrong diagnostics, P2 by the rubric; not
  promoted to a finding because it is shared infrastructure outside this
  area's codecs.
- **`Generated_List_Directory_Buckets_XML.Parse` re-raises with no message**
  (`:272-274`, `raise Malformed_Document;`), so the caller sees a source
  location instead of a reason. Same class as above.
- **No third-party lane exercises ListObjectVersions.** The only
  implementation-corpus caller of `Client_Objects.List_Versions_Page` is
  inside `Require_Durable_Version_Routing`, which returns immediately unless
  `FLYOLOGY_S3_IMPLEMENTATION` is `flyology-files` or `flyology-sqlite`
  (`tests/src/s3_implementation_corpus.adb:3318-3333`). This is why
  S3-DOMAIN-A-1 and S3-DOMAIN-A-7 have gone unnoticed despite a Docker matrix
  that runs MinIO on every change. It is consistent with
  `docs/compatibility/s3.md:67` ("no external interoperability claim"), so it
  is a coverage gap rather than a false claim — but adding one MinIO
  `?versions` call to that corpus would have caught both findings.

## Findings state

Seven findings, all CONFIRMED, all with a reproduction program that exits 1
on the current sources and includes at least one passing control:
two P0 (S3-DOMAIN-A-2, S3-DOMAIN-A-5), four P1 (A-1, A-4, A-6, A-7) and one
P2 (A-3). Two of the seven are new (A-6, A-7), promoted from the discovery's
uncounted observations after live evidence contradicted the reasons they were
set aside. No finding was refuted; none was left UNVERIFIABLE — the
S3-DOMAIN-A-4 root names the discovery could not confirm were settled from
the AWS S3 API Reference, since the pinned MinIO answers 501 for all four
operations. Every live claim in this report is backed by output pasted above
from the pinned MinIO image, from stock clients captured on the wire, or from
the AWS API Reference quoted verbatim.
