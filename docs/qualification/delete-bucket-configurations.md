# Bodyless bucket-configuration DELETE client qualification

This record qualifies the strict bounded synchronous clients and corpora for
thirteen bodyless bucket-configuration DELETE operations. It does not claim
configuration persistence in any Flyology backend, an authenticated Flyology
server route, or external-provider interoperability.

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

## Synchronous API and response contract

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

## Corpus and coverage boundary

The deterministic corpus enumerates all thirteen path and virtual-hosted
targets, owner presence and omission, every required-identifier operation,
canonical escaping and ordering, exact and one-past whole-target boundaries,
control-bearing and overlong inputs, exact 204 semantics, structured errors,
malformed errors, and cross-operation executor rejection before HTTP.

The raw-loopback corpus adds one signed high-level 204 exchange for every
operation and caller. The complete sequence runs once under a native task and
once under a Flyology lightweight task; the root gate repeats the whole socket
corpus three times. The existing shared DeleteBucketCors physical-response
lane supplies duplicate, empty, malformed, and one-past bounded response
faults against the same internal decoder and executor machinery.

The machine ledger records each operation as `missing / covered / missing /
covered`. Client and corpus evidence do not manufacture backend persistence or
a server route. Promoting either remaining cell requires independent storage,
reopen/crash/concurrency, authenticated routing, and black-box tests.

## Gate evidence

The final warning-strict root gate passed 38/38 AUnit tests, the 88-case files
crash matrix, 320 checksum oracle vectors, 210 chunk boundaries, the strict
server application corpus, and three repetitions of the deterministic family
corpus and native/lightweight socket and TLS corpora. The SQLite wrapper,
catalog, backend, reopen, and upgrade gate passed separately. The operation
inventory verifier reported thirteen operations, thirty request members, no
modeled success outputs, and eight reciprocal vectors; the 116-operation
coverage verifier and its negative oracle also passed.

The latest serialized proof campaign remains the 2026-08-23 936/936 result.
This slice changes only non-SPARK client, corpus, coverage, and documentation
units, not any of the nine `tools/prove.sh` manifest units, so a redundant
proof rerun was not performed.
