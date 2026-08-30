# CompleteMultipartUpload qualification

This record defines the focused qualification boundary for the authenticated
general-purpose, path-style CompleteMultipartUpload server route and typed
composable client. A qualification claim requires the maintained focused lane
to finish. The boundary does not extend the directory-bucket, access-point,
Outposts, Requester Pays, or server-side-encryption capability set.

## Composable client boundary

`Flyology.Object_Storage.Client.Transfers.Complete_Multipart_Upload` serializes
the part manifest exactly once during bounded initiation. Its limited operation
owns the XML and exposes it as a non-rewindable request-body source while one
hidden HTTP child is driven on the caller's completion-set owner stack. It has
no helper task, retained borrowed input, automatic retry, or second protocol
engine. The typed synchronous transfer overload is a literal wait on the same
operation.

Only a complete validated successful response reports
`Multipart_Completed`. Definite pre-admission failure reports
`Definitely_Not_Completed`, with a separate cancellation spelling. Every
complete S3 rejection and every failure after possible admission reports
`Completion_Outcome_Unknown`; this deliberately includes error XML embedded
in HTTP 200. The caller reconciles the destination object and exact upload
read-only before choosing retry or abort. The socket corpus requires both a
generation-bound whole-object read and exact-upload ListParts rejection after
a lost completion response. A later abort cannot roll back an already
published object.

The 46-row compile-independent certainty corpus covers the complete modeled
success and rejection set plus every HTTP terminal failure under each admission
state. The Ada normalization corpus applies the same mapping. Native and
lightweight socket tests cover success, restart of the same operation,
pre-admission cancellation, admitted cancellation through transport drain,
typed Finish, and restart of the same consumed operation. A server that accepts
completion but loses the response requires a subsequent whole Get and exact
upload ListParts reconciliation without replaying completion. The six-server
implementation matrix
drives this typed synchronous path for Flyology memory, files, and SQLite,
RustFS, SeaweedFS, and supplemental MinIO.

## Admission and state boundary

SigV4 authentication completes before any signed request control is evaluated.
The route then validates physical singleton headers, expected owner, payer,
destination entity-tag conditions, expected size, checksum algorithm, checksum
type, and checksum value before looking up the upload. Consequently, a missing
upload does not mask a malformed request-intrinsic control.

Unknown `x-amz-checksum-*` names are rejected instead of being silently
ignored. A checksum algorithm or type which is well formed but disagrees with
the immutable initiation policy is rejected after the upload snapshot is read.
The completed-part manifest must agree with that snapshot, and the backend
publishes the destination body, metadata, tags, version identity, and checksum
atomically. Failed admission, part validation, destination conditions, size,
or checksum checks leave both the active upload and prior destination object
unchanged.

The XML manifest is buffered under the existing 2 MiB project-policy ceiling.
The signed corpus admits a syntactically valid document of exactly that size
and rejects the same document with one additional byte as `EntityTooLarge`.
Changing this ceiling changes accepted wire inputs and requires compatibility
review.

## Qualified controls and exclusions

The direct application corpus covers:

- matching, mismatched, empty, duplicate, and combined expected-owner inputs;
- invalid, empty, duplicate, and explicitly unsupported Requester Pays inputs;
- malformed, empty, mixed-wildcard, satisfied, and failed destination
  `If-Match`/`If-None-Match` predicates;
- malformed, mismatched, and successful expected object sizes;
- unknown, malformed, mismatched, and successful checksum algorithms, types,
  value headers, and digests;
- incomplete and complete SSE-C groups on an upload which did not initiate
  SSE-C, both rejected before completion;
- corrupted-signature precedence over all signed controls;
- request-intrinsic validation before `NoSuchUpload`; and
- exact-limit and one-byte-over manifests, followed by successful completion
  of the same active upload to prove rejected requests did not consume it.

Valid Requester Pays and encryption requests remain explicit typed capability
exclusions. This route does not claim trailer-based completion manifests or a
directory-bucket session contract. PutObject and UploadPart are covered for
their authenticated general-purpose profiles; inner SigV4 `aws-chunked`
framing, advanced policy controls, and HTTP/2 or HTTP/3 server qualification
remain separate capabilities.

For an enabled versioned bucket, successful completion emits the exact opaque
`x-amz-version-id` returned by the same backend publication. The durable files
and SQLite black-box lanes keep an initiation and signed part live across a
server restart, complete afterward, and require that identity in a
generation-bound whole GET before deleting it.

## Gate

The maintained focused lane requires the independent preparation verifier,
the composable certainty fixture verifier and its negative self-tests, the
warning-strict tests build, the signed socket corpus, the 116-operation
coverage verifier, fresh public API documentation, the pinned-model repository
gate, and a clean diff check. The lane is not successful unless every command
exits cleanly and the final qualification sentinel is emitted.

The focused lane does not run the provider matrix, full repository suite, or a
formal proof tool. Evidence from those separate campaigns is not attributed to
CompleteMultipartUpload qualification.
