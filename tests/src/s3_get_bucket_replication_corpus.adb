with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Replication;
with Flyology.Object_Storage.S3.XML;

procedure S3_Get_Bucket_Replication_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Replication renames Flyology.Object_Storage.S3.Replication;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Ada.Containers.Count_Type;
   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Replication.Status_Kind;
   use type Replication.Storage_Class_Kind;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>ReplicationConfigurationNotFoundError</Code>" &
     "<Message>missing</Message></Error>";
   Document : constant String :=
     "<ReplicationConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
     "2006-03-01/""><Role>arn:aws:iam::123456789012:role/repl" &
     "</Role><Rule><ID>full&lt;&amp;&gt;</ID>" &
     "<Priority>-123456789012345678901234567890</Priority>" &
     "<Prefix>legacy/</Prefix><Filter><Prefix>current/</Prefix>" &
     "<Tag><Key>single</Key><Value>tag</Value></Tag><And>" &
     "<Prefix>and/</Prefix><Tag><Key>one</Key><Value>1</Value>" &
     "</Tag><Tag><Key>two</Key><Value>2</Value></Tag></And></Filter>" &
     "<Status>Enabled</Status><SourceSelectionCriteria>" &
     "<SseKmsEncryptedObjects><Status>Enabled</Status>" &
     "</SseKmsEncryptedObjects><ReplicaModifications>" &
     "<Status>Disabled</Status></ReplicaModifications>" &
     "</SourceSelectionCriteria><ExistingObjectReplication>" &
     "<Status>Enabled</Status></ExistingObjectReplication>" &
     "<Destination><Bucket>arn:aws:s3:::replica</Bucket>" &
     "<Account>123456789012</Account><StorageClass>DEEP_ARCHIVE" &
     "</StorageClass><AccessControlTranslation><Owner>Destination" &
     "</Owner></AccessControlTranslation><EncryptionConfiguration>" &
     "<ReplicaKmsKeyID>arn:aws:kms:us-east-1:123456789012:key/id" &
     "</ReplicaKmsKeyID></EncryptionConfiguration><ReplicationTime>" &
     "<Status>Enabled</Status><Time><Minutes>+invalid</Minutes></Time>" &
     "</ReplicationTime><Metrics><Status>Disabled</Status>" &
     "<EventThreshold><Minutes>15</Minutes></EventThreshold></Metrics>" &
     "</Destination><DeleteMarkerReplication><Status>Disabled</Status>" &
     "</DeleteMarkerReplication></Rule></ReplicationConfiguration>";
   Valid_Document : constant String :=
     Ada.Strings.Fixed.Replace_Slice
       (Document,
        Ada.Strings.Fixed.Index (Document, "+invalid"),
        Ada.Strings.Fixed.Index (Document, "+invalid") + 7,
        "999999999999999999999999999999999999");

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Malformed (Value : String) is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Replication.Replication_Configuration :=
              Replication.Parse (Value, XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Replication.Malformed_Replication => Raised := True;
      end;
      Require (Raised, "invalid replication document was parsed");
   end Expect_Malformed;

   procedure Expect_Invalid_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Low_Level.Get_Bucket_Replication_Outcome :=
              Low_Level.Decode_Get_Bucket_Replication_Response
                (Status, Payload, "", "", XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "invalid replication response was decoded");
   end Expect_Invalid_Response;

   function Wire (Value : Replication.Storage_Class_Kind) return String is
     (case Value is
         when Replication.Standard => "STANDARD",
         when Replication.Reduced_Redundancy => "REDUCED_REDUNDANCY",
         when Replication.Standard_IA => "STANDARD_IA",
         when Replication.One_Zone_IA => "ONEZONE_IA",
         when Replication.Intelligent_Tiering => "INTELLIGENT_TIERING",
         when Replication.Glacier => "GLACIER",
         when Replication.Deep_Archive => "DEEP_ARCHIVE",
         when Replication.Outposts => "OUTPOSTS",
         when Replication.Glacier_Instant_Retrieval => "GLACIER_IR",
         when Replication.Snow => "SNOW",
         when Replication.Express_One_Zone => "EXPRESS_ONEZONE",
         when Replication.FSX_OpenZFS => "FSX_OPENZFS",
         when Replication.FSX_ONTAP => "FSX_ONTAP",
         when Replication.AWS_Backup_Warm => "AWS_BACKUP_WARM",
         when Replication.AWS_Backup_Low_Cost_Warm =>
           "AWS_BACKUP_LOW_COST_WARM");

begin
   Expect_Malformed (Document);
   declare
      Value : constant Replication.Replication_Configuration :=
        Replication.Parse (Valid_Document, XML.Default_Limits);
      Rule : constant Replication.Replication_Rule :=
        Value.Rules.First_Element;
   begin
      Require
        (US.To_String (Value.Role) =
           "arn:aws:iam::123456789012:role/repl"
         and then Value.Rules.Length = 1
         and then Rule.Status = Replication.Enabled
         and then US.To_String (Rule.Priority.Text) =
           "-123456789012345678901234567890"
         and then Rule.Filter.Tag.Is_Set
         and then Rule.Filter.And_Predicates.Tags.Length = 2
         and then Rule.Source_Selection.SSE_KMS_Encrypted_Objects.Status =
           Replication.Enabled
         and then Rule.Source_Selection.SSE_KMS_Encrypted_Objects.
           Status_Is_Set
         and then Rule.Target.Storage_Class = Replication.Deep_Archive
         and then Rule.Target.Access_Control.Is_Set
         and then Rule.Target.Time.Time.Minutes.Is_Set
         and then Rule.Target.Metrics.Event_Threshold.Minutes.Is_Set
         and then Rule.Delete_Marker_Replication.Status =
           Replication.Disabled
         and then Rule.Delete_Marker_Replication.Status_Is_Set,
         "replication full graph lost members or presence");
   end;

   for Storage_Class in Replication.Storage_Class_Kind loop
      declare
         Value : constant Replication.Replication_Configuration :=
           Replication.Parse
             ("<ReplicationConfiguration><Role>r</Role><Rule>" &
              "<Status>Disabled</Status><Destination><Bucket>b</Bucket>" &
              "<StorageClass>" & Wire (Storage_Class) & "</StorageClass>" &
              "</Destination></Rule></ReplicationConfiguration>",
              XML.Default_Limits);
      begin
         Require
           (Value.Rules.First_Element.Target.Storage_Class = Storage_Class,
            "replication storage-class domain mismatch");
      end;
   end loop;

   declare
      Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Replication
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String ("owner")),
           Identity, "us-east-1", "20130524T000000Z");
   begin
      Require
        (Low_Level.Target (Prepared) = "/example-bucket?replication"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Canonical_Request (Prepared),
            "x-amz-expected-bucket-owner:owner") > 0,
         "replication GET preparation mismatch");
   end;

   declare
      Found : constant Low_Level.Get_Bucket_Replication_Outcome :=
        Low_Level.Decode_Get_Bucket_Replication_Response
          (200, Valid_Document, "request", "host", XML.Default_Limits);
      Rejected : constant Low_Level.Get_Bucket_Replication_Outcome :=
        Low_Level.Decode_Get_Bucket_Replication_Response
          (404, Error_XML, "request", "host", XML.Default_Limits);
   begin
      Require
        (Found.Kind = Low_Level.Bucket_Control_Found
         and then Found.Status = 200
         and then Found.Configuration.Rules.Length = 1
         and then Rejected.Kind = Low_Level.Get_Bucket_Control_Rejected
         and then US.To_String (Rejected.Error.Code) =
           "ReplicationConfigurationNotFoundError",
         "replication response decoding mismatch");
   end;

   Expect_Malformed
     ("<ReplicationConfiguration><Rule><Status>Enabled</Status>" &
      "<Destination><Bucket>b</Bucket></Destination></Rule>" &
      "</ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Destination><Bucket>b</Bucket></Destination></Rule>" &
      "</ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Destination></Destination></Rule>" &
      "</ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Future</Status><Destination><Bucket>b</Bucket>" &
      "</Destination></Rule></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Destination><Bucket>b</Bucket>" &
      "<StorageClass>FUTURE</StorageClass></Destination></Rule>" &
      "</ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Filter><Tag><Key>incomplete</Key>" &
      "</Tag></Filter><Destination><Bucket>b</Bucket></Destination>" &
      "</Rule></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><SourceSelectionCriteria>" &
      "<SseKmsEncryptedObjects></SseKmsEncryptedObjects>" &
      "</SourceSelectionCriteria><Destination><Bucket>b</Bucket>" &
      "</Destination></Rule></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><ExistingObjectReplication>" &
      "</ExistingObjectReplication><Destination><Bucket>b</Bucket>" &
      "</Destination></Rule></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Destination><Bucket>b</Bucket>" &
      "<AccessControlTranslation></AccessControlTranslation>" &
      "</Destination></Rule></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Destination><Bucket>b</Bucket>" &
      "<ReplicationTime><Status>Enabled</Status></ReplicationTime>" &
      "</Destination></Rule></ReplicationConfiguration>");
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Destination><Bucket>b</Bucket>" &
      "<Metrics></Metrics></Destination></Rule>" &
      "</ReplicationConfiguration>");
   declare
      Value : constant Replication.Replication_Configuration :=
        Replication.Parse
          ("<ReplicationConfiguration><Role>r</Role><Rule>" &
           "<Status>Enabled</Status><Destination><Bucket>b</Bucket>" &
           "</Destination><DeleteMarkerReplication>" &
           "</DeleteMarkerReplication></Rule></ReplicationConfiguration>",
           XML.Default_Limits);
   begin
      Require
        (Value.Rules.First_Element.Delete_Marker_Replication.Is_Set
         and then not Value.Rules.First_Element.Delete_Marker_Replication.
           Status_Is_Set,
         "optional delete-marker status presence was not preserved");
   end;
   Expect_Malformed
     ("<ReplicationConfiguration><Role>r</Role><Rule>" &
      "<Status>Enabled</Status><Destination><Bucket>b</Bucket>" &
      "</Destination></Rule><Unknown/></ReplicationConfiguration>");

   declare
      Tight : constant XML.Parse_Limits :=
        (Maximum_Document_Bytes => Valid_Document'Length - 1,
         Maximum_Depth          => XML.Default_Limits.Maximum_Depth,
         Maximum_Elements       => XML.Default_Limits.Maximum_Elements,
         Maximum_Text_Bytes     => XML.Default_Limits.Maximum_Text_Bytes);
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Replication.Replication_Configuration :=
              Replication.Parse (Valid_Document, Tight);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Replication.Malformed_Replication => Raised := True;
      end;
      Require (Raised, "replication document limit was not enforced");
   end;

   Expect_Invalid_Response (200, "");
   Expect_Invalid_Response (200, "<ReplicationConfiguration>");

   Ada.Text_IO.Put_Line
     ("S3 GetBucketReplication deterministic corpus: OK");
end S3_Get_Bucket_Replication_Corpus;
