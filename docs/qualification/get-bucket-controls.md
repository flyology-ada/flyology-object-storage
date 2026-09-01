# Bucket-control GET client qualification

This record qualifies strict bounded synchronous clients and corpora for
`GetBucketAbac`, `GetBucketAccelerateConfiguration`, `GetBucketPolicy`,
`GetBucketPolicyStatus`, `GetBucketRequestPayment`, and
`GetPublicAccessBlock`. The client-family record itself does not manufacture
backend or server coverage; `GetPublicAccessBlock` now has that independent
coverage in [public-access-block.md](public-access-block.md). No external-
provider interoperability is claimed here. `GetBucketPolicy` has independent
backend and server coverage in [bucket-policy.md](bucket-policy.md).
`GetBucketPolicyStatus` additionally has a provider-owned limited constructor,
operation-last reusable initiation, typed Finish, and typed synchronous wait;
its established convenience overload waits on that same state machine. The
Flyology server now evaluates the exact persisted policy document and exposes
the resulting status through the same strict client decoder.
`GetBucketRequestPayment` now has the same provider-owned forms and uses its
exact prepared operation and strict payer decoder without interpreting billing
policy locally. `GetBucketAbac` has the same forms, preserves its
presence-sensitive status through a caller-bounded response, and selects no
mutation retry policy. `GetBucketAccelerateConfiguration` now completes this
provider-owned set while preserving its owner, requester-pays, status, and
request-charged fields.

## Pinned authority and complete inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
It records the six exact GET operations, request and output shapes, subresource
URIs, 200 success codes, all 26 request/output/nested members, member shapes,
wire locations, required flags, and the five relevant enum domains.

`tests/corpora/get-bucket-controls/operations.tsv` binds each generated
operation to its exact low-level preparer, executor, and high-level convenience
call. `members.tsv` records every ordered member. `vectors.tsv` records thirteen
reciprocal model, request, response, and transport contracts. The verifier
checks all of that evidence against the pinned generated model and both public
API layers:

```sh
python3 tools/verify-get-bucket-controls-preparation.py
```

## Request and response contracts

Every low-level preparer requires one valid bucket, supports path and
virtual-hosted addressing, projects the optional expected-owner precondition,
signs an empty body, and binds the exact generated operation. Only the
accelerate request projects `x-amz-request-payer`, whose sole modeled value is
the exact lowercase `requester`. Each executor rejects a request prepared for
another member of the family before entering HTTP. The composable
`GetBucketAbac`, `GetBucketAccelerateConfiguration`,
`GetBucketPolicyStatus`, and `GetBucketRequestPayment` low-level initiators
preserve their exact operation binding.

ABAC status preserves absent, `Enabled`, and `Disabled`. Accelerate status
preserves absent, `Enabled`, and `Suspended`. Request payment
preserves absent, `Requester`, and `BucketOwner`. Policy status preserves
presence independently from its Boolean value. Public-access block does the
same for `BlockPublicAcls`, `IgnorePublicAcls`, `BlockPublicPolicy`, and
`RestrictPublicBuckets`. Accelerate additionally preserves the optional exact
`x-amz-request-charged: requester` response header.

The five structured outputs use the strict shallow S3 XML parser. They accept
only the exact root and modeled children, no attributes, no duplicate or nested
fields, exact lowercase Boolean values, and either the established empty
namespace or `http://s3.amazonaws.com/doc/2006-03-01/`. Foreign namespaces,
unknown fields, malformed XML, DTDs, entities, and caller-limit violations are
rejected without a partial output. `GetBucketPolicy` instead returns the exact
same-response payload, including an empty payload, and applies the caller's
document-byte ceiling without inventing an independent policy limit.

Non-200 responses require one strict bounded S3 error. The composable ABAC,
accelerate, policy-status, and requester-payment parents also reject duplicate
or present-empty request-ID and host-ID response headers and apply
`Maximum_Document_Bytes` while bytes arrive. Object Storage selects no retry,
retains no caller input, releases the response before return, and creates no
detached helper task. Flyology.HTTP's
separately qualified one-shot stale pooled-connection recovery remains limited
to safe GET/HEAD exchanges with no request source and no response bytes.

## Corpus and coverage boundary

The deterministic corpus covers exact targets and signed headers,
cross-operation pre-admission rejection, every modeled successful output,
optional presence, raw policy byte boundaries, exact enum and Boolean
spellings, namespace compatibility, malformed XML, DTD/entity rejection, and
structured errors. The raw-loopback corpus performs all six high-level calls
over sequential signed real-socket responses under both native and Flyology
lightweight callers. It additionally exercises typed/composable ABAC,
accelerate, policy-status, and requester-payment success, consumed-operation
restart, exact prepared-operation mismatch, malformed singleton headers,
response overflow, and every normalized HTTP terminal kind; the root gate
repeats that corpus three times.

The machine ledger records `GetBucketPolicy`, `GetBucketPolicyStatus`, and
`GetPublicAccessBlock` as `covered / covered / covered / covered` using their
independent backend and server evidence. The other three operations remain
`missing / covered / missing / covered`; this client corpus does not
manufacture their backend persistence or server routes.

## Policy-status server boundary

The authenticated general-purpose-bucket route reads the exact bucket policy
already persisted by the shared backend contract. No configured policy returns
the distinct `NoSuchBucketPolicy` error. Malformed stored JSON fails closed as
`InternalError`; it is never reported as non-public.

For a valid policy document, the private evaluator follows S3's documented
public-policy rule: an Allow grant is non-public only when it is restricted by
a fixed principal or by fixed values for the documented trust keys. Source-IP
conditions additionally enforce valid IP syntax and the documented IPv4 `/8`
and IPv6 `/32` breadth thresholds. Wildcard role-session user IDs remain
public, duplicate condition members are rejected, and a public Allow remains
public even when another statement is fixed. Deny statements do not create a
public grant. This assessment reports policy status only; it does not enforce
the policy or claim a complete effective-access analysis.

The server corpus pins missing and malformed policy responses, public and
non-public grants, fixed-condition cases, mixed statements, Deny behavior,
expected-owner enforcement, exact query geometry, body rejection, and the
unsupported requester-pays header. The implementation corpus exercises the
same route over every maintained Flyology server/backend lane and restores the
policy fixture on both normal and exceptional exits.

## Gate evidence

The final warning-strict root gate passed 41/41 AUnit tests, the 132-case files
crash matrix, 320 checksum oracle vectors, 210 chunk boundaries, the strict
server application corpus, and three repetitions of the deterministic family
corpus and native/lightweight socket and TLS corpora. The operation inventory
verifier reported six operations, 26 request/output/nested members, five exact
enum domains, and thirteen reciprocal vectors; the 116-operation coverage
verifier and its negative oracle also passed. Repository integrity and
whitespace gates passed. GNATdoc produced a nonempty 430-file HTML API index;
none of the new typed or composable public declarations appears in its
undocumented-entity warnings.

The original client slice changed no SPARK proof unit. The later policy-status
server slice changes only the non-SPARK server application and shared
implementation/server corpora; its backend matrix is exercised through the
maintained root wrapper. Neither slice changes a public API profile or claims
directory-bucket or external-provider interoperability.
