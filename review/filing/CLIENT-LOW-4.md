Title: A bodyless or non-XML 4xx becomes Invalid_Response instead of a typed rejection with the wire status
Labels: bug
Refs: none

## Summary

`S3.Errors.Parse` raises `Malformed_Error` for any non-2xx body that is absent, whitespace, HTML or otherwise not an S3 `<Error>` document, and the response decoders in the low-level client convert that into `Invalid_Response`, discarding the HTTP status. A reverse proxy answering 503 with an HTML page, or a peer answering 403 with no body, therefore reaches a synchronous caller as a protocol failure with no status at all, and a composable caller as `Corrupt_Or_Invalid_Response` where `Unavailable_Or_Retryable` is the correct classification, so a transient outage is not retried. The repository has already made the opposite decision twice, unconditionally for HeadObject and with an explanatory comment for GetObject, so this is an internal inconsistency and every affected outcome type already carries the variant the fix needs.

## Problem

Commit `5fe6e3e`.

Error parsing raises on an empty or non-`<Error>` document (`src/flyology-object_storage-s3-errors.adb:116-127`):

```ada
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Code
        or else not Handler.Seen_Message
        or else US.Length (Handler.Value.Code) = 0
        or else US.Length (Handler.Value.Message) = 0
      then
         raise Malformed_Error with "S3 error lacks Code or Message";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Error with "malformed S3 error XML";
```

The decoders convert that into a client protocol failure. ListObjectsV2 is representative (`src/flyology-object_storage-client-low_level.adb:1957-1959`):

```ada
   exception
      when S3.Listings.Malformed_Listing | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjectsV2 response";
```

The same handler shape is repeated at more than sixty places in that one file. The operation decoders carrying it include ListObjects `:1694`, ListObjectsV2 `:1958`, ListObjectVersions `:2228`, CreateMultipartUpload `:3340`, CompleteMultipartUpload `:3884`, CreateBucket `:4369`, GetObjectAttributes `:5331`, PutObject `:7733`, bucket-configuration deletions `:8240`, bucket-control mutations `:10849`, DeleteObject `:11299`, object tagging `:12412`, DeleteObjects `:12732`, AbortMultipartUpload `:12925`, ListParts `:13193`, ListMultipartUploads `:13427`, UploadPart `:14044`, UploadPartCopy `:14426` and CopyObject `:14779`, plus every bucket-control GET between `:8875` and `:9784`.

The status the caller loses is available at the point of the conversion. The same decoder returns it on the path where the body does parse (`src/flyology-object_storage-client-low_level.adb:1954`):

```ada
            return (Kind => Rejected, Status => Status, Error => Value);
```

so every affected outcome type already has a `Rejected` variant carrying the wire status and no new public type is needed.

GetObject deliberately does the opposite, and says why (`src/flyology-object_storage-client-low_level.adb:7148-7165`):

```ada
            begin
               return
                 (Kind   => Get_Object_Rejected,
                  Status => Status,
                  Error  => Error_Response
                    (Text, Request_ID, Host_ID, Limits));
            exception
               when S3.Errors.Malformed_Error =>
                  --  S3 peers and intermediaries may return bodyless or
                  --  non-XML HTTP errors.  Preserve the typed rejection and
                  --  wire status instead of turning a valid rejection into
                  --  a client protocol failure.
                  return
                    (Kind   => Get_Object_Rejected,
                     Status => Status,
                     Error  => Head_Error
                       ("GetObject", Status, Request_ID, Host_ID));
            end;
```

`Head_Error` is the shape those tolerant paths return (`src/flyology-object_storage-client-low_level.adb:4865-4871`):

```ada
      return
         (Code       => US.To_Unbounded_String ("HTTP" & Status_Text),
         Message    => US.To_Unbounded_String
           (Operation & " returned HTTP status " & Status_Text),
         Resource   => US.Null_Unbounded_String,
         Request_ID => US.To_Unbounded_String (Request_ID),
         Host_ID    => US.To_Unbounded_String (Host_ID));
```

and HeadObject uses it for every non-2xx without consulting the body at all (`src/flyology-object_storage-client-low_level.adb:5673-5678`):

