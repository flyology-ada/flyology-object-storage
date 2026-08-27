with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Intelligent_Tiering;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

procedure S3_Put_Bucket_Intelligent_Tiering_Configuration_Qualification is
   package Environment renames Ada.Environment_Variables;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Client renames Flyology.Object_Storage.Client;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Intelligent_Tiering renames
     Flyology.Object_Storage.S3.Intelligent_Tiering;
   package Operations renames Flyology.Operations;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Client.Failure_Reason;
   use all type
     Buckets.Intelligent_Tiering_Mutation_Disposition;
   use type Buckets.Put_Bucket_Intelligent_Tiering_Result_Kind;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;

   subtype Mutation_Disposition is
     Buckets.Intelligent_Tiering_Mutation_Disposition;
   Definite_Rejection : constant Mutation_Disposition :=
     Intelligent_Tiering_Mutation_Definitely_Not_Applied;
   Unknown_Outcome : constant Mutation_Disposition :=
     Intelligent_Tiering_Mutation_Outcome_Unknown;

   Port : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_PORT");
   Case_ID : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_CASE");
   Lane : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_LANE");
   Bucket : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_BUCKET");
   Identifier : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_INPUT_ID");
   Expected_Bucket_Owner : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_EXPECTED_BUCKET_OWNER");
   Expected : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_EXPECTED");

   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("http://127.0.0.1:" & Port);
   Identity : constant Low_Level.Credentials :=
     --  AWS SigV4 published-example identity retained by the signed socket
     --  corpus; changing it invalidates the request-signing oracle.
     Low_Level.Make_Credentials
       ("AKIAIOSFODNN7EXAMPLE",
        "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   Parameters : constant
     Low_Level.Put_Bucket_Intelligent_Tiering_Configuration_Parameters :=
       (ID                    => US.To_Unbounded_String (Identifier),
        Expected_Bucket_Owner =>
          US.To_Unbounded_String (Expected_Bucket_Owner));
   --  Five seconds is the established local socket-corpus watchdog, not a
   --  public client default.
   Socket_Timeout : constant Duration := 5.0;

   function Limit (Name : String; Default : Positive) return Positive is
      Variable : constant String := "FLYOLOGY_S3_QUALIFICATION_" & Name;
   begin
      return
        (if Environment.Exists (Variable)
         then Positive'Value (Environment.Value (Variable))
         else Default);
   end Limit;

   Limits : constant XML.Parse_Limits :=
     (Maximum_Document_Bytes =>
        Limit
          ("MAXIMUM_DOCUMENT_BYTES",
           XML.Default_Limits.Maximum_Document_Bytes),
      Maximum_Depth =>
        Limit ("MAXIMUM_DEPTH", XML.Default_Limits.Maximum_Depth),
      Maximum_Elements =>
        Limit ("MAXIMUM_ELEMENTS", XML.Default_Limits.Maximum_Elements),
      Maximum_Text_Bytes =>
        Limit
          ("MAXIMUM_TEXT_BYTES", XML.Default_Limits.Maximum_Text_Bytes));

   Document : constant String :=
     "<IntelligentTieringConfiguration xmlns=""http://s3.amazonaws.com/" &
     "doc/2006-03-01/""><Id>" & XML.Escape_Text (Identifier) &
     "</Id><Status>Enabled</Status><Tiering><Days>90</Days>" &
     "<AccessTier>ARCHIVE_ACCESS</AccessTier></Tiering>" &
     "</IntelligentTieringConfiguration>";
   Value : constant
     Intelligent_Tiering.Intelligent_Tiering_Configuration :=
       Intelligent_Tiering.Parse (Document, Limits);

   --  Every case is serial. One HTTP slot is the derived minimum and makes a
   --  leaked exchange observable; it is not production policy.
   HTTP : aliased HTTP_Client.Client (Capacity => 1);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Case_ID & ": " & Message;
      end if;
   end Require;

   procedure Check_Result
     (Result : Buckets.Put_Bucket_Intelligent_Tiering_Result)
   is
      procedure Check_Rejection (Failure : Client.Failure_Reason) is
      begin
         Require
           (Result.Kind =
              Buckets.Put_Bucket_Intelligent_Tiering_Response_Available
            and then Result.Disposition = Definite_Rejection
            and then Result.Failure = Failure,
            "typed rejection mismatch");
      end Check_Rejection;
   begin
      if Expected = "success" then
         Require
           (Result.Kind =
              Buckets.Put_Bucket_Intelligent_Tiering_Response_Available
            and then Result.Disposition =
              Buckets.
                Intelligent_Tiering_Mutation_Completed
            and then Result.Failure = Client.No_Failure
            and then Result.Response.Kind =
              Low_Level.Bucket_Control_Updated,
            "typed success mismatch");
      elsif Expected = "invalid_request" then
         Check_Rejection (Client.Invalid_Request);
      elsif Expected = "authentication_failed" then
         Check_Rejection (Client.Authentication_Failed);
      elsif Expected = "authorization_failed" then
         Check_Rejection (Client.Authorization_Failed);
      elsif Expected = "not_found" then
         Check_Rejection (Client.Not_Found);
      elsif Expected = "response_invalid" then
         Require
           (Result.Kind =
              Buckets.Put_Bucket_Intelligent_Tiering_Exchange_Failed
            and then Result.Disposition =
              Unknown_Outcome
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Invalid,
            "typed invalid-response mismatch");
      elsif Expected = "response_sink_failed" then
         Require
           (Result.Kind =
              Buckets.Put_Bucket_Intelligent_Tiering_Exchange_Failed
            and then Result.Disposition =
              Unknown_Outcome
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Sink_Failed,
            "typed bounded-sink mismatch");
      else
         raise Program_Error with Case_ID & ": unknown expected result";
      end if;
   end Check_Result;

begin
   HTTP_Client.Configure (HTTP, Origin);
   if Lane = "low_level" then
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Bucket_Intelligent_Tiering_Configuration
             (Origin, Low_Level.Path_Style, Bucket, Value, Parameters,
              Identity, "us-east-1", "20130524T000000Z", Limits);
         Result : constant Low_Level.Put_Bucket_Control_Outcome :=
           Low_Level.Execute_Put_Bucket_Intelligent_Tiering_Configuration
             (HTTP, Prepared, Socket_Timeout, null, Limits);
      begin
         Require
           (Expected = "success"
            and then Result.Kind = Low_Level.Bucket_Control_Updated,
            "low-level result mismatch");
      end;
   elsif Lane = "synchronous" or else Lane = "invalid_xml" then
      Check_Result
        (Buckets.Set_Intelligent_Tiering_Configuration
           (HTTP, Origin, Bucket, Value, Parameters, Identity, "us-east-1",
            Low_Level.Path_Style, Socket_Timeout, null, Limits));
   elsif Lane = "composable" then
      declare
         --  Derived owner stack: provider, HTTP exchange, transport child.
         Set : aliased Operations.Completion_Set (3);
         Operation : Buckets.Put_Bucket_Intelligent_Tiering_Operation :=
           Buckets.Set_Intelligent_Tiering_Configuration
             (Set'Access, HTTP'Access, Origin, Bucket, Value, Parameters,
              Identity, HTTP_Client.Deadline_After (Socket_Timeout),
              "us-east-1", Low_Level.Path_Style, Limits, null);
         Result : Buckets.Put_Bucket_Intelligent_Tiering_Result;
      begin
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Check_Result (Result);
      end;
   elsif Lane = "restart" then
      declare
         Set : aliased Operations.Completion_Set (3);
         Operation : Buckets.Put_Bucket_Intelligent_Tiering_Operation :=
           Buckets.Set_Intelligent_Tiering_Configuration
             (Set'Access, HTTP'Access, Origin, Bucket, Value, Parameters,
              Identity, HTTP_Client.Deadline_After (Socket_Timeout),
              "us-east-1", Low_Level.Path_Style, Limits, null);
         Result : Buckets.Put_Bucket_Intelligent_Tiering_Result;
      begin
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Require
           (Result.Kind =
              Buckets.Put_Bucket_Intelligent_Tiering_Response_Available
            and then Result.Disposition =
              Buckets.
                Intelligent_Tiering_Mutation_Completed,
            "restart first result mismatch");
         Buckets.Set_Intelligent_Tiering_Configuration
           (HTTP'Access, Origin, Bucket & "-second", Value, Parameters,
            Identity, HTTP_Client.Deadline_After (Socket_Timeout),
            "us-east-1", Low_Level.Path_Style, Limits, null, Operation);
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Check_Result (Result);
      end;
   else
      raise Program_Error with Case_ID & ": unknown call lane";
   end if;
   HTTP_Client.Shutdown (HTTP);
   Ada.Text_IO.Put_Line
     ("PutBucketIntelligentTieringConfiguration signed qualification " &
      Case_ID & ": OK");
exception
   when others =>
      HTTP_Client.Shutdown (HTTP);
      raise;
end S3_Put_Bucket_Intelligent_Tiering_Configuration_Qualification;
