# Adversarial verification: server executable (SERVER-EXE)

Scope verified by reading: `server/src/flyology_object_storage_server.adb`,
`server/src/flyology_object_storage_server_configuration.adb`,
`server/src/flyology_object_storage_server_credentials.adb`,
`server/src/flyology_object_storage_server_runtime.adb`,
`server/src/flyology_object_storage_server_assets.adb`,
`server/README.md`, `server/alire.toml`, `server/alire/build_hash_inputs`,
`server/tests/scripts/test.sh`, `.github/workflows/ci.yml`,
`src/flyology-object_storage-backends-files.ads` and `.adb:355-405,3514-3570`,
`src/flyology-object_storage.ads:39-`, `docs/architecture/files-layout.md`,
and the pinned dependency sources
`/Users/yrashk/.local/share/alire/builds/flyology_0.1.1_7be049fc/5e4ec5d2d7fb582d5512843a434aaaa816073423e6241e0ce95898ea1d152ad2/src/platform/darwin/flyology.ads`,
`.../src/flyology-execution_groups.ads:130-175`,
`/Users/yrashk/.local/share/alire/builds/flyology_http_0.1.3_537edbc5/661c5a9c55c739267d3a551b9656bff46ed477e22bf132d032c0fbeed94f5ec3/src/flyology-http-server-routing.ads:81-100`,
`.../src/flyology-http-server-middleware_rate_limits.ads`.

Harness programs added: `tests/repros/shell/repro_server_exe_1.sh`,
`tests/repros/shell/repro_server_exe_2.sh`,
`tests/repros/src/repro_server_exe_3.adb`,
`tests/repros/shell/repro_server_exe_3_server.sh`,
`tests/repros/shell/repro_server_exe_4.sh`,
`tests/repros/shell/repro_server_exe_5.sh`.
Nothing tracked was modified (`git status --short` shows only the untracked
`review/`, `tests/repros/` and `sqlite/tests/repros/` trees).

**Server build** (the one build this area was authorised to run, taken while
holding `tests/repros/.build.lock`, released immediately afterwards):
`cd server && alr -n build` → **exit 0, 47 s wall** (`alr` itself reports
"Build finished successfully in 46.26 seconds"). Log:
`review/baseline/server-build.log`. Binary:
`server/bin/flyology_object_storage_server` (28.1 MB). Build profile
`DEVELOPMENT` with `-Og` (`server/alire/build_hash_inputs`) — the crate's own
default for `alr -n build`, and the profile every timing number below was
measured under.

**Measurement conditions** (recorded per the repository's performance-testing
rule). Host: Apple M3 Max, macOS 25.6.0, on AC power, `pmset -g` reports
`powermode 0` (normal, not low-power) and `pmset -g therm` records no thermal
or performance warning. Load average at the time was 12.3 (other review agents
were building concurrently); every baseline and its comparison were taken
back-to-back on that same host under the same profile, and the effects
reported are 300–3400x, far outside load noise.

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| SERVER-EXE-1 | CONFIRMED | P1 (P1) | `tests/repros/shell/repro_server_exe_1.sh` |
| SERVER-EXE-2 | CONFIRMED | P2 (P2) | `tests/repros/shell/repro_server_exe_2.sh` |
| SERVER-EXE-3 | CONFIRMED | P2 (P2) | `tests/repros/src/repro_server_exe_3.adb`, `tests/repros/shell/repro_server_exe_3_server.sh` |
| SERVER-EXE-4 | CONFIRMED | P2 (P2) | `tests/repros/shell/repro_server_exe_4.sh` |
| SERVER-EXE-5 | CONFIRMED (new) | P2 (—) | `tests/repros/shell/repro_server_exe_5.sh` |

---

### SERVER-EXE-1: administrator login runs 600,000 PBKDF2 iterations on the shared cooperative event loop and stalls the S3 listener

**Verdict:** CONFIRMED, and measured. A signed S3 request issued 0.15 s into a
single valid administrator login takes **0.771–0.876 s** against a baseline of
**0.002–0.003 s** — a factor of ~350. One login costs **0.99–1.07 s** of CPU.
Ten simultaneous logins starve one S3 request for **10.2 s**; fifty starve the
management listener for **51 s** and cause 1–3 of the 50 connections to be
closed with no response at all.

**Severity:** P1 (discovery said P1; unchanged). The single-login case is a
wrong result on valid input via a reachable path with the default
configuration, which is P1. It is not P0: the stall terminates (it is
starvation, not a hang or deadlock), it does not fall into any of the P0
security categories (no signature bypass, traversal, credential exposure or
authorisation bypass), and the unbounded-starvation variant needs a local
process that can reach the loopback-only management port.

Verified by reading:

- `server/src/flyology_object_storage_server_runtime.adb:187-190` — the S3
  listener instantiates `Flyology.IO.Structured_Servers` with
  `Handler_Model => Flyology.Lightweight_Task`.
- `server/src/flyology_object_storage_server_runtime.adb:853-858` — the
  management listener does the same, `Server : aliased Structured.Server
  (Capacity => 32)`.
- `.../flyology_0.1.1_.../src/platform/darwin/flyology.ads:21-26` —
  "Run the task cooperatively on an event loop … Ada reserves CPU 0 as
  `Not_A_Specific_CPU`, so it selects the configured pool exactly as an absent
  aspect does." Neither listener sets a `Handler_CPU`, so both land in the
  automatic pool.
