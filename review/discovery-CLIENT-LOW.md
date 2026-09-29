# Correctness discovery: CLIENT-LOW (low-level prepared S3 operations, generic REST/XML read and mutation families)

Scope: `src/flyology-object_storage-client-low_level.ads` (1-330 public
contracts, 1362-1700 HeadBucket/HeadObject, 6118-6160 object tagging,
6396-6420 CreateSession, 10394-10604 private part) and
`src/flyology-object_storage-client-low_level.adb` read by family: shared
machinery 1-146, 626-1553 (model projector, path/query/scalar validation,
`Prepare_Object_Request`, `Authority`, `Wire_Query`), listings 1553-2366,
CreateSession 2385-2925, multipart 2925-3991 and 12883-14202, ListBuckets
3991-4210, CreateBucket 4242-4458, HeadBucket 4833-4998, object reads
5007-6040 and 7049-7290, GetObjectAttributes 5189-5518, ACL/torrent
6040-6386, PutObject 7290-7927, bucket-control 8213-8308, 8458-8580,
8831-8880, 9798-9872, 10829-10954, DeleteObject 11161-11386, tagging
12249-12579, DeleteObjects 12579-12883, ListParts/ListMultipartUploads
13019-13544, checksum validators 13544-13689, UploadPartCopy/CopyObject
14202-14894, composable start machinery 14894-15007; skimmed (status,
raise, source and echo sites only) 182-540, 4458-4833, 6386-7049,
11386-12249. Read in full: `-client-bounded_rest_xml_reads.ad?`,
`-client-paginated_rest_xml_reads.ad?`, `-client-rest_xml_mutations.ad?`,
`-s3-paginated_rest_xml_reads.ad?`, `src/flyology-object_storage-client.ads`;
`docs/architecture/composable-client-operations.md` 1-480 in full and the
rest by keyword. Dependencies consulted read-only: pinned `flyology_http`
snapshot eb09a80a (`flyology-http-client.ads` 33-66, 190-270, 495-620,
1040-1210; `flyology-http-client.adb` 1876-1890, 6247-6338;
`flyology-http.adb` 31-35), `src/flyology-object_storage-s3-errors.adb`,
`-s3-sigv4.adb` 128-150, `-s3-sigv4_encoding.adb` 19-46, `-s3-listings.adb`
575-615, `-s3-core.ads`, `-s3-buckets.ads`, server emission sites in
`src/flyology-object_storage-server-s3_applications.adb` (4180-4200, 13228,
14563, 15145, 15843, 16344, 16614, 17428). Reference:
`review/baseline/service-2.json` (output shapes and required members for
every object, multipart, listing and bucket operation; `responseCode` for
every Put/Delete; `CopyObjectRequest` condition members),
`review/baseline-rustfs.md`. Coverage inspected:
`tests/src/s3_http_socket_corpus.adb` (2738-2770 HeadObject version cases,
3255-3275 and 5588-5600 5xx fixtures, 4331-4400 and 15040-15290 tagging
version cases), `tests/src/object_storage_test_cases.adb` (HeadObject
outcome tests 15021-17182 by grep), `tests/src/s3_implementation_corpus.adb`
(323-340, 860-940, 1130-1180, 1617-1861, 2985-3030), the qualification
programs `s3_bounded_rest_xml_read_qualification.ad?` and
`s3_paginated_rest_xml_read_qualification.ad?` (headers only).

Severity rubric: P0 memory/aliasing unsafety, security (signature bypass,
traversal, secret exposure, authz bypass), data loss/durability, hang or
deadlock, or an interop-breaking protocol violation a stock client/server
rejects; P1 wrong result or unexpected exception on valid input via a
reachable path, or a documented contract (`.ads`, README, compatibility
matrix, qualification doc) violated; P2 edge-case incorrectness, wrong
diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| CLIENT-LOW-1 | `Execute_Head_Object` raises `Invalid_Response` when a 200 omits `x-amz-version-id` after `versionId=` was requested (every real server on a never-versioned bucket) | P1 | High |
| CLIENT-LOW-2 | `Execute_Get_Object_Attributes` raises `Invalid_Response` when a 200 omits `x-amz-version-id` after `versionId=` was requested | P1 | High |
| CLIENT-LOW-3 | `Execute_{Put,Get,Delete}_Object_Tagging` require exactly one `x-amz-version-id` on every success, rejecting unversioned buckets on every server | P1 | High |
| CLIENT-LOW-4 | Every decoder except HeadBucket/HeadObject/GetObject turns a bodyless or non-XML 4xx/5xx into `Invalid_Response` (composable: `Corrupt_Or_Invalid_Response`) instead of a typed rejection | P2 | Medium |
| CLIENT-LOW-5 | `Prepare_Create_Session` rejects an explicit `Bucket_Key_Enabled = False` that its spec says is preserved, and would serialise any set value as `true` | P2 | High |

