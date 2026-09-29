# WIRE consolidation block

## Index rows

| WIRE-1 | P1 | C0-control byte in an accepted key makes every listing without `encoding-type=url` answer 500 | `src/flyology-object_storage-s3-xml.adb:228-234` | `repro_wire_1` |
| WIRE-1b | P2 | Non-UTF-8 key produces a 200 listing whose body is not the UTF-8 it declares | `src/flyology-object_storage.adb:479-490` | `repro_wire_1b` |
| WIRE-2 | P2 | Entity-tag list parser rejects RFC-valid empty list elements as `Invalid_Request` | `src/flyology-object_storage.adb:182-186` | `repro_wire_2` |
| WIRE-3 | P2 | Range field whose unit is not `bytes` is answered 400 instead of ignored | `src/flyology-object_storage-server-s3_applications.adb:16839-16847` | `repro_wire_3` |
| WIRE-4 | P1 | Key containing CR is silently reported as a different key by unencoded listings | `src/flyology-object_storage-s3-xml.adb:228-234` | `repro_wire_4` |

## Totals row

| WIRE | 0 | 2 | 3 | 5 | WIRE-1b added by the verifier as a sibling of WIRE-1, counted separately |

## Area section

## WIRE: wire core, XML boundary, request targets, byte ranges, IMF dates, root validators (WIRE-1, WIRE-1b, WIRE-2 .. WIRE-4)

The area covers `src/flyology-object_storage.ad?`, `-s3-wire_core.ad?`, `-s3-xml.ad?`, `-s3-xml_writers.ad?`, `-s3-strict_xml_codecs.ad?`, `-s3-requests.ad?`, `-s3-core.ad?` and `-s3-imf_dates.ad?`, with the listing serializers in `-s3-listings.adb` and the request handlers in `src/flyology-object_storage-server-s3_applications.adb` read to establish reachability.

### WIRE-1: A C0-control byte in an accepted object key makes every listing without `encoding-type=url` answer 500

**Severity:** P1 (the discovery report also said P1).

**Location:** `src/flyology-object_storage-s3-xml.adb:228-234` (`Escape`) and `:252-253` (`Escape_Text`); key contract at `src/flyology-object_storage.ads:672-675` and `src/flyology-object_storage.adb:479-490`; percent decoding and the only key gate at `src/flyology-object_storage-s3-requests.adb:62-88` and `:171-173`; serializer at `src/flyology-object_storage-s3-listings.adb:1033-1034`; the `Encoded` no-op at `src/flyology-object_storage-server-s3_applications.adb:10657-10660`, repeated at `:10793`, `:10960` and `:11200`; the narrow local handler at `:10763-10768` and the catch-all at `:18056-18066`.

**Repro:** `tests/repros/src/repro_wire_1.adb`, exit status 1, four failed expectations.

**What is wrong:** `Valid_Object_Key` accepts every non-NUL byte, so a key holding U+0001 is stored and stays individually addressable, but `XML.Escape` raises `XML_Error` for every byte below 32 except TAB, LF and CR, and `Escape_Text` is the only text escaper the listing serializers use. Serializing a page that contains the key therefore raises inside `Listings.Serialize_*` before `Apps.Respond` is reached, and the handler's catch-all turns it into 500 InternalError. ListObjects v1, ListObjectsV2 and ListObjectVersions for that bucket page fail for every client that does not send `encoding-type=url`, deterministically, until the key is deleted; ListMultipartUploads and ListParts use the same `Encoded` shape. DeleteObjects cannot clean up: a request document carrying the byte raw or as `&#1;` is rejected 400 MalformedXML by the crate's own `Test_Valid_Chars`, so only `DELETE /bucket/a%01b` removes it. The pinned botocore model's `EncodingType` shape documents that an object key can contain any Unicode character and that the parameter is optional, so the keys themselves are valid input.

