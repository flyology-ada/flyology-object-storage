# Baseline investigation: RustFS HeadObject rejection

Commit under investigation: `5fe6e3e`.
Investigated: 2026-09-07, macOS (darwin 25.6.0), Docker 29.4.0.

## Verdict

**(A) A client defect.** `Head_Object_Response_Bound` in
`/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d/src/flyology-object_storage-client-low_level.adb:5650-5653`
rejects an HTTP 200 HeadObject response solely because the server did not echo
`x-amz-version-id`. Omitting that header is the shape AWS itself returns for an
object in a bucket that has never had versioning enabled, which is exactly the
state of the corpus bucket. RustFS is not deviating here; the library is
demanding a header that is not required.

The repository's oracle-mode machinery cannot express this, because the
rejection is an exception raised inside `Execute_Head_Object` before any
`Head_Object_Outcome` reaches the corpus — so this is not (B). It is not (C):
the failure is bit-for-bit deterministic across fresh and reused containers,
distinct ports, and a proxied connection, and every request was signed and
accepted (HTTP 200).

## 1. What RustFS actually returns

Pinned image
`ghcr.io/rustfs/rustfs@sha256:800cf3f352a0a27e3275ca854a51f0027975d7acc7a0d52089a35bcc9fcbf0b5`
(reports `1.0.0-rc.3`), started by hand the way
`tests/scripts/test-rustfs.sh:29-34` does: `--publish 127.0.0.1::9000`,
`RUSTFS_ACCESS_KEY=FLYOLOGYS3ORACLE`,
`RUSTFS_SECRET_KEY=flyology-s3-oracle-secret-key-tests`, health-waited on
`/minio/health/live`.

### The exact failing exchange

Captured verbatim through a logging reverse proxy while the built
`tests/bin/s3_implementation_corpus` binary drove the corpus. This is exchange
44 of 44 — the last thing that happens before the exception.

```
HEAD /flyology-review-corpus-proxy/native-object?versionId=null HTTP/1.1
Host: 127.0.0.1:39000
x-amz-content-sha256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
x-amz-date: 20260907T012831Z
x-amz-request-payer: requester
x-amz-checksum-mode: ENABLED
authorization: AWS4-HMAC-SHA256 Credential=FLYOLOGYS3ORACLE/20260907/us-east-1/s3/aws4_request,SignedHeaders=host;x-amz-checksum-mode;x-amz-content-sha256;x-amz-date;x-amz-request-payer,Signature=fbb4c350ba4706fdb27bc31a3b6dfb53b43a80ab5d95090fe25102e9e364420b
```

```
HTTP/1.1 200 OK
accept-ranges: bytes
x-amz-checksum-sha256: 3myrefIiyzkI+qZCzK9EvhguCw5b6aRwoGHFefDi4gY=-2
x-amz-checksum-type: COMPOSITE
content-length: 6291456
content-type: binary/octet-stream
etag: "c3b3f33ec1ed7de45d99a636d2f68e6b-2"
last-modified: Mon, 07 Sep 2026 01:28:32 GMT
x-request-id: 82ae92a3-b844-47d0-a376-c95236931f87
x-amz-request-id: 82ae92a3-b844-47d0-a376-c95236931f87
date: Mon, 07 Sep 2026 01:28:32 GMT
```

No `x-amz-version-id`. No `x-amz-request-charged`.

Note what *is* present: the composite checksum
`3myrefIiyzkI+qZCzK9EvhguCw5b6aRwoGHFefDi4gY=-2` and
`x-amz-checksum-type: COMPOSITE` are precisely the values the corpus asserts at
`tests/src/s3_implementation_corpus.adb:1159-1166` (`Composite_SHA256_Object`,
`"COMPOSITE"`). **RustFS satisfies every assertion the corpus itself makes
about this response.** The corpus never gets to evaluate them, because the
library raises first.

### Independent raw-socket probes

Signed with a standalone SigV4 script (Python 3.13 via `uv run`), not the Ada
client, against the same container. All responses verbatim:

**(a) `HEAD /bucket/native-object`, no query** — unversioned bucket:

```
HTTP/1.1 200 OK
accept-ranges: bytes
content-length: 64
content-type: application/octet-stream
etag: "014842d480b571495a4a0363793f7367"
last-modified: Mon, 07 Sep 2026 01:27:10 GMT
x-request-id: 7248859e-9e9c-4f2d-99fd-80244d8ecac6
x-amz-request-id: 7248859e-9e9c-4f2d-99fd-80244d8ecac6
date: Mon, 07 Sep 2026 01:27:10 GMT
```

