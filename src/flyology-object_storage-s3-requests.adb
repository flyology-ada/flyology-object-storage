package body Flyology.Object_Storage.S3.Requests
  with SPARK_Mode => On
is

   function Character_At
     (Value : String; Offset : Positive) return Character is
     (Value (Value'First + (Offset - 1)))
   with Pre => Offset <= Value'Length;

   function Is_Hex (Value : Character) return Boolean is
     (Value in '0' .. '9' or else Value in 'a' .. 'f'
      or else Value in 'A' .. 'F');

   function Hex_Value (Value : Character) return Natural is
     (if Value in '0' .. '9' then
         Character'Pos (Value) - Character'Pos ('0')
      elsif Value in 'a' .. 'f' then
         Character'Pos (Value) - Character'Pos ('a') + 10
      elsif Value in 'A' .. 'F' then
         Character'Pos (Value) - Character'Pos ('A') + 10
      else 0);

   function Valid_Escapes (Value : String) return Boolean
     with Pre => Value'Length <= Maximum_Target_Length
   is
      subtype Escape_Cursor is
        Positive range 1 .. Maximum_Target_Length + 1;
      Offset : Escape_Cursor := 1;
   begin
      while Offset <= Value'Length loop
         if Character_At (Value, Offset) = '%' then
            if Offset + 2 > Value'Length
              or else not Is_Hex (Character_At (Value, Offset + 1))
              or else not Is_Hex (Character_At (Value, Offset + 2))
            then
               return False;
            end if;
            Offset := Offset + 3;
         else
            Offset := Offset + 1;
         end if;
         pragma Loop_Invariant (Offset <= Value'Length + 1);
         pragma Loop_Variant (Increases => Offset);
      end loop;
      return True;
   end Valid_Escapes;

   function Decode
     (Value : String; First, Last : Target_Offset) return String
   is
      subtype Decode_Cursor is
        Natural range 0 .. Maximum_Target_Length + 1;
      Result : String (1 .. Maximum_Target_Length)
        with Relaxed_Initialization;
      Input  : Decode_Cursor := First;
      Output : Target_Offset := 0;
      Byte   : Natural;
   begin
      if First = 0 or else Last < First or else Last > Value'Length then
         return "";
      end if;
      while Input <= Last loop
         Output := Output + 1;
         if Character_At (Value, Positive (Input)) = '%' then
            if Input + 2 > Last
              or else not Is_Hex
                (Character_At (Value, Positive (Input + 1)))
              or else not Is_Hex
                (Character_At (Value, Positive (Input + 2)))
            then
               return "";
            end if;
            Byte :=
              16 * Hex_Value
                (Character_At (Value, Positive (Input + 1))) +
              Hex_Value (Character_At (Value, Positive (Input + 2)));
            Result (Positive (Output)) := Character'Val (Byte);
            Input := Input + 3;
         else
            Result (Positive (Output)) :=
              Character_At (Value, Positive (Input));
            Input := Input + 1;
         end if;
         pragma Loop_Invariant (Input in First + 1 .. Last + 1);
         pragma Loop_Invariant (Output <= Input - First);
         pragma Loop_Invariant (Result (1 .. Output)'Initialized);
         pragma Loop_Variant (Increases => Input);
      end loop;
      return Result (1 .. Output);
   end Decode;

   function Parse_Target (Value : String) return Target_Result
   is
      Invalid : constant Target_Result := (others => <>);
      Path_Last    : Target_Offset;
      Query_Marker : Target_Offset := 0;
      Bucket_End   : Target_Offset := 0;
   begin
      if Value'Length = 0
        or else Value'Length > Maximum_Target_Length
        or else Character_At (Value, 1) /= '/'
        or else not Valid_Escapes (Value)
      then
         return Invalid;
      end if;
      for Offset in 1 .. Value'Length loop
         if Character_At (Value, Offset) = '#' then
            return Invalid;
         elsif Character_At (Value, Offset) = '?'
           and then Query_Marker = 0
         then
            Query_Marker := Offset;
         end if;
         pragma Loop_Invariant
           (Query_Marker = 0 or else Query_Marker in 1 .. Offset);
      end loop;
      Path_Last :=
        (if Query_Marker = 0 then Value'Length else Query_Marker - 1);
      if Path_Last = 0 then
         return Invalid;
      end if;
      if Path_Last = 1 then
         return
           (Status       => Target_Parsed,
            Kind         => Service_Target,
            Has_Query    => Query_Marker /= 0,
            Query_First  =>
              (if Query_Marker = 0 or else Query_Marker = Value'Length
               then 0 else Query_Marker + 1),
            Query_Last   =>
              (if Query_Marker = 0 or else Query_Marker = Value'Length
               then 0 else Value'Length),
            others       => <>);
      end if;

      for Offset in 2 .. Path_Last loop
         if Character_At (Value, Offset) = '/' then
            Bucket_End := Offset - 1;
            exit;
         end if;
      end loop;
      if Bucket_End = 0 then
         Bucket_End := Path_Last;
      end if;
      declare
         Bucket : constant String := Decode (Value, 2, Bucket_End);
      begin
         if not Valid_Bucket_Name (Bucket) then
            return Invalid;
         end if;
      end;

      if Bucket_End = Path_Last or else Bucket_End + 1 = Path_Last then
         return
           (Status       => Target_Parsed,
            Kind         => Bucket_Target,
            Bucket_First => 2,
            Bucket_Last  => Bucket_End,
            Has_Query    => Query_Marker /= 0,
            Query_First  =>
              (if Query_Marker = 0 or else Query_Marker = Value'Length
               then 0 else Query_Marker + 1),
            Query_Last   =>
              (if Query_Marker = 0 or else Query_Marker = Value'Length
               then 0 else Value'Length),
            others       => <>);
      end if;
      declare
         Key_First : constant Target_Offset := Bucket_End + 2;
         Key       : constant String := Decode (Value, Key_First, Path_Last);
      begin
         if not Valid_Object_Key (Key) then
            return Invalid;
         end if;
         return
           (Status       => Target_Parsed,
            Kind         => Object_Target,
            Bucket_First => 2,
            Bucket_Last  => Bucket_End,
            Key_First    => Key_First,
            Key_Last     => Path_Last,
            Has_Query    => Query_Marker /= 0,
            Query_First  =>
              (if Query_Marker = 0 or else Query_Marker = Value'Length
               then 0 else Query_Marker + 1),
            Query_Last   =>
              (if Query_Marker = 0 or else Query_Marker = Value'Length
               then 0 else Value'Length));
      end;
   end Parse_Target;

   function Bucket_Name
     (Value : String; Parsed : Target_Result) return String is
   begin
      if Parsed.Status /= Target_Parsed
        or else Parsed.Kind not in Bucket_Target | Object_Target
        or else Parsed.Bucket_First = 0
        or else Parsed.Bucket_Last > Value'Length
      then
         return "";
      end if;
      return Decode (Value, Parsed.Bucket_First, Parsed.Bucket_Last);
   end Bucket_Name;

   function Object_Key
     (Value : String; Parsed : Target_Result) return String is
   begin
      if Parsed.Status /= Target_Parsed
        or else Parsed.Kind /= Object_Target
        or else Parsed.Key_First = 0
        or else Parsed.Key_Last > Value'Length
      then
         return "";
      end if;
      return Decode (Value, Parsed.Key_First, Parsed.Key_Last);
   end Object_Key;

   function Query_String
     (Value : String; Parsed : Target_Result) return String is
   begin
      if Parsed.Status /= Target_Parsed
        or else not Parsed.Has_Query
        or else Parsed.Query_First = 0
        or else Parsed.Query_Last < Parsed.Query_First
        or else Parsed.Query_Last > Value'Length
      then
         return "";
      end if;
      return
        Value
          (Value'First + (Parsed.Query_First - 1) ..
           Value'First + (Parsed.Query_Last - 1));
   end Query_String;

end Flyology.Object_Storage.S3.Requests;
