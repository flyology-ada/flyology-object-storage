Title: Administrator login runs 600,000 PBKDF2 iterations on the shared event loop and stalls every S3 request
Labels: bug
Refs: SERVER-EXE-2

## Summary

Both HTTP listeners instantiate `Flyology.IO.Structured_Servers` with `Handler_Model => Flyology.Lightweight_Task`, and the automatic execution-group pool defaults to one, so every handler of both listeners is multiplexed onto a single event-loop thread. The management `Login` handler then runs a 600,000-iteration PBKDF2-HMAC-SHA256 derivation inline, with no I/O, no delay and no `Cancellation.Requested` poll, which is exactly the CPU-only case the `Structured_Servers` contract requires a handler to break up. One administrator sign-in holds the loop for about a second: a signed S3 request issued during it takes 0.883 s where the same request with no other traffic takes 0.002 s to 0.007 s. Ten simultaneous logins keep an S3 request waiting 9.780 s, while a plain TCP connect to the same port still completes in 0.001 s, so a health check that only opens a socket does not see the outage.

## Problem

Commit `5fe6e3e`.

The S3 listener runs its handlers as cooperative lightweight tasks (`server/src/flyology_object_storage_server_runtime.adb:187-190`):

```ada
      package Structured is new Flyology.IO.Structured_Servers
        (Handler_Context => Server_Context,
         Handle          => Handle,
         Handler_Model   => Flyology.Lightweight_Task);
```

and so does the management listener (`server/src/flyology_object_storage_server_runtime.adb:853-858`):

```ada
      package Structured is new Flyology.IO.Structured_Servers
        (Handler_Context => Service_Context,
         Handle => Handle,
         Handler_Model => Flyology.Lightweight_Task);

      Server : aliased Structured.Server (Capacity => 32);
```

Neither instantiation sets a `Handler_CPU`, so both are placed by the automatic pool. The pinned flyology 0.1.1-dev release defines that model (`flyology.ads:21-26`, Darwin platform source):

```ada
   --  Run the task cooperatively on an event loop. A CPU aspect in 1 .. 127
   --  selects that shared execution group. Ada reserves CPU 0 as
   --  Not_A_Specific_CPU, so it selects the configured pool exactly as an
   --  absent aspect does.
   Lightweight_Task : constant Execution_Model :=
     System.Task_Info.Process_Scope;
```

and states the pool's default size (`flyology-execution_groups.ads:154-159`):

```ada
   --  Return the automatic pool size without starting any group. The value of
   --  FLYOLOGY_LOOP_POOL_SIZE is captured once at process startup, defaults to
   --  one when absent, and establishes the initial size before task
   --  activation.
   --  Runtime growth or reduction may change it later. A lightweight task
   --  without a specific CPU is assigned among groups 0 .. Result - 1.
```

Nothing in the executable grows that pool, `server/README.md` does not mention `FLYOLOGY_LOOP_POOL_SIZE`, and the maintained test launches the server with `env -i` (`server/tests/scripts/test.sh:462-471`), so the shipped default of one group applies.

`Login` calls the password check inline in its handler (`server/src/flyology_object_storage_server_runtime.adb:438-440`):

```ada
           or else not Admin_Credentials.Verify
             (Admin_Credential, "admin",
              Form (Form'First + Login_Prefix'Length .. Form'Last))
```

The work factor is 600,000 (`server/src/flyology_object_storage_server_credentials.adb:16`):

```ada
   Work_Factor : constant Positive := 600_000;
```

and the derivation loop suspends on nothing (`server/src/flyology_object_storage_server_credentials.adb:134-147`):

```ada
      for Iteration in 2 .. Iterations loop
         declare
            Next : String (1 .. Hash_Length) := HMAC (Password, U);
         begin
            for Index in Result'Range loop
               Result (Index) := Character'Val
                 (Interfaces.Unsigned_8 (Character'Pos (Result (Index))) xor
                  Interfaces.Unsigned_8 (Character'Pos (Next (Index))));
            end loop;
            Wipe (U);
            U := Next;
            Wipe (Next);
         end;
      end loop;
```

That is the case the server library requires a handler to break up (pinned flyology 0.1.1-dev, `flyology-io-structured_servers.ads:98-102`):

