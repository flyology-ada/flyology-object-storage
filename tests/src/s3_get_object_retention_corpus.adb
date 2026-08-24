with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Object_Retention_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Get_Object_Retention_Outcome_Kind;
   use type Object_Lock.Retention_Mode;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>NoSuchKey</Code><Message>missing</Message>" &
     "<Resource>/example-bucket/object</Resource></Error>";
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  One alternate success-class status plus representative HTTP failure
   --  classes prove that only the model's exact 200 status is successful.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);
   --  This is the production object-key validator's established boundary.
   Key_Boundary : constant Positive := 1_024;
   --  This is the shared modeled version-ID boundary used by object queries.
   Version_Boundary : constant Positive :=
     Flyology.Object_Storage.S3.Deletions.Maximum_Version_ID_Length;
   --  This is the established response-header admission boundary and not a
   --  new GetObjectRetention resource policy.
   Header_Boundary : constant Positive := 8_192;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Request
     (Bucket  : String := "example-bucket";
      Key     : String := "object";
      Version : String := "";
      Payer   : String := "";
      Owner   : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_Retention
                (Origin, Low_Level.Path_Style, Bucket, Key,
                 (Version_ID => US.To_Unbounded_String (Version),
                  Request_Payer => US.To_Unbounded_String (Payer),
                  Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Prepared);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require (Raised, "GetObjectRetention admitted invalid request");
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
            Outcome : constant Low_Level.Get_Object_Retention_Outcome :=
              Low_Level.Decode_Get_Object_Retention_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "GetObjectRetention admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Parameters : constant Low_Level.Get_Object_Retention_Parameters :=
        (Version_ID => US.To_Unbounded_String ("version one"),
         Request_Payer => US.To_Unbounded_String ("requester"),
         Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012"));
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", "path/to object",
           Parameters, Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Retention
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", "path/to object",
           Parameters, Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/path/to%20object?retention&versionId=" &
           "version%20one"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetObjectRetention path-style projection mismatch");
      Require
        (Low_Level.Target (Hosted) =
           "/path/to%20object?retention&versionId=version%20one"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetObjectRetention virtual-hosted projection mismatch");
   end;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Prepared) = "/example-bucket/object?retention"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared), "x-amz-request-payer") = 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared),
            "x-amz-expected-bucket-owner") = 0,
         "GetObjectRetention optional omission mismatch");
   end;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Key => "");
   Expect_Invalid_Request
     (Key => String'(1 .. Key_Boundary + 1 => 'k'));
   Expect_Invalid_Request
     (Version => String'(1 .. Version_Boundary + 1 => 'v'));
   Expect_Invalid_Request (Version => "bad" & Character'Val (0));
   Expect_Invalid_Request (Payer => "Requester");
   Expect_Invalid_Request (Payer => "requester,other");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));

   declare
      Exact_Key : constant String := String'(1 .. Key_Boundary => 'k');
      Exact_Version : constant String :=
        String'(1 .. Version_Boundary => 'v');
      Exact_Owner : constant String :=
        String'(1 .. Header_Boundary => 'o');
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", Exact_Key,
           (Version_ID => US.To_Unbounded_String (Exact_Version),
            Request_Payer => US.Null_Unbounded_String,
            Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Prepared);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response (200, "");
      Empty : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (200, "<Retention/>");
      Governance : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (200, "<Retention><Mode>GOVERNANCE</Mode></Retention>");
      Compliance : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (200, "<Retention xmlns=""http://s3.amazonaws.com/doc/" &
             "2006-03-01/""><Mode>COMPLIANCE</Mode>" &
             "<RetainUntilDate>2028-02-29T23:59:59.123456789+23:59" &
             "</RetainUntilDate></Retention>");
      Date_Only : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (200, "<Retention><RetainUntilDate>2027-01-02T03:04:05Z" &
             "</RetainUntilDate></Retention>");
      Reverse_Order : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (200, "<Retention><RetainUntilDate>2029-03-04T05:06:07Z" &
             "</RetainUntilDate><Mode>GOVERNANCE</Mode></Retention>");
   begin
      Require
        (Absent.Kind = Low_Level.Object_Retention_Found
         and then not Absent.Retention.Is_Set
         and then Absent.Retention.Mode = Object_Lock.Retention_Mode_Absent
         and then US.Length (Absent.Retention.Retain_Until_Date) = 0,
         "GetObjectRetention absent payload mismatch");
      Require
        (Empty.Retention.Is_Set
         and then Empty.Retention.Mode = Object_Lock.Retention_Mode_Absent
         and then US.Length (Empty.Retention.Retain_Until_Date) = 0,
         "GetObjectRetention nested absence mismatch");
      Require
        (Governance.Retention.Mode = Object_Lock.Governance_Retention
         and then Compliance.Retention.Mode = Object_Lock.Compliance_Retention
         and then US.To_String (Compliance.Retention.Retain_Until_Date) =
           "2028-02-29T23:59:59.123456789+23:59"
         and then Date_Only.Retention.Mode = Object_Lock.Retention_Mode_Absent
         and then US.To_String (Date_Only.Retention.Retain_Until_Date) =
           "2027-01-02T03:04:05Z"
         and then Reverse_Order.Retention.Mode =
           Object_Lock.Governance_Retention
         and then US.To_String (Reverse_Order.Retention.Retain_Until_Date) =
           "2029-03-04T05:06:07Z",
         "GetObjectRetention value mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response (200, "<Retention><Unknown/></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><Mode>GOVERNANCE</Mode>" &
        "<Mode>COMPLIANCE</Mode></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>2027-01-02T03:04:05Z" &
        "</RetainUntilDate><RetainUntilDate>2028-01-02T03:04:05Z" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><Mode><Nested/></Mode></Retention>");
   Expect_Invalid_Response (200, "<Retention value=""x""/>");
   Expect_Invalid_Response (200, "<Retention xmlns=""urn:wrong""/>");
   Expect_Invalid_Response
     (200, "<Retention xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Mode xmlns="""">GOVERNANCE</Mode></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><Mode>governance</Mode></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><Mode> GOVERNANCE </Mode></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>0000-01-02T03:04:05Z" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>2027-02-29T03:04:05Z" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>2027-01-02T24:04:05Z" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>2027-01-02T03:04:05.1234567890Z" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>2027-01-02T03:04:05+24:00" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><RetainUntilDate>2027-01-02T03:04:05" &
        "</RetainUntilDate></Retention>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE Retention [<!ENTITY x 'GOVERNANCE'>]>" &
        "<Retention><Mode>&x;</Mode></Retention>");
   Expect_Invalid_Response
     (200, "<?probe value?><Retention><Mode>GOVERNANCE</Mode></Retention>");
   Expect_Invalid_Response
     (200, "<Retention><Mode>" & Character'Val (16#C3#) &
        "</Mode></Retention>");

   declare
      Payload : constant String :=
        "<Retention><Mode>GOVERNANCE</Mode><RetainUntilDate>" &
        "2027-01-02T03:04:05Z</RetainUntilDate></Retention>";
      --  The exact structural and text counts are derived from Payload.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth          => 2,
         Maximum_Elements       => 3,
         Maximum_Text_Bytes     => 30);
      Outcome : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length - 1,
                    Maximum_Depth => 2, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 30));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 1, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 30));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 2, Maximum_Elements => 2,
                    Maximum_Text_Bytes => 30));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 2, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 29));
   end;

   Expect_Invalid_Response
     (200, "<Retention/>", Request_ID =>
        "request" & Character'Val (13));
   Expect_Invalid_Response
     (200, "<Retention/>", Request_ID =>
        String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<Retention/>", Host_ID => "host" & Character'Val (10));
   Expect_Invalid_Response
     (200, "<Retention/>", Host_ID =>
        String'(1 .. Header_Boundary + 1 => 'h'));

   declare
      Exact_Request_ID : constant String :=
        String'(1 .. Header_Boundary => 'r');
      Exact_Host_ID : constant String :=
        String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (403, Error_XML, Exact_Request_ID, Exact_Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Exact_Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Exact_Host_ID,
         "GetObjectRetention exact-boundary identifiers mismatch");
   end;

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Object_Retention_Outcome :=
           Low_Level.Decode_Get_Object_Retention_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Object_Retention_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "NoSuchKey"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "GetObjectRetention typed rejection mismatch");
      end;
   end loop;

   Expect_Invalid_Response (403, "");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");
   declare
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
         Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
         Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes);
      Outcome : constant Low_Level.Get_Object_Retention_Outcome :=
        Low_Level.Decode_Get_Object_Retention_Response
          (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (403, Error_XML,
         Limits =>
           (Maximum_Document_Bytes => Error_XML'Length - 1,
            Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
            Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
            Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes));
   end;

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant Low_Level.Get_Object_Retention_Outcome :=
              Low_Level.Execute_Get_Object_Retention (HTTP, Wrong);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require
        (Raised,
         "GetObjectRetention executor admitted another operation before HTTP");
   end;

   Ada.Text_IO.Put_Line ("S3 GetObjectRetention deterministic corpus: OK");
end S3_Get_Object_Retention_Corpus;
