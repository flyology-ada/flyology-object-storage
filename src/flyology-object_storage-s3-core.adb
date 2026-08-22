package body Flyology.Object_Storage.S3.Core
  with SPARK_Mode => On
is

   function Is_Hexadecimal (Value : Character) return Boolean is
     (Value in '0' .. '9' | 'a' .. 'f' | 'A' .. 'F');

   function Valid_Listing_Continuation_Syntax
     (Token : String) return Boolean
   is
      Prefix_Length : constant := 5;
      Digest_Length : constant := 64;
      Header_Length : constant := Prefix_Length + Digest_Length + 1;
      Maximum_Length : constant :=
        Header_Length + 2 * Maximum_Listing_Cursor_Bytes;
      Length : constant Natural := Token'Length;
   begin
      if Length < Header_Length
        or else Length > Maximum_Length
        or else (Length - Header_Length) mod 2 /= 0
      then
         return False;
      end if;
      declare
         Raw : constant String (1 .. Length) := Token;
      begin
         if Raw (1 .. Prefix_Length) /= "fos1."
           or else Raw (Header_Length) /= '.'
         then
            return False;
         end if;
         for Index in Prefix_Length + 1 .. Prefix_Length + Digest_Length loop
            pragma Loop_Invariant
              (Index in Prefix_Length + 1 .. Prefix_Length + Digest_Length);
            pragma Loop_Variant (Increases => Index);
            if not Is_Hexadecimal (Raw (Index)) then
               return False;
            end if;
         end loop;
         if Length > Header_Length then
            for Index in Header_Length + 1 .. Length loop
               pragma Loop_Invariant
                 (Index in Header_Length + 1 .. Length);
               pragma Loop_Variant (Increases => Index);
               if not Is_Hexadecimal (Raw (Index)) then
                  return False;
               end if;
            end loop;
         end if;
         return True;
      end;
   end Valid_Listing_Continuation_Syntax;

   function Is_OWS (Value : Character) return Boolean is
     (Value = ' ' or else Value = Character'Val (9));

   function Equal_CI (Left, Right : Character) return Boolean is
     (Left = Right
      or else (Left in 'A' .. 'Z'
               and then Character'Val
                 (Character'Pos (Left) +
                    Character'Pos ('a') - Character'Pos ('A')) = Right));

   procedure Parse_Decimal
     (Value  : String;
      First  : Positive;
      Last   : Positive;
      Number : out Byte_Count;
      Valid  : out Boolean)
   is
      Accumulator : Byte_Count := 0;
      Digit       : Byte_Count;
   begin
      Number := 0;
      Valid := First <= Last
        and then First in Value'Range
        and then Last in Value'Range;
      if not Valid then
         return;
      end if;
      for Index in First .. Last loop
         if Value (Index) not in '0' .. '9' then
            Valid := False;
            return;
         end if;
         Digit := Character'Pos (Value (Index)) - Character'Pos ('0');
         if Accumulator > (Byte_Count'Last - Digit) / 10 then
            Valid := False;
            return;
         end if;
         Accumulator := Accumulator * 10 + Digit;
      end loop;
      Number := Accumulator;
   end Parse_Decimal;

   function Parse_Range_Header (Value : String) return Range_Parse_Result
   is
      Invalid : constant Range_Parse_Result :=
        (Status => Malformed_Range, Request => (others => <>));
      Cursor      : Positive;
      Last        : Positive;
      Hyphen      : Natural := 0;
      First_Value : Byte_Count;
      Last_Value  : Byte_Count;
      Valid       : Boolean;
   begin
      if Value'Length < 7 or else Value'Length > 256 then
         return Invalid;
      end if;
      if not Equal_CI (Value (Value'First), 'b')
        or else not Equal_CI (Value (Value'First + 1), 'y')
        or else not Equal_CI (Value (Value'First + 2), 't')
        or else not Equal_CI (Value (Value'First + 3), 'e')
        or else not Equal_CI (Value (Value'First + 4), 's')
        or else Value (Value'First + 5) /= '='
      then
         return Invalid;
      end if;

      Cursor := Value'First + 6;
      while Cursor < Value'Last and then Is_OWS (Value (Cursor)) loop
         Cursor := Cursor + 1;
         pragma Loop_Invariant (Cursor in Value'Range);
         pragma Loop_Variant (Increases => Cursor);
      end loop;
      Last := Value'Last;
      while Last > Cursor and then Is_OWS (Value (Last)) loop
         Last := Last - 1;
         pragma Loop_Invariant (Last in Cursor .. Value'Last);
         pragma Loop_Variant (Decreases => Last);
      end loop;
      if Is_OWS (Value (Cursor)) then
         return Invalid;
      end if;

      for Index in Cursor .. Last loop
         if Value (Index) = '-' then
            if Hyphen /= 0 then
               return Invalid;
            end if;
            Hyphen := Index;
         elsif Value (Index) not in '0' .. '9' then
            return Invalid;
         end if;
         pragma Loop_Invariant
           (Hyphen = 0 or else Hyphen in Cursor .. Last);
      end loop;
      if Hyphen = 0 then
         return Invalid;
      elsif Hyphen = Cursor then
         if Hyphen = Last then
            return Invalid;
         end if;
         Parse_Decimal
           (Value, Positive (Hyphen + 1), Last, Last_Value, Valid);
         if not Valid then
            return Invalid;
         end if;
         return
           (Status  => Range_Parsed,
            Request =>
              (Kind => Suffix, First => 0, Last => 0, Count => Last_Value));
      end if;

      Parse_Decimal
        (Value, Cursor, Positive (Hyphen - 1), First_Value, Valid);
      if not Valid then
         return Invalid;
      elsif Hyphen = Last then
         return
           (Status  => Range_Parsed,
            Request =>
              (Kind  => Open_Ended,
               First => First_Value,
               Last  => 0,
               Count => 0));
      end if;
      Parse_Decimal
        (Value, Positive (Hyphen + 1), Last, Last_Value, Valid);
      if not Valid then
         return Invalid;
      end if;
      return
        (Status  => Range_Parsed,
         Request =>
           (Kind  => Bounded,
            First => First_Value,
            Last  => Last_Value,
            Count => 0));
   end Parse_Range_Header;

   function Valid_Completion_Order
     (Parts : Part_Number_Array) return Boolean
   is
   begin
      if Parts'Length = 0 then
         return False;
      end if;
      if Parts'First < Parts'Last then
         for Index in Parts'First + 1 .. Parts'Last loop
            if Parts (Index - 1) >= Parts (Index) then
               return False;
            end if;
         end loop;
      end if;
      return True;
   end Valid_Completion_Order;

   function Valid_Consecutive_Completion_Order
     (Parts : Part_Number_Array) return Boolean
   is
   begin
      if Parts'Length = 0 or else Parts (Parts'First) /= 1 then
         return False;
      end if;
      if Parts'First < Parts'Last then
         for Index in Parts'First + 1 .. Parts'Last loop
            if Parts (Index - 1) = Part_Number'Last
              or else Parts (Index) /= Parts (Index - 1) + 1
            then
               return False;
            end if;
         end loop;
      end if;
      return True;
   end Valid_Consecutive_Completion_Order;

end Flyology.Object_Storage.S3.Core;