```ada
   --  other values are seconds. One deadline covers the drain. Connection I/O
   --  wakes on cancellation, while
   --  CPU-only Handle code must poll Cancellation.Requested cooperatively.
   --  Lightweight handlers suspend on event-loop I/O; native handlers block
   --  their threads.
```

A wrong password costs the same as a right one, because `Verify` derives first and compares afterwards in constant time (`server/src/flyology_object_storage_server_credentials.adb:329-340`):

```ada
      if User'Length /= Username'Length
        or else not Constant_Time_Equal (User, Username)
        or else Password'Length not in 1 .. 64
      then
         return False;
      end if;
      declare
         Candidate : String (1 .. Hash_Length) :=
           Derive (Password, Value.Salt, Value.Iterations);
         Matches : constant Boolean :=
           Constant_Time_Equal (Candidate, Value.Hash);
```

The length gate at `:331` never short-circuits a real attempt, because `Login` reaches `Verify` only with a password of exactly `Generated_Password_Length` characters. The constant-time comparison itself is correct and is not what this report is about.

Nothing documents the coupling. `server/README.md:8-12` couples the two listeners only through supervision order:

```
The server provides bounded S3 and management HTTP/1.1 listeners under a
dependency-ordered Flyology static supervisor. SIGTERM requests an orderly
stop, interrupts accepts and active connection handlers, and allows a
ten-second S3 drain. The management child depends on the S3 child, so an S3
generation failure restarts the workbench generation as well.
```

No existing test can catch it. The maintained script issues its logins one after another with a full second between them (`server/tests/scripts/test.sh:102-107`):

```sh
  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H "Origin: $base" \
    --data-binary 'username=admin&password=000000000000000000000000000000000000000000000000')
  test "$code" = 401
  sleep 1
```

and never issues S3 traffic while a login is in flight, so no assertion covers S3 availability during a sign-in and none has to change.

## What happens now

Spike: the program below starts the built server itself on a fresh temporary root with `env -i`, `FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0` and the memory backend, reads the two `READY` ports and the bootstrap password from the server's own output, then times three signed SigV4 `ListBuckets` requests with no other traffic, three logins on their own, and three signed S3 requests each issued 0.15 s into a valid login, with a plain TCP connect alongside. It asserts the correct behaviour, that a concurrent S3 request stays within the larger of ten times the worst baseline and 0.050 s, and it always stops the server.

```sh
for run in 1 2 3; do
  python3 "$probe" login "$admin_port" "$password" >"$work/login-$run" 2>&1 &
  login_pid=$!
  sleep 0.15
  s3out=$(python3 "$probe" s3 "$s3_port" REPROKEY reprosecret us-east-1) || exit 2
  conn=$(python3 "$probe" connect "$s3_port") || exit 2
  wait "$login_pid"
```

Output, exit status 1:

```
  -- s3 port 59318, management port 59319, loop pool = default (FLYOLOGY_LOOP_POOL_SIZE unset)
  -- baseline: signed S3 ListBuckets with no other traffic (3 runs)
     run 1: 0.007 200 184  (seconds status bytes)
     run 2: 0.002 200 184  (seconds status bytes)
     run 3: 0.002 200 184  (seconds status bytes)
  -- worst baseline S3 latency: 0.007s
  -- one management login on its own (3 runs)
     run 1: 1.124 200 {"authenticated":true}
     run 2: 1.014 200 {"authenticated":true}
     run 3: 1.018 200 {"authenticated":true}
  -- threshold for a concurrent S3 request: 0.07s (max of 10x baseline and 0.050 s)
  -- S3 request issued 0.15 s into a valid login (3 runs)
     run 1: s3=0.883 200 184  tcp-connect=0.001 connected  login=1.036 200 {"authenticated":true}
     run 2: s3=0.862 200 184  tcp-connect=0.001 connected  login=1.017 200 {"authenticated":true}
     run 3: s3=0.853 200 184  tcp-connect=0.001 connected  login=1.014 200 {"authenticated":true}
  -- worst S3 latency during a login: 0.883s
  FAILED: an S3 request issued during an administrator login stays within 0.07s
  -- control: S3 request after the logins: 0.002 200 184  (seconds status bytes)
  ok: control: with no login in flight the same signed S3 request is fast
BUG REPRODUCED: 1 failed expectation(s)
```

