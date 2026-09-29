Title: The GetObjectAttributes decoder treats a present ObjectParts as proof of multipart and rejects full-object checksums
Labels: bug
Refs: S3-DOMAIN-B-8

## Summary

`Attributes.Validate` passes `Is_Multipart => Value.Has_Object_Parts` into `Validate_Object_Checksum`, and `Has_Object_Parts` is set on the `<ObjectParts>` start tag alone. The narrow multipart policy then applies, which permits only CRC32, CRC32C and CRC64NVME, instead of the ordinary-object policy the same package exports and documents. A server that reports a one-part container for an object written with a single PUT, which MinIO does, and returns a `FULL_OBJECT` SHA-256, MD5 or xxHash digest gets `Invalid_Response` for a well-formed 200. The same branch fires when the server omits `ChecksumType` and the decoder infers `FULL_OBJECT`.

## Problem

Commit `5fe6e3e`.

The flag is set on element presence (`src/flyology-object_storage-s3-attributes.adb:422-428`):

```ada
         elsif Local_Name = "ObjectParts" then
            if Item.Seen_Object_Parts then
               raise Malformed_Attributes with "duplicate ObjectParts";
            end if;
            Item.Seen_Object_Parts := True;
            Item.Value.Has_Object_Parts := True;
            Item.In_Parts := True;
```

and is used as the multipart verdict (`src/flyology-object_storage-s3-attributes.adb:771-774`):

```ada
      if Value.Has_Checksum then
         Validate_Object_Checksum
           (Value.Checksum, Is_Multipart => Value.Has_Object_Parts);
      end if;
```

The `FULL_OBJECT` branch then requires the multipart predicate (`src/flyology-object_storage-s3-attributes.adb:731-738`):

```ada
         elsif Kind = "FULL_OBJECT"
           and then
             ((Is_Multipart
               and then not Policy.Supported
                 (Algorithm, Policy.Full_Object))
              or else not Raw)
         then
            raise Malformed_Attributes with "invalid full-object checksum";
```

`Policy.Supported` is documented as the multipart rule and allows three algorithms (`src/flyology-object_storage-s3-checksum_policy.ads:69-75`):

```ada
   --  Report whether AWS permits the algorithm/type pair for multipart use.
   function Supported
     (Value : Algorithm; Kind : Checksum_Type) return Boolean is
     (case Kind is
         when Full_Object =>
           Value in Core.CRC32 | Core.CRC32C | Core.CRC64NVME,
         when Composite   => Value /= Core.CRC64NVME);
```

The package already exports the predicate for the other case, and says so (`src/flyology-object_storage-s3-checksum_policy.ads:77-83`):

```ada
   --  Report whether an ordinary, non-multipart object can retain this
   --  checksum. PutObject and CopyObject accept every concrete algorithm in
   --  the pinned model, always as one full-object digest. Keep this predicate
   --  separate from the narrower multipart policy above.
   function Ordinary_Object_Supported
     (Kind : Checksum_Type) return Boolean is
     (Kind = Full_Object);
```

The decoder never reaches it, because it decides which world it is in from the container's presence.

The same branch fires for servers that omit the type, because `Parse_Result` infers `FULL_OBJECT` for a plain Base64 digest (`src/flyology-object_storage-s3-attributes.adb:871-876`):

```ada
            elsif Wire_Core.Valid_Base64
              (Text, Policy.Digest_Length (Algorithm))
            then
               Handler.Value.Checksum.Kind :=
                 US.To_Unbounded_String ("FULL_OBJECT");
            end if;
```

The client turns the exception into a response-level failure (`src/flyology-object_storage-client-low_level.adb:5330-5332`):

```ada
   exception
      when S3.Attributes.Malformed_Attributes | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed GetObjectAttributes response";
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) ties nothing about `ObjectParts` to a multipart upload. Printed with python3:

```
--- GetObjectAttributesOutput.ObjectParts ---
{"shape": "GetObjectAttributesParts"}
required: None
--- ObjectAttributes enum --- ['ETag', 'Checksum', 'ObjectParts', 'StorageClass', 'ObjectSize']
```

`ObjectParts` is an ordinary optional output member, and the request enum lets a caller select it for any object.

MinIO `RELEASE.2025-09-07T16-13-09Z`, from the image pinned at `tests/scripts/test-minio.sh:5`, really does return a full-object SHA-256 together with a one-part container for an object written with one PUT carrying `x-amz-checksum-sha256`. A signed `GET /oracle-b/single?attributes` with `x-amz-object-attributes: ETag,Checksum,ObjectParts,StorageClass,ObjectSize`:

```
GetObjectAttributes single : 200 <?xml version="1.0" encoding="UTF-8"?> <getObjectAttributesResponse><ETag>5eb63bbbe01eeed093cb22bb8f5acdc3</ETag><Checksum><ChecksumSHA256>uU0nuZNNPgilLlLX2n2r+sSE7+N6U4DukIj3rOLvzek=</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum><ObjectParts><IsTruncated>false</IsTruncated><MaxParts>10000</MaxParts><NextPartNumberMarker>1</NextPartNumberMarker><PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount><Part><PartNumber>1</PartNumber><Size>11</Size></Part></ObjectParts><StorageClass>STANDARD</StorageClass><ObjectSize>11</ObjectSize></getObjectAttributesResponse>
```

Two separate rules stop that exact answer before the checksum rule is even relevant. Its root element is the lowercase `getObjectAttributesResponse`, which the decoder refuses (`src/flyology-object_storage-s3-attributes.adb:405-409`):

```ada
      if Item.Depth = 1 then
         if Local_Name /= "GetObjectAttributesResponse" then
            raise Malformed_Attributes with
              "wrong object-attributes response root";
         end if;
