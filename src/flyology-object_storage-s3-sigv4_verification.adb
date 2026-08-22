with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.SigV4_Encoding;

package body Flyology.Object_Storage.S3.SigV4_Verification is

   package US renames Ada.Strings.Unbounded;
   package Encoding renames S3.SigV4_Encoding;

   function Access_Key (Item : Authorization_Data) return String is
     (US.To_String (Item.Access_Key_Value));

   function Scope_Date (Item : Authorization_Data) return String is
     (US.To_String (Item.Date_Value));

   function Region (Item : Authorization_Data) return String is
     (US.To_String (Item.Region_Value));

   function Service (Item : Authorization_Data) return String is
     (US.To_String (Item.Service_Value));

   function Signature (Item : Authorization_Data) return String is
     (US.To_String (Item.Signature_Value));

   function Signed_Header_Count
     (Item : Authorization_Data) return Natural is (Item.Header_Count);

   function Signed_Header_Name
     (Item : Authorization_Data; Index : Positive) return String is
     (Item.Headers (Index).Data (1 .. Item.Headers (Index).Length));

   function Header_Is_Signed
     (Item : Authorization_Data; Name : String) return Boolean
   is
      Lower : constant String := Encoding.Lowercase (Name);
   begin
      for Index in 1 .. Item.Header_Count loop
         if Signed_Header_Name (Item, Index) = Lower then
            return True;
         end if;
      end loop;
      return False;
   end Header_Is_Signed;

   function Decimal_Date (Value : String) return Boolean is
   begin
      if Value'Length /= 8 then
         return False;
      end if;
      for Item of Value loop
         if Item not in '0' .. '9' then
            return False;
         end if;
      end loop;
      return True;
   end Decimal_Date;

   function Parse (Value : String) return Parse_Result is
      Prefix : constant String := "AWS4-HMAC-SHA256";
      Result : Parse_Result := (Status => Parsed, others => <>);
      Credential_Seen : Boolean := False;
      Headers_Seen    : Boolean := False;
      Signature_Seen  : Boolean := False;

      procedure Fail (Status : Parse_Status) is
      begin
         Result := (Status => Status, others => <>);
      end Fail;

      procedure Parse_Credential (Text : String) is
         Parts : array (Positive range 1 .. 5) of US.Unbounded_String;
         Part  : Positive := 1;
         First : Positive := Text'First;
      begin
         if Text'Length = 0 or else Text'Length > 512 then
            Fail (Invalid_Credential_Scope);
            return;
         end if;
         for Index in Text'Range loop
            if Text (Index) = '/' then
               if Index = First or else Part = Parts'Last then
                  Fail (Invalid_Credential_Scope);
                  return;
               end if;
               Parts (Part) := US.To_Unbounded_String
                 (Text (First .. Index - 1));
               Part := Part + 1;
               First := Index + 1;
            end if;
         end loop;
         if Part /= Parts'Last or else First > Text'Last then
            Fail (Invalid_Credential_Scope);
            return;
         end if;
         Parts (Part) := US.To_Unbounded_String
           (Text (First .. Text'Last));
         if not Encoding.Valid_Access_Key (US.To_String (Parts (1)))
           or else not Decimal_Date (US.To_String (Parts (2)))
           or else not Encoding.Valid_Scope_Segment
             (US.To_String (Parts (3)))
           or else not Encoding.Valid_Scope_Segment
             (US.To_String (Parts (4)))
           or else US.To_String (Parts (5)) /= "aws4_request"
         then
            Fail (Invalid_Credential_Scope);
            return;
         end if;
         Result.Data.Access_Key_Value := Parts (1);
         Result.Data.Date_Value := Parts (2);
         Result.Data.Region_Value := Parts (3);
         Result.Data.Service_Value := Parts (4);
      end Parse_Credential;

      procedure Parse_Headers (Text : String) is
         First : Positive := Text'First;

         procedure Add (Name : String) is
            Lower : constant String := Encoding.Lowercase (Name);
         begin
            if Result.Status /= Parsed then
               return;
            elsif Name'Length = 0
              or else Name'Length > Maximum_Header_Name
              or else not Encoding.Valid_Header_Name (Name)
              or else Name /= Lower
              or else Name = "authorization"
              or else Result.Data.Header_Count = Maximum_Signed_Headers
              or else (Result.Data.Header_Count > 0
                       and then Signed_Header_Name
                         (Result.Data, Result.Data.Header_Count) >= Name)
            then
               Fail (Invalid_Signed_Headers);
               return;
            end if;
            Result.Data.Header_Count := Result.Data.Header_Count + 1;
            Result.Data.Headers (Result.Data.Header_Count).Length :=
              Name'Length;
            Result.Data.Headers (Result.Data.Header_Count).Data
              (1 .. Name'Length) := Name;
         end Add;
      begin
         if Text'Length = 0 or else Text'Length > 4_096 then
            Fail (Invalid_Signed_Headers);
            return;
         end if;
         for Index in Text'Range loop
            if Text (Index) = ';' then
               if Index = First then
                  Fail (Invalid_Signed_Headers);
                  return;
               end if;
               Add (Text (First .. Index - 1));
               First := Index + 1;
            end if;
         end loop;
         if First > Text'Last then
            Fail (Invalid_Signed_Headers);
         else
            Add (Text (First .. Text'Last));
         end if;
         if Result.Status = Parsed
           and then (not Header_Is_Signed (Result.Data, "host")
                     or else not Header_Is_Signed
                       (Result.Data, "x-amz-content-sha256")
                     or else not Header_Is_Signed
                       (Result.Data, "x-amz-date"))
         then
            Fail (Invalid_Signed_Headers);
         end if;
      end Parse_Headers;

      First : Positive;
   begin
      if Value'Length = 0 then
         return (Status => Missing_Authorization, others => <>);
      elsif Value'Length > 8_192
        or else Value'Length <= Prefix'Length
        or else Value (Value'First .. Value'First + Prefix'Length - 1) /=
          Prefix
        or else Value (Value'First + Prefix'Length) /= ' '
      then
         return (Status => Unsupported_Algorithm, others => <>);
      end if;
      First := Value'First + Prefix'Length + 1;
      for Index in First .. Value'Last + 1 loop
         if Index = Value'Last + 1 or else Value (Index) = ',' then
            declare
               Attribute : constant String := Ada.Strings.Fixed.Trim
                 (Value (First .. Index - 1), Ada.Strings.Both);
               Equals : constant Natural :=
                 Ada.Strings.Fixed.Index (Attribute, "=");
            begin
               if Equals = 0 or else Equals = Attribute'First
                 or else Equals = Attribute'Last
               then
                  Fail (Malformed_Authorization);
               elsif Attribute (Attribute'First .. Equals - 1) =
                 "Credential"
               then
                  if Credential_Seen then
                     Fail (Malformed_Authorization);
                  else
                     Credential_Seen := True;
                     Parse_Credential
                       (Attribute (Equals + 1 .. Attribute'Last));
                  end if;
               elsif Attribute (Attribute'First .. Equals - 1) =
                 "SignedHeaders"
               then
                  if Headers_Seen then
                     Fail (Malformed_Authorization);
                  else
                     Headers_Seen := True;
                     Parse_Headers
                       (Attribute (Equals + 1 .. Attribute'Last));
                  end if;
               elsif Attribute (Attribute'First .. Equals - 1) =
                 "Signature"
               then
                  if Signature_Seen then
                     Fail (Malformed_Authorization);
                  else
                     Signature_Seen := True;
                     declare
                        Signature_Text : constant String :=
                          Attribute (Equals + 1 .. Attribute'Last);
                     begin
                        if not Encoding.Valid_SHA256_Hex (Signature_Text) then
                           Fail (Invalid_Signature);
                        else
                           Result.Data.Signature_Value :=
                             US.To_Unbounded_String (Signature_Text);
                        end if;
                     end;
                  end if;
               else
                  Fail (Malformed_Authorization);
               end if;
            end;
            exit when Result.Status /= Parsed or else Index > Value'Last;
            First := Index + 1;
         end if;
      end loop;
      if Result.Status = Parsed
        and then not (Credential_Seen and Headers_Seen and Signature_Seen)
      then
         Fail (Malformed_Authorization);
      end if;
      return Result;
   exception
      when Constraint_Error =>
         return (Status => Malformed_Authorization, others => <>);
   end Parse;

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9'
      then Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'A' .. 'F'
      then Character'Pos (Value) - Character'Pos ('A') + 10
      else Character'Pos (Value) - Character'Pos ('a') + 10);

   function Decode_Query_Component
     (Value : String; Valid : out Boolean) return String
   is
      Result : String (1 .. Value'Length) := (others => Character'Val (0));
      Used   : Natural := 0;
      Index  : Natural := Value'First;
   begin
      Valid := True;
      while Index <= Value'Last loop
         if Value (Index) = '%' then
            if Index > Value'Last - 2
              or else not (Value (Index + 1) in '0' .. '9' | 'A' .. 'F' |
                                              'a' .. 'f')
              or else not (Value (Index + 2) in '0' .. '9' | 'A' .. 'F' |
                                              'a' .. 'f')
            then
               Valid := False;
               return "";
            end if;
            Used := Used + 1;
            Result (Used) := Character'Val
              (16 * Hex_Value (Value (Index + 1)) +
               Hex_Value (Value (Index + 2)));
            Index := Index + 3;
         else
            Used := Used + 1;
            Result (Used) := Value (Index);
            Index := Index + 1;
         end if;
      end loop;
      return Result (1 .. Used);
   end Decode_Query_Component;

   function Verify
     (Item         : Authorization_Data;
      Method       : String;
      Target       : String;
      Headers      : SigV4.Name_Value_Array;
      Payload_Hash : String;
      Secret_Key   : String) return Boolean
   is
      Question : constant Natural := Ada.Strings.Fixed.Index (Target, "?");
      Path : constant String :=
        (if Question = 0 then Target
         elsif Question = Target'First then ""
         else Target (Target'First .. Question - 1));
      Path_Valid : Boolean;
      Decoded_Path : constant String :=
        Decode_Query_Component (Path, Path_Valid);
      Query_Text : constant String :=
        (if Question = 0 or else Question = Target'Last then ""
         else Target (Question + 1 .. Target'Last));
      Query_Count : Natural := 0;
      Timestamp : US.Unbounded_String;
      Content_Hash : US.Unbounded_String;

      function Declared_Signed_Headers return String is
         Result : US.Unbounded_String;
      begin
         for Index in 1 .. Item.Header_Count loop
            if Index > 1 then
               US.Append (Result, ";");
            end if;
            US.Append (Result, Signed_Header_Name (Item, Index));
         end loop;
         return US.To_String (Result);
      end Declared_Signed_Headers;
   begin
      if Target'Length = 0 or else Target'Length > 8_192
        or else Path'Length = 0 or else Path (Path'First) /= '/'
        or else not Path_Valid
        or else Decoded_Path'Length = 0
        or else Secret_Key'Length = 0
        or else US.To_String (Item.Service_Value) /= "s3"
      then
         return False;
      end if;
      if Query_Text'Length > 0 then
         Query_Count := 1;
         for Character_Value of Query_Text loop
            if Character_Value = '&' then
               Query_Count := Query_Count + 1;
            end if;
         end loop;
      end if;
      if Query_Count > 128 then
         return False;
      end if;
      declare
         Query : SigV4.Name_Value_Array (1 .. Query_Count);
         Query_Last : Natural := 0;
         First : Positive :=
           (if Query_Text'Length = 0 then 1 else Query_Text'First);
      begin
         if Query_Text'Length > 0 then
            for Index in Query_Text'First .. Query_Text'Last + 1 loop
               if Index = Query_Text'Last + 1
                 or else Query_Text (Index) = '&'
               then
                  if Index = First then
                     return False;
                  end if;
                  declare
                     Pair_Text : constant String :=
                       Query_Text (First .. Index - 1);
                     Equals : constant Natural :=
                       Ada.Strings.Fixed.Index (Pair_Text, "=");
                     Name_Valid  : Boolean;
                     Value_Valid : Boolean;
                     Name : constant String := Decode_Query_Component
                       ((if Equals = 0 then Pair_Text
                         elsif Equals = Pair_Text'First then ""
                         else Pair_Text (Pair_Text'First .. Equals - 1)),
                        Name_Valid);
                     Value : constant String := Decode_Query_Component
                       ((if Equals = 0 or else Equals = Pair_Text'Last
                         then ""
                         else Pair_Text (Equals + 1 .. Pair_Text'Last)),
                        Value_Valid);
                  begin
                     if not Name_Valid or else not Value_Valid then
                        return False;
                     end if;
                     Query_Last := Query_Last + 1;
                     Query (Query_Last) := SigV4.Pair (Name, Value);
                  end;
                  First := Index + 1;
               end if;
            end loop;
         end if;
         declare
            Signing : SigV4.Signing_Result;
         begin
            for Header of Headers loop
               declare
                  Name : constant String :=
                    Encoding.Lowercase (US.To_String (Header.Name));
               begin
                  if Name = "x-amz-date" then
                     if US.Length (Timestamp) > 0 then
                        return False;
                     end if;
                     Timestamp := Header.Value;
                  elsif Name = "x-amz-content-sha256" then
                     if US.Length (Content_Hash) > 0 then
                        return False;
                     end if;
                     Content_Hash := Header.Value;
                  end if;
               end;
            end loop;
            if US.Length (Timestamp) /= 16
              or else US.To_String (Content_Hash) /= Payload_Hash
              or else US.To_String (Timestamp)
                (1 .. 8) /= US.To_String (Item.Date_Value)
            then
               return False;
            end if;
            Signing := SigV4.Sign
              (Method, Decoded_Path, Query, Headers, Payload_Hash,
               US.To_String (Item.Access_Key_Value), Secret_Key,
               US.To_String (Item.Region_Value), US.To_String (Timestamp),
               US.To_String (Item.Service_Value));
            return US.To_String (Signing.Signed_Headers) =
              Declared_Signed_Headers
              and then SigV4.Constant_Time_Equal
                (US.To_String (Signing.Signature),
                 US.To_String (Item.Signature_Value));
         end;
      end;
   exception
      when Constraint_Error | SigV4.Invalid_Signing_Input =>
         return False;
   end Verify;

end Flyology.Object_Storage.S3.SigV4_Verification;
