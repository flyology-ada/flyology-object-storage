# DeleteBucketCors client qualification

This record qualifies the strict bounded synchronous client and corpus for
`DeleteBucketCors`. It does not claim CORS configuration storage in any
Flyology backend, an authenticated Flyology server route, or external-server
interoperability.

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

## Synchronous API and response contract

`Client.Low_Level.Prepare_Delete_Bucket_CORS` validates the bucket and bounded
owner precondition before transport, projects only the generated model's two
members, signs an empty payload, and supports both path and virtual-hosted
addressing. `Execute_Delete_Bucket_CORS` admits only a prepared request for
this operation and releases its response before return.

`Decode_Delete_Bucket_CORS_Response` accepts only status 204 with no response
body. Every other status requires a strict bounded S3 error document. Physical
request and host identifiers must each be absent or one nonempty control-free
value within the shared header bound; the executing path rejects duplicate
physical fields instead of collapsing them. The high-level
`Client.Buckets.Delete_CORS` exposes the same terminal completion or structured
rejection without retry, detached work, or retained caller input.

## Corpus and coverage boundary

The deterministic corpus covers path and virtual-hosted targets, owner
presence and omission, invalid buckets and headers before admission, exact
204 semantics, whitespace and nonempty success bodies, status alternatives,
five error status classes, malformed errors, identifier controls and one-past
bounds, and exact/one-past XML document limits.

The raw-loopback corpus adds seven signed exchanges per caller: high-level
success with exact owner binding, typed rejection with both identifiers,
independent duplicate request/host identifier rejection, present-empty
identifier rejection, malformed error rejection, and bounded oversized-error
rejection. The same sequence runs under native and Flyology lightweight task
owners, and the root gate repeats it three times.

The machine ledger records `DeleteBucketCors` as `missing / covered / missing /
covered`. Client and corpus evidence do not manufacture backend persistence or
a server route. Promoting either remaining cell requires independent storage,
reopen/crash/concurrency, authenticated routing, and black-box tests.

## Gate evidence

The final warning-strict root gate passed 38/38 AUnit tests with zero failed
assertions or unexpected errors, the 88-case files crash matrix, 320 checksum
oracle vectors, 210 chunk boundaries, the strict server application corpus,
and three repetitions of the deterministic DeleteBucketCors corpus and
native/lightweight socket and TLS corpora. The SQLite wrapper, catalog,
backend, reopen, and upgrade gate passed separately. The inventory verifier
reported two request members, no modeled success output, and 12 reciprocal
vectors; the 116-operation coverage verifier and its negative oracle also
passed.

The latest serialized proof campaign remains the 2026-08-23 936/936 result:
180 flow checks and 756 prover checks across all nine manifest units, with
zero warnings, unproved or justified checks, or `pragma Assume` statements.
This slice changes only non-SPARK client, corpus, and documentation units; none
of the nine `tools/prove.sh` manifest units changed after that campaign, so a
redundant proof rerun was not performed.