---

### CLIENT-LOW-1: `Execute_Head_Object` raises `Invalid_Response` when a 200 omits `x-amz-version-id` after `versionId=` was requested

**Location:** `src/flyology-object_storage-client-low_level.adb:5641-5658`
(`Head_Object_Response_Bound`), `:5879-5886` (raise site in
`Execute_Head_Object`); second site of the same predicate shape in
`src/flyology-object_storage-client-objects.adb:121-155`
(`Get_Object_Response_Bound`, `Head_Object_Response_Bound`; CLIENT-OBJECTS area).

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-low_level.adb:5641-5658`:

```ada
   function Head_Object_Response_Bound
     (Value    : Head_Object_Result;
      Prepared : Prepared_Request) return Boolean
   is
      Requested_Version : constant String := US.To_String
        (Prepared.Requested_Head_Object_Version_ID);
      ...
   begin
      return
        (Requested_Version'Length = 0
         or else US.To_String (Value.Version_ID) = Requested_Version)
        and then
          (Returned_Payer /= "requester"
           or else Requested_Payer = "requester");
   end Head_Object_Response_Bound;
```

`src/flyology-object_storage-client-low_level.adb:5879-5886`:

```ada
            if Result.Kind = Object_Found
              and then not Head_Object_Response_Bound
                (Result.Result, Prepared)
            then
               raise Invalid_Response with
                 "HeadObject response does not match prepared request";
            end if;
```

`Value.Version_ID` is `H ("x-amz-version-id")` (line 5813), i.e. the empty
string when the header is absent, so an absent header fails the equality
against any nonempty requested selector, including the documented current
version selector `null`.

Contract, `src/flyology-object_storage-client-low_level.ads:1570-1571`
(`Head_Object_Result`): `@field Version_ID Optional selected object-version
response value`; spec line 300-301: `Invalid_Response` is "Raised when a
received S3 response violates its modeled contract". The pinned model,
`review/baseline/service-2.json` shape `HeadObjectOutput`, has
`required = []` and `VersionId` is an optional `x-amz-version-id` header, so
a 200 without the header does not violate the modeled contract.

Repository evidence that only the in-repo server satisfies the demand,
`src/flyology-object_storage-server-s3_applications.adb:4188-4193`:

```ada
            if US.Length (Info.Version) > 0 then
               Apps.Set_Header
                 (X, "x-amz-version-id", US.To_String (Info.Version));
            elsif Object_Read_Request.Has_Version_ID then
               Apps.Set_Header (X, "x-amz-version-id", "null");
            end if;
