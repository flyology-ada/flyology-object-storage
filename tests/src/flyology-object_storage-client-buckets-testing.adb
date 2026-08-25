with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Errors;

package body Flyology.Object_Storage.Client.Buckets.Testing is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;

   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Put_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Get_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Tagging_Outcome_Kind;

   procedure Check_List_Buckets_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.List_Buckets_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Buckets_Listed,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.List_Buckets_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant List_Buckets_Result :=
        Normalize_List_Buckets_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= List_Buckets_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "ListBuckets response normalization mismatch: status=" &
           Status'Image & " code=" & Code & " expected=" &
           Failure'Image & " actual=" & Result.Failure'Image;
      end if;
   end Check_List_Buckets_Response;

   procedure Check_List_Buckets_Failure
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
      Result : constant List_Buckets_Result := Normalize_List_Buckets_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= List_Buckets_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "ListBuckets exchange normalization mismatch";
      end if;
   end Check_List_Buckets_Failure;

   procedure Check_List_Buckets_Result_Corpus is
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
      Check_List_Buckets_Response (200, "", No_Failure);
      Check_List_Buckets_Response
        (400, "InvalidArgument", Invalid_Request);
      Check_List_Buckets_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_List_Buckets_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_List_Buckets_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_List_Buckets_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_List_Buckets_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Buckets_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_List_Buckets_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_List_Buckets_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Buckets_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_List_Buckets_Response (501, "NotImplemented", Invalid_Request);
      Check_List_Buckets_Response (400, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.List_Buckets_Outcome :=
              (Kind => Low_Level.Buckets_Listed,
               Status => 200,
               Result => (others => <>));
            Result : constant List_Buckets_Result :=
              Normalize_List_Buckets_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent ListBuckets certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_List_Buckets_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_List_Buckets_Result_Corpus;

   procedure Check_Create_Bucket_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Bucket_Creation_Disposition;
      Failure     : Failure_Reason)
   is
      Value : constant Low_Level.Create_Bucket_Outcome :=
        (if Status = 200
         then (Kind => Low_Level.Bucket_Created,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Create_Bucket_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Create_Bucket_Result :=
        Normalize_Create_Bucket_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Create_Bucket_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "CreateBucket response normalization corpus mismatch";
      end if;
   end Check_Create_Bucket_Response;

   procedure Check_Create_Bucket_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Bucket_Creation_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Creation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Definitely_Not_Created
         else Bucket_Creation_Outcome_Unknown);
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
      Result : constant Create_Bucket_Result :=
        Normalize_Create_Bucket_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Create_Bucket_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "CreateBucket exchange normalization corpus mismatch";
      end if;
   end Check_Create_Bucket_Failure;

   procedure Check_Create_Bucket_Certainty_Corpus is
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
      Check_Create_Bucket_Response
        (200, "", Bucket_Creation_Completed, No_Failure);
      Check_Create_Bucket_Response
        (400, "InvalidBucketName", Bucket_Definitely_Not_Created,
         Invalid_Request);
      Check_Create_Bucket_Response
        (400, "IllegalLocationConstraintException",
         Bucket_Definitely_Not_Created, Invalid_Request);
      Check_Create_Bucket_Response
        (401, "InvalidAccessKeyId", Bucket_Definitely_Not_Created,
         Authentication_Failed);
      Check_Create_Bucket_Response
        (403, "AccessDenied", Bucket_Definitely_Not_Created,
         Authorization_Failed);
      Check_Create_Bucket_Response
        (409, "BucketAlreadyExists", Bucket_Definitely_Not_Created,
         Invalid_Request);
      Check_Create_Bucket_Response
        (409, "BucketAlreadyOwnedByYou", Bucket_Definitely_Not_Created,
         Invalid_Request);
      Check_Create_Bucket_Response
        (409, "TooManyBuckets", Bucket_Definitely_Not_Created,
         Invalid_Request);
      Check_Create_Bucket_Response
        (501, "NotImplemented", Bucket_Definitely_Not_Created,
         Invalid_Request);
      Check_Create_Bucket_Response
        (409, "OperationAborted", Bucket_Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Bucket_Response
        (429, "SlowDown", Bucket_Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Bucket_Response
        (500, "InternalError", Bucket_Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Bucket_Response
        (502, "BadGateway", Bucket_Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Bucket_Response
        (503, "SlowDown", Bucket_Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Bucket_Response
        (504, "RequestTimeout", Bucket_Creation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Bucket_Response
        (409, "", Bucket_Creation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);
      Check_Create_Bucket_Response
        (500, "SlowDown", Bucket_Creation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Create_Bucket_Outcome :=
              (Kind => Low_Level.Bucket_Created,
               Status => 200,
               Result => (others => <>));
            Result : constant Create_Bucket_Result :=
              Normalize_Create_Bucket_Response (Value, Admission);
         begin
            if Result.Disposition /= Bucket_Creation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent CreateBucket certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Create_Bucket_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Create_Bucket_Certainty_Corpus;

   procedure Check_Delete_Bucket_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Bucket_Deletion_Disposition;
      Failure     : Failure_Reason)
   is
      Value  : constant Low_Level.Delete_Bucket_Outcome :=
        (if Status = 204
         then (Kind => Low_Level.Bucket_Deleted, Status => Status)
         else
           (Kind   => Low_Level.Delete_Bucket_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Delete_Bucket_Result :=
        Normalize_Delete_Bucket_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Delete_Bucket_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error
           with "DeleteBucket response normalization corpus mismatch";
      end if;
   end Check_Delete_Bucket_Response;

   procedure Check_Delete_Bucket_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Bucket_Deletion_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Deletion_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Definitely_Not_Deleted
         else Bucket_Deletion_Outcome_Unknown);
      Expected_Failure     : constant Failure_Reason :=
        (case Kind is
           when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
           when HTTP_Client.Cancelled              => Cancelled,
           when HTTP_Client.Timed_Out              => Timed_Out,
           when HTTP_Client.Client_Unavailable     => Client_Unavailable,
           when HTTP_Client.Connection_Failed      => Connection_Failed,
           when HTTP_Client.Transport_Failed       => Transport_Failed,
           when HTTP_Client.Request_Source_Failed  => Request_Source_Failed,
           when HTTP_Client.Response_Body_Too_Large
              | HTTP_Client.Response_Invalid
              | HTTP_Client.Response_Sink_Failed   =>
             Corrupt_Or_Invalid_Response,
           when HTTP_Client.Response_Complete      =>
             raise Program_Error with "complete response is not a failure");
      Result               : constant Delete_Bucket_Result :=
        Normalize_Delete_Bucket_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Delete_Bucket_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error
           with "DeleteBucket exchange normalization corpus mismatch";
      end if;
   end Check_Delete_Bucket_Failure;

   procedure Check_Delete_Bucket_Certainty_Corpus is
      type Failure_Kind_Array is
        array (Positive range <>) of HTTP_Client.Exchange_Result_Kind;
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
      Check_Delete_Bucket_Response
        (204, "", Bucket_Deletion_Completed, No_Failure);
      Check_Delete_Bucket_Response
        (400,
         "InvalidBucketName",
         Bucket_Definitely_Not_Deleted,
         Invalid_Request);
      Check_Delete_Bucket_Response
        (401,
         "InvalidAccessKeyId",
         Bucket_Definitely_Not_Deleted,
         Authentication_Failed);
      Check_Delete_Bucket_Response
        (403,
         "AccessDenied",
         Bucket_Definitely_Not_Deleted,
         Authorization_Failed);
      Check_Delete_Bucket_Response
        (404, "NoSuchBucket", Bucket_Definitely_Not_Deleted, Not_Found);
      Check_Delete_Bucket_Response
        (409,
         "BucketNotEmpty",
         Bucket_Definitely_Not_Deleted,
         Invalid_Request);
      Check_Delete_Bucket_Response
        (501,
         "NotImplemented",
         Bucket_Definitely_Not_Deleted,
         Invalid_Request);
      Check_Delete_Bucket_Response
        (409,
         "OperationAborted",
         Bucket_Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Bucket_Response
        (429,
         "SlowDown",
         Bucket_Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Bucket_Response
        (500,
         "InternalError",
         Bucket_Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Bucket_Response
        (409,
         "",
         Bucket_Deletion_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value  : constant Low_Level.Delete_Bucket_Outcome :=
              (Kind => Low_Level.Bucket_Deleted, Status => 204);
            Result : constant Delete_Bucket_Result :=
              Normalize_Delete_Bucket_Response (Value, Admission);
         begin
            if Result.Disposition /= Bucket_Deletion_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error
                 with "inconsistent DeleteBucket certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Delete_Bucket_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Delete_Bucket_Certainty_Corpus;

   procedure Check_Head_Bucket_Response
     (Status  : Flyology.HTTP.Status_Code;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Head_Bucket_Outcome :=
        (if Status = 200
         then (Kind => Low_Level.Bucket_Found,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Head_Bucket_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String ("HTTP"),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Head_Bucket_Result :=
        Normalize_Head_Bucket_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Head_Bucket_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "HeadBucket response normalization mismatch: status=" &
           Status'Image & " expected=" & Failure'Image & " actual=" &
           Result.Failure'Image;
      end if;
   end Check_Head_Bucket_Response;

   procedure Check_Head_Bucket_Failure
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
      Result : constant Head_Bucket_Result := Normalize_Head_Bucket_Failure
        (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Head_Bucket_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "HeadBucket exchange normalization mismatch";
      end if;
   end Check_Head_Bucket_Failure;

   procedure Check_Head_Bucket_Result_Corpus is
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
      Check_Head_Bucket_Response (200, No_Failure);
      Check_Head_Bucket_Response (301, Invalid_Request);
      Check_Head_Bucket_Response (307, Invalid_Request);
      Check_Head_Bucket_Response (400, Invalid_Request);
      Check_Head_Bucket_Response (501, Invalid_Request);
      Check_Head_Bucket_Response (401, Authentication_Failed);
      Check_Head_Bucket_Response (403, Authorization_Failed);
      Check_Head_Bucket_Response (404, Not_Found);
      Check_Head_Bucket_Response (409, Unavailable_Or_Retryable);
      Check_Head_Bucket_Response (429, Unavailable_Or_Retryable);
      Check_Head_Bucket_Response (500, Unavailable_Or_Retryable);
      Check_Head_Bucket_Response (502, Unavailable_Or_Retryable);
      Check_Head_Bucket_Response (503, Unavailable_Or_Retryable);
      Check_Head_Bucket_Response (504, Unavailable_Or_Retryable);
      Check_Head_Bucket_Response (418, Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Head_Bucket_Outcome :=
              (Kind => Low_Level.Bucket_Found,
               Status => 200,
               Result => (others => <>));
            Result : constant Head_Bucket_Result :=
              Normalize_Head_Bucket_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent HeadBucket certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Head_Bucket_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Head_Bucket_Result_Corpus;

   procedure Check_Bucket_Tagging_Certainty_Corpus is
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

      function Error_Response (Code : String) return S3.Errors.Error_Response
      is
        ((Code       => US.To_Unbounded_String (Code),
          Message    => US.Null_Unbounded_String,
          Resource   => US.Null_Unbounded_String,
          Request_ID => US.Null_Unbounded_String,
          Host_ID    => US.Null_Unbounded_String));

      function Expected_Failure
        (Kind : HTTP_Client.Exchange_Result_Kind) return Failure_Reason is
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

      function Expected_Disposition
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
         return Bucket_Tag_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Tag_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Tag_Mutation_Definitely_Not_Applied
         else Bucket_Tag_Mutation_Outcome_Unknown);

      procedure Check_Put_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Tag_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Tagging_Outcome :=
           (if Status = 200
            then (Kind   => Low_Level.Bucket_Tags_Replaced,
                  Status => Status,
                  Result => (others => <>))
            else (Kind   => Low_Level.Put_Bucket_Tagging_Rejected,
                  Status => Status,
                  Error  => Error_Response (Code)));
         Result : constant Put_Bucket_Tagging_Result :=
           Normalize_Put_Bucket_Tagging_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Bucket_Tagging_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketTagging response normalization mismatch";
         end if;
      end Check_Put_Response;

      procedure Check_Get_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Get_Bucket_Tagging_Outcome :=
           (if Status = 200
            then (Kind   => Low_Level.Bucket_Tags_Found,
                  Status => Status,
                  Result => (others => <>))
            else (Kind   => Low_Level.Get_Bucket_Tagging_Rejected,
                  Status => Status,
                  Error  => Error_Response (Code)));
         Result : constant Get_Bucket_Tagging_Result :=
           Normalize_Get_Bucket_Tagging_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Bucket_Tagging_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketTagging response normalization mismatch";
         end if;
      end Check_Get_Response;

      procedure Check_Delete_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Tag_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Tagging_Outcome :=
           (if Status = 204
            then (Kind   => Low_Level.Bucket_Tags_Deleted,
                  Status => Status)
            else (Kind   => Low_Level.Delete_Bucket_Tagging_Rejected,
                  Status => Status,
                  Error  => Error_Response (Code)));
         Result : constant Delete_Bucket_Tagging_Result :=
           Normalize_Delete_Bucket_Tagging_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_Tagging_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketTagging response normalization mismatch";
         end if;
      end Check_Delete_Response;

      procedure Check_Failure
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
      is
         Put_Result : constant Put_Bucket_Tagging_Result :=
           Normalize_Put_Bucket_Tagging_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
         Get_Result : constant Get_Bucket_Tagging_Result :=
           Normalize_Get_Bucket_Tagging_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
         Delete_Result : constant Delete_Bucket_Tagging_Result :=
           Normalize_Delete_Bucket_Tagging_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
      begin
         if Put_Result.Kind /= Put_Bucket_Tagging_Exchange_Failed
           or else Put_Result.Disposition /=
             Expected_Disposition (Kind, Admission)
           or else Put_Result.Failure /= Expected_Failure (Kind)
           or else Put_Result.Admission /= Admission
           or else Put_Result.HTTP_Result /= Kind
           or else Get_Result.Kind /= Get_Bucket_Tagging_Exchange_Failed
           or else Get_Result.Failure /= Expected_Failure (Kind)
           or else Get_Result.Admission /= Admission
           or else Get_Result.HTTP_Result /= Kind
           or else Delete_Result.Kind /=
             Delete_Bucket_Tagging_Exchange_Failed
           or else Delete_Result.Disposition /=
             Expected_Disposition (Kind, Admission)
           or else Delete_Result.Failure /= Expected_Failure (Kind)
           or else Delete_Result.Admission /= Admission
           or else Delete_Result.HTTP_Result /= Kind
         then
            raise Program_Error with
              "bucket-tagging exchange normalization mismatch";
         end if;
      end Check_Failure;
   begin
      Check_Put_Response
        (200, "", Bucket_Tag_Mutation_Completed, No_Failure);
      Check_Put_Response
        (400, "InvalidTag", Bucket_Tag_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put_Response
        (409, "OperationAborted", Bucket_Tag_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (500, "SlowDown", Bucket_Tag_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      Check_Get_Response (200, "", No_Failure);
      Check_Get_Response (403, "AccessDenied", Authorization_Failed);
      Check_Get_Response (404, "NoSuchTagSet", Not_Found);

      Check_Delete_Response
        (204, "", Bucket_Tag_Mutation_Completed, No_Failure);
      Check_Delete_Response
        (404, "NoSuchBucket", Bucket_Tag_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Delete_Response
        (500, "InternalError", Bucket_Tag_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (403, "", Bucket_Tag_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Put_Value : constant Low_Level.Put_Bucket_Tagging_Outcome :=
              (Kind   => Low_Level.Bucket_Tags_Replaced,
               Status => 200,
               Result => (others => <>));
            Get_Value : constant Low_Level.Get_Bucket_Tagging_Outcome :=
              (Kind   => Low_Level.Bucket_Tags_Found,
               Status => 200,
               Result => (others => <>));
            Delete_Value : constant Low_Level.Delete_Bucket_Tagging_Outcome :=
              (Kind   => Low_Level.Bucket_Tags_Deleted,
               Status => 204);
            Put_Result : constant Put_Bucket_Tagging_Result :=
              Normalize_Put_Bucket_Tagging_Response (Put_Value, Admission);
            Get_Result : constant Get_Bucket_Tagging_Result :=
              Normalize_Get_Bucket_Tagging_Response (Get_Value, Admission);
            Delete_Result : constant Delete_Bucket_Tagging_Result :=
              Normalize_Delete_Bucket_Tagging_Response
                (Delete_Value, Admission);
         begin
            if Put_Result.Disposition /= Bucket_Tag_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Get_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Delete_Result.Disposition /=
                Bucket_Tag_Mutation_Outcome_Unknown
              or else Delete_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent bucket-tagging certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Bucket_Tagging_Certainty_Corpus;

end Flyology.Object_Storage.Client.Buckets.Testing;
