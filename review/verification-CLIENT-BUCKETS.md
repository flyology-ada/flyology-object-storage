# Adversarial verification: CLIENT-BUCKETS (bucket convenience client)

Scope verified by reading: `src/flyology-object_storage-client-buckets.ads`
(`Failure_Reason` users, `Bucket_Creation_Disposition` `:145-157`,
`Head_Bucket_Result` `:391-422`, `Get_Bucket_Location_Result` `:493-528`,
`Bucket_Tag_Mutation_Disposition` and `Put_Bucket_Tagging_Result` `:600-660`,
`List_Page` `:930-999`, `Create` `:1030-1055`, `Head`/`Get_Location`/`Put_Tags`
`:10115-10320`), `src/flyology-object_storage-client-buckets.adb`
(convenience raise mappers `:60-145`, `List_Page` `:145-222`,
`Normalize_Create_Bucket_Response` `:4096-4151`,
`Normalize_Head_Bucket_Response` `:4796-4822`,
`Normalize_Get_Bucket_Location_Response` `:23460-23499`, bucket-tagging
classifiers `:24417-24500`, shared generated-mutation classifiers
`:26443-26476`, replication exchange-failure sentinel `:8747-8772`),
`src/flyology-object_storage-client-low_level.ad?` (`Head_Bucket_Result` and
`Head_Bucket_Outcome` `.ads:1370-1440`, `Head_Error` `.adb:4856-4872`,
`Decode_Head_Bucket_Response` `.adb:4874-4913`,
`Decode_Head_Bucket_Complete_Response` `.adb:4915-4967`,
`Decode_Get_Bucket_Location_Response` `.adb:4483-4510`, ListBuckets prefix
binding `.adb:4130-4176`, PutBucketTagging preparation `.adb:200-245`),
`src/flyology-object_storage-client.ads:22-52`,
`src/flyology-object_storage-server-authentication.adb:180-226`,
`src/flyology-object_storage-server-s3_applications.adb:1860-1912`,
`src/flyology-object_storage-tags.ads`, the pinned model
`review/baseline/service-2.json` (`ListBucketsOutput`, `HeadBucketOutput`),
`docs/compatibility/s3.md:8-20,487-506`,
`docs/qualification/list-buckets.md:1-40`,
`docs/qualification/head-bucket-composable.md`,
`docs/architecture/client-buckets.md:68-75`,
`tests/src/flyology-object_storage-client-buckets-testing.adb` (the 401 rows),
and `~/.local/share/alire/releases/flyology_0.1.1_*/src/flyology-bytes.ads:91-93`
for `Clear`.

Harness programs added: `tests/repros/src/repro_client_buckets_1.adb`,
`tests/repros/src/repro_client_buckets_2.adb`,
`tests/repros/src/repro_client_buckets_3.adb`,
`tests/repros/src/repro_client_buckets_probe.adb` (needs a MinIO container),
and the helper `tests/repros/src/repro_client_buckets_fake.ads/.adb` (a private
copy of the CLIENT-OBJECTS scripted-origin pattern; the CLIENT-OBJECTS unit was
read but not modified). Nothing tracked was modified; `git status --short`
shows only `review/`, `tests/repros/` and `sqlite/tests/repros/`.

Docker: one MinIO container was started **by hand** from the image pinned in
`tests/scripts/test-minio.sh` (`--publish 127.0.0.1::9000`, health wait,
container `flyology-review-buckets-460`) and stopped afterwards. No repository
test script, no `alr`, no `gprbuild` was invoked directly; every build and run
went through `tests/repros/run.sh`.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| CLIENT-BUCKETS-1 | CONFIRMED | P1 (P2) | `tests/repros/src/repro_client_buckets_1.adb` |
| CLIENT-BUCKETS-2 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_client_buckets_2.adb` |
| CLIENT-BUCKETS-3 | DOCUMENTED LIMITATION | P2 (new; discovery observation 1, unsettled) | `tests/repros/src/repro_client_buckets_3.adb` |

---

## MinIO probe

Image: `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`,
the digest pinned in `tests/scripts/test-minio.sh`.

Release string (`docker run --rm <image> --version`):

```
minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)
Runtime: go1.24.6 linux/arm64
License: GNU AGPLv3 - https://www.gnu.org/licenses/agpl-3.0.html
Copyright: 2015-2025 MinIO, Inc.
```

Both authentication-failure captures were taken with the crate's own SigV4
(`Flyology.Object_Storage.S3.SigV4.Sign`) over a raw loopback socket from
`tests/repros/src/repro_client_buckets_probe.adb`; the request was
`GET /flyology-review-buckets?location` in both cases.

**(a) Unknown access key** (correct secret, credential names a key MinIO does
not have):

```
HTTP/1.1 403 Forbidden\r\nAccept-Ranges: bytes\r\nContent-Length: 378\r\nContent-Type: application/xml\r\nServer: MinIO\r\n...
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>InvalidAccessKeyId</Code><Message>The Access Key Id you provided does not exist in our records.</Message><BucketName>flyology-review-buckets</BucketName><Resource>/flyology-review-buckets</Resource><RequestId>18D2F58C3E2DF40C</RequestId><HostId>dd9025ba...</HostId></Error>
```

**(b) Wrong secret** (correct access key, signature computed with a different
secret):

```
HTTP/1.1 403 Forbidden\r\nAccept-Ranges: bytes\r\nContent-Length: 433\r\nContent-Type: application/xml\r\nServer: MinIO\r\n...
<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match the signature you provided. Check your key and signing method.</Message><BucketName>flyology-review-buckets</BucketName><Resource>/flyology-review-buckets</Resource><RequestId>18D2F58C3E47F132</RequestId><HostId>dd9025ba...</HostId></Error>
```

Neither status is 401; MinIO emitted no 401 on any probed path. A bodyless
`HEAD /flyology-review-buckets` with the unknown key answers `403 Forbidden`
with `Content-Length: 0` and `X-Minio-Error-Code: InvalidAccessKeyId` (a
non-AWS header the client does not read).

**This crate's own server** answers both cases the same way, and also not with
401: `Verify_Request` maps an unknown key and a bad signature alike to
`Credential_Rejected`
(`src/flyology-object_storage-server-authentication.adb:213-216`) and
`Send_Authentication_Error` emits `403 SignatureDoesNotMatch`
(`src/flyology-object_storage-server-s3_applications.adb:1906-1909`). The first
leg of `repro_client_buckets_1` shows this in process:

```
  -- own server, unknown access key: HTTP 403 <Code> = "SignatureDoesNotMatch"
  -- own server, wrong signature: HTTP 403 <Code> = "SignatureDoesNotMatch"
