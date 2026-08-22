with Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Attributes is

   package US renames Ada.Strings.Unbounded;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;

   Maximum_Query_Length : constant := 8 * 1_024;

   function Trim_OWS (Value : String) return String is
      First : Natural := Value'First;
      Last  : Natural := Value'Last;
   begin
      while First <= Value'Last
        and then Value (First) in ' ' | Character'Val (9)
      loop
         First := First + 1;
      end loop;
      while Last >= First
        and then Value (Last) in ' ' | Character'Val (9)
      loop
         Last := Last - 1;
      end loop;
      return (if First > Last then "" else Value (First .. Last));
   end Trim_OWS;

   function Parse_Selection (Value : String) return Attribute_Selection is
      Result : Attribute_Selection;
      Count  : Natural := 1;
   begin
      if Value'Length = 0 or else Value'Length > 256 then
         raise Malformed_Attributes with "invalid object-attributes list";
      end if;
      for Item of Value loop
         if Item = ',' then
            Count := Count + 1;
         elsif Character'Pos (Item) < 32 and then Item /= Character'Val (9)
         then
            raise Malformed_Attributes with
              "control byte in object-attributes list";
         end if;
      end loop;
      if Count > 5 then
         raise Malformed_Attributes with "too many object attributes";
      end if;
      declare
         Text  : constant String (1 .. Value'Length) := Value;
         First : Positive := 1;
      begin
         for Index in 1 .. Text'Last + 1 loop
            if Index = Text'Last + 1 or else Text (Index) = ',' then
               declare
                  Name : constant String :=
                    Trim_OWS (Text (First .. Index - 1));
               begin
                  if Name = "ETag" and then not Result.Entity_Tag then
                     Result.Entity_Tag := True;
                  elsif Name = "Checksum" and then not Result.Checksum then
                     Result.Checksum := True;
                  elsif Name = "ObjectParts" and then not Result.Object_Parts
                  then
                     Result.Object_Parts := True;
                  elsif Name = "StorageClass"
                    and then not Result.Storage_Class
                  then
                     Result.Storage_Class := True;
                  elsif Name = "ObjectSize" and then not Result.Object_Size
                  then
                     Result.Object_Size := True;
                  else
                     raise Malformed_Attributes with
                       "unknown or duplicate object attribute";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      return Result;
   exception
      when Constraint_Error =>
         raise Malformed_Attributes with "invalid object-attributes list";
   end Parse_Selection;

   function Image (Value : Attribute_Selection) return String is
      Result : US.Unbounded_String;
      procedure Add (Name : String; Present : Boolean) is
      begin
         if Present then
            if US.Length (Result) > 0 then
               US.Append (Result, ",");
            end if;
            US.Append (Result, Name);
         end if;
      end Add;
   begin
      Add ("ETag", Value.Entity_Tag);
      Add ("Checksum", Value.Checksum);
      Add ("ObjectParts", Value.Object_Parts);
      Add ("StorageClass", Value.Storage_Class);
      Add ("ObjectSize", Value.Object_Size);
      if US.Length (Result) = 0 then
         raise Malformed_Attributes with "empty object-attributes list";
      end if;
      return US.To_String (Result);
   end Image;

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
               raise Malformed_Attributes with
                 "invalid attributes query percent escape";
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

   function Parse_Query (Query : String) return Attributes_Query is
      Result : Attributes_Query;
      Seen_Attributes, Seen_Version, Seen_X_ID : Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Length then
         raise Malformed_Attributes with "invalid attributes query size";
      end if;
      for Item of Query loop
         if Item = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 3 then
         raise Malformed_Attributes with
           "too many attributes query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Attributes with
                    "empty attributes query parameter";
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
                  if Name = "attributes" then
                     if Seen_Attributes or else Value'Length /= 0 then
                        raise Malformed_Attributes with
                          "invalid attributes marker";
                     end if;
                     Seen_Attributes := True;
                  elsif Name = "versionId" then
                     if Seen_Version or else Value'Length = 0
                       or else not Deletions.Valid_Version_ID (Value)
                     then
                        raise Malformed_Attributes with
                          "invalid attributes version ID";
                     end if;
                     Seen_Version := True;
                     Result.Has_Version_ID := True;
                     Result.Version_ID := US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "GetObjectAttributes" then
                        raise Malformed_Attributes with
                          "invalid attributes operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_Attributes with
                       "unsupported attributes query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      if not Seen_Attributes then
         raise Malformed_Attributes with "attributes marker is required";
      end if;
      return Result;
   exception
      when Constraint_Error =>
         raise Malformed_Attributes with "malformed attributes query";
   end Parse_Query;

   type Field_Kind is
     (No_Field,
      Entity_Tag_Field, Storage_Class_Field, Object_Size_Field,
      CRC32_Field, CRC32C_Field, CRC64NVME_Field, SHA1_Field,
      SHA256_Field, SHA512_Field, MD5_Field, XXHASH64_Field,
      XXHASH3_Field, XXHASH128_Field, Checksum_Type_Field,
      Total_Parts_Count_Field, Part_Number_Marker_Field,
      Next_Part_Number_Marker_Field, Max_Parts_Field,
      Is_Truncated_Field, Part_Number_Field, Part_Size_Field);

   type Result_Handler is new XML.Event_Handler with record
      Value       : Get_Object_Attributes_Result;
      Current     : Object_Part;
      Text_Value  : US.Unbounded_String;
      Depth       : Natural := 0;
      Ignore_Depth : Natural := 0;
      Field       : Field_Kind := No_Field;
      In_Checksum : Boolean := False;
      In_Parts    : Boolean := False;
      In_Part     : Boolean := False;
      Seen_Entity_Tag, Seen_Checksum, Seen_Object_Parts,
        Seen_Storage_Class, Seen_Object_Size : Boolean := False;
      Seen_CRC32, Seen_CRC32C, Seen_CRC64NVME, Seen_SHA1,
        Seen_SHA256, Seen_SHA512, Seen_MD5, Seen_XXHASH64,
        Seen_XXHASH3, Seen_XXHASH128, Seen_Checksum_Type : Boolean := False;
      Seen_Total, Seen_Marker, Seen_Next, Seen_Max, Seen_Truncated :
        Boolean := False;
      Part_Seen_Number, Part_Seen_Size, Part_Seen_CRC32,
        Part_Seen_CRC32C, Part_Seen_CRC64NVME, Part_Seen_SHA1,
        Part_Seen_SHA256, Part_Seen_SHA512, Part_Seen_MD5,
        Part_Seen_XXHASH64, Part_Seen_XXHASH3,
        Part_Seen_XXHASH128 : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Result_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Result_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Result_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Item of Value loop
         if Item not in ' ' | Character'Val (9) | Character'Val (10) |
           Character'Val (13)
         then
            raise Malformed_Attributes with
              "text outside object-attributes fields";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Select_Field
     (Item  : in out Result_Handler;
      Seen  : in out Boolean;
      Field : Field_Kind)
   is
   begin
      if Seen then
         raise Malformed_Attributes with
           "duplicate object-attributes field";
      end if;
      Seen := True;
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Field;

   procedure Reset_Part (Item : in out Result_Handler) is
   begin
      Item.Current := (others => <>);
      Item.Part_Seen_Number := False;
      Item.Part_Seen_Size := False;
      Item.Part_Seen_CRC32 := False;
      Item.Part_Seen_CRC32C := False;
      Item.Part_Seen_CRC64NVME := False;
      Item.Part_Seen_SHA1 := False;
      Item.Part_Seen_SHA256 := False;
      Item.Part_Seen_SHA512 := False;
      Item.Part_Seen_MD5 := False;
      Item.Part_Seen_XXHASH64 := False;
      Item.Part_Seen_XXHASH3 := False;
      Item.Part_Seen_XXHASH128 := False;
      Item.In_Part := True;
   end Reset_Part;

   procedure Select_Checksum_Field
     (Item : in out Result_Handler; Local_Name : String; In_Part : Boolean)
   is
   begin
      if Local_Name = "ChecksumCRC32" then
         if In_Part then
            Select_Field
              (Item, Item.Part_Seen_CRC32, CRC32_Field);
         else
            Select_Field (Item, Item.Seen_CRC32, CRC32_Field);
         end if;
      elsif Local_Name = "ChecksumCRC32C" then
         if In_Part then
            Select_Field
              (Item, Item.Part_Seen_CRC32C, CRC32C_Field);
         else
            Select_Field (Item, Item.Seen_CRC32C, CRC32C_Field);
         end if;
      elsif Local_Name = "ChecksumCRC64NVME" then
         if In_Part then
            Select_Field
              (Item, Item.Part_Seen_CRC64NVME, CRC64NVME_Field);
         else
            Select_Field
              (Item, Item.Seen_CRC64NVME, CRC64NVME_Field);
         end if;
      elsif Local_Name = "ChecksumSHA1" then
         if In_Part then
            Select_Field (Item, Item.Part_Seen_SHA1, SHA1_Field);
         else
            Select_Field (Item, Item.Seen_SHA1, SHA1_Field);
         end if;
      elsif Local_Name = "ChecksumSHA256" then
         if In_Part then
            Select_Field (Item, Item.Part_Seen_SHA256, SHA256_Field);
         else
            Select_Field (Item, Item.Seen_SHA256, SHA256_Field);
         end if;
      elsif Local_Name = "ChecksumSHA512" then
         if In_Part then
            Select_Field (Item, Item.Part_Seen_SHA512, SHA512_Field);
         else
            Select_Field (Item, Item.Seen_SHA512, SHA512_Field);
         end if;
      elsif Local_Name = "ChecksumMD5" then
         if In_Part then
            Select_Field (Item, Item.Part_Seen_MD5, MD5_Field);
         else
            Select_Field (Item, Item.Seen_MD5, MD5_Field);
         end if;
      elsif Local_Name = "ChecksumXXHASH64" then
         if In_Part then
            Select_Field (Item, Item.Part_Seen_XXHASH64, XXHASH64_Field);
         else
            Select_Field (Item, Item.Seen_XXHASH64, XXHASH64_Field);
         end if;
      elsif Local_Name = "ChecksumXXHASH3" then
         if In_Part then
            Select_Field (Item, Item.Part_Seen_XXHASH3, XXHASH3_Field);
         else
            Select_Field (Item, Item.Seen_XXHASH3, XXHASH3_Field);
         end if;
      elsif Local_Name = "ChecksumXXHASH128" then
         if In_Part then
            Select_Field
              (Item, Item.Part_Seen_XXHASH128, XXHASH128_Field);
         else
            Select_Field (Item, Item.Seen_XXHASH128, XXHASH128_Field);
         end if;
      elsif not In_Part and then Local_Name = "ChecksumType" then
         Select_Field
           (Item, Item.Seen_Checksum_Type, Checksum_Type_Field);
      else
         Item.Ignore_Depth := Item.Depth;
      end if;
   end Select_Checksum_Field;

   overriding procedure Start_Element
     (Item : in out Result_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Attributes with "attributes XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      end if;
      if Item.Depth = 1 then
         if Local_Name /= "GetObjectAttributesResponse" then
            raise Malformed_Attributes with
              "wrong object-attributes response root";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "ETag" then
            Select_Field
              (Item, Item.Seen_Entity_Tag, Entity_Tag_Field);
            Item.Value.Has_Entity_Tag := True;
         elsif Local_Name = "Checksum" then
            if Item.Seen_Checksum then
               raise Malformed_Attributes with "duplicate Checksum";
            end if;
            Item.Seen_Checksum := True;
            Item.Value.Has_Checksum := True;
            Item.In_Checksum := True;
         elsif Local_Name = "ObjectParts" then
            if Item.Seen_Object_Parts then
               raise Malformed_Attributes with "duplicate ObjectParts";
            end if;
            Item.Seen_Object_Parts := True;
            Item.Value.Has_Object_Parts := True;
            Item.In_Parts := True;
         elsif Local_Name = "StorageClass" then
            Select_Field
              (Item, Item.Seen_Storage_Class, Storage_Class_Field);
            Item.Value.Has_Storage_Class := True;
         elsif Local_Name = "ObjectSize" then
            Select_Field
              (Item, Item.Seen_Object_Size, Object_Size_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.In_Checksum then
         Select_Checksum_Field (Item, Local_Name, False);
      elsif Item.Depth = 3 and then Item.In_Parts then
         if Local_Name = "PartsCount" then
            Select_Field
              (Item, Item.Seen_Total, Total_Parts_Count_Field);
         elsif Local_Name = "PartNumberMarker" then
            Select_Field
              (Item, Item.Seen_Marker, Part_Number_Marker_Field);
         elsif Local_Name = "NextPartNumberMarker" then
            Select_Field
              (Item, Item.Seen_Next, Next_Part_Number_Marker_Field);
         elsif Local_Name = "MaxParts" then
            Select_Field (Item, Item.Seen_Max, Max_Parts_Field);
         elsif Local_Name = "IsTruncated" then
            Select_Field
              (Item, Item.Seen_Truncated, Is_Truncated_Field);
         elsif Local_Name = "Part" then
            if Item.Value.Object_Parts.Parts.Length >=
              Ada.Containers.Count_Type (Core.Part_Number'Last)
            then
               raise Malformed_Attributes with
                 "too many object attribute parts";
            end if;
            Reset_Part (Item);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 4 and then Item.In_Part then
         if Local_Name = "PartNumber" then
            Select_Field
              (Item, Item.Part_Seen_Number, Part_Number_Field);
         elsif Local_Name = "Size" then
            Select_Field (Item, Item.Part_Seen_Size, Part_Size_Field);
         else
            Select_Checksum_Field (Item, Local_Name, True);
         end if;
      else
         raise Malformed_Attributes with "nested object-attributes field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Result_Handler; Value : String) is
   begin
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field = No_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   procedure Set_Checksum
     (Item : in out Result_Handler;
      Field : Field_Kind;
      Value : US.Unbounded_String)
   is
      Target : Checksum_Values :=
        (if Item.In_Part then Item.Current.Checksums
         else Item.Value.Checksum);
   begin
      case Field is
         when CRC32_Field => Target.CRC32 := Value;
         when CRC32C_Field => Target.CRC32C := Value;
         when CRC64NVME_Field => Target.CRC64NVME := Value;
         when SHA1_Field => Target.SHA1 := Value;
         when SHA256_Field => Target.SHA256 := Value;
         when SHA512_Field => Target.SHA512 := Value;
         when MD5_Field => Target.MD5 := Value;
         when XXHASH64_Field => Target.XXHASH64 := Value;
         when XXHASH3_Field => Target.XXHASH3 := Value;
         when XXHASH128_Field => Target.XXHASH128 := Value;
         when Checksum_Type_Field => Target.Kind := Value;
         when others => null;
      end case;
      if Item.In_Part then
         Item.Current.Checksums := Target;
      else
         Item.Value.Checksum := Target;
      end if;
   end Set_Checksum;

   procedure Finish_Field (Item : in out Result_Handler) is
      Text : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Field is
         when Entity_Tag_Field =>
            if Text'Length = 0 then
               raise Malformed_Attributes with "empty ETag";
            end if;
            Item.Value.Entity_Tag := Item.Text_Value;
         when Storage_Class_Field =>
            Item.Value.Storage_Class := Item.Text_Value;
         when Object_Size_Field | Part_Size_Field =>
            declare
               Parsed : constant Wire_Core.Byte_Count_Result :=
                 Wire_Core.Parse_Byte_Count (Text);
            begin
               if not Parsed.Valid then
                  raise Malformed_Attributes with "invalid object size";
               end if;
               if Item.Field = Object_Size_Field then
                  Item.Value.Object_Size :=
                    (Is_Set => True, Value => Parsed.Value);
               else
                  Item.Current.Size :=
                    (Is_Set => True, Value => Parsed.Value);
               end if;
            end;
         when Total_Parts_Count_Field | Part_Number_Marker_Field |
              Next_Part_Number_Marker_Field | Max_Parts_Field |
              Part_Number_Field =>
            declare
               Parsed : constant Wire_Core.Natural_Result :=
                 Wire_Core.Parse_Natural (Text);
               Optional : Optional_Natural;
            begin
               if not Parsed.Valid
                 or else
                   (Item.Field = Part_Number_Field
                    and then Parsed.Value not in Core.Part_Number'Range)
                 or else
                   (Item.Field /= Max_Parts_Field
                    and then Item.Field /= Total_Parts_Count_Field
                    and then Item.Field /= Part_Number_Field
                    and then Parsed.Value > Part_Marker_Value'Last)
                 or else
                   (Item.Field = Max_Parts_Field
                    and then Parsed.Value > Core.Page_Size'Last)
                 or else
                   (Item.Field = Total_Parts_Count_Field
                    and then Parsed.Value > Core.Part_Number'Last)
               then
                  raise Malformed_Attributes with
                    "invalid object part scalar";
               end if;
               Optional := (Is_Set => True, Value => Parsed.Value);
               case Item.Field is
                  when Total_Parts_Count_Field =>
                     Item.Value.Object_Parts.Total_Parts_Count := Optional;
                  when Part_Number_Marker_Field =>
                     Item.Value.Object_Parts.Part_Number_Marker := Optional;
                  when Next_Part_Number_Marker_Field =>
                     Item.Value.Object_Parts.Next_Part_Number_Marker :=
                       Optional;
                  when Max_Parts_Field =>
                     Item.Value.Object_Parts.Max_Parts := Optional;
                  when Part_Number_Field =>
                     Item.Current.Number := Optional;
                  when others => null;
               end case;
            end;
         when Is_Truncated_Field =>
            declare
               Parsed : constant Wire_Core.Boolean_Result :=
                 Wire_Core.Parse_Boolean (Text);
            begin
               if not Parsed.Valid then
                  raise Malformed_Attributes with
                    "invalid object-parts truncation flag";
               end if;
               Item.Value.Object_Parts.Has_Is_Truncated := True;
               Item.Value.Object_Parts.Is_Truncated := Parsed.Value;
            end;
         when CRC32_Field | CRC32C_Field | CRC64NVME_Field | SHA1_Field |
              SHA256_Field | SHA512_Field | MD5_Field | XXHASH64_Field |
              XXHASH3_Field | XXHASH128_Field | Checksum_Type_Field =>
            Set_Checksum (Item, Item.Field, Item.Text_Value);
         when No_Field => null;
      end case;
      Item.Field := No_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Field;

   overriding procedure End_Element
     (Item : in out Result_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Attributes with "attributes XML stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         Finish_Field (Item);
      elsif Item.Depth = 3 and then Item.In_Part then
         Item.Value.Object_Parts.Parts.Append (Item.Current);
         Item.In_Part := False;
      elsif Item.Depth = 2 and then Item.In_Checksum then
         Item.In_Checksum := False;
      elsif Item.Depth = 2 and then Item.In_Parts then
         Item.In_Parts := False;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Valid_Checksum
     (Value : US.Unbounded_String; Bytes : Positive) return Boolean is
     (US.Length (Value) = 0
      or else Wire_Core.Valid_Base64 (US.To_String (Value), Bytes));

   function Valid_Checksums (Value : Checksum_Values) return Boolean is
      Kind : constant String := US.To_String (Value.Kind);
   begin
      return Valid_Checksum (Value.CRC32, 4)
        and then Valid_Checksum (Value.CRC32C, 4)
        and then Valid_Checksum (Value.CRC64NVME, 8)
        and then Valid_Checksum (Value.SHA1, 20)
        and then Valid_Checksum (Value.SHA256, 32)
        and then Valid_Checksum (Value.SHA512, 64)
        and then Valid_Checksum (Value.MD5, 16)
        and then Valid_Checksum (Value.XXHASH64, 8)
        and then Valid_Checksum (Value.XXHASH3, 8)
        and then Valid_Checksum (Value.XXHASH128, 16)
        and then (Kind'Length = 0 or else Kind in "COMPOSITE" | "FULL_OBJECT");
   end Valid_Checksums;

   function Valid_Storage_Class (Value : String) return Boolean is
     (Value in "STANDARD" | "REDUCED_REDUNDANCY" | "STANDARD_IA" |
       "ONEZONE_IA" | "INTELLIGENT_TIERING" | "GLACIER" |
       "DEEP_ARCHIVE" | "OUTPOSTS" | "GLACIER_IR" | "SNOW" |
       "EXPRESS_ONEZONE" | "FSX_OPENZFS" | "FSX_ONTAP");

   procedure Validate (Value : Get_Object_Attributes_Result) is
      Previous : Natural := 0;
   begin
      if Value.Has_Entity_Tag and then US.Length (Value.Entity_Tag) = 0
      then
         raise Malformed_Attributes with "empty object-attributes ETag";
      elsif Value.Has_Checksum and then not Valid_Checksums (Value.Checksum)
      then
         raise Malformed_Attributes with "invalid object checksum";
      elsif Value.Has_Storage_Class
        and then not Valid_Storage_Class (US.To_String (Value.Storage_Class))
      then
         raise Malformed_Attributes with "invalid storage class";
      end if;
      if Value.Has_Object_Parts then
         if Value.Object_Parts.Total_Parts_Count.Is_Set
           and then Value.Object_Parts.Total_Parts_Count.Value >
             Core.Part_Number'Last
         then
            raise Malformed_Attributes with "invalid total part count";
         elsif Value.Object_Parts.Max_Parts.Is_Set
           and then Value.Object_Parts.Max_Parts.Value >
             Core.Page_Size'Last
         then
            raise Malformed_Attributes with "invalid max parts";
         end if;
         for Part of Value.Object_Parts.Parts loop
            if not Part.Number.Is_Set
              or else Part.Number.Value not in Core.Part_Number'Range
              or else not Part.Size.Is_Set
              or else not Valid_Checksums (Part.Checksums)
              or else Part.Number.Value <= Previous
            then
               raise Malformed_Attributes with "invalid object part";
            end if;
            Previous := Part.Number.Value;
         end loop;
         if Value.Object_Parts.Total_Parts_Count.Is_Set
           and then Value.Object_Parts.Total_Parts_Count.Value <
             Natural (Value.Object_Parts.Parts.Length)
         then
            raise Malformed_Attributes with
              "object parts exceed total part count";
         end if;
      end if;
   end Validate;

   function Parse_Result
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Get_Object_Attributes_Result
   is
      Handler : aliased Result_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Attributes with
           "malformed GetObjectAttributes XML";
   end Parse_Result;

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Natural_Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Byte_Count_Image (Value : Byte_Count) return String is
     (Ada.Strings.Fixed.Trim (Byte_Count'Image (Value), Ada.Strings.Both));

   procedure Append_Optional
     (Target : in out US.Unbounded_String; Name : String;
      Value : US.Unbounded_String) is
   begin
      if US.Length (Value) > 0 then
         US.Append (Target, Element (Name, US.To_String (Value)));
      end if;
   end Append_Optional;

   procedure Append_Checksums
     (Target : in out US.Unbounded_String; Value : Checksum_Values;
      Include_Type : Boolean) is
   begin
      Append_Optional (Target, "ChecksumCRC32", Value.CRC32);
      Append_Optional (Target, "ChecksumCRC32C", Value.CRC32C);
      Append_Optional (Target, "ChecksumCRC64NVME", Value.CRC64NVME);
      Append_Optional (Target, "ChecksumSHA1", Value.SHA1);
      Append_Optional (Target, "ChecksumSHA256", Value.SHA256);
      Append_Optional (Target, "ChecksumSHA512", Value.SHA512);
      Append_Optional (Target, "ChecksumMD5", Value.MD5);
      Append_Optional (Target, "ChecksumXXHASH64", Value.XXHASH64);
      Append_Optional (Target, "ChecksumXXHASH3", Value.XXHASH3);
      Append_Optional (Target, "ChecksumXXHASH128", Value.XXHASH128);
      if Include_Type then
         Append_Optional (Target, "ChecksumType", Value.Kind);
      end if;
   end Append_Checksums;

   procedure Append_Optional_Natural
     (Target : in out US.Unbounded_String; Name : String;
      Value : Optional_Natural) is
   begin
      if Value.Is_Set then
         US.Append (Target, Element (Name, Natural_Image (Value.Value)));
      end if;
   end Append_Optional_Natural;

   function Serialize_Result
     (Value : Get_Object_Attributes_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<GetObjectAttributesResponse xmlns=""http://s3.amazonaws.com/" &
         "doc/2006-03-01/"">");
      if Value.Has_Entity_Tag then
         US.Append
           (Result, Element ("ETag", US.To_String (Value.Entity_Tag)));
      end if;
      if Value.Has_Checksum then
         US.Append (Result, "<Checksum>");
         Append_Checksums (Result, Value.Checksum, True);
         US.Append (Result, "</Checksum>");
      end if;
      if Value.Has_Object_Parts then
         US.Append (Result, "<ObjectParts>");
         Append_Optional_Natural
           (Result, "PartsCount",
            Value.Object_Parts.Total_Parts_Count);
         Append_Optional_Natural
           (Result, "PartNumberMarker",
            Value.Object_Parts.Part_Number_Marker);
         Append_Optional_Natural
           (Result, "NextPartNumberMarker",
            Value.Object_Parts.Next_Part_Number_Marker);
         Append_Optional_Natural
           (Result, "MaxParts", Value.Object_Parts.Max_Parts);
         if Value.Object_Parts.Has_Is_Truncated then
            US.Append
              (Result,
               Element
                 ("IsTruncated",
                  (if Value.Object_Parts.Is_Truncated
                   then "true" else "false")));
         end if;
         for Part of Value.Object_Parts.Parts loop
            US.Append (Result, "<Part>");
            Append_Checksums (Result, Part.Checksums, False);
            US.Append
              (Result,
               Element ("PartNumber", Natural_Image (Part.Number.Value)) &
               Element ("Size", Byte_Count_Image (Part.Size.Value)) &
               "</Part>");
         end loop;
         US.Append (Result, "</ObjectParts>");
      end if;
      if Value.Has_Storage_Class then
         US.Append
           (Result,
            Element
              ("StorageClass", US.To_String (Value.Storage_Class)));
      end if;
      if Value.Object_Size.Is_Set then
         US.Append
           (Result,
            Element
              ("ObjectSize", Byte_Count_Image (Value.Object_Size.Value)));
      end if;
      US.Append (Result, "</GetObjectAttributesResponse>");
      return US.To_String (Result);
   end Serialize_Result;

end Flyology.Object_Storage.S3.Attributes;