```

Captured wire evidence from RustFS 1.0.0-rc.3, and the byte-identical
failure message in `review/baseline/minio.log:96` and
`review/baseline/seaweedfs.log:99`, are in `review/baseline-rustfs.md`
sections 1, 2 and 5. AWS behaviour (from memory, unverified): S3 omits
`x-amz-version-id` on HEAD/GET of an object in a bucket where versioning was
never enabled; the header is documented as the version ID of the object, not
as an echo of the request selector. Checkable with
`tests/scripts/test-minio.sh` / `test-rustfs.sh` / `test-seaweedfs.sh`.

**Failure scenario:** caller prepares `Prepare_Head_Object` with
`Parameters.Version_ID = "null"` against a never-versioned bucket on MinIO,
RustFS, SeaweedFS (or AWS, unverified). Server answers `200 OK` with ETag,
Content-Length, Last-Modified and no `x-amz-version-id`.
`Decode_Head_Object_Complete_Response` returns `Object_Found`; line 5881
evaluates `"" = "null"` as False; line 5884 raises `Invalid_Response`
"HeadObject response does not match prepared request". The caller never sees
the successful metadata. The repository's own conformance corpus does exactly
this at `tests/src/s3_implementation_corpus.adb:1144-1172`
(`Parameters.Version_ID := "null"`, `Request_Payer := "requester"`,
`Checksum_Mode := True`) and fails on all three real servers.

**Reproduction test sketch:** over the in-process socket fake
(`tests/src/s3_http_socket_corpus.adb`): serve `HEAD /b/k?versionId=null`
with `200`, `ETag: "abc"`, `Content-Length: 3`, `Last-Modified: <IMF date>`,
and no `x-amz-version-id`; call `Prepare_Head_Object` with
`Version_ID = "null"` then `Execute_Head_Object`. Expected: `Object_Found`,
`Result.Version_ID = ""`. Actual: `Invalid_Response`. The same request
against the memory-backed S3 application (`tests/src/s3_memory_server.adb`)
passes only because of the server special case quoted above; Docker runs of
`tests/scripts/test-rustfs.sh` reproduce the real failure.

**Existing coverage:** `tests/src/s3_http_socket_corpus.adb` cases added by
commit 2703ed6 (`head-cancel-version`, `wrong-head-version`) always emit
`x-amz-version-id`; none omits it. `tests/src/object_storage_test_cases.adb`
(same commit) checks the mismatch path only.
`tests/src/s3_implementation_corpus.adb:1144-1172` asserts success for the
real-server exchange and is red at this commit (`review/baseline-rustfs.md`
section 4, 7/7 runs).

**Refutation attempts:** (1) Checked whether `Prepare_Head_Object` rejects
`Version_ID = "null"` so the path could not be reached: it does not; the
corpus sends it. (2) Checked whether the pinned model marks `VersionId`
required on `HeadObjectOutput`: it does not (`required = []`). (3) Checked
whether the HTTP client canonicalises or synthesises the header: the value
comes straight from `Flyology.HTTP.Client.Header (Response, "x-amz-version-id")`.
(4) Checked whether the corpus is gated in CI so the failure could be a known
exclusion: `.github/workflows/ci.yml` runs the real-server scripts only on
schedule and with `FLYOLOGY_S3_SERVER_RUNNER`, which short-circuits before the
corpus (`review/baseline-rustfs.md` section 6). None of these make it a
non-issue.

---

### CLIENT-LOW-2: `Execute_Get_Object_Attributes` raises `Invalid_Response` when a 200 omits `x-amz-version-id` after `versionId=` was requested

**Location:** `src/flyology-object_storage-client-low_level.adb:5383-5397`
(`Decode_Get_Object_Attributes_Complete_Response`), reached from
`Execute_Get_Object_Attributes` (`:5488-5516`) and from the composable
`Client.Objects` GetObjectAttributes operation (it calls the same
`Decode_Get_Object_Attributes_Complete_Response`).

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-low_level.adb:5383-5397`:

```ada
         if Outcome.Kind = Object_Attributes_Found
           and then
             ((Request_Charged'Length > 0
               and then US.To_String
                 (Prepared.Requested_Get_Attributes_Request_Payer) /=
                   "requester")
              or else
                (US.Length
                   (Prepared.Requested_Get_Attributes_Version_ID) > 0
                 and then Version_ID /= US.To_String
                   (Prepared.Requested_Get_Attributes_Version_ID)))
         then
            raise Invalid_Response with
              "GetObjectAttributes response does not match request";
```

`Version_ID` is `Singleton_Header ("x-amz-version-id")` (line 5371-5372), which
returns `""` when the header is absent (line 5349-5350), so an absent header
fails the equality against any nonempty requested selector.

