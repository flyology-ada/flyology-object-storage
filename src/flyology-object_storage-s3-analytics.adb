package body Flyology.Object_Storage.S3.Analytics is

   package US renames Ada.Strings.Unbounded;

   type Namespace_Style is
     (Namespace_Not_Selected, Unqualified, S3_Qualified);
   type Container_Kind is
     (No_Container, Root_Container, Filter_Container,
      Direct_Tag_Container, And_Container, And_Tag_Container,
      Analysis_Container, Data_Export_Container,
      Export_Destination_Container, S3_Destination_Container);
   type Scalar_Kind is
     (No_Scalar, ID_Scalar, Filter_Prefix_Scalar,
      Direct_Tag_Key_Scalar, Direct_Tag_Value_Scalar,
      And_Prefix_Scalar, And_Tag_Key_Scalar, And_Tag_Value_Scalar,
      Schema_Version_Scalar, Export_Format_Scalar,
      Bucket_Account_ID_Scalar, Bucket_Scalar,
      Destination_Prefix_Scalar);

   function Empty_String return Optional_String is
     ((Is_Set => False, Value => US.Null_Unbounded_String));

   function Empty_Tag return Analytics_Tag is
     ((Key => US.Null_Unbounded_String,
       Value => US.Null_Unbounded_String));

   function Empty_Configuration return Analytics_Configuration is
     --  CSV and V_1 are neutral construction values derived from the pinned
     --  single-value enum domains. Seen flags below prevent either value from
     --  being accepted when the required wire member is absent.
     ((ID     => US.Null_Unbounded_String,
       Filter =>
         (Is_Set         => False,
          Prefix         => Empty_String,
          Tag            => (Is_Set => False, Value => Empty_Tag),
          And_Predicates =>
            (Is_Set => False,
             Prefix => Empty_String,
             Tags   => Tag_Vectors.Empty_Vector)),
       Storage_Class_Analysis =>
         (Data_Export =>
            (Is_Set => False,
             Value  =>
               (Output_Schema_Version => V_1,
                Destination           =>
                  (S3_Bucket =>
                     (Format            => CSV,
                      Bucket_Account_ID => Empty_String,
                      Bucket            => US.Null_Unbounded_String,
                      Prefix            => Empty_String)))))));

   type Analytics_Handler is new XML.Event_Handler with record
      Depth                    : Natural := 0;
      Root_Seen                : Boolean := False;
      ID_Seen                  : Boolean := False;
      Filter_Seen              : Boolean := False;
      Filter_Prefix_Seen       : Boolean := False;
      Filter_Tag_Seen          : Boolean := False;
      And_Seen                 : Boolean := False;
      And_Prefix_Seen          : Boolean := False;
      Analysis_Seen            : Boolean := False;
      Data_Export_Seen         : Boolean := False;
      Schema_Version_Seen      : Boolean := False;
      Destination_Seen         : Boolean := False;
      S3_Destination_Seen      : Boolean := False;
      Export_Format_Seen       : Boolean := False;
      Bucket_Account_ID_Seen   : Boolean := False;
      Bucket_Seen              : Boolean := False;
      Destination_Prefix_Seen  : Boolean := False;
      Tag_Key_Seen             : Boolean := False;
      Tag_Value_Seen           : Boolean := False;
      Namespace                : Namespace_Style := Namespace_Not_Selected;
      Container                : Container_Kind := No_Container;
      Scalar                   : Scalar_Kind := No_Scalar;
      Text_Value               : US.Unbounded_String;
      Current_Tag              : Analytics_Tag := Empty_Tag;
      Value                    : Analytics_Configuration :=
        Empty_Configuration;
   end record;

   overriding procedure Start_Element
     (Item : in out Analytics_Handler; Local_Name : String);
   overriding procedure Start_Element_Details
     (Item            : in out Analytics_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural);
   overriding procedure Text
     (Item : in out Analytics_Handler; Value : String);
   overriding procedure End_Element
     (Item : in out Analytics_Handler; Local_Name : String);

   procedure Require_Whitespace (Value : String) is
   begin
      for Character of Value loop
         if Character not in ' ' | ASCII.HT | ASCII.LF | ASCII.CR then
            raise Malformed_Analytics with
              "text outside analytics scalar";
         end if;
      end loop;
   end Require_Whitespace;

   overriding procedure Start_Element_Details
     (Item            : in out Analytics_Handler;
      Namespace_URI   : String;
      Attribute_Count : Natural)
   is
      --  The S3 REST/XML namespace is the established provider wire
      --  authority; accepting another URI would change compatibility.
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
         raise Malformed_Analytics with
           "analytics namespace or attributes are invalid";
      end if;
      Item.Namespace := Style;
   end Start_Element_Details;

   procedure Begin_Scalar
     (Item : in out Analytics_Handler; Kind : Scalar_Kind) is
   begin
      Item.Scalar := Kind;
      Item.Text_Value := US.Null_Unbounded_String;
   end Begin_Scalar;

   procedure Begin_Tag
     (Item : in out Analytics_Handler; Kind : Container_Kind) is
   begin
      Item.Container := Kind;
      Item.Tag_Key_Seen := False;
      Item.Tag_Value_Seen := False;
      Item.Current_Tag := Empty_Tag;
   end Begin_Tag;

   overriding procedure Start_Element
     (Item : in out Analytics_Handler; Local_Name : String) is
   begin
      if Item.Depth = Natural'Last then
         raise Malformed_Analytics with "analytics depth overflow";
      elsif Item.Scalar /= No_Scalar then
         raise Malformed_Analytics with "analytics scalar contains element";
      end if;
      Item.Depth := Item.Depth + 1;

      if Item.Depth = 1 then
         if Item.Root_Seen or else Local_Name /= "AnalyticsConfiguration" then
            raise Malformed_Analytics with "invalid analytics root";
         end if;
         Item.Root_Seen := True;
         Item.Container := Root_Container;
         return;
      end if;

      case Item.Container is
         when Root_Container =>
            if Local_Name = "Id" and then not Item.ID_Seen then
               Item.ID_Seen := True;
               Begin_Scalar (Item, ID_Scalar);
            elsif Local_Name = "Filter" and then not Item.Filter_Seen then
               Item.Filter_Seen := True;
               Item.Value.Filter.Is_Set := True;
               Item.Container := Filter_Container;
            elsif Local_Name = "StorageClassAnalysis"
              and then not Item.Analysis_Seen
            then
               Item.Analysis_Seen := True;
               Item.Container := Analysis_Container;
            else
               raise Malformed_Analytics with
                 "unknown or duplicate analytics member";
            end if;

         when Filter_Container =>
            if Local_Name = "Prefix"
              and then not Item.Filter_Prefix_Seen
            then
               Item.Filter_Prefix_Seen := True;
               Begin_Scalar (Item, Filter_Prefix_Scalar);
            elsif Local_Name = "Tag" and then not Item.Filter_Tag_Seen then
               Item.Filter_Tag_Seen := True;
               Item.Value.Filter.Tag.Is_Set := True;
               Begin_Tag (Item, Direct_Tag_Container);
            elsif Local_Name = "And" and then not Item.And_Seen then
               Item.And_Seen := True;
               Item.Value.Filter.And_Predicates.Is_Set := True;
               Item.Container := And_Container;
            else
               raise Malformed_Analytics with
                 "unknown or duplicate analytics filter member";
            end if;

         when Direct_Tag_Container | And_Tag_Container =>
            if Local_Name = "Key" and then not Item.Tag_Key_Seen then
               Item.Tag_Key_Seen := True;
               Begin_Scalar
                 (Item,
                  (if Item.Container = Direct_Tag_Container
                   then Direct_Tag_Key_Scalar
                   else And_Tag_Key_Scalar));
            elsif Local_Name = "Value" and then not Item.Tag_Value_Seen then
               Item.Tag_Value_Seen := True;
               Begin_Scalar
                 (Item,
                  (if Item.Container = Direct_Tag_Container
                   then Direct_Tag_Value_Scalar
                   else And_Tag_Value_Scalar));
            else
               raise Malformed_Analytics with
                 "unknown or duplicate analytics tag member";
            end if;

         when And_Container =>
            if Local_Name = "Prefix" and then not Item.And_Prefix_Seen then
               Item.And_Prefix_Seen := True;
               Begin_Scalar (Item, And_Prefix_Scalar);
            elsif Local_Name = "Tag" then
               Begin_Tag (Item, And_Tag_Container);
            else
               raise Malformed_Analytics with
                 "unknown or duplicate analytics And member";
            end if;

         when Analysis_Container =>
            if Local_Name = "DataExport"
              and then not Item.Data_Export_Seen
            then
               Item.Data_Export_Seen := True;
               Item.Value.Storage_Class_Analysis.Data_Export.Is_Set := True;
               Item.Container := Data_Export_Container;
            else
               raise Malformed_Analytics with
                 "unknown or duplicate storage-class analysis member";
            end if;

         when Data_Export_Container =>
            if Local_Name = "OutputSchemaVersion"
              and then not Item.Schema_Version_Seen
            then
               Item.Schema_Version_Seen := True;
               Begin_Scalar (Item, Schema_Version_Scalar);
            elsif Local_Name = "Destination"
              and then not Item.Destination_Seen
            then
               Item.Destination_Seen := True;
               Item.Container := Export_Destination_Container;
            else
               raise Malformed_Analytics with
                 "unknown or duplicate analytics data-export member";
            end if;

         when Export_Destination_Container =>
            if Local_Name = "S3BucketDestination"
              and then not Item.S3_Destination_Seen
            then
               Item.S3_Destination_Seen := True;
               Item.Container := S3_Destination_Container;
            else
               raise Malformed_Analytics with
                 "unknown or duplicate analytics destination member";
            end if;

         when S3_Destination_Container =>
            if Local_Name = "Format"
              and then not Item.Export_Format_Seen
            then
               Item.Export_Format_Seen := True;
               Begin_Scalar (Item, Export_Format_Scalar);
            elsif Local_Name = "BucketAccountId"
              and then not Item.Bucket_Account_ID_Seen
            then
               Item.Bucket_Account_ID_Seen := True;
               Begin_Scalar (Item, Bucket_Account_ID_Scalar);
            elsif Local_Name = "Bucket" and then not Item.Bucket_Seen then
               Item.Bucket_Seen := True;
               Begin_Scalar (Item, Bucket_Scalar);
            elsif Local_Name = "Prefix"
              and then not Item.Destination_Prefix_Seen
            then
               Item.Destination_Prefix_Seen := True;
               Begin_Scalar (Item, Destination_Prefix_Scalar);
            else
               raise Malformed_Analytics with
                 "unknown or duplicate S3 analytics destination member";
            end if;

         when No_Container =>
            raise Malformed_Analytics with "analytics element outside root";
      end case;
   end Start_Element;

   overriding procedure Text
     (Item : in out Analytics_Handler; Value : String) is
   begin
      if Item.Scalar /= No_Scalar then
         US.Append (Item.Text_Value, Value);
      elsif Item.Depth > 0 then
         Require_Whitespace (Value);
      else
         raise Malformed_Analytics with
           "analytics text outside document";
      end if;
   end Text;

   function Scalar_Name (Kind : Scalar_Kind) return String is
     (case Kind is
         when ID_Scalar => "Id",
         when Filter_Prefix_Scalar | And_Prefix_Scalar |
              Destination_Prefix_Scalar => "Prefix",
         when Direct_Tag_Key_Scalar | And_Tag_Key_Scalar => "Key",
         when Direct_Tag_Value_Scalar | And_Tag_Value_Scalar => "Value",
         when Schema_Version_Scalar => "OutputSchemaVersion",
         when Export_Format_Scalar => "Format",
         when Bucket_Account_ID_Scalar => "BucketAccountId",
         when Bucket_Scalar => "Bucket",
         when No_Scalar => "");

   procedure Store_Scalar (Item : in out Analytics_Handler) is
      Text : constant String := US.To_String (Item.Text_Value);
   begin
      case Item.Scalar is
         when ID_Scalar =>
            Item.Value.ID := Item.Text_Value;
         when Filter_Prefix_Scalar =>
            Item.Value.Filter.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when And_Prefix_Scalar =>
            Item.Value.Filter.And_Predicates.Prefix :=
              (Is_Set => True, Value => Item.Text_Value);
         when Direct_Tag_Key_Scalar | And_Tag_Key_Scalar =>
            if US.Length (Item.Text_Value) = 0 then
               raise Malformed_Analytics with "empty analytics tag key";
            end if;
            Item.Current_Tag.Key := Item.Text_Value;
         when Direct_Tag_Value_Scalar | And_Tag_Value_Scalar =>
            Item.Current_Tag.Value := Item.Text_Value;
         when Schema_Version_Scalar =>
            if Text /= "V_1" then
               raise Malformed_Analytics with
                 "invalid analytics schema version";
            end if;
            Item.Value.Storage_Class_Analysis.Data_Export.Value.
              Output_Schema_Version := V_1;
         when Export_Format_Scalar =>
            if Text /= "CSV" then
               raise Malformed_Analytics with
                 "invalid analytics export format";
            end if;
            Item.Value.Storage_Class_Analysis.Data_Export.Value.Destination.
              S3_Bucket.
              Format := CSV;
         when Bucket_Account_ID_Scalar =>
            Item.Value.Storage_Class_Analysis.Data_Export.Value.Destination.
              S3_Bucket.
              Bucket_Account_ID :=
                (Is_Set => True, Value => Item.Text_Value);
         when Bucket_Scalar =>
            Item.Value.Storage_Class_Analysis.Data_Export.Value.Destination.
              S3_Bucket.
              Bucket := Item.Text_Value;
         when Destination_Prefix_Scalar =>
            Item.Value.Storage_Class_Analysis.Data_Export.Value.Destination.
              S3_Bucket.
              Prefix := (Is_Set => True, Value => Item.Text_Value);
         when No_Scalar =>
            raise Malformed_Analytics with "analytics close without scalar";
      end case;
      Item.Scalar := No_Scalar;
      Item.Text_Value := US.Null_Unbounded_String;
   end Store_Scalar;

   procedure Finish_Tag (Item : in out Analytics_Handler) is
   begin
      if not Item.Tag_Key_Seen or else not Item.Tag_Value_Seen then
         raise Malformed_Analytics with "incomplete analytics tag";
      elsif Item.Container = Direct_Tag_Container then
         Item.Value.Filter.Tag.Value := Item.Current_Tag;
         Item.Container := Filter_Container;
      elsif Item.Container = And_Tag_Container then
         Item.Value.Filter.And_Predicates.Tags.Append (Item.Current_Tag);
         Item.Container := And_Container;
      else
         raise Malformed_Analytics with "analytics tag outside filter";
      end if;
   end Finish_Tag;

   overriding procedure End_Element
     (Item : in out Analytics_Handler; Local_Name : String) is
   begin
      if Item.Depth = 0 then
         raise Malformed_Analytics with "analytics close outside document";
      elsif Item.Scalar /= No_Scalar then
         if Local_Name /= Scalar_Name (Item.Scalar) then
            raise Malformed_Analytics with
              "mismatched analytics scalar close";
         end if;
         Store_Scalar (Item);
         Item.Depth := Item.Depth - 1;
         return;
      end if;

      case Item.Container is
         when Direct_Tag_Container | And_Tag_Container =>
            if Local_Name /= "Tag" then
               raise Malformed_Analytics with
                 "invalid analytics tag close";
            end if;
            Finish_Tag (Item);
         when And_Container =>
            if Local_Name /= "And" then
               raise Malformed_Analytics with
                 "invalid analytics And close";
            end if;
            Item.Container := Filter_Container;
         when Filter_Container =>
            if Local_Name /= "Filter" then
               raise Malformed_Analytics with
                 "invalid analytics filter close";
            end if;
            Item.Container := Root_Container;
         when S3_Destination_Container =>
            if Local_Name /= "S3BucketDestination"
              or else not Item.Export_Format_Seen
              or else not Item.Bucket_Seen
            then
               raise Malformed_Analytics with
                 "incomplete analytics S3 destination";
            end if;
            Item.Container := Export_Destination_Container;
         when Export_Destination_Container =>
            if Local_Name /= "Destination"
              or else not Item.S3_Destination_Seen
            then
               raise Malformed_Analytics with
                 "incomplete analytics export destination";
            end if;
            Item.Container := Data_Export_Container;
         when Data_Export_Container =>
            if Local_Name /= "DataExport"
              or else not Item.Schema_Version_Seen
              or else not Item.Destination_Seen
            then
               raise Malformed_Analytics with
                 "incomplete analytics data export";
            end if;
            Item.Container := Analysis_Container;
         when Analysis_Container =>
            if Local_Name /= "StorageClassAnalysis" then
               raise Malformed_Analytics with
                 "invalid storage-class analysis close";
            end if;
            Item.Container := Root_Container;
         when Root_Container =>
            if Local_Name /= "AnalyticsConfiguration"
              or else not Item.ID_Seen
              or else not Item.Analysis_Seen
            then
               raise Malformed_Analytics with
                 "incomplete analytics configuration";
            end if;
            Item.Container := No_Container;
         when No_Container =>
            raise Malformed_Analytics with
              "analytics container close outside document";
      end case;
      Item.Depth := Item.Depth - 1;
   end End_Element;

   function Parse
     (Document : String; Limits : XML.Parse_Limits)
      return Analytics_Configuration
   is
      Handler : aliased Analytics_Handler;
   begin
      XML.Parse (Document, Handler, Limits);
      if Handler.Depth /= 0
        or else not Handler.Root_Seen
        or else Handler.Container /= No_Container
      then
         raise Malformed_Analytics with
           "incomplete analytics document";
      end if;
      return Handler.Value;
   exception
      when XML.XML_Error =>
         raise Malformed_Analytics with "malformed analytics XML";
   end Parse;

end Flyology.Object_Storage.S3.Analytics;
