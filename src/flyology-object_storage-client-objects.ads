with Ada.Strings.Unbounded;
with Flyology.Buffers;
with Flyology.Bytes;
with Flyology.Cancellation;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.Client.Scoped;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Errors;
with Flyology.Object_Storage.S3.Attributes;
with Flyology.Object_Storage.S3.Core;
with Flyology.Object_Storage.S3.Listings;
with Flyology.Object_Storage.S3.Versions;

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

   type List_V1_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : S3.Listings.List_Objects_Result;
            --  Exclusive marker for the next page. For delimiter listings it
            --  is the modeled NextMarker; otherwise it is the last object
            --  key, as required by ListObjects v1.
            Next_Marker : Ada.Strings.Unbounded.Unbounded_String;
            Has_Next_Marker : Boolean := False;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when List_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page with the backward-compatible S3 ListObjects v1
   --  operation. When Has_Next_Marker is true, pass Next_Marker as Marker to
   --  continue. The helper derives the marker from the final object when an
   --  S3 response is truncated without delimiter grouping.
   function List_V1_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Prefix   : String := "";
      Delimiter : String := "";
      Maximum  : S3.Core.Page_Size := 1_000;
      Marker   : String := "";
      URL_Encoding : Boolean := False;
      Include_Restore_Status : Boolean := False;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_V1_Outcome;

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

   --  One complete typed version-listing page or structured S3 rejection.
   type List_Versions_Outcome
     (Kind : List_Outcome_Kind := List_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Page_Available =>
            Page : S3.Versions.List_Object_Versions_Result;
            Next_Key_Marker : Ada.Strings.Unbounded.Unbounded_String;
            Next_Version_ID_Marker : Ada.Strings.Unbounded.Unbounded_String;
            Has_Next_Markers : Boolean := False;
            Request_Charged : Ada.Strings.Unbounded.Unbounded_String;
         when List_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  List one bounded page of object versions and delete markers. A
   --  Version_ID_Marker is valid only together with Key_Marker. When
   --  Has_Next_Markers is true, pass the outcome's Next_Key_Marker and
   --  Next_Version_ID_Marker to continue the same prefix/delimiter scope.
   --  Next_Key_Marker is decoded from the url response representation;
   --  version identifiers remain opaque.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose versions are listed
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Prefix Optional byte prefix filter
   --  @param Delimiter Optional byte delimiter for CommonPrefixes grouping
   --  @param Maximum Maximum combined entries and prefixes in this page
   --  @param Key_Marker Key component of the paired pagination cursor
   --  @param Version_ID_Marker Version component of the paired cursor
   --  @param URL_Encoding Percent-encode returned keys, prefixes and delimiter
   --  @param Include_Restore_Status Request RestoreStatus where it exists
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return One typed page or a structured S3 rejection
   function List_Versions_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Prefix   : String := "";
      Delimiter : String := "";
      Maximum  : S3.Core.Page_Size := 1_000;
      Key_Marker : String := "";
      Version_ID_Marker : String := "";
      URL_Encoding : Boolean := False;
      Include_Restore_Status : Boolean := False;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Versions_Outcome;

   subtype Complete_Put_Outcome is Low_Level.Put_Object_Outcome;
   subtype Conditional_Put_Outcome is Complete_Put_Outcome;

   --  Semantically bounded, backend-neutral controls supported by the
   --  complete-object S3 convenience call. Every dynamic field is validated
   --  against the shared/model wire limits before request admission.
   --  Checksum, when present, must be a direct
   --  Full_Object_Checksum with one canonical encoded digest. Tags and
   --  metadata retain the shared backend limits.
   type Complete_Put_Options is record
      Content_MD5           : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type          : Ada.Strings.Unbounded.Unbounded_String;
      Metadata              : Object_Metadata;
      Tags                  : Object_Tag_Set;
      Checksum              : Checksum_Information;
      Conditions            : Write_Conditions;
      Expected_Bucket_Owner : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   Default_Complete_Put_Options : constant Complete_Put_Options :=
     (Content_MD5           => Ada.Strings.Unbounded.Null_Unbounded_String,
      Content_Type          => Ada.Strings.Unbounded.Null_Unbounded_String,
      Metadata              => Empty_Object_Metadata,
      Tags                  => Empty_Object_Tags,
      Checksum              => No_Checksum_Information,
      Conditions            => Default_Write_Conditions,
      Expected_Bucket_Owner => Ada.Strings.Unbounded.Null_Unbounded_String);

   --  Publish one complete object through the typed PutObject client. Source
   --  must be one-shot: this call never opts into the blocking HTTP client's
   --  stale-connection replay path. Expected S3 rejections are returned;
   --  after execution begins any propagated timeout, cancellation, transport,
   --  or invalid-response exception is conservatively an unknown publication
   --  outcome and must be reconciled by a generation-bound read. No mutation
   --  is retried by this helper.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination bucket
   --  @param Key Exact destination object key
   --  @param Source One-shot complete request body, borrowed for this call
   --  @param Payload_SHA256 Exact lowercase body digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only while signing this request
   --  @param Options Bounded metadata, tags, checksum, conditions, and owner
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Blocking HTTP exchange budget
   --  @param Token Optional cancellation source
   --  @return Complete PutObject result or structured S3 rejection
   --  @exception Low_Level.Invalid_Request Source or options are invalid
   function Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Options  : Complete_Put_Options := Default_Complete_Put_Options;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Complete_Put_Outcome;

   --  Publish a complete object only when no current object exists. Source
   --  must be a one-shot Request_Body_Source, not a rewindable source; this
   --  prevents the blocking HTTP client from replaying an ambiguous
   --  conditional mutation. Expected rejections, including HTTP 412, are
   --  returned in the typed low-level outcome. Once execution begins, any
   --  propagated exception must conservatively be treated as an unknown
   --  publication outcome and reconciled with Get_Whole; this function does
   --  not classify admission certainty.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Destination bucket
   --  @param Key Exact destination object key
   --  @param Source One-shot complete request body, borrowed for this call
   --  @param Payload_SHA256 Exact lowercase body digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Content_Type Optional object content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Blocking HTTP exchange budget
   --  @param Token Optional cancellation source
   --  @return Complete PutObject result or structured S3 rejection
   --  @exception Low_Level.Invalid_Request Source is rewindable or invalid
   function Put_If_Absent
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Outcome;

   --  Blocking buffer-owned conditional PUT implemented by waiting on the
   --  composable operation. Unlike the legacy one-shot source overload, its
   --  result preserves HTTP admission and publication certainty. Its defaults
   --  intentionally match the established source-based overload; changing
   --  them would be a source and wire-compatibility change.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Payload_Buffer Acquired bytes restored before return
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed publication certainty and terminal result
   function Put_If_Absent
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Scoped.Conditional_Put_Result
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   --  Replace a complete current object only when its opaque HTTP entity tag
   --  exactly matches Expected_Entity_Tag. Pass the quoted ETag returned by
   --  Put_If_Absent, Put_If_Matches, Get_Whole, or HeadObject unchanged.
   --  Source and exception certainty follow Put_If_Absent.
   function Put_If_Matches
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Outcome;

   --  Blocking buffer-owned compare-and-swap PUT implemented by waiting on
   --  the composable operation and preserving its exact certainty mapping.
   --  Defaults match the established source-based overload so buffer
   --  ownership does not select different wire policy.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Destination bucket
   --  @param Key Exact destination key
   --  @param Expected_Entity_Tag Exact strong opaque generation validator
   --  @param Payload_Buffer Acquired bytes restored before return
   --  @param Payload_SHA256 Exact lowercase digest or UNSIGNED-PAYLOAD
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Content_Type Optional content type
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed publication certainty and terminal result
   function Put_If_Matches
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Scoped.Conditional_Put_Result
     with Pre => Flyology.Buffers.Has_Buffer (Payload_Buffer);

   type Whole_Get_Outcome_Kind is (Whole_Object_Read, Whole_Get_Rejected);

   --  A complete GetObject body and its response metadata from one HTTP
   --  exchange. Result.Entity_Tag and Result.Version_ID remain separate,
   --  opaque provider generation values.
   type Whole_Get_Outcome
     (Kind : Whole_Get_Outcome_Kind := Whole_Get_Rejected) is record
      Status : Flyology.HTTP.Status_Code := 500;
      case Kind is
         when Whole_Object_Read =>
            Result : Low_Level.Get_Object_Result;
            Object_Bytes : Flyology.Bytes.Unbounded_Bytes;
         when Whole_Get_Rejected =>
            Error : S3.Errors.Error_Response;
      end case;
   end record;

   --  Read one complete object and its exact metadata from the same immutable
   --  S3 response. Expected_Entity_Tag binds reconciliation to an opaque ETag;
   --  Version_ID independently selects a provider version when supported.
   --  Maximum bounds retained bytes. A larger or malformed successful body
   --  raises Response_Too_Large or Low_Level.Invalid_Response respectively.
   function Get_Whole
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Maximum  : Natural;
      Identity : Low_Level.Credentials;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Whole_Get_Outcome;

   --  Blocking bounded same-response GET implemented by waiting on the
   --  composable operation. Destination contains bytes only for Object_Opened.
   --  Defaults match the established owned-bytes overload so the bounded
   --  representation does not select different wire policy.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Destination Acquired bounded output buffer
   --  @param Identity Credentials used only during signing
   --  @param Expected_Entity_Tag Optional exact strong ETag validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed same-response metadata or bounded exchange failure
   function Get_Whole
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : aliased in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Scoped.Whole_Get_Result
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Read exactly one generation-bound byte interval by waiting on the
   --  composable range operation. Requested may be bounded, open-ended, or a
   --  suffix range. A successful response returns both the bytes and the
   --  resolved interval from the same 206 response; Destination is empty for
   --  every rejection or exchange failure.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Requested Typed single byte range
   --  @param Destination Acquired bounded output buffer
   --  @param Identity Credentials used only during signing
   --  @param Expected_Entity_Tag Required exact strong generation validator
   --  @param Version_ID Optional exact provider version selector
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Expected_Bucket_Owner Optional owner precondition
   --  @param Request_Payer Empty or requester
   --  @param Checksum_Mode Whether to request provider checksum headers
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed response and resolved interval or bounded failure
   function Get_Range
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : aliased in out Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Scoped.Range_Get_Result
     with Pre => Flyology.Buffers.Has_Buffer (Destination);

   --  Execute one bodyless HeadObject by waiting on the composable operation.
   --  Parameters is the complete modeled HeadObject control surface and is
   --  copied before the operation starts.
   --  @param Client Configured origin client
   --  @param Origin Exact origin used by Client and SigV4
   --  @param Bucket Source bucket
   --  @param Key Exact source key
   --  @param Parameters Complete modeled HeadObject controls
   --  @param Identity Credentials used only during signing
   --  @param Region SigV4 region
   --  @param Style S3 addressing style
   --  @param Timeout Complete operation timeout
   --  @param Token Optional cancellation source
   --  @return Typed complete response or bounded exchange failure
   function Head_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Scoped.Head_Result;

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

   --  Execute one DeleteObject by waiting on the composable operation. This
   --  result-type overload preserves HTTP admission and deletion certainty;
   --  selecting the established Delete_Outcome overload preserves its
   --  existing raising transport contract. All parameters and defaults are
   --  identical so composition does not select different S3 wire policy.
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
   --  @param MFA Optional root-owner MFA device and credential value
   --  @param Bypass_Governance_Retention Optional governance bypass request
   --  @param If_Match_Last_Modified_Time Optional directory-bucket predicate
   --  @param If_Match_Size Optional directory-bucket size predicate
   --  @return Typed deletion certainty and terminal response or failure
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
      Token    : access Flyology.Cancellation.Token := null;
      MFA      : String := "";
      Bypass_Governance_Retention : Low_Level.Optional_Boolean :=
        (Is_Set => False, Value => False);
      If_Match_Last_Modified_Time : String := "";
      If_Match_Size : Low_Level.Optional_Byte_Count :=
        (Is_Set => False, Value => 0))
      return Scoped.Delete_Result;

   --  Execute one DeleteObjects request by waiting on the composable
   --  operation. Request is serialized and copied before admission; the
   --  resulting one-shot body is never replayed. A processed result retains
   --  the complete per-entry Deleted/Error response. Unknown outcomes require
   --  read-only reconciliation of every requested generation before retry.
   --  @param Client Configured, caller-owned Flyology HTTP client
   --  @param Origin Exact origin used to configure Client and sign requests
   --  @param Bucket Bucket whose selected entries are deleted
   --  @param Request Bounded ordered delete request
   --  @param Parameters Complete modeled DeleteObjects controls
   --  @param Identity Credentials used only while signing this request
   --  @param Region SigV4 signing region
   --  @param Style Path or virtual-hosted addressing
   --  @param Timeout Whole-operation budget
   --  @param Token Optional cancellation source
   --  @return Typed batch certainty and per-entry response or failure
   function Delete_Objects
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Scoped.Delete_Objects_Result;

   --  Delete one object or a specific object version. S3 treats a missing
   --  unversioned key as a successful idempotent deletion. Every modeled
   --  DeleteObject control is available here; optional boolean/count values
   --  distinguish an omitted header from an explicitly supplied false or
   --  zero value. Transport, timeout, and cancellation exceptions after
   --  request admission may mean the deletion was published. The call is not
   --  transparently replayed; reconcile the exact key/generation before any
   --  conditional retry.
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
   --  @param MFA Optional root-owner MFA device and credential value
   --  @param Bypass_Governance_Retention Optional governance bypass request
   --  @param If_Match_Last_Modified_Time Optional directory-bucket predicate
   --  @param If_Match_Size Optional directory-bucket size predicate
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
      Token    : access Flyology.Cancellation.Token := null;
      MFA      : String := "";
      Bypass_Governance_Retention : Low_Level.Optional_Boolean :=
        (Is_Set => False, Value => False);
      If_Match_Last_Modified_Time : String := "";
      If_Match_Size : Low_Level.Optional_Byte_Count :=
        (Is_Set => False, Value => 0))
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
