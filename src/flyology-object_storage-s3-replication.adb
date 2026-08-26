package body Flyology.Object_Storage.S3.Replication is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Rule_Container, Filter_Container,
      Filter_Tag_Container, And_Container, And_Tag_Container,
      Source_Container, SSE_Container, Replica_Modifications_Container,
      Existing_Object_Container, Destination_Container,
      Access_Control_Container, Encryption_Container,
      Replication_Time_Container, Replication_Time_Value_Container,
      Metrics_Container, Event_Threshold_Container,
      Delete_Marker_Container);
   type Scalar_Kind is
     (No_Scalar, Role_Scalar, Rule_ID_Scalar, Priority_Scalar,
      Rule_Prefix_Scalar, Rule_Status_Scalar, Filter_Prefix_Scalar,
      Tag_Key_Scalar, Tag_Value_Scalar, And_Prefix_Scalar,
      And_Tag_Key_Scalar, And_Tag_Value_Scalar, Nested_Status_Scalar,
      Destination_Bucket_Scalar, Destination_Account_Scalar,
      Destination_Storage_Class_Scalar, Owner_Scalar,
      Replica_KMS_Key_Scalar, Replication_Time_Status_Scalar,
      Replication_Time_Minutes_Scalar, Metrics_Status_Scalar,
      Event_Threshold_Minutes_Scalar);

   function Empty_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));
   function Empty_Integer return Optional_Integer_Text is
     ((Is_Set => False, Text => US.Null_Unbounded_String));
   function Empty_Tag return Replication_Tag is
     ((Key => US.Null_Unbounded_String, Value => US.Null_Unbounded_String));
   function Empty_Optional_Tag return Optional_Tag is
     ((Is_Set => False, Value => Empty_Tag));
   function Empty_Status return Optional_Status is
     ((Is_Set => False, Status_Is_Set => False, Status => Disabled));
   function Empty_And return Replication_And is
     ((Is_Set => False, Prefix => Empty_String, Tags => <>));
   function Empty_Filter return Replication_Filter is
     ((Is_Set => False, Prefix => Empty_String, Tag => Empty_Optional_Tag,
       And_Predicates => Empty_And));
   function Empty_Source return Source_Selection_Criteria is
     ((Is_Set => False, SSE_KMS_Encrypted_Objects => Empty_Status,
       Replica_Modifications => Empty_Status));
   function Empty_Time_Value return Replication_Time_Value is
     ((Is_Set => False, Minutes => Empty_Integer));
   function Empty_Time return Replication_Time is
     ((Is_Set => False, Status => Disabled, Time => Empty_Time_Value));
   function Empty_Metrics return Replication_Metrics is
     ((Is_Set => False, Status => Disabled,
       Event_Threshold => Empty_Time_Value));
   function Empty_Destination return Destination is
     ((Bucket => US.Null_Unbounded_String, Account => Empty_String,
       Storage_Class_Is_Set => False, Storage_Class => Standard,
       Access_Control => (Is_Set => False),
       Encryption => (Is_Set => False, Replica_KMS_Key_ID => Empty_String),
       Time => Empty_Time, Metrics => Empty_Metrics));
   function Empty_Rule return Replication_Rule is
     ((ID => Empty_String, Priority => Empty_Integer, Prefix => Empty_String,
       Filter => Empty_Filter, Status => Disabled,
       Source_Selection => Empty_Source,
       Existing_Object_Replication => Empty_Status,
       Target => Empty_Destination,
       Delete_Marker_Replication => Empty_Status));

   type Replication_Handler is new XML.Event_Handler with record
      Depth                : Natural := 0;
      Root_Seen            : Boolean := False;
      Role_Seen            : Boolean := False;
      Rule_Status_Seen     : Boolean := False;
      Destination_Seen     : Boolean := False;
      Destination_Bucket_Seen : Boolean := False;
      Nested_Status_Seen   : Boolean := False;
      Required_Time_Seen   : Boolean := False;
      Tag_Key_Seen         : Boolean := False;
      Tag_Value_Seen       : Boolean := False;
      Namespace            : Namespace_Style := Namespace_Not_Selected;
      Container            : Container_Kind := No_Container;
      Scalar               : Scalar_Kind := No_Scalar;
      Text_Value           : US.Unbounded_String;
      Current_Tag          : Replication_Tag := Empty_Tag;
      Current_Rule         : Replication_Rule := Empty_Rule;
      Value                : Replication_Configuration :=
        (Role => US.Null_Unbounded_String, Rules => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Replication_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item : in out Replication_Handler; Namespace_URI : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Replication_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Replication_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Replication with
              "text outside bucket-replication scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item : in out Replication_Handler; Namespace_URI : String;
      Attribute_Count : Natural)
   is
      --  Exact S3 REST/XML namespace fixed by the pinned service model.
      Style : constant Namespace_Style :=
        (if Namespace_URI'Length = 0 then Unqualified
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then S3_Qualified else Namespace_Not_Selected);
   begin
      if Attribute_Count /= 0 or else Style = Namespace_Not_Selected
        or else (Item.Namespace /= Namespace_Not_Selected
                 and then Item.Namespace /= Style)
      then
         raise Malformed_Replication with
           "bucket-replication namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Replication_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Begin_Tag
     (Item : in out Replication_Handler; Kind : Container_Kind) is
   begin
      Item.Container := Kind;
      Item.Current_Tag := Empty_Tag;
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
   end Begin_Tag;

   overriding procedure Start_Element
     (Item : in out Replication_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Replication with "bucket-replication depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "ReplicationConfiguration"
            then
               raise Malformed_Replication with
                 "invalid ReplicationConfiguration root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name = "Role" and then not Item.Role_Seen then
               Item.Role_Seen := True;
               Begin_Scalar (Item, Role_Scalar);
            elsif Local_Name = "Rule" then
               Item.Container := Rule_Container;
               Item.Current_Rule := Empty_Rule;
               Item.Rule_Status_Seen := False;
               Item.Destination_Seen := False;
               Item.Destination_Bucket_Seen := False;
            else
               raise Malformed_Replication with
                 "unknown or duplicate replication root member";
            end if;
         when 3 =>
            if Item.Container /= Rule_Container then
               raise Malformed_Replication with "invalid replication rule";
            elsif Local_Name = "ID" and then not Item.Current_Rule.ID.Is_Set
            then
               Begin_Scalar (Item, Rule_ID_Scalar);
            elsif Local_Name = "Priority"
              and then not Item.Current_Rule.Priority.Is_Set
            then
               Begin_Scalar (Item, Priority_Scalar);
            elsif Local_Name = "Prefix"
              and then not Item.Current_Rule.Prefix.Is_Set
            then
               Begin_Scalar (Item, Rule_Prefix_Scalar);
            elsif Local_Name = "Filter"
              and then not Item.Current_Rule.Filter.Is_Set
            then
               Item.Current_Rule.Filter.Is_Set := True;
               Item.Container := Filter_Container;
            elsif Local_Name = "Status" and then not Item.Rule_Status_Seen
            then
               Item.Rule_Status_Seen := True;
               Begin_Scalar (Item, Rule_Status_Scalar);
            elsif Local_Name = "SourceSelectionCriteria"
              and then not Item.Current_Rule.Source_Selection.Is_Set
            then
               Item.Current_Rule.Source_Selection.Is_Set := True;
               Item.Container := Source_Container;
            elsif Local_Name = "ExistingObjectReplication"
              and then not Item.Current_Rule.Existing_Object_Replication.Is_Set
            then
               Item.Current_Rule.Existing_Object_Replication.Is_Set := True;
               Item.Nested_Status_Seen := False;
               Item.Container := Existing_Object_Container;
            elsif Local_Name = "Destination" and then not Item.Destination_Seen
            then
               Item.Destination_Seen := True;
               Item.Container := Destination_Container;
            elsif Local_Name = "DeleteMarkerReplication"
              and then not Item.Current_Rule.Delete_Marker_Replication.Is_Set
            then
               Item.Current_Rule.Delete_Marker_Replication.Is_Set := True;
               Item.Nested_Status_Seen := False;
               Item.Container := Delete_Marker_Container;
            else
               raise Malformed_Replication with
                 "unknown or duplicate replication rule member";
            end if;
         when 4 =>
            case Item.Container is
               when Filter_Container =>
                  if Local_Name = "Prefix"
                    and then not Item.Current_Rule.Filter.Prefix.Is_Set
                  then
                     Begin_Scalar (Item, Filter_Prefix_Scalar);
                  elsif Local_Name = "Tag"
                    and then not Item.Current_Rule.Filter.Tag.Is_Set
                  then
                     Item.Current_Rule.Filter.Tag.Is_Set := True;
                     Begin_Tag (Item, Filter_Tag_Container);
                  elsif Local_Name = "And"
                    and then not Item.Current_Rule.Filter.And_Predicates.Is_Set
                  then
                     Item.Current_Rule.Filter.And_Predicates.Is_Set := True;
                     Item.Container := And_Container;
                  else
                     raise Malformed_Replication with
                       "unknown or duplicate replication filter member";
                  end if;
               when Source_Container =>
                  if Local_Name = "SseKmsEncryptedObjects"
                    and then not Item.Current_Rule.Source_Selection.
                      SSE_KMS_Encrypted_Objects.Is_Set
                  then
                     Item.Current_Rule.Source_Selection.
                       SSE_KMS_Encrypted_Objects.Is_Set := True;
                     Item.Nested_Status_Seen := False;
                     Item.Container := SSE_Container;
                  elsif Local_Name = "ReplicaModifications"
                    and then not Item.Current_Rule.Source_Selection.
                      Replica_Modifications.Is_Set
                  then
                     Item.Current_Rule.Source_Selection.
                       Replica_Modifications.Is_Set := True;
                     Item.Nested_Status_Seen := False;
                     Item.Container := Replica_Modifications_Container;
                  else
                     raise Malformed_Replication with
                       "unknown source-selection member";
                  end if;
               when Existing_Object_Container | Delete_Marker_Container =>
                  if Local_Name /= "Status" or else Item.Nested_Status_Seen
                  then
                     raise Malformed_Replication with
                       "invalid replication status structure";
                  end if;
                  Item.Nested_Status_Seen := True;
                  Begin_Scalar (Item, Nested_Status_Scalar);
               when Destination_Container =>
                  if Local_Name = "Bucket"
                    and then not Item.Destination_Bucket_Seen
                  then
                     Item.Destination_Bucket_Seen := True;
                     Begin_Scalar (Item, Destination_Bucket_Scalar);
                  elsif Local_Name = "Account"
                    and then not Item.Current_Rule.Target.Account.Is_Set
                  then
                     Begin_Scalar (Item, Destination_Account_Scalar);
                  elsif Local_Name = "StorageClass"
                    and then not Item.Current_Rule.Target.
                      Storage_Class_Is_Set
                  then
                     Begin_Scalar
                       (Item, Destination_Storage_Class_Scalar);
                  elsif Local_Name = "AccessControlTranslation"
                    and then not Item.Current_Rule.Target.Access_Control.Is_Set
                  then
                     Item.Current_Rule.Target.Access_Control.Is_Set := True;
                     Item.Nested_Status_Seen := False;
                     Item.Container := Access_Control_Container;
                  elsif Local_Name = "EncryptionConfiguration"
                    and then not Item.Current_Rule.Target.Encryption.Is_Set
                  then
                     Item.Current_Rule.Target.Encryption.Is_Set := True;
                     Item.Container := Encryption_Container;
                  elsif Local_Name = "ReplicationTime"
                    and then not Item.Current_Rule.Target.Time.Is_Set
                  then
                     Item.Current_Rule.Target.Time.Is_Set := True;
                     Item.Nested_Status_Seen := False;
                     Item.Required_Time_Seen := False;
                     Item.Container := Replication_Time_Container;
                  elsif Local_Name = "Metrics"
                    and then not Item.Current_Rule.Target.Metrics.Is_Set
                  then
                     Item.Current_Rule.Target.Metrics.Is_Set := True;
                     Item.Nested_Status_Seen := False;
                     Item.Container := Metrics_Container;
                  else
                     raise Malformed_Replication with
                       "unknown or duplicate replication destination member";
                  end if;
               when others =>
                  raise Malformed_Replication with
                    "invalid replication member depth";
            end case;
         when 5 =>
            case Item.Container is
               when Filter_Tag_Container | And_Tag_Container =>
                  if Local_Name = "Key" and then not Item.Tag_Key_Seen then
                     Item.Tag_Key_Seen := True;
                     Begin_Scalar
                       (Item, (if Item.Container = Filter_Tag_Container
                              then Tag_Key_Scalar else And_Tag_Key_Scalar));
                  elsif Local_Name = "Value" and then not Item.Tag_Value_Seen
                  then
                     Item.Tag_Value_Seen := True;
                     Begin_Scalar
                       (Item,
                        (if Item.Container = Filter_Tag_Container
                         then Tag_Value_Scalar else And_Tag_Value_Scalar));
                  else
                     raise Malformed_Replication with
                       "unknown or duplicate replication tag member";
                  end if;
               when And_Container =>
                  if Local_Name = "Prefix" and then not Item.Current_Rule.
                    Filter.And_Predicates.Prefix.Is_Set
                  then
                     Begin_Scalar (Item, And_Prefix_Scalar);
                  elsif Local_Name = "Tag" then
                     Begin_Tag (Item, And_Tag_Container);
                  else
                     raise Malformed_Replication with
                       "unknown replication And member";
                  end if;
               when SSE_Container | Replica_Modifications_Container =>
                  if Local_Name /= "Status" or else Item.Nested_Status_Seen
                  then
                     raise Malformed_Replication with
                       "invalid source-selection status";
                  end if;
                  Item.Nested_Status_Seen := True;
                  Begin_Scalar (Item, Nested_Status_Scalar);
               when Access_Control_Container =>
                  if Local_Name /= "Owner" or else Item.Nested_Status_Seen
                  then
                     raise Malformed_Replication with
                       "invalid access-control translation";
                  end if;
                  Item.Nested_Status_Seen := True;
                  Begin_Scalar (Item, Owner_Scalar);
               when Encryption_Container =>
                  if Local_Name /= "ReplicaKmsKeyID" or else
                    Item.Current_Rule.Target.Encryption.
                      Replica_KMS_Key_ID.Is_Set
                  then
                     raise Malformed_Replication with
                       "invalid encryption configuration";
                  end if;
                  Begin_Scalar (Item, Replica_KMS_Key_Scalar);
               when Replication_Time_Container =>
                  if Local_Name = "Status" and then not Item.Nested_Status_Seen
                  then
                     Item.Nested_Status_Seen := True;
                     Begin_Scalar (Item, Replication_Time_Status_Scalar);
                  elsif Local_Name = "Time"
                    and then not Item.Required_Time_Seen
                  then
                     Item.Required_Time_Seen := True;
                     Item.Current_Rule.Target.Time.Time.Is_Set := True;
                     Item.Container := Replication_Time_Value_Container;
                  else
                     raise Malformed_Replication with
                       "invalid replication-time member";
                  end if;
               when Metrics_Container =>
                  if Local_Name = "Status" and then not Item.Nested_Status_Seen
                  then
                     Item.Nested_Status_Seen := True;
                     Begin_Scalar (Item, Metrics_Status_Scalar);
                  elsif Local_Name = "EventThreshold" and then not
                    Item.Current_Rule.Target.Metrics.Event_Threshold.Is_Set
                  then
                     Item.Current_Rule.Target.Metrics.Event_Threshold.Is_Set :=
                       True;
                     Item.Container := Event_Threshold_Container;
                  else
                     raise Malformed_Replication with
                       "invalid metrics member";
                  end if;
               when others =>
                  raise Malformed_Replication with
                    "invalid nested replication member";
            end case;
         when 6 =>
            if Item.Container = And_Tag_Container then
               if Local_Name = "Key" and then not Item.Tag_Key_Seen then
                  Item.Tag_Key_Seen := True;
                  Begin_Scalar (Item, And_Tag_Key_Scalar);
               elsif Local_Name = "Value" and then not Item.Tag_Value_Seen then
                  Item.Tag_Value_Seen := True;
                  Begin_Scalar (Item, And_Tag_Value_Scalar);
               else
                  raise Malformed_Replication with
                    "invalid And tag member";
               end if;
            elsif Item.Container = Replication_Time_Value_Container
              and then Local_Name = "Minutes"
              and then not Item.Current_Rule.Target.Time.Time.Minutes.Is_Set
            then
               Begin_Scalar (Item, Replication_Time_Minutes_Scalar);
            elsif Item.Container = Event_Threshold_Container
              and then Local_Name = "Minutes" and then not Item.Current_Rule.
                Target.Metrics.Event_Threshold.Minutes.Is_Set
            then
               Begin_Scalar (Item, Event_Threshold_Minutes_Scalar);
            else
               raise Malformed_Replication with
                 "invalid deep replication member";
            end if;
         when others =>
            raise Malformed_Replication with
              "nested bucket-replication member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Replication_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 6 then
         Require_Whitespace (Value);
      else
         raise Malformed_Replication with
           "bucket-replication text outside modeled member";
      end if;
   end Text;

   function Parse_Status (Value : String) return Status_Kind is
     (if Value = "Enabled" then Enabled
      elsif Value = "Disabled" then Disabled
      else raise Malformed_Replication with "invalid replication status");

   function Parse_Storage_Class (Value : String) return Storage_Class_Kind is
   begin
      if Value = "STANDARD" then
         return Standard;
      elsif Value = "REDUCED_REDUNDANCY" then
         return Reduced_Redundancy;
      elsif Value = "STANDARD_IA" then
         return Standard_IA;
      elsif Value = "ONEZONE_IA" then
         return One_Zone_IA;
      elsif Value = "INTELLIGENT_TIERING" then
         return Intelligent_Tiering;
      elsif Value = "GLACIER" then
         return Glacier;
      elsif Value = "DEEP_ARCHIVE" then
         return Deep_Archive;
      elsif Value = "OUTPOSTS" then
         return Outposts;
      elsif Value = "GLACIER_IR" then
         return Glacier_Instant_Retrieval;
      elsif Value = "SNOW" then
         return Snow;
      elsif Value = "EXPRESS_ONEZONE" then
         return Express_One_Zone;
      elsif Value = "FSX_OPENZFS" then
         return FSX_OpenZFS;
      elsif Value = "FSX_ONTAP" then
         return FSX_ONTAP;
      elsif Value = "AWS_BACKUP_WARM" then
         return AWS_Backup_Warm;
      elsif Value = "AWS_BACKUP_LOW_COST_WARM" then
         return AWS_Backup_Low_Cost_Warm;
      end if;
      raise Malformed_Replication with "invalid replication storage class";
   end Parse_Storage_Class;

   function Valid_Integer (Value : String) return Boolean is
      First_Digit : Integer := Value'First;
   begin
      if Value'Length = 0 then
         return False;
      end if;
      if Value (Value'First) = '-' then
         if Value'Length = 1 then
            return False;
         end if;
         First_Digit := First_Digit + 1;
      elsif Value (Value'First) = '+' then
         return False;
      end if;
      for Index in First_Digit .. Value'Last loop
         if Value (Index) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Integer;

   procedure Close_Scalar
     (Item : in out Replication_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
      Status : Status_Kind;
   begin
      case Item.Scalar is
         when Role_Scalar =>
            if Local_Name /= "Role" then
               raise Malformed_Replication;
            end if;
            Item.Value.Role := Item.Text_Value;
         when Rule_ID_Scalar =>
            Item.Current_Rule.ID := (True, Item.Text_Value);
         when Priority_Scalar | Rule_Prefix_Scalar | Filter_Prefix_Scalar |
              And_Prefix_Scalar | Destination_Account_Scalar |
              Replica_KMS_Key_Scalar =>
            if Item.Scalar = Priority_Scalar then
               if not Valid_Integer (Value) then
                  raise Malformed_Replication with "invalid priority";
               end if;
               Item.Current_Rule.Priority := (True, Item.Text_Value);
            elsif Item.Scalar = Rule_Prefix_Scalar then
               Item.Current_Rule.Prefix := (True, Item.Text_Value);
            elsif Item.Scalar = Filter_Prefix_Scalar then
               Item.Current_Rule.Filter.Prefix := (True, Item.Text_Value);
            elsif Item.Scalar = And_Prefix_Scalar then
               Item.Current_Rule.Filter.And_Predicates.Prefix :=
                 (True, Item.Text_Value);
            elsif Item.Scalar = Destination_Account_Scalar then
               Item.Current_Rule.Target.Account := (True, Item.Text_Value);
            else
               Item.Current_Rule.Target.Encryption.Replica_KMS_Key_ID :=
                 (True, Item.Text_Value);
            end if;
         when Rule_Status_Scalar =>
            Item.Current_Rule.Status := Parse_Status (Value);
         when Tag_Key_Scalar | And_Tag_Key_Scalar =>
            Item.Current_Tag.Key := Item.Text_Value;
         when Tag_Value_Scalar | And_Tag_Value_Scalar =>
            Item.Current_Tag.Value := Item.Text_Value;
         when Nested_Status_Scalar =>
            Status := Parse_Status (Value);
            case Item.Container is
               when SSE_Container =>
                  Item.Current_Rule.Source_Selection.
                    SSE_KMS_Encrypted_Objects.Status_Is_Set := True;
                  Item.Current_Rule.Source_Selection.
                    SSE_KMS_Encrypted_Objects.Status := Status;
               when Replica_Modifications_Container =>
                  Item.Current_Rule.Source_Selection.Replica_Modifications.
                    Status_Is_Set := True;
                  Item.Current_Rule.Source_Selection.Replica_Modifications.
                    Status := Status;
               when Existing_Object_Container =>
                  Item.Current_Rule.Existing_Object_Replication.
                    Status_Is_Set := True;
                  Item.Current_Rule.Existing_Object_Replication.Status :=
                    Status;
               when Delete_Marker_Container =>
                  Item.Current_Rule.Delete_Marker_Replication.Status_Is_Set :=
                    True;
                  Item.Current_Rule.Delete_Marker_Replication.Status := Status;
               when others => raise Malformed_Replication;
            end case;
         when Destination_Bucket_Scalar =>
            Item.Current_Rule.Target.Bucket := Item.Text_Value;
         when Destination_Storage_Class_Scalar =>
            Item.Current_Rule.Target.Storage_Class_Is_Set := True;
            Item.Current_Rule.Target.Storage_Class :=
              Parse_Storage_Class (Value);
         when Owner_Scalar =>
            if Value /= "Destination" then
               raise Malformed_Replication with "invalid owner override";
            end if;
         when Replication_Time_Status_Scalar =>
            Item.Current_Rule.Target.Time.Status := Parse_Status (Value);
         when Metrics_Status_Scalar =>
            Item.Current_Rule.Target.Metrics.Status := Parse_Status (Value);
         when Replication_Time_Minutes_Scalar |
              Event_Threshold_Minutes_Scalar =>
            if not Valid_Integer (Value) then
               raise Malformed_Replication with "invalid replication minutes";
            elsif Item.Scalar = Replication_Time_Minutes_Scalar then
               Item.Current_Rule.Target.Time.Time.Minutes :=
                 (True, Item.Text_Value);
            else
               Item.Current_Rule.Target.Metrics.Event_Threshold.Minutes :=
                 (True, Item.Text_Value);
            end if;
         when No_Scalar => raise Malformed_Replication;
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Close_Scalar;

   procedure Require_Tag (Item : Replication_Handler) is
   begin
      if not Item.Tag_Key_Seen or else not Item.Tag_Value_Seen then
         raise Malformed_Replication with "incomplete replication tag";
      end if;
   end Require_Tag;

   overriding procedure End_Element
     (Item : in out Replication_Handler; Local_Name : String) is
   begin
      if Item.Scalar /= No_Scalar then
         Close_Scalar (Item, Local_Name);
         Item.Depth := Item.Depth - 1;
         return;
      end if;
      case Item.Depth is
         when 5 =>
            if Item.Container = And_Tag_Container
              and then Local_Name = "Tag"
            then
               Require_Tag (Item);
               Item.Current_Rule.Filter.And_Predicates.Tags.Append
                 (Item.Current_Tag);
               Item.Container := And_Container;
            elsif Item.Container = Replication_Time_Value_Container
              and then Local_Name = "Time"
            then
               Item.Container := Replication_Time_Container;
            elsif Item.Container = Event_Threshold_Container
              and then Local_Name = "EventThreshold"
            then
               Item.Container := Metrics_Container;
            else
               raise Malformed_Replication;
            end if;
         when 4 =>
            case Item.Container is
               when Filter_Tag_Container =>
                  if Local_Name /= "Tag" then
                     raise Malformed_Replication;
                  end if;
                  Require_Tag (Item);
                  Item.Current_Rule.Filter.Tag.Value := Item.Current_Tag;
                  Item.Container := Filter_Container;
               when And_Container =>
                  if Local_Name /= "And" then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Filter_Container;
               when SSE_Container | Replica_Modifications_Container =>
                  if not Item.Nested_Status_Seen then
                     raise Malformed_Replication with "missing status";
                  end if;
                  Item.Container := Source_Container;
               when Access_Control_Container =>
                  if Local_Name /= "AccessControlTranslation"
                    or else not Item.Nested_Status_Seen
                  then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Destination_Container;
               when Encryption_Container =>
                  if Local_Name /= "EncryptionConfiguration" then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Destination_Container;
               when Replication_Time_Container =>
                  if Local_Name /= "ReplicationTime"
                    or else not Item.Nested_Status_Seen
                    or else not Item.Required_Time_Seen
                  then
                     raise Malformed_Replication with
                       "incomplete replication time";
                  end if;
                  Item.Container := Destination_Container;
               when Metrics_Container =>
                  if Local_Name /= "Metrics" or else
                    not Item.Nested_Status_Seen
                  then
                     raise Malformed_Replication with
                       "incomplete replication metrics";
                  end if;
                  Item.Container := Destination_Container;
               when others =>
                  raise Malformed_Replication;
            end case;
         when 3 =>
            case Item.Container is
               when Filter_Container =>
                  if Local_Name /= "Filter" then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Rule_Container;
               when Source_Container =>
                  if Local_Name /= "SourceSelectionCriteria" then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Rule_Container;
               when Existing_Object_Container =>
                  if Local_Name /= "ExistingObjectReplication" or else
                    not Item.Nested_Status_Seen
                  then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Rule_Container;
               when Delete_Marker_Container =>
                  if Local_Name /= "DeleteMarkerReplication" then
                     raise Malformed_Replication;
                  end if;
                  Item.Container := Rule_Container;
               when Destination_Container =>
                  if Local_Name /= "Destination" or else
                    not Item.Destination_Bucket_Seen
                  then
                     raise Malformed_Replication with
                       "incomplete replication destination";
                  end if;
                  Item.Container := Rule_Container;
               when others =>
                  raise Malformed_Replication;
            end case;
         when 2 =>
            if Local_Name /= "Rule" or else Item.Container /= Rule_Container
              or else not Item.Rule_Status_Seen
              or else not Item.Destination_Seen
            then
               raise Malformed_Replication with
                 "incomplete replication rule";
            end if;
            Item.Value.Rules.Append (Item.Current_Rule);
            Item.Container := No_Container;
         when 1 =>
            if Local_Name /= "ReplicationConfiguration"
              or else not Item.Role_Seen or else Item.Value.Rules.Is_Empty
            then
               raise Malformed_Replication with
                 "incomplete ReplicationConfiguration";
            end if;
         when others =>
            raise Malformed_Replication;
      end case;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Replication_Configuration
   is
      Handler : aliased Replication_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Replication with
           "incomplete bucket-replication document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Replication with "malformed bucket-replication XML";
   end Parse;

end Flyology.Object_Storage.S3.Replication;
