# Correctness discovery: CLIENT-BUCKETS (bucket convenience client)

Scope: `src/flyology-object_storage-client-buckets.ads` (public contracts read for ListBuckets `:40-143`, CreateBucket `:145-330`, List/Head/Location/Versioning/Session `:930-979`, `:10115-10230`, `:10780-10942`, replication `:6763-6800`, the 25 generic instantiations `:12560-14700`, private completions `:15748-15850`) and `src/flyology-object_storage-client-buckets.adb` sampled by family: shared machinery `:1-450`; ListBuckets `:3839-4092`; CreateBucket `:4096-4240`; DeleteBucket `:4441-4600`; HeadBucket `:2749-2853`, `:4796-4900`; GetBucketLocation `:2855-2972`; tagging `:2974-3190`, `:24417-24870`; versioning `:3192-3455`, `:23749-24160`; CreateSession `:3455-3838`; GetBucketReplication `:5935-6140`; GetBucketLifecycleConfiguration `:1819-1851`, `:5619-5800`; ListBucketMetricsConfigurations `:6368-6470`; PutBucketReplication `:8663-8930`; DeleteBucketCors `:17561-17800`; RequestPayment read/write `:19802-19920`, `:22450-22520`; GetBucketPolicy `:1477-1577`, `:21855-21900`; generated region `:26237-26720` (ListDirectoryBuckets, shared generated-mutation classifiers, CreateBucketMetadataConfiguration). The remaining ~100 `Normalize_*`/`Conclusive_*`/`*_Response_Failure` bodies were inspected through a python extraction of their status/code sets rather than read linearly. Reference material: `src/flyology-object_storage-client-low_level.ad?` where the sampled paths delegate (ListBuckets decode `:4090-4178`, CreateBucket `:4378-4426`, HeadBucket `:4856-4967`, tagging `:182-240`, versioning `:4548-4625`, bucket-control mutation preparer `:10316-10830`), `src/flyology-object_storage-client.ads` (`Failure_Reason`), `src/flyology-object_storage-s3-buckets.ads`, `src/flyology-object_storage-s3-tagging.ads`, the pinned model `review/baseline/service-2.json` (queried with python for `httpChecksum`, `ContentMD5`, output header members, `required`, and error shapes of every sampled operation), `docs/architecture/client-buckets.md`, `docs/qualification/{list-buckets,head-bucket-composable,bucket-tagging}.md`, `review/discovery-CLIENT-LOW.md` and `review/discovery-SERVER.md` (SERVER-1) to avoid duplication, and `src/flyology-object_storage-server-s3_applications.adb:8795-8850` for the lifecycle integrity cross-check. Existing coverage inspected: `tests/src/flyology-object_storage-client-buckets-testing.ad?` (the per-family `Check_*_Corpus` procedures, HeadBucket corpus `:504-621`, 401/403 rows), `tests/src/s3_http_socket_corpus.adb` (grep for `Buckets.`, 401 rows), `tests/src/s3_implementation_corpus.adb` (which conveniences run against real servers), `tests/src/s3_put_bucket_lifecycle_configuration_corpus.adb`.

Severity rubric: P0 memory/aliasing unsafety, security (signature bypass, path or symlink escape, credential exposure, authorisation bypass), data loss or durability violation, hang or deadlock, or an interop-breaking protocol violation that a stock client or server rejects; P1 wrong result or unexpected exception on valid input via a reachable path, or a documented contract violated (`.ads`, README, compatibility matrix, qualification document); P2 edge-case incorrectness, wrong diagnostics, or contract drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| CLIENT-BUCKETS-1 | Authentication rejections are recognised only at HTTP 401; the 403 `InvalidAccessKeyId`/`SignatureDoesNotMatch` that real servers send is classified `Corrupt_Or_Invalid_Response` and, for every mutation, `..._Outcome_Unknown` | P2 | Medium |
| CLIENT-BUCKETS-2 | A bodyless HeadBucket rejection (301/307/403/404) discards `x-amz-bucket-region`, so `Client.Buckets.Head` cannot report the region a redirected bucket lives in (cross-area: drop is in Low_Level) | P2 | Medium |

