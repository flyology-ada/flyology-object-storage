package body Flyology.Object_Storage.S3.Wire_Core
  with SPARK_Mode => On
is
   function Parse_Natural (Text : String) return Natural_Result is
      Result : Natural := 0;
      Digit  : Natural;
   begin
      if Text'Length = 0 then
         return (Valid => False);
      end if;
      for Character_Value of Text loop
         if Character_Value not in '0' .. '9' then
            return (Valid => False);
         end if;
         Digit := Character'Pos (Character_Value) - Character'Pos ('0');
         if Result > (Natural'Last - Digit) / 10 then
            return (Valid => False);
         end if;
         Result := Result * 10 + Digit;
      end loop;
      return (Valid => True, Value => Result);
   end Parse_Natural;

   function Parse_Byte_Count (Text : String) return Byte_Count_Result is
      Result : Byte_Count := 0;
      Digit  : Byte_Count;
   begin
      if Text'Length = 0 then
         return (Valid => False);
      end if;
      for Character_Value of Text loop
         if Character_Value not in '0' .. '9' then
            return (Valid => False);
         end if;
         Digit := Byte_Count
           (Character'Pos (Character_Value) - Character'Pos ('0'));
         if Result > (Byte_Count'Last - Digit) / 10 then
            return (Valid => False);
         end if;
         Result := Result * 10 + Digit;
      end loop;
      return (Valid => True, Value => Result);
   end Parse_Byte_Count;

   function Parse_Boolean (Text : String) return Boolean_Result is
     (if Text = "true" then (Valid => True, Value => True)
      elsif Text = "false" then (Valid => True, Value => False)
      else (Valid => False));

   function Base64_Character (Value : Character) return Boolean is
     (Value in 'A' .. 'Z'
      or else Value in 'a' .. 'z'
      or else Value in '0' .. '9'
      or else Value = '+'
      or else Value = '/');

   function Valid_Base64
     (Text : String; Decoded_Length : Natural) return Boolean
   is
      Encoded_Length : constant Natural :=
        4 * ((Decoded_Length + 2) / 3);
   begin
      if Text'Length /= Encoded_Length then
         return False;
      end if;
      if Encoded_Length = 0 then
         return True;
      end if;
      case Decoded_Length mod 3 is
         when 0 =>
            for Character_Value of Text loop
               if not Base64_Character (Character_Value) then
                  return False;
               end if;
            end loop;
            return True;
         when 1 =>
            for Index in Text'First .. Text'Last - 3 loop
               if not Base64_Character (Text (Index)) then
                  return False;
               end if;
            end loop;
            return
              Text (Text'Last - 2) in 'A' | 'Q' | 'g' | 'w'
              and then Text (Text'Last - 1) = '='
              and then Text (Text'Last) = '=';
         when 2 =>
            for Index in Text'First .. Text'Last - 2 loop
               if not Base64_Character (Text (Index)) then
                  return False;
               end if;
            end loop;
            return
              Text (Text'Last - 1) in
                'A' | 'E' | 'I' | 'M' | 'Q' | 'U' | 'Y' | 'c' |
                'g' | 'k' | 'o' | 's' | 'w' | '0' | '4' | '8'
              and then Text (Text'Last) = '=';
         when others =>
            return False;
      end case;
   end Valid_Base64;

end Flyology.Object_Storage.S3.Wire_Core;
