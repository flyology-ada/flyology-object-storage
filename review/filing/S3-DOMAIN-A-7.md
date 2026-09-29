Title: Versions.Validate rejects every untruncated MinIO ListObjectVersions page over a lone next marker
Labels: bug
Refs: S3-DOMAIN-A-1

## Summary

`Versions.Validate` requires `NextKeyMarker` and `NextVersionIdMarker` to be present together and to match `IsTruncated`. MinIO emits an empty `<NextVersionIdMarker></NextVersionIdMarker>` on every `?versions` response, including untruncated ones, and omits `<NextKeyMarker>` there, so the first disjunct fires and `Malformed_Version_Listing` is raised for every page. The client turns it into `Invalid_Response`, so `Client.Objects.List_Versions_Page` returns nothing and ListObjectVersions is unusable against MinIO through the high-level client. The pinned model puts no cross-member constraint on either element.

## Problem

Commit `5fe6e3e`.

The pairing rule is the first disjunct of the check, before emptiness or truncation are considered (`src/flyology-object_storage-s3-versions.adb:1031-1041`):

```ada
      elsif Value.Has_Next_Version_ID_Marker /=
        Value.Has_Next_Key_Marker
        or else Value.Is_Truncated /= Value.Has_Next_Key_Marker
        or else
          (Value.Has_Next_Key_Marker
           and then
             (US.Length (Value.Next_Key_Marker) = 0
              or else US.Length (Value.Next_Version_ID_Marker) = 0))
      then
         raise Malformed_Version_Listing with
           "inconsistent ListObjectVersions next markers";
```

A page carrying one marker without the other is rejected whatever its emptiness or truncation, and the client turns the exception into an invalid response with no partial page (`src/flyology-object_storage-client-low_level.adb:2226-2229`):

```ada
   exception
      when S3.Versions.Malformed_Version_Listing |
           S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjectVersions response";
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) expresses no such pairing. `ListObjectVersionsOutput` has no `required` list, both markers are plain optional strings, and their documentation describes what a server sends when the page overflows without forbidding anything else. Printed with `python3`, markup stripped:

```
ListObjectVersionsOutput required: None
NextKeyMarker {"shape": "NextKeyMarker"}
   doc: When the number of responses exceeds the value of MaxKeys, NextKeyMarker specifies the first key not returned that satisfies the search criteria. Use this value for the key-marker request parameter in a subsequent request.
NextVersionIdMarker {"shape": "NextVersionIdMarker"}
   doc: When the number of responses exceeds the value of MaxKeys, NextVersionIdMarker specifies the first object version not returned that satisfies the search criteria. Use this value for the version-id-marker request parameter in a subsequent request.
```

MinIO sends exactly the shape the rule refuses. The pinned image, `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e` from `tests/scripts/test-minio.sh:5`, whose `--version` prints `minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)`, answered a signed `GET /bucket?versions` on a versioned bucket with 200 and this envelope, verbatim apart from the bucket name and the version entries:

```
<ListVersionsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">...<Prefix></Prefix><KeyMarker></KeyMarker><NextVersionIdMarker></NextVersionIdMarker><VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>...
```

`Has_Next_Version_ID_Marker` is therefore True while `Has_Next_Key_Marker` is False, and the first disjunct holds. The same server's truncated page carries both markers non-empty and is accepted:

```
...<KeyMarker></KeyMarker><NextKeyMarker>obj-reduced-redundancy[minio_cache:v2,return:]</NextKeyMarker><NextVersionIdMarker>8d8cfaec-244b-48b2-810c-3c203c9f335e</NextVersionIdMarker><VersionIdMarker></VersionIdMarker><MaxKeys>1</MaxKeys><IsTruncated>true</IsTruncated>...
```

so every untruncated page fails and every truncated one succeeds.

The rule is documented as an invariant at `docs/qualification/list-object-versions.md:86-88`:

```
singletons. Versions, delete markers, and common prefixes count together
against `MaxKeys`; truncated pages require both nonempty next markers, while
final pages reject either one.
```

which is what has to change with the fix. Two corpus cases enforce it. `tests/src/s3_list_object_versions_corpus.adb:284-292`:

```ada
   Expect_Bad
     (Page ("", Is_Truncated => "true"),
      "accepted truncated page without markers");
   Expect_Bad
     (Page
        ("", Markers =>
           "<NextKeyMarker>key</NextKeyMarker>" &
           "<NextVersionIdMarker>version</NextVersionIdMarker>"),
      "accepted final page with next markers");
