package body Flyology.Object_Storage.S3.SigV4_Encoding
  with SPARK_Mode => On
is
   function Hex (Value : Natural) return Character is
     (if Value < 10
      then Character'Val (Character'Pos ('0') + Value)
      else Character'Val (Character'Pos ('A') + Value - 10))
   with Pre => Value <= 15;

   function Unreserved (Value : Character) return Boolean is
     (Value in 'A' .. 'Z'
      or else Value in 'a' .. 'z'
      or else Value in '0' .. '9'
      or else Value = '-'
      or else Value = '.'
      or else Value = '_'
      or else Value = '~');

   function URI_Encode
     (Value : String; Encode_Slash : Boolean) return String
   is
      Result : String (1 .. 3 * Value'Length) := (others => Character'Val (0));
      Used   : Natural := 0;
   begin
      for Index in Value'Range loop
         pragma Loop_Invariant
           (Used <= 3 * Natural (Index - Value'First));
         declare
            Item : constant Character := Value (Index);
         begin
            if Unreserved (Item)
              or else (Item = '/' and then not Encode_Slash)
            then
               Used := Used + 1;
               Result (Used) := Item;
            else
               Result (Used + 1) := '%';
               Result (Used + 2) := Hex (Character'Pos (Item) / 16);
               Result (Used + 3) := Hex (Character'Pos (Item) mod 16);
               Used := Used + 3;
            end if;
         end;
      end loop;
      pragma Assert (Used <= Result'Length);
      return Result (1 .. Used);
   end URI_Encode;

   function Lowercase (Value : String) return String is
      Result : String (Value'Range);
   begin
      for Index in Value'Range loop
         Result (Index) :=
           (if Value (Index) in 'A' .. 'Z'
            then Character'Val
              (Character'Pos (Value (Index)) +
               Character'Pos ('a') - Character'Pos ('A'))
            else Value (Index));
      end loop;
      return Result;
   end Lowercase;

   function Normalize_Header_Value (Value : String) return String is
      Result     : String (1 .. Value'Length) := (others => Character'Val (0));
      Used       : Natural := 0;
      Saw_Space  : Boolean := True;
   begin
      for Index in Value'Range loop
         pragma Loop_Invariant
           (Used <= Natural (Index - Value'First));
         declare
            Item : constant Character := Value (Index);
         begin
            if Item = ' ' or else Item = Character'Val (9) then
               if not Saw_Space then
                  Used := Used + 1;
                  Result (Used) := ' ';
                  Saw_Space := True;
               end if;
            else
               Used := Used + 1;
               Result (Used) := Item;
               Saw_Space := False;
            end if;
         end;
      end loop;
      pragma Assert (Used <= Result'Length);
      if Used > 0 and then Result (Used) = ' ' then
         Used := Used - 1;
      end if;
      return Result (1 .. Used);
   end Normalize_Header_Value;

   function Valid_Header_Name (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;
      for Item of Value loop
         if not (Item in 'A' .. 'Z'
                 or else Item in 'a' .. 'z'
                 or else Item in '0' .. '9'
                 or else Item = '!'
                 or else Item = '#'
                 or else Item = '$'
                 or else Item = '%'
                 or else Item = '&'
                 or else Item = Character'Val (39)
                 or else Item = '*'
                 or else Item = '+'
                 or else Item = '-'
                 or else Item = '.'
                 or else Item = '^'
                 or else Item = '_'
                 or else Item = Character'Val (96)
                 or else Item = '|'
                 or else Item = '~')
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Header_Name;

   function Valid_SHA256_Hex (Value : String) return Boolean is
   begin
      if Value'Length /= 64 then
         return False;
      end if;
      for Item of Value loop
         if Item not in '0' .. '9' and then Item not in 'a' .. 'f' then
            return False;
         end if;
      end loop;
      return True;
   end Valid_SHA256_Hex;

   function Valid_Timestamp (Value : String) return Boolean is
   begin
      if Value'Length /= 16
        or else Value (Value'First + 8) /= 'T'
        or else Value (Value'Last) /= 'Z'
      then
         return False;
      end if;
      for Offset in 0 .. 14 loop
         if Offset /= 8
           and then Value (Value'First + Offset) not in '0' .. '9'
         then
            return False;
         end if;
      end loop;
      declare
         Year : constant Natural :=
           1_000 * (Character'Pos (Value (Value'First)) -
                    Character'Pos ('0')) +
           100 * (Character'Pos (Value (Value'First + 1)) -
                  Character'Pos ('0')) +
           10 * (Character'Pos (Value (Value'First + 2)) -
                 Character'Pos ('0')) +
           Character'Pos (Value (Value'First + 3)) - Character'Pos ('0');
         Month : constant Natural :=
           10 * (Character'Pos (Value (Value'First + 4)) -
                 Character'Pos ('0')) +
           Character'Pos (Value (Value'First + 5)) - Character'Pos ('0');
         Day : constant Natural :=
           10 * (Character'Pos (Value (Value'First + 6)) -
                 Character'Pos ('0')) +
           Character'Pos (Value (Value'First + 7)) - Character'Pos ('0');
         Hour : constant Natural :=
           10 * (Character'Pos (Value (Value'First + 9)) -
                 Character'Pos ('0')) +
           Character'Pos (Value (Value'First + 10)) - Character'Pos ('0');
         Minute : constant Natural :=
           10 * (Character'Pos (Value (Value'First + 11)) -
                 Character'Pos ('0')) +
           Character'Pos (Value (Value'First + 12)) - Character'Pos ('0');
         Second : constant Natural :=
           10 * (Character'Pos (Value (Value'First + 13)) -
                 Character'Pos ('0')) +
           Character'Pos (Value (Value'First + 14)) - Character'Pos ('0');
         Leap : constant Boolean :=
           Year mod 400 = 0
           or else (Year mod 4 = 0 and then Year mod 100 /= 0);
         Maximum_Day : constant Natural :=
           (case Month is
               when 2 => (if Leap then 29 else 28),
               when 4 | 6 | 9 | 11 => 30,
               when others => 31);
      begin
         return Year > 0
           and then Month in 1 .. 12
           and then Day in 1 .. Maximum_Day
           and then Hour <= 23
           and then Minute <= 59
           and then Second <= 59;
      end;
   end Valid_Timestamp;

   function Valid_Scope_Segment (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;
      for Item of Value loop
         if Item not in 'a' .. 'z'
           and then Item not in '0' .. '9'
           and then Item /= '-'
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Scope_Segment;

   function Valid_Access_Key (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;
      for Item of Value loop
         if Item not in 'A' .. 'Z'
           and then Item not in 'a' .. 'z'
           and then Item not in '0' .. '9'
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Access_Key;

   function Valid_Method (Value : String) return Boolean is
   begin
      if Value'Length = 0 then
         return False;
      end if;
      for Item of Value loop
         if Item not in 'A' .. 'Z' then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Method;

end Flyology.Object_Storage.S3.SigV4_Encoding;
