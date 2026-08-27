with Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;

package body Flyology.Object_Storage.S3.Metrics is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Filter_Container, Direct_Tag_Container,
      And_Container, And_Tag_Container);
   type Scalar_Kind is
     (No_Scalar, ID_Scalar, Filter_Prefix_Scalar,
      Filter_Access_Point_Scalar, Direct_Tag_Key_Scalar,
      Direct_Tag_Value_Scalar, And_Prefix_Scalar,
      And_Access_Point_Scalar, And_Tag_Key_Scalar,
      And_Tag_Value_Scalar);

   type Metrics_Handler is new XML.Event_Handler with record
      Depth                    : Natural := 0;
      Root_Seen                : Boolean := False;
      ID_Seen                  : Boolean := False;
      Filter_Seen              : Boolean := False;
      Filter_Prefix_Seen       : Boolean := False;
      Filter_Tag_Seen          : Boolean := False;
      Filter_Access_Point_Seen : Boolean := False;
      And_Seen                 : Boolean := False;
      And_Prefix_Seen          : Boolean := False;
      And_Access_Point_Seen    : Boolean := False;
      Tag_Key_Seen             : Boolean := False;
      Tag_Value_Seen           : Boolean := False;
      Namespace                : Namespace_Style := Namespace_Not_Selected;
      Container                : Container_Kind := No_Container;
      Scalar                   : Scalar_Kind := No_Scalar;
      Text_Value               : US.Unbounded_String;
      Current_Tag              : Metrics_Tag :=
        (Key => US.Null_Unbounded_String,
         Value => US.Null_Unbounded_String);
      Value                    : Metrics_Configuration :=
        (ID     => US.Null_Unbounded_String,
         Filter =>
           (Is_Set           => False,
            Prefix           =>
              (Is_Set => False, Value => US.Null_Unbounded_String),
            Tag              =>
              (Is_Set => False,
               Value =>
                 (Key => US.Null_Unbounded_String,
                  Value => US.Null_Unbounded_String)),
            Access_Point_ARN =>
              (Is_Set => False, Value => US.Null_Unbounded_String),
            And_Predicates   =>
              (Is_Set           => False,
               Prefix           =>
                 (Is_Set => False, Value => US.Null_Unbounded_String),
               Tags             => Tag_Vectors.Empty_Vector,
               Access_Point_ARN =>
                 (Is_Set => False, Value => US.Null_Unbounded_String))));
   end record;

   overriding procedure Start_Element
     (Item : in out Metrics_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Metrics_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Metrics_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Metrics_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Metrics with "text outside metrics scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Metrics_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  The S3 REST/XML namespace is the established provider wire
      --  authority; accepting another URI would change compatibility.
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
         raise Malformed_Metrics with
           "metrics namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Metrics_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Begin_Tag
     (Item : in out Metrics_Handler; Kind : Container_Kind) is
   begin
      Item.Container := Kind;
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
      Item.Current_Tag :=
        (Key => US.Null_Unbounded_String,
         Value => US.Null_Unbounded_String);
   end Begin_Tag;

   overriding procedure Start_Element
     (Item : in out Metrics_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Metrics with "metrics depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "MetricsConfiguration" then
               raise Malformed_Metrics with "invalid metrics root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name = "Id" and then not Item.ID_Seen then
               Item.ID_Seen := True;
               Begin_Scalar (Item, ID_Scalar);
            elsif Local_Name = "Filter" and then not Item.Filter_Seen then
               Item.Filter_Seen := True;
               Item.Container := Filter_Container;
               Item.Value.Filter.Is_Set := True;
            else
               raise Malformed_Metrics with
                 "unknown or duplicate metrics member";
            end if;
         when 3 =>
            if Item.Container /= Filter_Container then
               raise Malformed_Metrics with "metrics member outside filter";
            elsif Local_Name = "Prefix"
              and then not Item.Filter_Prefix_Seen
            then
               Item.Filter_Prefix_Seen := True;
               Begin_Scalar (Item, Filter_Prefix_Scalar);
            elsif Local_Name = "Tag" and then not Item.Filter_Tag_Seen then
               Item.Filter_Tag_Seen := True;
               Item.Value.Filter.Tag.Is_Set := True;
               Begin_Tag (Item, Direct_Tag_Container);
            elsif Local_Name = "AccessPointArn"
              and then not Item.Filter_Access_Point_Seen
            then
               Item.Filter_Access_Point_Seen := True;
               Begin_Scalar (Item, Filter_Access_Point_Scalar);
            elsif Local_Name = "And" and then not Item.And_Seen then
               Item.And_Seen := True;
               Item.Container := And_Container;
               Item.Value.Filter.And_Predicates.Is_Set := True;
            else
               raise Malformed_Metrics with
                 "unknown or duplicate metrics filter member";
            end if;
         when 4 =>
            if Item.Container = Direct_Tag_Container then
               if Local_Name = "Key" and then not Item.Tag_Key_Seen then
                  Item.Tag_Key_Seen := True;
                  Begin_Scalar (Item, Direct_Tag_Key_Scalar);
               elsif Local_Name = "Value"
                 and then not Item.Tag_Value_Seen
               then
                  Item.Tag_Value_Seen := True;
                  Begin_Scalar (Item, Direct_Tag_Value_Scalar);
               else
                  raise Malformed_Metrics with
                    "unknown or duplicate direct metrics tag member";
               end if;
            elsif Item.Container = And_Container then
               if Local_Name = "Prefix" and then not Item.And_Prefix_Seen then
                  Item.And_Prefix_Seen := True;
                  Begin_Scalar (Item, And_Prefix_Scalar);
               elsif Local_Name = "AccessPointArn"
                 and then not Item.And_Access_Point_Seen
               then
                  Item.And_Access_Point_Seen := True;
                  Begin_Scalar (Item, And_Access_Point_Scalar);
               elsif Local_Name = "Tag" then
                  Begin_Tag (Item, And_Tag_Container);
               else
                  raise Malformed_Metrics with
                    "unknown or duplicate metrics And member";
               end if;
            else
               raise Malformed_Metrics with "invalid metrics nesting";
            end if;
         when 5 =>
            if Item.Container /= And_Tag_Container then
               raise Malformed_Metrics with "metrics nesting exceeds model";
            elsif Local_Name = "Key" and then not Item.Tag_Key_Seen then
               Item.Tag_Key_Seen := True;
               Begin_Scalar (Item, And_Tag_Key_Scalar);
            elsif Local_Name = "Value" and then not Item.Tag_Value_Seen then
               Item.Tag_Value_Seen := True;
               Begin_Scalar (Item, And_Tag_Value_Scalar);
            else
               raise Malformed_Metrics with
                 "unknown or duplicate And tag member";
            end if;
         when others =>
            raise Malformed_Metrics with "metrics nesting exceeds model";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Metrics_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 4 then
         Require_Whitespace (Value);
      else
         raise Malformed_Metrics with "metrics text outside modeled member";
      end if;
   end Text;

   procedure Store_Scalar (Item : in out Metrics_Handler) is
   begin
      case Item.Scalar is
         when ID_Scalar =>
            Item.Value.ID := Item.Text_Value;
         when Filter_Prefix_Scalar =>
            Item.Value.Filter.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Filter_Access_Point_Scalar =>
            Item.Value.Filter.Access_Point_ARN :=
              (Is_Set => True, Value => Item.Text_Value);
         when And_Prefix_Scalar =>
            Item.Value.Filter.And_Predicates.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when And_Access_Point_Scalar =>
            Item.Value.Filter.And_Predicates.Access_Point_ARN :=
              (Is_Set => True, Value => Item.Text_Value);
         when Direct_Tag_Key_Scalar | And_Tag_Key_Scalar =>
            if US.Length (Item.Text_Value) = 0 then
               raise Malformed_Metrics with "empty metrics tag key";
            end if;
            Item.Current_Tag.Key := Item.Text_Value;
         when Direct_Tag_Value_Scalar | And_Tag_Value_Scalar =>
            Item.Current_Tag.Value := Item.Text_Value;
         when No_Scalar =>
            raise Malformed_Metrics with "metrics close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   procedure Finish_Tag (Item : in out Metrics_Handler) is
   begin
      if not Item.Tag_Key_Seen or else not Item.Tag_Value_Seen then
         raise Malformed_Metrics with "incomplete metrics tag";
      elsif Item.Container = Direct_Tag_Container then
         Item.Value.Filter.Tag.Value := Item.Current_Tag;
         Item.Container := Filter_Container;
      elsif Item.Container = And_Tag_Container then
         Item.Value.Filter.And_Predicates.Tags.Append (Item.Current_Tag);
         Item.Container := And_Container;
      else
         raise Malformed_Metrics with "metrics tag outside filter";
      end if;
   end Finish_Tag;

   overriding procedure End_Element
     (Item : in out Metrics_Handler; Local_Name : String) is
   begin
      case Item.Depth is
         when 5 =>
            if (Item.Scalar = And_Tag_Key_Scalar
                and then Local_Name /= "Key")
              or else (Item.Scalar = And_Tag_Value_Scalar
                       and then Local_Name /= "Value")
            then
               raise Malformed_Metrics with "mismatched And tag close";
            end if;
            Store_Scalar (Item);
            Item.Depth := 4;
         when 4 =>
            if Item.Scalar /= No_Scalar then
               if (Item.Scalar = Direct_Tag_Key_Scalar
                   and then Local_Name /= "Key")
                 or else (Item.Scalar = Direct_Tag_Value_Scalar
                          and then Local_Name /= "Value")
                 or else (Item.Scalar = And_Prefix_Scalar
                          and then Local_Name /= "Prefix")
                 or else (Item.Scalar = And_Access_Point_Scalar
                          and then Local_Name /= "AccessPointArn")
               then
                  raise Malformed_Metrics with
                    "mismatched metrics scalar close";
               end if;
               Store_Scalar (Item);
            elsif Local_Name = "Tag" then
               Finish_Tag (Item);
            else
               raise Malformed_Metrics with "invalid metrics container close";
            end if;
            Item.Depth := 3;
         when 3 =>
            if Item.Scalar /= No_Scalar then
               if (Item.Scalar = Filter_Prefix_Scalar
                   and then Local_Name /= "Prefix")
                 or else (Item.Scalar = Filter_Access_Point_Scalar
                          and then Local_Name /= "AccessPointArn")
               then
                  raise Malformed_Metrics with
                    "mismatched filter scalar close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Direct_Tag_Container
              and then Local_Name = "Tag"
            then
               Finish_Tag (Item);
            elsif Item.Container = And_Container
              and then Local_Name = "And"
            then
               Item.Container := Filter_Container;
            else
               raise Malformed_Metrics with "invalid metrics filter close";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Item.Scalar = ID_Scalar and then Local_Name = "Id" then
               Store_Scalar (Item);
            elsif Item.Container = Filter_Container
              and then Local_Name = "Filter"
            then
               Item.Container := No_Container;
            else
               raise Malformed_Metrics with "invalid metrics member close";
            end if;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "MetricsConfiguration"
              or else not Item.ID_Seen
            then
               raise Malformed_Metrics with "incomplete metrics configuration";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Metrics with "invalid metrics closing element";
      end case;
   end End_Element;

   procedure Reset_Handler (Item : in out Metrics_Handler) is
   begin
      Item.Depth := 0;
      Item.Root_Seen := False;
      Item.ID_Seen := False;
      Item.Filter_Seen := False;
      Item.Filter_Prefix_Seen := False;
      Item.Filter_Tag_Seen := False;
      Item.Filter_Access_Point_Seen := False;
      Item.And_Seen := False;
      Item.And_Prefix_Seen := False;
      Item.And_Access_Point_Seen := False;
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
      Item.Namespace := Namespace_Not_Selected;
      Item.Container := No_Container;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
      Item.Current_Tag :=
        (Key => US.Null_Unbounded_String,
         Value => US.Null_Unbounded_String);
      Item.Value :=
        (ID     => US.Null_Unbounded_String,
         Filter =>
           (Is_Set           => False,
            Prefix           =>
              (Is_Set => False, Value => US.Null_Unbounded_String),
            Tag              =>
              (Is_Set => False,
               Value =>
                 (Key => US.Null_Unbounded_String,
                  Value => US.Null_Unbounded_String)),
            Access_Point_ARN =>
              (Is_Set => False, Value => US.Null_Unbounded_String),
            And_Predicates   =>
              (Is_Set           => False,
               Prefix           =>
                 (Is_Set => False, Value => US.Null_Unbounded_String),
               Tags             => Tag_Vectors.Empty_Vector,
               Access_Point_ARN =>
                 (Is_Set => False, Value => US.Null_Unbounded_String))));
   end Reset_Handler;

   function Read_Handler
     (Item : Metrics_Handler) return Metrics_Configuration is
   begin
      if Item.Depth /= 0 or else not Item.Root_Seen or else not Item.ID_Seen
      then
         raise Malformed_Metrics with "incomplete metrics document";
      end if;
      return Item.Value;
   end Read_Handler;

   function Empty_Page return Metrics_Configuration_Page is
     ((Has_Is_Truncated        => False,
       Is_Truncated            => False,
       Continuation_Token      =>
         (Is_Set => False, Value => US.Null_Unbounded_String),
       Next_Continuation_Token =>
         (Is_Set => False, Value => US.Null_Unbounded_String),
       Configurations          => Configuration_Vectors.Empty_Vector));

   procedure Set_Page_Is_Truncated
     (Result : in out Metrics_Configuration_Page; Value : Boolean) is
   begin
      Result.Has_Is_Truncated := True;
      Result.Is_Truncated := Value;
   end Set_Page_Is_Truncated;

   procedure Set_Page_Continuation_Token
     (Result : in out Metrics_Configuration_Page; Value : String) is
   begin
      Result.Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Continuation_Token;

   procedure Set_Page_Next_Continuation_Token
     (Result : in out Metrics_Configuration_Page; Value : String) is
   begin
      Result.Next_Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Next_Continuation_Token;

   procedure Append_Page_Item
     (Result : in out Metrics_Configuration_Page;
      Value  : Metrics_Configuration) is
   begin
      Result.Configurations.Append (Value);
   end Append_Page_Item;

   procedure Reject_Page_Extra_Scalar
     (Result : in out Metrics_Configuration_Page;
      Name   : String;
      Value  : String) is
      pragma Unreferenced (Result, Name, Value);
   begin
      raise Malformed_Metrics with "unknown metrics page member";
   end Reject_Page_Extra_Scalar;

   procedure Ignore_Item_Container_Presence
     (Result : in out Metrics_Configuration_Page) is
      pragma Unreferenced (Result);
   begin
      null;
   end Ignore_Item_Container_Presence;

   --  Both element names are fixed by the pinned Botocore operation/output
   --  model. Changing either changes accepted S3 wire documents.
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                  =>
        "ListBucketMetricsConfigurationsOutput",
      Item_Container_Name        => "",
      Item_Name                  => "MetricsConfiguration",
      Allow_Is_Truncated         => True,
      Allow_Continuation_Token   => True,
      Allow_Next_Continuation_Token => True,
      Item_Type                  => Metrics_Configuration,
      Item_Handler_Type          => Metrics_Handler,
      Reset_Item                 => Reset_Handler,
      Read_Item                  => Read_Handler,
      Result_Type                => Metrics_Configuration_Page,
      Empty_Result               => Empty_Page,
      Set_Is_Truncated           => Set_Page_Is_Truncated,
      Set_Continuation_Token     => Set_Page_Continuation_Token,
      Set_Next_Continuation_Token => Set_Page_Next_Continuation_Token,
      Set_Extra_Scalar           => Reject_Page_Extra_Scalar,
      Set_Item_Container_Present => Ignore_Item_Container_Presence,
      Append_Item                => Append_Page_Item);

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Metrics_Configuration
   is
      Handler : aliased Metrics_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      return Read_Handler (Handler);
   exception
      when XML.XML_Error =>
         raise Malformed_Metrics with "malformed metrics XML";
   end Parse;

   function Parse_List
     (Document : String; Limits : XML.Parse_Limits)
      return Metrics_Configuration_Page is
   begin
      return Page_Decoder.Parse (Document, Limits);
   exception
      when Page_Decoder.Malformed_Page =>
         raise Malformed_Metrics with "malformed metrics-list XML";
   end Parse_List;

end Flyology.Object_Storage.S3.Metrics;
