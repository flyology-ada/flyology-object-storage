package body Flyology.Object_Storage.S3.Bucket_Controls is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   type Document_Kind is
     (Abac_Document,
      Accelerate_Document,
      Policy_Status_Document,
      Request_Payment_Document,
      Public_Access_Block_Document);

   type Field_Kind is
     (No_Field,
      Status_Field,
      Is_Public_Field,
      Payer_Field,
      Block_Public_ACLs_Field,
      Ignore_Public_ACLs_Field,
      Block_Public_Policy_Field,
      Restrict_Public_Buckets_Field);

   type Field_Seen_Array is array (Field_Kind) of Boolean;

   type Configuration_Handler (Kind : Document_Kind) is
     new XML.Event_Handler with record
      Depth      : Natural := 0;
      Field      : Field_Kind := No_Field;
      Seen       : Field_Seen_Array := (others => False);
      Text_Value : US.Unbounded_String;
      Root_Seen  : Boolean := False;
      --  Parser-state representation: absent is the pinned optional-member
      --  sentinel until an exact Status event arrives; this affects decoded
      --  presence, not provider policy.
      Abac       : Abac_Status := Abac_Status_Absent;
      Accelerate : Accelerate_Status := Accelerate_Status_Absent;
      Is_Public  : Optional_Boolean;
      Payment    : Payer := Payer_Absent;
      Public_Access : Public_Access_Block_Configuration;
   end record;

   overriding procedure Start_Element
     (Item : in out Configuration_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Configuration_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Configuration_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Configuration_Handler; Local_Name : String);

   type Ownership_Namespace_Style is
     (Ownership_Namespace_Not_Selected, Ownership_Unqualified,
      Ownership_S3_Qualified);

   type Ownership_Handler is new XML.Event_Handler with record
      Depth          : Natural := 0;
      Root_Seen      : Boolean := False;
      Rule_Seen      : Boolean := False;
      Ownership_Seen : Boolean := False;
      Namespace      : Ownership_Namespace_Style :=
        Ownership_Namespace_Not_Selected;
      Text_Value     : US.Unbounded_String;
      --  Parser scratch is overwritten by the required wire member before a
      --  rule is appended; this deterministic initializer is not a default
      --  ownership policy and never appears for absent or malformed input.
      Current        : Ownership_Control_Rule :=
        (Ownership => Bucket_Owner_Preferred);
      Value          : Ownership_Controls_Configuration :=
        (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Ownership_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Ownership_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Ownership_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Ownership_Handler; Local_Name : String);

   type CORS_Namespace_Style is
     (CORS_Namespace_Not_Selected, CORS_Unqualified, CORS_S3_Qualified);

   type CORS_Field is
     (No_CORS_Field, CORS_ID_Field, Allowed_Header_Field,
      Allowed_Method_Field, Allowed_Origin_Field, Expose_Header_Field,
      Max_Age_Seconds_Field);

   type CORS_Handler is new XML.Event_Handler with record
      Depth               : Natural := 0;
      Root_Seen           : Boolean := False;
      Rule_Open           : Boolean := False;
      ID_Seen             : Boolean := False;
      Allowed_Method_Seen : Boolean := False;
      Allowed_Origin_Seen : Boolean := False;
      Max_Age_Seen        : Boolean := False;
      Namespace           : CORS_Namespace_Style :=
        CORS_Namespace_Not_Selected;
      Field               : CORS_Field := No_CORS_Field;
      Text_Value          : US.Unbounded_String;
      Current             : CORS_Rule := (others => <>);
      Value               : CORS_Configuration :=
        (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out CORS_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out CORS_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out CORS_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out CORS_Handler; Local_Name : String);

   --  External REST/XML contract from the pinned generated S3 model: these
   --  root, member, enumeration, boolean, and namespace spellings are exact;
   --  changing them changes provider wire compatibility.
   Namespace_Attribute : constant String :=
     " xmlns=""http://s3.amazonaws.com/doc/2006-03-01/""";

   function Root_Name (Kind : Document_Kind) return String is
     (case Kind is
         when Abac_Document => "AbacStatus",
         when Accelerate_Document => "AccelerateConfiguration",
         when Policy_Status_Document => "PolicyStatus",
         when Request_Payment_Document => "RequestPaymentConfiguration",
         when Public_Access_Block_Document =>
           "PublicAccessBlockConfiguration");

   procedure Require_Whitespace (Value : String) is
   begin
      for Item of Value loop
         if Item not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Configuration with
              "text outside bucket-control fields";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Configuration_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      pragma Unreferenced (Item);
   begin
      if (Namespace_URI'Length > 0
          and then Namespace_URI /=
            "http://s3.amazonaws.com/doc/2006-03-01/")
        or else Attribute_Count /= 0
      then
         raise Malformed_Configuration with
           "bucket-control namespace or attributes are invalid";
      end if;
   end Start_Element_Details;

   function Field_For
     (Kind : Document_Kind; Local_Name : String) return Field_Kind
   is
   begin
      case Kind is
         when Abac_Document =>
            return (if Local_Name = "Status" then Status_Field else No_Field);
         when Accelerate_Document =>
            return (if Local_Name = "Status" then Status_Field else No_Field);
         when Policy_Status_Document =>
            return
              (if Local_Name = "IsPublic" then Is_Public_Field else No_Field);
         when Request_Payment_Document =>
            return (if Local_Name = "Payer" then Payer_Field else No_Field);
         when Public_Access_Block_Document =>
            if Local_Name = "BlockPublicAcls" then
               return Block_Public_ACLs_Field;
            elsif Local_Name = "IgnorePublicAcls" then
               return Ignore_Public_ACLs_Field;
            elsif Local_Name = "BlockPublicPolicy" then
               return Block_Public_Policy_Field;
            elsif Local_Name = "RestrictPublicBuckets" then
               return Restrict_Public_Buckets_Field;
            end if;
            return No_Field;
      end case;
   end Field_For;

   overriding procedure Start_Element
     (Item : in out Configuration_Handler; Local_Name : String)
   is
      Field : Field_Kind;
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Configuration with "bucket-control depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= Root_Name (Item.Kind) then
            raise Malformed_Configuration with "invalid bucket-control root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2 then
         Field := Field_For (Item.Kind, Local_Name);
         if Field = No_Field or else Item.Seen (Field) then
            raise Malformed_Configuration with
              "unknown or duplicate bucket-control field";
         end if;
         Item.Seen (Field) := True;
         Item.Field := Field;
         Item.Text_Value := US.Null_Unbounded_String;
      else
         raise Malformed_Configuration with "nested bucket-control field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Configuration_Handler; Value : String) is
   begin
      if Item.Depth = 2 and then Item.Field /= No_Field then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth = 1 then
         Require_Whitespace (Value);
      else
         raise Malformed_Configuration with
           "bucket-control text outside the document root";
      end if;
   end Text;

   function Parse_Boolean (Value : String) return Optional_Boolean is
   begin
      if Value = "true" then
         return (Is_Set => True, Value => True);
      elsif Value = "false" then
         return (Is_Set => True, Value => False);
      end if;
      raise Malformed_Configuration with "invalid bucket-control boolean";
   end Parse_Boolean;

   overriding procedure End_Element
     (Item : in out Configuration_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      if Item.Depth = 2 then
         if Field_For (Item.Kind, Local_Name) /= Item.Field then
            raise Malformed_Configuration with
              "mismatched bucket-control field close";
         end if;
         case Item.Field is
            when Status_Field =>
               case Item.Kind is
                  when Abac_Document =>
                     if Value = "Enabled" then
                        Item.Abac := Abac_Enabled;
                     elsif Value = "Disabled" then
                        Item.Abac := Abac_Disabled;
                     else
                        raise Malformed_Configuration with
                          "invalid ABAC status";
                     end if;
                  when Accelerate_Document =>
                     if Value = "Enabled" then
                        Item.Accelerate := Accelerate_Enabled;
                     elsif Value = "Suspended" then
                        Item.Accelerate := Accelerate_Suspended;
                     else
                        raise Malformed_Configuration with
                          "invalid accelerate status";
                     end if;
                  when others =>
                     raise Malformed_Configuration with
                       "status is not valid for bucket-control document";
               end case;
            when Is_Public_Field =>
               Item.Is_Public := Parse_Boolean (Value);
            when Payer_Field =>
               if Value = "Requester" then
                  Item.Payment := Requester;
               elsif Value = "BucketOwner" then
                  Item.Payment := Bucket_Owner;
               else
                  raise Malformed_Configuration with "invalid payer";
               end if;
            when Block_Public_ACLs_Field =>
               Item.Public_Access.Block_Public_ACLs := Parse_Boolean (Value);
            when Ignore_Public_ACLs_Field =>
               Item.Public_Access.Ignore_Public_ACLs := Parse_Boolean (Value);
            when Block_Public_Policy_Field =>
               Item.Public_Access.Block_Public_Policy := Parse_Boolean (Value);
            when Restrict_Public_Buckets_Field =>
               Item.Public_Access.Restrict_Public_Buckets :=
                 Parse_Boolean (Value);
            when No_Field =>
               raise Malformed_Configuration with
                 "bucket-control field state is invalid";
         end case;
         Item.Field := No_Field;
         Item.Text_Value := US.Null_Unbounded_String;
         Item.Depth := 1;
      elsif Item.Depth = 1 and then Local_Name = Root_Name (Item.Kind) then
         Item.Depth := 0;
      else
         raise Malformed_Configuration with
           "invalid bucket-control closing element";
      end if;
   end End_Element;

   procedure Parse
     (Document : String;
      Limits   : XML.Parse_Limits;
      Handler  : aliased in out Configuration_Handler)
   is
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Configuration with
           "incomplete bucket-control document";
      end if;
   exception
      when XML.XML_Error =>
         raise Malformed_Configuration with "malformed bucket-control XML";
   end Parse;

   function Parse_Accelerate
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Accelerate_Status
   is
      Handler : aliased Configuration_Handler (Accelerate_Document);
   begin
      Parse (Document, Limits, Handler);
      return Handler.Accelerate;
   end Parse_Accelerate;

   function Parse_Abac
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Abac_Status
   is
      Handler : aliased Configuration_Handler (Abac_Document);
   begin
      Parse (Document, Limits, Handler);
      return Handler.Abac;
   end Parse_Abac;

   function Parse_Policy_Status
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Optional_Boolean
   is
      Handler : aliased Configuration_Handler (Policy_Status_Document);
   begin
      Parse (Document, Limits, Handler);
      return Handler.Is_Public;
   end Parse_Policy_Status;

   function Parse_Request_Payment
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Payer
   is
      Handler : aliased Configuration_Handler (Request_Payment_Document);
   begin
      Parse (Document, Limits, Handler);
      return Handler.Payment;
   end Parse_Request_Payment;

   function Parse_Public_Access_Block
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Public_Access_Block_Configuration
   is
      Handler : aliased Configuration_Handler (Public_Access_Block_Document);
   begin
      Parse (Document, Limits, Handler);
      return Handler.Public_Access;
   end Parse_Public_Access_Block;

   overriding procedure Start_Element_Details
     (Item            : in out Ownership_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      Style : constant Ownership_Namespace_Style :=
        (if Namespace_URI'Length = 0 then Ownership_Unqualified
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then Ownership_S3_Qualified
         else Ownership_Namespace_Not_Selected);
   begin
      if Attribute_Count /= 0
        or else Style = Ownership_Namespace_Not_Selected
        or else (Item.Namespace /= Ownership_Namespace_Not_Selected
                 and then Item.Namespace /= Style)
      then
         raise Malformed_Configuration with
           "ownership-controls namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Ownership_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Configuration with
           "ownership-controls depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "OwnershipControls" then
               raise Malformed_Configuration with
                 "invalid OwnershipControls root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name /= "Rule" then
               raise Malformed_Configuration with
                 "unknown ownership-controls member";
            end if;
            Item.Rule_Seen := True;
            Item.Ownership_Seen := False;
            Item.Text_Value := US.Null_Unbounded_String;
         when 3 =>
            if Local_Name /= "ObjectOwnership" or else Item.Ownership_Seen then
               raise Malformed_Configuration with
                 "unknown or duplicate ownership rule member";
            end if;
            Item.Ownership_Seen := True;
            Item.Text_Value := US.Null_Unbounded_String;
         when others =>
            raise Malformed_Configuration with
              "nested ownership-controls member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Ownership_Handler; Value : String) is
   begin
      if Item.Depth = 3 and then Item.Ownership_Seen then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 2 then
         Require_Whitespace (Value);
      else
         raise Malformed_Configuration with
           "ownership-controls text outside modeled member";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Ownership_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Depth is
         when 3 =>
            if Local_Name /= "ObjectOwnership" then
               raise Malformed_Configuration with
                 "mismatched ObjectOwnership close";
            elsif Value = "BucketOwnerPreferred" then
               Item.Current.Ownership := Bucket_Owner_Preferred;
            elsif Value = "ObjectWriter" then
               Item.Current.Ownership := Object_Writer;
            elsif Value = "BucketOwnerEnforced" then
               Item.Current.Ownership := Bucket_Owner_Enforced;
            else
               raise Malformed_Configuration with
                 "invalid ObjectOwnership value";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Local_Name /= "Rule" or else not Item.Ownership_Seen then
               raise Malformed_Configuration with
                 "incomplete ownership-controls rule";
            end if;
            Item.Value.Rules.Append (Item.Current);
            Item.Ownership_Seen := False;
            Item.Text_Value := US.Null_Unbounded_String;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "OwnershipControls" or else not Item.Rule_Seen
            then
               raise Malformed_Configuration with
                 "incomplete OwnershipControls document";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Configuration with
              "invalid ownership-controls closing element";
      end case;
   end End_Element;

   function Parse_Ownership_Controls
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Ownership_Controls_Configuration
   is
      Handler : aliased Ownership_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Configuration with
           "incomplete OwnershipControls document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Configuration with
           "malformed OwnershipControls XML";
   end Parse_Ownership_Controls;

   function Serialize_Ownership_Controls
     (Value  : Ownership_Controls_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Result : US.Unbounded_String;
      Text_Bytes : Natural := 0;
      --  Pinned shape graph: OwnershipControls / Rule / ObjectOwnership is
      --  exactly three elements deep, with one root and two elements per rule.
      Required_Depth    : constant Positive := 3;
      Root_Elements     : constant Positive := 1;
      Elements_Per_Rule : constant Positive := 2;
      --  Exact external REST/XML namespace and member spellings from the
      --  pinned PutBucketOwnershipControls model.
      Prefix : constant String :=
        "<OwnershipControls xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/"">";
      Rule_Open : constant String := "<Rule><ObjectOwnership>";
      Rule_Close : constant String := "</ObjectOwnership></Rule>";
      Suffix : constant String := "</OwnershipControls>";

      function Wire_Value (Item : Object_Ownership) return String is
        (case Item is
            when Bucket_Owner_Preferred => "BucketOwnerPreferred",
            when Object_Writer => "ObjectWriter",
            when Bucket_Owner_Enforced => "BucketOwnerEnforced");

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Configuration with
              "ownership-controls document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;
   begin
      if not Value.Is_Set or else Value.Rules.Is_Empty then
         raise Malformed_Configuration with
           "ownership-controls rules are required";
      elsif Limits.Maximum_Depth < Required_Depth
        or else Value.Rules.Length >
          Ada.Containers.Count_Type
            ((Limits.Maximum_Elements - Root_Elements) / Elements_Per_Rule)
      then
         raise Malformed_Configuration with
           "ownership-controls structure exceeds caller limit";
      end if;

      Append_Bounded (Prefix);
      for Rule of Value.Rules loop
         declare
            Item : constant String := Wire_Value (Rule.Ownership);
         begin
            if Item'Length > Limits.Maximum_Text_Bytes - Text_Bytes then
               raise Malformed_Configuration with
                 "ownership-controls text exceeds caller limit";
            end if;
            Text_Bytes := Text_Bytes + Item'Length;
            Append_Bounded (Rule_Open);
            Append_Bounded (Item);
            Append_Bounded (Rule_Close);
         end;
      end loop;
      Append_Bounded (Suffix);
      return US.To_String (Result);
   end Serialize_Ownership_Controls;

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

   overriding procedure Start_Element_Details
     (Item            : in out CORS_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      Style : constant CORS_Namespace_Style :=
        (if Namespace_URI'Length = 0 then CORS_Unqualified
         --  Pinned S3 REST/XML namespace; changing this exact external value
         --  changes provider wire compatibility for every CORS member.
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then CORS_S3_Qualified
         else CORS_Namespace_Not_Selected);
   begin
      if Attribute_Count /= 0
        or else Style = CORS_Namespace_Not_Selected
        or else (Item.Namespace /= CORS_Namespace_Not_Selected
                 and then Item.Namespace /= Style)
      then
         raise Malformed_Configuration with
           "CORS namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   function CORS_Field_For (Local_Name : String) return CORS_Field is
   begin
      if Local_Name = "ID" then
         return CORS_ID_Field;
      elsif Local_Name = "AllowedHeader" then
         return Allowed_Header_Field;
      elsif Local_Name = "AllowedMethod" then
         return Allowed_Method_Field;
      elsif Local_Name = "AllowedOrigin" then
         return Allowed_Origin_Field;
      elsif Local_Name = "ExposeHeader" then
         return Expose_Header_Field;
      elsif Local_Name = "MaxAgeSeconds" then
         return Max_Age_Seconds_Field;
      end if;
      return No_CORS_Field;
   end CORS_Field_For;

   overriding procedure Start_Element
     (Item : in out CORS_Handler; Local_Name : String)
   is
      Field : CORS_Field;
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Configuration with "CORS depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "CORSConfiguration" then
               raise Malformed_Configuration with
                 "invalid CORSConfiguration root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name /= "CORSRule" then
               raise Malformed_Configuration with "unknown CORS member";
            end if;
            Item.Rule_Open := True;
            Item.ID_Seen := False;
            Item.Allowed_Method_Seen := False;
            Item.Allowed_Origin_Seen := False;
            Item.Max_Age_Seen := False;
            Item.Current := (others => <>);
         when 3 =>
            Field := CORS_Field_For (Local_Name);
            if Field = No_CORS_Field
              or else (Field = CORS_ID_Field and then Item.ID_Seen)
              or else (Field = Max_Age_Seconds_Field
                       and then Item.Max_Age_Seen)
            then
               raise Malformed_Configuration with
                 "unknown or duplicate CORS rule member";
            end if;
            Item.Field := Field;
            Item.Text_Value := US.Null_Unbounded_String;
            case Field is
               when CORS_ID_Field => Item.ID_Seen := True;
               when Allowed_Method_Field => Item.Allowed_Method_Seen := True;
               when Allowed_Origin_Field => Item.Allowed_Origin_Seen := True;
               when Max_Age_Seconds_Field => Item.Max_Age_Seen := True;
               when others => null;
            end case;
         when others =>
            raise Malformed_Configuration with "nested CORS rule member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out CORS_Handler; Value : String) is
   begin
      if Item.Depth = 3 and then Item.Field /= No_CORS_Field then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 2 then
         Require_Whitespace (Value);
      else
         raise Malformed_Configuration with
           "CORS text outside a modeled member";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out CORS_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Depth is
         when 3 =>
            if CORS_Field_For (Local_Name) /= Item.Field then
               raise Malformed_Configuration with
                 "mismatched CORS rule member close";
            end if;
            case Item.Field is
               when CORS_ID_Field =>
                  Item.Current.ID :=
                    (Is_Set => True, Value => Item.Text_Value);
               when Allowed_Header_Field =>
                  Item.Current.Allowed_Headers.Append (Value);
               when Allowed_Method_Field =>
                  Item.Current.Allowed_Methods.Append (Value);
               when Allowed_Origin_Field =>
                  Item.Current.Allowed_Origins.Append (Value);
               when Expose_Header_Field =>
                  Item.Current.Expose_Headers.Append (Value);
               when Max_Age_Seconds_Field =>
                  if not Valid_Integer_Text (Value) then
                     raise Malformed_Configuration with
                       "invalid CORS MaxAgeSeconds";
                  end if;
                  Item.Current.Max_Age_Seconds :=
                    (Is_Set => True, Text => Item.Text_Value);
               when No_CORS_Field =>
                  raise Malformed_Configuration with
                    "CORS member close without an open member";
            end case;
            Item.Field := No_CORS_Field;
            Item.Text_Value := US.Null_Unbounded_String;
            Item.Depth := 2;
         when 2 =>
            if Local_Name /= "CORSRule"
              or else not Item.Rule_Open
              or else not Item.Allowed_Method_Seen
              or else not Item.Allowed_Origin_Seen
            then
               raise Malformed_Configuration with "incomplete CORS rule";
            end if;
            Item.Value.Rules.Append (Item.Current);
            Item.Rule_Open := False;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "CORSConfiguration" then
               raise Malformed_Configuration with
                 "mismatched CORSConfiguration close";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Configuration with
              "invalid CORS closing element";
      end case;
   end End_Element;

   function Parse_CORS
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return CORS_Configuration
   is
      Handler : aliased CORS_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Configuration with
           "incomplete CORSConfiguration document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Configuration with "malformed CORS XML";
   end Parse_CORS;

   function Serialize_CORS
     (Value  : CORS_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Result     : US.Unbounded_String;
      --  Pinned shape derivation: CORSConfiguration / CORSRule / field is
      --  exactly three elements deep and the document begins with one root.
      --  Changing either value changes caller-limit compatibility.
      Required_Depth : constant Positive := 3;
      Root_Elements  : constant Positive := 1;
      Elements   : Natural := Root_Elements;
      Text_Bytes : Natural := 0;

      --  Pinned PutBucketCors REST/XML namespace and member spellings.
      --  Changing them changes provider compatibility and request signatures.
      Prefix : constant String :=
        "<CORSConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">";
      Suffix : constant String := "</CORSConfiguration>";

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Configuration with
              "CORS document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;

      procedure Add_Element is
      begin
         if Elements = Limits.Maximum_Elements then
            raise Malformed_Configuration with
              "CORS elements exceed caller limit";
         end if;
         Elements := Elements + 1;
      end Add_Element;

      procedure Add_Text (Text : String) is
      begin
         if Text'Length > Limits.Maximum_Text_Bytes - Text_Bytes then
            raise Malformed_Configuration with
              "CORS text exceeds caller limit";
         end if;
         Text_Bytes := Text_Bytes + Text'Length;
         Append_Bounded (XML.Escape_Text (Text));
      end Add_Text;

      procedure Add_Field (Name : String; Text : String) is
      begin
         Add_Element;
         Append_Bounded ("<" & Name & ">");
         Add_Text (Text);
         Append_Bounded ("</" & Name & ">");
      end Add_Field;
   begin
      if not Value.Is_Set or else Value.Rules.Is_Empty then
         raise Malformed_Configuration with "CORS rules are required";
      elsif Limits.Maximum_Depth < Required_Depth then
         raise Malformed_Configuration with
           "CORS depth exceeds caller limit";
      end if;

      Append_Bounded (Prefix);
      for Rule of Value.Rules loop
         if Rule.Allowed_Methods.Is_Empty
           or else Rule.Allowed_Origins.Is_Empty
         then
            raise Malformed_Configuration with
              "CORS methods and origins are required";
         elsif Rule.Max_Age_Seconds.Is_Set
           and then not Valid_Integer_Text
             (US.To_String (Rule.Max_Age_Seconds.Text))
         then
            raise Malformed_Configuration with "invalid CORS MaxAgeSeconds";
         end if;

         Add_Element;
         Append_Bounded ("<CORSRule>");
         if Rule.ID.Is_Set then
            Add_Field ("ID", US.To_String (Rule.ID.Value));
         end if;
         for Item of Rule.Allowed_Headers loop
            Add_Field ("AllowedHeader", Item);
         end loop;
         for Item of Rule.Allowed_Methods loop
            Add_Field ("AllowedMethod", Item);
         end loop;
         for Item of Rule.Allowed_Origins loop
            Add_Field ("AllowedOrigin", Item);
         end loop;
         for Item of Rule.Expose_Headers loop
            Add_Field ("ExposeHeader", Item);
         end loop;
         if Rule.Max_Age_Seconds.Is_Set then
            Add_Field
              ("MaxAgeSeconds", US.To_String (Rule.Max_Age_Seconds.Text));
         end if;
         Append_Bounded ("</CORSRule>");
      end loop;
      Append_Bounded (Suffix);
      return US.To_String (Result);
   end Serialize_CORS;

   function Serialize_Abac (Value : Abac_Status) return String is
      Status : constant String :=
        (case Value is
            when Abac_Status_Absent => "",
            when Abac_Enabled => "<Status>Enabled</Status>",
            when Abac_Disabled => "<Status>Disabled</Status>");
   begin
      return "<AbacStatus" & Namespace_Attribute & ">" & Status &
        "</AbacStatus>";
   end Serialize_Abac;

   function Serialize_Accelerate (Value : Accelerate_Status) return String is
      Status : constant String :=
        (case Value is
            when Accelerate_Status_Absent => "",
            when Accelerate_Enabled => "<Status>Enabled</Status>",
            when Accelerate_Suspended => "<Status>Suspended</Status>");
   begin
      return "<AccelerateConfiguration" & Namespace_Attribute & ">" & Status &
        "</AccelerateConfiguration>";
   end Serialize_Accelerate;

   function Serialize_Request_Payment (Value : Payer) return String is
      Payer_Text : constant String :=
        (case Value is
            when Payer_Absent => "",
            when Requester => "Requester",
            when Bucket_Owner => "BucketOwner");
   begin
      if Value = Payer_Absent then
         raise Malformed_Configuration with "payer is required";
      end if;
      return "<RequestPaymentConfiguration" & Namespace_Attribute & ">" &
        "<Payer>" & Payer_Text & "</Payer>" &
        "</RequestPaymentConfiguration>";
   end Serialize_Request_Payment;

   function Boolean_Element
     (Name : String; Value : Optional_Boolean) return String is
     (if not Value.Is_Set then ""
      else "<" & Name & ">" & (if Value.Value then "true" else "false") &
        "</" & Name & ">");

   function Serialize_Public_Access_Block
     (Value : Public_Access_Block_Configuration) return String is
   begin
      return "<PublicAccessBlockConfiguration" & Namespace_Attribute & ">" &
        Boolean_Element ("BlockPublicAcls", Value.Block_Public_ACLs) &
        Boolean_Element ("IgnorePublicAcls", Value.Ignore_Public_ACLs) &
        Boolean_Element ("BlockPublicPolicy", Value.Block_Public_Policy) &
        Boolean_Element
          ("RestrictPublicBuckets", Value.Restrict_Public_Buckets) &
        "</PublicAccessBlockConfiguration>";
   end Serialize_Public_Access_Block;

end Flyology.Object_Storage.S3.Bucket_Controls;
