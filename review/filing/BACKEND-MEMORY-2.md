Title: Same-key CopyObject naming a source version is rejected as Invalid_Request, so a version restore never publishes
Labels: bug
Refs: none

## Summary

The self-copy guard in `Copy_Object` compares the source and destination bucket and key and the four directive fields, and never looks at `Options.Source_Selector`. The operation S3 clients use to restore a previous version, CopyObject with `x-amz-copy-source: /bucket/key?versionId=OLD` and the same destination bucket and key, is therefore answered `Invalid_Request` and HTTP 400 before the source snapshot is even fetched, and no generation is published. The same predicate is duplicated verbatim in the memory, files and SQLite backends, so all three refuse the restore. The pinned MinIO release answers 200 to that request and rejects only the same-key copy that names no source version.

## Problem

Commit `5fe6e3e`.

The guard in the memory backend (`src/flyology-object_storage-backends-memory.adb:4977-4986`):

```ada
      elsif Source_Bucket = Destination_Bucket
        and then Source_Key = Destination_Key
        and then Options.Metadata_Directive = Copy_Metadata
        and then Options.Tagging_Directive = Copy_Tags
        and then Options.Annotation_Directive = Copy_Annotations
        and then Options.Selected_Checksum = No_Checksum
        and then not Options.Metadata.Website_Redirect_Location.Is_Set
      then
         Result := Invalid_Request;
         return;
```

The `return` happens before `Fetch_For_Copy` at `:4989`, so the selected source generation is never read.

The same predicate, verbatim, in the files backend (`src/flyology-object_storage-backends-files.adb:7602-7611`):

```ada
      elsif Source_Bucket = Destination_Bucket
        and then Source_Key = Destination_Key
        and then Options.Metadata_Directive = Copy_Metadata
        and then Options.Tagging_Directive = Copy_Tags
        and then Options.Annotation_Directive = Copy_Annotations
        and then Options.Selected_Checksum = No_Checksum
        and then not Options.Metadata.Website_Redirect_Location.Is_Set
      then
         Result := Invalid_Request;
         return;
      end if;
```

and in the SQLite backend (`sqlite/src/flyology-object_storage-backends-sqlite.adb:2436-2445`):

```ada
      elsif Source_Bucket = Destination_Bucket
        and then Source_Key = Destination_Key
        and then Options.Metadata_Directive = Copy_Metadata
        and then Options.Tagging_Directive = Copy_Tags
        and then Options.Annotation_Directive = Copy_Annotations
        and then Options.Selected_Checksum = No_Checksum
        and then not Options.Metadata.Website_Redirect_Location.Is_Set
      then
         Result := Invalid_Request;
         return;
      end if;
```

The server hands the selector through unaltered, so the versioned request reaches the guard intact (`src/flyology-object_storage-server-s3_applications.adb:14090-14101`):

```ada
                        Source_Read_Request := Object_Reads.Parse_Query
                          (Source_Query, Object_Reads.Get_Object);
                        if not Source_Read_Request.Has_Version_ID
                          or else Source_Read_Request.Has_Part_Number
                          or else
                            Source_Read_Request.Has_Response_Overrides
                        then
                           raise Object_Reads.Malformed_Object_Read_Request;
                        end if;
                        Copy_Options_Value.Source_Selector :=
                          To_Version_Selector
                            (True, Source_Read_Request.Version_ID);
```

Nothing in the contract licenses the rejection. The `Copy_Object` GNATdoc documents source selection, directives, checksums, conditions and identities and states no self-copy rule at all (`src/flyology-object_storage-backends.ads:1969-1974`):

```ada
   --  Copy one immutable source snapshot to the destination. The snapshot
   --  contains the exact body, Object_Information, metadata, and tags from one
   --  source generation; source predicates are evaluated against that same
   --  generation. Source_Bucket_Not_Found and Source_Not_Found remain
   --  distinct, while destination-bucket absence is Not_Found.
```

The behaviour also contradicts two published documents. `docs/compatibility/s3.md:61` claims the exact-source lane on all three backends:

```
| CopyObject | memory/files/SQLite current, null, and retained exact source generations | complete typed composable, synchronous, and convenience clients; authenticated general-purpose path-style server | atomic source/destination version identities, exact/null selection, one-shot no-replay execution with typed publication certainty, exhaustive 44-input/24-output projection, signed raw-wire corpus, repeated six-server byte oracle, and files/SQLite exact-source process-restart oracle |
```

