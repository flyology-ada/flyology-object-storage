# Private ACL server profile

This record covers the authenticated Flyology server profile shared by
`GetBucketAcl`, `GetObjectAcl`, `PutBucketAcl`, and `PutObjectAcl`. The store
has one stable tenant principal, bucket creation admits only private ownership
controls, and object publication admits only the private canned ACL. ACL state
is therefore derived from target existence and the authenticated principal;
it is not stored independently.

## Read projection

The two Get operations retain their existing behavior. `GetBucketAcl` checks
the bucket through `Head_Bucket`. `GetObjectAcl` checks the selected current,
null, or exact object generation through `Head_Object` and distinguishes a
missing bucket from a missing key with a read-only bucket check. A successful
response contains one canonical-user `FULL_CONTROL` grant for the stable
tenant principal.

The common backend conformance suite already proves bucket existence and
current, null, and retained exact object-generation selection for memory,
files, and SQLite. That substrate is the complete backend state used by the
derived ACL projection. Backend coverage does not mean arbitrary ACL
persistence exists.

## Idempotent private replacement

The two Put routes admit exactly one server mode: an empty request carrying
`x-amz-acl: private` and `Content-MD5` for that empty body. Authentication,
the exact `acl` query and optional operation identifier, expected-owner
validation, and the backend target check all complete before success. The
object route additionally binds an optional `versionId` and validates the
modeled requester-pays value. A requester-pays success emits the exact modeled
response header.

Because the selected target already has the immutable private profile, exact
HTTP 200 reports an idempotent validation and changes no backend state. A Get
before and after the request returns the same derived projection. The server
does not automatically replay a request and does not turn a later observation
into proof that an uncertain request caused state.

XML policy bodies, explicit grant headers, non-private canned ACL values, and
additional checksum algorithms are unsupported. Missing, duplicated,
conflicting, malformed, or incorrectly digested controls fail closed. These
limits avoid selecting grantee-resolution, permission-enforcement, email,
public-access, or ACL-storage policy.

## Client and qualification boundary

The generated `PutBucketAcl` client remains independently covered for its
modeled XML, canned, and grant-header request construction. The Flyology server
claim is narrower and covers only the exact private canned request. The
`PutObjectAcl` client remains model-only and `Not_Exposed`; server support does
not create a public Low_Level or Objects operation.

The focused verifier pins all four registry entries, the exact server route,
the private-mode and unsupported-mode corpus, target selection, and this
boundary. The maintained root wrapper remains the integration gate. This is
Flyology private-profile coverage, not general S3 ACL interoperability.
