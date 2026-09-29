# Correctness discovery: S3-DOMAIN-B (object-level typed codecs and shared vocabulary)

Scope: every file in the area was read completely against its `.ads`
contract: `src/flyology-object_storage-s3-errors.ad?` (40/149 lines),
`-copies.ad?` (49/385), `-object_reads.ad?` (56/337),
`-tagging.ad?` (61/615), `-deletions.ad?` (152/750),
`-object_lock.ad?` (165/863), `-multipart_uploads.ad?` (127/887),
`-attributes.ad?` (171/1001), `-annotations.ad?` (207/919), and
`src/flyology-object_storage-tags.ad?` (42/46), plus the parent-package
validators they call (`src/flyology-object_storage.ads:585-690`,
`.adb:822-955`) and `src/flyology-object_storage-s3-checksum_policy.ads:55-95`.
Reference material: the pinned model `review/baseline/service-2.json`
(shapes `CopyObjectResult`, `CopyPartResult`, `Delete`, `ObjectIdentifier`,
`DeleteObjectsOutput`, `DeletedObject`, `Error`, `GetObjectAttributesOutput`,
`GetObjectAttributesParts`, `ObjectPart`, `Checksum`, `StorageClass`,
`ListMultipartUploadsOutput`, `MultipartUpload`, `Tagging`, `Tag`,
`ObjectLockLegalHold`, `ObjectLockRetention`, `ObjectLockConfiguration`,
`DefaultRetention`, `AnnotationEntry`, `ListObjectAnnotationsOutput`, the
four annotation request shapes and the twenty `exception` shapes, all dumped
with python3), `docs/qualification/{delete-objects,copy-object,object-tagging,
bucket-tagging,get-object-attributes,object-annotations-backend-server}.md`,
`docs/compatibility/s3.md` rows for the area operations, and the generated
descriptor `src/flyology-object_storage-s3-model.adb:45387-45599` (query
location names only). Call sites confirmed in
`src/flyology-object_storage-server-s3_applications.adb` (DeleteObjects
`:17731-17963`, PutBucketTagging `:8261-8294`, PutObjectTagging
`:15940-15962`, `x-amz-tagging` `:11985-12002`/`:15070-15080`,
ListMultipartUploads `:11182-11286`, GetObjectAttributes `:16298-16341`,
PutObjectLockConfiguration `:10539-10587`, annotation routing
`:6495-6530`/`:7015-7019`/`:15700-15735`, final handler tail) and
`src/flyology-object_storage-client-low_level.adb` (`:1214-1224`,
`:2370-2381`, `:5324-5333`, `:11557-11628`, `:13380-13512`, `:14764`).
Coverage inspected: `tests/src/object_storage_test_cases.adb`
(`:11200-11290`, `:11440-11480`, `:10975`), `tests/src/s3_server_application_corpus.adb`
(`:6390-6425`, `:7330-7380`, `:13552`, `:13588`, `:14400-14495`,
`:16005-16030`), `tests/src/s3_http_socket_corpus.adb:12640-12700`,
`tests/src/s3_implementation_corpus.adb:1675-1812`,
`tests/src/s3_list_object_annotations_qualification.adb:50-83`, and the
existing reports `review/discovery-SERVER.md` (SERVER-1) and
`review/discovery-CLIENT-LOW.md` for overlap.

Out of scope here and not re-reviewed: the ListParts, CompleteMultipartUpload,
InitiateMultipartUpload and CopyPartResult codecs live in
`src/flyology-object_storage-s3-multipart.ad?` (S3-DOMAIN-A), `Content-Range`
and `Range` parsing live in `s3-core.adb` and `client-low_level.adb`, and the
S3 XML parser itself (`s3-xml.ad?`) belongs to WIRE.

Severity rubric: P0 memory or aliasing unsafety, security-relevant defect,
data loss or durability violation, hang or deadlock, or an interop-breaking
protocol violation that a stock client or server rejects; P1 wrong result or
unexpected exception on valid input via a reachable path, or a documented
contract violated (`.ads` comment, README, compatibility matrix,
qualification document); P2 edge-case incorrectness, wrong diagnostics, or
contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| S3-DOMAIN-B-1 | DeleteObjects request parser rejects namespace-free `<Delete>` bodies with `MalformedXML`; stock clients that omit `xmlns` (minio-go/`mc`, s3cmd) cannot batch-delete | P1 | High (code, model, test); Medium (which stock clients omit `xmlns`, from memory) |
| S3-DOMAIN-B-2 | PutBucketTagging rejects namespace-free `<Tagging>` bodies while PutObjectTagging and the client's own bucket-tagging response decoder accept them | P1 | Medium |
| S3-DOMAIN-B-3 | ListObjectAnnotations query parser binds `annotationPrefix`/`maxAnnotationResults`/`continuationToken`; the pinned model, the generated descriptor and Flyology's own client use `annotation-prefix`/`max-annotation-results`/`continuation-token`, so prefixed, bounded and paginated list requests get 400 | P1 | High |
| S3-DOMAIN-B-4 | ListMultipartUploads cursor-advance check compares URL-encoded markers bytewise; a valid truncated `encoding-type=url` page whose next key diverges at a non-ASCII or reserved byte makes the server answer 500 and the client raise `Invalid_Response` | P1 | High (mechanism, python-verified); Medium (frequency) |
| S3-DOMAIN-B-5 | GetObjectAttributes decoder hard-codes 13 `StorageClass` values; the model's `AWS_BACKUP_WARM` and `AWS_BACKUP_LOW_COST_WARM` are rejected as malformed | P2 | High |
| S3-DOMAIN-B-6 | PutObjectTagging reports tag-repertoire, duplicate-key and eleven-tag failures as `MalformedXML`, while the same failures through `x-amz-tagging` and PutBucketTagging report `InvalidTag` | P2 | Medium |
| S3-DOMAIN-B-7 | GetObjectAttributes decoder infers "multipart" from the mere presence of `<ObjectParts>` and then rejects valid `FULL_OBJECT` SHA/MD5/XXHASH checksums | P2 | Medium |

