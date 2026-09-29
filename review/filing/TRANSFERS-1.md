Title: Download_File reports a 200 answer to a ranged GET as "GetObject returned an unsolicited representation interval"
Labels: bug
Refs: none

## Summary

`Download_File` uses one status test for two opposite protocol events and gives them the same message. When the caller sent no `Range` and the server answered 206, "GetObject returned an unsolicited representation interval" is accurate. When the caller did send a `Range` and the server answered 200 with the whole representation and no `Content-Range`, the same text is emitted, and it is false in every particular: no interval was returned and nothing was unsolicited. The refusal itself is the documented range-mode policy and the destination file is correctly left untouched, so the defect is the diagnostic an operator has to act on.

## Problem

Commit `5fe6e3e`.

One `elsif` covers both events and raises one message (`src/flyology-object_storage-client-transfers.adb:1706-1717`):

```ada
            if Head.Kind = Low_Level.Get_Object_Rejected then
               return
                 (Kind   => Download_Rejected,
                  Status => Head.Status,
                  Error  => Head.Error);
            elsif (Byte_Range_Header'Length = 0 and then Head.Status /= 200)
              or else
                (Byte_Range_Header'Length > 0 and then Head.Status /= 206)
            then
               raise Low_Level.Invalid_Response with
                 "GetObject returned an unsolicited representation interval";
            end if;
```

That literal appears at exactly one site in the repository, so no other message distinguishes the two cases.

The decode step cannot produce a better one. `Validate_Get_Object_Headers` rejects a 200 only when it carries a `Content-Range`, so a plain 200 with a `Content-Length` and no `Content-Range` is a valid head and passes through (`src/flyology-object_storage-client-low_level.adb:5981-5987`):

```ada
   procedure Validate_Get_Object_Headers
     (Value : Get_Object_Result; Status : Flyology.HTTP.Status_Code) is
   begin
      if (Status = 206
          and then not Valid_Content_Range
            (US.To_String (Value.Content_Range), Value.Content_Length))
        or else (Status = 200 and then US.Length (Value.Content_Range) > 0)
```

The decoder never sees the request, so it cannot know a `Range` was sent, and the check in `Download_File` is the only gate.

Refusing is correct and documented. The `Download_File` contract states range mode as a 206 rule (`src/flyology-object_storage-client-transfers.ads:1688-1689`):

```ada
   --  @param Byte_Range_Header Optional single bytes range; a successful 206
   --  atomically publishes the selected interval as the destination file
```

and the architecture document says the same (`docs/architecture/client-transfers.md:153-154`):

```
one S3 `Range` value; that mode accepts only HTTP 206 with a strict, coherent
single `Content-Range` whose interval length equals `Content-Length` and the
```

The wording is what is wrong, not the refusal.

The path is public and reachable. `Byte_Range_Header` is a public parameter with an empty default (`src/flyology-object_storage-client-transfers.ads:1710`):

```ada
      Byte_Range_Header : String := "";
```

No maintained lane sends a `Range` and answers 200, so the suite never observes the text. The `download-unexpected-range` lane exercises only the first disjunct, an unranged request, and asserts nothing about the message (`tests/src/s3_http_socket_corpus.adb:16936-16950`):

```ada
               begin
                  declare
                     Ignored : constant Transfers.Download_Outcome :=
                       Transfers.Download_File
                         (HTTP, Origin, "example-bucket",
                          "download-unexpected-range", Partial_Path,
                          Identity, Timeout => 5.0);
                     pragma Unreferenced (Ignored);
                  begin
                     null;
                  end;
               exception
                  when Low_Level.Invalid_Response =>
                     Partial := True;
               end;
```

and the `download-range` lane sends a real `Range` against a server that answers 206 (`tests/src/s3_http_socket_corpus.adb:16960-16965`):

```ada
               declare
                  Result : constant Transfers.Download_Outcome :=
                    Transfers.Download_File
                      (HTTP, Origin, "example-bucket", "download-range",
                       Range_Path, Identity, Timeout => 5.0,
                       Byte_Range_Header => "bytes=7-13");
```

No existing test asserts the wording, so nothing has to change to fix it.

`Transfer_Many` cannot reach the wrong text. `Execute_Transfer` calls `Download_File` with an argument list ending at `Token` (`src/flyology-object_storage-client-transfers.adb:663-669`):

```ada
               Outcome : constant Download_Outcome := Download_File
                 (Input.Client.all, Input.Origin,
                  US.To_String (Input.Value.Bucket),
                  US.To_String (Input.Value.Key),
                  US.To_String (Input.Value.Local_Path), Input.Identity.all,
                  US.To_String (Input.Region), Input.Style,
                  Remaining (Deadline), Token);
```