**Notes:** `aws-cli` sends `encoding-type=url` on every listing and never reaches it, which is why the verifier kept P1 rather than P0; boto3 and the Flyology client's own default listing calls do not send it. No existing test asserts the wrong behaviour, so no test needs changing; `tests/src/object_storage_test_cases.adb:9223-9238` asserts only that the escaper must raise for NUL. A fix needs an externally visible maintainer decision between three options: narrow `Valid_Object_Key` to reject C0 controls, which changes a documented `.ads` contract and rejects keys AWS accepts; percent-encode unescapable bytes in the listing serializers regardless of `EncodingType`, which changes response bytes; or map the failure to a defined 4xx. WIRE-1b and WIRE-4 are siblings that share the same escaper asymmetry.

---

### WIRE-1b: A key with a non-UTF-8 byte produces a 200 listing whose body is not the UTF-8 it declares

**Severity:** P2 (the discovery report listed this only as a secondary effect of WIRE-1 and assigned no severity; the verifier raised it to a distinct finding because the mechanism is silent success rather than 500).

**Location:** `src/flyology-object_storage.adb:479-490` (no UTF-8 requirement in the key contract); `src/flyology-object_storage-s3-xml.adb:228-234` (`Escape` rejects only bytes below 32); existing assertion that the crate's own reader must refuse such a document at `tests/src/object_storage_test_cases.adb:9219-9221`.

**Repro:** `tests/repros/src/repro_wire_1b.adb`, exit status 1, two failed expectations.

**What is wrong:** Because the key contract admits arbitrary non-NUL bytes and the escaper guards only the C0 range, a key containing a byte that is not valid UTF-8 is copied verbatim into a listing whose XML declaration says `encoding="UTF-8"`. The server answers 200 and the response passes its own framing checks, but the document is not well formed: every conforming parser, including this crate's `S3.XML.Parse`, rejects the whole page, so the client sees a parse failure rather than a server error and cannot tell which key caused it. It is deterministic and confined to buckets holding such a key, and `encoding-type=url` avoids it. The pinned botocore model describes keys as Unicode and responses as UTF-8 encoded, and a raw `0xFF` is neither.

**Notes:** Only a hand-built signed request can create the key, because botocore and every SDK that encodes keys from Unicode strings cannot emit a lone `0xFF`; that input unusualness is why the severity is P2 even though the consequence is worse than WIRE-1's. No existing test asserts the wrong behaviour. A fix shares WIRE-1's maintainer decision: whether `Valid_Object_Key` gains a UTF-8 requirement, which is an `.ads` contract change, or the serializers escape unrepresentable bytes unconditionally. Counted as a separate finding from WIRE-1, not as a duplicate.

---

### WIRE-2: The entity-tag list parser rejects RFC-valid empty list elements as `Invalid_Request`

**Severity:** P2 (the discovery report also said P2).

**Location:** `src/flyology-object_storage.adb:182-186` (element at end of field), `:197-201` (element that is neither `W/` nor a quote), `:235-249` (`Valid := True` only when the field ends after a tag); consumers `Evaluate_Object_Write_Conditions` at `:250-275`, `Valid_Object_Read_Entity_Tag_Condition` at `:278-288` and `Evaluate_Object_Read_Conditions` at `:298-336`; server admission at `src/flyology-object_storage-server-s3_applications.adb:16706-16718`; contract at `src/flyology-object_storage.ads:126-130`.

**Repro:** `tests/repros/src/repro_wire_2.adb`, exit status 1, nine failed expectations.

**What is wrong:** `Read_Entity_Tag_List` sets `Valid` only when the field ends immediately after a quoted tag, so any empty list element, whether a trailing comma, a leading comma or `",,"` between two tags, makes the whole field `Invalid_Request`. The server turns that into 400 InvalidArgument for HeadObject and GetObject conditions and into `Invalid_Request` for PutObject write conditions, instead of evaluating the request against the tags that are present. RFC 9110 section 5.6.1 defines the recipient list form `[ element ] *( OWS "," OWS [ element ] )` and section 5.6.1.2 requires a recipient to parse and ignore a reasonable number of empty list elements, so a field a compliant intermediary may legitimately produce is answered 400 rather than 200 or 412. It is deterministic and affects only recipients, since the RFC forbids senders from generating an empty element.

