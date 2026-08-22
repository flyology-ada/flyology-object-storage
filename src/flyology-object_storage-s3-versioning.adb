with Ada.Strings.Unbounded;

package body Flyology.Object_Storage.S3.Versioning is

   package US renames Ada.Strings.Unbounded;

   type Field_Kind is (No_Field, Status_Field, MFA_Delete_Field);

   type Configuration_Handler is new XML.Event_Handler with record
      Value           : Bucket_Versioning_Configuration;
      Depth           : Natural := 0;
      Field           : Field_Kind := No_Field;
      Text_Value      : US.Unbounded_String;
      Root_Seen       : Boolean := False;
      Status_Seen     : Boolean := False;
      MFA_Delete_Seen : Boolean := False;
      Allow_Empty_Namespace : Boolean := False;
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

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Configuration with
              "text outside bucket versioning fields";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Configuration_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
   begin
      if (Namespace_URI /= "http://s3.amazonaws.com/doc/2006-03-01/"
          and then
            (not Item.Allow_Empty_Namespace or else Namespace_URI'Length > 0))
        or else Attribute_Count /= 0
      then
         raise Malformed_Configuration with
           "bucket versioning namespace or attributes are invalid";
      end if;
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Configuration_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Configuration with
           "bucket versioning depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "VersioningConfiguration" then
            raise Malformed_Configuration with
              "invalid bucket versioning root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2 then
         Item.Text_Value := US.Null_Unbounded_String;
         if Local_Name = "Status" and then not Item.Status_Seen then
            Item.Status_Seen := True;
            Item.Field := Status_Field;
         elsif Local_Name = "MfaDelete" and then not Item.MFA_Delete_Seen then
            Item.MFA_Delete_Seen := True;
            Item.Field := MFA_Delete_Field;
         else
            raise Malformed_Configuration with
              "unknown or duplicate bucket versioning field";
         end if;
      else
         raise Malformed_Configuration with
           "nested bucket versioning field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Configuration_Handler; Value : String) is
   begin
      if Item.Depth = 2 and then Item.Field /= No_Field then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth = 1 then
         Require_Whitespace (Value);
      else
         raise Malformed_Configuration with
           "bucket versioning text outside the document root";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Configuration_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      if Item.Depth = 2 then
         case Item.Field is
            when Status_Field =>
               if Local_Name /= "Status" then
                  raise Malformed_Configuration with
                    "mismatched bucket versioning status close";
               elsif Value = "Enabled" then
                  Item.Value.Status := Versioning_Enabled;
               elsif Value = "Suspended" then
                  Item.Value.Status := Versioning_Suspended;
               else
                  raise Malformed_Configuration with
                    "invalid bucket versioning status";
               end if;
            when MFA_Delete_Field =>
               if Local_Name /= "MfaDelete" then
                  raise Malformed_Configuration with
                    "mismatched MFA-delete close";
               elsif Value = "Enabled" then
                  Item.Value.MFA_Delete := MFA_Delete_Enabled;
               elsif Value = "Disabled" then
                  Item.Value.MFA_Delete := MFA_Delete_Disabled;
               else
                  raise Malformed_Configuration with
                    "invalid MFA-delete status";
               end if;
            when No_Field =>
               raise Malformed_Configuration with
                 "bucket versioning field state is invalid";
         end case;
         Item.Field := No_Field;
         Item.Text_Value := US.Null_Unbounded_String;
         Item.Depth := 1;
      elsif Item.Depth = 1
        and then Local_Name = "VersioningConfiguration"
      then
         Item.Depth := 0;
      else
         raise Malformed_Configuration with
           "invalid bucket versioning closing element";
      end if;
   end End_Element;

   function Parse_Document
     (Document : String;
      Limits   : XML.Parse_Limits;
      Allow_Empty_Namespace : Boolean)
      return Bucket_Versioning_Configuration
   is
      Handler : aliased Configuration_Handler :=
        (Allow_Empty_Namespace => Allow_Empty_Namespace, others => <>);
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Configuration with
           "incomplete bucket versioning document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Configuration with
           "malformed bucket versioning XML";
   end Parse_Document;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration is
     (Parse_Document
        (Document, Limits, Allow_Empty_Namespace => False));

   function Parse_Response
     (Document : String;
      Limits   : XML.Parse_Limits := Default_Limits)
      return Bucket_Versioning_Configuration is
     (Parse_Document
        (Document, Limits, Allow_Empty_Namespace => True));

   function Serialize (Value : Bucket_Versioning_Configuration) return String
   is
      Status : constant String :=
        (case Value.Status is
            when Versioning_Unconfigured => "",
            when Versioning_Enabled      => "Enabled",
            when Versioning_Suspended    => "Suspended");
      MFA_Delete : constant String :=
        (case Value.MFA_Delete is
            when MFA_Delete_Unconfigured => "",
            when MFA_Delete_Enabled      => "Enabled",
            when MFA_Delete_Disabled     => "Disabled");
   begin
      return
        "<?xml version=""1.0"" encoding=""UTF-8""?>" &
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">" &
        (if MFA_Delete'Length = 0 then ""
         else "<MfaDelete>" & MFA_Delete & "</MfaDelete>") &
        (if Status'Length = 0 then ""
         else "<Status>" & Status & "</Status>") &
        "</VersioningConfiguration>";
   end Serialize;

   function Serialize_Response
     (Value : Bucket_Versioning_Configuration) return String
   is
      Status : constant String :=
        (case Value.Status is
            when Versioning_Unconfigured => "",
            when Versioning_Enabled      => "Enabled",
            when Versioning_Suspended    => "Suspended");
      MFA_Delete : constant String :=
        (case Value.MFA_Delete is
            when MFA_Delete_Unconfigured => "",
            when MFA_Delete_Enabled      => "Enabled",
            when MFA_Delete_Disabled     => "Disabled");
   begin
      return
        "<?xml version=""1.0"" encoding=""UTF-8""?>" &
        "<VersioningConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">" &
        (if Status'Length = 0 then ""
         else "<Status>" & Status & "</Status>") &
        (if MFA_Delete'Length = 0 then ""
         else "<MfaDelete>" & MFA_Delete & "</MfaDelete>") &
        "</VersioningConfiguration>";
   end Serialize_Response;

end Flyology.Object_Storage.S3.Versioning;