- `.../src/flyology-execution_groups.ads:154-158` — `Configured_Pool_Size`
  "defaults to one when absent"; `rg 'Grow_Configured_Pool'` over `server/`,
  `src/`, `sqlite/`, `tests/` finds no call site.
- `server/src/flyology_object_storage_server_runtime.adb:432-441` — `Login`
  calls `Admin_Credentials.Verify` inline in the handler.
- `server/src/flyology_object_storage_server_credentials.adb:16` —
  `Work_Factor : constant Positive := 600_000;` — and `:134-145`, the
  derivation loop: no `delay`, no I/O, no `Cancellation.Requested` poll.
- `server/src/flyology_object_storage_server_credentials.adb:325-344` —
  `Verify` derives first and then compares in constant time, so a wrong
  password costs the same as a right one (measured: 0.994 s for a wrong
  password).

Refutation attempts that failed:

- *Maybe the login route rejects a wrong password before deriving.* It does
  reject a wrong `User` and a `Password'Length` outside `1 .. 64` first
  (`credentials.adb:329-333`), but `Login` only reaches `Verify` with a
  48-character password, so every attempt pays the full cost. Measured a
  wrong-password login at 0.994 s.
- *Maybe the two listeners are on different execution groups.* Both use the
  default `Handler_CPU`, so both are placed by the same automatic pool.
- *Maybe the pool is larger than one by default.* I raised it explicitly with
  `FLYOLOGY_LOOP_POOL_SIZE=8` and re-measured: a **single** concurrent login
  then costs the S3 probe nothing (0.002 s), but **ten** concurrent logins
  still stall an S3 request for **0.774 s**, and the flood's wall time falls
  from 10.5 s to 2.13 s. So the pool size only raises the number of
  simultaneous derivations needed to starve the loop from one to the pool
  size; it does not remove the coupling. The executable never grows the pool,
  the variable is not mentioned in `server/README.md`, and
  `server/tests/scripts/test.sh:388-392,462-471` launch the server with
  `env -i`, so the shipped default is one.
