with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML_Writers;

package body
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Inventory_Configuration_XML
is

   package US renames Ada.Strings.Unbounded;
   package XML renames Flyology.Object_Storage.S3.XML;
   package XML_Writers renames Flyology.Object_Storage.S3.XML_Writers;
   package Inventory renames Flyology.Object_Storage.S3.Inventory;

   --  These values are owned by the pinned Botocore payload declaration;
   --  changing either changes the serialized and signed request contract.
   Root_Name : constant String := "InventoryConfiguration";
   Namespace_URI : constant String :=
     "http://s3.amazonaws.com/doc/2006-03-01/";

   function Inventory_Format_Image
     (Value : Inventory.Inventory_Format) return String is
     (case Value is
         when Inventory.CSV     => "CSV",
         when Inventory.ORC     => "ORC",
         when Inventory.Parquet => "Parquet");

   function Frequency_Image
     (Value : Inventory.Inventory_Frequency) return String is
     (case Value is
         when Inventory.Daily  => "Daily",
         when Inventory.Weekly => "Weekly");

   function Versions_Image
     (Value : Inventory.Included_Object_Versions) return String is
     (case Value is
         when Inventory.All_Versions     => "All",
         when Inventory.Current_Versions => "Current");

   function Optional_Field_Image
     (Value : Inventory.Optional_Field_Kind) return String is
     (case Value is
         when Inventory.Size => "Size",
         when Inventory.Last_Modified_Date => "LastModifiedDate",
         when Inventory.Storage_Class => "StorageClass",
         when Inventory.ETag => "ETag",
         when Inventory.Is_Multipart_Uploaded => "IsMultipartUploaded",
         when Inventory.Replication_Status => "ReplicationStatus",
         when Inventory.Encryption_Status => "EncryptionStatus",
         when Inventory.Object_Lock_Retain_Until_Date =>
           "ObjectLockRetainUntilDate",
         when Inventory.Object_Lock_Mode => "ObjectLockMode",
         when Inventory.Object_Lock_Legal_Hold_Status =>
           "ObjectLockLegalHoldStatus",
         when Inventory.Intelligent_Tiering_Access_Tier =>
           "IntelligentTieringAccessTier",
         when Inventory.Bucket_Key_Status => "BucketKeyStatus",
         when Inventory.Checksum_Algorithm => "ChecksumAlgorithm",
         when Inventory.Object_Access_Control_List =>
           "ObjectAccessControlList",
         when Inventory.Object_Owner => "ObjectOwner",
         when Inventory.Lifecycle_Expiration_Date =>
           "LifecycleExpirationDate");

   function Serialize
     (Value  : Inventory.Inventory_Configuration;
      Limits : XML.Parse_Limits) return String
   is
      Item : XML_Writers.Writer;
      S3_Destination : Inventory.S3_Bucket_Destination renames
        Value.Destination.S3_Bucket;
   begin
      XML_Writers.Initialize (Item, Limits);
      XML_Writers.Start_Document (Item, Root_Name, Namespace_URI);
      XML_Writers.Start_Element (Item, "Destination");
      XML_Writers.Start_Element (Item, "S3BucketDestination");
      if S3_Destination.Account_ID.Is_Set then
         XML_Writers.Text_Element
           (Item, "AccountId", US.To_String (S3_Destination.Account_ID.Value));
      end if;
      XML_Writers.Text_Element
        (Item, "Bucket", US.To_String (S3_Destination.Bucket));
      XML_Writers.Text_Element
        (Item, "Format", Inventory_Format_Image (S3_Destination.Format));
      if S3_Destination.Prefix.Is_Set then
         XML_Writers.Text_Element
           (Item, "Prefix", US.To_String (S3_Destination.Prefix.Value));
      end if;
      if S3_Destination.Encryption.Is_Set then
         XML_Writers.Start_Element (Item, "Encryption");
         if S3_Destination.Encryption.SSE_S3 then
            XML_Writers.Empty_Element (Item, "SSE-S3");
         end if;
         if S3_Destination.Encryption.SSE_KMS_Key_ID.Is_Set then
            XML_Writers.Start_Element (Item, "SSE-KMS");
            XML_Writers.Text_Element
              (Item, "KeyId",
               US.To_String (S3_Destination.Encryption.SSE_KMS_Key_ID.Value));
            XML_Writers.End_Element (Item, "SSE-KMS");
         end if;
         XML_Writers.End_Element (Item, "Encryption");
      end if;
      XML_Writers.End_Element (Item, "S3BucketDestination");
      XML_Writers.End_Element (Item, "Destination");
      XML_Writers.Text_Element
        (Item, "IsEnabled", (if Value.Is_Enabled then "true" else "false"));
      if Value.Filter.Is_Set then
         XML_Writers.Start_Element (Item, "Filter");
         XML_Writers.Text_Element
           (Item, "Prefix", US.To_String (Value.Filter.Prefix));
         XML_Writers.End_Element (Item, "Filter");
      end if;
      XML_Writers.Text_Element (Item, "Id", US.To_String (Value.ID));
      XML_Writers.Text_Element
        (Item, "IncludedObjectVersions", Versions_Image (Value.Versions));
      if not Value.Optional_Fields.Is_Empty then
         XML_Writers.Start_Element (Item, "OptionalFields");
         for Field of Value.Optional_Fields loop
            XML_Writers.Text_Element
              (Item, "Field", Optional_Field_Image (Field));
         end loop;
         XML_Writers.End_Element (Item, "OptionalFields");
      end if;
      XML_Writers.Start_Element (Item, "Schedule");
      XML_Writers.Text_Element
        (Item, "Frequency", Frequency_Image (Value.Schedule.Frequency));
      XML_Writers.End_Element (Item, "Schedule");
      return XML_Writers.Finish (Item, Root_Name);
   exception
      when XML_Writers.Encoding_Error =>
         raise Inventory.Malformed_Inventory with
           "inventory serialization violates caller limits";
   end Serialize;

end
  Flyology.Object_Storage.S3.Generated_Put_Bucket_Inventory_Configuration_XML;
