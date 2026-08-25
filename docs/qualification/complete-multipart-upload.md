# CompleteMultipartUpload qualification

This record qualifies both the authenticated general-purpose, path-style
CompleteMultipartUpload server route and the typed composable client. It does
not extend the directory-bucket, access-point, Outposts, Requester Pays, or
server-side-encryption capability set.

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
read-only before choosing retry or abort. A later abort cannot roll back an
already published object.

The 46-row compile-independent certainty corpus covers the complete modeled
success and rejection set plus every HTTP terminal failure under each admission
state. The Ada normalization corpus applies the same mapping. Native and
lightweight socket tests cover success, restart of the same operation,
pre-admission cancellation, and a server that accepts completion but loses the
response; a subsequent whole Get must prove the exact bytes, checksum, and
entity tag without replaying completion. The six-server implementation matrix
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

The focused executable is:

```sh
cd tests
alr -n build
./bin/s3_server_application_corpus
```

Repository qualification additionally requires the root and SQLite test
scripts, the coverage verifier, GNATdoc with the documented Flyology root
project exclusion, and a clean diff check. The change is confined to the
authenticated server adapter and its corpus; no SPARK-enabled backend or wire
codec unit changes, so it does not expand the proof boundary.

On the final reviewed tree, the root gate passed 41/41 AUnit tests, the 126-case
files crash matrix, 320 checksum vectors, 210 chunk boundaries, the 64 GiB CRC
linearization oracle, the signed application corpus, and three
native/lightweight socket repetitions. The fixture verifier and its mutation
self-tests passed. The full implementation matrix passed three repetitions
against RustFS, SeaweedFS, supplemental MinIO, and Flyology memory, files, and
SQLite; durable files/SQLite restart lanes also passed. GNATdoc produced a
nonempty API index containing the new composable operation. Its warnings are
confined to upstream and pre-existing undocumented entities; the maintained
fail-closed build reported no internal error.

The serialized warning-strict GNATprove gate proved 936/936 checks. Its report
contained zero warnings, unproved or justified checks, and `pragma Assume`
statements; the source contained no proof suppression or SPARK exclusion. The
post-run host audit was clean for GNATprove, Why3, SMT solvers, TLC, and TLAPS.
