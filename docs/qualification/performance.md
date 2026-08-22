# Server performance qualification

Performance qualification compares Flyology Object Storage with the pinned
RustFS and SeaweedFS oracle versions on the same dedicated host. MinIO remains
a compatibility runtime, not a performance target. A result is comparable
only when its machine, kernel, filesystem, compiler, container runtime, power
mode, server revision, client revision, and scenario-file digest are recorded.

The server matrix will run every scenario in
[`benchmarks/scenarios.tsv`](../../benchmarks/scenarios.tsv) against:

1. RustFS;
2. SeaweedFS;
3. the Flyology memory backend;
4. the Flyology files backend; and
5. the Flyology SQLite backend.

[`benchmarks/implementations.tsv`](../../benchmarks/implementations.tsv) is
the machine-checked comparison manifest. RustFS and SeaweedFS are the two
permissively licensed references. MinIO is deliberately excluded from the
performance target set: it remains useful compatibility evidence, but its
license and implementation lineage make it a poor optimization target for
this project.

Data-plane scenarios drive all endpoints through the same digest-pinned s5cmd
process for the cross-server comparison. ListMultipartUploads uses the shared
compiled Ada driver described below. A second lane uses the Flyology high-level
client to measure our complete client/runtime path. Every measured run has a
correctness preflight and postflight appropriate to its operation. The current
common slice checks s5cmd's exact success/error counts, heads the first and last
uploaded object, verifies their fixed-seed hashes, verifies every expected
download file exists plus endpoint hashes, and requires the first and last
deleted object to be absent. Exact remote object sets are mandatory before
and after namespace-list measurement. The v2 namespace oracle makes one
signed ListObjectsV2 request and requires the exact ordered unique key
sequence, matching `KeyCount`, the default `MaxKeys`,
`IsTruncated=false`, and no continuation token. The v1 scenario makes a
separate signed ListObjects request and requires the exact ordered unique key
sequence, default `MaxKeys`, `IsTruncated=false`, a v1 `Marker`, and no
`NextMarker`, `KeyCount`, or continuation-token elements. Neither oracle
counts s5cmd's human-readable `ls` lines: the
pinned client can receive a complete 64-key response while dropping lines in
its human-output path. The retained
[`20260822-listobjects-v2-p1-closure.tsv`](../../benchmarks/evidence/20260822-listobjects-v2-p1-closure.tsv)
records the instrumented publication/response/list ordering that classified
that client-output defect. The populated namespace is deleted after the
scenario. CopyObject is measured as server-side 64 MiB copies from
pre-populated immutable sources; the destination pair is re-read and checked
against the source payload hash after every measured repetition.
Namespace deletion is driven through s5cmd's batched DeleteObjects request,
not mislabeled as a series of independent DeleteObject requests.
ListMultipartUploads uses one shared Ada driver because s5cmd does not expose
that control-plane operation. The driver creates a deterministic active-upload
set, requires the full page and exact key order on every measured request, and
aborts every upload after measurement. The metric is upload entries decoded
per second; the full profile uses an exact 1,000-entry page.

`benchmarks/run-matrix.sh` automates the common endpoint lifecycle and drives
the two references plus all three Flyology backends sequentially. Its default
`smoke` profile uses reduced object counts and one aggregate repetition. A
`full` profile honors each scenario's warmup and duration, uses five
repetitions by default, and requires explicit `FLYOLOGY_BENCH_HOST_LABEL`,
`FLYOLOGY_BENCH_POWER_MODE`, and `FLYOLOGY_BENCH_CPU_POLICY` metadata. The
launcher refuses to compare Flyology until the indexed fixed-length HTTP
response dependency is consumed.

The current common eligibility manifest is
[`benchmarks/eligibility.tsv`](../../benchmarks/eligibility.tsv). Eleven
scenarios (small/medium PUT and GET,
forced 64 MiB multipart PUT, large GET, 64 MiB CopyObject, batched namespace
delete, v1 and v2 namespace list, and active multipart-upload list) are
executable. Mixed objects
is emitted as a blocked row until its workload generator and correctness
postflights exist; it is never silently omitted or timed as a failure.
[`benchmarks/exclusions.tsv`](../../benchmarks/exclusions.tsv) records the
narrow endpoint-specific exception: pinned SeaweedFS 4.43 is not measured for
ListMultipartUploads because its exact-page response has invalid truncation
markers and omits required initiation metadata. RustFS and all three Flyology
backends remain in that scenario, so the defect is visible rather than hidden
by weakening the response oracle.

