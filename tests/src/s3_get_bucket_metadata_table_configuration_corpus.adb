with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_Metadata_Table_Configuration_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Metadata_Tables renames
     Flyology.Object_Storage.S3.Metadata_Tables;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Get_Bucket_Control_Outcome_Kind;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message>" &
     "<Resource>/example-bucket</Resource></Error>";
   --  Exact established low-level bucket-control header-text ceiling; these
   --  tests preserve the shared admission and diagnostic compatibility edge.
   Header_Boundary : constant Positive := 8_192;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with another 2xx and representative failures.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);

   function Payload
     (Status : String := "ACTIVE"; Error : String := "") return String is
     ("<GetBucketMetadataTableConfigurationResult>" &
      "<MetadataTableConfigurationResult>" &
      "<S3TablesDestinationResult>" &
      "<TableBucketArn>arn:bucket</TableBucketArn>" &
      "<TableName>table-name</TableName>" &
      "<TableArn>arn:table</TableArn>" &
      "<TableNamespace>namespace</TableNamespace>" &
      "</S3TablesDestinationResult>" &
      "</MetadataTableConfigurationResult><Status>" & Status &
      "</Status>" & Error &
      "</GetBucketMetadataTableConfigurationResult>");

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Document : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
                Low_Level.
                  Decode_Get_Bucket_Metadata_Table_Configuration_Response
                    (Status, Document, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "metadata-table read admitted invalid response");
   end Expect_Invalid_Response;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
                (Origin, Low_Level.Path_Style, Bucket,
                 (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "metadata-table read admitted invalid request");
   end Expect_Invalid_Request;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?metadataTable"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "metadata-table path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?metadataTable"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "metadata-table hosted projection mismatch");
   end;
   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Metadata_Table_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Absent : constant
        Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
            (200, "");
      Full : constant
        Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
            (200, Payload
               ("future:READY/v2",
                "<Error><ErrorCode></ErrorCode>" &
                "<ErrorMessage>provider detail</ErrorMessage></Error>"));
      Empty : constant
        Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
            (200, "<GetBucketMetadataTableConfigurationResult>" &
               "<MetadataTableConfigurationResult>" &
               "<S3TablesDestinationResult><TableBucketArn/>" &
               "<TableName/><TableArn/><TableNamespace/>" &
               "</S3TablesDestinationResult>" &
               "</MetadataTableConfigurationResult><Status/>" &
               "<Error/></GetBucketMetadataTableConfigurationResult>");
      Result : constant Metadata_Tables.Metadata_Table_Configuration_Result :=
        Full.Configuration;
   begin
      Require
        (not Absent.Configuration.Is_Set
         and then Full.Configuration.Is_Set
         and then US.To_String (Result.Destination.Table_Bucket_ARN) =
           "arn:bucket"
         and then US.To_String (Result.Destination.Table_Name) = "table-name"
         and then US.To_String (Result.Destination.Table_ARN) = "arn:table"
         and then US.To_String (Result.Destination.Table_Namespace) =
           "namespace"
         and then US.To_String (Result.Status) = "future:READY/v2"
         and then Result.Error.Is_Set
         and then Result.Error.Code.Is_Set
         and then US.To_String (Result.Error.Code.Value) = ""
         and then Result.Error.Message.Is_Set
         and then US.To_String (Result.Error.Message.Value) =
           "provider detail",
         "metadata-table typed result mismatch");
      Require
        (Empty.Configuration.Is_Set
         and then US.Length
           (Empty.Configuration.Destination.Table_Bucket_ARN) = 0
         and then US.Length (Empty.Configuration.Destination.Table_Name) = 0
         and then US.Length (Empty.Configuration.Destination.Table_ARN) = 0
         and then US.Length
           (Empty.Configuration.Destination.Table_Namespace) = 0
         and then US.Length (Empty.Configuration.Status) = 0
         and then Empty.Configuration.Error.Is_Set
         and then not Empty.Configuration.Error.Code.Is_Set
         and then not Empty.Configuration.Error.Message.Is_Set,
         "metadata-table empty-string or optional presence mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult><Status>x</Status>" &
        "</GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult/>" &
        "</GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult><S3TablesDestinationResult>" &
        "<TableBucketArn/><TableName/><TableArn/>" &
        "</S3TablesDestinationResult></MetadataTableConfigurationResult>" &
        "<Status>x</Status></GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult>" &
        "<S3TablesDestinationResult><TableBucketArn/><TableName/>" &
        "<TableArn/><TableNamespace/></S3TablesDestinationResult>" &
        "</MetadataTableConfigurationResult>" &
        "</GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult>" &
        "<S3TablesDestinationResult><TableBucketArn/><TableName/>" &
        "<TableArn/><TableNamespace/></S3TablesDestinationResult>" &
        "</MetadataTableConfigurationResult><Status>x</Status>" &
        "<Status>y</Status></GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult>" &
        "<S3TablesDestinationResult><TableBucketArn/><TableName/>" &
        "<TableArn/><TableNamespace/></S3TablesDestinationResult>" &
        "</MetadataTableConfigurationResult><Status>x</Status>" &
        "<Unknown/></GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, Payload ("x") & "<unexpected/>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult value=""x"">" &
        "</GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult xmlns=""urn:wrong"">" &
        "</GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult xmlns=""http://s3." &
        "amazonaws.com/doc/2006-03-01/"">" &
        "<MetadataTableConfigurationResult xmlns=""""/>" &
        "</GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE GetBucketMetadataTableConfigurationResult [" &
        "<!ENTITY x 'ACTIVE'>]><GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult><S3TablesDestinationResult>" &
        "<TableBucketArn/><TableName/><TableArn/><TableNamespace/>" &
        "</S3TablesDestinationResult></MetadataTableConfigurationResult>" &
        "<Status>&x;</Status></GetBucketMetadataTableConfigurationResult>");
   Expect_Invalid_Response
     (200, "<?probe value?><GetBucketMetadataTableConfigurationResult/>");
   Expect_Invalid_Response
     (200, "<GetBucketMetadataTableConfigurationResult>" &
        Character'Val (255) &
        "</GetBucketMetadataTableConfigurationResult>");

   declare
      Document : constant String :=
        "<GetBucketMetadataTableConfigurationResult>" &
        "<MetadataTableConfigurationResult>" &
        "<S3TablesDestinationResult><TableBucketArn/><TableName/>" &
        "<TableArn/><TableNamespace/></S3TablesDestinationResult>" &
        "</MetadataTableConfigurationResult><Status>xy</Status>" &
        "</GetBucketMetadataTableConfigurationResult>";
      --  This fixed reference has depth four, eight elements, and two text
      --  bytes; each field below is the exact caller-selected test boundary.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Document'Length,
         Maximum_Depth => 4, Maximum_Elements => 8,
         Maximum_Text_Bytes => 2);
      Ignored : constant
        Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
            (200, Document, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (200, Document, Limits => (Document'Length - 1, 4, 8, 2));
      Expect_Invalid_Response
        (200, Document, Limits => (Document'Length, 3, 8, 2));
      Expect_Invalid_Response
        (200, Document, Limits => (Document'Length, 4, 7, 2));
      Expect_Invalid_Response
        (200, Document, Limits => (Document'Length, 4, 8, 1));
   end;

   Expect_Invalid_Response
     (200, Payload, Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, Payload, Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   Expect_Invalid_Response
     (200, Payload, Request_ID => "request" & Character'Val (10));
   Expect_Invalid_Response
     (200, Payload, Host_ID => "host" & Character'Val (13));
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant
        Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
            (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "metadata-table diagnostic boundary mismatch");
   end;
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant
           Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
             Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
               (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied",
            "metadata-table typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 33 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 4,
         Maximum_Text_Bytes => 33);
      Ignored : constant
        Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Metadata_Table_Configuration_Response
            (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length - 1, 2, 4, 33));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 1, 4, 33));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 2, 3, 33));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 2, 4, 32));
   end;
   Expect_Invalid_Response (403, "");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Encryption
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Get_Bucket_Metadata_Table_Configuration_Outcome :=
                Low_Level.Execute_Get_Bucket_Metadata_Table_Configuration
                  (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "metadata-table cross-operation execution admitted");
   end;

   Ada.Text_IO.Put_Line
     ("S3 GetBucketMetadataTableConfiguration deterministic corpus: OK");
end S3_Get_Bucket_Metadata_Table_Configuration_Corpus;
