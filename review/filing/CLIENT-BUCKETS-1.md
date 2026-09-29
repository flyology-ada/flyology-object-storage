Title: Bucket client recognises a credential rejection only at 401, so a stock 403 becomes Corrupt_Or_Invalid_Response
Labels: bug
Refs: CLIENT-LOW-4

## Summary

Every classifier in the bucket convenience client enumerates exact `(status, code)` pairs, and the only authentication pair enumerated is `(401, "InvalidAccessKeyId")`. No server in evidence answers a credential problem with 401: the pinned MinIO release answers an unknown access key with `403 InvalidAccessKeyId` and a wrong secret with `403 SignatureDoesNotMatch`, and this crate's own S3 application answers both with `403 SignatureDoesNotMatch`. The pair never matches, so a well-formed conclusive refusal is reported as `Corrupt_Or_Invalid_Response`, and because the same predicate also decides conclusiveness, every bucket mutation additionally reports `..._Outcome_Unknown`. The caller is told to reconcile a mutation the server refused before touching any state, on the most common operator error there is.

## Problem

Commit `5fe6e3e`.

`Normalize_Create_Bucket_Response` decides conclusiveness from an enumeration whose only authentication entry is at 401 (`src/flyology-object_storage-client-buckets.adb:4104-4115`):

```ada
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in "IllegalLocationConstraintException" |
           "InvalidArgument" | "InvalidBucketName" |
           "InvalidLocationConstraint" | "InvalidRequest" | "MalformedXML")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else
          (Value.Status = 409
           and then Code in "BucketAlreadyExists" |
             "BucketAlreadyOwnedByYou" | "TooManyBuckets")
        or else (Value.Status = 501 and then Code = "NotImplemented");
```

The reason derivation repeats the same two pairs and falls through to `Corrupt_Or_Invalid_Response` (`src/flyology-object_storage-client-buckets.adb:4123-4132`):

```ada
      Failure : constant Failure_Reason :=
        (if Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Conclusive_Rejection
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
```

and the same `Conclusive_Rejection` decides the mutation disposition (`src/flyology-object_storage-client-buckets.adb:4136-4143`):

```ada
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Creation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Created
            then Bucket_Creation_Completed
            elsif Conclusive_Rejection
            then Bucket_Definitely_Not_Created
            else Bucket_Creation_Outcome_Unknown),
```

The shape is not local to CreateBucket. The classifier shared by the generated bucket mutations has the identical enumeration (`src/flyology-object_storage-client-buckets.adb:26443-26453`):

```ada
   function Conclusive_Generated_Mutation_Rejection
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 400
       and then Code in
         "AccessControlListNotSupported" | "InvalidArgument" |
         "InvalidBucketName" | "InvalidRequest" | "MalformedXML")
      or else (Status = 401 and then Code = "InvalidAccessKeyId")
      or else (Status = 403 and then Code = "AccessDenied")
      or else (Status = 404 and then Code in "NoSuchBucket" | "NoSuchKey")
      or else (Status = 405 and then Code = "MethodNotAllowed")
      or else (Status = 501 and then Code = "NotImplemented"));
```

with the matching reason derivation at `src/flyology-object_storage-client-buckets.adb:26464-26477`. Bucket tagging repeats it at `:24417-24426` and `:24437-24450`, and the read path repeats it too (`src/flyology-object_storage-client-buckets.adb:23474-23477`):

```ada
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
```

`grep -c 'Status = 401 and then Code = "InvalidAccessKeyId"' src/flyology-object_storage-client-buckets.adb` returns 88, and the same three-line pattern appears 18 times in `src/flyology-object_storage-client-objects.adb` and 11 times in `src/flyology-object_storage-client-transfers.adb`.

Two documented public meanings are contradicted by the fall-through. `src/flyology-object_storage-client.ads:36`:

```ada
   --  @enum Corrupt_Or_Invalid_Response Response was not conclusive or valid
```

The MinIO and in-repo answers below are both conclusive and valid. `src/flyology-object_storage-client-buckets.ads:145-150`:

```ada
   --  What is known about one CreateBucket mutation after terminal drain.
   --  Unknown creation requires caller-selected HeadBucket reconciliation of
   --  ownership and location before any retry.
   --  @enum Bucket_Creation_Completed Complete validated 200 proves creation
   --  @enum Bucket_Definitely_Not_Created Non-admission or exact rejection
   --  @enum Bucket_Creation_Outcome_Unknown Creation must be reconciled
```

A caller who follows that instruction issues a HeadBucket reconciliation for a request the server refused before touching any state.

