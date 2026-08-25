# CreateMultipartUpload qualification

This record freezes the pinned model inventory, qualified synchronous client,
and strict authenticated server-admission boundary. Backend initiation
deliberately retains its narrower policy support; the server admits that
supported subset and explicitly rejects every validated unsupported policy
before creating an upload. The server ledger cell is covered for this
authenticated general-purpose capability profile; advanced policies remain
explicit exclusions rather than silently accepted partial behavior.

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

The limited constructor and operation-last procedure named
`Client.Transfers.Create_Multipart_Upload` are the completion-set-aware forms.
They copy the complete prepared request before returning, drive one hidden
HTTP child on the caller's stack, use a one-shot non-replayable known-empty
source, and bound the response sink by the existing S3 XML parse limits.
`Client.Transfers.Create_Multipart_Upload` has a typed-result overload that is
a literal wait on this same operation. The established
`Low_Level.Create_Multipart_Outcome` overload remains source compatible.
Neither form creates a helper task or performs automatic replay. Credentials
and sensitive SSE-C material are retained only by the bounded request state
and are not durably stored by this layer.

An accepted initiation followed by a lost response is ambiguous: the service
may have created an upload whose identifier the caller did not receive.
Transparent retry can create a second active upload. The typed result preserves
HTTP admission separately from its bounded failure reason. A pre-admission
failure is definitely not created, with a distinct spelling for cancellation;
an exact modeled service rejection is also conclusive. A timeout,
cancellation, transport failure, malformed response, conflict, throttling, or
service failure after possible admission is `Creation_Outcome_Unknown`.
Callers reconcile before retry and the wrapper never auto-retries.
ListMultipartUploads is a read-only discovery aid, but it cannot uniquely
identify the lost initiation when concurrent requests for the same key are
indistinguishable; callers must arrange a stronger application invariant or
retain the unknown outcome.

## Isolated artifacts

`tests/corpora/create-multipart-upload/members.tsv` preserves the
prequalification boundary for every request and output member together with
its generated wire location, required closure, and strict vectors. The
coverage ledger and this qualification record carry the promoted state.
`tests/corpora/create-multipart-upload/vectors.tsv` defines target, header-map,
ACL, metadata, tagging, checksum, encryption, Object Lock, owner/payer,
response, durability, inheritance, ambiguity, and external-server designs.
`tests/corpora/composable-client/create-multipart-certainty.tsv` independently
freezes the typed response, failure, admission, and reconciliation mapping for
the composable operation and its synchronous result wrapper.

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
lightweight clients, use both the direct composable constructor and its typed
synchronous wrapper, bind bucket/key and explicit policy, and reject duplicate
and present-empty physical headers. A dropped successful initiation returns
typed unknown creation certainty and is followed by one read-only
ListMultipartUploads reconciliation request; the scripted server rejects any
automatic POST replay.
The original evidence promoted only the client cell. The server-admission
closure below separately gates every modeled request field without claiming
advanced backend policy persistence.

## Qualified server admission boundary

The authenticated general-purpose path-style route handles every one of the
31 modeled request members. Content type and the checksum algorithm/type pair
are the supported durable initiation subset on memory, files, and SQLite. The
server applies the documented checksum default, enforces supported
algorithm/type combinations, and passes only that validated snapshot to the
backend.

Every other modeled policy is authenticated and classified before backend
entry. Physical singleton duplication, case-colliding metadata, unknown
checksum headers, empty or over-budget metadata, malformed HTTP dates, ACL
enums and ACL/grant conflicts, bounded quoted grant lists and duplicate
grantees, payer and storage enums, SSE-C key/digest/HTTPS relations, mutually
exclusive SSE/KMS groups, canonical KMS context, bucket-key relations, tag
syntax, Object Lock enums/group/timestamp syntax, and expected-owner mismatch
all fail with a typed request error. A syntactically valid but unsupported ACL,
metadata, encryption, storage, payer, tagging, redirect, or Object Lock policy
returns authenticated `NotImplemented` before upload creation. The route never
silently drops such a field.

The strict signed corpus exercises malformed and valid-but-unsupported values,
authentication precedence, a nonempty request body, absence of any upload
after the rejection matrix, the exact derived Content-Type aggregate boundary,
and successful creation/abort at that boundary. The files and SQLite black-box
lanes additionally create a SHA-256 multipart upload, publish one signed part,
terminate the server, reopen the same storage root, rediscover the upload and
part through authenticated listings, complete it, and verify exact bytes and
the returned version identity. This qualifies the covered server profile but
does not claim persistence or application of explicitly excluded policies.

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

## Composable initiation addendum

The completion-set-aware initiation slice passed the current root gate with
41/41 AUnit tests, all 126 abrupt files crash points, the 45-case independent
creation-certainty fixture and its negative verifier, and three complete
native/lightweight socket repetitions. The socket corpus includes direct
constructor success, pre-admission cancellation, exact lost-response admission
certainty, read-only reconciliation, and rejection of automatic POST replay.
The SQLite wrapper/backend gate passed.

The six-server implementation matrix passed all 18 implementation/repetition
lanes across RustFS, SeaweedFS, supplemental MinIO, and Flyology memory, files,
and SQLite. Its primary CreateMultipartUpload call uses the typed synchronous
wrapper over the same composable state machine. Pinned external capability
exclusions remained exact; there was no unexpected failure or unexpected pass.
GNATdoc generated the public `Client.Transfers` operation, result, constructor,
reusable procedure, and Finish entries. The maintained warning-strict proof gate passed
936/936, and the post-run process audit was clean before the exclusive formal
lane was released.

## Server-admission gate evidence

The authenticated server admission closure passed the root gate with 40/40
AUnit tests, the 88-case files crash matrix, 320 checksum vectors, 210 chunk
boundaries, the 64-GiB CRC linearization oracle, the expanded signed server
application corpus, and three repetitions of the native/lightweight socket
corpus. The SQLite wrapper, catalog, and backend gate passed. The coverage and
31-request/14-response preparation verifiers passed, including their negative
oracles.

GNATdoc 26 produced a 12,440-line log and a nonempty API index containing
`Flyology.Object_Storage`, with no error, internal-error,
`LANGKIT_SUPPORT.ERRORS`, infinite-recursion, or
`flyology-channels-bounded` diagnostic. The serialized warning-strict proof
campaign started at 2026-08-24T08:18:24Z with FSF GNATprove 16.1.0 and proved
936/936 checks across all nine manifest units: 180 flow checks and 756 prover
checks, with a maximum of 663 steps. The report contains zero warnings,
unproved or justified checks, and `pragma Assume` statements; the selected
source contains no proof suppression. The post-run host process audit was
clean, and the exclusive prover lane was explicitly released.