and `docs/qualification/copy-object.md:39` requires the selection without qualification:

```
| 9 | `CopySource` / `x-amz-copy-source` | Parse strictly, including one optional bounded `versionId`, and select that immutable current, null, or exact source snapshot on memory, files, and SQLite. |
```

A real server was measured. The image pinned by `tests/scripts/test-minio.sh` (`quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`, reporting `RELEASE.2025-09-07T16-13-09Z commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb`) was run as a single detached container on `127.0.0.1:19000` and driven with the `aws` CLI:

| request | MinIO answer |
|---|---|
| versioning on, `copy-source b/k?versionId=<v1>` to `b/k` | 200, `CopySourceVersionId=<v1>`, a new `VersionId`, current body becomes `v1` |
| versioning on, `copy-source b/k?versionId=null` to `b/k` | 200, `CopySourceVersionId=null`, current body becomes the null generation's |
| versioning on, `copy-source b/k?versionId=<the current version>` to `b/k` | 200 |
| versioning on, `copy-source b/k` with no version named, to `b/k` | 400 `InvalidRequest`, "This copy request is illegal because it is trying to copy an object to itself without changing the object's metadata, storage class, website redirect location or encryption attributes." |
| unversioned bucket, `copy-source b/k` to `b/k` | 400 `InvalidRequest`, same message |

The reference server's rule is therefore to reject only when no source version is named, which is exactly the discriminator this predicate omits.

No existing test asserts the wrong behaviour; the case is simply uncovered. `tests/src/copy_object_conformance.adb` exercises the same-key rejection with no selector only, and the versioned conformance copies an exact source and a null source to a different bucket and key (`tests/src/versioned_object_conformance.adb:335-339` and `:816-820`):

```ada
         Options.Source_Selector := Exact (V1);
         Store.Copy_Object
           (Bucket, "alpha", Copy_Bucket, "exact", Options, null,
            Ada.Real_Time.Time_Last, Copied, Source_Identity,
            Destination_Identity, Result);
```

```ada
         Options.Source_Selector := Null_Version_Selector;
         Store.Copy_Object
           (Bucket, "alpha", Copy_Bucket, "null", Options, null,
            Ada.Real_Time.Time_Last, Copied, Source_Identity,
            Destination_Identity, Result);
```

## What happens now

Spike: the program below enables versioning on a private memory store, PUTs `v1` then `v2`, confirms as a control that a same-key copy with the default current-version selector is still `Invalid_Request`, then performs the same-key copy with an exact selector naming `v1` and asserts success, a source identity naming `v1`, and a current body of `v1`. A second store repeats the case with the null-version selector. It finally drives the same restore over the in-process S3 application with `x-amz-copy-source: /copy-restore/k?versionId=<v1>` to destination `/copy-restore/k`.

```ada
      --  Control: a same-key copy with NO source selector must stay
      --  Invalid_Request (this is what AWS and MinIO reject).
      Options := Backends.Default_Copy_Options;
      Store.Copy_Object
        (Bucket, Key, Bucket, Key, Options, null, Deadline,
         Info, Source_Identity, Destination_Identity, Result);
...
      --  Under test: restore v1 onto the same key.
      Options := Backends.Default_Copy_Options;
      Options.Source_Selector :=
        (Kind => Backends.Exact_Version, ID => V1);
      Store.Copy_Object
        (Bucket, Key, Bucket, Key, Options, null, Deadline,
         Info, Source_Identity, Destination_Identity, Result);
```

Output, exit status 1:

