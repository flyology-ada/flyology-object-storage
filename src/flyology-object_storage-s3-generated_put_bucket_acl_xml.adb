with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML_Writers;

package body
  Flyology.Object_Storage.S3.Generated_Put_Bucket_ACL_XML
is

   package US renames Ada.Strings.Unbounded;
   package XML renames Flyology.Object_Storage.S3.XML;
   package XML_Writers renames Flyology.Object_Storage.S3.XML_Writers;
   package ACL renames Flyology.Object_Storage.S3.ACL;

   --  These values are owned by the pinned Botocore payload declaration;
   --  changing either changes the serialized and signed request contract.
   Root_Name : constant String := "AccessControlPolicy";
   Namespace_URI : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";

   function Grantee_Type_Image
     (Value : ACL.Grantee_Type) return String is
     (case Value is
         when ACL.Canonical_User => "CanonicalUser",
         when ACL.Amazon_Customer_By_Email => "AmazonCustomerByEmail",
         when ACL.Group_Grantee => "Group");

   function Permission_Image
     (Value : ACL.Permission) return String is
     (case Value is
         when ACL.Full_Control => "FULL_CONTROL",
         when ACL.Write        => "WRITE",
         when ACL.Write_ACP    => "WRITE_ACP",
         when ACL.Read         => "READ",
         when ACL.Read_ACP     => "READ_ACP");

   procedure Write_Optional_String
     (Item  : in out XML_Writers.Writer;
      Name  : String;
      Value : ACL.Optional_String) is
   begin
      if Value.Is_Set then
         XML_Writers.Text_Element (Item, Name, US.To_String (Value.Value));
      end if;
   end Write_Optional_String;

   procedure Write_Grantee
     (Item  : in out XML_Writers.Writer;
      Value : ACL.Grantee) is
   begin
      if not Value.Is_Set then
         return;
      end if;
      XML_Writers.Start_Element (Item, "Grantee");
      XML_Writers.Attribute
        (Item, "type", Grantee_Type_Image (Value.Kind),
         "http://www.w3.org/2001/XMLSchema-instance", "xsi");
      Write_Optional_String (Item, "DisplayName", Value.Display_Name);
      Write_Optional_String (Item, "EmailAddress", Value.Email_Address);
      Write_Optional_String (Item, "ID", Value.ID);
      Write_Optional_String (Item, "URI", Value.URI);
      XML_Writers.End_Element (Item, "Grantee");
   end Write_Grantee;

   function Serialize
     (Value  : ACL.Access_Control_Policy;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      if not Value.Is_Set then
         return "";
      end if;
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document (Item, Root_Name, Namespace_URI);
      if Value.Policy_Owner.Is_Set then
         XML_Writers.Start_Element (Item, "Owner");
         Write_Optional_String
           (Item, "DisplayName", Value.Policy_Owner.Display_Name);
         Write_Optional_String (Item, "ID", Value.Policy_Owner.ID);
         XML_Writers.End_Element (Item, "Owner");
      end if;
      if Value.ACL.Is_Set then
         XML_Writers.Start_Element (Item, "AccessControlList");
         for Grant of Value.ACL.Grants loop
            XML_Writers.Start_Element (Item, "Grant");
            Write_Grantee (Item, Grant.Principal);
            if Grant.Allowed.Is_Set then
               XML_Writers.Text_Element
                 (Item, "Permission", Permission_Image (Grant.Allowed.Value));
            end if;
            XML_Writers.End_Element (Item, "Grant");
         end loop;
         XML_Writers.End_Element (Item, "AccessControlList");
      end if;
      return XML_Writers.Finish (Item, Root_Name);
   exception
      when XML_Writers.Encoding_Error =>
         raise ACL.Malformed_ACL with
           "ACL serialization violates caller limits";
   end Serialize;

end
  Flyology.Object_Storage.S3.Generated_Put_Bucket_ACL_XML;
