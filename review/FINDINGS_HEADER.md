# Flyology Object Storage correctness review — findings

Date: 2026-09-06

{{ISSUE_PARAGRAPH}}

## Scope and method

This document consolidates a correctness review of Flyology Object Storage, an
Ada 2022 S3 client and pluggable object-storage server, at commit `5fe6e3e`
(origin/main on 2026-09-06). The review covered the core crate under `src/`
(about 257,000 lines, of which 79,000 are the generated botocore descriptor),
the SQLite backend crate under `sqlite/`, the server executable under
`server/`, and the generator tooling under `tools/`. Fifteen per-area
discovery reviews produced candidate findings. Every candidate was then
verified adversarially by an independent agent, which re-derived each claim
from the source rather than from the discovery text. Where the claim depended
on S3 wire semantics, the verifier read the pinned botocore S3 model
(`service-2.json` at botocore commit `36c34f15`), the repository's own
compatibility matrix and qualification documents, and, for interop claims,
drove the pinned MinIO, RustFS and SeaweedFS images or a stock boto3 client
against the repository's own memory server. Only confirmed findings are listed
here. Each confirmed finding has a runnable reproduction program that asserts
the correct behaviour and fails on the current sources.

The severity rubric used throughout:

- **P0** — memory or aliasing unsafety; security-relevant (signature
  verification bypass, path traversal or symlink escape, credential or secret
  exposure, authorisation bypass); data loss or durability violation (an
  acknowledged write that is not durable or is silently corrupted); hang or
  deadlock in normal operation; or an interop-breaking protocol violation that
  a stock client or server rejects.
- **P1** — wrong result or unexpected exception on valid input via a reachable
  path, or a documented contract violated (`.ads` comment, README,
  compatibility matrix, qualification document).
- **P2** — edge-case incorrectness, wrong diagnostics, or contract drift
  needing unusual input.

Documented policy values (limits, defaults, capacities) were not counted as
bugs unless they break a protocol rule or a documented invariant; they are
listed under "Observations not counted" in each area section.

The severities in this document are the verifier's corrected ones. Where a
verifier raised, lowered or re-scoped a discovery severity, that is recorded in
the finding's Notes.

## Baselines

All maintained gates were run before review work started (details and logs in
`review/baseline-notes.md`): root build, root test suite (with
`FLYOLOGY_S3_SERVICE_MODEL` set as CI does), SQLite tests, the GNATprove gate
(999 of 999 checks proved), the repository integrity check, and the botocore
model verifier all pass. The Docker conformance scripts fail against all three
third-party servers at the same exchange; that failure is itself a finding
(CLIENT-LOW-1). The corpus passes against the three Flyology backends. The two
s5cmd-driven CI jobs cannot fail as written (BASELINE-2).

## How to reproduce

One reproduction harness was added, `tests/repros`, an Alire crate pinned to
the root crate. Each program asserts the correct behaviour, so on the current
sources it prints `BUG REPRODUCED` and exits 1. After a fix it prints `PASS`
and exits 0. A hang is reported as exit 124 by the harness `timeout` wrapper.
Exit 2 means a build failure.

| Harness | Run one program | Run all |
| --- | --- | --- |
| `tests/repros` (Ada programs) | `./run.sh repro_<id>` | `./run-all.sh` |
| `tests/repros/shell` (shell programs) | `./repro_<id>.sh` | (run each) |
| `tests/repros/python` (stock-client probes) | see each file's header | (run each) |

`run.sh` takes an optional second argument, a time limit in seconds (default
60), and serializes builds with a lock directory. Programs whose name ends in
`_probe` pass on the current sources and exist to show that a suspected defect
is absent; `run-all.sh` skips them. Programs that need a Docker server read the
endpoint from environment variables named in their header comment.

`src/repro_support.ad?` provides `Check`/`Note`/`Finish` and raw HTTP
response helpers. `src/repro_s3_server.ad?` provides an in-process S3
application over the memory backend with SigV4-signed raw requests, a
loopback listener, and direct access to the backend store.

The harness directory and the `review/` reports are untracked additions. No
library, test, or script was modified by the review.
