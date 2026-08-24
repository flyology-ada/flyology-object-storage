with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Bucket_Ownership_Controls_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Controls renames
     Flyology.Object_Storage.S3.Bucket_Controls;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;
   use type Controls.Object_Ownership;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Hosted_Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin
       ("https://example-bucket.s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>AccessDenied</Code><Message>denied</Message></Error>";
   --  Exact established low-level response-header text ceiling.
   Header_Boundary : constant Positive := 8_192;
   type Status_Array is array (Positive range <>) of
     Flyology.HTTP.Status_Code;
   --  Exact 200 is contrasted with another 2xx and representative failures.
   Rejection_Statuses : constant Status_Array :=
     (201, 400, 403, 404, 429, 500);
   type Text_Array is array (Positive range <>) of US.Unbounded_String;
   --  Pinned SDK checksum enum and its exact algorithm-specific headers.
   Algorithms : constant Text_Array :=
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
   Checksum_Headers : constant Text_Array :=
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

   function Configuration
     return Controls.Ownership_Controls_Configuration
   is
   begin
      return Value : Controls.Ownership_Controls_Configuration :=
        (Is_Set => True, others => <>)
      do
         Value.Rules.Append
           (Controls.Ownership_Control_Rule'
              (Ownership => Controls.Bucket_Owner_Preferred));
         Value.Rules.Append
           (Controls.Ownership_Control_Rule'
              (Ownership => Controls.Object_Writer));
         Value.Rules.Append
           (Controls.Ownership_Control_Rule'
              (Ownership => Controls.Bucket_Owner_Enforced));
      end return;
   end Configuration;

   function Parameters
     (Checksum : String := ""; MD5 : String := ""; Owner : String := "")
      return Low_Level.Put_Bucket_Control_Parameters is
     ((Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner)));

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Invalid_Configuration
     (Value : Controls.Ownership_Controls_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String :=
              Controls.Serialize_Ownership_Controls (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Controls.Malformed_Configuration => Raised := True;
      end;
      Require (Raised, "ownership serializer admitted invalid configuration");
   end Expect_Invalid_Configuration;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket";
      Value : Controls.Ownership_Controls_Configuration := Configuration;
      Params : Low_Level.Put_Bucket_Control_Parameters := Parameters;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Ownership_Controls
                (Origin, Low_Level.Path_Style, Bucket, Value, Params,
                 Identity, "us-east-1", "20130524T000000Z", Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutBucketOwnershipControls admitted invalid request");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Decode_Put_Bucket_Control_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "ownership PUT admitted invalid response");
   end Expect_Invalid_Response;

begin
   declare
      Value : constant Controls.Ownership_Controls_Configuration :=
        Configuration;
      Document : constant String :=
        Controls.Serialize_Ownership_Controls (Value);
      Expected : constant String :=
        "<OwnershipControls xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><Rule><ObjectOwnership>BucketOwnerPreferred" &
        "</ObjectOwnership></Rule><Rule><ObjectOwnership>ObjectWriter" &
        "</ObjectOwnership></Rule><Rule><ObjectOwnership>" &
        "BucketOwnerEnforced</ObjectOwnership></Rule></OwnershipControls>";
      Parsed : constant Controls.Ownership_Controls_Configuration :=
        Controls.Parse_Ownership_Controls (Document);
   begin
      Require
        (Document = Expected
         and then Parsed.Is_Set
         and then Parsed.Rules.Length = 3
         and then Parsed.Rules.Element (1).Ownership =
           Controls.Bucket_Owner_Preferred
         and then Parsed.Rules.Element (2).Ownership = Controls.Object_Writer
         and then Parsed.Rules.Element (3).Ownership =
           Controls.Bucket_Owner_Enforced,
         "ownership-controls exact serialization or round trip mismatch");
      declare
         --  Pinned graph formula for three rules: root + two elements/rule;
         --  enum wire text is 20 + 12 + 19 = 51 bytes at depth three.
         Exact : constant XML.Parse_Limits :=
           (Maximum_Document_Bytes => Document'Length,
            Maximum_Depth => 3, Maximum_Elements => 7,
            Maximum_Text_Bytes => 51);
         Ignored : constant String :=
           Controls.Serialize_Ownership_Controls (Value, Exact);
         pragma Unreferenced (Ignored);
      begin
         Expect_Invalid_Configuration
           (Value, (Document'Length - 1, 3, 7, 51));
         Expect_Invalid_Configuration
           (Value, (Document'Length, 2, 7, 51));
         Expect_Invalid_Configuration
           (Value, (Document'Length, 3, 6, 51));
         Expect_Invalid_Configuration
           (Value, (Document'Length, 3, 7, 50));
      end;
   end;
   Expect_Invalid_Configuration ((others => <>));
   Expect_Invalid_Configuration ((Is_Set => True, others => <>));

   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Ownership_Controls
          (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
           Parameters (Checksum => "CRC32", Owner => "123456789012"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Ownership_Controls
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Configuration, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?ownershipControls"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "content-md5") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-sdk-checksum-algorithm") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-checksum-crc32") > 0,
         "ownership-controls path projection or checksum mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?ownershipControls"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Hosted), "content-md5") > 0,
         "ownership-controls hosted projection mismatch");
   end;

   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Bucket_Ownership_Controls
             (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
              Parameters (Checksum => US.To_String (Algorithms (Index))),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               US.To_String (Checksum_Headers (Index))) > 0,
            "ownership-controls checksum header mismatch");
      end;
   end loop;

   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request (Params => Parameters (Checksum => "crc32"));
   Expect_Invalid_Request (Params => Parameters (MD5 => "invalid"));
   Expect_Invalid_Request
     (Params => Parameters
        (Owner => String'(1 .. Header_Boundary + 1 => 'o')));
   Expect_Invalid_Request
     (Params => Parameters (Owner => "owner" & Character'Val (10)));
   declare
      --  Exact base64 encoding of 16 zero bytes exercises a caller-supplied
      --  Content-MD5 without changing the externally fixed digest width.
      Valid_MD5 : constant String := "AAAAAAAAAAAAAAAAAAAAAA==";
      Exact_Owner : constant String := String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Ownership_Controls
          (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
           Parameters (MD5 => Valid_MD5, Owner => Exact_Owner), Identity,
           "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;
   declare
      Document : constant String :=
        Controls.Serialize_Ownership_Controls (Configuration);
   begin
      Expect_Invalid_Request
        (Limits => (Document'Length - 1, 3, 7, 51));
   end;

   declare
      Empty : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response (200, "");
      Whitespace : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response (200, " " & ASCII.HT);
   begin
      Require
        (Empty.Kind = Low_Level.Bucket_Control_Updated
         and then Whitespace.Kind = Low_Level.Bucket_Control_Updated,
         "ownership-controls exact success mismatch");
   end;
   Expect_Invalid_Response (200, "x");
   Expect_Invalid_Response
     (200, "", Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "", Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   Expect_Invalid_Response
     (200, "", Request_ID => "request" & Character'Val (10));
   Expect_Invalid_Response
     (200, "", Host_ID => "host" & Character'Val (13));
   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Put_Bucket_Control_Outcome :=
           Low_Level.Decode_Put_Bucket_Control_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Put_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) = "AccessDenied",
            "ownership-controls rejection status mismatch");
      end;
   end loop;
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (Outcome.Kind = Low_Level.Put_Bucket_Control_Rejected
         and then Outcome.Status = 403
         and then US.To_String (Outcome.Error.Code) = "AccessDenied"
         and then US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "ownership-controls typed rejection mismatch");
   end;
   declare
      --  Fixed error graph: depth two, three elements, 18 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 3,
         Maximum_Text_Bytes => 18);
      Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (403, Error_XML, Limits => Exact);
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
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket",
           Controls.Abac_Enabled, Parameters, Identity, "us-east-1",
           "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Execute_Put_Bucket_Ownership_Controls (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised,
         "PutBucketOwnershipControls cross-operation execution admitted");
   end;

   Ada.Text_IO.Put_Line
     ("S3 PutBucketOwnershipControls deterministic corpus: OK");
end S3_Put_Bucket_Ownership_Controls_Corpus;
