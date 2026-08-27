with Flyology.Object_Storage.S3.Wire_Core;
with Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;

package body Flyology.Object_Storage.S3.Inventory is

   package US renames Ada.Strings.Unbounded;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container,
      Root_Container,
      Destination_Container,
      S3_Destination_Container,
      Filter_Container,
      Optional_Fields_Container,
      Schedule_Container,
      Encryption_Container,
      SSE_S3_Container,
      SSE_KMS_Container);
   type Scalar_Kind is
     (No_Scalar,
      Is_Enabled_Scalar,
      ID_Scalar,
      Versions_Scalar,
      Account_ID_Scalar,
      Bucket_Scalar,
      Format_Scalar,
      Destination_Prefix_Scalar,
      Filter_Prefix_Scalar,
      Optional_Field_Scalar,
      Frequency_Scalar,
      KMS_Key_ID_Scalar);

   function Empty_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Encryption return Inventory_Encryption is
     ((Is_Set         => False,
       SSE_S3         => False,
       SSE_KMS_Key_ID => Empty_String));

   function Empty_Configuration return Inventory_Configuration is
     --  CSV, All_Versions, and Daily are neutral construction values drawn
     --  from the pinned enum domains. Seen flags prevent absent required
     --  members from being accepted as those values.
     ((Destination =>
         (S3_Bucket =>
            (Account_ID => Empty_String,
             Bucket     => US.Null_Unbounded_String,
             Format     => CSV,
             Prefix     => Empty_String,
             Encryption => Empty_Encryption)),
       Is_Enabled      => False,
       Filter          =>
         (Is_Set => False, Prefix => US.Null_Unbounded_String),
       ID              => US.Null_Unbounded_String,
       Versions        => All_Versions,
       Optional_Fields => Optional_Field_Vectors.Empty_Vector,
       Schedule        => (Frequency => Daily)));

   type Inventory_Handler is new XML.Event_Handler with record
      Depth                  : Natural := 0;
      Root_Seen              : Boolean := False;
      Destination_Seen       : Boolean := False;
      S3_Destination_Seen    : Boolean := False;
      Is_Enabled_Seen        : Boolean := False;
      Filter_Seen            : Boolean := False;
      Filter_Prefix_Seen     : Boolean := False;
      ID_Seen                : Boolean := False;
      Versions_Seen          : Boolean := False;
      Optional_Fields_Seen   : Boolean := False;
      Schedule_Seen          : Boolean := False;
      Frequency_Seen         : Boolean := False;
      Account_ID_Seen        : Boolean := False;
      Bucket_Seen            : Boolean := False;
      Format_Seen            : Boolean := False;
      Destination_Prefix_Seen : Boolean := False;
      Encryption_Seen        : Boolean := False;
      SSE_S3_Seen            : Boolean := False;
      SSE_KMS_Seen           : Boolean := False;
      KMS_Key_ID_Seen        : Boolean := False;
      Namespace              : Namespace_Style := Namespace_Not_Selected;
      Container              : Container_Kind := No_Container;
      Scalar                 : Scalar_Kind := No_Scalar;
      Text_Value             : US.Unbounded_String;
      Value                  : Inventory_Configuration := Empty_Configuration;
   end record;

   overriding procedure Start_Element
     (Item : in out Inventory_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Inventory_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Inventory_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Inventory_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Inventory with "text outside inventory scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Inventory_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  The S3 REST/XML namespace is the provider wire authority; accepting
      --  another URI would change response compatibility.
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
         raise Malformed_Inventory with
           "inventory namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Inventory_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   overriding procedure Start_Element
     (Item : in out Inventory_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Inventory with "inventory depth overflow";
      elsif Item.Scalar /= No_Scalar then
         raise Malformed_Inventory with "inventory scalar contains element";
      end if;
      Item.Depth := Item.Depth + 1;

      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "InventoryConfiguration" then
            raise Malformed_Inventory with "invalid inventory root";
         end if;
         Item.Root_Seen := True;
         Item.Container := Root_Container;
         return;
      end if;

      case Item.Container is
         when Root_Container =>
            if Local_Name = "Destination"
              and then not Item.Destination_Seen
            then
               Item.Destination_Seen := True;
               Item.Container := Destination_Container;
            elsif Local_Name = "IsEnabled"
              and then not Item.Is_Enabled_Seen
            then
               Item.Is_Enabled_Seen := True;
               Begin_Scalar (Item, Is_Enabled_Scalar);
            elsif Local_Name = "Filter" and then not Item.Filter_Seen then
               Item.Filter_Seen := True;
               Item.Value.Filter.Is_Set := True;
               Item.Container := Filter_Container;
            elsif Local_Name = "Id" and then not Item.ID_Seen then
               Item.ID_Seen := True;
               Begin_Scalar (Item, ID_Scalar);
            elsif Local_Name = "IncludedObjectVersions"
              and then not Item.Versions_Seen
            then
               Item.Versions_Seen := True;
               Begin_Scalar (Item, Versions_Scalar);
            elsif Local_Name = "OptionalFields"
              and then not Item.Optional_Fields_Seen
            then
               Item.Optional_Fields_Seen := True;
               Item.Container := Optional_Fields_Container;
            elsif Local_Name = "Schedule" and then not Item.Schedule_Seen then
               Item.Schedule_Seen := True;
               Item.Container := Schedule_Container;
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory member";
            end if;

         when Destination_Container =>
            if Local_Name = "S3BucketDestination"
              and then not Item.S3_Destination_Seen
            then
               Item.S3_Destination_Seen := True;
               Item.Container := S3_Destination_Container;
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory destination member";
            end if;

         when S3_Destination_Container =>
            if Local_Name = "AccountId" and then not Item.Account_ID_Seen then
               Item.Account_ID_Seen := True;
               Begin_Scalar (Item, Account_ID_Scalar);
            elsif Local_Name = "Bucket" and then not Item.Bucket_Seen then
               Item.Bucket_Seen := True;
               Begin_Scalar (Item, Bucket_Scalar);
            elsif Local_Name = "Format" and then not Item.Format_Seen then
               Item.Format_Seen := True;
               Begin_Scalar (Item, Format_Scalar);
            elsif Local_Name = "Prefix"
              and then not Item.Destination_Prefix_Seen
            then
               Item.Destination_Prefix_Seen := True;
               Begin_Scalar (Item, Destination_Prefix_Scalar);
            elsif Local_Name = "Encryption"
              and then not Item.Encryption_Seen
            then
               Item.Encryption_Seen := True;
               Item.Value.Destination.S3_Bucket.Encryption.Is_Set := True;
               Item.Container := Encryption_Container;
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory S3 destination member";
            end if;

         when Filter_Container =>
            if Local_Name = "Prefix" and then not Item.Filter_Prefix_Seen then
               Item.Filter_Prefix_Seen := True;
               Begin_Scalar (Item, Filter_Prefix_Scalar);
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory filter member";
            end if;

         when Optional_Fields_Container =>
            if Local_Name = "Field" then
               Begin_Scalar (Item, Optional_Field_Scalar);
            else
               raise Malformed_Inventory with
                 "unknown inventory optional-fields member";
            end if;

         when Schedule_Container =>
            if Local_Name = "Frequency" and then not Item.Frequency_Seen then
               Item.Frequency_Seen := True;
               Begin_Scalar (Item, Frequency_Scalar);
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory schedule member";
            end if;

         when Encryption_Container =>
            if Local_Name = "SSE-S3" and then not Item.SSE_S3_Seen then
               Item.SSE_S3_Seen := True;
               Item.Value.Destination.S3_Bucket.Encryption.SSE_S3 := True;
               Item.Container := SSE_S3_Container;
            elsif Local_Name = "SSE-KMS" and then not Item.SSE_KMS_Seen then
               Item.SSE_KMS_Seen := True;
               Item.Container := SSE_KMS_Container;
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory encryption member";
            end if;

         when SSE_KMS_Container =>
            if Local_Name = "KeyId" and then not Item.KMS_Key_ID_Seen then
               Item.KMS_Key_ID_Seen := True;
               Begin_Scalar (Item, KMS_Key_ID_Scalar);
            else
               raise Malformed_Inventory with
                 "unknown or duplicate inventory SSE-KMS member";
            end if;

         when SSE_S3_Container =>
            raise Malformed_Inventory with
              "SSE-S3 inventory member contains an element";

         when No_Container =>
            raise Malformed_Inventory with "inventory element outside root";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Inventory_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth > 0 then
         Require_Whitespace (Value);
      else
         raise Malformed_Inventory with "inventory text outside document";
      end if;
   end Text;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when Is_Enabled_Scalar => "IsEnabled",
         when ID_Scalar => "Id",
         when Versions_Scalar => "IncludedObjectVersions",
         when Account_ID_Scalar => "AccountId",
         when Bucket_Scalar => "Bucket",
         when Format_Scalar => "Format",
         when Destination_Prefix_Scalar | Filter_Prefix_Scalar => "Prefix",
         when Optional_Field_Scalar => "Field",
         when Frequency_Scalar => "Frequency",
         when KMS_Key_ID_Scalar => "KeyId",
         when No_Scalar => "");

   function Decode_Optional_Field (Text : String) return Optional_Field_Kind is
   begin
      if Text = "Size" then
         return Size;
      elsif Text = "LastModifiedDate" then
         return Last_Modified_Date;
      elsif Text = "StorageClass" then
         return Storage_Class;
      elsif Text = "ETag" then
         return ETag;
      elsif Text = "IsMultipartUploaded" then
         return Is_Multipart_Uploaded;
      elsif Text = "ReplicationStatus" then
         return Replication_Status;
      elsif Text = "EncryptionStatus" then
         return Encryption_Status;
      elsif Text = "ObjectLockRetainUntilDate" then
         return Object_Lock_Retain_Until_Date;
      elsif Text = "ObjectLockMode" then
         return Object_Lock_Mode;
      elsif Text = "ObjectLockLegalHoldStatus" then
         return Object_Lock_Legal_Hold_Status;
      elsif Text = "IntelligentTieringAccessTier" then
         return Intelligent_Tiering_Access_Tier;
      elsif Text = "BucketKeyStatus" then
         return Bucket_Key_Status;
      elsif Text = "ChecksumAlgorithm" then
         return Checksum_Algorithm;
      elsif Text = "ObjectAccessControlList" then
         return Object_Access_Control_List;
      elsif Text = "ObjectOwner" then
         return Object_Owner;
      elsif Text = "LifecycleExpirationDate" then
         return Lifecycle_Expiration_Date;
      end if;
      raise Malformed_Inventory with "invalid inventory optional field";
   end Decode_Optional_Field;

   procedure Store_Scalar (Item : in out Inventory_Handler) is
      Text_Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when Is_Enabled_Scalar =>
            declare
               Parsed : constant Wire_Core.Boolean_Result :=
                 Wire_Core.Parse_Boolean (Text_Value);
            begin
               if not Parsed.Valid then
                  raise Malformed_Inventory with
                    "invalid inventory enabled value";
               end if;
               Item.Value.Is_Enabled := Parsed.Value;
            end;
         when ID_Scalar =>
            Item.Value.ID := Item.Text_Value;
         when Versions_Scalar =>
            if Text_Value = "All" then
               Item.Value.Versions := All_Versions;
            elsif Text_Value = "Current" then
               Item.Value.Versions := Current_Versions;
            else
               raise Malformed_Inventory with
                 "invalid inventory included-object-versions value";
            end if;
         when Account_ID_Scalar =>
            Item.Value.Destination.S3_Bucket.Account_ID :=
              (Is_Set => True, Value => Item.Text_Value);
         when Bucket_Scalar =>
            Item.Value.Destination.S3_Bucket.Bucket := Item.Text_Value;
         when Format_Scalar =>
            if Text_Value = "CSV" then
               Item.Value.Destination.S3_Bucket.Format := CSV;
            elsif Text_Value = "ORC" then
               Item.Value.Destination.S3_Bucket.Format := ORC;
            elsif Text_Value = "Parquet" then
               Item.Value.Destination.S3_Bucket.Format := Parquet;
            else
               raise Malformed_Inventory with "invalid inventory format";
            end if;
         when Destination_Prefix_Scalar =>
            Item.Value.Destination.S3_Bucket.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Filter_Prefix_Scalar =>
            Item.Value.Filter.Prefix := Item.Text_Value;
         when Optional_Field_Scalar =>
            Item.Value.Optional_Fields.Append
              (Decode_Optional_Field (Text_Value));
         when Frequency_Scalar =>
            if Text_Value = "Daily" then
               Item.Value.Schedule.Frequency := Daily;
            elsif Text_Value = "Weekly" then
               Item.Value.Schedule.Frequency := Weekly;
            else
               raise Malformed_Inventory with "invalid inventory frequency";
            end if;
         when KMS_Key_ID_Scalar =>
            Item.Value.Destination.S3_Bucket.Encryption.SSE_KMS_Key_ID :=
              (Is_Set => True, Value => Item.Text_Value);
         when No_Scalar =>
            raise Malformed_Inventory with "inventory close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   overriding procedure End_Element
     (Item : in out Inventory_Handler; Local_Name : String) is
   begin
      if Item.Depth = 0 then
         raise Malformed_Inventory with "inventory close outside document";
      elsif Item.Scalar /= No_Scalar then
         if Local_Name /= Scalar_Name (Item.Scalar) then
            raise Malformed_Inventory with
              "mismatched inventory scalar close";
         end if;
         Store_Scalar (Item);
         Item.Depth := Item.Depth - 1;
         return;
      end if;

      case Item.Container is
         when SSE_S3_Container =>
            if Local_Name /= "SSE-S3" then
               raise Malformed_Inventory with "invalid SSE-S3 close";
            end if;
            Item.Container := Encryption_Container;
         when SSE_KMS_Container =>
            if Local_Name /= "SSE-KMS" or else not Item.KMS_Key_ID_Seen then
               raise Malformed_Inventory with
                 "incomplete inventory SSE-KMS member";
            end if;
            Item.Container := Encryption_Container;
         when Encryption_Container =>
            if Local_Name /= "Encryption" then
               raise Malformed_Inventory with
                 "invalid inventory encryption close";
            end if;
            Item.Container := S3_Destination_Container;
         when S3_Destination_Container =>
            if Local_Name /= "S3BucketDestination"
              or else not Item.Bucket_Seen
              or else not Item.Format_Seen
            then
               raise Malformed_Inventory with
                 "incomplete inventory S3 destination";
            end if;
            Item.Container := Destination_Container;
         when Destination_Container =>
            if Local_Name /= "Destination"
              or else not Item.S3_Destination_Seen
            then
               raise Malformed_Inventory with
                 "incomplete inventory destination";
            end if;
            Item.Container := Root_Container;
         when Filter_Container =>
            if Local_Name /= "Filter" or else not Item.Filter_Prefix_Seen then
               raise Malformed_Inventory with
                 "incomplete inventory filter";
            end if;
            Item.Container := Root_Container;
         when Optional_Fields_Container =>
            if Local_Name /= "OptionalFields" then
               raise Malformed_Inventory with
                 "invalid inventory optional-fields close";
            end if;
            Item.Container := Root_Container;
         when Schedule_Container =>
            if Local_Name /= "Schedule" or else not Item.Frequency_Seen then
               raise Malformed_Inventory with
                 "incomplete inventory schedule";
            end if;
            Item.Container := Root_Container;
         when Root_Container =>
            if Local_Name /= "InventoryConfiguration"
              or else not Item.Destination_Seen
              or else not Item.Is_Enabled_Seen
              or else not Item.ID_Seen
              or else not Item.Versions_Seen
              or else not Item.Schedule_Seen
            then
               raise Malformed_Inventory with
                 "incomplete inventory configuration";
            end if;
            Item.Container := No_Container;
         when No_Container =>
            raise Malformed_Inventory with
              "inventory container close outside document";
      end case;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Reset_Handler (Item : in out Inventory_Handler) is
   begin
      Item.Depth := 0;
      Item.Root_Seen := False;
      Item.Destination_Seen := False;
      Item.S3_Destination_Seen := False;
      Item.Is_Enabled_Seen := False;
      Item.Filter_Seen := False;
      Item.Filter_Prefix_Seen := False;
      Item.ID_Seen := False;
      Item.Versions_Seen := False;
      Item.Optional_Fields_Seen := False;
      Item.Schedule_Seen := False;
      Item.Frequency_Seen := False;
      Item.Account_ID_Seen := False;
      Item.Bucket_Seen := False;
      Item.Format_Seen := False;
      Item.Destination_Prefix_Seen := False;
      Item.Encryption_Seen := False;
      Item.SSE_S3_Seen := False;
      Item.SSE_KMS_Seen := False;
      Item.KMS_Key_ID_Seen := False;
      Item.Namespace := Namespace_Not_Selected;
      Item.Container := No_Container;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
      Item.Value := Empty_Configuration;
   end Reset_Handler;

   function Read_Handler
     (Item : Inventory_Handler) return Inventory_Configuration is
   begin
      if Item.Depth /= 0
        or else not Item.Root_Seen
        or else not Item.Destination_Seen
        or else not Item.Is_Enabled_Seen
        or else not Item.ID_Seen
        or else not Item.Versions_Seen
        or else not Item.Schedule_Seen
        or else Item.Container /= No_Container
      then
         raise Malformed_Inventory with "incomplete inventory document";
      end if;
      return Item.Value;
   end Read_Handler;

   function Empty_Page return Inventory_Configuration_Page is
     ((Has_Is_Truncated        => False,
       Is_Truncated            => False,
       Continuation_Token      => Empty_String,
       Next_Continuation_Token => Empty_String,
       Configurations          => Configuration_Vectors.Empty_Vector));

   procedure Set_Page_Is_Truncated
     (Result : in out Inventory_Configuration_Page; Value : Boolean) is
   begin
      Result.Has_Is_Truncated := True;
      Result.Is_Truncated := Value;
   end Set_Page_Is_Truncated;

   procedure Set_Page_Continuation_Token
     (Result : in out Inventory_Configuration_Page; Value : String) is
   begin
      Result.Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Continuation_Token;

   procedure Set_Page_Next_Continuation_Token
     (Result : in out Inventory_Configuration_Page; Value : String) is
   begin
      Result.Next_Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Next_Continuation_Token;

   procedure Append_Page_Item
     (Result : in out Inventory_Configuration_Page;
      Value  : Inventory_Configuration) is
   begin
      Result.Configurations.Append (Value);
   end Append_Page_Item;

   procedure Reject_Page_Extra_Scalar
     (Result : in out Inventory_Configuration_Page;
      Name   : String;
      Value  : String) is
      pragma Unreferenced (Result, Name, Value);
   begin
      raise Malformed_Inventory with
        "unknown inventory page member";
   end Reject_Page_Extra_Scalar;

   procedure Ignore_Item_Container_Presence
     (Result : in out Inventory_Configuration_Page) is
      pragma Unreferenced (Result);
   begin
      null;
   end Ignore_Item_Container_Presence;

   --  Both element names are fixed by the pinned Botocore operation/output
   --  model. Changing either changes accepted S3 wire documents.
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                   =>
        "ListBucketInventoryConfigurationsOutput",
      Item_Container_Name         => "",
      Item_Name                   => "InventoryConfiguration",
      Allow_Is_Truncated          => True,
      Allow_Continuation_Token    => True,
      Allow_Next_Continuation_Token => True,
      Item_Type                   => Inventory_Configuration,
      Item_Handler_Type           => Inventory_Handler,
      Reset_Item                  => Reset_Handler,
      Read_Item                   => Read_Handler,
      Result_Type                 => Inventory_Configuration_Page,
      Empty_Result                => Empty_Page,
      Set_Is_Truncated            => Set_Page_Is_Truncated,
      Set_Continuation_Token      => Set_Page_Continuation_Token,
      Set_Next_Continuation_Token => Set_Page_Next_Continuation_Token,
      Set_Extra_Scalar            => Reject_Page_Extra_Scalar,
      Set_Item_Container_Present  => Ignore_Item_Container_Presence,
      Append_Item                 => Append_Page_Item);

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Inventory_Configuration
   is
      Handler : aliased Inventory_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      return Read_Handler (Handler);
   exception
      when XML.XML_Error =>
         raise Malformed_Inventory with "malformed inventory XML";
   end Parse;

   function Parse_List
     (Document : String; Limits : XML.Parse_Limits)
      return Inventory_Configuration_Page is
   begin
      return Page_Decoder.Parse (Document, Limits);
   exception
      when Page_Decoder.Malformed_Page =>
         raise Malformed_Inventory with "malformed inventory-list XML";
   end Parse_List;

end Flyology.Object_Storage.S3.Inventory;
