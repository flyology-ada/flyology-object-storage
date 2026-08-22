with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

--  Typed CreateBucket REST/XML documents shared by clients and servers.
package Flyology.Object_Storage.S3.Buckets is

   Invalid_Bucket_Configuration : exception;

   type Tag is record
      Key   : Ada.Strings.Unbounded.Unbounded_String;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   package Tag_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Tag);

   subtype Tag_List is Tag_Vectors.Vector;

   --  Every member of the pinned CreateBucketConfiguration shape. Empty
   --  paired fields mean that their containing XML structure is absent.
   type Create_Bucket_Configuration is record
      Location_Constraint : Ada.Strings.Unbounded.Unbounded_String;
      Location_Type       : Ada.Strings.Unbounded.Unbounded_String;
      Location_Name       : Ada.Strings.Unbounded.Unbounded_String;
      Data_Redundancy     : Ada.Strings.Unbounded.Unbounded_String;
      Bucket_Type         : Ada.Strings.Unbounded.Unbounded_String;
      Tags                : Tag_List;
   end record;

   function Is_Empty (Value : Create_Bucket_Configuration) return Boolean;

   --  Returns an empty string when the configuration is absent; otherwise
   --  emits the namespaced CreateBucketConfiguration document.
   function Serialize_Create_Configuration
     (Value : Create_Bucket_Configuration) return String;

end Flyology.Object_Storage.S3.Buckets;
