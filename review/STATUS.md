# Review working record (re-read after any context compaction)

Objective: complete correctness review of flyology-ada/flyology-object-storage at commit 5fe6e3e
(worktree above, branch claude/flyology-object-storage-review-b1846d), verify every finding with a
runnable reproduction, file confirmed findings as GitHub issues in the house style, and write the
Codex triage brief. Repeats the flyology-postgres procedure (issues #31-#93, 2026-09-05).

Completion criteria: (1) baselines recorded (done, review/baseline-notes.md); (2) fifteen discovery
reports review/discovery-<AREA>.md (Fable, batches of four); (3) fifteen verification reports
review/verification-<AREA>.md (Opus) with one repro per confirmed finding under tests/repros
(shell repros under tests/repros/shell); (4) FINDINGS.md at the worktree root; (5) issue bodies in
review/filing/<ID>.md validated by review/filing/file_issues.py --dry-run; (6) STOP and ask the user
before filing (show two sample bodies and totals; ask: file all or P0/P1 only; push branch with
harness or keep local; lane order); (7) file with --file then --resolve; write review/ISSUES.md and
a project memory note; (8) review/TRIAGE_FOR_CODEX.md; (9) final report.

Constraints: no tracked file modified; no commit or push unless asked; never bare git stash; alr is
serialized (harness run.sh lock; never run alr concurrently with test scripts); Fable discovery
agents at most four at once; Opus for verification and drafting; SendMessage to subagents is not
available, spawn fresh agents instead.

Area status (D = discovery, V = verification):
| Area | D | V | Notes |
|---|---|---|---|
| WIRE | done (1 P1, 1 P2) | done: WIRE-1 P1, WIRE-1b P2, WIRE-2 P2, WIRE-3 P2 (new), WIRE-4 P1 (new: CR in key reported as LF) | harness note: Signed_Request could not sign percent-escaped paths; Signing_Path parameter added afterwards |
| SIGV4 | done (2 P2) | done: SIGV4-1 P2, SIGV4-2 P1 (raised); probe program passes | |
| BACKEND-FILES | done (4 P1, 2 P2) | done: 6 CONFIRMED; -3 and -4 raised to P0 (SIGKILL reading a 3 MiB policy on a 2 MiB worker stack; annotation destroyed before a failed delete); -1, -2 P1; -5, -6 P2 | doc-drift observation: matrix says annotations 'server absent' but the server routes them |
| SERVER | done (1 P1, 1 P2) | done: SERVER-1 P0 (raised; aws-cli v2.36.34 stock delete-objects/put-bucket-versioning/tagging fail), SERVER-2 P1 (raised), SERVER-3 P2 (new, HEAD always x-amz-version-id: null), SERVER-4 P2 (new, relative Location), SERVER-5 P2 partial (STREAMING-UNSIGNED-PAYLOAD-TRAILER -> 400, documented limitation) | aws-cli v2 is installed on this host and usable for stock-client probes |
| BACKEND-MEMORY | done (2 P1, 1 P2; -3 overlaps SERVER-2) | done: -1 P1 (ListMultipartUploads pagination drops same-key uploads; DECISION which S3 rule wins), -2 P1 (same-key versioned copy rejected; MinIO accepts; contradicts matrix s3.md:61; same predicate in files and sqlite), -3 P2 = backend half of SERVER-2 (fold) | probe program passes |
| CHECKSUM | done (1 P2) | done: CHECKSUM-1 P2 (partially weakened: BadDigest not a modeled shape); CHECKSUM-2 P0 = duplicate of SERVER-1 from the boto3 side (fold into SERVER-1, keep repro_checksum_2 and the python probe as evidence); boto3 1.43.89 object-path checksums all pass; boto3 sends no object-level checksum on CompleteMultipartUpload | |
| TRANSFERS | done (1 P2) | done: TRANSFERS-1 P2 (one sub-claim refuted); MinIO probe passes (unsuffixed completion checksum accepted; ListParts strictness never bites; MinIO does not clamp max-parts) | |
| BACKEND-SQLITE | done (1 P0, 2 P1, 2 P2) | done: -1 P1 (raised; payload race, documented invariant sqlite-backend.md:20-23), -2 P1, -3 P0 (gate leaked forever; repro_sqlite_3 deterministic, repro_sqlite_3b caller-reachable), -4 P1, -5 P2 (doc, no program) | harness sqlite/tests/repros builds; config files landed under src/ |
| CLIENT-LOW | done (3 P1, 2 P2) | done: -1/-2/-3 P0 (raised), -4 P2, -5 P2, -6 P2 (new: CreateMultipartUpload executor has no operation guard), -7 P2 (new: Long_Long_Integer'Value accepts Ada literal forms for query integers); probe passes | seed CLIENT-LOW-1 = BASELINE-1: Head_Object_Response_Bound (low_level.adb:5641-5658) rejects 200 without x-amz-version-id after versionId=null (all three real servers fail the corpus; Flyology server passes only because s3_applications.adb:4192 always emits x-amz-version-id: null); classified (A) client defect in review/baseline-rustfs.md |
| CLIENT-OBJECTS | done (2 P1: the seeds) | done: -1 P0 (raised), -2 P0 (raised), -3 P2 (new: torrent rejection labelled No_Failure); probe passes | seed: same predicate in client-objects.adb:121-155 (Get/Head_Object_Response_Bound); Tagging_Version_ID (client-objects.adb:7177-7189) demands x-amz-version-id on PutObjectTagging 200 (deferred discovery from the RustFS investigation) |
| MODEL | done (0 findings) | done: no finding upheld; tests/repros/python/model_differential.py exit 0 (116 ops, 718 shapes, 1699 members, 279 enum values, 74 ordinals; 20/20 mutations caught) | |
| SERVER-EXE | done (1 P1, 3 P2) | done: -1 P1 (measured ~350x S3 latency during one login; 10 logins starve S3 10 s), -2 P2, -3 P2, -4 P2, -5 P2 (new: second server opens a live files root); server built (47 s) | |
| CLIENT-BUCKETS | done (2 P2) | done: -1 P1 (raised; MinIO and the crate's server answer 403, never the enumerated 401), -2 P2, -3 P2 DOCUMENTED LIMITATION with MinIO interop consequence (prefixed ListBuckets fails); probe passes | |
| S3-DOMAIN-A | done (3 P1, 2 P2) | done: -1 P1, -2 P0 (raised; v1 NextMarker without delimiter rejected; matrix claims six-server oracle), -3 P2, -4 P1 (AWS roots verified from the API Reference), -5 P0 (raised; mc version enable body rejected 400 MalformedXML), -6 P1 (new: max-keys > 1000 rejected; aws-cli fails), -7 P1 (new: Versions.Validate rejects every untruncated MinIO ?versions page) | |
| S3-DOMAIN-B | done (4 P1, 3 P2) | done: -1 P0 (raised; mc and s3cmd namespace-free Delete rejected), -2 P0 (raised; mc tag set rejected), -3 P1, -4 P1 (ASCII keys a9/a: suffice), -5 P2, -6 P2, -7 P2, -8 P2 (new: MaxParts echo bounded at 1000; MinIO answers 10000), -9 P2 (new: empty TagSet response rejected) | |
| BASELINE | n/a | done (review/baseline-rustfs.md) | BASELINE-1: client HeadObject post-check rejects every third-party server; BASELINE-2: CI s5cmd jobs cannot fail (repro tests/repros/shell/repro_baseline_2.sh, exit 1) |

Deferred discoveries: none yet.

Consolidation: an Opus agent is writing review/consolidation/<AREA>.md for WIRE, SIGV4, BACKEND-FILES,
SERVER, CHECKSUM, TRANSFERS, BACKEND-MEMORY and BASELINE (index rows, totals row, area section, two
appendix blocks). A second pass will cover the remaining areas; the assembler then builds FINDINGS.md
from review/FINDINGS_HEADER.md plus the consolidation files.

Session-limit interruption (2026-09-06 evening): nine agents died; relaunched SERVER-EXE (resume from 2 findings), CLIENT-BUCKETS, S3-DOMAIN-A, S3-DOMAIN-B (fresh), CLIENT-OBJECTS V (finish: programs exist), CLIENT-LOW V (fresh), MODEL V (finish script), consolidation (remaining six areas; WIRE and SIGV4 done).
Drafting: review/DRAFTING_PROMPT.md written; WIRE (5 bodies) and SIGV4 (2 bodies) drafting agents launched; file_issues.py has a provisional ORDER of 35 IDs (BASELINE added to INTERNAL_ID). Remaining drafting waits for each area's consolidation file.
Bodies drafted and validated: SIGV4-1, SIGV4-2. BACKEND-SQLITE consolidation done; its drafting launched.
Bodies drafted and validated: WIRE-1, WIRE-1b, WIRE-2, WIRE-3, WIRE-4. Assembler note: the WIRE drafter corrected spans against the worktree (Valid_Object_Key contract is flyology-object_storage.ads:667-670, not :672-675; the escaper chain is s3-xml.adb:228-248); FINDINGS.md must take the drafted bodies' file:line values where they differ from consolidation files.
Consolidation done for BACKEND-FILES, SERVER, CHECKSUM, TRANSFERS, BACKEND-MEMORY, BASELINE, BACKEND-SQLITE; CLIENT-OBJECTS in progress. Drafting launched: SERVER+CHECKSUM-1 (6 bodies, folds CHECKSUM-2 -> SERVER-1 and BACKEND-MEMORY-3 -> SERVER-2), BACKEND-FILES (6), BACKEND-MEMORY-1/-2 + TRANSFERS-1 + BASELINE-2 (4).
Assembler items from the consolidator: (1) BASELINE-2 severity P1 assigned by the consolidator (no verifier); confirm before filing. (2) Line-number conflicts resolved per area report: Selected_Object_Index memory.adb:318-331 (SERVER) vs :318-329 (BACKEND-MEMORY); PutBucketVersioning MD5 gate :10358-10369 (SERVER) vs :10352-10370 (CHECKSUM); Valid_Object_Key :479-489 vs :479-490; drafted bodies are authoritative once they exist. (3) SERVER-4 anchored at s3_applications.adb:13193-13197 and s3-multipart.adb:1125 by the consolidator. (4) SERVER-3 masking wording: only HeadObject (:16619-16622) emits x-amz-version-id: null unconditionally; GetObject :4189-4194 only when a version exists or was named. (5) Global totals exclude CHECKSUM-2 and BACKEND-MEMORY-3.
GitHub: no open issues or PRs on flyology-ada/flyology-object-storage (PRs #10-#12 merged); labels bug and documentation exist; new issues will number from #13.
CLIENT-OBJECTS consolidation done; drafting launched (3 bodies). Conflicts to reconcile: CLIENT-LOW-3 site span (12465-12475 vs 12463-12489); HEAD vs GET attribution of unconditional x-amz-version-id: null (see sed check in transcript).
Resolved by sed at 5fe6e3e: s3_applications.adb:16619-16622 is inside the `when Head_Object =>` branch (:16518) and emits x-amz-version-id unconditionally (null when no version); :4189-4194 is the GetObject whole-object path and emits null only when Object_Read_Request.Has_Version_ID. SERVER.md is right; the CLIENT-OBJECTS reports reversed it; FINDINGS.md and the CLIENT-OBJECTS-1 body must use the HEAD attribution.
Bodies drafted and validated: BACKEND-SQLITE-1..5 (5 files; -5 is bug,documentation). Drafters must elide scratch paths from output (they contain a forbidden word). Regression placement fact: the class-wide backend exercisers are private in tests/src/object_storage_test_cases.adb; Backends.Testing is an 18-line helper (TRIAGE_HEADER corrected).
Bodies drafted and validated: BACKEND-MEMORY-1, BACKEND-MEMORY-2, TRANSFERS-1, BASELINE-2 (19 total). Shared-suite fact: the four *_conformance.adb programs are the backend-neutral suites (TRIAGE_HEADER corrected again). test-flyology-server.sh has no --publish; the memory server binds loopback directly (s3_server_harness.adb:120-121).
Consolidation done: CLIENT-LOW (7), MODEL (0). CLIENT-LOW drafting launched (7 bodies). Span facts settled for the assembler: Response_Version_ID = low_level.adb:12465-12492; corpus HeadObject case = s3_implementation_corpus.adb:1144-1172; tagging socket case = :15091-15253.
Assembler: review/assemble_findings.py (tested; draft at review/FINDINGS.draft.md: 12 areas, 38 confirmed, 9/12/17). Final run: python3 review/assemble_findings.py -> FINDINGS.md after the four remaining consolidation files exist and review/ISSUE_PARAGRAPH.md is written.
Bodies drafted and validated: CLIENT-OBJECTS-1..3 (22 total). Running: drafting SERVER+CHECKSUM (6), BACKEND-FILES (6), CLIENT-LOW (7); verifiers CLIENT-BUCKETS, S3-DOMAIN-A, S3-DOMAIN-B, SERVER-EXE.
Bodies drafted and validated: SERVER-1..5, CHECKSUM-1 (folds done). Validator: 31 present, 7 missing (CLIENT-LOW). Corrected spans from the drafter: CHECKSUM-1 branch :14813-14821 (twin :15555-15562); DeleteObjects gate :17672-17684; PutBucketTagging :8012-8019; matrix row s3.md:70.
Bodies drafted and validated: BACKEND-FILES-1..6 (31 total; CLIENT-LOW drafting running). Span corrections: Write_Header in Complete_Multipart_Upload files.adb:11855; Annotations.Clear memory.adb:3346; orphan is unreachable for the life of the bucket (Delete_Bucket removes the tree, files.adb:3854-3855).
Consolidation done: CLIENT-BUCKETS (3). Drafting launched: CLIENT-BUCKETS (3 bodies). Running: CLIENT-LOW drafting, SERVER-EXE consolidation, S3-DOMAIN-A/B verifiers.
Consolidation done: SERVER-EXE (5). Drafting launched: SERVER-EXE (5). Running: CLIENT-LOW and CLIENT-BUCKETS drafting, S3-DOMAIN-A consolidation, S3-DOMAIN-B verifier.
Bodies drafted and validated: CLIENT-LOW-1..7 (38 total). All fifteen verifications complete. Sweep started (Ada harnesses, detached; logs under review/sweep/). Shell and python sweeps run last, after all drafters stop.
Brief: review/assemble_brief.py assembles TRIAGE_FOR_CODEX.md from TRIAGE_HEADER.md + TRIAGE_LAYERS.draft.md (renumbers entries). TODO before filing: reconcile 'item N' prose references with the renumbered list; ORDER = 62 IDs (CHECKSUM-2 and BACKEND-MEMORY-3 folded).
Consolidation done: S3-DOMAIN-A (7). Drafting launched: S3-DOMAIN-A (7). Running: CLIENT-BUCKETS and SERVER-EXE drafting, S3-DOMAIN-B consolidation, Ada sweep.
Consolidation complete for all 16 areas. Drafting launched: S3-DOMAIN-B (9). Running: CLIENT-BUCKETS, SERVER-EXE, S3-DOMAIN-A drafting; Ada/SQLite sweep.
Interim sweep: Ada 54/54 BUG REPRODUCED (fake helpers and _live holders excluded by the runner now), SQLite 5/5. Final clean sweep (Ada, SQLite, shell, python) to be re-run once the last drafters stop.
Bodies drafted and validated: CLIENT-BUCKETS-1..3 (41 total). Remaining drafting: SERVER-EXE (5), S3-DOMAIN-A (7), S3-DOMAIN-B (9).
Bodies drafted and validated: SERVER-EXE-1..5. Remaining: S3-DOMAIN-A (agent finishing), S3-DOMAIN-B (running).
Bodies drafted and validated: S3-DOMAIN-A-1..7 (58 total). Remaining: S3-DOMAIN-B-6..9 (drafter running). Next: clean sweeps (Ada, SQLite, shell, python) once the drafter stops, then final FINDINGS.md, then the filing question.
All 62 bodies validate (five titles shortened to the style target). Final clean sweep running detached (review/sweep/run-sweep.sh: Ada, SQLite, shell, python). Next: assemble FINDINGS.md with the sweep summary, then STOP and ask the user (file all or P0/P1; push branch or keep local; lane order).
FILED: 62 issues #13-#74 on 2026-09-07; --resolve patched 7 forward references and the brief; P0/P1/P2 labels created and applied to all 62. Branch kept local per the user. Lane order: wire+server, backends, client, codecs, CI.
