with Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Multipart is

   package US renames Ada.Strings.Unbounded;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;

   Maximum_Query_Length : constant := 8 * 1_024;

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 16);

   function Decode_Component (Value : String) return String is
      Raw    : constant String (1 .. Value'Length) := Value;
      Result : String (1 .. Value'Length);
      Input  : Natural := 1;
      Output : Natural := 0;
   begin
      while Input <= Raw'Length loop
         Output := Output + 1;
         if Raw (Input) = '%' then
            if Input + 2 > Raw'Length
              or else Hex_Value (Raw (Input + 1)) > 15
              or else Hex_Value (Raw (Input + 2)) > 15
            then
               raise Malformed_Multipart with
                 "invalid multipart query percent escape";
            end if;
            Result (Output) := Character'Val
              (16 * Hex_Value (Raw (Input + 1)) +
               Hex_Value (Raw (Input + 2)));
            Input := Input + 3;
         else
            Result (Output) := Raw (Input);
            Input := Input + 1;
         end if;
      end loop;
      return Result (1 .. Output);
   end Decode_Component;

   function Parse_Query (Query : String) return Multipart_Query is
      Seen_Uploads, Seen_Upload_ID, Seen_Part, Seen_X_ID : Boolean := False;
      Upload_ID : US.Unbounded_String;
      Operation_ID : US.Unbounded_String;
      Part_Number : Core.Part_Number := Core.Part_Number'First;
      Parameter_Count : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Length then
         raise Malformed_Multipart with "invalid multipart query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Parameter_Count := Parameter_Count + 1;
         end if;
      end loop;
      if Parameter_Count > 16 then
         raise Malformed_Multipart with "too many multipart query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Multipart with
                    "empty multipart query parameter";
               end if;
               declare
                  Pair_Text : constant String := Raw (First .. Index - 1);
                  Equals : constant Natural :=
                    Ada.Strings.Fixed.Index (Pair_Text, "=");
                  Name : constant String := Decode_Component
                    ((if Equals = 0 then Pair_Text
                      elsif Equals = Pair_Text'First then ""
                      else Pair_Text (Pair_Text'First .. Equals - 1)));
                  Value : constant String := Decode_Component
                    ((if Equals = 0 or else Equals = Pair_Text'Last then ""
                      else Pair_Text (Equals + 1 .. Pair_Text'Last)));
               begin
                  if Name = "uploads" then
                     if Seen_Uploads or else Value'Length /= 0 then
                        raise Malformed_Multipart with
                          "invalid multipart uploads marker";
                     end if;
                     Seen_Uploads := True;
                  elsif Name = "uploadId" then
                     if Seen_Upload_ID or else Value'Length not in 1 .. 1_024
                     then
                        raise Malformed_Multipart with
                          "invalid multipart upload identifier";
                     end if;
                     Seen_Upload_ID := True;
                     Upload_ID := US.To_Unbounded_String (Value);
                  elsif Name = "partNumber" then
                     declare
                        Parsed : constant Wire_Core.Natural_Result :=
                          Wire_Core.Parse_Natural (Value);
                     begin
                        if Seen_Part or else not Parsed.Valid
                          or else Parsed.Value not in Core.Part_Number'Range
                        then
                           raise Malformed_Multipart with
                             "invalid multipart part number";
                        end if;
                        Seen_Part := True;
                        Part_Number := Core.Part_Number (Parsed.Value);
                     end;
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value'Length = 0 then
                        raise Malformed_Multipart with
                          "invalid multipart operation identifier";
                     end if;
                     Seen_X_ID := True;
                     Operation_ID := US.To_Unbounded_String (Value);
                  else
                     raise Malformed_Multipart with
                       "unsupported multipart query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;

      if Seen_Uploads then
         if Seen_Upload_ID or else Seen_Part
           or else (Seen_X_ID and then US.To_String (Operation_ID) /=
             "CreateMultipartUpload")
         then
            raise Malformed_Multipart with
              "inconsistent multipart create query";
         end if;
         return (Kind => Create_Upload_Query,
                 Operation_ID => Operation_ID);
      elsif Seen_Upload_ID and then Seen_Part then
         if Seen_X_ID
           and then US.To_String (Operation_ID) /= "UploadPart"
           and then US.To_String (Operation_ID) /= "UploadPartCopy"
         then
            raise Malformed_Multipart with
              "inconsistent multipart part query";
         end if;
         return
           (Kind        => Upload_Part_Query,
            Operation_ID => Operation_ID,
            Upload_ID   => Upload_ID,
            Part_Number => Part_Number);
      elsif Seen_Upload_ID then
         if Seen_X_ID
           and then US.To_String (Operation_ID) /= "CompleteMultipartUpload"
           and then US.To_String (Operation_ID) /= "AbortMultipartUpload"
         then
            raise Malformed_Multipart with
              "inconsistent multipart upload query";
         end if;
         return
           (Kind               => Existing_Upload_Query,
            Operation_ID       => Operation_ID,
            Existing_Upload_ID => Upload_ID);
      else
         raise Malformed_Multipart with "multipart query lacks an upload";
      end if;
   end Parse_Query;

   type Field_Kind is
     (No_Field,
      Entity_Tag_Field,
      Part_Number_Field,
      Checksum_CRC32_Field,
      Checksum_CRC32C_Field,
      Checksum_CRC64NVME_Field,
      Checksum_SHA1_Field,
      Checksum_SHA256_Field,
      Checksum_SHA512_Field,
      Checksum_MD5_Field,
      Checksum_XXHASH64_Field,
      Checksum_XXHASH3_Field,
      Checksum_XXHASH128_Field);

   type Complete_Handler is new XML.Event_Handler with record
      Value                 : Complete_Multipart_Upload_Request;
      Current               : Completed_Part;
      Text_Value            : US.Unbounded_String;
      Depth                 : Natural := 0;
      Ignore_Depth          : Natural := 0;
      Field                 : Field_Kind := No_Field;
      In_Part               : Boolean := False;
      Seen_Entity_Tag       : Boolean := False;
      Seen_Part_Number      : Boolean := False;
      Seen_Checksum_CRC32   : Boolean := False;
      Seen_Checksum_CRC32C  : Boolean := False;
      Seen_Checksum_CRC64NVME : Boolean := False;
      Seen_Checksum_SHA1    : Boolean := False;
      Seen_Checksum_SHA256  : Boolean := False;
      Seen_Checksum_SHA512  : Boolean := False;
      Seen_Checksum_MD5     : Boolean := False;
      Seen_Checksum_XXHASH64 : Boolean := False;
      Seen_Checksum_XXHASH3  : Boolean := False;
      Seen_Checksum_XXHASH128 : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Complete_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Complete_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Complete_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value /= ' '
           and then Character_Value /= Character'Val (9)
           and then Character_Value /= Character'Val (10)
           and then Character_Value /= Character'Val (13)
         then
            raise Malformed_Multipart with "text outside multipart fields";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Select_Field
     (Item  : in out Complete_Handler;
      Seen  : in out Boolean;
      Field : Field_Kind)
   is
   begin
      if Seen then
         raise Malformed_Multipart with "duplicate multipart part field";
      end if;
      Seen := True;
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Field;

   procedure Reset_Part (Item : in out Complete_Handler) is
   begin
      Item.Current := (others => <>);
      Item.Seen_Entity_Tag := False;
      Item.Seen_Part_Number := False;
      Item.Seen_Checksum_CRC32 := False;
      Item.Seen_Checksum_CRC32C := False;
      Item.Seen_Checksum_CRC64NVME := False;
      Item.Seen_Checksum_SHA1 := False;
      Item.Seen_Checksum_SHA256 := False;
      Item.Seen_Checksum_SHA512 := False;
      Item.Seen_Checksum_MD5 := False;
      Item.Seen_Checksum_XXHASH64 := False;
      Item.Seen_Checksum_XXHASH3 := False;
      Item.Seen_Checksum_XXHASH128 := False;
      Item.In_Part := True;
   end Reset_Part;

   procedure Finish_Field (Item : in out Complete_Handler) is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Field is
         when Entity_Tag_Field =>
            Item.Current.Entity_Tag := Item.Text_Value;
         when Part_Number_Field =>
            declare
               Parsed : constant Wire_Core.Natural_Result :=
                 Wire_Core.Parse_Natural (Value);
            begin
               if not Parsed.Valid
                 or else Parsed.Value not in Core.Part_Number'Range
               then
                  raise Malformed_Multipart with
                    "invalid multipart part number";
               end if;
               Item.Current.Number := Core.Part_Number (Parsed.Value);
            end;
         when Checksum_CRC32_Field =>
            Item.Current.Checksum_CRC32 := Item.Text_Value;
         when Checksum_CRC32C_Field =>
            Item.Current.Checksum_CRC32C := Item.Text_Value;
         when Checksum_CRC64NVME_Field =>
            Item.Current.Checksum_CRC64NVME := Item.Text_Value;
         when Checksum_SHA1_Field =>
            Item.Current.Checksum_SHA1 := Item.Text_Value;
         when Checksum_SHA256_Field =>
            Item.Current.Checksum_SHA256 := Item.Text_Value;
         when Checksum_SHA512_Field =>
            Item.Current.Checksum_SHA512 := Item.Text_Value;
         when Checksum_MD5_Field =>
            Item.Current.Checksum_MD5 := Item.Text_Value;
         when Checksum_XXHASH64_Field =>
            Item.Current.Checksum_XXHASH64 := Item.Text_Value;
         when Checksum_XXHASH3_Field =>
            Item.Current.Checksum_XXHASH3 := Item.Text_Value;
         when Checksum_XXHASH128_Field =>
            Item.Current.Checksum_XXHASH128 := Item.Text_Value;
         when No_Field =>
            null;
      end case;
      Item.Field := No_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Field;

   overriding procedure Start_Element
     (Item : in out Complete_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Multipart with "multipart XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      end if;
      if Item.Depth = 1 then
         if Local_Name /= "CompleteMultipartUpload" then
            raise Malformed_Multipart with "wrong multipart completion root";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "Part" then
            if Item.Value.Parts.Length >=
              Ada.Containers.Count_Type (Core.Part_Number'Last)
            then
               raise Malformed_Multipart with "too many multipart parts";
            end if;
            Reset_Part (Item);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.In_Part then
         if Local_Name = "ETag" then
            Select_Field (Item, Item.Seen_Entity_Tag, Entity_Tag_Field);
         elsif Local_Name = "PartNumber" then
            Select_Field (Item, Item.Seen_Part_Number, Part_Number_Field);
         elsif Local_Name = "ChecksumCRC32" then
            Select_Field
              (Item, Item.Seen_Checksum_CRC32, Checksum_CRC32_Field);
         elsif Local_Name = "ChecksumCRC32C" then
            Select_Field
              (Item, Item.Seen_Checksum_CRC32C, Checksum_CRC32C_Field);
         elsif Local_Name = "ChecksumCRC64NVME" then
            Select_Field
              (Item, Item.Seen_Checksum_CRC64NVME,
               Checksum_CRC64NVME_Field);
         elsif Local_Name = "ChecksumSHA1" then
            Select_Field
              (Item, Item.Seen_Checksum_SHA1, Checksum_SHA1_Field);
         elsif Local_Name = "ChecksumSHA256" then
            Select_Field
              (Item, Item.Seen_Checksum_SHA256, Checksum_SHA256_Field);
         elsif Local_Name = "ChecksumSHA512" then
            Select_Field
              (Item, Item.Seen_Checksum_SHA512, Checksum_SHA512_Field);
         elsif Local_Name = "ChecksumMD5" then
            Select_Field
              (Item, Item.Seen_Checksum_MD5, Checksum_MD5_Field);
         elsif Local_Name = "ChecksumXXHASH64" then
            Select_Field
              (Item, Item.Seen_Checksum_XXHASH64, Checksum_XXHASH64_Field);
         elsif Local_Name = "ChecksumXXHASH3" then
            Select_Field
              (Item, Item.Seen_Checksum_XXHASH3, Checksum_XXHASH3_Field);
         elsif Local_Name = "ChecksumXXHASH128" then
            Select_Field
              (Item, Item.Seen_Checksum_XXHASH128, Checksum_XXHASH128_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      else
         raise Malformed_Multipart with "nested multipart field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Complete_Handler; Value : String) is
   begin
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field = No_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Complete_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Multipart with "multipart XML stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         Finish_Field (Item);
      elsif Item.Depth = 2 and then Item.In_Part then
         if not Item.Seen_Entity_Tag
           or else not Item.Seen_Part_Number
           or else US.Length (Item.Current.Entity_Tag) = 0
         then
            raise Malformed_Multipart with "incomplete multipart part";
         end if;
         Item.Value.Parts.Append (Item.Current);
         Item.In_Part := False;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Validate (Value : Complete_Multipart_Upload_Request) is
      Length : constant Ada.Containers.Count_Type := Value.Parts.Length;
      Has_Additional_Checksum : Boolean := False;
   begin
      if Length = 0
        or else Length > Ada.Containers.Count_Type (Core.Part_Number'Last)
      then
         raise Malformed_Multipart with "invalid multipart part count";
      end if;
      declare
         Numbers : Core.Part_Number_Array (1 .. Natural (Length));
         Index   : Positive := Numbers'First;
      begin
         for Part of Value.Parts loop
            if US.Length (Part.Entity_Tag) = 0 then
               raise Malformed_Multipart with "empty multipart entity tag";
            elsif (US.Length (Part.Checksum_CRC32) > 0
                   and then not Wire_Core.Valid_Base64
                     (US.To_String (Part.Checksum_CRC32), 4))
              or else (US.Length (Part.Checksum_CRC32C) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_CRC32C), 4))
              or else (US.Length (Part.Checksum_CRC64NVME) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_CRC64NVME), 8))
              or else (US.Length (Part.Checksum_SHA1) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_SHA1), 20))
              or else (US.Length (Part.Checksum_SHA256) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_SHA256), 32))
              or else (US.Length (Part.Checksum_SHA512) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_SHA512), 64))
              or else (US.Length (Part.Checksum_MD5) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_MD5), 16))
              or else (US.Length (Part.Checksum_XXHASH64) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_XXHASH64), 8))
              or else (US.Length (Part.Checksum_XXHASH3) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_XXHASH3), 8))
              or else (US.Length (Part.Checksum_XXHASH128) > 0
                       and then not Wire_Core.Valid_Base64
                         (US.To_String (Part.Checksum_XXHASH128), 16))
            then
               raise Malformed_Multipart with "invalid multipart checksum";
            end if;
            Has_Additional_Checksum := Has_Additional_Checksum
              or else US.Length (Part.Checksum_CRC32) > 0
              or else US.Length (Part.Checksum_CRC32C) > 0
              or else US.Length (Part.Checksum_CRC64NVME) > 0
              or else US.Length (Part.Checksum_SHA1) > 0
              or else US.Length (Part.Checksum_SHA256) > 0
              or else US.Length (Part.Checksum_SHA512) > 0
              or else US.Length (Part.Checksum_MD5) > 0
              or else US.Length (Part.Checksum_XXHASH64) > 0
              or else US.Length (Part.Checksum_XXHASH3) > 0
              or else US.Length (Part.Checksum_XXHASH128) > 0;
            Numbers (Index) := Part.Number;
            if Index < Numbers'Last then
               Index := Index + 1;
            end if;
         end loop;
         if not Core.Valid_Completion_Order (Numbers) then
            raise Malformed_Multipart with "multipart parts are not ordered";
         elsif Has_Additional_Checksum
           and then not Core.Valid_Consecutive_Completion_Order (Numbers)
         then
            raise Malformed_Multipart with
              "checksummed multipart parts are not consecutive";
         end if;
      end;
   end Validate;

   function Parse_Complete_Request
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Complete_Multipart_Upload_Request
   is
      Handler : aliased Complete_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Multipart with "malformed multipart completion XML";
   end Parse_Complete_Request;

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Image (Value : Core.Part_Number) return String is
     (Ada.Strings.Fixed.Trim
        (Core.Part_Number'Image (Value), Ada.Strings.Both));

   procedure Append_Optional
     (Target : in out US.Unbounded_String; Name, Value : String) is
   begin
      if Value'Length > 0 then
         US.Append (Target, Element (Name, Value));
      end if;
   end Append_Optional;

   function Serialize_Complete_Request
     (Value : Complete_Multipart_Upload_Request) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<CompleteMultipartUpload xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">");
      for Part of Value.Parts loop
         US.Append
           (Result,
            "<Part>" & Element ("ETag", US.To_String (Part.Entity_Tag)));
         Append_Optional
           (Result, "ChecksumCRC32", US.To_String (Part.Checksum_CRC32));
         Append_Optional
           (Result, "ChecksumCRC32C", US.To_String (Part.Checksum_CRC32C));
         Append_Optional
           (Result, "ChecksumCRC64NVME",
            US.To_String (Part.Checksum_CRC64NVME));
         Append_Optional
           (Result, "ChecksumSHA1", US.To_String (Part.Checksum_SHA1));
         Append_Optional
           (Result, "ChecksumSHA256", US.To_String (Part.Checksum_SHA256));
         Append_Optional
           (Result, "ChecksumSHA512", US.To_String (Part.Checksum_SHA512));
         Append_Optional
           (Result, "ChecksumMD5", US.To_String (Part.Checksum_MD5));
         Append_Optional
           (Result, "ChecksumXXHASH64",
            US.To_String (Part.Checksum_XXHASH64));
         Append_Optional
           (Result, "ChecksumXXHASH3",
            US.To_String (Part.Checksum_XXHASH3));
         Append_Optional
           (Result, "ChecksumXXHASH128",
            US.To_String (Part.Checksum_XXHASH128));
         US.Append (Result, Element ("PartNumber", Image (Part.Number)));
         US.Append (Result, "</Part>");
      end loop;
      US.Append (Result, "</CompleteMultipartUpload>");
      return US.To_String (Result);
   end Serialize_Complete_Request;

   type Result_Kind is
     (Create_Result_Kind, Complete_Result_Kind, Copy_Part_Result_Kind);

   type Result_Field is
     (No_Result_Field,
      Location_Result_Field,
      Bucket_Result_Field,
      Key_Result_Field,
      Upload_ID_Result_Field,
      Entity_Tag_Result_Field,
      Last_Modified_Result_Field,
      CRC32_Result_Field,
      CRC32C_Result_Field,
      CRC64NVME_Result_Field,
      SHA1_Result_Field,
      SHA256_Result_Field,
      SHA512_Result_Field,
      MD5_Result_Field,
      XXHASH64_Result_Field,
      XXHASH3_Result_Field,
      XXHASH128_Result_Field,
      Checksum_Type_Result_Field);

   type Seen_Result_Fields is array (Result_Field) of Boolean;

   type Result_Handler (Kind : Result_Kind) is
     new XML.Event_Handler with record
      Create_Value   : Create_Multipart_Upload_Result;
      Complete_Value : Complete_Multipart_Upload_Result;
      Copy_Part_Value : Copy_Part_Result;
      Text_Value     : US.Unbounded_String;
      Depth          : Natural := 0;
      Ignore_Depth   : Natural := 0;
      Field          : Result_Field := No_Result_Field;
      Seen           : Seen_Result_Fields := (others => False);
   end record;

   overriding procedure Start_Element
     (Item : in out Result_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Result_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Result_Handler; Local_Name : String);

   procedure Select_Result_Field
     (Item : in out Result_Handler; Field : Result_Field) is
   begin
      if Item.Seen (Field) then
         raise Malformed_Multipart with "duplicate multipart result field";
      end if;
      Item.Seen (Field) := True;
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Result_Field;

   function Complete_Field (Local_Name : String) return Result_Field is
     (if Local_Name = "Location" then Location_Result_Field
      elsif Local_Name = "Bucket" then Bucket_Result_Field
      elsif Local_Name = "Key" then Key_Result_Field
      elsif Local_Name = "ETag" then Entity_Tag_Result_Field
      elsif Local_Name = "ChecksumCRC32" then CRC32_Result_Field
      elsif Local_Name = "ChecksumCRC32C" then CRC32C_Result_Field
      elsif Local_Name = "ChecksumCRC64NVME" then CRC64NVME_Result_Field
      elsif Local_Name = "ChecksumSHA1" then SHA1_Result_Field
      elsif Local_Name = "ChecksumSHA256" then SHA256_Result_Field
      elsif Local_Name = "ChecksumSHA512" then SHA512_Result_Field
      elsif Local_Name = "ChecksumMD5" then MD5_Result_Field
      elsif Local_Name = "ChecksumXXHASH64" then XXHASH64_Result_Field
      elsif Local_Name = "ChecksumXXHASH3" then XXHASH3_Result_Field
      elsif Local_Name = "ChecksumXXHASH128" then XXHASH128_Result_Field
      elsif Local_Name = "ChecksumType" then Checksum_Type_Result_Field
      else No_Result_Field);

   function Copy_Part_Field (Local_Name : String) return Result_Field is
     (if Local_Name = "LastModified" then Last_Modified_Result_Field
      elsif Complete_Field (Local_Name) in
        Entity_Tag_Result_Field | CRC32_Result_Field |
        CRC32C_Result_Field | CRC64NVME_Result_Field |
        SHA1_Result_Field | SHA256_Result_Field | SHA512_Result_Field |
        MD5_Result_Field | XXHASH64_Result_Field | XXHASH3_Result_Field |
        XXHASH128_Result_Field
      then Complete_Field (Local_Name)
      else No_Result_Field);

   overriding procedure Start_Element
     (Item : in out Result_Handler; Local_Name : String)
   is
      Selected : Result_Field := No_Result_Field;
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Multipart with "multipart result depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Depth = 1 then
         if (Item.Kind = Create_Result_Kind
             and then Local_Name /= "InitiateMultipartUploadResult")
           or else (Item.Kind = Complete_Result_Kind
                    and then Local_Name /= "CompleteMultipartUploadResult")
           or else (Item.Kind = Copy_Part_Result_Kind
                    and then Local_Name /= "CopyPartResult")
         then
            raise Malformed_Multipart with "wrong multipart result root";
         end if;
      elsif Item.Depth = 2 then
         case Item.Kind is
            when Create_Result_Kind =>
               Selected :=
                 (if Local_Name = "Bucket" then Bucket_Result_Field
                  elsif Local_Name = "Key" then Key_Result_Field
                  elsif Local_Name = "UploadId" then Upload_ID_Result_Field
                  else No_Result_Field);
            when Complete_Result_Kind =>
               Selected := Complete_Field (Local_Name);
            when Copy_Part_Result_Kind =>
               Selected := Copy_Part_Field (Local_Name);
         end case;
         if Selected = No_Result_Field then
            Item.Ignore_Depth := Item.Depth;
         else
            Select_Result_Field (Item, Selected);
         end if;
      else
         raise Malformed_Multipart with "nested multipart result field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Result_Handler; Value : String) is
   begin
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field = No_Result_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   procedure Finish_Result_Field (Item : in out Result_Handler) is
   begin
      case Item.Field is
         when Bucket_Result_Field =>
            if Item.Kind = Create_Result_Kind then
               Item.Create_Value.Bucket := Item.Text_Value;
            else
               Item.Complete_Value.Bucket := Item.Text_Value;
            end if;
         when Key_Result_Field =>
            if Item.Kind = Create_Result_Kind then
               Item.Create_Value.Key := Item.Text_Value;
            else
               Item.Complete_Value.Key := Item.Text_Value;
            end if;
         when Upload_ID_Result_Field =>
            Item.Create_Value.Upload_ID := Item.Text_Value;
         when Location_Result_Field =>
            Item.Complete_Value.Location := Item.Text_Value;
         when Entity_Tag_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Entity_Tag := Item.Text_Value;
            else
               Item.Copy_Part_Value.Entity_Tag := Item.Text_Value;
            end if;
         when Last_Modified_Result_Field =>
            Item.Copy_Part_Value.Last_Modified := Item.Text_Value;
         when CRC32_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_CRC32 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_CRC32 := Item.Text_Value;
            end if;
         when CRC32C_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_CRC32C := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_CRC32C := Item.Text_Value;
            end if;
         when CRC64NVME_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_CRC64NVME := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_CRC64NVME := Item.Text_Value;
            end if;
         when SHA1_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_SHA1 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_SHA1 := Item.Text_Value;
            end if;
         when SHA256_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_SHA256 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_SHA256 := Item.Text_Value;
            end if;
         when SHA512_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_SHA512 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_SHA512 := Item.Text_Value;
            end if;
         when MD5_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_MD5 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_MD5 := Item.Text_Value;
            end if;
         when XXHASH64_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_XXHASH64 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_XXHASH64 := Item.Text_Value;
            end if;
         when XXHASH3_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_XXHASH3 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_XXHASH3 := Item.Text_Value;
            end if;
         when XXHASH128_Result_Field =>
            if Item.Kind = Complete_Result_Kind then
               Item.Complete_Value.Checksum_XXHASH128 := Item.Text_Value;
            else
               Item.Copy_Part_Value.Checksum_XXHASH128 := Item.Text_Value;
            end if;
         when Checksum_Type_Result_Field =>
            Item.Complete_Value.Checksum_Type := Item.Text_Value;
         when No_Result_Field =>
            null;
      end case;
      Item.Field := No_Result_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Result_Field;

   overriding procedure End_Element
     (Item : in out Result_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Multipart with "multipart result stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Result_Field then
         Finish_Result_Field (Item);
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
         raise Malformed_Multipart with "invalid multipart result checksum";
      end if;
   end Validate_Checksum;

   procedure Validate (Value : Complete_Multipart_Upload_Result) is
      Kind : constant String := US.To_String (Value.Checksum_Type);
   begin
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
         raise Malformed_Multipart with "invalid multipart checksum type";
      end if;
   end Validate;

   procedure Validate (Value : Copy_Part_Result) is
   begin
      if US.Length (Value.Entity_Tag) = 0
        or else US.Length (Value.Last_Modified) = 0
      then
         raise Malformed_Multipart with "incomplete copy part result";
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
   end Validate;

   function Parse_Create_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Create_Multipart_Upload_Result
   is
      Handler : aliased Result_Handler (Create_Result_Kind);
   begin
      XML.Parse (Document, Handler, Limits);
      if US.Length (Handler.Create_Value.Bucket) = 0
        or else US.Length (Handler.Create_Value.Key) = 0
        or else US.Length (Handler.Create_Value.Upload_ID) = 0
      then
         raise Malformed_Multipart with
           "incomplete create multipart result";
      end if;
      return Handler.Create_Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Multipart with "malformed create multipart result";
   end Parse_Create_Result;

   function Parse_Complete_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Complete_Multipart_Upload_Result
   is
      Handler : aliased Result_Handler (Complete_Result_Kind);
   begin
      XML.Parse (Document, Handler, Limits);
      if US.Length (Handler.Complete_Value.Bucket) = 0
        or else US.Length (Handler.Complete_Value.Key) = 0
        or else US.Length (Handler.Complete_Value.Entity_Tag) = 0
      then
         raise Malformed_Multipart with
           "incomplete complete multipart result";
      end if;
      Validate (Handler.Complete_Value);
      return Handler.Complete_Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Multipart with "malformed complete multipart result";
   end Parse_Complete_Result;

   function Parse_Copy_Part_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Copy_Part_Result
   is
      Handler : aliased Result_Handler (Copy_Part_Result_Kind);
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Copy_Part_Value);
      return Handler.Copy_Part_Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Multipart with "malformed copy part result";
   end Parse_Copy_Part_Result;

   function Result_Document (Root, Content : String) return String is
     ("<?xml version=""1.0"" encoding=""UTF-8""?>" &
      "<" & Root & " xmlns=""http://s3.amazonaws.com/doc/2006-03-01/"">" &
      Content & "</" & Root & ">");

   function Serialize_Create_Result
     (Value : Create_Multipart_Upload_Result) return String
   is
   begin
      if US.Length (Value.Bucket) = 0
        or else US.Length (Value.Key) = 0
        or else US.Length (Value.Upload_ID) = 0
      then
         raise Malformed_Multipart with
           "incomplete create multipart result";
      end if;
      return Result_Document
        ("InitiateMultipartUploadResult",
         Element ("Bucket", US.To_String (Value.Bucket)) &
         Element ("Key", US.To_String (Value.Key)) &
         Element ("UploadId", US.To_String (Value.Upload_ID)));
   end Serialize_Create_Result;

   function Serialize_Complete_Result
     (Value : Complete_Multipart_Upload_Result) return String
   is
      Content : US.Unbounded_String;
   begin
      if US.Length (Value.Bucket) = 0
        or else US.Length (Value.Key) = 0
        or else US.Length (Value.Entity_Tag) = 0
      then
         raise Malformed_Multipart with
           "incomplete complete multipart result";
      end if;
      Validate (Value);
      Append_Optional (Content, "Location", US.To_String (Value.Location));
      Append_Optional (Content, "Bucket", US.To_String (Value.Bucket));
      Append_Optional (Content, "Key", US.To_String (Value.Key));
      Append_Optional (Content, "ETag", US.To_String (Value.Entity_Tag));
      Append_Optional
        (Content, "ChecksumCRC32", US.To_String (Value.Checksum_CRC32));
      Append_Optional
        (Content, "ChecksumCRC32C", US.To_String (Value.Checksum_CRC32C));
      Append_Optional
        (Content, "ChecksumCRC64NVME",
         US.To_String (Value.Checksum_CRC64NVME));
      Append_Optional
        (Content, "ChecksumSHA1", US.To_String (Value.Checksum_SHA1));
      Append_Optional
        (Content, "ChecksumSHA256", US.To_String (Value.Checksum_SHA256));
      Append_Optional
        (Content, "ChecksumSHA512", US.To_String (Value.Checksum_SHA512));
      Append_Optional
        (Content, "ChecksumMD5", US.To_String (Value.Checksum_MD5));
      Append_Optional
        (Content, "ChecksumXXHASH64",
         US.To_String (Value.Checksum_XXHASH64));
      Append_Optional
        (Content, "ChecksumXXHASH3", US.To_String (Value.Checksum_XXHASH3));
      Append_Optional
        (Content, "ChecksumXXHASH128",
         US.To_String (Value.Checksum_XXHASH128));
      Append_Optional
        (Content, "ChecksumType", US.To_String (Value.Checksum_Type));
      return Result_Document
        ("CompleteMultipartUploadResult", US.To_String (Content));
   end Serialize_Complete_Result;

   function Serialize_Copy_Part_Result
     (Value : Copy_Part_Result) return String
   is
      Content : US.Unbounded_String;
   begin
      Validate (Value);
      Append_Optional
        (Content, "LastModified", US.To_String (Value.Last_Modified));
      Append_Optional (Content, "ETag", US.To_String (Value.Entity_Tag));
      Append_Optional
        (Content, "ChecksumCRC32", US.To_String (Value.Checksum_CRC32));
      Append_Optional
        (Content, "ChecksumCRC32C", US.To_String (Value.Checksum_CRC32C));
      Append_Optional
        (Content, "ChecksumCRC64NVME",
         US.To_String (Value.Checksum_CRC64NVME));
      Append_Optional
        (Content, "ChecksumSHA1", US.To_String (Value.Checksum_SHA1));
      Append_Optional
        (Content, "ChecksumSHA256", US.To_String (Value.Checksum_SHA256));
      Append_Optional
        (Content, "ChecksumSHA512", US.To_String (Value.Checksum_SHA512));
      Append_Optional
        (Content, "ChecksumMD5", US.To_String (Value.Checksum_MD5));
      Append_Optional
        (Content, "ChecksumXXHASH64",
         US.To_String (Value.Checksum_XXHASH64));
      Append_Optional
        (Content, "ChecksumXXHASH3", US.To_String (Value.Checksum_XXHASH3));
      Append_Optional
        (Content, "ChecksumXXHASH128",
         US.To_String (Value.Checksum_XXHASH128));
      return Result_Document ("CopyPartResult", US.To_String (Content));
   end Serialize_Copy_Part_Result;

end Flyology.Object_Storage.S3.Multipart;