```

The first stays correct under any fix. The second asserts that a final page carrying both markers is refused, which is the assertion a truncation-driven rule relaxes.

Nothing in the repository catches it. The in-house server never emits a lone marker, and no third-party lane runs the operation at all: the only implementation-corpus caller of `List_Versions_Page` sits inside a routine that returns immediately unless the implementation under test is a Flyology backend (`tests/src/s3_implementation_corpus.adb:3318-3333`):

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

so the Docker matrix that runs MinIO on every change has never sent a `?versions` request through the client.

## What happens now

Spike: the program below puts three documents through `S3.Versions.Parse_List_Object_Versions`. Every `StorageClass` in all three is `STANDARD`, so the storage-class rule reported as {{ISSUE:S3-DOMAIN-A-1}} cannot interfere. The controls are MinIO's untruncated envelope with the empty `NextVersionIdMarker` removed, and MinIO's truncated envelope with both markers non-empty. The third document is MinIO's actual untruncated envelope.

```ada
   MinIO_Untruncated : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" &
     "<ListVersionsResult xmlns=""" & NS & """>" &
     ... &
     "<KeyMarker></KeyMarker>" &
     "<NextVersionIdMarker></NextVersionIdMarker>" &
     "<VersionIdMarker></VersionIdMarker><MaxKeys>1000</MaxKeys>" &
     "<IsTruncated>false</IsTruncated>" & Entry_Text & "</ListVersionsResult>";
...
         Page : constant Versions.List_Object_Versions_Result :=
           Versions.Parse_List_Object_Versions (Document, XML.Default_Limits);
```

Output, exit status 1:

```
  -- untruncated, no NextVersionIdMarker: decoded, versions=1 truncated=FALSE
  ok: untruncated, no NextVersionIdMarker: the page keeps its version
  -- truncated, both next markers set   : decoded, versions=1 truncated=TRUE
  ok: truncated, both next markers set   : the page keeps its version
  -- MinIO untruncated, empty NextVersionIdMarker: REJECTED, inconsistent ListObjectVersions next markers
  FAILED: MinIO untruncated, empty NextVersionIdMarker: the page is accepted
BUG REPRODUCED: 1 failed expectation(s)
```

The first control differs from the failing document by that one empty element and nothing else, so the presence flag alone is what fires.

A second program drove the same case live against the pinned MinIO through `Client.Objects.List_Versions_Page`, on a versioned bucket holding only a default-class object, so no storage class other than `STANDARD` is involved. The call raised, exit status 1:

```
raised Invalid_Response: malformed ListObjectVersions response
```

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

An untruncated page carrying a present-but-empty `NextVersionIdMarker` and no `NextKeyMarker` must decode, since the pinned model imposes no cross-member constraint on either element and both are optional. A truncated page must still carry usable continuation state, so requiring both markers non-empty when `IsTruncated` is true remains correct.

## Suggested treatment

This needs a maintainer decision, because it relaxes an invariant the repository documents:

- Key the rule on truncation and non-emptiness. Require both markers non-empty when `Is_Truncated` is true, and ignore a present-but-empty marker otherwise, by replacing the first two disjuncts at `src/flyology-object_storage-s3-versions.adb:1031-1033` with a truncation-driven test over the marker lengths rather than their presence flags. This admits MinIO and every server that echoes empty continuation elements, and keeps a truncated page without usable markers rejected.
- Keep the presence pairing and accept that ListObjectVersions does not work against servers that echo an empty marker. This leaves the operation unusable against MinIO through the high-level client.

If the first is chosen, `docs/qualification/list-object-versions.md:86-88` states the invariant being relaxed ("final pages reject either one") and must be reworded, and `tests/src/s3_list_object_versions_corpus.adb:287-292` asserts the rejection of a final page carrying next markers and must change with it.

The regression tests belong in `tests/src/s3_list_object_versions_corpus.adb`, beside those marker cases: accept MinIO's untruncated envelope with the empty `NextVersionIdMarker`, keep the truncated-page-without-markers rejection at `:284-286`, and keep rejecting a truncated page whose markers are present but empty. The spike is the test. Because no third-party lane runs the operation, one MinIO `?versions` call added to `tests/src/s3_implementation_corpus.adb` outside the Flyology-only gate at `:3318-3333` would catch a regression the in-process corpus cannot.

This finding and {{ISSUE:S3-DOMAIN-A-1}} both break ListObjectVersions against MinIO and must land together. Fixing this one alone still loses any page containing a version whose storage class is not `STANDARD`, and fixing that one alone changes nothing against MinIO, because every page fails here first.

## Severity

Every untruncated ListObjectVersions page from MinIO is refused, so listing versions of any bucket that fits in one page fails outright: `Client.Objects.List_Versions_Page` raises `Invalid_Response` and returns nothing, with no marker to retry from. In reach it is worse than the storage-class defect reported as {{ISSUE:S3-DOMAIN-A-1}}, since it does not depend on what the bucket holds. It is a pure function of the response text, so no timing or server state is involved. The matrix row `docs/compatibility/s3.md:67` disclaims external interoperability for this operation, so no documented promise is broken, and a caller using only Flyology backends never sees it, because the in-house server never emits a lone marker. Deterministic.
