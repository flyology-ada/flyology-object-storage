with Ada.Finalization;
with Ada.Real_Time;
with Ada.Strings.Unbounded;
with Ada.Streams;
with Flyology.Cancellation;
with Flyology.Object_Storage.Tags;

--  Provides a bounded concurrent in-memory backend. Byte_Capacity covers
--  retained committed, staged, and in-progress payload buffer capacity;
--  atomic overwrite and multipart assembly therefore require coexistence
--  headroom. It implements the same contract as durable backends and is the
--  reference oracle for conformance tests; capacity exhaustion is an ordinary
--  reported outcome.
package Flyology.Object_Storage.Backends.Memory is

   type Store
     (Bucket_Capacity : Positive;
      Object_Capacity : Positive;
      Byte_Capacity   : Byte_Count)
   is limited new Backend with private;

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

   overriding procedure Put_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Value    : Tags.Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status);

   overriding procedure Get_Bucket_Tags
     (Item     : in out Store;
      Bucket   : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Value    : out Tags.Tag_Set;
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
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result : out Status);

   overriding procedure Get_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags : out Object_Tag_Set; Result : out Status);

   overriding procedure Delete_Object_Tags
     (Item : in out Store; Bucket, Key : String;
      Token : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
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

   --  Return the current retained byte total, including committed objects,
   --  staged multipart parts, and reserved in-progress input and immutable
   --  outbound snapshot buffer capacity.
   function Bytes_Used (Item : Store) return Byte_Count;

private
   type Byte_Array_Access is access Ada.Streams.Stream_Element_Array;

   type Owned_Bytes is new Ada.Finalization.Controlled with record
      Value    : Byte_Array_Access := null;
      Length   : Natural := 0;
      Capacity : Natural := 0;
   end record;

   overriding procedure Adjust (Data : in out Owned_Bytes);
   overriding procedure Finalize (Data : in out Owned_Bytes);
   procedure Append
     (Data  : in out Owned_Bytes;
      Value : Ada.Streams.Stream_Element_Array);
   procedure Append (Data : in out Owned_Bytes; Value : Owned_Bytes);
   procedure Reserve_Capacity
     (Data : in out Owned_Bytes; Capacity : Natural);
   procedure Move (Target : in out Owned_Bytes; Source : in out Owned_Bytes);
   function Element
     (Data : Owned_Bytes; Index : Positive)
      return Ada.Streams.Stream_Element;

   type Bucket_Slot is record
      Used    : Boolean := False;
      Name    : Ada.Strings.Unbounded.Unbounded_String;
      Created : Unix_Time := 0;
      Tags    : Flyology.Object_Storage.Tags.Tag_Set;
   end record;
   type Bucket_Array is array (Positive range <>) of Bucket_Slot;

   type Object_Slot is record
      Used   : Boolean := False;
      Bucket : Ada.Strings.Unbounded.Unbounded_String;
      Key    : Ada.Strings.Unbounded.Unbounded_String;
      Info   : Object_Information;
      Tags   : Object_Tag_Set;
      Completed_Parts : Completed_Object_Part_List;
      Data   : Owned_Bytes;
   end record;
   type Object_Array is array (Positive range <>) of Object_Slot;

   type Upload_Slot is record
      Used       : Boolean := False;
      ID         : Ada.Strings.Unbounded.Unbounded_String;
      Bucket     : Ada.Strings.Unbounded.Unbounded_String;
      Key        : Ada.Strings.Unbounded.Unbounded_String;
      Options    : Multipart_Options := Default_Multipart_Options;
      Created    : Unix_Time := 0;
   end record;
   type Upload_Array is array (Positive range <>) of Upload_Slot;

   type Part_Slot is record
      Used       : Boolean := False;
      Upload_ID  : Ada.Strings.Unbounded.Unbounded_String;
      Number     : Multipart_Part_Number := Multipart_Part_Number'First;
      Info       : Object_Information;
      Data       : Owned_Bytes;
   end record;
   type Part_Array is array (Positive range <>) of Part_Slot;

   protected type Memory_State
     (Bucket_Limit : Positive;
      Object_Limit : Positive;
      Byte_Limit   : Byte_Count)
   is
      procedure Create_Bucket
        (Name : String; Created : Unix_Time; Result : out Status);
      procedure List_Buckets
        (Options : List_Buckets_Options;
         Page    : out Bucket_Page;
         Result  : out Status);
      procedure Head_Bucket (Name : String; Result : out Status);
      procedure Delete_Bucket (Name : String; Result : out Status);
      procedure Put_Bucket_Tags
        (Name : String; Value : Tags.Tag_Set; Result : out Status);
      procedure Get_Bucket_Tags
        (Name : String; Value : out Tags.Tag_Set; Result : out Status);
      procedure Reserve_Transient
        (Amount : Byte_Count; Result : out Status);
      procedure Release_Transient (Amount : Byte_Count);
      procedure Commit
        (Bucket : String;
         Key    : String;
         Data   : in out Owned_Bytes;
         Info   : Object_Information;
         Stored : out Object_Information;
         Result : out Status);
      procedure Fetch
        (Bucket : String;
         Key    : String;
         Data   : out Owned_Bytes;
         Info   : out Object_Information;
         Result : out Status);
      procedure Fetch_Range
        (Bucket    : String;
         Key       : String;
         Requested : Byte_Range;
         Data      : out Owned_Bytes;
         Info      : out Object_Information;
         Result    : out Status);
      procedure Head
        (Bucket : String;
         Key    : String;
         Info   : out Object_Information;
         Result : out Status);
      procedure Attributes
        (Bucket   : String;
         Key      : String;
         Options  : Object_Attribute_Options;
         Snapshot : out Object_Attribute_Snapshot;
         Result   : out Status);
      procedure Delete
        (Bucket : String;
         Key    : String;
         Result : out Status);
      procedure Put_Tags
        (Bucket : String; Key : String; Tags : Object_Tag_Set;
         Result : out Status);
      procedure Get_Tags
        (Bucket : String; Key : String; Tags : out Object_Tag_Set;
         Result : out Status);
      procedure Delete_Tags
        (Bucket : String; Key : String; Result : out Status);
      procedure List
        (Bucket  : String;
         Options : List_Options;
         Page    : out List_Page;
         Result  : out Status);
      procedure Start_Multipart
        (Bucket    : String;
         Key       : String;
         Options   : Multipart_Options;
         Created   : Unix_Time;
         Upload_ID : out Ada.Strings.Unbounded.Unbounded_String;
         Result    : out Status);
      procedure List_Uploads
        (Bucket  : String;
         Options : List_Multipart_Uploads_Options;
         Page    : out Multipart_Upload_Page;
         Result  : out Status);
      procedure Commit_Part
        (Bucket      : String;
         Key         : String;
         Upload_ID   : String;
         Part_Number : Multipart_Part_Number;
         Data        : in out Owned_Bytes;
         Info        : Object_Information;
         Stored      : out Object_Information;
         Result      : out Status);
      procedure List_Parts
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Options   : List_Multipart_Parts_Options;
         Page      : out Multipart_Part_Page;
         Result    : out Status);
      procedure Complete_Multipart
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Completion : Multipart_Part_References;
         Options   : Complete_Multipart_Options;
         Modified  : Unix_Time;
         Info      : out Object_Information;
         Result    : out Status);
      procedure Abort_Multipart
        (Bucket    : String;
         Key       : String;
         Upload_ID : String;
         Conditions : Abort_Multipart_Conditions;
         Result    : out Status);
      function Used_Bytes return Byte_Count;
   private
      function Bucket_Index (Name : String) return Natural;
      function Object_Index
        (Bucket : String; Key : String) return Natural;
      function Upload_Index
        (Bucket : String; Key : String; Upload_ID : String) return Natural;
      function Part_Index
        (Upload_ID : String;
         Part_Number : Multipart_Part_Number) return Natural;
      Buckets : Bucket_Array (1 .. Bucket_Limit);
      Objects : Object_Array (1 .. Object_Limit);
      Uploads : Upload_Array (1 .. Object_Limit);
      Parts   : Part_Array (1 .. Object_Limit);
      Highest_Object : Natural := 0;
      Highest_Part   : Natural := 0;
      Bytes   : Byte_Count := 0;
      Reserved_Bytes : Byte_Count := 0;
      Next_Upload : Long_Long_Integer := 0;
   end Memory_State;

   type Store
     (Bucket_Capacity : Positive;
      Object_Capacity : Positive;
      Byte_Capacity   : Byte_Count)
   is limited new Backend with record
      State : Memory_State
        (Bucket_Capacity, Object_Capacity, Byte_Capacity);
   end record;

end Flyology.Object_Storage.Backends.Memory;
