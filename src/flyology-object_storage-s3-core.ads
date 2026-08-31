--  SPARK-proved scalar rules shared by S3 client, server, and backends.
package Flyology.Object_Storage.S3.Core
  with SPARK_Mode => On
is

   --  One binary kibibyte in bytes.
   KiB : constant Byte_Count := 1_024;

   --  One binary mebibyte in bytes.
   MiB : constant Byte_Count := KiB * 1_024;

   --  One binary gibibyte in bytes.
   GiB : constant Byte_Count := MiB * 1_024;

   --  Maximum object size accepted by the shared S3 contract.
   Maximum_Object_Size : constant Byte_Count := 50_000 * GiB;

   --  Minimum size accepted for a non-final multipart part.
   Minimum_Part_Size   : constant Byte_Count := 5 * MiB;

   --  Maximum size accepted for any multipart part.
   Maximum_Part_Size   : constant Byte_Count := 5 * GiB;

   --  Valid S3 multipart part number.
   subtype Part_Number is Positive range 1 .. 10_000;

   --  Requested or returned item count for one S3 page.
   subtype Page_Size is Natural range 0 .. 1_000;

   --  Maximum decoded cursor bytes in a listing continuation token.
   Maximum_Listing_Cursor_Bytes : constant := 1_024;

   --  Validate the bounded Flyology continuation envelope before token
   --  decoding or digest work: fos1., 64 hexadecimal characters encoding a
   --  SHA-256 digest, a dot, and an even hexadecimal cursor no longer than an
   --  S3 object key.
   --  @param Token Candidate continuation token
   --  @return True when Token has valid bounded envelope syntax
   function Valid_Listing_Continuation_Syntax
     (Token : String) return Boolean;

   --  Checksum algorithms represented by the shared S3 scalar contract.
   --  @enum No_Checksum No checksum algorithm is selected
   --  @enum CRC32 CRC-32 checksum
   --  @enum CRC32C CRC-32C checksum
   --  @enum CRC64NVME CRC-64/NVME checksum
   --  @enum SHA1 SHA-1 checksum
   --  @enum SHA256 SHA-256 checksum
   --  @enum SHA512 SHA-512 checksum
   --  @enum MD5 MD5 checksum
   --  @enum XXHASH64 XXH64 checksum
   --  @enum XXHASH3 XXH3 64-bit checksum
   --  @enum XXHASH128 XXH3 128-bit checksum
   type Checksum_Algorithm is
     (No_Checksum, CRC32, CRC32C, CRC64NVME, SHA1, SHA256, SHA512, MD5,
      XXHASH64, XXHASH3, XXHASH128);

   --  Effective S3 bucket-versioning state.
   --  @enum Disabled Versioning has not been enabled
   --  @enum Enabled Versioning is enabled
   --  @enum Suspended Versioning is suspended
   type Versioning_State is (Disabled, Enabled, Suspended);

   --  Multipart upload lifecycle state.
   --  @enum Initiated Upload has been initiated
   --  @enum Active Upload accepts parts
   --  @enum Completing Completion is in progress
   --  @enum Completed Upload completed successfully
   --  @enum Aborted Upload was aborted
   type Multipart_State is
     (Initiated, Active, Completing, Completed, Aborted);

   --  Test whether a multipart lifecycle transition is permitted.
   --  @param From Current multipart state
   --  @param To Proposed multipart state
   --  @return True when the transition is permitted
   function Can_Transition
     (From, To : Multipart_State) return Boolean
   is
     (case From is
         when Initiated  => To in Active | Completing | Aborted,
         when Active     => To in Active | Completing | Aborted,
         when Completing => To in Completed | Active | Aborted,
         when Completed | Aborted => False);

   --  Validate one uploaded multipart part size.
   --  @param Size Part size in bytes
   --  @param Is_Final Whether this is the final part
   --  @return True when Size satisfies the applicable part bounds
   function Valid_Part_Size
     (Size : Byte_Count; Is_Final : Boolean) return Boolean
   is
     (Size <= Maximum_Part_Size
      and then (Is_Final or else Size >= Minimum_Part_Size));

   --  Validate a fixed multipart planning size.
   --  @param Part_Size Planned part size in bytes
   --  @return True when Part_Size is within the multipart part bounds
   function Valid_Multipart_Part_Size
     (Part_Size : Byte_Count) return Boolean
   is
     (Part_Size in Minimum_Part_Size .. Maximum_Part_Size);

   --  Return the exact number of fixed-size multipart ranges required for
   --  Size. The subtract-before-divide form avoids addition overflow.
   --  @param Size Complete object size in bytes
   --  @param Part_Size Nonzero fixed part size in bytes
   --  @return Number of fixed-size ranges needed to cover Size
   function Multipart_Part_Count
     (Size, Part_Size : Byte_Count) return Byte_Count
   is
     (if Size = 0 then 0 else 1 + (Size - 1) / Part_Size)
   with Pre => Part_Size > 0;

   --  Validate a complete fixed-size multipart upload plan.
   --  @param Size Complete object size in bytes
   --  @param Part_Size Planned fixed part size in bytes
   --  @return True when object, part, and part-count bounds are satisfied
   function Valid_Multipart_Plan
     (Size, Part_Size : Byte_Count) return Boolean
   is
     (Size in 1 .. Maximum_Object_Size
      and then Valid_Multipart_Part_Size (Part_Size)
      and then Multipart_Part_Count (Size, Part_Size) <= 10_000);

   --  Sequence of bounded multipart part numbers.
   type Part_Number_Array is array (Positive range <>) of Part_Number;

   --  Validate a nonempty strictly increasing completion sequence.
   --  @param Parts Multipart part numbers in completion order
   --  @return True when Parts is nonempty and strictly increasing
   function Valid_Completion_Order
     (Parts : Part_Number_Array) return Boolean;

   --  Validate a complete consecutive sequence beginning at part one.
   --  @param Parts Multipart part numbers in completion order
   --  @return True when Parts is exactly a nonempty consecutive prefix
   function Valid_Consecutive_Completion_Order
     (Parts : Part_Number_Array) return Boolean;

   --  Kind of object byte-range request.
   subtype Range_Request_Kind is Byte_Range_Kind;

   --  Whole-object range-request kind.
   Whole      : constant Range_Request_Kind := Whole_Range;

   --  Inclusive first-to-last range-request kind.
   Bounded    : constant Range_Request_Kind := Bounded_Range;

   --  First-byte-through-object-end range-request kind.
   Open_Ended : constant Range_Request_Kind := Open_Ended_Range;

   --  Trailing-byte-count range-request kind.
   Suffix     : constant Range_Request_Kind := Suffix_Range;

   --  Object byte-range request.
   subtype Range_Request is Byte_Range;

   --  Result of parsing one range header.
   --  @enum Range_Parsed Header contains one supported byte range
   --  @enum Malformed_Range Header is malformed or unsupported
   type Range_Parse_Status is (Range_Parsed, Malformed_Range);

   --  Parsed range header outcome.
   --  @field Status Parse outcome
   --  @field Request Parsed request when Status is Range_Parsed
   type Range_Parse_Result is record
      Status  : Range_Parse_Status := Malformed_Range;
      Request : Range_Request;
   end record;

   --  Parse one RFC 9110 byte range. The bytes unit is case-insensitive and
   --  optional whitespace after '=' and at the field end is accepted.
   --  Multiple ranges are rejected because the server does not yet emit
   --  multipart/byteranges responses.
   --  @param Value Candidate Range header value
   --  @return Parsed request or Malformed_Range
   function Parse_Range_Header (Value : String) return Range_Parse_Result;

   --  Outcome kind for resolving a range against an object size.
   subtype Range_Resolution_Kind is
     Flyology.Object_Storage.Range_Resolution_Kind;

   --  Resolution kind for a whole-body request on an empty object.
   Empty_Object : constant Range_Resolution_Kind := Empty_Object_Range;

   --  Resolution kind for a nonempty satisfiable byte interval.
   Satisfied    : constant Range_Resolution_Kind := Satisfied_Range;

   --  Resolution kind for a request that cannot be satisfied for the object.
   Unsatisfiable : constant Range_Resolution_Kind := Unsatisfiable_Range;

   --  Resolved object byte interval.
   subtype Range_Resolution is Flyology.Object_Storage.Range_Resolution;

   --  Resolve a range request against one immutable object size.
   --  @param Size Immutable object size
   --  @param Request Requested byte interval
   --  @return Resolved interval or empty/unsatisfiable outcome
   function Resolve_Range
     (Size : Byte_Count; Request : Range_Request) return Range_Resolution
     renames Flyology.Object_Storage.Resolve_Range;

end Flyology.Object_Storage.S3.Core;
