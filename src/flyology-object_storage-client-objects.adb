with Ada.Calendar;
with Ada.Calendar.Formatting;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.IMF_Dates;
with Flyology.Object_Storage.S3.Tagging;

package body Flyology.Object_Storage.Client.Objects is

   package US renames Ada.Strings.Unbounded;
   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.Object_Tagging_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;
   use type US.Unbounded_String;

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
      Parameters.Delimiter := US.To_Unbounded_String (Delimiter);
      Parameters.Marker := US.To_Unbounded_String (Marker);
      Parameters.Max_Keys := Maximum;
      Parameters.URL_Encoding := URL_Encoding;
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Include_Restore_Status := Include_Restore_Status;
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_List_Objects
             (Origin, Style, Bucket, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.List_Objects_Outcome :=
           Low_Level.Execute_List_Objects
             (Client, Prepared, Timeout, Token);
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
                    "truncated ListObjects page lacks a continuation marker";
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

      function Result_Checksum
        (Value : Low_Level.Put_Object_Result) return US.Unbounded_String is
      begin
         case Options.Checksum.Algorithm is
            when No_Checksum => return US.Null_Unbounded_String;
            when Checksum_CRC32 => return Value.Checksum_CRC32;
            when Checksum_CRC32C => return Value.Checksum_CRC32C;
            when Checksum_CRC64NVME => return Value.Checksum_CRC64NVME;
            when Checksum_SHA1 => return Value.Checksum_SHA1;
            when Checksum_SHA256 => return Value.Checksum_SHA256;
            when Checksum_SHA512 => return Value.Checksum_SHA512;
            when Checksum_MD5 => return Value.Checksum_MD5;
            when Checksum_XXHASH64 => return Value.Checksum_XXHASH64;
            when Checksum_XXHASH3 => return Value.Checksum_XXHASH3;
            when Checksum_XXHASH128 => return Value.Checksum_XXHASH128;
         end case;
      end Result_Checksum;
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
         if Outcome.Kind = Low_Level.Object_Put
           and then
             (not Valid_Exact_Entity_Tag
                (US.To_String (Outcome.Result.Entity_Tag))
              or else
                (Options.Checksum.Algorithm /= No_Checksum
                 and then
                   (Result_Checksum (Outcome.Result) /= Options.Checksum.Value
                    or else US.To_String (Outcome.Result.Checksum_Type) /=
                      "FULL_OBJECT")))
         then
            raise Low_Level.Invalid_Response with
              "PutObject success does not match requested publication";
         end if;
         return Outcome;
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
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object_Tagging
             (Origin, Style, Bucket, Key, Tags, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.Object_Tagging_Outcome :=
           Low_Level.Execute_Put_Object_Tagging
             (Client, Prepared, Timeout, Token);
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
   end Put_Tags;

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
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Get_Object_Tagging
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.Object_Tagging_Outcome :=
           Low_Level.Execute_Get_Object_Tagging
             (Client, Prepared, Timeout, Token);
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
   end Get_Tags;

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
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Delete_Object_Tagging
             (Origin, Style, Bucket, Key, Parameters, Identity, Region,
              Timestamp);
         Outcome : constant Low_Level.Object_Tagging_Outcome :=
           Low_Level.Execute_Delete_Object_Tagging
             (Client, Prepared, Timeout, Token);
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
   end Delete_Tags;

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

end Flyology.Object_Storage.Client.Objects;
