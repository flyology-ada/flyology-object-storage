# Flyology Object Storage issue triage: #13–#74

Sixty-two issues were filed on flyology-ada/flyology-object-storage from a crate-wide correctness
review at commit 5fe6e3e. Each issue body has the mechanism, file:line locations, evidence (a spike
program and its output, a stock-client capture, or a real-server capture) and a suggested treatment.
Work the layers in order: wire and SigV4 first (what every request passes through), then the server
application (what stock clients hit), then the backends (durability and hangs), then the client
families (what this crate's own users hit against real servers), then the domain codecs, then CI.
Inside a layer, work P0 before P1 before P2, in the order listed. The severities below are the
reviewer's; the issue bodies state impact in prose and carry only the `bug` label, plus
`documentation` for pure contract drift.

## Ground rules for every fix

- Read `AGENTS.md` first, in particular its sections "Flyology Object Storage agent guide" (the
  namespace, the layering rule that backends never see HTTP types, the conformance-suite rule, the
  64-bit streaming rule, the structured-task rule, the required test commands and the proof gate),
  "Decision authority", "Ada interface values", "Ada source style", "Review cycle", "Commits",
  "Repository workflow", "TLA+ assurance" and "Performance testing"; they are the contract you are
  fixing against. Run `apm install --frozen` and `apm compile --target codex` after creating a
  worktree, as the "Repository workflow" section requires, so `AGENTS.md` is current.
- One issue per branch and PR unless an item below says two issues share a fix. Problem/Solution
  commit messages, one problem per commit, no attribution footers. Reference the issue with
  `Closes #N`.
- Verification by area:
  - everything: `tools/ci/run-tests.sh` is the CI gate (root build, `tests/scripts/test.sh`,
    `sqlite/tests/scripts/test.sh`). `tests/scripts/test.sh` needs `uv` with Python 3.13 and the
    pinned botocore model: fetch it as `.github/workflows/ci.yml` does (botocore commit
    `36c34f15391da01cd717c73c0fffa747c9889768`, `botocore/data/s3/2006-03-01/service-2.json`) and
    export `FLYOLOGY_S3_SERVICE_MODEL=<path>`; without it the model verifiers fail. The quick loop for
    core, backend and client changes is `cd tests && alr -n build && ./bin/flyology_object_storage_tests`
    plus the corpus binary for the operation you touched.
  - anything under the SPARK boundary (the nine forced units in `tools/prove.sh`:
    `flyology-object_storage.adb`, `-s3-core`, `-s3-checksum_policy`, `-s3-checksum_crc`,
    `-s3-imf_dates`, `-s3-model`, `-s3-requests`, `-s3-sigv4_encoding`, `-s3-wire_core`):
    `tools/prove.sh` (GNATprove 16.1.0 via Alire, serialized, level 0, warnings as errors). A change
    there is not done until it reports every check proved; never suppress a finding.
  - the generated descriptor and its verifiers: never hand-edit
    `src/flyology-object_storage-s3-model.ad?` or a `generated_*_xml` unit; change
    `tools/generate-s3-model.py` or `tools/s3_codegen.py` or their input, regenerate, and let
    `tools/verify-botocore-model.sh <model>` and the `run_s3_model_verifiers` step of
    `tests/scripts/test.sh` check the result.
  - SQLite backend: `sqlite/tests/scripts/test.sh` in addition to the root gate.
  - interop items (anything whose issue quotes aws-cli, boto3, MinIO, RustFS or SeaweedFS): drive the
    real thing. `tests/scripts/test-minio.sh`, `test-rustfs.sh`, `test-seaweedfs.sh` and
    `test-flyology-server.sh <backend>` run the implementation corpus and the s5cmd slice against the
    pinned images (Docker); `FLYOLOGY_S3_MATRIX_REPEATS=1 tests/scripts/test-s3-matrix.sh` runs all
    six once. Until the client-side version-header issues are fixed, the three third-party runs fail
    at the corpus's third HeadObject case; that is expected and is what those issues are about. The
    memory server `tests/bin/s3_memory_server` (built by the test suite; needs `AWS_ACCESS_KEY_ID`
    and `AWS_SECRET_ACCESS_KEY` in the environment, prints `PORT <n>`) is the target for stock
    clients: `aws` v2 if installed, or boto3 through `uv run --python 3.13 --with boto3`.
  - `git diff --check` and the repository's maintained formatter on touched handwritten Ada before
    committing (the "Ada source style" section: at most one formatter run and one format check, only
    when the formatter is already provisioned; report it if it is not).
- Every fix needs a regression test that fails before and passes after. Every issue includes the
  spike that reproduced the defect and names the suite it belongs to; turn it into a test there
  rather than inventing a new one: `tests/src/s3_server_application_corpus.adb` for server behaviour
  over the in-process transport; `tests/src/object_storage_test_cases.adb` for domain predicates and
  client units; the backend-neutral conformance programs `tests/src/{conditional_put,versioned_object,multipart_part,copy_object}_conformance.adb`
  for behaviour every backend must share (they run against memory and files from
  `tests/src/object_storage_test_cases.adb` and against SQLite from
  `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`, whose project compiles `tests/src/`);
  the other class-wide exercisers are private to `object_storage_test_cases.adb` and
  `Flyology.Object_Storage.Backends.Testing` is only an 18-line helper, so a new shared family may
  need a new conformance program (DECISION on where); the files-specific probes live in
  `tests/src/files_*probe.adb` and the crash matrix in `tests/scripts/test.sh`; `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`
  for the SQLite backend; `tests/src/s3_http_socket_corpus.adb` for client behaviour against a
  scripted server (and fix the cases there that assert the wrong behaviour; each issue names them);
  `tests/src/s3_implementation_corpus.adb` for behaviour that must hold against real servers.
- Do not widen scope: an issue that asks for a one-line guard gets a one-line guard. Do not
  introduce new public constants, defaults, limits, variants, parameters or outcome kinds without
  asking (`AGENTS.md`, sections "Ada interface values" and "Decision authority").
- Items marked DECISION need a maintainer choice before implementation; ask, do not guess.

## Confirm every finding before fixing it

The issues were written by a reviewer, not by the maintainer. Every one carries a runtime
reproduction on the reviewer's host (macOS 26.6.2, arm64, GNAT 16.1.0 via Alire). The interop
claims were established three ways and each issue says which: a stock client (aws-cli v2.36.34, or
boto3 1.43.89 through uv) driven against this crate's own memory server; this crate's client driven
against the pinned MinIO, RustFS or SeaweedFS image; or the pinned botocore model's shapes and
documentation strings. No claim was checked against the AWS service itself. Treat each issue as a
claim to verify, not an instruction to execute:

1. Re-read the cited locations at the current `main`, not at 5fe6e3e; line numbers may have moved
   and a later commit may already have changed the mechanism. Re-derive the failure scenario from
   the code yourself and write it down in the PR description in your own words.
2. Reproduce it. Rebuild the spike the issue quotes (each issue carries the essential source and the
   observed output) and confirm the output. For the interop claims, go one step further than the
   issue did where you can: drive the real client or server named in the issue, and record what
   happened. The reproduction becomes the regression test.
3. If the reading or the reproduction disagrees with the issue, stop and report to the master with
   what you observed. The master takes it to the maintainer, who closes or amends the issue. Do not
   fix a finding you could not confirm, and do not widen a fix to cover a scenario the issue
   describes but you could not reproduce.
4. Confirm severity as well as mechanism: if a P0 or P1 turns out to need a precondition the issue
   did not state, say so in the PR and let the master reorder.

A finding confirmed by the lane, with its own reproduction, is the bar for opening a fix PR.

## Work organization: one master task, lanes of at most three

The task reading this brief is the master. It owns the queue below, the list of open DECISION
items, and the record of what each lane has merged. It does not implement issues itself; it starts
lane tasks, answers their questions, relays decisions to the maintainer, and reorders the queue when
a lane reports a dependency.

- A lane is one layer's worth of issues worked in one git worktree on one branch stack. Start with
  three lanes: **Layer 1 wire, SigV4 and the server application** (what stock clients hit; the
  namespace and Content-MD5 items are one change class), **Layer 2 backends** (memory, files, SQLite;
  independent of Layer 1), and **Layer 4 client families** (independent of the server lane except
  that the version-header fixes on both sides must agree on what a never-versioned bucket looks like;
  the client side is authoritative there because the servers it must talk to are not this crate's,
  and the server's `null` fallback issue lands after the client issues). Start **Layer 3 the server
  executable**, **Layer 5 domain codecs** and **Layer 6 CI** when any lane finishes; the CI item
  is small and can go first in whichever lane frees up. Never run more than three lane tasks at once.
- Lanes report to the master after every merged PR (issue number, PR URL, checks run) and before any
  step that changes a shared assumption: a change to a public `.ads`, to the `Backends` contract, to
  the proof boundary, to a generator under `tools/`, or to a corpus that all backends share. The
  master forwards such changes to the other live lanes so they rebase at their next PR boundary, not
  mid-branch.
- Lanes may message each other directly for coordination on a shared file, but every DECISION goes
  through the master, which asks the maintainer once and records the answer in this file.
- Serialize Alire and Docker runs across lanes. Alire redeploys indexed releases into one shared
  cache on every command, so two lanes running `alr` at the same time corrupt each other, and the
  conformance scripts publish container ports and start the memory server on loopback ports. Use one
  lock (for example `flock` on a file under `/tmp`) around every Alire-driven command and every
  `tests/scripts/*.sh` run, or route all suite runs through the master.
- Each lane keeps its own worktree; never share a checkout, and never use bare `git stash` (the
  stash stack is shared across worktrees).

## Model first: contracts and models where they pay for themselves

This repository proves its wire core with SPARK (`tools/prove.sh`, nine units) and has no TLA+
models yet, but its `AGENTS.md` section "TLA+ assurance" sets the policy: model an algorithm whose
ordering, interleaving or liveness properties span several steps, use the `tla-plus` skill, run both
TLC and TLAPM rather than treating one as evidence for the other, replay TLC traces through the
shared `flyology-ada/tla` Ada harness as conformance evidence, and never let a finite model's bounds
or fairness assumptions become product policy. Use each where it fits; neither is a gate on the rest
of the queue.

- SPARK contracts, existing boundary. #15 (the entity-tag list grammar in the root
  validation package) and #45 (the model-scalar integer validator, if it sits in
  `Flyology.Object_Storage.S3.Requests`) are one-step grammar decisions inside the nine proved units:
  express the corrected grammar as a contract so the wrong acceptance is unrepresentable, and run
  `tools/prove.sh`. #16 (unrecognised Range unit) belongs to the server's admission code,
  outside the boundary, but its range parser is the proved one; keep the parser's contract unchanged
  and fix the caller.
