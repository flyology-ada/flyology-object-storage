# CreateSession client qualification

This record qualifies the synchronous client boundary for the directory-bucket
CreateSession operation. It does not claim a directory-bucket backend, an
authenticated Flyology server route, or interoperability from the pinned
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

## Qualified synchronous boundary

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

`Client.Buckets.Create_Session` performs the bounded synchronous call without a
refresh task or retained client-side session cache. It returns a limited typed
success or structured S3 rejection. Transport retry behavior remains owned by
the configured Flyology HTTP client; this wrapper does not add an operation
replay or a detached helper task.

## Independent corpus

`tests/corpora/create-session/members.tsv` accounts for all 15 modeled members.
`vectors.tsv` defines request, response, ownership, TLS, and capability cases.
The isolated verifier checks the locked revision and hash, exact generated
member counts, names and wire locations, canonical vector identifiers, and
reciprocal references:

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
noncanonical booleans.

CreateSession requires an AWS directory-bucket zonal endpoint. RustFS,
SeaweedFS, MinIO, and the Flyology general-purpose servers in the existing
implementation matrix do not supply that capability. Their absence is an
explicit external capability exclusion, not a reason to relax the client or
to claim server interoperability.

## Frozen gate evidence

The qualified source passed the root and SQLite gates and the isolated
CreateSession inventory verifier. The root gate includes 38/38 AUnit tests and
three repetitions of both task kinds through the loopback TLS corpus. The
serialized proof campaign started at 2026-08-23T15:56:13Z with FSF GNATprove
16.1.0. `./tools/prove.sh` used warnings as errors and proved 936/936 checks
across all nine manifest units: 180 flow checks and 756 prover checks, with a
maximum of 663 steps. The report contains zero warnings, justified or unproved
checks, and `pragma Assume` statements. The source suppression audit and the
post-run GNATprove/Why3/SMT process audit were clean.
