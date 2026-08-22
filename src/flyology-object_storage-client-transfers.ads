with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Core;

--  Defines bounded multi-subject transfer policy shared by convenience client
--  operations. The execution implementation uses structured Flyology tasks.
package Flyology.Object_Storage.Client.Transfers is

   Minimum_Multipart_Part_Size : constant Byte_Count :=
     Flyology.Object_Storage.S3.Core.Minimum_Part_Size;
   Maximum_Multipart_Part_Size : constant Byte_Count :=
     Flyology.Object_Storage.S3.Core.Maximum_Part_Size;
   Default_Multipart_Threshold : constant Byte_Count := 64 * 1_024 * 1_024;
   Default_Multipart_Part_Size : constant Byte_Count := 16 * 1_024 * 1_024;

   type Upload_Outcome_Kind is (File_Uploaded, Upload_Rejected);

   type Upload_Outcome
     (Kind : Upload_Outcome_Kind := Upload_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when File_Uploaded =>
            Bytes      : Byte_Count := 0;
            Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
         when Upload_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Hash and upload one local file without retaining its contents. A single
   --  monotonic deadline is established before opening the file and is shared
   --  by hashing and HTTP execution. Open and Close are metadata syscalls, and
   --  a native positional read cannot be interrupted after entry, so timeout
   --  or cancellation delivery may be delayed by those operating-system calls.
   --  The same open descriptor is hashed and streamed, so replacement of the
   --  path cannot substitute a different file between those phases. The
   --  caller must prevent mutation of that file for the duration of the call;
   --  mutations affecting streamed bytes are rejected by S3 payload-hash
   --  validation. Client must already be configured for Origin. Files at or
   --  above Multipart_Threshold are split automatically. Parts for one file
   --  are sent sequentially through one open descriptor; Transfer_Many
   --  supplies bounded parallelism across independent subjects.
   --
   --  A timeout, cancellation, or transport failure after the complete-
   --  multipart request is sent is an ambiguous outcome: S3 may have
   --  committed the object even though no success response arrived. The
   --  implementation attempts AbortMultipartUpload on failure, but that is
   --  cleanup rather than a transactional rollback. Applications requiring
   --  certainty must reconcile with HeadObject or an application manifest.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination S3 bucket
   --  @param Key Destination S3 object key
   --  @param Local_Path Local file to hash and stream
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Content_Type Optional Content-Type request field
   --  @param Timeout Whole-operation budget; metadata syscalls may delay
   --     delivery after the deadline
   --  @param Token Optional cancellation source
   --  @param Multipart_Threshold Nonempty files at or above this size use
   --     multipart upload
   --  @param Multipart_Part_Size Multipart range size, from 5 MiB through
   --     5 GiB; a plan requiring more than 10,000 parts is rejected
   --  @return Typed successful upload or S3 rejection
   function Upload_File
     (Client       : aliased in out Flyology.HTTP.Client.Client;
      Origin       : Flyology.HTTP.Origin;
      Bucket       : String;
      Key          : String;
      Local_Path   : String;
      Identity     : Low_Level.Credentials;
      Region       : String := "us-east-1";
      Style        : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Timeout      : Duration := 30.0;
      Token        : access Flyology.Cancellation.Token := null;
      Multipart_Threshold : Byte_Count := Default_Multipart_Threshold;
      Multipart_Part_Size : Byte_Count := Default_Multipart_Part_Size)
      return Upload_Outcome;

   type Download_Outcome_Kind is (File_Downloaded, Download_Rejected);

   type Download_Outcome
     (Kind : Download_Outcome_Kind := Download_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when File_Downloaded =>
            Bytes      : Byte_Count := 0;
            Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
         when Download_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Stream one object into a same-directory temporary file, then atomically
   --  replace Local_Path only after the complete response is written and the
   --  temporary descriptor closes successfully. A failed request or transfer
   --  leaves an existing destination unchanged. Concurrent calls targeting
   --  the same Local_Path require caller synchronization, and the destination
   --  directory must not be concurrently writable by untrusted principals.
   --  One monotonic HTTP
   --  deadline covers the response head and body; local metadata syscalls and
   --  an in-progress native positional write can delay timeout or cancellation
   --  delivery. Client must already be configured for Origin.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Source S3 bucket
   --  @param Key Source S3 object key
   --  @param Local_Path Destination file atomically replaced on success
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget; local syscalls may delay delivery
   --  @param Token Optional cancellation source
   --  @return Typed successful download or S3 rejection
   function Download_File
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Local_Path : String;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Download_Outcome;

   type Failure_Mode is (Continue_After_Failure, Cancel_Remaining);

   type Batch_Options is record
      Maximum_Concurrent_Objects  : Positive := 16;
      Maximum_Concurrent_Requests : Positive := 32;
      Maximum_In_Flight_Bytes     : Byte_Count := 256 * 1_024 * 1_024;
      On_Failure                  : Failure_Mode := Continue_After_Failure;
      Multipart_Threshold         : Byte_Count :=
        Default_Multipart_Threshold;
      Multipart_Part_Size         : Byte_Count :=
        Default_Multipart_Part_Size;
   end record;

   type Transfer_Kind is (Upload, Download);

   type Subject is record
      Kind       : Transfer_Kind := Upload;
      Bucket     : Ada.Strings.Unbounded.Unbounded_String;
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Local_Path : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Subject_Array is array (Positive range <>) of Subject;

   type Transfer_Status is (Completed, Rejected, Failed, Cancelled);

   type Transfer_Result is record
      State      : Transfer_Status := Failed;
      Status     : Flyology.HTTP.Status_Code := 500;
      Bytes      : Byte_Count := 0;
      Entity_Tag : Ada.Strings.Unbounded.Unbounded_String;
      Error_Code : Ada.Strings.Unbounded.Unbounded_String;
      Message    : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   type Transfer_Result_Array is array (Positive range <>) of Transfer_Result;

   --  Execute Subjects in bounded structured waves. Each wave is a Flyology
   --  task scope and is fully joined before this call advances or returns.
   --  The effective worker count is the minimum of both concurrency caps and
   --  Maximum_In_Flight_Bytes / 64 KiB. The byte cap covers file-transfer
   --  buffers owned by this package; Flyology HTTP applies its own bounded
   --  protocol storage and the configured Client capacity remains an
   --  additional request-admission bound. Timeout is one shared batch budget,
   --  not a fresh budget per subject. Results retain input order.
   --  Cancel_Remaining requests the scope token after the first rejected or
   --  failed operation, joins every admitted sibling, and marks later waves
   --  cancelled. Parent cancellation is never propagated upward.
   --  Client and Identity are borrowed only until the fully joined return;
   --  callers must not concurrently finalize or otherwise mutate them. Each
   --  large upload automatically uses multipart, but its parts remain ordered
   --  and sequential; the runtime multiplexes and applies backpressure among
   --  the concurrently admitted subjects rather than spawning one task per
   --  part.
   --  @param Client Configured shared Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Subjects Ordered upload and download subjects
   --  @param Results Per-subject terminal results in matching index positions
   --  @param Identity Aliased credentials borrowed until the joined return
   --  @param Region SigV4 region
   --  @param Style Path or virtual-hosted addressing
   --  @param Options Independent concurrency, buffer, and failure policy
   --  @param Timeout One whole-batch monotonic budget
   --  @param Token Optional parent cancellation source
   procedure Transfer_Many
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Subjects : Subject_Array;
      Results  : out Transfer_Result_Array;
      Identity : aliased Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Options  : Batch_Options := (others => <>);
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
   with Pre => Subjects'First = Results'First
     and then Subjects'Last = Results'Last;

end Flyology.Object_Storage.Client.Transfers;