```

That deviation is already a documented exclusion (`tests/scripts/test-minio.sh:64` and `:73-74`):

```
FLYOLOGY_GET_OBJECT_ATTRIBUTES_ORACLE_MODE=minio-2025-lowercase-root \
...
echo "MinIO GetObjectAttributes oracle: skipped, pinned response uses" \
  "a non-AWS lowercase root element"
```

and its `<MaxParts>10000</MaxParts>` is refused by a separate bound, reported as {{ISSUE:S3-DOMAIN-B-8}}. Between them, MinIO's answer never reaches this checksum rule in any lane, which is why the rule was never exercised in tree.

The crate's own server cannot produce the combination either, because it emits the container only for multipart objects (`src/flyology-object_storage-server-s3_applications.adb:16314-16316`):

```ada
                     if Selection.Object_Parts and then Snapshot.Is_Multipart
                     then
                        Response.Has_Object_Parts := True;
```

The conformance corpus pairs `ObjectParts` with CRC-family checksums on completed multipart objects only (`tests/src/s3_implementation_corpus.adb:1691-1700`):

```ada
         Parameters.Has_Max_Parts := True;
         Parameters.Max_Parts := 1;
         Parameters.Has_Part_Number_Marker := True;
         Parameters.Part_Number_Marker := 0;
         Parameters.Attributes :=
           (Entity_Tag => True,
            Checksum => True,
            Object_Parts => Multipart_Checksum_Oracle_Mode /=
              RustFS_RC3_Multipart_Checksum_Divergence,
            Storage_Class => True, Object_Size => True);
```

so no case combines a non-CRC full-object checksum with a present parts container, and nothing asserts the wrong behaviour.

## What happens now

Spike: the program below decodes MinIO's captured checksum and parts combination, re-rooted under the AWS root element so the root rule does not fire first, plus MD5, xxHash64 and a variant with `ChecksumType` omitted, through `S3.Attributes.Parse_Result` and `Client.Low_Level.Decode_Get_Object_Attributes_Response`. The controls are a `FULL_OBJECT` CRC32 with the container present and a `FULL_OBJECT` SHA-256 with no container. The last block puts a single-PUT object with `x-amz-checksum-sha256` into the in-process memory-backed application and reads its `GetObjectAttributes` answer back through the crate's own client. MinIO's `<MaxParts>10000</MaxParts>` is lowered to `1000` in the program so that only the checksum rule is exercised; the 10000 echo is {{ISSUE:S3-DOMAIN-B-8}}, and against a live MinIO the two rejections stack.

```ada
   Object_Parts : constant String :=
     "<ObjectParts><IsTruncated>false</IsTruncated>" &
     "<MaxParts>1000</MaxParts>" &
     "<NextPartNumberMarker>1</NextPartNumberMarker>" &
     "<PartNumberMarker>0</PartNumberMarker><PartsCount>1</PartsCount>" &
     "<Part><PartNumber>1</PartNumber><Size>11</Size></Part></ObjectParts>";

   function Response_Body
     (Checksum : String; With_Parts : Boolean := True) return String
   is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<GetObjectAttributesResponse " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<ETag>""5eb63bbbe01eeed093cb22bb8f5acdc3""</ETag>" &
      "<Checksum>" & Checksum & "</Checksum>" &
      (if With_Parts then Object_Parts else "") &
      "<StorageClass>STANDARD</StorageClass>" &
      "<ObjectSize>11</ObjectSize>" &
      "</GetObjectAttributesResponse>");
