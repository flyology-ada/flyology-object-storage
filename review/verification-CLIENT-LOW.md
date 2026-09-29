# Adversarial verification: CLIENT-LOW (low-level prepared S3 operations, generic REST/XML read and mutation families)

Scope verified by reading:
`src/flyology-object_storage-client-low_level.ads` (150-230, 290-310,
1464-1700, 2630-2800, 6082-6290, 6390-6450, 6760-6800, 7290-7300,
10505-10560), `src/flyology-object_storage-client-low_level.adb`
(163-182, 897-1000, 1791-1975, 2366-2520, 3345-3530, 4856-4872, 5330-5420,
5488-5900, 7100-7180, 7690-7745, 11270-11360, 12400-12580, 12740-12850,
13268-13300, and an enumeration of all 110 `Execute_*` bodies),
`src/flyology-object_storage-s3-errors.adb:100-130`,
`src/flyology-object_storage-s3-tagging.ads`,
`src/flyology-object_storage-s3-deletions.ads:53-67`,
`src/flyology-object_storage-s3-object_reads.adb:75-100`,
`src/flyology-object_storage-client-bounded_rest_xml_reads.adb:95-125`,
`src/flyology-object_storage-client.ads:37-51`,
`src/flyology-object_storage.ads:590-630`,
`src/flyology-object_storage-server-s3_applications.adb` (4188-4194,
15145-15165, 15790-15860, 16330-16360, 17420-17440),
`review/baseline/service-2.json` (`HeadObjectOutput`,
`GetObjectAttributesOutput`, `PutObjectTaggingOutput`,
`GetObjectTaggingOutput`, `DeleteObjectTaggingOutput`,
`CreateSessionRequest`, `MaxKeys`, tagging `responseCode`s),
`docs/compatibility/s3.md` (300-380, 440-460, 720-730),
`tests/src/s3_implementation_corpus.adb:1120-1185`,
`tests/src/s3_http_socket_corpus.adb` (2527-2540, 4325-4400, 15080-15260),
and `review/baseline-rustfs.md` sections 1-8.

Harness programs added: `tests/repros/src/repro_client_low_1.adb`,
`repro_client_low_2.adb`, `repro_client_low_3.adb`, `repro_client_low_4.adb`,
`repro_client_low_5.adb`, `repro_client_low_6.adb`, `repro_client_low_7.adb`,
`repro_client_low_probe.adb`. They reuse the read-only loopback helper
`tests/repros/src/repro_client_objects_fake.ad?` written by the CLIENT-OBJECTS
verifier, unmodified. Nothing tracked was modified; no Docker server was
started (the live-server evidence for CLIENT-LOW-1 and CLIENT-LOW-3 is the
pre-existing capture in `review/baseline-rustfs.md` and
`review/baseline/{minio,seaweedfs}.log`).

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| CLIENT-LOW-1 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_client_low_1.adb` |
| CLIENT-LOW-2 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_client_low_2.adb` |
| CLIENT-LOW-3 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_client_low_3.adb` |
| CLIENT-LOW-4 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_client_low_4.adb` |
| CLIENT-LOW-5 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_client_low_5.adb` |
| CLIENT-LOW-6 | CONFIRMED (new) | P2 (—) | `tests/repros/src/repro_client_low_6.adb` |
| CLIENT-LOW-7 | CONFIRMED (new) | P2 (—) | `tests/repros/src/repro_client_low_7.adb` |

All five discovery findings survived adversarial review. CLIENT-LOW-1, -2 and
-3 share one mechanism — a response header the pinned model marks optional is
required to be present and to echo the request — and I raised all three from
P1 to P0; the rubric reading behind that is stated in full under
CLIENT-LOW-3, together with the alternative under which they stay P1.
CLIENT-LOW-6 and CLIENT-LOW-7 are new defects found while assessing the
discovery's eleven uncounted observations; the remaining observations are
reassessed in the last section, where one (`DeleteObjects` entry binding) is
refuted for the case I could test.

---

### CLIENT-LOW-1: `Execute_Head_Object` raises `Invalid_Response` when a 200 omits `x-amz-version-id`

**Verdict:** CONFIRMED.

**Severity:** P0 (discovery said P1). See the rubric note under CLIENT-LOW-3.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:5641-5658`
  (`Head_Object_Response_Bound`) returns
  `Requested_Version'Length = 0 or else US.To_String (Value.Version_ID) =
  Requested_Version` and-ed with the payer clause. Plain equality, no
  absence tolerance.
- `:5813` builds `Version_ID => H ("x-amz-version-id")`, and `H` is
  `Flyology.HTTP.Client.Header (Response, ...)`, which returns `""` when the
  header is absent. So an absent header decodes to `""`.
- `:5877-5887` (`Execute_Head_Object`): when the decoded outcome is
  `Object_Found` and the predicate is False, it raises
  `Invalid_Response with "HeadObject response does not match prepared
  request"`. The exception escapes the `Head_Object_Outcome` type entirely,
  so no caller can classify it as a per-server deviation.
- `:5153` (`Prepare_Head_Object`) copies `Parameters.Version_ID` into
  `Result.Requested_Head_Object_Version_ID` unconditionally; no validation
  rejects `"null"`.
