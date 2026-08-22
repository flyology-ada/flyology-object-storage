with Ada.Containers;
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

   procedure Validate (Value : Delete_Objects_Request) is
   begin
      if Value.Objects.Is_Empty
        or else Value.Objects.Length > Maximum_Objects
      then
         raise Malformed_Delete with "invalid DeleteObjects entry count";
      end if;
      for Item of Value.Objects loop
         if US.Length (Item.Key) = 0 then
            raise Malformed_Delete with "empty DeleteObjects key";
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
              or else US.Length (Item.Current_Deleted.Key) = 0
              or else (Item.Seen_Version
                       and then US.Length
                         (Item.Current_Deleted.Version_ID) = 0)
              or else (Item.Seen_Marker_Version
                       and then US.Length
                         (Item.Current_Deleted.Delete_Marker_Version_ID) = 0)
            then
               raise Malformed_Delete with
                 "invalid DeleteObjects deleted entry";
            end if;
            Item.Value.Deleted.Append (Item.Current_Deleted);
         elsif Item.Current_Entry = Error_Entry then
            if not Item.Seen_Key
              or else US.Length (Item.Current_Error.Key) = 0
              or else not Item.Seen_Code
              or else US.Length (Item.Current_Error.Code) = 0
              or else (Item.Seen_Version
                       and then US.Length
                         (Item.Current_Error.Version_ID) = 0)
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
         if US.Length (Item.Key) = 0 then
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
         if US.Length (Item.Key) = 0 or else US.Length (Item.Code) = 0 then
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
