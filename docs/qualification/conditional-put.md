# Conditional complete-object publication

`Put_Object` accepts an optional, HTTP-independent `Write_Conditions` value.
`If_None_Match = "*"` publishes a complete object only when the destination is
absent. `If_Match` replaces a complete object only when its strong entity-tag
list matches the current opaque `Object_Information.Entity_Tag`. Both fields
use the same bounded syntax evaluator as conditional copy publication.

The condition and publication share one backend boundary:

- memory evaluates against the current slot inside the protected commit;
- pure-files reads the current header and evaluates while holding the
  publication gate, immediately before atomic rename;
- SQLite evaluates inside the catalog gate and database transaction,
  immediately before the object-row upsert.

Every backend rejects malformed conditions before reading the source, then
consumes and validates the complete streaming source before the publication
boundary. Source exceptions, zero progress, cancellation, deadline,
declared-length failures, malformed conditions, and failed predicates leave
the prior body and complete `Object_Information` unchanged. SQLite removes
failed candidate payloads and retires the previous immutable payload only
after the catalog commit. The files backend rejects live and dangling
object-path symlinks without following them.

## Deterministic gates

`Conditional_Put_Conformance.Exercise` runs the same semantic oracle against
memory, files, and SQLite. It covers create-if-absent success and collision,
matching/stale/missing generation replacement, both predicates together,
malformed-before-read, exceptional and zero-progress sources, pre-call and
mid-stream cancellation/deadline, exact final body/metadata, and 32
barrier-synchronized two-writer races. Each race requires exactly one success
and one `Precondition_Failed`, then binds the stored body and metadata to the
reported winner.

The pure-files lane additionally reopens a power-loss-durable store, runs six
abrupt-process conditional replacement cases around its three durability
barriers, and tests live and dangling object-path symlinks. The SQLite lane
counts exactly the live immutable payload set after all failed and successful
replacements, then reopens the database and rechecks the committed generation.
The authenticated HTTP corpus covers success, 412 mapping, combined
predicates, and empty, malformed, and duplicate header rejection through the
real request-head parser and S3 application. The signed loopback socket corpus
runs create/collision/unchanged-read/replace/stale/final-read lifecycles from
both native and Flyology lightweight tasks.

The full pinned six-server implementation matrix ran three repetitions on
2026-08-22: RustFS 1.0.0-rc.3, SeaweedFS 4.43, MinIO
RELEASE.2025-09-07T16-13-09Z, and Flyology memory, files, and SQLite. Every
native and lightweight client lane passed the same conditional lifecycle with
exact final bytes and entity tags. No condition-specific reference divergence
or exclusion was observed.

The authorized SPARK gate proved the exact
`Evaluate_Object_Write_Conditions` target with 3/3 flow checks, then completed
one clean forced eight-unit widening with 625/625 checks (157 flow and 468
prover). Both level-0 reports used warnings as errors and output headers and
contain zero warnings, unproved or justified checks, and zero `Assume`
statements. Retained logs are under `obj/proof/logs/`.

## Client outcome boundary

This slice qualifies backend and server predicate atomicity only. The current
synchronous low-level client does not classify publication certainty and is
not the Flyology.DB production adapter. A transport failure after handoff may
therefore be ambiguous. The separately tracked composable HTTP/object-storage
client will distinguish `Not_Admitted` from `Possibly_Admitted` and will not
retry an ambiguously admitted conditional write. Flyology.DB reconciles an
ambiguous HEAD transition by reading the complete object bytes and generation;
a generation-only `HeadObject` observation is not sufficient.