**(b) `HEAD /bucket/native-object?versionId=null` with
`x-amz-request-payer: requester` and `x-amz-checksum-mode: ENABLED`** — run
three times, byte-identical apart from `x-request-id`:

```
HTTP/1.1 200 OK
accept-ranges: bytes
content-length: 64
content-type: application/octet-stream
etag: "014842d480b571495a4a0363793f7367"
last-modified: Mon, 07 Sep 2026 01:27:10 GMT
x-request-id: 8c68e1c0-a791-45ec-8778-d9b0729a1312
x-amz-request-id: 8c68e1c0-a791-45ec-8778-d9b0729a1312
date: Mon, 07 Sep 2026 01:27:10 GMT
```

The same request without the two `x-amz-*` request headers, and a request with
the payer header but no `versionId`, both return the same header set. So
neither `x-amz-request-payer` nor `x-amz-checksum-mode` changes whether
`x-amz-version-id` appears; only the bucket's versioning state does.

**(c) After the versioning sequence.** A correction to the premise first: the
setup phase does **not** version-configure the corpus bucket.
`Require_Bucket_Versioning`
(`tests/src/s3_implementation_corpus.adb:3244-3303`) creates a *separate* probe
bucket named `<bucket>-versioning`, drives it Unconfigured → Enabled →
Suspended, and then deletes it (`Delete_Empty_Bucket`, line 3300). The corpus
bucket that the failing HeadObject targets is never versioned at all, and
`Require_Durable_Version_Routing` returns immediately because
`FLYOLOGY_S3_IMPLEMENTATION` is unset on the RustFS path
(`tests/src/s3_implementation_corpus.adb:3324-3333`;
`tests/scripts/test-rustfs.sh:79-88` sets it only for the runner and s3t
branches).

Reproducing that versioning sequence anyway on a probe bucket, RustFS behaves
three different ways, none of which is `null`:

| Bucket versioning state | `HEAD ?versionId=null` | `x-amz-version-id` returned |
| --- | --- | --- |
| Never configured (the corpus bucket) | `200 OK` | *absent* |
| Enabled | `404 Not Found` | *absent* |
| Suspended | `200 OK` | `00000000-0000-0000-0000-000000000000` |

Verbatim, suspended case:

```
HTTP/1.1 200 OK
accept-ranges: bytes
content-length: 64
content-type: application/octet-stream
etag: "0b649bcb5a82868817fec9a6e709d233"
last-modified: Mon, 07 Sep 2026 01:27:10 GMT
x-amz-version-id: 00000000-0000-0000-0000-000000000000
x-request-id: 0ba525d6-485e-4e8c-8541-680a90ecae6e
x-amz-request-id: 0ba525d6-485e-4e8c-8541-680a90ecae6e
date: Mon, 07 Sep 2026 01:27:10 GMT
```

This matters for the fix: even a server that *does* emit the header will not
generally echo the literal string `null`, so a repair that merely requires the
header to be present would still fail.

## 2. Which clause rejects it

`src/flyology-object_storage-client-low_level.adb:5641-5658`:

```ada
      return
        (Requested_Version'Length = 0
         or else US.To_String (Value.Version_ID) = Requested_Version)
        and then
          (Returned_Payer /= "requester"
           or else Requested_Payer = "requester");
```

The **first** clause. `Requested_Version` is `"null"` (length 3, so the
short-circuit does not apply) and `Value.Version_ID` is `""` because the header
is absent, so `"" = "null"` is False and the function returns False.
`Execute_Head_Object` then raises at line 5884-5885.

The payer clause is satisfied and is not involved: `Returned_Payer` is `""`
(RustFS sends no `x-amz-request-charged`), so `Returned_Payer /= "requester"`
is True.

**Controlled confirmation.** Re-running the corpus through the same proxy with
one modification — inject `x-amz-version-id: null` into HEAD responses whose
request line contains `versionId=null`, changing nothing else — the HeadObject
rejection disappears entirely and the corpus advances 16 further exchanges
(44 → 60) past HeadObject, GetObjectAttributes and GetObject. That isolates the
cause to this single absent header.

The same predicate is duplicated at the composable layer in
`src/flyology-object_storage-client-objects.adb:139-155`
(`Head_Object_Response_Bound`), used at line 2964, and the identically shaped
`Get_Object_Response_Bound` at lines 121-137 is used at lines 951, 2429 and
2551. Any fix must cover all of them.

## 3. AWS-documented behaviour

*From memory, unverified — no network lookup was performed for this section.*

