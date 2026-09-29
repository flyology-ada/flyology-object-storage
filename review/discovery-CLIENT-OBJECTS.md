# Correctness discovery: CLIENT-OBJECTS (object convenience client)

Scope: `src/flyology-object_storage-client-objects.ads` (all 5,433 lines) and
`src/flyology-object_storage-client-objects.adb` (all 8,884 lines), read
against `docs/architecture/client-objects.md` and
`docs/qualification/{get-object,head-object,object-reads,conditional-put,
object-tagging,get-object-attributes,delete-object}.md`.
`docs/qualification/{put-object,copy-object}.md` were consulted only for
references to `Client.Objects` (put-object.md:145-149; copy-object.md has
none). Reference material: the pinned model `review/baseline/service-2.json`
(output shapes `GetObjectOutput`, `HeadObjectOutput`, `PutObjectOutput`,
`DeleteObjectOutput`, `PutObjectTaggingOutput`, `GetObjectTaggingOutput`,
`DeleteObjectTaggingOutput`, `GetObjectAttributesOutput`, ACL/legal-hold/
retention outputs, all without a `required` marker on any header member),
`review/baseline-rustfs.md`, the low-level contracts in
`src/flyology-object_storage-client-low_level.ads` (result records at
`:1563-1660`, `:1740-1830`, `:2932-2990`, `:5803-5850`, `:6082-6210`) and the
relevant decoders in `client-low_level.adb` (`:5570-5610`, `:5641-5658`,
`:5933-5997`, `:7205-7225`, `:12367-12540`), `Resolve_Range`
(`src/flyology-object_storage.adb:957-1010`), `Parse_Range_Header`
(`src/flyology-object_storage-s3-core.adb:96-190`), `Parse_Byte_Count`
(`src/flyology-object_storage-s3-wire_core.adb:24-45`), and the pinned
`flyology_http` snapshot `eb09a80a` (`~/.local/share/alire/releases/
flyology_http_0.1.3_eb09a80a/src/flyology-http-client.ads`, `Finish`
contracts `:1007-1033`, replay rules `:502-506`, `:558-562`,
`Rewindable_Request_Body_Source` `:314-324`). Coverage inspected:
`tests/src/s3_http_socket_corpus.adb` (GetObject/HeadObject version cases
`:2586-2660`, `:2733-2790`, `:9308-9336`, `:9711-9745`; tagging cases
`:4225-4410`, `:15040-15240`), `tests/src/s3_implementation_corpus.adb`
(`:1144-1170`, `:1617-1673`, `:2700-2712`),
`tests/src/flyology-object_storage-client-objects-testing.ad?` (certainty
corpora), `tests/corpora/composable-client/put-certainty.tsv`,
`tests/src/s3_get_object_torrent_socket_corpus.adb` (`:650-950`), and
`tests/src/object_storage_test_cases.adb` (no direct `Client.Objects` calls;
its 26 `Objects.` hits are listing-record fields).

CopyObject is not part of this package (it lives in
`Client.Transfers`/`Low_Level`), so the copy-source, metadata-directive and
"200 with Error body" items from the area brief are out of scope here.
Header-to-field decoding (Last-Modified, ETag quoting, user metadata, storage
class, checksum and expiration headers) is done by
`Low_Level.Decode_*_Complete_Response`; this area only checked what the
Objects layer adds on top (version/payer binding, range binding, tagging
version header, ACL/annotation singleton headers, torrent length).

Severity rubric: P0 memory or aliasing unsafety, security-relevant defect,
data loss or durability violation, hang or deadlock, or an interop-breaking
protocol violation that a stock client or server rejects; P1 wrong result or
unexpected exception on valid input via a reachable path, or a documented
contract violated; P2 edge-case incorrectness, wrong diagnostics, or contract
drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| CLIENT-OBJECTS-1 | Whole/range GetObject and HeadObject reject a valid 200/206 that omits `x-amz-version-id` after a `versionId=` request | P1 | High |
| CLIENT-OBJECTS-2 | Put/Get/DeleteObjectTagging reject every successful response that omits `x-amz-version-id`, even with no version requested | P1 | High |

