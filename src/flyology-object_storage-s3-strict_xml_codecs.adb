with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body Flyology.Object_Storage.S3.Strict_XML_Codecs is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);

   type Seen_Set is array (Element_Id) of Boolean;
   type Count_Set is array (Element_Id) of Natural;

   type Frame is record
      Element : Element_Id;
      Seen    : Seen_Set := (others => False);
      Counts  : Count_Set := (others => 0);
   end record;

   package Frame_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Frame);

   type Pending_Attribute is record
      Namespace_URI : US.Unbounded_String;
      Local_Name    : US.Unbounded_String;
      Value         : US.Unbounded_String;
   end record;

   package Attribute_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Pending_Attribute);

   function Child
     (Owner      : Element_Id;
      Local_Name : String;
      Attribute  : Boolean) return Element_Id
   is
   begin
      for Candidate in Element_Id loop
         if Candidate /= No_Element
           and then Parent (Candidate) = Owner
           and then Is_Attribute (Candidate) = Attribute
           and then Element_Name (Candidate) = Local_Name
         then
            return Candidate;
         end if;
      end loop;
      return No_Element;
   end Child;

   function Valid_Integer (Value : String) return Boolean is
      First : Integer := Value'First;
   begin
      if Value'Length = 0 then
         return False;
      elsif Value (First) = '-' then
         First := First + 1;
         if First > Value'Last then
            return False;
         end if;
      end if;
      for Index in First .. Value'Last loop
         if Value (Index) not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Integer;

   --  Pinned Botocore timestamp shapes use the established S3 ISO-8601 wire
   --  grammar: a calendar date and time, optional 1..9 fractional digits,
   --  and either Z or an explicit numeric offset.
   function Valid_ISO_8601_Timestamp (Value : String) return Boolean is
      Text : constant String (1 .. Value'Length) := Value;

      function Decimal (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               return Natural'Last;
            end if;
            Result := Result * 10
              + Character'Pos (Text (Index)) - Character'Pos ('0');
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

   procedure Validate_Scalar (Element : Element_Id; Value : String) is
      Found : Boolean := Enumeration_Count (Element) = 0;
   begin
      if Value'Length < Minimum_Length (Element)
        or else (Has_Maximum_Length (Element)
                 and then Value'Length > Maximum_Length (Element))
      then
         raise Malformed_Document with "modeled scalar length is invalid";
      elsif Is_Boolean (Element)
        and then Value /= "true"
        and then Value /= "false"
      then
         raise Malformed_Document with "invalid modeled boolean";
      elsif Is_Integer (Element) and then not Valid_Integer (Value) then
         raise Malformed_Document with "invalid modeled integer";
      elsif Is_Timestamp (Element)
        and then not Valid_ISO_8601_Timestamp (Value)
      then
         raise Malformed_Document with "invalid modeled timestamp";
      end if;
      for Index in 1 .. Enumeration_Count (Element) loop
         if Value = Enumeration_Value (Element, Index) then
            Found := True;
         end if;
      end loop;
      if not Found then
         raise Malformed_Document with "invalid modeled enumeration";
      elsif not Matches_Pattern (Element, Value) then
         raise Malformed_Document with "invalid modeled string pattern";
      end if;
   end Validate_Scalar;

   type Result_Access is access all Result_Type;

   type Wire_Handler is new XML.Event_Handler with record
      Target             : Result_Access;
      Collection_Limit   : Positive;
      Namespace          : Namespace_Style := Namespace_Not_Selected;
      Frames             : Frame_Vectors.Vector;
      Pending_Attributes : Attribute_Vectors.Vector;
      Text_Value         : US.Unbounded_String;
   end record;

   overriding procedure Start_Element
     (Item : in out Wire_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Wire_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Element_Attribute
     (Item               : in out Wire_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String);
   overriding procedure Text
     (Item : in out Wire_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Wire_Handler; Local_Name : String);

   procedure Select_Namespace
     (Item : in out Wire_Handler; Namespace_URI : String)
   is
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
         raise Malformed_Document with "invalid XML namespace";
      end if;
      Item.Namespace := Style;
   end Select_Namespace;

   overriding procedure Start_Element_Details
     (Item            : in out Wire_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural) is
   begin
      Select_Namespace (Item, Namespace_URI);
      Item.Pending_Attributes.Clear;
      if Attribute_Count > Item.Collection_Limit then
         raise Malformed_Document with "attribute collection limit exceeded";
      end if;
   end Start_Element_Details;

   overriding procedure Element_Attribute
     (Item               : in out Wire_Handler;
      Element_Local_Name : String;
      Namespace_URI      : String;
      Local_Name         : String;
      Value              : String)
   is
      pragma Unreferenced (Element_Local_Name);
   begin
      Item.Pending_Attributes.Append
        (Pending_Attribute'
           (Namespace_URI => US.To_Unbounded_String (Namespace_URI),
            Local_Name    => US.To_Unbounded_String (Local_Name),
            Value         => US.To_Unbounded_String (Value)));
   end Element_Attribute;

   procedure Mark
     (Item : in out Wire_Handler; Element : Element_Id) is
      Owner : Frame := Item.Frames.Last_Element;
   begin
      if Owner.Seen (Element) and then not Is_Repeated (Element) then
         raise Malformed_Document with "duplicate singleton member";
      end if;
      Owner.Seen (Element) := True;
      if Is_Repeated (Element) then
         if Owner.Counts (Element) = Item.Collection_Limit then
            raise Malformed_Document with "collection limit exceeded";
         end if;
         Owner.Counts (Element) := Owner.Counts (Element) + 1;
      end if;
      Item.Frames.Replace_Element (Item.Frames.Last_Index, Owner);
   end Mark;

   procedure Read_Attributes
     (Item : in out Wire_Handler; Owner : Element_Id) is
   begin
      for Attribute of Item.Pending_Attributes loop
         declare
            Name    : constant String := US.To_String (Attribute.Local_Name);
            Element : constant Element_Id := Child (Owner, Name, True);
            URI     : constant String :=
              US.To_String (Attribute.Namespace_URI);
            Value   : constant String := US.To_String (Attribute.Value);
         begin
            if Element = No_Element
              or else URI /= Attribute_Namespace (Element)
            then
               raise Malformed_Document with "unexpected XML attribute";
            end if;
            Mark (Item, Element);
            Validate_Scalar (Element, Value);
            Set_Scalar (Item.Target.all, Element, Value);
         end;
      end loop;
      Item.Pending_Attributes.Clear;
   end Read_Attributes;

   overriding procedure Start_Element
     (Item : in out Wire_Handler; Local_Name : String)
   is
      Element : Element_Id;
   begin
      if Item.Frames.Is_Empty then
         Element := Root_Element;
         if Local_Name /= Element_Name (Root_Element) then
            raise Malformed_Document with "invalid XML root";
         end if;
      else
         if Is_Scalar (Item.Frames.Last_Element.Element) then
            raise Malformed_Document with "scalar contains an element";
         end if;
         Element := Child
           (Item.Frames.Last_Element.Element, Local_Name, False);
         if Element = No_Element then
            raise Malformed_Document with "unknown XML member";
         end if;
         Mark (Item, Element);
      end if;
      Item.Frames.Append
        (Frame'
           (Element => Element,
            Seen    => (others => False),
            Counts  => (others => 0)));
      Start_Node (Item.Target.all, Element);
      Read_Attributes (Item, Element);
      Item.Text_Value := US.Null_Unbounded_String;
   end Start_Element;

   overriding procedure Text
     (Item : in out Wire_Handler; Value : String) is
   begin
      if not Item.Frames.Is_Empty
        and then Is_Scalar (Item.Frames.Last_Element.Element)
      then
         US.Append (Item.Text_Value, Value);
      else
         for Character of Value loop
            if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
               raise Malformed_Document with "text outside modeled scalar";
            end if;
         end loop;
      end if;
   end Text;

   procedure Check_Required (Value : Frame) is
   begin
      for Element in Element_Id loop
         if Element /= No_Element
           and then Parent (Element) = Value.Element
           and then Is_Required (Element)
           and then not Value.Seen (Element)
         then
            raise Malformed_Document with "missing required XML member";
         end if;
      end loop;
   end Check_Required;

   overriding procedure End_Element
     (Item : in out Wire_Handler; Local_Name : String)
   is
      Value : Frame;
   begin
      if Item.Frames.Is_Empty then
         raise Malformed_Document with "XML stack underflow";
      end if;
      Value := Item.Frames.Last_Element;
      if Local_Name /= Element_Name (Value.Element) then
         raise Malformed_Document with "mismatched XML close";
      end if;
      Check_Required (Value);
      if Is_Scalar (Value.Element) then
         declare
            Text : constant String := US.To_String (Item.Text_Value);
         begin
            Validate_Scalar (Value.Element, Text);
            Set_Scalar (Item.Target.all, Value.Element, Text);
         end;
      end if;
      End_Node (Item.Target.all, Value.Element);
      Item.Frames.Delete_Last;
      Item.Text_Value := US.Null_Unbounded_String;
   end End_Element;

   procedure Parse
     (Document         : String;
      Limits           : XML.Parse_Limits;
      Collection_Limit : Positive;
      Result           : aliased in out Result_Type)
   is
      Handler : aliased Wire_Handler :=
        (XML.Event_Handler with
         Target             => Result'Unchecked_Access,
         Collection_Limit   => Collection_Limit,
         Namespace          => Namespace_Not_Selected,
         Frames             => <>,
         Pending_Attributes => <>,
         Text_Value         => <>);
   begin
      XML.Parse (Document, Handler, Limits);
      if not Handler.Frames.Is_Empty then
         raise Malformed_Document with "incomplete XML document";
      end if;
   exception
      when XML.XML_Error =>
         raise Malformed_Document with "malformed XML document";
   end Parse;

end Flyology.Object_Storage.S3.Strict_XML_Codecs;
