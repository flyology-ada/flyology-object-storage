# ListObjectsV2 composable client qualification

`ListObjectsV2` is an existing bounded, read-only Objects-provider operation.
This qualification records its established contract; it does not add another
public API, cursor policy, resource limit, or retry rule.

The low-level layer prepares and signs the exact bucket, prefix, delimiter,
opaque continuation token, start-after key, maximum, encoding mode, expected
owner, and requester-pays controls. Complete decoding rejects duplicate or
empty singleton metadata and requires a successful listing to echo the exact
prepared request scope. URL-encoded key fields remain encoded in the modeled
result; callers decode a key before using it as a later request value, while
continuation tokens remain opaque.

The registry codec label intentionally omits `strict`: the established XML
decoder ignores unknown future elements while still rejecting malformed XML,
invalid modeled values, inconsistent request echoes, and invalid singleton
headers.

The provider exposes the existing operation-last `List_Page`, limited-root
constructor, typed `Finish`, and synchronous parameter-record overload. One
operation retains its HTTP client and optional cancellation owner by identity,
owns one response no larger than the maintained S3 XML document limit, drains
its hidden HTTP child before terminal completion, and releases prepared request
storage during `Finish`. Restart rejects owner replacement before preparing
another request and then clears retained response bytes; finalization clears
both prepared request and response storage.

Each completed page is an independent read-only service snapshot. A complete
bounded non-200 response is returned as a structured S3 rejection. The
provider maps reviewed authentication, authorization, missing-bucket, invalid
request, retryable service, and corrupt-response cases without authorizing an
automatic retry. There is no dedicated absence variant and no reconciliation
step because the operation does not mutate service state.

The focused gate owns the preparation verifier, warning-strict test build,
the maintained signed HTTP socket corpus, the 116-operation coverage ledger,
fresh selected public documentation, pinned-model repository checks, and the
final diff check. Documentation acceptance must resolve the ListObjectsV2
`List_Page` overloads and adjacent ownership and snapshot prose rather than a
same-named ListObjects v1 entity or a broad site token.
