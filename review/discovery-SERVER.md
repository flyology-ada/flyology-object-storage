# Correctness discovery: SERVER (S3 application, routing, authorisation, operations)

Scope: `src/flyology-object_storage-server-s3_applications.ads` (whole) and
`.adb` read in these regions: with-clauses/constants/exceptions 1-230; error
senders `Send_Error`/`Send_Authentication_Error`/`Send_Backend_Error`
1861-2017; the `Handle` declarative part covering target/method/query
constants and every query detector and parser 2088-3565 (Parse_ACL_Query,
Parse_Object_Lock_Query, Parse_Point_Configuration_Query,
Parse_Configuration_List_Query, Parse_Directory_Bucket_List_Query,
version-selector mapping); `Set_Object_Metadata_Headers`, `Request_IO`
(request source with payload-hash/Content-MD5/checksum/trailer/length
enforcement), `Response_IO`, `Torrent_Response_IO`,
`Annotation_Response_IO` 3918-4526; `Body_Length`, `Read_Document`,
`Verify_Document_Checksum`, `Read_Bucket_Scalar_Control`,
`Read_Object_Lock_Document`, `Read_Metadata_Document`,
`Check_Expected_Bucket_Owner`, `Validate_Private_Canned_ACL`,
`Copy_Result_XML` 3744-3918 and 4526-5482; the pre-authentication
classification 6014-6690, route configuration and `Verify_Request` call
6690-6700, WriteGetObjectResponse admission 6700-6850, SSE-C/encryption
gating, query-invalid mapping and body-policy application 6850-7096; the
operation arms ListBuckets, ListDirectoryBuckets, CreateBucket, HeadBucket,
Put/GetBucketAcl, GetBucketLocation, PutBucketVersioning,
Put/GetObjectLockConfiguration, DeleteBucket, ListObjects v1/v2,
ListObjectVersions, ListMultipartUploads, CreateMultipartUpload, ListParts,
UploadPart, UploadPartCopy, CompleteMultipartUpload, AbortMultipartUpload,
RenameObject (header gating only), CopyObject, PutObject,
Put/GetObjectLegalHold, Put/GetObjectRetention (header gating and body
admission), GetObjectAttributes, HeadObject, GetObjectTorrent, GetObject,
DeleteObject, DeleteObjects, the Content-MD5 gates of PutBucketTagging,
PutPublicAccessBlock, PutBucketCors, PutBucketEncryption/OwnershipControls,
PutBucketPolicy, PutBucketReplication/Website, PutObjectTagging, and the
`Handle` exception handler 17970-18068. Not read line by line:
Create_Session, SelectObjectContent, UpdateObjectEncryption, RestoreObject
bodies, the bucket analytics/metrics/inventory/intelligent-tiering/
lifecycle/logging/notification/website/replication/policy bodies beyond their
admission gates, the metadata-configuration provider flow 5482-6014, and
`Assess_Bucket_Policy` 661-1469. Also read: `-server.ads`,
`-server-metadata_results.ads`, `-server-object_lambda_responses.ads`,
`-server-authentication.ad?` (only which target/method/headers reach the
verifier, not SigV4 internals); `src/flyology-object_storage-s3-requests.ad?`;
`Valid_Object_Key`/`Valid_Bucket_Name`, `Resolve_Range`,
`Evaluate_Object_Read/Copy/Write_Conditions` in
`src/flyology-object_storage.adb`; `Backends` contracts for `Source_Length`,
`Copy_Object`, `Delete_Object`, `Get_Object`, `Get_Object_Attributes`,
`Read_Conditions`; `Backends.Memory` generation selection 272-331; callers
`tests/src/s3_server_harness.ad?`, `s3_memory_server.adb`,
`s3_files_server.adb`, `server/src/flyology_object_storage_server_runtime.adb`
(instantiation, `Handlers.Serve` limits, absence of TLS); flyology_http 0.1.3
`Flyology.HTTP.Server.Applications` spec (contracts used), `Add_Header`/
`Set_Header` validation in its body, `Connection_Handlers.Serve` exception
handling, `Max_Request_Body`. Reference material:
`docs/compatibility/s3.md` (table rows and the DeleteObjects, PutObject/
UploadPart, server-boundary, HeadObject/GetObject, ListObjects and s3t
sections), `review/baseline/service-2.json` (httpChecksum traits, ContentMD5
membership, HeadObject/GetObject output bindings and documentation),
`tests/scripts/run-s3-server-slice.sh` (pinned s5cmd v2.3.0). Existing
coverage inspected: `tests/src/s3_server_application_corpus.adb` assertions
around DeleteObjects checksums (16039-16160), DeleteObject marker headers
(17735-17760, 18190-18210), metadata 405s (4490-4515), and helper
`Signed_Delete_Objects_Request`.

