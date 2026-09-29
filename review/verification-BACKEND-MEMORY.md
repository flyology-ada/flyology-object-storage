# Adversarial verification: BACKEND-MEMORY (memory backend, backend interface, shared listing)

Scope verified by reading: `src/flyology-object_storage-backends-memory.adb`
(`Owned_Bytes` 93-206; `Selected_Generation_Index` / `Selected_Object_Index`
284-329; reservations 1366-1385 and 3427-3465; `Commit` 1387-1541; `Fetch`
1543-1594; `Head` / `Attributes` 1729-1794; slot reset 1902, 1953; legal-hold
and retention gating 2025-2140; `List` 2523-2553; `List_Versions` 2555-2803
including the paired-cursor rejection 2675-2690; multipart 2805-2860; the
`Store` overrides, in particular `Copy_Object` 4940-5010, `Get_Object`
5142-5240, and the listing exception mapping 5855-5895),
`src/flyology-object_storage-backends-multipart_listing.adb` (full) and its
`.ads`, `src/flyology-object_storage-backends.ads` (`Listed_Version` 85-104,
`List_Versions_Page` 135-141, `Version_Selector` 50-70, `Copy_Options`
245-267, `Version_Delete_Kind` 339-360, multipart option and page types
600-740, `Put_Bucket_Versioning` 760-786, `Put_Object` / `Copy_Object` /
`Head_Object` / `Get_Object` / `Get_Object_Attributes` 1925-2117,
`Delete_Selected_Object` 2140-2170, `Delete_Object_Tags` 2610-2622,
`List_Object_Versions` 2640-2655, `List_Multipart_Uploads` 2711-2723),
`src/flyology-object_storage.ads` (`Status` 39-52, versioning 230-251,
`Byte_Range` 385-405, `Object_Information` 554-562, `Write_Conditions` 635-641,
`Put_Options` 651-660), the identical self-copy predicates in
`src/flyology-object_storage-backends-files.adb:7602-7611` and
`sqlite/src/flyology-object_storage-backends-sqlite.adb:2436-2445`,
`src/flyology-object_storage-server-s3_applications.adb` (ListMultipartUploads
11148-11260, CopyObject source-version parsing 14080-14110),
`docs/qualification/{list-multipart-uploads-preparation,copy-object,
list-object-versions}.md`, `docs/compatibility/s3.md:61`,
`review/baseline/service-2.json` (`GetObjectOutput`/`HeadObjectOutput`
`DeleteMarker`), and the existing coverage at
`tests/src/object_storage_test_cases.adb:3273-3400`,
`tests/src/versioned_object_conformance.adb:755-780`, and
`tests/src/copy_object_conformance.adb`.

Harness programs added: `tests/repros/src/repro_backend_memory_support.ads`,
`tests/repros/src/repro_backend_memory_support.adb`,
`tests/repros/src/repro_backend_memory_1.adb`,
`tests/repros/src/repro_backend_memory_2.adb`,
`tests/repros/src/repro_backend_memory_3.adb`,
`tests/repros/src/repro_backend_memory_probe.adb`. Nothing tracked was
modified.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| BACKEND-MEMORY-1 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_backend_memory_1.adb` |
| BACKEND-MEMORY-2 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_backend_memory_2.adb` |
| BACKEND-MEMORY-3 | CONFIRMED (backend half of SERVER-2) | P2 (P2) | `tests/repros/src/repro_backend_memory_3.adb` |

All three discovery findings survived. No new finding was raised: the eight
uncounted observations were re-read and two were measured with
`tests/repros/src/repro_backend_memory_probe.adb`; all of them stay
observations, so there is no BACKEND-MEMORY-4. Details and the measured
evidence are in the observations section at the end.

---

### BACKEND-MEMORY-1: ListMultipartUploads paired cursor skips same-key uploads whose SHA-256 upload IDs sort against initiation order

**Verdict:** CONFIRMED.

**Severity:** P1 (discovery said P1).

Verified by reading:

- `src/flyology-object_storage-backends-multipart_listing.adb:17-30`: `Before`
  orders same-key candidates by `Initiated` first and only breaks equal-time
  ties with the upload ID.
- `src/flyology-object_storage-backends-multipart_listing.adb:84-91`: the
  exclusive marker test is
  `Candidate_Key = After_Key and then (After_ID'Length = 0 or else Candidate_ID <= After_ID)`
  — purely lexical on the upload ID, with no reference to `Initiated`.
- `src/flyology-object_storage-backends-multipart_listing.adb:141-149`:
  `Next_After` is the key and upload ID of the last *returned* candidate, i.e.
  the service itself produces the marker pair that the filter then
  misinterprets.
- `src/flyology-object_storage-backends-memory.adb:2830-2833`: `Upload_ID` is
  `GNAT.SHA256.Digest (Bucket & NUL & Key & NUL & Long_Long_Integer'Image (Next_Upload))`,
  so lexical order carries no relation to creation order.
- `src/flyology-object_storage-backends-memory.adb:207-208`: `Current_Unix_Time`
  is whole seconds, so two uploads a second apart get different `Initiated`
  values and `Before` falls through to the time comparison.
