# AbortMultipartUpload qualification

This record qualifies the authenticated path-style AbortMultipartUpload route
and the typed composable client. It does not extend directory-bucket,
access-point, Outposts, or Requester Pays capabilities.

## Composable client boundary

`Flyology.Object_Storage.Client.Transfers.Abort_Multipart_Upload` owns a
non-rewindable known-empty request source and one hidden HTTP child driven on
the caller's completion-set owner stack. It has no helper task, retained
borrowed input, automatic retry, or second protocol engine. The typed
synchronous transfer overload is a literal wait on the same operation. The
established low-level outcome overload remains source compatible and also uses
a non-replayable empty source.

Only a complete validated 204 response reports `Multipart_Aborted`. Definite
pre-admission failure reports `Definitely_Not_Aborted`, with a separate
cancellation spelling. Every complete S3 rejection and every failure after
possible admission reports `Abort_Outcome_Unknown`. This includes
`NoSuchUpload`, because the upload may already have been aborted, completed, or
changed concurrently. The caller reconciles the exact upload read-only before
choosing any later retry or completion action.

The 45-row compile-independent certainty corpus covers the complete modeled
success and rejection set plus every HTTP terminal failure under each
admission state. The Ada normalization corpus applies the same mapping. Native
and lightweight socket tests cover success, restart of the same operation,
physical singleton response-header validation, pre-admission cancellation,
and a server that accepts abort but loses the response. The next request must
be an exact-upload ListParts reconciliation; a transparent DELETE retry
desynchronizes that oracle. The six-server implementation matrix drives the
typed synchronous path for Flyology memory, files, and SQLite, RustFS,
SeaweedFS, and supplemental MinIO.

## Admission and state boundary

SigV4 authentication completes before signed request controls are evaluated.
The route validates physical singleton headers, expected owner, payer, and the
optional initiation-time condition before asking the backend to retire the
upload. Memory, files, and SQLite compare that condition with the stored
initiation timestamp under the same publication lock or database transaction
that retires every part, so failed admission cannot race with deletion.

Successful durable abort removes the active upload and its parts. A transport
failure after request admission does not establish whether that transition
committed. Read-only reconciliation therefore precedes any caller-selected
retry. Abort remains cleanup and cannot roll back a destination object already
published by completion.

## Gate

The focused local executable is:

```sh
cd tests
alr -n build
./bin/s3_http_socket_corpus
```

Repository qualification additionally requires the root and SQLite test
scripts, the fixture verifier and mutation self-tests, the repeated six-server
implementation matrix, GNATdoc with the documented Flyology root-project
exclusion, the serialized warning-strict proof gate, and a clean diff check.

On the final reviewed tree, the root gate passed 41/41 AUnit tests, the
126-case files crash matrix, 320 checksum vectors, 210 chunk boundaries, the
64 GiB CRC linearization oracle, the signed application corpus, and three
native/lightweight socket repetitions. The fixture verifier and its mutation
self-tests passed, as did the SQLite gate. The full six-server implementation
matrix passed all 18 implementation/repetition lanes with the established
external capability exclusions unchanged. GNATdoc produced a nonempty API
index containing the new composable operation; warnings remained confined to
pre-existing or upstream undocumented entities.

The serialized warning-strict GNATprove gate proved 936/936 checks. Its report
contained zero flow warnings, unproved or justified checks, and `pragma
Assume` statements. The post-run exact executable-name host audit was clean
for GNATprove, Why3, SMT solvers, TLC, and TLAPS.
