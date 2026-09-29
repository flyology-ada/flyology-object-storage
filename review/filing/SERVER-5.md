Title: STREAMING-UNSIGNED-PAYLOAD-TRAILER is answered 400 AuthorizationHeaderMalformed instead of the 501 aws-chunked gets
Labels: bug
Refs: none

## Summary

`Verify_Request` treats "the payload hash is neither 64 hex digits nor `UNSIGNED-PAYLOAD`" as the same failure as a broken Authorization header, so a request carrying `x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER` is answered 400 `AuthorizationHeaderMalformed` with "The authorization header is malformed". That sentinel is what aws-cli v2 and boto3 send for PutObject and UploadPart over HTTPS, and the real cause is an unimplemented payload encoding, which the crate documents and reports correctly one branch away as 501 `NotImplemented` with "aws-chunked payloads are not implemented". The operator is told their credentials are wrong when the signature was never examined.

## Problem

Commit `5fe6e3e`.

The payload-hash shape check is one disjunct of the chain that returns `Malformed_Credentials` (`src/flyology-object_storage-server-authentication.adb:138-148`):

```ada
        or else
          (Payload_Hash /= SigV4.Unsigned_Payload
           and then not Encoding.Valid_SHA256_Hex (Payload_Hash))
        or else (Applications.Request_Header_Count
                   (X, "x-amz-security-token") > 0
                 and then (Applications.Request_Header_Count
                              (X, "x-amz-security-token") /= 1
                           or else not Verification.Header_Is_Signed
                             (Parsed.Data, "x-amz-security-token")))
      then
         return (Status => Malformed_Credentials, others => <>);
      end if;
```

That chain starts at `:130` and returns before the provider is asked to verify anything; the signature work begins in the block at `:177`. The S3 layer renders the single status as a signing complaint (`src/flyology-object_storage-server-s3_applications.adb:1889-1892`):

```ada
         when Authentication.Malformed_Credentials =>
            Send_Error
              (X, 400, "AuthorizationHeaderMalformed",
               "The authorization header is malformed", Resource);
```

The arm that describes the real situation is one branch away and is reached only when the payload hash has an ordinary shape (`src/flyology-object_storage-server-s3_applications.adb:14892-14895`):

```ada
                     Send_Error
                       (X, 501, "NotImplemented",
                        "aws-chunked payloads are not implemented",
                        Target_Text);
```

with the UploadPart twin at `:12618-12621`.

Rejecting `aws-chunked` framing is a documented limitation, and this issue does not ask for it to be implemented. `docs/compatibility/s3.md:342-345` states the boundary:

```
general-purpose profile, including fixed-length and HTTP transfer-chunked
streaming and physical checksum trailers. Inner SigV4 `aws-chunked` framing,
advanced policy controls, directory buckets, and HTTP/2 or HTTP/3 server
qualification remain explicit separate capabilities.
```

and `:457-459` repeats it:

```
server-compatibility boundary. SigV4 streaming `aws-chunked` payloads are also
rejected before reading the source until a signature-chain decoder is
available; ordinary application content encodings remain supported verbatim.
```

Two things keep this worth reporting. The documented exclusion names *SigV4 streaming* `aws-chunked`, while `STREAMING-UNSIGNED-PAYLOAD-TRAILER` is the unsigned variant, and `:342-343` positively claims physical checksum trailers, so the document does not name the sentinel a modern client actually sends. And neither sentence says anything about the status code, so a documented capability boundary is being reported with an error code that points at the wrong subsystem.

The sentinel is the current default over HTTPS. Captured from aws-cli/2.36.34 through a local TLS terminator holding a self-signed certificate, for `s3api put-object`:

```
PUT /live-bucket/tls.txt HTTP/1.1
Expect: 100-continue
Transfer-Encoding: chunked
Content-Encoding: aws-chunked
X-Amz-Trailer: x-amz-checksum-crc64nvme
X-Amz-Decoded-Content-Length: 15
x-amz-sdk-checksum-algorithm: CRC64NVME
X-Amz-Content-SHA256: STREAMING-UNSIGNED-PAYLOAD-TRAILER
Authorization: AWS4-HMAC-SHA256 Credential=..., SignedHeaders=content-encoding;host;x-amz-content-sha256;x-amz-date;x-amz-decoded-content-length;x-amz-sdk-checksum-algorithm;x-amz-trailer, Signature=...
```

Over plain `http://` the same client sends a fixed-length body with a header checksum instead, and the server accepts it: an ordinary `aws s3 cp` and `aws s3api put-object` both succeeded against the crate's own loopback listener. This crate ships no TLS listener, so the failing shape appears only when a TLS terminator sits in front of the server, which is the ordinary way to serve S3 over HTTPS.

No existing test covers a payload-hash sentinel that is neither hex nor `UNSIGNED-PAYLOAD`.

## What happens now

Spike: the program below sends PutObject and UploadPart with `Content-Encoding: aws-chunked`, `x-amz-decoded-content-length`, `x-amz-trailer` and `x-amz-content-sha256: STREAMING-UNSIGNED-PAYLOAD-TRAILER`, and asserts that the server does not blame the authorization header and answers the 501 it already uses for the same situation. Controls confirm that the same request with an ordinary hex payload hash gets exactly that 501, that an ordinary PutObject still succeeds, and that a well-shaped but wrong payload hash is still `XAmzContentSHA256Mismatch`. The sentinel is substituted into an otherwise ordinary signed request, which is faithful because the server decides before checking the signature, and necessary because the crate's own signer rejects that payload hash before producing a signature (`src/flyology-object_storage-s3-sigv4.adb:255-258`):

