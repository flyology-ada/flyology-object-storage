# Adversarial verification: SERVER (S3 application, routing, authorisation, operations)

Scope verified by reading: `src/flyology-object_storage-server-s3_applications.adb`
(the DeleteObjects arm 17580-17730, PutBucketVersioning 10350-10400, the object
tagging arm 15823-15990, PutObject/UploadPart `Content-Encoding` handling
12420-12630 and 14720-14910, `Send_Error`/`Send_Authentication_Error`/
`Send_Backend_Error` 1860-2016, `Response_IO.Begin_Object` 4180-4210,
HeadObject's `Set_Common_Headers` 16610-16660, GetObject result mapping
17230-17270, the pre-authentication classification 6014-6700, and the
`Secure_HTTPS` gates 5362-5375, 6733, 6874);
`src/flyology-object_storage-server-authentication.adb:81-230`;
`src/flyology-object_storage.ads:39-62`;
`src/flyology-object_storage-backends-memory.adb:318-331`;
`src/flyology-object_storage-s3-checksums.ads`;
`src/flyology-object_storage-s3-checksum_policy.ads`;
`server/src/flyology_object_storage_server_runtime.adb:160-180`;
`tests/src/s3_server_harness.adb:85-100`;
`tests/src/s3_server_application_corpus.adb` (1085-1115, 15700-15740,
16030-16150, 17740-17760, 18180-18210);
`tests/scripts/run-s3-server-slice.sh:100-115`;
`docs/compatibility/s3.md` (rows 58-72, and 258, 340-350, 440-462, 500-530,
536-545); `review/baseline/service-2.json` (the `httpChecksum` traits and
`ContentMD5`/`ChecksumAlgorithm` members of every `requestChecksumRequired`
operation, `GetObjectOutput`/`HeadObjectOutput` `DeleteMarker` and `VersionId`,
and `CompleteMultipartUploadOutput.Location`); and flyology_http 0.1.3
`Flyology.HTTP.Server.Applications` (`Create`, `Request_Scheme`).

Harness programs added: `tests/repros/src/repro_server_1.adb`,
`repro_server_1_live.adb` (a listener holder used for the stock-client run, not
an assertion), `repro_server_2.adb`, `repro_server_3.adb`,
`repro_server_4.adb`, `repro_server_5.adb`, and `repro_server_probe.adb` (an
exploration program for the discovery observations; it always exits 0).
Nothing tracked was modified. No Docker script was run: the aws-cli v2.36.34
already installed on this machine was pointed at the crate's own loopback
listener, and at a plain-socket and a TLS sniffer under the scratch directory,
to capture what a stock client actually sends.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| SERVER-1 | CONFIRMED | P0 (P1) | `tests/repros/src/repro_server_1.adb` |
| SERVER-2 | CONFIRMED | P1 (P2) | `tests/repros/src/repro_server_2.adb` |
| SERVER-3 | CONFIRMED | P2 (not counted) | `tests/repros/src/repro_server_3.adb` |
| SERVER-4 | CONFIRMED | P2 (not counted) | `tests/repros/src/repro_server_4.adb` |
| SERVER-5 | PARTIALLY CONFIRMED | P2 (not counted) | `tests/repros/src/repro_server_5.adb` |

SERVER-3 through SERVER-5 are new numbers assigned to items the discovery
report listed under "Observations not counted"; SERVER-5 is partially
confirmed because the `aws-chunked` rejection itself is a documented
limitation and only the diagnostic survives, and because the discovery
report's premise that such a request receives 501 is wrong (it receives 400).
Two further observations were examined and are recorded as REFUTED at the end
of this report: the pre-authentication classification discloses nothing about
stored state, and the exception containment on truncated bodies holds.

---

### SERVER-1: Content-MD5 is mandatory on DeleteObjects, PutBucketVersioning, PutObjectTagging and the other `requestChecksumRequired` routes, so stock aws-cli v2 is rejected

**Verdict:** CONFIRMED, and strengthened. The discovery report marked the
client-behaviour half "from memory, unverified"; I settled it with the
aws-cli v2.36.34 already installed on this machine, driven against the real
Ada application over the loopback listener.

**Severity:** P0 (discovery said P1). Corrected because the rubric's P0 covers
"an interop-breaking protocol violation that a stock client or server
rejects", and I observed a stock, unconfigured aws-cli v2 authenticate
successfully against this server and then be refused on three ordinary
operations. This is not a model-driven-SDK hypothetical.

Verified by reading:

- `src/flyology-object_storage-server-s3_applications.adb:17674-17683` —
  DeleteObjects: `if MD5_Count /= 1 or else not S3.Wire_Core.Valid_Base64 (...)
  then Send_Error (X, 400, "InvalidRequest", "DeleteObjects requires one valid
  Content-MD5 header", ...)`.
- `src/flyology-object_storage-server-s3_applications.adb:17617-17670`
  (`Verify_Checksum`) computes and compares the modelled flexible checksum over
  the exact body, and `:17713-17723` consults `Checksum_Status` — but only in
  the `elsif` chain *after* the Content-MD5 gate, so a correct
  `x-amz-checksum-crc32` can never substitute for Content-MD5.
- `src/flyology-object_storage-server-s3_applications.adb:10358-10369` —
  PutBucketVersioning, same gate, same 400.
- `src/flyology-object_storage-server-s3_applications.adb:15883-15904` —
  object tagging is worse than the discovery report states: *before* the
  Content-MD5 gate, `elsif Algorithm_Count = 1 or else Has_Checksum_Header
  then Send_Error (X, 501, "NotImplemented", "Object tagging SDK checksums are
  not implemented", ...)`. A model-driven client that sends the flexible
  checksum gets 501, not 400, and there is no accepted combination other than
  Content-MD5 alone.
- `src/flyology-object_storage.ads` is not involved; this is purely a server
  admission rule.

Pinned model, printed from `review/baseline/service-2.json` with python3
(this is a botocore `service-2.json`, so the traits live under
`operations.<Name>.httpChecksum` and the members under
`shapes.<Input>.members`):