```ada
      else
         return
           (Kind   => Head_Object_Rejected,
            Status => Status,
            Error  => Head_Error
              ("HeadObject", Status, Request_ID, Host_ID));
```

In the composable families the exception becomes a corruption verdict (`src/flyology-object_storage-client-bounded_rest_xml_reads.adb:105-111`):

```ada
         exception
            when Low.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result), "");
```

which surfaces as `Corrupt_Or_Invalid_Response`, although the failure set has a separate value for exactly this case (`src/flyology-object_storage-client.ads:35` and `:50`):

```ada
   --  @enum Unavailable_Or_Retryable Modeled transient service response
```

No existing test asserts either behaviour, so nothing has to be inverted. Every 4xx and 5xx fixture in the socket corpus carries a well-formed `<Error>` body, for example a 503 at `tests/src/s3_http_socket_corpus.adb:3258-3264` and a 500 at `:5591-5597`:

```ada
         Serve
           (HTTP_Response
              ("503 Service Unavailable",
               "<Error><Code>SlowDown</Code>" &
                 "<Message>retry later</Message></Error>"),
```

and the only bodyless or non-XML error fixtures are the GetObject ones served to the already tolerant path.

## What happens now

Spike: the program below scripts four exchanges on a loopback origin. A signed `ListObjectsV2` is answered `503 Service Unavailable` with `content-type: text/html` and an HTML body, and a signed `DeleteObject` is answered `403 Forbidden` with `content-length: 0`. Both assert the typed rejection with the wire status and the `HTTP<status>` code the tolerant paths already synthesise. Two control legs follow: a bodyless 503 on `HeadObject`, and a 503 carrying a well-formed `<Error>` document on `ListObjectsV2`.

```ada
   Proxy_503 : constant String :=
     "HTTP/1.1 503 Service Unavailable" & CRLF &
     "content-type: text/html" & CRLF &
     "content-length:" & HTML'Length'Image & CRLF &
     "Connection: close" & CRLF & CRLF & HTML;

   Empty_403 : constant String :=
     "HTTP/1.1 403 Forbidden" & CRLF &
     "content-length: 0" & CRLF &
     "Connection: close" & CRLF & CRLF;
...
         Outcome : constant Low_Level.List_Objects_V2_Outcome :=
           Low_Level.Execute_List_Objects_V2 (HTTP, Prepared, 10.0);
      begin
...
         Check (Outcome.Kind = Low_Level.Rejected,
                Label & ": a non-XML 5xx is a typed rejection carrying the " &
                  "wire status");
...
            Check (Outcome.Status = 503, Label & ": status is 503");
            Check (US.To_String (Outcome.Error.Code) = Expect_Code,
                   Label & ": Error.Code is """ & Expect_Code & """");
...
         Outcome : constant Low_Level.Delete_Object_Outcome :=
           Low_Level.Execute_Delete_Object (HTTP, Prepared, 10.0);
      begin
...
         Check (Outcome.Kind = Low_Level.Delete_Object_Rejected,
                Label & ": a bodyless 4xx is a typed rejection carrying the " &
                  "wire status");
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:50510
  -- every *_Outcome type already carries a Rejected variant with the wire Status; Head_Error (low_level.adb:4856-4872) synthesises Code = "HTTP<status>" for exactly this case
  -- --- 503 Service Unavailable with a text/html body ---
  -- html 503 ListObjectsV2: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : malformed ListObjectsV2 response
  FAILED: html 503 ListObjectsV2: a non-XML 5xx is a typed rejection carrying the wire status
  -- --- 403 Forbidden with Content-Length: 0 ---
  -- empty 403 DeleteObject: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : malformed DeleteObject response
  FAILED: empty 403 DeleteObject: a bodyless 4xx is a typed rejection carrying the wire status
  -- --- control: HeadObject, the route that already tolerates it ---
  -- control HEAD 503: Kind = HEAD_OBJECT_REJECTED, status 503
  ok: control HEAD 503: HEAD already maps a bodyless 5xx to the typed rejection
  -- control HEAD 503: Error.Code = HTTP503, Message = HeadObject returned HTTP status 503
  ok: control HEAD 503: Error.Code is "HTTP503"
  -- --- control: 503 carrying a well-formed <Error> document ---
  -- modeled 503 ListObjectsV2: Kind = REJECTED, status 503
  ok: modeled 503 ListObjectsV2: a non-XML 5xx is a typed rejection carrying the wire status
  -- modeled 503 ListObjectsV2: Error.Code = SlowDown, Message = Please reduce your request rate
  ok: modeled 503 ListObjectsV2: status is 503
  ok: modeled 503 ListObjectsV2: Error.Code is "SlowDown"
  -- request 1: GET /example-bucket?list-type=2&max-keys=1000 HTTP/1.1
  -- request 2: DELETE /example-bucket/native-object HTTP/1.1
  -- request 3: HEAD /example-bucket/native-object HTTP/1.1
  -- request 4: GET /example-bucket?list-type=2&max-keys=1000 HTTP/1.1
  ok: the origin served all four scripted exchanges
BUG REPRODUCED: 2 failed expectation(s)
```

