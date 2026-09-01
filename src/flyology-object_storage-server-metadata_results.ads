with Ada.Real_Time;
with Flyology.Cancellation;
with Flyology.Object_Storage.S3.Metadata_Configurations;
with Flyology.Object_Storage.S3.Metadata_Tables;

--  Supplies exact provider-owned metadata configuration projections to the
--  authenticated S3 server. Each request invokes at most one callback exactly
--  once, synchronously, before backend mutation; the server never retries a
--  callback automatically. Callbacks resolve values only and must not
--  provision or modify external resources. Bucket, request, configuration,
--  previous result, token, and deadline inputs are borrowed for the call;
--  implementations must copy anything retained after return.
--
--  Success requires every output to be completely initialized. On any other
--  Status the server ignores all outputs and performs no backend mutation.
--  Flyology.Cancellation.Operation_Cancelled and Flyology.IO.Timeout_Error
--  propagate through the server's established cancellation path. The server
--  converts every other exception to Backend_Unavailable without retaining
--  partial output.
package Flyology.Object_Storage.Server.Metadata_Results is

   package Configurations renames S3.Metadata_Configurations;
   package Tables renames S3.Metadata_Tables;

   --  Provider of complete metadata configuration results. Implementations
   --  must be safe for concurrent calls made by the bound server application.
   type Provider is limited interface;

   --  Caller-owned provider reference borrowed by one server application.
   --  The object must remain alive until the application has finished every
   --  request and must not be freed while the generic package instance exists.
   type Provider_Access is access all Provider'Class;

   --  Resolve one V1 creation into both V1 and V2 observations plus the
   --  canonical V2 configuration used by later update operations.
   --  @param Item Provider resolving the request
   --  @param Bucket Borrowed exact bucket name
   --  @param Request Borrowed validated V1 destination request
   --  @param Configuration Complete canonical V2 configuration on Success
   --  @param Legacy_Result Complete canonical V1 observation on Success
   --  @param Current_Result Complete canonical V2 observation on Success
   --  @param Token Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Success or an existing service failure status
   procedure Create_Legacy
     (Item          : in out Provider;
      Bucket        : String;
      Request       : Tables.S3_Tables_Destination;
      Configuration : out Configurations.Metadata_Configuration_Request;
      Legacy_Result : out Tables.Metadata_Table_Configuration_Result;
      Current_Result : out Configurations.Metadata_Configuration;
      Token         : access Flyology.Cancellation.Token;
      Deadline      : Ada.Real_Time.Time;
      Result        : out Status) is abstract;

   --  Resolve one V2 creation into its complete current observation.
   --  @param Item Provider resolving the request
   --  @param Bucket Borrowed exact bucket name
   --  @param Request Borrowed validated V2 creation request
   --  @param Current_Result Complete canonical V2 observation on Success
   --  @param Token Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Success or an existing service failure status
   procedure Create_Current
     (Item           : in out Provider;
      Bucket         : String;
      Request        : Configurations.Metadata_Configuration_Request;
      Current_Result : out Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Status) is abstract;

   --  Resolve one complete inventory-table update.
   --  @param Item Provider resolving the request
   --  @param Bucket Borrowed exact bucket name
   --  @param Configuration Borrowed complete updated V2 configuration
   --  @param Previous Borrowed previous V2 observation
   --  @param Current_Result Complete updated V2 observation on Success
   --  @param Token Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Success or an existing service failure status
   procedure Update_Inventory
     (Item           : in out Provider;
      Bucket         : String;
      Configuration  : Configurations.Metadata_Configuration_Request;
      Previous       : Configurations.Metadata_Configuration;
      Current_Result : out Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Status) is abstract;

   --  Resolve one complete journal-table update.
   --  @param Item Provider resolving the request
   --  @param Bucket Borrowed exact bucket name
   --  @param Configuration Borrowed complete updated V2 configuration
   --  @param Previous Borrowed previous V2 observation
   --  @param Current_Result Complete updated V2 observation on Success
   --  @param Token Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Success or an existing service failure status
   procedure Update_Journal
     (Item           : in out Provider;
      Bucket         : String;
      Configuration  : Configurations.Metadata_Configuration_Request;
      Previous       : Configurations.Metadata_Configuration;
      Current_Result : out Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Status) is abstract;

   --  Resolve one complete annotation-table update.
   --  @param Item Provider resolving the request
   --  @param Bucket Borrowed exact bucket name
   --  @param Configuration Borrowed complete updated V2 configuration
   --  @param Previous Borrowed previous V2 observation
   --  @param Current_Result Complete updated V2 observation on Success
   --  @param Token Borrowed cooperative cancellation token
   --  @param Deadline Absolute operation deadline
   --  @param Result Success or an existing service failure status
   procedure Update_Annotation
     (Item           : in out Provider;
      Bucket         : String;
      Configuration  : Configurations.Metadata_Configuration_Request;
      Previous       : Configurations.Metadata_Configuration;
      Current_Result : out Configurations.Metadata_Configuration;
      Token          : access Flyology.Cancellation.Token;
      Deadline       : Ada.Real_Time.Time;
      Result         : out Status) is abstract;

end Flyology.Object_Storage.Server.Metadata_Results;