Each campaign retains `samples.tsv`, digest-pinned s5cmd aggregate JSON logs
or the compiled multipart-list driver's checked-page records, machine
metadata, and `summary.tsv`. The summary reports median aggregate
operations/second and bytes/second plus same-campaign ratios to RustFS and
SeaweedFS. It deliberately contains no latency percentiles: s5cmd does not
emit one sample per request, so p50/p95/p99 remain reserved for the in-process
driver lane.

## Measurement protocol

- Use one isolated host and loopback networking; never compare across hosts.
- Run one server at a time with identical CPU affinity and resource limits.
- Use deterministic payloads generated from a recorded seed.
- Run the declared warmup, then five independent measured repetitions.
- The current aggregate s5cmd lane reports every repetition plus median
  requests/second and bytes/second. Dedicated-host qualification additionally
  requires CPU time, peak RSS, and disk bytes written; those resource samples
  remain a launcher gate rather than being inferred from throughput. The
  in-process lane additionally reports p50, p95, p99, and maximum per-request
  latency.
- Record cold-start and steady-state results separately. Do not combine them.
- Record failures, retries, throttling, and tail latency; throughput alone is
  not a passing result.
- Retain raw, machine-readable samples as CI artifacts. Summaries are derived
  from those samples and are never the sole evidence.
- For every Flyology series, report throughput ratios and inverse tail-latency
  ratios against RustFS and SeaweedFS from the same campaign. Never compare
  numbers collected on different machines or campaign runs.

The mixed scenario uses a fixed-seed distribution of 70% 4 KiB, 25% 1 MiB,
and 5% 64 MiB objects, with 60% GET, 25% PUT, 10% HEAD, and 5% DELETE after
its initial population phase.

## Backend semantics

Memory, files, and SQLite are separate result series. Memory is non-durable.
The files series uses its production-default `Power_Loss_Durable` policy;
`Process_Crash_Atomic` results require a distinct implementation label and
cannot be substituted for the production series. SQLite is measured with its
production `WAL` and `synchronous=FULL` settings; a weaker SQLite durability
mode cannot be used to claim parity. Results with different durability
semantics may guide tuning but must not be presented as equivalent.

## Regression policy

The first stable dedicated-host campaign establishes baselines; it does not
invent a threshold from a laptop run. After two repeatable campaigns, the
repository will pin per-scenario absolute budgets and oracle-relative floors
for each backend. The optimization objective is to close the gap to the best
permissive reference for that scenario, while preserving the backend's stated
durability semantics. CI fails when the five-run median violates a ratified
throughput floor, its p99 latency ceiling, or its oracle-relative floor, and
reruns once to distinguish a noisy host from a repeatable regression. Any
correctness, crash, leak, or data-integrity failure fails immediately
regardless of speed.

Runnable loopback endpoints now exist for memory, files, and SQLite, and the
black-box correctness preflight passes against all three. The aggregate s5cmd
launcher and raw result schema are executable. Percentile latency will not be
inferred from s5cmd's aggregate `--stat` output: an in-process driver must
record one sample per completed request before p50/p95/p99 claims are
accepted. Resource telemetry must also be added before the `full` profile is
used to ratify a performance threshold.

## Bucket-tagging lifecycle benchmark

`benchmarks/run-bucket-tagging-matrix.sh` measures one deliberately narrow
control-plane workload with a persistent Flyology HTTP client:
PutBucketTagging, an immediately validated GetBucketTagging snapshot,
DeleteBucketTagging, and a second Get that must return NoSuchTagSet. Values
alternate between lifecycles. Every timed lifecycle checks the typed outcomes
and exact state, so a stale Put, no-op Delete, rejected request, or incomplete
endpoint fails rather than producing a sample. The benchmark starts with
negative self-oracles for stale Put, no-op Delete, and a NoSuchTagSet body with
the wrong HTTP status. Successful lifecycle statuses are checked exactly. The same
driver runs against digest-pinned RustFS,
SeaweedFS, and supplemental MinIO plus Flyology memory, files, and SQLite.
RustFS and SeaweedFS remain the permissively licensed comparison baselines;
MinIO is reported only as supplemental compatibility evidence.