Summary: no P0 or P1 findings. The bucket client is a thin, uniformly generated wrapper over `Client.Low_Level`; the sampled state machines, request sources, sinks, instantiation actuals, integrity-header choices, and per-operation error-code sets are mutually consistent and match the pinned model. The two findings are diagnostic: a whitelist-only classification that mislabels the most common credential error as a corrupt response and turns every mutation into "reconcile before retry", and a HeadBucket redirect whose region hint is captured and then thrown away.

---

### CLIENT-BUCKETS-1: Authentication rejections are recognised only at HTTP 401; the 403 `InvalidAccessKeyId`/`SignatureDoesNotMatch` that real servers send is classified `Corrupt_Or_Invalid_Response` and, for every mutation, `..._Outcome_Unknown`

**Location:** `src/flyology-object_storage-client-buckets.adb:4096-4133` (CreateBucket), `:4441-4478` (DeleteBucket), `:26443-26476` (shared generated-mutation classifier), `:24417-24450` (bucket tagging), `:5935-5975` (GetBucketReplication read), and the same three-line pattern in every other `Normalize_*_Response` / `Conclusive_*_Rejection` / `*_Response_Failure` in the file (about 80 sites; `rg -n '401 and then Code = "InvalidAccessKeyId"' src/flyology-object_storage-client-buckets.adb`).

**Severity:** P2. **Confidence:** Medium (the classification consequence is code-verified and pinned by the unit corpus; the statement that AWS S3 and MinIO answer a bad key or bad signature with HTTP 403 rather than 401 is from memory, unverified, and is the one fact a live run must confirm).

**Evidence:**

`src/flyology-object_storage-client-buckets.adb:4096-4133`
```ada
   function Normalize_Create_Bucket_Response
     (Value     : Low_Level.Create_Bucket_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Create_Bucket_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Create_Bucket_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in "IllegalLocationConstraintException" |
           "InvalidArgument" | "InvalidBucketName" |
           "InvalidLocationConstraint" | "InvalidRequest" | "MalformedXML")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        ...
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

`src/flyology-object_storage-client-buckets.adb:4135-4151`
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

`src/flyology-object_storage-client-buckets.adb:26443-26453` (shared by the eleven generated mutations: PutBucketAcl, PutBucketLogging, PutBucketWebsite, PutBucketInventoryConfiguration, CreateBucketMetadataConfiguration, the three metadata-table updates, and so on)
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

Contract being drifted from, `src/flyology-object_storage-client.ads:22-36`:
```ada
   --  Stable reason domain shared by composable provider results.
   --  @enum No_Failure Successful or conclusively failed condition
   --  @enum Authentication_Failed Modeled authentication rejection
   --  @enum Authorization_Failed Modeled authorization rejection
   ...
   --  @enum Corrupt_Or_Invalid_Response Response was not conclusive or valid
```
and `src/flyology-object_storage-client-buckets.ads:150-157`:
```ada
   --  Unknown creation requires caller-selected HeadBucket reconciliation of
   --  ownership and location before any retry.
   --  @enum Bucket_Creation_Completed Complete validated 200 proves creation
   --  @enum Bucket_Definitely_Not_Created Non-admission or exact rejection
   --  @enum Bucket_Creation_Outcome_Unknown Creation must be reconciled
