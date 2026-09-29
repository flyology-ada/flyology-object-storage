--  Harness smoke test: the in-process S3 application and the loopback
--  listener both serve a signed CreateBucket / PutObject / GetObject round
--  trip.  This program must PASS on current sources.
with Repro_Support; use Repro_Support;
with Repro_S3_Server; use Repro_S3_Server;

procedure Repro_Smoke is
   Port : Natural;
begin
   declare
      Created : constant String :=
        Run (Signed_Request ("PUT", "/smoke-bucket"));
   begin
      Note ("in-process CreateBucket status " & Image (Status_Code (Created)));
      Check (Status_Code (Created) = 200, "in-process CreateBucket is 200");
   end;
   declare
      Put : constant String :=
        Run (Signed_Request ("PUT", "/smoke-bucket/hello.txt", "hello"));
   begin
      Check (Status_Code (Put) = 200, "in-process PutObject is 200");
      Check (Header_Value (Put, "ETag") /= "", "PutObject returns an ETag");
   end;
   declare
      Got : constant String :=
        Run (Signed_Request ("GET", "/smoke-bucket/hello.txt"));
   begin
      Check (Status_Code (Got) = 200, "in-process GetObject is 200");
      Check (Body_Of (Got) = "hello", "GetObject body round-trips");
   end;
   Start_Loopback (Port);
   Note ("loopback listener on port " & Image (Port));
   declare
      Got : constant String := Exchange_Over_Socket
        (Port, Signed_Request ("GET", "/smoke-bucket/hello.txt"));
   begin
      Check (Status_Code (Got) = 200, "loopback GetObject is 200");
      Check (Body_Of (Got) = "hello", "loopback GetObject body round-trips");
   end;
   declare
      Missing : constant String := Exchange_Over_Socket
        (Port, Signed_Request ("GET", "/smoke-bucket/absent"));
   begin
      Check (Status_Code (Missing) = 404, "loopback missing key is 404");
      Check (Contains (Body_Of (Missing), "<Code>NoSuchKey</Code>"),
             "missing key error XML carries NoSuchKey");
   end;
   Stop_Loopback;
   Finish;
end Repro_Smoke;