MinIO does not send 401. The image pinned at `tests/scripts/test-minio.sh:5` is `quay.io/minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e`, whose `--version` reports

```
minio version RELEASE.2025-09-07T16-13-09Z (commit-id=07c3a429bfed433e49018cb0f78a52145d4bedeb)
Runtime: go1.24.6 linux/arm64
```

Signing `GET /flyology-review-buckets?location` with this crate's own SigV4 over a raw loopback socket, a credential naming an access key MinIO does not have answers

```
HTTP/1.1 403 Forbidden
Content-Length: 378
Content-Type: application/xml
Server: MinIO

<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>InvalidAccessKeyId</Code><Message>The Access Key Id you provided does not exist in our records.</Message>...</Error>
```

and the same request signed with a different secret answers

```
HTTP/1.1 403 Forbidden
Content-Length: 433
Content-Type: application/xml
Server: MinIO

<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match the signature you provided. Check your key and signing method.</Message>...</Error>
```

A bodyless `HEAD /flyology-review-buckets` with the unknown key answers `403 Forbidden` with `Content-Length: 0` and the non-AWS header `X-Minio-Error-Code: InvalidAccessKeyId`, which this client does not read. No probed path produced a 401.

This crate's own server does not send 401 either. `Verify_Request` maps an unknown key and a bad signature alike to one status (`src/flyology-object_storage-server-authentication.adb:213-217`):

```ada
            if not Allowed
              or else not Valid_Principal (US.To_String (Principal))
            then
               return (Status => Credential_Rejected, others => <>);
            end if;
```

and that status is rendered as a signature failure (`src/flyology-object_storage-server-s3_applications.adb:1907-1910`):

```ada
         when Authentication.Credential_Rejected =>
            Send_Error
              (X, 403, "SignatureDoesNotMatch",
               "The request signature does not match", Resource);
```

so the client cannot classify its own server's credential rejection. `InvalidAccessKeyId` appears nowhere outside the three client bodies: `grep -rl InvalidAccessKeyId src/` matches only `client-buckets.adb`, `client-objects.adb` and `client-transfers.adb`.

The pinned model cannot settle the status either way. Reading the pinned botocore S3 model (botocore revision `36c34f15391da01cd717c73c0fffa747c9889768`, pinned at `coverage/corpora.lock.toml:3-8`) with `python3` for shapes whose name contains either code returns an empty list, so neither `InvalidAccessKeyId` nor `SignatureDoesNotMatch` is modelled with an `httpStatusCode`. The status the AWS service itself returns for these two codes was not checked against a live AWS endpoint.

No maintained document states that only 401 is recognised. `docs/compatibility/s3.md` and the qualification documents say nothing about which authentication status and code pairs are accepted; the nearest text describes the corpus rather than a limitation (`docs/qualification/list-buckets.md:21-22`):

```
The strict normalization corpus covers every accepted service status/code
pair, every non-complete HTTP result across all admission certainties, and an
```

One classifier does not fall through, and is wrong differently. `Normalize_Head_Bucket_Response` switches on status alone (`src/flyology-object_storage-client-buckets.adb:4806-4811`):

```ada
         elsif Value.Status in 301 | 307 | 400 | 501
         then Invalid_Request
         elsif Value.Status = 401
         then Authentication_Failed
         elsif Value.Status = 403
         then Authorization_Failed
```

so the bodyless MinIO credential rejection above is labelled `Authorization_Failed`, an authorisation failure, rather than an authentication one.

The unit corpus pins the 401-only behaviour. `tests/src/flyology-object_storage-client-buckets-testing.adb:129-130` is the ListBuckets row:

```ada
      Check_List_Buckets_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
```

`:270-272` is the CreateBucket row and `:436-439` the DeleteBucket row:

```ada
      Check_Delete_Bucket_Response
        (401,
         "InvalidAccessKeyId",
         Bucket_Definitely_Not_Deleted,
         Authentication_Failed);
```

The file carries 32 such `401, "InvalidAccessKeyId"` rows in total. Neither that file nor `tests/src/s3_http_socket_corpus.adb` contains a single `403 InvalidAccessKeyId` or `SignatureDoesNotMatch` row: `grep -rn 'SignatureDoesNotMatch' tests/src/` matches only the server-side corpus. The socket corpus builds its bucket rejection assertions on `403 AccessDenied` (`tests/src/s3_http_socket_corpus.adb:11360`, `:10722`, `:10445`), which is one of the two enumerated pairs, so it passes. `Check_Head_Bucket_Response (403, Authorization_Failed)` at `tests/src/flyology-object_storage-client-buckets-testing.adb:588` pins the HeadBucket mislabel as well.

