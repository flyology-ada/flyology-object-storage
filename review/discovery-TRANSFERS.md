# Correctness discovery: TRANSFERS (multi-subject transfer client and multipart planning/codecs)

Scope: `src/flyology-object_storage-client-transfers.ads` (all 2,197 lines),
`src/flyology-object_storage-client-transfers.adb` (all of 1-3750; 3750-4814
read through the `Start_Copy_Object`, `Start_Upload_Part_Copy`,
`Prepare_Copy_From_Raw_Source`, `Normalize_Copy_Response` and
`Normalize_Upload_Part_Copy_Response` bodies, the remainder being the same
operation template as the six operations read in full),
`src/flyology-object_storage-s3-multipart.ads/.adb` (all),
`src/flyology-object_storage-s3-core.ads` (planner: `Multipart_Part_Count`,
`Valid_Multipart_Plan`, `Valid_Part_Size`), `Checksum_Policy` and `Checksums`
specs plus the `Composite`/`Encode_Object`/`Decode_Object` bodies,
`Low_Level` regions `Execute_Upload_Part` (14162-14200),
`Valid_Content_Range`/`Validate_Get_Object_Headers` (5933-5995),
`Decode_Get_Object_Response_Head` (7264-7288), `Prepare_Upload_Part`
(13689-13800), Malformed_Multipart mapping sites; server
`s3_applications.adb` 12917-13200 (completion checksum admission) for the
composite-header convention. Flyology primitives read read-only:
`flyology-task_scopes.ads/.adb` (all), `flyology-operations.ads` (Wait_All /
Wait_Some), `flyology-io-files.ads/.adb` (`Close`, `Read_At`),
`flyology-http-client.ads` (`Body_Size`, timeout semantics),
`flyology-http-client-request_bodies-files.ads/.adb` (`Range_Source`).
Docs: `docs/architecture/client-transfers.md`, the six multipart
qualification records. Coverage inspected:
`tests/src/flyology-object_storage-client-transfers-testing.adb`,
`tests/src/s3_transfer_many_corpus.adb`, `tests/src/s3_http_socket_corpus.adb`
(high-level upload/download lanes 16440-16990 and the scripted server
4700-4870), `tests/src/s3_implementation_corpus.adb` 760-850. Planner edge
arithmetic was re-checked with a small Python script (sizes 0, 1, 5 MiB,
5 MiB+1, 10,000 x part, 10,000 x part + 1, the 50,000 GiB bound and
2^63-1 against 5 MiB, 16 MiB and 5 GiB parts).

Severity rubric: P0 = memory/aliasing unsafety, security-relevant bypass or
exposure, data loss or durability violation, hang or deadlock in normal
operation, interop-breaking protocol violation a stock client or server
rejects. P1 = wrong result or unexpected exception on valid input via a
reachable path, or a documented contract (.ads, README, compatibility matrix,
qualification document) violated. P2 = edge-case incorrectness, wrong
diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| TRANSFERS-1 | `Download_File` misdiagnoses a 200 answer to a `Range` request as an "unsolicited representation interval" | P2 | High |

---

### TRANSFERS-1: `Download_File` misdiagnoses a 200 answer to a `Range` request as an "unsolicited representation interval"

