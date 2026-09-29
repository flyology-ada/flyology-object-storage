Title: Listing query parsers reject max-keys above 1000 with 400 InvalidArgument instead of capping the page
Labels: bug
Refs: none

## Summary

The ListObjects, ListObjectsV2 and ListObjectVersions query parsers reuse the response page bound `S3.Core.Page_Size'Last` as a request validity bound, so a `max-keys` above 1000 raises `Malformed_List_Request` and the server answers 400 `InvalidArgument`. The pinned model describes the parameter as a ceiling on the response, not a constraint on the request, and MinIO answers the same request with 200 and echoes the value back. A stock `aws s3api list-objects-v2 --max-keys 2000` therefore fails against a Flyology server and succeeds against MinIO, and any SDK paginator that passes a caller-supplied `MaxKeys` through does the same.

## Problem

Commit `5fe6e3e`.

All three query parsers compare against the page bound and raise. ListObjects v1 (`src/flyology-object_storage-s3-listings.adb:111-118`):

```ada
                  if Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Max_Keys or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_List_Request with
                          "invalid ListObjects max-keys";
                     end if;
```

ListObjectsV2 (`src/flyology-object_storage-s3-listings.adb:223-230`):

```ada
                  elsif Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Max_Keys or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 max-keys";
                     end if;
```

ListObjectVersions (`src/flyology-object_storage-s3-versions.adb:134-141`):

```ada
                  elsif Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Maximum or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_Version_Request with
                          "invalid ListObjectVersions max-keys";
                     end if;
```

The bound is a visible subtype in the public specification (`src/flyology-object_storage-s3-core.ads:27-28`):

```ada
   --  Requested or returned item count for one S3 page.
   subtype Page_Size is Natural range 0 .. 1_000;
```

and the server turns the exception into a 400 (`src/flyology-object_storage-server-s3_applications.adb:10763-10767`):

```ada
               exception
                  when Listings.Malformed_List_Request =>
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ListObjects request is invalid", Target_Text);
```

with the same shape in the two neighbouring listing handlers.

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) puts no bound on the value and states in its own documentation that the parameter caps the response. Printed with `python3`, markup stripped:

```
ListObjects ListObjectsRequest MaxKeys: {"shape": "MaxKeys", "location": "querystring", "locationName": "max-keys"} shape def: {"type": "integer"}
ListObjectsV2 ListObjectsV2Request MaxKeys: {"shape": "MaxKeys", "location": "querystring", "locationName": "max-keys"} shape def: {"type": "integer"}
ListObjectVersions ListObjectVersionsRequest MaxKeys: {"shape": "MaxKeys", "location": "querystring", "locationName": "max-keys"} shape def: {"type": "integer"}
```

```
ListObjectsV2 -> Sets the maximum number of keys returned in the response. By default, the action returns up to 1,000 key names. The response might contain fewer keys but will never contain more.
```

The same sentence appears for ListObjects, and ListObjectVersions repeats it with the truncation rule appended. The `MaxKeys` shape is a plain integer with no `min` or `max`.

MinIO answers the request. The pinned image, `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` from `tests/scripts/test-minio.sh:5`, whose `--version` prints `minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`, answered a signed `GET /bucket?max-keys=2000` with 200 and echoed the value:

```
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">...<Marker></Marker><MaxKeys>2000</MaxKeys><IsTruncated>false</IsTruncated>...
```

and `GET /bucket?max-keys=2000&versions` likewise with `<MaxKeys>2000</MaxKeys>`. Driven through aws-cli 2.36.34, `list-objects --max-keys 2000`, `list-objects-v2 --max-keys 2000` and `list-object-versions --max-keys 2000` all returned 200 against that MinIO.

The same three commands against this crate's own application, on its loopback listener with aws-cli 2.36.34 and no checksum or retry configuration:

```
$ aws s3api list-objects-v2 --bucket stock-versioning --max-keys 2000
An error occurred (InvalidArgument) when calling the ListObjectsV2 operation: The ListObjectsV2 request is invalid
$ aws s3api list-objects --bucket stock-versioning --max-keys 5000
An error occurred (InvalidArgument) when calling the ListObjects operation: The ListObjects request is invalid
$ aws s3api list-object-versions --bucket stock-versioning --max-keys 2000
An error occurred (InvalidArgument) when calling the ListObjectVersions operation: The ListObjectVersions request is invalid
$ aws s3api list-objects-v2 --bucket stock-versioning --max-keys 1000
{
    "IsTruncated": false,
    "Name": "stock-versioning",
    "Prefix": "",
    "MaxKeys": 1000,
    "EncodingType": "url",
    "KeyCount": 0
}
```

Nothing documents the rejection as a rule. `docs/compatibility/s3.md:861-864` describes the backend page contract, not the accepted request domain:

```
ListObjects v1 and v2 use the same bounded backend page contract across
memory, files, and SQLite. Both provide bytewise lexical ordering, prefix
filtering, delimiter/CommonPrefixes grouping, max-keys 0..1000, URL-encoded
response fields, 64-bit sizes, quoted ETags, and fixed-length XML responses.
```

