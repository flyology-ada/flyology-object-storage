with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;
with Flyology.Operations;

--  Shared signed-socket driver for one bounded REST/XML read. Operation-
--  specific adapters retain the public result type and supply only typed
--  construction, completion, and result-observation callbacks.
generic
   Operation_Name : String;

   type Result_Type is private;
   type Operation_Type (<>) is limited private;

   with procedure Execute_Low_Level
     (HTTP                  : aliased in out Flyology.HTTP.Client.Client;
      Origin                : Flyology.HTTP.Origin;
      Bucket                : String;
      Identifier            : String;
      Expected_Bucket_Owner : String;
      Identity              :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Region                : String;
      Signing_Timestamp     : String;
      Timeout               : Duration;
      Limits                : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Expected              : String;
      Expected_Value        : String);

   with procedure Execute_Synchronous
     (HTTP                  : aliased in out Flyology.HTTP.Client.Client;
      Origin                : Flyology.HTTP.Origin;
      Bucket                : String;
      Identifier            : String;
      Expected_Bucket_Owner : String;
      Identity              :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Region                : String;
      Timeout               : Duration;
      Limits                : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Result                : out Result_Type);

   with function Start
     (Set                   : not null access
        Flyology.Operations.Completion_Set'Class;
      HTTP                  : not null access Flyology.HTTP.Client.Client;
      Origin                : Flyology.HTTP.Origin;
      Bucket                : String;
      Identifier            : String;
      Expected_Bucket_Owner : String;
      Identity              :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Deadline              : Flyology.HTTP.Client.Monotonic_Deadline;
      Region                : String;
      Limits                : Flyology.Object_Storage.S3.XML.Parse_Limits)
      return Operation_Type;

   with procedure Restart
     (HTTP                  : not null access Flyology.HTTP.Client.Client;
      Origin                : Flyology.HTTP.Origin;
      Bucket                : String;
      Identifier            : String;
      Expected_Bucket_Owner : String;
      Identity              :
        Flyology.Object_Storage.Client.Low_Level.Credentials;
      Deadline              : Flyology.HTTP.Client.Monotonic_Deadline;
      Region                : String;
      Limits                : Flyology.Object_Storage.S3.XML.Parse_Limits;
      Operation             : in out Operation_Type);

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

package S3_Bounded_REST_XML_Read_Qualification is
   procedure Run;
end S3_Bounded_REST_XML_Read_Qualification;
