# Correctness discovery: server executable (SERVER-EXE)

Scope: the `flyology_object_storage_server` crate at commit 5fe6e3e, read in
full — `server/src/flyology_object_storage_server.adb` (main, 100 lines),
`flyology_object_storage_server_configuration.ad?` (27 + 98),
`flyology_object_storage_server_credentials.ad?` (38 + 345) and
`flyology_object_storage_server_credentials_native.c` (155),
`flyology_object_storage_server_credentials_corpus.adb` (65),
`flyology_object_storage_server_runtime.ad?` (11 + 1090),
`flyology_object_storage_server_sessions.ad?` (22 + 79),
`flyology_object_storage_server_signals.ad?` (20 + 25),
`flyology_object_storage_server_assets.ad?` (16 + 72); `server/assets/app.js`
(request shapes: `fetch` calls, `Content-Type`, `credentials`, `textContent`
only) and `server/assets/index.html` (single external `<script>`, no inline
code); `server/README.md`, `server/alire.toml`,
`server/flyology_object_storage_server.gpr`, `server/tests/scripts/test.sh`
(565 lines), `.github/workflows/ci.yml` (server wiring).
Library contracts consulted: `flyology_http` 0.1.3 specs
`flyology-http-server.ads:18-100,460-520,590-620` (`Max_Request_Body`,
`Ingress_Budget`, `Read_Request_Head` deadline, `Request_Deadline`),
`flyology-http-server-applications.ads` (`Request_Authority`, `Content`,
`Request_Header`, `Create`, `JSON`), `flyology-http-server-routing.ads:81-89`
(`Route_Policy`), `flyology-http-server-routing.adb:1996-2004,2255-2280`
(route metadata, handler exception block),
`flyology-http-server-responses.ads:25-41` (`Set_Cookie`),
`flyology-http-server-requests.ads` (`Query`, `Has_Query`),
`flyology-http-server-connection_handlers.ads` and `.adb:30-175` (`Serve`
timeout semantics, exception coverage),
`flyology-http-server-middleware_rate_limits.ad?`,
`flyology-http-server-middleware_bulkheads.ad?`,
`flyology-http-server-applications.adb:1080-1094`; `flyology` 0.1.1
`flyology-io-structured_servers.ads` and `.adb:184-236,445-465,536-560`,
`flyology-supervision.ads:110-145,164-177,236-300,340-415`,
`flyology-supervision-static.ads:60-125` and `.adb:700-790,823-851`,
`flyology-supervision-children.adb`, `flyology-task_results.adb:88`,
`platform/darwin/flyology.ads:20-28`, `flyology-execution_groups.ads:145-158`
and `.adb:35-137`, `flyology-io-sockets.ads` (`Port`, `Loopback_IPv4`,
`Is_IP_Address`), `native/flyology_sockets.c` (SIGPIPE suppression).
Repository pieces wired by the executable:
`src/flyology-object_storage-server-s3_applications.ads` and `.adb:18020-18066`
(top-level handler), `src/flyology-object_storage-server-static_credentials.ad?`
(`Create`, `Invalid_Credentials` messages),
`src/flyology-object_storage-backends-files.adb:3514-3567` (`Open`, root
handling) and `Validate_Tree_Symlink_Free`,
`sqlite/src/flyology-object_storage-backends-sqlite.adb:105-149,247-315`
(`Open`, `Clean_Directory`, `flock` root lock via
`flyology_object_storage_sqlite_durability.c:77`),
`src/flyology-object_storage-backends.ads` (list limits),
`src/flyology-object_storage-s3-listings.adb:329-376` and
`src/flyology-object_storage-s3-core.adb:8-24` (continuation tokens),
`src/flyology_object_storage_secure_erase.c`, `docs/architecture/files-layout.md`,
`docs/architecture/sqlite-backend.md:151-158`, `tests/src/s3_server_harness.adb:96-114`.
GNAT 15.3.1 runtime sources (`gnat_native_15.3.1_36dc7314`: `a-strsea.adb:610-621`,
`a-textio.adb:311-365`) were read to confirm `Index (From)` and
`End_Of_File` semantics. `python3` was used to confirm that the three pinned
asset digests equal the SHA-256 of the shipped files byte-for-byte and that
the PBKDF2 self-test vector equals `hashlib.pbkdf2_hmac`.
Existing coverage inspected: `server/tests/scripts/test.sh` (the only
maintained black-box test of the executable), the credentials corpus, and
the CI workflow (which runs `tests/scripts/test-flyology-server.sh` against
the in-tree test servers, not the server crate).

Severity rubric: P0 memory/aliasing unsafety, security-relevant (signature
bypass, traversal or symlink escape, credential or secret exposure,
authorisation bypass), data loss or durability violation, hang or deadlock in
normal operation, or interop-breaking protocol violation; P1 wrong result or
unexpected exception on valid input via a reachable path, or a documented
contract violated; P2 edge-case incorrectness, wrong diagnostics, or contract
drift needing unusual input.

| ID | Title | Severity | Confidence |
|----|-------|----------|------------|
| SERVER-EXE-1 | Administrator login runs 600,000 PBKDF2 iterations on the shared cooperative event loop and stalls the S3 listener | P1 | Medium |
| SERVER-EXE-2 | Management route `Concurrency`/`Rate_Per_Second` policies are inert: no rate-limit or bulkhead middleware is installed | P2 | High |
| SERVER-EXE-3 | Any `FLYOLOGY_OBJECT_STORAGE_ROOT` is handed to `Files.Open`/`SQLite.Open`, which delete a pre-existing `tmp/`, `staging/` or unreferenced `objects/` content of that directory with no layout check | P2 | High |
| SERVER-EXE-4 | Supervisor termination diagnostics are discarded: a listener bind failure or exhausted recovery prints only the outcome name | P2 | High |

---

### SERVER-EXE-1: Administrator login runs 600,000 PBKDF2 iterations on the shared cooperative event loop and stalls the S3 listener

**Location:** `server/src/flyology_object_storage_server_runtime.adb:426-444`
(`Login` calls `Verify`), `:853-858` (management handlers are
`Lightweight_Task`), `:187-190` (S3 handlers are `Lightweight_Task`),
`server/src/flyology_object_storage_server_credentials.adb:125-155,325-344`
(`Derive`, `Verify`).

**Severity:** P1. **Confidence:** Medium (the mechanism is established by the
library contracts quoted below; the stall duration per attempt is not
measured here).

**Evidence:**

`server/src/flyology_object_storage_server_runtime.adb:853-858`
```ada
      package Structured is new Flyology.IO.Structured_Servers
        (Handler_Context => Service_Context,
         Handle => Handle,
         Handler_Model => Flyology.Lightweight_Task);

      Server : aliased Structured.Server (Capacity => 32);
```

