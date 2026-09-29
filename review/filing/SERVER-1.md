Title: Operations the model marks requestChecksumRequired demand Content-MD5, so stock aws-cli v2 and boto3 are refused
Labels: bug
Refs: none

## Summary

For every operation the pinned botocore S3 model marks `httpChecksum.requestChecksumRequired: true`, the server's preflight requires exactly one syntactically valid `Content-MD5` and answers 400 `InvalidRequest` before it reaches the verifier that already validates the `x-amz-sdk-checksum-algorithm` / `x-amz-checksum-<alg>` group over the same body. A current AWS SDK satisfies that trait with the checksum group and sends no `Content-MD5` at all, so an unmodified `aws s3api delete-objects`, `put-bucket-versioning`, `put-bucket-tagging` or `put-object-tagging` is refused, and object tagging answers 501 to any request that carries a flexible checksum. DeleteObjects is unreachable from a model-generated client under any client configuration, because `DeleteObjectsRequest` has no `ContentMD5` member to set.

## Problem

Commit `5fe6e3e`.

DeleteObjects computes the flexible-checksum verdict and then ignores it, because the `Content-MD5` gate is the first arm of the chain (`src/flyology-object_storage-server-s3_applications.adb:17672-17684`):

```ada
                  Checksum_Status : constant Checksum_Verification :=
                    Verify_Checksum;
               begin
                  if MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      ((if MD5_Count = 1
                        then Apps.Request_Header (X, "content-md5") else ""),
                       16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "DeleteObjects requires one valid Content-MD5 header",
                        Target_Text);
```

`Verify_Checksum` (`:17617-17670`) computes and compares the modelled checksum over the exact admitted body, and `Checksum_Status` is consulted only in a later arm of the same chain (`:17712-17718`):

```ada
                  elsif Checksum_Status in
                    Invalid_Checksum_Group | Invalid_Checksum_Value
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "The DeleteObjects checksum group is invalid",
                        Target_Text);
```

so a correct `x-amz-checksum-crc32` can never substitute for `Content-MD5`.

PutBucketVersioning has the same gate (`src/flyology-object_storage-server-s3_applications.adb:10352-10370`):

```ada
            when Put_Bucket_Versioning =>
               declare
                  MD5_Count : constant Natural :=
                    Apps.Request_Header_Count (X, "content-md5");
...
                  if MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      ((if MD5_Count = 1
                        then Apps.Request_Header (X, "content-md5") else ""),
                       16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutBucketVersioning requires one valid " &
                        "Content-MD5 header",
                        Target_Text);
```

and so does PutBucketTagging (`:8012-8019`):

```ada
                  elsif MD5_Count /= 1
                    or else not S3.Wire_Core.Valid_Base64
                      (Apps.Request_Header (X, "content-md5"), 16)
                  then
                     Send_Error
                       (X, 400, "InvalidRequest",
                        "PutBucketTagging requires a valid Content-MD5",
                        Target_Text);
```

Object tagging is stricter still. Before its `Content-MD5` gate it rejects the flexible checksum outright (`:15888-15893`):

```ada
                  elsif Algorithm_Count = 1 or else Has_Checksum_Header then
                     Send_Error
                       (X, 501, "NotImplemented",
                        "Object tagging SDK checksums are not implemented",
                        Target_Text);
                     return;
```

and only then demands the header a stock client no longer sends (`:15896-15904`):

```ada
                  if Operation = Put_Object_Tagging then
                     if MD5_Count /= 1 or else Length.Kind /= Backends.Known
                       or else Length.Bytes > Maximum_Object_Tagging_Body
                     then
                        Send_Error
                          (X, 400, "InvalidRequest",
                           "PutObjectTagging requires bounded " &
                           "Content-Length " &
                           "and Content-MD5", Target_Text);
```

so for PutObjectTagging there is no model-conformant request the server accepts at all.

