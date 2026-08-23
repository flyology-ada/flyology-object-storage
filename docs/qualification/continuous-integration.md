# Continuous integration qualification

The repository CI separates fast deterministic checks from networked S3
oracles. Pull requests and pushes to `main` run the complete root and SQLite
test scripts on Linux and macOS, generate the public GNATdoc API reference,
and run the SPARK manifest through `tools/prove.sh`. The proof job has a
repository-wide concurrency lock so two workflow runs never share the proof
lane logically, even though GitHub gives them separate runners.

Repository integrity is checked before the build jobs. That gate requires all
five Alire roots to use the exact provisional Flyology HTTP PR #33 commit and
matching QUIC subcrate without any local HTTP path pin. It also requires
immutable full-commit GitHub Action references, executable and syntax-clean
scripts, clean changed lines, no merge-conflict markers, valid local Markdown
links, the exact 116-operation coverage ledger, its negative anti-promotion
oracle, reviewed corpus locks, and generated S3 model sources matching the
hash-pinned botocore model. A second negative oracle mutates the workflow to
use a floating Action, an incorrect proof tool, an incorrect documentation
tool, and persisted checkout credentials; all four unsafe fixtures must be
rejected.

Every pull request and push also runs the digest-pinned, MIT-licensed s5cmd
black-box corpus against the memory server. A scheduled lane runs a bounded
copy of the same wire slice against the digest-pinned Apache-2.0 RustFS and
SeaweedFS references. MinIO remains in the explicit full qualification matrix
but is not a primary CI reference because its server license is AGPL-3.0-only.
The full six-server, repeated matrix remains a deliberate qualification run:

```sh
./tests/scripts/test-s3-matrix.sh
```

The ordinary CI-equivalent local gates are:

```sh
./tools/ci/check-repository.sh /path/to/pinned/service-2.json
./tools/ci/run-tests.sh
./tools/prove.sh
./tools/build-api-docs.sh
./tests/scripts/test-flyology-server.sh memory
```

CI installs Alire 2.1.1, GNAT 16.1.0, and GPRbuild 26.0.1. GNATdoc is pinned
to 26.0.0. GitHub Actions and Docker images use immutable digests or full
commit hashes. Workflow permissions are read-only, checkout credentials are
not persisted, networked steps and jobs have explicit time bounds, and no
repository secret is exposed to pull-request code.

Test, proof, documentation, integrity, and oracle logs are retained as
workflow artifacts. Artifact retention is 14 days except for proof evidence,
which is retained for 30 days.
