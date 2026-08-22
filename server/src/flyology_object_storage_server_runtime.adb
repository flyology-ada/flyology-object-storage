with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology;
with Flyology.HTTP.Server;
with Flyology.HTTP.Server.Applications;
with Flyology.HTTP.Server.Connection_Handlers;
with Flyology.HTTP.Server.Connections;
with Flyology.HTTP.Server.Responses;
with Flyology.HTTP.Server.Routing;
with Flyology.IO.Connections;
with Flyology.IO.Sockets;
with Flyology.IO.Structured_Servers;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;
with Flyology.Supervision;
with Flyology.Supervision.Children;
with Flyology.Supervision.Static;
with Flyology_Object_Storage_Server_Signals;
with Flyology_Object_Storage_Server_Assets;
with Flyology_Object_Storage_Server_Credentials;
with Flyology_Object_Storage_Server_Sessions;

procedure Flyology_Object_Storage_Server_Runtime is
   package HTTP renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Responses renames Flyology.HTTP.Server.Responses;
   package Owned renames Flyology.IO.Connections;
   package Sockets renames Flyology.IO.Sockets;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;
   package US renames Ada.Strings.Unbounded;
   package Admin_Credentials renames
     Flyology_Object_Storage_Server_Credentials;

   use type Flyology.Supervision.Supervisor_Outcome;
   use type Sockets.Port;

   function Required_Environment (Name : String) return String is
   begin
      if not Ada.Environment_Variables.Exists (Name)
        or else Ada.Environment_Variables.Value (Name)'Length = 0
      then
         raise Constraint_Error with
           "missing required environment: " & Name;
      end if;
      return Ada.Environment_Variables.Value (Name);
   end Required_Environment;

   function Compact (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

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
        Principal => "server");
   Rules : constant Authentication.Policy :=
     (Expected_Region    => US.To_Unbounded_String (Region),
      Maximum_Clock_Skew => 900.0);

   package S3_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type             => Backend_Type,
      Store                    => Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials              => Credentials,
      Rules                    => Rules);

   protected type Runtime_Status is
      procedure Set_S3_Endpoint (Value : Sockets.Endpoint);
      procedure Set_Admin_Port (Value : Sockets.Port);
      function S3_Address return Sockets.IP_Address;
      function S3_Port return Sockets.Port;
      function Admin_Port return Sockets.Port;
   private
      Bound_S3_Port : Sockets.Port := 0;
      Bound_S3_Address : Sockets.IP_Address := Sockets.Loopback_IPv4;
      Bound_Admin_Port : Sockets.Port := 0;
   end Runtime_Status;

   protected body Runtime_Status is
      procedure Set_S3_Endpoint (Value : Sockets.Endpoint) is
      begin
         Bound_S3_Address := Value.Address;
         Bound_S3_Port := Value.Port;
      end Set_S3_Endpoint;

      procedure Set_Admin_Port (Value : Sockets.Port) is
      begin
         Bound_Admin_Port := Value;
      end Set_Admin_Port;

      function S3_Address return Sockets.IP_Address is (Bound_S3_Address);
      function S3_Port return Sockets.Port is (Bound_S3_Port);
      function Admin_Port return Sockets.Port is (Bound_Admin_Port);
   end Runtime_Status;

   type Application_Context is record
      Sessions : access Flyology_Object_Storage_Server_Sessions.Store;
      Status   : access Runtime_Status;
      Assets   : Flyology_Object_Storage_Server_Assets.Bundle;
   end record;

   procedure Run_S3
     (Context : in out Application_Context;
      Control : not null access Flyology.Supervision.Generation_Control)
   is
      type Server_Context is limited null record;

      procedure Handle
        (State        : in out Server_Context;
         Connection   : in out Owned.Connection;
         Peer         : Sockets.Endpoint;
         Cancellation : not null access Owned.Cancellation_Token)
      is
         pragma Unreferenced (State);
         Channel : aliased HTTP.Connections.Connection_Transport
           (Connection'Unchecked_Access);
         Client : aliased HTTP.Connection (Channel'Access);

         procedure Dispatch
           (Item : in out HTTP.Connection;
            Request_Value : HTTP.Request)
         is
            pragma Unreferenced (Item);
            Request : aliased HTTP.Request := Request_Value;
            X : Apps.Exchange := Apps.Create
              (Request, Client, Peer, Cancellation,
               HTTP.Request_Deadline (Client));
         begin
            S3_App.Handle (X);
         end Dispatch;

         package Handlers is new HTTP.Connection_Handlers (Dispatch);
      begin
         Handlers.Serve
           (Client,
            Timeout            => 60.0,
            Max_Body           => HTTP.Max_Request_Body,
            Buffer_Body        => False,
            Max_Requests       => 10_000,
            Max_Connection_Age => 600.0,
            Token              => Cancellation);
      end Handle;

      package Structured is new Flyology.IO.Structured_Servers
        (Handler_Context => Server_Context,
         Handle          => Handle,
         Handler_Model   => Flyology.Lightweight_Task);

      Listener : Sockets.Socket_Type;
      Bound    : Sockets.Endpoint;
      Server : aliased Structured.Server
        (Capacity => Configuration.Capacity);
      State    : aliased Server_Context;

      protected Lifecycle is
         procedure Complete;
         function Done return Boolean;
      private
         Finished : Boolean := False;
      end Lifecycle;

      protected body Lifecycle is
         procedure Complete is
         begin
            Finished := True;
         end Complete;
         function Done return Boolean is (Finished);
      end Lifecycle;
   begin
      Sockets.Create_Socket (Listener);
      Sockets.Set_Socket_Option
        (Listener, Sockets.Socket_Level, (Sockets.Reuse_Address, True));
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint
           (Configuration.S3_Address, Configuration.S3_Port));
      Sockets.Listen_Socket (Listener, Length => Configuration.Capacity * 2);
      Bound := Sockets.Get_Socket_Name (Listener);
      Context.Status.Set_S3_Endpoint (Bound);
      Flyology.Supervision.Mark_Ready (Control.all);
      Ada.Text_IO.Put_Line
        ("READY s3 http://" & Sockets.Image (Bound.Address) & ":" &
         Compact (Natural (Bound.Port)) &
         " backend=" &
         Flyology_Object_Storage_Server_Configuration.Image
           (Configuration.Backend));
      Ada.Text_IO.Flush;

      declare
         task Stopper is
            pragma Task_Info (Flyology.Native_Task);
         end Stopper;

         task body Stopper is
         begin
            loop
               exit when Lifecycle.Done;
               if Flyology.Supervision.Stopping (Control.all).Requested then
                  Structured.Request_Shutdown (Server);
                  exit;
               end if;
               delay 0.050;
            end loop;
         end Stopper;
      begin
         begin
            Structured.Serve
              (Server, Listener, State, Drain_Timeout => 10.0);
            Lifecycle.Complete;
         exception
            when others =>
               Lifecycle.Complete;
               raise;
         end;
      end;
   end Run_S3;

   procedure Run_Management
     (Context : in out Application_Context;
      Control : not null access Flyology.Supervision.Generation_Control)
   is
      package Routing is new Flyology.HTTP.Server.Routing
        (Application_Context);

      Cookie_Name : constant String := "flyology_admin";
      Login_Prefix : constant String := "username=admin&password=";

      function Session_Token (X : Apps.Exchange) return String is
      begin
         if X.Request_Header_Count ("Cookie") /= 1 then
            return "";
         end if;
         declare
            Header : constant String := X.Request_Header ("Cookie");
            Marker : constant String := Cookie_Name & "=";
            Cursor : Natural := Header'First;
            Found  : US.Unbounded_String;
            Seen   : Boolean := False;
         begin
            while Cursor <= Header'Last loop
               declare
                  Separator : constant Natural :=
                    Ada.Strings.Fixed.Index (Header, ";", From => Cursor);
                  Segment_Last : constant Natural :=
                    (if Separator = 0 then Header'Last else Separator - 1);
                  Segment : constant String := Ada.Strings.Fixed.Trim
                    (Header (Cursor .. Segment_Last), Ada.Strings.Both);
               begin
                  if Segment'Length >= Marker'Length
                    and then Segment
                      (Segment'First .. Segment'First + Marker'Length - 1) =
                        Marker
                  then
                     if Seen then
                        return "";
                     end if;
                     Seen := True;
                     Found := US.To_Unbounded_String
                       (Segment
                          (Segment'First + Marker'Length .. Segment'Last));
                  end if;
                  exit when Separator = 0;
                  Cursor := Separator + 1;
               end;
            end loop;
            return US.To_String (Found);
         end;
      end Session_Token;

      function Authenticated
        (State : Application_Context; X : Apps.Exchange) return Boolean
      is
         Token : constant String := Session_Token (X);
      begin
         return State.Sessions.Valid (Token, Ada.Real_Time.Clock);
      end Authenticated;

      function Local_Authority
        (State : Application_Context) return String
      is
        (if State.Status.Admin_Port = 80
         then "127.0.0.1"
         else "127.0.0.1:" &
           Compact (Natural (State.Status.Admin_Port)));

      function Local_Request
        (State : Application_Context; X : Apps.Exchange) return Boolean
      is (X.Request_Authority = Local_Authority (State));

      function Same_Origin
        (State : Application_Context; X : Apps.Exchange) return Boolean
      is
         Count : constant Natural := X.Request_Header_Count ("Origin");
      begin
         return Local_Request (State, X)
           and then (Count = 0
           or else (Count = 1 and then X.Request_Header ("Origin") =
             "http://" & Local_Authority (State)));
      end Same_Origin;

      function JSON_Escape (Value : String) return String is
         Result : US.Unbounded_String;
      begin
         for Item of Value loop
            if Item = '"' or else Item = '\' then
               US.Append (Result, Character'Val (16#5C#));
               US.Append (Result, Item);
            elsif Character'Pos (Item) < 32 then
               US.Append (Result, '?');
            else
               US.Append (Result, Item);
            end if;
         end loop;
         return US.To_String (Result);
      end JSON_Escape;

      procedure No_Store (X : in out Apps.Exchange) is
      begin
         X.Set_Header ("Cache-Control", "no-store");
         X.Set_Header ("X-Content-Type-Options", "nosniff");
         X.Set_Header ("Cross-Origin-Resource-Policy", "same-origin");
         X.Set_Header ("Referrer-Policy", "no-referrer");
         X.Set_Header ("X-Frame-Options", "DENY");
         X.Set_Header
           ("Content-Security-Policy",
            "default-src 'self'; object-src 'none'; base-uri 'none'; " &
            "frame-ancestors 'none'; form-action 'self'");
      end No_Store;

      procedure Home
        (State : in out Application_Context; X : in out Apps.Exchange)
      is
      begin
         No_Store (X);
         if not Local_Request (State, X) then
            X.Respond
              (421, "text/plain; charset=utf-8", "misdirected request");
            return;
         end if;
         X.Respond
           (200, "text/html; charset=utf-8",
            US.To_String (State.Assets.HTML));
      end Home;

      procedure Stylesheet
        (State : in out Application_Context; X : in out Apps.Exchange) is
      begin
         No_Store (X);
         if not Local_Request (State, X) then
            X.Respond
              (421, "text/plain; charset=utf-8", "misdirected request");
            return;
         end if;
         X.Respond
           (200, "text/css; charset=utf-8",
            US.To_String (State.Assets.Stylesheet));
      end Stylesheet;

      procedure Script
        (State : in out Application_Context; X : in out Apps.Exchange) is
      begin
         No_Store (X);
         if not Local_Request (State, X) then
            X.Respond
              (421, "text/plain; charset=utf-8", "misdirected request");
            return;
         end if;
         X.Respond
           (200, "text/javascript; charset=utf-8",
            US.To_String (State.Assets.Script));
      end Script;

      procedure Login
        (State : in out Application_Context; X : in out Apps.Exchange)
      is
         Form : constant String := X.Content;
      begin
         No_Store (X);
         if not Same_Origin (State, X)
           or else Form'Length /= Login_Prefix'Length +
             Admin_Credentials.Generated_Password_Length
           or else Form
             (Form'First .. Form'First + Login_Prefix'Length - 1) /=
             Login_Prefix
           or else not Admin_Credentials.Verify
             (Admin_Credential, "admin",
              Form (Form'First + Login_Prefix'Length .. Form'Last))
         then
            X.JSON (401, "{""authenticated"":false}");
            return;
         end if;
         declare
            Token : String :=
              Admin_Credentials.Random_Token;
            Options : constant Responses.Cookie_Options :=
              (Secure      => False,
               HTTP_Only   => True,
               SameSite    => Responses.SameSite_Strict,
               Path        => US.To_Unbounded_String ("/"),
               Has_Max_Age => True,
               Max_Age     => 43_200,
               others      => <>);
         begin
            State.Sessions.Create (Token, Ada.Real_Time.Clock);
            Responses.Set_Cookie (X, Cookie_Name, Token, Options);
            Admin_Credentials.Wipe (Token);
         exception
            when others =>
               State.Sessions.Revoke (Token);
               Admin_Credentials.Wipe (Token);
               raise;
         end;
         X.JSON (200, "{""authenticated"":true}");
      end Login;

      procedure Status
        (State : in out Application_Context; X : in out Apps.Exchange) is
      begin
         No_Store (X);
         if not Local_Request (State, X)
           or else not Authenticated (State, X)
         then
            X.JSON (401, "{""authenticated"":false}");
            return;
         end if;
         X.JSON
           (200, "{""authenticated"":true,""backend"":""" &
            Flyology_Object_Storage_Server_Configuration.Image
              (Configuration.Backend) & """,""region"":""" &
            JSON_Escape (Region) & """,""s3_address"":""" &
            Sockets.Image (State.Status.S3_Address) & """,""s3_port"":" &
            Compact (Natural (State.Status.S3_Port)) & "}");
      end Status;

      procedure Logout
        (State : in out Application_Context; X : in out Apps.Exchange)
      is
         Token : constant String := Session_Token (X);
         Options : constant Responses.Cookie_Options :=
           (Secure      => False,
            HTTP_Only   => True,
            SameSite    => Responses.SameSite_Strict,
            Path        => US.To_Unbounded_String ("/"),
            Has_Max_Age => True,
            Max_Age     => 0,
            others      => <>);
      begin
         No_Store (X);
         if not Same_Origin (State, X)
           or else not Authenticated (State, X)
         then
            X.JSON (401, "{""authenticated"":false}");
            return;
         end if;
         State.Sessions.Revoke (Token);
         Responses.Set_Cookie (X, Cookie_Name, "", Options);
         X.JSON (200, "{""authenticated"":false}");
      end Logout;

      type Service_Context is limited record
         Application : aliased Application_Context;
         Routes : aliased Routing.Router
           (Capacity => 6, Slashes => Routing.Strict_Slashes);
         Budget : aliased HTTP.Ingress_Budget (Limit => 4 * 1_024);
      end record;

      procedure Handle
        (State : in out Service_Context;
         Connection : in out Owned.Connection;
         Peer : Sockets.Endpoint;
         Cancellation : not null access Owned.Cancellation_Token)
      is
         Channel : aliased HTTP.Connections.Connection_Transport
           (Connection'Unchecked_Access);
         Client : aliased HTTP.Connection (Channel'Access);
      begin
         HTTP.Configure_Ingress_Budget (Client, State.Budget'Access);
         State.Routes.Serve
           (State.Application, Client, Peer, Timeout => 30.0,
            Header_Timeout => 5.0, Token => Cancellation);
      end Handle;

      package Structured is new Flyology.IO.Structured_Servers
        (Handler_Context => Service_Context,
         Handle => Handle,
         Handler_Model => Flyology.Lightweight_Task);

      Server : aliased Structured.Server (Capacity => 32);
      State : aliased Service_Context;
      Listener : Sockets.Socket_Type;
      Bound : Sockets.Endpoint;
      protected Lifecycle is
         procedure Complete;
         function Done return Boolean;
      private
         Finished : Boolean := False;
      end Lifecycle;
      protected body Lifecycle is
         procedure Complete is
         begin
            Finished := True;
         end Complete;
         function Done return Boolean is (Finished);
      end Lifecycle;
   begin
      State.Application := Context;
      State.Routes.Get ("/", Home'Access, Name => "admin.home");
      State.Routes.Get
        ("/assets/app.css", Stylesheet'Access, Name => "admin.assets.css");
      State.Routes.Get
        ("/assets/app.js", Script'Access, Name => "admin.assets.js");
      State.Routes.Post
        ("/api/login", Login'Access, Name => "admin.login",
         Policy =>
           (Routing.Default_Route_Policy with delta
              Body_Handling => Apps.Buffer_Body, Max_Body => 256,
              Concurrency => 1, Rate_Per_Second => 2));
      State.Routes.Get
        ("/api/status", Status'Access, Name => "admin.status");
      State.Routes.Post
        ("/api/logout", Logout'Access, Name => "admin.logout",
         Policy =>
           (Routing.Default_Route_Policy with delta
              Concurrency => 4, Rate_Per_Second => 4));
      Sockets.Create_Socket (Listener);
      Sockets.Set_Socket_Option
        (Listener, Sockets.Socket_Level, (Sockets.Reuse_Address, True));
      Sockets.Bind_Socket
        (Listener, Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Configuration.Admin_Port));
      Sockets.Listen_Socket (Listener, Length => 64);
      Bound := Sockets.Get_Socket_Name (Listener);
      Context.Status.Set_Admin_Port (Bound.Port);
      Flyology.Supervision.Mark_Ready (Control.all);
      Ada.Text_IO.Put_Line
        ("READY admin http://127.0.0.1:" & Compact (Natural (Bound.Port)) &
         "/");
      Ada.Text_IO.Flush;
      declare
         task Stopper is
            pragma Task_Info (Flyology.Native_Task);
         end Stopper;
         task body Stopper is
         begin
            loop
               exit when Lifecycle.Done;
               if Flyology.Supervision.Stopping (Control.all).Requested then
                  Structured.Request_Shutdown (Server);
                  exit;
               end if;
               delay 0.050;
            end loop;
         end Stopper;
      begin
         begin
            Structured.Serve
              (Server, Listener, State, Drain_Timeout => 2.0);
            Lifecycle.Complete;
         exception
            when others =>
               Lifecycle.Complete;
               raise;
         end;
      end;
   end Run_Management;

   package S3_Child is new Flyology.Supervision.Children
     (Application_Context => Application_Context,
      Execute             => Run_S3,
      Task_Model          => Flyology.Native_Task);

   package Management_Child is new Flyology.Supervision.Children
     (Application_Context => Application_Context,
      Execute             => Run_Management,
      Task_Model          => Flyology.Native_Task);

   type Service_Kind is (S3_Service, Management_Service);

   function Logical_Id
     (Child : Service_Kind) return Flyology.Supervision.Child_Id
   is (case Child is
         when S3_Service         => 1,
         when Management_Service => 2);

   function Specification
     (Child : Service_Kind) return Flyology.Supervision.Child_Specification
   is
      Value : Flyology.Supervision.Child_Specification := (others => <>);
   begin
      Value.Restart := Flyology.Supervision.On_Failure;
      Value.Impact :=
        (if Child = S3_Service
         then Flyology.Supervision.Restart_Dependents
         else Flyology.Supervision.Isolate_Child);
      Value.Stopping :=
        (Grace             => Ada.Real_Time.Seconds (12),
         Request_Abort     => False,
         Abort_Observation => Ada.Real_Time.Seconds (1));
      Value.Readiness_Timeout := Ada.Real_Time.Seconds (15);
      Value.Restart_Safe := True;
      Value.Task_Model := Flyology.Native_Task;
      return Value;
   end Specification;

   function Depends_On
     (Child, Prerequisite : Service_Kind) return Boolean
   is
   begin
      return Child = Management_Service and then Prerequisite = S3_Service;
   end Depends_On;

   function No_Cohort
     (Trigger, Member : Service_Kind) return Boolean
   is
      pragma Unreferenced (Trigger, Member);
   begin
      return False;
   end No_Cohort;

   procedure Run_One_Generation
     (Context : aliased in out Application_Context;
      Child   : Service_Kind;
      Control : aliased in out Flyology.Supervision.Generation_Control;
      Result  : out Flyology.Supervision.Generation_Result)
   is
   begin
      case Child is
         when S3_Service =>
            S3_Child.Run (Context, Control, Result);
         when Management_Service =>
            Management_Child.Run (Context, Control, Result);
      end case;
   end Run_One_Generation;

   package Supervisors is new Flyology.Supervision.Static
     (Child_Kind          => Service_Kind,
      Application_Context => Application_Context,
      Logical_Id          => Logical_Id,
      Specification       => Specification,
      Depends_On          => Depends_On,
      Cohort_Member       => No_Cohort,
      Run_One_Generation  => Run_One_Generation);

   Session_State : aliased Flyology_Object_Storage_Server_Sessions.Store;
   Status_State  : aliased Runtime_Status;
   Context       : aliased Application_Context :=
     (Sessions => Session_State'Access,
      Status   => Status_State'Access,
      Assets   => (others => <>));
   Supervisor : aliased Supervisors.Supervisor;
   Result     : Flyology.Supervision.Supervisor_Result;

   task Signal_Watcher is
      pragma Task_Info (Flyology.Native_Task);
   end Signal_Watcher;

   task body Signal_Watcher is
   begin
      loop
         exit when Flyology_Object_Storage_Server_Signals.Completed;
         if Flyology_Object_Storage_Server_Signals.Stop_Requested then
            Supervisors.Request_Shutdown (Supervisor);
            exit;
         end if;
         delay 0.050;
      end loop;
   end Signal_Watcher;
begin
   Flyology_Object_Storage_Server_Assets.Load (Context.Assets);
   Supervisors.Run (Supervisor, Context, Result);
   Flyology_Object_Storage_Server_Signals.Complete;
   if Result.Outcome /= Flyology.Supervision.Shutdown_Completed then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "object-storage server stopped: " & Result.Outcome'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
exception
   when Error : others =>
      Flyology_Object_Storage_Server_Signals.Complete;
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "object-storage server failed: " &
         Ada.Exceptions.Exception_Information (Error));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Flyology_Object_Storage_Server_Runtime;
