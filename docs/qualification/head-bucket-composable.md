# Composable HeadBucket qualification

`Flyology.Object_Storage.Client.Buckets.Head` provides the owner-driven
bodyless bucket probe. Its operation-last procedure restarts a consumed operation only
with its retained HTTP client and cancellation owner. The operation owns its
prepared signed request through terminal drain and retains no borrowed bucket,
owner-precondition, credential, or region input after initiation.

`Decode_Head_Bucket_Complete_Response` is shared by blocking and composable
paths. It rejects response bodies, transfer coding, duplicate modeled singleton
headers, invalid optional Boolean metadata, invalid region/location syntax, and
oversized modeled values. Complete bodyless rejections preserve request and
host identifiers.

The strict normalization corpus covers successful response observation,
redirect and invalid-request statuses, authentication, authorization, absence,
transient service responses, unsupported statuses, every expected composable
HTTP terminal kind, and every admission-certainty value. The signed raw-socket
corpus runs on native and Flyology lightweight tasks and covers exact owner
binding, modeled success metadata, rejection identifiers, duplicate singleton
headers, direct restart, pre-admission cancellation, and deadline expiry. The
established convenience call waits this same state machine and retains its
raising transport behavior and signing-region fallback.

Provider compatibility remains gated by the existing HeadBucket black-box
matrix across RustFS, SeaweedFS, supplemental MinIO, and Flyology memory,
files, and SQLite. The composable change introduces no backend or server
capability claim.
