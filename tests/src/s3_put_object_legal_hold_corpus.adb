with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Object_Lock;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Object_Legal_Hold_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Deletions renames Flyology.Object_Storage.S3.Deletions;
   package Object_Lock renames Flyology.Object_Storage.S3.Object_Lock;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Object_Legal_Hold_Outcome_Kind;

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

   function Hold
     (Set : Boolean := True;
      Status : Object_Lock.Legal_Hold_Status := Object_Lock.Legal_Hold_On)
      return Object_Lock.Legal_Hold is
     ((Is_Set => Set, Status => Status));

   function Parameters
     (Payer : String := ""; Version : String := "";
      MD5 : String := ""; Checksum : String := ""; Owner : String := "")
      return Low_Level.Put_Object_Legal_Hold_Parameters is
     ((Request_Payer => US.To_Unbounded_String (Payer),
       Version_ID => US.To_Unbounded_String (Version),
       Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner)));

   function Headers (Charged : String := "")
      return Low_Level.Put_Object_Legal_Hold_Result is
     ((Request_Charged => US.To_Unbounded_String (Charged)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Serialization
     (Value : Object_Lock.Legal_Hold;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String :=
              Object_Lock.Serialize_Legal_Hold (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Object_Lock.Malformed_Object_Lock => Raised := True;
      end;
      Require (Raised, "LegalHold serializer admitted invalid input");
   end Expect_Invalid_Serialization;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Key : String := "key";
      Value : Object_Lock.Legal_Hold := Hold;
      Params : Low_Level.Put_Object_Legal_Hold_Parameters := Parameters;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Object_Legal_Hold
                (Origin, Low_Level.Path_Style, Bucket, Key, Value, Params,
                 Identity, "us-east-1", "20130524T000000Z", Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutObjectLegalHold admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Result : Low_Level.Put_Object_Legal_Hold_Result := Headers;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
              Low_Level.Decode_Put_Object_Legal_Hold_Response
                (Status, Payload, Result, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "PutObjectLegalHold admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      On_Document : constant String :=
        Object_Lock.Serialize_Legal_Hold (Hold);
      Off_Document : constant String :=
        Object_Lock.Serialize_Legal_Hold
          (Hold (Status => Object_Lock.Legal_Hold_Off));
      Empty_Root : constant String :=
        Object_Lock.Serialize_Legal_Hold
          (Hold (Status => Object_Lock.Legal_Hold_Status_Absent));
      Absent : constant String :=
        Object_Lock.Serialize_Legal_Hold
          (Hold (False, Object_Lock.Legal_Hold_Status_Absent));
      Expected_On : constant String :=
        "<LegalHold xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
        "<Status>ON</Status></LegalHold>";
   begin
      Require (On_Document = Expected_On, "LegalHold ON XML mismatch");
      Require
        (Ada.Strings.Fixed.Index (Off_Document, "<Status>OFF</Status>") > 0,
         "LegalHold OFF XML mismatch");
      Require
        (Ada.Strings.Fixed.Index (Empty_Root, "<Status>") = 0,
         "LegalHold absent status was encoded");
      Require (Absent = "", "absent LegalHold did not encode empty payload");
      declare
         --  Pinned ON document graph is two elements at depth two with two
         --  decoded status bytes.
         Exact : constant XML.Parse_Limits :=
           (Maximum_Document_Bytes => On_Document'Length,
            Maximum_Depth => 2, Maximum_Elements => 2,
            Maximum_Text_Bytes => 2);
         Ignored : constant String :=
           Object_Lock.Serialize_Legal_Hold (Hold, Exact);
         pragma Unreferenced (Ignored);
      begin
         Expect_Invalid_Serialization
           (Hold, (On_Document'Length - 1, 2, 2, 2));
         Expect_Invalid_Serialization
           (Hold, (On_Document'Length, 1, 2, 2));
         Expect_Invalid_Serialization
           (Hold, (On_Document'Length, 2, 1, 2));
         Expect_Invalid_Serialization
           (Hold, (On_Document'Length, 2, 2, 1));
      end;
   end;
   Expect_Invalid_Serialization
     (Hold (False, Object_Lock.Legal_Hold_On));

   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "dir/a b%", Hold,
           Parameters
             (Payer => "requester", Version => "v /%", Checksum => "CRC32",
              Owner => "123456789012"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Legal_Hold
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           "dir/a b%", Hold (Status => Object_Lock.Legal_Hold_Off),
           Parameters, Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) =
           "/example-bucket/dir/a%20b%25?legal-hold&versionId=v%20%2F%25",
         "PutObjectLegalHold path target mismatch");
      Require
        (Low_Level.Target (Hosted) = "/dir/a%20b%25?legal-hold"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "PutObjectLegalHold hosted target mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "content-md5") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-request-payer") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-sdk-checksum-algorithm") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-checksum-crc32") > 0,
         "PutObjectLegalHold signed projection mismatch");
   end;

   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Object_Legal_Hold
             (Origin, Low_Level.Path_Style, "example-bucket", "key", Hold,
              Parameters (Checksum => US.To_String (Algorithms (Index))),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               US.To_String (Checksum_Headers (Index))) > 0,
            "PutObjectLegalHold checksum header mismatch");
      end;
   end loop;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Key => "");
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
      Exact_Version : constant String :=
        String'(1 .. Version_Boundary => 'v');
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "key", Hold,
           Parameters
             (Version => Exact_Version, MD5 => Valid_MD5,
              Owner => Exact_Owner),
           Identity,
           "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Empty : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Put_Object_Legal_Hold_Response (200, "", Headers);
      Whitespace : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Put_Object_Legal_Hold_Response
          (200, " " & ASCII.HT, Headers ("requester"));
   begin
      Require
        (Empty.Kind = Low_Level.Object_Legal_Hold_Updated
         and then Whitespace.Kind = Low_Level.Object_Legal_Hold_Updated,
         "PutObjectLegalHold exact success mismatch");
   end;
   Expect_Invalid_Response (200, "x");
   Expect_Invalid_Response (200, "", Headers ("Requester"));
   Expect_Invalid_Response
     (200, "", Headers, Request_ID => "r" & Character'Val (10));
   Expect_Invalid_Response
     (200, "", Headers, Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
           Low_Level.Decode_Put_Object_Legal_Hold_Response
             (Status, Error_XML, Headers, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Put_Object_Legal_Hold_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied"
            and then US.To_String (Outcome.Error.Request_ID) = "request-id"
            and then US.To_String (Outcome.Error.Host_ID) = "host-id",
            "PutObjectLegalHold rejection mismatch");
      end;
   end loop;
   declare
      --  Fixed error graph: depth two, three elements, 18 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 3,
         Maximum_Text_Bytes => 18);
      Ignored : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
        Low_Level.Decode_Put_Object_Legal_Hold_Response
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
        Low_Level.Prepare_Get_Object_Legal_Hold
          (Origin, Low_Level.Path_Style, "example-bucket", "key",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Object_Legal_Hold_Outcome :=
              Low_Level.Execute_Put_Object_Legal_Hold (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutObjectLegalHold cross-operation admitted");
   end;

   Ada.Text_IO.Put_Line ("S3 PutObjectLegalHold deterministic corpus: OK");
end S3_Put_Object_Legal_Hold_Corpus;
