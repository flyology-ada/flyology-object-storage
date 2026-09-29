Title: A HeadBucket rejection discards x-amz-bucket-region, so Head cannot report where a redirected bucket lives
Labels: bug
Refs: none

## Summary

`Decode_Head_Bucket_Complete_Response` parses `x-amz-bucket-region` out of every HeadBucket response and hands it to `Decode_Head_Bucket_Response`, which uses it only on a 200 and discards it on every other status. The rejected variants of both the low-level outcome and the convenience outcome have no field a region could occupy, so the loss is structural: no caller of the typed decoder, the composable operation or the convenience `Head` can recover the one datum a HeadBucket redirect exists to convey. `Head` is documented as the call that reports a bucket's availability and region, and it meets that promise only on 200.

## Problem

Commit `5fe6e3e`.

The complete-response decoder captures the header for every status (`src/flyology-object_storage-client-low_level.adb:4956-4968`):

```ada
         Headers : constant Head_Bucket_Result :=
           (Bucket_ARN           => H ("x-amz-bucket-arn"),
            Bucket_Location_Type => H ("x-amz-bucket-location-type"),
            Bucket_Location_Name => H ("x-amz-bucket-location-name"),
            Bucket_Region        => H ("x-amz-bucket-region"),
            Access_Point_Alias   => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-access-point-alias")));
      begin
         return Decode_Head_Bucket_Response
           (Flyology.HTTP.Client.Status (Response), Payload, Headers,
            Flyology.HTTP.Client.Header (Response, "x-amz-request-id"),
            Flyology.HTTP.Client.Header (Response, "x-amz-id-2"));
```

`Decode_Head_Bucket_Response` consults `Headers` only inside the 200 branch and never mentions it again (`src/flyology-object_storage-client-low_level.adb:4906-4913`):

```ada
         return (Kind => Bucket_Found, Status => Status, Result => Headers);
      else
         return
           (Kind   => Head_Bucket_Rejected,
            Status => Status,
            Error  => Head_Error
              ("HeadBucket", Status, Request_ID, Host_ID));
      end if;
```

`Head_Error` synthesises the whole error from the status, so there is no field a region could hide in (`src/flyology-object_storage-client-low_level.adb:4865-4871`):

```ada
      return
         (Code       => US.To_Unbounded_String ("HTTP" & Status_Text),
         Message    => US.To_Unbounded_String
           (Operation & " returned HTTP status " & Status_Text),
         Resource   => US.Null_Unbounded_String,
         Request_ID => US.To_Unbounded_String (Request_ID),
         Host_ID    => US.To_Unbounded_String (Host_ID));
```

The rejected variant carries exactly `Status` and `Error` (`src/flyology-object_storage-client-low_level.ads:1391-1405`):

```ada
   --  Completed HeadBucket response.
   --  @field Kind Active response variant
   --  @field Status Carried HTTP response status
   --  @field Result Successful bucket metadata
   --  @field Error Synthesized bodyless rejection
   type Head_Bucket_Outcome
     (Kind : Head_Bucket_Outcome_Kind := Head_Bucket_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Found =>
            Result : Head_Bucket_Result;
         when Head_Bucket_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;
```

The convenience outcome has the same shape, with `Region` only on the available variant (`src/flyology-object_storage-client-buckets.ads:10129-10142`):

```ada
   type Head_Outcome
     (Kind : Head_Outcome_Kind := Head_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Available =>
            Bucket_ARN           : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_Location_Type : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_Location_Name : Ada.Strings.Unbounded.Unbounded_String;
            Region               : Ada.Strings.Unbounded.Unbounded_String;
            Access_Point_Alias   : Low_Level.Optional_Boolean;
         when Head_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;
```

and the convenience body simply forwards the rejection (`src/flyology-object_storage-client-buckets.adb:2835-2838`):

```ada
            if Outcome.Kind = Low_Level.Head_Bucket_Rejected then
               return
                 (Kind => Head_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
```

The contract this breaks is the documented purpose of the call (`src/flyology-object_storage-client-buckets.ads:10172-10179`):

```ada
   --  Probe one bucket without downloading a response body. Successful
   --  results preserve every modeled HeadBucket response header and expose
   --  the bucket region under the convenience-level Region name. If a
   --  compatible server omits the optional response header, Region falls
   --  back to the region used to sign the request.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose availability and region are requested
```

The region is requested, and on any status other than 200 it is parsed and then thrown away.

The redirect is additionally reported as a request rejection (`src/flyology-object_storage-client-buckets.adb:4806-4807`):

```ada
         elsif Value.Status in 301 | 307 | 400 | 501
         then Invalid_Request
```

`src/flyology-object_storage-client.ads:26` defines that reason as `Invalid_Request Local or modeled service request rejection`. A redirect is not a rejection of the request.

This is not a stated exclusion. `docs/qualification/head-bucket-composable.md:26-28` excludes redirect following, not exposing the region a redirect carries:

