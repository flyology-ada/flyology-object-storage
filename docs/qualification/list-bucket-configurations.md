# Bucket configuration listing qualification

The coherent listing boundary covers `ListBucketAnalyticsConfigurations`,
`ListBucketIntelligentTieringConfigurations`,
`ListBucketInventoryConfigurations`, and
`ListBucketMetricsConfigurations`. Each operation uses the existing strict,
bounded REST/XML client path and the same HTTP-independent backend page model.

## Page and cursor contract

An existing bucket with no retained configurations returns an exact HTTP 200
empty page. A missing bucket returns exact HTTP 404 `NoSuchBucket`. There is
no per-configuration absence result in a list response.

The maintained server orders retained request identifiers by exact bytewise
lexical order. A modeled payload `Id` is data inside the retained document and
does not select, order, or page storage. Continuation tokens remain opaque at
the public API and are bound internally to the exact bucket and configuration
family. An empty token supplied by the caller remains explicitly present in
the response.

Each backend call returns one atomic snapshot current at that call. Following
a returned token is a separate caller-selected read. It neither freezes a
cross-page snapshot nor proves completeness across concurrent writes, and the
client performs no automatic page request. A token resolves only while the
configuration that supplied its ordering marker remains retained; deleting
that marker invalidates the token.

The pinned model documents at most 100 configurations per page for Analytics,
Inventory, and Metrics. It states no page maximum for Intelligent-Tiering.
The maintained Intelligent-Tiering server therefore uses the existing 1,000
configuration per-family storage ceiling and may truncate earlier to preserve
the existing bounded XML document budget. This is not an AWS page-size
compatibility claim. Every family fails closed rather than exposing a partial
configuration when a complete entry cannot fit the response budget.

## Evidence and exclusions

The memory, files, and SQLite backends use the same bounded page contract and
exact identifier order. Server application evidence distinguishes list
requests from the existing named Get operations, rejects malformed or
cross-bucket and cross-family cursors, preserves large binary identifier
cursors, rejects a cursor after its marker is deleted, and covers empty,
complete, truncated, and missing-bucket replies.
The generated signed socket adapters cover client request encoding, strict
parsing, singleton headers, explicit empty-token presence, cancellation, and
same-object restart.

Analytics and Intelligent-Tiering remain unsupported for directory buckets.
Inventory and Metrics do not claim automatic S3 Express control-endpoint or
path-style rewriting, including directory-bucket `ExpectedBucketOwner`
behavior. Analytics report generation, Intelligent-Tiering transitions,
Inventory report generation, CloudWatch emission, and external-provider
ordering remain outside this server boundary.

The focused lane runs the independent source/model verifier, the registry
negative oracle, warning-strict build, all four signed socket adapters, server
and HTTP socket corpora, coverage, selected-operation API documentation, the
pinned-model repository gate, and a clean diff. These checks are conditional
evidence only until every command in the maintained lane succeeds; this page
does not independently claim qualification.

Reproduce the focused lane with:

```text
FLYOLOGY_S3_SERVICE_MODEL=/path/to/service-2.json \
  uv run --python 3.13 -- tools/s3-operation.py qualify \
  ListBucketAnalyticsConfigurations \
  ListBucketIntelligentTieringConfigurations \
  ListBucketInventoryConfigurations \
  ListBucketMetricsConfigurations
```
