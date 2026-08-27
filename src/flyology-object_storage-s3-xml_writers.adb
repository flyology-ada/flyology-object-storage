package body Flyology.Object_Storage.S3.XML_Writers is

   package US renames Ada.Strings.Unbounded;

   procedure Append (Item : in out Writer; Fragment : String) is
      Current : constant Natural := US.Length (Item.Data);
   begin
      if Fragment'Length > Item.Limits.Maximum_Document_Bytes - Current then
         raise Encoding_Error with "XML document exceeds caller limit";
      end if;
      US.Append (Item.Data, Fragment);
   end Append;

   procedure Close_Start (Item : in out Writer) is
   begin
      if Item.Start_Is_Open then
         Append (Item, ">");
         Item.Start_Is_Open := False;
      end if;
   end Close_Start;

   procedure Initialize
     (Item   : out Writer;
      Limits : Flyology.Object_Storage.S3.XML.Parse_Limits) is
   begin
      Item.Limits := Limits;
      US.Set_Unbounded_String (Item.Data, "");
      Item.Depth := 0;
      Item.Elements := 0;
      Item.Text_Bytes := 0;
      Item.Start_Is_Open := False;
      Item.Started := False;
      Item.Finished := False;
   end Initialize;

   procedure Begin_Element (Item : in out Writer; Name : String) is
   begin
      if Item.Finished then
         raise Encoding_Error with "XML writer is already finished";
      elsif Item.Depth = Item.Limits.Maximum_Depth then
         raise Encoding_Error with "XML depth exceeds caller limit";
      elsif Item.Elements = Item.Limits.Maximum_Elements then
         raise Encoding_Error with "XML elements exceed caller limit";
      end if;
      Close_Start (Item);
      Item.Depth := Item.Depth + 1;
      Item.Elements := Item.Elements + 1;
      Append (Item, "<" & Name);
      Item.Start_Is_Open := True;
   end Begin_Element;

   procedure Start_Document
     (Item          : in out Writer;
      Root_Name     : String;
      Namespace_URI : String) is
   begin
      if Item.Started then
         raise Encoding_Error with "XML writer is already started";
      end if;
      Item.Started := True;
      Begin_Element (Item, Root_Name);
      if Namespace_URI'Length > 0 then
         Attribute (Item, "xmlns", Namespace_URI, "", "");
      end if;
   end Start_Document;

   procedure Start_Element (Item : in out Writer; Name : String) is
   begin
      if not Item.Started then
         raise Encoding_Error with "XML writer is not started";
      end if;
      Begin_Element (Item, Name);
   end Start_Element;

   procedure End_Element (Item : in out Writer; Name : String) is
   begin
      if Item.Depth = 0 then
         raise Encoding_Error with "XML element stack is empty";
      end if;
      Close_Start (Item);
      Append (Item, "</" & Name & ">");
      Item.Depth := Item.Depth - 1;
   end End_Element;

   procedure Empty_Element (Item : in out Writer; Name : String) is
   begin
      Start_Element (Item, Name);
      Append (Item, "/>");
      Item.Start_Is_Open := False;
      Item.Depth := Item.Depth - 1;
   end Empty_Element;

   procedure Append_Text (Item : in out Writer; Text : String) is
   begin
      Close_Start (Item);
      if Text'Length > Item.Limits.Maximum_Text_Bytes - Item.Text_Bytes then
         raise Encoding_Error with "XML text exceeds caller limit";
      end if;
      Item.Text_Bytes := Item.Text_Bytes + Text'Length;
      Append (Item, Flyology.Object_Storage.S3.XML.Escape_Text (Text));
   end Append_Text;

   procedure Text_Element
     (Item : in out Writer;
      Name : String;
      Text : String) is
   begin
      Start_Element (Item, Name);
      Append_Text (Item, Text);
      End_Element (Item, Name);
   end Text_Element;

   procedure Attribute
     (Item          : in out Writer;
      Name          : String;
      Value         : String;
      Namespace_URI : String;
      Prefix        : String) is
   begin
      if not Item.Start_Is_Open then
         raise Encoding_Error with "XML attributes follow element content";
      end if;
      if Namespace_URI'Length > 0 then
         if Prefix'Length = 0 then
            raise Encoding_Error with "namespaced XML attribute lacks prefix";
         end if;
         Append
           (Item,
            " xmlns:" & Prefix & "=""" &
            Flyology.Object_Storage.S3.XML.Escape_Attribute (Namespace_URI) &
            """");
      end if;
      Append
        (Item,
         " " & (if Prefix'Length = 0 then "" else Prefix & ":") & Name &
         "=""" & Flyology.Object_Storage.S3.XML.Escape_Attribute (Value) &
         """");
   end Attribute;

   function Finish (Item : in out Writer; Root_Name : String) return String is
   begin
      if not Item.Started or else Item.Finished or else Item.Depth /= 1 then
         raise Encoding_Error with "XML document is structurally incomplete";
      end if;
      End_Element (Item, Root_Name);
      Item.Finished := True;
      return US.To_String (Item.Data);
   end Finish;

end Flyology.Object_Storage.S3.XML_Writers;
