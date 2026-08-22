with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Interfaces;
with Flyology.Object_Storage;
with Flyology.Object_Storage.S3.Checksum_CRC;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;

procedure S3_Checksum_Corpus is
   package Storage renames Flyology.Object_Storage;
   package CRC renames Storage.S3.Checksum_CRC;
   package Policy renames Storage.S3.Checksum_Policy;
   package Checksums renames Storage.S3.Checksums;

   use type Ada.Streams.Stream_Element_Offset;
   use type Interfaces.Unsigned_64;
   use type Policy.Algorithm;
   use type Policy.Checksum_Type;

   subtype SEO is Ada.Streams.Stream_Element_Offset;
   subtype Bytes is Ada.Streams.Stream_Element_Array;
   subtype U64 is Interfaces.Unsigned_64;

   Vector_Count : Natural := 0;

   procedure Require (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Require;

   function Payload (Length : Natural) return Bytes is
      Result : Bytes (1 .. SEO (Length));
   begin
      for Index in 0 .. Length - 1 loop
         Result (SEO (Index + 1)) := Ada.Streams.Stream_Element
           ((Index * 131 + Length * 17 + Index / 7) mod 256);
      end loop;
      return Result;
   end Payload;

   function From_String (Value : String) return Bytes is
      Result : Bytes (1 .. SEO (Value'Length));
   begin
      for Index in Value'Range loop
         Result (SEO (Index - Value'First + 1)) :=
           Ada.Streams.Stream_Element (Character'Pos (Value (Index)));
      end loop;
      return Result;
   end From_String;

   function To_U64 (Value : Checksums.Digest_Value) return U64 is
      Raw    : constant Bytes := Checksums.Raw_Bytes (Value);
      Result : U64 := 0;
   begin
      for Byte of Raw loop
         Result := Interfaces.Shift_Left (Result, 8) or U64 (Byte);
      end loop;
      return Result;
   end To_U64;

   function Chunked
     (Kind : Policy.Algorithm; Data : Bytes; Chunk_Size : Positive)
      return Checksums.Digest_Value
   is
      Item     : Checksums.Context (Kind);
      Position : SEO := Data'First;
      Last     : SEO;
   begin
      if Data'Length = 0 then
         Checksums.Update (Item, Data);
      end if;
      while Position <= Data'Last loop
         Last := SEO'Min
           (Data'Last, Position + SEO (Chunk_Size) - 1);
         Checksums.Update (Item, Data (Position .. Last));
         Position := Last + 1;
      end loop;
      return Checksums.Finish (Item);
   end Chunked;

   procedure Check_Known
     (Kind : Policy.Algorithm; Data, Expected : String; Label : String)
   is
      Value : constant Checksums.Digest_Value :=
        Checksums.Compute (Kind, From_String (Data));
   begin
      Require
        (Checksums.Encode_Base64 (Value) = Expected,
         Label & " known vector mismatch");
   end Check_Known;

   procedure Check_Official_And_Upstream_Vectors is
   begin
      Check_Known (Policy.Core.CRC32, "123456789", "y/Q5Jg==", "CRC32");
      Check_Known (Policy.Core.CRC32C, "123456789", "4waSgw==", "CRC32C");
      Check_Known
        (Policy.Core.CRC64NVME, "123456789", "rosUhgp5mIg=", "CRC64NVME");
      Check_Known
        (Policy.Core.SHA1, "abc", "qZk+NkcGgWq6PiVxeFDCbJzQ2J0=", "SHA1");
      Check_Known
        (Policy.Core.SHA256, "abc",
         "ungWv48Bz+pBQUDeXa4iI7ADYaOWF3qctBD/YfIAFa0=", "SHA256");
      Check_Known
        (Policy.Core.SHA512, "abc",
         "3a81oZNherrMQXNJriBBMRLm+k6JqX6iCp7u5ktV05ohkpkqJ0/" &
         "BqDa6PCOj/uu9RU1EI2Q86A4qmslPpUyknw==", "SHA512");
      Check_Known
        (Policy.Core.MD5, "abc", "kAFQmDzST7DWlj99KOF/cg==", "MD5");
      Check_Known
        (Policy.Core.XXHASH64, "123456789", "jLhB20DmroM=", "XXHASH64");
      Check_Known
        (Policy.Core.XXHASH3, "123456789", "ctyxi2ehff8=", "XXHASH3");
      Check_Known
        (Policy.Core.XXHASH128, "123456789",
         "MxGUd+3l3NXpcWQnaB1YYA==", "XXHASH128");
   end Check_Official_And_Upstream_Vectors;

   procedure Check_Vector
     (Length : Natural; Kind : Policy.Algorithm; Expected : String)
   is
      Data    : constant Bytes := Payload (Length);
      Value   : constant Checksums.Digest_Value :=
        Checksums.Compute (Kind, Data);
      Decoded : constant Checksums.Decode_Result :=
        Checksums.Decode_Base64 (Expected, Kind);
      Chunk_Sizes : constant array (Positive range <>) of Positive :=
        (1, 2, 3, 7, 8, 15, 16, 17, 31, 63, 64, 65, 127, 128, 129,
         239, 240, 241, 255, 1_024, 4_096);
   begin
      Require
        (Checksums.Encode_Base64 (Value) = Expected,
         Policy.Wire_Name (Kind) & " differential vector mismatch at" &
         Natural'Image (Length));
      Require
        (Decoded.Valid
         and then Checksums.Equivalent (Decoded.Value, Value),
         Policy.Wire_Name (Kind) & " Base64 round trip failed");

      if Length = 65_535 then
         for Size of Chunk_Sizes loop
            Require
              (Checksums.Equivalent (Chunked (Kind, Data, Size), Value),
               Policy.Wire_Name (Kind) & " chunk boundary" &
               Positive'Image (Size));
         end loop;
      end if;
      Vector_Count := Vector_Count + 1;
   end Check_Vector;

   procedure Load_Differential_Corpus is
      File   : Ada.Text_IO.File_Type;
      Buffer : String (1 .. 256);
      Last   : Natural;
      First_Tab, Second_Tab : Natural;
      Parsed : Policy.Algorithm_Parse_Result;
   begin
      Ada.Text_IO.Open
        (File, Ada.Text_IO.In_File, "corpora/s3-checksums.tsv");
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Buffer, Last);
         if Last > 0 and then Buffer (1) /= '#' then
            declare
               Line : constant String := Buffer (1 .. Last);
               Tab  : constant String := (1 => ASCII.HT);
            begin
               First_Tab := Ada.Strings.Fixed.Index (Line, Tab);
               Second_Tab := Ada.Strings.Fixed.Index
                 (Line, Tab, From => First_Tab + 1);
               Require
                 (First_Tab > 1 and then Second_Tab > First_Tab + 1,
                  "malformed checksum corpus row");
               Parsed := Policy.Parse_Algorithm
                 (Line (First_Tab + 1 .. Second_Tab - 1));
               Require (Parsed.Valid, "unknown checksum corpus algorithm");
               Check_Vector
                 (Natural'Value (Line (Line'First .. First_Tab - 1)),
                  Parsed.Value, Line (Second_Tab + 1 .. Line'Last));
            end;
         end if;
      end loop;
      Ada.Text_IO.Close (File);
      Require (Vector_Count = 320, "differential corpus is incomplete");
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         raise;
   end Load_Differential_Corpus;

   procedure Check_Strict_Base64 is
      Data : constant Bytes := From_String ("base64 validation");
   begin
      for Kind in Policy.Algorithm loop
         declare
            Good : constant String := Checksums.Encode_Base64
              (Checksums.Compute (Kind, Data));
            Bad_Alphabet : String := Good;
            Bad_Padding  : String := Good;
            Noncanonical : String := Good;
         begin
            Bad_Alphabet (Bad_Alphabet'First) := '-';
            Bad_Padding (Bad_Padding'Last) := 'A';
            if Policy.Digest_Length (Kind) mod 3 = 1 then
               Noncanonical (Noncanonical'Last - 2) := 'B';
            else
               Noncanonical (Noncanonical'Last - 1) := 'B';
            end if;
            Require
              (not Checksums.Decode_Base64
                 (Good (Good'First .. Good'Last - 1), Kind).Valid,
               Policy.Wire_Name (Kind) & " accepted truncated Base64");
            Require
              (not Checksums.Decode_Base64 (Good & "=", Kind).Valid,
               Policy.Wire_Name (Kind) & " accepted extra padding");
            Require
              (not Checksums.Decode_Base64 (Bad_Alphabet, Kind).Valid,
               Policy.Wire_Name (Kind) & " accepted URL-safe Base64");
            Require
              (not Checksums.Decode_Base64 (Bad_Padding, Kind).Valid,
               Policy.Wire_Name (Kind) & " accepted missing padding");
            Require
              (not Checksums.Decode_Base64 (Noncanonical, Kind).Valid,
               Policy.Wire_Name (Kind) & " accepted noncanonical pad bits");
            Require
              (not Checksums.Decode_Base64 (' ' & Good, Kind).Valid,
               Policy.Wire_Name (Kind) & " accepted whitespace");
         end;
      end loop;
   end Check_Strict_Base64;

   procedure Check_AWS_Composite is
      First : constant Checksums.Decode_Result := Checksums.Decode_Base64
        ("QLl8R4i4+SaJlrl8ZIcutc5TbZtwt2NwB8lTXkd3GH0=", Policy.Core.SHA256);
      Second : constant Checksums.Decode_Result := Checksums.Decode_Base64
        ("xCdgs1K5Bm4jWETYw/CmGYr+m6O2DcGfpckx5NVokvE=", Policy.Core.SHA256);
      Third : constant Checksums.Decode_Result := Checksums.Decode_Base64
        ("f5wsfsa5bB+yXuwzqG1Bst91uYneqGD3CCidpb54mAo=", Policy.Core.SHA256);
   begin
      Require (First.Valid and then Second.Valid and then Third.Valid,
               "AWS tutorial part vectors did not decode");
      declare
         Parts : constant Checksums.Digest_Array :=
           (First.Value, Second.Value, Third.Value);
         Value : constant Checksums.Digest_Value :=
           Checksums.Composite (Policy.Core.SHA256, Parts);
         Object_Value : constant String :=
           Checksums.Encode_Object (Value, Policy.Composite, 3);
      begin
         Require
           (Checksums.Encode_Base64 (Value) =
              "aI8EoktCdotjU8Bq46DrPCxQCGuGcPIhJ51noWs6hvk=",
            "AWS tutorial checksum-of-checksums mismatch");
         Require
           (Object_Value = "aI8EoktCdotjU8Bq46DrPCxQCGuGcPIhJ51noWs6hvk=-3",
            "AWS tutorial composite suffix mismatch");
         Require
           (Checksums.Decode_Object
              (Object_Value, Policy.Core.SHA256, Policy.Composite, 3).Valid,
            "AWS tutorial object checksum rejected");
         Require
           (not Checksums.Decode_Object
              (Object_Value, Policy.Core.SHA256, Policy.Composite, 2).Valid,
            "wrong composite part count accepted");
      end;
   end Check_AWS_Composite;

   procedure Check_Full_Object (Kind : CRC.Algorithm) is
      Data  : constant Bytes := Payload (8_193);
      Parts : Checksums.Part_Checksum_Array (1 .. 3);
      Whole : constant Checksums.Digest_Value :=
        Checksums.Compute (Kind, Data);
   begin
      Parts (1) :=
        (Value => Checksums.Compute (Kind, Data (1 .. 1)), Length => 1);
      Parts (2) :=
        (Value => Checksums.Compute (Kind, Data (2 .. 4_097)),
         Length => 4_096);
      Parts (3) :=
        (Value => Checksums.Compute (Kind, Data (4_098 .. 8_193)),
         Length => 4_096);
      Require
        (Checksums.Equivalent (Checksums.Full_Object (Kind, Parts), Whole),
         Policy.Wire_Name (Kind) & " CRC linearization mismatch");
   end Check_Full_Object;

   procedure Check_Large_Logical
     (Kind : CRC.Algorithm; Expected : U64)
   is
      Block    : constant Bytes := Payload (65_536);
      Combined : U64 := To_U64 (Checksums.Compute (Kind, Block));
      Length   : Storage.Byte_Count := 65_536;
   begin
      for Power in 1 .. 20 loop
         Combined := CRC.Combine (Kind, Combined, Combined, Length);
         Length := Length * 2;
      end loop;
      Require (Length = 64 * Policy.Core.GiB,
               "logical checksum length did not reach 64 GiB");
      Require (Combined = Expected,
               Policy.Wire_Name (Kind) & " 64 GiB logical vector mismatch");
   end Check_Large_Logical;

   procedure Check_Policy is
   begin
      for Kind in Policy.Algorithm loop
         Require
           (Policy.Parse_Algorithm (Policy.Wire_Name (Kind)).Valid,
            "algorithm wire name did not parse");
         Require
           (Policy.Supported (Kind, Policy.Composite) =
              (Kind /= Policy.Core.CRC64NVME),
            "composite support matrix mismatch");
         Require
           (Policy.Supported (Kind, Policy.Full_Object) =
              (Kind in Policy.Core.CRC32 .. Policy.Core.CRC64NVME),
            "full-object support matrix mismatch");
      end loop;
      Require (not Policy.Parse_Algorithm ("sha256").Valid,
               "algorithm parser accepted wrong case");
      Require (not Policy.Parse_Type ("FULL-OBJECT").Valid,
               "checksum type parser accepted wrong spelling");
      Require
        (Policy.Default_Type (Policy.Core.CRC64NVME) = Policy.Full_Object,
         "CRC64NVME default type mismatch");
      Require
        (Policy.Default_Type (Policy.Core.SHA256) = Policy.Composite,
         "SHA256 default type mismatch");
   end Check_Policy;

begin
   Check_Policy;
   Check_Official_And_Upstream_Vectors;
   Load_Differential_Corpus;
   Check_Strict_Base64;
   Check_AWS_Composite;
   Check_Full_Object (Policy.Core.CRC32);
   Check_Full_Object (Policy.Core.CRC32C);
   Check_Full_Object (Policy.Core.CRC64NVME);
   Check_Large_Logical (Policy.Core.CRC32, 16#2D97_ADFF#);
   Check_Large_Logical (Policy.Core.CRC32C, 16#B9FA_C0D5#);
   Check_Large_Logical (Policy.Core.CRC64NVME, 16#967F_0A6A_103B_6221#);
   Ada.Text_IO.Put_Line
     ("S3 checksum corpus: 320 oracle vectors, 210 chunk boundaries, " &
      "strict wire, composite, and 64 GiB CRC linearization OK");
end S3_Checksum_Corpus;