```ada
        or else (Payload_Hash /= Unsigned_Payload and then
                 not Encoding.Valid_SHA256_Hex (Payload_Hash))
      then
         raise Invalid_Signing_Input with "invalid SigV4 input";
```

The essential lines of the program:

```ada
   Chunked_Headers : constant String :=
     "Content-Encoding: aws-chunked" & CRLF &
     "x-amz-decoded-content-length: 15" & CRLF &
     "x-amz-sdk-checksum-algorithm: CRC64NVME" & CRLF &
     "x-amz-trailer: x-amz-checksum-crc64nvme" & CRLF;
...
      Response : constant String :=
        Run (With_Sentinel (Base, "STREAMING-UNSIGNED-PAYLOAD-TRAILER"));
   begin
      Check (not Contains (Body_Of (Response),
                           "<Code>AuthorizationHeaderMalformed</Code>"),
             "an unimplemented streaming payload encoding is not reported " &
             "as a malformed authorization header");
```

Output, exit status 1:

```
  ok: fixture: CreateBucket /stream-bucket
  -- PutObject with STREAMING-UNSIGNED-PAYLOAD-TRAILER + aws-chunked: status 400
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/stream-bucket/o</Resource></Error>
  FAILED: an unimplemented streaming payload encoding is not reported as a malformed authorization header
  FAILED: PutObject with STREAMING-UNSIGNED-PAYLOAD-TRAILER is 501 NotImplemented, like the aws-chunked path it belongs to
  -- UploadPart with STREAMING-UNSIGNED-PAYLOAD-TRAILER + aws-chunked: status 400
  --    body <?xml version="1.0" encoding="UTF-8"?><Error><Code>AuthorizationHeaderMalformed</Code><Message>The authorization header is malformed</Message><Resource>/stream-bucket/o?partNumber=1&amp;uploadId=0123456789abcdef</Resource></Error>
  FAILED: UploadPart does not report the streaming sentinel as a malformed authorization header
  -- CONTROL aws-chunked with an ordinary signed payload hash: status 501 body <?xml version="1.0" encoding="UTF-8"?><Error><Code>NotImplemented</Code><Message>aws-chunked payloads are not implemented</Message><Resource>/stream-bucket/o</Resource></Error>
  ok: CONTROL: aws-chunked with an ordinary hash is 501 NotImplemented
  ok: CONTROL: an ordinary PutObject still succeeds
  -- CONTROL a genuinely wrong (but well-shaped) payload hash: status 400 body <?xml version="1.0" encoding="UTF-8"?><Error><Code>XAmzContentSHA256Mismatch</Code><Message>The provided payload hash does not match the request body</Message><Resource>/stream-bucket/bad</Resource></Error>
  ok: CONTROL: a wrong payload hash is still rejected
```

The two controls are the point: the identical request with an ordinary payload hash is answered 501 with the correct explanation, and a genuinely wrong payload hash is answered with the code that names the payload hash. Only the recognised streaming sentinel is reported as a credentials problem.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A request whose payload hash is a recognised streaming sentinel the server does not implement should be reported as unimplemented, with the 501 `NotImplemented` and the "aws-chunked payloads are not implemented" message the crate already emits for the same situation, and not as a malformed authorization header. A payload hash that is genuinely unrecognisable should keep its current treatment.

## Suggested treatment

This changes where the boundary between authentication and the S3 application sits, so it needs a maintainer decision:

- Give `Verify_Request` a distinct outcome for a recognised-but-unimplemented streaming payload sentinel, and map it in `Send_Authentication_Error` beside `src/flyology-object_storage-server-s3_applications.adb:1889-1892`. This is a new literal in the visible `Authentication` outcome type, which the "Ada interface values" section of `AGENTS.md` reserves for the maintainer, and every consumer of that type gains an arm.
- Have the S3 application inspect `x-amz-content-sha256` for the streaming sentinels before calling `Verify_Request`, and answer 501 there. No public type changes, but it moves a decision ahead of authentication, so an unauthenticated caller could distinguish this build's streaming support from a generic rejection.

Either way the recognised set has to be written down: the unsigned trailer sentinel captured above alone, or the signed streaming payload sentinels as well. No `STREAMING-` value appears anywhere in `src/` or `docs/` today, so the set is new text either way. `docs/compatibility/s3.md:342-345` and `:457-459` should name the sentinel and the status code a client receives, since they currently describe the exclusion in terms of SigV4 streaming only.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, beside the existing aws-chunked admission cases, asserting the chosen status and code for a PutObject and an UploadPart carrying the sentinel. The spike is the test; no existing assertion has to change.

## Severity

Over plain HTTP, which is the only transport this crate serves, a stock PutObject does not use this shape and succeeds, so an ordinary deployment is unaffected. It matters once TLS fronts the server, which is the normal way to expose S3: aws-cli v2 and boto3 then send the sentinel on every PutObject and UploadPart, every upload fails, and the message accuses the operator's credentials while the signature was never checked. No data is at risk and the request is refused either way; what is wrong is the diagnosis, and it sends the operator to the signing code instead of to the documented streaming boundary. Deterministic.
