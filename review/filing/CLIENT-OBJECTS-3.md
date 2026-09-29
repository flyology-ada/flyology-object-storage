Title: GetObjectTorrent labels a 500 or 503 rejection No_Failure instead of Unavailable_Or_Retryable
Labels: bug
Refs: none

## Summary

`Normalize_Get_Object_Torrent_Response` assigns `Failure => No_Failure` to every complete GetObjectTorrent response, with no reference to the decoded status or S3 error code. Every other normalizer in the same package classifies those pairs, so a `503 SlowDown` or `500 InternalError` answered to `?torrent` carries `No_Failure` while the identical response answered to GetObjectAcl, GetObjectTagging, GetObjectLegalHold or GetObjectRetention on the same client carries `Unavailable_Or_Retryable`. A caller that routes retry policy off the shared `Failure_Reason` domain therefore does not retry a transient service rejection on this one operation.

## Problem

Commit `5fe6e3e`.

The torrent normalizer returns a constant (`src/flyology-object_storage-client-objects.adb:5200-5210`):

```ada
   function Normalize_Get_Object_Torrent_Response
     (Value     : Low_Level.Get_Object_Torrent_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Object_Torrent_Result is
   begin
      return
        (Kind      => Get_Object_Torrent_Response_Available,
         Failure   => No_Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Get_Object_Torrent_Response;
```

`Value.Kind`, `Value.Status` and the error `Code` are all available and none is consulted. The sibling normalizer for GetObjectAcl, in the same file, classifies them (`src/flyology-object_storage-client-objects.adb:4899-4934`):

```ada
   function Normalize_Get_Object_ACL_Response
     (Value     : Low_Level.Get_Object_ACL_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Object_ACL_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Object_ACL_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Object_ACL_Found
         then No_Failure
...
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
         then Not_Found
...
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
```

Twelve normalizers in this file carry that same retryable table, among them the object tagging helper (`Retryable_Object_Tag_Response`, `src/flyology-object_storage-client-objects.adb:7228`) and the object-lock helper used by the legal-hold and retention results (`Object_Lock_Response_Failure`, `:4876`, applied at `:5622`, `:5922`, `:6202` and `:6463`). `tests/corpora/composable-client/put-certainty.tsv` records the same mapping as the maintained policy for the mutating operations.

`Failure_Reason` is a single shared domain, not a per-operation one (`src/flyology-object_storage-client.ads:22-23`):

```ada
   --  Stable reason domain shared by composable provider results.
   --  @enum No_Failure Successful or conclusively failed condition
```

and the torrent result record uses the same field wording as the other twenty result records in the package (`src/flyology-object_storage-client-objects.ads:1527`):

```ada
   --  @field Failure Bounded expected failure reason
```

A `503 SlowDown` is neither a success nor a conclusive failure, so `No_Failure` misstates it. This is not an admission artefact: the normalizer is reached only for a decoded complete response (`src/flyology-object_storage-client-objects.adb:5416-5423`):

```ada
                  if Outcome.Kind =
                    Low_Level.Get_Object_Torrent_Rejected
                  then
                     Clear_Buffer (Item.Destination.all);
                  end if;
                  Item.Final_Result :=
                    Normalize_Get_Object_Torrent_Response
                      (Outcome, HTTP_Client.Certainty (HTTP_Result));
```

No test covers a well-formed retryable rejection on this path. The torrent corpus asserts `No_Failure` only for a `404` (`tests/src/s3_get_object_torrent_socket_corpus.adb:701-708`):

```ada
            if Result.Kind /=
                Objects.Get_Object_Torrent_Response_Available
              or else Result.Failure /= Client_API.No_Failure
              or else Result.Response.Kind /=
                Low_Level.Get_Object_Torrent_Rejected
              or else Result.Response.Status /= 404
              or else Buffers.Length (Destination) /= 0
            then
```

and its only `500` scenarios serve bodies that take the `Response_Invalid` path instead of producing a decoded rejection (`tests/src/s3_get_object_torrent_socket_corpus.adb:341-348`):

