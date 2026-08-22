with Ada.Strings;
with Ada.Strings.Fixed;

package body Flyology.Object_Storage.Backends is

   function Trim_OWS (Value : String) return String is
      First : Integer := Value'First;
      Last  : Integer := Value'Last;
   begin
      while First <= Last
        and then Value (First) in ' ' | ASCII.HT
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then Value (Last) in ' ' | ASCII.HT
      loop
         Last := Last - 1;
      end loop;
      return (if First > Last then "" else Value (First .. Last));
   end Trim_OWS;

   procedure Read_Entity_Tag_List
     (Value       : String;
      Entity_Tag  : String;
      Weak_Match  : Boolean;
      Valid       : out Boolean;
      Matches     : out Boolean)
   is
      Text   : constant String := Trim_OWS (Value);
      Cursor : Integer := Text'First;
   begin
      Valid := False;
      Matches := False;
      if Text'Length = 0 then
         return;
      elsif Text = "*" then
         Valid := True;
         Matches := True;
         return;
      elsif Ada.Strings.Fixed.Index (Text, "*") /= 0 then
         return;
      end if;

      while Cursor <= Text'Last loop
         declare
            Separator : constant Natural :=
              Ada.Strings.Fixed.Index
                (Text, ",", From => Positive (Cursor));
            Last : constant Integer :=
              (if Separator = 0 then Text'Last else Separator - 1);
            Token : constant String := Trim_OWS (Text (Cursor .. Last));
            Weak : constant Boolean :=
              Token'Length >= 2
              and then Token (Token'First .. Token'First + 1) = "W/";
            Quote_First : constant Integer :=
              Token'First + (if Weak then 2 else 0);
         begin
            if Token'Length < (if Weak then 4 else 2)
              or else Token (Quote_First) /= '"'
              or else Token (Token'Last) /= '"'
            then
               return;
            end if;
            for Index in Quote_First + 1 .. Token'Last - 1 loop
               if Character'Pos (Token (Index)) < 16#21#
                 or else Token (Index) = '"'
                 or else Character'Pos (Token (Index)) = 16#7F#
               then
                  return;
               end if;
            end loop;
            if (not Weak or else Weak_Match)
              and then Token (Quote_First + 1 .. Token'Last - 1) = Entity_Tag
            then
               Matches := True;
            end if;
            exit when Separator = 0;
            Cursor := Separator + 1;
            if Cursor > Text'Last then
               return;
            end if;
         end;
      end loop;
      Valid := True;
   end Read_Entity_Tag_List;

   function Valid_Read_Entity_Tag_Condition
     (Value : String) return Boolean
   is
      Valid, Matches : Boolean;
   begin
      Read_Entity_Tag_List (Value, "", True, Valid, Matches);
      return Valid;
   end Valid_Read_Entity_Tag_Condition;

   function Evaluate_Read_Conditions
     (Conditions : Read_Conditions;
      Entity_Tag : String;
      Modified   : Unix_Time) return Status
   is
      Match_Value : constant String :=
        Ada.Strings.Unbounded.To_String (Conditions.If_Match);
      None_Value : constant String :=
        Ada.Strings.Unbounded.To_String (Conditions.If_None_Match);
      Valid, Matches : Boolean;
   begin
      if Match_Value'Length > 0 then
         Read_Entity_Tag_List
           (Match_Value, Entity_Tag, False, Valid, Matches);
         if not Valid then
            return Invalid_Request;
         elsif not Matches then
            return Precondition_Failed;
         end if;
      elsif Conditions.If_Unmodified_Since.Is_Set
        and then Long_Long_Integer (Modified) >
          Conditions.If_Unmodified_Since.Value
      then
         return Precondition_Failed;
      end if;

      if None_Value'Length > 0 then
         Read_Entity_Tag_List
           (None_Value, Entity_Tag, True, Valid, Matches);
         if not Valid then
            return Invalid_Request;
         elsif Matches then
            return Not_Modified;
         end if;
      elsif Conditions.If_Modified_Since.Is_Set
        and then Long_Long_Integer (Modified) <=
          Conditions.If_Modified_Since.Value
      then
         return Not_Modified;
      end if;
      return Success;
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

end Flyology.Object_Storage.Backends;
