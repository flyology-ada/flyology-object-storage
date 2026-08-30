with Ada.Exceptions;
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Operations;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;

--  Share owner-driven state for bounded REST/XML read operations. Provider
--  packages retain request preparation, response decoding, and modeled result
--  classification; this generic owns buffering, child lifetime, cancellation,
--  drain, restart, and Finish mechanics.
--  @formal Result_Type Typed provider result retained for Finish
--  @formal Operation_Name Operation name used in diagnostic messages
--  @formal Start_Exchange Start the operation-specific child exchange
--  @formal Decode_Response Decode one complete response into Result_Type
--  @formal Normalize_Failure Map a terminal exchange failure to Result_Type
generic
   --  Typed provider result retained for Finish.
   type Result_Type is private;
   --  Operation name used in diagnostic messages.
   Operation_Name : String;

   --  Start the operation-specific child exchange.
   with procedure Start_Exchange
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Low_Level.Prepared_Request;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

   --  Decode one complete response into Result_Type.
   with function Decode_Response
     (Status     : Flyology.HTTP.Status_Code;
      Response   : Flyology.HTTP.Client.Response;
      Payload    : String;
      Request_ID : String;
      Host_ID    : String;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Admission  : Flyology.HTTP.Client.Admission_Certainty;
      Phase      : Flyology.HTTP.Client.Exchange_Phase)
      return Result_Type;

   --  Map a terminal exchange failure to Result_Type.
   with function Normalize_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Result_Type;

package Flyology.Object_Storage.Client.Bounded_REST_XML_Reads is
   --  Share owner-driven state for bounded REST/XML read operations. Provider
   --  packages retain request preparation, response decoding, and modeled
   --  result classification; this generic owns buffering, child lifetime,
   --  cancellation, drain, restart, and Finish mechanics.
   --  @formal Result_Type Typed provider result retained for Finish
   --  @formal Operation_Name Operation name used in diagnostic messages
   --  @formal Start_Exchange Start the operation-specific child exchange
   --  @formal Decode_Response Decode one complete response into Result_Type
   --  @formal Normalize_Failure Map a terminal exchange failure to Result_Type

   --  Retain one reusable provider lifecycle.
   type State
     ( --  Completion set that owns the child exchange.
      Set : not null access Flyology.Operations.Completion_Set'Class) is
     limited private;

   --  Append one response-body slice within the configured XML limit.
   --  @param Item Lifecycle state receiving the response
   --  @param Data Next response-body slice
   procedure Write
     (Item : in out State;
      Data : Ada.Streams.Stream_Element_Array);

   --  Advance the parent lifecycle for one driver event.
   --  @param Item Lifecycle state being advanced
   --  @param Parent Parent operation completed by this lifecycle
   --  @param Sink Operation-specific response sink
   --  @param Client HTTP client retained by the parent operation
   --  @param Cancellation Optional cancellation source
   --  @param Event Driver event to process
   procedure Drive
     (Item         : in out State;
      Parent       : not null access Flyology.Operations.Operation'Class;
      Sink         : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Client       : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token;
      Event        : Flyology.Operations.Driver_Event);

   --  Forward cancellation to the active child exchange.
   --  @param Item Lifecycle state whose child is cancelled
   procedure Request_Cancellation (Item : in out State);

   --  Clear the retained prepared request and buffered response.
   --  @param Item Lifecycle state being finalized
   procedure Finalize (Item : in out State);

   --  Install one prepared request and start its parent operation.
   --  @param Item Lifecycle state to initialize
   --  @param Parent Parent operation to start
   --  @param Prepared Prepared operation-specific request
   --  @param Deadline Absolute deadline retained for the child exchange
   --  @param Limits Caller-selected XML parse limits
   procedure Start
     (Item      : in out State;
      Parent    : not null access Flyology.Operations.Operation'Class;
      Prepared  : Low_Level.Prepared_Request;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Limits    : Flyology.Object_Storage.S3.XML.Parse_Limits);

   --  Consume one terminal parent and expose its typed result.
   --  @param Item Lifecycle state holding terminal evidence
   --  @param Parent Terminal parent operation to consume
   --  @param Result Typed provider result produced by the child exchange
   procedure Finish
     (Item   : in out State;
      Parent : not null access Flyology.Operations.Operation'Class;
      Result : out Result_Type);

private

   type State
     (Set : not null access Flyology.Operations.Completion_Set'Class) is
   limited record
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Prepared         : aliased Low_Level.Prepared_Request;
      Child            : Flyology.HTTP.Client.Exchange_Operation (Set);
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural;
      Final_Result     : Result_Type;
      Has_Final_Result : Boolean;
      Has_Saved_Error  : Boolean;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

end Flyology.Object_Storage.Client.Bounded_REST_XML_Reads;
