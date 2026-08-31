with Flyology.Object_Storage.S3.XML_Writers;

package body Flyology.Object_Storage.S3.Metadata_Configurations is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Metadata_Container, Destination_Container,
      Journal_Container, Inventory_Container, Annotation_Container,
      Error_Container, Expiration_Container);
   type Scalar_Kind is
     (No_Scalar, Destination_Bucket_Type_Scalar,
      Destination_Bucket_ARN_Scalar, Destination_Namespace_Scalar,
      Journal_Status_Scalar, Journal_Name_Scalar, Journal_ARN_Scalar,
      Inventory_State_Scalar, Inventory_Status_Scalar,
      Inventory_Name_Scalar, Inventory_ARN_Scalar,
      Annotation_State_Scalar, Annotation_Status_Scalar,
      Annotation_Name_Scalar, Annotation_ARN_Scalar,
      Annotation_Role_Scalar, Error_Code_Scalar, Error_Message_Scalar,
      Expiration_State_Scalar, Expiration_Days_Scalar);

   function Empty_Optional_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Error return Error_Details is
     ((Is_Set  => False,
       Code    => Empty_Optional_String,
       Message => Empty_Optional_String));

   function Empty_Metadata_Configuration return Metadata_Configuration is
     --  Enum values are unreachable scratch state while their surrounding
     --  Is_Set flags are false. They are private parser initialization, not
     --  public defaults or provider policy.
     ((Destination =>
         (Table_Bucket_Type =>
            (Is_Set => False, Value => AWS_Table_Bucket),
          Table_Bucket_ARN => Empty_Optional_String,
          Table_Namespace  => Empty_Optional_String),
       Journal =>
         (Is_Set       => False,
          Table_Status => US.Null_Unbounded_String,
          Error        => Empty_Error,
          Table_Name   => US.Null_Unbounded_String,
          Table_ARN    => Empty_Optional_String,
          Expiration   =>
            (Expiration => Expiration_Disabled,
             Days       =>
               (Is_Set => False, Text => US.Null_Unbounded_String))),
       Inventory =>
         (Is_Set              => False,
          Configuration_State => Inventory_Disabled,
          Table_Status        => Empty_Optional_String,
          Error               => Empty_Error,
          Table_Name          => Empty_Optional_String,
          Table_ARN           => Empty_Optional_String),
       Annotation =>
         (Is_Set              => False,
          Configuration_State => Annotation_Disabled,
          Table_Status        => Empty_Optional_String,
          Error               => Empty_Error,
          Table_Name          => Empty_Optional_String,
          Table_ARN           => Empty_Optional_String,
          Role                => Empty_Optional_String)));

   type Metadata_Handler is new XML.Event_Handler with record
      Depth              : Natural := 0;
      Root_Seen          : Boolean := False;
      Metadata_Seen      : Boolean := False;
      Destination_Seen   : Boolean := False;
      Journal_Seen       : Boolean := False;
      Inventory_Seen     : Boolean := False;
      Annotation_Seen    : Boolean := False;
      Destination_Type_Seen      : Boolean := False;
      Destination_ARN_Seen       : Boolean := False;
      Destination_Namespace_Seen : Boolean := False;
      Journal_Status_Seen     : Boolean := False;
      Journal_Error_Seen      : Boolean := False;
      Journal_Name_Seen       : Boolean := False;
      Journal_ARN_Seen        : Boolean := False;
      Journal_Expiration_Seen : Boolean := False;
      Inventory_State_Seen  : Boolean := False;
      Inventory_Status_Seen : Boolean := False;
      Inventory_Error_Seen  : Boolean := False;
      Inventory_Name_Seen   : Boolean := False;
      Inventory_ARN_Seen    : Boolean := False;
      Annotation_State_Seen  : Boolean := False;
      Annotation_Status_Seen : Boolean := False;
      Annotation_Error_Seen  : Boolean := False;
      Annotation_Name_Seen   : Boolean := False;
      Annotation_ARN_Seen    : Boolean := False;
      Annotation_Role_Seen   : Boolean := False;
      Error_Code_Seen       : Boolean := False;
      Error_Message_Seen    : Boolean := False;
      Expiration_State_Seen : Boolean := False;
      Expiration_Days_Seen  : Boolean := False;
      Namespace          : Namespace_Style := Namespace_Not_Selected;
      Container          : Container_Kind := No_Container;
      Parent_Container   : Container_Kind := No_Container;
      Scalar             : Scalar_Kind := No_Scalar;
      Text_Value         : US.Unbounded_String;
      Value              : Metadata_Configuration :=
        Empty_Metadata_Configuration;
   end record;

   overriding procedure Start_Element
     (Item : in out Metadata_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Metadata_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Metadata_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Metadata_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Metadata_Configuration with
              "text outside metadata-configuration scalar";
         end if;
      end loop;
   end Require_Whitespace;

   function Valid_Integer_Text (Value : String) return Boolean is
      Cursor : Integer := Value'First;
   begin
      if Value'Length = 0 then
         return False;
      end if;
      if Value (Cursor) in '+' | '-' then
         Cursor := Cursor + 1;
      end if;
      if Cursor > Value'Last then
         return False;
      end if;
      while Cursor <= Value'Last loop
         if Value (Cursor) not in '0' .. '9' then
            return False;
         end if;
         Cursor := Cursor + 1;
      end loop;
      return True;
   end Valid_Integer_Text;

   overriding procedure Start_Element_Details
     (Item            : in out Metadata_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  Exact established S3 REST/XML namespace. Changing this externally
      --  fixed value changes provider compatibility for every result member.
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
         raise Malformed_Metadata_Configuration with
           "metadata-configuration namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Metadata_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Begin_Error
     (Item : in out Metadata_Handler; Parent : Container_Kind) is
   begin
      Item.Parent_Container := Parent;
      Item.Container := Error_Container;
      Item.Error_Code_Seen := False;
      Item.Error_Message_Seen := False;
      case Parent is
         when Journal_Container =>
            Item.Value.Journal.Error.Is_Set := True;
         when Inventory_Container =>
            Item.Value.Inventory.Error.Is_Set := True;
         when Annotation_Container =>
            Item.Value.Annotation.Error.Is_Set := True;
         when others =>
            raise Malformed_Metadata_Configuration with
              "metadata error outside a table result";
      end case;
   end Begin_Error;

   overriding procedure Start_Element
     (Item : in out Metadata_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Metadata_Configuration with
           "metadata-configuration depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen
              or else Local_Name /= "GetBucketMetadataConfigurationResult"
            then
               raise Malformed_Metadata_Configuration with
                 "invalid metadata-configuration result root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Item.Metadata_Seen
              or else Local_Name /= "MetadataConfigurationResult"
            then
               raise Malformed_Metadata_Configuration with
                 "unknown or duplicate metadata result member";
            end if;
            Item.Metadata_Seen := True;
            Item.Container := Metadata_Container;
         when 3 =>
            if Item.Container /= Metadata_Container then
               raise Malformed_Metadata_Configuration with
                 "metadata result member outside result";
            elsif Local_Name = "DestinationResult"
              and then not Item.Destination_Seen
            then
               Item.Destination_Seen := True;
               Item.Container := Destination_Container;
            elsif Local_Name = "JournalTableConfigurationResult"
              and then not Item.Journal_Seen
            then
               Item.Journal_Seen := True;
               Item.Value.Journal.Is_Set := True;
               Item.Container := Journal_Container;
            elsif Local_Name = "InventoryTableConfigurationResult"
              and then not Item.Inventory_Seen
            then
               Item.Inventory_Seen := True;
               Item.Value.Inventory.Is_Set := True;
               Item.Container := Inventory_Container;
            elsif Local_Name = "AnnotationTableConfigurationResult"
              and then not Item.Annotation_Seen
            then
               Item.Annotation_Seen := True;
               Item.Value.Annotation.Is_Set := True;
               Item.Container := Annotation_Container;
            else
               raise Malformed_Metadata_Configuration with
                 "unknown or duplicate metadata table result";
            end if;
         when 4 =>
            case Item.Container is
               when Destination_Container =>
                  if Local_Name = "TableBucketType"
                    and then not Item.Destination_Type_Seen
                  then
                     Item.Destination_Type_Seen := True;
                     Begin_Scalar (Item, Destination_Bucket_Type_Scalar);
                  elsif Local_Name = "TableBucketArn"
                    and then not Item.Destination_ARN_Seen
                  then
                     Item.Destination_ARN_Seen := True;
                     Begin_Scalar (Item, Destination_Bucket_ARN_Scalar);
                  elsif Local_Name = "TableNamespace"
                    and then not Item.Destination_Namespace_Seen
                  then
                     Item.Destination_Namespace_Seen := True;
                     Begin_Scalar (Item, Destination_Namespace_Scalar);
                  else
                     raise Malformed_Metadata_Configuration with
                       "unknown or duplicate metadata destination member";
                  end if;
               when Journal_Container =>
                  if Local_Name = "TableStatus"
                    and then not Item.Journal_Status_Seen
                  then
                     Item.Journal_Status_Seen := True;
                     Begin_Scalar (Item, Journal_Status_Scalar);
                  elsif Local_Name = "Error"
                    and then not Item.Journal_Error_Seen
                  then
                     Item.Journal_Error_Seen := True;
                     Begin_Error (Item, Journal_Container);
                  elsif Local_Name = "TableName"
                    and then not Item.Journal_Name_Seen
                  then
                     Item.Journal_Name_Seen := True;
                     Begin_Scalar (Item, Journal_Name_Scalar);
                  elsif Local_Name = "TableArn"
                    and then not Item.Journal_ARN_Seen
                  then
                     Item.Journal_ARN_Seen := True;
                     Begin_Scalar (Item, Journal_ARN_Scalar);
                  elsif Local_Name = "RecordExpiration"
                    and then not Item.Journal_Expiration_Seen
                  then
                     Item.Journal_Expiration_Seen := True;
                     Item.Parent_Container := Journal_Container;
                     Item.Container := Expiration_Container;
                  else
                     raise Malformed_Metadata_Configuration with
                       "unknown or duplicate metadata journal member";
                  end if;
               when Inventory_Container =>
                  if Local_Name = "ConfigurationState"
                    and then not Item.Inventory_State_Seen
                  then
                     Item.Inventory_State_Seen := True;
                     Begin_Scalar (Item, Inventory_State_Scalar);
                  elsif Local_Name = "TableStatus"
                    and then not Item.Inventory_Status_Seen
                  then
                     Item.Inventory_Status_Seen := True;
                     Begin_Scalar (Item, Inventory_Status_Scalar);
                  elsif Local_Name = "Error"
                    and then not Item.Inventory_Error_Seen
                  then
                     Item.Inventory_Error_Seen := True;
                     Begin_Error (Item, Inventory_Container);
                  elsif Local_Name = "TableName"
                    and then not Item.Inventory_Name_Seen
                  then
                     Item.Inventory_Name_Seen := True;
                     Begin_Scalar (Item, Inventory_Name_Scalar);
                  elsif Local_Name = "TableArn"
                    and then not Item.Inventory_ARN_Seen
                  then
                     Item.Inventory_ARN_Seen := True;
                     Begin_Scalar (Item, Inventory_ARN_Scalar);
                  else
                     raise Malformed_Metadata_Configuration with
                       "unknown or duplicate metadata inventory member";
                  end if;
               when Annotation_Container =>
                  if Local_Name = "ConfigurationState"
                    and then not Item.Annotation_State_Seen
                  then
                     Item.Annotation_State_Seen := True;
                     Begin_Scalar (Item, Annotation_State_Scalar);
                  elsif Local_Name = "TableStatus"
                    and then not Item.Annotation_Status_Seen
                  then
                     Item.Annotation_Status_Seen := True;
                     Begin_Scalar (Item, Annotation_Status_Scalar);
                  elsif Local_Name = "Error"
                    and then not Item.Annotation_Error_Seen
                  then
                     Item.Annotation_Error_Seen := True;
                     Begin_Error (Item, Annotation_Container);
                  elsif Local_Name = "TableName"
                    and then not Item.Annotation_Name_Seen
                  then
                     Item.Annotation_Name_Seen := True;
                     Begin_Scalar (Item, Annotation_Name_Scalar);
                  elsif Local_Name = "TableArn"
                    and then not Item.Annotation_ARN_Seen
                  then
                     Item.Annotation_ARN_Seen := True;
                     Begin_Scalar (Item, Annotation_ARN_Scalar);
                  elsif Local_Name = "Role"
                    and then not Item.Annotation_Role_Seen
                  then
                     Item.Annotation_Role_Seen := True;
                     Begin_Scalar (Item, Annotation_Role_Scalar);
                  else
                     raise Malformed_Metadata_Configuration with
                       "unknown or duplicate metadata annotation member";
                  end if;
               when others =>
                  raise Malformed_Metadata_Configuration with
                    "metadata scalar outside table result";
            end case;
         when 5 =>
            if Item.Container = Error_Container then
               if Local_Name = "ErrorCode"
                 and then not Item.Error_Code_Seen
               then
                  Item.Error_Code_Seen := True;
                  Begin_Scalar (Item, Error_Code_Scalar);
               elsif Local_Name = "ErrorMessage"
                 and then not Item.Error_Message_Seen
               then
                  Item.Error_Message_Seen := True;
                  Begin_Scalar (Item, Error_Message_Scalar);
               else
                  raise Malformed_Metadata_Configuration with
                    "unknown or duplicate metadata error member";
               end if;
            elsif Item.Container = Expiration_Container then
               if Local_Name = "Expiration"
                 and then not Item.Expiration_State_Seen
               then
                  Item.Expiration_State_Seen := True;
                  Begin_Scalar (Item, Expiration_State_Scalar);
               elsif Local_Name = "Days"
                 and then not Item.Expiration_Days_Seen
               then
                  Item.Expiration_Days_Seen := True;
                  Begin_Scalar (Item, Expiration_Days_Scalar);
               else
                  raise Malformed_Metadata_Configuration with
                    "unknown or duplicate record-expiration member";
               end if;
            else
               raise Malformed_Metadata_Configuration with
                 "nested metadata member outside modeled container";
            end if;
         when others =>
            raise Malformed_Metadata_Configuration with
              "nested metadata-configuration member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Metadata_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      else
         Require_Whitespace (Value);
      end if;
   end Text;

   function Optional (Value : US.Unbounded_String) return Optional_String is
     ((Is_Set => True, Value => Value));

   procedure Store_Error_Scalar
     (Item : in out Metadata_Handler; Is_Code : Boolean) is
      Value : constant Optional_String := Optional (Item.Text_Value);
   begin
      case Item.Parent_Container is
         when Journal_Container =>
            if Is_Code then
               Item.Value.Journal.Error.Code := Value;
            else
               Item.Value.Journal.Error.Message := Value;
            end if;
         when Inventory_Container =>
            if Is_Code then
               Item.Value.Inventory.Error.Code := Value;
            else
               Item.Value.Inventory.Error.Message := Value;
            end if;
         when Annotation_Container =>
            if Is_Code then
               Item.Value.Annotation.Error.Code := Value;
            else
               Item.Value.Annotation.Error.Message := Value;
            end if;
         when others =>
            raise Malformed_Metadata_Configuration with
              "metadata error scalar outside table result";
      end case;
   end Store_Error_Scalar;

   procedure Store_Scalar (Item : in out Metadata_Handler) is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when Destination_Bucket_Type_Scalar =>
            Item.Value.Destination.Table_Bucket_Type :=
              (Is_Set => True,
               Value  =>
                 (if Value = "aws" then AWS_Table_Bucket
                  elsif Value = "customer" then Customer_Table_Bucket
                  else raise Malformed_Metadata_Configuration with
                    "invalid metadata table-bucket type"));
         when Destination_Bucket_ARN_Scalar =>
            Item.Value.Destination.Table_Bucket_ARN :=
              Optional (Item.Text_Value);
         when Destination_Namespace_Scalar =>
            Item.Value.Destination.Table_Namespace :=
              Optional (Item.Text_Value);
         when Journal_Status_Scalar =>
            Item.Value.Journal.Table_Status := Item.Text_Value;
         when Journal_Name_Scalar =>
            Item.Value.Journal.Table_Name := Item.Text_Value;
         when Journal_ARN_Scalar =>
            Item.Value.Journal.Table_ARN := Optional (Item.Text_Value);
         when Inventory_State_Scalar =>
            Item.Value.Inventory.Configuration_State :=
              (if Value = "ENABLED" then Inventory_Enabled
               elsif Value = "DISABLED" then Inventory_Disabled
               else raise Malformed_Metadata_Configuration with
                 "invalid inventory-table configuration state");
         when Inventory_Status_Scalar =>
            Item.Value.Inventory.Table_Status := Optional (Item.Text_Value);
         when Inventory_Name_Scalar =>
            Item.Value.Inventory.Table_Name := Optional (Item.Text_Value);
         when Inventory_ARN_Scalar =>
            Item.Value.Inventory.Table_ARN := Optional (Item.Text_Value);
         when Annotation_State_Scalar =>
            Item.Value.Annotation.Configuration_State :=
              (if Value = "ENABLED" then Annotation_Enabled
               elsif Value = "DISABLED" then Annotation_Disabled
               else raise Malformed_Metadata_Configuration with
                 "invalid annotation-table configuration state");
         when Annotation_Status_Scalar =>
            Item.Value.Annotation.Table_Status := Optional (Item.Text_Value);
         when Annotation_Name_Scalar =>
            Item.Value.Annotation.Table_Name := Optional (Item.Text_Value);
         when Annotation_ARN_Scalar =>
            Item.Value.Annotation.Table_ARN := Optional (Item.Text_Value);
         when Annotation_Role_Scalar =>
            Item.Value.Annotation.Role := Optional (Item.Text_Value);
         when Error_Code_Scalar =>
            Store_Error_Scalar (Item, True);
         when Error_Message_Scalar =>
            Store_Error_Scalar (Item, False);
         when Expiration_State_Scalar =>
            Item.Value.Journal.Expiration.Expiration :=
              (if Value = "ENABLED" then Expiration_Enabled
               elsif Value = "DISABLED" then Expiration_Disabled
               else raise Malformed_Metadata_Configuration with
                 "invalid record-expiration state");
         when Expiration_Days_Scalar =>
            if not Valid_Integer_Text (Value) then
               raise Malformed_Metadata_Configuration with
                 "invalid record-expiration day count";
            end if;
            Item.Value.Journal.Expiration.Days :=
              (Is_Set => True, Text => Item.Text_Value);
         when No_Scalar =>
            raise Malformed_Metadata_Configuration with
              "metadata close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when Destination_Bucket_Type_Scalar => "TableBucketType",
         when Destination_Bucket_ARN_Scalar  => "TableBucketArn",
         when Destination_Namespace_Scalar   => "TableNamespace",
         when Journal_Status_Scalar | Inventory_Status_Scalar |
              Annotation_Status_Scalar       => "TableStatus",
         when Journal_Name_Scalar | Inventory_Name_Scalar |
              Annotation_Name_Scalar         => "TableName",
         when Journal_ARN_Scalar | Inventory_ARN_Scalar |
              Annotation_ARN_Scalar          => "TableArn",
         when Inventory_State_Scalar | Annotation_State_Scalar =>
           "ConfigurationState",
         when Annotation_Role_Scalar         => "Role",
         when Error_Code_Scalar              => "ErrorCode",
         when Error_Message_Scalar           => "ErrorMessage",
         when Expiration_State_Scalar        => "Expiration",
         when Expiration_Days_Scalar         => "Days",
         when No_Scalar                      => "");

   overriding procedure End_Element
     (Item : in out Metadata_Handler; Local_Name : String) is
   begin
      case Item.Depth is
         when 5 =>
            if Item.Scalar = No_Scalar
              or else Local_Name /= Scalar_Name (Item.Scalar)
            then
               raise Malformed_Metadata_Configuration with
                 "mismatched nested metadata scalar close";
            end if;
            Store_Scalar (Item);
            Item.Depth := 4;
         when 4 =>
            if Item.Scalar /= No_Scalar then
               if Local_Name /= Scalar_Name (Item.Scalar) then
                  raise Malformed_Metadata_Configuration with
                    "mismatched metadata scalar close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Error_Container then
               if Local_Name /= "Error" then
                  raise Malformed_Metadata_Configuration with
                    "mismatched metadata error close";
               end if;
               Item.Container := Item.Parent_Container;
               Item.Parent_Container := No_Container;
            elsif Item.Container = Expiration_Container then
               if Local_Name /= "RecordExpiration"
                 or else not Item.Expiration_State_Seen
               then
                  raise Malformed_Metadata_Configuration with
                    "incomplete record-expiration result";
               end if;
               Item.Container := Journal_Container;
               Item.Parent_Container := No_Container;
            else
               raise Malformed_Metadata_Configuration with
                 "metadata member close without open member";
            end if;
            Item.Depth := 3;
         when 3 =>
            case Item.Container is
               when Destination_Container =>
                  if Local_Name /= "DestinationResult" then
                     raise Malformed_Metadata_Configuration with
                       "mismatched metadata destination close";
                  end if;
               when Journal_Container =>
                  if Local_Name /= "JournalTableConfigurationResult"
                    or else not Item.Journal_Status_Seen
                    or else not Item.Journal_Name_Seen
                    or else not Item.Journal_Expiration_Seen
                  then
                     raise Malformed_Metadata_Configuration with
                       "incomplete metadata journal result";
                  end if;
               when Inventory_Container =>
                  if Local_Name /= "InventoryTableConfigurationResult"
                    or else not Item.Inventory_State_Seen
                  then
                     raise Malformed_Metadata_Configuration with
                       "incomplete metadata inventory result";
                  end if;
               when Annotation_Container =>
                  if Local_Name /= "AnnotationTableConfigurationResult"
                    or else not Item.Annotation_State_Seen
                  then
                     raise Malformed_Metadata_Configuration with
                       "incomplete metadata annotation result";
                  end if;
               when others =>
                  raise Malformed_Metadata_Configuration with
                    "metadata table result close without open result";
            end case;
            Item.Container := Metadata_Container;
            Item.Depth := 2;
         when 2 =>
            if Item.Container /= Metadata_Container
              or else Local_Name /= "MetadataConfigurationResult"
              or else not Item.Destination_Seen
            then
               raise Malformed_Metadata_Configuration with
                 "incomplete metadata configuration result";
            end if;
            Item.Container := No_Container;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "GetBucketMetadataConfigurationResult"
              or else not Item.Metadata_Seen
            then
               raise Malformed_Metadata_Configuration with
                 "incomplete metadata-configuration document";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Metadata_Configuration with
              "invalid metadata-configuration closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Metadata_Configuration
   is
      Handler : aliased Metadata_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Metadata_Configuration with
           "incomplete metadata-configuration document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Metadata_Configuration with
           "malformed metadata-configuration XML";
   end Parse;

   function Annotation_State_Image
     (Value : Annotation_Configuration_State) return String is
     (case Value is
         when Annotation_Enabled  => "ENABLED",
         when Annotation_Disabled => "DISABLED");

   function Inventory_State_Image
     (Value : Inventory_Configuration_State) return String is
     (case Value is
         when Inventory_Enabled  => "ENABLED",
         when Inventory_Disabled => "DISABLED");

   function Expiration_State_Image
     (Value : Expiration_State) return String is
     (case Value is
         when Expiration_Enabled  => "ENABLED",
         when Expiration_Disabled => "DISABLED");

   function SSE_Algorithm_Image
     (Value : Metadata_Table_SSE_Algorithm) return String is
     (case Value is
         when Metadata_SSE_KMS => "aws:kms",
         when Metadata_SSE_S3  => "AES256");

   procedure Write_Encryption
     (Item  : in out XML_Writers.Writer;
      Value : Metadata_Table_Encryption) is
   begin
      if not Value.Is_Set then
         return;
      end if;
      XML_Writers.Start_Element (Item, "EncryptionConfiguration");
      XML_Writers.Text_Element
        (Item, "SseAlgorithm", SSE_Algorithm_Image (Value.Algorithm));
      if Value.KMS_Key_ARN.Is_Set then
         XML_Writers.Text_Element
           (Item, "KmsKeyArn", US.To_String (Value.KMS_Key_ARN.Value));
      end if;
      XML_Writers.End_Element (Item, "EncryptionConfiguration");
   end Write_Encryption;

   procedure Write_Record_Expiration
     (Item  : in out XML_Writers.Writer;
      Value : Record_Expiration) is
      Days : constant String := US.To_String (Value.Days.Text);
   begin
      if Value.Days.Is_Set and then not Valid_Integer_Text (Days) then
         raise Malformed_Metadata_Configuration with
           "invalid metadata record-expiration days";
      end if;
      XML_Writers.Start_Element (Item, "RecordExpiration");
      XML_Writers.Text_Element
        (Item, "Expiration", Expiration_State_Image (Value.Expiration));
      if Value.Days.Is_Set then
         XML_Writers.Text_Element (Item, "Days", Days);
      end if;
      XML_Writers.End_Element (Item, "RecordExpiration");
   end Write_Record_Expiration;

   function Serialize_Create
     (Value  : Metadata_Configuration_Request;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document
        (Item, "MetadataConfiguration",
         "http://s3.amazonaws.com/doc/2006-03-01/");
      XML_Writers.Start_Element (Item, "JournalTableConfiguration");
      Write_Record_Expiration (Item, Value.Journal.Expiration);
      Write_Encryption (Item, Value.Journal.Encryption);
      XML_Writers.End_Element (Item, "JournalTableConfiguration");
      if Value.Inventory.Is_Set then
         XML_Writers.Start_Element (Item, "InventoryTableConfiguration");
         XML_Writers.Text_Element
           (Item, "ConfigurationState",
            Inventory_State_Image (Value.Inventory.Configuration_State));
         Write_Encryption (Item, Value.Inventory.Encryption);
         XML_Writers.End_Element (Item, "InventoryTableConfiguration");
      end if;
      if Value.Annotation.Is_Set then
         XML_Writers.Start_Element (Item, "AnnotationTableConfiguration");
         XML_Writers.Text_Element
           (Item, "ConfigurationState",
            Annotation_State_Image (Value.Annotation.Configuration_State));
         Write_Encryption (Item, Value.Annotation.Encryption);
         if Value.Annotation.Role.Is_Set then
            XML_Writers.Text_Element
              (Item, "Role", US.To_String (Value.Annotation.Role.Value));
         end if;
         XML_Writers.End_Element (Item, "AnnotationTableConfiguration");
      end if;
      return XML_Writers.Finish (Item, "MetadataConfiguration");
   exception
      when XML_Writers.Encoding_Error =>
         raise Malformed_Metadata_Configuration with
           "metadata serialization violates caller limits";
   end Serialize_Create;

   function Serialize_Update_Inventory
     (Value  : Inventory_Table_Configuration;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      if not Value.Is_Set then
         raise Malformed_Metadata_Configuration with
           "missing inventory-table configuration update";
      end if;
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document
        (Item, "InventoryTableConfiguration",
         "http://s3.amazonaws.com/doc/2006-03-01/");
      XML_Writers.Text_Element
        (Item, "ConfigurationState",
         Inventory_State_Image (Value.Configuration_State));
      Write_Encryption (Item, Value.Encryption);
      return XML_Writers.Finish (Item, "InventoryTableConfiguration");
   exception
      when XML_Writers.Encoding_Error =>
         raise Malformed_Metadata_Configuration with
           "metadata inventory update serialization violates caller limits";
   end Serialize_Update_Inventory;

   function Serialize_Update_Journal
     (Value  : Record_Expiration;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document
        (Item, "JournalTableConfiguration",
         "http://s3.amazonaws.com/doc/2006-03-01/");
      Write_Record_Expiration (Item, Value);
      return XML_Writers.Finish (Item, "JournalTableConfiguration");
   exception
      when XML_Writers.Encoding_Error =>
         raise Malformed_Metadata_Configuration with
           "metadata journal update serialization violates caller limits";
   end Serialize_Update_Journal;

   function Serialize_Update_Annotation
     (Value  : Annotation_Table_Configuration;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      if not Value.Is_Set then
         raise Malformed_Metadata_Configuration with
           "missing annotation-table configuration update";
      end if;
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document
        (Item, "AnnotationTableConfiguration",
         "http://s3.amazonaws.com/doc/2006-03-01/");
      XML_Writers.Text_Element
        (Item, "ConfigurationState",
         Annotation_State_Image (Value.Configuration_State));
      Write_Encryption (Item, Value.Encryption);
      if Value.Role.Is_Set then
         XML_Writers.Text_Element
           (Item, "Role", US.To_String (Value.Role.Value));
      end if;
      return XML_Writers.Finish (Item, "AnnotationTableConfiguration");
   exception
      when XML_Writers.Encoding_Error =>
         raise Malformed_Metadata_Configuration with
           "metadata annotation update serialization violates caller limits";
   end Serialize_Update_Annotation;

end Flyology.Object_Storage.S3.Metadata_Configurations;
