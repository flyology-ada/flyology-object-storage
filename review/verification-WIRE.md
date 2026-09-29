# Adversarial verification: WIRE (wire core, XML boundary, request targets, byte ranges, IMF dates, root validators)

Scope verified by reading: `src/flyology-object_storage.ads` (:118-133,
:655-676), `src/flyology-object_storage.adb` (:142-247, :250-338, :479-490),
`src/flyology-object_storage-s3-xml.ads`, `-s3-xml.adb` (:205-253),
`-s3-requests.ads`, `-s3-requests.adb` (:20-185), `-s3-core.ads` (:158-200),
`-s3-core.adb` (:64-100), `-s3-wire_core.ads`, `-s3-wire_core.adb` (:1-80),
`-s3-imf_dates.ads`, `-s3-listings.adb` (:1027-1045),
`-s3-object_reads.adb` (:75-159), `-s3-sigv4.ads`, `-s3-sigv4.adb` (:135-275),
`-s3-sigv4_encoding.ad?`, `-s3-sigv4_verification.adb` (:255-430),
`src/flyology-object_storage-server-s3_applications.adb` (:1705-1750,
:6650-6665, :10645-10800, :10960, :11200, :16695-16860, :17230,
:17966-18066), `docs/compatibility/s3.md` (:575-590, :855-870, :900-935),
`tests/src/object_storage_test_cases.adb` (:3714-3780, :8780-8812,
:9219-9240), and, read-only, the pinned `flyology_http` eb09a80a
(`src/flyology-http-server.adb` :770-800, :1160-1180,
`src/flyology-http-decoded_path_policy.ads`) plus
`review/baseline/service-2.json`.

Harness programs added: `tests/repros/src/repro_wire_1.adb`,
`repro_wire_1b.adb`, `repro_wire_2.adb`, `repro_wire_3.adb`,
`repro_wire_4.adb`. Nothing tracked was modified (`git status --short` shows
only the untracked `review/` and `tests/repros/`). No Docker server was used;
every AWS/MinIO behaviour statement below is explicitly marked unverified.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| WIRE-1 | CONFIRMED | P1 (P1) | `tests/repros/src/repro_wire_1.adb` |
| WIRE-1b | CONFIRMED | P2 (not raised) | `tests/repros/src/repro_wire_1b.adb` |
| WIRE-2 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_wire_2.adb` |
| WIRE-3 | CONFIRMED | P2 (not counted) | `tests/repros/src/repro_wire_3.adb` |
| WIRE-4 | CONFIRMED | P1 (not counted) | `tests/repros/src/repro_wire_4.adb` |

---

### WIRE-1: a C0-control byte in an accepted object key makes every listing without `encoding-type=url` answer 500

**Verdict:** CONFIRMED. Every sub-claim of the discovery entry reproduced,
including the DeleteObjects escape hatch, which the discovery report asserted
without running it.

**Severity:** P1 (discovery also said P1). Not P0: `aws-cli` sends
`encoding-type=url` on every listing and therefore never hits it, so this is
not "an interop-breaking protocol violation that a stock client rejects"; it
is a wrong result (500 on a well-formed request) on input the crate's own
documented `Valid_Object_Key` contract calls valid, reached by any client that
omits `EncodingType` -- boto3 and the Flyology client's own default listing
calls among them.

Verified by reading:

- `src/flyology-object_storage.ads:672-675` documents `Valid_Object_Key` as
  "True for a nonempty key of at most 1,024 bytes without NUL", and
  `src/flyology-object_storage.adb:479-490` implements exactly that: the only
  rejected byte is `Character'Val (0)`.
- `src/flyology-object_storage-s3-requests.adb:62-88` turns any well-formed
  `%XX` into the raw byte, so `%01` reaches `Valid_Object_Key` as `0x01`
  (`:171-173` is the only key gate in `Parse_Target`).
- `src/flyology-object_storage-s3-xml.adb:228-234` raises `XML_Error` for
  every byte below 32 except TAB, LF and CR, and `Escape_Text` (`:252-253`) is
  the only text escaper the listing serializers use
  (`src/flyology-object_storage-s3-listings.adb:1033-1034`).
- `src/flyology-object_storage-server-s3_applications.adb:10657-10660` shows
  `Encoded` is a no-op unless `Request.URL_Encoding` is set; the same shape
  recurs at `:10793`, `:10960` and `:11200` for ListObjectVersions,
  ListMultipartUploads and ListParts.
- The local handler around the v1 listing catches only
  `Listings.Malformed_List_Request`
  (`s3_applications.adb:10763-10768`), so `XML_Error` reaches the outer
  `when others` at `:18056-18066` and becomes 500 InternalError.
- `~/.local/share/alire/releases/flyology_http_0.1.3_eb09a80a/src/flyology-http-server.adb:1172-1177`
  rejects raw target bytes <= 32, and `:780-796` rejects raw bytes > 127 and
  nine punctuation characters, but accepts any well-formed `%XX`. The dot-
  segment policy in `flyology-http-decoded_path_policy.ads` is used only by
  `flyology-http-server-routing.adb`, which the S3 application does not use.

Refutation attempts that failed:

- Looked for a UTF-8 or control-character gate above `Valid_Object_Key`:
  there is none between `Parse_Target` and the backend; `Valid_Object_Key` is
  the whole key contract.
