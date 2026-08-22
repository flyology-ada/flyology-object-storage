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

procedure Flyology_Object_Storage_Server_Runtime is
   package HTTP renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Owned renames Flyology.IO.Connections;
   package Sockets renames Flyology.IO.Sockets;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;
   package US renames Ada.Strings.Unbounded;

   use type Flyology.Supervision.Supervisor_Outcome;

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

   type Application_Context is limited null record;

   procedure Run_S3
     (Context : in out Application_Context;
      Control : not null access Flyology.Supervision.Generation_Control)
   is
      pragma Unreferenced (Context);

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

   package S3_Child is new Flyology.Supervision.Children
     (Application_Context => Application_Context,
      Execute             => Run_S3,
      Task_Model          => Flyology.Native_Task);

   type Service_Kind is (S3_Service);

   function Logical_Id
     (Child : Service_Kind) return Flyology.Supervision.Child_Id
   is (case Child is when S3_Service => 1);

   function Specification
     (Child : Service_Kind) return Flyology.Supervision.Child_Specification
   is
      pragma Unreferenced (Child);
      Value : Flyology.Supervision.Child_Specification := (others => <>);
   begin
      Value.Restart := Flyology.Supervision.On_Failure;
      Value.Impact := Flyology.Supervision.Isolate_Child;
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
      pragma Unreferenced (Child, Prerequisite);
   begin
      return False;
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
      pragma Unreferenced (Child);
   begin
      S3_Child.Run (Context, Control, Result);
   end Run_One_Generation;

   package Supervisors is new Flyology.Supervision.Static
     (Child_Kind          => Service_Kind,
      Application_Context => Application_Context,
      Logical_Id          => Logical_Id,
      Specification       => Specification,
      Depends_On          => Depends_On,
      Cohort_Member       => No_Cohort,
      Run_One_Generation  => Run_One_Generation);

   Context    : aliased Application_Context;
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
