with Ada.Streams;
with GNAT.SHA256;
with Interfaces;
with Flyology.Object_Storage.Secrets;
with Flyology.Object_Storage.S3.SigV4_Encoding;

package body Flyology.Object_Storage.S3.SigV4 is

   package US renames Ada.Strings.Unbounded;
   package Encoding renames
     Flyology.Object_Storage.S3.SigV4_Encoding;
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_32;

   LF : constant Character := Character'Val (10);

   function Pair (Name, Value : String) return Name_Value is
     (Name  => US.To_Unbounded_String (Name),
      Value => US.To_Unbounded_String (Value));

   function SHA256_Hex (Value : String) return String is
      Result : constant GNAT.SHA256.Message_Digest :=
        GNAT.SHA256.Digest (Value);
   begin
      return String (Result);
   end SHA256_Hex;

   function Binary_String
     (Value : GNAT.SHA256.Binary_Message_Digest) return String
   is
      Result : String (1 .. Natural (Value'Length));
   begin
      for Index in Result'Range loop
         Result (Index) := Character'Val
           (Value
              (Value'First +
               Ada.Streams.Stream_Element_Offset (Index - Result'First)));
      end loop;
      return Result;
   end Binary_String;

   function HMAC (Key, Value : String) return String is
      Context : GNAT.SHA256.Context := GNAT.SHA256.HMAC_Initial_Context (Key);
      Result  : String (1 .. Natural (GNAT.SHA256.Hash_Length));
   begin
      GNAT.SHA256.Update (Context, Value);
      Result := Binary_String (GNAT.SHA256.Digest (Context));
      Flyology.Object_Storage.Secrets.Wipe
        (Context'Address, (Context'Size + System.Storage_Unit - 1) /
         System.Storage_Unit);
      return Result;
   exception
      when others =>
         Flyology.Object_Storage.Secrets.Wipe
           (Context'Address, (Context'Size + System.Storage_Unit - 1) /
            System.Storage_Unit);
         raise;
   end HMAC;

   function HMAC_Hex (Key, Value : String) return String is
      Context : GNAT.SHA256.Context := GNAT.SHA256.HMAC_Initial_Context (Key);
      Result  : GNAT.SHA256.Message_Digest;
   begin
      GNAT.SHA256.Update (Context, Value);
      Result := GNAT.SHA256.Digest (Context);
      Flyology.Object_Storage.Secrets.Wipe
        (Context'Address, (Context'Size + System.Storage_Unit - 1) /
         System.Storage_Unit);
      return String (Result);
   exception
      when others =>
         Flyology.Object_Storage.Secrets.Wipe
           (Context'Address, (Context'Size + System.Storage_Unit - 1) /
            System.Storage_Unit);
         raise;
   end HMAC_Hex;

   function Less (Left, Right : Name_Value) return Boolean is
      Left_Name  : constant String := US.To_String (Left.Name);
      Right_Name : constant String := US.To_String (Right.Name);
   begin
      return Left_Name < Right_Name
        or else (Left_Name = Right_Name and then
                 US.To_String (Left.Value) < US.To_String (Right.Value));
   end Less;

   procedure Sort (Items : in out Name_Value_Array) is
   begin
      if Items'Length > 1 then
         for Index in Items'First + 1 .. Items'Last loop
            declare
               Value : constant Name_Value := Items (Index);
               Place : Positive := Index;
            begin
               while Place > Items'First
                 and then Less (Value, Items (Place - 1))
               loop
                  Items (Place) := Items (Place - 1);
                  Place := Place - 1;
               end loop;
               Items (Place) := Value;
            end;
         end loop;
      end if;
   end Sort;

   procedure Stable_Sort_By_Name (Items : in out Name_Value_Array) is
   begin
      if Items'Length > 1 then
         for Index in Items'First + 1 .. Items'Last loop
            declare
               Value : constant Name_Value := Items (Index);
               Place : Positive := Index;
            begin
               while Place > Items'First
                 and then US.To_String (Value.Name) <
                   US.To_String (Items (Place - 1).Name)
               loop
                  Items (Place) := Items (Place - 1);
                  Place := Place - 1;
               end loop;
               Items (Place) := Value;
            end;
         end loop;
      end if;
   end Stable_Sort_By_Name;

   function Canonical_Query (Query : Name_Value_Array) return String is
      Encoded : Name_Value_Array (Query'Range);
      Result  : US.Unbounded_String;
   begin
      for Item of Query loop
         if US.Length (Item.Name) > Natural'Last / 3
           or else US.Length (Item.Value) > Natural'Last / 3
         then
            raise Invalid_Signing_Input with "SigV4 query item is too large";
         end if;
      end loop;
      for Index in Query'Range loop
         Encoded (Index) := Pair
           (Encoding.URI_Encode (US.To_String (Query (Index).Name), True),
            Encoding.URI_Encode (US.To_String (Query (Index).Value), True));
      end loop;
      Sort (Encoded);
      for Index in Encoded'Range loop
         if Index /= Encoded'First then
            US.Append (Result, "&");
         end if;
         US.Append (Result, US.To_String (Encoded (Index).Name));
         US.Append (Result, "=");
         US.Append (Result, US.To_String (Encoded (Index).Value));
      end loop;
      return US.To_String (Result);
   end Canonical_Query;

   function Contains_Unsafe_Value (Value : String) return Boolean is
   begin
      for Item of Value loop
         if Character'Pos (Item) < 32 and then Item /= Character'Val (9) then
            return True;
         elsif Item = Character'Val (127) then
            return True;
         end if;
      end loop;
      return False;
   end Contains_Unsafe_Value;

   procedure Canonical_Headers
     (Headers   : Name_Value_Array;
      Canonical : out US.Unbounded_String;
      Signed    : out US.Unbounded_String)
   is
      Values   : Name_Value_Array (Headers'Range);
      Host_Count : Natural := 0;
   begin
      Canonical := US.Null_Unbounded_String;
      Signed := US.Null_Unbounded_String;
      for Index in Headers'Range loop
         declare
            Name  : constant String := US.To_String (Headers (Index).Name);
            Value : constant String := US.To_String (Headers (Index).Value);
         begin
            if not Encoding.Valid_Header_Name (Name)
              or else Contains_Unsafe_Value (Value)
            then
               raise Invalid_Signing_Input with "invalid canonical header";
            end if;
            Values (Index) := Pair
              (Encoding.Lowercase (Name),
               Encoding.Normalize_Header_Value (Value));
         end;
      end loop;
      Stable_Sort_By_Name (Values);
      for Index in Values'Range loop
         declare
            Name : constant String := US.To_String (Values (Index).Name);
         begin
            if Name = "host" then
               Host_Count := Host_Count + 1;
            end if;
            if Index /= Values'First
              and then US.To_String (Values (Index).Name) =
                US.To_String (Values (Index - 1).Name)
            then
               US.Append (Canonical, ",");
               US.Append (Canonical, US.To_String (Values (Index).Value));
            else
               if Index /= Values'First then
                  US.Append (Canonical, String'(1 => LF));
               end if;
               US.Append (Canonical, Name & ":");
               US.Append (Canonical, US.To_String (Values (Index).Value));
               if US.Length (Signed) > 0 then
                  US.Append (Signed, ";");
               end if;
               US.Append (Signed, Name);
            end if;
         end;
      end loop;
      if Host_Count /= 1 then
         raise Invalid_Signing_Input with
           "exactly one host header is required";
      end if;
      US.Append (Canonical, String'(1 => LF));
   end Canonical_Headers;

   function Sign
     (Method             : String;
      Path               : String;
      Query              : Name_Value_Array;
      Headers            : Name_Value_Array;
      Payload_Hash       : String;
      Access_Key         : String;
      Secret_Key         : String;
      Region             : String;
      Timestamp          : String;
      Service            : String := "s3") return Signing_Result
   is
      Canonical_Header_Text : US.Unbounded_String;
      Signed_Header_Text    : US.Unbounded_String;
      Canonical             : US.Unbounded_String;
      To_Sign               : US.Unbounded_String;
      Signature             : US.Unbounded_String;
      Authorization         : US.Unbounded_String;
   begin
      if not Encoding.Valid_Method (Method)
        or else Path'Length = 0
        or else Path (Path'First) /= '/'
        or else Path'Length > Natural'Last / 3
        or else not Encoding.Valid_Access_Key (Access_Key)
        or else Secret_Key'Length = 0
        or else not Encoding.Valid_Scope_Segment (Region)
        or else not Encoding.Valid_Scope_Segment (Service)
        or else not Encoding.Valid_Timestamp (Timestamp)
        or else (Payload_Hash /= Unsigned_Payload and then
                 not Encoding.Valid_SHA256_Hex (Payload_Hash))
      then
         raise Invalid_Signing_Input with "invalid SigV4 input";
      end if;
      for Item of Query loop
         if US.Length (Item.Name) > Natural'Last / 3
           or else US.Length (Item.Value) > Natural'Last / 3
         then
            raise Invalid_Signing_Input with "SigV4 query item is too large";
         end if;
      end loop;
      Canonical_Headers
        (Headers, Canonical_Header_Text, Signed_Header_Text);
      Canonical := US.To_Unbounded_String
        (Method & LF & Encoding.URI_Encode (Path, False) & LF &
         Canonical_Query (Query) & LF &
         US.To_String (Canonical_Header_Text) & LF &
         US.To_String (Signed_Header_Text) & LF & Payload_Hash);
      declare
         Date  : constant String :=
           Timestamp (Timestamp'First .. Timestamp'First + 7);
         Scope : constant String :=
           Date & "/" & Region & "/" & Service & "/aws4_request";
         Prefixed_Key : String (1 .. Secret_Key'Length + 4);
         Date_Key     : String (1 .. Natural (GNAT.SHA256.Hash_Length));
         Region_Key   : String (Date_Key'Range);
         Service_Key  : String (Date_Key'Range);
         Signing_Key  : String (Date_Key'Range);
      begin
         Prefixed_Key (1 .. 4) := "AWS4";
         Prefixed_Key (5 .. Prefixed_Key'Last) := Secret_Key;
         Date_Key := HMAC (Prefixed_Key, Date);
         Region_Key := HMAC (Date_Key, Region);
         Service_Key := HMAC (Region_Key, Service);
         Signing_Key := HMAC (Service_Key, "aws4_request");
         To_Sign := US.To_Unbounded_String
           ("AWS4-HMAC-SHA256" & LF & Timestamp & LF & Scope & LF &
            SHA256_Hex (US.To_String (Canonical)));
         Signature := US.To_Unbounded_String
           (HMAC_Hex (Signing_Key, US.To_String (To_Sign)));
         Authorization := US.To_Unbounded_String
           ("AWS4-HMAC-SHA256 Credential=" & Access_Key & "/" & Scope &
            ",SignedHeaders=" & US.To_String (Signed_Header_Text) &
            ",Signature=" & US.To_String (Signature));
         Flyology.Object_Storage.Secrets.Wipe (Prefixed_Key);
         Flyology.Object_Storage.Secrets.Wipe (Date_Key);
         Flyology.Object_Storage.Secrets.Wipe (Region_Key);
         Flyology.Object_Storage.Secrets.Wipe (Service_Key);
         Flyology.Object_Storage.Secrets.Wipe (Signing_Key);
      exception
         when others =>
            Flyology.Object_Storage.Secrets.Wipe (Prefixed_Key);
            Flyology.Object_Storage.Secrets.Wipe (Date_Key);
            Flyology.Object_Storage.Secrets.Wipe (Region_Key);
            Flyology.Object_Storage.Secrets.Wipe (Service_Key);
            Flyology.Object_Storage.Secrets.Wipe (Signing_Key);
            raise;
      end;
      return
        (Canonical_Request => Canonical,
         String_To_Sign    => To_Sign,
         Signed_Headers    => Signed_Header_Text,
         Signature         => Signature,
         Authorization     => Authorization);
   end Sign;

   function Constant_Time_Equal (Left, Right : String) return Boolean is
      Difference : Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Left'Length) xor
        Interfaces.Unsigned_32 (Right'Length);
      Maximum : constant Natural := Natural'Max (Left'Length, Right'Length);
   begin
      if Maximum > 0 then
         for Offset in 0 .. Maximum - 1 loop
            Difference := Difference or
              (Interfaces.Unsigned_32
                (Character'Pos
                   (if Offset < Left'Length
                    then Left (Left'First + Offset) else '0'))
              xor Interfaces.Unsigned_32
                (Character'Pos
                   (if Offset < Right'Length
                    then Right (Right'First + Offset) else '0')));
         end loop;
      end if;
      return Difference = 0;
   end Constant_Time_Equal;

end Flyology.Object_Storage.S3.SigV4;