- Looked for a listing-specific escaper that tolerates C0: `Escape_Text` is
  the only one, and `tests/src/object_storage_test_cases.adb:9223-9238`
  asserts it must raise for NUL, so the strictness is deliberate.
- Looked for a narrower handler that would turn this into a 4xx: the
  serialization happens before `Apps.Respond`, so `Apps.Response (X)` is still
  `Not_Started` and the catch-all takes the 500 branch, as the run shows.
- Checked whether AWS forbids such keys: `review/baseline/service-2.json`,
  shape `EncodingType`, documents that "An object key can contain any Unicode
  character. However, the XML 1.0 parser can't parse certain characters, such
  as characters with an ASCII value from 0 to 10", and the parameter is
  optional (`location: querystring`, not required). AWS's own behaviour when
  the parameter is absent is from memory, unverified; the model text
  establishes that the keys themselves are valid.
- Checked the existing suite: `tests/src/object_storage_test_cases.adb:3721`
  asserts `Valid_Object_Key ("../opaque/key")`, `:3723-3727` cover empty, NUL
  and oversized keys, and `:8880` covers a 1,024-byte key, but nothing lists a
  bucket holding a control-character key.

**Repro:** `tests/repros/src/repro_wire_1.adb`. It signs the decoded path and
puts the percent-encoded path on the wire (`Repro_S3_Server.Signed_Request`
signs the same string it emits, and SigV4 canonicalization re-encodes, so a
wire path carrying an escape needs the local `Signed_Wire` helper). It stores
`plain.txt` and `a%01b` in one bucket, checks that GET, HEAD and DELETE of the
control key all work, then asserts that ListObjectsV2, ListObjects v1 and
ListObjectVersions without `encoding-type=url` answer 200 with a page.
It also prints, as notes, the `encoding-type=url` listing, both DeleteObjects
attempts, and the non-UTF-8 key case that WIRE-1b covers.

**Output** (`cd tests/repros && ./run.sh repro_wire_1`, exit status **1**):

```
  -- Valid_Object_Key ("a" & SOH & "b") = TRUE
  -- XML.Escape_Text of the same key raised XML_Error
  -- CreateBucket -> status 200
  ok: CreateBucket is 200
  -- PutObject plain.txt -> status 200
  ok: PutObject of an ordinary key is 200
  -- CONTROL ListObjectsV2 with only ordinary keys -> status 200
  ok: CONTROL: listing a bucket of ordinary keys is 200
  ok: CONTROL: the ordinary key appears in the page
  -- PutObject /wire-one-bucket/a%01b -> status 200
  ok: PutObject of a %01 key is accepted (precondition)
  -- CONTROL GetObject of the %01 key -> status 200
  ok: CONTROL: GetObject of the %01 key returns its body
  -- CONTROL HeadObject of the %01 key -> status 200
  ok: CONTROL: HeadObject of the %01 key is 200
  -- ListObjectsV2 (no encoding-type) -> status 500  <Code>InternalError</Code>
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error</Message><Resource>/wire-one-bucket?list-type=2</Resource></Error>
  FAILED: ListObjectsV2 without encoding-type is 200
  FAILED: ListObjectsV2 without encoding-type returns a listing page
  -- ListObjects v1 (no encoding-type) -> status 500  <Code>InternalError</Code>
  FAILED: ListObjects v1 without encoding-type is 200
  -- ListObjectVersions (no encoding-type) -> status 500  <Code>InternalError</Code>
  FAILED: ListObjectVersions without encoding-type is 200
  -- ListObjectsV2 with encoding-type=url -> status 200
  --   body: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-one-bucket</Name><Prefix></Prefix><KeyCount>2</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><EncodingType>url</EncodingType><Contents><Key>a%01b</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents><Contents><Key>plain.txt</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents></ListBucketResult>
  -- DeleteObjects with a raw U+0001 in the request XML -> status 400  <Code>MalformedXML</Code>
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/wire-one-bucket?delete</Resource></Error>
  -- DeleteObjects with &#1; in the request XML -> status 400  <Code>MalformedXML</Code>
  --   body: <?xml version="1.0" encoding="UTF-8"?><Error><Code>MalformedXML</Code><Message>The XML provided was not well-formed or did not validate against the published schema</Message><Resource>/wire-one-bucket?delete</Resource></Error>
  -- PutObject /wire-one-bucket/h%FF -> status 200
  -- ListObjectsV2 encoding-type=url with the %FF key too -> status 200
  --   body valid UTF-8: TRUE
  --   body: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-one-bucket</Name><Prefix></Prefix><KeyCount>3</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><EncodingType>url</EncodingType><Contents><Key>a%01b</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents><Contents><Key>h%FF</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"415290769594460e2e485922904f345d"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents><Contents><Key>plain.txt</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents></ListBucketResult>
  -- CONTROL DeleteObject of the %01 key -> status 204
  ok: CONTROL: DELETE of the %01 key succeeds
  -- ListObjectsV2 (no encoding-type) with only the %FF key -> status 200
  --   body valid UTF-8: FALSE
  --   body: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-one-bucket</Name><Prefix></Prefix><KeyCount>2</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Contents><Key>h\xff</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"415290769594460e2e485922904f345d"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents><Contents><Key>plain.txt</Key><LastModified>2026-09-07T01:47:26.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass></Contents></ListBucketResult>
  -- DeleteObject of the %FF key -> status 204
  -- CONTROL ListObjectsV2 after the keys are removed -> status 200
  ok: CONTROL: the listing works again once the keys are gone
BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** `Valid_Object_Key` accepts every non-NUL byte, so a key
holding U+0001 is stored and remains individually addressable, but the only
XML text escaper in the crate refuses that byte. Serializing any listing page
that contains the key therefore raises `XML_Error` inside
`Listings.Serialize_*`, before `Apps.Respond` is reached, and the request
handler's catch-all turns it into 500 InternalError. The consequence is that
ListObjects v1, ListObjectsV2 and ListObjectVersions for that bucket page fail
for every client that does not send `encoding-type=url`, deterministically,
until the key is deleted; ListMultipartUploads and ListParts use the same
`Encoded` shape, so an in-flight multipart upload with such a key blocks those
too. DeleteObjects cannot be used to clean up: a request document carrying the
byte raw or as `&#1;` is rejected 400 MalformedXML by the crate's own
`Test_Valid_Chars` parser, so only `DELETE /bucket/a%01b` removes it. `aws-cli`
escapes this by always sending `encoding-type=url`; boto3 and the Flyology
client's default listing calls do not. No existing test asserts the wrong
behaviour, so no test needs changing. A fix needs a maintainer decision that is
externally visible: either the storage boundary narrows (reject C0 controls in
`Valid_Object_Key`, which changes a documented `.ads` contract and rejects keys
AWS accepts), or the listing serializers percent-encode unescapable bytes
regardless of `EncodingType` (which changes response bytes), or the failure
maps to a defined 4xx. That choice belongs to the maintainer, not to a fix
applied in passing.