Contract: `src/flyology-object_storage-client-low_level.ads` (the
`Requested_Get_Attributes_Version_ID` comment at 10513-10515 states the
intended binding: "a requested version must be echoed by a successful
response"), but the modeled contract that `Invalid_Response` claims to enforce
(`:300-301`) is `review/baseline/service-2.json` shape
`GetObjectAttributesOutput`: `required = []`, `VersionId` optional header.
The design intent itself is what contradicts the model.

**Failure scenario:** `Prepare_Get_Object_Attributes` with
`Parameters.Version_ID = "null"` (the documented selector for the current
version in a never-versioned bucket) against MinIO, RustFS, SeaweedFS or AWS
(unverified) → `200` with `<GetObjectAttributesResponse>` and no
`x-amz-version-id` → `Decode_Get_Object_Attributes_Response` returns
`Object_Attributes_Found` → lines 5390-5394 compare `"" /= "null"` → line 5395
raises `Invalid_Response`. The same request against the in-repo server
also fails: the in-repo attributes handler
(`src/flyology-object_storage-server-s3_applications.adb:16348-16352`) emits
`x-amz-version-id` only when the stored version is nonempty and has no
`null` fallback, unlike the GET/HEAD path quoted in CLIENT-LOW-1. So this one
reproduces against the memory backend without Docker.

**Reproduction test sketch:** in-process loopback server over the memory
backend (`tests/src/s3_server_harness.adb`, `tests/src/s3_memory_server.adb`):
put one object into a never-versioned bucket, then
`Prepare_Get_Object_Attributes` with `Version_ID = "null"`,
`Attributes.Entity_Tag = True` and `Execute_Get_Object_Attributes`. Expected
`Object_Attributes_Found` with `Result.Version_ID = ""`; actual
`Invalid_Response` "GetObjectAttributes response does not match request".
Same with the socket fake serving `200` plus
`<GetObjectAttributesResponse xmlns="..."><ETag>abc</ETag></GetObjectAttributesResponse>`
and no `x-amz-version-id`. Also reachable through the composable
`Client.Objects` operation, which calls the same decoder
(`src/flyology-object_storage-client-objects.adb:4179`).

**Existing coverage:** `tests/src/s3_implementation_corpus.adb:1675-1861`
(`Require_Get_Object_Attributes`) never sets `Parameters.Version_ID`, so the
real-server corpus does not reach the branch. `tests/src/s3_http_socket_corpus.adb`
covers attributes mismatch cases where the fake echoes a version (rg
`attributes` there); none omits the header after a versioned request.

**Refutation attempts:** (1) Model: `VersionId` optional on
`GetObjectAttributesOutput`. (2) `Prepare_Get_Object_Attributes` accepts any
`Version_ID` up to 8,192 bytes (line 5237), so `null` reaches the wire. (3)
Looked for a caller that strips `Version_ID` before preparing: the corpus and
`Client.Objects` pass it through. Not refuted.

---

### CLIENT-LOW-3: `Execute_{Put,Get,Delete}_Object_Tagging` require exactly one `x-amz-version-id` on every success, rejecting unversioned buckets on every server

**Location:** `src/flyology-object_storage-client-low_level.adb:12465-12478`
(`Response_Version_ID` inside `Execute_Object_Tagging`), `:12533-12539`
(second, redundant echo check). Second site of the same demand in
`src/flyology-object_storage-client-objects.adb:7177-7189`
(`Tagging_Version_ID`; CLIENT-OBJECTS area, deferred discovery in
`review/baseline-rustfs.md` section 8).

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-low_level.adb:12465-12478`:

```ada
         function Response_Version_ID
           (Response : Flyology.HTTP.Client.Response;
            Success  : Boolean) return String
         is
            Count : constant Natural :=
              Flyology.HTTP.Client.Header_Count
                (Response, "x-amz-version-id");
         begin
            if Count > 1 or else (Success and then Count /= 1) then
               raise Invalid_Response with
                 "invalid object tagging version header multiplicity";
            elsif Count = 0 then
               return "";
```

`Success` is `Status = Model.Response_Code (Expected)` (line 12529), i.e. 200
for Put/Get and 204 for Delete. So every successful tagging response without
`x-amz-version-id` raises, regardless of whether the request carried a
`versionId`.

Contract: `review/baseline/service-2.json` shapes `PutObjectTaggingOutput`,
`GetObjectTaggingOutput` (required = `["TagSet"]` only) and
`DeleteObjectTaggingOutput` all model `VersionId` as an optional
`x-amz-version-id` header. The spec's own field comment for
`Requested_Object_Tagging_Version_ID` (`low_level.ads:10540-10543`) says
"Empty means the request selected the current version, so any returned
version remains an observation rather than proof", which the code contradicts
by making the header mandatory even then.

Wire evidence: `review/baseline-rustfs.md` section 8 captured RustFS
answering `PUT /bucket/native-object?tagging` with `200 OK`, `content-length:
0` and no `x-amz-version-id`; the corpus then failed in the
`Client.Objects` twin of this check. AWS (from memory, unverified) omits the
header on unversioned buckets for all three tagging operations; checkable
with `tests/scripts/test-minio.sh`.

**Failure scenario:** any caller uses `Prepare_Put_Object_Tagging` (no
`Version_ID`) then `Execute_Put_Object_Tagging` against a bucket that has
never had versioning enabled on MinIO/RustFS/SeaweedFS. Server: `200 OK`,
empty body, no `x-amz-version-id`. Line 12474 raises `Invalid_Response`
"invalid object tagging version header multiplicity" although the tags were
applied. Same for `Execute_Get_Object_Tagging` (200 with `<Tagging>` body) and
`Execute_Delete_Object_Tagging` (204). The caller cannot distinguish this
from a corrupt response; the mutation is reported as unknown.

**Reproduction test sketch:** the socket fake already serves the exact
shapes: `tests/src/s3_http_socket_corpus.adb:4331-4333` (`PUT
/example-bucket/tag-put-missing?tagging` → 200, no version header), `:4360-4362`
(`GET …/tag-get-missing?tagging` → 200 + `<Tagging>`), `:4385-4388`
(`DELETE …/tag-delete-missing?tagging` → 204). Expected per model:
`Tags_Put` / `Tags_Gotten` / `Tags_Deleted` with `Version_ID = ""`. Actual:
`Invalid_Response`. Against real servers: `tests/scripts/test-rustfs.sh` after
CLIENT-LOW-1 is fixed (the corpus reaches tagging at exchange 60).

**Existing coverage:** `tests/src/s3_http_socket_corpus.adb:15092-15253`
(`Require_Invalid_Version` with `Invalid_Version_Kind = Missing`) asserts the
wrong behaviour: it requires `Invalid_Response` (synchronous) or
`Corrupt_Or_Invalid_Response` (composable) for the `*-missing` fixtures and
raises `"... object tagging accepted missing version response"` otherwise.
That assertion must be inverted when the code is fixed.
`tests/src/s3_implementation_corpus.adb:1617-1673` (`Require_Object_Tagging`)
goes through `Client.Objects.Put_Tags/Get_Tags/Delete_Tags` and expects
success from real servers, so it contradicts the socket assertion.

**Refutation attempts:** (1) Model: optional in all three outputs. (2)
Checked whether the in-repo server always emits the header so the memory
server run could be the reference: it does (rg `x-amz-version-id` in
`server-s3_applications.adb` tagging handlers), which is why CI is green and
real servers are not. (3) Checked whether a `versionId`-less request could be
argued to require the echo of the "current" version: the spec comment quoted
above says the opposite. Not refuted.

---

### CLIENT-LOW-4: Every decoder except HeadBucket/HeadObject/GetObject turns a bodyless or non-XML 4xx/5xx into `Invalid_Response` instead of a typed rejection

**Location:** `src/flyology-object_storage-client-low_level.adb:1694`
(ListObjects), `:1958` (ListObjectsV2), `:2228` (ListObjectVersions),
`:3340` (CreateMultipartUpload), `:3884` (CompleteMultipartUpload), `:4369`
(CreateBucket), `:5331` (GetObjectAttributes), `:7733` (PutObject), `:8240`
(bucket-configuration deletions), `:10849` (bucket-control mutations),
`:8875-9784` (every bucket-control GET), `:11299` (DeleteObject), `:12412`
(object tagging), `:12732` (DeleteObjects), `:12925` (AbortMultipartUpload),
`:13193` (ListParts), `:13427` (ListMultipartUploads), `:14044`
(UploadPart), `:14426` (UploadPartCopy), `:14779` (CopyObject); root cause
`src/flyology-object_storage-s3-errors.adb:109-128`.

**Severity:** P2. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage-s3-errors.adb:116-127` (an empty body or any
non-`<Error>` body raises):

```ada
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Code
        or else not Handler.Seen_Message
        ...
         raise Malformed_Error with "S3 error lacks Code or Message";
      ...
      when XML.XML_Error =>
         raise Malformed_Error with "malformed S3 error XML";
```

Representative decoder, `src/flyology-object_storage-client-low_level.adb:1682-1697`
(ListObjects):

```ada
      else
         declare
            Value : S3.Errors.Error_Response :=
              S3.Errors.Parse (Payload, Limits);
         ...
   exception
      when S3.Listings.Malformed_Listing | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed ListObjects response";
```

The repository already treats this as wrong for GetObject,
`src/flyology-object_storage-client-low_level.adb:7141-7166`:

```ada
            if Whitespace_Only (Text) then
               return (Kind => Get_Object_Rejected, Status => Status,
                       Error => Head_Error ("GetObject", Status, ...));
            end if;
            begin
               return (... Error => Error_Response (Text, ...));
            exception
               when S3.Errors.Malformed_Error =>
                  --  S3 peers and intermediaries may return bodyless or
                  --  non-XML HTTP errors.  Preserve the typed rejection and
                  --  wire status instead of turning a valid rejection into
                  --  a client protocol failure.
```

Contract: `low_level.ads:300-301` says `Invalid_Response` is for a response
that "violates its modeled contract"; a 503 or 502 produced by a load
balancer, or a 403/404 with an empty body, is not a modeled S3 response at
all, and every `*_Outcome` type carries a `Rejected` variant with `Status`
for exactly this purpose. In the composable families the same exception is
mapped to `Normalize_Failure (Response_Invalid, ...)` →
`Corrupt_Or_Invalid_Response` (`bounded_rest_xml_reads.adb:106-112`), so a
retryable 503 is classified as a corrupt response rather than
`Unavailable_Or_Retryable`.

**Failure scenario:** a caller runs `Execute_List_Objects_V2` (or any of the
operations above) through a reverse proxy or against a server under load;
the peer answers `503 Service Unavailable` with `Content-Type: text/html`
and an HTML body, or `403 Forbidden` with `Content-Length: 0`.
`S3.Errors.Parse` raises `Malformed_Error`; the decoder converts it to
`Invalid_Response "malformed ListObjectsV2 response"`. The caller cannot see
the status code or distinguish a transient 503 from a corrupt 200; a
composable caller sees `Corrupt_Or_Invalid_Response`.

**Reproduction test sketch:** socket fake serving
`GET /example-bucket?list-type=2&max-keys=1000` → `HTTP/1.1 503 Service
Unavailable`, `Content-Type: text/html`, body `<html><body>upstream
unavailable</body></html>`; `Prepare_List_Objects_V2` + `Execute_List_Objects_V2`.
Expected (by analogy with GetObject and with the `Rejected` variant):
`Outcome.Kind = Rejected`, `Status = 503`, `Error.Code = "HTTP503"`; actual:
`Invalid_Response`. Repeat with a `403` and empty body for `Execute_Put_Object`.

**Existing coverage:** every 4xx/5xx fixture in
`tests/src/s3_http_socket_corpus.adb` carries a well-formed `<Error>` body
(e.g. `:3260-3263`, `:5593-5597`); the only bodyless/non-XML error tests are
the GetObject ones behind `:7141-7166`. None asserts the behaviour above.

**Refutation attempts:** (1) Looked for a wrapper that catches
`Malformed_Error` before these decoders: the composable generics catch only
`Invalid_Response` and map it to `Response_Invalid`. (2) Checked whether the
model requires an `<Error>` body on every non-2xx: the model describes
`errors` shapes per operation but says nothing about intermediaries; AWS
itself always emits XML, which is why this is P2 (diagnostics on
non-S3-originated responses) rather than P1. (3) Checked that HEAD paths and
GetObject are deliberately tolerant (`Head_Error` at `:4911`, `:5677`,
`:7145`, `:7163`), confirming the inconsistency is not intentional across
the file.

---

### CLIENT-LOW-5: `Prepare_Create_Session` rejects an explicit `Bucket_Key_Enabled = False` that its spec says is preserved, and would serialise any set value as `true`

**Location:** `src/flyology-object_storage-client-low_level.adb:2430-2434`
(`Validate_Create_Session_Policy`), `:2470-2480` (call from
`Prepare_Create_Session`), `:2496-2502` (serialisation);
`src/flyology-object_storage-client-low_level.ads:6402-6416` (contract).

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-low_level.ads:6402-6409`:

```ada
   --  Every non-resource member in the pinned CreateSession input. Empty
   --  strings preserve omission; Bucket_Key_Enabled preserves absent versus
   --  explicit false.
   ...
   --  @field Bucket_Key_Enabled Presence-preserving bucket-key request flag
```

`src/flyology-object_storage-client-low_level.adb:2430-2434` (the same
predicate is applied to the request at 2470-2480, mapping the raise to
`Invalid_Request "invalid CreateSession parameters"`):

```ada
        or else (Bucket_Key_Enabled.Is_Set
                 and then not Bucket_Key_Enabled.Value)
      then
         raise Invalid_Response with Failure;
```

`src/flyology-object_storage-client-low_level.adb:2496-2502`:

```ada
      if Parameters.Bucket_Key_Enabled.Is_Set then
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String ("BucketKeyEnabled"),
            Map_Key => US.Null_Unbounded_String,
            Value => US.To_Unbounded_String ("true"));
