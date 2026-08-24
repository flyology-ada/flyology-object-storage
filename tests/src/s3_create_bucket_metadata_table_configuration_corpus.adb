with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.Metadata_Tables;
with Flyology.Object_Storage.S3.XML;

procedure S3_Create_Bucket_Metadata_Table_Configuration_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Controls renames Flyology.Object_Storage.S3.Bucket_Controls;
   package Metadata renames Flyology.Object_Storage.S3.Metadata_Tables;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Bucket_Control_Outcome_Kind;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Hosted_Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin
       ("https://example-bucket.s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
   --  Project-policy compatibility value from the low-level diagnostic-header
   --  validator; changing it would change public response admission.
   Header_Boundary : constant Positive := 8_192;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with another 2xx and representative failures.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);
   type Text_Array is array (Positive range <>) of US.Unbounded_String;
   --  Pinned SDK checksum enum and its exact algorithm-specific headers.
   Algorithms : constant Text_Array :=
     (US.To_Unbounded_String ("CRC32"),
      US.To_Unbounded_String ("CRC32C"),
      US.To_Unbounded_String ("SHA1"),
      US.To_Unbounded_String ("SHA256"),
      US.To_Unbounded_String ("CRC64NVME"),
      US.To_Unbounded_String ("SHA512"),
      US.To_Unbounded_String ("MD5"),
      US.To_Unbounded_String ("XXHASH64"),
      US.To_Unbounded_String ("XXHASH3"),
      US.To_Unbounded_String ("XXHASH128"));
   Checksum_Headers : constant Text_Array :=
     (US.To_Unbounded_String ("x-amz-checksum-crc32"),
      US.To_Unbounded_String ("x-amz-checksum-crc32c"),
      US.To_Unbounded_String ("x-amz-checksum-sha1"),
      US.To_Unbounded_String ("x-amz-checksum-sha256"),
      US.To_Unbounded_String ("x-amz-checksum-crc64nvme"),
      US.To_Unbounded_String ("x-amz-checksum-sha512"),
      US.To_Unbounded_String ("x-amz-checksum-md5"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash64"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash3"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash128"));

   function Destination
     (ARN : String := "arn&<>"; Name : String := "table&<>")
      return Metadata.S3_Tables_Destination is
     ((Table_Bucket_ARN => US.To_Unbounded_String (ARN),
       Table_Name => US.To_Unbounded_String (Name)));

   function Parameters
     (Checksum : String := ""; MD5 : String := ""; Owner : String := "")
      return Low_Level.Bucket_Control_Mutation_Parameters is
     ((Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Serialization
     (Value : Metadata.S3_Tables_Destination;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String := Metadata.Serialize_Create
              (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Metadata.Malformed_Metadata_Table => Raised := True;
      end;
      Require (Raised, "metadata-table serializer admitted invalid input");
   end Expect_Invalid_Serialization;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket";
      Value : Metadata.S3_Tables_Destination := Destination;
      Params : Low_Level.Bucket_Control_Mutation_Parameters := Parameters;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Create_Bucket_Metadata_Table_Configuration
                (Origin, Low_Level.Path_Style, Bucket, Value, Params,
                 Identity, "us-east-1", "20130524T000000Z", Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised,
         "CreateBucketMetadataTableConfiguration admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Decode_Put_Bucket_Control_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "metadata-table create admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Value : constant Metadata.S3_Tables_Destination := Destination;
      Document : constant String := Metadata.Serialize_Create (Value);
      Expected : constant String :=
        "<MetadataTableConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><S3TablesDestination><TableBucketArn>" &
        "arn&amp;&lt;&gt;</TableBucketArn><TableName>table&amp;&lt;&gt;" &
        "</TableName></S3TablesDestination></MetadataTableConfiguration>";
      --  Decoded source text is six ARN bytes plus eight table-name bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Document'Length,
         Maximum_Depth => 3, Maximum_Elements => 4,
         Maximum_Text_Bytes => 14);
      Ignored : constant String := Metadata.Serialize_Create (Value, Exact);
      pragma Unreferenced (Ignored);
   begin
      Require (Document = Expected, "metadata-table exact XML mismatch");
      Expect_Invalid_Serialization
        (Value, (Document'Length - 1, 3, 4, 14));
      Expect_Invalid_Serialization
        (Value, (Document'Length, 2, 4, 14));
      Expect_Invalid_Serialization
        (Value, (Document'Length, 3, 3, 14));
      Expect_Invalid_Serialization
        (Value, (Document'Length, 3, 4, 13));
   end;
   declare
      Empty : constant String := Metadata.Serialize_Create
        (Destination ("", ""),
         (Maximum_Document_Bytes =>
            XML.Default_Limits.Maximum_Document_Bytes,
          Maximum_Depth => 3,
          Maximum_Elements => 4,
          --  Parse_Limits fields are positive; one is its exact smallest
          --  selectable budget and still admits the modeled empty strings.
          Maximum_Text_Bytes => 1));
   begin
      Require
        (Ada.Strings.Fixed.Index
           (Empty, "<TableBucketArn></TableBucketArn><TableName></TableName>")
         > 0,
         "metadata-table empty required strings were not preserved");
   end;
   Expect_Invalid_Serialization
     (Destination ("bad" & Character'Val (1), "table"));

   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Bucket_Metadata_Table_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Destination,
           Parameters (Checksum => "CRC32", Owner => "123456789012"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Bucket_Metadata_Table_Configuration
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Destination, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?metadataTable"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "content-md5") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-sdk-checksum-algorithm") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-checksum-crc32") > 0,
         "metadata-table path projection or checksum mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?metadataTable"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Hosted), "content-md5") > 0,
         "metadata-table hosted projection mismatch");
   end;

   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Create_Bucket_Metadata_Table_Configuration
             (Origin, Low_Level.Path_Style, "example-bucket", Destination,
              Parameters (Checksum => US.To_String (Algorithms (Index))),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               US.To_String (Checksum_Headers (Index))) > 0,
            "metadata-table checksum header mismatch");
      end;
   end loop;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Params => Parameters (Checksum => "crc32"));
   Expect_Invalid_Request (Params => Parameters (MD5 => "invalid"));
   Expect_Invalid_Request
     (Params => Parameters
        (Owner => String'(1 .. Header_Boundary + 1 => 'o')));
   Expect_Invalid_Request
     (Params => Parameters (Owner => "owner" & Character'Val (10)));
   declare
      --  Exact base64 representation of a 16-byte caller-provided MD5.
      Valid_MD5 : constant String := "AAAAAAAAAAAAAAAAAAAAAA==";
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Create_Bucket_Metadata_Table_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Destination,
           Parameters (MD5 => Valid_MD5, Owner => Exact_Owner), Identity,
           "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;
   declare
      Document : constant String := Metadata.Serialize_Create (Destination);
   begin
      Expect_Invalid_Request
        (Limits => (Document'Length - 1, 3, 4, 14));
   end;

   declare
      Empty : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response (200, "");
      Whitespace : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response (200, " " & ASCII.HT);
   begin
      Require
        (Empty.Kind = Low_Level.Bucket_Control_Updated
         and then Whitespace.Kind = Low_Level.Bucket_Control_Updated,
         "metadata-table exact success mismatch");
   end;
   Expect_Invalid_Response (200, "x");
   Expect_Invalid_Response
     (200, "", Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "", Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   Expect_Invalid_Response
     (200, "", Request_ID => "request" & Character'Val (10));
   Expect_Invalid_Response
     (200, "", Host_ID => "host" & Character'Val (13));
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Put_Bucket_Control_Outcome :=
           Low_Level.Decode_Put_Bucket_Control_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Put_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied",
            "metadata-table rejection status mismatch");
      end;
   end loop;
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (Outcome.Kind = Low_Level.Put_Bucket_Control_Rejected
         and then US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "metadata-table rejection diagnostic mismatch");
   end;
   declare
      --  Fixed error graph: depth two, three elements, 18 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 3,
         Maximum_Text_Bytes => 18);
      Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length - 1, 2, 3, 18));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 1, 3, 18));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 2, 2, 18));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 2, 3, 17));
   end;
   Expect_Invalid_Response (403, "");

   declare
      --  One client slot is the type's minimum and is sufficient because the
      --  operation-binding rejection must occur before transport admission.
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Abac_Enabled, Parameters, Identity,
           "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Execute_Create_Bucket_Metadata_Table_Configuration
                (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised,
         "CreateBucketMetadataTableConfiguration cross-operation admitted");
   end;

   Ada.Text_IO.Put_Line
     ("S3 CreateBucketMetadataTableConfiguration deterministic corpus: OK");
end S3_Create_Bucket_Metadata_Table_Configuration_Corpus;