The capability is already implemented and already reachable. `Verify_Document_Checksum` parses and verifies the whole group for all ten algorithms for exactly these documents (`src/flyology-object_storage-server-s3_applications.adb:5033-5039`, ending at `:5163`):

```ada
      function Verify_Document_Checksum
        (Document : String) return Document_Checksum_Status
      is
         SDK_Count : constant Natural := Apps.Request_Header_Count
           (X, "x-amz-sdk-checksum-algorithm");
         Trailer_Declaration_Count : constant Natural :=
           Apps.Request_Header_Count (X, "x-amz-trailer");
```

and the crate already applies the accept-either rule on other configuration routes, in `Read_Bucket_Scalar_Control` (`:5194-5201`):

```ada
         elsif Require_Checksum
           and then MD5_Count = 0
           and then SDK_Count = 0
           and then Checksum_Value_Header_Count = 0
         then
            Send_Error
              (X, 400, "InvalidRequest",
               Operation_Name & " requires a request checksum", Target_Text);
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) makes the checksum group the way the requirement is met, and does not make `Content-MD5` mandatory anywhere. Printed from the model with python3:

```
DeleteObjects httpChecksum= {"requestAlgorithmMember": "ChecksumAlgorithm", "requestChecksumRequired": true}
  input shape DeleteObjectsRequest ContentMD5 ABSENT | required: ['Bucket', 'Delete']
  members: Bucket, Delete, MFA, RequestPayer, BypassGovernanceRetention, ExpectedBucketOwner, ChecksumAlgorithm
PutBucketVersioning httpChecksum= {"requestAlgorithmMember": "ChecksumAlgorithm", "requestChecksumRequired": true}
  input shape PutBucketVersioningRequest ContentMD5 PRESENT | required: ['Bucket', 'VersioningConfiguration']
  members: Bucket, ContentMD5, ChecksumAlgorithm, MFA, VersioningConfiguration, ExpectedBucketOwner
PutObjectTagging httpChecksum= {"requestAlgorithmMember": "ChecksumAlgorithm", "requestChecksumRequired": true}
  input shape PutObjectTaggingRequest ContentMD5 PRESENT | required: ['Bucket', 'Key', 'Tagging']
  members: Bucket, Key, VersionId, ContentMD5, ChecksumAlgorithm, Tagging, ExpectedBucketOwner, RequestPayer
```

`ContentMD5` is in no such operation's `required` list, and for `DeleteObjects` the member does not exist in the input shape, so a client generated from this model has no modelled way to send it there. The model's `DeleteObjectsRequest.ChecksumAlgorithm` documentation, with HTML stripped, states what does satisfy the requirement:

```
Indicates the algorithm used to create the checksum for the object when you
use the SDK. ... When you send this header, there must be a corresponding
x-amz-checksum-algorithm or x-amz-trailer header sent. Otherwise, Amazon S3
fails the request with the HTTP status code 400 Bad Request .
```

The same shape carries `requestChecksumRequired: true` on 27 operations, so the other configuration and object-control PUTs listed above are affected by inspection.

The crate documents the rule as intended behaviour and never discloses that a model-driven client cannot comply (`docs/compatibility/s3.md:506-509`):

```
DeleteObjects accepts the exact `delete` subresource forms, validates a
bounded 1,000-key REST/XML document and payload hash, and requires canonical
Content-MD5 over the exact admitted body. It also verifies each of the ten
modeled SDK checksum algorithm/header pairs.
```

That statement contradicts the model it is written against: the model marks the operation `requestChecksumRequired` and gives its request shape no `ContentMD5` member. `docs/compatibility/s3.md:638-639` states the same rule for the configuration PUTs, and `docs/qualification/delete-objects.md:10-12` repeats it ("It requires one canonical Content-MD5 computed over the exact body bytes and can verify one matching SDK checksum algorithm/value pair").

The existing tests pass because they never send the model-conformant shape. `tests/src/s3_server_application_corpus.adb:16039-16045` asserts the rejection of a request with no integrity header at all, which AWS also rejects, and so locks in the current gate:

```ada
         Require
           (Has
              (Run
                 (Signed_Delete_Objects_Request
                    (Payload, Include_MD5 => False)),
               "<Code>InvalidRequest</Code>"),
            "DeleteObjects accepted a missing Content-MD5");
