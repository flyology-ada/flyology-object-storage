with Ada.Calendar;
with Ada.Calendar.Formatting;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Flyology.Object_Storage.Client.Low_Level.Scoped;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations.Drivers;

package body Flyology.Object_Storage.Client.Scoped is

   package US renames Ada.Strings.Unbounded;
   package Buffer_Drivers renames Flyology.Buffers.Drivers;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Operations renames Flyology.Operations;
   package Operation_Drivers renames Flyology.Operations.Drivers;
   package Low_Scoped renames
     Flyology.Object_Storage.Client.Low_Level.Scoped;
   package Byte_Pointers is new System.Address_To_Access_Conversions
     (Ada.Streams.Stream_Element);

   use type Ada.Streams.Stream_Element_Offset;
   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type Operations.Driver_Event;
   use type System.Storage_Elements.Storage_Offset;
   use type US.Unbounded_String;

   Response_Limit_Exceeded : exception;

   --  SigV4 external wire contract: basic-format timestamps are UTC
   --  YYYYMMDD'T'HHMMSS'Z'. The slices below project that fixed shape from
   --  Ada.Calendar.Formatting.Image; changing them invalidates signatures.
   function Timestamp return String is
      Image : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => False, Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 3) &
        Image (Image'First + 5 .. Image'First + 6) &
        Image (Image'First + 8 .. Image'First + 9) & "T" &
        Image (Image'First + 11 .. Image'First + 12) &
        Image (Image'First + 14 .. Image'First + 15) &
        Image (Image'First + 17 .. Image'First + 18) & "Z";
   end Timestamp;

   --  HTTP entity-tag wire contract: a strong opaque tag is quoted and its
   --  interior is obs-text, 0x21, or 0x23 .. 0x7E. Weak validators are not
   --  admitted because these operations bind exact object generations.
   function Valid_Exact_Entity_Tag (Value : String) return Boolean is
   begin
      if Value'Length < 2
        or else Value (Value'First) /= '"'
        or else Value (Value'Last) /= '"'
      then
         return False;
      end if;
      for Index in Value'First + 1 .. Value'Last - 1 loop
         declare
            Code : constant Natural := Character'Pos (Value (Index));
         begin
            if Value (Index) = '"'
              or else not
                (Code = 16#21#
                 or else Code in 16#23# .. 16#7E#
                 or else Code in 16#80# .. 16#FF#)
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Valid_Exact_Entity_Tag;

   function Failed_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Publication_Disposition is
   begin
      if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then
         return Cancelled_Before_Publication;
      elsif Admission = HTTP_Client.Not_Admitted then
         return Definitely_Not_Published;
      else
         return Outcome_Unknown;
      end if;
   end Failed_Disposition;

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

   --  Project certainty exactly from the maintained
   --  tests/corpora/composable-client/put-certainty.tsv oracle. Status and S3
   --  code pairs are externally modeled wire values; changing a row changes
   --  whether callers must reconcile before any later retry.
   function Normalize_Put_Response
     (Value     : Low_Level.Put_Object_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Conditional_Put_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Object_Rejected
         then US.To_String (Value.Error.Code) else "");
   begin
      if Admission /= HTTP_Client.Response_Observed then
         return
           (Kind        => Put_Response_Available,
            Disposition => Outcome_Unknown,
            Failure     => Corrupt_Or_Invalid_Response,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Kind = Low_Level.Object_Put then
         return
           (Kind        => Put_Response_Available,
            Disposition => Published,
            Failure     => No_Failure,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 412 and then Code = "PreconditionFailed" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Precondition_Failed,
            Failure     => No_Failure,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 401 and then Code = "InvalidAccessKeyId" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Authentication_Failed,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 403 and then Code = "AccessDenied" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Authorization_Failed,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 400 and then Code = "InvalidRequest" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Invalid_Request,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 404 and then Code = "NoSuchBucket" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Not_Found,
            Admission   => Admission,
            Response    => Value);
      elsif (Value.Status = 409
             and then Code = "ConditionalRequestConflict")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout")
      then
         return
           (Kind        => Put_Response_Available,
            Disposition => Outcome_Unknown,
            Failure     => Unavailable_Or_Retryable,
            Admission   => Admission,
            Response    => Value);
      else
         return
           (Kind        => Put_Response_Available,
            Disposition => Outcome_Unknown,
            Failure     => Corrupt_Or_Invalid_Response,
            Admission   => Admission,
            Response    => Value);
      end if;
   end Normalize_Put_Response;

   function Normalize_Put_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Required  : HTTP_Client.Length_Requirement := (others => <>);
      Detail    : String := "") return Conditional_Put_Result is
   begin
      return
        (Kind                 => Put_Exchange_Failed,
         Disposition          => Failed_Disposition (Kind, Admission),
         Failure              =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission            => Admission,
         HTTP_Result          => Kind,
         HTTP_Phase           => Phase,
         Required_Body_Length => Required,
         Detail               => US.To_Unbounded_String (Detail));
   end Normalize_Put_Failure;

   overriding function Declared_Length
     (Item : Conditional_Put_Operation)
      return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Buffer_Drivers.Length (Item.Source)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Conditional_Put_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural := Buffer_Drivers.Length (Item.Source);
      Count  : constant Natural :=
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
           Byte_Pointers.To_Pointer
             (Buffer_Drivers.Address (Item.Source) +
                System.Storage_Elements.Storage_Offset
                  (Item.Source_Position + Offset)).all;
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Conditional_Put_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Conditional_Put_Operation) is
   begin
      --  The parent operation owns the detached token through typed Finish;
      --  releasing the HTTP borrow therefore has no storage action.
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Conditional_Put_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "PutObject response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Child (Item : in out Conditional_Put_Operation) is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish
           (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Put_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
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
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Put_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Required_Body_Length (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Put_Response
              (Low_Level.Decode_Put_Object_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data)),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Child;

   overriding procedure Drive
     (Item : in out Conditional_Put_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Put_Object
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Child (Item);
      else
         raise Program_Error with "invalid conditional PUT driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Conditional_Put_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Conditional_Put_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Buffer_Drivers.Release (Item.Source);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put
     (Item     : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      If_Match : String;
      If_None_Match : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String;
      Style    : Low_Level.Addressing_Style;
      Content_Type : String;
      Expected_Bucket_Owner : String;
      Token    : access Flyology.Cancellation.Token)
   is
      Parameters : Low_Level.Put_Object_Parameters;
   begin
      if Item.HTTP /= Client or else Item.Cancellation /= Token then
         raise Program_Error with
           "conditional PUT restart changed a retained owner";
      end if;
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
      Parameters.If_None_Match := US.To_Unbounded_String (If_None_Match);
      Parameters.Content_Type := US.To_Unbounded_String (Content_Type);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Item.Prepared := Low_Level.Prepare_Put_Object
        (Origin, Style, Bucket, Key, Parameters, Payload_SHA256, Identity,
         Region, Timestamp);
      Item.Deadline := Deadline;
      Item.Source_Position := 0;
      Flyology.Bytes.Clear (Item.Response_Data);
      Item.Response_Limit :=
        --  Derived resource bound: retained Put error bytes use the same
        --  maintained limit as the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Item.Has_Final_Result := False;
      Item.Has_Saved_Error := False;

      Operation_Drivers.Start (Item);
      begin
         Buffer_Drivers.Move_From (Payload_Buffer, Item.Source);
         Operations.Drive
           (Operations.Operation'Class (Item), Operations.Start_Operation);
      exception
         when others =>
            if Buffer_Drivers.Has_Buffer (Item.Source) then
               Buffer_Drivers.Move_To (Item.Source, Payload_Buffer);
            end if;
            if Operations.Is_Active (Item) then
               Operation_Drivers.Rollback_Start (Item);
            end if;
            raise;
      end;
   end Start_Put;

   procedure Start_Put_If_Absent
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      Start_Put
        (Operation, Client, Origin, Bucket, Key, "", "*", Payload_Buffer,
         Payload_SHA256, Identity, Deadline, Region, Style, Content_Type,
         Expected_Bucket_Owner, Token);
   end Start_Put_If_Absent;

   procedure Start_Put_If_Matches
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if not Valid_Exact_Entity_Tag (Expected_Entity_Tag) then
         raise Low_Level.Invalid_Request with
           "Put_If_Matches requires one strong entity tag";
      end if;
      Start_Put
        (Operation, Client, Origin, Bucket, Key, Expected_Entity_Tag, "",
         Payload_Buffer, Payload_SHA256, Identity, Deadline, Region, Style,
         Content_Type, Expected_Bucket_Owner, Token);
   end Start_Put_If_Matches;

   function Put_If_Absent
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation is
   begin
      return Result : Conditional_Put_Operation (Set, Client, Token) do
         Start_Put_If_Absent
           (Result, Client, Origin, Bucket, Key, Payload_Buffer,
            Payload_SHA256, Identity, Deadline, Region, Style, Content_Type,
            Expected_Bucket_Owner, Token);
      end return;
   end Put_If_Absent;

   function Put_If_Matches
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation is
   begin
      return Result : Conditional_Put_Operation (Set, Client, Token) do
         Start_Put_If_Matches
           (Result, Client, Origin, Bucket, Key, Expected_Entity_Tag,
            Payload_Buffer, Payload_SHA256, Identity, Deadline, Region, Style,
            Content_Type, Expected_Bucket_Owner, Token);
      end return;
   end Put_If_Matches;

   procedure Finish
     (Operation : in out Conditional_Put_Operation;
      Result    : out Conditional_Put_Result;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer) is
   begin
      if not Buffer_Drivers.Same_Pool
        (Operation.Source, Payload_Buffer)
      then
         raise Program_Error with
           "conditional PUT Finish requires the original buffer pool";
      end if;
      Operations.Consume (Operation);
      Buffer_Drivers.Move_To (Operation.Source, Payload_Buffer);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "conditional PUT has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Read_Exchange_Failure
     (Value : HTTP_Client.Exchange_Result) return Whole_Get_Result is
   begin
      return
        (Kind                 => Whole_Get_Exchange_Failed,
         Failure              => Failed_Reason (HTTP_Client.Kind (Value)),
         HTTP_Result          => HTTP_Client.Kind (Value),
         HTTP_Phase           => HTTP_Client.Phase (Value),
         Required_Body_Length =>
           HTTP_Client.Required_Body_Length (Value),
         Detail               => US.To_Unbounded_String
           (HTTP_Client.Failure_Detail (Value)));
   end Read_Exchange_Failure;

   function Invalid_Read_Result return Whole_Get_Result is
   begin
      return
        (Kind                 => Whole_Get_Exchange_Failed,
         Failure              => Corrupt_Or_Invalid_Response,
         HTTP_Result          => HTTP_Client.Response_Invalid,
         HTTP_Phase           => HTTP_Client.Receiving_Response_Body,
         Required_Body_Length => (others => <>),
         Detail               => US.Null_Unbounded_String);
   end Invalid_Read_Result;

   procedure Clear_Buffer (Item : in out Flyology.Buffers.Unique_Buffer) is
      procedure Clear
        (Data   : in out Ada.Streams.Stream_Element_Array;
         Length : in out Natural) is
      begin
         pragma Unreferenced (Data);
         Length := 0;
      end Clear;
   begin
      Flyology.Buffers.With_Writable_Data (Item, Clear'Access);
   end Clear_Buffer;

   function Buffer_Text
     (Item : Flyology.Buffers.Unique_Buffer) return String
   is
      Bytes : Flyology.Bytes.Unbounded_Bytes;

      procedure Copy (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Bytes := Flyology.Bytes.To_Unbounded_Bytes (Data);
      end Copy;
   begin
      Flyology.Buffers.With_Readable_Data (Item, Copy'Access);
      return Flyology.Bytes.To_Byte_String (Bytes);
   end Buffer_Text;

   procedure Complete_Child (Item : in out Whole_Get_Operation) is
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish
           (Item.Child, HTTP_Result, Response, Item.Destination.all);
      exception
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Read_Exchange_Failure (HTTP_Result);
      else
         begin
            declare
               Head : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Complete_Response
                   (Response, Buffer_Text (Item.Destination.all));
            begin
               if Head.Kind = Low_Level.Get_Object_Rejected then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result :=
                    (Kind     => Whole_Get_Response_Available,
                     Failure  => No_Failure,
                     Response => Head);
               elsif Head.Status /= 200
                 or else not Valid_Exact_Entity_Tag
                   (US.To_String (Head.Result.Entity_Tag))
                 or else not Head.Result.Content_Length.Is_Set
                 or else Head.Result.Content_Length.Value /=
                   Byte_Count
                     (Flyology.Buffers.Length (Item.Destination.all))
                 or else
                   (US.Length (Item.Expected_Entity_Tag) > 0
                      and then Head.Result.Entity_Tag /=
                        Item.Expected_Entity_Tag)
               then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result := Invalid_Read_Result;
               else
                  Item.Final_Result :=
                    (Kind     => Whole_Get_Response_Available,
                     Failure  => No_Failure,
                     Response => Head);
               end if;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Clear_Buffer (Item.Destination.all);
               Item.Final_Result := Invalid_Read_Result;
         end;
      end if;
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Child;

   overriding procedure Drive
     (Item : in out Whole_Get_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Get_Object
           (Item.Child, Item.HTTP, Item.Prepared'Access,
            Item.Destination.all, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Child (Item);
      else
         raise Program_Error with "invalid whole GET driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Whole_Get_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Whole_Get_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
   end Finalize;

   procedure Start_Get
     (Item      : in out Whole_Get_Operation;
      Client    : not null access HTTP_Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Key       : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity  : Low_Level.Credentials;
      Deadline  : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String;
      Region    : String;
      Style     : Low_Level.Addressing_Style;
      Expected_Bucket_Owner : String;
      Request_Payer : String;
      Checksum_Mode : Boolean;
      Token     : access Flyology.Cancellation.Token)
   is
      Parameters : Low_Level.Get_Object_Parameters;
   begin
      if Item.HTTP /= Client
        or else Item.Destination /= Destination
        or else Item.Cancellation /= Token
      then
         raise Program_Error with
           "whole GET restart changed a retained owner";
      end if;
      if Expected_Entity_Tag'Length > 0
        and then not Valid_Exact_Entity_Tag (Expected_Entity_Tag)
      then
         raise Low_Level.Invalid_Request with
           "Get_Whole requires one strong entity tag";
      end if;
      Parameters.If_Match :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Checksum_Mode := Checksum_Mode;
      Item.Prepared := Low_Level.Prepare_Get_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Item.Deadline := Deadline;
      Item.Expected_Entity_Tag :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Item.Has_Final_Result := False;
      Item.Has_Saved_Error := False;

      Operation_Drivers.Start (Item);
      begin
         Operations.Drive
           (Operations.Operation'Class (Item), Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Item) then
               Operation_Drivers.Rollback_Start (Item);
            end if;
            raise;
      end;
   end Start_Get;

   procedure Start_Get_Whole
     (Operation : in out Whole_Get_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      Start_Get
        (Operation, Client, Origin, Bucket, Key, Destination, Identity,
         Deadline, Expected_Entity_Tag, Version_ID, Region, Style,
         Expected_Bucket_Owner, Request_Payer, Checksum_Mode, Token);
   end Start_Get_Whole;

   function Get_Whole
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
      return Whole_Get_Operation is
   begin
      return Result : Whole_Get_Operation
        (Set, Client, Destination, Token)
      do
         Start_Get_Whole
           (Result, Client, Origin, Bucket, Key, Destination, Identity,
            Deadline, Expected_Entity_Tag, Version_ID, Region, Style,
            Expected_Bucket_Owner, Request_Payer, Checksum_Mode, Token);
      end return;
   end Get_Whole;

   procedure Finish
     (Operation : in out Whole_Get_Operation;
      Result    : out Whole_Get_Result) is
   begin
      Operations.Consume (Operation);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "whole GET has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

end Flyology.Object_Storage.Client.Scoped;
