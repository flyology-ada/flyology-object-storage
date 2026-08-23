with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;

procedure S3_Delete_Bucket_Configurations_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package US renames Ada.Strings.Unbounded;
   use type Low_Level.Delete_Bucket_Configuration_Outcome_Kind;

   type Operation_Kind is
     (Delete_Bucket_Analytics_Configuration,
      Delete_Bucket_Encryption,
      Delete_Bucket_Intelligent_Tiering_Configuration,
      Delete_Bucket_Inventory_Configuration,
      Delete_Bucket_Lifecycle,
      Delete_Bucket_Metadata_Configuration,
      Delete_Bucket_Metadata_Table_Configuration,
      Delete_Bucket_Metrics_Configuration,
      Delete_Bucket_Ownership_Controls,
      Delete_Bucket_Policy,
      Delete_Bucket_Replication,
      Delete_Bucket_Website,
      Delete_Public_Access_Block);

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Timestamp : constant String := "20130524T000000Z";
   Region : constant String := "us-east-1";
   Bucket : constant String := "example-bucket";
   Owner : constant String := "123456789012";
   Identifier : constant String := "config id";
   Maximum_Request_Target_Bytes : constant Positive := 8_192;
   Maximum_Header_Text_Bytes : constant Positive := 8_192;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Needs_Identifier (Kind : Operation_Kind) return Boolean is
     (Kind in Delete_Bucket_Analytics_Configuration |
              Delete_Bucket_Intelligent_Tiering_Configuration |
              Delete_Bucket_Inventory_Configuration |
              Delete_Bucket_Metrics_Configuration);

   function Subresource (Kind : Operation_Kind) return String is
   begin
      case Kind is
         when Delete_Bucket_Analytics_Configuration =>
            return "analytics";
         when Delete_Bucket_Encryption =>
            return "encryption";
         when Delete_Bucket_Intelligent_Tiering_Configuration =>
            return "intelligent-tiering";
         when Delete_Bucket_Inventory_Configuration =>
            return "inventory";
         when Delete_Bucket_Lifecycle =>
            return "lifecycle";
         when Delete_Bucket_Metadata_Configuration =>
            return "metadataConfiguration";
         when Delete_Bucket_Metadata_Table_Configuration =>
            return "metadataTable";
         when Delete_Bucket_Metrics_Configuration =>
            return "metrics";
         when Delete_Bucket_Ownership_Controls =>
            return "ownershipControls";
         when Delete_Bucket_Policy =>
            return "policy";
         when Delete_Bucket_Replication =>
            return "replication";
         when Delete_Bucket_Website =>
            return "website";
         when Delete_Public_Access_Block =>
            return "publicAccessBlock";
      end case;
   end Subresource;

   function Prepare
     (Kind       : Operation_Kind;
      Origin     : Flyology.HTTP.Origin;
      Style      : Low_Level.Addressing_Style;
      Identifier : String;
      Owner      : String) return Low_Level.Prepared_Request
   is
      Parameters : constant Low_Level.Delete_Bucket_Configuration_Parameters :=
        (Expected_Bucket_Owner => US.To_Unbounded_String (Owner));
      With_ID : constant
        Low_Level.Delete_Bucket_Configuration_With_ID_Parameters :=
          (ID                    => US.To_Unbounded_String (Identifier),
           Expected_Bucket_Owner => US.To_Unbounded_String (Owner));
   begin
      case Kind is
         when Delete_Bucket_Analytics_Configuration =>
            return Low_Level.Prepare_Delete_Bucket_Analytics_Configuration
              (Origin, Style, Bucket, With_ID, Identity, Region, Timestamp);
         when Delete_Bucket_Encryption =>
            return Low_Level.Prepare_Delete_Bucket_Encryption
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Bucket_Intelligent_Tiering_Configuration =>
            return
              Low_Level.Prepare_Delete_Bucket_Intelligent_Tiering_Configuration
                (Origin, Style, Bucket, With_ID, Identity, Region, Timestamp);
         when Delete_Bucket_Inventory_Configuration =>
            return Low_Level.Prepare_Delete_Bucket_Inventory_Configuration
              (Origin, Style, Bucket, With_ID, Identity, Region, Timestamp);
         when Delete_Bucket_Lifecycle =>
            return Low_Level.Prepare_Delete_Bucket_Lifecycle
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Bucket_Metadata_Configuration =>
            return Low_Level.Prepare_Delete_Bucket_Metadata_Configuration
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Bucket_Metadata_Table_Configuration =>
            return
              Low_Level.Prepare_Delete_Bucket_Metadata_Table_Configuration
                (Origin, Style, Bucket, Parameters, Identity, Region,
                 Timestamp);
         when Delete_Bucket_Metrics_Configuration =>
            return Low_Level.Prepare_Delete_Bucket_Metrics_Configuration
              (Origin, Style, Bucket, With_ID, Identity, Region, Timestamp);
         when Delete_Bucket_Ownership_Controls =>
            return Low_Level.Prepare_Delete_Bucket_Ownership_Controls
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Bucket_Policy =>
            return Low_Level.Prepare_Delete_Bucket_Policy
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Bucket_Replication =>
            return Low_Level.Prepare_Delete_Bucket_Replication
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Bucket_Website =>
            return Low_Level.Prepare_Delete_Bucket_Website
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
         when Delete_Public_Access_Block =>
            return Low_Level.Prepare_Delete_Public_Access_Block
              (Origin, Style, Bucket, Parameters, Identity, Region,
               Timestamp);
      end case;
   end Prepare;

   procedure Expect_Invalid_Identifier
     (Kind : Operation_Kind; Value : String)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Prepare
                (Kind,
                 Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
                 Low_Level.Path_Style, Value, Owner);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require
        (Raised, Operation_Kind'Image (Kind) &
           " admitted an invalid required Id");
   end Expect_Invalid_Identifier;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Delete_Bucket_Configuration_Outcome :=
                Low_Level.Decode_Delete_Bucket_Configuration_Response
                  (Status, Payload);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "shared configuration response was admitted");
   end Expect_Invalid_Response;

