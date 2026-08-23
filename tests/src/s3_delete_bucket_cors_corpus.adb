with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;

procedure S3_Delete_Bucket_CORS_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;
   use type Low_Level.Delete_Bucket_CORS_Outcome_Kind;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message>" &
     "<Resource>/example-bucket</Resource></Error>";
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   Rejection_Statuses : constant Status_Array :=
     (200, 201, 202, 400, 403, 404, 429, 500);

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Request
     (Bucket : String; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Prepared : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Bucket_CORS
                (Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
                 Low_Level.Path_Style, Bucket,
                 (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Prepared);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require
        (Raised,
         "DeleteBucketCors admitted invalid request input: bucket='" &
         Bucket & "', owner length=" & Owner'Length'Image);
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
            Outcome : constant Low_Level.Delete_Bucket_CORS_Outcome :=
              Low_Level.Decode_Delete_Bucket_CORS_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Outcome);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "DeleteBucketCors admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Legacy_Kind : constant Low_Level.Delete_Bucket_CORS_Outcome_Kind :=
        Low_Level.Delete_Bucket_CORS_Outcome_Kind'Value
          ("BUCKET_CORS_DELETED");
   begin
      Require
        (Legacy_Kind = Low_Level.Bucket_CORS_Deleted,
         "DeleteBucketCors public enumeration literals changed");
   end;

   declare
      Parameters : constant Low_Level.Delete_Bucket_CORS_Parameters :=
        (Expected_Bucket_Owner =>
           US.To_Unbounded_String ("123456789012"));
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket_CORS
          (Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
           Low_Level.Path_Style, "example-bucket", Parameters, Identity,
           "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket_CORS
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", Parameters,
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?cors"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "DeleteBucketCors path-style projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?cors"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "DeleteBucketCors virtual-hosted projection mismatch");
   end;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket_CORS
          (Flyology.HTTP.Parse_Origin ("http://localhost:9000"),
           Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.Null_Unbounded_String), Identity,
           "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Prepared) = "/example-bucket?cors"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Prepared),
            "x-amz-expected-bucket-owner") = 0,
         "DeleteBucketCors owner omission mismatch");
   end;

   Expect_Invalid_Request ("");
   Expect_Invalid_Request ("UPPERCASE");
   declare
      Maximum_Bucket : constant String :=
        "a" & String'(1 .. 61 => 'b') & "c";
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Bucket_CORS
          (Flyology.HTTP.Parse_Origin ("https://s3.example.test"),
           Low_Level.Path_Style, Maximum_Bucket,
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String (String'(1 .. 8_192 => 'o'))),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Prepared);
   begin
      Expect_Invalid_Request ("a" & String'(1 .. 62 => 'b') & "c");
      Expect_Invalid_Request
        ("example-bucket", String'(1 .. 8_193 => 'o'));
   end;
   Expect_Invalid_Request
     ("example-bucket", "owner" & Character'Val (10));

   declare
      Outcome : constant Low_Level.Delete_Bucket_CORS_Outcome :=
        Low_Level.Decode_Delete_Bucket_CORS_Response (204, "");
   begin
      Require
        (Outcome.Kind = Low_Level.Bucket_CORS_Deleted
         and then Outcome.Status = 204,
         "DeleteBucketCors typed success mismatch");
   end;
   Expect_Invalid_Response (204, " ");
   Expect_Invalid_Response (204, "unexpected");
   Expect_Invalid_Response (200, "");

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Delete_Bucket_CORS_Outcome :=
           Low_Level.Decode_Delete_Bucket_CORS_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Delete_Bucket_CORS_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "DeleteBucketCors typed rejection mismatch");
      end;
   end loop;

   Expect_Invalid_Response (403, "");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");
   Expect_Invalid_Response
     (403, "<!DOCTYPE Error [<!ENTITY x 'bad'>]>" &
        "<Error><Code>&x;</Code></Error>");
   Expect_Invalid_Response
     (403, Error_XML, String'(1 .. 8_193 => 'r'));
   Expect_Invalid_Response
     (403, Error_XML, Host_ID => "host" & Character'Val (13));

   declare
      Outcome : constant Low_Level.Delete_Bucket_CORS_Outcome :=
        Low_Level.Decode_Delete_Bucket_CORS_Response
          (403, Error_XML, String'(1 .. 8_192 => 'r'));
      pragma Unreferenced (Outcome);
   begin
      null;
   end;

   declare
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
         Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
         Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes);
      Outcome : constant Low_Level.Delete_Bucket_CORS_Outcome :=
        Low_Level.Decode_Delete_Bucket_CORS_Response
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
      declare
         Exact_Structure : constant XML.Parse_Limits :=
           (Maximum_Document_Bytes => Error_XML'Length,
            Maximum_Depth          => 2,
            Maximum_Elements       => 4,
            Maximum_Text_Bytes     => 33);
         Exact_Outcome : constant Low_Level.Delete_Bucket_CORS_Outcome :=
           Low_Level.Decode_Delete_Bucket_CORS_Response
             (403, Error_XML, Limits => Exact_Structure);
         pragma Unreferenced (Exact_Outcome);
      begin
         Expect_Invalid_Response
           (403, Error_XML,
            Limits =>
              (Maximum_Document_Bytes => Error_XML'Length,
               Maximum_Depth          => 1,
               Maximum_Elements       => 4,
               Maximum_Text_Bytes     => 33));
         Expect_Invalid_Response
           (403, Error_XML,
            Limits =>
              (Maximum_Document_Bytes => Error_XML'Length,
               Maximum_Depth          => 2,
               Maximum_Elements       => 3,
               Maximum_Text_Bytes     => 33));
         Expect_Invalid_Response
           (403, Error_XML,
            Limits =>
              (Maximum_Document_Bytes => Error_XML'Length,
               Maximum_Depth          => 2,
               Maximum_Elements       => 4,
               Maximum_Text_Bytes     => 32));
      end;
   end;
end S3_Delete_Bucket_CORS_Corpus;
