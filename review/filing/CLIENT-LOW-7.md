Title: Valid_Model_Scalar accepts Ada literal integers, so Prepare_Model_Request signs and sends max-keys=1_000
Labels: bug
Refs: none

## Summary

`Valid_Model_Scalar` validates a modeled integer or long member by calling `Long_Long_Integer'Value` on the caller's text, which is Ada's own numeric-literal grammar, and then the projector percent-encodes the caller's original text rather than the parsed number. A caller of the public `Prepare_Model_Request` who supplies `1_000`, `16#3E8#`, `1E3` or `+1000` therefore gets a fully signed request carrying `max-keys=1_000`, `max-keys=16%233E8%23`, `max-keys=1E3` or `max-keys=%2B1000`, with no client-side complaint. The validator exists to catch exactly this before signing, and the first thing that notices is the server, which answers 400.

## Problem

Commit `5fe6e3e`.

The integer branch borrows Ada's literal grammar (`src/flyology-object_storage-client-low_level.adb:949-965`):

```ada
         when Model.Integer_Shape | Model.Long_Shape =>
            declare
               Number : Long_Long_Integer;
               Minimum : constant String := Model.Minimum (Shape);
               Maximum : constant String := Model.Maximum (Shape);
            begin
               Number := Long_Long_Integer'Value (Value);
               return
                 (Minimum'Length = 0
                  or else Number >= Long_Long_Integer'Value (Minimum))
                 and then
                 (Maximum'Length = 0
                  or else Number <= Long_Long_Integer'Value (Maximum));
            exception
               when Constraint_Error =>
                  return False;
            end;
```

`'Value` accepts underscores, based literals, exponents and a leading `+`, so all four forms pass. The bounds are then checked against `Number`, but `Number` is discarded: the raw `Value` text is what the projector encodes into the request target, which the run below shows on the wire.

The entry point is public and is documented as the projector that validates member values (`src/flyology-object_storage-client-low_level.ads:193-198`, declared at `:210`):

```ada
   --  Prepare any operation in the pinned 116-operation S3 model. The
   --  projector validates member names, locations, required top-level
   --  members, duplicate scalar members, header-map keys, addressing, and
   --  the signed payload hash. Structured body serialization remains a
   --  separate codec concern; Payload_Is_Set distinguishes an absent body
   --  from an explicitly empty REST/XML or blob payload.
```

Bounds are not what should have rejected these values. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3`:

```python
op = model['operations']['ListObjectsV2']
inp = model['shapes'][op['input']['shape']]
m = inp['members']['MaxKeys']
print('ListObjectsV2Request.MaxKeys:', {k: m[k] for k in ('shape', 'location', 'locationName')})
print('MaxKeys shape:', model['shapes'][m['shape']])
```

```
ListObjectsV2Request.MaxKeys: {'shape': 'MaxKeys', 'location': 'querystring', 'locationName': 'max-keys'}
MaxKeys shape: {'type': 'integer'}
```

`MaxKeys` carries no minimum and no maximum, so the defect is purely lexical: the validator never asks whether the text is a wire integer.

The crate's own server refuses every one of those forms. Starting the in-repo memory server built from this commit, `tests/bin/s3_memory_server`, with the environment `tests/scripts/test-flyology-server.sh:46-52` uses, and sending four hand-signed requests to it after creating the bucket:

```
### GET /probe-bucket?list-type=2&max-keys=1000
HTTP/1.1 200 OK
Date: Mon, 07 Sep 2026 06:33:32 GMT
Content-Length: 242
Content-Type: application/xml
Connection: close

<?xml version="1.0" encoding="UTF-8"?><ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>probe-bucket</Name><Prefix></Prefix><KeyCount>0</KeyCount><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated></ListBucketResult>
### GET /probe-bucket?list-type=2&max-keys=1_000
HTTP/1.1 400 Bad Request
Date: Mon, 07 Sep 2026 06:33:32 GMT
Content-Length: 201
Content-Type: application/xml
Connection: close

