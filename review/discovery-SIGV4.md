# Correctness discovery: SIGV4 (signing, verification, admission, credentials, secrets)

Scope: read in full `src/flyology-object_storage-s3-sigv4.ad?`,
`src/flyology-object_storage-s3-sigv4_encoding.ad?`,
`src/flyology-object_storage-s3-sigv4_verification.ad?`,
`src/flyology-object_storage-server-authentication.ad?`,
`src/flyology-object_storage-server-static_credentials.ad?`,
`src/flyology-object_storage-server-mfa.ad?`,
`src/flyology-object_storage-secrets.ad?`,
`src/flyology_object_storage_secure_erase.c`, `tests/src/s3_server_harness.adb`,
`tools/s3-signed-socket.py`. Read partially:
`src/flyology-object_storage-server-s3_applications.adb` 1875-1925
(outcome-to-error mapping), 4020-4075 (body hash enforcement), 6014 and
6680-6745 (`Verify_Request` call site), 17970-18066 (`Handle` exception
handler), plus `rg` for every `Auth.Payload_Hash`, `aws-chunked`,
`x-amz-decoded-content-length`, `Create_Session` use;
`src/flyology-object_storage-client-low_level.adb` 545-570, 680-700, 770-800,
1160-1310, 1429-1441, 1455-1530 (both `SigV4.Sign` call sites, `Wire_Query`,
path expansion). Reference material: `flyology_http` 0.1.3
(`~/.local/share/alire/releases/flyology_http_0.1.3_eb09a80a/src/flyology-http-server-applications.ads`
84-170, 275-283, 312-318) for `Request_Header*`, `Request_Target`,
`Request_Scheme`, `Set_Principal`; GNAT 16.2 runtime `a-calend.adb` 288-314
(`"-" (Time, Time)`), `system.ads` (`Duration_32_Bits = False`);
`review/baseline/service-2.json` (confirmed it carries no `signingName`);
`docs/compatibility/s3.md` 77-78, 452-460; `README.md` 407-412;
`docs/qualification/create-session.md` 28-50; `docs/qualification/put-object.md`
9-11, 158-172. Existing coverage inspected:
`tests/src/object_storage_test_cases.adb` `Check_SigV4_Official_Vectors`
(8905-9115) and `Check_SigV4_Verification` (19335-19466);
`tests/src/s3_server_application_corpus.adb` provider and policy setup
(802-809), `Fixed_Clock` (407-409); `tests/src/s3_server_harness.adb`;
`tools/s3-signed-socket.py`. No AWS SigV4 test-suite corpus exists under
`tests/corpora/`; the only `aws4_request` vectors are the AWS S3 published
examples embedded in `Check_SigV4_Official_Vectors`.

