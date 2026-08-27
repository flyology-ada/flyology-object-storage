with Ada.Environment_Variables;
with Ada.Text_IO;

package body S3_Paginated_REST_XML_Read_Qualification is
   package Environment renames Ada.Environment_Variables;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Operations renames Flyology.Operations;
   package XML renames Flyology.Object_Storage.S3.XML;

   procedure Run is
      Port : constant String :=
        Environment.Value ("FLYOLOGY_S3_QUALIFICATION_PORT");
      Case_ID : constant String :=
        Environment.Value ("FLYOLOGY_S3_QUALIFICATION_CASE");
      Lane : constant String :=
        Environment.Value ("FLYOLOGY_S3_QUALIFICATION_LANE");
      Expected : constant String :=
        Environment.Value ("FLYOLOGY_S3_QUALIFICATION_EXPECTED");
      Expected_Value : constant String :=
        Environment.Value
          ("FLYOLOGY_S3_QUALIFICATION_EXPECTED_VALUE", "");

      Origin : constant Flyology.HTTP.Origin :=
        Flyology.HTTP.Parse_Origin ("http://127.0.0.1:" & Port);
      Identity : constant Low_Level.Credentials :=
        --  AWS SigV4 published-example identity retained by the signed socket
        --  corpus; changing it invalidates the request-signing oracle.
        Low_Level.Make_Credentials
          ("AKIAIOSFODNN7EXAMPLE",
           "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
      Region : constant String := "us-east-1";
      --  The published SigV4 corpus timestamp is part of the signed request
      --  oracle, not a client clock or retry policy.
      Signing_Timestamp : constant String := "20130524T000000Z";
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
             ("MAXIMUM_TEXT_BYTES",
              XML.Default_Limits.Maximum_Text_Bytes));
      --  The collection limit is mandatory case data. The shared driver does
      --  not select a production or test default for operation-specific
      --  decoded collections.
      Collection_Limit : constant Positive :=
        Positive'Value
          (Environment.Value
             ("FLYOLOGY_S3_QUALIFICATION_COLLECTION_LIMIT"));
      Value : constant Inputs_Type := Inputs;

      --  Every signed case is serial. One HTTP slot is the derived minimum
      --  and makes a leaked exchange observable; it is not production policy.
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
   begin
      HTTP_Client.Configure (HTTP, Origin);
      Check_Pre_Admission_Rejection
        (HTTP, Origin, Value, Identity, Region, Signing_Timestamp,
         Socket_Timeout, Limits, Collection_Limit);
      if Lane = "low_level" then
         Execute_Low_Level
           (HTTP, Origin, Value, Identity, Region, Signing_Timestamp,
            Socket_Timeout, Limits, Collection_Limit, Expected,
            Expected_Value);
      elsif Lane = "synchronous" or else Lane = "invalid_xml" then
         declare
            Result : Result_Type;
         begin
            Execute_Synchronous
              (HTTP, Origin, Value, Identity, Region, Socket_Timeout, Limits,
               Collection_Limit, Result);
            Check_Result (Result, Expected, Expected_Value, Case_ID);
         end;
      elsif Lane = "composable" then
         declare
            --  Provider, HTTP exchange, and transport child are the derived
            --  owner stack for this family.
            Set : aliased Operations.Completion_Set (3);
            Operation : Operation_Type :=
              Start
                (Set'Access, HTTP'Access, Origin, Value, Identity,
                 HTTP_Client.Deadline_After (Socket_Timeout), Region, Limits,
                 Collection_Limit);
            Result : Result_Type;
         begin
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            Check_Result (Result, Expected, Expected_Value, Case_ID);
         end;
      elsif Lane = "restart" then
         declare
            Set : aliased Operations.Completion_Set (3);
            Operation : Operation_Type :=
              Start
                (Set'Access, HTTP'Access, Origin, Value, Identity,
                 HTTP_Client.Deadline_After (Socket_Timeout), Region, Limits,
                 Collection_Limit);
            Result : Result_Type;
         begin
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            Check_Result (Result, "success", Expected_Value, Case_ID);
            Restart
              (HTTP'Access, Origin, Value, Identity,
               HTTP_Client.Deadline_After (Socket_Timeout), Region, Limits,
               Collection_Limit, Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            Check_Result (Result, Expected, Expected_Value, Case_ID);
         end;
      elsif Lane = "cancel_restart" then
         declare
            Set : aliased Operations.Completion_Set (3);
            Operation : Operation_Type :=
              Start
                (Set'Access, HTTP'Access, Origin, Value, Identity,
                 HTTP_Client.Deadline_After (Socket_Timeout), Region, Limits,
                 Collection_Limit);
            Result : Result_Type;
         begin
            Request_Cancellation (Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            Check_Result (Result, "cancelled", "", Case_ID);
            Restart
              (HTTP'Access, Origin, Value, Identity,
               HTTP_Client.Deadline_After (Socket_Timeout), Region, Limits,
               Collection_Limit, Operation);
            Operations.Wait_All (Set);
            Finish (Operation, Result);
            Check_Result (Result, Expected, Expected_Value, Case_ID);
         end;
      else
         raise Program_Error with Case_ID & ": unknown call lane";
      end if;
      HTTP_Client.Shutdown (HTTP);
      Ada.Text_IO.Put_Line
        (Operation_Name & " signed qualification " & Case_ID & ": OK");
   exception
      when others =>
         HTTP_Client.Shutdown (HTTP);
         raise;
   end Run;
end S3_Paginated_REST_XML_Read_Qualification;
