with Ada.Streams;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP.Server;
with Flyology.HTTP.Server.Applications;
with Flyology.IO.Sockets;
with Flyology.Object_Storage.Server.Authentication;
with Flyology.Object_Storage.Server.S3_Applications;
with Flyology.Object_Storage.Server.Static_Credentials;
with Repro_S3_Server;

package body Repro_SigV4_Support is

   package HTTP_Server renames Flyology.HTTP.Server;
   package Apps renames Flyology.HTTP.Server.Applications;
   package Sockets renames Flyology.IO.Sockets;
   package US renames Ada.Strings.Unbounded;
   package Authentication renames
     Flyology.Object_Storage.Server.Authentication;
   package Static_Credentials renames
     Flyology.Object_Storage.Server.Static_Credentials;

   use type Ada.Streams.Stream_Element_Offset;

   Rules : constant Authentication.Policy :=
     (Expected_Region    =>
        US.To_Unbounded_String (Repro_S3_Server.Region),
      Maximum_Clock_Skew => 900.0);

   Short_Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Repro_S3_Server.Access_Key,
        Repro_S3_Server.Secret_Key,
        Principal => Short_Principal);

   Long_Credentials : Static_Credentials.Provider :=
     Static_Credentials.Create
       (Repro_S3_Server.Access_Key,
        Repro_S3_Server.Secret_Key,
        Principal => Long_Principal);

   package Short_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type             =>
        Flyology.Object_Storage.Backends.Memory.Store,
      Store                    => Short_Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials              => Short_Credentials,
      Rules                    => Rules,
      Torrent_Piece_Length     => 256 * 1_024);

   package Long_App is new Flyology.Object_Storage.Server.S3_Applications
     (Backend_Type             =>
        Flyology.Object_Storage.Backends.Memory.Store,
      Store                    => Long_Store,
      Credential_Provider_Type => Static_Credentials.Provider,
      Credentials              => Long_Credentials,
      Rules                    => Rules,
      Torrent_Piece_Length     => 256 * 1_024);

   ---------------------------------------------------------------------
   --  In-memory transport (same shape as Repro_S3_Server's)
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

   function Run_Short (Raw_Request : String) return String is
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
            Short_App.Handle (X);
         end;
      end;
      return US.To_String (Wire.Output);
   end Run_Short;

   function Run_Long (Raw_Request : String) return String is
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
            Long_App.Handle (X);
         end;
      end;
      return US.To_String (Wire.Output);
   end Run_Long;

end Repro_SigV4_Support;