```

Two further MinIO facts settled here, both used below:

- HeadBucket is **not** redirected. A HeadBucket signed with an `eu-west-1`
  credential scope against a bucket MinIO reports as `us-east-1`
  (`GetBucketLocation` returns an empty `LocationConstraint`) answers
  `200 OK` with **no** `x-amz-bucket-region` header at all. The convenience
  `Head` then reports `Region = "eu-west-1"` — the documented signing-region
  fallback (`client-buckets.ads:10174-10176`) misreporting a us-east-1 bucket.
- `GET /?max-buckets=10&prefix=flyology` answers `200 OK` with a
  `ListAllMyBucketsResult` that carries **no** `<Prefix>` element.

---

### CLIENT-BUCKETS-1: authentication rejections are recognised only at HTTP 401, so every stock server's `403 InvalidAccessKeyId` / `403 SignatureDoesNotMatch` becomes `Corrupt_Or_Invalid_Response` and, for mutations, `..._Outcome_Unknown`

**Verdict:** CONFIRMED.

**Severity:** P1 (discovery said P2 because the misclassification is
"conservative, therefore safe"). Corrected to P1 because the rubric's P1 clause
"wrong result on valid input via a reachable path, or a documented contract
violated" is met on all three counts: the path is the most common operator
error, the input is a well-formed stock rejection, and two documented public
enum meanings are contradicted —
`Corrupt_Or_Invalid_Response  Response was not conclusive or valid`
(`client.ads:35`) is reported for a response that is both conclusive and valid,
and `Bucket_Creation_Outcome_Unknown  Creation must be reconciled`
(`client-buckets.ads:150`) instructs the caller to perform a HeadBucket
reconciliation for a request the server refused before touching any state. The
"conservative" argument would hold if the wrong value were only advisory; it is
the documented decision input for whether a mutation must be reconciled before
retry, and it is wrong for **every** bucket mutation against AWS, MinIO **and
this crate's own server**.

Verified by reading:

- `src/flyology-object_storage-client-buckets.adb:4109` — the only 401 pairing
  in `Normalize_Create_Bucket_Response`'s `Conclusive_Rejection`:
  `or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")`, and
  `:4110` the only 403 pairing, `Code = "AccessDenied"`.
- `:4123-4131` — `Failure` is `Authentication_Failed` only for
  `(401, InvalidAccessKeyId)`, `Authorization_Failed` only for
  `(403, AccessDenied)`, otherwise `Invalid_Request` /
  `Unavailable_Or_Retryable` / `Corrupt_Or_Invalid_Response`.
- `:4136-4143` — `Disposition` is `Bucket_Definitely_Not_Created` only when
  `Conclusive_Rejection`, else `Bucket_Creation_Outcome_Unknown`.
- `:26443-26453` (`Conclusive_Generated_Mutation_Rejection`) and `:26464-26476`
  (`Generated_Mutation_Response_Failure`) — the shared classifier for the
  generated bucket mutations repeats the same two pairs.
- `:24417-24450` (`Conclusive_Bucket_Tag_Rejection`) and `:24437-24456`
  (`Bucket_Tag_Response_Failure`) — same shape.
- `:23474-23477` — `Normalize_Get_Bucket_Location_Response`, same shape on a
  read path.
- `grep -c 'Status = 401 and then Code = "InvalidAccessKeyId"'` gives **88**
  occurrences in `client-buckets.adb` (plus 18 in `client-objects.adb` and 11
  in `client-transfers.adb`), i.e. the same three-line pattern throughout;
  `rg InvalidAccessKeyId src/ server/src/` matches only the client packages, so
  no in-repo server ever emits the pair the client waits for.
- `src/flyology-object_storage-client-buckets.adb:4796-4822`
  (`elsif Value.Status in 301 | 307 | 400 | 501` at `:4806`) is the one
  exception: `Normalize_Head_Bucket_Response` classifies on status alone, so a
  bodyless `403` becomes `Authorization_Failed` — still wrong for an
  authentication failure, but not `Corrupt_Or_Invalid_Response`.
