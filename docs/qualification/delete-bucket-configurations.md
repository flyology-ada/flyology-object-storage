# Bodyless bucket-configuration DELETE client qualification

This record qualifies the strict bounded clients and corpora for thirteen
bodyless bucket-configuration DELETE operations. DeleteBucketLifecycle,
DeleteBucketReplication, DeleteBucketAnalyticsConfiguration,
DeleteBucketMetricsConfiguration, DeleteBucketIntelligentTieringConfiguration,
DeleteBucketMetadataConfiguration,
DeleteBucketMetadataTableConfiguration, DeleteBucketWebsite, and
DeleteBucketInventoryConfiguration also have
provider-owned composable operations and typed synchronous waits that use their
corresponding state machines. It does not manufacture backend or server
coverage. `DeleteBucketPolicy` and
`DeletePublicAccessBlock` now have that independent coverage in
[bucket-policy.md](bucket-policy.md) and
[public-access-block.md](public-access-block.md). No external-provider
interoperability is claimed here.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
It records thirteen exact DELETE operations, thirteen distinct request shapes,
thirty total request members, exact subresource URIs, exact 204 success codes,
and no modeled success output shapes. Analytics, intelligent-tiering,
inventory, and metrics shapes require `Bucket` and `Id`; the other nine
require only `Bucket`. Every shape also permits `ExpectedBucketOwner`.

`tests/corpora/delete-bucket-configurations/operations.tsv` records the exact
public preparer, executor, and convenience function for each operation.
`members.tsv` records every ordered member, wire location, and required flag.
`vectors.tsv` contains eight reciprocal family-wide request, response,
operation-binding, and transport contracts. The verifier checks the pinned
source, exact generated operation metadata, all member inventories, public API
presence, and both directions of every operation/vector reference:

```sh
python3 tools/verify-delete-bucket-configurations-preparation.py
```

## API and response contract

Each low-level preparer validates the bucket, required identifier when present,
and optional owner before transport; projects only its generated model shape;
signs an empty payload; and supports path and virtual-hosted addressing. The
query is canonicalized, so `Id` sorts before the intelligent-tiering,
inventory, and metrics flags and after the analytics flag. The target remains
subject to the shared 8,192-byte request-target bound, which can be narrower
than the scalar text bound once the bucket path and subresource are included.

Each exact executor checks both the private family kind and exact generated
operation before entering HTTP. This prevents an analytics request, for
example, from being executed through the encryption function even though the
operations share transport and response code. The shared decoder accepts only
an empty 204 response. Every other status requires a strict bounded S3 error;
physical request and host identifiers must each be absent or one bounded,
nonempty, control-free value.

The high-level `Client.Buckets` functions preserve those exact operation
bindings while returning the existing deletion-completed or structured-error
outcome. Calls are synchronous, do not retry, retain no caller input, release
the response before return, and create no detached helper task.

For `DeleteBucketEncryption`, the pinned operation resets bucket default
encryption to SSE-S3; it does not create an absent configuration state. Only
an exact empty 204 proves completion. Exact recognized rejections or definite
non-admission prove non-application, while possible admission, malformed or
oversized responses, and retryable responses preserve outcome-unknown. A
caller-selected `Get_Encryption` can observe current configuration before a
retry, but cannot prove that the lost deletion caused the observed state,
upgrade mutation certainty, or authorize automatic replay.

For `DeleteBucketLifecycle`, the pinned operation removes every rule from the
bucket lifecycle configuration. Only an exact empty 204 proves completion.
Exact recognized rejections or definite non-admission prove non-application,
while possible admission, malformed or oversized responses, and retryable
responses preserve outcome-unknown. A caller-selected
`Get_Lifecycle_Configuration` can observe current configuration or exact
`NoSuchLifecycleConfiguration` before a retry, but cannot prove that the lost
deletion caused the observation, upgrade mutation certainty, or authorize
automatic replay.

For `DeleteBucketReplication`, the pinned operation removes the bucket
replication configuration. Only an exact empty 204 proves completion. Exact
recognized rejections or definite non-admission prove non-application, while
possible admission, malformed or oversized responses, and retryable responses
preserve outcome-unknown. A caller-selected `Get_Replication_Configuration`
can observe current configuration or exact
`ReplicationConfigurationNotFoundError` before a retry, but cannot prove that
the lost deletion caused the observation, upgrade mutation certainty, or
authorize automatic replay.