begin
   for Kind in Operation_Kind loop
      declare
         Path : constant Low_Level.Prepared_Request :=
           Prepare
             (Kind,
              Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
              Low_Level.Path_Style,
              (if Needs_Identifier (Kind) then Identifier else ""), Owner);
         Hosted : constant Low_Level.Prepared_Request :=
           Prepare
             (Kind,
              Flyology.HTTP.Parse_Origin
                ("https://example-bucket.s3.example.test"),
              Low_Level.Virtual_Hosted_Style,
              (if Needs_Identifier (Kind) then Identifier else ""), Owner);
         Omitted : constant Low_Level.Prepared_Request :=
           Prepare
             (Kind,
              Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
              Low_Level.Path_Style,
              (if Needs_Identifier (Kind) then Identifier else ""), "");
         Query : constant String :=
           (if not Needs_Identifier (Kind)
            then "?" & Subresource (Kind)
            elsif Kind = Delete_Bucket_Analytics_Configuration
            then "?analytics&id=config%20id"
            else "?id=config%20id&" & Subresource (Kind));
      begin
         Require
           (Low_Level.Target (Path) = "/example-bucket" & Query,
            Operation_Kind'Image (Kind) & " path target mismatch: " &
              Low_Level.Target (Path));
         Require
           (Low_Level.Target (Hosted) = "/" & Query
            and then Low_Level.Authority (Hosted) =
              "example-bucket.s3.example.test",
            Operation_Kind'Image (Kind) & " hosted target mismatch");
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Path),
               "x-amz-expected-bucket-owner") > 0
            and then Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Omitted),
               "x-amz-expected-bucket-owner") = 0,
            Operation_Kind'Image (Kind) & " owner projection mismatch");
      end;
      if Needs_Identifier (Kind) then
         Expect_Invalid_Identifier (Kind, "");
         Expect_Invalid_Identifier
           (Kind, "id" & Character'Val (10));
         declare
            Target_Prefix : constant String :=
              "/example-bucket?" & Subresource (Kind) & "&id=";
            Maximum_ID_Length : constant Positive :=
              Maximum_Request_Target_Bytes - Target_Prefix'Length;
            Exact : constant Low_Level.Prepared_Request :=
              Prepare
                (Kind,
                 Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
                 Low_Level.Path_Style,
                 String'(1 .. Maximum_ID_Length => 'i'), Owner);
            pragma Unreferenced (Exact);
         begin
            Expect_Invalid_Identifier
              (Kind, String'(1 .. Maximum_ID_Length + 1 => 'i'));
         end;
      end if;
   end loop;

   declare
      Exact : constant Low_Level.Prepared_Request :=
        Prepare
          (Delete_Bucket_Encryption,
           Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
           Low_Level.Path_Style, "",
           String'(1 .. Maximum_Header_Text_Bytes => 'o'));
      pragma Unreferenced (Exact);
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Prepare
                (Delete_Bucket_Encryption,
                 Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
                 Low_Level.Path_Style, "",
                 String'(1 .. Maximum_Header_Text_Bytes + 1 => 'o'));
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require (Raised, "configuration deletion admitted overlong owner");
   end;

   declare
      Success : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
        Low_Level.Decode_Delete_Bucket_Configuration_Response (204, "");
      Error_XML : constant String :=
        "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
      Rejection : constant Low_Level.Delete_Bucket_Configuration_Outcome :=
        Low_Level.Decode_Delete_Bucket_Configuration_Response
          (403, Error_XML, "request", "host");
   begin
      Require
        (Success.Kind = Low_Level.Configuration_Deleted
         and then Success.Status = 204,
         "shared configuration success mismatch");
      Require
        (Rejection.Kind = Low_Level.Delete_Configuration_Rejected
         and then Rejection.Status = 403
         and then US.To_String (Rejection.Error.Code) = "AccessDenied",
         "shared configuration rejection mismatch");
   end;
   Expect_Invalid_Response (204, " ");
   Expect_Invalid_Response (200, "");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Prepared : constant Low_Level.Prepared_Request :=
        Prepare
          (Delete_Bucket_Analytics_Configuration,
           Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
           Low_Level.Path_Style, Identifier, Owner);
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Delete_Bucket_Configuration_Outcome :=
                Low_Level.Execute_Delete_Bucket_Encryption
                  (HTTP, Prepared, Timeout => 0.01);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require (Raised, "cross-operation prepared request was executed");
   end;
end S3_Delete_Bucket_Configurations_Corpus;
