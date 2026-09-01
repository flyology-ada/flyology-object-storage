package body Flyology.Object_Storage.Backends is

   function Empty_Bucket_Metadata_State return Bucket_Metadata_State is
     ((Kind                    => Current_Metadata_Configuration,
       Current_Configuration_Document =>
         Ada.Strings.Unbounded.Null_Unbounded_String,
       Current_Result_Document =>
         Ada.Strings.Unbounded.Null_Unbounded_String,
       Legacy_Result_Document =>
         Ada.Strings.Unbounded.Null_Unbounded_String));

   procedure Reset_Unsupported_Bucket_Metadata_Get
     (Value      : out Bucket_Metadata_State;
      Configured : out Boolean;
      Result     : out Status) is
   begin
      Value := Empty_Bucket_Metadata_State;
      Configured := False;
      Result := Unsupported_Bucket_Metadata_Status;
   end Reset_Unsupported_Bucket_Metadata_Get;

   function Valid_Bucket_CORS_Document (Document : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_CORS_Bytes);

   function Valid_Bucket_Encryption_Document
     (Document : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_Configuration_Bytes);

   function Valid_Bucket_Ownership_Controls_Document
     (Document : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_Configuration_Bytes);

   function Valid_Bucket_Lifecycle_Document
     (Document : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_Configuration_Bytes);

   function Valid_Bucket_Lifecycle_Document
     (Document : String;
      Transition_Default_Minimum_Object_Size : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_Configuration_Bytes
      and then
        Byte_Count (Transition_Default_Minimum_Object_Size'Length) <=
          Maximum_Bucket_Configuration_Bytes - Byte_Count (Document'Length));

   function Valid_Bucket_Logging_Document
     (Document : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_Configuration_Bytes);

   function Valid_Bucket_Notification_Document
     (Document : String) return Boolean is
     (Byte_Count (Document'Length) <= Maximum_Bucket_Configuration_Bytes);

   procedure Put_Bucket_Notification_If_Supported
     (Item     : in out Backend'Class;
      Bucket   : String;
      Document : String;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is
   begin
      if Item in Bucket_Notification_Backend'Class then
         Put_Bucket_Notification
           (Bucket_Notification_Backend'Class (Item), Bucket, Document,
            Token, Deadline, Result);
      else
         Result := Not_Implemented;
      end if;
   end Put_Bucket_Notification_If_Supported;

   procedure Get_Bucket_Notification_If_Supported
     (Item       : in out Backend'Class;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Document   : out Ada.Strings.Unbounded.Unbounded_String;
      Configured : out Boolean;
      Result     : out Status) is
   begin
      Document := Ada.Strings.Unbounded.Null_Unbounded_String;
      Configured := False;
      if Item in Bucket_Notification_Backend'Class then
         Get_Bucket_Notification
           (Bucket_Notification_Backend'Class (Item), Bucket, Token,
            Deadline, Document, Configured, Result);
      else
         Result := Not_Implemented;
      end if;
   end Get_Bucket_Notification_If_Supported;

   function Valid_Bucket_Metadata_State
     (Value : Bucket_Metadata_State) return Boolean
   is
      Configuration_Length : constant Byte_Count := Byte_Count
        (Ada.Strings.Unbounded.Length
           (Value.Current_Configuration_Document));
      Current_Length : constant Byte_Count := Byte_Count
        (Ada.Strings.Unbounded.Length (Value.Current_Result_Document));
      Legacy_Length : constant Byte_Count := Byte_Count
        (Ada.Strings.Unbounded.Length (Value.Legacy_Result_Document));
   begin
      return Configuration_Length > 0
        and then Current_Length > 0
        and then
          (Value.Kind = Legacy_Metadata_Table_Configuration
           or else Legacy_Length = 0)
        and then Configuration_Length <= Maximum_Bucket_Configuration_Bytes
        and then Current_Length <= Maximum_Bucket_Configuration_Bytes
        and then Legacy_Length <= Maximum_Bucket_Configuration_Bytes;
   end Valid_Bucket_Metadata_State;

   procedure Create_Bucket_Metadata_State_If_Supported
     (Item     : in out Backend'Class;
      Bucket   : String;
      Value    : Bucket_Metadata_State;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is
   begin
      if Item in Bucket_Metadata_Backend'Class then
         Create_Bucket_Metadata_State
           (Bucket_Metadata_Backend'Class (Item), Bucket, Value, Token,
            Deadline, Result);
      else
         Result := Unsupported_Bucket_Metadata_Status;
      end if;
   end Create_Bucket_Metadata_State_If_Supported;

   procedure Get_Bucket_Metadata_State_If_Supported
     (Item       : in out Backend'Class;
      Bucket     : String;
      Token      : access Flyology.Cancellation.Token;
      Deadline   : Ada.Real_Time.Time;
      Value      : out Bucket_Metadata_State;
      Configured : out Boolean;
      Result     : out Status) is
   begin
      if Item in Bucket_Metadata_Backend'Class then
         Value := Empty_Bucket_Metadata_State;
         Configured := False;
         Get_Bucket_Metadata_State
           (Bucket_Metadata_Backend'Class (Item), Bucket, Token, Deadline,
            Value, Configured, Result);
      else
         Reset_Unsupported_Bucket_Metadata_Get
           (Value, Configured, Result);
      end if;
   end Get_Bucket_Metadata_State_If_Supported;

   procedure Replace_Bucket_Metadata_State_If_Supported
     (Item     : in out Backend'Class;
      Bucket   : String;
      Expected : Bucket_Metadata_State;
      Value    : Bucket_Metadata_State;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is
   begin
      if Item in Bucket_Metadata_Backend'Class then
         Replace_Bucket_Metadata_State
           (Bucket_Metadata_Backend'Class (Item), Bucket, Expected, Value,
            Token, Deadline, Result);
      else
         Result := Unsupported_Bucket_Metadata_Status;
      end if;
   end Replace_Bucket_Metadata_State_If_Supported;

   procedure Delete_Bucket_Metadata_State_If_Supported
     (Item     : in out Backend'Class;
      Bucket   : String;
      Expected : Bucket_Metadata_State;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Result   : out Status) is
   begin
      if Item in Bucket_Metadata_Backend'Class then
         Delete_Bucket_Metadata_State
           (Bucket_Metadata_Backend'Class (Item), Bucket, Expected, Token,
            Deadline, Result);
      else
         Result := Unsupported_Bucket_Metadata_Status;
      end if;
   end Delete_Bucket_Metadata_State_If_Supported;

   function Valid_Bucket_Named_Configuration
     (Identifier : String; Document : String) return Boolean is
     (Byte_Count (Identifier'Length) <=
        Maximum_Bucket_Configuration_Bytes
      and then Byte_Count (Document'Length) <=
        Maximum_Bucket_Configuration_Bytes -
          Byte_Count (Identifier'Length));

   function Valid_Bucket_Policy (Policy : String) return Boolean is
     (Byte_Count (Policy'Length) <= Maximum_Bucket_Policy_Bytes);

   procedure Put_Object
     (Item     : in out Backend'Class;
      Bucket   : String;
      Key      : String;
      Source   : in out Byte_Source'Class;
      Options  : Put_Options;
      Token    : access Flyology.Cancellation.Token;
      Deadline : Ada.Real_Time.Time;
      Info     : out Object_Information;
      Result   : out Status;
      Conditions : Write_Conditions := Default_Write_Conditions)
   is
      Identity : Version_Identity;
   begin
      Item.Put_Object
        (Bucket, Key, Source, Options, Token, Deadline, Info, Identity,
         Result, Conditions);
   end Put_Object;

   procedure Copy_Object
     (Item               : in out Backend'Class;
      Source_Bucket      : String;
      Source_Key         : String;
      Destination_Bucket : String;
      Destination_Key    : String;
      Options            : Copy_Options;
      Token              : access Flyology.Cancellation.Token;
      Deadline           : Ada.Real_Time.Time;
      Info               : out Object_Information;
      Result             : out Status)
   is
      Source_Identity      : Version_Identity;
      Destination_Identity : Version_Identity;
   begin
      Item.Copy_Object
        (Source_Bucket, Source_Key, Destination_Bucket, Destination_Key,
         Options, Token, Deadline, Info, Source_Identity,
         Destination_Identity, Result);
   end Copy_Object;

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