For `DeleteBucketWebsite`, the pinned operation removes the bucket website
configuration. Only an exact empty 204 proves completion. Exact recognized
rejections or definite non-admission prove non-application, while possible
admission, malformed or oversized responses, and retryable responses preserve
outcome-unknown. A caller-selected `Get_Website` can observe current
configuration or exact `NoSuchWebsiteConfiguration` before a retry, but cannot
prove that the lost deletion caused the observation, upgrade mutation
certainty, or authorize automatic replay. Completion does not assert that a
website configuration was previously present.

For `DeleteBucketAnalyticsConfiguration`, the pinned operation removes the
selected analytics configuration. Only an exact empty 204 proves completion.
Exact recognized rejections or definite non-admission prove non-application,
while possible admission, malformed or oversized responses, and retryable
responses preserve outcome-unknown. A caller-selected
`Get_Analytics_Configuration` for the same identifier can observe current
configuration or exact `NoSuchConfiguration` before a retry, but cannot prove
that the lost deletion caused the observation, upgrade mutation certainty, or
authorize automatic replay. Completion does not assert prior presence.

For `DeleteBucketIntelligentTieringConfiguration`, the pinned operation
removes the selected intelligent-tiering configuration. Only an exact empty
204 proves completion. Exact recognized rejections or definite non-admission
prove non-application, while possible admission, malformed or oversized
responses, and retryable responses preserve outcome-unknown. A caller-selected
`Get_Intelligent_Tiering_Configuration` for the same identifier can observe
current configuration or exact `NoSuchConfiguration` before a retry, but
cannot prove that the lost deletion caused the observation, upgrade mutation
certainty, or authorize automatic replay. Completion does not assert prior
presence.

For `DeleteBucketInventoryConfiguration`, the pinned operation removes the
selected inventory configuration. Only an exact empty 204 proves completion.
Exact recognized rejections or definite non-admission prove non-application,
while possible admission, malformed or oversized responses, and retryable
responses preserve outcome-unknown. A caller-selected
`Get_Inventory_Configuration` for the same identifier can observe current
configuration or exact `NoSuchConfiguration` before a retry, but cannot prove
that the lost deletion caused the observation, upgrade mutation certainty, or
authorize automatic replay. Completion does not assert prior presence.

For `DeleteBucketMetadataConfiguration`, the pinned operation removes the
bucket metadata configuration. Only an exact empty 204 proves completion.
Exact recognized rejections or definite non-admission prove non-application,
while possible admission, malformed or oversized responses, and retryable
responses preserve outcome-unknown. A caller-selected
`Get_Metadata_Configuration` can observe the current modeled configuration
response or structured rejection before a retry, but cannot prove that the
lost deletion caused the observation, upgrade mutation certainty, or
authorize automatic replay. Completion does not assert prior presence.

For `DeleteBucketMetadataTableConfiguration`, the pinned operation removes
the bucket metadata-table configuration. Only an exact empty 204 proves
completion. Exact recognized rejections or definite non-admission prove
non-application, while possible admission, malformed or oversized responses,
and retryable responses preserve outcome-unknown. A caller-selected
`Get_Metadata_Table_Configuration` can observe the current modeled
configuration response or structured rejection before a retry, but cannot
prove that the lost deletion caused the observation, upgrade mutation
certainty, or authorize automatic replay. Completion does not assert prior
presence.

For `DeleteBucketMetricsConfiguration`, the pinned operation removes the
selected bucket metrics configuration. Only an exact empty 204 proves
completion. Exact recognized rejections or definite non-admission prove
non-application, while possible admission, malformed or oversized responses,
and retryable responses preserve outcome-unknown. A caller-selected
`Get_Metrics_Configuration` for the same identifier can observe the current
configuration or exact `NoSuchConfiguration` before a retry, but cannot prove
that the lost deletion caused the observation, upgrade mutation certainty, or
authorize automatic replay. Completion does not assert prior presence.

