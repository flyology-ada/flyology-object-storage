with Ada.Containers;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Deletions is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;

   type Field_Kind is (No_Field, Key_Field, Version_Field, Quiet_Field);

   type Delete_Handler is new XML.Event_Handler with record
      Value          : Delete_Objects_Request;
      Current        : Object_Identifier;
      Text_Value     : US.Unbounded_String;
      Depth          : Natural := 0;
      Ignore_Depth   : Natural := 0;
      Field          : Field_Kind := No_Field;
      In_Object      : Boolean := False;
      Seen_Key       : Boolean := False;
      Seen_Version   : Boolean := False;
      Seen_Quiet     : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Delete_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Delete_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Delete_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value /= ' '
           and then Character_Value /= Character'Val (9)
           and then Character_Value /= Character'Val (10)
           and then Character_Value /= Character'Val (13)
         then
            raise Malformed_Delete with "text outside DeleteObjects fields";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Select_Field
     (Item : in out Delete_Handler;
      Seen : in out Boolean;
      Kind : Field_Kind) is
   begin
      if Seen then
         raise Malformed_Delete with "duplicate DeleteObjects field";
      end if;
      Seen := True;
      Item.Field := Kind;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Field;

   overriding procedure Start_Element
     (Item : in out Delete_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Delete with "DeleteObjects XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Depth = 1 then
         if Local_Name /= "Delete" then
            raise Malformed_Delete with "wrong DeleteObjects root";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "Object" then
            if Item.Value.Objects.Length >= Maximum_Objects then
               raise Malformed_Delete with "too many DeleteObjects entries";
            end if;
            Item.Current := (others => <>);
            Item.Seen_Key := False;
            Item.Seen_Version := False;
            Item.In_Object := True;
         elsif Local_Name = "Quiet" then
            Select_Field (Item, Item.Seen_Quiet, Quiet_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.In_Object then
         if Local_Name = "Key" then
            Select_Field (Item, Item.Seen_Key, Key_Field);
         elsif Local_Name = "VersionId" then
            Select_Field (Item, Item.Seen_Version, Version_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      else
         raise Malformed_Delete with "nested DeleteObjects field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Delete_Handler; Value : String) is
   begin
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field = No_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Delete_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Delete with "DeleteObjects XML stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         case Item.Field is
            when Key_Field =>
               Item.Current.Key := Item.Text_Value;
            when Version_Field =>
               Item.Current.Version_ID := Item.Text_Value;
            when Quiet_Field =>
               declare
                  Parsed : constant S3.Wire_Core.Boolean_Result :=
                    S3.Wire_Core.Parse_Boolean
                      (US.To_String (Item.Text_Value));
               begin
                  if not Parsed.Valid then
                     raise Malformed_Delete with
                       "invalid DeleteObjects Quiet value";
                  end if;
                  Item.Value.Quiet := Parsed.Value;
               end;
            when No_Field =>
               null;
         end case;
         Item.Field := No_Field;
         US.Set_Unbounded_String (Item.Text_Value, "");
      elsif Item.Depth = 2 and then Item.In_Object then
         if not Item.Seen_Key or else US.Length (Item.Current.Key) = 0 then
            raise Malformed_Delete with "DeleteObjects entry lacks a key";
         elsif Item.Seen_Version
           and then US.Length (Item.Current.Version_ID) = 0
         then
            raise Malformed_Delete with "empty DeleteObjects version ID";
         end if;
         Item.Value.Objects.Append (Item.Current);
         Item.In_Object := False;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Valid_Version_ID (Item : String) return Boolean is
   begin
      if Item'Length > Maximum_Version_ID_Length then
         return False;
      end if;
      for Character_Value of Item loop
         if Character_Value = Character'Val (0) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Version_ID;

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 16);

   function Decode_Query_Component (Value : String) return String is
      Result : String (1 .. Value'Length);
      Input  : Natural := 1;
      Output : Natural := 0;
      Raw    : constant String (1 .. Value'Length) := Value;
   begin
      while Input <= Raw'Length loop
         Output := Output + 1;
         if Raw (Input) = '%' then
            if Input + 2 > Raw'Length
              or else Hex_Value (Raw (Input + 1)) > 15
              or else Hex_Value (Raw (Input + 2)) > 15
            then
               raise Malformed_Delete_Object_Request with
                 "invalid DeleteObject percent escape";
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
   end Decode_Query_Component;

   function Parse_Delete_Object_Query
     (Query : String) return Delete_Object_Request
   is
      Maximum_Query_Length : constant := 8 * 1_024;
      Result : Delete_Object_Request;
      Seen_X_ID : Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 then
         return Result;
      elsif Query'Length > Maximum_Query_Length then
         raise Malformed_Delete_Object_Request with
           "invalid DeleteObject query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 2 then
         raise Malformed_Delete_Object_Request with
           "too many DeleteObject query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Delete_Object_Request with
                    "empty DeleteObject query parameter";
               end if;
               declare
                  Pair_Text : constant String := Raw (First .. Index - 1);
                  Equals : constant Natural :=
                    Ada.Strings.Fixed.Index (Pair_Text, "=");
                  Name : constant String := Decode_Query_Component
                    ((if Equals = 0 then Pair_Text
                      elsif Equals = Pair_Text'First then ""
                      else Pair_Text (Pair_Text'First .. Equals - 1)));
                  Value : constant String := Decode_Query_Component
                    ((if Equals = 0 or else Equals = Pair_Text'Last then ""
                      else Pair_Text (Equals + 1 .. Pair_Text'Last)));
               begin
                  if Name = "versionId" then
                     if Result.Has_Version_ID
                       or else Value'Length = 0
                       or else not Valid_Version_ID (Value)
                     then
                        raise Malformed_Delete_Object_Request with
                          "invalid DeleteObject version ID";
                     end if;
                     Result.Has_Version_ID := True;
                     Result.Version_ID := US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "DeleteObject" then
                        raise Malformed_Delete_Object_Request with
                          "invalid DeleteObject operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_Delete_Object_Request with
                       "unsupported DeleteObject query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      return Result;
   end Parse_Delete_Object_Query;

   procedure Validate (Value : Delete_Objects_Request) is
   begin
      if Value.Objects.Is_Empty
        or else Value.Objects.Length > Maximum_Objects
      then
         raise Malformed_Delete with "invalid DeleteObjects entry count";
      end if;
      for Item of Value.Objects loop
         if not Valid_Object_Key (US.To_String (Item.Key)) then
            raise Malformed_Delete with "invalid DeleteObjects key";
         elsif not Valid_Version_ID (US.To_String (Item.Version_ID)) then
            raise Malformed_Delete with "invalid DeleteObjects version ID";
         end if;
      end loop;
   end Validate;

   function Parse_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Request
   is
      Handler : aliased Delete_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Delete with "malformed DeleteObjects XML";
   end Parse_Request;

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Serialize_Request (Value : Delete_Objects_Request) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<Delete xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">");
      for Item of Value.Objects loop
         US.Append (Result, "<Object>" & Element
           ("Key", US.To_String (Item.Key)));
         if US.Length (Item.Version_ID) > 0 then
            US.Append (Result, Element
              ("VersionId", US.To_String (Item.Version_ID)));
         end if;
         US.Append (Result, "</Object>");
      end loop;
      if Value.Quiet then
         US.Append (Result, "<Quiet>true</Quiet>");
      end if;
      US.Append (Result, "</Delete>");
      if US.Length (Result) > Maximum_Document_Bytes then
         raise Malformed_Delete with "DeleteObjects request is too large";
      end if;
      return US.To_String (Result);
   end Serialize_Request;

   type Result_Entry_Kind is (No_Entry, Deleted_Entry, Error_Entry);
   type Result_Field_Kind is
     (No_Result_Field, Result_Key_Field, Result_Version_Field,
      Delete_Marker_Field, Delete_Marker_Version_Field, Code_Field,
      Message_Field);

   type Result_Handler is new XML.Event_Handler with record
      Value          : Delete_Objects_Result;
      Current_Deleted : Deleted_Object;
      Current_Error  : Delete_Error;
      Text_Value     : US.Unbounded_String;
      Depth          : Natural := 0;
      Ignore_Depth   : Natural := 0;
      Current_Entry  : Result_Entry_Kind := No_Entry;
      Field          : Result_Field_Kind := No_Result_Field;
      Seen_Key       : Boolean := False;
      Seen_Version   : Boolean := False;
      Seen_Marker    : Boolean := False;
      Seen_Marker_Version : Boolean := False;
      Seen_Code      : Boolean := False;
      Seen_Message   : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Result_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Result_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Result_Handler; Local_Name : String);

   procedure Select_Result_Field
     (Item : in out Result_Handler;
      Seen : in out Boolean;
      Kind : Result_Field_Kind) is
   begin
      if Seen then
         raise Malformed_Delete with "duplicate DeleteObjects result field";
      end if;
      Seen := True;
      Item.Field := Kind;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Result_Field;

   overriding procedure Start_Element
     (Item : in out Result_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Delete with "DeleteObjects result depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Depth = 1 then
         if Local_Name /= "DeleteResult" then
            raise Malformed_Delete with "wrong DeleteObjects result root";
         end if;
      elsif Item.Depth = 2 then
         if Item.Value.Deleted.Length + Item.Value.Errors.Length >=
           Maximum_Objects
         then
            raise Malformed_Delete with
              "too many DeleteObjects result entries";
         elsif Local_Name = "Deleted" then
            Item.Current_Entry := Deleted_Entry;
            Item.Current_Deleted := (others => <>);
         elsif Local_Name = "Error" then
            Item.Current_Entry := Error_Entry;
            Item.Current_Error := (others => <>);
         else
            Item.Ignore_Depth := Item.Depth;
            return;
         end if;
         Item.Seen_Key := False;
         Item.Seen_Version := False;
         Item.Seen_Marker := False;
         Item.Seen_Marker_Version := False;
         Item.Seen_Code := False;
         Item.Seen_Message := False;
      elsif Item.Depth = 3
        and then Item.Current_Entry = Deleted_Entry
      then
         if Local_Name = "Key" then
            Select_Result_Field
              (Item, Item.Seen_Key, Result_Key_Field);
         elsif Local_Name = "VersionId" then
            Select_Result_Field
              (Item, Item.Seen_Version, Result_Version_Field);
         elsif Local_Name = "DeleteMarker" then
            Select_Result_Field
              (Item, Item.Seen_Marker, Delete_Marker_Field);
         elsif Local_Name = "DeleteMarkerVersionId" then
            Select_Result_Field
              (Item, Item.Seen_Marker_Version,
               Delete_Marker_Version_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Current_Entry = Error_Entry then
         if Local_Name = "Key" then
            Select_Result_Field
              (Item, Item.Seen_Key, Result_Key_Field);
         elsif Local_Name = "VersionId" then
            Select_Result_Field
              (Item, Item.Seen_Version, Result_Version_Field);
         elsif Local_Name = "Code" then
            Select_Result_Field (Item, Item.Seen_Code, Code_Field);
         elsif Local_Name = "Message" then
            Select_Result_Field (Item, Item.Seen_Message, Message_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      else
         raise Malformed_Delete with "nested DeleteObjects result field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Result_Handler; Value : String) is
   begin
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field = No_Result_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Result_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Delete with
           "DeleteObjects result XML stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Result_Field then
         case Item.Field is
            when Result_Key_Field =>
               if Item.Current_Entry = Deleted_Entry then
                  Item.Current_Deleted.Key := Item.Text_Value;
               else
                  Item.Current_Error.Key := Item.Text_Value;
               end if;
            when Result_Version_Field =>
               if Item.Current_Entry = Deleted_Entry then
                  Item.Current_Deleted.Version_ID := Item.Text_Value;
               else
                  Item.Current_Error.Version_ID := Item.Text_Value;
               end if;
            when Delete_Marker_Field =>
               declare
                  Parsed : constant S3.Wire_Core.Boolean_Result :=
                    S3.Wire_Core.Parse_Boolean
                      (US.To_String (Item.Text_Value));
               begin
                  if not Parsed.Valid then
                     raise Malformed_Delete with
                       "invalid DeleteObjects delete marker";
                  end if;
                  Item.Current_Deleted.Delete_Marker :=
                    (Is_Set => True, Value => Parsed.Value);
               end;
            when Delete_Marker_Version_Field =>
               Item.Current_Deleted.Delete_Marker_Version_ID :=
                 Item.Text_Value;
            when Code_Field =>
               Item.Current_Error.Code := Item.Text_Value;
            when Message_Field =>
               Item.Current_Error.Message := Item.Text_Value;
            when No_Result_Field =>
               null;
         end case;
         Item.Field := No_Result_Field;
         US.Set_Unbounded_String (Item.Text_Value, "");
      elsif Item.Depth = 2 then
         if Item.Current_Entry = Deleted_Entry then
            if not Item.Seen_Key
              or else not Valid_Object_Key
                (US.To_String (Item.Current_Deleted.Key))
              or else (Item.Seen_Version
                       and then
                         (US.Length (Item.Current_Deleted.Version_ID) = 0
                          or else not Valid_Version_ID
                            (US.To_String
                               (Item.Current_Deleted.Version_ID))))
              or else (Item.Seen_Marker_Version
                       and then
                         (US.Length
                            (Item.Current_Deleted.Delete_Marker_Version_ID) = 0
                          or else not Valid_Version_ID
                            (US.To_String
                               (Item.Current_Deleted
                                  .Delete_Marker_Version_ID))))
            then
               raise Malformed_Delete with
                 "invalid DeleteObjects deleted entry";
            end if;
            Item.Value.Deleted.Append (Item.Current_Deleted);
         elsif Item.Current_Entry = Error_Entry then
            if not Item.Seen_Key
              or else not Valid_Object_Key
                (US.To_String (Item.Current_Error.Key))
              or else not Item.Seen_Code
              or else US.Length (Item.Current_Error.Code) = 0
              or else (Item.Seen_Version
                       and then
                         (US.Length (Item.Current_Error.Version_ID) = 0
                          or else not Valid_Version_ID
                            (US.To_String (Item.Current_Error.Version_ID))))
            then
               raise Malformed_Delete with
                 "invalid DeleteObjects error entry";
            end if;
            Item.Value.Errors.Append (Item.Current_Error);
         else
            raise Malformed_Delete with
              "invalid DeleteObjects result entry";
         end if;
         Item.Current_Entry := No_Entry;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Delete_Objects_Result
   is
      Handler : aliased Result_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Delete with "malformed DeleteObjects result XML";
   end Parse_Result;

   function Serialize_Result (Value : Delete_Objects_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      if Value.Deleted.Length > Maximum_Objects
        or else Value.Errors.Length > Maximum_Objects
        or else Value.Deleted.Length + Value.Errors.Length > Maximum_Objects
      then
         raise Malformed_Delete with "invalid DeleteObjects result count";
      end if;
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<DeleteResult xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">");
      for Item of Value.Deleted loop
         if not Valid_Object_Key (US.To_String (Item.Key))
           or else not Valid_Version_ID (US.To_String (Item.Version_ID))
           or else not Valid_Version_ID
             (US.To_String (Item.Delete_Marker_Version_ID))
         then
            raise Malformed_Delete with "invalid deleted object";
         end if;
         US.Append (Result, "<Deleted>" & Element
           ("Key", US.To_String (Item.Key)));
         if US.Length (Item.Version_ID) > 0 then
            US.Append (Result, Element
              ("VersionId", US.To_String (Item.Version_ID)));
         end if;
         if Item.Delete_Marker.Is_Set then
            US.Append
              (Result, Element
                 ("DeleteMarker",
                  (if Item.Delete_Marker.Value then "true" else "false")));
         end if;
         if US.Length (Item.Delete_Marker_Version_ID) > 0 then
            US.Append
              (Result, Element
                 ("DeleteMarkerVersionId",
                  US.To_String (Item.Delete_Marker_Version_ID)));
         end if;
         US.Append (Result, "</Deleted>");
      end loop;
      for Item of Value.Errors loop
         if not Valid_Object_Key (US.To_String (Item.Key))
           or else not Valid_Version_ID (US.To_String (Item.Version_ID))
           or else US.Length (Item.Code) = 0
         then
            raise Malformed_Delete with "invalid DeleteObjects error";
         end if;
         US.Append (Result, "<Error>" & Element
           ("Key", US.To_String (Item.Key)));
         if US.Length (Item.Version_ID) > 0 then
            US.Append (Result, Element
              ("VersionId", US.To_String (Item.Version_ID)));
         end if;
         US.Append (Result, Element ("Code", US.To_String (Item.Code)));
         US.Append
           (Result, Element ("Message", US.To_String (Item.Message)) &
            "</Error>");
      end loop;
      US.Append (Result, "</DeleteResult>");
      return US.To_String (Result);
   end Serialize_Result;

end Flyology.Object_Storage.S3.Deletions;
