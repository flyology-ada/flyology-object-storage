package body Flyology.Object_Storage.S3.Notifications is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Configuration_Kind is
     (No_Configuration, Topic_Configuration_Kind,
      Queue_Configuration_Kind, Lambda_Configuration_Kind,
      Event_Bridge_Configuration_Kind);
   type Scalar_Kind is
     (No_Scalar, ID_Scalar, Destination_Scalar, Event_Scalar,
      Filter_Name_Scalar, Filter_Value_Scalar);

   function Empty_Optional_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Filter return Notification_Filter is
     ((Is_Set => False, Key_Is_Set => False, Rules => <>));

   type Notification_Handler is new XML.Event_Handler with record
      Depth             : Natural := 0;
      Root_Seen         : Boolean := False;
      Namespace         : Namespace_Style := Namespace_Not_Selected;
      Configuration     : Configuration_Kind := No_Configuration;
      Scalar            : Scalar_Kind := No_Scalar;
      ID_Seen           : Boolean := False;
      Destination_Seen  : Boolean := False;
      Event_Seen        : Boolean := False;
      Filter_Seen       : Boolean := False;
      Key_Seen          : Boolean := False;
      Name_Seen         : Boolean := False;
      Value_Seen        : Boolean := False;
      Text_Value        : US.Unbounded_String;
      Current_ID        : Optional_String := Empty_Optional_String;
      Current_Destination : US.Unbounded_String;
      Current_Events    : Event_Vectors.Vector;
      Current_Filter    : Notification_Filter := Empty_Filter;
      Current_Rule      : Filter_Rule :=
        (Name_Is_Set => False,
         Name        => Prefix_Filter,
         Value       => Empty_Optional_String);
      Value             : Notification_Configuration :=
        (Topics              => <>,
         Queues              => <>,
         Lambdas             => <>,
         Event_Bridge_Is_Set => False);
   end record;

   overriding procedure Start_Element
     (Item : in out Notification_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Notification_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Notification_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Notification_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Notification with
              "text outside bucket-notification scalar";
         end if;
      end loop;
   end Require_Whitespace;

   function Event_Text (Item : Event_Kind) return String is
     (case Item is
         when Reduced_Redundancy_Lost_Object =>
           "s3:ReducedRedundancyLostObject",
         when Object_Created_All => "s3:ObjectCreated:*",
         when Object_Created_Put => "s3:ObjectCreated:Put",
         when Object_Created_Post => "s3:ObjectCreated:Post",
         when Object_Created_Copy => "s3:ObjectCreated:Copy",
         when Object_Created_Complete_Multipart_Upload =>
           "s3:ObjectCreated:CompleteMultipartUpload",
         when Object_Removed_All => "s3:ObjectRemoved:*",
         when Object_Removed_Delete => "s3:ObjectRemoved:Delete",
         when Object_Removed_Delete_Marker_Created =>
           "s3:ObjectRemoved:DeleteMarkerCreated",
         when Object_Restore_All => "s3:ObjectRestore:*",
         when Object_Restore_Post => "s3:ObjectRestore:Post",
         when Object_Restore_Completed => "s3:ObjectRestore:Completed",
         when Replication_All => "s3:Replication:*",
         when Replication_Operation_Failed =>
           "s3:Replication:OperationFailedReplication",
         when Replication_Operation_Not_Tracked =>
           "s3:Replication:OperationNotTracked",
         when Replication_Operation_Missed_Threshold =>
           "s3:Replication:OperationMissedThreshold",
         when Replication_Operation_Replicated_After_Threshold =>
           "s3:Replication:OperationReplicatedAfterThreshold",
         when Object_Restore_Delete => "s3:ObjectRestore:Delete",
         when Lifecycle_Transition => "s3:LifecycleTransition",
         when Intelligent_Tiering => "s3:IntelligentTiering",
         when Object_ACL_Put => "s3:ObjectAcl:Put",
         when Lifecycle_Expiration_All => "s3:LifecycleExpiration:*",
         when Lifecycle_Expiration_Delete =>
           "s3:LifecycleExpiration:Delete",
         when Lifecycle_Expiration_Delete_Marker_Created =>
           "s3:LifecycleExpiration:DeleteMarkerCreated",
         when Object_Tagging_All => "s3:ObjectTagging:*",
         when Object_Tagging_Put => "s3:ObjectTagging:Put",
         when Object_Tagging_Delete => "s3:ObjectTagging:Delete",
         when Object_Annotation_All => "s3:ObjectAnnotation:*",
         when Object_Annotation_Put => "s3:ObjectAnnotation:Put",
         when Object_Annotation_Delete => "s3:ObjectAnnotation:Delete");

   function Parse_Event (Value : String) return Event_Kind is
   begin
      for Item in Event_Kind loop
         if Value = Event_Text (Item) then
            return Item;
         end if;
      end loop;
      raise Malformed_Notification with "invalid bucket-notification event";
   end Parse_Event;

   function Filter_Name_Text (Item : Filter_Rule_Name) return String is
     (case Item is
         when Prefix_Filter => "prefix",
         when Suffix_Filter => "suffix");

   function Parse_Filter_Name (Value : String) return Filter_Rule_Name is
   begin
      if Value = "prefix" then
         return Prefix_Filter;
      elsif Value = "suffix" then
         return Suffix_Filter;
      end if;
      raise Malformed_Notification with
        "invalid bucket-notification filter name";
   end Parse_Filter_Name;

   function Configuration_For (Local_Name : String)
      return Configuration_Kind is
   begin
      if Local_Name = "TopicConfiguration" then
         return Topic_Configuration_Kind;
      elsif Local_Name = "QueueConfiguration" then
         return Queue_Configuration_Kind;
      elsif Local_Name = "CloudFunctionConfiguration" then
         return Lambda_Configuration_Kind;
      elsif Local_Name = "EventBridgeConfiguration" then
         return Event_Bridge_Configuration_Kind;
      end if;
      return No_Configuration;
   end Configuration_For;

   function Destination_Name (Kind : Configuration_Kind) return String is
     (case Kind is
         when Topic_Configuration_Kind => "Topic",
         when Queue_Configuration_Kind => "Queue",
         when Lambda_Configuration_Kind => "CloudFunction",
         when others => "");

   overriding procedure Start_Element_Details
     (Item            : in out Notification_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      Style : constant Namespace_Style :=
        (if Namespace_URI'Length = 0 then Unqualified
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then S3_Qualified
         else Namespace_Not_Selected);
   begin
      if Attribute_Count /= 0
        or else Style = Namespace_Not_Selected
        or else (Item.Namespace /= Namespace_Not_Selected
                 and then Item.Namespace /= Style)
      then
         raise Malformed_Notification with
           "bucket-notification namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Reset_Current (Item : in out Notification_Handler) is
   begin
      Item.Scalar := No_Scalar;
      Item.ID_Seen := False;
      Item.Destination_Seen := False;
      Item.Event_Seen := False;
      Item.Filter_Seen := False;
      Item.Key_Seen := False;
      Item.Name_Seen := False;
      Item.Value_Seen := False;
      Item.Text_Value := US.Null_Unbounded_String;
      Item.Current_ID := Empty_Optional_String;
      Item.Current_Destination := US.Null_Unbounded_String;
      Item.Current_Events.Clear;
      Item.Current_Filter := Empty_Filter;
      Item.Current_Rule :=
        (Name_Is_Set => False,
         Name        => Prefix_Filter,
         Value       => Empty_Optional_String);
   end Reset_Current;

   overriding procedure Start_Element
     (Item : in out Notification_Handler; Local_Name : String)
   is
      Kind : Configuration_Kind;
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Notification with
           "bucket-notification depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen
              or else Local_Name /= "NotificationConfiguration"
            then
               raise Malformed_Notification with
                 "invalid NotificationConfiguration root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            Kind := Configuration_For (Local_Name);
            if Kind = No_Configuration
              or else (Kind = Event_Bridge_Configuration_Kind
                       and then Item.Value.Event_Bridge_Is_Set)
            then
               raise Malformed_Notification with
                 "unknown or duplicate bucket-notification member";
            end if;
            Item.Configuration := Kind;
            Reset_Current (Item);
            if Kind = Event_Bridge_Configuration_Kind then
               Item.Value.Event_Bridge_Is_Set := True;
            end if;
         when 3 =>
            if Item.Configuration = Event_Bridge_Configuration_Kind then
               raise Malformed_Notification with
                 "nested EventBridgeConfiguration member";
            elsif Local_Name = "Id" and then not Item.ID_Seen then
               Item.ID_Seen := True;
               Item.Scalar := ID_Scalar;
            elsif Local_Name = Destination_Name (Item.Configuration)
              and then not Item.Destination_Seen
            then
               Item.Destination_Seen := True;
               Item.Scalar := Destination_Scalar;
            elsif Local_Name = "Event" then
               Item.Event_Seen := True;
               Item.Scalar := Event_Scalar;
            elsif Local_Name = "Filter" and then not Item.Filter_Seen then
               Item.Filter_Seen := True;
               Item.Current_Filter.Is_Set := True;
               Item.Scalar := No_Scalar;
            else
               raise Malformed_Notification with
                 "unknown or duplicate destination member";
            end if;
            Item.Text_Value := US.Null_Unbounded_String;
         when 4 =>
            if Item.Filter_Seen and then Item.Scalar = No_Scalar
              and then Local_Name = "S3Key" and then not Item.Key_Seen
            then
               Item.Key_Seen := True;
               Item.Current_Filter.Key_Is_Set := True;
            else
               raise Malformed_Notification with
                 "invalid notification filter member";
            end if;
         when 5 =>
            if Item.Key_Seen and then Local_Name = "FilterRule" then
               Item.Name_Seen := False;
               Item.Value_Seen := False;
               Item.Current_Rule :=
                 (Name_Is_Set => False,
                  Name        => Prefix_Filter,
                  Value       => Empty_Optional_String);
            else
               raise Malformed_Notification with
                 "invalid S3Key filter member";
            end if;
         when 6 =>
            if Local_Name = "Name" and then not Item.Name_Seen then
               Item.Name_Seen := True;
               Item.Scalar := Filter_Name_Scalar;
            elsif Local_Name = "Value" and then not Item.Value_Seen then
               Item.Value_Seen := True;
               Item.Scalar := Filter_Value_Scalar;
            else
               raise Malformed_Notification with
                 "unknown or duplicate FilterRule member";
            end if;
            Item.Text_Value := US.Null_Unbounded_String;
         when others =>
            raise Malformed_Notification with
              "nested bucket-notification member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Notification_Handler; Value : String) is
   begin
      if (Item.Depth = 3
          and then Item.Scalar in ID_Scalar .. Event_Scalar)
        or else (Item.Depth = 6
                 and then Item.Scalar in
                   Filter_Name_Scalar .. Filter_Value_Scalar)
      then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 5 then
         Require_Whitespace (Value);
      else
         raise Malformed_Notification with
           "bucket-notification text outside modeled member";
      end if;
   end Text;

   procedure Close_Scalar
     (Item : in out Notification_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when ID_Scalar =>
            if Local_Name /= "Id" then
               raise Malformed_Notification with "mismatched Id close";
            end if;
            Item.Current_ID := (Is_Set => True, Value => Item.Text_Value);
         when Destination_Scalar =>
            if Local_Name /= Destination_Name (Item.Configuration) then
               raise Malformed_Notification with
                 "mismatched notification destination close";
            end if;
            Item.Current_Destination := Item.Text_Value;
         when Event_Scalar =>
            if Local_Name /= "Event" then
               raise Malformed_Notification with "mismatched Event close";
            end if;
            Item.Current_Events.Append (Parse_Event (Value));
         when Filter_Name_Scalar =>
            if Local_Name /= "Name" then
               raise Malformed_Notification with "mismatched Name close";
            end if;
            Item.Current_Rule.Name_Is_Set := True;
            Item.Current_Rule.Name := Parse_Filter_Name (Value);
         when Filter_Value_Scalar =>
            if Local_Name /= "Value" then
               raise Malformed_Notification with "mismatched Value close";
            end if;
            Item.Current_Rule.Value :=
              (Is_Set => True, Value => Item.Text_Value);
         when No_Scalar =>
            raise Malformed_Notification with
              "notification close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Close_Scalar;

   overriding procedure End_Element
     (Item : in out Notification_Handler; Local_Name : String) is
   begin
      case Item.Depth is
         when 6 =>
            Close_Scalar (Item, Local_Name);
            Item.Depth := 5;
         when 5 =>
            if Local_Name /= "FilterRule" or else Item.Scalar /= No_Scalar
            then
               raise Malformed_Notification with
                 "incomplete FilterRule structure";
            end if;
            Item.Current_Filter.Rules.Append (Item.Current_Rule);
            Item.Depth := 4;
         when 4 =>
            if Local_Name /= "S3Key" or else not Item.Key_Seen then
               raise Malformed_Notification with
                 "incomplete S3Key structure";
            end if;
            Item.Depth := 3;
         when 3 =>
            if Item.Scalar /= No_Scalar then
               Close_Scalar (Item, Local_Name);
            elsif Local_Name /= "Filter" or else not Item.Filter_Seen then
               raise Malformed_Notification with
                 "incomplete notification Filter structure";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Configuration_For (Local_Name) /= Item.Configuration then
               raise Malformed_Notification with
                 "mismatched notification configuration close";
            end if;
            case Item.Configuration is
               when Topic_Configuration_Kind =>
                  if not Item.Destination_Seen or else not Item.Event_Seen then
                     raise Malformed_Notification with
                       "incomplete topic notification configuration";
                  end if;
                  Item.Value.Topics.Append
                    (Topic_Configuration'
                       (ID        => Item.Current_ID,
                        Topic_ARN => Item.Current_Destination,
                        Events    => Item.Current_Events,
                        Filter    => Item.Current_Filter));
               when Queue_Configuration_Kind =>
                  if not Item.Destination_Seen or else not Item.Event_Seen then
                     raise Malformed_Notification with
                       "incomplete queue notification configuration";
                  end if;
                  Item.Value.Queues.Append
                    (Queue_Configuration'
                       (ID        => Item.Current_ID,
                        Queue_ARN => Item.Current_Destination,
                        Events    => Item.Current_Events,
                        Filter    => Item.Current_Filter));
               when Lambda_Configuration_Kind =>
                  if not Item.Destination_Seen or else not Item.Event_Seen then
                     raise Malformed_Notification with
                       "incomplete Lambda notification configuration";
                  end if;
                  Item.Value.Lambdas.Append
                    (Lambda_Configuration'
                       (ID                  => Item.Current_ID,
                        Lambda_Function_ARN => Item.Current_Destination,
                        Events              => Item.Current_Events,
                        Filter              => Item.Current_Filter));
               when Event_Bridge_Configuration_Kind =>
                  null;
               when No_Configuration =>
                  raise Malformed_Notification with
                    "notification close without configuration";
            end case;
            Item.Configuration := No_Configuration;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "NotificationConfiguration"
              or else Item.Configuration /= No_Configuration
            then
               raise Malformed_Notification with
                 "incomplete NotificationConfiguration";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Notification with
              "invalid bucket-notification closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Notification_Configuration
   is
      Handler : aliased Notification_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Notification with
           "incomplete bucket-notification document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Notification with
           "malformed bucket-notification XML";
   end Parse;

   function Serialize
     (Value  : Notification_Configuration;
      Limits : XML.Parse_Limits) return String
   is
      Result       : US.Unbounded_String;
      Elements     : Natural := 1;
      Text_Bytes   : Natural := 0;
      Actual_Depth : Positive := 1;

      --  Pinned PutBucketNotificationConfiguration REST/XML root and
      --  namespace. Changing either changes request signing and compatibility.
      Prefix : constant String :=
        "<NotificationConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">";
      Suffix : constant String := "</NotificationConfiguration>";

      --  XML 1.0 permits the represented UTF-8 scalar ranges but excludes
      --  surrogate encodings and U+FFFE/U+FFFF. This validation precedes XML
      --  escaping so the serialized request remains a valid signed document.
      function Valid_XML_UTF8 (Text : String) return Boolean is
         Cursor : Integer := Text'First;

         function Byte_At (Offset : Natural) return Natural is
           (Character'Pos (Text (Cursor + Integer (Offset))));

         function Continuation (Offset : Natural) return Boolean is
           (Offset <= Natural (Text'Last - Cursor)
            and then Byte_At (Offset) in 16#80# .. 16#BF#);
      begin
         while Cursor <= Text'Last loop
            declare
               First : constant Natural := Byte_At (0);
               Width : Positive;
            begin
               if First in 16#20# .. 16#7E#
                 or else First in 16#09# | 16#0A# | 16#0D#
               then
                  Width := 1;
               elsif First in 16#C2# .. 16#DF#
                 and then Continuation (1)
               then
                  Width := 2;
               elsif First in 16#E0# .. 16#EF#
                 and then Continuation (1) and then Continuation (2)
                 and then (First /= 16#E0# or else Byte_At (1) >= 16#A0#)
                 and then (First /= 16#ED# or else Byte_At (1) <= 16#9F#)
                 and then
                   (First /= 16#EF#
                    or else Byte_At (1) /= 16#BF#
                    or else Byte_At (2) not in 16#BE# .. 16#BF#)
               then
                  Width := 3;
               elsif First in 16#F0# .. 16#F4#
                 and then Continuation (1) and then Continuation (2)
                 and then Continuation (3)
                 and then (First /= 16#F0# or else Byte_At (1) >= 16#90#)
                 and then (First /= 16#F4# or else Byte_At (1) <= 16#8F#)
               then
                  Width := 4;
               else
                  return False;
               end if;
               if Width - 1 = Natural (Text'Last - Cursor) then
                  return True;
               end if;
               Cursor := Cursor + Width;
            end;
         end loop;
         return True;
      end Valid_XML_UTF8;

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Notification with
              "bucket-notification document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;

      procedure Add_Element (Name : String; Depth : Positive) is
      begin
         if Elements = Limits.Maximum_Elements then
            raise Malformed_Notification with
              "bucket-notification elements exceed caller limit";
         end if;
         Elements := Elements + 1;
         Actual_Depth := Positive'Max (Actual_Depth, Depth);
         Append_Bounded ("<" & Name & ">");
      end Add_Element;

      procedure End_Element (Name : String) is
      begin
         Append_Bounded ("</" & Name & ">");
      end End_Element;

      procedure Add_Text (Text : String) is
      begin
         if not Valid_XML_UTF8 (Text) then
            raise Malformed_Notification with
              "invalid bucket-notification XML text";
         elsif Text'Length > Limits.Maximum_Text_Bytes - Text_Bytes then
            raise Malformed_Notification with
              "bucket-notification text exceeds caller limit";
         end if;
         Text_Bytes := Text_Bytes + Text'Length;
         Append_Bounded (XML.Escape_Text (Text));
      end Add_Text;

      procedure Add_Scalar
        (Name : String; Text : String; Depth : Positive) is
      begin
         Add_Element (Name, Depth);
         Add_Text (Text);
         End_Element (Name);
      end Add_Scalar;

      procedure Add_Optional_String
        (Name : String; Item : Optional_String; Depth : Positive) is
      begin
         if Item.Is_Set then
            Add_Scalar (Name, US.To_String (Item.Value), Depth);
         elsif US.Length (Item.Value) /= 0 then
            raise Malformed_Notification with
              "absent notification string contains text";
         end if;
      end Add_Optional_String;

      procedure Add_Filter (Item : Notification_Filter) is
      begin
         if not Item.Is_Set then
            if Item.Key_Is_Set or else not Item.Rules.Is_Empty then
               raise Malformed_Notification with
                 "absent notification filter contains values";
            end if;
            return;
         end if;
         Add_Element ("Filter", 3);
         if Item.Key_Is_Set then
            Add_Element ("S3Key", 4);
            for Rule of Item.Rules loop
               Add_Element ("FilterRule", 5);
               if Rule.Name_Is_Set then
                  Add_Scalar ("Name", Filter_Name_Text (Rule.Name), 6);
               elsif Rule.Name /= Prefix_Filter then
                  raise Malformed_Notification with
                    "absent filter name contains a value";
               end if;
               Add_Optional_String ("Value", Rule.Value, 6);
               End_Element ("FilterRule");
            end loop;
            End_Element ("S3Key");
         elsif not Item.Rules.Is_Empty then
            raise Malformed_Notification with
              "absent S3Key contains filter rules";
         end if;
         End_Element ("Filter");
      end Add_Filter;

      procedure Add_Destination
        (Element_Name : String; Destination_Name : String;
         ID : Optional_String; Destination : US.Unbounded_String;
         Events : Event_Vectors.Vector; Filter : Notification_Filter) is
      begin
         if Events.Is_Empty then
            raise Malformed_Notification with
              "notification destination events are required";
         end if;
         Add_Element (Element_Name, 2);
         Add_Optional_String ("Id", ID, 3);
         Add_Scalar (Destination_Name, US.To_String (Destination), 3);
         for Event of Events loop
            Add_Scalar ("Event", Event_Text (Event), 3);
         end loop;
         Add_Filter (Filter);
         End_Element (Element_Name);
      end Add_Destination;
   begin
      Append_Bounded (Prefix);
      for Topic of Value.Topics loop
         Add_Destination
           ("TopicConfiguration", "Topic", Topic.ID, Topic.Topic_ARN,
            Topic.Events, Topic.Filter);
      end loop;
      for Queue of Value.Queues loop
         Add_Destination
           ("QueueConfiguration", "Queue", Queue.ID, Queue.Queue_ARN,
            Queue.Events, Queue.Filter);
      end loop;
      for Lambda of Value.Lambdas loop
         Add_Destination
           ("CloudFunctionConfiguration", "CloudFunction", Lambda.ID,
            Lambda.Lambda_Function_ARN, Lambda.Events, Lambda.Filter);
      end loop;
      if Value.Event_Bridge_Is_Set then
         Add_Element ("EventBridgeConfiguration", 2);
         End_Element ("EventBridgeConfiguration");
      end if;
      if Actual_Depth > Limits.Maximum_Depth then
         raise Malformed_Notification with
           "bucket-notification depth exceeds caller limit";
      end if;
      Append_Bounded (Suffix);
      return US.To_String (Result);
   exception
      when XML.XML_Error =>
         raise Malformed_Notification with
           "invalid bucket-notification XML text";
   end Serialize;

end Flyology.Object_Storage.S3.Notifications;
