Title: Read_Entity_Tag_List rejects empty list elements, so an If-Match with a trailing comma is answered 400
Labels: bug
Refs: none

## Summary

`Read_Entity_Tag_List` sets its `Valid` flag only when the field ends immediately after a quoted tag, so any empty list element makes the whole field invalid: a trailing comma, a leading comma, or `",,"` between two tags. The server turns that into 400 InvalidArgument for HeadObject and GetObject conditions, and into `Invalid_Request` for PutObject write conditions, instead of evaluating the request against the tags that are present. RFC 9110 requires a recipient to parse and ignore a reasonable number of empty list elements, so a field a compliant intermediary may produce is answered 400 rather than 200 or 412.

## Problem

Commit `5fe6e3e`.

The parser returns without setting `Valid` at an element position that holds no tag (`src/flyology-object_storage.adb:183-186`):

```ada
         Skip_Whitespace;
         if Cursor > Length then
            return;
         end if;
```

and at an element position whose first character is neither `W/` nor a quote (`src/flyology-object_storage.adb:198-202`):

```ada
            if Cursor > Length
              or else Character_At (Value, Positive (Cursor)) /= '"'
            then
               return;
            end if;
```

`Valid` is set in exactly one place, when the field ends right after a tag (`src/flyology-object_storage.adb:235-246`):

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

A trailing comma therefore leaves the loop at the first return above, and a leading or interior comma at the second.

`Valid_Object_Read_Entity_Tag_Condition` is defined as "not `Invalid_Request`" over the same evaluation (`src/flyology-object_storage.adb:278-289`):

```ada
   function Valid_Object_Read_Entity_Tag_Condition
     (Value : String) return Boolean is
     (Value'Length > 0
      and then Evaluate_Object_Read_Conditions
        (If_Match => Value,
         If_None_Match => "",
         Has_If_Modified_Since => False,
         If_Modified_Since => 0,
         Has_If_Unmodified_Since => False,
         If_Unmodified_Since => 0,
         Entity_Tag => "",
         Modified => 0) /= Invalid_Request);
```

and the server rejects the request on that predicate (`src/flyology-object_storage-server-s3_applications.adb:16706-16719`):

```ada
                  elsif (If_Match_Count = 1
                         and then not
                           Backends.Valid_Read_Entity_Tag_Condition
                             (Apps.Request_Header (X, "if-match")))
                    or else (If_None_Match_Count = 1
                             and then not
                               Backends.Valid_Read_Entity_Tag_Condition
                                 (Apps.Request_Header (X, "if-none-match")))
                  then
                     Send_Error
                       (X, 400, "InvalidArgument",
                        "A HeadObject entity-tag condition is malformed",
                        Target_Text);
                     return;
```

The contract the predicate claims to implement is HTTP list syntax (`src/flyology-object_storage.ads:124-130`):

```ada
   --  Validate one If-Match or If-None-Match field for an object read.
   --  Weak entity tags are valid syntax; comparison semantics are selected by
   --  Evaluate_Object_Read_Conditions. Oversized fields are rejected.
   --  @param Value Entity-tag condition field value
   --  @return True when Value has valid bounded entity-tag list syntax
   function Valid_Object_Read_Entity_Tag_Condition
     (Value : String) return Boolean;
```

RFC 9110 section 5.6.1 defines the `#rule` list extension. Its recipient form is `[ element ] *( OWS "," OWS [ element ] )`, and it requires a recipient to parse and ignore a reasonable number of empty list elements, while forbidding a sender from generating them. So the fields above are valid list syntax on the receiving side. Whether the S3 service itself tolerates them was not checked against a live server: the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) types `IfMatch` as an unconstrained `string` shape and so answers neither way.

The existing tests pin neighbouring cases but not this one (`tests/src/object_storage_test_cases.adb:3763-3775`):

