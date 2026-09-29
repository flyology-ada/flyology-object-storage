Title: Attributes.Valid_Storage_Class hard-codes 13 of the model's 15 storage classes, so AWS Backup objects decode as malformed
Labels: bug
Refs: none

## Summary

`Attributes.Valid_Storage_Class` duplicates the pinned botocore S3 model's `StorageClass` enumeration as thirteen string literals, and the model has fifteen values. `Validate` rejects any present-but-unlisted value with `Malformed_Attributes "invalid storage class"`, which `Client.Low_Level` turns into `Invalid_Response "malformed GetObjectAttributes response"`. A GetObjectAttributes response naming `AWS_BACKUP_WARM` or `AWS_BACKUP_LOW_COST_WARM`, both of which are modelled and both of which the crate's own replication codec already decodes, is therefore reported to the caller as a malformed answer.

## Problem

Commit `5fe6e3e`.

The list is written out by hand (`src/flyology-object_storage-s3-attributes.adb:756-760`):

```ada
   function Valid_Storage_Class (Value : String) return Boolean is
     (Value in "STANDARD" | "REDUCED_REDUNDANCY" | "STANDARD_IA" |
       "ONEZONE_IA" | "INTELLIGENT_TIERING" | "GLACIER" |
       "DEEP_ARCHIVE" | "OUTPOSTS" | "GLACIER_IR" | "SNOW" |
       "EXPRESS_ONEZONE" | "FSX_OPENZFS" | "FSX_ONTAP");
```

and `Validate` applies it whenever the member is present, not only when it was selected (`src/flyology-object_storage-s3-attributes.adb:775-779`):

```ada
      if Value.Has_Storage_Class
        and then not Valid_Storage_Class (US.To_String (Value.Storage_Class))
      then
         raise Malformed_Attributes with "invalid storage class";
      end if;
```

The client maps the exception to a response-level failure (`src/flyology-object_storage-client-low_level.adb:5330-5332`):

```ada
   exception
      when S3.Attributes.Malformed_Attributes | S3.Errors.Malformed_Error =>
         raise Invalid_Response with "malformed GetObjectAttributes response";
```

The pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) carries fifteen values. Printed with python3:

```
--- StorageClass enum ---
15 ['STANDARD', 'REDUCED_REDUNDANCY', 'STANDARD_IA', 'ONEZONE_IA', 'INTELLIGENT_TIERING', 'GLACIER', 'DEEP_ARCHIVE', 'OUTPOSTS', 'GLACIER_IR', 'SNOW', 'EXPRESS_ONEZONE', 'FSX_OPENZFS', 'FSX_ONTAP', 'AWS_BACKUP_WARM', 'AWS_BACKUP_LOW_COST_WARM']
```

The model is not the limitation. The crate's own replication codec already decodes both missing spellings (`src/flyology-object_storage-s3-replication.adb:485-488`):

```ada
      elsif Value = "AWS_BACKUP_WARM" then
         return AWS_Backup_Warm;
      elsif Value = "AWS_BACKUP_LOW_COST_WARM" then
         return AWS_Backup_Low_Cost_Warm;
```

and the sibling listing codec validates the same shape dynamically against the model instead of copying it (`src/flyology-object_storage-s3-multipart_uploads.adb:492-504`):

```ada
   function Valid_Enumeration
     (Value : String; Shape : Model.Shape_Index) return Boolean is
   begin
      if Model.Enumeration_Count (Shape) = 0 then
         return False;
      end if;
      for Index in 1 .. Model.Enumeration_Count (Shape) loop
         if Model.Enumeration_Value (Shape, Index) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Valid_Enumeration;
```

used for the upload storage class at `src/flyology-object_storage-s3-multipart_uploads.adb:687-689`. So the mechanism that would have prevented the drift is already in the same area.

The compatibility matrix claims a complete typed client for this operation (`docs/compatibility/s3.md:60`):

```
| GetObjectAttributes | memory, files, SQLite including exact retained generations | complete typed composable, synchronous, and convenience clients; ...
```

so the drift also contradicts a maintained document.

No test pins the list: `rg AWS_BACKUP tests/src` matches only the replication corpus, and the crate's own server never emits anything but `STANDARD`, so no lane can produce the value. Nothing asserts the wrong behaviour, so no test has to be inverted.

## What happens now

