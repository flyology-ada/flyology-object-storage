package body Flyology.Object_Storage.S3.Checksum_CRC
  with SPARK_Mode => On
is
   use type Interfaces.Unsigned_64;

   subtype U64 is Interfaces.Unsigned_64;
   type Lookup_Table is array (Natural range 0 .. 255) of U64;
   type GF2_Matrix is array (Natural range 0 .. 63) of U64;

   CRC32_Polynomial      : constant U64 := 16#EDB8_8320#;
   CRC32C_Polynomial     : constant U64 := 16#82F6_3B78#;
   CRC64NVME_Polynomial : constant U64 := 16#9A6C_9329_AC4B_C9B5#;

   function Polynomial (Kind : Algorithm) return U64 is
     (case Kind is
         when Core.CRC32 => CRC32_Polynomial,
         when Core.CRC32C => CRC32C_Polynomial,
         when Core.CRC64NVME => CRC64NVME_Polynomial);

   function Width_Mask (Kind : Algorithm) return U64 is
     (if Kind = Core.CRC64NVME then U64'Last else 16#FFFF_FFFF#);

   function Make_Table (Polynomial : U64) return Lookup_Table is
      Result : Lookup_Table;
      Value  : U64;
   begin
      for Index in Result'Range loop
         Value := U64 (Index);
         for Bit in 1 .. 8 loop
            Value :=
              (if (Value and 1) /= 0
               then Interfaces.Shift_Right (Value, 1) xor Polynomial
               else Interfaces.Shift_Right (Value, 1));
         end loop;
         Result (Index) := Value;
      end loop;
      return Result;
   end Make_Table;

   CRC32_Table      : constant Lookup_Table := Make_Table (CRC32_Polynomial);
   CRC32C_Table     : constant Lookup_Table := Make_Table (CRC32C_Polynomial);
   CRC64NVME_Table : constant Lookup_Table :=
     Make_Table (CRC64NVME_Polynomial);

   function Table_Value (Kind : Algorithm; Index : Natural) return U64 is
     (case Kind is
         when Core.CRC32 => CRC32_Table (Index),
         when Core.CRC32C => CRC32C_Table (Index),
         when Core.CRC64NVME => CRC64NVME_Table (Index))
   with Pre => Index <= 255;

   function Initial_Context (Kind : Algorithm) return Context is
     (Kind => Kind, State => Width_Mask (Kind));

   procedure Update
     (Item : in out Context; Data : Ada.Streams.Stream_Element_Array)
   is
      Index : Natural;
   begin
      for Value of Data loop
         Index := Natural ((Item.State xor U64 (Value)) and 16#FF#);
         Item.State := Interfaces.Shift_Right (Item.State, 8)
           xor Table_Value (Item.Kind, Index);
      end loop;
   end Update;

   function Finish (Item : Context) return U64 is
     (Item.State xor Width_Mask (Item.Kind));

   function Matrix_Times
     (Matrix : GF2_Matrix; Vector : U64; Width : Positive) return U64
   with Pre => Width in 32 | 64
   is
      Result : U64 := 0;
      Value  : U64 := Vector;
      Index  : Natural := 0;
   begin
      while Value /= 0 and then Index < Width loop
         pragma Loop_Variant (Increases => Index);
         if (Value and 1) /= 0 then
            Result := Result xor Matrix (Index);
         end if;
         Value := Interfaces.Shift_Right (Value, 1);
         Index := Index + 1;
      end loop;
      return Result;
   end Matrix_Times;

   function Matrix_Square
     (Matrix : GF2_Matrix; Width : Positive) return GF2_Matrix
   with Pre => Width in 32 | 64
   is
      Result : GF2_Matrix := (others => 0);
   begin
      for Index in 0 .. Width - 1 loop
         Result (Index) := Matrix_Times (Matrix, Matrix (Index), Width);
      end loop;
      return Result;
   end Matrix_Square;

   function Combine
     (Kind         : Algorithm;
      Left, Right  : U64;
      Right_Length : Byte_Count) return U64
   is
      Width : constant Positive :=
        (if Kind = Core.CRC64NVME then 64 else 32);
      Mask  : constant U64 := Width_Mask (Kind);
      Odd   : GF2_Matrix := (others => 0);
      Even  : GF2_Matrix;
      Row   : U64 := 1;
      Bytes : Byte_Count := Right_Length;
      Value : U64 := Left and Mask;
   begin
      if Right_Length = 0 then
         return (Left xor Right) and Mask;
      end if;

      Odd (0) := Polynomial (Kind);
      for Index in 1 .. Width - 1 loop
         Odd (Index) := Row;
         Row := Interfaces.Shift_Left (Row, 1);
      end loop;

      Even := Matrix_Square (Odd, Width);
      Odd := Matrix_Square (Even, Width);

      while Bytes /= 0 loop
         pragma Loop_Variant (Decreases => Bytes);
         Even := Matrix_Square (Odd, Width);
         if Bytes mod 2 /= 0 then
            Value := Matrix_Times (Even, Value, Width);
         end if;
         Bytes := Bytes / 2;
         exit when Bytes = 0;

         Odd := Matrix_Square (Even, Width);
         if Bytes mod 2 /= 0 then
            Value := Matrix_Times (Odd, Value, Width);
         end if;
         Bytes := Bytes / 2;
      end loop;
      return (Value xor Right) and Mask;
   end Combine;

end Flyology.Object_Storage.S3.Checksum_CRC;
