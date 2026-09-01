# GetObjectRetention client qualification

This record covers the strict bounded provider-owned composable and
synchronous client plus corpus for `GetObjectRetention`. Shared Flyology
backend persistence and authenticated server-route evidence is recorded in
`object-lock-server.md`; external-server interoperability is not claimed.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 285 has exactly five members: required `Bucket` and `Key` URI
labels, optional `VersionId`, optional `RequestPayer`, and optional
`ExpectedBucketOwner`. Output shape 284 has the optional `Retention` payload.
Nested shape 480 has optional `Mode` and `RetainUntilDate`; shape 481 permits
exactly `GOVERNANCE` and `COMPLIANCE`, while timestamp shape 140 requires the
`iso8601` wire format and the sole payer enum value is `requester`.

`tests/corpora/get-object-retention/members.tsv` records all eight members,
their shapes, locations, required flags, and implementation boundary.
`vectors.tsv` contains 13 reciprocal request, response, timestamp, security,
header, limit, and transport contracts. The verifier checks the pinned
upstream identity; exact method, URI, status, shapes, payload, member names,
shapes, locations, required flags, enum domains, and timestamp format; typed
API presence; canonical vector IDs; and both directions of every
member/vector reference:

```sh
python3 tools/verify-get-object-retention-preparation.py
```

## Provider-owned API and response contract

`Client.Low_Level.Prepare_Get_Object_Retention` validates the bucket, key,
opaque bounded version selector, exact requester-pays value, and bounded owner
precondition before transport. It projects only the five generated-model
inputs, signs an empty payload, and supports path and virtual-hosted
addressing.

`Client.Low_Level.Get_Object_Retention` starts only a prepared request for this
exact operation into a caller-owned bounded sink. `Client.Objects` owns the
limited parent, signed request, same-response XML, HTTP child, cancellation,
and terminal drain. Its limited constructor, same-name operation-last
procedure, and typed `Finish` expose composition directly from the Objects
provider. The parameter-record synchronous overload waits on that same state
machine. `Execute_Get_Object_Retention` remains the established blocking
low-level form and returns the same modeled response.

There is no transparent retry, helper task, retained request input, or
operation-specific XML limit. Both paths use the shared `S3.XML.Parse_Limits`
policy, and the composable parent applies that same document-byte ceiling to
the response sink before decoding.

An empty successful body preserves absence of the modeled `Retention` payload.
`<Retention/>` preserves a present payload with both children absent. `Mode`
and `RetainUntilDate` remain independently optional. An explicit mode is
accepted only as case-sensitive `GOVERNANCE` or `COMPLIANCE`; an explicit date
must satisfy the pinned ISO-8601 calendar, fraction, and zone grammar and is
returned verbatim without normalization. No default mode, retention period, or
date is synthesized.

The strict parser rejects wrong roots, foreign namespaces, attributes, unknown
or duplicate members, nested field content, whitespace-altered enums, invalid
calendar or zone values, DTDs, entities, processing instructions, malformed
UTF-8, and caller-limit violations. Physical request-ID and host-ID fields must
each be absent or one nonempty control-free value within the shared response
header boundary.

## Corpus and coverage boundary

The deterministic corpus covers path and virtual-hosted targets; optional
omission and projection; exact and one-past key, version, owner, and response
identifier boundaries; exact payer and mode enums; outer and nested presence;
UTC, fractional, offset, leap-day, and invalid timestamp cases;
representative non-200 statuses; strict schemas and namespaces; and exact and
one-past document, depth, element, and text limits. Cross-operation execution
is rejected before HTTP.

The consolidated raw-loopback corpus adds signed success and rejection
exchanges, physical identifier multiplicity and emptiness, malformed and
transport-oversized success bodies, exact prepared-operation rejection before
admission, limited construction, operation-last restart, typed Finish,
synchronous parity, an actual one-past composable sink failure, and identical
execution under native and Flyology lightweight task owners. The direct
normalization oracle crosses every terminal HTTP failure with every admission
certainty. The root gate repeats the deterministic and socket paths three
times.

The machine ledger records `GetObjectRetention` as `covered / covered / covered
/ covered`. This client record remains operation-specific; the shared Object
Lock record owns backend persistence, authenticated routing, and independent
black-box tests.

## Formal boundary

This slice changes only non-SPARK client, parser, corpus, and documentation
units. None of the nine `tools/prove.sh` manifest units changes, so the latest
serialized proof result remains applicable and a redundant campaign is not
required for this client-only closure.

## Gate evidence

The final warning-strict root gate passed 41/41 AUnit tests with zero failed
assertions or unexpected errors, the 126-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the deterministic retention corpus and consolidated
native/lightweight signed socket corpus. The SQLite wrapper, catalog, and
backend gate passed separately after rebuilding against the public client
specification.

The inventory verifier reported five request members, one top-level output
member, two nested members, both exact enum domains, the ISO-8601 timestamp
format, and 13 reciprocal vectors; the 116-operation coverage verifier and its
negative oracle also passed. GNATdoc 26 completed a 43,629-line run with a
nonempty 430-file object-storage API index containing every new retention type,
field, enum value, parameter, exception, and return value, with no warning on
the new declarations or internal documentation error.

The latest serialized proof campaign remains the 2026-08-24 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with zero
warnings, unproved or justified checks, or `pragma Assume` statements. This
slice does not alter any manifest unit, so no formal tool was started and the
shared prover/model-checker lane remained free after DB's clean release.
