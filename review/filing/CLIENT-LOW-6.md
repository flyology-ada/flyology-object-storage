Title: Execute_Create_Multipart_Upload sends a mismatched prepared request to the origin before rejecting it
Labels: bug
Refs: none

## Summary

`Prepared_Request` is one opaque private type shared by all 116 modeled operations, so every executor in the low-level client checks that the caller handed it a request for the right operation before doing anything else. `Execute_Create_Multipart_Upload` is the one standalone executor with no such check, and its response and payload objects are elaborated in the declarative part, so the whole HTTP exchange runs before the decoder raises `Invalid_Request`. A caller who passes the wrong prepared request has that request really executed against the origin, and since a prepared request is fully signed and complete, the wrong request can be a mutation: a DeleteObject, an AbortMultipartUpload, or a PutObject with a retained payload.

## Problem

Commit `5fe6e3e`.

The executor performs the exchange in its declarative part and never tests the operation (`src/flyology-object_storage-client-low_level.adb:3505-3526`):

```ada
   function Execute_Create_Multipart_Upload
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Prepared : Prepared_Request;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null;
      Limits   : S3.XML.Parse_Limits := S3.XML.Default_Limits)
      return Create_Multipart_Outcome
   is
      Response : Flyology.HTTP.Client.Response :=
        Flyology.HTTP.Client.Execute
          (Client, Prepared.Message, Timeout, Token);
      Payload : constant Flyology.Bytes.Unbounded_Bytes :=
        Flyology.HTTP.Client.Read_All
          (Response, Limits.Maximum_Document_Bytes, Token);
   begin
      return Decode_Create_Multipart_Complete_Response
        (Response, Flyology.Bytes.To_Byte_String (Payload), Prepared, Limits);
   exception
      when Flyology.HTTP.Client.Response_Too_Large =>
         raise Invalid_Response with
           "CreateMultipartUpload response exceeds XML limit";
   end Execute_Create_Multipart_Upload;
```

The check exists, but in the decoder, which runs after the exchange (`src/flyology-object_storage-client-low_level.adb:3352-3355`):

```ada
   begin
      if Prepared.Operation /= Create_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
```

Every other standalone executor performs that test as its first statement, before any declarative part is elaborated. `Execute_List_Parts` is representative (`src/flyology-object_storage-client-low_level.adb:13276-13280`):

```ada
   begin
      if Prepared.Operation /= List_Parts_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      declare
```

and so do `Execute_Head_Object` (`:5864-5867`), `Execute_Get_Object_Attributes` (`:5497-5499`) and `Execute_Delete_Objects` (`:12820-12823`). The remaining executors are thin wrappers over four shared bodies that each guard the same way, `Execute_Bucket_Configuration_Deletion` at `:8245`, `Execute_Bucket_Control_Get` at `:9798`, `Execute_Bucket_Control_Mutation` at `:10892` and `Execute_Object_Tagging` at `:12459-12463`. Of the 110 `Execute_*` bodies in the file, `Execute_Create_Multipart_Upload` is the only standalone one that does not test the operation before sending.

The mismatched request is not inert. `Prepared.Message` is the complete signed request for whatever operation it was prepared for, and the projector that builds it is documented as covering all 116 pinned operations through one type (`src/flyology-object_storage-client-low_level.ads:193-198`), so nothing distinguishes a DeleteObject request from a CreateMultipartUpload request at the point where the executor sends it.

The specification is silent about the guard rather than sanctioning its absence. The decoder's block documents the exception (`src/flyology-object_storage-client-low_level.ads:6767`):

```ada
   --  @exception Invalid_Request Prepared is not CreateMultipartUpload
```

while the executor's block documents none (`src/flyology-object_storage-client-low_level.ads:6777-6783`):

```ada
   --  Execute one bodyless initiation attempt without automatic replay.
   --  @param Client Configured client for the prepared request origin
   --  @param Prepared Prepared CreateMultipartUpload request metadata
   --  @param Timeout Whole synchronous exchange timeout
   --  @param Token Optional cooperative cancellation source
   --  @param Limits Caller-selected XML and S3 error limits
   --  @return Multipart initiation or structured S3 rejection
```

although other executors do document it, for example `src/flyology-object_storage-client-low_level.ads:6392` for `Execute_Delete_Objects` and `:256` for `Execute_Model_Request`.

No existing test covers a mismatched prepared request for this operation, so nothing has to be inverted with the fix.

## What happens now

