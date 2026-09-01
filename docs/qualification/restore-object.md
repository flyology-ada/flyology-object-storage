# RestoreObject active-tier compatibility profile

RestoreObject is covered only for the maintained local-server active-tier
boundary. The operation remains Not_Exposed: there is no public Low_Level or
Objects request, synchronous wrapper, composable operation, Finish path, or
client GNATdoc claim.

The authenticated POST object?restore route accepts an optional exact
versionId and the modeled x-id=RestoreObject. It validates query and header
multiplicity, expected-owner and requester-pays values, Content-MD5, and SDK
checksum selector/value coupling before inspecting storage. Its private,
entity-safe XML receiver uses the shared S3.XML.Default_Limits. Empty and
direct Tier-only speed-up requests are accepted and validated. A regular
request supplies a positive lexical Days value and may name Standard, Bulk, or
Expedited directly or inside GlacierJobParameters.

Select, OutputLocation, Description, unknown members, duplicate members,
attributes, foreign namespaces, and malformed XML are rejected. This
validation introduces no public Days or Tier default and no new resource
bound.

The route first checks the bucket, then performs the existing atomic current,
null, or exact-version Head_Object selection. A missing bucket, key, or version
remains distinct. Every object in the maintained memory, files, and SQLite
backends is active-tier, so an existing selection returns only the modeled
403 ObjectAlreadyInActiveTierError. The server never reports 200 or 202,
schedules a restore, or persists archival state.

The provider-neutral lookup substrate is exercised by
versioned_object_conformance.adb in the memory, files, and SQLite suites. The
signed application corpus pins routing, authentication-adjacent controls,
checksums, XML rejection, version binding, missing-resource classification,
and the active-tier error.

Qualification remains conditional on every command in the single
restore_object lane succeeding. This tranche does not claim successful
restore, external-provider interoperability, automatic replay, causal
reconciliation, or proof that a later HeadObject observation was caused by a
lost RestoreObject request.
