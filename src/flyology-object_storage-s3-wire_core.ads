--  SPARK-proved lexical rules for attacker-controlled S3 wire scalars.
package Flyology.Object_Storage.S3.Wire_Core
  with SPARK_Mode => On
is
   type Natural_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Natural;
         when False =>
            null;
      end case;
   end record;

   type Byte_Count_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Byte_Count;
         when False =>
            null;
      end case;
   end record;

   type Boolean_Result (Valid : Boolean := False) is record
      case Valid is
         when True =>
            Value : Boolean;
         when False =>
            null;
      end case;
   end record;

   function Parse_Natural (Text : String) return Natural_Result;
   function Parse_Byte_Count (Text : String) return Byte_Count_Result;
   function Parse_Boolean (Text : String) return Boolean_Result;

   function Valid_Base64
     (Text : String; Decoded_Length : Natural) return Boolean
   with Pre => Decoded_Length <= 1_000_000;

end Flyology.Object_Storage.S3.Wire_Core;
