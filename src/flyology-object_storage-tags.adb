with Ada.Wide_Wide_Characters.Unicode;

package body Flyology.Object_Storage.Tags is

   package Unicode renames Ada.Wide_Wide_Characters.Unicode;
   package US renames Ada.Strings.Unbounded;
   use type Ada.Containers.Count_Type;
   use type US.Unbounded_String;

   function Valid_Text
     (Value : String; Maximum : Positive; Empty_Allowed : Boolean)
      return Boolean
   is
      Cursor : Integer := Value'First;
      Count  : Natural := 0;

      function Byte_At (Offset : Natural) return Natural is
        (Character'Pos (Value (Cursor + Integer (Offset))));

      function Continuation (Offset : Natural) return Boolean is
        (Cursor + Integer (Offset) <= Value'Last
         and then Byte_At (Offset) in 16#80# .. 16#BF#);

      function Allowed (Code : Natural) return Boolean is
         Character_Value : constant Wide_Wide_Character :=
           Wide_Wide_Character'Val (Code);
         Category : constant Unicode.Category :=
           Unicode.Get_Category (Character_Value);
      begin
         return Category in
             Unicode.Lu | Unicode.Ll | Unicode.Lt | Unicode.Lm | Unicode.Lo |
             Unicode.Nd | Unicode.Nl | Unicode.No |
             Unicode.Zs | Unicode.Zl | Unicode.Zp
           or else Code in
             Character'Pos ('_') | Character'Pos ('.') |
             Character'Pos (':') | Character'Pos ('/') |
             Character'Pos ('=') | Character'Pos ('+') |
             Character'Pos ('-') | Character'Pos ('@');
      end Allowed;
   begin
      if Value'Length = 0 then
         return Empty_Allowed;
      end if;
      while Cursor <= Value'Last loop
         declare
            First : constant Natural := Byte_At (0);
            Width : Positive;
            Code  : Natural;
         begin
            if First <= 16#7F# then
               Width := 1;
               Code := First;
            elsif First in 16#C2# .. 16#DF# and then Continuation (1) then
               Width := 2;
               Code := (First - 16#C0#) * 64 + (Byte_At (1) - 16#80#);
            elsif First in 16#E0# .. 16#EF#
              and then Continuation (1) and then Continuation (2)
              and then (First /= 16#E0# or else Byte_At (1) >= 16#A0#)
              and then (First /= 16#ED# or else Byte_At (1) <= 16#9F#)
            then
               Width := 3;
               Code := (First - 16#E0#) * 4_096
                 + (Byte_At (1) - 16#80#) * 64
                 + (Byte_At (2) - 16#80#);
            elsif First in 16#F0# .. 16#F4#
              and then Continuation (1) and then Continuation (2)
              and then Continuation (3)
              and then (First /= 16#F0# or else Byte_At (1) >= 16#90#)
              and then (First /= 16#F4# or else Byte_At (1) <= 16#8F#)
            then
               Width := 4;
               Code := (First - 16#F0#) * 262_144
                 + (Byte_At (1) - 16#80#) * 4_096
                 + (Byte_At (2) - 16#80#) * 64
                 + (Byte_At (3) - 16#80#);
            else
               return False;
            end if;
            Count := Count + 1;
            if Count > Maximum or else not Allowed (Code) then
               return False;
            end if;
            Cursor := Cursor + Width;
         end;
      end loop;
      return True;
   end Valid_Text;

   function Reserved_Key (Value : String) return Boolean is
     (Value'Length >= 4
      and then Value (Value'First) in 'a' | 'A'
      and then Value (Value'First + 1) in 'w' | 'W'
      and then Value (Value'First + 2) in 's' | 'S'
      and then Value (Value'First + 3) = ':');

   function Valid_Bucket_Tag_Set (Value : Tag_Set) return Boolean is
   begin
      if Value.Is_Empty
        or else Value.Length > Ada.Containers.Count_Type (Maximum_Bucket_Tags)
      then
         return False;
      end if;
      for Index in Value.First_Index .. Value.Last_Index loop
         declare
            Key  : constant String := US.To_String (Value (Index).Key);
            Text : constant String := US.To_String (Value (Index).Value);
         begin
            if Reserved_Key (Key)
              or else not Valid_Text
                (Key, Maximum_Key_Characters, Empty_Allowed => False)
              or else not Valid_Text
                (Text, Maximum_Value_Characters, Empty_Allowed => True)
            then
               return False;
            end if;
            if Index < Value.Last_Index then
               for Other in Index + 1 .. Value.Last_Index loop
                  if Value (Other).Key = Value (Index).Key then
                     return False;
                  end if;
               end loop;
            end if;
         end;
      end loop;
      return True;
   end Valid_Bucket_Tag_Set;

end Flyology.Object_Storage.Tags;
