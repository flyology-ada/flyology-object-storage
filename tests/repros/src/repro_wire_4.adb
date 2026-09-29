--  WIRE-4: a key containing CR (U+000D) passes XML.Escape_Text unchanged
--  (Escape allows TAB, LF and CR), so a listing without encoding-type=url
--  emits the CR literally in the <Key> text.  XML 1.0 end-of-line
--  normalization turns a literal CR in character data into LF, so a
--  conforming client -- including the crate's own S3.XML.Parse -- reads back
--  a different key from the one stored, with no error anywhere.  This
--  program asserts the CORRECT behavior: the key the listing reports is the
--  key that was stored.
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Wire_4 is

   package US renames Ada.Strings.Unbounded;
   package XML renames Flyology.Object_Storage.S3.XML;

   Bucket : constant String := "wire-four-bucket";

   CR : constant Character := Character'Val (13);
   Key_Decoded : constant String := "a" & CR & "b";
   Key_Wire    : constant String := "a%0Db";

   function Signed_Wire
     (Method       : String;
      Wire_Path    : String;
      Decoded_Path : String;
      Payload      : String := "") return String
   is
      Stamp        : constant String := Timestamp;
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers      : constant SigV4.Name_Value_Array (1 .. 3) :=
        [SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Stamp)];
      Signing : constant SigV4.Signing_Result := SigV4.Sign
        (Method, Decoded_Path, No_Query, Headers, Payload_Hash, Access_Key,
         Secret_Key, Region, Stamp);
   begin
      return Method & " " & Wire_Path & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "x-amz-date: " & Stamp & CRLF &
        "x-amz-content-sha256: " & Payload_Hash & CRLF &
        "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
        "Content-Length: " & Image (Payload'Length) & CRLF &
        "Connection: close" & CRLF & CRLF & Payload;
   end Signed_Wire;

   type Key_Collector is limited new XML.Event_Handler with record
      In_Key : Boolean := False;
      Keys   : US.Unbounded_String;
      Count  : Natural := 0;
   end record;

   overriding procedure Start_Element
     (Item : in out Key_Collector; Local_Name : String);
   overriding procedure Text (Item : in out Key_Collector; Value : String);
   overriding procedure End_Element
     (Item : in out Key_Collector; Local_Name : String);

   overriding procedure Start_Element
     (Item : in out Key_Collector; Local_Name : String) is
   begin
      Item.In_Key := Local_Name = "Key";
   end Start_Element;

   overriding procedure Text (Item : in out Key_Collector; Value : String) is
   begin
      if Item.In_Key then
         Item.Count := Item.Count + 1;
         US.Append (Item.Keys, Value);
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Key_Collector; Local_Name : String) is
      pragma Unreferenced (Local_Name);
   begin
      Item.In_Key := False;
   end End_Element;

   function Parsed_Keys (Document : String) return String is
      Receiver : aliased Key_Collector;
   begin
      XML.Parse (Document, Receiver);
      return US.To_String (Receiver.Keys);
   exception
      when XML.XML_Error =>
         return "<XML_Error>";
   end Parsed_Keys;

begin
   Note ("CreateBucket " & Image (Status_Code
     (Run (Signed_Request ("PUT", "/" & Bucket)))));

   declare
      R : constant String := Run (Signed_Wire
        ("PUT", "/" & Bucket & "/" & Key_Wire,
         "/" & Bucket & "/" & Key_Decoded, "x"));
   begin
      Note ("PutObject /" & Bucket & "/" & Key_Wire & " -> " &
            Image (Status_Code (R)));
      Check (Status_Code (R) = 200,
             "PutObject of a %0D key is accepted (precondition)");
   end;
   declare
      R : constant String := Run (Signed_Wire
        ("GET", "/" & Bucket & "/" & Key_Wire,
         "/" & Bucket & "/" & Key_Decoded));
   begin
      Check (Status_Code (R) = 200 and then Body_Of (R) = "x",
             "CONTROL: GetObject of the %0D key returns its body");
   end;

   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket));
      Wire_Keys : constant String := Parsed_Keys (Body_Of (R));
   begin
      Note ("ListObjects (no encoding-type) -> " & Image (Status_Code (R)));
      Note ("  wire bytes of the page: " & Escape (Body_Of (R)));
      Note ("  stored key:            [" & Escape (Key_Decoded) & "]");
      Note ("  key read back by S3.XML.Parse: [" & Escape (Wire_Keys) & "]");
      Check (Status_Code (R) = 200, "the listing answers 200");
      Check (Wire_Keys = Key_Decoded,
             "the key a conforming XML parser reads back is the stored key");
   end;

   --  CONTROL: with encoding-type=url the key survives.
   declare
      R : constant String := Run (Signed_Request
        ("GET", "/" & Bucket,
         Query => [SigV4.Pair ("encoding-type", "url")]));
      Wire_Keys : constant String := Parsed_Keys (Body_Of (R));
   begin
      Note ("CONTROL encoding-type=url -> " & Image (Status_Code (R)) &
            "  key read back [" & Escape (Wire_Keys) & "]");
      Check (Wire_Keys = Key_Wire,
             "CONTROL: encoding-type=url reports the key percent-encoded");
   end;

   declare
      R : constant String := Run (Signed_Wire
        ("DELETE", "/" & Bucket & "/" & Key_Wire,
         "/" & Bucket & "/" & Key_Decoded));
   begin
      Note ("DeleteObject of the %0D key -> " & Image (Status_Code (R)));
   end;

   Finish;
end Repro_Wire_4;
