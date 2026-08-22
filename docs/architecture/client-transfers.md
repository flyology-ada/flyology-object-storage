# Client transfer policy

`Flyology.Object_Storage.Client.Transfers` is the convenience layer over the
model-driven S3 client. It provides single-file upload/download and an ordered
multi-subject call without hiding S3 results or resource policy.

## Server-side copy

`Copy_Object` takes raw source and destination bucket/key strings and performs
a server-side S3 CopyObject. It owns percent-encoding and signing the
`x-amz-copy-source` header, including keys containing spaces, plus signs, and
literal percent bytes. The compact result retains the entity tag, modification
time, and source/destination version identifiers, or the structured S3 error.
An optional source entity-tag precondition supports safe conditional copies.

The convenience call deliberately excludes metadata replacement, tagging,
ACL, encryption, object-lock, and version-selection policy. Those controls
remain explicit at `Client.Low_Level.Prepare_Copy_Object`, where the complete
typed core and generated-model boundary can represent them without surprising
defaults such as silently discarding existing user metadata.

## Automatic multipart uploads

`Upload_File` hashes a local file and every multipart range in one sequential
pass over one open descriptor. Files smaller than the threshold use PutObject;
nonempty files at or above it use CreateMultipartUpload, ordered UploadPart
requests, and CompleteMultipartUpload. Defaults are a 64 MiB threshold and
16 MiB parts. Part size must be 5 MiB through 5 GiB, and the proved planner
rejects plans above 10,000 parts or the supported 50 TiB object bound.

Parts within one file are sequential. This keeps one file descriptor and one
bounded request body active, avoids a task per chunk, and leaves protocol
multiplexing, flow control, cancellation and deadline waiting to Flyology HTTP
and the runtime. Parallelism belongs at the subject level unless a future
measured workload demonstrates that per-object part parallelism is necessary.

`Client.Low_Level.Prepare_Put_Object` and `Execute_Put_Object` form the complete
typed path for single-request uploads. Its 42-field policy record, explicit bucket/key,
and the borrowed source's body/declared length account for all 46 members in
the pinned PutObject input. It signs user metadata and every modeled header,
requires checksum selectors to have their matching value, validates checksum
widths and HTTPS-only SSE-C material, and rejects cross-field combinations the
model shape cannot express: canned plus explicit ACLs, KMS fields without
SSE-KMS, SSE-C mixed with KMS, and Object Lock without an integrity header.
The 22-member result decoder validates the required entity tag, every checksum
family, modeled enums, optional object size and bucket-key state, and rejects
an unexpected success body. `Upload_File` uses this typed path for small and
empty objects; multipart uploads continue through their typed primitives.

After initiation, a rejected part or local exception triggers a best-effort
AbortMultipartUpload with an independent short cleanup budget. A lost response
to CompleteMultipartUpload remains ambiguous: S3 may have committed the object
before the transport failed. Abort is not rollback. Applications needing an
unambiguous workflow must reconcile the expected key, size and metadata with
HeadObject or publish through an application-level manifest/version pointer.

Callers can also retire an upload explicitly with `Abort_Multipart_Upload`.
The convenience call accepts bucket, key, and upload ID directly and retains
the typed S3 outcome. Requester Pays, expected-owner, and RFC 822
initiation-time preconditions remain optional named arguments; the low-level
builder signs the complete six-member pinned request shape and validates the
sole `x-amz-request-charged` success member.

`Client.Low_Level.Prepare_Complete_Multipart_Upload` preserves its compact
overload and also exposes all 23 pinned request members through typed
parameters: ten checksum families, checksum type, exact assembled size,
destination entity-tag predicates, owner/payer policy, and SSE-C material.
The result retains all 21 modeled body and response-header members. The
Flyology server evaluates `If-Match`, `If-None-Match`, and exact assembled
size inside each backend's atomic publication boundary, so a failed predicate
does not retire the staged upload. Additional-checksum completion and
encrypted-upload policy remain explicitly unsupported by the server and keep
the operation's server coverage partial.

## HeadObject reconciliation

`Head_Object` performs that reconciliation without retaining a response body.
It projects raw bucket/key strings through the generated S3 model and returns
the 64-bit content length, entity tag, last-modified value, content type,
version ID, and the common CRC32, CRC32C, SHA-1, and SHA-256 checksum headers.
Nonempty checksum headers are validated for their exact decoded width, and a
checksum type must be `COMPOSITE` or `FULL_OBJECT`.

The convenience call retains its original version, entity-tag, and checksum
arguments and adds the remaining modeled controls as trailing named
arguments. Its `Details` component exposes the complete validated typed result
without removing the compact common-field aliases. A bodyless unsuccessful
HEAD response becomes a compact synthetic
`HTTP<status>` S3 error while retaining `x-amz-request-id` and `x-amz-id-2`.
This avoids inventing an XML error document that S3 does not send. The typed
`Client.Low_Level.Prepare_Head_Object`/`Execute_Head_Object` path exposes all
21 pinned request members and 43 response members. User
metadata is preserved as an ordered entry vector. Checksums, numeric counts,
modeled enums, entity tags, dates, Accept-Ranges, and ranged response framing
are validated before success is returned. SSE-C request keys are rejected on
plaintext HTTP, and any response-body octet is a protocol failure for HEAD.

## Multi-subject transfers

`Transfer_Many` accepts one ordered array containing uploads and downloads and
returns a result at every matching index. It executes fully joined structured
waves. The effective worker count is the minimum imposed by maximum concurrent
objects, maximum concurrent requests, and the in-flight byte budget. The
batch timeout is one shared monotonic budget, not a fresh timeout per object.

`Continue_After_Failure` records independent terminal outcomes and continues.
`Cancel_Remaining` requests the scope token after the first rejected or failed
subject, joins already admitted siblings, and marks later waves cancelled.
The borrowed HTTP client and credentials are never retained beyond the joined
return.

Downloads stream into a same-directory temporary file and atomically replace
the destination only after a complete response and successful close. Existing
destinations survive failed transfers. Callers must serialize two subjects
that target the same local path and must not allow untrusted concurrent writes
to the destination directory. By default the convenience operation requests
the whole representation and accepts only HTTP 200. Callers may instead supply
one S3 `Range` value; that mode accepts only HTTP 206 with a strict, coherent
single `Content-Range` whose interval length equals `Content-Length` and the
bytes actually received. Missing, inverted, multipart, unsolicited, or
length-inconsistent intervals are protocol failures and cannot publish a
destination. Version selection, all four HTTP entity/date conditions,
expected-owner, requester-pays, and checksum mode are also available without
dropping to the low-level API. A 304 or 412 is returned as a typed rejection
and leaves any existing destination untouched.

The lower-level GetObject path separates response-head validation from body
consumption. `Prepare_Get_Object` projects all 21 modeled request members,
`Execute_Get_Object` returns Flyology HTTP's limited streaming response, and
`Decode_Get_Object_Response_Head` validates all 42 modeled response-head
members while leaving a successful body unread. Callers then pull bounded body
chunks under the original exchange deadline. Rejected responses are consumed
within the XML limit and decoded as S3 errors. Bodyless or non-XML rejection
responses use the same request-ID-preserving `HTTP<status>` representation as
HeadObject; malformed successful response heads remain hard protocol failures.
SSE-C keys are accepted only for HTTPS origins.
