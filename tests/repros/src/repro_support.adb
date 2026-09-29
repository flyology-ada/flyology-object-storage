with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

package body Repro_Support is

   Failure_Count : Natural := 0;

   procedure Check (Condition : Boolean; Description : String) is
   begin
      if Condition then
         Ada.Text_IO.Put_Line ("  ok: " & Description);
      else
         Failure_Count := Failure_Count + 1;
         Ada.Text_IO.Put_Line ("  FAILED: " & Description);
      end if;
   end Check;

   procedure Note (Text : String) is
   begin
      Ada.Text_IO.Put_Line ("  -- " & Text);
   end Note;

   procedure Finish is
   begin
      if Failure_Count = 0 then
         Ada.Text_IO.Put_Line ("PASS");
         Ada.Command_Line.Set_Exit_Status (0);
      else
         Ada.Text_IO.Put_Line
           ("BUG REPRODUCED:" & Failure_Count'Image &
            " failed expectation(s)");
         Ada.Command_Line.Set_Exit_Status (1);
      end if;
   end Finish;

   function Failures return Natural is (Failure_Count);

   function Trim (Value : String) return String is
     (Ada.Strings.Fixed.Trim (Value, Ada.Strings.Both));

   function Image (Value : Integer) return String is
     (Trim (Integer'Image (Value)));

   function Image_64 (Value : Long_Long_Integer) return String is
     (Trim (Long_Long_Integer'Image (Value)));

   function Repeat (Item : Character; Count : Natural) return String is
      Result : constant String (1 .. Count) := [others => Item];
   begin
      return Result;
   end Repeat;

   function Contains (Haystack, Needle : String) return Boolean is
     (Needle'Length = 0
      or else Ada.Strings.Fixed.Index (Haystack, Needle) > 0);

   function Head_End (Response : String) return Natural is
     (Ada.Strings.Fixed.Index (Response, CRLF & CRLF));

   function Status_Code (Response : String) return Natural is
      Space : constant Natural := Ada.Strings.Fixed.Index (Response, " ");
   begin
      if Space = 0 or else Space + 3 > Response'Last then
         return 0;
      end if;
      declare
         Digits_Text : constant String := Response (Space + 1 .. Space + 3);
      begin
         for C of Digits_Text loop
            if C not in '0' .. '9' then
               return 0;
            end if;
         end loop;
         return Natural'Value (Digits_Text);
      end;
   end Status_Code;

   function Lower (Value : String) return String is
     (Ada.Characters.Handling.To_Lower (Value));

   procedure Each_Header
     (Response : String;
      Name     : String;
      Found    : in out Natural;
      Value    : in out Ada.Strings.Unbounded.Unbounded_String;
      First    : Boolean)
   is
      Stop   : constant Natural := Head_End (Response);
      Limit  : constant Natural :=
        (if Stop = 0 then Response'Last else Stop - 1);
      Cursor : Natural := Ada.Strings.Fixed.Index (Response, CRLF);
      Wanted : constant String := Lower (Name);
   begin
      if Cursor = 0 then
         return;
      end if;
      Cursor := Cursor + 2;
      while Cursor <= Limit loop
         declare
            Line_End : Natural :=
              Ada.Strings.Fixed.Index (Response, CRLF, From => Cursor);
         begin
            if Line_End = 0 or else Line_End > Limit + 1 then
               Line_End := Limit + 1;
            end if;
            declare
               Line  : constant String := Response (Cursor .. Line_End - 1);
               Colon : constant Natural := Ada.Strings.Fixed.Index (Line, ":");
            begin
               if Colon > 0
                 and then Lower (Trim (Line (Line'First .. Colon - 1)))
                          = Wanted
               then
                  Found := Found + 1;
                  if Found = 1 or else not First then
                     Value := Ada.Strings.Unbounded.To_Unbounded_String
                       (Trim (Line (Colon + 1 .. Line'Last)));
                  end if;
               end if;
            end;
            Cursor := Line_End + 2;
         end;
      end loop;
   end Each_Header;

   function Header_Value (Response : String; Name : String) return String is
      Found : Natural := 0;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Each_Header (Response, Name, Found, Value, First => True);
      return Ada.Strings.Unbounded.To_String (Value);
   end Header_Value;

   function Header_Count (Response : String; Name : String) return Natural is
      Found : Natural := 0;
      Value : Ada.Strings.Unbounded.Unbounded_String;
   begin
      Each_Header (Response, Name, Found, Value, First => True);
      return Found;
   end Header_Count;

   function Body_Of (Response : String) return String is
      Stop : constant Natural := Head_End (Response);
   begin
      if Stop = 0 then
         return "";
      end if;
      declare
         Raw : constant String := Response (Stop + 4 .. Response'Last);
      begin
         if Lower (Header_Value (Response, "Transfer-Encoding")) /= "chunked"
         then
            return Raw;
         end if;
         declare
            Result : Ada.Strings.Unbounded.Unbounded_String;
            Cursor : Natural := Raw'First;
         begin
            loop
               exit when Cursor > Raw'Last;
               declare
                  Line_End : constant Natural :=
                    Ada.Strings.Fixed.Index (Raw, CRLF, From => Cursor);
               begin
                  exit when Line_End = 0;
                  declare
                     Size_Text : constant String := Raw (Cursor .. Line_End - 1);
                     Semi      : constant Natural :=
                       Ada.Strings.Fixed.Index (Size_Text, ";");
                     Hex_Text  : constant String :=
                       Trim (Size_Text
                               (Size_Text'First ..
                                  (if Semi = 0 then Size_Text'Last
                                   else Semi - 1)));
                     Size : Natural := 0;
                  begin
                     for C of Hex_Text loop
                        Size := Size * 16 +
                          (case C is
                              when '0' .. '9' =>
                                Character'Pos (C) - Character'Pos ('0'),
                              when 'a' .. 'f' =>
                                Character'Pos (C) - Character'Pos ('a') + 10,
                              when 'A' .. 'F' =>
                                Character'Pos (C) - Character'Pos ('A') + 10,
                              when others => 0);
                     end loop;
                     exit when Size = 0;
                     Ada.Strings.Unbounded.Append
                       (Result, Raw (Line_End + 2 .. Line_End + 1 + Size));
                     Cursor := Line_End + 2 + Size + 2;
                  end;
               end;
            end loop;
            return Ada.Strings.Unbounded.To_String (Result);
         end;
      end;
   end Body_Of;

   function Escape (Value : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for C of Value loop
         case C is
            when ASCII.CR => Ada.Strings.Unbounded.Append (Result, "\r");
            when ASCII.LF => Ada.Strings.Unbounded.Append (Result, "\n");
            when ASCII.HT => Ada.Strings.Unbounded.Append (Result, "\t");
            when others =>
               if Character'Pos (C) < 32 or else Character'Pos (C) > 126 then
                  declare
                     Hex : constant String := "0123456789abcdef";
                  begin
                     Ada.Strings.Unbounded.Append
                       (Result,
                        "\x" & Hex (Character'Pos (C) / 16 + 1) &
                          Hex (Character'Pos (C) mod 16 + 1));
                  end;
               else
                  Ada.Strings.Unbounded.Append (Result, C);
               end if;
         end case;
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Escape;

end Repro_Support;