---

### WIRE-1b: a key with a non-UTF-8 byte produces a 200 listing whose body is not the UTF-8 it declares

**Verdict:** CONFIRMED. This is a sibling of WIRE-1 that the discovery report
listed only as a "secondary effect" without a severity or a repro; verified
here as a distinct defect with a distinct mechanism (silent success rather
than 500).

**Severity:** P2 (discovery did not assign one). It needs unusual input: a
lone `0xFF` in a key cannot be produced by botocore or any SDK that encodes
keys from Unicode strings, only by a hand-built signed request. The
consequence once present is worse than WIRE-1's -- the server reports 200 and
the client's parser fails -- but the rubric keys P2 on input unusualness, and
nothing about the failure is unsafe for the server.

Verified by reading:

- `src/flyology-object_storage.adb:479-490`: no UTF-8 requirement in the key
  contract, so `0xFF` is a valid key byte.
- `src/flyology-object_storage-s3-xml.adb:228-234`: `Escape` only rejects
  bytes below 32; `0xFF` passes through unchanged into the page.
- `tests/src/object_storage_test_cases.adb:9219-9221` asserts that the
  crate's own `XML.Parse` must reject invalid UTF-8 (`<a>` + `0xC0`), so the
  server emits a document its own reader is required to refuse.
- `review/baseline/service-2.json` describes keys as Unicode and responses as
  UTF-8 encoded; a raw `0xFF` is neither.

Refutation attempts that failed:

- Checked whether the listing path validates UTF-8 anywhere before writing
  the key: it does not; `Encoded` and `Element` are the only transforms.
- Checked whether `encoding-type=url` rescues it: it does (the run shows the
  `%FF` form and a valid-UTF-8 body), which is exactly the WIRE-1 asymmetry.
- Checked whether the memory backend normalizes keys: it stores the bytes
  given, as the GET/DELETE controls in `repro_wire_1` show.

**Repro:** `tests/repros/src/repro_wire_1b.adb`. It stores `plain.txt` and
`h%FF`, then asserts that the v1 listing body is valid UTF-8 and that the
crate's own `S3.XML.Parse` accepts the page the server just emitted. The
all-ASCII listing is checked first as a control, so a failure cannot be blamed
on the receiver.

**Output** (`cd tests/repros && ./run.sh repro_wire_1b`, exit status **1**):

```
  -- CreateBucket status 200
  ok: CreateBucket is 200
  ok: PutObject of an ordinary key is 200
  -- CONTROL ListObjects status 200
  ok: CONTROL: an ordinary listing body is valid UTF-8
  -- CONTROL listing: parsed, keys [plain.txt]
  ok: CONTROL: the crate parses its own ordinary listing
  -- PutObject /wire-one-b-bucket/h%FF status 200
  ok: PutObject of a %FF key is accepted (precondition)
  -- ListObjects (no encoding-type) status 200
  --   body: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-one-b-bucket</Name><Prefix></Prefix><Marker></Marker><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Contents><Key>h\xff</Key><LastModified>2026-09-07T01:47:28.000Z</LastModified><ETag>"415290769594460e2e485922904f345d"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass><Owner><ID>repro-principal</ID></Owner></Contents><Contents><Key>plain.txt</Key><LastModified>2026-09-07T01:47:28.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass><Owner><ID>repro-principal</ID></Owner></Contents></ListBucketResult>
  ok: the listing answers 200
  FAILED: the listing body is valid UTF-8 as its declaration claims
  -- listing with the %FF key: S3.XML.Parse raised XML_Error
  FAILED: the crate's own S3 XML parser accepts the listing it emitted
  -- DeleteObject of the %FF key status 204
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** Because the key contract admits arbitrary non-NUL bytes and
the XML escaper only guards the C0 range, a key containing a byte that is not
valid UTF-8 is copied verbatim into a listing whose XML declaration says
`encoding="UTF-8"`. The server answers 200 and the response passes its own
framing checks, but the document is not well-formed XML: every conforming
parser, including this crate's `S3.XML.Parse`, rejects the whole page, so the
client sees a parse failure rather than a server error and cannot tell which
key caused it. It is deterministic and confined to buckets holding such a key,
and `encoding-type=url` avoids it. Only a hand-built request can create the
key, so no SDK user reaches it accidentally. No existing test asserts the
wrong behaviour. A fix shares WIRE-1's maintainer decision: whether
`Valid_Object_Key` gains a UTF-8 requirement (an `.ads` contract change) or
the serializers escape unrepresentable bytes unconditionally.

---

### WIRE-2: the entity-tag list parser rejects RFC-valid empty list elements as `Invalid_Request`

**Verdict:** CONFIRMED at both levels the discovery entry predicted: the
domain predicate returns False and the server answers 400 InvalidArgument. The
one thing I could not settle is S3's own tolerance, which is why the severity
stays low; see below.

**Severity:** P2 (discovery also said P2). It needs unusual input -- no S3 SDK
emits an empty list element, and the RFC forbids senders from generating one.
It is a recipient-side conformance gap, not a wrong answer to anything a
normal client sends.

Verified by reading:

- `src/flyology-object_storage.adb:182-186`: after `Skip_Whitespace`, an
  element position at end of field returns with `Valid` still False, so a
  trailing comma invalidates the whole field.
- `:197-201`: an element position that is not `W/` and not `"` returns with
  `Valid` False, so a leading or interior comma invalidates the field.