`server/src/flyology_object_storage_server_runtime.adb:187-190`
```ada
      package Structured is new Flyology.IO.Structured_Servers
        (Handler_Context => Server_Context,
         Handle          => Handle,
         Handler_Model   => Flyology.Lightweight_Task);
```

`server/src/flyology_object_storage_server_runtime.adb:432-444`
```ada
         if not Same_Origin (State, X)
           or else Form'Length /= Login_Prefix'Length +
             Admin_Credentials.Generated_Password_Length
           or else Form
             (Form'First .. Form'First + Login_Prefix'Length - 1) /=
             Login_Prefix
           or else not Admin_Credentials.Verify
             (Admin_Credential, "admin",
              Form (Form'First + Login_Prefix'Length .. Form'Last))
         then
            X.JSON (401, "{""authenticated"":false}");
            return;
         end if;
```

`server/src/flyology_object_storage_server_credentials.adb:134-147` (no yield,
no cancellation poll inside the loop)
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

`server/src/flyology_object_storage_server_credentials.adb:16` and
`:336-337`
```ada
   Work_Factor : constant Positive := 600_000;
...
         Candidate : String (1 .. Hash_Length) :=
           Derive (Password, Value.Salt, Value.Iterations);
```

Contract of the handler model, `flyology` 0.1.1
`src/platform/darwin/flyology.ads:22-27`
```ada
   --  Run the task cooperatively on an event loop. A CPU aspect in 1 .. 127
   --  selects that shared execution group. Ada reserves CPU 0 as
   --  Not_A_Specific_CPU, so it selects the configured pool exactly as an
   --  absent aspect does.
   Lightweight_Task : constant Execution_Model := System.Task_Info.Process_Scope;
```

`flyology` 0.1.1 `src/flyology-io-structured_servers.ads:100-105`
```ada
   --  ... One deadline covers the drain. Connection I/O
   --  wakes on cancellation, while
   --  CPU-only Handle code must poll Cancellation.Requested cooperatively.
   --  Lightweight handlers suspend on event-loop I/O; native handlers block
   --  their threads.
```

`flyology` 0.1.1 `src/flyology-execution_groups.ads:148-153` (both listeners'
handlers, and the supervisor's manager tasks, land on the same single group
by default)
```ada
   --  Return the automatic pool size without starting any group. The value of
   --  FLYOLOGY_LOOP_POOL_SIZE is captured once at process startup, defaults to
   --  one when absent, and establishes the initial size before task
   --  activation.
   --  Runtime growth or reduction may change it later. A lightweight task
   --  without a specific CPU is assigned among groups 0 .. Result - 1.
```

Nothing in the executable or its dependencies grows the pool (`rg
Grow_Configured_Pool|FLYOLOGY_LOOP_POOL_SIZE` over `server/`, `src/`,
`tests/`, `sqlite/`, the `flyology` and `flyology_http` sources: the only
matches are the definition and its C import in `flyology-execution_groups.adb:35-137`;
no call site exists), and
`server/tests/scripts/test.sh:388-392,462-471` launch the executable with
`env -i`, so the default pool of one applies.

Documented behaviour the executable claims, `server/README.md:8-12`
```
The server provides bounded S3 and management HTTP/1.1 listeners under a
dependency-ordered Flyology static supervisor. ... The management child
depends on the S3 child, so an S3 generation failure restarts the workbench
generation as well.
```
(the only documented coupling between the listeners is supervision order; no
document says a workbench login pauses S3 service).

**Failure scenario:**

1. The server starts with default environment; `Configured_Pool_Size` is 1,
   so the 32 management handler tasks (`:858`), the up-to-128 S3 handler tasks
   (`:194-195`), and the supervisor's manager tasks are all cooperative tasks
   multiplexed on one event-loop thread.
2. Any local process (no session or credential needed; `Same_Origin` accepts a
   request without an `Origin` header, `:338-341`) sends
   `POST /api/login` with a 72-byte body `username=admin&password=<48 hex>`.
   The route buffers 256 bytes at most (`:882-887`) and calls `Login`.
3. `Login` (`:438-440`) calls `Verify` → `Derive` with 600,000 iterations
   (`credentials.adb:134-147`), a pure CPU loop of 600,000 HMAC-SHA256
   computations in `GNAT.SHA256` that never suspends on I/O, never delays,
   and never polls `Cancellation.Requested`.
4. Because the handler is a cooperative task on the only event loop, every
   other lightweight task on that loop — every in-flight and newly accepted
   S3 connection handler, the other management handlers, and the supervisor
   managers — cannot run until the derivation completes. A legitimate
   workbench sign-in therefore pauses all S3 request processing for the
   derivation time; a sustained loop of login requests from an
   unauthenticated local process (there is no effective rate limit, see
   SERVER-EXE-2; the 32 handlers serialise on the loop) keeps the S3 listener
   unresponsive for as long as the loop runs, and drains the 60-second S3
   request timeout of clients that were mid-request.
5. During SIGTERM drain the same handler cannot be cancelled by
   `Handler_Stop` (`structured_servers.adb:232-234`) until its derivation
   finishes, contrary to the `Structured_Servers` requirement that CPU-only
   handler code poll cancellation.

The failure needs no invalid input: a single correct login shows the stall;
the DoS variant needs only loopback TCP access to the management port.

**Reproduction test sketch:** (a real process is required; the in-process
harness `tests/src/s3_server_harness.adb:108-110` instantiates
`Structured_Servers` with the default `Handler_Model`, i.e. native tasks, so
it cannot reproduce this.)

1. `FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0 ./bin/flyology_object_storage_server`
   with no other environment (memory backend); read `$S3` and `$ADMIN` ports
   from the `READY` lines.
2. Baseline: `curl -s -o /dev/null -w '%{time_total}\n' http://127.0.0.1:$S3/`
   (unauthenticated `ListBuckets`, answered with a 403 in milliseconds).
3. In the background run, for 30 seconds, 8 parallel loops of
   `curl -s -o /dev/null -X POST -H "Origin: http://127.0.0.1:$ADMIN" --data-binary "username=admin&password=$(printf '0%.0s' $(seq 48))" http://127.0.0.1:$ADMIN/api/login`.
4. Repeat step 2 while step 3 runs. Expected (correct) result: S3 latency
   stays at the baseline because the listeners are documented as
   independent bounded services. Actual result: each S3 request waits behind
   the queued derivations (multiple seconds per probe; with the loops
   sustained, probes exceed client timeouts). Control: re-run with
   `FLYOLOGY_LOOP_POOL_SIZE=8`; the stall shrinks but does not disappear
   (each derivation still blocks one eighth of the handlers).