The AWS S3 API reference for `HeadObject` documents `versionId` as an optional
query parameter naming a specific version, and documents the `x-amz-version-id`
response header as "the version ID of the object". It also documents that
objects stored in a bucket where versioning has never been enabled carry the
version ID `null`, and that `versionId=null` addresses such an object. What it
does **not** state is that `x-amz-version-id` is always present on a successful
response, nor that its value must equal the `versionId` that was requested. In
practice S3 returns `x-amz-version-id` for objects in versioning-enabled or
versioning-suspended buckets and omits it for never-versioned buckets — the
same shape RustFS produced. Likewise `x-amz-request-charged` is documented as
returned when the requester is charged, not as an unconditional echo.

On that reading the client's rejection is **wrong**: it refuses a response that
AWS itself would produce for exactly this request against exactly this bucket
state. The safety goal behind the check (never present metadata for a version
other than the one asked for) is achievable without it — see the fix direction.

Corroborating evidence inside this repository: the in-repo server has a special
case whose only purpose is to satisfy this check.
`src/flyology-object_storage-server-s3_applications.adb:4188-4194`:

```ada
            if US.Length (Info.Version) > 0 then
               Apps.Set_Header
                 (X, "x-amz-version-id", US.To_String (Info.Version));
            elsif Object_Read_Request.Has_Version_ID then
               Apps.Set_Header (X, "x-amz-version-id", "null");
            end if;
```

No third-party server does this. That is why the corpus passes against the
memory backend in CI and fails against every real server.

## 4. Determinism and container-state dependence

Deterministic; independent of container state. All runs used the built
`tests/bin/s3_implementation_corpus`, invoked the way
`tests/scripts/run-s3-implementation.sh:50-59,63-65` does (`setup` phase, then
the three-argument main phase) with the seven `*_ORACLE_MODE` variables from
`tests/scripts/test-rustfs.sh:60-75`.

| Run | Container | Bucket | Result |
| --- | --- | --- | --- |
| 1 | A (fresh) | `flyology-review-corpus-1` | `INVALID_RESPONSE : HeadObject response does not match prepared request` |
| 2 | A, via logging proxy | `flyology-review-corpus-proxy` | same |
| 3 | B (fresh, second container, different port) | `flyology-review-fresh-1` | same |
| 4 | B | `flyology-review-fresh-2` | same |
| 5 | B | `flyology-review-fresh-3` | same |
| 6 | A (reused, 5 prior corpora) | `flyology-review-reused-4` | same |
| 7 | A (reused) | `flyology-review-reused-5` | same |

7/7 failures, same message, same point. The raw HEAD in section 1(b) was also
issued three times with identical results. Fresh versus reused container makes
no difference; nor do distinct host ports (32798, 32799, 39000, 39001) or the
extra proxy hop.

Environmental causes are ruled out: SigV4 signatures were accepted (every
exchange returned 2xx up to the failing one), the `Host` header matched what
was signed on every path including through the proxy, and no clock or
networking symptom appeared anywhere in 44 exchanges.

## 5. Not RustFS-specific

`review/baseline/minio.log:96` and `review/baseline/seaweedfs.log:99` carry the
byte-identical message
`raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject
response does not match prepared request`. That text has exactly one raise site
(`src/flyology-object_storage-client-low_level.adb:5885`), and the corpus makes
exactly one synchronous `Execute_Head_Object` call that can trip either clause —
line 1147 is the only `Version_ID` assignment and line 1148 the only
`Request_Payer` assignment in the whole corpus. So MinIO and SeaweedFS fail on
the same request, for the same reason. All three reference implementations are
red at this commit for one client-side cause.

## 6. Was `test-rustfs.sh` ever expected to pass at this commit?

No — and it was never gated.

- The corpus case was added by `7d2d4c4` "Strengthen HeadObject implementation
  oracle" (Sat Aug 22 2026), which sent `versionId=null` plus
  `x-amz-request-payer: requester` to live servers and *expected success*.
- `git log -p --follow tests/scripts/test-rustfs.sh` shows the script being
  curated per discovered RustFS deviation right through
  `95c198a` (Sun Aug 23 2026, `FLYOLOGY_PUT_OBJECT_ORACLE_MODE`). It has not
  been touched since. So on Aug 23 it was maintained as a passing script.
