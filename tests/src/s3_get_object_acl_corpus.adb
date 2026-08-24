with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Object_ACL_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package ACL renames Flyology.Object_Storage.S3.ACL;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Object_ACL_Outcome_Kind;
   use type ACL.Grantee_Type;
   use type ACL.Permission;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message>" &
     "<Resource>/example-bucket/a b</Resource></Error>";
   --  Exact established low-level response-header text ceiling.
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
      Request_Charged : String := ""; Request_ID : String := "";
      Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Object_ACL_Outcome :=
              Low_Level.Decode_Get_Object_ACL_Response
                (Status, Payload, Request_Charged, Request_ID, Host_ID,
                 Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "GetObjectAcl admitted invalid response");
   end Expect_Invalid_Response;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Key : String := "a b";
      Version_ID : String := ""; Request_Payer : String := "";
      Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Object_ACL
                (Origin, Low_Level.Path_Style, Bucket, Key,
                 (Version_ID => US.To_Unbounded_String (Version_ID),
                  Request_Payer => US.To_Unbounded_String (Request_Payer),
                  Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "GetObjectAcl admitted invalid request");
   end Expect_Invalid_Request;

begin
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_ACL
          (Origin, Low_Level.Path_Style, "example-bucket", "a b",
           (Version_ID => US.To_Unbounded_String ("v/1"),
            Request_Payer => US.To_Unbounded_String ("requester"),
            Expected_Bucket_Owner =>
              US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_ACL
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", "a b",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/a%20b?acl&versionId=v%2F1"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetObjectAcl path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/a%20b?acl"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetObjectAcl hosted projection mismatch");
   end;
   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Key => "");
   Expect_Invalid_Request (Key => "a" & Character'Val (0));
   --  One past the shared public 1,024-byte S3 object-key limit.
   Expect_Invalid_Request (Key => String'(1 .. 1_025 => 'k'));
   Expect_Invalid_Request (Version_ID => "v" & Character'Val (0));
   Expect_Invalid_Request
     (Version_ID =>
        String'(1 .. Deletions.Maximum_Version_ID_Length + 1 => 'v'));
   Expect_Invalid_Request (Request_Payer => "owner");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Version : constant String :=
        String'(1 .. Deletions.Maximum_Version_ID_Length => 'v');
      --  External S3 object-key limit documented by the shared public API.
      Exact_Key : constant String := String'(1 .. 1_024 => 'k');
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_ACL
          (Origin, Low_Level.Path_Style, "example-bucket", Exact_Key,
           (Version_ID => US.To_Unbounded_String (Exact_Version),
            Request_Payer => US.To_Unbounded_String ("requester"),
            Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Object_ACL_Outcome :=
        Low_Level.Decode_Get_Object_ACL_Response (200, "");
      Full : constant Low_Level.Get_Object_ACL_Outcome :=
        Low_Level.Decode_Get_Object_ACL_Response
          (200, "<AccessControlPolicy><Owner><DisplayName></DisplayName>" &
             "<ID>owner-id</ID></Owner><AccessControlList>" &
             "<Grant><Grantee" & XSI & " xsi:type=""CanonicalUser"">" &
             "<ID>principal</ID></Grantee>" &
             "<Permission>FULL_CONTROL</Permission></Grant>" &
             "<Grant><Grantee" & XSI & " xsi:type=""Group"">" &
             "<URI>group</URI></Grantee><Permission>READ</Permission>" &
             "</Grant><Grant><Grantee" & XSI &
             " xsi:type=""AmazonCustomerByEmail""/>" &
             "<Permission>WRITE_ACP</Permission></Grant>" &
             "<Grant><Permission>WRITE</Permission></Grant>" &
             "<Grant><Permission>READ_ACP</Permission></Grant>" &
             "<Grant/></AccessControlList></AccessControlPolicy>",
           Request_Charged => "requester");
      First : constant ACL.Grant := Full.Result.Policy.ACL.Grants.Element (1);
   begin
      Require
        (Absent.Kind = Low_Level.Object_ACL_Found
         and then not Absent.Result.Policy.Is_Set
         and then US.Length (Absent.Result.Request_Charged) = 0
         and then Full.Result.Policy.Is_Set
         and then Full.Result.Policy.Policy_Owner.Is_Set
         and then Full.Result.Policy.Policy_Owner.Display_Name.Is_Set
         and then Full.Result.Policy.ACL.Grants.Length = 6
         and then First.Principal.Kind = ACL.Canonical_User
         and then First.Allowed.Value = ACL.Full_Control
         and then Full.Result.Policy.ACL.Grants.Element (2).Principal.Kind =
           ACL.Group_Grantee
         and then Full.Result.Policy.ACL.Grants.Element (2).Allowed.Value =
           ACL.Read
         and then Full.Result.Policy.ACL.Grants.Element (3).Principal.Kind =
           ACL.Amazon_Customer_By_Email
         and then Full.Result.Policy.ACL.Grants.Element (3).Allowed.Value =
           ACL.Write_ACP
         and then Full.Result.Policy.ACL.Grants.Element (4).Allowed.Value =
           ACL.Write
         and then Full.Result.Policy.ACL.Grants.Element (5).Allowed.Value =
           ACL.Read_ACP
         and then not Full.Result.Policy.ACL.Grants.Element
           (6).Principal.Is_Set
         and then not Full.Result.Policy.ACL.Grants.Element (6).Allowed.Is_Set
         and then US.To_String (Full.Result.Request_Charged) = "requester",
         "GetObjectAcl typed success mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><Owner/><Owner/></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee/>" &
        "</Grant></AccessControlList></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" & XSI &
        " xsi:type=""Group"" xsi:type=""CanonicalUser""/></Grant>" &
        "</AccessControlList></AccessControlPolicy>");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy><AccessControlList><Grant><Grantee" & XSI &
        " xsi:type=""Group"" extra=""x""/></Grant></AccessControlList>" &
        "</AccessControlPolicy>");
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
   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>", Request_Charged => "charged");
   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>",
      Request_Charged => "requester" & Character'Val (10));
   Expect_Invalid_Response
     (200, "<AccessControlPolicy/>",
      Request_Charged => String'(1 .. Header_Boundary + 1 => 'r'));

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
      Ignored : constant Low_Level.Get_Object_ACL_Outcome :=
        Low_Level.Decode_Get_Object_ACL_Response
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
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Object_ACL_Outcome :=
        Low_Level.Decode_Get_Object_ACL_Response
          (403, Error_XML, "requester", Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "GetObjectAcl identifier boundary mismatch");
   end;
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Object_ACL_Outcome :=
           Low_Level.Decode_Get_Object_ACL_Response
             (Status, Error_XML, "requester", "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Object_ACL_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied",
            "GetObjectAcl typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 37 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 4,
         Maximum_Text_Bytes => 37);
      Ignored : constant Low_Level.Get_Object_ACL_Outcome :=
        Low_Level.Decode_Get_Object_ACL_Response
          (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length - 1, 2, 4, 37));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 1, 4, 37));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 2, 3, 37));
      Expect_Invalid_Response
        (403, Error_XML, Limits => (Error_XML'Length, 2, 4, 36));
   end;
   Expect_Invalid_Response (403, "");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "key",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Object_ACL_Outcome :=
              Low_Level.Execute_Get_Object_ACL (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "GetObjectAcl cross-operation execution admitted");
   end;

   Ada.Text_IO.Put_Line ("S3 GetObjectAcl deterministic corpus: OK");
end S3_Get_Object_ACL_Corpus;
