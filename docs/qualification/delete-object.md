# DeleteObject qualification and boundaries

This slice qualifies the pinned S3 `DeleteObject` request and response model,
atomic current-object deletion, signed low- and high-level clients, and the
authenticated server route. The coverage ledger remains deliberately
`partial` for the server: object-version deletion, Requester Pays enforcement,
governance retention, and directory buckets are not implemented.

The complete modeled request surface is represented: bucket, key, MFA,
version ID, Requester Pays, governance-retention bypass, expected owner,
entity-tag condition, directory-bucket modification-time condition, and
directory-bucket size condition. Authentication precedes semantic errors.
Strict route parsing rejects bodies, duplicate or malformed controls, unknown
query members, invalid percent escapes, invalid bounds, and conflicting
conditions without mutation. Success is exactly bodyless HTTP 204. The clients
preserve the optional delete-marker, version-ID, and request-charged headers;
present-empty, duplicate, or malformed modeled response headers are invalid.
A structured HTTP 409 remains a typed S3 rejection, while a bodyless or
malformed 409 is an invalid response.

Memory, pure-files, and SQLite evaluate the object predicates and publish the
deletion under the same protected, publication-gate, or transactional
boundary. An ordinary missing unversioned key succeeds idempotently. A missing
key with `If-Match` is `Not_Found`; a mismatched existing object is
`Precondition_Failed`. Race lanes admit one atomic outcome and preserve exact
body/metadata on rejection. The server also rechecks the current versioning
and MFA Delete state at publication. A configured versioning or MFA Delete
state fails closed rather than pretending that delete markers or version
selection exist.

The files backend treats every required store, bucket, configuration, object,
and multipart namespace component as an exact nonsymlink kind before using it.
The adversarial corpus covers live and dangling links, valid external FOS
records, encoded object ancestors, multipart roots/uploads/manifests/parts,
missing or wrong-kind required roots, post-open root replacement, and recursive
listing/deletion. External sentinels and directory entry sets remain unchanged,
and a rejected bucket-root Put consumes no source bytes. These checks qualify
pre-existing corruption and same-process serialized operations; they are not a
descriptor-relative `openat`/`O_NOFOLLOW` defense against a hostile local
process swapping path components between validation and use.

Pure-files unlink is the publication point. A later directory-sync failure can
return `Backend_Unavailable` after the name is already gone, so a single caller
must reconcile the exact key/generation. A batch may expose a deleted prefix
after a later failure or cancellation. The deterministic barrier and
cancellation lanes gate both cases; no status or exception after publication is
documented as proof that deletion did not occur.

Low- and high-level DeleteObject calls deliberately use a known-empty,
non-rewindable HTTP source. This retains the empty signed payload, emits exact
zero-length streaming framing, and disables Flyology.HTTP's method-idempotent
stale-transport replay. The signed socket corpus primes a reused connection,
accepts one conditional DELETE, drops its response, and requires the next
request to be reconciliation HEAD. The call raises an outcome-unknown transport
exception; it never converts a replayed 404 into a definite predicate result.

The supported server semantics are ordinary unversioned deletion, atomic
`If-Match`, expected-owner policy, and pluggable fail-closed MFA authorization.
A present false governance-bypass value is a no-op. Version selection,
Requester Pays, and a true governance bypass return explicit modeled
`NotImplemented`; directory-only time/size predicates return
`InvalidArgument`. MFA requires secure transport and a bounded non-retained
verifier decision for the bucket root owner; missing, malformed, duplicate,
overlong, insecure, non-root, unavailable, null, and raising verifier cases
fail without mutation.

## Reproducible gates

```text
./tools/verify-coverage.sh
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
./tests/scripts/test-s3-matrix.sh
./tools/prove.sh
```

The root gate includes 33/33 AUnit tests, 88 abrupt-crash cases, signed native
and Flyology-lightweight application/socket corpora, exact body/header error
oracles, condition races, durability faults, dormant-condition bounds, and the
live/dangling namespace corpus. The SQLite gate repeats atomic conditions,
concurrent outcomes, persistence/reopen, and catalog migration coverage.

On 2026-08-22 the default three-repeat six-server campaign passed all 18 lanes:
digest-pinned RustFS, SeaweedFS, supplemental MinIO, and Flyology memory, files,
and SQLite, each three times. Every lane retained the independent s5cmd byte,
multi-delete, and cleanup oracles. The three Flyology servers are authoritative
for the strict modeled behavior. Narrow external divergences are explicit:
RustFS and SeaweedFS return 412 rather than AWS's documented 404 for
`If-Match` against a missing key, while the pinned MinIO release ignores
`If-Match` and deletes the mismatched object. These observations do not weaken
the Flyology server or client conformance gates.

The final source base also passed one clean serialized FSF GNATprove 16.1.0
forced-manifest run across eight units. With warnings as errors, all 625/625
checks proved (157 flow and 468 prover), with zero warnings, justified or
unproved checks, or `Assume` statements. Invocation-attributed output is
retained under `obj/proof/`.