Severity rubric: P0 = memory/aliasing unsafety, signature-verification bypass,
path escape, credential exposure, authorisation bypass, data loss, hang, or an
interop-breaking violation a stock client/server rejects. P1 = wrong result or
unexpected exception on valid input via a reachable path, or a documented
contract violated. P2 = edge-case incorrectness, wrong diagnostics, or contract
drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| SIGV4-1 | Far-future `x-amz-date` (>= 2318-12-16 today) escapes `Verify_Request` as `Ada.Calendar.Time_Error`; server answers 500 `InternalError` instead of 403 `RequestTimeTooSkewed` | P2 | High |
| SIGV4-2 | `Static_Credentials.Create` accepts principals of 257..1024 bytes that `Authentication.Valid_Principal` (mirroring `Set_Principal`'s 256-byte bound) rejects, so every correctly signed request gets 403 `SignatureDoesNotMatch` | P2 | High |

Summary: no P0 or P1 finding. The signature path itself (canonicalisation,
key derivation, mandatory signed headers, scope/date binding, body-hash
enforcement, constant-time compare, session-token binding, secret wiping) was
reviewed against the AWS rules and the published S3 vectors and no bypass or
weakening was found. Two P2 defects on the admission edges, listed above.

---

### SIGV4-1: Far-future `x-amz-date` escapes `Verify_Request` as `Ada.Calendar.Time_Error`; 500 instead of 403 `RequestTimeTooSkewed`

**Location:** `src/flyology-object_storage-server-authentication.adb:150-165`,
`src/flyology-object_storage-server-authentication.adb:224-227`,
`src/flyology-object_storage-s3-sigv4_encoding.adb:190-195`,
`src/flyology-object_storage-server-s3_applications.adb:6697-6701`,
`src/flyology-object_storage-server-s3_applications.adb:18056-18065`.

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-s3-sigv4_encoding.adb:190-195` accepts any
four-digit year above zero:

```ada
         return Year > 0
           and then Month in 1 .. 12
           and then Day in 1 .. Maximum_Day
           and then Hour <= 23
           and then Minute <= 59
           and then Second <= 59;
```

`src/flyology-object_storage-server-authentication.adb:57-69` converts it with
`Ada.Calendar.Year_Number` (GNAT range 1901 .. 2399), catching only the
conversion errors:

```ada
      return Ada.Calendar.Formatting.Time_Of
        (Ada.Calendar.Year_Number (Year),
         ...
         Time_Zone => 0);
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         Valid := False;
         return Ada.Calendar.Time_Of (2000, 1, 1);
   end Timestamp_Time;
```

`src/flyology-object_storage-server-authentication.adb:157-165` subtracts the
two `Time` values outside that handler:

```ada
      declare
         Difference : constant Duration :=
           (if Now >= Request_Time then Now - Request_Time
            else Request_Time - Now);
      begin
         if Difference > Rules.Maximum_Clock_Skew then
            return (Status => Request_Time_Too_Skewed, others => <>);
         end if;
      end;
```

`src/flyology-object_storage-server-authentication.adb:224-227` catches only
`Constraint_Error`:

```ada
   exception
      when Constraint_Error =>
         return (Status => Malformed_Credentials, others => <>);
   end Verify_Request;
```

GNAT runtime, `adainclude/a-calend.adb:288-314` (toolchain
`gnat_flyology_native_16.2.0`; identical text in the 13.2 .. 16.1 toolchains
present on this host): `"-" (Left, Right : Time) return Duration` raises
`Time_Error`, not `Constraint_Error`, when the difference leaves `Duration`'s
range, and re-raises an internal `Constraint_Error` as `Time_Error`:

```ada
      if Res_N < Dur_Low or else Res_N > Dur_High then
         raise Time_Error;
      end if;
      return Time_Rep_To_Duration (Res_N);
   exception
      when Constraint_Error =>
         raise Time_Error;
   end "-";
```

`system.ads` in the same toolchain has `Duration_32_Bits := False`, so
`Duration'Last` = 9,223,372,036.854 s = 292.277 years. For `Now` =
2026-09-06 (today), every `x-amz-date` from 2318-12-16T23:47:17Z through the
`Year_Number` ceiling 2399-12-31T23:59:59Z overflows (python3 arithmetic in
the review session). The past side cannot overflow because 2026 - 292 years
is below the 1901 floor.

Contract, `src/flyology-object_storage-server-authentication.ads:53-64`:

```ada
   --  Authenticate an exchange before accepting or consuming its body.
   --  Exactly one Authorization, date, content hash, and each declared signed
   --  field must be present. The scope date, semantic UTC timestamp, clock
   --  skew, optional region, and HTTPS requirement for UNSIGNED-PAYLOAD are
   --  checked before the credential provider is invoked.
```

and the application's intended mapping,
`src/flyology-object_storage-server-s3_applications.adb:1893-1897`:

```ada
         when Authentication.Request_Time_Too_Skewed =>
            Send_Error
              (X, 403, "RequestTimeTooSkewed",
```

The escaping exception is instead absorbed by `Handle`'s catch-all,
`src/flyology-object_storage-server-s3_applications.adb:18056-18065`:

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

**Failure scenario:** An unauthenticated peer (no valid credentials are
needed; the provider is never reached) sends any routed request with
`x-amz-date: 23190101T000000Z`, `Credential=AKID/23190101/us-east-1/s3/aws4_request`,
`x-amz-content-sha256: e3b0c442...b855`, `SignedHeaders=host;x-amz-content-sha256;x-amz-date`,
and a 64-hex `Signature`. `Parse` succeeds (all fields well formed);
`Verify_Request` passes the header-count checks (130-149); `Timestamp_Time`
returns 2319-01-01 without raising (2319 is inside `Year_Number`); at 159
`Now >= Request_Time` is false so `Request_Time - Now` is evaluated; GNAT's
`"-"` raises `Time_Error`; the handler at 225 does not match it; the exception
leaves `Verify_Request` and `S3_App.Handle` at 6697, and the catch-all at
18056 sends `500 InternalError`. The correct answer is
`403 RequestTimeTooSkewed` (or, for a policy that wants to hide it,
`400 AuthorizationHeaderMalformed`); a 500 is also the status that operators
alert on and that clients such as aws-cli/boto3 retry with backoff.

**Reproduction test sketch:** Through the in-process loopback application used
by `tests/src/s3_server_application_corpus.adb` (its `Run` helper sends raw
request text to the `S3_Applications` instance with `Fixed_Clock` =
2013-05-24T00:00:00Z and `Maximum_Clock_Skew => 1.0`):

```
GET /test-bucket HTTP/1.1
Host: 127.0.0.1:<port>
x-amz-date: 23190101T000000Z
x-amz-content-sha256: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
Authorization: AWS4-HMAC-SHA256 Credential=<corpus access key>/23190101/us-east-1/s3/aws4_request, SignedHeaders=host;x-amz-content-sha256;x-amz-date, Signature=0000000000000000000000000000000000000000000000000000000000000000
```

Expected: `HTTP/1.1 403` with `<Code>RequestTimeTooSkewed</Code>`. Actual:
`HTTP/1.1 500` with `<Code>InternalError</Code>`. With the corpus' fixed 2013
clock the threshold is 2305-09-02; with the harness' wall clock it is
2318-12-16 today and moves forward one day per day. A direct unit check is
also possible: `Authentication.Verify_Request (X, Provider, Rules, Now =>
Time_Of (2026, 9, 6))` with an `Exchange` carrying that header must return
`Request_Time_Too_Skewed`, not propagate.

**Existing coverage:** none. `Check_SigV4_Official_Vectors` (9095-9113) only
asserts `Sign` rejects a syntactically malformed timestamp. The corpus signs
every request with `20130524T000000Z` against `Fixed_Clock` and never sends a
skewed timestamp; `rg RequestTimeTooSkewed tests/ server/tests/` finds no
assertion. No test sends an `x-amz-date` in a year above 2013.

**Refutation attempts:** (1) Checked `Valid_Timestamp` for an upper bound on
the year: there is none (`Year > 0`). (2) Checked whether `Timestamp_Time`'s
handler covers the subtraction: it does not; the subtraction is at 159-160 in
`Verify_Request`, outside that function. (3) Checked whether `Year_Number`
would reject 2319: GNAT's range is 1901 .. 2399, so 2319 .. 2399 convert
cleanly. (4) Checked whether GNAT raises `Constraint_Error` (which the 225
handler would catch): the runtime source explicitly raises `Time_Error` and
converts any internal `Constraint_Error` into `Time_Error`. (5) Checked
`Duration_32_Bits`: it is `False`, so the 292-year window is the real one on
the supported native targets. (6) Checked whether the HTTP layer rejects the
value earlier: `x-amz-date` is an opaque field to `flyology_http`. (7) Checked
whether the exception is fatal: `Handle`'s catch-all turns it into a 500, so
the process and connection survive; that is why this is P2 (wrong diagnostic
on unusual input) rather than P1.

---

### SIGV4-2: `Static_Credentials.Create` accepts principals up to 1,024 bytes that the server then rejects on every request

**Location:** `src/flyology-object_storage-server-static_credentials.ads:20-36`,
`src/flyology-object_storage-server-static_credentials.adb:36-40`,
`src/flyology-object_storage-server-authentication.adb:18-31`,
`src/flyology-object_storage-server-authentication.adb:213-217`.

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-server-static_credentials.ads:20-36` promises
that `Create` validates length and raises otherwise, with a 1,024-byte bound:

```ada
   --  Copy one credential identity into bounded provider-owned storage.
   --  All retained fields are wiped during finalization. An empty Principal
   --  uses Access_Key as the authenticated principal name.
   ...
   --  @exception Invalid_Credentials A field is empty, malformed, or too long
   function Create
   ...
private
   Maximum_Credential_Bytes : constant := 1_024;
   Maximum_Session_Token_Bytes : constant := 8_192;
   Maximum_Principal_Bytes : constant := 1_024;
```

`src/flyology-object_storage-server-static_credentials.adb:36-40`:

```ada
        or else Effective_Principal'Length = 0
        or else Effective_Principal'Length > Maximum_Principal_Bytes
      then
         raise Invalid_Credentials with "invalid static S3 credentials";
      end if;
```

`src/flyology-object_storage-server-authentication.adb:18-31` and 213-217
reject anything over 256 bytes after the signature has already verified:

```ada
   function Valid_Principal (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value'Length > 256 then
         return False;
      end if;
```

```ada
            if not Allowed
              or else not Valid_Principal (US.To_String (Principal))
            then
               return (Status => Credential_Rejected, others => <>);
            end if;
```

`Credential_Rejected` is mapped to `403 SignatureDoesNotMatch`
(`s3_applications.adb:1907-1910`). The 256-byte figure comes from the HTTP
layer, `flyology-http-server-applications.ads:279-283`:

```ada
   --  Install an authenticated principal. Header control bytes and values
   --  longer than 256 bytes are rejected.
   procedure Set_Principal (Item : in out Exchange; Value : String);
```

`Authentication.ads:17-23` documents only that the provider must return "the
same nonempty Principal"; neither it nor `Static_Credentials.ads` mentions
256.

**Failure scenario:** An operator builds the harness or their own server with
`Static_Credentials.Create (Access_Key, Secret_Key, Principal => P)` where
`P'Length` is 257 .. 1024 (for example a long tenant URN or e-mail-style
identifier). `Create` accepts it. Every request signed with the correct
secret reaches `Authenticate`, which returns `Allowed = True` and the long
principal (static_credentials.adb:80-88); `Valid_Principal` returns `False`;
the server answers `403 SignatureDoesNotMatch` with the message "The request
signature does not match" although the signature matched. The operator has no
diagnostic pointing at the principal.

**Reproduction test sketch:** In `object_storage_test_cases.adb`:
`Provider : Static_Credentials.Provider := Static_Credentials.Create
("AKIDEXAMPLE", "secret", Principal => String'(1 .. 300 => 'p'))` (expected:
raises `Invalid_Credentials` if 256 is the contract, or is accepted and
authenticates if 1,024 is). Then a corpus-style signed
`GET /test-bucket` through the loopback application with that provider.
Expected: the operation's normal response. Actual: `403
SignatureDoesNotMatch`. Equivalent unit form: `Authentication.Verify_Request`
with that provider returns `Credential_Rejected` for a request whose
`Verification.Verify` returns `True`.

**Existing coverage:** none. There are no `Static_Credentials` unit tests in
`object_storage_test_cases.adb` (`rg Static_Credentials tests/src/object_storage_test_cases.adb`
is empty); the corpus uses `Principal => "test-principal"` (802-803) and the
harness `"qualification"` (57).

**Refutation attempts:** (1) Looked for a 256-byte check anywhere in
`Static_Credentials.Create`: only the 1,024 bound and control-byte scan
(31-48). (2) Looked for documentation of the 256 limit on the provider
contract in `authentication.ads`: absent. (3) Checked whether
`Valid_Principal` could be dead code by verifying that `Set_Principal` in the
HTTP layer enforces the same 256 bound, so the admission check is
deliberate and the mismatch lies in `Create`'s accepted range and its
GNATdoc. (4) Checked that `Access_Key` as default principal cannot hit this:
`Valid_Access_Key` allows up to `Maximum_Credential_Bytes` = 1,024
alphanumerics (static_credentials.adb:31-32), so an access key of 257 .. 1024
characters with an empty `Principal` triggers the same failure.

---

## Areas reviewed with no findings

- `SigV4.Sign` canonical request: method token validation; single URI
  encoding of the decoded path with `/` preserved (S3 rule, no double
  encoding); canonical query encodes name and value with the RFC 3986
  unreserved set, uppercase hex, `+` and space encoded, empty values rendered
  as `name=`, sorted after encoding by name then value (same order as
  botocore's `_canonical_query_string_url`); canonical headers lowercased,
  trimmed, inner whitespace folded, stably sorted, repeated names joined with
  `,` in wire order, exactly one `host` required, trailing newline after the
  header block and between sections; payload hash validated as 64 lowercase
  hex or `UNSIGNED-PAYLOAD`. All four AWS S3 published examples are asserted
  byte-for-byte on canonical-request hash and signature in
  `Check_SigV4_Official_Vectors` (8905-9040).
- `SigV4.Sign` string-to-sign and key derivation: `AWS4-HMAC-SHA256\n<ts>\n<scope>\n<hex(sha256(canonical))>`;
  key chain `HMAC("AWS4"+secret, date) -> region -> service -> "aws4_request"`;
  scope date taken from the validated timestamp; every derived key and the
  prefixed secret wiped on both normal and exceptional exit.
- `SigV4.Constant_Time_Equal`: length difference folded into the accumulator,
  loop runs to the longer length, no data-dependent early return.
- `SigV4_Encoding` (SPARK): `URI_Encode` bound `3 * Length` with loop
  invariant; `Lowercase` ASCII-only; `Normalize_Header_Value` trims and folds
  space/tab; `Valid_Timestamp` is calendar-aware (month lengths, Gregorian
  leap years); `Valid_Header_Name` is the HTTP tchar set;
  `Valid_Scope_Segment`, `Valid_Access_Key`, `Valid_Method` reject empty and
  out-of-set bytes.
- `SigV4_Verification.Parse`: prefix and single space; attributes split on
  `,` with trimming; only `Credential`, `SignedHeaders`, `Signature`;
  duplicates and unknown attributes rejected; 5-part scope with literal
  `aws4_request`, decimal 8-digit date, validated access key/region/service;
  `SignedHeaders` must be lowercase, tchar, strictly ascending (so no
  duplicates), never `authorization`, and must include `host`,
  `x-amz-content-sha256`, `x-amz-date`; signature must be 64 lowercase hex;
  bounded 8,192/512/4,096-byte inputs; `Constraint_Error` mapped to
  `Malformed_Authorization`. Tried empty value, prefix only, trailing space,
  trailing comma, missing `=`, `=` first/last, six-part scope, uppercase
  header names, uppercase hex signature: all return a status, none raise.
- `SigV4_Verification.Verify`: origin-form only, first `?` splits, path must
  start with `/`; percent escapes strictly validated (`%GG`, trailing `%`
  fail closed); `+` literal in both path and query; query split on `&` before
  decoding, first `=` separates name/value, so `%26`/`%3D` inside values are
  preserved; empty segments and trailing `&` fail closed; scope service must
  be `s3`; `x-amz-date` and `x-amz-content-sha256` must each appear once in
  the signed set; scope date must equal the timestamp date; passed
  `Payload_Hash` must equal the signed header; the recomputed `SignedHeaders`
  must equal the declared list exactly (so extra or missing physical headers
  cannot verify); signature compared constant-time; `Invalid_Signing_Input`
  and `Constraint_Error` return `False`. Decode-then-re-encode normalisation
  of the path equals MinIO's `EncodePath(URL.Path)` behaviour and is
  consistent with the crate's own client (signs the raw path, sends
  `URI_Encode` of it) and with the s5cmd conformance slice that exercises a
  key with space, plus and percent (`docs/compatibility/s3.md:474-484`).
- `Authentication.Verify_Request`: exactly one `authorization`, `x-amz-date`,
  `x-amz-content-sha256`; payload hash must be `UNSIGNED-PAYLOAD` or 64
  lowercase hex (so `STREAMING-*` never reaches signing and fails closed with
  400); every physical `x-amz-*` header must be in `SignedHeaders`;
  `x-amz-security-token` must be a signed singleton when present and is
  passed to the provider; skew checked in both directions against a caller
  supplied `Now`; optional region pin; `UNSIGNED-PAYLOAD` only on
  `Secure_HTTPS`; every declared signed header must exist physically and
  every occurrence is collected in wire order through the per-occurrence
  accessor (never the comma-joined one); occurrence total bounded at 256;
  provider refusal and invalid principal both map to `Credential_Rejected`.
- Body-hash enforcement (`s3_applications.adb:4055-4059` and every
  `Expected_Hash => Auth.Payload_Hash` site): SHA-256 of the streamed body is
  compared with the signed `x-amz-content-sha256` whenever it is not
  `UNSIGNED-PAYLOAD`, raising `Payload_Hash_Mismatch` -> 400
  `XAmzContentSHA256Mismatch`; a started response is failed instead of
  completed.
- `Static_Credentials`: alphanumeric access key, bounded copies into
  provider-owned fixed arrays, session token compared constant-time in both
  directions (a token present on a token-less identity, or absent on a
  token-bearing one, is rejected), access key compared before any secret use,
  `Finalize` wipes all four buffers and zeroes lengths.
- `MFA`: bounded copies, control-byte rejection, `Clear` on entry and on
  request, borrowed slices only.
- `Secrets` and the C shim: volatile byte-store loop; both `Wipe` overloads
  guard zero length; call sites wipe on exceptional paths too.
- Client `low_level` signing (both preparers): signs the decoded path and
  sends `URI_Encode (Raw_Path, Encode_Slash => False)`; bucket label
  encoded with slash, key label greedy; query canonicalised once and
  transmitted through `Wire_Query` (drops `=` only for empty values, which
  the server re-canonicalises to `name=`); `host`, `x-amz-content-sha256`,
  `x-amz-date`, session-token header always signed; `UNSIGNED-PAYLOAD`
  refused off HTTPS; 8,192-byte target bound mirrors the server.

## Observations not counted

- `aws-chunked` / `STREAMING-AWS4-HMAC-SHA256-PAYLOAD` /
  `STREAMING-UNSIGNED-PAYLOAD-TRAILER`: rejected at admission with 400
  `AuthorizationHeaderMalformed` (authentication.adb:139-140) and, for
  `Content-Encoding: aws-chunked` with a plain hash, `NotImplemented`
  (s3_applications.adb:12620, 14894). Documented boundary
  (`docs/compatibility/s3.md:452-460`, `docs/qualification/put-object.md:9-11,
  166`). Practical impact worth recording: botocore >= 1.36 / aws-cli v2 >=
  2.23 default to `STREAMING-UNSIGNED-PAYLOAD-TRAILER` for PutObject and
  UploadPart over HTTPS and sign the full payload only over plain HTTP (from
  memory, unverified), which is why loopback conformance passes while an
  HTTPS deployment would see 400s from those clients. Not a defect under the
  brief because it is documented; flagged for the SERVER area.
- Presigned URLs (query-string authentication) are not implemented on either
  side; `docs/compatibility/s3.md:78` says "planned / not claimed". A
  presigned request arrives without `Authorization` and gets 403
  `AccessDenied`.
- Credential scope service is hard-coded to `s3` (verification.adb:335). AWS
  SDKs sign `WriteGetObjectResponse` with signing name `s3-object-lambda`
  via the endpoint ruleset (from memory, unverified; the pinned
  `service-2.json` carries no `signingName`). If so, a stock SDK cannot call
  the server's `WriteGetObjectResponse` (403 `SignatureDoesNotMatch`); the
  crate's own client signs it with `s3`, so the pair is self-consistent.
  Recorded here rather than as a finding because it cannot be grounded in
  the repository.
- `x-amz-s3session-token` must be signed (it is `x-amz-*`) but is neither
  bound to a credential nor rejected; with `Static_Credentials` a long-term
  key plus an arbitrary `x-amz-s3session-token` is accepted. Whether the
  server's `Create_Session` (s3_applications.adb:7455) issues credentials
  that would need binding was not reviewed (SERVER area).
- Access-key character set is `[A-Za-z0-9]` in `Sign`, `Parse` and
  `Create`. AWS keys satisfy it; MinIO and Ceph RGW permit `-`, `_` and
  others, so such identities can neither be used by this client nor
  configured as static server identities (`Invalid_Signing_Input` /
  `Invalid_Credentials` / 400). Policy value.
- Only `x-amz-date` is accepted (no `Date` header fallback) and
  `x-amz-content-sha256` must be present and signed; documented boundary
  (`docs/compatibility/s3.md:452-457`).
- Timestamps with year 0001 .. 1900 pass `Valid_Timestamp` and fail
  `Year_Number` inside `Timestamp_Time`, yielding 400
  `AuthorizationHeaderMalformed` instead of 403 `RequestTimeTooSkewed`. Same
  family as SIGV4-1 but caught; diagnostic only.
- Canonical-URI normalisation is not injective on the raw target
  (`/b/a%2Fc` and `/b/a/c`, or `%41` and `A`, share a signature). Identical
  to MinIO; harmless as long as the router decodes the target the same way
  (WIRE/SERVER areas).
- Best-effort erasure gaps consistent with `README.md:407-412`: the
  secondary-stack copy returned by `Static_Credentials.Secret_Key`, the
  return copies of `SigV4.HMAC`, and GNAT.SHA256's internal context copy
  inside `Digest` are not wiped.
- `UNSIGNED-PAYLOAD` requires the listener's own scheme to be HTTPS
  (`Request_Scheme`); behind a TLS-terminating proxy the SDK default is
  refused with 400 `InvalidRequest`. Policy.
- `Static_Credentials.Authenticate` compares the access key with ordinary
  `=` before the constant-time token and signature checks
  (static_credentials.adb:81); timing reveals whether an access key exists.
  AWS distinguishes this case explicitly (`InvalidAccessKeyId`), so not
  counted.
- Bounds: more than 128 query parameters -> `Verify` returns `False` (403);
  more than 256 signed physical header occurrences or more than 128 signed
  names -> 400. Policy values; no stock client approaches them.
- Diagnostic drift on inputs no stock client produces: a declared-but-absent
  signed header -> 400 `AuthorizationHeaderMalformed` (AWS answers 403
  `SignatureDoesNotMatch`, from memory); trailing `&` or an empty query
  segment -> 403 `SignatureDoesNotMatch`.
- Query sort order is by encoded name (botocore behaviour); aws-sdk-go sorts
  raw keys before encoding, so the two SDK families disagree for keys mixing
  unreserved and reserved bytes in the 0x2D .. 0x2F range (for example `a-`
  versus `a/`). Ecosystem ambiguity, not a defect of this crate.
- `tools/s3-signed-socket.py` checks request-line, `Host`, header presence
  and `SignedHeaders` membership only; it never recomputes a signature, so
  the signed-socket qualification does not itself evidence signature
  correctness (the AUnit vectors do).
