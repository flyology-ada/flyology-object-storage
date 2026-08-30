# HeadObject qualification and boundaries

This document records the maintained `HeadObject` evidence boundary.
Qualification remains conditional on the complete `head_object` lane
succeeding, including the repository-wide GNATdoc classifier. Directory-bucket
session semantics, access-point, Object Lambda, and S3 on Outposts routing are
not claimed.

The prepared request preserves every modeled HeadObject input. An explicit
nonempty `VersionId` must be a valid text-safe selector, and a successful
response must echo it byte-for-byte. An omitted selector observes whichever
generation is current at read time. A requester-charged response is accepted
only when the same prepared request admitted requester pays.

Successful responses are bodyless and require coherent framing, singleton
metadata, a quoted entity tag, a valid last-modified value, and compatible
checksum metadata. Duplicate, malformed, unsafe, mismatched-version, or
unrequested requester-charged responses fail closed as invalid responses.

The returned version and entity tag identify the generation observed by the
read. They do not prove the cause of a prior mutation, authorize automatic
replay, or upgrade mutation certainty. Checksum values are structurally
validated and exposed; HeadObject has no response payload to recompute.

The composable operation retains its HTTP client and cancellation-token owners
through terminal drain. Maintained socket evidence covers admitted
cancellation, typed `Finish`, drain completion, rejection of both owner
substitutions, and same-object restart. The synchronous function uses the same
prepared request and response-binding decoder.

Executable evidence is provided by direct low-level preparation and response
tests, the operation-local cancellation and invalid-binding socket cases, and
the maintained backend, server-application, and external-server corpora.

Reproduce the focused lane with the generated qualification plan for
`HeadObject`; the documentation command is extended mechanically with
`--operation HeadObject`.

The coverage ledger and exact region-scoped GNATdoc reduction of 96 prior
Low_Level warnings are measurement inputs, not a qualification claim by
themselves. The operation is qualified only when the complete maintained lane
exits successfully. Unrelated repository GNATdoc warnings currently keep that
global gate closed.
