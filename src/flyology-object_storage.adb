package body Flyology.Object_Storage
  with SPARK_Mode => On
is

   function Starts_With (Value, Prefix : String) return Boolean is
     (Value'Length >= Prefix'Length
      and then Value
        (Value'First .. Value'First - 1 + Prefix'Length) = Prefix);

   function Ends_With (Value, Suffix : String) return Boolean is
     (Suffix'Length = 0
      or else
        (Value'Length >= Suffix'Length
         and then Value
           (Value'Last - (Suffix'Length - 1) .. Value'Last) = Suffix));

   function Looks_Like_IPv4 (Value : String) return Boolean is
      subtype Part_Count is Natural range 0 .. 3;
      subtype Decimal_Digit_Count is Natural range 0 .. 3;
      subtype Octet is Natural range 0 .. 255;

      Parts       : Part_Count := 0;
      Digit_Count : Decimal_Digit_Count := 0;
      Octet_Value : Octet := 0;
   begin
      for Character_Value of Value loop
         if Character_Value in '0' .. '9' then
            if Digit_Count = Decimal_Digit_Count'Last then
               return False;
            end if;
            Digit_Count := Digit_Count + 1;
            declare
               subtype Decimal_Digit is Natural range 0 .. 9;
               Digit : constant Decimal_Digit :=
                 Character'Pos (Character_Value) - Character'Pos ('0');
            begin
               if Octet_Value > 25
                 or else (Octet_Value = 25 and then Digit > 5)
               then
                  return False;
               end if;
               Octet_Value := Octet_Value * 10 + Digit;
            end;
         elsif Character_Value = '.' and then Digit_Count > 0 then
            if Parts = Part_Count'Last then
               return False;
            end if;
            Parts := Parts + 1;
            Digit_Count := 0;
            Octet_Value := 0;
         else
            return False;
         end if;
      end loop;
      return Parts = 3 and then Digit_Count > 0;
   end Looks_Like_IPv4;

   function Valid_Bucket_Name (Value : String) return Boolean is
      Previous_Dot : Boolean := False;
      Previous_Hyphen : Boolean := False;
   begin
      if Value'Length not in 3 .. 63
        or else Value (Value'First) in '.' | '-'
        or else Value (Value'Last) in '.' | '-'
        or else Looks_Like_IPv4 (Value)
        or else Starts_With (Value, "xn--")
        or else Starts_With (Value, "sthree-")
        or else Starts_With (Value, "amzn-s3-demo-")
        or else Ends_With (Value, "-s3alias")
        or else Ends_With (Value, "--ol-s3")
        or else Ends_With (Value, ".mrap")
        or else Ends_With (Value, "--x-s3")
        or else Ends_With (Value, "--table-s3")
        or else Ends_With (Value, "-an")
      then
         return False;
      end if;

      for Character_Value of Value loop
         if not (Character_Value in 'a' .. 'z'
                 or else Character_Value in '0' .. '9'
                 or else Character_Value in '.' | '-')
         then
            return False;
         end if;
         if Character_Value = '.'
           and then (Previous_Dot or else Previous_Hyphen)
         then
            return False;
         elsif Character_Value = '-'
           and then Previous_Dot
         then
            return False;
         end if;
         Previous_Dot := Character_Value = '.';
         Previous_Hyphen := Character_Value = '-';
      end loop;
      return True;
   end Valid_Bucket_Name;

   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
      for Character_Value of Value loop
         if Character_Value = Character'Val (0) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Object_Key;

   function Valid_Object_Tag_Set (Tags : Object_Tag_Set) return Boolean is
   begin
      for Index in 1 .. Tags.Length loop
         declare
            Key : constant String :=
              Ada.Strings.Unbounded.To_String (Tags.Items (Index).Key);
            Value : constant String :=
              Ada.Strings.Unbounded.To_String (Tags.Items (Index).Value);
         begin
            if Key'Length not in 1 .. 512 or else Value'Length > 1_024 then
               return False;
            end if;
            for Character_Value of Key loop
               if Character_Value = Character'Val (0) then
                  return False;
               end if;
            end loop;
            for Character_Value of Value loop
               if Character_Value = Character'Val (0) then
                  return False;
               end if;
            end loop;
            for Previous in 1 .. Index - 1 loop
               if Ada.Strings.Unbounded."="
                 (Tags.Items (Previous).Key, Tags.Items (Index).Key)
               then
                  return False;
               end if;
            end loop;
         end;
      end loop;
      return True;
   end Valid_Object_Tag_Set;

   function Resolve_Range
     (Size : Byte_Count; Request : Byte_Range) return Range_Resolution
   is
      Effective_Last  : Byte_Count;
      Effective_First : Byte_Count;
   begin
      if Size = 0 then
         if Request.Kind = Whole_Range then
            return (Kind => Empty_Object_Range);
         else
            return (Kind => Unsatisfiable_Range);
         end if;
      end if;

      case Request.Kind is
         when Whole_Range =>
            return
              (Kind   => Satisfied_Range,
               First  => 0,
               Last   => Size - 1,
               Length => Size);

         when Bounded_Range =>
            if Request.First > Request.Last or else Request.First >= Size then
               return (Kind => Unsatisfiable_Range);
            end if;
            Effective_Last :=
              (if Request.Last < Size then Request.Last else Size - 1);
            return
              (Kind   => Satisfied_Range,
               First  => Request.First,
               Last   => Effective_Last,
               Length => Effective_Last - Request.First + 1);

         when Open_Ended_Range =>
            if Request.First >= Size then
               return (Kind => Unsatisfiable_Range);
            end if;
            return
              (Kind   => Satisfied_Range,
               First  => Request.First,
               Last   => Size - 1,
               Length => Size - Request.First);

         when Suffix_Range =>
            if Request.Count = 0 then
               return (Kind => Unsatisfiable_Range);
            end if;
            Effective_First :=
              (if Request.Count >= Size then 0 else Size - Request.Count);
            return
              (Kind   => Satisfied_Range,
               First  => Effective_First,
               Last   => Size - 1,
               Length => Size - Effective_First);
      end case;
   end Resolve_Range;

end Flyology.Object_Storage;
