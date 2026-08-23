# CreateMultipartUpload client qualification

This record freezes the pinned model inventory and the qualified synchronous
client boundary. Backend initiation and the authenticated server route retain
their narrower policy support; server coverage therefore remains partial.

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

## Qualified client and ambiguity boundary

`Client.Low_Level.Create_Multipart_Parameters` exposes every non-resource
member in the pinned request shape and projects all 31 inputs through the
generated model. It additionally rejects relationally invalid ACL/grant,
SSE-C, KMS, checksum, Object Lock, expiry, payer, and case-colliding metadata
combinations before HTTP admission. SSE-C key MD5 is recomputed and SSE-C is
rejected over plaintext HTTP.

`Client.Low_Level.Create_Multipart_Result` preserves all 14 modeled output
members, while the XML codec remains limited to its three body fields.
Execution requires physical singleton response headers, rejects
present-empty, duplicate, over-8-KiB, and control-bearing values, validates
abort-date/rule, encryption, boolean, payer, and checksum relations, and binds
the XML bucket and key exactly to the prepared request. Optional service
confirmation headers may be absent; when present they must be coherent with
the explicitly requested policy. Error request identifiers are bounded by the
same 8-KiB limit.

`Client.Transfers.Create_Multipart_Upload` is the public synchronous wrapper.
It prepares and executes exactly once without a helper task or automatic
replay. Credentials and sensitive SSE-C material are retained only by the
bounded synchronous request state and are not durably stored by this layer.

An accepted initiation followed by a lost response is ambiguous: the service
may have created an upload whose identifier the caller did not receive.
Transparent retry can create a second active upload. `Invalid_Request` from the
wrapper is pre-admission and definite non-creation. Any exception after the
blocking execute call is entered, including timeout, cancellation, transport,
or invalid-response failure, is conservatively ambiguous. Callers reconcile
and clean up through ListMultipartUploads; the wrapper never auto-retries.

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

The direct corpus signs every modeled request policy class and rejects invalid
checksum, ACL/grant, SSE-C, KMS, Object Lock, expiry, and duplicate-metadata
relations. It preserves both KMS and SSE-C response groups, admits exact
8-KiB response-header and error-ID boundaries, and rejects one-past and control
values. Fragmented raw-loopback responses run through native and Flyology
lightweight clients, use the public wrapper, bind bucket/key and explicit
policy, and reject duplicate and present-empty physical headers. A dropped
successful initiation is followed by one read-only ListMultipartUploads
reconciliation request; the scripted server rejects any automatic POST replay.
This evidence promotes only the client cell; advanced backend and server policy
enforcement remains separately gated and partial.

## Frozen gate evidence

The qualified source passed the root gate with 37/37 AUnit tests, the 88-case
files crash matrix, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC
linearization oracle, the server application corpus, and three repetitions of
the native/lightweight socket corpus. The SQLite gate passed. The six-server
implementation matrix passed all 18 lanes and repetitions, with pinned
external-service exclusions reported rather than accepted as relaxed client
behavior.

The serialized proof campaign started at 2026-08-23T15:19:08Z with FSF
GNATprove 16.1.0. `./tools/prove.sh` used output headers and warnings as errors
and proved 936/936 checks across all nine manifest units: 180 flow checks and
756 prover checks, with a maximum of 663 steps. The report contains zero
warnings, unproved or justified checks, and `pragma Assume` statements;
the source contains no `pragma Assume`, `pragma Suppress`, `False_Positive`, or
`SPARK_Mode => Off`. The post-run host process audit was clean.
