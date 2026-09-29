Title: ListObjectVersions decoder rejects every version whose StorageClass is not STANDARD
Labels: bug
Refs: S3-DOMAIN-A-7

## Summary

The ListObjectVersions decoder validates every `<Version>/<StorageClass>` against the pinned one-value `ObjectVersionStorageClass` enumeration, so a page in which any single version reports a different class raises `Malformed_Version_Listing` and the client turns it into `Invalid_Response`. The whole page is lost, not just the offending entry, and there is no cursor with which to skip it. MinIO accepts `x-amz-storage-class: REDUCED_REDUNDANCY` on PutObject and reports that class back inside `<Version>`, so `Client.Objects.List_Versions_Page` returns nothing for any bucket holding such an object. The same crate accepts all fifteen storage classes for the same object through the ListObjects decoder.

## Problem

Commit `5fe6e3e`.

`Finish_Field` validates the element against the model enumeration and raises (`src/flyology-object_storage-s3-versions.adb:798-805`):

```ada
         when Storage_Class_Field =>
            Require_Name ("StorageClass");
            if not Valid_Enumeration (Value, Version_Member_Shape (5)) then
               raise Malformed_Version_Listing with
                 "invalid ObjectVersion storage class";
            end if;
            Item.Current_Version.Storage_Class := Item.Text_Value;
            Item.Current_Version.Has_Storage_Class := True;
```

`Version_Member_Shape` resolves output member 6, `Versions`, then that list's member shape, then member N of `ObjectVersion` (`src/flyology-object_storage-s3-versions.adb:355-363`):

```ada
   function Version_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Version_List : constant Model.Shape_Index := Output_Member_Shape (6);
      Version_Shape : constant Model.Shape_Index := Model.Shape_Index
        (Model.List_Member_Shape (Version_List));
   begin
      return Model.Member_Shape (Version_Shape, Member);
   end Version_Member_Shape;
```

`Valid_Enumeration` has no permissive branch: it returns False for any value outside the list, and False again when the shape carries no enumeration (`src/flyology-object_storage-s3-versions.adb:365-381`):

```ada
   function Valid_Enumeration
     (Value : String; Shape : Model.Shape_Index) return Boolean
   is
      Scalar : constant Model.Shape_Index :=
        (if Model.Kind (Shape) = Model.List_Shape
         then Model.Shape_Index (Model.List_Member_Shape (Shape))
         else Shape);
   begin
      if Model.Enumeration_Count (Scalar) = 0 then
         return False;
      end if;
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) does define that member with a one-value enumeration, so the decoder is faithful to the model. Printed with `python3`:

```
ObjectVersionStorageClass: {"type": "string", "enum": ["STANDARD"]}
ObjectStorageClass enum count: 15
ObjectStorageClass: ['STANDARD', 'REDUCED_REDUNDANCY', 'GLACIER', 'STANDARD_IA', 'ONEZONE_IA', 'INTELLIGENT_TIERING', 'DEEP_ARCHIVE', 'OUTPOSTS', 'GLACIER_IR', 'SNOW', 'EXPRESS_ONEZONE', 'FSX_OPENZFS', 'FSX_ONTAP', 'AWS_BACKUP_WARM', 'AWS_BACKUP_LOW_COST_WARM']
ObjectVersion required: None
ObjectVersion StorageClass member: {"shape": "ObjectVersionStorageClass"}
```

The defect is that the enumeration is applied to a decoder, where a real server's value arrives. The `Object` shape used by ListObjects has fifteen values for the same physical object, and the sibling codec validates against those (`src/flyology-object_storage-s3-listings.adb:646-653`):

```ada
         when Object_Storage_Class_Field =>
            if not Valid_Object_Enumeration (Value, 7) then
               raise Malformed_Listing with
                 "invalid S3 object storage class";
            end if;
            Item.Current_Object.Storage_Class := Item.Text_Value;
```

So the same object decodes through ListObjectsV2 with `StorageClass=REDUCED_REDUNDANCY` and makes ListObjectVersions raise.

The client turns the exception into an invalid response with no partial page (`src/flyology-object_storage-client-low_level.adb:2226-2229`):

```ada
   exception
      when S3.Versions.Malformed_Version_Listing |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjectVersions response";
