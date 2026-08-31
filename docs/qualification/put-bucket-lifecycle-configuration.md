# PutBucketLifecycleConfiguration client qualification

This record qualifies the strict bounded low-level and provider-owned clients
for `PutBucketLifecycleConfiguration`. Independent backend and server evidence
also covers atomic lifecycle-configuration persistence and the authenticated
Flyology route. It does not claim lifecycle action execution or external
server interoperability.

The pinned model also retains deprecated `PutBucketLifecycle`. Its method,
resource path, success status, checksum selection, and prefix-rule payload are
a structural subset of the maintained operation. The client deliberately
exposes only a compatibility subset through `Set_Lifecycle_Configuration`:
it uses the current operation identity and does not reject modern-only inputs
when the evidence is attributed to the deprecated name. The optional legacy
`ContentMD5` override is not surfaced. Its separate registry lane appends
only `PutBucketLifecycle`; no automatic replay, full legacy-operation, or
external-provider claim follows.

## Pinned authority and complete inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Input shape 532 has five members: required `Bucket`, optional
`ChecksumAlgorithm`, the lifecycle body, `ExpectedBucketOwner`, and
`TransitionDefaultMinimumObjectSize`. Output shape 531 has the optional exact
transition-minimum header. The operation returns exact status 200 and requires
a request checksum selected through `ChecksumAlgorithm`.

The lifecycle body is optional; when present it requires the flattened Rules
member and reuses the same 32-member nested graph qualified for
`GetBucketLifecycleConfiguration`. Rules require Status; present tags require
Key and Value; ordered transition,
noncurrent-transition, and tag projections remain exact. Enum domains,
timestamps, Booleans, optional structures, arbitrary-precision decimal text,
and XML namespace behavior are identical in both directions.

The maintained verifier gates the exact operation scalars, five request
members, one output member, required flattened Rules projection, checksum and
transition enum domains, implementation vocabulary, and shared nested graph:

```sh
uv run python \
  tools/verify-put-bucket-lifecycle-configuration-preparation.py
```

## Serialization and request contract

`S3.Lifecycle.Serialize` emits an empty body for exact configuration absence
and requires at least one rule when the configuration is present. A present
document uses the exact S3 namespace, direct flattened lists, required
members, exact enums and timestamps, lowercase Booleans, validated decimal
text, and escaped strings in caller order. The caller's shared XML limits
bound document bytes, depth, elements, and decoded text. Inconsistent presence
state, absent or empty required rules, malformed values, and one-past limits
fail before HTTP admission.

The pinned shapes do not encode the prose-only 1,000-rule ceiling or every
documented one-of/action combination. The codec therefore does not invent
those lifecycle policies. Callers select their XML resource limits and the
provider remains responsible for policy validation beyond the structural
wire model.

`Client.Low_Level.Prepare_Put_Bucket_Lifecycle_Configuration` signs the exact
path-style or virtual-hosted `?lifecycle` target. The current input exposes no
Content-MD5 member, while its checksum trait requires a request checksum.
Callers therefore explicitly select one of the ten modeled algorithms; the
client computes and signs the matching digest over the immutable serialized
bytes. Optional owner and transition-minimum headers preserve true omission or
one exact validated value. The prepared request owns its body, and the request
source is deliberately non-rewindable.

Only exact 200 plus an empty or XML-whitespace body is update success. The
optional transition-minimum response header is a physical singleton in its
two-value domain. Non-whitespace success content, duplicate or malformed
headers, and over-limit bodies fail closed. Every other complete response is
one bounded typed S3 rejection.

## Provider-owned composition and certainty

`Client.Buckets.Set_Lifecycle_Configuration` colocates the limited
constructor, operation-last reusable procedure, typed `Finish`, and
synchronous wait. Every addressing, deadline, cancellation, XML-limit,
checksum, owner, and transition choice is explicit. The parent owns the exact
serialized body, signed request, response bytes, and one hidden HTTP child
through terminal drain. It copies caller input during initiation, retains no
credential or configuration borrow, creates no helper task, and never replays
the mutation.

Exact success is completed. Response-observed conclusive pre-mutation errors
and failures known not to have entered admission are definitely not applied;
cancellation before admission remains distinct. Every other possibly admitted
failure is outcome unknown and requires caller-selected
`Get_Lifecycle_Configuration` reconciliation before any retry.

## Evidence boundary

The deterministic corpus covers full-graph canonical round trip, every
request member, exact signed checksum and transition headers, malformed and
inconsistent input, every caller XML boundary, exact response status/body/
header behavior, and strict structured errors. The signed loopback corpus
covers low-level execution, typed synchronous waiting, limited construction,
copied input lifetime, operation-last restart, response-observed certainty,
and exact prepared-operation rejection before admission. The normalization
corpus crosses modeled responses and HTTP terminal failures with admission
certainty.

The complete evidence advances every ledger cell. Memory, files, and SQLite
preserve the canonical document and optional transition-minimum header
atomically, while the authenticated route validates the exact checksum and
owner contract. Lifecycle action execution and external-provider behavior
remain separate work. Proof is not reused to claim serializer or client
behavior.

## Maintained gate results

The exact implementation tree passed the maintained full test gate: 41/41
shared AUnit cases, all 132 files-backend crash-barrier cases, the 320-vector
checksum oracle with 210 chunk boundaries, and all three required repetitions
of the deterministic lifecycle and signed socket corpora. Repository
integrity, the pinned generated model, the 116-operation coverage ledger,
Python syntax, Markdown links, workflow policy, and whitespace checks passed.

GNATdoc 26 exited successfully and produced a nonempty 430-page public API
site from a 44,281-line diagnostic log. The generated site contains the
lifecycle operation, preparer, limited operation type, and all
`Set_Lifecycle_Configuration` overloads. The new declarations introduced no
targeted documentation warning, internal error, recursion diagnostic, or fatal
error.
