with Ada.Strings.Unbounded;

package body Flyology.Object_Storage.S3.Bucket_Controls is

   package US renames Ada.Strings.Unbounded;

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
