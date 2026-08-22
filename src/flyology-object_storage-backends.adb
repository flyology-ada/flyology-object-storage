with Ada.Strings;
with Ada.Strings.Fixed;

package body Flyology.Object_Storage.Backends is

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

end Flyology.Object_Storage.Backends;
