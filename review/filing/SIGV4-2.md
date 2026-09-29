Title: Static_Credentials.Create accepts principals over 256 bytes, so every correctly signed request is 403
Labels: bug
Refs: none

## Summary

`Static_Credentials.Create` bounds the principal at `Maximum_Principal_Bytes`, which is 1_024, while `Authentication.Valid_Principal` rejects any principal longer than 256 bytes, mirroring the bound the HTTP layer's `Set_Principal` documents. A provider built with a principal of 257 to 1_024 bytes is accepted at construction and then fails admission on every request: the provider verifies the signature and returns the long principal, `Verify_Request` collapses the length rejection into `Credential_Rejected`, and the S3 layer answers 403 SignatureDoesNotMatch with "The request signature does not match". The signature did match, and neither the response nor either specification points at the principal, so the operator debugs a signing problem that does not exist.

## Problem

Commit `5fe6e3e`.

`Create`'s GNATdoc promises to reject a field that is too long (`src/flyology-object_storage-server-static_credentials.ads:18-31`):

```ada
   --  Copy one credential identity into bounded provider-owned storage.
   --  All retained fields are wiped during finalization. An empty Principal
   --  uses Access_Key as the authenticated principal name.
   --  @param Access_Key AWS access-key identifier
   --  @param Secret_Key AWS secret signing key
   --  @param Session_Token Optional required session token
   --  @param Principal Application principal reported after authentication
   --  @return Limited credential provider owning independent copies
   --  @exception Invalid_Credentials A field is empty, malformed, or too long
   function Create
     (Access_Key    : String;
      Secret_Key    : String;
      Session_Token : String := "";
      Principal     : String := "") return Provider;
```

"too long" is 1_024 bytes for the principal (`src/flyology-object_storage-server-static_credentials.ads:34-36`):

```ada
   Maximum_Credential_Bytes : constant := 1_024;
   Maximum_Session_Token_Bytes : constant := 8_192;
   Maximum_Principal_Bytes : constant := 1_024;
```

and `Create` enforces that bound and nothing narrower (`src/flyology-object_storage-server-static_credentials.adb:30-40`):

```ada
   begin
      if not Encoding.Valid_Access_Key (Access_Key)
        or else Access_Key'Length > Maximum_Credential_Bytes
        or else Secret_Key'Length = 0
        or else Secret_Key'Length > Maximum_Credential_Bytes
        or else Session_Token'Length > Maximum_Session_Token_Bytes
        or else Effective_Principal'Length = 0
        or else Effective_Principal'Length > Maximum_Principal_Bytes
      then
         raise Invalid_Credentials with "invalid static S3 credentials";
      end if;
```

Admission uses 256 (`src/flyology-object_storage-server-authentication.adb:18-22`):

```ada
   function Valid_Principal (Value : String) return Boolean is
   begin
      if Value'Length = 0 or else Value'Length > 256 then
         return False;
      end if;
```

256 is the figure the HTTP layer imposes on the principal the server installs, so `Valid_Principal` is a deliberate pre-check rather than dead code. The pinned flyology_http 0.1.3-dev release, `flyology-http-server-applications.ads:279-283`:

```ada
   --  Install an authenticated principal. Header control bytes and values
   --  longer than 256 bytes are rejected.
   --  @param Item Request exchange
   --  @param Value Application-defined principal
   procedure Set_Principal (Item : in out Exchange; Value : String);
```

The two bounds meet after the signature has already verified. `Authenticate` sets `Allowed` from the access-key comparison, the constant-time token compare and `Verification.Verify`, then returns the long principal (`src/flyology-object_storage-server-static_credentials.adb:80-88`):

```ada
      Allowed :=
        Verification.Access_Key (Authorization) = Access_Key (Item)
        and then Token_Matches
        and then Verification.Verify
          (Authorization, Method, Target, Headers, Payload_Hash,
           Secret_Key (Item));
      Principal :=
        (if Allowed then US.To_Unbounded_String (Principal_Name (Item))
         else US.Null_Unbounded_String);
```

`Verify_Request` then discards the distinction between a rejected signature and an over-long principal (`src/flyology-object_storage-server-authentication.adb:213-217`):

```ada
            if not Allowed
              or else not Valid_Principal (US.To_String (Principal))
            then
               return (Status => Credential_Rejected, others => <>);
            end if;
```

and the S3 layer renders that single status as a signature failure (`src/flyology-object_storage-server-s3_applications.adb:1907-1910`):

```ada
         when Authentication.Credential_Rejected =>
            Send_Error
              (X, 403, "SignatureDoesNotMatch",
               "The request signature does not match", Resource);
```

Neither specification publishes the 256-byte rule. `src/flyology-object_storage-server-authentication.ads:12-20` documents only that a provider must return "the same nonempty Principal" for every credential it accepts, and `static_credentials.ads` publishes 1_024.

There is a second route to the same failure. An empty `Principal` makes the access key the principal (`src/flyology-object_storage-server-static_credentials.adb:28-29`):

```ada
      Effective_Principal : constant String :=
        (if Principal'Length = 0 then Access_Key else Principal);
```

