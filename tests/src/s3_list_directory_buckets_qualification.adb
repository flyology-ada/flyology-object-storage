with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;
with S3_Paginated_REST_XML_Read_Qualification;

procedure S3_List_Directory_Buckets_Qualification is
   package Environment renames Ada.Environment_Variables;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Client renames Flyology.Object_Storage.Client;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Client.Failure_Reason;
   use type Buckets.List_Directory_Buckets_Result_Kind;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.List_Directory_Buckets_Outcome_Kind;

   type Input_Values is record
      Parameters : Low_Level.List_Directory_Buckets_Parameters;
   end record;

   function Inputs return Input_Values is
      Has_Continuation_Token : constant Boolean :=
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN");
      Has_Max_Directory_Buckets : constant Boolean :=
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_MAX_DIRECTORY_BUCKETS");
      Max_Directory_Buckets : constant Natural :=
        (if Has_Max_Directory_Buckets
         then Natural'Value
           (Environment.Value
              ("FLYOLOGY_S3_QUALIFICATION_INPUT_MAX_DIRECTORY_BUCKETS"))
         else 0);
   begin
      return
        (Parameters =>
           (Continuation_Token =>
              US.To_Unbounded_String
                (Environment.Value
                   ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN", "")),
            Has_Continuation_Token => Has_Continuation_Token,
            Max_Directory_Buckets => Max_Directory_Buckets,
            Has_Max_Directory_Buckets => Has_Max_Directory_Buckets));
   end Inputs;

   procedure Require
     (Condition : Boolean;
      Context   : String;
      Message   : String) is
   begin
      if not Condition then
         raise Program_Error with Context & ": " & Message;
      end if;
   end Require;

   procedure Check_Low_Level
     (Value          : Low_Level.List_Directory_Buckets_Outcome;
      Expected       : String;
      Expected_Value : String;
      Context        : String) is
   begin
      if Expected = "success" then
         Require
           (Value.Kind = Low_Level.Directory_Buckets_Listed,
            Context, "typed page kind mismatch");
         if Expected_Value'Length = 0 then
            Require
              (Value.Result.Buckets.Is_Empty,
               Context, "expected empty directory-bucket page");
         else
            Require
              (not Value.Result.Buckets.Is_Empty
               and then US.To_String
                 (Value.Result.Buckets.First_Element.Name) = Expected_Value,
               Context, "first directory-bucket name mismatch");
         end if;
      elsif Expected = "invalid_request" then
         Require
           (Value.Kind = Low_Level.List_Directory_Buckets_Rejected,
            Context, "expected structured rejection");
      else
         raise Program_Error with Context & ": unknown low-level result";
      end if;
   end Check_Low_Level;

   procedure Check_Result
     (Result         : Buckets.List_Directory_Buckets_Result;
      Expected       : String;
      Expected_Value : String;
      Context        : String) is
   begin
      if Expected = "success" then
         Require
           (Result.Kind =
              Buckets.List_Directory_Buckets_Response_Available
            and then Result.Failure = Client.No_Failure,
            Context, "typed success mismatch");
         Check_Low_Level
           (Result.Response, Expected, Expected_Value, Context);
      elsif Expected = "invalid_request" then
         Require
           (Result.Kind =
              Buckets.List_Directory_Buckets_Response_Available
            and then Result.Failure = Client.Invalid_Request,
            Context, "typed rejection mismatch");
      elsif Expected = "response_invalid" then
         Require
           (Result.Kind = Buckets.List_Directory_Buckets_Exchange_Failed
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Invalid,
            Context, "typed invalid-response mismatch");
      elsif Expected = "response_sink_failed" then
         Require
           (Result.Kind = Buckets.List_Directory_Buckets_Exchange_Failed
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Sink_Failed,
            Context, "typed bounded-sink mismatch");
      elsif Expected = "cancelled" then
         Require
           (Result.Kind = Buckets.List_Directory_Buckets_Exchange_Failed
            and then Result.Failure = Client.Cancelled
            and then Result.HTTP_Result = HTTP_Client.Cancelled,
            Context, "typed cancellation mismatch");
      else
         raise Program_Error with Context & ": unknown expected result";
      end if;
   end Check_Result;

   procedure Check_Pre_Admission_Rejection
     (HTTP              : aliased in out HTTP_Client.Client;
      Origin            : Flyology.HTTP.Origin;
      Value             : Input_Values;
      Identity          : Low_Level.Credentials;
      Region            : String;
      Signing_Timestamp : String;
      Timeout           : Duration;
      Limits            : XML.Parse_Limits;
      Collection_Limit  : Positive)
   is
      pragma Unreferenced (Value);
      Wrong_Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_List_Buckets
          (Origin, Low_Level.Path_Style,
           Low_Level.List_Buckets_Parameters'(others => <>), Identity,
           Region, Signing_Timestamp);
   begin
      declare
         Unexpected : constant Low_Level.List_Directory_Buckets_Outcome :=
           Low_Level.Execute_List_Directory_Buckets
             (HTTP, Wrong_Prepared, Timeout, null, Limits,
              Collection_Limit);
         pragma Unreferenced (Unexpected);
      begin
         raise Program_Error with
           "mismatched prepared operation entered the HTTP call";
      end;
   exception
      when Low_Level.Invalid_Request =>
         null;
   end Check_Pre_Admission_Rejection;

   procedure Execute_Low_Level
     (HTTP              : aliased in out HTTP_Client.Client;
      Origin            : Flyology.HTTP.Origin;
      Value             : Input_Values;
      Identity          : Low_Level.Credentials;
      Region            : String;
      Signing_Timestamp : String;
      Timeout           : Duration;
      Limits            : XML.Parse_Limits;
      Collection_Limit  : Positive;
      Expected          : String;
      Expected_Value    : String)
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_List_Directory_Buckets
          (Origin, Value.Parameters, Identity, Region, Signing_Timestamp);
      Result : constant Low_Level.List_Directory_Buckets_Outcome :=
        Low_Level.Execute_List_Directory_Buckets
          (HTTP, Prepared, Timeout, null, Limits, Collection_Limit);
   begin
      Check_Low_Level
        (Result, Expected, Expected_Value, "low-level");
   end Execute_Low_Level;

   procedure Execute_Synchronous
     (HTTP             : aliased in out HTTP_Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Value            : Input_Values;
      Identity         : Low_Level.Credentials;
      Region           : String;
      Timeout          : Duration;
      Limits           : XML.Parse_Limits;
      Collection_Limit : Positive;
      Result           : out Buckets.List_Directory_Buckets_Result) is
   begin
      Result :=
        Buckets.List_Directory_Buckets
          (HTTP, Origin, Value.Parameters, Identity, Region, Timeout, null,
           Limits, Collection_Limit);
   end Execute_Synchronous;

   function Start
     (Set              : not null access
        Flyology.Operations.Completion_Set'Class;
      HTTP             : not null access HTTP_Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Value            : Input_Values;
      Identity         : Low_Level.Credentials;
      Deadline         : HTTP_Client.Monotonic_Deadline;
      Region           : String;
      Limits           : XML.Parse_Limits;
      Collection_Limit : Positive)
      return Buckets.List_Directory_Buckets_Operation is
     (Buckets.List_Directory_Buckets
        (Set, HTTP, Origin, Value.Parameters, Identity, Deadline, Region,
         Limits, Collection_Limit, null));

   procedure Restart
     (HTTP             : not null access HTTP_Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Value            : Input_Values;
      Identity         : Low_Level.Credentials;
      Deadline         : HTTP_Client.Monotonic_Deadline;
      Region           : String;
      Limits           : XML.Parse_Limits;
      Collection_Limit : Positive;
      Operation        : in out Buckets.List_Directory_Buckets_Operation) is
   begin
      Buckets.List_Directory_Buckets
        (HTTP, Origin, Value.Parameters, Identity, Deadline, Region, Limits,
         Collection_Limit, null, Operation);
   end Restart;

   procedure Request_Cancellation
     (Operation : in out Buckets.List_Directory_Buckets_Operation) is
   begin
      Flyology.Operations.Cancel (Operation);
   end Request_Cancellation;

   package Qualification is new S3_Paginated_REST_XML_Read_Qualification
     (Operation_Name       => "ListDirectoryBuckets",
      Inputs_Type          => Input_Values,
      Result_Type          => Buckets.List_Directory_Buckets_Result,
      Operation_Type       => Buckets.List_Directory_Buckets_Operation,
      Inputs               => Inputs,
      Check_Pre_Admission_Rejection => Check_Pre_Admission_Rejection,
      Execute_Low_Level    => Execute_Low_Level,
      Execute_Synchronous  => Execute_Synchronous,
      Start                => Start,
      Restart              => Restart,
      Finish               => Buckets.Finish,
      Request_Cancellation => Request_Cancellation,
      Check_Result         => Check_Result);
begin
   Qualification.Run;
end S3_List_Directory_Buckets_Qualification;
