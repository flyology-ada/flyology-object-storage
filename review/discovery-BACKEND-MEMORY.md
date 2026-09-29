# Correctness discovery: BACKEND-MEMORY (memory backend, backend interface, shared listing)

Scope: `src/flyology-object_storage-backends.ads` (lines 1-750 and 1900-2878
in full; the bucket-configuration contracts at 750-1900 skimmed by signature),
`src/flyology-object_storage-backends.adb` (full),
`src/flyology-object_storage-backends-memory.ads` (public header, private part
1333-1859), `src/flyology-object_storage-backends-memory.adb` (full: Owned_Bytes
1-260; protected `Memory_State` 258-3425 including bucket configuration
accounting 682-1366, reservations and `Commit` 1366-1543, fetch/head/attributes
1543-1796, `Delete_Many`/`Delete_Selected` 1796-2016, legal hold/retention/tags
2016-2240, annotations 2240-2523, `List`/`List_Versions` 2523-2805, multipart
2805-3424; the `Store` overrides 3427-6320), the three shared listing packages
(`-backends-listing`, `-backends-bucket_listing`,
`-backends-multipart_listing`, full), `docs/architecture/memory-backend.md`,
`docs/qualification/{list-objects-v1,list-objects-v2,list-object-versions,
list-parts-preparation,list-multipart-uploads-preparation,conditional-put,
bucket-versioning,delete-objects,complete-multipart-upload,upload-part-copy}.md`.
Reference material: `review/baseline/service-2.json` (`GetObjectOutput` and
`HeadObjectOutput` `DeleteMarker` members). Root-package helpers consulted for
refutation only: `Resolve_Range`, `Merge_Bucket_Versioning`,
`Evaluate_Object_Write_Conditions`, `Evaluate_Object_Delete_Conditions`,
`Listing_Follows_Cursor`, `Valid_Object_Key`. Server call sites consulted for
reachability only: `src/flyology-object_storage-server-s3_applications.adb`
(ListMultipartUploads 11150-11260, UploadPartCopy 12732-12860, CopyObject
source-version parsing 14060-14110). Existing coverage inspected:
`tests/src/object_storage_test_cases.adb` (memory capacity cases 4037-4430,
5194-5410; multipart upload listing 3273-3480),
`tests/src/versioned_object_conformance.adb` (700-800, 1140-1260, 325-375,
810-835), `tests/src/copy_object_conformance.adb`,
`tests/src/conditional_put_conformance.adb` (by description),
`tests/src/s3_multipart_listing_benchmark.adb`.

Severity rubric: P0 memory/aliasing unsafety, security, data loss, hang, or an
interop-breaking violation a stock client or server rejects; P1 wrong result
or unexpected exception on valid input via a reachable path, or a documented
contract violated; P2 edge-case incorrectness, wrong diagnostics, or contract
drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| BACKEND-MEMORY-1 | ListMultipartUploads paired cursor skips same-key uploads whose SHA-256 upload IDs sort against initiation time | P1 | High |
| BACKEND-MEMORY-2 | Same-key CopyObject with an exact or null source selector (version restore) is rejected as Invalid_Request | P1 | Medium |
| BACKEND-MEMORY-3 | Backend read contracts cannot report a selected delete marker, so GET/HEAD of a marker are plain Not_Found | P2 | Medium |

---

### BACKEND-MEMORY-1: ListMultipartUploads paired cursor skips same-key uploads whose SHA-256 upload IDs sort against initiation time

