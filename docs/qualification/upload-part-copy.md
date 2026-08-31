# UploadPartCopy qualification

This record ties the existing UploadPartCopy backend, client, server, and
corpus evidence to one focused registry lane. It covers authenticated
general-purpose path-style requests and does not add a new public API,
capacity, retry, or source-version default.

## Request and response binding

The prepared request retains the exact destination bucket, key, upload ID,
part number, `x-amz-copy-source` value, optional byte range, source conditions,
expected owners, requester token, and source and destination SSE-C groups. Any
source version is caller-selected inside the exact copy-source value. The
client does not infer a current-version selector.

A complete response requires one bounded `CopyPartResult`, strict singleton
headers, and a requester-charge value consistent with the admitted request.
Malformed, duplicated, present-empty, oversized, or inconsistent response
data is invalid rather than normalized as success.

## Certainty and lifecycle

Only a complete validated HTTP 200 copied-part response reports `Published`.
An exact precondition rejection reports `Precondition_Failed`; recognized
authentication, authorization, not-found, invalid-request, and unsupported
responses report `Definitely_Not_Published`. Definite non-admission and
pre-admission cancellation remain distinct. Possible or incomplete admission,
embedded errors, retryable responses, and malformed replies remain
`Outcome_Unknown`.

The library never automatically replays UploadPartCopy. An unknown result
requires read-only ListParts for the exact destination upload and part before
a caller-selected retry or completion decision. That observation does not
prove which concurrent writer staged indistinguishable content; causal
attribution requires caller serialization or independent content binding.

The composable operation owns one HTTP child, drains typed `Finish`, rejects
HTTP-client or cancellation-token owner substitution, clears prepared and
response storage at terminal completion and finalization, and supports
same-object restart only after the prior operation is consumed.

## Evidence boundary

Memory, files, and SQLite cover atomic ranged copy-part publication and
preservation on failed conditions. The authenticated server and raw socket
corpora cover exact copy-source and range transport, success and embedded
errors, response singleton validation, lost-response uncertainty,
cancellation, direct restart, and structured rejection.

The `UploadPartCopy` registry lane is conditional on every maintained command
succeeding. The generated-model GNATdoc association is a region-scoped warning
measurement only; repository-wide and selected GNATdoc qualification remain
blocked by pre-existing warnings outside that declaration region.