and `Create` accepts an access key of up to `Maximum_Credential_Bytes` alphanumerics, so an access key of 257 characters or more fails identically. The practical ceiling on that route is 477 characters, because `Parse_Credential` rejects credential text longer than 512 bytes (`src/flyology-object_storage-s3-sigv4_verification.adb:75`) and the `us-east-1/s3/aws4_request` scope consumes the rest. This route is established by reading, not by the spike.

Nothing tests it. `Static_Credentials` has no unit test at all: the package is not named anywhere in `tests/src/object_storage_test_cases.adb`. The two places that build a provider both use a short principal, `Principal => "test-principal"` in the server corpus (`tests/src/s3_server_application_corpus.adb:801-803`) and an environment-supplied identity in the qualification harness (`tests/src/s3_server_harness.adb:50-53`), so no assertion covers the bound and none has to change.

## What happens now

Spike: the program below records whether `Create` accepts a 300-byte principal, then sends one and the same correctly signed `PUT /principal-bucket` to two in-process S3 applications that differ only in the principal their static provider reports, 200 bytes against 300 bytes. Both use the same access key and secret, so the identical signed bytes verify against both. It asserts that a provider `Create` accepted authenticates the request. A helper unit declares the two applications and their memory backends.

```ada
   Long_Principal : constant String (1 .. 300) := (others => 'p');
...
         Probe : Static_Credentials.Provider := Static_Credentials.Create
           (Access_Key, Secret_Key, Principal => Long_Principal);
...
      Created : constant String :=
        Run_Short (Signed_Request ("PUT", "/principal-bucket"));
      Check (Status_Code (Created) = 200,
             "control: a 200-byte principal authenticates (200)");
...
      Created : constant String :=
        Run_Long (Signed_Request ("PUT", "/principal-bucket"));
      Check (Status_Code (Created) = 200,
             "a 300-byte principal accepted by Create authenticates (200)");
      Check (not Contains (Body_Of (Created),
                           "<Code>SignatureDoesNotMatch</Code>"),
             "a correct signature is never reported as " &
             "SignatureDoesNotMatch");
```

Output, exit status 1:

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
BUG REPRODUCED: 3 failed expectation(s)
```

`Create` accepted the 300-byte principal without raising, and the same signed request that succeeds against the 200-byte provider is refused as a signature failure against the 300-byte one. The failure is not intermittent and not request-dependent: every request against that provider gets the same answer.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A provider that `Create` returned must authenticate a correctly signed request, or `Create` must have raised `Invalid_Credentials`, which its GNATdoc promises for a field that is too long (`src/flyology-object_storage-server-static_credentials.ads:26`). Whichever length is authoritative, construction and admission must agree on it, and 403 SignatureDoesNotMatch must not be the answer to a signature that verified.

## Suggested treatment

Both bounds are interface values, so this needs a maintainer decision:

- Make the construction bound match admission: change `Maximum_Principal_Bytes` at `src/flyology-object_storage-server-static_credentials.ads:36` from 1_024 to 256, so `Create` raises `Invalid_Credentials` as documented. A visible private constant changes value, the provider's `Principal_Data` buffer shrinks, and `Create` starts rejecting principals it used to accept, which is a breaking change for any deployment that configured one.
- Keep the 1_024-byte storage bound and add an explicit 256-byte check to `Create`, so the storage capacity and the accepted range stop being the same number. No constant changes value, and `Create`'s accepted range still narrows.
- Keep both bounds and report the mismatch distinctly instead of as a signature failure, by adding an `Outcome_Status` literal to `src/flyology-object_storage-server-authentication.ads:41-48` and a mapping beside `src/flyology-object_storage-server-s3_applications.adb:1907-1910`. This widens the public outcome set and adds an S3 error code, and it leaves the long principal unusable, since `Set_Principal` still refuses it.

Publishing the 256-byte rule in `authentication.ads` and `static_credentials.ads` is worth doing under any of these, but on its own it does not close the defect, because `Create`'s `@exception Invalid_Credentials` promise would remain unmet. Whichever option is chosen, the access-key route needs the same treatment, since `Valid_Access_Key` admits up to `Maximum_Credential_Bytes` alphanumerics and an empty `Principal` promotes the access key to principal.

The regression test belongs in a new `Static_Credentials` case in `tests/src/object_storage_test_cases.adb`; the package has no unit test there today, so the case is new rather than an amendment. It should assert the chosen contract directly, either that `Create` with a 300-byte principal raises `Invalid_Credentials`, or that a provider `Create` accepted authenticates a corpus-style signed request end to end. The spike is the test.

## Severity

An operator who configures a static identity with a principal longer than 256 bytes, such as a tenant URN, a directory DN or an e-mail-style identifier, gets a server on which every correctly signed request fails. The outage is total for that deployment and the diagnostic is actively misleading, since 403 SignatureDoesNotMatch and "The request signature does not match" send the operator to the client's signing code while the signature verified. It needs an unusual configuration value, chosen once at deployment rather than per request, and `Create` gives no hint at the time it is chosen. Deterministic.
