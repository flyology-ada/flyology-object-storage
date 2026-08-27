with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.ACL;
with Flyology.Object_Storage.S3.XML_Writers;

package body
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Logging_XML
is

   package US renames Ada.Strings.Unbounded;
   package XML renames Flyology.Object_Storage.S3.XML;
   package XML_Writers renames Flyology.Object_Storage.S3.XML_Writers;
   package Logging renames Flyology.Object_Storage.S3.Logging;
   package ACL renames Flyology.Object_Storage.S3.ACL;

   --  These values are owned by the pinned Botocore payload declaration;
   --  changing either changes the serialized and signed request contract.
   Root_Name : constant String := "BucketLoggingStatus";
   Namespace_URI : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";

   function Grantee_Type_Image
     (Value : ACL.Grantee_Type) return String is
     (case Value is
         when ACL.Canonical_User => "CanonicalUser",
         when ACL.Amazon_Customer_By_Email => "AmazonCustomerByEmail",
         when ACL.Group_Grantee => "Group");

   function Permission_Image
     (Value : Logging.Logging_Permission) return String is
     (case Value is
         when Logging.Full_Control => "FULL_CONTROL",
         when Logging.Read         => "READ",
         when Logging.Write        => "WRITE");

   function Date_Source_Image
     (Value : Logging.Partition_Date_Source) return String is
     (case Value is
         when Logging.Event_Time    => "EventTime",
         when Logging.Delivery_Time => "DeliveryTime");

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
     (Value  : Logging.Logging_Status;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
   begin
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document (Item, Root_Name, Namespace_URI);
      if Value.Is_Enabled then
         XML_Writers.Start_Element (Item, "LoggingEnabled");
         XML_Writers.Text_Element
           (Item, "TargetBucket", US.To_String (Value.Target_Bucket));
         if Value.Grants.Is_Set then
            XML_Writers.Start_Element (Item, "TargetGrants");
            for Grant of Value.Grants.Grants loop
               XML_Writers.Start_Element (Item, "Grant");
               Write_Grantee (Item, Grant.Principal);
               if Grant.Permission.Is_Set then
                  XML_Writers.Text_Element
                    (Item, "Permission",
                     Permission_Image (Grant.Permission.Value));
               end if;
               XML_Writers.End_Element (Item, "Grant");
            end loop;
            XML_Writers.End_Element (Item, "TargetGrants");
         end if;
         XML_Writers.Text_Element
           (Item, "TargetPrefix", US.To_String (Value.Target_Prefix));
         if Value.Key_Format.Is_Set then
            XML_Writers.Start_Element (Item, "TargetObjectKeyFormat");
            if Value.Key_Format.Simple_Prefix then
               XML_Writers.Empty_Element (Item, "SimplePrefix");
            end if;
            if Value.Key_Format.Partitioned_Prefix then
               XML_Writers.Start_Element (Item, "PartitionedPrefix");
               if Value.Key_Format.Date_Source.Is_Set then
                  XML_Writers.Text_Element
                    (Item, "PartitionDateSource",
                     Date_Source_Image (Value.Key_Format.Date_Source.Value));
               end if;
               XML_Writers.End_Element (Item, "PartitionedPrefix");
            end if;
            XML_Writers.End_Element (Item, "TargetObjectKeyFormat");
         end if;
         XML_Writers.End_Element (Item, "LoggingEnabled");
      end if;
      return XML_Writers.Finish (Item, Root_Name);
   exception
      when XML_Writers.Encoding_Error =>
         raise Logging.Malformed_Logging with
           "logging serialization violates caller limits";
   end Serialize;

end
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Logging_XML;