```
Directory-bucket and S3 Express endpoint selection, access-point, Object
Lambda, and Outposts endpoint discovery or rewriting, and cross-region
redirect following remain outside this focused lane.
```

The pinned model does not settle it either way. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```
HeadBucketOutput required: None
BucketRegion: {'shape': 'Region', 'location': 'header', 'locationName': 'x-amz-bucket-region'}
HeadBucket errors: [{'shape': 'NoSuchBucket'}]
```

so `BucketRegion` is modelled as that header on the output shape, and the only modelled error is `NoSuchBucket`. The model neither requires nor forbids the header on a non-200 status. That AWS attaches `x-amz-bucket-region` to the 301 it returns for a bucket in another region was not checked against a live AWS endpoint. MinIO was checked and does not redirect at all: a HeadBucket signed with an `eu-west-1` credential scope against a bucket the pinned MinIO release reports as `us-east-1` answers `200 OK` with no `x-amz-bucket-region` header, so no server in the maintained matrix can produce the shape and the spike supplies the header itself.

Two existing assertions pin the discard. `tests/src/flyology-object_storage-client-buckets-testing.adb:583-584`:

```ada
      Check_Head_Bucket_Response (301, Invalid_Request);
      Check_Head_Bucket_Response (307, Invalid_Request);
```

and the helper those rows use builds the outcome from the status alone, with no headers at all (`tests/src/flyology-object_storage-client-buckets-testing.adb:503-515`):

```ada
   procedure Check_Head_Bucket_Response
     (Status  : Flyology.HTTP.Status_Code;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Head_Bucket_Outcome :=
        (if Status = 200
         then (Kind => Low_Level.Bucket_Found,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Head_Bucket_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String ("HTTP"),
```

so no test ever supplies `x-amz-bucket-region` on a non-200. The socket corpus does serve that header, but only on 200 responses (`tests/src/s3_http_socket_corpus.adb:2874`, `:2912`).

## What happens now

Spike: the program below works at two layers. It first calls the public `Low_Level.Decode_Head_Bucket_Response` with `Status => 301` and a `Head_Bucket_Result` whose `Bucket_Region` is `eu-west-1`, prints every readable field of the returned outcome and asserts the region is still somewhere in it. It then serves `HEAD /flyology-elsewhere` from a scripted loopback origin as `301 Moved Permanently` with `Content-Length: 0` and `x-amz-bucket-region: eu-west-1`, and drives both the convenience `Head` and the parameter-record `Head`. Four control legs repeat every leg with `200 OK` and the same header.

```ada
   Bucket : constant String := "flyology-elsewhere";
   Elsewhere : constant String := "eu-west-1";
   Signing_Region : constant String := "us-east-1";
...
      Headers : constant Low_Level.Head_Bucket_Result :=
        (Bucket_ARN           => US.Null_Unbounded_String,
         Bucket_Location_Type => US.Null_Unbounded_String,
         Bucket_Location_Name => US.Null_Unbounded_String,
         Bucket_Region        => US.To_Unbounded_String (Elsewhere),
         Access_Point_Alias   => (others => <>));
      Outcome : constant Low_Level.Head_Bucket_Outcome :=
        Low_Level.Decode_Head_Bucket_Response
          (Status, "", Headers, "AMZREQ1", "AMZHOST1");
...
            Note (Label & ": every readable field = " & Readable);
            Check (Contains_Region (Readable),
                   Label & ": the decoded rejection still reports " &
                     Elsewhere);
```

The scripted response and the two public calls:

```ada
   function Head_Response (Status_Line : String) return String is
     ("HTTP/1.1 " & Status_Line & CRLF &
      "Content-Length: 0" & CRLF &
      "x-amz-bucket-region: " & Elsewhere & CRLF &
      "x-amz-request-id: AMZREQ1" & CRLF &
      "x-amz-id-2: AMZHOST1" & CRLF &
      "Server: AmazonS3" & CRLF &
      "Connection: close" & CRLF & CRLF);
...
      Result : constant Buckets.Head_Outcome :=
        Buckets.Head
          (HTTP, Origin, Bucket, Identity, Region => Signing_Region,
           Timeout => 10.0);
...
            Check (Contains_Region (Readable),
                   Label & ": Head still reports " & Elsewhere &
                     " after the redirect");
...
      Result : constant Buckets.Head_Bucket_Result :=
        Buckets.Head
          (HTTP, Origin, Bucket, Parameters, Identity,
           Region => Signing_Region, Timeout => 10.0);
...
            Check (Contains_Region (Readable),
                   Label & ": the composable result still reports " &
                     Elsewhere);
```

Output, exit status 1:

```
  -- --- typed decoder, 301 with x-amz-bucket-region: eu-west-1 ---
  -- decode 301: decoded kind HEAD_BUCKET_REJECTED, status 301
  -- decode 301: every readable field = HTTP301|HeadBucket returned HTTP status 301||AMZREQ1|AMZHOST1
  FAILED: decode 301: the decoded rejection still reports eu-west-1
  -- --- typed decoder control, 200 with the same header ---
  -- decode 200: decoded kind BUCKET_FOUND, status 200
  -- decode 200: Result.Bucket_Region = "eu-west-1"
  ok: decode 200: the decoder keeps x-amz-bucket-region
  -- scripted loopback origin on 127.0.0.1:58243
  -- --- Client.Buckets.Head over the origin, 301 redirect ---
  -- convenience 301: Head kind HEAD_REJECTED, status 301
  -- convenience 301: every readable field = HTTP301|HeadBucket returned HTTP status 301||AMZREQ1|AMZHOST1
  FAILED: convenience 301: Head still reports eu-west-1 after the redirect
  -- composable 301: response kind HEAD_BUCKET_REJECTED, status 301, Failure = INVALID_REQUEST
  -- composable 301: every readable field = HTTP301|HeadBucket returned HTTP status 301|
  FAILED: composable 301: the composable result still reports eu-west-1
  -- --- control: the same header on a 200 ---
  -- convenience 200: Head kind BUCKET_AVAILABLE, status 200
  -- convenience 200: Region = "eu-west-1"
  ok: convenience 200: Head reports eu-west-1
  -- composable 200: response kind BUCKET_FOUND, status 200, Failure = NO_FAILURE
  ok: composable 200: the composable result reports eu-west-1
  -- request 1: HEAD /flyology-elsewhere HTTP/1.1
  -- request 2: HEAD /flyology-elsewhere HTTP/1.1
  -- request 3: HEAD /flyology-elsewhere HTTP/1.1
  -- request 4: HEAD /flyology-elsewhere HTTP/1.1
  ok: the origin served all four exchanges
BUG REPRODUCED: 3 failed expectation(s)
```

The control legs differ from the failing legs only in the status line, and they report `eu-west-1` through both APIs, so the header is parsed correctly and is present in `Headers` at the moment the non-200 branch drops it. The three failing legs print every readable field of the rejection, and the region is in none of them.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A HeadBucket rejection that carries `x-amz-bucket-region` should let the caller read that region, because `src/flyology-object_storage-client-buckets.ads:10179` documents `Head` as the call by which a bucket's "availability and region are requested" and the pinned model defines `BucketRegion` as exactly that response header. A 301 should also not be reported as `Invalid_Request`, which `src/flyology-object_storage-client.ads:26` reserves for a request rejection.

## Suggested treatment

The fix adds a component to public variant records, so this needs a maintainer decision under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`:

- Add a region component to the rejected variants of `Low_Level.Head_Bucket_Outcome` (`src/flyology-object_storage-client-low_level.ads:1396-1405`) and `Buckets.Head_Outcome` (`src/flyology-object_storage-client-buckets.ads:10129-10142`), and pass `Headers.Bucket_Region` through the `else` branch at `src/flyology-object_storage-client-low_level.adb:4907-4913`. Smallest surface, but it publishes a component that is empty for every server in the maintained matrix.
- Carry the whole modelled header set on the rejected variants, by replacing the rejection's payload with `Status`, `Error` and `Result : Head_Bucket_Result`. Uniform with the 200 branch and future-proof for `x-amz-bucket-arn` and the location members, at the cost of a larger public record.
- Fold the value into the synthesised `Error` at `src/flyology-object_storage-client-low_level.adb:4865-4871`, for example as `Resource`. No record changes, but it changes the documented meaning of an existing field and makes the region something callers have to parse out of a message.

Whichever is chosen, the `301 | 307` arm at `src/flyology-object_storage-client-buckets.adb:4806-4807` should stop reporting a redirect as `Invalid_Request`; picking a different reason is itself a change to a documented public enum, so it belongs in the same decision.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, in the HeadBucket socket block that already scripts `x-amz-bucket-region` on 200 responses (`:2874`, `:2912`): add a `301 Moved Permanently` response with `Content-Length: 0` and that header, and require the region to be readable from both the convenience and the parameter-record results. The rows at `tests/src/flyology-object_storage-client-buckets-testing.adb:583-584` assert `(301, Invalid_Request)` and `(307, Invalid_Request)` and must change if the redirect reason changes; the helper at `:503-522` has no header parameter and needs one before it can express the new case. This case is not observable against any server in the maintained matrix, so `tests/src/s3_implementation_corpus.adb` cannot cover it. The spike is the test.

## Severity

A caller that signs for one region and probes a bucket that lives in another gets a rejection carrying `HTTP301` and nothing else, and has no way, short of driving the raw HTTP exchange itself, to learn the region the server just told it. That defeats the documented purpose of `Head` and makes automatic retargeting impossible on top of this client. Reaching it needs a cross-region bucket plus a signing region that does not match, which is an unusual configuration rather than an everyday call, and no server in the maintained six-server matrix produces the shape: the pinned MinIO release answers `200 OK` with no region header instead of redirecting. The AWS behaviour the case rests on was not checked against a live endpoint, so the spike supplies the header itself. The discard is a branch in a pure decoder, with no timing or state involved. Deterministic; not reproduced against a live server.
