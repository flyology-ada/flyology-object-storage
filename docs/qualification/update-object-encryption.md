# UpdateObjectEncryption negative-capability profile

UpdateObjectEncryption is covered only for the maintained local server's
authenticated rejection boundary. The operation remains `Not_Exposed`: there
is no public Low_Level or Objects request, synchronous wrapper, composable
operation, Finish path, response decoder, or public client GNATdoc claim.

The private server recognizes only an exact `PUT` object query carrying
`encryption`, an optional `versionId`, and an optional modeled
`x-id=UpdateObjectEncryption` association. Authentication precedes every
query, header, and body diagnostic. A present version selects exactly the S3
`null` generation or its opaque named generation; omission selects the current
object.

The route requires one nonempty request body bounded by the shared entity-safe
S3 XML limits. It accepts only the pinned `ObjectEncryption` root and sole
`SSE-KMS` union member, with one required KMS key ARN in the pinned lexical
domain and an optional exact lowercase Boolean `BucketKeyEnabled`. The optional
Boolean remains absent when omitted. The server does not invent the SSES3 union
variant or a false default described only by surrounding prose.

Expected-owner and requester-pays controls are physical singletons and are
validated before storage observation. An optional Content-MD5 and the pinned
required generated-checksum selector plus its individual value or trailer bind
the exact request document. The server chooses no checksum algorithm and emits
no success-only `x-amz-request-charged` header.

After validation, the route calls only the shared `Head_Bucket` and
version-aware `Head_Object` capabilities. An absent bucket returns
`NoSuchBucket`; an absent current object returns `NoSuchKey`; an absent selected
generation returns `NoSuchVersion`; and an existing object returns
`NotImplemented`. It never calls `Get_Object` or `Put_Object`, reads object
bytes, changes encryption or object state, invokes KMS, or reports success.

The lexical KMS ARN check does not establish account or organization ownership,
permissions, present encryption, Object Lock eligibility, key usability, or an
encryption result. Sensitive request text is neither logged nor retained after
the request. Directory buckets, S3 on Outposts, access-point routing, and
external-provider interoperability remain unimplemented and unqualified.

The selected generation is only the target whose unsupported update was
rejected. No encryption state changes, and a later HeadObject observation can
reflect concurrent or already-matching state. It cannot prove causation,
upgrade mutation certainty, or authorize automatic replay. No automatic replay
is authorized.

Qualification remains conditional on every command in the single
`update_object_encryption` lane succeeding. The dedicated preparation verifier
pins this negative-capability source boundary, the generated-model verifier
pins the eight-input, one-output, and seventeen-shape inventory, and the
maintained root test and repository gates retain shared backend and
authenticated server evidence. This tranche does not claim successful
UpdateObjectEncryption qualification.
