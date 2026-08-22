with Ada.Containers;
with Ada.Strings;
with Ada.Strings.Fixed;
with Flyology.Object_Storage.S3.SigV4_Encoding;
with Flyology.Object_Storage.S3.Wire_Core;
with GNAT.SHA256;

package body Flyology.Object_Storage.S3.Buckets is

   package US renames Ada.Strings.Unbounded;
   package Wire_Core renames Flyology.Object_Storage.S3.Wire_Core;
   use type Ada.Containers.Count_Type;

   Maximum_Query_Length : constant := 8 * 1_024;
   Token_Prefix : constant String := "fosb1.";

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
               raise Malformed_List_Buckets_Request with
                 "invalid ListBuckets percent escape";
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

   function Parse_List_Buckets_Query
     (Query : String) return List_Buckets_Request
   is
      Result : List_Buckets_Request;
      Seen_Max, Seen_Token, Seen_Prefix, Seen_Region, Seen_X_ID : Boolean :=
        False;
      Count : Natural := 1;
   begin
      if Query'Length = 0 then
         return Result;
      elsif Query'Length > Maximum_Query_Length then
         raise Malformed_List_Buckets_Request with
           "invalid ListBuckets query size";
      end if;
      for Value of Query loop
         if Value = '&' then
            Count := Count + 1;
         end if;
      end loop;
      if Count > 16 then
         raise Malformed_List_Buckets_Request with
           "too many ListBuckets query parameters";
      end if;
      declare
         Raw   : constant String (1 .. Query'Length) := Query;
         First : Positive := 1;
      begin
         for Index in 1 .. Raw'Last + 1 loop
            if Index = Raw'Last + 1 or else Raw (Index) = '&' then
               if Index = First then
                  raise Malformed_List_Buckets_Request with
                    "empty ListBuckets query parameter";
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
                  if Name = "max-buckets" then
                     Number := Wire_Core.Parse_Natural (Value);
                     if Seen_Max or else not Number.Valid
                       or else Number.Value not in Max_Buckets_Value'Range
                     then
                        raise Malformed_List_Buckets_Request with
                          "invalid ListBuckets max-buckets";
                     end if;
                     Seen_Max := True;
                     Result.Has_Max_Buckets := True;
                     Result.Max_Buckets := Max_Buckets_Value (Number.Value);
                  elsif Name = "continuation-token" then
                     if Seen_Token or else Value'Length = 0 then
                        raise Malformed_List_Buckets_Request with
                          "invalid ListBuckets continuation token";
                     end if;
                     Seen_Token := True;
                     Result.Has_Continuation_Token := True;
                     Result.Continuation_Token :=
                       US.To_Unbounded_String (Value);
                  elsif Name = "prefix" then
                     if Seen_Prefix then
                        raise Malformed_List_Buckets_Request with
                          "duplicate ListBuckets prefix";
                     end if;
                     Seen_Prefix := True;
                     Result.Prefix := US.To_Unbounded_String (Value);
                  elsif Name = "bucket-region" then
                     if Seen_Region
                       or else Value'Length > Maximum_Bucket_Region_Length
                       or else not SigV4_Encoding.Valid_Scope_Segment (Value)
                     then
                        raise Malformed_List_Buckets_Request with
                          "invalid ListBuckets bucket region";
                     end if;
                     Seen_Region := True;
                     Result.Bucket_Region := US.To_Unbounded_String (Value);
                  elsif Name = "x-id" then
                     if Seen_X_ID or else Value /= "ListBuckets" then
                        raise Malformed_List_Buckets_Request with
                          "invalid ListBuckets operation identifier";
                     end if;
                     Seen_X_ID := True;
                  else
                     raise Malformed_List_Buckets_Request with
                       "unsupported ListBuckets query parameter";
                  end if;
               end;
               First := Index + 1;
            end if;
         end loop;
      end;
      return Result;
   end Parse_List_Buckets_Query;

   function Token_Digest
     (Prefix, Bucket_Region, After : String) return String is
     (GNAT.SHA256.Digest
        ("flyology-list-buckets-v1" & Character'Val (0) & Prefix &
         Character'Val (0) & Bucket_Region & Character'Val (0) & After));

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
     (Prefix, Bucket_Region, After : String) return String is
     (Token_Prefix & Token_Digest (Prefix, Bucket_Region, After) & "." &
      Hex_Encode (After));

   function Decode_Continuation
     (Token, Prefix, Bucket_Region : String) return Continuation_Result
   is
      Invalid : constant Continuation_Result := (others => <>);
   begin
      if Token'Length < Token_Prefix'Length + 65
        or else Token'Length > Token_Prefix'Length + 65 + 126
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
            if not Valid_Bucket_Name (After)
              or else Raw (Digest_First .. Digest_Last) /=
                Token_Digest (Prefix, Bucket_Region, After)
            then
               return Invalid;
            end if;
            return
              (Valid => True, After => US.To_Unbounded_String (After));
         end;
      end;
   end Decode_Continuation;

   function Is_Empty (Value : Create_Bucket_Configuration) return Boolean is
     (US.Length (Value.Location_Constraint) = 0
      and then US.Length (Value.Location_Type) = 0
      and then US.Length (Value.Location_Name) = 0
      and then US.Length (Value.Data_Redundancy) = 0
      and then US.Length (Value.Bucket_Type) = 0
      and then Value.Tags.Is_Empty);

   function Valid_Location_Constraint (Value : String) return Boolean is
     (Value = "af-south-1"
      or else Value = "ap-east-1"
      or else Value = "ap-east-2"
      or else Value = "ap-northeast-1"
      or else Value = "ap-northeast-2"
      or else Value = "ap-northeast-3"
      or else Value = "ap-south-1"
      or else Value = "ap-south-2"
      or else Value = "ap-southeast-1"
      or else Value = "ap-southeast-2"
      or else Value = "ap-southeast-3"
      or else Value = "ap-southeast-4"
      or else Value = "ap-southeast-5"
      or else Value = "ap-southeast-6"
      or else Value = "ap-southeast-7"
      or else Value = "ca-central-1"
      or else Value = "ca-west-1"
      or else Value = "cn-north-1"
      or else Value = "cn-northwest-1"
      or else Value = "EU"
      or else Value = "eu-central-1"
      or else Value = "eu-central-2"
      or else Value = "eu-north-1"
      or else Value = "eu-south-1"
      or else Value = "eu-south-2"
      or else Value = "eu-west-1"
      or else Value = "eu-west-2"
      or else Value = "eu-west-3"
      or else Value = "il-central-1"
      or else Value = "me-central-1"
      or else Value = "me-south-1"
      or else Value = "mx-central-1"
      or else Value = "sa-east-1"
      or else Value = "us-east-2"
      or else Value = "us-gov-east-1"
      or else Value = "us-gov-west-1"
      or else Value = "us-west-1"
      or else Value = "us-west-2");

   type Location_Handler is new XML.Event_Handler with record
      Depth           : Natural := 0;
      Value           : US.Unbounded_String;
      Root_Seen       : Boolean := False;
      Constraint_Seen : Boolean := False;
      Wrapped         : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Location_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Location_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Location_Handler; Local_Name : String);

   overriding procedure Start_Element
     (Item : in out Location_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Bucket_Location with
           "GetBucketLocation depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Depth = 1 then
         if Item.Root_Seen then
            raise Malformed_Bucket_Location with
              "duplicate GetBucketLocation root";
         elsif Local_Name = "LocationConstraint" then
            Item.Root_Seen := True;
            Item.Constraint_Seen := True;
         elsif Local_Name = "CreateBucketConfiguration" then
            Item.Root_Seen := True;
            Item.Wrapped := True;
         else
            raise Malformed_Bucket_Location with
              "unexpected GetBucketLocation root";
         end if;
      elsif Item.Depth = 2 and then Item.Wrapped
        and then Local_Name = "LocationConstraint"
        and then not Item.Constraint_Seen
      then
         Item.Constraint_Seen := True;
      else
         raise Malformed_Bucket_Location with
           "nested GetBucketLocation element";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Location_Handler; Value : String) is
   begin
      if (not Item.Wrapped and then Item.Depth = 1)
        or else (Item.Wrapped and then Item.Depth = 2)
      then
         US.Append (Item.Value, Value);
      elsif Item.Wrapped and then Item.Depth = 1 then
         for Character_Value of Value loop
            if Character_Value not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR
            then
               raise Malformed_Bucket_Location with
                 "non-whitespace GetBucketLocation wrapper text";
            end if;
         end loop;
      else
         raise Malformed_Bucket_Location with
           "GetBucketLocation text outside root";
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Location_Handler; Local_Name : String) is
   begin
      if Item.Wrapped and then Item.Depth = 2
        and then Local_Name = "LocationConstraint"
      then
         Item.Depth := 1;
      elsif Item.Wrapped and then Item.Depth = 1
        and then Local_Name = "CreateBucketConfiguration"
        and then Item.Constraint_Seen
      then
         Item.Depth := 0;
      elsif not Item.Wrapped and then Item.Depth = 1
        and then Local_Name = "LocationConstraint"
      then
         Item.Depth := 0;
      else
         raise Malformed_Bucket_Location with
           "invalid GetBucketLocation closing element";
      end if;
   end End_Element;

   function Parse_Location_Constraint
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits) return String
   is
      Handler : aliased Location_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0
        or else not Handler.Root_Seen
        or else not Handler.Constraint_Seen
      then
         raise Malformed_Bucket_Location with
           "incomplete GetBucketLocation document";
      end if;
      declare
         Value : constant String := US.To_String (Handler.Value);
      begin
         if Value'Length > 0
           and then Value /= "us-east-1"
           and then not Valid_Location_Constraint (Value)
         then
            raise Malformed_Bucket_Location with
              "invalid GetBucketLocation constraint";
         end if;
         return Value;
      end;
   exception
      when XML.XML_Error =>
         raise Malformed_Bucket_Location with
           "malformed GetBucketLocation XML";
   end Parse_Location_Constraint;

   function Serialize_Location_Constraint (Region : String) return String is
      Value : constant String :=
        (if Region = "us-east-1" then "" else Region);
   begin
      if Region /= "us-east-1" and then not Valid_Location_Constraint (Region)
      then
         raise Malformed_Bucket_Location with
           "invalid configured bucket location";
      end if;
      return
        "<?xml version=""1.0"" encoding=""UTF-8""?>" &
        "<LocationConstraint xmlns=""http://s3.amazonaws.com/doc/" &
        "2006-03-01/"">" & XML.Escape_Text (Value) &
        "</LocationConstraint>";
   exception
      when XML.XML_Error =>
         raise Malformed_Bucket_Location with
           "bucket location contains invalid XML text";
   end Serialize_Location_Constraint;

   function Element (Name, Value : String) return String is
     ("<" & Name & ">" & XML.Escape_Text (Value) & "</" & Name & ">");

   function Serialize_Create_Configuration
     (Value : Create_Bucket_Configuration) return String
   is
      Constraint_Value : constant String :=
        US.To_String (Value.Location_Constraint);
      Location_Type : constant String := US.To_String (Value.Location_Type);
      Location_Name : constant String := US.To_String (Value.Location_Name);
      Redundancy : constant String := US.To_String (Value.Data_Redundancy);
      Bucket_Type : constant String := US.To_String (Value.Bucket_Type);
      Has_Location : constant Boolean :=
        Location_Type'Length > 0 or else Location_Name'Length > 0;
      Has_Bucket : constant Boolean :=
        Redundancy'Length > 0 or else Bucket_Type'Length > 0;
      Result : US.Unbounded_String;
   begin
      if Is_Empty (Value) then
         return "";
      end if;
      if (Constraint_Value'Length > 0
          and then not Valid_Location_Constraint (Constraint_Value))
        or else (Has_Location
                 and then (Location_Type'Length = 0
                           or else Location_Name'Length = 0))
        or else (Location_Type'Length > 0
                 and then Location_Type /= "AvailabilityZone"
                 and then Location_Type /= "LocalZone")
        or else (Has_Bucket
                 and then (Redundancy'Length = 0
                           or else Bucket_Type'Length = 0))
        or else (Redundancy'Length > 0
                 and then Redundancy /= "SingleAvailabilityZone"
                 and then Redundancy /= "SingleLocalZone")
        or else (Bucket_Type'Length > 0 and then Bucket_Type /= "Directory")
        or else (Constraint_Value'Length > 0
                 and then (Has_Location or else Has_Bucket))
      then
         raise Invalid_Bucket_Configuration with
           "invalid CreateBucket configuration";
      end if;
      for Item of Value.Tags loop
         if US.Length (Item.Key) = 0 then
            raise Invalid_Bucket_Configuration with
              "CreateBucket tag key is empty";
         end if;
      end loop;
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<CreateBucketConfiguration xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">");
      if Constraint_Value'Length > 0 then
         US.Append
           (Result, Element ("LocationConstraint", Constraint_Value));
      end if;
      if Has_Location then
         US.Append
           (Result,
            "<Location>" & Element ("Type", Location_Type) &
            Element ("Name", Location_Name) & "</Location>");
      end if;
      if Has_Bucket then
         US.Append
           (Result,
            "<Bucket>" & Element ("DataRedundancy", Redundancy) &
            Element ("Type", Bucket_Type) & "</Bucket>");
      end if;
      if not Value.Tags.Is_Empty then
         US.Append (Result, "<Tags>");
         for Item of Value.Tags loop
            US.Append
              (Result,
               "<Tag>" & Element ("Key", US.To_String (Item.Key)) &
               Element ("Value", US.To_String (Item.Value)) & "</Tag>");
         end loop;
         US.Append (Result, "</Tags>");
      end if;
      US.Append (Result, "</CreateBucketConfiguration>");
      return US.To_String (Result);
   exception
      when XML.XML_Error =>
         raise Invalid_Bucket_Configuration with
           "CreateBucket configuration contains invalid XML text";
   end Serialize_Create_Configuration;

   type Bucket_Field is
     (No_Field,
      Name_Field,
      Creation_Date_Field,
      Bucket_Region_Field,
      Bucket_ARN_Field,
      Owner_Display_Name_Field,
      Owner_ID_Field,
      Continuation_Token_Field,
      Prefix_Field);

   type Bucket_Context is
     (Root_Context, Buckets_Context, Bucket_Context_Value, Owner_Context);

   type Bucket_Handler is new XML.Event_Handler with record
      Value                   : List_Buckets_Result;
      Current_Bucket          : Bucket_Entry;
      Text_Value              : US.Unbounded_String;
      Depth                   : Natural := 0;
      Ignore_Depth            : Natural := 0;
      Context                 : Bucket_Context := Root_Context;
      Field                   : Bucket_Field := No_Field;
      Seen_Buckets            : Boolean := False;
      Seen_Owner              : Boolean := False;
      Seen_Continuation_Token : Boolean := False;
      Seen_Prefix             : Boolean := False;
      Seen_Name               : Boolean := False;
      Seen_Creation_Date      : Boolean := False;
      Seen_Bucket_Region      : Boolean := False;
      Seen_Bucket_ARN         : Boolean := False;
      Seen_Owner_Display_Name : Boolean := False;
      Seen_Owner_ID           : Boolean := False;
   end record;

   overriding procedure Start_Element
     (Item : in out Bucket_Handler; Local_Name : String);
   overriding procedure Text
     (Item : in out Bucket_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Bucket_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character_Value of Value loop
         if Character_Value /= ' '
           and then Character_Value /= Character'Val (9)
           and then Character_Value /= Character'Val (10)
           and then Character_Value /= Character'Val (13)
         then
            raise Malformed_Bucket_Listing with
              "text outside ListBuckets fields";
         end if;
      end loop;
   end Require_Whitespace;

   procedure Select_Field
     (Item  : in out Bucket_Handler;
      Seen  : in out Boolean;
      Field : Bucket_Field)
   is
   begin
      if Seen then
         raise Malformed_Bucket_Listing with
           "duplicate ListBuckets field";
      end if;
      Seen := True;
      Item.Field := Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Select_Field;

   procedure Finish_Field (Item : in out Bucket_Handler) is
   begin
      case Item.Field is
         when Name_Field =>
            Item.Current_Bucket.Name := Item.Text_Value;
         when Creation_Date_Field =>
            Item.Current_Bucket.Creation_Date := Item.Text_Value;
         when Bucket_Region_Field =>
            Item.Current_Bucket.Bucket_Region := Item.Text_Value;
         when Bucket_ARN_Field =>
            Item.Current_Bucket.Bucket_ARN := Item.Text_Value;
         when Owner_Display_Name_Field =>
            Item.Value.Owner.Display_Name := Item.Text_Value;
         when Owner_ID_Field =>
            Item.Value.Owner.ID := Item.Text_Value;
         when Continuation_Token_Field =>
            Item.Value.Continuation_Token := Item.Text_Value;
         when Prefix_Field =>
            Item.Value.Prefix := Item.Text_Value;
         when No_Field =>
            null;
      end case;
      Item.Field := No_Field;
      US.Set_Unbounded_String (Item.Text_Value, "");
   end Finish_Field;

   overriding procedure Start_Element
     (Item : in out Bucket_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Bucket_Listing with
           "ListBuckets depth overflow";
      end if;
      Item.Depth := Item.Depth + 1;
      if Item.Ignore_Depth /= 0 then
         return;
      elsif Item.Field /= No_Field then
         raise Malformed_Bucket_Listing with
           "nested ListBuckets scalar";
      end if;

      if Item.Depth = 1 then
         if Local_Name /= "ListAllMyBucketsResult" then
            raise Malformed_Bucket_Listing with
              "unexpected ListBuckets root";
         end if;
      elsif Item.Depth = 2 then
         if Local_Name = "Buckets" then
            if Item.Seen_Buckets then
               raise Malformed_Bucket_Listing with
                 "duplicate ListBuckets field";
            end if;
            Item.Seen_Buckets := True;
            Item.Context := Buckets_Context;
         elsif Local_Name = "Owner" then
            if Item.Seen_Owner then
               raise Malformed_Bucket_Listing with
                 "duplicate ListBuckets field";
            end if;
            Item.Seen_Owner := True;
            Item.Value.Has_Owner := True;
            Item.Value.Owner := (others => <>);
            Item.Context := Owner_Context;
         elsif Local_Name = "ContinuationToken" then
            Select_Field
              (Item, Item.Seen_Continuation_Token,
               Continuation_Token_Field);
         elsif Local_Name = "Prefix" then
            Select_Field (Item, Item.Seen_Prefix, Prefix_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Context = Buckets_Context then
         if Local_Name = "Bucket" then
            Item.Context := Bucket_Context_Value;
            Item.Current_Bucket := (others => <>);
            Item.Seen_Name := False;
            Item.Seen_Creation_Date := False;
            Item.Seen_Bucket_Region := False;
            Item.Seen_Bucket_ARN := False;
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 3 and then Item.Context = Owner_Context then
         if Local_Name = "DisplayName" then
            Select_Field
              (Item, Item.Seen_Owner_Display_Name,
               Owner_Display_Name_Field);
         elsif Local_Name = "ID" then
            Select_Field (Item, Item.Seen_Owner_ID, Owner_ID_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      elsif Item.Depth = 4 and then Item.Context = Bucket_Context_Value then
         if Local_Name = "Name" then
            Select_Field (Item, Item.Seen_Name, Name_Field);
         elsif Local_Name = "CreationDate" then
            Select_Field
              (Item, Item.Seen_Creation_Date, Creation_Date_Field);
         elsif Local_Name = "BucketRegion" then
            Select_Field
              (Item, Item.Seen_Bucket_Region, Bucket_Region_Field);
         elsif Local_Name = "BucketArn" then
            Select_Field (Item, Item.Seen_Bucket_ARN, Bucket_ARN_Field);
         else
            Item.Ignore_Depth := Item.Depth;
         end if;
      else
         raise Malformed_Bucket_Listing with
           "nested ListBuckets field";
      end if;
   end Start_Element;

   overriding procedure Text
     (Item : in out Bucket_Handler; Value : String) is
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
     (Item : in out Bucket_Handler; Local_Name : String)
   is
      pragma Unreferenced (Local_Name);
   begin
      if Item.Depth = 0 then
         raise Malformed_Bucket_Listing with
           "ListBuckets stack underflow";
      elsif Item.Ignore_Depth /= 0 then
         if Item.Depth = Item.Ignore_Depth then
            Item.Ignore_Depth := 0;
         end if;
      elsif Item.Field /= No_Field then
         Finish_Field (Item);
      elsif Item.Depth = 3 and then Item.Context = Bucket_Context_Value then
         if Item.Value.Buckets.Length = 10_000 then
            raise Malformed_Bucket_Listing with
              "ListBuckets result exceeds MaxBuckets";
         end if;
         Item.Value.Buckets.Append (Item.Current_Bucket);
         Item.Context := Buckets_Context;
      elsif Item.Depth = 2
        and then Item.Context in Buckets_Context | Owner_Context
      then
         Item.Context := Root_Context;
      end if;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Validate (Value : List_Buckets_Result) is
   begin
      if Value.Buckets.Length > 10_000 then
         raise Malformed_Bucket_Listing with
           "ListBuckets result exceeds MaxBuckets";
      elsif not Value.Has_Owner
        and then
          (US.Length (Value.Owner.Display_Name) > 0
           or else US.Length (Value.Owner.ID) > 0)
      then
         raise Malformed_Bucket_Listing with
           "ListBuckets owner lacks presence state";
      end if;
   end Validate;

   function Parse_List_Buckets
     (Document : String;
      Limits   : XML.Parse_Limits := XML.Default_Limits)
      return List_Buckets_Result
   is
      Handler : aliased Bucket_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      Validate (Handler.Value);
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Bucket_Listing with
           "malformed ListBuckets XML";
   end Parse_List_Buckets;

   procedure Append_Optional
     (Target : in out US.Unbounded_String; Name, Value : String) is
   begin
      if Value'Length > 0 then
         US.Append (Target, Element (Name, Value));
      end if;
   end Append_Optional;

   function Serialize_List_Buckets
     (Value : List_Buckets_Result) return String
   is
      Result : US.Unbounded_String;
   begin
      Validate (Value);
      US.Append
        (Result,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<ListAllMyBucketsResult xmlns=""http://s3.amazonaws.com/doc/" &
         "2006-03-01/"">");
      if Value.Has_Owner then
         US.Append (Result, "<Owner>");
         Append_Optional
           (Result, "DisplayName", US.To_String (Value.Owner.Display_Name));
         Append_Optional (Result, "ID", US.To_String (Value.Owner.ID));
         US.Append (Result, "</Owner>");
      end if;
      US.Append (Result, "<Buckets>");
      for Bucket of Value.Buckets loop
         US.Append (Result, "<Bucket>");
         Append_Optional (Result, "Name", US.To_String (Bucket.Name));
         Append_Optional
           (Result, "CreationDate", US.To_String (Bucket.Creation_Date));
         Append_Optional
           (Result, "BucketRegion", US.To_String (Bucket.Bucket_Region));
         Append_Optional
           (Result, "BucketArn", US.To_String (Bucket.Bucket_ARN));
         US.Append (Result, "</Bucket>");
      end loop;
      US.Append (Result, "</Buckets>");
      Append_Optional
        (Result, "ContinuationToken",
         US.To_String (Value.Continuation_Token));
      Append_Optional (Result, "Prefix", US.To_String (Value.Prefix));
      US.Append (Result, "</ListAllMyBucketsResult>");
      return US.To_String (Result);
   exception
      when XML.XML_Error =>
         raise Malformed_Bucket_Listing with
           "ListBuckets result contains invalid XML text";
   end Serialize_List_Buckets;

end Flyology.Object_Storage.S3.Buckets;