- `review/baseline/service-2.json`, shape `HeadObjectOutput`:
  `required = []`, and `VersionId` is `{"location": "header",
  "locationName": "x-amz-version-id"}` with no presence requirement. A 200
  without the header does not violate the modeled contract that
  `low_level.ads:300-301` says `Invalid_Response` guards ("Raised when a
  received S3 response violates its modeled contract").
- `tests/src/s3_implementation_corpus.adb:1144-1157` is the live-server
  conformance call: `Parameters.Version_ID := "null"`,
  `Request_Payer := "requester"`, `Checksum_Mode := True`, then
  `Prepare_Head_Object` + `Execute_Head_Object`, asserting `Object_Found`.
- `src/flyology-object_storage-server-s3_applications.adb:4188-4194` is the
  only reason this passes in CI: the in-repo server synthesises
  `x-amz-version-id: null` when the request carried a version selector and
  the stored version is empty.

Refutation attempts that failed:

- **Is the path unreachable?** No. `Prepare_Head_Object` accepts `"null"`
  and the repository's own conformance corpus sends it.
- **Does the model require the header?** No: `HeadObjectOutput.required` is
  `[]` (printed from the pinned `service-2.json`).
- **Is it a documented limitation?** `docs/compatibility/s3.md:449` documents
  the opposite direction — "The server omits the header for unversioned
  publication" — so the repository already treats omission as the correct
  shape. Nothing in `docs/compatibility/s3.md` documents the client demand.
  The only statement of the intent is a private-part comment,
  `src/flyology-object_storage-client-low_level.ads:10533-10535` ("an
  explicit version selector must be echoed by a successful response"), which
  is the design decision under review rather than a maintained limitation.
- **Does the HTTP client synthesise the header?** No: the value comes
  straight from `Flyology.HTTP.Client.Header`.
- **Is the live-server evidence third-party-specific?** No.
  `review/baseline-rustfs.md` section 5 records the byte-identical failure in
  `review/baseline/minio.log:96` and `review/baseline/seaweedfs.log:99`, and
  section 4 records 7/7 deterministic RustFS reproductions.

**Repro:** `tests/repros/src/repro_client_low_1.adb`. A scripted loopback
origin replies to `HEAD /never-versioned/native-object?versionId=null` with
the verbatim RustFS 1.0.0-rc.3 header set from `review/baseline-rustfs.md`
section 1 probe (b) — `200 OK`, `accept-ranges`, `content-length: 64`,
`content-type`, quoted `etag`, `last-modified`, the two request-id headers,
`date`, and **no** `x-amz-version-id`. The program drives
`Low_Level.Prepare_Head_Object` with exactly the corpus parameters
(`Version_ID = "null"`, `Request_Payer = "requester"`,
`Checksum_Mode = True`) and `Low_Level.Execute_Head_Object`, and asserts
`Object_Found` with `Version_ID = ""` and the ETag delivered. The control leg
scripts the same exchange with `x-amz-version-id: null` added.

**Output** (`cd tests/repros && ./run.sh repro_client_low_1`, exit status
**1**):

```
  -- scripted loopback origin on 127.0.0.1:49794
  -- model: HeadObjectOutput required = [], VersionId is an optional x-amz-version-id header (review/baseline/service-2.json)
  -- --- absent x-amz-version-id (RustFS/MinIO/SeaweedFS/AWS shape) ---
  -- no-header: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject response does not match prepared request
  FAILED: no-header: a 200 HeadObject without x-amz-version-id is a modeled success
  -- --- control: the origin echoes x-amz-version-id: null ---
  -- control: Execute_Head_Object Kind = OBJECT_FOUND, status 200
  -- control: ETag = "014842d480b571495a4a0363793f7367", Content-Length = 64, Version_ID = "null"
  ok: control: a 200 HeadObject without x-amz-version-id is a modeled success
  ok: control: decoded Version_ID is "null"
  ok: control: the ETag reaches the caller
  -- request 1: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 2: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  ok: the origin served both scripted exchanges
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** `Head_Object_Response_Bound` compares the decoded
`x-amz-version-id` against the retained request selector with plain string
equality. An absent response header decodes to the empty string, so any
request that carried a `versionId` — including the AWS-documented `null`
selector that addresses an object in a bucket where versioning was never
enabled — makes the predicate False and `Execute_Head_Object` raises
`Invalid_Response` at `low_level.adb:5884` on an otherwise valid 200. The
caller never sees the metadata, and because the failure is an exception
rather than a variant of `Head_Object_Outcome`, it cannot be classified or
tolerated by the caller (this is exactly why no `*_ORACLE_MODE` in the
implementation corpus can express it — see `review/baseline-rustfs.md`
"Verdict"). Anyone doing a version-selected HEAD against MinIO, RustFS,
SeaweedFS or AWS on a never-versioned bucket hits it, deterministically. The
repository's own conformance corpus does exactly this at
`tests/src/s3_implementation_corpus.adb:1144-1157` and is red against all
three pinned reference servers. The check passes in CI only because the
in-repo server manufactures `x-amz-version-id: null`
(`src/flyology-object_storage-server-s3_applications.adb:4188-4194`). Two
maintainer decisions a fix needs: (a) whether the contract becomes "the
response must not *contradict* the selector" (accept an absent header, reject
a present-and-different one) or whether the mismatch becomes a typed outcome
instead of an exception — note that RustFS's versioning-*suspended* sentinel
`00000000-0000-0000-0000-000000000000` (`review/baseline-rustfs.md` section 1
(c)) is present-and-different, so a strict-echo contract is not viable across
real servers even in principle; and (b) whether the server's `null` fallback
should remain once the client stops requiring it. The same predicate shape is
duplicated at `src/flyology-object_storage-client-objects.adb:121-155`
(CLIENT-OBJECTS-1, a separate area) and any fix must cover both.

---

### CLIENT-LOW-2: `Execute_Get_Object_Attributes` raises `Invalid_Response` when a 200 omits `x-amz-version-id`

**Verdict:** CONFIRMED — and it reproduces against the repository's own
in-process S3 application, not only against third-party servers.

**Severity:** P0 (discovery said P1). See the rubric note under CLIENT-LOW-3.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:5371-5372` binds
  `Version_ID : constant String := Singleton_Header ("x-amz-version-id");`
  and `Singleton_Header` returns `""` for `Count = 0` (`:5348-5350`).
- `:5383-5396` raises `Invalid_Response with "GetObjectAttributes response
  does not match request"` when the outcome is `Object_Attributes_Found` and
  `US.Length (Prepared.Requested_Get_Attributes_Version_ID) > 0 and then
  Version_ID /= US.To_String (Prepared.Requested_Get_Attributes_Version_ID)`.
  So `"" /= "null"` trips it.
- `src/flyology-object_storage-server-s3_applications.adb:16347-16352` — the
  in-repo GetObjectAttributes handler emits `x-amz-version-id` **only** when
  `US.Length (Snapshot.Info.Version) > 0`. Unlike the GET/HEAD route at
  `:4188-4194` there is no `null` fallback, so the repository's own server
  cannot satisfy its own client here. My repro confirms this on the wire.
- `review/baseline/service-2.json`, shape `GetObjectAttributesOutput`:
  `required = []`, `VersionId` an optional `x-amz-version-id` header.

Refutation attempts that failed:

- **Does `Prepare_Get_Object_Attributes` reject `"null"`?** No — the repro
  prepares and signs it, and the request reaches the wire as
  `?attributes&versionId=null`.
- **Does the model require the header?** No (`required = []`).
- **Is the in-repo server the reference that makes this third-party-only?**
  The opposite: the in-repo server omits the header for a never-versioned
  object on this route, so the demand is unsatisfiable even against the
  library's own server.
- **Is there existing coverage that pins the behaviour deliberately?**
  `tests/src/s3_implementation_corpus.adb:1675-1861`
  (`Require_Get_Object_Attributes`) never sets `Parameters.Version_ID`, so
  no maintained test reaches the branch in either direction.

**Repro:** `tests/repros/src/repro_client_low_2.adb`. It PUTs one object into
a never-versioned bucket through `Repro_S3_Server.Run`, shows with a raw
signed `GET /bucket/key?attributes&versionId=null` that the server answers
`200` with zero `x-amz-version-id` headers, then starts the same application
on the loopback listener and drives
`Low_Level.Prepare_Get_Object_Attributes` (`Version_ID = "null"`,
`Attributes.Entity_Tag` and `Attributes.Object_Size` selected) plus
`Low_Level.Execute_Get_Object_Attributes`, asserting
`Object_Attributes_Found`. The control leg is the same request with no
version selector.

**Output** (`cd tests/repros && ./run.sh repro_client_low_2`, exit status
**1**):

```
  -- in-process CreateBucket status 200
  ok: setup: CreateBucket is 200
  -- in-process PutObject status 200, x-amz-version-id = ""
  ok: setup: PutObject is 200
  ok: setup: the never-versioned publication returns no version id
  -- raw GET ?attributes&versionId=null -> status 200, x-amz-version-id count 0
  ok: setup: the in-repo server answers the versioned attributes request with 200
  ok: setup: that 200 carries no x-amz-version-id
  -- loopback S3 application on 127.0.0.1:50890
  -- model: GetObjectAttributesOutput required = [], VersionId is an optional x-amz-version-id header (review/baseline/service-2.json)
  -- --- explicit versionId=null against a never-versioned bucket ---
  -- versioned: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : GetObjectAttributes response does not match request
  FAILED: versioned: a 200 GetObjectAttributes without x-amz-version-id is a modeled success
  -- --- control: no version selector, same object ---
  -- control: Execute_Get_Object_Attributes Kind = OBJECT_ATTRIBUTES_FOUND, status 200
  -- control: ETag = 6b344779a83cd6a352fbfcec796f62f2, ObjectSize set = TRUE, Version_ID = ""
  ok: control: a 200 GetObjectAttributes without x-amz-version-id is a modeled success
  ok: control: the requested ETag attribute reaches the caller
  ok: control: ObjectSize is 16
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** Same mechanism as CLIENT-LOW-1 in a different decoder:
`Decode_Get_Object_Attributes_Complete_Response` requires the optional
`x-amz-version-id` response header to equal the requested selector, and an
absent header compares as the empty string. A `GetObjectAttributes` request
that selects `versionId=null` against an object in a never-versioned bucket
therefore turns a valid `200` carrying the requested ETag and ObjectSize into
`Invalid_Response`. Deterministic, and reachable both from
`Execute_Get_Object_Attributes` and from the composable `Client.Objects`
GetObjectAttributes operation, which calls the same decoder. What makes this
one sharper than CLIENT-LOW-1 is that no server can satisfy it: the
repository's own memory-backed S3 application omits the header on this route
(`server-s3_applications.adb:16347-16352`), so the run above needs no Docker
and no third-party server. No maintained test covers the branch
(`tests/src/s3_implementation_corpus.adb:1675-1861` never sets
`Version_ID`), so nothing is currently red — the defect is simply
unexercised. A fix needs the same maintainer decision as CLIENT-LOW-1
(tolerate an absent header versus expose a typed mismatch outcome) and should
be made consistently across all four sites.

---

### CLIENT-LOW-3: `Execute_{Put,Get,Delete}_Object_Tagging` require exactly one `x-amz-version-id` on every success

**Verdict:** CONFIRMED for all three operations.

**Severity:** P0 (discovery said P1).

**Rubric note (applies to CLIENT-LOW-1, -2 and -3).** The rubric's P0 interop
clause is written as "an interop-breaking protocol violation that a stock
client or server rejects". Read literally that describes the library emitting
bytes a stock peer refuses; here the direction is reversed — the library's
client refuses bytes that every stock server legitimately emits. I treat the
clause as being about interoperability failure rather than about which side
does the refusing, because the consequence is the same and worse: the library
cannot complete these operations against any conforming S3 server on the
default bucket state, the pinned model marks every demanded header optional,
and the failure escapes as an exception rather than as a typed outcome, so a
caller cannot even degrade gracefully. `review/baseline-rustfs.md` sections 4
and 5 show CLIENT-LOW-1 red on all three pinned reference servers (7/7 runs,
byte-identical messages in `review/baseline/minio.log:96` and
`review/baseline/seaweedfs.log:99`); CLIENT-LOW-2 is red against the
repository's own server; CLIENT-LOW-3 needs no unusual request parameter at
all. Under the strict literal reading of the clause all three would fall back
to P1 ("unexpected exception on valid input via a reachable path"); I record
that alternative explicitly so the maintainer can re-rank without re-deriving
the facts. CLIENT-LOW-3 is the broadest of the three.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:12463-12489`
  (`Response_Version_ID` nested in `Execute_Object_Tagging`):
  `if Count > 1 or else (Success and then Count /= 1) then raise
  Invalid_Response with "invalid object tagging version header
  multiplicity";`
- `:12527-12529` supplies `Success` as
  `Status = Model.Response_Code (Expected)`. From the pinned model that is
  200 for `PutObjectTagging` and `GetObjectTagging` and 204 for
  `DeleteObjectTagging` (`service-2.json` gives `DeleteObjectTagging` an
  explicit `"responseCode": 204`; the other two default to 200). So the
  demand fires on every success.
- The demand is unconditional on the request: the *separate*, correct check
  at `:12531-12538` (`Requested_Version_ID'Length > 0 and then Version_ID /=
  Requested_Version_ID`) is the one that binds an explicit selector.
  `Response_Version_ID` fires even when no `versionId` was requested.
- `review/baseline/service-2.json`: `PutObjectTaggingOutput.required = []`,
  `DeleteObjectTaggingOutput.required = []`,
  `GetObjectTaggingOutput.required = ["TagSet"]` — `VersionId` is an
  optional `x-amz-version-id` header in all three.
- `src/flyology-object_storage-client-low_level.ads:10538-10543`, the
  spec comment for `Requested_Object_Tagging_Version_ID`: "Empty means the
  request selected the current version, so any returned version remains an
  observation rather than proof." The code contradicts its own spec comment
  by making the header mandatory in exactly that case.
- `review/baseline-rustfs.md` section 8 records RustFS answering
  `PUT /bucket/native-object?tagging` with `200 OK`,
  `content-length: 0` and the two request-id headers only.

Refutation attempts that failed:

- **Is the header required by the model?** No, optional in all three output
  shapes.
- **Does the in-repo server make this third-party-specific?** It does emit
  the header unconditionally — `server-s3_applications.adb:15846-15854`
  (`Set_Version_Header` in the `when Put_Object_Tagging | Get_Object_Tagging
  | ...` branch) defaults to the literal `"null"` when the identity has no
  version — which is precisely why CI is green and real servers are not.
- **Is this deliberate policy pinned by a test?** There is a test, and it
  asserts the wrong behaviour — see below. It is not backed by any
  document: `docs/compatibility/s3.md:364-372` describes the tagging clients
  as validating "bounded responses and version IDs" without stating that a
  version header is mandatory.

**Repro:** `tests/repros/src/repro_client_low_3.adb`. A scripted loopback
origin answers `PUT /never-versioned/native-object?tagging` with `200 OK`,
`content-length: 0` and the RustFS request-id headers (section 8);
`GET .../?tagging` with `200 OK` plus a `<Tagging>` document; and
`DELETE .../?tagging` with `204 No Content`. None carries
`x-amz-version-id`; none of the three prepared requests carries a `versionId`
selector. The program asserts `Tags_Put` / `Tags_Gotten` / `Tags_Deleted`
with `Version_ID = ""`, and that the decoded tag set reaches the caller. The
control legs script the same three exchanges with the header present.

**Output** (`cd tests/repros && ./run.sh repro_client_low_3`, exit status
**1**):

```
  -- scripted loopback origin on 127.0.0.1:51904
  -- no request carries a versionId selector; the model marks VersionId optional in all three tagging output shapes
  -- --- no x-amz-version-id (RustFS/MinIO/SeaweedFS/AWS shape) ---
  -- no-header PUT: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : invalid object tagging version header multiplicity
  FAILED: no-header PUT: a successful tagging response without x-amz-version-id is TAGS_PUT
  -- no-header GET: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : invalid object tagging version header multiplicity
  FAILED: no-header GET: a successful tagging response without x-amz-version-id is TAGS_GOTTEN
  -- no-header DELETE: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : invalid object tagging version header multiplicity
  FAILED: no-header DELETE: a successful tagging response without x-amz-version-id is TAGS_DELETED
  -- --- control: the origin echoes x-amz-version-id ---
  -- control PUT: Kind = TAGS_PUT, status 200
  ok: control PUT: a successful tagging response without x-amz-version-id is TAGS_PUT
  -- control PUT: Version_ID = "opaque-version-1", tags 0
  ok: control PUT: decoded Version_ID is "opaque-version-1"
  -- control GET: Kind = TAGS_GOTTEN, status 200
  ok: control GET: a successful tagging response without x-amz-version-id is TAGS_GOTTEN
  -- control GET: Version_ID = "opaque-version-1", tags 1
  ok: control GET: decoded Version_ID is "opaque-version-1"
  ok: control GET: the decoded tag set reaches the caller
  -- control DELETE: Kind = TAGS_DELETED, status 204
  ok: control DELETE: a successful tagging response without x-amz-version-id is TAGS_DELETED
  -- control DELETE: Version_ID = "opaque-version-1", tags 0
  ok: control DELETE: decoded Version_ID is "opaque-version-1"
  -- request 1: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 2: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 3: DELETE /never-versioned/native-object?tagging HTTP/1.1
  -- request 4: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 5: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 6: DELETE /never-versioned/native-object?tagging HTTP/1.1
  ok: the origin served all six scripted exchanges
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** `Response_Version_ID` conflates two different rules. Header
*multiplicity* (`Count > 1`) is a genuine protocol violation; header
*presence* on a success is not, because the model marks `VersionId` optional
in `PutObjectTaggingOutput`, `GetObjectTaggingOutput` and
`DeleteObjectTaggingOutput`. Because `Success` is just "the status matched
the modeled response code", every 200 PutObjectTagging, every 200
GetObjectTagging and every 204 DeleteObjectTagging against a bucket that
never had versioning enabled raises `Invalid_Response "invalid object tagging
version header multiplicity"` — a misleading message, since the count is
zero, not two. This is the broadest of the three version-echo defects: unlike
CLIENT-LOW-1 and CLIENT-LOW-2 it needs no request parameter, so the plain
`Put_Tags` / `Get_Tags` / `Delete_Tags` call path is affected. For
PutObjectTagging and DeleteObjectTagging the mutation has already been
applied when the exception is raised, and the caller is left unable to
distinguish an applied mutation from a corrupt response. **An existing test
asserts the wrong behaviour:**
`tests/src/s3_http_socket_corpus.adb:15091-15253`
(`Require_Invalid_Version` with `Invalid_Version_Kind = Missing`, fixtures
`tag-put-missing` / `tag-get-missing` / `tag-delete-missing` served at
`:4332-4334`, `:4361-4363`, `:4386-4389`) requires `Invalid_Response`
(synchronous) or `Corrupt_Or_Invalid_Response` with
`Object_Tag_Mutation_Outcome_Unknown` (composable) and raises `"… object
tagging accepted missing version response"` otherwise. Note the `Missing`
case leaves `Selected` empty, so that test pins exactly the no-selector case;
it must be inverted when the code is fixed. It also directly contradicts
`tests/src/s3_implementation_corpus.adb:1617-1673`
(`Require_Object_Tagging`), which expects success from real servers. The
sibling site in the composable layer,
`src/flyology-object_storage-client-objects.adb:7177-7189`
(`Tagging_Version_ID`, CLIENT-OBJECTS area), has the identical predicate and
is what actually failed against RustFS in `review/baseline-rustfs.md`
section 8; any fix must cover both. A maintainer decision is needed on
whether `Version_ID` should stay a plain `Unbounded_String` that is empty
when the server omitted the header (the shape both `Head_Object_Result` and
`Get_Object_Attributes_Result` already use) or become an explicit optional.

---

### CLIENT-LOW-4: bodyless or non-XML 4xx/5xx becomes `Invalid_Response` instead of the typed rejection

**Verdict:** CONFIRMED (discovery confidence Medium; raised to High — it now has
a run).

**Severity:** P2 (discovery said P2; unchanged).

Verified by reading:

- `src/flyology-object_storage-s3-errors.adb:109-127` (`Parse`): an empty or
  non-`<Error>` document raises `Malformed_Error` either from the
  `Seen_Code`/`Seen_Message` check or from `when XML.XML_Error =>`.
- `src/flyology-object_storage-client-low_level.adb:1956-1958` (ListObjectsV2)
  and `:11297-11299` (DeleteObject) map `S3.Errors.Malformed_Error` to
  `Invalid_Response`. The same pattern is at `:1694` (ListObjects), `:2228`,
  `:3340`, `:3884`, `:4369`, `:5331`, `:7731-7733` (PutObject), `:8240`,
  `:10849`, `:12412`, `:12732`, `:12925`, `:13193`, `:13427`, `:14044`,
  `:14426`, `:14779` and every bucket-control GET.
- The contrasting, deliberate treatment for GetObject at `:7137-7166`,
  comment verbatim at `:7159-7163`: "S3 peers and intermediaries may return
  bodyless or non-XML HTTP errors. Preserve the typed rejection and wire
  status instead of turning a valid rejection into a client protocol
  failure."
- `Head_Error` at `:4856-4872` synthesises
  `Code => "HTTP" & <status>`, `Message => <op> & " returned HTTP status " &
  <status>` — the shape the tolerant paths return. HEAD uses it
  unconditionally (`:5670-5674`).
- Every affected outcome type already carries a `Rejected` variant with the
  wire `Status`, so no new public type is needed.
- `src/flyology-object_storage-client-bounded_rest_xml_reads.adb:105-111`
  maps `Low.Invalid_Response` to
  `Normalize_Failure (HTTP_Client.Response_Invalid, ...)`, which surfaces as
  `Corrupt_Or_Invalid_Response`. `Flyology.Object_Storage.Client.Failure_Reason`
  (`src/flyology-object_storage-client.ads:37-51`) has a distinct
  `Unavailable_Or_Retryable` value, so a transient 503 from a proxy is
  classified as corruption rather than as retryable.

Refutation attempts that failed:

- **Is there a wrapper that catches `Malformed_Error` earlier?** No — the
  composable generics catch only `Invalid_Response`.
- **Does the model require an `<Error>` body on every non-2xx?** The model
  describes per-operation `errors` shapes but says nothing about
  intermediaries; that is why this stays P2 rather than P1.
- **Is the strictness uniform, i.e. deliberate?** No: HEAD and GetObject are
  deliberately tolerant, and my control legs confirm both the tolerant HEAD
  path and the well-formed-`<Error>` path work.

**Repro:** `tests/repros/src/repro_client_low_4.adb`. A scripted loopback
origin answers a signed `ListObjectsV2` with `503 Service Unavailable`,
`content-type: text/html` and an HTML body, and a signed `DeleteObject` with
`403 Forbidden`, `content-length: 0`. The program asserts the typed rejection
with the wire status and `Error.Code = "HTTP503"` / `"HTTP403"`. Two control
legs: a bodyless `503` on `HeadObject` (already tolerant) and a `503`
carrying a well-formed `<Error>` document on `ListObjectsV2`.

**Output** (`cd tests/repros && ./run.sh repro_client_low_4`, exit status
**1**):

```
  -- scripted loopback origin on 127.0.0.1:53914
  -- every *_Outcome type already carries a Rejected variant with the wire Status; Head_Error (low_level.adb:4856-4872) synthesises Code = "HTTP<status>" for exactly this case
  -- --- 503 Service Unavailable with a text/html body ---
  -- html 503 ListObjectsV2: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : malformed ListObjectsV2 response
  FAILED: html 503 ListObjectsV2: a non-XML 5xx is a typed rejection carrying the wire status
  -- --- 403 Forbidden with Content-Length: 0 ---
  -- empty 403 DeleteObject: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : malformed DeleteObject response
  FAILED: empty 403 DeleteObject: a bodyless 4xx is a typed rejection carrying the wire status
  -- --- control: HeadObject, the route that already tolerates it ---
  -- control HEAD 503: Kind = HEAD_OBJECT_REJECTED, status 503
  ok: control HEAD 503: HEAD already maps a bodyless 5xx to the typed rejection
  -- control HEAD 503: Error.Code = HTTP503, Message = HeadObject returned HTTP status 503
  ok: control HEAD 503: Error.Code is "HTTP503"
  -- --- control: 503 carrying a well-formed <Error> document ---
  -- modeled 503 ListObjectsV2: Kind = REJECTED, status 503
  ok: modeled 503 ListObjectsV2: a non-XML 5xx is a typed rejection carrying the wire status
  -- modeled 503 ListObjectsV2: Error.Code = SlowDown, Message = Please reduce your request rate
  ok: modeled 503 ListObjectsV2: status is 503
  ok: modeled 503 ListObjectsV2: Error.Code is "SlowDown"
  -- request 1: GET /example-bucket?list-type=2&max-keys=1000 HTTP/1.1
  -- request 2: DELETE /example-bucket/native-object HTTP/1.1
  -- request 3: HEAD /example-bucket/native-object HTTP/1.1
  -- request 4: GET /example-bucket?list-type=2&max-keys=1000 HTTP/1.1
  ok: the origin served all four scripted exchanges
```

**Description:** Roughly twenty decoders convert an
`S3.Errors.Malformed_Error` — which is raised for any non-2xx whose body is
absent, whitespace, HTML, or otherwise not an S3 `<Error>` document — into
`Invalid_Response`, discarding the HTTP status the caller needs. The failure
mode appears when a reverse proxy, load balancer or CDN answers on the
origin's behalf (`503` with an HTML page) or when a peer answers `403` with
no body. A synchronous caller loses the status entirely; a composable caller
receives `Corrupt_Or_Invalid_Response` where `Unavailable_Or_Retryable` is
the correct classification, so a transient outage is treated as a protocol
violation and is not retried. The repository has already made the opposite
decision twice — unconditionally for HEAD (`Head_Error`, `:4856-4872`) and
with an explicit explanatory comment for GetObject (`:7159-7163`) — so this
is an internal inconsistency rather than a missing design decision, and my
two control legs show both tolerant paths working. It stays P2 because a
conforming S3 origin always emits an `<Error>` document, so the trigger is a
non-S3 intermediary rather than ordinary valid input, and the client fails
closed rather than accepting something wrong. No existing test asserts either
behaviour: every 4xx/5xx fixture in `tests/src/s3_http_socket_corpus.adb`
carries a well-formed `<Error>` body. A fix is mechanical (mirror the
GetObject `when S3.Errors.Malformed_Error` handler at each site) and needs no
new public type, since every `*_Outcome` already has a `Rejected` variant
with `Status`; the one maintainer decision is whether the synthesised
`Code = "HTTP<status>"` convention that HEAD and GetObject already use should
become the documented contract for the rest.

---

### CLIENT-LOW-5: `Prepare_Create_Session` rejects an explicit `Bucket_Key_Enabled = False`, and would serialise any set value as `true`

**Verdict:** CONFIRMED, both sub-claims.

**Severity:** P2 (discovery said P2; unchanged).

Verified by reading:

- `src/flyology-object_storage-client-low_level.ads:6401-6416`: "Every
  non-resource member in the pinned CreateSession input. Empty strings
  preserve omission; Bucket_Key_Enabled preserves absent versus explicit
  false." and `@field Bucket_Key_Enabled Presence-preserving bucket-key
  request flag`.
- `src/flyology-object_storage-client-low_level.adb:2429-2432`
  (`Validate_Create_Session_Policy`) includes
  `or else (Bucket_Key_Enabled.Is_Set and then not Bucket_Key_Enabled.Value)`
  in the disjunction that raises.
- `:2472-2482` calls it from `Prepare_Create_Session` and remaps the raise to
  `Invalid_Request with "invalid CreateSession parameters"`.
- `:2494-2502`: when the flag is set, the emitted `Model_Value` is
  `Value => US.To_Unbounded_String ("true")` — the caller's boolean is never
  read. The `true` control leg in the repro shows this is the code path that
  produces the header, so if the policy check were relaxed a `False` would be
  sent as `true`.
- `review/baseline/service-2.json`, `CreateSessionRequest`: `required =
  ["Bucket"]`, and `BucketKeyEnabled` is a boolean bound to the header
  `x-amz-server-side-encryption-bucket-key-enabled` — a boolean member admits
  `false`.

Refutation attempts that failed (one partially succeeded — see below):

- **Is the rejection deliberate S3 Express policy?** Materially, yes,
  plausibly. The pinned model's own documentation string for
  `CreateSessionRequest.BucketKeyEnabled` states that S3 Bucket Keys are
  always enabled for directory-bucket GET and PUT and cannot be disabled. So
  refusing `false` may well be the right wire behaviour. That does **not**
  refute the finding: it relocates it. Either the `.ads` contract at
  `:6401-6404` is wrong and must stop promising that explicit `false` is
  preserved, or the check is wrong. They cannot both stand.
- **Is the `"true"` literal harmless because the check fires first?** Only
  today. It is dead-but-wrong code that silently inverts the caller's value
  the moment the policy is relaxed, and nothing in the file ties the two
  together.
- **Is there existing coverage?** None for an explicit `false`.

**Repro:** `tests/repros/src/repro_client_low_5.adb`. A pure preparation
test, no server: `Prepare_Create_Session` against an HTTPS virtual-hosted
S3 Express origin with `SessionMode = ReadWrite`,
`ServerSideEncryption = aws:kms`, a KMS key ARN, and
`Bucket_Key_Enabled = (Is_Set => True, Value => False)`. It asserts that
preparation succeeds and that the canonical request carries
`x-amz-server-side-encryption-bucket-key-enabled:false`. Control legs: the
flag absent (header must be absent) and explicitly true (header must be
`true`).

**Output** (`cd tests/repros && ./run.sh repro_client_low_5`, exit status
**1**):

```
  -- model: CreateSessionRequest.BucketKeyEnabled is a boolean bound to x-amz-server-side-encryption-bucket-key-enabled (review/baseline/service-2.json)
  -- spec: low_level.ads:6402-6404 -- "Bucket_Key_Enabled preserves absent versus explicit false"
  -- --- explicit false, exactly what the spec says is preserved ---
  -- explicit false: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_REQUEST : invalid CreateSession parameters
  FAILED: explicit false: Prepare_Create_Session accepts the presence-preserving flag
  FAILED: explicit false: the canonical request carries "x-amz-server-side-encryption-bucket-key-enabled:false"
  -- --- control: flag absent ---
  -- absent: prepared, target /?session
  -- absent: signed headers = host;x-amz-content-sha256;x-amz-create-session-mode;x-amz-date;x-amz-server-side-encryption;x-amz-server-side-encryption-aws-kms-key-id
  ok: absent: Prepare_Create_Session accepts the presence-preserving flag
  ok: absent: the canonical request omits x-amz-server-side-encryption-bucket-key-enabled
  -- --- control: explicit true ---
  -- explicit true: prepared, target /?session
  -- explicit true: signed headers = host;x-amz-content-sha256;x-amz-create-session-mode;x-amz-date;x-amz-server-side-encryption;x-amz-server-side-encryption-aws-kms-key-id;x-amz-server-side-encryption-bucket-key-enabled
  ok: explicit true: Prepare_Create_Session accepts the presence-preserving flag
  -- explicit true: looking for "x-amz-server-side-encryption-bucket-key-enabled:true"
  ok: explicit true: the canonical request carries "x-amz-server-side-encryption-bucket-key-enabled:true"
```

**Description:** The published contract for `Create_Session_Parameters` says
the `Bucket_Key_Enabled` flag preserves absent versus explicit `false`;
`Prepare_Create_Session` raises `Invalid_Request` on exactly the explicit
`false` the comment promises, and the serialiser that would have emitted it
hard-codes the string `"true"`. A caller who reads the specification and
sets `(Is_Set => True, Value => False)` gets an exception with a message that
does not say which member was wrong. Deterministic, and no wrong bytes can
reach the wire today because the policy check fires before the serialiser,
which is why this stays P2: it is contract drift plus a latent value
inversion, not a live wire defect. The maintainer decision is a genuine
either/or and should be recorded next to the value per the repository's
convention for externally mandated policy: if S3 Express really forbids
disabling bucket keys, keep the check, delete the `"true"` literal branch in
favour of a serialiser that cannot express `false`, and correct the `.ads`
comment to say that only `true` is accepted; if the model's boolean is to be
honoured, drop the check at `:2429-2432` and serialise
`Boolean'Image`-derived `"true"`/`"false"` at `:2494-2502`. Either way the
`"true"` literal must not survive unchanged.

---

### CLIENT-LOW-6 (new): `Execute_Create_Multipart_Upload` sends a mismatched prepared request before rejecting it

**Verdict:** CONFIRMED. Found while assessing the discovery's observation
"`Execute_Create_Multipart_Upload` (`:3505-3526`) lacks the up-front
`Prepared.Operation` check every other executor has".

**Severity:** P2. It needs an erroneous caller input (a prepared request for
the wrong operation), which is the P2 "needs unusual input" clause; but the
consequence is a real, unintended request executed against the origin, not
merely a wrong diagnostic, so it sits at the top of P2.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:3505-3526`
  (`Execute_Create_Multipart_Upload`): `Response` and `Payload` are elaborated
  in the *declarative part*, so `Flyology.HTTP.Client.Execute` runs before the
  body. There is no `Prepared.Operation` test anywhere in the subprogram.
- `:3345-3355` (`Decode_Create_Multipart_Complete_Response`) is where the
  check lives — after the exchange.
- I enumerated every `function Execute_*` body in the file
  (110 declarations). Each one either performs the
  `Prepared.Operation /= ... ` / `Prepared.Modeled_Operation /= ...` test as
  its first statement or is a thin wrapper delegating to a guarded shared
  executor (`Execute_Bucket_Configuration_Deletion` `:8245`,
  `Execute_Bucket_Control_Get` `:9798`, `Execute_Bucket_Control_Mutation`
  `:10892`, `Execute_Object_Tagging` `:12452`).
  `Execute_Create_Multipart_Upload` is the single standalone body with no
  guard.
- Representative guarded executors for contrast: `Execute_List_Parts`
  `:13268-13279`, `Execute_Head_Object` `:5864-5867`,
  `Execute_Delete_Objects` `:12820-12823`.
- `src/flyology-object_storage-client-low_level.ads:6777-6790` documents
  `Execute_Create_Multipart_Upload` with no `@exception Invalid_Request`,
  while `:6763-6769` documents exactly that exception for the decoder — so
  the specification is silent about the guard rather than sanctioning its
  absence.

Refutation attempts that failed:

- **Is the mismatched request harmless because it is unsigned or malformed?**
  No: `Prepared.Message` is a fully signed, complete request for whatever
  operation it was prepared for. The repro shows the origin receiving
  `DELETE /example-bucket/irreplaceable-object HTTP/1.1`.
- **Does a caller ever legitimately reuse a prepared request across
  executors?** No — `Prepared_Request` is one opaque private type shared by
  all 116 operations, which is precisely why every other executor checks.
- **Is the check redundant because the decoder catches it?** The decoder
  catches it only after the side effect has happened.

**Repro:** `tests/repros/src/repro_client_low_6.adb`. It prepares a genuine
`DeleteObject` for `/example-bucket/irreplaceable-object`, hands it to
`Execute_Create_Multipart_Upload`, and asserts both that `Invalid_Request` is
raised and that the origin exchange counter did not move. Control legs: the
same mismatched request through the guarded `Execute_List_Parts` (must raise
and send nothing) and a genuine `Execute_Delete_Object` (must send exactly
one request), so the program proves the origin is live and the counter works.

**Output** (`cd tests/repros && ./run.sh repro_client_low_6`, exit status
**1**):

```
  -- scripted loopback origin on 127.0.0.1:57109
  -- --- a prepared DeleteObject handed to Execute_Create_Multipart_Upload ---
  -- unguarded: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_REQUEST : prepared request operation mismatch
  ok: unguarded: a mismatched prepared request is rejected as Invalid_Request
  -- unguarded: origin exchanges before 0, after 1
  -- unguarded: the origin received DELETE /example-bucket/irreplaceable-object HTTP/1.1
  FAILED: unguarded: no request reached the origin
  -- --- control: the same mismatched request through a guarded executor (Execute_List_Parts) ---
  -- guarded: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_REQUEST : prepared request operation mismatch
  ok: guarded: a mismatched prepared request is rejected as Invalid_Request
  ok: guarded: no request reached the origin
  -- --- control: a genuine DeleteObject must reach the origin ---
  -- genuine: Kind = OBJECT_DELETED, status 204
  ok: genuine: Execute_Delete_Object succeeds
  ok: genuine: exactly one request reached the origin
  -- origin exchange 1: DELETE /example-bucket/irreplaceable-object HTTP/1.1
  -- origin exchange 2: DELETE /example-bucket/irreplaceable-object HTTP/1.1
```

**Description:** `Prepared_Request` is one private type used for all 116
modeled operations, so "did the caller hand me the right kind of prepared
request?" is checked at the top of every executor in the package — except
`Execute_Create_Multipart_Upload`, whose `Response` and `Payload` objects are
elaborated in the declarative part and therefore perform the whole HTTP
exchange before the decoder's `Invalid_Request` is raised. The
fail-safe invariant the rest of the API establishes — a mismatched prepared
request never touches the network — is broken at exactly one site, and the
worst case is that a mutation the caller did not intend to send at that
moment (a `DeleteObject`, an `AbortMultipartUpload`, a `PutObject` with a
retained payload) is really executed against the origin, with its effect
reported to the caller only as "prepared request operation mismatch". It is
deterministic and needs no server cooperation. The fix is one guard copied
from `Execute_List_Parts` (`:13276-13279`) placed before the declarative
part, plus an `@exception Invalid_Request` line in the `.ads` block at
`:6777-6784` to match every sibling; no new public entity is needed. No
existing test covers a mismatched prepared request for this operation.

---

### CLIENT-LOW-7 (new): `Valid_Model_Scalar` accepts Ada literal integer forms and forwards them verbatim to the wire

**Verdict:** CONFIRMED. Found while assessing the discovery's observation
"`Valid_Model_Scalar` (`:897-999`) validates integer members with
`Long_Long_Integer'Value`".

**Severity:** P2. It needs unusual caller text through the public
`Prepare_Model_Request`, which is the P2 clause; but the request is signed
and sent with no client-side complaint, so the validator silently fails at
the one job it exists for.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:949-965`: for
  `Model.Integer_Shape | Model.Long_Shape` the validator computes
  `Number := Long_Long_Integer'Value (Value);` and then range-checks
  `Number`. Ada's `'Value` accepts underscores, based literals, exponents and
  a leading `+`, so all of those pass.
- The *raw* `Value` text, not `Number`, is what the projector percent-encodes
  into the request target — confirmed on the wire by the repro output.
- `src/flyology-object_storage-client-low_level.ads:193-220` documents
  `Prepare_Model_Request` as the public projector that validates member
  values; it is a public entry point, not an internal helper.
- `review/baseline/service-2.json`: `MaxKeys` is `{"type": "integer"}` with
  no `min`/`max`, so bounds are not what rejects anything here — this is
  purely about lexical form.

Refutation attempts that failed:

- **Is `Prepare_Model_Request` internal?** No, it is declared at
  `low_level.ads:210` in the visible part.
- **Do the typed preparers avoid this?** Yes — they format with `'Image`,
  which is why this is P2 rather than P1. But that only means the defect is
  confined to the generic public entry point, not that it is unreachable.
- **Would a later stage catch it?** No. The repro shows the value reaching
  the signed request target; the first thing that notices is the S3 server,
  which will answer `400 InvalidArgument`.

**Repro:** `tests/repros/src/repro_client_low_7.adb`. It calls
`Prepare_Model_Request (Model.List_Objects_V2_Operation, ...)` with the
`MaxKeys` member set to `"1_000"`, `"16#3E8#"`, `"1E3"` and `"+1000"` and
asserts each is rejected as `Invalid_Request`. Controls: `"500"` must prepare
and appear verbatim in the target, `"not-a-number"` must be rejected — so the
program shows the validator is reached and does reject genuine garbage.

**Output** (`cd tests/repros && ./run.sh repro_client_low_7`, exit status
**1**):

```
  -- MaxKeys is an Integer_Shape ListObjectsV2 member bound to the max-keys query parameter; Valid_Model_Scalar validates it with Long_Long_Integer'Value and forwards the raw text
  -- --- control: a plain decimal value ---
  -- MaxKeys="500" prepared; target = /example-bucket?list-type=2&max-keys=500
  ok: control MaxKeys="500" reaches the wire verbatim
  -- --- control: text that is not a number at all ---
  -- MaxKeys="not-a-number" rejected: invalid modeled request scalar
  ok: MaxKeys="not-a-number" is not a wire-valid decimal integer and must be rejected at preparation
  -- --- Ada literal forms that 'Value accepts and S3 does not ---
  -- MaxKeys="1_000" prepared; target = /example-bucket?list-type=2&max-keys=1_000
  FAILED: MaxKeys="1_000" is not a wire-valid decimal integer and must be rejected at preparation
  -- MaxKeys="16#3E8#" prepared; target = /example-bucket?list-type=2&max-keys=16%233E8%23
  FAILED: MaxKeys="16#3E8#" is not a wire-valid decimal integer and must be rejected at preparation
  -- MaxKeys="1E3" prepared; target = /example-bucket?list-type=2&max-keys=1E3
  FAILED: MaxKeys="1E3" is not a wire-valid decimal integer and must be rejected at preparation
  -- MaxKeys="+1000" prepared; target = /example-bucket?list-type=2&max-keys=%2B1000
  FAILED: MaxKeys="+1000" is not a wire-valid decimal integer and must be rejected at preparation
```

**Description:** `Valid_Model_Scalar` exists so that a modeled member value is
checked before it is signed and sent, but for integer and long shapes it
borrows Ada's own numeric-literal grammar via `Long_Long_Integer'Value`
instead of the S3 wire grammar, and then hands the projector the caller's
original text rather than the parsed number. A caller of the public
`Prepare_Model_Request` who supplies an Ada-shaped literal gets a fully
signed request carrying `max-keys=1_000`, `max-keys=16%233E8%23`,
`max-keys=1E3` or `max-keys=%2B1000` — bytes no S3 server accepts — with no
client-side error at all. The failure surfaces only as a remote
`400 InvalidArgument` whose cause is not visible locally, and because the
malformed text is inside the signed canonical request it cannot be repaired
by an intermediary. Deterministic. The fix is local and needs no maintainer
policy decision: reject any character outside an optional `-` followed by
decimal digits before calling `'Value` (or serialise `Number'Image` trimmed,
instead of the raw text, so that the validated value is the value sent). No
existing test exercises a non-decimal integer member through
`Prepare_Model_Request`.

---

## Discovery observations reassessed

I re-read each of the eleven items the discovery listed under "Observations
not counted" and recorded the current behaviour with
`tests/repros/src/repro_client_low_probe.adb` (a probe, not a finding; it
PASSES, exit 0, and its output is the evidence below). Two became findings
(CLIENT-LOW-6 and CLIENT-LOW-7); one is refuted; the rest stand as
observations, with what would be needed to settle them.

**Probe output** (`cd tests/repros && ./run.sh repro_client_low_probe`, exit
status **0**):

```
  -- === observation: Valid_Model_Scalar accepts Ada literal forms ===
  -- MaxKeys="1_000" accepted, wire target = /probe-bucket?list-type=2&max-keys=1_000
  -- MaxKeys="16#3E8#" accepted, wire target = /probe-bucket?list-type=2&max-keys=16%233E8%23
  -- MaxKeys="1E3" accepted, wire target = /probe-bucket?list-type=2&max-keys=1E3
  -- MaxKeys="+1000" accepted, wire target = /probe-bucket?list-type=2&max-keys=%2B1000
  ok: Valid_Model_Scalar behaviour recorded
  -- === observation: DeleteObjects entry key/version binding ===
  ok: probe: CreateBucket is 200
  ok: probe: both objects published
  -- loopback S3 application on 127.0.0.1:56336
  -- DeleteObjects Kind = OBJECTS_DELETED, status 200
  --   <Deleted> Key=entry-a VersionId=""
  --   <Deleted> Key=entry-b VersionId=""
  ok: probe: unversioned DeleteObjects against the in-repo server is accepted
  -- === observations: HeadObject header demands ===
  -- scripted loopback origin on 127.0.0.1:56338
  -- HEAD 200 without ETag: REJECTED -- invalid HeadObject response headers
  ok: HEAD 200 without ETag: behaviour recorded
  -- HEAD 200 without Last-Modified: REJECTED -- invalid HeadObject response headers
  ok: HEAD 200 without Last-Modified: behaviour recorded
  -- HEAD 200 with Transfer-Encoding: REJECTED -- HeadObject response uses transfer coding
  ok: HEAD 200 with Transfer-Encoding: behaviour recorded
  -- HEAD 200 control (both present): Kind = OBJECT_FOUND
  ok: HEAD 200 control (both present): accepted (probe expectation)
  -- origin served 4 exchanges
PASS
```

| Observation | Disposition |
|---|---|
| Synchronous `Execute_Copy_Object` (`:14865`) and `Execute_Upload_Part_Copy` (`:14506`) may be replayed once by `flyology_http` on a stale reused transport | Stands. I confirmed both send through the retained-request path and that `x-amz-copy-source-if-*` are not in the dependency's mutation-condition set; I did not reproduce it, because it needs a transport-fault injection the harness does not offer. Worst case remains a duplicate copy or extra version, not data loss. Would need a proxy that closes a reused keep-alive connection between request and response. |
| `Valid_Model_Scalar` accepts Ada literal integer forms | **Escalated to CLIENT-LOW-7.** Confirmed on the wire. |
| `Validate_Head_Object_Headers` requires a quoted ETag and a parseable `Last-Modified` on every 200/206 | Stands as an observation, now with the client side pinned down: the probe shows both omissions rejected with `invalid HeadObject response headers`, and `Valid_Response_Entity_Tag` (`:5569-5586`) returns False for `""` while `Object_Reads.Parse_Conditional_Date ("")` is not `Valid`. The pinned model marks `HeadObjectOutput.ETag` and `.LastModified` optional, so the demand exceeds the contract — but I found no server that omits either on a 200/206 HEAD, so I will not call it a defect. Settling it needs a live probe against MinIO/RustFS/SeaweedFS for SSE-KMS, restored-archive and directory-bucket objects. |
| `Validate_Create_Multipart_Headers` (`:3273`) requires `x-amz-checksum-algorithm` and `x-amz-checksum-type` to be both present or both absent | Stands, unverified. Same shape as the previous row; needs live-server evidence. |
| Listing echo comparison under `URL_Encoding`; ListObjectsV2 requires `Has_Delimiter` to match request presence exactly (`:2022-2023`) | Stands, unverified. The real-server corpus never sets `URL_Encoding`, so nothing exercises it. |
| `Valid_Read_Checksum_Headers` rejects a 200 carrying two `x-amz-checksum-*` headers | Stands, unverified. |
| `Decode_Delete_Objects_Complete_Response` (`:12777-12820`) requires an exact key/version pair match for every `<Deleted>`/`<Error>` entry | **Refuted for the reachable case I could test.** The probe drove a real unversioned two-entry `DeleteObjects` through the in-repo server over the loopback listener: it returned `Objects_Deleted` with `<Deleted> Key=entry-a VersionId=""` and `Key=entry-b VersionId=""`, i.e. the server does not echo a `null` version for an entry that carried none, so the binding holds. It would still trip on a server that echoes `<VersionId>null</VersionId>`; no such server is known to me. |
| HEAD responses carrying `Transfer-Encoding` are rejected (`:5757-5759`, `:4935-4937`) | Stands as an observation, client side now pinned: the probe shows `HeadObject response uses transfer coding`. RFC 9110 permits the field on a HEAD response; no known server sends it. |
| CreateSession secret material not zeroized (`:2674-2703`) | DOCUMENTED LIMITATION — the architecture documentation states that allocator memory is not zeroed. Not a finding. |
| `Execute_Create_Multipart_Upload` lacks the up-front `Prepared.Operation` check | **Escalated to CLIENT-LOW-6.** Confirmed: the mismatched request really reaches the origin. |
| `Wire_Query` sends a genuinely empty query value as `name` rather than `name=` | Not a defect as stated: an empty `Version_ID` means the member is omitted entirely, so `versionId=` is not reachable from the typed preparers, and both sides canonicalise `name` identically for SigV4. |
