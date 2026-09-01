with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.Deletions;
with Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.Wire_Core;
with GNAT.SHA256;

package body Flyology.Object_Storage.S3.Annotations is

   package US renames Ada.Strings.Unbounded;

   Maximum_Query_Bytes : constant := 8 * 1_024;
   Token_Prefix        : constant String := "fos1.";

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
               raise Malformed_Annotation_Request with
                 "invalid annotation query percent escape";
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

   function Operation_Name (Operation : Annotation_Operation) return String is
     (case Operation is
         when Put_Annotation    => "PutObjectAnnotation",
         when Get_Annotation    => "GetObjectAnnotation",
         when List_Annotations  => "ListObjectAnnotations",
         when Delete_Annotation => "DeleteObjectAnnotation");

   function Parse_Query
     (Query : String; Operation : Annotation_Operation)
      return Annotation_Request
   is
      Result : Annotation_Request :=
        (Annotation_Name        => US.Null_Unbounded_String,
         Has_Annotation_Name    => False,
         Version_ID             => US.Null_Unbounded_String,
         Has_Version_ID         => False,
         Annotation_Prefix      => US.Null_Unbounded_String,
         Has_Annotation_Prefix  => False,
         Maximum                => Annotation_Result_Limit'First,
         Has_Maximum            => False,
         Continuation_Token     => US.Null_Unbounded_String,
         Has_Continuation_Token => False);
      Seen_Annotation : Boolean := False;
      Seen_X_ID       : Boolean := False;
      Count           : Natural := 1;
   begin
      if Query'Length = 0 or else Query'Length > Maximum_Query_Bytes then
         raise Malformed_Annotation_Request with
           "invalid annotation query size";
      end if;
      for Item of Query loop
         if Item = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 7 then
         raise Malformed_Annotation_Request with
           "too many annotation query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_Annotation_Request with
                    "empty annotation query parameter";
               end if;
               declare
                  Pair_Text : constant String := Raw (First .. Index - 1);
                  Equals    : constant Natural :=
                    Ada.Strings.Fixed.Index (Pair_Text, "=");
                  Name      : constant String := Decode_Component
                    ((if Equals = 0 then Pair_Text
                      elsif Equals = Pair_Text'First then ""
                      else Pair_Text (Pair_Text'First .. Equals - 1)));
                  Value     : constant String := Decode_Component
                    ((if Equals = 0 or else Equals = Pair_Text'Last then ""
                      else Pair_Text (Equals + 1 .. Pair_Text'Last)));
               begin
                  if Name = "annotation" then
                     if Seen_Annotation or else Value'Length /= 0 then
                        raise Malformed_Annotation_Request with
                          "invalid annotation subresource";
                     end if;
                     Seen_Annotation := True;
                  elsif Name = "annotationName" then
                     if Result.Has_Annotation_Name
                       or else not Valid_Object_Annotation_Name (Value)
                     then
                        raise Malformed_Annotation_Request with
                          "invalid annotation name";
                     end if;
                     Result.Has_Annotation_Name := True;
                     Result.Annotation_Name := US.To_Unbounded_String (Value);
                  elsif Name = "versionId" then
                     if Result.Has_Version_ID or else Value'Length = 0
                       or else not Deletions.Valid_Version_ID (Value)
                     then
                        raise Malformed_Annotation_Request with
                          "invalid annotation version ID";
                     end if;
                     Result.Has_Version_ID := True;
                     Result.Version_ID := US.To_Unbounded_String (Value);
                  elsif Name = "annotationPrefix" then
                     if Result.Has_Annotation_Prefix then
                        raise Malformed_Annotation_Request with
                          "duplicate annotation prefix";
                     end if;
                     Result.Has_Annotation_Prefix := True;
                     Result.Annotation_Prefix :=
                       US.To_Unbounded_String (Value);
                  elsif Name = "maxAnnotationResults" then
                     if Result.Has_Maximum or else Value'Length = 0 then
                        raise Malformed_Annotation_Request with
                          "invalid annotation result limit";
                     end if;
                     for Digit of Value loop
                        if Digit not in '0' .. '9' then
                           raise Malformed_Annotation_Request with
                             "invalid annotation result limit";
                        end if;
                     end loop;
                     Result.Maximum := Annotation_Result_Limit'Value (Value);
                     Result.Has_Maximum := True;
                  elsif Name = "continuationToken" then
                     if Result.Has_Continuation_Token
                       or else Value'Length = 0
                     then
                        raise Malformed_Annotation_Request with
                          "invalid annotation continuation token";
                     end if;
                     Result.Has_Continuation_Token := True;
                     Result.Continuation_Token :=
                       US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= Operation_Name (Operation)
                     then
                        raise Malformed_Annotation_Request with
                          "invalid annotation operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_Annotation_Request with
                       "unsupported annotation query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      if not Seen_Annotation then
         raise Malformed_Annotation_Request with
           "missing annotation subresource";
      elsif Operation = List_Annotations then
         if Result.Has_Annotation_Name then
            raise Malformed_Annotation_Request with
              "annotation name is not a list member";
         end if;
      elsif not Result.Has_Annotation_Name
        or else Result.Has_Annotation_Prefix
        or else Result.Has_Maximum
        or else Result.Has_Continuation_Token
      then
         raise Malformed_Annotation_Request with
           "invalid annotation operation members";
      end if;
      return Result;
   exception
      when Malformed_Annotation_Request =>
         raise;
      when others =>
         raise Malformed_Annotation_Request with
           "malformed annotation query";
   end Parse_Query;

   function Token_Digest
     (Bucket, Key, Version_ID, Prefix, After : String) return String is
     (GNAT.SHA256.Digest
        ("flyology-annotation-list-v1" & Character'Val (0) & Bucket &
         Character'Val (0) & Key & Character'Val (0) & Version_ID &
         Character'Val (0) & Prefix & Character'Val (0) & After));

   function Hex_Encode (Value : String) return String is
      Hex_Digits : constant String := "0123456789abcdef";
      Result     : String (1 .. Value'Length * 2);
      Cursor     : Positive := 1;
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
     (Bucket, Key, Version_ID, Prefix, After : String) return String is
     (Token_Prefix & Token_Digest
        (Bucket, Key, Version_ID, Prefix, After) & "." & Hex_Encode (After));

   function Decode_Continuation
     (Token, Bucket, Key, Version_ID, Prefix : String)
      return Continuation_Result
   is
      Invalid : constant Continuation_Result :=
        (Valid => False, After => US.Null_Unbounded_String);
   begin
      if not Core.Valid_Listing_Continuation_Syntax (Token) then
         return Invalid;
      end if;
      declare
         Raw          : constant String (1 .. Token'Length) := Token;
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
            After  : String (1 .. Hex_Length / 2);
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
            if not Valid_Object_Annotation_Name (After)
              or else Raw (Digest_First .. Digest_Last) /= Token_Digest
                (Bucket, Key, Version_ID, Prefix, After)
            then
               return Invalid;
            end if;
            return
              (Valid => True, After => US.To_Unbounded_String (After));
         end;
      end;
   end Decode_Continuation;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Scalar_Kind is
     (No_Scalar, Name_Scalar, Last_Modified_Scalar, Entity_Tag_Scalar,
      Checksum_Scalar, Size_Scalar, Replication_Scalar);

   function Empty_Optional_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Annotation return Annotation_Entry is
     --  Replication_Complete is unreachable parser scratch while Is_Set is
     --  false. It is not a public default or compatibility choice.
     ((Name          => US.Null_Unbounded_String,
       Last_Modified => US.Null_Unbounded_String,
       Entity_Tag    => Empty_Optional_String,
       Checksums     => Checksum_Algorithm_Vectors.Empty_Vector,
       Size          => 0,
       Replication   =>
         (Is_Set => False, Value => Replication_Complete)));

   type Annotation_Handler is new XML.Event_Handler with record
      Depth              : Natural := 0;
      Root_Seen          : Boolean := False;
      Name_Seen          : Boolean := False;
      Last_Modified_Seen : Boolean := False;
      Entity_Tag_Seen    : Boolean := False;
      Size_Seen          : Boolean := False;
      Replication_Seen   : Boolean := False;
      Namespace          : Namespace_Style := Namespace_Not_Selected;
      Scalar             : Scalar_Kind := No_Scalar;
      Text_Value         : US.Unbounded_String;
      Value              : Annotation_Entry := Empty_Annotation;
   end record;

   overriding procedure Start_Element
     (Item : in out Annotation_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Annotation_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Annotation_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Annotation_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Annotations with
              "text outside annotation entry scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Annotation_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  Exact established S3 REST/XML namespace. Changing this externally
      --  fixed value changes accepted wire documents.
      Style : constant Namespace_Style :=
        (if Namespace_URI'Length = 0 then Unqualified
         elsif Namespace_URI = "http://s3.amazonaws.com/doc/2006-03-01/"
         then S3_Qualified
         else Namespace_Not_Selected);
   begin
      if Attribute_Count /= 0
        or else Style = Namespace_Not_Selected
        or else (Item.Namespace /= Namespace_Not_Selected
                 and then Item.Namespace /= Style)
      then
         raise Malformed_Annotations with
           "annotation namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Annotation_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   overriding procedure Start_Element
     (Item : in out Annotation_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Annotations with "annotation depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "AnnotationEntry" then
            raise Malformed_Annotations with "invalid annotation entry root";
         end if;
         Item.Root_Seen := True;
      elsif Item.Depth = 2 then
         if Local_Name = "AnnotationName" and then not Item.Name_Seen then
            Item.Name_Seen := True;
            Begin_Scalar (Item, Name_Scalar);
         elsif Local_Name = "LastModified"
           and then not Item.Last_Modified_Seen
         then
            Item.Last_Modified_Seen := True;
            Begin_Scalar (Item, Last_Modified_Scalar);
         elsif Local_Name = "ETag" and then not Item.Entity_Tag_Seen then
            Item.Entity_Tag_Seen := True;
            Begin_Scalar (Item, Entity_Tag_Scalar);
         elsif Local_Name = "ChecksumAlgorithm" then
            Begin_Scalar (Item, Checksum_Scalar);
         elsif Local_Name = "Size" and then not Item.Size_Seen then
            Item.Size_Seen := True;
            Begin_Scalar (Item, Size_Scalar);
         elsif Local_Name = "ReplicationStatus"
           and then not Item.Replication_Seen
         then
            Item.Replication_Seen := True;
            Begin_Scalar (Item, Replication_Scalar);
         else
            raise Malformed_Annotations with
              "unknown or duplicate annotation entry member";
         end if;
      else
         raise Malformed_Annotations with
           "annotation entry nesting exceeds model";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Annotation_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth = 1 then
         Require_Whitespace (Value);
      else
         raise Malformed_Annotations with
           "annotation text outside modeled member";
      end if;
   end Text;

   function Valid_ISO_8601_Timestamp (Value : String) return Boolean is
      Text : constant String (1 .. Value'Length) := Value;

      function Decimal (First, Last : Positive) return Natural is
         Result : Natural := 0;
      begin
         for Index in First .. Last loop
            if Text (Index) not in '0' .. '9' then
               return Natural'Last;
            end if;
            Result := Result * 10
              + Character'Pos (Text (Index)) - Character'Pos ('0');
         end loop;
         return Result;
      end Decimal;

      Year        : Natural;
      Month       : Natural;
      Day         : Natural;
      Hour        : Natural;
      Minute      : Natural;
      Second      : Natural;
      Zone        : Positive := 20;
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

   function Decode_Checksum (Value : String) return Checksum_Algorithm is
   begin
      if Value = "CRC32" then
         return Core.CRC32;
      elsif Value = "CRC32C" then
         return Core.CRC32C;
      elsif Value = "SHA1" then
         return Core.SHA1;
      elsif Value = "SHA256" then
         return Core.SHA256;
      elsif Value = "CRC64NVME" then
         return Core.CRC64NVME;
      elsif Value = "SHA512" then
         return Core.SHA512;
      elsif Value = "MD5" then
         return Core.MD5;
      elsif Value = "XXHASH64" then
         return Core.XXHASH64;
      elsif Value = "XXHASH3" then
         return Core.XXHASH3;
      elsif Value = "XXHASH128" then
         return Core.XXHASH128;
      end if;
      raise Malformed_Annotations with
        "invalid annotation checksum algorithm";
   end Decode_Checksum;

   function Decode_Replication (Value : String) return Replication_Status is
   begin
      if Value = "COMPLETE" then
         return Replication_Complete;
      elsif Value = "PENDING" then
         return Replication_Pending;
      elsif Value = "FAILED" then
         return Replication_Failed;
      elsif Value = "REPLICA" then
         return Replication_Replica;
      elsif Value = "COMPLETED" then
         return Replication_Completed;
      end if;
      raise Malformed_Annotations with
        "invalid annotation replication status";
   end Decode_Replication;

   procedure Store_Scalar (Item : in out Annotation_Handler) is
   begin
      case Item.Scalar is
         when Name_Scalar =>
            Item.Value.Name := Item.Text_Value;
         when Last_Modified_Scalar =>
            if not Valid_ISO_8601_Timestamp
              (US.To_String (Item.Text_Value))
            then
               raise Malformed_Annotations with
                 "invalid annotation modification timestamp";
            end if;
            Item.Value.Last_Modified := Item.Text_Value;
         when Entity_Tag_Scalar =>
            Item.Value.Entity_Tag :=
              (Is_Set => True, Value => Item.Text_Value);
         when Checksum_Scalar =>
            Item.Value.Checksums.Append
              (Decode_Checksum (US.To_String (Item.Text_Value)));
         when Size_Scalar =>
            declare
               Parsed : constant Wire_Core.Byte_Count_Result :=
                 Wire_Core.Parse_Byte_Count
                   (US.To_String (Item.Text_Value));
            begin
               if not Parsed.Valid then
                  raise Malformed_Annotations with
                    "invalid annotation size";
               end if;
               Item.Value.Size := Parsed.Value;
            end;
         when Replication_Scalar =>
            Item.Value.Replication :=
              (Is_Set => True,
               Value => Decode_Replication
                 (US.To_String (Item.Text_Value)));
         when No_Scalar =>
            raise Malformed_Annotations with
              "annotation close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when Name_Scalar          => "AnnotationName",
         when Last_Modified_Scalar => "LastModified",
         when Entity_Tag_Scalar    => "ETag",
         when Checksum_Scalar      => "ChecksumAlgorithm",
         when Size_Scalar          => "Size",
         when Replication_Scalar   => "ReplicationStatus",
         when No_Scalar            => "");

   overriding procedure End_Element
     (Item : in out Annotation_Handler; Local_Name : String) is
   begin
      if Item.Depth = 2 then
         if Item.Scalar = No_Scalar
           or else Local_Name /= Scalar_Name (Item.Scalar)
         then
            raise Malformed_Annotations with
              "mismatched annotation scalar close";
         end if;
         Store_Scalar (Item);
      elsif Item.Depth = 1 then
         if Local_Name /= "AnnotationEntry"
           or else not Item.Name_Seen
           or else not Item.Last_Modified_Seen
           or else not Item.Size_Seen
         then
            raise Malformed_Annotations with
              "incomplete annotation entry";
         end if;
      else
         raise Malformed_Annotations with
           "invalid annotation closing element";
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Reset_Handler (Item : in out Annotation_Handler) is
   begin
      Item :=
        (XML.Event_Handler with
         Depth              => 0,
         Root_Seen          => False,
         Name_Seen          => False,
         Last_Modified_Seen => False,
         Entity_Tag_Seen    => False,
         Size_Seen          => False,
         Replication_Seen   => False,
         Namespace          => Namespace_Not_Selected,
         Scalar             => No_Scalar,
         Text_Value         => US.Null_Unbounded_String,
         Value              => Empty_Annotation);
   end Reset_Handler;

   function Read_Handler
     (Item : Annotation_Handler) return Annotation_Entry is
   begin
      if Item.Depth /= 0
        or else not Item.Root_Seen
        or else not Item.Name_Seen
        or else not Item.Last_Modified_Seen
        or else not Item.Size_Seen
      then
         raise Malformed_Annotations with
           "incomplete annotation entry document";
      end if;
      return Item.Value;
   end Read_Handler;

   function Empty_Page return Annotation_Page is
     --  Annotation_Result_Limit'First is unreachable scratch while Is_Set is
     --  false; it does not select a request or response default.
     ((Has_Annotations        => False,
       Annotations            => Annotation_Entry_Vectors.Empty_Vector,
       Bucket                 => Empty_Optional_String,
       Key                    => Empty_Optional_String,
       Annotation_Prefix      => Empty_Optional_String,
       Max_Annotation_Results =>
         (Is_Set => False, Value => Annotation_Result_Limit'First),
       Annotation_Count       =>
         (Is_Set => False, Text => US.Null_Unbounded_String),
       Continuation_Token     => Empty_Optional_String,
       Next_Continuation_Token => Empty_Optional_String));

   procedure Reject_Is_Truncated
     (Result : in out Annotation_Page; Value : Boolean) is
      pragma Unreferenced (Result, Value);
   begin
      raise Malformed_Annotations with
        "IsTruncated is not modeled for object annotations";
   end Reject_Is_Truncated;

   procedure Set_Page_Continuation_Token
     (Result : in out Annotation_Page; Value : String) is
   begin
      Result.Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Continuation_Token;

   procedure Set_Page_Next_Continuation_Token
     (Result : in out Annotation_Page; Value : String) is
   begin
      Result.Next_Continuation_Token :=
        (Is_Set => True, Value => US.To_Unbounded_String (Value));
   end Set_Page_Next_Continuation_Token;

   function Valid_Integer_Text (Value : String) return Boolean is
      Cursor : Integer := Value'First;
   begin
      if Value'Length = 0 then
         return False;
      end if;
      if Value (Cursor) in '+' | '-' then
         Cursor := Cursor + 1;
      end if;
      if Cursor > Value'Last then
         return False;
      end if;
      while Cursor <= Value'Last loop
         if Value (Cursor) not in '0' .. '9' then
            return False;
         end if;
         Cursor := Cursor + 1;
      end loop;
      return True;
   end Valid_Integer_Text;

   procedure Set_Page_Extra_Scalar
     (Result : in out Annotation_Page; Name : String; Value : String) is
   begin
      if Name = "Bucket" and then not Result.Bucket.Is_Set then
         Result.Bucket :=
           (Is_Set => True, Value => US.To_Unbounded_String (Value));
      elsif Name = "Key" and then not Result.Key.Is_Set then
         Result.Key :=
           (Is_Set => True, Value => US.To_Unbounded_String (Value));
      elsif Name = "AnnotationPrefix"
        and then not Result.Annotation_Prefix.Is_Set
      then
         Result.Annotation_Prefix :=
           (Is_Set => True, Value => US.To_Unbounded_String (Value));
      elsif Name = "MaxAnnotationResults"
        and then not Result.Max_Annotation_Results.Is_Set
      then
         declare
            Parsed : constant Wire_Core.Natural_Result :=
              Wire_Core.Parse_Natural (Value);
         begin
            if not Parsed.Valid
              or else Parsed.Value not in
                Annotation_Result_Limit'First ..
                Annotation_Result_Limit'Last
            then
               raise Malformed_Annotations with
                 "invalid MaxAnnotationResults";
            end if;
            Result.Max_Annotation_Results :=
              (Is_Set => True,
               Value => Annotation_Result_Limit (Parsed.Value));
         end;
      elsif Name = "AnnotationCount"
        and then not Result.Annotation_Count.Is_Set
        and then Valid_Integer_Text (Value)
      then
         Result.Annotation_Count :=
           (Is_Set => True, Text => US.To_Unbounded_String (Value));
      else
         raise Malformed_Annotations with
           "unknown, duplicate, or invalid annotation page member";
      end if;
   end Set_Page_Extra_Scalar;

   procedure Set_Annotations_Present (Result : in out Annotation_Page) is
   begin
      Result.Has_Annotations := True;
   end Set_Annotations_Present;

   procedure Append_Page_Item
     (Result : in out Annotation_Page; Value : Annotation_Entry) is
   begin
      Result.Annotations.Append (Value);
   end Append_Page_Item;

   package Page_Decoder is new Paginated_REST_XML_Reads
     (Root_Name                     => "ListObjectAnnotationsOutput",
      Item_Container_Name           => "Annotations",
      Item_Name                     => "AnnotationEntry",
      Allow_Is_Truncated            => False,
      Allow_Continuation_Token      => True,
      Allow_Next_Continuation_Token => True,
      Item_Type                     => Annotation_Entry,
      Item_Handler_Type             => Annotation_Handler,
      Reset_Item                    => Reset_Handler,
      Read_Item                     => Read_Handler,
      Result_Type                   => Annotation_Page,
      Empty_Result                  => Empty_Page,
      Set_Is_Truncated              => Reject_Is_Truncated,
      Set_Continuation_Token        => Set_Page_Continuation_Token,
      Set_Next_Continuation_Token   => Set_Page_Next_Continuation_Token,
      Set_Extra_Scalar              => Set_Page_Extra_Scalar,
      Set_Item_Container_Present    => Set_Annotations_Present,
      Append_Item                   => Append_Page_Item);

   function Parse_List
     (Document : String; Limits : XML.Parse_Limits) return Annotation_Page is
   begin
      return Page_Decoder.Parse (Document, Limits);
   exception
      when Page_Decoder.Malformed_Page | XML.XML_Error =>
         raise Malformed_Annotations with
           "malformed object annotation listing XML";
   end Parse_List;

   function Checksum_Image (Value : Checksum_Algorithm) return String is
     (case Value is
         when Core.CRC32      => "CRC32",
         when Core.CRC32C     => "CRC32C",
         when Core.CRC64NVME  => "CRC64NVME",
         when Core.SHA1       => "SHA1",
         when Core.SHA256     => "SHA256",
         when Core.SHA512     => "SHA512",
         when Core.MD5        => "MD5",
         when Core.XXHASH64   => "XXHASH64",
         when Core.XXHASH3    => "XXHASH3",
         when Core.XXHASH128  => "XXHASH128");

   function Serialize_List (Value : Annotation_Page) return String is
      Result : US.Unbounded_String := US.To_Unbounded_String
        ("<ListObjectAnnotationsOutput xmlns=""" &
         "http://s3.amazonaws.com/doc/2006-03-01/"">");

      procedure Add (Name, Text : String) is
      begin
         US.Append
           (Result, "<" & Name & ">" & XML.Escape_Text (Text) &
              "</" & Name & ">");
      end Add;
   begin
      if not Value.Has_Annotations then
         raise Malformed_Annotations with
           "server annotation page omits Annotations";
      end if;
      US.Append (Result, "<Annotations>");
      for Annotation of Value.Annotations loop
         if not Valid_Object_Annotation_Name (US.To_String (Annotation.Name))
           or else US.Length (Annotation.Last_Modified) = 0
           or else not Valid_ISO_8601_Timestamp
             (US.To_String (Annotation.Last_Modified))
         then
            raise Malformed_Annotations with
              "invalid server annotation entry";
         end if;
         US.Append (Result, "<AnnotationEntry>");
         Add ("AnnotationName", US.To_String (Annotation.Name));
         Add ("LastModified", US.To_String (Annotation.Last_Modified));
         if Annotation.Entity_Tag.Is_Set then
            Add ("ETag", US.To_String (Annotation.Entity_Tag.Value));
         end if;
         for Algorithm of Annotation.Checksums loop
            Add ("ChecksumAlgorithm", Checksum_Image (Algorithm));
         end loop;
         Add
           ("Size",
            Ada.Strings.Fixed.Trim (Byte_Count'Image (Annotation.Size),
                                    Ada.Strings.Both));
         if Annotation.Replication.Is_Set then
            Add
              ("ReplicationStatus",
               (case Annotation.Replication.Value is
                   when Replication_Complete  => "COMPLETE",
                   when Replication_Pending   => "PENDING",
                   when Replication_Failed    => "FAILED",
                   when Replication_Replica   => "REPLICA",
                   when Replication_Completed => "COMPLETED"));
         end if;
         US.Append (Result, "</AnnotationEntry>");
      end loop;
      US.Append (Result, "</Annotations>");
      if Value.Bucket.Is_Set then
         Add ("Bucket", US.To_String (Value.Bucket.Value));
      end if;
      if Value.Key.Is_Set then
         Add ("Key", US.To_String (Value.Key.Value));
      end if;
      if Value.Annotation_Prefix.Is_Set then
         Add
           ("AnnotationPrefix",
            US.To_String (Value.Annotation_Prefix.Value));
      end if;
      if Value.Max_Annotation_Results.Is_Set then
         Add
           ("MaxAnnotationResults",
            Ada.Strings.Fixed.Trim
              (Annotation_Result_Limit'Image
                 (Value.Max_Annotation_Results.Value), Ada.Strings.Both));
      end if;
      if Value.Annotation_Count.Is_Set then
         Add ("AnnotationCount", US.To_String (Value.Annotation_Count.Text));
      end if;
      if Value.Continuation_Token.Is_Set then
         Add
           ("ContinuationToken",
            US.To_String (Value.Continuation_Token.Value));
      end if;
      if Value.Next_Continuation_Token.Is_Set then
         Add
           ("NextContinuationToken",
            US.To_String (Value.Next_Continuation_Token.Value));
      end if;
      US.Append (Result, "</ListObjectAnnotationsOutput>");
      return US.To_String (Result);
   end Serialize_List;

end Flyology.Object_Storage.S3.Annotations;
