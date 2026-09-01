# ListDirectoryBuckets local empty-catalog profile

The generated client retains its strict bounded ListDirectoryBuckets request,
response, cancellation, and ownership behavior. The local server adds a
separate, deliberately empty directory-bucket compatibility profile without
changing the backend model or exposing general-purpose buckets as directory
buckets.

The backend catalog stores bucket name and creation time, but has no directory
bucket kind. Local CreateBucket already rejects directory-bucket configuration.
For a recognized directory listing request, the server therefore calls the
existing List_Buckets backend operation only to preserve cancellation,
deadline, and backend-availability behavior, discards the general-purpose
page, and returns an empty `<ListDirectoryBucketsOutput/>` document.

The local service-root router distinguishes this operation when the query has
`max-directory-buckets` or the exact `x-id=ListDirectoryBuckets` discriminator.
The optional maximum is validated against the pinned model's exact 0–1000
range; this wire bound is not a local storage capacity. An empty service-root
query remains ListBuckets. A continuation token is rejected because this
empty profile never issues one. Duplicate, malformed, unknown, and
body-bearing requests are rejected.

This profile does not claim nonempty directory-bucket storage, S3 Express
endpoint discovery, availability-zone semantics, directory naming or ARN
validation, or external-provider interoperability. The qualification lane
retains the generated client socket evidence and adds the local server corpus
and independent registry-oracle coverage. Qualification remains conditional
on every command in that lane succeeding.
