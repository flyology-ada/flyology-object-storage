Title: Valid object keys beyond 464 bytes are unusable on the files backend and are reported as a retryable 503
Labels: bug
Refs: none

## Summary

The files backend expands every key byte to two hexadecimal characters and starts a new path component every 100 characters, so a key of N bytes costs about 2.02N path bytes below `buckets/<name>/objects/`, while the crate's storage boundary admits keys of up to 1,024 bytes and the memory backend stores them. On macOS, where `PATH_MAX` is 1024, `mkdir` on an intermediate component fails with `ENAMETOOLONG`, `Ada.Directories.Create_Directory` raises `Use_Error`, and the blanket handler in `Put_Object_Internal` reports `Backend_Unavailable`, which the S3 layer renders as 503 SlowDown. Stock clients retry 503 with backoff, so a `PutObject` for such a key never completes and never reports a permanent error, and `HeadObject`, `GetObject` and `DeleteObject` for the same key fail identically. The ceiling is not documented anywhere and moves with the length of the configured root: on a 49-byte root it is exactly 464 bytes.

## Problem

Commit `5fe6e3e`.

The storage boundary publishes 1,024 bytes as the key limit (`src/flyology-object_storage.ads:667-670`):

```ada
   --  Validate an object key at the storage boundary.
   --  @param Value Candidate object key
   --  @return True for a nonempty key of at most 1,024 bytes without NUL
   function Valid_Object_Key (Value : String) return Boolean;
```

and the implementation enforces exactly that (`src/flyology-object_storage.adb:479-483`):

```ada
   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
```

The pinned botocore S3 model expresses no maximum of its own for the shape, so the crate's own bound is the contract here. `ObjectKey` in the model at botocore revision `36c34f15391da01cd717c73c0fffa747c9889768` (pinned at `coverage/corpora.lock.toml:3-8`) is:

```json
{
  "type": "string",
  "min": 1
}
```

The files backend turns that key into a path that is roughly twice as long (`src/flyology-object_storage-backends-files.adb:835-860`):

```ada
   function Encoded_Object_Path
     (Root : String; Key : String; Suffix : String) return String
   is
      Result  : US.Unbounded_String := US.To_Unbounded_String (Root);
      Segment : String (1 .. 100);
      Used    : Natural := 0;
   begin
      for Character_Value of Key loop
         Segment (Used + 1) :=
           Hex (Character'Pos (Character_Value) / 16);
         Segment (Used + 2) :=
           Hex (Character'Pos (Character_Value) mod 16);
         Used := Used + 2;
         if Used = Segment'Length then
            US.Set_Unbounded_String
              (Result, Join (US.To_String (Result), Segment));
            Used := 0;
         end if;
      end loop;
      if Used = 0 then
         return US.To_String (Result) & Suffix;
      else
         return Join
           (US.To_String (Result), Segment (1 .. Used) & Suffix);
      end if;
   end Encoded_Object_Path;
```

The arithmetic matches the measured threshold exactly. With a 49-byte root, `/buckets/long-key-bucket/objects` adds 32 bytes. A 464-byte key is 928 hexadecimal characters: nine full components at 101 bytes each including their separator, then a separator plus a 28-character remainder plus `.fos`. That is 49 + 32 + 909 + 33 = 1023 bytes, one below `PATH_MAX`. Each further key byte adds two characters, so 465 bytes gives 1025 and crosses the limit. A deployment with a longer root has a proportionally lower ceiling.

`Ensure_Directory` composes absolute paths and creates each ancestor (`src/flyology-object_storage-backends-files.adb:227-238`):

```ada
      declare
         Parent : constant String := Ada.Directories.Containing_Directory
           (Path);
      begin
         if Parent = Path or else Parent'Length = 0 then
            raise Ada.IO_Exceptions.Name_Error;
         end if;
         Ensure_Directory (Item, Parent);
         Ada.Directories.Create_Directory (Path);
         Sync_Directory (Item, Path);
         Sync_Directory (Item, Parent);
      end;
```

and the resulting `Use_Error` reaches the blanket handler (`src/flyology-object_storage-backends-files.adb:7449-7455`):

```ada
         Info := Empty_Info;
         Identity := (others => <>);
         if In_Callback then
            raise;
         else
            Result := Backend_Unavailable;
         end if;
```

which the S3 layer renders as a status that clients are supposed to retry (`src/flyology-object_storage-server-s3_applications.adb:1951-1954`):

```ada
         when Capacity_Exceeded | Backend_Unavailable =>
            Send_Error
              (X, 503, "SlowDown",
               "Please reduce your request rate", Resource);
```

Nothing narrower catches the key first. The only length-related guard on the encoded path bounds recursion, not bytes (`src/flyology-object_storage-backends-files.adb:113`):

```ada
   Maximum_Object_Path_Depth : constant Natural := 32;
```

and a 1,024-byte key needs 21 components, so it never fires. The layout document bounds each component and says nothing about the total (`docs/architecture/files-layout.md:3-6`):

```
The files backend requires exclusive ownership of its configured root by one
process. Buckets are ordinary validated directory names. Object keys are
opaque bytes encoded as uppercase hexadecimal and split into bounded path
components; caller-provided slashes and dot segments are never interpreted.
```

