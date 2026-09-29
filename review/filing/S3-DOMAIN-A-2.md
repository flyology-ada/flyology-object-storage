Title: ListObjects v1 decoder rejects a truncated page that carries NextMarker without a delimiter
Labels: bug
Refs: none

## Summary

`S3.Listings.Validate` treats "AWS sends `NextMarker` only when a delimiter was requested" as a wire rule and raises `Malformed_Listing` when a truncated page carries the element without a non-empty `<Delimiter>`. MinIO, RustFS and SeaweedFS all emit `NextMarker` unconditionally, so paging any bucket with more than `max-keys` objects and no delimiter against those servers loses the very first page and pagination never starts. The compatibility matrix claims a six-server oracle for this operation while the three Docker scripts switch the case off through an environment variable, so the lane that would have caught it is disabled rather than fixed.

## Problem

Commit `5fe6e3e`.

An echoed empty `<Delimiter/>` cannot rescue the page, because the flag requires non-empty text (`src/flyology-object_storage-s3-listings.adb:1093-1094`):

```ada
      Effective_Delimiter : constant Boolean :=
        Value.Has_Delimiter and then US.Length (Value.Delimiter) > 0;
```

and the raise ties the presence of `NextMarker` to that flag (`src/flyology-object_storage-s3-listings.adb:1108-1116`):

```ada
      elsif Value.Has_Next_Marker /=
        (Value.Is_Truncated and then Effective_Delimiter)
        or else
          (Value.Has_Next_Marker and then US.Length (Value.Next_Marker) = 0)
        or else
          (not Value.Has_Next_Marker
           and then US.Length (Value.Next_Marker) > 0)
      then
         raise Malformed_Listing with "inconsistent S3 next marker";
```

`Parse_List_Objects` always calls `Validate`, with no bypass (`src/flyology-object_storage-s3-listings.adb:1152-1158`):

```ada
      if not Handler.Seen_Name
        or else not Handler.Seen_Max_Keys
        or else not Handler.Seen_Is_Truncated
      then
         raise Malformed_Listing with "S3 listing lacks required fields";
      end if;
      Validate (Handler.V1_Value);
```

and the client converts the exception into an invalid response, so no page is returned (`src/flyology-object_storage-client-low_level.adb:1693-1695`):

```ada
   exception
      when S3.Listings.Malformed_Listing | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjects response";
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) imposes no such constraint. `ListObjectsOutput` has no `required` list and `NextMarker` is a plain optional string. The AWS rule the crate has turned into a wire check is carried in the model as prose addressed to a client, printed with `python3` and stripped of markup:

```
ListObjectsOutput required: None
NextMarker member: {"shape": "NextMarker"}
NextMarker documentation: When the response is truncated (the IsTruncated element value in the response is true), you can use the key name in this field as the marker parameter in the subsequent request to get the next set of objects. Amazon S3 lists objects in alphabetical order. This element is returned only if you have the delimiter request parameter specified. If the response does not include the NextMarker element and it is truncated, you can use the value of the last Key element in the response as the marker parameter in the subsequent request to get the next set of object keys.
```

That paragraph tells a client what it may rely on. It does not forbid a server from sending the element, and the model records no error for it.

Real servers send it. The pinned MinIO image, `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` from `tests/scripts/test-minio.sh:5`, whose `--version` prints `minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`, answered a signed `GET /bucket?max-keys=1` on a three-key bucket with 200 and, verbatim apart from the bucket name and the object entry:

```
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">...<Marker></Marker><NextMarker>k1[minio_cache:v2,return:]</NextMarker><MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>...
```

The same request with `delimiter=/` answered 200 with the same `NextMarker` and one extra element:

```
...<NextMarker>k1[minio_cache:v2,return:]</NextMarker><MaxKeys>1</MaxKeys><Delimiter>/</Delimiter><IsTruncated>true</IsTruncated>...
```

The two bodies differ by exactly that `<Delimiter>` element, and that one element decides whether the crate accepts the page.

Accepting the element costs the client nothing, because it already derives the marker from the last key when `NextMarker` is absent (`src/flyology-object_storage-client-objects.adb:403-415`):

```ada
               if Page.Is_Truncated then
                  if Page.Has_Next_Marker then
                     Next := US.To_Unbounded_String
                       (Logical_Marker (US.To_String (Page.Next_Marker)));
                  elsif not Page.Contents.Is_Empty then
                     Next := US.To_Unbounded_String
                       (Logical_Marker
                          (US.To_String (Page.Contents.Last_Element.Key)));
