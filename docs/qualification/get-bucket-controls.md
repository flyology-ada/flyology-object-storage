# Bucket-control GET client qualification

This record qualifies strict bounded synchronous clients and corpora for
`GetBucketAbac`, `GetBucketAccelerateConfiguration`, `GetBucketPolicy`,
`GetBucketPolicyStatus`, `GetBucketRequestPayment`, and
`GetPublicAccessBlock`. The client-family record itself does not manufacture
backend or server coverage; `GetPublicAccessBlock` now has that independent
coverage in [public-access-block.md](public-access-block.md). No external-
provider interoperability is claimed here.

## Pinned authority and complete inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
It records the six exact GET operations, request and output shapes, subresource
URIs, 200 success codes, all 26 request/output/nested members, member shapes,
wire locations, required flags, and the five relevant enum domains.

`tests/corpora/get-bucket-controls/operations.tsv` binds each generated
operation to its exact low-level preparer, executor, and high-level convenience
call. `members.tsv` records every ordered member. `vectors.tsv` records thirteen
reciprocal model, request, response, and transport contracts. The verifier
checks all of that evidence against the pinned generated model and both public
API layers:

```sh
python3 tools/verify-get-bucket-controls-preparation.py
```

## Request and response contracts

Every low-level preparer requires one valid bucket, supports path and
virtual-hosted addressing, projects the optional expected-owner precondition,
signs an empty body, and binds the exact generated operation. Only the
accelerate request projects `x-amz-request-payer`, whose sole modeled value is
the exact lowercase `requester`. Each executor rejects a request prepared for
another member of the family before entering HTTP.

ABAC status preserves absent, `Enabled`, and `Disabled`. Accelerate status
preserves absent, `Enabled`, and `Suspended`. Request payment
preserves absent, `Requester`, and `BucketOwner`. Policy status preserves
presence independently from its Boolean value. Public-access block does the
same for `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, and
`RestrictPublicBuckets`. Accelerate additionally preserves the optional exact
`x-amz-request-charged: requester` response header.

The five structured outputs use the strict shallow S3 XML parser. They accept
only the exact root and modeled children, no attributes, no duplicate or nested
fields, exact lowercase Boolean values, and either the established empty
namespace or `http://s3.amazonaws.com/doc/2006-03-01/`. Foreign namespaces,
unknown fields, malformed XML, DTDs, entities, and caller-limit violations are
rejected without a partial output. `GetBucketPolicy` instead returns the exact
same-response payload, including an empty payload, and applies the caller's
document-byte ceiling without inventing an independent policy limit.

Non-200 responses require one strict bounded S3 error. Calls are synchronous,
do not retry, retain no caller input, release their response before return, and
create no detached helper task.

## Corpus and coverage boundary

The deterministic corpus covers exact targets and signed headers,
cross-operation pre-admission rejection, every modeled successful output,
optional presence, raw policy byte boundaries, exact enum and Boolean
spellings, namespace compatibility, malformed XML, DTD/entity rejection, and
structured errors. The raw-loopback corpus performs all five high-level calls
over sequential signed real-socket responses under both native and Flyology
lightweight callers; the root gate repeats that corpus three times.

The machine ledger records `GetPublicAccessBlock` as `covered / covered /
covered / covered` using the independent backend and server evidence in the
dedicated qualification record. The other five operations remain `missing /
covered / missing / covered`; this client corpus does not manufacture their
backend persistence or server routes.

## Gate evidence

The final warning-strict root gate passed 38/38 AUnit tests, the 88-case files
crash matrix, 320 checksum oracle vectors, 210 chunk boundaries, the strict
server application corpus, and three repetitions of the deterministic family
corpus and native/lightweight socket and TLS corpora. The SQLite wrapper,
catalog, backend, reopen, and upgrade gate passed separately. The operation
inventory verifier reported six operations, 26 request/output/nested members,
five exact enum domains, and thirteen reciprocal vectors; the 116-operation
coverage verifier and its negative oracle also passed.

The latest serialized proof campaign remains the 2026-08-23 936/936 result.
This slice changes only non-SPARK client, codec, corpus, coverage, and
documentation units, not any of the nine `tools/prove.sh` manifest units, so a
redundant proof rerun was not performed.
