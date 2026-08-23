# ListParts closure preparation

This inventory prepares a later ListParts completion slice. It is not an
implementation, qualification result, or coverage-ledger claim.

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

## Deliberate closure boundary

The low-level client already projects all modeled request positions and parses
all top-level output positions. The backend has bounded marker pagination and
the existing implementation oracle covers ordinary and checksummed uploads.
The ledger remains partial because a high-level pager is absent and the server
route does not yet deliberately enforce expected owner, requester-pays, or
SSE-C controls.

The future slice must authenticate before semantics; validate duplicate,
empty, malformed, and overlong query/header values; bind SSE-C to the exact
initiation state; and fail explicitly when billing or encryption policy is
unsupported. It must not silently ignore modeled security controls.

Successful response parsing must preserve absent optional members while
rejecting present-empty or duplicate singleton headers and XML fields. It must
bound total document bytes, XML depth, element and text counts, flattened part
count, identity text, timestamps, ETags, 64-bit sizes, and every checksum.
Forward-compatible unknown XML may be ignored only at positions deliberately
allowed by the bounded parser; misplaced modeled fields and entity expansion
remain invalid.

RustFS 1.0.0-rc.3 and SeaweedFS 4.43 are expected to retain their measured,
version-pinned omission of multipart checksum algorithm/type and per-part
checksum values. MinIO remains supplemental. The decoder must preserve those
exact absences without weakening Flyology's complete checksum profile or
accepting any new divergence.

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

After the active PutObject work freezes, the implementation owner must
re-audit the resulting shared HTTP and policy contracts, translate these
designs into normal native/lightweight application/socket and repeated
six-server gates, and complete an independent review cycle before any ledger
promotion.
