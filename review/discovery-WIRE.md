# Correctness discovery: WIRE (SPARK wire core, XML boundary, request targets, byte ranges, IMF dates, root validators)

Scope: read in full -- `src/flyology-object_storage-s3-wire_core.ad?`,
`-s3-xml.ad?`, `-s3-xml_writers.ad?`, `-s3-strict_xml_codecs.ad?`,
`-s3-requests.ad?`, `-s3-core.ad?`, `-s3-imf_dates.ad?`,
`src/flyology-object_storage.ad?`, `-s3.ads`, `docs/architecture/spark-coverage.md`,
`tools/prove.sh`, `tools/flyology_object_storage_proof.gpr`. Read in part, to
establish reachability of the boundary subprograms --
`src/flyology-object_storage-server-s3_applications.adb` (lines 600-660,
1768-1880, 2190-2320, 2490-2640, 4160-4215, 6805-6840, 10648-10672,
12740-12830, 15300-15380, 16520-16960, 17056-17075, 17820-17870,
18030-18068), `src/flyology-object_storage-s3-listings.adb` (105-125,
220-235, 487-500, 605-622, 990-1075), `-s3-multipart.adb` (56-200,
1238-1270), `-s3-multipart_uploads.adb` (125-142, 231-243), `-s3-versions.adb`
(125-145), `-s3-object_reads.adb` (35-200), `-s3-object_lock.adb` (112-201,
455-545), `-s3-lifecycle.adb` (491-500), `-s3-deletions.adb` (360-385),
`-s3-sigv4_encoding.adb` (1-46), `-s3-errors.adb` (132-143),
`src/flyology-object_storage-client-objects.adb` (2300-2400),
`-client-transfers.adb` (1288-1306, 1440-1500), `-client-low_level.adb`
(895-965, 1110-1125, 5055-5085, 13540-13600). Dependencies consulted read-only:
XMLAda 26.0.0 (`sax/sax-readers.adb` 5113-5140, 5505-5530, 5943-6010,
`input_sources/input_sources-strings.adb` Open) and the pinned
`flyology_http` snapshot eb09a80a (`src/flyology-http-server.adb` 612-640,
768-800, 1138-1185; `src/flyology-http-server-routing.adb` 2264-2273).
Reference: `review/baseline/service-2.json` (shapes `ObjectIdentifier`,
`LastModifiedTime`, `EncodingType`, `Expires`, `GetObjectRequest.Range`).
Coverage inspected: `tests/src/object_storage_test_cases.adb` (3694-3875
root validators and conditions; 8405-8895 core rules, IMF dates, ranges,
targets; 9116-9245 XML security and limits), `tests/src/s3_http_socket_corpus.adb`
(2640-2820 ranges, 3129-3292 url-encoded listings), the corpus programs under
`tests/src/s3_*_corpus.adb` that feed DOCTYPE/ENTITY documents, and
`tests/corpora/` (fixture inputs only).

Severity rubric: P0 memory/aliasing unsafety, security (signature bypass,
traversal, secret exposure, authz bypass), data loss/durability, hang or
deadlock, or an interop-breaking protocol violation a stock client/server
rejects; P1 wrong result or unexpected exception on valid input via a
reachable path, or a documented contract (`.ads`, README, compatibility
matrix, qualification doc) violated; P2 edge-case incorrectness, wrong
diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| WIRE-1 | Accepted C0-control object keys make every non-url-encoded listing fail with 500 | P1 | High |
| WIRE-2 | Entity-tag list parser rejects RFC-valid empty list elements as Invalid_Request | P2 | Medium |

---

### WIRE-1: Accepted C0-control object keys make every non-url-encoded listing fail with 500

**Location:** `src/flyology-object_storage.adb:479-490` (`Valid_Object_Key`),
`src/flyology-object_storage-s3-requests.adb:48-90,168-174` (`Decode`, key
validation in `Parse_Target`), `src/flyology-object_storage-s3-xml.adb:228-235`
(`Escape`), `src/flyology-object_storage-s3-listings.adb:1033-1034`
(`Element`), `src/flyology-object_storage-server-s3_applications.adb:10657-10661`
(`Encoded`), `src/flyology-object_storage-server-s3_applications.adb:18056-18066`
(catch-all).

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage.ads:667-670` (contract) and
`src/flyology-object_storage.adb:479-490` (implementation):

```ada
   --  Validate an object key at the storage boundary.
   --  @param Value Candidate object key
   --  @return True for a nonempty key of at most 1,024 bytes without NUL
   function Valid_Object_Key (Value : String) return Boolean;
