with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Flyology.Object_Storage.Client.Buckets is

   package US renames Ada.Strings.Unbounded;
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
