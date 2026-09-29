Title: A far-future x-amz-date escapes Verify_Request as Ada.Calendar.Time_Error and is answered 500 InternalError
Labels: bug
Refs: none

## Summary

`SigV4_Encoding.Valid_Timestamp` puts no upper bound on the year of `x-amz-date`, so a timestamp anywhere in GNAT's `Ada.Calendar.Year_Number` survives admission and reaches the clock-skew test in `Authentication.Verify_Request`. That test subtracts two `Ada.Calendar.Time` values outside any handler that covers `Ada.Calendar.Time_Error`, and GNAT's `"-"` raises `Time_Error` once the difference leaves `Duration`'s range, which is 292.277 years. The exception leaves the public `Verify_Request` and reaches the S3 application's catch-all, so the peer is answered 500 InternalError instead of the 403 RequestTimeTooSkewed that the outcome mapping exists to produce. No credentials are needed, because the skew test runs before the credential provider is invoked.

## Problem

Commit `5fe6e3e`.

`Valid_Timestamp` accepts any year above zero and never bounds it from above (`src/flyology-object_storage-s3-sigv4_encoding.adb:190-195`):

```ada
         return Year > 0
           and then Month in 1 .. 12
           and then Day in 1 .. Maximum_Day
           and then Hour <= 23
           and then Minute <= 59
           and then Second <= 59;
```

`Timestamp_Time` converts the accepted stamp to an `Ada.Calendar.Time`, and its handler covers only the conversion inside that function (`src/flyology-object_storage-server-authentication.adb:57-69`):

```ada
      return Ada.Calendar.Formatting.Time_Of
        (Ada.Calendar.Year_Number (Year),
         Ada.Calendar.Month_Number (Month),
         Ada.Calendar.Day_Number (Day),
         Ada.Calendar.Formatting.Hour_Number (Hour),
         Ada.Calendar.Formatting.Minute_Number (Minute),
         Ada.Calendar.Formatting.Second_Number (Second),
         Time_Zone => 0);
   exception
      when Constraint_Error | Ada.Calendar.Time_Error =>
         Valid := False;
         return Ada.Calendar.Time_Of (2000, 1, 1);
   end Timestamp_Time;
```

The skew test then subtracts the two times in `Verify_Request` itself, outside that guard (`src/flyology-object_storage-server-authentication.adb:157-165`):

```ada
      declare
         Difference : constant Duration :=
           (if Now >= Request_Time then Now - Request_Time
            else Request_Time - Now);
      begin
         if Difference > Rules.Maximum_Clock_Skew then
            return (Status => Request_Time_Too_Skewed, others => <>);
         end if;
      end;
```

`Verify_Request`'s own handler catches `Constraint_Error` only (`src/flyology-object_storage-server-authentication.adb:224-227`):

```ada
   exception
      when Constraint_Error =>
         return (Status => Malformed_Credentials, others => <>);
   end Verify_Request;
```

`Constraint_Error` is not what is raised. In the GNAT runtime this crate builds against, `Ada.Calendar.Year_Number` is `Integer range 1901 .. 2399`, `System.Duration_32_Bits` is `False`, so `Duration'Last` is 9_223_372_036.854775807 seconds, and `Ada.Calendar."-" (Left, Right : Time)` raises `Time_Error` when the difference leaves that range and re-raises an internal `Constraint_Error` as `Time_Error`. 9_223_372_036.854775807 seconds is 292.277 years, so every `x-amz-date` from about 292 years after the trusted clock up to the 2399 ceiling overflows: with a clock of 2026-09-06 the window opens at 2318-12-16 and advances one day per day. The past side cannot overflow, because 292 years before 2026 is below the 1901 floor.

The exception therefore leaves the public `Verify_Request` at its call site in `Handle` (`src/flyology-object_storage-server-s3_applications.adb:6697-6701`):

```ada
      Auth := Authentication.Verify_Request (X, Credentials, Rules, Clock);
      if Auth.Status /= Authentication.Authenticated then
         Send_Authentication_Error (X, Auth, Target_Text);
         return;
      end if;
```

and is absorbed by `Handle`'s catch-all, which sends 500 because no response has been started (`src/flyology-object_storage-server-s3_applications.adb:18056-18065`):