The control shows the request is fast again once no login is in flight, so the signature, the probe and the listener are all healthy. The TCP connect is unaffected in every run, because the kernel accept queue absorbs the connection while no handler can run.

A second measurement against the same binary shows what happens with more than one login outstanding, and what a larger loop pool does:

```
== default loop pool (FLYOLOGY_LOOP_POOL_SIZE unset)
  -- baseline s3: 0.007 200 184
  -- ten concurrent logins:
     s3 at t+0.3 s: 9.780 200 184
     flood wall: 10.16s, statuses:   10 200
== FLYOLOGY_LOOP_POOL_SIZE=8
  -- baseline s3: 0.002 200 184
  -- one concurrent login:
     s3 at t+0.3 s: 0.002 200 184
     flood wall: 1.07s, statuses:    1 200
  -- ten concurrent logins:
     s3 at t+0.3 s: 0.798 200 184
     flood wall: 2.23s, statuses:   10 200
```

Ten simultaneous logins hold one S3 request for 9.780 s of the flood's 10.16 s, and all ten are run to completion. Raising the pool to eight groups removes the single-login stall, since the S3 probe then measures 0.002 s, but ten logins still stall an S3 request for 0.798 s. A larger pool raises the number of simultaneous derivations needed to starve the loop from one to the pool size and does nothing else.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. The binary is the crate's default `alr -n build` development profile. The host was on AC power with `pmset -g` reporting `powermode 0` and `pmset -g therm` recording no thermal or performance warning; every baseline and the comparison beside it were taken back to back under that profile.

## What should happen

An administrator sign-in must not change S3 request latency. `server/README.md:8-12` presents the two listeners as bounded services coupled only through supervision order, and `flyology-io-structured_servers.ads:98-102` requires CPU-only handler code to poll `Cancellation.Requested` cooperatively, which a 600,000-iteration derivation with no poll does not.

## Suggested treatment

The derivation has to stop occupying the cooperative loop. This needs a maintainer decision, because each option adds an externally visible placement or resource choice under the "Decision authority" and "Ada interface values" sections of `AGENTS.md`:

- Run the derivation off the loop on a native thread, either by giving the management listener `Handler_Model => Flyology.Native_Task` at `server/src/flyology_object_storage_server_runtime.adb:853-858`, or by handing password verification to one dedicated native task. The first moves every management handler off the loop; the second keeps the handler cooperative and needs a hand-off point and a queue bound.
- Run it on a bounded worker pool sized for concurrent verifications. This bounds the CPU the login path can take, and the pool size is a new public resource value.
- Break the loop up with a cooperative yield and a `Cancellation.Requested` poll every N iterations at `server/src/flyology_object_storage_server_credentials.adb:134-147`. The interval N is a new value, the derivation still consumes the only loop, and a concurrent S3 request would be interleaved rather than freed.
- Grow the automatic pool at startup. That is a new public policy value and, as the `FLYOLOGY_LOOP_POOL_SIZE=8` measurement above shows, it only raises the number of concurrent logins needed to starve the loop.

The absent admission bound on the same route is a separate defect, reported as {{ISSUE:SERVER-EXE-2}}. The two are complementary: a rate limit bounds how many derivations can be queued, and moving the derivation off the loop bounds what one derivation costs the S3 listener. Fixing either alone leaves the other.

The regression test belongs in `server/tests/scripts/test.sh`, beside the existing login sequence at `:102-117`. The case should measure a signed S3 request with no other traffic, issue a valid login, and assert that a signed S3 request issued during the login stays within a bounded multiple of that baseline, with an absolute floor so scheduling noise on a sub-millisecond baseline cannot trip it. The spike is the test. No existing test asserts the wrong behaviour, so nothing has to change.

## Severity

Any deployment in which an administrator opens the workbench while S3 clients are active loses S3 service for the duration of the sign-in, about one second per login on this host, which is more than a hundred times the slowest baseline request measured beside it. It needs no invalid input and no unusual configuration: it is what the shipped defaults do on every sign-in. The unbounded form, ten or more simultaneous logins holding the listener for ten seconds or more, needs a local process that can reach the loopback-only management port, and it needs no session and no valid credential, because a wrong password costs the same derivation. A socket-only health check reports the server healthy throughout. Deterministic.
