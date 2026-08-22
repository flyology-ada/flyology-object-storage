with Ada.Wide_Wide_Characters.Unicode;

package body Flyology.Object_Storage
  with SPARK_Mode => On
is

   package Unicode renames Ada.Wide_Wide_Characters.Unicode;

   Maximum_Condition_Length : constant := 16_384;
   Maximum_Entity_Tag_Length : constant := 8_192;

   function Valid_Object_Delete_ETag_Condition
     (Value : String) return Boolean
   is
      Quoted : constant Boolean :=
        Value'Length >= 2
        and then Value (Value'First) = '"'
        and then Value (Value'Last) = '"';
   begin
      if Value'Length = 0 or else Value'Length > Maximum_Entity_Tag_Length then
         return False;
      elsif Value = "*" then
         return True;
      elsif Value (Value'First) = '"' or else Value (Value'Last) = '"' then
         if not Quoted or else Value'Length = 2 then
            return False;
         end if;
      end if;
      for Position in Value'Range loop
         if Character'Pos (Value (Position)) <= 16#20#
           or else Character'Pos (Value (Position)) = 16#7F#
           or else Value (Position) = '*'
           or else Value (Position) = ','
           or else
             (Value (Position) = '"'
              and then
                (not Quoted
                 or else Position not in Value'First | Value'Last))
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Object_Delete_ETag_Condition;

   function Evaluate_Object_Delete_Conditions
     (Has_ETag               : Boolean;
      ETag                   : String;
      Has_Last_Modified_Time : Boolean;
      Last_Modified_Time     : Long_Long_Integer;
      Has_Size               : Boolean;
      Expected_Size          : Byte_Count;
      Exists                 : Boolean;
      Entity_Tag             : String;
      Modified               : Unix_Time;
      Size                   : Byte_Count) return Status
   is
      ETag_Matches : Boolean := True;
   begin
      if Has_ETag and then not Valid_Object_Delete_ETag_Condition (ETag) then
         return Invalid_Request;
      elsif not Exists then
         if Has_ETag or else Has_Last_Modified_Time or else Has_Size then
            return Not_Found;
         else
            return Success;
         end if;
      end if;

      if Has_ETag then
         ETag_Matches := ETag = "*" or else ETag = Entity_Tag;
         if not ETag_Matches
           and then Entity_Tag'Length <= Maximum_Entity_Tag_Length
           and then ETag'Length = Entity_Tag'Length + 2
           and then ETag (ETag'First) = '"'
           and then ETag (ETag'Last) = '"'
         then
            ETag_Matches :=
              ETag (ETag'First + 1 .. ETag'Last - 1) = Entity_Tag;
         end if;
      end if;

      if not ETag_Matches
        or else
          (Has_Last_Modified_Time
           and then Last_Modified_Time /= Long_Long_Integer (Modified))
        or else (Has_Size and then Expected_Size /= Size)
      then
         return Precondition_Failed;
      else
         return Success;
      end if;
   end Evaluate_Object_Delete_Conditions;

   function Character_At (Value : String; Offset : Positive)
      return Character
   with Pre => Offset <= Value'Length;

   function Character_At (Value : String; Offset : Positive)
      return Character is
     (Value (Value'First + (Offset - 1)));

   procedure Read_Entity_Tag_List
     (Value      : String;
      Entity_Tag : String;
      Weak_Match : Boolean;
      Valid      : out Boolean;
      Matches    : out Boolean)
   with Always_Terminates
   is
      Cursor : Natural := 1;
      Length : constant Natural := Value'Length;
      Remaining_Items : Natural;

      procedure Skip_Whitespace
      with
        Pre => Length <= Maximum_Condition_Length
          and then Cursor in 1 .. Maximum_Condition_Length + 1,
        Post => Cursor in 1 .. Maximum_Condition_Length + 1,
        Always_Terminates
      is
      begin
         while Cursor <= Length
           and then Character_At (Value, Positive (Cursor)) in ' ' | ASCII.HT
         loop
            pragma Loop_Invariant
              (Cursor in 1 .. Maximum_Condition_Length);
            pragma Loop_Variant (Increases => Cursor);
            Cursor := Cursor + 1;
         end loop;
      end Skip_Whitespace;

      function Same_Tag (First, Last : Natural) return Boolean
      with
        Pre => Length <= Maximum_Condition_Length
          and then First >= 1
          and then First <= Last
          and then Last <= Length
      is
         Tag_Length : constant Natural := Last - First;
      begin
         if Tag_Length /= Entity_Tag'Length then
            return False;
         elsif Tag_Length = 0 then
            return True;
         end if;
         for Offset in 0 .. Tag_Length - 1 loop
            pragma Loop_Invariant (First + Offset < Last);
            if Character_At (Value, Positive (First + Offset)) /=
              Character_At (Entity_Tag, Offset + 1)
            then
               return False;
            end if;
         end loop;
         return True;
      end Same_Tag;
   begin
      Valid := False;
      Matches := False;
      if Length > Maximum_Condition_Length
        or else Entity_Tag'Length > Maximum_Entity_Tag_Length
      then
         return;
      end if;
      Remaining_Items := Length + 1;
      Skip_Whitespace;
      if Cursor > Length then
         return;
      elsif Character_At (Value, Positive (Cursor)) = '*' then
         Cursor := Cursor + 1;
         Skip_Whitespace;
         Valid := Cursor > Length;
         Matches := Valid;
         return;
      end if;

      loop
         pragma Loop_Invariant
           (Length <= Maximum_Condition_Length
            and then Cursor in 1 .. Maximum_Condition_Length + 1
            and then Remaining_Items <= Maximum_Condition_Length + 1);
         pragma Loop_Variant (Decreases => Remaining_Items);
         Skip_Whitespace;
         if Cursor > Length then
            return;
         end if;
         declare
            Weak : Boolean := False;
            First : Natural;
         begin
            if Cursor < Length
              and then Character_At (Value, Positive (Cursor)) = 'W'
              and then Character_At (Value, Positive (Cursor + 1)) = '/'
            then
               Weak := True;
               Cursor := Cursor + 2;
            end if;
            if Cursor > Length
              or else Character_At (Value, Positive (Cursor)) /= '"'
            then
               return;
            end if;
            Cursor := Cursor + 1;
            First := Cursor;
            while Cursor <= Length
              and then Character_At (Value, Positive (Cursor)) /= '"'
            loop
               pragma Loop_Invariant
                 (Cursor in 1 .. Maximum_Condition_Length);
               pragma Loop_Variant (Increases => Cursor);
               declare
                  Item : constant Character :=
                    Character_At (Value, Positive (Cursor));
               begin
                  if Character'Pos (Item) < 16#21#
                    or else Character'Pos (Item) = 16#7F#
                  then
                     return;
                  end if;
               end;
               Cursor := Cursor + 1;
            end loop;
            if Cursor > Length then
               return;
            end if;
            if First > Cursor then
               return;
            elsif (not Weak or else Weak_Match)
              and then Same_Tag (First, Cursor)
            then
               Matches := True;
            end if;
            Cursor := Cursor + 1;
         end;
         Skip_Whitespace;
         if Cursor > Length then
            Valid := True;
            return;
         elsif Character_At (Value, Positive (Cursor)) /= ',' then
            return;
         end if;
         Cursor := Cursor + 1;
         if Remaining_Items = 0 then
            return;
         end if;
         Remaining_Items := Remaining_Items - 1;
      end loop;
   end Read_Entity_Tag_List;

   function Evaluate_Object_Write_Conditions
     (If_Match, If_None_Match : String;
      Exists                  : Boolean;
      Entity_Tag              : String) return Status
   is
      Valid, Matches : Boolean;
   begin
      if If_Match'Length > 0 then
         Read_Entity_Tag_List
           (If_Match, Entity_Tag, False, Valid, Matches);
         if not Valid then
            return Invalid_Request;
         elsif not Exists or else not Matches then
            return Precondition_Failed;
         end if;
      end if;
      if If_None_Match'Length > 0 then
         Read_Entity_Tag_List
           (If_None_Match, Entity_Tag, True, Valid, Matches);
         if not Valid then
            return Invalid_Request;
         elsif Exists and then Matches then
            return Precondition_Failed;
         end if;
      end if;
      return Success;
   end Evaluate_Object_Write_Conditions;

   function Valid_Object_Read_Entity_Tag_Condition
     (Value : String) return Boolean is
     (Value'Length > 0
      and then Evaluate_Object_Read_Conditions
        (If_Match => Value,
         If_None_Match => "",
         Has_If_Modified_Since => False,
         If_Modified_Since => 0,
         Has_If_Unmodified_Since => False,
         If_Unmodified_Since => 0,
         Entity_Tag => "",
         Modified => 0) /= Invalid_Request);

   function Valid_Object_Write_Conditions
     (If_Match, If_None_Match : String) return Boolean is
     ((If_Match'Length = 0
       or else Valid_Object_Read_Entity_Tag_Condition (If_Match))
      and then
        (If_None_Match'Length = 0
         or else Valid_Object_Read_Entity_Tag_Condition (If_None_Match)));

   function Evaluate_Object_Read_Conditions
     (If_Match, If_None_Match : String;
      Has_If_Modified_Since   : Boolean;
      If_Modified_Since       : Long_Long_Integer;
      Has_If_Unmodified_Since : Boolean;
      If_Unmodified_Since     : Long_Long_Integer;
      Entity_Tag              : String;
      Modified                : Unix_Time) return Status
   is
      Valid, Matches : Boolean;
   begin
      if If_Match'Length > 0 then
         Read_Entity_Tag_List
           (If_Match, Entity_Tag, False, Valid, Matches);
         if not Valid then
            return Invalid_Request;
         elsif not Matches then
            return Precondition_Failed;
         end if;
      elsif Has_If_Unmodified_Since
        and then Long_Long_Integer (Modified) > If_Unmodified_Since
      then
         return Precondition_Failed;
      end if;

      if If_None_Match'Length > 0 then
         Read_Entity_Tag_List
           (If_None_Match, Entity_Tag, True, Valid, Matches);
         if not Valid then
            return Invalid_Request;
         elsif Matches then
            return Not_Modified;
         end if;
      elsif Has_If_Modified_Since
        and then Long_Long_Integer (Modified) <= If_Modified_Since
      then
         return Not_Modified;
      end if;
      return Success;
   end Evaluate_Object_Read_Conditions;

   function Evaluate_Object_Copy_Conditions
     (If_Match, If_None_Match : String;
      Has_If_Modified_Since   : Boolean;
      If_Modified_Since       : Long_Long_Integer;
      Has_If_Unmodified_Since : Boolean;
      If_Unmodified_Since     : Long_Long_Integer;
      Entity_Tag              : String;
      Modified                : Unix_Time) return Status
   is
      Read_Result : constant Status := Evaluate_Object_Read_Conditions
        (If_Match,
         If_None_Match,
         Has_If_Modified_Since,
         If_Modified_Since,
         Has_If_Unmodified_Since,
         If_Unmodified_Since,
         Entity_Tag,
         Modified);
   begin
      return
        (if Read_Result = Not_Modified
         then Precondition_Failed
         else Read_Result);
   end Evaluate_Object_Copy_Conditions;

   function Merge_Bucket_Versioning
     (Current, Update : Bucket_Versioning_Configuration)
      return Bucket_Versioning_Configuration is
     (Status =>
        (if Update.Status = Versioning_Unconfigured
         then Current.Status else Update.Status),
      MFA_Delete =>
        (if Update.MFA_Delete = MFA_Delete_Unconfigured
         then Current.MFA_Delete else Update.MFA_Delete));

   function Starts_With (Value, Prefix : String) return Boolean is
     (Value'Length >= Prefix'Length
      and then Value
        (Value'First .. Value'First - 1 + Prefix'Length) = Prefix);

   function Listing_Matches_Prefix
     (Key, Prefix : String) return Boolean is
     (Starts_With (Key, Prefix));

   function Listing_Follows_Cursor
     (Projected_Key, After : String) return Boolean is
     (Projected_Key > After);

   function Ends_With (Value, Suffix : String) return Boolean is
     (Suffix'Length = 0
      or else
        (Value'Length >= Suffix'Length
         and then Value
           (Value'Last - (Suffix'Length - 1) .. Value'Last) = Suffix));

   function Looks_Like_IPv4 (Value : String) return Boolean is
      subtype Part_Count is Natural range 0 .. 3;
      subtype Decimal_Digit_Count is Natural range 0 .. 3;
      subtype Octet is Natural range 0 .. 255;

      Parts       : Part_Count := 0;
      Digit_Count : Decimal_Digit_Count := 0;
      Octet_Value : Octet := 0;
   begin
      for Character_Value of Value loop
         if Character_Value in '0' .. '9' then
            if Digit_Count = Decimal_Digit_Count'Last then
               return False;
            end if;
            Digit_Count := Digit_Count + 1;
            declare
               subtype Decimal_Digit is Natural range 0 .. 9;
               Digit : constant Decimal_Digit :=
                 Character'Pos (Character_Value) - Character'Pos ('0');
            begin
               if Octet_Value > 25
                 or else (Octet_Value = 25 and then Digit > 5)
               then
                  return False;
               end if;
               Octet_Value := Octet_Value * 10 + Digit;
            end;
         elsif Character_Value = '.' and then Digit_Count > 0 then
            if Parts = Part_Count'Last then
               return False;
            end if;
            Parts := Parts + 1;
            Digit_Count := 0;
            Octet_Value := 0;
         else
            return False;
         end if;
      end loop;
      return Parts = 3 and then Digit_Count > 0;
   end Looks_Like_IPv4;

   function Valid_Bucket_Name (Value : String) return Boolean is
      Previous_Dot : Boolean := False;
      Previous_Hyphen : Boolean := False;
   begin
      if Value'Length not in 3 .. 63
        or else Value (Value'First) in '.' | '-'
        or else Value (Value'Last) in '.' | '-'
        or else Looks_Like_IPv4 (Value)
        or else Starts_With (Value, "xn--")
        or else Starts_With (Value, "sthree-")
        or else Starts_With (Value, "amzn-s3-demo-")
        or else Ends_With (Value, "-s3alias")
        or else Ends_With (Value, "--ol-s3")
        or else Ends_With (Value, ".mrap")
        or else Ends_With (Value, "--x-s3")
        or else Ends_With (Value, "--table-s3")
        or else Ends_With (Value, "-an")
      then
         return False;
      end if;

      for Character_Value of Value loop
         if not (Character_Value in 'a' .. 'z'
                 or else Character_Value in '0' .. '9'
                 or else Character_Value in '.' | '-')
         then
            return False;
         end if;
         if Character_Value = '.'
           and then (Previous_Dot or else Previous_Hyphen)
         then
            return False;
         elsif Character_Value = '-'
           and then Previous_Dot
         then
            return False;
         end if;
         Previous_Dot := Character_Value = '.';
         Previous_Hyphen := Character_Value = '-';
      end loop;
      return True;
   end Valid_Bucket_Name;

   function Valid_Object_Key (Value : String) return Boolean is
   begin
      if Value'Length not in 1 .. 1_024 then
         return False;
      end if;
      for Character_Value of Value loop
         if Character_Value = Character'Val (0) then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Object_Key;

   function Valid_Object_Metadata
     (Metadata : Object_Metadata; Content_Type : String) return Boolean
   is
      System_Bytes : Natural := 0;
      User_Bytes   : Natural := 0;

      function Valid_UTF8_Header_Value (Value : String) return Boolean is
         Cursor : Integer := Value'First;

         function Byte_At (Offset : Natural) return Natural is
           (Character'Pos (Value (Cursor + Integer (Offset))))
         with Pre =>
           Cursor in Value'Range
           and then Offset <= Natural (Value'Last - Cursor);

         function Continuation (Offset : Natural) return Boolean is
           (Offset <= Natural (Value'Last - Cursor)
            and then Byte_At (Offset) in 16#80# .. 16#BF#)
         with Pre => Cursor in Value'Range;
      begin
         while Cursor <= Value'Last loop
            pragma Loop_Invariant (Cursor in Value'Range);
            pragma Loop_Variant (Decreases => Value'Last - Cursor);
            declare
               First : constant Natural := Byte_At (0);
               Width : Positive;
            begin
               if First in 16#20# .. 16#7E# then
                  Width := 1;
               elsif First in 16#C2# .. 16#DF#
                 and then Continuation (1)
               then
                  Width := 2;
               elsif First in 16#E0# .. 16#EF#
                 and then Continuation (1) and then Continuation (2)
                 and then (First /= 16#E0# or else Byte_At (1) >= 16#A0#)
                 and then (First /= 16#ED# or else Byte_At (1) <= 16#9F#)
               then
                  Width := 3;
               elsif First in 16#F0# .. 16#F4#
                 and then Continuation (1) and then Continuation (2)
                 and then Continuation (3)
                 and then (First /= 16#F0# or else Byte_At (1) >= 16#90#)
                 and then (First /= 16#F4# or else Byte_At (1) <= 16#8F#)
               then
                  Width := 4;
               else
                  return False;
               end if;
               pragma Assert
                 (Width - 1 <= Natural (Value'Last - Cursor));
               if Width - 1 = Natural (Value'Last - Cursor) then
                  return True;
               end if;
               Cursor := Cursor + Width;
            end;
         end loop;
         return True;
      end Valid_UTF8_Header_Value;

      function Valid_System
        (Item : Optional_Metadata_Value; Name : String) return Boolean
      is
         Value : constant String :=
           Ada.Strings.Unbounded.To_String (Item.Value);
      begin
         if not Item.Is_Set then
            return Value'Length = 0;
         elsif Value'Length > Maximum_System_Metadata_Value_Bytes then
            return False;
         end if;
         for Character_Value of Value loop
            if Character'Pos (Character_Value) not in 16#20# .. 16#7E# then
               return False;
            end if;
         end loop;
         System_Bytes := System_Bytes + Name'Length + Value'Length;
         return System_Bytes <= Maximum_System_Metadata_Bytes;
      end Valid_System;

      function Valid_User_Key (Value : String) return Boolean is
      begin
         if Value'Length not in 1 .. Maximum_User_Metadata_Key_Bytes then
            return False;
         end if;
         for Character_Value of Value loop
            if not (Character_Value in 'a' .. 'z' | '0' .. '9'
                    or else Character_Value in
                      '!' | '#' | '$' | '%' | '&' | ''' | '*' | '+' | '-' |
                      '.' | '^' | '_' | '`' | '|' | '~')
            then
               return False;
            end if;
         end loop;
         return True;
      end Valid_User_Key;
   begin
      if Content_Type'Length > Maximum_System_Metadata_Value_Bytes then
         return False;
      end if;
      for Character_Value of Content_Type loop
         if Character'Pos (Character_Value) not in 16#20# .. 16#7E# then
            return False;
         end if;
      end loop;
      if Content_Type'Length > 0 then
         System_Bytes := 12 + Content_Type'Length;
      end if;
      if not Valid_System (Metadata.Cache_Control, "Cache-Control")
        or else not Valid_System
          (Metadata.Content_Disposition, "Content-Disposition")
        or else not Valid_System
          (Metadata.Content_Encoding, "Content-Encoding")
        or else not Valid_System
          (Metadata.Content_Language, "Content-Language")
        or else not Valid_System
          (Metadata.Website_Redirect_Location,
           "x-amz-website-redirect-location")
      then
         return False;
      end if;

      --  IMF-fixdate is always 29 US-ASCII bytes.  An absent typed value must
      --  retain no hidden timestamp, matching Optional_Metadata_Value.
      if not Metadata.Expires.Is_Set and then Metadata.Expires.Value /= 0 then
         return False;
      elsif Metadata.Expires.Is_Set then
         if System_Bytes > Maximum_System_Metadata_Bytes - 36 then
            return False;
         end if;
         System_Bytes := System_Bytes + 36;
      end if;

      for Index in User_Metadata_Index loop
         declare
            Key : constant String := Ada.Strings.Unbounded.To_String
              (Metadata.User.Items (Index).Key);
            Value : constant String := Ada.Strings.Unbounded.To_String
              (Metadata.User.Items (Index).Value);
         begin
            if Index <= Metadata.User.Length then
               if not Valid_User_Key (Key)
                 or else Key'Length >
                   Maximum_User_Metadata_Bytes - User_Bytes
                 or else Value'Length >
                   Maximum_User_Metadata_Bytes - User_Bytes - Key'Length
                 or else not Valid_UTF8_Header_Value (Value)
               then
                  return False;
               end if;
               for Previous in 1 .. Index - 1 loop
                  if Ada.Strings.Unbounded."="
                    (Metadata.User.Items (Previous).Key,
                     Metadata.User.Items (Index).Key)
                  then
                     return False;
                  end if;
               end loop;
               User_Bytes := User_Bytes + Key'Length + Value'Length;
            elsif Key'Length /= 0 or else Value'Length /= 0 then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Valid_Object_Metadata;

   function Valid_Object_Tag_Set (Tags : Object_Tag_Set) return Boolean is
   begin
      for Index in 1 .. Tags.Length loop
         declare
            Key : constant String :=
              Ada.Strings.Unbounded.To_String (Tags.Items (Index).Key);
            Value : constant String :=
              Ada.Strings.Unbounded.To_String (Tags.Items (Index).Value);
         begin
            if Key'Length not in 1 .. 512 or else Value'Length > 1_024 then
               return False;
            end if;
            for Character_Value of Key loop
               if Character_Value = Character'Val (0) then
                  return False;
               end if;
            end loop;
            for Character_Value of Value loop
               if Character_Value = Character'Val (0) then
                  return False;
               end if;
            end loop;
            for Previous in 1 .. Index - 1 loop
               if Ada.Strings.Unbounded."="
                 (Tags.Items (Previous).Key, Tags.Items (Index).Key)
               then
                  return False;
               end if;
            end loop;
         end;
      end loop;
      return True;
   end Valid_Object_Tag_Set;

   function Valid_Tag_Text
     (Value         : String;
      Maximum       : Tag_Character_Limit;
      Empty_Allowed : Boolean) return Boolean
   is
      subtype Tag_Character_Count is
        Natural range 0 .. Tag_Character_Limit'Last;

      Cursor : Integer := Value'First;
      Count  : Tag_Character_Count := 0;

      function Byte_At (Offset : Natural) return Natural is
        (Character'Pos (Value (Cursor + Integer (Offset))))
        with Pre =>
          Cursor in Value'Range
          and then Offset <= Natural (Value'Last - Cursor);

      function Continuation (Offset : Natural) return Boolean is
        (Offset <= Natural (Value'Last - Cursor)
         and then Byte_At (Offset) in 16#80# .. 16#BF#)
        with Pre => Cursor in Value'Range;

      function Allowed (Code : Natural) return Boolean is
         Character_Value : constant Wide_Wide_Character :=
           Wide_Wide_Character'Val (Code);
         Category : constant Unicode.Category :=
           Unicode.Get_Category (Character_Value);
      begin
         return Category in
             Unicode.Lu | Unicode.Ll | Unicode.Lt | Unicode.Lm | Unicode.Lo |
             Unicode.Nd | Unicode.Nl | Unicode.No |
             Unicode.Zs | Unicode.Zl | Unicode.Zp
           or else Code in
             Character'Pos ('_') | Character'Pos ('.') |
             Character'Pos (':') | Character'Pos ('/') |
             Character'Pos ('=') | Character'Pos ('+') |
             Character'Pos ('-') | Character'Pos ('@');
      end Allowed;
   begin
      if Value'Length = 0 then
         return Empty_Allowed;
      end if;
      while Cursor <= Value'Last loop
         pragma Loop_Invariant (Cursor in Value'Range);
         pragma Loop_Invariant (Count <= Maximum);
         pragma Loop_Variant (Decreases => Value'Last - Cursor);
         declare
            First : constant Natural := Byte_At (0);
            Width : Positive;
            Code  : Natural;
         begin
            if First <= 16#7F# then
               Width := 1;
               Code := First;
            elsif First in 16#C2# .. 16#DF# and then Continuation (1) then
               Width := 2;
               Code := (First - 16#C0#) * 64 + (Byte_At (1) - 16#80#);
            elsif First in 16#E0# .. 16#EF#
              and then Continuation (1) and then Continuation (2)
              and then (First /= 16#E0# or else Byte_At (1) >= 16#A0#)
              and then (First /= 16#ED# or else Byte_At (1) <= 16#9F#)
            then
               Width := 3;
               Code := (First - 16#E0#) * 4_096
                 + (Byte_At (1) - 16#80#) * 64
                 + (Byte_At (2) - 16#80#);
            elsif First in 16#F0# .. 16#F4#
              and then Continuation (1) and then Continuation (2)
              and then Continuation (3)
              and then (First /= 16#F0# or else Byte_At (1) >= 16#90#)
              and then (First /= 16#F4# or else Byte_At (1) <= 16#8F#)
            then
               Width := 4;
               Code := (First - 16#F0#) * 262_144
                 + (Byte_At (1) - 16#80#) * 4_096
                 + (Byte_At (2) - 16#80#) * 64
                 + (Byte_At (3) - 16#80#);
            else
               return False;
            end if;

            pragma Assert
              (Width - 1 <= Natural (Value'Last - Cursor));

            if Count = Maximum then
               return False;
            end if;
            Count := Count + 1;
            if not Allowed (Code) then
               return False;
            end if;

            if Width - 1 = Natural (Value'Last - Cursor) then
               return True;
            end if;
            Cursor := Cursor + Width;
         end;
      end loop;
      return True;
   end Valid_Tag_Text;

   function Resolve_Range
     (Size : Byte_Count; Request : Byte_Range) return Range_Resolution
   is
      Effective_Last  : Byte_Count;
      Effective_First : Byte_Count;
   begin
      if Size = 0 then
         if Request.Kind = Whole_Range then
            return (Kind => Empty_Object_Range);
         else
            return (Kind => Unsatisfiable_Range);
         end if;
      end if;

      case Request.Kind is
         when Whole_Range =>
            return
              (Kind   => Satisfied_Range,
               First  => 0,
               Last   => Size - 1,
               Length => Size);

         when Bounded_Range =>
            if Request.First > Request.Last or else Request.First >= Size then
               return (Kind => Unsatisfiable_Range);
            end if;
            Effective_Last :=
              (if Request.Last < Size then Request.Last else Size - 1);
            return
              (Kind   => Satisfied_Range,
               First  => Request.First,
               Last   => Effective_Last,
               Length => Effective_Last - Request.First + 1);

         when Open_Ended_Range =>
            if Request.First >= Size then
               return (Kind => Unsatisfiable_Range);
            end if;
            return
              (Kind   => Satisfied_Range,
               First  => Request.First,
               Last   => Size - 1,
               Length => Size - Request.First);

         when Suffix_Range =>
            if Request.Count = 0 then
               return (Kind => Unsatisfiable_Range);
            end if;
            Effective_First :=
              (if Request.Count >= Size then 0 else Size - Request.Count);
            return
              (Kind   => Satisfied_Range,
               First  => Effective_First,
               Last   => Size - 1,
               Length => Size - Effective_First);
      end case;
   end Resolve_Range;

end Flyology.Object_Storage;