5. Single-login variant: time one valid login while a concurrent
   `aws --endpoint-url http://127.0.0.1:$S3 s3 ls` runs; the `s3 ls` completes
   only after the login response.

**Existing coverage:** `server/tests/scripts/test.sh:102-117` exercises three
sequential logins with `sleep 1` between them and never issues S3 traffic
concurrently with a login; the s5cmd slice (`:438-440`, `:512-514`) runs
before `verify_bucket_inventory` logs in. Nothing asserts S3 latency or
availability during a login, and nothing runs the lightweight handler model
except the executable itself.

**Refutation attempts:**
- Checked whether the management and S3 listeners use different execution
  groups: both instantiate `Structured_Servers` with
  `Handler_Model => Flyology.Lightweight_Task` and the default
  `Handler_CPU => Not_A_Specific_CPU` (`structured_servers.ads:36-42`), so
  both are placed by the automatic pool.
- Checked whether the pool is larger than one by default or grown by the
  executable or a dependency: `Configured_Pool_Size` "defaults to one when
  absent"; no `Grow_Configured_Pool` caller exists in the reviewed trees; the
  maintained test uses `env -i`.
- Checked whether `Derive`/`HMAC` yields: `GNAT.SHA256` and the loop in
  `credentials.adb:134-147` contain no delay, I/O, or cancellation poll.
- Checked whether the route policy bounds the damage: `Concurrency => 1,
  Rate_Per_Second => 2` on `/api/login` (`:882-887`) is never enforced
  (SERVER-EXE-2); even if it were, a single derivation would still stall the
  loop for its full duration.
- Checked whether `Verify` short-circuits on a wrong password before deriving:
  it derives first and compares in constant time (`credentials.adb:336-341`),
  which is correct for timing safety but means every attempt pays the full
  cost.

---

### SERVER-EXE-2: Management route `Concurrency`/`Rate_Per_Second` policies are inert: no rate-limit or bulkhead middleware is installed

**Location:** `server/src/flyology_object_storage_server_runtime.adb:882-918`
(route registrations), `:837-851` (`Handle` serves the router directly).

**Severity:** P2. **Confidence:** High.

**Evidence:**

`server/src/flyology_object_storage_server_runtime.adb:882-887`
```ada
      State.Routes.Post
        ("/api/login", Login'Access, Name => "admin.login",
         Policy =>
           (Routing.Default_Route_Policy with delta
              Body_Handling => Apps.Buffer_Body, Max_Body => 256,
              Concurrency => 1, Rate_Per_Second => 2));
```
(the same pattern sets `Concurrency`/`Rate_Per_Second` on `/api/buckets`,
`/api/objects`, `/api/buckets/delete`, `/api/logout`, `:888-918`).

`server/src/flyology_object_storage_server_runtime.adb:847-850` — the router is
served with no middleware registered anywhere in the file (`rg -n -i
'middleware|bulkhead|rate_limits' server/src/` returns nothing):
```ada
         HTTP.Configure_Ingress_Budget (Client, State.Budget'Access);
         State.Routes.Serve
           (State.Application, Client, Peer, Timeout => 30.0,
            Header_Timeout => 5.0, Token => Cancellation);
```

Contract, `flyology_http` 0.1.3 `src/flyology-http-server-routing.ads:81-89`
```ada
   --  Route-local policy consumed incrementally by optional toolkit layers.
   --  A zero concurrency or rate value means unlimited. ...
   --  @field Concurrency Maximum active handlers; zero is unlimited
   --  @field Rate_Per_Second Per-client admission rate; zero is unlimited
```

`src/flyology-http-server-middleware_rate_limits.ads:6,24-25`
```ada
--  Enforces bounded per-client, per-route token buckets.
...
   --  Token-bucket middleware. Burst capacity equals the configured route
   --  requests-per-second rate. Rejection is 429 with Retry-After.
```

`src/flyology-http-server-middleware_bulkheads.ads:5,20`
```ada
--  Enforces nonblocking global and route concurrency limits.
...
   --  Nonblocking bulkhead middleware. Rejection is 503 with Retry-After.
```

`src/flyology-http-server-applications.adb:1080-1094` (`Configure_Route` only
stores the values) and the only consumers of `X.Rate_Per_Second` /
`X.Concurrency_Limit` are `middleware_rate_limits.adb:140` and
`middleware_bulkheads.adb:180`.

The maintained test paces itself as if the limit existed,
`server/tests/scripts/test.sh:102-117`
```sh
  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H "Origin: $base" \
    --data-binary 'username=admin&password=000000000000000000000000000000000000000000000000')
  test "$code" = 401
  sleep 1
```

**Failure scenario:** Any number of concurrent `POST /api/login` requests
from the same peer are all admitted up to the listener's 32 handlers and
each runs the full PBKDF2 derivation; there is no 429/503, no burst cap, and
no per-client bucket. The same holds for the mutation routes (`Concurrency
=> 1` on create/delete is not enforced, so two concurrent creates of the same
name race on the backend's atomic primitive — which the backends handle —
but the intended serialisation is absent). Brute force of the 192-bit
password remains infeasible; the practical impact is that SERVER-EXE-1 has no
admission bound, and that the route registrations and the test script
document a protection that does not exist.

**Reproduction test sketch:** With the server running, issue 10 concurrent
`POST /api/login` requests with a wrong 48-hex password and `Origin:
http://127.0.0.1:$ADMIN`. Expected under the written policy: at most 2 per
second admitted, the rest receive `429` with `Retry-After` (or `503` from a
bulkhead); actual: all 10 return `401` after their derivations complete. In
process, `Middleware_Rate_Limits` can be instantiated over `Routing.Components`
and installed before the routes to make the written policy effective;
`Middleware_Bulkheads` likewise for `Concurrency`.

**Existing coverage:** none asserts a 429/503; `test.sh:106,112,142,147,...`
insert `sleep 1` between mutating requests, which passes with or without the
limit.

**Refutation attempts:**
- Searched the router body for any automatic enforcement of
  `Policy.Concurrency`/`Policy.Rate_Per_Second`: `routing.adb:1996-2004`
  passes them to `X.Configure_Route`; `Automatic_Rate_Per_Second` (`:1568`)
  concerns automatic 404/405 responses only, and no bucket or counter exists
  in `routing.adb` outside the middleware packages.
- Checked `server/README.md` for a rate-limit claim: none, so this is not a
  documented-contract violation (hence P2, not P1); the intent is visible only
  in the route policy literals and the test's pacing.

