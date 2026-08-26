with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Bucket_Controls;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_CORS_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Controls renames Flyology.Object_Storage.S3.Bucket_Controls;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;

   Identity : constant Low_Level.Credentials := Low_Level.Make_Credentials
     ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Hosted_Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin
       ("https://example-bucket.s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>NoSuchCORSConfiguration</Code><Message>missing</Message>" &
     "<Resource>/example-bucket</Resource></Error>";
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

   function Configuration return Controls.CORS_Configuration is
   begin
      return Value : Controls.CORS_Configuration :=
        (Is_Set => True, others => <>)
      do
         declare
            Rule : Controls.CORS_Rule := (others => <>);
         begin
            Rule.ID :=
              (Is_Set => True,
               Value => US.To_Unbounded_String ("rule<&>"));
            Rule.Allowed_Headers.Append ("*");
            Rule.Allowed_Headers.Append ("x-test");
            Rule.Allowed_Methods.Append ("GET");
            Rule.Allowed_Methods.Append ("PUT");
            Rule.Allowed_Origins.Append ("https://example.test");
            Rule.Expose_Headers.Append ("etag");
            Rule.Max_Age_Seconds :=
              (Is_Set => True,
               Text => US.To_Unbounded_String
                 ("+999999999999999999999999"));
            Value.Rules.Append (Rule);
         end;
         declare
            Rule : Controls.CORS_Rule := (others => <>);
         begin
            Rule.Allowed_Methods.Append ("HEAD");
            Rule.Allowed_Origins.Append ("*");
            Value.Rules.Append (Rule);
         end;
      end return;
   end Configuration;

   function Put_Parameters
     (Checksum : String := ""; MD5 : String := ""; Owner : String := "")
      return Low_Level.Put_Bucket_Control_Parameters is
     ((Content_MD5 => US.To_Unbounded_String (MD5),
       Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner)));
   Header_Boundary : constant Positive := 8_192;

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
            Ignored : constant Low_Level.Get_Bucket_CORS_Outcome :=
              Low_Level.Decode_Get_Bucket_CORS_Response
                (Status, Payload, Request_ID, Host_ID, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "GetBucketCors admitted invalid response");
   end Expect_Invalid_Response;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_CORS
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
      Require (Raised, "GetBucketCors admitted invalid bucket");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Put
     (Bucket : String := "example-bucket";
      Value : Controls.CORS_Configuration := Configuration;
      Parameters : Low_Level.Put_Bucket_Control_Parameters := Put_Parameters;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_CORS
                (Origin, Low_Level.Path_Style, Bucket, Value, Parameters,
                 Identity, "us-east-1", "20130524T000000Z", Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "PutBucketCors admitted invalid request");
   end Expect_Invalid_Put;

begin
   declare
      Value : constant Controls.CORS_Configuration := Configuration;
      Document : constant String := Controls.Serialize_CORS (Value);
      Expected : constant String :=
        "<CORSConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><CORSRule><ID>rule&lt;&amp;&gt;</ID>" &
        "<AllowedHeader>*</AllowedHeader><AllowedHeader>x-test" &
        "</AllowedHeader><AllowedMethod>GET</AllowedMethod>" &
        "<AllowedMethod>PUT</AllowedMethod><AllowedOrigin>https://" &
        "example.test</AllowedOrigin><ExposeHeader>etag</ExposeHeader>" &
        "<MaxAgeSeconds>+999999999999999999999999</MaxAgeSeconds>" &
        "</CORSRule><CORSRule><AllowedMethod>HEAD</AllowedMethod>" &
        "<AllowedOrigin>*</AllowedOrigin></CORSRule></CORSConfiguration>";
      Parsed : constant Controls.CORS_Configuration :=
        Controls.Parse_CORS (Document);
      First : constant Controls.CORS_Rule := Parsed.Rules.Element (1);
      Second : constant Controls.CORS_Rule := Parsed.Rules.Element (2);
      --  Reference-fixture derivation: root + two rules + ten fields gives
      --  thirteen elements; the ten decoded field strings above total 74
      --  bytes. Changing either value changes the exact limit oracle.
      Text_Bytes : constant Positive := 74;
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Document'Length,
         Maximum_Depth => 3, Maximum_Elements => 13,
         Maximum_Text_Bytes => Text_Bytes);
      Ignored : constant String := Controls.Serialize_CORS (Value, Exact);
      pragma Unreferenced (Ignored);
   begin
      Require
        (Document = Expected
         and then Parsed.Rules.Length = 2
         and then US.To_String (First.ID.Value) = "rule<&>"
         and then First.Allowed_Methods.Length = 2
         and then Second.Allowed_Origins (1) = "*",
         "PutBucketCors exact serialization or round trip mismatch");
      Expect_Invalid_Put
        (Limits => (Document'Length - 1, 3, 13, Text_Bytes));
      Expect_Invalid_Put
        (Limits => (Document'Length, 2, 13, Text_Bytes));
      Expect_Invalid_Put
        (Limits => (Document'Length, 3, 12, Text_Bytes));
      Expect_Invalid_Put
        (Limits => (Document'Length, 3, 13, Text_Bytes - 1));
   end;
   Expect_Invalid_Put (Value => (others => <>));
   Expect_Invalid_Put (Value => (Is_Set => True, others => <>));
   declare
      Invalid : Controls.CORS_Configuration := Configuration;
      Rule : Controls.CORS_Rule := Invalid.Rules.Element (1);
   begin
      Rule.Allowed_Methods.Clear;
      Invalid.Rules.Replace_Element (1, Rule);
      Expect_Invalid_Put (Value => Invalid);
   end;
   declare
      Invalid : Controls.CORS_Configuration := Configuration;
      Rule : Controls.CORS_Rule := Invalid.Rules.Element (1);
   begin
      Rule.Allowed_Origins.Clear;
      Invalid.Rules.Replace_Element (1, Rule);
      Expect_Invalid_Put (Value => Invalid);
   end;
   declare
      Invalid : Controls.CORS_Configuration := Configuration;
      Rule : Controls.CORS_Rule := Invalid.Rules.Element (1);
   begin
      Rule.Max_Age_Seconds.Text := US.To_Unbounded_String ("1.0");
      Invalid.Rules.Replace_Element (1, Rule);
      Expect_Invalid_Put (Value => Invalid);
   end;
   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_CORS
          (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
           Put_Parameters (Checksum => "CRC32", Owner => "123456789012"),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_CORS
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           Configuration, Put_Parameters, Identity, "us-east-1",
           "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?cors"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "content-md5") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-sdk-checksum-algorithm") > 0
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path), "x-amz-checksum-crc32") > 0
         and then Low_Level.Owned_Payload_Length (Path) =
           Controls.Serialize_CORS (Configuration)'Length,
         "PutBucketCors path projection or checksum mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?cors"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "PutBucketCors hosted projection mismatch");
   end;
   for Index in Algorithms'Range loop
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Bucket_CORS
             (Origin, Low_Level.Path_Style, "example-bucket", Configuration,
              Put_Parameters (Checksum => US.To_String (Algorithms (Index))),
              Identity, "us-east-1", "20130524T000000Z");
      begin
         Require
           (Ada.Strings.Fixed.Index
              (Low_Level.Signed_Headers (Prepared),
               US.To_String (Checksum_Headers (Index))) > 0,
            "PutBucketCors checksum header mismatch");
      end;
   end loop;
   Expect_Invalid_Put (Bucket => "");
   Expect_Invalid_Put (Bucket => "UPPERCASE");
   Expect_Invalid_Put (Parameters => Put_Parameters (Checksum => "crc32"));
   Expect_Invalid_Put (Parameters => Put_Parameters (MD5 => "invalid"));
   Expect_Invalid_Put
     (Parameters => Put_Parameters
        (Owner => String'(1 .. Header_Boundary + 1 => 'o')));
   Expect_Invalid_Put
     (Parameters => Put_Parameters
        (Owner => "owner" & Character'Val (10)));

   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_CORS
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_CORS
          (Flyology.HTTP.Parse_Origin
             ("https://example-bucket.s3.example.test"),
           Low_Level.Virtual_Hosted_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?cors"
         and then Low_Level.Authority (Path) = "s3.example.test"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetBucketCors path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?cors"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetBucketCors hosted projection mismatch");
   end;

   Expect_Invalid_Request ("");
   Expect_Invalid_Request ("UPPERCASE");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));
   declare
      Exact_Owner : constant String :=
        String'(1 .. Header_Boundary => 'o');
      Ignored : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_CORS
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String (Exact_Owner)),
           Identity, "us-east-1", "20130524T000000Z");
      pragma Unreferenced (Ignored);
   begin
      null;
   end;

   declare
      Absent : constant Low_Level.Get_Bucket_CORS_Outcome :=
        Low_Level.Decode_Get_Bucket_CORS_Response (200, "");
      Empty : constant Low_Level.Get_Bucket_CORS_Outcome :=
        Low_Level.Decode_Get_Bucket_CORS_Response
          (200, "<CORSConfiguration/>");
      Full : constant Low_Level.Get_Bucket_CORS_Outcome :=
        Low_Level.Decode_Get_Bucket_CORS_Response
          (200, "<CORSConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
             "2006-03-01/""><CORSRule><ID></ID><AllowedHeader>*" &
             "</AllowedHeader><AllowedHeader>x-test</AllowedHeader>" &
             "<AllowedMethod>GET</AllowedMethod><AllowedMethod>PUT" &
             "</AllowedMethod><AllowedOrigin>https://example.test" &
             "</AllowedOrigin><ExposeHeader>etag</ExposeHeader>" &
             "<MaxAgeSeconds>+999999999999999999999999</MaxAgeSeconds>" &
             "</CORSRule><CORSRule><AllowedMethod>HEAD</AllowedMethod>" &
             "<AllowedOrigin>*</AllowedOrigin></CORSRule>" &
             "</CORSConfiguration>");
      First : constant Controls.CORS_Rule :=
        Full.Configuration.Rules.Element (1);
   begin
      Require
        (not Absent.Configuration.Is_Set
         and then Absent.Configuration.Rules.Is_Empty
         and then Empty.Configuration.Is_Set
         and then Empty.Configuration.Rules.Is_Empty,
         "GetBucketCors outer presence mismatch");
      Require
        (Full.Configuration.Rules.Length = 2
         and then First.ID.Is_Set
         and then US.To_String (First.ID.Value) = ""
         and then First.Allowed_Headers.Length = 2
         and then First.Allowed_Headers (1) = "*"
         and then First.Allowed_Methods.Length = 2
         and then First.Allowed_Methods (2) = "PUT"
         and then First.Allowed_Origins (1) = "https://example.test"
         and then First.Expose_Headers (1) = "etag"
         and then First.Max_Age_Seconds.Is_Set
         and then US.To_String (First.Max_Age_Seconds.Text) =
           "+999999999999999999999999",
         "GetBucketCors flattened values mismatch");
   end;

   Expect_Invalid_Response (200, " ");
   Expect_Invalid_Response (200, "<Wrong/>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration><CORSRule><AllowedOrigin>*" &
        "</AllowedOrigin></CORSRule></CORSConfiguration>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration><CORSRule><AllowedMethod>GET" &
        "</AllowedMethod></CORSRule></CORSConfiguration>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration><CORSRule><AllowedMethod>GET" &
        "</AllowedMethod><AllowedOrigin>*</AllowedOrigin><ID>a</ID>" &
        "<ID>b</ID></CORSRule></CORSConfiguration>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration><CORSRule><AllowedMethod>GET" &
        "</AllowedMethod><AllowedOrigin>*</AllowedOrigin>" &
        "<MaxAgeSeconds>1.0</MaxAgeSeconds></CORSRule>" &
        "</CORSConfiguration>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration value=""x""/>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration xmlns=""urn:wrong""/>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><CORSRule xmlns=""""><AllowedMethod>GET" &
        "</AllowedMethod><AllowedOrigin>*</AllowedOrigin></CORSRule>" &
        "</CORSConfiguration>");
   Expect_Invalid_Response
     (200, "<!DOCTYPE CORSConfiguration [<!ENTITY x 'GET'>]>" &
        "<CORSConfiguration><CORSRule><AllowedMethod>&x;" &
        "</AllowedMethod><AllowedOrigin>*</AllowedOrigin></CORSRule>" &
        "</CORSConfiguration>");
   Expect_Invalid_Response
     (200, "<?probe value?><CORSConfiguration/>");
   Expect_Invalid_Response
     (200, "<CORSConfiguration><CORSRule><AllowedMethod>" &
        Character'Val (255) & "</AllowedMethod><AllowedOrigin>*" &
        "</AllowedOrigin></CORSRule></CORSConfiguration>");

   declare
      Payload : constant String :=
        "<CORSConfiguration><CORSRule><AllowedMethod>GET</AllowedMethod>" &
        "<AllowedOrigin>*</AllowedOrigin></CORSRule></CORSConfiguration>";
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Payload'Length,
         Maximum_Depth => 3, Maximum_Elements => 4,
         Maximum_Text_Bytes => 4);
      Ignored : constant Low_Level.Get_Bucket_CORS_Outcome :=
        Low_Level.Decode_Get_Bucket_CORS_Response
          (200, Payload, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length - 1,
                    Maximum_Depth => 3, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 4));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 4));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 4));
      Expect_Invalid_Response
        (200, Payload,
         Limits => (Maximum_Document_Bytes => Payload'Length,
                    Maximum_Depth => 3, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 3));
   end;

   Expect_Invalid_Response
     (200, "<CORSConfiguration/>",
      Request_ID => String'(1 .. Header_Boundary + 1 => 'r'));
   Expect_Invalid_Response
     (200, "<CORSConfiguration/>", Host_ID => "host" & Character'Val (10));
   declare
      Request_ID : constant String := String'(1 .. Header_Boundary => 'r');
      Host_ID : constant String := String'(1 .. Header_Boundary => 'h');
      Outcome : constant Low_Level.Get_Bucket_CORS_Outcome :=
        Low_Level.Decode_Get_Bucket_CORS_Response
          (403, Error_XML, Request_ID, Host_ID);
   begin
      Require
        (US.To_String (Outcome.Error.Request_ID) = Request_ID
         and then US.To_String (Outcome.Error.Host_ID) = Host_ID,
         "GetBucketCors identifier boundary mismatch");
   end;

   for Status of Rejection_Statuses loop
      declare
         Outcome : constant Low_Level.Get_Bucket_CORS_Outcome :=
           Low_Level.Decode_Get_Bucket_CORS_Response
             (Status, Error_XML, "request-id", "host-id");
      begin
         Require
           (Outcome.Kind = Low_Level.Get_Bucket_Control_Rejected
            and then Outcome.Status = Status
            and then US.To_String (Outcome.Error.Code) =
              "NoSuchCORSConfiguration",
            "GetBucketCors typed rejection mismatch");
      end;
   end loop;
   declare
      --  The fixed error has depth two, four elements, and 45 text bytes.
      Exact : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Error_XML'Length,
         Maximum_Depth => 2, Maximum_Elements => 4,
         Maximum_Text_Bytes => 45);
      Ignored : constant Low_Level.Get_Bucket_CORS_Outcome :=
        Low_Level.Decode_Get_Bucket_CORS_Response
          (403, Error_XML, Limits => Exact);
      pragma Unreferenced (Ignored);
   begin
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length - 1,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 45));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 1, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 45));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 2, Maximum_Elements => 3,
                    Maximum_Text_Bytes => 45));
      Expect_Invalid_Response
        (403, Error_XML,
         Limits => (Maximum_Document_Bytes => Error_XML'Length,
                    Maximum_Depth => 2, Maximum_Elements => 4,
                    Maximum_Text_Bytes => 44));
   end;
   Expect_Invalid_Response (403, "");

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Abac
          (Origin, Low_Level.Path_Style, "example-bucket", (others => <>),
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Bucket_CORS_Outcome :=
              Low_Level.Execute_Get_Bucket_CORS (HTTP, Wrong);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "GetBucketCors cross-operation execution");
   end;

   Ada.Text_IO.Put_Line ("S3 Get/PutBucketCors deterministic corpus: OK");
end S3_Get_Bucket_CORS_Corpus;