```
DeleteObjects            requestChecksumRequired=True  reqAlgMember=ChecksumAlgorithm  ContentMD5=ABSENT   MD5required=False
PutBucketVersioning      requestChecksumRequired=True  reqAlgMember=ChecksumAlgorithm  ContentMD5=present  MD5required=False
PutObjectTagging         requestChecksumRequired=True  reqAlgMember=ChecksumAlgorithm  ContentMD5=present  MD5required=False
PutBucketPolicy          requestChecksumRequired=True  reqAlgMember=ChecksumAlgorithm  ContentMD5=present  MD5required=False
PutBucketTagging         requestChecksumRequired=True  reqAlgMember=ChecksumAlgorithm  ContentMD5=present  MD5required=False
PutObjectLockConfiguration  requestChecksumRequired=True  ...  ContentMD5=present  MD5required=False
PutObjectLegalHold       requestChecksumRequired=True  ...  ContentMD5=present  MD5required=False
PutObjectRetention       requestChecksumRequired=True  ...  ContentMD5=present  MD5required=False
PutBucketAcl / PutObjectAcl / PutBucketReplication / PutBucketWebsite /
PutBucketEncryption / PutBucketOwnershipControls / PutBucketCors /
PutPublicAccessBlock     requestChecksumRequired=True  ...  ContentMD5=present  MD5required=False
PutBucketLifecycleConfiguration  requestChecksumRequired=True  ...  ContentMD5=ABSENT
```

`ContentMD5` is never in any of these operations' `required` lists, and for
`DeleteObjects` and `PutBucketLifecycleConfiguration` the member does not
exist in the input shape at all — a client generated from this model has no
modelled way to send it. The model's own `ChecksumAlgorithm` documentation
(`shapes.DeleteObjectsRequest.members.ChecksumAlgorithm.documentation`) says
the algorithm header must be accompanied by "a corresponding
`x-amz-checksum-algorithm` or `x-amz-trailer` header", i.e. the flexible
checksum *is* the way `requestChecksumRequired` is satisfied.

Refutation attempts that failed:

- Looked for an alternative acceptance path in the DeleteObjects arm: the
  Content-MD5 gate is the first `if` of the chain at `:17674`, so
  `Checksum_Status = Checksum_OK` is unreachable as a substitute.
- Checked whether the model marks `ContentMD5` required anywhere: it does not
  (table above).
- Checked whether the existing corpus already covers the model-conformant
  request. It does not: `tests/src/s3_server_application_corpus.adb:16039-16045`
  asserts `InvalidRequest` for `Include_MD5 => False` with *no* checksum at
  all, and the ten-algorithm loop at `:16080-16096` leaves `Include_MD5` at its
  default `True`, so every accepted flexible-checksum case also carries
  Content-MD5 (`:1097-1113`, `Signed_Delete_Objects_Request`).
- Checked whether `docs/compatibility/s3.md` frames this as a deliberate
  boundary the way it does for `aws-chunked`. `:506-508` states the rule
  ("requires canonical Content-MD5 over the exact admitted body") as intended
  behaviour but never says that a model-driven client cannot comply; the
  DeleteObjects row is therefore accurate to the code and wrong about
  interoperability. This is why I did not record it as DOCUMENTED LIMITATION:
  the document does not disclose the consequence.
- Checked whether only obsolete SDKs are affected, by capturing what the
  installed aws-cli actually sends (see below). It is the current default.

**Real-client evidence.** `command -v aws mc s5cmd` found
`/opt/homebrew/bin/aws` (aws-cli/2.36.34, awscrt 0.36.2) and
`/opt/homebrew/bin/mc`; no Docker script was used. I ran
`tests/repros/src/repro_server_1_live.adb` (a helper main that creates the
fixtures, opens the loopback listener and holds it for 45 s) and pointed the
stock CLI at it with only `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` /
`AWS_DEFAULT_REGION` set — no checksum configuration of any kind:

```
### aws s3api list-objects-v2 (sanity)
{
    "Contents": [ { "Key": "modelled", ... "Size": 7 } ], ...
}

### aws s3api delete-objects (stock defaults)
aws: [ERROR]: An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header

### aws s3api put-bucket-versioning (stock defaults)
aws: [ERROR]: An error occurred (InvalidRequest) when calling the PutBucketVersioning operation: PutBucketVersioning requires one valid Content-MD5 header

### aws s3api put-object-tagging (stock defaults)
aws: [ERROR]: An error occurred (NotImplemented) when calling the PutObjectTagging operation: Object tagging SDK checksums are not implemented

### aws s3api put-bucket-tagging (stock defaults)
aws: [ERROR]: An error occurred (InvalidRequest) when calling the PutBucketTagging operation: PutBucketTagging requires a valid Content-MD5
```

`list-objects-v2`, `s3 cp`, `s3api put-object` and single-key `s3 rm` all
succeed against the same listener in the same session, so authentication,
signing and routing are fine; only the `requestChecksumRequired` routes fail.
The exact bytes the CLI puts on the wire (captured with a plain socket
listener so nothing about the Ada server could influence it):

```
POST /md5-bucket?delete HTTP/1.1
Host: 127.0.0.1:64829
User-Agent: aws-cli/2.36.34 md/awscrt#0.36.2 ... md/command#s3api.delete-objects
x-amz-checksum-crc64nvme: hBxFfoI/0Yk=
x-amz-sdk-checksum-algorithm: CRC64NVME
X-Amz-Date: 20260907T013904Z
X-Amz-Content-SHA256: 063b9d00...8ad7
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/...,
  SignedHeaders=host;x-amz-checksum-crc64nvme;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=...
Content-Length: 101

<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>modelled</Key></Object></Delete>
```

There is no `Content-MD5` field. The default algorithm is CRC64NVME, which the
server's own `Verify_Checksum` supports.

