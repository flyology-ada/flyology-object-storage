with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Flyology.Object_Storage.Client.Objects is

   package US renames Ada.Strings.Unbounded;
   use type Low_Level.Delete_Object_Outcome_Kind;

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

end Flyology.Object_Storage.Client.Objects;
