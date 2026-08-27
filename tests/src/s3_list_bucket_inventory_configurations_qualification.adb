with Ada.Containers;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Inventory;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

procedure S3_List_Bucket_Inventory_Configurations_Qualification is
   package Environment renames Ada.Environment_Variables;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Client renames Flyology.Object_Storage.Client;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Inventory renames Flyology.Object_Storage.S3.Inventory;
   package Operations renames Flyology.Operations;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Client.Failure_Reason;
   use type Buckets.List_Bucket_Inventory_Result_Kind;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Inventory.Inventory_Format;
   use type Inventory.Inventory_Frequency;
   use type Inventory.Included_Object_Versions;
   use type Inventory.Optional_Field_Kind;
   use type Low_Level.List_Bucket_Inventory_Configurations_Outcome_Kind;

   Port : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_PORT");
   Case_ID : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_CASE");
   Lane : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_LANE");
   Bucket : constant String :=
     Environment.Value ("FLYOLOGY_S3_QUALIFICATION_BUCKET");
   Has_Continuation_Token : constant Boolean :=
     Environment.Exists
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN");
   Continuation_Token : constant String :=
     Environment.Value
       ("FLYOLOGY_S3_QUALIFICATION_INPUT_CONTINUATION_TOKEN", "");
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
   Parameters : constant Low_Level.List_Bucket_Configuration_Parameters :=
     (Continuation_Token     => US.To_Unbounded_String (Continuation_Token),
      Has_Continuation_Token => Has_Continuation_Token,
      Expected_Bucket_Owner  =>
        US.To_Unbounded_String (Expected_Bucket_Owner));
   --  Five seconds is the established local socket-corpus watchdog, not a
   --  public client default.
   Socket_Timeout : constant Duration := 5.0;
   --  The region and timestamp are the established fixed SigV4 socket-corpus
   --  oracle. Changing either changes the signed request under test.
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
     (Value : Low_Level.List_Bucket_Inventory_Configurations_Outcome) is
   begin
      Require
        (Value.Kind = Low_Level.Bucket_Inventory_Configurations_Listed,
         "typed page kind mismatch");
      if Expected_Value'Length = 0 then
         Require (Value.Result.Configurations.Is_Empty, "page is not empty");
      else
         Require
           (not Value.Result.Configurations.Is_Empty
            and then US.To_String
              (Value.Result.Configurations.First_Element.ID) = Expected_Value,
            "first inventory identifier mismatch");
      end if;
      if Case_ID = "low-level-success" then
         Require
           (Value.Result.Has_Is_Truncated
            and then not Value.Result.Is_Truncated
            and then Value.Result.Continuation_Token.Is_Set
            and then US.To_String
              (Value.Result.Continuation_Token.Value) = "low level% cursor"
            and then not Value.Result.Next_Continuation_Token.Is_Set
            and then Value.Result.Configurations.Length = 1,
            "low-level page envelope mismatch");
      elsif Case_ID = "synchronous-success" then
         Require
           (Value.Result.Has_Is_Truncated
            and then Value.Result.Is_Truncated
            and then Value.Result.Continuation_Token.Is_Set
            and then US.To_String
              (Value.Result.Continuation_Token.Value) = "sync cursor"
            and then Value.Result.Next_Continuation_Token.Is_Set
            and then US.To_String
              (Value.Result.Next_Continuation_Token.Value) = "next cursor"
            and then Value.Result.Configurations.Length = 2
            and then Value.Result.Configurations.First_Element.Destination.
              S3_Bucket.Account_ID.Is_Set
            and then US.To_String
              (Value.Result.Configurations.First_Element.Destination.S3_Bucket.
                 Account_ID.Value) = "123456789012"
            and then US.To_String
              (Value.Result.Configurations.First_Element.Destination.S3_Bucket.
                 Bucket) = "arn:aws:s3:::qualified-destination"
            and then Value.Result.Configurations.First_Element.Destination.
              S3_Bucket.Format = Inventory.Parquet
            and then Value.Result.Configurations.First_Element.Destination.
              S3_Bucket.Prefix.Is_Set
            and then US.To_String
              (Value.Result.Configurations.First_Element.Destination.S3_Bucket.
                 Prefix.Value) = "inventory/"
            and then Value.Result.Configurations.First_Element.Destination.
              S3_Bucket.Encryption.Is_Set
            and then Value.Result.Configurations.First_Element.Destination.
              S3_Bucket.Encryption.SSE_S3
            and then Value.Result.Configurations.First_Element.Destination.
              S3_Bucket.Encryption.SSE_KMS_Key_ID.Is_Set
            and then US.To_String
              (Value.Result.Configurations.First_Element.Destination.S3_Bucket.
                 Encryption.SSE_KMS_Key_ID.Value) = "key-123"
            and then Value.Result.Configurations.First_Element.Is_Enabled
            and then Value.Result.Configurations.First_Element.Filter.Is_Set
            and then US.To_String
              (Value.Result.Configurations.First_Element.Filter.Prefix) =
                "logs/"
            and then Value.Result.Configurations.First_Element.Versions =
              Inventory.All_Versions
            and then Value.Result.Configurations.First_Element.Optional_Fields.
              Length = 3
            and then Value.Result.Configurations.First_Element.Optional_Fields.
              First_Element = Inventory.ETag
            and then Value.Result.Configurations.First_Element.Optional_Fields.
              Element (2) = Inventory.Checksum_Algorithm
            and then Value.Result.Configurations.First_Element.Optional_Fields.
              Last_Element = Inventory.Lifecycle_Expiration_Date
            and then Value.Result.Configurations.First_Element.Schedule.
              Frequency = Inventory.Weekly
            and then US.To_String
              (Value.Result.Configurations.Last_Element.ID) =
                "second-inventory"
            and then Value.Result.Configurations.Last_Element.Destination.
              S3_Bucket.Format = Inventory.ORC
            and then Value.Result.Configurations.Last_Element.Versions =
              Inventory.Current_Versions
            and then Value.Result.Configurations.Last_Element.Schedule.
              Frequency = Inventory.Daily,
            "synchronous page payload, envelope, or order mismatch");
      elsif Case_ID = "empty-cursor-empty-page" then
         Require
           (Value.Result.Has_Is_Truncated
            and then not Value.Result.Is_Truncated
            and then Value.Result.Continuation_Token.Is_Set
            and then US.Length (Value.Result.Continuation_Token.Value) = 0
            and then not Value.Result.Next_Continuation_Token.Is_Set,
            "empty cursor presence mismatch");
      elsif Case_ID = "composable-success" then
         Require
           (Value.Result.Has_Is_Truncated
            and then not Value.Result.Is_Truncated
            and then not Value.Result.Continuation_Token.Is_Set
            and then not Value.Result.Next_Continuation_Token.Is_Set
            and then Value.Result.Configurations.Length = 1,
            "composable page envelope mismatch");
      end if;
   end Check_Success_Page;

   procedure Check_Result (Result : Buckets.List_Bucket_Inventory_Result) is
   begin
      if Expected = "success" then
         Require
           (Result.Kind = Buckets.List_Bucket_Inventory_Response_Available
            and then Result.Failure = Client.No_Failure,
            "typed success mismatch");
         Check_Success_Page (Result.Response);
      elsif Expected = "not_found" then
         Require
           (Result.Kind = Buckets.List_Bucket_Inventory_Response_Available
            and then Result.Failure = Client.Not_Found,
            "typed absence mismatch");
      elsif Expected = "response_invalid" then
         Require
           (Result.Kind = Buckets.List_Bucket_Inventory_Exchange_Failed
            and then Result.Failure = Client.Corrupt_Or_Invalid_Response
            and then Result.HTTP_Result = HTTP_Client.Response_Invalid,
            "typed invalid-response mismatch");
      elsif Expected = "response_sink_failed" then
         Require
           (Result.Kind = Buckets.List_Bucket_Inventory_Exchange_Failed
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
           Low_Level.Prepare_List_Bucket_Inventory_Configurations
             (Origin, Low_Level.Path_Style, Bucket, Parameters, Identity,
              Signed_Region, Signed_Timestamp);
         Result : constant
           Low_Level.List_Bucket_Inventory_Configurations_Outcome :=
           Low_Level.Execute_List_Bucket_Inventory_Configurations
             (HTTP, Prepared, Socket_Timeout, null, Limits);
      begin
         Require (Expected = "success", "unexpected low-level expectation");
         Check_Success_Page (Result);
      end;
   elsif Lane = "synchronous" or else Lane = "invalid_xml" then
      Check_Result
        (Buckets.List_Inventory_Configurations
           (HTTP, Origin, Bucket, Parameters, Identity, Signed_Region,
            Low_Level.Path_Style, Socket_Timeout, null, Limits));
   elsif Lane = "composable" then
      declare
         --  Derived owner stack: provider, HTTP exchange, transport child.
         Set : aliased Operations.Completion_Set (3);
         Operation : Buckets.List_Bucket_Inventory_Operation :=
           Buckets.List_Inventory_Configurations
             (Set'Access, HTTP'Access, Origin, Bucket, Parameters, Identity,
              HTTP_Client.Deadline_After (Socket_Timeout), Signed_Region,
              Low_Level.Path_Style, Limits, null);
         Result : Buckets.List_Bucket_Inventory_Result;
      begin
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Check_Result (Result);
      end;
   elsif Lane = "restart" then
      declare
         Set : aliased Operations.Completion_Set (3);
         Operation : Buckets.List_Bucket_Inventory_Operation :=
           Buckets.List_Inventory_Configurations
             (Set'Access, HTTP'Access, Origin, Bucket, Parameters, Identity,
              HTTP_Client.Deadline_After (Socket_Timeout), Signed_Region,
              Low_Level.Path_Style, Limits, null);
         Result : Buckets.List_Bucket_Inventory_Result;
      begin
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Require
           (Result.Kind = Buckets.List_Bucket_Inventory_Response_Available
            and then Result.Failure = Client.No_Failure,
            "restart first result mismatch");
         Buckets.List_Inventory_Configurations
           (HTTP'Access, Origin, Bucket & "-second", Parameters, Identity,
            HTTP_Client.Deadline_After (Socket_Timeout), Signed_Region,
            Low_Level.Path_Style, Limits, null, Operation);
         Operations.Wait_All (Set);
         Buckets.Finish (Operation, Result);
         Require
           (Expected = "not_found"
            and then Result.Kind =
              Buckets.List_Bucket_Inventory_Response_Available
            and then Result.Failure = Client.Not_Found,
            "restart terminal result mismatch");
      end;
   else
      raise Program_Error with Case_ID & ": unknown call lane";
   end if;
   HTTP_Client.Shutdown (HTTP);
   Ada.Text_IO.Put_Line
     ("ListBucketInventoryConfigurations signed qualification " &
      Case_ID & ": OK");
exception
   when others =>
      HTTP_Client.Shutdown (HTTP);
      raise;
end S3_List_Bucket_Inventory_Configurations_Qualification;
