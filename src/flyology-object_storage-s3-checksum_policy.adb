package body Flyology.Object_Storage.S3.Checksum_Policy
  with SPARK_Mode => On
is

   function Parse_Algorithm (Text : String) return Algorithm_Parse_Result is
   begin
      if Text = "CRC32" then
         return (Valid => True, Value => Core.CRC32);
      elsif Text = "CRC32C" then
         return (Valid => True, Value => Core.CRC32C);
      elsif Text = "CRC64NVME" then
         return (Valid => True, Value => Core.CRC64NVME);
      elsif Text = "SHA1" then
         return (Valid => True, Value => Core.SHA1);
      elsif Text = "SHA256" then
         return (Valid => True, Value => Core.SHA256);
      elsif Text = "SHA512" then
         return (Valid => True, Value => Core.SHA512);
      elsif Text = "MD5" then
         return (Valid => True, Value => Core.MD5);
      elsif Text = "XXHASH64" then
         return (Valid => True, Value => Core.XXHASH64);
      elsif Text = "XXHASH3" then
         return (Valid => True, Value => Core.XXHASH3);
      elsif Text = "XXHASH128" then
         return (Valid => True, Value => Core.XXHASH128);
      else
         return (Valid => False);
      end if;
   end Parse_Algorithm;

   function Parse_Type (Text : String) return Type_Parse_Result is
   begin
      if Text = "COMPOSITE" then
         return (Valid => True, Value => Composite);
      elsif Text = "FULL_OBJECT" then
         return (Valid => True, Value => Full_Object);
      else
         return (Valid => False);
      end if;
   end Parse_Type;

end Flyology.Object_Storage.S3.Checksum_Policy;