and `Subject` has no range field (`src/flyology-object_storage-client-transfers.ads:1731-1737`):

```ada
   type Subject is record
      Kind       : Transfer_Kind := Upload;
      Bucket     : Ada.Strings.Unbounded.Unbounded_String;
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Local_Path : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
   end record;
```

so only the accurate first disjunct is reachable from a multi-subject transfer.

## What happens now

Spike: a loopback HTTP/1.1 server answers the first two GETs with `200 OK`, `Content-Length: 27` and the whole 27-byte body regardless of any `Range` header, and a third with an unsolicited `206` and `Content-Range: bytes 7-13/27`. The program drives `Download_File` against it three times: unranged as a control that the harness works, then with `Byte_Range_Header => "bytes=7-13"` asserting the diagnostic names the actual event, then unranged against the 206 showing which event the existing text describes. It also asserts the destination is preserved on both failures and that no download temporary is left behind.

```ada
               Result : constant Transfers.Download_Outcome :=
                 Transfers.Download_File
                   (HTTP, Origin, "example-bucket", "range-ignored",
                    Range_Path, Identity, Timeout => 20.0,
                    Byte_Range_Header => "bytes=7-13");
...
         Check (not Contains (Lower (US.To_String (Message)), "unsolicited"),
                "ranged-200 diagnostic does not claim an UNSOLICITED "
                & "interval (no interval was returned at all)");
```

Output, exit status 1:

```
  -- fake HTTP/1.1 server on 127.0.0.1:57480 answers every GET with 200 and the whole 27-byte body
  -- control unranged request: GET /example-bucket/range-ignored HTTP/1.1
  -- control unranged outcome: status 200, bytes 27
  ok: control: unranged Download_File publishes the 200 body
  ok: control: published bytes round-trip
  -- ranged request line: GET /example-bucket/range-ignored HTTP/1.1
  -- ranged request Range header: bytes=7-13
  -- server answered: HTTP/1.1 200 OK, Content-Length 27, no Content-Range
  -- Invalid_Response raised: TRUE
  -- message: "GetObject returned an unsolicited representation interval"
  ok: control: a 200 answer to a ranged request is refused
  ok: control: the refused ranged download leaves the destination untouched
  FAILED: ranged-200 diagnostic does not claim an UNSOLICITED interval (no interval was returned at all)
  FAILED: ranged-200 diagnostic names the actual event: the server ignored the Range and returned the whole representation
  -- unsolicited-206 message: "GetObject returned an unsolicited representation interval"
  ok: control: an unrequested 206 is refused
  ok: control: the unrequested-206 case is the one the 'unsolicited representation interval' text describes
  ok: control: the refused 206 leaves the destination untouched
  -- files left in the scratch directory: 3 (the three destinations)
  ok: control: no download temporary is left behind
BUG REPRODUCED: 2 failed expectation(s)
```

The two opposite events produce byte-identical messages. The refusal, the untouched destination and the absent temporary are all correct.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A ranged request answered with 200 and the whole representation should be refused with a message that names that event, so an operator reads that the server or an intermediary ignored the `Range`. The existing text belongs to the opposite case, an unrequested 206, which the contract at `src/flyology-object_storage-client-transfers.ads:1688-1689` also refuses.

## Suggested treatment

Split the `elsif` at `src/flyology-object_storage-client-transfers.adb:1711-1716` into two branches with two messages, keeping the existing text for the unrequested-206 case and giving the ranged-200 case its own, for example "GetObject ignored the requested Range and returned the whole representation". This adds no public constant, parameter or outcome, and the raised exception stays `Low_Level.Invalid_Response`, so it is not an interface change and needs no maintainer decision.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing `download-unexpected-range` and `download-range` lanes at `:16935-16978`. It needs one new key whose loopback response is 200 with the whole body, requested with a `Byte_Range_Header`, asserting the raised message text, which is the property the spike asserts. The spike is the test. No existing assertion has to change, because no maintained lane asserts the wording.

## Severity

The refusal is right and no data is lost: the destination file is untouched and no temporary is left behind. The cost is a misleading diagnostic. An operator whose proxy or cache strips `Range` reads that the server returned an interval nobody asked for and looks for a server that is sending 206, when the server actually returned 200 and the whole object. It needs a direct `Download_File` call with a `Byte_Range_Header` answered by a server or intermediary that ignores `Range`; multi-subject transfers never pass a range and cannot reach it. Deterministic, since the branch is a pure function of the range-header length and the status.
