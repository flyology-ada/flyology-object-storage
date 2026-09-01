# GetObjectTorrent qualification

This record preserves the completed strict low-level streaming qualification
and defines provider-composable bounded evidence for `GetObjectTorrent`. The
new lifecycle lanes are not qualification evidence until the maintained
focused gate passes. The local server now derives one single-file bencoded
information dictionary from an immutable backend object snapshot without
persisting torrent state or adding discovery metadata. This record does not
claim peer seeding, tracker availability, or external-server interoperability.

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

The machine ledger records `GetObjectTorrent` as `covered / covered / covered /
covered`. The backend cell is shared-family evidence: memory, files, and SQLite
all pass the provider-neutral immutable `Get_Object` stream contract. Exact
bencoded-information routing and rendering are exercised through the
memory-backed server;
this record does not claim that the same HTTP exchange was independently run
against the files and SQLite providers.

The server accepts only the exact torrent subresource, validates the expected
owner and request-payer header, and reads the current immutable object through
that backend boundary. It preserves the complete decoded object-key string
accepted by authenticated request-target parsing as `info.name`, without an
additional naming normalization or a broader request-target claim. A required
no-default generic formal makes the piece
length an explicit application choice and is deliberately source-incompatible
for existing generic instantiations. The production executable explicitly
selects 256 KiB; the focused corpus selects 10,000 bytes to exercise piece and
backend-fragment boundaries. Changing either choice changes the info hash.

The pinned operation boundary is strictly smaller than 5 GiB; the sink rejects
the 5 GiB boundary before starting a response. Configured SSE-C object state is
not available in the local server profile, so this route cannot expose one.

The response is a canonical single-file bencoded information dictionary. It
streams the header, one raw SHA-1 digest per configured piece, and the closing
dictionary bytes without retaining the object or complete digest list. It does
not include a tracker or peer-discovery field and therefore makes no
peer-discoverable torrent claim. Empty, multi-piece, final-partial-piece,
backend-fragment-boundary, decoded-path name, missing-object, malformed-query,
owner, payer, request-body, pre-admission cancellation, and response-start
cancellation cases are black-box server evidence.

## Gate evidence

The maintained warning-strict root gate passed 46/46 AUnit tests with zero
failed assertions or unexpected errors, the 140-case files crash matrix, the
strict server application corpus, and three native/lightweight repetitions of
the deterministic GetObjectTorrent preparation and signed socket corpora. The
dedicated inventory verifier reported four request members, two output
members, and 21 reciprocal vectors against the pinned model.

A fresh focused GNATdoc 26 site and index were produced after the server slice.
The maintained classifier reported 333 dependency warnings, zero repository
warnings, zero errors, and one selected API documented.

The latest serialized proof campaign remains the 2026-08-24 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with zero
warnings, unproved or justified checks, or `pragma Assume` statements. This
slice changes the non-SPARK server adapter, its instantiations, corpus,
registry, and documentation; none of
the nine `tools/prove.sh` manifest units changed after that campaign, so a
redundant formal rerun was not performed.