---

### CLIENT-OBJECTS-1: Whole/range GetObject and HeadObject reject a valid 200/206 that omits `x-amz-version-id` after a `versionId=` request

**Location:** `src/flyology-object_storage-client-objects.adb:121-137`
(`Get_Object_Response_Bound`), `:139-155` (`Head_Object_Response_Bound`);
callers `:951-956` (synchronous `Get_Whole`, `Whole_Get_Outcome` overload),
`:2429-2434` (composable whole read, also behind the synchronous
`Get_Whole` at `:980-1012`), `:2551-2556` (composable range read, also behind
`Get_Range` at `:1014-1047`), `:2963-2973` (composable HeadObject, also behind
`Head_Object` at `:1049-1073`).

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-objects.adb:121-137`
```ada
   function Get_Object_Response_Bound
     (Result        : Low_Level.Get_Object_Result;
      Version_ID    : US.Unbounded_String;
      Request_Payer : US.Unbounded_String) return Boolean
   is
      Requested_Version : constant String := US.To_String (Version_ID);
      Requested_Payer : constant String := US.To_String (Request_Payer);
      Returned_Payer : constant String :=
        US.To_String (Result.Request_Charged);
   begin
      return
        (Requested_Version'Length = 0
         or else US.To_String (Result.Version_ID) = Requested_Version)
        and then
          (Returned_Payer /= "requester"
           or else Requested_Payer = "requester");
   end Get_Object_Response_Bound;
```
`Head_Object_Response_Bound` (`:139-155`) is the same predicate over
`Low_Level.Head_Object_Result`.

`src/flyology-object_storage-client-objects.adb:951-956` (synchronous whole read)
```ada
         elsif not Get_Object_Response_Bound
           (Head.Result, US.To_Unbounded_String (Version_ID),
            US.To_Unbounded_String (Request_Payer))
         then
            raise Low_Level.Invalid_Response with
              "GetObject response does not match prepared request";
