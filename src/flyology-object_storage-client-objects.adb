with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Flyology.Object_Storage.Client.Objects is

   package US renames Ada.Strings.Unbounded;
   use type Low_Level.Delete_Object_Outcome_Kind;
   use type Low_Level.Get_Object_Head_Outcome_Kind;
   use type Low_Level.List_Outcome_Kind;
   use type Low_Level.Object_Tagging_Outcome_Kind;
   use type Low_Level.Put_Object_Outcome_Kind;

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
      Parameters : Low_Level.Put_Object_Parameters;
   begin
      if Source in
        Flyology.HTTP.Client.Rewindable_Request_Body_Source'Class
      then
         raise Low_Level.Invalid_Request with
           "conditional PutObject source must be one-shot";
      end if;
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
      Parameters.If_None_Match := US.To_Unbounded_String (If_None_Match);
      Parameters.Content_Type := US.To_Unbounded_String (Content_Type);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
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
           and then not Valid_Exact_Entity_Tag
             (US.To_String (Outcome.Result.Entity_Tag))
         then
            raise Low_Level.Invalid_Response with
              "PutObject success has no exact opaque entity tag";
         end if;
         return Outcome;
      end;
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
      Token    : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is
      Parameters : Low_Level.Delete_Object_Parameters;
   begin
      Parameters.Version_ID := US.To_Unbounded_String (Version_ID);
      Parameters.If_Match := US.To_Unbounded_String (If_Match);
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      Parameters.Request_Payer := US.To_Unbounded_String (Request_Payer);
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
