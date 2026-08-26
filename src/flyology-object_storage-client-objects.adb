with System.Address_To_Access_Conversions;
with System.Storage_Elements;
with Flyology.Operations.Drivers;
with Ada.Strings.Fixed;
with Ada.Calendar;
with Ada.Calendar.Formatting;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.IMF_Dates;
with Flyology.Object_Storage.S3.Tagging;

package body Flyology.Object_Storage.Client.Objects is

   package US renames Ada.Strings.Unbounded;
   package Buffer_Drivers renames Flyology.Buffers.Drivers;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Operations renames Flyology.Operations;
   package Operation_Drivers renames Flyology.Operations.Drivers;
   package Low renames Flyology.Object_Storage.Client.Low_Level;
   package Core renames Flyology.Object_Storage.S3.Core;
   package Byte_Pointers is new System.Address_To_Access_Conversions
     (Ada.Streams.Stream_Element);

   use type Ada.Streams.Stream_Element_Offset;
   use type HTTP_Client.Admission_Certainty;
   use type HTTP_Client.Exchange_Result_Kind;
   use type Operations.Driver_Event;
   use type System.Storage_Elements.Storage_Offset;
   use type US.Unbounded_String;

   Response_Limit_Exceeded : exception;

   function Failed_Reason
     (Kind : HTTP_Client.Exchange_Result_Kind) return Failure_Reason is
     (case Kind is
         when HTTP_Client.Pre_Admission_Rejected => Invalid_Request,
         when HTTP_Client.Cancelled => Cancelled,
         when HTTP_Client.Timed_Out => Timed_Out,
         when HTTP_Client.Client_Unavailable => Client_Unavailable,
         when HTTP_Client.Connection_Failed => Connection_Failed,
         when HTTP_Client.Transport_Failed => Transport_Failed,
         when HTTP_Client.Request_Source_Failed => Request_Source_Failed,
         when HTTP_Client.Response_Body_Too_Large => Response_Too_Large,
         when HTTP_Client.Response_Complete |
              HTTP_Client.Response_Invalid |
              HTTP_Client.Response_Sink_Failed =>
           Corrupt_Or_Invalid_Response);

   function Failed_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Publication_Disposition is
   begin
      if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then
         return Cancelled_Before_Publication;
      elsif Admission = HTTP_Client.Not_Admitted then
         return Definitely_Not_Published;
      else
         return Outcome_Unknown;
      end if;
   end Failed_Disposition;

   use type Low_Level.Put_Object_Outcome_Kind;
   use type Low_Level.Get_Object_ACL_Outcome_Kind;
   use type Low_Level.Delete_Objects_Outcome_Kind;
   use type Low_Level.Get_Object_Attributes_Outcome_Kind;
   use type Core.Range_Parse_Status;

   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.Get_Object_Legal_Hold_Outcome_Kind;
   use type Low_Level.Get_Object_Retention_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.Object_Tagging_Outcome_Kind;
   use type Low_Level.Put_Object_Legal_Hold_Outcome_Kind;
   use type Low_Level.Put_Object_Retention_Outcome_Kind;

   function Timestamp return String is
      Image : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => False,
         Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 3) &
        Image (Image'First + 5 .. Image'First + 6) &
        Image (Image'First + 8 .. Image'First + 9) & "T" &
        Image (Image'First + 11 .. Image'First + 12) &
        Image (Image'First + 14 .. Image'First + 15) &
        Image (Image'First + 17 .. Image'First + 18) & "Z";
   end Timestamp;

   function Valid_Exact_Entity_Tag (Value : String) return Boolean is
   begin
      if Value'Length < 2
        or else Value (Value'First) /= '"'
        or else Value (Value'Last) /= '"'
      then
         return False;
      end if;
      for Index in Value'First + 1 .. Value'Last - 1 loop
         declare
            Code : constant Natural := Character'Pos (Value (Index));
         begin
            if Value (Index) = '"'
              or else not
                (Code = 16#21#
                 or else Code in 16#23# .. 16#7E#
                 or else Code in 16#80# .. 16#FF#)
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Valid_Exact_Entity_Tag;

   procedure Raise_List_Objects_Exchange_Failure
     (Result : List_Objects_Result) is
   begin
      case Result.HTTP_Result is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error with
              "unreachable complete ListObjects exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              "ListObjects response is invalid or exceeds the XML limit";
      end case;
   end Raise_List_Objects_Exchange_Failure;

   procedure Raise_Object_Tagging_Exchange_Failure
     (Kind      : Flyology.HTTP.Client.Exchange_Result_Kind;
      Operation : String) is
   begin
      case Kind is
         when Flyology.HTTP.Client.Response_Complete =>
            raise Program_Error with
              "unreachable complete " & Operation & " exchange failure";
         when Flyology.HTTP.Client.Pre_Admission_Rejected =>
            raise Constraint_Error with "HTTP request was rejected";
         when Flyology.HTTP.Client.Cancelled =>
            raise Flyology.Cancellation.Operation_Cancelled;
         when Flyology.HTTP.Client.Timed_Out =>
            raise Flyology.IO.Timeout_Error;
         when Flyology.HTTP.Client.Client_Unavailable =>
            raise Flyology.HTTP.Client.Client_Closed;
         when Flyology.HTTP.Client.Connection_Failed =>
            raise Flyology.HTTP.Client.Connection_Error;
         when Flyology.HTTP.Client.Transport_Failed =>
            raise Flyology.IO.Device_Error;
         when Flyology.HTTP.Client.Request_Source_Failed =>
            raise Flyology.HTTP.Client.Request_Body_Error;
         when Flyology.HTTP.Client.Response_Invalid |
              Flyology.HTTP.Client.Response_Body_Too_Large |
              Flyology.HTTP.Client.Response_Sink_Failed =>
            raise Low_Level.Invalid_Response with
              Operation & " response is invalid or exceeds the XML limit";
      end case;
   end Raise_Object_Tagging_Exchange_Failure;

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
      return List_Outcome
   is
      Parameters : Low_Level.List_Objects_V2_Parameters;
   begin
      Parameters.Prefix := US.To_Unbounded_String (Prefix);
      Parameters.Delimiter := US.To_Unbounded_String (Delimiter);
      Parameters.Continuation_Token :=
        US.To_Unbounded_String (Continuation_Token);
      Parameters.Has_Continuation_Token := Continuation_Token'Length > 0;
      Parameters.Start_After := US.To_Unbounded_String (Start_After);
      Parameters.Max_Keys := Maximum;
      Parameters.Fetch_Owner := Fetch_Owner;
      Parameters.Has_Fetch_Owner := Fetch_Owner;
      Parameters.URL_Encoding := URL_Encoding;
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Include_Restore_Status := Include_Restore_Status;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Objects_V2
             (Origin, Style, Bucket, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.List_Objects_V2_Outcome :=
           Low_Level.Execute_List_Objects_V2
             (Client, Prepared, Timeout, Token);
      begin
         if Outcome.Kind = Low_Level.Rejected then
            return
              (Kind => List_Rejected, Status => Outcome.Status,
               Error => Outcome.Error);
         end if;
         return
           (Kind            => Page_Available,
            Status          => Outcome.Status,
            Page            => Outcome.Listing,
            Request_Charged => Outcome.Request_Charged);
      end;
   end List_Page;

   function List_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_V2_Result
   is
      --  The listing parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : List_Objects_V2_Operation :=
           List_Page
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : List_Objects_V2_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end List_Page;

   function List_V1_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_Result
   is
      --  The listing parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : List_Objects_Operation :=
           List_V1_Page
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : List_Objects_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end List_V1_Page;

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
      return List_V1_Outcome
   is
      Parameters : Low_Level.List_Objects_Parameters;
   begin
      Parameters.Prefix := US.To_Unbounded_String (Prefix);
      Parameters.Has_Prefix := Prefix'Length > 0;
      Parameters.Delimiter := US.To_Unbounded_String (Delimiter);
      Parameters.Has_Delimiter := Delimiter'Length > 0;
      Parameters.Marker := US.To_Unbounded_String (Marker);
      Parameters.Has_Marker := Marker'Length > 0;
      Parameters.Max_Keys := Maximum;
      Parameters.Has_Max_Keys := True;
      Parameters.URL_Encoding := URL_Encoding;
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Include_Restore_Status := Include_Restore_Status;
      declare
         Result : constant List_Objects_Result :=
           List_V1_Page
             (Client, Origin, Bucket, Parameters, Identity, Region, Style,
              Timeout, Token);
      begin
         if Result.Kind = List_Objects_Exchange_Failed then
            Raise_List_Objects_Exchange_Failure (Result);
         end if;
         declare
            Outcome : Low_Level.List_Objects_Outcome renames Result.Response;
         begin
            if Outcome.Kind = Low_Level.Rejected then
               return
                 (Kind => List_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            declare
               Page : S3.Listings.List_Objects_Result renames
                 Outcome.Result.Listing;
               Next : US.Unbounded_String;

               function Logical_Marker (Value : String) return String is
               begin
                  if Page.Has_Encoding_Type then
                     return S3.Listings.Decode_URL_Value (Value);
                  end if;
                  return Value;
               exception
                  when S3.Listings.Malformed_Listing =>
                     raise Low_Level.Invalid_Response with
                       "malformed encoded ListObjects marker";
               end Logical_Marker;
            begin
               if Page.Is_Truncated then
                  if Page.Has_Next_Marker then
                     Next := US.To_Unbounded_String
                       (Logical_Marker (US.To_String (Page.Next_Marker)));
                  elsif not Page.Contents.Is_Empty then
                     Next := US.To_Unbounded_String
                       (Logical_Marker
                          (US.To_String (Page.Contents.Last_Element.Key)));
                  else
                     raise Low_Level.Invalid_Response with
                       "truncated ListObjects page lacks a continuation " &
                       "marker";
                  end if;
               end if;
               return
                 (Kind            => Page_Available,
                  Status          => Outcome.Status,
                  Page            => Page,
                  Next_Marker     => Next,
                  Has_Next_Marker => Page.Is_Truncated,
                  Request_Charged => Outcome.Result.Request_Charged);
            end;
         end;
      end;
   end List_V1_Page;

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
      return List_Versions_Outcome
   is
      Parameters : Low_Level.List_Object_Versions_Parameters;
   begin
      Parameters.Prefix := US.To_Unbounded_String (Prefix);
      Parameters.Has_Prefix := Prefix'Length > 0;
      Parameters.Delimiter := US.To_Unbounded_String (Delimiter);
      Parameters.Has_Delimiter := Delimiter'Length > 0;
      Parameters.Key_Marker := US.To_Unbounded_String (Key_Marker);
      Parameters.Has_Key_Marker := Key_Marker'Length > 0;
      Parameters.Version_ID_Marker :=
        US.To_Unbounded_String (Version_ID_Marker);
      Parameters.Has_Version_ID_Marker := Version_ID_Marker'Length > 0;
      Parameters.Max_Keys := Maximum;
      Parameters.Has_Max_Keys := True;
      Parameters.URL_Encoding := URL_Encoding;
      Parameters.Include_Restore_Status := Include_Restore_Status;
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Object_Versions
             (Origin, Style, Bucket, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.List_Object_Versions_Outcome :=
           Low_Level.Execute_List_Object_Versions
             (Client, Prepared, Timeout, Token);
      begin
         if Outcome.Kind = Low_Level.Rejected then
            return
              (Kind => List_Rejected, Status => Outcome.Status,
               Error => Outcome.Error);
         end if;
         declare
            Page : S3.Versions.List_Object_Versions_Result renames
              Outcome.Result.Listing;
            Next_Key : US.Unbounded_String;
            Next_Version : US.Unbounded_String;
         begin
            if Page.Is_Truncated then
               Next_Key :=
                 (if Page.Has_Encoding_Type
                  then US.To_Unbounded_String
                    (S3.Listings.Decode_URL_Value
                       (US.To_String (Page.Next_Key_Marker)))
                  else Page.Next_Key_Marker);
               Next_Version := Page.Next_Version_ID_Marker;
            end if;
            return
              (Kind                   => Page_Available,
               Status                 => Outcome.Status,
               Page                   => Page,
               Next_Key_Marker        => Next_Key,
               Next_Version_ID_Marker => Next_Version,
               Has_Next_Markers       => Page.Is_Truncated,
               Request_Charged        => Outcome.Result.Request_Charged);
         exception
            when S3.Listings.Malformed_Listing =>
               raise Low_Level.Invalid_Response with
                 "malformed encoded ListObjectVersions next key marker";
         end;
      end;
   end List_Versions_Page;

   function List_Versions_Page
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Object_Versions_Result
   is
      --  The listing parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : List_Object_Versions_Operation :=
           List_Versions_Page
             (Set'Access, Client'Access, Origin, Bucket, Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : List_Object_Versions_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end List_Versions_Page;

   procedure Apply_Complete_Put_Options
     (Options    : Complete_Put_Options;
      Parameters : in out Low_Level.Put_Object_Parameters)
   is
      Content_Type : constant String := US.To_String (Options.Content_Type);

      procedure Copy
        (Value  : Optional_Metadata_Value;
         Target : out US.Unbounded_String) is
      begin
         Target :=
           (if Value.Is_Set then Value.Value else US.Null_Unbounded_String);
      end Copy;

      procedure Set_Checksum is
         Value : constant US.Unbounded_String := Options.Checksum.Value;
      begin
         if Options.Checksum.Algorithm = No_Checksum then
            if Options.Checksum.Method /= No_Checksum_Method
              or else US.Length (Value) > 0
            then
               raise Low_Level.Invalid_Request with
                 "incomplete PutObject checksum selection";
            end if;
            return;
         elsif Options.Checksum.Method /= Full_Object_Checksum
           or else US.Length (Value) = 0
         then
            raise Low_Level.Invalid_Request with
              "PutObject requires one full-object checksum";
         end if;
         case Options.Checksum.Algorithm is
            when No_Checksum =>
               null;
            when Checksum_CRC32 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.CRC32));
               Parameters.Checksum_CRC32 := Value;
            when Checksum_CRC32C =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.CRC32C));
               Parameters.Checksum_CRC32C := Value;
            when Checksum_CRC64NVME =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.CRC64NVME));
               Parameters.Checksum_CRC64NVME := Value;
            when Checksum_SHA1 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.SHA1));
               Parameters.Checksum_SHA1 := Value;
            when Checksum_SHA256 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.SHA256));
               Parameters.Checksum_SHA256 := Value;
            when Checksum_SHA512 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.SHA512));
               Parameters.Checksum_SHA512 := Value;
            when Checksum_MD5 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.MD5));
               Parameters.Checksum_MD5 := Value;
            when Checksum_XXHASH64 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.XXHASH64));
               Parameters.Checksum_XXHASH64 := Value;
            when Checksum_XXHASH3 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.XXHASH3));
               Parameters.Checksum_XXHASH3 := Value;
            when Checksum_XXHASH128 =>
               Parameters.Checksum_Algorithm := US.To_Unbounded_String
                 (S3.Checksum_Policy.Wire_Name
                    (S3.Checksum_Policy.Core.XXHASH128));
               Parameters.Checksum_XXHASH128 := Value;
         end case;
      end Set_Checksum;
   begin
      if not Valid_Object_Metadata (Options.Metadata, Content_Type)
        or else not S3.Tagging.Valid_S3_Tags (Options.Tags)
        or else not Valid_Object_Write_Conditions
          (US.To_String (Options.Conditions.If_Match),
           US.To_String (Options.Conditions.If_None_Match))
      then
         raise Low_Level.Invalid_Request with
           "invalid complete PutObject options";
      end if;
      Parameters.Content_MD5 := Options.Content_MD5;
      Parameters.Content_Type := Options.Content_Type;
      Parameters.If_Match := Options.Conditions.If_Match;
      Parameters.If_None_Match := Options.Conditions.If_None_Match;
      Parameters.Expected_Bucket_Owner := Options.Expected_Bucket_Owner;
      Copy (Options.Metadata.Cache_Control, Parameters.Cache_Control);
      Copy
        (Options.Metadata.Content_Disposition,
         Parameters.Content_Disposition);
      Copy (Options.Metadata.Content_Encoding, Parameters.Content_Encoding);
      Copy (Options.Metadata.Content_Language, Parameters.Content_Language);
      Copy
        (Options.Metadata.Website_Redirect_Location,
         Parameters.Website_Redirect_Location);
      if Options.Metadata.Expires.Is_Set then
         Parameters.Expires := US.To_Unbounded_String
           (S3.IMF_Dates.Image (Options.Metadata.Expires.Value));
      end if;
      for Index in 1 .. Options.Metadata.User.Length loop
         Parameters.Metadata.Append
           (Low_Level.Metadata_Entry'
              (Name  => Options.Metadata.User.Items (Index).Key,
               Value => Options.Metadata.User.Items (Index).Value));
      end loop;
      if Options.Tags.Length > 0 then
         Parameters.Tagging := US.To_Unbounded_String
           (S3.Tagging.Serialize_Header (Options.Tags));
      end if;
      Set_Checksum;
   exception
      when S3.Tagging.Invalid_Tag =>
         raise Low_Level.Invalid_Request with
           "invalid complete PutObject tags";
   end Apply_Complete_Put_Options;

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
      return Complete_Put_Outcome
   is
      Parameters : Low_Level.Put_Object_Parameters;
   begin
      if Source in Flyology.HTTP.Client.Rewindable_Request_Body_Source'Class
      then
         raise Low_Level.Invalid_Request with
           "complete PutObject source must be one-shot";
      end if;
      Apply_Complete_Put_Options (Options, Parameters);
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object
             (Origin, Style, Bucket, Key, Parameters, Payload_SHA256,
              Identity, Region, Timestamp);
         Outcome : constant Conditional_Put_Outcome :=
           Low_Level.Execute_Put_Object
             (Client, Prepared, Source, Timeout, Token);
      begin
         return Outcome;
      end;
   end Put_Object;

   function Put_Object
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Options  : Complete_Put_Options := Default_Complete_Put_Options;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Result
   is
      Parameters : Low_Level.Put_Object_Parameters;
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      Apply_Complete_Put_Options (Options, Parameters);
      declare
         Operation : Conditional_Put_Operation := Put_Object
           (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
            Payload_Buffer, Payload_SHA256, Identity,
            Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
            Token);
         Result : Conditional_Put_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result, Payload_Buffer);
         return Result;
      end;
   end Put_Object;

   function Conditional_Put
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      If_Match : String;
      If_None_Match : String;
      Source   : in out Flyology.HTTP.Client.Request_Body_Source'Class;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Region   : String;
      Style    : Low_Level.Addressing_Style;
      Content_Type : String;
      Expected_Bucket_Owner : String;
      Timeout  : Duration;
      Token    : access Flyology.Cancellation.Token)
      return Conditional_Put_Outcome
   is
      Options : Complete_Put_Options := Default_Complete_Put_Options;
   begin
      Options.Conditions.If_Match := US.To_Unbounded_String (If_Match);
      Options.Conditions.If_None_Match :=
        US.To_Unbounded_String (If_None_Match);
      Options.Content_Type := US.To_Unbounded_String (Content_Type);
      Options.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      return Put_Object
        (Client, Origin, Bucket, Key, Source, Payload_SHA256, Identity,
         Options, Region, Style, Timeout, Token);
   end Conditional_Put;

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
      return Conditional_Put_Outcome is
   begin
      return Conditional_Put
        (Client, Origin, Bucket, Key, "", "*", Source, Payload_SHA256,
         Identity, Region, Style, Content_Type, Expected_Bucket_Owner,
         Timeout, Token);
   end Put_If_Absent;

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
      return Conditional_Put_Outcome is
   begin
      if not Valid_Exact_Entity_Tag (Expected_Entity_Tag) then
         raise Low_Level.Invalid_Request with
           "Put_If_Matches requires one strong entity tag";
      end if;
      return Conditional_Put
        (Client, Origin, Bucket, Key, Expected_Entity_Tag, "", Source,
         Payload_SHA256, Identity, Region, Style, Content_Type,
         Expected_Bucket_Owner, Timeout, Token);
   end Put_If_Matches;

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
      return Conditional_Put_Result
   is
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Operation : Conditional_Put_Operation :=
        Put_If_Absent
          (Set'Access, Client'Access, Origin, Bucket, Key, Payload_Buffer,
           Payload_SHA256, Identity,
           Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
           Content_Type, Expected_Bucket_Owner, Token);
      Result : Conditional_Put_Result;
   begin
      Flyology.Operations.Wait_All (Set);
      Finish (Operation, Result, Payload_Buffer);
      return Result;
   end Put_If_Absent;

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
      return Conditional_Put_Result
   is
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Operation : Conditional_Put_Operation :=
        Put_If_Matches
          (Set'Access, Client'Access, Origin, Bucket, Key,
           Expected_Entity_Tag, Payload_Buffer, Payload_SHA256, Identity,
           Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
           Content_Type, Expected_Bucket_Owner, Token);
      Result : Conditional_Put_Result;
   begin
      Flyology.Operations.Wait_All (Set);
      Finish (Operation, Result, Payload_Buffer);
      return Result;
   end Put_If_Matches;

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
      return Whole_Get_Outcome
   is
      Parameters : Low_Level.Get_Object_Parameters;
   begin
      if Expected_Entity_Tag'Length > 0
        and then not Valid_Exact_Entity_Tag (Expected_Entity_Tag)
      then
         raise Low_Level.Invalid_Request with
           "Get_Whole requires one strong entity tag";
      end if;
      Parameters.If_Match :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Checksum_Mode := Checksum_Mode;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Get_Object
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Timestamp);
         Response : Flyology.HTTP.Client.Response :=
           Low_Level.Execute_Get_Object
             (Client, Prepared, Timeout, Token);
         Head : constant Low_Level.Get_Object_Head_Outcome :=
           Low_Level.Decode_Get_Object_Response_Head
             (Response, Token);
      begin
         if Head.Kind = Low_Level.Get_Object_Rejected then
            return
              (Kind   => Whole_Get_Rejected,
               Status => Head.Status,
               Error  => Head.Error);
         end if;
         if Head.Status /= 200 then
            raise Low_Level.Invalid_Response with
              "whole GetObject returned a partial response";
         elsif not Valid_Exact_Entity_Tag
           (US.To_String (Head.Result.Entity_Tag))
         then
            raise Low_Level.Invalid_Response with
              "GetObject success has no exact opaque entity tag";
         elsif not Head.Result.Content_Length.Is_Set then
            raise Low_Level.Invalid_Response with
              "GetObject success omits Content-Length";
         elsif Head.Result.Content_Length.Value > Byte_Count (Maximum) then
            raise Flyology.HTTP.Client.Response_Too_Large with
              "GetObject body exceeds caller maximum";
         end if;
         declare
            Object_Bytes : constant Flyology.Bytes.Unbounded_Bytes :=
              Flyology.HTTP.Client.Read_All (Response, Maximum, Token);
         begin
            if Byte_Count (Flyology.Bytes.Length (Object_Bytes)) /=
              Head.Result.Content_Length.Value
            then
               raise Low_Level.Invalid_Response with
                 "GetObject body length does not match response metadata";
            end if;
            return
              (Kind   => Whole_Object_Read,
               Status => Head.Status,
               Result => Head.Result,
               Object_Bytes => Object_Bytes);
         end;
      end;
   end Get_Whole;

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
      return Whole_Get_Result
   is
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Operation : Whole_Get_Operation := Get_Whole
        (Set'Access, Client'Access, Origin, Bucket, Key,
         Destination'Access, Identity,
         Flyology.HTTP.Client.Deadline_After (Timeout),
         Expected_Entity_Tag, Version_ID, Region, Style,
         Expected_Bucket_Owner, Request_Payer, Checksum_Mode, Token);
      Result : Whole_Get_Result;
   begin
      Flyology.Operations.Wait_All (Set);
      Finish (Operation, Result);
      return Result;
   end Get_Whole;

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
      return Range_Get_Result
   is
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Operation : Range_Get_Operation := Get_Range
        (Set'Access, Client'Access, Origin, Bucket, Key, Requested,
         Destination'Access, Identity,
         Flyology.HTTP.Client.Deadline_After (Timeout),
         Expected_Entity_Tag, Version_ID, Region, Style,
         Expected_Bucket_Owner, Request_Payer, Checksum_Mode, Token);
      Result : Range_Get_Result;
   begin
      Flyology.Operations.Wait_All (Set);
      Finish (Operation, Result);
      return Result;
   end Get_Range;

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
      return Head_Result
   is
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Operation : Head_Operation := Head_Object
        (Set'Access, Client'Access, Origin, Bucket, Key, Parameters, Identity,
         Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style, Token);
      Result : Head_Result;
   begin
      Flyology.Operations.Wait_All (Set);
      Finish (Operation, Result);
      return Result;
   end Head_Object;

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
      return Delete_Result
   is
      Parameters : Low_Level.Delete_Object_Parameters;
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.MFA := US.To_Unbounded_String (MFA);
      Parameters.Bypass_Governance_Retention :=
        Bypass_Governance_Retention;
      Parameters.If_Match_Last_Modified_Time :=
        US.To_Unbounded_String (If_Match_Last_Modified_Time);
      Parameters.If_Match_Size := If_Match_Size;
      declare
         Operation : Delete_Operation := Delete
           (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
            Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
            Style, Token);
         Result : Delete_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Delete;

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
      return Delete_Objects_Result
   is
      --  The object operation, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
      Operation : Delete_Objects_Operation := Delete_Objects
        (Set'Access, Client'Access, Origin, Bucket, Request, Parameters,
         Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
         Style, Token);
      Result : Delete_Objects_Result;
   begin
      Flyology.Operations.Wait_All (Set);
      Finish (Operation, Result);
      return Result;
   end Delete_Objects;

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
      return Delete_Outcome
   is
      Parameters : Low_Level.Delete_Object_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.MFA := US.To_Unbounded_String (MFA);
      Parameters.Bypass_Governance_Retention :=
        Bypass_Governance_Retention;
      Parameters.If_Match_Last_Modified_Time :=
        US.To_Unbounded_String (If_Match_Last_Modified_Time);
      Parameters.If_Match_Size := If_Match_Size;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Delete_Object
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.Delete_Object_Outcome :=
           Low_Level.Execute_Delete_Object
             (Client, Prepared, Timeout, Token);
      begin
         if Outcome.Kind = Low_Level.Delete_Object_Rejected then
            return
              (Kind => Delete_Rejected, Status => Outcome.Status,
               Error => Outcome.Error);
         end if;
         return
           (Kind            => Object_Removed,
            Status          => Outcome.Status,
            Delete_Marker   => Outcome.Result.Delete_Marker,
            Version_ID      => Outcome.Result.Version_ID,
            Request_Charged => Outcome.Result.Request_Charged);
      end;
   end Delete;

   function Get_ACL
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits)
      return Get_Object_ACL_Result
   is
      --  The ACL-read parent, HTTP exchange, and HTTP's single active
      --  transport child determine this derived capacity.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Object_ACL_Operation :=
           Get_ACL
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Limits, Token);
         Result : Get_Object_ACL_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_ACL;

   function Get_Legal_Hold
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Legal_Hold_Result
   is
      --  Derived capacity: legal-hold parent, HTTP exchange, and HTTP's
      --  single active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Legal_Hold_Operation :=
           Get_Legal_Hold
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Get_Legal_Hold_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Legal_Hold;

   function Put_Legal_Hold
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Legal_Hold_Result
   is
      --  Derived capacity: legal-hold parent, HTTP exchange, and HTTP's
      --  single active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Put_Legal_Hold_Operation :=
           Put_Legal_Hold
             (Set'Access, Client'Access, Origin, Bucket, Key, Value,
              Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Put_Legal_Hold_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Put_Legal_Hold;

   function Get_Retention
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Retention_Result
   is
      --  Derived capacity: retention parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Retention_Operation :=
           Get_Retention
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Get_Retention_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Retention;

   function Put_Retention
     (Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout    : Duration := 30.0;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Retention_Result
   is
      --  Derived capacity: retention parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Put_Retention_Operation :=
           Put_Retention
             (Set'Access, Client'Access, Origin, Bucket, Key, Value,
              Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Put_Retention_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Put_Retention;

   function Put_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Tags : Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity : Low_Level.Credentials;
      Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Put_Object_Tagging_Result
   is
      --  Derived capacity: tagging parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Put_Object_Tagging_Operation :=
           Put_Tags
             (Set'Access, Client'Access, Origin, Bucket, Key, Tags,
              Parameters, Identity,
              Flyology.HTTP.Client.Deadline_After (Timeout), Region, Style,
              Token);
         Result : Put_Object_Tagging_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Put_Tags;

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
      return Tagging_Outcome
   is
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Checksum_Algorithm :=
        US.To_Unbounded_String (Checksum_Algorithm);
      declare
         Result : constant Put_Object_Tagging_Result :=
           Put_Tags
             (Client, Origin, Bucket, Key, Tags, Parameters, Identity,
              Region, Style, Timeout, Token);
      begin
         if Result.Kind = Put_Object_Tagging_Exchange_Failed then
            Raise_Object_Tagging_Exchange_Failure
              (Result.HTTP_Result, "PutObjectTagging");
         end if;
         declare
            Outcome : Low_Level.Object_Tagging_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Object_Tagging_Rejected then
               return
                 (Kind => Tagging_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind => Tags_Replaced, Status => Outcome.Status,
               Result => Outcome.Result);
         end;
      end;
   end Put_Tags;

   function Get_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Get_Object_Tagging_Result
   is
      --  Derived capacity: tagging parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Object_Tagging_Operation :=
           Get_Tags
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Get_Object_Tagging_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Tags;

   function Get_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Request_Payer : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome
   is
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      declare
         Result : constant Get_Object_Tagging_Result :=
           Get_Tags
             (Client, Origin, Bucket, Key, Parameters, Identity, Region,
              Style, Timeout, Token);
      begin
         if Result.Kind = Get_Object_Tagging_Exchange_Failed then
            Raise_Object_Tagging_Exchange_Failure
              (Result.HTTP_Result, "GetObjectTagging");
         end if;
         declare
            Outcome : Low_Level.Object_Tagging_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Object_Tagging_Rejected then
               return
                 (Kind => Tagging_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind => Tags_Read, Status => Outcome.Status,
               Result => Outcome.Result);
         end;
      end;
   end Get_Tags;

   function Delete_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Object_Tagging_Result
   is
      --  Derived capacity: tagging parent, HTTP exchange, and HTTP's single
      --  active transport child are the only simultaneous operations.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Delete_Object_Tagging_Operation :=
           Delete_Tags
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Delete_Object_Tagging_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Delete_Tags;

   function Delete_Tags
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Key : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Version_ID : String := ""; Expected_Bucket_Owner : String := "";
      Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Tagging_Outcome
   is
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      declare
         Result : constant Delete_Object_Tagging_Result :=
           Delete_Tags
             (Client, Origin, Bucket, Key, Parameters, Identity, Region,
              Style, Timeout, Token);
      begin
         if Result.Kind = Delete_Object_Tagging_Exchange_Failed then
            Raise_Object_Tagging_Exchange_Failure
              (Result.HTTP_Result, "DeleteObjectTagging");
         end if;
         declare
            Outcome : Low_Level.Object_Tagging_Outcome renames
              Result.Response;
         begin
            if Outcome.Kind = Low_Level.Object_Tagging_Rejected then
               return
                 (Kind => Tagging_Rejected, Status => Outcome.Status,
                  Error => Outcome.Error);
            end if;
            return
              (Kind => Tags_Cleared, Status => Outcome.Status,
               Result => Outcome.Result);
         end;
      end;
   end Delete_Tags;

   function Get_Attributes
     (Client   : aliased in out Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Timeout  : Duration := 30.0;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Object_Attributes_Result
   is
      --  The attributes parent, HTTP exchange, and HTTP's single active
      --  transport child determine this capacity; it is a derived bound.
      Set : aliased Flyology.Operations.Completion_Set (3);
   begin
      declare
         Operation : Get_Object_Attributes_Operation :=
           Get_Attributes
             (Set'Access, Client'Access, Origin, Bucket, Key, Parameters,
              Identity, Flyology.HTTP.Client.Deadline_After (Timeout), Region,
              Style, Token);
         Result : Get_Object_Attributes_Result;
      begin
         Flyology.Operations.Wait_All (Set);
         Finish (Operation, Result);
         return Result;
      end;
   end Get_Attributes;

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
      return Get_Attributes_Outcome
   is
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Max_Parts := Max_Parts;
      Parameters.Has_Max_Parts := Has_Max_Parts;
      Parameters.Part_Number_Marker := Part_Number_Marker;
      Parameters.Has_Part_Number_Marker := Has_Part_Number_Marker;
      Parameters.SSE_Customer_Algorithm :=
        US.To_Unbounded_String (SSE_Customer_Algorithm);
      Parameters.SSE_Customer_Key := US.To_Unbounded_String (SSE_Customer_Key);
      Parameters.SSE_Customer_Key_MD5 :=
        US.To_Unbounded_String (SSE_Customer_Key_MD5);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Attributes := Attributes;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Get_Object_Attributes
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Timestamp);
      begin
         return Low_Level.Execute_Get_Object_Attributes
           (Client, Prepared, Timeout, Token);
      end;
   end Get_Attributes;

   --  Project certainty exactly from the maintained
   --  tests/corpora/composable-client/put-certainty.tsv oracle. Status and S3
   --  code pairs are externally modeled wire values; changing a row changes
   --  whether callers must reconcile before any later retry.
   function Normalize_Put_Response
     (Value     : Low_Level.Put_Object_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Conditional_Put_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Object_Rejected
         then US.To_String (Value.Error.Code) else "");
   begin
      if Admission /= HTTP_Client.Response_Observed then
         return
           (Kind        => Put_Response_Available,
            Disposition => Outcome_Unknown,
            Failure     => Corrupt_Or_Invalid_Response,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Kind = Low_Level.Object_Put then
         return
           (Kind        => Put_Response_Available,
            Disposition => Published,
            Failure     => No_Failure,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 412 and then Code = "PreconditionFailed" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Precondition_Failed,
            Failure     => No_Failure,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 401 and then Code = "InvalidAccessKeyId" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Authentication_Failed,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 403 and then Code = "AccessDenied" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Authorization_Failed,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 400 and then Code = "InvalidRequest" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Invalid_Request,
            Admission   => Admission,
            Response    => Value);
      elsif Value.Status = 404 and then Code = "NoSuchBucket" then
         return
           (Kind        => Put_Response_Available,
            Disposition => Definitely_Not_Published,
            Failure     => Not_Found,
            Admission   => Admission,
            Response    => Value);
      elsif (Value.Status = 409
             and then Code = "ConditionalRequestConflict")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout")
      then
         return
           (Kind        => Put_Response_Available,
            Disposition => Outcome_Unknown,
            Failure     => Unavailable_Or_Retryable,
            Admission   => Admission,
            Response    => Value);
      else
         return
           (Kind        => Put_Response_Available,
            Disposition => Outcome_Unknown,
            Failure     => Corrupt_Or_Invalid_Response,
            Admission   => Admission,
            Response    => Value);
      end if;
   end Normalize_Put_Response;

   function Normalize_Put_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Required  : HTTP_Client.Length_Requirement := (others => <>);
      Detail    : String := "") return Conditional_Put_Result is
   begin
      return
        (Kind                 => Put_Exchange_Failed,
         Disposition          => Failed_Disposition (Kind, Admission),
         Failure              =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission            => Admission,
         HTTP_Result          => Kind,
         HTTP_Phase           => Phase,
         Required_Body_Length => Required,
         Detail               => US.To_Unbounded_String (Detail));
   end Normalize_Put_Failure;

   overriding function Declared_Length
     (Item : Conditional_Put_Operation)
      return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size (Buffer_Drivers.Length (Item.Source)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Conditional_Put_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural := Buffer_Drivers.Length (Item.Source);
      Count  : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Byte_Pointers.To_Pointer
             (Buffer_Drivers.Address (Item.Source) +
                System.Storage_Elements.Storage_Offset
                  (Item.Source_Position + Offset)).all;
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Conditional_Put_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Conditional_Put_Operation) is
   begin
      --  The parent operation owns the detached token through typed Finish;
      --  releasing the HTTP borrow therefore has no storage action.
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Conditional_Put_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "PutObject response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Child (Item : in out Conditional_Put_Operation) is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish
           (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Put_Failure
               (HTTP_Client.Response_Sink_Failed, Admission,
                HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Put_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Required_Body_Length (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Put_Response
              (Low_Level.Decode_Put_Object_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Child;

   overriding procedure Drive
     (Item : in out Conditional_Put_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Object
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Child (Item);
      else
         raise Program_Error with "invalid PutObject driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Conditional_Put_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Conditional_Put_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Buffer_Drivers.Release (Item.Source);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put
     (Item     : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Put_Object_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String;
      Style    : Low_Level.Addressing_Style;
      Token    : access Flyology.Cancellation.Token)
   is
   begin
      if Item.HTTP /= Client or else Item.Cancellation /= Token then
         raise Program_Error with
           "PutObject restart changed a retained owner";
      end if;
      Item.Prepared := Low_Level.Prepare_Put_Object
        (Origin, Style, Bucket, Key, Parameters, Payload_SHA256, Identity,
         Region, Timestamp);
      Item.Deadline := Deadline;
      Item.Source_Position := 0;
      Flyology.Bytes.Clear (Item.Response_Data);
      Item.Response_Limit :=
        --  Derived resource bound: retained Put error bytes use the same
        --  maintained limit as the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Item.Has_Final_Result := False;
      Item.Has_Saved_Error := False;

      Operation_Drivers.Start (Item);
      begin
         Buffer_Drivers.Move_From (Payload_Buffer, Item.Source);
         Operations.Drive
           (Operations.Operation'Class (Item), Operations.Start_Operation);
      exception
         when others =>
            if Buffer_Drivers.Has_Buffer (Item.Source) then
               Buffer_Drivers.Move_To (Item.Source, Payload_Buffer);
            end if;
            if Operations.Is_Active (Item) then
               Operation_Drivers.Rollback_Start (Item);
            end if;
            Low.Clear_Prepared_Request (Item.Prepared);
            raise;
      end;
   end Start_Put;

   procedure Start_Put_Object
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Put_Object_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      Start_Put
        (Operation, Client, Origin, Bucket, Key, Parameters, Payload_Buffer,
         Payload_SHA256, Identity, Deadline, Region, Style, Token);
   end Start_Put_Object;

   function Put_Object
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Put_Object_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation is
   begin
      return Result : Conditional_Put_Operation (Set, Client, Token) do
         Start_Put_Object
           (Result, Client, Origin, Bucket, Key, Parameters, Payload_Buffer,
            Payload_SHA256, Identity, Deadline, Region, Style, Token);
      end return;
   end Put_Object;

   procedure Start_Put_If_Absent
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null) is
      Parameters : Low_Level.Put_Object_Parameters;
   begin
      Parameters.If_None_Match := US.To_Unbounded_String ("*");
      Parameters.Content_Type := US.To_Unbounded_String (Content_Type);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Start_Put
        (Operation, Client, Origin, Bucket, Key, Parameters, Payload_Buffer,
         Payload_SHA256, Identity, Deadline, Region, Style, Token);
   end Start_Put_If_Absent;

   procedure Start_Put_If_Matches
     (Operation : in out Conditional_Put_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null) is
      Parameters : Low_Level.Put_Object_Parameters;
   begin
      if not Valid_Exact_Entity_Tag (Expected_Entity_Tag) then
         raise Low_Level.Invalid_Request with
           "Put_If_Matches requires one strong entity tag";
      end if;
      Parameters.If_Match := US.To_Unbounded_String (Expected_Entity_Tag);
      Parameters.Content_Type := US.To_Unbounded_String (Content_Type);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Start_Put
        (Operation, Client, Origin, Bucket, Key, Parameters, Payload_Buffer,
         Payload_SHA256, Identity, Deadline, Region, Style, Token);
   end Start_Put_If_Matches;

   function Put_If_Absent
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation is
   begin
      return Result : Conditional_Put_Operation (Set, Client, Token) do
         Start_Put_If_Absent
           (Result, Client, Origin, Bucket, Key, Payload_Buffer,
            Payload_SHA256, Identity, Deadline, Region, Style, Content_Type,
            Expected_Bucket_Owner, Token);
      end return;
   end Put_If_Absent;

   function Put_If_Matches
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null)
      return Conditional_Put_Operation is
   begin
      return Result : Conditional_Put_Operation (Set, Client, Token) do
         Start_Put_If_Matches
           (Result, Client, Origin, Bucket, Key, Expected_Entity_Tag,
            Payload_Buffer, Payload_SHA256, Identity, Deadline, Region, Style,
            Content_Type, Expected_Bucket_Owner, Token);
      end return;
   end Put_If_Matches;

   procedure Finish
     (Operation : in out Conditional_Put_Operation;
      Result    : out Conditional_Put_Result;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer) is
   begin
      if not Buffer_Drivers.Same_Pool
        (Operation.Source, Payload_Buffer)
      then
         raise Program_Error with
           "PutObject Finish requires the original buffer pool";
      end if;
      Operations.Consume (Operation);
      Buffer_Drivers.Move_To (Operation.Source, Payload_Buffer);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutObject has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Read_Exchange_Failure
     (Value : HTTP_Client.Exchange_Result) return Whole_Get_Result is
   begin
      return
        (Kind                 => Whole_Get_Exchange_Failed,
         Failure              => Failed_Reason (HTTP_Client.Kind (Value)),
         HTTP_Result          => HTTP_Client.Kind (Value),
         HTTP_Phase           => HTTP_Client.Phase (Value),
         Required_Body_Length =>
           HTTP_Client.Required_Body_Length (Value),
         Detail               => US.To_Unbounded_String
           (HTTP_Client.Failure_Detail (Value)));
   end Read_Exchange_Failure;

   function Invalid_Read_Result return Whole_Get_Result is
   begin
      return
        (Kind                 => Whole_Get_Exchange_Failed,
         Failure              => Corrupt_Or_Invalid_Response,
         HTTP_Result          => HTTP_Client.Response_Invalid,
         HTTP_Phase           => HTTP_Client.Receiving_Response_Body,
         Required_Body_Length => (others => <>),
         Detail               => US.Null_Unbounded_String);
   end Invalid_Read_Result;

   function Range_Read_Exchange_Failure
     (Value : HTTP_Client.Exchange_Result) return Range_Get_Result is
   begin
      return
        (Kind                 => Range_Get_Exchange_Failed,
         Failure              => Failed_Reason (HTTP_Client.Kind (Value)),
         HTTP_Result          => HTTP_Client.Kind (Value),
         HTTP_Phase           => HTTP_Client.Phase (Value),
         Required_Body_Length =>
           HTTP_Client.Required_Body_Length (Value),
         Detail               => US.To_Unbounded_String
           (HTTP_Client.Failure_Detail (Value)));
   end Range_Read_Exchange_Failure;

   function Invalid_Range_Read_Result return Range_Get_Result is
   begin
      return
        (Kind                 => Range_Get_Exchange_Failed,
         Failure              => Corrupt_Or_Invalid_Response,
         HTTP_Result          => HTTP_Client.Response_Invalid,
         HTTP_Phase           => HTTP_Client.Receiving_Response_Body,
         Required_Body_Length => (others => <>),
         Detail               => US.Null_Unbounded_String);
   end Invalid_Range_Read_Result;

   procedure Clear_Buffer (Item : in out Flyology.Buffers.Unique_Buffer) is
      procedure Clear
        (Data   : in out Ada.Streams.Stream_Element_Array;
         Length : in out Natural) is
      begin
         pragma Unreferenced (Data);
         Length := 0;
      end Clear;
   begin
      Flyology.Buffers.With_Writable_Data (Item, Clear'Access);
   end Clear_Buffer;

   function Buffer_Text
     (Item : Flyology.Buffers.Unique_Buffer) return String
   is
      Bytes : Flyology.Bytes.Unbounded_Bytes;

      procedure Copy (Data : Ada.Streams.Stream_Element_Array) is
      begin
         Bytes := Flyology.Bytes.To_Unbounded_Bytes (Data);
      end Copy;
   begin
      Flyology.Buffers.With_Readable_Data (Item, Copy'Access);
      return Flyology.Bytes.To_Byte_String (Bytes);
   end Buffer_Text;

   function Decimal (Value : Byte_Count) return String is
     (Ada.Strings.Fixed.Trim
        (Byte_Count'Image (Value), Ada.Strings.Both));

   function Valid_Range_Request (Value : Byte_Range) return Boolean is
     (case Value.Kind is
         when Bounded_Range => Value.First <= Value.Last,
         when Open_Ended_Range => True,
         when Suffix_Range => Value.Count > 0,
         when Whole_Range => False);

   --  RFC 9110 single-range wire form. The public Byte_Range domain is the
   --  authority; this formatter introduces no independent bound or policy.
   function Range_Header (Value : Byte_Range) return String is
   begin
      case Value.Kind is
         when Bounded_Range =>
            return "bytes=" & Decimal (Value.First) & "-" &
              Decimal (Value.Last);
         when Open_Ended_Range =>
            return "bytes=" & Decimal (Value.First) & "-";
         when Suffix_Range =>
            return "bytes=-" & Decimal (Value.Count);
         when Whole_Range =>
            raise Low_Level.Invalid_Request with
              "Get_Range requires a non-whole byte range";
      end case;
   end Range_Header;

   function Bind_Response_Range
     (Value     : String;
      Requested : Byte_Range;
      Resolved  : out Resolved_Byte_Range) return Boolean
   is
      Prefix : constant String := "bytes ";
      Hyphen : Natural;
      Slash  : Natural;
   begin
      Resolved := (others => 0);
      if Value'Length <= Prefix'Length
        or else Value (Value'First .. Value'First + Prefix'Length - 1) /=
          Prefix
      then
         return False;
      end if;
      Hyphen := Ada.Strings.Fixed.Index
        (Value, "-", From => Value'First + Prefix'Length);
      Slash := Ada.Strings.Fixed.Index
        (Value, "/", From => Value'First + Prefix'Length);
      if Hyphen = 0 or else Slash = 0 or else Hyphen >= Slash then
         return False;
      end if;
      declare
         Returned : constant Core.Range_Parse_Result :=
           Core.Parse_Range_Header
             ("bytes=" &
                Value (Value'First + Prefix'Length .. Slash - 1));
         Total : constant Byte_Count :=
           Byte_Count'Value (Value (Slash + 1 .. Value'Last));
         Expected : constant Range_Resolution :=
           Core.Resolve_Range (Total, Requested);
      begin
         if Returned.Status /= Core.Range_Parsed
           or else Returned.Request.Kind /= Bounded_Range
           or else Expected.Kind /= Satisfied_Range
           or else Returned.Request.First /= Expected.First
           or else Returned.Request.Last /= Expected.Last
         then
            return False;
         end if;
         Resolved :=
           (First        => Expected.First,
            Last         => Expected.Last,
            Total_Length => Total);
         return True;
      end;
   exception
      when Constraint_Error =>
         return False;
   end Bind_Response_Range;

   procedure Complete_Child (Item : in out Whole_Get_Operation) is
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish
           (Item.Child, HTTP_Result, Response, Item.Destination.all);
      exception
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Read_Exchange_Failure (HTTP_Result);
      else
         begin
            declare
               Head : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Complete_Response
                   (Response, Buffer_Text (Item.Destination.all));
            begin
               if Head.Kind = Low_Level.Get_Object_Rejected then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result :=
                    (Kind     => Whole_Get_Response_Available,
                     Failure  => No_Failure,
                     Response => Head);
               elsif Head.Status /= 200
                 or else not Valid_Exact_Entity_Tag
                   (US.To_String (Head.Result.Entity_Tag))
                 or else not Head.Result.Content_Length.Is_Set
                 or else Head.Result.Content_Length.Value /=
                   Byte_Count
                     (Flyology.Buffers.Length (Item.Destination.all))
                 or else
                   (US.Length (Item.Expected_Entity_Tag) > 0
                      and then Head.Result.Entity_Tag /=
                        Item.Expected_Entity_Tag)
               then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result := Invalid_Read_Result;
               else
                  Item.Final_Result :=
                    (Kind     => Whole_Get_Response_Available,
                     Failure  => No_Failure,
                     Response => Head);
               end if;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Clear_Buffer (Item.Destination.all);
               Item.Final_Result := Invalid_Read_Result;
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Child;

   overriding procedure Drive
     (Item : in out Whole_Get_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object
           (Item.HTTP, Item.Prepared'Access,
            Item.Destination.all, Item.Deadline, Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Child (Item);
      else
         raise Program_Error with "invalid whole GET driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Whole_Get_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Whole_Get_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
   end Finalize;

   procedure Complete_Range_Child (Item : in out Range_Get_Operation) is
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish
           (Item.Child, HTTP_Result, Response, Item.Destination.all);
      exception
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Range_Read_Exchange_Failure (HTTP_Result);
      else
         begin
            declare
               Head : constant Low_Level.Get_Object_Head_Outcome :=
                 Low_Level.Decode_Get_Object_Complete_Response
                   (Response, Buffer_Text (Item.Destination.all));
            begin
               if Head.Kind = Low_Level.Get_Object_Rejected then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result :=
                    (Kind               => Range_Get_Response_Available,
                     Failure            => No_Failure,
                     Response           => Head,
                     Has_Resolved_Range => False,
                     Resolved           => (others => 0));
               elsif Head.Status /= 206
                 or else not Valid_Exact_Entity_Tag
                   (US.To_String (Head.Result.Entity_Tag))
                 or else not Head.Result.Content_Length.Is_Set
                 or else Head.Result.Content_Length.Value /=
                   Byte_Count
                     (Flyology.Buffers.Length (Item.Destination.all))
                 or else Head.Result.Entity_Tag /= Item.Expected_Entity_Tag
               then
                  Clear_Buffer (Item.Destination.all);
                  Item.Final_Result := Invalid_Range_Read_Result;
               else
                  declare
                     Bound : Resolved_Byte_Range;
                  begin
                     if not Bind_Response_Range
                       (US.To_String (Head.Result.Content_Range),
                        Item.Requested_Range, Bound)
                     then
                        Clear_Buffer (Item.Destination.all);
                        Item.Final_Result := Invalid_Range_Read_Result;
                     else
                        Item.Final_Result :=
                          (Kind               => Range_Get_Response_Available,
                           Failure            => No_Failure,
                           Response           => Head,
                           Has_Resolved_Range => True,
                           Resolved           => Bound);
                     end if;
                  end;
               end if;
            end;
         exception
            when Low_Level.Invalid_Response =>
               Clear_Buffer (Item.Destination.all);
               Item.Final_Result := Invalid_Range_Read_Result;
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Range_Child;

   overriding procedure Drive
     (Item : in out Range_Get_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object
           (Item.HTTP, Item.Prepared'Access,
            Item.Destination.all, Item.Deadline, Item.Cancellation,
            Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Range_Child (Item);
      else
         raise Program_Error with "invalid range GET driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Range_Get_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Range_Get_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
   end Finalize;

   procedure Start_Get
     (Item      : in out Whole_Get_Operation;
      Client    : not null access HTTP_Client.Client;
      Origin    : Flyology.HTTP.Origin;
      Bucket    : String;
      Key       : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity  : Low_Level.Credentials;
      Deadline  : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String;
      Region    : String;
      Style     : Low_Level.Addressing_Style;
      Expected_Bucket_Owner : String;
      Request_Payer : String;
      Checksum_Mode : Boolean;
      Token     : access Flyology.Cancellation.Token)
   is
      Parameters : Low_Level.Get_Object_Parameters;
   begin
      if Item.HTTP /= Client
        or else Item.Destination /= Destination
        or else Item.Cancellation /= Token
      then
         raise Program_Error with
           "whole GET restart changed a retained owner";
      end if;
      if Expected_Entity_Tag'Length > 0
        and then not Valid_Exact_Entity_Tag (Expected_Entity_Tag)
      then
         raise Low_Level.Invalid_Request with
           "Get_Whole requires one strong entity tag";
      end if;
      Parameters.If_Match :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Checksum_Mode := Checksum_Mode;
      Item.Prepared := Low_Level.Prepare_Get_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Item.Deadline := Deadline;
      Item.Expected_Entity_Tag :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Item.Has_Final_Result := False;
      Item.Has_Saved_Error := False;

      Operation_Drivers.Start (Item);
      begin
         Operations.Drive
           (Operations.Operation'Class (Item), Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Item) then
               Operation_Drivers.Rollback_Start (Item);
            end if;
            Low.Clear_Prepared_Request (Item.Prepared);
            raise;
      end;
   end Start_Get;

   procedure Start_Get_Whole
     (Operation : in out Whole_Get_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      Start_Get
        (Operation, Client, Origin, Bucket, Key, Destination, Identity,
         Deadline, Expected_Entity_Tag, Version_ID, Region, Style,
         Expected_Bucket_Owner, Request_Payer, Checksum_Mode, Token);
   end Start_Get_Whole;

   function Get_Whole
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
      return Whole_Get_Operation is
   begin
      return Result : Whole_Get_Operation
        (Set, Client, Destination, Token)
      do
         Start_Get_Whole
           (Result, Client, Origin, Bucket, Key, Destination, Identity,
            Deadline, Expected_Entity_Tag, Version_ID, Region, Style,
            Expected_Bucket_Owner, Request_Payer, Checksum_Mode, Token);
      end return;
   end Get_Whole;

   procedure Start_Get_Range
     (Operation : in out Range_Get_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
   is
      Parameters : Low_Level.Get_Object_Parameters;
   begin
      if Operation.HTTP /= Client
        or else Operation.Destination /= Destination
        or else Operation.Cancellation /= Token
      then
         raise Program_Error with
           "range GET restart changed a retained owner";
      elsif not Valid_Exact_Entity_Tag (Expected_Entity_Tag) then
         raise Low_Level.Invalid_Request with
           "Get_Range requires one strong entity tag";
      elsif not Valid_Range_Request (Requested) then
         raise Low_Level.Invalid_Request with
           "Get_Range requires one valid single range";
      end if;
      Parameters.If_Match :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Parameters.Byte_Range_Header :=
        US.To_Unbounded_String (Range_Header (Requested));
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Checksum_Mode := Checksum_Mode;
      Operation.Prepared := Low_Level.Prepare_Get_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Expected_Entity_Tag :=
        US.To_Unbounded_String (Expected_Entity_Tag);
      Operation.Requested_Range := Requested;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;

      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Range;

   function Get_Range
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null)
      return Range_Get_Operation is
   begin
      return Result : Range_Get_Operation
        (Set, Client, Destination, Token)
      do
         Start_Get_Range
           (Result, Client, Origin, Bucket, Key, Requested, Destination,
            Identity, Deadline, Expected_Entity_Tag, Version_ID, Region,
            Style, Expected_Bucket_Owner, Request_Payer, Checksum_Mode,
            Token);
      end return;
   end Get_Range;

   procedure Finish
     (Operation : in out Whole_Get_Operation;
      Result    : out Whole_Get_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "whole GET has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure Finish
     (Operation : in out Range_Get_Operation;
      Result    : out Range_Get_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "range GET has no terminal result";
      elsif Operation.Final_Result.Kind = Range_Get_Response_Available
        and then Operation.Final_Result.Response.Kind = Low_Level.Object_Opened
        and then not Operation.Final_Result.Has_Resolved_Range
      then
         raise Program_Error with "range GET lacks a resolved interval";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Head_Exchange_Failure
     (Value : HTTP_Client.Exchange_Result) return Head_Result is
   begin
      return
        (Kind        => Head_Exchange_Failed,
         Failure     => Failed_Reason (HTTP_Client.Kind (Value)),
         HTTP_Result => HTTP_Client.Kind (Value),
         HTTP_Phase  => HTTP_Client.Phase (Value),
         Detail      => US.To_Unbounded_String
           (HTTP_Client.Failure_Detail (Value)));
   end Head_Exchange_Failure;

   overriding procedure Write
     (Item : in out Head_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      pragma Unreferenced (Item);
      if Data'Length > 0 then
         --  HTTP defines HEAD as bodyless. Reject any octet that its framing
         --  layer nevertheless exposes to this sink; bytes after a complete
         --  HEAD response remain the HTTP connection owner's responsibility.
         raise Response_Limit_Exceeded with
           "HeadObject response contains a body";
      end if;
   end Write;

   procedure Complete_Head_Child (Item : in out Head_Operation) is
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish
           (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              (Kind        => Head_Exchange_Failed,
               Failure     => Corrupt_Or_Invalid_Response,
               HTTP_Result => HTTP_Client.Response_Sink_Failed,
               HTTP_Phase  => HTTP_Client.Receiving_Response_Body,
               Detail      => US.Null_Unbounded_String);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            Low.Clear_Prepared_Request (Item.Prepared);
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Head_Exchange_Failure (HTTP_Result);
      else
         begin
            Item.Final_Result :=
              (Kind     => Head_Response_Available,
               Failure  => No_Failure,
               Response => Low_Level.Decode_Head_Object_Complete_Response
                 (Response, ""));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 (Kind        => Head_Exchange_Failed,
                  Failure     => Corrupt_Or_Invalid_Response,
                  HTTP_Result => HTTP_Client.Response_Invalid,
                  HTTP_Phase  => HTTP_Client.Waiting_Response_Head,
                  Detail      => US.Null_Unbounded_String);
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Head_Child;

   overriding procedure Drive
     (Item : in out Head_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Head_Object
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Head_Child (Item);
      else
         raise Program_Error with "invalid HeadObject driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Head_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Head_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
   end Finalize;

   procedure Start_Head_Object
     (Operation : in out Head_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "HeadObject restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Head_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Head_Object;

   function Head_Object
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Head_Operation is
   begin
      return Result : Head_Operation (Set, Client, Token) do
         Start_Head_Object
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Head_Object;

   procedure Finish
     (Operation : in out Head_Operation;
      Result    : out Head_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "HeadObject has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Delete_Response
     (Value     : Low_Level.Delete_Object_Outcome;
      Admission : HTTP_Client.Admission_Certainty) return Delete_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Delete_Object_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400 and then Code = "InvalidRequest")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else
          (Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion")
        or else (Value.Status = 412 and then Code = "PreconditionFailed");
      Retryable_Response : constant Boolean :=
        (Value.Status = 409 and then Code = "OperationAborted")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout");
      Failure : constant Failure_Reason :=
        (if Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
         then Not_Found
         elsif Value.Status = 400 and then Code = "InvalidRequest"
         then Invalid_Request
         elsif Conclusive_Rejection
         then No_Failure
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Delete_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Deletion_Outcome_Unknown
            elsif Value.Kind = Low_Level.Object_Deleted
            then Deletion_Completed
            elsif Conclusive_Rejection
            then Definitely_Not_Deleted
            else Deletion_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Deleted
            then No_Failure
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Delete_Response;

   function Normalize_Delete_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Result is
   begin
      return
        (Kind        => Delete_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Deletion_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Definitely_Not_Deleted
            else Deletion_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Failure;

   overriding function Declared_Length
     (Item : Delete_Operation) return HTTP_Client.Body_Length is
   begin
      pragma Unreferenced (Item);
      return HTTP_Client.Known_Length (0);
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Delete_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      pragma Unreferenced (Item);
      Data := (others => 0);
      Last := Ada.Streams.Stream_Element_Offset'Pred (Data'First);
      Result := HTTP_Client.Source_Finished;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source (Item : in out Delete_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Delete_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "DeleteObject response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Delete_Child (Item : in out Delete_Operation) is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish
           (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              (Kind        => Delete_Exchange_Failed,
               Disposition =>
                 (if Admission = HTTP_Client.Not_Admitted
                  then Definitely_Not_Deleted
                  else Deletion_Outcome_Unknown),
               Failure     => Corrupt_Or_Invalid_Response,
               Admission   => Admission,
               HTTP_Result => HTTP_Client.Response_Sink_Failed,
               HTTP_Phase  => HTTP_Client.Receiving_Response_Body,
               Detail      => US.Null_Unbounded_String);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Delete_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Delete_Response
              (Low_Level.Decode_Delete_Object_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data)),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 (Kind        => Delete_Exchange_Failed,
                  Disposition => Deletion_Outcome_Unknown,
                  Failure     => Corrupt_Or_Invalid_Response,
                  Admission   => HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Result => HTTP_Client.Response_Invalid,
                  HTTP_Phase  => HTTP_Client.Phase (HTTP_Result),
                  Detail      => US.Null_Unbounded_String);
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Child;

   overriding procedure Drive
     (Item : in out Delete_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Delete_Object
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Child (Item);
      else
         raise Program_Error with "invalid DeleteObject driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Delete_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize (Item : in out Delete_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Object
     (Operation : in out Delete_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "DeleteObject restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Delete_Object
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained DeleteObject error bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Object;

   function Delete
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Operation is
   begin
      return Result : Delete_Operation (Set, Client, Token) do
         Start_Delete_Object
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Delete;

   procedure Finish
     (Operation : in out Delete_Operation;
      Result    : out Delete_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "DeleteObject has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Exact status/code pairs are the S3 wire authority for definite batch
   --  non-acceptance. A validated 200 means processing completed, but its
   --  per-entry Deleted/Error members remain the only entry-level result.
   function Normalize_Delete_Objects_Response
     (Value     : Low_Level.Delete_Objects_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Delete_Objects_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Delete_Objects_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive_Rejection : constant Boolean :=
        (Value.Status = 400
         and then Code in
           "BadDigest" | "EntityTooLarge" | "InvalidArgument" |
           "InvalidRequest" | "MalformedXML")
        or else (Value.Status = 401 and then Code = "InvalidAccessKeyId")
        or else (Value.Status = 403 and then Code = "AccessDenied")
        or else (Value.Status = 404 and then Code = "NoSuchBucket")
        or else (Value.Status = 501 and then Code = "NotImplemented");
      Retryable_Response : constant Boolean :=
        (Value.Status = 409 and then Code = "OperationAborted")
        or else (Value.Status = 429 and then Code = "SlowDown")
        or else (Value.Status = 500 and then Code = "InternalError")
        or else (Value.Status = 502 and then Code = "BadGateway")
        or else (Value.Status = 503 and then Code = "SlowDown")
        or else (Value.Status = 504 and then Code = "RequestTimeout");
      Failure : constant Failure_Reason :=
        (if Value.Kind = Low_Level.Objects_Deleted then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif Value.Status in 400 | 501 and then Conclusive_Rejection
         then Invalid_Request
         elsif Retryable_Response
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind        => Delete_Objects_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Batch_Outcome_Unknown
            elsif Value.Kind = Low_Level.Objects_Deleted
            then Batch_Processed
            elsif Conclusive_Rejection
            then Batch_Definitely_Not_Processed
            else Batch_Outcome_Unknown),
         Failure     =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            else Failure),
         Admission   => Admission,
         Response    => Value);
   end Normalize_Delete_Objects_Response;

   function Normalize_Delete_Objects_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Objects_Result is
   begin
      return
        (Kind        => Delete_Objects_Exchange_Failed,
         Disposition =>
           (if Kind = HTTP_Client.Cancelled
              and then Admission = HTTP_Client.Not_Admitted
            then Batch_Cancelled_Before_Admission
            elsif Admission = HTTP_Client.Not_Admitted
            then Batch_Definitely_Not_Processed
            else Batch_Outcome_Unknown),
         Failure     =>
           (if Kind = HTTP_Client.Response_Body_Too_Large
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Objects_Failure;

   overriding function Declared_Length
     (Item : Delete_Objects_Operation) return HTTP_Client.Body_Length is
   begin
      return HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Item.Prepared)));
   end Declared_Length;

   overriding procedure Read_Now
     (Item   : in out Delete_Objects_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural :=
        Low.Owned_Payload_Length (Item.Prepared);
      Count : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Item.Source_Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Item.Prepared, Item.Source_Position + Offset + 1)));
      end loop;
      Item.Source_Position := Item.Source_Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Objects_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Delete_Objects_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Delete_Objects_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "DeleteObjects response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Delete_Objects_Child
     (Item : in out Delete_Objects_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Delete_Objects_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Delete_Objects_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Delete_Objects_Response
              (Low_Level.Decode_Delete_Objects_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Delete_Objects_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Objects_Child;

   overriding procedure Drive
     (Item : in out Delete_Objects_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Delete_Objects
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Objects_Child (Item);
      else
         raise Program_Error with "invalid DeleteObjects driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Delete_Objects_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Delete_Objects_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Objects
     (Operation : in out Delete_Objects_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "DeleteObjects restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Delete_Objects
        (Origin, Style, Bucket, Request, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained DeleteObjects response bytes use
        --  the maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Objects;

   function Delete_Objects
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Objects_Operation is
   begin
      return Result : Delete_Objects_Operation (Set, Client, Token) do
         Start_Delete_Objects
           (Result, Client, Origin, Bucket, Request, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Delete_Objects;

   procedure Finish
     (Operation : in out Delete_Objects_Operation;
      Result    : out Delete_Objects_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "DeleteObjects has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Project multipart-initiation certainty from exact modeled S3
   --  status/code pairs. A complete response alone is not conclusive unless
   --  the success identity or rejection semantics validate.
   function Normalize_List_Object_Versions_Response
     (Value     : Low_Level.List_Object_Versions_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Object_Versions_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => List_Object_Versions_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Object_Versions_Response;

   function Normalize_List_Object_Versions_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Object_Versions_Result is
   begin
      return
        (Kind        => List_Object_Versions_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Object_Versions_Failure;

   overriding procedure Write
     (Item : in out List_Object_Versions_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListObjectVersions response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Object_Versions_Child
     (Item : in out List_Object_Versions_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Object_Versions_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Object_Versions_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Object_Versions_Response
              (Low_Level.Decode_List_Object_Versions_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Object_Versions_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Object_Versions_Child;

   overriding procedure Drive
     (Item : in out List_Object_Versions_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.List_Object_Versions
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Object_Versions_Child (Item);
      else
         raise Program_Error with "invalid ListObjectVersions driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Object_Versions_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Object_Versions_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Object_Versions
     (Operation : in out List_Object_Versions_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListObjectVersions restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Object_Versions
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained version-listing bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Object_Versions;

   function List_Versions_Page
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Object_Versions_Operation is
   begin
      return Result : List_Object_Versions_Operation (Set, Client, Token) do
         Start_List_Object_Versions
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end List_Versions_Page;

   procedure Finish
     (Operation : in out List_Object_Versions_Operation;
      Result    : out List_Object_Versions_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "ListObjectVersions has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only GetObjectAttributes
   --  attempt; it does not authorize retry.
   function Normalize_Get_Object_Attributes_Response
     (Value     : Low_Level.Get_Object_Attributes_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Object_Attributes_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Object_Attributes_Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Object_Attributes_Found
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
         then Not_Found
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Get_Object_Attributes_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Get_Object_Attributes_Response;

   function Normalize_Get_Object_Attributes_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Object_Attributes_Result is
   begin
      return
        (Kind        => Get_Object_Attributes_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Get_Object_Attributes_Failure;

   overriding procedure Write
     (Item : in out Get_Object_Attributes_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "GetObjectAttributes response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_Get_Object_Attributes_Child
     (Item : in out Get_Object_Attributes_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Get_Object_Attributes_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Get_Object_Attributes_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Get_Object_Attributes_Response
              (Low_Level.Decode_Get_Object_Attributes_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Get_Object_Attributes_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Object_Attributes_Child;

   overriding procedure Drive
     (Item : in out Get_Object_Attributes_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object_Attributes
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Object_Attributes_Child (Item);
      else
         raise Program_Error with
           "invalid GetObjectAttributes driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Object_Attributes_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Object_Attributes_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Object_Attributes
     (Operation : in out Get_Object_Attributes_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "GetObjectAttributes restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Get_Object_Attributes
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained attribute bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Object_Attributes;

   function Get_Attributes
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return Get_Object_Attributes_Operation is
   begin
      return Result : Get_Object_Attributes_Operation (Set, Client, Token) do
         Start_Get_Object_Attributes
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Get_Attributes;

   procedure Finish
     (Operation : in out Get_Object_Attributes_Operation;
      Result    : out Get_Object_Attributes_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "GetObjectAttributes has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListObjects v1 attempt; it
   --  does not authorize retry or imply a shared snapshot with a later page.
   function Normalize_List_Objects_Response
     (Value     : Low_Level.List_Objects_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Objects_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => List_Objects_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Objects_Response;

   function Normalize_List_Objects_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Objects_Result is
   begin
      return
        (Kind        => List_Objects_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Objects_Failure;

   overriding procedure Write
     (Item : in out List_Objects_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListObjects response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Objects_Child
     (Item : in out List_Objects_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Objects_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Objects_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Objects_Response
              (Low_Level.Decode_List_Objects_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Objects_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Objects_Child;

   overriding procedure Drive
     (Item : in out List_Objects_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.List_Objects
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Objects_Child (Item);
      else
         raise Program_Error with "invalid ListObjects driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Objects_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Objects_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Objects
     (Operation : in out List_Objects_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListObjects restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Objects
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained ListObjects bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Objects;

   function List_V1_Page
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_Operation is
   begin
      return Result : List_Objects_Operation (Set, Client, Token) do
         Start_List_Objects
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end List_V1_Page;

   procedure Finish
     (Operation : in out List_Objects_Operation;
      Result    : out List_Objects_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "ListObjects has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  S3 service status/code pairs below are externally modeled response
   --  values. The mapping classifies one read-only ListBuckets attempt; it
   --  does not authorize retry or imply a shared snapshot with a later page.
   function Normalize_List_Objects_V2_Response
     (Value     : Low_Level.List_Objects_V2_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return List_Objects_V2_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Rejected
         then US.To_String (Value.Error.Code) else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Listed
         then No_Failure
         elsif Value.Status = 400
           and then Code in "InvalidArgument" | "InvalidRequest"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404 and then Code = "NoSuchBucket"
         then Not_Found
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => List_Objects_V2_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_List_Objects_V2_Response;

   function Normalize_List_Objects_V2_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return List_Objects_V2_Result is
   begin
      return
        (Kind        => List_Objects_V2_Exchange_Failed,
         Failure     => Failed_Reason (Kind),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_List_Objects_V2_Failure;

   overriding procedure Write
     (Item : in out List_Objects_V2_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) >
        Item.Response_Limit - Flyology.Bytes.Length (Item.Response_Data)
      then
         raise Response_Limit_Exceeded with
           "ListObjectsV2 response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Item.Response_Data, Data);
   end Write;

   procedure Complete_List_Objects_V2_Child
     (Item : in out List_Objects_V2_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_List_Objects_V2_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_List_Objects_V2_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_List_Objects_V2_Response
              (Low_Level.Decode_List_Objects_V2_Complete_Response
                 (Response,
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  Item.Prepared),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_List_Objects_V2_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_List_Objects_V2_Child;

   overriding procedure Drive
     (Item : in out List_Objects_V2_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.List_Objects_V2
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_List_Objects_V2_Child (Item);
      else
         raise Program_Error with "invalid ListObjectsV2 driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out List_Objects_V2_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out List_Objects_V2_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_List_Objects_V2
     (Operation : in out List_Objects_V2_Operation;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "ListObjectsV2 restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_List_Objects_V2
        (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        --  Derived resource bound: retained ListObjectsV2 bytes use the
        --  maintained limit of the S3 XML decoder that consumes them.
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_List_Objects_V2;

   function List_Page
     (Set      : not null access Operations.Completion_Set'Class;
      Client   : not null access HTTP_Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : HTTP_Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null)
      return List_Objects_V2_Operation is
   begin
      return Result : List_Objects_V2_Operation (Set, Client, Token) do
         Start_List_Objects_V2
           (Result, Client, Origin, Bucket, Parameters, Identity, Deadline,
            Region, Style, Token);
      end return;
   end List_Page;

   procedure Finish
     (Operation : in out List_Objects_V2_Operation;
      Result    : out List_Objects_V2_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "ListObjectsV2 has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure Append_Object_Lock_Response
     (Target : in out Flyology.Bytes.Unbounded_Bytes;
      Limit  : Natural;
      Data   : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) > Limit - Flyology.Bytes.Length (Target) then
         raise Response_Limit_Exceeded with
           "Object Lock response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Target, Data);
   end Append_Object_Lock_Response;

   --  These status/code pairs are the modeled conclusive Object Lock
   --  rejections. Retryable or unknown provider failures remain ambiguous.
   function Conclusive_Object_Lock_Rejection
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 400
       and then Code in "BadDigest" | "InvalidArgument" | "InvalidDigest" |
         "InvalidRequest" | "MalformedXML" |
         "XAmzContentSHA256Mismatch")
      or else (Status = 401 and then Code = "InvalidAccessKeyId")
      or else (Status = 403 and then Code = "AccessDenied")
      or else (Status = 404
        and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion")
      or else (Status = 501 and then Code = "NotImplemented"));

   function Object_Lock_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 401 and then Code = "InvalidAccessKeyId"
      then Authentication_Failed
      elsif Status = 403 and then Code = "AccessDenied"
      then Authorization_Failed
      elsif Status = 404
        and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
      then Not_Found
      elsif Conclusive_Object_Lock_Rejection (Status, Code)
      then Invalid_Request
      elsif (Status = 409 and then Code = "OperationAborted")
        or else (Status = 429 and then Code = "SlowDown")
        or else (Status = 500 and then Code = "InternalError")
        or else (Status = 502 and then Code = "BadGateway")
        or else (Status = 503 and then Code = "SlowDown")
        or else (Status = 504 and then Code = "RequestTimeout")
      then Unavailable_Or_Retryable
      else Corrupt_Or_Invalid_Response);

   --  Exact status/code pairs are the maintained S3 GetObjectAcl error
   --  surface. This read-only classification authorizes no mutation or retry.
   function Normalize_Get_Object_ACL_Response
     (Value     : Low_Level.Get_Object_ACL_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Object_ACL_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Object_ACL_Rejected
         then US.To_String (Value.Error.Code)
         else "");
      Failure : constant Failure_Reason :=
        (if Admission /= HTTP_Client.Response_Observed
         then Corrupt_Or_Invalid_Response
         elsif Value.Kind = Low_Level.Object_ACL_Found
         then No_Failure
         elsif Value.Status = 401 and then Code = "InvalidAccessKeyId"
         then Authentication_Failed
         elsif Value.Status = 403 and then Code = "AccessDenied"
         then Authorization_Failed
         elsif Value.Status = 404
           and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
         then Not_Found
         elsif Value.Status = 400
           and then Code in
             "InvalidArgument" | "InvalidBucketName" | "InvalidRequest"
               | "InvalidVersionId"
         then Invalid_Request
         elsif Value.Status = 501 and then Code = "NotImplemented"
         then Invalid_Request
         elsif (Value.Status = 409 and then Code = "OperationAborted")
           or else (Value.Status = 429 and then Code = "SlowDown")
           or else (Value.Status = 500 and then Code = "InternalError")
           or else (Value.Status = 502 and then Code = "BadGateway")
           or else (Value.Status = 503 and then Code = "SlowDown")
           or else (Value.Status = 504 and then Code = "RequestTimeout")
         then Unavailable_Or_Retryable
         else Corrupt_Or_Invalid_Response);
   begin
      return
        (Kind      => Get_Object_ACL_Response_Available,
         Failure   => Failure,
         Admission => Admission,
         Response  => Value);
   end Normalize_Get_Object_ACL_Response;

   function Normalize_Get_Object_ACL_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Object_ACL_Result is
   begin
      return
        (Kind        => Get_Object_ACL_Exchange_Failed,
         Failure     =>
           (if Kind
               in HTTP_Client.Response_Invalid
                | HTTP_Client.Response_Body_Too_Large
                | HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission   => Admission,
         HTTP_Result => Kind,
         HTTP_Phase  => Phase,
         Detail      => US.To_Unbounded_String (Detail));
   end Normalize_Get_Object_ACL_Failure;

   overriding procedure Write
     (Item : in out Get_Object_ACL_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Object_Lock_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Get_Object_ACL_Child
     (Item : in out Get_Object_ACL_Operation)
   is
      Admission   : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response    : HTTP_Client.Response;

      function Singleton_Header (Name : String) return String is
         Count : constant Natural := HTTP_Client.Header_Count (Response, Name);
      begin
         if Count > 1 then
            raise Low_Level.Invalid_Response with
              "duplicate GetObjectAcl response header";
         elsif Count = 0 then
            return "";
         end if;
         declare
            Value : constant String := HTTP_Client.Header (Response, Name);
         begin
            if Value'Length = 0 then
               raise Low_Level.Invalid_Response with
                 "empty GetObjectAcl response header";
            end if;
            return Value;
         end;
      end Singleton_Header;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result :=
              Normalize_Get_Object_ACL_Failure
                (HTTP_Client.Response_Sink_Failed,
                 Admission,
                 HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result :=
           Normalize_Get_Object_ACL_Failure
             (HTTP_Client.Kind (HTTP_Result),
              HTTP_Client.Certainty (HTTP_Result),
              HTTP_Client.Phase (HTTP_Result),
              HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result :=
              Normalize_Get_Object_ACL_Response
                (Low_Level.Decode_Get_Object_ACL_Response
                   (HTTP_Client.Status (Response),
                    Flyology.Bytes.To_Byte_String (Item.Response_Data),
                    Singleton_Header ("x-amz-request-charged"),
                    Singleton_Header ("x-amz-request-id"),
                    Singleton_Header ("x-amz-id-2"),
                    Item.Limits),
                 HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result :=
                 Normalize_Get_Object_ACL_Failure
                   (HTTP_Client.Response_Invalid,
                    HTTP_Client.Certainty (HTTP_Result),
                    HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Object_ACL_Child;

   overriding procedure Drive
     (Item  : in out Get_Object_ACL_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object_ACL
           (Item.HTTP, Item.Prepared'Access, Item'Access, Item.Deadline,
            Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Object_ACL_Child (Item);
      else
         raise Program_Error with "invalid GetObjectAcl driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Object_ACL_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others =>
         null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Object_ACL_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others =>
            null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Object_ACL
     (Operation  : in out Get_Object_ACL_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "GetObjectAcl restart changed a retained owner";
      end if;
      Operation.Prepared :=
        Low_Level.Prepare_Get_Object_ACL
          (Origin, Style, Bucket, Key, Parameters, Identity, Region,
           Timestamp);
      Operation.Deadline := Deadline;
      Operation.Limits := Limits;
      Flyology.Bytes.Clear (Operation.Response_Data);
      --  The caller-selected XML document limit bounds the complete ACL or
      --  structured S3 error; no independent response policy is introduced.
      Operation.Response_Limit := Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Object_ACL;

   function Get_ACL
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Object_ACL_Operation is
   begin
      return Result : Get_Object_ACL_Operation (Set, Client, Token) do
         Start_Get_Object_ACL
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Limits, Token);
      end return;
   end Get_ACL;

   procedure Finish
     (Operation : in out Get_Object_ACL_Operation;
      Result    : out Get_Object_ACL_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetObjectAcl has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Get_Legal_Hold_Response
     (Value     : Low_Level.Get_Object_Legal_Hold_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Legal_Hold_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Object_Legal_Hold_Rejected
         then US.To_String (Value.Error.Code) else "");
   begin
      return
        (Kind => Get_Legal_Hold_Response_Available,
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Legal_Hold_Found
            then No_Failure
            else Object_Lock_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Get_Legal_Hold_Response;

   function Normalize_Get_Legal_Hold_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Legal_Hold_Result is
   begin
      return
        (Kind => Get_Legal_Hold_Exchange_Failed,
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Get_Legal_Hold_Failure;

   overriding procedure Write
     (Item : in out Get_Legal_Hold_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Object_Lock_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Get_Legal_Hold_Child
     (Item : in out Get_Legal_Hold_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Get_Legal_Hold_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Get_Legal_Hold_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Get_Legal_Hold_Response
              (Low_Level.Decode_Get_Object_Legal_Hold_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Get_Legal_Hold_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Legal_Hold_Child;

   overriding procedure Drive
     (Item : in out Get_Legal_Hold_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object_Legal_Hold
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Legal_Hold_Child (Item);
      else
         raise Program_Error with "invalid GetObjectLegalHold driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Legal_Hold_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Legal_Hold_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Legal_Hold
     (Operation  : in out Get_Legal_Hold_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Token      : access Flyology.Cancellation.Token) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "GetObjectLegalHold restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Get_Object_Legal_Hold
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Legal_Hold;

   function Get_Legal_Hold
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Legal_Hold_Operation is
   begin
      return Result : Get_Legal_Hold_Operation (Set, Client, Token) do
         Start_Get_Legal_Hold
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Get_Legal_Hold;

   procedure Finish
     (Operation : in out Get_Legal_Hold_Operation;
      Result    : out Get_Legal_Hold_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetObjectLegalHold has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   --  Shared reader for exact body bytes copied into Prepared_Request during
   --  signing.  The owned copy permits an operation to outlive initiation,
   --  but does not make a mutation replayable after possible admission.
   function Owned_Prepared_Length
     (Prepared : Low_Level.Prepared_Request) return HTTP_Client.Body_Length is
     (HTTP_Client.Known_Length
        (HTTP_Client.Body_Size
           (Low.Owned_Payload_Length (Prepared))));

   procedure Read_Owned_Prepared_Source
     (Prepared : Low_Level.Prepared_Request;
      Position : in out Natural;
      Data     : out Ada.Streams.Stream_Element_Array;
      Last     : out Ada.Streams.Stream_Element_Offset;
      Result   : out HTTP_Client.Source_Step_Kind)
   is
      Length : constant Natural :=
        Low.Owned_Payload_Length (Prepared);
      Count : constant Natural :=
        Natural'Min (Natural (Data'Length), Length - Position);
   begin
      Data := (others => 0);
      Last := Data'First - 1;
      if Count = 0 then
         Result := HTTP_Client.Source_Finished;
         return;
      end if;
      for Offset in 0 .. Count - 1 loop
         Data (Data'First + Ada.Streams.Stream_Element_Offset (Offset)) :=
           Ada.Streams.Stream_Element
             (Character'Pos
                (Low.Owned_Payload_Element
                   (Prepared, Position + Offset + 1)));
      end loop;
      Position := Position + Count;
      Last := Data'First + Ada.Streams.Stream_Element_Offset (Count) - 1;
      Result := HTTP_Client.Source_Progress;
   end Read_Owned_Prepared_Source;

   function Failed_Legal_Hold_Mutation_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Legal_Hold_Mutation_Disposition is
     (if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then Legal_Hold_Mutation_Cancelled_Before_Admission
      elsif Admission = HTTP_Client.Not_Admitted
      then Legal_Hold_Mutation_Definitely_Not_Applied
      else Legal_Hold_Mutation_Outcome_Unknown);

   function Normalize_Put_Legal_Hold_Response
     (Value     : Low_Level.Put_Object_Legal_Hold_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Put_Legal_Hold_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Object_Legal_Hold_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive : constant Boolean :=
        Conclusive_Object_Lock_Rejection (Value.Status, Code);
   begin
      return
        (Kind => Put_Legal_Hold_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Legal_Hold_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Object_Legal_Hold_Updated
            then Legal_Hold_Mutation_Completed
            elsif Conclusive
            then Legal_Hold_Mutation_Definitely_Not_Applied
            else Legal_Hold_Mutation_Outcome_Unknown),
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Legal_Hold_Updated
            then No_Failure
            else Object_Lock_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Put_Legal_Hold_Response;

   function Normalize_Put_Legal_Hold_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Put_Legal_Hold_Result is
   begin
      return
        (Kind => Put_Legal_Hold_Exchange_Failed,
         Disposition =>
           Failed_Legal_Hold_Mutation_Disposition (Kind, Admission),
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Put_Legal_Hold_Failure;

   overriding function Declared_Length
     (Item : Put_Legal_Hold_Operation) return HTTP_Client.Body_Length is
     (Owned_Prepared_Length (Item.Prepared));

   overriding procedure Read_Now
     (Item   : in out Put_Legal_Hold_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      Read_Owned_Prepared_Source
        (Item.Prepared, Item.Source_Position, Data, Last, Result);
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Put_Legal_Hold_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
      pragma Unreferenced (Item, Required);
   begin
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Put_Legal_Hold_Operation) is
   begin
      Item.Source_Position := Low.Owned_Payload_Length (Item.Prepared);
   end Release_Source;

   overriding procedure Write
     (Item : in out Put_Legal_Hold_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Object_Lock_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Put_Legal_Hold_Child
     (Item : in out Put_Legal_Hold_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Put_Legal_Hold_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Put_Legal_Hold_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Put_Legal_Hold_Response
              (Low_Level.Decode_Put_Object_Legal_Hold_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  (Request_Charged => US.To_Unbounded_String
                     (HTTP_Client.Header
                        (Response, "x-amz-request-charged"))),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Legal_Hold_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Put_Legal_Hold_Child;

   overriding procedure Drive
     (Item : in out Put_Legal_Hold_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Object_Legal_Hold
           (Item.HTTP, Item.Prepared'Access, Item'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Put_Legal_Hold_Child (Item);
      else
         raise Program_Error with "invalid PutObjectLegalHold driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Put_Legal_Hold_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Put_Legal_Hold_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put_Legal_Hold
     (Operation  : in out Put_Legal_Hold_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Token      : access Flyology.Cancellation.Token) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "PutObjectLegalHold restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Put_Object_Legal_Hold
        (Origin, Style, Bucket, Key, Value, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Put_Legal_Hold;

   function Put_Legal_Hold
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Legal_Hold_Operation is
   begin
      return Result : Put_Legal_Hold_Operation (Set, Client, Token) do
         Start_Put_Legal_Hold
           (Result, Client, Origin, Bucket, Key, Value, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Put_Legal_Hold;

   procedure Finish
     (Operation : in out Put_Legal_Hold_Operation;
      Result    : out Put_Legal_Hold_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutObjectLegalHold has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Get_Retention_Response
     (Value     : Low_Level.Get_Object_Retention_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Retention_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Get_Object_Retention_Rejected
         then US.To_String (Value.Error.Code) else "");
   begin
      return
        (Kind => Get_Retention_Response_Available,
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Retention_Found
            then No_Failure
            else Object_Lock_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Get_Retention_Response;

   function Normalize_Get_Retention_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Retention_Result is
   begin
      return
        (Kind => Get_Retention_Exchange_Failed,
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Get_Retention_Failure;

   overriding procedure Write
     (Item : in out Get_Retention_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Object_Lock_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Get_Retention_Child
     (Item : in out Get_Retention_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Get_Retention_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Get_Retention_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Get_Retention_Response
              (Low_Level.Decode_Get_Object_Retention_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Get_Retention_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Retention_Child;

   overriding procedure Drive
     (Item : in out Get_Retention_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object_Retention
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Retention_Child (Item);
      else
         raise Program_Error with "invalid GetObjectRetention driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Retention_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Retention_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Retention
     (Operation  : in out Get_Retention_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Token      : access Flyology.Cancellation.Token) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "GetObjectRetention restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Get_Object_Retention
        (Origin, Style, Bucket, Key, Parameters, Identity, Region, Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Retention;

   function Get_Retention
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Retention_Operation is
   begin
      return Result : Get_Retention_Operation (Set, Client, Token) do
         Start_Get_Retention
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Get_Retention;

   procedure Finish
     (Operation : in out Get_Retention_Operation;
      Result    : out Get_Retention_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetObjectRetention has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Failed_Retention_Mutation_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Retention_Mutation_Disposition is
     (if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then Retention_Mutation_Cancelled_Before_Admission
      elsif Admission = HTTP_Client.Not_Admitted
      then Retention_Mutation_Definitely_Not_Applied
      else Retention_Mutation_Outcome_Unknown);

   function Normalize_Put_Retention_Response
     (Value     : Low_Level.Put_Object_Retention_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Put_Retention_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Put_Object_Retention_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive : constant Boolean :=
        Conclusive_Object_Lock_Rejection (Value.Status, Code);
   begin
      return
        (Kind => Put_Retention_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Retention_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Object_Retention_Updated
            then Retention_Mutation_Completed
            elsif Conclusive
            then Retention_Mutation_Definitely_Not_Applied
            else Retention_Mutation_Outcome_Unknown),
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Object_Retention_Updated
            then No_Failure
            else Object_Lock_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Put_Retention_Response;

   function Normalize_Put_Retention_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Put_Retention_Result is
   begin
      return
        (Kind => Put_Retention_Exchange_Failed,
         Disposition =>
           Failed_Retention_Mutation_Disposition (Kind, Admission),
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Put_Retention_Failure;

   overriding function Declared_Length
     (Item : Put_Retention_Operation) return HTTP_Client.Body_Length is
     (Owned_Prepared_Length (Item.Prepared));

   overriding procedure Read_Now
     (Item   : in out Put_Retention_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      Read_Owned_Prepared_Source
        (Item.Prepared, Item.Source_Position, Data, Last, Result);
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Put_Retention_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
      pragma Unreferenced (Item, Required);
   begin
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Put_Retention_Operation) is
   begin
      Item.Source_Position := Low.Owned_Payload_Length (Item.Prepared);
   end Release_Source;

   overriding procedure Write
     (Item : in out Put_Retention_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Object_Lock_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Put_Retention_Child
     (Item : in out Put_Retention_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Put_Retention_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Put_Retention_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Put_Retention_Response
              (Low_Level.Decode_Put_Object_Retention_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  (Request_Charged => US.To_Unbounded_String
                     (HTTP_Client.Header
                        (Response, "x-amz-request-charged"))),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Retention_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Put_Retention_Child;

   overriding procedure Drive
     (Item : in out Put_Retention_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Object_Retention
           (Item.HTTP, Item.Prepared'Access, Item'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Put_Retention_Child (Item);
      else
         raise Program_Error with "invalid PutObjectRetention driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Put_Retention_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Put_Retention_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put_Retention
     (Operation  : in out Put_Retention_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Token      : access Flyology.Cancellation.Token) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "PutObjectRetention restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Put_Object_Retention
        (Origin, Style, Bucket, Key, Value, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Put_Retention;

   function Put_Retention
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : Flyology.Object_Storage.S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Retention_Operation is
   begin
      return Result : Put_Retention_Operation (Set, Client, Token) do
         Start_Put_Retention
           (Result, Client, Origin, Bucket, Key, Value, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Put_Retention;

   procedure Finish
     (Operation : in out Put_Retention_Operation;
      Result    : out Put_Retention_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutObjectRetention has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure Append_Tagging_Response
     (Target : in out Flyology.Bytes.Unbounded_Bytes;
      Limit  : Natural;
      Data   : Ada.Streams.Stream_Element_Array) is
   begin
      if Natural (Data'Length) > Limit - Flyology.Bytes.Length (Target) then
         raise Response_Limit_Exceeded with
           "tagging response exceeds the S3 XML limit";
      end if;
      Flyology.Bytes.Append (Target, Data);
   end Append_Tagging_Response;
   --  These exact status/code pairs are the maintained S3 object-tagging
   --  response contract. Unpaired or unknown responses remain ambiguous.
   function Conclusive_Object_Tag_Rejection
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 400
       and then Code in "BadDigest" | "InvalidArgument" | "InvalidDigest" |
         "InvalidRequest" | "InvalidTag" | "MalformedXML" |
         "XAmzContentSHA256Mismatch")
      or else (Status = 401 and then Code = "InvalidAccessKeyId")
      or else (Status = 403 and then Code = "AccessDenied")
      or else (Status = 404
        and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion")
      or else (Status = 501 and then Code = "NotImplemented"));

   function Retryable_Object_Tag_Response
     (Status : Flyology.HTTP.Status_Code; Code : String) return Boolean is
     ((Status = 409 and then Code = "OperationAborted")
      or else (Status = 429 and then Code = "SlowDown")
      or else (Status = 500 and then Code = "InternalError")
      or else (Status = 502 and then Code = "BadGateway")
      or else (Status = 503 and then Code = "SlowDown")
      or else (Status = 504 and then Code = "RequestTimeout"));

   function Object_Tag_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 401 and then Code = "InvalidAccessKeyId"
      then Authentication_Failed
      elsif Status = 403 and then Code = "AccessDenied"
      then Authorization_Failed
      elsif Status = 404
        and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
      then Not_Found
      elsif Conclusive_Object_Tag_Rejection (Status, Code)
      then Invalid_Request
      elsif Retryable_Object_Tag_Response (Status, Code)
      then Unavailable_Or_Retryable
      else Corrupt_Or_Invalid_Response);

   function Object_Tag_Read_Response_Failure
     (Status : Flyology.HTTP.Status_Code; Code : String)
      return Failure_Reason is
     (if Status = 404
       and then Code in "NoSuchBucket" | "NoSuchKey" | "NoSuchVersion"
      then Not_Found
      else Object_Tag_Response_Failure (Status, Code));

   function Failed_Object_Tag_Mutation_Disposition
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty)
      return Object_Tag_Mutation_Disposition is
     (if Kind = HTTP_Client.Cancelled
        and then Admission = HTTP_Client.Not_Admitted
      then Object_Tag_Mutation_Cancelled_Before_Admission
      elsif Admission = HTTP_Client.Not_Admitted
      then Object_Tag_Mutation_Definitely_Not_Applied
      else Object_Tag_Mutation_Outcome_Unknown);

   function Normalize_Put_Object_Tagging_Response
     (Value     : Low_Level.Object_Tagging_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Put_Object_Tagging_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Object_Tagging_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive : constant Boolean :=
        Conclusive_Object_Tag_Rejection (Value.Status, Code);
   begin
      return
        (Kind => Put_Object_Tagging_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Object_Tag_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Tags_Put
            then Object_Tag_Mutation_Completed
            elsif Conclusive
            then Object_Tag_Mutation_Definitely_Not_Applied
            else Object_Tag_Mutation_Outcome_Unknown),
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Tags_Put
            then No_Failure
            else Object_Tag_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Put_Object_Tagging_Response;

   function Normalize_Put_Object_Tagging_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Put_Object_Tagging_Result is
   begin
      return
        (Kind => Put_Object_Tagging_Exchange_Failed,
         Disposition =>
           Failed_Object_Tag_Mutation_Disposition (Kind, Admission),
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Put_Object_Tagging_Failure;

   overriding function Declared_Length
     (Item : Put_Object_Tagging_Operation) return HTTP_Client.Body_Length is
     (Owned_Prepared_Length (Item.Prepared));

   overriding procedure Read_Now
     (Item   : in out Put_Object_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      Read_Owned_Prepared_Source
        (Item.Prepared, Item.Source_Position, Data, Last, Result);
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Put_Object_Tagging_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Put_Object_Tagging_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Put_Object_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Tagging_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Put_Object_Tagging_Child
     (Item : in out Put_Object_Tagging_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Put_Object_Tagging_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Put_Object_Tagging_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Put_Object_Tagging_Response
              (Low_Level.Decode_Put_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  HTTP_Client.Header (Response, "x-amz-version-id"),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Put_Object_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Put_Object_Tagging_Child;

   overriding procedure Drive
     (Item : in out Put_Object_Tagging_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Put_Object_Tagging
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Put_Object_Tagging_Child (Item);
      else
         raise Program_Error with "invalid PutObjectTagging driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Put_Object_Tagging_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Put_Object_Tagging_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Put_Object_Tagging
     (Operation  : in out Put_Object_Tagging_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Tags       : Flyology.Object_Storage.Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "PutObjectTagging restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Put_Object_Tagging
        (Origin, Style, Bucket, Key, Tags, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Put_Object_Tagging;

   function Put_Tags
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Tags       : Flyology.Object_Storage.Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Put_Object_Tagging_Operation is
   begin
      return Result : Put_Object_Tagging_Operation (Set, Client, Token) do
         Start_Put_Object_Tagging
           (Result, Client, Origin, Bucket, Key, Tags, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Put_Tags;

   procedure Finish
     (Operation : in out Put_Object_Tagging_Operation;
      Result    : out Put_Object_Tagging_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "PutObjectTagging has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Get_Object_Tagging_Response
     (Value     : Low_Level.Object_Tagging_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Get_Object_Tagging_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Object_Tagging_Rejected
         then US.To_String (Value.Error.Code) else "");
   begin
      return
        (Kind => Get_Object_Tagging_Response_Available,
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Tags_Gotten
            then No_Failure
            else Object_Tag_Read_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Get_Object_Tagging_Response;

   function Normalize_Get_Object_Tagging_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Get_Object_Tagging_Result is
   begin
      return
        (Kind => Get_Object_Tagging_Exchange_Failed,
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Get_Object_Tagging_Failure;

   overriding procedure Write
     (Item : in out Get_Object_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Tagging_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Get_Object_Tagging_Child
     (Item : in out Get_Object_Tagging_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Get_Object_Tagging_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Get_Object_Tagging_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Get_Object_Tagging_Response
              (Low_Level.Decode_Get_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  HTTP_Client.Header (Response, "x-amz-version-id"),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Get_Object_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Get_Object_Tagging_Child;

   overriding procedure Drive
     (Item : in out Get_Object_Tagging_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Get_Object_Tagging
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Get_Object_Tagging_Child (Item);
      else
         raise Program_Error with "invalid GetObjectTagging driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Get_Object_Tagging_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Get_Object_Tagging_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Get_Object_Tagging
     (Operation  : in out Get_Object_Tagging_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "GetObjectTagging restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Get_Object_Tagging
        (Origin, Style, Bucket, Key, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit := Natural'Min
        (Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes,
         Flyology.Object_Storage.S3.Tagging.Maximum_Document_Bytes);
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Get_Object_Tagging;

   function Get_Tags
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Get_Object_Tagging_Operation is
   begin
      return Result : Get_Object_Tagging_Operation (Set, Client, Token) do
         Start_Get_Object_Tagging
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Get_Tags;

   procedure Finish
     (Operation : in out Get_Object_Tagging_Operation;
      Result    : out Get_Object_Tagging_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with "GetObjectTagging has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   function Normalize_Delete_Object_Tagging_Response
     (Value     : Low_Level.Object_Tagging_Outcome;
      Admission : HTTP_Client.Admission_Certainty)
      return Delete_Object_Tagging_Result
   is
      Code : constant String :=
        (if Value.Kind = Low_Level.Object_Tagging_Rejected
         then US.To_String (Value.Error.Code) else "");
      Conclusive : constant Boolean :=
        Conclusive_Object_Tag_Rejection (Value.Status, Code);
   begin
      return
        (Kind => Delete_Object_Tagging_Response_Available,
         Disposition =>
           (if Admission /= HTTP_Client.Response_Observed
            then Object_Tag_Mutation_Outcome_Unknown
            elsif Value.Kind = Low_Level.Tags_Deleted
            then Object_Tag_Mutation_Completed
            elsif Conclusive
            then Object_Tag_Mutation_Definitely_Not_Applied
            else Object_Tag_Mutation_Outcome_Unknown),
         Failure =>
           (if Admission /= HTTP_Client.Response_Observed
            then Corrupt_Or_Invalid_Response
            elsif Value.Kind = Low_Level.Tags_Deleted
            then No_Failure
            else Object_Tag_Response_Failure (Value.Status, Code)),
         Admission => Admission,
         Response => Value);
   end Normalize_Delete_Object_Tagging_Response;

   function Normalize_Delete_Object_Tagging_Failure
     (Kind      : HTTP_Client.Exchange_Result_Kind;
      Admission : HTTP_Client.Admission_Certainty;
      Phase     : HTTP_Client.Exchange_Phase;
      Detail    : String := "") return Delete_Object_Tagging_Result is
   begin
      return
        (Kind => Delete_Object_Tagging_Exchange_Failed,
         Disposition =>
           Failed_Object_Tag_Mutation_Disposition (Kind, Admission),
         Failure =>
           (if Kind in HTTP_Client.Response_Invalid |
                         HTTP_Client.Response_Body_Too_Large |
                         HTTP_Client.Response_Sink_Failed
            then Corrupt_Or_Invalid_Response
            else Failed_Reason (Kind)),
         Admission => Admission,
         HTTP_Result => Kind,
         HTTP_Phase => Phase,
         Detail => US.To_Unbounded_String (Detail));
   end Normalize_Delete_Object_Tagging_Failure;

   overriding function Declared_Length
     (Item : Delete_Object_Tagging_Operation)
      return HTTP_Client.Body_Length is
     (Owned_Prepared_Length (Item.Prepared));

   overriding procedure Read_Now
     (Item   : in out Delete_Object_Tagging_Operation;
      Data   : out Ada.Streams.Stream_Element_Array;
      Last   : out Ada.Streams.Stream_Element_Offset;
      Result : out HTTP_Client.Source_Step_Kind) is
   begin
      Read_Owned_Prepared_Source
        (Item.Prepared, Item.Source_Position, Data, Last, Result);
   end Read_Now;

   overriding procedure Source_Wait_Source
     (Item       : in out Delete_Object_Tagging_Operation;
      Required   : HTTP_Client.Source_Wait_Kind;
      Descriptor : out Flyology.IO.Descriptor;
      Ready_Now  : out Boolean) is
   begin
      pragma Unreferenced (Item, Required);
      Descriptor := Flyology.IO.Invalid_Descriptor;
      Ready_Now := True;
   end Source_Wait_Source;

   overriding procedure Release_Source
     (Item : in out Delete_Object_Tagging_Operation) is
   begin
      pragma Unreferenced (Item);
      null;
   end Release_Source;

   overriding procedure Write
     (Item : in out Delete_Object_Tagging_Operation;
      Data : Ada.Streams.Stream_Element_Array) is
   begin
      Append_Tagging_Response
        (Item.Response_Data, Item.Response_Limit, Data);
   end Write;

   procedure Complete_Delete_Object_Tagging_Child
     (Item : in out Delete_Object_Tagging_Operation)
   is
      Admission : constant HTTP_Client.Admission_Certainty :=
        HTTP_Client.Admission (Item.Child);
      HTTP_Result : HTTP_Client.Exchange_Result;
      Response : HTTP_Client.Response;
   begin
      begin
         HTTP_Client.Finish (Item.Child, HTTP_Result, Response);
      exception
         when Response_Limit_Exceeded =>
            Operations.Release (Item.Child);
            Item.Final_Result := Normalize_Delete_Object_Tagging_Failure
              (HTTP_Client.Response_Sink_Failed, Admission,
               HTTP_Client.Receiving_Response_Body);
            Low.Clear_Prepared_Request (Item.Prepared);
            Item.Has_Final_Result := True;
            Operation_Drivers.Complete (Item, Operations.Succeeded);
            return;
         when Error : others =>
            if Operations.Id (Item.Child) /= 0
              and then not Operations.Is_Active (Item.Child)
              and then not Operations.Is_Terminal (Item.Child)
            then
               Operations.Release (Item.Child);
            end if;
            Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
            Item.Has_Saved_Error := True;
            if not Operations.Is_Active (Item.Child) then
               Low.Clear_Prepared_Request (Item.Prepared);
            end if;
            Operation_Drivers.Complete (Item, Operations.Failed);
            return;
      end;
      Operations.Release (Item.Child);
      if HTTP_Client.Kind (HTTP_Result) /= HTTP_Client.Response_Complete then
         Item.Final_Result := Normalize_Delete_Object_Tagging_Failure
           (HTTP_Client.Kind (HTTP_Result),
            HTTP_Client.Certainty (HTTP_Result),
            HTTP_Client.Phase (HTTP_Result),
            HTTP_Client.Failure_Detail (HTTP_Result));
      else
         begin
            Item.Final_Result := Normalize_Delete_Object_Tagging_Response
              (Low_Level.Decode_Delete_Object_Tagging_Response
                 (HTTP_Client.Status (Response),
                  Flyology.Bytes.To_Byte_String (Item.Response_Data),
                  HTTP_Client.Header (Response, "x-amz-version-id"),
                  HTTP_Client.Header (Response, "x-amz-request-id"),
                  HTTP_Client.Header (Response, "x-amz-id-2")),
               HTTP_Client.Certainty (HTTP_Result));
         exception
            when Low_Level.Invalid_Response =>
               Item.Final_Result := Normalize_Delete_Object_Tagging_Failure
                 (HTTP_Client.Response_Invalid,
                  HTTP_Client.Certainty (HTTP_Result),
                  HTTP_Client.Phase (HTTP_Result));
         end;
      end if;
      Low.Clear_Prepared_Request (Item.Prepared);
      Item.Has_Final_Result := True;
      Operation_Drivers.Complete (Item, Operations.Succeeded);
   end Complete_Delete_Object_Tagging_Child;

   overriding procedure Drive
     (Item : in out Delete_Object_Tagging_Operation;
      Event : Operations.Driver_Event) is
   begin
      if Event = Operations.Start_Operation then
         Low.Delete_Object_Tagging
           (Item.HTTP, Item.Prepared'Access, Item'Access,
            Item'Access, Item.Deadline, Item.Cancellation, Item.Child);
         Operations.Continue_After (Item, Item.Child);
      elsif Event = Operations.Dependency_Changed
        and then Operations.Is_Terminal (Item.Child)
      then
         Complete_Delete_Object_Tagging_Child (Item);
      else
         raise Program_Error with "invalid DeleteObjectTagging driver event";
      end if;
   exception
      when Error : others =>
         Ada.Exceptions.Save_Occurrence (Item.Saved_Error, Error);
         Item.Has_Saved_Error := True;
         if not Operations.Is_Active (Item.Child) then
            Low.Clear_Prepared_Request (Item.Prepared);
         end if;
         if Operations.Is_Active (Item) then
            Operation_Drivers.Complete (Item, Operations.Failed);
         end if;
   end Drive;

   overriding procedure Request_Cancellation
     (Item : in out Delete_Object_Tagging_Operation) is
   begin
      if Operations.Is_Active (Item.Child) then
         Operations.Cancel (Item.Child);
      end if;
   exception
      when others => null;
   end Request_Cancellation;

   overriding procedure Finalize
     (Item : in out Delete_Object_Tagging_Operation) is
   begin
      begin
         Operations.Finalize (Operations.Operation (Item));
      exception
         when others => null;
      end;
      Low.Clear_Prepared_Request (Item.Prepared);
      Flyology.Bytes.Clear (Item.Response_Data);
   end Finalize;

   procedure Start_Delete_Object_Tagging
     (Operation  : in out Delete_Object_Tagging_Operation;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null) is
   begin
      if Operation.HTTP /= Client or else Operation.Cancellation /= Token then
         raise Program_Error with
           "DeleteObjectTagging restart changed a retained owner";
      end if;
      Operation.Prepared := Low_Level.Prepare_Delete_Object_Tagging
        (Origin, Style, Bucket, Key, Parameters, Identity, Region,
         Timestamp);
      Operation.Deadline := Deadline;
      Operation.Source_Position := 0;
      Flyology.Bytes.Clear (Operation.Response_Data);
      Operation.Response_Limit :=
        Flyology.Object_Storage.S3.XML.Default_Limits.Maximum_Document_Bytes;
      Operation.Has_Final_Result := False;
      Operation.Has_Saved_Error := False;
      Operation_Drivers.Start (Operation);
      begin
         Operations.Drive
           (Operations.Operation'Class (Operation),
            Operations.Start_Operation);
      exception
         when others =>
            if Operations.Is_Active (Operation) then
               Operation_Drivers.Rollback_Start (Operation);
            end if;
            Low.Clear_Prepared_Request (Operation.Prepared);
            raise;
      end;
   end Start_Delete_Object_Tagging;

   function Delete_Tags
     (Set        : not null access Operations.Completion_Set'Class;
      Client     : not null access HTTP_Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : HTTP_Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null)
      return Delete_Object_Tagging_Operation is
   begin
      return Result : Delete_Object_Tagging_Operation (Set, Client, Token) do
         Start_Delete_Object_Tagging
           (Result, Client, Origin, Bucket, Key, Parameters, Identity,
            Deadline, Region, Style, Token);
      end return;
   end Delete_Tags;

   procedure Finish
     (Operation : in out Delete_Object_Tagging_Operation;
      Result    : out Delete_Object_Tagging_Result) is
   begin
      Operations.Consume (Operation);
      Low.Clear_Prepared_Request (Operation.Prepared);
      if Operation.Has_Saved_Error then
         Ada.Exceptions.Raise_Exception
           (Ada.Exceptions.Exception_Identity (Operation.Saved_Error),
            Ada.Exceptions.Exception_Message (Operation.Saved_Error));
      elsif not Operation.Has_Final_Result then
         raise Program_Error with
           "DeleteObjectTagging has no terminal result";
      end if;
      Result := Operation.Final_Result;
   end Finish;

   procedure Put_Object
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Put_Object_Parameters;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Conditional_Put_Operation) is
   begin
      Start_Put_Object
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Payload_Buffer,
         Payload_SHA256,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Put_Object;

   procedure Put_If_Absent
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Conditional_Put_Operation) is
   begin
      Start_Put_If_Absent
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Payload_Buffer,
         Payload_SHA256,
         Identity,
         Deadline,
         Region,
         Style,
         Content_Type,
         Expected_Bucket_Owner,
         Token);
   end Put_If_Absent;

   procedure Put_If_Matches
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Expected_Entity_Tag : String;
      Payload_Buffer : in out Flyology.Buffers.Unique_Buffer;
      Payload_SHA256 : String;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Content_Type : String := "";
      Expected_Bucket_Owner : String := "";
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Conditional_Put_Operation) is
   begin
      Start_Put_If_Matches
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Expected_Entity_Tag,
         Payload_Buffer,
         Payload_SHA256,
         Identity,
         Deadline,
         Region,
         Style,
         Content_Type,
         Expected_Bucket_Owner,
         Token);
   end Put_If_Matches;

   procedure Get_Whole
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Expected_Entity_Tag : String := "";
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Whole_Get_Operation) is
   begin
      Start_Get_Whole
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Destination,
         Identity,
         Deadline,
         Expected_Entity_Tag,
         Version_ID,
         Region,
         Style,
         Expected_Bucket_Owner,
         Request_Payer,
         Checksum_Mode,
         Token);
   end Get_Whole;

   procedure Get_Range
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Requested : Byte_Range;
      Destination : not null access Flyology.Buffers.Unique_Buffer;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Expected_Entity_Tag : String;
      Version_ID : String := "";
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := "";
      Request_Payer : String := "";
      Checksum_Mode : Boolean := False;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Range_Get_Operation) is
   begin
      Start_Get_Range
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Requested,
         Destination,
         Identity,
         Deadline,
         Expected_Entity_Tag,
         Version_ID,
         Region,
         Style,
         Expected_Bucket_Owner,
         Request_Payer,
         Checksum_Mode,
         Token);
   end Get_Range;

   procedure Head_Object
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Head_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Head_Operation) is
   begin
      Start_Head_Object
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Head_Object;

   procedure Delete
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Delete_Object_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Delete_Operation) is
   begin
      Start_Delete_Object
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Delete;

   procedure Delete_Objects
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Request  : S3.Deletions.Delete_Objects_Request;
      Parameters : Low_Level.Delete_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Delete_Objects_Operation) is
   begin
      Start_Delete_Objects
        (Operation,
         Client,
         Origin,
         Bucket,
         Request,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Delete_Objects;

   procedure List_V1_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Objects_Operation) is
   begin
      Start_List_Objects
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end List_V1_Page;

   procedure List_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Objects_V2_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Objects_V2_Operation) is
   begin
      Start_List_Objects_V2
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end List_Page;

   procedure List_Versions_Page
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Parameters : Low_Level.List_Object_Versions_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out List_Object_Versions_Operation) is
   begin
      Start_List_Object_Versions
        (Operation,
         Client,
         Origin,
         Bucket,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end List_Versions_Page;

   procedure Get_Attributes
     (Client   : not null access Flyology.HTTP.Client.Client;
      Origin   : Flyology.HTTP.Origin;
      Bucket   : String;
      Key      : String;
      Parameters : Low_Level.Get_Object_Attributes_Parameters;
      Identity : Low_Level.Credentials;
      Deadline : Flyology.HTTP.Client.Monotonic_Deadline;
      Region   : String := "us-east-1";
      Style    : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token    : access Flyology.Cancellation.Token := null;
      Operation : in out Get_Object_Attributes_Operation) is
   begin
      Start_Get_Object_Attributes
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Get_Attributes;

   procedure Get_ACL
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_ACL_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Limits     : Flyology.Object_Storage.S3.XML.Parse_Limits :=
        Flyology.Object_Storage.S3.XML.Default_Limits;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Object_ACL_Operation) is
   begin
      Start_Get_Object_ACL
        (Operation, Client, Origin, Bucket, Key, Parameters, Identity,
         Deadline, Region, Style, Limits, Token);
   end Get_ACL;

   procedure Get_Legal_Hold
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Legal_Hold_Operation) is
   begin
      Start_Get_Legal_Hold
        (Operation, Client, Origin, Bucket, Key, Parameters, Identity,
         Deadline, Region, Style, Token);
   end Get_Legal_Hold;

   procedure Put_Legal_Hold
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Legal_Hold;
      Parameters : Low_Level.Put_Object_Legal_Hold_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Legal_Hold_Operation) is
   begin
      Start_Put_Legal_Hold
        (Operation, Client, Origin, Bucket, Key, Value, Parameters, Identity,
         Deadline, Region, Style, Token);
   end Put_Legal_Hold;

   procedure Get_Retention
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Retention_Operation) is
   begin
      Start_Get_Retention
        (Operation, Client, Origin, Bucket, Key, Parameters, Identity,
         Deadline, Region, Style, Token);
   end Get_Retention;

   procedure Put_Retention
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Value      : S3.Object_Lock.Retention;
      Parameters : Low_Level.Put_Object_Retention_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Retention_Operation) is
   begin
      Start_Put_Retention
        (Operation, Client, Origin, Bucket, Key, Value, Parameters, Identity,
         Deadline, Region, Style, Token);
   end Put_Retention;

   procedure Put_Tags
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Tags       : Flyology.Object_Storage.Object_Tag_Set;
      Parameters : Low_Level.Put_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Put_Object_Tagging_Operation) is
   begin
      Start_Put_Object_Tagging
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Tags,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Put_Tags;

   procedure Get_Tags
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Get_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Get_Object_Tagging_Operation) is
   begin
      Start_Get_Object_Tagging
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Get_Tags;

   procedure Delete_Tags
     (Client     : not null access Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Key        : String;
      Parameters : Low_Level.Delete_Object_Tagging_Parameters;
      Identity   : Low_Level.Credentials;
      Deadline   : Flyology.HTTP.Client.Monotonic_Deadline;
      Region     : String := "us-east-1";
      Style      : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Token      : access Flyology.Cancellation.Token := null;
      Operation  : in out Delete_Object_Tagging_Operation) is
   begin
      Start_Delete_Object_Tagging
        (Operation,
         Client,
         Origin,
         Bucket,
         Key,
         Parameters,
         Identity,
         Deadline,
         Region,
         Style,
         Token);
   end Delete_Tags;

end Flyology.Object_Storage.Client.Objects;