---

### S3-DOMAIN-B-1: DeleteObjects request parser rejects namespace-free `<Delete>` bodies with `MalformedXML`; stock clients that omit `xmlns` cannot batch-delete

**Location:** `src/flyology-object_storage-s3-deletions.adb:66-79`, `:380-393`;
`src/flyology-object_storage-server-s3_applications.adb:17731-17741`, `:17958-17963`.

**Severity:** P1. **Confidence:** High for the code path, the model and the
pinned test; Medium for the claim about which stock clients omit `xmlns`
(from memory, unverified; see the check method below).

**Evidence:**

`src/flyology-object_storage-s3-deletions.adb:66-79`
```ada
   overriding procedure Start_Element_Details
     (Item            : in out Delete_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      pragma Unreferenced (Item);
   begin
      if Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
        or else Attribute_Count /= 0
      then
         raise Malformed_Delete with
           "DeleteObjects namespace or attributes are invalid";
      end if;
   end Start_Element_Details;
```

`src/flyology-object_storage-server-s3_applications.adb:17731-17741` passes
the request body straight to the codec, and `:17958-17963` maps the
exception:
```ada
                  when Deletions.Malformed_Delete =>
                     Send_Error
                       (X, 400, "MalformedXML",
                        "The XML provided was not well-formed or did not " &
                        "validate against the published schema", Target_Text);
```

Model (`review/baseline/service-2.json`): the `Delete` shape carries no
`xmlNamespace`; only the `DeleteObjectsRequest.Delete` *member* does
(`{'locationName': 'Delete', 'xmlNamespace': {'uri': 'http://s3.amazonaws.com/doc/2006-03-01/'}}`).
In botocore that trait instructs SDK serializers to emit the attribute; it is
not a receiver-side validation rule, and the S3 XML for `Tagging`
(`Tagging.Parse`, `tagging.adb:43-90`, no `Start_Element_Details` override)
is accepted by this same server without any namespace.

`docs/qualification/delete-objects.md` documents the strictness ("XML
namespace, attributes, member order, duplicates ... are validated before the
relevant entry can reach storage"), so this is a deliberate policy; it is
reported because it is not an S3 protocol rule and it breaks a stock client.

**Failure scenario:** minio-go's `RemoveObjects` (used by `mc rm --recursive`
and `mc rb --force`) marshals `deleteMultiObjects{XMLName "Delete"; Quiet;
Objects []deleteObject "Object"}` with Go `encoding/xml`, which writes
`<Delete><Quiet>false</Quiet><Object><Key>k</Key></Object></Delete>` without
an `xmlns` attribute; s3cmd's batch delete builds the same document by string
concatenation (both from memory, unverified). Against the Flyology server the
root `Delete` start element arrives with an empty `Namespace_URI`,
`Start_Element_Details` raises `Malformed_Delete`, and the handler answers
`400 MalformedXML`. Every batch fails; nothing is deleted. The same request
succeeds against AWS S3 and MinIO, which is why `mc` works against both.

**Reproduction test sketch:** through `tests/src/s3_server_harness.adb` with
the memory backend, sign and send
`POST /bucket?delete` with `Content-MD5` and body
`<Delete><Object><Key>k</Key></Object></Delete>` after putting `k`.
Expected: `200` with `<DeleteResult ...><Deleted><Key>k</Key></Deleted></DeleteResult>`
(the answer AWS and MinIO give; check by running `mc rm` against a MinIO
container from `tests/scripts/test-minio.sh` and against this server).
Actual: `400 MalformedXML`. Unit level:
`Deletions.Parse_Request ("<Delete><Object><Key>k</Key></Object></Delete>")`
is expected to return one entry; it raises `Malformed_Delete`.

**Existing coverage:** `tests/src/object_storage_test_cases.adb:11450-11452`
asserts the rejection: `Must_Reject_Request ("<Delete><Object><Key>k</Key></Object></Delete>", "namespace-free DeleteObjects request was accepted")`,
i.e. the suite pins the behaviour this finding disputes.
`tests/src/s3_server_application_corpus.adb:16012-16022` sends a
namespace-free body that is malformed for another reason (no `Key`) and
expects `MalformedXML`. The external matrix uses s5cmd (aws-sdk-go v1, which
emits `xmlns`), so no lane ever sends a namespace-free body.

**Refutation attempts:** (a) looked for normalisation before the codec:
`:17731-17741` passes `Document` verbatim. (b) Checked whether the XML layer
supplies the S3 namespace implicitly: the unit test at `:11451` proves it
does not. (c) Checked whether the model makes the namespace mandatory on
receipt: the `Delete` shape has no `xmlNamespace`, and the object-tagging
codec in this same crate accepts any namespace. (d) Considered the stock
clients named in the brief: aws-cli/boto3, aws-sdk-go v1/v2 (s5cmd, rclone),
Java and PHP SDKs all emit `xmlns` from the member trait (from memory), so
they are unaffected; minio-go and s3cmd are the affected ones (from memory,
unverified).