```

The ten-algorithm loop at `:16080-16097` leaves `Include_MD5` at its default `True` (`:1097-1113`), so every accepted flexible-checksum case also carries `Content-MD5`, and the cross-server wire slice drives DeleteObjects only through the pinned s5cmd image (`tests/scripts/run-s3-server-slice.sh:9` and `:104-107`), whose requests this server accepts today, so no lane sends a checksum-only batch.

## What happens now

Spike: the program below creates two buckets and four objects in the in-process memory-backed application, then sends DeleteObjects, PutBucketVersioning and PutObjectTagging twice each, once with a correct `x-amz-checksum-crc32` plus `x-amz-sdk-checksum-algorithm: CRC32` and no `Content-MD5` (asserting 200, which is what the model describes), and once with `Content-MD5` as the control. It also re-reads the key the checksum-only batch should have deleted.

```ada
   function Flexible_Checksum_Headers (Payload : String) return String is
     ("x-amz-sdk-checksum-algorithm: CRC32" & CRLF &
      "x-amz-checksum-crc32: " & CRC32_Base64 (Payload) & CRLF);
...
      Response : constant String :=
        Run (Signed_Request
               ("POST", "/md5-bucket", Payload,
                Extra_Headers => Flexible_Checksum_Headers (Payload),
                Query         => Delete_Query));
   begin
      Check (Status_Code (Response) = 200,
             "DeleteObjects with a valid x-amz-checksum-crc32 and " &
             "x-amz-sdk-checksum-algorithm: CRC32 and no Content-MD5 is 200");
```

Output, exit status 1:

```
  ok: fixture: CreateBucket /md5-bucket
  ok: fixture: PutObject /md5-bucket/modelled
  -- DeleteObjects flexible checksum headers: x-amz-sdk-checksum-algorithm: CRC32\r\nx-amz-checksum-crc32: YZjakw==\r\n
  -- DeleteObjects CRC32 only, no Content-MD5: status 400  body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>DeleteObjects requires one valid Content-MD5 header</Message><Resource>/md5-bucket?delete</Resource></Error>
  FAILED: DeleteObjects with a valid x-amz-checksum-crc32 and x-amz-sdk-checksum-algorithm: CRC32 and no Content-MD5 is 200
  FAILED: DeleteObjects CRC32-only response reports the deleted key
  -- GET /md5-bucket/modelled after the CRC32-only batch: status 200  body payload
  FAILED: the CRC32-only DeleteObjects actually removed the key
  -- CONTROL DeleteObjects with Content-MD5: status 200  body <?xml version="1.0" encoding="UTF-8"?><DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>control</Key></Deleted></DeleteResult>
  ok: CONTROL: DeleteObjects with Content-MD5 is 200
  -- PutBucketVersioning CRC32 only, no Content-MD5: status 400  body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>PutBucketVersioning requires one valid Content-MD5 header</Message><Resource>/md5-bucket?versioning</Resource></Error>
  FAILED: PutBucketVersioning with a valid flexible checksum and no Content-MD5 is 200
  -- CONTROL PutBucketVersioning with Content-MD5: status 200  body 
  ok: CONTROL: PutBucketVersioning with Content-MD5 is 200
  -- PutObjectTagging CRC32 only, no Content-MD5: status 501  body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NotImplemented</Code><Message>Object tagging SDK checksums are not implemented</Message><Resource>/md5-control/tagged?tagging</Resource></Error>
  FAILED: PutObjectTagging with a valid flexible checksum and no Content-MD5 is 200
  -- CONTROL PutObjectTagging with Content-MD5: status 200  body 
  ok: CONTROL: PutObjectTagging with Content-MD5 is 200