- `:235-249`: `Valid := True` is set only when the field ends immediately
  after a tag; any comma continues the loop into the two returns above.
- Consumers: `Evaluate_Object_Write_Conditions` (`:250-275`) and
  `Evaluate_Object_Read_Conditions` (`:298-336`) map `not Valid` to
  `Invalid_Request`, and `Valid_Object_Read_Entity_Tag_Condition`
  (`:278-288`) is defined as "not `Invalid_Request`".
- Server admission:
  `src/flyology-object_storage-server-s3_applications.adb:16706-16718` calls
  `Backends.Valid_Read_Entity_Tag_Condition` on the verbatim
  `if-match` / `if-none-match` header and answers 400 InvalidArgument.
- Contract: `src/flyology-object_storage.ads:126-130` says the predicate is
  True "when Value has valid bounded entity-tag list syntax"; RFC 9110
  section 5.6.1 defines `#element` with a recipient form
  `[ element ] *( OWS "," OWS [ element ] )` and section 5.6.1.2 requires a
  recipient to parse and ignore a reasonable number of empty list elements
  (from memory, unverified). So "valid list syntax" includes them.

Refutation attempts that failed:

- Looked for a caller that trims commas before the predicate: the server
  passes `Apps.Request_Header (X, "if-match")` verbatim, and the client copies
  `Conditions.If_Match` verbatim.
- Looked for an existing test that pins the current rejection as intended:
  `tests/src/object_storage_test_cases.adb:3763-3765` asserts a *valid* list
  with HT and a weak tag, `:3770-3772` rejects `*, "etag"`, `:3773-3775`
  rejects an oversized field. Nothing covers an empty element, so the
  behaviour is unasserted rather than deliberate.
- Checked whether tolerating empties could unbound the parser: the field is
  already capped by `Maximum_Condition_Length` and the loop is bounded by
  `Remaining_Items`, so ignoring an empty element is free.
- Tried to settle S3's own behaviour: `review/baseline/service-2.json` types
  `IfMatch` as an unconstrained header string, and I did not run a live server
  or MinIO. That sub-question remains UNVERIFIABLE from the repository alone.

**Repro:** `tests/repros/src/repro_wire_2.adb`. Unit level, it asserts
`Valid_Object_Read_Entity_Tag_Condition` and `Evaluate_Object_Read_Conditions`
accept a trailing, a leading and an interior empty element and evaluate to
`Success` against the matching tag, and prints what
`Evaluate_Object_Write_Conditions` returns for the same fields. Server level,
it stores an object and asserts a signed HEAD carrying each field answers 200.
Controls: the plain quoted tag and `*` must be 200, and a genuinely
non-matching tag must still be 412, so the program is not merely asserting
that everything succeeds.

**Output** (`cd tests/repros && ./run.sh repro_wire_2`, exit status **1**):

