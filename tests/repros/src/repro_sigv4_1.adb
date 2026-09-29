--  SIGV4-1: a far-future x-amz-date escapes Verify_Request as
--  Ada.Calendar.Time_Error instead of returning Request_Time_Too_Skewed, so
--  the application's catch-all answers 500 InternalError rather than
--  403 RequestTimeTooSkewed.
--
--  Mechanism: Flyology.Object_Storage.S3.SigV4_Encoding.Valid_Timestamp
--  accepts any year > 0; Authentication.Timestamp_Time converts it through
--  Ada.Calendar.Year_Number (GNAT: 1901 .. 2399) and only guards the
--  conversion; the clock-skew subtraction at authentication.adb:157-165 is
--  outside that guard, and GNAT's "-" (Time, Time) raises Time_Error (not
--  Constraint_Error) when the difference leaves Duration'Range
--  (Duration_32_Bits = False => about 292.3 years).  Verify_Request's own
--  handler catches only Constraint_Error.
--
--  Correct behaviour asserted here: any accepted x-amz-date that is further
--  from the trusted clock than Maximum_Clock_Skew answers
--  403 RequestTimeTooSkewed, exactly as a moderately skewed date does.
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_SigV4_1 is

   --  Well inside Ada.Calendar.Year_Number (<= 2399) and well beyond
   --  Now + Duration'Last (about 2318 for a 2026 clock), so the result does
   --  not depend on the exact day the program runs.
   Far_Future : constant String := "23900101T000000Z";

   --  Moderately skewed: same code path, no Duration overflow.
   Past       : constant String := "20200101T000000Z";

   procedure Report (Label, Response : String) is
   begin
      Note (Label & ": status " & Image (Status_Code (Response)));
      Note (Label & ": body " & Escape (Body_Of (Response)));
   end Report;

begin
   --  Control 1: an ordinary signed request still succeeds, so the harness,
   --  the credential provider and the signature path all work.
   declare
      Created : constant String :=
        Run (Signed_Request ("PUT", "/skew-bucket"));
   begin
      Report ("control CreateBucket", Created);
      Check (Status_Code (Created) = 200,
             "control: a correctly signed CreateBucket is 200");
   end;

   --  Control 2: a moderately skewed date is diagnosed correctly.
   declare
      Skewed : constant String :=
        Run (Signed_Request ("GET", "/skew-bucket",
                             Timestamp_Value => Past));
   begin
      Report ("x-amz-date " & Past, Skewed);
      Check (Status_Code (Skewed) = 403,
             "control: x-amz-date " & Past & " is 403");
      Check (Contains (Body_Of (Skewed),
                       "<Code>RequestTimeTooSkewed</Code>"),
             "control: x-amz-date " & Past & " is RequestTimeTooSkewed");
   end;

   --  The finding: the same policy decision, a far-future date.
   declare
      Future : constant String :=
        Run (Signed_Request ("GET", "/skew-bucket",
                             Timestamp_Value => Far_Future));
   begin
      Report ("x-amz-date " & Far_Future, Future);
      Check (Status_Code (Future) /= 500,
             "x-amz-date " & Far_Future & " is not answered with 500");
      Check (Status_Code (Future) = 403,
             "x-amz-date " & Far_Future & " is 403");
      Check (Contains (Body_Of (Future),
                       "<Code>RequestTimeTooSkewed</Code>"),
             "x-amz-date " & Far_Future & " is RequestTimeTooSkewed");
   end;

   Finish;
end Repro_SigV4_1;
