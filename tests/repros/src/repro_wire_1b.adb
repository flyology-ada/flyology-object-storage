--  WIRE-1b (sibling of WIRE-1): Valid_Object_Key accepts arbitrary non-NUL
--  bytes, so a key holding a byte that is not valid UTF-8 is stored, and a
--  listing without encoding-type=url copies that byte into the response.
--  The response announces encoding="UTF-8" but is not UTF-8, so a conforming
--  XML parser -- including the crate's own S3.XML.Parse -- rejects the whole
--  page.  This program asserts the CORRECT behavior: the listing body is
--  valid UTF-8 and parses.
with Ada.Strings.Unbounded;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Wire_1b is

   package US renames Ada.Strings.Unbounded;
   package XML renames Flyology.Object_Storage.S3.XML;

   Bucket : constant String := "wire-one-b-bucket";

   High_Key_Decoded : constant String := "h" & Character'Val (16#FF#);
   High_Key_Wire    : constant String := "h%FF";

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

   function Valid_UTF8 (Value : String) return Boolean is
      Index : Natural := Value'First;
      Extra : Natural;
      Byte  : Natural;
   begin
      while Index <= Value'Last loop
         Byte := Character'Pos (Value (Index));
         if Byte < 16#80# then
            Extra := 0;
         elsif Byte in 16#C2# .. 16#DF# then
            Extra := 1;
         elsif Byte in 16#E0# .. 16#EF# then
            Extra := 2;
         elsif Byte in 16#F0# .. 16#F4# then
            Extra := 3;
         else
            return False;
         end if;
         if Index + Extra > Value'Last then
            return False;
         end if;
         for Offset in 1 .. Extra loop
            if Character'Pos (Value (Index + Offset)) not in
              16#80# .. 16#BF#
            then
               return False;
            end if;
         end loop;
         Index := Index + Extra + 1;
      end loop;
      return True;
   end Valid_UTF8;

   --  A receiver that records the keys the crate's own parser can read.
   type Key_Collector is limited new XML.Event_Handler with record
      In_Key : Boolean := False;
      Keys   : US.Unbounded_String;
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
         US.Append (Item.Keys, "[" & Escape (Value) & "]");
      end if;
   end Text;

   overriding procedure End_Element
     (Item : in out Key_Collector; Local_Name : String) is
      pragma Unreferenced (Local_Name);
   begin
      Item.In_Key := False;
   end End_Element;

   procedure Try_Parse (Label, Document : String; Parsed : out Boolean) is
      Receiver : aliased Key_Collector;
   begin
      Parsed := True;
      XML.Parse (Document, Receiver);
      Note (Label & ": parsed, keys " & US.To_String (Receiver.Keys));
   exception
      when XML.XML_Error =>
         Parsed := False;
         Note (Label & ": S3.XML.Parse raised XML_Error");
   end Try_Parse;

begin
   declare
      R : constant String := Run (Signed_Request ("PUT", "/" & Bucket));
   begin
      Note ("CreateBucket status " & Image (Status_Code (R)));
      Check (Status_Code (R) = 200, "CreateBucket is 200");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("PUT", "/" & Bucket & "/plain.txt", "x"));
   begin
      Check (Status_Code (R) = 200, "PutObject of an ordinary key is 200");
   end;

   --  CONTROL: an all-ASCII listing is UTF-8 and the crate parses it back.
   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket));
      Parsed : Boolean;
   begin
      Note ("CONTROL ListObjects status " & Image (Status_Code (R)));
      Check (Valid_UTF8 (Body_Of (R)),
             "CONTROL: an ordinary listing body is valid UTF-8");
      Try_Parse ("CONTROL listing", Body_Of (R), Parsed);
      Check (Parsed, "CONTROL: the crate parses its own ordinary listing");
   end;

   --  Store a key whose bytes are not valid UTF-8.
   declare
      R : constant String := Run (Signed_Wire
        ("PUT", "/" & Bucket & "/" & High_Key_Wire,
         "/" & Bucket & "/" & High_Key_Decoded, "y"));
   begin
      Note ("PutObject /" & Bucket & "/" & High_Key_Wire & " status " &
            Image (Status_Code (R)));
      Check (Status_Code (R) = 200,
             "PutObject of a %FF key is accepted (precondition)");
   end;

   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket));
      Parsed : Boolean;
   begin
      Note ("ListObjects (no encoding-type) status " &
            Image (Status_Code (R)));
      Note ("  body: " & Escape (Body_Of (R)));
      Check (Status_Code (R) = 200, "the listing answers 200");
      Check (Valid_UTF8 (Body_Of (R)),
             "the listing body is valid UTF-8 as its declaration claims");
      Try_Parse ("listing with the %FF key", Body_Of (R), Parsed);
      Check (Parsed,
             "the crate's own S3 XML parser accepts the listing it emitted");
   end;

   --  Clean up so a rerun starts from the same state.
   declare
      R : constant String := Run (Signed_Wire
        ("DELETE", "/" & Bucket & "/" & High_Key_Wire,
         "/" & Bucket & "/" & High_Key_Decoded));
   begin
      Note ("DeleteObject of the %FF key status " & Image (Status_Code (R)));
   end;

   Finish;
end Repro_Wire_1b;