```

```ada
   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
      for Character_Value of Value loop
         if Character_Value = Character'Val (0) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Object_Key;
```

`src/flyology-object_storage-s3-requests.adb:73-77` (any `%XX` becomes the raw
byte, including `%01`):

```ada
            Byte :=
              16 * Hex_Value
                (Character_At (Value, Positive (Input + 1))) +
              Hex_Value (Character_At (Value, Positive (Input + 2)));
            Result (Positive (Output)) := Character'Val (Byte);
```

`src/flyology-object_storage-s3-xml.adb:228-235` (the only writer used by every
S3 response codec refuses the same bytes):

```ada
         for Item of Value loop
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise XML_Error with "invalid XML character";
```

`src/flyology-object_storage-s3-listings.adb:1033-1034` and
`src/flyology-object_storage-server-s3_applications.adb:10657-10661`:

```ada
   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");
```

```ada
                     function Encoded (Value : String) return String is
                       (if Request.URL_Encoding
                        then Encoding.URI_Encode
                          (Value, Encode_Slash => False)
                        else Value);
```

`src/flyology-object_storage-server-s3_applications.adb:18056-18066`:

```ada
      when others =>
         if Apps.Response (X) /= Apps.Not_Started
           or else Apps.Wire_Response_Started (X)
         then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 500, "InternalError",
               "We encountered an internal error", Target_Text);
         end if;
```

Model: `review/baseline/service-2.json`, shape `EncodingType` (and the
`ListObjectsV2Request.EncodingType` member) documents: "An object key can
contain any Unicode character. However, the XML 1.0 parser can't parse
certain characters, such as characters with an ASCII value from 0 to 10. For
characters that aren't supported in XML 1.0, you can add this parameter to
request that Amazon S3 encode the keys in the response." The parameter is
optional (`location: querystring`, no `required`). AWS S3 is understood to
emit such keys unencoded when the parameter is absent (from memory,
unverified; a MinIO or RustFS run through `tests/scripts/test-*.sh` with
`PUT /b/a%01b` followed by `GET /b?list-type=2` would show what a stock server
does).

**Failure scenario:**

1. A client sends `PUT /example-bucket/a%01b` (botocore percent-encodes a key
   containing U+0001 exactly this way). `flyology_http` admits the target
   because `%01` is a well-formed escape
   (`flyology-http-server.adb:787-796`); `Parse_Target` decodes it to the
   three bytes `a`,`0x01`,`b`; `Valid_Object_Key` returns True; the backend
   stores the object. 200 OK.
2. Any client sends `GET /example-bucket?list-type=2` (or v1
   `GET /example-bucket`) without `encoding-type=url` -- boto3, the Flyology
   client's default listing calls, and every SDK that does not add
   `EncodingType` automatically (aws-cli does add it).
3. The server builds the listing page: `Encoded` returns the raw key,
   `Element ("Key", ...)` calls `Escape_Text`, which raises `XML_Error`
   before `Apps.Respond` is reached.
4. The exception unwinds to the `when others` at line 18056; the response has
   not started, so the client receives `500 InternalError`. Every subsequent
   listing of that bucket page fails the same way until the key is deleted;
   `DeleteObjects` cannot even name the key because `Test_Valid_Chars_Feature`
   makes a request XML containing U+0001 (raw or as `&#1;`) unparsable, so
   only `DELETE /example-bucket/a%01b` removes it. The same rendering path is
   used for ListObjectVersions, ListMultipartUploads and ListParts (`Encoded`
   at lines 10794, 10961, 11201), so an in-progress multipart upload with such
   a key blocks those listings too.

Secondary effects of the same domain/XML mismatch:
- Keys containing `0x0D` are emitted raw; XML end-of-line normalisation on
  the client turns CR into LF, so the client sees a key it cannot address.
