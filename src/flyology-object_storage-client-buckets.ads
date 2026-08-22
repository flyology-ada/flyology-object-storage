with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Errors;

--  High-level bucket operations over a configured Flyology HTTP client.
package Flyology.Object_Storage.Client.Buckets is

   type List_Outcome_Kind is (Page_Available, List_Rejected);

   type List_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : Flyology.Object_Storage.S3.Buckets.List_Buckets_Result;
         when List_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page of general-purpose buckets. Pagination is enabled
   --  by default with a 1,000-bucket page, following AWS's recommendation.
   --  Pass the returned continuation token to obtain the next page.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Maximum Maximum number of buckets returned in this page
   --  @param Continuation_Token Opaque token returned by the prior page
   --  @param Prefix Optional bucket-name prefix filter
   --  @param Bucket_Region Optional bucket-region filter
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return One typed page or a structured S3 rejection
   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Maximum  : Flyology.Object_Storage.S3.Buckets.Max_Buckets_Value :=
        1_000;
      Continuation_Token : String := "";
      Prefix   : String := "";
      Bucket_Region : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Outcome;

   type Create_Outcome_Kind is (Creation_Completed, Create_Rejected);

   type Create_Outcome
     (Kind : Create_Outcome_Kind := Create_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Creation_Completed =>
            Location   : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_ARN : Ada.Strings.Unbounded.Unbounded_String;
         when Create_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Create a general-purpose bucket. Unless explicitly supplied,
   --  Location_Constraint follows Region and is omitted for us-east-1.
   --  Advanced ACL, Object Lock, tagging, namespace, and directory-bucket
   --  inputs remain available through the typed Low_Level API.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket New general-purpose bucket name
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the CreateBucket request
   --  @param Location_Constraint Optional explicit legacy region constraint
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Modeled creation headers or structured S3 rejection
   function Create
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Location_Constraint : String := "";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Create_Outcome;

   type Delete_Outcome_Kind is (Deletion_Completed, Delete_Rejected);

   type Delete_Outcome
     (Kind : Delete_Outcome_Kind := Delete_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Deletion_Completed =>
            null;
         when Delete_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Delete one empty bucket. S3 rejects buckets that still contain objects
   --  or active multipart state; callers receive that rejection unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Empty bucket to delete
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the DeleteBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   type Head_Outcome_Kind is (Bucket_Available, Head_Rejected);

   type Head_Outcome
     (Kind : Head_Outcome_Kind := Head_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Bucket_Available =>
            Bucket_ARN           : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_Location_Type : Ada.Strings.Unbounded.Unbounded_String;
            Bucket_Location_Name : Ada.Strings.Unbounded.Unbounded_String;
            Region               : Ada.Strings.Unbounded.Unbounded_String;
            Access_Point_Alias   : Low_Level.Optional_Boolean;
         when Head_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Probe one bucket without downloading a response body. Successful
   --  results preserve every modeled HeadBucket response header and expose
   --  the bucket region under the convenience-level Region name. If a
   --  compatible server omits the optional response header, Region falls
   --  back to the region used to sign the request.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose availability and region are requested
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the HeadBucket request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Modeled HeadBucket headers or structured bodyless rejection
   function Head
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Outcome;

   type Location_Outcome_Kind is (Location_Found, Location_Rejected);

   type Location_Outcome
     (Kind : Location_Outcome_Kind := Location_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Location_Found =>
            --  Normalized AWS signing region: an empty legacy constraint is
            --  us-east-1 and EU is eu-west-1.
            Region : Ada.Strings.Unbounded.Unbounded_String;
            Legacy_Constraint : Ada.Strings.Unbounded.Unbounded_String;
         when Location_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Resolve one bucket's legacy GetBucketLocation value into a usable
   --  signing region while preserving the raw constraint for callers that
   --  need wire-level compatibility diagnostics.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose location is requested
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the location request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional 12-digit owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Normalized signing region or structured S3 rejection
   function Get_Location
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Location_Outcome;

end Flyology.Object_Storage.Client.Buckets;
