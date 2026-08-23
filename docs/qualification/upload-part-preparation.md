# UploadPart closure preparation

This is a preparatory contract inventory, not an implementation or an S3
coverage claim. It freezes the exact modeled surface that a later UploadPart
slice must close after the active PutObject work has established the shared
streaming, checksum-trailer, and HTTP/2/HTTP/3 behavior.

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
pinned SDK model differ. The eventual implementation must document any narrow
version-pinned oracle divergence rather than weakening the decoder.

## Current boundary

The low-level client already projects the non-body request members and decodes
the modeled response headers. The existing authenticated server streams the
part body and validates a useful subset of checksum headers. That is why the
operation remains `partial`, not `missing`.

The remaining closure is substantive:

- the server must deliberately handle Content-MD5, expected owner, requester
  acknowledgement, and the SSE-C triplet instead of silently ignoring them;
- checksum selection must share PutObject's final header/trailer precedence,
  physical-trailer validation, and atomic no-publication-on-mismatch rule;
- checksum and encryption choices must be checked against the exact multipart
  initiation state at the part-publication boundary;
- the client must distinguish absent, present-empty, duplicate, malformed, and
  overlong modeled response headers and require an exactly empty success body;
- a convenience API must retain source ownership and whole-operation deadline
  semantics without detached work or unsafe automatic replay; and
- native and lightweight signed application/socket tests plus the repeated
  permissive-server matrix must qualify identical bytes and state transitions.

The design intentionally does not claim SSE-C, Requester Pays, directory
buckets, access points, or object versioning. Unsupported policy must be
authenticated, strictly validated, and explicitly rejected. It must never be
accepted and discarded.

## Machine-checked artifacts

`tests/corpora/upload-part/members.tsv` records every modeled member, its wire
position, the current boundary, the required closure, and the vectors that
gate it. `tests/corpora/upload-part/vectors.tsv` records adversarial request,
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

It needs only the Python standard library and does not build the Ada project,
invoke a shared test runner, alter the 116-operation ledger, or run GNATprove.

## Integration boundary

After PutObject freezes, the implementation owner should re-audit its final
checksum and streaming APIs before translating these vectors into executable
application/socket and six-server lanes. At that point the owner must add the
ordinary project gates and independent review cycle. This preparation alone
must not promote any UploadPart ledger cell.