**Repro:** `tests/repros/src/repro_server_1.adb`. It creates two buckets and
four objects, then for each of DeleteObjects, PutBucketVersioning and
PutObjectTagging sends the request twice: once with a correct
`x-amz-checksum-crc32` plus `x-amz-sdk-checksum-algorithm: CRC32` and no
Content-MD5 (asserting 200, the model-conformant behaviour), and once with
Content-MD5 as the control (asserting 200, which passes today). It also
re-reads the key that the CRC32-only DeleteObjects should have removed.
Supporting helper: `tests/repros/src/repro_server_1_live.adb` (not an
assertion; it only holds the listener open for the aws-cli run above).

**Output** (`cd tests/repros && ./run.sh repro_server_1`, exit status **1**):

```
  ok: fixture: CreateBucket /md5-bucket
  ok: fixture: CreateBucket /md5-control
  ok: fixture: PutObject /md5-bucket/modelled
  ok: fixture: PutObject /md5-bucket/control
  -- DeleteObjects flexible checksum headers: x-amz-sdk-checksum-algorithm: CRC32\r\nx-amz-checksum-crc32: YZjakw==\r\n
  -- DeleteObjects CRC32 only, no Content-MD5: status 400  body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>DeleteObjects requires one valid Content-MD5 header</Message><Resource>/md5-bucket?delete</Resource></Error>
  FAILED: DeleteObjects with a valid x-amz-checksum-crc32 and x-amz-sdk-checksum-algorithm: CRC32 and no Content-MD5 is 200
  FAILED: DeleteObjects CRC32-only response reports the deleted key
  -- GET /md5-bucket/modelled after the CRC32-only batch: status 200  body payload
  FAILED: the CRC32-only DeleteObjects actually removed the key
  -- CONTROL DeleteObjects with Content-MD5: status 200  body <?xml version="1.0" encoding="UTF-8"?><DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>control</Key></Deleted></DeleteResult>
  ok: CONTROL: DeleteObjects with Content-MD5 is 200
  -- PutBucketVersioning CRC32 only, no Content-MD5: status 400  body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>PutBucketVersioning requires one valid Content-MD5 header</Message><Resource>/md5-bucket?versioning</Resource></Error>
  FAILED: PutBucketVersioning with a valid flexible checksum and no Content-MD5 is 200
  -- CONTROL PutBucketVersioning with Content-MD5: status 200  body 
  ok: CONTROL: PutBucketVersioning with Content-MD5 is 200
  ok: fixture: PutObject /md5-control/tagged
  ok: fixture: PutObject /md5-control/tagged-control
  -- PutObjectTagging CRC32 only, no Content-MD5: status 501  body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NotImplemented</Code><Message>Object tagging SDK checksums are not implemented</Message><Resource>/md5-control/tagged?tagging</Resource></Error>
  FAILED: PutObjectTagging with a valid flexible checksum and no Content-MD5 is 200
  -- CONTROL PutObjectTagging with Content-MD5: status 200  body 
  ok: CONTROL: PutObjectTagging with Content-MD5 is 200
BUG REPRODUCED: 5 failed expectation(s)
```

**Description:** For every operation the pinned model marks
`requestChecksumRequired: true`, the server treats Content-MD5 as the only
acceptable integrity header rather than as one of several. On DeleteObjects
the gate at `s3_applications.adb:17674` runs before the already-implemented
flexible-checksum verdict at `:17713`, so a request carrying a correct
`x-amz-checksum-crc32`/`-crc64nvme` is answered `400 InvalidRequest` and
nothing is deleted; PutBucketVersioning (`:10358`) and PutBucketTagging behave
the same way, and the object-tagging arm (`:15889`) additionally answers
`501 NotImplemented` to any request that carries a flexible checksum at all,
so for PutObjectTagging there is no model-conformant request the server will
accept. Since AWS turned on default integrity protection, the stock aws-cli v2
sends `x-amz-sdk-checksum-algorithm: CRC64NVME` + `x-amz-checksum-crc64nvme`
and no Content-MD5 on exactly these operations, so an unmodified
`aws s3api delete-objects`, `put-bucket-versioning`, `put-bucket-tagging`,
`put-object-tagging` (and by inspection `put-bucket-policy`,
`put-object-retention`, `put-object-legal-hold`,
`put-object-lock-configuration`, `put-bucket-encryption`,
`put-bucket-ownership-controls`, `put-bucket-acl`, `put-object-acl`,
`put-bucket-replication`, `put-bucket-website`, `put-public-access-block`)
against this server fails. It is fully deterministic. The reason the existing
gates pass is that they never exercise the model-conformant shape:
`tests/src/s3_server_application_corpus.adb:16039-16045` asserts
`InvalidRequest` for a request with *no* integrity header (which AWS also
rejects) and the flexible-checksum loop at `:16080-16096` keeps
`Include_MD5 => True`, while `tests/scripts/run-s3-server-slice.sh:107` drives
DeleteObjects only through s5cmd v2.3.0 on aws-sdk-go v1, which still sends
Content-MD5. A fix is a maintainer policy decision, not a mechanical change:
the crate must decide whether "at least one of Content-MD5 or a verified
flexible checksum" replaces "Content-MD5 required" on these routes (the
pattern `Read_Bucket_Scalar_Control`'s `Require_Checksum` at `:5165-5200`
already uses elsewhere), and whether the object-tagging 501 for SDK checksums
at `:15889` becomes an accept path; `docs/compatibility/s3.md:506-508` and
`:526-527` would have to be restated with it.

---

### SERVER-2: reading a delete marker loses `x-amz-delete-marker`, and an exact-version marker read is 404 instead of 405

**Verdict:** CONFIRMED. Both sub-claims reproduce, and I additionally
confirmed the HEAD-with-versionId case, which the discovery report did not
state.

**Severity:** P1 (discovery said P2). Corrected because the state involved is
not unusual input: after any `DELETE` of any key in a versioned bucket, that
key's *current* version is a delete marker, so every subsequent GET/HEAD takes
this path. The response the client gets is indistinguishable from "this key
never existed", which is a wrong result on a reachable path, and the model
documents a different status code for the exact-version case. The
missing-header half alone would be P2; the 404-instead-of-405 half is the
reason for P1.