- Contract `src/flyology-object_storage-backends.ads:2711-2715` states the two
  rules independently ("Uploads with the same key use initiation-time order and
  upload ID breaks equal-time ties; marker filtering independently follows S3's
  lexical upload-ID rule").
- `docs/qualification/list-multipart-uploads-preparation.md:42-45`: "The later
  implementation and oracle must exercise inverse upload-ID/initiation-time
  data rather than assume those orders coincide. A service-produced marker pair
  must always resume without skipping, repeating, or looping, with a
  deterministic upload-ID tie break for equal initiation times."
- `src/flyology-object_storage-server-s3_applications.adb:11186-11196`: the
  server copies `key-marker` / `upload-id-marker` straight into
  `Options.After` and copies `Page.Next_After` straight back into
  `NextKeyMarker` / `NextUploadIdMarker` (`:11240-11246`). No re-sorting or
  re-filtering happens above the backend.

Refutation attempts that failed:

- Looked for a guard that makes the two orders agree: upload IDs are SHA-256
  hex, not monotone, and `Next_Upload` is a store-wide counter, so the digests
  for one key are effectively random relative to creation order.
- Looked for a server-side reconciliation (a second pass, a re-sort, a
  key-only fallback when a page comes back empty but the key is unchanged):
  none exists in the `List_Multipart_Uploads` branch.
- Checked whether the `.ads` contract sanctions the loss. It fixes the two
  rules but never says a service cursor may skip; the qualification document
  above explicitly forbids it.
- Checked whether existing coverage already pins this: it does not.
  `tests/src/object_storage_test_cases.adb:3318-3328` creates all five uploads
  in one tight loop, so the two `same`-key uploads share an `Initiated` value
  and `Before` falls through to the upload-ID tie break, which coincides with
  the marker rule. The marker-filtering assertion at `:3379-3389` deliberately
  uses `Smaller_ID`/`Larger_ID` rather than creation order, so it never
  exercises the split. No test creates same-key uploads across a second
  boundary.
- Checked whether `Maximum = 1` is unusual input: `max-uploads` is a modelled
  request member from 1 through 1,000
  (`docs/qualification/list-multipart-uploads-preparation.md:54`), and any
  page bound reached inside one key exposes the same skip.

**Repro:** `tests/repros/src/repro_backend_memory_1.adb`. It initiates six
multipart uploads for one key (bucket `bkt`, key `k`) one second apart on a
private `Backends.Memory.Store (4, 64, 1 MiB)`, prints each upload ID, then
(control) lists them unbounded and (test) walks the cursor with
`Maximum => 1`, following the returned `Next_After` pair, asserting each ID
comes back exactly once. It then repeats the whole walk over the in-process S3
application with `?uploads&max-uploads=1&key-marker=…&upload-id-marker=…`.
Because the IDs are digests of `"bkt" & NUL & "k" & NUL & Image (n)`, the six
values are deterministic (`dc3e…`, `6f9a…`, `42d9…`, `ccbf…`, `8044…`,
`c4dd…`): every upload after the first sorts before it, so the first
continuation is already empty.

**Output** (`cd tests/repros && ./run.sh repro_backend_memory_1`, exit
status **1**; the whole run including the build takes about 14 s, so the
default 60 s limit is enough):

```
ok: backend: bucket created
  ok: backend: upload1 initiated
  -- backend: initiation order1 id dc3e6a657ac580f3a4df5f53a1aa570d861b135eabcd560f2e5936367c9cddd5
  ok: backend: upload2 initiated
  -- backend: initiation order2 id 6f9a9cb723b61b14f34db49873718b5baeea1eb589c1753782a65e2f07947138
  ok: backend: upload3 initiated
  -- backend: initiation order3 id 42d949c57319e756b32d3d1f177824319cfc34b8a5c67dfca60df01a4ad316a8
  ok: backend: upload4 initiated
  -- backend: initiation order4 id ccbf3d6b3f1a122555b50f694bd1d9345371752501ee78df4dd560dee418b526
  ok: backend: upload5 initiated
  -- backend: initiation order5 id 80440036e843b5fb193a8c428ada1e4235de05b26577d8a8338397f6a97ff0bb
  ok: backend: upload6 initiated
  -- backend: initiation order6 id c4dd2ccd99b9625d41552478b4bd692ba625a4db414a4994e09cd6ae36d60da3
  ok: control: unbounded listing succeeds and is complete
  ok: control: unbounded listing returns every active upload
  -- backend: page order1 initiated 1788746889 id dc3e6a657ac580f3a4df5f53a1aa570d861b135eabcd560f2e5936367c9cddd5
  -- backend: page order2 initiated 1788746890 id 6f9a9cb723b61b14f34db49873718b5baeea1eb589c1753782a65e2f07947138
  -- backend: page order3 initiated 1788746891 id 42d949c57319e756b32d3d1f177824319cfc34b8a5c67dfca60df01a4ad316a8
  -- backend: page order4 initiated 1788746892 id ccbf3d6b3f1a122555b50f694bd1d9345371752501ee78df4dd560dee418b526
  -- backend: page order5 initiated 1788746893 id 80440036e843b5fb193a8c428ada1e4235de05b26577d8a8338397f6a97ff0bb
  -- backend: page order6 initiated 1788746894 id c4dd2ccd99b9625d41552478b4bd692ba625a4db414a4994e09cd6ae36d60da3
  -- backend: page1 uploads1 truncated TRUE next-key 'k' next-id 'dc3e6a657ac580f3a4df5f53a1aa570d861b135eabcd560f2e5936367c9cddd5'
  -- backend: page2 uploads0 truncated FALSE next-key '' next-id ''
  ok: backend: every page succeeded
  -- backend: walk returned1 of6 uploads
  FAILED: backend: paired-cursor walk returns every active upload
  ok: backend: initiation order1 returned exactly once by the walk
  FAILED: backend: initiation order2 returned exactly once by the walk
  FAILED: backend: initiation order3 returned exactly once by the walk
  FAILED: backend: initiation order4 returned exactly once by the walk
  FAILED: backend: initiation order5 returned exactly once by the walk
  FAILED: backend: initiation order6 returned exactly once by the walk
  ok: wire: CreateBucket is 200
  ok: wire: CreateMultipartUpload1 is 200
  -- wire: initiation order1 id 942bb21a5ebfcde5ebd2b01a2554177a62e43461baaccb9ce3061d20b450690e
  ok: wire: CreateMultipartUpload2 is 200
  -- wire: initiation order2 id 275b96b9680a79069ec5222dd7c918ba036e2a1a52a19a5af6951548630b5fd7
  ok: wire: CreateMultipartUpload3 is 200
  -- wire: initiation order3 id eea53f36e17e5f3ad8155674dc19707d4c5ceaa7311c335b78da5ea3a80d4579
  ok: wire: CreateMultipartUpload4 is 200
  -- wire: initiation order4 id 0a462fdd4cacca678c3f6fc11dddeb3d87e6afbf7aef5bb0c1f367aac36674d6
  ok: wire: CreateMultipartUpload5 is 200
  -- wire: initiation order5 id 98fccd473ffe584caaf4a4ebf7749a0c8be56bddd4dc7ed73816a44f99656925
  ok: wire: CreateMultipartUpload6 is 200
  -- wire: initiation order6 id 7a6185167218316a65353e661e50fcc99f8ac6865c4c51e75fe9c71335a0762c
  ok: control: wire ListMultipartUploads is 200
  -- control: unbounded wire listing reported6 uploads, IsTruncated false
  ok: control: unbounded wire listing returns every upload
  ok: wire: page1 is 200
  -- wire: page1 uploads1 IsTruncated TRUE NextKeyMarker 'k' NextUploadIdMarker '942bb21a5ebfcde5ebd2b01a2554177a62e43461baaccb9ce3061d20b450690e'
  ok: wire: page2 is 200
  -- wire: page2 uploads1 IsTruncated TRUE NextKeyMarker 'k' NextUploadIdMarker 'eea53f36e17e5f3ad8155674dc19707d4c5ceaa7311c335b78da5ea3a80d4579'
  ok: wire: page3 is 200
  -- wire: page3 uploads0 IsTruncated FALSE NextKeyMarker '' NextUploadIdMarker ''
  -- wire: walk returned2 of6 uploads
  FAILED: wire: paired-cursor walk returns every active upload
  ok: wire: initiation order1 returned exactly once by the walk
  FAILED: wire: initiation order2 returned exactly once by the walk
  ok: wire: initiation order3 returned exactly once by the walk
  FAILED: wire: initiation order4 returned exactly once by the walk
  FAILED: wire: initiation order5 returned exactly once by the walk
  FAILED: wire: initiation order6 returned exactly once by the walk
BUG REPRODUCED: 11 failed expectation(s)
```

**Description:** `Multipart_Listing.Consider` sorts same-key candidates by
initiation time and filters them by lexical upload ID, and
`Multipart_Listing.Finish` builds the continuation cursor from the last
*returned* candidate. Those three rules are mutually inconsistent whenever the
two orders disagree, which for the memory backend is the normal case because
upload IDs are SHA-256 digests. A client that paginates ListMultipartUploads
with the markers the service itself returned silently loses every same-key
upload whose ID sorts at or before the marker — in the runs above, 5 of 6
uploads at the backend interface and 4 of 6 over the wire, with the pages
reporting `IsTruncated false`, so nothing tells the client that anything is
missing. Anyone using `max-uploads` on a key with several concurrent uploads
hits it: multi-writer retry loops, orphan-upload sweepers, and lifecycle
cleanup are exactly the callers that paginate. It is fully deterministic for a
given bucket/key/counter triple, and only invisible when all same-key uploads
land in the same wall-clock second (which is why
`tests/src/object_storage_test_cases.adb:3318-3328` and its marker assertion at
`:3379-3389` pass while asserting a weaker property). The shared builder is
also used by the files and SQLite backends, so a fix belongs in
`multipart_listing.adb` rather than in one store. A fix needs a maintainer
decision on which of the two S3 rules wins: either the page order for a shared
key becomes lexical upload ID (matching the marker, diverging from AWS's stated
initiation-time ordering and from the `.ads` sentence at
`backends.ads:2712-2714`), or the marker filter must resolve `After_ID` to its
initiation time and compare on the same `(Initiated, Upload_ID)` key the page
order uses (matching AWS's ordering, but making the marker meaningful only
while the referenced upload still exists, which raises the same
unknown-cursor policy question already pinned for `ListObjectVersions` at
`memory.adb:2687-2690`).

---

### BACKEND-MEMORY-2: same-key CopyObject with an exact or null source selector (version restore) is rejected as Invalid_Request

**Verdict:** CONFIRMED.

**Severity:** P1 (discovery said P1). The discovery entry's confidence was
Medium only because the AWS acceptance of a versioned self-copy was from
memory; that is now measured against a real server (below), so the finding is
confirmed, not merely plausible.

Verified by reading:

- `src/flyology-object_storage-backends-memory.adb:4977-4986`: the rejection is
  `Source_Bucket = Destination_Bucket and then Source_Key = Destination_Key
  and then Options.Metadata_Directive = Copy_Metadata and then
  Options.Tagging_Directive = Copy_Tags and then Options.Annotation_Directive =
  Copy_Annotations and then Options.Selected_Checksum = No_Checksum and then
  not Options.Metadata.Website_Redirect_Location.Is_Set`, followed by
  `Result := Invalid_Request; return;`. `Options.Source_Selector` is never
  consulted, and the return happens before `Fetch_For_Copy` at `:4988`.
- The identical predicate exists at
  `src/flyology-object_storage-backends-files.adb:7602-7611` and
  `sqlite/src/flyology-object_storage-backends-sqlite.adb:2436-2445`, so all
  three backends behave the same way. Only the memory backend has a program
  here, as instructed.
- `src/flyology-object_storage-server-s3_applications.adb:14080-14101` parses
  `?versionId=` out of `x-amz-copy-source` into
  `Copy_Options_Value.Source_Selector` and rejects only a malformed source
  query, so the versioned same-key copy reaches the backend unaltered.
- `src/flyology-object_storage-backends.ads:1969-2010` (the `Copy_Object`
  contract) documents source selection, directives, checksums, and identities,
  and contains no self-copy rule at all. Nothing in the specification licenses
  the rejection, and nothing scopes it to the current generation.
- `docs/compatibility/s3.md:61` claims CopyObject support for "memory/files/
  SQLite current, null, and retained exact source generations" with a "repeated
  six-server byte oracle", i.e. the exact-source lane is a published claim.
- `docs/qualification/copy-object.md:39` requires the parser to "select that
  immutable current, null, or exact source snapshot on memory, files, and
  SQLite"; the document never mentions a self-copy restriction.

Refutation attempts that failed:

- Looked for a server-side rewrite that would force `Replace_Metadata` for a
  versioned source, or a pre-backend rejection with a better message: neither
  exists; the only pre-backend rejection is for a malformed source query
  (`s3_applications.adb:14101-14108`).
- Looked for existing coverage that pins the current behaviour deliberately:
  `tests/src/copy_object_conformance.adb` exercises the same-key rejection with
  no selector only, and `tests/src/versioned_object_conformance.adb` copies
  exact and null sources to a *different* bucket and key. Nothing asserts the
  same-key versioned case either way.
- **Checked the claim against a real server.** I ran the image pinned by
  `tests/scripts/test-minio.sh`
  (`quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`,
  reporting `RELEASE.2025-09-07T16-13-09Z commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb`,
  matching the provenance check in that script) as a single detached container
  on `127.0.0.1:19000` and drove it with the `aws` CLI; I did not run
  `test-minio.sh` itself, so no `alr -n build` was triggered. The container was
  stopped afterwards. Results:

  | case | MinIO |
  |---|---|
  | versioning on, `copy-source b/k?versionId=<v1>` -> `b/k` | **200**, `CopySourceVersionId=<v1>`, new `VersionId`, current body becomes `v1` |
  | versioning on, `copy-source b/k` (no versionId) -> `b/k` | **400 InvalidRequest** "This copy request is illegal because it is trying to copy an object to itself without changing the object's metadata, storage class, website redirect location or encryption attributes." |
  | `copy-source b/k?versionId=null` -> `b/k` | **200**, `CopySourceVersionId=null`, current body becomes the null generation's |
  | `copy-source b/k?versionId=<the current version>` -> `b/k` | **200** |
  | unversioned bucket, `copy-source b/k` -> `b/k` | **400 InvalidRequest** (same message) |

  So the reference server's rule is "reject only when no source version is
  named", which is exactly the discriminator the Flyology predicate omits.

**Repro:** `tests/repros/src/repro_backend_memory_2.adb`. On a private
`Backends.Memory.Store (4, 64, 1 MiB)` it enables versioning, PUTs `v1` then
`v2`, and (control) confirms a same-key `Copy_Object` with the default
`Current_Version_Selector` is still `Invalid_Request` — the behaviour AWS and
MinIO also reject. It then performs the same-key copy with
`Source_Selector => (Exact_Version, V1)` and asserts `Success`, a
`Source_Identity` naming V1, and a current body of `v1`. A second store
repeats the case with `Null_Version_Selector` after an unconfigured PUT. It
finally drives the same restore over the in-process S3 application with
`x-amz-copy-source: /copy-restore/k?versionId=<v1>` to destination
`/copy-restore/k`.

**Output** (`cd tests/repros && ./run.sh repro_backend_memory_2`, exit status
**1**):

```
  ok: exact: bucket created
  ok: exact: versioning enabled
  ok: exact: first PUT published
  ok: exact: second PUT published
  -- exact: v1 41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602 v2 9386a25901aec99598857ac6f2616db093bd4fc09678d8ca98ce1c22bef3b6f3
  ok: exact: current body is v2
  -- control: same-key copy without a selector -> INVALID_REQUEST
  ok: control: unselected same-key copy is still Invalid_Request
  -- exact: same-key copy with Source_Selector = (Exact_Version, v1) -> INVALID_REQUEST
  FAILED: exact: same-key copy of an exact source generation succeeds
  FAILED: exact: Source_Identity names the selected generation
  -- exact: destination identity 
  -- exact: current body after restore 'v2'
  FAILED: exact: restore republished the v1 bytes as current
  ok: null: bucket created
  ok: null: unconfigured PUT published the null generation
  ok: null: versioning enabled
  ok: null: enabled PUT published
  ok: null: current body is e1
  -- null: same-key copy with Null_Version_Selector -> INVALID_REQUEST
  FAILED: null: same-key copy of the null generation succeeds
  -- null: current body after restore 'e1'
  FAILED: null: restore republished the null-generation bytes
  ok: wire: CreateBucket is 200
  ok: wire: PutBucketVersioning is 200
  ok: wire: first PUT is 200
  -- wire: v1 version id 1705f7127d0e471eb4a961a3b1f49d8b4192533a28aaf416a5fcba966bee7b4b
  ok: wire: second PUT is 200
  -- wire: v2 version id 28305ded3ed79f37c4548decbe8c69e3621949effc3587027dbb21c0c87da392
  ok: wire: current body is v2
  -- control: wire same-key copy without versionId -> 400
  ok: control: wire unselected same-key copy is still 400
  -- wire: CopyObject /copy-restore/k?versionId=1705f7127d0e471eb4a961a3b1f49d8b4192533a28aaf416a5fcba966bee7b4b -> 400
  -- wire: response body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>Invalid request</Message><Resource>/copy-restore/k</Resource></Error>
  FAILED: wire: versioned same-key CopyObject is 200
  FAILED: wire: response names the selected source generation
  -- wire: current body after restore 'v2'
  FAILED: wire: restore republished the v1 bytes as current
BUG REPRODUCED: 8 failed expectation(s)
```

**Description:** The self-copy guard in `Copy_Object` compares only the source
and destination bucket/key and the four directive fields; it never looks at
`Options.Source_Selector`. As a result the operation S3 clients use to restore
a previous version — `CopyObject` with `x-amz-copy-source:
/bucket/key?versionId=OLD` and the same destination bucket and key — is
answered `Invalid_Request` / HTTP 400 before the source snapshot is even
fetched, so no generation is published and the restore fails. Every version-
aware caller hits it: `aws s3api copy-object`, the AWS console's "restore
previous version", and any lifecycle or rollback tooling built on the same
idiom. It is fully deterministic and identical in the memory, files, and SQLite
backends (`files.adb:7602-7611`, `sqlite.adb:2436-2445`), so the published
compatibility claim at `docs/compatibility/s3.md:61` ("retained exact source
generations", "repeated six-server byte oracle") is not met for this input, and
the measured MinIO lane diverges. No existing test asserts the wrong behaviour;
the case is simply uncovered (`tests/src/copy_object_conformance.adb` uses no
selector, `tests/src/versioned_object_conformance.adb:335-345` and `:810-825`
copy exact and null sources only to a different bucket and key). A fix is a
maintainer decision about the guard's scope rather than a mechanical change:
the narrow reading measured on MinIO is "reject only when
`Options.Source_Selector.Kind = Current_Version`", which also permits an
explicit copy of the current version onto itself; a stricter reading would
additionally reject an exact selector that resolves to the current generation.
The choice is externally visible policy, and it belongs in the `Copy_Object`
contract at `backends.ads:1969-2010`, which currently states no self-copy rule
at all.

---

### BACKEND-MEMORY-3: backend read contracts cannot report a selected delete marker, so GET/HEAD of a marker are plain Not_Found

**Verdict:** CONFIRMED (backend half of the same defect as SERVER-2, which is
verified at the wire level in the SERVER area; consolidate them).

**Severity:** P2 (discovery said P2). The current-read case is a missing
response header on an otherwise correct 404; the exact-version case is a wrong
error classification (404 instead of 405). Both are wrong diagnostics rather
than a wrong success/failure outcome, so P2 under the rubric. It is not P0:
stock SDK clients still see an error either way.

Verified by reading:

- `src/flyology-object_storage-backends-memory.adb:318-329`
  (`Selected_Object_Index`) returns 0 when the selected generation
  `Is_Delete_Marker`, for every selector kind including `Exact_Version`. Every
  read goes through it.
- `src/flyology-object_storage-backends-memory.adb:1729-1746` (`Head`) and
  `:1748-1760` (`Attributes`) set `Info := Empty_Info` / `Snapshot := (others
  => <>)` and `Result := Not_Found` when the index is 0; `Fetch`
  (`:1562-1566`) does the same after distinguishing only a missing bucket.
- `src/flyology-object_storage.ads:39-52`: `Status` has no delete-marker value.
  `src/flyology-object_storage.ads:554-562`: `Object_Information` has no
  marker flag. So `Head_Object`, `Get_Object`, and `Get_Object_Attributes`
  (`backends.ads:2049-2117`) have no channel for the fact at all — this is an
  interface gap, not a memory-backend coding slip.
- The information does exist in the store: `Listed_Version.Is_Delete_Marker`
  (`backends.ads:98-104`) is populated from `Objects (Index).Is_Delete_Marker`
  at `memory.adb:2671` and comes back correctly from `List_Object_Versions`
  (the control in the program below).
- `review/baseline/service-2.json`, `GetObjectOutput.DeleteMarker` (header
  `x-amz-delete-marker`): "If the current version of the object is a delete
  marker, Amazon S3 behaves as if the object was deleted and includes
  `x-amz-delete-marker: true` in the response. If the specified version in the
  request is a delete marker, the response returns a `405 Method Not Allowed`
  error and the `Last-Modified: timestamp` response header."
  `HeadObjectOutput.DeleteMarker` carries the same header.

Refutation attempts that failed:

- Looked for a server-side fallback that could synthesise the header from a
  `List_Object_Versions` probe on a 404: `rg x-amz-delete-marker
  src/flyology-object_storage-server-s3_applications.adb` hits only the
  DeleteObject response and the Object Lambda forwarding paths, never the
  GET/HEAD handlers.
- Checked whether the `.ads` contracts promise the S3 behaviour: they do not,
  which is why this is contract drift against the pinned model rather than an
  `.ads` violation.
- Checked `docs/compatibility/s3.md` and
  `docs/qualification/list-object-versions.md:139-140`: the latter claims only
  "exact-generation GET/HEAD, simple marker publication, and permanent exact
  deletion", never marker read semantics. So it is not a documented limitation
  that names this behaviour either.
- **Checked what a real server does**, on the same pinned MinIO container
  described under BACKEND-MEMORY-2: HEAD of a key whose current generation is a
  delete marker returns **404 with `x-amz-delete-marker: true` and
  `x-amz-version-id: <marker>`**; HEAD and GET of the exact marker version
  return **405 Method Not Allowed**. That is exactly the pinned model's text,
  so the divergence is real and not a documentation artefact.

**Repro:** `tests/repros/src/repro_backend_memory_3.adb`. On a private
`Backends.Memory.Store (4, 64, 1 MiB)` it enables versioning, PUTs `k`, and
deletes it with `Current_Version_Selector` so `Delete_Selected_Object` reports
`Delete_Marker_Created` and returns the marker's version ID. The control that
passes shows `List_Object_Versions` does report `Is_Delete_Marker` for that
generation. It then asserts the two distinctions the read surface must offer:
`Head_Object` of the marker-hidden key must differ in some observable way from
`Head_Object` of a key that never existed, and `Head_Object` with
`Selector => (Exact_Version, marker)` must differ from `Head_Object` with an
unknown version ID and must carry the marker's `Modified` time. A second
control confirms an exact HEAD of the retained live generation still succeeds,
and a final check covers the same hole on `Get_Object_Attributes`.

**Output** (`cd tests/repros && ./run.sh repro_backend_memory_3`, exit status
**1**):

```
  ok: setup: bucket created
  ok: setup: versioning enabled
  ok: setup: object published
  -- setup: live version 41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602
  ok: setup: simple delete published a delete marker
  -- setup: marker version 9386a25901aec99598857ac6f2616db093bd4fc09678d8ca98ce1c22bef3b6f3
  ok: control: List_Object_Versions works
  -- control: listed version '9386a25901aec99598857ac6f2616db093bd4fc09678d8ca98ce1c22bef3b6f3' is_latest TRUE is_delete_marker TRUE
  -- control: listed version '41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602' is_latest FALSE is_delete_marker FALSE
  ok: control: the listing surface reports the marker generation
  -- head absent key          : NOT_FOUND size 0 modified 0 version ''
  -- head marker-hidden key   : NOT_FOUND size 0 modified 0 version ''
  FAILED: current HEAD distinguishes a delete marker from an absent key
  -- head unknown version id  : NOT_FOUND size 0 modified 0 version ''
  -- head exact marker version: NOT_FOUND size 0 modified 0 version ''
  FAILED: exact HEAD distinguishes a delete marker from an unknown version
  FAILED: exact HEAD of a marker carries the marker's Last-Modified time
  -- head exact live version  : SUCCESS size 7 modified 1788746412 version '41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602'
  ok: control: exact HEAD of the retained live generation succeeds
  -- attributes exact marker  : NOT_FOUND
  FAILED: GetObjectAttributes on a marker generation is not plain Not_Found
BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** `Selected_Object_Index` folds a delete marker into "no
object" before any read can see it, and neither `Status` nor
`Object_Information` can carry the fact, so the backend interface simply has no
way to tell an adapter that the generation it selected is a marker. A caller
therefore cannot distinguish "this key is hidden by a delete marker" from "this
key never existed", nor "this exact version is a marker" from "this version ID
is unknown", through `Head_Object`, `Get_Object`, or `Get_Object_Attributes`.
Over HTTP that surfaces as a 404 with no `x-amz-delete-marker: true` for the
current read and a 404 instead of a 405-with-`Last-Modified` for an exact
marker read (the wire-level half is SERVER-2, verified separately). Anyone
writing version-aware tooling hits it — bucket replication, backup/sync
reconciliation, and anything that must reproduce delete markers keys on that
header. The tag, legal-hold, retention, and attribute surfaces
(`memory.adb:2016-2240`, `:1748-1794`) share the same `Selected_Object_Index`
and the same blind spot. It is deterministic. An existing test asserts the
current behaviour rather than the S3 one:
`tests/src/versioned_object_conformance.adb` requires a simple delete to hide
only current reads, i.e. marker reads are `Not_Found`, so a fix must update
that expectation. A fix is a public-interface decision the maintainer has to
make: either add a `Status` value (for example `Delete_Marker_Selected`) whose
`Info` still carries `Modified` and `Version`, or add an `Is_Delete_Marker`
field to `Object_Information` and let the read return `Not_Found` with a
populated snapshot. Both are visible additions to
`src/flyology-object_storage.ads` and must be reflected in the `Head_Object` /
`Get_Object` / `Get_Object_Attributes` contracts at
`backends.ads:2049-2117`, and implemented identically in the files and SQLite
backends.

---

## The discovery report's uncounted observations

I re-read each one against the sources and, for two of them, measured the
behaviour with `tests/repros/src/repro_backend_memory_probe.adb` (a probe, not a
bug reproduction: it asserts the dispositions below, so it PASSES with exit
status 0). None is promoted to a finding; there is no BACKEND-MEMORY-4.

**1. Read-path reservation makes GET able to return `Capacity_Exceeded` near
the byte cap. Stays an observation (documented policy).**
Confirmed by reading `memory.adb:1567-1574`: `Fetch` reserves
`Byte_Count (Objects (Index).Data.Length)` and returns `Capacity_Exceeded`
when it does not fit, before copying. `docs/architecture/memory-backend.md`
documents the coexistence-headroom model and
`tests/src/object_storage_test_cases.adb:5230-5240` asserts it. It is a stated
property of a bounded reference oracle, not a defect.

**2. Unknown-length sources are charged allocator capacity, not logical size.
Stays an observation (documented policy).**
`Growth_Capacity` (`memory.adb:142-157`) doubles from at least 4,096, and
`Bytes_Used` reflects the allocated capacity. Documented in
`docs/architecture/memory-backend.md` and pinned by the `Slack_Store` case.

**3. An unknown, stale, or prefix-excluded paired `ListObjectVersions` cursor
is `Invalid_Request`. Stays an observation, but with measured evidence of an
oracle divergence.**
Confirmed by reading `memory.adb:2675-2690`: when the paired marker's
generation is not among the prefix-filtered candidates, `Result :=
Invalid_Request`. The probe measured the three cases: a fresh service cursor
resumes; removing an *unrelated* generation leaves it working; removing the
generation the cursor names makes the next page `INVALID_REQUEST` with no
entries and `Is_Truncated` false — the client is **rejected**, not skipped
forward and not restarted; a prefix that excludes the marked key is also
`INVALID_REQUEST`. The policy is deliberate: it is pinned at
`tests/src/versioned_object_conformance.adb:776` ("unknown exact version
cursor") and named in `docs/qualification/list-object-versions.md:167`
("prefix-scoped cursor rejection"). On the pinned MinIO container, by contrast,
a stale cursor whose generation was deleted returns the remaining versions
normally, and a fabricated unknown `version-id-marker` with a valid
`key-marker` is ignored rather than rejected. I am not promoting this to a
finding, for two reasons: the repository documents and gates the rejection, and
MinIO is a weak oracle here because its `NextKeyMarker` is an opaque internal
token (observed literally as `alpha[minio_cache:v2,return:]`) rather than an
AWS-shaped key marker, so its tolerance says little about AWS's rule. Settling
it needs a real AWS account or the RustFS/SeaweedFS lanes; the practical
exposure is a client paginating `ListObjectVersions` across a concurrent
permanent delete of its own cursor generation, which gets a 400 and must
restart the listing from the beginning.

**4. A missing bucket is `Not_Found` from some operations and
`Bucket_Not_Found` from others. Stays an observation.**
Confirmed: `Head` (`memory.adb:1729-1746`) and `Attributes` (`:1748-1794`)
never call `Bucket_Index` at all and reach `Not_Found` through `Index = 0`;
`List` (`:2531-2534`), `Start_Multipart` (`:2816-2819`), `List_Uploads`
(`:2852-2855`) and `Enable_Bucket_Object_Lock` (`:462-464`) return `Not_Found`
explicitly; `Fetch` (`:1562-1564`), tags, annotations and the delete paths
return `Bucket_Not_Found`. The contract requires the distinction only for
`Delete_Object_Tags` (`backends.ads:2620-2622`: "Not_Found means the bucket
exists but the key does not. Bucket_Not_Found means the bucket itself does not
exist"), and the server routes that care call `Head_Bucket` first. Contract
drift with no reachable wrong answer today; worth tightening if the
distinction is ever generalised.

**5. In-place replacement does not reset a reused slot's `Legal_Hold` and
`Retention`. Stays an observation (unreachable).**
Confirmed by reading `Commit` (`memory.adb:1509-1539`): the reused slot's
fields are assigned individually and `Legal_Hold` / `Retention` are not among
them, while a *freed* slot is fully reset with `Objects (Target_At) := (others
=> <>)` (`:1902`, `:1953`). The path is unreachable because in-place
replacement happens only under Unconfigured or Suspended versioning, while
`Put_Legal_Hold` and `Put_Retention` require both Object Lock and
`Versioning_Enabled` (`:2026-2034`, `:2088-2095`), and
`Enable_Bucket_Object_Lock` itself requires `Versioning_Enabled` (`:465-466`).
A defensive reset would be cheap insurance if Object Lock is ever permitted
under suspension.

**6. `Adjust` sets `Capacity := Length` before allocating, so a `Storage_Error`
there can produce a double release. Stays an observation; confirmed
`Storage_Error`-only and not reachable otherwise.**
The mechanism is real and I re-derived it precisely: `Adjust`
(`memory.adb:100-115`) nulls `Data.Value`, sets `Data.Capacity := Data.Length`,
and only then allocates; `Fetch`'s handler (`:1587-1592`) releases the
reservation only when `Copied` is still False, which is exactly the case if the
`Data := Objects (Index).Data;` assignment raises inside `Adjust` — and the
caller's `Release_Buffer` (`:3456-3464`) then releases `Data.Capacity`, now
nonzero, a second time. The only guard is
`Release_Transient`'s `raise Program_Error with "memory reservation underflow"`
(`:1379-1385`); note that with a concurrent operation holding its own
reservation the second release would not underflow the global counter at all
and would silently borrow that operation's accounting instead. The probe drove
every reachable path that reserves transient bytes — three successful GETs, a
GET whose sink raises in `Begin_Object`, a GET whose sink raises in `Write`, a
conditional GET rejected after reservation, an unsatisfiable-range GET, a
CopyObject followed by a delete, a conditional PUT rejected at publication, a
PUT rejected for capacity, and a multipart stage-then-abort — and `Bytes_Used`
returned to exactly the retained baseline (4,096) after every one, and to 0
after teardown. So there is no reachable underflow or leak; provoking the
anomaly needs a real allocation failure at a specific instruction, which no
reproduction program can arrange deterministically. Structurally,
`Release_Buffer` zeroing the buffer before releasing is what makes the common
paths safe; the `Adjust` window is the one place that ordering is inverted.

**7. `Include_Part_Digest` raises `Constraint_Error` for a part ETag that is
not 32 hex characters. Stays an observation (unreachable).**
Confirmed at `memory.adb:219-241`. Part ETags are always `GNAT.MD5.Digest`
output, so no caller can reach it; it is an internal assertion.

**8. `List_Objects` and `List_Object_Versions` map any unexpected exception to
`Backend_Unavailable`. Stays an observation.**
Confirmed at `memory.adb:5860-5868` and `:5886-5894`: both re-raise only
`Flyology.Cancellation.Operation_Cancelled` and `Flyology.IO.Timeout_Error`
and turn everything else — including a `Program_Error` from an internal
invariant such as the reservation-underflow guard — into a 503-class result.
That hides invariant failures behind a retryable status, which is a debugging
and operability concern rather than a wrong answer on valid input.

**9. Linear scans and the O(n^2) `List_Versions` insertion.** Performance
characteristics of a bounded reference oracle, not correctness; I did not
measure them (and the host's power profile was not established, which the
repository's performance-testing rule requires before benchmarking).

**Probe output** (`cd tests/repros && ./run.sh repro_backend_memory_probe`,
exit status **0** — this program passes, which is the point):

```
  ok: accounting: empty store uses no bytes
  ok: accounting: bucket created
  ok: accounting: object published
  -- accounting: retained baseline 4096
  ok: accounting: read1 succeeded
  ok: accounting: read2 succeeded
  ok: accounting: read3 succeeded
  -- accounting: three successful GETs Bytes_Used 4096 expected 4096
  ok: accounting: three successful GETs leaves Bytes_Used unchanged
  ok: accounting: Begin_Object failure propagates
  -- accounting: GET whose sink raised in Begin_Object Bytes_Used 4096 expected 4096
  ok: accounting: GET whose sink raised in Begin_Object leaves Bytes_Used unchanged
  ok: accounting: Write failure propagates
  -- accounting: GET whose sink raised in Write Bytes_Used 4096 expected 4096
  ok: accounting: GET whose sink raised in Write leaves Bytes_Used unchanged
  -- accounting: conditional GET -> NOT_MODIFIED
  -- accounting: conditional GET rejected after reservation Bytes_Used 4096 expected 4096
  ok: accounting: conditional GET rejected after reservation leaves Bytes_Used unchanged
  -- accounting: unsatisfiable range GET -> INVALID_RANGE
  -- accounting: unsatisfiable range GET Bytes_Used 4096 expected 4096
  ok: accounting: unsatisfiable range GET leaves Bytes_Used unchanged
  ok: accounting: copy published
  ok: accounting: copy removed
  -- accounting: CopyObject then DeleteObject Bytes_Used 4096 expected 4096
  ok: accounting: CopyObject then DeleteObject leaves Bytes_Used unchanged
  -- accounting: conditional PUT -> PRECONDITION_FAILED
  -- accounting: conditional PUT rejected at publication Bytes_Used 4096 expected 4096
  ok: accounting: conditional PUT rejected at publication leaves Bytes_Used unchanged
  -- accounting: oversize PUT -> CAPACITY_EXCEEDED
  ok: accounting: oversize PUT is Capacity_Exceeded
  -- accounting: PUT rejected for capacity Bytes_Used 4096 expected 4096
  ok: accounting: PUT rejected for capacity leaves Bytes_Used unchanged
  ok: accounting: upload initiated
  ok: accounting: part staged
  ok: accounting: upload aborted
  -- accounting: multipart stage then abort Bytes_Used 4096 expected 4096
  ok: accounting: multipart stage then abort leaves Bytes_Used unchanged
  ok: accounting: object removed
  ok: accounting: bucket removed
  -- accounting: empty store after teardown Bytes_Used 0 expected 0
  ok: accounting: empty store after teardown leaves Bytes_Used unchanged
  ok: cursor: bucket created
  ok: cursor: versioning enabled
  ok: cursor: generation1 published
  ok: cursor: generation2 published
  ok: cursor: generation3 published
  ok: cursor: first page is truncated
  -- cursor: page 1 marker key 'alpha' version '6fe06e71fc2d5dfae869aada68acd5476c882bb98ff655d732d7c9289359b0ad'
  -- cursor: fresh cursor -> SUCCESS entries1
  ok: cursor: a fresh service cursor resumes
  ok: cursor: unrelated generation removed
  -- cursor: after removing an unrelated generation -> SUCCESS entries1
  ok: cursor: cursor still resumes after an unrelated removal
  ok: cursor: the marked generation was removed
  -- cursor: stale cursor (marked generation deleted) -> INVALID_REQUEST entries0 truncated FALSE
  ok: cursor: a stale cursor is REJECTED, not skipped or restarted
  ok: cursor: refreshed page
  -- cursor: prefix-excluded cursor -> INVALID_REQUEST
  ok: cursor: a prefix-excluded cursor is also rejected
PASS
```

## Docker use

The pinned MinIO image from `tests/scripts/test-minio.sh`
(`quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`,
verified to report `RELEASE.2025-09-07T16-13-09Z
commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb`, matching that script's own
provenance check) was started by hand as a single detached container on
`127.0.0.1:19000` and driven with the `aws` CLI, for the CopyObject oracle
under BACKEND-MEMORY-2, the delete-marker read oracle under BACKEND-MEMORY-3,
and the cursor oracle under observation 3. The Docker scripts themselves were
not run, so no `alr -n build` was triggered from them. The container was
stopped after each use.
