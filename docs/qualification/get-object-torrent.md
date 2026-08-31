# GetObjectTorrent client qualification

This record preserves the completed strict low-level streaming qualification
and defines provider-composable bounded evidence for `GetObjectTorrent`. The
new lifecycle lanes are not qualification evidence until the maintained
focused gate passes. This record does not claim torrent generation in any
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
contains 21 reciprocal request, response, transport, admission, error, header,
streaming, limit, ownership, cancellation, restart, and equivalence contracts.
The verifier checks the pinned upstream
revision and hash; exact method, URI, status, shapes, payload, member names,
member shapes, locations, required and streaming flags; typed API presence;
canonical vector IDs; and both directions of every member/vector reference:

```sh
python3 tools/verify-get-object-torrent-preparation.py
```

## Low-level and provider-composable ownership contract

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

`Client.Objects.Get_Torrent` adds bounded provider-owned initiation without a
parallel namespace. The limited-root constructor, operation-last restart,
typed `Finish`, and synchronous wrapper all use the same operation state
machine. The operation retains the caller's HTTP client, acquired destination
buffer, and optional cancellation token by identity; restart rejects any
replacement before preparing or admitting another request. Parent
terminalization and the hidden HTTP child's `Finish` restore the caller buffer
exactly once before public typed `Finish` consumes the terminal result. A
successful body fills it with exact octets; a typed rejection, cancellation,
or known-capacity failure restores it empty. Known `Content-Length` over
capacity reports the
required length rather than partially filling the destination.

Cancellation evidence is admission-aware: after validating the exact signed
first request, the test peer withholds its response, observes EOF or reset on
that same connection, and only then acknowledges terminal drain. The caller
cancels, receives the exact `Possibly_Admitted` certainty, waits for all
operation work, consumes typed `Finish`, waits for the peer's drain
acknowledgment, and only then restarts the same operation object. The
successful second exchange is not a replay of the admitted request.

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
original twelve signed low-level exchanges run under native and Flyology
lightweight task owners. The expanded socket corpus also exercises limited-root
binary success, typed rejection with an empty restored buffer, known capacity
failure, operation-last restart, admitted cancellation followed by EOF/drain
and restart, synchronous/composable equivalence, retained HTTP/buffer/token
identity rejection, and exact-operation pre-admission rejection. The root gate
repeats both corpora three times.

The machine ledger records `GetObjectTorrent` as `missing / covered / missing /
covered`. Client and corpus evidence do not manufacture backend torrent
generation or a server route. Promoting either remaining cell requires an
independent generation contract, authenticated routing, and black-box tests.

## Gate evidence

The maintained warning-strict root gate passed 41/41 AUnit tests with zero
failed assertions or unexpected errors, the 132-case files crash matrix, the
strict server application corpus, and three native/lightweight repetitions of
the deterministic GetObjectTorrent preparation and signed socket corpora. The
dedicated inventory verifier reported four request members, two output
members, and 21 reciprocal vectors against the pinned model.

A fresh GNATdoc 26 site and index were produced after the composable slice.
The changed GetObjectTorrent declaration regions in Low_Level and Objects have
zero retained warnings; the final association repair reduced the repository
warning count by exactly twelve with no added warning. The repository-wide
classifier still stops on the pre-existing undocumented Client parameter in
the generated Buckets specification. This is region-scoped documentation
measurement only, not selected-operation or repository qualification.

The latest serialized proof campaign remains the 2026-08-24 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with zero
warnings, unproved or justified checks, or `pragma Assume` statements. This
slice changes only non-SPARK client, corpus, and documentation units; none of
the nine `tools/prove.sh` manifest units changed after that campaign, so a
redundant formal rerun was not performed.