The smoke profile defaults to three repetitions of 64 sequential lifecycles
after eight warmups. The full profile defaults to seven repetitions of 2,000
lifecycles after 100 warmups and requires a clean revision plus host, power,
and CPU policy labels. Samples record monotonic elapsed time, lifecycle and
four-request rates, exact server revision, and the persistent-client/correctness
policy. This is a throughput regression tool for small control-plane requests;
it does not claim concurrent saturation, tail latency, or durability-equivalent
configuration between implementations.

The retained
[`20260822-bucket-tagging-smoke`](../../benchmarks/evidence/20260822-bucket-tagging-smoke/)
campaign records the clean `3f26be46851328bee394b2c39fde2105bb80e154`
source revision, all six roles, raw and normalized samples, exact tool and
container provenance, and artifact hashes. Run
`./tools/verify-bucket-tagging-benchmark-evidence.sh` to validate the bundle's
schema, rates, and raw-to-summary derivation. The malformed Alire provenance
field was the only post-campaign correction: `alr=APPLICATION` became the
same-host/tool `alr=alr 2.1.1`; measured rows and source revision were not
regenerated or altered. Its unqualified host, power, and CPU-policy labels keep
the rates explicitly outside release-threshold evidence.

## Checksum microbenchmark

Run 'benchmarks/run-checksums.sh [MiB-per-algorithm]' for a focused streaming
benchmark of all ten S3 algorithms. It feeds one deterministic 1 MiB buffer
repeatedly into a single context and reports TSV containing the algorithm,
total bytes, elapsed monotonic time, MiB/s, and final digest. The digest
prevents the measured work from becoming dead code. This benchmark is for
implementation regressions and algorithm selection; it does not replace the
end-to-end server matrix and does not set a release threshold from a developer
machine.

Run `benchmarks/run-multipart-checksums.sh [MiB-per-selection]` to measure the
actual memory-backend UploadPart path with explicit `No_Checksum` and retained
full-object CRC64NVME selections over identical generated bytes. This guards
the backend contract from hashing data for an explicit no-checksum selection;
AWS default selection is applied at the S3 boundary instead. The output is TSV
with selection, bytes, elapsed time, and MiB/s. It is a comparison signal, not
a portable pass/fail threshold.

An unqualified Apple arm64 development-profile smoke run on 2026-08-22 used
64 MiB per algorithm. It measured approximately 383 MiB/s CRC32, 389 MiB/s
CRC32C, 381 MiB/s CRC64NVME, 213 MiB/s SHA1, 143 MiB/s SHA256, 338 MiB/s
SHA512, 472 MiB/s MD5, 13.4 GiB/s XXHASH64, 9.0 GiB/s XXHASH3, and 14.4 GiB/s
XXHASH128. These numbers show no pathological scalar path in the initial
implementation; they are explicitly not a portable baseline or qualification
claim.

## Development smoke evidence

The retained `20260821Tmultipart-final` campaign is a correctness-checked,
unqualified-host smoke comparison of two concurrent 64 MiB multipart uploads.
It is tuning evidence, not a release baseline. Its same-campaign aggregate
results were 284 MB/s for memory (1.324x RustFS), 278 MB/s for files (1.293x),
231 MB/s for SQLite (1.075x), 215 MB/s for RustFS, and 105 MB/s for SeaweedFS.
The raw samples, summary, host metadata, scenario digests, and immutable
reference/client image digests are retained under
[`benchmarks/results/20260821Tmultipart-final`](../../benchmarks/results/20260821Tmultipart-final).

The retained `20260821Tcopy-reviewed` campaign applies the same caveat to two
concurrent 64 MiB server-side copies. It measured 371 MB/s for memory (0.792x
RustFS, 0.666x SeaweedFS), 444 MB/s for files (0.949x, 0.798x), and 474 MB/s
for SQLite (1.013x, 0.851x), versus 468 MB/s for RustFS and 557 MB/s for
SeaweedFS. Each series used pre-populated sources and verified destination
hashes after timing. The corrected provenance recorder stores exactly one
revision field per implementation and rejects newline or tab injection. Raw
evidence is retained under
[`benchmarks/results/20260821Tcopy-reviewed`](../../benchmarks/results/20260821Tcopy-reviewed).