**Notes:** The verifier could not settle S3's own tolerance: the pinned model types `IfMatch` as an unconstrained header string, and no live server or MinIO run was made, so a maintainer may prefer to match S3 rather than the RFC. That is the only open question; the RFC statements above are cited from memory and were marked unverified. No existing test pins the current rejection: `tests/src/object_storage_test_cases.adb:3763-3765` asserts a valid list with HT and a weak tag, `:3770-3772` rejects `*, "etag"` and `:3773-3775` rejects an oversized field. The fix is local, needs no new public constant or contract change, and cannot unbound the parser because the field is already capped by `Maximum_Condition_Length` and the loop by `Remaining_Items`.

---

### WIRE-3: A Range field whose unit is not `bytes` is answered 400 instead of being ignored

**Severity:** P2 (the discovery report listed the Range policy under observations not counted and handed disposition to the server area; the verifier counted the unrecognized-unit case as a finding because RFC 9110 states a MUST there rather than a MAY, and nothing in the repository documents the 400).

**Location:** `src/flyology-object_storage-server-s3_applications.adb:16839-16847` (HeadObject) and `:17226-17234` (GetObject), the only two consumers of the classification; parser contract at `src/flyology-object_storage-s3-core.ads:172-178`, multi-range rejection documented at `:174-176`; parser-level test coverage at `tests/src/object_storage_test_cases.adb:8787-8794`; documentation at `docs/compatibility/s3.md:736-737` and `:907`.

**Repro:** `tests/repros/src/repro_wire_3.adb`, exit status 1, three failed expectations.

**What is wrong:** `Parse_Range_Header` folds every shape it cannot serve into one `Malformed_Range` status, and both server call sites answer 400 InvalidRequest for all of them. For an unrecognized range unit RFC 9110 section 14.2 requires the field to be ignored and the representation returned normally, so a client sending `Range: items=0-1` gets 400 here. The same 400 covers multi-range, which is a deliberate parser decision documented in `core.ads:174-176` but whose server mapping is documented nowhere; `curl -r 0-1,4-5` is the realistic stock client that reaches it. The behaviour is deterministic and applies to HEAD as well as GET. Both external facts, the RFC 9110 requirement and the belief that AWS S3 returns 200 with the whole object for Range fields it cannot use, are recorded by the verifier as from memory and unverified; no live S3, MinIO or RustFS server was run.

**Notes:** No test asserts the server's 400: a repository-wide grep for "Range header is malformed" finds no test, and the compatibility matrix documents only the supported shapes. Two maintainer decisions are needed and neither should be taken in passing: whether `Range_Parse_Status` gains a third value distinguishing "ignore this field" from "reject this request", which is a public enumeration change in a SPARK-proved `.ads`, and which of the remaining malformed shapes should be ignored rather than rejected, which should be pinned against a live S3 or the pinned MinIO image rather than from memory. The inverted range `bytes=5-1` is a separate case that currently parses and yields 416 with `Content-Range: bytes */10`; it was not checked against any real server and is not counted.

---

### WIRE-4: A key containing CR is silently reported as a different key by every listing without `encoding-type=url`

**Severity:** P1 (the discovery report named the mechanism in one line as a secondary effect of WIRE-1 with no severity and no repro; the verifier scored it above WIRE-1b because the key is reachable from a stock SDK).

**Location:** `src/flyology-object_storage-s3-xml.adb:228-234`, where `Escape` exempts `Character'Val (13)` from the C0 rejection; `src/flyology-object_storage-s3-listings.adb:1033-1034`, where `Element` applies only `Escape_Text`; key contract at `src/flyology-object_storage.adb:479-490`; percent decoding at `src/flyology-object_storage-s3-requests.adb:73-77`; existing listing coverage at `tests/src/s3_http_socket_corpus.adb:3129-3292`.

**Repro:** `tests/repros/src/repro_wire_4.adb`, exit status 1, one failed expectation.

**What is wrong:** `XML.Escape` deliberately allows TAB, LF and CR through unescaped, which is correct for arbitrary text but wrong for a key, because XML 1.0 requires a parser to normalize a literal CR in character data to LF before handing it to the application. A key stored as `a\rb` is therefore reported by ListObjects v1, ListObjectsV2 and ListObjectVersions as `a\nb` whenever `encoding-type=url` is absent. The server returns 200, the document is well formed, and nothing reports an error; the client gets a key it cannot address, and a subsequent GET, HEAD or DELETE of `a%0Ab` answers 404. The same substitution corrupts a `NextMarker` derived from such a key, so a paginating client can skip or repeat entries. It is fully deterministic and reachable from a stock SDK, because botocore percent-encodes a key containing `\r` as `%0D`. The repro confirms the normalization empirically through the crate's own `S3.XML.Parse`, so the claim does not rest on the verifier's memory of the XML specification.

