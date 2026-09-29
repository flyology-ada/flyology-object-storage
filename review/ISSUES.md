# Filed issues

Repository: https://github.com/flyology-ada/flyology-object-storage. Filed from review commit 5fe6e3e.

| Finding | Issue | Title |
| --- | --- | --- |
| WIRE-1 | [#13](https://github.com/flyology-ada/flyology-object-storage/issues/13) | A C0 control byte in an accepted object key makes every listing without encoding-type=url answer 500 |
| WIRE-1b | [#14](https://github.com/flyology-ada/flyology-object-storage/issues/14) | A non-UTF-8 byte in an object key produces a 200 listing whose body is not the UTF-8 it declares |
| WIRE-2 | [#15](https://github.com/flyology-ada/flyology-object-storage/issues/15) | Read_Entity_Tag_List rejects empty list elements, so an If-Match with a trailing comma is answered 400 |
| WIRE-3 | [#16](https://github.com/flyology-ada/flyology-object-storage/issues/16) | A Range field whose unit is not bytes is answered 400 instead of being ignored |
| WIRE-4 | [#17](https://github.com/flyology-ada/flyology-object-storage/issues/17) | A key containing a carriage return is reported as a different key by listings without encoding-type=url |
| SIGV4-1 | [#18](https://github.com/flyology-ada/flyology-object-storage/issues/18) | A far-future x-amz-date escapes Verify_Request as Ada.Calendar.Time_Error and is answered 500 InternalError |
| SIGV4-2 | [#19](https://github.com/flyology-ada/flyology-object-storage/issues/19) | Static_Credentials.Create accepts principals over 256 bytes, so every correctly signed request is 403 |
| SERVER-1 | [#20](https://github.com/flyology-ada/flyology-object-storage/issues/20) | Operations the model marks requestChecksumRequired demand Content-MD5, so stock aws-cli v2 and boto3 are refused |
| SERVER-2 | [#21](https://github.com/flyology-ada/flyology-object-storage/issues/21) | Reading a key hidden by a delete marker is a bare 404, and reading the marker's own version is 404 instead of 405 |
| SERVER-3 | [#22](https://github.com/flyology-ada/flyology-object-storage/issues/22) | HeadObject emits x-amz-version-id: null for an object in a never-versioned bucket while GetObject omits it |
| SERVER-4 | [#23](https://github.com/flyology-ada/flyology-object-storage/issues/23) | CompleteMultipartUpload returns a path in <Location> where the model documents the URI of the new object |
| SERVER-5 | [#24](https://github.com/flyology-ada/flyology-object-storage/issues/24) | STREAMING-UNSIGNED-PAYLOAD-TRAILER is answered 400 AuthorizationHeaderMalformed instead of the 501 aws-chunked gets |
| CHECKSUM-1 | [#25](https://github.com/flyology-ada/flyology-object-storage/issues/25) | PutObject answers InvalidRequest for an SDK-algorithm and value-header mismatch where the model documents BadDigest |
| BACKEND-MEMORY-1 | [#26](https://github.com/flyology-ada/flyology-object-storage/issues/26) | ListMultipartUploads pagination silently drops same-key uploads whose upload IDs sort against initiation order |
| BACKEND-MEMORY-2 | [#27](https://github.com/flyology-ada/flyology-object-storage/issues/27) | Same-key CopyObject naming a source version is rejected as Invalid_Request, so a version restore never publishes |
| BACKEND-FILES-1 | [#28](https://github.com/flyology-ada/flyology-object-storage/issues/28) | Multipart completion in an unversioned bucket inherits the replaced object's annotations and orphans a sidecar |
| BACKEND-FILES-2 | [#29](https://github.com/flyology-ada/flyology-object-storage/issues/29) | Valid object keys beyond 464 bytes are unusable on the files backend and are reported as a retryable 503 |
| BACKEND-FILES-3 | [#30](https://github.com/flyology-ada/flyology-object-storage/issues/30) | Bucket-configuration readers size a stack local from the stored document, so a 3 MiB policy kills the process |
| BACKEND-FILES-4 | [#31](https://github.com/flyology-ada/flyology-object-storage/issues/31) | A failed DeleteObject destroys the object's acknowledged annotations while leaving the object in place |
| BACKEND-FILES-5 | [#32](https://github.com/flyology-ada/flyology-object-storage/issues/32) | Multipart operations with a valid upload ID but the wrong key answer Backend_Unavailable instead of Not_Found |
| BACKEND-FILES-6 | [#33](https://github.com/flyology-ada/flyology-object-storage/issues/33) | Deleting the newest generation lets the next PUT reuse the deleted generation's opaque version ID |
| BACKEND-SQLITE-1 | [#34](https://github.com/flyology-ada/flyology-object-storage/issues/34) | SQLite Get_Object opens the payload after the catalog gate is released, so a concurrent overwrite answers 503 |
| BACKEND-SQLITE-2 | [#35](https://github.com/flyology-ada/flyology-object-storage/issues/35) | The first CopyObject of an annotated SQLite object raises SQLite_Error from its own annotation lease CHECK(refs>0) |
| BACKEND-SQLITE-3 | [#36](https://github.com/flyology-ada/flyology-object-storage/issues/36) | A failed lease release in Find_Selected_Object leaks the SQLite catalog gate and the store stops answering |
| BACKEND-SQLITE-4 | [#37](https://github.com/flyology-ada/flyology-object-storage/issues/37) | SQLite Delete_Bucket reports Backend_Unavailable for a bucket whose keys are all delete markers |
| BACKEND-SQLITE-5 | [#38](https://github.com/flyology-ada/flyology-object-storage/issues/38) | The annotation qualification record claims SQLite corpus evidence that no test produces |
| CLIENT-LOW-1 | [#39](https://github.com/flyology-ada/flyology-object-storage/issues/39) | Execute_Head_Object rejects a valid 200 that omits x-amz-version-id after a versionId selector |
| CLIENT-LOW-2 | [#40](https://github.com/flyology-ada/flyology-object-storage/issues/40) | Execute_Get_Object_Attributes rejects the 200 the crate's own server returns for versionId=null |
| CLIENT-LOW-3 | [#41](https://github.com/flyology-ada/flyology-object-storage/issues/41) | Execute_Object_Tagging requires exactly one x-amz-version-id on every tagging success, even with no selector |
| CLIENT-LOW-4 | [#42](https://github.com/flyology-ada/flyology-object-storage/issues/42) | A bodyless or non-XML 4xx becomes Invalid_Response instead of a typed rejection with the wire status |
| CLIENT-LOW-5 | [#43](https://github.com/flyology-ada/flyology-object-storage/issues/43) | Prepare_Create_Session rejects the explicit Bucket_Key_Enabled False its specification says is preserved |
| CLIENT-LOW-6 | [#44](https://github.com/flyology-ada/flyology-object-storage/issues/44) | Execute_Create_Multipart_Upload sends a mismatched prepared request to the origin before rejecting it |
| CLIENT-LOW-7 | [#45](https://github.com/flyology-ada/flyology-object-storage/issues/45) | Valid_Model_Scalar accepts Ada literal integers, so Prepare_Model_Request signs and sends max-keys=1_000 |
| CLIENT-OBJECTS-1 | [#46](https://github.com/flyology-ada/flyology-object-storage/issues/46) | Get_Whole and Head_Object reject a valid 200 or 206 that omits x-amz-version-id after a versionId selector |
| CLIENT-OBJECTS-2 | [#47](https://github.com/flyology-ada/flyology-object-storage/issues/47) | Put_Tags, Get_Tags and Delete_Tags reject every successful tagging response that omits x-amz-version-id |
| CLIENT-OBJECTS-3 | [#48](https://github.com/flyology-ada/flyology-object-storage/issues/48) | GetObjectTorrent labels a 500 or 503 rejection No_Failure instead of Unavailable_Or_Retryable |
| CLIENT-BUCKETS-1 | [#49](https://github.com/flyology-ada/flyology-object-storage/issues/49) | Bucket client recognises a credential rejection only at 401, so a stock 403 becomes Corrupt_Or_Invalid_Response |
| CLIENT-BUCKETS-2 | [#50](https://github.com/flyology-ada/flyology-object-storage/issues/50) | A HeadBucket rejection discards x-amz-bucket-region, so Head cannot report where a redirected bucket lives |
| CLIENT-BUCKETS-3 | [#51](https://github.com/flyology-ada/flyology-object-storage/issues/51) | List_Page with a nonempty Prefix raises Invalid_Response against MinIO, which filters without echoing <Prefix> |
| TRANSFERS-1 | [#52](https://github.com/flyology-ada/flyology-object-storage/issues/52) | Download_File reports a 200 answer to a ranged GET as "GetObject returned an unsolicited representation interval" |
| S3-DOMAIN-A-1 | [#53](https://github.com/flyology-ada/flyology-object-storage/issues/53) | ListObjectVersions decoder rejects every version whose StorageClass is not STANDARD |
| S3-DOMAIN-A-2 | [#54](https://github.com/flyology-ada/flyology-object-storage/issues/54) | ListObjects v1 decoder rejects a truncated page that carries NextMarker without a delimiter |
| S3-DOMAIN-A-3 | [#55](https://github.com/flyology-ada/flyology-object-storage/issues/55) | Lifecycle and Notifications serializers reject U+007F that their own parsers and Replication accept |
| S3-DOMAIN-A-4 | [#56](https://github.com/flyology-ada/flyology-object-storage/issues/56) | Four list decoders require the botocore output shape name as the XML root, not the element AWS sends |
| S3-DOMAIN-A-5 | [#57](https://github.com/flyology-ada/flyology-object-storage/issues/57) | PutBucketVersioning rejects an unqualified root, so mc version enable cannot turn versioning on |
| S3-DOMAIN-A-6 | [#58](https://github.com/flyology-ada/flyology-object-storage/issues/58) | Listing query parsers reject max-keys above 1000 with 400 InvalidArgument instead of capping the page |
| S3-DOMAIN-A-7 | [#59](https://github.com/flyology-ada/flyology-object-storage/issues/59) | Versions.Validate rejects every untruncated MinIO ListObjectVersions page over a lone next marker |
| S3-DOMAIN-B-1 | [#60](https://github.com/flyology-ada/flyology-object-storage/issues/60) | Deletions.Parse_Request demands the S3 namespace on every element, so mc and s3cmd batch deletes are 400 MalformedXML |
| S3-DOMAIN-B-2 | [#61](https://github.com/flyology-ada/flyology-object-storage/issues/61) | Tagging.Parse_Bucket rejects a namespace-free `<Tagging>` body that PutObjectTagging on the same server accepts |
| S3-DOMAIN-B-3 | [#62](https://github.com/flyology-ada/flyology-object-storage/issues/62) | Annotations.Parse_Query binds camelCase query names the model and this crate's own client never send |
| S3-DOMAIN-B-4 | [#63](https://github.com/flyology-ada/flyology-object-storage/issues/63) | Multipart_Uploads.Validate compares URL-encoded cursors bytewise, so page 2 of an encoded listing is 500 |
| S3-DOMAIN-B-5 | [#64](https://github.com/flyology-ada/flyology-object-storage/issues/64) | Attributes.Valid_Storage_Class hard-codes 13 of the model's 15 storage classes, so AWS Backup objects decode as malformed |
| S3-DOMAIN-B-6 | [#65](https://github.com/flyology-ada/flyology-object-storage/issues/65) | PutObjectTagging answers MalformedXML for tag failures that the header form and PutBucketTagging answer InvalidTag |
| S3-DOMAIN-B-7 | [#66](https://github.com/flyology-ada/flyology-object-storage/issues/66) | The GetObjectAttributes decoder treats a present ObjectParts as proof of multipart and rejects full-object checksums |
| S3-DOMAIN-B-8 | [#67](https://github.com/flyology-ada/flyology-object-storage/issues/67) | The GetObjectAttributes decoder bounds a response's MaxParts echo by Core.Page_Size'Last, and MinIO echoes 10000 |
| S3-DOMAIN-B-9 | [#68](https://github.com/flyology-ada/flyology-object-storage/issues/68) | Parse_Bucket_Response applies the nonempty publication predicate to a response, so an empty TagSet is rejected |
| SERVER-EXE-1 | [#69](https://github.com/flyology-ada/flyology-object-storage/issues/69) | Administrator login runs 600,000 PBKDF2 iterations on the shared event loop and stalls every S3 request |
| SERVER-EXE-2 | [#70](https://github.com/flyology-ada/flyology-object-storage/issues/70) | Management route Concurrency and Rate_Per_Second policies are inert because no middleware is installed |
| SERVER-EXE-3 | [#71](https://github.com/flyology-ada/flyology-object-storage/issues/71) | Any FLYOLOGY_OBJECT_STORAGE_ROOT is opened as a store, deleting its pre-existing tmp and staging content |
| SERVER-EXE-4 | [#72](https://github.com/flyology-ada/flyology-object-storage/issues/72) | A failed start prints only the outcome name, discarding the supervisor's child, endpoint and exception |
| SERVER-EXE-5 | [#73](https://github.com/flyology-ada/flyology-object-storage/issues/73) | Two servers can open one files root at once because Files.Open takes no lock, unlike SQLite.Open |
| BASELINE-2 | [#74](https://github.com/flyology-ada/flyology-object-storage/issues/74) | The two s5cmd-driven CI jobs report success while the conformance script fails and reaches no server |
