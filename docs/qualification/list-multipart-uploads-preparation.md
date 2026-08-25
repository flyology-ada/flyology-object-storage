# ListMultipartUploads qualification

This record freezes the pinned model inventory and qualifies the composable
and synchronous clients plus the authenticated general-purpose path-style
server. Backend, client, server, and corpus coverage are complete within that
scope. Directory buckets and configured Requester Pays accounting remain
explicit capability exclusions.

## Pinned authority

The machine-checked inventory is tied to the immutable botocore S3 model used
by this repository:

- revision `36c34f15391da01cd717c73c0fffa747c9889768`;
- service model SHA-256
  `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`;
- request shape 391, `ListMultipartUploadsRequest`, with 9 members; and
- output shape 390, `ListMultipartUploadsOutput`, with 13 members.

The current
[AWS ListMultipartUploads API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListMultipartUploads.html)
and [multipart upload overview](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
were reviewed on 2026-08-22. The pinned generated model remains authoritative
for this crate when current prose and the pinned SDK revision differ.

## Paired continuation

For general-purpose buckets, `KeyMarker` and `UploadIdMarker` form one cursor.
The caller copies both `NextKeyMarker` and `NextUploadIdMarker` from a truncated
response into the next request. An upload-ID marker without a key marker is
preserved on the wire but ignored semantically. A key marker without an upload
ID excludes uploads whose key equals that marker.

AWS separately describes response order as ascending key and, for a shared
key, ascending initiation time. Its marker rule permits same-key uploads only
when their upload IDs compare after the supplied upload-ID marker. The later
implementation and oracle must exercise inverse upload-ID/initiation-time data
rather than assume those orders coincide. A service-produced marker pair must
always resume without skipping, repeating, or looping, with a deterministic
upload-ID tie break for equal initiation times.

Each backend page is one immutable active-upload snapshot. No snapshot spans
multiple HTTP requests: concurrent create, abort, or completion may change a
later page. The high-level pager must preserve prefix, delimiter, encoding, and
maximum scope and remain strictly advancing despite those changes.

## Grouping and encoding

`MaxUploads` is a canonical integer from 1 through 1,000. The bounded page
counts visible upload and common-prefix candidates together. Prefix filtering
happens before delimiter grouping. Each distinct substring through the first
delimiter occurrence after the prefix appears once in `CommonPrefixes`, and a
grouped upload is not also returned as an upload.

With `encoding-type=url`, the response percent-encodes UTF-8 bytes in
Delimiter, KeyMarker, Prefix, NextKeyMarker, each Upload Key, and each
CommonPrefix. Upload-ID marker values remain opaque and are not key-encoded.
Request percent escapes are strict and `+` remains a literal plus.

Directory buckets have different ordering and no upload-ID marker. They remain
outside this general-purpose path-style claim and must be rejected explicitly
until their endpoint and session policy exists.

## Qualified client and oracle boundary

The low-level client projects all nine modeled request positions and parses all
13 top-level output positions. `Client.Transfers.List_Multipart_Uploads_Page` is the
caller-owned completion-set-aware operation; the typed
`Client.Transfers.List_Multipart_Uploads_Page` overload is a literal wait on
that same state machine. The established low-level-outcome overload remains
source compatible. Prepared requests retain bucket, both markers, prefix,
delimiter, encoding mode, maximum, and Requester Pays admission; complete
response decoding binds every echoed field and any charged response to that
exact scope, including URL-encoded key fields while leaving upload-ID markers
opaque. Callers advance the two returned markers as one cursor, and separate
calls do not share a snapshot.

The operation retains response bytes only up to the existing S3 XML document
limit, owns no borrowed request input, creates no helper task, and contains one
HTTP child. Typed Finish distinguishes a modeled S3 response from a bounded
exchange failure and preserves terminal admission certainty for diagnostics.
As a read-only request, ListMultipartUploads has no publication disposition.

The sole modeled response header is a physical singleton. Present-empty,
duplicate, over-8-KiB, control-bearing, or invalid requester-pays values are
rejected. The codec enforces combined upload/common-prefix bounds, complete and
unique uploads, canonical initiation timestamps, checksum type/algorithm
coherence, unique grouping prefixes, grouped-upload exclusion, final/truncated
marker consistency, and advancing general-purpose cursor pairs. The server
enforces a matching expected owner, rejects duplicate controls before listing,
accepts only the modeled `requester` billing token, and returns authenticated
`NotImplemented` for that valid token because Requester Pays bucket policy is
not configured. It does not silently accept unsupported billing.

The client rejects duplicate modeled singleton XML fields and headers,
distinguishes required nonempty identities from permitted absent or empty
default markers, validates complete upload records and optional identity,
storage-class, and checksum fields, and enforces document/depth/element/text
and combined-page bounds. Unknown extensions are ignored only at deliberately
bounded forward-compatible positions; misplaced modeled fields and entity
expansion remain invalid.

RustFS 1.0.0-rc.3 is a positive oracle with its exact model-optional
StorageClass omission. Supplemental MinIO and Flyology memory, files, and
SQLite complete the five positive lanes. SeaweedFS 4.43 remains explicitly
excluded from the positive operation oracle: its measured fresh exact-limit
page says it is truncated but omits `NextKeyMarker` and initiation metadata.
That divergence must stay pinned rather than weakening continuation or upload
completeness validation.

## Isolated verification

`tests/corpora/list-multipart-uploads/members.tsv` maps every modeled request
and output member to its generated wire location, current boundary, required
closure, and strict vectors.
`tests/corpora/list-multipart-uploads/vectors.tsv` defines paired pagination,
scope, grouping, encoding, XML/header, backend lifecycle, fragmentation, and
external-server designs.

Run:

```sh
python3 tools/verify-list-multipart-uploads-preparation.py
```

The standard-library-only verifier checks the pinned model revision/hash,
exact 9/13 counts, ordered names, generated wire locations, canonical unique
vector identifiers, and reciprocal member/vector references. It does not
build Ada, invoke shared runners, edit a manifest or ledger, or run GNATprove.

The fragmented raw-loopback corpus runs through both native and Flyology
lightweight clients, covers pre-admission cancellation and direct operation
restart, independently mutates all seven echoed scope/cursor fields, rejects a
charged response without an admitted payer, exercises duplicate and
present-empty headers, and follows a real two-page paired cursor. Direct
normalization checks cover modeled service responses and every HTTP terminal
failure across all admission states. The signed server corpus additionally
requires matching
owner success, mismatched-owner `AccessDenied`, duplicate-owner rejection, and
valid, invalid, and duplicate requester-pays dispositions. The repeated
implementation matrix calls the public page API against RustFS, supplemental
MinIO, and Flyology memory/files/SQLite; the exact SeaweedFS exclusion above
remains pinned. Ledger promotion records the qualified client and
general-purpose server boundaries.

## Frozen gate evidence

The qualified source passed the root gate with 41/41 AUnit tests, the 126-case
files crash matrix, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC
linearization oracle, the server application corpus, and three repetitions of
the native/lightweight socket corpus. The SQLite gate passed. The six-server
implementation matrix passed all 18 lanes and repetitions, with the exact
SeaweedFS exclusions above reported rather than accepted.

The serialized proof campaign on 2026-08-24 used FSF GNATprove 16.1.0.
`./tools/prove.sh` used output headers and warnings as errors and proved
936/936 checks across all nine manifest units: 180 flow checks and 756 prover
checks, with a maximum of 663 steps. The report contains zero warnings,
unproved or justified checks, and `pragma Assume` statements; the source
contains no `pragma Assume`, `pragma Suppress`, `False_Positive`, or
`SPARK_Mode => Off`. Exact pre/post-run host process audits were clean and the
exclusive prover/model-checker lane was released after the campaign.