Severity rubric: P0 memory/aliasing unsafety, security (signature bypass,
traversal, secret exposure, authz bypass), data loss/durability, hang or
deadlock, or interop-breaking protocol violation that a stock client or
server rejects; P1 wrong result or unexpected exception on valid input via a
reachable path, or a documented contract violated; P2 edge-case
incorrectness, wrong diagnostics, contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| SERVER-1 | Content-MD5 is mandatory on DeleteObjects and most configuration PUTs although the pinned model satisfies `requestChecksumRequired` with `x-amz-checksum-*` | P1 | High |
| SERVER-2 | GET/HEAD of a delete marker returns a plain 404 without `x-amz-delete-marker`, and an exact-version marker read returns 404 instead of 405 | P2 | High |

---

### SERVER-1: Content-MD5 is mandatory on DeleteObjects and most configuration PUTs although the pinned model satisfies `requestChecksumRequired` with `x-amz-checksum-*`

**Location:** `src/flyology-object_storage-server-s3_applications.adb:17675-17684` (DeleteObjects); `:10360-10370` (PutBucketVersioning); `:15897-15904` (PutObjectTagging); `:10128-10137` (PutBucketPolicy); `:8012-8019` (PutBucketTagging); `:5285-5291` (`Read_Object_Lock_Document`, used by PutObjectLockConfiguration, PutObjectLegalHold, PutObjectRetention); `:8823-8824` with `:9042-9046` (PutBucketEncryption, PutBucketOwnershipControls); `:9905` (PutBucketReplication, PutBucketWebsite); `:3858-3861` (PutBucketAcl, PutObjectAcl); `:5461-5464` (`Read_Metadata_Document`, metadata configuration creates/updates).

**Severity:** P1. **Confidence:** High (code path and model); the statement about which stock clients stopped sending Content-MD5 is from memory, unverified, and is marked as such below.

**Evidence:**

`src/flyology-object_storage-server-s3_applications.adb:17675-17684`
```ada
                  if MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      ((if MD5_Count = 1
                        then Apps.Request_Header (X, "content-md5") else ""),
                       16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "DeleteObjects requires one valid Content-MD5 header",
                        Target_Text);
```

The same arm already accepts and verifies a flexible checksum (`Verify_Checksum`, `:17624-17672`), so the CRC32/SHA256 path is implemented, but only in addition to Content-MD5, never instead of it.

`src/flyology-object_storage-server-s3_applications.adb:10360-10370`
```ada
                  if MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      ((if MD5_Count = 1
                        then Apps.Request_Header (X, "content-md5") else ""),
                       16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutBucketVersioning requires one valid " &
                        "Content-MD5 header",
```

`src/flyology-object_storage-server-s3_applications.adb:15897-15904`
```ada
                     if MD5_Count /= 1 or else Length.Kind /= Backends.Known
                       or else Length.Bytes > Maximum_Object_Tagging_Body
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "PutObjectTagging requires bounded " &
                           "Content-Length " &
                           "and Content-MD5", Target_Text);
```

Pinned model, `review/baseline/service-2.json` (queried with python3):

