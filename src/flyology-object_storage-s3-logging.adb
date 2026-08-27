with Ada.Exceptions;

package body Flyology.Object_Storage.S3.Logging is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container,
      Root_Container,
      Logging_Container,
      Grants_Container,
      Grant_Container,
      Grantee_Container,
      Key_Format_Container,
      Simple_Prefix_Container,
      Partitioned_Prefix_Container);
   type Scalar_Kind is
     (No_Scalar,
      Target_Bucket_Scalar,
      Target_Prefix_Scalar,
      Permission_Scalar,
      Display_Name_Scalar,
      Email_Address_Scalar,
      ID_Scalar,
      URI_Scalar,
      Partition_Date_Source_Scalar);

   function Empty_Grant return Target_Grant is
     --  Full_Control is parser scratch from the pinned permission domain;
     --  Is_Set prevents it from representing an absent permission.
     ((Principal => (others => <>),
       Permission => (Is_Set => False, Value => Full_Control)));

   function Empty_Status return Logging_Status is
     --  Event_Time is parser scratch from the pinned date-source domain;
     --  presence flags prevent it from representing an absent format value.
     ((Is_Enabled    => False,
       Target_Bucket => US.Null_Unbounded_String,
       Grants        =>
         (Is_Set => False, Grants => Target_Grant_Vectors.Empty_Vector),
       Target_Prefix => US.Null_Unbounded_String,
       Key_Format    =>
         (Is_Set             => False,
          Simple_Prefix      => False,
          Partitioned_Prefix => False,
          Date_Source        => (Is_Set => False, Value => Event_Time))));

   type Logging_Handler is new S3.XML.Event_Handler with record
      Depth                  : Natural := 0;
      Root_Seen              : Boolean := False;
      Logging_Seen           : Boolean := False;
      Target_Bucket_Seen     : Boolean := False;
      Grants_Seen            : Boolean := False;
      Target_Prefix_Seen     : Boolean := False;
      Key_Format_Seen        : Boolean := False;
      Simple_Prefix_Seen     : Boolean := False;
      Partitioned_Seen       : Boolean := False;
      Partition_Date_Seen    : Boolean := False;
      Grantee_Seen           : Boolean := False;
      Permission_Seen        : Boolean := False;
      Display_Name_Seen      : Boolean := False;
      Email_Address_Seen     : Boolean := False;
      ID_Seen                : Boolean := False;
      URI_Seen               : Boolean := False;
      Attribute_Count        : Natural := 0;
      Pending_Type_Seen      : Boolean := False;
      Namespace              : Namespace_Style := Namespace_Not_Selected;
      Container              : Container_Kind := No_Container;
      Scalar                 : Scalar_Kind := No_Scalar;
      Text_Value             : US.Unbounded_String;
      Current_Grant          : Target_Grant := Empty_Grant;
      Value                  : Logging_Status := Empty_Status;
   end record;

   overriding procedure Start_Element
     (Item : in out Logging_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Logging_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Element_Attribute
     (Item               : in out Logging_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String);
   overriding procedure Text
     (Item : in out Logging_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Logging_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Logging with "text outside logging scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Logging_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  S3 REST/XML namespace is an external wire value. Accepting another
      --  element namespace would change the qualified response contract.
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
         raise Malformed_Logging with "logging namespace is invalid";
      end if;
      Item.Namespace := Style;
      Item.Attribute_Count := Attribute_Count;
      Item.Pending_Type_Seen := False;
   end Start_Element_Details;

   procedure Set_Grantee_Type
     (Item : in out Logging_Handler; Value : String) is
   begin
      if Value = "CanonicalUser" then
         Item.Current_Grant.Principal.Kind := S3.ACL.Canonical_User;
      elsif Value = "AmazonCustomerByEmail" then
         Item.Current_Grant.Principal.Kind :=
           S3.ACL.Amazon_Customer_By_Email;
      elsif Value = "Group" then
         Item.Current_Grant.Principal.Kind := S3.ACL.Group_Grantee;
      else
         raise Malformed_Logging with "invalid logging grantee type";
      end if;
   end Set_Grantee_Type;

   overriding procedure Element_Attribute
     (Item               : in out Logging_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String) is
   begin
      --  The shared S3 Grantee shape requires exactly xsi:type in the W3C
      --  XML Schema-instance namespace.
      if Element_Local_Name /= "Grantee"
        or else Namespace_URI /=
          "http://www.w3.org/2001/XMLSchema-instance"
        or else Local_Name /= "type"
        or else Item.Pending_Type_Seen
      then
         raise Malformed_Logging with "invalid logging attribute";
      end if;
      Set_Grantee_Type (Item, Value);
      Item.Pending_Type_Seen := True;
   end Element_Attribute;

   procedure Begin_Scalar
     (Item : in out Logging_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Reset_Grant (Item : in out Logging_Handler) is
   begin
      Item.Grantee_Seen := False;
      Item.Permission_Seen := False;
      Item.Display_Name_Seen := False;
      Item.Email_Address_Seen := False;
      Item.ID_Seen := False;
      Item.URI_Seen := False;
      Item.Current_Grant := Empty_Grant;
   end Reset_Grant;

   overriding procedure Start_Element
     (Item : in out Logging_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Logging with "logging depth overflow";
      elsif Item.Scalar /= No_Scalar then
         raise Malformed_Logging with "logging scalar contains element";
      end if;
      Item.Depth := Item.Depth + 1;

      if (Local_Name = "Grantee"
          and then (Item.Attribute_Count /= 1
                    or else not Item.Pending_Type_Seen))
        or else (Local_Name /= "Grantee" and then Item.Attribute_Count /= 0)
      then
         raise Malformed_Logging with
           "logging attributes violate pinned schema";
      end if;

      case Item.Depth is
         when 1 =>
            if Item.Root_Seen or else Local_Name /= "BucketLoggingStatus" then
               raise Malformed_Logging with "invalid logging root";
            end if;
            Item.Root_Seen := True;
            Item.Container := Root_Container;

         when 2 =>
            if Item.Container /= Root_Container
              or else Local_Name /= "LoggingEnabled"
              or else Item.Logging_Seen
            then
               raise Malformed_Logging with
                 "unknown or duplicate logging member";
            end if;
            Item.Logging_Seen := True;
            Item.Value.Is_Enabled := True;
            Item.Container := Logging_Container;

         when 3 =>
            if Item.Container /= Logging_Container then
               raise Malformed_Logging with "logging member outside status";
            elsif Local_Name = "TargetBucket"
              and then not Item.Target_Bucket_Seen
            then
               Item.Target_Bucket_Seen := True;
               Begin_Scalar (Item, Target_Bucket_Scalar);
            elsif Local_Name = "TargetGrants" and then not Item.Grants_Seen
            then
               Item.Grants_Seen := True;
               Item.Value.Grants.Is_Set := True;
               Item.Container := Grants_Container;
            elsif Local_Name = "TargetPrefix"
              and then not Item.Target_Prefix_Seen
            then
               Item.Target_Prefix_Seen := True;
               Begin_Scalar (Item, Target_Prefix_Scalar);
            elsif Local_Name = "TargetObjectKeyFormat"
              and then not Item.Key_Format_Seen
            then
               Item.Key_Format_Seen := True;
               Item.Value.Key_Format.Is_Set := True;
               Item.Container := Key_Format_Container;
            else
               raise Malformed_Logging with
                 "unknown or duplicate LoggingEnabled member";
            end if;

         when 4 =>
            if Item.Container = Grants_Container
              and then Local_Name = "Grant"
            then
               Reset_Grant (Item);
               Item.Container := Grant_Container;
            elsif Item.Container = Key_Format_Container
              and then Local_Name = "SimplePrefix"
              and then not Item.Simple_Prefix_Seen
            then
               Item.Simple_Prefix_Seen := True;
               Item.Value.Key_Format.Simple_Prefix := True;
               Item.Container := Simple_Prefix_Container;
            elsif Item.Container = Key_Format_Container
              and then Local_Name = "PartitionedPrefix"
              and then not Item.Partitioned_Seen
            then
               Item.Partitioned_Seen := True;
               Item.Value.Key_Format.Partitioned_Prefix := True;
               Item.Container := Partitioned_Prefix_Container;
            else
               raise Malformed_Logging with
                 "unknown logging grant or key-format member";
            end if;

         when 5 =>
            if Item.Container = Grant_Container
              and then Local_Name = "Grantee"
              and then not Item.Grantee_Seen
            then
               Item.Grantee_Seen := True;
               Item.Current_Grant.Principal.Is_Set := True;
               Item.Container := Grantee_Container;
            elsif Item.Container = Grant_Container
              and then Local_Name = "Permission"
              and then not Item.Permission_Seen
            then
               Item.Permission_Seen := True;
               Begin_Scalar (Item, Permission_Scalar);
            elsif Item.Container = Partitioned_Prefix_Container
              and then Local_Name = "PartitionDateSource"
              and then not Item.Partition_Date_Seen
            then
               Item.Partition_Date_Seen := True;
               Begin_Scalar (Item, Partition_Date_Source_Scalar);
            else
               raise Malformed_Logging with
                 "unknown or duplicate nested logging member";
            end if;

         when 6 =>
            if Item.Container /= Grantee_Container then
               raise Malformed_Logging with "member outside logging Grantee";
            elsif Local_Name = "DisplayName"
              and then not Item.Display_Name_Seen
            then
               Item.Display_Name_Seen := True;
               Begin_Scalar (Item, Display_Name_Scalar);
            elsif Local_Name = "EmailAddress"
              and then not Item.Email_Address_Seen
            then
               Item.Email_Address_Seen := True;
               Begin_Scalar (Item, Email_Address_Scalar);
            elsif Local_Name = "ID" and then not Item.ID_Seen then
               Item.ID_Seen := True;
               Begin_Scalar (Item, ID_Scalar);
            elsif Local_Name = "URI" and then not Item.URI_Seen then
               Item.URI_Seen := True;
               Begin_Scalar (Item, URI_Scalar);
            else
               raise Malformed_Logging with
                 "unknown or duplicate logging Grantee member";
            end if;

         when others =>
            raise Malformed_Logging with "nested logging member";
      end case;
      Item.Attribute_Count := 0;
   end Start_Element;

   overriding procedure Text
     (Item : in out Logging_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth > 0 then
         Require_Whitespace (Value);
      else
         raise Malformed_Logging with "logging text outside document";
      end if;
   end Text;

   procedure Store_Scalar (Item : in out Logging_Handler) is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when Target_Bucket_Scalar =>
            Item.Value.Target_Bucket := Item.Text_Value;
         when Target_Prefix_Scalar =>
            Item.Value.Target_Prefix := Item.Text_Value;
         when Permission_Scalar =>
            Item.Current_Grant.Permission.Is_Set := True;
            if Value = "FULL_CONTROL" then
               Item.Current_Grant.Permission.Value := Full_Control;
            elsif Value = "READ" then
               Item.Current_Grant.Permission.Value := Read;
            elsif Value = "WRITE" then
               Item.Current_Grant.Permission.Value := Write;
            else
               raise Malformed_Logging with "invalid logging permission";
            end if;
         when Display_Name_Scalar =>
            Item.Current_Grant.Principal.Display_Name :=
              (Is_Set => True, Value => Item.Text_Value);
         when Email_Address_Scalar =>
            Item.Current_Grant.Principal.Email_Address :=
              (Is_Set => True, Value => Item.Text_Value);
         when ID_Scalar =>
            Item.Current_Grant.Principal.ID :=
              (Is_Set => True, Value => Item.Text_Value);
         when URI_Scalar =>
            Item.Current_Grant.Principal.URI :=
              (Is_Set => True, Value => Item.Text_Value);
         when Partition_Date_Source_Scalar =>
            Item.Value.Key_Format.Date_Source.Is_Set := True;
            if Value = "EventTime" then
               Item.Value.Key_Format.Date_Source.Value := Event_Time;
            elsif Value = "DeliveryTime" then
               Item.Value.Key_Format.Date_Source.Value := Delivery_Time;
            else
               raise Malformed_Logging with
                 "invalid logging partition date source";
            end if;
         when No_Scalar =>
            null;
      end case;
   end Store_Scalar;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when Target_Bucket_Scalar => "TargetBucket",
         when Target_Prefix_Scalar => "TargetPrefix",
         when Permission_Scalar => "Permission",
         when Display_Name_Scalar => "DisplayName",
         when Email_Address_Scalar => "EmailAddress",
         when ID_Scalar => "ID",
         when URI_Scalar => "URI",
         when Partition_Date_Source_Scalar => "PartitionDateSource",
         when No_Scalar => "");

   overriding procedure End_Element
     (Item : in out Logging_Handler; Local_Name : String) is
   begin
      if Item.Depth = 0 then
         raise Malformed_Logging with "logging close outside document";
      elsif Item.Scalar /= No_Scalar then
         if Local_Name /= Scalar_Name (Item.Scalar) then
            raise Malformed_Logging with "mismatched logging scalar";
         end if;
         Store_Scalar (Item);
         Item.Scalar := No_Scalar;
         Item.Text_Value := US.Null_Unbounded_String;
      else
         case Item.Depth is
            when 6 =>
               if Item.Container /= Grantee_Container then
                  raise Malformed_Logging with "invalid logging close";
               end if;
            when 5 =>
               if Local_Name = "Grantee"
                 and then Item.Container = Grantee_Container
               then
                  Item.Container := Grant_Container;
               else
                  raise Malformed_Logging with "invalid nested logging close";
               end if;
            when 4 =>
               if Local_Name = "Grant"
                 and then Item.Container = Grant_Container
               then
                  Item.Value.Grants.Grants.Append (Item.Current_Grant);
                  Item.Container := Grants_Container;
               elsif Local_Name = "SimplePrefix"
                 and then Item.Container = Simple_Prefix_Container
               then
                  Item.Container := Key_Format_Container;
               elsif Local_Name = "PartitionedPrefix"
                 and then Item.Container = Partitioned_Prefix_Container
               then
                  Item.Container := Key_Format_Container;
               else
                  raise Malformed_Logging with
                    "invalid logging container close";
               end if;
            when 3 =>
               if Local_Name = "TargetGrants"
                 and then Item.Container = Grants_Container
               then
                  Item.Container := Logging_Container;
               elsif Local_Name = "TargetObjectKeyFormat"
                 and then Item.Container = Key_Format_Container
               then
                  Item.Container := Logging_Container;
               else
                  raise Malformed_Logging with
                    "invalid logging member close";
               end if;
            when 2 =>
               if Local_Name /= "LoggingEnabled"
                 or else Item.Container /= Logging_Container
                 or else not Item.Target_Bucket_Seen
                 or else not Item.Target_Prefix_Seen
               then
                  raise Malformed_Logging with
                    "incomplete LoggingEnabled member";
               end if;
               Item.Container := Root_Container;
            when 1 =>
               if Local_Name /= "BucketLoggingStatus"
                 or else Item.Container /= Root_Container
               then
                  raise Malformed_Logging with "invalid logging root close";
               end if;
               Item.Container := No_Container;
            when others =>
               raise Malformed_Logging with "invalid logging depth";
         end case;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse
     (Document : String; Limits : S3.XML.Parse_Limits)
      return Logging_Status
   is
      Handler : aliased Logging_Handler;
   begin
      S3.XML.Parse (Document, Handler, Limits);
      if not Handler.Root_Seen
        or else Handler.Depth /= 0
        or else Handler.Container /= No_Container
      then
         raise Malformed_Logging with "incomplete logging document";
      end if;
      return Handler.Value;
   exception
      when Error : S3.XML.XML_Error =>
         raise Malformed_Logging with
           "malformed logging XML: "
           & Ada.Exceptions.Exception_Message (Error);
   end Parse;

end Flyology.Object_Storage.S3.Logging;
