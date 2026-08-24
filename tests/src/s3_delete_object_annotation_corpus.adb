with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.XML;

procedure S3_Delete_Object_Annotation_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Delete_Object_Annotation_Outcome_Kind;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Hosted_Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin
       ("https://example-bucket.s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
   --  Project-policy compatibility value from the shared low-level response
   --  header validator; changing it alters public response admission.
   Header_Boundary : constant Positive := 8_192;
   --  Project-policy compatibility value from the modeled request projector;
   --  changing it alters public request-target admission.
   Target_Boundary : constant Positive := 8_192;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 204 is contrasted with alternate successes and representative
   --  provider rejection classes from the shared S3 error contract.
   Rejection_Statuses : constant Status_Array :=
     (200, 201, 202, 400, 403, 404, 409, 412, 429, 500, 503);

   function Parameters
     (Version : String := ""; Payer : String := "";
      Owner : String := ""; Match : String := "")
      return Low_Level.Delete_Object_Annotation_Parameters is
     ((Version_ID => US.To_Unbounded_String (Version),
       Request_Payer => US.To_Unbounded_String (Payer),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner),
       Object_If_Match => US.To_Unbounded_String (Match)));

   function Headers
     (Version : String := ""; Charged : String := "")
      return Low_Level.Delete_Object_Annotation_Result is
     ((Object_Version_ID => US.To_Unbounded_String (Version),
       Request_Charged => US.To_Unbounded_String (Charged)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Key : String := "key";
      Annotation : String := "name";
      Params : Low_Level.Delete_Object_Annotation_Parameters := Parameters;
      Case_Name : String := "unspecified")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Delete_Object_Annotation
                (Origin, Low_Level.Path_Style, Bucket, Key, Annotation,
                 Params, Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised,
         "DeleteObjectAnnotation admitted invalid request: " & Case_Name);
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Result : Low_Level.Delete_Object_Annotation_Result := Headers;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Delete_Object_Annotation_Outcome :=
              Low_Level.Decode_Delete_Object_Annotation_Response
                (Status, Payload, Result, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "DeleteObjectAnnotation admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Object_Annotation
          (Origin, Low_Level.Path_Style, "example-bucket", "dir/a b%", "n /%",
           Parameters
             (Version => "v /%", Payer => "requester",
              Owner => "123456789012", Match => "etag-opaque"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Object_Annotation
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           "dir/a b%", "", Parameters, Identity, "us-east-1",
           "20130524T000000Z");
      Canonical : constant String := Low_Level.Canonical_Request (Path);
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/dir/a%20b%25?annotation&" &
           "annotationName=n%20%2F%25&versionId=v%20%2F%25",
         "DeleteObjectAnnotation path target mismatch");
      Require
        (Low_Level.Target (Hosted) =
           "/dir/a%20b%25?annotation&annotationName"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "DeleteObjectAnnotation hosted target mismatch: " &
           Low_Level.Target (Hosted));
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-object-if-match") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-object-if-match:etag-opaque") > 0,
         "DeleteObjectAnnotation signed header projection mismatch");
   end;

   Expect_Invalid_Request (Bucket => "", Case_Name => "empty bucket");
   Expect_Invalid_Request
     (Bucket => "UPPERCASE", Case_Name => "uppercase bucket");
   Expect_Invalid_Request (Key => "", Case_Name => "empty key");
   Expect_Invalid_Request
     (Params => Parameters (Payer => "Requester"),
      Case_Name => "payer case");
   Expect_Invalid_Request
     (Params => Parameters (Payer => "requesters"),
      Case_Name => "payer spelling");
   Expect_Invalid_Request
     (Params => Parameters (Owner => "owner" & Character'Val (10)),
      Case_Name => "owner newline");
   Expect_Invalid_Request
     (Params => Parameters (Match => "etag" & Character'Val (13)),
      Case_Name => "match return");
   Expect_Invalid_Request
     (Annotation => String'(1 .. Target_Boundary => 'a'),
      Case_Name => "target above established 8192-byte ceiling");

   declare
      One_Byte_Key : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Object_Annotation
          (Origin, Low_Level.Path_Style, "example-bucket", "k", "",
           Parameters (Payer => "requester"), Identity, "us-east-1",
           "20130524T000000Z");
      pragma Unreferenced (One_Byte_Key);
   begin
      null;
   end;

   declare
      Outcome : constant Low_Level.Delete_Object_Annotation_Outcome :=
        Low_Level.Decode_Delete_Object_Annotation_Response
          (204, "", Headers ("generation-1", "requester"),
           "request-id", "host-id");
   begin
      Require
        (Outcome.Kind = Low_Level.Object_Annotation_Deleted
         and then Outcome.Status = 204
         and then US.To_String (Outcome.Result.Object_Version_ID) =
           "generation-1"
         and then US.To_String (Outcome.Result.Request_Charged) =
           "requester",
         "DeleteObjectAnnotation exact success mismatch");
   end;
   Expect_Invalid_Response (204, " ");
   Expect_Invalid_Response (204, "x");
   Expect_Invalid_Response (204, "", Headers (Charged => "Requester"));
   Expect_Invalid_Response
     (204, "", Headers (Version => "v" & Character'Val (1)));
   Expect_Invalid_Response
     (204, "", Headers, Request_ID => "r" & Character'Val (10));
   Expect_Invalid_Response
     (204, "", Headers, Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   declare
      Exact_Version : constant String :=
        String'(1 .. Header_Boundary => 'v');
      Exact : constant Low_Level.Delete_Object_Annotation_Outcome :=
        Low_Level.Decode_Delete_Object_Annotation_Response
          (204, "", Headers (Version => Exact_Version));
   begin
      Require
        (US.To_String (Exact.Result.Object_Version_ID) = Exact_Version,
         "DeleteObjectAnnotation exact header boundary rejected");
   end;
   Expect_Invalid_Response
     (204, "", Headers
        (Version => String'(1 .. Header_Boundary + 1 => 'v')));

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Delete_Object_Annotation_Outcome :=
           Low_Level.Decode_Delete_Object_Annotation_Response
             (Status, Error_XML, Headers, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Delete_Object_Annotation_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "DeleteObjectAnnotation rejection mismatch");
      end;
   end loop;
   declare
      --  Fixed error graph: depth two, three elements, 18 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 3,
         Maximum_Text_Bytes => 18);
      Ignored : constant Low_Level.Delete_Object_Annotation_Outcome :=
        Low_Level.Decode_Delete_Object_Annotation_Response
          (403, Error_XML, Headers, Limits => Exact);
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
      --  One client slot is the smallest selectable capacity and suffices
      --  because operation mismatch must be rejected before call admission.
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Delete_Object
          (Origin, Low_Level.Path_Style, "example-bucket", "key",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Delete_Object_Annotation_Outcome :=
              Low_Level.Execute_Delete_Object_Annotation (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "DeleteObjectAnnotation cross-operation admitted");
   end;

   Ada.Text_IO.Put_Line
     ("S3 DeleteObjectAnnotation deterministic corpus: OK");
end S3_Delete_Object_Annotation_Corpus;