```

The pinned model (`CreateSessionRequest.BucketKeyEnabled`, boolean header
`x-amz-server-side-encryption-bucket-key-enabled`) admits `false`.

**Failure scenario:** caller sets
`Parameters.Bucket_Key_Enabled := (Is_Set => True, Value => False)` with
`Server_Side_Encryption = "aws:kms"` and a key id, expecting the documented
"explicit false" to reach the wire. `Prepare_Create_Session` raises
`Invalid_Request`. Had the policy check not fired, line 2501 would have sent
`true`, silently inverting the caller's value.

**Reproduction test sketch:** pure preparation, no server: call
`Prepare_Create_Session` with the parameters above and an HTTPS
virtual-hosted origin. Expected per spec: a prepared request whose
`Canonical_Request` contains
`x-amz-server-side-encryption-bucket-key-enabled:false`; actual:
`Invalid_Request`.

**Existing coverage:** none found for an explicit false (`rg
Bucket_Key_Enabled tests/src/s3_http_socket_corpus.adb` shows only true /
absent cases).

**Refutation attempts:** (1) Considered whether S3 Express directory
buckets forbid `false` so the policy is deliberate: plausible (from memory,
unverified), but then the `.ads` comment is what is wrong, and line 2501
would still be a latent inversion if the policy were relaxed. Classified P2
rather than P1 because no wrong bytes can reach the wire today; the defect
is a contract/documentation drift plus dead-but-wrong serialisation.

---

## Areas reviewed with no findings

- `Prepare_Model_Request_Internal` / `Prepare_Model_Request` /
  `Prepare_Model_Streaming_Request` (`low_level.adb:999-1381`): member
  lookup, duplicate and keyed-member rejection, `Content-Length` binding to
  the payload, required-member enforcement, URI template expansion with
  greedy `{Key+}` (slash preserved) and single encoding matching what
  `SigV4.Sign` canonicalises, fixed-query splitting, virtual-hosted host
  prefix check, payload-hash selection (explicit / UNSIGNED-PAYLOAD over
  HTTPS only / computed), generated request checksum header. Header
  injection through user metadata or any header value is blocked by
  `Flyology.HTTP.Client.Add_Header` raising `Constraint_Error`
  (`flyology-http-client.ads:207-215`), mapped to `Invalid_Request`.
- `Prepare_Object_Request`, `Authority`, `Wire_Query`
  (`low_level.adb:1410-1553`): host field byte-identical to
  `flyology_http`'s `Host_Field` (`flyology-http-client.adb:1876-1890`,
  default port omitted, IPv6 bracketed); `=` stripped only for empty values
  after canonicalisation, matching SigV4's `name=` canonical form.
- The three client generics (`bounded_rest_xml_reads.adb`,
  `paginated_rest_xml_reads.adb`, `rest_xml_mutations.adb`): response limit
  accepts exactly `Maximum_Document_Bytes` and rejects one byte over; sink
  overflow becomes a typed `Response_Sink_Failed`; saved exceptions re-raised
  at `Finish`; prepared request cleared only once the child is inactive;
  cancellation forwarded to an active child; restart only through `Start`
  after `Finish`; one absolute deadline for the child exchange; one-shot
  in-memory source with exact declared length.
- `S3.Paginated_REST_XML_Reads` envelope decoder: root/container/item
  structure, namespace consistency, whitespace-only text, scalar close
  matching; duplicate `IsTruncated`/token members fall to
  `Set_Extra_Scalar`, which every instantiation (`metrics`, `analytics`,
  `inventory`, `intelligent_tiering`) implements as a rejection.
- Response-echo bindings for ListObjects v1/v2, ListObjectVersions,
  ListParts, ListMultipartUploads, ListBuckets, CreateMultipartUpload
  (present-and-different form), CompleteMultipartUpload, PutObject and
  UploadPart checksum echo, DeleteObjects entry binding: consistent with the
  model's default echoes (`MaxKeys` default 1000 = `Page_Size'Last`,
  `PartNumberMarker`/`MaxParts` always sent explicitly); the real-server
  corpus passes v1/v2 listings with a prefix.
