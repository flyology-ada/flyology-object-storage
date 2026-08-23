with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO.Sockets;
with Flyology.IO.TLS;
with Flyology.IO.TLS.OpenSSL;
with Flyology.Object_Storage.Client.Buckets;
with Flyology.Object_Storage.Client.Low_Level;

procedure S3_Create_Session_TLS_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Buckets renames Flyology.Object_Storage.Client.Buckets;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Sockets renames Flyology.IO.Sockets;
   package TLS renames Flyology.IO.TLS;
   package OpenSSL renames Flyology.IO.TLS.OpenSSL;
   package US renames Ada.Strings.Unbounded;

   use Ada.Streams;
   use type Low_Level.Create_Session_Outcome_Kind;
   use type Sockets.Selector_Status;

   CRLF : constant String := Character'Val (13) & Character'Val (10);
   Certificate : constant String :=
     "fixtures/tls/create-session-cert.pem";
   Private_Key : constant String :=
     "fixtures/tls/create-session-key.pem";
   Request_Count : constant Positive := 10;
   Client_Backend : aliased OpenSSL.OpenSSL_Provider;
   Server_Backend : aliased OpenSSL.OpenSSL_Provider;

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

   function Header_Value (Head, Name : String) return String is
      Lower : constant String := Ada.Characters.Handling.To_Lower (Head);
      Marker : constant String := CRLF &
        Ada.Characters.Handling.To_Lower (Name) & ":";
      Position : constant Natural := Ada.Strings.Fixed.Index (Lower, Marker);
      First : Natural := Position + Marker'Length;
      Last : Natural;
   begin
      if Position = 0 then
         return "";
      end if;
      while First <= Head'Last and then Head (First) = ' ' loop
         First := First + 1;
      end loop;
      Last := Ada.Strings.Fixed.Index (Head, CRLF, From => First) - 1;
      return (if Last < First then "" else Head (First .. Last));
   end Header_Value;

   function HTTP_Response (Payload, Extra_Headers : String) return String is
     ("HTTP/1.1 200 OK" & CRLF &
      "Content-Type: application/xml" & CRLF &
      "Content-Length: " & Decimal (Payload'Length) & CRLF &
      "Connection: close" & CRLF & Extra_Headers & CRLF & Payload);

   function Session_XML (Suffix : String) return String is
     ("<CreateSessionResult xmlns=""" &
      "http://s3.amazonaws.com/doc/2006-03-01/"">" &
      "<Credentials><AccessKeyId>ASIAIOSFODNN7EXAMPLE</AccessKeyId>" &
      "<SecretAccessKey>session-secret-" & Suffix &
      "</SecretAccessKey><SessionToken>session-token-" & Suffix &
      "</SessionToken><Expiration>2026-08-23T15:30:00Z</Expiration>" &
      "</Credentials></CreateSessionResult>");

   protected State is
      procedure Publish (Port : Sockets.Port);
      entry Wait_Ready (Port : out Sockets.Port);
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

      entry Wait_Ready (Port : out Sockets.Port) when Ready is
      begin
         Port := Port_Value;
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

   protected Client_Results is
      procedure Report (Passed : Boolean; Detail : String := "");
      entry Wait_All (Passed : out Boolean; Detail : out US.Unbounded_String);
   private
      Count : Natural := 0;
      Passed_Value : Boolean := True;
      Detail_Value : US.Unbounded_String;
   end Client_Results;

   protected body Client_Results is
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
   end Client_Results;

   procedure Run_Client is
      Port : Sockets.Port;
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
        ("AKIAIOSFODNN7EXAMPLE",
         "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY");
   begin
      State.Wait_Ready (Port);
      declare
         Origin : constant Flyology.HTTP.Origin := Flyology.HTTP.Parse_Origin
           ("https://127.0.0.1:" & Decimal (Natural (Port)));

         function Call (Key_ID : String)
            return Low_Level.Create_Session_Outcome is
           (Buckets.Create_Session
              (HTTP, Origin, "127", Identity,
               Session_Mode => "ReadOnly",
               Server_Side_Encryption => "aws:kms",
               SSE_KMS_Key_ID => Key_ID,
               SSE_KMS_Encryption_Context => "e30=",
               Bucket_Key_Enabled => (Is_Set => True, Value => True),
               Timeout => 5.0));

         procedure Must_Reject (Key_ID, Message : String) is
            Raised : Boolean := False;
         begin
            begin
               declare
                  Ignored : constant Low_Level.Create_Session_Outcome :=
                    Call (Key_ID);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            exception
               when Low_Level.Invalid_Response =>
                  Raised := True;
            end;
            if not Raised then
               raise Program_Error with Message;
            end if;
         end Must_Reject;
      begin
         HTTP_Client.Configure
           (HTTP, Origin, Client_Backend'Access, HTTP_Client.HTTP_1_Only);
         declare
            Outcome : constant Low_Level.Create_Session_Outcome :=
              Call ("valid");
         begin
            if Outcome.Kind /= Low_Level.Session_Created
              or else US.To_String (Outcome.Result.Expiration) /=
                "2026-08-23T15:30:00Z"
              or else US.To_String
                (Outcome.Result.Server_Side_Encryption) /= "aws:kms"
              or else US.To_String (Outcome.Result.SSE_KMS_Key_ID) /= "valid"
              or else not Outcome.Result.Bucket_Key_Enabled.Is_Set
              or else not Outcome.Result.Bucket_Key_Enabled.Value
            then
               raise Program_Error with
                 "CreateSession TLS wrapper result mismatch";
            end if;
            declare
               Prepared : constant Low_Level.Prepared_Request :=
                 Low_Level.Prepare_Create_Session
                   (Origin, Low_Level.Virtual_Hosted_Style, "127",
                    (others => <>), Outcome.Result.Identity, "us-east-1",
                    "20260823T150000Z");
            begin
               if Ada.Strings.Fixed.Index
                 (Low_Level.Signed_Headers (Prepared),
                  "x-amz-s3session-token") = 0
                 or else Ada.Strings.Fixed.Index
                   (Low_Level.Signed_Headers (Prepared),
                    "x-amz-security-token") > 0
               then
                  raise Program_Error with
                    "CreateSession TLS identity used the wrong token header";
               end if;
            end;
         end;
         Must_Reject
           ("mismatch", "CreateSession accepted mismatched response policy");
         Must_Reject
           ("duplicate", "CreateSession accepted duplicate physical header");
         Must_Reject
           ("empty", "CreateSession accepted present-empty physical header");
         Must_Reject
           ("bool", "CreateSession accepted noncanonical boolean header");
         HTTP_Client.Shutdown (HTTP);
      end;
   end Run_Client;

begin
   OpenSSL.Initialize_Client (Client_Backend, CA_File => Certificate);
   OpenSSL.Initialize_Server
     (Server_Backend, Certificate_File => Certificate,
      Private_Key_File => Private_Key);
   declare
      task Raw_TLS_Server is
         pragma Task_Info (Flyology.Native_Task);
      end Raw_TLS_Server;

      task body Raw_TLS_Server is
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
              (Listener, Peer, Address, Timeout => 10.0, Status => Status);
            if Status /= Sockets.Completed then
               raise Program_Error with "CreateSession TLS accept timed out";
            end if;
            declare
               Secure : TLS.Connection;
               Buffer : Stream_Element_Array (1 .. 4_096);
               Last : Stream_Element_Offset;
               Head : US.Unbounded_String;
            begin
               TLS.Take (Server_Backend, Peer, TLS.Server, "", Secure);
               TLS.Handshake (Secure, Timeout => 5.0);
               loop
                  TLS.Receive (Secure, Buffer, Last, Timeout => 5.0);
                  if Last < Buffer'First then
                     raise Program_Error with
                       "CreateSession TLS client closed before request";
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
                  Key_ID : constant String := Header_Value
                    (Request,
                     "x-amz-server-side-encryption-aws-kms-key-id");
                  Payload : constant String := Session_XML (Key_ID);
                  Extra : US.Unbounded_String;
               begin
                  if Ada.Strings.Fixed.Index
                    (Lower, "get /?session http/1.1" & CRLF) /= 1
                    or else Header_Value
                      (Request, "x-amz-create-session-mode") /= "ReadOnly"
                    or else Header_Value
                      (Request, "x-amz-server-side-encryption") /= "aws:kms"
                    or else Header_Value
                      (Request, "x-amz-server-side-encryption-context") /=
                        "e30="
                    or else Header_Value
                      (Request,
                       "x-amz-server-side-encryption-bucket-key-enabled") /=
                        "true"
                    or else Ada.Strings.Fixed.Index
                      (Lower, "authorization: aws4-hmac-sha256 ") = 0
                  then
                     raise Program_Error with
                       "CreateSession TLS signed request mismatch";
                  end if;
                  US.Append
                    (Extra, "x-amz-server-side-encryption: " &
                       (if Key_ID = "mismatch" then "AES256" else "aws:kms") &
                       CRLF);
                  if Key_ID = "duplicate" then
                     US.Append
                       (Extra,
                        "x-amz-server-side-encryption: aws:kms" & CRLF);
                  elsif Key_ID = "empty" then
                     US.Append
                       (Extra,
                        "x-amz-server-side-encryption-context:" & CRLF);
                  else
                     US.Append
                       (Extra,
                        "x-amz-server-side-encryption-context: e30=" & CRLF);
                  end if;
                  US.Append
                    (Extra,
                     "x-amz-server-side-encryption-aws-kms-key-id: " &
                       (if Key_ID = "mismatch" then "other" else Key_ID) &
                       CRLF &
                     "x-amz-server-side-encryption-bucket-key-enabled: " &
                       (if Key_ID = "bool" then "TRUE" else "true") & CRLF);
                  TLS.Send_All
                    (Secure,
                     Bytes (HTTP_Response (Payload, US.To_String (Extra))),
                     Timeout => 5.0);
               end;
               TLS.Shutdown (Secure, Timeout => 5.0);
               TLS.Close (Secure);
            exception
               when others =>
                  TLS.Close (Secure);
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
      end Raw_TLS_Server;

      procedure Run_And_Report is
      begin
         Run_Client;
         Client_Results.Report (True);
      exception
         when Occurrence : others =>
            Client_Results.Report
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
      Client_Results.Wait_All (Clients_Passed, Client_Detail);
      State.Wait_Server (Server_Passed, Server_Detail);
      if not Clients_Passed then
         raise Program_Error with US.To_String (Client_Detail);
      elsif not Server_Passed then
         raise Program_Error with US.To_String (Server_Detail);
      end if;
   end;
   Ada.Text_IO.Put_Line ("S3 CreateSession TLS corpus: OK");
exception
   when Occurrence : others =>
      Ada.Text_IO.Put_Line
        ("S3 CreateSession TLS corpus failed: " &
         Ada.Exceptions.Exception_Information (Occurrence));
      raise;
end S3_Create_Session_TLS_Corpus;
