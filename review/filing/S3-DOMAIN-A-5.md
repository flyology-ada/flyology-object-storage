Title: PutBucketVersioning rejects an unqualified root, so mc version enable cannot turn versioning on
Labels: bug
Refs: S3-DOMAIN-B-1, S3-DOMAIN-B-2

## Summary

`Versioning.Parse` is the only request-body codec in the crate that treats the S3 namespace as a wire precondition, and the server calls exactly that one. A `PUT /bucket?versioning` whose body omits `xmlns` is answered 400 `MalformedXML`, while the same client's lifecycle, notification and CreateBucket bodies are accepted unqualified by their own parsers. MinIO's `mc`, the default way to turn versioning on against any S3 endpoint, sends the body without a namespace and with a correct `Content-MD5`, so `mc version enable` cannot enable versioning on a Flyology server at all. The leniency already exists in the same package and is simply not wired to the server path.

## Problem

Commit `5fe6e3e`.

The handler rejects any root that is neither the S3 namespace nor, when permitted, the empty one (`src/flyology-object_storage-s3-versioning.adb:47-54`):

```ada
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then
            (not Item.Allow_Empty_Namespace or else Namespace_URI'Length > 0))
        or else Attribute_Count /= 0
      then
         raise Malformed_Configuration with
           "bucket versioning namespace or attributes are invalid";
      end if;
```

The two entry points differ only in that flag (`src/flyology-object_storage-s3-versioning.adb:171-183`):

```ada
   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration is
     (Parse_Document
        (Document, Limits, Allow_Empty_Namespace => False));

   function Parse_Response
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration is
     (Parse_Document
        (Document, Limits, Allow_Empty_Namespace => True));
```

and the server calls the strict one, after the Content-MD5 and checksum gates have already passed (`src/flyology-object_storage-server-s3_applications.adb:10421-10425`):

```ada
                           else
                              declare
                                 Configuration : constant
                                   Bucket_Versioning_Configuration :=
                                     Versioning.Parse (Document);
```

Every sibling request-body parser the server calls accepts an unqualified root. Lifecycle treats it as one of two acceptable styles (`src/flyology-object_storage-s3-lifecycle.adb:70-74`):

```ada
      Style : constant Namespace_Style :=
        (if Namespace_URI'Length = 0 then Unqualified
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then S3_Qualified
         else Namespace_Not_Selected);
```

Notifications is identical (`src/flyology-object_storage-s3-notifications.adb:166-170`), and `Buckets.Parse_Create_Configuration` has no namespace check at all, matching only the root element name (`src/flyology-object_storage-s3-buckets.adb:539-544`):

```ada
      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "CreateBucketConfiguration"
         then
            raise Malformed_Bucket_Configuration with
              "invalid CreateBucket root";
         end if;
```

The crate's own specification says why the leniency exists (`src/flyology-object_storage-s3-versioning.ads:30-32`):

```ada
   --  Parse an implementation response. AWS responses use the S3 namespace,
   --  while a few otherwise compatible implementations omit it; foreign
   --  namespaces and all element attributes still fail closed.
```

That sentence is attached to `Parse_Response`, and the same implementations omit the namespace on the request.

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) does not make the namespace a parsing precondition. It records the namespace on the payload member, which is what a serializer writes. Printed with `python3`:

```
PutBucketVersioningRequest payload: VersioningConfiguration required: ['Bucket', 'VersioningConfiguration']
VersioningConfiguration member: {"shape": "VersioningConfiguration", "locationName": "VersioningConfiguration", "xmlNamespace": {"uri": "http://s3.amazonaws.com/doc/2006-03-01/"}}
```

A stock client sends the body without it. MinIO `mc` RELEASE.2025-08-13T08-35-41Z (minio-go/v7.0.90), from the image `minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727`, was pointed at this crate's own in-process S3 application through a plain logging TCP relay, because `mc` runs inside Docker and the application listens on loopback. The bytes below are the relay's capture of the real socket for `mc version enable`:

```
PUT /stock-versioning-3/?versioning= HTTP/1.1
Host: host.docker.internal:58080
User-Agent: MinIO (linux; arm64) minio-go/v7.0.90 mc/RELEASE.2025-08-13T08-35-41Z
Content-Length: 75
Accept-Encoding: zstd,gzip
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=content-md5;host;x-amz-content-sha256;x-amz-date, Signature=73a0504faf9bf169dcdd61d8d4da80c930e45f96c1e44da905946d7314467113
Content-Md5: 8qj8HSeDu3APPMQZVG06WQ==
X-Amz-Content-Sha256: dd6f6f21cc8680cc5c32bba98d4297e37552279d7e326a35df847ed2713f2d6a
X-Amz-Date: 20260907T065759Z

<VersioningConfiguration><Status>Enabled</Status></VersioningConfiguration>
===== SERVER -> CLIENT =====
HTTP/1.1 400 Bad Request
Date: Mon, 07 Sep 2026 06:57:59 GMT
Content-Length: 235
Content-Type: application/xml

<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/stock-versioning-3/?versioning=</Resource></Error>
```

`mc` reported:

```
mc: <ERROR> Unable to enable versioning. The XML provided was not well-formed or did not validate against the published schema.
```

The 75-byte body carries no `xmlns`, and the correct `Content-MD5` cleared every checksum gate, so the absent namespace is the only reason for the rejection. There is no client-side workaround: `mc` offers no option to add a namespace.

Two other stock clients are unaffected by this defect, because both serialize the model's `xmlNamespace`. Against the same listener, aws-cli 2.36.34 (Python 3.14.7) sent, captured on the same relay:

```
PUT /stock-versioning-2?versioning HTTP/1.1
Host: 127.0.0.1:58080
User-Agent: aws-cli/2.36.34 md/awscrt#0.36.2 ua/2.1 os/macos#25.6.0 md/arch#arm64 lang/python#3.14.7 md/pyimpl#CPython ... md/command#s3api.put-bucket-versioning
...
<VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Status>Enabled</Status></VersioningConfiguration>
```

and boto3 with botocore 1.43.89 sent the same body. Both were refused for an unrelated checksum reason:

```
An error occurred (InvalidRequest) when calling the PutBucketVersioning operation: PutBucketVersioning requires one valid Content-MD5 header
```

so neither is evidence for or against the namespace rule.

The strictness is not disclosed where a client would look. The matrix row `docs/compatibility/s3.md:57` claims an "authenticated path-style server" and a "configuration-only six-server oracle" for Put and Get bucket versioning, and neither it nor `docs/qualification/put-bucket-versioning.md` names the namespace as a client requirement.

One existing test asserts the current rejection and must change with the fix (`tests/src/object_storage_test_cases.adb:21868-21871`):

```ada
      Expect_Malformed
        ("<VersioningConfiguration><Status>Enabled</Status>" &
         "</VersioningConfiguration>",
         "namespace-free versioning request accepted");
```

The neighbouring assertions stay correct: `:21872-21880` rejects a foreign namespace and an element attribute, and `:21881-21890` requires `Parse_Response` to accept the very same namespace-free bytes.

## What happens now

Spike: the program below has two parts. Part one runs four namespace-free request bodies through their own parsers side by side. Part two sends signed requests through the in-process S3 application: a namespaced `?versioning` body as the control, a second `CreateBucket` as a second control, then the exact 75-byte body `mc` puts on the wire, then `GET ?versioning` on that second bucket to show whether it became versioned.

```ada
   Unqualified_Body : constant String :=
     "<VersioningConfiguration><Status>Enabled</Status>" &
     "</VersioningConfiguration>";
...
         Ignored : constant
           Flyology.Object_Storage.Bucket_Versioning_Configuration :=
             Versioning.Parse (Unqualified_Body);
...
      Response : constant String := Run
        (Signed_Request
           ("PUT", Other_Bucket, Unqualified_Body,
            MD5_Header (Unqualified_Body), Versioning_Query));
   begin
      Check (Status_Code (Response) = 200,
             "namespace-free PutBucketVersioning is accepted");
```

Output, exit status 1:

```
  -- --- unqualified request bodies through their own parsers ---
  --   codec Lifecycle.Parse: accepted
  --   codec Notifications.Parse: accepted
  --   codec Buckets.Parse_Create_Configuration: accepted
  --   codec Versioning.Parse_Response: accepted
  --   codec Versioning.Parse: REJECTED
  --     malformed bucket versioning XML
  FAILED: Versioning.Parse accepts an unqualified root
  -- --- signed requests through the S3 application ---
  -- CreateBucket /domain-a-5 status 200
  -- PUT /domain-a-5?versioning  (xmlns present) -> 200
  ok: namespaced PutBucketVersioning is accepted
  -- CreateBucket /domain-a-5-other status 200
  ok: the second bucket is created
  -- PUT /domain-a-5-other?versioning (no xmlns) -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-a-5-other?versioning</Resource></Error>
  FAILED: namespace-free PutBucketVersioning is accepted
  -- GET /domain-a-5-other?versioning -> 200 body <?xml version="1.0" encoding="UTF-8"?><VersioningConfiguration xmlns="http://s3.amazonaws.com/doc/2006-03-01/"></VersioningConfiguration>
  FAILED: the bucket ends up with versioning enabled
BUG REPRODUCED: 3 failed expectation(s)
```

The control PUT differs from the failing PUT only by the `xmlns` attribute, and both carry a correct `Content-MD5`, so signing, routing and the integrity gates are not what fires. The final `GET` shows the bucket never became versioned.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Stock-client bodies captured on the wire from MinIO `mc` RELEASE.2025-08-13T08-35-41Z, aws-cli 2.36.34 and botocore 1.43.89. Shapes checked against the pinned botocore S3 model.

## What should happen

`PUT /bucket?versioning` with a valid body and no `xmlns` must be accepted, as `Lifecycle.Parse`, `Notifications.Parse` and `Buckets.Parse_Create_Configuration` already accept their unqualified bodies, and as the crate's own `Parse_Response` already accepts the identical document. A foreign namespace and any element attribute must still be refused.

## Suggested treatment

The mechanism already exists: `Parse_Document` takes `Allow_Empty_Namespace`, and `Parse_Response` already passes `True`. The smallest fix is to have the server-facing entry point pass `True` as well, at `src/flyology-object_storage-s3-versioning.adb:175-176`, leaving the foreign-namespace and attribute checks at `:47-54` intact. No new public constant, type, parameter or default is introduced.

This needs a maintainer decision only in that it widens the server's accepted request domain:

- Make `Parse` lenient, so one function serves both directions and the package no longer distinguishes them. Simplest, and matches every sibling request codec.
- Keep `Parse` strict and add a separate lenient request entry point that the server calls. Preserves the current strict function for callers that want it, at the cost of a new public subprogram, which the "Ada interface values" section of `AGENTS.md` puts under explicit approval.

`tests/src/object_storage_test_cases.adb:21868-21871` asserts the current rejection and must be inverted into an acceptance assertion that the parsed `Status` is `Versioning_Enabled`; `:21872-21880` and `:21881-21890` stay correct. The server-side regression test belongs in `tests/src/s3_server_application_corpus.adb`, in the PutBucketVersioning block beside the foreign-namespace and attribute cases at `:10524-10546`: send the namespace-free body through `Signed_Versioning_Request` with its `Content_MD5` and require 200, then require the follow-up `GET ?versioning` to report `Enabled`. The spike is the test.

This is one of three request codecs with the same defect. {{ISSUE:S3-DOMAIN-B-1}} reports a namespace-free `<Delete>` refused by DeleteObjects and {{ISSUE:S3-DOMAIN-B-2}} a namespace-free `<Tagging>` refused by PutBucketTagging. The fix is the same class of change in all three, letting the request parser accept an unqualified root the way the lenient sibling codecs already do, so the three should be decided together even if they are three commits.

## Severity

`mc version enable alias/bucket` cannot enable versioning on a Flyology server, and neither can anything else built on minio-go, which is the largest non-AWS S3 client family. The request is well formed, correctly signed and carries a correct `Content-MD5`; the server answers 400 `MalformedXML` and the bucket is left unversioned, with no client-side workaround, since `mc` does not offer to add a namespace. The matrix row `docs/compatibility/s3.md:57` claims an authenticated path-style server and a configuration-only six-server oracle for this operation. Current AWS SDK clients are not affected, because botocore serializes the model's `xmlNamespace`. Deterministic.