Verified by reading:

- `src/flyology-object_storage-backends-memory.adb:318-331`
  (`Selected_Object_Index`) returns 0 — indistinguishable from "absent" —
  when the selected generation `Is_Delete_Marker`.
- `src/flyology-object_storage-server-s3_applications.adb:17253-17262`
  (GetObject) and `:16880-16957` (HeadObject) forward that as a plain
  `Result`, then `Send_Backend_Error`.
- `src/flyology-object_storage-server-s3_applications.adb:1929-1936`
  (`Send_Backend_Error`) maps `Not_Found` to `404` with
  `NoSuchBucket`/`NoSuchKey` and has no marker-aware branch.
- `src/flyology-object_storage.ads:39-62` — the public `Status` enumeration
  runs `Success, Not_Found, Bucket_Not_Found, Tag_Set_Not_Found,
  Already_Exists, ... Backend_Unavailable` with no delete-marker outcome, so
  the backend has no way to tell the server what happened. I re-read this
  myself; the discovery report's claim is accurate.
- `rg 'x-amz-delete-marker' src/` — the only emitters are the DeleteObject arm
  and the WriteGetObjectResponse forwarding table.

Pinned model, `review/baseline/service-2.json`,
`shapes.GetObjectOutput.members.DeleteMarker` (`"location": "header"`,
`"locationName": "x-amz-delete-marker"`), documentation verbatim:

```
Indicates whether the object retrieved was (true) or was not (false) a Delete
Marker. If false, this response header does not appear in the response.
  - If the current version of the object is a delete marker, Amazon S3 behaves
    as if the object was deleted and includes x-amz-delete-marker: true in the
    response.
  - If the specified version in the request is a delete marker, the response
    returns a 405 Method Not Allowed error and the Last-Modified: timestamp
    response header.
```

