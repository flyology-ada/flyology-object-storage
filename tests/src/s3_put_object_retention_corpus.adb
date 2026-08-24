with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Object_Retention_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Object_Retention_Outcome_Kind;

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
   --  Project object-generation policy shared with all version-bound calls.
   Version_Boundary : constant Positive :=
     Deletions.Maximum_Version_ID_Length;
   --  Production object-key validation is explicitly capped at this boundary.
   Key_Boundary : constant Positive := 1_024;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with alternate successes and representative
   --  provider rejection classes from the shared S3 error contract.
   Rejection_Statuses : constant Status_Array :=
     (201, 202, 204, 400, 403, 404, 409, 412, 429, 500, 503);
   type Text_Array is array (Positive range <>) of US.Unbounded_String;
   --  Pinned SDK checksum enum and its exact algorithm-specific headers.
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
   --  Boundary and grammar mutants for the externally fixed ISO-8601 shape.
   Invalid_Dates : constant Text_Array :=
     (US.To_Unbounded_String ("0000-01-01T00:00:00Z"),
      US.To_Unbounded_String ("2027-02-29T00:00:00Z"),
      US.To_Unbounded_String ("2028-01-01T24:00:00Z"),
      US.To_Unbounded_String ("2028-01-01T00:00:00.1234567890Z"),
      US.To_Unbounded_String ("2028-01-01T00:00:00+24:00"),
      US.To_Unbounded_String ("2028-01-01T00:00:00"));

   function Retention
     (Set : Boolean := True;
      Mode : Object_Lock.Retention_Mode := Object_Lock.Governance_Retention;
      Date : String := "2028-02-29T23:59:59Z")
      return Object_Lock.Retention is
     ((Is_Set => Set, Mode => Mode,
       Retain_Until_Date => US.To_Unbounded_String (Date)));

   function Parameters
     (Payer : String := ""; Version : String := "";
      Bypass_Set : Boolean := False; Bypass : Boolean := False;
      MD5 : String := ""; Checksum : String := ""; Owner : String := "")
      return Low_Level.Put_Object_Retention_Parameters is
     ((Request_Payer => US.To_Unbounded_String (Payer),
       Version_ID => US.To_Unbounded_String (Version),
       Bypass_Governance_Retention =>
         (Is_Set => Bypass_Set, Value => Bypass),
       Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner)));

   function Headers (Charged : String := "")
      return Low_Level.Put_Object_Retention_Result is
     ((Request_Charged => US.To_Unbounded_String (Charged)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Serialization
     (Value : Object_Lock.Retention;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String :=
              Object_Lock.Serialize_Retention (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Object_Lock.Malformed_Object_Lock => Raised := True;
      end;
      Require (Raised, "Retention serializer admitted invalid input");
   end Expect_Invalid_Serialization;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Key : String := "key";
      Value : Object_Lock.Retention := Retention;
      Params : Low_Level.Put_Object_Retention_Parameters := Parameters;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object_Retention
                (Origin, Low_Level.Path_Style, Bucket, Key, Value, Params,
                 Identity, "us-east-1", "20130524T000000Z", Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutObjectRetention admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Result : Low_Level.Put_Object_Retention_Result := Headers;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Object_Retention_Outcome :=
              Low_Level.Decode_Put_Object_Retention_Response
                (Status, Payload, Result, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "PutObjectRetention admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Date : constant String := "2028-02-29T23:59:59.123456789+23:59";
      Mode_Text : constant String := "GOVERNANCE";
      Both_Value : constant Object_Lock.Retention :=
        Retention (Date => Date);
      Both : constant String := Object_Lock.Serialize_Retention (Both_Value);
      Compliance : constant String := Object_Lock.Serialize_Retention
        (Retention (Mode => Object_Lock.Compliance_Retention, Date => ""));
      Date_Only : constant String := Object_Lock.Serialize_Retention
        (Retention (Mode => Object_Lock.Retention_Mode_Absent));
      Empty_Root : constant String := Object_Lock.Serialize_Retention
        (Retention (Mode => Object_Lock.Retention_Mode_Absent, Date => ""));
      Absent : constant String := Object_Lock.Serialize_Retention
        (Retention (False, Object_Lock.Retention_Mode_Absent, ""));
      Expected : constant String :=
        "<Retention xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Mode>GOVERNANCE</Mode><RetainUntilDate>" & Date &
        "</RetainUntilDate></Retention>";
      Required_Text : constant Positive := Mode_Text'Length + Date'Length;
   begin
      Require (Both = Expected, "Retention full XML mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Compliance, "<Mode>COMPLIANCE</Mode>") > 0
         and then Ada.Strings.Fixed.Index
           (Compliance, "<RetainUntilDate>") = 0,
         "Retention compliance-only XML mismatch");
      Require
        (Ada.Strings.Fixed.Index (Date_Only, "<Mode>") = 0
         and then Ada.Strings.Fixed.Index
           (Date_Only, "<RetainUntilDate>") > 0,
         "Retention date-only XML mismatch");
      Require
        (Ada.Strings.Fixed.Index (Empty_Root, "<Mode>") = 0
         and then Ada.Strings.Fixed.Index
           (Empty_Root, "<RetainUntilDate>") = 0,
         "Retention empty root mismatch");
      Require (Absent = "", "absent Retention did not encode empty payload");
      declare
         --  Pinned full graph is three elements at depth two with aggregate
         --  scalar text equal to the mode plus timestamp byte counts.
         Exact : constant XML.Parse_Limits :=
           (Maximum_Document_Bytes => Both'Length,
            Maximum_Depth => 2, Maximum_Elements => 3,
            Maximum_Text_Bytes => Required_Text);
         Ignored : constant String :=
           Object_Lock.Serialize_Retention (Both_Value, Exact);
         pragma Unreferenced (Ignored);
      begin
         Expect_Invalid_Serialization
           (Both_Value, (Both'Length - 1, 2, 3, Required_Text));
         Expect_Invalid_Serialization
           (Both_Value, (Both'Length, 1, 3, Required_Text));
         Expect_Invalid_Serialization
           (Both_Value, (Both'Length, 2, 2, Required_Text));
         Expect_Invalid_Serialization
           (Both_Value, (Both'Length, 2, 3, Required_Text - 1));
      end;
   end;
   Expect_Invalid_Serialization
     (Retention (False, Object_Lock.Governance_Retention, ""));
   Expect_Invalid_Serialization
     (Retention (False, Object_Lock.Retention_Mode_Absent,
                 "2028-02-29T23:59:59Z"));
   for Bad_Date of Invalid_Dates loop
      Expect_Invalid_Serialization
        (Retention (Date => US.To_String (Bad_Date)));
   end loop;

   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", "dir/a b%",
           Retention,
           Parameters
             (Payer => "requester", Version => "v /%", Bypass_Set => True,
              Bypass => True, Checksum => "CRC32", Owner => "123456789012"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Retention
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           "dir/a b%",
           Retention (Mode => Object_Lock.Compliance_Retention, Date => ""),
           Parameters (Bypass_Set => True, Bypass => False), Identity,
           "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/dir/a%20b%25?retention&versionId=v%20%2F%25",
         "PutObjectRetention path target mismatch");
      Require
        (Low_Level.Target (Hosted) = "/dir/a%20b%25?retention"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "PutObjectRetention hosted target mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "content-md5") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-bypass-governance-retention") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-sdk-checksum-algorithm") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-checksum-crc32") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Hosted),
            "x-amz-bypass-governance-retention") > 0,
         "PutObjectRetention signed projection mismatch");
   end;

   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object_Retention
             (Origin, Low_Level.Path_Style, "example-bucket", "key",
              Retention,
              Parameters (Checksum => US.To_String (Algorithms (Index))),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               US.To_String (Checksum_Headers (Index))) > 0,
            "PutObjectRetention checksum header mismatch");
      end;
   end loop;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Key => "");
   Expect_Invalid_Request
     (Key => String'(1 .. Key_Boundary + 1 => 'k'));
   Expect_Invalid_Request (Params => Parameters (Payer => "Requester"));
   Expect_Invalid_Request (Params => Parameters (Checksum => "crc32"));
   Expect_Invalid_Request (Params => Parameters (MD5 => "invalid"));
   Expect_Invalid_Request
     (Params => Parameters
        (Version => String'(1 .. Version_Boundary + 1 => 'v')));
   Expect_Invalid_Request
     (Params => Parameters (Version => "bad" & Character'Val (0)));
   Expect_Invalid_Request
     (Params => Parameters
        (Owner => String'(1 .. Header_Boundary + 1 => 'o')));
   Expect_Invalid_Request
     (Params => Parameters (Owner => "owner" & Character'Val (10)));
   declare
      --  Exact base64 representation of a 16-byte caller-provided MD5.
      Valid_MD5 : constant String := "AAAAAAAAAAAAAAAAAAAAAA==";
      Exact_Key : constant String := String'(1 .. Key_Boundary => 'k');
      Exact_Version : constant String :=
        String'(1 .. Version_Boundary => 'v');
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", Exact_Key,
           Retention,
           Parameters
             (Version => Exact_Version, MD5 => Valid_MD5,
              Owner => Exact_Owner),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Empty : constant Low_Level.Put_Object_Retention_Outcome :=
        Low_Level.Decode_Put_Object_Retention_Response (200, "", Headers);
      Whitespace : constant Low_Level.Put_Object_Retention_Outcome :=
        Low_Level.Decode_Put_Object_Retention_Response
          (200, " " & ASCII.HT, Headers ("requester"));
   begin
      Require
        (Empty.Kind = Low_Level.Object_Retention_Updated
         and then Whitespace.Kind = Low_Level.Object_Retention_Updated,
         "PutObjectRetention exact success mismatch");
   end;
   Expect_Invalid_Response (200, "x");
   Expect_Invalid_Response (200, "", Headers ("Requester"));
   Expect_Invalid_Response
     (200, "", Headers, Request_ID => "r" & Character'Val (10));
   Expect_Invalid_Response
     (200, "", Headers, Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Put_Object_Retention_Outcome :=
           Low_Level.Decode_Put_Object_Retention_Response
             (Status, Error_XML, Headers, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Put_Object_Retention_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "PutObjectRetention rejection mismatch");
      end;
   end loop;
   declare
      --  Fixed error graph: depth two, three elements, 18 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 3,
         Maximum_Text_Bytes => 18);
      Ignored : constant Low_Level.Put_Object_Retention_Outcome :=
        Low_Level.Decode_Put_Object_Retention_Response
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
        Low_Level.Prepare_Get_Object_Retention
          (Origin, Low_Level.Path_Style, "example-bucket", "key",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Object_Retention_Outcome :=
              Low_Level.Execute_Put_Object_Retention (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutObjectRetention cross-operation admitted");
   end;

   Ada.Text_IO.Put_Line ("S3 PutObjectRetention deterministic corpus: OK");
end S3_Put_Object_Retention_Corpus;
