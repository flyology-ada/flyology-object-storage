Title: Deletions.Parse_Request demands the S3 namespace on every element, so mc and s3cmd batch deletes are 400 MalformedXML
Labels: bug
Refs: SERVER-1, S3-DOMAIN-A-5, S3-DOMAIN-B-2

## Summary

`Delete_Handler.Start_Element_Details` raises `Malformed_Delete` unless the element namespace is exactly `http://s3.amazonaws.com/doc/2006-03-01/`, and because it is an override on the handler it runs for every element of a DeleteObjects request body. In the pinned botocore S3 model the namespace is a serializer trait on the `DeleteObjectsRequest.Delete` member, not a constraint on the `Delete` shape, so a receiver must not require it. minio `mc` and `s3cmd` both marshal a namespace-free `<Delete>` with a correct `Content-MD5` and are answered 400 `MalformedXML`, while MinIO answers 200 for the identical bytes. `mc rm --recursive`, `mc rb --force` and `s3cmd rm --recursive` therefore delete nothing against a Flyology endpoint.

## Problem

Commit `5fe6e3e`.

The namespace check is an override on the whole handler, so it fires on the root and on every nested element (`src/flyology-object_storage-s3-deletions.adb:66-79`):

```ada
   overriding procedure Start_Element_Details
     (Item            : in out Delete_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      pragma Unreferenced (Item);
   begin
      if Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
        or else Attribute_Count /= 0
      then
         raise Malformed_Delete with
           "DeleteObjects namespace or attributes are invalid";
      end if;
   end Start_Element_Details;
```

`Parse_Request` turns the handler exception into `Malformed_Delete` through its `XML.XML_Error` arm (`src/flyology-object_storage-s3-deletions.adb:380-393`):

```ada
   function Parse_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Request
   is
      Handler : aliased Delete_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Delete with "malformed DeleteObjects XML";
   end Parse_Request;
```

The specification promises no such rule (`src/flyology-object_storage-s3-deletions.ads:76-83`):

```ada
   --  Parse one bounded DeleteObjects request document.
   --  @param Document DeleteObjects request XML
   --  @param Limits XML parsing limits
   --  @return Decoded DeleteObjects request body
   function Parse_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Request;
```

The server hands the request body to that codec verbatim, with no namespace normalization in between (`src/flyology-object_storage-server-s3_applications.adb:17729-17734`):

```ada
                  if Owner_Accepted then
                     declare
                        Request : constant
                          Deletions.Delete_Objects_Request :=
                            Deletions.Parse_Request
                              (Document,
```

and maps the exception to the wire code (`src/flyology-object_storage-server-s3_applications.adb:17959-17963`):

```ada
                  when Deletions.Malformed_Delete =>
                     Send_Error
                       (X, 400, "MalformedXML",
                        "The XML provided was not well-formed or did not " &
                        "validate against the published schema", Target_Text);
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) puts the namespace on the member, not on the shape. Printed with python3:

```
--- Delete shape ---
{"type": "structure", "required": ["Objects"],
 "members": {"Objects": {"shape": "ObjectIdentifierList", "locationName": "Object"},
             "Quiet": {"shape": "Quiet"}}}
--- DeleteObjectsRequest.Delete member ---
{"shape": "Delete", "locationName": "Delete",
 "xmlNamespace": {"uri": "http://s3.amazonaws.com/doc/2006-03-01/"}}
