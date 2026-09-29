Title: The GetObjectAttributes decoder bounds a response's MaxParts echo by Core.Page_Size'Last, and MinIO echoes 10000
Labels: bug
Refs: S3-DOMAIN-A-6, S3-DOMAIN-B-7

## Summary

The GetObjectAttributes response decoder rejects any `<MaxParts>` above `Core.Page_Size'Last`, which is 1,000. That subtype exists for Flyology's own pagination policy, and the pinned botocore S3 model puts no bound on this member at all. MinIO answers `<MaxParts>10000</MaxParts>` on every GetObjectAttributes request that selects `ObjectParts`, regardless of what was asked for, so a Flyology client talking to a MinIO-compatible server gets `Invalid_Response` for a well-formed 200. The diagnostic is wrong as well as the rule: because the check runs inside the SAX handler, the range failure is rewritten as "malformed GetObjectAttributes XML".

## Problem

Commit `5fe6e3e`.

The scalar handler applies the bound while parsing (`src/flyology-object_storage-s3-attributes.adb:558-576`):

```ada
               if not Parsed.Valid
                 or else
                   (Item.Field = Part_Number_Field
                    and then Parsed.Value not in Core.Part_Number'Range)
                 or else
                   (Item.Field /= Max_Parts_Field
                    and then Item.Field /= Total_Parts_Count_Field
                    and then Item.Field /= Part_Number_Field
                    and then Parsed.Value > Part_Marker_Value'Last)
                 or else
                   (Item.Field = Max_Parts_Field
                    and then Parsed.Value > Core.Page_Size'Last)
                 or else
                   (Item.Field = Total_Parts_Count_Field
                    and then Parsed.Value > Core.Part_Number'Last)
               then
                  raise Malformed_Attributes with
                    "invalid object part scalar";
               end if;
```

Because that runs inside the handler, `Parse_Result` rewrites the message through its `XML.XML_Error` arm (`src/flyology-object_storage-s3-attributes.adb:881-885`):

```ada
   exception
      when XML.XML_Error =>
         raise Malformed_Attributes with
           "malformed GetObjectAttributes XML";
   end Parse_Result;
```

so a maintainer reading the diagnostic is pointed at the parser rather than at a range. `Validate` then applies the same bound a second time (`src/flyology-object_storage-s3-attributes.adb:786-790`):

```ada
         elsif Value.Object_Parts.Max_Parts.Is_Set
           and then Value.Object_Parts.Max_Parts.Value >
             Core.Page_Size'Last
         then
            raise Malformed_Attributes with "invalid max parts";
         end if;
```

The bound is a visible subtype meant for one page of a Flyology listing (`src/flyology-object_storage-s3-core.ads:24-28`):

```ada
   --  Valid S3 multipart part number.
   subtype Part_Number is Positive range 1 .. 10_000;

   --  Requested or returned item count for one S3 page.
   subtype Page_Size is Natural range 0 .. 1_000;
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) places no bound on the member. Printed with python3:

```
--- GetObjectAttributesParts.MaxParts + MaxParts shape ---
{"shape": "MaxParts"}
{"type": "integer"}
```

The `MaxParts` shape has no `min` and no `max`, and the request-side member is the `x-amz-max-parts` header, which uses the same unbounded shape. So the crate is not reusing a limit the model imposes.

MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned at `tests/scripts/test-minio.sh:5`, exceeds it. A signed `GET /oracle-b/single?attributes` with `x-amz-object-attributes: ETag,Checksum,ObjectParts,StorageClass,ObjectSize`, against an object written with a single PUT:

```
GetObjectAttributes single : 200 <?xml version="1.0" encoding="UTF-8"?> <getObjectAttributesResponse>...<ObjectParts><IsTruncated>false</IsTruncated><MaxParts>10000</MaxParts><NextPartNumberMarker>1</NextPartNumberMarker><PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount><Part><PartNumber>1</PartNumber><Size>11</Size></Part></ObjectParts><StorageClass>STANDARD</StorageClass><ObjectSize>11</ObjectSize></getObjectAttributesResponse>
```

Nothing in tree asserts the wrong behaviour, and nothing exercises it either. The conformance corpus disables the GetObjectAttributes assertions entirely under MinIO's oracle mode (`tests/src/s3_implementation_corpus.adb:323-335`):

```ada
   function Check_Get_Object_Attributes return Boolean is
      Name : constant String :=
        "FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE";
   begin
      if not Ada.Environment_Variables.Exists (Name)
        or else Ada.Environment_Variables.Value (Name) =
          "rustfs-rc3-missing-error-message"
      then
         return True;
      elsif Ada.Environment_Variables.Value (Name) =
        "minio-2025-lowercase-root"
      then
         return False;
