with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.Cancellation;
with Flyology.HTTP.Server;
with Flyology.HTTP.Server.Applications;
with Flyology.HTTP.Server.Connection_Handlers;
with Flyology.HTTP.Server.Connections;
with Flyology.IO;
with Flyology.IO.Connections;
with Flyology.IO.Sockets;
with Flyology.IO.Structured_Servers;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;
with Repro_Support;

package body Repro_S3_Server is

   package HTTP_Server renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Sockets renames Flyology.IO.Sockets;
   package US renames Ada.Strings.Unbounded;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;
   package IO_Connections renames Flyology.IO.Connections;

   use type Ada.Streams.Stream_Element_Offset;

   CRLF : constant String := Repro_Support.CRLF;

   Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Access_Key, Secret_Key, Principal => Principal);
   Rules : constant Authentication.Policy :=
     (Expected_Region    => US.To_Unbounded_String (Region),
      Maximum_Clock_Skew => 900.0);

   package S3_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type             => Flyology.Object_Storage.Backends.Memory.Store,
      Store                    => Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials              => Credentials,
      Rules                    => Rules,
      Torrent_Piece_Length     => 256 * 1_024);

   ---------------------------------------------------------------------
   --  Timestamp
   ---------------------------------------------------------------------

   function Timestamp return String is
      Image : constant String :=
        Ada.Calendar.Formatting.Image
          (Ada.Calendar.Clock, Time_Zone => 0);
      --  "YYYY-MM-DD HH:MM:SS"
   begin
      return Image (1 .. 4) & Image (6 .. 7) & Image (9 .. 10) & "T" &
        Image (12 .. 13) & Image (15 .. 16) & Image (18 .. 19) & "Z";
   end Timestamp;

   ---------------------------------------------------------------------
   --  Signed_Request
   ---------------------------------------------------------------------

   function Signed_Request
     (Method          : String;
      Path            : String;
      Payload         : String := "";
      Extra_Headers   : String := "";
      Query           : SigV4.Name_Value_Array := No_Query;
      Hash_Override   : String := "";
      Chunked         : Boolean := False;
      Host_Value      : String := Host;
      Timestamp_Value : String := "";
      Keep_Alive      : Boolean := False;
      Signing_Path    : String := "") return String
   is
      Canonical_Path : constant String :=
        (if Signing_Path'Length > 0 then Signing_Path else Path);
      Stamp : constant String :=
        (if Timestamp_Value'Length > 0 then Timestamp_Value else Timestamp);
      Payload_Hash : constant String :=
        (if Hash_Override'Length > 0 then Hash_Override
         else SigV4.SHA256_Hex (Payload));

      function Extra_Header_Count return Natural is
         Result : Natural := 0;
         Cursor : Integer := Extra_Headers'First;
      begin
         while Cursor <= Extra_Headers'Last loop
            declare
               Ending : constant Natural := Ada.Strings.Fixed.Index
                 (Extra_Headers, CRLF, From => Cursor);
            begin
               if Ending = 0 then
                  raise Program_Error with
                    "Extra_Headers must end each field with CRLF";
               end if;
               Result := Result + 1;
               Cursor := Integer (Ending) + CRLF'Length;
            end;
         end loop;
         return Result;
      end Extra_Header_Count;

      Extra_Count : constant Natural := Extra_Header_Count;
      Headers : SigV4.Name_Value_Array (1 .. 3 + Extra_Count);
      Wire_Body : constant String :=
        (if not Chunked then Payload
         elsif Payload'Length = 0 then "0" & CRLF & CRLF
         else Repro_Support.Image (Integer (Payload'Length)) & CRLF &
           Payload & CRLF & "0" & CRLF & CRLF);
      Query_Text : US.Unbounded_String;
   begin
      Headers (1) := SigV4.Pair ("host", Host_Value);
      Headers (2) := SigV4.Pair ("x-amz-content-sha256", Payload_Hash);
      Headers (3) := SigV4.Pair ("x-amz-date", Stamp);
      if Extra_Count > 0 then
         declare
            Cursor : Integer := Extra_Headers'First;
         begin
            for Index in 1 .. Extra_Count loop
               declare
                  Ending : constant Natural := Ada.Strings.Fixed.Index
                    (Extra_Headers, CRLF, From => Cursor);
                  Line : constant String :=
                    Extra_Headers (Cursor .. Integer (Ending) - 1);
                  Colon : constant Natural :=
                    Ada.Strings.Fixed.Index (Line, ":");
               begin
                  if Colon = 0 or else Colon = Line'First then
                     raise Program_Error with
                       "Extra_Headers contains a malformed field";
                  end if;
                  Headers (3 + Index) := SigV4.Pair
                    (Line (Line'First .. Integer (Colon) - 1),
                     Repro_Support.Trim (Line (Integer (Colon) + 1 .. Line'Last)));
                  Cursor := Integer (Ending) + CRLF'Length;
               end;
            end loop;
         end;
      end if;
      for Index in Query'Range loop
         US.Append (Query_Text, (if Index = Query'First then "?" else "&"));
         US.Append (Query_Text, US.To_String (Query (Index).Name));
         if US.Length (Query (Index).Value) > 0 then
            US.Append (Query_Text, "=");
            US.Append (Query_Text, US.To_String (Query (Index).Value));
         end if;
      end loop;
      declare
         Signing : constant SigV4.Signing_Result := SigV4.Sign
           (Method, Canonical_Path, Query, Headers, Payload_Hash, Access_Key,
            Secret_Key, Region, Stamp);
      begin
         return Method & " " & Path & US.To_String (Query_Text) &
           " HTTP/1.1" & CRLF &
           "Host: " & Host_Value & CRLF &
           "x-amz-date: " & Stamp & CRLF &
           "x-amz-content-sha256: " & Payload_Hash & CRLF &
           "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
           Extra_Headers &
           (if Chunked then "Transfer-Encoding: chunked" & CRLF
            else "Content-Length: " &
              Repro_Support.Image (Integer (Payload'Length)) & CRLF) &
           (if Keep_Alive then "" else "Connection: close" & CRLF) &
           CRLF & Wire_Body;
      end;
   end Signed_Request;

   ---------------------------------------------------------------------
   --  In-process exchange
   ---------------------------------------------------------------------

   type Memory_Transport is limited new HTTP_Server.Transport with record
      Input  : US.Unbounded_String;
      Output : US.Unbounded_String;
   end record;

   overriding procedure Receive
     (Item    : in out Memory_Transport;
      Data    : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token);

   overriding procedure Send_All
     (Item    : in out Memory_Transport;
      Data    : Ada.Streams.Stream_Element_Array;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token);

   overriding procedure Receive
     (Item    : in out Memory_Transport;
      Data    : out Ada.Streams.Stream_Element_Array;
      Last    : out Ada.Streams.Stream_Element_Offset;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
      Available : constant String := US.To_String (Item.Input);
      Count     : Natural;
   begin
      Data := [others => 0];
      Last := Data'First - 1;
      if Available'Length = 0 then
         return;
      end if;
      Count := Natural'Min (Natural (Data'Length), Available'Length);
      for Index in 1 .. Count loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Index - 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Available (Index)));
      end loop;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count - 1);
      Item.Input :=
        (if Count = Available'Length then US.Null_Unbounded_String
         else US.To_Unbounded_String
           (Available (Count + 1 .. Available'Last)));
   end Receive;

   overriding procedure Send_All
     (Item    : in out Memory_Transport;
      Data    : Ada.Streams.Stream_Element_Array;
      Timeout : Duration;
      Token   : access Flyology.Cancellation.Token)
   is
      pragma Unreferenced (Timeout, Token);
   begin
      for Value of Data loop
         US.Append (Item.Output, Character'Val (Value));
      end loop;
   end Send_All;

   function Run (Raw_Request : String) return String is
      Wire : aliased Memory_Transport;
   begin
      Wire.Input := US.To_Unbounded_String (Raw_Request);
      declare
         Client  : aliased HTTP_Server.Connection (Wire'Access);
         Request : aliased HTTP_Server.Request;
         Closed  : Boolean;
      begin
         HTTP_Server.Read_Request_Head (Client, Request, Closed);
         if Closed then
            raise Program_Error with "peer closed before S3 request head";
         end if;
         declare
            X : Apps.Exchange := Apps.Create
              (Request, Client,
               Sockets.Network_Endpoint (Sockets.Loopback_IPv4, 12_345),
               null, HTTP_Server.Request_Deadline (Client));
         begin
            S3_App.Handle (X);
         end;
      end;
      return US.To_String (Wire.Output);
   end Run;

   ---------------------------------------------------------------------
   --  Loopback listener
   ---------------------------------------------------------------------

   type Server_Context is limited null record;

   procedure Handle_Connection
     (Context      : in out Server_Context;
      Connection   : in out IO_Connections.Connection;
      Peer         : Sockets.Endpoint;
      Cancellation : not null access IO_Connections.Cancellation_Token)
   is
      pragma Unreferenced (Context);
      Transport : aliased HTTP_Server.Connections.Connection_Transport
        (Connection'Access);
      HTTP : aliased HTTP_Server.Connection (Transport'Access);

      procedure Dispatch
        (Item  : in out HTTP_Server.Connection;
         Value : HTTP_Server.Request)
      is
         pragma Unreferenced (Item);
         Request : aliased HTTP_Server.Request := Value;
         X : Apps.Exchange := Apps.Create
           (Request, HTTP, Peer, Cancellation,
            HTTP_Server.Request_Deadline (HTTP));
      begin
         S3_App.Handle (X);
      end Dispatch;

      package Handlers is new HTTP_Server.Connection_Handlers (Dispatch);
   begin
      Handlers.Serve
        (HTTP,
         Timeout            => 30.0,
         Max_Body           => HTTP_Server.Max_Request_Body,
         Buffer_Body        => False,
         Max_Requests       => 10_000,
         Max_Connection_Age => 600.0,
         Token              => Cancellation);
   end Handle_Connection;

   package Structured is new Flyology.IO.Structured_Servers
     (Handler_Context => Server_Context,
      Handle          => Handle_Connection);

   Listener : Sockets.Socket_Type;
   Server   : aliased Structured.Server (Capacity => 8);
   Context  : aliased Server_Context;
   Started  : Boolean := False;

   task Server_Task is
      entry Start;
   end Server_Task;

   task body Server_Task is
   begin
      select
         accept Start;
      or
         terminate;
      end select;
      Structured.Serve (Server, Listener, Context, Drain_Timeout => 5.0);
   exception
      when E : others =>
         Ada.Text_IO.Put_Line
           ("  -- loopback server task ended: " &
              Ada.Exceptions.Exception_Information (E));
   end Server_Task;

   procedure Start_Loopback (Port : out Natural) is
      Bound : Sockets.Endpoint;
   begin
      if Started then
         raise Program_Error with "loopback server already started";
      end if;
      Started := True;
      Sockets.Create_Socket (Listener);
      Sockets.Set_Socket_Option
        (Listener, Sockets.Socket_Level, (Sockets.Reuse_Address, True));
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint (Sockets.Loopback_IPv4, Sockets.Any_Port));
      Sockets.Listen_Socket (Listener, Length => 16);
      Bound := Sockets.Get_Socket_Name (Listener);
      Port := Natural (Bound.Port);
      Server_Task.Start;
   end Start_Loopback;

   procedure Stop_Loopback is
   begin
      if Started then
         Structured.Request_Shutdown (Server);
      end if;
   end Stop_Loopback;

   function Exchange_Over_Socket
     (Port        : Natural;
      Raw_Request : String;
      Timeout     : Duration := 10.0) return String
   is
      Peer   : Sockets.Socket_Type;
      Result : US.Unbounded_String;
      Buffer : Ada.Streams.Stream_Element_Array (1 .. 65_536);
      Last   : Ada.Streams.Stream_Element_Offset;
      Data   : Ada.Streams.Stream_Element_Array (1 .. Raw_Request'Length);
   begin
      for Index in Raw_Request'Range loop
         Data (Ada.Streams.Stream_Element_Offset
                 (Index - Raw_Request'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Raw_Request (Index)));
      end loop;
      Sockets.Create_Socket (Peer);
      Sockets.Connect_Socket
        (Peer,
         Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Sockets.Port (Port)));
      Sockets.Send_All (Peer, Data, Timeout => Timeout);
      begin
         loop
            Sockets.Receive (Peer, Buffer, Last, Timeout => Timeout);
            exit when Last < Buffer'First;
            for Index in Buffer'First .. Last loop
               US.Append (Result, Character'Val (Buffer (Index)));
            end loop;
         end loop;
      exception
         when Flyology.IO.Timeout_Error =>
            null;
      end;
      Sockets.Close_Socket (Peer);
      return US.To_String (Result);
   end Exchange_Over_Socket;

end Repro_S3_Server;