```

Output, exit status 1:

```
  -- === controls: shapes the decoder accepts today ===
  -- FULL_OBJECT CRC32, parts container present   
  --     S3.Attributes.Parse_Result: accepted, Has_Checksum=TRUE Has_Object_Parts=TRUE
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- FULL_OBJECT SHA256, no parts container       
  --     S3.Attributes.Parse_Result: accepted, Has_Checksum=TRUE Has_Object_Parts=FALSE
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- 
  -- === the modeled combinations the decoder rejects ===
  -- FULL_OBJECT SHA256 + parts (MinIO's answer)  
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: FULL_OBJECT SHA256 + parts (MinIO's answer)  
  -- FULL_OBJECT MD5 + parts                      
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: FULL_OBJECT MD5 + parts                      
  -- FULL_OBJECT XXHASH64 + parts                 
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: FULL_OBJECT XXHASH64 + parts                 
  -- untyped raw SHA256 + parts (type omitted)    
  --     S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid full-object checksum
  --     Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: untyped raw SHA256 + parts (type omitted)    
  -- 
  -- === self-interop: what this crate's own server emits ===
  ok: CreateBucket /domain-b7 is 200
  ok: PutObject with x-amz-checksum-sha256 is 200
  -- GetObjectAttributes status=200
  --     body=<?xml version="1.0" encoding="UTF-8"?><GetObjectAttributesResponse xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><ETag>5eb63bbbe01eeed093cb22bb8f5acdc3</ETag><Checksum><ChecksumSHA256>uU0nuZNNPgilLlLX2n2r+sSE7+N6U4DukIj3rOLvzek=</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum><ObjectSize>11</ObjectSize></GetObjectAttributesResponse>
  ok: control: the crate's own GetObjectAttributes is 200
  -- this crate's own answer, read by its own client
  --     S3.Attributes.Parse_Result: accepted, Has_Checksum=TRUE Has_Object_Parts=FALSE
  --     Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  ok: this crate's own answer, read by its own client
BUG REPRODUCED: 4 failed expectation(s)
```

The two controls isolate the rule. The same SHA-256 digest is accepted when the parts container is absent, and the same parts container is accepted when the digest is CRC32, so neither the checksum nor the container is refused on its own. The last block shows the crate's own server answering the identical single-PUT question without a parts container, so this is a client-side failure against other servers and not a self-interop failure.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO `RELEASE.2025-09-07T16-13-09Z` from the pinned image. Shapes checked against the pinned botocore S3 model.

## What should happen

A `FULL_OBJECT` checksum of any modelled algorithm must decode even when the response carries an `ObjectParts` container, because the pinned model makes `ObjectParts` an ordinary optional output member with nothing tying its presence to a multipart upload, and because `Checksum_Policy.Ordinary_Object_Supported` is the predicate the same package documents for a single full-object digest. A genuinely composite checksum must still be held to the multipart rule.

## Suggested treatment

`Validate` needs a real multipart signal instead of the container's presence, at `src/flyology-object_storage-s3-attributes.adb:771-774`. This needs a maintainer decision, because the choice fixes what "multipart" means to this decoder and each option accepts a different set of responses:

- Apply `Ordinary_Object_Supported` unless the checksum is explicitly `COMPOSITE`. Smallest change, and it accepts every server that labels its digest honestly. A composite digest with a bare `-N` suffix and no `ChecksumType` is inferred as `COMPOSITE` at `src/flyology-object_storage-s3-attributes.adb:866-870`, so that case is still caught.
- Use `Value.Object_Parts.Total_Parts_Count > 1` as the multipart signal. Closest to the container's meaning, but the member is optional in the model and MinIO's one-part answer reports `PartsCount 1`, so an absent count needs its own rule.
- Use the composite `-N` suffix on the ETag. Independent of the checksum, but it depends on an opaque field the crate treats as opaque elsewhere.

`Checksum_Policy` already exports both predicates, so no new public declaration is required for any of them.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the other scripted GetObjectAttributes responses, as a decode of a `FULL_OBJECT` SHA-256 together with a one-part `ObjectParts` container that must succeed, with a `COMPOSITE` SHA-256 plus container case kept as a rejection. `tests/src/s3_implementation_corpus.adb:1691-1700` selects `Checksum` with `ObjectParts` only for completed multipart objects and should gain the single-PUT case once the MinIO oracle can run it. No existing assertion has to be inverted. The spike is the test.

## Severity

A valid, modelled 200 is reported to the caller as a malformed response, so a GetObjectAttributes that selects both `Checksum` and `ObjectParts` fails against any server that reports a parts container for a single-PUT object and uses a non-CRC digest. MinIO is such a server. The trigger needs the caller to select both attribute groups, which the convenience clients expose, and the crate's own server never produces the combination, so a deployment that talks only to Flyology will not see it. Against MinIO specifically the failure is currently masked, because the documented lowercase-root exclusion and the `MaxParts` bound reported as {{ISSUE:S3-DOMAIN-B-8}} both stop the same response earlier. Nothing is written or lost; the read is refused. Deterministic.
