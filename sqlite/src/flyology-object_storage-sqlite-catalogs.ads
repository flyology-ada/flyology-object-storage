with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.SQLite.Databases;
with Flyology.Object_Storage.Tags;

--  Transactional namespace and object metadata for the SQLite backend.
--  Payloads are immutable external files named by the backend.
package Flyology.Object_Storage.SQLite.Catalogs is

   Catalog_Error : exception;

   type Catalog is limited private;

   procedure Open (Item : in out Catalog; Path : String);
   procedure Close (Item : in out Catalog);

   procedure Create_Bucket
     (Item    : in out Catalog;
      Name    : String;
      Created : Unix_Time;
      Result  : out Status);

   procedure List_Buckets
     (Item    : in out Catalog;
      Options : Backends.List_Buckets_Options;
      Check   : not null access procedure;
      Page    : out Backends.Bucket_Page;
      Result  : out Status);

   procedure Head_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Delete_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Put_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : Tags.Tag_Set;
      Result : out Status);

   procedure Get_Bucket_Tags
     (Item   : in out Catalog;
      Bucket : String;
      Value  : out Tags.Tag_Set;
      Result : out Status);

   procedure Put_Object
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result           : out Status);

   procedure Find_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Info    : out Object_Information;
      Result  : out Status;
      Check   : access procedure
        (Payload : String; Info : Object_Information) := null);
   --  When present, Check runs after a successful lookup while the catalog
   --  operation gate is still held. It may validate the immutable external
   --  payload before a concurrent publication retires the previous file.

   procedure Get_Object_Attributes
     (Item     : in out Catalog;
      Bucket   : String;
      Key      : String;
      Options  : Backends.Object_Attribute_Options;
      Check    : not null access procedure;
      Snapshot : out Backends.Object_Attribute_Snapshot;
      Result   : out Status);

   procedure Delete_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result  : out Status);

   procedure Put_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : Object_Tag_Set; Result : out Status);

   procedure Get_Object_Tags
     (Item : in out Catalog; Bucket, Key : String;
      Tags : out Object_Tag_Set; Result : out Status);

   procedure Delete_Object_Tags
     (Item : in out Catalog; Bucket, Key : String; Result : out Status);

   procedure List_Objects
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Options;
      Check   : not null access procedure;
      Page    : out Backends.List_Page;
      Result  : out Status);

   function Payload_Referenced
     (Item : in out Catalog; Payload : String) return Boolean;

   type Multipart_Part_Record is record
      Number  : Backends.Multipart_Part_Number :=
        Backends.Multipart_Part_Number'First;
      Payload : Ada.Strings.Unbounded.Unbounded_String;
      Info    : Object_Information;
   end record;

   package Multipart_Part_Record_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Multipart_Part_Record);
   subtype Multipart_Part_Records is Multipart_Part_Record_Vectors.Vector;

   package Payload_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural,
      Element_Type => Ada.Strings.Unbounded.Unbounded_String,
      "=" => Ada.Strings.Unbounded."=");
   subtype Payloads is Payload_Vectors.Vector;

   procedure Create_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Content_Type : String;
      Created      : Unix_Time;
      Result       : out Status);

   procedure Find_Multipart_Upload
     (Item         : in out Catalog;
      Bucket       : String;
      Key          : String;
      Upload_ID    : String;
      Content_Type : out Ada.Strings.Unbounded.Unbounded_String;
      Result       : out Status);

   procedure Put_Multipart_Part
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Part_Number      : Backends.Multipart_Part_Number;
      Payload          : String;
      Info             : Object_Information;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result           : out Status);

   procedure List_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : Backends.List_Multipart_Parts_Options;
      Page      : out Backends.Multipart_Part_Page;
      Result    : out Status);

   procedure List_Multipart_Uploads
     (Item    : in out Catalog;
      Bucket  : String;
      Options : Backends.List_Multipart_Uploads_Options;
      Check   : not null access procedure;
      Page    : out Backends.Multipart_Upload_Page;
      Result  : out Status);

   procedure Read_Multipart_Parts
     (Item      : in out Catalog;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Backends.Multipart_Part_References;
      Records   : out Multipart_Part_Records;
      Result    : out Status);

   procedure Complete_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Selected         : Multipart_Part_Records;
      Payload          : String;
      Info             : Object_Information;
      Conditions       : Backends.Copy_Conditions;
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Retired_Payloads : out Payloads;
      Result           : out Status);

   procedure Abort_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
      Conditions       : Backends.Abort_Multipart_Conditions;
      Retired_Payloads : out Payloads;
      Result           : out Status);

private
   protected type Operation_Gate is
      entry Acquire;
      procedure Release;
   private
      Held : Boolean := False;
   end Operation_Gate;

   type Catalog is limited record
      Database : Flyology.Object_Storage.SQLite.Databases.Database;
      Gate     : Operation_Gate;
   end record;

end Flyology.Object_Storage.SQLite.Catalogs;