```ada
               elsif Scenario = "malformed-error" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("500 Internal Server Error",
                        "<Error><Unknown/></Error>"));
               elsif Scenario = "error-limit" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response ("500 Internal Server Error", Error_XML));
```

So the retryable statuses can be corrected without contradicting an existing assertion. There is no torrent certainty corpus under `tests/corpora/composable-client/` and no torrent-specific policy in the specification, so nothing documents a different domain for this operation.

## What happens now

Spike: the program below scripts five exchanges on a loopback origin and demonstrates both sides in one run. A well-formed `503 Service Unavailable` with `<Code>SlowDown</Code>` and a `500 Internal Server Error` with `<Code>InternalError</Code>` are answered to `Get_Torrent` and asserted to carry `Unavailable_Or_Retryable`. A `404 NoSuchKey` is answered to `Get_Torrent` and only reported, because the existing corpus assertion fixes that label. The identical `503` is then answered to `Get_ACL` as a control, and a `200 OK` torrent body as a second control.

```ada
   function Error_XML (Code : String) return String is
     ("<Error><Code>" & Code & "</Code><Message>service is busy</Message>" &
      "<Resource>/example-bucket/native-object</Resource></Error>");
...
         Result : constant Objects.Get_Object_Torrent_Result :=
           Objects.Get_Torrent
             (HTTP, Origin, Bucket, Key, Parameters, Destination, Identity,
              Timeout => 10.0);
      begin
...
            Check (Result.Failure = Expected,
                   Label & ": Failure is " &
                     Client_API.Failure_Reason'Image (Expected) &
                     ", as every sibling normalizer assigns for this " &
                     "status and code");
...
      Result : constant Objects.Get_Object_ACL_Result := Objects.Get_ACL
        (HTTP, Origin, Bucket, "native-object", Parameters, Identity,
         Timeout => 10.0);
...
   Run_Torrent
     ("503 SlowDown torrent", "busy-object",
      Client_API.Unavailable_Or_Retryable, Assert => True);
   Run_Torrent
     ("500 InternalError torrent", "faulted-object",
      Client_API.Unavailable_Or_Retryable, Assert => True);
...
   Run_ACL ("503 SlowDown ACL", Client_API.Unavailable_Or_Retryable);
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:60700
  -- --- GetObjectTorrent: well-formed transient S3 rejections ---
  -- 503 SlowDown torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- 503 SlowDown torrent: response Kind = GET_OBJECT_TORRENT_REJECTED, status 503, code SlowDown, destination length 0
  ok: 503 SlowDown torrent: the rejection is a complete modeled response
  FAILED: 503 SlowDown torrent: Failure is UNAVAILABLE_OR_RETRYABLE, as every sibling normalizer assigns for this status and code
  -- 500 InternalError torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- 500 InternalError torrent: response Kind = GET_OBJECT_TORRENT_REJECTED, status 500, code InternalError, destination length 0
  ok: 500 InternalError torrent: the rejection is a complete modeled response
  FAILED: 500 InternalError torrent: Failure is UNAVAILABLE_OR_RETRYABLE, as every sibling normalizer assigns for this status and code
  -- --- reported only: 404 is asserted as No_Failure by tests/src/s3_get_object_torrent_socket_corpus.adb:703 ---
  -- 404 NoSuchKey torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE
  -- 404 NoSuchKey torrent: response Kind = GET_OBJECT_TORRENT_REJECTED, status 404, code NoSuchKey, destination length 0
  -- --- control: the identical 503 answered to GetObjectAcl ---
  -- 503 SlowDown ACL: Get_ACL Kind = GET_OBJECT_ACL_RESPONSE_AVAILABLE, Failure = UNAVAILABLE_OR_RETRYABLE
  -- 503 SlowDown ACL: response Kind = GET_OBJECT_ACL_REJECTED, status 503, code SlowDown
  ok: 503 SlowDown ACL: the rejection is a complete modeled response
  ok: 503 SlowDown ACL: Failure is UNAVAILABLE_OR_RETRYABLE
  -- --- control: a 200 GetObjectTorrent success ---
  -- 200 torrent: Get_Torrent Kind = GET_OBJECT_TORRENT_RESPONSE_AVAILABLE, Failure = NO_FAILURE, destination length 18
  ok: 200 torrent: a 200 torrent read is a complete response
  ok: 200 torrent: a success carries No_Failure
  ok: 200 torrent: outcome is Torrent_Opened
  ok: 200 torrent: destination holds the torrent bytes
  -- request 1: GET /example-bucket/busy-object?torrent HTTP/1.1
  -- request 2: GET /example-bucket/faulted-object?torrent HTTP/1.1
  -- request 3: GET /example-bucket/absent-object?torrent HTTP/1.1
  -- request 4: GET /example-bucket/native-object?acl HTTP/1.1
  -- request 5: GET /example-bucket/native-object?torrent HTTP/1.1
  ok: the origin served all five scripted exchanges
BUG REPRODUCED: 2 failed expectation(s)
```