- Bounded TLA+ models, new (DECISION: which to build first and the bounds; the "TLA+ assurance"
  section already answers whether). Three state machines produced the findings that span several
  steps and meet that section's bar. Each should get a `_broken` configuration that reproduces the
  filed bug as a TLC counterexample before the fix, a TLAPM proof of the safety invariant where
  TLAPS can express it, and trace replay through the shared `flyology-ada/tla` harness:
  - multipart-upload listing pagination for #26: uploads for one key
    initiated in time order with upload IDs in an unrelated lexical order, pages of one, the paired
    key and upload-id markers, and the invariant that a full walk returns every upload exactly once.
    The model decides which of the two S3 ordering rules the marker follows (the DECISION in that
    issue) before the code does. Bound it to three uploads and two keys.
  - object versioning transitions and delete-marker reads for #21,
    #33 and #27: Unconfigured, Enabled and Suspended
    states, the null version, delete markers as current versions, exact-version deletes, version-ID
    uniqueness after deletes, and same-key copies from a selected version; the invariant that a
    version ID is never reused and that a read of a marker is distinguishable from a missing key.
    Bound it to one key and three generations.
  - the SQLite catalog gate for #36 and #34: gate
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

## Layer 1 — wire core, SigV4 and the server application

Everything a stock client passes through. #20 must land first: it is the only P0
here and the one every stock client with default integrity protection hits.

