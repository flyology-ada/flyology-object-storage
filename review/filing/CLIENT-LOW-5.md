Title: Prepare_Create_Session rejects the explicit Bucket_Key_Enabled False its specification says is preserved
Labels: bug
Refs: none

## Summary

`Create_Session_Parameters` is documented as preserving absent versus explicit `false` for `Bucket_Key_Enabled`, and `Prepare_Create_Session` raises `Invalid_Request` on exactly the explicit `false` that promise describes, with a message that does not name the member. The serialiser that would have emitted the value hard-codes the string `"true"` and never reads the caller's boolean, so if the policy check were relaxed the request would carry `true` for a caller who asked for `false`. The specification and the code cannot both be right, and the `"true"` literal is wrong under either answer.

## Problem

Commit `5fe6e3e`.

The published contract promises presence preservation (`src/flyology-object_storage-client-low_level.ads:6402-6409`):

```ada
   --  Every non-resource member in the pinned CreateSession input. Empty
   --  strings preserve omission; Bucket_Key_Enabled preserves absent versus
   --  explicit false.
   --  @field Session_Mode Optional modeled session mode
   --  @field Server_Side_Encryption Optional encryption algorithm
   --  @field SSE_KMS_Key_ID Optional KMS key identifier
   --  @field SSE_KMS_Encryption_Context Optional canonical Base64 KMS context
   --  @field Bucket_Key_Enabled Presence-preserving bucket-key request flag
```

The policy validator refuses that value (`src/flyology-object_storage-client-low_level.adb:2430-2434`):

```ada
        or else (Bucket_Key_Enabled.Is_Set
                 and then not Bucket_Key_Enabled.Value)
      then
         raise Invalid_Response with Failure;
      end if;
```

and `Prepare_Create_Session` remaps that raise to an `Invalid_Request` whose message names no member (`src/flyology-object_storage-client-low_level.adb:2474-2484`):

```ada
      begin
         Validate_Create_Session_Policy
           (Parameters.Server_Side_Encryption,
            Parameters.SSE_KMS_Key_ID,
            Parameters.SSE_KMS_Encryption_Context,
            Parameters.Bucket_Key_Enabled,
            "invalid CreateSession request policy");
      exception
         when Invalid_Response =>
            raise Invalid_Request with "invalid CreateSession parameters";
      end;
```

The serialiser that runs when the flag is set ignores the caller's boolean entirely (`src/flyology-object_storage-client-low_level.adb:2496-2502`):

```ada
      if Parameters.Bucket_Key_Enabled.Is_Set then
         Last := Last + 1;
         Values (Last) :=
           (Member_Name => US.To_Unbounded_String ("BucketKeyEnabled"),
            Map_Key => US.Null_Unbounded_String,
            Value => US.To_Unbounded_String ("true"));
      end if;
```

so the only reason a `false` never reaches the wire as `true` today is that the check at `:2430` fires first. Nothing in the file ties the two together.

The pinned model admits `false`, and its own documentation explains why a server might not. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`, with HTML stripped from the documentation string:

```python
sh = model['shapes']['CreateSessionRequest']
print('CreateSessionRequest required:', sh.get('required'))
m = sh['members']['BucketKeyEnabled']
print(' BucketKeyEnabled:', {k: m[k] for k in ('shape', 'location', 'locationName')})
print(' shape kind:', model['shapes'][m['shape']]['type'])
```

```
CreateSessionRequest required: ['Bucket']
 BucketKeyEnabled: {'shape': 'BucketKeyEnabled', 'location': 'header', 'locationName': 'x-amz-server-side-encryption-bucket-key-enabled'}
 shape kind: boolean
```

with the member's documentation beginning

```
Specifies whether Amazon S3 should use an S3 Bucket Key for object encryption with server-side encryption using KMS keys (SSE-KMS). S3 Bucket Keys are always enabled for GET and PUT operations in a directory bucket and can’t be disabled.
```

So refusing `false` may well be the right wire behaviour for a directory bucket. That does not remove the defect, it relocates it: either the specification at `:6402-6404` is wrong to promise that explicit `false` is preserved, or the check at `:2430-2431` is wrong to refuse it. The two cannot both stand, and the `"true"` literal at `:2501` is a latent value inversion under either answer.

One existing test pins the current rejection, so it is part of the decision rather than a safety net. `tests/src/object_storage_test_cases.adb:14311-14316` builds an SSE-KMS parameter set and requires preparation to raise:

```ada
         Parameters.SSE_KMS_Encryption_Context := US.Null_Unbounded_String;
         Parameters.Bucket_Key_Enabled :=
           (Is_Set => True, Value => False);
         Reject_Prepare
           (Parameters,
            Message => "CreateSession accepted disabled bucket key");
