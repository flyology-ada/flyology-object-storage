# BASELINE consolidation block

## Index rows

| BASELINE-2 | P1 | The two s5cmd-driven CI jobs cannot fail: the piped step's status is `tee`'s, and the endpoint is unreachable from the s5cmd container on Linux | `.github/workflows/ci.yml:271-272` | `tests/repros/shell/repro_baseline_2.sh` |

## Totals row

| BASELINE | 0 | 1 | 0 | 1 | BASELINE-1 was reclassified as a client defect and is filed as CLIENT-LOW-1; it is not listed here |

## Area section

## BASELINE: maintained gates and the CI evidence behind them (BASELINE-2)

The area covers the gate run recorded in `review/baseline-notes.md` and its logs under `review/baseline/`, with `.github/workflows/ci.yml`, `tests/scripts/test-flyology-server.sh`, `tests/scripts/run-s3-server-slice.sh` and the three reference scripts `tests/scripts/test-{minio,rustfs,seaweedfs}.sh` read as the implementation, and the scheduled-run logs `review/baseline/ci-blackbox-job.log` and `review/baseline/ci-rustfs-job.log` as the evidence.

### BASELINE-2: The two s5cmd-driven CI jobs report success while executing nothing

**Severity:** P1. No verification report covers this area, so this is the drafter's assignment under the header rubric: the jobs are the repository's own interop gate, they report success on runs in which the conformance script demonstrably failed, and a maintainer reading a green scheduled run is told something untrue about a reachable, deterministic path. The assembler should confirm the severity before filing.

**Location:** `.github/workflows/ci.yml:271-272` (`./tests/scripts/test-flyology-server.sh memory 2>&1 | tee obj/ci/s3-smoke.log`, the "Run digest-pinned s5cmd oracle against memory backend" step declared at `:268`) and `:304-305` (`./tests/scripts/test-${{ matrix.reference }}.sh 2>&1 | tee obj/ci/reference-${{ matrix.reference }}.log`, the "Run bounded permissive-reference slice" step declared at `:299`, matrixed over `rustfs` and `seaweedfs`); the whole file contains no `shell:` key and no `set -o pipefail`, so both steps run under GitHub's default `bash -e {0}`; the container-side endpoint at `tests/scripts/test-flyology-server.sh:95` (`http://host.docker.internal:$PORT`) and the s5cmd invocation at `tests/scripts/run-s3-server-slice.sh:60`; the loopback publications at `tests/scripts/test-minio.sh:26`, `tests/scripts/test-rustfs.sh:29` and `tests/scripts/test-seaweedfs.sh:34` (`--publish "127.0.0.1::<port>"`) and the loopback bind of the Flyology test server at `tests/src/s3_server_harness.adb:120-121` (`Sockets.Loopback_IPv4`); the failure the script itself does detect at `tests/scripts/test-flyology-server.sh:97-101`; evidence at `review/baseline/ci-blackbox-job.log:1611,1613` and `review/baseline/ci-rustfs-job.log:183`; recorded as note 3 of `review/baseline-notes.md`.

**Repro:** `tests/repros/shell/repro_baseline_2.sh`, exit status 1. It asserts the correct behaviour — a step written the way the workflow writes it must fail when the script fails — running the verbatim step shape under `bash -e` (fails the assertion), the same shape under `bash -eo pipefail` (control, passes), a demonstration of what `--publish 127.0.0.1::9000` binds to, and a grep showing `ci.yml` sets neither `shell: bash` nor `pipefail`.

