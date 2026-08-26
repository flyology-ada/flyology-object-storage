with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_Lifecycle_Configuration_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Lifecycle renames Flyology.Object_Storage.S3.Lifecycle;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Lifecycle.Rule_Status;
   use type Lifecycle.Transition_Storage_Class;
   use type Lifecycle.Transition_Default_Minimum_Size;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Hosted_Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin
       ("https://example-bucket.s3.example.test");
   --  Exact established low-level response-header text boundary.
   Header_Boundary : constant Positive := 8_192;
   Error_XML : constant String :=
     "<Error><Code>NoSuchLifecycleConfiguration</Code>" &
     "<Message>missing</Message><Resource>/example-bucket</Resource>" &
     "</Error>";
   Document : constant String :=
     "<LifecycleConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
     "2006-03-01/""><Rule><Expiration>" &
     "<Date>2030-01-02T00:00:00Z</Date><Days>+365</Days>" &
     "<ExpiredObjectDeleteMarker>true</ExpiredObjectDeleteMarker>" &
     "</Expiration><ID>archive&lt;&amp;&gt;</ID><Prefix>legacy/</Prefix>" &
     "<Filter><Prefix>filter/</Prefix>" &
     "<Tag><Key>direct</Key><Value>yes</Value></Tag>" &
     "<ObjectSizeGreaterThan>10</ObjectSizeGreaterThan>" &
     "<ObjectSizeLessThan>20</ObjectSizeLessThan>" &
     "<And><Prefix>logs/</Prefix>" &
     "<Tag><Key>class</Key><Value>audit</Value></Tag>" &
     "<Tag><Key>tenant</Key><Value></Value></Tag>" &
     "<ObjectSizeGreaterThan>-1</ObjectSizeGreaterThan>" &
     "<ObjectSizeLessThan>999999999999999999999999999999" &
     "</ObjectSizeLessThan></And></Filter><Status>Enabled</Status>" &
     "<Transition><Date>2031-02-03T00:00:00+00:00</Date>" &
     "<Days>0</Days><StorageClass>GLACIER</StorageClass></Transition>" &
     "<Transition><StorageClass>STANDARD_IA</StorageClass></Transition>" &
     "<Transition><StorageClass>ONEZONE_IA</StorageClass></Transition>" &
     "<Transition><StorageClass>INTELLIGENT_TIERING</StorageClass>" &
     "</Transition><Transition><StorageClass>DEEP_ARCHIVE</StorageClass>" &
     "</Transition><Transition><StorageClass>GLACIER_IR</StorageClass>" &
     "</Transition><NoncurrentVersionTransition>" &
     "<NoncurrentDays>30</NoncurrentDays><StorageClass>GLACIER_IR" &
     "</StorageClass><NewerNoncurrentVersions>100</NewerNoncurrentVersions>" &
     "</NoncurrentVersionTransition><NoncurrentVersionExpiration>" &
     "<NoncurrentDays>+90</NoncurrentDays>" &
     "<NewerNoncurrentVersions>2</NewerNoncurrentVersions>" &
     "</NoncurrentVersionExpiration><AbortIncompleteMultipartUpload>" &
     "<DaysAfterInitiation>7</DaysAfterInitiation>" &
     "</AbortIncompleteMultipartUpload></Rule><Rule><Expiration>" &
     "<ExpiredObjectDeleteMarker>false</ExpiredObjectDeleteMarker>" &
     "</Expiration><Filter></Filter>" &
     "<Status>Disabled</Status></Rule></LifecycleConfiguration>";
   Limit_Document : constant String :=
     "<LifecycleConfiguration><Rule><Status>Enabled</Status></Rule>" &
     "</LifecycleConfiguration>";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Malformed
     (Value : String; Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Lifecycle.Lifecycle_Configuration :=
              Lifecycle.Parse (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Lifecycle.Malformed_Lifecycle => Raised := True;
      end;
      Require (Raised, "invalid lifecycle XML was accepted");
   end Expect_Malformed;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Request_ID : String := ""; Host_ID : String := "";
      Transition_Header : String := "";
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
                Low_Level.Decode_Get_Bucket_Lifecycle_Configuration_Response
                  (Status, Payload, Request_ID, Host_ID,
                   Transition_Header, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require
        (Raised,
         "GetBucketLifecycleConfiguration admitted invalid response");
   end Expect_Invalid_Response;

   procedure Expect_Invalid_Request
     (Bucket : String := "example-bucket"; Owner : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Get_Bucket_Lifecycle_Configuration
                (Origin, Low_Level.Path_Style, Bucket,
                 (Expected_Bucket_Owner =>
                    US.To_Unbounded_String (Owner)),
                 Identity, "us-east-1", "20130524T000000Z");
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require
        (Raised,
         "GetBucketLifecycleConfiguration admitted invalid request");
   end Expect_Invalid_Request;

begin
   declare
      Parsed : constant Lifecycle.Lifecycle_Configuration :=
        Lifecycle.Parse (Document);
      First : constant Lifecycle.Lifecycle_Rule :=
        Parsed.Rules.Element (1);
      Second : constant Lifecycle.Lifecycle_Rule :=
        Parsed.Rules.Element (2);
   begin
      Require
        (Parsed.Is_Set
         and then Parsed.Rules.Length = 2
         and then First.Status = Lifecycle.Rule_Enabled
         and then First.Expiration.Is_Set
         and then First.Expiration.Date.Is_Set
         and then US.To_String (First.Expiration.Date.Text) =
           "2030-01-02T00:00:00Z"
         and then US.To_String (First.Expiration.Days.Text) = "+365"
         and then First.Expiration.Expired_Object_Delete_Marker.Is_Set
         and then First.Expiration.Expired_Object_Delete_Marker.Value
         and then US.To_String (First.ID.Value) = "archive<&>"
         and then US.To_String (First.Prefix.Value) = "legacy/"
         and then US.To_String (First.Filter.Prefix.Value) = "filter/"
         and then First.Filter.Tag.Is_Set
         and then US.To_String (First.Filter.Tag.Value.Key) = "direct"
         and then US.To_String (First.Filter.Tag.Value.Value) = "yes"
         and then US.To_String
           (First.Filter.Object_Size_Greater_Than.Text) = "10"
         and then US.To_String (First.Filter.Object_Size_Less_Than.Text) = "20"
         and then First.Filter.And_Predicates.Is_Set
         and then US.To_String
           (First.Filter.And_Predicates.Prefix.Value) = "logs/"
         and then First.Filter.And_Predicates.Tags.Length = 2
         and then US.To_String
           (First.Filter.And_Predicates.Tags.Element (2).Value) = ""
         and then US.To_String
           (First.Filter.And_Predicates.Object_Size_Greater_Than.Text) = "-1"
         and then US.To_String
           (First.Filter.And_Predicates.Object_Size_Less_Than.Text) =
             "999999999999999999999999999999"
         and then First.Transitions.Length = 6
         and then First.Transitions.Element (1).Date.Is_Set
         and then US.To_String (First.Transitions.Element (1).Date.Text) =
           "2031-02-03T00:00:00+00:00"
         and then US.To_String (First.Transitions.Element (1).Days.Text) = "0"
         and then First.Transitions.Element (1).Storage_Class =
           Lifecycle.Glacier
         and then First.Transitions.Element (2).Storage_Class =
           Lifecycle.Standard_IA
         and then First.Transitions.Element (3).Storage_Class =
           Lifecycle.One_Zone_IA
         and then First.Transitions.Element (4).Storage_Class =
           Lifecycle.Intelligent_Tiering
         and then First.Transitions.Element (5).Storage_Class =
           Lifecycle.Deep_Archive
         and then First.Transitions.Element (6).Storage_Class =
           Lifecycle.Glacier_Instant_Retrieval
         and then First.Noncurrent_Transitions.Length = 1
         and then US.To_String
           (First.Noncurrent_Transitions.Element (1).Noncurrent_Days.Text) =
             "30"
         and then First.Noncurrent_Transitions.Element (1).
           Storage_Class_Is_Set
         and then First.Noncurrent_Transitions.Element (1).Storage_Class =
           Lifecycle.Glacier_Instant_Retrieval
         and then US.To_String
           (First.Noncurrent_Transitions.Element (1).
              Newer_Noncurrent_Versions.Text) = "100"
         and then First.Noncurrent_Expiration.Is_Set
         and then US.To_String
           (First.Noncurrent_Expiration.Noncurrent_Days.Text) = "+90"
         and then US.To_String
           (First.Noncurrent_Expiration.Newer_Noncurrent_Versions.Text) = "2"
         and then First.Abort_Incomplete.Is_Set
         and then US.To_String
           (First.Abort_Incomplete.Days_After_Initiation.Text) = "7"
         and then Second.Expiration.Is_Set
         and then Second.Expiration.Expired_Object_Delete_Marker.Is_Set
         and then not Second.Expiration.Expired_Object_Delete_Marker.Value
         and then Second.Filter.Is_Set
         and then Second.Status = Lifecycle.Rule_Disabled,
         "GetBucketLifecycleConfiguration exact graph mismatch");
   end;

   Require
     (Lifecycle.Parse_Transition_Default_Minimum_Size ("") =
        Lifecycle.Transition_Minimum_Absent
      and then Lifecycle.Parse_Transition_Default_Minimum_Size
        ("varies_by_storage_class") = Lifecycle.Varies_By_Storage_Class
      and then Lifecycle.Parse_Transition_Default_Minimum_Size
        ("all_storage_classes_128K") =
          Lifecycle.All_Storage_Classes_128K,
      "lifecycle transition-minimum header domain mismatch");
   begin
      declare
         Ignored : constant Lifecycle.Transition_Default_Minimum_Size :=
           Lifecycle.Parse_Transition_Default_Minimum_Size ("128K");
         pragma Unreferenced (Ignored);
      begin
         raise Program_Error with "invalid lifecycle header was accepted";
      end;
   exception
      when Lifecycle.Malformed_Lifecycle => null;
   end;

   Expect_Malformed ("");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule/></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Status>enabled</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Status>Enabled</Status>" &
      "<Status>Disabled</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Filter><Tag><Key>k</Key>" &
      "</Tag></Filter><Status>Enabled</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Expiration><Days>1x</Days>" &
      "</Expiration><Status>Enabled</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Expiration>" &
      "<Date>2030-02-30T00:00:00Z</Date></Expiration>" &
      "<Status>Enabled</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Expiration>" &
      "<ExpiredObjectDeleteMarker>TRUE</ExpiredObjectDeleteMarker>" &
      "</Expiration><Status>Enabled</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Transition>" &
      "<StorageClass>ARCHIVE</StorageClass></Transition>" &
      "<Status>Enabled</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Unknown/>" &
      "<Status>Enabled</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><Expiration><Days></Days>" &
      "</Expiration><Status>Enabled</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration xmlns=""urn:other""><Rule>" &
      "<Status>Enabled</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule id=""x""><Status>Enabled" &
      "</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
      "2006-03-01/""><Rule xmlns=""""><Status>Enabled</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<!DOCTYPE LifecycleConfiguration [<!ENTITY x ""Enabled"">]>" &
      "<LifecycleConfiguration><Rule><Status>&x;</Status></Rule>" &
      "</LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><?probe data?><Rule><Status>Enabled" &
      "</Status></Rule></LifecycleConfiguration>");
   Expect_Malformed
     ("<LifecycleConfiguration><Rule><ID>" & Character'Val (16#C3#) &
      "</ID><Status>Enabled</Status></Rule></LifecycleConfiguration>");
   --  Test-only reductions of the caller-selected shared XML limits.
   Expect_Malformed
     (Document,
      (Maximum_Document_Bytes => Document'Length - 1,
       Maximum_Depth => 64, Maximum_Elements => 1_000,
       Maximum_Text_Bytes => Document'Length));
   Expect_Malformed
     (Document,
      (Maximum_Document_Bytes => Document'Length,
       Maximum_Depth => 5, Maximum_Elements => 1_000,
       Maximum_Text_Bytes => Document'Length));
   declare
      Exact : constant Lifecycle.Lifecycle_Configuration :=
        Lifecycle.Parse
          (Limit_Document,
           (Maximum_Document_Bytes => Limit_Document'Length,
            Maximum_Depth => 3, Maximum_Elements => 3,
            Maximum_Text_Bytes => 7));
   begin
      Require
        (Exact.Rules.Length = 1,
         "exact lifecycle XML limits rejected a valid document");
   end;
   Expect_Malformed
     (Limit_Document,
      (Maximum_Document_Bytes => Limit_Document'Length - 1,
       Maximum_Depth => 3, Maximum_Elements => 3,
       Maximum_Text_Bytes => 7));
   Expect_Malformed
     (Limit_Document,
      (Maximum_Document_Bytes => Limit_Document'Length,
       Maximum_Depth => 2, Maximum_Elements => 3,
       Maximum_Text_Bytes => 7));
   Expect_Malformed
     (Limit_Document,
      (Maximum_Document_Bytes => Limit_Document'Length,
       Maximum_Depth => 3, Maximum_Elements => 2,
       Maximum_Text_Bytes => 7));
   Expect_Malformed
     (Limit_Document,
      (Maximum_Document_Bytes => Limit_Document'Length,
       Maximum_Depth => 3, Maximum_Elements => 3,
       Maximum_Text_Bytes => 6));

   declare
      Path : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Lifecycle_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String ("123456789012")),
           Identity, "us-east-1", "20130524T000000Z");
      Hosted : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Lifecycle_Configuration
          (Hosted_Origin, Low_Level.Virtual_Hosted_Style, "example-bucket",
           (others => <>), Identity, "us-east-1", "20130524T000000Z");
      Boundary : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Lifecycle_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner =>
              US.To_Unbounded_String
                (String'(1 .. Header_Boundary => 'o'))),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Path) = "/example-bucket?lifecycle"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Path),
            "x-amz-expected-bucket-owner") > 0,
         "GetBucketLifecycleConfiguration path projection mismatch");
      Require
        (Low_Level.Target (Hosted) = "/?lifecycle"
         and then Low_Level.Authority (Hosted) =
           "example-bucket.s3.example.test",
         "GetBucketLifecycleConfiguration hosted projection mismatch");
      Require
        (Ada.Strings.Fixed.Index
           (Low_Level.Signed_Headers (Boundary),
            "x-amz-expected-bucket-owner") > 0,
         "exact lifecycle owner-header boundary was rejected");
   end;
   Expect_Invalid_Request (Bucket => "");
   Expect_Invalid_Request (Bucket => "UPPERCASE");
   Expect_Invalid_Request
     (Owner => String'(1 .. Header_Boundary + 1 => 'o'));
   Expect_Invalid_Request (Owner => "owner" & Character'Val (10));

   declare
      Found : constant
        Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Lifecycle_Configuration_Response
            (200, Document, "request", "host",
             "varies_by_storage_class");
      Empty : constant
        Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Lifecycle_Configuration_Response
            (200, "");
      Missing : constant
        Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Lifecycle_Configuration_Response
            (404, Error_XML, "request", "host");
      Boundary : constant
        Low_Level.Get_Bucket_Lifecycle_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Lifecycle_Configuration_Response
            (200, "", String'(1 .. Header_Boundary => 'r'),
             String'(1 .. Header_Boundary => 'h'));
   begin
      Require
        (Found.Kind = Low_Level.Bucket_Control_Found
         and then Found.Configuration.Rules.Length = 2
         and then Found.Transition_Default_Minimum_Object_Size =
           Lifecycle.Varies_By_Storage_Class
         and then Empty.Kind = Low_Level.Bucket_Control_Found
         and then not Empty.Configuration.Is_Set
         and then Missing.Kind = Low_Level.Get_Bucket_Control_Rejected
         and then US.To_String (Missing.Error.Code) =
           "NoSuchLifecycleConfiguration"
         and then Boundary.Kind = Low_Level.Bucket_Control_Found,
         "GetBucketLifecycleConfiguration response decoding mismatch");
   end;
   Expect_Invalid_Response (201, Document);
   Expect_Invalid_Response (200, Document, Transition_Header => "bad");
   Expect_Invalid_Response
     (404, Error_XML, Transition_Header => "varies_by_storage_class");
   Expect_Invalid_Response
     (200, Document, Request_ID => "request" & Character'Val (10));
   Expect_Invalid_Response
     (200, Document,
      Host_ID => String'(1 .. Header_Boundary + 1 => 'h'));
   Expect_Invalid_Response
     (200, Document,
      Limits =>
        (Maximum_Document_Bytes => Document'Length - 1,
         Maximum_Depth => 64, Maximum_Elements => 1_000,
         Maximum_Text_Bytes => Document'Length));

   Ada.Text_IO.Put_Line
     ("S3 GetBucketLifecycleConfiguration deterministic corpus: OK");
end S3_Get_Bucket_Lifecycle_Configuration_Corpus;
