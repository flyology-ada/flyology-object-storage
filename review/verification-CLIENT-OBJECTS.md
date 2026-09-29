# Adversarial verification: CLIENT-OBJECTS (object convenience client)

Scope verified by reading: `src/flyology-object_storage-client-objects.adb`
(`:96-155`, `:385-420`, `:889-1012`, `:2410-2445`, `:2530-2590`, `:2950-2990`,
`:4899-5010`, `:5190-5345`, `:5380-5445`, `:6918-6950`, `:7170-7215`,
`:7416-7435`, `:7660-7685`, `:7950-7975`, `:8040-8060`),
`src/flyology-object_storage-client-objects.ads` (`:436-448`, `:1494-1700`,
`:3204-3300`), `src/flyology-object_storage-client-low_level.ads`
(`:1828-1990`), `src/flyology-object_storage-client.ads` (`:18-50`),
`src/flyology-object_storage-s3-errors.ads` (`:4-32`),
`src/flyology-object_storage-server-s3_applications.adb` (`:4185-4196`,
`:15842-15858`, `:16615-16626`), `docs/architecture/client-objects.md`
(`:55-110`), `docs/qualification/{get-object,head-object,object-tagging}.md`,
`review/baseline/service-2.json` (via `python3`),
`tests/corpora/composable-client/{put-certainty,object-tagging-certainty}.tsv`,
`tests/src/s3_http_socket_corpus.adb` (`:9305-9345`, `:9705-9750`,
`:15085-15262`), `tests/src/s3_get_object_torrent_socket_corpus.adb`
(`:60-125`, `:315-360`, `:640-710`, `:920-955`), the pinned
`flyology_http_0.1.3_eb09a80a` `Read_All` contract
(`src/flyology-http-client.ads:1164-1184`), and `git log -S` on the three
predicates. Harness programs added: `tests/repros/src/repro_client_objects_1.adb`,
`repro_client_objects_2.adb`, `repro_client_objects_3.adb`,
`repro_client_objects_probe.adb`, helper `repro_client_objects_fake.ads/.adb`.
Nothing tracked was modified (`git status --short` shows only untracked
`review/`, `tests/repros/`, `sqlite/tests/repros/`). No Docker script was run;
the real-server evidence is the verbatim capture already recorded in
`review/baseline-rustfs.md`, replayed here through a scripted loopback origin.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| CLIENT-OBJECTS-1 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_client_objects_1.adb` |
| CLIENT-OBJECTS-2 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_client_objects_2.adb` |
| CLIENT-OBJECTS-3 | CONFIRMED (new) | P2 (—) | `tests/repros/src/repro_client_objects_3.adb` |

Probe, no finding: `tests/repros/src/repro_client_objects_probe.adb`
(Content-Length / body-length disagreement on `Get_Whole`) exits 0.

---

### CLIENT-OBJECTS-1: Whole/range GetObject and HeadObject reject a valid 200/206 that omits `x-amz-version-id` after a `versionId=` request

**Verdict:** CONFIRMED.

