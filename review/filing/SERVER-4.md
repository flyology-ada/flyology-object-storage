Title: CompleteMultipartUpload returns a path in <Location> where the model documents the URI of the new object
Labels: bug
Refs: none

## Summary

Every successful CompleteMultipartUpload returns `<Location>/bucket/key</Location>`. The pinned model documents that member as the URI that identifies the newly created object, and a value with no scheme is a relative reference, not a URI. A caller that treats the member as an address has to know the endpoint out of band to use it, and cannot compare it with what AWS or another S3 server returned for the same upload.

## Problem

Commit `5fe6e3e`.

The completion result is built with a path (`src/flyology-object_storage-server-s3_applications.adb:13192-13197`):

```ada
                        Response : Multipart.Complete_Multipart_Upload_Result
                          := (Location => US.To_Unbounded_String
                                ("/" & Bucket & "/" &
                                 Encoding.URI_Encode
                                   (Key, Encode_Slash => False)),
                              Bucket => US.To_Unbounded_String (Bucket),
                              Key => US.To_Unbounded_String (Key),
```

and the serializer emits it verbatim (`src/flyology-object_storage-s3-multipart.adb:1125`):

```ada
      Append_Optional (Content, "Location", US.To_String (Value.Location));
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) documents `shapes.CompleteMultipartUploadOutput.members.Location` as:

```
{'shape': 'Location'}
The URI that identifies the newly created object.
```

The `Location` shape is a plain string, so the model constrains only the documented meaning, not a syntax. RFC 3986 section 3 requires a scheme in a URI, so `/mpu-bucket/dir/object.bin` is a relative reference and does not identify the object on its own.

The crate documents nothing about this member. The CompleteMultipartUpload row of the compatibility matrix (`docs/compatibility/s3.md:70`) claims the operation without excluding the result address:

```
| CompleteMultipartUpload | memory, files, SQLite | complete typed composable and synchronous clients; authenticated general-purpose path-style server | atomic condition/size/checksum completion, strict signed control and body-boundary corpus, 46-case admission/certainty oracle including embedded HTTP-200 errors, ...
```

No existing test asserts either form.

The reason this is not a mechanical fix is that the server has no scheme to build a URI from. `Apps.Request_Scheme` is `Plain_HTTP` for every request this repository can produce, because neither the runtime nor the test harness passes a `Scheme` to `Apps.Create` (`server/src/flyology_object_storage_server_runtime.adb:168-170`):

```ada
            X : Apps.Exchange := Apps.Create
              (Request, Client, Peer, Cancellation,
               HTTP.Request_Deadline (Client));
```

and `tests/src/s3_server_harness.adb:89-91`:

```ada
         X : Apps.Exchange := Apps.Create
           (Request, HTTP, Peer, Cancellation,
            HTTP_Server.Request_Deadline (HTTP));
```

## What happens now

Spike: the program below runs a one-part multipart upload on `/mpu-bucket/dir/object.bin` and asserts that `<Location>` is an absolute URI naming the object. Controls confirm the completion is 200 and that `<Bucket>`, `<Key>` and the composite `<ETag>` are present and correct, and that `<Location>` at least names the object.

```ada
      Where : constant String := Element_Text (Doc, "Location");
...
      Check (Contains (Where, "://"),
             "CompleteMultipartUpload <Location> is an absolute URI " &
             "(the model documents 'The URI that identifies the newly " &
             "created object')");
      Check (Contains (Where, "dir/object.bin"),
             "CONTROL: <Location> at least names the object");
```

Output, exit status 1:

```
  ok: fixture: CreateBucket /mpu-bucket
  ok: fixture: CreateMultipartUpload returns an UploadId
  ok: fixture: UploadPart is 200
  -- CompleteMultipartUpload status 200
  --    body <?xml version="1.0" encoding="UTF-8"?><CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Location>/mpu-bucket/dir/object.bin</Location><Bucket>mpu-bucket</Bucket><Key>dir/object.bin</Key><ETag>"dba2eb2ed95ff6ac73da0388b617482b-1"</ETag><ChecksumCRC64NVME>6d18xdZ10Zg=</ChecksumCRC64NVME><ChecksumType>FULL_OBJECT</ChecksumType></CompleteMultipartUploadResult>
  --    <Location> = [/mpu-bucket/dir/object.bin]
  ok: CONTROL: CompleteMultipartUpload is 200
  ok: CONTROL: the result names the bucket
  ok: CONTROL: the result names the key
  ok: CONTROL: the result carries a composite ETag
  FAILED: CompleteMultipartUpload <Location> is an absolute URI (the model documents 'The URI that identifies the newly created object')
  ok: CONTROL: <Location> at least names the object
BUG REPRODUCED: 1 failed expectation(s)
```

Every other member of the result document is correct; only `<Location>` is a path.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

`<Location>` should identify the newly created object, which is what the pinned model documents for that output member. Either it carries an absolute URI, or the crate states in `docs/compatibility/s3.md` that it deliberately returns a path and why.

## Suggested treatment

Building an absolute URI requires choosing where the scheme and authority come from, which is externally visible policy, so this needs a maintainer decision:

- Derive the address from the request: `http` or `https` from `Apps.Request_Scheme` plus the signed `Host` header, giving `scheme://host/bucket/key`. This needs no new configuration, but it makes a response member depend on a client-supplied header, and it always yields `http://` for this repository's own server, since `Apps.Create` is never given a `Scheme` at either call site above.
- Add a configured public base URI to the S3 application's construction, used as the prefix. This produces a correct address behind a TLS terminator or a proxy, and it is a new public configuration value with a default to choose, which the "Ada interface values" section of `AGENTS.md` reserves for the maintainer.
- Keep the path deliberately and document it as a boundary in `docs/compatibility/s3.md`, next to the CompleteMultipartUpload row at `:70`. Nothing changes on the wire and the divergence from the model's documented meaning stays, disclosed.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, in the CompleteMultipartUpload block, asserting whichever form is chosen for `<Location>` on an ordinary one-part completion. The spike is the test; no existing assertion has to change, because none covers the member.

## Severity

Every multipart completion returns a value of the wrong form in a modelled output member. Nothing fails today: aws-cli and boto3 surface the member verbatim without dereferencing it, and the rest of the completion document is correct, so the effect is confined to a caller that stores or resolves the address, or a conformance comparison against another S3 server. It affects every user of multipart upload, and the response is otherwise a success. Deterministic.
