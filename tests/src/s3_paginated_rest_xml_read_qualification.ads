with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

--  Shared signed-socket driver for one paginated REST/XML read. The shared
--  driver owns lane sequencing, limits, cancellation, restart, and terminal
--  consumption. A small typed adapter supplies only operation inputs and
--  result inspection, so result domains remain operation-specific.
generic
   Operation_Name : String;

   type Inputs_Type is private;
   type Result_Type is private;
   type Operation_Type (<>) is limited private;

   with function Inputs return Inputs_Type;

   with procedure Check_Pre_Admission_Rejection
     (HTTP              : aliased in out Flyology.HTTP.Client.Client;
      Origin            : Flyology.HTTP.Origin;
      Value             : Inputs_Type;
      Identity          :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Region            : String;
      Signing_Timestamp : String;
      Timeout           : Duration;
      Limits            : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Collection_Limit  : Positive);

   with procedure Execute_Low_Level
     (HTTP              : aliased in out Flyology.HTTP.Client.Client;
      Origin            : Flyology.HTTP.Origin;
      Value             : Inputs_Type;
      Identity          :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Region            : String;
      Signing_Timestamp : String;
      Timeout           : Duration;
      Limits            : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Collection_Limit  : Positive;
      Expected          : String;
      Expected_Value    : String);

   with procedure Execute_Synchronous
     (HTTP             : aliased in out Flyology.HTTP.Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Value            : Inputs_Type;
      Identity         :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Region           : String;
      Timeout          : Duration;
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Collection_Limit : Positive;
      Result           : out Result_Type);

   with function Start
     (Set              : not null access
        Flyology.Operations.Completion_Set'Class;
      HTTP             : not null access Flyology.HTTP.Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Value            : Inputs_Type;
      Identity         :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Region           : String;
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Collection_Limit : Positive)
      return Operation_Type;

   with procedure Restart
     (HTTP             : not null access Flyology.HTTP.Client.Client;
      Origin           : Flyology.HTTP.Origin;
      Value            : Inputs_Type;
      Identity         :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Deadline         : Flyology.HTTP.Client.Monotonic_Deadline;
      Region           : String;
      Limits           : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Collection_Limit : Positive;
      Operation        : in out Operation_Type);

   with procedure Finish
     (Operation : in out Operation_Type;
      Result    : out Result_Type);

   with procedure Request_Cancellation
     (Operation : in out Operation_Type);

   with procedure Check_Result
     (Result         : Result_Type;
      Expected       : String;
      Expected_Value : String;
      Context        : String);

package S3_Paginated_REST_XML_Read_Qualification is
   procedure Run;
end S3_Paginated_REST_XML_Read_Qualification;
