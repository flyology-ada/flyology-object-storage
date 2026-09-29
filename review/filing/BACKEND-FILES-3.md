Title: Bucket-configuration readers size a stack local from the stored document, so a 3 MiB policy kills the process
Labels: bug
Refs: none

## Summary

`Read_String` declares `Result : String (1 .. Length)`, a local sized by the persisted document length, while the matching writer streams the same document in 64 KiB chunks and admission accepts up to 16 MiB. Seven singleton bucket-configuration readers on the files backend go through it: policy, CORS, encryption, ownership controls, lifecycle, logging and notification. A document larger than the reading task's primary stack is therefore accepted, acknowledged with 200 and durable on disk, and then cannot be read back. The failure is not an exception: from a task with the GNAT default 2 MiB stack, which is what every Flyology HTTP worker gets, the oversized frame runs past the guard page and the process is killed with SIGKILL, so one `GetBucketPolicy` for an already-accepted configuration takes the server down for every concurrent client.

## Problem

Commit `5fe6e3e`.

`Read_String` streams the file in 64 KiB chunks but assembles the result in one contiguous stack local (`src/flyology-object_storage-backends-files.adb:1579-1587`):

```ada
   function Read_String
     (File : in out SIO.File_Type; Length : Natural) return String
   is
      Result : String (1 .. Length);
      Data   : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset
          (File_String_IO_Chunk_Bytes));
      Target_Position : Positive := Result'First;
      Remaining       : Natural := Length;
```

The matching writer, `Write_String` at `src/flyology-object_storage-backends-files.adb:1478-1504`, writes the same document 64 KiB at a time, and the comment above it states the intent that the working set does not follow the admitted value (`src/flyology-object_storage-backends-files.adb:1474-1476`):

```ada
   File_String_IO_Chunk_Bytes : constant Positive := 64 * 1_024;
   --  Match the files backend's existing streaming chunk convention while
   --  bounding the stack working set independently of the admitted value.
```

`Read_Bucket_Policy` calls it with the persisted length (`src/flyology-object_storage-backends-files.adb:1780-1796`):

```ada
   procedure Read_Bucket_Policy
     (File : in out SIO.File_Type; Policy : out US.Unbounded_String)
   is
      File_Magic : constant String :=
        Read_String (File, Bucket_Policy_Magic'Length);
      Length : constant Natural := Read_U32 (File);
   begin
      Policy := US.Null_Unbounded_String;
      if File_Magic /= Bucket_Policy_Magic
        or else Byte_Count (Length) > Maximum_Bucket_Policy_Bytes
        or else SIO.Size (File) /=
          SIO.Count (Bucket_Policy_Magic'Length + 4 + Length)
      then
         raise Ada.IO_Exceptions.Data_Error;
      end if;
      Policy := US.To_Unbounded_String (Read_String (File, Length));
   end Read_Bucket_Policy;
```

Six more readers have the same shape, each ending in the same statement: `Read_Bucket_CORS` (declared at `:1809`, reads at `:1824`), `Read_Bucket_Encryption` (`:1839`, `:1857`), `Read_Bucket_Ownership_Controls` (`:1872`, `:1890`), `Read_Bucket_Lifecycle` (`:1908`, `:1930`, and again for its metadata field at `:1932`), `Read_Bucket_Logging` (`:1947`, `:1965`) and `Read_Bucket_Notification` (`:1980`, `:1998`).

The chunked reader that keeps the frame bounded already exists and is already used by the replication and website readers (`src/flyology-object_storage-backends-files.adb:1610-1624`):

```ada
   procedure Read_Unbounded_String
     (File   : in out SIO.File_Type;
      Length : Natural;
      Value  : out US.Unbounded_String)
   is
      Remaining : Natural := Length;
   begin
      Value := US.Null_Unbounded_String;
      while Remaining > 0 loop
         declare
            Count : constant Natural :=
              Natural'Min (File_String_IO_Chunk_Bytes, Remaining);
         begin
            US.Append (Value, Read_String (File, Count));
            Remaining := Remaining - Count;
```

`Read_Bucket_Replication` ends in `Read_Unbounded_String (File, Length, Document);` (`src/flyology-object_storage-backends-files.adb:2104`) and `Read_Bucket_Website` in the identical call (`:2137`).

The document that reaches these readers is bounded at 16 MiB, not at any stack figure (`src/flyology-object_storage-backends.ads:2792`):

```ada
   Maximum_Bucket_Policy_Bytes : constant Byte_Count := 16 * 1_024 * 1_024;
```

and admission accepts anything up to it (`src/flyology-object_storage-backends.adb:199-200`):

