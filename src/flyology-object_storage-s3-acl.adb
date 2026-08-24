package body Flyology.Object_Storage.S3.ACL is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Owner_Container, ACL_Container, Grant_Container,
      Grantee_Container);
   type Scalar_Kind is
     (No_Scalar, Owner_Display_Name_Scalar, Owner_ID_Scalar,
      Grantee_Display_Name_Scalar, Grantee_Email_Scalar, Grantee_ID_Scalar,
      Grantee_URI_Scalar, Permission_Scalar);

   type ACL_Handler is new XML.Event_Handler with record
      Depth                : Natural := 0;
      Root_Seen            : Boolean := False;
      Owner_Seen           : Boolean := False;
      ACL_Seen             : Boolean := False;
      Owner_Display_Seen   : Boolean := False;
      Owner_ID_Seen        : Boolean := False;
      Grantee_Seen         : Boolean := False;
      Permission_Seen      : Boolean := False;
      Grantee_Type_Seen    : Boolean := False;
      Pending_Type_Seen    : Boolean := False;
      Grantee_Display_Seen : Boolean := False;
      Grantee_Email_Seen   : Boolean := False;
      Grantee_ID_Seen      : Boolean := False;
      Grantee_URI_Seen     : Boolean := False;
      Attribute_Count      : Natural := 0;
      Namespace            : Namespace_Style := Namespace_Not_Selected;
      Container            : Container_Kind := No_Container;
      Scalar               : Scalar_Kind := No_Scalar;
      Text_Value           : US.Unbounded_String;
      Current              : Grant := (others => <>);
      Value                : Access_Control_Policy :=
        (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out ACL_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out ACL_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Element_Attribute
     (Item               : in out ACL_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String);
   overriding procedure Text
     (Item : in out ACL_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out ACL_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_ACL with "text outside ACL scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out ACL_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  Exact established S3 REST/XML namespace.  Changing this external
      --  value changes provider compatibility for every ACL member.
      Style : constant Namespace_Style :=
        (if Namespace_URI'Length = 0 then Unqualified
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then S3_Qualified
         else Namespace_Not_Selected);
   begin
      if Style = Namespace_Not_Selected
        or else (Item.Namespace /= Namespace_Not_Selected
                 and then Item.Namespace /= Style)
      then
         raise Malformed_ACL with "ACL namespace is invalid";
      end if;
      Item.Namespace := Style;
      Item.Attribute_Count := Attribute_Count;
      Item.Pending_Type_Seen := False;
   end Start_Element_Details;

   procedure Set_Grantee_Type (Item : in out ACL_Handler; Value : String) is
   begin
      if Value = "CanonicalUser" then
         Item.Current.Principal.Kind := Canonical_User;
      elsif Value = "AmazonCustomerByEmail" then
         Item.Current.Principal.Kind := Amazon_Customer_By_Email;
      elsif Value = "Group" then
         Item.Current.Principal.Kind := Group_Grantee;
      else
         raise Malformed_ACL with "invalid ACL grantee type";
      end if;
   end Set_Grantee_Type;

   overriding procedure Element_Attribute
     (Item               : in out ACL_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String) is
   begin
      --  S3 ACL wire contract: Grantee carries exactly xsi:type in the W3C
      --  XML Schema-instance namespace; changing it is wire-incompatible.
      if Element_Local_Name /= "Grantee"
        or else Namespace_URI /=
          "http://www.w3.org/2001/XMLSchema-instance"
        or else Local_Name /= "type"
        or else Item.Pending_Type_Seen
      then
         raise Malformed_ACL with "invalid ACL attribute";
      end if;
      Set_Grantee_Type (Item, Value);
      Item.Pending_Type_Seen := True;
   end Element_Attribute;

   procedure Begin_Scalar
     (Item : in out ACL_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   overriding procedure Start_Element
     (Item : in out ACL_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_ACL with "ACL depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if (Local_Name = "Grantee"
          and then (Item.Attribute_Count /= 1
                    or else not Item.Pending_Type_Seen))
        or else (Local_Name /= "Grantee" and then Item.Attribute_Count /= 0)
      then
         raise Malformed_ACL with "ACL attributes violate pinned schema";
      end if;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "AccessControlPolicy" then
               raise Malformed_ACL with "invalid AccessControlPolicy root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name = "Owner" and then not Item.Owner_Seen then
               Item.Owner_Seen := True;
               Item.Value.Policy_Owner.Is_Set := True;
               Item.Container := Owner_Container;
            elsif Local_Name = "AccessControlList" and then not Item.ACL_Seen
            then
               Item.ACL_Seen := True;
               Item.Value.ACL.Is_Set := True;
               Item.Container := ACL_Container;
            else
               raise Malformed_ACL with "unknown or duplicate ACL member";
            end if;
         when 3 =>
            if Item.Container = Owner_Container
              and then Local_Name = "DisplayName"
              and then not Item.Owner_Display_Seen
            then
               Item.Owner_Display_Seen := True;
               Begin_Scalar (Item, Owner_Display_Name_Scalar);
            elsif Item.Container = Owner_Container
              and then Local_Name = "ID"
              and then not Item.Owner_ID_Seen
            then
               Item.Owner_ID_Seen := True;
               Begin_Scalar (Item, Owner_ID_Scalar);
            elsif Item.Container = ACL_Container and then Local_Name = "Grant"
            then
               Item.Container := Grant_Container;
               Item.Grantee_Seen := False;
               Item.Permission_Seen := False;
               Item.Grantee_Type_Seen := False;
               Item.Current := (others => <>);
            else
               raise Malformed_ACL with "unknown ACL owner or list member";
            end if;
         when 4 =>
            if Item.Container = Grant_Container
              and then Local_Name = "Grantee"
              and then not Item.Grantee_Seen
            then
               Item.Grantee_Seen := True;
               Item.Grantee_Type_Seen := True;
               Item.Current.Principal.Is_Set := True;
               Item.Container := Grantee_Container;
               Item.Grantee_Display_Seen := False;
               Item.Grantee_Email_Seen := False;
               Item.Grantee_ID_Seen := False;
               Item.Grantee_URI_Seen := False;
            elsif Item.Container = Grant_Container
              and then Local_Name = "Permission"
              and then not Item.Permission_Seen
            then
               Item.Permission_Seen := True;
               Begin_Scalar (Item, Permission_Scalar);
            else
               raise Malformed_ACL with "unknown or duplicate Grant member";
            end if;
         when 5 =>
            if Item.Container /= Grantee_Container then
               raise Malformed_ACL with "grantee member outside Grantee";
            elsif Local_Name = "DisplayName"
              and then not Item.Grantee_Display_Seen
            then
               Item.Grantee_Display_Seen := True;
               Begin_Scalar (Item, Grantee_Display_Name_Scalar);
            elsif Local_Name = "EmailAddress"
              and then not Item.Grantee_Email_Seen
            then
               Item.Grantee_Email_Seen := True;
               Begin_Scalar (Item, Grantee_Email_Scalar);
            elsif Local_Name = "ID" and then not Item.Grantee_ID_Seen then
               Item.Grantee_ID_Seen := True;
               Begin_Scalar (Item, Grantee_ID_Scalar);
            elsif Local_Name = "URI" and then not Item.Grantee_URI_Seen then
               Item.Grantee_URI_Seen := True;
               Begin_Scalar (Item, Grantee_URI_Scalar);
            else
               raise Malformed_ACL with "unknown or duplicate Grantee member";
            end if;
         when others =>
            raise Malformed_ACL with "nested ACL member";
      end case;
      Item.Attribute_Count := 0;
   end Start_Element;

   overriding procedure Text
     (Item : in out ACL_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar and then Item.Depth in 3 .. 5 then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 4 then
         Require_Whitespace (Value);
      else
         raise Malformed_ACL with "ACL text outside modeled member";
      end if;
   end Text;

   procedure Store_Permission (Item : in out ACL_Handler; Value : String) is
   begin
      Item.Current.Allowed.Is_Set := True;
      if Value = "FULL_CONTROL" then
         Item.Current.Allowed.Value := Full_Control;
      elsif Value = "WRITE" then
         Item.Current.Allowed.Value := Write;
      elsif Value = "WRITE_ACP" then
         Item.Current.Allowed.Value := Write_ACP;
      elsif Value = "READ" then
         Item.Current.Allowed.Value := Read;
      elsif Value = "READ_ACP" then
         Item.Current.Allowed.Value := Read_ACP;
      else
         raise Malformed_ACL with "invalid ACL permission";
      end if;
   end Store_Permission;

   procedure Store_Scalar (Item : in out ACL_Handler) is
   begin
      case Item.Scalar is
         when Owner_Display_Name_Scalar =>
            Item.Value.Policy_Owner.Display_Name :=
              (Is_Set => True, Value => Item.Text_Value);
         when Owner_ID_Scalar =>
            Item.Value.Policy_Owner.ID :=
              (Is_Set => True, Value => Item.Text_Value);
         when Grantee_Display_Name_Scalar =>
            Item.Current.Principal.Display_Name :=
              (Is_Set => True, Value => Item.Text_Value);
         when Grantee_Email_Scalar =>
            Item.Current.Principal.Email_Address :=
              (Is_Set => True, Value => Item.Text_Value);
         when Grantee_ID_Scalar =>
            Item.Current.Principal.ID :=
              (Is_Set => True, Value => Item.Text_Value);
         when Grantee_URI_Scalar =>
            Item.Current.Principal.URI :=
              (Is_Set => True, Value => Item.Text_Value);
         when Permission_Scalar =>
            Store_Permission (Item, US.To_String (Item.Text_Value));
         when No_Scalar =>
            raise Malformed_ACL with "ACL close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   overriding procedure End_Element
     (Item : in out ACL_Handler; Local_Name : String) is
   begin
      case Item.Depth is
         when 5 =>
            if (Item.Scalar = Grantee_Display_Name_Scalar
                and then Local_Name /= "DisplayName")
              or else (Item.Scalar = Grantee_Email_Scalar
                       and then Local_Name /= "EmailAddress")
              or else (Item.Scalar = Grantee_ID_Scalar
                       and then Local_Name /= "ID")
              or else (Item.Scalar = Grantee_URI_Scalar
                       and then Local_Name /= "URI")
              or else Item.Scalar not in Grantee_Display_Name_Scalar ..
                Grantee_URI_Scalar
            then
               raise Malformed_ACL with "mismatched Grantee scalar close";
            end if;
            Store_Scalar (Item);
            Item.Depth := 4;
         when 4 =>
            if Item.Scalar = Permission_Scalar then
               if Local_Name /= "Permission" then
                  raise Malformed_ACL with "mismatched Permission close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Grantee_Container then
               if Local_Name /= "Grantee" or else not Item.Grantee_Type_Seen
               then
                  raise Malformed_ACL with "incomplete Grantee";
               end if;
               Item.Container := Grant_Container;
            else
               raise Malformed_ACL with "incomplete Grant member";
            end if;
            Item.Depth := 3;
         when 3 =>
            if Item.Scalar in Owner_Display_Name_Scalar .. Owner_ID_Scalar
            then
               if (Item.Scalar = Owner_Display_Name_Scalar
                   and then Local_Name /= "DisplayName")
                 or else (Item.Scalar = Owner_ID_Scalar
                          and then Local_Name /= "ID")
               then
                  raise Malformed_ACL with "mismatched Owner scalar close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Grant_Container then
               if Local_Name /= "Grant" then
                  raise Malformed_ACL with "mismatched Grant close";
               end if;
               Item.Value.ACL.Grants.Append (Item.Current);
               Item.Container := ACL_Container;
            else
               raise Malformed_ACL with "incomplete ACL nested member";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Item.Container = Owner_Container and then Local_Name = "Owner"
            then
               Item.Container := No_Container;
            elsif Item.Container = ACL_Container
              and then Local_Name = "AccessControlList"
            then
               Item.Container := No_Container;
            else
               raise Malformed_ACL with "mismatched ACL structure close";
            end if;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "AccessControlPolicy" then
               raise Malformed_ACL with "mismatched ACL root close";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_ACL with "invalid ACL closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Access_Control_Policy
   is
      Handler : aliased ACL_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_ACL with "incomplete ACL document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_ACL with "malformed ACL XML";
   end Parse;

end Flyology.Object_Storage.S3.ACL;