**Location:** `src/flyology-object_storage-backends-multipart_listing.adb:17-30`
(ordering), `:81-92` (marker filter), `:139-149` (next marker);
`src/flyology-object_storage-backends-memory.adb:2829-2833` (upload ID
generation); contract `src/flyology-object_storage-backends.ads:2712-2723`.

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-backends-memory.adb:2829-2833` (upload IDs are
hex SHA-256 digests of a counter; lexical order is unrelated to creation order):

```ada
         Next_Upload := Next_Upload + 1;
         Upload_ID := Ada.Strings.Unbounded.To_Unbounded_String
           (GNAT.SHA256.Digest
              (Bucket & Character'Val (0) & Key & Character'Val (0) &
               Long_Long_Integer'Image (Next_Upload)));
```

`src/flyology-object_storage-backends-multipart_listing.adb:17-30` (page
order within one key is initiation time, then upload ID):

```ada
   function Before (Left, Right : Candidate) return Boolean is
      ...
      return Left_Key < Right_Key
        or else
          (Left_Key = Right_Key
           and then
             (Left.Initiated < Right.Initiated
              or else
                (Left.Initiated = Right.Initiated
                 and then US.To_String (Left.Upload_ID) <
                   US.To_String (Right.Upload_ID))));
```

`src/flyology-object_storage-backends-multipart_listing.adb:81-92` (the
exclusive marker is applied by lexical upload ID only):

```ada
         if Candidate_Key < After_Key
           or else
             (Candidate_Key = After_Key
              and then
                (After_ID'Length = 0 or else Candidate_ID <= After_ID))
         then
            return;
         end if;
```

`src/flyology-object_storage-backends-multipart_listing.adb:139-149` (the
next marker is the last returned upload's key and ID):

```ada
      if Result.Is_Truncated then
         if Returned = 0 then
            Result.Next_After := Item.Options.After;
         else
            Result.Next_After.Key := Item.Candidates (Returned).Key;
            Result.Next_After.Upload_ID :=
              Item.Candidates (Returned).Upload_ID;
         end if;
      end if;
```

Contract, `src/flyology-object_storage-backends.ads:2712-2716`:

```ada
   --  Return one atomic snapshot of active uploads after the exclusive marker.
   --  Keys use unsigned bytewise lexical order. Uploads with the same key use
   --  initiation-time order and upload ID breaks equal-time ties; marker
   --  filtering independently follows S3's lexical upload-ID rule.
```

`docs/qualification/list-multipart-uploads-preparation.md:39-44`:

> The later implementation and oracle must exercise inverse
> upload-ID/initiation-time data rather than assume those orders coincide. A
> service-produced marker pair must always resume without skipping, repeating,
> or looping, with a deterministic upload-ID tie break for equal initiation
> times.

**Failure scenario:** Two uploads U1 then U2 are created for the same key in
different Unix seconds (`Created` is `Current_Unix_Time`, one-second
resolution, `memory.adb:207-208`), and SHA-256 happens to give `ID(U1) >
ID(U2)` lexically. The page order is U1 (older) then U2. A listing with
`Maximum = 1` returns U1 and `Next_After = (key, ID(U1))`. The continuation
request applies the lexical rule at `multipart_listing.adb:88`:
`ID(U2) <= ID(U1)` is true, so U2 is dropped; the page is empty and
untruncated. U2 is never returned by any continuation of that cursor. The
symmetric case (`ID(U1) < ID(U2)` but U2 created first) loses U1 the same way.
The store's own IDs make the inversion common: with bucket `b`, key `k`, the
first and second IDs generated are `c9342c80...` and `a9ec2e9e...`
(computed with python3 from the exact digest input
`bucket & NUL & key & NUL & " 1"`), which already invert.

**Reproduction test sketch:** Memory store, bucket `b`. `Create_Multipart_Upload
("b", "k")` -> U1; wait until `Current_Unix_Time` advances by one second;
`Create_Multipart_Upload ("b", "k")` -> U2 (with these inputs `ID(U1) >
ID(U2)`). `List_Multipart_Uploads` with `Maximum => 1`: expect U1,
`Is_Truncated = True`. Continue with `After => Page.Next_After`, `Maximum =>
10`. Expected: one upload, U2, untruncated. Actual: zero uploads, untruncated.
Over the loopback S3 server (`tests/src/s3_memory_server.adb`), the same is
visible as `ListMultipartUploads?max-uploads=1` followed by
`key-marker=k&upload-id-marker=<U1>` returning an empty `ListMultipartUploadsResult`.

**Existing coverage:**
`tests/src/object_storage_test_cases.adb:3273-3480` (`Exercise_Multipart_Upload_Listing`)
creates both `same`-key uploads in one loop iteration burst, so their
`Initiated` values are equal and the lexical tie break coincides with the
marker rule; the "multipart upload-ID marker filtering" assertion at 3357-3367
only exercises the equal-time case. No test creates same-key uploads across a
second boundary. `tests/src/s3_multipart_listing_benchmark.adb` measures
throughput only.

**Refutation attempts:** Checked whether upload IDs are lexically monotone
(they are SHA-256 hex digests, `memory.adb:2831`, so no). Checked whether the
server re-sorts or re-filters (`s3_applications.adb:11195-11199` passes the
markers straight through as `After`). Checked whether the `.ads` contract
sanctions the loss: it fixes the two rules independently but the qualification
document quoted above forbids skipping under a service-produced cursor. Checked
the files/SQLite backends' ID schemes only to the extent that they share
`Multipart_Listing` (they do, so the same builder rule applies there whenever
their IDs are not lexically monotone; not verified for those backends).

---

### BACKEND-MEMORY-2: Same-key CopyObject with an exact or null source selector (version restore) is rejected as Invalid_Request

**Location:** `src/flyology-object_storage-backends-memory.adb:4977-4987`;
contract `src/flyology-object_storage-backends.ads:1970-2010` (no self-copy
rule documented). Identical code in
`src/flyology-object_storage-backends-files.adb:7602-7610` and
`sqlite/src/flyology-object_storage-backends-sqlite.adb:2436-2444` (noted for
cross-reference; not reviewed further here).

**Severity:** P1. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage-backends-memory.adb:4977-4987`:

```ada
      elsif Source_Bucket = Destination_Bucket
        and then Source_Key = Destination_Key
        and then Options.Metadata_Directive = Copy_Metadata
        and then Options.Tagging_Directive = Copy_Tags
        and then Options.Annotation_Directive = Copy_Annotations
        and then Options.Selected_Checksum = No_Checksum
        and then not Options.Metadata.Website_Redirect_Location.Is_Set
      then
         Result := Invalid_Request;
         return;
      end if;
```

The predicate never consults `Options.Source_Selector`, so an
`Exact_Version` or `Null_Version` source that is *not* the current generation
is treated as "copying an object onto itself".

The server reaches this with a versioned copy source
(`src/flyology-object_storage-server-s3_applications.adb:14080-14101` parses
`?versionId=` from `x-amz-copy-source` into `Copy_Options_Value.Source_Selector`).

AWS behaviour (from memory, unverified): the "InvalidRequest: This copy
request is illegal because it is trying to copy an object to itself without
changing the object's metadata..." rejection applies when the *current*
object is copied onto itself; copying a noncurrent version onto its own key
(`aws s3api copy-object --copy-source bucket/key?versionId=OLD --bucket bucket
--key key`) is the documented way to restore a previous version and succeeds.
This can be checked against MinIO with `tests/scripts/test-*.sh`.

**Failure scenario:** Versioning enabled; PUT `k` -> v1; PUT `k` -> v2. A
client restores v1 with CopyObject source `b/k?versionId=v1`, destination
`b/k`, default directives. `Copy_Object` at 4977-4987 returns
`Invalid_Request` before `Fetch_For_Copy`; the server answers 400. Nothing is
published; the client's restore fails on every backend.

**Reproduction test sketch:** Memory store, `Put_Bucket_Versioning (Enabled)`;
`Put_Object ("b","k","v1")`, `Put_Object ("b","k","v2")` capturing identities;
`Copy_Object ("b","k","b","k", Options => (Source_Selector => (Exact_Version,
V1), others => default))`. Expected: `Success`, a new current generation whose
body is `v1` and whose `Source_Identity.Version_ID = V1`. Actual:
`Invalid_Request`. The same holds with `Null_Version_Selector` on a bucket
whose current version is opaque.

**Existing coverage:** `tests/src/versioned_object_conformance.adb:335-345`
and `810-825` copy exact and null sources only to a *different* bucket/key
(`Copy_Bucket`, `"exact"`/`"null"`). `tests/src/copy_object_conformance.adb`
exercises the same-key rejection only with the current source (no selector).
None asserts the same-key versioned restore.

**Refutation attempts:** Checked whether the server rejects or rewrites
same-key versioned copies before the backend (it does not; it only rejects
malformed version queries at 14101-14107). Checked whether
`Replace_Metadata` could be forced by the server for versioned sources (no).
Checked the `.ads` contract for a documented self-copy rule (none;
`backends.ads:1970-2010` describes source selection and directives only).
Confidence is Medium only because the AWS acceptance of the versioned
self-copy is from memory.

---

### BACKEND-MEMORY-3: Backend read contracts cannot report a selected delete marker, so GET/HEAD of a marker are plain Not_Found

**Location:** `src/flyology-object_storage-backends.ads:2049-2098`
(`Head_Object`, `Get_Object` contracts), `:2100-2117` (`Get_Object_Attributes`);
`src/flyology-object_storage-backends-memory.adb:318-329`
(`Selected_Object_Index`), `:1543-1594` (`Fetch`), `:1729-1746` (`Head`).

**Severity:** P2. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage-backends-memory.adb:318-329` (a delete marker,
current or exact, is folded into "no object"):

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

`src/flyology-object_storage-backends-memory.adb:1729-1746` (`Head` returns
`Not_Found` for both a missing key and a marker; `Fetch` at 1565-1567 does the
same):

```ada
         Info := Empty_Info;
         if Index = 0 then
            Result := Not_Found;
```

The interface offers no marker signal: `Head_Object`, `Get_Object`, and
`Get_Object_Attributes` (`backends.ads:2049-2117`; the attributes contract
begins at 2100) return only
`Object_Information` and `Status`, and `Status` has no delete-marker value.

Pinned model, `review/baseline/service-2.json`, `GetObjectOutput.DeleteMarker`
(header `x-amz-delete-marker`): "If the current version of the object is a
delete marker, Amazon S3 behaves as if the object was deleted and includes
`x-amz-delete-marker: true` in the response. If the specified version in the
request is a delete marker, the response returns a `405 Method Not Allowed`
error and the `Last-Modified: timestamp` response header."
`HeadObjectOutput.DeleteMarker` carries the same header.

The server has no other source for this: `rg x-amz-delete-marker
src/flyology-object_storage-server-s3_applications.adb` hits only the
DeleteObject response (17446) and Object Lambda forwarding (4596, 4789).

**Failure scenario:** Versioning enabled; PUT `k`; DELETE `k` (marker M
published, `Delete_Selected` -> `Publish_Marker`). (a) GET/HEAD `k`: memory
returns `Not_Found`; the server emits 404 without `x-amz-delete-marker: true`.
(b) GET `k?versionId=M`: `Selected_Object_Index` returns 0 -> `Not_Found`; the
server emits 404 `NoSuchVersion` (see `s3_applications.adb:13860` pattern)
instead of 405 with `Last-Modified`. Tag, legal-hold, retention, and
attribute reads of a marker generation fall into the same `Not_Found` path
(`Put_Tags`/`Get_Tags` 2150-2210, `Attributes` 1748-1794).

**Reproduction test sketch:** Memory store; enable versioning; `Put_Object
("b","k")`; `Delete_Selected_Object ("b","k", Current_Version_Selector, ...)`
giving `Outcome.Version_ID = M`. `Head_Object ("b","k")` -> `Not_Found`
(expected: a result that lets the adapter emit `x-amz-delete-marker: true`).
`Head_Object ("b","k", Selector => (Exact_Version, M))` -> `Not_Found`
(expected: a distinguishable "selected generation is a delete marker" result
carrying `Info.Modified`). Over the loopback server the observable is the
missing header on the 404 and the 404-instead-of-405 for the exact marker.

**Existing coverage:** `tests/src/versioned_object_conformance.adb` asserts
that a simple delete "hides only current reads" (marker -> `Not_Found`), i.e.
the suite pins the current behaviour; no test asserts a delete-marker signal.
`docs/qualification/list-object-versions.md` claims only "supports
exact-generation GET/HEAD, simple marker publication, and permanent exact
deletion" and does not claim marker read semantics.

**Refutation attempts:** Looked for a server-side fallback (a
`List_Object_Versions` probe on 404) -- none. Checked whether the `.ads`
contracts promise the S3 behaviour (they do not; hence P2 contract drift
against the pinned model rather than a `.ads` violation). Checked
`docs/compatibility/s3.md` for a claim of `x-amz-delete-marker` on reads --
only listings and DeleteObject mention markers. Stock clients accept the 404,
so this is not interop-breaking; it misleads version-aware tooling that keys
on the header.

---

## Areas reviewed with no findings

- `Owned_Bytes` (`memory.adb:100-206`): `Adjust` deep-copies with
  `Capacity := Length`; `Move` transfers ownership and zeroes the source;
  `Append`/`Reserve_Capacity` guard `Natural'Last`; no aliasing between the
  store and returned snapshots.
- Reservation protocol (`Reserve_Transient`/`Release_Transient`
  `memory.adb:1366-1385`, `Reserve_Buffer_Capacity`/`Release_Buffer`
  `memory.adb:3427-3465`): every path in `Put_Object_Internal`,
  `Put_Multipart_Part`, `Put_Object_Annotation`, `Copy_Object`,
  `Copy_Multipart_Part`, `Get_Object` releases exactly `Data.Capacity`; after a
  successful `Commit`/`Commit_Part`/`Put_Annotation` the buffer is moved
  (capacity 0) so no double release; failed commits leave the reservation for
  the caller's `Release_Buffer`. `Fetch_For_Copy` annotation reservation
  (`Annotation_Length` = post-`Adjust` capacities) is released either by
  `Commit` or by `Copy_Object` on every non-success path.
- `Commit` (`memory.adb:1387-1541`): conditions evaluated against the current
  non-marker generation inside the protected action; overwrite capacity uses
  `Byte_Limit - (Bytes - Existing)`; publication order burned before the first
  mutation; Unconfigured/Suspended in-place replacement, Enabled appends;
  identity fields match the contract at `backends.ads:1915-1919`.
- `Delete_Selected`/`Delete_Many` (`memory.adb:1796-2014`): unversioned
  physical delete, enabled marker append (also for absent keys, as S3), suspended
  null-marker replacement releasing the null generation's bytes, exact/null
  removal with legal-hold and retention refusal, MFA gating, slot reset
  `(others => <>)` on every removal, `Highest_Object` shrink. Batch behaviour
  matches `docs/architecture/memory-backend.md` (ordered, per-entry outcomes,
  later entries observe earlier mutations, one protected action).
- Versioning transitions: `Merge_Bucket_Versioning` never returns to
  Unconfigured; `Put_Bucket_Versioning` refuses Suspended under Object Lock;
  `Enable_Bucket_Object_Lock`, `Put_Legal_Hold`, `Put_Retention` require
  Enabled + Object Lock, so the in-place overwrite paths that do not reset
  `Legal_Hold`/`Retention` (see observations) are unreachable with a hold set.
- `Selected_Generation_Index` (`memory.adb:284-316`): newest publication
  wins; exact IDs never match null generations; at most one null generation
  per key can exist (all null publications replace in place).
- `List` + `Listing` (`memory.adb:2523-2553`, `listing.adb`): bytewise
  `String` ordering (Latin-1 positions = unsigned bytes), prefix filter,
  delimiter projection from the byte after the prefix, multi-byte/multi-char
  delimiters via `Ada.Strings.Fixed.Index`, key-equals-prefix listed as an
  object, common prefixes deduplicated and counted once, exclusive `After`
  applied to the projected key (a marker inside a prefix skips the prefix),
  smallest `Maximum + 1` retained so `Is_Truncated` is exact with exactly
  `Maximum` remaining, `Maximum = 0` untruncated (pinned project policy).
- `List_Versions` (`memory.adb:2555-2803`): key ascending / publication
  descending, `Is_Latest` across markers, `Version_ID = "null"` for null
  generations, key-only marker exclusive on the whole key, paired marker
  resumes after the exact generation, common-prefix cursor bound to the last
  hidden generation, unpaired version marker rejected.
- `Multipart_Listing` and `Bucket_Listing` builders apart from
  BACKEND-MEMORY-1: prefix/delimiter/`Maximum + 1` retention identical to
  `Listing`; upload-id marker without key marker is a no-op as documented.
- Multipart lifecycle (`memory.adb:2805-3422`, overrides 5897-6315): SHA-256
  upload IDs unique per store; part overwrite releases the old capacity;
  `List_Parts` strictly after the marker with exact truncation; completion
  validates ascending unique numbers, existence, ETag/checksum match, 5 MiB
  non-final minimum, expected size and checksum, destination conditions, then
  publishes atomically with `"md5-N"` ETag; completing an aborted upload and
  aborting a completed upload are `Not_Found`; abort and completion release
  staged bytes; `Delete_Bucket` refuses with active uploads.
- `Get_Object` (`memory.adb:5142-5240`): snapshot copied under the lock so a
  concurrent overwrite/delete cannot change streamed bytes; `Resolve_Range`
  clamps `last >= size`, suffix and open-ended forms, 416 for `first >= size`
  and for any range on an empty object; `Begin_Object` called exactly once.
- `Fetch_Range`/`Copy_Multipart_Part`: strict bounded-range-only contract;
  versioned copy sources are refused by the server with 501 before reaching
  the backend (`s3_applications.adb:12794-12799`).
- Bucket configuration byte accounting (`memory.adb:682-1364`, `Delete_Bucket`
  578-638): every put charges `Base + Incoming`, every delete and bucket delete
  subtracts the same lengths (policy, CORS, encryption, ownership, singleton
  documents plus metadata, metadata state, named configurations key+document);
  no asymmetric path found.
- Protected-object hygiene: no potentially blocking operation inside
  `Memory_State` (no `Clock`, delay, or entry calls; timestamps are passed in);
  all compound operations are single protected actions.

## Observations not counted

- Documented policy: an overwrite, multipart completion, or CopyObject needs
  coexistence headroom (`memory-backend.md`, asserted at
  `object_storage_test_cases.adb:5230-5240`), and every nonempty GET/Copy
  reserves a full body snapshot, so reads can return `Capacity_Exceeded` near
  the byte cap.
- Documented policy: unknown-length sources are charged allocator capacity
  (`Growth_Capacity`, minimum 8192 after the first chunk) rather than logical
  size; `Bytes_Used` reflects it (`memory-backend.md`; `Slack_Store` test
  5370-5405).
- Policy pinned by tests: an unknown or prefix-excluded paired
  version-id-marker is `Invalid_Request` (`memory.adb:2687-2690`,
  `versioned_object_conformance.adb:765-775`). Practical effect: a client
  paginating `ListObjectVersions` whose returned marker generation is deleted
  between pages receives 400 rather than resuming; AWS tolerance of a
  vanished marker is unverified.
- `Head`, `Attributes`, `List`, `List_Versions`, `List_Uploads`, `Start_Multipart`
  return `Not_Found` for a missing bucket while `Fetch`, tags, annotations and
  deletes return `Bucket_Not_Found`; the `.ads` contracts only require the
  distinction for tag deletion (`backends.ads:2620-2622`), and server routes
  call `Head_Bucket` first where it matters.
- `Commit` and `Complete_Multipart` in-place replacement (Unconfigured or
  Suspended) do not reset `Legal_Hold`/`Retention` of the reused slot; a
  freed slot is always reset, and a hold requires Enabled versioning, so the
  stale-hold path is unreachable today. Worth a defensive reset if Object Lock
  is ever allowed under suspension.
- Storage_Error-only accounting anomaly (Low confidence): `Adjust`
  (`memory.adb:100-115`) sets `Capacity := Length` before allocating; if the
  allocation inside `Fetch`/`Fetch_For_Copy`/`Get_Annotation` raises, the
  protected handler releases the snapshot reservation and the caller's
  `Release_Buffer` then releases `Data.Capacity` again, which can trip the
  `Program_Error` "memory reservation underflow" guard or borrow another
  caller's reservation. Same class for a Storage_Error after partial slot
  mutation in `Commit`/`Complete_Multipart` (metadata replaced, body not).
- `Include_Part_Digest` raises `Constraint_Error` for a stored part ETag that
  is not 32 hex characters; unreachable because part ETags are always
  `GNAT.MD5.Digest` output.
- `List_Objects`/`List_Object_Versions` overrides map any unexpected
  exception (including `Program_Error`) to `Backend_Unavailable`
  (`memory.adb:5864-5868`, `5890-5895`), which hides internal invariant
  failures behind a 503-class result.
- Linear scans in `Bucket_Index`, `Object_Index`, `Upload_Index`,
  `Part_Index`, and the O(n^2) `List_Versions` insertion/`Is_Latest` are
  performance, not correctness, properties of the reference oracle.
