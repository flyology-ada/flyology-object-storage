# GetBucketReplication qualification

The current client boundary is derived from botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and normalized service-model
SHA-256 `429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
The modeled request is `GET /{Bucket}?replication`, requires `Bucket`, and
optionally signs `x-amz-expected-bucket-owner`. The sole modeled success status
is 200.

The response codec retains the complete current graph. A successful document
requires `Role` and at least one flattened `Rule`; every rule requires
`Status` and `Destination`, and every destination requires `Bucket`. Optional
members preserve their presence independently: ID, arbitrary-precision signed
decimal priority, legacy prefix, current prefix/tag/And filters, source KMS and
replica-modification criteria, existing-object and delete-marker controls,
destination account and storage class, access-control translation, replica KMS
key, replication time, and metrics. Minute values remain validated decimal
text rather than being narrowed to a machine integer. Enabled/Disabled and the
15 destination storage classes are exact pinned-model domains. The codec
preserves the pinned distinction that existing-object status is required when
its structure is present, while delete-marker status is independently
optional.

The generated structural model does not encode every policy sentence in the
shape documentation. In particular, the codec does not independently enforce
the prose-only exactly-one child rule for `Filter`, the pairing requirements
between replication time and metrics, or the V1/V2 and tag/delete-marker
cross-field restrictions. Those constraints remain service-side policy rather
than claims made by this structural response decoder.

`Client.Low_Level.Prepare_Get_Bucket_Replication`,
`Execute_Get_Bucket_Replication`, and the operation-last
`Get_Bucket_Replication` initiator share the same signed prepared request. The
initiator rejects another modeled operation before HTTP admission.
`Client.Buckets.Get_Replication_Configuration` owns the limited constructor,
operation-last reusable initiation, typed `Finish`, and synchronous wait. The
synchronous form waits on that same owner-driven state machine; no helper task,
retry, or detached response parse exists. One caller-selected XML limit bounds
the captured same-response document and structured S3 error.

Deterministic qualification covers the full nested graph, every storage class,
arbitrary-precision values, malformed and incomplete structures, unknown
domains, response and document limits, request projection, strict error
decoding, high-level response/failure normalization, and wrong prepared
operation rejection. The signed socket corpus exercises low-level,
synchronous, limited-constructor, reusable-restart, duplicate-header, and
bounded-response paths against the native and lightweight HTTP profiles used
by the maintained suite. This is client and corpus qualification only; it does
not claim an Object Storage backend, server route, or external provider result.
