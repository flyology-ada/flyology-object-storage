with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Object_Lock_Configuration_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Get_Object_Lock_Configuration_Outcome_Kind;
   use type Object_Lock.Object_Lock_Enabled_Status;
   use type Object_Lock.Retention_Mode;

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
              Low_Level.Prepare_Get_Object_Lock_Configuration
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
        (Raised, "GetObjectLockConfiguration admitted invalid request");
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
              Low_Level.Get_Object_Lock_Configuration_Outcome :=
                Low_Level.Decode_Get_Object_Lock_Configuration_Response
                  (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require
        (Raised, "GetObjectLockConfiguration admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Lock_Configuration
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket",
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?object-lock"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetObjectLockConfiguration path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?object-lock"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetObjectLockConfiguration hosted projection mismatch");
   end;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared),
            "x-amz-expected-bucket-owner") = 0,
         "GetObjectLockConfiguration owner omission mismatch");
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
        Low_Level.Prepare_Get_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Prepared);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response (200, "");
      Empty : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response
          (200, "<ObjectLockConfiguration/>");
      Enabled : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response
          (200, "<ObjectLockConfiguration><ObjectLockEnabled>Enabled" &
             "</ObjectLockEnabled></ObjectLockConfiguration>");
      Empty_Rule : constant
        Low_Level.Get_Object_Lock_Configuration_Outcome :=
          Low_Level.Decode_Get_Object_Lock_Configuration_Response
            (200, "<ObjectLockConfiguration><Rule/>" &
               "</ObjectLockConfiguration>");
      Empty_Default : constant
        Low_Level.Get_Object_Lock_Configuration_Outcome :=
          Low_Level.Decode_Get_Object_Lock_Configuration_Response
            (200, "<ObjectLockConfiguration><Rule><DefaultRetention/>" &
               "</Rule></ObjectLockConfiguration>");
      Large_Days : constant String :=
        "+12345678901234567890123456789012345678901234567890";
      Full : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response
          (200, "<ObjectLockConfiguration xmlns=""http://s3.amazonaws.com/" &
             "doc/2006-03-01/""><Rule><DefaultRetention><Years>-0002" &
             "</Years><Days>" & Large_Days & "</Days><Mode>COMPLIANCE" &
             "</Mode></DefaultRetention></Rule><ObjectLockEnabled>Enabled" &
             "</ObjectLockEnabled></ObjectLockConfiguration>");
   begin
      Require
        (Absent.Kind = Low_Level.Object_Lock_Configuration_Found
         and then not Absent.Configuration.Is_Set,
         "GetObjectLockConfiguration outer absence mismatch");
      Require
        (Empty.Configuration.Is_Set
         and then Empty.Configuration.Enabled =
           Object_Lock.Object_Lock_Enabled_Absent
         and then not Empty.Configuration.Rule.Is_Set,
         "GetObjectLockConfiguration empty payload mismatch");
      Require
        (Enabled.Configuration.Enabled = Object_Lock.Object_Lock_Enabled
         and then Empty_Rule.Configuration.Rule.Is_Set
         and then not Empty_Rule.Configuration.Rule.Default_Value.Is_Set
         and then Empty_Default.Configuration.Rule.Default_Value.Is_Set
         and then Empty_Default.Configuration.Rule.Default_Value.Mode =
           Object_Lock.Retention_Mode_Absent,
         "GetObjectLockConfiguration nested presence mismatch");
      Require
        (Full.Configuration.Enabled = Object_Lock.Object_Lock_Enabled
         and then Full.Configuration.Rule.Default_Value.Mode =
           Object_Lock.Compliance_Retention
         and then Full.Configuration.Rule.Default_Value.Days.Is_Set
         and then US.To_String
           (Full.Configuration.Rule.Default_Value.Days.Text) = Large_Days
         and then Full.Configuration.Rule.Default_Value.Years.Is_Set
         and then US.To_String
           (Full.Configuration.Rule.Default_Value.Years.Text) = "-0002",
         "GetObjectLockConfiguration full value mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Unknown/>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule/><Rule/>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><ObjectLockEnabled>Enabled" &
        "</ObjectLockEnabled><ObjectLockEnabled>Enabled" &
        "</ObjectLockEnabled></ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>1</Days><Days>2</Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Mode>governance</Mode></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days></Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>+</Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>-</Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days> 1</Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>1 </Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>1.0</Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>1x</Days></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Years>--1</Years></DefaultRetention></Rule>" &
        "</ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration><Rule><DefaultRetention>" &
        "<Days>" & Character'Val (255) &
        "</Days></DefaultRetention></Rule></ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration value=""x""/>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration xmlns=""urn:wrong""/>");
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Rule xmlns=""""/></ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE ObjectLockConfiguration [<!ENTITY x 'Enabled'>]>" &
        "<ObjectLockConfiguration><ObjectLockEnabled>&x;" &
        "</ObjectLockEnabled></ObjectLockConfiguration>");
   Expect_Invalid_Response
     (200, "<?probe value?><ObjectLockConfiguration/>");

   declare
      Payload : constant String :=
        "<ObjectLockConfiguration><ObjectLockEnabled>Enabled" &
        "</ObjectLockEnabled><Rule><DefaultRetention>" &
        "<Mode>GOVERNANCE</Mode><Days>+001</Days><Years>-02</Years>" &
        "</DefaultRetention></Rule></ObjectLockConfiguration>";
      --  Exact structural and text limits derive from this fixed payload.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth => 4, Maximum_Elements => 7,
         Maximum_Text_Bytes => 24);
      Outcome : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length - 1,
                    Maximum_Depth => 4, Maximum_Elements => 7,
                    Maximum_Text_Bytes => 24));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 7,
                    Maximum_Text_Bytes => 24));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 4, Maximum_Elements => 6,
                    Maximum_Text_Bytes => 24));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 4, Maximum_Elements => 7,
                    Maximum_Text_Bytes => 23));
   end;

   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration/>", Request_ID =>
        String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<ObjectLockConfiguration/>", Host_ID =>
        "host" & Character'Val (10));
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "GetObjectLockConfiguration identifier boundary mismatch");
   end;

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
           Low_Level.Decode_Get_Object_Lock_Configuration_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Object_Lock_Configuration_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "NoSuchBucket",
            "GetObjectLockConfiguration typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 34 text bytes.
      Exact_Error_Limits : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth          => 2,
         Maximum_Elements       => 4,
         Maximum_Text_Bytes     => 34);
      Outcome : constant Low_Level.Get_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Get_Object_Lock_Configuration_Response
          (403, Error_XML, Limits => Exact_Error_Limits);
      pragma Unreferenced (Outcome);
   begin
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length - 1,
                    Maximum_Depth          => 2,
                    Maximum_Elements       => 4,
                    Maximum_Text_Bytes     => 34));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth          => 1,
                    Maximum_Elements       => 4,
                    Maximum_Text_Bytes     => 34));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth          => 2,
                    Maximum_Elements       => 3,
                    Maximum_Text_Bytes     => 34));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth          => 2,
                    Maximum_Elements       => 4,
                    Maximum_Text_Bytes     => 33));
   end;
   Expect_Invalid_Response (403, "");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", "object",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Outcome : constant
              Low_Level.Get_Object_Lock_Configuration_Outcome :=
                Low_Level.Execute_Get_Object_Lock_Configuration (HTTP, Wrong);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised, "GetObjectLockConfiguration cross-operation execution");
   end;

   Ada.Text_IO.Put_Line
     ("S3 GetObjectLockConfiguration deterministic corpus: OK");
end S3_Get_Object_Lock_Configuration_Corpus;
