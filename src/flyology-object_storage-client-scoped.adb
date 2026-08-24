with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Flyology.Object_Storage.Client.Low_Level.Scoped;
with Flyology.Object_Storage.S3.Core;
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
   package Core renames Flyology.Object_Storage.S3.Core;
   package Byte_Pointers is new System.Address_To_Access_Conversions
     (Ada.Streams.Stream_Element);

   use type Ada.Streams.Stream_Element_Offset;
   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Create_Multipart_Outcome_Kind;
   use type Low_Level.Complete_Multipart_Outcome_Kind;
   use type Low_Level.Abort_Multipart_Outcome_Kind;
   use type Low_Level.List_Parts_Outcome_Kind;
   use type Low_Level.List_Multipart_Uploads_Outcome_Kind;
   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type Low_Level.Upload_Part_Outcome_Kind;
   use type Core.Range_Parse_Status;
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
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
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
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
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
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
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

   function Range_Read_Exchange_Failure
     (Value : HTTP_Client.Exchange_Result) return Range_Get_Result is
   begin
      return
        (Kind                 => Range_Get_Exchange_Failed,
         Failure              => Failed_Reason (HTTP_Client.Kind (Value)),
         HTTP_Result          => HTTP_Client.Kind (Value),
         HTTP_Phase           => HTTP_Client.Phase (Value),
         Required_Body_Length =>
           HTTP_Client.Required_Body_Length (Value),
         Detail               => US.To_Unbounded_String
           (HTTP_Client.Failure_Detail (Value)));
   end Range_Read_Exchange_Failure;

   function Invalid_Range_Read_Result return Range_Get_Result is
   begin
      return
        (Kind                 => Range_Get_Exchange_Failed,
         Failure              => Corrupt_Or_Invalid_Response,
         HTTP_Result          => HTTP_Client.Response_Invalid,
         HTTP_Phase           => HTTP_Client.Receiving_Response_Body,
         Required_Body_Length => (others => <>),
         Detail               => US.Null_Unbounded_String);
   end Invalid_Range_Read_Result;

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

   function Decimal (Value : Byte_Count) return String is
     (Ada.Strings.Fixed.Trim
        (Byte_Count'Image (Value), Ada.Strings.Both));

   function Valid_Range_Request (Value : Byte_Range) return Boolean is
     (case Value.Kind is
         when Bounded_Range => Value.First <= Value.Last,
         when Open_Ended_Range => True,
         when Suffix_Range => Value.Count > 0,
         when Whole_Range => False);

   --  RFC 9110 single-range wire form. The public Byte_Range domain is the
   --  authority; this formatter introduces no independent bound or policy.
   function Range_Header (Value : Byte_Range) return String is
   begin
      case Value.Kind is
         when Bounded_Range =>
            return "bytes=" & Decimal (Value.First) & "-" &
              Decimal (Value.Last);
         when Open_Ended_Range =>
            return "bytes=" & Decimal (Value.First) & "-";
         when Suffix_Range =>
            return "bytes=-" & Decimal (Value.Count);
         when Whole_Range =>
            raise Low_Level.Invalid_Request with
              "Get_Range requires a non-whole byte range";
      end case;
   end Range_Header;

   function Bind_Response_Range
     (Value     : String;
      Requested : Byte_Range;
      Resolved  : out Resolved_Byte_Range) return Boolean
   is
      Prefix : constant String := "bytes ";
      Hyphen : Natural;
      Slash  : Natural;
   begin
      Resolved := (others => 0);
      if Value'Length <= Prefix'Length
        or else Value (Value'First .. Value'First + Prefix'Length - 1) /=
          Prefix
      then
         return False;
      end if;
      Hyphen := Ada.Strings.Fixed.Index
        (Value, "-", From => Value'First + Prefix'Length);
      Slash := Ada.Strings.Fixed.Index
        (Value, "/", From => Value'First + Prefix'Length);
      if Hyphen = 0 or else Slash = 0 or else Hyphen >= Slash then
         return False;
      end if;
      declare
         Returned : constant Core.Range_Parse_Result :=
           Core.Parse_Range_Header
             ("bytes=" &
                Value (Value'First + Prefix'Length .. Slash - 1));
         Total : constant Byte_Count :=
           Byte_Count'Value (Value (Slash + 1 .. Value'Last));
         Expected : constant Range_Resolution :=
           Core.Resolve_Range (Total, Requested);
      begin
         if Returned.Status /= Core.Range_Parsed
           or else Returned.Request.Kind /= Bounded_Range
           or else Expected.Kind /= Satisfied_Range
           or else Returned.Request.First /= Expected.First
           or else Returned.Request.Last /= Expected.Last
         then
            return False;
         end if;
         Resolved :=
           (First        => Expected.First,
            Last         => Expected.Last,
            Total_Length => Total);
         return True;
      end;
   exception
      when Constraint_Error =>
         return False;
   end Bind_Response_Range;

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
            if not Operations.Is_Active (Item.Child) then
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
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
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
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
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
   end Finalize;

   procedure Complete_Range_Child (Item : in out Range_Get_Operation) is
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
            if not Operations.Is_Active (Item.Child) then
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Range_Read_Exchange_Failure (HTTP_Result);
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
                    (Kind               => Range_Get_Response_Available,
                     Failure            => No_Failure,
                     Response           => Head,
                     Has_Resolved_Range => False,
                     Resolved           => (others => 0));
               elsif Head.Status /= 206
                 or else not Valid_Exact_Entity_Tag
                   (US.To_String (Head.Result.Entity_Tag))
                 or else not Head.Result.Content_Length.Is_Set
                 or else Head.Result.Content_Length.Value /=
                   Byte_Count
                     (Flyology.Buffers.Length (Item.Destination.all))
                 or else Head.Result.Entity_Tag /= Item.Expected_Entity_Tag
               then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result := Invalid_Range_Read_Result;
               else
                  declare
                     Bound : Resolved_Byte_Range;
                  begin
                     if not Bind_Response_Range
                       (US.To_String (Head.Result.Content_Range),
                        Item.Requested_Range, Bound)
                     then
                        Clear_Buffer (Item.Destination.all);
                        Item.Final_Result := Invalid_Range_Read_Result;
                     else
                        Item.Final_Result :=
                          (Kind               => Range_Get_Response_Available,
                           Failure            => No_Failure,
                           Response           => Head,
                           Has_Resolved_Range => True,
                           Resolved           => Bound);
                     end if;
                  end;
               end if;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Clear_Buffer (Item.Destination.all);
               Item.Final_Result := Invalid_Range_Read_Result;
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Range_Child;

   overriding procedure Drive
     (Item : in out Range_Get_Operation;
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
         Complete_Range_Child (Item);
      else
         raise Program_Error with "invalid range GET driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Range_Get_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Range_Get_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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

   procedure Start_Get_Range
     (Operation : in out Range_Get_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
   is
      Parameters : Low_Level.Get_Object_Parameters;
   begin
      if Operation.HTTP /= Client
        or else Operation.Destination /= Destination
        or else Operation.Cancellation /= Token
      then
         raise Program_Error with
           "range GET restart changed a retained owner";
      elsif not Valid_Exact_Entity_Tag (Expected_Entity_Tag) then
         raise Low_Level.Invalid_Request with
           "Get_Range requires one strong entity tag";
      elsif not Valid_Range_Request (Requested) then
         raise Low_Level.Invalid_Request with
           "Get_Range requires one valid single range";
      end if;
      Parameters.If_Match :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Parameters.Byte_Range_Header :=
        US.To_Unbounded_String (Range_Header (Requested));
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Checksum_Mode := Checksum_Mode;
      Operation.Prepared := Low_Level.Prepare_Get_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Expected_Entity_Tag :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Operation.Requested_Range := Requested;
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Range;

   function Get_Range
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
      return Range_Get_Operation is
   begin
      return Result : Range_Get_Operation
        (Set, Client, Destination, Token)
      do
         Start_Get_Range
           (Result, Client, Origin, Bucket, Key, Requested, Destination,
            Identity, Deadline, Expected_Entity_Tag, Version_ID, Region,
            Style, Expected_Bucket_Owner, Request_Payer, Checksum_Mode,
            Token);
      end return;
   end Get_Range;

   procedure Finish
     (Operation : in out Whole_Get_Operation;
      Result    : out Whole_Get_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "whole GET has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure Finish
     (Operation : in out Range_Get_Operation;
      Result    : out Range_Get_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "range GET has no terminal result";
      elsif Operation.Final_Result.Kind = Range_Get_Response_Available
        and then Operation.Final_Result.Response.Kind = Low_Level.Object_Opened
        and then not Operation.Final_Result.Has_Resolved_Range
      then
         raise Program_Error with "range GET lacks a resolved interval";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Head_Exchange_Failure
     (Value : HTTP_Client.Exchange_Result) return Head_Result is
   begin
      return
        (Kind        => Head_Exchange_Failed,
         Failure     => Failed_Reason (HTTP_Client.Kind (Value)),
         HTTP_Result => HTTP_Client.Kind (Value),
         HTTP_Phase  => HTTP_Client.Phase (Value),
         Detail      => US.To_Unbounded_String
           (HTTP_Client.Failure_Detail (Value)));
   end Head_Exchange_Failure;

   overriding procedure Write
     (Item : in out Head_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      pragma Unreferenced (Item);
      if Data'Length > 0 then
         --  HTTP defines HEAD as bodyless. Reject any octet that its framing
         --  layer nevertheless exposes to this sink; bytes after a complete
         --  HEAD response remain the HTTP connection owner's responsibility.
         raise Response_Limit_Exceeded with
           "HeadObject response contains a body";
      end if;
   end Write;

   procedure Complete_Head_Child (Item : in out Head_Operation) is
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish
           (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              (Kind        => Head_Exchange_Failed,
               Failure     => Corrupt_Or_Invalid_Response,
               HTTP_Result => HTTP_Client.Response_Sink_Failed,
               HTTP_Phase  => HTTP_Client.Receiving_Response_Body,
               Detail      => US.Null_Unbounded_String);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Head_Exchange_Failure (HTTP_Result);
      else
         begin
            Item.Final_Result :=
              (Kind     => Head_Response_Available,
               Failure  => No_Failure,
               Response => Low_Level.Decode_Head_Object_Complete_Response
                 (Response, ""));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 (Kind        => Head_Exchange_Failed,
                  Failure     => Corrupt_Or_Invalid_Response,
                  HTTP_Result => HTTP_Client.Response_Invalid,
                  HTTP_Phase  => HTTP_Client.Waiting_Response_Head,
                  Detail      => US.Null_Unbounded_String);
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Head_Child;

   overriding procedure Drive
     (Item : in out Head_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Head_Object
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Head_Child (Item);
      else
         raise Program_Error with "invalid HeadObject driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Head_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Head_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
   end Finalize;

   procedure Start_Head_Object
     (Operation : in out Head_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "HeadObject restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Head_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Head_Object;

   function Head_Object
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Operation is
   begin
      return Result : Head_Operation (Set, Client, Token) do
         Start_Head_Object
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Head_Object;

   procedure Finish
     (Operation : in out Head_Operation;
      Result    : out Head_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "HeadObject has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Delete_Response
     (Value     : Low_Level.Delete_Object_Outcome;
      Admission : HTTP_Client.Admission_Certainty) return Delete_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Delete_Object_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400 and then Code = "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else
          (Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion")
        or else (Value.Status = 412 and then Code = "PreconditionFailed");
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
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
         then Not_Found
         elsif Value.Status = 400 and then Code = "InvalidRequest"
         then Invalid_Request
         elsif Conclusive_Rejection
         then No_Failure
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Delete_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Deletion_Outcome_Unknown
            elsif Value.Kind = Low_Level.Object_Deleted
            then Deletion_Completed
            elsif Conclusive_Rejection
            then Definitely_Not_Deleted
            else Deletion_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Deleted
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Delete_Response;

   function Normalize_Delete_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Result is
   begin
      return
        (Kind        => Delete_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Deletion_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Deleted
            else Deletion_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Failure;

   overriding function Declared_Length
     (Item : Delete_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Delete_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source (Item : in out Delete_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Delete_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "DeleteObject response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Delete_Child (Item : in out Delete_Operation) is
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
            Item.Final_Result :=
              (Kind        => Delete_Exchange_Failed,
               Disposition =>
                 (if Admission = HTTP_Client.Not_Admitted
                  then Definitely_Not_Deleted
                  else Deletion_Outcome_Unknown),
               Failure     => Corrupt_Or_Invalid_Response,
               Admission   => Admission,
               HTTP_Result => HTTP_Client.Response_Sink_Failed,
               HTTP_Phase  => HTTP_Client.Receiving_Response_Body,
               Detail      => US.Null_Unbounded_String);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Delete_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Delete_Response
              (Low_Level.Decode_Delete_Object_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data)),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 (Kind        => Delete_Exchange_Failed,
                  Disposition => Deletion_Outcome_Unknown,
                  Failure     => Corrupt_Or_Invalid_Response,
                  Admission   => HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Result => HTTP_Client.Response_Invalid,
                  HTTP_Phase  => HTTP_Client.Phase (HTTP_Result),
                  Detail      => US.Null_Unbounded_String);
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Child;

   overriding procedure Drive
     (Item : in out Delete_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Delete_Object
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Child (Item);
      else
         raise Program_Error with "invalid DeleteObject driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Delete_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Delete_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Object
     (Operation : in out Delete_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "DeleteObject restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Delete_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained DeleteObject error bytes use the
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Object;

   function Delete_Object
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Operation is
   begin
      return Result : Delete_Operation (Set, Client, Token) do
         Start_Delete_Object
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Delete_Object;

   procedure Finish
     (Operation : in out Delete_Operation;
      Result    : out Delete_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "DeleteObject has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Project multipart-initiation certainty from exact modeled S3
   --  status/code pairs. A complete response alone is not conclusive unless
   --  the success identity or rejection semantics validate.
   function Normalize_Create_Multipart_Response
     (Value     : Low_Level.Create_Multipart_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Create_Multipart_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Create_Rejected
         then US.To_String (Value.Error.Code) else "");
      --  Wire authority: only exact modeled S3 status/code pairs establish
      --  rejection; changing this set changes mutation certainty semantics.
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400 and then Code = "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else (Value.Status = 404 and then Code = "NoSuchBucket");
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
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif Value.Status = 400 and then Code = "InvalidRequest"
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Create_Multipart_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Creation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Created
            then Multipart_Upload_Created
            elsif Conclusive_Rejection
            then Definitely_Not_Created
            else Creation_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Created
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Create_Multipart_Response;

   function Normalize_Create_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Create_Multipart_Result is
   begin
      return
        (Kind        => Create_Multipart_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Creation_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Created
            else Creation_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Create_Multipart_Failure;

   overriding function Declared_Length
     (Item : Create_Multipart_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  Wire authority: CreateMultipartUpload has no request body.  The
      --  zero-length declaration prevents content from entering initiation.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Create_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Create_Multipart_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Create_Multipart_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Create_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "CreateMultipartUpload response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Create_Multipart_Child
     (Item : in out Create_Multipart_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              (Kind        => Create_Multipart_Exchange_Failed,
               Disposition =>
                 (if Admission = HTTP_Client.Not_Admitted
                  then Definitely_Not_Created
                  else Creation_Outcome_Unknown),
               Failure     => Corrupt_Or_Invalid_Response,
               Admission   => Admission,
               HTTP_Result => HTTP_Client.Response_Sink_Failed,
               HTTP_Phase  => HTTP_Client.Receiving_Response_Body,
               Detail      => US.Null_Unbounded_String);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Create_Multipart_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Create_Multipart_Response
              (Low_Level.Decode_Create_Multipart_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 (Kind        => Create_Multipart_Exchange_Failed,
                  Disposition => Creation_Outcome_Unknown,
                  Failure     => Corrupt_Or_Invalid_Response,
                  Admission   => HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Result => HTTP_Client.Response_Invalid,
                  HTTP_Phase  => HTTP_Client.Phase (HTTP_Result),
                  Detail      => US.Null_Unbounded_String);
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Create_Multipart_Child;

   overriding procedure Drive
     (Item : in out Create_Multipart_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Create_Multipart_Upload
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Create_Multipart_Child (Item);
      else
         raise Program_Error with
           "invalid CreateMultipartUpload driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Create_Multipart_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Create_Multipart_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Create_Multipart_Upload
     (Operation : in out Create_Multipart_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "CreateMultipartUpload restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Create_Multipart_Upload
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained initiation response bytes use the
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Create_Multipart_Upload;

   function Create_Multipart_Upload
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Create_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Multipart_Operation is
   begin
      return Result : Create_Multipart_Operation (Set, Client, Token) do
         Start_Create_Multipart_Upload
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Create_Multipart_Upload;

   procedure Finish
     (Operation : in out Create_Multipart_Operation;
      Result    : out Create_Multipart_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "CreateMultipartUpload has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. A complete modeled
   --  rejection still does not prove that an earlier attempt did not stage a
   --  part, so only a validated success or definite non-admission changes
   --  publication certainty.
   function Normalize_Upload_Part_Response
     (Value     : Low_Level.Upload_Part_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Upload_Part_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Upload_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Part_Uploaded then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status = 400
           and then Code in
             "BadDigest" | "InvalidPart" | "InvalidRequest" |
             "EntityTooLarge"
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
        (Kind        => Upload_Part_Response_Available,
         Disposition =>
           (if Admission = HTTP_Client.Response_Observed
              and then Value.Kind = Low_Level.Part_Uploaded
            then Part_Published
            else Part_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Upload_Part_Response;

   function Normalize_Upload_Part_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Upload_Part_Result is
   begin
      return
        (Kind        => Upload_Part_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Part_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Staged
            else Part_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Upload_Part_Failure;

   overriding function Declared_Length
     (Item : Upload_Part_Operation) return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Buffer_Drivers.Length (Item.Source)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Upload_Part_Operation;
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
     (Item       : in out Upload_Part_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Upload_Part_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Upload_Part_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "UploadPart response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Upload_Part_Child
     (Item : in out Upload_Part_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Upload_Part_Failure
               (HTTP_Client.Response_Sink_Failed, Admission,
                HTTP_Client.Receiving_Response_Body);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Upload_Part_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Upload_Part_Response
              (Low_Level.Decode_Upload_Part_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Upload_Part_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Upload_Part_Child;

   overriding procedure Drive
     (Item : in out Upload_Part_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Upload_Part
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Upload_Part_Child (Item);
      else
         raise Program_Error with "invalid UploadPart driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Upload_Part_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Upload_Part_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Buffer_Drivers.Release (Item.Source);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Upload_Part
     (Operation : in out Upload_Part_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "UploadPart restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Upload_Part
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained UploadPart response bytes use the
        --  maintained limit of the S3 XML decoder that consumes errors.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Buffer_Drivers.Move_From (Payload_Buffer, Operation.Source);
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Buffer_Drivers.Has_Buffer (Operation.Source) then
               Buffer_Drivers.Move_To (Operation.Source, Payload_Buffer);
            end if;
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Upload_Part;

   function Upload_Part
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Upload_Part_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Upload_Part_Operation is
   begin
      return Result : Upload_Part_Operation (Set, Client, Token) do
         Start_Upload_Part
           (Result, Client, Origin, Bucket, Key, Parameters, Payload_Buffer,
            Identity, Deadline, Region, Style, Token);
      end return;
   end Upload_Part;

   procedure Finish
     (Operation : in out Upload_Part_Operation;
      Result    : out Upload_Part_Result;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer) is
   begin
      if not Buffer_Drivers.Same_Pool
        (Operation.Source, Payload_Buffer)
      then
         raise Program_Error with
           "UploadPart Finish requires the original buffer pool";
      end if;
      Operations.Consume (Operation);
      Buffer_Drivers.Move_To (Operation.Source, Payload_Buffer);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "UploadPart has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority. Even a complete modeled
   --  rejection may be an embedded HTTP 200 error after server-side work, so
   --  only validated success or definite non-admission is conclusive.
   function Normalize_Complete_Multipart_Response
     (Value     : Low_Level.Complete_Multipart_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Multipart_Completion_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Complete_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Completed then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status in 200 | 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status in 200 | 400 | 412
           and then Code in
             "BadDigest" | "EntityTooSmall" | "InvalidPart" |
             "InvalidPartOrder" | "InvalidRequest" | "PreconditionFailed"
         then Invalid_Request
         elsif (Value.Status in 200 | 409
                  and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status in 200 | 500
                      and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Complete_Multipart_Response_Available,
         Disposition =>
           (if Admission = HTTP_Client.Response_Observed
              and then Value.Kind = Low_Level.Completed
            then Multipart_Completed
            else Completion_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Complete_Multipart_Response;

   function Normalize_Complete_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Completion_Result is
   begin
      return
        (Kind        => Complete_Multipart_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Completion_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Completed
            else Completion_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Complete_Multipart_Failure;

   overriding function Declared_Length
     (Item : Complete_Multipart_Operation) return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low_Scoped.Owned_Payload_Length (Item.Prepared)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Complete_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural :=
        Low_Scoped.Owned_Payload_Length (Item.Prepared);
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
                (Low_Scoped.Owned_Payload_Element
                   (Item.Prepared, Item.Source_Position + Offset + 1)));
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Complete_Multipart_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Complete_Multipart_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Complete_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "CompleteMultipartUpload response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Multipart_Child
     (Item : in out Complete_Multipart_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Complete_Multipart_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Complete_Multipart_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Complete_Multipart_Response
              (Low_Level.Decode_Complete_Multipart_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Complete_Multipart_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Multipart_Child;

   overriding procedure Drive
     (Item : in out Complete_Multipart_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Complete_Multipart_Upload
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Multipart_Child (Item);
      else
         raise Program_Error with
           "invalid CompleteMultipartUpload driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Complete_Multipart_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Complete_Multipart_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Complete_Multipart_Upload
     (Operation : in out Complete_Multipart_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "CompleteMultipartUpload restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Complete_Multipart_Upload
        (Origin, Style, Bucket, Key, Upload_ID, Completion, Parameters,
         Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained completion response bytes use the
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Complete_Multipart_Upload;

   function Complete_Multipart_Upload
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Completion : S3.Multipart.Complete_Multipart_Upload_Request;
      Parameters : Low_Level.Complete_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Complete_Multipart_Operation is
   begin
      return Result : Complete_Multipart_Operation (Set, Client, Token) do
         Start_Complete_Multipart_Upload
           (Result, Client, Origin, Bucket, Key, Upload_ID, Completion,
            Parameters, Identity, Deadline, Region, Style, Token);
      end return;
   end Complete_Multipart_Upload;

   procedure Finish
     (Operation : in out Complete_Multipart_Operation;
      Result    : out Multipart_Completion_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "CompleteMultipartUpload has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are S3 wire authority for bounded diagnostics.
   --  Only a validated 204 proves this abort request was accepted; every
   --  complete rejection remains conservative after possible admission.
   function Normalize_Abort_Multipart_Response
     (Value     : Low_Level.Abort_Multipart_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Multipart_Abort_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Abort_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Aborted then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
         elsif Value.Status in 400 | 412
           and then Code in "InvalidRequest" | "PreconditionFailed"
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
        (Kind        => Abort_Multipart_Response_Available,
         Disposition =>
           (if Admission = HTTP_Client.Response_Observed
              and then Value.Kind = Low_Level.Aborted
            then Multipart_Aborted
            else Abort_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Abort_Multipart_Response;

   function Normalize_Abort_Multipart_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Multipart_Abort_Result is
   begin
      return
        (Kind        => Abort_Multipart_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Abort_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Aborted
            else Abort_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Abort_Multipart_Failure;

   overriding function Declared_Length
     (Item : Abort_Multipart_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      --  S3 wire contract: AbortMultipartUpload has no request body.
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Abort_Multipart_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Abort_Multipart_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Abort_Multipart_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Abort_Multipart_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "AbortMultipartUpload response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Abort_Multipart_Child
     (Item : in out Abort_Multipart_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Abort_Multipart_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Abort_Multipart_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Abort_Multipart_Response
              (Low_Level.Decode_Abort_Multipart_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Abort_Multipart_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Abort_Multipart_Child;

   overriding procedure Drive
     (Item : in out Abort_Multipart_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_Abort_Multipart_Upload
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Abort_Multipart_Child (Item);
      else
         raise Program_Error with
           "invalid AbortMultipartUpload driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Abort_Multipart_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Abort_Multipart_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Abort_Multipart_Upload
     (Operation : in out Abort_Multipart_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "AbortMultipartUpload restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Abort_Multipart_Upload
        (Origin, Style, Bucket, Key, Upload_ID, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained abort error bytes use the
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Abort_Multipart_Upload;

   function Abort_Multipart_Upload
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Upload_ID : String;
      Parameters : Low_Level.Abort_Multipart_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Abort_Multipart_Operation is
   begin
      return Result : Abort_Multipart_Operation (Set, Client, Token) do
         Start_Abort_Multipart_Upload
           (Result, Client, Origin, Bucket, Key, Upload_ID, Parameters,
            Identity, Deadline, Region, Style, Token);
      end return;
   end Abort_Multipart_Upload;

   procedure Finish
     (Operation : in out Abort_Multipart_Operation;
      Result    : out Multipart_Abort_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "AbortMultipartUpload has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListParts attempt; it does
   --  not authorize retry or imply a shared snapshot with a later page.
   function Normalize_List_Parts_Response
     (Value     : Low_Level.List_Parts_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Parts_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.List_Parts_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Parts_Listed
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
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchUpload"
         then Not_Found
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
        (Kind      => List_Parts_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Parts_Response;

   function Normalize_List_Parts_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Parts_Result is
   begin
      return
        (Kind        => List_Parts_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Parts_Failure;

   overriding procedure Write
     (Item : in out List_Parts_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListParts response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Parts_Child
     (Item : in out List_Parts_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Parts_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Parts_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Parts_Response
              (Low_Level.Decode_List_Parts_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Parts_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Parts_Child;

   overriding procedure Drive
     (Item : in out List_Parts_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_List_Parts
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Parts_Child (Item);
      else
         raise Program_Error with "invalid ListParts driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Parts_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Parts_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Parts
     (Operation : in out List_Parts_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListParts restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Parts
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained ListParts bytes use the maintained
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Parts;

   function List_Parts
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.List_Parts_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Parts_Operation is
   begin
      return Result : List_Parts_Operation (Set, Client, Token) do
         Start_List_Parts
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end List_Parts;

   procedure Finish
     (Operation : in out List_Parts_Operation;
      Result    : out List_Parts_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "ListParts has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListMultipartUploads
   --  attempt; it does not authorize retry or imply a shared snapshot with a
   --  later page.
   function Normalize_List_Multipart_Uploads_Response
     (Value     : Low_Level.List_Multipart_Uploads_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Multipart_Uploads_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.List_Multipart_Uploads_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Multipart_Uploads_Listed
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
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
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
        (Kind      => Multipart_Uploads_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Multipart_Uploads_Response;

   function Normalize_List_Multipart_Uploads_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Multipart_Uploads_Result is
   begin
      return
        (Kind        => List_Multipart_Uploads_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Multipart_Uploads_Failure;

   overriding procedure Write
     (Item : in out List_Multipart_Uploads_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListMultipartUploads response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Multipart_Uploads_Child
     (Item : in out List_Multipart_Uploads_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Scoped.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Scoped.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Multipart_Uploads_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
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
               Low_Scoped.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Multipart_Uploads_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Multipart_Uploads_Response
              (Low_Level.Decode_List_Multipart_Uploads_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Multipart_Uploads_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Multipart_Uploads_Child;

   overriding procedure Drive
     (Item : in out List_Multipart_Uploads_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low_Scoped.Start_List_Multipart_Uploads
           (Item.Child, Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Multipart_Uploads_Child (Item);
      else
         raise Program_Error with
           "invalid ListMultipartUploads driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low_Scoped.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Multipart_Uploads_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Multipart_Uploads_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low_Scoped.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Multipart_Uploads
     (Operation : in out List_Multipart_Uploads_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListMultipartUploads restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Multipart_Uploads
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained listing bytes use the maintained
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
            Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Multipart_Uploads;

   function List_Multipart_Uploads
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Multipart_Uploads_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Multipart_Uploads_Operation is
   begin
      return Result : List_Multipart_Uploads_Operation
        (Set, Client, Token)
      do
         Start_List_Multipart_Uploads
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end List_Multipart_Uploads;

   procedure Finish
     (Operation : in out List_Multipart_Uploads_Operation;
      Result    : out List_Multipart_Uploads_Result) is
   begin
      Operations.Consume (Operation);
      Low_Scoped.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "ListMultipartUploads has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

end Flyology.Object_Storage.Client.Scoped;