## What happens now

Spike: the program below first sends two requests to this crate's own S3 application in process, one whose Authorization credential names an access key the server does not have and one with a single signature hex digit flipped, and prints the status and `<Code>` of each answer. It then serves the verbatim MinIO 403 documents from a scripted loopback origin and drives three public entry points through them, one read and two mutations, asserting `Authentication_Failed` and a definite disposition. Six control legs replay the two enumerated pairs, `401 InvalidAccessKeyId` and `403 AccessDenied`, through the same code.

The scripted bodies are MinIO's, byte for byte:

```ada
   Invalid_Key_Body : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" & ASCII.LF &
     "<Error><Code>InvalidAccessKeyId</Code><Message>The Access Key Id you " &
     "provided does not exist in our records.</Message><BucketName>" & ...
   Bad_Signature_Body : constant String :=
     "<?xml version=""1.0"" encoding=""UTF-8""?>" & ASCII.LF &
     "<Error><Code>SignatureDoesNotMatch</Code><Message>The request " &
     "signature we calculated does not match the signature you provided. " & ...
```

The calls and the assertions:

```ada
      Result : constant Buckets.Get_Bucket_Location_Result :=
        Buckets.Get_Location
          (HTTP, Origin, Bucket, Parameters, Identity, Timeout => 10.0);
...
      Check (Result.Failure = Expected,
             Label & ": GetBucketLocation Failure is " &
               Client_API.Failure_Reason'Image (Expected));
...
      Result : constant Buckets.Put_Bucket_Tagging_Result :=
        Buckets.Put_Tags
          (HTTP, Origin, Bucket, Sample_Tags, Parameters, Identity,
           Timeout => 10.0);
...
      Check (Result.Disposition = Disposition,
             Label & ": PutBucketTagging Disposition is " &
               Buckets.Bucket_Tag_Mutation_Disposition'Image (Disposition));
...
      Result : constant Buckets.Create_Bucket_Result :=
        Buckets.Create
          (HTTP, Origin, Bucket, Parameters, Identity, Timeout => 10.0);
...
      Check (Result.Disposition = Disposition,
             Label & ": CreateBucket Disposition is " &
               Buckets.Bucket_Creation_Disposition'Image (Disposition));
```

driven with the expectations the documented enums require:

```ada
   Run_Location
     ("403 InvalidAccessKeyId/location", Client_API.Authentication_Failed);
   Run_Location
     ("403 SignatureDoesNotMatch/location", Client_API.Authentication_Failed);
   Run_Put_Tags
     ("403 InvalidAccessKeyId/put-tags", Client_API.Authentication_Failed,
      Buckets.Bucket_Tag_Mutation_Definitely_Not_Applied);
   Run_Put_Tags
     ("403 SignatureDoesNotMatch/put-tags", Client_API.Authentication_Failed,
      Buckets.Bucket_Tag_Mutation_Definitely_Not_Applied);
   Run_Create
     ("403 InvalidAccessKeyId/create", Client_API.Authentication_Failed,
      Buckets.Bucket_Definitely_Not_Created);
```

Output, exit status 1:

```
  -- --- what this crate's own S3 server answers ---
  -- own server, unknown access key: HTTP 403 <Code> = "SignatureDoesNotMatch"
  -- own server, wrong signature: HTTP 403 <Code> = "SignatureDoesNotMatch"
  -- scripted loopback origin on 127.0.0.1:58231
  -- --- MinIO shape: 403 InvalidAccessKeyId / SignatureDoesNotMatch ---
  -- 403 InvalidAccessKeyId/location: status 403, Error.Code = "InvalidAccessKeyId", Failure = CORRUPT_OR_INVALID_RESPONSE
  FAILED: 403 InvalidAccessKeyId/location: GetBucketLocation Failure is AUTHENTICATION_FAILED
  -- 403 SignatureDoesNotMatch/location: status 403, Error.Code = "SignatureDoesNotMatch", Failure = CORRUPT_OR_INVALID_RESPONSE
  FAILED: 403 SignatureDoesNotMatch/location: GetBucketLocation Failure is AUTHENTICATION_FAILED
  -- 403 InvalidAccessKeyId/put-tags: status 403, Error.Code = "InvalidAccessKeyId", Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  FAILED: 403 InvalidAccessKeyId/put-tags: PutBucketTagging Failure is AUTHENTICATION_FAILED
  FAILED: 403 InvalidAccessKeyId/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 403 SignatureDoesNotMatch/put-tags: status 403, Error.Code = "SignatureDoesNotMatch", Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  FAILED: 403 SignatureDoesNotMatch/put-tags: PutBucketTagging Failure is AUTHENTICATION_FAILED
  FAILED: 403 SignatureDoesNotMatch/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 403 InvalidAccessKeyId/create: status 403, Error.Code = "InvalidAccessKeyId", Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_CREATION_OUTCOME_UNKNOWN
  FAILED: 403 InvalidAccessKeyId/create: CreateBucket Failure is AUTHENTICATION_FAILED
  FAILED: 403 InvalidAccessKeyId/create: CreateBucket Disposition is BUCKET_DEFINITELY_NOT_CREATED
  -- --- control: the enumerated 401 InvalidAccessKeyId pair ---
  -- 401 InvalidAccessKeyId/location: status 401, Error.Code = "InvalidAccessKeyId", Failure = AUTHENTICATION_FAILED
  ok: 401 InvalidAccessKeyId/location: GetBucketLocation Failure is AUTHENTICATION_FAILED
  -- 401 InvalidAccessKeyId/put-tags: status 401, Error.Code = "InvalidAccessKeyId", Failure = AUTHENTICATION_FAILED, Disposition = BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  ok: 401 InvalidAccessKeyId/put-tags: PutBucketTagging Failure is AUTHENTICATION_FAILED
  ok: 401 InvalidAccessKeyId/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 401 InvalidAccessKeyId/create: status 401, Error.Code = "InvalidAccessKeyId", Failure = AUTHENTICATION_FAILED, Disposition = BUCKET_DEFINITELY_NOT_CREATED
  ok: 401 InvalidAccessKeyId/create: CreateBucket Failure is AUTHENTICATION_FAILED
  ok: 401 InvalidAccessKeyId/create: CreateBucket Disposition is BUCKET_DEFINITELY_NOT_CREATED
  -- --- control: the enumerated 403 AccessDenied pair ---
  -- 403 AccessDenied/location: status 403, Error.Code = "AccessDenied", Failure = AUTHORIZATION_FAILED
  ok: 403 AccessDenied/location: GetBucketLocation Failure is AUTHORIZATION_FAILED
  -- 403 AccessDenied/put-tags: status 403, Error.Code = "AccessDenied", Failure = AUTHORIZATION_FAILED, Disposition = BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  ok: 403 AccessDenied/put-tags: PutBucketTagging Failure is AUTHORIZATION_FAILED
  ok: 403 AccessDenied/put-tags: PutBucketTagging Disposition is BUCKET_TAG_MUTATION_DEFINITELY_NOT_APPLIED
  -- 403 AccessDenied/create: status 403, Error.Code = "AccessDenied", Failure = AUTHORIZATION_FAILED, Disposition = BUCKET_DEFINITELY_NOT_CREATED
  ok: 403 AccessDenied/create: CreateBucket Failure is AUTHORIZATION_FAILED
  ok: 403 AccessDenied/create: CreateBucket Disposition is BUCKET_DEFINITELY_NOT_CREATED
  -- request 1: GET /flyology-review-buckets?location HTTP/1.1
  -- request 2: GET /flyology-review-buckets?location HTTP/1.1
  -- request 3: PUT /flyology-review-buckets?tagging HTTP/1.1
...
  -- request 11: PUT /flyology-review-buckets HTTP/1.1
  ok: the origin served all eleven exchanges
BUG REPRODUCED: 8 failed expectation(s)
```

The control legs differ from the failing legs only in the status line or the error code, so nothing about the transport, the signature or the body parse is involved. The status and code that reach the classifier are printed on each line and are exactly the ones MinIO sent.

The same classification is reached against the live container with no scripted bytes at all, through the same public calls:

```
  -- location/wrong-key: status 403, outcome GET_BUCKET_LOCATION_REJECTED
  -- location/wrong-key: Error.Code = "InvalidAccessKeyId"
  -- location/wrong-key: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE
  -- location/wrong-secret: Error.Code = "SignatureDoesNotMatch"
  -- location/wrong-secret: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE
  -- put-tags/wrong-key: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  -- put-tags/wrong-secret: Client.Buckets Failure = CORRUPT_OR_INVALID_RESPONSE, Disposition = BUCKET_TAG_MUTATION_OUTCOME_UNKNOWN
  -- put-tags/control: status 200, outcome BUCKET_TAGS_REPLACED
  -- put-tags/control: Client.Buckets Failure = NO_FAILURE, Disposition = BUCKET_TAG_MUTATION_COMPLETED
```

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. Compared against MinIO RELEASE.2025-09-07T16-13-09Z from the pinned image.