- `review/baseline/service-2.json` has no error shape for `InvalidAccessKeyId`
  or `SignatureDoesNotMatch`, so the pinned model cannot justify the 401
  pairing either way.

Refutation attempts that failed:

- Looked for a status normalisation step between the Low_Level decoders and the
  classifiers that could remap 403 to 401. There is none: the classifiers read
  `Value.Status` straight out of `Decode_*_Response`; the live MinIO run shows
  `Result.Response.Status = 403` and `Error.Code = "InvalidAccessKeyId"`
  reaching `Normalize_*` unchanged.
- Checked whether the 401 pairing at least matches the in-repo server, so the
  behaviour would be self-consistent. It does not: the crate's own server emits
  `403 SignatureDoesNotMatch` for both a bad key and a bad secret
  (probe output above, and `server-authentication.adb:213-216` ->
  `server-s3_applications.adb:1906-1909`). The client cannot classify its own
  server's credential rejection.
- Checked whether the compatibility matrix or a qualification document states
  that only 401 is recognised. `docs/compatibility/s3.md` and
  `docs/qualification/*` say nothing about the accepted status/code pairs for
  authentication; the closest text ("every accepted service status/code pair"
  in `docs/qualification/list-buckets.md:21-22`) describes the corpus, not a
  documented limitation.
- Checked whether a caller can recover: yes, `Result.Response.Error.Code` still
  carries the true code, so a caller who ignores `Failure`/`Disposition` is
  unaffected. That is why this is P1 and not P0.
- Checked the existing suite for a row that would already cover it.
  `tests/src/flyology-object_storage-client-buckets-testing.adb` asserts
  `(401, "InvalidAccessKeyId", ..., Authentication_Failed)` at `:130`, `:271`,
  `:437`, `:711`, `:846`, `:982`, `:1120`, `:1257`, `:1391`, `:1527`, `:1658`
  and at 32 `401, "InvalidAccessKeyId"` rows in total; no row anywhere presents
  `403 InvalidAccessKeyId` or `403 SignatureDoesNotMatch`. The suite pins the
  wrong behaviour.

**Repro:** `tests/repros/src/repro_client_buckets_1.adb`. It first runs two
in-process exchanges against this crate's own S3 application
(`Repro_S3_Server.Run`) — one with the access key in the (unsigned)
Authorization credential replaced, one with a single signature hex digit
flipped — and prints the status and `<Code>`. It then starts a scripted
loopback origin serving the **verbatim MinIO 403 documents** recorded by
`repro_client_buckets_probe.adb`, and drives three public entry points through
them: `Buckets.Get_Location` (read), `Buckets.Put_Tags` (mutation) and
`Buckets.Create` (mutation). It asserts `Failure = Authentication_Failed` and,
for the mutations, `Disposition = ..._Definitely_Not_Applied` /
`Bucket_Definitely_Not_Created`. Six control legs replay the two enumerated
pairs (`401 InvalidAccessKeyId`, `403 AccessDenied`) through the same code and
must pass.

**Output** (`cd tests/repros && ./run.sh repro_client_buckets_1`, exit status
**1**):