```
DeleteObjects:          httpChecksum={requestAlgorithmMember: ChecksumAlgorithm, requestChecksumRequired: True}  ContentMD5 member: ABSENT
PutBucketVersioning:    httpChecksum={..., requestChecksumRequired: True}  ContentMD5 member: present, optional
PutObjectTagging:       httpChecksum={..., requestChecksumRequired: True}  ContentMD5 member: present, optional
PutBucketPolicy:        httpChecksum={..., requestChecksumRequired: True}  ContentMD5 member: present, optional
PutBucketTagging, PutObjectLockConfiguration, PutObjectLegalHold, PutObjectRetention,
PutBucketAcl, PutObjectAcl, PutBucketReplication, PutBucketWebsite, PutBucketEncryption,
PutBucketOwnershipControls, CreateBucketMetadata[Table]Configuration: same shape
(requestChecksumRequired: True, ContentMD5 optional).
```

The model's `httpChecksum` trait is the contract a model-driven SDK implements: `requestChecksumRequired: true` is satisfied by the algorithm named in `requestAlgorithmMember` (sent as `x-amz-sdk-checksum-algorithm` + `x-amz-checksum-<alg>`); `ContentMD5` is a plain optional member, and for `DeleteObjects` it does not exist in the input shape at all, so a client generated from this model has no modeled way to send Content-MD5 on DeleteObjects. The server's own `Verify_Checksum` at `:17624-17672` shows it can validate the modeled flexible checksum over the exact body, so the integrity purpose of the rule is already met without Content-MD5.

Documented contract (`docs/compatibility/s3.md:506-508`) states the requirement as intended behaviour: "DeleteObjects ... requires canonical Content-MD5 over the exact admitted body." The compatibility table row for DeleteObjects is therefore accurate to the code; the finding is that this documented policy contradicts the pinned protocol model, which is the stated source of truth for shapes and bindings.

**Failure scenario:** A stock model-driven client issues `POST /bucket?delete` with a valid SigV4 signature, `x-amz-sdk-checksum-algorithm: CRC32`, `x-amz-checksum-crc32: <correct>` and no `Content-MD5` (from memory, unverified: botocore >= 1.36 / aws-cli v2 >= 2.23 and AWS SDK for Java 2.30+ do exactly this by default and no longer inject Content-MD5 for `requestChecksumRequired` operations; older SDKs sent Content-MD5). Authentication succeeds (`:6697`), the body is read and hashed (`:17483-17495`), then `:17675` sees `MD5_Count = 0` and the server answers `400 InvalidRequest "DeleteObjects requires one valid Content-MD5 header"`; nothing is deleted. The same client's `put-bucket-versioning`, `put-object-tagging`, `put-bucket-policy`, `put-bucket-tagging`, `put-object-retention`, `put-object-legal-hold`, `put-object-lock-configuration`, `put-bucket-encryption`, `put-bucket-ownership-controls`, `put-bucket-acl`, `put-object-acl`, `put-bucket-replication`, `put-bucket-website` calls fail the same way. Older clients that still send Content-MD5 (s5cmd v2.3.0 on aws-sdk-go v1, the crate's own typed client which "always generates and signs Content-MD5", `docs/compatibility/s3.md:526-527`) are unaffected, which is why the existing slices pass.

**Reproduction test sketch:** Through the in-process loopback application (`tests/src/s3_server_harness.adb` + `s3_memory_server.adb`), after `PUT /b` and `PUT /b/k`: send the corpus's `Signed_Delete_Objects_Request (Payload, Include_MD5 => False, Extra_Headers => "x-amz-sdk-checksum-algorithm: CRC32" & CRLF & "x-amz-checksum-crc32: " & Checksum_Value (Core.CRC32, Payload) & CRLF)`. Expected (per model): `200 OK` with `<Deleted><Key>k</Key></Deleted>`. Actual: `400` with `<Code>InvalidRequest</Code>` and the object still present. Same shape for `PUT /b?versioning` with a CRC32 checksum header and no Content-MD5: expected 200, actual 400. A Docker run of aws-cli v2 (current) `s3api delete-objects` against `s3_memory_server` would show the same, but only the loopback form is needed.

