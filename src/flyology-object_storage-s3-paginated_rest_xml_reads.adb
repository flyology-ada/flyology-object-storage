with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Paginated_REST_XML_Reads is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Scalar_Kind is
     (No_Scalar, Is_Truncated_Scalar, Continuation_Token_Scalar,
      Next_Continuation_Token_Scalar, Extra_Scalar);

   type Page_Handler is new XML.Event_Handler with record
      Depth                        : Natural := 0;
      Root_Seen                    : Boolean := False;
      Is_Truncated_Seen            : Boolean := False;
      Continuation_Token_Seen      : Boolean := False;
      Next_Continuation_Token_Seen : Boolean := False;
      Item_Container_Seen          : Boolean := False;
      Namespace                    : Namespace_Style := Namespace_Not_Selected;
      Pending_Namespace            : US.Unbounded_String;
      Pending_Attribute_Count      : Natural := 0;
      Scalar                       : Scalar_Kind := No_Scalar;
      Scalar_Name                  : US.Unbounded_String;
      Text_Value                   : US.Unbounded_String;
      In_Item_Container            : Boolean := False;
      In_Item                      : Boolean := False;
      Item                         : Item_Handler_Type;
      Value                        : Result_Type := Empty_Result;
   end record;

   overriding procedure Start_Element
     (Item : in out Page_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Page_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Element_Attribute
     (Item               : in out Page_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String);
   overriding procedure Text
     (Item : in out Page_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Page_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Page with "text outside modeled page member";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Validate_Envelope_Details
     (Item            : in out Page_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  The S3 REST/XML namespace is the external wire authority shared by
      --  every configuration-list page and its item codec.
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
         raise Malformed_Page with
           "configuration-list namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Validate_Envelope_Details;

   overriding procedure Start_Element_Details
     (Item            : in out Page_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural) is
   begin
      Validate_Envelope_Details (Item, Namespace_URI, Attribute_Count);
      if Item.In_Item then
         Start_Element_Details
           (Item.Item, Namespace_URI, Attribute_Count);
      else
         Item.Pending_Namespace := US.To_Unbounded_String (Namespace_URI);
         Item.Pending_Attribute_Count := Attribute_Count;
      end if;
   end Start_Element_Details;

   overriding procedure Element_Attribute
     (Item               : in out Page_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String) is
   begin
      if Item.In_Item then
         Element_Attribute
           (Item.Item, Element_Local_Name, Namespace_URI, Local_Name, Value);
      else
         raise Malformed_Page with
           "configuration-list attributes are not modeled";
      end if;
   end Element_Attribute;

   procedure Begin_Scalar
     (Item : in out Page_Handler;
      Kind : Scalar_Kind;
      Name : String := "") is
   begin
      Item.Scalar := Kind;
      Item.Scalar_Name := US.To_Unbounded_String (Name);
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   overriding procedure Start_Element
     (Item : in out Page_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Page with "configuration-list depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.In_Item then
         Start_Element (Item.Item, Local_Name);
      elsif Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= Root_Name then
            raise Malformed_Page with "invalid configuration-list root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2
        and then Item_Container_Name'Length /= 0
        and then Local_Name = Item_Container_Name
        and then not Item.Item_Container_Seen
      then
         Item.Item_Container_Seen := True;
         Item.In_Item_Container := True;
         Set_Item_Container_Present (Item.Value);
      elsif Item.Depth = 2
        and then Item_Container_Name'Length = 0
        and then Local_Name = Item_Name
      then
         Item.In_Item := True;
         Start_Element_Details
           (Item.Item,
            US.To_String (Item.Pending_Namespace),
            Item.Pending_Attribute_Count);
         Start_Element (Item.Item, Local_Name);
      elsif Item.Depth = 3
        and then Item.In_Item_Container
        and then Local_Name = Item_Name
      then
         Item.In_Item := True;
         Start_Element_Details
           (Item.Item,
            US.To_String (Item.Pending_Namespace),
            Item.Pending_Attribute_Count);
         Start_Element (Item.Item, Local_Name);
      elsif Item.Depth = 2
        and then Local_Name = "IsTruncated"
        and then Allow_Is_Truncated
        and then not Item.Is_Truncated_Seen
      then
         Item.Is_Truncated_Seen := True;
         Begin_Scalar (Item, Is_Truncated_Scalar);
      elsif Item.Depth = 2
        and then Local_Name = "ContinuationToken"
        and then Allow_Continuation_Token
        and then not Item.Continuation_Token_Seen
      then
         Item.Continuation_Token_Seen := True;
         Begin_Scalar (Item, Continuation_Token_Scalar);
      elsif Item.Depth = 2
        and then Local_Name = "NextContinuationToken"
        and then Allow_Next_Continuation_Token
        and then not Item.Next_Continuation_Token_Seen
      then
         Item.Next_Continuation_Token_Seen := True;
         Begin_Scalar (Item, Next_Continuation_Token_Scalar);
      elsif Item.Depth = 2 then
         Begin_Scalar (Item, Extra_Scalar, Local_Name);
      else
         raise Malformed_Page with
           "unknown or duplicate configuration-list member";
      end if;
      Item.Pending_Namespace := US.Null_Unbounded_String;
      Item.Pending_Attribute_Count := 0;
   end Start_Element;

   overriding procedure Text
     (Item : in out Page_Handler; Value : String) is
   begin
      if Item.In_Item then
         Text (Item.Item, Value);
      elsif Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth = 1
        or else (Item.In_Item_Container and then Item.Depth = 2)
      then
         Require_Whitespace (Value);
      else
         raise Malformed_Page with
           "configuration-list text outside modeled member";
      end if;
   end Text;

   procedure Store_Scalar (Item : in out Page_Handler) is
   begin
      case Item.Scalar is
         when Is_Truncated_Scalar =>
            declare
               Parsed : constant Wire_Core.Boolean_Result :=
                 Wire_Core.Parse_Boolean (US.To_String (Item.Text_Value));
            begin
               if not Parsed.Valid then
                  raise Malformed_Page with
                    "invalid configuration-list truncation value";
               end if;
               Set_Is_Truncated (Item.Value, Parsed.Value);
            end;
         when Continuation_Token_Scalar =>
            Set_Continuation_Token
              (Item.Value, US.To_String (Item.Text_Value));
         when Next_Continuation_Token_Scalar =>
            Set_Next_Continuation_Token
              (Item.Value, US.To_String (Item.Text_Value));
         when Extra_Scalar =>
            Set_Extra_Scalar
              (Item.Value, US.To_String (Item.Scalar_Name),
               US.To_String (Item.Text_Value));
         when No_Scalar =>
            raise Malformed_Page with
              "configuration-list close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Scalar_Name := US.Null_Unbounded_String;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   overriding procedure End_Element
     (Item : in out Page_Handler; Local_Name : String) is
   begin
      if Item.In_Item then
         End_Element (Item.Item, Local_Name);
         if (Item_Container_Name'Length = 0 and then Item.Depth = 2)
           or else (Item_Container_Name'Length /= 0 and then Item.Depth = 3)
         then
            if Local_Name /= Item_Name then
               raise Malformed_Page with
                 "mismatched configuration-list item close";
            end if;
            Append_Item (Item.Value, Read_Item (Item.Item));
            Reset_Item (Item.Item);
            Item.In_Item := False;
         end if;
      elsif Item.In_Item_Container and then Item.Depth = 2 then
         if Local_Name /= Item_Container_Name then
            raise Malformed_Page with
              "mismatched configuration-list item container close";
         end if;
         Item.In_Item_Container := False;
      elsif Item.Depth = 2 then
         if (Item.Scalar = Is_Truncated_Scalar
             and then Local_Name /= "IsTruncated")
           or else (Item.Scalar = Continuation_Token_Scalar
                    and then Local_Name /= "ContinuationToken")
           or else (Item.Scalar = Next_Continuation_Token_Scalar
                    and then Local_Name /= "NextContinuationToken")
           or else (Item.Scalar = Extra_Scalar
                    and then Local_Name /= US.To_String (Item.Scalar_Name))
         then
            raise Malformed_Page with
              "mismatched configuration-list scalar close";
         end if;
         Store_Scalar (Item);
      elsif Item.Depth = 1 then
         if Local_Name /= Root_Name then
            raise Malformed_Page with
              "mismatched configuration-list root close";
         end if;
      else
         raise Malformed_Page with
           "invalid configuration-list closing element";
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse
     (Document : String; Limits : XML.Parse_Limits) return Result_Type
   is
      Handler : aliased Page_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0
        or else Handler.In_Item
        or else Handler.In_Item_Container
        or else not Handler.Root_Seen
      then
         raise Malformed_Page with "incomplete configuration-list document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Page with "malformed configuration-list XML";
   end Parse;

end Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;
