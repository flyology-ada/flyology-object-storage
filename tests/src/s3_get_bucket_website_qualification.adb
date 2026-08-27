with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Website;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

procedure S3_Get_Bucket_Website_Qualification is
   package Environment renames Ada.Environment_Variables;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Client renames Flyology.Object_Storage.Client;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Website renames Flyology.Object_Storage.S3.Website;
   package Operations renames Flyology.Operations;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Client.Failure_Reason;
   use type Buckets.Get_Bucket_Website_Result_Kind;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Website.Protocol;

   Port : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_PORT");
   Case_ID : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_CASE");
   Lane : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_LANE");
   Bucket : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_BUCKET");
   Expected_Bucket_Owner : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_EXPECTED_BUCKET_OWNER");
   Expected : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_EXPECTED");
   Expected_Value : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_EXPECTED_VALUE", "");

   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("http://127.0.0.1:" & Port);
   Identity : constant Low_Level.Credentials :=
     --  AWS SigV4 published-example identity retained by the signed socket
     --  corpus; changing it invalidates the request-signing oracle.
     Low_Level.Make_Credentials
       ("AKIAIOSFODNN7EXAMPLE",
        "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   Parameters : constant Low_Level.Get_Bucket_Control_Parameters :=
     (Expected_Bucket_Owner =>
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

   --  Every case is serial. One HTTP slot is the derived minimum and makes a
   --  leaked exchange observable; it is not production policy.
   HTTP : aliased HTTP_Client.Client (Capacity => 1);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Case_ID & ": " & Message;
      end if;
   end Require;

   procedure Check_Success
     (Configuration : Website.Website_Configuration) is
   begin
      if Expected_Value = "empty" then
         Require
           (not Configuration.Redirect_All.Is_Set
            and then not Configuration.Index.Is_Set
            and then not Configuration.Error.Is_Set
            and then not Configuration.Routes.Is_Set,
            "empty website configuration mismatch");
      else
         Require
           (Configuration.Index.Is_Set
            and then US.To_String (Configuration.Index.Suffix) =
              Expected_Value,
            "website index suffix mismatch");
      end if;

      if Expected_Value = "synchronous-index" then
         declare
            First : constant Website.Routing_Rule :=
              Configuration.Routes.Rules.Element (1);
            Second : constant Website.Routing_Rule :=
              Configuration.Routes.Rules.Element (2);
         begin
            Require
              (Configuration.Redirect_All.Is_Set
               and then US.To_String
                 (Configuration.Redirect_All.Host_Name) = "all.example"
               and then Configuration.Redirect_All.Scheme.Is_Set
               and then Configuration.Redirect_All.Scheme.Value =
                 Website.HTTPS
               and then Configuration.Error.Is_Set
               and then US.To_String (Configuration.Error.Key) = "error.html"
               and then Configuration.Routes.Is_Set
               and then Natural (Configuration.Routes.Rules.Length) = 2
               and then First.Condition.Is_Set
               and then First.Condition.HTTP_Error_Code.Is_Set
               and then US.To_String
                 (First.Condition.HTTP_Error_Code.Value) = "404"
               and then First.Redirect.Host_Name.Is_Set
               and then US.To_String (First.Redirect.Host_Name.Value) =
                 "errors.example"
               and then First.Redirect.Scheme.Is_Set
               and then First.Redirect.Scheme.Value = Website.HTTP
               and then First.Redirect.Replace_Key.Is_Set
               and then US.To_String (First.Redirect.Replace_Key.Value) =
                 "missing.html"
               and then Second.Condition.Key_Prefix.Is_Set
               and then US.To_String
                 (Second.Condition.Key_Prefix.Value) = "docs/"
               and then Second.Redirect.HTTP_Redirect_Code.Is_Set
               and then US.To_String
                 (Second.Redirect.HTTP_Redirect_Code.Value) = "302"
               and then Second.Redirect.Replace_Key_Prefix.Is_Set
               and then US.To_String
                 (Second.Redirect.Replace_Key_Prefix.Value) = "archive/",
               "complete typed website graph mismatch");
         end;
      end if;
   end Check_Success;

   procedure Check_Result (Result : Buckets.Get_Bucket_Website_Result) is
   begin
      if Expected = "success" then
         Require
           (Result.Kind = Buckets.Get_Bucket_Website_Response_Available
            and then Result.Failure = Client.No_Failure,
            "typed success mismatch: "
            & Buckets.Get_Bucket_Website_Result_Kind'Image (Result.Kind)
            & "/" & Client.Failure_Reason'Image (Result.Failure)
            & "/" & HTTP_Client.Exchange_Result_Kind'Image
              (Result.HTTP_Result)
            & "/" & US.To_String (Result.Detail));
         Check_Success (Result.Response.Configuration);
      elsif Expected = "not_found" then
         Require
           (Result.Kind = Buckets.Get_Bucket_Website_Response_Available
            and then Result.Failure = Client.Not_Found,
            "typed absence mismatch");
      elsif Expected = "response_invalid" then
         Require
           (Result.Kind = Buckets.Get_Bucket_Website_Exchange_Failed
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Invalid,
            "typed invalid-response mismatch");
      elsif Expected = "response_sink_failed" then
         Require
           (Result.Kind = Buckets.Get_Bucket_Website_Exchange_Failed
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
           Low_Level.Prepare_Get_Bucket_Website
             (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
              "us-east-1", "20130524T000000Z");
         Result : constant Low_Level.Get_Bucket_Website_Outcome :=
           Low_Level.Execute_Get_Bucket_Website
             (HTTP, Prepared, Socket_Timeout, null, Limits);
      begin
         Require
           (Expected = "success"
            and then Result.Kind = Low_Level.Bucket_Control_Found,
            "low-level result mismatch");
         Check_Success (Result.Configuration);
      end;
   elsif Lane = "synchronous" or else Lane = "invalid_xml" then
      Check_Result
        (Buckets.Get_Website
           (HTTP, Origin, Bucket, Parameters, Identity, "us-east-1",
            Low_Level.Path_Style, Socket_Timeout, null, Limits));
   elsif Lane = "composable" then
      declare
         --  Derived owner stack: provider, HTTP exchange, transport child.
         Set : aliased Operations.Completion_Set (3);
         Operation : Buckets.Get_Bucket_Website_Operation :=
           Buckets.Get_Website
             (Set'Access, HTTP'Access, Origin, Bucket, Parameters, Identity,
              HTTP_Client.Deadline_After (Socket_Timeout), "us-east-1",
              Low_Level.Path_Style, Limits, null);
         Result : Buckets.Get_Bucket_Website_Result;
      begin
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Check_Result (Result);
      end;
   elsif Lane = "restart" then
      declare
         Set : aliased Operations.Completion_Set (3);
         Operation : Buckets.Get_Bucket_Website_Operation :=
           Buckets.Get_Website
             (Set'Access, HTTP'Access, Origin, Bucket, Parameters, Identity,
              HTTP_Client.Deadline_After (Socket_Timeout), "us-east-1",
              Low_Level.Path_Style, Limits, null);
         Result : Buckets.Get_Bucket_Website_Result;
      begin
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Require
           (Result.Kind = Buckets.Get_Bucket_Website_Response_Available
            and then Result.Failure = Client.No_Failure,
            "restart first result mismatch");
         Buckets.Get_Website
           (HTTP'Access, Origin, Bucket & "-second", Parameters, Identity,
            HTTP_Client.Deadline_After (Socket_Timeout), "us-east-1",
            Low_Level.Path_Style, Limits, null, Operation);
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Require
           (Expected = "not_found"
            and then Result.Kind =
              Buckets.Get_Bucket_Website_Response_Available
            and then Result.Failure = Client.Not_Found,
            "restart terminal result mismatch");
      end;
   else
      raise Program_Error with Case_ID & ": unknown call lane";
   end if;
   HTTP_Client.Shutdown (HTTP);
   Ada.Text_IO.Put_Line
     ("GetBucketWebsite signed qualification " & Case_ID & ": OK");
exception
   when others =>
      HTTP_Client.Shutdown (HTTP);
      raise;
end S3_Get_Bucket_Website_Qualification;
