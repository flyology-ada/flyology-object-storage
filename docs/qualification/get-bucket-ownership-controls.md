# GetBucketOwnershipControls client qualification

This record qualifies the strict bounded synchronous client and corpus for
`GetBucketOwnershipControls`. It does not claim ownership-control persistence
in a Flyology backend, an authenticated Flyology server route, or
external-server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 255 has required `Bucket` and optional `ExpectedBucketOwner`.
Output shape 254 has the optional `OwnershipControls` payload. Shape 501 has
the required `Rules` list; list shape 503 contains shape 502 under the exact
flattened `Rule` wire name. Every rule requires `ObjectOwnership`, whose shape
485 permits exactly `BucketOwnerPreferred`, `ObjectWriter`, and
`BucketOwnerEnforced`.

`tests/corpora/get-bucket-ownership-controls/members.tsv` records all five
named members, their shapes, locations, required flags, and implementation
boundary. `vectors.tsv` contains 13 reciprocal request, response, list,
security, header, limit, and transport contracts. The verifier additionally
checks the list member shape and flattened wire name, so list-shape drift
cannot hide behind the named-member count:

```sh
python3 tools/verify-get-bucket-ownership-controls-preparation.py
```

## Synchronous API and response contract

`Client.Low_Level.Prepare_Get_Bucket_Ownership_Controls` reuses the common
bucket-control request projector and validates the bucket and bounded owner
precondition before transport. It projects only the two generated inputs,
signs an empty payload, and supports path and virtual-hosted addressing.

`Execute_Get_Bucket_Ownership_Controls` drives the same common synchronous
bucket-control response state machine as the already qualified scalar reads.
It admits only this exact modeled operation, consumes one bounded whole body,
and returns either a typed configuration or strict S3 rejection. There is no
retry, helper task, retained input, or new transport engine.

An empty successful body preserves absence of the optional outer payload. A
present payload must contain at least one flattened `Rule`, because the pinned
`Rules` member is required and a present empty flattened list has no wire
representation. Every rule must contain exactly one required enum. The public
vector has no independent count ceiling because the pinned list has none; its
population remains bounded by the caller-selected XML element limit.

The parser rejects wrong roots, missing required rules or values, unknown or
duplicate rule fields, attributes, foreign or mixed namespaces,
whitespace-altered or unknown enums, DTDs, entities, processing instructions,
malformed UTF-8, and caller-limit violations. Physical request-ID and host-ID
fields must each be absent or one nonempty control-free value within the
shared response-header boundary.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles; owner omission,
projection, and exact/one-past bounds; outer absence; every enum; repeated
valid rules; all required-member failures; strict schemas and namespaces;
representative non-200 statuses; response identifier bounds; cross-operation
rejection; and exact/one-past document, depth, element, and text limits.

The consolidated raw-loopback corpus adds signed multi-rule success, outer
absence, strict rejection, physical identifier multiplicity and emptiness,
malformed and transport-oversized bodies, and identical execution under
native and Flyology lightweight task owners. The root gate repeats both paths
three times.

The machine ledger records `GetBucketOwnershipControls` as `missing / covered
/ missing / covered`. Client and corpus evidence do not manufacture backend
state or a server route. Promoting either remaining cell requires a separately
approved persistence contract, authenticated routing, and independent
black-box tests.

## Formal boundary and gates

This slice changes only non-SPARK client, parser, corpus, and documentation
units. None of the nine `tools/prove.sh` manifest units changes, so the latest
serialized 2026-08-24 proof result remains applicable: 936/936 checks, 180
flow and 756 prover, with zero warnings, unproved or justified checks, or
`pragma Assume` statements.

The warning-strict root gate passed 40/40 AUnit tests, the 88-case files crash
matrix, 320 checksum vectors, 210 chunk boundaries, the server application
corpus, and three deterministic and native/lightweight socket repetitions.
The SQLite wrapper, catalog, and backend gate passed after rebuilding against
the public specification. The inventory and 116-operation coverage verifiers,
the coverage negative oracle, and GNATdoc 26 all passed; GNATdoc produced a
nonempty API index containing every new ownership type, field, enum, and call.