```

Model: `review/baseline/service-2.json` has no error shape for `InvalidAccessKeyId` or `SignatureDoesNotMatch` (checked with python; only `AccessDenied` 403, `NoSuchBucket` 404, `BucketAlreadyExists`/`BucketAlreadyOwnedByYou` 409 carry `httpStatusCode`), so the model cannot settle the status. The AWS S3 API Reference "Error responses" table lists `InvalidAccessKeyId` and `SignatureDoesNotMatch` with HTTP 403 Forbidden and lists no 401 code at all (from memory, unverified). Nothing in this repository emits `InvalidAccessKeyId` on the server side (`rg -n InvalidAccessKeyId src/ server/src/` matches only the two client packages), so the 401 pairing is not derived from the Flyology server either.

**Failure scenario:**

1. A caller invokes `Client.Buckets.Create (..., Identity => <key that the server does not know>)` or any other bucket mutation against AWS S3 or MinIO.
2. The server answers `403 Forbidden` with a well-formed `<Error><Code>InvalidAccessKeyId</Code>...` body. `Low_Level.Decode_Create_Bucket_...` returns `Create_Bucket_Rejected` with `Status = 403`, `Error.Code = "InvalidAccessKeyId"`.
3. `Normalize_Create_Bucket_Response` (line 4096): `Conclusive_Rejection` is False (the only 403 pairing is `AccessDenied`), `Retryable_Response` is False, so `Failure = Corrupt_Or_Invalid_Response` and `Disposition = Bucket_Creation_Outcome_Unknown`.
4. The caller is told the response was "not conclusive or valid" and that creation "must be reconciled" by HeadBucket before any retry, although the server conclusively refused to authenticate the request and nothing was mutated. The typed `Response.Error` still carries the real code, so a caller that ignores `Failure`/`Disposition` and reads the error itself is unaffected.

The same fall-through applies to any structured rejection whose exact (status, code) pair is not enumerated: for example `403 SignatureDoesNotMatch`, `403 RequestTimeTooSkewed`, `400 AuthorizationHeaderMalformed`, `400 MalformedPolicy` on `Set_Policy` (`Conclusive_Bucket_Policy_Rejection`, line 22763, lists neither it nor `InvalidBucketName`), `404 NoSuchBucketPolicy` on `Get_Policy_Status` (line 22142 has no 404 pairing at all), and `404 NoSuchConfiguration` on `Get_Metadata_Table_Configuration` (line 9539) although the sibling `Get_Metadata_Configuration` (line 8222) does map it (the AWS codes named here are from memory, unverified).

**Reproduction test sketch:**

In-process, no external service: extend `tests/src/flyology-object_storage-client-buckets-testing.adb` `Check_Create_Bucket_Certainty_Corpus` (which drives `Normalize_Create_Bucket_Response` through the loopback fake server) with the row `(403, "InvalidAccessKeyId", Bucket_Definitely_Not_Created, Authentication_Failed)`. Expected: that disposition and failure. Actual with the current code: `Bucket_Creation_Outcome_Unknown` and `Corrupt_Or_Invalid_Response`. Live confirmation of the 403 status: run `Client.Buckets.Create` with a wrong access key against MinIO through `tests/scripts/test-minio.sh`'s server and print `Result.Response.Status` and `Result.Response.Error.Code`.

**Existing coverage:** `tests/src/flyology-object_storage-client-buckets-testing.adb:130, 271, 437, 711, 846, 982, 1120, 1257` and `tests/src/s3_http_socket_corpus.adb:12010, 12299, 19350` all assert the 401 pairing (`(401, "InvalidAccessKeyId", ..., Authentication_Failed)`), so the suite pins the 401-only behaviour; no test presents `403 InvalidAccessKeyId` or `403 SignatureDoesNotMatch`.

**Refutation attempts:** Looked for a shared status-normalisation step that would remap 403+InvalidAccessKeyId to 401 before these classifiers (none: the classifiers receive `Value.Status` straight from the Low_Level decoders, e.g. `Decode_Put_Bucket_Control_Response`). Checked whether the pinned model assigns a status to the two codes (it does not). Checked whether the Flyology server emits 401 for a bad key so that the pairing would at least match the in-repo server (`rg InvalidAccessKeyId src/ server/src/` finds no server emitter). Considered whether "unknown, reconcile first" is merely conservative: it is safe, which is why this is P2 rather than P1, but it contradicts the documented meaning of `Corrupt_Or_Invalid_Response` and forces a pointless HeadBucket round trip on the most common operator error.

---

### CLIENT-BUCKETS-2: A bodyless HeadBucket rejection (301/307/403/404) discards `x-amz-bucket-region`, so `Client.Buckets.Head` cannot report the region a redirected bucket lives in

**Location:** `src/flyology-object_storage-client-low_level.adb:4856-4872` and `:4907-4913` (`Head_Error`, non-200 branch of `Decode_Head_Bucket_Response`), `:4956-4967` (`Decode_Head_Bucket_Complete_Response` captures the header and then drops it); surfaced by `src/flyology-object_storage-client-buckets.adb:2808-2853` (`Head` convenience) and `:4796-4823` (`Normalize_Head_Bucket_Response`). Cross-area: the drop happens in CLIENT-LOW code, but the only public convenience that promises the region is in this area, and CLIENT-LOW did not report it.

**Severity:** P2. **Confidence:** Medium (the code path is verified; that AWS S3 attaches `x-amz-bucket-region` to the 301/403/404 HeadBucket responses used for region discovery, and that the botocore redirector relies on exactly that header, is from memory, unverified).

**Evidence:**

`src/flyology-object_storage-client-low_level.adb:4956-4967`
```ada
         Headers : constant Head_Bucket_Result :=
           (Bucket_ARN           => H ("x-amz-bucket-arn"),
            Bucket_Location_Type => H ("x-amz-bucket-location-type"),
            Bucket_Location_Name => H ("x-amz-bucket-location-name"),
            Bucket_Region        => H ("x-amz-bucket-region"),
            Access_Point_Alias   => Optional_Boolean_Header
              (Flyology.HTTP.Client.Header
                 (Response, "x-amz-access-point-alias")));
      begin
         return Decode_Head_Bucket_Response
           (Flyology.HTTP.Client.Status (Response), Payload, Headers,
```

`src/flyology-object_storage-client-low_level.adb:4907-4913` (every non-200 status; `Headers` is unused here)
```ada
      else
         return
           (Kind   => Head_Bucket_Rejected,
            Status => Status,
            Error  => Head_Error
              ("HeadBucket", Status, Request_ID, Host_ID));
      end if;
```

`src/flyology-object_storage-client-low_level.adb:4865-4871`
```ada
      return
         (Code       => US.To_Unbounded_String ("HTTP" & Status_Text),
         Message    => US.To_Unbounded_String
           (Operation & " returned HTTP status " & Status_Text),
         Resource   => US.Null_Unbounded_String,
```

`src/flyology-object_storage-client-buckets.adb:2831-2852`
```ada
            if Outcome.Kind = Low_Level.Head_Bucket_Rejected then
               return
                 (Kind => Head_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind                 => Bucket_Available,
               ...
               Region               =>
                 (if US.Length (Outcome.Result.Bucket_Region) = 0
                  then US.To_Unbounded_String (Region)
                  else Outcome.Result.Bucket_Region),
```

`src/flyology-object_storage-client-buckets.adb:4796-4816` (301 and 307 are labelled a request rejection)
```ada
         elsif Value.Status in 301 | 307 | 400 | 501
         then Invalid_Request
```

Contract, `src/flyology-object_storage-client-buckets.ads:10172-10186`:
```ada
   --  Probe one bucket without downloading a response body. Successful
   --  results preserve every modeled HeadBucket response header and expose
   --  the bucket region under the convenience-level Region name. ...
   --  @param Bucket Bucket whose availability and region are requested
   ...
   --  @return Modeled HeadBucket headers or structured bodyless rejection
```
`docs/qualification/head-bucket-composable.md:27-28` states that "cross-region redirect following" is outside the lane; it says nothing about exposing the region hint that a redirect carries.

Model: `review/baseline/service-2.json` models `BucketRegion` as the header `x-amz-bucket-region` on `HeadBucketOutput` and declares only `NoSuchBucket` as the modelled error, so the model does not say which statuses carry the header; the AWS S3 API Reference for HeadBucket documents 301 Moved Permanently for a bucket in another Region and the SDKs read `x-amz-bucket-region` from that 301 (and from the 403/404 variants) to retarget the request (from memory, unverified).

**Failure scenario:**

1. A caller signs for `us-east-1` and calls `Client.Buckets.Head (..., Bucket => "b", Region => "us-east-1")` for a bucket that lives in `eu-west-1`, or uses the composable `Head` + `Finish`.
2. AWS answers `301 Moved Permanently`, no body, with `x-amz-bucket-region: eu-west-1`.
3. `Decode_Head_Bucket_Complete_Response` (line 4956) copies the header into `Headers.Bucket_Region`, then `Decode_Head_Bucket_Response` (line 4907) returns `Head_Bucket_Rejected` with a synthesised `Error.Code = "HTTP301"`; `Headers` is discarded.
4. `Normalize_Head_Bucket_Response` labels it `Invalid_Request`; the convenience `Head` returns `Head_Rejected` with only that synthesised error. The one datum the redirect exists to convey is gone, and the caller has no way to recover it short of the raw `Low_Level` exchange. The documented purpose of the call ("availability and region are requested") is met only on 200.

**Reproduction test sketch:** In-process: add to `tests/src/flyology-object_storage-client-buckets-testing.adb` `Check_Head_Bucket_Result_Corpus` (line 567) a fake-server reply `301` with header `x-amz-bucket-region: eu-west-1` and no body; call the convenience `Head`. Expected: a rejection that still exposes `eu-west-1` (for example a `Region` component on the rejected variant, or the region in `Error.Message`). Actual: `Head_Rejected`, `Error.Code = "HTTP301"`, `Error.Message = "HeadBucket returned HTTP status 301"`, no region anywhere. Live confirmation of what AWS sends needs an AWS account and cannot be shown with MinIO/RustFS/SeaweedFS (single-region servers).

**Existing coverage:** `tests/src/flyology-object_storage-client-buckets-testing.adb:583-584` asserts `(301, Invalid_Request)` and `(307, Invalid_Request)` through the fake server, and the helper at `:504-515` builds the outcome from the status alone, so the suite pins the discard without ever supplying the header.

**Refutation attempts:** Checked whether the rejected variant of `Low_Level.Head_Bucket_Outcome` (`low_level.ads:1396-1405`) has any field other than `Status` and `Error` (it does not). Checked whether `Head_Error` folds the region into `Message` or `Resource` (it does not). Checked the qualification document for a stated exclusion of the region hint (only redirect *following* is excluded). Considered whether callers should use `Get_Location` instead: GetBucketLocation sent to the wrong region also answers 301 on AWS (from memory, unverified), so it does not substitute.

---

## Areas reviewed with no findings

- Shared convenience machinery, `client-buckets.adb:26-145`: `Failed_Reason`, `Timestamp` (the `Ada.Calendar.Formatting.Image` slice arithmetic yields `YYYYMMDDTHHMMSSZ` in UTC), and the per-operation `Raise_*_Exchange_Failure` mappers are consistent with each other.
- ListBuckets family (the paginated listing in this file), `:145-222`, `:3839-4092`, spec `:40-143`, `:930-979`: the convenience overload maps `Maximum`/`Continuation_Token`/`Prefix`/`Bucket_Region` to presence flags correctly (`Has_Continuation_Token => Length > 0`, `Has_Prefix => Length > 0`, `Has_Max_Buckets => True`); the owner-driven state machine (`Write` bound, `Complete_List_Buckets_Child`, `Drive`, `Request_Cancellation`, `Finalize`, `Start_List_Buckets`, `Finish`) releases the child exactly once on every path and clears the prepared request; the response bound is the shared XML document limit. Cursor semantics (ContinuationToken presence, MaxBuckets 1..10_000, prefix/region echo) live in `Low_Level.Decode_List_Buckets_Complete_Response` (`low_level.adb:4090-4178`) and `S3.Buckets`, checked against the pinned model (`ListBucketsOutput` members all optional).
- ListDirectoryBuckets (Paginated_REST_XML_Reads instance), `:26240-26440`, spec `:12573-12580`: actuals match the operation; `Collection_Limit` is threaded through; failure normaliser is the shared shape.
- CreateBucket, `:223-326`, `:4096-4180`, `:4180-4240` (one-shot request source: `Read_Now` offset arithmetic, `Source_Finished` on exhaustion, `Source_Wait_Source` immediate): the convenience derives `LocationConstraint` as documented (omitted for `us-east-1`, the signing region otherwise, explicit override wins); 409 `BucketAlreadyExists`/`BucketAlreadyOwnedByYou`/`TooManyBuckets` and 400 constraint errors are conclusive; a us-east-1 200 for an already-owned bucket is `Bucket_Creation_Completed`, which is what AWS intends there (from memory, unverified). `Location`/`x-amz-bucket-arn` are optional in `Low_Level.Decode_Create_Bucket_Complete_Response` (`low_level.adb:4384-4426`), so no optional-header-required predicate of the CLIENT-LOW-1 kind exists on this path.
- DeleteBucket and the thirteen bodyless configuration deletes (sampled DeleteBucketCors `:17561-17800`, plus the classifier extraction over all of them): known-empty non-rewindable source (`Known_Length (0)`), the sink accepts an XML error body up to the limit (so 409 `BucketNotEmpty` and 404 bodies still decode), 204 success via `Low_Level.Decode_Delete_Bucket_Configuration_Response`.
- HeadBucket state machine `:2749-2853`, `:4796-4900`: bodyless sink, header-only decode, documented signing-region fallback for a missing `x-amz-bucket-region` on 200. (Finding 2 concerns only the non-200 branch.)
- GetBucketLocation `:2855-2972`: `""`->`us-east-1`, `EU`->`eu-west-1`, everything else verbatim, legacy value preserved, matching the spec comment at `:10214-10216`.
- Bucket tagging `:2974-3190`, `:24417-24870`: Put sends an automatically generated Content-MD5 (and a checksum header when asked, `low_level.adb:182-240`); `NoSuchTagSet` maps to `Not_Found` on reads; the read bound is `min (caller limit, 1 MiB)`; `Request_Payer` is documented as rejected when nonempty (`low_level.ads:911-917`).
- Versioning `:3192-3455`, `:23749-24160`: the convenience `Set_Versioning` passes only Status; the full overload threads MFA and checksum; MFA on a cleartext origin and MFA-Delete without status/credential are rejected locally in `low_level.adb:4595-4610`, as the architecture document promises.
- CreateSession `:3455-3838`: raw response retained only until `Finish`; the limited zeroizing identity is constructed once; every exit path clears the prepared request and the response buffer; `Finish` on an exchange failure returns the typed failure rather than raising.
- Bounded reads (sampled GetBucketReplication `:5935-6140`, GetBucketLifecycleConfiguration `:5619-5800` incl. the `x-amz-transition-default-minimum-object-size` singleton header, GetBucketRequestPayment `:22450-22520`, GetBucketPolicy `:21855-21900`, ListBucketMetricsConfigurations `:6368-6470`): `pragma Unreferenced (Response)` in the generated `Decode_*` actuals is safe because the pinned model gives none of those outputs a header member (checked with python for all 27 read operations; only GetBucketLifecycleConfiguration and GetBucketAccelerateConfiguration have one, and both are handwritten and read it).
- Mutations (sampled PutBucketReplication `:8663-8930`, PutBucketRequestPayment `:19802-19920`, the shared generated-mutation helpers `:26443-26476`, `Decode_Create_Bucket_Metadata_Configuration_Family_Response` `:26546-26562`): disposition/failure derivation is uniform; non-replay is enforced by the generic state; integrity headers are decided in `Low_Level.Prepare_Bucket_Control_Mutation` (`low_level.adb:10316-10420`) and match the pinned `httpChecksum` traits for every bucket write checked (Versioning/Tagging/Policy/CORS/Encryption/Ownership/PublicAccessBlock/RequestPayment/ObjectLock send a generated Content-MD5; Lifecycle sends only the caller's required `x-amz-checksum-*`, which the in-repo server accepts and for which it forbids Content-MD5, `s3_applications.adb:8822-8833`; Replication sends both; Accelerate/Inventory/Notification/Analytics/Metrics/IntelligentTiering send neither, as modelled).
- All 25 generic instantiations (spec `:12573-14700`): `Operation_Name`, `Start_Exchange`, and `Decode_Response` actuals are mutually consistent (python extraction); no copy-paste divergence.
- Classification-set extraction over all ~130 `Normalize_*_Response` / `Conclusive_*` / `*_Response_Failure` bodies: the per-operation not-found codes (`NoSuchCORSConfiguration`, `ServerSideEncryptionConfigurationNotFoundError`, `NoSuchLifecycleConfiguration`, `ReplicationConfigurationNotFoundError`, `NoSuchConfiguration`, `NoSuchWebsiteConfiguration`, `OwnershipControlsNotFoundError`, `NoSuchPublicAccessBlockConfiguration`, `ObjectLockConfigurationNotFoundError`, `NoSuchBucketPolicy`, `NoSuchTagSet`) are attached to the right readers; the only gaps found are recorded under finding 1.

## Observations not counted

- ListBuckets prefix strictness (`low_level.adb:4139-4173`, documented in `docs/qualification/list-buckets.md:13-16`): a supplied prefix must be echoed byte-for-byte and every bucket name must match it, otherwise `List_Page` raises `Low_Level.Invalid_Response` (convenience) or reports `Corrupt_Or_Invalid_Response` (composable). Against a server that ignores `prefix` the caller gets a failure rather than the unfiltered page. Documented policy, not counted; the real-server corpus calls `List_Page` only without a prefix (`s3_implementation_corpus.adb:3182-3184`), so a MinIO/RustFS/SeaweedFS run with `Prefix => "x"` through `tests/scripts/test-*.sh` would settle interop.
- 301/307/400/501 on HeadBucket are labelled `Invalid_Request` (`:4810-4811`), which the `Failure_Reason` doc defines as a request rejection; a redirect is not one. Folded into finding 2.
- The generated result records (`Put_Bucket_Replication_Result`, spec `:6763-6772`, and every `*_Result` with a non-variant `Response` field) carry a synthesised `Status => 500, Kind => ..._Rejected` sentinel in the exchange-failed case (`:8746-8760`, `:6020-6030`). It is labelled inert and `Kind` selects it, but a caller that reads `Result.Response.Status` without checking `Result.Kind` sees a fake 500. Design choice; not counted.
- Convenience overloads translate `Pre_Admission_Rejected` into `Constraint_Error` (`:97`, `:124`, `:1246`) and the spec carries no `@exception` tags at all; the architecture document calls this the "established raising transport behavior". Documentation gap, not counted.
- Architecture document `docs/architecture/client-buckets.md:73-74` still says bucket-tagging checksum selection "currently fails locally until paired checksum generation is implemented"; `low_level.adb:222-240` now computes and signs every modelled algorithm and `docs/qualification/bucket-tagging.md:51-52` says so. Stale prose only.
- CreateSession keeps the raw XML (which contains the temporary secret) in `Response_Data` until `Finish`, then calls `Flyology.Bytes.Clear`, which the dependency documents as releasing storage, not zeroising it (`flyology-bytes.ads:78-80`). The spec promises zeroisation only for the decoded identity (`.ads:10915-10917`, `:10939-10941`), so no contract is violated; noted for the security-minded reader.
- `Head` convenience returns the signing region when `x-amz-bucket-region` is absent (`:2846-2849`), which conflates "server did not say" with "same region"; documented at `.ads:10174-10176`, so not counted.
- CLIENT-LOW-4 (bodyless or non-XML 4xx/5xx becoming `Invalid_Response`) is reachable through every convenience overload in this file (`Raise_*_Exchange_Failure` re-raises it); not duplicated here.
- Not reviewed: ListObjects v1/v2 and ListObjectVersions cursors, `encoding-type=url` decoding, `Contents`/`CommonPrefixes`/`Owner`/`RestoreStatus`/`ChecksumAlgorithm` typed outputs, and DeleteObjects. None of these live in `Client.Buckets` (they are in `Client.Objects` and `S3.Listings`, areas CLIENT-OBJECTS and S3-DOMAIN-A); the only ListObjectVersions text in this file is the disclaimer at `.ads:10801-10803`. Also not read line by line: the 23 generated read/mutation instances beyond the sampled ones (their shape was verified structurally through the extraction scripts), and the `Bounded_REST_XML_Reads` / `Paginated_REST_XML_Reads` / `REST_XML_Mutations` generic bodies themselves.
