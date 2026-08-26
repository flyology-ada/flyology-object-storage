with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Flyology.HTTP;
with Flyology.Object_Storage.Client.Low_Level;
with Flyology.Object_Storage.S3.Notifications;
with Flyology.Object_Storage.S3.XML;

procedure S3_Bucket_Notification_Configuration_Corpus is
   package Low_Level renames Flyology.Object_Storage.Client.Low_Level;
   package Notifications renames
     Flyology.Object_Storage.S3.Notifications;
   package XML renames Flyology.Object_Storage.S3.XML;
   package US renames Ada.Strings.Unbounded;

   use type Low_Level.Get_Bucket_Control_Outcome_Kind;
   use type Low_Level.Put_Bucket_Control_Outcome_Kind;
   use type Ada.Containers.Count_Type;
   use type Notifications.Event_Kind;
   use type Notifications.Filter_Rule_Name;

   Identity : constant Low_Level.Credentials :=
     Low_Level.Make_Credentials ("AKID", "SECRET");
   Origin : constant Flyology.HTTP.Origin :=
     Flyology.HTTP.Parse_Origin ("https://s3.example.test");
   Error_XML : constant String :=
     "<Error><Code>MalformedXML</Code><Message>bad</Message></Error>";
   Document : constant String :=
     "<NotificationConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
     "2006-03-01/""><TopicConfiguration><Id>topic&lt;&amp;&gt;</Id>" &
     "<Topic>arn:aws:sns:us-east-1:123456789012:topic</Topic>" &
     "<Event>s3:ObjectCreated:*</Event><Event>s3:ObjectTagging:Put</Event>" &
     "<Filter><S3Key><FilterRule><Name>prefix</Name>" &
     "<Value>images/</Value></FilterRule><FilterRule><Name>suffix</Name>" &
     "<Value>.jpg</Value></FilterRule></S3Key></Filter>" &
     "</TopicConfiguration><QueueConfiguration><Queue>" &
     "arn:aws:sqs:us-east-1:123456789012:queue</Queue>" &
     "<Event>s3:ObjectRemoved:Delete</Event><Filter></Filter>" &
     "</QueueConfiguration><CloudFunctionConfiguration>" &
     "<CloudFunction>arn:aws:lambda:us-east-1:123456789012:function:f" &
     "</CloudFunction><Event>s3:ObjectRestore:Completed</Event>" &
     "<Filter><S3Key></S3Key></Filter></CloudFunctionConfiguration>" &
     "<EventBridgeConfiguration></EventBridgeConfiguration>" &
     "</NotificationConfiguration>";

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   procedure Expect_Malformed_Document (Value : String) is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant Notifications.Notification_Configuration :=
              Notifications.Parse (Value, XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Notifications.Malformed_Notification => Raised := True;
      end;
      Require (Raised, "invalid notification document was parsed");
   end Expect_Malformed_Document;

   procedure Expect_Malformed_Value
     (Value  : Notifications.Notification_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant String :=
              Notifications.Serialize (Value, Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Notifications.Malformed_Notification => Raised := True;
      end;
      Require (Raised, "invalid notification value was serialized");
   end Expect_Malformed_Value;

   procedure Expect_Invalid_Get_Response
     (Status : Flyology.HTTP.Status_Code; Payload : String)
   is
      Raised : Boolean := False;
   begin
      begin
         declare
            Ignored : constant
              Low_Level.Get_Bucket_Notification_Configuration_Outcome :=
                Low_Level.Decode_Get_Bucket_Notification_Configuration_Response
                  (Status, Payload, "", "", XML.Default_Limits);
            pragma Unreferenced (Ignored);
         begin
            null;
         end;
      exception
         when Low_Level.Invalid_Response => Raised := True;
      end;
      Require (Raised, "invalid notification response was decoded");
   end Expect_Invalid_Get_Response;

begin
   declare
      Value : constant Notifications.Notification_Configuration :=
        Notifications.Parse (Document, XML.Default_Limits);
      Serialized : constant String :=
        Notifications.Serialize (Value, XML.Default_Limits);
      Get_Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Get_Bucket_Notification_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket",
           (Expected_Bucket_Owner => US.To_Unbounded_String ("owner")),
           Identity, "us-east-1", "20130524T000000Z");
      Put_Prepared : constant Low_Level.Prepared_Request :=
        Low_Level.Prepare_Put_Bucket_Notification_Configuration
          (Origin, Low_Level.Path_Style, "example-bucket", Value,
           (Expected_Bucket_Owner => US.To_Unbounded_String ("owner"),
            Skip_Destination_Validation => (Is_Set => True, Value => False)),
           Identity, "us-east-1", "20130524T000000Z", XML.Default_Limits);
      Put_Canonical : constant String :=
        Low_Level.Canonical_Request (Put_Prepared);
   begin
      Require
        (Serialized = Document,
         "notification full-graph canonical serialization mismatch");
      Require
        (Value.Topics.Length = 1
         and then Value.Queues.Length = 1
         and then Value.Lambdas.Length = 1
         and then Value.Event_Bridge_Is_Set
         and then Value.Topics.First_Element.Events.Element (1) =
           Notifications.Object_Created_All
         and then Value.Topics.First_Element.Filter.Rules.Element (2).Name =
           Notifications.Suffix_Filter,
         "notification full graph lost members or presence");
      Require
        (Low_Level.Target (Get_Prepared) = "/example-bucket?notification"
         and then Ada.Strings.Fixed.Index
           (Low_Level.Canonical_Request (Get_Prepared),
            "x-amz-expected-bucket-owner:owner") > 0,
         "notification GET preparation mismatch");
      Require
        (Low_Level.Target (Put_Prepared) = "/example-bucket?notification"
         and then Low_Level.Owned_Payload_Length (Put_Prepared) =
           Serialized'Length
         and then Ada.Strings.Fixed.Index
           (Put_Canonical, "x-amz-skip-destination-validation:false") > 0
         and then Ada.Strings.Fixed.Index
           (Put_Canonical, "x-amz-expected-bucket-owner:owner") > 0
         and then Ada.Strings.Fixed.Index
           (Put_Canonical, "content-md5:") = 0
         and then Ada.Strings.Fixed.Index
           (Put_Canonical, "x-amz-sdk-checksum-algorithm:") = 0,
         "notification PUT projection or checksum exclusion mismatch");
   end;

   declare
      Empty : constant Notifications.Notification_Configuration :=
        (Topics => <>, Queues => <>, Lambdas => <>,
         Event_Bridge_Is_Set => False);
      Payload : constant String :=
        Notifications.Serialize (Empty, XML.Default_Limits);
      Parsed : constant Notifications.Notification_Configuration :=
        Notifications.Parse (Payload, XML.Default_Limits);
   begin
      Require
        (Payload =
           "<NotificationConfiguration xmlns=""http://s3.amazonaws.com/" &
           "doc/2006-03-01/""></NotificationConfiguration>"
         and then Parsed.Topics.Is_Empty
         and then not Parsed.Event_Bridge_Is_Set,
         "empty notification configuration was not preserved");
   end;

   Expect_Malformed_Document
     ("<NotificationConfiguration><TopicConfiguration><Topic>x</Topic>" &
      "</TopicConfiguration></NotificationConfiguration>");
   Expect_Malformed_Document
     ("<NotificationConfiguration><Unknown/></NotificationConfiguration>");
   Expect_Malformed_Document
     ("<NotificationConfiguration><EventBridgeConfiguration/>" &
      "<EventBridgeConfiguration/></NotificationConfiguration>");

   declare
      Value : Notifications.Notification_Configuration :=
        Notifications.Parse (Document, XML.Default_Limits);
      Topic : Notifications.Topic_Configuration := Value.Topics.First_Element;
   begin
      Topic.Events.Clear;
      Value.Topics.Replace_Element (Value.Topics.First_Index, Topic);
      Expect_Malformed_Value (Value);
   end;
   declare
      Value : Notifications.Notification_Configuration :=
        Notifications.Parse (Document, XML.Default_Limits);
      Topic : Notifications.Topic_Configuration := Value.Topics.First_Element;
   begin
      Topic.ID :=
        (Is_Set => True,
         Value => US.To_Unbounded_String
           (String'
              (Character'Val (16#EF#), Character'Val (16#BF#),
               Character'Val (16#BF#))));
      Value.Topics.Replace_Element (Value.Topics.First_Index, Topic);
      Expect_Malformed_Value (Value);
   end;
   declare
      Value : Notifications.Notification_Configuration :=
        Notifications.Parse (Document, XML.Default_Limits);
      Topic : Notifications.Topic_Configuration := Value.Topics.First_Element;
   begin
      Topic.Filter.Is_Set := False;
      Value.Topics.Replace_Element (Value.Topics.First_Index, Topic);
      Expect_Malformed_Value (Value);
   end;

   declare
      Value : constant Notifications.Notification_Configuration :=
        Notifications.Parse (Document, XML.Default_Limits);
      Canonical : constant String :=
        Notifications.Serialize (Value, XML.Default_Limits);
   begin
      Expect_Malformed_Value
        (Value,
         (Maximum_Document_Bytes => Canonical'Length - 1,
          Maximum_Depth => XML.Default_Limits.Maximum_Depth,
          Maximum_Elements => XML.Default_Limits.Maximum_Elements,
          Maximum_Text_Bytes => XML.Default_Limits.Maximum_Text_Bytes));
   end;

   declare
      Found : constant
        Low_Level.Get_Bucket_Notification_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Notification_Configuration_Response
            (200, Document, "request", "host", XML.Default_Limits);
      Rejected : constant
        Low_Level.Get_Bucket_Notification_Configuration_Outcome :=
          Low_Level.Decode_Get_Bucket_Notification_Configuration_Response
            (400, Error_XML, "request", "host", XML.Default_Limits);
      Updated : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (200, "", "request", "host", XML.Default_Limits);
      Put_Rejected : constant Low_Level.Put_Bucket_Control_Outcome :=
        Low_Level.Decode_Put_Bucket_Control_Response
          (400, Error_XML, "request", "host", XML.Default_Limits);
   begin
      Require
        (Found.Kind = Low_Level.Bucket_Control_Found
         and then Found.Configuration.Event_Bridge_Is_Set
         and then Rejected.Kind = Low_Level.Get_Bucket_Control_Rejected
         and then US.To_String (Rejected.Error.Code) = "MalformedXML"
         and then Updated.Kind = Low_Level.Bucket_Control_Updated
         and then Put_Rejected.Kind = Low_Level.Put_Bucket_Control_Rejected,
         "notification response decoding mismatch");
   end;
   Expect_Invalid_Get_Response (200, "");
   Expect_Invalid_Get_Response (200, "<NotificationConfiguration>");

   Ada.Text_IO.Put_Line
     ("S3 bucket notification configuration deterministic corpus: OK");
end S3_Bucket_Notification_Configuration_Corpus;