```ada
   function Valid_Bucket_Policy (Policy : String) return Boolean is
     (Byte_Count (Policy'Length) <= Maximum_Bucket_Policy_Bytes);
```

The S3 route sizes the request body from the same budget, so nothing narrower stands between a client and the backend (`src/flyology-object_storage-server-s3_applications.adb:186-187`):

```ada
   Maximum_Bucket_Policy_Body : constant Byte_Count :=
     Byte_Count (XML.Default_Limits.Maximum_Document_Bytes);
```

`Maximum_Document_Bytes` defaults to `16 * 1_024 * 1_024` (`src/flyology-object_storage-s3-xml.ads:14`).

The reading task's stack is the real bound, and it is 2 MiB for every server worker. A GNAT task that declares no `Storage_Size` gets the default (toolchain `adainclude/s-parame.adb:55-60`, GNAT 16.1.0):

```ada
   function Default_Stack_Size return Size_Type is
      Default_Stack_Size : constant Integer;
      pragma Import (C, Default_Stack_Size, "__gl_default_stack_size");
   begin
      if Default_Stack_Size = -1 then
         return 2 * 1024 * 1024;
```

and the handler task in the pinned flyology 0.1.1-dev release declares none (`src/flyology-io-structured_servers.adb:386-389`):

```ada
            task type Worker with CPU => Handler_CPU is
               pragma Task_Info (Handler_Model);
               entry Start;
            end Worker;
```

`Get_Bucket_Policy` has a `when others` handler that would turn a caught `Storage_Error` into a status (`src/flyology-object_storage-backends-files.adb:6268-6277`):

```ada
      when others =>
         if Opened then
            SIO.Close (File);
         end if;
         if Locked then
            Item.Publication.Release;
         end if;
         Policy := US.Null_Unbounded_String;
         Configured := False;
         Result := Backend_Unavailable;
```

In a secondary task with the default stack the process never reaches it.

The existing tests do not reach this. `Exercise_Bucket_Singleton_Configuration_Bounds` is the case that uses 16 MiB documents, and it round-trips only replication, which goes through the chunked reader (`tests/src/object_storage_test_cases.adb:1543-1550`):

```ada
      Store.Put_Bucket_Replication
        (Bucket, At_Limit.all, null, Ada.Real_Time.Time_Last, Result);
      Assert
        (Result = Success,
         "replication rejected its exact configuration byte limit");
      Store.Get_Bucket_Replication
        (Bucket, null, Ada.Real_Time.Time_Last,
         Document, Configured, Result);
```

Its website and notification steps only assert that an over-limit document is refused (`:1562-1571`). The policy and CORS round-trip cases use short literals (`:583-600` and `:702-711`). The case runs against a files store (`:5843-5844`), so the gap is the document size, not the backend.

## What happens now

Spike: the program below stores a 1 MiB and a 3 MiB bucket policy on a files store, reads both back from the environment task as a control, and then re-executes itself as a child process that performs each read from a task with the GNAT default `Storage_Size`. The child runs under `/bin/sh` so its termination status is visible. It asserts that a policy the backend acknowledged can be read back from a default-stack task.

```ada
      declare
         task Worker;

         task body Worker is
            Policy     : US.Unbounded_String;
            Configured : Boolean;
         begin
            Subject.Get_Bucket_Policy
              (Bucket, null, Forever, Policy, Configured, Worker_Result);
            Worker_Length := US.Length (Policy);
...
      Check (Small = 0,
             "files  (subject) a default-stack task reads a 1 MiB policy "
             & "back (child-process control)");
...
      Check (Large = 0,
             "files  (subject) a default-stack task reads the acknowledged "
             & "3 MiB policy back");
```

Output, exit status 1 (the absolute path in the `/bin/sh` diagnostic is shortened for width; every other line is verbatim):

