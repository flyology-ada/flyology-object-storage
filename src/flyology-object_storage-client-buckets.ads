with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Buckets;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.Tags;

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

   --  Remove the complete CORS configuration from one bucket. Deleting an
   --  absent configuration follows the endpoint's S3 status unchanged.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose CORS configuration is removed
   --  @param Identity Credentials used only while signing this request
   --  @param Region Region used to sign the DeleteBucketCors request
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_CORS
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

   --  Remove one named analytics configuration.
   function Delete_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete default encryption configuration.
   function Delete_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove one named intelligent-tiering configuration.
   function Delete_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove one named inventory configuration.
   function Delete_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete lifecycle configuration.
   function Delete_Lifecycle
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete metadata configuration.
   function Delete_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete metadata-table configuration.
   function Delete_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove one named metrics configuration.
   function Delete_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete ownership-controls configuration.
   function Delete_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete bucket policy.
   function Delete_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete replication configuration.
   function Delete_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete website configuration.
   function Delete_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome;

   --  Remove the complete public-access-block configuration.
   function Delete_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
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

   type Put_Tags_Outcome_Kind is (Tags_Replaced, Put_Tags_Rejected);

   type Put_Tags_Outcome
     (Kind : Put_Tags_Outcome_Kind := Put_Tags_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Replaced =>
            null;
         when Put_Tags_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Atomically replace the complete tag set of one bucket. Content-MD5 and
   --  the strict S3 XML body are generated automatically. This unreleased
   --  strict surface intentionally omits RequestPayer, which is absent from
   --  the pinned PutBucketTagging model.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose complete tag set is replaced
   --  @param Value Nonempty, unique, AWS-valid bucket tag set
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed replacement or structured S3 rejection
   function Put_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Value    : Flyology.Object_Storage.Tags.Tag_Set;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Put_Tags_Outcome;

   type Get_Tags_Outcome_Kind is (Tags_Found, Get_Tags_Rejected);

   type Get_Tags_Outcome
     (Kind : Get_Tags_Outcome_Kind := Get_Tags_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Found =>
            Value : Flyology.Object_Storage.Tags.Tag_Set;
         when Get_Tags_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Fetch one atomic bucket tag snapshot. An untagged bucket is returned as
   --  the structured NoSuchTagSet S3 rejection. This unreleased strict surface
   --  intentionally omits the non-modeled RequestPayer control and charged
   --  response metadata.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose tag snapshot is requested
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed tag snapshot or structured S3 rejection
   function Get_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Tags_Outcome;

   type Delete_Tags_Outcome_Kind is
     (Tags_Deleted, Delete_Tags_Rejected);

   type Delete_Tags_Outcome
     (Kind : Delete_Tags_Outcome_Kind := Delete_Tags_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Deleted =>
            null;
         when Delete_Tags_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Remove the complete tag set of one bucket. Deleting an already absent
   --  tag set remains successful when the bucket exists.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose tag set is removed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed deletion or structured S3 rejection
   function Delete_Tags
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Tags_Outcome;

   subtype Configurable_Versioning_Status is Bucket_Versioning_Status range
     Versioning_Enabled .. Versioning_Suspended;

   type Set_Versioning_Outcome_Kind is
     (Versioning_Updated, Set_Versioning_Rejected);

   type Set_Versioning_Outcome
     (Kind : Set_Versioning_Outcome_Kind := Set_Versioning_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Versioning_Updated =>
            null;
         when Set_Versioning_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Enable or suspend bucket versioning configuration. This convenience
   --  call does not expose MFA-delete because safe use requires a separately
   --  verified MFA policy. It does not imply that object version creation or
   --  ListObjectVersions is implemented by a compatible endpoint.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is changed
   --  @param Versioning Enabled or Suspended
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed configuration update or structured S3 rejection
   function Set_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Versioning : Configurable_Versioning_Status;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Set_Versioning_Outcome;

   --  Apply the complete modeled bucket-versioning configuration. Changing
   --  MFA Delete requires an explicit versioning status, an MFA credential,
   --  and a secure HTTPS origin. The credential is retained only while the
   --  synchronous request is signed and executed. This configures the bucket;
   --  it does not claim object-version publication or listing support.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact secure origin used to configure and sign requests
   --  @param Bucket Bucket whose configuration is changed
   --  @param Configuration Presence-preserving Status and MfaDelete members
   --  @param Identity Credentials used only while signing this request
   --  @param MFA Optional physical-device header; required for MFA Delete
   --  @param Checksum_Algorithm Optional modeled request checksum algorithm
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Completed configuration update or structured S3 rejection
   function Set_Versioning_Configuration
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Configuration : Bucket_Versioning_Configuration;
      Identity : Low_Level.Credentials;
      MFA      : String := "";
      Checksum_Algorithm : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Set_Versioning_Outcome;

   type Get_Versioning_Outcome_Kind is
     (Versioning_Found, Get_Versioning_Rejected);

   type Get_Versioning_Outcome
     (Kind : Get_Versioning_Outcome_Kind := Get_Versioning_Rejected)
   is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Versioning_Found =>
            Configuration : Bucket_Versioning_Configuration;
         when Get_Versioning_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Read the presence-preserving bucket versioning configuration.
   --  Unconfigured is distinct from Suspended.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose configuration is read
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Configuration snapshot or structured S3 rejection
   function Get_Versioning
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Versioning_Outcome;

   --  Create one five-minute directory-bucket authorization session through
   --  the secure virtual-hosted CreateSession endpoint. Returned access,
   --  secret, and token values remain inside the zeroizing low-level
   --  Credentials object; the outcome cannot be copied. This layer creates no
   --  refresh task and retains no session state after the call. Transport
   --  retry behavior remains the configured Flyology HTTP client's policy.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Secure zonal endpoint used to configure and sign Client
   --  @param Bucket Directory bucket encoded in Origin's virtual host
   --  @param Identity Long-term credentials used only for this request
   --  @param Session_Mode Optional ReadOnly or ReadWrite mode
   --  @param Server_Side_Encryption Optional modeled encryption selection
   --  @param SSE_KMS_Key_ID Required customer key for an explicit KMS mode
   --  @param SSE_KMS_Encryption_Context Optional canonical base64 context
   --  @param Bucket_Key_Enabled Absent or explicit true for a KMS session
   --  @param Region SigV4 signing region
   --  @param Style Must remain virtual-hosted for CreateSession
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Zeroizing temporary identity, expiration, policy, or S3 error
   function Create_Session
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Session_Mode : String := "";
      Server_Side_Encryption : String := "";
      SSE_KMS_Key_ID : String := "";
      SSE_KMS_Encryption_Context : String := "";
      Bucket_Key_Enabled : Low_Level.Optional_Boolean := (others => <>);
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Virtual_Hosted_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Low_Level.Create_Session_Outcome;

end Flyology.Object_Storage.Client.Buckets;