DeleteBucketLifecycle, DeleteBucketReplication,
DeleteBucketAnalyticsConfiguration, DeleteBucketMetricsConfiguration,
DeleteBucketIntelligentTieringConfiguration,
DeleteBucketMetadataConfiguration,
DeleteBucketMetadataTableConfiguration, DeleteBucketWebsite, and
DeleteBucketInventoryConfiguration
additionally expose limited constructors, same-name operation-last reusable
initiation procedures, typed `Finish`, and typed synchronous overloads in
`Client.Buckets`.
`Client.Low_Level` exposes each exact prepared-operation initiator used by its
parent. Each parent owns a known-empty nonrewindable source and bounded error
response through terminal drain. None replays a mutation. A complete 204
proves completion; exact conclusive service rejection proves non-application;
cancellation before admission is distinct; and any failure after possible
admission remains outcome-unknown for caller-selected read-only
reconciliation. Restart retains only the established HTTP client and
cancellation owner.

## Corpus and coverage boundary

The deterministic corpus enumerates all thirteen path and virtual-hosted
targets, owner presence and omission, every required-identifier operation,
canonical escaping and ordering, exact and one-past whole-target boundaries,
control-bearing and overlong inputs, exact 204 semantics, structured errors,
malformed errors, and cross-operation executor rejection before HTTP.

The raw-loopback corpus adds one signed high-level 204 exchange for every
operation and caller. It also gates DeleteBucketLifecycle,
DeleteBucketReplication, DeleteBucketAnalyticsConfiguration,
DeleteBucketMetricsConfiguration, DeleteBucketIntelligentTieringConfiguration,
DeleteBucketMetadataConfiguration,
DeleteBucketMetadataTableConfiguration, DeleteBucketWebsite, and
DeleteBucketInventoryConfiguration typed synchronous
calls, limited constructors, operation-last restarts, exact prepared-operation
rejection, typed 403 certainty, duplicate and empty physical response
identifiers, and bounded error bodies. The replication, analytics, metrics,
intelligent-tiering, metadata, metadata-table, website, and inventory lanes
additionally change caller-owned parameters after initiation to prove that the
operations retained no borrow.
The complete sequence runs once under a native task and once under a Flyology
lightweight task; the root gate repeats the whole socket corpus three times.
The existing shared DeleteBucketCors physical-response lane supplies empty,
malformed, and one-past bounded response faults against the same internal
decoder and executor machinery.

The machine ledger records `DeleteBucketPolicy` and
`DeletePublicAccessBlock` as `covered / covered / covered / covered` using
their independent backend and server evidence. The other eleven operations
remain `missing / covered / missing / covered`; the additional lifecycle,
replication, analytics, metrics, intelligent-tiering, metadata,
metadata-table, website, and inventory composable clients do not change those
ledger tuples.
This client corpus does not manufacture their backend persistence or server
routes.

`DeleteBucketEncryption`, `DeleteBucketLifecycle`,
`DeleteBucketReplication`, `DeleteBucketWebsite`,
`DeleteBucketAnalyticsConfiguration`,
`DeleteBucketIntelligentTieringConfiguration`,
`DeleteBucketInventoryConfiguration`, and
`DeleteBucketMetadataConfiguration`, and
`DeleteBucketMetadataTableConfiguration`, and
`DeleteBucketMetricsConfiguration`
have operation-specific reviewed registry lanes, but their ledger tuples remain
`missing / covered / missing / covered`. Each lane is conditional on every
maintained command succeeding and does not convert client evidence into
backend, server, directory-bucket, or external-provider qualification.

## Gate evidence

The final warning-strict root gate passed 41/41 AUnit tests, the 132-case files
crash matrix, 320 checksum oracle vectors, 210 chunk boundaries, the strict
server application corpus, and three repetitions of the deterministic family
corpus and native/lightweight socket and TLS corpora. The operation inventory
verifier reported thirteen operations, thirty request members, no modeled
success outputs, eight reciprocal vectors, and the exact lifecycle,
replication, analytics, metrics, intelligent-tiering, metadata,
metadata-table, website, and inventory composable declarations. The
116-operation coverage verifier and its negative oracle, repository-integrity
gate, Markdown-link gate, and generated API build
also passed. GNATdoc produced a 44,241-line log and 429 HTML files with all
nine composable APIs present. It reported no error diagnostic and no warning
naming the new public API; the generated model's pre-existing undocumented
operation-enum warnings remain visible.