The response payload itself is correct in every leg: the rejection decodes, the status and code are present, and the destination is empty as it should be. Only the `Failure` label differs from what the same client reports for the same bytes on the ACL path.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A decoded GetObjectTorrent rejection should carry the same `Failure_Reason` that every other operation in the package assigns for the same status and S3 error code, because `src/flyology-object_storage-client.ads:22` presents `Failure_Reason` as one stable domain shared by all composable results and defines `No_Failure` as a successful or conclusively failed condition. A `503 SlowDown` and a `500 InternalError` are transient service rejections and belong to `Unavailable_Or_Retryable`.

## Suggested treatment

Give `Normalize_Get_Object_Torrent_Response` a `Failure` expression instead of the constant, in the shape `Normalize_Get_Object_ACL_Response` already uses at `src/flyology-object_storage-client-objects.adb:4904-4934`: derive `Code` from `Value.Error.Code` when `Value.Kind = Low_Level.Get_Object_Torrent_Rejected`, keep `No_Failure` for `Torrent_Opened`, and keep `Corrupt_Or_Invalid_Response` when `Admission /= HTTP_Client.Response_Observed`.

How much of the sibling table to adopt needs a maintainer decision, because one of its rows contradicts an existing assertion:

- Map only the six retryable pairs (`409 OperationAborted`, `429 SlowDown`, `500 InternalError`, `502 BadGateway`, `503 SlowDown`, `504 RequestTimeout`) to `Unavailable_Or_Retryable` and leave every other decoded rejection at `No_Failure`. This closes the retry divergence and changes no existing test, since `tests/src/s3_get_object_torrent_socket_corpus.adb:703` covers only a `404`. It leaves the torrent path reporting `No_Failure` for an authentication or authorization rejection, which no sibling does.
- Reuse the ACL table whole, so `404 NoSuchKey` becomes `Not_Found`, `401 InvalidAccessKeyId` becomes `Authentication_Failed`, and an unmodeled rejection becomes `Corrupt_Or_Invalid_Response`. This makes the operation consistent with the rest of the package and changes the value a caller sees for a `404`, so `tests/src/s3_get_object_torrent_socket_corpus.adb:703` has to be updated from `No_Failure` to `Not_Found`.

The regression test belongs in `tests/src/s3_get_object_torrent_socket_corpus.adb`, alongside the existing `provider-rejection` case: add scenarios serving a well-formed `503 SlowDown` and `500 InternalError` error document and assert `Unavailable_Or_Retryable`, which the corpus does not cover today because its only `500` cases are the malformed and over-limit bodies at `:341-348`. The spike is the test.

## Severity

The value is a label. The response payload is complete and correct, no bytes or state are lost, and a caller can still read `Response.Kind`, `Response.Status` and `Response.Error.Code` and decide for itself. The harm falls on a caller that uses the shared `Failure_Reason` domain for retry policy, which is what that domain is for: it will not retry a `503 SlowDown` or `500 InternalError` from GetObjectTorrent while retrying the identical response from every other operation on the same client. It needs no unusual input, only a server that answers `?torrent` with a transient error. Deterministic.
