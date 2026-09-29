# Flyology Object Storage issue triage: {{ISSUE_RANGE}}

{{ISSUE_COUNT}} issues were filed on flyology-ada/flyology-object-storage from a crate-wide correctness
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

{{MODEL_FIRST_ITEMS}}

{{LAYERS}}

## Explicitly out of scope

{{OUT_OF_SCOPE}}
