{{MODEL_FIRST_ITEMS}}
- SPARK contracts, existing boundary. {{ISSUE:WIRE-2}} (the entity-tag list grammar in the root
  validation package) and {{ISSUE:CLIENT-LOW-7}} (the model-scalar integer validator, if it sits in
  `Flyology.Object_Storage.S3.Requests`) are one-step grammar decisions inside the nine proved units:
  express the corrected grammar as a contract so the wrong acceptance is unrepresentable, and run
  `tools/prove.sh`. {{ISSUE:WIRE-3}} (unrecognised Range unit) belongs to the server's admission code,
  outside the boundary, but its range parser is the proved one; keep the parser's contract unchanged
  and fix the caller.
- Bounded TLA+ models, new (DECISION: which to build first and the bounds; the "TLA+ assurance"
  section already answers whether). Three state machines produced the findings that span several
  steps and meet that section's bar. Each should get a `_broken` configuration that reproduces the
  filed bug as a TLC counterexample before the fix, a TLAPM proof of the safety invariant where
  TLAPS can express it, and trace replay through the shared `flyology-ada/tla` harness:
  - multipart-upload listing pagination for {{ISSUE:BACKEND-MEMORY-1}}: uploads for one key
    initiated in time order with upload IDs in an unrelated lexical order, pages of one, the paired
    key and upload-id markers, and the invariant that a full walk returns every upload exactly once.
    The model decides which of the two S3 ordering rules the marker follows (the DECISION in that
    issue) before the code does. Bound it to three uploads and two keys.
  - object versioning transitions and delete-marker reads for {{ISSUE:SERVER-2}},
    {{ISSUE:BACKEND-FILES-6}} and {{ISSUE:BACKEND-MEMORY-2}}: Unconfigured, Enabled and Suspended
    states, the null version, delete markers as current versions, exact-version deletes, version-ID
    uniqueness after deletes, and same-key copies from a selected version; the invariant that a
    version ID is never reused and that a read of a marker is distinguishable from a missing key.
    Bound it to one key and three generations.
  - the SQLite catalog gate for {{ISSUE:BACKEND-SQLITE-3}} and {{ISSUE:BACKEND-SQLITE-1}}: gate
    acquire and release across the normal and exception paths of a copy with annotation leases and
    a read that opens its payload after release, with the invariants that every acquire is released
    on every path and that an open payload handle outlives a concurrent unlink. Bound it to two
    tasks. If the maintainer prefers, the release-on-every-path property can be a SPARK-style
    structural argument on the handler ordering instead; the gate itself is a protected object, so
    the model is small either way.
  Until a model exists, the exhaustive sequence tests in the conformance programs are the
  evidence; write them as tables of sequences. The remaining issues are single-step decoding,
  encoding or admission rules, which that policy says are better served by Ada/SPARK contracts and
  tests than by a model.

{{LAYERS}}

## Layer 1 — wire core, SigV4 and the server application

Everything a stock client passes through. {{ISSUE:SERVER-1}} must land first: it is the only P0
here and the one every stock client with default integrity protection hits.

P0
1. **{{ISSUE:SERVER-1}} Content-MD5 is the only accepted integrity header on the
   `requestChecksumRequired` routes, so stock aws-cli v2 and boto3 are refused on DeleteObjects,
   PutBucketVersioning and the tagging and configuration writes.** Accept the `x-amz-checksum-<alg>`
   group wherever Content-MD5 is demanded, through the `Verify_Document_Checksum` path that already
   exists; keep Content-MD5 as an alternative. DECISION: whether Content-MD5 stays mandatory when no
   checksum header is present. Regression: the stock-client capture in the issue, in
   `tests/src/s3_server_application_corpus.adb` and the s5cmd or aws-cli slice.
2. **{{ISSUE:S3-DOMAIN-A-5}} The server rejects an unqualified `<VersioningConfiguration>` root,
   which is what `mc version enable` sends.** Accept the root with and without the S3 namespace,
   as every other request codec already does. Items 2, 3 and 4 are one change class; do them in
   one PR only if the maintainer agrees to a shared helper.
3. **{{ISSUE:S3-DOMAIN-B-1}} `Deletions.Parse_Request` demands the S3 namespace on every element of a
   `<Delete>` body, which the MinIO client and s3cmd do not send.** Accept the namespace-free form as
   the other request codecs do. Same change class as item 2; lands with it.
4. **{{ISSUE:S3-DOMAIN-B-2}} `Tagging.Parse_Bucket` rejects a namespace-free `<Tagging>` on
   PutBucketTagging (`mc tag set`) while PutObjectTagging accepts it.** Same change class as items 2
   and 3.