```

MinIO returns the offending value. The pinned image, `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` from `tests/scripts/test-minio.sh:5`, whose `--version` prints `minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`, answered a signed `PUT` carrying `x-amz-storage-class: REDUCED_REDUNDANCY` with 200. A signed `GET /bucket?versions` on that versioned bucket then answered 200 with a `ListVersionsResult` whose first version element is, verbatim:

```
<Version><Key>obj-reduced-redundancy</Key><LastModified>2026-09-07T06:56:08.281Z</LastModified><ETag>&#34;9dd4e461268c8034f5c8564e155c67a6&#34;</ETag><Size>1</Size><Owner><ID>02d6176db174dc93cb1b899f7c6078f08654445fe8cf1b6ce98d8855f66bdbf4</ID><DisplayName>minio</DisplayName></Owner><StorageClass>REDUCED_REDUNDANCY</StorageClass><IsLatest>true</IsLatest><VersionId>8d8cfaec-244b-48b2-810c-3c203c9f335e</VersionId></Version>
```

The same MinIO refuses `STANDARD_IA`, `GLACIER`, `ONEZONE_IA` and `INTELLIGENT_TIERING` on PutObject with `InvalidStorageClass`, so `REDUCED_REDUNDANCY` is the reachable non-`STANDARD` class there.

There is a second, smaller drift beside the enumeration: `Finish_Version` makes the member mandatory although the model marks it optional and gives `ObjectVersion` no `required` list at all (`src/flyology-object_storage-s3-versions.adb:893-902`):

```ada
   procedure Finish_Version (Item : in out Version_Listing_Handler) is
      Value : Object_Version renames Item.Current_Version;
   begin
      if not Value.Has_Key or else US.Length (Value.Key) = 0
        or else not Value.Has_Version_ID
        or else US.Length (Value.Version_ID) = 0
        or else not Value.Has_Is_Latest
        or else not Value.Has_Last_Modified
        or else not Value.Has_Size
        or else not Value.Has_Storage_Class
```

The in-house server can never expose the defect, because its own serializer applies the same one-value enumeration before emitting a page (`src/flyology-object_storage-s3-versions.adb:1202-1216`):

```ada
      procedure Validate_Version (Item : Object_Version) is
      begin
         if not Item.Has_Key or else US.Length (Item.Key) = 0
```

ending with

```ada
           or else not Valid_Enumeration
             (US.To_String (Item.Storage_Class), Version_Member_Shape (5))
```

No third-party lane can expose it either. The only implementation-corpus caller of `List_Versions_Page` sits inside a routine that returns immediately unless the implementation under test is a Flyology backend (`tests/src/s3_implementation_corpus.adb:3318-3333`):

```ada
      Implementation_Variable : constant String :=
        "FLYOLOGY_S3_IMPLEMENTATION";
      Files_Implementation  : constant String := "flyology-files";
      SQLite_Implementation : constant String := "flyology-sqlite";
   begin
      if not Ada.Environment_Variables.Exists (Implementation_Variable)
        or else
          Ada.Environment_Variables.Value (Implementation_Variable) not in
            Files_Implementation | SQLite_Implementation
      then
         if Phase = Complete_Durable_Routing then
            return;
         end if;
```

so no MinIO, RustFS or SeaweedFS lane runs ListObjectVersions at all, despite a Docker matrix that runs MinIO on every change.

Two artefacts assert the current behaviour and must change with a fix. `tests/src/s3_list_object_versions_corpus.adb:335-341`:

```ada
   Expect_Bad
     (Page
        ("<Version><Size>1</Size><StorageClass>GLACIER</StorageClass>" &
         "<Key>key</Key><VersionId>v</VersionId>" &
         "<IsLatest>true</IsLatest>" &
         "<LastModified>2026-08-23T01:02:03Z</LastModified></Version>"),
      "accepted unmodeled storage class");
