with Flyology.Operations.Drivers;

package body Flyology.Object_Storage.Client.Bounded_REST_XML_Reads is

   package HTTP_Client renames Flyology.HTTP.Client;
   package Operations renames Flyology.Operations;
   package Operation_Drivers renames Flyology.Operations.Drivers;
   package Low renames Flyology.Object_Storage.Client.Low_Level;

   use type HTTP_Client.Exchange_Result_Kind;
   use type Operations.Driver_Event;

   Response_Limit_Exceeded : exception;

   procedure Write
     (Item : in out State;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length)
        > Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           Operation_Name & " response exceeds the caller-selected limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Child
     (Item   : in out State;
      Parent : not null access Operations.Operation'Class)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;

      function Singleton_Header (Name : String) return String is
         Count : constant Natural := HTTP_Client.Header_Count (Response, Name);
      begin
         if Count > 1 then
            raise Low.Invalid_Response with
              "duplicate " & Operation_Name & " response header";
         elsif Count = 0 then
            return "";
         end if;
         declare
            Value : constant String := HTTP_Client.Header (Response, Name);
         begin
            if Value'Length = 0 then
               raise Low.Invalid_Response with
                 "empty " & Operation_Name & " response header";
            end if;
            return Value;
         end;
      end Singleton_Header;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Failure
                (HTTP_Client.Response_Sink_Failed, Admission,
                 HTTP_Client.Receiving_Response_Body, "");
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Parent.all, Operations.Succeeded);
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
            Operation_Drivers.Complete (Parent.all, Operations.Failed);
            return;
      end;

      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Decode_Response
                (HTTP_Client.Status (Response),
                 Flyology.Bytes.To_Byte_String (Item.Response_Data),
                 Singleton_Header ("x-amz-request-id"),
                 Singleton_Header ("x-amz-id-2"), Item.Limits,
                 HTTP_Client.Certainty (HTTP_Result),
                 HTTP_Client.Phase (HTTP_Result));
         exception
            when Low.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result), "");
         end;
      end if;

      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Parent.all, Operations.Succeeded);
   end Complete_Child;

   procedure Drive
     (Item         : in out State;
      Parent       : not null access Operations.Operation'Class;
      Sink         : not null access HTTP_Client.Response_Body_Sink'Class;
      Client       : not null access HTTP_Client.Client;
      Cancellation : access Flyology.Cancellation.Token;
      Event        : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Start_Exchange
           (Client, Item.Prepared'Access, Sink, Item.Deadline,
            Cancellation, Item.Child);
         Operations.Continue_After (Parent.all, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Child (Item, Parent);
      else
         raise Program_Error with
           "invalid " & Operation_Name & " driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Parent.all) then
            Operation_Drivers.Complete (Parent.all, Operations.Failed);
         end if;
   end Drive;

   procedure Request_Cancellation (Item : in out State) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   procedure Finalize (Item : in out State) is
   begin
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start
     (Item      : in out State;
      Parent    : not null access Operations.Operation'Class;
      Prepared  : Low.Prepared_Request;
      Deadline  : HTTP_Client.Monotonic_Deadline;
      Limits    : Flyology.Object_Storage.S3.XML.Parse_Limits) is
   begin
      Item.Prepared := Prepared;
      Item.Deadline := Deadline;
      Item.Limits := Limits;
      Flyology.Bytes.Clear (Item.Response_Data);
      Item.Response_Limit := Limits.Maximum_Document_Bytes;
      Item.Has_Final_Result := False;
      Item.Has_Saved_Error := False;
      Operation_Drivers.Start (Parent.all);
      begin
         Operations.Drive (Parent.all, Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Parent.all) then
               Operation_Drivers.Rollback_Start (Parent.all);
            end if;
            Low.Clear_Prepared_Request (Item.Prepared);
            raise;
      end;
   end Start;

   procedure Finish
     (Item   : in out State;
      Parent : not null access Operations.Operation'Class;
      Result : out Result_Type) is
   begin
      Operations.Consume (Parent.all);
      Low.Clear_Prepared_Request (Item.Prepared);
      if Item.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Item.Saved_Error),
            Ada.Exceptions.Exception_Message (Item.Saved_Error));
      elsif not Item.Has_Final_Result then
         raise Program_Error with Operation_Name & " has no terminal result";
      end if;
      Result := Item.Final_Result;
   end Finish;

end Flyology.Object_Storage.Client.Bounded_REST_XML_Reads;
