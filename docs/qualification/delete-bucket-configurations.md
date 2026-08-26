# Bodyless bucket-configuration DELETE client qualification

This record qualifies the strict bounded clients and corpora for thirteen
bodyless bucket-configuration DELETE operations. DeleteBucketLifecycle and
DeleteBucketReplication also have provider-owned composable operations and
typed synchronous waits that use their corresponding state machines. It does
not
manufacture backend or server coverage. `DeleteBucketPolicy` and
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

DeleteBucketLifecycle and DeleteBucketReplication additionally expose limited
constructors, same-name operation-last reusable initiation procedures, typed
`Finish`, and typed synchronous overloads in `Client.Buckets`.
`Client.Low_Level` exposes each exact prepared-operation initiator used by its
parent. Each parent owns a known-empty nonrewindable source and bounded error
response through terminal drain. Neither replays a mutation. A complete 204
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
operation and caller. It also gates DeleteBucketLifecycle and
DeleteBucketReplication typed synchronous calls, limited constructors,
operation-last restarts, exact prepared-operation rejection, typed 403
certainty, duplicate and empty physical response identifiers, and bounded
error bodies. The replication lane additionally changes caller-owned
parameters after initiation to prove that the operation retained no borrow.
The complete sequence runs once under a native task and once under a Flyology
lightweight task; the root gate repeats the whole socket corpus three times.
The existing shared DeleteBucketCors physical-response lane supplies empty,
malformed, and one-past bounded response faults against the same internal
decoder and executor machinery.

The machine ledger records `DeleteBucketPolicy` and
`DeletePublicAccessBlock` as `covered / covered / covered / covered` using
their independent backend and server evidence. The other eleven operations
remain `missing / covered / missing / covered`; the additional lifecycle and
replication composable clients do not change those ledger tuples. This client
corpus does not manufacture their backend persistence or server routes.

## Gate evidence

The final warning-strict root gate passed 41/41 AUnit tests, the 132-case files
crash matrix, 320 checksum oracle vectors, 210 chunk boundaries, the strict
server application corpus, and three repetitions of the deterministic family
corpus and native/lightweight socket and TLS corpora. The operation inventory
verifier reported thirteen operations, thirty request members, no modeled
success outputs, eight reciprocal vectors, and the exact lifecycle and
replication composable declarations. The 116-operation coverage verifier and
its negative oracle,
repository-integrity gate, Markdown-link gate, and generated API build also
passed. GNATdoc produced a 44,047-line log and 429 HTML files with both
composable APIs present. It reported no error diagnostic and no new related
warning; the generated model's pre-existing undocumented replication enum
literal warning remains visible.

The latest serialized proof campaign remains the 2026-08-26 936/936 result.
This slice changes only non-SPARK client, corpus, coverage, and documentation
units, not any of the nine `tools/prove.sh` manifest units, so a redundant
proof rerun was not performed.
