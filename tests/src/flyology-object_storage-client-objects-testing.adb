with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.Object_Storage.S3.Errors;

package body Flyology.Object_Storage.Client.Objects.Testing is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;

   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.Object_Tagging_Outcome_Kind;
   use type Low_Level.Get_Object_Legal_Hold_Outcome_Kind;
   use type Low_Level.Put_Object_Legal_Hold_Outcome_Kind;
   use type Low_Level.Delete_Objects_Outcome_Kind;

   procedure Check_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Publication_Disposition;
      Failure     : Failure_Reason)
   is
      Value : constant Low_Level.Put_Object_Outcome :=
        (if Status = 200
         then (Kind => Low_Level.Object_Put,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Put_Object_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Conditional_Put_Result := Normalize_Put_Response
        (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Put_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "conditional PUT response normalization corpus mismatch";
      end if;
   end Check_Response;

   procedure Check_Failure
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
      Result : constant Conditional_Put_Result := Normalize_Put_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Put_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "conditional PUT exchange normalization corpus mismatch";
      end if;
   end Check_Failure;

   procedure Check_Put_Certainty_Corpus is
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
      Check_Response (200, "", Published, No_Failure);
      Check_Response
        (412, "PreconditionFailed", Precondition_Failed, No_Failure);
      Check_Response
        (401, "InvalidAccessKeyId", Definitely_Not_Published,
         Authentication_Failed);
      Check_Response
        (403, "AccessDenied", Definitely_Not_Published,
         Authorization_Failed);
      Check_Response
        (400, "InvalidRequest", Definitely_Not_Published, Invalid_Request);
      Check_Response
        (404, "NoSuchBucket", Definitely_Not_Published, Not_Found);
      Check_Response
        (409, "ConditionalRequestConflict", Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Response
        (429, "SlowDown", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Response
        (500, "InternalError", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Response
        (502, "BadGateway", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Response
        (503, "SlowDown", Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Response
        (504, "RequestTimeout", Outcome_Unknown, Unavailable_Or_Retryable);

      --  Status alone, a mismatched modeled code, or an absent code never
      --  supplies retry or conclusive publication evidence.
      Check_Response
        (400, "", Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Response
        (403, "", Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Response
        (404, "", Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Response
        (412, "", Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Response
        (500, "SlowDown", Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Response
        (502, "InternalError", Outcome_Unknown,
         Corrupt_Or_Invalid_Response);
      Check_Response
        (503, "InternalError", Outcome_Unknown,
         Corrupt_Or_Invalid_Response);
      Check_Response
        (504, "SlowDown", Outcome_Unknown, Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Put_Object_Outcome :=
              (Kind   => Low_Level.Object_Put,
               Status => 200,
               Result => (others => <>));
            Result : constant Conditional_Put_Result :=
              Normalize_Put_Response (Value, Admission);
         begin
            if Result.Disposition /= Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent complete-response certainty was conclusive";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Put_Certainty_Corpus;

   procedure Check_Delete_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Deletion_Disposition;
      Failure     : Failure_Reason)
   is
      Value : constant Low_Level.Delete_Object_Outcome :=
        (if Status = 204
         then (Kind => Low_Level.Object_Deleted,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Delete_Object_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Delete_Result := Normalize_Delete_Response
        (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Delete_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "DeleteObject response normalization corpus mismatch";
      end if;
   end Check_Delete_Response;

   procedure Check_Delete_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Deletion_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Deletion_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Definitely_Not_Deleted
         else Deletion_Outcome_Unknown);
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
      Result : constant Delete_Result := Normalize_Delete_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Delete_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "DeleteObject exchange normalization corpus mismatch";
      end if;
   end Check_Delete_Failure;

   procedure Check_Delete_Certainty_Corpus is
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
      Check_Delete_Response
        (204, "", Deletion_Completed, No_Failure);
      Check_Delete_Response
        (412, "PreconditionFailed", Definitely_Not_Deleted, No_Failure);
      Check_Delete_Response
        (401, "InvalidAccessKeyId", Definitely_Not_Deleted,
         Authentication_Failed);
      Check_Delete_Response
        (403, "AccessDenied", Definitely_Not_Deleted,
         Authorization_Failed);
      Check_Delete_Response
        (400, "InvalidRequest", Definitely_Not_Deleted, Invalid_Request);
      Check_Delete_Response
        (404, "NoSuchBucket", Definitely_Not_Deleted, Not_Found);
      Check_Delete_Response
        (404, "NoSuchKey", Definitely_Not_Deleted, Not_Found);
      Check_Delete_Response
        (404, "NoSuchVersion", Definitely_Not_Deleted, Not_Found);
      Check_Delete_Response
        (409, "OperationAborted", Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (429, "SlowDown", Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (500, "InternalError", Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (502, "BadGateway", Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (503, "SlowDown", Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Response
        (504, "RequestTimeout", Deletion_Outcome_Unknown,
         Unavailable_Or_Retryable);

      --  Status without the exact modeled code remains ambiguous.
      Check_Delete_Response
        (400, "", Deletion_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Delete_Response
        (403, "", Deletion_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Delete_Response
        (404, "", Deletion_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Delete_Response
        (412, "", Deletion_Outcome_Unknown, Corrupt_Or_Invalid_Response);
      Check_Delete_Response
        (500, "SlowDown", Deletion_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Delete_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Delete_Certainty_Corpus;

   procedure Check_List_Objects_Response
     (Status  : Flyology.HTTP.Status_Code;
      Code    : String;
      Failure : Failure_Reason)
   is
      Value : constant Low_Level.List_Objects_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Listed,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant List_Objects_Result :=
        Normalize_List_Objects_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= List_Objects_Response_Available
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "ListObjects response normalization mismatch: status=" &
           Status'Image & " code=" & Code & " expected=" &
           Failure'Image & " actual=" & Result.Failure'Image;
      end if;
   end Check_List_Objects_Response;

   procedure Check_List_Objects_Failure
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
      Result : constant List_Objects_Result := Normalize_List_Objects_Failure
        (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= List_Objects_Exchange_Failed
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "ListObjects exchange normalization mismatch";
      end if;
   end Check_List_Objects_Failure;

   procedure Check_List_Objects_Result_Corpus is
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
      Check_List_Objects_Response (200, "", No_Failure);
      Check_List_Objects_Response
        (400, "InvalidArgument", Invalid_Request);
      Check_List_Objects_Response
        (400, "InvalidRequest", Invalid_Request);
      Check_List_Objects_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_List_Objects_Response
        (403, "AccessDenied", Authorization_Failed);
      Check_List_Objects_Response (404, "NoSuchBucket", Not_Found);
      Check_List_Objects_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_List_Objects_Response
        (429, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Objects_Response
        (500, "InternalError", Unavailable_Or_Retryable);
      Check_List_Objects_Response
        (502, "BadGateway", Unavailable_Or_Retryable);
      Check_List_Objects_Response
        (503, "SlowDown", Unavailable_Or_Retryable);
      Check_List_Objects_Response
        (504, "RequestTimeout", Unavailable_Or_Retryable);
      Check_List_Objects_Response (501, "NotImplemented", Invalid_Request);
      Check_List_Objects_Response (400, "", Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.List_Objects_Outcome :=
              (Kind => Low_Level.Listed,
               Status => 200,
               Result => (others => <>));
            Result : constant List_Objects_Result :=
              Normalize_List_Objects_Response (Value, Admission);
         begin
            if Result.Failure /= Corrupt_Or_Invalid_Response then
               raise Program_Error with
                 "inconsistent ListObjects certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_List_Objects_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_List_Objects_Result_Corpus;

   procedure Check_Object_Tagging_Certainty_Corpus is
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
         return Object_Tag_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Object_Tag_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Object_Tag_Mutation_Definitely_Not_Applied
         else Object_Tag_Mutation_Outcome_Unknown);

      function Value
        (Kind   : Low_Level.Object_Tagging_Outcome_Kind;
         Status : Flyology.HTTP.Status_Code;
         Code   : String := "") return Low_Level.Object_Tagging_Outcome is
      begin
         case Kind is
            when Low_Level.Tags_Put =>
               return
                 (Kind => Low_Level.Tags_Put, Status => Status,
                  Result => (others => <>));
            when Low_Level.Tags_Gotten =>
               return
                 (Kind => Low_Level.Tags_Gotten, Status => Status,
                  Result => (others => <>));
            when Low_Level.Tags_Deleted =>
               return
                 (Kind => Low_Level.Tags_Deleted, Status => Status,
                  Result => (others => <>));
            when Low_Level.Object_Tagging_Rejected =>
               return
                 (Kind => Low_Level.Object_Tagging_Rejected,
                  Status => Status, Error => Error_Response (Code));
         end case;
      end Value;

      procedure Check_Put_Response
        (Item        : Low_Level.Object_Tagging_Outcome;
         Disposition : Object_Tag_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Result : constant Put_Object_Tagging_Result :=
           Normalize_Put_Object_Tagging_Response
             (Item, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Object_Tagging_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutObjectTagging response normalization mismatch";
         end if;
      end Check_Put_Response;

      procedure Check_Get_Response
        (Item    : Low_Level.Object_Tagging_Outcome;
         Failure : Failure_Reason)
      is
         Result : constant Get_Object_Tagging_Result :=
           Normalize_Get_Object_Tagging_Response
             (Item, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Object_Tagging_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetObjectTagging response normalization mismatch";
         end if;
      end Check_Get_Response;

      procedure Check_Delete_Response
        (Item        : Low_Level.Object_Tagging_Outcome;
         Disposition : Object_Tag_Mutation_Disposition;
         Failure     : Failure_Reason)
      is
         Result : constant Delete_Object_Tagging_Result :=
           Normalize_Delete_Object_Tagging_Response
             (Item, HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Delete_Object_Tagging_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "DeleteObjectTagging response normalization mismatch";
         end if;
      end Check_Delete_Response;

      procedure Check_Failure
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
      is
         Put_Result : constant Put_Object_Tagging_Result :=
           Normalize_Put_Object_Tagging_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
         Get_Result : constant Get_Object_Tagging_Result :=
           Normalize_Get_Object_Tagging_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
         Delete_Result : constant Delete_Object_Tagging_Result :=
           Normalize_Delete_Object_Tagging_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
      begin
         if Put_Result.Kind /= Put_Object_Tagging_Exchange_Failed
           or else Put_Result.Disposition /=
             Expected_Disposition (Kind, Admission)
           or else Put_Result.Failure /= Expected_Failure (Kind)
           or else Put_Result.Admission /= Admission
           or else Put_Result.HTTP_Result /= Kind
           or else Get_Result.Kind /= Get_Object_Tagging_Exchange_Failed
           or else Get_Result.Failure /= Expected_Failure (Kind)
           or else Get_Result.Admission /= Admission
           or else Get_Result.HTTP_Result /= Kind
           or else Delete_Result.Kind /=
             Delete_Object_Tagging_Exchange_Failed
           or else Delete_Result.Disposition /=
             Expected_Disposition (Kind, Admission)
           or else Delete_Result.Failure /= Expected_Failure (Kind)
           or else Delete_Result.Admission /= Admission
           or else Delete_Result.HTTP_Result /= Kind
         then
            raise Program_Error with
              "object-tagging exchange normalization mismatch";
         end if;
      end Check_Failure;
   begin
      Check_Put_Response
        (Value (Low_Level.Tags_Put, 200), Object_Tag_Mutation_Completed,
         No_Failure);
      Check_Put_Response
        (Value (Low_Level.Object_Tagging_Rejected, 400, "InvalidTag"),
         Object_Tag_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Put_Response
        (Value (Low_Level.Object_Tagging_Rejected, 404, "NoSuchVersion"),
         Object_Tag_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Put_Response
        (Value (Low_Level.Object_Tagging_Rejected, 409,
                "OperationAborted"),
         Object_Tag_Mutation_Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Put_Response
        (Value (Low_Level.Object_Tagging_Rejected, 500, "SlowDown"),
         Object_Tag_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      Check_Get_Response (Value (Low_Level.Tags_Gotten, 200), No_Failure);
      Check_Get_Response
        (Value (Low_Level.Object_Tagging_Rejected, 401,
                "InvalidAccessKeyId"),
         Authentication_Failed);
      Check_Get_Response
        (Value (Low_Level.Object_Tagging_Rejected, 403, "AccessDenied"),
         Authorization_Failed);
      Check_Get_Response
        (Value (Low_Level.Object_Tagging_Rejected, 404, "NoSuchKey"),
         Not_Found);

      Check_Delete_Response
        (Value (Low_Level.Tags_Deleted, 204),
         Object_Tag_Mutation_Completed, No_Failure);
      Check_Delete_Response
        (Value (Low_Level.Object_Tagging_Rejected, 404, "NoSuchBucket"),
         Object_Tag_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Delete_Response
        (Value (Low_Level.Object_Tagging_Rejected, 500, "InternalError"),
         Object_Tag_Mutation_Outcome_Unknown, Unavailable_Or_Retryable);
      Check_Delete_Response
        (Value (Low_Level.Object_Tagging_Rejected, 403),
         Object_Tag_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Put_Result : constant Put_Object_Tagging_Result :=
              Normalize_Put_Object_Tagging_Response
                (Value (Low_Level.Tags_Put, 200), Admission);
            Get_Result : constant Get_Object_Tagging_Result :=
              Normalize_Get_Object_Tagging_Response
                (Value (Low_Level.Tags_Gotten, 200), Admission);
            Delete_Result : constant Delete_Object_Tagging_Result :=
              Normalize_Delete_Object_Tagging_Response
                (Value (Low_Level.Tags_Deleted, 204), Admission);
         begin
            if Put_Result.Disposition /=
                Object_Tag_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Get_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Delete_Result.Disposition /=
                Object_Tag_Mutation_Outcome_Unknown
              or else Delete_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent object-tagging certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Object_Tagging_Certainty_Corpus;

   procedure Check_Legal_Hold_Certainty_Corpus is
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
         return Legal_Hold_Mutation_Disposition is
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Legal_Hold_Mutation_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Legal_Hold_Mutation_Definitely_Not_Applied
         else Legal_Hold_Mutation_Outcome_Unknown);

      function Get_Value
        (Status : Flyology.HTTP.Status_Code;
         Code   : String := "")
         return Low_Level.Get_Object_Legal_Hold_Outcome is
        (if Status = 200
         then (Kind => Low_Level.Object_Legal_Hold_Found,
               Status => Status, Legal_Hold => (others => <>))
         else (Kind => Low_Level.Get_Object_Legal_Hold_Rejected,
               Status => Status, Error => Error_Response (Code)));

      function Put_Value
        (Status : Flyology.HTTP.Status_Code;
         Code   : String := "")
         return Low_Level.Put_Object_Legal_Hold_Outcome is
        (if Status = 200
         then (Kind => Low_Level.Object_Legal_Hold_Updated,
               Status => Status, Result => (others => <>))
         else (Kind => Low_Level.Put_Object_Legal_Hold_Rejected,
               Status => Status, Error => Error_Response (Code)));

      procedure Check_Get_Response
        (Status : Flyology.HTTP.Status_Code;
         Code : String;
         Failure : Failure_Reason)
      is
         Result : constant Get_Legal_Hold_Result :=
           Normalize_Get_Legal_Hold_Response
             (Get_Value (Status, Code), HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Get_Legal_Hold_Response_Available
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "GetObjectLegalHold response normalization mismatch";
         end if;
      end Check_Get_Response;

      procedure Check_Put_Response
        (Status : Flyology.HTTP.Status_Code;
         Code : String;
         Disposition : Legal_Hold_Mutation_Disposition;
         Failure : Failure_Reason)
      is
         Result : constant Put_Legal_Hold_Result :=
           Normalize_Put_Legal_Hold_Response
             (Put_Value (Status, Code), HTTP_Client.Response_Observed);
      begin
         if Result.Kind /= Put_Legal_Hold_Response_Available
           or else Result.Disposition /= Disposition
           or else Result.Failure /= Failure
           or else Result.Admission /= HTTP_Client.Response_Observed
         then
            raise Program_Error with
              "PutObjectLegalHold response normalization mismatch";
         end if;
      end Check_Put_Response;

      procedure Check_Failure
        (Kind      : HTTP_Client.Exchange_Result_Kind;
         Admission : HTTP_Client.Admission_Certainty)
      is
         Get_Result : constant Get_Legal_Hold_Result :=
           Normalize_Get_Legal_Hold_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
         Put_Result : constant Put_Legal_Hold_Result :=
           Normalize_Put_Legal_Hold_Failure
             (Kind, Admission, HTTP_Client.Waiting_Response_Head);
      begin
         if Get_Result.Kind /= Get_Legal_Hold_Exchange_Failed
           or else Get_Result.Failure /= Expected_Failure (Kind)
           or else Get_Result.Admission /= Admission
           or else Get_Result.HTTP_Result /= Kind
           or else Put_Result.Kind /= Put_Legal_Hold_Exchange_Failed
           or else Put_Result.Disposition /=
             Expected_Disposition (Kind, Admission)
           or else Put_Result.Failure /= Expected_Failure (Kind)
           or else Put_Result.Admission /= Admission
           or else Put_Result.HTTP_Result /= Kind
         then
            raise Program_Error with
              "Object Legal Hold exchange normalization mismatch";
         end if;
      end Check_Failure;
   begin
      Check_Get_Response (200, "", No_Failure);
      Check_Get_Response
        (401, "InvalidAccessKeyId", Authentication_Failed);
      Check_Get_Response (403, "AccessDenied", Authorization_Failed);
      Check_Get_Response (404, "NoSuchVersion", Not_Found);
      Check_Get_Response
        (409, "OperationAborted", Unavailable_Or_Retryable);
      Check_Get_Response (403, "", Corrupt_Or_Invalid_Response);

      Check_Put_Response
        (200, "", Legal_Hold_Mutation_Completed, No_Failure);
      Check_Put_Response
        (400, "MalformedXML",
         Legal_Hold_Mutation_Definitely_Not_Applied, Invalid_Request);
      Check_Put_Response
        (403, "AccessDenied",
         Legal_Hold_Mutation_Definitely_Not_Applied, Authorization_Failed);
      Check_Put_Response
        (404, "NoSuchVersion",
         Legal_Hold_Mutation_Definitely_Not_Applied, Not_Found);
      Check_Put_Response
        (409, "OperationAborted", Legal_Hold_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (500, "InternalError", Legal_Hold_Mutation_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Put_Response
        (403, "", Legal_Hold_Mutation_Outcome_Unknown,
         Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Get_Result : constant Get_Legal_Hold_Result :=
              Normalize_Get_Legal_Hold_Response
                (Get_Value (200), Admission);
            Put_Result : constant Put_Legal_Hold_Result :=
              Normalize_Put_Legal_Hold_Response
                (Put_Value (200), Admission);
         begin
            if Get_Result.Failure /= Corrupt_Or_Invalid_Response
              or else Put_Result.Disposition /=
                Legal_Hold_Mutation_Outcome_Unknown
              or else Put_Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent Object Legal Hold certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Legal_Hold_Certainty_Corpus;

   procedure Check_Legal_Hold_Pre_Admission_Rejection
     (Client   : not null access Flyology.HTTP.Client.Client;
      Prepared : Flyology.Object_Storage.Client.Low_Level.Prepared_Request;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline)
   is
      --  Derived capacity: test parent, rejected HTTP exchange, and the
      --  otherwise possible transport child bound this negative oracle.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Wrong : aliased Low_Level.Prepared_Request := Prepared;
      Get_Operation : aliased Get_Legal_Hold_Operation
        (Set'Access, Client, null);
      Put_Operation : aliased Put_Legal_Hold_Operation
        (Set'Access, Client, null);
      Get_Rejected : Boolean := False;
      Put_Rejected : Boolean := False;
   begin
      begin
         Low_Level.Get_Object_Legal_Hold
           (Client, Wrong'Access, Get_Operation'Access, Deadline, null,
            Get_Operation.Child);
      exception
         when Low_Level.Invalid_Request => Get_Rejected := True;
      end;
      begin
         Low_Level.Put_Object_Legal_Hold
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
           "Object Legal Hold wrong prepared operation crossed admission";
      end if;
   end Check_Legal_Hold_Pre_Admission_Rejection;

   procedure Set_Response_Limit
     (Operation : in out Get_Legal_Hold_Operation;
      Maximum   : Natural) is
   begin
      Operation.Response_Limit := Maximum;
   end Set_Response_Limit;

   procedure Set_Response_Limit
     (Operation : in out Put_Legal_Hold_Operation;
      Maximum   : Natural) is
   begin
      Operation.Response_Limit := Maximum;
   end Set_Response_Limit;

   procedure Check_Delete_Objects_Response
     (Status      : Flyology.HTTP.Status_Code;
      Code        : String;
      Disposition : Delete_Objects_Disposition;
      Failure     : Failure_Reason)
   is
      Value : constant Low_Level.Delete_Objects_Outcome :=
        (if Status = 200 and then Code'Length = 0
         then (Kind => Low_Level.Objects_Deleted,
               Status => Status,
               Result => (others => <>))
         else (Kind => Low_Level.Delete_Objects_Rejected,
               Status => Status,
               Error =>
                 (Code       => US.To_Unbounded_String (Code),
                  Message    => US.Null_Unbounded_String,
                  Resource   => US.Null_Unbounded_String,
                  Request_ID => US.Null_Unbounded_String,
                  Host_ID    => US.Null_Unbounded_String)));
      Result : constant Delete_Objects_Result :=
        Normalize_Delete_Objects_Response
          (Value, HTTP_Client.Response_Observed);
   begin
      if Result.Kind /= Delete_Objects_Response_Available
        or else Result.Disposition /= Disposition
        or else Result.Failure /= Failure
        or else Result.Admission /= HTTP_Client.Response_Observed
      then
         raise Program_Error with
           "DeleteObjects response normalization mismatch";
      end if;
   end Check_Delete_Objects_Response;

   procedure Check_Delete_Objects_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
   is
      Expected_Disposition : constant Delete_Objects_Disposition :=
        (if Kind = HTTP_Client.Cancelled
           and then Admission = HTTP_Client.Not_Admitted
         then Batch_Cancelled_Before_Admission
         elsif Admission = HTTP_Client.Not_Admitted
         then Batch_Definitely_Not_Processed
         else Batch_Outcome_Unknown);
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
      Result : constant Delete_Objects_Result :=
        Normalize_Delete_Objects_Failure
          (Kind, Admission, HTTP_Client.Receiving_Response_Body);
   begin
      if Result.Kind /= Delete_Objects_Exchange_Failed
        or else Result.Disposition /= Expected_Disposition
        or else Result.Failure /= Expected_Failure
        or else Result.Admission /= Admission
        or else Result.HTTP_Result /= Kind
      then
         raise Program_Error with
           "DeleteObjects exchange normalization mismatch";
      end if;
   end Check_Delete_Objects_Failure;

   procedure Check_Delete_Objects_Certainty_Corpus is
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
      Check_Delete_Objects_Response
        (200, "", Batch_Processed, No_Failure);
      Check_Delete_Objects_Response
        (400, "BadDigest", Batch_Definitely_Not_Processed, Invalid_Request);
      Check_Delete_Objects_Response
        (400, "MalformedXML", Batch_Definitely_Not_Processed,
         Invalid_Request);
      Check_Delete_Objects_Response
        (401, "InvalidAccessKeyId", Batch_Definitely_Not_Processed,
         Authentication_Failed);
      Check_Delete_Objects_Response
        (403, "AccessDenied", Batch_Definitely_Not_Processed,
         Authorization_Failed);
      Check_Delete_Objects_Response
        (404, "NoSuchBucket", Batch_Definitely_Not_Processed, Not_Found);
      Check_Delete_Objects_Response
        (501, "NotImplemented", Batch_Definitely_Not_Processed,
         Invalid_Request);
      Check_Delete_Objects_Response
        (409, "OperationAborted", Batch_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Objects_Response
        (500, "InternalError", Batch_Outcome_Unknown,
         Unavailable_Or_Retryable);
      Check_Delete_Objects_Response
        (400, "", Batch_Outcome_Unknown, Corrupt_Or_Invalid_Response);

      for Admission in
        HTTP_Client.Not_Admitted .. HTTP_Client.Possibly_Admitted
      loop
         declare
            Value : constant Low_Level.Delete_Objects_Outcome :=
              (Kind => Low_Level.Objects_Deleted,
               Status => 200,
               Result => (others => <>));
            Result : constant Delete_Objects_Result :=
              Normalize_Delete_Objects_Response (Value, Admission);
         begin
            if Result.Disposition /= Batch_Outcome_Unknown
              or else Result.Failure /= Corrupt_Or_Invalid_Response
            then
               raise Program_Error with
                 "inconsistent DeleteObjects certainty was accepted";
            end if;
         end;
      end loop;

      for Kind of Failure_Kinds loop
         for Admission in HTTP_Client.Admission_Certainty loop
            Check_Delete_Objects_Failure (Kind, Admission);
         end loop;
      end loop;
   end Check_Delete_Objects_Certainty_Corpus;

end Flyology.Object_Storage.Client.Objects.Testing;