- `Valid_Object_Key` does not require UTF-8, so `PUT /b/%FF` is accepted and a
  non-url-encoded listing is then not valid UTF-8; the Flyology client
  (`Test_Valid_Chars_Feature => True`) and expat-based clients reject the
  whole page. The model text "Responses are encoded only in UTF-8" and "any
  Unicode character" define keys as Unicode, not arbitrary bytes.

**Reproduction test sketch:** In-process loopback via
`tests/src/s3_server_harness.adb` with the memory backend:
`PUT /example-bucket/a%01b` (body "x") -> expect 200 (observed 200);
`GET /example-bucket?list-type=2` -> expected: a well-formed page listing the
key (or a defined 4xx if the server chooses to require `encoding-type=url`
for such keys); actual: `500 InternalError`. Unit level:
`Valid_Object_Key ("a" & Character'Val (1) & "b")` = True while
`XML.Escape_Text ("a" & Character'Val (1) & "b")` raises `XML_Error`.

**Existing coverage:** `tests/src/object_storage_test_cases.adb:3721-3726`
asserts keys are opaque and that empty, NUL and >1024-byte keys are rejected;
`:9226-9237` asserts `Escape_Text` raises on NUL; `:8880-8888` asserts a
1024-byte key parses. No test lists a bucket containing a control-character or
non-UTF-8 key. `tests/src/s3_http_socket_corpus.adb:3129-3292` covers
`encoding-type=url` listings only with printable keys.

**Refutation attempts:** (a) Checked whether `flyology_http` rejects the
escape: `flyology-http-server.adb:781-793` rejects raw bytes >127 and nine raw
punctuation characters, and `:1173-1177` rejects raw bytes <=32 and 127, but
any well-formed `%XX` passes, so `%01` reaches `Parse_Target`. (b) Checked
whether the server URL-encodes keys unconditionally: `Encoded` only encodes
when `Request.URL_Encoding` is set. (c) Checked whether `Escape_Text`
tolerates C0 controls: it raises for all except TAB/LF/CR. (d) Checked whether
the catch-all downgrades to a partial response: the page is serialised before
`Respond`, so the 500 path is taken. (e) Checked whether AWS forbids such
keys: the model's `EncodingType` documentation explicitly anticipates them,
so they are valid S3 keys.

---

### WIRE-2: Entity-tag list parser rejects RFC-valid empty list elements as Invalid_Request

**Location:** `src/flyology-object_storage.adb:177-247` (`Read_Entity_Tag_List`),
in particular `:183-186`, `:198-202` and `:235-246`; consumers
`src/flyology-object_storage.adb:250-338` (`Evaluate_Object_Write_Conditions`,
`Valid_Object_Read_Entity_Tag_Condition`, `Evaluate_Object_Read_Conditions`).

**Severity:** P2. **Confidence:** Medium.

**Evidence:**

`src/flyology-object_storage.ads:124-130` and `:630-632` (contract):

```ada
   --  Validate one If-Match or If-None-Match field for an object read.
   --  Weak entity tags are valid syntax; comparison semantics are selected by
   --  Evaluate_Object_Read_Conditions. Oversized fields are rejected.
   --  @param Value Entity-tag condition field value
   --  @return True when Value has valid bounded entity-tag list syntax
```

```ada
   --  Destination validators evaluated against the same publication boundary
   --  that makes a complete object visible. Values use HTTP entity-tag list
   --  syntax; the storage contract remains independent of HTTP request types.
```

`src/flyology-object_storage.adb:183-186` (an element position with no tag
after a comma returns with `Valid = False`) and `:198-202` (a leading comma
is not a `"` and returns with `Valid = False`):

```ada
         Skip_Whitespace;
         if Cursor > Length then
            return;
         end if;
```

```ada
            if Cursor > Length
              or else Character_At (Value, Positive (Cursor)) /= '"'
            then
               return;
            end if;
```

`src/flyology-object_storage.adb:235-246`:

```ada
         Skip_Whitespace;
         if Cursor > Length then
            Valid := True;
            return;
         elsif Character_At (Value, Positive (Cursor)) /= ',' then
            return;
         end if;
         Cursor := Cursor + 1;
         if Remaining_Items = 0 then
            return;
         end if;
         Remaining_Items := Remaining_Items - 1;
```

