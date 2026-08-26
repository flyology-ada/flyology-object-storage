package body Flyology.Object_Storage.S3.Encryption is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is (No_Container, Default_Container, Blocked_Container);
   type Scalar_Kind is
     (No_Scalar, Algorithm_Scalar, KMS_Key_Scalar, Bucket_Key_Scalar,
      Blocked_Type_Scalar);

   type Encryption_Handler is new XML.Event_Handler with record
      Depth          : Natural := 0;
      Root_Seen      : Boolean := False;
      Rule_Seen      : Boolean := False;
      Default_Seen   : Boolean := False;
      Algorithm_Seen : Boolean := False;
      KMS_Key_Seen   : Boolean := False;
      Bucket_Key_Seen : Boolean := False;
      Blocked_Seen   : Boolean := False;
      Namespace      : Namespace_Style := Namespace_Not_Selected;
      Container      : Container_Kind := No_Container;
      Scalar         : Scalar_Kind := No_Scalar;
      Text_Value     : US.Unbounded_String;
      Current        : Encryption_Rule := (others => <>);
      Value          : Encryption_Configuration :=
        (Is_Set => True, others => <>);
   end record;

   overriding procedure Start_Element
     (Item : in out Encryption_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Encryption_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Encryption_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Encryption_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Encryption with
              "text outside bucket-encryption scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Encryption_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  Exact pinned S3 REST/XML namespace.  Changing this external value
      --  changes provider compatibility for every configuration member.
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
         raise Malformed_Encryption with
           "bucket-encryption namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   overriding procedure Start_Element
     (Item : in out Encryption_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Encryption with "bucket-encryption depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      case Item.Depth is
         when 1 =>
            if Item.Root_Seen
              or else Local_Name /= "ServerSideEncryptionConfiguration"
            then
               raise Malformed_Encryption with
                 "invalid ServerSideEncryptionConfiguration root";
            end if;
            Item.Root_Seen := True;
         when 2 =>
            if Local_Name /= "Rule" then
               raise Malformed_Encryption with
                 "unknown bucket-encryption member";
            end if;
            Item.Rule_Seen := True;
            Item.Default_Seen := False;
            Item.Algorithm_Seen := False;
            Item.KMS_Key_Seen := False;
            Item.Bucket_Key_Seen := False;
            Item.Blocked_Seen := False;
            Item.Container := No_Container;
            Item.Scalar := No_Scalar;
            Item.Current := (others => <>);
         when 3 =>
            if Local_Name = "ApplyServerSideEncryptionByDefault"
              and then not Item.Default_Seen
            then
               Item.Default_Seen := True;
               Item.Container := Default_Container;
               Item.Current.Default_Encryption.Is_Set := True;
            elsif Local_Name = "BucketKeyEnabled"
              and then not Item.Bucket_Key_Seen
            then
               Item.Bucket_Key_Seen := True;
               Item.Scalar := Bucket_Key_Scalar;
               Item.Text_Value := US.Null_Unbounded_String;
            elsif Local_Name = "BlockedEncryptionTypes"
              and then not Item.Blocked_Seen
            then
               Item.Blocked_Seen := True;
               Item.Container := Blocked_Container;
               Item.Current.Blocked_Types.Is_Set := True;
            else
               raise Malformed_Encryption with
                 "unknown or duplicate bucket-encryption rule member";
            end if;
         when 4 =>
            if Item.Container = Default_Container
              and then Local_Name = "SSEAlgorithm"
              and then not Item.Algorithm_Seen
            then
               Item.Algorithm_Seen := True;
               Item.Scalar := Algorithm_Scalar;
            elsif Item.Container = Default_Container
              and then Local_Name = "KMSMasterKeyID"
              and then not Item.KMS_Key_Seen
            then
               Item.KMS_Key_Seen := True;
               Item.Scalar := KMS_Key_Scalar;
            elsif Item.Container = Blocked_Container
              and then Local_Name = "EncryptionType"
            then
               Item.Current.Blocked_Types.Types_Is_Set := True;
               Item.Scalar := Blocked_Type_Scalar;
            else
               raise Malformed_Encryption with
                 "unknown or duplicate nested encryption member";
            end if;
            Item.Text_Value := US.Null_Unbounded_String;
         when others =>
            raise Malformed_Encryption with
              "nested bucket-encryption member";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Encryption_Handler; Value : String) is
   begin
      if (Item.Depth = 3 and then Item.Scalar = Bucket_Key_Scalar)
        or else (Item.Depth = 4 and then Item.Scalar /= No_Scalar)
      then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth in 1 .. 3 then
         Require_Whitespace (Value);
      else
         raise Malformed_Encryption with
           "bucket-encryption text outside modeled member";
      end if;
   end Text;

   function Parse_Boolean (Value : String) return Optional_Boolean is
   begin
      if Value = "true" then
         return (Is_Set => True, Value => True);
      elsif Value = "false" then
         return (Is_Set => True, Value => False);
      end if;
      raise Malformed_Encryption with "invalid bucket-encryption Boolean";
   end Parse_Boolean;

   procedure Set_Algorithm
     (Item : in out Encryption_Handler; Value : String) is
   begin
      if Value = "AES256" then
         Item.Current.Default_Encryption.Algorithm := AES256_Encryption;
      elsif Value = "aws:fsx" then
         Item.Current.Default_Encryption.Algorithm := FSx_Encryption;
      elsif Value = "aws:backup" then
         Item.Current.Default_Encryption.Algorithm := Backup_Encryption;
      elsif Value = "aws:kms" then
         Item.Current.Default_Encryption.Algorithm := KMS_Encryption;
      elsif Value = "aws:kms:dsse" then
         Item.Current.Default_Encryption.Algorithm := KMS_DSSE_Encryption;
      else
         raise Malformed_Encryption with "invalid encryption algorithm";
      end if;
   end Set_Algorithm;

   procedure Append_Blocked_Type
     (Item : in out Encryption_Handler; Value : String) is
   begin
      if Value = "NONE" then
         Item.Current.Blocked_Types.Types.Append (No_Blocked_Encryption);
      elsif Value = "SSE-C" then
         Item.Current.Blocked_Types.Types.Append (SSE_C_Blocked);
      else
         raise Malformed_Encryption with "invalid blocked encryption type";
      end if;
   end Append_Blocked_Type;

   overriding procedure End_Element
     (Item : in out Encryption_Handler; Local_Name : String)
   is
      Value : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Depth is
         when 4 =>
            case Item.Scalar is
               when Algorithm_Scalar =>
                  if Local_Name /= "SSEAlgorithm" then
                     raise Malformed_Encryption with
                       "mismatched SSEAlgorithm close";
                  end if;
                  Set_Algorithm (Item, Value);
               when KMS_Key_Scalar =>
                  if Local_Name /= "KMSMasterKeyID" then
                     raise Malformed_Encryption with
                       "mismatched KMSMasterKeyID close";
                  end if;
                  Item.Current.Default_Encryption.KMS_Master_Key_ID :=
                    (Is_Set => True, Value => Item.Text_Value);
               when Blocked_Type_Scalar =>
                  if Local_Name /= "EncryptionType" then
                     raise Malformed_Encryption with
                       "mismatched EncryptionType close";
                  end if;
                  Append_Blocked_Type (Item, Value);
               when others =>
                  raise Malformed_Encryption with
                    "nested encryption close without scalar";
            end case;
            Item.Scalar := No_Scalar;
            Item.Text_Value := US.Null_Unbounded_String;
            Item.Depth := 3;
         when 3 =>
            if Item.Scalar = Bucket_Key_Scalar then
               if Local_Name /= "BucketKeyEnabled" then
                  raise Malformed_Encryption with
                    "mismatched BucketKeyEnabled close";
               end if;
               Item.Current.Bucket_Key_Enabled := Parse_Boolean (Value);
               Item.Scalar := No_Scalar;
               Item.Text_Value := US.Null_Unbounded_String;
            elsif Item.Container = Default_Container then
               if Local_Name /= "ApplyServerSideEncryptionByDefault"
                 or else not Item.Algorithm_Seen
               then
                  raise Malformed_Encryption with
                    "incomplete default-encryption structure";
               end if;
               Item.Container := No_Container;
            elsif Item.Container = Blocked_Container then
               if Local_Name /= "BlockedEncryptionTypes" then
                  raise Malformed_Encryption with
                    "mismatched blocked-encryption close";
               end if;
               Item.Container := No_Container;
            else
               raise Malformed_Encryption with
                 "rule member close without open member";
            end if;
            Item.Depth := 2;
         when 2 =>
            if Local_Name /= "Rule"
              or else Item.Container /= No_Container
              or else Item.Scalar /= No_Scalar
            then
               raise Malformed_Encryption with
                 "incomplete bucket-encryption rule";
            end if;
            Item.Value.Rules.Append (Item.Current);
            Item.Depth := 1;
         when 1 =>
            if Local_Name /= "ServerSideEncryptionConfiguration"
              or else not Item.Rule_Seen
            then
               raise Malformed_Encryption with
                 "incomplete ServerSideEncryptionConfiguration";
            end if;
            Item.Depth := 0;
         when others =>
            raise Malformed_Encryption with
              "invalid bucket-encryption closing element";
      end case;
   end End_Element;

   function Parse
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return Encryption_Configuration
   is
      Handler : aliased Encryption_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0 or else not Handler.Root_Seen then
         raise Malformed_Encryption with
           "incomplete bucket-encryption document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Encryption with "malformed bucket-encryption XML";
   end Parse;

   function Serialize
     (Value  : Encryption_Configuration;
      Limits : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Result       : US.Unbounded_String;
      Elements     : Natural := 1;
      Text_Bytes   : Natural := 0;
      Actual_Depth : Positive := 2;

      --  Pinned PutBucketEncryption REST/XML namespace and member spellings.
      --  Changing them changes provider compatibility and request signatures.
      Prefix : constant String :=
        "<ServerSideEncryptionConfiguration xmlns=""" &
        "http://s3.amazonaws.com/doc/2006-03-01/"">";
      Suffix : constant String :=
        "</ServerSideEncryptionConfiguration>";

      function Algorithm_Text (Item : Encryption_Algorithm) return String is
        (case Item is
            when AES256_Encryption   => "AES256",
            when FSx_Encryption      => "aws:fsx",
            when Backup_Encryption   => "aws:backup",
            when KMS_Encryption      => "aws:kms",
            when KMS_DSSE_Encryption => "aws:kms:dsse");

      function Blocked_Text (Item : Blocked_Encryption_Type) return String is
        (case Item is
            when No_Blocked_Encryption => "NONE",
            when SSE_C_Blocked         => "SSE-C");

      procedure Append_Bounded (Fragment : String) is
         Current : constant Natural := US.Length (Result);
      begin
         if Fragment'Length > Limits.Maximum_Document_Bytes - Current then
            raise Malformed_Encryption with
              "bucket-encryption document exceeds caller limit";
         end if;
         US.Append (Result, Fragment);
      end Append_Bounded;

      procedure Add_Elements (Count : Positive) is
      begin
         if Count > Limits.Maximum_Elements - Elements then
            raise Malformed_Encryption with
              "bucket-encryption elements exceed caller limit";
         end if;
         Elements := Elements + Count;
      end Add_Elements;

      procedure Add_Text (Text : String) is
      begin
         if Text'Length > Limits.Maximum_Text_Bytes - Text_Bytes then
            raise Malformed_Encryption with
              "bucket-encryption text exceeds caller limit";
         end if;
         Text_Bytes := Text_Bytes + Text'Length;
         Append_Bounded (XML.Escape_Text (Text));
      end Add_Text;
   begin
      if not Value.Is_Set or else Value.Rules.Is_Empty then
         raise Malformed_Encryption with
           "bucket-encryption rules are required";
      end if;

      Append_Bounded (Prefix);
      for Rule of Value.Rules loop
         Add_Elements (1);
         Append_Bounded ("<Rule>");

         if Rule.Default_Encryption.Is_Set then
            Add_Elements (2);
            Actual_Depth := Positive'Max (Actual_Depth, 4);
            Append_Bounded ("<ApplyServerSideEncryptionByDefault>");
            Append_Bounded ("<SSEAlgorithm>");
            Add_Text (Algorithm_Text (Rule.Default_Encryption.Algorithm));
            Append_Bounded ("</SSEAlgorithm>");
            if Rule.Default_Encryption.KMS_Master_Key_ID.Is_Set then
               Add_Elements (1);
               Append_Bounded ("<KMSMasterKeyID>");
               Add_Text
                 (US.To_String
                    (Rule.Default_Encryption.KMS_Master_Key_ID.Value));
               Append_Bounded ("</KMSMasterKeyID>");
            end if;
            Append_Bounded ("</ApplyServerSideEncryptionByDefault>");
         elsif Rule.Default_Encryption.KMS_Master_Key_ID.Is_Set then
            raise Malformed_Encryption with
              "KMS key requires default encryption";
         end if;

         if Rule.Bucket_Key_Enabled.Is_Set then
            Add_Elements (1);
            Actual_Depth := Positive'Max (Actual_Depth, 3);
            Append_Bounded ("<BucketKeyEnabled>");
            Add_Text
              ((if Rule.Bucket_Key_Enabled.Value then "true" else "false"));
            Append_Bounded ("</BucketKeyEnabled>");
         end if;

         if Rule.Blocked_Types.Is_Set then
            Add_Elements (1);
            Actual_Depth := Positive'Max (Actual_Depth, 3);
            if Rule.Blocked_Types.Types_Is_Set
              and then Rule.Blocked_Types.Types.Is_Empty
            then
               raise Malformed_Encryption with
                 "present blocked-encryption list is empty";
            elsif not Rule.Blocked_Types.Types_Is_Set
              and then not Rule.Blocked_Types.Types.Is_Empty
            then
               raise Malformed_Encryption with
                 "absent blocked-encryption list contains values";
            end if;
            Append_Bounded ("<BlockedEncryptionTypes>");
            if Rule.Blocked_Types.Types_Is_Set then
               Actual_Depth := Positive'Max (Actual_Depth, 4);
               for Item of Rule.Blocked_Types.Types loop
                  Add_Elements (1);
                  Append_Bounded ("<EncryptionType>");
                  Add_Text (Blocked_Text (Item));
                  Append_Bounded ("</EncryptionType>");
               end loop;
            end if;
            Append_Bounded ("</BlockedEncryptionTypes>");
         elsif Rule.Blocked_Types.Types_Is_Set
           or else not Rule.Blocked_Types.Types.Is_Empty
         then
            raise Malformed_Encryption with
              "blocked-encryption values require their container";
         end if;

         Append_Bounded ("</Rule>");
      end loop;
      if Actual_Depth > Limits.Maximum_Depth then
         raise Malformed_Encryption with
           "bucket-encryption depth exceeds caller limit";
      end if;
      Append_Bounded (Suffix);
      return US.To_String (Result);
   end Serialize;

end Flyology.Object_Storage.S3.Encryption;
