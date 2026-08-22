with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP.Server;
with Flyology.HTTP.Server.Applications;
with Flyology.HTTP.Server.Connection_Handlers;
with Flyology.HTTP.Server.Connections;
with Flyology.IO.Connections;
with Flyology.IO.Sockets;
with Flyology.IO.Structured_Servers;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;

procedure S3_Server_Harness is
   package HTTP_Server renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package IO_Connections renames Flyology.IO.Connections;
   package Sockets renames Flyology.IO.Sockets;
   package US renames Ada.Strings.Unbounded;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;

   function Required_Environment (Name : String) return String is
   begin
      if not Ada.Environment_Variables.Exists (Name) then
         raise Program_Error with "missing required environment: " & Name;
      end if;
      return Ada.Environment_Variables.Value (Name);
   end Required_Environment;

   function Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   Port : constant Sockets.Port :=
     (if Ada.Command_Line.Argument_Count = 0 then Sockets.Any_Port
      else Sockets.Port'Value (Ada.Command_Line.Argument (1)));
   Capacity : constant Positive :=
     (if Ada.Command_Line.Argument_Count < 2 then 32
      else Positive'Value (Ada.Command_Line.Argument (2)));
   Region : constant String :=
     (if Ada.Environment_Variables.Exists ("AWS_REGION")
      then Ada.Environment_Variables.Value ("AWS_REGION")
      else "us-east-1");

   Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Required_Environment ("AWS_ACCESS_KEY_ID"),
        Required_Environment ("AWS_SECRET_ACCESS_KEY"),
        (if Ada.Environment_Variables.Exists ("AWS_SESSION_TOKEN")
         then Ada.Environment_Variables.Value ("AWS_SESSION_TOKEN")
         else ""),
        Principal => "qualification");
   Rules : constant Authentication.Policy :=
     (Expected_Region    => US.To_Unbounded_String (Region),
      Maximum_Clock_Skew => 900.0);

   package S3_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type             => Backend_Type,
      Store                    => Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials              => Credentials,
      Rules                    => Rules);

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
         Timeout            => 60.0,
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
   Bound    : Sockets.Endpoint;
   Server   : aliased Structured.Server (Capacity => Capacity);
   Context  : aliased Server_Context;
begin
   Sockets.Create_Socket (Listener);
   Sockets.Set_Socket_Option
     (Listener, Sockets.Socket_Level, (Sockets.Reuse_Address, True));
   Sockets.Bind_Socket
     (Listener, Sockets.Network_Endpoint (Sockets.Loopback_IPv4, Port));
   Sockets.Listen_Socket (Listener, Length => Capacity * 2);
   Bound := Sockets.Get_Socket_Name (Listener);
   Ada.Text_IO.Put_Line ("PORT " & Image (Natural (Bound.Port)));
   Ada.Text_IO.Flush;
   Structured.Serve (Server, Listener, Context, Drain_Timeout => 10.0);
end S3_Server_Harness;
