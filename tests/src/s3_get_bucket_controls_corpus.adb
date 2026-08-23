with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_Controls_Corpus is
   package Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;
   use type Controls.Accelerate_Status;
   use type Controls.Payer;
   use type Low_Level.Addressing_Style;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;

   --  External SigV4/S3 reference fixture: these values make signed requests
   --  and exact protocol documents deterministic. Changing them requires
   --  updating paired assertions, but does not alter production policy.
   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Owner : constant String := "123456789012";
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
   Namespace : constant String :=
     " xmlns=""http://s3.amazonaws.com/doc/2006-03-01/""";
   --  Test-reference latency only: exact-operation mismatch must fail before
   --  HTTP, so this bounds a regression's delay rather than product behavior.
   Pre_Admission_Timeout : constant Duration := 0.01;
   --  Test-reference classification for the established low-level
   --  scalar/header ceiling. This mirrors the shared request projector;
   --  changing it requires changing that public boundary and the paired
   --  exact/one-past regression together.
   Maximum_Header_Text_Bytes : constant Positive := 8_192;

   type Response_Kind is
     (Accelerate_Response,
      Policy_Response,
      Policy_Status_Response,
      Request_Payment_Response,
      Public_Access_Block_Response);

   type Payer_Vector is array (Positive range <>) of US.Unbounded_String;
   --  Negative external-enum references: wrong case and a control-bearing
   --  extension must both remain pre-admission failures.
   Invalid_Payers : constant Payer_Vector :=
     (US.To_Unbounded_String ("Requester"),
      US.To_Unbounded_String ("requester" & ASCII.LF));

   function Expected_Target (Kind : Response_Kind) return String is
     (case Kind is
         when Accelerate_Response => "/?accelerate",
         when Policy_Response => "/?policy",
         when Policy_Status_Response => "/?policyStatus",
         when Request_Payment_Response => "/?requestPayment",
         when Public_Access_Block_Response => "/?publicAccessBlock");

   function Prepare
     (Kind : Response_Kind; Style : Low_Level.Addressing_Style;
      Owner_Value : String; Payer_Value : String := "")
      return Low_Level.Prepared_Request
   is
      Request_Origin : constant Flyology.HTTP.Origin :=
        (if Style = Low_Level.Virtual_Hosted_Style
         then Flyology.HTTP.Parse_Origin
           ("https://example-bucket.s3.example.test")
         else Origin);
      Common : constant Low_Level.Get_Bucket_Control_Parameters :=
        (Expected_Bucket_Owner => US.To_Unbounded_String (Owner_Value));
   begin
      case Kind is
         when Accelerate_Response =>
            return Low_Level.Prepare_Get_Bucket_Accelerate_Configuration
              (Request_Origin, Style, "example-bucket",
               (Expected_Bucket_Owner =>
                  US.To_Unbounded_String (Owner_Value),
                Request_Payer => US.To_Unbounded_String (Payer_Value)),
               Identity, "us-east-1", "20130524T000000Z");
         when Policy_Response =>
            return Low_Level.Prepare_Get_Bucket_Policy
              (Request_Origin, Style, "example-bucket", Common,
               Identity, "us-east-1", "20130524T000000Z");
         when Policy_Status_Response =>
            return Low_Level.Prepare_Get_Bucket_Policy_Status
              (Request_Origin, Style, "example-bucket", Common,
               Identity, "us-east-1", "20130524T000000Z");
         when Request_Payment_Response =>
            return Low_Level.Prepare_Get_Bucket_Request_Payment
              (Request_Origin, Style, "example-bucket", Common,
               Identity, "us-east-1", "20130524T000000Z");
         when Public_Access_Block_Response =>
            return Low_Level.Prepare_Get_Public_Access_Block
              (Request_Origin, Style, "example-bucket", Common,
               Identity, "us-east-1", "20130524T000000Z");
      end case;
   end Prepare;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Response
     (Kind : Response_Kind; Payload : String;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         case Kind is
            when Accelerate_Response =>
               declare
                  Ignored : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
                    Low_Level.Decode_Get_Bucket_Accelerate_Response
                      (200, Payload, Limits => Limits);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            when Policy_Response =>
               declare
                  Ignored : constant Low_Level.Get_Bucket_Policy_Outcome :=
                    Low_Level.Decode_Get_Bucket_Policy_Response
                      (200, Payload, Limits => Limits);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            when Policy_Status_Response =>
               declare
                  Ignored : constant
                    Low_Level.Get_Bucket_Policy_Status_Outcome :=
                      Low_Level.Decode_Get_Bucket_Policy_Status_Response
                        (200, Payload, Limits => Limits);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            when Request_Payment_Response =>
               declare
                  Ignored : constant
                    Low_Level.Get_Bucket_Request_Payment_Outcome :=
                      Low_Level.Decode_Get_Bucket_Request_Payment_Response
                        (200, Payload, Limits => Limits);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
            when Public_Access_Block_Response =>
               declare
                  Ignored : constant
                    Low_Level.Get_Public_Access_Block_Outcome :=
                      Low_Level.Decode_Get_Public_Access_Block_Response
                        (200, Payload, Limits => Limits);
                  pragma Unreferenced (Ignored);
               begin
                  null;
               end;
         end case;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "bucket-control response was admitted");
   end Expect_Invalid_Response;

