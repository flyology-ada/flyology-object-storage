with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Versions is

   package US renames Ada.Strings.Unbounded;
   package Model renames Flyology.Object_Storage.S3.Model;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;
   use type Model.Shape_Kind;
   use type US.Unbounded_String;

   --  This request-target bound matches the established S3 listing parsers;
   --  larger queries are rejected before allocation or field projection.
   Maximum_Query_Bytes : constant Natural := 8 * 1_024;
   --  The pinned ListObjectVersions input has eight distinct query members,
   --  including its required `versions` marker and optional SDK operation ID.
   Maximum_Query_Members : constant Positive := 8;

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 16);

   function Decode_Component (Value : String) return String is
      Result : String (1 .. Value'Length);
      Input  : Natural := 1;
      Output : Natural := 0;
      Raw    : constant String (1 .. Value'Length) := Value;
   begin
      while Input <= Raw'Length loop
         Output := Output + 1;
         if Raw (Input) = '%' then
            if Input + 2 > Raw'Length
              or else Hex_Value (Raw (Input + 1)) > 15
              or else Hex_Value (Raw (Input + 2)) > 15
            then
               raise Malformed_Version_Request with
                 "invalid ListObjectVersions percent escape";
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

   function Parse_List_Object_Versions_Query
     (Query : String) return List_Object_Versions_Request
   is
      Result : List_Object_Versions_Request;
      Seen_Versions, Seen_Delimiter, Seen_Encoding, Seen_Key : Boolean :=
        False;
      Seen_Maximum, Seen_Prefix, Seen_Version, Seen_X_ID : Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Bytes then
         raise Malformed_Version_Request with
           "invalid ListObjectVersions query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > Maximum_Query_Members then
         raise Malformed_Version_Request with
           "too many ListObjectVersions query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Version_Request with
                    "empty ListObjectVersions query parameter";
               end if;
               declare
                  Pair_Text : constant String := Raw (First .. Index - 1);
                  Equals : constant Natural :=
                    Ada.Strings.Fixed.Index (Pair_Text, "=");
                  Name : constant String :=
                    (if Equals = 0 then Pair_Text
                     elsif Equals = Pair_Text'First then ""
                     else Pair_Text (Pair_Text'First .. Equals - 1));
                  Value : constant String := Decode_Component
                    ((if Equals = 0 or else Equals = Pair_Text'Last then ""
                      else Pair_Text (Equals + 1 .. Pair_Text'Last)));
                  Number : Wire_Core.Natural_Result;
               begin
                  if Name = "versions" then
                     if Seen_Versions or else Value'Length /= 0 then
                        raise Malformed_Version_Request with
                          "invalid ListObjectVersions marker";
                     end if;
                     Seen_Versions := True;
                  elsif Name = "delimiter" then
                     if Seen_Delimiter then
                        raise Malformed_Version_Request with
                          "duplicate ListObjectVersions delimiter";
                     end if;
                     Seen_Delimiter := True;
                     Result.Has_Delimiter := True;
                     Result.Delimiter := US.To_Unbounded_String (Value);
                  elsif Name = "encoding-type" then
                     if Seen_Encoding or else Value /= "url" then
                        raise Malformed_Version_Request with
                          "invalid ListObjectVersions encoding-type";
                     end if;
                     Seen_Encoding := True;
                     Result.URL_Encoding := True;
                  elsif Name = "key-marker" then
                     if Seen_Key then
                        raise Malformed_Version_Request with
                          "duplicate ListObjectVersions key marker";
                     end if;
                     Seen_Key := True;
                     Result.Has_Key_Marker := True;
                     Result.Key_Marker := US.To_Unbounded_String (Value);
                  elsif Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Maximum or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_Version_Request with
                          "invalid ListObjectVersions max-keys";
                     end if;
                     Seen_Maximum := True;
                     Result.Has_Max_Keys := True;
                     Result.Max_Keys := Core.Page_Size (Number.Value);
                  elsif Name = "prefix" then
                     if Seen_Prefix then
                        raise Malformed_Version_Request with
                          "duplicate ListObjectVersions prefix";
                     end if;
                     Seen_Prefix := True;
                     Result.Has_Prefix := True;
                     Result.Prefix := US.To_Unbounded_String (Value);
                  elsif Name = "version-id-marker" then
                     if Seen_Version then
                        raise Malformed_Version_Request with
                          "duplicate ListObjectVersions version marker";
                     end if;
                     Seen_Version := True;
                     Result.Has_Version_ID_Marker := True;
                     Result.Version_ID_Marker :=
                       US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "ListObjectVersions" then
                        raise Malformed_Version_Request with
                          "invalid ListObjectVersions operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_Version_Request with
                       "unsupported ListObjectVersions query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      if not Seen_Versions then
         raise Malformed_Version_Request with
           "ListObjectVersions query lacks versions marker";
      elsif Result.Has_Version_ID_Marker and then not Result.Has_Key_Marker
      then
         raise Malformed_Version_Request with
           "ListObjectVersions version marker lacks key marker";
      end if;
      return Result;
   end Parse_List_Object_Versions_Query;

   type Context_Kind is
     (Root_Context, Version_Context, Delete_Marker_Context, Prefix_Context);
   type Subcontext_Kind is
     (No_Subcontext, Owner_Subcontext, Restore_Subcontext);
   type Field_Kind is
     (No_Field,
      Is_Truncated_Field,
      Key_Marker_Field,
      Version_ID_Marker_Field,
      Next_Key_Marker_Field,
      Next_Version_ID_Marker_Field,
      Name_Field,
      Prefix_Field,
      Delimiter_Field,
      Max_Keys_Field,
      Encoding_Type_Field,
      Entity_Tag_Field,
      Checksum_Algorithm_Field,
      Checksum_Type_Field,
      Size_Field,
      Storage_Class_Field,
      Object_Key_Field,
      Object_Version_ID_Field,
      Object_Is_Latest_Field,
      Object_Last_Modified_Field,
      Owner_Display_Name_Field,
      Owner_ID_Field,
      Restore_In_Progress_Field,
      Restore_Expiry_Date_Field,
      Common_Prefix_Field);

   type Top_Field_Seen_Array is
     array (Is_Truncated_Field .. Encoding_Type_Field) of Boolean;
   type Version_Field_Seen_Array is
     array (Entity_Tag_Field .. Object_Last_Modified_Field) of Boolean;

   type Version_Listing_Handler is new XML.Event_Handler with record
      Value                  : List_Object_Versions_Result;
      Current_Version        : Object_Version;
      Current_Delete_Marker  : Delete_Marker;
      Current_Prefix         : US.Unbounded_String;
      Text_Value             : US.Unbounded_String;
      Depth                  : Natural := 0;
      Root_Seen              : Boolean := False;
      Root_Closed            : Boolean := False;
      Context                : Context_Kind := Root_Context;
      Subcontext             : Subcontext_Kind := No_Subcontext;
      Field                  : Field_Kind := No_Field;
      Seen_Top               : Top_Field_Seen_Array := (others => False);
      Seen_Version           : Version_Field_Seen_Array :=
        (others => False);
      Seen_Delete_Key        : Boolean := False;
      Seen_Delete_Version_ID : Boolean := False;
      Seen_Delete_Is_Latest  : Boolean := False;
      Seen_Delete_Modified   : Boolean := False;
      Seen_Owner_Display     : Boolean := False;
      Seen_Owner_ID          : Boolean := False;
      Seen_Restore_Progress  : Boolean := False;
      Seen_Restore_Expiry    : Boolean := False;
      Seen_Common_Prefix     : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Version_Listing_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Version_Listing_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Version_Listing_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Version_Listing_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Version_Listing with
              "text outside ListObjectVersions fields";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Version_Listing_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      pragma Unreferenced (Item);
   begin
      if Namespace_URI not in
        "" | "http://s3.amazonaws.com/doc/2006-03-01/"
        or else Attribute_Count /= 0
      then
         raise Malformed_Version_Listing with
           "ListObjectVersions namespace or attributes are invalid";
      end if;
   end Start_Element_Details;

   procedure Select_Field
     (Item  : in out Version_Listing_Handler;
      Seen  : in out Boolean;
      Field : Field_Kind)
   is
   begin
      if Seen or else Item.Field /= No_Field then
         raise Malformed_Version_Listing with
           "duplicate ListObjectVersions field";
      end if;
      Seen := True;
      Item.Field := Field;
      Item.Text_Value := US.Null_Unbounded_String;
   end Select_Field;

   procedure Select_Checksum_Algorithm
     (Item : in out Version_Listing_Handler) is
   begin
      if Item.Field /= No_Field then
         raise Malformed_Version_Listing with
           "nested ListObjectVersions scalar";
      end if;
      Item.Field := Checksum_Algorithm_Field;
      Item.Text_Value := US.Null_Unbounded_String;
   end Select_Checksum_Algorithm;

   function Parse_Boolean (Value : String) return Boolean is
      Result : constant Wire_Core.Boolean_Result :=
        Wire_Core.Parse_Boolean (Value);
   begin
      if not Result.Valid then
         raise Malformed_Version_Listing with
           "invalid ListObjectVersions boolean";
      end if;
      return Result.Value;
   end Parse_Boolean;

   function Parse_Byte_Count (Value : String) return Byte_Count is
      Result : constant Wire_Core.Byte_Count_Result :=
        Wire_Core.Parse_Byte_Count (Value);
   begin
      if not Result.Valid then
         raise Malformed_Version_Listing with
           "invalid ListObjectVersions object size";
      end if;
      return Result.Value;
   end Parse_Byte_Count;

   function Parse_Page_Size (Value : String) return Core.Page_Size is
      Result : constant Wire_Core.Natural_Result :=
        Wire_Core.Parse_Natural (Value);
   begin
      if not Result.Valid or else Result.Value > Core.Page_Size'Last then
         raise Malformed_Version_Listing with
           "invalid ListObjectVersions MaxKeys";
      end if;
      return Core.Page_Size (Result.Value);
   end Parse_Page_Size;

   function Output_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.List_Object_Versions_Operation));
   begin
      return Model.Member_Shape (Output, Member);
   end Output_Member_Shape;

   function Version_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Version_List : constant Model.Shape_Index := Output_Member_Shape (6);
      Version_Shape : constant Model.Shape_Index := Model.Shape_Index
        (Model.List_Member_Shape (Version_List));
   begin
      return Model.Member_Shape (Version_Shape, Member);
   end Version_Member_Shape;

   function Valid_Enumeration
     (Value : String; Shape : Model.Shape_Index) return Boolean
   is
      Scalar : constant Model.Shape_Index :=
        (if Model.Kind (Shape) = Model.List_Shape
         then Model.Shape_Index (Model.List_Member_Shape (Shape))
         else Shape);
   begin
      if Model.Enumeration_Count (Scalar) = 0 then
         return False;
      end if;
      for Index in 1 .. Model.Enumeration_Count (Scalar) loop
         if Model.Enumeration_Value (Scalar, Index) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Valid_Enumeration;

   function Has_Checksum_Algorithm
     (Item : Object_Version; Value : String) return Boolean is
   begin
      for Algorithm of Item.Checksum_Algorithms loop
         if US.To_String (Algorithm) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Has_Checksum_Algorithm;

   function Valid_ISO_8601_Timestamp (Value : String) return Boolean is
      Text : constant String (1 .. Value'Length) := Value;

      function Decimal (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               return Natural'Last;
            end if;
            Result := Result * 10 +
              Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Decimal;

      Year, Month, Day, Hour, Minute, Second : Natural;
      Zone : Positive := 20;
      Maximum_Day : Natural;
   begin
      if Text'Length not in 20 .. 35
        or else Text (5) /= '-'
        or else Text (8) /= '-'
        or else Text (11) /= 'T'
        or else Text (14) /= ':'
        or else Text (17) /= ':'
      then
         return False;
      end if;
      Year := Decimal (1, 4);
      Month := Decimal (6, 7);
      Day := Decimal (9, 10);
      Hour := Decimal (12, 13);
      Minute := Decimal (15, 16);
      Second := Decimal (18, 19);
      if Year not in 1 .. 9_999
        or else Month not in 1 .. 12
        or else Hour > 23
        or else Minute > 59
        or else Second > 59
      then
         return False;
      end if;
      Maximum_Day :=
        (case Month is
            when 2 =>
              (if Year mod 400 = 0
                 or else (Year mod 4 = 0 and then Year mod 100 /= 0)
               then 29 else 28),
            when 4 | 6 | 9 | 11 => 30,
            when others => 31);
      if Day not in 1 .. Maximum_Day then
         return False;
      end if;
      if Text (Zone) = '.' then
         Zone := Zone + 1;
         declare
            First_Fraction : constant Positive := Zone;
         begin
            while Zone <= Text'Last and then Text (Zone) in '0' .. '9' loop
               Zone := Zone + 1;
            end loop;
            if Zone = First_Fraction or else Zone - First_Fraction > 9 then
               return False;
            end if;
         end;
      end if;
      if Zone = Text'Last and then Text (Zone) = 'Z' then
         return True;
      elsif Zone + 5 = Text'Last
        and then Text (Zone) in '+' | '-'
        and then Text (Zone + 3) = ':'
      then
         declare
            Offset_Hour : constant Natural := Decimal (Zone + 1, Zone + 2);
            Offset_Minute : constant Natural := Decimal (Zone + 4, Zone + 5);
         begin
            return Offset_Hour <= 23 and then Offset_Minute <= 59;
         end;
      end if;
      return False;
   end Valid_ISO_8601_Timestamp;

   procedure Reset_Identity_Seen (Item : in out Version_Listing_Handler) is
   begin
      Item.Seen_Owner_Display := False;
      Item.Seen_Owner_ID := False;
   end Reset_Identity_Seen;

   procedure Start_Version (Item : in out Version_Listing_Handler) is
   begin
      if Item.Context /= Root_Context then
         raise Malformed_Version_Listing with
           "nested ListObjectVersions entry";
      end if;
      Item.Context := Version_Context;
      Item.Subcontext := No_Subcontext;
      Item.Current_Version := (others => <>);
      Item.Seen_Version := (others => False);
      Reset_Identity_Seen (Item);
      Item.Seen_Restore_Progress := False;
      Item.Seen_Restore_Expiry := False;
   end Start_Version;

   procedure Start_Delete_Marker
     (Item : in out Version_Listing_Handler) is
   begin
      if Item.Context /= Root_Context then
         raise Malformed_Version_Listing with
           "nested ListObjectVersions delete marker";
      end if;
      Item.Context := Delete_Marker_Context;
      Item.Subcontext := No_Subcontext;
      Item.Current_Delete_Marker := (others => <>);
      Item.Seen_Delete_Key := False;
      Item.Seen_Delete_Version_ID := False;
      Item.Seen_Delete_Is_Latest := False;
      Item.Seen_Delete_Modified := False;
      Reset_Identity_Seen (Item);
   end Start_Delete_Marker;

   overriding procedure Start_Element
     (Item : in out Version_Listing_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Version_Listing with
           "ListObjectVersions depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Root_Closed or else Item.Field /= No_Field then
         raise Malformed_Version_Listing with
           "nested ListObjectVersions scalar";
      elsif Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "ListVersionsResult" then
            raise Malformed_Version_Listing with
              "invalid ListObjectVersions response root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2 then
         if Item.Context /= Root_Context then
            raise Malformed_Version_Listing with
              "unclosed ListObjectVersions entry";
         elsif Local_Name = "Version" then
            Start_Version (Item);
         elsif Local_Name = "DeleteMarker" then
            Start_Delete_Marker (Item);
         elsif Local_Name = "CommonPrefixes" then
            Item.Context := Prefix_Context;
            Item.Current_Prefix := US.Null_Unbounded_String;
            Item.Seen_Common_Prefix := False;
         elsif Local_Name = "IsTruncated" then
            Select_Field
              (Item, Item.Seen_Top (Is_Truncated_Field),
               Is_Truncated_Field);
         elsif Local_Name = "KeyMarker" then
            Select_Field
              (Item, Item.Seen_Top (Key_Marker_Field), Key_Marker_Field);
         elsif Local_Name = "VersionIdMarker" then
            Select_Field
              (Item, Item.Seen_Top (Version_ID_Marker_Field),
               Version_ID_Marker_Field);
         elsif Local_Name = "NextKeyMarker" then
            Select_Field
              (Item, Item.Seen_Top (Next_Key_Marker_Field),
               Next_Key_Marker_Field);
         elsif Local_Name = "NextVersionIdMarker" then
            Select_Field
              (Item, Item.Seen_Top (Next_Version_ID_Marker_Field),
               Next_Version_ID_Marker_Field);
         elsif Local_Name = "Name" then
            Select_Field (Item, Item.Seen_Top (Name_Field), Name_Field);
         elsif Local_Name = "Prefix" then
            Select_Field (Item, Item.Seen_Top (Prefix_Field), Prefix_Field);
         elsif Local_Name = "Delimiter" then
            Select_Field
              (Item, Item.Seen_Top (Delimiter_Field), Delimiter_Field);
         elsif Local_Name = "MaxKeys" then
            Select_Field
              (Item, Item.Seen_Top (Max_Keys_Field), Max_Keys_Field);
         elsif Local_Name = "EncodingType" then
            Select_Field
              (Item, Item.Seen_Top (Encoding_Type_Field),
               Encoding_Type_Field);
         else
            raise Malformed_Version_Listing with
              "unknown ListObjectVersions response field";
         end if;
      elsif Item.Depth = 3 and then Item.Context = Version_Context then
         if Local_Name = "ETag" then
            Select_Field
              (Item, Item.Seen_Version (Entity_Tag_Field), Entity_Tag_Field);
         elsif Local_Name = "ChecksumAlgorithm" then
            Select_Checksum_Algorithm (Item);
         elsif Local_Name = "ChecksumType" then
            Select_Field
              (Item, Item.Seen_Version (Checksum_Type_Field),
               Checksum_Type_Field);
         elsif Local_Name = "Size" then
            Select_Field (Item, Item.Seen_Version (Size_Field), Size_Field);
         elsif Local_Name = "StorageClass" then
            Select_Field
              (Item, Item.Seen_Version (Storage_Class_Field),
               Storage_Class_Field);
         elsif Local_Name = "Key" then
            Select_Field
              (Item, Item.Seen_Version (Object_Key_Field), Object_Key_Field);
         elsif Local_Name = "VersionId" then
            Select_Field
              (Item, Item.Seen_Version (Object_Version_ID_Field),
               Object_Version_ID_Field);
         elsif Local_Name = "IsLatest" then
            Select_Field
              (Item, Item.Seen_Version (Object_Is_Latest_Field),
               Object_Is_Latest_Field);
         elsif Local_Name = "LastModified" then
            Select_Field
              (Item, Item.Seen_Version (Object_Last_Modified_Field),
               Object_Last_Modified_Field);
         elsif Local_Name = "Owner" then
            if Item.Current_Version.Has_Owner then
               raise Malformed_Version_Listing with
                 "duplicate ListObjectVersions owner";
            end if;
            Item.Current_Version.Has_Owner := True;
            Item.Current_Version.Owner := (others => <>);
            Item.Subcontext := Owner_Subcontext;
            Reset_Identity_Seen (Item);
         elsif Local_Name = "RestoreStatus" then
            if Item.Current_Version.Has_Restore_Status then
               raise Malformed_Version_Listing with
                 "duplicate ListObjectVersions restore status";
            end if;
            Item.Current_Version.Has_Restore_Status := True;
            Item.Current_Version.Restore_Status := (others => <>);
            Item.Subcontext := Restore_Subcontext;
            Item.Seen_Restore_Progress := False;
            Item.Seen_Restore_Expiry := False;
         else
            raise Malformed_Version_Listing with
              "unknown ObjectVersion field";
         end if;
      elsif Item.Depth = 3
        and then Item.Context = Delete_Marker_Context
      then
         if Local_Name = "Owner" then
            if Item.Current_Delete_Marker.Has_Owner then
               raise Malformed_Version_Listing with
                 "duplicate delete-marker owner";
            end if;
            Item.Current_Delete_Marker.Has_Owner := True;
            Item.Current_Delete_Marker.Owner := (others => <>);
            Item.Subcontext := Owner_Subcontext;
            Reset_Identity_Seen (Item);
         elsif Local_Name = "Key" then
            Select_Field
              (Item, Item.Seen_Delete_Key, Object_Key_Field);
         elsif Local_Name = "VersionId" then
            Select_Field
              (Item, Item.Seen_Delete_Version_ID, Object_Version_ID_Field);
         elsif Local_Name = "IsLatest" then
            Select_Field
              (Item, Item.Seen_Delete_Is_Latest, Object_Is_Latest_Field);
         elsif Local_Name = "LastModified" then
            Select_Field
              (Item, Item.Seen_Delete_Modified, Object_Last_Modified_Field);
         else
            raise Malformed_Version_Listing with
              "unknown DeleteMarker field";
         end if;
      elsif Item.Depth = 3 and then Item.Context = Prefix_Context then
         if Local_Name /= "Prefix" then
            raise Malformed_Version_Listing with
              "unknown CommonPrefixes field";
         end if;
         Select_Field
           (Item, Item.Seen_Common_Prefix, Common_Prefix_Field);
      elsif Item.Depth = 4
        and then Item.Subcontext = Owner_Subcontext
      then
         if Local_Name = "DisplayName" then
            Select_Field
              (Item, Item.Seen_Owner_Display, Owner_Display_Name_Field);
         elsif Local_Name = "ID" then
            Select_Field (Item, Item.Seen_Owner_ID, Owner_ID_Field);
         else
            raise Malformed_Version_Listing with "unknown Owner field";
         end if;
      elsif Item.Depth = 4
        and then Item.Context = Version_Context
        and then Item.Subcontext = Restore_Subcontext
      then
         if Local_Name = "IsRestoreInProgress" then
            Select_Field
              (Item, Item.Seen_Restore_Progress,
               Restore_In_Progress_Field);
         elsif Local_Name = "RestoreExpiryDate" then
            Select_Field
              (Item, Item.Seen_Restore_Expiry,
               Restore_Expiry_Date_Field);
         else
            raise Malformed_Version_Listing with
              "unknown RestoreStatus field";
         end if;
      else
         raise Malformed_Version_Listing with
           "misplaced ListObjectVersions field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Version_Listing_Handler; Value : String) is
   begin
      if Item.Field = No_Field then
         Require_Whitespace (Value);
      else
         US.Append (Item.Text_Value, Value);
      end if;
   end Text;

   procedure Finish_Field
     (Item : in out Version_Listing_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);

      procedure Require_Name (Expected : String) is
      begin
         if Local_Name /= Expected then
            raise Malformed_Version_Listing with
              "mismatched ListObjectVersions closing element";
         end if;
      end Require_Name;
   begin
      case Item.Field is
         when Is_Truncated_Field =>
            Require_Name ("IsTruncated");
            Item.Value.Is_Truncated := Parse_Boolean (Value);
            Item.Value.Has_Is_Truncated := True;
         when Key_Marker_Field =>
            Require_Name ("KeyMarker");
            Item.Value.Key_Marker := Item.Text_Value;
            Item.Value.Has_Key_Marker := True;
         when Version_ID_Marker_Field =>
            Require_Name ("VersionIdMarker");
            Item.Value.Version_ID_Marker := Item.Text_Value;
            Item.Value.Has_Version_ID_Marker := True;
         when Next_Key_Marker_Field =>
            Require_Name ("NextKeyMarker");
            Item.Value.Next_Key_Marker := Item.Text_Value;
            Item.Value.Has_Next_Key_Marker := True;
         when Next_Version_ID_Marker_Field =>
            Require_Name ("NextVersionIdMarker");
            Item.Value.Next_Version_ID_Marker := Item.Text_Value;
            Item.Value.Has_Next_Version_ID_Marker := True;
         when Name_Field =>
            Require_Name ("Name");
            Item.Value.Name := Item.Text_Value;
            Item.Value.Has_Name := True;
         when Prefix_Field =>
            Require_Name ("Prefix");
            Item.Value.Prefix := Item.Text_Value;
            Item.Value.Has_Prefix := True;
         when Delimiter_Field =>
            Require_Name ("Delimiter");
            Item.Value.Delimiter := Item.Text_Value;
            Item.Value.Has_Delimiter := True;
         when Max_Keys_Field =>
            Require_Name ("MaxKeys");
            Item.Value.Max_Keys := Parse_Page_Size (Value);
            Item.Value.Has_Max_Keys := True;
         when Encoding_Type_Field =>
            Require_Name ("EncodingType");
            if not Valid_Enumeration (Value, Output_Member_Shape (13)) then
               raise Malformed_Version_Listing with
                 "invalid ListObjectVersions encoding type";
            end if;
            Item.Value.Encoding_Type := Item.Text_Value;
            Item.Value.Has_Encoding_Type := True;
         when Entity_Tag_Field =>
            Require_Name ("ETag");
            Item.Current_Version.Entity_Tag := Item.Text_Value;
            Item.Current_Version.Has_Entity_Tag := True;
         when Checksum_Algorithm_Field =>
            Require_Name ("ChecksumAlgorithm");
            if not Valid_Enumeration (Value, Version_Member_Shape (2))
              or else Has_Checksum_Algorithm (Item.Current_Version, Value)
            then
               raise Malformed_Version_Listing with
                 "invalid ObjectVersion checksum algorithm";
            end if;
            Item.Current_Version.Checksum_Algorithms.Append
              (Item.Text_Value);
         when Checksum_Type_Field =>
            Require_Name ("ChecksumType");
            if not Valid_Enumeration (Value, Version_Member_Shape (3)) then
               raise Malformed_Version_Listing with
                 "invalid ObjectVersion checksum type";
            end if;
            Item.Current_Version.Checksum_Type := Item.Text_Value;
            Item.Current_Version.Has_Checksum_Type := True;
         when Size_Field =>
            Require_Name ("Size");
            Item.Current_Version.Size := Parse_Byte_Count (Value);
            Item.Current_Version.Has_Size := True;
         when Storage_Class_Field =>
            Require_Name ("StorageClass");
            if not Valid_Enumeration (Value, Version_Member_Shape (5)) then
               raise Malformed_Version_Listing with
                 "invalid ObjectVersion storage class";
            end if;
            Item.Current_Version.Storage_Class := Item.Text_Value;
            Item.Current_Version.Has_Storage_Class := True;
         when Object_Key_Field =>
            Require_Name ("Key");
            if Item.Context = Version_Context then
               Item.Current_Version.Key := Item.Text_Value;
               Item.Current_Version.Has_Key := True;
            else
               Item.Current_Delete_Marker.Key := Item.Text_Value;
               Item.Current_Delete_Marker.Has_Key := True;
            end if;
         when Object_Version_ID_Field =>
            Require_Name ("VersionId");
            if Item.Context = Version_Context then
               Item.Current_Version.Version_ID := Item.Text_Value;
               Item.Current_Version.Has_Version_ID := True;
            else
               Item.Current_Delete_Marker.Version_ID := Item.Text_Value;
               Item.Current_Delete_Marker.Has_Version_ID := True;
            end if;
         when Object_Is_Latest_Field =>
            Require_Name ("IsLatest");
            if Item.Context = Version_Context then
               Item.Current_Version.Is_Latest := Parse_Boolean (Value);
               Item.Current_Version.Has_Is_Latest := True;
            else
               Item.Current_Delete_Marker.Is_Latest := Parse_Boolean (Value);
               Item.Current_Delete_Marker.Has_Is_Latest := True;
            end if;
         when Object_Last_Modified_Field =>
            Require_Name ("LastModified");
            if not Valid_ISO_8601_Timestamp (Value) then
               raise Malformed_Version_Listing with
                 "invalid ListObjectVersions timestamp";
            end if;
            if Item.Context = Version_Context then
               Item.Current_Version.Last_Modified := Item.Text_Value;
               Item.Current_Version.Has_Last_Modified := True;
            else
               Item.Current_Delete_Marker.Last_Modified := Item.Text_Value;
               Item.Current_Delete_Marker.Has_Last_Modified := True;
            end if;
         when Owner_Display_Name_Field =>
            Require_Name ("DisplayName");
            if Item.Context = Version_Context then
               Item.Current_Version.Owner.Display_Name := Item.Text_Value;
            else
               Item.Current_Delete_Marker.Owner.Display_Name :=
                 Item.Text_Value;
            end if;
         when Owner_ID_Field =>
            Require_Name ("ID");
            if Item.Context = Version_Context then
               Item.Current_Version.Owner.ID := Item.Text_Value;
            else
               Item.Current_Delete_Marker.Owner.ID := Item.Text_Value;
            end if;
         when Restore_In_Progress_Field =>
            Require_Name ("IsRestoreInProgress");
            Item.Current_Version.Restore_Status.
              Has_Is_Restore_In_Progress := True;
            Item.Current_Version.Restore_Status.Is_Restore_In_Progress :=
              Parse_Boolean (Value);
         when Restore_Expiry_Date_Field =>
            Require_Name ("RestoreExpiryDate");
            if not Valid_ISO_8601_Timestamp (Value) then
               raise Malformed_Version_Listing with
                 "invalid ObjectVersion restore expiry";
            end if;
            Item.Current_Version.Restore_Status.Restore_Expiry_Date :=
              Item.Text_Value;
         when Common_Prefix_Field =>
            Require_Name ("Prefix");
            Item.Current_Prefix := Item.Text_Value;
         when No_Field =>
            raise Malformed_Version_Listing with
              "ListObjectVersions field state is invalid";
      end case;
      Item.Field := No_Field;
      Item.Text_Value := US.Null_Unbounded_String;
   end Finish_Field;

   function Valid_Owner
     (Present : Boolean; Value : Listings.Object_Owner) return Boolean is
     (Present
      or else
        (US.Length (Value.Display_Name) = 0
         and then US.Length (Value.ID) = 0));

   procedure Finish_Version (Item : in out Version_Listing_Handler) is
      Value : Object_Version renames Item.Current_Version;
   begin
      if not Value.Has_Key or else US.Length (Value.Key) = 0
        or else not Value.Has_Version_ID
        or else US.Length (Value.Version_ID) = 0
        or else not Value.Has_Is_Latest
        or else not Value.Has_Last_Modified
        or else not Value.Has_Size
        or else not Value.Has_Storage_Class
        or else not Valid_Owner (Value.Has_Owner, Value.Owner)
        or else
          (Value.Has_Checksum_Type and then Value.Checksum_Algorithms.Is_Empty)
        or else
          (not Value.Has_Checksum_Type
           and then US.Length (Value.Checksum_Type) > 0)
        or else
          (not Value.Has_Restore_Status
           and then
             (Value.Restore_Status.Has_Is_Restore_In_Progress
              or else Value.Restore_Status.Is_Restore_In_Progress
              or else
                US.Length (Value.Restore_Status.Restore_Expiry_Date) > 0))
      then
         raise Malformed_Version_Listing with
           "incomplete ObjectVersion entry";
      end if;
      Item.Value.Versions.Append (Value);
      Item.Context := Root_Context;
      Item.Subcontext := No_Subcontext;
   end Finish_Version;

   procedure Finish_Delete_Marker
     (Item : in out Version_Listing_Handler) is
      Value : Delete_Marker renames Item.Current_Delete_Marker;
   begin
      if not Value.Has_Key or else US.Length (Value.Key) = 0
        or else not Value.Has_Version_ID
        or else US.Length (Value.Version_ID) = 0
        or else not Value.Has_Is_Latest
        or else not Value.Has_Last_Modified
        or else not Valid_Owner (Value.Has_Owner, Value.Owner)
      then
         raise Malformed_Version_Listing with
           "incomplete DeleteMarker entry";
      end if;
      Item.Value.Delete_Markers.Append (Value);
      Item.Context := Root_Context;
      Item.Subcontext := No_Subcontext;
   end Finish_Delete_Marker;

   overriding procedure End_Element
     (Item : in out Version_Listing_Handler; Local_Name : String) is
   begin
      if Item.Depth = 0 then
         raise Malformed_Version_Listing with
           "ListObjectVersions stack underflow";
      elsif Item.Field /= No_Field then
         Finish_Field (Item, Local_Name);
      elsif Item.Depth = 3 and then Item.Subcontext /= No_Subcontext then
         if (Item.Subcontext = Owner_Subcontext and then Local_Name /= "Owner")
           or else
             (Item.Subcontext = Restore_Subcontext
              and then Local_Name /= "RestoreStatus")
         then
            raise Malformed_Version_Listing with
              "mismatched ListObjectVersions nested close";
         end if;
         Item.Subcontext := No_Subcontext;
      elsif Item.Depth = 2 then
         if Item.Context = Version_Context and then Local_Name = "Version" then
            Finish_Version (Item);
         elsif Item.Context = Delete_Marker_Context
           and then Local_Name = "DeleteMarker"
         then
            Finish_Delete_Marker (Item);
         elsif Item.Context = Prefix_Context
           and then Local_Name = "CommonPrefixes"
         then
            if not Item.Seen_Common_Prefix
              or else US.Length (Item.Current_Prefix) = 0
            then
               raise Malformed_Version_Listing with
                 "incomplete CommonPrefixes entry";
            end if;
            Item.Value.Common_Prefixes.Append (Item.Current_Prefix);
            Item.Context := Root_Context;
         else
            raise Malformed_Version_Listing with
              "mismatched ListObjectVersions entry close";
         end if;
      elsif Item.Depth = 1 then
         if Local_Name /= "ListVersionsResult" or else Item.Root_Closed then
            raise Malformed_Version_Listing with
              "invalid ListObjectVersions root close";
         end if;
         Item.Root_Closed := True;
      elsif Item.Depth /= 1 then
         raise Malformed_Version_Listing with
           "invalid ListObjectVersions closing element";
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Same_Identity
     (Left_Key, Left_Version, Right_Key, Right_Version : US.Unbounded_String)
      return Boolean is
     (Left_Key = Right_Key and then Left_Version = Right_Version);

   procedure Validate (Value : List_Object_Versions_Result) is
      Returned : Ada.Containers.Count_Type := Value.Versions.Length;
   begin
      if Returned > Ada.Containers.Count_Type'Last -
        Value.Delete_Markers.Length
      then
         raise Malformed_Version_Listing with
           "ListObjectVersions result count overflow";
      end if;
      Returned := Returned + Value.Delete_Markers.Length;
      if Returned > Ada.Containers.Count_Type'Last -
        Value.Common_Prefixes.Length
      then
         raise Malformed_Version_Listing with
           "ListObjectVersions result count overflow";
      end if;
      Returned := Returned + Value.Common_Prefixes.Length;

      if not Value.Has_Name or else US.Length (Value.Name) = 0
        or else not Value.Has_Max_Keys
        or else not Value.Has_Is_Truncated
        or else Returned > Ada.Containers.Count_Type (Value.Max_Keys)
        or else (Value.Max_Keys = 0 and then Value.Is_Truncated)
      then
         raise Malformed_Version_Listing with
           "incomplete or inconsistent ListObjectVersions page";
      elsif Value.Has_Version_ID_Marker and then not Value.Has_Key_Marker then
         raise Malformed_Version_Listing with
           "version marker lacks its key marker";
      elsif Value.Has_Next_Version_ID_Marker /=
        Value.Has_Next_Key_Marker
        or else Value.Is_Truncated /= Value.Has_Next_Key_Marker
        or else
          (Value.Has_Next_Key_Marker
           and then
             (US.Length (Value.Next_Key_Marker) = 0
              or else US.Length (Value.Next_Version_ID_Marker) = 0))
      then
         raise Malformed_Version_Listing with
           "inconsistent ListObjectVersions next markers";
      elsif Value.Has_Encoding_Type
        and then US.To_String (Value.Encoding_Type) /= "url"
      then
         raise Malformed_Version_Listing with
           "invalid ListObjectVersions encoding type";
      end if;

      if not Value.Versions.Is_Empty then
         for Left in Value.Versions.First_Index .. Value.Versions.Last_Index
         loop
            if Left < Value.Versions.Last_Index then
               for Right in Positive'Succ (Left) ..
                 Value.Versions.Last_Index
               loop
                  if Same_Identity
                    (Value.Versions (Left).Key,
                     Value.Versions (Left).Version_ID,
                     Value.Versions (Right).Key,
                     Value.Versions (Right).Version_ID)
                  then
                     raise Malformed_Version_Listing with
                       "duplicate ObjectVersion entry";
                  end if;
               end loop;
            end if;
            for Marker of Value.Delete_Markers loop
               if Same_Identity
                 (Value.Versions (Left).Key,
                  Value.Versions (Left).Version_ID,
                  Marker.Key, Marker.Version_ID)
               then
                  raise Malformed_Version_Listing with
                    "version and delete marker share one identity";
               end if;
            end loop;
         end loop;
      end if;

      if not Value.Delete_Markers.Is_Empty then
         for Left in Value.Delete_Markers.First_Index ..
           Value.Delete_Markers.Last_Index
         loop
            if Left < Value.Delete_Markers.Last_Index then
               for Right in Positive'Succ (Left) ..
                 Value.Delete_Markers.Last_Index
               loop
                  if Same_Identity
                    (Value.Delete_Markers (Left).Key,
                     Value.Delete_Markers (Left).Version_ID,
                     Value.Delete_Markers (Right).Key,
                     Value.Delete_Markers (Right).Version_ID)
                  then
                     raise Malformed_Version_Listing with
                       "duplicate DeleteMarker entry";
                  end if;
               end loop;
            end if;
         end loop;
      end if;

      if not Value.Common_Prefixes.Is_Empty then
         for Left in Value.Common_Prefixes.First_Index ..
           Value.Common_Prefixes.Last_Index
         loop
            if US.Length (Value.Common_Prefixes (Left)) = 0 then
               raise Malformed_Version_Listing with
                 "empty ListObjectVersions common prefix";
            end if;
            if Left < Value.Common_Prefixes.Last_Index then
               for Right in Positive'Succ (Left) ..
                 Value.Common_Prefixes.Last_Index
               loop
                  if Value.Common_Prefixes (Left) =
                    Value.Common_Prefixes (Right)
                  then
                     raise Malformed_Version_Listing with
                       "duplicate ListObjectVersions common prefix";
                  end if;
               end loop;
            end if;
         end loop;
      end if;
   end Validate;

   function Parse_List_Object_Versions
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Object_Versions_Result
   is
      Handler : aliased Version_Listing_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0
        or else not Handler.Root_Seen
        or else not Handler.Root_Closed
        or else Handler.Context /= Root_Context
        or else Handler.Field /= No_Field
      then
         raise Malformed_Version_Listing with
           "incomplete ListObjectVersions document";
      end if;
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when Occurrence : XML.XML_Error =>
         raise Malformed_Version_Listing with
           "malformed ListObjectVersions XML: " &
           Ada.Exceptions.Exception_Message (Occurrence);
   end Parse_List_Object_Versions;

   function Serialize_List_Object_Versions
     (Value : List_Object_Versions_Result) return String
   is
      Result : US.Unbounded_String;

      function Image (Item : Core.Page_Size) return String is
        (Ada.Strings.Fixed.Trim
           (Core.Page_Size'Image (Item), Ada.Strings.Both));

      function Image (Item : Byte_Count) return String is
        (Ada.Strings.Fixed.Trim
           (Byte_Count'Image (Item), Ada.Strings.Both));

      function Element (Name, Text : String) return String is
        ("<" & Name & ">" & XML.Escape_Text (Text) & "</" & Name & ">");

      procedure Append_Present
        (Present : Boolean; Name : String; Text : US.Unbounded_String) is
      begin
         if Present then
            US.Append (Result, Element (Name, US.To_String (Text)));
         elsif US.Length (Text) > 0 then
            raise Malformed_Version_Listing with
              "ListObjectVersions value lacks presence state";
         end if;
      end Append_Present;

      procedure Append_Owner
        (Present : Boolean; Owner : Listings.Object_Owner) is
      begin
         if Present then
            US.Append (Result, "<Owner>");
            if US.Length (Owner.Display_Name) > 0 then
               US.Append
                 (Result,
                  Element
                    ("DisplayName", US.To_String (Owner.Display_Name)));
            end if;
            if US.Length (Owner.ID) > 0 then
               US.Append (Result, Element ("ID", US.To_String (Owner.ID)));
            end if;
            US.Append (Result, "</Owner>");
         elsif US.Length (Owner.Display_Name) > 0
           or else US.Length (Owner.ID) > 0
         then
            raise Malformed_Version_Listing with
              "ListObjectVersions owner lacks presence state";
         end if;
      end Append_Owner;

      procedure Validate_Version (Item : Object_Version) is
      begin
         if not Item.Has_Key or else US.Length (Item.Key) = 0
           or else not Item.Has_Version_ID
           or else US.Length (Item.Version_ID) = 0
           or else not Item.Has_Is_Latest
           or else not Item.Has_Last_Modified
           or else not Valid_ISO_8601_Timestamp
             (US.To_String (Item.Last_Modified))
           or else not Item.Has_Size
           or else not Item.Has_Storage_Class
           or else not Valid_Enumeration
             (US.To_String (Item.Storage_Class), Version_Member_Shape (5))
           or else not Valid_Owner (Item.Has_Owner, Item.Owner)
           or else
             (Item.Has_Checksum_Type
              and then Item.Checksum_Algorithms.Is_Empty)
           or else
             (Item.Has_Checksum_Type
              and then not Valid_Enumeration
                (US.To_String (Item.Checksum_Type),
                 Version_Member_Shape (3)))
           or else
             (not Item.Has_Checksum_Type
              and then US.Length (Item.Checksum_Type) > 0)
           or else
             (not Item.Has_Restore_Status
              and then
                (Item.Restore_Status.Has_Is_Restore_In_Progress
                 or else Item.Restore_Status.Is_Restore_In_Progress
                 or else
                   US.Length
                     (Item.Restore_Status.Restore_Expiry_Date) > 0))
           or else
             (Item.Has_Restore_Status
              and then Item.Restore_Status.Is_Restore_In_Progress
              and then not Item.Restore_Status.Has_Is_Restore_In_Progress)
           or else
             (US.Length (Item.Restore_Status.Restore_Expiry_Date) > 0
              and then not Valid_ISO_8601_Timestamp
                (US.To_String
                   (Item.Restore_Status.Restore_Expiry_Date)))
         then
            raise Malformed_Version_Listing with
              "incomplete ObjectVersion entry";
         end if;
         if not Item.Checksum_Algorithms.Is_Empty then
            for Left in Item.Checksum_Algorithms.First_Index ..
              Item.Checksum_Algorithms.Last_Index
            loop
               if not Valid_Enumeration
                 (US.To_String (Item.Checksum_Algorithms (Left)),
                  Version_Member_Shape (2))
               then
                  raise Malformed_Version_Listing with
                    "invalid ObjectVersion checksum algorithm";
               end if;
               if Left < Item.Checksum_Algorithms.Last_Index then
                  for Right in Positive'Succ (Left) ..
                    Item.Checksum_Algorithms.Last_Index
                  loop
                     if Item.Checksum_Algorithms (Left) =
                       Item.Checksum_Algorithms (Right)
                     then
                        raise Malformed_Version_Listing with
                          "duplicate ObjectVersion checksum algorithm";
                     end if;
                  end loop;
               end if;
            end loop;
         end if;
      end Validate_Version;

      procedure Validate_Marker (Item : Delete_Marker) is
      begin
         if not Item.Has_Key or else US.Length (Item.Key) = 0
           or else not Item.Has_Version_ID
           or else US.Length (Item.Version_ID) = 0
           or else not Item.Has_Is_Latest
           or else not Item.Has_Last_Modified
           or else not Valid_ISO_8601_Timestamp
             (US.To_String (Item.Last_Modified))
           or else not Valid_Owner (Item.Has_Owner, Item.Owner)
         then
            raise Malformed_Version_Listing with
              "incomplete DeleteMarker entry";
         end if;
      end Validate_Marker;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<ListVersionsResult xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">" &
         Element
           ("IsTruncated",
            (if Value.Is_Truncated then "true" else "false")));
      Append_Present
        (Value.Has_Key_Marker, "KeyMarker", Value.Key_Marker);
      Append_Present
        (Value.Has_Version_ID_Marker, "VersionIdMarker",
         Value.Version_ID_Marker);
      Append_Present
        (Value.Has_Next_Key_Marker, "NextKeyMarker",
         Value.Next_Key_Marker);
      Append_Present
        (Value.Has_Next_Version_ID_Marker, "NextVersionIdMarker",
         Value.Next_Version_ID_Marker);

      for Item of Value.Versions loop
         Validate_Version (Item);
         US.Append (Result, "<Version>");
         Append_Present (Item.Has_Entity_Tag, "ETag", Item.Entity_Tag);
         for Algorithm of Item.Checksum_Algorithms loop
            US.Append
              (Result,
               Element ("ChecksumAlgorithm", US.To_String (Algorithm)));
         end loop;
         Append_Present
           (Item.Has_Checksum_Type, "ChecksumType", Item.Checksum_Type);
         US.Append (Result, Element ("Size", Image (Item.Size)));
         US.Append
           (Result,
            Element ("StorageClass", US.To_String (Item.Storage_Class)) &
            Element ("Key", US.To_String (Item.Key)) &
            Element ("VersionId", US.To_String (Item.Version_ID)) &
            Element
              ("IsLatest", (if Item.Is_Latest then "true" else "false")) &
            Element
              ("LastModified", US.To_String (Item.Last_Modified)));
         Append_Owner (Item.Has_Owner, Item.Owner);
         if Item.Has_Restore_Status then
            US.Append (Result, "<RestoreStatus>");
            if Item.Restore_Status.Has_Is_Restore_In_Progress then
               US.Append
                 (Result,
                  Element
                    ("IsRestoreInProgress",
                     (if Item.Restore_Status.Is_Restore_In_Progress
                      then "true" else "false")));
            end if;
            if US.Length (Item.Restore_Status.Restore_Expiry_Date) > 0 then
               US.Append
                 (Result,
                  Element
                    ("RestoreExpiryDate",
                     US.To_String
                       (Item.Restore_Status.Restore_Expiry_Date)));
            end if;
            US.Append (Result, "</RestoreStatus>");
         end if;
         US.Append (Result, "</Version>");
      end loop;

      for Item of Value.Delete_Markers loop
         Validate_Marker (Item);
         US.Append (Result, "<DeleteMarker>");
         Append_Owner (Item.Has_Owner, Item.Owner);
         US.Append
           (Result,
            Element ("Key", US.To_String (Item.Key)) &
            Element ("VersionId", US.To_String (Item.Version_ID)) &
            Element
              ("IsLatest", (if Item.Is_Latest then "true" else "false")) &
            Element
              ("LastModified", US.To_String (Item.Last_Modified)) &
            "</DeleteMarker>");
      end loop;

      US.Append (Result, Element ("Name", US.To_String (Value.Name)));
      Append_Present (Value.Has_Prefix, "Prefix", Value.Prefix);
      Append_Present (Value.Has_Delimiter, "Delimiter", Value.Delimiter);
      US.Append (Result, Element ("MaxKeys", Image (Value.Max_Keys)));
      for Prefix of Value.Common_Prefixes loop
         US.Append
           (Result,
            "<CommonPrefixes>" &
            Element ("Prefix", US.To_String (Prefix)) &
            "</CommonPrefixes>");
      end loop;
      Append_Present
        (Value.Has_Encoding_Type, "EncodingType", Value.Encoding_Type);
      US.Append (Result, "</ListVersionsResult>");
      return US.To_String (Result);
   end Serialize_List_Object_Versions;

end Flyology.Object_Storage.S3.Versions;