P1
3. **{{ISSUE:WIRE-1}} A C0 control byte in an accepted key makes every listing without
   `encoding-type=url` answer 500.** Escape or reject at the boundary; the crate's own high-level
   client sends no `encoding-type`, so it hits this by default. DECISION: reject such keys at PUT
   (a policy the matrix must state) or emit character references in listings. Pair with
   {{ISSUE:WIRE-4}}.
4. **{{ISSUE:WIRE-4}} A key containing a carriage return is reported as a different key by
   unencoded listings.** Same site and same decision as item 5.
5. **{{ISSUE:SIGV4-2}} `Static_Credentials.Create` accepts a principal of 257 to 1,024 bytes that
   admission rejects, so every signed request is 403.** DECISION: reject at `Create`, accept in
   `Valid_Principal`, or lower the documented maximum; the issue lists the three.
6. **{{ISSUE:SERVER-2}} Reading a key hidden by a delete marker is a bare 404, and reading the
   marker's own version is 404 instead of 405 with `x-amz-delete-marker`.** DECISION: a delete-marker
   signal in the `Backends` read contract (a new `Status` value or an `Object_Information` field),
   then the two responses. MODEL FIRST. The memory-backend half is folded into the same issue.
7. **{{ISSUE:S3-DOMAIN-A-6}} `max-keys`, `max-uploads` and `max-parts` above 1,000 are rejected
   instead of capped, so `aws s3api list-objects-v2 --max-keys 2000` fails.** Clamp in the three
   query parsers; DECISION only if the maintainer prefers to widen `S3.Core.Page_Size`.
8. **{{ISSUE:S3-DOMAIN-B-3}} The ListObjectAnnotations query codec binds `annotationPrefix`,
   `maxAnnotationResults` and `continuationToken` while the pinned model, the generated descriptor
   and the crate's own client send the hyphenated names, so prefixed and paginated list requests
   are 400.** Bind the model's spellings (a self-interop failure).
9. **{{ISSUE:S3-DOMAIN-B-4}} `Multipart_Uploads.Validate` compares URL-encoded markers bytewise,
   so page 2 of an `encoding-type=url` ListMultipartUploads whose next key diverges at a byte that
   encodes out of order is 500.** Compare decoded keys.

P2
10. **{{ISSUE:SIGV4-1}}** A far-future `x-amz-date` escapes as `Time_Error` and becomes 500: contain
   the subtraction and answer `RequestTimeTooSkewed`. DECISION on the year bound option only.
9. **{{ISSUE:WIRE-2}}** empty list elements in `If-Match` are rejected: accept them in the root
   predicate. MODEL FIRST (a SPARK contract).
10. **{{ISSUE:WIRE-3}}** an unrecognised Range unit is answered 400: ignore the field, as RFC 9110
    requires. One existing test pins the rejection and must change under one option.
11. **{{ISSUE:WIRE-1b}}** a non-UTF-8 key byte yields a 200 listing that is not valid UTF-8: same
    decision as items 5 and 6 (reject at PUT, or encode).
12. **{{ISSUE:SERVER-3}}** HeadObject always emits `x-amz-version-id: null`: after the client issues
    in Layer 4 land, because that fallback is what keeps the in-repo corpus green until then.
13. **{{ISSUE:SERVER-4}}** CompleteMultipartUpload `<Location>` is a path: emit the URI the model
    documents.
14. **{{ISSUE:SERVER-5}}** `STREAMING-UNSIGNED-PAYLOAD-TRAILER` is answered 400
    `AuthorizationHeaderMalformed`: answer the 501 the aws-chunked path already uses and name the
    sentinel in the compatibility matrix. Matters once TLS fronts the server.
15. **{{ISSUE:CHECKSUM-1}}** PutObject answers `InvalidRequest` for an SDK-algorithm and value-header
    mismatch where the model documents `BadDigest`: DECISION between the two codes; the corpus pins
    the current one.

## Layer 2 — backends: memory, files, SQLite

Durability and hangs. The three P0s here are independent of everything else and can start at once.

P0
16. **{{ISSUE:BACKEND-FILES-3}} A bucket-configuration document of a few MiB is accepted and durable,
    but reading it from a default-stack worker task kills the process with SIGKILL.** Route the seven
    `Read_String` readers through the chunked reader the replication and website readers already
    use. No public value changes. Regression: a new files probe launched from `tests/scripts/test.sh`.
17. **{{ISSUE:BACKEND-FILES-4}} A failed DeleteObject destroys the object's acknowledged annotations
    while leaving the object in place.** Remove the sidecar after the object's publication or
    durability point, not before; the crash variant is read-verified only. DECISION on where the
    orphan sweep lives (shared with item 24).
18. **{{ISSUE:BACKEND-SQLITE-3}} A failed lease release inside `Find_Selected_Object`'s exception
    handler skips `Gate.Release`, and the store stops answering forever.** Release the gate first, or
    make the lease release non-raising; also fix item 23, which is why the release raises at all.
    DECISION: whether `Gate.Acquire` should honour the caller's token and deadline (the amplifier).
    MODEL FIRST.

