# Discovery agent brief (shared by every area)

You are performing a read-only correctness discovery review of one area of
the Ada 2022 crate `flyology_object_storage` (an S3 client and pluggable
object-storage server). The repository worktree is

    /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d

at commit 5fe6e3e (origin/main). Use absolute paths in every shell command;
the shell's working directory persists between calls and a bare `cd` into a
directory you are already in fails.

## Hard rules

- Read-only. Do not modify, create, or delete any tracked file. The only file
  you may write is your report, `review/discovery-<AREA>.md` (path given in
  your area section). Do not create any other file.
- Never run `alr`, `gprbuild`, `gnatprove`, `docker`, `make`, or any test
  script. Baseline builds are running and Alire's shared cache is not safe to
  use concurrently. You may run `rg`, `sed -n`, `wc`, `python3` (for reading
  JSON and for small arithmetic checks), and `git log -p`/`git blame` for
  history. Do not run `git stash` in any form.
- Do not read the 79,000-line generated file
  `src/flyology-object_storage-s3-model.adb` line by line. If your area needs
  a descriptor from it, `rg -n` for the specific shape or operation name and
  read that region only.
- Write your report incrementally: create the file as soon as you have your
  first finding (with a provisional header), append each further finding as
  you confirm it, and rewrite the header (scope, rubric, summary table) at
  the end. A crash must leave partial results on disk.
- Your final chat message must be a short summary only (counts by severity,
  one line per finding, and anything you could not review). Do not paste the
  report into the chat.

## What to look for

Correctness defects, in priority order: memory or aliasing unsafety; security
(signature verification bypass, path traversal or symlink escape, credential
or secret exposure, authorisation bypass, attacker-controlled parsing that
raises an unexpected exception or loops); data loss or durability violations;
hangs and deadlocks; interop-breaking protocol violations that a stock S3
client (aws-cli, boto3, s5cmd, MinIO client) or a stock server would reject;
wrong results or unexpected exceptions on valid input via a reachable path;
documented contracts (`.ads` GNATdoc comments, README, `docs/compatibility/s3.md`,
`docs/qualification/*.md`, `docs/architecture/*.md`) that the code violates;
edge-case incorrectness and wrong diagnostics.

Not defects: documented policy values (limits, defaults, capacities,
timeouts) unless they break a protocol rule or a documented invariant. List
those under "Observations not counted" with one line each. Style, naming and
formatting are out of scope entirely.

## Method

1. Read the `.ads` specifications of your area first; they are the contracts.
   Note every documented precondition, postcondition, exception, bound and
   ownership rule.
2. Read the bodies against those contracts. For every candidate, find the real
   callers (`rg -n 'Subprogram_Name'` across `src/`, `server/src/`,
   `sqlite/src/`, `tests/src/`) and confirm the defect is reachable through a
   public API, the memory backend, the S3 server application, or a stock S3
   client. A defect in a subprogram nothing calls is an observation, not a
   finding.
3. Try to refute each candidate yourself before recording it: look for a
   guard elsewhere, a precondition that excludes the input, a caller that
   never passes it, or a test that already exercises it. Record the refutation
   attempts you made.
4. Check existing coverage under `tests/src/` (AUnit suite
   `flyology_object_storage_tests.adb`, `object_storage_test_cases.adb`, the
   conformance and qualification programs, corpora under `tests/corpora/`),
   `sqlite/tests/src/` and `server/tests/scripts/` so the reproduction sketch
   states what the suite already asserts and whether a test asserts the wrong
   behaviour.
5. For claims about what AWS S3 does: the pinned botocore model is at
   `review/baseline/service-2.json` (source of truth for shapes, member
   locations, HTTP bindings, error shapes). Cite the AWS S3 API Reference or
   the SigV4 specification by document and section from your own knowledge
   only when the model cannot answer, and mark such a citation
   "(from memory, unverified)". Never state a live-service behaviour as fact
   without saying how it could be checked (a MinIO, RustFS or SeaweedFS run
   through `tests/scripts/test-*.sh`, or the model).
6. Prefer depth on the severe surfaces of your area over breadth on cosmetic
   ones. Ten well-evidenced findings beat thirty speculative ones. A finding
   with Confidence below Medium should usually be an observation instead.

## Severity rubric (use exactly)

- P0: memory or aliasing unsafety; security-relevant (signature verification
  bypass, path traversal or symlink escape, credential or secret exposure,
  authorisation bypass); data loss or durability violation (an acknowledged
  write that is not durable or is silently corrupted); hang or deadlock in
  normal operation; or an interop-breaking protocol violation that a stock
  client or server rejects.
- P1: wrong result or unexpected exception on valid input via a reachable
  path, or a documented contract violated (`.ads` comment, README,
  compatibility matrix, qualification document).
- P2: edge-case incorrectness, wrong diagnostics, or contract drift needing
  unusual input.

## Report format (`review/discovery-<AREA>.md`)

```
# Correctness discovery: <area title>

Scope: <the files reviewed with line ranges where partial; the reference
material consulted; the existing coverage inspected>

Severity rubric: <the three lines above, verbatim or condensed>

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| <AREA>-1 | ... | P1 | High |

---

### <AREA>-1: <title>

**Location:** `path:line-line` (one or more)

**Severity:** Px. **Confidence:** High | Medium | Low.

**Evidence:** the exact quoted lines in ```ada blocks (or ```c, ```python,
```sql), each preceded by its `path:line-line`; the contract being violated
quoted the same way; the model or document citation.

**Failure scenario:** a concrete sequence: what the caller or peer does, what
the code does at each cited line, what is observed.

**Reproduction test sketch:** concrete calls and inputs, the expected
(correct) result and the actual result, expressible through the public API,
the memory backend, or the S3 application over an in-process loopback server
(see `tests/src/s3_server_harness.adb` and `tests/src/s3_memory_server.adb`)
without external services where possible. Say when only a files-backend
directory, a SQLite root, or a Docker server can show it.

**Existing coverage:** which test touches this path and what it asserts; or
"none".

**Refutation attempts:** what you checked that could have made this a
non-issue, and why it did not.

---

## Areas reviewed with no findings

<one line per subprogram family or file region reviewed and found sound>

## Observations not counted

<policy values, unreachable code, documentation-only remarks, low-confidence
candidates; one or two lines each>
```

Number findings `<AREA>-1`, `<AREA>-2`, ... in the order you confirm them.