```

and that mode is what `tests/scripts/test-minio.sh:64` sets, so MinIO's `MaxParts` never reaches the decoder in CI. The crate's own server never emits a value above its own `Page_Size`, so the codec suites do not see it either.

## What happens now

Spike: the program below prints the two bounds, then decodes one GetObjectAttributes response body twice through `S3.Attributes.Parse_Result` and `Client.Low_Level.Decode_Get_Object_Attributes_Response`, once with `<MaxParts>1000</MaxParts>` and once with MinIO's real `<MaxParts>10000</MaxParts>`. Everything else in the two bodies is identical.

```ada
   function Response_Body (Max_Parts : String) return String is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<GetObjectAttributesResponse " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<Checksum><ChecksumCRC32>" & Digest (Core.CRC32) &
      "</ChecksumCRC32><ChecksumType>FULL_OBJECT</ChecksumType></Checksum>" &
      "<ObjectParts><IsTruncated>false</IsTruncated>" &
      "<MaxParts>" & Max_Parts & "</MaxParts>" &
      "<NextPartNumberMarker>1</NextPartNumberMarker>" &
      "<PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount>" &
      "<Part><PartNumber>1</PartNumber><Size>11</Size></Part>" &
      "</ObjectParts>" &
      "<ObjectSize>11</ObjectSize>" &
      "</GetObjectAttributesResponse>");
```

Output, exit status 1:

```
  -- Core.Page_Size'Last  = 1000
  -- Core.Part_Number'Last= 10000
  -- 
  -- === control: a MaxParts echo inside the crate's bound ===
  -- control: MaxParts within Page_Size (MaxParts=1000)
  --     S3.Attributes.Parse_Result: accepted, MaxParts=1000
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- 
  -- === MinIO's actual MaxParts echo ===
  -- MinIO's GetObjectAttributes answer (MaxParts=10000)
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: malformed GetObjectAttributes XML
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: MinIO's GetObjectAttributes answer
BUG REPRODUCED: 1 failed expectation(s)
```

The body uses a `FULL_OBJECT` CRC32 digest, which the multipart policy accepts, so the parts-container rule reported as {{ISSUE:S3-DOMAIN-B-7}} does not explain the rejection: the only difference between the passing and failing legs is the `MaxParts` value. The message that comes out names the XML, not the bound.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A `MaxParts` echoed by another server must not be rejected against Flyology's own page-size policy, because the pinned botocore S3 model puts no `min` or `max` on the `MaxParts` shape and MinIO answers 10000 for every request that selects `ObjectParts`. If a receive-side bound is kept, a failing value must be reported as a range violation and not as malformed XML.

## Suggested treatment

Separate the receive-side rule from Flyology's own pagination policy. Concretely, change the `Max_Parts_Field` arm at `src/flyology-object_storage-s3-attributes.adb:567-569` and the matching `Validate` branch at `:786-790`, and let the range failure surface with its own message rather than through the `XML.XML_Error` arm at `:881-885`, so the diagnostic names the bound.

This needs a maintainer decision, because `Core.Page_Size` is a visible subtype whose scope is a specification-level choice under the "Ada interface values" section of `AGENTS.md`, not an implementation detail:

- Bound the echo by `Core.Part_Number'Last` (10,000). Accepts MinIO and keeps a sanity limit that has an S3 meaning, since a multipart upload has at most 10,000 parts.
- Place no bound on the echoed value beyond what the field's own type allows. Follows the model exactly, and accepts any future server that echoes a larger number.
- Keep `Core.Page_Size'Last` and document that GetObjectAttributes with `ObjectParts` does not work against servers that echo more than 1,000.

Either of the first two is a change to a validation rule and needs no new public declaration.

{{ISSUE:S3-DOMAIN-A-6}} is the same 1,000 ceiling, the same `Core.Page_Size` subtype at `src/flyology-object_storage-s3-core.ads:28`, applied on the request side where the model also places no bound, and MinIO exceeds it there too. The two can be fixed independently, but the answer to "where does Flyology's own pagination policy apply" should cover both, so they should be decided together.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the other scripted GetObjectAttributes responses, as a decode of MinIO's `<MaxParts>10000</MaxParts>` body that must succeed, with a value above whatever bound is chosen kept as a rejection asserting a message that names the range. `tests/src/s3_implementation_corpus.adb:323-340` disables the whole GetObjectAttributes group under MinIO's oracle mode, so this will not be covered there until that exclusion is narrowed to the lowercase root element it was written for. No existing assertion has to be inverted. The spike is the test.

## Severity

A well-formed, modelled 200 is reported to the caller as a malformed response, so GetObjectAttributes with `ObjectParts` selected fails against a server that echoes a `MaxParts` above 1,000, and MinIO does that on every such request. The wrong diagnostic makes it worse to diagnose than it needs to be, because it names the XML rather than the bound. Against MinIO specifically the failure is currently masked by the already-documented lowercase-root exclusion, so a deployment only meets it through a MinIO-compatible server that uses the AWS root element. Nothing is written or lost; the read is refused. Deterministic.
