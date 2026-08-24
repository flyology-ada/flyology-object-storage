with Flyology.Buffers;
with Flyology.Cancellation;
with Flyology.HTTP.Client;

--  Bridges prepared S3 requests into caller-owned composable HTTP exchanges.
package Flyology.Object_Storage.Client.Low_Level.Scoped is

   --  Start a prepared PutObject exchange with a nonblocking source and a
   --  bounded immediate response sink. Prepared, Source, Sink, Client, Token,
   --  and their owners must outlive terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared PutObject request
   --  @param Source Nonblocking complete-object source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not PutObject
   procedure Start_Put_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared GetObject exchange into an acquired caller buffer.
   --  Typed HTTP Finish restores the exact buffer token on every outcome.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared GetObject request
   --  @param Destination Acquired bounded response buffer
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not GetObject
   procedure Start_Get_Object
     (Operation   : in out Flyology.HTTP.Client.Exchange_Operation;
      Client      : not null access Flyology.HTTP.Client.Client;
      Prepared    : not null access constant Prepared_Request;
      Destination : in out Flyology.Buffers.Unique_Buffer;
      Deadline    : Flyology.HTTP.Client.Monotonic_Deadline;
      Token       : access Flyology.Cancellation.Token := null)
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Start a prepared HeadObject exchange into a bounded immediate sink.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared HeadObject request
   --  @param Sink Bounded response sink used to reject nonempty HEAD bodies
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not HeadObject
   procedure Start_Head_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared DeleteObject exchange with a deliberately
   --  non-replayable empty source and a bounded immediate response sink.
   --  Prepared, Source, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared DeleteObject request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not DeleteObject
   procedure Start_Delete_Object
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

   --  Start a prepared CreateMultipartUpload exchange with a deliberately
   --  non-replayable empty source and a bounded immediate response sink.
   --  Prepared, Source, Sink, Client, Token, and their owners must outlive
   --  terminal typed Finish of Operation.
   --  @param Operation Established HTTP child operation
   --  @param Client Configured origin client
   --  @param Prepared Prepared CreateMultipartUpload request
   --  @param Source Nonblocking one-shot empty request source
   --  @param Sink Bounded complete-response sink
   --  @param Deadline Absolute whole-exchange deadline
   --  @param Token Optional cancellation source
   --  @exception Invalid_Request Prepared is not CreateMultipartUpload
   procedure Start_Create_Multipart_Upload
     (Operation : in out Flyology.HTTP.Client.Exchange_Operation;
      Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token := null);

end Flyology.Object_Storage.Client.Low_Level.Scoped;