and the two listing qualification documents mention 1000 only as the modeled default.

The typed client cannot express the value, since `Low_Level.List_Objects_Parameters.Max_Keys` is `S3.Core.Page_Size`, so only the server side refuses. No existing test in `tests/src/object_storage_test_cases.adb` or `tests/src/s3_server_application_corpus.adb` asserts a rejection for values above 1000; the listing query blocks exercise 0, 1 and 2 only.

## What happens now

Spike: the program below creates a bucket and one object in the in-process S3 application, then sends six signed GETs: `?max-keys=1000`, `?list-type=2&max-keys=1000` and `?versions&max-keys=1000` as controls, then the same three at 2000.

```ada
      Response : constant String :=
        Run (Signed_Request ("GET", Bucket, "", "", Query));
      Status   : constant Natural := Status_Code (Response);
...
   Probe ("GET ?max-keys=2000                 ",
          [SigV4.Pair ("max-keys", "2000")], True);
   Probe ("GET ?list-type=2&max-keys=2000     ",
          [SigV4.Pair ("list-type", "2"), SigV4.Pair ("max-keys", "2000")],
          True);
   Probe ("GET ?versions&max-keys=2000        ",
          [SigV4.Pair ("max-keys", "2000"), SigV4.Pair ("versions", "")],
          True);
```

Output, exit status 1:

```
  -- CreateBucket /domain-a-6 status 200
  -- PutObject /domain-a-6/k1 status 200
  -- GET ?max-keys=1000                  -> 200
  ok: GET ?max-keys=1000                  is accepted
  -- GET ?list-type=2&max-keys=1000      -> 200
  ok: GET ?list-type=2&max-keys=1000      is accepted
  -- GET ?versions&max-keys=1000         -> 200
  ok: GET ?versions&max-keys=1000         is accepted
  -- GET ?max-keys=2000                  -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjects request is invalid</Message><Resource>/domain-a-6?max-keys=2000</Resource></Error>
  FAILED: GET ?max-keys=2000                  is accepted
  -- GET ?list-type=2&max-keys=2000      -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjectsV2 request is invalid</Message><Resource>/domain-a-6?list-type=2&amp;max-keys=2000</Resource></Error>
  FAILED: GET ?list-type=2&max-keys=2000      is accepted
  -- GET ?versions&max-keys=2000         -> 400
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjectVersions request is invalid</Message><Resource>/domain-a-6?max-keys=2000&amp;versions</Resource></Error>
  FAILED: GET ?versions&max-keys=2000         is accepted
BUG REPRODUCED: 3 failed expectation(s)
```

The three failing requests differ from their controls only in the digits of `max-keys`, so routing, signing and the rest of the query parsing are not what fires.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image, and against aws-cli 2.36.34 driven at both servers. Shapes checked against the pinned botocore S3 model.

## What should happen

`max-keys` above 1000 must be honoured as a request for at most that many keys, and the server must return a page bounded by its own maximum. That is what the pinned model's own documentation for the parameter describes, and what MinIO does. A negative or non-numeric value, and a repeated `max-keys`, must still be refused.

## Suggested treatment

This needs a maintainer decision, because the bound is the visible subtype `S3.Core.Page_Size` (`src/flyology-object_storage-s3-core.ads:27-28`), which the "Ada interface values" section of `AGENTS.md` puts under explicit approval:

- Clamp in the three query parsers. Replace the `Number.Value > Core.Page_Size'Last` disjunct at `src/flyology-object_storage-s3-listings.adb:114` and `:226` and `src/flyology-object_storage-s3-versions.adb:137` with an assignment of `Core.Page_Size'Last` when the parsed value exceeds it, keeping the "repeated" and "not valid" disjuncts. No public declaration changes, every response bound and every backend page contract stays exactly as it is, and the behaviour is what the model's own wording describes.
- Widen the request-side bound into a separate, wider subtype. This adds a public declaration whose value, name, type and visibility are a separate decision, and it changes what a caller may put in `List_Objects_Parameters.Max_Keys`.

The first option is the smaller change and leaves the interface untouched.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the existing ListObjects query block at `:16527-16533`: send `max-keys=2000` on each of the three listing operations and require 200 with `<MaxKeys>` reporting the server's own bound, keeping a case for a malformed and a repeated `max-keys` that still expects 400 `InvalidArgument`. The spike is the test. No existing test asserts the current rejection, so nothing has to be inverted. If the clamp is chosen, `docs/compatibility/s3.md:861-864` stays correct as written, because it describes the backend page contract rather than the request domain.

## Severity

A stock tool pointed at a Flyology endpoint with an explicit page hint above 1000 gets a hard 400 instead of a page: `aws s3api list-objects-v2 --max-keys 2000` is the plainest case, and an SDK paginator that forwards a caller-supplied `MaxKeys` behaves the same. No default invocation reaches it, because the user has to ask for more than 1000, and the caller can work around it by asking for 1000 or fewer. Nothing is lost or corrupted; the refusal is an honest 400 with a correct error code, and the response side is unaffected. The typed Flyology client cannot express the value at all, so this is a server-side defect only. Deterministic.