RFC 9110 section 5.6.1 defines `If-Match = "*" / #entity-tag` with the `#`
list rule whose recipient form is `[ element ] *( OWS "," OWS [ element ] )`,
and section 5.6.1.2 states that a recipient MUST parse and ignore a
reasonable number of empty list elements (from memory, unverified). The
botocore model gives `IfMatch` as an unconstrained header string, so it
neither confirms nor refutes S3's own tolerance.

**Failure scenario:** A client (or a proxy that merges header values) sends
`HEAD /example-bucket/key` with `If-Match: "etag",` (trailing comma), or
`If-Match: "etag",,"other"`, or `If-None-Match: ,"etag"`. The server's
admission at `s3_applications.adb:16704-16712` calls
`Backends.Valid_Read_Entity_Tag_Condition`, which returns False through
`Valid_Object_Read_Entity_Tag_Condition`, and answers 400 instead of
evaluating the (valid) list; the same happens for PutObject
`If-Match`/`If-None-Match` through `Evaluate_Object_Write_Conditions`, which
returns `Invalid_Request` at `:260-261`/`:269-270`. Under the RFC the empty
elements are ignored and the request should be evaluated against `"etag"`.

**Reproduction test sketch:** Unit:
`Valid_Object_Read_Entity_Tag_Condition ("""etag"",")` -- expected True,
actual False; `Evaluate_Object_Read_Conditions (If_Match => """etag"", ",
If_None_Match => "", Has_If_Modified_Since => False, If_Modified_Since => 0,
Has_If_Unmodified_Since => False, If_Unmodified_Since => 0, Entity_Tag =>
"etag", Modified => 0)` -- expected `Success`, actual `Invalid_Request`.
Loopback (`tests/src/s3_server_harness.adb`, memory backend): put an object,
then `HEAD /example-bucket/key` with `If-Match: "<etag>",` -- expected 200,
actual 400.

**Existing coverage:** `tests/src/object_storage_test_cases.adb:3764-3775`
asserts `*, "etag"` and a 16,385-byte field are invalid and a plain quoted tag
is valid; `:3777-3833` cover weak/strong matching and precedence. No test
exercises an empty list element; no test asserts the current 400.

**Refutation attempts:** Checked whether any caller trims trailing commas or
collapses empty elements before calling the domain predicate -- the server
passes `Apps.Request_Header (X, "if-match")` verbatim and the client copies
`Conditions.If_Match` verbatim. Checked whether accepting empties would
unbound the parser -- the field is already capped at
`Maximum_Condition_Length` and `Remaining_Items` bounds the loop, so ignoring
empty elements is safe. Checked whether the `.ads` contract excludes them --
it says "HTTP entity-tag list syntax", which includes them. Could not verify
S3's own behaviour from the model, hence Medium.

---

## Areas reviewed with no findings

- `Wire_Core.Parse_Natural` / `Parse_Byte_Count`: overflow guard
  `Result > (T'Last - Digit) / 10` is exact for every digit; empty and
  non-digit input rejected; leading zeros accepted (consistent with callers).
- `Wire_Core.Parse_Boolean`; `Wire_Core.Valid_Base64`: canonical padding-bit
  tables for `mod 3 = 1` and `mod 3 = 2`, zero-length case; every caller
  passes 16, 32 or an algorithm digest size, satisfying `Pre <= 1_000_000`.
- `Core.Parse_Range_Header`: 7..256 length gate, case-insensitive unit, OWS
  after `=` and at end, single hyphen, `bytes=-`, `bytes=-0` (parsed as
  suffix 0 and made unsatisfiable by `Resolve_Range`), overflow via
  `Parse_Decimal`, non-one string bounds (test 8763-8766).
- `Resolve_Range`: all four kinds, empty object, last-position clamp, suffix
  longer than object, no overflow with `Byte_Count'Last` operands; the
  proved postcondition matches the GNATdoc.
- `Core.Multipart_Part_Count` (Pre guarded by `Valid_Multipart_Plan` at
  `client-transfers.adb:1297-1300`), `Valid_Multipart_Plan`,
  `Valid_Completion_Order`, `Valid_Consecutive_Completion_Order`
  (`Part_Number'Last` guard), `Can_Transition`, `Valid_Part_Size`.