**Notes:** Not P0 because no stock client rejects the response and there is no data loss; the object remains stored under its real key and reachable by anyone who knows it. No existing test asserts the wrong behaviour. The fix is narrower than WIRE-1's and needs no contract change if it is confined to the listing serializers, emitting `&#13;` and, for symmetry, `&#9;` and `&#10;` for the characters XML normalization would alter; whether that escaping applies to every `Escape_Text` caller or only to key-bearing elements is a maintainer decision about the crate's response bytes.

---

## Coverage evidence: WIRE

- `Wire_Core.Parse_Natural` and `Parse_Byte_Count`: the overflow guard `Result > (T'Last - Digit) / 10` at `src/flyology-object_storage-s3-wire_core.adb:16-19,35-38` is exact for every digit, and the same guard in `Core.Parse_Decimal` at `src/flyology-object_storage-s3-core.adb:86-90`; measured, `0` and `007` are accepted, `+1`, `-1`, `" 1"`, `"1 "` and the empty string are rejected, and values above the target's range are rejected, matching the HTTP `1*DIGIT` production.
- `Wire_Core.Parse_Boolean` and `Valid_Base64` canonical padding-bit tables; every caller passes 16, 32 or an algorithm digest size, satisfying the precondition.
- `Core.Parse_Range_Header` length gate, case-insensitive unit, OWS handling, `bytes=-` and `bytes=-0`; `Resolve_Range` for all four kinds including the last-position clamp and `Byte_Count'Last` operands; the proved postcondition matches the GNATdoc.
- `Core.Multipart_Part_Count`, `Valid_Multipart_Plan`, `Valid_Completion_Order`, `Valid_Consecutive_Completion_Order`, `Can_Transition`, `Valid_Part_Size`, `Valid_Listing_Continuation_Syntax`.
- `Requests.Parse_Target`, `Decode` and `Valid_Escapes`: the 8192 gate, strict `%XX`, `+` as a literal, `#` rejection and the 1024-byte decoded key at the bound; measured classification of `/`, `//`, `///`, `/bkt`, `/bkt/`, `/bkt//`, `/bkt/.`, `/bkt/..`, `/bkt/%2e%2e/x`, `/./`, `/../`, `%2F` inside a key, `/%62kt/k`, `/bkt/k#frag` and a bare `?acl` is correct for S3, which treats keys as opaque and performs no dot-segment resolution.
- `IMF_Dates.Parse` and `Image`: measured weekday congruence, impossible and leap dates, second 60 normalization, and rejection of RFC 850, asctime, `0` and `-1`, all matching the deliberately non-generic contract at `src/flyology-object_storage-s3-imf_dates.ads:1-3,16-19`; the conditional-date path that RFC 9110 does require to accept all three formats does accept all three at `src/flyology-object_storage-s3-object_reads.adb:84-124`.
- `XML.Parse` DOCTYPE, processing-instruction and entity rejection, `Test_Valid_Chars`, depth, element, text and document limits with exact at-bound semantics, XMLAda parser-state release on both paths, BOM handling, and `Close` on every path; `XML.Escape`'s six-times expansion bound and attribute versus text escaping sets.
- `XML_Writers` state machine and limits; `Strict_XML_Codecs` root name, unknown member, duplicate singleton, collection and attribute-count limits, required-member check, `Valid_ISO_8601_Timestamp` and `Valid_Integer`.
- Root validators: `Valid_Bucket_Name` character, adjacency, prefix and IPv4 rules, `Looks_Like_IPv4`, `Starts_With` and `Ends_With` slice bounds, `Listing_Matches_Prefix`, `Valid_Object_Delete_ETag_Condition`, the read, write, copy and delete condition precedence rules, `Valid_Tag_Text`, `Valid_Object_Metadata` budgets, `Valid_Object_Annotation_Name` and `Merge_Bucket_Versioning`.
- Just-outside consumers: `max-keys`, `max-uploads`, `max-parts`, `partNumber` and `part-number-marker` range-check before the subtype conversion, the guarded `'Value` uses in `s3_applications.adb:2312-2316` and `client-objects.adb:2374-2376`, and `flyology_http`'s rejection of raw target bytes at or below 32, 127 and above 127, which keeps `Send_Error`'s `Escape_Text (Target_Text)` from raising inside the catch-all.
- Verifier measurements with no finding: `max-keys=0`, `1000` and `00001000` answer 200 and `1001`, `-1`, `+1` and a twenty-digit value answer 400, which is the documented `docs/compatibility/s3.md:863` contract implemented at `src/flyology-object_storage-s3-listings.adb:105-121`; the bare query key `?acl` is accepted and `?zzz` rejected, which is the documented policy at `docs/compatibility/s3.md:581-582` and `s3_applications.adb:6659-6663`; Range shapes other than an unrecognized unit are classified and answered as documented.

