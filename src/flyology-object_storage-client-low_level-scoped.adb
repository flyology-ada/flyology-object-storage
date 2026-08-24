with Ada.Strings.Unbounded;

package body Flyology.Object_Storage.Client.Low_Level.Scoped is

   procedure Clear_Prepared_Request
     (Prepared : in out Prepared_Request) is
   begin
      Prepared := (others => <>);
   end Clear_Prepared_Request;

   function Owned_Payload_Length
     (Prepared : Prepared_Request) return Natural is
     (Ada.Strings.Unbounded.Length (Prepared.Owned_Request_Payload));

   function Owned_Payload_Element
     (Prepared : Prepared_Request;
      Index    : Positive) return Character is
     (Ada.Strings.Unbounded.Element
        (Prepared.Owned_Request_Payload, Index));

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

   procedure Start_Delete_Object
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
      if Prepared.Operation /= Delete_Object_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
         (Operation, Client, Prepared.Message'Access, Source, Sink, Deadline,
          Token);
   end Start_Delete_Object;

   procedure Start_Create_Multipart_Upload
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
      if Prepared.Operation /= Create_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Source, Sink, Deadline,
         Token);
   end Start_Create_Multipart_Upload;

   procedure Start_Complete_Multipart_Upload
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
      if Prepared.Operation /= Complete_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Source, Sink, Deadline,
         Token);
   end Start_Complete_Multipart_Upload;

   procedure Start_Abort_Multipart_Upload
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
      if Prepared.Operation /= Abort_Multipart_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Source, Sink, Deadline,
         Token);
   end Start_Abort_Multipart_Upload;

   procedure Start_List_Parts
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Prepared.Operation /= List_Parts_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Sink, Deadline, Token);
   end Start_List_Parts;

   procedure Start_List_Multipart_Uploads
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null) is
   begin
      if Prepared.Operation /= List_Multipart_Uploads_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Sink, Deadline, Token);
   end Start_List_Multipart_Uploads;

   procedure Start_Upload_Part
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
      if Prepared.Operation /= Upload_Part_Operation then
         raise Invalid_Request with "prepared request operation mismatch";
      end if;
      Flyology.HTTP.Client.Scoped.Start
        (Operation, Client, Prepared.Message'Access, Source, Sink, Deadline,
         Token);
   end Start_Upload_Part;

end Flyology.Object_Storage.Client.Low_Level.Scoped;