```

`xmlNamespace` on a member instructs an SDK serializer to emit the attribute. It is not a receiver-side validation rule, and the `Delete` shape itself carries none.

MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned at `tests/scripts/test-minio.sh:5`, accepts the namespace-free body. A signed `POST /oracle-b?delete` carrying `Content-MD5` and the body `<Delete><Quiet>false</Quiet><Object><Key>single-crc</Key></Object></Delete>`:

```
DeleteObjects, namespace-free body (mc/s3cmd form)         : 200 <?xml version="1.0" encoding="UTF-8"?> <DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>single-crc</Key></Deleted></DeleteResult>
```

The same route also carries the mandatory `Content-MD5` gate reported as {{ISSUE:SERVER-1}}, and the order of rejection matters for both fixes. Current boto3 1.43.89 and aws-cli 2.36.34 send `x-amz-checksum-crc32` instead of `Content-MD5`, so that gate stops them one step earlier and they never reach the namespace check. `mc` and `s3cmd` do send `Content-MD5`, so for them the namespace check is the first and only rejection. Driving boto3 1.43.89 at the prebuilt `tests/bin/s3_memory_server` with default settings:

```
boto3 1.43.89 botocore 1.43.89
delete_objects ERROR: An error occurred (InvalidRequest) when calling the DeleteObjects operation: DeleteObjects requires one valid Content-MD5 header
```

Today no client can batch-delete at all. Fixing the `Content-MD5` gate alone would still leave `mc` and `s3cmd` broken here, and fixing this alone would still leave boto3 and aws-cli broken there.

Two maintained documents state the strictness as intended behaviour, so they are part of the defect rather than a defence of it. `docs/qualification/delete-objects.md:13-15`:

```
the pinned model. XML namespace, attributes, member order, duplicates, UTF-8,
key limits, booleans, nonnegative 64-bit sizes, ETag syntax, and HTTP dates are
validated before the relevant entry can reach storage.
```

and `docs/compatibility/s3.md:511-512`:

```
`BadDigest`. The namespace-aware request parser rejects attributes, unknown or
duplicate members, malformed scalars, and out-of-order structures before any
```

Neither is an S3 protocol rule, and MinIO accepts what this server refuses.

The unit suite pins the rejection, so it asserts the wrong behaviour and must change (`tests/src/object_storage_test_cases.adb:11450-11452`):

```ada
      Must_Reject_Request
        ("<Delete><Object><Key>k</Key></Object></Delete>",
         "namespace-free DeleteObjects request was accepted");
```

The adjacent case at `:11453-11456` rejects a foreign namespace (`urn:foreign`) and is a correct rejection that must keep failing. The only DeleteObjects in the cross-server wire slice is s5cmd's `rm` (`tests/scripts/run-s3-server-slice.sh:104-107`, image pinned at `:9`), whose requests this server accepts today, so no lane sends a namespace-free body.

The same change class appears twice more. {{ISSUE:S3-DOMAIN-B-2}} is the bucket-tagging request parser and {{ISSUE:S3-DOMAIN-A-5}} is the PutBucketVersioning body parser. All three enforce a namespace the pinned model places on the member as a serializer instruction, and one decision about receiver-side namespace tolerance settles all three.

## What happens now

Spike: the program below creates `/domain-b1` and the keys `k1`, `k2` and `k3` in the in-process memory-backed application. It first calls `Deletions.Parse_Request` on the document captured from `mc`, then sends the captured `mc` and `s3cmd` bodies as signed `POST /domain-b1?delete` requests with a correct `Content-MD5`, asserting 200 and a `<Deleted>` entry for each. The namespaced boto3 and aws-cli body is the control.

```ada
   --  Captured from mc RELEASE.2025-08-13T08-35-41Z (minio-go v7.0.90).
   MC_Body : constant String :=
     "<Delete><Quiet>false</Quiet><Object><Key>k1</Key></Object></Delete>";
   --  Captured from s3cmd 2.4.0.
   S3cmd_Body : constant String :=
     "<Delete><Object><Key>k2</Key></Object></Delete>";
   --  Captured from boto3 1.43.89 / aws-cli 2.36.34 (control: accepted today).
   SDK_Body : constant String :=
     "<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<Object><Key>k3</Key></Object><Quiet>false</Quiet></Delete>";

   function Delete_Request (Document : String) return String is
     (Signed_Request
        ("POST", Bucket, Document,
         "Content-MD5: " & MD5_Base64 (Document) & CRLF &
         "Content-Type: application/xml" & CRLF,
         Delete_Query));
