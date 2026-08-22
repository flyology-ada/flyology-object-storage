with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Wire_Core;
with Interfaces.C;
with System;

package body Flyology.Object_Storage.S3.Checksums is
   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.C.int;
   use type Interfaces.C.size_t;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_64;
   use type Policy.Checksum_Type;

   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   subtype U8 is Interfaces.Unsigned_8;
   subtype U64 is Interfaces.Unsigned_64;

   function XXH_State_Size return Interfaces.C.size_t
   with Import, Convention => C,
     External_Name => "flyology_object_storage_xxhash_state_size";

   function XXH_State_Alignment return Interfaces.C.size_t
   with Import, Convention => C,
     External_Name => "flyology_object_storage_xxhash_state_alignment";

   function XXH_Reset
     (Storage      : System.Address;
      Storage_Size : Interfaces.C.size_t;
      Kind         : Interfaces.C.int) return Interfaces.C.int
   with Import, Convention => C,
     External_Name => "flyology_object_storage_xxhash_reset";

   function XXH_Update
     (Storage : System.Address;
      Data    : System.Address;
      Length  : Interfaces.C.size_t) return Interfaces.C.int
   with Import, Convention => C,
     External_Name => "flyology_object_storage_xxhash_update";

   function XXH_Digest
     (Storage    : System.Address;
      Output     : System.Address;
      Output_Size : Interfaces.C.size_t) return Interfaces.C.int
   with Import, Convention => C,
     External_Name => "flyology_object_storage_xxhash_digest";

   function XXH_Kind (Kind : Algorithm) return Interfaces.C.int is
     (case Kind is
         when Policy.Core.XXHASH64 => 0,
         when Policy.Core.XXHASH3 => 1,
         when Policy.Core.XXHASH128 => 2,
         when others => raise Program_Error);

   function Kind (Value : Digest_Value) return Algorithm is
     (Value.Algorithm_Value);

   function Length (Value : Digest_Value) return Positive is
     (Policy.Digest_Length (Value.Algorithm_Value));

   function Raw_Bytes
     (Value : Digest_Value) return Ada.Streams.Stream_Element_Array
   is
      Result : Ada.Streams.Stream_Element_Array
        (1 .. Ada.Streams.Stream_Element_Offset (Length (Value)));
   begin
      for Index in Result'Range loop
         Result (Index) := Value.Bytes (Positive (Index));
      end loop;
      return Result;
   end Raw_Bytes;

   function Equivalent (Left, Right : Digest_Value) return Boolean is
      Difference : U8 := 0;
   begin
      if Left.Algorithm_Value /= Right.Algorithm_Value then
         return False;
      end if;
      for Index in 1 .. Length (Left) loop
         Difference := Difference or
           (U8 (Left.Bytes (Index)) xor U8 (Right.Bytes (Index)));
      end loop;
      return Difference = 0;
   end Equivalent;

   Base64_Alphabet : constant String :=
     "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

   function Base64_Value (Value : Character) return Natural is
     (if Value in 'A' .. 'Z' then Character'Pos (Value) - Character'Pos ('A')
      elsif Value in 'a' .. 'z' then
        Character'Pos (Value) - Character'Pos ('a') + 26
      elsif Value in '0' .. '9' then
        Character'Pos (Value) - Character'Pos ('0') + 52
      elsif Value = '+' then 62
      else 63);

   function Encode_Base64 (Value : Digest_Value) return String is
      Input  : constant Ada.Streams.Stream_Element_Array := Raw_Bytes (Value);
      Result : String (1 .. 4 * ((Input'Length + 2) / 3));
      Source : Ada.Streams.Stream_Element_Offset := Input'First;
      Target : Positive := Result'First;
      First, Second, Third : Natural;
      Remaining : Natural;
   begin
      while Source <= Input'Last loop
         Remaining := Natural (Input'Last - Source + 1);
         First := Natural (Input (Source));
         Second :=
           (if Remaining >= 2 then Natural (Input (Source + 1)) else 0);
         Third :=
           (if Remaining >= 3 then Natural (Input (Source + 2)) else 0);
         Result (Target) := Base64_Alphabet (1 + First / 4);
         Result (Target + 1) := Base64_Alphabet
           (1 + (First mod 4) * 16 + Second / 16);
         Result (Target + 2) :=
           (if Remaining >= 2
            then Base64_Alphabet (1 + (Second mod 16) * 4 + Third / 64)
            else '=');
         Result (Target + 3) :=
           (if Remaining >= 3
            then Base64_Alphabet (1 + Third mod 64)
            else '=');
         Source := Source + Ada.Streams.Stream_Element_Offset
           (Natural'Min (3, Remaining));
         Target := Target + 4;
      end loop;
      return Result;
   end Encode_Base64;

   function Decode_Base64
     (Text : String; Expected : Algorithm) return Decode_Result
   is
      Expected_Length : constant Positive := Policy.Digest_Length (Expected);
      Result          : Digest_Value :=
        (Algorithm_Value => Expected, Bytes => (others => 0));
      Source : Positive := Text'First;
      Target : Positive := 1;
      First, Second, Third, Fourth : Natural;
   begin
      if not Wire_Core.Valid_Base64 (Text, Expected_Length) then
         return (Valid => False);
      end if;

      while Source <= Text'Last loop
         First := Base64_Value (Text (Source));
         Second := Base64_Value (Text (Source + 1));
         Third :=
           (if Text (Source + 2) = '='
            then 0 else Base64_Value (Text (Source + 2)));
         Fourth :=
           (if Text (Source + 3) = '='
            then 0 else Base64_Value (Text (Source + 3)));
         Result.Bytes (Target) := Ada.Streams.Stream_Element
           (First * 4 + Second / 16);
         if Target < Expected_Length then
            Target := Target + 1;
            Result.Bytes (Target) := Ada.Streams.Stream_Element
              ((Second mod 16) * 16 + Third / 4);
         end if;
         if Target < Expected_Length then
            Target := Target + 1;
            Result.Bytes (Target) := Ada.Streams.Stream_Element
              ((Third mod 4) * 64 + Fourth);
         end if;
         Source := Source + 4;
         if Target < Expected_Length then
            Target := Target + 1;
         end if;
      end loop;
      return (Valid => True, Value => Result);
   end Decode_Base64;

   function Decimal (Value : Positive) return String is
     (Ada.Strings.Fixed.Trim (Positive'Image (Value), Ada.Strings.Both));

   function Encode_Object
     (Value      : Digest_Value;
      Kind       : Checksum_Type;
      Part_Count : Positive) return String
   is
      Encoded : constant String := Encode_Base64 (Value);
   begin
      if Kind = Policy.Composite then
         return Encoded & '-' & Decimal (Part_Count);
      else
         return Encoded;
      end if;
   end Encode_Object;

   function Decode_Object
     (Text       : String;
      Expected   : Algorithm;
      Kind       : Checksum_Type;
      Part_Count : Positive) return Decode_Result
   is
      Encoded_Length : constant Positive :=
        4 * ((Policy.Digest_Length (Expected) + 2) / 3);
      Suffix : constant String := '-' & Decimal (Part_Count);
   begin
      if Kind = Policy.Full_Object then
         return Decode_Base64 (Text, Expected);
      elsif Text'Length /= Encoded_Length + Suffix'Length
        or else Text (Text'Last - Suffix'Length + 1 .. Text'Last) /= Suffix
      then
         return (Valid => False);
      else
         return Decode_Base64
           (Text (Text'First .. Text'First + Encoded_Length - 1), Expected);
      end if;
   end Decode_Object;

   overriding procedure Initialize (Item : in out Context) is
   begin
      Reset (Item);
   end Initialize;

   procedure Reset (Item : in out Context) is
      Success : Interfaces.C.int;
   begin
      case Item.Kind is
         when Policy.Core.CRC32 .. Policy.Core.CRC64NVME =>
            case Item.Kind is
               when Policy.Core.CRC32 =>
                  Item.CRC32_State := CRC.Initial_Context (Policy.Core.CRC32);
               when Policy.Core.CRC32C =>
                  Item.CRC32C_State :=
                    CRC.Initial_Context (Policy.Core.CRC32C);
               when Policy.Core.CRC64NVME =>
                  Item.CRC64NVME_State :=
                    CRC.Initial_Context (Policy.Core.CRC64NVME);
               when others =>
                  null;
            end case;
         when Policy.Core.MD5 =>
            Item.MD5_State := GNAT.MD5.Initial_Context;
         when Policy.Core.SHA1 =>
            Item.SHA1_State := GNAT.SHA1.Initial_Context;
         when Policy.Core.SHA256 =>
            Item.SHA256_State := GNAT.SHA256.Initial_Context;
         when Policy.Core.SHA512 =>
            Item.SHA512_State := GNAT.SHA512.Initial_Context;
         when Policy.Core.XXHASH64 .. Policy.Core.XXHASH128 =>
            if XXH_State_Size > Interfaces.C.size_t (XXH_Storage_Bytes)
              or else XXH_State_Alignment > 64
            then
               raise Program_Error with
                 "vendored xxHash state exceeds Ada storage";
            end if;
            Success := XXH_Reset
              (Item.XXH_State'Address,
               Interfaces.C.size_t (XXH_Storage_Bytes),
               XXH_Kind (Item.Kind));
            if Success = 0 then
               raise Program_Error with "xxHash context reset failed";
            end if;
      end case;
   end Reset;

   procedure Update
     (Item : in out Context; Data : Ada.Streams.Stream_Element_Array)
   is
      Success : Interfaces.C.int;
      Address : constant System.Address :=
        (if Data'Length = 0
         then System.Null_Address
         else Data (Data'First)'Address);
   begin
      case Item.Kind is
         when Policy.Core.CRC32 .. Policy.Core.CRC64NVME =>
            case Item.Kind is
               when Policy.Core.CRC32 =>
                  CRC.Update (Item.CRC32_State, Data);
               when Policy.Core.CRC32C =>
                  CRC.Update (Item.CRC32C_State, Data);
               when Policy.Core.CRC64NVME =>
                  CRC.Update (Item.CRC64NVME_State, Data);
               when others =>
                  null;
            end case;
         when Policy.Core.MD5 =>
            GNAT.MD5.Update (Item.MD5_State, Data);
         when Policy.Core.SHA1 =>
            GNAT.SHA1.Update (Item.SHA1_State, Data);
         when Policy.Core.SHA256 =>
            GNAT.SHA256.Update (Item.SHA256_State, Data);
         when Policy.Core.SHA512 =>
            GNAT.SHA512.Update (Item.SHA512_State, Data);
         when Policy.Core.XXHASH64 .. Policy.Core.XXHASH128 =>
            Success := XXH_Update
              (Item.XXH_State'Address, Address,
               Interfaces.C.size_t (Data'Length));
            if Success = 0 then
               raise Program_Error with "xxHash context update failed";
            end if;
      end case;
   end Update;

   function From_CRC (Kind : Algorithm; Value : U64) return Digest_Value is
      Result : Digest_Value :=
        (Algorithm_Value => Kind, Bytes => (others => 0));
      Remaining : U64 := Value;
   begin
      for Index in reverse 1 .. Policy.Digest_Length (Kind) loop
         Result.Bytes (Index) := Ada.Streams.Stream_Element
           (Remaining and 16#FF#);
         Remaining := Interfaces.Shift_Right (Remaining, 8);
      end loop;
      return Result;
   end From_CRC;

   function Finish (Item : Context) return Digest_Value is
      Result : Digest_Value :=
        (Algorithm_Value => Item.Kind, Bytes => (others => 0));

      procedure Copy (Data : Ada.Streams.Stream_Element_Array) is
      begin
         for Index in Data'Range loop
            Result.Bytes (Positive (Index - Data'First + 1)) := Data (Index);
         end loop;
      end Copy;

      Success : Interfaces.C.int;
   begin
      case Item.Kind is
         when Policy.Core.CRC32 .. Policy.Core.CRC64NVME =>
            case Item.Kind is
               when Policy.Core.CRC32 =>
                  return From_CRC
                    (Item.Kind, CRC.Finish (Item.CRC32_State));
               when Policy.Core.CRC32C =>
                  return From_CRC
                    (Item.Kind, CRC.Finish (Item.CRC32C_State));
               when Policy.Core.CRC64NVME =>
                  return From_CRC
                    (Item.Kind, CRC.Finish (Item.CRC64NVME_State));
               when others =>
                  raise Program_Error;
            end case;
         when Policy.Core.MD5 =>
            Copy (GNAT.MD5.Digest (Item.MD5_State));
         when Policy.Core.SHA1 =>
            Copy (GNAT.SHA1.Digest (Item.SHA1_State));
         when Policy.Core.SHA256 =>
            Copy (GNAT.SHA256.Digest (Item.SHA256_State));
         when Policy.Core.SHA512 =>
            Copy (GNAT.SHA512.Digest (Item.SHA512_State));
         when Policy.Core.XXHASH64 .. Policy.Core.XXHASH128 =>
            Success := XXH_Digest
              (Item.XXH_State'Address, Result.Bytes'Address,
               Interfaces.C.size_t (Maximum_Digest_Length));
            if Success = 0 then
               raise Program_Error with "xxHash context digest failed";
            end if;
      end case;
      return Result;
   end Finish;

   function Compute
     (Kind : Algorithm; Data : Ada.Streams.Stream_Element_Array)
      return Digest_Value
   is
      Item : Context (Kind);
   begin
      Update (Item, Data);
      return Finish (Item);
   end Compute;

   function Composite
     (Kind : Algorithm; Parts : Digest_Array) return Digest_Value
   is
      Item : Context (Kind);
   begin
      for Part of Parts loop
         declare
            Raw : constant Ada.Streams.Stream_Element_Array :=
              Raw_Bytes (Part);
         begin
            Update (Item, Raw);
         end;
      end loop;
      return Finish (Item);
   end Composite;

   function To_CRC (Value : Digest_Value) return U64 is
      Result : U64 := 0;
   begin
      for Index in 1 .. Length (Value) loop
         Result := Interfaces.Shift_Left (Result, 8)
           or U64 (Value.Bytes (Index));
      end loop;
      return Result;
   end To_CRC;

   function Full_Object
     (Kind : Algorithm; Parts : Part_Checksum_Array) return Digest_Value
   is
      Result : U64 := To_CRC (Parts (Parts'First).Value);
   begin
      if Parts'First < Parts'Last then
         for Index in Parts'First + 1 .. Parts'Last loop
            Result := CRC.Combine
              (Kind, Result, To_CRC (Parts (Index).Value),
               Parts (Index).Length);
         end loop;
      end if;
      return From_CRC (Kind, Result);
   end Full_Object;

end Flyology.Object_Storage.S3.Checksums;
