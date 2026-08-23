# UploadPart qualification

This record ties the covered UploadPart backend, client, and corpus cells to
executable evidence. The authenticated Flyology server remains `partial`
because it validates and explicitly rejects unsupported SSE-C and Requester
Pays controls and does not accept `aws-chunked` request bodies. Those exclusions
are not silently ignored and are not counted as positive support.

## Authority and scope

The inventory is tied to the repository's immutable botocore S3 model:

- revision `36c34f15391da01cd717c73c0fffa747c9889768`;
- service model SHA-256
  `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`;
- input shape 708, `UploadPartRequest`, with 23 members; and
- output shape 707, `UploadPartOutput`, with 17 members.

Current AWS primary references were reviewed on 2026-08-22:

- [UploadPart API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html)
- [CreateMultipartUpload API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateMultipartUpload.html)
- [ListParts API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListParts.html)
- [Multipart checksum guidance](https://docs.aws.amazon.com/AmazonS3/latest/userguide/checking-object-integrity-upload.html)

The pinned generated model remains authoritative when current prose and the
pinned SDK model differ. Narrow version-pinned oracle divergences are
documented rather than used to weaken the decoder.

## Qualified synchronous client

`Flyology.Object_Storage.Client.Transfers.Upload_Part` is the direct synchronous
entry point. It accepts the complete 23-member typed request policy, borrows a
forward-only body source only for the duration of the call, and returns the
complete 17-member typed response result or a structured S3 rejection. A
rewindable source and every invalid modeled request combination are rejected
before HTTP admission. The operation does not create helper tasks, retain the
source, or transparently retry.

The client qualifies:

- all ten concrete checksum headers, exact canonical Base64 widths, selector
  precedence, Content-MD5, expected owner, requester, and secure SSE-C groups;
- a complete request-target bound, including the composed upload-ID query;
- exactly one required opaque ETag and singleton handling for all 17 response
  headers, with absent/present-empty/duplicate/overlong/control-bearing cases;
- exact empty success bodies, bounded structured errors, and request-bound
  checksum response algorithm/value equality; and
- the same one-shot state machine from direct calls and `Upload_File` multipart
  ranges, with one absolute synchronous timeout budget.

`Invalid_Request` from the synchronous wrapper is pre-admission. Every other
exception is conservatively publication-ambiguous, including
`Invalid_Response` raised while validating a reply after S3 may have accepted
the part. The caller reconciles the exact upload ID and part number through
ListParts before retrying or completing; the library performs no automatic
retry. The lost-response socket lane accepts one PUT, drops the response,
requires ListParts next, completes from the reconciled tuple, and verifies the
exact bytes, ETag, and SHA-256 with a generation-bound whole GET.

## Backend and server boundary

Memory, pure-files, and SQLite share the same generation-bound multipart
conformance suite. They enforce the 5 GiB part ceiling, atomic whole-part
replacement, checksum metadata, prior-part preservation on validation failure,
and reopen/crash behavior appropriate to each backend.

The authenticated path-style server validates Content-MD5, all ten checksum
headers, physical checksum trailers, expected owner, payer, and SSE-C request
groups before publication. It checks checksum selection against initiation
state at the atomic publication boundary. Unsupported policy is authenticated,
strictly validated, and returned as explicit `NotImplemented`; `aws-chunked`
content encoding is likewise excluded. The server ledger cell therefore
remains `partial`.

The design intentionally does not claim SSE-C, Requester Pays, directory
buckets, access points, or object versioning. Unsupported policy must be
authenticated, strictly validated, and explicitly rejected. It must never be
accepted and discarded.

For the unsupported SSE-C boundary, the server validates the complete triplet,
canonical key/digest encodings, key MD5, and HTTPS before returning an
authenticated `NotImplemented` response without reading the part source. It
does not log, persist, or deliberately retain the key beyond request cleanup.
The HTTP exchange retains the encoded header until cleanup and the generic MD5
implementation may create transient request-stack copies that are not
guaranteed erased. Guaranteed end-to-end zeroization and persisted initiation
encryption state are prerequisites for any later positive SSE-C support.

The authenticated path-style server is a single-tenant application profile.
Its credential provider reports one stable tenant/account-owner principal for
every access key accepted by the application instance and its bound Store.
`ExpectedBucketOwner` is compared exactly with that principal. A provider that
returns different principals for credentials admitted to the same Store is
outside this profile; it must instead bind a separate application/store per
tenant or provide a future bucket-owner capability.

## Machine-checked artifacts

`tests/corpora/upload-part/members.tsv` records every modeled member, its wire
position, qualified boundary, behavioral contract, and the vectors that gate
it. `tests/corpora/upload-part/vectors.tsv` records adversarial request,
response, lifecycle, oracle, and benchmark designs. The verifier checks:

- exact 23/17 counts and ordinal member names against generated shapes 708/707;
- the immutable model revision and SHA in `coverage/corpora.lock.toml`;
- canonical unique vector identifiers;
- complete reciprocal member-to-vector references; and
- absence of empty or surplus TSV fields.

Run the isolated self-test with:

```sh
python3 tools/verify-upload-part-preparation.py
```

The deterministic qualification gates are:

```sh
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
./tests/scripts/test-s3-matrix.sh
```

The root gate runs 37 AUnit cases, the signed server application corpus, and
the native/lightweight raw socket corpus three times. The backend gate covers
SQLite wrapper, catalog, and backend behavior. The matrix repeats native and
lightweight signed client lifecycles three times against pinned RustFS,
SeaweedFS, supplemental MinIO, and Flyology memory, files, and SQLite, with an
independent digest-pinned s5cmd byte and deletion oracle.

The isolated verifier needs only the Python standard library; it does not build
the Ada project or run GNATprove. Proof evidence is recorded separately after
the deterministic source freeze and serialized prover-lane audit.
