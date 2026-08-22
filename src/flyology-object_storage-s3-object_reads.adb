with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Object_Reads is

   package US renames Ada.Strings.Unbounded;

   Maximum_Query_Length : constant := 8 * 1_024;

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

                  procedure Mark_Override (Seen : in out Boolean) is
                  begin
                     if Seen or else not Valid_Override (Value) then
                        raise Malformed_Object_Read_Request with
                          "invalid object-read response override";
                     end if;
                     Seen := True;
                     Result.Has_Response_Overrides := True;
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
                     Mark_Override (Seen_Cache);
                  elsif Name = "response-content-disposition" then
                     Mark_Override (Seen_Disposition);
                  elsif Name = "response-content-encoding" then
                     Mark_Override (Seen_Encoding);
                  elsif Name = "response-content-language" then
                     Mark_Override (Seen_Language);
                  elsif Name = "response-content-type" then
                     Mark_Override (Seen_Type);
                  elsif Name = "response-expires" then
                     Mark_Override (Seen_Expires);
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