```

where `Reject_Prepare` (`tests/src/object_storage_test_cases.adb:14173-14198`) asserts that `Prepare_Create_Session` raises `Invalid_Request`. Nothing tests what the specification promises, and nothing tests the `"true"` literal against a `False` value, because that path is unreachable while the check stands.

## What happens now

Spike: the program below prepares a CreateSession request against an HTTPS virtual-hosted S3 Express origin with `SessionMode = ReadWrite`, `ServerSideEncryption = aws:kms` and a KMS key ARN, three times: with `Bucket_Key_Enabled = (Is_Set => True, Value => False)`, with the flag absent, and with an explicit `True`. It asserts that preparation succeeds and that the canonical request carries the header with the requested value. No server is involved.

```ada
      Parameters.Session_Mode := US.To_Unbounded_String ("ReadWrite");
      Parameters.Server_Side_Encryption := US.To_Unbounded_String ("aws:kms");
      Parameters.SSE_KMS_Key_ID := US.To_Unbounded_String
        ("arn:aws:kms:us-east-1:111122223333:key/" &
         "1234abcd-12ab-34cd-56ef-1234567890ab");
      Parameters.Bucket_Key_Enabled := Flag;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Session
             (Origin, Low_Level.Virtual_Hosted_Style, Bucket, Parameters,
              Identity, "us-east-1", "20260907T012831Z");
         Canonical : constant String := Low_Level.Canonical_Request (Prepared);
         Wanted    : constant String := Header & ":" & Expect_Wire;
      begin
...
         Check (True, Label & ": Prepare_Create_Session accepts the " &
                  "presence-preserving flag");
...
            Check (Ada.Strings.Fixed.Index (Canonical, Wanted) /= 0,
                   Label & ": the canonical request carries """ & Wanted &
                     """");
...
   Run ("explicit false", (Is_Set => True, Value => False), "false");
   Run ("absent", (Is_Set => False, Value => False), "");
   Run ("explicit true", (Is_Set => True, Value => True), "true");
```

Output, exit status 1:

```
  -- spec: low_level.ads:6402-6404 -- "Bucket_Key_Enabled preserves absent versus explicit false"
  -- --- explicit false, exactly what the spec says is preserved ---
  -- explicit false: raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_REQUEST : invalid CreateSession parameters
  FAILED: explicit false: Prepare_Create_Session accepts the presence-preserving flag
  FAILED: explicit false: the canonical request carries "x-amz-server-side-encryption-bucket-key-enabled:false"
  -- --- control: flag absent ---
  -- absent: prepared, target /?session
  -- absent: signed headers = host;x-amz-content-sha256;x-amz-create-session-mode;x-amz-date;x-amz-server-side-encryption;x-amz-server-side-encryption-aws-kms-key-id
  ok: absent: Prepare_Create_Session accepts the presence-preserving flag
  ok: absent: the canonical request omits x-amz-server-side-encryption-bucket-key-enabled
  -- --- control: explicit true ---
  -- explicit true: prepared, target /?session
  -- explicit true: signed headers = host;x-amz-content-sha256;x-amz-create-session-mode;x-amz-date;x-amz-server-side-encryption;x-amz-server-side-encryption-aws-kms-key-id;x-amz-server-side-encryption-bucket-key-enabled
  ok: explicit true: Prepare_Create_Session accepts the presence-preserving flag
  -- explicit true: looking for "x-amz-server-side-encryption-bucket-key-enabled:true"
  ok: explicit true: the canonical request carries "x-amz-server-side-encryption-bucket-key-enabled:true"
BUG REPRODUCED: 2 failed expectation(s)
```

The two control legs show that the rest of the path is live: with the flag absent the header is absent from the signed headers, and with it explicitly true the same code path signs `x-amz-server-side-encryption-bucket-key-enabled:true`. That is the branch that would have emitted `true` for a caller who asked for `false`.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

The specification and the code must agree on one contract, and the serialiser must never be able to send a value the caller did not ask for. Either an explicit `false` is preserved and signed as `false`, as `src/flyology-object_storage-client-low_level.ads:6402-6404` promises and the pinned model's boolean member admits, or it is refused and the specification says so and names the member in the rejection message.

## Suggested treatment

This needs a maintainer decision, because it settles an externally visible policy for a modeled request member, which is a decision under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`:

- Honour the model's boolean. Drop the `Bucket_Key_Enabled` clause from the disjunction at `src/flyology-object_storage-client-low_level.adb:2430-2431` and serialise the caller's value at `:2501` instead of the literal, so the header carries `true` or `false`. A directory bucket that refuses `false` then answers with its own error, which the caller sees. The existing assertion at `tests/src/object_storage_test_cases.adb:14311-14316` has to be inverted.
- Keep the refusal as deliberate S3 Express policy. Then correct `src/flyology-object_storage-client-low_level.ads:6402-6404` to say that only an explicit `true` is accepted, record next to the check that the authority is the pinned model's statement that bucket keys cannot be disabled for a directory bucket, and make the rejection message name the member. The existing assertion stays.

Under either answer the `"true"` literal at `src/flyology-object_storage-client-low_level.adb:2501` must not survive unchanged: it is dead-but-wrong code that inverts the caller's value the moment the policy is relaxed, and the two lines are not tied together in any way a later reader would notice.

The regression test belongs in `Check_Low_Level_Create_Session` in `tests/src/object_storage_test_cases.adb`, beside the existing case at `:14311-14316`, and must assert the chosen contract on the canonical request rather than only on whether preparation raised: either that an explicit `false` prepares and signs `x-amz-server-side-encryption-bucket-key-enabled:false`, or that it raises and that the message names the member. The spike is the test.

## Severity

A caller who reads the published contract and sets the flag to an explicit `false` gets `Invalid_Request` with a message that does not say which member was wrong, so the contract is unusable as written. No wrong bytes reach the wire today, because the policy check fires before the serialiser, which is what keeps this to contract drift plus a latent inversion rather than a live wire defect. The inversion becomes real the moment anyone relaxes the check without also reading the serialiser, and at that point the request would carry `true` for a caller who asked for `false`, silently. CreateSession applies to S3 Express directory buckets only, so callers who do not use them never reach it. Deterministic.
