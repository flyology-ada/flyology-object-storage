Title: Tagging.Parse_Bucket rejects a namespace-free `<Tagging>` body that PutObjectTagging on the same server accepts
Labels: bug
Refs: S3-DOMAIN-A-5, S3-DOMAIN-B-1

## Summary

`Bucket_Tagging_Handler.Start_Element_Details` rejects an empty namespace unless `Allow_Empty_Namespace` is set, and `Parse_Bucket` sets it to `False` while `Parse_Bucket_Response` sets it to `True`. The object tagging handler overrides no `Start_Element_Details` at all, so `PUT /bucket/key?tagging` accepts a document that `PUT /bucket?tagging` refuses with 400 `MalformedXML`. minio-go marshals `<Tagging>` with no namespace for both resources, so `mc tag set` on a bucket fails against a Flyology endpoint while MinIO accepts the identical bytes with 200. The pinned botocore S3 model puts no `xmlNamespace` on the `Tagging` shape.

## Problem

Commit `5fe6e3e`.

The bucket handler's namespace rule is conditional on a flag (`src/flyology-object_storage-s3-tagging.adb:434-448`):

```ada
   overriding procedure Start_Element_Details
     (Item            : in out Bucket_Tagging_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then
            (not Item.Allow_Empty_Namespace or else Namespace_URI'Length > 0))
        or else Attribute_Count /= 0
      then
         raise Malformed_Tagging with
           "bucket tagging namespace or attributes are invalid";
      end if;
   end Start_Element_Details;
```

Both entry points share one body and differ only in that flag (`src/flyology-object_storage-s3-tagging.adb:574-586`):

```ada
   function Parse_Bucket
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => False));

   function Parse_Bucket_Response
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => True));
```

The specification grants the tolerance to the response decoder only (`src/flyology-object_storage-s3-tagging.ads:48-54`):

```ada
   --  Parse a bucket-tagging response from S3-compatible implementations.
   --  The official S3 namespace and an absent namespace are accepted;
   --  foreign namespaces and attributes remain invalid.
   function Parse_Bucket_Response
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set;
```

The server calls the strict entry point for PutBucketTagging (`src/flyology-object_storage-server-s3_applications.adb:8259-8262`):

```ada
                              declare
                                 Value : constant Tags.Tag_Set :=
                                   Tagging.Parse_Bucket
                                     (Document,
```

and maps the two exceptions to different codes (`src/flyology-object_storage-server-s3_applications.adb:8283-8294`):

```ada
                        exception
                           when Tagging.Malformed_Tagging =>
                              Send_Error
                                (X, 400, "MalformedXML",
                                 "The XML provided was not well-formed or " &
                                 "did not validate against the published " &
                                 "schema", Target_Text);
                           when Tagging.Invalid_Tag =>
                              Send_Error
                                (X, 400, "InvalidTag",
                                 "The tag set contains an invalid tag",
                                 Target_Text);
```

The object tagging handler in the same package overrides no `Start_Element_Details`. Its `Start_Element` checks only local names (`src/flyology-object_storage-s3-tagging.adb:43-54`):

```ada
   overriding procedure Start_Element
     (Item : in out Tagging_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Tagging with "object tagging XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Local_Name /= "Tagging" then
               raise Malformed_Tagging with "wrong object tagging root";
            end if;
```

so `PutObjectTagging` accepts any namespace, including none. The crate is therefore inconsistent with itself in two directions: the object request path and the bucket response path both accept what the bucket request path refuses.

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) puts the namespace on the member, not the shape. Printed with python3:

```
--- Tagging shape ---
{"type": "structure", "required": ["TagSet"],
 "members": {"TagSet": {"shape": "TagSet"}}}
--- PutBucketTaggingRequest.Tagging member ---
{"shape": "Tagging", "locationName": "Tagging",
 "xmlNamespace": {"uri": "http://s3.amazonaws.com/doc/2006-03-01/"}}
```

MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned at `tests/scripts/test-minio.sh:5`, accepts the namespace-free body on the bucket resource. A signed `PUT /oracle-b?tagging` with `Content-MD5` and the body `<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>`:

```
PutBucketTagging, namespace-free body (mc form)            : 200
```

`docs/qualification/bucket-tagging.md:50` records the rule as an offline gate:

```
rejection; strict namespace-aware XML and tag limits; SigV4 auth-before-
```

The model imposes no such rule and MinIO accepts the body, so that document states the defect rather than a documented limitation.

Two unit assertions pin the inconsistency. The rejection (`tests/src/object_storage_test_cases.adb:11267-11270`):