The two control legs show both existing tolerant behaviours working: the same bodyless 503 that destroys the listing yields `Head_Object_Rejected` with `Error.Code = HTTP503` on the HEAD route, and a 503 that does carry an `<Error>` document yields `Rejected` with status 503 and `Error.Code = SlowDown` on the listing route. Only the non-XML and bodyless cases on the listing and delete routes fail.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A non-2xx response whose body is not an S3 `<Error>` document is a valid rejection whose HTTP status the caller needs, not a violation of a modeled contract. It should be reported through the `Rejected` variant of the operation's outcome, carrying the wire status and the synthesised `HTTP<status>` code, which is what `src/flyology-object_storage-client-low_level.adb:7148-7165` states for GetObject and what HeadObject does unconditionally at `:5673-5678`. `Invalid_Response` is specified for a response that "violates its modeled contract" (`src/flyology-object_storage-client-low_level.ads:300-301`), which a proxy-generated 503 does not.

## Suggested treatment

Mirror the GetObject handler at each decoder that maps `S3.Errors.Malformed_Error` to `Invalid_Response`: on a non-2xx status, catch `Malformed_Error` and return the operation's `Rejected` variant with the wire status and `Head_Error (<operation>, Status, Request_ID, Host_ID)`, leaving the success-path parse failures raising as they do now. The change is mechanical and needs no new public entity, since every affected outcome already has that variant.

This needs a maintainer decision on one point, because it fixes a documented classification rather than an internal ordering: whether the synthesised `Code = "HTTP<status>"` convention that HeadObject and GetObject already use becomes the documented contract for the rest of the operations, so that callers may match on it. The alternative is a distinct error code or an empty code for a peer-generated rejection, which changes what those callers see.

The composable side follows from the same change: once the decoders return a rejection rather than raising, `src/flyology-object_storage-client-bounded_rest_xml_reads.adb:105-111` is no longer reached for these responses, and a transient 5xx can be classified `Unavailable_Or_Retryable` instead of `Corrupt_Or_Invalid_Response`.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing error fixtures, which today all carry a well-formed `<Error>` body: serve a 503 with an HTML body to `Execute_List_Objects_V2` and a bodyless 403 to `Execute_Delete_Object`, and require `Rejected` and `Delete_Object_Rejected` with the wire status and `Error.Code = "HTTP503"` and `"HTTP403"`. No existing assertion has to change. The spike is the test.

## Severity

The caller loses the HTTP status of a rejection it needs to act on, and gets a diagnostic that blames the response format. In the composable families the misclassification has a behavioural consequence: a transient 503 from a load balancer is reported as a corrupt response rather than as retryable, so a caller that retries on `Unavailable_Or_Retryable` will not retry. The trigger is a response produced by something other than a conforming S3 origin, such as a reverse proxy, load balancer or CDN answering on its behalf, or a peer answering 4xx with no body; a conforming origin always emits an `<Error>` document, so this is not on the ordinary path. The client fails closed rather than accepting something wrong, and no data is lost. Deterministic.