```
  -- --- what this crate's own S3 server answers ---
  -- own server, unknown access key: HTTP 403 <Code> = "SignatureDoesNotMatch"
  -- own server, wrong signature: HTTP 403 <Code> = "SignatureDoesNotMatch"
  -- scripted loopback origin on 127.0.0.1:54027
  -- --- MinIO shape: 403 InvalidAccessKeyId / SignatureDoesNotMatch ---
  -- 403 InvalidAccessKeyId/location: status 403, Error.Code = "InvalidAccessKeyId", Failure = CORRUPT_OR_INVALID_RESPONSE
  FAILED: 403 InvalidAccessKeyId/location: GetBucketLocation Failure is AUTHENTICATION_FAILED
  -- 403 SignatureDoesNotMatch/location: status 403, Error.Code = "SignatureDoesNotMatch", Failure = CORRUPT_OR_INVALID_RESPONSE
  FAILED: 403 SignatureDoesNotMatch/location: GetBucketLocation Failure is AUTHENTICATION_FAILED
  -- 403 InvalidAccessKeyId/put-tags: status 403, Error.Code = "InvalidAccessKeyId", Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  FAILED: 403 InvalidAccessKeyId/put-tags: PutBucketTagging Failure is AUTHENTICATION_FAILED
  FAILED: 403 InvalidAccessKeyId/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 403 SignatureDoesNotMatch/put-tags: status 403, Error.Code = "SignatureDoesNotMatch", Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  FAILED: 403 SignatureDoesNotMatch/put-tags: PutBucketTagging Failure is AUTHENTICATION_FAILED
  FAILED: 403 SignatureDoesNotMatch/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 403 InvalidAccessKeyId/create: status 403, Error.Code = "InvalidAccessKeyId", Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_CREATION_OUTCOME_UNKNOWN
  FAILED: 403 InvalidAccessKeyId/create: CreateBucket Failure is AUTHENTICATION_FAILED
  FAILED: 403 InvalidAccessKeyId/create: CreateBucket Disposition is BUCKET_DEFINITELY_NOT_CREATED
  -- --- control: the enumerated 401 InvalidAccessKeyId pair ---
  -- 401 InvalidAccessKeyId/location: status 401, Error.Code = "InvalidAccessKeyId", Failure = AUTHENTICATION_FAILED
  ok: 401 InvalidAccessKeyId/location: GetBucketLocation Failure is AUTHENTICATION_FAILED
  -- 401 InvalidAccessKeyId/put-tags: status 401, Error.Code = "InvalidAccessKeyId", Failure = AUTHENTICATION_FAILED, Disposition = BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  ok: 401 InvalidAccessKeyId/put-tags: PutBucketTagging Failure is AUTHENTICATION_FAILED
  ok: 401 InvalidAccessKeyId/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 401 InvalidAccessKeyId/create: status 401, Error.Code = "InvalidAccessKeyId", Failure = AUTHENTICATION_FAILED, Disposition = BUCKET_DEFINITELY_NOT_CREATED
  ok: 401 InvalidAccessKeyId/create: CreateBucket Failure is AUTHENTICATION_FAILED
  ok: 401 InvalidAccessKeyId/create: CreateBucket Disposition is BUCKET_DEFINITELY_NOT_CREATED
  -- --- control: the enumerated 403 AccessDenied pair ---
  -- 403 AccessDenied/location: status 403, Error.Code = "AccessDenied", Failure = AUTHORIZATION_FAILED
  ok: 403 AccessDenied/location: GetBucketLocation Failure is AUTHORIZATION_FAILED
  -- 403 AccessDenied/put-tags: status 403, Error.Code = "AccessDenied", Failure = AUTHORIZATION_FAILED, Disposition = BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  ok: 403 AccessDenied/put-tags: PutBucketTagging Failure is AUTHORIZATION_FAILED
  ok: 403 AccessDenied/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 403 AccessDenied/create: status 403, Error.Code = "AccessDenied", Failure = AUTHORIZATION_FAILED, Disposition = BUCKET_DEFINITELY_NOT_CREATED
  ok: 403 AccessDenied/create: CreateBucket Failure is AUTHORIZATION_FAILED
  ok: 403 AccessDenied/create: CreateBucket Disposition is BUCKET_DEFINITELY_NOT_CREATED
  -- request 1: GET /flyology-review-buckets?location HTTP/1.1
  -- request 2: GET /flyology-review-buckets?location HTTP/1.1
  -- request 3: PUT /flyology-review-buckets?tagging HTTP/1.1
  -- request 4: PUT /flyology-review-buckets?tagging HTTP/1.1
  -- request 5: PUT /flyology-review-buckets HTTP/1.1
  -- request 6: GET /flyology-review-buckets?location HTTP/1.1
  -- request 7: PUT /flyology-review-buckets?tagging HTTP/1.1
  -- request 8: PUT /flyology-review-buckets HTTP/1.1
  -- request 9: GET /flyology-review-buckets?location HTTP/1.1
  -- request 10: PUT /flyology-review-buckets?tagging HTTP/1.1
  -- request 11: PUT /flyology-review-buckets HTTP/1.1
  ok: the origin served all eleven exchanges
BUG REPRODUCED: 8 failed expectation(s)
```

The live MinIO run reaches the same classification through the same public
calls, without any scripted bytes
(`tests/repros/src/repro_client_buckets_probe.adb`):

```
  -- location/wrong-key: status 403, outcome GET_BUCKET_LOCATION_REJECTED
  -- location/wrong-key: Error.Code = "InvalidAccessKeyId"
  -- location/wrong-key: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE
  -- location/wrong-secret: Error.Code = "SignatureDoesNotMatch"
  -- location/wrong-secret: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE
  -- put-tags/wrong-key: status 403, outcome PUT_BUCKET_TAGGING_REJECTED
  -- put-tags/wrong-key: Error.Code = "InvalidAccessKeyId"
  -- put-tags/wrong-key: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  -- put-tags/wrong-secret: Error.Code = "SignatureDoesNotMatch"
  -- put-tags/wrong-secret: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  -- put-tags/control: status 200, outcome BUCKET_TAGS_REPLACED
  -- put-tags/control: Client.Buckets Failure = NO_FAILURE, Disposition = BUCKET_TAG_MUTATION_COMPLETED
```

**Description:** every `Normalize_*_Response` / `Conclusive_*_Rejection` /
`*_Response_Failure` body in `client-buckets.adb` enumerates exact
`(status, code)` pairs, and the only authentication pair enumerated is
`(401, "InvalidAccessKeyId")`. No S3 server in evidence — AWS's documented
error table, the pinned MinIO release measured here, or this crate's own S3
application — returns 401 for a credential problem; they return
`403 InvalidAccessKeyId` for an unknown key and `403 SignatureDoesNotMatch`
for a bad signature. The pair therefore never matches, the response falls
through to `Corrupt_Or_Invalid_Response`, and because the same predicate also
decides `Conclusive_Rejection`, every bucket **mutation** additionally reports
`..._Outcome_Unknown`. The caller is told that a perfectly well-formed,
conclusive refusal was "not conclusive or valid" and that the mutation "must be
reconciled" by a read before any retry, when in fact nothing was mutated and
the correct action is to fix the credentials. It is deterministic and hits
anyone who mistypes a key or lets a secret rotate — including anyone running
this client against this repository's own server. The typed
`Result.Response.Error` still carries the true code, so a caller who ignores
the classification is unaffected. `Normalize_Head_Bucket_Response`
(`:4796-4822`) is the sole classifier that switches on status alone; it reports
`Authorization_Failed` for the same 403, which is wrong in a different way.
Existing tests that assert the wrong behaviour:
`tests/src/flyology-object_storage-client-buckets-testing.adb:130`, `:271`,
`:437`, `:711`, `:846`, `:982`, `:1120`, `:1257`, `:1391`, `:1527`, `:1658`
(32 `401, "InvalidAccessKeyId"` rows in that file), plus
`tests/src/s3_http_socket_corpus.adb` 401 rows. A fix is a maintainer decision
about the public error surface: which `(status, code)` pairs are treated as
conclusive authentication rejections (at minimum `403 InvalidAccessKeyId` and
`403 SignatureDoesNotMatch`; `403 RequestTimeTooSkewed` and
`400 AuthorizationHeaderMalformed` are the same class), and whether the 401
pairing is retained for compatibility. The same decision governs
`client-objects.adb` (18 sites) and `client-transfers.adb` (11 sites), which
carry the identical pattern, so a fix should be made once and applied
uniformly.