- *Maybe it is documented.* `server/README.md:8-12` couples the two listeners
  only through supervision order ("The management child depends on the S3
  child, so an S3 generation failure restarts the workbench generation as
  well"). No document says a workbench sign-in pauses S3 service.
- *Maybe an existing test would catch it.* `server/tests/scripts/test.sh`
  issues its three logins sequentially with `sleep 1` between them and never
  runs S3 traffic concurrently with a login.

**Repro:** `tests/repros/shell/repro_server_exe_1.sh`. It starts the server
itself on a fresh temporary root under `/private/tmp/claude-501/` with
`env -i`, `FLYOLOGY_S3_PORT=0 FLYOLOGY_ADMIN_PORT=0` and the memory backend,
reads the two `READY` ports and the `BOOTSTRAP ADMIN` password from the
server's own output, then times three signed SigV4 `ListBuckets` requests with
no other traffic, three logins on their own, and three signed S3 requests each
issued 0.15 s into a valid login (with a plain TCP connect alongside). It
fails when the worst concurrent S3 latency exceeds the stated threshold —
`max(10 x worst baseline, 0.050 s)`, the floor keeping sub-millisecond
scheduling noise from tripping the ratio — and it always stops the server.
The control re-issues the same signed request with no login in flight.

**Output** (`./tests/repros/shell/repro_server_exe_1.sh`, exit status **1**):

```
  -- s3 port 56076, management port 56077, loop pool = default (FLYOLOGY_LOOP_POOL_SIZE unset)
  -- baseline: signed S3 ListBuckets with no other traffic (3 runs)
     run 1: 0.002 200 184  (seconds status bytes)
     run 2: 0.002 200 184  (seconds status bytes)
     run 3: 0.002 200 184  (seconds status bytes)
  -- worst baseline S3 latency: 0.002s
  -- one management login on its own (3 runs)
     run 1: 1.001 200 {"authenticated":true}
     run 2: 1.067 200 {"authenticated":true}
     run 3: 1.074 200 {"authenticated":true}
  -- threshold for a concurrent S3 request: 0.05s (max of 10x baseline and 0.050 s)
  -- S3 request issued 0.15 s into a valid login (3 runs)
     run 1: s3=0.863 200 184  tcp-connect=0.001 connected  login=1.026 200 {"authenticated":true}
     run 2: s3=0.849 200 184  tcp-connect=0.001 connected  login=1.010 200 {"authenticated":true}
     run 3: s3=0.771 200 184  tcp-connect=0.001 connected  login=1.017 200 {"authenticated":true}
  -- worst S3 latency during a login: 0.863s
  FAILED: an S3 request issued during an administrator login stays within 0.05s
  -- control: S3 request after the logins: 0.002 200 184  (seconds status bytes)
  ok: control: with no login in flight the same signed S3 request is fast
BUG REPRODUCED: 1 failed expectation(s)
```

Supporting measurements taken by hand against the same binary (`ADMIN`/`S3`
are the ephemeral ports of one server instance):

```
--- 10 concurrent wrong-password logins; one signed S3 request at t+0.3 s ---
  t+1 s3=10.201 200 184        <- starved for the whole flood
  t+2 s3=0.002 200 184
  ...
  10 x 401   wall=10.50s min=1.10s median=6.40s max=10.50s   limited(429/503)=0

--- FLYOLOGY_LOOP_POOL_SIZE=8, same binary ---
  baseline                     0.002 200 184
  s3 during ONE login          0.002 200 184   (login=1.001 s)
  s3 during TEN logins         0.774 200 184   (flood wall=2.13 s)
```

Note that the plain TCP connect always completes in 0.001 s: the kernel's
accept queue absorbs the connection, so a health check that only opens a
socket will not see the outage — only a request that needs a response does.

**Description:** Both HTTP listeners run their handlers as Flyology
lightweight tasks, and with the shipped default of one shared execution group
every handler for both listeners is multiplexed onto a single event-loop
thread. `Login` performs a 600,000-iteration PBKDF2-HMAC-SHA256 derivation
inline in its handler; that loop contains no I/O, no delay and no
`Cancellation.Requested` poll, which is exactly the CPU-only case
`Structured_Servers` requires handlers to break up
(`flyology-io-structured_servers.ads:100-105`). The event loop therefore
cannot run any other handler for the ~1 s the derivation takes, so every
in-flight and newly accepted S3 request waits behind it. Anyone running the
server hits the one-second version on every workbench sign-in; the unbounded
version needs only a local process that can open the loopback management port
and post form bodies — no session, no credential, and no rate limit
(SERVER-EXE-2) — and it also drops connections outright once the queue
exceeds the 30 s request timeout (1–3 of 50 in the runs above). It is fully
deterministic. No existing test asserts S3 availability during a login
(`server/tests/scripts/test.sh:102-117` paces its logins with `sleep 1` and
runs its s5cmd slice before the logged-in inventory check), and nothing in CI
runs the lightweight handler model at all. A fix needs a maintainer decision
that this review cannot make on its own: either the derivation moves off the
cooperative loop (a `Flyology.Native_Task` handler model or an explicit
worker for password verification), or the loop is broken up with a
cooperative yield and a cancellation poll, or the executable grows the
automatic pool at startup — the last of which is a new public policy value
(a pool size) and would only raise the threshold, as the
`FLYOLOGY_LOOP_POOL_SIZE=8` measurement above shows.

---

### SERVER-EXE-2: management route `Concurrency`/`Rate_Per_Second` policies are inert

**Verdict:** CONFIRMED. Of 50 simultaneous `POST /api/login` attempts with a
wrong password, 47–49 were run to completion (each paying a full
600,000-iteration derivation) and answered `401`; **zero** received `429` or
`503`. The declared policy is `Concurrency => 1, Rate_Per_Second => 2`, whose
token bucket has a burst capacity equal to the rate, so at most 2 should have
been admitted.

**Severity:** P2 (discovery said P2; unchanged). The library explicitly calls
the consuming layers optional — `flyology-http-server-routing.ads:81`, "Route-
local policy consumed incrementally by **optional** toolkit layers" — so this
is not a violation of a library contract, and `server/README.md` promises no
rate limit. What is wrong is that the server declares admission policy on five
routes and never enforces it, and that `server/tests/scripts/test.sh` paces
itself as though the limit existed.

Verified by reading:

- `server/src/flyology_object_storage_server_runtime.adb:882-887` — the
  `/api/login` registration with `Concurrency => 1, Rate_Per_Second => 2`; the
  same shape on `/api/buckets` (GET and POST), `/api/objects`,
  `/api/buckets/delete` and `/api/logout` at `:888-918`.
- `server/src/flyology_object_storage_server_runtime.adb:846-850` — `Handle`
  calls `State.Routes.Serve` directly; `grep -rn -i
  'middleware|bulkhead|rate_limit' server/src/` returns nothing (exit 1).
- `.../flyology_http_0.1.3_.../src/flyology-http-server-routing.ads:81-89` —
  the policy fields and "A zero concurrency or rate value means unlimited".
- `.../src/flyology-http-server-middleware_rate_limits.ads:24-25` — "Token-
  bucket middleware. Burst capacity equals the configured route
  requests-per-second rate. Rejection is 429 with Retry-After."

Refutation attempts that failed:

- *Maybe the router enforces the policy itself.* No counter or bucket exists
  in `routing.adb` outside the middleware packages; `Configure_Route` only
  stores the values.
- *Maybe the burst just happened to fit under the limit.* The flood is
  barrier-synchronised, so all 50 requests are outstanding simultaneously;
  47–49 were nonetheless served.
- *Maybe the effective serialisation is equivalent.* It is not a limiter: the
  requests are serialised by the single event loop (SERVER-EXE-1), so all of
  them run and the burst takes ~51 s of CPU instead of being rejected in
  milliseconds.

**Repro:** `tests/repros/shell/repro_server_exe_2.sh`. Starts the server on a
temporary root, fires 50 barrier-synchronised `POST /api/login` requests with
a wrong 48-hex password from one peer, tallies the outcomes and `Retry-After`
headers, and asserts (a) some are rejected with 429/503 and (b) at most the
declared burst of 2 is admitted. Control: one wrong-password login on its own
is answered `401`, so the request shape is right and the flood measured real
handler work.

**Output** (`./tests/repros/shell/repro_server_exe_2.sh`, exit status **1**):

```
  -- management port 54524; declared policy on /api/login is Concurrency => 1, Rate_Per_Second => 2
  -- 50 simultaneous POST /api/login with a wrong 48-hex password:
      49 x 401
       1 x transport-error RemoteDisconnected
     wall=51.66s min=1.05s median=27.08s max=51.66s
  -- fully processed by a handler (200/401): 49; rejected by a limiter (429/503): 0
  FAILED: a per-client rate limit or bulkhead rejects some of 50 simultaneous logins with 429/503
  -- burst capacity of the declared policy is 2; observed admissions: 49 (wall 51.66s)
  FAILED: a simultaneous burst from one peer admits at most the declared burst of 2
  -- control: one wrong-password login on its own: 401 {"authenticated":false}
  ok: control: a single wrong-password login is answered 401
BUG REPRODUCED: 2 failed expectation(s)
```

(An earlier run of the same script with the same server showed `47 x 401` and
`3 x transport-error RemoteDisconnected`; the split between answered and
dropped connections varies, the zero limiter rejections do not.)

**Description:** Five management routes carry `Concurrency` and
`Rate_Per_Second` values, but the router is served with no middleware, so the
only readers of those fields — `Middleware_Rate_Limits` and
`Middleware_Bulkheads` — are never instantiated. Every management request from
every peer is therefore admitted up to the listener's 32 handler slots. On its
own this is a documentation-versus-code discrepancy; combined with
SERVER-EXE-1 it is what removes any admission bound from the expensive login
path, and it also means the `Concurrency => 1` intended to serialise bucket
create/delete is absent (the backends' own atomic primitives still make those
operations safe). Nothing in `server/tests/scripts/test.sh` asserts a 429 or
503; its `sleep 1` between mutating requests passes with or without the limit.
A fix needs a maintainer decision on the client key policy and the retained-key
capacity that `Middleware_Rate_Limits` takes as generic formals — both are new
externally visible resource choices.

---

### SERVER-EXE-3: any `FLYOLOGY_OBJECT_STORAGE_ROOT` is handed to `Files.Open`/`SQLite.Open`, which delete `<root>/tmp`, `<root>/staging` and unreferenced `<root>/objects` files with no layout check

**Verdict:** CONFIRMED at both levels — the backend `Open` and the executable's
documented environment variable. A directory containing an unrelated `tmp/`
tree loses that tree, and a directory containing `objects/` and `staging/`
loses their ordinary files, while the server prints `READY` and serves
normally.

**Severity:** P2 (discovery said P2; unchanged). The data destroyed is never
the store's own acknowledged writes, and it needs a root that is not a
dedicated directory, which the rubric puts at P2 ("edge-case incorrectness …
needing unusual input"). It is at the top of that band: the destruction is
silent, irreversible, and reached through one documented variable whose
documentation states no dedicated-directory precondition.

**Layout marker:** there is none. I read `docs/architecture/files-layout.md` in
full and grepped it for `marker|\.flyology|layout file|sentinel` — no match.
The document states the precondition on the operator ("The files backend
requires exclusive ownership of its configured root by one process", line 3;
"opening the exclusively owned root removes interrupted staging artifacts",
line 66) but defines no on-disk marker that `Open` could check, and
`server/README.md:64` documents the variable as "mandatory for files and
SQLite" without the precondition. The SQLite root's `catalog.sqlite3` and
`.flyology-object-storage.lock` are created, not required, so they are not a
marker either.

**Shared responsibility:** the destructive code belongs to the FILES and
SQLITE backends (`src/flyology-object_storage-backends-files.adb:3548-3564`;
`sqlite/src/flyology-object_storage-backends-sqlite.adb:304-305`); the
reachable path from a documented, unvalidated configuration variable belongs
to the executable
(`server/src/flyology_object_storage_server_configuration.adb:42-45` and
`server/src/flyology_object_storage_server.adb:64-68,78-82`). A fix could sit
in either layer — an `Open` that refuses a non-empty directory without a
layout marker, or an executable that validates the root before opening — and
choosing between them, plus choosing whether to introduce a marker file, is a
maintainer decision.

Verified by reading:

- `server/src/flyology_object_storage_server_configuration.adb:42-45` — the
  only check on the root is `Root'Length = 0` for non-memory backends.
- `server/src/flyology_object_storage_server.adb:64-68` — `Files.Open
  (US.To_String (Settings.Storage_Root))` with no further validation.
- `src/flyology-object_storage-backends-files.adb:3514-3573` (`Open`), and
  specifically `:3548-3564` — `Open` checks
  that the root is not a symlink and is a directory (creating it if absent),
  then, for `<root>/tmp`: not a symlink, is a directory,
  `Validate_Tree_Symlink_Free`, `Ada.Directories.Delete_Tree`. Nothing looks
  for a store marker or refuses a non-empty foreign directory.
- `src/flyology-object_storage-backends-files.adb:364-365` — `Temp_Path` is
  exactly `<root>/tmp`, so the swept directory is the store's staging area.

Refutation attempts that failed:

- *Maybe `Validate_Tree_Symlink_Free` protects a foreign tree.* It raises only
  for symlinks, non-ordinary files, or depth > 64; my sentinel tree of two
  ordinary files in two ordinary directories passed and was deleted.
- *Maybe the sweep is wider than tmp/ and the test is unfair.* No — the
  control shows `<root>/notes/readme.txt` surviving both backends, so the
  sweep is precisely the store's own directories, which is what makes it
  invisible to an operator inspecting the rest of the root.
- *Maybe the executable refuses a root it did not create.* It does not; both
  backends printed `READY` on the foreign roots.
- *Maybe an existing test covers it.* `server/tests/scripts/test.sh:458-471`
  always uses a fresh `$RUN_ROOT/<backend>-store`; no test points a store at a
  directory holding foreign content.

**Repro (backend level, cheapest):** `tests/repros/src/repro_server_exe_3.adb`.
Creates a scratch directory with `tmp/keep.txt`, `tmp/nested/deep.txt` and
`notes/readme.txt`, runs a control on a dedicated empty root (open + create a
bucket), then calls `Files.Open` on the foreign directory and asserts that
`Open` either raised `Configuration_Error` or left the sentinels in place.

**Output** (`cd tests/repros && ./run.sh repro_server_exe_3`, exit status **1**):

```
  -- foreign root = /private/tmp/claude-501/repro-server-exe-3-foreign-84444-496931000
  --   before: tmp/keep.txt exists        = TRUE
  --   before: tmp/nested/deep.txt exists = TRUE
  --   before: notes/readme.txt exists    = TRUE
  -- control: dedicated empty root /private/tmp/claude-501/repro-server-exe-3-dedicated-84444-498973000
  --   Create_Bucket status = SUCCESS
  ok: control: a dedicated empty root opens and accepts a bucket
  -- Files.Open (foreign root) returned normally
  --   after:  tmp/keep.txt exists        = FALSE
  --   after:  tmp/nested/deep.txt exists = FALSE
  --   after:  notes/readme.txt exists    = TRUE
  --   Open refused the root (Configuration_Error) = FALSE
  FAILED: Files.Open either refuses a root that is not a store or leaves <root>/tmp/keep.txt in place
  FAILED: Files.Open either refuses a root that is not a store or leaves <root>/tmp/nested/deep.txt in place
  ok: control: a sibling directory the store does not use survives
BUG REPRODUCED: 2 failed expectation(s)
```

**Repro (through the documented variable, both backends):**
`tests/repros/shell/repro_server_exe_3_server.sh`. Starts the real executable
with `FLYOLOGY_OBJECT_STORAGE_ROOT` pointed at prepared foreign directories,
waits for `READY`, stops the server, and compares the directory listings.

**Output** (`./tests/repros/shell/repro_server_exe_3_server.sh`, exit status **1**):

```
  -- files root /private/tmp/claude-501/repro-server-exe-3-Vbwmr7/files-root before:
       ./notes/readme.txt
       ./tmp/keep.txt
       ./tmp/nested/deep.txt
  -- files server reached READY:
       READY s3 http://127.0.0.1:54723 backend=files
       READY admin http://127.0.0.1:54726/
  -- files root after:
       ./notes/readme.txt
  FAILED: files: the server refuses a root that is not a store, or leaves tmp/keep.txt in place
  FAILED: files: ... and leaves tmp/nested/deep.txt in place
  ok: control: files: a sibling directory the store does not use survives
  -- sqlite root /private/tmp/claude-501/repro-server-exe-3-Vbwmr7/sqlite-root before:
       ./notes/readme.txt
       ./objects/keep.txt
       ./staging/keep.txt
  -- sqlite server reached READY:
       READY s3 http://127.0.0.1:54727 backend=sqlite
       READY admin http://127.0.0.1:54728/
  -- sqlite root after:
       ./.flyology-object-storage.lock
       ./catalog.sqlite3
       ./notes/readme.txt
  FAILED: sqlite: the server refuses a root that is not a store, or leaves objects/keep.txt in place
  FAILED: sqlite: ... and leaves staging/keep.txt in place
  ok: control: sqlite: a sibling directory the store does not use survives
BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** `Configuration.Load` accepts any non-empty string as the
storage root, and the executable passes it straight to the backend's `Open`,
which treats the directory as a store it owns: the files backend recursively
deletes `<root>/tmp`, and the SQLite backend deletes every ordinary file under
`<root>/staging` and every ordinary file under `<root>/objects` that the
freshly created catalog does not reference. Neither backend looks for any
marker distinguishing a real store from an arbitrary directory, and no
diagnostic is printed — the server prints `READY` and serves normally. An
operator who mistypes the root (`/var` for `/var/lib/flyology`, a home
directory with a `~/tmp`, a checkout with a scratch area) loses that content
silently and irreversibly. On this macOS host `/tmp` and `/var` are symlinks
and are refused, so a Linux deployment is the exposed case. It is
deterministic. No existing test points a store at foreign content.

---

### SERVER-EXE-4: supervisor termination diagnostics are discarded

**Verdict:** CONFIRMED. With another process holding the management port, the
executable prints exactly `object-storage server stopped: STARTUP_FAILED` and
exits 1 — naming neither the failing child, nor the endpoint, nor the
exception, all of which the supervisor handed back in `Result.Termination`.

**Severity:** P2 (discovery said P2; unchanged). Wrong diagnostics on a valid
and common input (a port already in use); no wrong data and no unsafety.

Verified by reading:

- `server/src/flyology_object_storage_server_runtime.adb:1075-1080` — the
  report is `"object-storage server stopped: " & Result.Outcome'Image`;
  `Result.Termination` and `Result.Child` are never read.
- `server/src/flyology_object_storage_server_runtime.adb:920-924` — the
  management `Bind_Socket`/`Listen_Socket` have no handler, so `Socket_Error`
  escapes the generation.
- `flyology-supervision.ads:167-177,405-411` — `Supervisor_Result` carries
  `Child`, `Generation`, and a `Termination_Summary` with the exception id,
  exception name and up to 512 characters of message.

Refutation attempts that failed:

- *Maybe `Exception_Information` reaches stderr through the main procedure.*
  `Runtime` catches everything at `:1082-1089` and returns normally, so main's
  handler is not involved for supervisor outcomes. My control confirms the
  contrast: a configuration failure *before* the supervisor does name its
  cause (`raised CONSTRAINT_ERROR :
  FLYOLOGY_OBJECT_STORAGE_BACKEND must be memory, files, or sqlite`).
- *Maybe the "admin" that appears in the output is a diagnostic.* It is not —
  it is the `BOOTSTRAP ADMIN` banner and the credentials path, printed on
  every run. The repro deliberately scopes its assertion to the
  `object-storage server stopped:` line and everything after it. (My first
  draft of the script matched the banner and produced a false PASS; the
  scoped version is what is reported here.)
- *Maybe `Configuration.Load` rejects the conflict earlier.* It validates
  neither port availability nor equal S3/management ports
  (`configuration.adb:66-70`), so the supervisor is the first place the
  conflict is seen.

**Repro:** `tests/repros/shell/repro_server_exe_4.sh`. Holds a loopback port
with a `python3` listener, starts the executable with `FLYOLOGY_ADMIN_PORT`
set to that port, captures stdout and stderr, and asserts that the failure
diagnostic names at least one of the failing child, the endpoint, or the
exception. Controls: the exit status is non-zero, the executable does report
that the server stopped, and a pre-supervisor configuration failure does name
its cause.

**Output** (`./tests/repros/shell/repro_server_exe_4.sh`, exit status **1**):

```
  -- another process holds 127.0.0.1:53658 (a port already in use is the common operator mistake)
  -- server exit status: 1
  -- stdout:
       READY s3 http://127.0.0.1:53670 backend=memory
  -- stderr:
       BOOTSTRAP ADMIN username=admin password=04c77cea071d50ab7f22a54a83d63cc7cda48300e255585a
       Store this password now; it will not be shown again. credentials=/private/tmp/claude-501/repro-server-exe-4-2VTs9L/admin.credentials
       object-storage server stopped: STARTUP_FAILED
  -- failure diagnostic under test:
       object-storage server stopped: STARTUP_FAILED
  ok: control: a management bind failure gives a non-zero exit status
  ok: control: the executable reports that the server stopped
  -- diagnostic names the failing child: no
  -- diagnostic names the endpoint 127.0.0.1:53658: no
  -- diagnostic names the exception: no
  FAILED: the startup-failure diagnostic names the failing child, the endpoint, or the exception
  -- control (pre-supervisor failure, bad backend name), stderr:
       raised CONSTRAINT_ERROR : FLYOLOGY_OBJECT_STORAGE_BACKEND must be memory, files, or sqlite
  ok: control: a configuration failure before the supervisor names its cause
BUG REPRODUCED: 1 failed expectation(s)
```

Note that the S3 child had already printed `READY s3 http://127.0.0.1:53670`,
so an operator reading the output sees a successful listener followed by an
unexplained `STARTUP_FAILED` — the misleading half of the diagnostic.

**Description:** When a child generation terminates with an exception during
startup, `Flyology.Supervision.Static` copies the child's identity and a
512-character termination summary into `Supervisor_Result`, but the executable
prints only `Result.Outcome'Image`. The exception never reaches GNAT's
unhandled-exception reporter either, because the runtime's task termination
hook captures it, so the operator gets one enumeral for every distinct
failure: a port in use, a permission problem, a duplicated
`FLYOLOGY_S3_PORT`/`FLYOLOGY_ADMIN_PORT` pair, or an exhausted restart budget
all read as `STARTUP_FAILED` or `RECOVERY_EXHAUSTED`. Anyone starting the
server on a busy port hits it; it is deterministic.
`server/tests/scripts/test.sh:343-385` (`expect_startup_failure`) asserts only
a non-zero exit and every case it runs fails before the supervisor starts,
where `server.adb:92-98` does print `Exception_Information`. A fix is a
formatting decision (which of `Child`, `Generation`, `Termination.Exception_
Name` and `Termination.Message` to print, and whether the child ids get names)
rather than a new interface value.

---

### SERVER-EXE-5: the executable enforces the documented exclusive-root precondition for SQLite but not for files (new)

**Verdict:** CONFIRMED (new finding, raised from the discovery's observations
list, where it was recorded and deferred to the FILES area). Two servers start
on the same files root; the second's `Open` empties the live first server's
`<root>/tmp/` staging directory while the first is still running and serving.
The same attempt on a SQLite root is refused with a named error.

**Severity:** P2. The deterministic part is the missing enforcement and the
emptying of a live process's staging directory; the harmful part — destroying
a staging file the first process is actually mid-way through writing —
requires a timing race that I did not demonstrate, and the destroyed data
would be transient staging rather than acknowledged writes. It is not P1
because the exclusive-ownership statement in `docs/architecture/files-layout.md`
is a precondition on the operator rather than a promise by the code; a
maintainer who reads the SQLite backend's `flock` as establishing that
enforcement is the contract would reasonably raise it to P1.

Verified by reading:

- `docs/architecture/files-layout.md:3` — "The files backend requires
  exclusive ownership of its configured root by one process."
- `README.md:36` — "one process owning an exclusive storage root".
- `src/flyology-object_storage-backends-files.adb:3514-3573` — `Open` takes no
  lock of any kind; the only guards are symlink and directory-kind checks.
- `src/flyology-object_storage-backends-files.adb:364-365` and the 18 uses of
  `Temp_Path (Item)` in the same body (bucket-creation staging at `:3606`,
  and the publication staging at `:3902`, `:4142`, `:4388`, `:4686`, `:5195`,
  `:6122`) — `<root>/tmp` is the live staging target of ordinary operations,
  not a startup-only directory.
- `sqlite/src/flyology-object_storage-backends-sqlite.adb:107-125`
  (`Acquire_Root_Lock`), called from `Open` at `:301-302` — the
  SQLite backend takes `flock(LOCK_EX|LOCK_NB)` on
  `<root>/.flyology-object-storage.lock` and raises
  `Configuration_Error : could not acquire exclusive SQLite backend root lock`.

Refutation attempts that failed:

- *Maybe the harm is confined to startup, before the first server can be
  affected.* No: `Temp_Path` is the staging target of every publication path
  listed above, so the swept directory is in use for the whole lifetime of the
  first process.
- *Maybe in-flight multipart state is destroyed too, making this worse.* It is
  not: uploads live under `buckets/<bucket>/multipart/`
  (`files.adb:402-403,524-530`), which the sweep does not touch. This bounds
  the finding to transient staging and is why I assign P2 rather than P1.
- *Maybe the executable refuses the second start for another reason.* It does
  not — the second server printed both `READY` lines while the first was still
  alive.
- *Maybe this is the same defect as SERVER-EXE-3.* It is adjacent but
  distinct: SERVER-EXE-3 is about a directory that was never a store;
  this one is about a directory that is a store, currently owned by a live
  process, and the asymmetry with the SQLite backend is what makes it a defect
  rather than a design choice.

**Repro:** `tests/repros/shell/repro_server_exe_5.sh`. Starts server 1 on a
fresh files root, places a sentinel inside the live `<root>/tmp/`, starts
server 2 on the same root, and asserts that server 2 is refused or that the
sentinel survives. The sentinel stands in for server 1's transient staging
artefacts and is created by the script — the program says so in its header,
and it does **not** claim to have destroyed a real in-flight staging file.
Control: the identical two-process attempt on a SQLite root is refused with a
named reason.

**Output** (`./tests/repros/shell/repro_server_exe_5.sh`, exit status **1**):

```
  -- server 1 owns /private/tmp/claude-501/repro-server-exe-5-TcAgmm/files-root:
       READY s3 http://127.0.0.1:55824 backend=files
       READY admin http://127.0.0.1:55825/
  -- placed /private/tmp/claude-501/repro-server-exe-5-TcAgmm/files-root/tmp/owner-staging.tmp while server 1 is live
  -- server 2 on the same root:
       READY s3 http://127.0.0.1:55826 backend=files
       READY admin http://127.0.0.1:55827/
  -- server 2 reached READY: yes
  -- server 1's tmp/owner-staging.tmp survived: no
  -- server 1 still alive: yes
  FAILED: files: a second server is refused a root a live server already owns
  FAILED: files: ... or at least leaves the live root's tmp/ contents in place
  -- control, sqlite: second server on the same root:
       object-storage server startup failed: raised FLYOLOGY.OBJECT_STORAGE.BACKENDS.SQLITE.CONFIGURATION_ERROR : could not acquire exclusive SQLit
       raised FLYOLOGY.OBJECT_STORAGE.BACKENDS.SQLITE.CONFIGURATION_ERROR : could not acquire exclusive SQLite backend root lock
  ok: control: sqlite refuses a second server on a root a live server owns
  ok: control: the sqlite refusal names the reason
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** The server executable offers one `FLYOLOGY_OBJECT_STORAGE_ROOT`
variable for both persistent backends, and the exclusive-ownership
precondition the architecture documents is enforced for exactly one of them.
Pointing a second server (a restart that overlaps the old process, a
misconfigured supervisor unit, an operator running a second instance for a
different port) at a live files root succeeds silently, and the second
`Open`'s `Delete_Tree` of `<root>/tmp` removes whatever the first process has
staged there at that instant; ordinary publication paths stage in exactly that
directory, so a concurrent PUT, tag replacement, bucket creation or multipart
completion can lose its staged record and fail (or, at the margins, leave the
first process to `Sync_Directory` a directory that was replaced underneath
it). The narrow, timing-dependent nature of the harm is why this is P2 rather
than higher, and it is why the deterministic part of the repro is the missing
refusal rather than a corrupted object. `server/tests/scripts/test.sh` never
runs two servers on one root. A fix is a maintainer decision on mechanism —
the files backend could take the same `flock` the SQLite backend already
takes, at the cost of making the files backend depend on a lock file inside
its root, which is a new on-disk artefact and a new failure mode on
filesystems without working advisory locks.

---

## Observations checked with my own reading

Two of the discovery's observations needed correction; the rest I confirmed as
recorded and none of them rises to a finding.

- **Corrected — the `SO_REUSEADDR`/`0.0.0.0` hijack is real but the stated
  mechanism is wrong.** The discovery says "With `FLYOLOGY_S3_BIND=0.0.0.0`,
  `SO_REUSEADDR` on the S3 listener lets another local user on BSD-derived
  kernels bind `127.0.0.1:9000` more specifically". I measured all four
  combinations on this macOS host:

  ```
  wildcard SO_REUSEADDR=True  specific SO_REUSEADDR=True  -> SUCCEEDED
  wildcard SO_REUSEADDR=True  specific SO_REUSEADDR=False -> refused (48 Address already in use)
  wildcard SO_REUSEADDR=False specific SO_REUSEADDR=True  -> SUCCEEDED
  wildcard SO_REUSEADDR=False specific SO_REUSEADDR=False -> refused (48 Address already in use)
  ```

  Only the *attacker's* socket needs `SO_REUSEADDR`; the option the server sets
  on its own listener (`runtime.adb:214-215`) is irrelevant to the outcome, and
  the more-specific listener does receive the loopback connections (verified by
  accepting one). So this is a platform property of any wildcard bind on
  BSD-derived kernels, not something the server's socket options cause or can
  remove — removing `SO_REUSEADDR` from the S3 listener would not help. It
  stays an observation about the documented `FLYOLOGY_S3_BIND=0.0.0.0` option
  on multi-user macOS hosts, and it is not a defect in the executable's code.

- **Confirmed — the credential-file default drift.** `server/README.md:72-73`
  says the file defaults "to `admin.credentials` inside a persistent backend
  root, or `./flyology-admin.credentials` for memory";
  `configuration.adb:47-54` uses `<root>/admin.credentials` whenever
  `FLYOLOGY_OBJECT_STORAGE_ROOT` is set, memory backend included.
  Documentation drift only.

- **Confirmed — main's handler does not cover its declarative part.** Running
  the built executable with `FLYOLOGY_OBJECT_STORAGE_BACKEND=not-a-backend`
  prints GNAT's `Execution of … terminated by unhandled exception / raised
  CONSTRAINT_ERROR : FLYOLOGY_OBJECT_STORAGE_BACKEND must be memory, files, or
  sqlite` with a traceback, not the `object-storage server startup failed:`
  prefix. Exit status 1. Fail-closed and the cause is named, so cosmetic —
  and it is the control that makes SERVER-EXE-4's silence a gap rather than a
  house style.

- **Confirmed — `Local_Request` is a textual authority comparison.** Against a
  live server on port 64932, `Host: localhost:64932` receives
  `HTTP/1.1 421 Status` while `Host: 127.0.0.1:64932` receives
  `HTTP/1.1 200 OK`. Only hand-typed URLs are affected; the printed `READY`
  line gives the numeric form.

- **Confirmed — the server crate is not built or tested in CI.**
  `grep -n 'server' .github/workflows/ci.yml` matches only lines 271 and 301,
  both about `tests/scripts/`. Nothing in the workflow builds `server/` or
  runs `server/tests/scripts/test.sh`, so the lightweight handler
  configuration that produces SERVER-EXE-1, the management API, the credential
  bootstrap and the SIGTERM path are gated only by a local `alr test`. This is
  a process gap that belongs with the CI/baseline area rather than with the
  crate's code.

- **Confirmed — the assets loader requires a working directory or
  `FLYOLOGY_ADMIN_ASSET_ROOT`.** `assets.adb:16-27` looks only at
  `./assets/index.html` and `./server/assets/index.html`; started from any
  other directory the executable fails with `CONSTRAINT_ERROR : management
  assets not found`. This is documented at `server/README.md:74-76` ("By
  default the server finds `assets` from the crate directory or
  `server/assets` from the repository root") and is fail-closed; every repro
  script above therefore sets `FLYOLOGY_ADMIN_ASSET_ROOT` explicitly. Not a
  defect, but worth knowing when reproducing any of these findings.

- Confirmed as recorded, no change: the PBKDF2 work factor and self-test, the
  constant-time comparisons and plaintext wiping, the credential file's
  `O_EXCL`/`link` publication and `0600`/uid checks, the session and cookie
  policy, the CSRF and `Origin` handling, the security response headers, the
  bounded bodies and ingress budget, the SIGTERM/shutdown classification, and
  the descriptor leak in `Run_S3` when `Bind_Socket` raises (bounded by the
  recovery limits, at most ten per process, and not separately reproducible
  without also triggering SERVER-EXE-4).

## Findings sweep result

Five findings, all CONFIRMED: SERVER-EXE-1 at P1, SERVER-EXE-2 through
SERVER-EXE-5 at P2. No discovery finding was refuted or downgraded. One
observation (the `SO_REUSEADDR` mechanism) was partially refuted and its
corrected form is recorded above. Every server process started during this
verification was stopped (`pgrep -fl flyology_object_storage_server` returns
nothing).
