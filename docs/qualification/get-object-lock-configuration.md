# GetObjectLockConfiguration client qualification

This record qualifies the strict bounded synchronous client and corpus for
`GetObjectLockConfiguration`. It does not claim Object Lock persistence in a
Flyology backend, an authenticated Flyology server route, or external-server
interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 280 has exactly two members: required `Bucket` and optional
`ExpectedBucketOwner`. Output shape 279 has the optional
`ObjectLockConfiguration` payload. Shape 473 contains optional
`ObjectLockEnabled` and `Rule`; shape 482 contains optional
`DefaultRetention`; and shape 143 contains optional `Mode`, `Days`, and
`Years`. Shape 474 permits exactly `Enabled`, and shape 481 permits exactly
`GOVERNANCE` and `COMPLIANCE`. Integer shapes 141 and 718 have no pinned
minimum, maximum, or pattern.

`tests/corpora/get-object-lock-configuration/members.tsv` records all nine
members, their shapes, locations, required flags, and implementation boundary.
`vectors.tsv` contains 13 reciprocal request, response, integer, security,
header, limit, and transport contracts. The verifier checks the pinned
upstream identity; exact method, URI, status, shapes, payload, member names,
shapes, locations, required flags, enum domains, and unbounded integer model;
typed API presence; canonical vector IDs; and both directions of every
member/vector reference:

```sh
python3 tools/verify-get-object-lock-configuration-preparation.py
```

## Synchronous API and response contract

`Client.Low_Level.Prepare_Get_Object_Lock_Configuration` validates the bucket
and bounded owner precondition before transport. It projects only the two
generated-model inputs, signs an empty payload, and supports path and
virtual-hosted addressing.

`Execute_Get_Object_Lock_Configuration` admits only a prepared request for
this exact operation. It consumes one bounded whole response body and returns
either the typed configuration or a strict typed S3 rejection. There is no
transparent retry, helper task, retained request input, or operation-specific
XML limit; the caller supplies the shared `S3.XML.Parse_Limits` policy.

An empty successful body preserves absence of the modeled outer payload.
Every nested container and leaf remains independently optional. Explicit enum
values are case-sensitive. Because the pinned `Days` and `Years` integer
shapes establish no numeric bounds, the client validates signed decimal
syntax and preserves the exact wire text rather than imposing a machine
integer ceiling or normalization. It does not infer relationships among
`Mode`, `Days`, and `Years`.

The strict parser rejects wrong roots, foreign or mixed namespace styles,
attributes, unknown or duplicate members, nested leaf content,
whitespace-altered enums or integers, empty or sign-only integers, DTDs,
entities, processing instructions, malformed UTF-8, and caller-limit
violations. Physical request-ID and host-ID fields must each be absent or one
nonempty control-free value within the shared response-header boundary.

## Corpus and coverage boundary

The deterministic corpus covers path and virtual-hosted targets; owner
omission and projection; exact and one-past owner and response-identifier
boundaries; every outer and nested presence layer; enum spellings; arbitrarily
large and leading-zero signed decimal text; strict schemas and namespaces;
representative error statuses; and exact/one-past document, depth, element,
and text limits. Cross-operation execution is rejected before HTTP.

The consolidated raw-loopback corpus adds signed success and rejection
exchanges, physical identifier multiplicity and emptiness, malformed and
transport-oversized success bodies, and identical execution under native and
Flyology lightweight task owners. The root gate repeats the deterministic and
socket paths three times.

The machine ledger records `GetObjectLockConfiguration` as `missing / covered
/ missing / covered`. Client and corpus evidence do not manufacture backend
Object Lock state or a server route. Promoting either remaining cell requires
a separately approved persistence contract, authenticated routing, and
independent black-box tests.

## Formal boundary

This slice changes only non-SPARK client, parser, corpus, and documentation
units. None of the nine `tools/prove.sh` manifest units changes, so the latest
serialized proof result remains applicable and a redundant campaign is not
required for this client-only closure.

## Gate evidence

The final warning-strict root gate passed 40/40 AUnit tests with zero failed
assertions or unexpected errors, the 88-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the deterministic configuration corpus and
consolidated native/lightweight signed socket corpus. The SQLite wrapper,
catalog, and backend gate passed separately after rebuilding against the
public client specification.

The inventory verifier reported two request members, one top-level output
member, six nested members, exact enum domains, both unbounded integer shapes,
and 13 reciprocal vectors; the 116-operation coverage verifier and its
negative oracle also passed. GNATdoc 26 completed with a nonempty
object-storage API index containing every new configuration type, field, enum
value, parameter, exception, and return value.

The latest serialized proof campaign remains the 2026-08-24 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with zero
warnings, unproved or justified checks, or `pragma Assume` statements. This
slice does not alter any manifest unit, so no formal tool was started and the
shared prover/model-checker lane remained free after DB's clean release.
