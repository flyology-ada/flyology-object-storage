# Scalar bucket-control PUT client qualification

This record qualifies strict bounded synchronous clients and corpora for
`PutBucketAbac`, `PutBucketAccelerateConfiguration`,
`PutBucketPolicy`, `PutBucketRequestPayment`, and `PutPublicAccessBlock`. It
does not manufacture backend or server coverage. `PutBucketPolicy` and
`PutPublicAccessBlock` now have that independent coverage in
[bucket-policy.md](bucket-policy.md) and
[public-access-block.md](public-access-block.md). No external-provider
interoperability is claimed here.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
It records five exact PUT operations, request shapes and subresource URIs, all
32 request and nested members, locations, required flags, member shapes, and
four relevant enum domains. The reciprocal verifier checks those inventories,
exact public preparer/executor/convenience bindings, and eleven model, request,
response, and transport vectors:

```sh
python3 tools/verify-put-bucket-controls-preparation.py
```

## Request and response contracts

Every preparer requires a valid bucket, supports path and virtual-hosted
addressing, preserves the optional expected-owner header, and signs the exact
payload. ABAC and acceleration preserve an absent optional status. Request
payment requires exactly `Requester` or `BucketOwner`. Public-access block
preserves presence independently for all four Booleans. Those four operations
serialize the modeled XML with the AWS S3 namespace and exact case-sensitive
spellings. Policy instead preserves arbitrary Ada `String` bytes without XML
interpretation, admits an exact caller-provided document-byte limit, and
preserves the optional self-access-removal confirmation Boolean.

ABAC, policy, request payment, and public-access block generate Content-MD5
when the caller omits the low-level override. Acceleration rejects a supplied
MD5 because its generated request shape has no such member. Every operation
admits the ten modeled checksum algorithms, computes the matching concrete
checksum over the same serialized or raw bytes, and signs both algorithm and
checksum headers. Unknown algorithms and malformed MD5 values fail before
HTTP.

Each exact executor checks the private family kind and exact generated
operation before entering HTTP. A 200 response may contain only an empty or
whitespace body. Non-200 responses require one strict bounded S3 error.
PutBucketAbac and PutBucketRequestPayment additionally have provider-owned
limited-constructor, operation-last restart, typed Finish, and typed
synchronous-wait forms. They own their serialized documents and expose them
through one non-rewindable source, preserve admission certainty, and require
read-only GetBucketAbac or GetBucketRequestPayment reconciliation after an
outcome-unknown result. Calls do not retry, retain no caller input, release
each response before return, and create no detached helper task.

## Corpus and coverage boundary

The deterministic corpus covers every enum value, optional-member presence,
all four public-access-block fields, exact XML, raw and binary-safe policy
bytes, exact and one-past policy limits, policy confirmation, required-payer
rejection, modeled MD5 presence and exclusion, all ten checksum algorithms,
unknown algorithm rejection, exact targets, cross-operation pre-admission
rejection, bodyless success, and structured/malformed errors. The raw-loopback
corpus performs all five high-level calls with body-hash, MD5/checksum, owner,
confirmation, and operation verification under native and Flyology lightweight
callers. The composable PutBucketAbac and PutBucketRequestPayment corpora also
cover construction, restart, exact prepared-operation rejection, physical
response header multiplicity, present-empty response identifiers,
caller-selected response limits, and certainty normalization.

The ledger records `PutBucketPolicy` and `PutPublicAccessBlock` as `covered /
covered / covered / covered` using their independent backend and server
evidence. The other three operations remain `missing / covered / missing /
covered`; this client corpus does not manufacture their backend persistence or
server routes.

## Gate evidence

The exact-tree warning-strict root gate passed 41/41 AUnit tests, the 132-case
files crash matrix, 320 checksum oracle vectors, 210 chunk boundaries, the
strict server application corpus, and three repetitions of the deterministic
scalar GET/PUT corpora and native/lightweight socket and TLS corpora. The SQLite
wrapper, catalog, backend, reopen, and upgrade gate passed separately. The PUT
inventory verifier reported five operations, 32 request/nested members, four
exact enum domains, and eleven reciprocal vectors; the expanded GET verifier
reported six operations, 26 members, five enum domains, and thirteen vectors.
The 116-operation coverage verifier and its negative oracle also passed. The
repository-integrity gate passed, and the warning-strict GNATdoc build
generated 429 HTML pages with both operation types and all four provider-owned
overloads for `Set_ABAC` and `Set_Request_Payment` present in
`Client.Buckets`.

The latest serialized proof campaign remains the 2026-08-26 936/936 result.
This slice does not change any of the nine `tools/prove.sh` manifest units, so
a redundant proof rerun was not performed.
