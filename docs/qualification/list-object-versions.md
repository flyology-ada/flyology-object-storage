# ListObjectVersions client qualification

This record qualifies the bounded synchronous client, strict wire corpus, and
the first bounded in-memory retained-generation slice for
`ListObjectVersions`. It does not claim delete markers, delimiter pagination,
durable files/SQLite generations, an authenticated Flyology server route, or
external-server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
It accounts for all 45 members across seven generated shapes:

- request shape 395: 10 members;
- output shape 394: 14 top-level members, including the sole response header;
- ObjectVersion shape 491: 11 members;
- DeleteMarkerEntry shape 161: five members;
- Owner shape 499: two members;
- RestoreStatus shape 617: two members; and
- CommonPrefix shape 97: one member.

`tests/corpora/list-object-versions/members.tsv` maps every member to its wire
location, implemented boundary, contract, and reciprocal vectors.
`vectors.tsv` contains 23 request, response, transport, pagination, scalar,
identity, and limit designs. The standard-library-only verifier checks the
locked upstream revision and hash, exact generated counts, ordered names, wire
locations, canonical vector IDs, and both directions of every member/vector
reference:

```sh
python3 tools/verify-list-object-versions-preparation.py
```

## Synchronous API boundary

`Client.Low_Level.List_Object_Versions_Parameters` represents every
non-bucket request member with presence flags for explicit empty query values.
`Prepare_List_Object_Versions` projects the `versions` subresource, delimiter,
`url` encoding selection, key/version marker pair, 0-through-1000 maximum,
prefix, expected owner, requester-pays value, and the sole modeled optional
object attribute, `RestoreStatus`. A version-ID marker without a key marker and
any unmodeled payer are rejected before HTTP admission.

`Execute_List_Object_Versions` accepts only a prepared request for this
operation, reads at most the configured XML document bound, enforces physical
singleton response headers, and returns either a complete typed page or a
bounded structured S3 rejection. Successful pages are bound to the prepared
bucket, maximum, markers, prefix, delimiter, and encoding selection. AWS may
echo an omitted optional filter as an empty XML element, so omission accepts
either no echo or a present-empty echo but rejects every nonempty value. An
explicit request requires an exact echo. With `EncodingType=url`, key-bearing
fields use the S3 URL representation while version IDs remain opaque and are
never percent-decoded or re-encoded.

`Client.Objects.List_Versions_Page` is the public one-page wrapper. A caller
continues a truncated result by passing both `Next_Key_Marker` and
`Next_Version_ID_Marker` from the outcome back as the paired cursor. When URL
encoding is selected, the wrapper decodes the returned key marker to logical
bytes before exposing it, so the next request encodes it exactly once; version
IDs remain opaque. Malformed percent encoding is an invalid response. The
wrapper does not retain the HTTP client, credentials, response lease, or task
after the synchronous call returns, and it adds no retry or detached helper
task.

## Strict result contract

The REST/XML parser requires the exact `ListVersionsResult` tree in the empty
or S3 namespace and rejects attributes, unknown or misplaced elements,
wrappers, nested scalars, text outside fields, processing instructions, DTDs,
and entities. Required top-level identity, maximum, and truncation members are
singletons. Versions, delete markers, and common prefixes count together
against `MaxKeys`; truncated pages require both nonempty next markers, while
final pages reject either one.

Every ObjectVersion has a unique key/version identity, nonnegative signed
64-bit size, exact pinned storage class, canonical boolean and ISO-8601
timestamp, and optionally one ETag, owner, restore status, unique checksum
algorithm list, and compatible checksum type. Delete markers require their
key, version ID, latest flag, and timestamp. Duplicate identities within or
across entry kinds, duplicate common prefixes, duplicate singletons, unknown
enum values, invalid dates, and scalar overflow are invalid responses.

The direct corpus covers every one of the ten pinned checksum algorithms, both
checksum types, values above 32 bits and at signed 64-bit maximum, one-past
overflow, exact and one-past document/depth/element/text limits, combined page
count bounds, complete nested projection, malformed structure, typed errors,
and exact signed request projection. The raw-loopback corpus adds 15 exchanges
per caller for complete fragmented success, AWS-compatible empty echoes,
structured rejection with request IDs, duplicate physical headers, every
prepared-response binding class, malformed XML, and an oversized response. It
also follows a URL-encoded two-page response using the wrapper's logical
paired cursor and rejects a malformed encoded continuation marker. The same
sequence runs from a native caller and a Flyology lightweight caller, including
an omitted `max-keys` request bound to the modeled 1000 default, and the root
gate repeats the executable three times.

## Coverage boundary

The machine ledger records `ListObjectVersions` as `partial / covered /
missing / covered`. The memory backend now preserves null and opaque object
generations across unconfigured, enabled, and suspended transitions; identical
overwrites receive distinct opaque IDs; current, null, and exact generation
reads and tags remain isolated; and newest-first paired-cursor pagination is
independently exercised. Its object capacity counts every retained generation,
and its protected state is the atomic publication and listing boundary.

The backend cell remains partial because delete markers, delimiter/common-prefix
pagination, and durable files/SQLite reopen and crash behavior are absent. The
server cell remains missing. Neither cell can be promoted until shared
conformance covers version creation, deletion markers, exact generation
selection, pagination, persistence, crash recovery, and black-box S3 wire
behavior.

## Gate evidence

The warning-strict root gate passed 39/39 AUnit tests with zero failed
assertions or unexpected errors, the 88-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the native/lightweight socket and TLS corpora. The
SQLite wrapper, catalog, backend, reopen, and upgrade gate passed separately.
The inventory verifier reported 45 modeled members across seven shapes and 23
reciprocal vectors; the 116-operation coverage verifier and its negative oracle
also passed. The new backend-neutral memory corpus covers state transitions,
unique identical overwrites, null/current/exact reads, per-version tag
isolation, full ordering, one-entry paired pagination, zero-size pages, and
malformed or unknown selectors and cursors.

The serialized proof campaign started at 2026-08-23T22:07:16Z with FSF
GNATprove 16.1.0. `./tools/prove.sh` used `--level=0`, output headers, and
warnings as errors and proved 936/936 checks across all nine manifest units:
180 flow checks and 756 prover checks, with a maximum of 663 steps. The report
contains zero warnings, unproved or justified checks, and `pragma Assume`
statements. The source suppression audit and post-run GNATprove/Why3/SMT
process audit were clean. GNATdoc generated and exposed the new public API
without warnings for any added entity or selector parameter; its command still
reports the eight inherited bounded-channel internal diagnostics already
tracked outside this slice.
