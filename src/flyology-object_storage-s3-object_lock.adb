with Ada.Strings.Unbounded;

package body Flyology.Object_Storage.S3.Object_Lock is

   package US renames Ada.Strings.Unbounded;

   type Legal_Hold_Handler is new XML.Event_Handler with record
      Depth       : Natural := 0;
      Root_Seen   : Boolean := False;
      Status_Seen : Boolean := False;
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

   --  External REST/XML authority from the pinned generated model and S3
   --  protocol namespace; changing these spellings changes compatibility.
   S3_Namespace : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";

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
      pragma Unreferenced (Item);
   begin
      if (Namespace_URI'Length > 0
          and then Namespace_URI /= S3_Namespace)
        or else Attribute_Count /= 0
      then
         raise Malformed_Object_Lock with
           "Object Lock namespace or attributes are invalid";
      end if;
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

end Flyology.Object_Storage.S3.Object_Lock;