- 200-with-`<Error>` detection for CompleteMultipartUpload, CopyObject and
  UploadPartCopy (`:3824-3835`, `:14740-14750`, `:14389-14399`).
- Non-replayable sources for every conditional or non-idempotent mutation
  (PUT tagging/versioning/lock/legal-hold/retention/bucket controls,
  CreateBucket, CompleteMultipartUpload, DeleteObject, DeleteObjects,
  AbortMultipartUpload, DeleteObjectAnnotation); PutObject/UploadPart stream
  the caller's source with a caller-supplied payload hash.
- Status-class handling: 3xx is never followed (`flyology_http` default
  `No_Redirects`) and is reported through the rejection variant when an
  `<Error>` body is present; `Head_Error` synthesises `HTTP<status>` for
  bodyless HEAD rejections; whole-exchange timeout and cancellation token
  are applied to both `Execute` and `Read_All`; `Response_Too_Large` is
  mapped to `Invalid_Response` at every `Read_All` site with a bound of 1 for
  HEAD and PutObject/UploadPart successes.
- Singleton-header rules, `Valid_Content_Range` (206 must cover
  `Content-Length` exactly), `Valid_Read_Checksum_Headers` composite/full
  object arithmetic, `Content_MD5` base64, `Valid_ISO_8601_Timestamp`,
  `Valid_Response_Entity_Tag`, `Valid_Model_Scalar` list/enum/bounds.

