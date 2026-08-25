with Flyology.Object_Storage.S3.Tagging;
with Flyology.Object_Storage.S3.Versioning;
with Flyology.Operations.Drivers;
with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Flyology.Object_Storage.Client.Buckets is

   package US renames Ada.Strings.Unbounded;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Operations renames Flyology.Operations;
   package Operation_Drivers renames Flyology.Operations.Drivers;
   package Low renames Flyology.Object_Storage.Client.Low_Level;

   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Operations.Driver_Event;
   use type Ada.Streams.Stream_Element_Offset;

   Response_Limit_Exceeded : exception;

   function Failed_Reason
     (Kind : HTTP_Client.Exchange_Result_Kind) return Failure_Reason is
     (case Kind is
         when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
         when HTTP_Client.Cancelled => Cancelled,
         when HTTP_Client.Timed_Out => Timed_Out,
         when HTTP_Client.Client_Unavailable => Client_Unavailable,
         when HTTP_Client.Connection_Failed => Connection_Failed,
         when HTTP_Client.Transport_Failed => Transport_Failed,
         when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
         when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
         when HTTP_Client.Response_Complete |
              HTTP_Client.Response_Invalid |
              HTTP_Client.Response_Sink_Failed =>
           Corrupt_Or_Invalid_Response);

   package LL renames Low_Level;
   package Bucket_Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Configuration_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Put_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Get_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;
   use type Low_Level.Put_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Get_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;

   function Timestamp return String is
      Image : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => False, Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 3)
        & Image (Image'First + 5 .. Image'First + 6)
        & Image (Image'First + 8 .. Image'First + 9) & "T"
        & Image (Image'First + 11 .. Image'First + 12)
        & Image (Image'First + 14 .. Image'First + 15)
        & Image (Image'First + 17 .. Image'First + 18) & "Z";
   end Timestamp;

   procedure Raise_Bucket_Tagging_Exchange_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Operation : String) is
   begin
      case Kind is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error with
              "unreachable complete " & Operation & " exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              Operation & " response is invalid or exceeds the XML limit";
      end case;
   end Raise_Bucket_Tagging_Exchange_Failure;

   procedure Raise_List_Buckets_Exchange_Failure
     (Result : List_Buckets_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error with
              "unreachable complete ListBuckets exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "ListBuckets response is invalid or exceeds the XML limit";
      end case;
   end Raise_List_Buckets_Exchange_Failure;

   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Buckets_Result
   is
      --  The listing parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : List_Buckets_Operation :=
           List_Page
             (Set'Access, Client'Access, Origin, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : List_Buckets_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end List_Page;

   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Maximum  : Flyology.Object_Storage.S3.Buckets.Max_Buckets_Value :=
        1_000;
      Continuation_Token : String := "";
      Prefix   : String := "";
      Bucket_Region : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Outcome
   is
      Parameters : constant Low_Level.List_Buckets_Parameters :=
        (Max_Buckets            => Maximum,
         Has_Max_Buckets        => True,
         Continuation_Token     =>
           US.To_Unbounded_String (Continuation_Token),
         Has_Continuation_Token => Continuation_Token'Length > 0,
         Prefix                 => US.To_Unbounded_String (Prefix),
         Has_Prefix             => Prefix'Length > 0,
         Bucket_Region          => US.To_Unbounded_String (Bucket_Region));
   begin
      declare
         Result : constant List_Buckets_Result :=
           List_Page
             (Client, Origin, Parameters, Identity, Region, Style, Timeout,
              Token);
      begin
         if Result.Kind = List_Buckets_Exchange_Failed then
            Raise_List_Buckets_Exchange_Failure (Result);
         end if;
         declare
            Outcome : Low_Level.List_Buckets_Outcome renames Result.Response;
         begin
            if Outcome.Kind = Low_Level.List_Buckets_Rejected then
               return
                 (Kind => List_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind => Page_Available, Status => Outcome.Status,
               Page => Outcome.Result);
         end;
      end;
   end List_Page;

   function Create
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Bucket_Result
   is
      --  The CreateBucket parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Create_Bucket_Operation :=
           Create
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Create_Bucket_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Create;

   procedure Raise_Create_Bucket_Exchange_Failure
     (Result : Create_Bucket_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error with
              "unreachable complete CreateBucket exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "CreateBucket response is invalid or exceeds the XML limit";
      end case;
   end Raise_Create_Bucket_Exchange_Failure;

   function Create
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Location_Constraint : String := "";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Outcome
   is
      Parameters : Low_Level.Create_Bucket_Parameters;
   begin
      Parameters.Configuration.Location_Constraint :=
        US.To_Unbounded_String
          (if Location_Constraint'Length > 0 then Location_Constraint
           elsif Region /= "us-east-1" then Region
           else "");
      declare
         Result : constant Create_Bucket_Result :=
           Create
             (Client, Origin, Bucket, Parameters, Identity, Region, Style,
              Timeout, Token);
      begin
         if Result.Kind = Create_Bucket_Exchange_Failed then
            Raise_Create_Bucket_Exchange_Failure (Result);
         end if;
         declare
            Outcome : Low_Level.Create_Bucket_Outcome renames Result.Response;
         begin
            if Outcome.Kind = Low_Level.Create_Bucket_Rejected then
               return
                 (Kind => Create_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind       => Creation_Completed,
               Status     => Outcome.Status,
               Location   => Outcome.Result.Location,
               Bucket_ARN => Outcome.Result.Bucket_ARN);
         end;
      end;
   end Create;

   function Delete
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Result
   is
      --  The DeleteBucket parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Delete_Bucket_Operation :=
           Delete
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Token);
         Result    : Delete_Bucket_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Delete;

   procedure Raise_Delete_Bucket_Exchange_Failure
     (Result : Delete_Bucket_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete      =>
            raise Program_Error
              with "unreachable complete DeleteBucket exchange failure";

         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";

         when Flyology.HTTP.Client.Cancelled              =>
            raise Flyology.Cancellation.Operation_Cancelled;

         when Flyology.HTTP.Client.Timed_Out              =>
            raise Flyology.IO.Timeout_Error;

         when Flyology.HTTP.Client.Client_Unavailable     =>
            raise Flyology.HTTP.Client.Client_Closed;

         when Flyology.HTTP.Client.Connection_Failed      =>
            raise Flyology.HTTP.Client.Connection_Error;

         when Flyology.HTTP.Client.Transport_Failed       =>
            raise Flyology.IO.Device_Error;

         when Flyology.HTTP.Client.Request_Source_Failed  =>
            raise Flyology.HTTP.Client.Request_Body_Error;

         when Flyology.HTTP.Client.Response_Invalid
            | Flyology.HTTP.Client.Response_Body_Too_Large
            | Flyology.HTTP.Client.Response_Sink_Failed   =>
            raise Low_Level.Invalid_Response
              with "DeleteBucket response is invalid or exceeds the XML limit";
      end case;
   end Raise_Delete_Bucket_Exchange_Failure;

   function Delete
     (Client                : aliased in out Flyology.HTTP.Client.Client;
      Origin                : Flyology.HTTP.Origin;
      Bucket                : String;
      Identity              : Low_Level.Credentials;
      Region                : String := "us-east-1";
      Style                 : Low_Level.Addressing_Style :=
        Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout               : Duration := 30.0;
      Token                 : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is
      Parameters : constant Low_Level.Delete_Bucket_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
   begin
      declare
         Result : constant Delete_Bucket_Result :=
           Delete
             (Client,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Region,
              Style,
              Timeout,
              Token);
      begin
         if Result.Kind = Delete_Bucket_Exchange_Failed then
            Raise_Delete_Bucket_Exchange_Failure (Result);
         end if;
         declare
            Outcome : Low_Level.Delete_Bucket_Outcome renames Result.Response;
         begin
            if Outcome.Kind = Low_Level.Delete_Bucket_Rejected then
               return
                 (Kind   => Delete_Rejected,
                  Status => Outcome.Status,
                  Error  => Outcome.Error);
            end if;
            return (Kind => Deletion_Completed, Status => Outcome.Status);
         end;
      end;
   end Delete;

   type Configuration_Deletion_Kind is
     (CORS_Configuration,
      Analytics_Configuration,
      Encryption_Configuration,
      Intelligent_Tiering_Configuration,
      Inventory_Configuration,
      Lifecycle_Configuration,
      Metadata_Configuration,
      Metadata_Table_Configuration,
      Metrics_Configuration,
      Ownership_Controls_Configuration,
      Replication_Configuration,
      Website_Configuration,
      Public_Access_Block_Configuration);

   function Delete_Configuration
     (Kind       : Configuration_Deletion_Kind;
      Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Identifier : String;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Expected_Bucket_Owner : String;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token)
      return Delete_Outcome
   is
      Parameters : constant Low_Level.Delete_Bucket_Configuration_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
      Parameters_With_ID : constant
        Low_Level.Delete_Bucket_Configuration_With_ID_Parameters :=
          (ID                    => US.To_Unbounded_String (Identifier),
           Expected_Bucket_Owner =>
             US.To_Unbounded_String (Expected_Bucket_Owner));

      function Prepare return Low_Level.Prepared_Request is
      begin
         case Kind is
            when CORS_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_CORS
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Analytics_Configuration =>
               return
                 Low_Level.Prepare_Delete_Bucket_Analytics_Configuration
                   (Origin, Style, Bucket, Parameters_With_ID, Identity,
                    Region, Timestamp);
            when Encryption_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Encryption
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Intelligent_Tiering_Configuration =>
               return
                 LL.Prepare_Delete_Bucket_Intelligent_Tiering_Configuration
                   (Origin, Style, Bucket, Parameters_With_ID, Identity,
                    Region, Timestamp);
            when Inventory_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Inventory_Configuration
                 (Origin, Style, Bucket, Parameters_With_ID, Identity, Region,
                  Timestamp);
            when Lifecycle_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Lifecycle
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Metadata_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Metadata_Configuration
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Metadata_Table_Configuration =>
               return
                 Low_Level.Prepare_Delete_Bucket_Metadata_Table_Configuration
                   (Origin, Style, Bucket, Parameters, Identity, Region,
                    Timestamp);
            when Metrics_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Metrics_Configuration
                 (Origin, Style, Bucket, Parameters_With_ID, Identity, Region,
                  Timestamp);
            when Ownership_Controls_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Ownership_Controls
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Replication_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Replication
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Website_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Website
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Public_Access_Block_Configuration =>
               return Low_Level.Prepare_Delete_Public_Access_Block
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
         end case;
      end Prepare;

      Prepared : constant Low_Level.Prepared_Request := Prepare;

      function Execute return Low_Level.Delete_Bucket_Configuration_Outcome is
      begin
         case Kind is
            when CORS_Configuration =>
               return Low_Level.Execute_Delete_Bucket_CORS
                 (Client, Prepared, Timeout, Token);
            when Analytics_Configuration =>
               return
                 Low_Level.Execute_Delete_Bucket_Analytics_Configuration
                   (Client, Prepared, Timeout, Token);
            when Encryption_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Encryption
                 (Client, Prepared, Timeout, Token);
            when Intelligent_Tiering_Configuration =>
               return
                 LL.Execute_Delete_Bucket_Intelligent_Tiering_Configuration
                   (Client, Prepared, Timeout, Token);
            when Inventory_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Inventory_Configuration
                 (Client, Prepared, Timeout, Token);
            when Lifecycle_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Lifecycle
                 (Client, Prepared, Timeout, Token);
            when Metadata_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Metadata_Configuration
                 (Client, Prepared, Timeout, Token);
            when Metadata_Table_Configuration =>
               return
                 Low_Level.Execute_Delete_Bucket_Metadata_Table_Configuration
                   (Client, Prepared, Timeout, Token);
            when Metrics_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Metrics_Configuration
                 (Client, Prepared, Timeout, Token);
            when Ownership_Controls_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Ownership_Controls
                 (Client, Prepared, Timeout, Token);
            when Replication_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Replication
                 (Client, Prepared, Timeout, Token);
            when Website_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Website
                 (Client, Prepared, Timeout, Token);
            when Public_Access_Block_Configuration =>
               return Low_Level.Execute_Delete_Public_Access_Block
                 (Client, Prepared, Timeout, Token);
         end case;
      end Execute;

      Outcome : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
        Execute;
   begin
      if Outcome.Kind = Low_Level.Delete_Configuration_Rejected then
         return
           (Kind => Delete_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return (Kind => Deletion_Completed, Status => Outcome.Status);
   end Delete_Configuration;

   function Delete_CORS
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (CORS_Configuration, Client, Origin, Bucket, "", Identity, Region,
          Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Analytics_Configuration, Client, Origin, Bucket, Identifier,
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Encryption_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Intelligent_Tiering_Configuration, Client, Origin, Bucket,
          Identifier, Identity, Region, Style, Expected_Bucket_Owner,
          Timeout, Token));

   function Delete_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Inventory_Configuration, Client, Origin, Bucket, Identifier,
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Lifecycle
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Lifecycle_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Metadata_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Metadata_Table_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Metrics_Configuration, Client, Origin, Bucket, Identifier, Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Ownership_Controls_Configuration, Client, Origin, Bucket, "",
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is
      Parameters : constant Low_Level.Delete_Bucket_Configuration_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
      Result : constant Delete_Bucket_Policy_Result :=
        Delete_Policy
          (Client, Origin, Bucket, Parameters, Identity, Region, Style,
           Timeout, Token);
   begin
      if Result.Kind = Delete_Bucket_Policy_Exchange_Failed then
         case Result.HTTP_Result is
            when Flyology.HTTP.Client.Response_Complete =>
               raise Program_Error
                 with "unreachable complete DeleteBucketPolicy failure";
            when Flyology.HTTP.Client.Pre_Admission_Rejected =>
               raise Constraint_Error with
                 "HTTP request was rejected: " & US.To_String (Result.Detail);
            when Flyology.HTTP.Client.Cancelled =>
               raise Flyology.Cancellation.Operation_Cancelled;
            when Flyology.HTTP.Client.Timed_Out =>
               raise Flyology.IO.Timeout_Error;
            when Flyology.HTTP.Client.Client_Unavailable =>
               raise Flyology.HTTP.Client.Client_Closed;
            when Flyology.HTTP.Client.Connection_Failed =>
               raise Flyology.HTTP.Client.Connection_Error;
            when Flyology.HTTP.Client.Transport_Failed =>
               raise Flyology.IO.Device_Error;
            when Flyology.HTTP.Client.Request_Source_Failed =>
               raise Flyology.HTTP.Client.Request_Body_Error;
            when Flyology.HTTP.Client.Response_Invalid
               | Flyology.HTTP.Client.Response_Body_Too_Large
               | Flyology.HTTP.Client.Response_Sink_Failed =>
               raise Low_Level.Invalid_Response with
                 "DeleteBucketPolicy response is invalid or exceeds XML " &
                 "limit";
         end case;
      elsif Result.Response.Kind = Low_Level.Delete_Configuration_Rejected then
         return
           (Kind   => Delete_Rejected,
            Status => Result.Response.Status,
            Error  => Result.Response.Error);
      else
         return
           (Kind => Deletion_Completed, Status => Result.Response.Status);
      end if;
   end Delete_Policy;

   function Delete_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Replication_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Website_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Public_Access_Block_Configuration, Client, Origin, Bucket, "",
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Get_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Request_Payer : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Accelerate_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Accelerate_Configuration
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner),
            Request_Payer => US.To_Unbounded_String (Request_Payer)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Get_Bucket_Accelerate_Configuration
        (Client, Prepared, Timeout, Token, Limits);
   end Get_Accelerate_Configuration;

   function Get_ABAC
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Abac_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Abac
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Get_Bucket_Abac
        (Client, Prepared, Timeout, Token, Limits);
   end Get_ABAC;

   function Get_Policy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Bucket_Policy_Result
   is
      --  The policy parent, HTTP exchange, and HTTP's single active transport
      --  child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Bucket_Policy_Operation :=
           Get_Policy
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Limits,
              Token);
         Result : Get_Bucket_Policy_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Policy;

   procedure Raise_Get_Bucket_Policy_Exchange_Failure
     (Result : Get_Bucket_Policy_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error
              with "unreachable complete GetBucketPolicy exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid
            | Flyology.HTTP.Client.Response_Body_Too_Large
            | Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "GetBucketPolicy response is invalid or exceeds byte limit";
      end case;
   end Raise_Get_Bucket_Policy_Exchange_Failure;

   function Get_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Policy_Outcome
   is
      Result : constant Get_Bucket_Policy_Result :=
        Get_Policy
          (Client,
           Origin,
           Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity,
           Region,
           Style,
           Timeout,
           Token,
           Limits);
   begin
      if Result.Kind = Get_Bucket_Policy_Exchange_Failed then
         Raise_Get_Bucket_Policy_Exchange_Failure (Result);
      end if;
      return Result.Response;
   end Get_Policy;

   function Get_Policy_Status
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Policy_Status_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Policy_Status
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Get_Bucket_Policy_Status
        (Client, Prepared, Timeout, Token, Limits);
   end Get_Policy_Status;

   function Get_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Bucket_Request_Payment_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Request_Payment
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Get_Bucket_Request_Payment
        (Client, Prepared, Timeout, Token, Limits);
   end Get_Request_Payment;

   function Get_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Get_Public_Access_Block_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Public_Access_Block
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Get_Public_Access_Block
        (Client, Prepared, Timeout, Token, Limits);
   end Get_Public_Access_Block;

   function Set_ABAC
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Flyology.Object_Storage.S3.Bucket_Controls.Abac_Status;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Origin, Style, Bucket, Value,
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.To_Unbounded_String (Checksum_Algorithm),
            Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Put_Bucket_Abac
        (Client, Prepared, Timeout, Token, Limits);
   end Set_ABAC;

   function Set_Accelerate_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Flyology.Object_Storage.S3.Bucket_Controls.Accelerate_Status;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Accelerate_Configuration
          (Origin, Style, Bucket, Value,
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.To_Unbounded_String (Checksum_Algorithm),
            Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Put_Bucket_Accelerate_Configuration
        (Client, Prepared, Timeout, Token, Limits);
   end Set_Accelerate_Configuration;

   function Set_Request_Payment
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Flyology.Object_Storage.S3.Bucket_Controls.Payer;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Request_Payment
          (Origin, Style, Bucket, Value,
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.To_Unbounded_String (Checksum_Algorithm),
            Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Put_Bucket_Request_Payment
        (Client, Prepared, Timeout, Token, Limits);
   end Set_Request_Payment;

   function Set_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Value : Bucket_Controls.Public_Access_Block_Configuration;
      Identity : Low_Level.Credentials; Checksum_Algorithm : String := "";
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Public_Access_Block
          (Origin, Style, Bucket, Value,
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.To_Unbounded_String (Checksum_Algorithm),
            Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Put_Public_Access_Block
        (Client, Prepared, Timeout, Token, Limits);
   end Set_Public_Access_Block;

   function Set_Policy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Put_Bucket_Policy_Result
   is
      --  The policy parent, HTTP exchange, and HTTP's single active transport
      --  child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Put_Bucket_Policy_Operation :=
           Set_Policy
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Policy,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Limits,
              Token);
         Result : Put_Bucket_Policy_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Set_Policy;

   function Delete_Policy
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Delete_Bucket_Policy_Result
   is
      --  The policy parent, HTTP exchange, and HTTP's single active transport
      --  child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Delete_Bucket_Policy_Operation :=
           Delete_Policy
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Limits,
              Token);
         Result : Delete_Bucket_Policy_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Delete_Policy;

   procedure Raise_Put_Bucket_Policy_Exchange_Failure
     (Result : Put_Bucket_Policy_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error
              with "unreachable complete PutBucketPolicy failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with
              "HTTP request was rejected: " & US.To_String (Result.Detail);
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid
            | Flyology.HTTP.Client.Response_Body_Too_Large
            | Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "PutBucketPolicy response is invalid or exceeds XML limit";
      end case;
   end Raise_Put_Bucket_Policy_Exchange_Failure;

   function Set_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String; Policy : String;
      Identity : Low_Level.Credentials;
      Confirm_Remove_Self_Access : Low_Level.Optional_Boolean :=
        (others => <>);
      Checksum_Algorithm : String := ""; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Low_Level.Put_Bucket_Control_Outcome
   is
      Parameters : constant Low_Level.Put_Bucket_Policy_Parameters :=
        (Content_MD5 => US.Null_Unbounded_String,
         Checksum_Algorithm => US.To_Unbounded_String (Checksum_Algorithm),
         Confirm_Remove_Self_Access => Confirm_Remove_Self_Access,
         Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
      Result : constant Put_Bucket_Policy_Result :=
        Set_Policy
          (Client, Origin, Bucket, Policy, Parameters, Identity, Region,
           Style, Timeout, Token, Limits);
   begin
      if Result.Kind = Put_Bucket_Policy_Exchange_Failed then
         Raise_Put_Bucket_Policy_Exchange_Failure (Result);
      end if;
      return Result.Response;
   end Set_Policy;

   function Head
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Result
   is
      --  The HeadBucket parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Head_Bucket_Operation :=
           Head
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Head_Bucket_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Head;

   procedure Raise_Head_Bucket_Exchange_Failure
     (Result : Head_Bucket_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error with
              "unreachable complete HeadBucket exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "HeadBucket response is invalid";
      end case;
   end Raise_Head_Bucket_Exchange_Failure;

   function Head
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Outcome
   is
   begin
      declare
         Result : constant Head_Bucket_Result :=
           Head
             (Client, Origin, Bucket,
              (Expected_Bucket_Owner =>
                 US.To_Unbounded_String (Expected_Bucket_Owner)),
              Identity, Region, Style, Timeout, Token);
      begin
         if Result.Kind = Head_Bucket_Exchange_Failed then
            Raise_Head_Bucket_Exchange_Failure (Result);
         end if;
         declare
            Outcome : Low_Level.Head_Bucket_Outcome renames Result.Response;
         begin
            if Outcome.Kind = Low_Level.Head_Bucket_Rejected then
               return
                 (Kind => Head_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind                 => Bucket_Available,
               Status               => Outcome.Status,
               Bucket_ARN           => Outcome.Result.Bucket_ARN,
               Bucket_Location_Type => Outcome.Result.Bucket_Location_Type,
               Bucket_Location_Name => Outcome.Result.Bucket_Location_Name,
               Region               =>
                 (if US.Length (Outcome.Result.Bucket_Region) = 0
                  then US.To_Unbounded_String (Region)
                  else Outcome.Result.Bucket_Region),
               Access_Point_Alias   => Outcome.Result.Access_Point_Alias);
         end;
      end;
   end Head;

   function Get_Location
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Location_Result
   is
      --  The location parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Bucket_Location_Operation :=
           Get_Location
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Token);
         Result    : Get_Bucket_Location_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Location;

   procedure Raise_Get_Bucket_Location_Exchange_Failure
     (Result : Get_Bucket_Location_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error
              with "unreachable complete GetBucketLocation exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid
            | Flyology.HTTP.Client.Response_Body_Too_Large
            | Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "GetBucketLocation response is invalid or exceeds XML limit";
      end case;
   end Raise_Get_Bucket_Location_Exchange_Failure;

   function Get_Location
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Location_Outcome
   is
      Result : constant Get_Bucket_Location_Result :=
        Get_Location
          (Client,
           Origin,
           Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity,
           Region,
           Style,
           Timeout,
           Token);
   begin
      if Result.Kind = Get_Bucket_Location_Exchange_Failed then
         Raise_Get_Bucket_Location_Exchange_Failure (Result);
      end if;
      declare
         Outcome : Low_Level.Get_Bucket_Location_Outcome renames
           Result.Response;
      begin
         if Outcome.Kind = Low_Level.Get_Bucket_Location_Rejected then
            return
              (Kind => Location_Rejected, Status => Outcome.Status,
               Error => Outcome.Error);
         end if;
         declare
            Constraint : constant String :=
              US.To_String (Outcome.Result.Location_Constraint);
            Normalized : constant String :=
              (if Constraint'Length = 0 then "us-east-1"
               elsif Constraint = "EU" then "eu-west-1"
               else Constraint);
         begin
            return
              (Kind => Location_Found, Status => Outcome.Status,
               Region => US.To_Unbounded_String (Normalized),
               Legacy_Constraint => Outcome.Result.Location_Constraint);
         end;
      end;
   end Get_Location;

   function Put_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Value    : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Tagging_Result
   is
      --  Derived capacity: tagging parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Put_Bucket_Tagging_Operation :=
           Put_Tags
             (Set'Access, Client'Access, Origin, Bucket, Value, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Put_Bucket_Tagging_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Put_Tags;

   function Put_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Value    : Flyology.Object_Storage.Tags.Tag_Set;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Put_Tags_Outcome
   is
      Parameters : constant Low_Level.Put_Bucket_Tagging_Parameters :=
        (Content_MD5           => US.Null_Unbounded_String,
         Checksum_Algorithm    => US.Null_Unbounded_String,
         Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner),
         Request_Payer         => US.Null_Unbounded_String);
   begin
      declare
         Result : constant Put_Bucket_Tagging_Result :=
           Put_Tags
             (Client, Origin, Bucket, Value, Parameters, Identity, Region,
              Style, Timeout, Token);
      begin
         if Result.Kind = Put_Bucket_Tagging_Exchange_Failed then
            Raise_Bucket_Tagging_Exchange_Failure
              (Result.HTTP_Result, "PutBucketTagging");
         end if;
         declare
            Outcome : Low_Level.Put_Bucket_Tagging_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Put_Bucket_Tagging_Rejected then
               return
                 (Kind => Put_Tags_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return (Kind => Tags_Replaced, Status => Outcome.Status);
         end;
      end;
   end Put_Tags;

   function Get_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Tagging_Result
   is
      --  Derived capacity: tagging parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Bucket_Tagging_Operation :=
           Get_Tags
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Get_Bucket_Tagging_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Tags;

   function Get_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Tags_Outcome
   is
      Parameters : constant Low_Level.Get_Bucket_Tagging_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner),
         Request_Payer         => US.Null_Unbounded_String);
   begin
      declare
         Result : constant Get_Bucket_Tagging_Result :=
           Get_Tags
             (Client, Origin, Bucket, Parameters, Identity, Region, Style,
              Timeout, Token);
      begin
         if Result.Kind = Get_Bucket_Tagging_Exchange_Failed then
            Raise_Bucket_Tagging_Exchange_Failure
              (Result.HTTP_Result, "GetBucketTagging");
         end if;
         declare
            Outcome : Low_Level.Get_Bucket_Tagging_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Get_Bucket_Tagging_Rejected then
               return
                 (Kind => Get_Tags_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind => Tags_Found, Status => Outcome.Status,
               Value => Outcome.Result.Value);
         end;
      end;
   end Get_Tags;

   function Delete_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Tagging_Result
   is
      --  Derived capacity: tagging parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Delete_Bucket_Tagging_Operation :=
           Delete_Tags
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Delete_Bucket_Tagging_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Delete_Tags;

   function Delete_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Tags_Outcome
   is
      Parameters : constant Low_Level.Delete_Bucket_Tagging_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
   begin
      declare
         Result : constant Delete_Bucket_Tagging_Result :=
           Delete_Tags
             (Client, Origin, Bucket, Parameters, Identity, Region, Style,
              Timeout, Token);
      begin
         if Result.Kind = Delete_Bucket_Tagging_Exchange_Failed then
            Raise_Bucket_Tagging_Exchange_Failure
              (Result.HTTP_Result, "DeleteBucketTagging");
         end if;
         declare
            Outcome : Low_Level.Delete_Bucket_Tagging_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Delete_Bucket_Tagging_Rejected then
               return
                 (Kind => Delete_Tags_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return (Kind => Tags_Deleted, Status => Outcome.Status);
         end;
      end;
   end Delete_Tags;

   function Set_Versioning_Configuration
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Versioning_Result
   is
      --  The versioning parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Put_Bucket_Versioning_Operation :=
           Set_Versioning_Configuration
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Token);
         Result    : Put_Bucket_Versioning_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Set_Versioning_Configuration;

   procedure Raise_Put_Bucket_Versioning_Exchange_Failure
     (Result : Put_Bucket_Versioning_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error
              with "unreachable complete PutBucketVersioning failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with
              "HTTP request was rejected: " & US.To_String (Result.Detail);
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid
            | Flyology.HTTP.Client.Response_Body_Too_Large
            | Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "PutBucketVersioning response is invalid or exceeds XML limit";
      end case;
   end Raise_Put_Bucket_Versioning_Exchange_Failure;

   function Set_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Versioning : Configurable_Versioning_Status;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Set_Versioning_Outcome
   is
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
   begin
      Parameters.Configuration.Status := Versioning;
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      declare
         Result : constant Put_Bucket_Versioning_Result :=
           Set_Versioning_Configuration
             (Client, Origin, Bucket, Parameters, Identity, Region, Style,
              Timeout, Token);
      begin
         if Result.Kind = Put_Bucket_Versioning_Exchange_Failed then
            Raise_Put_Bucket_Versioning_Exchange_Failure (Result);
         end if;
         declare
            Outcome : Low_Level.Put_Bucket_Versioning_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Put_Bucket_Versioning_Rejected then
               return
                 (Kind => Set_Versioning_Rejected,
                  Status => Outcome.Status, Error => Outcome.Error);
            end if;
            return
              (Kind => Versioning_Updated, Status => Outcome.Status);
         end;
      end;
   end Set_Versioning;

   function Set_Versioning_Configuration
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Configuration : Bucket_Versioning_Configuration;
      Identity : Low_Level.Credentials;
      MFA      : String := "";
      Checksum_Algorithm : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Set_Versioning_Outcome
   is
      Parameters : constant Low_Level.Put_Bucket_Versioning_Parameters :=
        (Content_MD5           => US.Null_Unbounded_String,
         Checksum_Algorithm    => US.To_Unbounded_String
           (Checksum_Algorithm),
         MFA                   => US.To_Unbounded_String (MFA),
         Configuration         => Configuration,
         Expected_Bucket_Owner => US.To_Unbounded_String
           (Expected_Bucket_Owner));
      Result : constant Put_Bucket_Versioning_Result :=
        Set_Versioning_Configuration
          (Client, Origin, Bucket, Parameters, Identity, Region, Style,
           Timeout, Token);
   begin
      if Result.Kind = Put_Bucket_Versioning_Exchange_Failed then
         Raise_Put_Bucket_Versioning_Exchange_Failure (Result);
      end if;
      declare
         Outcome : Low_Level.Put_Bucket_Versioning_Outcome renames
           Result.Response;
      begin
         if Outcome.Kind = Low_Level.Put_Bucket_Versioning_Rejected then
            return
              (Kind => Set_Versioning_Rejected,
               Status => Outcome.Status, Error => Outcome.Error);
         end if;
         return (Kind => Versioning_Updated, Status => Outcome.Status);
      end;
   end Set_Versioning_Configuration;

   function Get_Versioning
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Versioning_Result
   is
      --  The versioning parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Bucket_Versioning_Operation :=
           Get_Versioning
             (Set'Access,
              Client'Access,
              Origin,
              Bucket,
              Parameters,
              Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout),
              Region,
              Style,
              Token);
         Result    : Get_Bucket_Versioning_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Versioning;

   procedure Raise_Get_Bucket_Versioning_Exchange_Failure
     (Result : Get_Bucket_Versioning_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error
              with "unreachable complete GetBucketVersioning failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid
            | Flyology.HTTP.Client.Response_Body_Too_Large
            | Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "GetBucketVersioning response is invalid or exceeds XML limit";
      end case;
   end Raise_Get_Bucket_Versioning_Exchange_Failure;

   function Get_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Versioning_Outcome
   is
      Result : constant Get_Bucket_Versioning_Result :=
        Get_Versioning
          (Client,
           Origin,
           Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity,
           Region,
           Style,
           Timeout,
           Token);
   begin
      if Result.Kind = Get_Bucket_Versioning_Exchange_Failed then
         Raise_Get_Bucket_Versioning_Exchange_Failure (Result);
      end if;
      declare
         Outcome : Low_Level.Get_Bucket_Versioning_Outcome renames
           Result.Response;
      begin
         if Outcome.Kind = Low_Level.Get_Bucket_Versioning_Rejected then
            return
              (Kind => Get_Versioning_Rejected,
               Status => Outcome.Status, Error => Outcome.Error);
         end if;
         return
           (Kind          => Versioning_Found,
            Status        => Outcome.Status,
            Configuration => Outcome.Configuration);
      end;
   end Get_Versioning;

   function Create_Session
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Session_Mode : String := "";
      Server_Side_Encryption : String := "";
      SSE_KMS_Key_ID : String := "";
      SSE_KMS_Encryption_Context : String := "";
      Bucket_Key_Enabled : Low_Level.Optional_Boolean := (others => <>);
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Virtual_Hosted_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Low_Level.Create_Session_Outcome
   is
      Parameters : constant Low_Level.Create_Session_Parameters :=
        (Session_Mode => US.To_Unbounded_String (Session_Mode),
         Server_Side_Encryption =>
           US.To_Unbounded_String (Server_Side_Encryption),
         SSE_KMS_Key_ID => US.To_Unbounded_String (SSE_KMS_Key_ID),
         SSE_KMS_Encryption_Context =>
           US.To_Unbounded_String (SSE_KMS_Encryption_Context),
         Bucket_Key_Enabled => Bucket_Key_Enabled);
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Session
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Create_Session
        (Client, Prepared, Timeout, Token);
   end Create_Session;

   function Normalize_List_Buckets_Response
     (Value     : Low_Level.List_Buckets_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Buckets_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.List_Buckets_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Buckets_Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => List_Buckets_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Buckets_Response;

   function Normalize_List_Buckets_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Buckets_Result is
   begin
      return
        (Kind        => List_Buckets_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Buckets_Failure;

   overriding procedure Write
     (Item : in out List_Buckets_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListBuckets response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Buckets_Child
     (Item : in out List_Buckets_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Buckets_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Buckets_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Buckets_Response
              (Low_Level.Decode_List_Buckets_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Buckets_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Buckets_Child;

   overriding procedure Drive
     (Item : in out List_Buckets_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.List_Buckets
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Buckets_Child (Item);
      else
         raise Program_Error with "invalid ListBuckets driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Buckets_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Buckets_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Buckets
     (Operation : in out List_Buckets_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListBuckets restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Buckets
        (Origin, Style, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained ListBuckets bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Buckets;

   function List_Page
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Buckets_Operation is
   begin
      return Result : List_Buckets_Operation (Set, Client, Token) do
         Start_List_Buckets
           (Result, Client, Origin, Parameters, Identity, Deadline, Region,
            Style, Token);
      end return;
   end List_Page;

   procedure Finish
     (Operation : in out List_Buckets_Operation;
      Result    : out List_Buckets_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "ListBuckets has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. A complete response is
   --  conclusive only when it proves success or a rejection that could not
   --  have created the requested bucket. No classification authorizes retry.
   function Normalize_Create_Bucket_Response
     (Value     : Low_Level.Create_Bucket_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Create_Bucket_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Create_Bucket_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in "IllegalLocationConstraintException" |
           "InvalidArgument" | "InvalidBucketName" |
           "InvalidLocationConstraint" | "InvalidRequest" | "MalformedXML")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else
          (Value.Status = 409
           and then Code in "BucketAlreadyExists" |
             "BucketAlreadyOwnedByYou" | "TooManyBuckets")
        or else (Value.Status = 501 and then Code = "NotImplemented");
      Retryable_Response : constant Boolean :=
        (Value.Status = 409 and then Code = "OperationAborted")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout");
      Failure : constant Failure_Reason :=
        (if Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Conclusive_Rejection
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Create_Bucket_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Creation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Created
            then Bucket_Creation_Completed
            elsif Conclusive_Rejection
            then Bucket_Definitely_Not_Created
            else Bucket_Creation_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Created
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Create_Bucket_Response;

   function Normalize_Create_Bucket_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Create_Bucket_Result is
   begin
      return
        (Kind        => Create_Bucket_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Bucket_Creation_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Bucket_Definitely_Not_Created
            else Bucket_Creation_Outcome_Unknown),
         Failure     =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Create_Bucket_Failure;

   overriding function Declared_Length
     (Item : Create_Bucket_Operation) return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Item.Prepared)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Create_Bucket_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural :=
        Low.Owned_Payload_Length (Item.Prepared);
      Count : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Item.Prepared, Item.Source_Position + Offset + 1)));
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Create_Bucket_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Create_Bucket_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Create_Bucket_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "CreateBucket response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Create_Bucket_Child
     (Item : in out Create_Bucket_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Create_Bucket_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Create_Bucket_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Create_Bucket_Response
              (Low_Level.Decode_Create_Bucket_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data)),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Create_Bucket_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Create_Bucket_Child;

   overriding procedure Drive
     (Item : in out Create_Bucket_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Create_Bucket
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Create_Bucket_Child (Item);
      else
         raise Program_Error with "invalid CreateBucket driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Create_Bucket_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Create_Bucket_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Create_Bucket
     (Operation : in out Create_Bucket_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "CreateBucket restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Create_Bucket
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived bound: retained response bytes use the maintained limit of
        --  the S3 XML decoder that consumes the response.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Create_Bucket;

   function Create
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Bucket_Operation is
   begin
      return Result : Create_Bucket_Operation (Set, Client, Token) do
         Start_Create_Bucket
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end Create;

   procedure Finish
     (Operation : in out Create_Bucket_Operation;
      Result    : out Create_Bucket_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "CreateBucket has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. A complete response is
   --  conclusive only when it proves success or a rejection that could not
   --  have applied this DeleteBucket request. No classification retries it.
   function Normalize_Delete_Bucket_Response
     (Value     : Low_Level.Delete_Bucket_Outcome;
      Admission : HTTP_Client.Admission_Certainty) return Delete_Bucket_Result
   is
      Code                 : constant String :=
        (if Value.Kind = Low_Level.Delete_Bucket_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in "InvalidBucketName" | "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else (Value.Status = 404 and then Code = "NoSuchBucket")
        or else (Value.Status = 409 and then Code = "BucketNotEmpty")
        or else (Value.Status = 501 and then Code = "NotImplemented");
      Retryable_Response   : constant Boolean :=
        (Value.Status = 409 and then Code = "OperationAborted")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout");
      Failure              : constant Failure_Reason :=
        (if Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif Conclusive_Rejection
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Delete_Bucket_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Deletion_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Deleted
            then Bucket_Deletion_Completed
            elsif Conclusive_Rejection
            then Bucket_Definitely_Not_Deleted
            else Bucket_Deletion_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Deleted
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Delete_Bucket_Response;

   function Normalize_Delete_Bucket_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Result is
   begin
      return
        (Kind        => Delete_Bucket_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Bucket_Deletion_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Bucket_Definitely_Not_Deleted
            else Bucket_Deletion_Outcome_Unknown),
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Bucket_Failure;

   overriding
   function Declared_Length
     (Item : Delete_Bucket_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  S3 DeleteBucket has no request payload. This zero is the operation's
      --  wire contract, not an independently selected resource limit.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding
   procedure Read_Now
     (Item   : in out Delete_Bucket_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding
   procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding
   procedure Release_Source (Item : in out Delete_Bucket_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding
   procedure Write
     (Item : in out Delete_Bucket_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded
           with "DeleteBucket response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Delete_Bucket_Child
     (Item : in out Delete_Bucket_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Delete_Bucket_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Delete_Bucket_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Delete_Bucket_Response
                (Low_Level.Decode_Delete_Bucket_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2")),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Delete_Bucket_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Bucket_Child;

   overriding
   procedure Drive
     (Item : in out Delete_Bucket_Operation; Event : Operations.Driver_Event)
   is
   begin
      if Event = Operations.Start_Operation then
         Low.Delete_Bucket
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Bucket_Child (Item);
      else
         raise Program_Error with "invalid DeleteBucket driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding
   procedure Request_Cancellation (Item : in out Delete_Bucket_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding
   procedure Finalize (Item : in out Delete_Bucket_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Bucket
     (Operation  : in out Delete_Bucket_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error
           with "DeleteBucket restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Delete_Bucket
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained DeleteBucket error bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Bucket;

   function Delete
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Operation is
   begin
      return Result : Delete_Bucket_Operation (Set, Client, Token) do
         Start_Delete_Bucket
           (Result,
            Client,
            Origin,
            Bucket,
            Parameters,
            Identity,
            Deadline,
            Region,
            Style,
            Token);
      end return;
   end Delete;

   procedure Finish
     (Operation : in out Delete_Bucket_Operation;
      Result    : out Delete_Bucket_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "DeleteBucket has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Status values below are the externally modeled bodyless HeadBucket
   --  response surface. This read-only classification authorizes no retry.
   function Normalize_Head_Bucket_Response
     (Value     : Low_Level.Head_Bucket_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Head_Bucket_Result
   is
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Bucket_Found
         then No_Failure
         elsif Value.Status in 301 | 307 | 400 | 501
         then Invalid_Request
         elsif Value.Status = 401
         then Authentication_Failed
         elsif Value.Status = 403
         then Authorization_Failed
         elsif Value.Status = 404
         then Not_Found
         elsif Value.Status in 409 | 429 | 500 | 502 | 503 | 504
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Head_Bucket_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Head_Bucket_Response;

   function Normalize_Head_Bucket_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Head_Bucket_Result is
   begin
      return
        (Kind        => Head_Bucket_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Head_Bucket_Failure;

   overriding procedure Write
     (Item : in out Head_Bucket_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      pragma Unreferenced (Item);
      if Data'Length > 0 then
         raise Response_Limit_Exceeded with
           "HeadBucket response contains a body";
      end if;
   end Write;

   procedure Complete_Head_Bucket_Child
     (Item : in out Head_Bucket_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Head_Bucket_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Head_Bucket_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Head_Bucket_Response
              (Low_Level.Decode_Head_Bucket_Complete_Response (Response, ""),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Head_Bucket_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Head_Bucket_Child;

   overriding procedure Drive
     (Item : in out Head_Bucket_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Head_Bucket
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Head_Bucket_Child (Item);
      else
         raise Program_Error with "invalid HeadBucket driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Head_Bucket_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Head_Bucket_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
   end Finalize;

   procedure Start_Head_Bucket
     (Operation : in out Head_Bucket_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "HeadBucket restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Head_Bucket
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Head_Bucket;

   function Head
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Bucket_Operation is
   begin
      return Result : Head_Bucket_Operation (Set, Client, Token) do
         Start_Head_Bucket
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end Head;

   procedure Finish
     (Operation : in out Head_Bucket_Operation;
      Result    : out Head_Bucket_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "HeadBucket has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are the maintained S3 GetBucketPolicy error
   --  surface. This read-only classification authorizes no mutation or retry.
   function Normalize_Get_Bucket_Policy_Response
     (Value     : Low_Level.Get_Bucket_Policy_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Bucket_Policy_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Bucket_Control_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Bucket_Control_Found
         then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchBucketPolicy"
         then Not_Found
         elsif Value.Status = 400
           and then Code in "InvalidBucketName" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Get_Bucket_Policy_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Get_Bucket_Policy_Response;

   function Normalize_Get_Bucket_Policy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Policy_Result is
   begin
      return
        (Kind        => Get_Bucket_Policy_Exchange_Failed,
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Get_Bucket_Policy_Failure;

   overriding procedure Write
     (Item : in out Get_Bucket_Policy_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded
           with "GetBucketPolicy response exceeds the caller-selected limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Get_Bucket_Policy_Child
     (Item : in out Get_Bucket_Policy_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Get_Bucket_Policy_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Get_Bucket_Policy_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Get_Bucket_Policy_Response
                (Low_Level.Decode_Get_Bucket_Policy_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2"),
                    Item.Limits),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Get_Bucket_Policy_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Bucket_Policy_Child;

   overriding procedure Drive
     (Item  : in out Get_Bucket_Policy_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Bucket_Policy
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Bucket_Policy_Child (Item);
      else
         raise Program_Error with "invalid GetBucketPolicy driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Policy_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Bucket_Policy_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Bucket_Policy
     (Operation  : in out Get_Bucket_Policy_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error
           with "GetBucketPolicy restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Get_Bucket_Policy
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Limits := Limits;
      Flyology.Bytes.Clear (Operation.Response_Data);
      --  Caller-selected policy/error bound; this is the same field consumed
      --  by the existing synchronous decoder and introduces no new ceiling.
      Operation.Response_Limit := Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Bucket_Policy;

   function Get_Policy
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Policy_Operation is
   begin
      return Result : Get_Bucket_Policy_Operation (Set, Client, Token) do
         Start_Get_Bucket_Policy
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Limits, Token);
      end return;
   end Get_Policy;

   procedure Finish
     (Operation : in out Get_Bucket_Policy_Operation;
      Result    : out Get_Bucket_Policy_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetBucketPolicy has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  The pinned S3 operation/error model and maintained signed-response
   --  corpus establish these exact status/code pairs as the conclusive and
   --  retryable bucket-policy surface. Unknown responses stay outcome-unknown
   --  and never authorize automatic mutation replay; changing this list
   --  changes caller-visible publication certainty.
   function Conclusive_Bucket_Policy_Rejection
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 400
       and then Code in "BadDigest" | "InvalidArgument" | "InvalidDigest" |
         "InvalidRequest" | "XAmzContentSHA256Mismatch")
      or else (Status = 401 and then Code = "InvalidAccessKeyId")
      or else (Status = 403 and then Code = "AccessDenied")
      or else (Status = 404 and then Code = "NoSuchBucket")
      or else (Status = 501 and then Code = "NotImplemented"));

   function Retryable_Bucket_Policy_Response
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 409 and then Code = "OperationAborted")
      or else (Status = 429 and then Code = "SlowDown")
      or else (Status = 500 and then Code = "InternalError")
      or else (Status = 502 and then Code = "BadGateway")
      or else (Status = 503 and then Code = "SlowDown")
      or else (Status = 504 and then Code = "RequestTimeout"));

   function Bucket_Policy_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 401 and then Code = "InvalidAccessKeyId"
      then Authentication_Failed
      elsif Status = 403 and then Code = "AccessDenied"
      then Authorization_Failed
      elsif Status = 404 and then Code = "NoSuchBucket"
      then Not_Found
      elsif Conclusive_Bucket_Policy_Rejection (Status, Code)
      then Invalid_Request
      elsif Retryable_Bucket_Policy_Response (Status, Code)
      then Unavailable_Or_Retryable
      else Corrupt_Or_Invalid_Response);

   function Failed_Bucket_Policy_Mutation_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Bucket_Policy_Mutation_Disposition is
     (if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then Bucket_Policy_Mutation_Cancelled_Before_Admission
      elsif Admission = HTTP_Client.Not_Admitted
      then Bucket_Policy_Mutation_Definitely_Not_Applied
      else Bucket_Policy_Mutation_Outcome_Unknown);

   function Normalize_Put_Bucket_Policy_Response
     (Value     : Low_Level.Put_Bucket_Control_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Put_Bucket_Policy_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Bucket_Control_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Conclusive : constant Boolean :=
        Conclusive_Bucket_Policy_Rejection (Value.Status, Code);
   begin
      return
        (Kind        => Put_Bucket_Policy_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Policy_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Control_Updated
            then Bucket_Policy_Mutation_Completed
            elsif Conclusive
            then Bucket_Policy_Mutation_Definitely_Not_Applied
            else Bucket_Policy_Mutation_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Control_Updated
            then No_Failure
            else Bucket_Policy_Response_Failure (Value.Status, Code)),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Put_Bucket_Policy_Response;

   function Normalize_Put_Bucket_Policy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Policy_Result is
   begin
      return
        (Kind        => Put_Bucket_Policy_Exchange_Failed,
         Disposition =>
           Failed_Bucket_Policy_Mutation_Disposition (Kind, Admission),
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Put_Bucket_Policy_Failure;

   overriding function Declared_Length
     (Item : Put_Bucket_Policy_Operation)
      return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Item.Prepared))));

   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Policy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural := Low.Owned_Payload_Length (Item.Prepared);
      Count  : constant Natural :=
        Natural'Min
          (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Item.Prepared, Item.Source_Position + Offset + 1)));
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Policy_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Put_Bucket_Policy_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Put_Bucket_Policy_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "PutBucketPolicy response exceeds the caller-selected limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Put_Bucket_Policy_Child
     (Item : in out Put_Bucket_Policy_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Put_Bucket_Policy_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Put_Bucket_Policy_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Put_Bucket_Policy_Response
                (Low_Level.Decode_Put_Bucket_Control_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2"),
                    Item.Limits),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Put_Bucket_Policy_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Put_Bucket_Policy_Child;

   overriding procedure Drive
     (Item  : in out Put_Bucket_Policy_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Bucket_Policy
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Put_Bucket_Policy_Child (Item);
      else
         raise Program_Error with "invalid PutBucketPolicy driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Policy_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Put_Bucket_Policy_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put_Bucket_Policy
     (Operation  : in out Put_Bucket_Policy_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "PutBucketPolicy restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Put_Bucket_Policy
          (Origin, Style, Bucket, Policy, Parameters, Identity, Region,
           Timestamp, Limits);
      Operation.Deadline := Deadline;
      Operation.Limits := Limits;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      --  Caller-selected policy/error bound; this is the same field consumed
      --  by request validation and the established synchronous decoder.
      Operation.Response_Limit := Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Put_Bucket_Policy;

   function Set_Policy
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Policy_Operation is
   begin
      return Result : Put_Bucket_Policy_Operation (Set, Client, Token) do
         Start_Put_Bucket_Policy
           (Result, Client, Origin, Bucket, Policy, Parameters, Identity,
            Deadline, Region, Style, Limits, Token);
      end return;
   end Set_Policy;

   procedure Finish
     (Operation : in out Put_Bucket_Policy_Operation;
      Result    : out Put_Bucket_Policy_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutBucketPolicy has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Delete_Bucket_Policy_Response
     (Value     : Low_Level.Delete_Bucket_Configuration_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Delete_Bucket_Policy_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Delete_Configuration_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Conclusive : constant Boolean :=
        Conclusive_Bucket_Policy_Rejection (Value.Status, Code);
   begin
      return
        (Kind        => Delete_Bucket_Policy_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Policy_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Configuration_Deleted
            then Bucket_Policy_Mutation_Completed
            elsif Conclusive
            then Bucket_Policy_Mutation_Definitely_Not_Applied
            else Bucket_Policy_Mutation_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Configuration_Deleted
            then No_Failure
            else Bucket_Policy_Response_Failure (Value.Status, Code)),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Delete_Bucket_Policy_Response;

   function Normalize_Delete_Bucket_Policy_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Policy_Result is
   begin
      return
        (Kind        => Delete_Bucket_Policy_Exchange_Failed,
         Disposition =>
           Failed_Bucket_Policy_Mutation_Disposition (Kind, Admission),
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Bucket_Policy_Failure;

   overriding function Declared_Length
     (Item : Delete_Bucket_Policy_Operation)
      return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  S3 DeleteBucketPolicy has no modeled request payload. Zero is the
      --  protocol-derived wire length, not a selectable buffering policy.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Policy_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Data'First - 1;
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Policy_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Policy_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Delete_Bucket_Policy_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "DeleteBucketPolicy response exceeds the caller-selected limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Delete_Bucket_Policy_Child
     (Item : in out Delete_Bucket_Policy_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Delete_Bucket_Policy_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Delete_Bucket_Policy_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Delete_Bucket_Policy_Response
                (Low_Level.Decode_Delete_Bucket_Configuration_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2"),
                    Item.Limits),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Delete_Bucket_Policy_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Bucket_Policy_Child;

   overriding procedure Drive
     (Item  : in out Delete_Bucket_Policy_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Delete_Bucket_Policy
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Bucket_Policy_Child (Item);
      else
         raise Program_Error with "invalid DeleteBucketPolicy driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Policy_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Delete_Bucket_Policy_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Bucket_Policy
     (Operation  : in out Delete_Bucket_Policy_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "DeleteBucketPolicy restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Delete_Bucket_Policy
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Limits := Limits;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit := Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Bucket_Policy;

   function Delete_Policy
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Policy_Operation is
   begin
      return Result : Delete_Bucket_Policy_Operation (Set, Client, Token) do
         Start_Delete_Bucket_Policy
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Limits, Token);
      end return;
   end Delete_Policy;

   procedure Finish
     (Operation : in out Delete_Bucket_Policy_Operation;
      Result    : out Delete_Bucket_Policy_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "DeleteBucketPolicy has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are the maintained S3 GetBucketLocation error
   --  surface. This read-only classification authorizes no mutation or retry.
   function Normalize_Get_Bucket_Location_Response
     (Value     : Low_Level.Get_Bucket_Location_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Bucket_Location_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Bucket_Location_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Bucket_Location_Found
         then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif Value.Status = 400
           and then Code in "InvalidBucketName" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Get_Bucket_Location_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Get_Bucket_Location_Response;

   function Normalize_Get_Bucket_Location_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Location_Result is
   begin
      return
        (Kind        => Get_Bucket_Location_Exchange_Failed,
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Get_Bucket_Location_Failure;

   overriding procedure Write
     (Item : in out Get_Bucket_Location_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded
           with "GetBucketLocation response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Get_Bucket_Location_Child
     (Item : in out Get_Bucket_Location_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Get_Bucket_Location_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Get_Bucket_Location_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Get_Bucket_Location_Response
                (Low_Level.Decode_Get_Bucket_Location_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2")),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Get_Bucket_Location_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Bucket_Location_Child;

   overriding procedure Drive
     (Item  : in out Get_Bucket_Location_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Bucket_Location
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Bucket_Location_Child (Item);
      else
         raise Program_Error with "invalid GetBucketLocation driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Location_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Bucket_Location_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Bucket_Location
     (Operation  : in out Get_Bucket_Location_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error
           with "GetBucketLocation restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Get_Bucket_Location
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained response bytes use the maintained
        --  limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Bucket_Location;

   function Get_Location
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Location_Operation is
   begin
      return Result : Get_Bucket_Location_Operation (Set, Client, Token) do
         Start_Get_Bucket_Location
           (Result,
            Client,
            Origin,
            Bucket,
            Parameters,
            Identity,
            Deadline,
            Region,
            Style,
            Token);
      end return;
   end Get_Location;

   procedure Finish
     (Operation : in out Get_Bucket_Location_Operation;
      Result    : out Get_Bucket_Location_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetBucketLocation has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are the maintained S3 GetBucketVersioning
   --  error surface. This read-only classification authorizes no mutation or
   --  retry and describes only one completed response.
   function Normalize_Get_Bucket_Versioning_Response
     (Value     : Low_Level.Get_Bucket_Versioning_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Bucket_Versioning_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Bucket_Versioning_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Bucket_Versioning_Found
         then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif Value.Status = 400
           and then Code in "InvalidBucketName" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Get_Bucket_Versioning_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Get_Bucket_Versioning_Response;

   function Normalize_Get_Bucket_Versioning_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Versioning_Result is
   begin
      return
        (Kind        => Get_Bucket_Versioning_Exchange_Failed,
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Get_Bucket_Versioning_Failure;

   overriding procedure Write
     (Item : in out Get_Bucket_Versioning_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded
           with "GetBucketVersioning response exceeds its XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Get_Bucket_Versioning_Child
     (Item : in out Get_Bucket_Versioning_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Get_Bucket_Versioning_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Get_Bucket_Versioning_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Get_Bucket_Versioning_Response
                (Low_Level.Decode_Get_Bucket_Versioning_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2")),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Get_Bucket_Versioning_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Bucket_Versioning_Child;

   overriding procedure Drive
     (Item  : in out Get_Bucket_Versioning_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Bucket_Versioning
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Bucket_Versioning_Child (Item);
      else
         raise Program_Error with "invalid GetBucketVersioning driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Versioning_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Bucket_Versioning_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Bucket_Versioning
     (Operation  : in out Get_Bucket_Versioning_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error
           with "GetBucketVersioning restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Get_Bucket_Versioning
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained bytes use the maintained limit
        --  of the versioning XML decoder that consumes them.
        Flyology.Object_Storage.S3.Versioning.Default_Limits
          .Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Bucket_Versioning;

   function Get_Versioning
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Versioning_Operation is
   begin
      return Result : Get_Bucket_Versioning_Operation (Set, Client, Token) do
         Start_Get_Bucket_Versioning
           (Result,
            Client,
            Origin,
            Bucket,
            Parameters,
            Identity,
            Deadline,
            Region,
            Style,
            Token);
      end return;
   end Get_Versioning;

   procedure Finish
     (Operation : in out Get_Bucket_Versioning_Operation;
      Result    : out Get_Bucket_Versioning_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetBucketVersioning has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  These exact S3 status/code pairs are the maintained
   --  PutBucketVersioning response contract. Unknown responses remain
   --  ambiguous and no classification authorizes mutation replay.
   function Conclusive_Bucket_Versioning_Rejection
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 400
       and then Code in "BadDigest" | "InvalidArgument" | "InvalidDigest" |
         "InvalidRequest" | "MalformedXML" | "XAmzContentSHA256Mismatch")
      or else (Status = 401 and then Code = "InvalidAccessKeyId")
      or else (Status = 403 and then Code = "AccessDenied")
      or else (Status = 404 and then Code = "NoSuchBucket")
      or else (Status = 501 and then Code = "NotImplemented"));

   function Retryable_Bucket_Versioning_Response
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 409 and then Code = "OperationAborted")
      or else (Status = 429 and then Code = "SlowDown")
      or else (Status = 500 and then Code = "InternalError")
      or else (Status = 502 and then Code = "BadGateway")
      or else (Status = 503 and then Code = "SlowDown")
      or else (Status = 504 and then Code = "RequestTimeout"));

   function Bucket_Versioning_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 401 and then Code = "InvalidAccessKeyId"
      then Authentication_Failed
      elsif Status = 403 and then Code = "AccessDenied"
      then Authorization_Failed
      elsif Status = 404 and then Code = "NoSuchBucket"
      then Not_Found
      elsif Conclusive_Bucket_Versioning_Rejection (Status, Code)
      then Invalid_Request
      elsif Retryable_Bucket_Versioning_Response (Status, Code)
      then Unavailable_Or_Retryable
      else Corrupt_Or_Invalid_Response);

   function Failed_Bucket_Versioning_Mutation_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Bucket_Versioning_Mutation_Disposition is
     (if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then Bucket_Versioning_Mutation_Cancelled_Before_Admission
      elsif Admission = HTTP_Client.Not_Admitted
      then Bucket_Versioning_Mutation_Definitely_Not_Applied
      else Bucket_Versioning_Mutation_Outcome_Unknown);

   function Normalize_Put_Bucket_Versioning_Response
     (Value     : Low_Level.Put_Bucket_Versioning_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Put_Bucket_Versioning_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Bucket_Versioning_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Conclusive : constant Boolean :=
        Conclusive_Bucket_Versioning_Rejection (Value.Status, Code);
   begin
      return
        (Kind        => Put_Bucket_Versioning_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Versioning_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Versioning_Updated
            then Bucket_Versioning_Mutation_Completed
            elsif Conclusive
            then Bucket_Versioning_Mutation_Definitely_Not_Applied
            else Bucket_Versioning_Mutation_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Versioning_Updated
            then No_Failure
            else Bucket_Versioning_Response_Failure (Value.Status, Code)),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Put_Bucket_Versioning_Response;

   function Normalize_Put_Bucket_Versioning_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Versioning_Result is
   begin
      return
        (Kind        => Put_Bucket_Versioning_Exchange_Failed,
         Disposition =>
           Failed_Bucket_Versioning_Mutation_Disposition (Kind, Admission),
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Put_Bucket_Versioning_Failure;

   overriding function Declared_Length
     (Item : Put_Bucket_Versioning_Operation)
      return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Item.Prepared))));

   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Versioning_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural := Low.Owned_Payload_Length (Item.Prepared);
      Count  : constant Natural :=
        Natural'Min
          (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Item.Prepared, Item.Source_Position + Offset + 1)));
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Versioning_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Put_Bucket_Versioning_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Put_Bucket_Versioning_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "PutBucketVersioning response exceeds its XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Put_Bucket_Versioning_Child
     (Item : in out Put_Bucket_Versioning_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Put_Bucket_Versioning_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Put_Bucket_Versioning_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Put_Bucket_Versioning_Response
                (Low_Level.Decode_Put_Bucket_Versioning_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    HTTP_Client.Header (Response, "x-amz-request-id"),
                    HTTP_Client.Header (Response, "x-amz-id-2")),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Put_Bucket_Versioning_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Put_Bucket_Versioning_Child;

   overriding procedure Drive
     (Item  : in out Put_Bucket_Versioning_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Bucket_Versioning
           (Item.HTTP,
            Item.Prepared'Access,
            Item'Access,
            Item'Access,
            Item.Deadline,
            Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Put_Bucket_Versioning_Child (Item);
      else
         raise Program_Error with "invalid PutBucketVersioning driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Versioning_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Put_Bucket_Versioning_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put_Bucket_Versioning
     (Operation  : in out Put_Bucket_Versioning_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "PutBucketVersioning restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Put_Bucket_Versioning
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained bytes use the maintained limit
        --  of the versioning XML/error decoder that consumes them.
        Flyology.Object_Storage.S3.Versioning.Default_Limits
          .Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Put_Bucket_Versioning;

   function Set_Versioning_Configuration
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Versioning_Operation is
   begin
      return Result : Put_Bucket_Versioning_Operation (Set, Client, Token) do
         Start_Put_Bucket_Versioning
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end Set_Versioning_Configuration;

   procedure Finish
     (Operation : in out Put_Bucket_Versioning_Operation;
      Result    : out Put_Bucket_Versioning_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutBucketVersioning has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListObjectsV2 attempt; it
   --  does not authorize retry or imply a shared snapshot with a later page.
   --  These exact status/code pairs are the maintained S3 bucket-tagging
   --  response contract. Unpaired or unknown responses remain ambiguous.
   function Conclusive_Bucket_Tag_Rejection
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 400
       and then Code in "BadDigest" | "InvalidArgument" | "InvalidDigest" |
         "InvalidRequest" | "InvalidTag" | "MalformedXML" |
         "XAmzContentSHA256Mismatch")
      or else (Status = 401 and then Code = "InvalidAccessKeyId")
      or else (Status = 403 and then Code = "AccessDenied")
      or else (Status = 404 and then Code = "NoSuchBucket")
      or else (Status = 501 and then Code = "NotImplemented"));

   function Retryable_Bucket_Tag_Response
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 409 and then Code = "OperationAborted")
      or else (Status = 429 and then Code = "SlowDown")
      or else (Status = 500 and then Code = "InternalError")
      or else (Status = 502 and then Code = "BadGateway")
      or else (Status = 503 and then Code = "SlowDown")
      or else (Status = 504 and then Code = "RequestTimeout"));

   function Bucket_Tag_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 401 and then Code = "InvalidAccessKeyId"
      then Authentication_Failed
      elsif Status = 403 and then Code = "AccessDenied"
      then Authorization_Failed
      elsif Status = 404 and then Code = "NoSuchBucket"
      then Not_Found
      elsif Conclusive_Bucket_Tag_Rejection (Status, Code)
      then Invalid_Request
      elsif Retryable_Bucket_Tag_Response (Status, Code)
      then Unavailable_Or_Retryable
      else Corrupt_Or_Invalid_Response);

   function Bucket_Tag_Read_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 404 and then Code = "NoSuchTagSet"
      then Not_Found
      else Bucket_Tag_Response_Failure (Status, Code));

   function Failed_Bucket_Tag_Mutation_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Bucket_Tag_Mutation_Disposition is
     (if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then Bucket_Tag_Mutation_Cancelled_Before_Admission
      elsif Admission = HTTP_Client.Not_Admitted
      then Bucket_Tag_Mutation_Definitely_Not_Applied
      else Bucket_Tag_Mutation_Outcome_Unknown);

   function Normalize_Put_Bucket_Tagging_Response
     (Value     : Low_Level.Put_Bucket_Tagging_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Put_Bucket_Tagging_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Bucket_Tagging_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive : constant Boolean :=
        Conclusive_Bucket_Tag_Rejection (Value.Status, Code);
   begin
      return
        (Kind => Put_Bucket_Tagging_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Tag_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Tags_Replaced
            then Bucket_Tag_Mutation_Completed
            elsif Conclusive
            then Bucket_Tag_Mutation_Definitely_Not_Applied
            else Bucket_Tag_Mutation_Outcome_Unknown),
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Tags_Replaced
            then No_Failure
            else Bucket_Tag_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Put_Bucket_Tagging_Response;

   function Normalize_Put_Bucket_Tagging_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Put_Bucket_Tagging_Result is
   begin
      return
        (Kind => Put_Bucket_Tagging_Exchange_Failed,
         Disposition =>
           Failed_Bucket_Tag_Mutation_Disposition (Kind, Admission),
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Put_Bucket_Tagging_Failure;

   function Owned_Tagging_Length
     (Prepared : Low_Level.Prepared_Request) return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Prepared))));

   procedure Read_Owned_Tagging_Source
     (Prepared : Low_Level.Prepared_Request;
      Position : in out Natural;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Result   : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural :=
        Low.Owned_Payload_Length (Prepared);
      Count : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Prepared, Position + Offset + 1)));
      end loop;
      Position := Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Owned_Tagging_Source;

   procedure Append_Tagging_Response
     (Target : in out Flyology.Bytes.Unbounded_Bytes;
      Limit  : Natural;
      Data   : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) > Limit - Flyology.Bytes.Length (Target) then
         raise Response_Limit_Exceeded with
           "tagging response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Target, Data);
   end Append_Tagging_Response;

   overriding function Declared_Length
     (Item : Put_Bucket_Tagging_Operation) return HTTP_Client.Body_Length is
     (Owned_Tagging_Length (Item.Prepared));

   overriding procedure Read_Now
     (Item   : in out Put_Bucket_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      Read_Owned_Tagging_Source
        (Item.Prepared, Item.Source_Position, Data, Last, Result);
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Put_Bucket_Tagging_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Put_Bucket_Tagging_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Put_Bucket_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Tagging_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Put_Bucket_Tagging_Child
     (Item : in out Put_Bucket_Tagging_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Put_Bucket_Tagging_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Put_Bucket_Tagging_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Put_Bucket_Tagging_Response
              (Low_Level.Decode_Put_Bucket_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  (Request_Charged => US.To_Unbounded_String
                     (HTTP_Client.Header
                        (Response, "x-amz-request-charged"))),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Bucket_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Put_Bucket_Tagging_Child;

   overriding procedure Drive
     (Item : in out Put_Bucket_Tagging_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Bucket_Tagging
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Put_Bucket_Tagging_Child (Item);
      else
         raise Program_Error with "invalid PutBucketTagging driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Put_Bucket_Tagging_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Put_Bucket_Tagging_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put_Bucket_Tagging
     (Operation : in out Put_Bucket_Tagging_Operation;
      Client    : not null access HTTP_Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Value     : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : HTTP_Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "PutBucketTagging restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Put_Bucket_Tagging
        (Origin, Style, Bucket, Value, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Put_Bucket_Tagging;

   function Put_Tags
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Value      : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Bucket_Tagging_Operation is
   begin
      return Result : Put_Bucket_Tagging_Operation (Set, Client, Token) do
         Start_Put_Bucket_Tagging
           (Result, Client, Origin, Bucket, Value, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Put_Tags;

   procedure Finish
     (Operation : in out Put_Bucket_Tagging_Operation;
      Result    : out Put_Bucket_Tagging_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutBucketTagging has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Get_Bucket_Tagging_Response
     (Value     : Low_Level.Get_Bucket_Tagging_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Bucket_Tagging_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Bucket_Tagging_Rejected
         then US.To_String (Value.Error.Code) else "");
   begin
      return
        (Kind => Get_Bucket_Tagging_Response_Available,
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Tags_Found
            then No_Failure
            else Bucket_Tag_Read_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Get_Bucket_Tagging_Response;

   function Normalize_Get_Bucket_Tagging_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Bucket_Tagging_Result is
   begin
      return
        (Kind => Get_Bucket_Tagging_Exchange_Failed,
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Get_Bucket_Tagging_Failure;

   overriding procedure Write
     (Item : in out Get_Bucket_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Tagging_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Get_Bucket_Tagging_Child
     (Item : in out Get_Bucket_Tagging_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Get_Bucket_Tagging_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Get_Bucket_Tagging_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Get_Bucket_Tagging_Response
              (Low_Level.Decode_Get_Bucket_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  (Value =>
                     Flyology.Object_Storage.Tags.Tag_Vectors.Empty_Vector,
                   Request_Charged => US.To_Unbounded_String
                     (HTTP_Client.Header
                        (Response, "x-amz-request-charged"))),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Get_Bucket_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Bucket_Tagging_Child;

   overriding procedure Drive
     (Item : in out Get_Bucket_Tagging_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Bucket_Tagging
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Bucket_Tagging_Child (Item);
      else
         raise Program_Error with "invalid GetBucketTagging driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Bucket_Tagging_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Bucket_Tagging_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Bucket_Tagging
     (Operation : in out Get_Bucket_Tagging_Operation;
      Client    : not null access HTTP_Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : HTTP_Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "GetBucketTagging restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Get_Bucket_Tagging
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit := Natural'Min
        (Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes,
         Flyology.Object_Storage.S3.Tagging.Maximum_Document_Bytes);
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Bucket_Tagging;

   function Get_Tags
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Bucket_Tagging_Operation is
   begin
      return Result : Get_Bucket_Tagging_Operation (Set, Client, Token) do
         Start_Get_Bucket_Tagging
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end Get_Tags;

   procedure Finish
     (Operation : in out Get_Bucket_Tagging_Operation;
      Result    : out Get_Bucket_Tagging_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetBucketTagging has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Delete_Bucket_Tagging_Response
     (Value     : Low_Level.Delete_Bucket_Tagging_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Delete_Bucket_Tagging_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Delete_Bucket_Tagging_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive : constant Boolean :=
        Conclusive_Bucket_Tag_Rejection (Value.Status, Code);
   begin
      return
        (Kind => Delete_Bucket_Tagging_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Bucket_Tag_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Bucket_Tags_Deleted
            then Bucket_Tag_Mutation_Completed
            elsif Conclusive
            then Bucket_Tag_Mutation_Definitely_Not_Applied
            else Bucket_Tag_Mutation_Outcome_Unknown),
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Bucket_Tags_Deleted
            then No_Failure
            else Bucket_Tag_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Delete_Bucket_Tagging_Response;

   function Normalize_Delete_Bucket_Tagging_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Bucket_Tagging_Result is
   begin
      return
        (Kind => Delete_Bucket_Tagging_Exchange_Failed,
         Disposition =>
           Failed_Bucket_Tag_Mutation_Disposition (Kind, Admission),
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Bucket_Tagging_Failure;

   overriding function Declared_Length
     (Item : Delete_Bucket_Tagging_Operation)
      return HTTP_Client.Body_Length is
     (Owned_Tagging_Length (Item.Prepared));

   overriding procedure Read_Now
     (Item   : in out Delete_Bucket_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      Read_Owned_Tagging_Source
        (Item.Prepared, Item.Source_Position, Data, Last, Result);
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Bucket_Tagging_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Delete_Bucket_Tagging_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Delete_Bucket_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Tagging_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Delete_Bucket_Tagging_Child
     (Item : in out Delete_Bucket_Tagging_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Delete_Bucket_Tagging_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Delete_Bucket_Tagging_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Delete_Bucket_Tagging_Response
              (Low_Level.Decode_Delete_Bucket_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Delete_Bucket_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Bucket_Tagging_Child;

   overriding procedure Drive
     (Item : in out Delete_Bucket_Tagging_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Delete_Bucket_Tagging
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Bucket_Tagging_Child (Item);
      else
         raise Program_Error with "invalid DeleteBucketTagging driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Delete_Bucket_Tagging_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Delete_Bucket_Tagging_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Bucket_Tagging
     (Operation : in out Delete_Bucket_Tagging_Operation;
      Client    : not null access HTTP_Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : HTTP_Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "DeleteBucketTagging restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Delete_Bucket_Tagging
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Bucket_Tagging;

   function Delete_Tags
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Bucket_Tagging_Operation is
   begin
      return Result : Delete_Bucket_Tagging_Operation (Set, Client, Token) do
         Start_Delete_Bucket_Tagging
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end Delete_Tags;

   procedure Finish
     (Operation : in out Delete_Bucket_Tagging_Operation;
      Result    : out Delete_Bucket_Tagging_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "DeleteBucketTagging has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure List_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Parameters : Low_Level.List_Buckets_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Buckets_Operation) is
   begin
      Start_List_Buckets
        (Operation,
         Client,
         Origin,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end List_Page;

   procedure Create
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Create_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Create_Bucket_Operation) is
   begin
      Start_Create_Bucket
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Create;

   procedure Delete
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Operation) is
   begin
      Start_Delete_Bucket
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Delete;

   procedure Head
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.Head_Bucket_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Head_Bucket_Operation) is
   begin
      Start_Head_Bucket
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Head;

   procedure Get_Policy
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Control_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Policy_Operation) is
   begin
      Start_Get_Bucket_Policy
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Limits,
         Token);
   end Get_Policy;

   procedure Set_Policy
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Policy     : String;
      Parameters : Low_Level.Put_Bucket_Policy_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Policy_Operation) is
   begin
      Start_Put_Bucket_Policy
        (Operation,
         Client,
         Origin,
         Bucket,
         Policy,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Limits,
         Token);
   end Set_Policy;

   procedure Delete_Policy
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Delete_Bucket_Configuration_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Bucket_Policy_Operation) is
   begin
      Start_Delete_Bucket_Policy
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Limits,
         Token);
   end Delete_Policy;

   procedure Get_Location
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Location_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Location_Operation) is
   begin
      Start_Get_Bucket_Location
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Get_Location;

   procedure Get_Versioning
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Get_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Bucket_Versioning_Operation) is
   begin
      Start_Get_Bucket_Versioning
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Get_Versioning;

   procedure Set_Versioning_Configuration
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Bucket_Versioning_Operation) is
   begin
      Start_Put_Bucket_Versioning
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Set_Versioning_Configuration;

   procedure Put_Tags
     (Client    : not null access Flyology.HTTP.Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Value     : Flyology.Object_Storage.Tags.Tag_Set;
      Parameters : Low_Level.Put_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Put_Bucket_Tagging_Operation) is
   begin
      Start_Put_Bucket_Tagging
        (Operation,
         Client,
         Origin,
         Bucket,
         Value,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Put_Tags;

   procedure Get_Tags
     (Client    : not null access Flyology.HTTP.Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Parameters : Low_Level.Get_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Get_Bucket_Tagging_Operation) is
   begin
      Start_Get_Bucket_Tagging
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Get_Tags;

   procedure Delete_Tags
     (Client    : not null access Flyology.HTTP.Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Parameters : Low_Level.Delete_Bucket_Tagging_Parameters;
      Identity  : Low_Level.Credentials;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Region    : String := "us-east-1";
      Style     : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token     : access Flyology.Cancellation.Token := null;
      Operation : in out Delete_Bucket_Tagging_Operation) is
   begin
      Start_Delete_Bucket_Tagging
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Delete_Tags;

end Flyology.Object_Storage.Client.Buckets;