P1
19. **{{ISSUE:BACKEND-SQLITE-2}}** the annotation copy lease is decremented below its own
    `CHECK(refs>0)`: DECISION on the intended lease lifecycle (drop the check, or delete at one).
20. **{{ISSUE:BACKEND-FILES-1}}** CompleteMultipartUpload writes no annotation generation ID, so a
    completed object inherits the replaced object's annotations after two completions and orphans
    a sidecar: mint the generation ID in completion as PUT does; the sweep is the DECISION of item 21.
21. **{{ISSUE:BACKEND-FILES-2}}** keys beyond 464 bytes are unusable on the files backend and are
    reported as a retryable 503: DECISION between a documented lower bound and a path encoding that
    bounds total length.
22. **{{ISSUE:BACKEND-SQLITE-1}}** `Get_Object` opens the payload after the catalog gate is released,
    so a concurrent overwrite answers 503: open under the gate through the `Check` hook the other
    readers use; DECISION on the retention the architecture document promises. MODEL FIRST.
23. **{{ISSUE:BACKEND-SQLITE-4}}** `Delete_Bucket` reports `Backend_Unavailable` for a bucket whose
    keys are all delete markers: count `object_versions` rows and answer `Bucket_Not_Empty`.
24. **{{ISSUE:BACKEND-MEMORY-1}}** ListMultipartUploads paired-cursor pagination silently drops
    same-key uploads whose IDs sort against initiation order: DECISION which S3 rule wins. MODEL
    FIRST.
25. **{{ISSUE:BACKEND-MEMORY-2}}** a same-key CopyObject naming a source version is rejected, so a
    version restore never publishes: consult `Source_Selector` in the self-copy predicate in all
    three backends (the issue cites the three sites). MODEL FIRST.

P2
26. **{{ISSUE:BACKEND-FILES-5}}** wrong-key multipart operations answer `Backend_Unavailable` instead
    of `Not_Found`; **{{ISSUE:BACKEND-FILES-6}}** deleted version IDs are reused (DECISION: persisted
    high-water mark, tombstone, or entropy; MODEL FIRST with item 8);
    **{{ISSUE:BACKEND-SQLITE-5}}** the annotation qualification record claims SQLite corpus evidence
    that no test produces (documentation, or add the run).

## Layer 3 — the server executable

27. **{{ISSUE:SERVER-EXE-1}} (P1)** an administrator login runs 600,000 PBKDF2 iterations on the
    shared cooperative loop and stalls every S3 request for a second; ten logins starve S3 for ten
    seconds. Run the hash off the loop; DECISION on the worker placement and bound.
28. **{{ISSUE:SERVER-EXE-2}} (P2)** the management route rate and concurrency policies are inert:
    install the limiter the policy describes. With item 31.
29. **{{ISSUE:SERVER-EXE-3}} (P2)** any root path is handed to the backends, which delete a
    pre-existing `tmp` tree: DECISION on a layout marker or a refusal on unexpected entries; shared
    with the backends.
30. **{{ISSUE:SERVER-EXE-5}} (P2)** two servers can open one files root: take the same `flock` the
    SQLite root takes.
31. **{{ISSUE:SERVER-EXE-4}} (P2)** startup failures print no cause: print the supervisor result's
    child, endpoint and exception.

## Layer 4 — client families: low-level, objects, buckets, transfers

What this crate's own users hit against real servers. The five P0s are one defect class (a demand
that an optional header be echoed) at five sites; fix them as one change per package with one
shared reading of "present and different is a mismatch, absent is not", and land them before
{{ISSUE:SERVER-3}}. The conformance corpus against MinIO, RustFS and SeaweedFS is the acceptance
test: `tests/scripts/test-minio.sh` must get past its HeadObject case.

P0
32. **{{ISSUE:CLIENT-LOW-1}}** `Head_Object_Response_Bound` rejects a valid 200 without
    `x-amz-version-id` after `versionId=null`; this is the exchange the three third-party
    conformance runs fail on. Reject only when the header is present and differs.
33. **{{ISSUE:CLIENT-OBJECTS-1}}** the same two predicates in the object convenience client
    (Get and Head).
34. **{{ISSUE:CLIENT-LOW-2}}** the GetObjectAttributes decoder demands the header; reproduces against
    the crate's own server.
35. **{{ISSUE:CLIENT-LOW-3}}** `Execute_Object_Tagging` requires exactly one `x-amz-version-id` on
    every successful tagging response; and **{{ISSUE:CLIENT-OBJECTS-2}}** its high-level twin.
    The socket-corpus cases the issues name assert the wrong behaviour and must be inverted.