## What should happen

A `403` carrying `InvalidAccessKeyId` or `SignatureDoesNotMatch` is a conclusive, valid, modelled authentication rejection. It should be reported as `Authentication_Failed`, and a mutation refused that way should be `..._Definitely_Not_Applied` or `Bucket_Definitely_Not_Created`, because the server refused the request before touching any state. `src/flyology-object_storage-client.ads:36` reserves `Corrupt_Or_Invalid_Response` for a response that "was not conclusive or valid", and `src/flyology-object_storage-client-buckets.ads:146-147` and `:150` reserve the unknown disposition for a creation that "must be reconciled".

## Suggested treatment

The mechanical change is to add the observed pairs beside the existing 401 pairing in each classifier, for example in `Conclusive_Generated_Mutation_Rejection` at `src/flyology-object_storage-client-buckets.adb:26449-26450` and in the matching `Generated_Mutation_Response_Failure` at `:26467-26470`:

```ada
      or else (Status = 403
               and then Code in "AccessDenied" | "InvalidAccessKeyId" |
                 "SignatureDoesNotMatch")
```

with `InvalidAccessKeyId` and `SignatureDoesNotMatch` mapping to `Authentication_Failed` and `AccessDenied` staying `Authorization_Failed`. The same edit applies to `Normalize_Create_Bucket_Response` (`:4104-4132`), `Conclusive_Bucket_Tag_Rejection` and `Bucket_Tag_Response_Failure` (`:24417-24450`), `Normalize_Get_Bucket_Location_Response` (`:23474-23477`) and the remaining sites of the 88 the file carries.

This needs a maintainer decision, because the accepted pair set is externally visible policy under the "Decision authority" section of `AGENTS.md`:

- Which pairs count as conclusive authentication rejections. At minimum `403 InvalidAccessKeyId` and `403 SignatureDoesNotMatch`, both measured above. `403 RequestTimeTooSkewed` and `400 AuthorizationHeaderMalformed` are the same class of conclusive credential refusal and were not measured here.
- Whether the `(401, "InvalidAccessKeyId")` pairing is kept. Keeping it costs nothing and preserves the 32 existing unit rows; removing it makes the table describe only observed behaviour and forces those rows to change.
- Whether `Normalize_Head_Bucket_Response` (`src/flyology-object_storage-client-buckets.adb:4796-4816`) keeps classifying HeadBucket on status alone. It cannot distinguish authentication from authorisation without a code, and a bodyless 403 is exactly what MinIO sends for an unknown key, so today it answers `Authorization_Failed` for a credential failure.

The identical pattern appears 18 times in `src/flyology-object_storage-client-objects.adb` and 11 times in `src/flyology-object_storage-client-transfers.adb`, so the decision should be made once and applied uniformly. The fall-through also catches any other structured rejection whose exact pair is unlisted; the complementary gap for a bodyless or non-XML rejection, which reaches these convenience overloads through the `Raise_*_Exchange_Failure` mappers at `src/flyology-object_storage-client-buckets.adb:137-141`, is reported as {{ISSUE:CLIENT-LOW-4}}.

The regression test belongs in `tests/src/s3_http_socket_corpus.adb`, beside the existing bucket rejection assertions that use `403 AccessDenied` (`:11360`, `:10722`, `:10445`): add scripted `403 InvalidAccessKeyId` and `403 SignatureDoesNotMatch` responses for a read and for a mutation, and require `Authentication_Failed` with a definite disposition. `tests/src/s3_implementation_corpus.adb` should additionally drive one bucket mutation with a deliberately wrong secret, since that is observable against every server the compatibility matrix lists. The 401 rows in `tests/src/flyology-object_storage-client-buckets-testing.adb` (`:129-130`, `:270-272`, `:436-439` and 29 more) may stay if the 401 pairing is retained, but a fix must add the 403 rows beside them. The spike is the test.

## Severity

Anyone who mistypes an access key, lets a secret rotate, or points the client at a server that does not know their credential gets `Corrupt_Or_Invalid_Response` for a plain refusal, and for a bucket mutation is additionally told the outcome is unknown and must be reconciled by a HeadBucket read before any retry. That is the most common operator error there is, and the wrong disposition is the documented decision input for whether a mutation is safe to retry. It applies against the pinned MinIO release, against this crate's own S3 server, and against any server that follows the same convention; the status the AWS service returns for these two codes was not checked live. A caller who ignores the classification and reads `Result.Response.Error.Code` still sees the true code, which bounds the damage. The classification is a pure function of a status and a string, so no timing, load or container state is involved. Deterministic.
