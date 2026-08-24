package body Flyology.Object_Storage.S3.Metadata_Tables is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Configuration_Container, Destination_Container,
      Error_Container);
   type Scalar_Kind is
     (No_Scalar, Status_Scalar, Table_Bucket_ARN_Scalar,
      Table_Name_Scalar, Table_ARN_Scalar, Table_Namespace_Scalar,
      Error_Code_Scalar, Error_Message_Scalar);

   type Metadata_Table_Handler is new XML.Event_Handler with record
      Depth               : Natural := 0;
      Root_Seen           : Boolean := False;
      Configuration_Seen  : Boolean := False;
      Status_Seen         : Boolean := False;
      Error_Seen          : Boolean := False;
      Destination_Seen    : Boolean := False;
      Table_Bucket_Seen   : Boolean := False;
      Table_Name_Seen     : Boolean := False;
      Table_ARN_Seen      : Boolean := False;
      Table_Namespace_Seen : Boolean := False;
      Error_Code_Seen     : Boolean := False;
      Error_Message_Seen  : Boolean := False;
      Namespace           : Namespace_Style := Namespace_Not_Selected;
      Container           : Container_Kind := No_Container;
      Scalar              : Scalar_Kind := No_Scalar;
      Text_Value          : US.Unbounded_String;
      Value               : Metadata_Table_Configuration_Result :=
        (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Metadata_Table_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Metadata_Table_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Metadata_Table_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Metadata_Table_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Metadata_Table with
              "text outside metadata-table scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Metadata_Table_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  Exact established S3 REST/XML namespace.  Changing this external
      --  value changes provider compatibility for every result member.
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
         raise Malformed_Metadata_Table with
           "metadata-table namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Metadata_Table_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   overriding procedure Start_Element
     (Item : in out Metadata_Table_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Metadata_Table with "metadata-table depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen
              or else Local_Name /=
                "GetBucketMetadataTableConfigurationResult"
            then
               raise Malformed_Metadata_Table with
                 "invalid metadata-table result root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name = "MetadataTableConfigurationResult"
              and then not Item.Configuration_Seen
            then
               Item.Configuration_Seen := True;
               Item.Container := Configuration_Container;
            elsif Local_Name = "Status" and then not Item.Status_Seen then
               Item.Status_Seen := True;
               Begin_Scalar (Item, Status_Scalar);
            elsif Local_Name = "Error" and then not Item.Error_Seen then
               Item.Error_Seen := True;
               Item.Container := Error_Container;
               Item.Value.Error.Is_Set := True;
            else
               raise Malformed_Metadata_Table with
                 "unknown or duplicate metadata-table result member";
            end if;
         when 3 =>
            if Item.Container = Configuration_Container
              and then Local_Name = "S3TablesDestinationResult"
              and then not Item.Destination_Seen
            then
               Item.Destination_Seen := True;
               Item.Container := Destination_Container;
            elsif Item.Container = Error_Container
              and then Local_Name = "ErrorCode"
              and then not Item.Error_Code_Seen
            then
               Item.Error_Code_Seen := True;
               Begin_Scalar (Item, Error_Code_Scalar);
            elsif Item.Container = Error_Container
              and then Local_Name = "ErrorMessage"
              and then not Item.Error_Message_Seen
            then
               Item.Error_Message_Seen := True;
               Begin_Scalar (Item, Error_Message_Scalar);
            else
               raise Malformed_Metadata_Table with
                 "unknown or duplicate nested metadata-table member";
            end if;
         when 4 =>
            if Item.Container /= Destination_Container then
               raise Malformed_Metadata_Table with
                 "metadata-table destination member outside destination";
            elsif Local_Name = "TableBucketArn"
              and then not Item.Table_Bucket_Seen
            then
               Item.Table_Bucket_Seen := True;
               Begin_Scalar (Item, Table_Bucket_ARN_Scalar);
            elsif Local_Name = "TableName" and then not Item.Table_Name_Seen
            then
               Item.Table_Name_Seen := True;
               Begin_Scalar (Item, Table_Name_Scalar);
            elsif Local_Name = "TableArn" and then not Item.Table_ARN_Seen
            then
               Item.Table_ARN_Seen := True;
               Begin_Scalar (Item, Table_ARN_Scalar);
            elsif Local_Name = "TableNamespace"
              and then not Item.Table_Namespace_Seen
            then
               Item.Table_Namespace_Seen := True;
               Begin_Scalar (Item, Table_Namespace_Scalar);
            else
               raise Malformed_Metadata_Table with
                 "unknown or duplicate metadata-table destination member";
            end if;
         when others =>
            raise Malformed_Metadata_Table with "nested metadata-table member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Metadata_Table_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar
        and then Item.Depth in 2 .. 4
      then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 3 then
         Require_Whitespace (Value);
      else
         raise Malformed_Metadata_Table with
           "metadata-table text outside modeled member";
      end if;
   end Text;

   procedure Store_Scalar (Item : in out Metadata_Table_Handler) is
   begin
      case Item.Scalar is
         when Status_Scalar =>
            Item.Value.Status := Item.Text_Value;
         when Table_Bucket_ARN_Scalar =>
            Item.Value.Destination.Table_Bucket_ARN := Item.Text_Value;
         when Table_Name_Scalar =>
            Item.Value.Destination.Table_Name := Item.Text_Value;
         when Table_ARN_Scalar =>
            Item.Value.Destination.Table_ARN := Item.Text_Value;
         when Table_Namespace_Scalar =>
            Item.Value.Destination.Table_Namespace := Item.Text_Value;
         when Error_Code_Scalar =>
            Item.Value.Error.Code :=
              (Is_Set => True, Value => Item.Text_Value);
         when Error_Message_Scalar =>
            Item.Value.Error.Message :=
              (Is_Set => True, Value => Item.Text_Value);
         when No_Scalar =>
            raise Malformed_Metadata_Table with
              "metadata-table close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   overriding procedure End_Element
     (Item : in out Metadata_Table_Handler; Local_Name : String) is
   begin
      case Item.Depth is
         when 4 =>
            if (Item.Scalar = Table_Bucket_ARN_Scalar
                and then Local_Name /= "TableBucketArn")
              or else (Item.Scalar = Table_Name_Scalar
                       and then Local_Name /= "TableName")
              or else (Item.Scalar = Table_ARN_Scalar
                       and then Local_Name /= "TableArn")
              or else (Item.Scalar = Table_Namespace_Scalar
                       and then Local_Name /= "TableNamespace")
              or else Item.Scalar not in Table_Bucket_ARN_Scalar ..
                Table_Namespace_Scalar
            then
               raise Malformed_Metadata_Table with
                 "mismatched metadata-table destination close";
            end if;
            Store_Scalar (Item);
            Item.Depth := 3;
         when 3 =>
            if Item.Scalar in Error_Code_Scalar .. Error_Message_Scalar then
               if (Item.Scalar = Error_Code_Scalar
                   and then Local_Name /= "ErrorCode")
                 or else (Item.Scalar = Error_Message_Scalar
                          and then Local_Name /= "ErrorMessage")
               then
                  raise Malformed_Metadata_Table with
                    "mismatched metadata-table error close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Destination_Container then
               if Local_Name /= "S3TablesDestinationResult"
                 or else not Item.Table_Bucket_Seen
                 or else not Item.Table_Name_Seen
                 or else not Item.Table_ARN_Seen
                 or else not Item.Table_Namespace_Seen
               then
                  raise Malformed_Metadata_Table with
                    "incomplete metadata-table destination";
               end if;
               Item.Container := Configuration_Container;
            else
               raise Malformed_Metadata_Table with
                 "incomplete nested metadata-table member";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Item.Scalar = Status_Scalar then
               if Local_Name /= "Status" then
                  raise Malformed_Metadata_Table with
                    "mismatched metadata-table status close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Configuration_Container then
               if Local_Name /= "MetadataTableConfigurationResult"
                 or else not Item.Destination_Seen
               then
                  raise Malformed_Metadata_Table with
                    "incomplete metadata-table configuration result";
               end if;
               Item.Container := No_Container;
            elsif Item.Container = Error_Container then
               if Local_Name /= "Error" then
                  raise Malformed_Metadata_Table with
                    "mismatched metadata-table error structure";
               end if;
               Item.Container := No_Container;
            else
               raise Malformed_Metadata_Table with
                 "result member close without open member";
            end if;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "GetBucketMetadataTableConfigurationResult"
              or else not Item.Configuration_Seen
              or else not Item.Status_Seen
            then
               raise Malformed_Metadata_Table with
                 "incomplete metadata-table result";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Metadata_Table with
              "invalid metadata-table closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Metadata_Table_Configuration_Result
   is
      Handler : aliased Metadata_Table_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Metadata_Table with
           "incomplete metadata-table document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Metadata_Table with "malformed metadata-table XML";
   end Parse;

   function Serialize_Create
     (Value  : S3_Tables_Destination;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Result : US.Unbounded_String;
      Table_Bucket_ARN : constant String :=
        US.To_String (Value.Table_Bucket_ARN);
      Table_Name : constant String := US.To_String (Value.Table_Name);
      --  Pinned shape graph: MetadataTableConfiguration contains one
      --  S3TablesDestination, which contains the two required scalar members.
      --  This externally established structure is four elements and three
      --  levels deep; changing either value changes accepted caller budgets.
      Required_Depth    : constant Positive := 3;
      Required_Elements : constant Positive := 4;
      --  Exact REST/XML namespace, root, and member spellings from the pinned
      --  CreateBucketMetadataTableConfiguration model.  These strings are a
      --  provider-compatibility contract rather than locally selected policy.
      Prefix : constant String :=
        "<MetadataTableConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/""><S3TablesDestination><TableBucketArn>";
      Between : constant String :=
        "</TableBucketArn><TableName>";
      Suffix : constant String :=
        "</TableName></S3TablesDestination></MetadataTableConfiguration>";

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Metadata_Table with
              "metadata-table document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;

      procedure Append_Escaped_Bounded (Text : String) is
      begin
         for Item of Text loop
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise Malformed_Metadata_Table with
                 "metadata-table text contains an invalid XML character";
            elsif Item = '&' then
               Append_Bounded ("&amp;");
            elsif Item = '<' then
               Append_Bounded ("&lt;");
            elsif Item = '>' then
               Append_Bounded ("&gt;");
            else
               Append_Bounded (String'(1 => Item));
            end if;
         end loop;
      end Append_Escaped_Bounded;
   begin
      if Limits.Maximum_Depth < Required_Depth
        or else Limits.Maximum_Elements < Required_Elements
      then
         raise Malformed_Metadata_Table with
           "metadata-table structure exceeds caller limit";
      elsif Table_Bucket_ARN'Length > Limits.Maximum_Text_Bytes
        or else Table_Name'Length >
          Limits.Maximum_Text_Bytes - Table_Bucket_ARN'Length
      then
         raise Malformed_Metadata_Table with
           "metadata-table text exceeds caller limit";
      end if;

      Append_Bounded (Prefix);
      Append_Escaped_Bounded (Table_Bucket_ARN);
      Append_Bounded (Between);
      Append_Escaped_Bounded (Table_Name);
      Append_Bounded (Suffix);
      return US.To_String (Result);
   end Serialize_Create;

end Flyology.Object_Storage.S3.Metadata_Tables;