P1
36. **{{ISSUE:CLIENT-BUCKETS-1}}** authentication failure is recognised only as `401
    InvalidAccessKeyId`; MinIO and the crate's own server answer 403, so reads report a corrupt
    response and mutations report outcome-unknown. Recognise the 403 pairings; DECISION only if a
    public enum changes.

P2
37. **{{ISSUE:CLIENT-LOW-4}}** bodyless or non-XML 4xx/5xx decoded as `Invalid_Response` at about
    twenty sites instead of the typed rejected outcome; **{{ISSUE:CLIENT-LOW-5}}**
    `Prepare_Create_Session` rejects explicit `Bucket_Key_Enabled = False`;
    **{{ISSUE:CLIENT-LOW-6}}** the CreateMultipartUpload executor sends a mismatched prepared
    request before raising; **{{ISSUE:CLIENT-LOW-7}}** `Long_Long_Integer'Value` lets Ada literal
    forms such as `1_000` reach the wire as query integers (MODEL FIRST if the validator is in the
    proof boundary); **{{ISSUE:CLIENT-OBJECTS-3}}** GetObjectTorrent labels a 500 or 503 as
    `No_Failure`; **{{ISSUE:CLIENT-BUCKETS-2}}** `Head` cannot report the region of a redirected
    bucket (DECISION: a field on the rejected variant); **{{ISSUE:CLIENT-BUCKETS-3}}** the strict
    ListBuckets prefix echo fails against MinIO (DECISION: relax or document);
    **{{ISSUE:TRANSFERS-1}}** `Download_File` reports a 200 answer to a ranged GET with the message
    meant for an unrequested 206.

## Layer 5 — domain codecs

Client-side decoders of server responses. Items 43 and 44 must land together: fixing one leaves
ListObjectVersions equally broken against MinIO.

P0
38. **{{ISSUE:S3-DOMAIN-A-2}}** the ListObjects v1 validator rejects a truncated page carrying
    `NextMarker` without a delimiter, which MinIO, RustFS and SeaweedFS all emit; the matrix claims a
    six-server oracle while the CI lane switches the case off through an oracle mode. Accept the
    page; remove the oracle-mode switch for this case.

P1
39. **{{ISSUE:S3-DOMAIN-A-1}}** ListObjectVersions rejects any non-`STANDARD` version storage class
    (the model's one-value enum): accept the object storage-class set.
40. **{{ISSUE:S3-DOMAIN-A-7}}** `Versions.Validate` rejects every untruncated MinIO `?versions`
    page (empty `NextVersionIdMarker` with no `NextKeyMarker`): pair the markers only when the page
    is truncated. With item 43; no third-party lane runs ListObjectVersions today, add one.
41. **{{ISSUE:S3-DOMAIN-A-4}}** four list decoders enforce the botocore shape name as the XML root
    where AWS sends `ListInventoryConfigurationsResult`, `ListMetricsConfigurationsResult`,
    `ListBucketAnalyticsConfigurationResult` and `ListAllMyDirectoryBucketsResult`: this is a
    generator-level change (`tools/s3_codegen.py`) plus the three hand-written decoders; the
    in-repo server must emit the same roots (one PR touching both sides).

P2
42. **{{ISSUE:S3-DOMAIN-A-3}}** lifecycle and notification serializers reject U+007F: widen the
    range to what the parsers accept.

P2, S3-DOMAIN-B client and server codecs
43. **{{ISSUE:S3-DOMAIN-B-5}}** `Attributes.Valid_Storage_Class` hard-codes 13 of the model's 15
    values; **{{ISSUE:S3-DOMAIN-B-6}}** PutObjectTagging maps repertoire, duplicate and eleven-tag
    failures to `MalformedXML` where the header form and PutBucketTagging (and MinIO) say
    `InvalidTag` (DECISION: the model names no code); **{{ISSUE:S3-DOMAIN-B-7}}** the
    GetObjectAttributes decoder treats `<ObjectParts>` as proof of multipart and rejects valid
    FULL_OBJECT checksums, which MinIO returns for a single PUT; **{{ISSUE:S3-DOMAIN-B-8}}** the
    decoder bounds the `MaxParts` echo at 1,000 while MinIO answers 10,000 (with item 9);
    **{{ISSUE:S3-DOMAIN-B-9}}** `Parse_Bucket_Response` runs the publication predicate over a
    decoded response, so MinIO's empty `<TagSet/>` is rejected.


## Layer 6 — continuous integration

44. **{{ISSUE:BASELINE-2}} (P1)** the two s5cmd-driven CI jobs cannot fail: `shell: bash` or
    `pipefail` on the two steps, and an endpoint the s5cmd container can reach on Linux (DECISION
    among the three addressing options in the issue). Land this first in its lane; it is what would
    have caught items 36 to 39 and 42 to 44 on Linux. Regression: a rule in
    `tools/ci/verify-workflow-policy.sh` with its mutation fixture.
