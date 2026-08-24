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

end Flyology.Object_Storage.S3.Object_Lock;