The focused generated-model documentation slice has a green maintained full
test wrapper and fresh region-scoped GNATdoc measurement. That measurement
removed exactly the one candidate-owned
`Delete_Bucket_Encryption_Operation` warning and added none, without changing
any Ada declaration token. Repository-wide and selected-operation GNATdoc
qualification remain blocked by pre-existing warnings outside this declaration
region. Every command in the maintained `delete_bucket_encryption` lane must
still succeed before a qualification claim.

The subsequent focused generated-model documentation slice likewise has a
green maintained full test wrapper and fresh region-scoped GNATdoc
measurement. It removed exactly the one candidate-owned
`Delete_Bucket_Lifecycle_Operation` warning and added none, without changing
any Ada declaration token. Repository-wide and selected-operation GNATdoc
qualification remain blocked by pre-existing warnings outside this declaration
region. Every command in the maintained `delete_bucket_lifecycle` lane must
still succeed before a qualification claim.

The next focused generated-model documentation slice also has a green
maintained full test wrapper and fresh region-scoped GNATdoc measurement. It
removed exactly the one candidate-owned
`Delete_Bucket_Replication_Operation` warning and added none, without changing
any Ada declaration token. Repository-wide and selected-operation GNATdoc
qualification remain blocked by pre-existing warnings outside this declaration
region. Every command in the maintained `delete_bucket_replication` lane must
still succeed before a qualification claim.

The subsequent focused generated-model documentation slice also has a green
maintained full test wrapper and fresh region-scoped GNATdoc measurement. It
removed exactly the one candidate-owned `Delete_Bucket_Website_Operation`
warning and added none, without changing any Ada declaration token.
Repository-wide and selected-operation GNATdoc qualification remain blocked by
pre-existing warnings outside this declaration region. Every command in the
maintained `delete_bucket_website` lane must still succeed before a
qualification claim.

The analytics generated-model documentation slice also has a green maintained
full test wrapper and fresh region-scoped GNATdoc measurement. It removed
exactly the one candidate-owned
`Delete_Bucket_Analytics_Configuration_Operation` warning and added none,
without changing any Ada declaration token. Repository-wide and
selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_analytics` lane must still succeed before a qualification
claim.

The intelligent-tiering generated-model documentation slice also has a green
maintained full test wrapper and fresh region-scoped GNATdoc measurement. It
removed exactly the one candidate-owned
`Delete_Bucket_Intelligent_Tiering_Configuration_Operation` warning and added
none, without changing any Ada declaration token. Repository-wide and
selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_intelligent_tiering` lane must still succeed before a
qualification claim.

The inventory generated-model documentation slice also has a green maintained
full test wrapper and fresh region-scoped GNATdoc measurement. It removed
exactly the one candidate-owned
`Delete_Bucket_Inventory_Configuration_Operation` warning and added none,
without changing any Ada declaration token. Repository-wide and
selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_inventory` lane must still succeed before a qualification
claim.

The metadata generated-model documentation slice also has a green maintained
full test wrapper and fresh region-scoped GNATdoc measurement. It removed
exactly the one candidate-owned
`Delete_Bucket_Metadata_Configuration_Operation` warning and added none,
without changing any Ada declaration token. Repository-wide and
selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_metadata` lane must still succeed before a qualification claim.

The metadata-table generated-model documentation slice also has a green
maintained full test wrapper and fresh region-scoped GNATdoc measurement. It
removed exactly the one candidate-owned
`Delete_Bucket_Metadata_Table_Configuration_Operation` warning and added none,
without changing any Ada declaration token. Repository-wide and
selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_metadata_table` lane must still succeed before a qualification
claim.

The metrics generated-model documentation slice also has a green maintained
full test wrapper and fresh region-scoped GNATdoc measurement. It removed
exactly the one candidate-owned
`Delete_Bucket_Metrics_Configuration_Operation` warning and added none,
without changing any Ada declaration token. Repository-wide and
selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_metrics` lane must still succeed before a qualification claim.

The latest serialized proof campaign remains the 2026-08-26 936/936 result.
This slice changes only non-SPARK client, corpus, coverage, and documentation
units, not any of the nine `tools/prove.sh` manifest units, so a redundant
proof rerun was not performed.