---
### SERVER-EXE-3: Any `FLYOLOGY_OBJECT_STORAGE_ROOT` is handed to `Files.Open`/`SQLite.Open`, which delete a pre-existing `tmp/`, `staging/` or unreferenced `objects/` content of that directory with no layout check

**Location:** `server/src/flyology_object_storage_server_configuration.adb:42-46`,
`server/src/flyology_object_storage_server.adb:64-68,78-82` (the executable's
only validation and the hand-off); `src/flyology-object_storage-backends-files.adb:3549-3564`
and `Validate_Tree_Symlink_Free`;
`sqlite/src/flyology-object_storage-backends-sqlite.adb:247-275,304-305`.
Shared with the FILES and SQLITE areas: the destructive code is theirs, the
reachable path through an environment variable is the executable's.

**Severity:** P2 (needs unusual input: a root that is not a dedicated
directory). **Confidence:** High for the mechanism; the operational
likelihood is a judgement.

**Evidence:**

`server/src/flyology_object_storage_server_configuration.adb:42-46` — the
only check the executable performs on the root
```ada
      if Result.Backend /= Memory and then Root'Length = 0 then
         raise Constraint_Error with
           "FLYOLOGY_OBJECT_STORAGE_ROOT is required for " & Backend_Name;
      end if;
      Result.Storage_Root := To_Unbounded_String (Root);
```

`server/src/flyology_object_storage_server.adb:64-68`
```ada
      when Configuration.Files =>
         declare
            Store : Flyology.Object_Storage.Backends.Files.Store :=
              Flyology.Object_Storage.Backends.Files.Open
                (US.To_String (Settings.Storage_Root));
```

`src/flyology-object_storage-backends-files.adb:3549-3564` — an existing
`<root>/tmp` directory is deleted recursively before the store's own `tmp`
is created; the only guards are "not a symlink" and "is a directory"
```ada
         if GNAT.OS_Lib.Is_Symbolic_Link
           (Join (US.To_String (Full), "tmp"))
         then
            raise Configuration_Error;
         elsif Ada.Directories.Exists (Join (US.To_String (Full), "tmp")) then
            if Ada.Directories.Kind (Join (US.To_String (Full), "tmp")) /=
              Ada.Directories.Directory
            then
               raise Configuration_Error;
            end if;
            Validate_Tree_Symlink_Free
              (Join (US.To_String (Full), "tmp"));
            Ada.Directories.Delete_Tree (Join (US.To_String (Full), "tmp"));
            Sync_Directory (Result, US.To_String (Full));
         end if;
         Ensure_Directory (Result, Join (US.To_String (Full), "tmp"));
```

`Validate_Tree_Symlink_Free` (same file) raises `Data_Error` only when the
tree contains a symlink, a special file, or exceeds depth 64; a tree of
ordinary files and directories passes:
```ada
               if GNAT.OS_Lib.Is_Symbolic_Link (Full) then
                  raise Ada.IO_Exceptions.Data_Error;
               elsif Ada.Directories.Kind (Full) = Ada.Directories.Directory
               then
                  Validate_Tree_Symlink_Free (Full, Depth + 1);
               elsif Ada.Directories.Kind (Full) /=
                 Ada.Directories.Ordinary_File
               then
                  raise Ada.IO_Exceptions.Data_Error;
               end if;
```

`sqlite/src/flyology-object_storage-backends-sqlite.adb:304-305` and
`:264-270` — every ordinary file in `<root>/staging` is deleted; every
ordinary file in `<root>/objects` whose name is not a catalog-referenced
payload is deleted (a freshly created catalog references nothing)
```ada
         Clean_Directory (Result, Staging_Path (Result), False);
         Clean_Directory (Result, Objects_Path (Result), True);
```
```ada
            if not Check_References
              or else not Is_Payload_Name (Name)
              or else not Catalogs.Payload_Referenced (Item.Catalog, Name)
            then
               Ada.Directories.Delete_File
                 (Ada.Directories.Full_Name (Directory_Entry));
            end if;
```

Documented contract, `docs/architecture/files-layout.md:3-4,66`
```
The files backend requires exclusive ownership of its configured root by one
process. ...
... opening the exclusively owned root removes interrupted staging
```
and `server/README.md:64`, which documents the variable without the
precondition:
```
- `FLYOLOGY_OBJECT_STORAGE_ROOT` is mandatory for files and SQLite.
```
Neither `Open` looks for a layout marker (the files root has none; the SQLite
root's `catalog.sqlite3` and `.flyology-object-storage.lock` are created, not
required), and neither refuses a non-empty directory that lacks the layout.

**Failure scenario:**

1. An operator starts the executable with
   `FLYOLOGY_OBJECT_STORAGE_BACKEND=files FLYOLOGY_OBJECT_STORAGE_ROOT=/var`
   (a typo for `/var/lib/flyology`, or any directory that already has a `tmp`
   child: a checkout with `tmp/`, a home directory with `~/tmp`). On Linux
   `/var/tmp` is a plain directory; on macOS `/tmp` and `/var` are symlinks and
   are refused, so the macOS test host does not show the failure.
2. `Configuration.Load` accepts the value (`:42-46`); the credential bootstrap
   creates `/var/admin.credentials` (`configuration.adb:52-53`).
3. `Files.Open ("/var")`: the root exists and is a directory; `buckets/` is
   created; `/var/tmp` exists, is a directory and is not a symlink;
   `Validate_Tree_Symlink_Free` succeeds when nothing inside is a symlink or
   special file; `Delete_Tree ("/var/tmp")` removes every file and
   subdirectory. Running as root the tree is gone and the server prints
   `READY`; running unprivileged, `Delete_Tree` removes the caller's own
   entries until the sticky bit refuses a foreign one, raises, and `Open`
   reports `Configuration_Error` after the partial deletion.
4. SQLite variant: a root that already has `staging/` loses every ordinary
   file in it, and one that already has `objects/` loses every ordinary file
   there that is not a payload name referenced by the brand-new catalog.

The data destroyed is never the store's own acknowledged writes (a
correctly configured root is exclusively owned, and the sweep is documented
there), which is why this is P2 rather than P0; the defect is that the
executable's documented configuration surface accepts any directory and no
layer detects that the directory is not a store.

