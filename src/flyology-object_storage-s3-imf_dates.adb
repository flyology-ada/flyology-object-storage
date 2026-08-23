package body Flyology.Object_Storage.S3.IMF_Dates
  with SPARK_Mode => On
is
   subtype Calendar_Year is Positive range 1 .. 10_000;
   subtype Rendered_Year is Calendar_Year range 1 .. 9_999;
   subtype Month_Number_Value is Positive range 1 .. 12;
   subtype Month_Length is Positive range 28 .. 31;
   subtype Year_Length is Positive range 365 .. 366;
   subtype Day_Boundary is Natural range 0 .. 3_652_059;
   subtype Absolute_Day_Number is Natural range 0 .. 3_652_058;
   subtype Seconds_Within_Day is Natural range 0 .. 86_399;
   subtype Two_Digit_Number is Natural range 0 .. 99;
   subtype Decimal_Value is Integer range -1 .. 9_999;

   type Short_Name is new String (1 .. 3);
   Weekdays : constant array (Natural range 0 .. 6) of Short_Name :=
     ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun");
   Months : constant array (Month_Number_Value) of Short_Name :=
     ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
   Month_Start : constant array (Month_Number_Value) of Natural :=
     (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);

   function Leap (Year : Calendar_Year) return Boolean is
     (Year mod 4 = 0 and then (Year mod 100 /= 0 or else Year mod 400 = 0));

   function Days_Before_Year (Year : Calendar_Year) return Day_Boundary is
     (declare
         Previous : constant Natural := Year - 1;
      begin
         365 * Previous + Previous / 4 - Previous / 100 + Previous / 400);

   function Days_In_Year (Year : Rendered_Year) return Year_Length is
     (if Leap (Year) then 366 else 365);

   procedure Prove_Quotient_Step
     (Value : Positive; Divisor : Positive)
   with
     Ghost,
     Pre => Value <= 9_999 and then Divisor <= 400,
     Post =>
       Value / Divisor =
         (Value - 1) / Divisor + Boolean'Pos (Value mod Divisor = 0)
   is
      Quotient  : constant Natural := Value / Divisor;
      Remainder : constant Natural := Value mod Divisor;
   begin
      pragma Assert (Value = Quotient * Divisor + Remainder);
      if Remainder = 0 then
         pragma Assert (Quotient > 0);
         pragma Assert
           (Value - 1 = (Quotient - 1) * Divisor + (Divisor - 1));
      else
         pragma Assert
           (Value - 1 = Quotient * Divisor + (Remainder - 1));
      end if;
   end Prove_Quotient_Step;

   procedure Prove_Adjacent_Year (Year : Rendered_Year)
   with
     Ghost,
     Post =>
       Days_Before_Year (Calendar_Year (Year + 1)) =
         Days_Before_Year (Year) + Days_In_Year (Year)
   is
   begin
      Prove_Quotient_Step (Year, 4);
      Prove_Quotient_Step (Year, 100);
      Prove_Quotient_Step (Year, 400);
      if Year mod 400 = 0 then
         pragma Assert (Leap (Year));
      elsif Year mod 100 = 0 then
         pragma Assert (not Leap (Year));
      elsif Year mod 4 = 0 then
         pragma Assert (Leap (Year));
      else
         pragma Assert (not Leap (Year));
      end if;
   end Prove_Adjacent_Year;

   Epoch_Day : constant Day_Boundary := Days_Before_Year (1970);

   function Days_In_Month
     (Year : Rendered_Year; Month : Month_Number_Value) return Month_Length is
     (case Month is
        when 2 => (if Leap (Year) then 29 else 28),
        when 4 | 6 | 9 | 11 => 30,
        when others => 31);

   function Decimal (Text : String) return Decimal_Value
   with Pre => Text'Length in 1 .. 4
   is
      Result : Natural range 0 .. 9_999 := 0;
   begin
      for Item of Text loop
         pragma Loop_Invariant (Result in 0 .. 9_999);
         if Item not in '0' .. '9' then
            return -1;
         elsif Result > 999 then
            return -1;
         end if;
         Result := Result * 10 + Character'Pos (Item) - Character'Pos ('0');
      end loop;
      return Decimal_Value (Result);
   end Decimal;

   function Month_Number (Text : String) return Natural is
   begin
      for Index in Months'Range loop
         if Text = String (Months (Index)) then
            return Index;
         end if;
      end loop;
      return 0;
   end Month_Number;

   function Parse (Text : String) return Metadata_Time_Result is
      Raw : constant String (1 .. Text'Length) := Text;
   begin
      if Raw'Length /= 29
        or else Raw (4 .. 5) /= ", "
        or else Raw (8) /= ' '
        or else Raw (12) /= ' '
        or else Raw (17) /= ' '
        or else Raw (20) /= ':'
        or else Raw (23) /= ':'
        or else Raw (26 .. 29) /= " GMT"
      then
         return (Valid => False);
      end if;
      declare
         Year   : constant Integer := Decimal (Raw (13 .. 16));
         Month  : constant Natural := Month_Number (Raw (9 .. 11));
         Day    : constant Integer := Decimal (Raw (6 .. 7));
         Hour   : constant Integer := Decimal (Raw (18 .. 19));
         Minute : constant Integer := Decimal (Raw (21 .. 22));
         Second : constant Integer := Decimal (Raw (24 .. 25));
      begin
         if Year not in 1 .. 9_999
           or else Month not in 1 .. 12
           or else Day not in 1 .. 31
           or else Hour not in 0 .. 23
           or else Minute not in 0 .. 59
           or else Second not in 0 .. 60
         then
            return (Valid => False);
         end if;
         declare
            Year_Value : constant Rendered_Year := Rendered_Year (Year);
            Month_Value : constant Month_Number_Value :=
              Month_Number_Value (Month);
         begin
            if Day > Days_In_Month (Year_Value, Month_Value) then
               return (Valid => False);
            end if;
            declare
               Absolute_Day : constant Absolute_Day_Number :=
                 Absolute_Day_Number
                   (Days_Before_Year (Year_Value) +
                    Month_Start (Month_Value) +
                    Boolean'Pos
                      (Month_Value > 2 and then Leap (Year_Value)) +
                    Natural (Day - 1));
               Epoch_Delta : constant Long_Long_Integer :=
                 Long_Long_Integer (Absolute_Day) -
                 Long_Long_Integer (Epoch_Day);
               Value : constant Long_Long_Integer :=
                 Epoch_Delta * 86_400 + Long_Long_Integer (Hour) * 3_600 +
                 Long_Long_Integer (Minute) * 60 + Long_Long_Integer (Second);
               Weekday : constant Natural :=
                 Natural ((Epoch_Delta mod 7 + 3) mod 7);
            begin
               if Raw (1 .. 3) /= String (Weekdays (Weekday))
                 or else Value not in
                   Long_Long_Integer (Metadata_Time'First) ..
                     Long_Long_Integer (Metadata_Time'Last)
               then
                  return (Valid => False);
               end if;
               return (Valid => True, Value => Metadata_Time (Value));
            end;
         end;
      end;
   end Parse;

   function Image (Value : Metadata_Time) return String is
      Maximum_Elapsed : constant Long_Long_Integer :=
        Long_Long_Integer (Metadata_Time'Last) -
        Long_Long_Integer (Metadata_Time'First);
      subtype Elapsed_Seconds is
        Long_Long_Integer range 0 .. Maximum_Elapsed;
      Elapsed : constant Elapsed_Seconds :=
        Long_Long_Integer (Value) -
        Long_Long_Integer (Metadata_Time'First);
      Seconds : constant Seconds_Within_Day :=
        Seconds_Within_Day (Elapsed mod 86_400);
      Absolute_Day : constant Absolute_Day_Number :=
        Absolute_Day_Number (Elapsed / 86_400);
      Low  : Calendar_Year := 1;
      High : Calendar_Year := 10_000;
      Year : Rendered_Year;
      Day_Of_Year : Natural;
      Month : Month_Number_Value := 1;
      Day   : Two_Digit_Number;
      Hour  : constant Natural := Seconds / 3_600;
      Minute : constant Natural := (Seconds mod 3_600) / 60;
      Second : constant Natural := Seconds mod 60;
      Result : String (1 .. 29) := "Mon, 01 Jan 0001 00:00:00 GMT";

      procedure Put_Two
        (Position : Positive; Number : Two_Digit_Number)
      with Pre => Position < Result'Last
      is
      begin
         Result (Position) :=
           Character'Val (Character'Pos ('0') + Number / 10);
         Result (Position + 1) :=
           Character'Val (Character'Pos ('0') + Number mod 10);
      end Put_Two;
   begin
      while Low + 1 < High loop
         pragma Loop_Invariant (Low in 1 .. 9_999);
         pragma Loop_Invariant (High in 2 .. 10_000);
         pragma Loop_Invariant (Low < High);
         pragma Loop_Invariant
           (Days_Before_Year (Low) <= Absolute_Day);
         pragma Loop_Invariant
           (Absolute_Day < Days_Before_Year (High));
         pragma Loop_Variant (Decreases => High - Low);
         declare
            Middle : constant Calendar_Year := Low + (High - Low) / 2;
         begin
            if Days_Before_Year (Middle) <= Absolute_Day then
               Low := Middle;
            else
               High := Middle;
            end if;
         end;
      end loop;
      pragma Assert (High = Low + 1);
      Year := Rendered_Year (Low);
      Prove_Adjacent_Year (Year);
      pragma Assert
        (Days_Before_Year (High) =
           Days_Before_Year (Year) + Days_In_Year (Year));
      Day_Of_Year := Absolute_Day - Days_Before_Year (Year);
      pragma Assert (Day_Of_Year < Days_In_Year (Year));
      while Month < 12
        and then Day_Of_Year >= Days_In_Month (Year, Month)
      loop
         pragma Loop_Invariant (Month in 1 .. 11);
         pragma Loop_Invariant
           (Day_Of_Year <= 365 - 28 * (Natural (Month) - 1));
         pragma Loop_Variant (Decreases => 12 - Month);
         Day_Of_Year := Day_Of_Year - Days_In_Month (Year, Month);
         Month := Month + 1;
      end loop;
      Day := Two_Digit_Number (Day_Of_Year + 1);
      Result (1 .. 3) :=
        String (Weekdays (Absolute_Day mod 7));
      Put_Two (6, Day);
      Result (9 .. 11) := String (Months (Month));
      Result (13) := Character'Val (Character'Pos ('0') + Year / 1_000);
      Result (14) :=
        Character'Val (Character'Pos ('0') + (Year / 100) mod 10);
      Result (15) :=
        Character'Val (Character'Pos ('0') + (Year / 10) mod 10);
      Result (16) := Character'Val (Character'Pos ('0') + Year mod 10);
      Put_Two (18, Hour);
      Put_Two (21, Minute);
      Put_Two (24, Second);
      return Result;
   end Image;
end Flyology.Object_Storage.S3.IMF_Dates;
