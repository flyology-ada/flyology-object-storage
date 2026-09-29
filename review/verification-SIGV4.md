# Adversarial verification: SigV4 signing, verification, admission, credentials

Scope verified by reading, at commit 5fe6e3e:
`src/flyology-object_storage-s3-sigv4.ads/.adb`,
`src/flyology-object_storage-s3-sigv4_encoding.ads/.adb`,
`src/flyology-object_storage-s3-sigv4_verification.ads/.adb`,
`src/flyology-object_storage-server-authentication.ads/.adb`,
`src/flyology-object_storage-server-static_credentials.ads/.adb`,
`src/flyology-object_storage-server-s3_applications.ads` and its body at
1875-1914 (outcome-to-error mapping), 3960-4110 (body hash, Content-MD5,
checksum and trailer enforcement), 6660-6702 (`Verify_Request` call site) and
17970-18066 (`Handle`'s exception handlers);
`docs/compatibility/s3.md:70-84, 445-486`;
`tests/repros/README.md`, `src/repro_support.ads`, `src/repro_s3_server.ads/.adb`.
Toolchain facts were re-derived from the toolchain this harness actually
resolves (`tests/repros/alire/alire.lock` pins `gnat_native` 16.1.0 and
`flyology_http` 0.1.3-dev at commit `eb09a80a`):
`.../gnat_native_16.1.0_657cf254/.../adainclude/a-calend.ads:48`,
`.../a-calend.adb` (`"-" (Left, Right : Time)`), `.../system.ads:154`, and
`~/.local/share/alire/releases/flyology_http_0.1.3_eb09a80a/src/flyology-http-server-applications.ads:102-157, 279-283`
plus `.../flyology-http.ads:45`.

Harness programs added: `tests/repros/src/repro_sigv4_1.adb`,
`tests/repros/src/repro_sigv4_2.adb`,
`tests/repros/src/repro_sigv4_support.ads/.adb` (a second and third in-process
S3 application whose static provider reports a 200-byte and a 300-byte
principal), and `tests/repros/src/repro_sigv4_probe.adb` (the evidence for the
"Checked, no finding" section; it PASSES). Nothing tracked was modified, no
Docker server was used, and nothing was committed.

Statements about AWS's own wire behaviour below are from my own knowledge and
are marked as such; the repository-grounded claims are all cited to file:line.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| SIGV4-1 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_sigv4_1.adb` |
| SIGV4-2 | CONFIRMED | P1 (P2) | `tests/repros/src/repro_sigv4_2.adb` |

No new finding emerged from the uncounted observations or from my own sweep of
the areas the discovery did not reach; the six probes I was asked to run and a
seventh control all behave as the sources and documents say they should. They
are recorded under "Checked, no finding" with their evidence.

---

### SIGV4-1: Far-future `x-amz-date` escapes `Verify_Request` as `Ada.Calendar.Time_Error`; 500 `InternalError` instead of 403 `RequestTimeTooSkewed`

**Verdict:** CONFIRMED. Every step of the discovery's mechanism holds at this
commit, and the observable 500 was demonstrated end to end through the
in-process S3 application.

**Severity:** P2 (discovery said P2; unchanged). It is a wrong diagnostic on
input no stock client produces, so it lands squarely on the rubric's P2 line
("wrong diagnostics ... needing unusual input"). I considered P1 on the
grounds that `Authentication.Verify_Request` is a public function whose
GNATdoc (`authentication.ads:56-60`) says the clock skew "is checked" and
whose `Outcome_Status` (`authentication.ads:41-48`) has a dedicated
`Request_Time_Too_Skewed` value, so an exception leaving it violates the
documented contract, and a third-party server built directly on
`Authentication` (rather than on `S3_Applications`, which contains the
exception) would see it propagate into its connection handler. I left it at P2
because the in-tree caller does contain it, the connection and process survive,
and no valid request reaches the path.

Verified by reading:

- `src/flyology-object_storage-s3-sigv4_encoding.adb:190-195` — `Valid_Timestamp`
  returns `Year > 0 and then Month in 1 .. 12 and then ...`. There is no upper
  year bound anywhere in the unit; `23900101T000000Z` is accepted.
- `src/flyology-object_storage-server-authentication.adb:57-69` —
  `Timestamp_Time` converts through `Ada.Calendar.Year_Number` and its handler
  covers only `Constraint_Error | Ada.Calendar.Time_Error` **inside that
  function**.
- `src/flyology-object_storage-server-authentication.adb:157-165` — the skew
  test evaluates `Request_Time - Now` in a `declare` block in `Verify_Request`,
  outside `Timestamp_Time`.
- `src/flyology-object_storage-server-authentication.adb:224-227` —
  `Verify_Request`'s own handler is `when Constraint_Error =>` only.
- `.../gnat_native_16.1.0_657cf254/.../adainclude/a-calend.ads:48` —
  `subtype Year_Number is Integer range 1901 .. 2399`, so 2390 converts
  cleanly.
- The same toolchain's `a-calend.adb`, `function "-" (Left : Time; Right : Time)
  return Duration`, raises `Time_Error` when `Res_N` leaves `Duration`'s range
  and its handler converts any internal `Constraint_Error` into `Time_Error`.
  `Constraint_Error` is therefore never what escapes.
- `.../gnat_native_16.1.0_657cf254/.../adainclude/system.ads:154` —
  `Duration_32_Bits : constant Boolean := False`, so `Duration'Last` is
  9,223,372,036.854775807 s = 292.277 years. For a clock at 2026-09-07T01:37Z
  the overflow threshold is 2318-12-18T01:24Z and it advances one day per day
  (computed in this session); the past side cannot overflow because
  2026 − 292 is below the 1901 floor.
- `src/flyology-object_storage-server-s3_applications.adb:6697` calls
  `Authentication.Verify_Request` directly in `Handle`'s statement sequence
  (`procedure Handle` begins at :2017), so the exception meets `Handle`'s
  `when others` at :18056-18065, which sends `500 InternalError` because no
  response has been started.
- `src/flyology-object_storage-server-s3_applications.adb:1893-1897` is the
  mapping that should have run: `Request_Time_Too_Skewed` → 403
  `RequestTimeTooSkewed`.

Refutation attempts that failed:

- *Maybe the harness's toolchain differs from the one the discovery inspected.*
  It does — `tests/repros/alire/alire.lock` resolves `gnat_native` 16.1.0, not
  the 16.2.0 Flyology toolchain — but `Year_Number`, `Duration_32_Bits` and the
  `Time_Error`-raising `"-"` are byte-identical in it, so the conclusion is
  toolchain-independent across every native GNAT on this host.
- *Maybe `SigV4.Sign` refuses to sign such a timestamp, so the request cannot be
  built.* `Sign` validates the timestamp only through the same
  `Valid_Timestamp` (`sigv4.adb:254`), so a year-2390 request signs normally;
  the repro's `Signed_Request` produced one.
- *Maybe the scope-date check at `authentication.adb:151-153` rejects it first.*
  It does not: the credential scope is derived from the same stamp, so scope
  date and `x-amz-date` day agree and the check passes. My probe separately
  confirms that a scope/date mismatch really is caught (400) when it exists.
- *Maybe the exception is caught by a nearer handler.* The `Send_Error` at
  :18062 is the one that fires, and the response body proves it
  (`<Code>InternalError</Code>`).
- *Maybe an existing test already asserts 403 here.*
  `rg RequestTimeTooSkewed tests/ server/tests/` finds no assertion, and no
  test sends an `x-amz-date` outside 2013.
- *Maybe it is only reachable by an authenticated peer.* It is not: the check
  runs before `Credentials.Authenticate` is invoked (:209), so a peer with no
  valid key at all can elicit the 500, as the repro does with a signature over
  a key the fixture happens to know but that is never consulted on this path.

**Repro:** `tests/repros/src/repro_sigv4_1.adb`. It uses the in-process S3
application, creates a bucket with an ordinary signed request (control 1),
sends the same routed request with `x-amz-date: 20200101T000000Z` to show that
a moderately skewed date is diagnosed correctly (control 2), then sends it with
`x-amz-date: 23900101T000000Z` and asserts the answer is 403
`RequestTimeTooSkewed` and specifically not 500. 2390 is chosen so the result
does not depend on the day the program runs.

**Output** (`cd tests/repros && ./run.sh repro_sigv4_1`, exit status **1**):

```
  -- control CreateBucket: status 200
  -- control CreateBucket: body 
  ok: control: a correctly signed CreateBucket is 200
  -- x-amz-date 20200101T000000Z: status 403
  -- x-amz-date 20200101T000000Z: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>RequestTimeTooSkewed</Code><Message>The difference between the request time and the current time is too large</Message><Resource>/skew-bucket</Resource></Error>
  ok: control: x-amz-date 20200101T000000Z is 403
  ok: control: x-amz-date 20200101T000000Z is RequestTimeTooSkewed
  -- x-amz-date 23900101T000000Z: status 500
  -- x-amz-date 23900101T000000Z: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error</Message><Resource>/skew-bucket</Resource></Error>
  FAILED: x-amz-date 23900101T000000Z is not answered with 500
  FAILED: x-amz-date 23900101T000000Z is 403
  FAILED: x-amz-date 23900101T000000Z is RequestTimeTooSkewed
BUG REPRODUCED: 3 failed expectation(s)
```

**Description:** `SigV4_Encoding.Valid_Timestamp` puts no upper bound on the
year (`sigv4_encoding.adb:190`), so an `x-amz-date` anywhere in
`Ada.Calendar.Year_Number` (1901 .. 2399 on GNAT) survives admission and is
converted to an `Ada.Calendar.Time` by `Authentication.Timestamp_Time`. The
clock-skew test then evaluates `Request_Time - Now`
(`authentication.adb:157-165`) outside that function's guard. On 64-bit
`Duration` the difference overflows for any request time more than 292.277
years from the trusted clock — today, from 2318-12-18 to the 2399 ceiling — and
GNAT's `"-" (Time, Time)` raises `Ada.Calendar.Time_Error`, which
`Verify_Request`'s handler (`when Constraint_Error`, :225) does not catch. The
exception leaves the public `Verify_Request`, reaches `S3_Applications.Handle`'s
catch-all (:18056) and becomes `500 InternalError` for any routed request,
sent to an unauthenticated peer, instead of the `403 RequestTimeTooSkewed` that
`:1893-1897` exists to produce. It is fully deterministic and needs no valid
credentials, because the check runs before the credential provider is invoked
(:209). Operators alert on 5xx, and aws-cli/boto3 retry 500 with backoff rather
than failing fast (from my own knowledge of their retry policy, not verified
here). Same family, already handled correctly: years 0001 .. 1900 fail
`Year_Number` inside `Timestamp_Time` and yield 400
`AuthorizationHeaderMalformed`. No existing test asserts either case. A fix
needs one maintainer decision: whether `Valid_Timestamp` should gain an
explicit accepted-year range (a new public policy bound in a SPARK unit, so it
falls under the repository's rule on specification values), or whether
`Verify_Request` should simply widen its handler to `Constraint_Error |
Ada.Calendar.Time_Error` and return `Request_Time_Too_Skewed` — the latter
introduces no new interface value and preserves the documented outcome set.

---

### SIGV4-2: `Static_Credentials.Create` accepts principals of 257 .. 1,024 bytes that admission then rejects, so every correctly signed request is answered 403 `SignatureDoesNotMatch`

**Verdict:** CONFIRMED. `Create` accepts a 300-byte principal without raising,
and the identical signed request that succeeds against a 200-byte principal is
answered 403 `SignatureDoesNotMatch` against the 300-byte one.

**Severity:** P1 (discovery said P2). Corrected because the failing path takes
*valid* input — an ordinary, correctly signed request — and returns a wrong
result through a reachable path, which is the rubric's P1 line; and because
`Static_Credentials.Create`'s own GNATdoc
(`static_credentials.ads:26`, `@exception Invalid_Credentials A field is empty,
malformed, or too long`) promises to reject a field that is too long and
instead accepts one the system cannot use, which is the rubric's "documented
contract violated". P2's qualifier "needing unusual input" does not fit: the
unusual value is a constructor argument chosen once at deployment, after which
*every* request fails with a diagnostic that points at the client's signature.
I record the discovery's P2 as defensible on the grounds that a >256-byte
principal is an unusual configuration.

Verified by reading:

- `src/flyology-object_storage-server-static_credentials.ads:34-36` —
  `Maximum_Credential_Bytes : constant := 1_024;`
  `Maximum_Session_Token_Bytes : constant := 8_192;`
  `Maximum_Principal_Bytes : constant := 1_024;`
- `src/flyology-object_storage-server-static_credentials.adb:31-48` — `Create`
  checks only `Effective_Principal'Length = 0`, `> Maximum_Principal_Bytes`,
  and a control-byte scan. Nothing mentions 256.
- `src/flyology-object_storage-server-static_credentials.adb:80-88` —
  `Authenticate` sets `Allowed` from the access-key comparison, the
  constant-time token compare and `Verification.Verify`, and returns
  `Principal_Name (Item)` whenever `Allowed`.
- `src/flyology-object_storage-server-authentication.adb:18-31` —
  `Valid_Principal` returns `False` for `Value'Length > 256`.
- `src/flyology-object_storage-server-authentication.adb:213-217` — `not
  Allowed or else not Valid_Principal (...)` collapses both cases into
  `Credential_Rejected`, discarding the distinction.
- `src/flyology-object_storage-server-s3_applications.adb:1907-1910` —
  `Credential_Rejected` → `403 SignatureDoesNotMatch`, "The request signature
  does not match".
- `flyology_http` 0.1.3 `flyology-http-server-applications.ads:279-283` — the
  256-byte figure is that layer's contract for `Set_Principal`, so
  `Valid_Principal` is a deliberate pre-check, not dead code; the drift is on
  `Create`'s side.
- `src/flyology-object_storage-server-authentication.ads:17-20` documents only
  "the same nonempty Principal"; neither it nor `static_credentials.ads`
  publishes the 256-byte limit.

Refutation attempts that failed:

- *Maybe `Create` rejects it and the discovery misread the bound.* It does not;
  the repro calls `Static_Credentials.Create (..., Principal => 300 bytes)`
  inside an `Invalid_Credentials` handler and prints `accepted: TRUE`.
- *Maybe some other check clamps the principal before admission.*
  `rg` over `Valid_Principal` finds the single call site at
  `authentication.adb:214`; `Principal_Name` is returned verbatim from the
  provider's fixed buffer.
- *Maybe the harness's own principal is what makes the control pass.* The
  control and the finding use two applications built from the same generic with
  the same access key and secret, the same policy, and the same signed request
  bytes; the only difference is the provider's `Principal` argument (200 vs 300
  bytes). Both are declared in
  `tests/repros/src/repro_sigv4_support.ads/.adb`.
- *Maybe it is unreachable because operators always leave `Principal` empty.*
  Leaving it empty makes `Access_Key` the principal
  (`static_credentials.adb:28-29`), and `Valid_Access_Key` accepts up to
  `Maximum_Credential_Bytes` = 1,024 alphanumerics (:31-32), so an access key
  of 257 .. 477 characters reaches the identical failure — 477 being the
  ceiling imposed by `Parse_Credential`'s 512-byte credential-text bound
  (`sigv4_verification.adb:75`) for an `us-east-1`/`s3` scope. That is a second
  route to the same defect, established by reading, not by the repro.
- *Maybe an existing test covers it.*
  `rg Static_Credentials tests/src/object_storage_test_cases.adb` is empty; the
  corpus uses `Principal => "test-principal"` and the harness `"qualification"`.

**Repro:** `tests/repros/src/repro_sigv4_2.adb` with helper
`tests/repros/src/repro_sigv4_support.ads/.adb`. The helper instantiates two
further `S3_Applications` over their own memory backends, identical to the
shared one except that their `Static_Credentials.Provider` reports a 200-byte
and a 300-byte principal respectively; both reuse
`Repro_S3_Server.Access_Key`/`Secret_Key`, so `Repro_S3_Server.Signed_Request`
signs for both. The program first records whether `Create` accepts the 300-byte
principal, then sends the same signed `PUT /principal-bucket` to each
application and asserts the 300-byte one authenticates.

**Output** (`cd tests/repros && ./run.sh repro_sigv4_2`, exit status **1**):

```
  -- Static_Credentials.Create with a 300-byte principal accepted: TRUE
  -- control (200-byte principal) CreateBucket: status 200
  -- control (200-byte principal) CreateBucket: body 
  ok: control: a 200-byte principal authenticates (200)
  -- 300-byte principal CreateBucket: status 403
  -- 300-byte principal CreateBucket: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>SignatureDoesNotMatch</Code><Message>The request signature does not match</Message><Resource>/principal-bucket</Resource></Error>
  FAILED: a principal Create accepted is not rejected at admission
  FAILED: a 300-byte principal accepted by Create authenticates (200)
  FAILED: a correct signature is never reported as SignatureDoesNotMatch
```

**Description:** `Static_Credentials` bounds the principal at
`Maximum_Principal_Bytes` = 1,024 (`static_credentials.ads:36`) and `Create`
enforces only that (`static_credentials.adb:36-37`), while
`Authentication.Valid_Principal` rejects anything over 256 bytes
(`authentication.adb:20`) because that is `flyology_http`'s `Set_Principal`
contract. An operator who configures a static identity with a 257 .. 1,024-byte
principal — a tenant URN, a DN, an e-mail-style identifier — or, equivalently,
with an access key of 257 .. 477 characters and an empty `Principal`, gets a
provider that `Create` accepted and a server on which **every** correctly
signed request fails. The failure is deterministic and total: `Authenticate`
verifies the signature successfully and returns the long principal
(`static_credentials.adb:80-88`), then `authentication.adb:213-217` collapses
the length rejection into the same `Credential_Rejected` status that a genuinely
bad signature produces, and `s3_applications.adb:1907-1910` renders it as 403
`SignatureDoesNotMatch` / "The request signature does not match". Nothing in
the response, and nothing in `Static_Credentials.ads` or
`Authentication.ads`, points at the principal, so the operator debugs a
signature problem that does not exist. There is no existing test on
`Static_Credentials`, so nothing asserts the wrong behaviour today. A fix needs
one maintainer decision, because the two bounds are both interface values: either
`Maximum_Principal_Bytes` drops to the 256 the HTTP layer imposes (a visible
private constant changes value, and `Create` starts raising
`Invalid_Credentials` for inputs it used to accept), or `Authentication` stops
treating an over-long principal as `Credential_Rejected` and reports it
distinctly (a new `Outcome_Status` literal and a new S3 error mapping). Merely
documenting 256 in `Authentication.ads` would leave `Create`'s
`@exception Invalid_Credentials ... too long` promise unmet.

---

## Checked, no finding

All of the following were exercised against the running in-process application
by `tests/repros/src/repro_sigv4_probe.adb`, which **passes** (exit 0). Its
full output is reproduced once at the end of this section, because it is the
evidence for every item.

**(a) HTTPS-only `UNSIGNED-PAYLOAD` is genuinely enforced on plain HTTP.**
`authentication.adb:171-175` reads `elsif Payload_Hash = SigV4.Unsigned_Payload
and then Applications.Request_Scheme (X) /= Flyology.HTTP.Secure_HTTPS`. I
checked the `if/elsif` chain it belongs to: the preceding branch is the region
pin (:166-169), so the `elsif` is evaluated whenever the region check does not
fire, including when `Expected_Region` is empty — there is no path that skips
it. `flyology_http`'s `Origin_Scheme` defaults to `Plain_HTTP`
(`flyology-http.ads:45, 114`) and the harness has no TLS, so the probe's
`PUT` with `Hash_Override => "UNSIGNED-PAYLOAD"` and a 26-byte body that no
signature covers is refused with `400 InvalidRequest` / "UNSIGNED-PAYLOAD
requires a secure transport", and a follow-up `GET` returns 404, so the
unsigned body was never published. Not a defect; the discovery's separate note
that this refuses SDK defaults behind a TLS-terminating proxy remains a policy
observation for the SERVER area.

**(b) Two `Authorization` fields are rejected.**
`authentication.adb:130-133` returns `Missing_Credentials` at count 0 and
`Malformed_Credentials` at any count other than 1, before `Parse`'s result is
consulted. The probe duplicates the signed `Authorization` line verbatim and
gets `400 AuthorizationHeaderMalformed`.

**(b) `Authorization` plus query-string `X-Amz-Signature` is rejected, but by
the operation's query validator, not by an auth-mechanism rule.** The probe
signs `GET /probe-bucket` with `X-Amz-Algorithm`, `X-Amz-Credential`,
`X-Amz-Date`, `X-Amz-Expires` and `X-Amz-Signature` in the query, so the header
signature covers them; the request authenticates and then ListObjects' query
member validation answers `400 InvalidArgument` / "The ListObjects request is
invalid". AWS answers 400 too, with `InvalidArgument` / "Only one auth
mechanism allowed" (from my own knowledge, not verified here), so the status
agrees and only the message differs. I did not raise this as a finding: no
signature check is weakened (the query is part of the canonical request), the
request is refused, and presigning is out of scope (see (f)). The residual
theoretical case — an operation whose query validator tolerates unknown
members would accept such a request — is a SERVER-area question about query
validation, not a SigV4 defect, since the request is fully signed either way.

**(c) A padded, mixed-case signed header verifies in both directions.** The
probe sends `X-Amz-Meta-Note:   spaced   out   ` on a signed `PUT` and gets
200. Client and server both go through the same
`SigV4.Canonical_Headers` → `Encoding.Lowercase` + `Encoding.Normalize_Header_Value`
(`sigv4.adb:188-190`, `sigv4_encoding.adb:62-91`), which trims and folds
space/tab runs, and the server collects occurrences under the lowercase name
declared in `SignedHeaders` (`authentication.adb:199-206`), so the wire form
and the signed form cannot diverge.

**(c) A header named in `SignedHeaders` but absent from the request is
rejected.** `authentication.adb:196-198` returns `Malformed_Credentials` when
`Request_Header_Count (X, Name) = 0`. The probe signs an `x-amz-meta-note`
header and deletes the field from the wire: `400
AuthorizationHeaderMalformed`. AWS answers `403 SignatureDoesNotMatch` here
(from my own knowledge); that is diagnostic drift on input no stock client
produces, already listed by the discovery, and I agree it is not a finding.

**(c) A physical `x-amz-*` header that `SignedHeaders` does not name is
rejected.** `All_Amazon_Headers_Signed` (`authentication.adb:92-109`) scans
every physical field. The probe injects `x-amz-meta-extra: injected` after
signing: `400 AuthorizationHeaderMalformed`. This stricter-than-AWS rule is
documented at `docs/compatibility/s3.md:452-457`.

**(d) A credential scope date that differs from the `x-amz-date` day is
rejected.** Enforced twice: `authentication.adb:151-153` compares
`Verification.Scope_Date` with the first eight timestamp bytes before the skew
test, and `sigv4_verification.adb:413-419` repeats it inside `Verify`. The
probe rewrites only the `Credential=` scope day and gets `400
AuthorizationHeaderMalformed`.

**(e) An uppercase-hex `x-amz-content-sha256` is not accepted, even when the
body matches.** `authentication.adb:139-140` requires
`Encoding.Valid_SHA256_Hex`, which accepts `0-9a-f` only
(`sigv4_encoding.adb:130`), so the request is refused at admission with `400
AuthorizationHeaderMalformed` before any signature or body work. `SigV4.Sign`
applies the same rule (`sigv4.adb:255-256`), so this crate's own client cannot
emit one either. It fails closed, which is the important property; whether AWS
would accept it is a compatibility question I cannot settle from the
repository. Worth noting for the maintainer, not as a defect: the body-hash
comparison at `s3_applications.adb:4055-4057` does apply
`Encoding.Lowercase` to the expected hash, so that layer would have tolerated
uppercase had admission not already excluded it.

**(f) Presigned query authentication is not claimed, and a presigned-style
request gets a clean 403.** `docs/compatibility/s3.md:78` reads
`| SigV4 presigning | n/a | planned | not claimed |`. The probe sends a
presigned-shaped `GET` carrying `X-Amz-Algorithm`, `X-Amz-Credential`,
`X-Amz-Date`, `X-Amz-Expires=900`, `X-Amz-SignedHeaders` and `X-Amz-Signature`
with no `Authorization` field and no `x-amz-content-sha256`: `403 AccessDenied`
via `Missing_Credentials` (`authentication.adb:130-131`), no exception, no 500.
This also establishes the ordering the (b) result depends on — authentication
runs before the operation's query validation, since the same unknown query
members produced the auth error here and the query error there. DOCUMENTED
LIMITATION.

**(g) Control I added: the signed payload hash really binds the body.** Signing
`x-amz-content-sha256` for `"AAAA"` and sending `"BBBB"` yields `400
XAmzContentSHA256Mismatch` (`s3_applications.adb:4055-4059` →
`:18003-18011`) and the object is not published (follow-up `GET` is 404). This
is the property that makes (a) and (e) safe to leave as they are.

Additional items I checked by reading only, with no probe:

- **Request trailers are not an unsigned-input hole.** The trailer path is
  gated by the `x-amz-trailer` request header
  (`s3_applications.adb:3821, 5039, 5116, ...`), which is `x-amz-*` and
  therefore must appear in `SignedHeaders`; `Reject_Unexpected_Trailers`
  (`:4073-4078`) raises `Body_Checksum_Invalid` for any trailer that was not
  declared, and `:4079-4088` requires exactly the one declared trailer. Nothing
  unsigned reaches a decision.
- **`x-amz-s3session-token` is unbound but harmless here.** It is `x-amz-*`, so
  it must be signed, and there are no session credentials to confuse it with:
  `s3_applications.ads:49-50` describes CreateSession as "validated
  negative-capability routing" and `docs/compatibility/s3.md:72` records
  "server absent" for it. This stays a SERVER-area observation, as the
  discovery said.
- **`Verify`'s `Signed_Headers = Declared_Signed_Headers` check cannot fail via
  the server path**, because `authentication.adb:189-208` builds the array from
  the declared, strictly-ascending list itself
  (`sigv4_verification.adb:128-130`) and `Canonical_Headers` sorts by the same
  key. It is a real guard only for third-party providers that call
  `Verification.Verify` with their own header set; that is defensive, not
  drift.
- **`Constant_Time_Equal` (`sigv4.adb:322-342`)** folds the length difference
  into the accumulator, iterates to the longer length and substitutes a fixed
  byte past the end, with no data-dependent exit. I re-derived it; the
  discovery's assessment stands.

**Probe output** (`cd tests/repros && ./run.sh repro_sigv4_probe`, exit status
**0**):

```
  -- fixture CreateBucket: status 200
  -- fixture CreateBucket: body 
  ok: fixture: CreateBucket is 200
  -- (a) UNSIGNED-PAYLOAD on plain HTTP: status 400
  -- (a) UNSIGNED-PAYLOAD on plain HTTP: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidRequest</Code><Message>UNSIGNED-PAYLOAD requires a secure transport</Message><Resource>/probe-bucket/unsigned</Resource></Error>
  ok: (a) UNSIGNED-PAYLOAD over plain HTTP is refused with 400
  ok: (a) UNSIGNED-PAYLOAD over plain HTTP reports InvalidRequest
  -- (a) GET after refused UNSIGNED-PAYLOAD: status 404
  -- (a) GET after refused UNSIGNED-PAYLOAD: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist</Message><Resource>/probe-bucket/unsigned</Resource></Error>
  ok: (a) the refused UNSIGNED-PAYLOAD body was not stored
  -- (b) two Authorization fields: status 400
  -- (b) two Authorization fields: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/probe-bucket</Resource></Error>
  ok: (b) two Authorization fields are not accepted
  ok: (b) two Authorization fields do not raise an internal error
  -- (b) Authorization plus X-Amz-Signature query: status 400
  -- (b) Authorization plus X-Amz-Signature query: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjects request is invalid</Message><Resource>/probe-bucket?X-Amz-Algorithm=AWS4-HMAC-SHA256&amp;X-Amz-Credential=AKIDEXAMPLE/20260907/us-east-1/s3/aws4_request&amp;X-Amz-Date=20260907T013714Z&amp;X-Amz-Expires=900&amp;X-Amz-Signature=0000000000000000000000000000000000000000000000000000000000000000</Resource></Error>
  ok: (b) header auth plus presigned query is not an internal error
  -- (c) padded mixed-case signed header: status 200
  -- (c) padded mixed-case signed header: body 
  ok: (c) a padded, mixed-case signed x-amz-* header verifies
  -- (c) declared-but-absent signed header: status 400
  -- (c) declared-but-absent signed header: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/probe-bucket</Resource></Error>
  ok: (c) a declared but absent signed header is not accepted
  ok: (c) a declared but absent signed header is not a 500
  -- (c) unsigned physical x-amz-* header: status 400
  -- (c) unsigned physical x-amz-* header: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/probe-bucket</Resource></Error>
  ok: (c) an unsigned physical x-amz-* header is not accepted
  ok: (c) an unsigned physical x-amz-* header is not a 500
  -- (d) x-amz-date day 20260907, credential scope day 20260901
  -- (d) scope date mismatch: status 400
  -- (d) scope date mismatch: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/probe-bucket</Resource></Error>
  ok: (d) a scope date that differs from x-amz-date is refused
  ok: (d) a scope date mismatch is not a 500
  -- (e) sent x-amz-content-sha256: E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855
  -- (e) uppercase content digest: status 400
  -- (e) uppercase content digest: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/probe-bucket</Resource></Error>
  ok: (e) an uppercase x-amz-content-sha256 is not accepted
  ok: (e) an uppercase x-amz-content-sha256 is not a 500
  -- (f) presigned-style query request: status 403
  -- (f) presigned-style query request: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AccessDenied</Code><Message>Access Denied</Message><Resource>/probe-bucket?X-Amz-Algorithm=AWS4-HMAC-SHA256&amp;X-Amz-Credential=AKIDEXAMPLE%2F20260907%2Fus-east-1%2Fs3%2Faws4_request&amp;X-Amz-Date=20260907T013714Z&amp;X-Amz-Expires=900&amp;X-Amz-SignedHeaders=host&amp;X-Amz-Signature=0000000000000000000000000000000000000000000000000000000000000000</Resource></Error>
  ok: (f) a presigned-style request is not accepted
  ok: (f) a presigned-style request is a clean refusal, not a 500
  -- (g) signed hash of AAAA with body BBBB: status 400
  -- (g) signed hash of AAAA with body BBBB: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>XAmzContentSHA256Mismatch</Code><Message>The provided payload hash does not match the request body</Message><Resource>/probe-bucket/mismatch</Resource></Error>
  ok: (g) a body that does not match the signed hash is 400
  ok: (g) the mismatch reports XAmzContentSHA256Mismatch
  -- (g) GET after payload-hash mismatch: status 404
  -- (g) GET after payload-hash mismatch: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist</Message><Resource>/probe-bucket/mismatch</Resource></Error>
  ok: (g) the mismatched body was not published
PASS
```

## Harness

No harness problem. `tests/repros/run.sh` built and ran the three programs
added here — the two reproductions and the probe — without incident under its
build lock, and the control assertions in every one of them passed, so a
`BUG REPRODUCED` result is attributable to the finding rather than to the
harness. `git status --short` shows only untracked additions under `review/`
and `tests/repros/`.
