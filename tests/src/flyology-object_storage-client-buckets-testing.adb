with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Lifecycle;

package body Flyology.Object_Storage.Client.Buckets.Testing is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Bucket_Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;

   --  Test-only readable aliases for the exact public result identities.
   --  They do not select production state encodings or policy values.
   Metadata_Create_Response : constant
     Create_Bucket_Metadata_Table_Configuration_Result_Kind :=
       Create_Bucket_Metadata_Table_Configuration_Response_Available;
   Metadata_Create_Exchange_Failed : constant
     Create_Bucket_Metadata_Table_Configuration_Result_Kind :=
       Create_Bucket_Metadata_Table_Configuration_Exchange_Failed;

   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;
   use type Low_Level.Get_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Put_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Put_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Get_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Get_Object_Lock_Configuration_Outcome_Kind;
   use type Low_Level.Put_Object_Lock_Configuration_Outcome_Kind;

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

   procedure Check_Get_Bucket_Location_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value  : constant Low_Level.Get_Bucket_Location_Outcome :=
        (if Status = 200
         then
           (Kind   => Low_Level.Bucket_Location_Found,
            Status => Status,
            Result =>
              (Location_Constraint => US.To_Unbounded_String ("us-west-2")))
         else
           (Kind   => Low_Level.Get_Bucket_Location_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_Location_Result :=
        Normalize_Get_Bucket_Location_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_Location_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketLocation response normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Location_Response;

   procedure Check_Get_Bucket_Location_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_Location_Result :=
        Normalize_Get_Bucket_Location_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_Location_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketLocation exchange normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Location_Failure;

   procedure Check_Get_Bucket_Location_Result_Corpus is
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
      Check_Get_Bucket_Location_Response (200, "", No_Failure);
      Check_Get_Bucket_Location_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_Location_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_Location_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_Location_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_Location_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_Location_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_Location_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Location_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_Location_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_Location_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Location_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_Location_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_Location_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value  : constant Low_Level.Get_Bucket_Location_Outcome :=
              (Kind   => Low_Level.Bucket_Location_Found,
               Status => 200,
               Result =>
                 (Location_Constraint => US.To_Unbounded_String ("EU")));
            Result : constant Get_Bucket_Location_Result :=
              Normalize_Get_Bucket_Location_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketLocation certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_Location_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_Location_Result_Corpus;

   procedure Check_Get_Bucket_Policy_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Get_Bucket_Policy_Outcome :=
        (if Status = 200
         then
           (Kind   => Low_Level.Bucket_Control_Found,
            Status => Status,
            Policy => US.To_Unbounded_String ("{""Statement"":[]}"))
         else
           (Kind   => Low_Level.Get_Bucket_Control_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_Policy_Result :=
        Normalize_Get_Bucket_Policy_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_Policy_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketPolicy response normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Policy_Response;

   procedure Check_Get_Bucket_Policy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_Policy_Result :=
        Normalize_Get_Bucket_Policy_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_Policy_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketPolicy exchange normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Policy_Failure;

   procedure Check_Get_Bucket_Policy_Result_Corpus is
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
      Check_Get_Bucket_Policy_Response (200, "", No_Failure);
      Check_Get_Bucket_Policy_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_Policy_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_Policy_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_Policy_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_Policy_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_Policy_Response
        (404, "NoSuchBucketPolicy", Not_Found);
      Check_Get_Bucket_Policy_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_Policy_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_Policy_Outcome :=
              (Kind   => Low_Level.Bucket_Control_Found,
               Status => 200,
               Policy => US.To_Unbounded_String ("{}"));
            Result : constant Get_Bucket_Policy_Result :=
              Normalize_Get_Bucket_Policy_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketPolicy certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_Policy_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_Policy_Result_Corpus;

   procedure Check_Get_Bucket_Policy_Status_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Get_Bucket_Policy_Status_Outcome :=
        (if Status = 200
         then
           (Kind      => Low_Level.Bucket_Control_Found,
            Status    => Status,
            Is_Public => (Is_Set => True, Value => False))
         else
           (Kind   => Low_Level.Get_Bucket_Control_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_Policy_Status_Result :=
        Normalize_Get_Bucket_Policy_Status_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_Policy_Status_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketPolicyStatus response normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Policy_Status_Response;

   procedure Check_Get_Bucket_Policy_Status_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_Policy_Status_Result :=
        Normalize_Get_Bucket_Policy_Status_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_Policy_Status_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketPolicyStatus exchange normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Policy_Status_Failure;

   procedure Check_Get_Bucket_Policy_Status_Result_Corpus is
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
      Check_Get_Bucket_Policy_Status_Response (200, "", No_Failure);
      Check_Get_Bucket_Policy_Status_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_Policy_Status_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_Policy_Status_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_Policy_Status_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_Policy_Status_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_Policy_Status_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Status_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Status_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Status_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Status_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Status_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_Policy_Status_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_Policy_Status_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_Policy_Status_Outcome :=
              (Kind      => Low_Level.Bucket_Control_Found,
               Status    => 200,
               Is_Public => (Is_Set => True, Value => False));
            Result : constant Get_Bucket_Policy_Status_Result :=
              Normalize_Get_Bucket_Policy_Status_Response
                (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketPolicyStatus certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_Policy_Status_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_Policy_Status_Result_Corpus;

   procedure Check_Get_Bucket_Accelerate_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
        (if Status = 200
         then
           (Kind            => Low_Level.Bucket_Control_Found,
            Status          => Status,
            Configuration   => Bucket_Controls.Accelerate_Enabled,
            Request_Charged => US.To_Unbounded_String ("requester"))
         else
           (Kind   => Low_Level.Get_Bucket_Control_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_Accelerate_Configuration_Result :=
        Normalize_Get_Bucket_Accelerate_Configuration_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_Accelerate_Configuration_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketAccelerateConfiguration response normalization " &
           "corpus mismatch";
      end if;
   end Check_Get_Bucket_Accelerate_Response;

   procedure Check_Get_Bucket_Accelerate_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_Accelerate_Configuration_Result :=
        Normalize_Get_Bucket_Accelerate_Configuration_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_Accelerate_Configuration_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketAccelerateConfiguration exchange normalization " &
           "corpus mismatch";
      end if;
   end Check_Get_Bucket_Accelerate_Failure;

   procedure Check_Get_Bucket_Accelerate_Configuration_Result_Corpus is
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
      Check_Get_Bucket_Accelerate_Response (200, "", No_Failure);
      Check_Get_Bucket_Accelerate_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_Accelerate_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_Accelerate_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_Accelerate_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_Accelerate_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_Accelerate_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_Accelerate_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Accelerate_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_Accelerate_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_Accelerate_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Accelerate_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_Accelerate_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_Accelerate_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
              (Kind            => Low_Level.Bucket_Control_Found,
               Status          => 200,
               Configuration   => Bucket_Controls.Accelerate_Enabled,
               Request_Charged => US.To_Unbounded_String ("requester"));
            Result : constant Get_Bucket_Accelerate_Configuration_Result :=
              Normalize_Get_Bucket_Accelerate_Configuration_Response
                (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketAccelerateConfiguration certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_Accelerate_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_Accelerate_Configuration_Result_Corpus;

   procedure Check_Get_Bucket_ABAC_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Get_Bucket_Abac_Outcome :=
        (if Status = 200
         then
           (Kind          => Low_Level.Bucket_Control_Found,
            Status        => Status,
            Configuration => Bucket_Controls.Abac_Enabled)
         else
           (Kind   => Low_Level.Get_Bucket_Control_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_ABAC_Result :=
        Normalize_Get_Bucket_ABAC_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_ABAC_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketAbac response normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_ABAC_Response;

   procedure Check_Get_Bucket_ABAC_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_ABAC_Result :=
        Normalize_Get_Bucket_ABAC_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_ABAC_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketAbac exchange normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_ABAC_Failure;

   procedure Check_Get_Bucket_ABAC_Result_Corpus is
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
      Check_Get_Bucket_ABAC_Response (200, "", No_Failure);
      Check_Get_Bucket_ABAC_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_ABAC_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_ABAC_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_ABAC_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_ABAC_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_ABAC_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_ABAC_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_ABAC_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_ABAC_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_ABAC_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_ABAC_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_ABAC_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_ABAC_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_Abac_Outcome :=
              (Kind          => Low_Level.Bucket_Control_Found,
               Status        => 200,
               Configuration => Bucket_Controls.Abac_Enabled);
            Result : constant Get_Bucket_ABAC_Result :=
              Normalize_Get_Bucket_ABAC_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketAbac certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_ABAC_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_ABAC_Result_Corpus;

   procedure Check_Get_Bucket_Request_Payment_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.Get_Bucket_Request_Payment_Outcome :=
        (if Status = 200
         then
           (Kind    => Low_Level.Bucket_Control_Found,
            Status  => Status,
            Payment => Bucket_Controls.Requester)
         else
           (Kind   => Low_Level.Get_Bucket_Control_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_Request_Payment_Result :=
        Normalize_Get_Bucket_Request_Payment_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_Request_Payment_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketRequestPayment response normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Request_Payment_Response;

   procedure Check_Get_Bucket_Request_Payment_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_Request_Payment_Result :=
        Normalize_Get_Bucket_Request_Payment_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_Request_Payment_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketRequestPayment exchange normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Request_Payment_Failure;

   procedure Check_Get_Bucket_Request_Payment_Result_Corpus is
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
      Check_Get_Bucket_Request_Payment_Response (200, "", No_Failure);
      Check_Get_Bucket_Request_Payment_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_Request_Payment_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_Request_Payment_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_Request_Payment_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_Request_Payment_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_Request_Payment_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_Request_Payment_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Request_Payment_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_Request_Payment_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_Request_Payment_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Request_Payment_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_Request_Payment_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_Request_Payment_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_Request_Payment_Outcome :=
              (Kind    => Low_Level.Bucket_Control_Found,
               Status  => 200,
               Payment => Bucket_Controls.Requester);
            Result : constant Get_Bucket_Request_Payment_Result :=
              Normalize_Get_Bucket_Request_Payment_Response
                (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketRequestPayment certainty was " &
                 "accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_Request_Payment_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_Request_Payment_Result_Corpus;

   procedure Check_Get_Bucket_Versioning_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value  : constant Low_Level.Get_Bucket_Versioning_Outcome :=
        (if Status = 200
         then
           (Kind          => Low_Level.Bucket_Versioning_Found,
            Status        => Status,
            Configuration => (others => <>))
         else
           (Kind   => Low_Level.Get_Bucket_Versioning_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Get_Bucket_Versioning_Result :=
        Normalize_Get_Bucket_Versioning_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Get_Bucket_Versioning_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "GetBucketVersioning response normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Versioning_Response;

   procedure Check_Get_Bucket_Versioning_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Failure : constant Failure_Reason :=
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
      Result : constant Get_Bucket_Versioning_Result :=
        Normalize_Get_Bucket_Versioning_Failure
          (Kind, Admission, HTTP_Client.Waiting_Response_Head);
   begin
      if Result.Kind /= Get_Bucket_Versioning_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "GetBucketVersioning exchange normalization corpus mismatch";
      end if;
   end Check_Get_Bucket_Versioning_Failure;

   procedure Check_Get_Bucket_Versioning_Result_Corpus is
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
      Check_Get_Bucket_Versioning_Response (200, "", No_Failure);
      Check_Get_Bucket_Versioning_Response
        (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Bucket_Versioning_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_Get_Bucket_Versioning_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Bucket_Versioning_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_Get_Bucket_Versioning_Response
        (404, "NoSuchBucket", Not_Found);
      Check_Get_Bucket_Versioning_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Bucket_Versioning_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Versioning_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Bucket_Versioning_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Bucket_Versioning_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Bucket_Versioning_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Bucket_Versioning_Response
        (501, "NotImplemented", Invalid_Request);
      Check_Get_Bucket_Versioning_Response
        (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value  : constant Low_Level.Get_Bucket_Versioning_Outcome :=
              (Kind          => Low_Level.Bucket_Versioning_Found,
               Status        => 200,
               Configuration => (others => <>));
            Result : constant Get_Bucket_Versioning_Result :=
              Normalize_Get_Bucket_Versioning_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketVersioning certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Get_Bucket_Versioning_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Get_Bucket_Versioning_Result_Corpus;

   procedure Check_Put_Bucket_Versioning_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Bucket_Versioning_Mutation_Disposition;
      Failure     : Failure_Reason)
   is
      Value  : constant Low_Level.Put_Bucket_Versioning_Outcome :=
        (if Status = 200
         then
           (Kind   => Low_Level.Bucket_Versioning_Updated,
            Status => Status)
         else
           (Kind   => Low_Level.Put_Bucket_Versioning_Rejected,
            Status => Status,
            Error  =>
              (Code       => US.To_Unbounded_String (Code),
               Message    => US.Null_Unbounded_String,
               Resource   => US.Null_Unbounded_String,
               Request_ID => US.Null_Unbounded_String,
               Host_ID    => US.Null_Unbounded_String)));
      Result : constant Put_Bucket_Versioning_Result :=
        Normalize_Put_Bucket_Versioning_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Put_Bucket_Versioning_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "PutBucketVersioning response certainty corpus mismatch";
      end if;
   end Check_Put_Bucket_Versioning_Response;

   procedure Check_Put_Bucket_Versioning_Certainty_Corpus is
      type Failure_Kind_Array is
        array (Positive range <>) of HTTP_Client.Exchange_Result_Kind;
      type Response_Pair is record
         Status : Flyology.HTTP.Status_Code;
         Code   : US.Unbounded_String;
      end record;
      type Response_Pair_Array is
        array (Positive range <>) of Response_Pair;
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
      Conclusive_Pairs : constant Response_Pair_Array :=
        (1 => (400, US.To_Unbounded_String ("BadDigest")),
         2 => (400, US.To_Unbounded_String ("InvalidArgument")),
         3 => (400, US.To_Unbounded_String ("InvalidDigest")),
         4 => (400, US.To_Unbounded_String ("InvalidRequest")),
         5 => (400, US.To_Unbounded_String ("MalformedXML")),
         6 => (400, US.To_Unbounded_String ("XAmzContentSHA256Mismatch")),
         7 => (501, US.To_Unbounded_String ("NotImplemented")));
      Retryable_Pairs : constant Response_Pair_Array :=
        (1 => (409, US.To_Unbounded_String ("OperationAborted")),
         2 => (429, US.To_Unbounded_String ("SlowDown")),
         3 => (500, US.To_Unbounded_String ("InternalError")),
         4 => (502, US.To_Unbounded_String ("BadGateway")),
         5 => (503, US.To_Unbounded_String ("SlowDown")),
         6 => (504, US.To_Unbounded_String ("RequestTimeout")));
   begin
      Check_Put_Bucket_Versioning_Response
        (200,
         "",
         Bucket_Versioning_Mutation_Completed,
         No_Failure);
      for Pair of Conclusive_Pairs loop
         Check_Put_Bucket_Versioning_Response
           (Pair.Status,
            US.To_String (Pair.Code),
            Bucket_Versioning_Mutation_Definitely_Not_Applied,
            Invalid_Request);
      end loop;
      Check_Put_Bucket_Versioning_Response
        (401,
         "InvalidAccessKeyId",
         Bucket_Versioning_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Put_Bucket_Versioning_Response
        (403,
         "AccessDenied",
         Bucket_Versioning_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Put_Bucket_Versioning_Response
        (404,
         "NoSuchBucket",
         Bucket_Versioning_Mutation_Definitely_Not_Applied,
         Not_Found);
      for Pair of Retryable_Pairs loop
         Check_Put_Bucket_Versioning_Response
           (Pair.Status,
            US.To_String (Pair.Code),
            Bucket_Versioning_Mutation_Outcome_Unknown,
            Unavailable_Or_Retryable);
      end loop;
      Check_Put_Bucket_Versioning_Response
        (409,
         "",
         Bucket_Versioning_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Success : constant Low_Level.Put_Bucket_Versioning_Outcome :=
              (Kind   => Low_Level.Bucket_Versioning_Updated,
               Status => 200);
            Rejection : constant Low_Level.Put_Bucket_Versioning_Outcome :=
              (Kind   => Low_Level.Put_Bucket_Versioning_Rejected,
               Status => 403,
               Error  =>
                 (Code       => US.To_Unbounded_String ("AccessDenied"),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String));
            Success_Result : constant Put_Bucket_Versioning_Result :=
              Normalize_Put_Bucket_Versioning_Response
                (Success, Admission);
            Rejection_Result : constant Put_Bucket_Versioning_Result :=
              Normalize_Put_Bucket_Versioning_Response
                (Rejection, Admission);
         begin
            if Success_Result.Disposition /=
              Bucket_Versioning_Mutation_Outcome_Unknown
              or else Success_Result.Failure /=
                Corrupt_Or_Invalid_Response
              or else Rejection_Result.Disposition /=
                Bucket_Versioning_Mutation_Outcome_Unknown
              or else Rejection_Result.Failure /=
                Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "PutBucketVersioning accepted inconsistent certainty";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Put_Bucket_Versioning_Result :=
                 Normalize_Put_Bucket_Versioning_Failure
                   (Kind, Admission, HTTP_Client.Sending_Request_Body);
               Expected : constant Bucket_Versioning_Mutation_Disposition :=
                 (if Kind = HTTP_Client.Cancelled
                    and then Admission = HTTP_Client.Not_Admitted
                  then Bucket_Versioning_Mutation_Cancelled_Before_Admission
                  elsif Admission = HTTP_Client.Not_Admitted
                  then Bucket_Versioning_Mutation_Definitely_Not_Applied
                  else Bucket_Versioning_Mutation_Outcome_Unknown);
               Expected_Failure : constant Failure_Reason :=
                 (case Kind is
                    when HTTP_Client.Pre_Admission_Rejected =>
                      Invalid_Request,
                    when HTTP_Client.Cancelled => Cancelled,
                    when HTTP_Client.Timed_Out => Timed_Out,
                    when HTTP_Client.Client_Unavailable =>
                      Client_Unavailable,
                    when HTTP_Client.Connection_Failed =>
                      Connection_Failed,
                    when HTTP_Client.Transport_Failed => Transport_Failed,
                    when HTTP_Client.Request_Source_Failed =>
                      Request_Source_Failed,
                    when HTTP_Client.Response_Body_Too_Large
                       | HTTP_Client.Response_Invalid
                       | HTTP_Client.Response_Sink_Failed =>
                      Corrupt_Or_Invalid_Response,
                    when HTTP_Client.Response_Complete =>
                      raise Program_Error with
                        "complete response is not a failure");
            begin
               if Result.Kind /= Put_Bucket_Versioning_Exchange_Failed
                 or else Result.Disposition /= Expected
                 or else Result.Failure /= Expected_Failure
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "PutBucketVersioning exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Put_Bucket_Versioning_Certainty_Corpus;

   procedure Check_Bucket_Policy_Certainty_Corpus is
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
         return Bucket_Policy_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Policy_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Policy_Mutation_Definitely_Not_Applied
         else Bucket_Policy_Mutation_Outcome_Unknown);

      procedure Check_Put_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Policy_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind   => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error  => Error_Response (Code)));
         Result : constant Put_Bucket_Policy_Result :=
           Normalize_Put_Bucket_Policy_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Bucket_Policy_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketPolicy response normalization mismatch";
         end if;
      end Check_Put_Response;

      procedure Check_Delete_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Policy_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind   => Low_Level.Configuration_Deleted,
                  Status => Status)
            else (Kind   => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error  => Error_Response (Code)));
         Result : constant Delete_Bucket_Policy_Result :=
           Normalize_Delete_Bucket_Policy_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_Policy_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketPolicy response normalization mismatch";
         end if;
      end Check_Delete_Response;
   begin
      Check_Put_Response
        (200, "", Bucket_Policy_Mutation_Completed, No_Failure);
      Check_Put_Response
        (400, "BadDigest",
         Bucket_Policy_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Put_Response
        (409, "OperationAborted", Bucket_Policy_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (500, "Unknown", Bucket_Policy_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      Check_Delete_Response
        (204, "", Bucket_Policy_Mutation_Completed, No_Failure);
      Check_Delete_Response
        (404, "NoSuchBucket",
         Bucket_Policy_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Delete_Response
        (500, "InternalError", Bucket_Policy_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (403, "", Bucket_Policy_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Put_Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind   => Low_Level.Bucket_Control_Updated,
               Status => 200);
            Delete_Value : constant
              Low_Level.Delete_Bucket_Configuration_Outcome :=
                (Kind   => Low_Level.Configuration_Deleted,
                 Status => 204);
            Put_Result : constant Put_Bucket_Policy_Result :=
              Normalize_Put_Bucket_Policy_Response (Put_Value, Admission);
            Delete_Result : constant Delete_Bucket_Policy_Result :=
              Normalize_Delete_Bucket_Policy_Response
                (Delete_Value, Admission);
         begin
            if Put_Result.Disposition /=
              Bucket_Policy_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Delete_Result.Disposition /=
                Bucket_Policy_Mutation_Outcome_Unknown
              or else Delete_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent bucket-policy certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Put_Result : constant Put_Bucket_Policy_Result :=
                 Normalize_Put_Bucket_Policy_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Delete_Result : constant Delete_Bucket_Policy_Result :=
                 Normalize_Delete_Bucket_Policy_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Disposition : constant Bucket_Policy_Mutation_Disposition :=
                 Expected_Disposition (Kind, Admission);
               Failure : constant Failure_Reason := Expected_Failure (Kind);
            begin
               if Put_Result.Kind /= Put_Bucket_Policy_Exchange_Failed
                 or else Put_Result.Disposition /= Disposition
                 or else Put_Result.Failure /= Failure
                 or else Put_Result.Admission /= Admission
                 or else Put_Result.HTTP_Result /= Kind
                 or else Delete_Result.Kind /=
                   Delete_Bucket_Policy_Exchange_Failed
                 or else Delete_Result.Disposition /= Disposition
                 or else Delete_Result.Failure /= Failure
                 or else Delete_Result.Admission /= Admission
                 or else Delete_Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "bucket-policy exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Bucket_Policy_Certainty_Corpus;

   procedure Check_Bucket_Encryption_Result_Corpus is
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
         return Bucket_Encryption_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Encryption_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Encryption_Mutation_Definitely_Not_Applied
         else Bucket_Encryption_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Get_Bucket_Encryption_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Found,
                  Status => Status,
                  Configuration => (others => <>))
            else (Kind => Low_Level.Get_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Get_Bucket_Encryption_Result :=
           Normalize_Get_Bucket_Encryption_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Bucket_Encryption_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketEncryption response normalization mismatch";
         end if;
      end Check_Response;

      procedure Check_Put
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Encryption_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Bucket_Encryption_Result :=
           Normalize_Put_Bucket_Encryption_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Bucket_Encryption_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketEncryption response normalization mismatch";
         end if;
      end Check_Put;

      procedure Check_Delete
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Encryption_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Encryption_Result :=
           Normalize_Delete_Bucket_Encryption_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_Encryption_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketEncryption response normalization mismatch";
         end if;
      end Check_Delete;
   begin
      Check_Response (200, "", No_Failure);
      Check_Response (400, "InvalidBucketName", Invalid_Request);
      Check_Response (400, "InvalidRequest", Invalid_Request);
      Check_Response (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Response (403, "AccessDenied", Authorization_Failed);
      Check_Response (404, "NoSuchBucket", Not_Found);
      Check_Response
        (404, "ServerSideEncryptionConfigurationNotFoundError", Not_Found);
      Check_Response (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Response (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (500, "InternalError", Unavailable_Or_Retryable);
      Check_Response (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Response (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Response (501, "NotImplemented", Invalid_Request);
      Check_Response (409, "", Corrupt_Or_Invalid_Response);

      Check_Put
        (200, "", Bucket_Encryption_Mutation_Completed, No_Failure);
      Check_Put
        (400, "MalformedXML",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put
        (403, "AccessDenied",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Put
        (404, "NoSuchBucket",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Put
        (409, "OperationAborted",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put
        (500, "Unknown",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      Check_Delete
        (204, "", Bucket_Encryption_Mutation_Completed, No_Failure);
      Check_Delete
        (400, "InvalidBucketName",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Delete
        (400, "InvalidArgument",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Delete
        (400, "InvalidRequest",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Delete
        (401, "InvalidAccessKeyId",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Delete
        (403, "AccessDenied",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Delete
        (404, "NoSuchBucket",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Delete
        (409, "OperationAborted",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete
        (429, "SlowDown",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete
        (500, "InternalError",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete
        (502, "BadGateway",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete
        (503, "SlowDown",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete
        (504, "RequestTimeout",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete
        (501, "NotImplemented",
         Bucket_Encryption_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Delete
        (500, "Unknown",
         Bucket_Encryption_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_Encryption_Outcome :=
              (Kind          => Low_Level.Bucket_Control_Found,
               Status        => 200,
               Configuration => (others => <>));
            Result : constant Get_Bucket_Encryption_Result :=
              Normalize_Get_Bucket_Encryption_Response (Value, Admission);
            Delete_Value : constant
              Low_Level.Delete_Bucket_Configuration_Outcome :=
                (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Delete_Result : constant Delete_Bucket_Encryption_Result :=
              Normalize_Delete_Bucket_Encryption_Response
                (Delete_Value, Admission);
            Put_Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Put_Result : constant Put_Bucket_Encryption_Result :=
              Normalize_Put_Bucket_Encryption_Response
                (Put_Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response
              or else Put_Result.Disposition /=
                Bucket_Encryption_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Delete_Result.Disposition /=
                Bucket_Encryption_Mutation_Outcome_Unknown
              or else Delete_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent bucket-encryption certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Get_Bucket_Encryption_Result :=
                 Normalize_Get_Bucket_Encryption_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Delete_Result : constant Delete_Bucket_Encryption_Result :=
                 Normalize_Delete_Bucket_Encryption_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Put_Result : constant Put_Bucket_Encryption_Result :=
                 Normalize_Put_Bucket_Encryption_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Get_Bucket_Encryption_Exchange_Failed
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
                 or else Put_Result.Kind /=
                   Put_Bucket_Encryption_Exchange_Failed
                 or else Put_Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Put_Result.Failure /= Expected_Failure (Kind)
                 or else Put_Result.Admission /= Admission
                 or else Put_Result.HTTP_Result /= Kind
                 or else Delete_Result.Kind /=
                   Delete_Bucket_Encryption_Exchange_Failed
                 or else Delete_Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Delete_Result.Failure /= Expected_Failure (Kind)
                 or else Delete_Result.Admission /= Admission
                 or else Delete_Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "bucket-encryption exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Bucket_Encryption_Result_Corpus;

   procedure Check_Get_Bucket_Lifecycle_Result_Corpus is
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

      procedure Check_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant
           Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
             (if Status = 200
              then
                (Kind => Low_Level.Bucket_Control_Found,
                 Status => Status,
                 Configuration => (others => <>),
                 Transition_Default_Minimum_Object_Size =>
                   S3.Lifecycle.Transition_Minimum_Absent)
              else
                (Kind => Low_Level.Get_Bucket_Control_Rejected,
                 Status => Status,
                 Error => Error_Response (Code)));
         Result : constant Get_Bucket_Lifecycle_Result :=
           Normalize_Get_Bucket_Lifecycle_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Bucket_Lifecycle_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketLifecycleConfiguration normalization mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response (200, "", No_Failure);
      Check_Response (400, "InvalidBucketName", Invalid_Request);
      Check_Response (400, "InvalidRequest", Invalid_Request);
      Check_Response (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Response (403, "AccessDenied", Authorization_Failed);
      Check_Response (404, "NoSuchBucket", Not_Found);
      Check_Response (404, "NoSuchLifecycleConfiguration", Not_Found);
      Check_Response (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Response (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (500, "InternalError", Unavailable_Or_Retryable);
      Check_Response (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Response (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Response (501, "NotImplemented", Invalid_Request);
      Check_Response (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant
              Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
                (Kind => Low_Level.Bucket_Control_Found,
                 Status => 200,
                 Configuration => (others => <>),
                 Transition_Default_Minimum_Object_Size =>
                   S3.Lifecycle.Transition_Minimum_Absent);
            Result : constant Get_Bucket_Lifecycle_Result :=
              Normalize_Get_Bucket_Lifecycle_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent lifecycle read certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Get_Bucket_Lifecycle_Result :=
                 Normalize_Get_Bucket_Lifecycle_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Get_Bucket_Lifecycle_Exchange_Failed
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "lifecycle exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Get_Bucket_Lifecycle_Result_Corpus;

   procedure Check_Put_Bucket_Lifecycle_Result_Corpus is
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
         return Bucket_Lifecycle_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Lifecycle_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Lifecycle_Mutation_Definitely_Not_Applied
         else Bucket_Lifecycle_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Lifecycle_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant
           Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome :=
             (Kind =>
                (if Status = 200
                 then Low_Level.Bucket_Control_Updated
                 else Low_Level.Put_Bucket_Control_Rejected),
              Status => Status,
              Transition_Default_Minimum_Object_Size =>
                S3.Lifecycle.Transition_Minimum_Absent,
              Error => Error_Response (Code));
         Result : constant Put_Bucket_Lifecycle_Result :=
           Normalize_Put_Bucket_Lifecycle_Response
             (Value, HTTP_Client.Response_Observed,
              HTTP_Client.Waiting_Response_Head);
      begin
         if Result.Kind /= Put_Bucket_Lifecycle_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
           or else Result.HTTP_Result /= HTTP_Client.Response_Complete
         then
            raise Program_Error with
              "PutBucketLifecycleConfiguration normalization mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response
        (200, "", Bucket_Lifecycle_Mutation_Completed, No_Failure);
      Check_Response
        (400, "BadDigest",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (400, "InvalidArgument",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (400, "InvalidDigest",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (400, "MalformedXML",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (400, "XAmzContentSHA256Mismatch",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Response
        (409, "OperationAborted", Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown", Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (409, "", Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant
              Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome :=
                (Kind => Low_Level.Bucket_Control_Updated,
                 Status => 200,
                 Transition_Default_Minimum_Object_Size =>
                   S3.Lifecycle.Transition_Minimum_Absent,
                 Error => (others => <>));
            Result : constant Put_Bucket_Lifecycle_Result :=
              Normalize_Put_Bucket_Lifecycle_Response
                (Value, Admission, HTTP_Client.Waiting_Response_Head);
         begin
            if Result.Disposition /=
              Bucket_Lifecycle_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent lifecycle mutation certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Put_Bucket_Lifecycle_Result :=
                 Normalize_Put_Bucket_Lifecycle_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head, "");
            begin
               if Result.Kind /= Put_Bucket_Lifecycle_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "lifecycle mutation exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Put_Bucket_Lifecycle_Result_Corpus;

   procedure Check_Bucket_Notification_Result_Corpus is
      function Error_Response (Code : String) return S3.Errors.Error_Response
      is
        ((Code       => US.To_Unbounded_String (Code),
          Message    => US.Null_Unbounded_String,
          Resource   => US.Null_Unbounded_String,
          Request_ID => US.Null_Unbounded_String,
          Host_ID    => US.Null_Unbounded_String));

      function Get_Value
        (Status : Flyology.HTTP.Status_Code; Code : String)
         return Low_Level.Get_Bucket_Notification_Configuration_Outcome is
        ((Kind =>
            (if Status = 200
             then Low_Level.Bucket_Control_Found
             else Low_Level.Get_Bucket_Control_Rejected),
          Status => Status,
          Configuration => (others => <>),
          Error => Error_Response (Code)));

      function Put_Value
        (Status : Flyology.HTTP.Status_Code; Code : String)
         return Low_Level.Put_Bucket_Control_Outcome is
        (if Status = 200
         then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
         else
           (Kind => Low_Level.Put_Bucket_Control_Rejected,
            Status => Status, Error => Error_Response (Code)));

      procedure Check_Get
        (Status : Flyology.HTTP.Status_Code; Code : String;
         Failure : Failure_Reason)
      is
         Result : constant Get_Bucket_Notification_Result :=
           Normalize_Get_Bucket_Notification_Response
             (Get_Value (Status, Code), HTTP_Client.Response_Observed,
              HTTP_Client.Waiting_Response_Head);
      begin
         if Result.Kind /= Get_Bucket_Notification_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketNotificationConfiguration normalization mismatch";
         end if;
      end Check_Get;

      procedure Check_Put
        (Status : Flyology.HTTP.Status_Code; Code : String;
         Disposition : Bucket_Notification_Mutation_Disposition;
         Failure : Failure_Reason)
      is
         Result : constant Put_Bucket_Notification_Result :=
           Normalize_Put_Bucket_Notification_Response
             (Put_Value (Status, Code), HTTP_Client.Response_Observed,
              HTTP_Client.Waiting_Response_Head);
      begin
         if Result.Kind /= Put_Bucket_Notification_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
         then
            raise Program_Error with
              "PutBucketNotificationConfiguration normalization mismatch";
         end if;
      end Check_Put;
   begin
      Check_Get (200, "", No_Failure);
      Check_Get (400, "InvalidRequest", Invalid_Request);
      Check_Get (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get (403, "AccessDenied", Authorization_Failed);
      Check_Get (404, "NoSuchBucket", Not_Found);
      Check_Get (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get (409, "", Corrupt_Or_Invalid_Response);

      Check_Put
        (200, "", Bucket_Notification_Mutation_Completed, No_Failure);
      Check_Put
        (400, "MalformedXML",
         Bucket_Notification_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put
        (401, "InvalidAccessKeyId",
         Bucket_Notification_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Put
        (403, "AccessDenied",
         Bucket_Notification_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Put
        (404, "NoSuchBucket",
         Bucket_Notification_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Put
        (409, "OperationAborted",
         Bucket_Notification_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put
        (409, "", Bucket_Notification_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in HTTP_Client.Admission_Certainty loop
         declare
            Get_Result : constant Get_Bucket_Notification_Result :=
              Normalize_Get_Bucket_Notification_Failure
                (HTTP_Client.Timed_Out, Admission,
                 HTTP_Client.Waiting_Response_Head, "timeout");
            Put_Result : constant Put_Bucket_Notification_Result :=
              Normalize_Put_Bucket_Notification_Failure
                (HTTP_Client.Timed_Out, Admission,
                 HTTP_Client.Waiting_Response_Head, "timeout");
            Expected : constant Bucket_Notification_Mutation_Disposition :=
              (if Admission = HTTP_Client.Not_Admitted
               then Bucket_Notification_Mutation_Definitely_Not_Applied
               else Bucket_Notification_Mutation_Outcome_Unknown);
         begin
            if Get_Result.Kind /= Get_Bucket_Notification_Exchange_Failed
              or else Get_Result.Failure /= Timed_Out
              or else Get_Result.Admission /= Admission
              or else Put_Result.Kind /=
                Put_Bucket_Notification_Exchange_Failed
              or else Put_Result.Disposition /= Expected
              or else Put_Result.Failure /= Timed_Out
              or else Put_Result.Admission /= Admission
            then
               raise Program_Error with
                 "bucket notification exchange certainty mismatch";
            end if;
         end;
      end loop;

      declare
         Cancelled : constant Put_Bucket_Notification_Result :=
           Normalize_Put_Bucket_Notification_Failure
             (HTTP_Client.Cancelled, HTTP_Client.Not_Admitted,
              HTTP_Client.Waiting_Response_Head, "");
      begin
         if Cancelled.Disposition /=
           Bucket_Notification_Mutation_Cancelled_Before_Admission
         then
            raise Program_Error with
              "notification pre-admission cancellation certainty mismatch";
         end if;
      end;
   end Check_Bucket_Notification_Result_Corpus;

   procedure Check_Get_Bucket_ACL_Result_Corpus is
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

      procedure Check_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Get_Bucket_ACL_Outcome :=
           (if Status = 200
            then
              (Kind   => Low_Level.Bucket_Control_Found,
               Status => Status,
               Policy => (others => <>))
            else
              (Kind   => Low_Level.Get_Bucket_Control_Rejected,
               Status => Status,
               Error  => Error_Response (Code)));
         Result : constant Get_Bucket_ACL_Result :=
           Normalize_Get_Bucket_ACL_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Bucket_ACL_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketAcl response normalization mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response (200, "", No_Failure);
      Check_Response (400, "InvalidBucketName", Invalid_Request);
      Check_Response (400, "InvalidRequest", Invalid_Request);
      Check_Response (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Response (403, "AccessDenied", Authorization_Failed);
      Check_Response (404, "NoSuchBucket", Not_Found);
      Check_Response (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Response (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (500, "InternalError", Unavailable_Or_Retryable);
      Check_Response (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Response (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Response (501, "NotImplemented", Invalid_Request);
      Check_Response (409, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Get_Bucket_ACL_Outcome :=
              (Kind   => Low_Level.Bucket_Control_Found,
               Status => 200,
               Policy => (others => <>));
            Result : constant Get_Bucket_ACL_Result :=
              Normalize_Get_Bucket_ACL_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent GetBucketAcl certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Get_Bucket_ACL_Result :=
                 Normalize_Get_Bucket_ACL_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Get_Bucket_ACL_Exchange_Failed
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "GetBucketAcl exchange normalization mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Get_Bucket_ACL_Result_Corpus;

   procedure Check_Metadata_Table_Configuration_Result_Corpus is
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

      function Expected_Create_Disposition
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
         return Metadata_Table_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Metadata_Table_Configuration_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Metadata_Table_Configuration_Mutation_Definitely_Not_Applied
         else Metadata_Table_Configuration_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant
           Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
             (if Status = 200
              then
                (Kind          => Low_Level.Bucket_Control_Found,
                 Status        => Status,
                 Configuration => (others => <>))
              else
                (Kind   => Low_Level.Get_Bucket_Control_Rejected,
                 Status => Status,
                 Error  => Error_Response (Code)));
         Result : constant Get_Bucket_Metadata_Table_Configuration_Result :=
           Normalize_Get_Metadata_Table_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Get_Bucket_Metadata_Table_Configuration_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "metadata-table response normalization mismatch";
         end if;
      end Check_Response;

      procedure Check_Create_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Metadata_Table_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant
           Create_Bucket_Metadata_Table_Configuration_Result :=
             Normalize_Create_Metadata_Table_Response
               (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Metadata_Create_Response
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "metadata-table create response normalization mismatch";
         end if;
      end Check_Create_Response;
   begin
      Check_Response (200, "", No_Failure);
      Check_Response (400, "InvalidBucketName", Invalid_Request);
      Check_Response (400, "InvalidRequest", Invalid_Request);
      Check_Response (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Response (403, "AccessDenied", Authorization_Failed);
      Check_Response (404, "NoSuchBucket", Not_Found);
      Check_Response (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Response (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (500, "InternalError", Unavailable_Or_Retryable);
      Check_Response (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Response (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Response (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Response (501, "NotImplemented", Invalid_Request);
      Check_Response (409, "", Corrupt_Or_Invalid_Response);

      Check_Create_Response
        (200, "", Metadata_Table_Configuration_Mutation_Completed,
         No_Failure);
      Check_Create_Response
        (400, "BadDigest",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (400, "InvalidArgument",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (400, "InvalidBucketName",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (400, "InvalidDigest",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (400, "InvalidRequest",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (400, "MalformedXML",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (400, "XAmzContentSHA256Mismatch",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (401, "InvalidAccessKeyId",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Create_Response
        (403, "AccessDenied",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Create_Response
        (404, "NoSuchBucket",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Create_Response
        (409, "OperationAborted",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Response
        (429, "SlowDown",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Response
        (500, "InternalError",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Response
        (502, "BadGateway",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Response
        (503, "SlowDown",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Response
        (504, "RequestTimeout",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Create_Response
        (501, "NotImplemented",
         Metadata_Table_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Create_Response
        (500, "Unknown",
         Metadata_Table_Configuration_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
                (Kind          => Low_Level.Bucket_Control_Found,
                 Status        => 200,
                 Configuration => (others => <>));
            Result : constant Get_Bucket_Metadata_Table_Configuration_Result :=
              Normalize_Get_Metadata_Table_Response (Value, Admission);
            Create_Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Create_Result : constant
              Create_Bucket_Metadata_Table_Configuration_Result :=
                Normalize_Create_Metadata_Table_Response
                  (Create_Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response
              or else Create_Result.Disposition /=
                Metadata_Table_Configuration_Mutation_Outcome_Unknown
              or else Create_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent metadata-table certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Get_Bucket_Metadata_Table_Configuration_Result :=
                   Normalize_Get_Metadata_Table_Failure
                     (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Create_Result : constant
                 Create_Bucket_Metadata_Table_Configuration_Result :=
                   Normalize_Create_Metadata_Table_Failure
                     (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Get_Bucket_Metadata_Table_Configuration_Exchange_Failed
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
                 or else Create_Result.Kind /=
                   Metadata_Create_Exchange_Failed
                 or else Create_Result.Disposition /=
                   Expected_Create_Disposition (Kind, Admission)
                 or else Create_Result.Failure /= Expected_Failure (Kind)
                 or else Create_Result.Admission /= Admission
                 or else Create_Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "metadata-table exchange normalization mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Metadata_Table_Configuration_Result_Corpus;

   procedure Check_Delete_Bucket_Lifecycle_Certainty_Corpus is
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
         return Bucket_Lifecycle_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Lifecycle_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Lifecycle_Mutation_Definitely_Not_Applied
         else Bucket_Lifecycle_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Lifecycle_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Lifecycle_Result :=
           Normalize_Delete_Bucket_Lifecycle_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_Lifecycle_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketLifecycle response normalization mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response
        (204, "", Bucket_Lifecycle_Mutation_Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Bucket_Lifecycle_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Bucket_Lifecycle_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant Delete_Bucket_Lifecycle_Result :=
              Normalize_Delete_Bucket_Lifecycle_Response (Value, Admission);
         begin
            if Result.Disposition /=
                Bucket_Lifecycle_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketLifecycle certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Delete_Bucket_Lifecycle_Result :=
                 Normalize_Delete_Bucket_Lifecycle_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Delete_Bucket_Lifecycle_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketLifecycle exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Lifecycle_Certainty_Corpus;

   procedure Check_Delete_Bucket_Replication_Certainty_Corpus is
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
         return Bucket_Replication_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Replication_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Replication_Mutation_Definitely_Not_Applied
         else Bucket_Replication_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Replication_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Replication_Result :=
           Normalize_Delete_Bucket_Replication_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_Replication_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketReplication response normalization mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Bucket_Replication_Mutation_Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Bucket_Replication_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Bucket_Replication_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant Delete_Bucket_Replication_Result :=
              Normalize_Delete_Bucket_Replication_Response (Value, Admission);
         begin
            if Result.Disposition /=
                Bucket_Replication_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketReplication certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Delete_Bucket_Replication_Result :=
                 Normalize_Delete_Bucket_Replication_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Delete_Bucket_Replication_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketReplication exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Replication_Certainty_Corpus;

   procedure Check_Delete_Bucket_Website_Certainty_Corpus is
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
         return Bucket_Website_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Website_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Website_Mutation_Definitely_Not_Applied
         else Bucket_Website_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Website_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Website_Result :=
           Normalize_Delete_Bucket_Website_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_Website_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketWebsite response normalization mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Bucket_Website_Mutation_Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Bucket_Website_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Bucket_Website_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Bucket_Website_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Bucket_Website_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Bucket_Website_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Bucket_Website_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Bucket_Website_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Bucket_Website_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant Delete_Bucket_Website_Result :=
              Normalize_Delete_Bucket_Website_Response (Value, Admission);
         begin
            if Result.Disposition /=
                Bucket_Website_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketWebsite certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Delete_Bucket_Website_Result :=
                 Normalize_Delete_Bucket_Website_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Delete_Bucket_Website_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketWebsite exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Website_Certainty_Corpus;

   procedure Check_Delete_Bucket_Metadata_Certainty_Corpus is
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
      Completed : constant
        Bucket_Metadata_Configuration_Mutation_Disposition :=
          Bucket_Metadata_Configuration_Mutation_Completed;
      Definitely_Not_Applied : constant
        Bucket_Metadata_Configuration_Mutation_Disposition :=
          Bucket_Metadata_Configuration_Mutation_Definitely_Not_Applied;
      Outcome_Unknown : constant
        Bucket_Metadata_Configuration_Mutation_Disposition :=
          Bucket_Metadata_Configuration_Mutation_Outcome_Unknown;
      Cancelled_Before_Admission : constant
        Bucket_Metadata_Configuration_Mutation_Disposition :=
          Bucket_Metadata_Configuration_Mutation_Cancelled_Before_Admission;

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
         return Bucket_Metadata_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Applied
         else Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Metadata_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Metadata_Result :=
           Normalize_Delete_Bucket_Metadata_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Delete_Bucket_Metadata_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketMetadataConfiguration response " &
              "normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant
              Delete_Bucket_Metadata_Result :=
                Normalize_Delete_Bucket_Metadata_Response
                  (Value, Admission);
         begin
            if Result.Disposition /=
                Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketMetadataConfiguration " &
                 "certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Delete_Bucket_Metadata_Result :=
                 Normalize_Delete_Bucket_Metadata_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Delete_Bucket_Metadata_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketMetadataConfiguration exchange " &
                    "certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Metadata_Certainty_Corpus;

   procedure Check_Delete_Bucket_Metadata_Table_Certainty_Corpus is
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
      Completed : constant
        Bucket_Metadata_Table_Mutation_Disposition :=
          Bucket_Metadata_Table_Mutation_Completed;
      Definitely_Not_Applied : constant
        Bucket_Metadata_Table_Mutation_Disposition :=
          Bucket_Metadata_Table_Mutation_Definitely_Not_Applied;
      Outcome_Unknown : constant
        Bucket_Metadata_Table_Mutation_Disposition :=
          Bucket_Metadata_Table_Mutation_Outcome_Unknown;
      Cancelled_Before_Admission : constant
        Bucket_Metadata_Table_Mutation_Disposition :=
          Bucket_Metadata_Table_Mutation_Cancelled_Before_Admission;

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
         return Bucket_Metadata_Table_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Applied
         else Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Metadata_Table_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Metadata_Table_Result :=
           Normalize_Delete_Bucket_Metadata_Table_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Delete_Bucket_Metadata_Table_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketMetadataTableConfiguration response " &
              "normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant
              Delete_Bucket_Metadata_Table_Result :=
                Normalize_Delete_Bucket_Metadata_Table_Response
                  (Value, Admission);
         begin
            if Result.Disposition /=
                Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketMetadataTableConfiguration " &
                 "certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Delete_Bucket_Metadata_Table_Result :=
                 Normalize_Delete_Bucket_Metadata_Table_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Delete_Bucket_Metadata_Table_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketMetadataTableConfiguration exchange " &
                    "certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Metadata_Table_Certainty_Corpus;

   procedure Check_Delete_Bucket_Metrics_Certainty_Corpus is
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
      Completed : constant
        Bucket_Metrics_Configuration_Mutation_Disposition :=
          Bucket_Metrics_Configuration_Mutation_Completed;
      Definitely_Not_Applied : constant
        Bucket_Metrics_Configuration_Mutation_Disposition :=
          Bucket_Metrics_Configuration_Mutation_Definitely_Not_Applied;
      Outcome_Unknown : constant
        Bucket_Metrics_Configuration_Mutation_Disposition :=
          Bucket_Metrics_Configuration_Mutation_Outcome_Unknown;
      Cancelled_Before_Admission : constant
        Bucket_Metrics_Configuration_Mutation_Disposition :=
          Bucket_Metrics_Configuration_Mutation_Cancelled_Before_Admission;

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
         return Bucket_Metrics_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Applied
         else Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Metrics_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Metrics_Result :=
           Normalize_Delete_Bucket_Metrics_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Delete_Bucket_Metrics_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketMetricsConfiguration response " &
              "normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant
              Delete_Bucket_Metrics_Result :=
                Normalize_Delete_Bucket_Metrics_Response
                  (Value, Admission);
         begin
            if Result.Disposition /=
                Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketMetricsConfiguration " &
                 "certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Delete_Bucket_Metrics_Result :=
                 Normalize_Delete_Bucket_Metrics_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Delete_Bucket_Metrics_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketMetricsConfiguration exchange " &
                    "certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Metrics_Certainty_Corpus;

   procedure Check_Delete_Bucket_Analytics_Certainty_Corpus is
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
      Completed : constant
        Bucket_Analytics_Configuration_Mutation_Disposition :=
          Bucket_Analytics_Configuration_Mutation_Completed;
      Definitely_Not_Applied : constant
        Bucket_Analytics_Configuration_Mutation_Disposition :=
          Bucket_Analytics_Configuration_Mutation_Definitely_Not_Applied;
      Outcome_Unknown : constant
        Bucket_Analytics_Configuration_Mutation_Disposition :=
          Bucket_Analytics_Configuration_Mutation_Outcome_Unknown;
      Cancelled_Before_Admission : constant
        Bucket_Analytics_Configuration_Mutation_Disposition :=
          Bucket_Analytics_Configuration_Mutation_Cancelled_Before_Admission;

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
         return Bucket_Analytics_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Applied
         else Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Analytics_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Analytics_Result :=
           Normalize_Delete_Bucket_Analytics_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Delete_Bucket_Analytics_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketAnalyticsConfiguration response " &
              "normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant
              Delete_Bucket_Analytics_Result :=
                Normalize_Delete_Bucket_Analytics_Response
                  (Value, Admission);
         begin
            if Result.Disposition /=
                Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketAnalyticsConfiguration " &
                 "certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Delete_Bucket_Analytics_Result :=
                 Normalize_Delete_Bucket_Analytics_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Delete_Bucket_Analytics_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketAnalyticsConfiguration exchange " &
                    "certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Analytics_Certainty_Corpus;

   procedure Check_Delete_Bucket_Intelligent_Tiering_Certainty_Corpus is
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
      Completed : constant
        Bucket_Tiering_Configuration_Mutation_Disposition :=
          Bucket_Tiering_Configuration_Mutation_Completed;
      Definitely_Not_Applied : constant
        Bucket_Tiering_Configuration_Mutation_Disposition :=
          Bucket_Tiering_Configuration_Mutation_Definitely_Not_Applied;
      Outcome_Unknown : constant
        Bucket_Tiering_Configuration_Mutation_Disposition :=
          Bucket_Tiering_Configuration_Mutation_Outcome_Unknown;
      Cancelled_Before_Admission : constant
        Bucket_Tiering_Configuration_Mutation_Disposition :=
          Bucket_Tiering_Configuration_Mutation_Cancelled_Before_Admission;

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
         return Bucket_Tiering_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Applied
         else Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Tiering_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Tiering_Result :=
           Normalize_Delete_Bucket_Tiering_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Delete_Bucket_Tiering_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketIntelligentTieringConfiguration response " &
              "normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant
              Delete_Bucket_Tiering_Result :=
                Normalize_Delete_Bucket_Tiering_Response
                  (Value, Admission);
         begin
            if Result.Disposition /=
                Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketIntelligentTieringConfiguration " &
                 "certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Delete_Bucket_Tiering_Result :=
                 Normalize_Delete_Bucket_Tiering_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Delete_Bucket_Tiering_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketIntelligentTieringConfiguration exchange " &
                    "certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Intelligent_Tiering_Certainty_Corpus;

   procedure Check_Delete_Bucket_Inventory_Configuration_Certainty_Corpus is
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
      Completed : constant
        Bucket_Inventory_Configuration_Mutation_Disposition :=
          Bucket_Inventory_Configuration_Mutation_Completed;
      Definitely_Not_Applied : constant
        Bucket_Inventory_Configuration_Mutation_Disposition :=
          Bucket_Inventory_Configuration_Mutation_Definitely_Not_Applied;
      Outcome_Unknown : constant
        Bucket_Inventory_Configuration_Mutation_Disposition :=
          Bucket_Inventory_Configuration_Mutation_Outcome_Unknown;
      Cancelled_Before_Admission : constant
        Bucket_Inventory_Configuration_Mutation_Disposition :=
          Bucket_Inventory_Configuration_Mutation_Cancelled_Before_Admission;

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
         return Bucket_Inventory_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Applied
         else Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Inventory_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_Inventory_Configuration_Result :=
           Normalize_Delete_Bucket_Inventory_Configuration_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
           Delete_Bucket_Inventory_Configuration_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketInventoryConfiguration response normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      --  These status/code pairs are the pinned S3 error-model and signed
      --  family-corpus references used by the production normalizer.
      Check_Response
        (204, "", Completed, No_Failure);
      Check_Response
        (400, "InvalidArgument",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidBucketName",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (400, "InvalidRequest",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (401, "InvalidAccessKeyId",
         Definitely_Not_Applied,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied",
         Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (404, "NoSuchBucket",
         Definitely_Not_Applied,
         Not_Found);
      Check_Response
        (409, "OperationAborted",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout",
         Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (501, "NotImplemented",
         Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (500, "Unknown",
         Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
              (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Result : constant
              Delete_Bucket_Inventory_Configuration_Result :=
                Normalize_Delete_Bucket_Inventory_Configuration_Response
                  (Value, Admission);
         begin
            if Result.Disposition /=
                Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteBucketInventoryConfiguration certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Delete_Bucket_Inventory_Configuration_Result :=
                 Normalize_Delete_Bucket_Inventory_Configuration_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                 Delete_Bucket_Inventory_Configuration_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "DeleteBucketInventoryConfiguration exchange certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Delete_Bucket_Inventory_Configuration_Certainty_Corpus;

   procedure Check_Bucket_CORS_Result_Corpus is
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
         return Bucket_CORS_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_CORS_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_CORS_Mutation_Definitely_Not_Applied
         else Bucket_CORS_Mutation_Outcome_Unknown);

      procedure Check_Get_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Get_Bucket_CORS_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Found,
                  Status => Status,
                  Configuration => (others => <>))
            else (Kind => Low_Level.Get_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Get_Bucket_CORS_Result :=
           Normalize_Get_Bucket_CORS_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Bucket_CORS_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketCors response normalization mismatch";
         end if;
      end Check_Get_Response;

      procedure Check_Put_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_CORS_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Bucket_CORS_Result :=
           Normalize_Put_Bucket_CORS_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Bucket_CORS_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketCors response normalization mismatch";
         end if;
      end Check_Put_Response;

      procedure Check_Delete_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_CORS_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_CORS_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Bucket_CORS_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Bucket_CORS_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Bucket_CORS_Result :=
           Normalize_Delete_Bucket_CORS_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Bucket_CORS_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketCors response normalization mismatch";
         end if;
      end Check_Delete_Response;
   begin
      Check_Get_Response (200, "", No_Failure);
      Check_Get_Response (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Response (400, "InvalidRequest", Invalid_Request);
      Check_Get_Response (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Response (403, "AccessDenied", Authorization_Failed);
      Check_Get_Response (404, "NoSuchBucket", Not_Found);
      Check_Get_Response (404, "NoSuchCORSConfiguration", Not_Found);
      Check_Get_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Response (429, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Response (500, "InternalError", Unavailable_Or_Retryable);
      Check_Get_Response (502, "BadGateway", Unavailable_Or_Retryable);
      Check_Get_Response (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Response (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_Get_Response (501, "NotImplemented", Invalid_Request);
      Check_Get_Response (409, "", Corrupt_Or_Invalid_Response);

      Check_Put_Response
        (200, "", Bucket_CORS_Mutation_Completed, No_Failure);
      Check_Put_Response
        (400, "MalformedXML", Bucket_CORS_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put_Response
        (401, "InvalidAccessKeyId",
         Bucket_CORS_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Put_Response
        (403, "AccessDenied", Bucket_CORS_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Put_Response
        (404, "NoSuchBucket", Bucket_CORS_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Put_Response
        (409, "OperationAborted", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (429, "SlowDown", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (500, "InternalError", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (500, "Unknown", Bucket_CORS_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      Check_Delete_Response
        (204, "", Bucket_CORS_Mutation_Completed, No_Failure);
      Check_Delete_Response
        (400, "InvalidBucketName",
         Bucket_CORS_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Delete_Response
        (400, "InvalidArgument",
         Bucket_CORS_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Delete_Response
        (400, "InvalidRequest",
         Bucket_CORS_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Delete_Response
        (401, "InvalidAccessKeyId",
         Bucket_CORS_Mutation_Definitely_Not_Applied,
         Authentication_Failed);
      Check_Delete_Response
        (403, "AccessDenied",
         Bucket_CORS_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Delete_Response
        (404, "NoSuchBucket",
         Bucket_CORS_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Delete_Response
        (409, "OperationAborted", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (429, "SlowDown", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (500, "InternalError", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (502, "BadGateway", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (503, "SlowDown", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (504, "RequestTimeout", Bucket_CORS_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (501, "NotImplemented",
         Bucket_CORS_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Delete_Response
        (500, "Unknown", Bucket_CORS_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Get_Value : constant Low_Level.Get_Bucket_CORS_Outcome :=
              (Kind          => Low_Level.Bucket_Control_Found,
               Status        => 200,
               Configuration => (others => <>));
            Get_Result : constant Get_Bucket_CORS_Result :=
              Normalize_Get_Bucket_CORS_Response (Get_Value, Admission);
            Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Result : constant Put_Bucket_CORS_Result :=
              Normalize_Put_Bucket_CORS_Response (Value, Admission);
            Delete_Value : constant Low_Level.Delete_Bucket_CORS_Outcome :=
              (Kind => Low_Level.Bucket_CORS_Deleted, Status => 204);
            Delete_Result : constant Delete_Bucket_CORS_Result :=
              Normalize_Delete_Bucket_CORS_Response
                (Delete_Value, Admission);
         begin
            if Get_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Result.Disposition /=
                Bucket_CORS_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
              or else Delete_Result.Disposition /=
                Bucket_CORS_Mutation_Outcome_Unknown
              or else Delete_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent bucket-CORS certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Get_Result : constant Get_Bucket_CORS_Result :=
                 Normalize_Get_Bucket_CORS_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Result : constant Put_Bucket_CORS_Result :=
                 Normalize_Put_Bucket_CORS_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Delete_Result : constant Delete_Bucket_CORS_Result :=
                 Normalize_Delete_Bucket_CORS_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Get_Result.Kind /= Get_Bucket_CORS_Exchange_Failed
                 or else Get_Result.Failure /= Expected_Failure (Kind)
                 or else Get_Result.Admission /= Admission
                 or else Get_Result.HTTP_Result /= Kind
                 or else Result.Kind /= Put_Bucket_CORS_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
                 or else Delete_Result.Kind /=
                   Delete_Bucket_CORS_Exchange_Failed
                 or else Delete_Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Delete_Result.Failure /= Expected_Failure (Kind)
                 or else Delete_Result.Admission /= Admission
                 or else Delete_Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "bucket-CORS exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Bucket_CORS_Result_Corpus;

   procedure Check_Object_Lock_Configuration_Certainty_Corpus is
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

      function Error_Response
        (Code : String) return S3.Errors.Error_Response is
        (Code       => US.To_Unbounded_String (Code),
         Message    => US.Null_Unbounded_String,
         Resource   => US.Null_Unbounded_String,
         Request_ID => US.Null_Unbounded_String,
         Host_ID    => US.Null_Unbounded_String);

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
            when HTTP_Client.Response_Invalid |
                 HTTP_Client.Response_Body_Too_Large |
                 HTTP_Client.Response_Sink_Failed =>
              Corrupt_Or_Invalid_Response,
            when HTTP_Client.Response_Complete =>
              raise Program_Error with "complete response is not a failure");

      function Expected_Disposition
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
         return Object_Lock_Configuration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Object_Lock_Configuration_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Object_Lock_Configuration_Mutation_Definitely_Not_Applied
         else Object_Lock_Configuration_Mutation_Outcome_Unknown);

      function Get_Value
        (Status : Flyology.HTTP.Status_Code;
         Code   : String := "")
         return Low_Level.Get_Object_Lock_Configuration_Outcome is
        (if Status = 200
         then (Kind => Low_Level.Object_Lock_Configuration_Found,
               Status => Status, Configuration => (others => <>))
         else (Kind => Low_Level.Get_Object_Lock_Configuration_Rejected,
               Status => Status, Error => Error_Response (Code)));

      function Put_Value
        (Status : Flyology.HTTP.Status_Code;
         Code   : String := "")
         return Low_Level.Put_Object_Lock_Configuration_Outcome is
        (if Status = 200
         then (Kind => Low_Level.Object_Lock_Configuration_Updated,
               Status => Status, Result => (others => <>))
         else (Kind => Low_Level.Put_Object_Lock_Configuration_Rejected,
               Status => Status, Error => Error_Response (Code)));

      procedure Check_Get_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Result : constant Get_Object_Lock_Configuration_Result :=
           Normalize_Get_Object_Lock_Configuration_Response
             (Get_Value (Status, Code), HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Object_Lock_Configuration_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetObjectLockConfiguration response normalization mismatch";
         end if;
      end Check_Get_Response;

      procedure Check_Put_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Object_Lock_Configuration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Result : constant Put_Object_Lock_Configuration_Result :=
           Normalize_Put_Object_Lock_Configuration_Response
             (Put_Value (Status, Code), HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Object_Lock_Configuration_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutObjectLockConfiguration response normalization mismatch";
         end if;
      end Check_Put_Response;

      procedure Check_Failure
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
      is
         Get_Result : constant Get_Object_Lock_Configuration_Result :=
           Normalize_Get_Object_Lock_Configuration_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
         Put_Result : constant Put_Object_Lock_Configuration_Result :=
           Normalize_Put_Object_Lock_Configuration_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
      begin
         if Get_Result.Kind /= Get_Object_Lock_Configuration_Exchange_Failed
           or else Get_Result.Failure /= Expected_Failure (Kind)
           or else Get_Result.Admission /= Admission
           or else Get_Result.HTTP_Result /= Kind
           or else Put_Result.Kind /=
             Put_Object_Lock_Configuration_Exchange_Failed
           or else Put_Result.Disposition /=
             Expected_Disposition (Kind, Admission)
           or else Put_Result.Failure /= Expected_Failure (Kind)
           or else Put_Result.Admission /= Admission
           or else Put_Result.HTTP_Result /= Kind
         then
            raise Program_Error with
              "Object Lock configuration exchange normalization mismatch";
         end if;
      end Check_Failure;
   begin
      Check_Get_Response (200, "", No_Failure);
      Check_Get_Response (400, "InvalidBucketName", Invalid_Request);
      Check_Get_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Response (403, "AccessDenied", Authorization_Failed);
      Check_Get_Response (404, "NoSuchBucket", Not_Found);
      Check_Get_Response
        (404, "ObjectLockConfigurationNotFoundError", Not_Found);
      Check_Get_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Response (403, "", Corrupt_Or_Invalid_Response);

      Check_Put_Response
        (200, "", Object_Lock_Configuration_Mutation_Completed, No_Failure);
      Check_Put_Response
        (400, "MalformedXML",
         Object_Lock_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put_Response
        (403, "AccessDenied",
         Object_Lock_Configuration_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Put_Response
        (404, "NoSuchBucket",
         Object_Lock_Configuration_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Put_Response
        (409, "InvalidBucketState",
         Object_Lock_Configuration_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put_Response
        (409, "OperationAborted",
         Object_Lock_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (500, "InternalError",
         Object_Lock_Configuration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (403, "", Object_Lock_Configuration_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Get_Result : constant Get_Object_Lock_Configuration_Result :=
              Normalize_Get_Object_Lock_Configuration_Response
                (Get_Value (200), Admission);
            Put_Result : constant Put_Object_Lock_Configuration_Result :=
              Normalize_Put_Object_Lock_Configuration_Response
                (Put_Value (200), Admission);
         begin
            if Get_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Put_Result.Disposition /=
                Object_Lock_Configuration_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent Object Lock certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Object_Lock_Configuration_Certainty_Corpus;

   procedure Check_Object_Lock_Configuration_Pre_Admission_Rejection
     (Client   : not null access Flyology.HTTP.Client.Client;
      Prepared : Flyology.Object_Storage.Client.Low_Level.Prepared_Request;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline)
   is
      --  Derived capacity: test parent, rejected HTTP exchange, and the
      --  otherwise possible transport child bound this negative oracle.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Wrong : aliased Low_Level.Prepared_Request := Prepared;
      Get_Operation : aliased Get_Object_Lock_Configuration_Operation
        (Set'Access, Client, null);
      Put_Operation : aliased Put_Object_Lock_Configuration_Operation
        (Set'Access, Client, null);
      Get_Rejected : Boolean := False;
      Put_Rejected : Boolean := False;
   begin
      begin
         Low_Level.Get_Object_Lock_Configuration
           (Client, Wrong'Access, Get_Operation'Access, Deadline, null,
            Get_Operation.Child);
      exception
         when Low_Level.Invalid_Request => Get_Rejected := True;
      end;
      begin
         Low_Level.Put_Object_Lock_Configuration
           (Client, Wrong'Access, Put_Operation'Access, Put_Operation'Access,
            Deadline, null, Put_Operation.Child);
      exception
         when Low_Level.Invalid_Request => Put_Rejected := True;
      end;
      if not Get_Rejected or else not Put_Rejected
        or else Flyology.Operations.Is_Active (Get_Operation.Child)
        or else Flyology.Operations.Is_Active (Put_Operation.Child)
      then
         raise Program_Error with
           "Object Lock wrong prepared operation crossed admission";
      end if;
   end Check_Object_Lock_Configuration_Pre_Admission_Rejection;

   procedure Set_Response_Limit
     (Operation : in out Get_Object_Lock_Configuration_Operation;
      Maximum   : Natural) is
   begin
      Operation.Response_Limit := Maximum;
   end Set_Response_Limit;

   procedure Set_Response_Limit
     (Operation : in out Put_Object_Lock_Configuration_Operation;
      Maximum   : Natural) is
   begin
      Operation.Response_Limit := Maximum;
   end Set_Response_Limit;

   procedure Check_Ownership_Controls_Certainty_Corpus is
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
         return Bucket_Ownership_Controls_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Bucket_Ownership_Controls_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied
         else Bucket_Ownership_Controls_Mutation_Outcome_Unknown);

      procedure Check_Get_Response
        (Status  : Flyology.HTTP.Status_Code;
         Code    : String;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Found,
                  Status => Status,
                  Configuration => (others => <>))
            else (Kind => Low_Level.Get_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Get_Bucket_Ownership_Controls_Result :=
           Normalize_Get_Bucket_Ownership_Controls_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
              Get_Bucket_Ownership_Controls_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetBucketOwnershipControls response normalization mismatch";
         end if;
      end Check_Get_Response;

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Ownership_Controls_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Bucket_Ownership_Controls_Result :=
           Normalize_Put_Bucket_Ownership_Controls_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
              Put_Bucket_Ownership_Controls_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketOwnershipControls response normalization mismatch";
         end if;
      end Check_Response;

      procedure Check_Delete_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Bucket_Ownership_Controls_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Ownership_Controls_Result :=
           Normalize_Delete_Ownership_Controls_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Ownership_Controls_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteBucketOwnershipControls response normalization mismatch";
         end if;
      end Check_Delete_Response;
   begin
      Check_Get_Response (200, "", No_Failure);
      Check_Get_Response
        (404, "OwnershipControlsNotFoundError", Not_Found);
      Check_Get_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get_Response (409, "", Corrupt_Or_Invalid_Response);

      Check_Response
        (200, "", Bucket_Ownership_Controls_Mutation_Completed, No_Failure);
      Check_Response
        (400, "InvalidBucketAclWithObjectOwnership",
         Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Response
        (409, "OperationAborted",
         Bucket_Ownership_Controls_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "Unknown", Bucket_Ownership_Controls_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);
      Check_Delete_Response
        (204, "", Bucket_Ownership_Controls_Mutation_Completed, No_Failure);
      Check_Delete_Response
        (404, "NoSuchBucket",
         Bucket_Ownership_Controls_Mutation_Definitely_Not_Applied,
         Not_Found);
      Check_Delete_Response
        (500, "InternalError",
         Bucket_Ownership_Controls_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Result : constant Put_Bucket_Ownership_Controls_Result :=
              Normalize_Put_Bucket_Ownership_Controls_Response
                (Value, Admission);
         begin
            if Result.Disposition /=
                Bucket_Ownership_Controls_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent ownership-controls certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Put_Bucket_Ownership_Controls_Result :=
                 Normalize_Put_Bucket_Ownership_Controls_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Get_Result : constant Get_Bucket_Ownership_Controls_Result :=
                 Normalize_Get_Bucket_Ownership_Controls_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Delete_Result : constant Delete_Ownership_Controls_Result :=
                 Normalize_Delete_Ownership_Controls_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Disposition : constant
                 Bucket_Ownership_Controls_Mutation_Disposition :=
                   Expected_Disposition (Kind, Admission);
            begin
               if Result.Kind /=
                    Put_Bucket_Ownership_Controls_Exchange_Failed
                 or else Result.Disposition /= Disposition
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
                 or else Get_Result.Kind /=
                   Get_Bucket_Ownership_Controls_Exchange_Failed
                 or else Get_Result.Failure /= Expected_Failure (Kind)
                 or else Get_Result.Admission /= Admission
                 or else Get_Result.HTTP_Result /= Kind
                 or else Delete_Result.Kind /=
                   Delete_Ownership_Controls_Exchange_Failed
                 or else Delete_Result.Disposition /= Disposition
                 or else Delete_Result.Failure /= Expected_Failure (Kind)
                 or else Delete_Result.Admission /= Admission
                 or else Delete_Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "ownership-controls exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Ownership_Controls_Certainty_Corpus;

   procedure Check_Public_Access_Block_Certainty_Corpus is
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
         return Public_Access_Block_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Public_Access_Block_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Public_Access_Block_Mutation_Definitely_Not_Applied
         else Public_Access_Block_Mutation_Outcome_Unknown);

      procedure Check_Get
        (Status : Flyology.HTTP.Status_Code;
         Code : String;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Get_Public_Access_Block_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Found,
                  Status => Status,
                  Configuration => (others => <>))
            else (Kind => Low_Level.Get_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Get_Public_Access_Block_Result :=
           Normalize_Get_Public_Access_Block_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Public_Access_Block_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetPublicAccessBlock response normalization mismatch";
         end if;
      end Check_Get;

      procedure Check_Put
        (Status : Flyology.HTTP.Status_Code;
         Code : String;
         Disposition : Public_Access_Block_Mutation_Disposition;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Public_Access_Block_Result :=
           Normalize_Put_Public_Access_Block_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Public_Access_Block_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutPublicAccessBlock response normalization mismatch";
         end if;
      end Check_Put;

      procedure Check_Delete
        (Status : Flyology.HTTP.Status_Code;
         Code : String;
         Disposition : Public_Access_Block_Mutation_Disposition;
         Failure : Failure_Reason)
      is
         Value : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
           (if Status = 204
            then (Kind => Low_Level.Configuration_Deleted, Status => Status)
            else (Kind => Low_Level.Delete_Configuration_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Delete_Public_Access_Block_Result :=
           Normalize_Delete_Public_Access_Block_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Public_Access_Block_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeletePublicAccessBlock response normalization mismatch";
         end if;
      end Check_Delete;
   begin
      Check_Get (200, "", No_Failure);
      Check_Get (403, "AccessDenied", Authorization_Failed);
      Check_Get
        (404, "NoSuchPublicAccessBlockConfiguration", Not_Found);
      Check_Get (503, "SlowDown", Unavailable_Or_Retryable);
      Check_Get (409, "", Corrupt_Or_Invalid_Response);

      Check_Put
        (200, "", Public_Access_Block_Mutation_Completed, No_Failure);
      Check_Put
        (400, "MalformedXML",
         Public_Access_Block_Mutation_Definitely_Not_Applied,
         Invalid_Request);
      Check_Put
        (409, "OperationAborted",
         Public_Access_Block_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put
        (500, "Unknown", Public_Access_Block_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      Check_Delete
        (204, "", Public_Access_Block_Mutation_Completed, No_Failure);
      Check_Delete
        (404, "NoSuchBucket",
         Public_Access_Block_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Delete
        (500, "InternalError",
         Public_Access_Block_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Put_Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Delete_Value : constant
              Low_Level.Delete_Bucket_Configuration_Outcome :=
                (Kind => Low_Level.Configuration_Deleted, Status => 204);
            Get_Value : constant Low_Level.Get_Public_Access_Block_Outcome :=
              (Kind => Low_Level.Bucket_Control_Found,
               Status => 200,
               Configuration => (others => <>));
            Put_Result : constant Put_Public_Access_Block_Result :=
              Normalize_Put_Public_Access_Block_Response
                (Put_Value, Admission);
            Delete_Result : constant Delete_Public_Access_Block_Result :=
              Normalize_Delete_Public_Access_Block_Response
                (Delete_Value, Admission);
            Get_Result : constant Get_Public_Access_Block_Result :=
              Normalize_Get_Public_Access_Block_Response
                (Get_Value, Admission);
         begin
            if Put_Result.Disposition /=
                Public_Access_Block_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Delete_Result.Disposition /=
                Public_Access_Block_Mutation_Outcome_Unknown
              or else Delete_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Get_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent PublicAccessBlock certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Put_Result : constant Put_Public_Access_Block_Result :=
                 Normalize_Put_Public_Access_Block_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Delete_Result : constant Delete_Public_Access_Block_Result :=
                 Normalize_Delete_Public_Access_Block_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Get_Result : constant Get_Public_Access_Block_Result :=
                 Normalize_Get_Public_Access_Block_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
               Disposition : constant
                 Public_Access_Block_Mutation_Disposition :=
                   Expected_Disposition (Kind, Admission);
               Failure : constant Failure_Reason := Expected_Failure (Kind);
            begin
               if Put_Result.Kind /= Put_Public_Access_Block_Exchange_Failed
                 or else Put_Result.Disposition /= Disposition
                 or else Put_Result.Failure /= Failure
                 or else Put_Result.Admission /= Admission
                 or else Put_Result.HTTP_Result /= Kind
                 or else Delete_Result.Kind /=
                   Delete_Public_Access_Block_Exchange_Failed
                 or else Delete_Result.Disposition /= Disposition
                 or else Delete_Result.Failure /= Failure
                 or else Delete_Result.Admission /= Admission
                 or else Delete_Result.HTTP_Result /= Kind
                 or else Get_Result.Kind /=
                   Get_Public_Access_Block_Exchange_Failed
                 or else Get_Result.Failure /= Failure
                 or else Get_Result.Admission /= Admission
                 or else Get_Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "PublicAccessBlock exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Public_Access_Block_Certainty_Corpus;

   procedure Check_ABAC_Certainty_Corpus is
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
         return ABAC_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then ABAC_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then ABAC_Mutation_Definitely_Not_Applied
         else ABAC_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : ABAC_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Bucket_ABAC_Result :=
           Normalize_Put_Bucket_ABAC_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Bucket_ABAC_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketAbac response normalization mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response
        (200, "", ABAC_Mutation_Completed, No_Failure);
      Check_Response
        (400, "MalformedXML",
         ABAC_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (403, "AccessDenied",
         ABAC_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (409, "OperationAborted", ABAC_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "Unknown", ABAC_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Result : constant Put_Bucket_ABAC_Result :=
              Normalize_Put_Bucket_ABAC_Response
                (Value, Admission);
         begin
            if Result.Disposition /= ABAC_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent PutBucketAbac certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Put_Bucket_ABAC_Result :=
                 Normalize_Put_Bucket_ABAC_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Put_Bucket_ABAC_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "PutBucketAbac exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_ABAC_Certainty_Corpus;

   procedure Check_Acceleration_Certainty_Corpus is
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
         return Acceleration_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Acceleration_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Acceleration_Mutation_Definitely_Not_Applied
         else Acceleration_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Acceleration_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Bucket_Accelerate_Configuration_Result :=
           Normalize_Put_Bucket_Accelerate_Configuration_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /=
              Put_Bucket_Accelerate_Configuration_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketAccelerateConfiguration response normalization " &
              "mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response
        (200, "", Acceleration_Mutation_Completed, No_Failure);
      Check_Response
        (400, "MalformedXML",
         Acceleration_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (403, "AccessDenied",
         Acceleration_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (409, "OperationAborted", Acceleration_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "Unknown", Acceleration_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Result : constant Put_Bucket_Accelerate_Configuration_Result :=
              Normalize_Put_Bucket_Accelerate_Configuration_Response
                (Value, Admission);
         begin
            if Result.Disposition /= Acceleration_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent PutBucketAccelerateConfiguration certainty " &
                 "was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant
                 Put_Bucket_Accelerate_Configuration_Result :=
                   Normalize_Put_Bucket_Accelerate_Configuration_Failure
                     (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /=
                    Put_Bucket_Accelerate_Configuration_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "PutBucketAccelerateConfiguration exchange certainty " &
                    "mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Acceleration_Certainty_Corpus;

   procedure Check_Request_Payment_Certainty_Corpus is
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
         return Request_Payment_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Request_Payment_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Request_Payment_Mutation_Definitely_Not_Applied
         else Request_Payment_Mutation_Outcome_Unknown);

      procedure Check_Response
        (Status      : Flyology.HTTP.Status_Code;
         Code        : String;
         Disposition : Request_Payment_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Value : constant Low_Level.Put_Bucket_Control_Outcome :=
           (if Status = 200
            then (Kind => Low_Level.Bucket_Control_Updated, Status => Status)
            else (Kind => Low_Level.Put_Bucket_Control_Rejected,
                  Status => Status,
                  Error => Error_Response (Code)));
         Result : constant Put_Bucket_Request_Payment_Result :=
           Normalize_Put_Bucket_Request_Payment_Response
             (Value, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Bucket_Request_Payment_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutBucketRequestPayment response normalization mismatch";
         end if;
      end Check_Response;
   begin
      Check_Response
        (200, "", Request_Payment_Mutation_Completed, No_Failure);
      Check_Response
        (400, "MalformedXML",
         Request_Payment_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Response
        (403, "AccessDenied",
         Request_Payment_Mutation_Definitely_Not_Applied,
         Authorization_Failed);
      Check_Response
        (409, "OperationAborted", Request_Payment_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (500, "Unknown", Request_Payment_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Put_Bucket_Control_Outcome :=
              (Kind => Low_Level.Bucket_Control_Updated, Status => 200);
            Result : constant Put_Bucket_Request_Payment_Result :=
              Normalize_Put_Bucket_Request_Payment_Response
                (Value, Admission);
         begin
            if Result.Disposition /= Request_Payment_Mutation_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent PutBucketRequestPayment certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            declare
               Result : constant Put_Bucket_Request_Payment_Result :=
                 Normalize_Put_Bucket_Request_Payment_Failure
                   (Kind, Admission, HTTP_Client.Waiting_Response_Head);
            begin
               if Result.Kind /= Put_Bucket_Request_Payment_Exchange_Failed
                 or else Result.Disposition /=
                   Expected_Disposition (Kind, Admission)
                 or else Result.Failure /= Expected_Failure (Kind)
                 or else Result.Admission /= Admission
                 or else Result.HTTP_Result /= Kind
               then
                  raise Program_Error with
                    "PutBucketRequestPayment exchange certainty mismatch";
               end if;
            end;
         end loop;
      end loop;
   end Check_Request_Payment_Certainty_Corpus;

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
