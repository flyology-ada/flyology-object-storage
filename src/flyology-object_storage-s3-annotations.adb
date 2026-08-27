with Flyology.Object_Storage.S3.Paginated_REST_XML_Reads;
with Flyology.Object_Storage.S3.Wire_Core;

package body Flyology.Object_Storage.S3.Annotations is

   package US renames Ada.Strings.Unbounded;

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

end Flyology.Object_Storage.S3.Annotations;
