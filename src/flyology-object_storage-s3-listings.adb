with Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Wire_Core;
with GNAT.SHA256;

package body Flyology.Object_Storage.S3.Listings is

   package US renames Ada.Strings.Unbounded;
   package Model renames Flyology.Object_Storage.S3.Model;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;
   use type Model.Shape_Kind;

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

   function Decode_URL_Value (Value : String) return String is
   begin
      return Decode_Component (Value);
   exception
      when Malformed_List_Request =>
         raise Malformed_Listing with
           "invalid encoding-type=url listing value";
   end Decode_URL_Value;

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
                     Result.Has_Max_Keys := True;
                     Result.Max_Keys := Core.Page_Size (Number.Value);
                  elsif Name = "prefix" then
                     if Seen_Prefix then
                        raise Malformed_List_Request with
                          "duplicate ListObjects prefix";
                     end if;
                     Seen_Prefix := True;
                     Result.Has_Prefix := True;
                     Result.Prefix := US.To_Unbounded_String (Value);
                  elsif Name = "delimiter" then
                     if Seen_Delimiter then
                        raise Malformed_List_Request with
                          "duplicate ListObjects delimiter";
                     end if;
                     Seen_Delimiter := True;
                     Result.Has_Delimiter := True;
                     Result.Delimiter := US.To_Unbounded_String (Value);
                  elsif Name = "marker" then
                     if Seen_Marker then
                        raise Malformed_List_Request with
                          "duplicate ListObjects marker";
                     end if;
                     Seen_Marker := True;
                     Result.Has_Marker := True;
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
                     Result.Has_Delimiter := True;
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
                     Result.Has_Start_After := True;
                     Result.Start_After := US.To_Unbounded_String (Value);
                  elsif Name = "fetch-owner" then
                     Truth := Wire_Core.Parse_Boolean (Value);
                     if Seen_Fetch or else not Truth.Valid then
                        raise Malformed_List_Request with
                          "invalid ListObjectsV2 fetch-owner";
                     end if;
                     Seen_Fetch := True;
                     Result.Has_Fetch_Owner := True;
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
      if not Core.Valid_Listing_Continuation_Syntax (Token) then
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
      Object_Checksum_Algorithm_Field,
      Object_Checksum_Type_Field,
      Object_Size_Field,
      Object_Storage_Class_Field,
      Owner_Display_Name_Field,
      Owner_ID_Field,
      Restore_In_Progress_Field,
      Restore_Expiry_Date_Field,
      Common_Prefix_Field);

   type Parse_Context is (Root_Context, Object_Context, Prefix_Context);
   type Object_Subcontext is
     (No_Object_Subcontext, Owner_Subcontext, Restore_Subcontext);
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
      Object_Context_State        : Object_Subcontext :=
        No_Object_Subcontext;
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
      Seen_Object_Checksum_Type   : Boolean := False;
      Seen_Object_Size            : Boolean := False;
      Seen_Object_Storage_Class   : Boolean := False;
      Seen_Owner_Display_Name     : Boolean := False;
      Seen_Owner_ID               : Boolean := False;
      Seen_Restore_In_Progress    : Boolean := False;
      Seen_Restore_Expiry_Date    : Boolean := False;
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

   procedure Select_Repeated_Field
     (Item : in out Listing_Handler; Field : Field_Kind) is
   begin
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Repeated_Field;

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

   function Object_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.List_Objects_Operation));
      Contents : constant Model.Shape_Index :=
        Model.Member_Shape (Output, 4);
      Object_Shape : constant Model.Shape_Index := Model.Shape_Index
        (Model.List_Member_Shape (Contents));
   begin
      return Model.Member_Shape (Object_Shape, Member);
   end Object_Member_Shape;

   function Valid_Object_Enumeration
     (Value : String; Member : Positive) return Boolean
   is
      Member_Shape : constant Model.Shape_Index :=
        Object_Member_Shape (Member);
      Shape : constant Model.Shape_Index :=
        (if Model.Kind (Member_Shape) = Model.List_Shape
         then Model.Shape_Index (Model.List_Member_Shape (Member_Shape))
         else Member_Shape);
   begin
      if Model.Enumeration_Count (Shape) = 0 then
         return False;
      end if;
      for Index in 1 .. Model.Enumeration_Count (Shape) loop
         if Model.Enumeration_Value (Shape, Index) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Valid_Object_Enumeration;

   function Has_Checksum_Algorithm
     (Item : Object_Entry; Value : String) return Boolean is
   begin
      for Algorithm of Item.Checksum_Algorithms loop
         if US.To_String (Algorithm) = Value then
            return True;
         end if;
      end loop;
      return False;
   end Has_Checksum_Algorithm;

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
               Item.V1_Value.Has_Prefix := True;
            else
               Item.V2_Value.Prefix := Item.Text_Value;
            end if;
         when Delimiter_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Delimiter := Item.Text_Value;
               Item.V1_Value.Has_Delimiter := True;
            else
               Item.V2_Value.Delimiter := Item.Text_Value;
               Item.V2_Value.Has_Delimiter := True;
            end if;
         when Encoding_Type_Field =>
            if Item.Version = Version_1 then
               Item.V1_Value.Encoding_Type := Item.Text_Value;
               Item.V1_Value.Has_Encoding_Type := True;
            else
               Item.V2_Value.Encoding_Type := Item.Text_Value;
               Item.V2_Value.Has_Encoding_Type := True;
            end if;
         when Marker_Field =>
            Item.V1_Value.Marker := Item.Text_Value;
            Item.V1_Value.Has_Marker := True;
         when Next_Marker_Field =>
            Item.V1_Value.Next_Marker := Item.Text_Value;
            Item.V1_Value.Has_Next_Marker := True;
         when Continuation_Token_Field =>
            Item.V2_Value.Continuation_Token := Item.Text_Value;
            Item.V2_Value.Has_Continuation_Token := True;
         when Next_Continuation_Token_Field =>
            Item.V2_Value.Next_Continuation_Token := Item.Text_Value;
            Item.V2_Value.Has_Next_Continuation_Token := True;
         when Start_After_Field =>
            Item.V2_Value.Start_After := Item.Text_Value;
            Item.V2_Value.Has_Start_After := True;
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
         when Object_Checksum_Algorithm_Field =>
            if not Valid_Object_Enumeration (Value, 4)
              or else Has_Checksum_Algorithm (Item.Current_Object, Value)
            then
               raise Malformed_Listing with
                 "invalid S3 object checksum algorithm";
            end if;
            Item.Current_Object.Checksum_Algorithms.Append
              (Item.Text_Value);
         when Object_Checksum_Type_Field =>
            if not Valid_Object_Enumeration (Value, 5) then
               raise Malformed_Listing with "invalid S3 object checksum type";
            end if;
            Item.Current_Object.Checksum_Type := Item.Text_Value;
         when Object_Size_Field =>
            Item.Current_Object.Size := Parse_Byte_Count (Value);
         when Object_Storage_Class_Field =>
            if not Valid_Object_Enumeration (Value, 7) then
               raise Malformed_Listing with
                 "invalid S3 object storage class";
            end if;
            Item.Current_Object.Storage_Class := Item.Text_Value;
         when Owner_Display_Name_Field =>
            Item.Current_Object.Owner.Display_Name := Item.Text_Value;
         when Owner_ID_Field =>
            Item.Current_Object.Owner.ID := Item.Text_Value;
         when Restore_In_Progress_Field =>
            Item.Current_Object.Restore_Status.
              Has_Is_Restore_In_Progress := True;
            Item.Current_Object.Restore_Status.Is_Restore_In_Progress :=
              Parse_Boolean (Value);
         when Restore_Expiry_Date_Field =>
            Item.Current_Object.Restore_Status.Restore_Expiry_Date :=
              Item.Text_Value;
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
      elsif Item.Field /= No_Field then
         raise Malformed_Listing with "nested S3 listing scalar";
      end if;

      if Item.Depth = 1 then
         if Local_Name /= "ListBucketResult" then
            raise Malformed_Listing with
              "S3 listing root is not ListBucketResult";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "Contents" then
            Item.Context := Object_Context;
            Item.Current_Object := (others => <>);
            Item.Seen_Object_Key := False;
            Item.Seen_Object_Last_Modified := False;
            Item.Seen_Object_Entity_Tag := False;
            Item.Seen_Object_Checksum_Type := False;
            Item.Seen_Object_Size := False;
            Item.Seen_Object_Storage_Class := False;
            Item.Object_Context_State := No_Object_Subcontext;
            Item.Seen_Owner_Display_Name := False;
            Item.Seen_Owner_ID := False;
            Item.Seen_Restore_In_Progress := False;
            Item.Seen_Restore_Expiry_Date := False;
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
         elsif Local_Name = "ChecksumAlgorithm" then
            Select_Repeated_Field
              (Item, Object_Checksum_Algorithm_Field);
         elsif Local_Name = "ChecksumType" then
            Select_Field
              (Item, Item.Seen_Object_Checksum_Type,
               Object_Checksum_Type_Field);
         elsif Local_Name = "Size" then
            Select_Field (Item, Item.Seen_Object_Size, Object_Size_Field);
         elsif Local_Name = "StorageClass" then
            Select_Field
              (Item, Item.Seen_Object_Storage_Class,
               Object_Storage_Class_Field);
         elsif Local_Name = "Owner" then
            if Item.Current_Object.Has_Owner then
               raise Malformed_Listing with "duplicate S3 listing field";
            end if;
            Item.Object_Context_State := Owner_Subcontext;
            Item.Current_Object.Has_Owner := True;
            Item.Current_Object.Owner := (others => <>);
            Item.Seen_Owner_Display_Name := False;
            Item.Seen_Owner_ID := False;
         elsif Local_Name = "RestoreStatus" then
            if Item.Current_Object.Has_Restore_Status then
               raise Malformed_Listing with "duplicate S3 listing field";
            end if;
            Item.Object_Context_State := Restore_Subcontext;
            Item.Current_Object.Has_Restore_Status := True;
            Item.Current_Object.Restore_Status := (others => <>);
            Item.Seen_Restore_In_Progress := False;
            Item.Seen_Restore_Expiry_Date := False;
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
      elsif Item.Depth = 4
        and then Item.Context = Object_Context
        and then Item.Object_Context_State = Owner_Subcontext
      then
         if Local_Name = "DisplayName" then
            Select_Field
              (Item, Item.Seen_Owner_Display_Name,
               Owner_Display_Name_Field);
         elsif Local_Name = "ID" then
            Select_Field (Item, Item.Seen_Owner_ID, Owner_ID_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 4
        and then Item.Context = Object_Context
        and then Item.Object_Context_State = Restore_Subcontext
      then
         if Local_Name = "IsRestoreInProgress" then
            Select_Field
              (Item, Item.Seen_Restore_In_Progress,
               Restore_In_Progress_Field);
         elsif Local_Name = "RestoreExpiryDate" then
            Select_Field
              (Item, Item.Seen_Restore_Expiry_Date,
               Restore_Expiry_Date_Field);
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
      elsif Item.Depth = 3
        and then Item.Context = Object_Context
        and then Item.Object_Context_State /= No_Object_Subcontext
      then
         Item.Object_Context_State := No_Object_Subcontext;
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

   procedure Validate_Object (Value : Object_Entry) is
      Seen : Checksum_Algorithm_List;
   begin
      if US.Length (Value.Key) = 0 then
         raise Malformed_Listing with "empty S3 object key";
      elsif US.Length (Value.Checksum_Type) > 0
        and then
          (Value.Checksum_Algorithms.Is_Empty
           or else not Valid_Object_Enumeration
             (US.To_String (Value.Checksum_Type), 5))
      then
         raise Malformed_Listing with "invalid S3 object checksum type";
      elsif US.Length (Value.Storage_Class) > 0
        and then not Valid_Object_Enumeration
          (US.To_String (Value.Storage_Class), 7)
      then
         raise Malformed_Listing with "invalid S3 object storage class";
      elsif not Value.Has_Owner
        and then
          (US.Length (Value.Owner.Display_Name) > 0
           or else US.Length (Value.Owner.ID) > 0)
      then
         raise Malformed_Listing with "S3 object owner lacks presence state";
      elsif not Value.Has_Restore_Status
        and then
          (Value.Restore_Status.Has_Is_Restore_In_Progress
           or else Value.Restore_Status.Is_Restore_In_Progress
           or else US.Length (Value.Restore_Status.Restore_Expiry_Date) > 0)
      then
         raise Malformed_Listing with
           "S3 object restore status lacks presence state";
      end if;
      for Algorithm of Value.Checksum_Algorithms loop
         declare
            Text : constant String := US.To_String (Algorithm);
         begin
            if not Valid_Object_Enumeration (Text, 4) then
               raise Malformed_Listing with
                 "invalid S3 object checksum algorithm";
            end if;
            for Previous of Seen loop
               if US."=" (Previous, Algorithm) then
                  raise Malformed_Listing with
                    "duplicate S3 object checksum algorithm";
               end if;
            end loop;
            Seen.Append (Algorithm);
         end;
      end loop;
   end Validate_Object;

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
      if Value.Max_Keys > Natural (Core.Page_Size'Last)
        or else Value.Key_Count /= Returned
        or else Value.Key_Count > Value.Max_Keys
      then
         raise Malformed_Listing with "inconsistent S3 listing counts";
      elsif Value.Is_Truncated /= Value.Has_Next_Continuation_Token
        or else
          (Value.Has_Next_Continuation_Token
           and then US.Length (Value.Next_Continuation_Token) = 0)
        or else
          (not Value.Has_Next_Continuation_Token
           and then US.Length (Value.Next_Continuation_Token) > 0)
      then
         raise Malformed_Listing with "inconsistent S3 continuation token";
      elsif
        (Value.Has_Encoding_Type
         and then US.To_String (Value.Encoding_Type) /= "url")
        or else
          (not Value.Has_Encoding_Type
           and then US.Length (Value.Encoding_Type) > 0)
      then
         raise Malformed_Listing with "invalid S3 listing encoding type";
      elsif not Value.Has_Continuation_Token
        and then US.Length (Value.Continuation_Token) > 0
      then
         raise Malformed_Listing with
           "S3 continuation token lacks presence state";
      elsif not Value.Has_Delimiter and then US.Length (Value.Delimiter) > 0
      then
         raise Malformed_Listing with
           "S3 delimiter lacks presence state";
      elsif
        not Value.Has_Start_After
        and then US.Length (Value.Start_After) > 0
      then
         raise Malformed_Listing with
           "S3 start-after lacks presence state";
      end if;
      for Object_Value of Value.Contents loop
         Validate_Object (Object_Value);
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

   procedure Append_Object
     (Target : in out US.Unbounded_String; Value : Object_Entry) is
   begin
      US.Append
        (Target, "<Contents>" & Element ("Key", US.To_String (Value.Key)));
      Append_Optional
        (Target, "LastModified", US.To_String (Value.Last_Modified));
      Append_Optional (Target, "ETag", US.To_String (Value.Entity_Tag));
      for Algorithm of Value.Checksum_Algorithms loop
         US.Append
           (Target,
            Element ("ChecksumAlgorithm", US.To_String (Algorithm)));
      end loop;
      Append_Optional
        (Target, "ChecksumType", US.To_String (Value.Checksum_Type));
      US.Append (Target, Element ("Size", Image (Value.Size)));
      Append_Optional
        (Target, "StorageClass", US.To_String (Value.Storage_Class));
      if Value.Has_Owner then
         US.Append (Target, "<Owner>");
         Append_Optional
           (Target, "DisplayName", US.To_String (Value.Owner.Display_Name));
         Append_Optional (Target, "ID", US.To_String (Value.Owner.ID));
         US.Append (Target, "</Owner>");
      end if;
      if Value.Has_Restore_Status then
         US.Append (Target, "<RestoreStatus>");
         if Value.Restore_Status.Has_Is_Restore_In_Progress then
            US.Append
              (Target,
               Element
                 ("IsRestoreInProgress",
                  (if Value.Restore_Status.Is_Restore_In_Progress
                   then "true" else "false")));
         end if;
         Append_Optional
           (Target, "RestoreExpiryDate",
            US.To_String (Value.Restore_Status.Restore_Expiry_Date));
         US.Append (Target, "</RestoreStatus>");
      end if;
      US.Append (Target, "</Contents>");
   end Append_Object;

   procedure Validate (Value : List_Objects_Result) is
      Contents_Length : constant Ada.Containers.Count_Type :=
        Value.Contents.Length;
      Prefixes_Length : constant Ada.Containers.Count_Type :=
        Value.Common_Prefixes.Length;
      Returned : Natural;
      Effective_Delimiter : constant Boolean :=
        Value.Has_Delimiter and then US.Length (Value.Delimiter) > 0;
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
      elsif Value.Has_Next_Marker /=
        (Value.Is_Truncated and then Effective_Delimiter)
        or else
          (Value.Has_Next_Marker and then US.Length (Value.Next_Marker) = 0)
        or else
          (not Value.Has_Next_Marker
           and then US.Length (Value.Next_Marker) > 0)
      then
         raise Malformed_Listing with "inconsistent S3 next marker";
      elsif
        (Value.Has_Encoding_Type
         and then US.To_String (Value.Encoding_Type) /= "url")
        or else
          (not Value.Has_Encoding_Type
           and then US.Length (Value.Encoding_Type) > 0)
      then
         raise Malformed_Listing with "invalid S3 listing encoding type";
      elsif not Value.Has_Prefix and then US.Length (Value.Prefix) > 0 then
         raise Malformed_Listing with "S3 prefix lacks presence state";
      elsif not Value.Has_Delimiter
        and then US.Length (Value.Delimiter) > 0
      then
         raise Malformed_Listing with "S3 delimiter lacks presence state";
      elsif not Value.Has_Marker and then US.Length (Value.Marker) > 0 then
         raise Malformed_Listing with "S3 marker lacks presence state";
      end if;
      for Object_Value of Value.Contents loop
         Validate_Object (Object_Value);
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
         Element ("Name", US.To_String (Value.Name)));
      if Value.Has_Prefix then
         US.Append (Result, Element ("Prefix", US.To_String (Value.Prefix)));
      end if;
      if Value.Has_Marker then
         US.Append (Result, Element ("Marker", US.To_String (Value.Marker)));
      end if;
      if Value.Has_Next_Marker then
         US.Append
           (Result, Element ("NextMarker", US.To_String (Value.Next_Marker)));
      end if;
      US.Append (Result, Element ("MaxKeys", Image (Value.Max_Keys)));
      if Value.Has_Delimiter then
         US.Append
           (Result, Element ("Delimiter", US.To_String (Value.Delimiter)));
      end if;
      if Value.Has_Encoding_Type then
         US.Append
           (Result,
            Element ("EncodingType", US.To_String (Value.Encoding_Type)));
      end if;
      US.Append
        (Result,
         Element
           ("IsTruncated",
            (if Value.Is_Truncated then "true" else "false")));
      for Object_Value of Value.Contents loop
         Append_Object (Result, Object_Value);
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
      if Value.Has_Delimiter then
         US.Append
           (Result, Element ("Delimiter", US.To_String (Value.Delimiter)));
      end if;
      if Value.Has_Encoding_Type then
         US.Append
           (Result,
            Element ("EncodingType", US.To_String (Value.Encoding_Type)));
      end if;
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
      if Value.Has_Next_Continuation_Token then
         US.Append
           (Result,
            Element
              ("NextContinuationToken",
               US.To_String (Value.Next_Continuation_Token)));
      end if;
      if Value.Has_Start_After then
         US.Append
           (Result, Element ("StartAfter", US.To_String (Value.Start_After)));
      end if;
      for Object_Value of Value.Contents loop
         Append_Object (Result, Object_Value);
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