```

The repository already knows about the behaviour and has switched the check off rather than fixed it. `Check_List_Objects_V1_Pagination` returns `False` for the three server-specific oracle modes, skipping the subcase (`tests/src/s3_implementation_corpus.adb:258-274`):

```ada
   function Check_List_Objects_V1_Pagination return Boolean is
      Name : constant String := "FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "rustfs-rc3-next-marker-without-delimiter"
        or else Ada.Environment_Variables.Value (Name) =
          "seaweedfs-4.43-next-marker-without-delimiter"
        or else Ada.Environment_Variables.Value (Name) =
          "minio-2025-next-marker-without-delimiter"
      then
         return False;
```

and the three Docker scripts set exactly those values. `tests/scripts/test-minio.sh:66-67`:

```sh
FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE=\
minio-2025-next-marker-without-delimiter \
```

`tests/scripts/test-rustfs.sh:71-72`:

```sh
FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE=\
rustfs-rc3-next-marker-without-delimiter \
```

`tests/scripts/test-seaweedfs.sh:78-79`:

```sh
FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE=\
seaweedfs-4.43-next-marker-without-delimiter \
```

The exclusion is recorded in prose at `docs/qualification/list-objects-v1.md:54-58`:

```
All 18 lanes passed on 2026-08-22. Pinned
RustFS, SeaweedFS, and MinIO each emit a non-model NextMarker on a truncated
v1 page without a delimiter. Their strict no-delimiter continuation subcase is
excluded explicitly; the basic v1 path remains enabled, while every Flyology
backend passes the complete two-page AWS fallback rule.
```

while the matrix row still advertises the oracle, `docs/compatibility/s3.md:65`, whose evidence column ends:

```
strict presence/query/XML/header and socket corpora, native/lightweight six-server oracle, and five-server signed raw-XML benchmark
```

The one existing test in this area covers the other direction and stays correct: `tests/src/object_storage_test_cases.adb:9597-9599` rejects a marker on a final page.

```ada
      Must_Reject_Document
        (Empty_Listing ("<NextMarker>unexpected</NextMarker>"),
         "ListObjects marker on final page was accepted");
