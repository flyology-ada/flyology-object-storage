with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Replication;
with Flyology.Object_Storage.S3.XML;

procedure S3_Put_Bucket_Replication_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Replication renames Flyology.Object_Storage.S3.Replication;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Put_Bucket_Control_Outcome_Kind;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Document : constant String :=
     "<ReplicationConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
     "2006-03-01/""><Role>role&lt;&amp;&gt;</Role><Rule>" &
     "<ID>rule</ID><Priority>-12</Priority><Filter><And>" &
     "<Prefix>logs/</Prefix><Tag><Key>one</Key><Value>1</Value>" &
     "</Tag></And></Filter><Status>Enabled</Status>" &
     "<SourceSelectionCriteria><SseKmsEncryptedObjects>" &
     "<Status>Enabled</Status></SseKmsEncryptedObjects>" &
     "</SourceSelectionCriteria><ExistingObjectReplication>" &
     "<Status>Disabled</Status></ExistingObjectReplication>" &
     "<Destination><Bucket>arn:aws:s3:::replica</Bucket>" &
     "<StorageClass>DEEP_ARCHIVE</StorageClass>" &
     "<AccessControlTranslation><Owner>Destination</Owner>" &
     "</AccessControlTranslation><EncryptionConfiguration>" &
     "<ReplicaKmsKeyID>key</ReplicaKmsKeyID>" &
     "</EncryptionConfiguration><ReplicationTime><Status>Enabled" &
     "</Status><Time><Minutes>15</Minutes></Time></ReplicationTime>" &
     "<Metrics><Status>Disabled</Status><EventThreshold><Minutes>20" &
     "</Minutes></EventThreshold></Metrics></Destination>" &
     "<DeleteMarkerReplication></DeleteMarkerReplication>" &
     "</Rule></ReplicationConfiguration>";
   Error_XML : constant String :=
     "<Error><Code>MalformedXML</Code><Message>bad</Message></Error>";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Parameters
     (Checksum : String := "CRC32";
      MD5      : String := "";
      Token    : String := "token")
      return Low_Level.Put_Bucket_Replication_Parameters is
     ((Content_MD5           => US.To_Unbounded_String (MD5),
       Checksum_Algorithm    => US.To_Unbounded_String (Checksum),
       Token                 => US.To_Unbounded_String (Token),
       Expected_Bucket_Owner => US.To_Unbounded_String ("owner")));

   procedure Expect_Malformed
     (Value  : Replication.Replication_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String := Replication.Serialize (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Replication.Malformed_Replication => Raised := True;
      end;
      Require (Raised, "invalid replication payload was serialized");
   end Expect_Malformed;

   procedure Expect_Invalid_Request
     (Value : Replication.Replication_Configuration;
      Controls : Low_Level.Put_Bucket_Replication_Parameters)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Prepared_Request :=
              Low_Level.Prepare_Put_Bucket_Replication
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
      Require (Raised, "invalid replication request was prepared");
   end Expect_Invalid_Request;

begin
   declare
      Value : constant Replication.Replication_Configuration :=
        Replication.Parse (Document, XML.Default_Limits);
      Serialized : constant String :=
        Replication.Serialize (Value, XML.Default_Limits);
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Replication
          (Origin, Low_Level.Path_Style, "example-bucket", Value, Parameters,
           Identity, "us-east-1", "20130524T000000Z", XML.Default_Limits);
      Canonical : constant String := Low_Level.Canonical_Request (Prepared);
   begin
      Require (Serialized = Document, "replication serialization drift");
      Require
        (Low_Level.Target (Prepared) = "/example-bucket?replication"
         and then Low_Level.Owned_Payload_Length (Prepared) =
           Serialized'Length
         and then Ada.Strings.Fixed.Index (Canonical, "content-md5:") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-sdk-checksum-algorithm:CRC32") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-checksum-crc32:") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-bucket-object-lock-token:token") > 0
         and then Ada.Strings.Fixed.Index
           (Canonical, "x-amz-expected-bucket-owner:owner") > 0,
         "replication request projection mismatch");

      declare
         With_Del : Replication.Replication_Configuration := Value;
      begin
         --  XML 1.0's Char production includes U+007F; this boundary guards
         --  against narrowing modeled text to printable ASCII.
         With_Del.Role :=
           US.To_Unbounded_String ("role" & Character'Val (16#7F#));
         Require
           (Ada.Strings.Fixed.Index
              (Replication.Serialize (With_Del, XML.Default_Limits),
               "role" & Character'Val (16#7F#)) > 0,
            "XML 1.0 U+007F text was rejected");
      end;

      declare
         Invalid : Replication.Replication_Configuration := Value;
         Rule : Replication.Replication_Rule := Invalid.Rules.First_Element;
      begin
         Rule.Priority.Text := US.To_Unbounded_String ("+1");
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Replication.Replication_Configuration := Value;
         Rule : Replication.Replication_Rule := Invalid.Rules.First_Element;
      begin
         Rule.Target.Storage_Class_Is_Set := False;
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;
      declare
         Invalid : Replication.Replication_Configuration := Value;
         Rule : Replication.Replication_Rule := Invalid.Rules.First_Element;
      begin
         Rule.Source_Selection.Is_Set := False;
         Invalid.Rules.Replace_Element (1, Rule);
         Expect_Malformed (Invalid);
      end;

      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length - 1,
          Maximum_Depth => 6, Maximum_Elements => 32,
          Maximum_Text_Bytes => 64));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 5, Maximum_Elements => 32,
          Maximum_Text_Bytes => 64));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 6, Maximum_Elements => 1,
          Maximum_Text_Bytes => 64));
      Expect_Malformed
        (Value,
         (Maximum_Document_Bytes => Serialized'Length,
          Maximum_Depth => 6, Maximum_Elements => 32,
          Maximum_Text_Bytes => 1));
      Expect_Invalid_Request (Value, Parameters (Checksum => ""));
      Expect_Invalid_Request (Value, Parameters (Checksum => "CRC16"));
      Expect_Invalid_Request (Value, Parameters (MD5 => "invalid"));
      Expect_Invalid_Request
        (Value, Parameters (Token => String'(1 => Character'Val (10))));
   end;

   declare
      Empty : Replication.Replication_Configuration;
   begin
      Expect_Malformed (Empty);
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
         "replication response decoding mismatch");
   end;

   Ada.Text_IO.Put_Line ("S3 PutBucketReplication deterministic corpus: OK");
end S3_Put_Bucket_Replication_Corpus;
