with Ada.Calendar;
with Ada.Calendar.Formatting;

package body Flyology.Object_Storage.Client.Buckets is

   package US renames Ada.Strings.Unbounded;
   package LL renames Low_Level;
   use type Low_Level.List_Buckets_Outcome_Kind;
   use type Low_Level.Create_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Configuration_Outcome_Kind;
   use type Low_Level.Get_Bucket_Location_Outcome_Kind;
   use type Low_Level.Head_Bucket_Outcome_Kind;
   use type Low_Level.Put_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Get_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Delete_Bucket_Tagging_Outcome_Kind;
   use type Low_Level.Put_Bucket_Versioning_Outcome_Kind;
   use type Low_Level.Get_Bucket_Versioning_Outcome_Kind;

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

   type Configuration_Deletion_Kind is
     (CORS_Configuration,
      Analytics_Configuration,
      Encryption_Configuration,
      Intelligent_Tiering_Configuration,
      Inventory_Configuration,
      Lifecycle_Configuration,
      Metadata_Configuration,
      Metadata_Table_Configuration,
      Metrics_Configuration,
      Ownership_Controls_Configuration,
      Policy_Configuration,
      Replication_Configuration,
      Website_Configuration,
      Public_Access_Block_Configuration);

   function Delete_Configuration
     (Kind       : Configuration_Deletion_Kind;
      Client     : aliased in out Flyology.HTTP.Client.Client;
      Origin     : Flyology.HTTP.Origin;
      Bucket     : String;
      Identifier : String;
      Identity   : Low_Level.Credentials;
      Region     : String;
      Style      : Low_Level.Addressing_Style;
      Expected_Bucket_Owner : String;
      Timeout    : Duration;
      Token      : access Flyology.Cancellation.Token)
      return Delete_Outcome
   is
      Parameters : constant Low_Level.Delete_Bucket_Configuration_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
      Parameters_With_ID : constant
        Low_Level.Delete_Bucket_Configuration_With_ID_Parameters :=
          (ID                    => US.To_Unbounded_String (Identifier),
           Expected_Bucket_Owner =>
             US.To_Unbounded_String (Expected_Bucket_Owner));

      function Prepare return Low_Level.Prepared_Request is
      begin
         case Kind is
            when CORS_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_CORS
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Analytics_Configuration =>
               return
                 Low_Level.Prepare_Delete_Bucket_Analytics_Configuration
                   (Origin, Style, Bucket, Parameters_With_ID, Identity,
                    Region, Timestamp);
            when Encryption_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Encryption
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Intelligent_Tiering_Configuration =>
               return
                 LL.Prepare_Delete_Bucket_Intelligent_Tiering_Configuration
                   (Origin, Style, Bucket, Parameters_With_ID, Identity,
                    Region, Timestamp);
            when Inventory_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Inventory_Configuration
                 (Origin, Style, Bucket, Parameters_With_ID, Identity, Region,
                  Timestamp);
            when Lifecycle_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Lifecycle
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Metadata_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Metadata_Configuration
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Metadata_Table_Configuration =>
               return
                 Low_Level.Prepare_Delete_Bucket_Metadata_Table_Configuration
                   (Origin, Style, Bucket, Parameters, Identity, Region,
                    Timestamp);
            when Metrics_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Metrics_Configuration
                 (Origin, Style, Bucket, Parameters_With_ID, Identity, Region,
                  Timestamp);
            when Ownership_Controls_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Ownership_Controls
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Policy_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Policy
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Replication_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Replication
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Website_Configuration =>
               return Low_Level.Prepare_Delete_Bucket_Website
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
            when Public_Access_Block_Configuration =>
               return Low_Level.Prepare_Delete_Public_Access_Block
                 (Origin, Style, Bucket, Parameters, Identity, Region,
                  Timestamp);
         end case;
      end Prepare;

      Prepared : constant Low_Level.Prepared_Request := Prepare;

      function Execute return Low_Level.Delete_Bucket_Configuration_Outcome is
      begin
         case Kind is
            when CORS_Configuration =>
               return Low_Level.Execute_Delete_Bucket_CORS
                 (Client, Prepared, Timeout, Token);
            when Analytics_Configuration =>
               return
                 Low_Level.Execute_Delete_Bucket_Analytics_Configuration
                   (Client, Prepared, Timeout, Token);
            when Encryption_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Encryption
                 (Client, Prepared, Timeout, Token);
            when Intelligent_Tiering_Configuration =>
               return
                 LL.Execute_Delete_Bucket_Intelligent_Tiering_Configuration
                   (Client, Prepared, Timeout, Token);
            when Inventory_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Inventory_Configuration
                 (Client, Prepared, Timeout, Token);
            when Lifecycle_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Lifecycle
                 (Client, Prepared, Timeout, Token);
            when Metadata_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Metadata_Configuration
                 (Client, Prepared, Timeout, Token);
            when Metadata_Table_Configuration =>
               return
                 Low_Level.Execute_Delete_Bucket_Metadata_Table_Configuration
                   (Client, Prepared, Timeout, Token);
            when Metrics_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Metrics_Configuration
                 (Client, Prepared, Timeout, Token);
            when Ownership_Controls_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Ownership_Controls
                 (Client, Prepared, Timeout, Token);
            when Policy_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Policy
                 (Client, Prepared, Timeout, Token);
            when Replication_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Replication
                 (Client, Prepared, Timeout, Token);
            when Website_Configuration =>
               return Low_Level.Execute_Delete_Bucket_Website
                 (Client, Prepared, Timeout, Token);
            when Public_Access_Block_Configuration =>
               return Low_Level.Execute_Delete_Public_Access_Block
                 (Client, Prepared, Timeout, Token);
         end case;
      end Execute;

      Outcome : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
        Execute;
   begin
      if Outcome.Kind = Low_Level.Delete_Configuration_Rejected then
         return
           (Kind => Delete_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return (Kind => Deletion_Completed, Status => Outcome.Status);
   end Delete_Configuration;

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
      return Delete_Outcome
   is (Delete_Configuration
         (CORS_Configuration, Client, Origin, Bucket, "", Identity, Region,
          Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Analytics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Analytics_Configuration, Client, Origin, Bucket, Identifier,
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Encryption
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Encryption_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Intelligent_Tiering_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Intelligent_Tiering_Configuration, Client, Origin, Bucket,
          Identifier, Identity, Region, Style, Expected_Bucket_Owner,
          Timeout, Token));

   function Delete_Inventory_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Inventory_Configuration, Client, Origin, Bucket, Identifier,
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Lifecycle
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Lifecycle_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Metadata_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Metadata_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Metadata_Table_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Metadata_Table_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Metrics_Configuration
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket, Identifier : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Metrics_Configuration, Client, Origin, Bucket, Identifier, Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Ownership_Controls
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Ownership_Controls_Configuration, Client, Origin, Bucket, "",
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Policy
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Policy_Configuration, Client, Origin, Bucket, "", Identity, Region,
          Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Replication
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Replication_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Website
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Website_Configuration, Client, Origin, Bucket, "", Identity,
          Region, Style, Expected_Bucket_Owner, Timeout, Token));

   function Delete_Public_Access_Block
     (Client : aliased in out Flyology.HTTP.Client.Client;
      Origin : Flyology.HTTP.Origin; Bucket : String;
      Identity : Low_Level.Credentials; Region : String := "us-east-1";
      Style : Low_Level.Addressing_Style := Low_Level.Path_Style;
      Expected_Bucket_Owner : String := ""; Timeout : Duration := 30.0;
      Token : access Flyology.Cancellation.Token := null)
      return Delete_Outcome
   is (Delete_Configuration
         (Public_Access_Block_Configuration, Client, Origin, Bucket, "",
          Identity, Region, Style, Expected_Bucket_Owner, Timeout, Token));

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
      return Put_Tags_Outcome
   is
      Parameters : constant Low_Level.Put_Bucket_Tagging_Parameters :=
        (Content_MD5           => US.Null_Unbounded_String,
         Checksum_Algorithm    => US.Null_Unbounded_String,
         Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner),
         Request_Payer         => US.Null_Unbounded_String);
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Tagging
          (Origin, Style, Bucket, Value, Parameters, Identity, Region,
           Timestamp);
      Outcome : constant Low_Level.Put_Bucket_Tagging_Outcome :=
        Low_Level.Execute_Put_Bucket_Tagging
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Put_Bucket_Tagging_Rejected then
         return
           (Kind => Put_Tags_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return (Kind => Tags_Replaced, Status => Outcome.Status);
   end Put_Tags;

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
      return Get_Tags_Outcome
   is
      Parameters : constant Low_Level.Get_Bucket_Tagging_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner),
         Request_Payer         => US.Null_Unbounded_String);
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Tagging
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Outcome : constant Low_Level.Get_Bucket_Tagging_Outcome :=
        Low_Level.Execute_Get_Bucket_Tagging
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Get_Bucket_Tagging_Rejected then
         return
           (Kind => Get_Tags_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return
        (Kind => Tags_Found, Status => Outcome.Status,
         Value => Outcome.Result.Value);
   end Get_Tags;

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
      return Delete_Tags_Outcome
   is
      Parameters : constant Low_Level.Delete_Bucket_Tagging_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String (Expected_Bucket_Owner));
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket_Tagging
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Outcome : constant Low_Level.Delete_Bucket_Tagging_Outcome :=
        Low_Level.Execute_Delete_Bucket_Tagging
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Delete_Bucket_Tagging_Rejected then
         return
           (Kind => Delete_Tags_Rejected, Status => Outcome.Status,
            Error => Outcome.Error);
      end if;
      return (Kind => Tags_Deleted, Status => Outcome.Status);
   end Delete_Tags;

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
      return Set_Versioning_Outcome
   is
      Parameters : Low_Level.Put_Bucket_Versioning_Parameters;
   begin
      Parameters.Configuration.Status := Versioning;
      Parameters.Expected_Bucket_Owner :=
        US.To_Unbounded_String (Expected_Bucket_Owner);
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Bucket_Versioning
             (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
         Outcome : constant Low_Level.Put_Bucket_Versioning_Outcome :=
           Low_Level.Execute_Put_Bucket_Versioning
             (Client, Prepared, Timeout, Token);
      begin
         if Outcome.Kind = Low_Level.Put_Bucket_Versioning_Rejected then
            return
              (Kind => Set_Versioning_Rejected,
               Status => Outcome.Status, Error => Outcome.Error);
         end if;
         return
           (Kind => Versioning_Updated, Status => Outcome.Status);
      end;
   end Set_Versioning;

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
      return Set_Versioning_Outcome
   is
      Parameters : constant Low_Level.Put_Bucket_Versioning_Parameters :=
        (Content_MD5           => US.Null_Unbounded_String,
         Checksum_Algorithm    => US.To_Unbounded_String
           (Checksum_Algorithm),
         MFA                   => US.To_Unbounded_String (MFA),
         Configuration         => Configuration,
         Expected_Bucket_Owner => US.To_Unbounded_String
           (Expected_Bucket_Owner));
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Versioning
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
      Outcome : constant Low_Level.Put_Bucket_Versioning_Outcome :=
        Low_Level.Execute_Put_Bucket_Versioning
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Put_Bucket_Versioning_Rejected then
         return
           (Kind => Set_Versioning_Rejected,
            Status => Outcome.Status, Error => Outcome.Error);
      end if;
      return (Kind => Versioning_Updated, Status => Outcome.Status);
   end Set_Versioning_Configuration;

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
      return Get_Versioning_Outcome
   is
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Versioning
          (Origin, Style, Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (Expected_Bucket_Owner)),
           Identity, Region, Timestamp);
      Outcome : constant Low_Level.Get_Bucket_Versioning_Outcome :=
        Low_Level.Execute_Get_Bucket_Versioning
          (Client, Prepared, Timeout, Token);
   begin
      if Outcome.Kind = Low_Level.Get_Bucket_Versioning_Rejected then
         return
           (Kind => Get_Versioning_Rejected,
            Status => Outcome.Status, Error => Outcome.Error);
      end if;
      return
        (Kind          => Versioning_Found,
         Status        => Outcome.Status,
         Configuration => Outcome.Configuration);
   end Get_Versioning;

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
      return Low_Level.Create_Session_Outcome
   is
      Parameters : constant Low_Level.Create_Session_Parameters :=
        (Session_Mode => US.To_Unbounded_String (Session_Mode),
         Server_Side_Encryption =>
           US.To_Unbounded_String (Server_Side_Encryption),
         SSE_KMS_Key_ID => US.To_Unbounded_String (SSE_KMS_Key_ID),
         SSE_KMS_Encryption_Context =>
           US.To_Unbounded_String (SSE_KMS_Encryption_Context),
         Bucket_Key_Enabled => Bucket_Key_Enabled);
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Session
          (Origin, Style, Bucket, Parameters, Identity, Region, Timestamp);
   begin
      return Low_Level.Execute_Create_Session
        (Client, Prepared, Timeout, Token);
   end Create_Session;

end Flyology.Object_Storage.Client.Buckets;
