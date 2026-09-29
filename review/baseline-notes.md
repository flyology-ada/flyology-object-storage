# Baseline record (commit 5fe6e3e, 2026-09-06, macOS 26.6.2 arm64, GNAT 16.1.0 via Alire, APM 0.28.0, Alire 2.1.1, uv 0.11.28, Docker available)

Logs under `review/baseline/`.

| Gate | Command | Result | Log |
|---|---|---|---|
| Root build | `alr -n build` | PASS, 55 s, no warnings | `alr-build.log` |
| Root tests | `FLYOLOGY_S3_SERVICE_MODEL=review/baseline/service-2.json tests/scripts/test.sh` | PASS, 8 min 16 s | `tests.log` |
| SQLite tests | `sqlite/tests/scripts/test.sh` | PASS, 1 min 43 s | `sqlite-tests.log` |
| Proof gate | `tools/prove.sh` (GNATprove 16.1.0, nine forced units, level 0, warnings as errors) | PASS, 999/999 checks proved | `prove.log` |
| Repository integrity | `tools/ci/check-repository.sh review/baseline/service-2.json` | PASS, 4 min 19 s | `check-repository.log` |
| Botocore model | `tools/verify-botocore-model.sh` on the fetched pinned model (sha256 429763d6...) | PASS: hash, 116 operations, generated schema match | (inline) |
| Docker matrix | `FLYOLOGY_S3_MATRIX_REPEATS=1 tests/scripts/test-s3-matrix.sh` | FAIL on the first server (RustFS) | `s3-matrix.log` |
| MinIO | `tests/scripts/test-minio.sh` | FAIL, same exception | `minio.log` |
| SeaweedFS | `tests/scripts/test-seaweedfs.sh` | FAIL, same exception | `seaweedfs.log` |
| Flyology memory / files / sqlite | `tests/scripts/test-flyology-server.sh <backend>` | PASS, PASS, PASS (47 s, 48 s, 57 s; full corpus, s5cmd byte and deletion oracles, restart routing) | `flyology-*.log` |

Notes:

1. The first `tests/scripts/test.sh` run failed at the GetObjectAnnotation model verifier because `FLYOLOGY_S3_SERVICE_MODEL` was unset; CI sets it (`.github/workflows/ci.yml:118`). Not a repository defect; the rerun with the variable passes.
2. All three third-party servers (RustFS, MinIO, SeaweedFS, pinned images) fail `tests/bin/s3_implementation_corpus` at the same point, before any oracle-mode branching:
   `FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject response does not match prepared request`, raised by `Execute_Head_Object` (`src/flyology-object_storage-client-low_level.adb` ~5870) through `Head_Object_Response_Bound` (~5780), on the corpus's third HeadObject case (`tests/src/s3_implementation_corpus.adb:1144-1172`, `versionId=null` + `x-amz-request-payer: requester` + checksum mode). The check was introduced on 2026-08-30 (commit 2703ed6). Under investigation as BASELINE-1 (`review/baseline-rustfs.md`).
3. CI provides no evidence for either s5cmd-driven job. In the scheduled run 34031107803 of 2026-09-06, "Reference smoke (rustfs)", "Reference smoke (seaweedfs)" and "S3 black-box smoke (memory + s5cmd)" all report success, but their logs (`ci-rustfs-job.log`, `ci-blackbox-job.log`) show `ERROR "mb s3://...": ... dial tcp 172.17.0.1:<port>: connect: connection refused` followed by "Flyology memory endpoint runner failed", and nothing further. Two causes: (a) the workflow steps run `./tests/scripts/test-*.sh 2>&1 | tee obj/ci/*.log` under the default `bash -e` shell, where the pipeline's status is `tee`'s, so a failing script never fails the job (no `shell: bash` and no `set -o pipefail` anywhere in `ci.yml`); (b) the servers are published with `--publish 127.0.0.1::<port>`, bound to the host loopback, which the s5cmd container reaching `host.docker.internal` (172.17.0.1 on Linux) cannot connect to. On macOS Docker the second problem does not arise, which is why the corpus ran far enough locally to hit note 2. Recorded as BASELINE-2.
