--  WIRE-1: an object key containing a C0 control byte is accepted by the
--  storage boundary (Valid_Object_Key rejects only NUL) but the XML text
--  escaper refuses the same byte, so every listing that does not carry
--  encoding-type=url fails with 500 InternalError instead of returning the
--  page.  The program asserts the CORRECT behavior: a listing of a bucket
--  holding such a key answers 200 with a well-formed page.
--
--  Repro_S3_Server.Signed_Request signs the path it is given, and SigV4
--  canonicalization URI-encodes it, so a wire path carrying a percent escape
--  has to be signed from its decoded form.  Signed_Wire below does that: it
--  signs the decoded path and puts the encoded path on the wire.
with Ada.Streams;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with GNAT.MD5;
with Flyology.Object_Storage;
with Flyology.Object_Storage.S3.XML;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Wire_1 is

   package US renames Ada.Strings.Unbounded;
   package OS renames Flyology.Object_Storage;
   package XML renames Flyology.Object_Storage.S3.XML;

   Bucket : constant String := "wire-one-bucket";

   SOH : constant Character := Character'Val (1);
   --  U+0001, the key byte a client percent-encodes as %01.

   Control_Key_Decoded : constant String := "a" & SOH & "b";
   Control_Key_Wire    : constant String := "a%01b";

   High_Key_Decoded : constant String := "h" & Character'Val (16#FF#);
   High_Key_Wire    : constant String := "h%FF";

   ------------------------------------------------------------------
   --  Sign a request whose wire path differs from its decoded form.
   ------------------------------------------------------------------

   function Signed_Wire
     (Method       : String;
      Wire_Path    : String;
      Decoded_Path : String;
      Query        : SigV4.Name_Value_Array := No_Query;
      Payload      : String := "") return String
   is
      Stamp        : constant String := Timestamp;
      Payload_Hash : constant String := SigV4.SHA256_Hex (Payload);
      Headers      : constant SigV4.Name_Value_Array (1 .. 3) :=
        [SigV4.Pair ("host", Host),
         SigV4.Pair ("x-amz-content-sha256", Payload_Hash),
         SigV4.Pair ("x-amz-date", Stamp)];
      Query_Text   : US.Unbounded_String;
   begin
      for Index in Query'Range loop
         US.Append (Query_Text, (if Index = Query'First then "?" else "&"));
         US.Append (Query_Text, US.To_String (Query (Index).Name));
         if US.Length (Query (Index).Value) > 0 then
            US.Append (Query_Text, "=");
            US.Append (Query_Text, US.To_String (Query (Index).Value));
         end if;
      end loop;
      declare
         Signing : constant SigV4.Signing_Result := SigV4.Sign
           (Method, Decoded_Path, Query, Headers, Payload_Hash, Access_Key,
            Secret_Key, Region, Stamp);
      begin
         return Method & " " & Wire_Path & US.To_String (Query_Text) &
           " HTTP/1.1" & CRLF &
           "Host: " & Host & CRLF &
           "x-amz-date: " & Stamp & CRLF &
           "x-amz-content-sha256: " & Payload_Hash & CRLF &
           "Authorization: " & US.To_String (Signing.Authorization) & CRLF &
           "Content-Length: " & Image (Payload'Length) & CRLF &
           "Connection: close" & CRLF & CRLF & Payload;
      end;
   end Signed_Wire;

   function Content_MD5 (Value : String) return String is
      Alphabet : constant String :=
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
      Digest : constant GNAT.MD5.Binary_Message_Digest :=
        GNAT.MD5.Digest (Value);
      Result : String (1 .. 24);
      Output : Positive := 1;

      function Byte (Index : Ada.Streams.Stream_Element_Offset)
        return Natural is (Natural (Digest (Index)));
   begin
      for Group in 0 .. 4 loop
         declare
            First : constant Ada.Streams.Stream_Element_Offset :=
              Ada.Streams.Stream_Element_Offset (1 + 3 * Group);
            A : constant Natural := Byte (First);
            B : constant Natural :=
              Byte (Ada.Streams.Stream_Element_Offset'Succ (First));
            C : constant Natural := Byte
              (Ada.Streams.Stream_Element_Offset'Succ
                 (Ada.Streams.Stream_Element_Offset'Succ (First)));
         begin
            Result (Output) := Alphabet (A / 4 + 1);
            Result (Output + 1) := Alphabet ((A mod 4) * 16 + B / 16 + 1);
            Result (Output + 2) := Alphabet ((B mod 16) * 4 + C / 64 + 1);
            Result (Output + 3) := Alphabet (C mod 64 + 1);
            Output := Output + 4;
         end;
      end loop;
      declare
         A : constant Natural := Byte (16);
      begin
         Result (21) := Alphabet (A / 4 + 1);
         Result (22) := Alphabet ((A mod 4) * 16 + 1);
         Result (23 .. 24) := "==";
      end;
      return Result;
   end Content_MD5;

   function Q1 (Name : String; Value : String := "")
     return SigV4.Name_Value_Array is ([SigV4.Pair (Name, Value)]);

   function Q2 (Name_1, Value_1, Name_2, Value_2 : String)
     return SigV4.Name_Value_Array is
     ([SigV4.Pair (Name_1, Value_1), SigV4.Pair (Name_2, Value_2)]);

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

   procedure Report (Label : String; Response : String) is
   begin
      Note (Label & " -> status " & Image (Status_Code (Response)) &
            (if Contains (Body_Of (Response), "<Code>")
             then "  " &
               Body_Of (Response)
                 (Ada.Strings.Fixed.Index (Body_Of (Response), "<Code>") ..
                  Ada.Strings.Fixed.Index (Body_Of (Response), "</Code>") + 6)
             else ""));
   end Report;

begin
   ------------------------------------------------------------------
   --  Unit level: the domain accepts the key, the XML writer does not.
   ------------------------------------------------------------------
   Note ("Valid_Object_Key (""a"" & SOH & ""b"") = " &
         Boolean'Image (OS.Valid_Object_Key (Control_Key_Decoded)));
   begin
      declare
         Escaped : constant String := XML.Escape_Text (Control_Key_Decoded);
      begin
         Note ("XML.Escape_Text of the same key = " & Escape (Escaped));
      end;
   exception
      when XML.XML_Error =>
         Note ("XML.Escape_Text of the same key raised XML_Error");
   end;

   ------------------------------------------------------------------
   --  Set up: a bucket with one ordinary key (the control).
   ------------------------------------------------------------------
   declare
      R : constant String := Run (Signed_Request ("PUT", "/" & Bucket));
   begin
      Report ("CreateBucket", R);
      Check (Status_Code (R) = 200, "CreateBucket is 200");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("PUT", "/" & Bucket & "/plain.txt", "x"));
   begin
      Report ("PutObject plain.txt", R);
      Check (Status_Code (R) = 200, "PutObject of an ordinary key is 200");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket, Query => Q1 ("list-type",
             "2")));
   begin
      Report ("CONTROL ListObjectsV2 with only ordinary keys", R);
      Check (Status_Code (R) = 200,
             "CONTROL: listing a bucket of ordinary keys is 200");
      Check (Contains (Body_Of (R), "<Key>plain.txt</Key>"),
             "CONTROL: the ordinary key appears in the page");
   end;

   ------------------------------------------------------------------
   --  Store the control-character key.
   ------------------------------------------------------------------
   declare
      R : constant String := Run (Signed_Wire
        ("PUT", "/" & Bucket & "/" & Control_Key_Wire,
         "/" & Bucket & "/" & Control_Key_Decoded, Payload => "x"));
   begin
      Report ("PutObject /" & Bucket & "/" & Control_Key_Wire, R);
      Check (Status_Code (R) = 200,
             "PutObject of a %01 key is accepted (precondition)");
   end;

   --  Controls: the key itself stays addressable.
   declare
      R : constant String := Run (Signed_Wire
        ("GET", "/" & Bucket & "/" & Control_Key_Wire,
         "/" & Bucket & "/" & Control_Key_Decoded));
   begin
      Report ("CONTROL GetObject of the %01 key", R);
      Check (Status_Code (R) = 200 and then Body_Of (R) = "x",
             "CONTROL: GetObject of the %01 key returns its body");
   end;
   declare
      R : constant String := Run (Signed_Wire
        ("HEAD", "/" & Bucket & "/" & Control_Key_Wire,
         "/" & Bucket & "/" & Control_Key_Decoded));
   begin
      Report ("CONTROL HeadObject of the %01 key", R);
      Check (Status_Code (R) = 200,
             "CONTROL: HeadObject of the %01 key is 200");
   end;

   ------------------------------------------------------------------
   --  The finding: listings without encoding-type=url.
   ------------------------------------------------------------------
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket,
             Query => Q1 ("list-type", "2")));
   begin
      Report ("ListObjectsV2 (no encoding-type)", R);
      Note ("  body: " & Escape (Body_Of (R)));
      Check (Status_Code (R) = 200,
             "ListObjectsV2 without encoding-type is 200");
      Check (Contains (Body_Of (R), "<Key>"),
             "ListObjectsV2 without encoding-type returns a listing page");
   end;
   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket));
   begin
      Report ("ListObjects v1 (no encoding-type)", R);
      Check (Status_Code (R) = 200,
             "ListObjects v1 without encoding-type is 200");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket, Query => Q1 ("versions")));
   begin
      Report ("ListObjectVersions (no encoding-type)", R);
      Check (Status_Code (R) = 200,
             "ListObjectVersions without encoding-type is 200");
   end;

   --  Does encoding-type=url avoid it?
   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket,
        Query => Q2 ("encoding-type", "url", "list-type", "2")));
   begin
      Report ("ListObjectsV2 with encoding-type=url", R);
      Note ("  body: " & Escape (Body_Of (R)));
   end;

   --  DeleteObjects naming the key in its request XML.
   declare
      Doc : constant String :=
        "<Delete><Object><Key>" & Control_Key_Decoded &
        "</Key></Object></Delete>";
      R : constant String := Run (Signed_Request
        ("POST", "/" & Bucket, Doc, Query => Q1 ("delete"),
         Extra_Headers => "Content-MD5: " & Content_MD5 (Doc) & CRLF));
   begin
      Report ("DeleteObjects with a raw U+0001 in the request XML", R);
      Note ("  body: " & Escape (Body_Of (R)));
   end;
   declare
      Doc : constant String :=
        "<Delete><Object><Key>a&#1;b</Key></Object></Delete>";
      R : constant String := Run (Signed_Request
        ("POST", "/" & Bucket, Doc, Query => Q1 ("delete"),
         Extra_Headers => "Content-MD5: " & Content_MD5 (Doc) & CRLF));
   begin
      Report ("DeleteObjects with &#1; in the request XML", R);
      Note ("  body: " & Escape (Body_Of (R)));
   end;

   ------------------------------------------------------------------
   --  Diagnostic only: a key with a raw non-UTF-8 byte.
   ------------------------------------------------------------------
   declare
      R : constant String := Run (Signed_Wire
        ("PUT", "/" & Bucket & "/" & High_Key_Wire,
         "/" & Bucket & "/" & High_Key_Decoded, Payload => "y"));
   begin
      Report ("PutObject /" & Bucket & "/" & High_Key_Wire, R);
   end;
   declare
      R : constant String := Run (Signed_Request ("GET", "/" & Bucket,
        Query => Q2 ("encoding-type", "url", "list-type", "2")));
   begin
      Report ("ListObjectsV2 encoding-type=url with the %FF key too", R);
      Note ("  body valid UTF-8: " &
            Boolean'Image (Valid_UTF8 (Body_Of (R))));
      Note ("  body: " & Escape (Body_Of (R)));
   end;

   ------------------------------------------------------------------
   --  Deleting the key restores the listing.
   ------------------------------------------------------------------
   declare
      R : constant String := Run (Signed_Wire
        ("DELETE", "/" & Bucket & "/" & Control_Key_Wire,
         "/" & Bucket & "/" & Control_Key_Decoded));
   begin
      Report ("CONTROL DeleteObject of the %01 key", R);
      Check (Status_Code (R) in 200 | 204,
             "CONTROL: DELETE of the %01 key succeeds");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket,
             Query => Q1 ("list-type", "2")));
   begin
      Report ("ListObjectsV2 (no encoding-type) with only the %FF key", R);
      Note ("  body valid UTF-8: " &
            Boolean'Image (Valid_UTF8 (Body_Of (R))));
      Note ("  body: " & Escape (Body_Of (R)));
   end;
   declare
      R : constant String := Run (Signed_Wire
        ("DELETE", "/" & Bucket & "/" & High_Key_Wire,
         "/" & Bucket & "/" & High_Key_Decoded));
   begin
      Report ("DeleteObject of the %FF key", R);
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket,
             Query => Q1 ("list-type", "2")));
   begin
      Report ("CONTROL ListObjectsV2 after the keys are removed", R);
      Check (Status_Code (R) = 200,
             "CONTROL: the listing works again once the keys are gone");
   end;

   Finish;
end Repro_Wire_1;
