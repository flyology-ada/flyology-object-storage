with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Object_Lock_Configuration_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Object_Lock_Configuration_Outcome_Kind;

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
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with alternate successes and representative
   --  provider rejection classes from the shared S3 error contract.
   Rejection_Statuses : constant Status_Array :=
     (201, 202, 204, 400, 403, 404, 409, 412, 429, 500, 503);
   type Text_Array is array (Positive range <>) of US.Unbounded_String;
   --  Pinned SDK checksum enum and exact algorithm-specific headers.
   Algorithms : constant Text_Array :=
     (US.To_Unbounded_String ("CRC32"),
      US.To_Unbounded_String ("CRC32C"),
      US.To_Unbounded_String ("SHA1"),
      US.To_Unbounded_String ("SHA256"),
      US.To_Unbounded_String ("CRC64NVME"),
      US.To_Unbounded_String ("SHA512"),
      US.To_Unbounded_String ("MD5"),
      US.To_Unbounded_String ("XXHASH64"),
      US.To_Unbounded_String ("XXHASH3"),
      US.To_Unbounded_String ("XXHASH128"));
   Checksum_Headers : constant Text_Array :=
     (US.To_Unbounded_String ("x-amz-checksum-crc32"),
      US.To_Unbounded_String ("x-amz-checksum-crc32c"),
      US.To_Unbounded_String ("x-amz-checksum-sha1"),
      US.To_Unbounded_String ("x-amz-checksum-sha256"),
      US.To_Unbounded_String ("x-amz-checksum-crc64nvme"),
      US.To_Unbounded_String ("x-amz-checksum-sha512"),
      US.To_Unbounded_String ("x-amz-checksum-md5"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash64"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash3"),
      US.To_Unbounded_String ("x-amz-checksum-xxhash128"));
   Invalid_Integers : constant Text_Array :=
     (US.To_Unbounded_String (""),
      US.To_Unbounded_String ("+"),
      US.To_Unbounded_String ("-"),
      US.To_Unbounded_String (" 1"),
      US.To_Unbounded_String ("1 "),
      US.To_Unbounded_String ("1.0"),
      US.To_Unbounded_String ("1e3"),
      US.To_Unbounded_String ("--1"));

   function Integer_Value
     (Set : Boolean := False; Text : String := "")
      return Object_Lock.Optional_Integer_Text is
     ((Is_Set => Set, Text => US.To_Unbounded_String (Text)));

   function Configuration
     (Set : Boolean := True;
      Enabled : Object_Lock.Object_Lock_Enabled_Status :=
        Object_Lock.Object_Lock_Enabled_Absent;
      Rule_Set : Boolean := False;
      Default_Set : Boolean := False;
      Mode : Object_Lock.Retention_Mode := Object_Lock.Retention_Mode_Absent;
      Days_Set : Boolean := False;
      Days : String := "";
      Years_Set : Boolean := False;
      Years : String := "") return Object_Lock.Object_Lock_Configuration is
     ((Is_Set => Set,
       Enabled => Enabled,
       Rule =>
         (Is_Set => Rule_Set,
          Default_Value =>
            (Is_Set => Default_Set,
             Mode => Mode,
             Days => Integer_Value (Days_Set, Days),
             Years => Integer_Value (Years_Set, Years)))));

   function Parameters
     (Payer : String := ""; Lock_Token : String := "";
      MD5 : String := ""; Checksum : String := ""; Owner : String := "")
      return Low_Level.Put_Object_Lock_Configuration_Parameters is
     ((Request_Payer => US.To_Unbounded_String (Payer),
       Token => US.To_Unbounded_String (Lock_Token),
       Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner)));

   function Headers (Charged : String := "")
      return Low_Level.Put_Object_Lock_Configuration_Result is
     ((Request_Charged => US.To_Unbounded_String (Charged)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Serialization
     (Value : Object_Lock.Object_Lock_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String :=
              Object_Lock.Serialize_Configuration (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Object_Lock.Malformed_Object_Lock => Raised := True;
      end;
      Require (Raised, "configuration serializer admitted invalid input");
   end Expect_Invalid_Serialization;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket";
      Value : Object_Lock.Object_Lock_Configuration := Configuration;
      Params : Low_Level.Put_Object_Lock_Configuration_Parameters :=
        Parameters;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object_Lock_Configuration
                (Origin, Low_Level.Path_Style, Bucket, Value, Params,
                 Identity, "us-east-1", "20130524T000000Z", Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutObjectLockConfiguration admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Result : Low_Level.Put_Object_Lock_Configuration_Result := Headers;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Put_Object_Lock_Configuration_Outcome :=
                Low_Level.Decode_Put_Object_Lock_Configuration_Response
                  (Status, Payload, Result, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "PutObjectLockConfiguration admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Huge_Days : constant String :=
        "+00012345678901234567890123456789012345678901234567890";
      Huge_Years : constant String :=
        "-98765432109876543210987654321098765432109876543210";
      Full_Value : constant Object_Lock.Object_Lock_Configuration :=
        Configuration
          (Enabled => Object_Lock.Object_Lock_Enabled,
           Rule_Set => True, Default_Set => True,
           Mode => Object_Lock.Governance_Retention,
           Days_Set => True, Days => Huge_Days,
           Years_Set => True, Years => Huge_Years);
      Full : constant String :=
        Object_Lock.Serialize_Configuration (Full_Value);
      Expected : constant String :=
        "<ObjectLockConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><ObjectLockEnabled>Enabled</ObjectLockEnabled>" &
        "<Rule><DefaultRetention><Mode>GOVERNANCE</Mode><Days>" &
        Huge_Days & "</Days><Years>" & Huge_Years &
        "</Years></DefaultRetention></Rule></ObjectLockConfiguration>";
      Required_Text : constant Positive :=
        7 + 10 + Huge_Days'Length + Huge_Years'Length;
   begin
      Require (Full = Expected, "full configuration XML mismatch");
      Require
        (Object_Lock.Serialize_Configuration
           (Configuration (Set => False)) = "",
         "absent configuration did not encode empty payload");
      Require
        (Object_Lock.Serialize_Configuration (Configuration) =
           "<ObjectLockConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
           "2006-03-01/""></ObjectLockConfiguration>",
         "present empty configuration mismatch");
      for Text of Text_Array'
        (US.To_Unbounded_String ("+0"),
         US.To_Unbounded_String ("-0"),
         US.To_Unbounded_String ("000000"),
         US.To_Unbounded_String ("-00042"))
      loop
         declare
            Encoded : constant String := Object_Lock.Serialize_Configuration
              (Configuration
                 (Rule_Set => True, Default_Set => True,
                  Days_Set => True, Days => US.To_String (Text)));
         begin
            Require
              (Ada.Strings.Fixed.Index
                 (Encoded, "<Days>" & US.To_String (Text) & "</Days>") > 0,
               "integer spelling was not preserved");
         end;
      end loop;
      declare
         Exact : constant XML.Parse_Limits :=
           (Full'Length, 4, 7, Required_Text);
         Ignored : constant String :=
           Object_Lock.Serialize_Configuration (Full_Value, Exact);
         pragma Unreferenced (Ignored);
      begin
         Expect_Invalid_Serialization
           (Full_Value, (Full'Length - 1, 4, 7, Required_Text));
         Expect_Invalid_Serialization
           (Full_Value, (Full'Length, 3, 7, Required_Text));
         Expect_Invalid_Serialization
           (Full_Value, (Full'Length, 4, 6, Required_Text));
         Expect_Invalid_Serialization
           (Full_Value, (Full'Length, 4, 7, Required_Text - 1));
      end;
   end;

   Require
     (Ada.Strings.Fixed.Index
        (Object_Lock.Serialize_Configuration
           (Configuration (Enabled => Object_Lock.Object_Lock_Enabled)),
         "<ObjectLockEnabled>Enabled</ObjectLockEnabled>") > 0,
      "enabled-only configuration mismatch");
   Require
     (Ada.Strings.Fixed.Index
        (Object_Lock.Serialize_Configuration
           (Configuration (Rule_Set => True)), "<Rule></Rule>") > 0,
      "empty rule configuration mismatch");
   Require
     (Ada.Strings.Fixed.Index
        (Object_Lock.Serialize_Configuration
           (Configuration (Rule_Set => True, Default_Set => True)),
         "<DefaultRetention></DefaultRetention>") > 0,
      "empty default retention mismatch");
   Require
     (Ada.Strings.Fixed.Index
        (Object_Lock.Serialize_Configuration
           (Configuration
              (Rule_Set => True, Default_Set => True,
               Mode => Object_Lock.Compliance_Retention)),
         "<Mode>COMPLIANCE</Mode>") > 0,
      "compliance mode mismatch");
   Require
     (Ada.Strings.Fixed.Index
        (Object_Lock.Serialize_Configuration
           (Configuration
              (Rule_Set => True, Default_Set => True,
               Years_Set => True, Years => "123")),
         "<Years>123</Years>") > 0,
      "years-only configuration mismatch");

   Expect_Invalid_Serialization
     (Configuration
        (Set => False, Enabled => Object_Lock.Object_Lock_Enabled));
   Expect_Invalid_Serialization
     (Configuration (Set => False, Rule_Set => True));
   Expect_Invalid_Serialization
     (Configuration (Default_Set => True));
   Expect_Invalid_Serialization
     (Configuration
        (Rule_Set => True, Mode => Object_Lock.Governance_Retention));
   Expect_Invalid_Serialization
     (Configuration
        (Rule_Set => True, Default_Set => True, Days => "1"));
   Expect_Invalid_Serialization
     (Configuration
        (Rule_Set => True, Default_Set => True, Years => "1"));
   for Bad of Invalid_Integers loop
      Expect_Invalid_Serialization
        (Configuration
           (Rule_Set => True, Default_Set => True,
            Days_Set => True, Days => US.To_String (Bad)));
      Expect_Invalid_Serialization
        (Configuration
           (Rule_Set => True, Default_Set => True,
            Years_Set => True, Years => US.To_String (Bad)));
   end loop;

   declare
      Value : constant Object_Lock.Object_Lock_Configuration :=
        Configuration
          (Enabled => Object_Lock.Object_Lock_Enabled,
           Rule_Set => True, Default_Set => True,
           Mode => Object_Lock.Governance_Retention,
           Days_Set => True, Days => "30");
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Value,
           Parameters
             (Payer => "requester", Lock_Token => "token /%",
              Checksum => "CRC32", Owner => "123456789012"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Lock_Configuration
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Configuration, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?object-lock",
         "path-style Object Lock configuration target mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?object-lock"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "hosted Object Lock configuration target mismatch");
      for Header of Text_Array'
        (US.To_Unbounded_String ("content-md5"),
         US.To_Unbounded_String ("x-amz-request-payer"),
         US.To_Unbounded_String ("x-amz-bucket-object-lock-token"),
         US.To_Unbounded_String ("x-amz-expected-bucket-owner"),
         US.To_Unbounded_String ("x-amz-sdk-checksum-algorithm"),
         US.To_Unbounded_String ("x-amz-checksum-crc32"))
      loop
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Path), US.To_String (Header)) > 0,
            "signed configuration projection mismatch");
      end loop;
   end;

   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object_Lock_Configuration
             (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
              Parameters (Checksum => US.To_String (Algorithms (Index))),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               US.To_String (Checksum_Headers (Index))) > 0,
            "configuration checksum header mismatch");
      end;
   end loop;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Params => Parameters (Payer => "Requester"));
   Expect_Invalid_Request (Params => Parameters (Checksum => "crc32"));
   Expect_Invalid_Request (Params => Parameters (MD5 => "invalid"));
   Expect_Invalid_Request
     (Params => Parameters
        (Lock_Token => String'(1 .. Header_Boundary + 1 => 't')));
   Expect_Invalid_Request
     (Params => Parameters (Lock_Token => "token" & Character'Val (10)));
   Expect_Invalid_Request
     (Params => Parameters
        (Owner => String'(1 .. Header_Boundary + 1 => 'o')));
   Expect_Invalid_Request
     (Params => Parameters (Owner => "owner" & Character'Val (0)));
   declare
      --  Exact base64 representation of a 16-byte caller-provided MD5.
      Valid_MD5 : constant String := "AAAAAAAAAAAAAAAAAAAAAA==";
      Exact_Token : constant String :=
        String'(1 .. Header_Boundary => 't');
      Exact_Owner : constant String :=
        String'(1 .. Header_Boundary => 'o');
      Token_Request : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
           Parameters
             (Lock_Token => Exact_Token, MD5 => Valid_MD5),
           Identity, "us-east-1", "20130524T000000Z");
      Owner_Request : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
           Parameters (Owner => Exact_Owner, MD5 => Valid_MD5),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Token_Request, Owner_Request);
   begin
      null;
   end;

   declare
      Empty : constant Low_Level.Put_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Put_Object_Lock_Configuration_Response
          (200, "", Headers);
      Whitespace : constant
        Low_Level.Put_Object_Lock_Configuration_Outcome :=
          Low_Level.Decode_Put_Object_Lock_Configuration_Response
            (200, " " & ASCII.HT, Headers ("requester"));
   begin
      Require
        (Empty.Kind = Low_Level.Object_Lock_Configuration_Updated
         and then Whitespace.Kind =
           Low_Level.Object_Lock_Configuration_Updated,
         "configuration exact success mismatch");
   end;
   Expect_Invalid_Response (200, "x");
   Expect_Invalid_Response (200, "", Headers ("Requester"));
   Expect_Invalid_Response
     (200, "", Headers, Request_ID => "r" & Character'Val (10));
   Expect_Invalid_Response
     (200, "", Headers,
      Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Put_Object_Lock_Configuration_Outcome :=
           Low_Level.Decode_Put_Object_Lock_Configuration_Response
             (Status, Error_XML, Headers, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind =
              Low_Level.Put_Object_Lock_Configuration_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "configuration rejection mismatch");
      end;
   end loop;
   declare
      --  Fixed error graph: depth two, three elements, 18 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Error_XML'Length, 2, 3, 18);
      Ignored : constant Low_Level.Put_Object_Lock_Configuration_Outcome :=
        Low_Level.Decode_Put_Object_Lock_Configuration_Response
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
        Low_Level.Prepare_Get_Object_Lock_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Put_Object_Lock_Configuration_Outcome :=
                Low_Level.Execute_Put_Object_Lock_Configuration (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised, "PutObjectLockConfiguration cross-operation admitted");
   end;

   Ada.Text_IO.Put_Line
     ("S3 PutObjectLockConfiguration deterministic corpus: OK");
end S3_Put_Object_Lock_Configuration_Corpus;
