with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_ACL_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package ACL renames Flyology.Object_Storage.S3.ACL;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type ACL.Grantee_Type;
   use type ACL.Permission;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message>" &
     "<Resource>/example-bucket</Resource></Error>";
   --  Exact established low-level bucket-control header-text ceiling.
   Header_Boundary : constant Positive := 8_192;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with another 2xx and representative failures.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);
   --  External S3 ACL wire contract: Grantee type is qualified by the W3C
   --  XML Schema-instance namespace; changing it breaks reference responses.
   XSI : constant String :=
     " xmlns:xsi=""http://www.w3.org/2001/XMLSchema-instance""";

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
            Ignored : constant Low_Level.Get_Bucket_ACL_Outcome :=
              Low_Level.Decode_Get_Bucket_ACL_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "GetBucketAcl admitted invalid response");
   end Expect_Invalid_Response;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_ACL
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
      Require (Raised, "GetBucketAcl admitted invalid request");
   end Expect_Invalid_Request;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_ACL
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_ACL
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?acl"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetBucketAcl path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?acl"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetBucketAcl hosted projection mismatch");
   end;
   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_ACL
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Bucket_ACL_Outcome :=
        Low_Level.Decode_Get_Bucket_ACL_Response (200, "");
      Empty : constant Low_Level.Get_Bucket_ACL_Outcome :=
        Low_Level.Decode_Get_Bucket_ACL_Response
          (200, "<AccessControlPolicy><Owner/><AccessControlList/>" &
             "</AccessControlPolicy>");
      Full : constant Low_Level.Get_Bucket_ACL_Outcome :=
        Low_Level.Decode_Get_Bucket_ACL_Response
          (200, "<AccessControlPolicy xmlns=""http://s3.amazonaws.com/doc/" &
             "2006-03-01/""><Owner><DisplayName></DisplayName>" &
             "<ID>owner-id</ID></Owner><AccessControlList>" &
             "<Grant><Grantee" & XSI & " xsi:type=""CanonicalUser"">" &
             "<DisplayName></DisplayName><EmailAddress>mail@example.test" &
             "</EmailAddress><ID>canonical-id</ID><URI>group-uri</URI>" &
             "</Grantee><Permission>FULL_CONTROL</Permission></Grant>" &
             "<Grant><Grantee" & XSI &
             " xsi:type=""AmazonCustomerByEmail""/>" &
             "<Permission>WRITE</Permission></Grant>" &
             "<Grant><Grantee" & XSI & " xsi:type=""Group""/>" &
             "<Permission>WRITE_ACP</Permission></Grant>" &
             "<Grant><Permission>READ</Permission></Grant>" &
             "<Grant><Permission>READ_ACP</Permission></Grant>" &
             "<Grant/></AccessControlList></AccessControlPolicy>");
      First : constant ACL.Grant := Full.Policy.ACL.Grants.Element (1);
   begin
      Require
        (not Absent.Policy.Is_Set
         and then not Absent.Policy.Policy_Owner.Is_Set
         and then not Absent.Policy.ACL.Is_Set
         and then Empty.Policy.Is_Set
         and then Empty.Policy.Policy_Owner.Is_Set
         and then Empty.Policy.ACL.Is_Set
         and then Empty.Policy.ACL.Grants.Is_Empty,
         "GetBucketAcl outer or wrapper presence mismatch");
      Require
        (Full.Policy.Policy_Owner.Is_Set
         and then Full.Policy.Policy_Owner.Display_Name.Is_Set
         and then US.To_String
           (Full.Policy.Policy_Owner.Display_Name.Value) = ""
         and then US.To_String (Full.Policy.Policy_Owner.ID.Value) = "owner-id"
         and then Full.Policy.ACL.Grants.Length = 6
         and then First.Principal.Is_Set
         and then First.Principal.Kind = ACL.Canonical_User
         and then First.Principal.Display_Name.Is_Set
         and then First.Principal.Email_Address.Is_Set
         and then First.Principal.ID.Is_Set
         and then First.Principal.URI.Is_Set
         and then First.Allowed.Is_Set
         and then First.Allowed.Value = ACL.Full_Control
         and then Full.Policy.ACL.Grants.Element (2).Principal.Kind =
           ACL.Amazon_Customer_By_Email
         and then Full.Policy.ACL.Grants.Element (2).Allowed.Value = ACL.Write
         and then Full.Policy.ACL.Grants.Element (3).Principal.Kind =
           ACL.Group_Grantee
         and then Full.Policy.ACL.Grants.Element (3).Allowed.Value =
           ACL.Write_ACP
         and then Full.Policy.ACL.Grants.Element (4).Allowed.Value = ACL.Read
         and then Full.Policy.ACL.Grants.Element (5).Allowed.Value =
           ACL.Read_ACP
         and then not Full.Policy.ACL.Grants.Element (6).Principal.Is_Set
         and then not Full.Policy.ACL.Grants.Element (6).Allowed.Is_Set,
         "GetBucketAcl typed values or enum domains mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><Grant/></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><Owner/><Owner/></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><Owner><ID>a</ID><ID>b</ID></Owner>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee/>" &
        "</Grant></AccessControlList></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" &
        " type=""CanonicalUser""/></Grant></AccessControlList>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" &
        " xmlns:x=""urn:wrong"" x:type=""CanonicalUser""/></Grant>" &
        "</AccessControlList></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" & XSI &
        " xsi:type=""canonicaluser""/></Grant></AccessControlList>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" & XSI &
        " xsi:type=""Group"" extra=""x""/></Grant></AccessControlList>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" & XSI &
        " xsi:type=""Group"" xsi:type=""CanonicalUser""/></Grant>" &
        "</AccessControlList></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" & XSI &
        " xsi:type=""Group""/><Grantee" & XSI &
        " xsi:type=""CanonicalUser""/></Grant></AccessControlList>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant>" &
        "<Permission>READ</Permission><Permission>WRITE</Permission>" &
        "</Grant></AccessControlList></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant>" &
        "<Permission>read</Permission></Grant></AccessControlList>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy value=""x""/>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy xmlns=""urn:wrong""/>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Owner xmlns=""""/></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE AccessControlPolicy [<!ENTITY x 'owner'>]>" &
        "<AccessControlPolicy><Owner><ID>&x;</ID></Owner>" &
        "</AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<?probe value?><AccessControlPolicy/>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy>" & Character'Val (255) &
        "</AccessControlPolicy>");

   declare
      Payload : constant String :=
        "<AccessControlPolicy><Owner><ID>xy</ID></Owner>" &
        "<AccessControlList><Grant/></AccessControlList>" &
        "</AccessControlPolicy>";
      --  This fixed reference has depth three, five elements, and two text
      --  bytes; each field below is the exact caller-selected test boundary.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth => 3, Maximum_Elements => 5,
         Maximum_Text_Bytes => 2);
      Ignored : constant Low_Level.Get_Bucket_ACL_Outcome :=
        Low_Level.Decode_Get_Bucket_ACL_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (200, Payload, Limits => (Payload'Length - 1, 3, 5, 2));
      Expect_Invalid_Response
        (200, Payload, Limits => (Payload'Length, 2, 5, 2));
      Expect_Invalid_Response
        (200, Payload, Limits => (Payload'Length, 3, 4, 2));
      Expect_Invalid_Response
        (200, Payload, Limits => (Payload'Length, 3, 5, 1));
   end;

   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>",
      Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>",
      Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>",
      Request_ID => "request" & Character'Val (10));
   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>",
      Host_ID => "host" & Character'Val (13));
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Bucket_ACL_Outcome :=
        Low_Level.Decode_Get_Bucket_ACL_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "GetBucketAcl identifier boundary mismatch");
   end;
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Bucket_ACL_Outcome :=
           Low_Level.Decode_Get_Bucket_ACL_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied",
            "GetBucketAcl typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 33 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 4,
         Maximum_Text_Bytes => 33);
      Ignored : constant Low_Level.Get_Bucket_ACL_Outcome :=
        Low_Level.Decode_Get_Bucket_ACL_Response
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
            Ignored : constant Low_Level.Get_Bucket_ACL_Outcome :=
              Low_Level.Execute_Get_Bucket_ACL (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "GetBucketAcl cross-operation execution admitted");
   end;

   Ada.Text_IO.Put_Line ("S3 GetBucketAcl deterministic corpus: OK");
end S3_Get_Bucket_ACL_Corpus;
