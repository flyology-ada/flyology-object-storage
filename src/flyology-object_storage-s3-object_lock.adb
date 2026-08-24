package body Flyology.Object_Storage.S3.Object_Lock is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified_Namespace, S3_Qualified_Namespace);

   type Legal_Hold_Handler is new XML.Event_Handler with record
      Depth       : Natural := 0;
      Root_Seen   : Boolean := False;
      Status_Seen : Boolean := False;
      Namespace   : Namespace_Style := Namespace_Not_Selected;
      Text_Value  : US.Unbounded_String;
      Value       : Legal_Hold := (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Legal_Hold_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Legal_Hold_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Legal_Hold_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Legal_Hold_Handler; Local_Name : String);

   type Retention_Field is (No_Retention_Field, Mode_Field, Date_Field);

   type Retention_Handler is new XML.Event_Handler with record
      Depth     : Natural := 0;
      Root_Seen : Boolean := False;
      Mode_Seen : Boolean := False;
      Date_Seen : Boolean := False;
      Field     : Retention_Field := No_Retention_Field;
      Namespace : Namespace_Style := Namespace_Not_Selected;
      Text_Value : US.Unbounded_String;
      Value      : Retention := (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Retention_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Retention_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Retention_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Retention_Handler; Local_Name : String);

   type Configuration_Field is
     (No_Configuration_Field, Enabled_Field, Default_Mode_Field,
      Default_Days_Field, Default_Years_Field);

   type Configuration_Handler is new XML.Event_Handler with record
      Depth        : Natural := 0;
      Root_Seen    : Boolean := False;
      Enabled_Seen : Boolean := False;
      Rule_Seen    : Boolean := False;
      Default_Seen : Boolean := False;
      Mode_Seen    : Boolean := False;
      Days_Seen    : Boolean := False;
      Years_Seen   : Boolean := False;
      Field        : Configuration_Field := No_Configuration_Field;
      Namespace    : Namespace_Style := Namespace_Not_Selected;
      Text_Value   : US.Unbounded_String;
      Value        : Object_Lock_Configuration :=
        (Is_Set => True, others => <>);
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

   --  External REST/XML authority from the pinned generated model and S3
   --  protocol namespace; changing these spellings changes compatibility.
   S3_Namespace : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";

   procedure Validate_Element_Details
     (Style           : in out Namespace_Style;
      Namespace_URI   : String;
      Attribute_Count : Natural) is
      Current : constant Namespace_Style :=
        (if Namespace_URI'Length = 0
         then Unqualified_Namespace
         else S3_Qualified_Namespace);
   begin
      if (Namespace_URI'Length > 0
          and then Namespace_URI /= S3_Namespace)
        or else Attribute_Count /= 0
      then
         raise Malformed_Object_Lock with
           "Object Lock namespace or attributes are invalid";
      end if;
      if Style = Namespace_Not_Selected then
         Style := Current;
      elsif Style /= Current then
         raise Malformed_Object_Lock with
           "Object Lock document mixes namespace styles";
      end if;
   end Validate_Element_Details;

   --  The timestamp grammar is the pinned AWS ISO-8601 wire contract.
   --  Calendar ranges, fractional precision, and zone bounds are externally
   --  fixed; accepting another grammar changes Object Lock compatibility.
   function Valid_ISO_8601_Timestamp (Value : String) return Boolean is
      Text : constant String (1 .. Value'Length) := Value;

      function Decimal (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               return Natural'Last;
            end if;
            Result := Result * 10 +
              Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Decimal;

      Year        : Natural;
      Month       : Natural;
      Day         : Natural;
      Hour        : Natural;
      Minute      : Natural;
      Second      : Natural;
      Zone        : Positive := 20;
      Maximum_Day : Natural;
   begin
      if Text'Length not in 20 .. 35
        or else Text (5) /= '-'
        or else Text (8) /= '-'
        or else Text (11) /= 'T'
        or else Text (14) /= ':'
        or else Text (17) /= ':'
      then
         return False;
      end if;
      Year := Decimal (1, 4);
      Month := Decimal (6, 7);
      Day := Decimal (9, 10);
      Hour := Decimal (12, 13);
      Minute := Decimal (15, 16);
      Second := Decimal (18, 19);
      if Year not in 1 .. 9_999
        or else Month not in 1 .. 12
        or else Hour > 23
        or else Minute > 59
        or else Second > 59
      then
         return False;
      end if;
      Maximum_Day :=
        (case Month is
            when 2 =>
              (if Year mod 400 = 0
                 or else (Year mod 4 = 0 and then Year mod 100 /= 0)
               then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
      if Day not in 1 .. Maximum_Day then
         return False;
      end if;
      if Text (Zone) = '.' then
         Zone := Zone + 1;
         declare
            First_Fraction : constant Positive := Zone;
         begin
            while Zone <= Text'Last and then Text (Zone) in '0' .. '9' loop
               Zone := Zone + 1;
            end loop;
            if Zone = First_Fraction or else Zone - First_Fraction > 9 then
               return False;
            end if;
         end;
      end if;
      if Zone = Text'Last and then Text (Zone) = 'Z' then
         return True;
      elsif Zone + 5 = Text'Last
        and then Text (Zone) in '+' | '-'
        and then Text (Zone + 3) = ':'
      then
         declare
            Offset_Hour : constant Natural := Decimal (Zone + 1, Zone + 2);
            Offset_Minute : constant Natural := Decimal (Zone + 4, Zone + 5);
         begin
            return Offset_Hour <= 23 and then Offset_Minute <= 59;
         end;
      end if;
      return False;
   end Valid_ISO_8601_Timestamp;

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

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Object_Lock with
              "text outside Object Lock fields";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Legal_Hold_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      Validate_Element_Details
        (Item.Namespace, Namespace_URI, Attribute_Count);
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Legal_Hold_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Object_Lock with "Object Lock depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "LegalHold" then
            raise Malformed_Object_Lock with "invalid LegalHold root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2 then
         if Local_Name /= "Status" or else Item.Status_Seen then
            raise Malformed_Object_Lock with
              "unknown or duplicate LegalHold field";
         end if;
         Item.Status_Seen := True;
         Item.Text_Value := US.Null_Unbounded_String;
      else
         raise Malformed_Object_Lock with "nested LegalHold field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Legal_Hold_Handler; Value : String) is
   begin
      if Item.Depth = 2 and then Item.Status_Seen then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth = 1 then
         Require_Whitespace (Value);
      else
         raise Malformed_Object_Lock with
           "LegalHold text outside the document root";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Legal_Hold_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      if Item.Depth = 2 then
         if Local_Name /= "Status" then
            raise Malformed_Object_Lock with
              "mismatched LegalHold field close";
         elsif Value = "ON" then
            Item.Value.Status := Legal_Hold_On;
         elsif Value = "OFF" then
            Item.Value.Status := Legal_Hold_Off;
         else
            raise Malformed_Object_Lock with
              "invalid LegalHold status";
         end if;
         Item.Text_Value := US.Null_Unbounded_String;
         Item.Depth := 1;
      elsif Item.Depth = 1 and then Local_Name = "LegalHold" then
         Item.Depth := 0;
      else
         raise Malformed_Object_Lock with
           "invalid LegalHold closing element";
      end if;
   end End_Element;

   function Parse_Legal_Hold
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Legal_Hold
   is
      Handler : aliased Legal_Hold_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Object_Lock with
           "incomplete LegalHold document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Object_Lock with "malformed LegalHold XML";
   end Parse_Legal_Hold;

   function Serialize_Legal_Hold
     (Value  : Legal_Hold;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Result : US.Unbounded_String;
      Status : constant String :=
        (case Value.Status is
            when Legal_Hold_Status_Absent => "",
            when Legal_Hold_On => "ON",
            when Legal_Hold_Off => "OFF");
      --  Pinned shape 476 has one optional Status member.  A present outer
      --  value therefore has one element at depth one, or two elements at
      --  depth two when Status is present.
      Required_Depth : constant Positive :=
        (if Status'Length = 0 then 1 else 2);
      Required_Elements : constant Positive :=
        (if Status'Length = 0 then 1 else 2);
      --  Exact external REST/XML namespace, root, and member spellings from
      --  the pinned PutObjectLegalHold model.
      Prefix : constant String :=
        "<LegalHold xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">";
      Status_Open : constant String := "<Status>";
      Status_Close : constant String := "</Status>";
      Suffix : constant String := "</LegalHold>";

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Object_Lock with
              "LegalHold document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;
   begin
      if not Value.Is_Set then
         if Value.Status /= Legal_Hold_Status_Absent then
            raise Malformed_Object_Lock with
              "absent LegalHold contains a status";
         end if;
         return "";
      elsif Limits.Maximum_Depth < Required_Depth
        or else Limits.Maximum_Elements < Required_Elements
        or else Status'Length > Limits.Maximum_Text_Bytes
      then
         raise Malformed_Object_Lock with
           "LegalHold structure exceeds caller limit";
      end if;

      Append_Bounded (Prefix);
      if Status'Length > 0 then
         Append_Bounded (Status_Open);
         Append_Bounded (Status);
         Append_Bounded (Status_Close);
      end if;
      Append_Bounded (Suffix);
      return US.To_String (Result);
   end Serialize_Legal_Hold;

   overriding procedure Start_Element_Details
     (Item            : in out Retention_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      Validate_Element_Details
        (Item.Namespace, Namespace_URI, Attribute_Count);
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Retention_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Object_Lock with "Object Lock depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "Retention" then
            raise Malformed_Object_Lock with "invalid Retention root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2 then
         if Local_Name = "Mode" and then not Item.Mode_Seen then
            Item.Mode_Seen := True;
            Item.Field := Mode_Field;
         elsif Local_Name = "RetainUntilDate" and then not Item.Date_Seen then
            Item.Date_Seen := True;
            Item.Field := Date_Field;
         else
            raise Malformed_Object_Lock with
              "unknown or duplicate Retention field";
         end if;
         Item.Text_Value := US.Null_Unbounded_String;
      else
         raise Malformed_Object_Lock with "nested Retention field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Retention_Handler; Value : String) is
   begin
      if Item.Depth = 2 and then Item.Field /= No_Retention_Field then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth = 1 then
         Require_Whitespace (Value);
      else
         raise Malformed_Object_Lock with
           "Retention text outside the document root";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Retention_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      if Item.Depth = 2 then
         case Item.Field is
            when Mode_Field =>
               if Local_Name /= "Mode" then
                  raise Malformed_Object_Lock with
                    "mismatched Retention mode close";
               elsif Value = "GOVERNANCE" then
                  Item.Value.Mode := Governance_Retention;
               elsif Value = "COMPLIANCE" then
                  Item.Value.Mode := Compliance_Retention;
               else
                  raise Malformed_Object_Lock with
                    "invalid Retention mode";
               end if;
            when Date_Field =>
               if Local_Name /= "RetainUntilDate"
                 or else not Valid_ISO_8601_Timestamp (Value)
               then
                  raise Malformed_Object_Lock with
                    "invalid Retention date";
               end if;
               Item.Value.Retain_Until_Date := Item.Text_Value;
            when No_Retention_Field =>
               raise Malformed_Object_Lock with
                 "Retention field close without an open field";
         end case;
         Item.Text_Value := US.Null_Unbounded_String;
         Item.Field := No_Retention_Field;
         Item.Depth := 1;
      elsif Item.Depth = 1 and then Local_Name = "Retention" then
         Item.Depth := 0;
      else
         raise Malformed_Object_Lock with
           "invalid Retention closing element";
      end if;
   end End_Element;

   function Parse_Retention
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Retention
   is
      Handler : aliased Retention_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Object_Lock with
           "incomplete Retention document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Object_Lock with "malformed Retention XML";
   end Parse_Retention;

   function Serialize_Retention
     (Value  : Retention;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Result : US.Unbounded_String;
      Mode : constant String :=
        (case Value.Mode is
            when Retention_Mode_Absent => "",
            when Governance_Retention => "GOVERNANCE",
            when Compliance_Retention => "COMPLIANCE");
      Date : constant String := US.To_String (Value.Retain_Until_Date);
      Has_Mode : constant Boolean := Mode'Length > 0;
      Has_Date : constant Boolean := Date'Length > 0;
      --  Pinned shape 480 has two optional scalar children.  A present outer
      --  value therefore has one root and zero, one, or two depth-two fields.
      Required_Depth : constant Positive :=
        (if Has_Mode or else Has_Date then 2 else 1);
      Required_Elements : constant Positive :=
        1 + Boolean'Pos (Has_Mode) + Boolean'Pos (Has_Date);
      Required_Text : constant Natural := Mode'Length + Date'Length;
      --  Exact external REST/XML spellings from pinned shapes 480, 481, and
      --  140.  Changing their order or text changes S3 wire compatibility.
      Prefix : constant String :=
        "<Retention xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">";
      Mode_Open : constant String := "<Mode>";
      Mode_Close : constant String := "</Mode>";
      Date_Open : constant String := "<RetainUntilDate>";
      Date_Close : constant String := "</RetainUntilDate>";
      Suffix : constant String := "</Retention>";

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Object_Lock with
              "Retention document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;
   begin
      if not Value.Is_Set then
         if Has_Mode or else Has_Date then
            raise Malformed_Object_Lock with
              "absent Retention contains nested members";
         end if;
         return "";
      elsif Has_Date and then not Valid_ISO_8601_Timestamp (Date) then
         raise Malformed_Object_Lock with "invalid Retention date";
      elsif Limits.Maximum_Depth < Required_Depth
        or else Limits.Maximum_Elements < Required_Elements
        or else Limits.Maximum_Text_Bytes < Required_Text
      then
         raise Malformed_Object_Lock with
           "Retention structure exceeds caller limit";
      end if;

      Append_Bounded (Prefix);
      if Has_Mode then
         Append_Bounded (Mode_Open);
         Append_Bounded (Mode);
         Append_Bounded (Mode_Close);
      end if;
      if Has_Date then
         Append_Bounded (Date_Open);
         Append_Bounded (Date);
         Append_Bounded (Date_Close);
      end if;
      Append_Bounded (Suffix);
      return US.To_String (Result);
   end Serialize_Retention;

   overriding procedure Start_Element_Details
     (Item            : in out Configuration_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      Validate_Element_Details
        (Item.Namespace, Namespace_URI, Attribute_Count);
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Configuration_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Object_Lock with "Object Lock depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen
              or else Local_Name /= "ObjectLockConfiguration"
            then
               raise Malformed_Object_Lock with
                 "invalid ObjectLockConfiguration root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name = "ObjectLockEnabled"
              and then not Item.Enabled_Seen
            then
               Item.Enabled_Seen := True;
               Item.Field := Enabled_Field;
               Item.Text_Value := US.Null_Unbounded_String;
            elsif Local_Name = "Rule" and then not Item.Rule_Seen then
               Item.Rule_Seen := True;
               Item.Value.Rule.Is_Set := True;
            else
               raise Malformed_Object_Lock with
                 "unknown or duplicate Object Lock configuration field";
            end if;
         when 3 =>
            if Local_Name /= "DefaultRetention"
              or else not Item.Rule_Seen
              or else Item.Default_Seen
              or else Item.Field /= No_Configuration_Field
            then
               raise Malformed_Object_Lock with
                 "invalid Object Lock rule field";
            end if;
            Item.Default_Seen := True;
            Item.Value.Rule.Default_Value.Is_Set := True;
         when 4 =>
            if not Item.Default_Seen
              or else Item.Field /= No_Configuration_Field
            then
               raise Malformed_Object_Lock with
                 "invalid default retention field nesting";
            elsif Local_Name = "Mode" and then not Item.Mode_Seen then
               Item.Mode_Seen := True;
               Item.Field := Default_Mode_Field;
            elsif Local_Name = "Days" and then not Item.Days_Seen then
               Item.Days_Seen := True;
               Item.Field := Default_Days_Field;
            elsif Local_Name = "Years" and then not Item.Years_Seen then
               Item.Years_Seen := True;
               Item.Field := Default_Years_Field;
            else
               raise Malformed_Object_Lock with
                 "unknown or duplicate default retention field";
            end if;
            Item.Text_Value := US.Null_Unbounded_String;
         when others =>
            raise Malformed_Object_Lock with
              "nested Object Lock configuration field";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Configuration_Handler; Value : String) is
   begin
      if (Item.Depth = 2 and then Item.Field = Enabled_Field)
        or else (Item.Depth = 4
                 and then Item.Field /= No_Configuration_Field)
      then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 3 then
         Require_Whitespace (Value);
      else
         raise Malformed_Object_Lock with
           "configuration text outside a modeled field";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Configuration_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Depth is
         when 4 =>
            case Item.Field is
               when Default_Mode_Field =>
                  if Local_Name /= "Mode" then
                     raise Malformed_Object_Lock with
                       "mismatched default retention mode close";
                  elsif Value = "GOVERNANCE" then
                     Item.Value.Rule.Default_Value.Mode :=
                       Governance_Retention;
                  elsif Value = "COMPLIANCE" then
                     Item.Value.Rule.Default_Value.Mode :=
                       Compliance_Retention;
                  else
                     raise Malformed_Object_Lock with
                       "invalid default retention mode";
                  end if;
               when Default_Days_Field | Default_Years_Field =>
                  if (Item.Field = Default_Days_Field
                      and then Local_Name /= "Days")
                    or else (Item.Field = Default_Years_Field
                             and then Local_Name /= "Years")
                    or else not Valid_Integer_Text (Value)
                  then
                     raise Malformed_Object_Lock with
                       "invalid default retention integer";
                  end if;
                  if Item.Field = Default_Days_Field then
                     Item.Value.Rule.Default_Value.Days :=
                       (Is_Set => True, Text => Item.Text_Value);
                  else
                     Item.Value.Rule.Default_Value.Years :=
                       (Is_Set => True, Text => Item.Text_Value);
                  end if;
               when others =>
                  raise Malformed_Object_Lock with
                    "configuration leaf close without an open field";
            end case;
            Item.Field := No_Configuration_Field;
            Item.Text_Value := US.Null_Unbounded_String;
            Item.Depth := 3;
         when 3 =>
            if Local_Name /= "DefaultRetention" then
               raise Malformed_Object_Lock with
                 "mismatched DefaultRetention close";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Item.Field = Enabled_Field then
               if Local_Name /= "ObjectLockEnabled" or else Value /= "Enabled"
               then
                  raise Malformed_Object_Lock with
                    "invalid ObjectLockEnabled value";
               end if;
               Item.Value.Enabled := Object_Lock_Enabled;
               Item.Field := No_Configuration_Field;
               Item.Text_Value := US.Null_Unbounded_String;
            elsif Local_Name /= "Rule" then
               raise Malformed_Object_Lock with
                 "mismatched Object Lock rule close";
            end if;
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "ObjectLockConfiguration" then
               raise Malformed_Object_Lock with
                 "mismatched ObjectLockConfiguration close";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Object_Lock with
              "invalid Object Lock configuration closing element";
      end case;
   end End_Element;

   function Parse_Configuration
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Object_Lock_Configuration
   is
      Handler : aliased Configuration_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Object_Lock with
           "incomplete ObjectLockConfiguration document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Object_Lock with
           "malformed ObjectLockConfiguration XML";
   end Parse_Configuration;

end Flyology.Object_Storage.S3.Object_Lock;
