# DeleteBucketCors client qualification

This record defines the conditional qualification boundary for the strict
bounded provider-owned composable, typed synchronous, convenience, backend,
and authenticated server paths for `DeleteBucketCors`. It does not claim
external-server interoperability or directory-bucket endpoint behavior.

## Pinned authority and inventory

The machine inventory is tied to botocore S3 model revision
`36c34f15391da01cd717c73c0fffa747c9889768` and service-model SHA-256
`429763d64912af5edae4c7a0f20a8ac3e6fecf734cde5fc465016bc8badcdef9`.
Request shape 146 has exactly two members: the required bucket URI label and
optional `ExpectedBucketOwner` header. The operation has no modeled success
output shape.

`tests/corpora/delete-bucket-cors/members.tsv` records both members and their
wire locations. `vectors.tsv` contains 12 reciprocal request, response,
transport, admission, error, header, and limit contracts. The verifier checks
the pinned upstream revision and hash, exact input/output shapes, generated
member count, ordered names and locations, canonical vector IDs, and both
directions of every member/vector reference:

```sh
python3 tools/verify-delete-bucket-cors-preparation.py
```

## Provider API and response contract

`Client.Low_Level.Prepare_Delete_Bucket_CORS` validates the bucket and bounded
owner precondition before transport, projects only the generated model's two
members, signs an empty payload, and supports both path and virtual-hosted
addressing. `Execute_Delete_Bucket_CORS` admits only a prepared request for
this operation and releases its response before return.

The prepared-request `Client.Low_Level.Delete_Bucket_CORS` initiator accepts
the exact signed operation plus a deliberately non-rewindable empty source and
one bounded response sink. `Client.Buckets.Delete_CORS` owns the limited
constructor, operation-last reusable procedure, operation state, and typed
`Finish`; the typed synchronous and established convenience overloads drive
that same state machine.

`Decode_Delete_Bucket_CORS_Response` accepts only status 204 with no response
body. Every other status requires a strict bounded S3 error document. Physical
request and host identifiers must each be absent or one nonempty control-free
value within the shared header bound; the executing path rejects duplicate
physical fields instead of collapsing them. The high-level
`Client.Buckets.Delete_CORS` exposes the same terminal completion or structured
rejection without retry, detached work, or retained caller input. A response-
observed modeled rejection proves non-application only for the maintained
conclusive status/code set; every ambiguous admitted failure remains outcome
unknown and requires caller-selected read reconciliation before retry.
Put-only checksum and request-body errors never classify a DeleteBucketCors
rejection as conclusive or as an invalid Delete request.

## Corpus and coverage boundary

The deterministic corpus covers path and virtual-hosted targets, owner
presence and omission, invalid buckets and headers before admission, exact
204 semantics, whitespace and nonempty success bodies, status alternatives,
five error status classes, malformed errors, identifier controls and one-past
bounds, and exact/one-past XML document limits.

The raw-loopback corpus adds signed exchanges per caller for high-level
success with exact owner binding, typed rejection with both identifiers,
independent duplicate request/host identifier rejection, present-empty
identifier rejection, malformed error rejection, and bounded oversized-error
rejection. It also exercises the typed synchronous call, limited constructor,
operation-last restart, exact prepared-operation rejection, and a typed
response-sink failure with outcome-unknown disposition. The same sequence runs
under native and Flyology lightweight task owners, and the root gate repeats it
three times.

The machine ledger records `DeleteBucketCors` as `covered / covered / covered /
covered`. Memory, pure-files, and SQLite backend evidence covers idempotent
deletion and missing-bucket behavior; authenticated server and socket evidence
covers exact routing and status. These maintained paths do not establish
external-provider compatibility.

## Gate evidence

The final warning-strict root gate passed 41/41 AUnit tests with zero failed
assertions or unexpected errors, the 126-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the deterministic DeleteBucketCors corpus and
native/lightweight socket and TLS corpora. The SQLite wrapper, catalog,
backend, reopen, and upgrade gate passed separately. The inventory verifier
reported two request members, no modeled success output, and 12 reciprocal
vectors; the 116-operation coverage verifier and its negative oracle also
passed.

The provider-owned scheduling path requires a fresh serialized exact-tree
`tools/prove.sh` campaign before publication even though its implementation is
outside the nine SPARK manifest units. Proof evidence is recorded only after
the shared formal lane is granted and the maintained wrapper and post-run host
audit both complete cleanly.

The focused generated-model documentation slice has a green maintained full
test wrapper and fresh region-scoped GNATdoc measurement. That measurement
removed exactly the one candidate-owned `Delete_Bucket_Cors_Operation` warning
and added none, without changing any Ada declaration token. Repository-wide
and selected-operation GNATdoc qualification remain blocked by pre-existing
warnings outside this declaration region. Every command in the maintained
`delete_bucket_cors` lane must still succeed before a qualification claim.