**Existing coverage:** `tests/src/s3_server_application_corpus.adb:16039-16045` asserts the opposite behaviour ("DeleteObjects accepted a missing Content-MD5" expects `InvalidRequest`), but that case sends neither Content-MD5 nor a flexible checksum, so it does not distinguish "no integrity header at all" (which the model also rejects) from "flexible checksum instead of Content-MD5" (which the model accepts). `:16085-16112` sends every flexible algorithm together with Content-MD5 (`Include_MD5` defaults to `True`), never instead of it. `tests/scripts/run-s3-server-slice.sh:107` exercises DeleteObjects only through s5cmd v2.3.0 (pinned by digest), whose SDK still sends Content-MD5.

**Refutation attempts:** (1) Checked whether the model marks `ContentMD5` required on any of these operations: it does not; for DeleteObjects the member is absent. (2) Checked whether the server's flexible-checksum verification could be an alternative acceptance path: `:17675` runs before `Checksum_Status` is consulted, so a valid CRC32 never bypasses the MD5 check. (3) Checked `Read_Bucket_Scalar_Control` (`:5165-5200`, `Require_Checksum`), `Put_Bucket_Lifecycle*`/`PutBucketLogging`/`PutBucketNotification*` (`:8823-8832`, `:9082-9092`) and PutObject/UploadPart: those routes accept an SDK checksum in place of Content-MD5, which shows the crate already implements the model-conformant rule elsewhere; the affected routes are the ones listed above. (4) Checked whether the documentation frames this as a deliberate compatibility boundary comparable to the `aws-chunked` note (`docs/compatibility/s3.md:458-460`): it does not; it presents Content-MD5 as the integrity rule without noting that model-driven clients cannot send it on DeleteObjects.

---

### SERVER-2: GET/HEAD of a delete marker returns a plain 404 without `x-amz-delete-marker`, and an exact-version marker read returns 404 instead of 405

**Location:** `src/flyology-object_storage-server-s3_applications.adb:17230-17270` (GetObject result mapping); `:16880-16957` (HeadObject result mapping); `:1916-2015` (`Send_Backend_Error`, no marker-aware branch); `src/flyology-object_storage.ads:39-62` (`Status` has no marker outcome); `src/flyology-object_storage-backends-memory.adb:272-283, 322-331` (marker generations resolve to index 0, i.e. `Not_Found`).

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-memory.adb:322-331`
```ada
      function Selected_Object_Index
        (Bucket : String; Key : String; Selector : Version_Selector)
         return Natural
      is
         Selected : constant Natural :=
           Selected_Generation_Index (Bucket, Key, Selector);
      begin
         return
           (if Selected /= 0
              and then not Objects (Selected).Is_Delete_Marker
            then Selected else 0);
      end Selected_Object_Index;
```

`src/flyology-object_storage-server-s3_applications.adb:17253-17262`
```ada
                  elsif not Apps.Wire_Response_Started (X) then
                     if Result = Invalid_Range and then Info.Size >= 0 then
                        Apps.Set_Header
                          (X, "Content-Range",
                           "bytes */" & Decimal (Info.Size));
                     end if;
                     Send_Backend_Error (X, Result, False, Target_Text);