`shapes.HeadObjectOutput.members.DeleteMarker` carries the same binding with
the shorter documentation ("Specifies whether the object retrieved was (true)
or was not (false) a Delete Marker").

Refutation attempts that failed:

- Looked for a marker-aware branch in the GetObject/HeadObject arms or in
  `Send_Backend_Error`: there is none.
- Checked whether `Status` already carries a marker variant the server merely
  ignores: it does not (`flyology-object_storage.ads:39-62`), so this is
  structural.
- Checked whether the memory backend is the odd one out and the files backend
  reports something else: `Selected_Object_Index` is the shared shape of the
  selector contract, and the server would map any `Not_Found` identically, so
  the backend choice cannot change the answer.
- Checked whether `docs/compatibility/s3.md` scopes read-side marker
  behaviour out. `:59` (HeadObject) and `:851-858` (GetObject) list exclusions
  (part selection, non-null versions, SSE-C) but not delete-marker reads, and
  `:539-541` documents publishing and removing markers without a read-side
  caveat. So this is not a DOCUMENTED LIMITATION.
- Checked existing coverage:
  `tests/src/s3_server_application_corpus.adb:18196-18206` asserts the
  DeleteObject marker headers and `:17754` asserts an exact-version delete does
  *not* carry the header; no test reads a marker back through GET or HEAD.

**Repro:** `tests/repros/src/repro_server_2.adb`. It creates a bucket, enables
versioning, writes `k` and a second live key, deletes `k` (capturing the
marker version id from `x-amz-version-id`), then asserts the two documented
behaviours on GET and HEAD of the current version and of the exact marker
version. Controls: the DELETE itself must report `x-amz-delete-marker: true`
and a version id, a live key must still read 200, and a key that never existed
must read 404 with no marker header — all pass.

**Output** (`cd tests/repros && ./run.sh repro_server_2`, exit status **1**):

```
  ok: fixture: CreateBucket /marker-bucket
  ok: fixture: PutBucketVersioning Enabled
  ok: fixture: PutObject /marker-bucket/k
  ok: fixture: PutObject /marker-bucket/live
  -- CONTROL DELETE /marker-bucket/k: status 204  x-amz-delete-marker=[true]  x-amz-version-id=[f37f4dffd982f843741984a21d253e64aa73d8a80500283bd999f2928f6f4eed]  Last-Modified=[]
  --    body 
  ok: CONTROL: DELETE of a versioned key is 204
  ok: CONTROL: DELETE reports x-amz-delete-marker: true
  ok: CONTROL: DELETE reports the marker version id
  -- GET a key whose current version is a delete marker: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist</Message><Resource>/marker-bucket/k</Resource></Error>
  ok: GET of a current delete marker is 404
  FAILED: GET of a current delete marker carries x-amz-delete-marker: true
  -- HEAD a key whose current version is a delete marker: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  --    body 
  ok: HEAD of a current delete marker is 404
  FAILED: HEAD of a current delete marker carries x-amz-delete-marker: true
  -- GET ?versionId=<the marker itself>: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist</Message><Resource>/marker-bucket/k?versionId=f37f4dffd982f843741984a21d253e64aa73d8a80500283bd999f2928f6f4eed</Resource></Error>
  FAILED: GET of an exact delete-marker version is 405 MethodNotAllowed
  FAILED: GET of an exact delete-marker version carries x-amz-delete-marker: true
  FAILED: GET of an exact delete-marker version carries Last-Modified
  -- HEAD ?versionId=<the marker itself>: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  --    body 
  FAILED: HEAD of an exact delete-marker version is 405 MethodNotAllowed
  FAILED: HEAD of an exact delete-marker version carries x-amz-delete-marker: true
  -- CONTROL GET of a live key: status 200  x-amz-delete-marker=[]  x-amz-version-id=[77d55163c888e8ba05bf5972434e4870281279b1f5546f8145f9158af0f53a58]  Last-Modified=[Mon, 07 Sep 2026 01:42:33 GMT]
  ok: CONTROL: GET of a live key still reads 200
  -- CONTROL GET of a key that never existed: status 404  x-amz-delete-marker=[]  x-amz-version-id=[]  Last-Modified=[]
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist</Message><Resource>/marker-bucket/never-existed</Resource></Error>
  ok: CONTROL: GET of an absent key is 404
  ok: CONTROL: GET of an absent key carries no delete-marker header
BUG REPRODUCED: 7 failed expectation(s)
```

**Description:** In a versioned bucket, `Selected_Object_Index`
(`backends-memory.adb:318-331`) collapses "the selected generation is a delete
marker" onto the same `Natural` 0 it uses for "no such generation", so the
server sees `Not_Found` and `Send_Backend_Error`
(`s3_applications.adb:1929-1936`) emits a bare `404 NoSuchKey`. Two documented
behaviours are lost: a read of a key whose current version is a delete marker
does not carry `x-amz-delete-marker: true`, and a read of the marker's own
version returns 404 instead of `405 Method Not Allowed` with `Last-Modified`.
Any versioning-aware client — replication, backup, or a tool walking
ListObjectVersions and reading each generation — cannot distinguish "deleted"
from "never existed", and cannot tell that the version it asked for is a
marker. Everyone using a versioned bucket hits the first case on the very next
read after any DELETE; it is deterministic. No existing test asserts the wrong
behaviour, but none asserts the right one either
(`tests/src/s3_server_application_corpus.adb:18196-18206` and `:17754` cover
only the DeleteObject response headers). A fix cannot be made in the server
alone and needs a maintainer decision on the public API: `Status`
(`src/flyology-object_storage.ads:39-62`) has no marker outcome, so either a
new enumeration literal (e.g. `Delete_Marker`) must be added to that visible
type — a public-interface value change — or the backend read operations must
gain an out-parameter carrying the marker's presence and `Last_Modified`, and
every backend and the conformance suite must be extended together.

---

### SERVER-3: HeadObject emits `x-amz-version-id: null` for an unversioned object while PutObject and GetObject omit it

**Verdict:** CONFIRMED (new finding, promoted from the discovery report's
"Observations not counted"). The discovery report called it "harmless to
clients, inconsistent between the two reads"; it is also a deviation from the
crate's own documented three-way rule, which is why I counted it.

**Severity:** P2 (discovery did not count it). It is contract drift with no
behavioural consequence I could find — I checked that a client which
round-trips HEAD's `null` back as `?versionId=null` still gets 200 — so it does
not reach P1.

Verified by reading:

- `src/flyology-object_storage-server-s3_applications.adb:16619-16622`
  (HeadObject's `Set_Common_Headers`):
  `Apps.Set_Header (X, "x-amz-version-id", (if US.Length (Info.Version) > 0
  then US.To_String (Info.Version) else "null"));` — unconditional.
- `src/flyology-object_storage-server-s3_applications.adb:4189-4194`
  (`Response_IO.Begin_Object`, the GetObject path):
  `if US.Length (Info.Version) > 0 then Apps.Set_Header (X,
  "x-amz-version-id", ...); elsif Object_Read_Request.Has_Version_ID then
  Apps.Set_Header (X, "x-amz-version-id", "null"); end if;` — conditional.
- `docs/compatibility/s3.md:446-450` states the crate's own rule: "The server
  omits the header for unversioned publication, emits the exact opaque
  identity for enabled memory/files/SQLite publication, and emits
  `x-amz-version-id: null` for suspended memory/files/SQLite publication." The
  three cases are distinct; HeadObject conflates "unversioned" with
  "suspended".
- `review/baseline/service-2.json`,
  `shapes.HeadObjectOutput.members.VersionId` and
  `shapes.GetObjectOutput.members.VersionId` are the same binding
  (`"location": "header"`, `"locationName": "x-amz-version-id"`,
  documentation "Version ID of the object."), so the model gives the two
  reads no licence to differ.

Refutation attempts that failed:

- Checked whether the difference is only visible with an unusual request: it
  is not — any HEAD of any object in a never-versioned bucket shows it.
- Checked whether `null` breaks a client that feeds it back: `GET
  /plain-bucket/k?versionId=null` and the HEAD equivalent both return 200 with
  `x-amz-version-id: null`, so the value round-trips. This is why I did not
  raise the severity.
- Checked whether `docs/compatibility/s3.md` documents a HeadObject-specific
  exception: the HeadObject row (`:59`) lists only the multipart Range-to-part
  checksum exclusion.
- I did **not** check MinIO. Confirming what a third-party server does would
  need a Docker container, which is disproportionate for a P2 with no
  behavioural consequence; the finding rests on the crate's disagreement with
  itself and with `docs/compatibility/s3.md:446-450`, not on AWS behaviour.
  My recollection that AWS omits the header on never-versioned buckets is
  unverified and is not load-bearing here.

**Repro:** `tests/repros/src/repro_server_3.adb`. It writes one object into a
never-versioned bucket and one into a versioning-enabled bucket, then asserts
that GET and HEAD of the same object report the same `x-amz-version-id` and
that HEAD omits it where GetObject does. Controls: PutObject omits the header
for unversioned publication (matching the documented rule), the two reads
agree on a real version id in the versioned bucket, and an explicit
`?versionId=null` selection reports `null` on both reads.

**Output** (`cd tests/repros && ./run.sh repro_server_3`, exit status **1**):

```
  ok: fixture: CreateBucket /plain-bucket (never versioned)
  ok: fixture: PutObject /plain-bucket/k
  -- PutObject on the never-versioned bucket: x-amz-version-id header count 0 value []
  ok: CONTROL: PutObject omits x-amz-version-id for unversioned publication, as docs/compatibility/s3.md:446-450 states
  ok: fixture: CreateBucket /versioned-bucket
  ok: fixture: PutBucketVersioning Enabled
  ok: fixture: PutObject /versioned-bucket/k
  -- never-versioned bucket: GET status 200 x-amz-version-id=[] (header count 0)
  -- never-versioned bucket: HEAD status 200 x-amz-version-id=[null] (header count 1)
  ok: CONTROL: both reads of the unversioned object are 200
  FAILED: GET and HEAD report the same x-amz-version-id for the same unversioned object
  FAILED: HEAD of an object in a never-versioned bucket omits x-amz-version-id, as GetObject already does
  -- CONTROL versioned bucket: GET x-amz-version-id=[45dda79046d651db6ab22b5ae137da89aebed4224cb052ff10a9d76ab6530b12]  HEAD x-amz-version-id=[45dda79046d651db6ab22b5ae137da89aebed4224cb052ff10a9d76ab6530b12]
  ok: CONTROL: in a versioned bucket GET and HEAD agree on a real version id
  -- CONTROL explicit ?versionId=null: GET x-amz-version-id=[null]  HEAD x-amz-version-id=[null]
  ok: CONTROL: an explicit versionId=null selection reports null on both reads
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** HeadObject's `Set_Common_Headers`
(`s3_applications.adb:16619-16622`) always writes `x-amz-version-id`,
substituting the literal `null` when the object has no version, while the
GetObject responder (`:4189-4194`) writes it only when a version exists or the
request asked for one, and PutObject omits it for unversioned publication.
`docs/compatibility/s3.md:446-450` defines three distinct cases — omit for
unversioned, exact identity for enabled, `null` for suspended — so HEAD is
reporting an unversioned object with the spelling reserved for a suspended
bucket. Anyone doing HEAD-then-GET on the same key in a never-versioned bucket
sees two different answers; it is deterministic. I found no client behaviour
that changes as a result: the `null` value is accepted back as
`?versionId=null` on both reads. No existing test asserts either behaviour.
A fix is a one-line change at `:16619` to match `:4189-4194`, but it does
change an emitted response header, so a maintainer should confirm that no
downstream oracle in `tests/` or the six-server comparison depends on the
current spelling.

---

### SERVER-4: CompleteMultipartUpload `<Location>` is a path, not the URI the model documents

**Verdict:** CONFIRMED (new finding, promoted from the discovery report's
"Observations not counted", where it was recorded as "clients only echo it").

**Severity:** P2. It is a modelled output member carrying a value of the wrong
form on an ordinary success path. No stock client I know of dereferences it —
aws-cli and boto3 surface it verbatim — so it is contract drift rather than a
wrong result.

Verified by reading:

- `review/baseline/service-2.json`,
  `shapes.CompleteMultipartUploadOutput.members.Location`:
  `{"shape": "Location", "documentation": "<p>The URI that identifies the
  newly created object.</p>"}`. RFC 3986 requires a scheme in a URI;
  `/mpu-bucket/dir/object.bin` is a relative reference.
- The emitted document, captured by the repro below, contains
  `<Location>/mpu-bucket/dir/object.bin</Location>` alongside a correct
  `<Bucket>`, `<Key>` and composite `<ETag>`.
- `docs/compatibility/s3.md` says nothing about `Location`; the
  CompleteMultipartUpload row (`:71`) claims "atomic condition/size/checksum
  completion, strict signed control and body-boundary corpus, 46-case
  admission/certainty oracle" without excluding the result URI.

Refutation attempts that failed:

- Checked whether the model constrains `Location` to a scheme-relative or
  path form: the `Location` shape is a plain string; only the documentation
  says "URI".
- Checked whether the crate documents this as a boundary: it does not
  (`rg 'Location' docs/compatibility/s3.md` finds only GetBucketLocation and
  LocationConstraint prose).
- Considered whether a fix is mechanical: it is not entirely. Building an
  absolute URI requires choosing a scheme, and `Apps.Request_Scheme` is always
  `Plain_HTTP` in this crate (see the observations below), so a maintainer has
  to decide between deriving it from the `Host` header plus a configured
  scheme, or leaving the current path deliberately and documenting it. That
  policy choice is why I left this at P2 rather than proposing a fix.

**Repro:** `tests/repros/src/repro_server_4.adb`. It runs a one-part multipart
upload on `/mpu-bucket/dir/object.bin` and asserts that `<Location>` is an
absolute URI naming the object. Controls: the completion is 200 and the
`<Bucket>`, `<Key>` and composite `<ETag>` members are present and correct, and
`<Location>` does at least name the object.

**Output** (`cd tests/repros && ./run.sh repro_server_4`, exit status **1**):

```
  ok: fixture: CreateBucket /mpu-bucket
  ok: fixture: CreateMultipartUpload returns an UploadId
  ok: fixture: UploadPart is 200
  -- CompleteMultipartUpload status 200
  --    body <?xml version="1.0" encoding="UTF-8"?><CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Location>/mpu-bucket/dir/object.bin</Location><Bucket>mpu-bucket</Bucket><Key>dir/object.bin</Key><ETag>"dba2eb2ed95ff6ac73da0388b617482b-1"</ETag><ChecksumCRC64NVME>6d18xdZ10Zg=</ChecksumCRC64NVME><ChecksumType>FULL_OBJECT</ChecksumType></CompleteMultipartUploadResult>
  --    <Location> = [/mpu-bucket/dir/object.bin]
  ok: CONTROL: CompleteMultipartUpload is 200
  ok: CONTROL: the result names the bucket
  ok: CONTROL: the result names the key
  ok: CONTROL: the result carries a composite ETag
  FAILED: CompleteMultipartUpload <Location> is an absolute URI (the model documents 'The URI that identifies the newly created object')
  ok: CONTROL: <Location> at least names the object
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** Every successful CompleteMultipartUpload returns
`<Location>/bucket/key</Location>` where the pinned model documents "The URI
that identifies the newly created object". A caller that treats the member as
a URI — resolving it, storing it as a canonical object address, or comparing
it with what AWS or MinIO returned — gets a relative reference instead, and
must know the endpoint out of band to make it usable. It affects every
multipart completion and is deterministic. No existing test asserts either
form. Fixing it needs a maintainer decision rather than an edit: the server
would have to synthesise `scheme://host/bucket/key`, and this crate has no
scheme to use — `Apps.Request_Scheme` is `Plain_HTTP` for every request (the
runtime and both harnesses call `Apps.Create` without the `Scheme` argument),
so the choice is between a configured public base URI, deriving one from the
signed `Host` header, or keeping the path and documenting it as a boundary in
`docs/compatibility/s3.md`.

---

### SERVER-5: the modern default streaming payload sentinel is reported as `AuthorizationHeaderMalformed`

**Verdict:** PARTIALLY CONFIRMED (new finding, from the discovery report's
`aws-chunked` observation). The *rejection* is a documented limitation, so
that sub-claim is not a defect; what survives is the diagnostic. I also
refuted the discovery report's premise that such a request gets 501: it gets
`400 AuthorizationHeaderMalformed`, because the payload-hash shape check runs
inside `Verify_Request` and never reaches the aws-chunked arm.

**Severity:** P2 — wrong diagnostics. It is not P0, and I want to be explicit
about why, because the discovery brief raised the possibility: I verified with
the installed aws-cli that a stock PutObject over **plain HTTP** does *not*
use aws-chunked, and it succeeds against this server. The failing shape only
appears when the client's endpoint URL is `https://`, which for this crate
means a TLS terminator in front of it, since nothing in the repository ever
passes `Scheme => Secure_HTTPS` to `Apps.Create`.

Verified by reading:

- `src/flyology-object_storage-server-authentication.adb:139-140`:
  `(Payload_Hash /= SigV4.Unsigned_Payload and then not
  Encoding.Valid_SHA256_Hex (Payload_Hash))` is one disjunct of the `elsif`
  chain that `return (Status => Malformed_Credentials, others => <>)`, and it
  is evaluated at `:131-147`, before any signature verification (which happens
  in the `declare` block from `:176`). So the verdict does not depend on the
  signature being right, which is what makes the substitution in the repro
  faithful.
- `src/flyology-object_storage-server-s3_applications.adb:1889-1892`:
  `when Authentication.Malformed_Credentials => Send_Error (X, 400,
  "AuthorizationHeaderMalformed", "The authorization header is malformed",
  Resource);`
- `src/flyology-object_storage-server-s3_applications.adb:14891-14895` (and
  the UploadPart twin at `:12617-12621`): the arm that *would* answer this
  correctly, `Send_Error (X, 501, "NotImplemented", "aws-chunked payloads are
  not implemented", ...)`, is only reached when the payload hash has an
  ordinary shape.
- `docs/compatibility/s3.md:342-345` and `:457-460`: the exclusions are worded
  as "Inner SigV4 `aws-chunked` framing" and "SigV4 streaming `aws-chunked`
  payloads are also rejected before reading the source until a signature-chain
  decoder is available". `STREAMING-UNSIGNED-PAYLOAD-TRAILER` is the *unsigned*
  variant, and `:343` positively claims "fixed-length and HTTP
  transfer-chunked streaming and physical checksum trailers", so the document
  does not clearly cover the modern default, and says nothing about the status
  code a client receives.
- `src/flyology-object_storage-server-s3_applications.adb:6733` and `:6874`
  require `Apps.Request_Scheme (X) = Flyology.HTTP.Secure_HTTPS`; combined with
  `server/src/flyology_object_storage_server_runtime.adb:168-170` and
  `tests/src/s3_server_harness.adb:89-91` calling `Apps.Create` without a
  `Scheme` argument (default `Plain_HTTP` per flyology_http 0.1.3
  `Applications.Create`), no request this repository can produce is ever
  `Secure_HTTPS`.

**Client evidence.** With a TLS sniffer holding a self-signed certificate, the
same aws-cli/2.36.34 sends, for `s3api put-object` over `https://`:

```
PUT /live-bucket/tls.txt HTTP/1.1
Expect: 100-continue
Transfer-Encoding: chunked
Content-Encoding: aws-chunked
X-Amz-Trailer: x-amz-checksum-crc64nvme
X-Amz-Decoded-Content-Length: 15
x-amz-sdk-checksum-algorithm: CRC64NVME
X-Amz-Content-SHA256: STREAMING-UNSIGNED-PAYLOAD-TRAILER
Authorization: AWS4-HMAC-SHA256 Credential=..., SignedHeaders=content-encoding;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-sdk-checksum-algorithm;x-amz-trailer, Signature=...
```

and over plain `http://` it sends a fixed-length body with a header checksum
instead, which the server accepts (`aws s3 cp` and `aws s3api put-object` both
succeeded against the loopback listener in the SERVER-1 session).

Refutation attempts that failed:

- Tried to build the request with the harness's `Signed_Request
  (Hash_Override => "STREAMING-UNSIGNED-PAYLOAD-TRAILER")`: the crate's own
  `S3.SigV4.Sign` raises `Invalid_Signing_Input`, so the client side of this
  crate cannot even produce such a request. That is a separate, deliberate
  client restriction; the repro therefore substitutes the sentinel into an
  otherwise ordinary signed request, which is sound because the server decides
  before checking the signature (see the reading above).
- Checked whether the compatibility document already promises this exact
  status: it documents rejection but not the code, and words the exclusion as
  *SigV4* streaming. This is why the verdict is PARTIALLY CONFIRMED rather
  than DOCUMENTED LIMITATION.
- Checked whether a stock client over the transport this crate actually ships
  is refused: it is not (see the plain-HTTP result above). That is the reason
  this is P2 and not P0.

**Repro:** `tests/repros/src/repro_server_5.adb`. It sends PutObject and
UploadPart with `Content-Encoding: aws-chunked`,
`x-amz-decoded-content-length`, `x-amz-trailer` and
`x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER`, and asserts the
server does not blame the authorization header and answers the 501
`NotImplemented` it already uses for the same situation. Controls: the same
aws-chunked request with an ordinary hex payload hash gets exactly that 501, an
ordinary PutObject succeeds, and a well-shaped but wrong payload hash is still
rejected as `XAmzContentSHA256Mismatch`.

**Output** (`cd tests/repros && ./run.sh repro_server_5`, exit status **1**):

```
  ok: fixture: CreateBucket /stream-bucket
  -- PutObject with STREAMING-UNSIGNED-PAYLOAD-TRAILER + aws-chunked: status 400
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/stream-bucket/o</Resource></Error>
  FAILED: an unimplemented streaming payload encoding is not reported as a malformed authorization header
  FAILED: PutObject with STREAMING-UNSIGNED-PAYLOAD-TRAILER is 501 NotImplemented, like the aws-chunked path it belongs to
  -- UploadPart with STREAMING-UNSIGNED-PAYLOAD-TRAILER + aws-chunked: status 400
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/stream-bucket/o?partNumber=1&amp;uploadId=0123456789abcdef</Resource></Error>
  FAILED: UploadPart does not report the streaming sentinel as a malformed authorization header
  -- CONTROL aws-chunked with an ordinary signed payload hash: status 501 body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NotImplemented</Code><Message>aws-chunked payloads are not implemented</Message><Resource>/stream-bucket/o</Resource></Error>
  ok: CONTROL: aws-chunked with an ordinary hash is 501 NotImplemented
  ok: CONTROL: an ordinary PutObject still succeeds
  -- CONTROL a genuinely wrong (but well-shaped) payload hash: status 400 body <?xml version="1.0" encoding="UTF-8"?><Error><Code>XAmzContentSHA256Mismatch</Code><Message>The provided payload hash does not match the request body</Message><Resource>/stream-bucket/bad</Resource></Error>
  ok: CONTROL: a wrong payload hash is still rejected
```

**Description:** `Verify_Request` treats "the payload hash is not 64 hex digits
and not `UNSIGNED-PAYLOAD`" as the same failure as a broken Authorization
header (`server-authentication.adb:139-140`), and the server reports that as
`400 AuthorizationHeaderMalformed / "The authorization header is malformed"`
(`s3_applications.adb:1889-1892`). Since AWS turned on default integrity
protection, aws-cli v2 and boto3 send
`x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER` for PutObject and
UploadPart over HTTPS, so an operator who terminates TLS in front of this
server sees every upload fail with a message accusing their credentials, while
the real cause — an unimplemented payload encoding, which the crate documents
and reports correctly one branch away as `501 NotImplemented "aws-chunked
payloads are not implemented"` — is never mentioned. It is deterministic for
anyone in that deployment and invisible to anyone speaking plain HTTP. No
existing test covers a non-hex payload-hash sentinel. A fix needs a maintainer
decision on where the boundary belongs: either `Verify_Request` gains a
distinct status for a recognised-but-unimplemented streaming sentinel (a new
literal in the `Authentication` status type, which is a public interface
change) or the S3 application inspects `x-amz-content-sha256` before
authenticating, which changes what is decided before the signature is
verified and should not be done casually.

---

## Discovery observations examined and NOT counted

- **Pre-authentication classification (REFUTED as a disclosure concern).** The
  discovery report notes "an unauthenticated request to an unrecognised route
  receives `400 InvalidURI` or `501 NotImplemented` where AWS answers 403". I
  probed this directly: an unauthenticated request gets `403 AccessDenied` for
  a bucket that exists, a bucket that does not, a key that exists, a key that
  does not, an unknown subresource (`?unknown-subresource`), an implemented
  subresource (`?versioning`), an object-only subresource used on a bucket
  (`?torrent`), a subresource with a stray parameter (`?uploads&unknown=1`)
  and `POST /probe/k?restore`. Only two classes answer before authentication:
  a target the parser rejects (a key over 1024 bytes, `%00` in a key) gives
  `400 InvalidURI`, and `OPTIONS`/`PATCH` give `501 NotImplemented`. Both are
  purely syntactic and independent of any stored state, so an unauthenticated
  peer learns nothing about buckets, keys or which subresources this build
  implements. Nothing reaches a backend. I record this as a deliberate
  deviation from AWS's uniform 403, not a finding.
- **Exception containment (REFUTED — the containment holds).** Over the
  loopback listener I sent a signed PutObject declaring `Content-Length: 16`
  and then wrote only 4 body bytes. The application did not raise out of
  `Handle`: the exchange produced no response (the server waited for the
  missing bytes until the request timeout and closed), and the very next
  request on the listener was served normally (`GET /probe/k` → 200
  `payload`). In process, where the transport reports end of input instead of
  stalling, the same shape is answered `400 InvalidRequest / "Invalid request
  body framing"`. So both under-length forms are contained; there is no
  escaping exception and no deadlock.
- **`aws-chunked` rejection itself.** Rejecting aws-chunked framing is stated
  in `docs/compatibility/s3.md:342-345` and `:457-460`, and I treat the
  rejection as a DOCUMENTED LIMITATION. Only the diagnostic is counted, as
  SERVER-5 above.
- **`Apps.Request_Scheme` is always `Plain_HTTP`.** Neither
  `server/src/flyology_object_storage_server_runtime.adb:168-170` nor
  `tests/src/s3_server_harness.adb:89-91` passes a `Scheme` to `Apps.Create`,
  and flyology_http 0.1.3 defaults it to `Plain_HTTP`. Consequently
  `UNSIGNED-PAYLOAD` is always answered `400 InvalidRequest /
  "UNSIGNED-PAYLOAD requires a secure transport"` (I observed this), and the
  WriteGetObjectResponse admission at `:6733` and the SSE gate at `:5371` can
  never be satisfied by this repository's own server. I did not raise this as
  a finding — the crate ships no TLS listener, so the behaviour is consistent
  with its scope — but it is the reason SERVER-5 and the `Location` question
  in SERVER-4 both stop short of a mechanical fix, and a maintainer may want
  the constraint written down.
- **PutObjectTagging answers `501 NotImplemented` to any SDK checksum**
  (`s3_applications.adb:15889`). Folded into SERVER-1 rather than counted
  separately, because it is the same client-facing failure with a different
  status code.
