with Ada.Strings.Unbounded;

package body Flyology.Object_Storage.Checksum_Engine is
   package Policy renames Flyology.Object_Storage.S3.Checksum_Policy;
   package S3_Checksums renames Flyology.Object_Storage.S3.Checksums;
   package US renames Ada.Strings.Unbounded;
   use type Policy.Checksum_Type;

   function Algorithm_Value
     (Value : Checksum_Algorithm) return Policy.Algorithm is
   begin
      case Value is
         when Checksum_CRC32 => return Policy.Core.CRC32;
         when Checksum_CRC32C => return Policy.Core.CRC32C;
         when Checksum_CRC64NVME => return Policy.Core.CRC64NVME;
         when Checksum_SHA1 => return Policy.Core.SHA1;
         when Checksum_SHA256 => return Policy.Core.SHA256;
         when Checksum_SHA512 => return Policy.Core.SHA512;
         when Checksum_MD5 => return Policy.Core.MD5;
         when Checksum_XXHASH64 => return Policy.Core.XXHASH64;
         when Checksum_XXHASH3 => return Policy.Core.XXHASH3;
         when Checksum_XXHASH128 => return Policy.Core.XXHASH128;
         when No_Checksum => raise Constraint_Error;
      end case;
   end Algorithm_Value;

   function To_S3 (Value : Checksum_Method) return Policy.Checksum_Type is
     (case Value is
         when Composite_Checksum => Policy.Composite,
         when Full_Object_Checksum => Policy.Full_Object,
         when No_Checksum_Method => raise Constraint_Error);

   function Valid_Configuration
     (Value : Checksum_Information) return Boolean
   is
   begin
      if Value.Algorithm = No_Checksum then
         return Value.Method = No_Checksum_Method
           and then US.Length (Value.Value) = 0;
      elsif Value.Method = No_Checksum_Method then
         return False;
      else
         return Policy.Supported
           (Algorithm_Value (Value.Algorithm), To_S3 (Value.Method))
           and then US.Length (Value.Value) = 0;
      end if;
   end Valid_Configuration;

   function Valid_Digest
     (Value : String; Algorithm : Checksum_Algorithm) return Boolean is
     (Algorithm /= No_Checksum
      and then S3_Checksums.Decode_Base64
        (Value, Algorithm_Value (Algorithm)).Valid);

   function Valid_Object_Digest
     (Value      : String;
      Algorithm  : Checksum_Algorithm;
      Method     : Checksum_Method;
      Part_Count : Positive) return Boolean is
     (Algorithm /= No_Checksum
      and then Method /= No_Checksum_Method
      and then Policy.Supported
        (Algorithm_Value (Algorithm), To_S3 (Method))
      and then S3_Checksums.Decode_Object
        (Value, Algorithm_Value (Algorithm), To_S3 (Method),
         Part_Count).Valid);

   procedure Update
     (Item : in out Context; Data : Ada.Streams.Stream_Element_Array) is
   begin
      S3_Checksums.Update (Item.State, Data);
   end Update;

   function Finish (Item : Context) return String is
     (S3_Checksums.Encode_Base64 (S3_Checksums.Finish (Item.State)));

   function Multipart_Object_Value
     (Algorithm : Checksum_Algorithm;
      Method    : Checksum_Method;
      Parts     : Part_Value_Array) return String
   is
      S3_Algorithm : constant Policy.Algorithm := Algorithm_Value (Algorithm);
      S3_Method    : constant Policy.Checksum_Type := To_S3 (Method);
      Digests : S3_Checksums.Digest_Array (Parts'Range);
      Linear  : S3_Checksums.Part_Checksum_Array (Parts'Range);
   begin
      for Index in Parts'Range loop
         if Parts (Index).Value.Algorithm /= Algorithm
           or else Parts (Index).Value.Method /= Method
         then
            raise Constraint_Error with "inconsistent multipart checksum";
         end if;
         declare
            Decoded : constant S3_Checksums.Decode_Result :=
              S3_Checksums.Decode_Base64
                (US.To_String (Parts (Index).Value.Value), S3_Algorithm);
         begin
            if not Decoded.Valid then
               raise Constraint_Error with "invalid stored part checksum";
            end if;
            Digests (Index) := Decoded.Value;
            Linear (Index) :=
              (Value => Decoded.Value, Length => Parts (Index).Length);
         end;
      end loop;

      if S3_Method = Policy.Composite then
         return S3_Checksums.Encode_Object
           (S3_Checksums.Composite (S3_Algorithm, Digests),
            S3_Method, Parts'Length);
      else
         return S3_Checksums.Encode_Object
           (S3_Checksums.Full_Object (S3_Algorithm, Linear),
            S3_Method, Parts'Length);
      end if;
   end Multipart_Object_Value;

end Flyology.Object_Storage.Checksum_Engine;
