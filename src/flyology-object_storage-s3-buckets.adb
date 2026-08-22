with Flyology.Object_Storage.S3.XML;

package body Flyology.Object_Storage.S3.Buckets is

   package US renames Ada.Strings.Unbounded;

   function Is_Empty (Value : Create_Bucket_Configuration) return Boolean is
     (US.Length (Value.Location_Constraint) = 0
      and then US.Length (Value.Location_Type) = 0
      and then US.Length (Value.Location_Name) = 0
      and then US.Length (Value.Data_Redundancy) = 0
      and then US.Length (Value.Bucket_Type) = 0
      and then Value.Tags.Is_Empty);

   function Valid_Location_Constraint (Value : String) return Boolean is
     (Value = "af-south-1"
      or else Value = "ap-east-1"
      or else Value = "ap-east-2"
      or else Value = "ap-northeast-1"
      or else Value = "ap-northeast-2"
      or else Value = "ap-northeast-3"
      or else Value = "ap-south-1"
      or else Value = "ap-south-2"
      or else Value = "ap-southeast-1"
      or else Value = "ap-southeast-2"
      or else Value = "ap-southeast-3"
      or else Value = "ap-southeast-4"
      or else Value = "ap-southeast-5"
      or else Value = "ap-southeast-6"
      or else Value = "ap-southeast-7"
      or else Value = "ca-central-1"
      or else Value = "ca-west-1"
      or else Value = "cn-north-1"
      or else Value = "cn-northwest-1"
      or else Value = "EU"
      or else Value = "eu-central-1"
      or else Value = "eu-central-2"
      or else Value = "eu-north-1"
      or else Value = "eu-south-1"
      or else Value = "eu-south-2"
      or else Value = "eu-west-1"
      or else Value = "eu-west-2"
      or else Value = "eu-west-3"
      or else Value = "il-central-1"
      or else Value = "me-central-1"
      or else Value = "me-south-1"
      or else Value = "mx-central-1"
      or else Value = "sa-east-1"
      or else Value = "us-east-2"
      or else Value = "us-gov-east-1"
      or else Value = "us-gov-west-1"
      or else Value = "us-west-1"
      or else Value = "us-west-2");

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Serialize_Create_Configuration
     (Value : Create_Bucket_Configuration) return String
   is
      Constraint_Value : constant String :=
        US.To_String (Value.Location_Constraint);
      Location_Type : constant String := US.To_String (Value.Location_Type);
      Location_Name : constant String := US.To_String (Value.Location_Name);
      Redundancy : constant String := US.To_String (Value.Data_Redundancy);
      Bucket_Type : constant String := US.To_String (Value.Bucket_Type);
      Has_Location : constant Boolean :=
        Location_Type'Length > 0 or else Location_Name'Length > 0;
      Has_Bucket : constant Boolean :=
        Redundancy'Length > 0 or else Bucket_Type'Length > 0;
      Result : US.Unbounded_String;
   begin
      if Is_Empty (Value) then
         return "";
      end if;
      if (Constraint_Value'Length > 0
          and then not Valid_Location_Constraint (Constraint_Value))
        or else (Has_Location
                 and then (Location_Type'Length = 0
                           or else Location_Name'Length = 0))
        or else (Location_Type'Length > 0
                 and then Location_Type /= "AvailabilityZone"
                 and then Location_Type /= "LocalZone")
        or else (Has_Bucket
                 and then (Redundancy'Length = 0
                           or else Bucket_Type'Length = 0))
        or else (Redundancy'Length > 0
                 and then Redundancy /= "SingleAvailabilityZone"
                 and then Redundancy /= "SingleLocalZone")
        or else (Bucket_Type'Length > 0 and then Bucket_Type /= "Directory")
        or else (Constraint_Value'Length > 0
                 and then (Has_Location or else Has_Bucket))
      then
         raise Invalid_Bucket_Configuration with
           "invalid CreateBucket configuration";
      end if;
      for Item of Value.Tags loop
         if US.Length (Item.Key) = 0 then
            raise Invalid_Bucket_Configuration with
              "CreateBucket tag key is empty";
         end if;
      end loop;
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<CreateBucketConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">");
      if Constraint_Value'Length > 0 then
         US.Append
           (Result, Element ("LocationConstraint", Constraint_Value));
      end if;
      if Has_Location then
         US.Append
           (Result,
            "<Location>" & Element ("Type", Location_Type) &
            Element ("Name", Location_Name) & "</Location>");
      end if;
      if Has_Bucket then
         US.Append
           (Result,
            "<Bucket>" & Element ("DataRedundancy", Redundancy) &
            Element ("Type", Bucket_Type) & "</Bucket>");
      end if;
      if not Value.Tags.Is_Empty then
         US.Append (Result, "<Tags>");
         for Item of Value.Tags loop
            US.Append
              (Result,
               "<Tag>" & Element ("Key", US.To_String (Item.Key)) &
               Element ("Value", US.To_String (Item.Value)) & "</Tag>");
         end loop;
         US.Append (Result, "</Tags>");
      end if;
      US.Append (Result, "</CreateBucketConfiguration>");
      return US.To_String (Result);
   exception
      when XML.XML_Error =>
         raise Invalid_Bucket_Configuration with
           "CreateBucket configuration contains invalid XML text";
   end Serialize_Create_Configuration;

end Flyology.Object_Storage.S3.Buckets;