```
  -- Valid_Object_Read_Entity_Tag_Condition ("9dd4e461268c8034f5c8564e155c67a6") = TRUE
  ok: CONTROL: a plain quoted entity tag is valid
  -- trailing empty element: Valid_Object_Read_Entity_Tag_Condition ("9dd4e461268c8034f5c8564e155c67a6",) = FALSE
  FAILED: trailing empty element: the field is accepted as entity-tag list syntax
  -- trailing empty element: Evaluate_Object_Read_Conditions = INVALID_REQUEST
  FAILED: trailing empty element: the read condition evaluates to Success
  -- trailing empty element: Evaluate_Object_Write_Conditions = INVALID_REQUEST
  -- leading empty element: Valid_Object_Read_Entity_Tag_Condition (,"9dd4e461268c8034f5c8564e155c67a6") = FALSE
  FAILED: leading empty element: the field is accepted as entity-tag list syntax
  -- leading empty element: Evaluate_Object_Read_Conditions = INVALID_REQUEST
  FAILED: leading empty element: the read condition evaluates to Success
  -- leading empty element: Evaluate_Object_Write_Conditions = INVALID_REQUEST
  -- interior empty element: Valid_Object_Read_Entity_Tag_Condition ("9dd4e461268c8034f5c8564e155c67a6",,"other") = FALSE
  FAILED: interior empty element: the field is accepted as entity-tag list syntax
  -- interior empty element: Evaluate_Object_Read_Conditions = INVALID_REQUEST
  FAILED: interior empty element: the read condition evaluates to Success
  -- interior empty element: Evaluate_Object_Write_Conditions = INVALID_REQUEST
  -- CreateBucket status 200
  ok: CreateBucket is 200
  -- PutObject ETag "9dd4e461268c8034f5c8564e155c67a6"
  ok: the stored object has the expected ETag
  -- CONTROL exact tag: If-Match: "9dd4e461268c8034f5c8564e155c67a6" -> status 200
  ok: CONTROL exact tag answers 200
  -- CONTROL wildcard: If-Match: * -> status 200
  ok: CONTROL wildcard answers 200
  -- trailing empty element: If-Match: "9dd4e461268c8034f5c8564e155c67a6", -> status 400
  FAILED: trailing empty element answers 200
  -- leading empty element: If-Match: ,"9dd4e461268c8034f5c8564e155c67a6" -> status 400
  FAILED: leading empty element answers 200
  -- interior empty element: If-Match: "9dd4e461268c8034f5c8564e155c67a6",,"other" -> status 400
  FAILED: interior empty element answers 200
  -- CONTROL non-matching tag -> status 412
  ok: CONTROL: a non-matching If-Match is 412
BUG REPRODUCED: 9 failed expectation(s)
```

**Description:** `Read_Entity_Tag_List` sets `Valid` only when the field ends
immediately after a quoted tag, so any empty list element -- a trailing comma,
a leading comma, or `",,"` between two tags -- makes the whole field
`Invalid_Request`. The server turns that into 400 InvalidArgument for
HeadObject and GetObject conditions and into `Invalid_Request` for PutObject
write conditions, instead of evaluating the request against the tags that are
actually present. Under RFC 9110 section 5.6.1.2 a recipient is required to
parse and ignore a reasonable number of empty elements, so a field that a
compliant intermediary may legitimately produce (for example by joining a
present and an absent field value) is answered 400 rather than 200 or 412. It
is deterministic, and no existing test asserts the current 400, so a fix needs
no test rewrite. The fix is local -- treat a comma-terminated position with no
following tag as an ignorable element while keeping the `Remaining_Items`
bound -- and needs no new public constant or contract change; the `.ads`
wording already claims HTTP list syntax. Whether S3 itself tolerates empty
elements was not established, so a maintainer may prefer to match S3 rather
than the RFC; that is the only open question.

---

### WIRE-3: a Range field whose unit is not `bytes` is answered 400 instead of being ignored

**Verdict:** CONFIRMED. The discovery report listed the Range policy under
"observations not counted" and handed the disposition to the server area; on
re-reading I count the unrecognized-unit case as a finding, because RFC 9110
states a MUST there rather than a MAY, and nothing in the repository documents
the server's 400.

**Severity:** P2 (discovery did not count it). It needs unusual input -- no S3
SDK sends a non-`bytes` unit, and the closest stock-client case is
`curl -r a-b,c-d`, which is multi-range rather than unknown-unit. Not P1
because a non-`bytes` Range is not "valid input" for an S3 GET, and not P0
because the response is a clean, diagnosable 400 rather than corruption or a
protocol framing violation.

Verified by reading:

- `src/flyology-object_storage-s3-core.ads:172-178` documents
  `Parse_Range_Header` as accepting one `bytes` range and rejecting multiple
  ranges "because the server does not yet emit multipart/byteranges
  responses". It documents the *parser*'s classification only.
- `src/flyology-object_storage-server-s3_applications.adb:16839-16847`
  (HeadObject) and `:17226-17234` (GetObject) are the only two sites that
  consume that classification, and both map `Malformed_Range` to
  `Send_Error (X, 400, "InvalidRequest", "The Range header is malformed")`.
  Nothing else in `src/` or `docs/` mentions that string.
- `tests/src/object_storage_test_cases.adb:8787-8794` asserts the parser
  classification for `bytes=0-0,2-2` and `items=0-1`, but a repository-wide
  grep for "Range header is malformed" finds no test, so the server's 400
  mapping is unasserted.
- `docs/compatibility/s3.md:736-737` documents the HEAD/part response shape
  and `:907` records that "invalid ranges" are exercised by the `s3t`
  allowlist, but neither states the status code for an unusable Range.

External facts, both from memory and unverified: RFC 9110 section 14.2 states
that an origin server MUST ignore a Range header field containing a range unit
it does not understand, and separately that a server MAY ignore or reject a
pathological multi-range set (section 14.1.1); AWS S3 is believed to return
200 with the whole object for Range fields it cannot use, including
multi-range. I did not run a live S3, MinIO or RustFS server to check either.

Refutation attempts that failed:

- Looked for a documented policy that makes the 400 intended: `core.ads`
  documents only the parser, the compatibility matrix documents only the
  supported shapes, and no test pins the status.
- Looked for a separate path that ignores the header for unknown units before
  `Parse_Range_Header` is called: the header is fetched and parsed
  unconditionally when `Range_Count = 1`.