P0
1. **#20 Content-MD5 is the only accepted integrity header on the
   `requestChecksumRequired` routes, so stock aws-cli v2 and boto3 are refused on DeleteObjects,
   PutBucketVersioning and the tagging and configuration writes.** Accept the `x-amz-checksum-<alg>`
   group wherever Content-MD5 is demanded, through the `Verify_Document_Checksum` path that already
   exists; keep Content-MD5 as an alternative. DECISION: whether Content-MD5 stays mandatory when no
   checksum header is present. Regression: the stock-client capture in the issue, in
   `tests/src/s3_server_application_corpus.adb` and the s5cmd or aws-cli slice.
2. **#57 The server rejects an unqualified `<VersioningConfiguration>` root,
   which is what `mc version enable` sends.** Accept the root with and without the S3 namespace,
   as every other request codec already does. Items 2, 3 and 4 are one change class; do them in
   one PR only if the maintainer agrees to a shared helper.
3. **#60 `Deletions.Parse_Request` demands the S3 namespace on every element of a
   `<Delete>` body, which the MinIO client and s3cmd do not send.** Accept the namespace-free form as
   the other request codecs do. Same change class as item 2; lands with it.
4. **#61 `Tagging.Parse_Bucket` rejects a namespace-free `<Tagging>` on
   PutBucketTagging (`mc tag set`) while PutObjectTagging accepts it.** Same change class as items 2
   and 3.

