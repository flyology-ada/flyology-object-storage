# ListParts qualification

This record freezes the pinned model inventory and qualifies the composable
and synchronous clients plus the authenticated general-purpose path-style
server. Backend, client, server, and corpus coverage are complete within that
scope. Configured Requester Pays accounting, SSE-C multipart state, and
directory buckets remain explicit capability exclusions.

## Pinned authority

The machine-checked inventory is tied to the immutable botocore S3 model used
by this repository:

- revision `36c34f15391da01cd717c73c0fffa747c9889768`;
- service model SHA-256
  `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`;
- request shape 401, `ListPartsRequest`, with 10 members; and
- output shape 400, `ListPartsOutput`, with 16 top-level members.

The current [AWS ListParts API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListParts.html)
and [multipart upload overview](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
were reviewed on 2026-08-22. The pinned generated model is authoritative for
this crate when current AWS prose and the pinned SDK revision differ.

## Pagination contract

ListParts is not a snapshot spanning multiple HTTP requests. Each backend call
must produce one immutable page, while a caller continues by copying the prior
response's `NextPartNumberMarker` into the next request's
`PartNumberMarker`.

For every page:

- the echoed marker and maximum must match the admitted request;
- returned part numbers are unique, strictly increasing, and greater than the
  request marker;
- the count does not exceed `MaxParts`;
- a truncated page is nonempty and its next marker equals its final part;
- an untruncated page omits the next marker; and
- `MaxParts = 0` yields an empty untruncated page under the pinned project
  contract.

Concurrent changes between requests may alter later pages. The high-level
client must remain monotonic and must not promise a cross-request snapshot,
repeat a part at or below the supplied marker, or loop on a stale next marker.

## Qualified client boundary

The low-level client projects all modeled request positions and parses all
top-level output positions. `Client.Scoped.List_Parts` is the caller-owned,
completion-set-aware operation; the typed `Client.Transfers.List_Parts_Page`
overload is a literal wait on that same state machine. The established
low-level-outcome overload remains source compatible. The prepared request
retains bucket, key, upload ID, marker, and maximum, and complete-response
decoding rejects any response whose echoed values do not match exactly. SSE-C
key MD5 is recomputed before admission. The client does not promise a snapshot
across separate calls.

The operation retains response bytes only up to the existing S3 XML document
limit, owns no borrowed request input, creates no helper task, and contains one
HTTP child. Typed Finish distinguishes a modeled S3 response from a bounded
exchange failure and preserves terminal admission certainty for diagnostics.
As a read-only request, ListParts has no publication disposition. A complete
service rejection remains a modeled response; incomplete, malformed,
oversized, cancelled, timed-out, connection, or transport outcomes remain
typed exchange failures.

All modeled response headers are physical singletons. Present-empty,
duplicate, over-8-KiB, control-bearing, invalid requester-pays, malformed abort
date, and unpaired abort date/rule responses are rejected. Each listed part
has at most one canonical checksum and it must match the top-level checksum
algorithm. The server authenticates before semantics, enforces the expected
owner, validates the requester-pays token, and rejects duplicate, empty,
malformed, and overlong controls before multipart state is observed. It
validates a complete SSE-C triplet, HTTPS transport, and the key/digest
relationship without retaining or logging the key. A valid `requester` token
or valid HTTPS SSE-C group receives authenticated `NotImplemented` because the
corresponding bucket and initiation policies are unavailable; unsupported
security controls are never silently ignored.

Successful response parsing must preserve absent optional members while
rejecting present-empty or duplicate singleton headers and XML fields. It must
bound total document bytes, XML depth, element and text counts, flattened part
count, identity text, timestamps, ETags, 64-bit sizes, and every checksum.
Forward-compatible unknown XML may be ignored only at positions deliberately
allowed by the bounded parser; misplaced modeled fields and entity expansion
remain invalid.

RustFS 1.0.0-rc.3 and SeaweedFS 4.43 retain their measured,
version-pinned omission of multipart checksum algorithm/type and per-part
checksum values. MinIO remains supplemental. The decoder must preserve those
exact absences without weakening Flyology's complete checksum profile or
accepting any new divergence.

RustFS, supplemental MinIO, and the Flyology memory, files, and SQLite lanes
pass the real two-part, two-page continuation oracle. Pinned SeaweedFS 4.43
repeats a part at or below
the supplied `PartNumberMarker` on the second page; that lane is explicitly
excluded and the strict decoder continues to reject the repeated page.

## Isolated verification

`tests/corpora/list-parts/members.tsv` maps every request/output member to its
wire position, current boundary, required closure, and adversarial vectors.
`tests/corpora/list-parts/vectors.tsv` defines request, response, pagination,
backend lifecycle, external oracle, and transport designs.

Run:

```sh
python3 tools/verify-list-parts-preparation.py
```

The standard-library-only verifier checks the pinned model revision/hash,
exact shape counts, ordered member names, generated wire locations, unique
canonical vector identifiers, and reciprocal member/vector references. It
does not build Ada, invoke shared runners, update a manifest or ledger, or run
GNATprove.

The ordinary gate checks direct decoder boundaries, response/failure
normalization, and checksum conflicts. The fragmented raw-loopback corpus runs
through both native and Flyology lightweight clients, covers pre-admission
cancellation and direct operation restart over two continuation pages,
independently mutates every echoed request field, and tests duplicate and
present-empty singleton headers. The signed server corpus
adds exact-limit/one-past owner controls, owner/payer duplicates, malformed and
mismatched SSE-C material, plaintext rejection, valid unsupported HTTPS, and
bad-signature precedence. The implementation corpus uses the typed
composable-backed page API and exercises real service-returned continuation
markers. Ledger promotion
records the qualified client and general-purpose server boundaries.

## Frozen gate evidence

The qualified source passed the root gate with 41/41 AUnit tests, the 126-case
files crash matrix, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC
linearization oracle, the server application corpus, and three repetitions of
the native/lightweight socket corpus. The SQLite gate passed. The six-server
implementation matrix passed all 18 lanes and repetitions, with the exact
SeaweedFS pagination exclusion above reported rather than accepted.

The serialized proof campaign on 2026-08-24 used FSF GNATprove 16.1.0.
`./tools/prove.sh` used output headers and warnings as errors and proved
936/936 checks across all nine manifest units: 180 flow checks and 756 prover
checks, with a maximum of 663 steps. The report contains zero warnings,
unproved or justified checks, and `pragma Assume` statements; the source
contains no `pragma Assume`, `pragma Suppress`, `False_Positive`, or
`SPARK_Mode => Off`. Exact pre/post-run host process audits were clean and the
exclusive prover/model-checker lane was released after the campaign.
