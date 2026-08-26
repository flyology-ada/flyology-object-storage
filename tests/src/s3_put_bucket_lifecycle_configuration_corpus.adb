with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Lifecycle;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Bucket_Lifecycle_Configuration_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Lifecycle renames Flyology.Object_Storage.S3.Lifecycle;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Bucket_Control_Outcome_Kind;
   use type Lifecycle.Transition_Default_Minimum_Size;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
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
   Error_XML : constant String :=
     "<Error><Code>MalformedXML</Code><Message>bad</Message></Error>";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Malformed
     (Value : Lifecycle.Lifecycle_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String := Lifecycle.Serialize (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Lifecycle.Malformed_Lifecycle => Raised := True;
      end;
      Require (Raised, "invalid lifecycle payload was serialized");
   end Expect_Malformed;

   function Parameters
     (Checksum : String := "CRC32";
      Owner : String := "123456789012";
      Transition : String := "varies_by_storage_class")
      return Low_Level.Put_Bucket_Lifecycle_Configuration_Parameters is
     ((Checksum_Algorithm => US.To_Unbounded_String (Checksum),
       Expected_Bucket_Owner => US.To_Unbounded_String (Owner),
       Transition_Default_Minimum_Object_Size =>
         US.To_Unbounded_String (Transition)));

   procedure Expect_Invalid_Request
     (Value : Lifecycle.Lifecycle_Configuration;
      Controls : Low_Level.Put_Bucket_Lifecycle_Configuration_Parameters)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Lifecycle_Configuration
                (Origin, Low_Level.Path_Style, "example-bucket", Value,
                 Controls, Identity, "us-east-1", "20130524T000000Z",
                 XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      Require (Raised, "invalid lifecycle request was prepared");
   end Expect_Invalid_Request;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String;
      Transition : String := "")
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome :=
                Low_Level.Decode_Put_Bucket_Lifecycle_Configuration_Response
                  (Status, Payload, "", "", Transition, XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "invalid lifecycle response was decoded");
   end Expect_Invalid_Response;

begin
   declare
      Value : constant Lifecycle.Lifecycle_Configuration :=
        Lifecycle.Parse (Document);
      Serialized : constant String :=
        Lifecycle.Serialize (Value, XML.Default_Limits);
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Lifecycle_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Value,
           Parameters, Identity, "us-east-1", "20130524T000000Z",
           XML.Default_Limits);
      Canonical : constant String := Low_Level.Canonical_Request (Prepared);
   begin
      Require
        (Serialized = Document,
         "lifecycle full-graph canonical serialization mismatch");
      Require
        (Low_Level.Target (Prepared) = "/example-bucket?lifecycle"
         and then Low_Level.Owned_Payload_Length (Prepared) =
           Serialized'Length
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-sdk-checksum-algorithm:CRC32") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-checksum-crc32:") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-expected-bucket-owner:123456789012") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical,
            "x-amz-transition-default-minimum-object-size:" &
            "varies_by_storage_class") > 0,
         "lifecycle request projection or checksum mismatch");

      declare
         Invalid : Lifecycle.Lifecycle_Configuration := Value;
         Rule : Lifecycle.Lifecycle_Rule := Invalid.Rules.Element (1);
      begin
         Rule.Expiration.Days.Text := US.To_Unbounded_String ("1x");
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Lifecycle.Lifecycle_Configuration := Value;
         Rule : Lifecycle.Lifecycle_Rule := Invalid.Rules.Element (1);
      begin
         Rule.ID :=
           (Is_Set => True,
            Value => US.To_Unbounded_String
              (String'(1 => Character'Val (16#FF#))));
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Lifecycle.Lifecycle_Configuration := Value;
         Rule : Lifecycle.Lifecycle_Rule := Invalid.Rules.Element (1);
      begin
         Rule.ID :=
           (Is_Set => True,
            Value => US.To_Unbounded_String
              (String'
                 (Character'Val (16#EF#),
                  Character'Val (16#BF#),
                  Character'Val (16#BE#))));
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Lifecycle.Lifecycle_Configuration := Value;
         Rule : Lifecycle.Lifecycle_Rule := Invalid.Rules.Element (1);
      begin
         Rule.ID :=
           (Is_Set => True,
            Value => US.To_Unbounded_String
              (String'(1 => Character'Val (1))));
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Lifecycle.Lifecycle_Configuration := Value;
         Rule : Lifecycle.Lifecycle_Rule := Invalid.Rules.Element (1);
         Transition : Lifecycle.Lifecycle_Transition :=
           Rule.Transitions.Element (1);
      begin
         Transition.Storage_Class_Is_Set := False;
         Transition.Storage_Class := Lifecycle.Deep_Archive;
         Rule.Transitions.Replace_Element (1, Transition);
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Lifecycle.Lifecycle_Configuration := Value;
         Rule : Lifecycle.Lifecycle_Rule := Invalid.Rules.Element (1);
         Transition : Lifecycle.Noncurrent_Transition :=
           Rule.Noncurrent_Transitions.Element (1);
      begin
         Transition.Storage_Class_Is_Set := False;
         Transition.Storage_Class := Lifecycle.Deep_Archive;
         Rule.Noncurrent_Transitions.Replace_Element (1, Transition);
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
   end;

   declare
      Missing : Lifecycle.Lifecycle_Configuration;
      Empty : Lifecycle.Lifecycle_Configuration :=
        (Is_Set => True, others => <>);
   begin
      Require
        (Lifecycle.Serialize (Missing, XML.Default_Limits) = "",
         "absent lifecycle configuration did not emit an empty body");
      declare
         Prepared : constant Low_Level.Prepared_Request :=
           Low_Level.Prepare_Put_Bucket_Lifecycle_Configuration
             (Origin, Low_Level.Path_Style, "example-bucket", Missing,
              Parameters, Identity, "us-east-1", "20130524T000000Z",
              XML.Default_Limits);
      begin
         Require
           (Low_Level.Owned_Payload_Length (Prepared) = 0,
            "absent lifecycle body was not preserved through preparation");
      end;
      Expect_Malformed (Empty);
      Empty.Rules.Append
        (Lifecycle.Lifecycle_Rule'(others => <>));
      Empty.Is_Set := False;
      Expect_Malformed (Empty);
   end;

   declare
      Simple_Document : constant String :=
        "<LifecycleConfiguration><Rule><Status>Enabled</Status></Rule>" &
        "</LifecycleConfiguration>";
      Simple : constant Lifecycle.Lifecycle_Configuration :=
        Lifecycle.Parse (Simple_Document);
      Canonical : constant String :=
        Lifecycle.Serialize (Simple, XML.Default_Limits);
      Exact : constant String :=
        Lifecycle.Serialize
          (Simple,
           (Maximum_Document_Bytes => Canonical'Length,
            Maximum_Depth => 3, Maximum_Elements => 3,
            Maximum_Text_Bytes => 7));
   begin
      Require
        (Exact = Canonical, "exact lifecycle serialization limits failed");
      Expect_Malformed
        (Simple,
         (Maximum_Document_Bytes => Canonical'Length - 1,
          Maximum_Depth => 3, Maximum_Elements => 3,
          Maximum_Text_Bytes => 7));
      Expect_Malformed
        (Simple,
         (Maximum_Document_Bytes => Canonical'Length,
          Maximum_Depth => 2, Maximum_Elements => 3,
          Maximum_Text_Bytes => 7));
      Expect_Malformed
        (Simple,
         (Maximum_Document_Bytes => Canonical'Length,
          Maximum_Depth => 3, Maximum_Elements => 2,
          Maximum_Text_Bytes => 7));
      Expect_Malformed
        (Simple,
         (Maximum_Document_Bytes => Canonical'Length,
          Maximum_Depth => 3, Maximum_Elements => 3,
          Maximum_Text_Bytes => 6));
      Expect_Invalid_Request (Simple, Parameters (Checksum => ""));
      Expect_Invalid_Request (Simple, Parameters (Checksum => "CRC16"));
      Expect_Invalid_Request (Simple, Parameters (Transition => "128K"));
   end;

   declare
      Updated : constant
        Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome :=
          Low_Level.Decode_Put_Bucket_Lifecycle_Configuration_Response
            (200, "", "request", "host", "all_storage_classes_128K",
             XML.Default_Limits);
      Rejected : constant
        Low_Level.Put_Bucket_Lifecycle_Configuration_Outcome :=
          Low_Level.Decode_Put_Bucket_Lifecycle_Configuration_Response
            (400, Error_XML, "request", "host", "", XML.Default_Limits);
   begin
      Require
        (Updated.Kind = Low_Level.Bucket_Control_Updated
         and then Updated.Transition_Default_Minimum_Object_Size =
           Lifecycle.All_Storage_Classes_128K
         and then Rejected.Kind = Low_Level.Put_Bucket_Control_Rejected
         and then US.To_String (Rejected.Error.Code) = "MalformedXML",
         "lifecycle mutation response decoding mismatch");
   end;
   Expect_Invalid_Response (200, "unexpected");
   Expect_Invalid_Response (200, "", "invalid");
   Expect_Invalid_Response
     (400, Error_XML, "varies_by_storage_class");

   Ada.Text_IO.Put_Line
     ("S3 PutBucketLifecycleConfiguration deterministic corpus: OK");
end S3_Put_Bucket_Lifecycle_Configuration_Corpus;
