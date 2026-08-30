# PutBucketVersioning qualification boundary

`PutBucketVersioning` is exposed as
`Flyology.Object_Storage.Client.Buckets.Set_Versioning_Configuration`. The
caller supplies the origin, bucket, modeled versioning update,
expected-owner precondition, credentials, deadline, addressing style, and
optional cancellation source. The operation owns one serialized XML request
body and does not rewind or automatically replay it.

A complete validated `200` response reports
`Bucket_Versioning_Mutation_Completed`. Exact recognized non-mutating S3
rejections report `Bucket_Versioning_Mutation_Definitely_Not_Applied`, and
pre-admission cancellation reports
`Bucket_Versioning_Mutation_Cancelled_Before_Admission`. Possible or incomplete
admission, retryable responses, and malformed or oversized responses report
`Bucket_Versioning_Mutation_Outcome_Unknown`.

An unknown outcome is not retried automatically. The caller may reconcile by
calling `Get_Versioning` for the exact bucket and expected owner and comparing
each field explicitly present in the serialized mutation. A
`Versioning_Unconfigured` or `MFA_Delete_Unconfigured` value preserves that
field, so it is not a reconciliation comparison target before retry.

The focused socket evidence covers typed success, the reviewed XML body shape,
presence of generated `Content-MD5`, ordinary same-operation restart,
cancellation, and native and lightweight admitted cancellation followed by
`Wait_All`, typed `Finish`, explicit transport drain acknowledgement,
retained-owner rejection, and same-operation restart.

The boundary excludes directory buckets, automatic S3 Express control
endpoint selection, access-point and Outposts routing, the model-documented
propagation interval, downstream object-version publication and listing
semantics, and external-provider compatibility. Client cancellation cannot
roll back a completed update.

The maintained lane runs the independent preparation verifier, warning-strict
test build, signed loopback corpus, 116-operation coverage verifier, fresh
selected API documentation, pinned-model repository gate, and final diff
check. Any repository-owned documentation warning or missing subgate prevents
a qualification claim.