- Considered whether HEAD should differ: RFC 9110 defines range handling for
  GET only, and `docs/compatibility/s3.md:736-737` says the crate deliberately
  answers HEAD ranges AWS-style with 200 and a selected `Content-Length`; the
  400 applies to HEAD as well, which the run shows.

**Repro:** `tests/repros/src/repro_wire_3.adb`. It stores a ten-byte object
and asserts that GET and HEAD with `Range: items=0-1` answer 200 with the
whole object. Controls first: `bytes=0-1` must be 206 with the two bytes,
`bytes=100-200` must be 416, and a request with no Range must be 200 with all
ten bytes. The other malformed shapes -- multi-range with and without a
space, `bytes=abc`, `bytes 0-1`, `bytes=`, a parameter suffix, and the
inverted `bytes=5-1` -- are printed as notes only, because I could not
establish what AWS does for them.

**Output** (`cd tests/repros && ./run.sh repro_wire_3`, exit status **1**):

```
  -- CreateBucket 200
  -- PutObject 200
  -- GET Range: [bytes=0-1]  parser=RANGE_PARSED  status=206  Content-Range=[bytes 0-1/10]  Content-Length=[2]  body=2 bytes
  ok: CONTROL: a supported byte range is 206 with the two bytes
  -- GET Range: [bytes=100-200]  parser=RANGE_PARSED  status=416  Content-Range=[bytes */10]  Content-Length=[178]  body=178 bytes
  ok: CONTROL: a valid but unsatisfiable byte range is 416
  ok: CONTROL: a request without Range returns the whole object
  -- GET Range: [items=0-1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  FAILED: GET with an unrecognized range unit is 200
  FAILED: GET with an unrecognized range unit returns the whole object
  -- HEAD Range: [items=0-1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=0 bytes
  FAILED: HEAD with an unrecognized range unit is 200
  -- GET Range: [bytes=0-1, 4-5]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=0-1,4-5]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=abc]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes 0-1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=0-1;q=1]  parser=MALFORMED_RANGE  status=400  Content-Range=[]  Content-Length=[171]  body=171 bytes
  -- GET Range: [bytes=5-1]  parser=RANGE_PARSED  status=416  Content-Range=[bytes */10]  Content-Length=[178]  body=178 bytes
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** `Parse_Range_Header` folds every shape it cannot serve into
one `Malformed_Range` status, and both server call sites answer 400
InvalidRequest for all of them. For an unrecognized range unit RFC 9110
section 14.2 requires the field to be ignored and the representation returned
normally, so a client sending `Range: items=0-1` gets 400 here and (believed,
unverified) 200 from AWS S3. The same 400 covers multi-range, which is a
deliberate parser decision documented in `core.ads:174-176` but whose server
mapping is not documented anywhere; `curl -r 0-1,4-5` is the realistic stock
client that reaches it. The behaviour is deterministic and no test asserts it.
Two maintainer decisions are needed for a fix and neither should be taken in
passing: whether `Range_Parse_Status` gains a third value distinguishing
"ignore this field" from "reject this request" (a public enumeration change in
a SPARK-proved `.ads`), and which of the remaining malformed shapes should be
ignored rather than rejected -- the answer should be pinned against a live S3
or the pinned MinIO image rather than from memory. The inverted range
`bytes=5-1` is a separate case: it currently parses successfully and yields
416 with `Content-Range: bytes */10`, which I did not check against any real
server and have not counted as a finding.

---

### WIRE-4: a key containing CR is silently reported as a different key by every listing without `encoding-type=url`

**Verdict:** CONFIRMED. The discovery report named this mechanism in one line
as a "secondary effect" of WIRE-1 with no severity and no repro. It is a
distinct and more serious defect than WIRE-1: the server reports success and
the client silently receives the wrong key.

**Severity:** P1 (discovery did not assign one; higher than WIRE-1b because
the key is reachable from a stock SDK). Not P0: no stock client rejects the
response, and there is no data loss -- the object is still stored under its
real key and is still reachable by anyone who knows it.

Verified by reading:

- `src/flyology-object_storage-s3-xml.adb:228-234`: `Escape` explicitly
  exempts `Character'Val (13)` from the C0 rejection, so CR is written into
  the `<Key>` text literally rather than as `&#13;`.
- `src/flyology-object_storage-s3-listings.adb:1033-1034`: `Element` applies
  only `Escape_Text`, which escapes `&`, `<` and `>` and nothing else for text
  content, so no numeric character reference is produced for CR.
- `src/flyology-object_storage.adb:479-490`: CR is a valid key byte.
- `src/flyology-object_storage-s3-requests.adb:73-77`: `%0D` decodes to CR, so
  the key is reachable from any client that percent-encodes a key containing
  `\r`, which is what botocore does.
- XML 1.0 end-of-line normalization (external fact, from memory but not
  controversial): a literal CR in character data is reported to the
  application as LF. The run confirms it empirically through the crate's own
  parser, so the claim does not rest on my memory of the spec.

Refutation attempts that failed:

- Checked whether the escaper writes a character reference for CR: it does
  not; the `elsif` chain falls through to the verbatim `Append`.
- Checked whether `encoding-type=url` avoids it: it does -- the control in the
  run shows `a%0Db` -- which is the same asymmetry as WIRE-1 and WIRE-1b.
- Checked whether the object itself is affected: GET of `/bucket/a%0Db`
  returns the body, so the storage side is correct and only the listing
  representation is wrong.
- Checked the existing suite: nothing lists a bucket containing a CR key;
  `tests/src/s3_http_socket_corpus.adb:3129-3292` covers URL-encoded listings
  with printable keys only.

