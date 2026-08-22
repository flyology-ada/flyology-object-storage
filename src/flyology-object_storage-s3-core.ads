--  SPARK-proved scalar rules shared by S3 client, server, and backends.
package Flyology.Object_Storage.S3.Core
  with SPARK_Mode => On
is

   KiB : constant Byte_Count := 1_024;
   MiB : constant Byte_Count := KiB * 1_024;
   GiB : constant Byte_Count := MiB * 1_024;

   Maximum_Object_Size : constant Byte_Count := 50_000 * GiB;
   Minimum_Part_Size   : constant Byte_Count := 5 * MiB;
   Maximum_Part_Size   : constant Byte_Count := 5 * GiB;

   subtype Part_Number is Positive range 1 .. 10_000;
   subtype Page_Size is Natural range 0 .. 1_000;

   Maximum_Listing_Cursor_Bytes : constant := 1_024;

   --  Validate the bounded Flyology continuation envelope before token
   --  decoding or digest work: fos1., 64 hexadecimal characters encoding a
   --  SHA-256 digest, a dot, and an even hexadecimal cursor no longer than an
   --  S3 object key.
   function Valid_Listing_Continuation_Syntax
     (Token : String) return Boolean;

   type Checksum_Algorithm is
     (No_Checksum, CRC32, CRC32C, CRC64NVME, SHA1, SHA256, SHA512, MD5,
      XXHASH64, XXHASH3, XXHASH128);

   type Versioning_State is (Disabled, Enabled, Suspended);

   type Multipart_State is
     (Initiated, Active, Completing, Completed, Aborted);

   function Can_Transition
     (From, To : Multipart_State) return Boolean
   is
     (case From is
         when Initiated  => To in Active | Completing | Aborted,
         when Active     => To in Active | Completing | Aborted,
         when Completing => To in Completed | Active | Aborted,
         when Completed | Aborted => False);

   function Valid_Part_Size
     (Size : Byte_Count; Is_Final : Boolean) return Boolean
   is
     (Size <= Maximum_Part_Size
      and then (Is_Final or else Size >= Minimum_Part_Size));

   function Valid_Multipart_Part_Size
     (Part_Size : Byte_Count) return Boolean
   is
     (Part_Size in Minimum_Part_Size .. Maximum_Part_Size);

   --  Return the exact number of fixed-size multipart ranges required for
   --  Size. The subtract-before-divide form avoids addition overflow.
   function Multipart_Part_Count
     (Size, Part_Size : Byte_Count) return Byte_Count
   is
     (if Size = 0 then 0 else 1 + (Size - 1) / Part_Size)
   with Pre => Part_Size > 0;

   function Valid_Multipart_Plan
     (Size, Part_Size : Byte_Count) return Boolean
   is
     (Size in 1 .. Maximum_Object_Size
      and then Valid_Multipart_Part_Size (Part_Size)
      and then Multipart_Part_Count (Size, Part_Size) <= 10_000);

   type Part_Number_Array is array (Positive range <>) of Part_Number;

   function Valid_Completion_Order
     (Parts : Part_Number_Array) return Boolean;

   function Valid_Consecutive_Completion_Order
     (Parts : Part_Number_Array) return Boolean;

   subtype Range_Request_Kind is Byte_Range_Kind;
   Whole      : constant Range_Request_Kind := Whole_Range;
   Bounded    : constant Range_Request_Kind := Bounded_Range;
   Open_Ended : constant Range_Request_Kind := Open_Ended_Range;
   Suffix     : constant Range_Request_Kind := Suffix_Range;
   subtype Range_Request is Byte_Range;

   type Range_Parse_Status is (Range_Parsed, Malformed_Range);

   type Range_Parse_Result is record
      Status  : Range_Parse_Status := Malformed_Range;
      Request : Range_Request;
   end record;

   --  Parse one RFC 9110 byte range. The bytes unit is case-insensitive and
   --  optional whitespace after '=' and at the field end is accepted.
   --  Multiple ranges are rejected because the server does not yet emit
   --  multipart/byteranges responses.
   function Parse_Range_Header (Value : String) return Range_Parse_Result;

   subtype Range_Resolution_Kind is
     Flyology.Object_Storage.Range_Resolution_Kind;
   Empty_Object : constant Range_Resolution_Kind := Empty_Object_Range;
   Satisfied    : constant Range_Resolution_Kind := Satisfied_Range;
   Unsatisfiable : constant Range_Resolution_Kind := Unsatisfiable_Range;
   subtype Range_Resolution is Flyology.Object_Storage.Range_Resolution;

   function Resolve_Range
     (Size : Byte_Count; Request : Range_Request) return Range_Resolution
     renames Flyology.Object_Storage.Resolve_Range;

end Flyology.Object_Storage.S3.Core;
