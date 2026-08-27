with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Analytics;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Bucket_Analytics_Configuration_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Analytics renames Flyology.Object_Storage.S3.Analytics;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Bucket_Control_Outcome_Kind;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("http://s3.example.test");
   Document : constant String :=
     "<AnalyticsConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
     "2006-03-01/""><Id>analytics &amp; one</Id><Filter><And>" &
     "<Prefix>logs/</Prefix><Tag><Key>kind</Key><Value>audit</Value>" &
     "</Tag></And></Filter><StorageClassAnalysis><DataExport>" &
     "<OutputSchemaVersion>V_1</OutputSchemaVersion><Destination>" &
     "<S3BucketDestination><Format>CSV</Format>" &
     "<BucketAccountId>123456789012</BucketAccountId>" &
     "<Bucket>arn:aws:s3:::destination</Bucket><Prefix>reports/</Prefix>" &
     "</S3BucketDestination></Destination></DataExport>" &
     "</StorageClassAnalysis></AnalyticsConfiguration>";
   Error_XML : constant String :=
     "<Error><Code>MalformedXML</Code><Message>invalid</Message></Error>";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Malformed
     (Value  : Analytics.Analytics_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String := Analytics.Serialize (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Analytics.Malformed_Analytics => Raised := True;
      end;
      Require (Raised, "invalid analytics payload was serialized");
   end Expect_Malformed;

begin
   declare
      Value : constant Analytics.Analytics_Configuration :=
        Analytics.Parse (Document, XML.Default_Limits);
      Serialized : constant String :=
        Analytics.Serialize (Value, XML.Default_Limits);
      Parameters : constant
        Low_Level.Put_Bucket_Analytics_Configuration_Parameters :=
          (ID                    =>
             US.To_Unbounded_String ("query analytics"),
           Expected_Bucket_Owner => US.To_Unbounded_String ("owner"));
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Analytics_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Value, Parameters,
           Identity, "us-east-1", "20130524T000000Z", XML.Default_Limits);
      Canonical : constant String := Low_Level.Canonical_Request (Prepared);
   begin
      Require (Serialized = Document, "analytics serialization drift");
      Require
        (Low_Level.Target (Prepared) =
           "/example-bucket?analytics&id=query%20analytics"
         and then Low_Level.Owned_Payload_Length (Prepared) =
           Serialized'Length
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-expected-bucket-owner:owner") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-content-sha256:") > 0,
         "analytics request projection mismatch");

      declare
         Invalid : Analytics.Analytics_Configuration := Value;
      begin
         Invalid.Filter.Is_Set := False;
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Analytics.Analytics_Configuration := Value;
         Tag : Analytics.Analytics_Tag :=
           Invalid.Filter.And_Predicates.Tags.First_Element;
      begin
         Tag.Key := US.Null_Unbounded_String;
         Invalid.Filter.And_Predicates.Tags.Replace_Element (1, Tag);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Analytics.Analytics_Configuration := Value;
      begin
         Invalid.Storage_Class_Analysis.Data_Export.Is_Set := False;
         Expect_Malformed (Invalid);
      end;
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length - 1,
          Maximum_Depth => 6, Maximum_Elements => 21,
          Maximum_Text_Bytes => 96));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 5, Maximum_Elements => 21,
          Maximum_Text_Bytes => 96));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 6, Maximum_Elements => 1,
          Maximum_Text_Bytes => 96));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 6, Maximum_Elements => 21,
          Maximum_Text_Bytes => 1));
   end;

   declare
      Updated : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (200, "", "request", "host", XML.Default_Limits);
      Rejected : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (400, Error_XML, "request", "host", XML.Default_Limits);
   begin
      Require
        (Updated.Kind = Low_Level.Bucket_Control_Updated
         and then Rejected.Kind = Low_Level.Put_Bucket_Control_Rejected
         and then US.To_String (Rejected.Error.Code) = "MalformedXML",
         "analytics response decoding mismatch");
   end;

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Get_Parameters : constant
        Low_Level.Get_Bucket_Control_With_ID_Parameters :=
          (ID                    => US.To_Unbounded_String ("analytics"),
           Expected_Bucket_Owner => US.Null_Unbounded_String);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Analytics_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Get_Parameters,
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      HTTP_Client.Configure (HTTP, Origin);
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Execute_Put_Bucket_Analytics_Configuration
                (HTTP, Wrong, 1.0, null, XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Request => Raised := True;
      end;
      HTTP_Client.Shutdown (HTTP);
      Require (Raised, "wrong prepared operation entered HTTP");
   end;

   Ada.Text_IO.Put_Line
     ("S3 PutBucketAnalyticsConfiguration deterministic corpus: OK");
end S3_Put_Bucket_Analytics_Configuration_Corpus;