```

`src/flyology-object_storage-server-s3_applications.adb:1929-1936`
```ada
         when Not_Found =>
            Send_Error
              (X, 404,
               (if Is_Bucket then "NoSuchBucket" else "NoSuchKey"),
```

The only place the server emits `x-amz-delete-marker` is DeleteObject (`:17443-17447`) and the WriteGetObjectResponse forwarding table (`:4597`).

Pinned model, `review/baseline/service-2.json`, `GetObjectOutput.DeleteMarker` documentation (also present on `HeadObjectOutput`):
```
If the current version of the object is a delete marker, Amazon S3 behaves as if the
object was deleted and includes x-amz-delete-marker: true in the response.
If the specified version in the request is a delete marker, the response returns a
405 Method Not Allowed error and the Last-Modified: timestamp response header.
```

**Failure scenario:** Bucket `b` has versioning enabled; `PUT /b/k` then `DELETE /b/k` (creates marker `m`, `:17423-17447` reports `x-amz-delete-marker: true`). (a) `GET /b/k` or `HEAD /b/k`: the backend resolves the current generation to the marker, `Selected_Object_Index` returns 0, `Result = Not_Found`, and the server sends `404 NoSuchKey` with no `x-amz-delete-marker` header, so a versioning-aware client cannot distinguish "deleted by marker" from "never existed". (b) `GET /b/k?versionId=m`: same path, `404 NoSuchKey`, where the model specifies `405 Method Not Allowed` plus `Last-Modified`. `Status` (`flyology-object_storage.ads:39-62`) has no value the backend could return to let `Send_Backend_Error` produce either response, so this cannot be fixed in the server alone.

**Reproduction test sketch:** In-process loopback (`s3_memory_server`): `PUT /b`, `PUT /b?versioning` (Enabled), `PUT /b/k`, `DELETE /b/k` (capture `x-amz-version-id: m`). Then `HEAD /b/k`: expected `404` with `x-amz-delete-marker: true`; actual `404` without it. Then `GET /b/k?versionId=m`: expected `405 Method Not Allowed` with `Last-Modified`; actual `404 NoSuchKey`. The corpus helper `Signed_Delete_Object_Request` plus `Signed_Request ("GET", "/b/k?versionId=" & M, "")` express both.

**Existing coverage:** `tests/src/s3_server_application_corpus.adb:18196-18207` asserts the DeleteObject marker headers; `:17754` asserts an exact-version delete does not carry the header. No test reads a marker through GET/HEAD and asserts either the header or 405 (`rg '405|x-amz-delete-marker'` finds only metadata-configuration 405s and DeleteObject/WriteGetObjectResponse cases). `docs/compatibility/s3.md:539-541` documents publication and removal of markers but not their read-side surfacing.

**Refutation attempts:** (1) Looked for a marker-aware branch in HeadObject/GetObject or in `Send_Backend_Error`: none; the only `x-amz-delete-marker` emitters are DeleteObject and the Object Lambda forwarder. (2) Checked whether `Status` carries a marker variant the server ignores: it does not (`flyology-object_storage.ads:39-62`), so the omission is structural rather than a missed mapping. (3) Checked whether the documentation scopes read-side marker behaviour out: `docs/compatibility/s3.md:59` (HeadObject) and `:851-858` (GetObject) list exclusions (part selection, non-null versions, SSE-C) but not delete-marker reads, and the ListObjectVersions row (`:67`) claims a "retained-generation/delete-marker state machine" without a read-side caveat.

---

## Areas reviewed with no findings

- Authentication ordering and route/verification agreement: `Verify_Request` is called once at 6697 after classification and before any body byte is read or any backend call; it verifies the same `Apps.Request_Target`/`Request_Method` strings the application classifies (`authentication.adb:210-213`, body 2535-2536), so the signed target and the executed bucket/key/query cannot diverge. Every arm runs after the `Authenticated` check; the only pre-authentication responses are `InvalidURI`/`NotImplemented` (6014-6690), which never reach the backend. WriteGetObjectResponse additionally requires HTTPS + UNSIGNED-PAYLOAD + host/route agreement after authentication.
- Between admission and body acceptance: `Apps.Apply_Body_Policy` (7060-7074) runs only after authentication and header validation, so `100 Continue` is never emitted for a rejected request; non-body routes require `Body_Complete` before proceeding.
- Target parsing (`Requests.Parse_Target`): strict percent escapes, `#` rejected, first `?` starts the query, `/bucket/` classifies as bucket, `//key` yields a key with a leading slash (allowed by `Valid_Object_Key`), `%2F` in a bucket segment fails bucket validation, NUL-containing or over-1024-byte keys are `InvalidURI`; `Query_String` is the raw text so `x-id`/subresource matching is exact.
- Declarative-part parsers: every parser elaborated in `Handle`'s declarative region (where an exception would escape the handler) either guards `Constraint_Error` (Parse_ACL_Query, Parse_Object_Lock_Query, Parse_Point/Configuration_List_Query, Parse_Directory_Bucket_List_Query, Query_Mentions_ACL) or raises only its typed `Malformed_*` exception which is caught (`Is_Valid_Tagging_Query`; `Tagging.Decode_Component` raises `Malformed_Tagging_Query`).
- Request bodies: every buffered `Request_Source` aggregate sets `Maximum` (CreateBucket 64 KiB, DeleteObjects/Tagging/Versioning codec limits, CompleteMultipartUpload 2 MiB, XML default limits for configuration PUTs, 5 GiB PutObject, `Maximum_Multipart_Part_Size` UploadPart); `Request_IO.Read` rejects over-length or under-length bodies versus Content-Length, verifies `x-amz-content-sha256`, Content-MD5, header and trailer checksums before the source reports `Finished`, and every commit path asserts `Source.Completed` so a backend cannot commit an unverified body; Content-Length duplicates and malformed values are rejected (`Body_Length`); `Expect: 100-continue` is deferred to `Apply_Body_Policy`; chunked transfer coding is accepted for all streaming routes except PutObjectTagging (requires a known length, documented).
- Response framing: `Response_IO.Begin_Object` validates the backend's announced range against the snapshot, emits quoted ETag, IMF-fixdate Last-Modified (`HTTP_Last_Modified` verified against `Ada.Calendar.Formatting.Image` offsets), `Accept-Ranges: bytes`, `Content-Range: bytes first-last/size`, 206/200 with an exact 64-bit Content-Length; `Write` enforces the announced length; unsatisfiable ranges return 416 with `Content-Range: bytes */size`; a zero-length object with any Range is 416 (matches the `Resolve_Range` contract); multi-range headers are rejected as documented in `S3.Core`.
- Conditional reads: duplicate/empty/malformed `If-*` headers are 400; precedence (If-Match over If-Unmodified-Since, If-None-Match over If-Modified-Since) is delegated to `Evaluate_Object_Read_Conditions`, which implements it; 304 responses carry ETag/Last-Modified; CopyObject source conditions map `Not_Modified` to 412 (`Evaluate_Object_Copy_Conditions`).
- Error XML: `Send_Error` always emits Code/Message/Resource/RequestId with `application/xml`; status mapping in `Send_Backend_Error` (404/409/400/416/412/304/403/501/503) and the exception handler (400 for framing/hash/digest/XML failures, 500 otherwise) never sends a second response once the wire has started (`Wire_Response_Started`/`Mark_Failed`), and every unexpected Ada exception is converted rather than escaping `Handle`.
- Header emission safety: PutObject/CopyObject/CreateMultipartUpload metadata values are validated as printable ASCII or well-formed UTF-8 (`Valid_UTF8_Header_Value`), and `response-*` overrides reject control bytes, both stricter than flyology_http's `Validate_Header_Value` (controls and DEL only), so no stored value can make `Set_Header` raise on read.
- Multipart: UploadPart part numbers are bounded by `Multipart.Parse_Query` and `Multipart_Part_Number` (1..10000); UploadPart/Complete reconcile the initiation's algorithm and method through `List_Multipart_Parts` before mutation; composite uploads require per-part checksums; Complete strips quotes from part ETags, validates per-part checksum presence against the upload method, maps `Invalid_Part`/`Invalid_Part_Order`/`Entity_Too_Small` to their S3 codes, quotes the result ETag and sets `x-amz-version-id`; ListParts/ListMultipartUploads paginate with `NextPartNumberMarker`/`NextKeyMarker`+`NextUploadIdMarker` only when truncated; Abort on an unknown upload is `404 NoSuchUpload`; UploadPartCopy requires a bounded `x-amz-copy-source-range`.
- DeleteObjects: quiet mode suppresses only successes, per-key results stay in request order, versioned entries carry `DeleteMarker`/`DeleteMarkerVersionId`, the 1,000-key bound and malformed XML are `MalformedXML` through `Deletions.Parse_Request`, and an all-invalid entry set still checks bucket existence.
- Listings: `max-keys`/`max-parts`/`max-uploads` 0..1000 map onto `List_Limit` 0..1000 and `max-buckets` 1..10000 onto `Bucket_List_Limit` without a Constraint_Error path; v1 `NextMarker` only with a delimiter; v2 `KeyCount` includes common prefixes and the continuation token is validated against bucket/prefix/delimiter; encoding-type=url encodes keys, prefixes, delimiters and markers.
- Copy: `x-amz-copy-source` is parsed by the same strict target parser (percent-decoded key, `?versionId=` only), source-not-found errors name the source resource, `x-amz-copy-source-version-id`/`x-amz-version-id` are emitted on success, and metadata/tagging directives are enforced.
- Resource bounds and hangs: object bodies stream through 16 KiB reads and backend sinks (no whole-object buffering); every backend call receives `Apps.Cancellation`/`Apps.Deadline`; `Request_IO.Read` checks the token; cancellation and timeout re-raise after `Mark_Failed` and are handled by `Connection_Handlers.Serve` by closing the connection; the listener limits (`Handlers.Serve` in harness and runtime) bound requests per connection and connection age.

## Observations not counted

- `aws-chunked` (`STREAMING-*` payload hashes and `Content-Encoding: aws-chunked`) is rejected on PutObject/UploadPart with 501 after full header validation; documented as an explicit server boundary (`docs/compatibility/s3.md:342-345, 458-460`). Note that the `server` runtime has no TLS listener, so the HTTPS-only UNSIGNED-PAYLOAD path is unreachable there and a plain-HTTP stock client must sign payloads.
- SigV4 presigned (query-string) authentication is not implemented; such requests get `403 AccessDenied` (`Missing_Credentials`). Documented as "planned, not claimed" (`docs/compatibility/s3.md:78`).
- Pre-authentication responses: an unauthenticated request to an unrecognised route receives `400 InvalidURI` or `501 NotImplemented` (6014-6690) where AWS answers 403; nothing reaches the backend, so this only discloses route recognition. OPTIONS/PATCH on any target is 501 rather than 405/403.
- HeadObject always emits `x-amz-version-id: null` for unversioned objects (16663-16667) while GetObject omits the header unless a version was requested; AWS omits it on unversioned buckets. Harmless to clients, inconsistent between the two reads.
- HeadObject with a satisfiable `Range` answers 200 with the range's Content-Length and no Content-Range; this matches the pinned model's HeadObject `Range` documentation ("only the ContentLength is affected"), so it is not counted.
- CopyObject with the default COPY metadata directive and any replacement metadata header answers `400 InvalidRequest` (14396-14411); AWS ignores such headers (from memory, unverified). CopyObject onto itself with COPY is accepted; AWS rejects it with 400 (from memory, unverified).
- CompleteMultipartUpload `Location` is the path `/bucket/key` rather than an absolute URL; clients only echo it.
- CreateMultipartUpload rejects user metadata, Cache-Control/Content-Disposition/Content-Encoding/Content-Language/Expires, storage class, tagging and object-lock headers with 501, so `aws s3 cp --metadata ...` of a file above the multipart threshold fails; documented as explicit capability rejection (`docs/compatibility/s3.md:71`). Related, low confidence: an upload created without `x-amz-checksum-algorithm` defaults to CRC64NVME/FULL_OBJECT and any UploadPart carrying a different algorithm (for example a client-defaulted CRC32) is rejected with "differs from initiation" (12646-12655); whether AWS also rejects that combination could not be established from the model.
- CreateBucket on an existing bucket returns `409 BucketAlreadyOwnedByYou`; AWS us-east-1 returns 200 for the owner (legacy quirk), MinIO returns 409. Not counted.
- GetObjectAttributes never emits `StorageClass` even when requested (16305-16330); omitted rather than fabricated, per the documented profile.
- Per-request budget is `Timeout => 60.0` in both the harness and the runtime (`s3_server_harness.adb:104`, runtime 179), so a 5 GiB PutObject must complete within 60 s; policy value, not counted.
- `Read_Document` appends byte-by-byte into an `Unbounded_String` for buffered documents; bounded by each route's `Maximum` (at most 2 MiB), so a performance rather than correctness note.
- flyology_http answers `204 No Content` when a handler returns without responding (`connection_handlers.adb:141-152`); I found no arm that returns silently, but the fallback would mask such a regression as a success.
- PutObject `If-Match` against a missing key yields 412 (`Evaluate_Object_Write_Conditions`); AWS documents 404 NoSuchKey for the DeleteObject case in the model and (from memory, unverified) the same for PutObject. Core-area evaluator, not counted here.