P1
5. **#13 A C0 control byte in an accepted key makes every listing without
   `encoding-type=url` answer 500.** Escape or reject at the boundary; the crate's own high-level
   client sends no `encoding-type`, so it hits this by default. DECISION: reject such keys at PUT
   (a policy the matrix must state) or emit character references in listings. Pair with
   #17.
6. **#17 A key containing a carriage return is reported as a different key by
   unencoded listings.** Same site and same decision as item 5.
7. **#19 `Static_Credentials.Create` accepts a principal of 257 to 1,024 bytes that
   admission rejects, so every signed request is 403.** DECISION: reject at `Create`, accept in
   `Valid_Principal`, or lower the documented maximum; the issue lists the three.
8. **#21 Reading a key hidden by a delete marker is a bare 404, and reading the
   marker's own version is 404 instead of 405 with `x-amz-delete-marker`.** DECISION: a delete-marker
   signal in the `Backends` read contract (a new `Status` value or an `Object_Information` field),
   then the two responses. MODEL FIRST. The memory-backend half is folded into the same issue.
9. **#58 `max-keys`, `max-uploads` and `max-parts` above 1,000 are rejected
   instead of capped, so `aws s3api list-objects-v2 --max-keys 2000` fails.** Clamp in the three
   query parsers; DECISION only if the maintainer prefers to widen `S3.Core.Page_Size`.
10. **#62 The ListObjectAnnotations query codec binds `annotationPrefix`,
   `maxAnnotationResults` and `continuationToken` while the pinned model, the generated descriptor
   and the crate's own client send the hyphenated names, so prefixed and paginated list requests
   are 400.** Bind the model's spellings (a self-interop failure).
11. **#63 `Multipart_Uploads.Validate` compares URL-encoded markers bytewise,
   so page 2 of an `encoding-type=url` ListMultipartUploads whose next key diverges at a byte that
   encodes out of order is 500.** Compare decoded keys.

P2
12. **#18** A far-future `x-amz-date` escapes as `Time_Error` and becomes 500: contain
   the subtraction and answer `RequestTimeTooSkewed`. DECISION on the year bound option only.
13. **#15** empty list elements in `If-Match` are rejected: accept them in the root
   predicate. MODEL FIRST (a SPARK contract).
14. **#16** an unrecognised Range unit is answered 400: ignore the field, as RFC 9110
    requires. One existing test pins the rejection and must change under one option.
15. **#14** a non-UTF-8 key byte yields a 200 listing that is not valid UTF-8: same
    decision as items 5 and 6 (reject at PUT, or encode).
16. **#22** HeadObject always emits `x-amz-version-id: null`: after the client issues
    in Layer 4 land, because that fallback is what keeps the in-repo corpus green until then.
17. **#23** CompleteMultipartUpload `<Location>` is a path: emit the URI the model
    documents.
18. **#24** `STREAMING-UNSIGNED-PAYLOAD-TRAILER` is answered 400
    `AuthorizationHeaderMalformed`: answer the 501 the aws-chunked path already uses and name the
    sentinel in the compatibility matrix. Matters once TLS fronts the server.
19. **#25** PutObject answers `InvalidRequest` for an SDK-algorithm and value-header
    mismatch where the model documents `BadDigest`: DECISION between the two codes; the corpus pins
    the current one.

## Layer 2 — backends: memory, files, SQLite

Durability and hangs. The three P0s here are independent of everything else and can start at once.

P0
20. **#30 A bucket-configuration document of a few MiB is accepted and durable,
    but reading it from a default-stack worker task kills the process with SIGKILL.** Route the seven
    `Read_String` readers through the chunked reader the replication and website readers already
    use. No public value changes. Regression: a new files probe launched from `tests/scripts/test.sh`.