- `Core.Valid_Listing_Continuation_Syntax`: header 70 bytes, even cursor,
  2048-hex-character ceiling equals `Maximum_Listing_Cursor_Bytes`.
- `Requests.Parse_Target` / `Decode` / `Valid_Escapes`: 8192 gate, strict
  `%XX`, `+` literal, `#` rejection, trailing `?`, `//`, `/bucket//` (key
  `/`), `?` inside the bucket segment, 1024-byte decoded key at the bound,
  `Relaxed_Initialization` loop invariants; `Bucket_Name` / `Object_Key` /
  `Query_String` guards; server and client copy-source callers keep the
  synthesised target within 8192 bytes (`client-transfers.adb:1454-1466`,
  `s3_applications.adb:12775-12781`).
- `IMF_Dates.Parse` / `Image`: field layout, month table, Gregorian leap
  rule, `Days_In_Month`, second 60 normalisation, `Metadata_Time` range,
  weekday congruence (`Epoch_Day` = 719162 = 3 mod 7, Thursday; `Image`'s
  `Absolute_Day mod 7` is congruent with `Parse`'s formula), binary search
  invariants, 29-byte postcondition; exhaustive per-year round trip exists
  (test 8499-8560).
- `XML.Parse`: DOCTYPE, PI, internal/external entity and skipped-entity
  rejection (XMLAda invokes `Start_DTD` at `sax-readers.adb:5133` before the
  internal subset is read); `Test_Valid_Chars`; depth/element/text/document
  limits with exact at-bound semantics; XMLAda `Parse` frees parser state on
  both normal and exception paths (`sax-readers.adb:6003-6008`); UTF-8/16/32
  BOM handling in `Input_Sources.Strings.Open`; `Close` on every path.
- `XML.Escape`: 6x expansion bound with the `Natural'Last / 6` guard;
  attribute vs text escaping sets; NUL rejection (test 9226-9237).
- `XML_Writers`: `Started`/`Finished`/`Depth`/`Start_Is_Open` state machine,
  document/depth/element/text limits, namespaced attribute prefix rule.
- `Strict_XML_Codecs`: root name, unknown member, scalar-with-child,
  duplicate singleton, collection and attribute-count limits, namespace
  consistency, required-member check at close, text outside scalars,
  `Valid_ISO_8601_Timestamp` (20..35 bytes, 1..9 fraction digits, offset
  bounds, no out-of-range index), `Valid_Integer` (only a validator; the
  client's `'Value` use is wrapped in a `Constraint_Error` handler at
  `client-low_level.adb:955-967`).
- Root validators: `Valid_Bucket_Name` character, adjacency, prefix/suffix
  and IPv4 rules against the test vectors; `Looks_Like_IPv4`; `Starts_With`
  / `Ends_With` slice bounds; `Listing_Matches_Prefix`;
  `Valid_Object_Delete_ETag_Condition`; `Evaluate_Object_Read/Write/Copy/
  Delete_Conditions` precedence (If-Match over If-Unmodified-Since,
  If-None-Match over If-Modified-Since, weak vs strong comparison, missing
  object rules); `Valid_Tag_Text` count bound at exactly `Maximum`;
  `Valid_Object_Metadata` budgets (12 for `Content-Type`, 36 for `Expires`);
  `Valid_Object_Annotation_Name`; `Merge_Bucket_Versioning` (matches Post).
- Just-outside consumers: `max-keys`, `max-uploads`, `max-parts`,
  `partNumber`, `part-number-marker` all range-check before the subtype
  conversion; `Parse_Directory_Bucket_List_Query`'s `Natural'Value` is inside
  a `Constraint_Error` handler (`s3_applications.adb:2312-2316`); the client's
  `Bind_Response_Range` `Byte_Count'Value` is guarded
  (`client-objects.adb:2374-2376`); `Retention_Deadline` and
  `Parse_Conditional_Date` are guarded and the latter matches the model's
  `rfc822` format for `ObjectIdentifier.LastModifiedTime`; `flyology_http`
  rejects raw bytes <= 32, 127 and > 127 in targets, so `Send_Error`'s
  `Escape_Text (Target_Text)` cannot raise inside the catch-all.

## Observations not counted

- Range policy: `Parse_Range_Header` marks unknown units, multi-range and
  `first > last` as `Malformed_Range`/unsatisfiable and the server answers
  400 (`s3_applications.adb:16840-16844`) or 416. RFC 9110 section 14.2 says
  an origin server MUST ignore a Range field whose unit it does not recognise
  and MAY ignore or reject an invalid ranges-specifier; AWS S3 is believed to
  ignore invalid Range headers and return 200 (from memory, unverified;
  checkable against MinIO/RustFS via `tests/scripts/test-*.sh`). Documented
  as deliberate in `core.ads:173-176`; disposition belongs to the server area.
- `max-keys > 1000` is rejected with 400 (`listings.adb:112-121`) where AWS
  clamps to 1000 (from memory, unverified); `max-uploads=0` is rejected while
  `max-keys=0` is accepted (`multipart_uploads.adb:132-133`). Policy values.
- `Listing_Follows_Cursor` applies the exclusive cursor to the projected key
  (documented at `object_storage.ads:366-368`). For a user-supplied marker or
  start-after strictly inside a collapsed group (marker `a/x`, delimiter `/`,
  keys `a/y`), the `a/` CommonPrefixes entry is omitted; whether AWS emits it
  is unverified. Self-produced NextMarker values are unaffected.
- `Valid_Bucket_Name` rejects the suffix `-an` (`object_storage.adb:452`;
  test 3720 calls it "account namespace suffix"). I could not match it to the
  AWS naming rules I know (`-s3alias`, `--ol-s3`, `.mrap`, `--x-s3`,
  `--table-s3`), and no authority is recorded near the declaration as
  `decision-authority.md` requires. Over-restriction only.
- `IMF_Dates` is canonical-only by design (`imf_dates.ads:1-3`); `Expires`
  values in RFC 850/asctime form or the cache-busting `0`/`-1` are rejected
  at `s3_applications.adb:4794`. Current AWS handling of non-IMF `Expires`
  is unverified.
- `XML.Escape` allocates a `6 * Value'Length` stack buffer (`xml.adb:218`).
  Server-reachable inputs are bounded (raw target, 1024-byte keys, 16 KiB
  documents), so at most ~96 KiB per call; only a client escaping a 16 MiB
  string of its own would need a 96 MiB frame.
- `XML.Parse` funnels every non-`XML_Error` exception raised inside a
  receiver into `XML_Error "malformed S3 XML document"` (`xml.adb:203-207`)
  and `Strict_XML_Codecs.Parse` relabels it `Malformed_Document`; a genuine
  `Program_Error`/`Storage_Error` in a handler is therefore reported as a
  400 MalformedXML. Diagnostics only.
- XMLAda honours in-document `encoding=` declarations and transcodes to UTF-8
  (`sax-readers.adb:5524`); a body declaring ISO-8859-1 with UTF-8 key bytes
  gets a mojibake key. Standards-conformant; the sender chose the declaration.
- `Read_Entity_Tag_List` treats `""` as matching an empty stored tag
  (`object_storage.adb:142-146`); unreachable because stored tags are nonempty.
- `Parse_Target` percent-decodes the bucket segment (`/%62ucket/`); harmless,
  AWS behaviour unverified.
- `HTTP_Last_Modified` (`s3_applications.adb:1836-1858`) goes through
  `Duration` and `Ada.Calendar` (year <= 2399, `Duration'Last` about year
  2262); `Modified` comes from the backend clock, not from a peer.
- Virtual-hosted addressing is outside the documented path-style claim
  (`docs/compatibility/s3.md:473`), so `Parse_Target` classifying `/key`
  as a bucket is by design; a client configured for virtual-host style gets
  NoSuchBucket or 400 rather than a diagnostic naming the cause.
- Not reviewed in depth: the remaining bespoke query parsers
  (`tagging`, `annotations`, `attributes`, `object_reads.Parse_Query`) were
  only sampled through the shared `Decode_Component`/`Decode_ACL_Query_Component`
  pattern and `Multipart.Parse_Query`; generated model descriptors were used
  only through `review/baseline/service-2.json`; no live S3, MinIO or RustFS
  behaviour was exercised.
