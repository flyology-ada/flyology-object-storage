with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_Ownership_Controls_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Controls renames Flyology.Object_Storage.S3.Bucket_Controls;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Controls.Object_Ownership;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>NoSuchBucket</Code><Message>missing</Message>" &
     "<Resource>/example-bucket</Resource></Error>";
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with another 2xx and representative failures.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);
   --  The established shared response-header boundary is exercised exactly.
   Header_Boundary : constant Positive := 8_192;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Ownership_Controls
                (Origin, Low_Level.Path_Style, Bucket,
                 (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Prepared);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised, "GetBucketOwnershipControls admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status     : Flyology.HTTP.Status_Code;
      Payload    : String;
      Request_ID : String := "";
      Host_ID    : String := "";
      Limits     : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant
              Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
                Low_Level.Decode_Get_Bucket_Ownership_Controls_Response
                  (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require
        (Raised, "GetBucketOwnershipControls admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Ownership_Controls
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Ownership_Controls
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket",
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket?ownershipControls"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetBucketOwnershipControls path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?ownershipControls"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetBucketOwnershipControls hosted projection mismatch");
   end;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Ownership_Controls
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared),
            "x-amz-expected-bucket-owner") = 0,
         "GetBucketOwnershipControls owner omission mismatch");
   end;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Owner : constant String :=
        String'(1 .. Header_Boundary => 'o');
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Ownership_Controls
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Prepared);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
        Low_Level.Decode_Get_Bucket_Ownership_Controls_Response (200, "");
      Full : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
        Low_Level.Decode_Get_Bucket_Ownership_Controls_Response
          (200, "<OwnershipControls xmlns=""http://s3.amazonaws.com/doc/" &
             "2006-03-01/""><Rule><ObjectOwnership>BucketOwnerPreferred" &
             "</ObjectOwnership></Rule><Rule><ObjectOwnership>" &
             "ObjectWriter</ObjectOwnership></Rule><Rule>" &
             "<ObjectOwnership>BucketOwnerEnforced</ObjectOwnership>" &
             "</Rule></OwnershipControls>");
   begin
      Require
        (Absent.Kind = Low_Level.Bucket_Control_Found
         and then not Absent.Configuration.Is_Set
         and then Absent.Configuration.Rules.Is_Empty,
         "GetBucketOwnershipControls outer absence mismatch");
      Require
        (Full.Configuration.Is_Set
         and then Full.Configuration.Rules.Length = 3
         and then Full.Configuration.Rules.Element (1).Ownership =
           Controls.Bucket_Owner_Preferred
         and then Full.Configuration.Rules.Element (2).Ownership =
           Controls.Object_Writer
         and then Full.Configuration.Rules.Element (3).Ownership =
           Controls.Bucket_Owner_Enforced,
         "GetBucketOwnershipControls rule list mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response (200, "<OwnershipControls/>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule/></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Unknown/></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><Unknown/></Rule>" &
        "</OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><ObjectOwnership>ObjectWriter" &
        "</ObjectOwnership><ObjectOwnership>ObjectWriter" &
        "</ObjectOwnership></Rule></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><ObjectOwnership>objectWriter" &
        "</ObjectOwnership></Rule></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><ObjectOwnership> ObjectWriter" &
        "</ObjectOwnership></Rule></OwnershipControls>");
   Expect_Invalid_Response (200, "<OwnershipControls value=""x""/>");
   Expect_Invalid_Response
     (200, "<OwnershipControls xmlns=""urn:wrong""><Rule>" &
        "<ObjectOwnership>ObjectWriter</ObjectOwnership></Rule>" &
        "</OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Rule xmlns=""""/></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE OwnershipControls [<!ENTITY x 'ObjectWriter'>]>" &
        "<OwnershipControls><Rule><ObjectOwnership>&x;" &
        "</ObjectOwnership></Rule></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<?probe value?><OwnershipControls><Rule><ObjectOwnership>" &
        "ObjectWriter</ObjectOwnership></Rule></OwnershipControls>");
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><ObjectOwnership>" &
        Character'Val (255) &
        "</ObjectOwnership></Rule></OwnershipControls>");

   declare
      Payload : constant String :=
        "<OwnershipControls><Rule><ObjectOwnership>BucketOwnerPreferred" &
        "</ObjectOwnership></Rule><Rule><ObjectOwnership>ObjectWriter" &
        "</ObjectOwnership></Rule></OwnershipControls>";
      --  The fixed payload has depth three, five elements, and 32 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth          => 3,
         Maximum_Elements       => 5,
         Maximum_Text_Bytes     => 32);
      Outcome : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
        Low_Level.Decode_Get_Bucket_Ownership_Controls_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length - 1,
                    Maximum_Depth => 3, Maximum_Elements => 5,
                    Maximum_Text_Bytes => 32));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 2, Maximum_Elements => 5,
                    Maximum_Text_Bytes => 32));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 32));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 5,
                    Maximum_Text_Bytes => 31));
   end;

   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><ObjectOwnership>ObjectWriter" &
        "</ObjectOwnership></Rule></OwnershipControls>",
      Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<OwnershipControls><Rule><ObjectOwnership>ObjectWriter" &
        "</ObjectOwnership></Rule></OwnershipControls>",
      Host_ID => "host" & Character'Val (10));
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
        Low_Level.Decode_Get_Bucket_Ownership_Controls_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "GetBucketOwnershipControls identifier boundary mismatch");
   end;

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
           Low_Level.Decode_Get_Bucket_Ownership_Controls_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "NoSuchBucket",
            "GetBucketOwnershipControls typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 34 text bytes.
      Exact_Error_Limits : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth          => 2,
         Maximum_Elements       => 4,
         Maximum_Text_Bytes     => 34);
      Outcome : constant Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
        Low_Level.Decode_Get_Bucket_Ownership_Controls_Response
          (403, Error_XML, Limits => Exact_Error_Limits);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length - 1,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 34));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 1, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 34));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 2, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 34));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 33));
   end;
   Expect_Invalid_Response (403, "");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant
              Low_Level.Get_Bucket_Ownership_Controls_Outcome :=
                Low_Level.Execute_Get_Bucket_Ownership_Controls
                  (HTTP, Wrong);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised, "GetBucketOwnershipControls cross-operation execution");
   end;

   Ada.Text_IO.Put_Line
     ("S3 GetBucketOwnershipControls deterministic corpus: OK");
end S3_Get_Bucket_Ownership_Controls_Corpus;