**What is wrong:** Two independent causes make three CI jobs incapable of failing. First, both steps pipe the conformance script into `tee` under the default `bash -e` shell with no `pipefail`, so the step's exit status is `tee`'s and a failing script never fails the job. Second, the servers are reachable only on the host loopback — the reference servers are published with `--publish 127.0.0.1::<port>` and the Flyology memory server binds loopback directly — while the s5cmd oracle runs in a sibling container reaching `host.docker.internal`, which on Linux resolves to the docker0 gateway 172.17.0.1 and cannot connect. The observable consequence is that in the scheduled run 34031107803 of 2026-09-06 the jobs "Reference smoke (rustfs)", "Reference smoke (seaweedfs)" and "S3 black-box smoke (memory + s5cmd)" all report success while their logs show `ERROR "mb s3://...": ... dial tcp 172.17.0.1:<port>: connect: connection refused` followed by "Flyology memory endpoint runner failed" and nothing further. Everyone who reads a green scheduled run is affected: the s5cmd byte and deletion oracles that the repository relies on as its stock-client evidence have never actually run in CI, so no interop regression on those routes can be caught there. It is fully deterministic on a Linux runner, and both causes are visible statically in the maintained workflow and scripts. On macOS Docker the second problem does not arise, which is why the same scripts run far enough locally to expose CLIENT-LOW-1.

**Notes:** BASELINE-1 — the client's HeadObject post-check rejecting every third-party server — was reclassified as a client defect during the RustFS investigation (`review/baseline-rustfs.md`) and is filed as CLIENT-LOW-1, with the same predicate in the objects layer as CLIENT-OBJECTS-1; it is not listed under BASELINE. The two causes here are independent and should be fixed together: adding `shell: bash` (or `set -o pipefail`) to the two steps alone would turn the jobs red without making them meaningful, because the endpoint would still be unreachable, so a maintainer has to decide both how the step status is propagated and how the s5cmd container reaches the server on Linux (publishing on `0.0.0.0` and passing the runner's docker0 address, running s5cmd on the host network, or putting server and client on the same user-defined network). The local gate run recorded in `review/baseline-notes.md` shows what the CI jobs would have reported had they run: the three Flyology backends pass the full corpus, s5cmd byte and deletion oracles and restart routing, while all three third-party servers fail at the same exchange for the reason CLIENT-LOW-1 describes. Note 1 of the same record is not a defect: the first `tests/scripts/test.sh` run failed only because `FLYOLOGY_S3_SERVICE_MODEL` was unset locally, and CI sets it at `.github/workflows/ci.yml:118`.

---

## Coverage evidence: BASELINE

- Every maintained gate was run before review work started and passes: root build (`alr -n build`, 55 s, no warnings), root test suite with `FLYOLOGY_S3_SERVICE_MODEL` set as CI does (8 min 16 s), SQLite tests (1 min 43 s), the GNATprove gate (`tools/prove.sh`, nine forced units, level 0, warnings as errors, 999 of 999 checks proved), the repository integrity check (4 min 19 s) and the botocore model verifier (hash, 116 operations and generated schema match).
- The Flyology backends pass their black-box lane: `tests/scripts/test-flyology-server.sh memory`, `files` and `sqlite` all pass (47 s, 48 s, 57 s) over the full corpus, the s5cmd byte and deletion oracles and restart routing.
- The three third-party servers fail identically and before any oracle-mode branching, at the corpus's third HeadObject case, with `INVALID_RESPONSE : HeadObject response does not match prepared request`; the cause is the client-side predicate filed as CLIENT-LOW-1, not a gate defect.
- Logs for every gate above are retained under `review/baseline/`; the two CI job logs cited by BASELINE-2 are `ci-blackbox-job.log` and `ci-rustfs-job.log`.

## Observations not counted: BASELINE

- The first `tests/scripts/test.sh` run failed at the GetObjectAnnotation model verifier only because `FLYOLOGY_S3_SERVICE_MODEL` was unset in the local shell; CI sets it at `.github/workflows/ci.yml:118` and the rerun passes, so this is an environment prerequisite rather than a repository defect.
- The Docker conformance matrix and the individual MinIO and SeaweedFS scripts fail locally at the same exchange as RustFS; that failure is CLIENT-LOW-1 and is not counted again here.
- The scheduled-run logs also carry a GitHub deprecation warning about Node.js 20 actions being forced onto Node.js 24; unrelated to the gate's evidential value.
