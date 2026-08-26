# GetBucketMetadataTableConfiguration client qualification

This record qualifies the strict bounded provider-owned composable and typed
synchronous clients and corpus for `GetBucketMetadataTableConfiguration`. It
does not claim metadata-table state in a Flyology backend, an authenticated
Flyology server route, or external server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 249 has required `Bucket` and optional `ExpectedBucketOwner`.
Output shape 248 optionally contains result shape 250. A present result
requires `MetadataTableConfigurationResult` and `Status`, and optionally
contains `Error`. The configuration requires `S3TablesDestinationResult`,
whose four required strings are `TableBucketArn`, `TableName`, `TableArn`,
and `TableNamespace`. Optional error shape 196 contains `ErrorCode` and
`ErrorMessage`.

The reciprocal member and vector ledgers contain all 13 named members and 13
request, response, schema, security, header, limit, and transport contracts.
The verifier also gates requiredness, locations, the absence of flattened
members and enum domains, and the absence of independent string bounds:

```sh
UV_CACHE_DIR=/private/tmp/fos-uv-cache uv run --python 3.13 -- \
  ./tools/verify-get-bucket-metadata-table-configuration-preparation.py
```

## Provider-owned API and response contract

`Client.Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration` reuses the
strict common bucket-control projector. It validates the bucket and bounded
owner before transport, signs an empty body, projects only the two modeled
inputs, and supports path and virtual-hosted addressing.

`Client.Low_Level.Get_Bucket_Metadata_Table_Configuration` starts only the
exact prepared operation into the parent provider's bounded response sink;
another prepared operation is rejected before HTTP admission.
`Client.Buckets.Get_Metadata_Table_Configuration` owns the limited
constructor, operation-last reusable initiation, operation state, and typed
`Finish`. The typed synchronous overload waits on that same state machine.
All forms consume one bounded same-response body and return a typed result or
strict S3 error. There is no retry, helper task, retained borrowed input, or
second protocol engine. The established low-level synchronous executor
remains available over the same preparation and decoder.

An empty successful body preserves optional outer-result absence. A present
result requires the nested configuration, destination, all four destination
strings, and `Status`. Required strings may be empty because the pinned model
sets no minimum. `Status` remains exact opaque provider text: the client does
not invent a lifecycle enum or reject future values. Optional `Error`,
`ErrorCode`, and `ErrorMessage` preserve structure/member presence and empty
text. All provider strings are bounded by caller-selected shared XML limits.

The parser rejects missing required structures or strings; unknown,
duplicate, misplaced, nested, or attributed fields; foreign or mixed
namespaces; DTDs, entities, processing instructions, malformed UTF-8; and
caller-limit violations. Diagnostic request and host IDs must each be absent
or one nonempty control-free bounded value.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles; exact/one-past owner
and diagnostic bounds; outer absence; full and empty required strings;
optional error absence, empty structure, and populated members; future opaque
status text; required-member failures; strict schemas and namespaces;
representative non-200 statuses; cross-operation rejection; and
exact/one-past success and error XML byte, depth, element, and text limits.

The raw-loopback corpus adds signed nested success, absence, typed rejection,
duplicate and empty physical diagnostic headers, malformed XML, and a body
over the caller limit. Provider coverage adds exact-operation pre-admission
rejection, typed synchronous success, limited construction, consumed restart,
duplicate-header failure, caller-selected response bounds, every modeled
status/code mapping, and every HTTP terminal failure across all admission
certainties. The common root gate repeats the entire socket sequence under
native and Flyology lightweight task owners three times.

The machine ledger records `GetBucketMetadataTableConfiguration` as `missing
/ covered / missing / covered`. Client and corpus qualification does not
manufacture backend state or a server route; those cells require separate
persistence, routing, and independent black-box evidence.

## Formal boundary

This slice changes only non-SPARK client, corpus, verifier, and documentation
units. Neither changed client package appears in the nine `tools/prove.sh`
manifest units, so the latest serialized result remains applicable: 936/936
checks, 180 flow and 756 prover, with zero warnings, unproved or justified
checks, or `pragma Assume` statements.

## Gate evidence

The root gate passed 41/41 AUnit checks, 132 files crash-recovery scenarios,
320 checksum vectors with 210 chunkings, and three complete deterministic and
native/lightweight socket-corpus repetitions. The preparation verifier,
operation-coverage verifier, and its negative oracle all passed. GNATdoc
produced a 43,972-line log and nonempty API index containing the low-level
exact initiator, provider result and operation types, three
`Get_Metadata_Table_Configuration` forms, and typed `Finish`. The new public
declarations emitted no targeted warnings, and the log contained no internal
parser error signature.