## Observations not counted: WIRE

- `max-keys` above 1000 is rejected with 400 where AWS is believed to clamp to 1000, and `max-uploads=0` is rejected while `max-keys=0` is accepted (`src/flyology-object_storage-s3-multipart_uploads.adb:125-142`); both are policy values inside a documented range.
- `Listing_Follows_Cursor` applies the exclusive cursor to the projected key, so a user-supplied marker strictly inside a collapsed group omits the CommonPrefixes entry; documented at `src/flyology-object_storage.ads:366-368`, and AWS behaviour is unverified.
- `Valid_Bucket_Name` rejects the suffix `-an` (`src/flyology-object_storage.adb:452`) with no authority recorded near the declaration, which `.claude/rules/decision-authority.md` asks for; it only over-restricts bucket names.
- `IMF_Dates` is canonical-only by design, so `Expires` values in RFC 850 or asctime form and the cache-busting `0` and `-1` are rejected at `s3_applications.adb:4794`; current AWS handling is unverified.
- `XML.Escape` allocates a stack buffer of six times the value length (`xml.adb:218`); server-reachable inputs are bounded to roughly 96 KiB per call.
- `XML.Parse` funnels every non-`XML_Error` exception raised inside a receiver into `XML_Error` (`xml.adb:203-207`) and `Strict_XML_Codecs.Parse` relabels it `Malformed_Document`, so a genuine `Program_Error` or `Storage_Error` is reported as 400 MalformedXML; diagnostics only.
- XMLAda honours in-document `encoding=` declarations and transcodes to UTF-8, so a body declaring ISO-8859-1 with UTF-8 key bytes yields a mojibake key; standards-conformant, and the sender chose the declaration.
- `Read_Entity_Tag_List` treats `""` as matching an empty stored tag (`src/flyology-object_storage.adb:142-146`); unreachable because stored tags are nonempty.
- `Parse_Target` percent-decodes the bucket segment, so `/%62ucket/` resolves; harmless, and AWS behaviour is unverified.
- `HTTP_Last_Modified` (`s3_applications.adb:1836-1858`) goes through `Duration` and `Ada.Calendar`, so it is bounded by year 2262; `Modified` comes from the backend clock, not from a peer.
- Virtual-hosted addressing is outside the documented path-style claim (`docs/compatibility/s3.md:473`), so a client configured for virtual-host style gets NoSuchBucket or 400 rather than a diagnostic naming the cause.
- The remaining bespoke query parsers for `tagging`, `annotations`, `attributes` and `object_reads.Parse_Query` were only sampled through the shared decode pattern; no live S3, MinIO or RustFS behaviour was exercised in this area.
- Harness caveat for later work, not a defect: `Repro_S3_Server.Signed_Request` signs the same path string it puts on the wire, while the server percent-decodes the wire path before signing (`src/flyology-object_storage-s3-sigv4_verification.adb:309-310,420-423`), so a wire path carrying a percent escape needs the local `Signed_Wire` helper that `repro_wire_1`, `repro_wire_1b` and `repro_wire_4` each carry.
