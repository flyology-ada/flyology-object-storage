package body Flyology.Object_Storage.Client.Low_Level.Scoped is

   procedure Start_Put_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Prepared.Operation /= Put_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Source, Sink, Deadline,
         Token);
   end Start_Put_Object;

   procedure Start_Get_Object
     (Operation   : in out Flyology.HTTP.Client.Exchange_Operation;
      Client      : not null access Flyology.HTTP.Client.Client;
      Prepared    : not null access constant Prepared_Request;
      Destination : in out Flyology.Buffers.Unique_Buffer;
      Deadline    : Flyology.HTTP.Client.Monotonic_Deadline;
      Token       : access Flyology.Cancellation.Token := null) is
   begin
      if Prepared.Operation /= Get_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Destination, Deadline,
         Token);
   end Start_Get_Object;

   procedure Start_Head_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Prepared.Operation /= Head_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Sink, Deadline, Token);
   end Start_Head_Object;

end Flyology.Object_Storage.Client.Low_Level.Scoped;
