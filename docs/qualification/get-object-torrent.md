# GetObjectTorrent client qualification

This record qualifies the strict bounded synchronous streaming client and
corpus for `GetObjectTorrent`. It does not claim torrent generation in any
Flyology backend, an authenticated Flyology server route, or external-server
interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 289 has exactly four members: required `Bucket` and `Key` URI
labels, optional `RequestPayer`, and optional `ExpectedBucketOwner`. Output
shape 288 has the streaming `Body` payload and optional `RequestCharged`
header. The sole payer and charged enum value is `requester`.

`tests/corpora/get-object-torrent/members.tsv` records all six members, shapes,
wire locations, required flags, and the streaming boundary. `vectors.tsv`
contains 13 reciprocal request, response, transport, admission, error, header,
streaming, and limit contracts. The verifier checks the pinned upstream
revision and hash; exact method, URI, status, shapes, payload, member names,
member shapes, locations, required and streaming flags; typed API presence;
canonical vector IDs; and both directions of every member/vector reference:

```sh
python3 tools/verify-get-object-torrent-preparation.py
```

## Synchronous API and ownership contract

`Client.Low_Level.Prepare_Get_Object_Torrent` validates the bucket, key,
requester-pays value, and bounded owner precondition before transport. It
projects only the four generated-model inputs, signs an empty payload, and
supports path and virtual-hosted addressing.

`Execute_Get_Object_Torrent` admits only a prepared request for this exact
operation and returns the limited HTTP response without consuming it. The
caller must decode its head, consume or deliberately abandon the body, and
finish the limited response before reusing the client capacity. On status 200,
`Decode_Get_Object_Torrent_Response_Head` leaves every body octet unread and
returns the optional charged value. On all other statuses it consumes only the
caller-selected bounded XML error body and returns a strict typed S3 rejection.
There is no transparent retry, helper task, retained request input, body text
conversion, or operation-specific body-size ceiling.

Physical charged, request-ID, and host-ID headers must each be absent or one
nonempty control-free value within the shared response-header bound. Duplicate
physical fields are rejected before any collapsed value can be observed. The
charged value must be exactly `requester` when present.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles and exact signed
targets; optional-header omission and presence; invalid and exact/one-past
bucket, key, payer, and owner inputs; success status and charged values; five
error status classes; malformed, DTD, and entity documents; identifier
controls; and exact/one-past XML document limits. Cross-operation execution is
rejected before HTTP.

The raw-loopback corpus adds binary and chunked successful bodies, response
head/body fragmentation, exact successful byte preservation, duplicate, empty,
and unmodeled charged headers, typed rejection identifiers, duplicate request
and host IDs, an empty physical request ID, malformed and transport-oversized
errors, and a successful body one byte beyond an explicit caller limit. The
same twelve signed exchanges run under native and Flyology lightweight task
owners, and the root gate repeats both corpora three times.

The machine ledger records `GetObjectTorrent` as `missing / covered / missing /
covered`. Client and corpus evidence do not manufacture backend torrent
generation or a server route. Promoting either remaining cell requires an
independent generation contract, authenticated routing, and black-box tests.

## Gate evidence

The final warning-strict root gate passed 40/40 AUnit tests with zero failed
assertions or unexpected errors, the 88-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the deterministic GetObjectTorrent corpus and its 24
native/lightweight signed socket exchanges. The SQLite wrapper, catalog, and
backend gate passed separately after rebuilding against the public client spec.

The inventory verifier reported four request members, two output members, and
13 reciprocal vectors; the 116-operation coverage verifier and its negative
oracle also passed. GNATdoc 26 generated a nonempty object-storage API index,
and every new GetObjectTorrent entity, field, parameter, enum value, and return
value is documented in its leading public-spec comments.

The latest serialized proof campaign remains the 2026-08-24 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with zero
warnings, unproved or justified checks, or `pragma Assume` statements. This
slice changes only non-SPARK client, corpus, and documentation units; none of
the nine `tools/prove.sh` manifest units changed after that campaign, so a
redundant formal rerun was not performed.