---

### CLIENT-BUCKETS-2: a bodyless HeadBucket rejection discards `x-amz-bucket-region`, so `Client.Buckets.Head` cannot report where a redirected bucket lives

**Verdict:** CONFIRMED for the mechanism and its consequence at every layer of
this repository. The discovery's external premise — that AWS attaches
`x-amz-bucket-region` to the 301/403/404 HeadBucket responses used for region
discovery — was **not** checked against a live AWS endpoint and remains
unverified. MinIO was checked and does **not** redirect at all (see the probe
section), so no server in the six-server matrix can exercise the shape; the
repro supplies the header itself.

**Severity:** P2 (discovery also said P2; unchanged). The discarded datum is
real and the `.ads` sentence it contradicts is real, but reaching it needs a
cross-region bucket plus a wrong signing region — "contract drift needing
unusual input" in the rubric — and no supported server in the maintained
matrix produces it.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:4952-4964` —
  `Decode_Head_Bucket_Complete_Response` builds
  `Headers.Bucket_Region => H ("x-amz-bucket-region")` and passes `Headers`
  into `Decode_Head_Bucket_Response` for **every** status.
- `:4886-4906` — `Headers` is consulted only inside the `Status = 200` branch
  (`Location_Type`, `Location_Name`, `Region` validation, then
  `Result => Headers`).
- `:4907-4913` — the `else` branch returns
  `(Kind => Head_Bucket_Rejected, Status => Status, Error => Head_Error (...))`
  and never mentions `Headers`.
- `:4865-4871` — `Head_Error` synthesises
  `Code => "HTTP" & Status_Text`, `Message => Operation & " returned HTTP status " & Status_Text`,
  `Resource => Null_Unbounded_String`; only `Request_ID` and `Host_ID` are
  carried through, so there is no field a region could hide in.
- `src/flyology-object_storage-client-low_level.ads:1396-1404` — the
  `Head_Bucket_Rejected` variant has exactly `Status` and `Error`.
- `src/flyology-object_storage-client-buckets.ads:10129-10141` — the
  convenience `Head_Outcome` likewise carries `Region` only on
  `Bucket_Available`; `:10184` documents the call as
  `@param Bucket Bucket whose availability and region are requested`.
- `src/flyology-object_storage-client-buckets.adb:4810-4811` —
  `Value.Status in 301 | 307 | 400 | 501 then Invalid_Request`, so the redirect
  is additionally labelled a request rejection (discovery observation 2, folded
  in here).
- `review/baseline/service-2.json` models `BucketRegion` as the
  `x-amz-bucket-region` header of `HeadBucketOutput` and declares only
  `NoSuchBucket`, so the model neither requires nor forbids the header on a
  non-200.

Refutation attempts that failed:

- Looked for another public path that recovers the header on a rejection: the
  composable `Head` returning `Head_Bucket_Result` exposes only
  `Response : Low_Level.Head_Bucket_Outcome`, i.e. the same two fields; the
  repro drives it and shows nothing but `HTTP301`.
- Checked whether `Get_Location` substitutes. It cannot: it decodes a body, and
  a 301 to GetBucketLocation would take the identical bodyless-rejection route
  through `Decode_Get_Bucket_Location_Response`'s `else` branch
  (`low_level.adb:4499-4505`), where `Error_Response` parses an empty payload.
- Checked `docs/qualification/head-bucket-composable.md` for a stated
  exclusion. It excludes cross-region redirect *following*, not exposing the
  region a redirect carries.
- Checked whether the header would be rejected as invalid on a 301 anyway: no,
  the singleton and transfer-coding checks in
  `Decode_Head_Bucket_Complete_Response` accept it, and the repro's decoder leg
  shows the value present in `Headers` at the moment it is dropped.
- Checked whether MinIO could demonstrate it: measured, it does not — a
  HeadBucket signed for `eu-west-1` against a `us-east-1` MinIO bucket answers
  `200 OK` with no `x-amz-bucket-region` header.

**Repro:** `tests/repros/src/repro_client_buckets_2.adb`. Two layers. First it
calls the public `Low_Level.Decode_Head_Bucket_Response` directly with
`Status => 301` and a `Head_Bucket_Result` whose `Bucket_Region` is
`eu-west-1`, and asserts that the region is still readable somewhere in the
returned outcome (every field of the rejection is printed and searched).
Second it starts a scripted loopback origin answering `HEAD /flyology-elsewhere`
with `301 Moved Permanently`, `Content-Length: 0` and
`x-amz-bucket-region: eu-west-1`, and drives both the convenience `Head`
(`Head_Outcome`) and the parameter-record `Head` (`Head_Bucket_Result`). The
controls repeat all four legs with `200 OK` and the same header and must pass.

**Output** (`cd tests/repros && ./run.sh repro_client_buckets_2`, exit status
**1**):

```
  -- --- typed decoder, 301 with x-amz-bucket-region: eu-west-1 ---
  -- decode 301: decoded kind HEAD_BUCKET_REJECTED, status 301
  -- decode 301: every readable field = HTTP301|HeadBucket returned HTTP status 301||AMZREQ1|AMZHOST1
  FAILED: decode 301: the decoded rejection still reports eu-west-1
  -- --- typed decoder control, 200 with the same header ---
  -- decode 200: decoded kind BUCKET_FOUND, status 200
  -- decode 200: Result.Bucket_Region = "eu-west-1"
  ok: decode 200: the decoder keeps x-amz-bucket-region
  -- scripted loopback origin on 127.0.0.1:65453
  -- --- Client.Buckets.Head over the origin, 301 redirect ---
  -- convenience 301: Head kind HEAD_REJECTED, status 301
  -- convenience 301: every readable field = HTTP301|HeadBucket returned HTTP status 301||AMZREQ1|AMZHOST1
  FAILED: convenience 301: Head still reports eu-west-1 after the redirect
  -- composable 301: response kind HEAD_BUCKET_REJECTED, status 301, Failure = INVALID_REQUEST
  -- composable 301: every readable field = HTTP301|HeadBucket returned HTTP status 301|
  FAILED: composable 301: the composable result still reports eu-west-1
  -- --- control: the same header on a 200 ---
  -- convenience 200: Head kind BUCKET_AVAILABLE, status 200
  -- convenience 200: Region = "eu-west-1"
  ok: convenience 200: Head reports eu-west-1
  -- composable 200: response kind BUCKET_FOUND, status 200, Failure = NO_FAILURE
  ok: composable 200: the composable result reports eu-west-1
  -- request 1: HEAD /flyology-elsewhere HTTP/1.1
  -- request 2: HEAD /flyology-elsewhere HTTP/1.1
  -- request 3: HEAD /flyology-elsewhere HTTP/1.1
  -- request 4: HEAD /flyology-elsewhere HTTP/1.1
  ok: the origin served all four exchanges
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** `Decode_Head_Bucket_Complete_Response` parses
`x-amz-bucket-region` out of the response, hands it to
`Decode_Head_Bucket_Response`, and that function then throws it away on every
non-200 status, returning a synthesised `HTTP301` error whose message repeats
the status and nothing else. The `Head_Bucket_Rejected` variant has no field
that could hold a region, so the loss is structural, not an oversight in one
branch: no caller of the typed low level, the composable operation, or the
convenience can recover the one datum a HeadBucket redirect exists to convey,
and the convenience's documented purpose ("availability and region are
requested") is met only on 200. The redirect is additionally reported as
`Invalid_Request`, which `client.ads:26` defines as a request rejection. Who
hits it: a caller that signs for the wrong region against AWS — nobody on the
maintained six-server matrix, which is why this stays P2 and why the repro must
script the header. It is deterministic. Existing tests that pin the discard:
`tests/src/flyology-object_storage-client-buckets-testing.adb:583-584` assert
`(301, Invalid_Request)` and `(307, Invalid_Request)`, and the helper at
`:502-520` builds the outcome from the status alone, so no test ever supplies
the header on a non-200. A fix needs a maintainer decision on the public
surface: either add a region (or full modelled-header) component to the
rejected variants of `Low_Level.Head_Bucket_Outcome` and
`Buckets.Head_Outcome`, or fold the value into `Error.Resource`/`Message`. The
first changes two public variant records; the second changes the meaning of a
documented field. Both are `.ads` decisions, not implementation details.