21. **#31 A failed DeleteObject destroys the object's acknowledged annotations
    while leaving the object in place.** Remove the sidecar after the object's publication or
    durability point, not before; the crash variant is read-verified only. DECISION on where the
    orphan sweep lives (shared with item 24).
22. **#36 A failed lease release inside `Find_Selected_Object`'s exception
    handler skips `Gate.Release`, and the store stops answering forever.** Release the gate first, or
    make the lease release non-raising; also fix item 23, which is why the release raises at all.
    DECISION: whether `Gate.Acquire` should honour the caller's token and deadline (the amplifier).
    MODEL FIRST.

P1
23. **#35** the annotation copy lease is decremented below its own
    `CHECK(refs>0)`: DECISION on the intended lease lifecycle (drop the check, or delete at one).
24. **#28** CompleteMultipartUpload writes no annotation generation ID, so a
    completed object inherits the replaced object's annotations after two completions and orphans
    a sidecar: mint the generation ID in completion as PUT does; the sweep is the DECISION of item 21.
25. **#29** keys beyond 464 bytes are unusable on the files backend and are
    reported as a retryable 503: DECISION between a documented lower bound and a path encoding that
    bounds total length.
26. **#34** `Get_Object` opens the payload after the catalog gate is released,
    so a concurrent overwrite answers 503: open under the gate through the `Check` hook the other
    readers use; DECISION on the retention the architecture document promises. MODEL FIRST.
27. **#37** `Delete_Bucket` reports `Backend_Unavailable` for a bucket whose
    keys are all delete markers: count `object_versions` rows and answer `Bucket_Not_Empty`.
28. **#26** ListMultipartUploads paired-cursor pagination silently drops
    same-key uploads whose IDs sort against initiation order: DECISION which S3 rule wins. MODEL
    FIRST.
29. **#27** a same-key CopyObject naming a source version is rejected, so a
    version restore never publishes: consult `Source_Selector` in the self-copy predicate in all
    three backends (the issue cites the three sites). MODEL FIRST.

P2
30. **#32** wrong-key multipart operations answer `Backend_Unavailable` instead
    of `Not_Found`; **#33** deleted version IDs are reused (DECISION: persisted
    high-water mark, tombstone, or entropy; MODEL FIRST with item 8);
    **#38** the annotation qualification record claims SQLite corpus evidence
    that no test produces (documentation, or add the run).

## Layer 3 — the server executable

31. **#69 (P1)** an administrator login runs 600,000 PBKDF2 iterations on the
    shared cooperative loop and stalls every S3 request for a second; ten logins starve S3 for ten
    seconds. Run the hash off the loop; DECISION on the worker placement and bound.
32. **#70 (P2)** the management route rate and concurrency policies are inert:
    install the limiter the policy describes. With item 31.
33. **#71 (P2)** any root path is handed to the backends, which delete a
    pre-existing `tmp` tree: DECISION on a layout marker or a refusal on unexpected entries; shared
    with the backends.
34. **#73 (P2)** two servers can open one files root: take the same `flock` the
    SQLite root takes.
35. **#72 (P2)** startup failures print no cause: print the supervisor result's
    child, endpoint and exception.

## Layer 4 — client families: low-level, objects, buckets, transfers

What this crate's own users hit against real servers. The five P0s are one defect class (a demand
that an optional header be echoed) at five sites; fix them as one change per package with one
shared reading of "present and different is a mismatch, absent is not", and land them before
#22. The conformance corpus against MinIO, RustFS and SeaweedFS is the acceptance
test: `tests/scripts/test-minio.sh` must get past its HeadObject case.

P0
36. **#39** `Head_Object_Response_Bound` rejects a valid 200 without
    `x-amz-version-id` after `versionId=null`; this is the exchange the three third-party
    conformance runs fail on. Reject only when the header is present and differs.
37. **#46** the same two predicates in the object convenience client
    (Get and Head).
38. **#40** the GetObjectAttributes decoder demands the header; reproduces against
    the crate's own server.
39. **#41** `Execute_Object_Tagging` requires exactly one `x-amz-version-id` on
    every successful tagging response; and **#47** its high-level twin.
    The socket-corpus cases the issues name assert the wrong behaviour and must be inverted.

