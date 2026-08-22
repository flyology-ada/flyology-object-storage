with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Copies is

   package US renames Ada.Strings.Unbounded;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;

   type Result_Field is
     (No_Field,
      Entity_Tag_Field,
      Last_Modified_Field,
      Checksum_Type_Field,
      CRC32_Field,
      CRC32C_Field,
      CRC64NVME_Field,
      SHA1_Field,
      SHA256_Field,
      SHA512_Field,
      MD5_Field,
      XXHASH64_Field,
      XXHASH3_Field,
      XXHASH128_Field);

   type Seen_Fields is array (Result_Field) of Boolean;

   type Copy_Handler is new XML.Event_Handler with record
      Value        : Copy_Object_Result;
      Text_Value   : US.Unbounded_String;
      Depth        : Natural := 0;
      Ignore_Depth : Natural := 0;
      Field        : Result_Field := No_Field;
      Seen         : Seen_Fields := (others => False);
   end record;

   overriding procedure Start_Element
     (Item : in out Copy_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Copy_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Copy_Handler; Local_Name : String);

   function Field_For (Local_Name : String) return Result_Field is
     (if Local_Name = "ETag" then Entity_Tag_Field
      elsif Local_Name = "LastModified" then Last_Modified_Field
      elsif Local_Name = "ChecksumType" then Checksum_Type_Field
      elsif Local_Name = "ChecksumCRC32" then CRC32_Field
      elsif Local_Name = "ChecksumCRC32C" then CRC32C_Field
      elsif Local_Name = "ChecksumCRC64NVME" then CRC64NVME_Field
      elsif Local_Name = "ChecksumSHA1" then SHA1_Field
      elsif Local_Name = "ChecksumSHA256" then SHA256_Field
      elsif Local_Name = "ChecksumSHA512" then SHA512_Field
      elsif Local_Name = "ChecksumMD5" then MD5_Field
      elsif Local_Name = "ChecksumXXHASH64" then XXHASH64_Field
      elsif Local_Name = "ChecksumXXHASH3" then XXHASH3_Field
      elsif Local_Name = "ChecksumXXHASH128" then XXHASH128_Field
      else No_Field);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value not in ' ' | Character'Val (9) |
           Character'Val (10) | Character'Val (13)
         then
            raise Malformed_Copy with "text outside copy result fields";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element
     (Item : in out Copy_Handler; Local_Name : String)
   is
      Selected : Result_Field;
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Copy with "copy result depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Depth = 1 then
         if Local_Name /= "CopyObjectResult" then
            raise Malformed_Copy with "wrong copy result root";
         end if;
      elsif Item.Depth = 2 then
         Selected := Field_For (Local_Name);
         if Selected = No_Field then
            Item.Ignore_Depth := Item.Depth;
         elsif Item.Seen (Selected) then
            raise Malformed_Copy with "duplicate copy result field";
         else
            Item.Seen (Selected) := True;
            Item.Field := Selected;
            US.Set_Unbounded_String (Item.Text_Value, "");
         end if;
      else
         raise Malformed_Copy with "nested copy result field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Copy_Handler; Value : String) is
   begin
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field = No_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   procedure Finish_Field (Item : in out Copy_Handler) is
   begin
      case Item.Field is
         when Entity_Tag_Field =>
            Item.Value.Entity_Tag := Item.Text_Value;
         when Last_Modified_Field =>
            Item.Value.Last_Modified := Item.Text_Value;
         when Checksum_Type_Field =>
            Item.Value.Checksum_Type := Item.Text_Value;
         when CRC32_Field =>
            Item.Value.Checksum_CRC32 := Item.Text_Value;
         when CRC32C_Field =>
            Item.Value.Checksum_CRC32C := Item.Text_Value;
         when CRC64NVME_Field =>
            Item.Value.Checksum_CRC64NVME := Item.Text_Value;
         when SHA1_Field =>
            Item.Value.Checksum_SHA1 := Item.Text_Value;
         when SHA256_Field =>
            Item.Value.Checksum_SHA256 := Item.Text_Value;
         when SHA512_Field =>
            Item.Value.Checksum_SHA512 := Item.Text_Value;
         when MD5_Field =>
            Item.Value.Checksum_MD5 := Item.Text_Value;
         when XXHASH64_Field =>
            Item.Value.Checksum_XXHASH64 := Item.Text_Value;
         when XXHASH3_Field =>
            Item.Value.Checksum_XXHASH3 := Item.Text_Value;
         when XXHASH128_Field =>
            Item.Value.Checksum_XXHASH128 := Item.Text_Value;
         when No_Field =>
            null;
      end case;
      Item.Field := No_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Field;

   overriding procedure End_Element
     (Item : in out Copy_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Copy with "copy result stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         Finish_Field (Item);
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Validate_Checksum
     (Value : US.Unbounded_String; Decoded_Bytes : Positive) is
   begin
      if US.Length (Value) > 0
        and then not Wire_Core.Valid_Base64
          (US.To_String (Value), Decoded_Bytes)
      then
         raise Malformed_Copy with "invalid CopyObject checksum";
      end if;
   end Validate_Checksum;

   procedure Validate (Value : Copy_Object_Result) is
      Kind : constant String := US.To_String (Value.Checksum_Type);
   begin
      if US.Length (Value.Entity_Tag) = 0
        or else US.Length (Value.Last_Modified) = 0
      then
         raise Malformed_Copy with "incomplete CopyObject result";
      end if;
      Validate_Checksum (Value.Checksum_CRC32, 4);
      Validate_Checksum (Value.Checksum_CRC32C, 4);
      Validate_Checksum (Value.Checksum_CRC64NVME, 8);
      Validate_Checksum (Value.Checksum_SHA1, 20);
      Validate_Checksum (Value.Checksum_SHA256, 32);
      Validate_Checksum (Value.Checksum_SHA512, 64);
      Validate_Checksum (Value.Checksum_MD5, 16);
      Validate_Checksum (Value.Checksum_XXHASH64, 8);
      Validate_Checksum (Value.Checksum_XXHASH3, 8);
      Validate_Checksum (Value.Checksum_XXHASH128, 16);
      if Kind'Length > 0
        and then Kind /= "COMPOSITE"
        and then Kind /= "FULL_OBJECT"
      then
         raise Malformed_Copy with "invalid CopyObject checksum type";
      end if;
   end Validate;

   function Parse_Copy_Object_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Copy_Object_Result
   is
      Handler : aliased Copy_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Copy with "malformed CopyObject result";
   end Parse_Copy_Object_Result;

end Flyology.Object_Storage.S3.Copies;
