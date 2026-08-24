with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.Bytes;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO.Sockets;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Object_Torrent_Socket_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Sockets renames Flyology.IO.Sockets;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Low_Level.Get_Object_Torrent_Outcome_Kind;
   use type Sockets.Selector_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   --  Twelve named wire faults run once from each caller lane.  This is a
   --  corpus cardinality, not production retry or capacity policy.
   Scenarios_Per_Client : constant Positive := 12;
   Request_Count : constant Positive := 2 * Scenarios_Per_Client;
   --  One client slot makes a leaked limited response observable immediately
   --  while preserving the corpus's intentionally serial exchange order.
   HTTP_Client_Capacity : constant Positive := 1;
   --  The fixed signed request fits well below this test-only read capacity;
   --  production request or body limits are not derived from it.
   Request_Buffer_Capacity : constant Positive := 4_096;
   --  Five seconds is the repository socket-corpus watchdog.  The server
   --  accept window covers two such bounded I/O intervals without changing
   --  any public client default or transport deadline.
   Socket_Timeout : constant Duration := 5.0;
   Server_Accept_Timeout : constant Duration := 2 * Socket_Timeout;
   --  The success-limit fixture is four bytes, so three is its derived
   --  one-past rejection boundary and not a product body-size policy.
   Caller_Body_Limit : constant Positive := 3;
   Success_Body : constant String :=
     "torrent" & Character'Val (0) & Character'Val (255);
   Chunked_Body : constant String := "abcdefg";
   Error_XML : constant String :=
     "<Error><Code>NoSuchKey</Code><Message>missing</Message>" &
     "<Resource>/example-bucket/error</Resource></Error>";

   function Decimal (Value : Natural) return String is
      Image : constant String := Natural'Image (Value);
   begin
      return Image (Image'First + 1 .. Image'Last);
   end Decimal;

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

   function HTTP_Response
     (Status, Payload : String; Headers : String := "") return String is
     ("HTTP/1.1 " & Status & CRLF &
      "Content-Length: " & Decimal (Payload'Length) & CRLF & Headers &
      "Connection: close" & CRLF & CRLF & Payload);

   function Chunked_Response return String is
     ("HTTP/1.1 200 OK" & CRLF &
      "Transfer-Encoding: chunked" & CRLF &
      "Connection: close" & CRLF & CRLF &
      "3" & CRLF & "abc" & CRLF & "4" & CRLF & "defg" & CRLF &
      "0" & CRLF & CRLF);

   protected State is
      procedure Publish (Port : Sockets.Port);
      entry Wait_Ready
        (Port   : out Sockets.Port;
         Passed : out Boolean;
         Detail : out US.Unbounded_String);
      procedure Report_Server (Passed : Boolean; Detail : String := "");
      entry Wait_Server
        (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Ready : Boolean := False;
      Port_Value : Sockets.Port := Sockets.Any_Port;
      Server_Done : Boolean := False;
      Server_Passed : Boolean := False;
      Server_Detail : US.Unbounded_String;
   end State;

   protected body State is
      procedure Publish (Port : Sockets.Port) is
      begin
         Port_Value := Port;
         Ready := True;
      end Publish;

      entry Wait_Ready
        (Port   : out Sockets.Port;
         Passed : out Boolean;
         Detail : out US.Unbounded_String)
        when Ready or Server_Done
      is
      begin
         Port := Port_Value;
         Passed := Ready;
         Detail := Server_Detail;
      end Wait_Ready;

      procedure Report_Server (Passed : Boolean; Detail : String := "") is
      begin
         Server_Passed := Passed;
         Server_Detail := US.To_Unbounded_String (Detail);
         Server_Done := True;
      end Report_Server;

      entry Wait_Server
        (Passed : out Boolean; Detail : out US.Unbounded_String)
        when Server_Done
      is
      begin
         Passed := Server_Passed;
         Detail := Server_Detail;
      end Wait_Server;
   end State;

   protected Clients is
      procedure Report (Passed : Boolean; Detail : String := "");
      entry Wait_All (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Count : Natural := 0;
      Passed_Value : Boolean := True;
      Detail_Value : US.Unbounded_String;
   end Clients;

   protected body Clients is
      procedure Report (Passed : Boolean; Detail : String := "") is
      begin
         Count := Count + 1;
         Passed_Value := Passed_Value and Passed;
         if not Passed and then US.Length (Detail_Value) = 0 then
            Detail_Value := US.To_Unbounded_String (Detail);
         end if;
      end Report;

      entry Wait_All
        (Passed : out Boolean; Detail : out US.Unbounded_String)
        when Count = 2
      is
      begin
         Passed := Passed_Value;
         Detail := Detail_Value;
      end Wait_All;
   end Clients;

   task Raw_Server is
      pragma Task_Info (Flyology.Native_Task);
   end Raw_Server;

   task body Raw_Server is
      Listener : Sockets.Socket_Type;
      Peer : Sockets.Socket_Type;
      Address : Sockets.Endpoint;
      Status : Sockets.Selector_Status;
   begin
      Sockets.Create_Socket (Listener);
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Any_Port));
      Sockets.Listen_Socket (Listener);
      State.Publish (Sockets.Get_Socket_Name (Listener).Port);
      for Exchange in 1 .. Request_Count loop
         Sockets.Accept_Socket
           (Listener, Peer, Address, Timeout => Server_Accept_Timeout,
            Status => Status);
         if Status /= Sockets.Completed then
            raise Program_Error with
              "GetObjectTorrent socket accept timed out";
         end if;
         declare
            Buffer : Stream_Element_Array
              (1 .. Stream_Element_Offset (Request_Buffer_Capacity));
            Last : Stream_Element_Offset;
            Head : US.Unbounded_String;
         begin
            loop
               Sockets.Receive
                 (Peer, Buffer, Last, Timeout => Socket_Timeout);
               if Last < Buffer'First then
                  raise Program_Error with
                    "GetObjectTorrent client closed before request";
               end if;
               for Index in Buffer'First .. Last loop
                  US.Append (Head, Character'Val (Buffer (Index)));
               end loop;
               exit when Ada.Strings.Fixed.Index
                 (US.To_String (Head), CRLF & CRLF) > 0;
            end loop;
            declare
               Request : constant String := US.To_String (Head);
               Lower : constant String :=
                 Ada.Characters.Handling.To_Lower (Request);
               First_End : constant Natural :=
                 Ada.Strings.Fixed.Index (Request, CRLF);
               Request_Line : constant String :=
                 Request (Request'First .. First_End - 1);
               Prefix : constant String := "GET /example-bucket/";
               Suffix : constant String := "?torrent HTTP/1.1";
               Scenario_First : constant Natural :=
                 Request_Line'First + Prefix'Length;
               Scenario_Last : constant Natural :=
                 Request_Line'Last - Suffix'Length;
               Scenario : constant String :=
                 (if Scenario_First <= Scenario_Last
                  then Request_Line (Scenario_First .. Scenario_Last)
                  else "");
               Response : US.Unbounded_String;
            begin
               if Request_Line'Length <= Prefix'Length + Suffix'Length
                 or else Request_Line
                   (Request_Line'First .. Request_Line'First +
                      Prefix'Length - 1) /= Prefix
                 or else Request_Line
                   (Request_Line'Last - Suffix'Length + 1 ..
                      Request_Line'Last) /= Suffix
                 or else Ada.Strings.Fixed.Index
                   (Lower, "x-amz-request-payer: requester" & CRLF) = 0
                 or else Ada.Strings.Fixed.Index
                   (Lower,
                    "x-amz-expected-bucket-owner: 123456789012" & CRLF) = 0
                 or else Ada.Strings.Fixed.Index
                   (Lower, "authorization: aws4-hmac-sha256 ") = 0
               then
                  raise Program_Error with
                    "GetObjectTorrent signed request mismatch";
               end if;

               if Scenario = "success" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("200 OK", Success_Body,
                        "x-amz-request-charged: requester" & CRLF));
               elsif Scenario = "chunked" then
                  Response := US.To_Unbounded_String (Chunked_Response);
               elsif Scenario = "duplicate" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("200 OK", "body",
                        "x-amz-request-charged: requester" & CRLF &
                        "x-amz-request-charged: requester" & CRLF));
               elsif Scenario = "empty" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("200 OK", "body", "x-amz-request-charged:" & CRLF));
               elsif Scenario = "charged" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("200 OK", "body",
                        "x-amz-request-charged: owner" & CRLF));
               elsif Scenario = "error" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("404 Not Found", Error_XML,
                        "x-amz-request-id: request-id" & CRLF &
                        "x-amz-id-2: host-id" & CRLF));
               elsif Scenario = "duplicate-id" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("404 Not Found", Error_XML,
                        "x-amz-request-id: one" & CRLF &
                        "x-amz-request-id: two" & CRLF));
               elsif Scenario = "duplicate-host" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("404 Not Found", Error_XML,
                        "x-amz-id-2: one" & CRLF &
                        "x-amz-id-2: two" & CRLF));
               elsif Scenario = "empty-id" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("404 Not Found", Error_XML,
                        "x-amz-request-id:" & CRLF));
               elsif Scenario = "malformed-error" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response
                       ("500 Internal Server Error",
                        "<Error><Unknown/></Error>"));
               elsif Scenario = "error-limit" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response ("500 Internal Server Error", Error_XML));
               elsif Scenario = "success-limit" then
                  Response := US.To_Unbounded_String
                    (HTTP_Response ("200 OK", "four"));
               else
                  raise Program_Error with
                    "unknown GetObjectTorrent socket scenario";
               end if;

               --  Send the complete head separately from the body octets so
               --  every scenario crosses a real response fragmentation edge.
               declare
                  Wire : constant String := US.To_String (Response);
                  Separator : constant Natural :=
                    Ada.Strings.Fixed.Index (Wire, CRLF & CRLF);
               begin
                  Sockets.Send_All
                    (Peer, Bytes (Wire (Wire'First .. Separator + 3)),
                     Timeout => Socket_Timeout);
                  if Separator + 4 <= Wire'Last then
                     Sockets.Send_All
                       (Peer, Bytes (Wire (Separator + 4 .. Wire'Last)),
                        Timeout => Socket_Timeout);
                  end if;
               end;
            end;
            Sockets.Close_Socket (Peer);
         exception
            when others =>
               if Sockets.Is_Open (Peer) then
                  Sockets.Close_Socket (Peer);
               end if;
               raise;
         end;
      end loop;
      Sockets.Close_Socket (Listener);
      State.Report_Server (True);
   exception
      when Occurrence : others =>
         if Sockets.Is_Open (Peer) then
            Sockets.Close_Socket (Peer);
         end if;
         if Sockets.Is_Open (Listener) then
            Sockets.Close_Socket (Listener);
         end if;
         State.Report_Server
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Raw_Server;

   procedure Run_Client is
      Port : Sockets.Port;
      Server_Ready : Boolean;
      Server_Failure : US.Unbounded_String;
      HTTP : aliased HTTP_Client.Client
        (Capacity => HTTP_Client_Capacity);
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
      State.Wait_Ready (Port, Server_Ready, Server_Failure);
      if not Server_Ready then
         raise Program_Error with US.To_String (Server_Failure);
      end if;
      declare
         Origin : constant Flyology.HTTP.Origin := Flyology.HTTP.Parse_Origin
           ("http://127.0.0.1:" & Decimal (Natural (Port)));

         function Prepare (Scenario : String) return Low_Level.Prepared_Request
         is
           (Low_Level.Prepare_Get_Object_Torrent
              (Origin, Low_Level.Path_Style, "example-bucket", Scenario,
               (Request_Payer         => US.To_Unbounded_String ("requester"),
                Expected_Bucket_Owner =>
                  US.To_Unbounded_String ("123456789012")),
               Identity, "us-east-1", "20130524T000000Z"));

         procedure Expect_Invalid
           (Scenario : String;
            Limits   : XML.Parse_Limits := XML.Default_Limits)
         is
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object_Torrent
                (HTTP, Prepare (Scenario), Timeout => Socket_Timeout);
            Raised : Boolean := False;
         begin
            begin
               declare
                  Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
                    Low_Level.Decode_Get_Object_Torrent_Response_Head
                      (Response, Limits => Limits);
                  pragma Unreferenced (Outcome);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "GetObjectTorrent accepted socket fault " & Scenario;
            end if;
         end Expect_Invalid;
      begin
         HTTP_Client.Configure (HTTP, Origin);

         declare
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object_Torrent
                (HTTP, Prepare ("success"), Timeout => Socket_Timeout);
            Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
              Low_Level.Decode_Get_Object_Torrent_Response_Head (Response);
            Payload : constant Flyology.Bytes.Unbounded_Bytes :=
              HTTP_Client.Read_All (Response, Success_Body'Length);
         begin
            if Outcome.Kind /= Low_Level.Torrent_Opened
              or else US.To_String (Outcome.Result.Request_Charged) /=
                "requester"
              or else Flyology.Bytes.To_Byte_String (Payload) /= Success_Body
            then
               raise Program_Error with
                 "GetObjectTorrent binary success mismatch";
            end if;
         end;

         declare
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object_Torrent
                (HTTP, Prepare ("chunked"), Timeout => Socket_Timeout);
            Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
              Low_Level.Decode_Get_Object_Torrent_Response_Head (Response);
            Payload : constant Flyology.Bytes.Unbounded_Bytes :=
              HTTP_Client.Read_All (Response, Chunked_Body'Length);
         begin
            if Outcome.Kind /= Low_Level.Torrent_Opened
              or else Flyology.Bytes.To_Byte_String (Payload) /= Chunked_Body
            then
               raise Program_Error with
                 "GetObjectTorrent chunked success mismatch";
            end if;
         end;

         Expect_Invalid ("duplicate");
         Expect_Invalid ("empty");
         Expect_Invalid ("charged");

         declare
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object_Torrent
                (HTTP, Prepare ("error"), Timeout => Socket_Timeout);
            Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
              Low_Level.Decode_Get_Object_Torrent_Response_Head (Response);
         begin
            if Outcome.Kind /= Low_Level.Get_Object_Torrent_Rejected
              or else Outcome.Status /= 404
              or else US.To_String (Outcome.Error.Code) /= "NoSuchKey"
              or else US.To_String (Outcome.Error.Request_ID) /= "request-id"
              or else US.To_String (Outcome.Error.Host_ID) /= "host-id"
            then
               raise Program_Error with
                 "GetObjectTorrent structured error mismatch";
            end if;
         end;

         Expect_Invalid ("duplicate-id");
         Expect_Invalid ("duplicate-host");
         Expect_Invalid ("empty-id");
         Expect_Invalid ("malformed-error");
         --  One byte below the fixture is the derived transport-read boundary
         --  that exercises Response_Too_Large before XML parsing.
         Expect_Invalid
           ("error-limit",
            (Maximum_Document_Bytes => Error_XML'Length - 1,
             Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
             Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
             Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes));

         declare
            Response : HTTP_Client.Response :=
              Low_Level.Execute_Get_Object_Torrent
                (HTTP, Prepare ("success-limit"),
                 Timeout => Socket_Timeout);
            Outcome : constant Low_Level.Get_Object_Torrent_Outcome :=
              Low_Level.Decode_Get_Object_Torrent_Response_Head (Response);
            Raised : Boolean := False;
         begin
            if Outcome.Kind /= Low_Level.Torrent_Opened then
               raise Program_Error with
                 "GetObjectTorrent limit response head mismatch";
            end if;
            begin
               declare
                  Payload : constant Flyology.Bytes.Unbounded_Bytes :=
                    HTTP_Client.Read_All (Response, Caller_Body_Limit);
                  pragma Unreferenced (Payload);
               begin
                  null;
               end;
            exception
               when HTTP_Client.Response_Too_Large =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with
                 "GetObjectTorrent caller body limit was not enforced";
            end if;
         end;

         HTTP_Client.Shutdown (HTTP);
      end;
   end Run_Client;

   procedure Run_And_Report is
   begin
      Run_Client;
      Clients.Report (True);
   exception
      when Occurrence : others =>
         Clients.Report
           (False, Ada.Exceptions.Exception_Information (Occurrence));
   end Run_And_Report;

   Server_Passed : Boolean;
   Clients_Passed : Boolean;
   Server_Detail : US.Unbounded_String;
   Client_Detail : US.Unbounded_String;
begin
   Run_And_Report;
   declare
      task Lightweight_Client is
         pragma Task_Info (Flyology.Lightweight_Task);
      end Lightweight_Client;

      task body Lightweight_Client is
      begin
         Run_And_Report;
      end Lightweight_Client;
   begin
      null;
   end;
   Clients.Wait_All (Clients_Passed, Client_Detail);
   State.Wait_Server (Server_Passed, Server_Detail);
   if not Clients_Passed then
      raise Program_Error with US.To_String (Client_Detail);
   elsif not Server_Passed then
      raise Program_Error with US.To_String (Server_Detail);
   end if;
   Ada.Text_IO.Put_Line ("S3 GetObjectTorrent socket corpus: OK");
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("S3 GetObjectTorrent socket corpus failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_Get_Object_Torrent_Socket_Corpus;
