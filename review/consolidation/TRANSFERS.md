# TRANSFERS consolidation block

## Index rows

| TRANSFERS-1 | P2 | `Download_File` misdiagnoses a 200 answer to a `Range` request as an "unsolicited representation interval" | `src/flyology-object_storage-client-transfers.adb:1711-1716` | `repro_transfers_1` |

## Totals row

| TRANSFERS | 0 | 0 | 1 | 1 | TRANSFERS-1 confirmed with one sub-claim refuted (the wrong text is not reachable from `Transfer_Many`) |

## Area section

## TRANSFERS: multi-subject transfer client and multipart planning and codecs (TRANSFERS-1)

The area covers `src/flyology-object_storage-client-transfers.ad?`, `src/flyology-object_storage-s3-multipart.ad?`, `docs/architecture/client-transfers.md`, `tests/src/flyology-object_storage-client-transfers-testing.ad?` and `tests/src/s3_transfer_many_corpus.adb`, with `src/flyology-object_storage-client-low_level.adb`'s GetObject head validation, the loopback server and download lanes of `tests/src/s3_http_socket_corpus.adb`, `tests/scripts/test-minio.sh` and the pinned botocore model read as the reference.

### TRANSFERS-1: `Download_File` misdiagnoses a 200 answer to a `Range` request as an "unsolicited representation interval"

**Severity:** P2 (the discovery report also said P2). The refusal itself is documented policy and only the operator-facing text is wrong, which is the rubric's "wrong diagnostics" band; it is not P1, because no valid input produces a wrong result and the documented contract that a successful 206 atomically publishes the selected interval is honoured.

**Location:** `src/flyology-object_storage-client-transfers.adb:1711-1716`, one `elsif` covering both `(Byte_Range_Header'Length = 0 and then Head.Status /= 200)` and `(Byte_Range_Header'Length > 0 and then Head.Status /= 206)` and raising `Low_Level.Invalid_Response with "GetObject returned an unsolicited representation interval"` for both — the literal appears at exactly one site in the repository; the head validator that cannot produce a better message at `src/flyology-object_storage-client-low_level.adb:5981-5987`; the contract at `src/flyology-object_storage-client-transfers.ads:1688-1689` and the public parameter with its empty default at `:1710`; the `Transfer_Many` call site at `src/flyology-object_storage-client-transfers.adb:663-669` and the message capture at `:710-716`; `Subject` at `src/flyology-object_storage-client-transfers.ads:1731-1737`; existing lanes at `tests/src/s3_http_socket_corpus.adb:16935-16957` and `:16959-16978`, with the ranged request at `:16965`.

**Repro:** `tests/repros/src/repro_transfers_1.adb`, exit status 1, two failed expectations; a loopback HTTP/1.1 server answers two GETs with 200 and the whole 27-byte body regardless of any `Range`, and a third with an unsolicited 206, and the program shows both events producing byte-identical messages.

**What is wrong:** `Download_File` uses one status gate for two opposite protocol events. When the caller passed no `Range` and the server answered 206, "GetObject returned an unsolicited representation interval" is exactly right; when the caller did pass a `Range` and the server answered 200 with the whole representation and no `Content-Range`, the same text is emitted and it is false in every particular — no interval was returned and nothing was unsolicited. RFC 9110 section 14.2 permits a server to ignore `Range` (recorded by the verifier as from memory and unverified), and a `Range`-stripping proxy or a cache produces exactly this answer in practice, so it is a legitimate server behaviour rather than a protocol violation. The consequence is diagnostic only: the destination file is left untouched, no temporary is left behind, and the refusal matches the documented range-mode contract. It is fully deterministic, being a pure function of `Byte_Range_Header'Length` and `Head.Status`.

**Notes:** One sub-claim of the discovery entry is refuted. It said the wrong text also lands in `Transfer_Result.Message` for a subject in `Transfer_Many`; it does not, because `Execute_Transfer` calls `Download_File` with an argument list ending at `Token` and `Subject` has no range field, so `Transfer_Many` can never pass a non-empty `Byte_Range_Header` and only the accurate first disjunct is reachable from it. The misleading text is reachable only through the direct `Download_File` entry point, which is public and is exercised by the maintained suite. No maintained lane sends a `Range` and answers 200, so the suite never observes the text, and no existing test asserts the wording. The fix needs no new public constant or parameter: split the `elsif` into two branches with two messages, keeping the existing text for the unrequested-206 case.

---

## Coverage evidence: TRANSFERS