---

### S3-DOMAIN-B-2: PutBucketTagging rejects namespace-free `<Tagging>` bodies while PutObjectTagging and the client's own bucket-tagging response decoder accept them

**Location:** `src/flyology-object_storage-s3-tagging.adb:434-448`, `:550-586`;
`src/flyology-object_storage-server-s3_applications.adb:8261-8271`, `:8284-8289`.

**Severity:** P1. **Confidence:** Medium (the code path is certain; the
stock-client claim is from memory, unverified).

**Evidence:**

`src/flyology-object_storage-s3-tagging.adb:434-448`
```ada
   overriding procedure Start_Element_Details
     (Item            : in out Bucket_Tagging_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then
            (not Item.Allow_Empty_Namespace or else Namespace_URI'Length > 0))
        or else Attribute_Count /= 0
      then
         raise Malformed_Tagging with
           "bucket tagging namespace or attributes are invalid";
      end if;
   end Start_Element_Details;
```

`src/flyology-object_storage-s3-tagging.adb:574-586`
```ada
   function Parse_Bucket ... is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => False));

   function Parse_Bucket_Response ... is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => True));
```

The server uses the strict form for requests
(`s3_applications.adb:8261-8271`, `Tagging.Parse_Bucket (Document, ...)`) and
maps `Malformed_Tagging` to `400 MalformedXML` (`:8284-8289`). The object
tagging handler (`tagging.adb:13-30`) overrides no `Start_Element_Details`,
so `PutObjectTagging` accepts a namespace-free body from the same client.
The spec grants the tolerance to the client only
(`tagging.ads:46-52`: "The official S3 namespace and an absent namespace are
accepted; foreign namespaces and attributes remain invalid"). Model: the
`Tagging` shape has no `xmlNamespace`; the trait sits on the request member
as a serializer instruction. `docs/qualification/bucket-tagging.md` lists
"strict namespace-aware XML and tag limits" among the offline gates, so the
behaviour is documented; it is reported for the same reason as B-1.

**Failure scenario:** `mc tag set alias/bucket "team=storage"` (minio-go
`pkg/tags` marshals `tagging{XMLName "Tagging"; TagSet}` with no namespace,
from memory, unverified) sends `<Tagging><TagSet><Tag><Key>team</Key><Value>storage</Value></Tag></TagSet></Tagging>`
with `Content-MD5`. `Parse_Bucket` sees the root with an empty
`Namespace_URI`, raises `Malformed_Tagging`, and the client receives
`400 MalformedXML` for a document AWS and MinIO accept. The same client's
`mc tag set alias/bucket/object ...` succeeds against this server.

**Reproduction test sketch:** harness memory server; signed
`PUT /bucket?tagging` with `Content-MD5` and the body above.
Expected `200`; actual `400 MalformedXML`. Unit level:
`Tagging.Parse_Bucket ("<Tagging><TagSet><Tag><Key>a</Key><Value>b</Value></Tag></TagSet></Tagging>")`
expected to return one tag; raises `Malformed_Tagging`, while
`Tagging.Parse_Bucket_Response` on the same string returns it.

**Existing coverage:** `tests/src/object_storage_test_cases.adb:11268-11270`
asserts that `Parse_Bucket` rejects a namespace-free document ("bucket
tagging document without the S3 namespace was accepted"), pinning the
disputed behaviour; `:11233-11243` asserts `Parse_Bucket_Response` accepts
it. `tests/src/s3_server_application_corpus.adb:7351-7366` checks only the
foreign-namespace (`urn:not-s3`) rejection; `:7339-7350` sends a
namespace-free document that is malformed anyway (missing `Value`).

**Refutation attempts:** looked for a request-side tolerant entry point
(none; `Parse_Bucket_Response` is only called from the client at
`client-low_level.adb:392`); checked that the object-tagging path really has
no namespace check (`rg Start_Element_Details tagging.adb` shows only the
bucket handler's overrides at `:414`/`:434`); confirmed the model puts no
`xmlNamespace` on `Tagging` itself.

---

### S3-DOMAIN-B-3: ListObjectAnnotations query parser binds camelCase names that the pinned model, the generated descriptor and Flyology's own client do not use

**Location:** `src/flyology-object_storage-s3-annotations.adb:137-167`, `:175-178`;
`src/flyology-object_storage-server-s3_applications.adb:6507-6521`, `:7015-7019`;
`src/flyology-object_storage-s3-model.adb:45597-45599`;
`src/flyology-object_storage-client-low_level.adb:1217-1221`, `:11605-11621`.

**Severity:** P1. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-s3-annotations.adb:137-167` (abridged)
```ada
                  elsif Name = "annotationPrefix" then
                     ...
                  elsif Name = "maxAnnotationResults" then
                     ...
                  elsif Name = "continuationToken" then
                     ...
                  else
                     raise Malformed_Annotation_Request with
                       "unsupported annotation query parameter";
```

Model (`review/baseline/service-2.json`, `ListObjectAnnotationsRequest`
querystring members, dumped with python3):
```python
{'VersionId': 'versionId', 'MaxAnnotationResults': 'max-annotation-results',
 'AnnotationPrefix': 'annotation-prefix', 'ContinuationToken': 'continuation-token'}
```
(`GetObjectAnnotation`/`PutObjectAnnotation`/`DeleteObjectAnnotation` use
`annotationName` and `versionId`, which the codec matches.)

Generated descriptor `src/flyology-object_storage-s3-model.adb:45597-45599`
```ada
                  return "max-annotation-results";
                  return "annotation-prefix";
```

The client builds the request from the model
(`client-low_level.adb:11605-11621` adds `MaxAnnotationResults`,
`AnnotationPrefix`, `ContinuationToken` by member name; `:1217-1221` emits
`SigV4.Pair (Model.Member_Location_Name (Input_Shape, Member), ...)`), so it
sends the hyphenated names. The server routes the query through the codec
(`s3_applications.adb:6507-6508`), records `Annotation_Query_Invalid` on
`Malformed_Annotation_Request` (`:6519-6521`) and answers
```ada
         Send_Error
           (X, 400, "InvalidArgument",
            "The object annotation request query is invalid", Target_Text);
```
(`:7015-7019`).

**Failure scenario:** a Flyology client (or any SDK generated from the pinned
model) lists annotations with a prefix:
`GET /b/k?annotation&annotation-prefix=meta` → `Parse_Query` hits the
`else` branch for `annotation-prefix` → `400 InvalidArgument`. Pagination is
impossible: page one succeeds (no optional member), returns
`NextContinuationToken`, and page two
(`?annotation&continuation-token=fos1....`) is rejected. Conversely a client
hand-coded to the server's spelling would be rejected by a server that
follows the model.

**Reproduction test sketch:** harness memory server, put an object with two
annotations, then `Low_Level.Prepare_List_Object_Annotations` with
`Has_Max_Annotation_Results => True, Max_Annotation_Results => 1`, execute
twice following `Next_Continuation_Token`. Expected: two one-entry pages.
Actual: the first request already fails with `400 InvalidArgument`
("The object annotation request query is invalid"). Raw form:
`GET /b/k?annotation&max-annotation-results=1` → 400, while
`GET /b/k?annotation&maxAnnotationResults=1` → 200.

**Existing coverage:** `tests/src/s3_server_application_corpus.adb:13552` and
`:13588` send `maxAnnotationResults` and therefore assert the non-model
spelling. `tests/src/s3_list_object_annotations_qualification.adb:50-53`,
`:76-83` only add the optional members when environment inputs are set, so
the default lane never sends them to a server. No test sends the model's
names to the server.

**Refutation attempts:** checked whether the generated descriptor was
produced from a different model revision (it carries the same hyphenated
names as the pinned JSON); searched the server for a second parser accepting
hyphenated names (`continuation-token` appears only in the ListObjectsV2 and
ListBuckets parsers at `:2271`/`:2507`); confirmed the route sniff at
`:6497-6499` uses `&annotationName=` (model-conformant) so only the three
list members are wrong.

---

### S3-DOMAIN-B-4: ListMultipartUploads cursor-advance check compares URL-encoded markers bytewise; valid truncated `encoding-type=url` pages can be rejected (server 500, client `Invalid_Response`)

**Location:** `src/flyology-object_storage-s3-multipart_uploads.adb:655-667`,
`:773-795`, `:823-828`;
`src/flyology-object_storage-server-s3_applications.adb:11200-11204`,
`:11218-11220`, `:11240-11244`, `:11274-11286`, final `when others`;
`src/flyology-object_storage-client-low_level.adb:13405`, `:13423-13426`.

**Severity:** P1. **Confidence:** High for the mechanism (verified with
python3 below); Medium for how often stock clients request URL encoding on
this operation.

**Evidence:**

`src/flyology-object_storage-s3-multipart_uploads.adb:655-667`
```ada
      elsif Value.Is_Truncated
        and then
          (US.To_String (Value.Next_Key_Marker) <
             US.To_String (Value.Key_Marker)
           or else
             (Value.Next_Key_Marker = Value.Key_Marker
              and then
                (US.Length (Value.Next_Upload_ID_Marker) = 0
                 or else Value.Next_Upload_ID_Marker =
                   Value.Upload_ID_Marker)))
      then
         raise Malformed_Upload_Listing with
           "ListMultipartUploads next cursor does not advance";
```

`Validate` runs in both `Parse_List_Multipart_Uploads` (`:788`) and
`Serialize_List_Multipart_Uploads` (`:828`). The server fills both markers
with the *encoded* text when `encoding-type=url` was requested
(`s3_applications.adb:11200-11204`, `:11218-11220`, `:11240-11244`):
```ada
                        function Encoded (Value : String) return String is
                          (if Request.URL_Encoding
                           then Encoding.URI_Encode
                             (Value, Encode_Slash => False)
                           else Value);
```
and its handler catches only `Malformed_List_Request` (`:11280-11286`), so
`Malformed_Upload_Listing` reaches the final handler, which answers
`500 InternalError` ("We encountered an internal error"). The client maps the
same exception to `Invalid_Response` (`client-low_level.adb:13423-13426`).

Percent-encoding is not order-preserving: every encoded byte starts with `%`
(0x25), which sorts below every unreserved byte (`-`, `.`, digits, letters,
`_`, `~`, and `/` which `Encode_Slash => False` keeps). python3 check:
```python
enc = lambda s: ''.join(c if (c.isalnum() and c.isascii()) or c in '-._~/' else ''.join('%%%02X' % b for b in c.encode()) for c in s)
# ('b','é2')  raw b<é2: True   encoded 'b' vs '%C3%A92': b<é2: False
# ('a9','a:') raw True          encoded 'a9' vs 'a%3A':    False
# ('aA','a[') raw True          encoded 'aA' vs 'a%5B':    False
```

**Failure scenario:** a bucket has in-progress uploads for keys `b1`, `b2`,
`é1`, `é2`, `é3`. A client pages with `max-uploads=2&encoding-type=url`.
Page 1 (no marker) returns `b1`, `b2`, truncated, `NextKeyMarker=b2`. Page 2
sends `key-marker=b2`; the server builds `Key_Marker = "b2"`, uploads `é1`,
`é2`, truncated, `Next_Key_Marker = Encoded("é2") = "%C3%A92"`. In
`Serialize_List_Multipart_Uploads`, `Validate` evaluates
`"%C3%A92" < "b2"` = True and raises; the request that the backend answered
correctly ends as `500 InternalError`. The same page produced by AWS (which
encodes `NextKeyMarker` the same way when `EncodingType=url` is requested)
makes the client raise `Invalid_Response` at `:13423-13426`. Pure-ASCII
keys trigger it too whenever the divergence byte is a reserved character
sorting above an unreserved one (`a9`→`a:`, `aA`→`a[`).

**Reproduction test sketch:** in-process memory server
(`tests/src/s3_memory_server.adb`): create the five multipart uploads, then
`GET /bucket?uploads&max-uploads=2&encoding-type=url` followed by the same
with `&key-marker=b2` (percent-encoded in the request). Expected: `200` with
`<KeyMarker>b2</KeyMarker>...<NextKeyMarker>%C3%A92</NextKeyMarker><IsTruncated>true</IsTruncated>`.
Actual: `500 InternalError`. Unit level:
`Multipart_Uploads.Parse_List_Multipart_Uploads` on a document containing
`<Bucket>x</Bucket><KeyMarker>b2</KeyMarker><NextKeyMarker>%C3%A92</NextKeyMarker><NextUploadIdMarker>u</NextUploadIdMarker><MaxUploads>2</MaxUploads><IsTruncated>true</IsTruncated><EncodingType>url</EncodingType>`
plus two `<Upload>` entries is expected to decode; it raises
`Malformed_Upload_Listing` ("next cursor does not advance").

**Existing coverage:** `tests/src/s3_http_socket_corpus.adb:12666-12694`
requests URL encoding with ASCII markers (`a+b`, `photos/Jan &`) only to
check echo mismatches; `tests/src/object_storage_test_cases.adb:10975` only
rejects `encoding-type=xml`. No test produces a truncated URL-encoded page
whose next key diverges at an encoded byte.

**Refutation attempts:** checked whether the server compares decoded values
(no: the `Response` record is built from `Encoded (...)` for `Key_Marker`,
`Next_Key_Marker`, keys and prefixes); whether the client could avoid it
(`Requested_URL_Encoding` is a supported parameter, `:13477-13484`); whether
`URI_Encode` with `Encode_Slash => False` is order-preserving (it is not, per
the python check); whether the sibling listing codecs share the check
(`rg "does not advance" src/*.adb` matches only this file, so DOMAIN-A is not
affected by this exact predicate).

---

### S3-DOMAIN-B-5: GetObjectAttributes decoder hard-codes 13 `StorageClass` values; the model's `AWS_BACKUP_WARM` and `AWS_BACKUP_LOW_COST_WARM` are rejected as malformed

**Location:** `src/flyology-object_storage-s3-attributes.adb:756-760`, `:775-779`;
`src/flyology-object_storage-client-low_level.adb:5324`, `:5331-5333`.

**Severity:** P2. **Confidence:** High.

**Evidence:**

`src/flyology-object_storage-s3-attributes.adb:756-760`
```ada
   function Valid_Storage_Class (Value : String) return Boolean is
     (Value in "STANDARD" | "REDUCED_REDUNDANCY" | "STANDARD_IA" |
       "ONEZONE_IA" | "INTELLIGENT_TIERING" | "GLACIER" |
       "DEEP_ARCHIVE" | "OUTPOSTS" | "GLACIER_IR" | "SNOW" |
       "EXPRESS_ONEZONE" | "FSX_OPENZFS" | "FSX_ONTAP");
```

`src/flyology-object_storage-s3-attributes.adb:775-779`
```ada
      if Value.Has_Storage_Class
        and then not Valid_Storage_Class (US.To_String (Value.Storage_Class))
      then
         raise Malformed_Attributes with "invalid storage class";
      end if;
```

Model `StorageClass` enum (python3 dump of `review/baseline/service-2.json`):
`['STANDARD', 'REDUCED_REDUNDANCY', 'STANDARD_IA', 'ONEZONE_IA', 'INTELLIGENT_TIERING', 'GLACIER', 'DEEP_ARCHIVE', 'OUTPOSTS', 'GLACIER_IR', 'SNOW', 'EXPRESS_ONEZONE', 'FSX_OPENZFS', 'FSX_ONTAP', 'AWS_BACKUP_WARM', 'AWS_BACKUP_LOW_COST_WARM']`
(15 values). The sibling codec in this area validates the same shape
dynamically against the model (`multipart_uploads.adb:492-504`, `:686-689`,
`Valid_Enumeration (..., Upload_Member_Shape (4))`) and
`s3-replication.adb:483-487` already knows both missing spellings. The client
maps the exception to `Invalid_Response` (`client-low_level.adb:5331-5333`).
`docs/qualification/get-object-attributes.md` claims the decoder covers the
pinned output shape ("The bounded codec rejects duplicate or misplaced
fields ... stale or inconsistent pagination"); the compatibility matrix row
(`docs/compatibility/s3.md:60`) claims a complete typed client.

**Failure scenario:** an AWS object whose storage class is
`AWS_BACKUP_WARM` (objects materialised by AWS Backup) is queried with
`x-amz-object-attributes: StorageClass` (alone or with other groups). AWS
answers `200` with `<StorageClass>AWS_BACKUP_WARM</StorageClass>`;
`Parse_Result` → `Validate` raises `Malformed_Attributes`, and every typed and
convenience GetObjectAttributes client reports "malformed GetObjectAttributes
response" for a valid, modelled response.

**Reproduction test sketch:** unit level:
`Attributes.Parse_Result ("<GetObjectAttributesResponse xmlns=""http://s3.amazonaws.com/doc/2006-03-01/""><StorageClass>AWS_BACKUP_WARM</StorageClass></GetObjectAttributesResponse>")`.
Expected: `Has_Storage_Class = True`, `Storage_Class = "AWS_BACKUP_WARM"`.
Actual: `Malformed_Attributes` ("invalid storage class"). The Flyology
server only emits `STANDARD`, so only a scripted socket response (the
`s3_http_socket_corpus` style) or AWS itself shows it.

**Existing coverage:** none pins the attributes list (`rg AWS_BACKUP
tests/src` matches only the replication corpus).

**Refutation attempts:** checked whether `Storage_Class` is skipped unless
selected (it is validated whenever present, and it is present whenever the
caller selects it); whether a caller could avoid selecting it (yes, but the
convenience clients expose the selection to users); whether the generated
model lacks the two values (the JSON has 15 and `s3-replication.adb` decodes
both, so the model is not the limitation).

---

### S3-DOMAIN-B-6: PutObjectTagging reports tag-repertoire, duplicate-key and eleven-tag failures as `MalformedXML`, while the same failures through `x-amz-tagging` and PutBucketTagging report `InvalidTag`

**Location:** `src/flyology-object_storage-s3-tagging.adb:60-65`, `:153-174`;
`src/flyology-object_storage-server-s3_applications.adb:15956-15962`;
contrast `:15075-15079`, `:11994-11999`, `:8290-8294`.

**Severity:** P2 (wrong diagnostics). **Confidence:** Medium: the internal
inconsistency is verified; AWS's `InvalidTag` code for PutObjectTagging
bodies is from memory, unverified (check with `tests/scripts/test-minio.sh`:
put a tag key containing `#` through PutObjectTagging and compare the
`<Code>`).

**Evidence:**

`src/flyology-object_storage-s3-tagging.adb:163-167` (object document parser)
```ada
      if not Handler.Seen_Tag_Set or else Handler.Depth /= 0
        or else not Valid_S3_Tags (Handler.Tags)
      then
         raise Malformed_Tagging with "invalid object tagging document";
      end if;
```
and `:60-65` raise `Malformed_Tagging` ("invalid object tag entry") for the
eleventh `<Tag>`. `Invalid_Tag` is declared for this package
(`tagging.ads:9`) but the object parser never raises it. The server maps
the object path to
```ada
                        when Tagging.Malformed_Tagging =>
                           Send_Error
                             (X, 400, "MalformedXML",
                              "The XML provided did not validate against " &
                              "the object tagging schema", Target_Text);
```
(`s3_applications.adb:15956-15960`), while the same validator failures
(`Valid_S3_Tags`, `:392-395`) via `x-amz-tagging` on PutObject
(`:15075-15079`) and CreateMultipartUpload (`:11994-11999`) produce
`400 InvalidTag`, and the bucket path separates `Invalid_Tag` from
`Malformed_Tagging` (`:8284-8294`).
`tests/src/s3_server_application_corpus.adb:6420-6422` asserts
`InvalidTag` for eleven tags and a malformed tag on the header path.

**Failure scenario:** a client sends `PUT /b/k?tagging` with a well-formed
`<Tagging>` document whose key is `a#b` (outside the allowed repertoire),
or with two `<Tag>` entries sharing a key, or with eleven tags. The server
answers `MalformedXML` ("did not validate against the object tagging
schema"), which SDKs and users read as an XML syntax problem, while the same
tag set through `x-amz-tagging` on the same server yields `InvalidTag`.

**Reproduction test sketch:** harness memory server; signed
`PUT /b/k?tagging` with `Content-MD5` and
`<Tagging><TagSet><Tag><Key>a#b</Key><Value>v</Value></Tag></TagSet></Tagging>`.
Expected `400 InvalidTag` (consistent with `:15075-15079` and, from memory,
AWS); actual `400 MalformedXML`. Same for a duplicated key and for eleven
tags.

**Existing coverage:** `tests/src/s3_server_application_corpus.adb:14400-14495`
covers PutObjectTagging admission (size, digest, content type, malformed
syntax) but asserts no code for an invalid tag value; `:6420-6422` asserts
`InvalidTag` only through the header form.

**Refutation attempts:** checked whether `Valid_S3_Tags` failures are raised
as `Invalid_Tag` anywhere on the object XML path (no: `:163-167` and
`:169-173` collapse everything into `Malformed_Tagging`); checked whether
the server re-validates the parsed set before storage to emit `InvalidTag`
(no: `:15940-15954` stores the parsed set directly).

---

### S3-DOMAIN-B-7: GetObjectAttributes decoder infers "multipart" from the presence of `<ObjectParts>` and then rejects valid `FULL_OBJECT` SHA/MD5/XXHASH checksums

**Location:** `src/flyology-object_storage-s3-attributes.adb:422-428`, `:707-754`,
`:771-774`, `:857-878`; `src/flyology-object_storage-s3-checksum_policy.ads:70-75`.

**Severity:** P2. **Confidence:** Medium (the decoder logic is certain; the
concrete stock-server trigger is from memory, unverified).

**Evidence:**

`src/flyology-object_storage-s3-attributes.adb:771-774`
```ada
      if Value.Has_Checksum then
         Validate_Object_Checksum
           (Value.Checksum, Is_Multipart => Value.Has_Object_Parts);
      end if;
```
`Has_Object_Parts` is set on element presence alone (`:422-428`). Inside
`Validate_Object_Checksum` (`:731-738`):
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
with `src/flyology-object_storage-s3-checksum_policy.ads:70-75`
```ada
   function Supported
     (Value : Algorithm; Kind : Checksum_Type) return Boolean is
     (case Kind is
         when Full_Object =>
           Value in Core.CRC32 | Core.CRC32C | Core.CRC64NVME,
         when Composite   => Value /= Core.CRC64NVME);
```
An absent `ChecksumType` is inferred as `FULL_OBJECT` for any plain Base64
value (`:871-876`), so the branch also fires for servers that omit the type.
Model: `GetObjectAttributesParts` is an ordinary optional member of
`GetObjectAttributesOutput`; nothing in the model ties its presence to a
multipart upload, and the request enum `ObjectAttributes` lets a caller
select `ObjectParts` for any object. The Flyology server sidesteps the
question by emitting `ObjectParts` only when `Snapshot.Is_Multipart`
(`s3_applications.adb:16314-16317`), so it never produces the combination
itself.

**Failure scenario:** a caller selects `Checksum,ObjectParts` on an object
uploaded in one PUT with `x-amz-checksum-sha256`. A server that reports the
parts container for such an object (MinIO stores an ordinary PUT as one part
and reports `PartsCount 1` with one `<Part>`; AWS's behaviour for
non-multipart objects is not settled by the model; both from memory,
unverified) answers with `<Checksum><ChecksumSHA256>...</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum><ObjectParts>...</ObjectParts>`.
`Validate` sees `Is_Multipart = True`, `Supported (SHA256, Full_Object) =
False`, raises `Malformed_Attributes`, and the client reports
`Invalid_Response` for a response that is valid under the model.

**Reproduction test sketch:** unit level, independent of any server:
`Attributes.Parse_Result` on
`<GetObjectAttributesResponse xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Checksum><ChecksumSHA256>47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=</ChecksumSHA256><ChecksumType>FULL_OBJECT</ChecksumType></Checksum><ObjectParts><PartsCount>1</PartsCount><IsTruncated>false</IsTruncated><Part><PartNumber>1</PartNumber><Size>0</Size></Part></ObjectParts></GetObjectAttributesResponse>`.
Expected: decoded result with `Has_Checksum`, `Has_Object_Parts`, one part.
Actual: `Malformed_Attributes` ("invalid full-object checksum"). Live check:
`tests/scripts/test-minio.sh` environment, PUT with
`x-amz-checksum-sha256`, then GetObjectAttributes with
`x-amz-object-attributes: Checksum,ObjectParts`.

**Existing coverage:** `tests/src/s3_implementation_corpus.adb:1675-1700`
selects `Checksum` together with `ObjectParts` only for completed multipart
objects (CRC family) against RustFS and SeaweedFS; `:1786-1812` selects
`ObjectParts` alone. No case combines a non-CRC full-object checksum with a
present parts container.

**Refutation attempts:** looked for a stronger multipart signal available to
the decoder (`PartsCount > 1`, a composite `-N` suffix, or a multipart
ETag) that could replace container presence — none is used; checked whether
`Has_Object_Parts` could be false when the element is present but empty (no,
`:426-427` sets it on the start tag); confirmed the Flyology server cannot
produce the input, which is why the in-tree gates do not see it.

---

## Areas reviewed with no findings

- `Errors.Parse`/`Serialize` (`errors.adb:20-147`): root and depth checks,
  `RequestId`/`RequestID` and `HostId`/`HostID` spellings, duplicate
  detection, unknown members (including nested `Endpoint`, `Bucket`,
  `StringToSign*`) ignored, required non-empty `Code`/`Message`; HTML or empty
  bodies raise `Malformed_Error`, which every caller maps to
  `Invalid_Response`.
- `Tags.Valid_Bucket_Tag_Set` and `Valid_Tag_Text`
  (`flyology-object_storage.adb:822-955`): the UTF-8 decoder rejects
  overlongs, surrogates and code points above U+10FFFF, counts scalars not
  bytes, enforces 1..128/0..256, the `aws:` prefix and case-sensitive
  uniqueness; the L/N/Z plus `_.:/=+-@` repertoire matches AWS's rule.
- `Object_Lock` (all six subprograms): consistent-namespace rule, exact
  `ON`/`OFF`, `GOVERNANCE`/`COMPLIANCE`, `Enabled` values, strict but
  AWS-compatible ISO-8601 (`Z` or `±hh:mm`, up to nine fraction digits),
  arbitrary-precision `Days`/`Years` text, presence-preserving serializers with
  correct depth/element/text budget checks, empty payload for an absent outer
  member. `Days` versus `Years` exclusivity is deliberately not a codec rule
  (`object_lock.ads:118-121`) and the server refuses any `Rule` with
  `NotImplemented` (`s3_applications.adb:10556-10560`).
- `Deletions.Parse_Delete_Object_Query`, `Valid_Version_ID`,
  `Parse_Result`, `Serialize_Result`, `Serialize_Request`: quiet mode
  suppresses only `<Deleted>` entries (`s3_applications.adb:17884-17897`),
  errors are always reported, interleaved `<Deleted>`/`<Error>` and unknown
  members are handled, `DeleteMarker`/`DeleteMarkerVersionId` round-trip, the
  1000-entry and 1001st-entry bounds hold on both sides, keys are XML-escaped
  on output and decoded on input, empty `<Delete/>` is rejected (as AWS does).
- `Object_Reads.Parse_Query` and `Parse_Conditional_Date`: strict percent
  decoding with literal `+`, bounded and unique members, CR/LF/NUL rejection
  in response overrides, `partNumber` in 1..10000, all three RFC 9110 date
  forms with the fifty-year rule; the exact `x-id` values.
- `Tagging.Parse_Query`, `Parse_Header`, `Serialize_Header`, `Serialize`,
  `Serialize_Bucket`, and the object `Parse` structure checks: ten-tag bound,
  key/value size bounds, percent-encoding with RFC 3986 unreserved set,
  duplicate-key rejection, empty `<TagSet/>` accepted for objects.
- `Attributes.Parse_Selection`, `Image`, `Parse_Query`, and the SAX handler
  for `Checksum`/`ObjectParts`/`Part`: exact enum values with OWS, unique
  selection, `PartsCount` location name, 64-bit `Size`/`ObjectSize`,
  marker/count bounds, strictly increasing part numbers, composite count
  consistency, single-algorithm parts.
- `Multipart_Uploads.Parse_List_Multipart_Uploads_Query` and the SAX handler:
  required `uploads` marker, `url` encoding type, flattened `Upload` entries,
  `CommonPrefixes/Prefix`, `Owner`/`Initiator`, model-driven `StorageClass`,
  `ChecksumAlgorithm`, `ChecksumType`, `EncodingType` enumeration checks,
  duplicate-entry and grouped-key consistency.
- `Annotations` entry handler, `Encode_Continuation`/`Decode_Continuation`
  (scope-bound SHA-256 token, length pre-checked by
  `Core.Valid_Listing_Continuation_Syntax`), `Parse_List` via the shared
  paginated envelope, `Serialize_List` member names and order against the
  model (`AnnotationEntry` container, flattened `ChecksumAlgorithm`,
  required `AnnotationName`/`LastModified`/`Size`, `ReplicationStatus` five
  values, `MaxAnnotationResults` 1..1000).
- `Copies` SAX handler and `Validate_Checksum`: all 13 members, duplicate
  rejection, unknown members ignored, CRC64NVME never composite, composite
  `-N` suffix in 1..10000, exact Base64 digest lengths.

## Observations not counted

- `Copies.Validate` (`copies.adb:336-340`) requires both `ETag` (strong,
  quoted) and `LastModified` (strict ISO-8601) although every
  `CopyObjectResult` member is optional in the model; SeaweedFS's bare `ETag`
  is therefore rejected. `docs/qualification/copy-object.md` records this as a
  deliberate policy ("the production decoder continues to require one strong
  quoted entity-tag"), so it is listed rather than counted.
- Object `Tagging.Parse` requires `<Key>` before `<Value>` inside `<Tag>`
  (`tagging.adb:73-85`); the bucket parser does not. SDKs serialise in model
  order, so only hand-written clients are affected.
- `Tagging.Parse_Header` keeps `+` literal (documented policy,
  `tagging.ads:26-29`); whether AWS decodes `+` as a space in
  `x-amz-tagging` is unverified and checkable against MinIO/AWS.
- `Tags.Valid_Bucket_Tag_Set` rejects an empty set, so
  `Parse_Bucket_Response` raises `Invalid_Tag` on `<TagSet/>`; the tested
  servers answer `NoSuchTagSet` instead of an empty set, and the contract
  says "nonempty" (`tags.ads:35-38`).
- `Object_Reads.Parse_Conditional_Date`: `Ada.Calendar` limits (years
  1901..2399, `Duration` subtraction beyond about year 2262) yield
  `Valid => False`, which callers treat as an ignorable invalid HTTP-date per
  RFC 9110; harmless.
- `Multipart_Uploads.Parse_List_Multipart_Uploads_Query` rejects
  `max-uploads=0` and values above 1000 with `InvalidArgument` (documented
  1..1000 in `multipart_uploads.ads:35-37`); AWS clamps oversize values (from
  memory). Policy value.
- `Multipart_Uploads.Validate:642-654` rejects a non-truncated page that
  carries next markers and a truncated ungrouped page without
  `NextUploadIdMarker`; none of the tested servers emits those (MinIO, RGW and
  SeaweedFS set both only when truncated, from memory).
- `Annotations.Parse_List` requires the root `ListObjectAnnotationsOutput`;
  the model has no `locationName` for that output, so the live root name
  cannot be confirmed from the model.
- `Annotations.Decode_Continuation:246-250`: candidate `Constraint_Error` on
  tokens shorter than 70 bytes refuted; `Core.Valid_Listing_Continuation_Syntax`
  (`s3-core.adb:8-23`) enforces the header length first.
- `Deletions.Serialize_Request:408-412` emits `ETag` before `Key`; member
  order is not significant to REST-XML receivers.
- Mandatory `Content-MD5` on DeleteObjects is already SERVER-1
  (`review/discovery-SERVER.md:71`), not repeated here.
- The eleventh-tag and invalid-repertoire diagnostics on the object XML path
  are covered by B-6; the same limits on the header path already answer
  `InvalidTag`.
