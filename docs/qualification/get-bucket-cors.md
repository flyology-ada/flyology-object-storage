# GetBucketCors client qualification

This record qualifies the strict bounded provider-owned composable and typed
synchronous clients and corpus for `GetBucketCors`. It does not claim CORS
persistence in a Flyology backend, an
authenticated Flyology server route, or external-server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 230 has required `Bucket` and optional `ExpectedBucketOwner`.
Output shape 229 has the optional flattened `CORSRules` list, whose shape 72
contains rule shape 71. Each rule has optional `ID`, `AllowedHeaders`,
`ExposeHeaders`, and `MaxAgeSeconds`, plus required `AllowedMethods` and
`AllowedOrigins`. The four nested string lists and outer rule list are all
flattened. Integer shape 412 defines no minimum or maximum.

`tests/corpora/get-bucket-cors/members.tsv` records all nine named members,
their shapes, locations, required flags, and implementation boundary.
`vectors.tsv` contains 13 reciprocal request, response, schema, security,
header, limit, and transport contracts. The verifier also gates the five list
member shapes, all flattened flags, the document root authority, and the
unbounded integer shape:

```sh
python3 tools/verify-get-bucket-cors-preparation.py
```

## Provider API and response contract

`Client.Low_Level.Prepare_Get_Bucket_CORS` reuses the common bucket-control
request projector. It validates the bucket and bounded owner precondition
before transport, projects only the two modeled inputs, signs an empty
payload, and supports path and virtual-hosted addressing.

The prepared-request `Client.Low_Level.Get_Bucket_CORS` initiator admits only
the exact modeled operation and drives one caller-provided bounded sink.
`Client.Buckets.Get_CORS` owns the limited constructor, operation-last reusable
procedure, operation state, and typed `Finish`. The typed synchronous overload
is a literal wait on that same provider-owned state machine. It consumes one
bounded whole body and returns either a typed configuration or strict S3
rejection. There is no retry, helper task, retained input, or second transport
engine.

An empty successful body preserves absence of the optional output. A present
empty `CORSConfiguration` is preserved separately. Every present rule requires
at least one exact `AllowedMethod` and `AllowedOrigin`; optional flattened
lists preserve every string in wire order. List population is bounded only by
the caller-selected XML element and text limits because the pinned shapes have
no independent maxima. `MaxAgeSeconds` is retained as validated signed decimal
text because conversion to a machine integer would invent a compatibility
ceiling absent from the model.

The parser rejects wrong roots, missing required lists, unknown or duplicate
singleton fields, nesting, attributes, foreign or mixed namespaces, malformed
decimals, DTDs, entities, processing instructions, malformed UTF-8, and
caller-limit violations. Physical request-ID and host-ID fields must each be
absent or one nonempty control-free value within the shared header boundary.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles; owner projection;
outer absence versus present-empty configuration; repeated rules and all four
flattened string lists; empty optional strings; arbitrary-precision signed
decimal preservation; required-member failures; strict schemas and
namespaces; representative non-200 statuses; cross-operation rejection; and
exact/one-past byte, depth, element, and text limits.

The consolidated raw-loopback corpus adds signed success, absent response,
strict rejection, duplicate and empty diagnostic headers, malformed XML, and
transport-oversized bodies. It also exercises the typed synchronous call,
limited constructor, operation-last restart, exact prepared-operation
rejection, and a caller-bounded response-sink failure. The root gate runs that
sequence identically under native and Flyology lightweight task owners and
repeats both paths three times.

The machine ledger records `GetBucketCors` as `missing / covered / missing /
covered`. Client and corpus evidence do not manufacture backend state or a
server route. Promoting either remaining cell requires a separately approved
persistence contract, authenticated routing, and independent black-box tests.

## Formal boundary

The provider-owned scheduling path requires a fresh serialized exact-tree
`tools/prove.sh` campaign before publication even though its implementation is
outside the nine SPARK manifest units. Proof evidence is recorded only after
the shared formal lane is granted and the maintained wrapper and post-run host
audit both complete cleanly.

The warning-strict root gate passed 41/41 AUnit tests, the 126-case files crash
matrix, 320 checksum vectors, 210 chunk boundaries, and three deterministic
and native/lightweight socket repetitions. The SQLite wrapper, catalog, and
backend gate passed after rebuilding against the public specification. The
inventory and 116-operation coverage verifiers, coverage negative oracle, and
GNATdoc 26 passed; GNATdoc produced a nonempty API index containing every new
CORS type, field, and call with no new targeted documentation warnings.
