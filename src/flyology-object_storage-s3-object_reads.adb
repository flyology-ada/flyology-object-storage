with Ada.Calendar.Formatting;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Object_Reads is

   package US renames Ada.Strings.Unbounded;
   use type Ada.Calendar.Time;

   Maximum_Query_Length : constant := 8 * 1_024;

   function Decimal (Value : String) return Integer is
      Result : Integer := 0;
   begin
      if Value'Length = 0 then
         return -1;
      end if;
      for Item of Value loop
         if Item not in '0' .. '9' then
            return -1;
         end if;
         Result := Result * 10 + Character'Pos (Item) - Character'Pos ('0');
      end loop;
      return Result;
   end Decimal;

   function Month (Value : String) return Integer is
     (if Value = "Jan" then 1
      elsif Value = "Feb" then 2
      elsif Value = "Mar" then 3
      elsif Value = "Apr" then 4
      elsif Value = "May" then 5
      elsif Value = "Jun" then 6
      elsif Value = "Jul" then 7
      elsif Value = "Aug" then 8
      elsif Value = "Sep" then 9
      elsif Value = "Oct" then 10
      elsif Value = "Nov" then 11
      elsif Value = "Dec" then 12
      else 0);

   function Short_Weekday (Value : String) return Boolean is
     (Value in "Mon" | "Tue" | "Wed" | "Thu" | "Fri" | "Sat" | "Sun");

   function Long_Weekday (Value : String) return Boolean is
     (Value in "Monday" | "Tuesday" | "Wednesday" | "Thursday" |
       "Friday" | "Saturday" | "Sunday");

   function Date_Result
     (Year, Month_Value, Day, Hour, Minute, Second : Integer)
      return Conditional_Date_Result
   is
   begin
      declare
         Epoch : constant Ada.Calendar.Time :=
           Ada.Calendar.Formatting.Time_Of
             (1970, 1, 1, 0, 0, 0, Time_Zone => 0);
         Date : constant Ada.Calendar.Time :=
           Ada.Calendar.Formatting.Time_Of
             (Ada.Calendar.Year_Number (Year),
              Ada.Calendar.Month_Number (Month_Value),
              Ada.Calendar.Day_Number (Day), Hour, Minute, Second,
              Time_Zone => 0);
      begin
         return
           (Valid => True,
            Seconds_Since_Epoch => Long_Long_Integer (Date - Epoch));
      end;
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         return (Valid => False);
   end Date_Result;

   function Parse_Conditional_Date
     (Value : String;
      Now   : Ada.Calendar.Time := Ada.Calendar.Clock)
      return Conditional_Date_Result
   is
      Text : constant String (1 .. Value'Length) := Value;
   begin
      if Text'Length = 29
        and then Short_Weekday (Text (1 .. 3))
        and then Text (4 .. 5) = ", "
        and then Text (8) = ' '
        and then Text (12) = ' '
        and then Text (17) = ' '
        and then Text (20) = ':'
        and then Text (23) = ':'
        and then Text (26 .. 29) = " GMT"
      then
         return Date_Result
           (Decimal (Text (13 .. 16)), Month (Text (9 .. 11)),
            Decimal (Text (6 .. 7)), Decimal (Text (18 .. 19)),
            Decimal (Text (21 .. 22)), Decimal (Text (24 .. 25)));
      elsif Text'Length = 24
        and then Short_Weekday (Text (1 .. 3))
        and then Text (4) = ' '
        and then Text (8) = ' '
        and then Text (11) = ' '
        and then Text (14) = ':'
        and then Text (17) = ':'
        and then Text (20) = ' '
      then
         declare
            Day_Text : String (1 .. 2) := Text (9 .. 10);
         begin
            if Day_Text (1) = ' ' then
               Day_Text (1) := '0';
            end if;
            return Date_Result
              (Decimal (Text (21 .. 24)), Month (Text (5 .. 7)),
               Decimal (Day_Text), Decimal (Text (12 .. 13)),
               Decimal (Text (15 .. 16)), Decimal (Text (18 .. 19)));
         end;
      else
         declare
            Comma : constant Natural := Ada.Strings.Fixed.Index (Text, ",");
         begin
            if Comma = 0
              or else not Long_Weekday (Text (1 .. Comma - 1))
              or else Text'Last - Comma /= 23
            then
               return (Valid => False);
            end if;
            declare
               Rest : constant String (1 .. 23) :=
                 Text (Comma + 1 .. Text'Last);
               Short_Year : constant Integer := Decimal (Rest (9 .. 10));
               Current_Year : constant Integer :=
                 Integer (Ada.Calendar.Year (Now));
               Candidate : Integer :=
                 (Current_Year / 100) * 100 + Short_Year;
            begin
               if Rest (1) /= ' '
                 or else Rest (4) /= '-'
                 or else Rest (8) /= '-'
                 or else Rest (11) /= ' '
                 or else Rest (14) /= ':'
                 or else Rest (17) /= ':'
                 or else Rest (20 .. 23) /= " GMT"
                 or else Short_Year < 0
               then
                  return (Valid => False);
               end if;
               if Candidate - Current_Year > 50 then
                  Candidate := Candidate - 100;
               end if;
               return Date_Result
                 (Candidate, Month (Rest (5 .. 7)),
                  Decimal (Rest (2 .. 3)), Decimal (Rest (12 .. 13)),
                  Decimal (Rest (15 .. 16)), Decimal (Rest (18 .. 19)));
            end;
         end;
      end if;
   exception
      when Constraint_Error =>
         return (Valid => False);
   end Parse_Conditional_Date;

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 16);

   function Decode_Component (Value : String) return String is
      Result : String (1 .. Value'Length);
      Raw    : constant String (1 .. Value'Length) := Value;
      Input  : Natural := 1;
      Output : Natural := 0;
   begin
      while Input <= Raw'Length loop
         Output := Output + 1;
         if Raw (Input) = '%' then
            if Input + 2 > Raw'Length
              or else Hex_Value (Raw (Input + 1)) > 15
              or else Hex_Value (Raw (Input + 2)) > 15
            then
               raise Malformed_Object_Read_Request with
                 "invalid object-read percent escape";
            end if;
            Result (Output) := Character'Val
              (16 * Hex_Value (Raw (Input + 1)) +
               Hex_Value (Raw (Input + 2)));
            Input := Input + 3;
         else
            Result (Output) := Raw (Input);
            Input := Input + 1;
         end if;
      end loop;
      return Result (1 .. Output);
   end Decode_Component;

   function Valid_Override (Value : String) return Boolean is
   begin
      for Item of Value loop
         if Item in Character'Val (0) | Character'Val (10) |
           Character'Val (13)
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Override;

   function Parse_Query
     (Query : String; Operation : Read_Operation)
      return Object_Read_Request
   is
      Result : Object_Read_Request;
      Seen_Part, Seen_Version, Seen_Cache, Seen_Disposition, Seen_Encoding,
        Seen_Language, Seen_Type, Seen_Expires, Seen_X_ID : Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 then
         return Result;
      elsif Query'Length > Maximum_Query_Length then
         raise Malformed_Object_Read_Request with
           "invalid object-read query size";
      end if;
      for Item of Query loop
         if Item = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 9 then
         raise Malformed_Object_Read_Request with
           "too many object-read query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Object_Read_Request with
                    "empty object-read query parameter";
               end if;
               declare
                  Pair_Text : constant String := Raw (First .. Index - 1);
                  Equals : constant Natural :=
                    Ada.Strings.Fixed.Index (Pair_Text, "=");
                  Name : constant String := Decode_Component
                    ((if Equals = 0 then Pair_Text
                      elsif Equals = Pair_Text'First then ""
                      else Pair_Text (Pair_Text'First .. Equals - 1)));
                  Value : constant String := Decode_Component
                    ((if Equals = 0 or else Equals = Pair_Text'Last then ""
                      else Pair_Text (Equals + 1 .. Pair_Text'Last)));
                  Number : Wire_Core.Natural_Result;

                  procedure Mark_Override
                    (Seen : in out Boolean;
                     Target : in out US.Unbounded_String) is
                  begin
                     if Seen or else not Valid_Override (Value) then
                        raise Malformed_Object_Read_Request with
                          "invalid object-read response override";
                     end if;
                     Seen := True;
                     Result.Has_Response_Overrides := True;
                     Target := US.To_Unbounded_String (Value);
                  end Mark_Override;
               begin
                  if Name = "partNumber" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Part or else not Number.Valid
                       or else Number.Value not in S3.Core.Part_Number'Range
                     then
                        raise Malformed_Object_Read_Request with
                          "invalid object-read part number";
                     end if;
                     Seen_Part := True;
                     Result.Has_Part_Number := True;
                     Result.Part_Number := S3.Core.Part_Number (Number.Value);
                  elsif Name = "versionId" then
                     if Seen_Version or else Value'Length = 0
                       or else not Deletions.Valid_Version_ID (Value)
                     then
                        raise Malformed_Object_Read_Request with
                          "invalid object-read version ID";
                     end if;
                     Seen_Version := True;
                     Result.Has_Version_ID := True;
                     Result.Version_ID := US.To_Unbounded_String (Value);
                  elsif Name = "response-cache-control" then
                     Mark_Override
                       (Seen_Cache, Result.Response_Cache_Control);
                     Result.Has_Response_Cache_Control := True;
                  elsif Name = "response-content-disposition" then
                     Mark_Override
                       (Seen_Disposition,
                        Result.Response_Content_Disposition);
                     Result.Has_Response_Content_Disposition := True;
                  elsif Name = "response-content-encoding" then
                     Mark_Override
                       (Seen_Encoding, Result.Response_Content_Encoding);
                     Result.Has_Response_Content_Encoding := True;
                  elsif Name = "response-content-language" then
                     Mark_Override
                       (Seen_Language, Result.Response_Content_Language);
                     Result.Has_Response_Content_Language := True;
                  elsif Name = "response-content-type" then
                     Mark_Override
                       (Seen_Type, Result.Response_Content_Type);
                     Result.Has_Response_Content_Type := True;
                  elsif Name = "response-expires" then
                     Mark_Override (Seen_Expires, Result.Response_Expires);
                     Result.Has_Response_Expires := True;
                  elsif Name = "x-id" then
                     if Seen_X_ID
                       or else Value /=
                         (if Operation = Head_Object
                          then "HeadObject" else "GetObject")
                     then
                        raise Malformed_Object_Read_Request with
                          "invalid object-read operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_Object_Read_Request with
                       "unsupported object-read query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      return Result;
   end Parse_Query;

end Flyology.Object_Storage.S3.Object_Reads;
