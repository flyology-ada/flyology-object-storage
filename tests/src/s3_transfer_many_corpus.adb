with Ada.Characters.Handling;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO.Sockets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Transfers;
with Flyology.Object_Storage.S3.SigV4;

procedure S3_Transfer_Many_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Transfers renames Flyology.Object_Storage.Client.Transfers;
   package SigV4 renames Flyology.Object_Storage.S3.SigV4;
   package Sockets renames Flyology.IO.Sockets;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Sockets.Selector_Status;
   use type Transfers.Transfer_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Parallel_A_Body : constant String := "parallel-a-body";
   Parallel_B_Body : constant String := "parallel-b-body";
   Wave_Upload_Body : constant String := "wave-upload-body";
   Wave_Download_Body : constant String := "wave-download-body";
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";

   function Bytes (Value : String) return Stream_Element_Array is
      Result : Stream_Element_Array
        (1 .. Stream_Element_Offset (Value'Length));
   begin
      for Offset in 0 .. Value'Length - 1 loop
         Result (Result'First + Stream_Element_Offset (Offset)) :=
           Stream_Element (Character'Pos (Value (Value'First + Offset)));
      end loop;
      return Result;
   end Bytes;

   function Decimal (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal;

   function HTTP_Response
     (Status, Payload : String;
      Extra_Headers   : String := "") return String is
     ("HTTP/1.1 " & Status & CRLF
      & "Content-Length: " & Decimal (Payload'Length) & CRLF
      & Extra_Headers & "Connection: close" & CRLF & CRLF & Payload);

   procedure Write_File (Path, Value : String) is
      package SIO renames Ada.Streams.Stream_IO;
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Path);
      if Value'Length > 0 then
         SIO.Write (File, Bytes (Value));
      end if;
      SIO.Close (File);
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Write_File;

   function Read_File (Path : String) return String is
      package SIO renames Ada.Streams.Stream_IO;
      use type SIO.Count;
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Path);
      declare
         Size : constant SIO.Count := SIO.Size (File);
         Data : Stream_Element_Array (1 .. Stream_Element_Offset (Size));
         Last : Stream_Element_Offset;
         Result : String (1 .. Natural (Size));
      begin
         if Size > 0 then
            SIO.Read (File, Data, Last);
            if Last /= Data'Last then
               raise Program_Error with "short test file read";
            end if;
            for Index in Result'Range loop
               Result (Index) := Character'Val
                 (Data
                    (Data'First
                     + Stream_Element_Offset (Index - Result'First)));
            end loop;
         end if;
         SIO.Close (File);
         return Result;
      end;
   exception
      when others =>
         if SIO.Is_Open (File) then
            SIO.Close (File);
         end if;
         raise;
   end Read_File;

   procedure Delete_If_Present (Path : String) is
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
   end Delete_If_Present;

   protected type Coordination is
      procedure Publish (Value : Sockets.Port);
      entry Wait_Ready (Value : out Sockets.Port);
      procedure Complete (Passed : Boolean; Detail : String := "");
      entry Wait_Done (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Port_Value   : Sockets.Port := Sockets.Any_Port;
      Ready        : Boolean := False;
      Done         : Boolean := False;
      Passed_Value : Boolean := False;
      Detail_Value : US.Unbounded_String;
   end Coordination;

   protected body Coordination is
      procedure Publish (Value : Sockets.Port) is
      begin
         Port_Value := Value;
         Ready := True;
      end Publish;

      entry Wait_Ready (Value : out Sockets.Port) when Ready is
      begin
         Value := Port_Value;
      end Wait_Ready;

      procedure Complete (Passed : Boolean; Detail : String := "") is
      begin
         Passed_Value := Passed;
         Detail_Value := US.To_Unbounded_String (Detail);
         Done := True;
      end Complete;

      entry Wait_Done
        (Passed : out Boolean; Detail : out US.Unbounded_String) when Done is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait_Done;
   end Coordination;

   State : Coordination;

   task Raw_Batch_Server;

   task body Raw_Batch_Server is
      Listener : Sockets.Socket_Type;
      Peer_One : Sockets.Socket_Type;
      Peer_Two : Sockets.Socket_Type;
      Address  : Sockets.Endpoint;
      Status   : Sockets.Selector_Status;
      Port     : Sockets.Port;

      function Header_Value (Header, Name : String) return String is
         Marker : constant String := CRLF & Name & ":";
         Position : constant Natural := Ada.Strings.Fixed.Index
           (Header, Marker);
         First : Natural := Position + Marker'Length;
         Last  : Natural;
      begin
         if Position = 0 then
            return "";
         end if;
         while First <= Header'Last and then Header (First) = ' ' loop
            First := First + 1;
         end loop;
         Last := Ada.Strings.Fixed.Index (Header, CRLF, From => First) - 1;
         return Header (First .. Last);
      end Header_Value;

      procedure Accept_Request
        (Peer   : out Sockets.Socket_Type;
         Target : out US.Unbounded_String;
         Payload : out US.Unbounded_String)
      is
         Buffer : Stream_Element_Array (1 .. 4_096);
         Last   : Stream_Element_Offset;
         Head   : US.Unbounded_String;
      begin
         Sockets.Accept_Socket
           (Listener, Peer, Address, Timeout => 5.0, Status => Status);
         if Status /= Sockets.Completed then
            raise Program_Error with "batch socket accept timed out";
         end if;
         loop
            Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);
            if Last < Buffer'First then
               raise Program_Error with "client closed before request head";
            end if;
            for Index in Buffer'First .. Last loop
               US.Append (Head, Character'Val (Buffer (Index)));
            end loop;
            exit when Ada.Strings.Fixed.Index
              (US.To_String (Head), CRLF & CRLF) /= 0;
         end loop;
         declare
            Request : constant String := US.To_String (Head);
            Separator : constant Natural := Ada.Strings.Fixed.Index
              (Request, CRLF & CRLF);
            Header : constant String :=
              Request (Request'First .. Separator + 3);
            Lower : constant String := Ada.Characters.Handling.To_Lower
              (Header);
            First_Space : constant Natural := Ada.Strings.Fixed.Index
              (Header, " ");
            Second_Space : constant Natural := Ada.Strings.Fixed.Index
              (Header, " ", From => First_Space + 1);
            Length_Text : constant String :=
              Header_Value (Lower, "content-length");
            Expected_Length : constant Natural :=
              (if Length_Text'Length = 0
               then 0 else Natural'Value (Length_Text));
         begin
            if First_Space = 0 or else Second_Space = 0
              or else
                (Header (Header'First .. First_Space - 1) /= "PUT"
                 and then Header (Header'First .. First_Space - 1) /= "GET")
              or else Ada.Strings.Fixed.Index
                (Lower, "authorization: aws4-hmac-sha256 credential=") = 0
            then
               raise Program_Error with "unexpected batch request head";
            end if;
            Target := US.To_Unbounded_String
              (Header (First_Space + 1 .. Second_Space - 1));
            Payload := US.Null_Unbounded_String;
            if Separator + 4 <= Request'Last then
               US.Append
                 (Payload, Request (Separator + 4 .. Request'Last));
            end if;
            while US.Length (Payload) < Expected_Length loop
               Sockets.Receive (Peer, Buffer, Last, Timeout => 5.0);
               if Last < Buffer'First then
                  raise Program_Error with "short batch request body";
               end if;
               for Index in Buffer'First .. Last loop
                  US.Append (Payload, Character'Val (Buffer (Index)));
               end loop;
            end loop;
            if US.Length (Payload) /= Expected_Length
              or else Header_Value (Lower, "x-amz-content-sha256") /=
                SigV4.SHA256_Hex (US.To_String (Payload))
            then
               raise Program_Error with "invalid signed batch body";
            end if;
         end;
      end Accept_Request;

      procedure Send_Response
        (Peer : in out Sockets.Socket_Type; Response : String) is
      begin
         Sockets.Send_All (Peer, Bytes (Response), Timeout => 5.0);
         Sockets.Close_Socket (Peer);
      end Send_Response;

      procedure Validate_Parallel
        (Target, Payload : String; Seen_A, Seen_B : in out Boolean) is
      begin
         if Target = "/example-bucket/parallel-a"
           and then Payload = Parallel_A_Body and then not Seen_A
         then
            Seen_A := True;
         elsif Target = "/example-bucket/parallel-b"
           and then Payload = Parallel_B_Body and then not Seen_B
         then
            Seen_B := True;
         else
            raise Program_Error with "unexpected parallel upload";
         end if;
      end Validate_Parallel;

      function Parallel_Response (Target : String) return String is
        (HTTP_Response
           ("200 OK", "",
            "ETag: """ &
            (if Target = "/example-bucket/parallel-a"
             then "parallel-a" else "parallel-b") & """" & CRLF));

      procedure Serve
        (Expected_Target, Expected_Body, Response : String) is
         Target : US.Unbounded_String;
         Payload : US.Unbounded_String;
      begin
         Accept_Request (Peer_One, Target, Payload);
         if US.To_String (Target) /= Expected_Target
           or else US.To_String (Payload) /= Expected_Body
         then
            raise Program_Error with "unexpected sequential batch request";
         end if;
         Send_Response (Peer_One, Response);
      end Serve;
   begin
      Sockets.Create_Socket (Listener);
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Any_Port));
      Sockets.Listen_Socket (Listener);
      Port := Sockets.Get_Socket_Name (Listener).Port;
      State.Publish (Port);
      declare
         Target_One : US.Unbounded_String;
         Target_Two : US.Unbounded_String;
         Body_One   : US.Unbounded_String;
         Body_Two   : US.Unbounded_String;
         Seen_A     : Boolean := False;
         Seen_B     : Boolean := False;
      begin
         --  No response is sent until both complete requests arrive. A
         --  sequential implementation deadlocks here and hits the timeout.
         Accept_Request (Peer_One, Target_One, Body_One);
         Accept_Request (Peer_Two, Target_Two, Body_Two);
         Validate_Parallel
           (US.To_String (Target_One), US.To_String (Body_One),
            Seen_A, Seen_B);
         Validate_Parallel
           (US.To_String (Target_Two), US.To_String (Body_Two),
            Seen_A, Seen_B);
         if not Seen_A or else not Seen_B then
            raise Program_Error with "parallel subjects were not both seen";
         end if;
         Send_Response
           (Peer_One, Parallel_Response (US.To_String (Target_One)));
         Send_Response
           (Peer_Two, Parallel_Response (US.To_String (Target_Two)));
      end;
      Serve
        ("/example-bucket/wave-upload", Wave_Upload_Body,
         HTTP_Response
           ("200 OK", "", "ETag: ""wave-upload""" & CRLF));
      Serve
        ("/example-bucket/wave-rejected", Wave_Upload_Body,
         HTTP_Response ("403 Forbidden", Error_XML));
      Serve
        ("/example-bucket/wave-download", "",
         HTTP_Response
           ("200 OK", Wave_Download_Body,
            "ETag: ""wave-download""" & CRLF));
      Serve
        ("/example-bucket/cancel-first", Wave_Upload_Body,
         HTTP_Response ("403 Forbidden", Error_XML));
      Sockets.Accept_Socket
        (Listener, Peer_One, Address, Timeout => 1.0, Status => Status);
      if Status /= Sockets.Expired then
         if Sockets.Is_Open (Peer_One) then
            Sockets.Close_Socket (Peer_One);
         end if;
         raise Program_Error with
           "cancelled or locally rejected batch issued an extra request";
      end if;
      Sockets.Close_Socket (Listener);
      State.Complete (True);
   exception
      when Occurrence : others =>
         if Sockets.Is_Open (Peer_One) then
            Sockets.Close_Socket (Peer_One);
         end if;
         if Sockets.Is_Open (Peer_Two) then
            Sockets.Close_Socket (Peer_Two);
         end if;
         if Sockets.Is_Open (Listener) then
            Sockets.Close_Socket (Listener);
         end if;
         State.Complete
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Raw_Batch_Server;

   function Subject
     (Kind : Transfers.Transfer_Kind;
      Key, Local_Path : String) return Transfers.Subject is
     (Kind         => Kind,
      Bucket       => US.To_Unbounded_String ("example-bucket"),
      Key          => US.To_Unbounded_String (Key),
      Local_Path   => US.To_Unbounded_String (Local_Path),
      Content_Type => US.Null_Unbounded_String);

   procedure Run_Client is
      Port : Sockets.Port;
      HTTP : aliased HTTP_Client.Client (Capacity => 2);
      Identity : aliased constant Low_Level.Credentials :=
        Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
      State.Wait_Ready (Port);
      declare
         Origin : constant Flyology.HTTP.Origin := Flyology.HTTP.Parse_Origin
           ("http://127.0.0.1:" & Decimal (Natural (Port)));
         Prefix : constant String :=
           "/tmp/flyology-transfer-many-" & Decimal (Natural (Port));
         Parallel_A_Path : constant String := Prefix & "-parallel-a";
         Parallel_B_Path : constant String := Prefix & "-parallel-b";
         Wave_Upload_Path : constant String := Prefix & "-wave-upload";
         Wave_Download_Path : constant String := Prefix & "-wave-download";

         procedure Cleanup is
         begin
            Delete_If_Present (Parallel_A_Path);
            Delete_If_Present (Parallel_B_Path);
            Delete_If_Present (Wave_Upload_Path);
            Delete_If_Present (Wave_Download_Path);
         end Cleanup;
      begin
         HTTP_Client.Configure (HTTP, Origin);
         Write_File (Parallel_A_Path, Parallel_A_Body);
         Write_File (Parallel_B_Path, Parallel_B_Body);
         Write_File (Wave_Upload_Path, Wave_Upload_Body);
         begin
            declare
               Items : constant Transfers.Subject_Array :=
                 (1 => Subject
                    (Transfers.Upload, "parallel-a", Parallel_A_Path),
                  2 => Subject
                    (Transfers.Upload, "parallel-b", Parallel_B_Path));
               Results : Transfers.Transfer_Result_Array (Items'Range);
            begin
               Transfers.Transfer_Many
                 (HTTP, Origin, Items, Results, Identity,
                  Options =>
                    (Maximum_Concurrent_Objects  => 2,
                     Maximum_Concurrent_Requests => 2,
                     Maximum_In_Flight_Bytes     => 2 * 64 * 1_024,
                     On_Failure => Transfers.Continue_After_Failure,
                     others => <>),
                  Timeout => 5.0);
               if Results (1).State /= Transfers.Completed
                 or else Results (2).State /= Transfers.Completed
                 or else Results (1).Bytes /= Parallel_A_Body'Length
                 or else Results (2).Bytes /= Parallel_B_Body'Length
                 or else US.To_String (Results (1).Entity_Tag) /=
                   """parallel-a"""
                 or else US.To_String (Results (2).Entity_Tag) /=
                   """parallel-b"""
               then
                  raise Program_Error with
                    "parallel transfer results lost input ordering";
               end if;
            end;
            declare
               Items : constant Transfers.Subject_Array :=
                 (1 => Subject
                    (Transfers.Upload, "wave-upload", Wave_Upload_Path),
                  2 => Subject
                    (Transfers.Upload, "wave-rejected", Wave_Upload_Path),
                  3 => Subject
                    (Transfers.Download, "wave-download",
                     Wave_Download_Path));
               Results : Transfers.Transfer_Result_Array (Items'Range);
            begin
               Transfers.Transfer_Many
                 (HTTP, Origin, Items, Results, Identity,
                  Options =>
                    (Maximum_Concurrent_Objects  => 1,
                     Maximum_Concurrent_Requests => 1,
                     Maximum_In_Flight_Bytes     => 64 * 1_024,
                     On_Failure => Transfers.Continue_After_Failure,
                     others => <>),
                  Timeout => 5.0);
               if Results (1).State /= Transfers.Completed
                 or else Results (1).Bytes /= Wave_Upload_Body'Length
                 or else Results (2).State /= Transfers.Rejected
                 or else Results (2).Status /= 403
                 or else US.To_String (Results (2).Error_Code) /=
                   "AccessDenied"
                 or else Results (3).State /= Transfers.Completed
                 or else Results (3).Bytes /= Wave_Download_Body'Length
                 or else Read_File (Wave_Download_Path) /= Wave_Download_Body
               then
                  raise Program_Error with
                    "continued transfer wave result mismatch";
               end if;
            end;
            declare
               Items : constant Transfers.Subject_Array :=
                 (1 => Subject
                    (Transfers.Upload, "cancel-first", Wave_Upload_Path),
                  2 => Subject
                    (Transfers.Upload, "cancel-second", Wave_Upload_Path),
                  3 => Subject
                    (Transfers.Upload, "cancel-third", Wave_Upload_Path));
               Results : Transfers.Transfer_Result_Array (Items'Range);
            begin
               Transfers.Transfer_Many
                 (HTTP, Origin, Items, Results, Identity,
                  Options =>
                    (Maximum_Concurrent_Objects  => 1,
                     Maximum_Concurrent_Requests => 1,
                     Maximum_In_Flight_Bytes     => 64 * 1_024,
                     On_Failure => Transfers.Cancel_Remaining,
                     others => <>),
                  Timeout => 5.0);
               if Results (1).State /= Transfers.Rejected
                 or else Results (2).State /= Transfers.Cancelled
                 or else Results (3).State /= Transfers.Cancelled
               then
                  raise Program_Error with
                    "cancel-remaining terminal results mismatch";
               end if;
            end;
            declare
               Stop : aliased Flyology.Cancellation.Token;
               Items : constant Transfers.Subject_Array :=
                 (1 => Subject
                    (Transfers.Upload, "pre-cancel-a", Wave_Upload_Path),
                  2 => Subject
                    (Transfers.Upload, "pre-cancel-b", Wave_Upload_Path));
               Results : Transfers.Transfer_Result_Array (Items'Range);
            begin
               Stop.Request;
               Transfers.Transfer_Many
                 (HTTP, Origin, Items, Results, Identity,
                  Timeout => 5.0, Token => Stop'Access);
               if Results (1).State /= Transfers.Cancelled
                 or else Results (2).State /= Transfers.Cancelled
               then
                  raise Program_Error with
                    "pre-cancelled batch was admitted";
               end if;
            end;
            declare
               Items : constant Transfers.Subject_Array :=
                 (1 => Subject
                    (Transfers.Upload, "small-budget", Wave_Upload_Path));
               Results : Transfers.Transfer_Result_Array (Items'Range);
               Raised : Boolean := False;
            begin
               begin
                  Transfers.Transfer_Many
                    (HTTP, Origin, Items, Results, Identity,
                     Options =>
                       (Maximum_In_Flight_Bytes => 64 * 1_024 - 1,
                        others => <>),
                     Timeout => 5.0);
               exception
                  when Constraint_Error =>
                     Raised := True;
               end;
               if not Raised then
                  raise Program_Error with
                    "sub-buffer batch budget was accepted";
               end if;
            end;
            declare
               Items : constant Transfers.Subject_Array :=
                 (1 => Subject
                    (Transfers.Upload, "expired", Wave_Upload_Path));
               Results : Transfers.Transfer_Result_Array (Items'Range);
            begin
               Transfers.Transfer_Many
                 (HTTP, Origin, Items, Results, Identity, Timeout => 0.0);
               if Results (1).State /= Transfers.Failed
                 or else Ada.Strings.Fixed.Index
                   (US.To_String (Results (1).Message), "deadline") = 0
               then
                  raise Program_Error with
                    "expired batch did not return a terminal result";
               end if;
            end;
            declare
               Items : Transfers.Subject_Array (1 .. 0);
               Results : Transfers.Transfer_Result_Array (1 .. 0);
            begin
               Transfers.Transfer_Many
                 (HTTP, Origin, Items, Results, Identity, Timeout => 5.0);
            end;
         exception
            when others =>
               HTTP_Client.Shutdown (HTTP);
               Cleanup;
               raise;
         end;
         HTTP_Client.Shutdown (HTTP);
         Cleanup;
      end;
   end Run_Client;

   Client_Passed : Boolean := False;
   Server_Passed : Boolean;
   Client_Detail : US.Unbounded_String;
   Server_Detail : US.Unbounded_String;
begin
   begin
      Run_Client;
      Client_Passed := True;
   exception
      when Occurrence : others =>
         Client_Detail := US.To_Unbounded_String
           (Ada.Exceptions.Exception_Information (Occurrence));
   end;
   State.Wait_Done (Server_Passed, Server_Detail);
   if not Client_Passed then
      raise Program_Error with US.To_String (Client_Detail);
   elsif not Server_Passed then
      raise Program_Error with US.To_String (Server_Detail);
   end if;
end S3_Transfer_Many_Corpus;
