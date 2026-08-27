with Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;

package body Flyology.Object_Storage.S3.Intelligent_Tiering is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Root_Container, Filter_Container,
      Direct_Tag_Container, And_Container, And_Tag_Container,
      Tiering_Container);
   type Scalar_Kind is
     (No_Scalar, ID_Scalar, Filter_Prefix_Scalar,
      Direct_Tag_Key_Scalar, Direct_Tag_Value_Scalar,
      And_Prefix_Scalar, And_Tag_Key_Scalar, And_Tag_Value_Scalar,
      Status_Scalar, Days_Scalar, Access_Tier_Scalar);

   function Empty_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Tag return Intelligent_Tiering_Tag is
     ((Key => US.Null_Unbounded_String,
       Value => US.Null_Unbounded_String));

   function Empty_Configuration
      return Intelligent_Tiering_Configuration is
     --  Enabled and Archive_Access are neutral construction values from the
     --  pinned enum domains. Seen flags prevent absent members from using
     --  them.
     ((ID     => US.Null_Unbounded_String,
       Filter =>
         (Is_Set         => False,
          Prefix         => Empty_String,
          Tag            => (Is_Set => False, Value => Empty_Tag),
          And_Predicates =>
            (Is_Set => False,
             Prefix => Empty_String,
             Tags   => Tag_Vectors.Empty_Vector)),
       Status   => Enabled,
       Tierings => Tiering_Vectors.Empty_Vector));

   type Intelligent_Tiering_Handler is new XML.Event_Handler with record
      Depth                   : Natural := 0;
      Root_Seen               : Boolean := False;
      ID_Seen                 : Boolean := False;
      Filter_Seen             : Boolean := False;
      Filter_Prefix_Seen      : Boolean := False;
      Filter_Tag_Seen         : Boolean := False;
      And_Seen                : Boolean := False;
      And_Prefix_Seen         : Boolean := False;
      Status_Seen             : Boolean := False;
      Tiering_Days_Seen       : Boolean := False;
      Tiering_Access_Seen     : Boolean := False;
      Tag_Key_Seen            : Boolean := False;
      Tag_Value_Seen          : Boolean := False;
      Namespace               : Namespace_Style := Namespace_Not_Selected;
      Container               : Container_Kind := No_Container;
      Scalar                  : Scalar_Kind := No_Scalar;
      Text_Value              : US.Unbounded_String;
      Current_Tag             : Intelligent_Tiering_Tag := Empty_Tag;
      Current_Tiering_Days    : US.Unbounded_String;
      Current_Tiering_Access  : Access_Tier_Kind := Archive_Access;
      Value                   : Intelligent_Tiering_Configuration :=
        Empty_Configuration;
   end record;

   overriding procedure Start_Element
     (Item : in out Intelligent_Tiering_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Intelligent_Tiering_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Intelligent_Tiering_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Intelligent_Tiering_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Intelligent_Tiering with
              "text outside Intelligent-Tiering scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Intelligent_Tiering_Handler;
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
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Intelligent_Tiering_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Begin_Tag
     (Item : in out Intelligent_Tiering_Handler; Kind : Container_Kind) is
   begin
      Item.Container := Kind;
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
      Item.Current_Tag := Empty_Tag;
   end Begin_Tag;

   procedure Begin_Tiering (Item : in out Intelligent_Tiering_Handler) is
   begin
      Item.Container := Tiering_Container;
      Item.Tiering_Days_Seen := False;
      Item.Tiering_Access_Seen := False;
      Item.Current_Tiering_Days := US.Null_Unbounded_String;
      Item.Current_Tiering_Access := Archive_Access;
   end Begin_Tiering;

   overriding procedure Start_Element
     (Item : in out Intelligent_Tiering_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering depth overflow";
      elsif Item.Scalar /= No_Scalar then
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering scalar contains element";
      end if;
      Item.Depth := Item.Depth + 1;

      if Item.Depth = 1 then
         if Item.Root_Seen
           or else Local_Name /= "IntelligentTieringConfiguration"
         then
            raise Malformed_Intelligent_Tiering with
              "invalid Intelligent-Tiering root";
         end if;
         Item.Root_Seen := True;
         Item.Container := Root_Container;
         return;
      end if;

      case Item.Container is
         when Root_Container =>
            if Local_Name = "Id" and then not Item.ID_Seen then
               Item.ID_Seen := True;
               Begin_Scalar (Item, ID_Scalar);
            elsif Local_Name = "Filter" and then not Item.Filter_Seen then
               Item.Filter_Seen := True;
               Item.Value.Filter.Is_Set := True;
               Item.Container := Filter_Container;
            elsif Local_Name = "Status" and then not Item.Status_Seen then
               Item.Status_Seen := True;
               Begin_Scalar (Item, Status_Scalar);
            elsif Local_Name = "Tiering" then
               Begin_Tiering (Item);
            else
               raise Malformed_Intelligent_Tiering with
                 "unknown or duplicate Intelligent-Tiering member";
            end if;

         when Filter_Container =>
            if Local_Name = "Prefix"
              and then not Item.Filter_Prefix_Seen
            then
               Item.Filter_Prefix_Seen := True;
               Begin_Scalar (Item, Filter_Prefix_Scalar);
            elsif Local_Name = "Tag" and then not Item.Filter_Tag_Seen then
               Item.Filter_Tag_Seen := True;
               Item.Value.Filter.Tag.Is_Set := True;
               Begin_Tag (Item, Direct_Tag_Container);
            elsif Local_Name = "And" and then not Item.And_Seen then
               Item.And_Seen := True;
               Item.Value.Filter.And_Predicates.Is_Set := True;
               Item.Container := And_Container;
            else
               raise Malformed_Intelligent_Tiering with
                 "unknown or duplicate Intelligent-Tiering filter member";
            end if;

         when Direct_Tag_Container | And_Tag_Container =>
            if Local_Name = "Key" and then not Item.Tag_Key_Seen then
               Item.Tag_Key_Seen := True;
               Begin_Scalar
                 (Item,
                  (if Item.Container = Direct_Tag_Container
                   then Direct_Tag_Key_Scalar
                   else And_Tag_Key_Scalar));
            elsif Local_Name = "Value" and then not Item.Tag_Value_Seen then
               Item.Tag_Value_Seen := True;
               Begin_Scalar
                 (Item,
                  (if Item.Container = Direct_Tag_Container
                   then Direct_Tag_Value_Scalar
                   else And_Tag_Value_Scalar));
            else
               raise Malformed_Intelligent_Tiering with
                 "unknown or duplicate Intelligent-Tiering tag member";
            end if;

         when And_Container =>
            if Local_Name = "Prefix" and then not Item.And_Prefix_Seen then
               Item.And_Prefix_Seen := True;
               Begin_Scalar (Item, And_Prefix_Scalar);
            elsif Local_Name = "Tag" then
               Begin_Tag (Item, And_Tag_Container);
            else
               raise Malformed_Intelligent_Tiering with
                 "unknown or duplicate Intelligent-Tiering And member";
            end if;

         when Tiering_Container =>
            if Local_Name = "Days" and then not Item.Tiering_Days_Seen then
               Item.Tiering_Days_Seen := True;
               Begin_Scalar (Item, Days_Scalar);
            elsif Local_Name = "AccessTier"
              and then not Item.Tiering_Access_Seen
            then
               Item.Tiering_Access_Seen := True;
               Begin_Scalar (Item, Access_Tier_Scalar);
            else
               raise Malformed_Intelligent_Tiering with
                 "unknown or duplicate Intelligent-Tiering transition member";
            end if;

         when No_Container =>
            raise Malformed_Intelligent_Tiering with
              "Intelligent-Tiering element outside root";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Intelligent_Tiering_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth > 0 then
         Require_Whitespace (Value);
      else
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering text outside document";
      end if;
   end Text;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when ID_Scalar => "Id",
         when Filter_Prefix_Scalar | And_Prefix_Scalar => "Prefix",
         when Direct_Tag_Key_Scalar | And_Tag_Key_Scalar => "Key",
         when Direct_Tag_Value_Scalar | And_Tag_Value_Scalar => "Value",
         when Status_Scalar => "Status",
         when Days_Scalar => "Days",
         when Access_Tier_Scalar => "AccessTier",
         when No_Scalar => "");

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

   procedure Store_Scalar
     (Item : in out Intelligent_Tiering_Handler) is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when ID_Scalar =>
            Item.Value.ID := Item.Text_Value;
         when Filter_Prefix_Scalar =>
            Item.Value.Filter.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when And_Prefix_Scalar =>
            Item.Value.Filter.And_Predicates.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Direct_Tag_Key_Scalar | And_Tag_Key_Scalar =>
            if US.Length (Item.Text_Value) = 0 then
               raise Malformed_Intelligent_Tiering with
                 "empty Intelligent-Tiering tag key";
            end if;
            Item.Current_Tag.Key := Item.Text_Value;
         when Direct_Tag_Value_Scalar | And_Tag_Value_Scalar =>
            Item.Current_Tag.Value := Item.Text_Value;
         when Status_Scalar =>
            if Value = "Enabled" then
               Item.Value.Status := Enabled;
            elsif Value = "Disabled" then
               Item.Value.Status := Disabled;
            else
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering status";
            end if;
         when Days_Scalar =>
            if not Valid_Integer_Text (Value) then
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering days";
            end if;
            Item.Current_Tiering_Days := Item.Text_Value;
         when Access_Tier_Scalar =>
            if Value = "ARCHIVE_ACCESS" then
               Item.Current_Tiering_Access := Archive_Access;
            elsif Value = "DEEP_ARCHIVE_ACCESS" then
               Item.Current_Tiering_Access := Deep_Archive_Access;
            else
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering access tier";
            end if;
         when No_Scalar =>
            raise Malformed_Intelligent_Tiering with
              "Intelligent-Tiering close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   procedure Finish_Tag (Item : in out Intelligent_Tiering_Handler) is
   begin
      if not Item.Tag_Key_Seen or else not Item.Tag_Value_Seen then
         raise Malformed_Intelligent_Tiering with
           "incomplete Intelligent-Tiering tag";
      elsif Item.Container = Direct_Tag_Container then
         Item.Value.Filter.Tag.Value := Item.Current_Tag;
         Item.Container := Filter_Container;
      elsif Item.Container = And_Tag_Container then
         Item.Value.Filter.And_Predicates.Tags.Append (Item.Current_Tag);
         Item.Container := And_Container;
      else
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering tag outside filter";
      end if;
   end Finish_Tag;

   overriding procedure End_Element
     (Item : in out Intelligent_Tiering_Handler; Local_Name : String) is
   begin
      if Item.Depth = 0 then
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering close outside document";
      elsif Item.Scalar /= No_Scalar then
         if Local_Name /= Scalar_Name (Item.Scalar) then
            raise Malformed_Intelligent_Tiering with
              "mismatched Intelligent-Tiering scalar close";
         end if;
         Store_Scalar (Item);
         Item.Depth := Item.Depth - 1;
         return;
      end if;

      case Item.Container is
         when Direct_Tag_Container | And_Tag_Container =>
            if Local_Name /= "Tag" then
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering tag close";
            end if;
            Finish_Tag (Item);
         when And_Container =>
            if Local_Name /= "And" then
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering And close";
            end if;
            Item.Container := Filter_Container;
         when Filter_Container =>
            if Local_Name /= "Filter" then
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering filter close";
            end if;
            Item.Container := Root_Container;
         when Tiering_Container =>
            if Local_Name /= "Tiering"
              or else not Item.Tiering_Days_Seen
              or else not Item.Tiering_Access_Seen
            then
               raise Malformed_Intelligent_Tiering with
                 "incomplete Intelligent-Tiering transition";
            end if;
            Item.Value.Tierings.Append
              (Tiering'
                 (Days        => Item.Current_Tiering_Days,
                  Access_Tier => Item.Current_Tiering_Access));
            Item.Container := Root_Container;
         when Root_Container =>
            if Local_Name /= "IntelligentTieringConfiguration"
              or else not Item.ID_Seen
              or else not Item.Status_Seen
              or else Item.Value.Tierings.Is_Empty
            then
               raise Malformed_Intelligent_Tiering with
                 "incomplete Intelligent-Tiering configuration";
            end if;
            Item.Container := No_Container;
         when No_Container =>
            raise Malformed_Intelligent_Tiering with
              "Intelligent-Tiering container close outside document";
      end case;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Reset_Handler (Item : in out Intelligent_Tiering_Handler) is
   begin
      Item.Depth := 0;
      Item.Root_Seen := False;
      Item.ID_Seen := False;
      Item.Filter_Seen := False;
      Item.Filter_Prefix_Seen := False;
      Item.Filter_Tag_Seen := False;
      Item.And_Seen := False;
      Item.And_Prefix_Seen := False;
      Item.Status_Seen := False;
      Item.Tiering_Days_Seen := False;
      Item.Tiering_Access_Seen := False;
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
      Item.Namespace := Namespace_Not_Selected;
      Item.Container := No_Container;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
      Item.Current_Tag := Empty_Tag;
      Item.Current_Tiering_Days := US.Null_Unbounded_String;
      Item.Current_Tiering_Access := Archive_Access;
      Item.Value := Empty_Configuration;
   end Reset_Handler;

   function Read_Handler
     (Item : Intelligent_Tiering_Handler)
      return Intelligent_Tiering_Configuration is
   begin
      if Item.Depth /= 0
        or else not Item.Root_Seen
        or else not Item.ID_Seen
        or else not Item.Status_Seen
        or else Item.Value.Tierings.Is_Empty
        or else Item.Container /= No_Container
      then
         raise Malformed_Intelligent_Tiering with
           "incomplete Intelligent-Tiering document";
      end if;
      return Item.Value;
   end Read_Handler;

   function Empty_Page return Intelligent_Tiering_Configuration_Page is
     ((Has_Is_Truncated        => False,
       Is_Truncated            => False,
       Continuation_Token      => Empty_String,
       Next_Continuation_Token => Empty_String,
       Configurations          => Configuration_Vectors.Empty_Vector));

   procedure Set_Page_Is_Truncated
     (Result : in out Intelligent_Tiering_Configuration_Page;
      Value  : Boolean) is
   begin
      Result.Has_Is_Truncated := True;
      Result.Is_Truncated := Value;
   end Set_Page_Is_Truncated;

   procedure Set_Page_Continuation_Token
     (Result : in out Intelligent_Tiering_Configuration_Page;
      Value  : String) is
   begin
      Result.Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Continuation_Token;

   procedure Set_Page_Next_Continuation_Token
     (Result : in out Intelligent_Tiering_Configuration_Page;
      Value  : String) is
   begin
      Result.Next_Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Next_Continuation_Token;

   procedure Append_Page_Item
     (Result : in out Intelligent_Tiering_Configuration_Page;
      Value  : Intelligent_Tiering_Configuration) is
   begin
      Result.Configurations.Append (Value);
   end Append_Page_Item;

   procedure Reject_Page_Extra_Scalar
     (Result : in out Intelligent_Tiering_Configuration_Page;
      Name   : String;
      Value  : String) is
      pragma Unreferenced (Result, Name, Value);
   begin
      raise Malformed_Intelligent_Tiering with
        "unknown intelligent-tiering page member";
   end Reject_Page_Extra_Scalar;

   procedure Ignore_Item_Container_Presence
     (Result : in out Intelligent_Tiering_Configuration_Page) is
      pragma Unreferenced (Result);
   begin
      null;
   end Ignore_Item_Container_Presence;

   --  Both element names are fixed by the pinned Botocore operation/output
   --  model. Changing either changes accepted S3 wire documents.
   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                   =>
        "ListBucketIntelligentTieringConfigurationsOutput",
      Item_Container_Name         => "",
      Item_Name                   => "IntelligentTieringConfiguration",
      Allow_Is_Truncated          => True,
      Allow_Continuation_Token    => True,
      Allow_Next_Continuation_Token => True,
      Item_Type                   => Intelligent_Tiering_Configuration,
      Item_Handler_Type           => Intelligent_Tiering_Handler,
      Reset_Item                  => Reset_Handler,
      Read_Item                   => Read_Handler,
      Result_Type                 => Intelligent_Tiering_Configuration_Page,
      Empty_Result                => Empty_Page,
      Set_Is_Truncated            => Set_Page_Is_Truncated,
      Set_Continuation_Token      => Set_Page_Continuation_Token,
      Set_Next_Continuation_Token => Set_Page_Next_Continuation_Token,
      Set_Extra_Scalar            => Reject_Page_Extra_Scalar,
      Set_Item_Container_Present  => Ignore_Item_Container_Presence,
      Append_Item                 => Append_Page_Item);

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Intelligent_Tiering_Configuration
   is
      Handler : aliased Intelligent_Tiering_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      return Read_Handler (Handler);
   exception
      when XML.XML_Error =>
         raise Malformed_Intelligent_Tiering with
           "malformed Intelligent-Tiering XML";
   end Parse;

   function Parse_List
     (Document : String; Limits : XML.Parse_Limits)
      return Intelligent_Tiering_Configuration_Page is
   begin
      return Page_Decoder.Parse (Document, Limits);
   exception
      when Page_Decoder.Malformed_Page =>
         raise Malformed_Intelligent_Tiering with
           "malformed Intelligent-Tiering-list XML";
   end Parse_List;

   function Serialize
     (Value : Intelligent_Tiering_Configuration; Limits : XML.Parse_Limits)
      return String
   is
      Result     : US.Unbounded_String;
      Elements   : Natural := 1;
      Text_Bytes : Natural := 0;
      Depth      : Positive := 1;

      --  Pinned PutBucketIntelligentTieringConfiguration REST/XML root and
      --  namespace. Changing either changes the provider wire contract and
      --  signature.
      Prefix : constant String :=
        "<IntelligentTieringConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">";
      Suffix : constant String := "</IntelligentTieringConfiguration>";

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Intelligent_Tiering with
              "Intelligent-Tiering document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;

      procedure Start_Element (Name : String; At_Depth : Positive) is
      begin
         if Elements = Limits.Maximum_Elements then
            raise Malformed_Intelligent_Tiering with
              "Intelligent-Tiering elements exceed caller limit";
         end if;
         Elements := Elements + 1;
         Depth := Positive'Max (Depth, At_Depth);
         Append_Bounded ("<" & Name & ">");
      end Start_Element;

      procedure End_Element (Name : String) is
      begin
         Append_Bounded ("</" & Name & ">");
      end End_Element;

      procedure Add_Text (Text : String) is
      begin
         if Text'Length > Limits.Maximum_Text_Bytes - Text_Bytes then
            raise Malformed_Intelligent_Tiering with
              "Intelligent-Tiering text exceeds caller limit";
         end if;
         Text_Bytes := Text_Bytes + Text'Length;
         Append_Bounded (XML.Escape_Text (Text));
      exception
         when XML.XML_Error =>
            raise Malformed_Intelligent_Tiering with
              "invalid Intelligent-Tiering XML text";
      end Add_Text;

      procedure Add_Scalar
        (Name : String; Text : String; At_Depth : Positive) is
      begin
         Start_Element (Name, At_Depth);
         Add_Text (Text);
         End_Element (Name);
      end Add_Scalar;

      procedure Add_Optional
        (Name : String; Item : Optional_String; At_Depth : Positive) is
      begin
         if Item.Is_Set then
            Add_Scalar (Name, US.To_String (Item.Value), At_Depth);
         elsif US.Length (Item.Value) /= 0 then
            raise Malformed_Intelligent_Tiering with
              "absent Intelligent-Tiering member contains text";
         end if;
      end Add_Optional;

      procedure Add_Tag
        (Item : Intelligent_Tiering_Tag; At_Depth : Positive) is
      begin
         if US.Length (Item.Key) = 0 then
            raise Malformed_Intelligent_Tiering with
              "empty Intelligent-Tiering tag key";
         end if;
         Start_Element ("Tag", At_Depth);
         Add_Scalar ("Key", US.To_String (Item.Key), At_Depth + 1);
         Add_Scalar ("Value", US.To_String (Item.Value), At_Depth + 1);
         End_Element ("Tag");
      end Add_Tag;

      function Has_Filter_Content
        (Item : Intelligent_Tiering_Filter) return Boolean is
        (Item.Prefix.Is_Set
         or else US.Length (Item.Prefix.Value) /= 0
         or else Item.Tag.Is_Set
         or else US.Length (Item.Tag.Value.Key) /= 0
         or else US.Length (Item.Tag.Value.Value) /= 0
         or else Item.And_Predicates.Is_Set
         or else Item.And_Predicates.Prefix.Is_Set
         or else US.Length (Item.And_Predicates.Prefix.Value) /= 0
         or else not Item.And_Predicates.Tags.Is_Empty);

      --  These exhaustive mappings are the pinned Botocore enum domains.
      --  Adding a typed value must also choose its exact compatible wire text.
      function Image (Item : Configuration_Status) return String is
        (case Item is
            when Enabled  => "Enabled",
            when Disabled => "Disabled");

      function Image (Item : Access_Tier_Kind) return String is
        (case Item is
            when Archive_Access      => "ARCHIVE_ACCESS",
            when Deep_Archive_Access => "DEEP_ARCHIVE_ACCESS");
   begin
      Append_Bounded (Prefix);
      Add_Scalar ("Id", US.To_String (Value.ID), 2);

      if Value.Filter.Is_Set then
         Start_Element ("Filter", 2);
         Add_Optional ("Prefix", Value.Filter.Prefix, 3);
         if Value.Filter.Tag.Is_Set then
            Add_Tag (Value.Filter.Tag.Value, 3);
         elsif US.Length (Value.Filter.Tag.Value.Key) /= 0
           or else US.Length (Value.Filter.Tag.Value.Value) /= 0
         then
            raise Malformed_Intelligent_Tiering with
              "absent Intelligent-Tiering tag contains text";
         end if;
         if Value.Filter.And_Predicates.Is_Set then
            Start_Element ("And", 3);
            Add_Optional
              ("Prefix", Value.Filter.And_Predicates.Prefix, 4);
            for Tag of Value.Filter.And_Predicates.Tags loop
               Add_Tag (Tag, 4);
            end loop;
            End_Element ("And");
         elsif Value.Filter.And_Predicates.Prefix.Is_Set
           or else US.Length (Value.Filter.And_Predicates.Prefix.Value) /= 0
           or else not Value.Filter.And_Predicates.Tags.Is_Empty
         then
            raise Malformed_Intelligent_Tiering with
              "absent Intelligent-Tiering And contains members";
         end if;
         End_Element ("Filter");
      elsif Has_Filter_Content (Value.Filter) then
         raise Malformed_Intelligent_Tiering with
           "absent Intelligent-Tiering filter contains members";
      end if;

      Add_Scalar ("Status", Image (Value.Status), 2);
      if Value.Tierings.Is_Empty then
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering requires at least one transition";
      end if;
      for Transition of Value.Tierings loop
         declare
            Days : constant String := US.To_String (Transition.Days);
         begin
            if not Valid_Integer_Text (Days) then
               raise Malformed_Intelligent_Tiering with
                 "invalid Intelligent-Tiering days";
            end if;
            Start_Element ("Tiering", 2);
            Add_Scalar ("Days", Days, 3);
            Add_Scalar ("AccessTier", Image (Transition.Access_Tier), 3);
            End_Element ("Tiering");
         end;
      end loop;

      Append_Bounded (Suffix);
      if Depth > Limits.Maximum_Depth then
         raise Malformed_Intelligent_Tiering with
           "Intelligent-Tiering depth exceeds caller limit";
      end if;
      declare
         Document : constant String := US.To_String (Result);
         Verified : constant Intelligent_Tiering_Configuration :=
           Parse (Document, Limits);
         pragma Unreferenced (Verified);
      begin
         return Document;
      end;
   exception
      when XML.XML_Error =>
         raise Malformed_Intelligent_Tiering with
           "invalid Intelligent-Tiering XML text";
   end Serialize;

end Flyology.Object_Storage.S3.Intelligent_Tiering;
