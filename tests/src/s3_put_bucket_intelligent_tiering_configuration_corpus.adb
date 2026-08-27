with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.HTTP.Client;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Intelligent_Tiering;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Bucket_Intelligent_Tiering_Configuration_Corpus is
   package HTTP_Client renames Flyology.HTTP.Client;
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Intelligent_Tiering renames
     Flyology.Object_Storage.S3.Intelligent_Tiering;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Bucket_Control_Outcome_Kind;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("http://s3.example.test");
   Document : constant String :=
     "<IntelligentTieringConfiguration xmlns=""http://s3.amazonaws.com/" &
     "doc/2006-03-01/""><Id>tier &amp; one</Id><Filter><And>" &
     "<Prefix>logs/</Prefix><Tag><Key>kind</Key><Value>audit</Value>" &
     "</Tag></And></Filter><Status>Enabled</Status><Tiering>" &
     "<Days>90</Days><AccessTier>ARCHIVE_ACCESS</AccessTier></Tiering>" &
     "<Tiering><Days>180</Days><AccessTier>DEEP_ARCHIVE_ACCESS" &
     "</AccessTier></Tiering></IntelligentTieringConfiguration>";
   Error_XML : constant String :=
     "<Error><Code>MalformedXML</Code><Message>invalid</Message></Error>";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Malformed
     (Value  : Intelligent_Tiering.Intelligent_Tiering_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String :=
              Intelligent_Tiering.Serialize (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Intelligent_Tiering.Malformed_Intelligent_Tiering =>
            Raised := True;
      end;
      Require (Raised, "invalid Intelligent-Tiering payload was serialized");
   end Expect_Malformed;

begin
   declare
      Value : constant
        Intelligent_Tiering.Intelligent_Tiering_Configuration :=
          Intelligent_Tiering.Parse (Document, XML.Default_Limits);
      Serialized : constant String :=
        Intelligent_Tiering.Serialize (Value, XML.Default_Limits);
      Parameters : constant
        Low_Level.Put_Bucket_Intelligent_Tiering_Configuration_Parameters :=
          (ID                    => US.To_Unbounded_String ("query tiering"),
           Expected_Bucket_Owner => US.To_Unbounded_String ("owner"));
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Intelligent_Tiering_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Value, Parameters,
           Identity, "us-east-1", "20130524T000000Z", XML.Default_Limits);
      Canonical : constant String := Low_Level.Canonical_Request (Prepared);
   begin
      Require
        (Serialized = Document, "Intelligent-Tiering serialization drift");
      Require
        (Low_Level.Target (Prepared) =
           "/example-bucket?id=query%20tiering&intelligent-tiering"
         and then Low_Level.Owned_Payload_Length (Prepared) =
           Serialized'Length
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-expected-bucket-owner:owner") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-content-sha256:") > 0,
         "Intelligent-Tiering request projection mismatch");

      declare
         Invalid : Intelligent_Tiering.Intelligent_Tiering_Configuration :=
           Value;
      begin
         Invalid.Filter.Is_Set := False;
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Intelligent_Tiering.Intelligent_Tiering_Configuration :=
           Value;
         Tag : Intelligent_Tiering.Intelligent_Tiering_Tag :=
           Invalid.Filter.And_Predicates.Tags.First_Element;
      begin
         Tag.Key := US.Null_Unbounded_String;
         Invalid.Filter.And_Predicates.Tags.Replace_Element (1, Tag);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Intelligent_Tiering.Intelligent_Tiering_Configuration :=
           Value;
      begin
         Invalid.Tierings.Clear;
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Intelligent_Tiering.Intelligent_Tiering_Configuration :=
           Value;
         Transition : Intelligent_Tiering.Tiering :=
           Invalid.Tierings.First_Element;
      begin
         Transition.Days := US.To_Unbounded_String ("ninety");
         Invalid.Tierings.Replace_Element (1, Transition);
         Expect_Malformed (Invalid);
      end;
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length - 1,
          Maximum_Depth => 5, Maximum_Elements => 32,
          Maximum_Text_Bytes => 128));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 4, Maximum_Elements => 32,
          Maximum_Text_Bytes => 128));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 5, Maximum_Elements => 1,
          Maximum_Text_Bytes => 128));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 5, Maximum_Elements => 32,
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
         "Intelligent-Tiering response decoding mismatch");
   end;

   declare
      HTTP : aliased HTTP_Client.Client (Capacity => 1);
      Get_Parameters : constant
        Low_Level.Get_Bucket_Control_With_ID_Parameters :=
          (ID                    => US.To_Unbounded_String ("tiering"),
           Expected_Bucket_Owner => US.Null_Unbounded_String);
      Wrong : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Intelligent_Tiering_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Get_Parameters,
           Identity, "us-east-1", "20130524T000000Z");
      Raised : Boolean := False;
   begin
      HTTP_Client.Configure (HTTP, Origin);
      begin
         declare
            Ignored : constant Low_Level.Put_Bucket_Control_Outcome :=
              Low_Level.Execute_Put_Bucket_Intelligent_Tiering_Configuration
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
     ("S3 PutBucketIntelligentTieringConfiguration deterministic corpus: OK");
end S3_Put_Bucket_Intelligent_Tiering_Configuration_Corpus;
