# ListBuckets composable client qualification

The service-level `Client.Scoped.List_Buckets` operation composes the existing
complete ListBuckets request and response model without adding a second HTTP
engine. Initiation copies the complete presence-preserving parameter record,
prepares and signs the request, and retains bounded response storage through
typed `Finish`. Credentials are borrowed only while signing. The operation has
one hidden Flyology HTTP child, uses the caller's completion set and absolute
deadline, and can restart only after its prior result is consumed.

Complete-response decoding validates physical singleton request identifiers
and parses the entire response under `S3.XML.Default_Limits`. A successful
page cannot exceed the exact prepared maximum. An explicitly supplied prefix
must be echoed with the same presence and bytes, every returned bucket name
must remain in that prefix, and nonempty returned bucket-region metadata must
match an exact requested region. The continuation token remains opaque: it is
copied into the next prepared signed request and never interpreted. Each page
is an independent service snapshot; neither the composable operation nor its
synchronous wait retries automatically.

The strict normalization corpus covers every accepted service status/code
pair, every non-complete HTTP result across all admission certainties, and an
inconsistent success certainty. The signed native and lightweight socket
corpus covers fragmented success, exact structured rejection, wrong prefix
echo, duplicate singleton headers, cancellation before admission, and direct
restart through a returned continuation token. The existing convenience path
now waits on the same operation and retains its raising cancellation, timeout,
and transport contract.

The shared deterministic and six-provider matrix gates continue to exercise
the complete ListBuckets request/parser/server/backend path against RustFS,
SeaweedFS, supplemental MinIO, and Flyology memory, files, and SQLite. This
composable slice does not alter the existing atomic backend pagination or
external compatibility claim.

Reproduce the qualification with:

```text
./tests/scripts/test.sh
./sqlite/tests/scripts/test.sh
./tests/scripts/test-s3-matrix.sh
./tools/ci/check-repository.sh
./tools/build-api-docs.sh
./tools/prove.sh
```