```

`src/flyology-object_storage-client-objects.adb:2963-2973` (composable HeadObject)
```ada
               if Head.Kind = Low_Level.Object_Found
                 and then not Head_Object_Response_Bound
                   (Head.Result, Item.Requested_Version_ID,
                    Item.Requested_Request_Payer)
               then
                  Item.Final_Result :=
                    (Kind        => Head_Exchange_Failed,
                     Failure     => Corrupt_Or_Invalid_Response,
                     HTTP_Result => HTTP_Client.Response_Invalid,
```
The whole and range readers (`:2418-2434`, `:2543-2556`) clear the
destination and store `Invalid_Read_Result` / `Invalid_Range_Read_Result`
(`Failure => Corrupt_Or_Invalid_Response`, `HTTP_Result => Response_Invalid`).

The decoder that fills `Result.Version_ID` copies the header verbatim and
leaves it empty when absent: `src/flyology-object_storage-client-low_level.adb:5813`
(HeadObject) and `:7220` (GetObject), both `Version_ID => H ("x-amz-version-id")`.

The pinned model declares the header optional. `review/baseline/service-2.json`
shapes `GetObjectOutput` and `HeadObjectOutput` have no `required` list and
`VersionId` is `{"shape":"ObjectVersionId","location":"header",
"locationName":"x-amz-version-id"}` (checked with `python3` over the JSON).
The low-level record says the same:
`src/flyology-object_storage-client-low_level.ads`, `Head_Object_Result`,
`@field Version_ID Optional selected object-version response value`.

A never-versioned bucket on the three reference servers omits the header for
`?versionId=null`. `review/baseline-rustfs.md` section 1 records the verbatim
RustFS `HEAD …?versionId=null` exchange (`HTTP/1.1 200 OK`, `etag`,
`last-modified`, checksum headers, no `x-amz-version-id`); section 5 records
byte-identical failures in `review/baseline/minio.log:96` and
`review/baseline/seaweedfs.log:99`; section 3 (marked there as from memory,
unverified) records that AWS omits the header for objects in a bucket where
versioning was never enabled. Section 2 isolates the cause to the identical
predicate at `client-low_level.adb:5641-5658` (CLIENT-LOW-1, another area) by
injecting the header through a proxy, and names the four objects-layer
predicates above as sharing the defect.

The in-repo server carries a fallback whose only effect is to satisfy this
check, so the memory-server CI corpus cannot observe it:
`src/flyology-object_storage-server-s3_applications.adb:4188-4194` (HeadObject:
emit `x-amz-version-id: null` whenever the request carried a `versionId`) and
`:16619-16622` (GetObject `Set_Common_Headers`: always emit the header, `"null"`
when the backend has no version).

**Failure scenario:** the caller runs `Client.Objects.Get_Whole (…,
Version_ID => "null")`, `Get_Range (…, Version_ID => "null")` or `Head_Object`
with `Parameters.Version_ID = "null"` against MinIO, RustFS, SeaweedFS (or AWS)
on a bucket that never had versioning enabled. The server returns `200 OK`
(`206` for the range) with a strong ETag, `Content-Length`, `Last-Modified` and
the body, and no `x-amz-version-id`. `Low_Level.Decode_*_Complete_Response`
accepts the head with `Version_ID = ""`. The predicate evaluates
`"" = "null"` → False. The synchronous `Get_Whole` raises
`Low_Level.Invalid_Response` after `Execute_Get_Object` returned (body not yet
read, lease released by `Response` finalization); the composable whole/range
reads discard the fully received bytes and return `*_Exchange_Failed` with
`Failure = Corrupt_Or_Invalid_Response`; HeadObject returns
`Head_Exchange_Failed`. A valid read is reported as a corrupt response.

**Reproduction test sketch:** in-process, reuse the existing fake-server case
`scoped-get-version-missing` (`tests/src/s3_http_socket_corpus.adb:2607-2612`:
`200 OK`, `etag: "scoped-get-version"`, no version header, request
`?versionId=expected-version`) and call
`Objects.Get_Whole (…, Expected_Entity_Tag => """scoped-get-version""",
Version_ID => "expected-version")`. Expected: `Whole_Get_Response_Available`,
`Response.Kind = Object_Opened`, `Response.Result.Version_ID = ""`,
destination holds the body. Actual: `Whole_Get_Exchange_Failed`,
`Failure = Corrupt_Or_Invalid_Response`, destination length 0 (this is exactly
what `:9333` asserts today). Same for `scoped-head-version-missing`
(`:2757-2760`, asserted invalid at `:9741`). Against a real server:
`tests/scripts/test-rustfs.sh` (or `test-minio.sh`, `test-seaweedfs.sh`)
already stops at the low-level HeadObject (`review/baseline-rustfs.md`
section 4, 7/7 runs); after CLIENT-LOW-1 is fixed the corpus's next
`Client_Objects` reads with `Version_ID => "null"` fail here.

**Existing coverage:** `tests/src/s3_http_socket_corpus.adb:9333`
(`Require_Invalid_Whole_Get ("scoped-get-version-missing")`, definition
`:9308-9331`) and `:9741` (`Require_Invalid_Head
("scoped-head-version-missing")`, definition `:9711-9739`) assert that an
absent header is an invalid response, i.e. they assert the defective
behaviour. `:2615-2645`, `:2765-2790` and `:9334-9336` cover mismatched,
duplicate, control-character and DEL values, whose rejection is correct. No
test serves a `200` without the header and expects success.
`docs/qualification/get-object.md:11-12` and
`docs/qualification/head-object.md:10-11` ("a successful response must echo it
byte-for-byte") encode the same requirement and must change with the fix.

**Refutation attempts:** (a) looked for a caller-side guard that suppresses or
rewrites `"null"`: none; `:917`, `:2673`, `:2794`, `:3063` copy the caller's
`Version_ID` verbatim into both the prepared request and the bound. (b) checked
whether the low-level decoder substitutes the requested value when the header
is absent: it does not (`client-low_level.adb:5813`, `:7220`). (c) checked
whether the payer clause could be what fires instead: no, RustFS sends no
`x-amz-request-charged`, so `Returned_Payer /= "requester"` holds. (d) checked
the model for a `required` marker on `VersionId`: none. (e) checked whether
strict echo is needed for the stated safety goal (never accept bytes of a
different generation): rejecting only a present-and-different value keeps the
`*-mismatch` socket cases failing and accepts the AWS-shaped omission, as
`review/baseline-rustfs.md` section 7 proposes. (f) `git log -S
Get_Object_Response_Bound` shows the predicate arrived in `f4cabde`
(2026-08-30, "GetObject responses are not bound to requested versions"), after
the real-server corpus's `versionId=null` case (`7d2d4c4`, 2026-08-22), and
its diffstat touched only the socket corpus, consistent with the baseline
investigation's finding that no real-server run gated the change.

---

### CLIENT-OBJECTS-2: Put/Get/DeleteObjectTagging reject every successful response that omits `x-amz-version-id`, even with no version requested

**Location:** `src/flyology-object_storage-client-objects.adb:7177-7211`
(`Tagging_Version_ID`); callers `:7421-7423` (PutObjectTagging, `Success :=
Status = 200`), `:7669-7671` (GetObjectTagging, `Status = 200`),
`:7960-7962` (DeleteObjectTagging, `Status = 204`). Every public tagging entry
point reaches it: the `Tagging_Outcome` convenience functions (`:1438-1482`,
`:1512-1552`, `:1582-1621`) call the parameter-record overloads
(`:1407-1436`, `:1484-1510`, `:1554-1580`), which wait on the composable
operations; the composable constructors/procedures (`:7534-7554`,
`:7781-7800`, `:8072-8091`, `:8801-8882`) drive the same `Complete_*_Child`.

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-client-objects.adb:7177-7194`
```ada
   function Tagging_Version_ID
     (Response  : HTTP_Client.Response;
      Requested : US.Unbounded_String;
      Success   : Boolean) return String
   is
      Count : constant Natural :=
        HTTP_Client.Header_Count (Response, "x-amz-version-id");
      function Text_Safe (Value : String) return Boolean is
        ...
   begin
      if Count > 1 or else (Success and then Count /= 1) then
         raise Low_Level.Invalid_Response with
           "invalid object tagging version header multiplicity";
      elsif Count = 0 then
         return "";
      end if;
```
On a success status `Count = 0` raises; the `Count = 0` branch is reachable
only for rejections. Unlike CLIENT-OBJECTS-1 the demand is unconditional: it
fires even when the caller sent no `versionId` (`Requested` is consulted only
for the later mismatch test at `:7203-7204`).

`src/flyology-object_storage-client-objects.adb:7416-7433` (Put; Get at
`:7664-7681` and Delete at `:7955-7972` are the same shape)
```ada
            Item.Final_Result := Normalize_Put_Object_Tagging_Response
              (Low_Level.Decode_Put_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Tagging_Version_ID
                    (Response, Item.Requested_Version_ID,
                     HTTP_Client.Status (Response) = 200),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Object_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
```

The model marks the header optional: `review/baseline/service-2.json`
`PutObjectTaggingOutput` = `{VersionId: header x-amz-version-id}` with no
`required`; `GetObjectTaggingOutput.required = ["TagSet"]` only;
`DeleteObjectTaggingOutput` has no `required`. The low-level decoder this
value is fed to accepts an empty version
(`src/flyology-object_storage-client-low_level.adb:12379-12383` validates only
a nonempty value) and its spec says `@param Version_ID Optional selected
object version response header` (`client-low_level.ads`,
`Decode_Put_Object_Tagging_Response`). The architecture document promises the
opposite of the code: `docs/architecture/client-objects.md:100-101`: "All
three preserve the optional response version ID and structured S3 errors."

Observed on a real server: `review/baseline-rustfs.md` section 8 records the
verbatim RustFS reply to the corpus's `PUT …?tagging` (`HTTP/1.1 200 OK`,
`x-request-id`, `x-amz-request-id`, `content-length: 0`, no
`x-amz-version-id`) and the resulting `INVALID_RESPONSE : PutObjectTagging
response is invalid or exceeds the XML limit`, which is the message
`Raise_Object_Tagging_Exchange_Failure` (`:208-212`) produces for
`HTTP_Result = Response_Invalid`. The corpus call is
`Client_Objects.Put_Tags (HTTP, Origin, Bucket, Key, Wanted, Identity,
Timeout => 30.0)` (`tests/src/s3_implementation_corpus.adb:1629-1632`), i.e.
no version requested. The in-repo server always emits the header
(`src/flyology-object_storage-server-s3_applications.adb:15846-15854`,
`Set_Version_Header` falls back to `"null"`), so the memory-server CI corpus
cannot observe this either.