BUG REPRODUCED: 5 failed expectation(s)
```

The control requests, which differ only in carrying `Content-MD5`, all succeed, so the bodies, the signatures and the routes are right and only the integrity-header choice is refused.

Two stock clients were then driven against the real application to confirm this is the current default and not a hypothetical.

aws-cli/2.36.34 with awscrt 0.36.2, driven against the crate's own loopback listener. A second program created the same fixtures, opened the listener on 127.0.0.1 and held it open for 45 s; the CLI was pointed at that loopback endpoint with only `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and `AWS_DEFAULT_REGION` set and no checksum configuration of any kind:

```
### aws s3api list-objects-v2 (sanity)
{
    "Contents": [ { "Key": "modelled", ... "Size": 7 } ], ...
}

### aws s3api delete-objects (stock defaults)
aws: [ERROR]: An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header

### aws s3api put-bucket-versioning (stock defaults)
aws: [ERROR]: An error occurred (InvalidRequest) when calling the PutBucketVersioning operation: PutBucketVersioning requires one valid Content-MD5 header

### aws s3api put-object-tagging (stock defaults)
aws: [ERROR]: An error occurred (NotImplemented) when calling the PutObjectTagging operation: Object tagging SDK checksums are not implemented

### aws s3api put-bucket-tagging (stock defaults)
aws: [ERROR]: An error occurred (InvalidRequest) when calling the PutBucketTagging operation: PutBucketTagging requires a valid Content-MD5
```

`list-objects-v2`, `s3 cp`, `s3api put-object` and single-key `s3 rm` all succeeded against the same listener in the same session, so authentication, signing and routing are fine and only these routes fail. The bytes the CLI put on the wire, captured with a plain socket listener so nothing about the Ada server could influence them:

```
POST /md5-bucket?delete HTTP/1.1
Host: 127.0.0.1:64829
User-Agent: aws-cli/2.36.34 md/awscrt#0.36.2 ... md/command#s3api.delete-objects
x-amz-checksum-crc64nvme: hBxFfoI/0Yk=
x-amz-sdk-checksum-algorithm: CRC64NVME
X-Amz-Date: 20260907T013904Z
X-Amz-Content-SHA256: 063b9d00...8ad7
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/...,
  SignedHeaders=host;x-amz-checksum-crc64nvme;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=...
Content-Length: 101

<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>modelled</Key></Object></Delete>
```

There is no `Content-MD5` field, and the default algorithm is CRC64NVME, which the server's own `Verify_Checksum` supports.

boto3 and botocore 1.43.89 on Python 3.13.7, resolved from PyPI by `uv run --python 3.13 --with boto3` with nothing installed system-wide, driven against the repository's prebuilt `tests/bin/s3_memory_server` (started as `AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=... ./tests/bin/s3_memory_server 0`, no container). The client reported its own defaults as `request_checksum_calculation = when_supported` and `response_checksum_validation = when_supported`. Its `delete_objects` call, verbatim:

```
=== e. delete_objects (two keys), boto3 defaults ===
--- request POST http://127.0.0.1:58179/boto3-checksum-probe?delete
    Authorization: b'AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-checksum-crc32;x-amz-content-sha256;x-amz-date;x-amz-sdk-checksum-algorithm, Signature=eaa6e7167dbba6eab89843e988b58361b1e60cc65249b0b4e7e4a78592b2e6cd'
    Content-Length: 137
    X-Amz-Content-SHA256: b'4795d650e61e4eca68f8f20f376576c402445deb89b9b58ec953d1a43eb9f038'
    x-amz-checksum-crc32: b'ApXd/g=='
    x-amz-sdk-checksum-algorithm: b'CRC32'
--- request body: bytes(137): b'<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>absent-1</Key></Object><Object><Key>absent-2</Key></Object></Delete>'
--- response status 400
    Content-Type: application/xml
--- response body: '<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>DeleteObjects requires one valid Content-MD5 header</Message><Resource>/boto3-checksum-probe?delete</Resource></Error>'
--- CLIENT ERROR: An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header
```

