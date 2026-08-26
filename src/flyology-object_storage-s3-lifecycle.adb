package body Flyology.Object_Storage.S3.Lifecycle is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Expiration_Container, Filter_Container,
      Filter_Tag_Container, And_Container, And_Tag_Container,
      Transition_Container, Noncurrent_Transition_Container,
      Noncurrent_Expiration_Container, Abort_Container);
   type Scalar_Kind is
     (No_Scalar, Rule_ID_Scalar, Rule_Prefix_Scalar, Rule_Status_Scalar,
      Expiration_Date_Scalar, Expiration_Days_Scalar,
      Expiration_Delete_Marker_Scalar, Filter_Prefix_Scalar,
      Filter_Greater_Scalar, Filter_Less_Scalar, Tag_Key_Scalar,
      Tag_Value_Scalar, And_Prefix_Scalar, And_Greater_Scalar,
      And_Less_Scalar, Transition_Date_Scalar, Transition_Days_Scalar,
      Transition_Class_Scalar, Noncurrent_Days_Scalar,
      Noncurrent_Class_Scalar, Noncurrent_Newer_Scalar,
      Noncurrent_Expiration_Days_Scalar,
      Noncurrent_Expiration_Newer_Scalar, Abort_Days_Scalar);

   type Lifecycle_Handler is new XML.Event_Handler with record
      Depth          : Natural := 0;
      Root_Seen      : Boolean := False;
      Status_Seen    : Boolean := False;
      Namespace      : Namespace_Style := Namespace_Not_Selected;
      Container      : Container_Kind := No_Container;
      Scalar         : Scalar_Kind := No_Scalar;
      Text_Value     : US.Unbounded_String;
      Current_Rule   : Lifecycle_Rule := (others => <>);
      Current_Transition : Lifecycle_Transition := (others => <>);
      Current_Noncurrent : Noncurrent_Transition := (others => <>);
      Current_Tag    : Lifecycle_Tag;
      Tag_Key_Seen   : Boolean := False;
      Tag_Value_Seen : Boolean := False;
      Value          : Lifecycle_Configuration :=
        (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Lifecycle_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Lifecycle_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Lifecycle_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Lifecycle_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Lifecycle with
              "text outside bucket-lifecycle scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Lifecycle_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  Exact pinned S3 REST/XML namespace. Changing this external value
      --  changes lifecycle provider compatibility.
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
         raise Malformed_Lifecycle with
           "bucket-lifecycle namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Lifecycle_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Begin_Tag
     (Item : in out Lifecycle_Handler; Kind : Container_Kind) is
   begin
      Item.Container := Kind;
      Item.Current_Tag :=
        (Key => US.Null_Unbounded_String,
         Value => US.Null_Unbounded_String);
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
   end Begin_Tag;

   overriding procedure Start_Element
     (Item : in out Lifecycle_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Lifecycle with "bucket-lifecycle depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "LifecycleConfiguration"
            then
               raise Malformed_Lifecycle with
                 "invalid LifecycleConfiguration root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name /= "Rule" then
               raise Malformed_Lifecycle with
                 "unknown bucket-lifecycle root member";
            end if;
            Item.Status_Seen := False;
            Item.Container := No_Container;
            Item.Scalar := No_Scalar;
            Item.Current_Rule := (others => <>);
         when 3 =>
            if Item.Container /= No_Container or else Item.Scalar /= No_Scalar
            then
               raise Malformed_Lifecycle with
                 "incomplete bucket-lifecycle rule member";
            elsif Local_Name = "Expiration"
              and then not Item.Current_Rule.Expiration.Is_Set
            then
               Item.Current_Rule.Expiration.Is_Set := True;
               Item.Container := Expiration_Container;
            elsif Local_Name = "ID" and then not Item.Current_Rule.ID.Is_Set
            then
               Begin_Scalar (Item, Rule_ID_Scalar);
            elsif Local_Name = "Prefix"
              and then not Item.Current_Rule.Prefix.Is_Set
            then
               Begin_Scalar (Item, Rule_Prefix_Scalar);
            elsif Local_Name = "Filter"
              and then not Item.Current_Rule.Filter.Is_Set
            then
               Item.Current_Rule.Filter.Is_Set := True;
               Item.Container := Filter_Container;
            elsif Local_Name = "Status" and then not Item.Status_Seen then
               Item.Status_Seen := True;
               Begin_Scalar (Item, Rule_Status_Scalar);
            elsif Local_Name = "Transition" then
               Item.Current_Transition := (others => <>);
               Item.Container := Transition_Container;
            elsif Local_Name = "NoncurrentVersionTransition" then
               Item.Current_Noncurrent := (others => <>);
               Item.Container := Noncurrent_Transition_Container;
            elsif Local_Name = "NoncurrentVersionExpiration"
              and then not Item.Current_Rule.Noncurrent_Expiration.Is_Set
            then
               Item.Current_Rule.Noncurrent_Expiration.Is_Set := True;
               Item.Container := Noncurrent_Expiration_Container;
            elsif Local_Name = "AbortIncompleteMultipartUpload"
              and then not Item.Current_Rule.Abort_Incomplete.Is_Set
            then
               Item.Current_Rule.Abort_Incomplete.Is_Set := True;
               Item.Container := Abort_Container;
            else
               raise Malformed_Lifecycle with
                 "unknown or duplicate bucket-lifecycle rule member";
            end if;
         when 4 =>
            case Item.Container is
               when Expiration_Container =>
                  if Local_Name = "Date"
                    and then not Item.Current_Rule.Expiration.Date.Is_Set
                  then
                     Begin_Scalar (Item, Expiration_Date_Scalar);
                  elsif Local_Name = "Days"
                    and then not Item.Current_Rule.Expiration.Days.Is_Set
                  then
                     Begin_Scalar (Item, Expiration_Days_Scalar);
                  elsif Local_Name = "ExpiredObjectDeleteMarker"
                    and then not Item.Current_Rule.Expiration.
                      Expired_Object_Delete_Marker.Is_Set
                  then
                     Begin_Scalar (Item, Expiration_Delete_Marker_Scalar);
                  else
                     raise Malformed_Lifecycle with
                       "unknown or duplicate lifecycle expiration member";
                  end if;
               when Filter_Container =>
                  if Local_Name = "Prefix"
                    and then not Item.Current_Rule.Filter.Prefix.Is_Set
                  then
                     Begin_Scalar (Item, Filter_Prefix_Scalar);
                  elsif Local_Name = "Tag"
                    and then not Item.Current_Rule.Filter.Tag.Is_Set
                  then
                     Begin_Tag (Item, Filter_Tag_Container);
                  elsif Local_Name = "ObjectSizeGreaterThan"
                    and then not Item.Current_Rule.Filter.
                      Object_Size_Greater_Than.Is_Set
                  then
                     Begin_Scalar (Item, Filter_Greater_Scalar);
                  elsif Local_Name = "ObjectSizeLessThan"
                    and then not Item.Current_Rule.Filter.
                      Object_Size_Less_Than.Is_Set
                  then
                     Begin_Scalar (Item, Filter_Less_Scalar);
                  elsif Local_Name = "And"
                    and then not Item.Current_Rule.Filter.And_Predicates.Is_Set
                  then
                     Item.Current_Rule.Filter.And_Predicates.Is_Set := True;
                     Item.Container := And_Container;
                  else
                     raise Malformed_Lifecycle with
                       "unknown or duplicate lifecycle filter member";
                  end if;
               when Transition_Container =>
                  if Local_Name = "Date"
                    and then not Item.Current_Transition.Date.Is_Set
                  then
                     Begin_Scalar (Item, Transition_Date_Scalar);
                  elsif Local_Name = "Days"
                    and then not Item.Current_Transition.Days.Is_Set
                  then
                     Begin_Scalar (Item, Transition_Days_Scalar);
                  elsif Local_Name = "StorageClass"
                    and then not Item.Current_Transition.Storage_Class_Is_Set
                  then
                     Item.Current_Transition.Storage_Class_Is_Set := True;
                     Begin_Scalar (Item, Transition_Class_Scalar);
                  else
                     raise Malformed_Lifecycle with
                       "unknown or duplicate lifecycle transition member";
                  end if;
               when Noncurrent_Transition_Container =>
                  if Local_Name = "NoncurrentDays"
                    and then not Item.Current_Noncurrent.Noncurrent_Days.Is_Set
                  then
                     Begin_Scalar (Item, Noncurrent_Days_Scalar);
                  elsif Local_Name = "StorageClass"
                    and then not Item.Current_Noncurrent.Storage_Class_Is_Set
                  then
                     Item.Current_Noncurrent.Storage_Class_Is_Set := True;
                     Begin_Scalar (Item, Noncurrent_Class_Scalar);
                  elsif Local_Name = "NewerNoncurrentVersions"
                    and then not Item.Current_Noncurrent.
                      Newer_Noncurrent_Versions.Is_Set
                  then
                     Begin_Scalar (Item, Noncurrent_Newer_Scalar);
                  else
                     raise Malformed_Lifecycle with
                       "unknown or duplicate noncurrent transition member";
                  end if;
               when Noncurrent_Expiration_Container =>
                  if Local_Name = "NoncurrentDays"
                    and then not Item.Current_Rule.Noncurrent_Expiration.
                      Noncurrent_Days.Is_Set
                  then
                     Begin_Scalar
                       (Item, Noncurrent_Expiration_Days_Scalar);
                  elsif Local_Name = "NewerNoncurrentVersions"
                    and then not Item.Current_Rule.Noncurrent_Expiration.
                      Newer_Noncurrent_Versions.Is_Set
                  then
                     Begin_Scalar
                       (Item, Noncurrent_Expiration_Newer_Scalar);
                  else
                     raise Malformed_Lifecycle with
                       "unknown or duplicate noncurrent expiration member";
                  end if;
               when Abort_Container =>
                  if Local_Name = "DaysAfterInitiation"
                    and then not Item.Current_Rule.Abort_Incomplete.
                      Days_After_Initiation.Is_Set
                  then
                     Begin_Scalar (Item, Abort_Days_Scalar);
                  else
                     raise Malformed_Lifecycle with
                       "unknown or duplicate multipart abort member";
                  end if;
               when others =>
                  raise Malformed_Lifecycle with
                    "nested bucket-lifecycle member without container";
            end case;
         when 5 =>
            if Item.Container = Filter_Tag_Container then
               if Local_Name = "Key" and then not Item.Tag_Key_Seen then
                  Item.Tag_Key_Seen := True;
                  Begin_Scalar (Item, Tag_Key_Scalar);
               elsif Local_Name = "Value"
                 and then not Item.Tag_Value_Seen
               then
                  Item.Tag_Value_Seen := True;
                  Begin_Scalar (Item, Tag_Value_Scalar);
               else
                  raise Malformed_Lifecycle with
                    "unknown or duplicate lifecycle tag member";
               end if;
            elsif Item.Container = And_Container then
               if Local_Name = "Prefix"
                 and then not Item.Current_Rule.Filter.And_Predicates.
                   Prefix.Is_Set
               then
                  Begin_Scalar (Item, And_Prefix_Scalar);
               elsif Local_Name = "Tag" then
                  Begin_Tag (Item, And_Tag_Container);
               elsif Local_Name = "ObjectSizeGreaterThan"
                 and then not Item.Current_Rule.Filter.And_Predicates.
                   Object_Size_Greater_Than.Is_Set
               then
                  Begin_Scalar (Item, And_Greater_Scalar);
               elsif Local_Name = "ObjectSizeLessThan"
                 and then not Item.Current_Rule.Filter.And_Predicates.
                   Object_Size_Less_Than.Is_Set
               then
                  Begin_Scalar (Item, And_Less_Scalar);
               else
                  raise Malformed_Lifecycle with
                    "unknown or duplicate lifecycle And member";
               end if;
            else
               raise Malformed_Lifecycle with
                 "invalid lifecycle nesting at depth five";
            end if;
         when 6 =>
            if Item.Container /= And_Tag_Container then
               raise Malformed_Lifecycle with
                 "invalid lifecycle nesting at depth six";
            elsif Local_Name = "Key" and then not Item.Tag_Key_Seen then
               Item.Tag_Key_Seen := True;
               Begin_Scalar (Item, Tag_Key_Scalar);
            elsif Local_Name = "Value" and then not Item.Tag_Value_Seen then
               Item.Tag_Value_Seen := True;
               Begin_Scalar (Item, Tag_Value_Scalar);
            else
               raise Malformed_Lifecycle with
                 "unknown or duplicate lifecycle And tag member";
            end if;
         when others =>
            raise Malformed_Lifecycle with
              "bucket-lifecycle document is nested too deeply";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Lifecycle_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 5 then
         Require_Whitespace (Value);
      else
         raise Malformed_Lifecycle with
           "bucket-lifecycle text outside modeled member";
      end if;
   end Text;

   function Valid_Integer_Text (Value : String) return Boolean is
      Index : Integer := Value'First;
   begin
      if Value'Length = 0 then
         return False;
      end if;
      if Value (Index) in '+' | '-' then
         Index := Index + 1;
      end if;
      if Index > Value'Last then
         return False;
      end if;
      while Index <= Value'Last loop
         if Value (Index) not in '0' .. '9' then
            return False;
         end if;
         Index := Index + 1;
      end loop;
      return True;
   end Valid_Integer_Text;

   --  Pinned AWS ISO-8601 timestamp grammar shared by S3 modeled dates.
   function Valid_ISO_8601_Timestamp (Value : String) return Boolean is
      Text : constant String (1 .. Value'Length) := Value;

      function Decimal (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               return Natural'Last;
            end if;
            Result := Result * 10 +
              Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Decimal;

      Year        : Natural;
      Month       : Natural;
      Day         : Natural;
      Hour        : Natural;
      Minute      : Natural;
      Second      : Natural;
      Zone        : Positive := 20;
      Maximum_Day : Natural;
   begin
      if Text'Length not in 20 .. 35
        or else Text (5) /= '-'
        or else Text (8) /= '-'
        or else Text (11) /= 'T'
        or else Text (14) /= ':'
        or else Text (17) /= ':'
      then
         return False;
      end if;
      Year := Decimal (1, 4);
      Month := Decimal (6, 7);
      Day := Decimal (9, 10);
      Hour := Decimal (12, 13);
      Minute := Decimal (15, 16);
      Second := Decimal (18, 19);
      if Year not in 1 .. 9_999
        or else Month not in 1 .. 12
        or else Hour > 23
        or else Minute > 59
        or else Second > 59
      then
         return False;
      end if;
      Maximum_Day :=
        (case Month is
            when 2 =>
              (if Year mod 400 = 0
                 or else (Year mod 4 = 0 and then Year mod 100 /= 0)
               then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
      if Day not in 1 .. Maximum_Day then
         return False;
      end if;
      if Text (Zone) = '.' then
         Zone := Zone + 1;
         declare
            First_Fraction : constant Positive := Zone;
         begin
            while Zone <= Text'Last and then Text (Zone) in '0' .. '9' loop
               Zone := Zone + 1;
            end loop;
            if Zone = First_Fraction or else Zone - First_Fraction > 9 then
               return False;
            end if;
         end;
      end if;
      if Zone = Text'Last and then Text (Zone) = 'Z' then
         return True;
      elsif Zone + 5 = Text'Last
        and then Text (Zone) in '+' | '-'
        and then Text (Zone + 3) = ':'
      then
         declare
            Offset_Hour : constant Natural := Decimal (Zone + 1, Zone + 2);
            Offset_Minute : constant Natural := Decimal (Zone + 4, Zone + 5);
         begin
            return Offset_Hour <= 23 and then Offset_Minute <= 59;
         end;
      end if;
      return False;
   end Valid_ISO_8601_Timestamp;

   function Parse_Boolean (Value : String) return Optional_Boolean is
   begin
      if Value = "true" then
         return (Is_Set => True, Value => True);
      elsif Value = "false" then
         return (Is_Set => True, Value => False);
      end if;
      raise Malformed_Lifecycle with "invalid lifecycle Boolean";
   end Parse_Boolean;

   function Parse_Integer (Value : String) return Optional_Integer_Text is
   begin
      if not Valid_Integer_Text (Value) then
         raise Malformed_Lifecycle with "invalid lifecycle integer";
      end if;
      return (Is_Set => True, Text => US.To_Unbounded_String (Value));
   end Parse_Integer;

   function Parse_Timestamp (Value : String) return Optional_Timestamp is
   begin
      if not Valid_ISO_8601_Timestamp (Value) then
         raise Malformed_Lifecycle with "invalid lifecycle timestamp";
      end if;
      return (Is_Set => True, Text => US.To_Unbounded_String (Value));
   end Parse_Timestamp;

   function Parse_Storage_Class
     (Value : String) return Transition_Storage_Class is
   begin
      if Value = "GLACIER" then
         return Glacier;
      elsif Value = "STANDARD_IA" then
         return Standard_IA;
      elsif Value = "ONEZONE_IA" then
         return One_Zone_IA;
      elsif Value = "INTELLIGENT_TIERING" then
         return Intelligent_Tiering;
      elsif Value = "DEEP_ARCHIVE" then
         return Deep_Archive;
      elsif Value = "GLACIER_IR" then
         return Glacier_Instant_Retrieval;
      end if;
      raise Malformed_Lifecycle with "invalid lifecycle storage class";
   end Parse_Storage_Class;

   procedure Require_Close (Actual, Expected : String) is
   begin
      if Actual /= Expected then
         raise Malformed_Lifecycle with
           "mismatched bucket-lifecycle scalar close";
      end if;
   end Require_Close;

   procedure Finish_Scalar
     (Item : in out Lifecycle_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when Rule_ID_Scalar =>
            Require_Close (Local_Name, "ID");
            Item.Current_Rule.ID :=
              (Is_Set => True, Value => Item.Text_Value);
         when Rule_Prefix_Scalar =>
            Require_Close (Local_Name, "Prefix");
            Item.Current_Rule.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Rule_Status_Scalar =>
            Require_Close (Local_Name, "Status");
            if Value = "Enabled" then
               Item.Current_Rule.Status := Rule_Enabled;
            elsif Value = "Disabled" then
               Item.Current_Rule.Status := Rule_Disabled;
            else
               raise Malformed_Lifecycle with
                 "invalid lifecycle rule status";
            end if;
         when Expiration_Date_Scalar =>
            Require_Close (Local_Name, "Date");
            Item.Current_Rule.Expiration.Date := Parse_Timestamp (Value);
         when Expiration_Days_Scalar =>
            Require_Close (Local_Name, "Days");
            Item.Current_Rule.Expiration.Days := Parse_Integer (Value);
         when Expiration_Delete_Marker_Scalar =>
            Require_Close (Local_Name, "ExpiredObjectDeleteMarker");
            Item.Current_Rule.Expiration.Expired_Object_Delete_Marker :=
              Parse_Boolean (Value);
         when Filter_Prefix_Scalar =>
            Require_Close (Local_Name, "Prefix");
            Item.Current_Rule.Filter.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Filter_Greater_Scalar =>
            Require_Close (Local_Name, "ObjectSizeGreaterThan");
            Item.Current_Rule.Filter.Object_Size_Greater_Than :=
              Parse_Integer (Value);
         when Filter_Less_Scalar =>
            Require_Close (Local_Name, "ObjectSizeLessThan");
            Item.Current_Rule.Filter.Object_Size_Less_Than :=
              Parse_Integer (Value);
         when Tag_Key_Scalar =>
            Require_Close (Local_Name, "Key");
            Item.Current_Tag.Key := Item.Text_Value;
         when Tag_Value_Scalar =>
            Require_Close (Local_Name, "Value");
            Item.Current_Tag.Value := Item.Text_Value;
         when And_Prefix_Scalar =>
            Require_Close (Local_Name, "Prefix");
            Item.Current_Rule.Filter.And_Predicates.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when And_Greater_Scalar =>
            Require_Close (Local_Name, "ObjectSizeGreaterThan");
            Item.Current_Rule.Filter.And_Predicates.
              Object_Size_Greater_Than := Parse_Integer (Value);
         when And_Less_Scalar =>
            Require_Close (Local_Name, "ObjectSizeLessThan");
            Item.Current_Rule.Filter.And_Predicates.Object_Size_Less_Than :=
              Parse_Integer (Value);
         when Transition_Date_Scalar =>
            Require_Close (Local_Name, "Date");
            Item.Current_Transition.Date := Parse_Timestamp (Value);
         when Transition_Days_Scalar =>
            Require_Close (Local_Name, "Days");
            Item.Current_Transition.Days := Parse_Integer (Value);
         when Transition_Class_Scalar =>
            Require_Close (Local_Name, "StorageClass");
            Item.Current_Transition.Storage_Class :=
              Parse_Storage_Class (Value);
         when Noncurrent_Days_Scalar =>
            Require_Close (Local_Name, "NoncurrentDays");
            Item.Current_Noncurrent.Noncurrent_Days := Parse_Integer (Value);
         when Noncurrent_Class_Scalar =>
            Require_Close (Local_Name, "StorageClass");
            Item.Current_Noncurrent.Storage_Class :=
              Parse_Storage_Class (Value);
         when Noncurrent_Newer_Scalar =>
            Require_Close (Local_Name, "NewerNoncurrentVersions");
            Item.Current_Noncurrent.Newer_Noncurrent_Versions :=
              Parse_Integer (Value);
         when Noncurrent_Expiration_Days_Scalar =>
            Require_Close (Local_Name, "NoncurrentDays");
            Item.Current_Rule.Noncurrent_Expiration.Noncurrent_Days :=
              Parse_Integer (Value);
         when Noncurrent_Expiration_Newer_Scalar =>
            Require_Close (Local_Name, "NewerNoncurrentVersions");
            Item.Current_Rule.Noncurrent_Expiration.
              Newer_Noncurrent_Versions := Parse_Integer (Value);
         when Abort_Days_Scalar =>
            Require_Close (Local_Name, "DaysAfterInitiation");
            Item.Current_Rule.Abort_Incomplete.Days_After_Initiation :=
              Parse_Integer (Value);
         when No_Scalar =>
            raise Malformed_Lifecycle with
              "bucket-lifecycle scalar close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
      Item.Depth := Item.Depth - 1;
   end Finish_Scalar;

   overriding procedure End_Element
     (Item : in out Lifecycle_Handler; Local_Name : String) is
   begin
      if Item.Scalar /= No_Scalar then
         Finish_Scalar (Item, Local_Name);
         return;
      end if;

      case Item.Depth is
         when 5 =>
            if Item.Container /= And_Tag_Container
              or else Local_Name /= "Tag"
              or else not Item.Tag_Key_Seen
              or else not Item.Tag_Value_Seen
            then
               raise Malformed_Lifecycle with
                 "incomplete lifecycle And tag";
            end if;
            Item.Current_Rule.Filter.And_Predicates.Tags.Append
              (Item.Current_Tag);
            Item.Container := And_Container;
            Item.Depth := 4;
         when 4 =>
            if Item.Container = Filter_Tag_Container
              and then Local_Name = "Tag"
              and then Item.Tag_Key_Seen
              and then Item.Tag_Value_Seen
            then
               Item.Current_Rule.Filter.Tag :=
                 (Is_Set => True, Value => Item.Current_Tag);
               Item.Container := Filter_Container;
               Item.Depth := 3;
            elsif Item.Container = And_Container
              and then Local_Name = "And"
            then
               Item.Container := Filter_Container;
               Item.Depth := 3;
            else
               raise Malformed_Lifecycle with
                 "incomplete nested lifecycle filter";
            end if;
         when 3 =>
            case Item.Container is
               when Expiration_Container =>
                  Require_Close (Local_Name, "Expiration");
               when Filter_Container =>
                  Require_Close (Local_Name, "Filter");
               when Transition_Container =>
                  Require_Close (Local_Name, "Transition");
                  Item.Current_Rule.Transitions.Append
                    (Item.Current_Transition);
               when Noncurrent_Transition_Container =>
                  Require_Close
                    (Local_Name, "NoncurrentVersionTransition");
                  Item.Current_Rule.Noncurrent_Transitions.Append
                    (Item.Current_Noncurrent);
               when Noncurrent_Expiration_Container =>
                  Require_Close
                    (Local_Name, "NoncurrentVersionExpiration");
               when Abort_Container =>
                  Require_Close
                    (Local_Name, "AbortIncompleteMultipartUpload");
               when others =>
                  raise Malformed_Lifecycle with
                    "bucket-lifecycle container close without container";
            end case;
            Item.Container := No_Container;
            Item.Depth := 2;
         when 2 =>
            if Local_Name /= "Rule"
              or else Item.Container /= No_Container
              or else not Item.Status_Seen
            then
               raise Malformed_Lifecycle with
                 "incomplete bucket-lifecycle rule";
            end if;
            Item.Value.Rules.Append (Item.Current_Rule);
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "LifecycleConfiguration" then
               raise Malformed_Lifecycle with
                 "mismatched LifecycleConfiguration close";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Lifecycle with
              "invalid bucket-lifecycle closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Lifecycle_Configuration
   is
      Handler : aliased Lifecycle_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Lifecycle with
           "incomplete bucket-lifecycle document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Lifecycle with "malformed bucket-lifecycle XML";
   end Parse;

   function Parse_Transition_Default_Minimum_Size
     (Value : String) return Transition_Default_Minimum_Size is
   begin
      if Value'Length = 0 then
         return Transition_Minimum_Absent;
      elsif Value = "varies_by_storage_class" then
         return Varies_By_Storage_Class;
      elsif Value = "all_storage_classes_128K" then
         return All_Storage_Classes_128K;
      end if;
      raise Malformed_Lifecycle with
        "invalid transition default minimum object size";
   end Parse_Transition_Default_Minimum_Size;

end Flyology.Object_Storage.S3.Lifecycle;