**Failure scenario:** the caller runs `Client.Objects.Put_Tags (…, Tags)`
(or `Get_Tags`, `Delete_Tags`, or the composable forms) against a
never-versioned bucket on RustFS (observed), or on MinIO/SeaweedFS/AWS
(expected to match, given the same servers' HeadObject behaviour in
CLIENT-OBJECTS-1; checkable with `tests/scripts/test-minio.sh` /
`test-seaweedfs.sh` once CLIENT-LOW-1 and CLIENT-OBJECTS-1 no longer stop the
corpus earlier). The server replaces the tags and replies `200 OK` (`204` for
delete) with no version header. `Tagging_Version_ID` raises
`Invalid_Response`; the composable result is `Put_Object_Tagging_Exchange_Failed`
with `Disposition = Object_Tag_Mutation_Outcome_Unknown` and `Failure =
Corrupt_Or_Invalid_Response`; the `Tagging_Outcome` convenience overload
re-raises `Low_Level.Invalid_Response`. The mutation was applied but is
reported as unknown, and the documented reconciliation path (`Get_Tags`) fails
the same way, so the caller cannot reconcile through this API at all.

**Reproduction test sketch:** `tests/src/s3_http_socket_corpus.adb:4331-4333`
already serves `PUT /example-bucket/tag-put-missing?tagging` → `200 OK` with
no version header, `:4361-4362` `GET …/tag-get-missing?tagging` → `200` + tag
XML, `:4386-4388` `DELETE …/tag-delete-missing?tagging` → `204`. Expected for
`Put_Tags (…, "tag-put-missing", Tags, Put_Params)` with empty
`Put_Params.Version_ID`: `Kind = Put_Object_Tagging_Response_Available`,
`Disposition = Object_Tag_Mutation_Completed`, `Failure = No_Failure`,
`Response.Result.Version_ID = ""` (and `Tags_Gotten` with the served tag set /
`Tags_Deleted` for the other two). Actual: `*_Exchange_Failed`,
`Object_Tag_Mutation_Outcome_Unknown`, `Corrupt_Or_Invalid_Response`,
`HTTP_Result = Response_Invalid`. Against a real server: RustFS via
`tests/scripts/test-rustfs.sh`, once the earlier HeadObject stop is fixed
(`review/baseline-rustfs.md` section 8 reached it by header injection).