```

The truncated no-delimiter case has no test. The socket corpus exercises the shape the in-house server emits, a truncated no-delimiter page with no `NextMarker` at all (`tests/src/s3_http_socket_corpus.adb:11895-11900`), which never reaches the failing branch.

## What happens now

Spike: the program below puts four documents through `S3.Listings.Parse_List_Objects`. Two are the verbatim MinIO bodies quoted above, differing by the single `<Delimiter>` element; one is the truncated no-delimiter page without `NextMarker` that the in-house server emits; one is a minimal synthetic equivalent, so the finding does not rest on any MinIO-specific text. The delimiter page and the marker-free page are the controls.

```ada
   Minimal_No_Delimiter : constant String :=
     "<ListBucketResult xmlns=""" & NS & """>" &
     "<Name>b</Name><MaxKeys>1</MaxKeys>" &
     "<IsTruncated>true</IsTruncated><NextMarker>a</NextMarker>" &
     "<Contents><Key>a</Key><Size>1</Size></Contents></ListBucketResult>";
...
         Page : constant Listings.List_Objects_Result :=
           Listings.Parse_List_Objects (Document, XML.Default_Limits);
      begin
         ...
            Check (Page.Has_Next_Marker,
                   Label & ": the page keeps NextMarker");
            Check (US.To_String (Page.Next_Marker) = Expected_Marker,
                   Label & ": NextMarker text is preserved");
```

Output, exit status 1:

```
  -- MinIO max-keys=1 delimiter=/  : decoded, objects=1 truncated=TRUE has_next_marker=TRUE next_marker="k1[minio_cache:v2,return:]"
  ok: MinIO max-keys=1 delimiter=/  : the page keeps its one object
  ok: MinIO max-keys=1 delimiter=/  : the page is truncated
  ok: MinIO max-keys=1 delimiter=/  : the page keeps NextMarker
  ok: MinIO max-keys=1 delimiter=/  : NextMarker text is preserved
  -- Flyology-shaped page, no NextMarker: decoded, objects=1 truncated=TRUE has_next_marker=FALSE next_marker=""
  -- MinIO max-keys=1 no delimiter   : REJECTED, inconsistent S3 next marker
  FAILED: MinIO max-keys=1 no delimiter   : the page is accepted
  -- minimal truncated no-delimiter  : REJECTED, inconsistent S3 next marker
  FAILED: minimal truncated no-delimiter  : the page is accepted
BUG REPRODUCED: 2 failed expectation(s)
```

A second program drove the same case live against the pinned MinIO through `Client.Objects.List_V1_Page`, on a three-key bucket with `Maximum => 1`, once with `delimiter=/` and once without. The delimiter call returned the first page; the undelimited call raised. Output, exit status 1, the two legs:

```
  -- List_V1_Page max-keys=1 delimiter=/: kind PAGE_AVAILABLE status 200
  ok: List_V1_Page returns the first page (delimiter=/)
  --   objects 1 truncated TRUE next_marker "k1[minio_cache:v2,return:]"
  -- List_V1_Page max-keys=1 no delimiter: raised Invalid_Response: ListObjects response is invalid or exceeds the XML limit
  FAILED: List_V1_Page returns the first page (no delimiter)
```

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A truncated v1 page carrying `NextMarker` must be accepted whether or not a delimiter was requested. The pinned model puts no cross-member constraint on `NextMarker`, its own documentation states the delimiter rule as advice to a client rather than a constraint on a server, and MinIO, RustFS and SeaweedFS all emit the element unconditionally. A `NextMarker` on a page that is not truncated remains an inconsistency and must still be refused.

## Suggested treatment

Relax the first disjunct at `src/flyology-object_storage-s3-listings.adb:1108-1109` to key on truncation alone:

```ada
      elsif Value.Has_Next_Marker /= Value.Is_Truncated
```

leaving the two emptiness clauses at `:1110-1114` untouched, so an empty `NextMarker` and stray marker text are still rejected and a final-page marker is still rejected. No new public constant, type or parameter is needed, and the client's existing fallback at `src/flyology-object_storage-client-objects.adb:403-415` already handles both page shapes.

The switch-off must be retired with the fix, in both places: delete the three `FLYOLOGY_LIST_OBJECTS_V1_ORACLE_MODE` assignments (`tests/scripts/test-minio.sh:66-67`, `tests/scripts/test-rustfs.sh:71-72`, `tests/scripts/test-seaweedfs.sh:78-79`) and the reader that skips the subcase for them (`tests/src/s3_implementation_corpus.adb:258-274`), so the three third-party lanes run the no-delimiter continuation the matrix already claims. The exclusion paragraph at `docs/qualification/list-objects-v1.md:54-58` must be removed with it.

The client-side regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing no-delimiter case at `:11885-11904`: a scripted origin serving the MinIO page with `NextMarker` and no `<Delimiter>`, asserting `Page_Available`, one object, `Is_Truncated`, and the marker text preserved. `tests/src/object_storage_test_cases.adb:9597-9599` keeps asserting the final-page rejection and needs no change. The spike is the test.

## Severity

Every ListObjects v1 listing of a bucket with more than `max-keys` objects and no delimiter fails on its first page against MinIO, RustFS and SeaweedFS: `Parse_List_Objects` raises, the low-level decoder converts it to `Invalid_Response`, and `List_V1_Page` never returns, so pagination cannot start. That is the ordinary case for a v1 listing, not an edge case, and the caller has no workaround short of passing a delimiter it does not want. The matrix row `docs/compatibility/s3.md:65` claims a six-server oracle for the operation while the three Docker scripts disable exactly this subcase, so the claim is not met today. Flyology backends are unaffected, because the in-house server omits `NextMarker` in that case. Deterministic.
