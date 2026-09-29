with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.IO;
with Flyology.IO.Sockets;

package body Repro_Client_Objects_Fake is

   package US renames Ada.Strings.Unbounded;
   package Sockets renames Flyology.IO.Sockets;
   use type Ada.Streams.Stream_Element_Offset;
   use type Sockets.Selector_Status;

   CRLF : constant String := ASCII.CR & ASCII.LF;

   --  Test fixture capacity: the largest reproduction program in this area
   --  scripts eight exchanges.
   Capacity : constant := 32;

   type Text_Array is array (1 .. Capacity) of US.Unbounded_String;

   protected State is
      procedure Add (Item : String);
      procedure Take (Item : out US.Unbounded_String; Found : out Boolean);
      procedure Store_Head (Item : String);
      function Head_Text (Index : Positive) return String;
      function Head_Count return Natural;
      function Remaining return Natural;
      procedure Set_Error (Item : String);
      function Error_Text return String;
      procedure Request_Stop;
      function Stopping return Boolean;
   private
      Responses  : Text_Array;
      Heads      : Text_Array;
      Scripted   : Natural := 0;
      Next       : Natural := 0;
      Received   : Natural := 0;
      Detail     : US.Unbounded_String;
      Stop_Asked : Boolean := False;
   end State;

   protected body State is

      procedure Add (Item : String) is
      begin
         Scripted := Scripted + 1;
         Responses (Scripted) := US.To_Unbounded_String (Item);
      end Add;

      procedure Take (Item : out US.Unbounded_String; Found : out Boolean) is
      begin
         if Next < Scripted then
            Next := Next + 1;
            Item := Responses (Next);
            Found := True;
         else
            Item := US.Null_Unbounded_String;
            Found := False;
         end if;
      end Take;

      procedure Store_Head (Item : String) is
      begin
         Received := Received + 1;
         Heads (Received) := US.To_Unbounded_String (Item);
      end Store_Head;

      function Head_Text (Index : Positive) return String is
        (if Index <= Received then US.To_String (Heads (Index)) else "");

      function Head_Count return Natural is (Received);

      function Remaining return Natural is (Scripted - Next);

      procedure Set_Error (Item : String) is
      begin
         Detail := US.To_Unbounded_String (Item);
      end Set_Error;

      function Error_Text return String is (US.To_String (Detail));

      procedure Request_Stop is
      begin
         Stop_Asked := True;
      end Request_Stop;

      function Stopping return Boolean is (Stop_Asked);

   end State;

   Listener : Sockets.Socket_Type;

   function Lower (Value : String) return String
     renames Ada.Characters.Handling.To_Lower;

   function Complete_Request (Text : String) return Boolean is
      Separator : constant Natural :=
        Ada.Strings.Fixed.Index (Text, CRLF & CRLF);
   begin
      if Separator = 0 then
         return False;
      end if;
      declare
         Head  : constant String := Lower (Text (Text'First .. Separator + 3));
         Body_Bytes : constant Natural := Text'Last - (Separator + 3);
         Chunked : constant Natural :=
           Ada.Strings.Fixed.Index (Head, "transfer-encoding:");
         Marker  : constant Natural :=
           Ada.Strings.Fixed.Index (Head, "content-length:");
      begin
         if Chunked /= 0 then
            return Ada.Strings.Fixed.Index
              (Text (Separator + 4 .. Text'Last),
               "0" & CRLF & CRLF) /= 0;
         elsif Marker = 0 then
            return True;
         end if;
         declare
            Tail : constant String := Head (Marker + 15 .. Head'Last);
            Stop : constant Natural := Ada.Strings.Fixed.Index (Tail, CRLF);
            Digits_Text : constant String :=
              Ada.Strings.Fixed.Trim
                (Tail (Tail'First .. Stop - 1), Ada.Strings.Both);
         begin
            return Body_Bytes >= Natural'Value (Digits_Text);
         end;
      end;
   exception
      when others =>
         return True;
   end Complete_Request;

   procedure Send_Text (Peer : Sockets.Socket_Type; Text : String) is
      Data : Ada.Streams.Stream_Element_Array (1 .. Text'Length);
   begin
      for Index in Text'Range loop
         Data (Ada.Streams.Stream_Element_Offset
                 (Index - Text'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Text (Index)));
      end loop;
      Sockets.Send_All (Peer, Data, Timeout => 10.0);
   end Send_Text;

   task Server_Task is
      entry Go;
   end Server_Task;

   task body Server_Task is
      Peer    : Sockets.Socket_Type;
      Address : Sockets.Endpoint;
      Status  : Sockets.Selector_Status;
      Buffer  : Ada.Streams.Stream_Element_Array (1 .. 8_192);
      Last    : Ada.Streams.Stream_Element_Offset;
   begin
      select
         accept Go;
      or
         terminate;
      end select;
      loop
         exit when State.Stopping or else State.Remaining = 0;
         Sockets.Accept_Socket
           (Listener, Peer, Address, Timeout => 15.0, Status => Status);
         exit when Status /= Sockets.Completed;
         declare
            Head : US.Unbounded_String;
         begin
            loop
               Sockets.Receive (Peer, Buffer, Last, Timeout => 15.0);
               exit when Last < Buffer'First;
               for Index in Buffer'First .. Last loop
                  US.Append (Head, Character'Val (Buffer (Index)));
               end loop;
               exit when Complete_Request (US.To_String (Head));
            end loop;
            if US.Length (Head) > 0 then
               State.Store_Head (US.To_String (Head));
               declare
                  Response : US.Unbounded_String;
                  Found    : Boolean;
               begin
                  State.Take (Response, Found);
                  if Found then
                     Send_Text (Peer, US.To_String (Response));
                  end if;
               end;
            end if;
         exception
            when Flyology.IO.Timeout_Error =>
               null;
         end;
         Sockets.Close_Socket (Peer);
      end loop;
      if Sockets.Is_Open (Peer) then
         Sockets.Close_Socket (Peer);
      end if;
      if Sockets.Is_Open (Listener) then
         Sockets.Close_Socket (Listener);
      end if;
   exception
      when Occurrence : others =>
         State.Set_Error
           (Ada.Exceptions.Exception_Information (Occurrence));
         if Sockets.Is_Open (Listener) then
            Sockets.Close_Socket (Listener);
         end if;
   end Server_Task;

   procedure Script (Response : String) is
   begin
      State.Add (Response);
   end Script;

   procedure Start (Port : out Natural) is
      Bound : Sockets.Endpoint;
   begin
      Sockets.Create_Socket (Listener);
      Sockets.Set_Socket_Option
        (Listener, Sockets.Socket_Level, (Sockets.Reuse_Address, True));
      Sockets.Bind_Socket
        (Listener,
         Sockets.Network_Endpoint (Sockets.Loopback_IPv4, Sockets.Any_Port));
      Sockets.Listen_Socket (Listener, Length => 16);
      Bound := Sockets.Get_Socket_Name (Listener);
      Port := Natural (Bound.Port);
      Server_Task.Go;
   end Start;

   procedure Stop is
   begin
      State.Request_Stop;
   end Stop;

   function Served return Natural is (State.Head_Count);

   function Request_Head (Index : Positive) return String is
     (State.Head_Text (Index));

   function Request_Line (Index : Positive) return String is
      Text : constant String := State.Head_Text (Index);
      Stop : constant Natural := Ada.Strings.Fixed.Index (Text, CRLF);
   begin
      if Stop = 0 then
         return Text;
      end if;
      return Text (Text'First .. Stop - 1);
   end Request_Line;

   function Server_Error return String is (State.Error_Text);

end Repro_Client_Objects_Fake;
