with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Object_Legal_Hold_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Get_Object_Legal_Hold_Outcome_Kind;
   use type Object_Lock.Legal_Hold_Status;

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
   --  classes prove that only the model's exact 200 status is successful;
   --  this does not define an exhaustive provider status policy.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);
   --  This is the production object-key validator's established boundary.
   Key_Boundary : constant Positive := 1_024;
   --  This is the shared modeled version-ID bound used by deletion queries;
   --  exact and one-past cases prove the new client does not narrow it.
   Version_Boundary : constant Positive :=
     Flyology.Object_Storage.S3.Deletions.Maximum_Version_ID_Length;
   --  This is the established response-header admission boundary and not a
   --  new GetObjectLegalHold resource policy.
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
              Low_Level.Prepare_Get_Object_Legal_Hold
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
      Require (Raised, "GetObjectLegalHold admitted invalid request");
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
            Outcome : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
              Low_Level.Decode_Get_Object_Legal_Hold_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "GetObjectLegalHold admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Parameters : constant Low_Level.Get_Object_Legal_Hold_Parameters :=
        (Version_ID => US.To_Unbounded_String ("version one"),
         Request_Payer => US.To_Unbounded_String ("requester"),
         Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012"));
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "path/to object",
           Parameters, Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Legal_Hold
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", "path/to object",
           Parameters, Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/path/to%20object?legal-hold&versionId=" &
           "version%20one"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetObjectLegalHold path-style projection mismatch");
      Require
        (Low_Level.Target (Hosted) =
           "/path/to%20object?legal-hold&versionId=version%20one"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetObjectLegalHold virtual-hosted projection mismatch");
   end;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Prepared) =
           "/example-bucket/object?legal-hold"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared), "x-amz-request-payer") = 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared),
            "x-amz-expected-bucket-owner") = 0,
         "GetObjectLegalHold optional omission mismatch");
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
        Low_Level.Prepare_Get_Object_Legal_Hold
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
      Absent : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response (200, "");
      Empty : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response
          (200, "<LegalHold/>");
      On_Value : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response
          (200, "<LegalHold><Status>ON</Status></LegalHold>");
      Off_Value : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response
          (200, "<LegalHold xmlns=""http://s3.amazonaws.com/doc/" &
             "2006-03-01/""><Status>OFF</Status></LegalHold>");
   begin
      Require
        (Absent.Kind = Low_Level.Object_Legal_Hold_Found
         and then not Absent.Legal_Hold.Is_Set
         and then Absent.Legal_Hold.Status =
           Object_Lock.Legal_Hold_Status_Absent,
         "GetObjectLegalHold absent payload mismatch");
      Require
        (Empty.Legal_Hold.Is_Set
         and then Empty.Legal_Hold.Status =
           Object_Lock.Legal_Hold_Status_Absent,
         "GetObjectLegalHold absent status mismatch");
      Require
        (On_Value.Legal_Hold.Status = Object_Lock.Legal_Hold_On
         and then Off_Value.Legal_Hold.Status = Object_Lock.Legal_Hold_Off,
         "GetObjectLegalHold status enum mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response (200, "<LegalHold><Unknown/></LegalHold>");
   Expect_Invalid_Response
     (200, "<LegalHold><Status>ON</Status><Status>OFF</Status></LegalHold>");
   Expect_Invalid_Response
     (200, "<LegalHold><Status><Nested/></Status></LegalHold>");
   Expect_Invalid_Response
     (200, "<LegalHold value=""ON""/>");
   Expect_Invalid_Response
     (200, "<LegalHold xmlns=""urn:wrong""/>");
   Expect_Invalid_Response
     (200, "<LegalHold><Status>on</Status></LegalHold>");
   Expect_Invalid_Response
     (200, "<LegalHold><Status> ON </Status></LegalHold>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE LegalHold [<!ENTITY x 'ON'>]>" &
        "<LegalHold><Status>&x;</Status></LegalHold>");
   Expect_Invalid_Response
     (200, "<?probe value?><LegalHold><Status>ON</Status></LegalHold>");
   Expect_Invalid_Response
     (200, "<LegalHold><Status>" & Character'Val (16#C3#) &
        "</Status></LegalHold>");

   declare
      Payload : constant String :=
        "<LegalHold><Status>ON</Status></LegalHold>";
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth          => 2,
         Maximum_Elements       => 2,
         Maximum_Text_Bytes     => 2);
      Outcome : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length - 1,
                    Maximum_Depth          => 2,
                    Maximum_Elements       => 2,
                    Maximum_Text_Bytes     => 2));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth          => 1,
                    Maximum_Elements       => 2,
                    Maximum_Text_Bytes     => 2));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth          => 2,
                    Maximum_Elements       => 1,
                    Maximum_Text_Bytes     => 2));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth          => 2,
                    Maximum_Elements       => 2,
                    Maximum_Text_Bytes     => 1));
   end;

   Expect_Invalid_Response
     (200, "<LegalHold/>", Request_ID =>
        "request" & Character'Val (13));
   Expect_Invalid_Response
     (200, "<LegalHold/>", Request_ID =>
        String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<LegalHold/>", Host_ID => "host" & Character'Val (10));
   Expect_Invalid_Response
     (200, "<LegalHold/>", Host_ID =>
        String'(1 .. Header_Boundary + 1 => 'h'));

   declare
      Exact_Request_ID : constant String :=
        String'(1 .. Header_Boundary => 'r');
      Exact_Host_ID : constant String :=
        String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response
          (403, Error_XML, Exact_Request_ID, Exact_Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Exact_Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Exact_Host_ID,
         "GetObjectLegalHold exact-boundary identifiers mismatch");
   end;

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
           Low_Level.Decode_Get_Object_Legal_Hold_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Object_Legal_Hold_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "NoSuchKey"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "GetObjectLegalHold typed rejection mismatch");
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
      Outcome : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Get_Object_Legal_Hold_Response
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
        Low_Level.Prepare_Get_Object_Torrent
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant Low_Level.Get_Object_Legal_Hold_Outcome :=
              Low_Level.Execute_Get_Object_Legal_Hold (HTTP, Wrong);
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
         "GetObjectLegalHold executor admitted another operation before HTTP");
   end;

   Ada.Text_IO.Put_Line ("S3 GetObjectLegalHold deterministic corpus: OK");
end S3_Get_Object_Legal_Hold_Corpus;