**Existing coverage:** `tests/src/s3_http_socket_corpus.adb:15091-15258`
(`Require_Invalid_Version (Kind, Missing)`, invoked for every kind at
`:15258`) asserts the defective behaviour for all three operations: the
composable path must yield `*_Exchange_Failed` with
`Object_Tag_Mutation_Outcome_Unknown` / `Corrupt_Or_Invalid_Response` /
`Response_Invalid` (`:15171-15252`), and the low-level path must raise
`Invalid_Response` (`:15110-15169`, the twin predicate at
`client-low_level.adb:12465-12475`). The `Duplicate`, `Mismatch`, `Control`
and `Delete_Control` variants in the same loop remain correct rejections.
`:15040-15070` covers the success path only with the header present
(`convenient-put`/`convenient-get`/`convenient-delete`).
`tests/src/s3_implementation_corpus.adb:1617-1673` (`Require_Object_Tagging`)
exercises all three operations against real servers and is the path that
fails in `review/baseline-rustfs.md` section 8.
`docs/qualification/object-tagging.md:72-74` ("successful responses preserve
the selected `x-amz-version-id` from that same exchange") is ambiguous but is
being read by the tests as "must be present".

**Refutation attempts:** (a) checked whether `Success` could be False on the
real-server path: it is `Status = 200`/`204`, exactly the success status.
(b) checked whether the demand is conditional on a requested version: the
multiplicity test does not consult `Requested`. (c) checked whether the
low-level decoder needs a nonempty version: no (`:12379-12383`,
`Version := To_Unbounded_String (Version_ID)` accepts empty). (d) checked
whether the identical predicate in `Execute_Object_Tagging`
(`client-low_level.adb:12465-12475`) is the one that fired in the baseline:
no, the corpus uses `Client_Objects.Put_Tags`, which runs the composable
operation and this function; the low-level twin is a separate CLIENT-LOW
finding with the same fix direction. (e) `git log -S "invalid object tagging
version header multiplicity"` shows the check arrived in `51c4375`
(2026-08-30, "Object tagging lacks composable qualification evidence"), after
the real-server tagging corpus (`Require_Object_Tagging`) existed; the
in-repo server's `"null"` fallback made it pass in CI.

---

## Areas reviewed with no findings

- **Range binding** (`Bind_Response_Range` `:2327-2377`, `Range_Header`
  `:2311-2325`, `Valid_Range_Request` `:2302-2307`, `Complete_Range_Child`
  `:2502-2587`): a server that ignores `Range` and returns `200` with the full
  body is refused (`Head.Status /= 206` → destination cleared,
  `Invalid_Range_Read_Result`); an oversized body first fails as
  `Response_Body_Too_Large`. Suffix (`bytes=-N`), open-ended and bounded
  requests are resolved against the `Content-Range` total with
  `Resolve_Range` (clamps `Last` to `Size-1`, `First` of a suffix to
  `max(0, Size-N)`) and the returned interval must equal the resolution. The
  low-level `Valid_Content_Range` (`client-low_level.adb:5933-5979`) has
  already required strict digits, `First <= Last < Total` and
  `Last-First+1 = Content-Length` before this layer runs, so the
  `Byte_Count'Value` in `:2356` cannot see a non-digit total. The received
  byte count must equal `Content-Length` (`:2547-2549`) and the ETag must equal
  the `If-Match` value sent (`:2550`); a stale generation is a `412` →
  `Range_Get_Response_Available` with `Has_Resolved_Range = False`.
- **Destination ownership and clearing** for whole/range/torrent reads: the
  pinned `flyology_http` `Finish (…, Destination)` contract (`flyology-http-
  client.ads:1018-1033`) restores the token and "every other result restores
  length zero", so a transport failure, timeout, cancellation or
  `Response_Body_Too_Large` mid-body cannot leave partial bytes readable; the
  Objects layer additionally clears on every invalid or rejected decode
  (`:2413`, `:2433`, `:2444`, `:2536`, `:2555`, `:2565`, `:2580`,
  torrent `:5361-5504`). Error bodies written into the destination before the
  status is known are consumed as the S3 error payload
  (`Buffer_Text` `:2410`, `:2533`) and then cleared.
- **Non-replay of mutations**: `Conditional_Put_Operation`, `Delete_Operation`,
  `Delete_Objects_Operation`, `Put_Legal_Hold_Operation`,
  `Put_Retention_Operation`, `Put_Object_Tagging_Operation`,
  `Delete_Object_Tagging_Operation` and `Delete_Object_Annotation_Operation`
  all implement `Operation_Request_Body_Source` and none implements
  `Rewindable_Request_Body_Source`; `flyology_http` replays a streamed body
  only when the source is rewindable (`flyology-http-client.ads:502-506`,
  `:558-562`). The synchronous `Put_Object`/`Put_If_Absent`/`Put_If_Matches`
  source overloads reject a `Rewindable_Request_Body_Source` up front
  (`:690-694`). Source cursors are reset only at `Start_*`
  (`:2020`, `:3740`, `:6127`, `:6668`, `:7046`, `:7513`, `:8051`), so a
  consumed source cannot be re-read within one exchange.
- **Conditional put buffer ownership** (`Start_Put` `:1996-2045`, `Finish`
  `:2198-2220`, `Finalize` `:1984-1994`): validation and signing precede
  `Move_From`; a failed start moves the token back, rolls back the operation
  and clears the prepared request; `Finish` checks `Same_Pool`, moves the
  token back before re-raising a saved exception, matching the spec
  (`.ads:294-305`). `Read_Now` (`:1823-1849`) bounds the copy by
  `Length - Source_Position` and never reads past the detached buffer.
- **Certainty normalizers** for Put (`:1708-1792`), Delete (`:3120-3176`),
  DeleteObjects (`:3456-3511`), tagging (`:7214-7331`, `:7818-7869`),
  legal hold/retention (`:4864-4895`, `:5896-5947`, `:6437-6488`) and
  annotation deletion (`:6730-6830`): admission ≠ `Response_Observed` is
  always `Outcome_Unknown`; only exact modeled status/code pairs are
  conclusive; `Cancelled` + `Not_Admitted` maps to the cancelled-before-
  admission enum. The Put table matches
  `tests/corpora/composable-client/put-certainty.tsv` row for row.
- **Composable state machines** (18 operations, same skeleton:
  `Drive`/`Complete_*_Child`/`Request_Cancellation`/`Finalize`/`Finish`):
  child released exactly once on every path; `Clear_Prepared_Request` is
  guarded by `not Is_Active (Item.Child)` wherever the child may still be
  running; `Response_Limit_Exceeded` from the bounded sinks becomes
  `Response_Sink_Failed` with the pre-Finish admission; saved exceptions are
  re-raised only from `Finish` after `Consume`; restart requires the same
  `HTTP`/`Destination`/`Cancellation` owners (`Program_Error` otherwise).
- **Synchronous `Get_Whole` (`Whole_Get_Outcome` overload, `:889-978`)**:
  requires `200`, a strong quoted ETag and a present `Content-Length`,
  rejects `Content-Length > Maximum` before reading (`Response_Too_Large`, as
  documented at `.ads:3232-3233`), reads at most `Maximum` bytes and requires
  the received length to equal `Content-Length`. The `Response` local is a
  `Limited_Controlled` lease (`flyology-http-client.ads:1327-1333`), so the
  early `raise` paths release it.
- **Entity-tag validation** (`Valid_Exact_Entity_Tag` `:96-119`): quoted,
  no inner `"`, characters 0x21/0x23-0x7E/0x80-0xFF; weak (`W/`) and unquoted
  tags are refused for `If-Match` inputs, matching the "strong opaque"
  wording of the spec; identical to the low-level acceptance set.
- **ListObjects v1 marker derivation** (`:391-416`): `NextMarker` is preferred,
  the last key is used only without it, both are URL-decoded exactly when the
  page carries `EncodingType=url`, and a truncated page with neither raises
  `Invalid_Response` rather than looping.
- **`Timestamp`** (`:83-94`): UTC (`Time_Zone => 0`), slices of the fixed
  `YYYY-MM-DD HH:MM:SS` image produce `YYYYMMDDTHHMMSSZ`.
- **`Apply_Complete_Put_Options`** (`:542-671`): metadata, tags and write
  conditions are validated before any request is built; a checksum requires
  `Full_Object_Checksum` with a nonempty value; user metadata is copied
  1-based over `User.Length`; `Expires` goes through `IMF_Dates.Image`.
- **HeadObject sink** (`Write` `:2906-2918`): any body octet on a HEAD is
  refused and reported as `Response_Sink_Failed`.

## Observations not counted

- `Normalize_Put_Response` (`:1708-1792`) treats every modeled rejection not
  in its table (for example `404 NoSuchKey`, `400 BadDigest`, `400
  EntityTooLarge`, `403 SignatureDoesNotMatch`) as `Outcome_Unknown` with
  `Failure = Corrupt_Or_Invalid_Response`. This is the documented policy of
  `tests/corpora/composable-client/put-certainty.tsv` ("status alone does not
  prove semantic rejection"), conservative rather than wrong, but the
  `Failure` label misdescribes a well-formed S3 error and forces a
  reconciliation read after, e.g., a `Put_If_Matches` on an absent key.
  (AWS returning `404 NoSuchKey` for `If-Match` on a missing key: from memory,
  unverified.)
- `Normalize_Get_Object_Torrent_Response` (`:5200-5210`) sets
  `Failure => No_Failure` for every complete response, including `404
  NoSuchKey` and `500 InternalError`, whereas the ACL, attributes, tagging,
  legal-hold and retention normalizers map those to `Not_Found` /
  `Unavailable_Or_Retryable`. `tests/src/s3_get_object_torrent_socket_corpus.
  adb:703-706` asserts the current `No_Failure` for a `404`, and the
  `No_Failure` enum text ("Successful or conclusively failed condition")
  admits it, so this is an inconsistency rather than a contract breach.
- Whole/range reads bound the *entire* response body, error XML included, by
  the destination capacity (`.ads:442-443`); a small destination therefore
  reports a large `NoSuchKey` error body as `Response_Too_Large` instead of a
  typed rejection. Documented; noted because it hides the S3 error code from
  callers using tight buffers.
- `Failed_Reason` maps `Response_Body_Too_Large` to `Response_Too_Large` for
  reads and listings, while the mutation normalizers override it to
  `Corrupt_Or_Invalid_Response` (`:1805-1807`, `:3194-3196`, `:3529-3531`,
  `:4951-4957`, …). Only the bounded-buffer reads can actually receive that
  HTTP result, so the inconsistency is unobservable today.
- `Bind_Response_Range` rejects `Content-Range: bytes a-b/*`; the low-level
  validator rejects it first and S3 always sends the total, so no reachable
  effect.
- With a delimiter, the v1 marker fallback uses the last `Contents` key; a
  server that omits `NextMarker` on a delimiter listing (AWS always sends it,
  from memory, unverified) would either raise `Invalid_Response` (no keys) or
  re-list prefixes between the last key and the real cut-off. Low confidence,
  server-deviation only.
- `Get_Object_ACL` and `Delete_Object_Annotation` `Singleton_Header`
  (`:4980-4998`, `:6924-6944`) treat an empty `x-amz-request-id:` or
  `x-amz-id-2:` value as an invalid response; no server observed sends an
  empty id header.
- SigV4 timestamps are taken at `Start_*`; a deadline longer than the SigV4
  skew window could expire the signature before admission under a saturated
  client pool. Policy, not a defect.
- `docs/qualification/get-object.md:11-12`, `head-object.md:10-11` and
  `get-object-attributes.md:41-42` document the strict-echo requirement that
  CLIENT-OBJECTS-1 shows is not satisfiable against real servers; the
  attributes variant lives in `Low_Level` (CLIENT-LOW) and was not reviewed
  here.
- `Delete_Object_Annotation`/`List_Annotations` (annotation extension, not in
  the pinned S3 model) were reviewed only for state-machine consistency, not
  wire conformance.