<?xml version="1.0" encoding="UTF-8"?><Error><Code>InvalidArgument</Code><Message>The ListObjectsV2 request is invalid</Message><Resource>/probe-bucket?list-type=2&amp;max-keys=1_000</Resource></Error>
### GET /probe-bucket?list-type=2&max-keys=1E3
HTTP/1.1 400 Bad Request
...
### GET /probe-bucket?list-type=2&max-keys=16#3E8#
HTTP/1.1 400 Bad Request
...
### GET /probe-bucket?list-type=2&max-keys=+1000
HTTP/1.1 400 Bad Request
...
```

The three elided responses are identical to the `1_000` one apart from the `<Resource>` text, which echoes `max-keys=1E3`, `max-keys=16%233E8%23` and `max-keys=%2B1000` respectively. That is what the server's own query parser requires (`src/flyology-object_storage-s3-listings.adb:223-230`):

```ada
                  elsif Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Max_Keys or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 max-keys";
                     end if;
```

with `Parse_Natural` admitting decimal digits only (`src/flyology-object_storage-s3-wire_core.adb:11-14`):

```ada
      for Character_Value of Text loop
         if Character_Value not in '0' .. '9' then
            return (Valid => False);
         end if;
```

and the rejection rendered as the 400 above (`src/flyology-object_storage-server-s3_applications.adb:10926-10929`):

```ada
                  when Listings.Malformed_List_Request =>
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "The ListObjectsV2 request is invalid", Target_Text);
```

The typed preparers are unaffected, because they format integers with `'Image`, so the reachable route is the generic public entry point rather than the typed API. No existing test exercises a non-decimal integer member through `Prepare_Model_Request`: the model-projection cases assert an unknown member, a missing required member, a duplicate member, a body on a bodyless operation, a modeled minimum, a source pattern and an enumeration (`tests/src/object_storage_test_cases.adb:19236-19297`), and the closest is a bounds case rather than a lexical one (`:19268-19275`):

```ada
      declare
         Values : constant Low_Level.Model_Value_Array :=
           (1 => Item ("MaxBuckets", "0"));
      begin
         Expect_Invalid
           (Model.List_Directory_Buckets_Operation, Values,
            "modeled integer minimum was not enforced");
      end;
```

## What happens now

Spike: the program below calls `Prepare_Model_Request` for ListObjectsV2 with the `MaxKeys` member set to each of the four Ada literal forms and asserts that preparation rejects them, printing the resulting request target when it does not. Two controls follow: a plain `500`, which must prepare and appear verbatim, and `not-a-number`, which must be rejected.

```ada
      Values : constant Low_Level.Model_Value_Array :=
        [(Member_Name => US.To_Unbounded_String ("Bucket"),
          Map_Key => US.Null_Unbounded_String,
          Value => US.To_Unbounded_String (Bucket)),
         (Member_Name => US.To_Unbounded_String ("MaxKeys"),
          Map_Key => US.Null_Unbounded_String,
          Value => US.To_Unbounded_String (Text))];
   begin
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Model_Request
             (Model.List_Objects_V2_Operation, Origin,
              Low_Level.Path_Style, Values, "", False, Empty_Hash,
              Identity, "us-east-1", "20260907T012831Z");
         Target : constant String := Low_Level.Target (Prepared);
      begin
         Note ("MaxKeys=""" & Text & """ prepared; target = " & Target);
...
            Check (False,
                   "MaxKeys=""" & Text & """ is not a wire-valid decimal " &
                     "integer and must be rejected at preparation");
...
   Run ("500", Must_Prepare => True);
   Run ("not-a-number", Must_Prepare => False);
   Run ("1_000", Must_Prepare => False);
   Run ("16#3E8#", Must_Prepare => False);
   Run ("1E3", Must_Prepare => False);
   Run ("+1000", Must_Prepare => False);
```

Output, exit status 1:

```
  -- MaxKeys is an Integer_Shape ListObjectsV2 member bound to the max-keys query parameter; Valid_Model_Scalar validates it with Long_Long_Integer'Value and forwards the raw text
  -- --- control: a plain decimal value ---
  -- MaxKeys="500" prepared; target = /example-bucket?list-type=2&max-keys=500
  ok: control MaxKeys="500" reaches the wire verbatim
  -- --- control: text that is not a number at all ---
  -- MaxKeys="not-a-number" rejected: invalid modeled request scalar
  ok: MaxKeys="not-a-number" is not a wire-valid decimal integer and must be rejected at preparation
  -- --- Ada literal forms that 'Value accepts and S3 does not ---
  -- MaxKeys="1_000" prepared; target = /example-bucket?list-type=2&max-keys=1_000
  FAILED: MaxKeys="1_000" is not a wire-valid decimal integer and must be rejected at preparation
  -- MaxKeys="16#3E8#" prepared; target = /example-bucket?list-type=2&max-keys=16%233E8%23
  FAILED: MaxKeys="16#3E8#" is not a wire-valid decimal integer and must be rejected at preparation
  -- MaxKeys="1E3" prepared; target = /example-bucket?list-type=2&max-keys=1E3
  FAILED: MaxKeys="1E3" is not a wire-valid decimal integer and must be rejected at preparation
  -- MaxKeys="+1000" prepared; target = /example-bucket?list-type=2&max-keys=%2B1000
  FAILED: MaxKeys="+1000" is not a wire-valid decimal integer and must be rejected at preparation
BUG REPRODUCED: 4 failed expectation(s)
```

The `not-a-number` control shows that the validator is reached and does reject text that `'Value` cannot parse at all, and the `500` control shows that a decimal value reaches the target unchanged. The four failing lines print the request target that was actually built and signed, which is the byte sequence the server sees.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model; the 400 responses above are from the in-repo memory server built at this commit.

## What should happen

A modeled integer or long member value that is not a wire-valid decimal integer must be rejected at preparation, as `Invalid_Request`, before the request is signed. The validator is the only place that can catch it, since the same text is what the projector encodes into the target, and the pinned model gives `MaxKeys` no bounds that would catch it later.

## Suggested treatment

Two local fixes are available at `src/flyology-object_storage-client-low_level.adb:949-965`, and neither needs a maintainer decision or a new public entity:

- Check the lexical form before parsing: require an optional leading `-` followed by one or more characters in `'0' .. '9'` and nothing else, then call `'Value` for the numeric range check as today. The same guard applies to `Minimum` and `Maximum`, which come from the pinned model and are already decimal.
- Or serialise the validated number instead of the caller's text, by trimming `Number'Image` and using that as the member value, so that what is validated is what is sent. This also normalises a leading `+` rather than rejecting it, which is a small behaviour choice worth stating in the change.

The first is the smaller change and preserves the current "the caller's text is the value" rule for every other shape kind.

The regression test belongs in `Check_Model_Request_Projection` in `tests/src/object_storage_test_cases.adb`, using the existing `Expect_Invalid` helper at `:19024-19051` and placed beside the bounds case at `:19268-19275`: `Expect_Invalid (Model.List_Objects_V2_Operation, ...)` with `MaxKeys` set to `"1_000"`, `"16#3E8#"`, `"1E3"` and `"+1000"`, plus a positive case asserting that `"500"` still reaches the target. No existing assertion has to change. The spike is the test.

## Severity

A request that no S3 server accepts is signed and sent with no client-side error, and because the malformed text is inside the signed canonical request it cannot be corrected by anything downstream. The caller sees only a remote rejection: against the crate's own server that is a 400 `InvalidArgument` whose message names the operation rather than the member, and the cause is not visible locally at all. It needs unusual caller text through the generic `Prepare_Model_Request`, which is a public entry point but not the path the typed preparers take, since those format with `'Image`; so a caller who only uses the typed API is unaffected. The validator exists for exactly this check, so the failure is that it silently passes what it is there to stop. Deterministic.