- Multipart planning arithmetic: `1 + (Size - 1) / Part_Size` is an exact ceiling with no addition overflow, non-final parts are always exactly `Part_Size`, the last part is never empty, `n x Part_Size` yields exactly `n` parts, and plans above 10,000 parts or the 50,000 GiB bound are rejected before any network I/O; `Byte_Count` and `File_Offset` accumulation are guarded and each part's range source is delimited correctly.
- Structured task lifetime: every `Transfer_Many` wave is a `Task_Scopes.Scope` whose `Join` closes admission and awaits all workers, `Finalize` cancels and joins when `Join` was skipped, `Execute_Transfer` catches every exception so a worker never terminates the scope early, and children receive the scope-owned token — no detached task outlives the call.
- In-flight bounds: worker count is min(objects, requests, `Maximum_In_Flight_Bytes / 64 KiB`) as documented, each worker holds at most one 64 KiB buffer owned by this package, and parts within one subject are sequential.
- Result aggregation: per-subject results are stored by input index, `Cancel_Remaining` marks later waves cancelled, and deadline expiry and pre-cancelled batches produce terminal results, all asserted by `tests/src/s3_transfer_many_corpus.adb`.
- Multipart assembly: ETags appended in part-number order, per-part checksums verified against the UploadPart echo, composite and full-object values computed as specified, the final echo and optional `ChecksumType` verified before success, no part ever replayed (`One_Shot_Range_Source` is non-rewindable), and `Abort_Best_Effort` run on every failure after initiation with its own budget.
- Downloads: single range only, `Content-Range` coherence enforced in `Low_Level`, the body byte count compared with `Content-Length`, temp-file plus `rename(2)` publication, the temp deleted on every failure path, and `Files.Close` resetting the descriptor before raising so no double close is possible.
- `S3.Multipart` codecs: `Parse_Query` rejects malformed escapes, oversize queries and duplicate or inconsistent selectors without unhandled exceptions, and the three XML handlers bound depth, part count and listed-part count and map `XML_Error` to `Malformed_Multipart`.
- MinIO probe `tests/repros/src/repro_transfers_minio_probe.adb`, exit status 0 (PASS), against the digest pinned by `tests/scripts/test-minio.sh` (`RELEASE.2025-09-07T16-13-09Z`), started by hand so no repository test script ran: nothing the high-level client sends by default was rejected, so there is no TRANSFERS-2.
- That probe settles the `-N` suffix question for MinIO: the unsuffixed completion header `Upload_Multipart_File` sends is accepted for CRC32 and SHA256, MinIO echoes the `-N` form the client then requires, and a deliberately wrong bare digest is answered 400 `XAmzContentChecksumMismatch`, so the acceptance is real validation and not indifference.
- The probe also shows the client's `IsTruncated = (NextPartNumberMarker > 0)` strictness never bites on a real two-part upload (truncated, final and past-the-end pages all satisfy it), and that `max-parts` above 1000 is not expressible through the typed client at all.

## Observations not counted: TRANSFERS

- `docs/architecture/client-transfers.md` says the planner rejects plans above "the supported 50 TiB object bound" while `Core.Maximum_Object_Size` is 50,000 GiB = 48.83 TiB, exactly `10,000 x 5 GiB`; no object in the gap can satisfy the 10,000-part rule, so the wording has no observable effect.
- `S3.Multipart.Validate` (complete request, `:544-551`) demands consecutive part numbers whenever any part carries a checksum, while the server policy requires that for composites only and AWS is believed to allow non-consecutive parts with full-object part checksums (from memory, unverified); `Upload_File` always numbers parts 1..N, so only a hand-built manifest reaches the stricter client rule.
- `S3.Multipart.Validate` (ListParts result, `:1635-1637`) requires `IsTruncated = (NextPartNumberMarker > 0)`; whether AWS echoes the last part number on an untruncated page is unverified, and the pinned model's prose covers only the truncated case.
- One correction to the discovery observation on `max-parts`: the pinned MinIO release does **not** clamp an over-large value, it echoes `<MaxParts>2000</MaxParts>` verbatim; the client cannot emit such a request at all, since `Max_Parts` is typed `Core.Page_Size` (0 .. 1,000), so the rejection at `s3-multipart.adb:145-158` is this repository's *server*-side rule.
- Whether AWS accepts a raw, a suffixed, or no completion checksum header for composite uploads is still unsettled: the pinned model documents the request member as "the Base64 encoded, N-bit checksum of the object" with no suffix while warning that the output member may be a calculation over the parts, which is suggestive but not decisive, and MinIO's acceptance does not prove AWS's.
- `Upload_File` hashes the entire file before `Valid_Multipart_Plan` can reject an over-10,000-part plan, and `Hash_File` silently stops appending digests at 10,000; the outcome is correct, with wasted I/O on a rejected plan only.
- `Upload_File`'s handler calls `Files.Close` directly, so a failing close would replace the original exception, where downloads use the swallowing `Close_After_Failure`; a close failing on a read-only descriptor is not a reachable input in practice.
- After a successful completion whose echoed checksum or type mismatches, `Initiated` is still True, so the handler issues an `AbortMultipartUpload` against an already-completed upload; the expected `NoSuchUpload` is swallowed and the caller gets the `Invalid_Response` the `.ads` classes as ambiguous.
- `Transfer_Many` allocates fresh worker tasks per wave and the next wave cannot start until the slowest subject of the current one finishes; documented as bounded structured waves, performance only.
- `Abort_Best_Effort` uses a null token and a 5 s budget, so a cancelled or timed-out multipart subject can hold its wave open up to 5 s past the batch deadline; documented as an independent short cleanup budget.
- Resume and reconciliation are not implemented in `Upload_File` and are documented as caller-owned, with the direct `Upload_Part` and `List_Parts_Page` primitives as the documented path.