```ada
      when others =>
         if Apps.Response (X) /= Apps.Not_Started
           or else Apps.Wire_Response_Started (X)
         then
            Apps.Mark_Failed (X);
         else
            Send_Error
              (X, 500, "InternalError",
               "We encountered an internal error", Target_Text);
         end if;
```

The mapping that should have run is `src/flyology-object_storage-server-s3_applications.adb:1893-1897`:

```ada
         when Authentication.Request_Time_Too_Skewed =>
            Send_Error
              (X, 403, "RequestTimeTooSkewed",
               "The difference between the request time and the current " &
               "time is too large", Resource);
```

The contract being violated is `Verify_Request`'s own GNATdoc, which promises the skew is checked and says the checks run before the provider (`src/flyology-object_storage-server-authentication.ads:56-60`):

```ada
   --  Authenticate an exchange before accepting or consuming its body.
   --  Exactly one Authorization, date, content hash, and each declared signed
   --  field must be present. The scope date, semantic UTC timestamp, clock
   --  skew, optional region, and HTTPS requirement for UNSIGNED-PAYLOAD are
   --  checked before the credential provider is invoked.
```

`Outcome_Status` carries a dedicated value for this decision (`src/flyology-object_storage-server-authentication.ads:41-48`), and the code confirms the ordering: `Credentials.Authenticate` is reached only after the skew test, at `src/flyology-object_storage-server-authentication.adb:209-212`. An unauthenticated peer can therefore reach the failing subtraction.

No existing test covers it. The calendar assertions on `Valid_Timestamp` check month, day, hour and the year-zero floor but no far-future year, and they never call `Verify_Request` (`tests/src/object_storage_test_cases.adb:9066-9073`):

```ada
      Assert
        (Encoding.Valid_Timestamp ("20240229T235959Z")
         and then not Encoding.Valid_Timestamp ("20230229T235959Z")
         and then not Encoding.Valid_Timestamp ("20241301T000000Z")
         and then not Encoding.Valid_Timestamp ("20240132T000000Z")
         and then not Encoding.Valid_Timestamp ("20240101T240000Z")
         and then not Encoding.Valid_Timestamp ("00000101T000000Z"),
         "SigV4 timestamp calendar or time bounds");
```

The server corpus signs every request with the single constant `20130524T000000Z` (`tests/src/s3_server_application_corpus.adb:151`) against a fixed 2013-05-24 clock (`:407-409`) and a 1.0 second skew policy (`:807-809`), so it never varies the stamp. `RequestTimeTooSkewed` appears nowhere under `tests/src` or `server/tests`; the only occurrence in the repository is the server mapping quoted above. No test asserts the wrong behaviour, so no existing assertion has to change.

## What happens now

Spike: the program below drives an in-process S3 application over a memory backend with a static credential provider. It creates a bucket with an ordinary signed request as a control, sends the same routed request with `x-amz-date: 20200101T000000Z` to show that a moderately skewed date is diagnosed correctly, then sends it with `x-amz-date: 23900101T000000Z` and asserts the answer is 403 RequestTimeTooSkewed and specifically not 500. The year 2390 is inside `Year_Number` and beyond the overflow threshold for any clock in this decade, so the result does not depend on the day the program runs.

```ada
   Far_Future : constant String := "23900101T000000Z";
   Past       : constant String := "20200101T000000Z";
...
      Skewed : constant String :=
        Run (Signed_Request ("GET", "/skew-bucket",
                             Timestamp_Value => Past));
...
      Future : constant String :=
        Run (Signed_Request ("GET", "/skew-bucket",
                             Timestamp_Value => Far_Future));
   begin
      Check (Status_Code (Future) /= 500,
             "x-amz-date " & Far_Future & " is not answered with 500");
      Check (Status_Code (Future) = 403,
             "x-amz-date " & Far_Future & " is 403");
      Check (Contains (Body_Of (Future),
                       "<Code>RequestTimeTooSkewed</Code>"),
             "x-amz-date " & Far_Future & " is RequestTimeTooSkewed");
```

Output, exit status 1:

```
  -- control CreateBucket: status 200
  -- control CreateBucket: body 
  ok: control: a correctly signed CreateBucket is 200
  -- x-amz-date 20200101T000000Z: status 403
  -- x-amz-date 20200101T000000Z: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>RequestTimeTooSkewed</Code><Message>The difference between the request time and the current time is too large</Message><Resource>/skew-bucket</Resource></Error>
  ok: control: x-amz-date 20200101T000000Z is 403
  ok: control: x-amz-date 20200101T000000Z is RequestTimeTooSkewed
  -- x-amz-date 23900101T000000Z: status 500
  -- x-amz-date 23900101T000000Z: body <?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error</Message><Resource>/skew-bucket</Resource></Error>
  FAILED: x-amz-date 23900101T000000Z is not answered with 500
  FAILED: x-amz-date 23900101T000000Z is 403
  FAILED: x-amz-date 23900101T000000Z is RequestTimeTooSkewed
BUG REPRODUCED: 3 failed expectation(s)
```

The two dates take the same code path and differ only in magnitude. The 2020 stamp is diagnosed as 403 RequestTimeTooSkewed; the 2390 stamp becomes 500 InternalError.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

An `x-amz-date` that `Valid_Timestamp` accepted and that lies further from the trusted clock than `Rules.Maximum_Clock_Skew` should yield `Request_Time_Too_Skewed`, which the application renders as 403 RequestTimeTooSkewed, exactly as a stamp a few years off already does. `Verify_Request` is a public function whose GNATdoc states the clock skew is checked (`src/flyology-object_storage-server-authentication.ads:56-60`), so no exception should leave it for an input its own admission rules accepted.

## Suggested treatment

The smallest fix contains the subtraction where it happens. `Clock_Skew` is `Duration range 0.0 .. 86_400.0` (`src/flyology-object_storage-server-authentication.ads:32`), so a difference that overflows `Duration` is by construction larger than any permitted skew, and the overflow is the answer:

```ada
      declare
         Difference : Duration;
      begin
         Difference :=
           (if Now >= Request_Time then Now - Request_Time
            else Request_Time - Now);
         if Difference > Rules.Maximum_Clock_Skew then
            return (Status => Request_Time_Too_Skewed, others => <>);
         end if;
      exception
         when Ada.Calendar.Time_Error =>
            return (Status => Request_Time_Too_Skewed, others => <>);
      end;
```

This needs a maintainer decision:

- Contain the overflow in `Verify_Request` as above and report `Request_Time_Too_Skewed`. This introduces no new interface value, keeps `Outcome_Status` unchanged, and makes the 2390 case answer 403 like the 2020 case.
- Report the overflow as `Malformed_Credentials` instead, by widening the handler at `src/flyology-object_storage-server-authentication.adb:224-226` to `when Constraint_Error | Ada.Calendar.Time_Error`. This is a smaller edit but answers 400 AuthorizationHeaderMalformed, which is the answer years 0001 to 1900 already get because they fail `Year_Number` inside `Timestamp_Time`. It makes the observable status depend on which side of `Year_Number` the stamp falls.
- Give `Valid_Timestamp` an explicit accepted-year range so far-future stamps are refused at admission. This adds a public policy bound to a SPARK unit and decides what year range the server accepts, which falls under the "Ada interface values" and "Decision authority" sections of `AGENTS.md`. It is also not sufficient on its own unless the chosen ceiling is proved to keep the subtraction inside `Duration` for every supported clock.

The regression test belongs in `tests/src/s3_server_application_corpus.adb`, whose `Signed_Request` helper fixes the timestamp at `tests/src/s3_server_application_corpus.adb:151`; the case needs a caller-supplied stamp so it can send `23900101T000000Z` against `Fixed_Clock` and assert 403 RequestTimeTooSkewed. The spike is the test. No existing assertion has to change.

## Severity

Any routed request carrying an accepted but far-future `x-amz-date` is answered 500 InternalError rather than the 403 the server defines for it, so a client-side error is reported as a server fault and the operator's diagnostics point at the wrong side. The peer needs no credentials at all, because the skew test runs before the provider is invoked, and the connection and process survive, since the application's catch-all contains the exception. The trigger is unusual input that no stock client produces: a stamp more than 292 years ahead of the server clock, today from 2318-12-16 to the 2399 ceiling. A server built directly on `Authentication` rather than on `S3_Applications` would instead see the exception propagate into its own connection handler. Deterministic.