**Location:** `src/flyology-object_storage-client-transfers.adb:1706-1717`

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-transfers.adb:1706-1717`
```ada
            if Head.Kind = Low_Level.Get_Object_Rejected then
               return
                 (Kind   => Download_Rejected,
                  Status => Head.Status,
                  Error  => Head.Error);
            elsif (Byte_Range_Header'Length = 0 and then Head.Status /= 200)
              or else
                (Byte_Range_Header'Length > 0 and then Head.Status /= 206)
            then
               raise Low_Level.Invalid_Response with
                 "GetObject returned an unsolicited representation interval";
            end if;
```

The one message covers two opposite situations. The second disjunct fires
when the caller asked for an interval and the server answered `200` with the
whole representation, which RFC 9110 section 14.2 permits ("a server MAY
ignore the Range header field", from memory, unverified). Nothing about that
response is an interval, let alone an unsolicited one.

Contract being drifted from, `docs/architecture/client-transfers.md`
(Multi-subject transfers section):
```
Callers may instead supply one S3 `Range` value; that mode accepts only HTTP
206 with a strict, coherent single `Content-Range` ... Missing, inverted,
multipart, unsolicited, or length-inconsistent intervals are protocol failures
and cannot publish a destination.
```
The refusal itself matches the documented policy (only 206 publishes in range
mode); the diagnostic does not describe the failure that occurred.

**Failure scenario:** A caller invokes `Download_File (..., Byte_Range_Header
=> "bytes=0-99")` against a server that ignores `Range` (or a proxy that
strips it) and answers `200 OK`, `Content-Length: <full size>`, no
`Content-Range`. `Decode_Get_Object_Response_Head` accepts the head (a 200
without `Content-Range` is valid at `low_level.adb:5985-5987`). Line 1712-1713
selects the second disjunct and line 1715 raises `Invalid_Response` with the
message above. The operator sees "unsolicited representation interval" and
looks for a stray 206/`Content-Range`, when the actual event is a full
representation delivered in place of the requested interval. In
`Transfer_Many` the same text lands in `Transfer_Result.Message` for that
subject.

**Reproduction test sketch:** In the `s3_http_socket_corpus` scripted server,
add a lane keyed `download-range-ignored` that answers a `GET` carrying
`Range: bytes=7-13` with `HTTP/1.1 200 OK`, `Content-Length: 27`, the whole
`Download_Payload` and no `Content-Range`. Client side, call
`Transfers.Download_File (HTTP, Origin, "example-bucket",
"download-range-ignored", Range_Path, Identity, Timeout => 5.0,
Byte_Range_Header => "bytes=7-13")` inside a handler for
`Low_Level.Invalid_Response`. Expected: the exception is raised (destination
untouched, no temporary left) and its message names a full/whole
representation returned for a ranged request. Actual: the message is
"GetObject returned an unsolicited representation interval".

**Existing coverage:** `tests/src/s3_http_socket_corpus.adb:16935-16960`
(`download-unexpected-range`, scripted at 4885-4888) covers the first disjunct (206 without a
request `Range`) and asserts `Invalid_Response` plus destination
preservation; `:16961-16980` (`download-range`, scripted at 4889-4895) covers 206 with a `Range`.
No lane sends a `Range` and answers 200, so the misleading text is never
observed by the suite.

**Refutation attempts:** Checked whether `Decode_Get_Object_Response_Head`
already rejects a 200 in range mode with a better message: it does not know
the request carried a `Range` (`low_level.adb:5985-5987` only rejects a 200
that carries `Content-Range`). Checked whether the architecture doc
authorises accepting the 200 (it does not: "accepts only HTTP 206"), so the
refusal is correct and only the diagnostic is wrong. Checked
`Execute_Transfer` (`transfers.adb:710-716`) which forwards the message
verbatim into `Transfer_Result.Message`, so the wrong text is
caller-visible through both public entry points.

---

## Areas reviewed with no findings

- Multipart planning arithmetic (`s3-core.ads:104-124`, `Hash_File`
  727-858, `Upload_File` 1290-1302, `Upload_Multipart_File` 1076-1127):
  `1 + (Size - 1) / Part_Size` is an exact ceiling for `Size >= 1` with no
  addition overflow; non-final parts are always exactly `Part_Size`
  (>= 5 MiB by `Valid_Multipart_Part_Size`), the last part is `Part_Used > 0`
  so never empty, a file of `n x Part_Size` bytes yields exactly `n` parts,
  `10,000 x Part_Size + 1` and any plan over the 50,000 GiB bound are
  rejected by `Valid_Multipart_Plan` before any network I/O, and
  `Part_Digests.Length /= Multipart_Part_Count` catches the silent 10,000
  digest cap in `Hash_File`. Byte_Count accumulation is guarded at 759-763
  and File_Offset at 760; `Byte_Count'Min (Part_Size, Size - Offset)` and
  `Range_Source (File, Offset, Count)` (discriminant order confirmed in
  `request_bodies-files.ads`) delimit each part correctly.
- Structured task lifetime (`Transfer_Many` 1819-1977 with
  `Flyology.Task_Scopes`): every wave is a `Scope` whose `Join` closes
  admission and awaits all workers; `Finalize` cancels, joins and frees when
  `Join` was skipped (exception from `Configure`, `Spawn`, or caller abort);
  `Execute_Transfer` catches every exception so a worker never terminates the
  scope early; children receive the scope-owned token
  (`task_scopes.adb:Configure`, `Operation_Context`) so `Request_Cancellation`
  on failure cannot propagate to the parent token; the parent token is linked
  downward by `Cancellation_Monitor`. No detached task outlives the call.
- In-flight bounds: worker count = min(objects, requests,
  `Maximum_In_Flight_Bytes / 64 KiB`) exactly as documented; each worker holds
  at most one 64 KiB buffer owned by this package (`Hash_Buffer_Size`,
  `Transfer_Buffer_Size`); parts within one subject are sequential.
- Result aggregation: per-subject results are stored by input index,
  `Cancel_Remaining` marks later waves cancelled, deadline expiry and
  pre-cancelled batches produce terminal results (all asserted by
  `s3_transfer_many_corpus.adb`).
- Multipart assembly: ETags appended in part-number order; per-part
  checksums verified against the UploadPart echo; composite =
  algorithm(concat(raw part digests)) with `-N` suffix (`Checksums.Composite`,
  `Encode_Object`); full-object CRC computed linearly over the file; final
  echo and optional `ChecksumType` verified before success; no part is ever
  replayed (`One_Shot_Range_Source` is non-rewindable and `Execute_Upload_Part`
  re-checks); `Abort_Best_Effort` runs on every failure after initiation with
  its own budget and swallows its own errors.
- Resume/reconciliation: not implemented in `Upload_File` and documented as
  caller-owned (`.ads` 1377-1384, architecture doc); the direct
  `Upload_Part`/`List_Parts_Page` primitives and their dispositions are the
  documented reconciliation path.
- Downloads: single-range only; `Content-Range` coherence (first <= last <
  total, length = Content-Length) is enforced in `Low_Level`; body byte count
  is compared with `Content-Length`; temp file + `rename(2)` publication;
  temp deleted on every failure path; `Files.Close` resets the descriptor to
  `Invalid_File` before raising, so the double-close I looked for cannot
  happen.
- Timeouts: `Deadline_For`/`Remaining` map a negative `Timeout` to no
  deadline; Flyology HTTP and `Files.Read_At` document negative as unlimited,
  so `Remaining`'s `-1.0` is consistent end to end.
- Composable operations (Create/UploadPart/Complete/Abort/ListParts/
  ListMultipartUploads/Copy/UploadPartCopy): restart owner check, prepared
  request cleared on every terminal path, response sink bounded by the XML
  document limit, saved-error re-raised only after `Consume`, UploadPart
  buffer token moved back before re-raising, `Finalize` releases the buffer
  if `Finish` is skipped. Normalizers match the certainty corpus in
  `transfers-testing.adb` and the qualification records.
- `S3.Multipart` codecs: `Parse_Query` rejects malformed escapes, oversize
  queries, duplicate and inconsistent selectors without unhandled exceptions;
  the three XML handlers bound depth, part count (10,000) and listed-part
  count (1,000), reject text outside fields and nested modeled fields, and
  every decoder maps `XML_Error` to `Malformed_Multipart`, which `Low_Level`
  maps to `Invalid_Response`/`Invalid_Request`.

## Observations not counted

- `docs/architecture/client-transfers.md` says the planner rejects plans
  above "the supported 50 TiB object bound"; `Core.Maximum_Object_Size` is
  `50_000 * GiB` = 48.83 TiB, which is exactly `10,000 x 5 GiB`. No object
  between 50,000 GiB and 50 TiB can satisfy the 10,000-part rule, so the
  rounding has no observable effect; documentation wording only.
- `Upload_Multipart_File` sends the composite CompleteMultipartUpload
  `x-amz-checksum-*` header without the `-N` suffix (`Complete_Parameters`,
  902-913) and expects the `-N` form back in the body. This matches the
  in-repo server (`s3_applications.adb:13081-13089` validates the header as a
  raw digest) and the scripted corpus (`High_Level_SHA256_Composite_Raw`).
  Whether AWS accepts a raw, a suffixed, or no header on completion for
  composite uploads cannot be settled from the pinned model; a MinIO run of
  `Upload_File` with `Kind => Composite` through `tests/scripts/test-*.sh`
  would show MinIO's acceptance (the implementation corpus only runs
  `Full_Object` CRC32 at `s3_implementation_corpus.adb:792-800`).
- `S3.Multipart.Validate` (complete request, 544-551) demands consecutive part
  numbers whenever any part carries a checksum, regardless of checksum type.
  The server policy distinguishes (`Checksum_Policy.Consecutive_Parts_Required`
  is `Composite` only) and AWS is believed to allow non-consecutive parts with
  FULL_OBJECT part checksums (from memory, unverified). `Upload_File` always
  numbers parts 1..N, so only a hand-built manifest through
  `Complete_Multipart_Upload` could hit the stricter client-side rule.
- `S3.Multipart.Validate` (ListParts result, 1635-1637) requires
  `IsTruncated = (NextPartNumberMarker > 0)`. MinIO emits `0` when not
  truncated; if AWS echoes the last part number on an untruncated page (not
  verifiable here; an AWS ListParts run would show it), every untruncated AWS
  page would be rejected as malformed. Recorded as a low-confidence interop
  question, not a finding.
- `Parse_Query` rejects `max-parts` > 1000 and `part-number-marker` > 10000
  as malformed (lines 135-158). Both are documented policy subtypes
  (`Core.Page_Size`, `Part_Marker_Value`); MinIO clamps over-large `max-parts`
  instead. Policy value, not counted.
- `Upload_File` hashes the entire file (up to the object bound) before
  `Valid_Multipart_Plan` can reject an over-10,000-part plan (1290-1302), and
  `Hash_File` silently stops appending digests at 10,000 (792-799, 815).
  Correct outcome, wasted I/O on a rejected plan only.
- `Upload_File`'s handler (1367-1371) calls `Files.Close` directly; if close
  itself fails the close error replaces the original exception (e.g. a
  cancellation becomes a device error in `Transfer_Result`). Downloads use the
  swallowing `Close_After_Failure`. Close on a read-only descriptor failing is
  not a reachable input in practice.
- After a successful CompleteMultipartUpload whose echoed checksum or type
  mismatches (1146-1155), `Initiated` is still True, so the `when others`
  handler issues an AbortMultipartUpload against an already-completed upload
  (expected `NoSuchUpload`, swallowed). Harmless; the object is published and
  the caller gets `Invalid_Response`, which the `.ads` classes as ambiguous.
- `Transfer_Many` allocates `Wave_Count` fresh worker tasks per wave and the
  next wave cannot start until the slowest subject of the current wave
  finishes; documented "bounded structured waves", performance only.
- `Abort_Best_Effort` uses `Token => null` and a 5 s budget, so a cancelled
  or timed-out multipart subject can hold its wave open up to 5 s past the
  batch deadline; documented as an "independent short cleanup budget".