Spike: the program below prepares a genuine `DeleteObject` for `/example-bucket/irreplaceable-object`, hands it to `Execute_Create_Multipart_Upload`, and asserts both that `Invalid_Request` is raised and that the origin's exchange counter did not move. Two controls follow: the same mismatched request through the guarded `Execute_List_Parts`, and a genuine `Execute_Delete_Object`.

```ada
   function Prepared_Delete return Low_Level.Prepared_Request is
      Parameters : Low_Level.Delete_Object_Parameters;
   begin
      return Low_Level.Prepare_Delete_Object
        (Origin, Low_Level.Path_Style, Bucket, Key, Parameters, Identity,
         "us-east-1", Timestamp);
   end Prepared_Delete;
...
         Ignored : constant Low_Level.Create_Multipart_Outcome :=
           Low_Level.Execute_Create_Multipart_Upload
             (HTTP, Prepared_Delete, 10.0);
...
         Check (True, "unguarded: a mismatched prepared request is " &
                  "rejected as Invalid_Request");
...
         Check (Fake.Served = Before,
                "unguarded: no request reached the origin");
...
         Ignored : constant Low_Level.List_Parts_Outcome :=
           Low_Level.Execute_List_Parts (HTTP, Prepared_Delete, 10.0);
```

Output, exit status 1:

```
  -- scripted loopback origin on 127.0.0.1:50551
  -- --- a prepared DeleteObject handed to Execute_Create_Multipart_Upload ---
  -- unguarded: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_REQUEST : prepared request operation mismatch
  ok: unguarded: a mismatched prepared request is rejected as Invalid_Request
  -- unguarded: origin exchanges before 0, after 1
  -- unguarded: the origin received DELETE /example-bucket/irreplaceable-object HTTP/1.1
  FAILED: unguarded: no request reached the origin
  -- --- control: the same mismatched request through a guarded executor (Execute_List_Parts) ---
  -- guarded: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_REQUEST : prepared request operation mismatch
  ok: guarded: a mismatched prepared request is rejected as Invalid_Request
  ok: guarded: no request reached the origin
  -- --- control: a genuine DeleteObject must reach the origin ---
  -- genuine: Kind = OBJECT_DELETED, status 204
  ok: genuine: Execute_Delete_Object succeeds
  ok: genuine: exactly one request reached the origin
  -- origin exchange 1: DELETE /example-bucket/irreplaceable-object HTTP/1.1
  -- origin exchange 2: DELETE /example-bucket/irreplaceable-object HTTP/1.1
BUG REPRODUCED: 1 failed expectation(s)
```

The exception the caller sees is the same in both the unguarded and the guarded case, and it says nothing about a request having been sent. The counter and the origin's own log are what separate them: the guarded executor rejected the request with nothing on the wire, while the unguarded one delivered `DELETE /example-bucket/irreplaceable-object` to the origin first. The genuine delete leg shows the counter is sound.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A mismatched prepared request must never reach the network. Rejecting it before the exchange is the invariant every other executor in the package establishes, and `src/flyology-object_storage-client-low_level.adb:13276-13280` is the exact shape of it.

## Suggested treatment

Move the guard ahead of the exchange in `Execute_Create_Multipart_Upload`: begin the body with the same test the decoder performs, then elaborate `Response` and `Payload` inside a `declare` block, exactly as `Execute_List_Parts` does at `src/flyology-object_storage-client-low_level.adb:13276-13280`. The decoder's own check at `:3352-3355` can stay, since it also guards direct callers of the decoder. Add `--  @exception Invalid_Request Prepared is not CreateMultipartUpload` to the executor's specification block at `src/flyology-object_storage-client-low_level.ads:6777-6783`, matching the wording already used at `:6767` and `:6392`. No new public entity is involved and no maintainer decision is needed.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing multipart cases: prepare a request for a different operation, pass it to `Execute_Create_Multipart_Upload`, and require both that `Invalid_Request` is raised and that the fake origin served no request, which the corpus can observe because it counts and matches the exchanges it serves. No existing assertion has to change. The spike is the test.

## Severity

A caller that passes the wrong prepared request has that request executed against the origin, and only afterwards learns that it was the wrong one, from a message that describes a local argument error rather than a completed exchange. Because a prepared request is fully signed and complete, the executed request can be a mutation the caller did not intend to send at that moment, such as a DeleteObject or an AbortMultipartUpload, and the caller has no way to tell from the exception that anything was sent. It needs an erroneous caller input, which is not what a correct program does, and that is precisely why every other executor checks first: the rest of the API establishes the invariant that this one site breaks. No server cooperation is needed and the outcome is the same on every run. Deterministic.