## Observations not counted

- Synchronous `Execute_Copy_Object` (`:14865-14893`) and
  `Execute_Upload_Part_Copy` (`:14506-14535`) send a bodiless PUT through
  the retained-request path; `flyology_http` replays an unconditional
  idempotent PUT once on a stale reused transport even when admission is
  `Possibly_Admitted` (`flyology-http-client.adb:6320-6338`), and
  `x-amz-copy-source-if-*` are not in its `Has_Mutation_Condition`
  (`:6250-6257`). The architecture doc's "non-replaying CopyObject" claim
  covers the composable `Client.Transfers` operation (empty one-shot
  source), not these synchronous entry points. Worst case is a duplicate
  copy or extra version, not data loss.
- `Valid_Model_Scalar` (`:897-999`) validates integer members with
  `Long_Long_Integer'Value`, which accepts Ada literal forms (`1E3`,
  `1_000`, `16#3E8#`, leading `+`) and then forwards the original text to
  the wire; only reachable through the public `Prepare_Model_Request` with
  such text; typed preparers always format with `'Image`.
- `Validate_Head_Object_Headers` (`:5588-5639`) requires a quoted ETag and a
  parseable `Last-Modified` on every 200/206 although the model marks both
  optional; AWS always sends them; third-party behaviour for SSE-KMS or
  restored objects unverified. Same demand for ETag on PutObject/UploadPart
  200 (`Required => True`).
