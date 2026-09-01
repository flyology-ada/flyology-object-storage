# Object annotation backend and server evidence

This record covers the shared backend and authenticated server implementation
for `DeleteObjectAnnotation`, `GetObjectAnnotation`,
`ListObjectAnnotations`, and `PutObjectAnnotation`. It is conditional: each
operation retains its own qualification lane, and no operation is qualified
until every command in that operation's maintained lane succeeds.

## Backend contract

The HTTP-independent `Object_Annotation_Backend` interface streams annotation
bytes through `Byte_Source` and `Byte_Sink`. Information returned before or
after streaming includes the exact selected object version, byte count,
modification time, unquoted lowercase MD5 entity tag, and computed checksum.
Missing annotations use the dedicated presence result rather than a global
status value.

Put validates the expected checksum and object condition before publication.
Delete evaluates the same canonical object condition before removal. Explicit
versions select that exact parent generation; an omitted selector observes or
mutates the generation current at the operation boundary. List returns a
live-state page ordered by bytewise UTF-8 annotation name after an exact
backend lexical cursor. The S3 boundary, not the backend, owns opaque
scope-bound continuation tokens.

Memory, pure-files, and SQLite implement the same interface. Pure-files keeps
annotation payloads in external files. SQLite schema version 23 records
annotation metadata and external payload references rather than placing large
payloads in BLOB values. Copy defaults to `Copy_Annotations`; the explicit
`Exclude_Annotations` directive publishes the destination without source
annotations.

## Authenticated S3 boundary

The S3 application authenticates the four exact annotation operations and
binds bucket, key, annotation name, optional version, checksum, and
`ObjectIfMatch` inputs before backend dispatch. Put checks the request body and
selected checksum before publication. Get streams the selected payload and
metadata. List encodes and validates an opaque scope-bound continuation token.
Delete reports missing and removed annotations without replaying a mutation.

CopyObject applies the parsed annotation directive to actual destination
state: COPY preserves the selected source generation's annotations, while
EXCLUDE publishes none. The maintained backend and server corpora exercise
payload, checksum, version, list, missing, condition, and copy-directive
behavior across the implementations.

## Client and qualification boundary

Client coverage is intentionally asymmetric. DeleteObjectAnnotation and
ListObjectAnnotations retain their existing public client and corpus evidence.
GetObjectAnnotation and PutObjectAnnotation remain generated-model-only on the
client: `Not_Exposed` is a registry sentinel, not an Ada declaration, and no
public client streaming operation, response binding, admission result, or
GNATdoc qualification is claimed for either operation.

Each operation-specific qualification lane runs the shared backend/server
verifier in addition to its existing client/model, build, corpus, coverage,
documentation, repository, and diff gates. Passing the shared verifier alone
does not qualify any operation. External-provider annotation interoperability,
snapshot isolation across list pages, and causal proof from a later read are
not claimed. Generated coverage outputs remain stale until the separately
controlled generation step materializes this source registry change.
