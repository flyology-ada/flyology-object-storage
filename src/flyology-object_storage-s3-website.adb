package body Flyology.Object_Storage.S3.Website is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container,
      Root_Container,
      Redirect_All_Container,
      Index_Container,
      Error_Container,
      Rules_Container,
      Rule_Container,
      Condition_Container,
      Redirect_Container);
   type Scalar_Kind is
     (No_Scalar,
      Redirect_All_Host_Scalar,
      Redirect_All_Protocol_Scalar,
      Index_Suffix_Scalar,
      Error_Key_Scalar,
      Condition_Error_Code_Scalar,
      Condition_Key_Prefix_Scalar,
      Redirect_Host_Scalar,
      Redirect_Code_Scalar,
      Redirect_Protocol_Scalar,
      Redirect_Replace_Prefix_Scalar,
      Redirect_Replace_Key_Scalar);

   function Empty_Optional_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Optional_Protocol return Optional_Protocol is
     --  HTTP is parser scratch from the exact pinned enum; Is_Set prevents it
     --  from representing an absent Protocol member.
     ((Is_Set => False, Value => HTTP));

   function Empty_Rule return Routing_Rule is
     ((Condition =>
         (Is_Set          => False,
          HTTP_Error_Code => Empty_Optional_String,
          Key_Prefix      => Empty_Optional_String),
       Redirect  =>
         (Host_Name          => Empty_Optional_String,
          HTTP_Redirect_Code => Empty_Optional_String,
          Scheme             => Empty_Optional_Protocol,
          Replace_Key_Prefix => Empty_Optional_String,
          Replace_Key        => Empty_Optional_String)));

   function Empty_Configuration return Website_Configuration is
     ((Redirect_All =>
         (Is_Set    => False,
          Host_Name => US.Null_Unbounded_String,
          Scheme    => Empty_Optional_Protocol),
       Index        =>
         (Is_Set => False, Suffix => US.Null_Unbounded_String),
       Error        =>
         (Is_Set => False, Key => US.Null_Unbounded_String),
       Routes       =>
         (Is_Set => False, Rules => Routing_Rule_Vectors.Empty_Vector)));

   type Website_Handler is new S3.XML.Event_Handler with record
      Depth                       : Natural := 0;
      Root_Seen                   : Boolean := False;
      Redirect_All_Seen           : Boolean := False;
      Index_Seen                  : Boolean := False;
      Error_Seen                  : Boolean := False;
      Rules_Seen                  : Boolean := False;
      Redirect_All_Host_Seen      : Boolean := False;
      Redirect_All_Protocol_Seen  : Boolean := False;
      Index_Suffix_Seen           : Boolean := False;
      Error_Key_Seen              : Boolean := False;
      Rule_Condition_Seen         : Boolean := False;
      Rule_Redirect_Seen          : Boolean := False;
      Condition_Error_Code_Seen   : Boolean := False;
      Condition_Key_Prefix_Seen   : Boolean := False;
      Redirect_Host_Seen          : Boolean := False;
      Redirect_Code_Seen          : Boolean := False;
      Redirect_Protocol_Seen      : Boolean := False;
      Redirect_Replace_Prefix_Seen : Boolean := False;
      Redirect_Replace_Key_Seen   : Boolean := False;
      Namespace                   : Namespace_Style := Namespace_Not_Selected;
      Container                   : Container_Kind := No_Container;
      Scalar                      : Scalar_Kind := No_Scalar;
      Text_Value                  : US.Unbounded_String;
      Current_Rule                : Routing_Rule := Empty_Rule;
      Value                       : Website_Configuration :=
        Empty_Configuration;
   end record;

   overriding procedure Start_Element
     (Item : in out Website_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Website_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Website_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Website_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Website with "text outside website scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Website_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  The S3 REST/XML namespace is the external wire authority. Accepting
      --  another element namespace or attributes would change compatibility.
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
         raise Malformed_Website with
           "website namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Website_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Reset_Rule (Item : in out Website_Handler) is
   begin
      Item.Rule_Condition_Seen := False;
      Item.Rule_Redirect_Seen := False;
      Item.Condition_Error_Code_Seen := False;
      Item.Condition_Key_Prefix_Seen := False;
      Item.Redirect_Host_Seen := False;
      Item.Redirect_Code_Seen := False;
      Item.Redirect_Protocol_Seen := False;
      Item.Redirect_Replace_Prefix_Seen := False;
      Item.Redirect_Replace_Key_Seen := False;
      Item.Current_Rule := Empty_Rule;
   end Reset_Rule;

   overriding procedure Start_Element
     (Item : in out Website_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Website with "website depth overflow";
      elsif Item.Scalar /= No_Scalar then
         raise Malformed_Website with "website scalar contains element";
      end if;
      Item.Depth := Item.Depth + 1;

      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "WebsiteConfiguration"
            then
               raise Malformed_Website with "invalid website root";
            end if;
            Item.Root_Seen := True;
            Item.Container := Root_Container;

         when 2 =>
            if Item.Container /= Root_Container then
               raise Malformed_Website with "website member outside root";
            elsif Local_Name = "RedirectAllRequestsTo"
              and then not Item.Redirect_All_Seen
            then
               Item.Redirect_All_Seen := True;
               Item.Value.Redirect_All.Is_Set := True;
               Item.Container := Redirect_All_Container;
            elsif Local_Name = "IndexDocument" and then not Item.Index_Seen
            then
               Item.Index_Seen := True;
               Item.Value.Index.Is_Set := True;
               Item.Container := Index_Container;
            elsif Local_Name = "ErrorDocument" and then not Item.Error_Seen
            then
               Item.Error_Seen := True;
               Item.Value.Error.Is_Set := True;
               Item.Container := Error_Container;
            elsif Local_Name = "RoutingRules" and then not Item.Rules_Seen
            then
               Item.Rules_Seen := True;
               Item.Value.Routes.Is_Set := True;
               Item.Container := Rules_Container;
            else
               raise Malformed_Website with
                 "unknown or duplicate website member";
            end if;

         when 3 =>
            if Item.Container = Redirect_All_Container then
               if Local_Name = "HostName"
                 and then not Item.Redirect_All_Host_Seen
               then
                  Item.Redirect_All_Host_Seen := True;
                  Begin_Scalar (Item, Redirect_All_Host_Scalar);
               elsif Local_Name = "Protocol"
                 and then not Item.Redirect_All_Protocol_Seen
               then
                  Item.Redirect_All_Protocol_Seen := True;
                  Begin_Scalar (Item, Redirect_All_Protocol_Scalar);
               else
                  raise Malformed_Website with
                    "unknown or duplicate whole-site redirect member";
               end if;
            elsif Item.Container = Index_Container
              and then Local_Name = "Suffix"
              and then not Item.Index_Suffix_Seen
            then
               Item.Index_Suffix_Seen := True;
               Begin_Scalar (Item, Index_Suffix_Scalar);
            elsif Item.Container = Error_Container
              and then Local_Name = "Key"
              and then not Item.Error_Key_Seen
            then
               Item.Error_Key_Seen := True;
               Begin_Scalar (Item, Error_Key_Scalar);
            elsif Item.Container = Rules_Container
              and then Local_Name = "RoutingRule"
            then
               Reset_Rule (Item);
               Item.Container := Rule_Container;
            else
               raise Malformed_Website with
                 "unknown website nested member";
            end if;

         when 4 =>
            if Item.Container /= Rule_Container then
               raise Malformed_Website with "website nesting exceeds model";
            elsif Local_Name = "Condition"
              and then not Item.Rule_Condition_Seen
            then
               Item.Rule_Condition_Seen := True;
               Item.Current_Rule.Condition.Is_Set := True;
               Item.Container := Condition_Container;
            elsif Local_Name = "Redirect"
              and then not Item.Rule_Redirect_Seen
            then
               Item.Rule_Redirect_Seen := True;
               Item.Container := Redirect_Container;
            else
               raise Malformed_Website with
                 "unknown or duplicate routing-rule member";
            end if;

         when 5 =>
            if Item.Container = Condition_Container then
               if Local_Name = "HttpErrorCodeReturnedEquals"
                 and then not Item.Condition_Error_Code_Seen
               then
                  Item.Condition_Error_Code_Seen := True;
                  Begin_Scalar (Item, Condition_Error_Code_Scalar);
               elsif Local_Name = "KeyPrefixEquals"
                 and then not Item.Condition_Key_Prefix_Seen
               then
                  Item.Condition_Key_Prefix_Seen := True;
                  Begin_Scalar (Item, Condition_Key_Prefix_Scalar);
               else
                  raise Malformed_Website with
                    "unknown or duplicate routing condition member";
               end if;
            elsif Item.Container = Redirect_Container then
               if Local_Name = "HostName" and then not Item.Redirect_Host_Seen
               then
                  Item.Redirect_Host_Seen := True;
                  Begin_Scalar (Item, Redirect_Host_Scalar);
               elsif Local_Name = "HttpRedirectCode"
                 and then not Item.Redirect_Code_Seen
               then
                  Item.Redirect_Code_Seen := True;
                  Begin_Scalar (Item, Redirect_Code_Scalar);
               elsif Local_Name = "Protocol"
                 and then not Item.Redirect_Protocol_Seen
               then
                  Item.Redirect_Protocol_Seen := True;
                  Begin_Scalar (Item, Redirect_Protocol_Scalar);
               elsif Local_Name = "ReplaceKeyPrefixWith"
                 and then not Item.Redirect_Replace_Prefix_Seen
               then
                  Item.Redirect_Replace_Prefix_Seen := True;
                  Begin_Scalar (Item, Redirect_Replace_Prefix_Scalar);
               elsif Local_Name = "ReplaceKeyWith"
                 and then not Item.Redirect_Replace_Key_Seen
               then
                  Item.Redirect_Replace_Key_Seen := True;
                  Begin_Scalar (Item, Redirect_Replace_Key_Scalar);
               else
                  raise Malformed_Website with
                    "unknown or duplicate routing redirect member";
               end if;
            else
               raise Malformed_Website with "website nesting exceeds model";
            end if;

         when others =>
            raise Malformed_Website with "website nesting exceeds model";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Website_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 4 then
         Require_Whitespace (Value);
      else
         raise Malformed_Website with "website text outside modeled member";
      end if;
   end Text;

   function Parse_Protocol (Value : String) return Protocol is
   begin
      if Value = "http" then
         return HTTP;
      elsif Value = "https" then
         return HTTPS;
      end if;
      raise Malformed_Website with "invalid website protocol";
   end Parse_Protocol;

   procedure Store_Scalar (Item : in out Website_Handler) is
   begin
      case Item.Scalar is
         when Redirect_All_Host_Scalar =>
            Item.Value.Redirect_All.Host_Name := Item.Text_Value;
         when Redirect_All_Protocol_Scalar =>
            Item.Value.Redirect_All.Scheme :=
              (Is_Set => True,
               Value => Parse_Protocol (US.To_String (Item.Text_Value)));
         when Index_Suffix_Scalar =>
            Item.Value.Index.Suffix := Item.Text_Value;
         when Error_Key_Scalar =>
            if US.Length (Item.Text_Value) = 0 then
               raise Malformed_Website with "empty website error key";
            end if;
            Item.Value.Error.Key := Item.Text_Value;
         when Condition_Error_Code_Scalar =>
            Item.Current_Rule.Condition.HTTP_Error_Code :=
              (Is_Set => True, Value => Item.Text_Value);
         when Condition_Key_Prefix_Scalar =>
            Item.Current_Rule.Condition.Key_Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Redirect_Host_Scalar =>
            Item.Current_Rule.Redirect.Host_Name :=
              (Is_Set => True, Value => Item.Text_Value);
         when Redirect_Code_Scalar =>
            Item.Current_Rule.Redirect.HTTP_Redirect_Code :=
              (Is_Set => True, Value => Item.Text_Value);
         when Redirect_Protocol_Scalar =>
            Item.Current_Rule.Redirect.Scheme :=
              (Is_Set => True,
               Value => Parse_Protocol (US.To_String (Item.Text_Value)));
         when Redirect_Replace_Prefix_Scalar =>
            Item.Current_Rule.Redirect.Replace_Key_Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Redirect_Replace_Key_Scalar =>
            Item.Current_Rule.Redirect.Replace_Key :=
              (Is_Set => True, Value => Item.Text_Value);
         when No_Scalar =>
            raise Malformed_Website with "website close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when Redirect_All_Host_Scalar | Redirect_Host_Scalar => "HostName",
         when Redirect_All_Protocol_Scalar | Redirect_Protocol_Scalar =>
           "Protocol",
         when Index_Suffix_Scalar => "Suffix",
         when Error_Key_Scalar => "Key",
         when Condition_Error_Code_Scalar =>
           "HttpErrorCodeReturnedEquals",
         when Condition_Key_Prefix_Scalar => "KeyPrefixEquals",
         when Redirect_Code_Scalar => "HttpRedirectCode",
         when Redirect_Replace_Prefix_Scalar => "ReplaceKeyPrefixWith",
         when Redirect_Replace_Key_Scalar => "ReplaceKeyWith",
         when No_Scalar => "");

   overriding procedure End_Element
     (Item : in out Website_Handler; Local_Name : String) is
   begin
      case Item.Depth is
         when 5 =>
            if Item.Scalar = No_Scalar
              or else Local_Name /= Scalar_Name (Item.Scalar)
            then
               raise Malformed_Website with
                 "mismatched website routing scalar close";
            end if;
            Store_Scalar (Item);
            Item.Depth := 4;

         when 4 =>
            if Item.Scalar /= No_Scalar then
               raise Malformed_Website with "website scalar at wrong depth";
            elsif Item.Container = Condition_Container
              and then Local_Name = "Condition"
            then
               Item.Container := Rule_Container;
            elsif Item.Container = Redirect_Container
              and then Local_Name = "Redirect"
            then
               Item.Container := Rule_Container;
            else
               raise Malformed_Website with
                 "invalid website rule-member close";
            end if;
            Item.Depth := 3;

         when 3 =>
            if Item.Scalar /= No_Scalar then
               if Local_Name /= Scalar_Name (Item.Scalar) then
                  raise Malformed_Website with
                    "mismatched website configuration scalar close";
               end if;
               Store_Scalar (Item);
            elsif Item.Container = Rule_Container
              and then Local_Name = "RoutingRule"
            then
               if not Item.Rule_Redirect_Seen then
                  raise Malformed_Website with
                    "routing rule lacks required Redirect";
               end if;
               Item.Value.Routes.Rules.Append (Item.Current_Rule);
               Item.Container := Rules_Container;
            else
               raise Malformed_Website with
                 "invalid website nested close";
            end if;
            Item.Depth := 2;

         when 2 =>
            if Item.Container = Redirect_All_Container
              and then Local_Name = "RedirectAllRequestsTo"
            then
               if not Item.Redirect_All_Host_Seen then
                  raise Malformed_Website with
                    "whole-site redirect lacks required HostName";
               end if;
            elsif Item.Container = Index_Container
              and then Local_Name = "IndexDocument"
            then
               if not Item.Index_Suffix_Seen then
                  raise Malformed_Website with
                    "index document lacks required Suffix";
               end if;
            elsif Item.Container = Error_Container
              and then Local_Name = "ErrorDocument"
            then
               if not Item.Error_Key_Seen then
                  raise Malformed_Website with
                    "error document lacks required Key";
               end if;
            elsif Item.Container = Rules_Container
              and then Local_Name = "RoutingRules"
            then
               null;
            else
               raise Malformed_Website with
                 "invalid website top-level member close";
            end if;
            Item.Container := Root_Container;
            Item.Depth := 1;

         when 1 =>
            if Local_Name /= "WebsiteConfiguration" then
               raise Malformed_Website with "invalid website root close";
            end if;
            Item.Container := No_Container;
            Item.Depth := 0;

         when others =>
            raise Malformed_Website with "invalid website closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String; Limits : S3.XML.Parse_Limits)
      return Website_Configuration
   is
      Handler : aliased Website_Handler;
   begin
      S3.XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Website with "incomplete website document";
      end if;
      return Handler.Value;
   exception
      when S3.XML.XML_Error =>
         raise Malformed_Website with "malformed website XML";
   end Parse;

end Flyology.Object_Storage.S3.Website;
