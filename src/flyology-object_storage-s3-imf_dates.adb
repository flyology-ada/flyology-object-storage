package body Flyology.Object_Storage.S3.IMF_Dates
  with SPARK_Mode => On
is
   type Short_Name is new String (1 .. 3);
   Weekdays : constant array (Natural range 0 .. 6) of Short_Name :=
     ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun");
   Months : constant array (Positive range 1 .. 12) of Short_Name :=
     ("Jan", "Feb", "Mar", "Apr", "May", "Jun",
      "Jul", "Aug", "Sep", "Oct", "Nov", "Dec");
   Month_Start : constant array (Positive range 1 .. 12) of Natural :=
     (0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334);

   function Leap (Year : Positive) return Boolean is
     (Year mod 4 = 0 and then (Year mod 100 /= 0 or else Year mod 400 = 0));

   function Days_Before_Year (Year : Positive) return Natural is
      Previous : constant Natural := Year - 1;
   begin
      return
        365 * Previous + Previous / 4 - Previous / 100 + Previous / 400;
   end Days_Before_Year;

   Epoch_Day : constant Natural := Days_Before_Year (1970);

   function Days_In_Month (Year, Month : Positive) return Positive is
     (case Month is
        when 2 => (if Leap (Year) then 29 else 28),
        when 4 | 6 | 9 | 11 => 30,
        when others => 31)
   with Pre => Month <= 12;

   function Decimal (Text : String) return Integer is
      Result : Integer := 0;
   begin
      if Text'Length = 0 then
         return -1;
      end if;
      for Item of Text loop
         if Item not in '0' .. '9' then
            return -1;
         end if;
         Result := Result * 10 + Character'Pos (Item) - Character'Pos ('0');
      end loop;
      return Result;
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
            Year_Value : constant Positive := Positive (Year);
            Month_Value : constant Positive := Positive (Month);
         begin
            if Day > Days_In_Month (Year_Value, Month_Value) then
               return (Valid => False);
            end if;
            declare
               Absolute_Day : constant Natural :=
                 Days_Before_Year (Year_Value) + Month_Start (Month_Value) +
                 Boolean'Pos (Month_Value > 2 and then Leap (Year_Value)) +
                 Natural (Day - 1);
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
      Seconds : constant Natural :=
        Natural (Long_Long_Integer (Value) mod 86_400);
      Epoch_Delta : constant Long_Long_Integer :=
        (if Value >= 0
         then Long_Long_Integer (Value) / 86_400
         else (Long_Long_Integer (Value) - Long_Long_Integer (Seconds)) /
           86_400);
      Absolute_Day : constant Natural :=
        Natural (Epoch_Delta + Long_Long_Integer (Epoch_Day));
      Low  : Positive := 1;
      High : Positive := 10_000;
      Year : Positive;
      Day_Of_Year : Natural;
      Month : Positive := 1;
      Day   : Positive;
      Hour  : constant Natural := Seconds / 3_600;
      Minute : constant Natural := (Seconds mod 3_600) / 60;
      Second : constant Natural := Seconds mod 60;
      Result : String (1 .. 29) := "Mon, 01 Jan 0001 00:00:00 GMT";

      procedure Put_Two (Position : Positive; Number : Natural) is
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
         declare
            Middle : constant Positive := Low + (High - Low) / 2;
         begin
            if Days_Before_Year (Middle) <= Absolute_Day then
               Low := Middle;
            else
               High := Middle;
            end if;
         end;
      end loop;
      Year := Low;
      Day_Of_Year := Absolute_Day - Days_Before_Year (Year);
      while Month < 12
        and then Day_Of_Year >= Days_In_Month (Year, Month)
      loop
         pragma Loop_Invariant (Month in 1 .. 11);
         Day_Of_Year := Day_Of_Year - Days_In_Month (Year, Month);
         Month := Month + 1;
      end loop;
      Day := Positive (Day_Of_Year + 1);
      Result (1 .. 3) :=
        String (Weekdays (Natural ((Epoch_Delta mod 7 + 3) mod 7)));
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
