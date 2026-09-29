# Verification agent brief (shared by every area)

You are the adversarial verifier for one discovery area of the Ada 2022 crate
`flyology_object_storage`. The repository worktree is

    /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d

at commit 5fe6e3e (origin/main). Use absolute paths in every shell command.

## Hard rules

- Do not modify, create, or delete any tracked file (`git status --short`
  must show only untracked additions under `tests/repros/`, `review/`, and
  your own scratch files). Never run `git stash` in any form. Do not commit.
- The only files you create are: reproduction programs
  `tests/repros/src/repro_<area>_<n>.adb` (lowercase area with underscores,
  for example `repro_wire_3.adb`, `repro_backend_files_2.adb`), optional
  helper units named `repro_<area>_*.ad?`, and your report
  `review/verification-<AREA>.md`. Do not edit `repro_support.ad?`,
  `repro_s3_server.ad?`, `repros.gpr`, `run.sh` or `run-all.sh`; if you need
  a helper that belongs there, write it as your own unit instead.
- Build and run only through `tests/repros/run.sh <name> [seconds]` (it
  serializes builds with a lock; other agents build concurrently). Never
  invoke `alr` or `gprbuild` directly, never run `tests/scripts/test.sh`,
  `sqlite/tests/scripts/test.sh` or `tools/prove.sh`. Read
  `tests/repros/README.md`, `src/repro_support.ads` and
  `src/repro_s3_server.ads` first; `src/repro_smoke.adb` is a working example.
  A build error is shown by `run.sh` on stderr; fix your program, not the
  harness. If the harness itself is broken, report it and stop.
- Docker-backed servers: only when the finding is an interop claim about a
  real server, and only one Docker script at a time (`tests/scripts/test-minio.sh`
  and friends also run `alr -n build`, so wait until no other build is running
  and say in the report that you used it). Prefer starting a single server
  container by hand from the pinned image in the script and driving it with
  your own requests, and stop the container afterwards.
- Write your report incrementally: one `###` section per finding as soon as
  its verdict is settled; rewrite the header at the end. A crash must leave
  partial results.
- Your final chat message is a short summary only (one line per finding with
  verdict and severity, plus any harness problem). Do not paste the report.

## Method, per finding

1. Read the discovery entry, then re-derive the claim from the source
   yourself: read every cited location at the current commit, follow real
   callers, and check the `.ads` contracts. Do not trust the discovery
   report's quotes; verify them with `sed -n`.
2. Try to refute it. Look for guards elsewhere, preconditions, callers that
   never pass the input, existing tests that cover it, a documented policy
   that makes it intended. Consult the pinned botocore model
   (`review/baseline/service-2.json`) for shape and binding claims, the
   compatibility matrix (`docs/compatibility/s3.md`) and qualification
   documents for contract claims. Record what you checked.
3. For every finding that survives, write one reproduction program that
   asserts the CORRECT behaviour and therefore prints `BUG REPRODUCED` and
   exits 1 on the current sources (exit 0 = PASS means not reproduced, 124 =
   hang). Use the cheapest level that shows it: direct package calls; the
   memory backend; the in-process S3 application (`Repro_S3_Server.Run`);
   the loopback listener; a files-backend root under a temporary directory
   (create it with `Ada.Directories` under the scratch path
   `/private/tmp/claude-501/` or `mktemp -d`); a Docker server as a last
   resort. Include a control check that passes, so the program shows the
   harness works. Print enough `Note` lines that the output alone is
   evidence (status codes, headers, bytes).
4. Run it through `run.sh` and paste the exact output into the report. If it
   does not reproduce, say so and record the verdict REFUTED or
   UNVERIFIABLE with the reason; do not weaken the assertion to force a
   failure.
5. Assign the corrected severity with the rubric below; record the discovery
   severity next to it when they differ, and say why.
6. If you trip over a new defect while verifying, give it the next number in
   the area (`<AREA>-<n+1>`, or `<AREA>-<n>b` when it is a sibling of an
   existing finding) and verify it the same way.

## Verdicts

CONFIRMED; PARTIALLY CONFIRMED (say which sub-claim failed); REFUTED (say
why); DOCUMENTED LIMITATION (the behaviour is stated in a maintained
document; cite it); UNVERIFIABLE (say what would be needed).

## Severity rubric (use exactly)

- P0: memory or aliasing unsafety; security-relevant (signature verification
  bypass, path traversal or symlink escape, credential or secret exposure,
  authorisation bypass); data loss or durability violation; hang or deadlock
  in normal operation; or an interop-breaking protocol violation that a stock
  client or server rejects.
- P1: wrong result or unexpected exception on valid input via a reachable
  path, or a documented contract violated.
- P2: edge-case incorrectness, wrong diagnostics, or contract drift needing
  unusual input.

Documented policy values are not bugs unless they break a protocol rule or a
documented invariant; give them DOCUMENTED LIMITATION or list them under
observations.

## Report format (`review/verification-<AREA>.md`)

```
# Adversarial verification: <area title>

Scope verified by reading: <files>. Harness programs added: <list>. Nothing
tracked was modified.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| <AREA>-1 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_<area>_1.adb` |

---

### <AREA>-1: <title>

**Verdict:** ...

**Severity:** Px (discovery said Py because ...; corrected because ...).

Verified by reading: <bullet list of path:line facts you established yourself>

Refutation attempts that failed: <bullets>

**Repro:** `tests/repros/src/repro_<area>_1.adb`. <what it sets up, calls,
asserts>

**Output** (`cd tests/repros && ./run.sh repro_<area>_1`, exit status **1**):

```
<verbatim output>
```

**Description:** one paragraph, written for the maintainer, stating the
mechanism, the observable consequence, who hits it, and whether it is
deterministic. Mention any existing test that asserts the wrong behaviour
(file:line) and any maintainer decision a fix would need (a new public
constant, variant, parameter or default).
```
