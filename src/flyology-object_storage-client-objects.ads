with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Errors;

--  High-level single-object operations over a configured Flyology HTTP client.
package Flyology.Object_Storage.Client.Objects is

   type Delete_Outcome_Kind is (Object_Removed, Delete_Rejected);

   type Delete_Outcome
     (Kind : Delete_Outcome_Kind := Delete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Object_Removed =>
            Delete_Marker   : Low_Level.Optional_Boolean;
            Version_ID      : Ada.Strings.Unbounded.Unbounded_String;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when Delete_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Delete one object or a specific object version. S3 treats a missing
   --  unversioned key as a successful idempotent deletion. Advanced MFA and
   --  governance-bypass controls remain available through Client.Low_Level.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Version_ID Optional exact version to delete permanently
   --  @param If_Match Optional entity-tag precondition
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Modeled deletion headers or structured S3 rejection
   function Delete
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := "";
      If_Match : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

end Flyology.Object_Storage.Client.Objects;
