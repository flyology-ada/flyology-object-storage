with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Flyology.Object_Storage.Client.Buckets is

   package US renames Ada.Strings.Unbounded;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;

   function Timestamp return String is
      Image : constant String := Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock, Include_Time_Fraction => False, Time_Zone => 0);
   begin
      return Image (Image'First .. Image'First + 3)
        & Image (Image'First + 5 .. Image'First + 6)
        & Image (Image'First + 8 .. Image'First + 9) & "T"
        & Image (Image'First + 11 .. Image'First + 12)
        & Image (Image'First + 14 .. Image'First + 15)
        & Image (Image'First + 17 .. Image'First + 18) & "Z";
   end Timestamp;

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
      return List_Outcome
   is
      Parameters : constant Low_Level.List_Buckets_Parameters :=
        (Max_Buckets            => Maximum,
         Has_Max_Buckets        => True,
         Continuation_Token     =>
           US.To_Unbounded_String (Continuation_Token),
         Has_Continuation_Token => Continuation_Token'Length > 0,
         Prefix                 => US.To_Unbounded_String (Prefix),
         Has_Prefix             => Prefix'Length > 0,
         Bucket_Region          => US.To_Unbounded_String (Bucket_Region));
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_List_Buckets
          (Origin, Style, Parameters, Identity, Region, Timestamp);
      Outcome : constant Low_Level.List_Buckets_Outcome :=
        Low_Level.Execute_List_Buckets
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.List_Buckets_Rejected then
         return
           (Kind => List_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return
        (Kind => Page_Available, Status => Outcome.Status,
         Page => Outcome.Result);
   end List_Page;

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
      return Create_Outcome
   is
      Parameters : Low_Level.Create_Bucket_Parameters;
   begin
      Parameters.Configuration.Location_Constraint :=
        US.To_Unbounded_String
          (if Location_Constraint'Length > 0 then Location_Constraint
           elsif Region /= "us-east-1" then Region
           else "");
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Bucket
             (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
         Outcome : constant Low_Level.Create_Bucket_Outcome :=
           Low_Level.Execute_Create_Bucket
             (Client, Prepared, Timeout, Token);
      begin
         if Outcome.Kind = Low_Level.Create_Bucket_Rejected then
            return
              (Kind => Create_Rejected, Status => Outcome.Status,
               Error => Outcome.Error);
         end if;
         return
           (Kind       => Creation_Completed,
            Status     => Outcome.Status,
            Location   => Outcome.Result.Location,
            Bucket_ARN => Outcome.Result.Bucket_ARN);
      end;
   end Create;

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
      return Delete_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
      Outcome : constant Low_Level.Delete_Bucket_Outcome :=
        Low_Level.Execute_Delete_Bucket
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Delete_Bucket_Rejected then
         return
           (Kind => Delete_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return (Kind => Deletion_Completed, Status => Outcome.Status);
   end Delete;

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
      return Head_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Head_Bucket
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
      Outcome : constant Low_Level.Head_Bucket_Outcome :=
        Low_Level.Execute_Head_Bucket (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Head_Bucket_Rejected then
         return
           (Kind => Head_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return
        (Kind                 => Bucket_Available,
         Status               => Outcome.Status,
         Bucket_ARN           => Outcome.Result.Bucket_ARN,
         Bucket_Location_Type => Outcome.Result.Bucket_Location_Type,
         Bucket_Location_Name => Outcome.Result.Bucket_Location_Name,
         Region               =>
           (if US.Length (Outcome.Result.Bucket_Region) = 0
            then US.To_Unbounded_String (Region)
            else Outcome.Result.Bucket_Region),
         Access_Point_Alias   => Outcome.Result.Access_Point_Alias);
   end Head;

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
      return Location_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Location
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
      Outcome : constant Low_Level.Get_Bucket_Location_Outcome :=
        Low_Level.Execute_Get_Bucket_Location
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Get_Bucket_Location_Rejected then
         return
           (Kind => Location_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      declare
         Constraint : constant String :=
           US.To_String (Outcome.Result.Location_Constraint);
         Normalized : constant String :=
           (if Constraint'Length = 0 then "us-east-1"
            elsif Constraint = "EU" then "eu-west-1"
            else Constraint);
      begin
         return
           (Kind => Location_Found, Status => Outcome.Status,
            Region => US.To_Unbounded_String (Normalized),
            Legacy_Constraint => Outcome.Result.Location_Constraint);
      end;
   end Get_Location;

end Flyology.Object_Storage.Client.Buckets;
