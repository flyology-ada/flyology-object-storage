with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;

procedure S3_Put_Bucket_Controls_Corpus is
   package Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package US renames Ada.Strings.Unbounded;
   use type Controls.Abac_Status;
   use type Controls.Accelerate_Status;
   use type Controls.Payer;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;

   --  External SigV4/S3 reference fixture. Values make exact signed requests
   --  deterministic and have no product-policy effect.
   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Hosted_Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin
       ("https://example-bucket.s3.example.test");
   Owner : constant String := "123456789012";
   Namespace : constant String :=
     " xmlns=""http://s3.amazonaws.com/doc/2006-03-01/""";
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
   --  Test-reference latency only: exact-operation mismatch must fail before
   --  HTTP, so this bounds regression delay rather than product behavior.
   Pre_Admission_Timeout : constant Duration := 0.01;
   --  Test-reference classification for the established low-level header
   --  ceiling; exact and one-past cases must move with that shared boundary.
   Maximum_Header_Text_Bytes : constant Positive := 8_192;

   type Text_Vector is array (Positive range <>) of US.Unbounded_String;
   --  Pinned-model external enum domain. Every algorithm must generate and
   --  sign its corresponding checksum header; changes require model review.
   Algorithms : constant Text_Vector :=
     (US.To_Unbounded_String ("CRC32"),
      US.To_Unbounded_String ("CRC32C"),
      US.To_Unbounded_String ("CRC64NVME"),
      US.To_Unbounded_String ("SHA1"),
      US.To_Unbounded_String ("SHA256"),
      US.To_Unbounded_String ("SHA512"),
      US.To_Unbounded_String ("MD5"),
      US.To_Unbounded_String ("XXHASH64"),
      US.To_Unbounded_String ("XXHASH3"),
      US.To_Unbounded_String ("XXHASH128"));
   Checksum_Headers : constant Text_Vector :=
     (US.To_Unbounded_String ("x-amz-checksum-crc32"),
      US.To_Unbounded_String ("x-amz-checksum-crc32c"),
      US.To_Unbounded_String ("x-amz-checksum-crc64nvme"),
      US.To_Unbounded_String ("x-amz-checksum-sha1"),
      US.To_Unbounded_String ("x-amz-checksum-sha256"),
      US.To_Unbounded_String ("x-amz-checksum-sha512"),
      US.To_Unbounded_String ("x-amz-checksum-md5"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash64"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash3"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash128"));

   function Parameters
     (Checksum : String := ""; MD5 : String := ""; Owner_Value : String := "")
      return Low_Level.Put_Bucket_Control_Parameters is
     ((Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner_Value)));

   function Prepare_With_Checksum
     (Index : Positive) return Low_Level.Prepared_Request
   is
      Value : constant String := US.To_String (Algorithms (Index));
   begin
      --  Derived test distribution: modulo five rotates the ten external
      --  algorithms across every operation without changing product policy.
      case Index mod 5 is
         when 0 =>
            return Low_Level.Prepare_Put_Bucket_Abac
              (Origin, Low_Level.Path_Style, "example-bucket",
               Controls.Abac_Enabled, Parameters (Checksum => Value),
               Identity, "us-east-1", "20130524T000000Z");
         when 1 =>
            return Low_Level.Prepare_Put_Bucket_Accelerate_Configuration
              (Origin, Low_Level.Path_Style, "example-bucket",
               Controls.Accelerate_Enabled, Parameters (Checksum => Value),
               Identity, "us-east-1", "20130524T000000Z");
         when 2 =>
            return Low_Level.Prepare_Put_Bucket_Request_Payment
              (Origin, Low_Level.Path_Style, "example-bucket",
               Controls.Requester, Parameters (Checksum => Value),
               Identity, "us-east-1", "20130524T000000Z");
         when 3 =>
            return Low_Level.Prepare_Put_Public_Access_Block
              (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
               Parameters (Checksum => Value), Identity, "us-east-1",
               "20130524T000000Z");
         when others =>
            return Low_Level.Prepare_Put_Bucket_Policy
              (Origin, Low_Level.Path_Style, "example-bucket", "policy",
               (Content_MD5 => US.Null_Unbounded_String,
                Checksum_Algorithm => US.To_Unbounded_String (Value),
                Confirm_Remove_Self_Access => (others => <>),
                Expected_Bucket_Owner => US.Null_Unbounded_String),
               Identity, "us-east-1", "20130524T000000Z");
      end case;
   end Prepare_With_Checksum;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Decode_Put_Bucket_Control_Response (Status, Payload);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response =>
            Raised := True;
      end;
      Require (Raised, "bucket-control PUT response was admitted");
   end Expect_Invalid_Response;

begin
   Require
     (Controls.Serialize_Abac (Controls.Abac_Enabled) =
        "<AbacStatus" & Namespace & "><Status>Enabled</Status></AbacStatus>"
      and then Controls.Serialize_Abac (Controls.Abac_Disabled) =
        "<AbacStatus" & Namespace & "><Status>Disabled</Status></AbacStatus>"
      and then Controls.Parse_Abac
        (Controls.Serialize_Abac (Controls.Abac_Status_Absent)) =
          Controls.Abac_Status_Absent,
      "ABAC serialization domain mismatch");
   Require
     (Controls.Parse_Accelerate
        (Controls.Serialize_Accelerate (Controls.Accelerate_Suspended)) =
          Controls.Accelerate_Suspended
      and then Controls.Parse_Request_Payment
        (Controls.Serialize_Request_Payment (Controls.Bucket_Owner)) =
          Controls.Bucket_Owner,
      "bucket-control enum round trip mismatch");

   declare
      Public_Access : constant Controls.Public_Access_Block_Configuration :=
        (Block_Public_ACLs       => (Is_Set => True, Value => True),
         Ignore_Public_ACLs      => (Is_Set => True, Value => False),
         Block_Public_Policy     => (Is_Set => True, Value => True),
         Restrict_Public_Buckets => (Is_Set => True, Value => False));
      Parsed : constant Controls.Public_Access_Block_Configuration :=
        Controls.Parse_Public_Access_Block
          (Controls.Serialize_Public_Access_Block (Public_Access));
   begin
      Require
        (Parsed.Block_Public_ACLs.Is_Set
         and then Parsed.Block_Public_ACLs.Value
         and then Parsed.Ignore_Public_ACLs.Is_Set
         and then not Parsed.Ignore_Public_ACLs.Value
         and then Parsed.Block_Public_Policy.Is_Set
         and then Parsed.Block_Public_Policy.Value
         and then Parsed.Restrict_Public_Buckets.Is_Set
         and then not Parsed.Restrict_Public_Buckets.Value,
         "public-access-block serialization mismatch");
   end;

   declare
      Abac : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Abac_Enabled, Parameters (Owner_Value => Owner), Identity,
           "us-east-1", "20130524T000000Z");
      Accelerate : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Accelerate_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Accelerate_Suspended, Parameters (Owner_Value => Owner),
           Identity, "us-east-1", "20130524T000000Z");
      Payment : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Request_Payment
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Requester, Parameters (Owner_Value => Owner), Identity,
           "us-east-1", "20130524T000000Z");
      Public_Access : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Public_Access_Block
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Parameters (Owner_Value => Owner), Identity, "us-east-1",
           "20130524T000000Z");
      Policy : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Policy
          (Origin, Low_Level.Path_Style, "example-bucket", "policy",
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.Null_Unbounded_String,
            Confirm_Remove_Self_Access => (Is_Set => True, Value => True),
            Expected_Bucket_Owner => US.To_Unbounded_String (Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted_Abac : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Controls.Abac_Enabled, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
      Hosted_Accelerate : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Accelerate_Configuration
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Controls.Accelerate_Enabled, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
      Hosted_Payment : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Request_Payment
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Controls.Requester, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
      Hosted_Public_Access : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Public_Access_Block
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           (others => <>), Parameters, Identity, "us-east-1",
           "20130524T000000Z");
      Hosted_Policy : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Policy
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           "policy",
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.Null_Unbounded_String,
            Confirm_Remove_Self_Access => (others => <>),
            Expected_Bucket_Owner => US.Null_Unbounded_String),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Abac) = "/example-bucket?abac"
         and then Low_Level.Target (Accelerate) =
           "/example-bucket?accelerate"
         and then Low_Level.Target (Payment) =
           "/example-bucket?requestPayment"
         and then Low_Level.Target (Public_Access) =
           "/example-bucket?publicAccessBlock"
         and then Low_Level.Target (Policy) = "/example-bucket?policy",
         "bucket-control PUT targets mismatch");
      Require
        (Low_Level.Target (Hosted_Abac) = "/?abac"
         and then Low_Level.Target (Hosted_Accelerate) = "/?accelerate"
         and then Low_Level.Target (Hosted_Payment) = "/?requestPayment"
         and then Low_Level.Target (Hosted_Public_Access) =
           "/?publicAccessBlock"
         and then Low_Level.Target (Hosted_Policy) = "/?policy"
         and then Low_Level.Authority (Hosted_Abac) =
           "example-bucket.s3.example.test",
         "virtual-hosted bucket-control PUT targets mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Abac), "content-md5") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Accelerate), "content-md5") = 0,
         "bucket-control PUT MD5 projection mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Policy),
            "x-amz-confirm-remove-self-bucket-access") > 0,
         "PutBucketPolicy confirmation header was not signed");

      declare
         HTTP : aliased HTTP_Client.Client (Capacity => 1);
         Raised : Boolean := False;
      begin
         begin
            declare
               Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
                 Low_Level.Execute_Put_Bucket_Request_Payment
                   (HTTP, Abac, Timeout => Pre_Admission_Timeout);
               pragma Unreferenced (Ignored);
            begin
               null;
            end;
         exception
            when Low_Level.Invalid_Request =>
               Raised := True;
         end;
         Require (Raised, "cross-operation bucket-control PUT was executed");
      end;
   end;

   declare
      Exact_Owner : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Abac_Enabled,
           Parameters
             (Owner_Value =>
                String'(1 .. Maximum_Header_Text_Bytes => 'o')),
           Identity, "us-east-1", "20130524T000000Z");
      Canonical_Override : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Abac_Enabled,
           Parameters (MD5 => "AAAAAAAAAAAAAAAAAAAAAA=="), Identity,
           "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Exact_Owner, Canonical_Override);
      Raised_Overlong : Boolean := False;
      Raised_Malformed_MD5 : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Abac
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Controls.Abac_Enabled,
                 Parameters
                   (Owner_Value =>
                      String'(1 .. Maximum_Header_Text_Bytes + 1 => 'o')),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Low_Level.Invalid_Request => Raised_Overlong := True;
      end;
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Abac
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Controls.Abac_Enabled, Parameters (MD5 => "invalid"),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Low_Level.Invalid_Request => Raised_Malformed_MD5 := True;
      end;
      Require
        (Raised_Overlong and then Raised_Malformed_MD5,
         "bucket-control PUT owner or MD5 bound was not enforced");
   end;

   declare
      Policy_Text : constant String := "policy";
      Exact : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Policy
          (Origin, Low_Level.Path_Style, "example-bucket", Policy_Text,
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.Null_Unbounded_String,
            Confirm_Remove_Self_Access => (others => <>),
            Expected_Bucket_Owner => US.Null_Unbounded_String),
           Identity, "us-east-1", "20130524T000000Z",
           (Maximum_Document_Bytes => Policy_Text'Length,
            Maximum_Depth => 1, Maximum_Elements => 1,
            Maximum_Text_Bytes => 1));
      Binary_Safe : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Policy
          (Origin, Low_Level.Path_Style, "example-bucket",
           "p" & Character'Val (0),
           (Content_MD5 => US.Null_Unbounded_String,
            Checksum_Algorithm => US.Null_Unbounded_String,
            Confirm_Remove_Self_Access => (others => <>),
            Expected_Bucket_Owner => US.Null_Unbounded_String),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Exact, Binary_Safe);
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Policy
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Policy_Text & "!",
                 (Content_MD5 => US.Null_Unbounded_String,
                  Checksum_Algorithm => US.Null_Unbounded_String,
                  Confirm_Remove_Self_Access => (others => <>),
                  Expected_Bucket_Owner => US.Null_Unbounded_String),
                 Identity, "us-east-1", "20130524T000000Z",
                 (Maximum_Document_Bytes => Policy_Text'Length,
                  Maximum_Depth => 1, Maximum_Elements => 1,
                  Maximum_Text_Bytes => 1));
            pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutBucketPolicy admitted a one-past policy body");
   end;

   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Prepare_With_Checksum (Index);
         Signed : constant String := Low_Level.Signed_Headers (Prepared);
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Signed, "x-amz-sdk-checksum-algorithm") > 0
            and then Ada.Strings.Fixed.Index
              (Signed, US.To_String (Checksum_Headers (Index))) > 0,
            "bucket-control PUT checksum header mismatch");
      end;
   end loop;

   declare
      Raised_Absent_Payer : Boolean := False;
      Raised_Accelerate_MD5 : Boolean := False;
      Raised_Bad_Checksum : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Request_Payment
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Controls.Payer_Absent, Parameters, Identity, "us-east-1",
                 "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Low_Level.Invalid_Request => Raised_Absent_Payer := True;
      end;
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Accelerate_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Controls.Accelerate_Enabled, Parameters (MD5 => "invalid"),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Low_Level.Invalid_Request => Raised_Accelerate_MD5 := True;
      end;
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Abac
                (Origin, Low_Level.Path_Style, "example-bucket",
                 Controls.Abac_Enabled, Parameters (Checksum => "CRC16"),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin null; end;
      exception
         when Low_Level.Invalid_Request => Raised_Bad_Checksum := True;
      end;
      Require
        (Raised_Absent_Payer and then Raised_Accelerate_MD5
         and then Raised_Bad_Checksum,
         "bucket-control PUT invalid input was admitted");
   end;

   declare
      Success : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response (200, "");
      Whitespace : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response (200, " " & ASCII.LF);
      Rejected : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (403, Error_XML, "request", "host");
   begin
      Require
        (Success.Kind = Low_Level.Bucket_Control_Updated
         and then Whitespace.Kind = Low_Level.Bucket_Control_Updated
         and then Rejected.Kind = Low_Level.Put_Bucket_Control_Rejected
         and then US.To_String (Rejected.Error.Code) = "AccessDenied",
         "bucket-control PUT response outcome mismatch");
   end;
   Expect_Invalid_Response (200, "unexpected");
   Expect_Invalid_Response (403, "<Error><Unknown/></Error>");
end S3_Put_Bucket_Controls_Corpus;
