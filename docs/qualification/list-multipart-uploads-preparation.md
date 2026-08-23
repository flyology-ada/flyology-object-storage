# ListMultipartUploads closure preparation

This inventory prepares a later ListMultipartUploads completion slice. It is
not an implementation, qualification result, or coverage-ledger claim.

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

## Strict response and oracle boundary

The low-level client already projects all nine modeled request positions and
parses all 13 top-level output positions. Backends already form bounded atomic
pages. The ledger remains partial because a high-level paired-cursor pager is
absent and the server does not yet implement all owner and billing policy.

The future client must reject duplicate modeled singleton XML fields and
headers, distinguish required nonempty identities from permitted absent or
empty default markers, validate complete upload records and optional identity,
storage-class, and checksum fields, and enforce document/depth/element/text and
combined-page bounds. Unknown extensions may be ignored only at deliberately
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

After active PutObject work freezes, the implementation owner must translate
these designs into ordinary backend, native/lightweight application/socket,
reopen/concurrency, and repeated external-server gates, followed by an
independent review cycle. This preparation alone cannot promote coverage.
