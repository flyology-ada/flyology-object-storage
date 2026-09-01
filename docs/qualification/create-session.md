# CreateSession client qualification

This record qualifies the synchronous and provider-owned composable client
boundary and the Flyology server's authenticated negative-capability route for
the directory-bucket CreateSession operation. It does not claim successful
directory-bucket session issuance or interoperability from the pinned
general-purpose S3-compatible servers.

## Authority and inventory

The machine-checked inventory is tied to the repository's immutable botocore
S3 model revision `36c34f15391da01cd717c73c0fffa747c9889768` and service
model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
It covers request shape 137 with six members, output shape 136 with five
top-level members, and required SessionCredentials shape 652 with four
members. The current
[AWS CreateSession API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_CreateSession.html)
was reviewed on 2026-08-23. The pinned generated model remains authoritative
for this crate where its exact enum surface differs from current prose.

## Qualified client boundary

`Client.Low_Level.Create_Session_Parameters` projects every non-resource input
member. Preparation requires HTTPS and virtual-hosted addressing, preserves
true omission, validates the session-mode and encryption enums through the
generated model, and rejects incoherent KMS companions, noncanonical Base64,
explicitly disabled bucket keys, over-8-KiB values, and control bytes before
HTTP admission.

The success decoder covers every top-level response member and all four
required nested credential members. It requires one strict bounded
CreateSessionResult document, rejects foreign namespaces, attributes, unknown
or duplicate members, invalid timestamps, empty credentials, and excessive
documents. Every modeled response header is a physical singleton: omission is
preserved, while present-empty, duplicate, overlong, control-bearing,
noncanonical, incoherent, or request-conflicting values are Invalid_Response.
Access key, secret, and session token are returned in the existing limited,
zeroizing Credentials type; expiration is preserved separately. A later
prepared request signs the returned token as `x-amz-s3session-token`, never as
the generic `x-amz-security-token`. Generic HTTP and XML response buffers can
contain transient copies and are not claimed to be securely erased, but this
layer does not log or durably retain them.

`Client.Buckets.Create_Session` exposes a limited constructor, operation-last
restart, typed `Finish`, and a parameter-record synchronous wait. All four use
one owner-driven bounded-response state machine. The operation copies the
signed policy during initiation and retains bounded raw response state through
terminal drain; it does not store decoded credentials. `Finish` validates the
captured physical headers against the signed request and constructs the
limited, zeroizing identity exactly once. The established scalar convenience
form waits on that state machine while retaining its raising transport and
malformed-response behavior.

No overload creates a refresh task, retains client-side session state or caller
input after signing, adds operation-level replay, or starts a detached helper
task. Transport recovery remains the configured Flyology HTTP client's policy.
A typed exchange failure preserves admission certainty for the caller's retry
decision.

## Local authenticated negative-capability route

The Flyology server recognizes only the exact authenticated bucket-target
`GET ?session` forms, including the pinned `x-id=CreateSession` association.
It rejects malformed query shapes after authentication, rejects request
bodies, and validates physical singleton, nonempty, text-safe values for all
five modeled policy headers. Session mode, encryption enumeration, KMS
companions, canonical Base64 context, and the exact enabled bucket-key value
follow the same request contract as the qualified client.

After validation the route calls the existing shared `Head_Bucket` capability.
It returns `NoSuchBucket` for an absent bucket and `NotImplemented` for an
existing general-purpose bucket. It does not issue credentials, persist a
directory-bucket/session model, retain session state, or add session-token
authentication. The route therefore proves strict authenticated admission and
an explicit capability boundary; it does not manufacture successful
CreateSession support.

## Independent corpus

`tests/corpora/create-session/members.tsv` accounts for all 15 modeled members.
`vectors.tsv` defines request, response, ownership, TLS, and capability cases.
The isolated verifier checks the locked revision and hash, exact generated
member counts, names and wire locations, canonical vector identifiers, and
reciprocal references, plus the low-level initiator, captured-response decoder,
provider operation, operation-last restart, and typed Finish declarations:

```sh
python3 tools/verify-create-session-preparation.py
```

The direct AUnit corpus covers exact signing, invalid addressing, every policy
relation, scalar and header bounds, complete success and error decoding,
strict XML structure, required fields, timestamp validation, operation
binding, and reuse of returned temporary credentials. A trusted project-owned
TLS fixture drives the public wrapper through both native and Flyology
lightweight callers, verifies the exact signed request, and rejects response
policy mismatch, duplicate physical headers, present-empty headers, and
noncanonical booleans. Both task kinds also drive the typed synchronous form,
limited constructor, copied-policy mutation, operation-last mismatch and
successful restarts, typed Finish, and a caller-selected response bound.

CreateSession requires an AWS directory-bucket zonal endpoint. RustFS,
SeaweedFS, MinIO, and the Flyology general-purpose servers in the existing
implementation matrix do not supply that capability. Their absence is an
explicit external capability exclusion, not a reason to relax the client or
to claim server interoperability.

The machine ledger records the reviewed operation as `covered / covered /
covered / covered` with its exact public name, symbols, exclusions, evidence,
and isolated qualification lane. Backend coverage is the shared bucket
existence capability used by the authenticated negative route; it does not
claim directory-bucket state, credential issuance, or provider compatibility.

## Frozen gate evidence

The exact client slice passed the root gate, repository-integrity gate, and
isolated CreateSession inventory verifier. The root gate includes 41/41 AUnit
tests and three repetitions of both task kinds through the 20-exchange loopback
TLS corpus. Focused GNATdoc measurement produced a nonempty API index and
removed the generated model's sole CreateSession operation-enum warning: the
repository count fell from 35,992 to 35,991 with no added diagnostic and an
unchanged comment-stripped Ada token hash. Repository-wide qualification
remains blocked by preexisting warnings outside this operation's declaration
region. The slice does not change SQLite or backend code, so a redundant SQLite
gate was not run.

The latest serialized proof campaign remains the 2026-08-26 936/936 result.
This slice changes only non-SPARK client, TLS-corpus, verifier, and
documentation units, not any of the nine `tools/prove.sh` manifest units, so a
redundant proof rerun was not performed.
