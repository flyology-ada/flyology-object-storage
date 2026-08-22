with Ada.Finalization;
with Ada.Streams;
with GNAT.MD5;
with GNAT.SHA1;
with GNAT.SHA256;
with GNAT.SHA512;
with Interfaces;
with Flyology.Object_Storage.S3.Checksum_CRC;
with Flyology.Object_Storage.S3.Checksum_Policy;

--  Streaming S3 checksums with strict canonical Base64 wire encoding.
package Flyology.Object_Storage.S3.Checksums is
   package Policy renames Flyology.Object_Storage.S3.Checksum_Policy;
   package CRC renames Flyology.Object_Storage.S3.Checksum_CRC;
   use type Policy.Core.Checksum_Algorithm;

   subtype Algorithm is Policy.Algorithm;
   subtype Checksum_Type is Policy.Checksum_Type;

   Maximum_Digest_Length : constant := 64;

   type Digest_Value is private;

   --  Return the algorithm represented by a digest value.
   function Kind (Value : Digest_Value) return Algorithm;

   --  Return the exact fixed binary length for the digest algorithm.
   function Length (Value : Digest_Value) return Positive;

   --  Return the canonical big-endian digest bytes.
   function Raw_Bytes
     (Value : Digest_Value) return Ada.Streams.Stream_Element_Array;

   --  Compare fixed-size digest bytes without data-dependent early exit.
   function Equivalent (Left, Right : Digest_Value) return Boolean;

   --  Encode a raw part or full-object checksum as canonical padded Base64.
   function Encode_Base64 (Value : Digest_Value) return String;

   type Decode_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Digest_Value;
         when False =>
            null;
      end case;
   end record;

   --  Decode one canonical padded Base64 digest of the expected algorithm.
   function Decode_Base64
     (Text : String; Expected : Algorithm) return Decode_Result;

   --  Encode an object checksum, including S3's -part-count composite suffix.
   function Encode_Object
     (Value      : Digest_Value;
      Kind       : Checksum_Type;
      Part_Count : Positive) return String;

   --  Decode an object checksum and require the exact composite part count.
   function Decode_Object
     (Text       : String;
      Expected   : Algorithm;
      Kind       : Checksum_Type;
      Part_Count : Positive) return Decode_Result;

   type Context (Kind : Algorithm) is
     new Ada.Finalization.Limited_Controlled with private;

   --  Reset a context to its algorithm's standard unseeded initial state.
   procedure Reset (Item : in out Context);

   --  Add the next byte sequence. Input is consumed before the call returns.
   procedure Update
     (Item : in out Context; Data : Ada.Streams.Stream_Element_Array);

   --  Return the digest without invalidating the streaming context.
   function Finish (Item : Context) return Digest_Value;

   --  Hash one byte sequence without allocating an intermediate body buffer.
   function Compute
     (Kind : Algorithm; Data : Ada.Streams.Stream_Element_Array)
      return Digest_Value;

   type Digest_Array is array (Positive range <>) of Digest_Value;

   --  Hash the concatenated raw part digests for an S3 composite checksum.
   function Composite
     (Kind : Algorithm; Parts : Digest_Array) return Digest_Value
   with
     Pre =>
       Parts'Length > 0
       and then (for all Part of Parts => Checksums.Kind (Part) = Kind)
       and then Policy.Supported (Kind, Policy.Composite);

   type Part_Checksum is record
      Value  : Digest_Value;
      Length : Byte_Count := 0;
   end record;

   type Part_Checksum_Array is array (Positive range <>) of Part_Checksum;

   --  Linearize CRC part checksums into the full-object checksum.
   function Full_Object
     (Kind : Algorithm; Parts : Part_Checksum_Array) return Digest_Value
   with
     Pre =>
       Parts'Length > 0
       and then Policy.Supported (Kind, Policy.Full_Object)
       and then (for all Part of Parts =>
                    Checksums.Kind (Part.Value) = Kind);

private
   subtype Digest_Index is Positive range 1 .. Maximum_Digest_Length;
   type Digest_Buffer is array (Digest_Index) of Ada.Streams.Stream_Element;

   type Digest_Value is record
      Algorithm_Value : Algorithm := Policy.Core.CRC32;
      Bytes           : Digest_Buffer := (others => 0);
   end record;

   XXH_Storage_Bytes : constant := 1_024;
   type XXH_Storage is array (Natural range 0 .. 127) of
     aliased Interfaces.Unsigned_64
   with Convention => C, Alignment => 64;

   type Context (Kind : Algorithm) is
     new Ada.Finalization.Limited_Controlled with record
      CRC32_State : CRC.Context (Policy.Core.CRC32);
      CRC32C_State : CRC.Context (Policy.Core.CRC32C);
      CRC64NVME_State : CRC.Context (Policy.Core.CRC64NVME);
      MD5_State    : GNAT.MD5.Context := GNAT.MD5.Initial_Context;
      SHA1_State   : GNAT.SHA1.Context := GNAT.SHA1.Initial_Context;
      SHA256_State : GNAT.SHA256.Context := GNAT.SHA256.Initial_Context;
      SHA512_State : GNAT.SHA512.Context := GNAT.SHA512.Initial_Context;
      XXH_State    : XXH_Storage := (others => 0);
   end record;

   overriding procedure Initialize (Item : in out Context);

end Flyology.Object_Storage.S3.Checksums;
