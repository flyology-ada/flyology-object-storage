package body Flyology.Object_Storage.Backends is

   function Valid_Version_Selector
     (Selector : Version_Selector) return Boolean
   is
      ID : constant String :=
        Ada.Strings.Unbounded.To_String (Selector.ID);
   begin
      case Selector.Kind is
         when Current_Version | Null_Version =>
            return ID'Length = 0;
         when Exact_Version =>
            return ID'Length in 1 .. Maximum_Version_ID_Length
              and then ID /= "null";
      end case;
   end Valid_Version_Selector;

   procedure Put_Object_Tags
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Tags     : Object_Tag_Set;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector)
   is
      Identity : Version_Identity;
   begin
      Item.Put_Object_Tags
        (Bucket, Key, Tags, Token, Deadline, Identity, Result, Selector);
   end Put_Object_Tags;

   procedure Get_Object_Tags
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Tags     : out Object_Tag_Set;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector)
   is
      Identity : Version_Identity;
   begin
      Item.Get_Object_Tags
        (Bucket, Key, Token, Deadline, Tags, Identity, Result, Selector);
   end Get_Object_Tags;

   procedure Delete_Object_Tags
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status;
      Selector : Version_Selector := Current_Version_Selector)
   is
      Identity : Version_Identity;
   begin
      Item.Delete_Object_Tags
        (Bucket, Key, Token, Deadline, Identity, Result, Selector);
   end Delete_Object_Tags;

   procedure Put_Multipart_Part
     (Item        : in out Backend'Class;
      Bucket      : String;
      Key         : String;
      Upload_ID   : String;
      Part_Number : Multipart_Part_Number;
      Source      : in out Byte_Source'Class;
      Token       : access Flyology.Cancellation.Token;
      Deadline    : Ada.Real_Time.Time;
      Info        : out Object_Information;
      Result      : out Status) is
   begin
      Item.Put_Multipart_Part
        (Bucket, Key, Upload_ID, Part_Number, Source,
         Default_Multipart_Part_Options, Token, Deadline, Info, Result);
   end Put_Multipart_Part;

   function Valid_Read_Entity_Tag_Condition
     (Value : String) return Boolean is
     (Valid_Object_Read_Entity_Tag_Condition (Value));

   function Evaluate_Read_Conditions
     (Conditions : Read_Conditions;
      Entity_Tag : String;
      Modified   : Unix_Time) return Status
   is
   begin
      return Evaluate_Object_Read_Conditions
        (If_Match =>
           Ada.Strings.Unbounded.To_String (Conditions.If_Match),
         If_None_Match =>
           Ada.Strings.Unbounded.To_String (Conditions.If_None_Match),
         Has_If_Modified_Since => Conditions.If_Modified_Since.Is_Set,
         If_Modified_Since =>
           (if Conditions.If_Modified_Since.Is_Set
            then Conditions.If_Modified_Since.Value else 0),
         Has_If_Unmodified_Since => Conditions.If_Unmodified_Since.Is_Set,
         If_Unmodified_Since =>
           (if Conditions.If_Unmodified_Since.Is_Set
            then Conditions.If_Unmodified_Since.Value else 0),
         Entity_Tag => Entity_Tag,
         Modified => Modified);
   end Evaluate_Read_Conditions;

   function Evaluate_Copy_Conditions
     (Conditions : Copy_Conditions;
      Entity_Tag : String;
      Modified   : Unix_Time) return Status
   is
   begin
      return Evaluate_Object_Copy_Conditions
        (If_Match =>
           Ada.Strings.Unbounded.To_String (Conditions.If_Match),
         If_None_Match =>
           Ada.Strings.Unbounded.To_String (Conditions.If_None_Match),
         Has_If_Modified_Since => Conditions.If_Modified_Since.Is_Set,
         If_Modified_Since =>
           (if Conditions.If_Modified_Since.Is_Set
            then Conditions.If_Modified_Since.Value else 0),
         Has_If_Unmodified_Since => Conditions.If_Unmodified_Since.Is_Set,
         If_Unmodified_Since =>
           (if Conditions.If_Unmodified_Since.Is_Set
            then Conditions.If_Unmodified_Since.Value else 0),
         Entity_Tag => Entity_Tag,
         Modified => Modified);
   end Evaluate_Copy_Conditions;

   function Valid_Copy_Conditions
     (Conditions : Copy_Conditions) return Boolean is
     (Valid_Object_Write_Conditions
        (Ada.Strings.Unbounded.To_String (Conditions.If_Match),
         Ada.Strings.Unbounded.To_String (Conditions.If_None_Match)));

   function Evaluate_Write_Conditions
     (Conditions : Write_Conditions;
      Exists     : Boolean;
      Entity_Tag : String) return Status
   is
     (Evaluate_Object_Write_Conditions
        (Ada.Strings.Unbounded.To_String (Conditions.If_Match),
         Ada.Strings.Unbounded.To_String (Conditions.If_None_Match),
         Exists, Entity_Tag));

   function Valid_Write_Conditions
     (Conditions : Write_Conditions) return Boolean is
     (Valid_Object_Write_Conditions
        (Ada.Strings.Unbounded.To_String (Conditions.If_Match),
         Ada.Strings.Unbounded.To_String (Conditions.If_None_Match)));

   function Evaluate_Delete_Object_Conditions
     (Conditions : Delete_Object_Conditions;
      Exists     : Boolean;
      Info       : Object_Information) return Status
   is
   begin
      return Evaluate_Object_Delete_Conditions
        (Has_ETag => Conditions.Has_ETag,
         ETag => Ada.Strings.Unbounded.To_String (Conditions.ETag),
         Has_Last_Modified_Time => Conditions.Has_Last_Modified_Time,
         Last_Modified_Time => Conditions.Last_Modified_Time,
         Has_Size => Conditions.Has_Size,
         Expected_Size => Conditions.Size,
         Exists => Exists,
         Entity_Tag => Ada.Strings.Unbounded.To_String (Info.Entity_Tag),
         Modified => Info.Modified,
         Size => Info.Size);
   end Evaluate_Delete_Object_Conditions;

   procedure Complete_Multipart_Upload
     (Item      : in out Backend'Class;
      Bucket    : String;
      Key       : String;
      Upload_ID : String;
      Parts     : Multipart_Part_References;
      Token     : access Flyology.Cancellation.Token;
      Deadline  : Ada.Real_Time.Time;
      Info      : out Object_Information;
      Result    : out Status) is
   begin
      Item.Complete_Multipart_Upload
        (Bucket, Key, Upload_ID, Parts, Default_Complete_Multipart_Options,
         Token, Deadline, Info, Result);
   end Complete_Multipart_Upload;

end Flyology.Object_Storage.Backends;
