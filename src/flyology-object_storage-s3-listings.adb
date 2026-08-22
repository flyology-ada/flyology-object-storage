with Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.Wire_Core;
with GNAT.SHA256;

package body Flyology.Object_Storage.S3.Listings is

   package US renames Ada.Strings.Unbounded;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;

   Maximum_Query_Length : constant := 8 * 1_024;
   Token_Prefix : constant String := "fos1.";

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
               raise Malformed_List_Request with
                 "invalid listing percent escape";
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

   function Parse_List_Objects_Query
     (Query : String) return List_Objects_Request
   is
      Result : List_Objects_Request;
      Seen_Max_Keys, Seen_Prefix, Seen_Delimiter, Seen_Marker : Boolean :=
        False;
      Seen_Encoding, Seen_X_ID : Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 then
         return Result;
      elsif Query'Length > Maximum_Query_Length then
         raise Malformed_List_Request with "invalid ListObjects query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 32 then
         raise Malformed_List_Request with
           "too many ListObjects query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_List_Request with
                    "empty ListObjects query parameter";
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
                  Number : Wire_Core.Natural_Result;
               begin
                  if Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Max_Keys or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_List_Request with
                          "invalid ListObjects max-keys";
                     end if;
                     Seen_Max_Keys := True;
                     Result.Max_Keys := Core.Page_Size (Number.Value);
                  elsif Name = "prefix" then
                     if Seen_Prefix then
                        raise Malformed_List_Request with
                          "duplicate ListObjects prefix";
                     end if;
                     Seen_Prefix := True;
                     Result.Prefix := US.To_Unbounded_String (Value);
                  elsif Name = "delimiter" then
                     if Seen_Delimiter then
                        raise Malformed_List_Request with
                          "duplicate ListObjects delimiter";
                     end if;
                     Seen_Delimiter := True;
                     Result.Delimiter := US.To_Unbounded_String (Value);
                  elsif Name = "marker" then
                     if Seen_Marker then
                        raise Malformed_List_Request with
                          "duplicate ListObjects marker";
                     end if;
                     Seen_Marker := True;
                     Result.Marker := US.To_Unbounded_String (Value);
                  elsif Name = "encoding-type" then
                     if Seen_Encoding or else Value /= "url" then
                        raise Malformed_List_Request with
                          "invalid ListObjects encoding-type";
                     end if;
                     Seen_Encoding := True;
                     Result.URL_Encoding := True;
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "ListObjects" then
                        raise Malformed_List_Request with
                          "invalid ListObjects operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_List_Request with
                       "unsupported ListObjects query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      return Result;
   end Parse_List_Objects_Query;

   function Parse_List_Objects_V2_Query
     (Query : String) return List_Objects_V2_Request
   is
      Result : List_Objects_V2_Request;
      Seen_List_Type, Seen_Max_Keys, Seen_Prefix, Seen_Delimiter : Boolean :=
        False;
      Seen_Token, Seen_Start, Seen_Fetch, Seen_Encoding, Seen_X_ID : Boolean :=
        False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Length then
         raise Malformed_List_Request with "invalid ListObjectsV2 query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 32 then
         raise Malformed_List_Request with
           "too many ListObjectsV2 query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_List_Request with
                    "empty ListObjectsV2 query parameter";
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
                  Number : Wire_Core.Natural_Result;
                  Truth  : Wire_Core.Boolean_Result;
               begin
                  if Name = "list-type" then
                     if Seen_List_Type or else Value /= "2" then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 list type";
                     end if;
                     Seen_List_Type := True;
                  elsif Name = "max-keys" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Max_Keys or else not Number.Valid
                       or else Number.Value > Core.Page_Size'Last
                     then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 max-keys";
                     end if;
                     Seen_Max_Keys := True;
                     Result.Max_Keys := Core.Page_Size (Number.Value);
                  elsif Name = "prefix" then
                     if Seen_Prefix then
                        raise Malformed_List_Request with
                          "duplicate ListObjectsV2 prefix";
                     end if;
                     Seen_Prefix := True;
                     Result.Prefix := US.To_Unbounded_String (Value);
                  elsif Name = "delimiter" then
                     if Seen_Delimiter then
                        raise Malformed_List_Request with
                          "duplicate ListObjectsV2 delimiter";
                     end if;
                     Seen_Delimiter := True;
                     Result.Delimiter := US.To_Unbounded_String (Value);
                  elsif Name = "continuation-token" then
                     if Seen_Token then
                        raise Malformed_List_Request with
                          "duplicate ListObjectsV2 continuation token";
                     end if;
                     Seen_Token := True;
                     Result.Has_Continuation_Token := True;
                     Result.Continuation_Token :=
                       US.To_Unbounded_String (Value);
                  elsif Name = "start-after" then
                     if Seen_Start then
                        raise Malformed_List_Request with
                          "duplicate ListObjectsV2 start-after";
                     end if;
                     Seen_Start := True;
                     Result.Start_After := US.To_Unbounded_String (Value);
                  elsif Name = "fetch-owner" then
                     Truth := Wire_Core.Parse_Boolean (Value);
                     if Seen_Fetch or else not Truth.Valid then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 fetch-owner";
                     end if;
                     Seen_Fetch := True;
                     Result.Fetch_Owner := Truth.Value;
                  elsif Name = "encoding-type" then
                     if Seen_Encoding or else Value /= "url" then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 encoding-type";
                     end if;
                     Seen_Encoding := True;
                     Result.URL_Encoding := True;
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "ListObjectsV2" then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_List_Request with
                       "unsupported ListObjectsV2 query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      if not Seen_List_Type then
         raise Malformed_List_Request with
           "ListObjectsV2 query lacks list-type=2";
      end if;
      return Result;
   end Parse_List_Objects_V2_Query;

   function Token_Digest
     (Bucket, Prefix, Delimiter, After : String) return String is
     (GNAT.SHA256.Digest
        ("flyology-list-v1" & Character'Val (0) & Bucket &
         Character'Val (0) & Prefix & Character'Val (0) & Delimiter &
         Character'Val (0) & After));

   function Hex_Encode (Value : String) return String is
      Hex_Digits : constant String := "0123456789abcdef";
      Result : String (1 .. Value'Length * 2);
      Cursor : Positive := 1;
   begin
      for Byte of Value loop
         Result (Cursor) := Hex_Digits (Character'Pos (Byte) / 16 + 1);
         Result (Cursor + 1) :=
           Hex_Digits (Character'Pos (Byte) mod 16 + 1);
         Cursor := Cursor + 2;
      end loop;
      return Result;
   end Hex_Encode;

   function Encode_Continuation
     (Bucket, Prefix, Delimiter, After : String) return String is
     (Token_Prefix & Token_Digest (Bucket, Prefix, Delimiter, After) & "." &
      Hex_Encode (After));

   function Decode_Continuation
     (Token, Bucket, Prefix, Delimiter : String)
      return Continuation_Result
   is
      Invalid : constant Continuation_Result := (others => <>);
   begin
      if Token'Length < Token_Prefix'Length + 65
        or else Token'Length > Token_Prefix'Length + 65 + 2 * 1_024
      then
         return Invalid;
      end if;
      declare
         Raw : constant String (1 .. Token'Length) := Token;
         Digest_First : constant Positive := Token_Prefix'Length + 1;
         Digest_Last  : constant Positive := Digest_First + 63;
         Hex_First    : constant Positive := Digest_Last + 2;
         Hex_Length   : constant Natural := Raw'Last - Hex_First + 1;
      begin
         if Raw (1 .. Token_Prefix'Length) /= Token_Prefix
           or else Raw (Digest_Last + 1) /= '.'
           or else Hex_Length mod 2 /= 0
           or else not SigV4_Encoding.Valid_SHA256_Hex
             (Raw (Digest_First .. Digest_Last))
         then
            return Invalid;
         end if;
         declare
            After : String (1 .. Hex_Length / 2);
            Cursor : Positive := Hex_First;
         begin
            for Index in After'Range loop
               if Hex_Value (Raw (Cursor)) > 15
                 or else Hex_Value (Raw (Cursor + 1)) > 15
               then
                  return Invalid;
               end if;
               After (Index) := Character'Val
                 (16 * Hex_Value (Raw (Cursor)) +
                  Hex_Value (Raw (Cursor + 1)));
               Cursor := Cursor + 2;
            end loop;
            if (After'Length > 0 and then not Valid_Object_Key (After))
              or else Raw (Digest_First .. Digest_Last) /=
                Token_Digest (Bucket, Prefix, Delimiter, After)
            then
               return Invalid;
            end if;
            return
              (Valid => True, After => US.To_Unbounded_String (After));
         end;
      end;
   end Decode_Continuation;

   type Field_Kind is
     (No_Field,
      Name_Field,
      Prefix_Field,
      Delimiter_Field,
      Encoding_Type_Field,
      Marker_Field,
      Next_Marker_Field,
      Continuation_Token_Field,
      Next_Continuation_Token_Field,
      Start_After_Field,
      Key_Count_Field,
      Max_Keys_Field,
      Is_Truncated_Field,
      Object_Key_Field,
      Object_Last_Modified_Field,
      Object_Entity_Tag_Field,
      Object_Size_Field,
      Object_Storage_Class_Field,
      Common_Prefix_Field);

   type Parse_Context is (Root_Context, Object_Context, Prefix_Context);
   type Listing_Version is (Version_1, Version_2);

   type Listing_Handler (Version : Listing_Version) is
     new XML.Event_Handler with record
      V1_Value                    : List_Objects_Result;
      V2_Value                    : List_Objects_V2_Result;
      Current_Object              : Object_Entry;
      Current_Prefix              : US.Unbounded_String;
      Text_Value                  : US.Unbounded_String;
      Depth                       : Natural := 0;
      Ignore_Depth                : Natural := 0;
      Context                     : Parse_Context := Root_Context;
      Field                       : Field_Kind := No_Field;
      Seen_Name                   : Boolean := False;
      Seen_Prefix                 : Boolean := False;
      Seen_Delimiter              : Boolean := False;
      Seen_Encoding_Type          : Boolean := False;
      Seen_Marker                 : Boolean := False;
      Seen_Next_Marker            : Boolean := False;
      Seen_Continuation_Token     : Boolean := False;
      Seen_Next_Token             : Boolean := False;
      Seen_Start_After            : Boolean := False;
      Seen_Key_Count              : Boolean := False;
      Seen_Max_Keys               : Boolean := False;
      Seen_Is_Truncated           : Boolean := False;
      Seen_Object_Key             : Boolean := False;
      Seen_Object_Last_Modified   : Boolean := False;
      Seen_Object_Entity_Tag      : Boolean := False;
      Seen_Object_Size            : Boolean := False;
      Seen_Object_Storage_Class   : Boolean := False;
      Seen_Common_Prefix          : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Listing_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Listing_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Listing_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value /= ' '
           and then Character_Value /= Character'Val (9)
           and then Character_Value /= Character'Val (10)
           and then Character_Value /= Character'Val (13)
         then
            raise Malformed_Listing with "text outside S3 listing fields";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Select_Field
     (Item  : in out Listing_Handler;
      Seen  : in out Boolean;
      Field : Field_Kind)
   is
   begin
      if Seen then
         raise Malformed_Listing with "duplicate S3 listing field";
      end if;
      Seen := True;
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Field;

   function Parse_Natural (Value : String) return Natural is
      Result : constant Wire_Core.Natural_Result :=
        Wire_Core.Parse_Natural (Value);
   begin
      if not Result.Valid then
         raise Malformed_Listing with "invalid S3 listing integer";
      end if;
      return Result.Value;
   end Parse_Natural;

   function Parse_Byte_Count (Value : String) return Byte_Count is
      Result : constant Wire_Core.Byte_Count_Result :=
        Wire_Core.Parse_Byte_Count (Value);
   begin
      if not Result.Valid then
         raise Malformed_Listing with "invalid S3 object size";
      end if;
      return Result.Value;
   end Parse_Byte_Count;

   function Parse_Boolean (Value : String) return Boolean is
      Result : constant Wire_Core.Boolean_Result :=
        Wire_Core.Parse_Boolean (Value);
   begin
      if not Result.Valid then
         raise Malformed_Listing with "invalid S3 listing boolean";
      end if;
      return Result.Value;
   end Parse_Boolean;

   procedure Finish_Field (Item : in out Listing_Handler) is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Field is
         when Name_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Name := Item.Text_Value;
            else
               Item.V2_Value.Name := Item.Text_Value;
            end if;
         when Prefix_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Prefix := Item.Text_Value;
            else
               Item.V2_Value.Prefix := Item.Text_Value;
            end if;
         when Delimiter_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Delimiter := Item.Text_Value;
            else
               Item.V2_Value.Delimiter := Item.Text_Value;
            end if;
         when Encoding_Type_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Encoding_Type := Item.Text_Value;
            else
               Item.V2_Value.Encoding_Type := Item.Text_Value;
            end if;
         when Marker_Field =>
            Item.V1_Value.Marker := Item.Text_Value;
         when Next_Marker_Field =>
            Item.V1_Value.Next_Marker := Item.Text_Value;
         when Continuation_Token_Field =>
            Item.V2_Value.Continuation_Token := Item.Text_Value;
            Item.V2_Value.Has_Continuation_Token := True;
         when Next_Continuation_Token_Field =>
            Item.V2_Value.Next_Continuation_Token := Item.Text_Value;
         when Start_After_Field =>
            Item.V2_Value.Start_After := Item.Text_Value;
         when Key_Count_Field =>
            Item.V2_Value.Key_Count := Parse_Natural (Value);
         when Max_Keys_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Max_Keys := Parse_Natural (Value);
            else
               Item.V2_Value.Max_Keys := Parse_Natural (Value);
            end if;
         when Is_Truncated_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Is_Truncated := Parse_Boolean (Value);
            else
               Item.V2_Value.Is_Truncated := Parse_Boolean (Value);
            end if;
         when Object_Key_Field =>
            Item.Current_Object.Key := Item.Text_Value;
         when Object_Last_Modified_Field =>
            Item.Current_Object.Last_Modified := Item.Text_Value;
         when Object_Entity_Tag_Field =>
            Item.Current_Object.Entity_Tag := Item.Text_Value;
         when Object_Size_Field =>
            Item.Current_Object.Size := Parse_Byte_Count (Value);
         when Object_Storage_Class_Field =>
            Item.Current_Object.Storage_Class := Item.Text_Value;
         when Common_Prefix_Field =>
            Item.Current_Prefix := Item.Text_Value;
         when No_Field =>
            null;
      end case;
      Item.Field := No_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Field;

   overriding procedure Start_Element
     (Item : in out Listing_Handler; Local_Name : String)
   is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Listing with "S3 listing depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      end if;

      if Item.Depth = 1 then
         if Local_Name /= "ListBucketResult" then
            raise Malformed_Listing with
              "S3 listing root is not ListBucketResult";
         end if;
      elsif Item.Depth = 2 then
         if Item.Field /= No_Field then
            raise Malformed_Listing with "nested S3 listing scalar";
         elsif Local_Name = "Contents" then
            Item.Context := Object_Context;
            Item.Current_Object := (others => <>);
            Item.Seen_Object_Key := False;
            Item.Seen_Object_Last_Modified := False;
            Item.Seen_Object_Entity_Tag := False;
            Item.Seen_Object_Size := False;
            Item.Seen_Object_Storage_Class := False;
         elsif Local_Name = "CommonPrefixes" then
            Item.Context := Prefix_Context;
            US.Set_Unbounded_String (Item.Current_Prefix, "");
            Item.Seen_Common_Prefix := False;
         elsif Local_Name = "Name" then
            Select_Field (Item, Item.Seen_Name, Name_Field);
         elsif Local_Name = "Prefix" then
            Select_Field (Item, Item.Seen_Prefix, Prefix_Field);
         elsif Local_Name = "Delimiter" then
            Select_Field (Item, Item.Seen_Delimiter, Delimiter_Field);
         elsif Local_Name = "EncodingType" then
            Select_Field (Item, Item.Seen_Encoding_Type, Encoding_Type_Field);
         elsif Item.Version = Version_1 and then Local_Name = "Marker" then
            Select_Field (Item, Item.Seen_Marker, Marker_Field);
         elsif Item.Version = Version_1
           and then Local_Name = "NextMarker"
         then
            Select_Field (Item, Item.Seen_Next_Marker, Next_Marker_Field);
         elsif Item.Version = Version_2
           and then Local_Name = "ContinuationToken"
         then
            Select_Field
              (Item, Item.Seen_Continuation_Token, Continuation_Token_Field);
         elsif Item.Version = Version_2
           and then Local_Name = "NextContinuationToken"
         then
            Select_Field
              (Item, Item.Seen_Next_Token, Next_Continuation_Token_Field);
         elsif Item.Version = Version_2 and then Local_Name = "StartAfter" then
            Select_Field (Item, Item.Seen_Start_After, Start_After_Field);
         elsif Item.Version = Version_2 and then Local_Name = "KeyCount" then
            Select_Field (Item, Item.Seen_Key_Count, Key_Count_Field);
         elsif Local_Name = "MaxKeys" then
            Select_Field (Item, Item.Seen_Max_Keys, Max_Keys_Field);
         elsif Local_Name = "IsTruncated" then
            Select_Field (Item, Item.Seen_Is_Truncated, Is_Truncated_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Context = Object_Context then
         if Local_Name = "Key" then
            Select_Field (Item, Item.Seen_Object_Key, Object_Key_Field);
         elsif Local_Name = "LastModified" then
            Select_Field
              (Item, Item.Seen_Object_Last_Modified,
               Object_Last_Modified_Field);
         elsif Local_Name = "ETag" then
            Select_Field
              (Item, Item.Seen_Object_Entity_Tag, Object_Entity_Tag_Field);
         elsif Local_Name = "Size" then
            Select_Field (Item, Item.Seen_Object_Size, Object_Size_Field);
         elsif Local_Name = "StorageClass" then
            Select_Field
              (Item, Item.Seen_Object_Storage_Class,
               Object_Storage_Class_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Context = Prefix_Context then
         if Local_Name = "Prefix" then
            Select_Field
              (Item, Item.Seen_Common_Prefix, Common_Prefix_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      else
         raise Malformed_Listing with "nested S3 listing field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Listing_Handler; Value : String) is
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
     (Item : in out Listing_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Listing with "S3 listing stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         Finish_Field (Item);
      elsif Item.Depth = 2 and then Item.Context = Object_Context then
         if not Item.Seen_Object_Key
           or else not Item.Seen_Object_Size
           or else US.Length (Item.Current_Object.Key) = 0
         then
            raise Malformed_Listing with "incomplete S3 object entry";
         end if;
         if Item.Version = Version_1 then
            Item.V1_Value.Contents.Append (Item.Current_Object);
         else
            Item.V2_Value.Contents.Append (Item.Current_Object);
         end if;
         Item.Context := Root_Context;
      elsif Item.Depth = 2 and then Item.Context = Prefix_Context then
         if not Item.Seen_Common_Prefix
           or else US.Length (Item.Current_Prefix) = 0
         then
            raise Malformed_Listing with "incomplete S3 common prefix";
         end if;
         if Item.Version = Version_1 then
            Item.V1_Value.Common_Prefixes.Append (Item.Current_Prefix);
         else
            Item.V2_Value.Common_Prefixes.Append (Item.Current_Prefix);
         end if;
         Item.Context := Root_Context;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Validate (Value : List_Objects_V2_Result) is
      Contents_Length : constant Ada.Containers.Count_Type :=
        Value.Contents.Length;
      Prefixes_Length : constant Ada.Containers.Count_Type :=
        Value.Common_Prefixes.Length;
      Returned : Natural;
   begin
      if US.Length (Value.Name) = 0 then
         raise Malformed_Listing with "S3 listing lacks bucket name";
      elsif Contents_Length >
        Ada.Containers.Count_Type (Natural'Last) - Prefixes_Length
      then
         raise Malformed_Listing with "S3 listing count overflow";
      end if;
      Returned := Natural (Contents_Length + Prefixes_Length);
      if Value.Key_Count /= Returned
        or else Value.Key_Count > Value.Max_Keys
      then
         raise Malformed_Listing with "inconsistent S3 listing counts";
      elsif Value.Is_Truncated /=
        (US.Length (Value.Next_Continuation_Token) > 0)
      then
         raise Malformed_Listing with "inconsistent S3 continuation token";
      end if;
      for Object_Value of Value.Contents loop
         if US.Length (Object_Value.Key) = 0 then
            raise Malformed_Listing with "empty S3 object key";
         end if;
      end loop;
      for Prefix of Value.Common_Prefixes loop
         if US.Length (Prefix) = 0 then
            raise Malformed_Listing with "empty S3 common prefix";
         end if;
      end loop;
   end Validate;

   function Parse_List_Objects_V2
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Objects_V2_Result
   is
      Handler : aliased Listing_Handler (Version_2);
   begin
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Name
        or else not Handler.Seen_Key_Count
        or else not Handler.Seen_Max_Keys
        or else not Handler.Seen_Is_Truncated
      then
         raise Malformed_Listing with "S3 listing lacks required fields";
      end if;
      Validate (Handler.V2_Value);
      return Handler.V2_Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Listing with "malformed S3 listing XML";
   end Parse_List_Objects_V2;

   function Image (Value : Natural) return String is
     (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));

   function Image (Value : Byte_Count) return String is
     (Ada.Strings.Fixed.Trim (Byte_Count'Image (Value), Ada.Strings.Both));

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   procedure Append_Optional
     (Target : in out US.Unbounded_String; Name, Value : String) is
   begin
      if Value'Length > 0 then
         US.Append (Target, Element (Name, Value));
      end if;
   end Append_Optional;

   procedure Validate (Value : List_Objects_Result) is
      Contents_Length : constant Ada.Containers.Count_Type :=
        Value.Contents.Length;
      Prefixes_Length : constant Ada.Containers.Count_Type :=
        Value.Common_Prefixes.Length;
      Returned : Natural;
      Has_Delimiter : constant Boolean := US.Length (Value.Delimiter) > 0;
      Has_Next : constant Boolean := US.Length (Value.Next_Marker) > 0;
   begin
      if US.Length (Value.Name) = 0 then
         raise Malformed_Listing with "S3 listing lacks bucket name";
      elsif Contents_Length >
        Ada.Containers.Count_Type (Natural'Last) - Prefixes_Length
      then
         raise Malformed_Listing with "S3 listing count overflow";
      end if;
      Returned := Natural (Contents_Length + Prefixes_Length);
      if Returned > Value.Max_Keys then
         raise Malformed_Listing with "inconsistent S3 listing counts";
      elsif Value.Max_Keys = 0 and then Value.Is_Truncated then
         raise Malformed_Listing with "zero-sized S3 listing is truncated";
      elsif Has_Next /= (Value.Is_Truncated and then Has_Delimiter) then
         raise Malformed_Listing with "inconsistent S3 next marker";
      elsif US.Length (Value.Encoding_Type) > 0
        and then US.To_String (Value.Encoding_Type) /= "url"
      then
         raise Malformed_Listing with "invalid S3 listing encoding type";
      end if;
      for Object_Value of Value.Contents loop
         if US.Length (Object_Value.Key) = 0 then
            raise Malformed_Listing with "empty S3 object key";
         end if;
      end loop;
      for Prefix of Value.Common_Prefixes loop
         if US.Length (Prefix) = 0 then
            raise Malformed_Listing with "empty S3 common prefix";
         end if;
      end loop;
   end Validate;

   function Parse_List_Objects
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Objects_Result
   is
      Handler : aliased Listing_Handler (Version_1);
   begin
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen_Name
        or else not Handler.Seen_Max_Keys
        or else not Handler.Seen_Is_Truncated
      then
         raise Malformed_Listing with "S3 listing lacks required fields";
      end if;
      Validate (Handler.V1_Value);
      return Handler.V1_Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Listing with "malformed S3 listing XML";
   end Parse_List_Objects;

   function Serialize_List_Objects
     (Value : List_Objects_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">" &
         Element ("Name", US.To_String (Value.Name)) &
         Element ("Prefix", US.To_String (Value.Prefix)) &
         Element ("Marker", US.To_String (Value.Marker)));
      Append_Optional
        (Result, "NextMarker", US.To_String (Value.Next_Marker));
      US.Append (Result, Element ("MaxKeys", Image (Value.Max_Keys)));
      Append_Optional
        (Result, "Delimiter", US.To_String (Value.Delimiter));
      Append_Optional
        (Result, "EncodingType", US.To_String (Value.Encoding_Type));
      US.Append
        (Result,
         Element
           ("IsTruncated",
            (if Value.Is_Truncated then "true" else "false")));
      for Object_Value of Value.Contents loop
         US.Append
           (Result, "<Contents>" &
            Element ("Key", US.To_String (Object_Value.Key)));
         Append_Optional
           (Result, "LastModified", US.To_String (Object_Value.Last_Modified));
         Append_Optional
           (Result, "ETag", US.To_String (Object_Value.Entity_Tag));
         US.Append (Result, Element ("Size", Image (Object_Value.Size)));
         Append_Optional
           (Result, "StorageClass", US.To_String (Object_Value.Storage_Class));
         US.Append (Result, "</Contents>");
      end loop;
      for Prefix of Value.Common_Prefixes loop
         US.Append
           (Result,
            "<CommonPrefixes>" & Element ("Prefix", US.To_String (Prefix)) &
            "</CommonPrefixes>");
      end loop;
      US.Append (Result, "</ListBucketResult>");
      return US.To_String (Result);
   end Serialize_List_Objects;

   function Serialize_List_Objects_V2
     (Value : List_Objects_V2_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
         (Result,
          "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<ListBucketResult xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">" &
         Element ("Name", US.To_String (Value.Name)) &
         Element ("Prefix", US.To_String (Value.Prefix)) &
         Element ("KeyCount", Image (Value.Key_Count)) &
         Element ("MaxKeys", Image (Value.Max_Keys)) &
         Element
           ("IsTruncated", (if Value.Is_Truncated then "true" else "false")));
      Append_Optional
        (Result, "Delimiter", US.To_String (Value.Delimiter));
      Append_Optional
        (Result, "EncodingType", US.To_String (Value.Encoding_Type));
      if Value.Has_Continuation_Token then
         US.Append
           (Result,
            Element
              ("ContinuationToken",
               US.To_String (Value.Continuation_Token)));
      elsif US.Length (Value.Continuation_Token) > 0 then
         raise Malformed_Listing with
           "S3 continuation token lacks presence state";
      end if;
      Append_Optional
        (Result, "NextContinuationToken",
         US.To_String (Value.Next_Continuation_Token));
      Append_Optional
        (Result, "StartAfter", US.To_String (Value.Start_After));
      for Object_Value of Value.Contents loop
         US.Append (Result, "<Contents>" & Element
           ("Key", US.To_String (Object_Value.Key)));
         Append_Optional
           (Result, "LastModified", US.To_String (Object_Value.Last_Modified));
         Append_Optional
           (Result, "ETag", US.To_String (Object_Value.Entity_Tag));
         US.Append (Result, Element ("Size", Image (Object_Value.Size)));
         Append_Optional
           (Result, "StorageClass", US.To_String (Object_Value.Storage_Class));
         US.Append (Result, "</Contents>");
      end loop;
      for Prefix of Value.Common_Prefixes loop
         US.Append
           (Result,
            "<CommonPrefixes>" & Element ("Prefix", US.To_String (Prefix)) &
            "</CommonPrefixes>");
      end loop;
      US.Append (Result, "</ListBucketResult>");
      return US.To_String (Result);
   end Serialize_List_Objects_V2;

end Flyology.Object_Storage.S3.Listings;
