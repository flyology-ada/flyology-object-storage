# GetObjectLegalHold client qualification

This record qualifies the strict bounded synchronous client and corpus for
`GetObjectLegalHold`. It does not claim Object Lock persistence in a Flyology
backend, an authenticated Flyology server route, or external-server
interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 278 has exactly five members: required `Bucket` and `Key` URI
labels, optional `VersionId`, optional `RequestPayer`, and optional
`ExpectedBucketOwner`. Output shape 277 has the optional `LegalHold` payload.
Nested shape 476 has optional `Status`; shape 477 permits exactly `ON` and
`OFF`, while the sole payer enum value is `requester`.

`tests/corpora/get-object-legal-hold/members.tsv` records all seven members,
their shapes, locations, required flags, and implementation boundary.
`vectors.tsv` contains 13 reciprocal request, response, security, header,
limit, and transport contracts. The verifier checks the pinned upstream
identity; exact method, URI, status, shapes, payload, member names, shapes,
locations, required flags, and enum domains; typed API presence; canonical
vector IDs; and both directions of every member/vector reference:

```sh
python3 tools/verify-get-object-legal-hold-preparation.py
```

## Synchronous API and response contract

`Client.Low_Level.Prepare_Get_Object_Legal_Hold` validates the bucket, key,
opaque bounded version selector, exact requester-pays value, and bounded owner
precondition before transport. It projects only the five generated-model
inputs, signs an empty payload, and supports path and virtual-hosted
addressing.

`Execute_Get_Object_Legal_Hold` admits only a prepared request for this exact
operation. It consumes one bounded whole response body and returns either the
typed legal-hold value or a strict typed S3 rejection. There is no transparent
retry, helper task, retained request input, or operation-specific XML limit;
the caller supplies the shared `S3.XML.Parse_Limits` policy.

An empty successful body preserves absence of the modeled `LegalHold` payload.
`<LegalHold/>` preserves a present payload with absent `Status`. An explicit
status is accepted only as case-sensitive `ON` or `OFF`. The strict parser
rejects wrong roots, foreign namespaces, attributes, unknown or duplicate
members, nested status content, whitespace-altered enums, DTDs, entities,
processing instructions, malformed UTF-8, and caller-limit violations.
Physical request-ID and host-ID fields must each be absent or one nonempty
control-free value within the shared response-header boundary.

## Corpus and coverage boundary

The deterministic corpus covers path and virtual-hosted targets; optional
omission and projection; exact and one-past key, version, owner, and response
identifier boundaries; exact payer enums; outer and nested presence; both
status values; strict schemas and namespaces; representative error statuses;
and exact/one-past document, depth, element, and text limits. Cross-operation
execution is rejected before HTTP.

The consolidated raw-loopback corpus adds signed success and rejection
exchanges, physical identifier multiplicity and emptiness, malformed and
transport-oversized success bodies, and identical execution under native and
Flyology lightweight task owners. The root gate repeats the deterministic and
socket paths three times.

The machine ledger records `GetObjectLegalHold` as `missing / covered / missing
/ covered`. Client and corpus evidence do not manufacture backend Object Lock
state or a server route. Promoting either remaining cell requires a separately
approved persistence contract, authenticated routing, and independent
black-box tests.

## Formal boundary

This slice changes only non-SPARK client, parser, corpus, and documentation
units. None of the nine `tools/prove.sh` manifest units changes, so the latest
serialized proof result remains applicable and a redundant campaign is not
required for this client-only closure.

## Gate evidence

The final warning-strict root gate passed 40/40 AUnit tests with zero failed
assertions or unexpected errors, the 88-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the deterministic legal-hold corpus and consolidated
native/lightweight signed socket corpus. The SQLite wrapper, catalog, and
backend gate passed separately after rebuilding against the public client
specification.

The inventory verifier reported five request members, one top-level output
member, one nested member, two exact enum domains, and 13 reciprocal vectors;
the 116-operation coverage verifier and its negative oracle also passed.
GNATdoc 26 completed with a nonempty object-storage API index containing every
new legal-hold type, field, enum value, parameter, exception, and return value.

The latest serialized proof campaign remains the 2026-08-24 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with zero
warnings, unproved or justified checks, or `pragma Assume` statements. This
slice does not alter any manifest unit, so no formal tool was started and the
shared prover/model-checker lane remained free after DB's clean release.
