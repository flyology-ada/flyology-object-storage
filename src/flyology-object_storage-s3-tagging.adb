with Ada.Containers;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding;
with Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
with Ada.Wide_Wide_Characters.Handling;
with Flyology.Object_Storage.S3.Deletions;

package body Flyology.Object_Storage.S3.Tagging is

   package US renames Ada.Strings.Unbounded;
   package UTF8 renames Ada.Strings.UTF_Encoding.Wide_Wide_Strings;
   package Handling renames Ada.Wide_Wide_Characters.Handling;
   use type Ada.Containers.Count_Type;

   type Field_Kind is (No_Field, Key_Field, Value_Field);

   type Tagging_Handler is new XML.Event_Handler with record
      Tags        : Object_Tag_Set;
      Current     : Object_Tag;
      Text_Value  : US.Unbounded_String;
      Depth       : Natural := 0;
      Field       : Field_Kind := No_Field;
      In_Tag      : Boolean := False;
      Seen_Tag_Set : Boolean := False;
      Seen_Key    : Boolean := False;
      Seen_Value  : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Tagging_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Tagging_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Tagging_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value not in ' ' | Character'Val (9) |
           Character'Val (10) | Character'Val (13)
         then
            raise Malformed_Tagging with "text outside object tag fields";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element
     (Item : in out Tagging_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Tagging with "object tagging XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Local_Name /= "Tagging" then
               raise Malformed_Tagging with "wrong object tagging root";
            end if;
         when 2 =>
            if Local_Name /= "TagSet" or else Item.Seen_Tag_Set then
               raise Malformed_Tagging with "invalid object TagSet";
            end if;
            Item.Seen_Tag_Set := True;
         when 3 =>
            if Local_Name /= "Tag" or else not Item.Seen_Tag_Set
              or else Item.Tags.Length = Maximum_Object_Tags
            then
               raise Malformed_Tagging with "invalid object tag entry";
            end if;
            Item.Current := (others => <>);
            Item.Seen_Key := False;
            Item.Seen_Value := False;
            Item.In_Tag := True;
         when 4 =>
            if not Item.In_Tag then
               raise Malformed_Tagging with "object tag field outside Tag";
            elsif Local_Name = "Key" and then not Item.Seen_Key
              and then not Item.Seen_Value
            then
               Item.Seen_Key := True;
               Item.Field := Key_Field;
            elsif Local_Name = "Value" and then Item.Seen_Key
              and then not Item.Seen_Value
            then
               Item.Seen_Value := True;
               Item.Field := Value_Field;
            else
               raise Malformed_Tagging with "invalid object tag field";
            end if;
            US.Set_Unbounded_String (Item.Text_Value, "");
         when others =>
            raise Malformed_Tagging with "nested object tag field";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Tagging_Handler; Value : String) is
   begin
      if Item.Field = No_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
         if US.Length (Item.Text_Value) > 1_024 then
            raise Malformed_Tagging with "object tag field is too large";
         end if;
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Tagging_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Tagging with "object tagging XML stack underflow";
      elsif Item.Field /= No_Field then
         case Item.Field is
            when Key_Field =>
               Item.Current.Key := Item.Text_Value;
            when Value_Field =>
               Item.Current.Value := Item.Text_Value;
            when No_Field =>
               null;
         end case;
         Item.Field := No_Field;
         US.Set_Unbounded_String (Item.Text_Value, "");
      elsif Item.Depth = 3 and then Item.In_Tag then
         if not Item.Seen_Key or else not Item.Seen_Value then
            raise Malformed_Tagging with "incomplete object tag";
         end if;
         Item.Tags.Length := Item.Tags.Length + 1;
         Item.Tags.Items (Item.Tags.Length) := Item.Current;
         Item.In_Tag := False;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Valid_Character (Item : Wide_Wide_Character) return Boolean is
     (Handling.Is_Letter (Item)
      or else Handling.Is_Digit (Item)
      or else Handling.Is_Space (Item)
      or else Item in '_' | '.' | ':' | '/' | '=' | '+' | '-' | '@');

   function Valid_Field
     (Value : String; Minimum, Maximum : Natural) return Boolean
   is
      Decoded : constant Wide_Wide_String := UTF8.Decode (Value);
   begin
      if Decoded'Length not in Minimum .. Maximum then
         return False;
      end if;
      for Character_Value of Decoded loop
         if not Valid_Character (Character_Value) then
            return False;
         end if;
      end loop;
      return True;
   exception
      when Ada.Strings.UTF_Encoding.Encoding_Error =>
         return False;
   end Valid_Field;

   function Valid_S3_Tags (Tags : Object_Tag_Set) return Boolean is
   begin
      if not Valid_Object_Tag_Set (Tags) then
         return False;
      end if;
      for Index in 1 .. Tags.Length loop
         if not Valid_Field (US.To_String (Tags.Items (Index).Key), 1, 128)
           or else not Valid_Field
             (US.To_String (Tags.Items (Index).Value), 0, 256)
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_S3_Tags;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits) return Object_Tag_Set
   is
      Handler : Tagging_Handler;
   begin
      if Document'Length > Maximum_Document_Bytes then
         raise Malformed_Tagging with "object tagging document is too large";
      end if;
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Tag_Set or else Handler.Depth /= 0
        or else not Valid_S3_Tags (Handler.Tags)
      then
         raise Malformed_Tagging with "invalid object tagging document";
      end if;
      return Handler.Tags;
   exception
      when Malformed_Tagging =>
         raise;
      when others =>
         raise Malformed_Tagging with "malformed object tagging XML";
   end Parse;

   function Serialize (Tags : Object_Tag_Set) return String is
      Result : US.Unbounded_String := US.To_Unbounded_String
        ("<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<TagSet>");
   begin
      if not Valid_S3_Tags (Tags) then
         raise Malformed_Tagging with "cannot serialize invalid object tags";
      end if;
      for Index in 1 .. Tags.Length loop
         US.Append (Result, "<Tag><Key>");
         US.Append
           (Result, XML.Escape_Text (US.To_String (Tags.Items (Index).Key)));
         US.Append (Result, "</Key><Value>");
         US.Append
           (Result,
            XML.Escape_Text (US.To_String (Tags.Items (Index).Value)));
         US.Append (Result, "</Value></Tag>");
      end loop;
      US.Append (Result, "</TagSet></Tagging>");
      return US.To_String (Result);
   end Serialize;

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 16);

   function Decode_Component (Value : String) return String is
      Result : String (1 .. Value'Length);
      Raw    : constant String (1 .. Value'Length) := Value;
      Input  : Natural := 1;
      Output : Natural := 0;
   begin
      while Input <= Raw'Length loop
         Output := Output + 1;
         if Raw (Input) = '%' then
            if Input + 2 > Raw'Length
              or else Hex_Value (Raw (Input + 1)) > 15
              or else Hex_Value (Raw (Input + 2)) > 15
            then
               raise Malformed_Tagging_Query with
                 "invalid object tagging percent escape";
            end if;
            Result (Output) := Character'Val
              (16 * Hex_Value (Raw (Input + 1)) +
               Hex_Value (Raw (Input + 2)));
            Input := Input + 3;
         else
            Result (Output) := Raw (Input);
            Input := Input + 1;
         end if;
      end loop;
      return Result (1 .. Output);
   end Decode_Component;

   function Operation_Name (Operation : Tagging_Operation) return String is
     (case Operation is
         when Put_Object_Tagging => "PutObjectTagging",
         when Get_Object_Tagging => "GetObjectTagging",
         when Delete_Object_Tagging => "DeleteObjectTagging");

   function Parse_Query
     (Query : String; Operation : Tagging_Operation) return Tagging_Query
   is
      Result : Tagging_Query;
      Seen_Tagging : Boolean := False;
      Seen_X_ID : Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Bytes then
         raise Malformed_Tagging_Query with
           "invalid object tagging query size";
      end if;
      for Character_Value of Query loop
         if Character_Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 3 then
         raise Malformed_Tagging_Query with
           "too many object tagging query parameters";
      end if;
      declare
         Raw : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Tagging_Query with
                    "empty object tagging query parameter";
               end if;
               declare
                  Pair_Text : constant String := Raw (First .. Index - 1);
                  Equals : constant Natural :=
                    Ada.Strings.Fixed.Index (Pair_Text, "=");
                  Name : constant String := Decode_Component
                    ((if Equals = 0 then Pair_Text
                      elsif Equals = Pair_Text'First then ""
                      else Pair_Text (Pair_Text'First .. Equals - 1)));
                  Value : constant String := Decode_Component
                    ((if Equals = 0 or else Equals = Pair_Text'Last then ""
                      else Pair_Text (Equals + 1 .. Pair_Text'Last)));
               begin
                  if Name = "tagging" then
                     if Seen_Tagging or else Value'Length /= 0 then
                        raise Malformed_Tagging_Query with
                          "invalid tagging subresource";
                     end if;
                     Seen_Tagging := True;
                  elsif Name = "versionId" then
                     if Result.Has_Version_ID or else Value'Length = 0
                       or else not Deletions.Valid_Version_ID (Value)
                     then
                        raise Malformed_Tagging_Query with
                          "invalid object tagging version ID";
                     end if;
                     Result.Has_Version_ID := True;
                     Result.Version_ID := US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= Operation_Name (Operation)
                     then
                        raise Malformed_Tagging_Query with
                          "invalid object tagging operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_Tagging_Query with
                       "unsupported object tagging query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      if not Seen_Tagging then
         raise Malformed_Tagging_Query with "missing tagging subresource";
      end if;
      return Result;
   end Parse_Query;

   type Bucket_Tagging_Handler is new XML.Event_Handler with record
      Result        : Tags.Tag_Set;
      Current       : Tags.Tag;
      Text_Value    : US.Unbounded_String;
      Depth         : Natural := 0;
      Field         : Field_Kind := No_Field;
      Seen_Tag_Set  : Boolean := False;
      In_Tag        : Boolean := False;
      Seen_Key      : Boolean := False;
      Seen_Value    : Boolean := False;
      Allow_Empty_Namespace : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Bucket_Tagging_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Bucket_Tagging_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Bucket_Tagging_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Bucket_Tagging_Handler; Local_Name : String);

   procedure Require_Bucket_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value not in ' ' | Character'Val (9) |
           Character'Val (10) | Character'Val (13)
         then
            raise Malformed_Tagging with "text outside bucket tag fields";
         end if;
      end loop;
   end Require_Bucket_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Bucket_Tagging_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then
            (not Item.Allow_Empty_Namespace or else Namespace_URI'Length > 0))
        or else Attribute_Count /= 0
      then
         raise Malformed_Tagging with
           "bucket tagging namespace or attributes are invalid";
      end if;
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Bucket_Tagging_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Tagging with "bucket tagging XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Local_Name /= "Tagging" then
               raise Malformed_Tagging with "wrong bucket tagging root";
            end if;
         when 2 =>
            if Local_Name /= "TagSet" or else Item.Seen_Tag_Set then
               raise Malformed_Tagging with "invalid bucket TagSet";
            end if;
            Item.Seen_Tag_Set := True;
         when 3 =>
            if Local_Name /= "Tag"
              or else not Item.Seen_Tag_Set
              or else Item.Result.Length >=
                Ada.Containers.Count_Type (Tags.Maximum_Bucket_Tags)
            then
               raise Malformed_Tagging with "invalid bucket Tag entry";
            end if;
            Item.Current := (others => <>);
            Item.In_Tag := True;
            Item.Seen_Key := False;
            Item.Seen_Value := False;
         when 4 =>
            if not Item.In_Tag then
               raise Malformed_Tagging with "bucket tag field outside Tag";
            elsif Local_Name = "Key" and then not Item.Seen_Key then
               Item.Seen_Key := True;
               Item.Field := Key_Field;
            elsif Local_Name = "Value" and then not Item.Seen_Value then
               Item.Seen_Value := True;
               Item.Field := Value_Field;
            else
               raise Malformed_Tagging with
                 "unknown or duplicate bucket tag field";
            end if;
            US.Set_Unbounded_String (Item.Text_Value, "");
         when others =>
            raise Malformed_Tagging with "nested bucket tag field";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Bucket_Tagging_Handler; Value : String) is
   begin
      if Item.Field = No_Field then
         Require_Bucket_Whitespace (Value);
      else
         declare
            Maximum : constant Natural :=
              (if Item.Field = Key_Field
               then 4 * Tags.Maximum_Key_Characters
               else 4 * Tags.Maximum_Value_Characters);
         begin
            if Value'Length > Maximum
              or else US.Length (Item.Text_Value) > Maximum - Value'Length
            then
               raise Invalid_Tag with "bucket tag field is too long";
            end if;
            US.Append (Item.Text_Value, Value);
         end;
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Bucket_Tagging_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Tagging with "bucket tagging XML stack underflow";
      elsif Item.Depth = 4 then
         case Item.Field is
            when Key_Field =>
               Item.Current.Key := Item.Text_Value;
            when Value_Field =>
               Item.Current.Value := Item.Text_Value;
            when No_Field =>
               raise Malformed_Tagging with "bucket tag field state lost";
         end case;
         Item.Field := No_Field;
         US.Set_Unbounded_String (Item.Text_Value, "");
      elsif Item.Depth = 3 then
         if not Item.In_Tag or else not Item.Seen_Key
           or else not Item.Seen_Value
         then
            raise Malformed_Tagging with "incomplete bucket Tag";
         end if;
         Item.Result.Append (Item.Current);
         Item.In_Tag := False;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse_Bucket_Document
     (Document : String;
      Limits   : XML.Parse_Limits;
      Allow_Empty_Namespace : Boolean)
      return Tags.Tag_Set
   is
      Handler : aliased Bucket_Tagging_Handler :=
        (Allow_Empty_Namespace => Allow_Empty_Namespace, others => <>);
   begin
      if Document'Length > Maximum_Bucket_Document_Bytes then
         raise Malformed_Tagging with "bucket tagging document is too large";
      end if;
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Tag_Set or else Handler.Depth /= 0 then
         raise Malformed_Tagging with "bucket tagging document lacks TagSet";
      elsif not Tags.Valid_Bucket_Tag_Set (Handler.Result) then
         raise Invalid_Tag with "invalid bucket tag set";
      end if;
      return Handler.Result;
   exception
      when XML.XML_Error =>
         raise Malformed_Tagging with "malformed bucket tagging XML";
   end Parse_Bucket_Document;

   function Parse_Bucket
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => False));

   function Parse_Bucket_Response
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Tags.Tag_Set is
     (Parse_Bucket_Document
        (Document, Limits, Allow_Empty_Namespace => True));

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Serialize_Bucket (Value : Tags.Tag_Set) return String is
      Result : US.Unbounded_String;
   begin
      if not Tags.Valid_Bucket_Tag_Set (Value) then
         raise Invalid_Tag with "invalid bucket tag set";
      end if;
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<Tagging xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
         "<TagSet>");
      for Item of Value loop
         US.Append
           (Result,
            "<Tag>" & Element ("Key", US.To_String (Item.Key)) &
            Element ("Value", US.To_String (Item.Value)) & "</Tag>");
      end loop;
      US.Append (Result, "</TagSet></Tagging>");
      if US.Length (Result) > Maximum_Bucket_Document_Bytes then
         raise Invalid_Tag with "serialized bucket tag set is too large";
      end if;
      return US.To_String (Result);
   end Serialize_Bucket;

end Flyology.Object_Storage.S3.Tagging;