```

Output, exit status 1:

```
  -- === fixtures ===
  ok: CreateBucket /domain-b1 is 200
  ok: PutObject k1 is 200
  ok: PutObject k2 is 200
  ok: PutObject k3 is 200
  -- 
  -- === unit level: Deletions.Parse_Request ===
  -- Parse_Request raised Malformed_Delete: malformed DeleteObjects XML
  FAILED: Deletions.Parse_Request accepts a namespace-free <Delete>
  -- 
  -- === server: stock-client bodies (must be accepted) ===
  -- mc (minio-go) DeleteObjects    body=<Delete><Quiet>false</Quiet><Object><Key>k1</Key></Object></Delete>
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-b1?delete</Resource></Error>
  FAILED: mc (minio-go) DeleteObjects    is answered 200
  FAILED: mc (minio-go) DeleteObjects    reports k1 as deleted
  -- s3cmd DeleteObjects            body=<Delete><Object><Key>k2</Key></Object></Delete>
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-b1?delete</Resource></Error>
  FAILED: s3cmd DeleteObjects            is answered 200
  FAILED: s3cmd DeleteObjects            reports k2 as deleted
  -- 
  -- === control: the same request with xmlns (passes today) ===
  -- boto3/aws-cli DeleteObjects    body=<Delete xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Object><Key>k3</Key></Object><Quiet>false</Quiet></Delete>
  --     status=200 body=<?xml version="1.0" encoding="UTF-8"?><DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>k3</Key></Deleted></DeleteResult>
  ok: boto3/aws-cli DeleteObjects    is answered 200
  ok: boto3/aws-cli DeleteObjects    reports k3 as deleted
BUG REPRODUCED: 5 failed expectation(s)
```

The control differs from the two failing legs by the `xmlns` attribute and nothing else, so the signature, the `Content-MD5` and the route are right and only the namespace is refused.

The two client bodies are not hypothetical. `mc` RELEASE.2025-08-13T08-35-41Z with minio-go v7.0.90, run from the `minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727` image with `--rm`, was pointed at a logging TCP proxy forwarding byte for byte to `tests/bin/s3_memory_server`. `mc rm --recursive --force` reported

```
mc: <ERROR> Failed to remove `fly` recursively. The XML provided was not well-formed or did not validate against the published schema
```

and the bytes it put on the wire were

```
POST /mcbucket/?delete= HTTP/1.1
Host: host.docker.internal:62457
User-Agent: MinIO (linux; arm64) minio-go/v7.0.90 mc/RELEASE.2025-08-13T08-35-41Z
Content-Length: 127
Accept-Encoding: zstd,gzip
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=content-md5;host;x-amz-content-sha256;x-amz-date, Signature=79482a93c9d27d4187578fdbb667862132d85c363c911e0892958f8e00f27c5c
Content-Md5: 31pfUAHQbxJHn3iLLTGlGg==
X-Amz-Content-Sha256: 807b2595e206da7671988f6a9c33fd280a2887a86263ae41a289181e80fc0303
X-Amz-Date: 20260907T070150Z

<Delete><Quiet>false</Quiet><Object><Key>m1</Key></Object><Object><Key>m2</Key></Object><Object><Key>m3</Key></Object></Delete>
```

There is a correct `Content-MD5` and a real payload hash, and no `xmlns`. s3cmd 2.4.0, resolved from PyPI with `uv run --python 3.13 --with s3cmd` and nothing installed system-wide, reported `ERROR: S3 error: 400 (MalformedXML)` for `s3cmd rm --recursive --force` and sent

```
POST /mcbucket/?delete HTTP/1.1
Host: 127.0.0.1:62457
Accept-Encoding: identity
Content-Length: 145
content-md5: YEfodgAxxXRNXnyq7zzi3g==
content-type: application/xml
x-amz-date: 20260907T070206Z
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request,SignedHeaders=content-md5;content-type;host;x-amz-content-sha256;x-amz-date,Signature=3a06115c3b34a928df5ba37341f385c1884fbd2c515a3236804d6365c30fc6ba
x-amz-content-sha256: 3cfa2fc27dad77fb4d3b1460c8f1868b6bb0f3696de7c315d9144f2cdb719779