- `2703ed6` "Problem: HeadObject responses are not bound to their request"
  (Sun Aug 30 2026) introduced `Head_Object_Response_Bound`. Its diffstat
  touches `src/…client-low_level.{ads,adb}`, `src/…client-objects.{ads,adb}`,
  `tests/src/object_storage_test_cases.adb`,
  `tests/src/s3_http_socket_corpus.adb` and the canary — **not**
  `tests/src/s3_implementation_corpus.adb` and not any live-server script.
- The new check was qualified only against the in-process socket fake, which
  always echoes the requested version (`git show 2703ed6 --
  tests/src/s3_http_socket_corpus.adb`: cases emit `x-amz-version-id:
  head-cancel-version`, `wrong-head-version`, etc.). No case covers an *absent*
  header.
- `.github/workflows/ci.yml:282-291` runs `test-rustfs.sh` only under
  `if: github.event_name == 'schedule'`, and sets
  `FLYOLOGY_S3_SERVER_RUNNER`, which makes `test-rustfs.sh:51-58` take the
  early-exit branch and never reach `run-s3-implementation.sh`. The corpus path
  against RustFS therefore has no CI gate at all — scheduled or otherwise.
- The push/PR gate `s3-smoke` (`.github/workflows/ci.yml:239-273`) *does* run
  the same corpus, but against the in-repo memory server via
  `tests/scripts/test-flyology-server.sh:105-110` — the one server carrying the
  `x-amz-version-id: null` special case from section 3.

So `test-rustfs.sh`'s full path was expected to pass as of Aug 23, was silently
broken by the Aug 30 client change, and nothing in CI could have caught it.

## 7. Shortest fix direction

Change the version predicate from "the response must echo the requested version"
to "the response must not contradict the requested version" — reject only when
the header is present *and* differs:

```ada
        (Requested_Version'Length = 0
         or else US.Length (Value.Version_ID) = 0
         or else US.To_String (Value.Version_ID) = Requested_Version)
```

This keeps the stated safety property (metadata for a different version is
still refused, which is what the socket-corpus `wrong-head-version` case
exercises) and accepts the AWS-shaped response where the header is absent.
Apply it identically to all four predicates:
`Head_Object_Response_Bound` in
`src/flyology-object_storage-client-low_level.adb:5641-5658` and
`src/flyology-object_storage-client-objects.adb:139-155`, and
`Get_Object_Response_Bound` in
`src/flyology-object_storage-client-objects.adb:121-137` (the GetObject
predicate has the same defect and the same absent-header exposure).

Note this alone will not accept RustFS's *suspended*-versioning sentinel
`00000000-0000-0000-0000-000000000000`, which is a present-and-different value.
That path is not exercised by the corpus, but it means a strict-echo contract
is not viable across real servers even in principle.

Two decisions this leaves open for the user, both outside the scope of this
investigation:

1. Whether the relaxed predicate is the intended contract, or whether the
   library should instead expose the mismatch as a typed outcome rather than an
   exception, so the corpus's oracle-mode machinery could classify per-server
   deviations. Today the exception escapes before any outcome is produced,
   which is why no `*_ORACLE_MODE` can express this.
2. Whether the server's `x-amz-version-id: null` fallback
   (`src/flyology-object_storage-server-s3_applications.adb:4192`) should
   remain once the client no longer requires it.

## 8. Deferred discovery (not investigated, outside this goal)

With the header injected (section 2), the corpus proceeds and then fails
differently at exchange 60:

```
PUT /flyology-review-inject-1/native-object?tagging HTTP/1.1
…
HTTP/1.1 200 OK
x-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e
x-amz-request-id: 2e90fdc8-9408-47de-b681-bb06d8dc699e
content-length: 0
```

→ `INVALID_RESPONSE : PutObjectTagging response is invalid or exceeds the XML
limit`. `Tagging_Version_ID`
(`src/flyology-object_storage-client-objects.adb:7177-7189`) raises when a
successful tagging response carries no `x-amz-version-id`:

```ada
      if Count > 1 or else (Success and then Count /= 1) then
```

This is the same class of defect — an unconditional demand for a version header
that a never-versioned bucket need not produce. It is a *later* gate, not the
baseline failure, and fixing section 7 alone will not turn the RustFS matrix
green. Recommend extracting it as a separate task rather than folding it in.

## Reproduction notes

Containers `flyology-review-rustfs-A` and `flyology-review-rustfs-B` were
started for this investigation and have been stopped and removed. No tracked
file was modified; no `alr`, `gprbuild`, `git stash`, or
`tests/scripts/test-*.sh` script was run. The corpus binary was invoked directly
from the already-built `tests/bin/`. Scratch scripts and captured logs live
under `/private/tmp/claude-501/` and are not part of the repository.