**Severity:** P0 (discovery said P1). Corrected because the effect is a total
interop break, not a corner of one operation: no stock server can satisfy the
demand for an object in a bucket that never had versioning enabled, which is
the documented meaning of `versionId=null`. `review/baseline-rustfs.md`
section 1 records the verbatim RustFS `200 OK` without the header, section 5
records byte-identical failures against MinIO (`review/baseline/minio.log:96`)
and SeaweedFS (`review/baseline/seaweedfs.log:99`), and the only server that
passes is the in-repo one, which carries a fallback whose sole purpose is to
satisfy this check (`server-s3_applications.adb:4192`, `:16619-16622`). I note
the counter-reading: the rubric's P0 clause names "an interop-breaking protocol
violation that a stock client or server rejects", and here the crate emits
conforming requests and mis-*validates* conforming responses, so a strict
textual reading lands on P1 ("wrong result or unexpected exception on valid
input"). I judge the direction of the rejection immaterial to the harm the
clause exists to capture — the library cannot complete a valid, ordinary read
against any stock implementation — and the repository's own conformance corpus
is red against all three pinned servers for this predicate class.

Verified by reading:

- `src/flyology-object_storage-client-objects.adb:121-137`
  (`Get_Object_Response_Bound`) and `:139-155`
  (`Head_Object_Response_Bound`): both return
  `(Requested_Version'Length = 0 or else US.To_String (Result.Version_ID) =
  Requested_Version) and then (Returned_Payer /= "requester" or else
  Requested_Payer = "requester")`. Read with `sed -n '96,160p'`; the discovery
  quote is exact. An absent header decodes to `Version_ID = ""`, so
  `"" = "null"` is False.
- Callers, all four reached from public entry points:
  `:951-956` (synchronous `Get_Whole` returning `Whole_Get_Outcome`, `raise
  Low_Level.Invalid_Response`), `:2429-2434` (composable whole read →
  `Clear_Buffer` + `Invalid_Read_Result`), `:2551-2556` (composable range read
  → `Clear_Buffer` + `Invalid_Range_Read_Result`), `:2964-2973` (composable
  HeadObject → `Head_Exchange_Failed`, `Corrupt_Or_Invalid_Response`,
  `Response_Invalid`).
- The requested version reaches the predicate verbatim: `:2683`, `:2804`,
  `:3063` assign `Item.Requested_Version_ID` straight from the caller's
  `Version_ID` / `Parameters.Version_ID`. There is no `"null"` special case
  anywhere in the file.
- Pinned model, checked with `python3` over `review/baseline/service-2.json`:
  `GetObjectOutput` and `HeadObjectOutput` both have `required: None`, and
  `VersionId` is `{"shape":"ObjectVersionId","location":"header",
  "locationName":"x-amz-version-id"}`. The header is optional in the model the
  repository pins.
- `src/flyology-object_storage-server-s3_applications.adb:4189-4194` emits
  `x-amz-version-id: null` on HeadObject exactly when the request carried a
  version selector, and `:16620-16622` always emits it on GetObject. That is
  why the memory-server CI gate cannot observe the defect.
- `git log -S 'Get_Object_Response_Bound'` → `f4cabde` (2026-08-30);
  `-S 'Head_Object_Response_Bound'` → `2703ed6` (2026-08-30). Neither diffstat
  touches `tests/src/s3_implementation_corpus.adb` or any `tests/scripts/test-*.sh`;
  both touch only `object_storage_test_cases.adb` and
  `s3_http_socket_corpus.adb`, whose fakes always echo the requested version.

Refutation attempts that failed:

- Looked for a caller-side guard that rewrites or drops `"null"`, or a decoder
  that substitutes the requested value when the header is absent: none. The
  Objects layer copies the caller value verbatim (`:2683`, `:2804`, `:3063`).
- Checked whether the payer clause is what actually fires: it is not. With no
  `x-amz-request-charged` the clause `Returned_Payer /= "requester"` is True,
  so the version clause is the sole cause. The repro's control legs, which
  differ only by the presence of `x-amz-version-id: null`, all pass.
- Checked whether a documented policy makes the strict echo intended:
  `docs/qualification/get-object.md:11-12` and `head-object.md:10-11` do say "a
  successful response must echo it byte-for-byte". That is a repository
  document asserting a requirement the pinned model does not impose and no
  stock server satisfies, so it is part of the defect rather than a defence;
  it must change with the fix. Not treated as DOCUMENTED LIMITATION for that
  reason.
- Checked whether the composable range path fails earlier for another reason
  (status, ETag, Content-Length): the repro's control legs prove those checks
  pass on the same fixtures.

**Repro:** `tests/repros/src/repro_client_objects_1.adb` with helper
`repro_client_objects_fake.ads/.adb`. The helper is a scripted loopback
HTTP/1.1 origin; the in-process S3 application cannot show this finding because
it always emits the header. The program scripts six exchanges: three carrying
the verbatim RustFS never-versioned header set from
`review/baseline-rustfs.md` section 1 probe (b) (`200 OK`, `accept-ranges`,
`content-type`, strong `etag`, `last-modified`, `x-request-id`,
`x-amz-request-id`, `date`, `content-length: 64`, no `x-amz-version-id`), then
three control exchanges identical except for an added
`x-amz-version-id: null`. Against each set it calls `Head_Object` with
`Parameters.Version_ID = "null"`, `Get_Whole` (`Whole_Get_Outcome` overload)
and `Get_Whole` (bounded-destination overload), both with
`Version_ID => "null"`. It asserts that the response is complete, that the
64 body octets survive, and that the decoded `Version_ID` is `""` for the
absent-header legs and `"null"` for the controls.

**Output** (`cd tests/repros && ./run.sh repro_client_objects_1`, exit status **1**):

```
  -- scripted loopback origin on 127.0.0.1:65119
  -- responses carry ETag, Last-Modified, Content-Length and the RustFS request-id headers
  -- --- absent x-amz-version-id (MinIO/RustFS/SeaweedFS/AWS shape) ---
  -- no-header HEAD: Head_Object Kind = HEAD_EXCHANGE_FAILED
  -- no-header HEAD: Failure = CORRUPT_OR_INVALID_RESPONSE, HTTP_Result = RESPONSE_INVALID
  FAILED: no-header HEAD: HeadObject 200 without x-amz-version-id is a complete response
  -- no-header GET: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : GetObject response does not match prepared request
  FAILED: no-header GET: GetObject 200 without x-amz-version-id yields the object bytes
  -- no-header GET/dest: Get_Whole (destination) Kind = WHOLE_GET_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE, destination length 0
  -- no-header GET/dest: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  FAILED: no-header GET/dest: composable whole GetObject keeps the received bytes
  -- --- control: server echoes x-amz-version-id: null ---
  -- control HEAD: Head_Object Kind = HEAD_RESPONSE_AVAILABLE
  -- control HEAD: status 200, Version_ID = "null", ETag = "014842d480b571495a4a0363793f7367"
  ok: control HEAD: HeadObject 200 without x-amz-version-id is a complete response
  ok: control HEAD: HeadObject outcome is Object_Found
  ok: control HEAD: decoded Version_ID is "null"
  -- control GET: Get_Whole (outcome) Kind = WHOLE_OBJECT_READ, status 200
  ok: control GET: GetObject 200 without x-amz-version-id yields the object bytes
  -- control GET: body length 64, Version_ID = "null"
  ok: control GET: whole body round-trips
  ok: control GET: decoded Version_ID is "null"
  -- control GET/dest: Get_Whole (destination) Kind = WHOLE_GET_RESPONSE_AVAILABLE, Failure = NO_FAILURE, destination length 64
  ok: control GET/dest: composable whole GetObject keeps the received bytes
  ok: control GET/dest: GetObject head outcome is Object_Opened
  ok: control GET/dest: destination holds all 64 body octets
  ok: control GET/dest: decoded Version_ID is "null"
  -- request 1: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 2: GET /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 3: GET /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 4: HEAD /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 5: GET /never-versioned/native-object?versionId=null HTTP/1.1
  -- request 6: GET /never-versioned/native-object?versionId=null HTTP/1.1
  ok: the origin served all six scripted exchanges
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** `Get_Object_Response_Bound` and `Head_Object_Response_Bound`
require a successful response to echo the requested `versionId` byte-for-byte.
The pinned botocore model marks `VersionId` optional on both output shapes, and
a bucket that never had versioning enabled answers `?versionId=null` with a
`200`/`206` carrying no `x-amz-version-id` at all — the shape recorded verbatim
from RustFS and, by the identical failure message, from MinIO and SeaweedFS.
The empty decoded value then compares unequal to the requested selector, and a
complete valid read is destroyed: the synchronous `Get_Whole` raises
`Low_Level.Invalid_Response` after the head is decoded, the composable whole
and range reads clear the destination and return `*_Exchange_Failed` with
`Corrupt_Or_Invalid_Response`, and `Head_Object` returns `Head_Exchange_Failed`.
Anyone addressing an object by `versionId=null` — the documented way to name an
object in a never-versioned bucket, and what the repository's own conformance
corpus does at `tests/src/s3_implementation_corpus.adb:1147` — hits it on every
call. It is fully deterministic: the predicate is a pure function of two
strings. Existing tests assert the defective behaviour and must change with the
fix: `tests/src/s3_http_socket_corpus.adb:9333`
(`Require_Invalid_Whole_Get ("scoped-get-version-missing")`, definition
`:9308-9331`) and `:9741` (`Require_Invalid_Head
("scoped-head-version-missing")`, definition `:9711-9739`); the `-mismatch`,
`-duplicate`, `-control` and `-del` cases in the same loops are correct
rejections and must keep failing. `docs/qualification/get-object.md:11-12` and
`head-object.md:10-11` state the strict-echo requirement and must be reworded.
The maintainer decision a fix needs is the contract itself: relaxing the
predicate to "present and different is a mismatch; absent is accepted"
(`review/baseline-rustfs.md` section 7) is the minimal change, but it will
still reject RustFS's suspended-versioning sentinel
`00000000-0000-0000-0000-000000000000` (section 1(c)), so a strict-echo
contract is not viable across real servers even after the relaxation. Whether
the residual mismatch should stay an exception/`Corrupt_Or_Invalid_Response` or
become a typed outcome is a public-API decision, because today the exception
escapes before any outcome exists and no oracle mode can classify it.

---

### CLIENT-OBJECTS-2: Put/Get/DeleteObjectTagging reject every successful response that omits `x-amz-version-id`, even with no version requested

**Verdict:** CONFIRMED.

**Severity:** P0 (discovery said P1). Corrected for the same interop reason as
CLIENT-OBJECTS-1, and this one is stronger on three counts: the demand is
unconditional, so no caller input avoids it; it was observed directly against a
real server (`review/baseline-rustfs.md` section 8 records RustFS's verbatim
`200 OK` to the repository's own `PUT …?tagging` and the resulting
`INVALID_RESPONSE`); and the mutation is actually applied while being reported
as `Object_Tag_Mutation_Outcome_Unknown`, with the documented reconciliation
read (`Get_Tags`) failing identically — so a caller cannot recover the true
state through this API at all. Object tagging is unusable against every stock
server for objects in never-versioned buckets. The same counter-reading as
above applies (the crate is the rejector, not the emitter), and I again judge
it immaterial.

Verified by reading:

- `src/flyology-object_storage-client-objects.adb:7177-7211`
  (`Tagging_Version_ID`). The gate is `if Count > 1 or else (Success and then
  Count /= 1) then raise Low_Level.Invalid_Response with "invalid object
  tagging version header multiplicity";`. `Requested` is consulted only later,
  at `:7203-7204`, for a present-and-different value, so the presence demand is
  independent of what the caller asked for. Read with `sed -n '7170,7215p'`;
  the discovery quote is exact.
- Callers `:7421-7423` (Put, `Success := HTTP_Client.Status (Response) = 200`),
  `:7669-7671` (Get, `= 200`), `:7960-7962` (Delete, `= 204`) — i.e. `Success`
  is True on exactly the success statuses. Each wraps the call in `exception
  when Low_Level.Invalid_Response =>` and produces
  `Normalize_*_Failure (HTTP_Client.Response_Invalid, …)`.
- Every public tagging entry point funnels through those three sites:
  `:7511`, `:7758`, `:8049` assign `Operation.Requested_Version_ID` in the
  `Start_*` procedures that the parameter-record overloads and the
  `Tagging_Outcome` convenience overloads both drive.
- Pinned model, `python3` over `review/baseline/service-2.json`:
  `PutObjectTaggingOutput.required` is `None`,
  `GetObjectTaggingOutput.required` is `['TagSet']` (not `VersionId`),
  `DeleteObjectTaggingOutput.required` is `None`. All three carry `VersionId`
  as an optional `x-amz-version-id` header member.
- `docs/architecture/client-objects.md:99-101`: "All three preserve the
  optional response version ID and structured S3 errors." The code makes it
  mandatory, so a maintained document is contradicted.
- `tests/corpora/composable-client/object-tagging-certainty.tsv` rows 3, 5 and
  7 (`selection = omitted-version`) require `200`/`204` with no S3 code to map
  to `Object_Tag_Mutation_Completed` / `No_Failure` / `reconcile = no`
  ("current-version response proves completion, not target-version identity").
  That is precisely the case the repro exercises, and precisely what the code
  refuses. The maintained certainty corpus therefore contradicts the
  implementation; the socket fake hides it by always echoing the header.
- `src/flyology-object_storage-server-s3_applications.adb:15846-15854`
  (`Set_Version_Header`) always emits the header, falling back to `"null"`.
- `git log -S "invalid object tagging version header multiplicity"` →
  `51c4375` (2026-08-30) and `144d63d`. `51c4375`'s diffstat touches the
  socket corpus, the certainty TSV and the fixture verifier, not
  `tests/src/s3_implementation_corpus.adb` and no live-server script.

Refutation attempts that failed:

- Checked whether `Success` could be False on a real-server success: it is
  literally `Status = 200` (Put/Get) and `Status = 204` (Delete).
- Checked whether the demand is conditional on a requested version: the
  multiplicity test never reads `Requested`. The repro leaves every
  `Parameters.Version_ID` empty and still fails, matching the repository's own
  real-server call `Client_Objects.Put_Tags (… Wanted, Identity, Timeout =>
  30.0)` at `tests/src/s3_implementation_corpus.adb:1629`.
- Checked whether the low-level decoder needs a nonempty version:
  `client-low_level.adb:12379-12383` validates only a nonempty value and the
  spec calls it "Optional selected object version response header", so passing
  `""` through would have been accepted.
- Checked whether `docs/qualification/object-tagging.md:72-74` ("successful
  responses preserve the selected `x-amz-version-id` from that same exchange")
  makes it a DOCUMENTED LIMITATION: it does not say the header must be present,
  and the architecture document and the certainty corpus both say the opposite,
  so the balance of maintained documents is against the code.

**Repro:** `tests/repros/src/repro_client_objects_2.adb`. Eight scripted
exchanges on the same loopback origin: four carrying the verbatim RustFS
tagging reply shape from `review/baseline-rustfs.md` section 8
(`x-request-id`, `x-amz-request-id`, `content-length`, no `x-amz-version-id`;
`200` for Put, `200` + a one-tag `<Tagging>` document for Get, `204` for
Delete), then four controls identical except for `x-amz-version-id: null`.
Against each set it calls `Put_Tags`, `Get_Tags`, `Delete_Tags` (parameter-record
overloads) and the `Tagging_Outcome` convenience `Put_Tags`. No leg requests a
version. It asserts a complete response, `Object_Tag_Mutation_Completed` for
the two mutations, the served tag set for Get, and a decoded `Version_ID` of
`""` (absent-header legs) or `"null"` (controls).

**Output** (`cd tests/repros && ./run.sh repro_client_objects_2`, exit status **1**):

```
  -- scripted loopback origin on 127.0.0.1:65166
  -- no leg requests a version: every Parameters.Version_ID is empty
  -- --- absent x-amz-version-id (RustFS shape, baseline section 8) ---
  -- no-header PUT: Put_Tags Kind = PUT_OBJECT_TAGGING_EXCHANGE_FAILED, Disposition = OBJECT_TAG_MUTATION_OUTCOME_UNKNOWN, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- no-header PUT: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  FAILED: no-header PUT: PutObjectTagging 200 without x-amz-version-id is a complete response
  FAILED: no-header PUT: the applied tag replacement is reported as completed
  -- no-header GET: Get_Tags Kind = GET_OBJECT_TAGGING_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- no-header GET: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  FAILED: no-header GET: GetObjectTagging 200 without x-amz-version-id is a complete response
  -- no-header DELETE: Delete_Tags Kind = DELETE_OBJECT_TAGGING_EXCHANGE_FAILED, Disposition = OBJECT_TAG_MUTATION_OUTCOME_UNKNOWN, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- no-header DELETE: HTTP_Result = RESPONSE_INVALID
  FAILED: no-header DELETE: DeleteObjectTagging 204 without x-amz-version-id is a complete response
  FAILED: no-header DELETE: the applied tag deletion is reported as completed
  -- no-header PUT/convenience: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : PutObjectTagging response is invalid or exceeds the XML limit
  FAILED: no-header PUT/convenience: the convenience overload reports Tags_Replaced
  -- --- control: server echoes x-amz-version-id: null ---
  -- control PUT: Put_Tags Kind = PUT_OBJECT_TAGGING_RESPONSE_AVAILABLE, Disposition = OBJECT_TAG_MUTATION_COMPLETED, Failure = NO_FAILURE
  -- control PUT: status 200, Version_ID = "null"
  ok: control PUT: PutObjectTagging 200 without x-amz-version-id is a complete response
  ok: control PUT: the applied tag replacement is reported as completed
  ok: control PUT: outcome is Tags_Put
  ok: control PUT: decoded Version_ID is "null"
  -- control GET: Get_Tags Kind = GET_OBJECT_TAGGING_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- control GET: status 200, tags 1, Version_ID = "null"
  ok: control GET: GetObjectTagging 200 without x-amz-version-id is a complete response
  ok: control GET: outcome is Tags_Gotten
  ok: control GET: the served tag set is returned
  ok: control GET: decoded Version_ID is "null"
  -- control DELETE: Delete_Tags Kind = DELETE_OBJECT_TAGGING_RESPONSE_AVAILABLE, Disposition = OBJECT_TAG_MUTATION_COMPLETED, Failure = NO_FAILURE
  -- control DELETE: status 204, Version_ID = "null"
  ok: control DELETE: DeleteObjectTagging 204 without x-amz-version-id is a complete response
  ok: control DELETE: the applied tag deletion is reported as completed
  ok: control DELETE: decoded Version_ID is "null"
  -- control PUT/convenience: Put_Tags (Tagging_Outcome) Kind = TAGS_REPLACED, status 200
  ok: control PUT/convenience: the convenience overload reports Tags_Replaced
  -- request 1: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 2: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 3: DELETE /never-versioned/native-object?tagging HTTP/1.1
  -- request 4: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 5: PUT /never-versioned/native-object?tagging HTTP/1.1
  -- request 6: GET /never-versioned/native-object?tagging HTTP/1.1
  -- request 7: DELETE /never-versioned/native-object?tagging HTTP/1.1
  -- request 8: PUT /never-versioned/native-object?tagging HTTP/1.1
  ok: the origin served all eight scripted exchanges
BUG REPRODUCED: 6 failed expectation(s)
```

**Description:** `Tagging_Version_ID` raises `Low_Level.Invalid_Response`
whenever a successful tagging response carries anything other than exactly one
`x-amz-version-id` header. Rejecting a duplicate is right; rejecting an absent
one is not, because the pinned model marks the member optional on all three
output shapes and a never-versioned bucket has no version to report. Because
the demand ignores the requested version, it fires on ordinary tagging calls
that never mention a version. The consequence is worse than a failed read: the
server applied the tag replacement or deletion and answered `200`/`204`, and
the client reports `Object_Tag_Mutation_Outcome_Unknown` with
`Corrupt_Or_Invalid_Response`; the `Tagging_Outcome` convenience overload
re-raises the exception. The documented way out of an unknown mutation is a
reconciling `Get_Tags`, which fails the same way, so through this API the
caller can neither complete nor reconcile. It is deterministic and affects
every caller using object tagging against MinIO, RustFS, SeaweedFS or AWS on a
never-versioned bucket. Existing tests assert the defective behaviour and must
change: `tests/src/s3_http_socket_corpus.adb:15091-15254`
(`Require_Invalid_Version`), invoked for every operation and every invalid kind
at `:15256-15260` — only the `Missing` variant is wrong; `Duplicate`,
`Mismatch`, `Control` and `Delete_Control` are correct rejections. A fix must
also reconcile `docs/qualification/object-tagging.md:72-74` with
`docs/architecture/client-objects.md:100-101`, and needs one maintainer
decision: whether an absent header on a success yields `Version_ID = ""`
(matching the low-level decoder, which already accepts an empty value at
`client-low_level.adb:12379-12383`) or a new explicit "no version reported"
discriminant on the tagging result records.

---

### CLIENT-OBJECTS-3: GetObjectTorrent labels every rejection `No_Failure`, including transient 500/503 responses that every sibling maps to `Unavailable_Or_Retryable`

**Verdict:** CONFIRMED (new; raised from the discovery report's second
uncounted observation, which named only the 404 and 500 inconsistency and did
not test it).

**Severity:** P2. Wrong diagnostics on a reachable path: the value is a
label, callers can still read `Response.Kind`, `Response.Status` and
`Response.Error.Code`, and no bytes or state are lost. It is not P1 because
the response payload itself is correct and complete.

Verified by reading:

- `src/flyology-object_storage-client-objects.adb:5200-5210`
  (`Normalize_Get_Object_Torrent_Response`) returns a fixed
  `Failure => No_Failure` for every decoded outcome, with no reference to
  `Value.Kind`, `Value.Status`, the error `Code`, or `Admission`.
- The sibling in the same file, `Normalize_Get_Object_ACL_Response`
  (`:4899-4940`), classifies: `404` with `NoSuchBucket|NoSuchKey|NoSuchVersion`
  → `Not_Found`; `409 OperationAborted`, `429 SlowDown`, `500 InternalError`,
  `502 BadGateway`, `503 SlowDown`, `504 RequestTimeout` →
  `Unavailable_Or_Retryable`; anything unmodeled →
  `Corrupt_Or_Invalid_Response`. The tagging, legal-hold and retention
  normalizers carry the same table, and
  `tests/corpora/composable-client/put-certainty.tsv` documents it as the
  maintained policy ("caller reconciles before retry").
- `src/flyology-object_storage-client.ads:22-23` calls `Failure_Reason` the
  "stable reason domain shared by composable provider results" and defines
  `No_Failure` as "Successful or conclusively failed condition". A `503
  SlowDown` is neither.
- The torrent path reaches the normalizer only for a decoded complete response
  (`:5405-5422`), so this is not an admission artefact.
- Existing coverage: `tests/src/s3_get_object_torrent_socket_corpus.adb:703`
  asserts `No_Failure` for a `404` rejection, so the 404 label is a deliberate,
  tested choice. Its only `500` scenarios are `malformed-error` (`:341-345`,
  malformed XML) and `error-limit` (`:346-348`, error body over the sink
  limit), both of which take the `Response_Invalid` path instead. **No test
  covers a well-formed retryable rejection on this path**, which is why the
  repro asserts only the `500`/`503` cases and merely reports the `404` label.

Refutation attempts that failed:

- Checked whether `No_Failure` is defensible from its own definition: for a
  `404 NoSuchKey` it arguably is ("conclusively failed"), which is why that leg
  is reported and not asserted. For `500 InternalError` and `503 SlowDown` it
  is not — those are the retryable class every other operation labels
  `Unavailable_Or_Retryable`.
- Checked whether the `.ads` documents a different domain for this operation:
  `src/flyology-object_storage-client-objects.ads:1527` gives the torrent
  result the same "@field Failure Bounded expected failure reason" wording as
  all twenty other result records in the file.
- Checked whether a maintained corpus documents a torrent-specific policy:
  `tests/corpora/composable-client/` has `put-certainty.tsv` and
  `object-tagging-certainty.tsv`; there is no torrent certainty corpus.

**Repro:** `tests/repros/src/repro_client_objects_3.adb`. Five scripted
exchanges: a well-formed `503 Service Unavailable` + `<Code>SlowDown</Code>`
and a `500 Internal Server Error` + `<Code>InternalError</Code>` answered to
`Get_Torrent` (asserted `Unavailable_Or_Retryable`); a `404 NoSuchKey`
answered to `Get_Torrent` (reported only); the *identical* `503 SlowDown`
answered to `Get_ACL` (control, must pass); and a `200 OK` torrent body
(control, must pass).

**Output** (`cd tests/repros && ./run.sh repro_client_objects_3`, exit status **1**):

```
  -- scripted loopback origin on 127.0.0.1:51491
  -- --- GetObjectTorrent: well-formed transient S3 rejections ---
  -- 503 SlowDown torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- 503 SlowDown torrent: response Kind = GET_OBJECT_TORRENT_REJECTED, status 503, code SlowDown, destination length 0
  ok: 503 SlowDown torrent: the rejection is a complete modeled response
  FAILED: 503 SlowDown torrent: Failure is UNAVAILABLE_OR_RETRYABLE, as every sibling normalizer assigns for this status and code
  -- 500 InternalError torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- 500 InternalError torrent: response Kind = GET_OBJECT_TORRENT_REJECTED, status 500, code InternalError, destination length 0
  ok: 500 InternalError torrent: the rejection is a complete modeled response
  FAILED: 500 InternalError torrent: Failure is UNAVAILABLE_OR_RETRYABLE, as every sibling normalizer assigns for this status and code
  -- --- reported only: 404 is asserted as No_Failure by tests/src/s3_get_object_torrent_socket_corpus.adb:703 ---
  -- 404 NoSuchKey torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- 404 NoSuchKey torrent: response Kind = GET_OBJECT_TORRENT_REJECTED, status 404, code NoSuchKey, destination length 0
  -- --- control: the identical 503 answered to GetObjectAcl ---
  -- 503 SlowDown ACL: Get_ACL Kind = GET_OBJECT_ACL_RESPONSE_AVAILABLE, Failure = UNAVAILABLE_OR_RETRYABLE
  -- 503 SlowDown ACL: response Kind = GET_OBJECT_ACL_REJECTED, status 503, code SlowDown
  ok: 503 SlowDown ACL: the rejection is a complete modeled response
  ok: 503 SlowDown ACL: Failure is UNAVAILABLE_OR_RETRYABLE
  -- --- control: a 200 GetObjectTorrent success ---
  -- 200 torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE, destination length 18
  ok: 200 torrent: a 200 torrent read is a complete response
  ok: 200 torrent: a success carries No_Failure
  ok: 200 torrent: outcome is Torrent_Opened
  ok: 200 torrent: destination holds the torrent bytes
  -- request 1: GET /example-bucket/busy-object?torrent HTTP/1.1
  -- request 2: GET /example-bucket/faulted-object?torrent HTTP/1.1
  -- request 3: GET /example-bucket/absent-object?torrent HTTP/1.1
  -- request 4: GET /example-bucket/native-object?acl HTTP/1.1
  -- request 5: GET /example-bucket/native-object?torrent HTTP/1.1
  ok: the origin served all five scripted exchanges
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** `Normalize_Get_Object_Torrent_Response` hardcodes
`Failure => No_Failure` instead of classifying the decoded status and error
code the way every other normalizer in the package does. A caller that routes
retry policy off the shared `Failure_Reason` domain — which
`client.ads:22` presents as exactly that, a stable domain shared by all
composable results — sees a `503 SlowDown` from GetObjectTorrent as carrying no
failure, while the identical response to GetObjectAcl, GetObjectTagging,
GetObjectLegalHold or GetObjectRetention on the same client yields
`Unavailable_Or_Retryable`. The repro demonstrates both sides in one run. It is
deterministic and needs no unusual input; it just needs a server that answers
`?torrent` with a transient error, which the operation's own retry-worthy
statuses make ordinary. `tests/src/s3_get_object_torrent_socket_corpus.adb:703`
asserts `No_Failure` for a `404` and would need review, but nothing asserts the
retryable statuses, so those can be corrected without contradicting a test. The
maintainer decision is how far to align: the minimal fix maps only the six
retryable status/code pairs, and the consistent fix reuses the sibling table
whole, which would also change `404` to `Not_Found` and force the `:703`
assertion to be updated.

---

## Assessment of the discovery report's nine uncounted observations

Each was re-read against the sources; only the second produced a defect
(CLIENT-OBJECTS-3 above).

1. **`Normalize_Put_Response` maps unmodeled rejections to `Outcome_Unknown` /
   `Corrupt_Or_Invalid_Response`.** Agreed, not a defect. The behaviour is the
   maintained policy of `tests/corpora/composable-client/put-certainty.tsv`,
   whose rows for a missing or unmodeled code say exactly this ("unmodeled
   not-found body is not conclusive", "status alone does not prove semantic
   rejection"). The `Failure` label is unflattering for a well-formed S3 error
   whose code simply is not in the Put table, but the conservative disposition
   is deliberate and documented. **DOCUMENTED LIMITATION.**
2. **`Normalize_Get_Object_Torrent_Response` returns `No_Failure` for every
   complete response.** This one is a real defect for the retryable statuses;
   promoted to CLIENT-OBJECTS-3, P2, with a repro. The discovery report's
   reasoning (the enum text admits a conclusive failure) holds for `404` but
   not for `500`/`503`.
3. **Whole/range reads bound the entire body, error XML included, by the
   destination capacity.** Confirmed and documented:
   `src/flyology-object_storage-client-objects.ads:442-443` states "Destination
   capacity is the response body bound". A tight destination therefore reports
   a large `NoSuchKey` error body as `Response_Too_Large` and hides the S3 code.
   Real, but stated in the specification. **DOCUMENTED LIMITATION.**
4. **`Failed_Reason` maps `Response_Body_Too_Large` to `Response_Too_Large`
   while mutation normalizers override it to `Corrupt_Or_Invalid_Response`.**
   Confirmed by reading `:32-46` and the override at
   `Normalize_Get_Object_ACL_Failure:4943-4962` and its peers. Only the
   bounded-buffer reads can receive that HTTP result, so no caller can observe
   the divergence today. Not a defect; a latent inconsistency worth a comment.
5. **`Bind_Response_Range` rejects `Content-Range: bytes a-b/*`.** Agreed, no
   reachable effect: `client-low_level.adb`'s `Valid_Content_Range` rejects the
   `*` total before the Objects layer sees it, and S3 always sends the total.
   Not a defect.
6. **ListObjects v1 marker fallback uses the last `Contents` key when
   `NextMarker` is absent on a delimiter listing.** Re-read `:391-416`. The
   fallback is only reached for a truncated page, prefers `NextMarker`, and
   raises `Invalid_Response` rather than looping when a truncated page has
   neither. S3 requires `NextMarker` whenever a delimiter is used, so the
   fallback is a server-deviation path only. Not a defect at this commit.
7. **`Singleton_Header` treats an empty `x-amz-request-id:` value as invalid.**
   Re-read `:4980-4998` (ACL) and `:6924-6944` (annotation deletion). Both
   return `""` for `Count = 0` — an **absent** header is accepted, so this is
   not another instance of the CLIENT-OBJECTS-1/2 class. Only a present but
   empty value is refused. No observed server sends one. Not a defect.
8. **SigV4 timestamps are taken at `Start_*`.** Confirmed as described. A
   deadline exceeding the SigV4 skew window under a saturated pool would sign
   before admission and fail authentication; that is a timeout/pool policy
   choice, not an incorrectness. Not a defect.
9. **The qualification documents encode the strict-echo requirement.**
   Confirmed verbatim at `docs/qualification/get-object.md:11-12` and
   `head-object.md:10-11`. This is not a separate observation but part of
   CLIENT-OBJECTS-1's remediation: the documents assert a requirement no stock
   server satisfies and must change with the predicate.

---

## Extra check (no finding): `Get_Whole` against a Content-Length / body-length disagreement

`tests/repros/src/repro_client_objects_probe.adb` serves, from the same
loopback origin, a `200 OK` with `content-length: 64` and (a) 100 body octets
and (b) 32 body octets followed by a close, to both `Get_Whole` overloads.
Result: `Get_Whole` fails cleanly in every leg. The over-long body is framed at
the declared 64 octets and the extra bytes are discarded, which is correct
HTTP; the truncated body raises `Flyology.HTTP.Protocol_Error` ("peer closed
before Content-Length was received") from the owned-bytes overload and produces
`Whole_Get_Exchange_Failed` / `Corrupt_Or_Invalid_Response` with a
zero-length destination from the bounded overload. No unhandled exception, no
partial body left readable.

The one contract note: `Protocol_Error` is the documented framing exception of
the underlying `Read_All` (`flyology_http_0.1.3_eb09a80a`
`src/flyology-http-client.ads:1174`), but
`src/flyology-object_storage-client-objects.ads:3231-3233` names only
`Response_Too_Large` and `Low_Level.Invalid_Response` for a "larger or
malformed successful body". Propagating the transport/framing exception class
is consistent with the package's stated model
(`docs/architecture/client-objects.md:66-68`), so I record this as a
documentation gap in the `Get_Whole` prose rather than a finding; the probe
accepts it and passes.

**Output** (`cd tests/repros && ./run.sh repro_client_objects_probe`, exit status **0**):

```
  -- scripted loopback origin on 127.0.0.1:65240
  -- --- Content-Length: 64 with 100 body octets ---
  -- over-long outcome: Kind = WHOLE_OBJECT_READ, status 200
  -- over-long outcome: retained 64 body octets
  ok: over-long outcome: a successful read retains exactly the declared 64 octets
  -- over-long destination: Kind = WHOLE_GET_RESPONSE_AVAILABLE, Failure = NO_FAILURE, destination length 64
  ok: over-long destination: a successful read holds exactly 64 octets
  -- --- Content-Length: 64 with 32 body octets then close ---
  -- truncated outcome: typed exception FLYOLOGY.HTTP.PROTOCOL_ERROR : peer closed before Content-Length was received
  -- truncated destination: Kind = WHOLE_GET_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE, destination length 0
  -- truncated destination: HTTP_Result = RESPONSE_INVALID, phase RECEIVING_RESPONSE_BODY
  ok: truncated destination: a failed read leaves no readable bytes
  -- request 1: GET /framing/mismatched HTTP/1.1
  -- request 2: GET /framing/mismatched HTTP/1.1
  -- request 3: GET /framing/mismatched HTTP/1.1
  -- request 4: GET /framing/mismatched HTTP/1.1
PASS
```

Not covered, and out of this area: whether an over-long body desynchronises a
**reused** connection. The loopback helper closes the peer after each exchange,
and response framing belongs to `flyology_http`, not to `Client.Objects`.

---

## Harness

`tests/repros/run.sh` worked as documented for all four programs; no harness
problem. The programs the previous verifier left were re-read and run
unchanged — each asserts the correct behaviour, so none needed correction; only
`repro_client_objects_3.adb` was added.
