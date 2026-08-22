with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Listings;

--  High-level object and object-listing operations over a configured Flyology
--  HTTP client.
package Flyology.Object_Storage.Client.Objects is

   type List_Outcome_Kind is (Page_Available, List_Rejected);

   type List_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : S3.Listings.List_Objects_V2_Result;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when List_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page of current objects with S3 ListObjectsV2.
   --  Pass Page.Next_Continuation_Token from a truncated result to continue
   --  the same prefix/delimiter scope. Continuation tokens remain opaque;
   --  Start_After is an exclusive key used to select an initial page.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose current objects are listed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Prefix Optional byte prefix filter
   --  @param Delimiter Optional byte delimiter for CommonPrefixes grouping
   --  @param Maximum Maximum combined objects and prefixes in this page
   --  @param Continuation_Token Opaque token returned by the prior page
   --  @param Start_After Exclusive initial key; ignored by S3 when continuing
   --  @param Fetch_Owner Request an Owner structure for every object
   --  @param URL_Encoding Percent-encode returned keys, prefixes and delimiter
   --  @param Include_Restore_Status Request RestoreStatus where it exists
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return One typed page or a structured S3 rejection
   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Prefix   : String := "";
      Delimiter : String := "";
      Maximum  : S3.Core.Page_Size := 1_000;
      Continuation_Token : String := "";
      Start_After : String := "";
      Fetch_Owner : Boolean := False;
      URL_Encoding : Boolean := False;
      Include_Restore_Status : Boolean := False;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Outcome;

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

   type Tagging_Outcome_Kind is
     (Tags_Replaced, Tags_Read, Tags_Cleared, Tagging_Rejected);

   type Tagging_Outcome
     (Kind : Tagging_Outcome_Kind := Tagging_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Tags_Replaced | Tags_Read | Tags_Cleared =>
            Result : Low_Level.Object_Tagging_Result;
         when Tagging_Rejected =>
            Error : Flyology.Object_Storage.S3.Errors.Error_Response;
      end case;
   end record;

   --  Replace the complete tag set. Empty Tags clears the set, while
   --  Delete_Tags provides the explicit S3 deletion operation.
   function Put_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Tags : Object_Tag_Set; Identity : Low_Level.Credentials;
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Request_Payer : String := ""; Checksum_Algorithm : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome;

   function Get_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Request_Payer : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome;

   function Delete_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome;

   subtype Get_Attributes_Outcome is
     Low_Level.Get_Object_Attributes_Outcome;

   --  Retrieve selected object metadata without downloading the body. By
   --  default all five root attribute groups are requested. Numeric presence
   --  flags allow callers to omit pagination headers independently of their
   --  values.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket containing the object
   --  @param Key Exact object key
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Attributes Requested root-level result groups
   --  @param Version_ID Optional exact object version
   --  @param Max_Parts Object-parts page size when Has_Max_Parts is true
   --  @param Has_Max_Parts Whether to send Max_Parts
   --  @param Part_Number_Marker Exclusive completed-part marker
   --  @param Has_Part_Number_Marker Whether to send Part_Number_Marker
   --  @param SSE_Customer_Algorithm Optional SSE-C algorithm
   --  @param SSE_Customer_Key Optional base64 SSE-C key; HTTPS only
   --  @param SSE_Customer_Key_MD5 Optional base64 SSE-C key digest
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester for Requester Pays buckets
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed modeled result or structured S3 rejection
   function Get_Attributes
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Attributes : S3.Attributes.Attribute_Selection := (others => True);
      Version_ID : String := "";
      Max_Parts : S3.Core.Page_Size := 1_000;
      Has_Max_Parts : Boolean := False;
      Part_Number_Marker : S3.Attributes.Part_Marker_Value := 0;
      Has_Part_Number_Marker : Boolean := False;
      SSE_Customer_Algorithm : String := "";
      SSE_Customer_Key : String := "";
      SSE_Customer_Key_MD5 : String := "";
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Attributes_Outcome;

end Flyology.Object_Storage.Client.Objects;