```ada
      Must_Reject_Malformed
        ("<Tagging><TagSet>" & Tag_XML ("a", "b") &
         "</TagSet></Tagging>",
         "bucket tagging document without the S3 namespace was accepted");
```

and the acceptance of the same string by the response decoder (`tests/src/object_storage_test_cases.adb:11233-11243`):

```ada
         Namespace_Free : constant String :=
           "<Tagging><TagSet>" & Tag_XML ("project", "flyology") &
           "</TagSet></Tagging>";
         Parsed : constant Tags.Tag_Set :=
           Tagging.Parse_Bucket_Response (Namespace_Free);
         Rejected_Foreign : Boolean := False;
      begin
         Assert
           (Parsed.Length = 1
            and then US.To_String (Parsed.First_Element.Key) = "project",
            "namespace-free compatible response was rejected");
```

The first must be inverted with the fix. The foreign-namespace assertions at `:11244-11260` and `:11274-11278` and the attribute assertion at `:11271-11273` are correct rejections and must keep failing, and the namespace-free duplicate-`TagSet` case at `:11279-11282` stays rejected for its duplicate member.

{{ISSUE:S3-DOMAIN-B-1}} is the same question on the DeleteObjects request codec and {{ISSUE:S3-DOMAIN-A-5}} is the same question on the PutBucketVersioning body parser. One decision about receiver-side namespace tolerance settles all three sites.

## What happens now

Spike: the program below creates `/domain-b2` and the key `k` in the in-process memory-backed application. It first decodes the document captured from `mc tag set` through both bucket entry points, then sends the same document as a signed `PUT ...?tagging` with a correct `Content-MD5` to the object resource and to the bucket resource, asserting 200 for both. The namespaced boto3, aws-cli and s3cmd body on the bucket resource is the control.

```ada
   --  Captured from mc RELEASE.2025-08-13T08-35-41Z (minio-go v7.0.90),
   --  `mc tag set repro/probe-mc team=storage`.
   MC_Body : constant String :=
     "<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value>" &
     "</Tag></TagSet></Tagging>";
   --  Captured from boto3 1.43.89 / aws-cli 2.36.34 / s3cmd 2.4.0.
   SDK_Body : constant String :=
     "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
     "<TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet>" &
     "</Tagging>";

   function Tagging_Request (Target, Document : String) return String is
     (Signed_Request
        ("PUT", Target, Document,
         "Content-MD5: " & MD5_Base64 (Document) & CRLF &
         "Content-Type: application/xml" & CRLF,
         Tagging_Query));
```

Output, exit status 1:

```
  -- === fixtures ===
  ok: CreateBucket /domain-b2 is 200
  ok: PutObject k is 200
  -- 
  -- === unit level: the two bucket entry points on one document ===
  -- Parse_Bucket_Response accepted it, tags=1
  ok: control: Parse_Bucket_Response decodes the mc document
  -- Parse_Bucket raised FLYOLOGY.OBJECT_STORAGE.S3.TAGGING.MALFORMED_TAGGING: malformed bucket tagging XML
  FAILED: Tagging.Parse_Bucket accepts a namespace-free <Tagging>
  -- 
  -- === server: the same document on both tagging paths ===
  -- PutObjectTagging, mc document (accepted today)
  --     PUT /domain-b2/k?tagging body=<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
  --     status=200 body=
  ok: PutObjectTagging, mc document (accepted today) is answered 200
  -- PutBucketTagging, mc document                 
  --     PUT /domain-b2?tagging body=<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
  --     status=400 body=<?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/domain-b2?tagging</Resource></Error>
  FAILED: PutBucketTagging, mc document                  is answered 200
  -- 
  -- === control: PutBucketTagging with xmlns (passes today) ===
  -- PutBucketTagging, boto3/aws-cli document      
  --     PUT /domain-b2?tagging body=<Tagging xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
  --     status=200 body=
  ok: PutBucketTagging, boto3/aws-cli document       is answered 200
BUG REPRODUCED: 2 failed expectation(s)
```

One document, three requests: accepted on the object resource, refused on the bucket resource, accepted again on the bucket resource once `xmlns` is added.

The client body is not hypothetical. `mc` RELEASE.2025-08-13T08-35-41Z with minio-go v7.0.90, run from the `minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727` image with `--rm`, was pointed at a logging TCP proxy forwarding byte for byte to the prebuilt `tests/bin/s3_memory_server`. `mc tag set fly/mcbucket "team=storage"` put this on the wire, and `mc tag set fly/mcbucket/m1 "team=storage"` put the byte-identical body on the object resource:

```
PUT /mcbucket/?tagging= HTTP/1.1
Host: host.docker.internal:62457
User-Agent: MinIO (linux; arm64) minio-go/v7.0.90 mc/RELEASE.2025-08-13T08-35-41Z
Content-Length: 84
Accept-Encoding: zstd,gzip
Authorization: AWS4-HMAC-SHA256 Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request, SignedHeaders=content-md5;host;x-amz-content-sha256;x-amz-date, Signature=d3100d8dc1dbaef9f61019cd7ab70ec96210d23537a3a30b8066e424ef10ab40
Content-Md5: SLw5gP7IN3lXnRzCSb/wzw==
X-Amz-Content-Sha256: UNSIGNED-PAYLOAD
X-Amz-Date: 20260907T070150Z

<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>
```

There is a plain-HTTP caveat, stated plainly. minio-go signs this body as `UNSIGNED-PAYLOAD`, which the crate refuses without TLS (`src/flyology-object_storage-server-s3_applications.adb:1903-1906`):

```ada
         when Authentication.Insecure_Unsigned_Payload =>
            Send_Error
              (X, 400, "InvalidRequest",
               "UNSIGNED-PAYLOAD requires a secure transport", Resource);
```

so over the plain-HTTP test endpoint `mc tag set` reports `UNSIGNED-PAYLOAD requires a secure transport` and the namespace check is never reached. On an HTTPS endpoint that gate passes and the namespace check is what remains. To show what happens there, `mc`'s exact bytes were replayed over plain HTTP with a valid SigV4 header signature, a real payload hash and `Content-MD5`, so that neither the integrity gate nor the UNSIGNED-PAYLOAD rule applies:

```
PutBucketTagging  mc body (no xmlns)   : 400 <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/replay-b?tagging</Resource></Error>
PutBucketTagging  same body + xmlns    : 200
```

Adding only `xmlns` turns the request into a 200.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A PutBucketTagging request body with an absent namespace must be accepted, because the pinned botocore S3 model puts `xmlNamespace` on the `PutBucketTaggingRequest.Tagging` member as a serializer instruction and puts none on the `Tagging` shape, because PutObjectTagging on this same server already accepts it, and because MinIO answers 200 for the exact bytes. A foreign namespace and any attribute may still be rejected.

## Suggested treatment

The smallest fix is one Boolean: give `Parse_Bucket` the same `Allow_Empty_Namespace => True` that `Parse_Bucket_Response` already uses, at `src/flyology-object_storage-s3-tagging.adb:574-579`. That brings the bucket request path in line with the bucket response path and with the object path, changes no public declaration, and leaves foreign namespaces and attributes invalid, because only the empty namespace is at issue.

This needs a maintainer decision only on scope, because the two remaining choices differ in what the strict mode is for:

- Flip `Parse_Bucket` to the tolerant mode. `Parse_Bucket` and `Parse_Bucket_Response` then differ in nothing, so one of them can be removed later. `src/flyology-object_storage-s3-tagging.ads:48-50` should be reworded, since the namespace tolerance is no longer specific to the response decoder.
- Keep both modes and expose the choice to the server as a parameter. This preserves a strict parser for callers that want it, but it adds public surface, which is an interface decision under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`.

`docs/qualification/bucket-tagging.md:50` states the current rule as a qualification claim and must be restated with the fix. Because {{ISSUE:S3-DOMAIN-B-1}} and {{ISSUE:S3-DOMAIN-A-5}} are the same question on two other request codecs, the three should be sequenced together so the answer is uniform.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the existing bucket tagging block, as a signed `PUT /bucket?tagging` carrying the captured namespace-free body and a correct `Content-MD5`, asserting 200 and the stored tag. The unit assertion at `tests/src/object_storage_test_cases.adb:11267-11270` pins the rejection and must be inverted; the foreign-namespace cases around it must keep asserting rejection. The spike is the test.

## Severity

A bucket tag set cannot be written by any client that does not emit `xmlns`, and minio-go is such a client, so `mc tag set` on a bucket fails against a Flyology endpoint over HTTPS while it works against MinIO and AWS. The user sees 400 `MalformedXML`, which points at the XML rather than at a namespace, and the same client's object tagging succeeds on the same server, which makes the failure look like a bucket-specific outage. No data is lost or corrupted; the write simply never happens. Over a plain-HTTP endpoint minio-go is stopped one step earlier by the UNSIGNED-PAYLOAD rule, so the namespace rejection is only observable over TLS or through a replay of the same bytes with a signed payload hash. Deterministic.