begin
   for Kind in Response_Kind loop
      declare
         Virtual : constant Low_Level.Prepared_Request :=
           Prepare
             (Kind, Low_Level.Virtual_Hosted_Style, "",
              (if Kind = Accelerate_Response then "requester" else ""));
      begin
         Require
           (Low_Level.Target (Virtual) = Expected_Target (Kind)
            and then Low_Level.Authority (Virtual) =
              "example-bucket.s3.example.test",
            "virtual-hosted bucket-control target mismatch");
      end;
   end loop;

   declare
      Exact : constant Low_Level.Prepared_Request :=
        Prepare
          (Policy_Response, Low_Level.Path_Style,
           String'(1 .. Maximum_Header_Text_Bytes => 'o'));
      pragma Unreferenced (Exact);
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Prepare
                (Policy_Response, Low_Level.Path_Style,
                 String'(1 .. Maximum_Header_Text_Bytes + 1 => 'o'));
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request =>
            Raised := True;
      end;
      Require (Raised, "bucket-control GET admitted an overlong owner");
   end;

   for Invalid_Payer of Invalid_Payers loop
      declare
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Prepared_Request :=
                 Prepare
                   (Accelerate_Response, Low_Level.Path_Style, "",
                    US.To_String (Invalid_Payer));
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Require (Raised, "accelerate GET admitted invalid request payer");
      end;
   end loop;

   declare
      Accelerate : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Accelerate_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Owner),
            Request_Payer => US.To_Unbounded_String ("requester")),
           Identity, "us-east-1", "20130524T000000Z");
      Policy : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Policy
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      Policy_Status : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Policy_Status
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      Payment : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Request_Payment
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      Public_Access : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Public_Access_Block
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Accelerate) = "/example-bucket?accelerate"
         and then Low_Level.Target (Policy) = "/example-bucket?policy"
         and then Low_Level.Target (Policy_Status) =
           "/example-bucket?policyStatus"
         and then Low_Level.Target (Payment) =
           "/example-bucket?requestPayment"
         and then Low_Level.Target (Public_Access) =
           "/example-bucket?publicAccessBlock",
         "bucket-control targets mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Accelerate),
            "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Policy),
            "x-amz-expected-bucket-owner") > 0,
         "bucket-control headers mismatch");

      declare
         HTTP : aliased HTTP_Client.Client (Capacity => 1);
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Get_Bucket_Policy_Outcome :=
                 Low_Level.Execute_Get_Bucket_Policy
                   (HTTP, Accelerate, Timeout => Pre_Admission_Timeout);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Require (Raised, "cross-operation bucket-control GET was executed");
      end;
   end;

   declare
      Accelerate_XML : constant String :=
        "<AccelerateConfiguration" & Namespace & ">" &
        "<Status>Enabled</Status></AccelerateConfiguration>";
      Policy_Status_XML : constant String :=
        "<PolicyStatus" & Namespace & ">" &
        "<IsPublic>false</IsPublic></PolicyStatus>";
      Payment_XML : constant String :=
        "<RequestPaymentConfiguration" & Namespace & ">" &
        "<Payer>Requester</Payer></RequestPaymentConfiguration>";
      Public_Access_XML : constant String :=
        "<PublicAccessBlockConfiguration" & Namespace & ">" &
        "<BlockPublicAcls>true</BlockPublicAcls>" &
        "<IgnorePublicAcls>false</IgnorePublicAcls>" &
        "<BlockPublicPolicy>true</BlockPublicPolicy>" &
        "<RestrictPublicBuckets>false</RestrictPublicBuckets>" &
        "</PublicAccessBlockConfiguration>";
      Accelerate : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
        Low_Level.Decode_Get_Bucket_Accelerate_Response
          (200, Accelerate_XML, Request_Charged => "requester");
      Policy : constant Low_Level.Get_Bucket_Policy_Outcome :=
        Low_Level.Decode_Get_Bucket_Policy_Response
          (200, "{""Version"":""2012-10-17""}");
      Policy_Status : constant Low_Level.Get_Bucket_Policy_Status_Outcome :=
        Low_Level.Decode_Get_Bucket_Policy_Status_Response
          (200, Policy_Status_XML);
      Payment : constant Low_Level.Get_Bucket_Request_Payment_Outcome :=
        Low_Level.Decode_Get_Bucket_Request_Payment_Response
          (200, Payment_XML);
      Public_Access : constant Low_Level.Get_Public_Access_Block_Outcome :=
        Low_Level.Decode_Get_Public_Access_Block_Response
          (200, Public_Access_XML);
   begin
      Require
        (Accelerate.Kind = Low_Level.Bucket_Control_Found
         and then Accelerate.Configuration = Controls.Accelerate_Enabled
         and then US.To_String (Accelerate.Request_Charged) = "requester",
         "accelerate response mismatch");
      Require
         (Policy.Kind = Low_Level.Bucket_Control_Found
         and then US.To_String (Policy.Policy) =
           "{""Version"":""2012-10-17""}",
         "policy response mismatch");
      Require
        (Policy_Status.Kind = Low_Level.Bucket_Control_Found
         and then Policy_Status.Is_Public.Is_Set
         and then not Policy_Status.Is_Public.Value,
         "policy-status response mismatch");
      Require
        (Payment.Kind = Low_Level.Bucket_Control_Found
         and then Payment.Payment = Controls.Requester,
         "request-payment response mismatch");
      Require
        (Public_Access.Kind = Low_Level.Bucket_Control_Found
         and then Public_Access.Configuration.Block_Public_ACLs.Is_Set
         and then Public_Access.Configuration.Block_Public_ACLs.Value
         and then Public_Access.Configuration.Ignore_Public_ACLs.Is_Set
         and then not Public_Access.Configuration.Ignore_Public_ACLs.Value
         and then Public_Access.Configuration.Block_Public_Policy.Is_Set
         and then Public_Access.Configuration.Block_Public_Policy.Value
         and then
           Public_Access.Configuration.Restrict_Public_Buckets.Is_Set
         and then not
           Public_Access.Configuration.Restrict_Public_Buckets.Value,
         "public-access-block response mismatch");
   end;

   declare
      Suspended : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
        Low_Level.Decode_Get_Bucket_Accelerate_Response
          (200, "<AccelerateConfiguration><Status>Suspended</Status>" &
             "</AccelerateConfiguration>");
      Bucket_Owner : constant Low_Level.Get_Bucket_Request_Payment_Outcome :=
        Low_Level.Decode_Get_Bucket_Request_Payment_Response
          (200, "<RequestPaymentConfiguration><Payer>BucketOwner</Payer>" &
             "</RequestPaymentConfiguration>");
   begin
      Require
        (Suspended.Configuration = Controls.Accelerate_Suspended
         and then Bucket_Owner.Payment = Controls.Bucket_Owner,
         "secondary bucket-control enum values mismatch");
   end;

   for Kind in Response_Kind loop
      if Kind /= Policy_Response then
         Expect_Invalid_Response (Kind, " ");
         Expect_Invalid_Response (Kind, "<Unknown/>");
         Expect_Invalid_Response
           (Kind, "<!DOCTYPE x [<!ENTITY e 'bad'>]><x>&e;</x>");
      end if;
   end loop;

   --  Every structured top-level output member is optional in the pinned
   --  model. An exact empty 200 therefore maps to presence-free defaults;
   --  nonempty whitespace remains a malformed XML document.
   declare
      Accelerate : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
        Low_Level.Decode_Get_Bucket_Accelerate_Response (200, "");
      Policy_Status : constant Low_Level.Get_Bucket_Policy_Status_Outcome :=
        Low_Level.Decode_Get_Bucket_Policy_Status_Response (200, "");
      Payment : constant Low_Level.Get_Bucket_Request_Payment_Outcome :=
        Low_Level.Decode_Get_Bucket_Request_Payment_Response (200, "");
      Public_Access : constant Low_Level.Get_Public_Access_Block_Outcome :=
        Low_Level.Decode_Get_Public_Access_Block_Response (200, "");
   begin
      Require
        (Accelerate.Configuration = Controls.Accelerate_Status_Absent
         and then not Policy_Status.Is_Public.Is_Set
         and then Payment.Payment = Controls.Payer_Absent
         and then not Public_Access.Configuration.Block_Public_ACLs.Is_Set
         and then not Public_Access.Configuration.Ignore_Public_ACLs.Is_Set
         and then not Public_Access.Configuration.Block_Public_Policy.Is_Set
         and then not
           Public_Access.Configuration.Restrict_Public_Buckets.Is_Set,
         "absent bucket-control success members were not preserved");
   end;
   Expect_Invalid_Response
     (Accelerate_Response,
      "<AccelerateConfiguration><Status>Enabled</Status>" &
        "<Status>Suspended</Status></AccelerateConfiguration>");
   Expect_Invalid_Response
     (Policy_Status_Response,
      "<PolicyStatus><IsPublic>TRUE</IsPublic></PolicyStatus>");
   Expect_Invalid_Response
     (Request_Payment_Response,
      "<RequestPaymentConfiguration><Payer>Other</Payer>" &
        "</RequestPaymentConfiguration>");
   Expect_Invalid_Response
     (Public_Access_Block_Response,
      "<PublicAccessBlockConfiguration><BlockPublicAcls>1" &
        "</BlockPublicAcls></PublicAccessBlockConfiguration>");
   Expect_Invalid_Response
     (Accelerate_Response,
      "<AccelerateConfiguration xmlns=""urn:foreign"">" &
        "<Status>Enabled</Status></AccelerateConfiguration>");
   Expect_Invalid_Response
     (Policy_Status_Response,
      "<PolicyStatus unexpected=""yes""><IsPublic>false</IsPublic>" &
        "</PolicyStatus>");
   Expect_Invalid_Response
     (Request_Payment_Response,
      "<RequestPaymentConfiguration><Unknown>Requester</Unknown>" &
        "</RequestPaymentConfiguration>");
   Expect_Invalid_Response
     (Public_Access_Block_Response,
      "<PublicAccessBlockConfiguration><BlockPublicAcls><Nested/>" &
        "</BlockPublicAcls></PublicAccessBlockConfiguration>");
   Expect_Invalid_Response
     (Policy_Status_Response,
      "<PolicyStatus><IsPublic>false</IsPublic></PolicyStatus>",
      (Maximum_Document_Bytes => 1_000,
       Maximum_Depth          => 1,
       Maximum_Elements       => 10,
       Maximum_Text_Bytes     => 10));

   declare
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Bucket_Accelerate_Outcome :=
              Low_Level.Decode_Get_Bucket_Accelerate_Response
                (200, "<AccelerateConfiguration/>",
                 Request_Charged => "Requester");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "accelerate GET admitted invalid request-charged");
   end;

   declare
      Policy_Text : constant String := "policy";
      Exact : constant Low_Level.Get_Bucket_Policy_Outcome :=
        Low_Level.Decode_Get_Bucket_Policy_Response
          (200, Policy_Text,
           Limits =>
             (Maximum_Document_Bytes => Policy_Text'Length,
              Maximum_Depth          => 1,
              Maximum_Elements       => 1,
              Maximum_Text_Bytes     => 1));
      Rejected : constant Low_Level.Get_Bucket_Policy_Outcome :=
        Low_Level.Decode_Get_Bucket_Policy_Response
          (403, Error_XML, "request", "host");
      pragma Unreferenced (Exact);
   begin
      Expect_Invalid_Response
        (Policy_Response, Policy_Text & "!",
         (Maximum_Document_Bytes => Policy_Text'Length,
          Maximum_Depth          => 1,
          Maximum_Elements       => 1,
          Maximum_Text_Bytes     => 1));
      Require
        (Rejected.Kind = Low_Level.Get_Bucket_Control_Rejected
         and then US.To_String (Rejected.Error.Code) = "AccessDenied",
         "bucket-control structured rejection mismatch");
   end;
end S3_Get_Bucket_Controls_Corpus;
