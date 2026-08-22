with Ada.Streams;
with Interfaces;
with Flyology.Object_Storage.S3.Core;

--  Portable streaming CRCs and checksum linearization for S3.
package Flyology.Object_Storage.S3.Checksum_CRC
  with SPARK_Mode => On
is
   package Core renames Flyology.Object_Storage.S3.Core;
   use type Core.Checksum_Algorithm;

   subtype Algorithm is Core.Checksum_Algorithm range
     Core.CRC32 .. Core.CRC64NVME;

   type Context (Kind : Algorithm) is private;

   --  Construct a context at the standard algorithm initial state.
   function Initial_Context (Kind : Algorithm) return Context;

   --  Add the next byte sequence. Empty slices are accepted.
   procedure Update
     (Item : in out Context; Data : Ada.Streams.Stream_Element_Array);

   --  Return the finalized checksum in the low 32 or 64 bits.
   function Finish (Item : Context) return Interfaces.Unsigned_64;

   --  Linearize two finalized CRCs without rereading either byte sequence.
   function Combine
     (Kind         : Algorithm;
      Left, Right  : Interfaces.Unsigned_64;
      Right_Length : Byte_Count) return Interfaces.Unsigned_64;

private
   type Context (Kind : Algorithm) is record
      State : Interfaces.Unsigned_64 :=
        (if Kind = Core.CRC64NVME
         then Interfaces.Unsigned_64'Last
         else 16#FFFF_FFFF#);
   end record;
end Flyology.Object_Storage.S3.Checksum_CRC;
