# CreateMultipartUpload closure preparation

This inventory prepares a later CreateMultipartUpload completion slice. It is
not an implementation, qualification result, or coverage-ledger claim.

## Pinned authority

The machine-checked inventory is tied to the immutable botocore S3 model used
by this repository:

- revision `36c34f15391da01cd717c73c0fffa747c9889768`;
- service model SHA-256
  `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`;
- request shape 135, `CreateMultipartUploadRequest`, with 31 members; and
- output shape 134, `CreateMultipartUploadOutput`, with 14 members.

The current
[AWS CreateMultipartUpload API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateMultipartUpload.html),
[UploadPart API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html),
[CompleteMultipartUpload API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CompleteMultipartUpload.html),
and [multipart checksum guidance](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html)
were reviewed on 2026-08-22. The pinned generated model remains authoritative
for this crate when current prose and the pinned SDK revision differ.

## Durable initiation policy

CreateMultipartUpload does more than allocate an upload identifier. Every
accepted object policy is one immutable initiation snapshot. Memory, files,
and SQLite must atomically publish or reject that whole snapshot and preserve
it across reopen and supported schema migrations.

The snapshot includes, where supported:

- cache, content, expiry, redirect, and user metadata;
- the parsed object tag set;
- checksum algorithm and checksum type, including the documented server
  default when the request omits them;
- ACL or explicit grants as one coherent authorization policy;
- storage class;
- server-managed, KMS, or SSE-C encryption selection;
- Object Lock retention and legal-hold policy; and
- the authenticated owner and billing disposition needed for later checks.

SSE-C plaintext key material must not be logged or durably stored. The
initiation state may retain only bounded algorithm and verification material
needed to require the same key on UploadPart and CompleteMultipartUpload.

UploadPart must atomically recheck initiation checksum and encryption policy
before publishing each complete part. CompleteMultipartUpload must publish the
final body, metadata, tags, ACL, storage class, encryption, Object Lock, and
checksum policy together. A failed part or completion must not partially apply
any accepted initiation field, and a prior destination object must remain
unchanged.

Unsupported ACL, billing, encryption, Object Lock, directory-bucket, or access
point policy must be authenticated, strictly validated, and explicitly
rejected before upload creation. A successful initiation that silently drops
one of these controls is not permitted.

## Client and ambiguity boundary

The current typed client exposes only content type plus checksum algorithm and
type, while the generic projector can represent the remaining modeled fields.
The current typed success decoder parses the XML bucket, key, and upload ID but
does not expose all 11 modeled success headers. The future client must preserve
absent optional headers separately from present-empty values, reject duplicate
singletons, validate encryption/checksum relations, and compare response
identity with the prepared request.

An accepted initiation followed by a lost response is ambiguous: the service
may have created an upload whose identifier the caller did not receive.
Transparent retry can create a second active upload. The future client must not
replay this operation after possible admission and must document reconciliation
and cleanup through ListMultipartUploads rather than claim definite absence.

## Isolated artifacts

`tests/corpora/create-multipart-upload/members.tsv` maps every request and
output member to its generated wire location, current boundary, required
closure, and strict vectors.
`tests/corpora/create-multipart-upload/vectors.tsv` defines target, header-map,
ACL, metadata, tagging, checksum, encryption, Object Lock, owner/payer,
response, durability, inheritance, ambiguity, and external-server designs.

Run:

```sh
python3 tools/verify-create-multipart-upload-preparation.py
```

The standard-library-only verifier checks the pinned model revision/hash,
exact 31/14 counts, ordered names, generated wire locations, canonical unique
vector identifiers, and reciprocal member/vector references. It does not
build Ada, invoke shared runners, edit a manifest or ledger, or run GNATprove.

After active PutObject work freezes, the implementation owner must re-audit
its final metadata, tagging, checksum, encryption, and Object Lock policy APIs
before translating these vectors into ordinary backend, native/lightweight
application/socket, crash/reopen, and repeated six-server gates. No ledger cell
may be promoted from this preparation alone.
