with Flyology.Object_Storage.S3.Core;

--  Deterministic S3 checksum selection and wire metadata.
package Flyology.Object_Storage.S3.Checksum_Policy
  with SPARK_Mode => On
is
   package Core renames Flyology.Object_Storage.S3.Core;
   use type Core.Checksum_Algorithm;

   subtype Algorithm is Core.Checksum_Algorithm range
     Core.CRC32 .. Core.XXHASH128;

   type Checksum_Type is (Composite, Full_Object);

   type Algorithm_Parse_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Algorithm;
         when False =>
            null;
      end case;
   end record;

   type Type_Parse_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Checksum_Type;
         when False =>
            null;
      end case;
   end record;

   --  Return the fixed binary digest size used before Base64 encoding.
   function Digest_Length (Value : Algorithm) return Positive is
     (case Value is
         when Core.CRC32 | Core.CRC32C => 4,
         when Core.CRC64NVME | Core.XXHASH64 | Core.XXHASH3 => 8,
         when Core.MD5 | Core.XXHASH128 => 16,
         when Core.SHA1 => 20,
         when Core.SHA256 => 32,
         when Core.SHA512 => 64);

   --  Return the exact S3 model spelling for an algorithm.
   function Wire_Name (Value : Algorithm) return String is
     (case Value is
         when Core.CRC32 => "CRC32",
         when Core.CRC32C => "CRC32C",
         when Core.CRC64NVME => "CRC64NVME",
         when Core.SHA1 => "SHA1",
         when Core.SHA256 => "SHA256",
         when Core.SHA512 => "SHA512",
         when Core.MD5 => "MD5",
         when Core.XXHASH64 => "XXHASH64",
         when Core.XXHASH3 => "XXHASH3",
         when Core.XXHASH128 => "XXHASH128");

   --  Parse an exact, case-sensitive S3 checksum algorithm name.
   function Parse_Algorithm (Text : String) return Algorithm_Parse_Result;

   --  Return the exact S3 model spelling for a checksum type.
   function Wire_Name (Value : Checksum_Type) return String is
     (case Value is
         when Composite => "COMPOSITE",
         when Full_Object => "FULL_OBJECT");

   --  Parse an exact, case-sensitive S3 checksum type name.
   function Parse_Type (Text : String) return Type_Parse_Result;

   --  Report whether AWS permits the algorithm/type pair for multipart use.
   function Supported
     (Value : Algorithm; Kind : Checksum_Type) return Boolean is
     (case Kind is
         when Full_Object =>
           Value in Core.CRC32 | Core.CRC32C | Core.CRC64NVME,
         when Composite   => Value /= Core.CRC64NVME);

   --  Report whether an ordinary, non-multipart object can retain this
   --  checksum. PutObject and CopyObject accept every concrete algorithm in
   --  the pinned model, always as one full-object digest. Keep this predicate
   --  separate from the narrower multipart policy above.
   function Ordinary_Object_Supported
     (Kind : Checksum_Type) return Boolean is
     (Kind = Full_Object);

   --  Apply S3's default when CreateMultipartUpload omits checksum type.
   function Default_Type (Value : Algorithm) return Checksum_Type is
     (if Value = Core.CRC64NVME then Full_Object else Composite);

   --  Composite uploads require one checksum for every consecutive part.
   function Part_Checksums_Required
     (Kind : Checksum_Type) return Boolean is (Kind = Composite);

   function Consecutive_Parts_Required
     (Kind : Checksum_Type) return Boolean is (Kind = Composite);

end Flyology.Object_Storage.S3.Checksum_Policy;