```
  ok: exact: bucket created
  ok: exact: versioning enabled
  ok: exact: first PUT published
  ok: exact: second PUT published
  -- exact: v1 41b6ea08994cc7f6cbd3be48b86d242d2028e178ac6b576a668acdc4fe92a602 v2 9386a25901aec99598857ac6f2616db093bd4fc09678d8ca98ce1c22bef3b6f3
  ok: exact: current body is v2
  -- control: same-key copy without a selector -> INVALID_REQUEST
  ok: control: unselected same-key copy is still Invalid_Request
  -- exact: same-key copy with Source_Selector = (Exact_Version, v1) -> INVALID_REQUEST
  FAILED: exact: same-key copy of an exact source generation succeeds
  FAILED: exact: Source_Identity names the selected generation
  -- exact: destination identity 
  -- exact: current body after restore 'v2'
  FAILED: exact: restore republished the v1 bytes as current
  ok: null: bucket created
  ok: null: unconfigured PUT published the null generation
  ok: null: versioning enabled
  ok: null: enabled PUT published
  ok: null: current body is e1
  -- null: same-key copy with Null_Version_Selector -> INVALID_REQUEST
  FAILED: null: same-key copy of the null generation succeeds
  -- null: current body after restore 'e1'
  FAILED: null: restore republished the null-generation bytes
  ok: wire: CreateBucket is 200
  ok: wire: PutBucketVersioning is 200
  ok: wire: first PUT is 200
  -- wire: v1 version id 1705f7127d0e471eb4a961a3b1f49d8b4192533a28aaf416a5fcba966bee7b4b
  ok: wire: second PUT is 200
  -- wire: v2 version id 28305ded3ed79f37c4548decbe8c69e3621949effc3587027dbb21c0c87da392
  ok: wire: current body is v2
  -- control: wire same-key copy without versionId -> 400
  ok: control: wire unselected same-key copy is still 400
  -- wire: CopyObject /copy-restore/k?versionId=1705f7127d0e471eb4a961a3b1f49d8b4192533a28aaf416a5fcba966bee7b4b -> 400
  -- wire: response body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>Invalid request</Message><Resource>/copy-restore/k</Resource></Error>
  FAILED: wire: versioned same-key CopyObject is 200
  FAILED: wire: response names the selected source generation
  -- wire: current body after restore 'v2'
  FAILED: wire: restore republished the v1 bytes as current
BUG REPRODUCED: 8 failed expectation(s)
```

The exact-version restore, the null-version restore and the same request over HTTP are all refused, and the current body stays at `v2` in every case. The control shows the unselected same-key copy is still rejected, which is what AWS and MinIO also do.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image.

## What should happen

A CopyObject that names a source version and targets the same bucket and key must select that generation and publish it as a new current generation, which is what `docs/qualification/copy-object.md:39` requires, what `docs/compatibility/s3.md:61` claims, and what the pinned MinIO release does. Only a same-key copy that names no source version and changes nothing should be `Invalid_Request`.

## Suggested treatment

Add the source-selector discriminator to the guard, so it fires only when the request names no source generation. The narrow reading, which is the one measured on MinIO, is to add `and then Options.Source_Selector.Kind = Current_Version` to the predicate at each of the three sites. This is externally visible policy that the `Copy_Object` contract does not currently state, so it needs a maintainer decision:

- Reject only when the selector is `Current_Version`. This matches the pinned MinIO release exactly, and it also permits an explicit copy of the current version onto itself.
- Additionally reject an exact selector that resolves to the current generation. This is stricter than the measured MinIO behaviour and requires resolving the selector before the guard can answer, which moves the check after `Fetch_For_Copy`.

Whichever is chosen, the rule has to be written into the `Copy_Object` contract at `src/flyology-object_storage-backends.ads:1969-2010`, which states no self-copy rule today, and the same change has to be applied at all three sites (`src/flyology-object_storage-backends-memory.adb:4977-4986`, `src/flyology-object_storage-backends-files.adb:7602-7611`, `sqlite/src/flyology-object_storage-backends-sqlite.adb:2436-2445`), because the predicate is duplicated verbatim.

The regression test belongs in `tests/src/versioned_object_conformance.adb`, the backend-neutral version state machine, next to the existing exact and null copy cases at `:335-345` and `:810-825`. That suite is exercised against the memory and files backends from `tests/src/object_storage_test_cases.adb:7964` and `:7998` and against SQLite from `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:5191`, so one case covers all three backends. It should assert the exact-version and null-version same-key restores succeed and republish the selected bytes, and keep the unselected same-key rejection as a control. The spike is the test. No existing assertion has to change.

## Severity

A version restore, the standard way an S3 client rolls an object back to a previous generation, fails with HTTP 400 on every Flyology backend. `aws s3api copy-object` with a versioned copy source, the console's restore-previous-version action, and any rollback or lifecycle tooling built on the same idiom all hit it, on a default configuration and with no way to work around it other than reading the old version and PUTting it back. It is not silent: the caller gets an error rather than a wrong result. Deterministic, and identical in the memory, files and SQLite backends.