**Reproduction test sketch:** requires a files-backend directory (the memory
backend and the in-process harness cannot show it).
```sh
mkdir -p /tmp/x/tmp && echo keep > /tmp/x/tmp/keep
FLYOLOGY_OBJECT_STORAGE_BACKEND=files FLYOLOGY_OBJECT_STORAGE_ROOT=/tmp/x \
AWS_ACCESS_KEY_ID=a AWS_SECRET_ACCESS_KEY=b FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0 \
FLYOLOGY_ADMIN_CREDENTIALS_FILE=/tmp/x-admin ./bin/flyology_object_storage_server
```
Expected (correct): startup refuses a root that is not a recognised store
layout, or at least leaves `/tmp/x/tmp/keep` in place. Actual: `READY` is
printed and `/tmp/x/tmp/keep` no longer exists. SQLite:
`mkdir -p /tmp/y/objects && echo keep > /tmp/y/objects/keep`, start with
`FLYOLOGY_OBJECT_STORAGE_BACKEND=sqlite FLYOLOGY_OBJECT_STORAGE_ROOT=/tmp/y`;
actual: `keep` is deleted at `Open`.

**Existing coverage:** `server/tests/scripts/test.sh:458-471` always uses a
fresh `$RUN_ROOT/<backend>-store`; the fault and process corpora under
`tests/src/` and `sqlite/tests/src/` reopen roots they created. No test points
a store at a directory containing foreign content.

**Refutation attempts:**
- Looked for a layout marker or emptiness check in `Files.Open`
  (`files.adb:3514-3567`) and `SQLite.Open` (`sqlite.adb:280-315`): both check
  only symlink/directory kind of the root itself.
- Checked whether `Validate_Tree_Symlink_Free` protects foreign trees: it
  refuses only trees containing symlinks or special files, so a directory of
  ordinary files is deleted.
- Checked whether the documentation makes the precondition part of the
  executable's contract: `files-layout.md:3` states exclusive ownership and
  `README.md:36` "one process owning an exclusive storage root", but
  `server/README.md:64,86-93` documents the variable and the `/srv/...`
  example without saying the directory must be dedicated; no code enforces
  it. Recorded as a finding rather than a policy observation because the
  consequence is deletion of unrelated data through one documented variable.
- Confirmed the credential file itself is not at risk: the default
  `<root>/admin.credentials` (`configuration.adb:52-53`) sits beside
  `buckets/`, `tmp/`, `objects/`, `staging/` and is not swept.

---

### SERVER-EXE-4: Supervisor termination diagnostics are discarded: a listener bind failure or exhausted recovery prints only the outcome name

**Location:** `server/src/flyology_object_storage_server_runtime.adb:1074-1081`
(result reporting), `:216-220` and `:922-925` (listener binds that raise out
of a generation), `:984-996` (`On_Failure` restart policy).

**Severity:** P2 (wrong diagnostics on a valid and common input: a port
already in use). **Confidence:** High.

**Evidence:**

`server/src/flyology_object_storage_server_runtime.adb:1074-1081` — only the
outcome enumeral is printed
```ada
   Supervisors.Run (Supervisor, Context, Result);
   Flyology_Object_Storage_Server_Signals.Complete;
   if Result.Outcome /= Flyology.Supervision.Shutdown_Completed then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "object-storage server stopped: " & Result.Outcome'Image);
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
```

`server/src/flyology_object_storage_server_runtime.adb:922-925` — the
management bind has no handler; `Socket_Error` escapes the generation
```ada
      Sockets.Bind_Socket
        (Listener, Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Configuration.Admin_Port));
      Sockets.Listen_Socket (Listener, Length => 64);
```

What the supervisor hands back, `flyology` 0.1.1
`src/flyology-supervision.ads:167-177,405-411`
```ada
   type Termination_Summary is record
      Kind                     : Termination_Kind := No_Termination;
      Exception_Id             : Ada.Exceptions.Exception_Id := Ada.Exceptions.Null_Id;
      Exception_Name_Length    : Supervision.Exception_Name_Length := 0;
      Exception_Name_Truncated : Boolean := False;
      Exception_Name           : String (1 .. Maximum_Exception_Name_Length) := (others => ' ');
      Task_Id                  : Ada.Task_Identification.Task_Id := Ada.Task_Identification.Null_Task_Id;
      Message_Length           : Diagnostic_Length := 0;
      Message_Truncated        : Boolean := False;
      Message                  : String (1 .. Maximum_Diagnostic_Length) := (others => ' ');
   end record;
```
```ada
   type Supervisor_Result is record
      Outcome     : Supervisor_Outcome := Shutdown_Completed;
      Child       : Child_Id := Child_Id'First;
      Generation  : Supervision.Generation := Supervision.Generation'First;
      Termination : Termination_Summary;
      Incident    : Incident_Context := No_Incident;
   end record;
```
(`Maximum_Diagnostic_Length` is 512, `:142`.) The static supervisor stores
the child's termination before ending the run,
`src/flyology-supervision-static.adb:750-752`
```ada
         elsif Phase = Starting_Children then
            Active_Incident := Incident;
            Begin_Terminal_Stop (Startup_Failed, Child, Snapshots (Child).Termination);
```
Nothing in `flyology-supervision*.adb` prints (`rg -n 'Put_Line' ` over those
bodies: no match), and an exception escaping a generation task is captured
by the runtime termination hook (`flyology-task_results.adb:88`) rather than
reaching GNAT's unhandled-exception reporter, so no other layer names the
cause. Generation restarts under `On_Failure` (`:984`) are equally silent:
the only trace is a repeated `READY` line from `:224-229` / `:929-931`.

**Failure scenario:**

1. Another process holds `127.0.0.1:9001` (or the operator sets
   `FLYOLOGY_ADMIN_PORT` equal to `FLYOLOGY_S3_PORT` with the default bind).
2. The S3 child binds and prints `READY s3 ...`; the management child's
   `Bind_Socket` at `:922` raises `Socket_Error`; the generation terminates
   with `Unhandled_Exception` while the supervisor is in `Starting_Children`,
   so the run ends `Startup_Failed` (`static.adb:750-752`) and the S3 child is
   stopped.
3. The executable prints exactly `object-storage server stopped:
   STARTUP_FAILED` and exits 1. The operator is not told which child failed,
   which address and port were involved, or that the exception was
   `FLYOLOGY.IO.SOCKETS.SOCKET_ERROR` with the OS text the summary carries.
4. The same shape applies to `Recovery_Exhausted` after repeated S3-child
   failures (each restart silent, `Restart_Dependents` also restarting the
   management child) and to `Failure_Escalated`.

**Reproduction test sketch:** a real process is required (the in-process
harness has no supervisor). Hold a loopback port, e.g.
`python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(); print(s.getsockname()[1], flush=True); time.sleep(60)' &`,
then run `FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=$P ./bin/flyology_object_storage_server`.
Expected (correct): stderr names the management child, the endpoint
`127.0.0.1:$P`, and the socket error text before the non-zero exit. Actual:
one line `object-storage server stopped: STARTUP_FAILED`.

