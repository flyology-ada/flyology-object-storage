# GetObject qualification and boundaries

This document records the maintained `GetObject` evidence boundary for whole
and single-range reads. Qualification remains conditional on the complete
`get_object` lane succeeding, including the repository-wide GNATdoc
classifier. Directory-bucket session semantics, access-point, Object Lambda,
S3 on Outposts, multipart responses, and multi-range responses are not
claimed.

The prepared request preserves all 21 modeled request members. An explicit
nonempty `VersionId` must be a valid text-safe selector, and a successful
response must echo it byte-for-byte. An omitted selector observes whichever
generation is current at read time. A requester-charged response is accepted
only when the same prepared request admitted requester pays. Physical
singleton response metadata is rejected when duplicated.

Whole reads require HTTP 200, one exact strong entity tag, one content length,
and a body whose received size equals that length. Single-range reads require
HTTP 206, the exact requested strong entity tag, a content length equal to the
received bytes, and one response interval that resolves against the requested
bounded, open-ended, or suffix range. Invalid or incomplete responses clear
the destination and expose no object bytes.

Checksum mode requests and structurally validates the modeled checksum
headers. The values are exposed with the response metadata, but this client
slice does not recompute them over the returned payload. Exact version and
entity-tag observations identify the generation read; they do not prove the
cause of a prior mutation and do not authorize automatic replay or a mutation
certainty upgrade.

The composable whole-read operation retains its HTTP client, destination, and
cancellation-token owners through terminal drain. Maintained socket evidence
covers admitted cancellation, typed `Finish`, drain completion, rejection of
all three owner substitutions, and same-object restart. Synchronous whole and
range functions wait on the same composable drivers.

Executable evidence is provided by:

- direct low-level preparation and response-decoding tests for request fields,
  singleton headers, version safety, body length, and error mapping;
- `s3_http_socket_corpus` for explicit-version success, missing, mismatched,
  duplicate, control, and DEL version responses, requester-pays binding,
  whole and range response binding, and cancellation ownership;
- `range-get.tsv` and its maintained verifier negative oracle for generation
  and range geometry; and
- the memory, files, SQLite, server-application, and external-server corpora
  for current and exact-generation read behavior.

Reproduce the focused lane with the generated qualification plan for
`GetObject`; the documentation command is extended mechanically with
`--operation GetObject`.

The coverage ledger and the exact region-scoped GNATdoc reduction of 89 prior
warnings (65 Low_Level and 24 Objects) are measurement inputs, not a
qualification claim by themselves. The operation is qualified only when the
complete maintained lane exits successfully. Unrelated repository GNATdoc
warnings currently keep that global gate closed.
