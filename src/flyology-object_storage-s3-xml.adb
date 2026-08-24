with Input_Sources;
with Input_Sources.Strings;
with Sax.Readers;
with Sax.Symbols;
with Sax.Utils;
with Unicode.CES;
with Unicode.CES.Utf8;

package body Flyology.Object_Storage.S3.XML is

   type Handler_Access is access all Event_Handler'Class;

   type Secure_Reader is new Sax.Readers.Sax_Reader with record
      Receiver : Handler_Access;
      Limits   : Parse_Limits;
      Depth    : Natural := 0;
      Elements : Natural := 0;
      Text_Bytes : Natural := 0;
   end record;

   overriding procedure Start_Element
     (Handler    : in out Secure_Reader;
      NS         : Sax.Utils.XML_NS;
      Local_Name : Sax.Symbols.Symbol;
      Atts       : Sax.Readers.Sax_Attribute_List);

   overriding procedure End_Element
     (Handler    : in out Secure_Reader;
      NS         : Sax.Utils.XML_NS;
      Local_Name : Sax.Symbols.Symbol);

   overriding procedure Characters
     (Handler : in out Secure_Reader;
      Ch      : Unicode.CES.Byte_Sequence);

   overriding procedure Start_DTD
     (Handler   : in out Secure_Reader;
      Name      : Unicode.CES.Byte_Sequence;
      Public_Id : Unicode.CES.Byte_Sequence := "";
      System_Id : Unicode.CES.Byte_Sequence := "");

   overriding procedure Processing_Instruction
     (Handler : in out Secure_Reader;
      Target  : Unicode.CES.Byte_Sequence;
      Data    : Unicode.CES.Byte_Sequence);

   overriding procedure Skipped_Entity
     (Handler : in out Secure_Reader;
      Name    : Sax.Symbols.Symbol);

   overriding function Resolve_Entity
     (Handler   : Secure_Reader;
      Public_Id : Unicode.CES.Byte_Sequence;
      System_Id : Unicode.CES.Byte_Sequence)
      return Input_Sources.Input_Source_Access;

   function Symbol_Text (Value : Sax.Symbols.Symbol) return String is
     (Sax.Symbols.Get (Value).all);

   overriding procedure Start_Element
     (Handler    : in out Secure_Reader;
      NS         : Sax.Utils.XML_NS;
      Local_Name : Sax.Symbols.Symbol;
      Atts       : Sax.Readers.Sax_Attribute_List)
   is
      Name : Sax.Readers.Qualified_Name;
   begin
      if Handler.Depth = Handler.Limits.Maximum_Depth
        or else Handler.Elements = Handler.Limits.Maximum_Elements
      then
         raise XML_Error with "S3 XML structural limit exceeded";
      end if;
      Handler.Depth := Handler.Depth + 1;
      Handler.Elements := Handler.Elements + 1;
      Start_Element_Details
        (Handler.Receiver.all,
         Symbol_Text (Sax.Utils.Get_URI (NS)),
         Sax.Readers.Get_Length (Atts));
      for Index in 1 .. Sax.Readers.Get_Length (Atts) loop
         Name := Sax.Readers.Get_Name (Atts, Index);
         Element_Attribute
           (Handler.Receiver.all,
            Symbol_Text (Local_Name),
            Symbol_Text (Name.NS),
            Symbol_Text (Name.Local),
            Symbol_Text (Sax.Readers.Get_Value (Atts, Index)));
      end loop;
      Start_Element (Handler.Receiver.all, Symbol_Text (Local_Name));
   end Start_Element;

   overriding procedure End_Element
     (Handler    : in out Secure_Reader;
      NS         : Sax.Utils.XML_NS;
      Local_Name : Sax.Symbols.Symbol)
   is
      pragma Unreferenced (NS);
   begin
      if Handler.Depth = 0 then
         raise XML_Error with "S3 XML element stack underflow";
      end if;
      End_Element (Handler.Receiver.all, Symbol_Text (Local_Name));
      Handler.Depth := Handler.Depth - 1;
   end End_Element;

   overriding procedure Characters
     (Handler : in out Secure_Reader;
      Ch      : Unicode.CES.Byte_Sequence)
   is
   begin
      if Ch'Length > Handler.Limits.Maximum_Text_Bytes
        or else Handler.Text_Bytes >
          Handler.Limits.Maximum_Text_Bytes - Ch'Length
      then
         raise XML_Error with "S3 XML text limit exceeded";
      end if;
      Handler.Text_Bytes := Handler.Text_Bytes + Ch'Length;
      Text (Handler.Receiver.all, String (Ch));
   end Characters;

   overriding procedure Start_DTD
     (Handler   : in out Secure_Reader;
      Name      : Unicode.CES.Byte_Sequence;
      Public_Id : Unicode.CES.Byte_Sequence := "";
      System_Id : Unicode.CES.Byte_Sequence := "")
   is
      pragma Unreferenced (Handler, Name, Public_Id, System_Id);
   begin
      raise XML_Error with "DTD declarations are forbidden in S3 XML";
   end Start_DTD;

   overriding procedure Processing_Instruction
     (Handler : in out Secure_Reader;
      Target  : Unicode.CES.Byte_Sequence;
      Data    : Unicode.CES.Byte_Sequence)
   is
      pragma Unreferenced (Handler, Target, Data);
   begin
      raise XML_Error with "processing instructions are forbidden in S3 XML";
   end Processing_Instruction;

   overriding procedure Skipped_Entity
     (Handler : in out Secure_Reader;
      Name    : Sax.Symbols.Symbol)
   is
      pragma Unreferenced (Handler, Name);
   begin
      raise XML_Error with "entities are forbidden in S3 XML";
   end Skipped_Entity;

   overriding function Resolve_Entity
     (Handler   : Secure_Reader;
      Public_Id : Unicode.CES.Byte_Sequence;
      System_Id : Unicode.CES.Byte_Sequence)
      return Input_Sources.Input_Source_Access
   is
      pragma Unreferenced (Handler, Public_Id, System_Id);
   begin
      return
        (raise XML_Error with "external entities are forbidden in S3 XML");
   end Resolve_Entity;

   procedure Parse
     (Document : String;
      Receiver : aliased in out Event_Handler'Class;
      Limits   : Parse_Limits := Default_Limits)
   is
      Input  : Input_Sources.Strings.String_Input;
      Reader : Secure_Reader :=
        (Sax.Readers.Sax_Reader with
         Receiver   => Receiver'Unchecked_Access,
         Limits     => Limits,
         Depth      => 0,
         Elements   => 0,
         Text_Bytes => 0);
      Opened : Boolean := False;
   begin
      if Document'Length > Limits.Maximum_Document_Bytes then
         raise XML_Error with "S3 XML document limit exceeded";
      end if;
      Reader.Set_Feature
        (Sax.Readers.External_General_Entities_Feature, False);
      Reader.Set_Feature
        (Sax.Readers.External_Parameter_Entities_Feature, False);
      Reader.Set_Feature (Sax.Readers.Parameter_Entities_Feature, False);
      Reader.Set_Feature (Sax.Readers.Test_Valid_Chars_Feature, True);
      Input_Sources.Strings.Open
        (Unicode.CES.Byte_Sequence (Document),
         Unicode.CES.Utf8.Utf8_Encoding,
         Input);
      Opened := True;
      Reader.Parse (Input);
      Input_Sources.Strings.Close (Input);
      Opened := False;
      if Reader.Depth /= 0 then
         raise XML_Error with "S3 XML ended with open elements";
      end if;
   exception
      when XML_Error =>
         if Opened then
            Input_Sources.Strings.Close (Input);
         end if;
         raise;
      when others =>
         if Opened then
            Input_Sources.Strings.Close (Input);
         end if;
         raise XML_Error with "malformed S3 XML document";
   end Parse;

   function Escape
     (Value : String; Attribute : Boolean) return String
   is
   begin
      if Value'Length > Natural'Last / 6 then
         raise XML_Error with "XML value is too large to escape";
      end if;
      declare
         Result : String (1 .. 6 * Value'Length) :=
           (others => Character'Val (0));
         Used : Natural := 0;

         procedure Append (Text : String) is
         begin
            Result (Used + 1 .. Used + Text'Length) := Text;
            Used := Used + Text'Length;
         end Append;
      begin
         for Item of Value loop
            if Character'Pos (Item) < 32
              and then Item /= Character'Val (9)
              and then Item /= Character'Val (10)
              and then Item /= Character'Val (13)
            then
               raise XML_Error with "invalid XML character";
            elsif Item = '&' then
               Append ("&amp;");
            elsif Item = '<' then
               Append ("&lt;");
            elsif Item = '>' then
               Append ("&gt;");
            elsif Attribute and then Item = '"' then
               Append ("&quot;");
            elsif Attribute and then Item = Character'Val (39) then
               Append ("&apos;");
            else
               Append (String'(1 => Item));
            end if;
         end loop;
         return Result (1 .. Used);
      end;
   end Escape;

   function Escape_Text (Value : String) return String is
     (Escape (Value, Attribute => False));

   function Escape_Attribute (Value : String) return String is
     (Escape (Value, Attribute => True));

end Flyology.Object_Storage.S3.XML;
