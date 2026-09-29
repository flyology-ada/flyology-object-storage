--  WIRE-3: the server answers 400 InvalidRequest for every Range field that
--  S3.Core.Parse_Range_Header classifies Malformed_Range, including a field
--  whose range unit is not "bytes".  RFC 9110 section 14.2 states that an
--  origin server MUST ignore a Range header field that contains a range unit
--  it does not understand (from memory, unverified), and AWS S3 is believed
--  to return the whole object with 200 for Range fields it cannot use (from
--  memory, unverified; not checked against a live server).  This program
--  asserts the CORRECT behavior for the unrecognized-unit case: the field is
--  ignored and the whole object is returned with 200.  The other malformed
--  shapes are printed as notes only.
with Flyology.Object_Storage.S3.Core;
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Wire_3 is

   package Core renames Flyology.Object_Storage.S3.Core;
   use type Core.Range_Parse_Status;

   Bucket    : constant String := "wire-three-bucket";
   Key       : constant String := "obj";
   Body_Text : constant String := "0123456789";

   function Fetch (Method, Field : String) return String is
     (Run (Signed_Request
       (Method, "/" & Bucket & "/" & Key,
        Extra_Headers => "Range: " & Field & CRLF)));

   procedure Show (Method, Field : String) is
      R : constant String := Fetch (Method, Field);
   begin
      Note (Method & " Range: [" & Field & "]  parser=" &
            Core.Range_Parse_Status'Image
              (Core.Parse_Range_Header (Field).Status) &
            "  status=" & Image (Status_Code (R)) &
            "  Content-Range=[" & Header_Value (R, "Content-Range") &
            "]  Content-Length=[" & Header_Value (R, "Content-Length") &
            "]  body=" & Image (Body_Of (R)'Length) & " bytes");
   end Show;

begin
   Note ("CreateBucket " & Image (Status_Code
     (Run (Signed_Request ("PUT", "/" & Bucket)))));
   Note ("PutObject " & Image (Status_Code
     (Run (Signed_Request ("PUT", "/" & Bucket & "/" & Key, Body_Text)))));

   ------------------------------------------------------------------
   --  Controls: the range machinery works for the shapes it supports.
   ------------------------------------------------------------------
   Show ("GET", "bytes=0-1");
   declare
      R : constant String := Fetch ("GET", "bytes=0-1");
   begin
      Check (Status_Code (R) = 206 and then Body_Of (R) = "01",
             "CONTROL: a supported byte range is 206 with the two bytes");
   end;
   Show ("GET", "bytes=100-200");
   declare
      R : constant String := Fetch ("GET", "bytes=100-200");
   begin
      Check (Status_Code (R) = 416,
             "CONTROL: a valid but unsatisfiable byte range is 416");
   end;
   declare
      R : constant String :=
        Run (Signed_Request ("GET", "/" & Bucket & "/" & Key));
   begin
      Check (Status_Code (R) = 200 and then Body_Of (R) = Body_Text,
             "CONTROL: a request without Range returns the whole object");
   end;

   ------------------------------------------------------------------
   --  The finding: an unrecognized range unit must be ignored.
   ------------------------------------------------------------------
   Show ("GET", "items=0-1");
   declare
      R : constant String := Fetch ("GET", "items=0-1");
   begin
      Check (Status_Code (R) = 200,
             "GET with an unrecognized range unit is 200");
      Check (Body_Of (R) = Body_Text,
             "GET with an unrecognized range unit returns the whole object");
   end;
   Show ("HEAD", "items=0-1");
   declare
      R : constant String := Fetch ("HEAD", "items=0-1");
   begin
      Check (Status_Code (R) = 200,
             "HEAD with an unrecognized range unit is 200");
   end;

   ------------------------------------------------------------------
   --  Notes only: the other shapes Parse_Range_Header rejects.  AWS
   --  behaviour for these was not verified against a live server.
   ------------------------------------------------------------------
   Show ("GET", "bytes=0-1, 4-5");
   Show ("GET", "bytes=0-1,4-5");
   Show ("GET", "bytes=abc");
   Show ("GET", "bytes 0-1");
   Show ("GET", "bytes=");
   Show ("GET", "bytes=0-1;q=1");
   Show ("GET", "bytes=5-1");

   Finish;
end Repro_Wire_3;
