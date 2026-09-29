package Repro_Support is
   --  Shared helpers for bug reproduction programs.  Convention: a program
   --  asserts the CORRECT behavior.  On current sources it prints
   --  "BUG REPRODUCED" and exits with status 1; after a fix it prints "PASS"
   --  and exits 0.

   procedure Check (Condition : Boolean; Description : String);
   --  Record a failed expectation when Condition is False.

   procedure Note (Text : String);
   --  Print an informational line.

   procedure Finish;
   --  Print the verdict and set the process exit status.

   function Failures return Natural;

   CRLF : constant String := ASCII.CR & ASCII.LF;

   --  Raw HTTP/1.1 response helpers (the response text as one String).
   function Status_Code (Response : String) return Natural;
   --  The three-digit status, or 0 when the status line is malformed.

   function Header_Value (Response : String; Name : String) return String;
   --  First header with that name (case-insensitive), trimmed; "" if absent.

   function Header_Count (Response : String; Name : String) return Natural;

   function Body_Of (Response : String) return String;
   --  The message body; chunked transfer coding is decoded.

   function Contains (Haystack, Needle : String) return Boolean;

   function Trim (Value : String) return String;

   function Image (Value : Integer) return String;
   function Image_64 (Value : Long_Long_Integer) return String;

   function Repeat (Item : Character; Count : Natural) return String;

   function Escape (Value : String) return String;
   --  Make control characters visible for printing.

end Repro_Support;
