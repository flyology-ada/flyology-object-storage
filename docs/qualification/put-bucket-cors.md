# PutBucketCors client qualification

This record qualifies the strict bounded low-level and provider-owned clients,
backend persistence, authenticated server route, and corpora for
`PutBucketCors`. It does not claim browser CORS enforcement, policy-effect
interpretation, or external-server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Input shape 527 requires `Bucket` and `CORSConfiguration`; `ContentMD5`,
`ChecksumAlgorithm`, and `ExpectedBucketOwner` are optional. The operation
requires request-checksum admission, returns exact status 200, and has no
modeled success output.

The configuration requires flattened `CORSRules`. Each rule requires flattened
`AllowedMethods` and `AllowedOrigins`; flattened `AllowedHeaders` and
`ExposeHeaders`, `ID`, and arbitrary-precision signed-decimal `MaxAgeSeconds`
are optional. Checksum shape 77 contributes ten exact SDK algorithms. The
reciprocal member and vector ledgers cover all 12 named members and 13 request,
schema, checksum, limit, response, header, and transport contracts. The
maintained verifier gates the complete operation and shape graph:

```sh
python3 tools/verify-put-bucket-cors-preparation.py
```

## Serialization and request contract

`S3.Bucket_Controls.Serialize_CORS` requires a present configuration with at
least one rule and at least one allowed method and origin per rule. It emits the
exact S3 namespace, flattened rule and string lists, optional members, XML-
escaped opaque text, and signed-decimal maximum-age text in caller order.

The caller-selected shared XML limits bound the complete encoded document,
three-level depth, element count, and decoded text bytes. The serializer does
not introduce an independent rule, string, or numeric ceiling absent from the
pinned model. Absent or empty required lists, malformed signed-decimal text,
and every one-past limit fail before HTTP admission. The strict
`GetBucketCors` parser round-trips every emitted value.

`Client.Low_Level.Prepare_Put_Bucket_CORS` signs the exact path-style or
virtual-hosted `?cors` target. It computes Content-MD5 when omitted, validates
an exact caller override, and projects any of the ten modeled SDK checksum
algorithms over the immutable serialized bytes. The prepared request owns
those bytes. Its source is deliberately non-rewindable, so neither low-level
execution nor the provider operation can replay the mutation.

`Execute_Put_Bucket_CORS` accepts only that prepared operation. Exact 200 plus
an empty or XML-whitespace body is success; non-whitespace success content and
malformed or over-limit responses fail closed. Every other status becomes one
bounded typed S3 rejection.

## Provider-owned composition and certainty

`Client.Buckets.Set_CORS` colocates the limited constructor, operation-last
reusable procedure, typed `Finish`, and synchronous wait. The parent owns its
prepared request, source position, bounded response bytes, deadline, and
cancellation source through terminal drain. Initiation copies the complete
configuration before returning. Restart requires a consumed prior result and
the same retained HTTP and cancellation owners. No caller configuration or
credential borrow survives signing, and no helper task or second protocol
engine is introduced.

A complete exact-200 response proves completion. Only a response-observed
exact modeled pre-mutation rejection, or a failure known not to have entered
HTTP admission, proves that no mutation occurred. Cancellation before
admission is distinct. Every other possibly admitted failure and every unknown
response remains outcome unknown and requires caller-selected read
reconciliation before any retry.

## Evidence boundary

The deterministic corpus covers full and sparse two-rule serialization and
round trip, XML escaping, optional-list omission, arbitrary-precision signed
maximum age, both addressing styles, automatic MD5, all ten SDK checksums,
invalid inputs, caller limit boundaries, and cross-operation rejection. The
signed loopback corpus covers low-level execution, synchronous provider
waiting, limited construction, copied input lifetime, operation-last restart,
typed response-observed certainty, and exact prepared-operation identity. The
normalization corpus crosses every typed HTTP failure with every admission
certainty.

The machine ledger records `PutBucketCors` as `covered / covered / covered /
covered`. Backend and authenticated server evidence preserves the exact
serialized document, validates its checksums, and distinguishes an absent
bucket. This coverage does not claim browser enforcement of stored CORS state.

The `PutBucketCors` registry lane is independently conditional on every
maintained command succeeding. It records exact HTTP-200 completion, checksum
binding, unknown outcome after possible admission, and noncausal `Get_CORS`
observation without automatic replay. Its generated-model documentation
evidence is a region-scoped warning measurement only; repository-wide and
selected GNATdoc qualification remain blocked by pre-existing warnings outside
that declaration region.
