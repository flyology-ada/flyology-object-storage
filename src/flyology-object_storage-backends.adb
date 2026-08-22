with Ada.Strings;
with Ada.Strings.Fixed;

package body Flyology.Object_Storage.Backends is

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

   function Entity_Tag_List_Matches
     (Value : String; Entity_Tag : String) return Boolean
   is
      Cursor : Integer := Value'First;
   begin
      while Cursor <= Value'Last loop
         declare
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index
                (Value, ",", From => Positive (Cursor));
            Last : constant Integer :=
              (if Separator = 0 then Value'Last else Separator - 1);
            Token : constant String :=
              Ada.Strings.Fixed.Trim
                (Value (Cursor .. Last), Ada.Strings.Both);
         begin
            if Token = "*"
              or else Token = Entity_Tag
              or else Token = '"' & Entity_Tag & '"'
            then
               return True;
            end if;
            exit when Separator = 0;
            Cursor := Separator + 1;
         end;
      end loop;
      return False;
   end Entity_Tag_List_Matches;

   function Copy_Conditions_Accept
     (Conditions : Copy_Conditions; Entity_Tag : String) return Boolean
   is
      Match_Value : constant String :=
        Ada.Strings.Unbounded.To_String (Conditions.If_Match);
      None_Match_Value : constant String :=
        Ada.Strings.Unbounded.To_String (Conditions.If_None_Match);
   begin
      return
        (Match_Value'Length = 0
         or else Entity_Tag_List_Matches (Match_Value, Entity_Tag))
        and then
          (None_Match_Value'Length = 0
           or else not Entity_Tag_List_Matches
             (None_Match_Value, Entity_Tag));
   end Copy_Conditions_Accept;

   function Evaluate_Write_Conditions
     (Conditions : Copy_Conditions;
      Exists     : Boolean;
      Entity_Tag : String) return Status
   is
     (Evaluate_Object_Write_Conditions
        (Ada.Strings.Unbounded.To_String (Conditions.If_Match),
         Ada.Strings.Unbounded.To_String (Conditions.If_None_Match),
         Exists, Entity_Tag));

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
