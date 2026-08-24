# GetObject and HeadObject qualification and boundaries

This slice qualifies the authenticated general-purpose path-style server for
`GetObject` and `HeadObject`. Directory buckets, configured Requester Pays
accounting, encrypted SSE-C object state, and `GetObject` part-number projection
remain explicit capability exclusions rather than silently accepted behavior.

## Admission and security controls

Authentication and body rejection precede object-read semantics. Both routes
reject duplicate or empty conditional, range, owner, payer, checksum, and
encryption controls before storage. Expected-owner matching uses the verified
principal. Requester payer admits only the exact `requester` token, checksum
mode admits only `ENABLED`, and response overrides reject control bytes.

The three SSE-C headers form one indivisible group. The algorithm must be
exactly `AES256`, transport must be HTTPS, the key and MD5 must be valid Base64
at their fixed digest widths, and the MD5 must have been computed from the
decoded key. Malformed, incomplete, duplicate, insecure, algorithm-invalid, and
key/digest-mismatched requests fail before object bytes can be returned. The
borrowed key is used only for validation and is not retained or logged.
GetObject classifies a valid secure group as authenticated `NotImplemented`;
HeadObject checks the selected object's modeled encryption state and rejects the
group for an ordinary unencrypted object. Other encryption controls fail
explicitly. A combined bad-signature/control request gates authentication
precedence independently for each route.

## Selected snapshot and response

The backend evaluates all four HTTP conditions and the generation selector
against the same immutable object tuple used for metadata and bytes. Current and
explicit null selectors work across memory, files, and SQLite. Memory and SQLite
also select opaque retained generations; the pure-files backend reports its
typed exclusion for an opaque exact selector.

GetObject streams a whole or single resolved byte range with 64-bit lengths,
strict response framing, and no destination publication on typed client failure.
HeadObject emits no body, resolves ranges to their selected length, and can
select one retained multipart part with its raw checksum and part count. A
multipart range without `partNumber` omits checksum headers because the bounded
snapshot cannot atomically map an arbitrary range to all retained part
boundaries; it never substitutes the whole-object checksum.

## Adversarial evidence

The signed in-process corpus covers condition precedence, all three HTTP date
forms, malformed and duplicate entity tags and ranges, satisfied and
unsatisfied ranges, response overrides, current/null/exact selection, multipart
part selection, matching/mismatched/empty/duplicate owner, valid/invalid/empty/
duplicate payer and checksum controls, incomplete and duplicate SSE-C groups,
invalid algorithms, malformed keys, mismatched digests, plaintext SSE-C, valid
secure capability exclusions, unrelated encryption controls, and corrupt
signature precedence. The native/lightweight socket corpus adds fragmented
headers and bodies, 304/412 bodylessness, truncated or inconsistent framing,
and refusal to publish unsolicited range responses.

The qualified source passes the 40/40 AUnit root suite, 88 abrupt files-crash
cases, 320 checksum vectors, 210 chunk boundaries, the 64-GiB CRC linearization
oracle, signed server/application/socket/TLS corpora, the SQLite backend suite,
the 116-operation coverage verifier and negative oracle, and GNATdoc generation.
The admission repair is outside the SPARK manifest and changes no public API,
backend state, pagination algorithm, or scheduling boundary.
