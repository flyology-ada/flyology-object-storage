with Ada.Containers;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Objects;
with Flyology.Object_Storage.S3.Annotations;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

procedure S3_List_Object_Annotations_Qualification is
   package Environment renames Ada.Environment_Variables;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Client renames Flyology.Object_Storage.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Objects renames Flyology.Object_Storage.Client.Objects;
   package Annotations renames Flyology.Object_Storage.S3.Annotations;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Operations renames Flyology.Operations;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Client.Failure_Reason;
   use type Core.Checksum_Algorithm;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.List_Object_Annotations_Outcome_Kind;
   use type Objects.List_Object_Annotations_Result_Kind;
   use type Annotations.Replication_Status;

   Port : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_PORT");
   Case_ID : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_CASE");
   Lane : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_LANE");
   Bucket : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_BUCKET");
   Key : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_INPUT_KEY");
   Version_ID : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_VERSION_ID", "");
   Max_Text : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_MAX_ANNOTATION_RESULTS", "");
   Annotation_Prefix : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_ANNOTATION_PREFIX", "");
   Continuation_Token : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN", "");
   Request_Payer : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_REQUEST_PAYER", "");
   Expected_Bucket_Owner : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_EXPECTED_BUCKET_OWNER", "");
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
   Parameters : constant Low_Level.List_Object_Annotations_Parameters :=
     (Version_ID                 => US.To_Unbounded_String (Version_ID),
      Has_Version_ID             =>
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_VERSION_ID"),
      Max_Annotation_Results     =>
        (if Max_Text'Length = 0
         then Annotations.Annotation_Result_Limit'First
         else Annotations.Annotation_Result_Limit'Value (Max_Text)),
      Has_Max_Annotation_Results => Max_Text'Length > 0,
      Annotation_Prefix          =>
        US.To_Unbounded_String (Annotation_Prefix),
      Has_Annotation_Prefix      =>
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_ANNOTATION_PREFIX"),
      Continuation_Token         =>
        US.To_Unbounded_String (Continuation_Token),
      Has_Continuation_Token     =>
        Environment.Exists
          ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN"),
      Request_Payer              => US.To_Unbounded_String (Request_Payer),
      Expected_Bucket_Owner      =>
        US.To_Unbounded_String (Expected_Bucket_Owner));
   --  Five seconds is the established local socket-corpus watchdog, not a
   --  public client default.
   Socket_Timeout : constant Duration := 5.0;
   --  Fixed signing inputs are the established socket-corpus oracle.
   Signed_Region : constant String := "us-east-1";
   Signed_Timestamp : constant String := "20130524T000000Z";

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

   procedure Check_Success_Page
     (Value : Low_Level.List_Object_Annotations_Outcome) is
   begin
      Require
        (Value.Kind = Low_Level.Object_Annotations_Listed,
         "typed page kind mismatch");
      if Expected_Value'Length = 0 then
         Require (Value.Result.Page.Annotations.Is_Empty, "page is not empty");
      else
         Require
           (not Value.Result.Page.Annotations.Is_Empty
            and then US.To_String
              (Value.Result.Page.Annotations.First_Element.Name) =
                Expected_Value,
            "first annotation name mismatch");
      end if;
      if Case_ID = "low-level-success" then
         Require
           (Value.Result.Page.Has_Annotations
            and then Value.Result.Page.Annotations.Length = 1
            and then Value.Result.Page.Continuation_Token.Is_Set
            and then US.To_String
              (Value.Result.Page.Continuation_Token.Value) =
                "low level% cursor"
            and then US.To_String (Value.Result.Object_Version_ID) = "v-low"
            and then US.To_String (Value.Result.Request_Charged) = "requester",
            "low-level page or header mismatch");
      elsif Case_ID = "synchronous-success" then
         declare
            Annotation : constant Annotations.Annotation_Entry :=
              Value.Result.Page.Annotations.First_Element;
         begin
            Require
              (Value.Result.Page.Has_Annotations
               and then Value.Result.Page.Annotations.Length = 2
               and then Value.Result.Page.Bucket.Is_Set
               and then US.To_String (Value.Result.Page.Bucket.Value) =
                 "qualified-sync"
               and then Value.Result.Page.Key.Is_Set
               and then US.To_String (Value.Result.Page.Key.Value) =
                 "object/key"
               and then Value.Result.Page.Annotation_Prefix.Is_Set
               and then US.To_String
                 (Value.Result.Page.Annotation_Prefix.Value) = "reviewed/"
               and then Value.Result.Page.Max_Annotation_Results.Is_Set
               and then Value.Result.Page.Max_Annotation_Results.Value = 2
               and then Value.Result.Page.Annotation_Count.Is_Set
               and then US.To_String
                 (Value.Result.Page.Annotation_Count.Text) = "2"
               and then Value.Result.Page.Next_Continuation_Token.Is_Set
               and then US.To_String
                 (Value.Result.Page.Next_Continuation_Token.Value) = "next"
               and then US.To_String (Annotation.Last_Modified) =
                 "2026-08-27T12:34:56Z"
               and then Annotation.Entity_Tag.Is_Set
               and then US.To_String (Annotation.Entity_Tag.Value) =
                 """etag-one"""
               and then Annotation.Checksums.Length = 2
               and then Annotation.Checksums.First_Element = Core.CRC32C
               and then Annotation.Checksums.Last_Element = Core.SHA512
               and then Annotation.Size = 42
               and then Annotation.Replication.Is_Set
               and then Annotation.Replication.Value =
                 Annotations.Replication_Complete
               and then US.To_String (Value.Result.Object_Version_ID) =
                 "v-sync"
               and then US.To_String (Value.Result.Request_Charged) =
                 "requester",
               "complete synchronous annotation graph mismatch");
         end;
      elsif Case_ID = "empty-annotations" then
         Require
           (Value.Result.Page.Has_Annotations
            and then Value.Result.Page.Annotations.Is_Empty,
            "present empty annotations wrapper was not preserved");
      end if;
   end Check_Success_Page;

   procedure Check_Result (Result : Objects.List_Object_Annotations_Result) is
   begin
      if Expected = "success" then
         Require
           (Result.Kind =
              Objects.List_Object_Annotations_Response_Available
            and then Result.Failure = Client.No_Failure,
            "typed success mismatch");
         Check_Success_Page (Result.Response);
      elsif Expected = "not_found" then
         Require
           (Result.Kind =
              Objects.List_Object_Annotations_Response_Available
            and then Result.Failure = Client.Not_Found,
            "typed absence mismatch");
      elsif Expected = "invalid_request" then
         Require
           (Result.Kind =
              Objects.List_Object_Annotations_Response_Available
            and then Result.Failure = Client.Invalid_Request,
            "typed invalid-prefix mismatch");
      elsif Expected = "response_invalid" then
         Require
           (Result.Kind = Objects.List_Object_Annotations_Exchange_Failed
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Invalid,
            "typed invalid-response mismatch");
      elsif Expected = "response_sink_failed" then
         Require
           (Result.Kind = Objects.List_Object_Annotations_Exchange_Failed
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
           Low_Level.Prepare_List_Object_Annotations
             (Origin, Low_Level.Path_Style, Bucket, Key, Parameters, Identity,
              Signed_Region, Signed_Timestamp);
         Result : constant Low_Level.List_Object_Annotations_Outcome :=
           Low_Level.Execute_List_Object_Annotations
             (HTTP, Prepared, Socket_Timeout, null, Limits);
      begin
         Require (Expected = "success", "unexpected low-level expectation");
         Check_Success_Page (Result);
      end;
   elsif Lane = "synchronous" or else Lane = "invalid_xml" then
      Check_Result
        (Objects.List_Annotations
           (HTTP, Origin, Bucket, Key, Parameters, Identity, Signed_Region,
            Low_Level.Path_Style, Socket_Timeout, null, Limits));
   elsif Lane = "composable" then
      declare
         Set : aliased Operations.Completion_Set (3);
         Operation : Objects.List_Object_Annotations_Operation :=
           Objects.List_Annotations
             (Set'Access, HTTP'Access, Origin, Bucket, Key, Parameters,
              Identity, HTTP_Client.Deadline_After (Socket_Timeout),
              Signed_Region, Low_Level.Path_Style, Limits, null);
         Result : Objects.List_Object_Annotations_Result;
      begin
         Operations.Wait_All (Set);
         Objects.Finish (Operation, Result);
         Check_Result (Result);
      end;
   elsif Lane = "restart" then
      declare
         Set : aliased Operations.Completion_Set (3);
         Operation : Objects.List_Object_Annotations_Operation :=
           Objects.List_Annotations
             (Set'Access, HTTP'Access, Origin, Bucket, Key, Parameters,
              Identity, HTTP_Client.Deadline_After (Socket_Timeout),
              Signed_Region, Low_Level.Path_Style, Limits, null);
         Result : Objects.List_Object_Annotations_Result;
      begin
         Operations.Wait_All (Set);
         Objects.Finish (Operation, Result);
         Require
           (Result.Kind =
              Objects.List_Object_Annotations_Response_Available
            and then Result.Failure = Client.No_Failure,
            "restart first result mismatch");
         Objects.List_Annotations
           (HTTP'Access, Origin, Bucket, Key & "-second", Parameters,
            Identity, HTTP_Client.Deadline_After (Socket_Timeout),
            Signed_Region, Low_Level.Path_Style, Limits, null, Operation);
         Operations.Wait_All (Set);
         Objects.Finish (Operation, Result);
         Require
           (Expected = "not_found"
            and then Result.Kind =
              Objects.List_Object_Annotations_Response_Available
            and then Result.Failure = Client.Not_Found,
            "restart terminal result mismatch");
      end;
   else
      raise Program_Error with Case_ID & ": unknown call lane";
   end if;
   HTTP_Client.Shutdown (HTTP);
   Ada.Text_IO.Put_Line
     ("ListObjectAnnotations signed qualification " & Case_ID & ": OK");
exception
   when others =>
      HTTP_Client.Shutdown (HTTP);
      raise;
end S3_List_Object_Annotations_Qualification;
