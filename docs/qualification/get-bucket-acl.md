# GetBucketAcl client and server qualification

This record qualifies the strict bounded synchronous client, corpus, and
authenticated Flyology server route for `GetBucketAcl`. It does not claim ACL
persistence in a Flyology backend, ACL mutation, public grants, or external
server interoperability.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 226 has required `Bucket` and optional `ExpectedBucketOwner`.
Output shape 225 optionally contains `Owner` shape 499 and nonflattened
`Grants` list shape 300. Each Grant shape 293 optionally contains Grantee
shape 299 and Permission shape 514. Grantee has four optional text elements
and required XML-attribute member `Type` shape 696.

The exact type values are `CanonicalUser`, `AmazonCustomerByEmail`, and
`Group`. The exact permission values are `FULL_CONTROL`, `WRITE`,
`WRITE_ACP`, `READ`, and `READ_ACP`. The reciprocal member and vector
ledgers contain all 13 named members and 13 request, response, schema,
security, header, limit, and transport contracts. The verifier also gates the
list member, nonflattened flag, XML-attribute position, and both enum domains:

```sh
python3 tools/verify-get-bucket-acl-preparation.py
```

## XML attribute boundary

The shared bounded SAX facade now exposes an additive default-null
`Element_Attribute` callback after structural details and before the owning
start-element callback. It copies the owning element name, resolved attribute
namespace, local name, and normalized value while XMLAda symbols are valid.
Existing handlers remain source compatible and need no override.

The ACL codec requires exactly one `xsi:type` on each present Grantee, with
namespace `http://www.w3.org/2001/XMLSchema-instance`, local name `type`,
and one exact pinned enum value. Other attributes, an unqualified `type`,
wrong namespaces, duplicates, and extra attributes fail closed. The existing
document-byte limit bounds attribute storage; no new resource default or
independent ceiling is introduced.

## Synchronous API and response contract

`Client.Low_Level.Prepare_Get_Bucket_ACL` reuses the strict common
bucket-control projector. It validates the bucket and bounded owner before
transport, signs an empty body, projects only the two modeled inputs, and
supports path and virtual-hosted addressing.

`Execute_Get_Bucket_ACL` admits only the exact prepared operation and uses
the established synchronous bucket-control HTTP engine to consume one bounded
same-response body. It returns a typed policy or strict S3 error. There is no
retry, helper task, retained borrowed input, or second protocol engine.

An empty successful body preserves optional outer-payload absence. A present
policy independently preserves optional Owner and AccessControlList wrappers.
Owner strings, Grantee, Permission, and grantee strings retain presence and
empty text. Grants retain wire order, and an empty Grant is accepted because
both modeled members are optional. No principal or permission default is
selected. Dynamic grant and string storage is bounded by caller-selected
shared XML limits because the pinned shapes specify no independent maxima.

The parser rejects unknown, duplicate, misplaced, nested, or attributed
fields; missing or altered grantee types; altered permissions; foreign or
mixed namespaces; DTDs, entities, processing instructions, malformed UTF-8;
and caller-limit violations. Diagnostic request and host IDs must each be
absent or one nonempty control-free bounded value.

## Authenticated server profile

The path-style server accepts only the exact `acl` subresource with the
optional matching SDK `x-id`, authenticates before request validation, rejects
request bodies and RequestPayer, enforces the expected-owner precondition, and
checks bucket existence through the backend. Other methods on the ACL
subresource return authenticated `NotImplemented` and cannot fall through to
ordinary bucket mutation routing.

The server's existing application contract binds one store to one stable
tenant principal. CreateBucket accepts only `private` and
`BucketOwnerEnforced`, while object publication accepts only the `private`
canned ACL. The server therefore derives a single `CanonicalUser`
`FULL_CONTROL` grant for that principal. This is a read projection of the
qualified private-only profile, not stored ACL state or a general ACL engine.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles; exact/one-past owner
and diagnostic bounds; outer absence; empty and populated wrappers; all
grantee types and permissions; empty optional strings and Grant; attribute
namespace/name/value/multiplicity faults; strict schemas and namespaces;
representative non-200 statuses; cross-operation rejection; and exact/one-past
success and error XML byte, depth, element, and text limits.

The raw-loopback corpus adds signed nested success, absence, typed rejection,
duplicate and empty physical diagnostic headers, malformed XML, and a body
over the caller limit. The common root gate repeats the entire socket sequence
under native and Flyology lightweight task owners three times.

The machine ledger records `GetBucketAcl` as `missing / covered / covered /
covered`. The backend cell remains missing because no ACL is persisted. The
server cell is gated by the strict authenticated application corpus and a
separate signed client over the real Flyology memory-server socket; neither
gate claims external-server interoperability.

## Formal boundary

This server extension changes only non-SPARK routing, corpus, and
documentation units. None of the nine `tools/prove.sh` manifest units changes,
so the latest serialized 2026-08-25 result remains applicable:
936/936 checks, 180 flow and 756 prover, with zero warnings, unproved or
justified checks, or `pragma Assume` statements.

## Gate evidence

The authenticated application corpus and real memory, files, and SQLite server
sockets passed, including native and Flyology lightweight signed clients and
the existing independent s5cmd guard. The standalone supervised server gate
also passed all three backend selections. The root test gate passed all 41
AUnit cases, the 132-case crash corpus, the 320-case checksum corpus, the
210-case multipart-checksum corpus, and three complete native/lightweight
deterministic and raw-loopback repetitions. The SQLite wrapper, catalog, and
backend gate also passed. The pinned-model verifier, 116-operation coverage
verifier, and coverage negative oracle were green.

GNATdoc produced a 43,716-line log and a nonempty API index containing the ACL
codec, low-level GetBucketAcl API, and changed server `Handle` contract. That
contract emitted no targeted warning, and the documentation log contained no
internal error, `LANGKIT_SUPPORT.ERRORS`, infinite-recursion, or bounded-
channel diagnostic.
