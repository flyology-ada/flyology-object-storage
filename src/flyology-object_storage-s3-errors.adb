package body Flyology.Object_Storage.S3.Errors is

   package US renames Ada.Strings.Unbounded;

   type Field_Kind is
     (No_Field, Code_Field, Message_Field, Resource_Field,
      Request_ID_Field, Host_ID_Field, Unknown_Field);

   type Error_Handler is new XML.Event_Handler with record
      Value     : Error_Response;
      Depth     : Natural := 0;
      Field     : Field_Kind := No_Field;
      Seen_Code : Boolean := False;
      Seen_Message : Boolean := False;
      Seen_Resource : Boolean := False;
      Seen_Request_ID : Boolean := False;
      Seen_Host_ID : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Error_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Error_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Error_Handler; Local_Name : String);

   procedure Mark
     (Seen : in out Boolean; Field : Field_Kind; Item : in out Error_Handler)
   is
   begin
      if Seen then
         raise Malformed_Error with "duplicate S3 error field";
      end if;
      Seen := True;
      Item.Field := Field;
   end Mark;

   overriding procedure Start_Element
     (Item : in out Error_Handler; Local_Name : String) is
   begin
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Local_Name /= "Error" then
            raise Malformed_Error with "S3 error root is not Error";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "Code" then
            Mark (Item.Seen_Code, Code_Field, Item);
         elsif Local_Name = "Message" then
            Mark (Item.Seen_Message, Message_Field, Item);
         elsif Local_Name = "Resource" then
            Mark (Item.Seen_Resource, Resource_Field, Item);
         elsif Local_Name = "RequestId" or else Local_Name = "RequestID" then
            Mark (Item.Seen_Request_ID, Request_ID_Field, Item);
         elsif Local_Name = "HostId" or else Local_Name = "HostID" then
            Mark (Item.Seen_Host_ID, Host_ID_Field, Item);
         else
            Item.Field := Unknown_Field;
         end if;
      elsif Item.Field /= Unknown_Field then
         raise Malformed_Error with "nested S3 error field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Error_Handler; Value : String) is
   begin
      if Item.Depth = 2 then
         case Item.Field is
            when Code_Field =>
               US.Append (Item.Value.Code, Value);
            when Message_Field =>
               US.Append (Item.Value.Message, Value);
            when Resource_Field =>
               US.Append (Item.Value.Resource, Value);
            when Request_ID_Field =>
               US.Append (Item.Value.Request_ID, Value);
            when Host_ID_Field =>
               US.Append (Item.Value.Host_ID, Value);
            when No_Field | Unknown_Field =>
               null;
         end case;
      elsif Item.Depth <= 1 then
         for Character_Value of Value loop
            if Character_Value /= ' '
              and then Character_Value /= Character'Val (9)
              and then Character_Value /= Character'Val (10)
              and then Character_Value /= Character'Val (13)
            then
               raise Malformed_Error with "text outside S3 error fields";
            end if;
         end loop;
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Error_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Error with "S3 error stack underflow";
      elsif Item.Depth = 2 then
         Item.Field := No_Field;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Error_Response
   is
      Handler : aliased Error_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Code
        or else not Handler.Seen_Message
        or else US.Length (Handler.Value.Code) = 0
        or else US.Length (Handler.Value.Message) = 0
      then
         raise Malformed_Error with "S3 error lacks Code or Message";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Error with "malformed S3 error XML";
   end Parse;

   function Element (Name, Value : String) return String is
     (if Value'Length = 0 then ""
      else "<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Serialize (Value : Error_Response) return String is
      Code    : constant String := US.To_String (Value.Code);
      Message : constant String := US.To_String (Value.Message);
   begin
      if Code'Length = 0 or else Message'Length = 0 then
         raise Malformed_Error with "S3 error lacks Code or Message";
      end if;
      return "<?xml version=""1.0"" encoding=""UTF-8""?>" &
        "<Error><Code>" & XML.Escape_Text (Code) & "</Code>" &
        "<Message>" & XML.Escape_Text (Message) & "</Message>" &
        Element ("Resource", US.To_String (Value.Resource)) &
        Element ("RequestId", US.To_String (Value.Request_ID)) &
        Element ("HostId", US.To_String (Value.Host_ID)) & "</Error>";
   end Serialize;

end Flyology.Object_Storage.S3.Errors;