---

### CLIENT-BUCKETS-3: `Client.Buckets.List_Page` with a nonempty `Prefix` is unusable against the pinned MinIO release

(Discovery observation 1, which recorded the question and said a MinIO run
"would settle interop". It was run; MinIO fails the rule.)

**Verdict:** DOCUMENTED LIMITATION. The behaviour reproduces exactly as
described, but the strictness is written down:
`docs/qualification/list-buckets.md:13-16` — "An explicitly supplied prefix
must be echoed with the same presence and bytes, every returned bucket name
must remain in that prefix". The pinned botocore documentation embedded in
`review/baseline/service-2.json` supports the rule for AWS ("If `Prefix` was
sent with the request, it is included in the response"), though `Prefix` is not
in any `required` list, so the shape itself does not mandate it.

**Severity:** P2 (new; the discovery recorded it as an uncounted observation
with no severity). Not raised higher because the rule is documented and the
strict direction is deliberate: the client refuses to present an unfiltered
page as a filtered one. Not dismissed entirely because the observable effect is
that a public convenience parameter, `Prefix : Optional bucket-name prefix
filter` (`client-buckets.ads:961`), raises `Low_Level.Invalid_Response` against
a server the compatibility matrix lists for ListBuckets
(`docs/compatibility/s3.md:12`, "six-server matrix"), and no maintained
document says so.

Verified by reading:

- `src/flyology-object_storage-client-low_level.adb:4141-4148` — the echo rule:
  `(if Prepared.Requested_List_Buckets_Has_Prefix then not Page.Has_Prefix or else US.To_String (Page.Prefix) /= Requested_Prefix ...)`
  followed by `raise Invalid_Response with "ListBuckets response does not match prepared request"`.
- `:4150-4172` — the per-bucket prefix and region checks that follow.
- `src/flyology-object_storage-client-buckets.adb:191-197` (`Has_Prefix` at
  `:196`) — the convenience
  overload sets `Has_Prefix => Prefix'Length > 0`, so any nonempty prefix arms
  the rule.
- `:137-141` — the convenience turns the resulting `Response_Invalid` into
  `raise Low_Level.Invalid_Response with "ListBuckets response is invalid or exceeds the XML limit"`,
  a message that does not name the real cause.
- Measured wire: MinIO's answer to `GET /?max-buckets=10&prefix=flyology` is a
  200 `ListAllMyBucketsResult` with `Owner`, one `Bucket`, and no `<Prefix>`
  element (verbatim capture in `repro_client_buckets_probe.adb` output).
- Control on the same live server: `List_Page` with **no** prefix returns
  `PAGE_AVAILABLE, status 200`, so the prefix echo rule is the whole
  difference.

Refutation attempts that failed:

- Checked whether the failure is a parse error rather than the prefix rule: the
  identical document parses successfully when no prefix is requested, and the
  repro's control leg (the same document plus `<Prefix>flyology</Prefix>`)
  passes, isolating the rule.
- Checked the compatibility matrix for a stated exception. `docs/compatibility/
  s3.md:12` and `:487-506` describe strict prefix/cursor binding as a feature
  and claim "native/lightweight clients and s5cmd across the six-server matrix"
  for ListBuckets; they do not say a prefix-filtered listing is AWS-only.
- Checked whether the real-server corpus already covers it:
  `tests/src/s3_implementation_corpus.adb:3182-3184` calls `List_Page` without
  a prefix, so no maintained gate would notice.

**Repro:** `tests/repros/src/repro_client_buckets_3.adb`. A scripted loopback
origin replays MinIO's exact `ListAllMyBucketsResult` for
`GET /?max-buckets=10&prefix=flyology`, whose single bucket name does match the
requested prefix. It drives both the convenience `List_Page` (asserting a page,
catching `Invalid_Response`) and the parameter-record `List_Page` (asserting
`No_Failure`). The control legs replay the identical document with
`<Prefix>flyology</Prefix>` added and must pass.

**Output** (`cd tests/repros && ./run.sh repro_client_buckets_3`, exit status
**1**):

```
  -- scripted loopback origin on 127.0.0.1:53950
  -- --- MinIO shape: 200 ListAllMyBucketsResult with no <Prefix> ---
  -- minio/convenience: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : ListBuckets response is invalid or exceeds the XML limit
  FAILED: minio/convenience: the prefix-filtered page is returned
  -- minio/composable: kind LIST_BUCKETS_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE
  FAILED: minio/composable: the composable listing succeeds
  -- --- control: the same document echoing <Prefix>flyology</Prefix> ---
  -- echoed/convenience: kind PAGE_AVAILABLE, status 200
  ok: echoed/convenience: the prefix-filtered page is returned
  -- echoed/convenience: buckets in page = 1
  ok: echoed/convenience: the page holds the one matching bucket
  -- echoed/composable: kind LIST_BUCKETS_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  ok: echoed/composable: the composable listing succeeds
  -- request 1: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  -- request 2: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  -- request 3: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  -- request 4: GET /?max-buckets=10&prefix=flyology HTTP/1.1
  ok: the origin served all four exchanges
BUG REPRODUCED: 2 failed expectation(s)
```

The same failure occurs live, without any scripted bytes
(`repro_client_buckets_probe.adb` against the container):

```
  -- List_Page (Prefix => flyology) raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : ListBuckets response is invalid or exceeds the XML limit
  -- List_Page (no prefix, control): kind PAGE_AVAILABLE, status 200
  -- composable List_Page (Prefix => flyology): kind LIST_BUCKETS_EXCHANGE_FAILED, Failure = CORRUPT_OR_INVALID_RESPONSE
  -- composable List_Page: HTTP_Result = RESPONSE_INVALID
```

**Description:** the ListBuckets decoder requires a server that was sent
`prefix=` to echo `<Prefix>` byte-for-byte; MinIO omits it. The convenience
overload therefore raises `Low_Level.Invalid_Response` and the composable
overload reports `Response_Invalid` / `Corrupt_Or_Invalid_Response`, for a
response that is a valid, correctly filtered page. Who hits it: anyone calling
the public `Prefix` parameter against MinIO (and, by the same rule, against any
server that filters without echoing). It is deterministic. The behaviour is
intended and documented, so this is reported as a limitation rather than a bug;
what is missing is that neither the compatibility matrix nor the `.ads`
parameter documentation warns that the parameter is AWS-only in practice, and
the diagnostic the caller receives ("response is invalid or exceeds the XML
limit") names neither the prefix nor the server. A maintainer decision is
needed before any change: keep the strict rule and document the limitation, or
add a caller-selected relaxation (accept a missing `<Prefix>` while still
enforcing that every returned name matches) — the latter is a new public policy
choice about what a filtered page is allowed to mean, not an implementation
detail.

---

## Discovery observations, assessed independently

Each was re-derived from the sources at this commit; the verdict is mine.

1. **ListBuckets prefix strictness** — settled and promoted to
   CLIENT-BUCKETS-3 above. MinIO measured: no `<Prefix>` echo, listing fails.
2. **301/307/400/501 on HeadBucket labelled `Invalid_Request`** — confirmed at
   `client-buckets.adb:4810-4811`; `client.ads:26` defines `Invalid_Request` as
   a "Local or modeled service request rejection", which a redirect is not.
   Folded into CLIENT-BUCKETS-2 rather than counted separately; it has no
   observable consequence beyond the discarded region.
3. **Synthesised `Status => 500` sentinel in exchange-failed results** —
   confirmed and worth a note. `Put_Bucket_Replication_Result` and its siblings
   are **flat** records (`client-buckets.ads:6763-6772`), so on a transport
   failure `Normalize_Put_Bucket_Replication_Failure`
   (`client-buckets.adb:8765-8769`) stores
   `(Kind => Put_Bucket_Control_Rejected, Status => 500, Error => (others => <>))`
   into a field the spec documents as "Complete modeled S3 response". A caller
   who reads `Result.Response.Status` without first testing `Result.Kind` sees a
   fabricated 500 for an exchange in which no response was ever received. The
   variant-record results in the same file (`Create_Bucket_Result`,
   `Put_Bucket_Tagging_Result`, …) raise `Constraint_Error` instead, which is
   the safe behaviour; the inconsistency between the two families is the part I
   would raise with the maintainer. Not counted as a finding: it needs caller
   misuse, and the code comment at `:8766-8767` shows the choice was made
   deliberately.
4. **`Pre_Admission_Rejected` becomes `Constraint_Error`, with no `@exception`
   documentation** — confirmed: `client-buckets.adb:95` and `:122` (and the
   parallel mappers) `raise Constraint_Error with "HTTP request was rejected"`,
   and `grep -c '@exception' src/flyology-object_storage-client-buckets.ads`
   returns **0** for a spec whose convenience overloads can raise
   `Constraint_Error`, `Operation_Cancelled`, `Timeout_Error`, `Client_Closed`,
   `Connection_Error`, `Device_Error`, `Request_Body_Error` and
   `Invalid_Response`. Documentation gap, not a behaviour defect; agrees with
   the discovery. Using `Constraint_Error` (a language check exception) as a
   transport signal is a design choice a maintainer may want to revisit.
5. **Stale architecture prose** — confirmed.
   `docs/architecture/client-buckets.md:73-74` still says bucket-tagging
   "checksum selection currently fails locally until paired checksum generation
   is implemented", while `client-low_level.adb:224-245` (`Checksums.Compute` at `:227`) computes and
   signs a digest for all ten modelled algorithms and
   `docs/qualification/bucket-tagging.md:51-52` says all ten are covered.
   Documentation only.
6. **CreateSession retains the temporary secret in `Response_Data`** —
   confirmed. The raw XML is accumulated at `client-buckets.adb:3505` and
   released with `Flyology.Bytes.Clear` on every exit path (`:3616`, `:3640`,
   `:3715-3776`). The dependency documents `Clear` as "Release all retained
   elements and backing capacity"
   (`flyology_0.1.1/src/flyology-bytes.ads:91-93`) — release, not zeroisation.
   The spec promises zeroisation only for the decoded identity
   (`client-buckets.ads:10915-10917`, `:10939-10941`), so no contract is
   violated; noted for a security reviewer, not counted.
7. **`Head` returns the signing region when `x-amz-bucket-region` is absent** —
   confirmed at `client-buckets.adb:2845-2850` and documented at
   `client-buckets.ads:10174-10176`. Measured consequence against the live
   MinIO: a bucket MinIO reports as `us-east-1` (empty `LocationConstraint`) is
   reported by `Head` as `Region = "eu-west-1"` purely because the request was
   signed for `eu-west-1`. Documented, so not counted; but it means `Head`'s
   `Region` is not a trustworthy region source on any server that omits the
   header, which is every server in the matrix.
8. **CLIENT-LOW-4 reachable through these convenience overloads** — confirmed:
   the `Raise_*_Exchange_Failure` mappers re-raise `Invalid_Response` for
   `Response_Invalid | Response_Body_Too_Large | Response_Sink_Failed`
   (`client-buckets.adb:108-112`, `:137-141`), so a bodyless or non-XML 4xx/5xx
   surfaces here as `Invalid_Response`. Not duplicated; it belongs to
   CLIENT-LOW.

Areas where I looked for a further defect and found none: the `Failure_Reason`
and disposition derivations are internally consistent once the missing 403
pairs are set aside; the classification tables for the sampled reads and
mutations match the pinned model's error shapes; `Get_Location`'s `""` ->
`us-east-1` and `EU` -> `eu-west-1` normalisation matches `.ads:10214-10216`;
the tagging preparation computes Content-MD5 and the requested checksum header
as documented; and every scripted exchange in the three repro programs was
served exactly once, so no operation leaked or replayed a request.
