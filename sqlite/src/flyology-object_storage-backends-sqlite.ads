with Ada.Finalization;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Flyology.Cancellation;
with Flyology.Object_Storage.SQLite.Catalogs;

--  SQLite catalog with immutable object bodies stored as external files.
--  Namespace changes are transactional; startup removes incomplete and
--  superseded payload files left by process interruption.
package Flyology.Object_Storage.Backends.SQLite is

   Configuration_Error : exception;

   type Store is limited new Backend with private;

   function Open
     (Root                : String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last) return Store;

   overriding procedure Create_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure List_Buckets
     (Item     : in out Store;
      Options  : List_Buckets_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out Bucket_Page;
      Result   : out Status);

   overriding procedure Delete_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Head_Bucket
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status);

   overriding procedure Copy_Object
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Copy_Options;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status);

   overriding procedure Head_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status);

   overriding procedure Get_Object
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Requested : Byte_Range;
      Sink      : in out Byte_Sink'Class;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status;
      Conditions : Read_Conditions := Default_Read_Conditions);

   overriding procedure Get_Object_Attributes
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Options  : Object_Attribute_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Snapshot : out Object_Attribute_Snapshot;
      Result   : out Status);

   overriding procedure Delete_Object
     (Item     : in out Store;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Put_Object_Tags
     (Item : in out Store; Bucket, Key : String; Tags : Object_Tag_Set;
      Token : access Flyology.Cancellation.Token; Deadline : Ada.Real_Time.Time;
      Result : out Status);

   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token; Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Result : out Status);

   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token; Deadline : Ada.Real_Time.Time;
      Result : out Status);

   overriding procedure List_Objects
     (Item     : in out Store;
      Bucket   : String;
      Options  : List_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Page     : out List_Page;
      Result   : out Status);

   overriding procedure Create_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Options   : Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
      Result    : out Status);

   overriding procedure Put_Multipart_Part
     (Item        : in out Store;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status);

   overriding procedure List_Multipart_Parts
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Options   : List_Multipart_Parts_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Part_Page;
      Result    : out Status);

   overriding procedure List_Multipart_Uploads
     (Item      : in out Store;
      Bucket    : String;
      Options   : List_Multipart_Uploads_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Page      : out Multipart_Upload_Page;
      Result    : out Status);

   overriding procedure Copy_Multipart_Part
     (Item               : in out Store;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Upload_ID          : String;
      Part_Number        : Multipart_Part_Number;
      Requested          : Byte_Range;
      Conditions         : Copy_Conditions;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status);

   overriding procedure Complete_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Options   : Complete_Multipart_Options;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status);

   overriding procedure Abort_Multipart_Upload
     (Item      : in out Store;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Conditions : Abort_Multipart_Conditions;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Result    : out Status);

   function Root_Directory (Item : Store) return String;

private
   type Root_Lock is
     limited new Ada.Finalization.Limited_Controlled with record
      Root   : Ada.Strings.Unbounded.Unbounded_String;
      Locked : Boolean := False;
   end record;

   overriding procedure Finalize (Item : in out Root_Lock);

   protected type Sequence is
      procedure Next (Value : out Long_Long_Integer);
   private
      Value : Long_Long_Integer := 0;
   end Sequence;

   type Store is limited new Backend with record
      Root_Path           : Ada.Strings.Unbounded.Unbounded_String;
      Maximum_Object_Size : Byte_Count := Byte_Count'Last;
      Temp_Sequence       : Sequence;
      Lock                : Root_Lock;
      Catalog             : Flyology.Object_Storage.SQLite.Catalogs.Catalog;
   end record;

end Flyology.Object_Storage.Backends.SQLite;