`put_bucket_versioning` failed identically. In the same session `create_bucket`, `put_object` with defaults and with an explicit algorithm, `create_multipart_upload`, two 5 MiB `upload_part` calls, `complete_multipart_upload` and six `head_object`/`get_object` calls with `ChecksumMode=ENABLED` were all accepted with 200, so the object path is unaffected and only the `requestChecksumRequired` routes fail. The probe exits 1 on those two cases alone.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

An operation the model marks `requestChecksumRequired` must be satisfiable by the checksum group the model names, `x-amz-sdk-checksum-algorithm` together with `x-amz-checksum-<alg>` or `x-amz-trailer`, because that is the integrity mechanism the trait selects and the only one a client generated from this model can use on DeleteObjects. The server already computes and compares that group over the exact admitted body, so accepting it costs no integrity guarantee.

## Suggested treatment

Move the flexible-checksum verdict ahead of the `Content-MD5` gate on these routes and accept it as an alternative, which is the shape `Read_Bucket_Scalar_Control` already uses at `src/flyology-object_storage-server-s3_applications.adb:5194-5201`: in the DeleteObjects arm accept when `Checksum_Status` is the verified value or a valid `Content-MD5` is present, and in the PutBucketVersioning, PutBucketTagging and object-tagging arms call `Verify_Document_Checksum` before rejecting for a missing `Content-MD5`. For object tagging the 501 at `:15888-15893` has to become an accept path as well, otherwise the operation stays uncallable. No new public constant, type or parameter is needed for any of that.

What remains open is the policy at the other end of the rule, and it needs a maintainer decision:

- Accept either header and require at least one, so a request carrying neither is still 400 `InvalidRequest`. This matches what the crate does on the routes that go through `Read_Bucket_Scalar_Control` and keeps the current corpus assertion for a request with no integrity header true.
- Accept either header and require neither, so an unauthenticated-integrity request is admitted like an ordinary PUT. This is closer to what a request with no `httpChecksum` trait gets, and it weakens the guarantee the qualification documents claim.
- Keep `Content-MD5` mandatory where the model still defines the member and relax only DeleteObjects and PutBucketLifecycleConfiguration, whose request shapes have no `ContentMD5` member. This is the smallest change but leaves stock clients broken on the other 25 operations.

Whichever is chosen, `docs/compatibility/s3.md:506-509` and `:638-639`, `docs/qualification/delete-objects.md:10-12`, `docs/qualification/bucket-versioning.md:47` and `docs/qualification/bucket-tagging.md:51` state the current rule as a qualification claim and must be restated with it.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the DeleteObjects checksum block: the helper `Signed_Delete_Objects_Request` (`:1097-1113`) already takes `Include_MD5 => False` and an `Extra_Headers` string, so the new case is one call asserting 200 for a checksum-only batch, and the ten-algorithm loop at `:16080-16097` should be repeated with `Include_MD5 => False`. The assertion at `:16039-16045` pins the current rejection of a request with no integrity header and must be reworded or kept deliberately, depending on which option above is taken. The spike is the test. Because the failure is a stock-client interop break rather than a header-shape detail, a case driving a current aws-cli v2 or boto3 through `tests/scripts/test-flyology-server.sh` (which already starts `tests/bin/s3_memory_server` and hands it to a wire slice) would catch a regression the in-process corpus cannot, since the corpus builds its own requests.

## Severity

Four ordinary operations, and by inspection every one of the 27 the model marks `requestChecksumRequired`, cannot be called from a current AWS SDK with default settings. The user does nothing unusual: an unconfigured `aws s3api delete-objects` or a boto3 `delete_objects` on a default client is refused with 400 `InvalidRequest`, and nothing is deleted or configured. `DeleteObjects` has no workaround at all, because the request shape has no `ContentMD5` member to set by hand; the others can be worked around only by setting `request_checksum_calculation=when_required` and passing `ContentMD5=` explicitly. The object path is unaffected, so a deployment that only puts and gets objects will not notice. Deterministic.