There is no files-specific key-length limit in `docs/architecture/files-layout.md`, `docs/compatibility/s3.md` or `src/flyology-object_storage-backends-files.ads`.

macOS is a qualified platform, not an incidental one: the root and SQLite test job runs on both operating systems (`.github/workflows/ci.yml:66-67`):

```yaml
      matrix:
        os: [ubuntu-latest, macos-latest]
```

so a root written on Linux, where `PATH_MAX` is 4096, holds objects that the same code cannot read when the root is opened on macOS.

No existing test puts a long key into a files store. The only 1,024-byte key in the suite exercises the request target parser (`tests/src/object_storage_test_cases.adb:8879-8889`):

```ada
      declare
         Exact_Key : constant String := (1 .. 1_024 => 'x');
         Parsed : constant Requests.Target_Result :=
           Requests.Parse_Target ("/example-bucket/" & Exact_Key);
      begin
         Assert
           (Parsed.Status = Requests.Target_Parsed
            and then Requests.Object_Key
              ("/example-bucket/" & Exact_Key, Parsed)'Length = 1_024,
            "maximum decoded key length");
      end;
```

No assertion states the wrong behaviour, so none has to change.

## What happens now

Spike: the program below checks the documented boundary, then puts a 1,024-byte key on the memory backend as a control and on a files store rooted at a 49-byte path, and finally binary-searches the largest key length the files store accepts on this host and prints it.

```ada
   Check (Storage.Valid_Object_Key (String'(1 .. 1_024 => 'k')),
          "a 1,024-byte key satisfies the documented storage boundary");
...
      Result := Put_Key (Control, 1_024);
      Check (Result = Storage.Success,
             "memory (control) accepts a 1,024-byte key");
...
      Result := Put_Key (Subject, 1_024);
      Check (Result = Storage.Success,
             "files  (subject) accepts a 1,024-byte key");
```

Output, exit status 1:

```
  -- files root /private/tmp/... (49 bytes)
  ok: a 1,024-byte key satisfies the documented storage boundary
  ok: 1,024 bytes is the documented maximum
  ok: memory (control) CreateBucket
  -- memory (control) PUT 1024-byte key -> SUCCESS
  ok: memory (control) accepts a 1,024-byte key
  ok: files  (subject) CreateBucket
  -- files  (subject) PUT 8-byte key -> SUCCESS
  ok: files  (subject) accepts a short key (harness control)
  -- files  (subject) PUT 1024-byte key -> BACKEND_UNAVAILABLE
  FAILED: files  (subject) accepts a 1,024-byte key
  -- files  (subject) largest accepted key length on this host = 464 bytes; 465 bytes already fails
  -- files  (subject) status at 465 bytes -> BACKEND_UNAVAILABLE
  -- the S3 adapter maps Backend_Unavailable to 503 SlowDown (server-s3_applications.adb:1951-1954)
BUG REPRODUCED: 1 failed expectation(s)
```

The 8-byte key on the same store succeeds, so the store and the harness are sound; the memory backend takes the same 1,024-byte key. The measured cut is exactly where the arithmetic above puts it, at 464 accepted and 465 refused.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A key that `Valid_Object_Key` admits and that the memory backend stores must either be storable on the files backend as well, or be refused with a permanent, documented status that names the reason. `Backend_Unavailable` is neither: it is rendered as 503 SlowDown, which tells the client the request may succeed on retry, and it never will.

## Suggested treatment

This needs a maintainer decision, because either route changes an externally visible contract:

- Publish a files-backend key-length limit and enforce it at admission, so an over-long key is refused with `Invalid_Request` or `Capacity_Exceeded` rather than `Backend_Unavailable`. This makes the failure permanent and self-explaining, but it narrows the crate's documented 1,024-byte key bound for one backend, and the usable figure still depends on the configured root unless the root length is also bounded and documented.
- Change the on-disk key encoding so the total path is bounded independently of the key, for example a fixed digest-prefixed shard directory with the exact key kept in the record where it already lives (`Read_Header` compares it at `src/flyology-object_storage-backends-files.adb:3085-3086`). This keeps the full 1,024-byte range on every platform, and it changes the layout described in `docs/architecture/files-layout.md`, so existing roots need a migration or a compatibility read path.

A smaller alphabet is not a way out on its own: even a 1.34-times expansion puts a 1,024-byte key past 1023 bytes before the root is counted.

The regression test belongs in a new files probe under `tests/src/`, launched from `tests/scripts/test.sh` beside the existing files probes with a root created by `mktemp -d`, so the root length is fixed by the script rather than by the checkout path. A case added to the files-store section of `tests/src/object_storage_test_cases.adb` would work as well for the chosen contract, but its root is composed from `Ada.Directories.Current_Directory`, so the exact threshold it observes varies from host to host. The spike is the test: it asserts the documented boundary and reports the measured ceiling.

## Severity

On macOS an object key between roughly 465 and 1,024 bytes is silently unusable on the files backend, and the client is told to retry a request that can never succeed, so `aws s3 cp` and boto3 spin through their retry budget and then report a timeout or a server error. Keys of that length are unusual but legitimate, and they arise from generated or path-like naming schemes. The same root moved between Linux and macOS turns readable objects into unreadable ones with no warning, and both are qualified platforms. There is no way for an operator to discover the ceiling short of measuring it, since it depends on the root path length and is documented nowhere. Deterministic. Files backend only.