```

and the vector table that pins it, `tests/corpora/list-object-versions/members.tsv:30`:

```
version	491	5	StorageClass	body	decoded	Require exactly one pinned ObjectVersion storage class value.	LOV-RS-001,LOV-RS-006,LOV-RS-013
```

The strictness is documented as intended at `docs/qualification/list-object-versions.md:90-91`:

```
Every ObjectVersion has a unique key/version identity, nonnegative signed
64-bit size, exact pinned storage class, canonical boolean and ISO-8601
```

but the only place it reaches a user is the end of the matrix row `docs/compatibility/s3.md:67`, which says `no external interoperability claim` and does not name storage classes.

## What happens now

Spike: the program below decodes a minimal `ListVersionsResult` holding one version, once per storage class, through `S3.Versions.Parse_List_Object_Versions`; runs the same five classes through `S3.Listings.Parse_List_Objects` to show the crate accepts them there; then replays the exact `ListVersionsResult` body the pinned MinIO returned, 1157 bytes, and asserts both versions decode. The `STANDARD` case is the control.

```ada
   function Versions_Page (Storage_Class : String) return String is
     ("<ListVersionsResult xmlns=""" & NS & """>" &
      "<Name>b</Name><MaxKeys>1000</MaxKeys>" &
      "<IsTruncated>false</IsTruncated>" &
      "<Version><Key>k</Key><VersionId>v1</VersionId>" &
      "<IsLatest>true</IsLatest>" &
      "<LastModified>2026-01-01T00:00:00.000Z</LastModified>" &
      "<ETag>&quot;e&quot;</ETag><Size>1</Size>" &
      "<StorageClass>" & Storage_Class & "</StorageClass>" &
      "</Version></ListVersionsResult>");
...
         Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions (Versions_Page (Storage_Class));
      begin
         Check (Natural (Page.Versions.Length) = 1,
                "ListObjectVersions keeps the " & Storage_Class & " version");
```

Output, exit status 1:

```
  -- ListObjectVersions <StorageClass>STANDARD</StorageClass>: decoded, versions=1
  ok: ListObjectVersions keeps the STANDARD version
  ok: ListObjectVersions preserves STANDARD
  -- ListObjectVersions <StorageClass>REDUCED_REDUNDANCY</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a REDUCED_REDUNDANCY version
  -- ListObjectVersions <StorageClass>STANDARD_IA</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a STANDARD_IA version
  -- ListObjectVersions <StorageClass>GLACIER</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a GLACIER version
  -- ListObjectVersions <StorageClass>INTELLIGENT_TIERING</StorageClass>: REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: ListObjectVersions accepts a INTELLIGENT_TIERING version
  -- --- same classes through the ListObjects v1 decoder ---
  --   ListObjects v1 <StorageClass>STANDARD</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>REDUCED_REDUNDANCY</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>STANDARD_IA</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>GLACIER</StorageClass>: decoded, objects=1
  --   ListObjects v1 <StorageClass>INTELLIGENT_TIERING</StorageClass>: decoded, objects=1
  -- --- verbatim MinIO RELEASE.2025-09-07T16-13-09Z body ---
  -- body bytes 1157
  -- MinIO page REJECTED, malformed ListObjectVersions XML: malformed S3 XML document
  FAILED: the MinIO ListVersionsResult decodes with both versions
BUG REPRODUCED: 5 failed expectation(s)
```

The five classes differ by one element and nothing else, and all five decode through the ListObjects path, so the document shape and the harness are not what fires.

A second program drove the same case live against the pinned MinIO through the crate's own high-level client. It created a versioned bucket, put one object with `x-amz-storage-class: REDUCED_REDUNDANCY` (accepted, 200) and one with the default class, read `GET ?versions` directly to record the 200 body quoted above, and then called `Client.Objects.List_Versions_Page` on that bucket and on a second versioned bucket holding only a default-class object. Both calls raised, exit status 1:

```
raised Invalid_Response: malformed ListObjectVersions response
```

The second bucket holds only `STANDARD` versions and still fails, for the separate reason reported as {{ISSUE:S3-DOMAIN-A-7}}.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A valid 200 `ListVersionsResult` from a stock server must decode, whatever storage class its versions report. The model's one-value enumeration describes what AWS itself writes, not what an S3-compatible server may send, and the crate already accepts the fifteen-value domain for the same object through `S3.Listings` (`src/flyology-object_storage-s3-listings.adb:646-653`). Losing a whole page over one entry is the wrong failure mode in any case, since the decoder offers no way to skip past it.

## Suggested treatment

This needs a maintainer decision, because either choice widens a publicly observable acceptance domain:

- Accept any non-empty `StorageClass` text in `Storage_Class_Field` (`src/flyology-object_storage-s3-versions.adb:798-805`), keeping the element required but not the value domain. Widest, and immune to future AWS storage classes.
- Validate against the fifteen-value `ObjectStorageClass` used by the sibling codec, which makes the two listing decoders agree. This also changes the server-side `Validate_Version` (`:1202-1216`), because the serializer would then be free to emit those classes.

The smaller drift beside it is a separate decision: `Finish_Version` requires `Has_Storage_Class` at `:900` although the model marks the member optional and gives the shape no `required` list, so a server that omits the element loses the page too.

Whichever is chosen, `docs/qualification/list-object-versions.md:90-91` states "exact pinned storage class" as the contract being changed and must be reworded, and `tests/corpora/list-object-versions/members.tsv:30` must be updated with it.

The regression tests belong in `tests/src/s3_list_object_versions_corpus.adb`: invert `Expect_Bad` at `:335-341` into an acceptance assertion that the decoded version reports `GLACIER`, and add the MinIO `REDUCED_REDUNDANCY` page as a second case. The spike is the test. Because the failure is a real-server interop break, one MinIO `?versions` call added to `tests/src/s3_implementation_corpus.adb` outside the Flyology-only gate at `:3318-3333` would catch a regression the in-process corpus cannot.

This finding and {{ISSUE:S3-DOMAIN-A-7}} both break ListObjectVersions against MinIO and must land together. Fixing this one alone changes nothing at all against MinIO, because the next-marker rule rejects every untruncated page before any storage class is reached.

## Severity

Every ListObjectVersions call against a bucket holding a version in any class other than `STANDARD` fails outright: `Client.Objects.List_Versions_Page` raises `Invalid_Response` and returns no page, and there is no marker with which to page past the entry. On MinIO that means any bucket holding a `REDUCED_REDUNDANCY` object, which MinIO accepts by default on PutObject; on AWS it means any bucket with lifecycle-transitioned versions. It is a pure function of the response text, so no timing or container state is involved. The matrix row `docs/compatibility/s3.md:67` disclaims external interoperability for this operation, so no documented promise is broken, and a caller using only Flyology backends never sees it. Deterministic.