<?xml version="1.0" encoding="UTF-8"?><Delete><Object><Key>m1</Key></Object><Object><Key>m2</Key></Object><Object><Key>m3</Key></Object></Delete>
```

Replaying both captured documents over plain HTTP against the same server with a valid SigV4 header signature, a real payload hash and `Content-MD5`, so that neither the integrity gate nor the UNSIGNED-PAYLOAD rule applies, isolates the namespace as the cause:

```
DeleteObjects     mc body (no xmlns)   : 400 <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code>...
s3cmd DeleteObjects body (no xmlns)    : 400 <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code>...
DeleteObjects     same body + xmlns    : 200 <?xml version="1.0" encoding="UTF-8"?><DeleteResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Deleted><Key>m1</Key></Deleted><Deleted><Key>m2</Key></Deleted><Deleted><Key>m3</Key></Deleted></DeleteResult>
```

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A DeleteObjects request body with an absent namespace must be accepted, because the pinned botocore S3 model puts `xmlNamespace` on the `DeleteObjectsRequest.Delete` member as a serializer instruction and puts none on the `Delete` shape, and because MinIO answers 200 for the exact bytes this server refuses. A foreign namespace and any attribute may still be rejected.

## Suggested treatment

The smallest fix accepts an empty `Namespace_URI` in `Delete_Handler.Start_Element_Details` at `src/flyology-object_storage-s3-deletions.adb:66-79`, which is the same test the bucket tagging handler already writes for its tolerant mode at `src/flyology-object_storage-s3-tagging.adb:434-448`:

```ada
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then Namespace_URI'Length > 0)
        or else Attribute_Count /= 0
      then
```

This needs a maintainer decision, because it changes a documented policy and because the alternative adds public surface:

- Accept an absent namespace unconditionally in `Parse_Request`. One expression changes, no public declaration moves, and `Deletions` keeps one entry point. Foreign namespaces and attributes stay invalid.
- Thread an `Allow_Empty_Namespace` flag the way `Tagging.Parse_Bucket_Document` does at `src/flyology-object_storage-s3-tagging.adb:550-586`, and expose it as a new parameter on `Parse_Request` or as a second entry point. This keeps a strict mode available but adds a public parameter or subprogram, which is an interface decision under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.
- Keep the rule and document that `mc` and `s3cmd` cannot batch-delete against this server.

Whichever is chosen, `docs/qualification/delete-objects.md:13-15` and `docs/compatibility/s3.md:511-512` state the current rule as a qualification claim and must be restated with it. Because {{ISSUE:S3-DOMAIN-B-2}} and {{ISSUE:S3-DOMAIN-A-5}} are the same question on two other request codecs, the three should be sequenced together so the answer is uniform.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the DeleteObjects block, as a signed `POST /bucket?delete` carrying the captured namespace-free body and a correct `Content-MD5`, asserting 200 and a `<Deleted>` entry. The unit assertion at `tests/src/object_storage_test_cases.adb:11450-11452` pins the rejection and must be inverted; the foreign-namespace case at `:11453-11456` must keep asserting rejection. The spike is the test.

## Severity

Batch delete is unavailable from two stock clients with default settings, and nothing is deleted. A user running `mc rm --recursive`, `mc rb --force` or `s3cmd rm --recursive` against a Flyology endpoint gets 400 `MalformedXML` on every batch and no partial progress, while the same commands work against MinIO and AWS. The rejection is a string comparison on the namespace of each start element, so it fires on every request of this shape regardless of size, load or backend. Combined with the `Content-MD5` gate reported as {{ISSUE:SERVER-1}}, which stops current boto3 and aws-cli one step earlier, no client tested here can batch-delete at all. Deterministic.
