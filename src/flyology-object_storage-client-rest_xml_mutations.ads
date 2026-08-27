with Ada.Exceptions;
with Ada.Streams;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.IO;
with Flyology.Operations;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;

generic
   type Result_Type is private;
   Operation_Name : String;

   with procedure Start_Exchange
     (Client    : not null access Flyology.HTTP.Client.Client;
      Prepared  : not null access constant Low_Level.Prepared_Request;
      Source    : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink      : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Token     : access Flyology.Cancellation.Token;
      Operation : in out Flyology.HTTP.Client.Exchange_Operation);

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

   with function Normalize_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Admission : Flyology.HTTP.Client.Admission_Certainty;
      Phase     : Flyology.HTTP.Client.Exchange_Phase;
      Detail    : String) return Result_Type;

--  @exclude
--  Internal owner-driven state shared by nonreplaying REST/XML mutations.
--  Provider packages retain payload serialization, request preparation,
--  response decoding, admission classification, and reconciliation policy.
--  This family owns only the already-reviewed one-shot source, bounded sink,
--  child lifetime, cancellation, drain, restart, and typed Finish mechanics.
package Flyology.Object_Storage.Client.REST_XML_Mutations is

   type State
     (Set : not null access Flyology.Operations.Completion_Set'Class) is
     limited private;

   function Declared_Length
     (Item : State) return Flyology.HTTP.Client.Body_Length;

   procedure Read_Now
     (Item   : in out State;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out Flyology.HTTP.Client.Source_Step_Kind);

   procedure Source_Wait_Source
     (Item       : in out State;
      Required   : Flyology.HTTP.Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean);

   procedure Release_Source (Item : in out State);

   procedure Write
     (Item : in out State;
      Data : Ada.Streams.Stream_Element_Array);

   procedure Drive
     (Item         : in out State;
      Parent       : not null access Flyology.Operations.Operation'Class;
      Source       : not null access
        Flyology.HTTP.Client.Operation_Request_Body_Source'Class;
      Sink         : not null access
        Flyology.HTTP.Client.Response_Body_Sink'Class;
      Client       : not null access Flyology.HTTP.Client.Client;
      Cancellation : access Flyology.Cancellation.Token;
      Event        : Flyology.Operations.Driver_Event);

   procedure Request_Cancellation (Item : in out State);

   procedure Finalize (Item : in out State);

   procedure Start
     (Item      : in out State;
      Parent    : not null access Flyology.Operations.Operation'Class;
      Prepared  : Low_Level.Prepared_Request;
      Deadline  : Flyology.HTTP.Client.Monotonic_Deadline;
      Limits    : Flyology.Object_Storage.S3.XML.Parse_Limits);

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
      Source_Position  : Natural;
      Response_Data    : Flyology.Bytes.Unbounded_Bytes;
      Response_Limit   : Natural;
      Final_Result     : Result_Type;
      Has_Final_Result : Boolean;
      Has_Saved_Error  : Boolean;
      Saved_Error      : Ada.Exceptions.Exception_Occurrence;
   end record;

end Flyology.Object_Storage.Client.REST_XML_Mutations;
