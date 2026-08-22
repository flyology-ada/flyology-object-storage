with Ada.Finalization;
with Ada.Streams;
with Flyology.Object_Storage.S3.Checksum_Policy;
with Flyology.Object_Storage.S3.Checksums;

--  Internal streaming bridge between storage metadata and S3 checksum
--  algorithms. Protocol spelling and request validation stay above backends.
package Flyology.Object_Storage.Checksum_Engine is

   --  Return whether an upload checksum selection has a supported
   --  algorithm/method pair and no digest value attached yet.
   function Valid_Configuration
     (Value : Checksum_Information) return Boolean;

   --  Validate a direct whole-body checksum selection. Unlike the multipart
   --  policy, every checksum algorithm modeled by CopyObject is permitted.
   function Valid_Direct_Configuration
     (Value : Checksum_Information) return Boolean;

   --  Return whether Value is the canonical raw Base64 digest for Algorithm.
   function Valid_Digest
     (Value : String; Algorithm : Checksum_Algorithm) return Boolean;

   --  Return whether Value is the canonical completed-object checksum,
   --  including the exact part-count suffix required for composites.
   function Valid_Object_Digest
     (Value      : String;
      Algorithm  : Checksum_Algorithm;
      Method     : Checksum_Method;
      Part_Count : Positive) return Boolean;

   --  Compare an AWS completion-header raw Base64 digest with the canonical
   --  stored object form. Stored composites include their part-count suffix.
   function Matches_Stored_Object_Digest
     (Expected_Raw : String;
      Stored       : String;
      Algorithm    : Checksum_Algorithm;
      Method       : Checksum_Method;
      Part_Count   : Positive) return Boolean;

   --  Convert the storage-domain algorithm to the checksum implementation.
   function Algorithm_Value
     (Value : Checksum_Algorithm)
      return Flyology.Object_Storage.S3.Checksum_Policy.Algorithm
   with Pre => Value /= No_Checksum;

   type Context
     (Algorithm : Flyology.Object_Storage.S3.Checksum_Policy.Algorithm) is
     new Ada.Finalization.Limited_Controlled with private;

   --  Add the next contiguous body bytes to Item.
   procedure Update
     (Item : in out Context; Data : Ada.Streams.Stream_Element_Array);

   --  Return Item's canonical raw Base64 digest without invalidating Item.
   function Finish (Item : Context) return String;

   type Part_Value is record
      Value  : Checksum_Information;
      Length : Byte_Count := 0;
   end record;

   type Part_Value_Array is array (Positive range <>) of Part_Value;

   --  Return canonical stored object checksum form. Composite values include
   --  S3's part-count suffix; full-object CRC values do not.
   function Multipart_Object_Value
     (Algorithm : Checksum_Algorithm;
      Method    : Checksum_Method;
      Parts     : Part_Value_Array) return String
   with
     Pre =>
       Algorithm /= No_Checksum
       and then Method /= No_Checksum_Method
       and then Parts'Length > 0;

private
   type Context
     (Algorithm : Flyology.Object_Storage.S3.Checksum_Policy.Algorithm) is
     new Ada.Finalization.Limited_Controlled with record
      State : Flyology.Object_Storage.S3.Checksums.Context
        (Algorithm);
   end record;

end Flyology.Object_Storage.Checksum_Engine;
