with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Encryption;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_Encryption_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Encryption renames Flyology.Object_Storage.S3.Encryption;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Encryption.Encryption_Algorithm;
   use type Encryption.Blocked_Encryption_Type;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>ServerSideEncryptionConfigurationNotFoundError</Code>" &
     "<Message>missing</Message><Resource>/example-bucket</Resource></Error>";
   --  Exact established low-level bucket-control header-text ceiling; these
   --  tests preserve the shared admission and diagnostic compatibility edge.
   Header_Boundary : constant Positive := 8_192;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with another 2xx and representative failures.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Bucket_Encryption_Outcome :=
              Low_Level.Decode_Get_Bucket_Encryption_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "GetBucketEncryption admitted invalid response");
   end Expect_Invalid_Response;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Encryption
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
      Require (Raised, "GetBucketEncryption admitted invalid request");
   end Expect_Invalid_Request;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Encryption
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Encryption
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?encryption"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetBucketEncryption path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?encryption"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetBucketEncryption hosted projection mismatch");
   end;
   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Owner : constant String :=
        String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Encryption
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Bucket_Encryption_Outcome :=
        Low_Level.Decode_Get_Bucket_Encryption_Response (200, "");
      Full : constant Low_Level.Get_Bucket_Encryption_Outcome :=
        Low_Level.Decode_Get_Bucket_Encryption_Response
          (200, "<ServerSideEncryptionConfiguration xmlns=""http://s3." &
             "amazonaws.com/doc/2006-03-01/""><Rule>" &
             "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>AES256" &
             "</SSEAlgorithm><KMSMasterKeyID></KMSMasterKeyID>" &
             "</ApplyServerSideEncryptionByDefault><BucketKeyEnabled>true" &
             "</BucketKeyEnabled><BlockedEncryptionTypes>" &
             "<EncryptionType>NONE</EncryptionType><EncryptionType>SSE-C" &
             "</EncryptionType></BlockedEncryptionTypes></Rule><Rule>" &
             "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>aws:fsx" &
             "</SSEAlgorithm></ApplyServerSideEncryptionByDefault></Rule>" &
             "<Rule><ApplyServerSideEncryptionByDefault><SSEAlgorithm>" &
             "aws:backup</SSEAlgorithm></ApplyServerSideEncryptionByDefault>" &
             "</Rule><Rule><ApplyServerSideEncryptionByDefault>" &
             "<SSEAlgorithm>aws:kms</SSEAlgorithm>" &
             "</ApplyServerSideEncryptionByDefault></Rule><Rule>" &
             "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>aws:kms:dsse" &
             "</SSEAlgorithm></ApplyServerSideEncryptionByDefault></Rule>" &
             "</ServerSideEncryptionConfiguration>");
      Sparse : constant Low_Level.Get_Bucket_Encryption_Outcome :=
        Low_Level.Decode_Get_Bucket_Encryption_Response
          (200, "<ServerSideEncryptionConfiguration><Rule/><Rule>" &
             "<BlockedEncryptionTypes/></Rule>" &
             "</ServerSideEncryptionConfiguration>");
      First : constant Encryption.Encryption_Rule :=
        Full.Configuration.Rules.Element (1);
   begin
      Require
        (not Absent.Configuration.Is_Set
         and then Absent.Configuration.Rules.Is_Empty
         and then Full.Configuration.Is_Set
         and then Full.Configuration.Rules.Length = 5,
         "GetBucketEncryption outer or list presence mismatch");
      Require
        (Sparse.Configuration.Rules.Length = 2
         and then not Sparse.Configuration.Rules.Element (1).
           Default_Encryption.Is_Set
         and then Sparse.Configuration.Rules.Element (2).
           Blocked_Types.Is_Set
         and then not Sparse.Configuration.Rules.Element (2).
           Blocked_Types.Types_Is_Set
         and then Sparse.Configuration.Rules.Element (2).
           Blocked_Types.Types.Is_Empty,
         "GetBucketEncryption optional structure presence mismatch");
      Require
        (First.Default_Encryption.Is_Set
         and then First.Default_Encryption.Algorithm =
           Encryption.AES256_Encryption
         and then First.Default_Encryption.KMS_Master_Key_ID.Is_Set
         and then US.To_String
           (First.Default_Encryption.KMS_Master_Key_ID.Value) = ""
         and then First.Bucket_Key_Enabled.Is_Set
         and then First.Bucket_Key_Enabled.Value
         and then First.Blocked_Types.Is_Set
         and then First.Blocked_Types.Types_Is_Set
         and then First.Blocked_Types.Types.Length = 2
         and then First.Blocked_Types.Types.Element (1) =
           Encryption.No_Blocked_Encryption
         and then First.Blocked_Types.Types.Element (2) =
           Encryption.SSE_C_Blocked
         and then Full.Configuration.Rules.Element (2).
           Default_Encryption.Algorithm = Encryption.FSx_Encryption
         and then Full.Configuration.Rules.Element (3).
           Default_Encryption.Algorithm = Encryption.Backup_Encryption
         and then Full.Configuration.Rules.Element (4).
           Default_Encryption.Algorithm = Encryption.KMS_Encryption
         and then Full.Configuration.Rules.Element (5).
           Default_Encryption.Algorithm = Encryption.KMS_DSSE_Encryption,
         "GetBucketEncryption typed value mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration/>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule>" &
        "<ApplyServerSideEncryptionByDefault/>" &
        "</Rule></ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule>" &
        "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>aes256" &
        "</SSEAlgorithm></ApplyServerSideEncryptionByDefault>" &
        "</Rule></ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule>" &
        "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>AES256" &
        "</SSEAlgorithm><SSEAlgorithm>AES256</SSEAlgorithm>" &
        "</ApplyServerSideEncryptionByDefault></Rule>" &
        "</ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule>" &
        "<BucketKeyEnabled>TRUE</BucketKeyEnabled>" &
        "</Rule></ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule>" &
        "<BlockedEncryptionTypes><EncryptionType>SSE-KMS</EncryptionType>" &
        "</BlockedEncryptionTypes></Rule>" &
        "</ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration value=""x"">" &
        "<Rule/></ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration xmlns=""urn:wrong"">" &
        "<Rule/></ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration xmlns=""http://s3." &
        "amazonaws.com/doc/2006-03-01/""><Rule xmlns=""""/>" &
        "</ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE ServerSideEncryptionConfiguration [" &
        "<!ENTITY x 'AES256'>]><ServerSideEncryptionConfiguration><Rule>" &
        "<ApplyServerSideEncryptionByDefault><SSEAlgorithm>&x;" &
        "</SSEAlgorithm></ApplyServerSideEncryptionByDefault></Rule>" &
        "</ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<?probe value?><ServerSideEncryptionConfiguration><Rule/>" &
        "</ServerSideEncryptionConfiguration>");
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule>" &
        Character'Val (255) & "</Rule></ServerSideEncryptionConfiguration>");

   declare
      Payload : constant String :=
        "<ServerSideEncryptionConfiguration><Rule><BucketKeyEnabled>" &
        "false</BucketKeyEnabled></Rule>" &
        "</ServerSideEncryptionConfiguration>";
      --  This fixed reference has depth three, three elements, and five text
      --  bytes; each field below is the exact caller-selected test boundary.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth => 3, Maximum_Elements => 3,
         Maximum_Text_Bytes => 5);
      Ignored : constant Low_Level.Get_Bucket_Encryption_Outcome :=
        Low_Level.Decode_Get_Bucket_Encryption_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length - 1,
                    Maximum_Depth => 3, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 5));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 2, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 5));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 2,
                    Maximum_Text_Bytes => 5));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 4));
   end;

   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule/>" &
        "</ServerSideEncryptionConfiguration>",
      Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule/>" &
        "</ServerSideEncryptionConfiguration>",
      Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule/>" &
        "</ServerSideEncryptionConfiguration>",
      Request_ID => "request" & Character'Val (10));
   Expect_Invalid_Response
     (200, "<ServerSideEncryptionConfiguration><Rule/>" &
        "</ServerSideEncryptionConfiguration>",
      Host_ID => "host" & Character'Val (13));
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Bucket_Encryption_Outcome :=
        Low_Level.Decode_Get_Bucket_Encryption_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "GetBucketEncryption identifier boundary mismatch");
   end;
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Bucket_Encryption_Outcome :=
           Low_Level.Decode_Get_Bucket_Encryption_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) =
              "ServerSideEncryptionConfigurationNotFoundError",
            "GetBucketEncryption typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 68 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 4,
         Maximum_Text_Bytes => 68);
      Ignored : constant Low_Level.Get_Bucket_Encryption_Outcome :=
        Low_Level.Decode_Get_Bucket_Encryption_Response
          (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length - 1,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 68));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 1, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 68));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 2, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 68));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 67));
   end;
   Expect_Invalid_Response (403, "");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_CORS
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Bucket_Encryption_Outcome :=
              Low_Level.Execute_Get_Bucket_Encryption (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "GetBucketEncryption cross-operation execution");
   end;

   Ada.Text_IO.Put_Line
     ("S3 GetBucketEncryption deterministic corpus: OK");
end S3_Get_Bucket_Encryption_Corpus;
