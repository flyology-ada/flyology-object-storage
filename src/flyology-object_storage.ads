with Ada.Strings.Unbounded;

--  Defines storage-domain values shared by S3 clients, servers and backends.
--  Wire DTOs and HTTP state intentionally do not cross this package boundary.
package Flyology.Object_Storage
  with SPARK_Mode => On
is

   --  Nonnegative byte count used for object and multipart sizes.
   subtype Byte_Count is Long_Long_Integer range 0 .. Long_Long_Integer'Last;
   subtype Unix_Time is Long_Long_Integer range 0 .. Long_Long_Integer'Last;

   --  Storage operation outcome.
   type Status is
     (Success,
      Not_Found,
      Bucket_Not_Found,
      Already_Exists,
      Bucket_Not_Empty,
      Capacity_Exceeded,
      Invalid_Request,
      Invalid_Range,
      Invalid_Part,
      Invalid_Part_Order,
      Entity_Too_Small,
      Entity_Too_Large,
      Source_Not_Found,
      Precondition_Failed,
      Not_Modified,
      Conflict,
      Not_Implemented,
      Backend_Unavailable);

   --  Requested object byte interval. Backends resolve this request against
   --  the same immutable object snapshot that they stream, including suffix
   --  requests, so callers never need a racy Head_Object/Get_Object pair.
   type Byte_Range_Kind is
     (Whole_Range, Bounded_Range, Open_Ended_Range, Suffix_Range);

   type Byte_Range is record
      Kind  : Byte_Range_Kind := Whole_Range;
      First : Byte_Count := 0;
      Last  : Byte_Count := 0;
      Count : Byte_Count := 0;
   end record;

   --  Complete object body range.
   Whole_Object : constant Byte_Range := (others => <>);

   type Range_Resolution_Kind is
     (Empty_Object_Range, Satisfied_Range, Unsatisfiable_Range);

   type Range_Resolution
     (Kind : Range_Resolution_Kind := Unsatisfiable_Range)
   is record
      case Kind is
         when Satisfied_Range =>
            First  : Byte_Count;
            Last   : Byte_Count;
            Length : Byte_Count;
         when Empty_Object_Range | Unsatisfiable_Range =>
            null;
      end case;
   end record;

   --  Resolve a request against one immutable object size.
   function Resolve_Range
     (Size : Byte_Count; Request : Byte_Range) return Range_Resolution
   with
     Post =>
       (if Resolve_Range'Result.Kind = Satisfied_Range then
          Resolve_Range'Result.First <= Resolve_Range'Result.Last
          and then Resolve_Range'Result.Last < Size
          and then Resolve_Range'Result.Length > 0
          and then Resolve_Range'Result.Length =
            Resolve_Range'Result.Last - Resolve_Range'Result.First + 1);

   --  Metadata retained with one committed object version.
   type Object_Information is record
      Size          : Byte_Count := 0;
      Modified      : Unix_Time := 0;
      Entity_Tag    : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type  : Ada.Strings.Unbounded.Unbounded_String;
      Version       : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Metadata supplied when committing an object. An empty Entity_Tag asks
   --  the backend to generate the ordinary single-part S3 MD5 entity tag.
   --  This identifier is not a collision-resistant integrity checksum.
   type Put_Options is record
      Entity_Tag   : Ada.Strings.Unbounded.Unbounded_String;
      Content_Type : Ada.Strings.Unbounded.Unbounded_String;
   end record;

   --  Default metadata for an opaque binary object.
   Default_Put_Options : constant Put_Options;

   --  Validate an ordinary general-purpose S3 bucket name.
   --  @param Value Candidate bucket name
   --  @return True when Value is safe for the shared backend namespace
   function Valid_Bucket_Name (Value : String) return Boolean;

   --  Validate an object key at the storage boundary.
   --  @param Value Candidate object key
   --  @return True for a nonempty key of at most 1,024 bytes without NUL
   function Valid_Object_Key (Value : String) return Boolean;

private
   Default_Put_Options : constant Put_Options :=
     (Entity_Tag   => Ada.Strings.Unbounded.Null_Unbounded_String,
      Content_Type =>
        Ada.Strings.Unbounded.To_Unbounded_String
          ("application/octet-stream"));
end Flyology.Object_Storage;
