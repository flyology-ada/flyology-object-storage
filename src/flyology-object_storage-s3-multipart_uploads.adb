with Ada.Containers;
with Ada.Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Model;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Multipart_Uploads is

   package US renames Ada.Strings.Unbounded;
   package Model renames Flyology.Object_Storage.S3.Model;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;
   use type US.Unbounded_String;

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
               raise Malformed_List_Request with
                 "invalid ListMultipartUploads percent escape";
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

   function Parse_List_Multipart_Uploads_Query
     (Query : String) return List_Multipart_Uploads_Request
   is
      Result : List_Multipart_Uploads_Request;
      Seen_Uploads, Seen_Delimiter, Seen_Encoding, Seen_Key_Marker :
        Boolean := False;
      Seen_Max, Seen_Prefix, Seen_Upload_ID_Marker, Seen_X_ID :
        Boolean := False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Length then
         raise Malformed_List_Request with
           "invalid ListMultipartUploads query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 32 then
         raise Malformed_List_Request with
           "too many ListMultipartUploads query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_List_Request with
                    "empty ListMultipartUploads query parameter";
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
                        raise Malformed_List_Request with
                          "invalid ListMultipartUploads marker";
                     end if;
                     Seen_Uploads := True;
                  elsif Name = "delimiter" then
                     if Seen_Delimiter then
                        raise Malformed_List_Request with
                          "duplicate ListMultipartUploads delimiter";
                     end if;
                     Seen_Delimiter := True;
                     Result.Delimiter := US.To_Unbounded_String (Value);
                  elsif Name = "encoding-type" then
                     if Seen_Encoding or else Value /= "url" then
                        raise Malformed_List_Request with
                          "invalid ListMultipartUploads encoding-type";
                     end if;
                     Seen_Encoding := True;
                     Result.URL_Encoding := True;
                  elsif Name = "key-marker" then
                     if Seen_Key_Marker then
                        raise Malformed_List_Request with
                          "duplicate ListMultipartUploads key marker";
                     end if;
                     Seen_Key_Marker := True;
                     Result.Key_Marker := US.To_Unbounded_String (Value);
                  elsif Name = "max-uploads" then
                     declare
                        Number : constant Wire_Core.Natural_Result :=
                          Wire_Core.Parse_Natural (Value);
                     begin
                        if Seen_Max or else not Number.Valid
                          or else Number.Value not in 1 .. Core.Page_Size'Last
                        then
                           raise Malformed_List_Request with
                             "invalid ListMultipartUploads page size";
                        end if;
                        Seen_Max := True;
                        Result.Max_Uploads := Core.Page_Size (Number.Value);
                     end;
                  elsif Name = "prefix" then
                     if Seen_Prefix then
                        raise Malformed_List_Request with
                          "duplicate ListMultipartUploads prefix";
                     end if;
                     Seen_Prefix := True;
                     Result.Prefix := US.To_Unbounded_String (Value);
                  elsif Name = "upload-id-marker" then
                     if Seen_Upload_ID_Marker then
                        raise Malformed_List_Request with
                          "duplicate ListMultipartUploads upload ID marker";
                     end if;
                     Seen_Upload_ID_Marker := True;
                     Result.Upload_ID_Marker := US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "ListMultipartUploads" then
                        raise Malformed_List_Request with
                          "invalid ListMultipartUploads operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_List_Request with
                       "unsupported ListMultipartUploads query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      if not Seen_Uploads then
         raise Malformed_List_Request with
           "ListMultipartUploads query lacks uploads marker";
      end if;
      return Result;
   end Parse_List_Multipart_Uploads_Query;

   type Field_Kind is
     (No_Field, Bucket_Field, Key_Marker_Field, Upload_ID_Marker_Field,
      Next_Key_Marker_Field, Next_Upload_ID_Marker_Field, Prefix_Field,
      Delimiter_Field, Max_Uploads_Field, Is_Truncated_Field,
      Encoding_Type_Field, Upload_ID_Field, Key_Field, Initiated_Field,
      Storage_Class_Field, Checksum_Algorithm_Field, Checksum_Type_Field,
      Identity_ID_Field, Identity_Display_Name_Field,
      Common_Prefix_Field);

   type Context_Kind is
     (Root_Context, Upload_Context, Owner_Context, Initiator_Context,
      Common_Prefix_Context);

   type Seen_Array is array (Field_Kind) of Boolean;

   type Listing_Handler is new XML.Event_Handler with record
      Value            : List_Multipart_Uploads_Result;
      Current_Upload   : Upload_Entry;
      Current_Identity : Multipart.Multipart_Identity;
      Text_Value       : US.Unbounded_String;
      Depth            : Natural := 0;
      Ignore_Depth     : Natural := 0;
      Context          : Context_Kind := Root_Context;
      Field            : Field_Kind := No_Field;
      Seen             : Seen_Array := (others => False);
   end record;

   overriding procedure Start_Element
     (Item : in out Listing_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Listing_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Listing_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Upload_Listing with
              "text outside ListMultipartUploads fields";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Select_Field
     (Item : in out Listing_Handler; Field : Field_Kind) is
   begin
      if Item.Seen (Field) then
         raise Malformed_Upload_Listing with
           "duplicate ListMultipartUploads field";
      end if;
      Item.Seen (Field) := True;
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Field;

   function Parse_Page_Size (Value : String) return Core.Page_Size is
      Parsed : constant Wire_Core.Natural_Result :=
        Wire_Core.Parse_Natural (Value);
   begin
      if not Parsed.Valid or else Parsed.Value > Core.Page_Size'Last then
         raise Malformed_Upload_Listing with
           "invalid ListMultipartUploads page size";
      end if;
      return Core.Page_Size (Parsed.Value);
   end Parse_Page_Size;

   function Parse_Boolean (Value : String) return Boolean is
      Parsed : constant Wire_Core.Boolean_Result :=
        Wire_Core.Parse_Boolean (Value);
   begin
      if not Parsed.Valid then
         raise Malformed_Upload_Listing with
           "invalid ListMultipartUploads boolean";
      end if;
      return Parsed.Value;
   end Parse_Boolean;

   procedure Finish_Field (Item : in out Listing_Handler) is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Field is
         when Bucket_Field =>
            Item.Value.Bucket := Item.Text_Value;
         when Key_Marker_Field =>
            Item.Value.Key_Marker := Item.Text_Value;
         when Upload_ID_Marker_Field =>
            Item.Value.Upload_ID_Marker := Item.Text_Value;
         when Next_Key_Marker_Field =>
            Item.Value.Next_Key_Marker := Item.Text_Value;
         when Next_Upload_ID_Marker_Field =>
            Item.Value.Next_Upload_ID_Marker := Item.Text_Value;
         when Prefix_Field =>
            Item.Value.Prefix := Item.Text_Value;
         when Delimiter_Field =>
            Item.Value.Delimiter := Item.Text_Value;
         when Max_Uploads_Field =>
            Item.Value.Max_Uploads := Parse_Page_Size (Value);
         when Is_Truncated_Field =>
            Item.Value.Is_Truncated := Parse_Boolean (Value);
         when Encoding_Type_Field =>
            Item.Value.Encoding_Type := Item.Text_Value;
         when Upload_ID_Field =>
            Item.Current_Upload.Upload_ID := Item.Text_Value;
         when Key_Field =>
            Item.Current_Upload.Key := Item.Text_Value;
         when Initiated_Field =>
            Item.Current_Upload.Initiated := Item.Text_Value;
         when Storage_Class_Field =>
            Item.Current_Upload.Storage_Class := Item.Text_Value;
         when Checksum_Algorithm_Field =>
            Item.Current_Upload.Checksum_Algorithm := Item.Text_Value;
         when Checksum_Type_Field =>
            Item.Current_Upload.Checksum_Type := Item.Text_Value;
         when Identity_ID_Field =>
            Item.Current_Identity.ID := Item.Text_Value;
         when Identity_Display_Name_Field =>
            Item.Current_Identity.Display_Name := Item.Text_Value;
         when Common_Prefix_Field =>
            if Item.Value.Common_Prefixes.Length >=
              Ada.Containers.Count_Type (Core.Page_Size'Last)
            then
               raise Malformed_Upload_Listing with
                 "too many multipart common prefixes";
            end if;
            Item.Value.Common_Prefixes.Append (Item.Text_Value);
         when No_Field =>
            null;
      end case;
      Item.Field := No_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Field;

   procedure Reset_Upload (Item : in out Listing_Handler) is
   begin
      Item.Current_Upload := (others => <>);
      for Field in Upload_ID_Field .. Identity_Display_Name_Field loop
         Item.Seen (Field) := False;
      end loop;
      Item.Context := Upload_Context;
   end Reset_Upload;

   procedure Reset_Identity
     (Item : in out Listing_Handler; Context : Context_Kind) is
   begin
      Item.Current_Identity := (others => <>);
      Item.Seen (Identity_ID_Field) := False;
      Item.Seen (Identity_Display_Name_Field) := False;
      Item.Context := Context;
   end Reset_Identity;

   overriding procedure Start_Element
     (Item : in out Listing_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Upload_Listing with
           "ListMultipartUploads XML depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field /= No_Field then
         raise Malformed_Upload_Listing with
           "nested ListMultipartUploads scalar";
      end if;

      if Item.Depth = 1 then
         if Local_Name /= "ListMultipartUploadsResult" then
            raise Malformed_Upload_Listing with
              "wrong ListMultipartUploads root";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "Bucket" then
            Select_Field (Item, Bucket_Field);
         elsif Local_Name = "KeyMarker" then
            Select_Field (Item, Key_Marker_Field);
         elsif Local_Name = "UploadIdMarker" then
            Select_Field (Item, Upload_ID_Marker_Field);
         elsif Local_Name = "NextKeyMarker" then
            Select_Field (Item, Next_Key_Marker_Field);
         elsif Local_Name = "NextUploadIdMarker" then
            Select_Field (Item, Next_Upload_ID_Marker_Field);
         elsif Local_Name = "Prefix" then
            Select_Field (Item, Prefix_Field);
         elsif Local_Name = "Delimiter" then
            Select_Field (Item, Delimiter_Field);
         elsif Local_Name = "MaxUploads" then
            Select_Field (Item, Max_Uploads_Field);
         elsif Local_Name = "IsTruncated" then
            Select_Field (Item, Is_Truncated_Field);
         elsif Local_Name = "EncodingType" then
            Select_Field (Item, Encoding_Type_Field);
         elsif Local_Name = "Upload" then
            if Item.Value.Uploads.Length >=
              Ada.Containers.Count_Type (Core.Page_Size'Last)
            then
               raise Malformed_Upload_Listing with
                 "too many multipart uploads";
            end if;
            Reset_Upload (Item);
         elsif Local_Name = "CommonPrefixes" then
            Item.Seen (Common_Prefix_Field) := False;
            Item.Context := Common_Prefix_Context;
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Context = Upload_Context then
         if Local_Name = "UploadId" then
            Select_Field (Item, Upload_ID_Field);
         elsif Local_Name = "Key" then
            Select_Field (Item, Key_Field);
         elsif Local_Name = "Initiated" then
            Select_Field (Item, Initiated_Field);
         elsif Local_Name = "StorageClass" then
            Select_Field (Item, Storage_Class_Field);
         elsif Local_Name = "ChecksumAlgorithm" then
            Select_Field (Item, Checksum_Algorithm_Field);
         elsif Local_Name = "ChecksumType" then
            Select_Field (Item, Checksum_Type_Field);
         elsif Local_Name = "Owner" then
            if Item.Current_Upload.Has_Owner then
               raise Malformed_Upload_Listing with
                 "duplicate multipart upload owner";
            end if;
            Item.Current_Upload.Has_Owner := True;
            Reset_Identity (Item, Owner_Context);
         elsif Local_Name = "Initiator" then
            if Item.Current_Upload.Has_Initiator then
               raise Malformed_Upload_Listing with
                 "duplicate multipart upload initiator";
            end if;
            Item.Current_Upload.Has_Initiator := True;
            Reset_Identity (Item, Initiator_Context);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Context = Common_Prefix_Context then
         if Local_Name = "Prefix" then
            Select_Field (Item, Common_Prefix_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 4
        and then Item.Context in Owner_Context | Initiator_Context
      then
         if Local_Name = "ID" then
            Select_Field (Item, Identity_ID_Field);
         elsif Local_Name = "DisplayName" then
            Select_Field (Item, Identity_Display_Name_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      else
         raise Malformed_Upload_Listing with
           "nested ListMultipartUploads field";
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
         raise Malformed_Upload_Listing with
           "ListMultipartUploads XML stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         Finish_Field (Item);
      elsif Item.Depth = 3 and then Item.Context = Owner_Context then
         Item.Current_Upload.Owner := Item.Current_Identity;
         Item.Context := Upload_Context;
      elsif Item.Depth = 3 and then Item.Context = Initiator_Context then
         Item.Current_Upload.Initiator := Item.Current_Identity;
         Item.Context := Upload_Context;
      elsif Item.Depth = 2 and then Item.Context = Upload_Context then
         if not Item.Seen (Upload_ID_Field)
           or else not Item.Seen (Key_Field)
           or else not Item.Seen (Initiated_Field)
           or else US.Length (Item.Current_Upload.Upload_ID) = 0
           or else US.Length (Item.Current_Upload.Key) = 0
           or else US.Length (Item.Current_Upload.Initiated) = 0
         then
            raise Malformed_Upload_Listing with
              "incomplete multipart upload";
         end if;
         Item.Value.Uploads.Append (Item.Current_Upload);
         Item.Context := Root_Context;
      elsif Item.Depth = 2
        and then Item.Context = Common_Prefix_Context
      then
         if not Item.Seen (Common_Prefix_Field) then
            raise Malformed_Upload_Listing with
              "incomplete multipart common prefix";
         end if;
         Item.Context := Root_Context;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Valid_Enumeration
     (Value : String; Shape : Model.Shape_Index) return Boolean is
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
   end Valid_Enumeration;

   function Output_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Output : constant Model.Shape_Index := Model.Shape_Index
        (Model.Output_Shape (Model.List_Multipart_Uploads_Operation));
   begin
      return Model.Member_Shape (Output, Member);
   end Output_Member_Shape;

   function Upload_Member_Shape (Member : Positive)
      return Model.Shape_Index
   is
      Upload_List_Shape : constant Model.Shape_Index :=
        Output_Member_Shape (10);
      Upload_Shape : constant Model.Shape_Index := Model.Shape_Index
        (Model.List_Member_Shape (Upload_List_Shape));
   begin
      return Model.Member_Shape (Upload_Shape, Member);
   end Upload_Member_Shape;

   function Valid_Identity
     (Present : Boolean; Value : Multipart.Multipart_Identity)
      return Boolean is
     (Present
      or else
        (US.Length (Value.ID) = 0
         and then US.Length (Value.Display_Name) = 0));

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

      Year   : Natural;
      Month  : Natural;
      Day    : Natural;
      Hour   : Natural;
      Minute : Natural;
      Second : Natural;
      Zone   : Positive := 20;
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

   function Starts_With (Value, Prefix : String) return Boolean is
     (Prefix'Length <= Value'Length
      and then Value
        (Value'First .. Value'First + Prefix'Length - 1) = Prefix);

   procedure Validate (Value : List_Multipart_Uploads_Result) is
   begin
      if US.Length (Value.Bucket) = 0 then
         raise Malformed_Upload_Listing with
           "ListMultipartUploads lacks bucket";
      elsif Value.Uploads.Length + Value.Common_Prefixes.Length >
        Ada.Containers.Count_Type (Value.Max_Uploads)
        or else (Value.Max_Uploads = 0 and then Value.Is_Truncated)
      then
         raise Malformed_Upload_Listing with
           "inconsistent ListMultipartUploads page size";
      elsif Value.Is_Truncated and then US.Length (Value.Next_Key_Marker) = 0
      then
         raise Malformed_Upload_Listing with
           "truncated multipart upload page lacks next key marker";
      elsif not Value.Is_Truncated
        and then
          (US.Length (Value.Next_Key_Marker) > 0
           or else US.Length (Value.Next_Upload_ID_Marker) > 0)
      then
         raise Malformed_Upload_Listing with
           "final multipart upload page has next markers";
      elsif Value.Is_Truncated
        and then US.Length (Value.Delimiter) = 0
        and then US.Length (Value.Next_Upload_ID_Marker) = 0
      then
         raise Malformed_Upload_Listing with
           "truncated ungrouped page lacks paired next markers";
      elsif Value.Is_Truncated
        and then
          (US.To_String (Value.Next_Key_Marker) <
             US.To_String (Value.Key_Marker)
           or else
             (Value.Next_Key_Marker = Value.Key_Marker
              and then
                (US.Length (Value.Next_Upload_ID_Marker) = 0
                 or else Value.Next_Upload_ID_Marker =
                   Value.Upload_ID_Marker)))
      then
         raise Malformed_Upload_Listing with
           "ListMultipartUploads next cursor does not advance";
      elsif US.Length (Value.Encoding_Type) > 0
        and then not Valid_Enumeration
          (US.To_String (Value.Encoding_Type), Output_Member_Shape (12))
      then
         raise Malformed_Upload_Listing with
           "invalid ListMultipartUploads encoding type";
      end if;

      for Upload of Value.Uploads loop
         if US.Length (Upload.Upload_ID) = 0
           or else US.Length (Upload.Key) = 0
           or else US.Length (Upload.Initiated) = 0
           or else not Valid_ISO_8601_Timestamp
             (US.To_String (Upload.Initiated))
           or else
             (US.Length (Value.Prefix) > 0
              and then not Starts_With
                (US.To_String (Upload.Key), US.To_String (Value.Prefix)))
           or else
             (US.Length (Upload.Storage_Class) > 0
              and then not Valid_Enumeration
                (US.To_String (Upload.Storage_Class), Upload_Member_Shape (4)))
           or else not Valid_Identity (Upload.Has_Owner, Upload.Owner)
           or else not Valid_Identity
             (Upload.Has_Initiator, Upload.Initiator)
           or else
             (US.Length (Upload.Checksum_Algorithm) > 0
              and then not Valid_Enumeration
                (US.To_String (Upload.Checksum_Algorithm),
                 Upload_Member_Shape (7)))
           or else
             (US.Length (Upload.Checksum_Type) > 0
              and then
                (US.Length (Upload.Checksum_Algorithm) = 0
                 or else not Valid_Enumeration
                   (US.To_String (Upload.Checksum_Type),
                    Upload_Member_Shape (8))))
         then
            raise Malformed_Upload_Listing with
              "invalid multipart upload entry";
         end if;
      end loop;
      if not Value.Uploads.Is_Empty then
         for Left in Value.Uploads.First_Index .. Value.Uploads.Last_Index loop
            if Left < Value.Uploads.Last_Index then
               for Right in Positive'Succ (Left) ..
                 Value.Uploads.Last_Index
               loop
                  if Value.Uploads (Left).Key = Value.Uploads (Right).Key
                    and then Value.Uploads (Left).Upload_ID =
                      Value.Uploads (Right).Upload_ID
                  then
                     raise Malformed_Upload_Listing with
                       "duplicate multipart upload";
                  end if;
               end loop;
            end if;
         end loop;
      end if;

      for Prefix of Value.Common_Prefixes loop
         if US.Length (Prefix) = 0
           or else
             (US.Length (Value.Prefix) > 0
              and then not Starts_With
                (US.To_String (Prefix), US.To_String (Value.Prefix)))
           or else
             (US.Length (Value.Delimiter) > 0
              and then
                (US.Length (Value.Delimiter) > US.Length (Prefix)
                 or else US.Tail
                   (Prefix, US.Length (Value.Delimiter)) /= Value.Delimiter))
         then
            raise Malformed_Upload_Listing with
              "invalid multipart common prefix";
         end if;
         for Upload of Value.Uploads loop
            if Starts_With
              (US.To_String (Upload.Key), US.To_String (Prefix))
            then
               raise Malformed_Upload_Listing with
                 "grouped upload also appears in upload list";
            end if;
         end loop;
      end loop;
      if not Value.Common_Prefixes.Is_Empty then
         for Left in Value.Common_Prefixes.First_Index ..
           Value.Common_Prefixes.Last_Index
         loop
            if Left < Value.Common_Prefixes.Last_Index then
               for Right in Positive'Succ (Left) ..
                 Value.Common_Prefixes.Last_Index
               loop
                  if Value.Common_Prefixes (Left) =
                    Value.Common_Prefixes (Right)
                  then
                     raise Malformed_Upload_Listing with
                       "duplicate multipart common prefix";
                  end if;
               end loop;
            end if;
         end loop;
      end if;
   end Validate;

   function Parse_List_Multipart_Uploads
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Multipart_Uploads_Result
   is
      Handler : aliased Listing_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if not Handler.Seen (Bucket_Field)
        or else not Handler.Seen (Max_Uploads_Field)
        or else not Handler.Seen (Is_Truncated_Field)
      then
         raise Malformed_Upload_Listing with
           "ListMultipartUploads lacks required fields";
      end if;
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when Occurrence : XML.XML_Error =>
         raise Malformed_Upload_Listing with
           "malformed ListMultipartUploads XML: " &
           Ada.Exceptions.Exception_Message (Occurrence);
   end Parse_List_Multipart_Uploads;

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   procedure Append_Optional
     (Target : in out US.Unbounded_String; Name, Value : String) is
   begin
      if Value'Length > 0 then
         US.Append (Target, Element (Name, Value));
      end if;
   end Append_Optional;

   procedure Append_Identity
     (Target : in out US.Unbounded_String; Name : String;
      Value : Multipart.Multipart_Identity) is
   begin
      US.Append (Target, "<" & Name & ">");
      Append_Optional (Target, "ID", US.To_String (Value.ID));
      Append_Optional
        (Target, "DisplayName", US.To_String (Value.Display_Name));
      US.Append (Target, "</" & Name & ">");
   end Append_Identity;

   function Page_Size_Image (Value : Core.Page_Size) return String is
     (Ada.Strings.Fixed.Trim
        (Core.Page_Size'Image (Value), Ada.Strings.Both));

   function Serialize_List_Multipart_Uploads
     (Value : List_Multipart_Uploads_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<ListMultipartUploadsResult xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">" &
         Element ("Bucket", US.To_String (Value.Bucket)));
      Append_Optional
        (Result, "KeyMarker", US.To_String (Value.Key_Marker));
      Append_Optional
        (Result, "UploadIdMarker", US.To_String (Value.Upload_ID_Marker));
      Append_Optional
        (Result, "NextKeyMarker", US.To_String (Value.Next_Key_Marker));
      Append_Optional
        (Result, "NextUploadIdMarker",
         US.To_String (Value.Next_Upload_ID_Marker));
      Append_Optional (Result, "Prefix", US.To_String (Value.Prefix));
      Append_Optional (Result, "Delimiter", US.To_String (Value.Delimiter));
      US.Append
        (Result,
         Element ("MaxUploads", Page_Size_Image (Value.Max_Uploads)) &
         Element
           ("IsTruncated",
            (if Value.Is_Truncated then "true" else "false")));
      for Upload of Value.Uploads loop
         US.Append
           (Result,
            "<Upload>" &
            Element ("UploadId", US.To_String (Upload.Upload_ID)) &
            Element ("Key", US.To_String (Upload.Key)) &
            Element ("Initiated", US.To_String (Upload.Initiated)));
         Append_Optional
           (Result, "StorageClass", US.To_String (Upload.Storage_Class));
         if Upload.Has_Owner then
            Append_Identity (Result, "Owner", Upload.Owner);
         end if;
         if Upload.Has_Initiator then
            Append_Identity (Result, "Initiator", Upload.Initiator);
         end if;
         Append_Optional
           (Result, "ChecksumAlgorithm",
            US.To_String (Upload.Checksum_Algorithm));
         Append_Optional
           (Result, "ChecksumType", US.To_String (Upload.Checksum_Type));
         US.Append (Result, "</Upload>");
      end loop;
      for Prefix of Value.Common_Prefixes loop
         US.Append
           (Result,
            "<CommonPrefixes>" &
            Element ("Prefix", US.To_String (Prefix)) &
            "</CommonPrefixes>");
      end loop;
      Append_Optional
        (Result, "EncodingType", US.To_String (Value.Encoding_Type));
      US.Append (Result, "</ListMultipartUploadsResult>");
      return US.To_String (Result);
   end Serialize_List_Multipart_Uploads;

end Flyology.Object_Storage.S3.Multipart_Uploads;
