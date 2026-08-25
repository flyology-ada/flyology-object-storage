with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;

package body Flyology.Object_Storage.Client.Transfers.Testing is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;

   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.Copy_Object_Outcome_Kind;
   use type Low_Level.Upload_Part_Copy_Outcome_Kind;

   procedure Check_Create_Multipart_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Multipart_Creation_Disposition;
      Failure     : Failure_Reason)
   is
      Value : constant Low_Level.Create_Multipart_Outcome :=
        (if Status = 200
         then (Kind => Low_Level.Created,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Create_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Create_Multipart_Result :=
        Normalize_Create_Multipart_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Create_Multipart_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "CreateMultipartUpload response normalization corpus mismatch";
      end if;
   end Check_Create_Multipart_Response;

   procedure Check_Create_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Multipart_Creation_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Creation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Created
         else Creation_Outcome_Unknown);
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large |
                 HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant Create_Multipart_Result :=
        Normalize_Create_Multipart_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Create_Multipart_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "CreateMultipartUpload exchange normalization corpus mismatch";
      end if;
   end Check_Create_Multipart_Failure;

   procedure Check_Create_Multipart_Certainty_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_Create_Multipart_Response
        (200, "", Multipart_Upload_Created, No_Failure);
      Check_Create_Multipart_Response
        (400, "InvalidRequest", Definitely_Not_Created, Invalid_Request);
      Check_Create_Multipart_Response
        (401, "InvalidAccessKeyId", Definitely_Not_Created,
         Authentication_Failed);
      Check_Create_Multipart_Response
        (403, "AccessDenied", Definitely_Not_Created,
         Authorization_Failed);
      Check_Create_Multipart_Response
        (404, "NoSuchBucket", Definitely_Not_Created, Not_Found);
      Check_Create_Multipart_Response
        (409, "OperationAborted", Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Multipart_Response
        (429, "SlowDown", Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Multipart_Response
        (500, "InternalError", Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Multipart_Response
        (502, "BadGateway", Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Multipart_Response
        (503, "SlowDown", Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Multipart_Response
        (504, "RequestTimeout", Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);

      Check_Create_Multipart_Response
        (400, "", Creation_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Create_Multipart_Response
        (403, "", Creation_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Create_Multipart_Response
        (404, "", Creation_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Create_Multipart_Response
        (500, "SlowDown", Creation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Create_Multipart_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Create_Multipart_Certainty_Corpus;

   procedure Check_Upload_Part_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Upload_Part_Outcome :=
        (if Status = 200
         then (Kind => Low_Level.Part_Uploaded,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Upload_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Upload_Part_Result := Normalize_Upload_Part_Response
        (Value, HTTP_Client.Response_Observed);
      Expected : constant Part_Upload_Disposition :=
        (if Status = 200 then Part_Published else Part_Outcome_Unknown);
   begin
      if Result.Kind /= Upload_Part_Response_Available
        or else Result.Disposition /= Expected
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "UploadPart response normalization corpus mismatch";
      end if;
   end Check_Upload_Part_Response;

   procedure Check_Upload_Part_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Part_Upload_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Part_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Staged
         else Part_Outcome_Unknown);
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large |
                 HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant Upload_Part_Result := Normalize_Upload_Part_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Upload_Part_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "UploadPart exchange normalization corpus mismatch";
      end if;
   end Check_Upload_Part_Failure;

   procedure Check_Upload_Part_Certainty_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_Upload_Part_Response (200, "", No_Failure);
      Check_Upload_Part_Response
        (400, "BadDigest", Invalid_Request);
      Check_Upload_Part_Response
        (400, "InvalidPart", Invalid_Request);
      Check_Upload_Part_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Upload_Part_Response
        (400, "EntityTooLarge", Invalid_Request);
      Check_Upload_Part_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Upload_Part_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Upload_Part_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Upload_Part_Response
        (404, "NoSuchUpload", Not_Found);
      Check_Upload_Part_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Upload_Part_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Upload_Part_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Upload_Part_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Upload_Part_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Upload_Part_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Upload_Part_Response
        (400, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Upload_Part_Outcome :=
              (Kind => Low_Level.Part_Uploaded,
               Status => 200,
               Result => (others => <>));
            Result : constant Upload_Part_Result :=
              Normalize_Upload_Part_Response (Value, Admission);
         begin
            if Result.Disposition /= Part_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent UploadPart response certainty was conclusive";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Upload_Part_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Upload_Part_Certainty_Corpus;

   procedure Check_Upload_Part_Copy_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Disposition : Publication_Disposition;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Upload_Part_Copy_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Part_Copied,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Copy_Part_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Upload_Part_Copy_Result :=
        Normalize_Upload_Part_Copy_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Upload_Part_Copy_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "UploadPartCopy response normalization corpus mismatch";
      end if;
   end Check_Upload_Part_Copy_Response;

   procedure Check_Upload_Part_Copy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Publication_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Publication
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Published
         else Outcome_Unknown);
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large |
                 HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant Upload_Part_Copy_Result :=
        Normalize_Upload_Part_Copy_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Upload_Part_Copy_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "UploadPartCopy exchange normalization corpus mismatch";
      end if;
   end Check_Upload_Part_Copy_Failure;

   procedure Check_Upload_Part_Copy_Certainty_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_Upload_Part_Copy_Response
        (200, "", Published, No_Failure);
      Check_Upload_Part_Copy_Response
        (400, "InvalidArgument", Definitely_Not_Published, Invalid_Request);
      Check_Upload_Part_Copy_Response
        (400, "InvalidPart", Definitely_Not_Published, Invalid_Request);
      Check_Upload_Part_Copy_Response
        (400, "InvalidRequest", Definitely_Not_Published, Invalid_Request);
      Check_Upload_Part_Copy_Response
        (401, "InvalidAccessKeyId", Definitely_Not_Published,
         Authentication_Failed);
      Check_Upload_Part_Copy_Response
        (403, "AccessDenied", Definitely_Not_Published,
         Authorization_Failed);
      Check_Upload_Part_Copy_Response
        (404, "NoSuchBucket", Definitely_Not_Published, Not_Found);
      Check_Upload_Part_Copy_Response
        (404, "NoSuchKey", Definitely_Not_Published, Not_Found);
      Check_Upload_Part_Copy_Response
        (404, "NoSuchUpload", Definitely_Not_Published, Not_Found);
      Check_Upload_Part_Copy_Response
        (409, "OperationAborted", Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Upload_Part_Copy_Response
        (412, "PreconditionFailed", Precondition_Failed, No_Failure);
      Check_Upload_Part_Copy_Response
        (429, "SlowDown", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Upload_Part_Copy_Response
        (500, "InternalError", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Upload_Part_Copy_Response
        (502, "BadGateway", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Upload_Part_Copy_Response
        (503, "SlowDown", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Upload_Part_Copy_Response
        (504, "RequestTimeout", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Upload_Part_Copy_Response
        (501, "NotImplemented", Definitely_Not_Published, Invalid_Request);
      Check_Upload_Part_Copy_Response
        (400, "", Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Upload_Part_Copy_Response
        (200, "InternalError", Outcome_Unknown, Unavailable_Or_Retryable);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Upload_Part_Copy_Outcome :=
              (Kind => Low_Level.Part_Copied,
               Status => 200,
               Result => (others => <>));
            Result : constant Upload_Part_Copy_Result :=
              Normalize_Upload_Part_Copy_Response (Value, Admission);
         begin
            if Result.Disposition /= Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent UploadPartCopy certainty was conclusive";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Upload_Part_Copy_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Upload_Part_Copy_Certainty_Corpus;

   procedure Check_Complete_Multipart_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Complete_Multipart_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Completed,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Complete_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Multipart_Completion_Result :=
        Normalize_Complete_Multipart_Response
          (Value, HTTP_Client.Response_Observed);
      Expected : constant Multipart_Completion_Disposition :=
        (if Value.Kind = Low_Level.Completed
         then Multipart_Completed else Completion_Outcome_Unknown);
   begin
      if Result.Kind /= Complete_Multipart_Response_Available
        or else Result.Disposition /= Expected
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "CompleteMultipartUpload response normalization mismatch";
      end if;
   end Check_Complete_Multipart_Response;

   procedure Check_Complete_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Multipart_Completion_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Completion_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Completed
         else Completion_Outcome_Unknown);
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large |
                 HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant Multipart_Completion_Result :=
        Normalize_Complete_Multipart_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Complete_Multipart_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "CompleteMultipartUpload failure normalization mismatch";
      end if;
   end Check_Complete_Multipart_Failure;

   procedure Check_Complete_Multipart_Certainty_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_Complete_Multipart_Response (200, "", No_Failure);
      Check_Complete_Multipart_Response
        (200, "InternalError", Unavailable_Or_Retryable);
      Check_Complete_Multipart_Response
        (400, "BadDigest", Invalid_Request);
      Check_Complete_Multipart_Response
        (400, "EntityTooSmall", Invalid_Request);
      Check_Complete_Multipart_Response
        (400, "InvalidPart", Invalid_Request);
      Check_Complete_Multipart_Response
        (400, "InvalidPartOrder", Invalid_Request);
      Check_Complete_Multipart_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Complete_Multipart_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Complete_Multipart_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Complete_Multipart_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Complete_Multipart_Response
        (404, "NoSuchKey", Not_Found);
      Check_Complete_Multipart_Response
        (404, "NoSuchUpload", Not_Found);
      Check_Complete_Multipart_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Complete_Multipart_Response
        (412, "PreconditionFailed", Invalid_Request);
      Check_Complete_Multipart_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Complete_Multipart_Response
        (400, "", Corrupt_Or_Invalid_Response);

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Complete_Multipart_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Complete_Multipart_Certainty_Corpus;

   procedure Check_Abort_Multipart_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Abort_Multipart_Outcome :=
        (if Status = 204 and then Code'Length = 0
         then (Kind => Low_Level.Aborted,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Abort_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Multipart_Abort_Result :=
        Normalize_Abort_Multipart_Response
          (Value, HTTP_Client.Response_Observed);
      Expected : constant Multipart_Abort_Disposition :=
        (if Value.Kind = Low_Level.Aborted
         then Multipart_Aborted else Abort_Outcome_Unknown);
   begin
      if Result.Kind /= Abort_Multipart_Response_Available
        or else Result.Disposition /= Expected
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "AbortMultipartUpload response normalization mismatch";
      end if;
   end Check_Abort_Multipart_Response;

   procedure Check_Abort_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Multipart_Abort_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Abort_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Aborted
         else Abort_Outcome_Unknown);
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large |
                 HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant Multipart_Abort_Result :=
        Normalize_Abort_Multipart_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Abort_Multipart_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "AbortMultipartUpload failure normalization mismatch";
      end if;
   end Check_Abort_Multipart_Failure;

   procedure Check_Abort_Multipart_Certainty_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_Abort_Multipart_Response (204, "", No_Failure);
      Check_Abort_Multipart_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Abort_Multipart_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Abort_Multipart_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Abort_Multipart_Response (404, "NoSuchBucket", Not_Found);
      Check_Abort_Multipart_Response (404, "NoSuchKey", Not_Found);
      Check_Abort_Multipart_Response (404, "NoSuchUpload", Not_Found);
      Check_Abort_Multipart_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Abort_Multipart_Response
        (412, "PreconditionFailed", Invalid_Request);
      Check_Abort_Multipart_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Abort_Multipart_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Abort_Multipart_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Abort_Multipart_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Abort_Multipart_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Abort_Multipart_Response
        (400, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Abort_Multipart_Outcome :=
              (Kind => Low_Level.Aborted,
               Status => 204,
               Result => (others => <>));
            Result : constant Multipart_Abort_Result :=
              Normalize_Abort_Multipart_Response (Value, Admission);
         begin
            if Result.Disposition /= Abort_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent AbortMultipartUpload response was conclusive";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Abort_Multipart_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Abort_Multipart_Certainty_Corpus;

   procedure Check_List_Parts_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.List_Parts_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Parts_Listed,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.List_Parts_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant List_Parts_Result := Normalize_List_Parts_Response
        (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= List_Parts_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "ListParts response normalization mismatch: status=" &
           Status'Image & " code=" & Code & " expected=" &
           Failure'Image & " actual=" & Result.Failure'Image;
      end if;
   end Check_List_Parts_Response;

   procedure Check_List_Parts_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
            when HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant List_Parts_Result := Normalize_List_Parts_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= List_Parts_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "ListParts exchange normalization mismatch";
      end if;
   end Check_List_Parts_Failure;

   procedure Check_List_Parts_Result_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_List_Parts_Response (200, "", No_Failure);
      Check_List_Parts_Response (400, "InvalidArgument", Invalid_Request);
      Check_List_Parts_Response (400, "InvalidRequest", Invalid_Request);
      Check_List_Parts_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_List_Parts_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_List_Parts_Response (404, "NoSuchBucket", Not_Found);
      Check_List_Parts_Response (404, "NoSuchKey", Not_Found);
      Check_List_Parts_Response (404, "NoSuchUpload", Not_Found);
      Check_List_Parts_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_List_Parts_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Parts_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_List_Parts_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_List_Parts_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Parts_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_List_Parts_Response (501, "NotImplemented", Invalid_Request);
      Check_List_Parts_Response
        (400, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.List_Parts_Outcome :=
              (Kind => Low_Level.Parts_Listed,
               Status => 200,
               Result => (others => <>));
            Result : constant List_Parts_Result :=
              Normalize_List_Parts_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent ListParts response certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_List_Parts_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_List_Parts_Result_Corpus;

   procedure Check_List_Multipart_Uploads_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.List_Multipart_Uploads_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Multipart_Uploads_Listed,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.List_Multipart_Uploads_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant List_Multipart_Uploads_Result :=
        Normalize_List_Multipart_Uploads_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Multipart_Uploads_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "ListMultipartUploads response normalization mismatch: status=" &
           Status'Image & " code=" & Code & " expected=" &
           Failure'Image & " actual=" & Result.Failure'Image;
      end if;
   end Check_List_Multipart_Uploads_Response;

   procedure Check_List_Multipart_Uploads_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
            when HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant List_Multipart_Uploads_Result :=
        Normalize_List_Multipart_Uploads_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= List_Multipart_Uploads_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "ListMultipartUploads exchange normalization mismatch";
      end if;
   end Check_List_Multipart_Uploads_Failure;

   procedure Check_List_Multipart_Uploads_Result_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_List_Multipart_Uploads_Response (200, "", No_Failure);
      Check_List_Multipart_Uploads_Response
        (400, "InvalidArgument", Invalid_Request);
      Check_List_Multipart_Uploads_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_List_Multipart_Uploads_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_List_Multipart_Uploads_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_List_Multipart_Uploads_Response
        (404, "NoSuchBucket", Not_Found);
      Check_List_Multipart_Uploads_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_List_Multipart_Uploads_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Multipart_Uploads_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_List_Multipart_Uploads_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_List_Multipart_Uploads_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Multipart_Uploads_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_List_Multipart_Uploads_Response
        (501, "NotImplemented", Invalid_Request);
      Check_List_Multipart_Uploads_Response
        (400, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.List_Multipart_Uploads_Outcome :=
              (Kind => Low_Level.Multipart_Uploads_Listed,
               Status => 200,
               Result => (others => <>));
            Result : constant List_Multipart_Uploads_Result :=
              Normalize_List_Multipart_Uploads_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent ListMultipartUploads certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_List_Multipart_Uploads_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_List_Multipart_Uploads_Result_Corpus;

   procedure Check_Copy_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Publication_Disposition;
      Failure     : Failure_Reason)
   is
      Value : constant Low_Level.Copy_Object_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Object_Copied,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Copy_Object_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Copy_Result := Normalize_Copy_Response
        (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Copy_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "CopyObject response normalization mismatch: status=" &
           Status'Image & " code=" & Code;
      end if;
   end Check_Copy_Response;

   procedure Check_Copy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Publication_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Publication
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Published
         else Outcome_Unknown);
      Expected_Failure : constant Failure_Reason :=
        (case Kind is
            when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
            when HTTP_Client.Cancelled => Cancelled,
            when HTTP_Client.Timed_Out => Timed_Out,
            when HTTP_Client.Client_Unavailable => Client_Unavailable,
            when HTTP_Client.Connection_Failed => Connection_Failed,
            when HTTP_Client.Transport_Failed => Transport_Failed,
            when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
            when HTTP_Client.Response_Body_Too_Large =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");
      Result : constant Copy_Result := Normalize_Copy_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Copy_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with "CopyObject exchange normalization mismatch";
      end if;
   end Check_Copy_Failure;

   procedure Check_Copy_Result_Corpus is
      type Failure_Kind_Array is array (Positive range <>) of
        HTTP_Client.Exchange_Result_Kind;
      Failure_Kinds : constant Failure_Kind_Array :=
        (HTTP_Client.Pre_Admission_Rejected,
         HTTP_Client.Cancelled,
         HTTP_Client.Timed_Out,
         HTTP_Client.Client_Unavailable,
         HTTP_Client.Connection_Failed,
         HTTP_Client.Transport_Failed,
         HTTP_Client.Request_Source_Failed,
         HTTP_Client.Response_Invalid,
         HTTP_Client.Response_Body_Too_Large,
         HTTP_Client.Response_Sink_Failed);
   begin
      Check_Copy_Response (200, "", Published, No_Failure);
      Check_Copy_Response
        (412, "PreconditionFailed", Precondition_Failed, No_Failure);
      Check_Copy_Response
        (400, "InvalidArgument", Definitely_Not_Published, Invalid_Request);
      Check_Copy_Response
        (400, "InvalidRequest", Definitely_Not_Published, Invalid_Request);
      Check_Copy_Response
        (401, "InvalidAccessKeyId", Definitely_Not_Published,
         Authentication_Failed);
      Check_Copy_Response
        (403, "AccessDenied", Definitely_Not_Published,
         Authorization_Failed);
      Check_Copy_Response
        (404, "NoSuchBucket", Definitely_Not_Published, Not_Found);
      Check_Copy_Response
        (404, "NoSuchKey", Definitely_Not_Published, Not_Found);
      Check_Copy_Response
        (501, "NotImplemented", Definitely_Not_Published, Invalid_Request);
      Check_Copy_Response
        (409, "OperationAborted", Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Copy_Response
        (429, "SlowDown", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Copy_Response
        (500, "InternalError", Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Copy_Response
        (200, "InternalError", Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Copy_Response
        (502, "BadGateway", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Copy_Response
        (503, "SlowDown", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Copy_Response
        (504, "RequestTimeout", Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Copy_Response
        (412, "AccessDenied", Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Copy_Object_Outcome :=
              (Kind => Low_Level.Object_Copied,
               Status => 200,
               Result => (others => <>));
            Result : constant Copy_Result :=
              Normalize_Copy_Response (Value, Admission);
         begin
            if Result.Disposition /= Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent CopyObject certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Copy_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Copy_Result_Corpus;

end Flyology.Object_Storage.Client.Transfers.Testing;
