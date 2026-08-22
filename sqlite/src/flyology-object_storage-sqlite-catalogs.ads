with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.Backends;
with Flyology.Object_Storage.SQLite.Databases;

--  Transactional namespace and object metadata for the SQLite backend.
--  Payloads are immutable external files named by the backend.
package Flyology.Object_Storage.SQLite.Catalogs is

   Catalog_Error : exception;

   type Catalog is limited private;

   procedure Open (Item : in out Catalog; Path : String);
   procedure Close (Item : in out Catalog);

   procedure Create_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Head_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

   procedure Delete_Bucket
     (Item : in out Catalog; Name : String; Result : out Status);

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
      Result  : out Status);

   procedure Delete_Object
     (Item    : in out Catalog;
      Bucket  : String;
      Key     : String;
      Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Result  : out Status);

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
      Previous_Payload : out Ada.Strings.Unbounded.Unbounded_String;
      Retired_Payloads : out Payloads;
      Result           : out Status);

   procedure Abort_Multipart_Upload
     (Item             : in out Catalog;
      Bucket           : String;
      Key              : String;
      Upload_ID        : String;
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
