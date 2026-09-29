--  SIGV4 verification probe: the observations the discovery report listed
--  but did not count, re-derived against the running server.  This program
--  asserts what the maintained sources and documents say the behaviour
--  should be, so it PASSES (exit 0) when none of them is a defect.  Every
--  outcome is printed so the output alone is the evidence.
--
--  Probes:
--    (a) UNSIGNED-PAYLOAD over plain HTTP with a body nothing signed
--    (b) two Authorization fields; Authorization plus presigned query
--    (c) padded/mixed-case signed header values; declared-but-absent signed
--        header; unsigned physical x-amz-* header
--    (d) credential scope date different from the x-amz-date day
--    (e) uppercase hex x-amz-content-sha256 with a matching body
--    (f) presigned-style query authentication with no Authorization field
--    (g) control: signed payload-hash mismatch is caught and rolled back
with Ada.Strings.Fixed;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_SigV4_Probe is

   Bucket : constant String := "/probe-bucket";

   Stamp : constant String := Timestamp;
   Scope_Date : constant String := Stamp (Stamp'First .. Stamp'First + 7);

   Empty_Hash : constant String := SigV4.SHA256_Hex ("");

   procedure Report (Label, Response : String) is
   begin
      Note (Label & ": status " & Image (Status_Code (Response)));
      Note (Label & ": body " & Escape (Body_Of (Response)));
   end Report;

   function Uppercase (Value : String) return String is
      Result : String (Value'Range);
   begin
      for Index in Value'Range loop
         Result (Index) :=
           (if Value (Index) in 'a' .. 'z'
            then Character'Val (Character'Pos (Value (Index)) - 32)
            else Value (Index));
      end loop;
      return Result;
   end Uppercase;

   function Replace_First (Text, From, To : String) return String is
      At_Index : constant Natural := Ada.Strings.Fixed.Index (Text, From);
   begin
      if At_Index = 0 then
         raise Program_Error with "probe: pattern not found: " & From;
      end if;
      return Text (Text'First .. At_Index - 1) & To &
        Text (At_Index + From'Length .. Text'Last);
   end Replace_First;

   function Delete_Field (Text, Field_Line : String) return String is
     (Replace_First (Text, Field_Line & CRLF, ""));

   function Insert_Field (Text, Field_Line : String) return String is
     (Replace_First (Text, "Host: ", Field_Line & CRLF & "Host: "));

begin
   ------------------------------------------------------------------
   --  Fixtures
   ------------------------------------------------------------------
   declare
      Created : constant String := Run (Signed_Request ("PUT", Bucket));
   begin
      Report ("fixture CreateBucket", Created);
      Check (Status_Code (Created) = 200, "fixture: CreateBucket is 200");
   end;

   ------------------------------------------------------------------
   --  (a) UNSIGNED-PAYLOAD over plain HTTP
   ------------------------------------------------------------------
   declare
      Response : constant String := Run
        (Signed_Request ("PUT", Bucket & "/unsigned",
                         Payload       => "a body that nothing signed",
                         Hash_Override => "UNSIGNED-PAYLOAD"));
   begin
      Report ("(a) UNSIGNED-PAYLOAD on plain HTTP", Response);
      Check (Status_Code (Response) = 400,
             "(a) UNSIGNED-PAYLOAD over plain HTTP is refused with 400");
      Check (Contains (Body_Of (Response), "<Code>InvalidRequest</Code>"),
             "(a) UNSIGNED-PAYLOAD over plain HTTP reports InvalidRequest");
   end;
   declare
      Fetched : constant String :=
        Run (Signed_Request ("GET", Bucket & "/unsigned"));
   begin
      Report ("(a) GET after refused UNSIGNED-PAYLOAD", Fetched);
      Check (Status_Code (Fetched) = 404,
             "(a) the refused UNSIGNED-PAYLOAD body was not stored");
   end;

   ------------------------------------------------------------------
   --  (b) two Authorization fields
   ------------------------------------------------------------------
   declare
      Signed : constant String := Signed_Request ("GET", Bucket);
      At_Auth : constant Natural :=
        Ada.Strings.Fixed.Index (Signed, "Authorization: ");
      Line_End : constant Natural :=
        Ada.Strings.Fixed.Index (Signed, CRLF, From => At_Auth);
      Doubled : constant String :=
        Signed (Signed'First .. Line_End + CRLF'Length - 1) &
        Signed (At_Auth .. Line_End + CRLF'Length - 1) &
        Signed (Line_End + CRLF'Length .. Signed'Last);
      Response : constant String := Run (Doubled);
   begin
      Report ("(b) two Authorization fields", Response);
      Check (Status_Code (Response) /= 200,
             "(b) two Authorization fields are not accepted");
      Check (Status_Code (Response) /= 500,
             "(b) two Authorization fields do not raise an internal error");
   end;

   ------------------------------------------------------------------
   --  (b) Authorization plus presigned query parameters
   ------------------------------------------------------------------
   declare
      Both : constant SigV4.Name_Value_Array (1 .. 5) :=
        [SigV4.Pair ("X-Amz-Algorithm", "AWS4-HMAC-SHA256"),
         SigV4.Pair ("X-Amz-Credential",
                     Access_Key & "/" & Scope_Date & "/" & Region &
                     "/s3/aws4_request"),
         SigV4.Pair ("X-Amz-Date", Stamp),
         SigV4.Pair ("X-Amz-Expires", "900"),
         SigV4.Pair ("X-Amz-Signature", Repeat ('0', 64))];
      Response : constant String := Run
        (Signed_Request ("GET", Bucket, Query => Both,
                         Timestamp_Value => Stamp));
   begin
      Report ("(b) Authorization plus X-Amz-Signature query", Response);
      Check (Status_Code (Response) /= 500,
             "(b) header auth plus presigned query is not an internal error");
   end;

   ------------------------------------------------------------------
   --  (c) padded value and mixed-case name on a signed header
   ------------------------------------------------------------------
   declare
      Response : constant String := Run
        (Signed_Request
           ("PUT", Bucket & "/padded", Payload => "x",
            Extra_Headers =>
              "X-Amz-Meta-Note:   spaced   out   " & CRLF));
   begin
      Report ("(c) padded mixed-case signed header", Response);
      Check (Status_Code (Response) = 200,
             "(c) a padded, mixed-case signed x-amz-* header verifies");
   end;

   ------------------------------------------------------------------
   --  (c) header declared in SignedHeaders but absent from the request
   ------------------------------------------------------------------
   declare
      Signed : constant String := Signed_Request
        ("GET", Bucket, Extra_Headers => "x-amz-meta-note: v" & CRLF);
      Stripped : constant String :=
        Delete_Field (Signed, "x-amz-meta-note: v");
      Response : constant String := Run (Stripped);
   begin
      Report ("(c) declared-but-absent signed header", Response);
      Check (Status_Code (Response) /= 200,
             "(c) a declared but absent signed header is not accepted");
      Check (Status_Code (Response) /= 500,
             "(c) a declared but absent signed header is not a 500");
   end;

   ------------------------------------------------------------------
   --  (c) physical x-amz-* header that SignedHeaders does not name
   ------------------------------------------------------------------
   declare
      Signed : constant String := Signed_Request ("GET", Bucket);
      Injected : constant String :=
        Insert_Field (Signed, "x-amz-meta-extra: injected");
      Response : constant String := Run (Injected);
   begin
      Report ("(c) unsigned physical x-amz-* header", Response);
      Check (Status_Code (Response) /= 200,
             "(c) an unsigned physical x-amz-* header is not accepted");
      Check (Status_Code (Response) /= 500,
             "(c) an unsigned physical x-amz-* header is not a 500");
   end;

   ------------------------------------------------------------------
   --  (d) credential scope date different from the x-amz-date day
   ------------------------------------------------------------------
   declare
      Signed : constant String :=
        Signed_Request ("GET", Bucket, Timestamp_Value => Stamp);
      Other_Date : constant String :=
        (if Scope_Date (Scope_Date'Last) = '1'
         then Scope_Date (Scope_Date'First .. Scope_Date'Last - 1) & "2"
         else Scope_Date (Scope_Date'First .. Scope_Date'Last - 1) & "1");
      Shifted : constant String := Replace_First
        (Signed,
         "Credential=" & Access_Key & "/" & Scope_Date,
         "Credential=" & Access_Key & "/" & Other_Date);
      Response : constant String := Run (Shifted);
   begin
      Note ("(d) x-amz-date day " & Scope_Date &
            ", credential scope day " & Other_Date);
      Report ("(d) scope date mismatch", Response);
      Check (Status_Code (Response) /= 200,
             "(d) a scope date that differs from x-amz-date is refused");
      Check (Status_Code (Response) /= 500,
             "(d) a scope date mismatch is not a 500");
   end;

   ------------------------------------------------------------------
   --  (e) uppercase hex x-amz-content-sha256 with a matching body
   ------------------------------------------------------------------
   declare
      Signed : constant String := Signed_Request ("GET", Bucket);
      Upper : constant String := Replace_First
        (Signed,
         "x-amz-content-sha256: " & Empty_Hash,
         "x-amz-content-sha256: " & Uppercase (Empty_Hash));
      Response : constant String := Run (Upper);
   begin
      Note ("(e) sent x-amz-content-sha256: " & Uppercase (Empty_Hash));
      Report ("(e) uppercase content digest", Response);
      Check (Status_Code (Response) /= 200,
             "(e) an uppercase x-amz-content-sha256 is not accepted");
      Check (Status_Code (Response) /= 500,
             "(e) an uppercase x-amz-content-sha256 is not a 500");
   end;

   ------------------------------------------------------------------
   --  (f) presigned-style query authentication, no Authorization field
   ------------------------------------------------------------------
   declare
      Presigned : constant String :=
        "GET " & Bucket & "?X-Amz-Algorithm=AWS4-HMAC-SHA256" &
        "&X-Amz-Credential=" & Access_Key & "%2F" & Scope_Date & "%2F" &
        Region & "%2Fs3%2Faws4_request" &
        "&X-Amz-Date=" & Stamp &
        "&X-Amz-Expires=900" &
        "&X-Amz-SignedHeaders=host" &
        "&X-Amz-Signature=" & Repeat ('0', 64) & " HTTP/1.1" & CRLF &
        "Host: " & Host & CRLF &
        "Content-Length: 0" & CRLF &
        "Connection: close" & CRLF & CRLF;
      Response : constant String := Run (Presigned);
   begin
      Report ("(f) presigned-style query request", Response);
      Check (Status_Code (Response) /= 200,
             "(f) a presigned-style request is not accepted");
      Check (Status_Code (Response) /= 500,
             "(f) a presigned-style request is a clean refusal, not a 500");
   end;

   ------------------------------------------------------------------
   --  (g) control: a signed payload hash that the body does not match
   ------------------------------------------------------------------
   declare
      Response : constant String := Run
        (Signed_Request ("PUT", Bucket & "/mismatch", Payload => "BBBB",
                         Hash_Override => SigV4.SHA256_Hex ("AAAA")));
   begin
      Report ("(g) signed hash of AAAA with body BBBB", Response);
      Check (Status_Code (Response) = 400,
             "(g) a body that does not match the signed hash is 400");
      Check (Contains (Body_Of (Response),
                       "<Code>XAmzContentSHA256Mismatch</Code>"),
             "(g) the mismatch reports XAmzContentSHA256Mismatch");
   end;
   declare
      Fetched : constant String :=
        Run (Signed_Request ("GET", Bucket & "/mismatch"));
   begin
      Report ("(g) GET after payload-hash mismatch", Fetched);
      Check (Status_Code (Fetched) = 404,
             "(g) the mismatched body was not published");
   end;

   Finish;
end Repro_SigV4_Probe;