**Repro:** `tests/repros/src/repro_wire_4.adb`. It stores `a%0Db`, confirms
the object is addressable, then parses the v1 listing with the crate's own
`S3.XML.Parse` and asserts the key that comes back equals the key that was
stored. The `encoding-type=url` listing is asserted as a control to return
`a%0Db`, so the failure is isolated to the unencoded path.

**Output** (`cd tests/repros && ./run.sh repro_wire_4`, exit status **1**):

```
  -- CreateBucket 200
  -- PutObject /wire-four-bucket/a%0Db -> 200
  ok: PutObject of a %0D key is accepted (precondition)
  ok: CONTROL: GetObject of the %0D key returns its body
  -- ListObjects (no encoding-type) -> 200
  --   wire bytes of the page: <?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>wire-four-bucket</Name><Prefix></Prefix><Marker></Marker><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated><Contents><Key>a\rb</Key><LastModified>2026-09-07T01:47:32.000Z</LastModified><ETag>"9dd4e461268c8034f5c8564e155c67a6"</ETag><Size>1</Size><StorageClass>STANDARD</StorageClass><Owner><ID>repro-principal</ID></Owner></Contents></ListBucketResult>
  --   stored key:            [a\rb]
  --   key read back by S3.XML.Parse: [a\nb]
  ok: the listing answers 200
  FAILED: the key a conforming XML parser reads back is the stored key
  -- CONTROL encoding-type=url -> 200  key read back [a%0Db]
  ok: CONTROL: encoding-type=url reports the key percent-encoded
  -- DeleteObject of the %0D key -> 204
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** `XML.Escape` deliberately allows TAB, LF and CR through
unescaped, which is correct for arbitrary text but wrong for a key, because
XML 1.0 requires a parser to normalize a literal CR in character data to LF
before handing it to the application. A key stored as `a\rb` is therefore
reported by ListObjects v1, ListObjectsV2 and ListObjectVersions as `a\nb`
whenever `encoding-type=url` is absent. The server returns 200, the document
is well-formed, and nothing anywhere reports an error; the client simply gets
a key it cannot address, and a subsequent GET, HEAD or DELETE of `a%0Ab`
answers 404. The same substitution corrupts a `NextMarker` derived from such a
key, so a paginating client can also skip or repeat entries. It is fully
deterministic and is reachable from a stock SDK: botocore percent-encodes a
key containing `\r` as `%0D`, unlike the lone `0xFF` of WIRE-1b. No existing
test asserts the wrong behaviour. The fix is narrower than WIRE-1's and needs
no contract change if it is confined to the listing serializers -- emit `&#13;`
(and, for symmetry, `&#9;` and `&#10;`) for the characters XML normalization
would alter -- but whether that escaping applies to every `Escape_Text` caller
or only to key-bearing elements is a maintainer decision about the crate's
response bytes.

---

## Checked, no finding

Each item below was re-derived from the source and, where a behaviour is
quoted, measured with a scratch probe program that was removed after use (the
brief limits the files I keep to repro programs and this report). The source
anchors are what the conclusion rests on.

**Range shapes other than an unrecognized unit** (discovery: "Range policy",
not counted). `Parse_Range_Header` classifies `bytes=0-1,4-5`, `bytes=abc`,
`bytes 0-1`, `bytes=`, `bytes=0-1;q=1` as `Malformed_Range` and the server
answers 400; `bytes=5-1` and `bytes=100-200` parse and answer 416 with
`Content-Range: bytes */10`. Multi-range rejection is documented at
`src/flyology-object_storage-s3-core.ads:174-176`. RFC 9110 permits a server
to ignore *or reject* an invalid ranges-specifier (from memory, unverified), so
only the unrecognized-unit case is counted, as WIRE-3. The 416 for an inverted
range and the 400 for a syntactically invalid specifier were not checked
against any real server and are recorded as unverified.

**`max-keys` above 1000** (discovery: policy value). Measured: `max-keys=0`
and `max-keys=1000` answer 200 (`<MaxKeys>0</MaxKeys>` and
`<MaxKeys>1000</MaxKeys>`), `max-keys=00001000` answers 200 with
`<MaxKeys>1000</MaxKeys>`, and `max-keys=1001`, `-1`, `+1` and
`99999999999999999999` answer 400 InvalidArgument. `max-uploads=0` answers
400 while `max-keys=0` answers 200. AWS clamps `max-keys` to 1000 rather than
rejecting (from memory, unverified). This is a DOCUMENTED LIMITATION:
`docs/compatibility/s3.md:863` states the contract as "max-keys 0..1000", and
`src/flyology-object_storage-s3-listings.adb:105-121` implements exactly that
range check before the subtype conversion. The `max-uploads=0` asymmetry is
real (`-s3-multipart_uploads.adb:125-142`) but is a policy value inside a
documented range, not a protocol violation.

