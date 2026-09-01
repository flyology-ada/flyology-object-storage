# GetObjectAcl client and server qualification

This record qualifies the strict bounded provider-owned composable and typed
synchronous clients, corpus, and authenticated Flyology server route for
`GetObjectAcl`. It does not claim arbitrary ACL persistence, public grants,
requester billing, or external server interoperability. The companion private
server profile admits only an idempotent private canned-ACL replacement.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 271 requires `Bucket` and `Key`, and optionally contains
`VersionId`, `RequestPayer`, and `ExpectedBucketOwner`. Output shape 270
optionally contains `Owner` shape 499, nonflattened `Grants` list shape 300,
and `RequestCharged` response header shape 598.

The nested ACL graph is shared exactly with GetBucketAcl: each Grant shape 293
optionally contains Grantee shape 299 and Permission shape 514, and each
present Grantee requires XML-attribute member `Type` shape 696. The three type
values and five permission values remain exact. RequestPayer and RequestCharged
each have the sole value `requester`.

The reciprocal member and vector ledgers contain all 17 named members and 13
request, response, schema, security, header, limit, and transport contracts.
The verifier gates the exact operation scalars, list member and flattening,
XML-attribute position, and all four enum domains:

```sh
UV_CACHE_DIR=/private/tmp/fos-uv-cache uv run --python 3.13 -- \
  ./tools/verify-get-object-acl-preparation.py
```

## Provider-owned API and request contract

`Client.Low_Level.Prepare_Get_Object_ACL` validates the bucket, greedy object
key, bounded version selector, exact requester-pays value, and bounded owner
precondition before transport. It signs an empty body and projects only the
five modeled inputs. Path and virtual-hosted addressing preserve the exact
escaped key, `acl` flag, and optional `versionId` query value.

`Client.Low_Level.Get_Object_ACL` starts only the exact prepared operation into
the parent provider's bounded response sink; another prepared operation is
rejected before HTTP admission. `Client.Objects.Get_ACL` owns the limited
constructor, operation-last reusable initiation, operation state, and typed
`Finish`. The typed synchronous overload waits on that same state machine.
All forms consume one bounded same-response body and return typed ACL state or
a strict S3 error. There is no retry, helper task, retained borrowed input, or
second protocol engine. The caller-owned completion set, operation, signed
request, and response storage remain live through terminal drain and typed
Finish.

The established synchronous `Execute_Get_Object_ACL` remains the strict
low-level convenience form and uses the same prepared request and decoder.

## Response contract

The success result combines the qualified presence-preserving ACL codec with
the optional `x-amz-request-charged` header. An empty successful body preserves
outer-payload absence. A present policy independently preserves optional Owner
and AccessControlList wrappers, exact strings, ordered nonflattened grants,
exact grantee attributes and enums, and optional Grant children. No principal,
permission, or payer default is selected.

The physical requester-charged, request-ID, and host-ID headers must each be
absent or one nonempty control-free bounded value. RequestCharged admits only
`requester`. Duplicate, empty, altered, overlong, or control-bearing physical
values fail closed. Non-200 statuses return a strict bounded S3 error after the
same complete response is consumed.

The shared ACL parser rejects unknown, duplicate, misplaced, nested, or
attributed fields; missing or altered grantee types; altered permissions;
foreign or mixed namespaces; DTDs, entities, processing instructions,
malformed UTF-8; and caller-limit violations. Dynamic grant and string storage
is bounded by caller-selected XML limits because the pinned shapes specify no
independent maxima.

## Authenticated server profile

The path-style server accepts the exact `acl` subresource, an optional matching
SDK `x-id`, and an optional validated `versionId`. It authenticates before
request validation, rejects request bodies, enforces expected owner, admits
only the modeled `requester` payer spelling, and resolves current, null, or
opaque exact generations with `Head_Object`. An object miss is classified by a
read-only `Head_Bucket` call so absent buckets and absent keys retain their S3
error distinction. The server performs no requester billing and therefore
does not emit `x-amz-request-charged`.

The bound store has one stable tenant principal, and the qualified mutation
profile admits only private ACLs. The response therefore contains one
`CanonicalUser` `FULL_CONTROL` grant for that principal. It is derived
read-only state, not a persisted ACL. Other methods on the ACL subresource
return authenticated `NotImplemented` and cannot fall through to PutObject.

## Corpus and coverage boundary

The deterministic corpus covers both addressing styles; exact greedy-key and
version projection; omission and presence of all optional request members;
exact/one-past version, owner, response-header, success XML, and error XML
bounds; outer absence; populated wrappers; all grantee types and permissions;
strict schema and security faults; representative non-200 statuses; and
cross-operation execution rejection.

The raw-loopback corpus adds a signed versioned success with all request
headers, requester-charged success and rejection, outer absence, duplicate,
empty, and altered physical headers, malformed XML, and a body over the caller
limit. Provider coverage adds exact-operation pre-admission rejection, typed
synchronous success, limited construction, consumed restart, duplicate-header
failure, caller-selected response bounds, every modeled status/code mapping,
and every HTTP terminal failure across all admission certainties. The common
root gate repeats the full sequence under native and Flyology lightweight task
owners three times.

The machine ledger records `GetObjectAcl` as `covered / covered / covered /
covered`. Backend coverage is limited to current, null, and retained exact
generation selection used to derive the immutable private projection; no
arbitrary ACL is persisted. The server cell is gated by the strict
authenticated application corpus and a separate signed client over the real
Flyology memory-server socket; neither gate claims external-server
interoperability.

## Formal boundary

This provider extension changes only non-SPARK client, corpus, verifier, and
documentation units. Neither client package appears in the nine
`tools/prove.sh` manifest units, so the latest serialized result remains
applicable: 936/936 checks, 180 flow and 756 prover, with zero warnings,
unproved or justified checks, or `pragma Assume` statements.

## Gate evidence

The authenticated application corpus and real memory, files, and SQLite server
sockets passed, including native and Flyology lightweight signed clients and
the existing independent s5cmd guard. The standalone supervised server gate
also passed all three backend selections. The root test gate passed all 41
AUnit cases, the 132-case crash corpus, the 320-case checksum corpus, the
210-case multipart-checksum corpus, and three complete native/lightweight
deterministic and raw-loopback repetitions. The SQLite wrapper, catalog, and
backend gate also passed.

The pinned GetObjectAcl verifier reported all 17 modeled members, the one
nonflattened list, all 10 exact enum values, and all 13 reciprocal vectors.
The 116-operation coverage verifier and its negative oracle were green.

GNATdoc produced a 43,958-line log and a nonempty API index containing the
public GetObjectAcl parameters, low-level preparation and exact composable
initiator, provider result and operation types, three `Get_ACL` forms, typed
`Finish`, decoder, synchronous executor, and server `Handle` contract. The new
public declarations emitted no targeted warning, and the log contained no
internal error, `LANGKIT_SUPPORT.ERRORS`, infinite-recursion, or
bounded-channel diagnostic.