P1
40. **#49** authentication failure is recognised only as `401
    InvalidAccessKeyId`; MinIO and the crate's own server answer 403, so reads report a corrupt
    response and mutations report outcome-unknown. Recognise the 403 pairings; DECISION only if a
    public enum changes.

P2
41. **#42** bodyless or non-XML 4xx/5xx decoded as `Invalid_Response` at about
    twenty sites instead of the typed rejected outcome; **#43**
    `Prepare_Create_Session` rejects explicit `Bucket_Key_Enabled = False`;
    **#44** the CreateMultipartUpload executor sends a mismatched prepared
    request before raising; **#45** `Long_Long_Integer'Value` lets Ada literal
    forms such as `1_000` reach the wire as query integers (MODEL FIRST if the validator is in the
    proof boundary); **#48** GetObjectTorrent labels a 500 or 503 as
    `No_Failure`; **#50** `Head` cannot report the region of a redirected
    bucket (DECISION: a field on the rejected variant); **#51** the strict
    ListBuckets prefix echo fails against MinIO (DECISION: relax or document);
    **#52** `Download_File` reports a 200 answer to a ranged GET with the message
    meant for an unrequested 206.

## Layer 5 — domain codecs

Client-side decoders of server responses. Items 43 and 44 must land together: fixing one leaves
ListObjectVersions equally broken against MinIO.

P0
42. **#54** the ListObjects v1 validator rejects a truncated page carrying
    `NextMarker` without a delimiter, which MinIO, RustFS and SeaweedFS all emit; the matrix claims a
    six-server oracle while the CI lane switches the case off through an oracle mode. Accept the
    page; remove the oracle-mode switch for this case.

P1
43. **#53** ListObjectVersions rejects any non-`STANDARD` version storage class
    (the model's one-value enum): accept the object storage-class set.
44. **#59** `Versions.Validate` rejects every untruncated MinIO `?versions`
    page (empty `NextVersionIdMarker` with no `NextKeyMarker`): pair the markers only when the page
    is truncated. With item 43; no third-party lane runs ListObjectVersions today, add one.
45. **#56** four list decoders enforce the botocore shape name as the XML root
    where AWS sends `ListInventoryConfigurationsResult`, `ListMetricsConfigurationsResult`,
    `ListBucketAnalyticsConfigurationResult` and `ListAllMyDirectoryBucketsResult`: this is a
    generator-level change (`tools/s3_codegen.py`) plus the three hand-written decoders; the
    in-repo server must emit the same roots (one PR touching both sides).

P2
46. **#55** lifecycle and notification serializers reject U+007F: widen the
    range to what the parsers accept.

P2, S3-DOMAIN-B client and server codecs
47. **#64** `Attributes.Valid_Storage_Class` hard-codes 13 of the model's 15
    values; **#65** PutObjectTagging maps repertoire, duplicate and eleven-tag
    failures to `MalformedXML` where the header form and PutBucketTagging (and MinIO) say
    `InvalidTag` (DECISION: the model names no code); **#66** the
    GetObjectAttributes decoder treats `<ObjectParts>` as proof of multipart and rejects valid
    FULL_OBJECT checksums, which MinIO returns for a single PUT; **#67** the
    decoder bounds the `MaxParts` echo at 1,000 while MinIO answers 10,000 (with item 9);
    **#68** `Parse_Bucket_Response` runs the publication predicate over a
    decoded response, so MinIO's empty `<TagSet/>` is rejected.


## Layer 6 — continuous integration

48. **#74 (P1)** the two s5cmd-driven CI jobs cannot fail: `shell: bash` or
    `pipefail` on the two steps, and an endpoint the s5cmd container can reach on Linux (DECISION
    among the three addressing options in the issue). Land this first in its lane; it is what would
    have caught items 36 to 39 and 42 to 44 on Linux. Regression: a rule in
    `tools/ci/verify-workflow-policy.sh` with its mutation fixture.

## Explicitly out of scope

No issue or pull request was open on flyology-ada/flyology-object-storage when these were filed
(the last merged pull request is #12). The observations listed under "Observations not counted"
in each area of the review record are not issues: documented policy values, unreachable code, and
candidates that verification refuted. The `_probe` programs in the reproduction harness pass on
the current sources and exist only to show that a suspected defect is absent. Two documented
limitations were deliberately left unfiled and are the maintainer's call: `+` in `x-amz-tagging`
(the crate keeps the literal plus where MinIO decodes it to a space; `tagging.ads:27-30`) and
presigned URLs (documented as not claimed).