**Request-target classifier** (discovery: partially covered; the specific
shapes I was asked to check). Measured against `Requests.Parse_Target`:
`/` is `Service_Target`; `//` and `///` are `Malformed_Target` (the bucket
segment is empty and fails `Valid_Bucket_Name`); `/bkt` and `/bkt/` are
`Bucket_Target`; `/bkt//` is an `Object_Target` with key `/` and `/bkt///`
with key `//`; `/bkt/.`, `/bkt/..`, `/bkt/./x`, `/bkt/../x`,
`/bkt/%2e%2e/x` and `/bkt/%2E%2E` are ordinary `Object_Target`s whose keys
are `.`, `..`, `./x`, `../x`, `../x` and `..`; `/./` and `/../` are
`Malformed_Target` for the same bucket-name reason as `//`; `%2F` and `%2f`
in a key decode to `/` inside the key (`/bkt/a%2Fb` has key `a/b`);
`/bkt?acl` and `/bkt/k?x` carry the raw query without the `?`; `/bkt?` and
`/bkt/k?` have no query; `/%62kt/k` decodes the bucket segment to `bkt`;
`/bkt/k#frag` and `?acl` are rejected. This is correct for S3, which treats
keys as opaque and performs no dot-segment resolution
(`src/flyology-object_storage-s3-requests.ads:28-31` states the contract;
`tests/src/object_storage_test_cases.adb:3721-3722` already asserts
`Valid_Object_Key ("../opaque/key")` and a leading slash). The server accepts
`PUT /bucket/.`, `/bucket/..`, `/bucket//x` and `/bucket/./y` with 200, and
`flyology_http`'s dot-segment policy
(`flyology-http-decoded_path_policy.ads`) is used only by
`flyology-http-server-routing.adb`, which the S3 application does not use, so
nothing normalizes those keys on the wire path. Whether a *backend* then
maps `..` onto the filesystem is outside this area; I did not test it and
flag it only so the backend-files reviewer does not assume the wire layer
filters it.

**Bare query key with no `=`.** `?acl` is accepted (200); `?zzz` is rejected
400. That is the documented policy: `docs/compatibility/s3.md:581-582` says
the server "routes malformed tagging and operation-specific `x-id` candidates
through authentication before rejecting non-exact queries", and
`src/flyology-object_storage-server-s3_applications.adb:6659-6663` answers
501 NotImplemented for an unclassified operation while the listing parsers
answer 400 for an unknown parameter. DOCUMENTED LIMITATION, not a finding.

**IMF-fixdate parsing** (discovery: no finding; asked to recheck weekday and
impossible dates). Measured: `Sun, 06 Nov 1994 08:49:37 GMT` parses;
`Mon, 06 Nov 1994 08:49:37 GMT` (wrong weekday) is rejected;
`Sun, 31 Feb 2030 ...` and `Thu, 30 Feb 2030 ...` are rejected;
`Sun, 29 Feb 2029 ...` (non-leap year) is rejected while
`Thu, 29 Feb 2024 ...` parses; second `60` normalizes to the next minute
(`08:49:60` becomes `08:50:00`) and `61` is rejected; RFC 850, asctime, `0`
and `-1` are all rejected. Every one of these matches the documented contract
at `src/flyology-object_storage-s3-imf_dates.ads:1-3,16-19`, which states the
package is deliberately not a generic RFC 9110 recipient. Separately, the
conditional-date path that RFC 9110 *does* require to accept all three
formats does accept all three:
`src/flyology-object_storage-s3-object_reads.adb:84-124` handles IMF-fixdate,
asctime and the RFC 850 long-weekday form. No finding.

**Decimal parsing of `Content-Length`-like values** (discovery: no finding;
asked to recheck `+`, leading zeros, and above 2^63-1). Measured on
`Wire_Core.Parse_Natural` / `Parse_Byte_Count`: `0` and `007` are accepted
(007 yields 7); `+1`, `-1`, `" 1"`, `"1 "` and the empty string are rejected;
`9223372036854775807` is accepted as a `Byte_Count` and rejected as a
`Natural` (correctly -- `Natural'Last` is 2^31-1 on this target);
`9223372036854775808` and `18446744073709551616` are rejected. That matches
the HTTP `1*DIGIT` production, which permits leading zeros and forbids a sign.
The overflow guard `Result > (T'Last - Digit) / 10`
(`src/flyology-object_storage-s3-wire_core.adb:16-19,35-38`) and the same
guard in `Core.Parse_Decimal`
(`src/flyology-object_storage-s3-core.adb:86-90`) are exact for every digit.
No finding.

**`XML.Escape`'s stack buffer, `XML.Parse`'s exception funnel, the `-an`
bucket-name suffix, `Listing_Follows_Cursor` on a marker inside a collapsed
group, `Read_Entity_Tag_List`'s `""` handling, and bucket-segment percent
decoding.** Re-read each; I reached the same conclusions the discovery report
recorded and have nothing to add. The `-an` suffix
(`src/flyology-object_storage.adb:452`) does carry no recorded authority near
its declaration, which `.claude/rules/decision-authority.md` asks for, but it
only over-restricts bucket names and is not a correctness defect.

## Harness notes

`tests/repros/run.sh` worked as documented for all five programs; no harness
problem to report. One usage caveat for later agents:
`Repro_S3_Server.Signed_Request` passes the same `Path` string to
`SigV4.Sign` and onto the wire, and `SigV4.Sign` URI-encodes what it is given
(`src/flyology-object_storage-s3-sigv4.adb:270`) while the server percent-
decodes the wire path before signing
(`src/flyology-object_storage-s3-sigv4_verification.adb:309-310,420-423`).
A wire path containing a percent escape therefore cannot be signed through
`Signed_Request`; `repro_wire_1.adb`, `repro_wire_1b.adb` and
`repro_wire_4.adb` each carry a small local `Signed_Wire` helper that signs
the decoded path and emits the encoded one.