```ada
      Assert
        (Valid_Object_Read_Entity_Tag_Condition
           (ASCII.HT & """other""," & ASCII.HT & "W/""etag"""),
         "valid read entity-tag list was rejected");
      Assert
        (not Valid_Object_Read_Entity_Tag_Condition (""),
         "empty read entity-tag condition was accepted");
      Assert
        (not Valid_Object_Read_Entity_Tag_Condition ("*, ""etag"""),
         "mixed-wildcard read entity-tag list was accepted");
      Assert
        (not Valid_Object_Read_Entity_Tag_Condition ((1 .. 16_385 => 'x')),
         "oversized read entity-tag condition was accepted");
```

Nothing covers an empty element, and no test asserts the server's current 400, so the behaviour is unasserted rather than deliberate.

## What happens now

Spike: at the domain level it asserts that `Valid_Object_Read_Entity_Tag_Condition` and `Evaluate_Object_Read_Conditions` accept a trailing, a leading and an interior empty element and evaluate to `Success` against the matching tag, and prints what `Evaluate_Object_Write_Conditions` returns for the same fields. At the server level it stores an object and asserts that a signed conditional HEAD carrying each field answers 200. Controls first: a plain quoted tag and `*` must be 200, and a genuinely non-matching tag must still be 412.

```ada
   procedure Probe (Label, Field : String; Expect_200 : Boolean) is
      R : constant String := Run (Signed_Request
        ("HEAD", "/" & Bucket & "/" & Key,
         Extra_Headers => "If-Match: " & Field & CRLF));
...
   Probe ("CONTROL exact tag", Quote & Tag & Quote, True);
   Probe ("CONTROL wildcard", "*", True);
   Probe ("trailing empty element", Quote & Tag & Quote & ",", True);
   Probe ("leading empty element", "," & Quote & Tag & Quote, True);
   Probe ("interior empty element",
          Quote & Tag & Quote & ",," & Quote & "other" & Quote, True);
```

Output, exit status 1:

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

The write-condition notes show the same fields reaching `Invalid_Request` on the PutObject path, so the effect is not confined to reads.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

An empty list element should be ignored and the field evaluated against the tags that are present, so `If-Match: "<etag>",` against the matching object answers 200 and against a different object answers 412. RFC 9110 section 5.6.1 states the recipient requirement, and the `.ads` contract at `src/flyology-object_storage.ads:124-130` already claims entity-tag list syntax rather than a narrower grammar.

## Suggested treatment

The fix is local to `Read_Entity_Tag_List` in `src/flyology-object_storage.adb:103-248`: at the element position, when the next character is `,` or the field has ended, treat the element as empty and continue the loop rather than returning, and set `Valid` when the field ends after a comma as well as after a tag. The `Remaining_Items` bound at `:243-246` still limits the iteration count and `Maximum_Condition_Length` still bounds the field, so tolerating empty elements cannot unbound the parser. No new public constant, variant or contract change is required, so this does not raise a decision under the "Ada interface values" section of `AGENTS.md`.

One question is worth settling before the change lands: whether the S3 service itself tolerates empty elements. That was not checked against a live server, and the pinned botocore S3 model does not say, so a maintainer may prefer to match the service rather than the RFC. A run against the pinned MinIO or RustFS image under `tests/scripts/` would settle it.

The regression tests belong in two places. The domain predicate and `Evaluate_Object_Read_Conditions` and `Evaluate_Object_Write_Conditions` cases go in `tests/src/object_storage_test_cases.adb` beside the existing entity-tag list assertions at `:3763-3775`. The conditional HEAD and GET cases go in `tests/src/s3_server_application_corpus.adb`. The spike is those tests. No existing test asserts the current rejection, so nothing has to be rewritten.

## Severity

A conditional read or write carrying an empty list element is refused with 400 InvalidArgument instead of being evaluated, so a caller that would have got 200 or 412 gets a client error. No S3 SDK generates an empty list element and the RFC forbids senders from doing so, so the trigger is unusual: it takes a hand-written field or an intermediary that joins a present and an absent field value. It is a recipient-side conformance gap, not a wrong answer to anything a normal client sends. Deterministic; not reproduced against a live server.