Spike: the program below prints the `StorageClass` enumeration straight out of the compiled model, then builds one GetObjectAttributes response body per class and decodes it through `S3.Attributes.Parse_Result` and through `Client.Low_Level.Decode_Get_Object_Attributes_Response`. `STANDARD` and `GLACIER_IR` are the controls.

```ada
   function Response_Body (Storage_Class : String) return String is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<GetObjectAttributesResponse " &
      "xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<ETag>""9a0364b9e99bb480dd25e1f0284c8555""</ETag>" &
      "<StorageClass>" & Storage_Class & "</StorageClass>" &
      "<ObjectSize>7</ObjectSize>" &
      "</GetObjectAttributesResponse>");
```

Output, exit status 1:

```
  -- === the pinned model's StorageClass enumeration ===
  ok: control: the model has a GetObjectAttributes output shape
  ok: control: the output shape has a StorageClass member
  -- model StorageClass values (15):
  --     STANDARD
  --     REDUCED_REDUNDANCY
  --     STANDARD_IA
  --     ONEZONE_IA
  --     INTELLIGENT_TIERING
  --     GLACIER
  --     DEEP_ARCHIVE
  --     OUTPOSTS
  --     GLACIER_IR
  --     SNOW
  --     EXPRESS_ONEZONE
  --     FSX_OPENZFS
  --     FSX_ONTAP
  --     AWS_BACKUP_WARM
  --     AWS_BACKUP_LOW_COST_WARM
  -- 
  -- === control: a class the codec knows ===
  -- STANDARD
  --   S3.Attributes.Parse_Result: accepted, StorageClass=[STANDARD]
  --   Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- GLACIER_IR
  --   S3.Attributes.Parse_Result: accepted, StorageClass=[GLACIER_IR]
  --   Client.Low_Level: accepted, kind=OBJECT_ATTRIBUTES_FOUND
  -- 
  -- === the two modeled classes the codec does not know ===
  -- AWS_BACKUP_WARM
  --   S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid storage class
  --   Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: client decodes StorageClass AWS_BACKUP_WARM
  -- AWS_BACKUP_LOW_COST_WARM
  --   S3.Attributes.Parse_Result: FLYOLOGY.OBJECT_STORAGE.S3.ATTRIBUTES.MALFORMED_ATTRIBUTES: invalid storage class
  --   Client.Low_Level: FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE: malformed GetObjectAttributes response
  FAILED: client decodes StorageClass AWS_BACKUP_LOW_COST_WARM
BUG REPRODUCED: 2 failed expectation(s)
```

The fifteen values are read out of the compiled model in the same run that rejects two of them, and the four response bodies differ only in the `<StorageClass>` text, so nothing but the enumeration membership decides pass or fail.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Shapes checked against the pinned botocore S3 model.

## What should happen

A GetObjectAttributes response naming any value in the pinned model's `StorageClass` enumeration must decode, including `AWS_BACKUP_WARM` and `AWS_BACKUP_LOW_COST_WARM`. The model is the authority the crate already uses for the same shape in `src/flyology-object_storage-s3-multipart_uploads.adb:687-689` and for the same two values in `src/flyology-object_storage-s3-replication.adb:485-488`.

## Suggested treatment

Replace the literal list at `src/flyology-object_storage-s3-attributes.adb:756-760` with a model-driven check, so it cannot drift again: look the value up in the `StorageClass` enumeration the compiled model already exposes, as `Valid_Enumeration` does at `src/flyology-object_storage-s3-multipart_uploads.adb:492-504`. No new public declaration is needed, and `Validate` keeps its current shape and exception. Adding the two missing literals would also close the defect, but it leaves the same duplication in place and it will drift again on the next model bump.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the other scripted GetObjectAttributes response cases, as one decode per modelled storage class driven through `Client.Low_Level.Decode_Get_Object_Attributes_Response` and asserted to succeed. Driving the assertion off the model's enumeration rather than off a second hand-written list keeps the test from drifting with the codec. No existing assertion has to be inverted. The spike is the test.

## Severity

A valid, modelled 200 is reported to the caller as a malformed response, and every typed and convenience GetObjectAttributes client sees it, because the check runs whenever the member is present and the member is present exactly when the caller selected `StorageClass`. It needs an object in one of two uncommon storage classes, so it is reachable only against AWS or an implementation that reports the AWS Backup classes, and the crate's own server never emits anything but `STANDARD`. Nothing is written or lost; the read is refused. Deterministic; not reproduced against a live server.