**Existing coverage:** `server/tests/scripts/test.sh:343-385`
(`expect_startup_failure`) asserts only a non-zero exit, and every case it
runs fails before the supervisor starts (configuration, assets), where
`server.adb:92-99` does print `Exception_Information`. No test provokes a
child-generation failure or asserts any diagnostic text after `Run`.

**Refutation attempts:**
- Checked whether `Exception_Information` reaches stderr through
  `server.adb:92-99`: `Runtime` catches everything at `:1082-1089` and returns
  normally, so main's handler is not involved for supervisor outcomes.
- Checked whether the supervisor or the generation runner prints or re-raises:
  no `Put_Line` in the supervision bodies; the termination is copied into
  `Termination_Summary` and the run returns normally.
- Checked whether `Configuration.Load` rejects equal ports or a busy port:
  it does neither (`:67-70`), so the supervisor path is the first place the
  conflict is observed.

---

## Areas reviewed with no findings

- `flyology_object_storage_server_credentials_native.c`: CSPRNG source
  (`arc4random_buf` / `getrandom` with EINTR retry), 24 random bytes → 48
  hex characters (192 bits), 32-byte random salt; temp file created with
  `O_WRONLY|O_CREAT|O_EXCL, 0600` before any write, full write + `fsync`,
  `link()` publication that never replaces an existing name (EEXIST → caller
  reloads the racing process's file), parent-directory `fsync`, and a
  distinct status when only cleanup failed so the password is still revealed.
- `Secure_File`: `lstat` (symlinks and directories rejected as non-regular),
  effective-uid ownership check, exact `0600` mode; TOCTOU between the check
  and `Ada.Text_IO.Open` needs directory write access by an attacker, who
  could equally pre-create the file (which then fails the uid check).
- `Load` format parsing: fixed 160-character single line, `File_Prefix`
  pinning the version, username, and iteration count; lowercase-hex-only
  decoding; more than one line rejected; GNAT 15.3.1 `Index` (Forward) with
  `From` past the end returns 0 through a null slice and raises `Index_Error`
  only for `From < Source'First` (`a-strsea.adb:610-621`), so short lines hit
  the length check rather than `Index_Error`.
- PBKDF2-HMAC-SHA256 `Derive` (single block, `INT(1)` big-endian, XOR chain)
  and the iteration-1 self-test vector `120fb6cf…0be17b`, which equals
  `hashlib.pbkdf2_hmac('sha256', b'password', b'salt', 1, 32)` (verified with
  `python3` in this review); `File_Prefix` is 31 characters so the 160-column
  format check is exact; constant-time
  comparisons for verifier and session tokens; work factor 600,000 matches
  the OWASP figure cited by the README.
- Plaintext lifetime: `Password`, `Password_Bytes`, `Salt`, `Derived`, `U`,
  `Next`, `Candidate`, the HMAC context and session `Token` are all wiped on
  normal and exceptional paths; the password is printed exactly once, only
  when `Generated`, only to standard error (`server.adb:31-42`), and no other
  `Put_Line` in `server/src`, `src/flyology-object_storage-server*.adb`, or
  the HTTP server library prints request material. The reload run in
  `test.sh:558` asserts no second `BOOTSTRAP ADMIN` line.
- `Load_Or_Bootstrap` ordering with a racing process, a dangling symlink at
  the path (`Exists` false → `link` EEXIST → reload → `lstat` rejects), a
  directory at the path, and a missing parent (`Create_Path`).
- Sessions: 32 random bytes → 64 hex (256 bits); 12-hour absolute expiry;
  slot reuse only of unoccupied/expired entries with oldest-expiry eviction
  when all 64 are live; `Revoke` wipes; single `Cookie` header required and
  duplicate `flyology_admin` pairs fail closed (asserted by `test.sh:223-232`).
- Cookie attributes: `HttpOnly; SameSite=Strict; Path=/; Max-Age=43200`, no
  `Secure` (documented, loopback HTTP only); logout emits `Max-Age=0`
  (`test.sh:119-120,237-238`).
- CSRF/rebinding: `Local_Request` compares the parsed request authority
  (absolute-form target or `Host`, `applications.ads:109-113`) with the exact
  bound loopback authority; mutations require an exact `Origin`; login and
  logout accept an absent `Origin` (non-browser clients) but reject a
  mismatching one; `SameSite=Strict` prevents cross-site cookie attachment.
- Authorisation: every `/api/*` route checks `Local_Request` and
  `Authenticated` (or `Same_Origin`/`Strict_Same_Origin`) before touching the
  backend; assets and `/` check `Local_Request` only.
- Asset serving: three fixed routes, no path parameter, contents read once at
  startup and SHA-256 pinned against compiled digests (the three pinned
  digests equal the SHA-256 of the shipped files byte-for-byte, so the
  `Read_All` normalisation is an identity for the current assets); `FLYOLOGY_ADMIN_ASSET_ROOT`
  cannot change what is served, only where it is read from; tamper
  rejection asserted by `test.sh:376-384`.
- Response headers: `Cache-Control: no-store`, `X-Content-Type-Options:
  nosniff`, CSP `default-src 'self'; object-src 'none'; base-uri 'none';
  frame-ancestors 'none'; form-action 'self'`, `X-Frame-Options: DENY`,
  `Referrer-Policy: no-referrer`, `Cross-Origin-Resource-Policy: same-origin`
  on every handler response; JSON bodies escape `"`/`\` and map control
  characters; object keys are emitted URI-encoded; `app.js` uses
  `textContent` only (no `innerHTML`), so no server- or client-side HTML
  injection path exists for bucket names or keys.
- Error responses: fixed JSON error tokens, a fixed 421 text; no paths or
  exception text reach the client.
- Body bounds: login 256 bytes, create/delete 68 bytes, GET routes reject
  bodies (`Default_Route_Policy`), 4 KiB shared ingress budget, 30-second
  request and 5-second header timeouts on the management listener.
- Configuration: backend name lower-cased and closed; root required for
  files/SQLite and validated by the backends (`Files.Open` rejects a symlink
  or non-directory root; `SQLite.Open` acquires a root lock); bind address
  must be numeric IPv4 (hostnames rejected, `test.sh:367-369`); ports via
  `Port'Value` range 0..65535; capacity 1..4096; AWS credentials required
  as a complete non-empty pair with the session token only alongside them;
  region length- and scope-segment-validated. The management listener is
  hard-bound to `Loopback_IPv4` (`runtime.adb:922-924`) and no option can
  move it; the S3 bind address is configurable and documented as such.
- Signals and lifecycle: SIGTERM handler is a protected `Attach_Handler`
  that only latches a flag; a stop latched before `Supervisors.Run` is sticky
  (`static.ads:102-104`); the supervisor stops the dependent management child
  first, each child stops accepting and drains (2 s / 10 s) before forced
  cancellation; grace 12 s exceeds the drain; `Shutdown_Completed` yields
  exit 0 (asserted by `test.sh` through `wait` under `set -e`); any other
  outcome or exception sets a failure exit status; the files/SQLite `Store`
  is a block-local object finalised after `Run` returns on every path; the
  SQLite root lock is an OS lock released on process death
  (`docs/architecture/sqlite-backend.md:151-156`). SIGPIPE is suppressed at
  the socket layer (`native/flyology_sockets.c:31-32,166-169,362`).
- Restart behaviour: `On_Failure` with bounded default recovery limits (3 per
  5 s, 10 per incident, 60 s), so a port already in use ends in
  `Startup_Failed`/`Recovery_Exhausted` rather than an infinite loop (the
  missing cause text is SERVER-EXE-4); `Structured_Servers.Serve` always
  closes the transferred listener.
- Shutdown classification: `Static.Request_Stop` (`static.adb:823-851`) moves
  the phase to `Stopping_Children` at once and fixes the terminal outcome at
  `Shutdown_Completed`; every later generation termination, whatever its
  `Kind`, only advances the stop order (`static.adb:741-742`). So a SIGTERM
  during startup (including the window where `Mark_Ready` would raise
  `Program_Error` "after stopping begins", `supervision.ads:304-309`) and a
  deferred `Server_Failed` raised by `Structured_Servers.Serve` at stop
  (`structured_servers.adb:536`) both end with exit status 0. This closes the
  question the earlier pass left open.
- Handler exception containment: `Routing.Serve` answers any escaping
  management-handler exception with a plain 500 and keeps the connection
  loop (`routing.adb:2264-2276`); `Connection_Handlers.Serve` absorbs
  transport, timeout, payload and protocol exceptions around both the read
  and the `Handle` call (`connection_handlers.adb:99-142`); the S3
  application's `Handle` ends in a `when others` that answers 500
  `InternalError` or marks a started response failed
  (`s3_applications.adb:18055-18066`). Only `Operation_Cancelled` reaches
  `Structured_Servers`, where it is counted as cancelled, not failed
  (`structured_servers.adb:452-458`); `Server_Failed` is therefore not
  reachable from S3 or management traffic.
- Continuation tokens: `Core.Valid_Listing_Continuation_Syntax`
  (`core.adb:8-24`) enforces a 70-character minimum, an even remainder and a
  maximum before `Decode_Continuation` indexes `Raw (Digest_Last + 1)` or
  computes the `Natural` hex length (`listings.adb:338-347`), so the `token`
  query parameter cannot raise.
- Credential path versus store layout: buckets live under `<root>/buckets/`
  and staging under `<root>/tmp/` (files) or `<root>/objects/`,
  `<root>/staging/`, `catalog.sqlite3`, `.flyology-object-storage.lock`
  (SQLite), so the default `<root>/admin.credentials` is neither enumerated as
  a bucket nor swept at `Open`.
- SQLite root lock: `flock(LOCK_EX | LOCK_NB)` on a persistent lock inode
  (`flyology_object_storage_sqlite_durability.c:77`, `sqlite.adb:105-125`),
  released by the kernel on any exit, so a crash leaves no stale lock and the
  next start succeeds.
- Same-site cookies: because `SameSite` treats every port of `127.0.0.1` as
  one site, a page on another loopback port can attach the session cookie to
  cross-origin requests; mutations require an exact `Origin`
  (`Strict_Same_Origin`), logout and login reject a mismatching `Origin`
  (browsers always send one on cross-origin `POST`), and the GET inventory
  routes are unreadable cross-origin (no CORS headers,
  `Cross-Origin-Resource-Policy: same-origin`, `nosniff`).

## Observations not counted

- Policy values: memory store `Bucket_Capacity 256 / Object_Capacity 100_000 /
  Byte_Capacity 16 GiB` (`server.adb:52-54`), S3 handler timeout 60 s,
  10,000 requests and 600 s per connection, management capacity 32, session
  capacity 64 and 12 h, bucket inventory 256, object page 64/128, drain 10 s
  / 2 s, grace 12 s, readiness 15 s, ingress budget 4 KiB, clock skew 900 s,
  torrent piece 256 KiB.
- `Assets.Read_All` rebuilds files through `Ada.Text_IO.Get_Line`, so the
  pinned digest is over a normalised image: a missing final newline is added
  and one trailing empty line is dropped (GNAT 15.3.1 `End_Of_File` treats
  `LF EOF` and `LF FF EOF` as end of file, `a-textio.adb:311-365`). Only trailing
  whitespace of an asset can differ from the pinned bytes; the served bytes
  equal the digested bytes, so integrity of executable content is intact.
- Main's `exception when others` (`server.adb:92-99`) does not cover
  exceptions raised in its declarative part, so a `Configuration.Load`
  rejection is reported by the GNAT unhandled-exception message rather than
  the `"object-storage server startup failed:"` prefix; exit status is still
  non-zero (what `test.sh:343-353` asserts). Within `Load`, a non-numeric or
  out-of-range `FLYOLOGY_S3_PORT`, `FLYOLOGY_ADMIN_PORT` or
  `FLYOLOGY_S3_CAPACITY` is re-raised with GNAT's `'Value`/range-check text
  rather than a variable name (`configuration.adb:67-72,91-93`), and based or
  underscored literals (`16#2328#`, `9_000`) are accepted. Fail-closed,
  cosmetic.
- A zero-length credential file (only an operator can produce one; `Publish`
  never links an incomplete file) fails startup with `End_Error` from
  `Get_Line` instead of "invalid administrator credential file"; a directory
  at the path is reported as "must be owner-owned mode 0600". Fail-closed
  either way.
- `umask` bits in the owner triple (e.g. `0277`) make `open(..., 0600)`
  create a `0400` file that the next startup rejects as not `0600`; likewise
  an operator `chmod 400` of the credential file stops the next start
  (`credentials_native.c:154` requires exactly `0600`). Documented behaviour
  is owner-only `0600`; fail-closed.
- `link(2)` publication fails on filesystems without hard links (some FAT,
  exFAT, and network mounts) with "could not publish administrator credential
  file"; a stale `<path>.tmp.<pid>` from a crashed process with a reused PID
  produces the same failure. Both fail closed.
- Password and secret copies survive on the secondary stack (`Hex` result,
  the `"BOOTSTRAP ... password=" & Password` concatenation, the `Set-Cookie`
  header string) after the named buffers are wiped; no reachable path exposes
  them.
- Bootstrap ordering: the admin credential is created and printed before the
  backend opens and before listeners bind (`server.adb:28-43` vs `:45-91`),
  so a later configuration or bind failure leaves a persisted credential whose
  password was shown once; commit `4401e0e` already isolates this in tests.
- `Local_Request` is a textual authority comparison: `Host: localhost:9001`
  or, on port 80, `Host: 127.0.0.1:80` receive 421; browsers follow the
  printed `http://127.0.0.1:<port>/` and omit the default port, so only
  hand-typed URLs are affected.
- With `FLYOLOGY_S3_BIND=0.0.0.0`, `SO_REUSEADDR` on the S3 listener lets
  another local user on BSD-derived kernels (macOS) bind `127.0.0.1:9000`
  more specifically and receive loopback connections; Linux refuses while the
  wildcard socket listens. Multi-user hosts with a non-default bind only;
  the loopback-bound default and the management listener are the most
  specific binds and are not affected.
- The files backend has no root lock: two executables pointed at the same
  files root both start (README line 36 states the exclusive-owner
  precondition; `Files.Open` does not enforce it), and the second `Open`
  performs the `tmp/` sweep of SERVER-EXE-3 on the first instance's live
  staging. Deferred to the FILES area; the SQLite backend refuses the second
  process through its `flock`.
- `server/README.md:72-73` says the credential file defaults to
  `./flyology-admin.credentials` "for memory", but `Configuration.Load:47-54`
  uses `<root>/admin.credentials` whenever `FLYOLOGY_OBJECT_STORAGE_ROOT` is
  set, including with the memory backend. Documentation drift only.
- `Status` reports `s3_address` as bound (e.g. `0.0.0.0`), and `app.js:157`
  renders `http://0.0.0.0:<port>` as the copyable endpoint. Cosmetic.
- `Run_S3` does not close `Listener` when `Bind_Socket`/`Listen_Socket`
  raise before `Serve` takes ownership; the descriptor leaks once per failed
  generation, bounded by the recovery limits (at most 10).
- Second SIGTERM, SIGINT, and SIGHUP: a second SIGTERM re-latches the flag
  (no forced exit); SIGINT/SIGHUP take the default action and terminate
  without drain. Backends are crash-safe by design; README documents only
  SIGTERM.
- Stop policy `Request_Abort => False` with `Grace` 12 s (`runtime.adb:989-992`):
  a handler that ignores cancellation for longer than the grace is classified
  `Stop_Timeout` then `Stuck`, and `Supervisors.Run` "cannot return while the
  task is still alive" (`supervision.ads:400-402`), so the process would not
  exit on SIGTERM. No reachable handler was found that blocks that long (the
  PBKDF2 derivation of SERVER-EXE-1 is far shorter; backend I/O observes the
  token); a wedged disk is the only scenario, outside the executable's
  control.
- S3 request deadline: `Handlers.Serve (Timeout => 60.0)` is a monotonic
  deadline for each complete request including the streamed body
  (`connection_handlers.ads:20`, `flyology-http-server.ads:474-475`), so a
  single-request upload or download that needs more than 60 s over the
  configured `FLYOLOGY_S3_BIND` link is cut; multipart clients (aws-cli 8 MiB,
  s5cmd 50 MiB parts) are unaffected. The in-tree harness uses the same value
  (`tests/src/s3_server_harness.adb:98-104`), so this is a consistent policy
  value, not drift.
- During the 10-second S3 drain only admission stops; keep-alive connections
  keep serving requests until forced cancellation (`structured_servers.ads:100-105`),
  which then cuts an in-flight request without acknowledging it. Consistent
  with the README's "allows a ten-second S3 drain".
- Coverage gap: `.github/workflows/ci.yml:271,301` are the only references to
  a server in the workflow and both concern `tests/scripts/`; the server crate
  is neither built nor tested in CI (`server/tests/scripts/test.sh` runs only
  under a local `alr test`), so the lightweight handler configuration, the
  management API, the credential bootstrap, and the SIGTERM path are gated
  only when run locally.
- `test.sh` does not cover: concurrent logins or S3 traffic during login
  (SERVER-EXE-1), any 429/503 (SERVER-EXE-2), a root that already contains
  `tmp/`, `staging/` or `objects/` content (SERVER-EXE-3), a busy or
  duplicated port and the resulting diagnostic (SERVER-EXE-4), a credential
  file with a foreign owner, a symlink, a directory, or zero length (only
  `0644` is tested, through the corpus at `:451-455`), a root that is a file
  or symlink, `FLYOLOGY_S3_BIND` other than the default, `AWS_SESSION_TOKEN`
  with the complete pair, `AWS_REGION` other than `us-east-1`, session
  expiry, session-slot eviction, ingress-budget exhaustion, a second SIGTERM,
  an S3 upload in flight at SIGTERM, a SIGTERM before readiness, the
  `FLYOLOGY_LOOP_POOL_SIZE` variable, or the exit status after a child
  failure. The reload run (`:521-560`) asserts only login and status, not
  that objects written before the restart are still listed.
- Management continuation tokens: `Listings.Decode_Continuation`
  (`src/flyology-object_storage-s3-listings.adb:329-376`) returns
  `Valid => False` for malformed input and contains no `raise`, so
  `Object_Inventory` cannot be made to escape an exception through the
  `token` parameter (asserted for one input by `test.sh:280-284`).
- Bootstrapped S3 secret: with `AWS_ACCESS_KEY_ID` absent the executable
  prints `BOOTSTRAP S3 access_key=FLYOLOGYLOCAL secret_key=<64 hex>` to
  standard error on every start (`runtime.adb:1063-1072`), as the README
  documents; the `S3_Secret_Key` constant (`:83-85`) is retained unwiped for
  the process lifetime in addition to the provider's wiped copy.
- `Static_Credentials.Create` rejects a malformed key pair with fixed
  messages (`static_credentials.adb:39,46`) that do not echo the values, so the
  `startup failed` line cannot leak a secret.
- `Mark_Ready` after a stop request raises `Program_Error`
  (`supervision.ads:304-309`); reachable only by a SIGTERM in the milliseconds
  between a child's bind and its readiness call. The generation ends with an
  unlogged exception, the listener descriptor is not closed, and the process
  exits 0 (see the shutdown-classification entry above). Harmless.
- Handler exceptions during shutdown: resolved above — the supervisor's
  stop-phase classification keeps `Shutdown_Completed`, and no reachable
  handler exception escapes to `Structured_Servers` in the first place.
