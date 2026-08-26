# PutBucketReplication qualification

The current client boundary is derived from botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and normalized service-model
SHA-256 `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
The modeled request is `PUT /{Bucket}?replication`, requires `Bucket` and the
complete `ReplicationConfiguration` payload, and has sole success status 200.
It admits exact `Content-MD5`, `x-amz-bucket-object-lock-token`, and
`x-amz-expected-bucket-owner` headers. The model requires a request checksum;
the caller selects its exact algorithm and the client computes and signs both
that digest and an automatic Content-MD5 over the same owned XML when no exact
MD5 override is supplied.

The request codec shares the complete presence-sensitive graph documented by
[GetBucketReplication](get-bucket-replication.md): required role and nonempty
flattened rules, exact status and storage-class domains, arbitrary-precision
numeric text, nested filters, source criteria, destination controls,
replication time, metrics, and delete-marker controls. Serialization enforces
the pinned structural model and caller-selected document, depth, element, and
text limits. It deliberately does not invent the prose-only filter-cardinality,
replication-time/metrics pairing, or V1/V2 cross-field policy absent from the
service shapes.

`Client.Low_Level.Prepare_Put_Bucket_Replication`, its synchronous executor,
and its operation-last initiator share one exact modeled request. The initiator
rejects another prepared operation before HTTP admission. The provider-owned
`Client.Buckets.Set_Replication_Configuration` limited constructor,
operation-last restart, typed `Finish`, and synchronous wait all drive the same
one-shot state machine. It owns the serialized body through terminal drain,
does not retain caller input, and never rewinds or replays the mutation.

Typed completion distinguishes exact rejection from uncertain application.
Success completes the replacement. Only reviewed complete error/status pairs
prove non-application; malformed, retryable, lost, or otherwise uncertain
results after possible admission remain outcome-unknown. A caller must use
read-only `Get_Replication_Configuration` reconciliation before choosing any
later retry.

Deterministic qualification covers canonical full-graph serialization,
presence consistency, integer validation, request projection, automatic MD5,
checksum/token/owner signing, XML limits, strict response decoding, complete
failure/admission normalization, and exact-operation rejection. The signed
socket corpus exercises low-level, synchronous, limited-constructor, and
operation-last restart paths in both native and lightweight HTTP profiles.
This is client and corpus qualification only; it does not claim an Object
Storage backend, server route, or external provider result.