- `Validate_Create_Multipart_Headers` (`:3273`) requires
  `x-amz-checksum-algorithm` and `x-amz-checksum-type` to be both present or
  both absent; unverified against MinIO/RustFS/SeaweedFS (the corpus already
  carries a RustFS multipart-checksum divergence mode).
- Listing echo comparison under `URL_Encoding` uses
  `SigV4_Encoding.URI_Encode` (space → `%20`, `Encode_Slash => False`);
  whether AWS's `encoding-type=url` output is byte-identical for
  Prefix/Delimiter/Marker/StartAfter is unverified, and the real-server
  corpus never sets `URL_Encoding`. ListObjectsV2 additionally requires
  `Has_Delimiter` to be exactly the request presence (`:2022-2023`), unlike
  v1's tolerant `Matches_Optional_Echo`.
- `Valid_Read_Checksum_Headers` (`:13593-13687`) rejects a 200 carrying two
  `x-amz-checksum-*` headers; whether AWS ever returns the default
  CRC64NVME alongside an additional checksum on GET/HEAD is unverified.
- `Decode_Delete_Objects_Complete_Response` (`:12777-12820`) requires an
  exact key/version pair match for every `<Deleted>`/`<Error>` entry and no
  `<Deleted>` entries in Quiet mode; a server echoing `<VersionId>null</VersionId>`
  for an unversioned request entry, or ignoring Quiet, would be reported as
  `Invalid_Response` (unverified).
- HEAD responses carrying `Transfer-Encoding` are rejected (`:5757-5759`,
  `:4935-4937`) although RFC 9110 permits the field on HEAD; no known server
  does this.
- CreateSession: the raw XML payload and the intermediate
  `Raw_Create_Session_Credentials` Unbounded_Strings holding the secret key
  are not zeroized (`:2674-2703`); the architecture doc states that
  allocator memory is not zeroed, so this is a documented boundary.
- `Execute_Create_Multipart_Upload` (`:3505-3526`) lacks the up-front
  `Prepared.Operation` check every other executor has; a mismatched prepared
  request is sent before the decoder rejects it.
- The `Wire_Query` transformation means a query value that is genuinely
  empty (`versionId=`) is sent as `versionId`; both sides canonicalise
  identically, but a server that distinguishes `?versionId` from
  `?versionId=` would see the former.
