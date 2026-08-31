# GetBucketLifecycleConfiguration client qualification

This record qualifies the provider-owned composable and typed synchronous
client for `GetBucketLifecycleConfiguration`. Independent backend and server
evidence also covers atomic lifecycle-configuration persistence and the
authenticated Flyology route. It does not claim lifecycle action execution or
external server interoperability.

The pinned model also retains deprecated `GetBucketLifecycle`. Its method,
resource path, required bucket, and optional owner precondition are identical
to the maintained operation, while its Rules response is a structural subset.
The client therefore exposes that compatibility operation through the same
`Get_Lifecycle_Configuration` API and strict decoder rather than duplicating
an obsolete public name. Its separate registry lane appends only
`GetBucketLifecycle`; this shared client evidence is conditional on that lane.
The maintained backend and route evidence covers both exact operation
identities without making an external-provider claim.

## Pinned authority and complete inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 238 requires `Bucket` and optionally carries
`ExpectedBucketOwner`. Output shape 237 optionally carries direct `Rule`
elements and the
`x-amz-transition-default-minimum-object-size` response header.

The transitive graph contains 36 named members across the request, output,
abort, expiration, rule, filter, logical-And, noncurrent expiration,
noncurrent transition, tag, and current transition structures. The pinned
model projects direct ordered Rules, Transitions, NoncurrentVersionTransitions,
and logical-And Tag values. Each rule requires `Status`; every present Tag
requires `Key` and `Value`.

The exact enum domains are `Enabled` and `Disabled`; transition-minimum values
`varies_by_storage_class` and `all_storage_classes_128K`; and storage classes
`GLACIER`, `STANDARD_IA`, `ONEZONE_IA`, `INTELLIGENT_TIERING`, `DEEP_ARCHIVE`,
and `GLACIER_IR`. `Date` is a timestamp. The five distinct integer or long
shapes used by the graph have no pinned minimum or maximum, so the public
codec preserves validated signed-decimal text instead of selecting a machine
integer ceiling.

The reciprocal member and vector ledgers use shape-qualified references, so
repeated names such as `Prefix`, `Date`, and `Days` cannot collapse into false
coverage. The verifier gates all 36 members, direct list projections, required
members, enum domains, timestamp kind, and unbounded numeric shapes:

```sh
uv run --python 3.13 -- \
  python tools/verify-get-bucket-lifecycle-configuration-preparation.py
```

## Provider-owned API and ownership

`Client.Low_Level.Prepare_Get_Bucket_Lifecycle_Configuration` validates and
copies the bucket and optional owner precondition before transport, signs an
empty body, and projects only the pinned request members. Its prepared
initiator, synchronous executor, and response decoder all reject a prepared
operation for any other S3 call.

`Client.Buckets.Get_Lifecycle_Configuration` owns the complete public
operation vocabulary: a limited root constructor, an operation-last reusable
procedure, typed `Finish`, and a typed synchronous function. The synchronous
function waits on that same owner-driven state machine. One hidden bounded
HTTP exchange is driven on the owner task's stack. There is no helper task,
request body, retry, retained caller input after signing, or second protocol
engine. Restart is allowed only after typed Finish and requires the same HTTP
client and cancellation owner.

The complete success body, transition-minimum header, and S3 diagnostic
headers are captured from one response. Physical singleton headers are
strict. An empty HTTP 200 body preserves configuration absence; a present body
is decoded under the caller's existing shared XML byte, depth, element, and
text limits. Dynamic lists have no independent capacity because no such limit
exists in the pinned model and the caller already supplies the resource
boundary.

## Strict response contract

The parser accepts the exact unqualified REST/XML graph and the exact S3
namespace. It preserves optional empty strings, false Booleans, arbitrary-size
signed decimal text, exact timestamps, optional structures, and list order.
It does not enforce prose-only action combinations absent from the pinned
structural model, choose lifecycle policy, or normalize enum values.

It rejects wrong roots, unknown or duplicate members, attributes, foreign or
mixed namespaces, incorrect list wrappers, missing required Status or tag
pairs, invalid enum/Boolean/integer/timestamp values, DTDs, entity expansion,
processing instructions, malformed UTF-8, and caller-limit violations. Only
exact HTTP 200 is success; every other complete response is decoded as a
strict bounded S3 error, including `NoSuchLifecycleConfiguration`.

## Coverage boundary and gates

The deterministic Ada corpus covers the complete nested graph, every enum,
arbitrary-precision signed numbers, timestamps, namespaces, required-member
failures, addressing styles, owner signing, exact header domains, strict
status/error decoding, and caller XML limits. The native/lightweight raw
socket corpus adds signed success, typed synchronous and composable waits,
wrong prepared-operation rejection before admission, operation restart,
duplicate physical headers, and bounded response-sink failure. The exhaustive
normalization helper covers modeled statuses plus every HTTP terminal failure
and admission-certainty value.

The maintained full test gate passed 41/41 AUnit cases, all 132 files-backend
pre/post-barrier crash cases, the 320-vector checksum oracle with 210 chunk
boundaries, and three complete native/lightweight socket-corpus repetitions.
The model verifier reported all 36 members, four exact list projections, 10
enum values, five unbounded numeric shapes, and 13 reciprocal vectors. The
repository-integrity gate passed against the pinned model. GNATdoc produced a
nonempty 430-page API site from a 44,255-line log with no lifecycle-package
documentation warning, internal error, or recursion diagnostic.

The machine ledger records both lifecycle GET identities as
`covered / covered / covered / covered`. Memory, files, and SQLite preserve
the canonical document and optional transition-minimum header atomically; the
authenticated server distinguishes an absent lifecycle configuration from a
missing bucket.

This slice changes only non-SPARK client, codec, corpus, and documentation
units. It does not alter any unit named by the maintained proof manifest;
formal evidence is therefore not reused to claim this new client behavior.