```
  -- documents: 1048576 bytes and 3145728 bytes; documented admission bound is 16 MiB (backends.ads:2792); GNAT default task stack is 2 MiB
  ok: memory (control) CreateBucket
  ok: memory (control) PutBucketPolicy accepts 3 MiB
  -- memory (control) GetBucketPolicy -> SUCCESS length 3145728
  ok: memory (control) round-trips the 3 MiB policy
  ok: files  (subject) CreateBucket small-policy-bucket
  -- files  (subject) PutBucketPolicy(small-policy-bucket, 1048576 bytes) -> SUCCESS
  ok: files  (subject) PutBucketPolicy acknowledges small-policy-bucket
  -- files  (subject) GetBucketPolicy(small-policy-bucket) from the environment task -> SUCCESS length 1048576
  ok: files  (subject) the environment task reads small-policy-bucket back (the bytes are on disk and intact)
  ok: files  (subject) CreateBucket large-policy-bucket
  -- files  (subject) PutBucketPolicy(large-policy-bucket, 3145728 bytes) -> SUCCESS
  ok: files  (subject) PutBucketPolicy acknowledges large-policy-bucket
  -- files  (subject) GetBucketPolicy(large-policy-bucket) from the environment task -> SUCCESS length 3145728
  ok: files  (subject) the environment task reads large-policy-bucket back (the bytes are on disk and intact)
  -- [child] small-policy-bucket GetBucketPolicy from a default-Storage_Size task -> SUCCESS length 1048576
  -- [sh] child for small-policy-bucket terminated with status 0 (128+n means signal n)
/bin/sh: line 1: 89763 Killed: 9               '.../the spike' worker '/private/tmp/...' large-policy-bucket 3145728
  -- [sh] child for large-policy-bucket terminated with status 137 (128+n means signal n)
  -- files  (subject) child status for the 1 MiB policy 0
  ok: files  (subject) a default-stack task reads a 1 MiB policy back (child-process control)
  -- files  (subject) child status for the 3 MiB policy 137
  FAILED: files  (subject) a default-stack task reads the acknowledged 3 MiB policy back
BUG REPRODUCED: 1 failed expectation(s)
```

Status 137 is 128 plus signal 9: the child was killed, not terminated by an Ada exception, and printed no diagnostic of its own. The 1 MiB child on the same store and the same code path exits 0, so the failure follows the document size against the task stack and not the store or the request. The environment-task reads of both documents succeed, so the bytes on disk are intact and this is a read-path defect rather than a corrupted record. The memory backend round-trips the same 3 MiB policy.

The status a caller sees depends on which task issues the read. From the environment task with 8 MiB of headroom (`ulimit -s` reports 8176 KiB here) the same read succeeds; with a 3 MiB local already on that stack it returns `Backend_Unavailable` through the handler at `src/flyology-object_storage-backends-files.adb:6268-6277`. Both are the same defect.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A bucket policy, CORS, encryption, ownership-controls, lifecycle, logging or notification document that `Valid_Bucket_Policy` and the S3 route admitted, that was written and acknowledged, must be readable afterwards, and no read of a persisted document may consume stack in proportion to the document. `src/flyology-object_storage-backends-files.adb:1474-1476` already states that intent for the file string helpers, and the replication and website readers already meet it.

## Suggested treatment

Route the seven readers through the existing `Read_Unbounded_String` (`src/flyology-object_storage-backends-files.adb:1610-1631`) as `Read_Bucket_Replication` (`:2104`) and `Read_Bucket_Website` (`:2137`) already do: replace `Policy := US.To_Unbounded_String (Read_String (File, Length));` at `:1795` with `Read_Unbounded_String (File, Length, Policy);`, and the same at `:1824`, `:1857`, `:1890`, `:1930`, `:1932`, `:1965` and `:1998`. No constant, parameter or status changes value, and the persisted format is untouched. `Read_String` should keep only its short fixed-size uses, such as the magic value at `:1784`.

Whether these documents should also carry a bound smaller than `Maximum_Bucket_Policy_Bytes` at `src/flyology-object_storage-backends.ads:2792` is a separate, externally visible policy question and is not needed to close this defect.

The regression test belongs in a new files probe under `tests/src/`, launched from `tests/scripts/test.sh` beside the existing files probes, because a failing read terminates the process and would take a whole in-process suite run with it: the probe should store a policy larger than a default task stack, read it back from a task that declares no `Storage_Size`, and require exit status 0. The spike is the test. A second, in-process case for a policy that fits, added to `Exercise_Bucket_Singleton_Configuration_Bounds` at `tests/src/object_storage_test_cases.adb:1524-1579`, would cover the remaining six readers cheaply; no existing assertion there is wrong, so none has to change.

## Severity

An operator who stores a bucket policy or CORS, encryption, ownership-controls, lifecycle, logging or notification document of a few MiB gets a 200 and a durable file, and the next read of that document from a server worker kills the server process. Every concurrent request on that process dies with it, and there is no Ada exception, no log line and no status to attribute the failure to the request that caused it, so the operator sees an unexplained restart loop that repeats on every retry of the same `GetBucketPolicy`. The documents are admitted up to 16 MiB and the worker stack is 2 MiB, so the whole range between them is reachable through ordinary requests with no unusual configuration. It is fully deterministic. Files backend only.
