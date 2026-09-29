# Adversarial verification: SQLite backend (BACKEND-SQLITE)

Scope verified by reading, at commit 5fe6e3e:
`sqlite/src/flyology-object_storage-backends-sqlite.ads` (contract),
`sqlite/src/flyology-object_storage-backends-sqlite.adb` (lines 130-250,
2200-2900, 3118-3220, 4290-4360),
`sqlite/src/flyology-object_storage-sqlite-catalogs.ads:660-790`,
`sqlite/src/flyology-object_storage-sqlite-catalogs.adb` (lines 355-400,
800-935, 2820-2870, 3341-3395, 5593-5760, 6050-6100, 6480-6570, 7304-7380,
8776-9040, 9135-9176), `src/flyology-object_storage.ads`,
`src/flyology-object_storage.adb:100-300`,
`src/flyology-object_storage-backends.ads` (contract, 50-560, 1880-2630),
`src/flyology-object_storage-backends.adb:290-460`,
`src/flyology-object_storage-backends-memory.adb:560-615`,
`src/flyology-object_storage-backends-files.adb:3835-3872`,
`src/flyology-object_storage-server-s3_applications.adb:1945-1958, 14555,
18040-18066`, `sqlite/flyology_object_storage_sqlite.gpr`,
`sqlite/src/flyology_object_storage_sqlite_durability.c`,
`docs/architecture/sqlite-backend.md`,
`docs/qualification/object-annotations-backend-server.md`,
`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb` (by outline and
`rg`), `sqlite/tests/src/s3_sqlite_server.adb`,
`tests/src/object_storage_test_cases.adb:19555-19745`,
`tests/src/s3_server_application_corpus.adb:13600-13670`,
`tests/src/s3_implementation_corpus.adb` (by `rg`),
`tests/scripts/test-flyology-server.sh`.

Harness programs added (all untracked, under `sqlite/tests/repros/src/`):
`repro_sqlite_support.ads`, `repro_sqlite_support.adb`,
`repro_sqlite_smoke.adb`, `repro_sqlite_1.adb`, `repro_sqlite_2.adb`,
`repro_sqlite_3.adb`, `repro_sqlite_3b.adb`, `repro_sqlite_4.adb`.
Nothing tracked was modified. No Docker server was used.

Harness status: the SQLite reproduction crate builds and runs. The smoke
program `repro_sqlite_smoke` PASSes (exit 0).

| ID | Verdict | Severity (discovery) | Repro |
|----|---------|----------------------|-------|
| BACKEND-SQLITE-1 | CONFIRMED | P1 (P2) | `sqlite/tests/repros/src/repro_sqlite_1.adb` |
| BACKEND-SQLITE-2 | CONFIRMED | P1 (P1) | `sqlite/tests/repros/src/repro_sqlite_2.adb` |
| BACKEND-SQLITE-3 | CONFIRMED | P0 (P0) | `sqlite/tests/repros/src/repro_sqlite_3.adb`, `repro_sqlite_3b.adb` |
| BACKEND-SQLITE-4 | CONFIRMED | P1 (P1) | `sqlite/tests/repros/src/repro_sqlite_4.adb` |
| BACKEND-SQLITE-5 | CONFIRMED | P2 (P2) | none (documentation finding) |

No sixth finding: none of the thirteen discovery observations reaches P2 or
above under the rubric on my own reading (details at the end).

---

### BACKEND-SQLITE-1: `Get_Object` opens the payload after the catalog gate is released

**Verdict:** CONFIRMED, and materially worse than the discovery estimated.
Reproduced with ordinary reads (no window widening) at 7.0 % of 316,407
concurrent GETs against only 1,822 concurrent PUTs.

**Severity:** P1 (discovery said P2 with Medium confidence, on the assumption
that the window is a few instructions wide and stock clients retry the 503).
Corrected to P1 because (a) it is a wrong result on valid input through a
reachable path — a GET of a key that exists before and after the request
returns `Backend_Unavailable`, mapped to HTTP 503 `SlowDown` at
`src/flyology-object_storage-server-s3_applications.adb:1951-1954`; (b) it
violates a documented invariant of this backend, quoted below; and (c) the
measured rate under ordinary server concurrency is roughly twelve failed GETs
per overwrite, not a rare edge. Not P0: no data is lost, no request is
mis-served with wrong bytes (the size check at
`backends-sqlite.adb:2679-2681` and immutable payload names prevent that),
and 503 is retriable.

Verified by reading:

- `sqlite/src/flyology-object_storage-backends-sqlite.adb:2666-2683`:
  `Get_Object` calls `Catalogs.Find_Selected_Object` with no `Check`
  argument, then evaluates read conditions, then `SIO.Open`.
- `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:5688-5716`: that
  overload does `Item.Gate.Acquire`, the lookup, the optional `Check`, then
  `Item.Gate.Release` — so with a null `Check` the gate is released before
  the caller ever touches the file.
- The two sibling readers do pass the hook:
  `backends-sqlite.adb:2581-2583` (`Head_Object`, `Check_Payload'Access`)
  and `2448-2451` (`Copy_Object`, `Open_Source'Access`).
- `sqlite/src/flyology-object_storage-sqlite-catalogs.ads:707-712` documents
  the hook's purpose: it "may validate the immutable external payload before
  a concurrent publication retires the previous file".
- `backends-sqlite.adb:2232-2235`: `Put_Object` unlinks the replaced payload
  immediately after the commit returns, i.e. after the gate is released.
- `backends-sqlite.adb:2736-2745`: any exception outside a sink callback
  becomes `Result := Backend_Unavailable`.
- `docs/architecture/sqlite-backend.md:20-23` states the invariant the code
  does not keep: "Superseded and deleted bodies are intentionally retained
  until that recovery pass so an already-open reader is never invalidated by
  replacement." The code retires them at commit time, not at the next
  recovery pass (this is discovery observation O5, confirmed).

Refutation attempts that failed:

- Looked for a second guard between the lookup and `SIO.Open`: there is none;
  the only work is `Is_Payload_Name`, `Evaluate_Read_Conditions` and `Join`.
- Checked whether the failure could be `Not_Found` (a benign, well-defined
  answer) rather than `Backend_Unavailable`: the run records zero `Not_Found`
  and 22,281 `Backend_Unavailable` in phase A, so the catalog lookup always
  succeeded and only the file open failed.
- Checked whether the writers themselves were failing and thus corrupting the
  premise: all 1,822 phase-A PUTs and 1,792 phase-B PUTs returned `Success`.
- Checked whether the reads were racing a *deletion*: the writers only
  overwrite, so the key exists for the whole run; the single-task control GET
  with the same arguments succeeds.
- Checked whether widening the window is required to see it: phase A uses
  `Default_Read_Conditions` and still fails 7.0 % of the time; the long
  If-Match list in phase B (the only work Get_Object performs in the
  unprotected window) did not increase the rate materially, which shows the
  dominant factor is reader scheduling, not the window's instruction count.

**Repro:** `sqlite/tests/repros/src/repro_sqlite_1.adb`. Opens a SQLite store
on a fresh scratch root, creates `race-bucket`, seeds `k` with one byte, and
runs two 20 s phases of 32 reader tasks against 2 writer tasks. Every writer
publishes the *same* bytes, so the entity tag never changes and every GET is
required to return `Success`. Phase A reads with no conditions; phase B reads
with a 14,284-byte matching `If-Match` list. A single-task control GET runs
before the races and must succeed. Statuses are tallied per `Status` literal.

**Output** (`cd sqlite/tests/repros && ./run.sh repro_sqlite_1 180`, exit
status **1**):

```
  -- root /private/tmp/claude-501/repro-sqlite/get-race-68928105-0
  ok: Create_Bucket succeeds
  ok: Put_Object seeds the key
  -- entity tag 9dd4e461268c8034f5c8564e155c67a6 (constant: every writer publishes the same bytes)
  -- control Get_Object SUCCESS bytes 1
  ok: control Get_Object succeeds
  ok: control Get_Object round-trips the body
  -- phase A (plain reads) GET total 316407: SUCCESS=294126 BACKEND_UNAVAILABLE=22281
  -- phase A (plain reads) PUT total 1822: SUCCESS=1822
  ok: phase A (plain reads): the writers made progress
  ok: phase A (plain reads): tally is consistent
  FAILED: phase A (plain reads): no concurrent Get_Object reports Backend_Unavailable for a key that always exists
  ok: phase A (plain reads): no concurrent Get_Object reports Not_Found for a key that always exists
  -- phase B If-Match list length 14284 (matching, evaluated after the gate release)
  -- phase B (long matching If-Match) GET total 336671: SUCCESS=317508 BACKEND_UNAVAILABLE=19163
  -- phase B (long matching If-Match) PUT total 1792: SUCCESS=1792
  ok: phase B (long matching If-Match): the writers made progress
  ok: phase B (long matching If-Match): tally is consistent
  FAILED: phase B (long matching If-Match): no concurrent Get_Object reports Backend_Unavailable for a key that always exists
  ok: phase B (long matching If-Match): no concurrent Get_Object reports Not_Found for a key that always exists
BUG REPRODUCED: 2 failed expectation(s)
```

**Description:** `Get_Object` resolves the payload name under the catalog
operation gate and then opens the file after the gate has been released
(`backends-sqlite.adb:2666-2683`). A concurrent `Put_Object` on the same key
commits its replacement and unlinks the superseded payload as soon as it
leaves the gate (`backends-sqlite.adb:2232-2235`), so a reader holding the
old name gets `Name_Error` from `SIO.Open`, which the `when others` handler
turns into `Backend_Unavailable` and the S3 boundary into 503 `SlowDown`.
Every S3 client that reads a key while another client overwrites it is
affected; the observed rate is about twelve failed reads per overwrite with
32 concurrent readers, so it is not deterministic per request but is
statistically certain under load. `Head_Object` and `Copy_Object` already
pass the `Check` hook for exactly this purpose, and an open POSIX descriptor
survives unlink, so giving `Get_Object` (and the part readers at
`backends-sqlite.adb:4067-4072` and `4295-4301`) the same hook closes the
window without any interface change. The behaviour also contradicts
`docs/architecture/sqlite-backend.md:20-23`, so either the code or that
sentence has to change; no existing test asserts the wrong behaviour, because
`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:1365-1518` races
only writes against writes.

---

### BACKEND-SQLITE-2: annotation copy lease released below its own `CHECK(refs>0)`

**Verdict:** CONFIRMED, exactly as described, including the masking effect of
a second copy of the same source. Also confirmed for the
`Exclude_Annotations` directive, which the discovery predicted but did not
demonstrate.

**Severity:** P1 (discovery P1, unchanged). An unexpected exception escapes
`Copy_Object` on valid input through a reachable path, after the destination
has already been committed; the S3 boundary answers 500 `InternalError`
(`src/flyology-object_storage-server-s3_applications.adb:14555` dispatches
`Store.Copy_Object`, and the `when others` handler at `18056-18065` sends
500). Not P0: nothing is lost or corrupted and the client's retry succeeds.

Verified by reading:

- `sqlite/src/flyology-object_storage-sqlite-catalogs.adb:2842-2846`: the
  TEMP table is created as
  `annotation_copy_leases(payload TEXT PRIMARY KEY, refs INTEGER NOT NULL CHECK(refs>0)) WITHOUT ROWID`.
- `catalogs.adb:846-856`: leases are inserted with `VALUES(?1,1)` and
  `ON CONFLICT(payload) DO UPDATE SET refs=refs+1`.
- `catalogs.adb:874-892`: the release runs
  `UPDATE annotation_copy_leases SET refs=refs-1 WHERE payload=?1 AND refs>0`
  and then `DELETE ... WHERE payload=?1 AND refs=0`. The delete is dead code:
  the CHECK makes `refs=0` unreachable, so the intended reference-count
  lifecycle cannot complete even once.
- `catalogs.adb:7331-7347`: `Find_Selected_Object` (the tags+annotations
  overload) calls `Read_Version_Annotations_Internal` unconditionally on
  success, before the `Check` callback and irrespective of the copy
  directive.
- `backends-sqlite.adb:2448-2451, 2459, 2520-2521, 2532-2541`: `Copy_Object`
  is the only caller of that overload; it sets `Annotation_Leases_Held` and
  calls `Release_Annotations` on the success path (2521) and again from its
  own `when others` handler (2536). `Release_Annotations`
  (`backends-sqlite.adb:2378-2392`) clears the flag only *after*
  `Release_Annotation_Copy_Snapshot` returns, so a raise there leaves the
  flag set and the handler re-raises inside itself; the `SQLite_Error` then
  escapes `Copy_Object`.
- `sqlite/src/flyology-object_storage-sqlite-databases.adb:398-400`: a failed
  step raises `SQLite_Error` carrying the SQLite message.

Refutation attempts that failed:

- Checked the vendored build flags for `SQLITE_OMIT_CHECK` or
  `ignore_check_constraints`: `sqlite/flyology_object_storage_sqlite.gpr:19-36`
  defines `SQLITE_THREADSAFE`, `SQLITE_DQS`, `SQLITE_DEFAULT_MEMSTATUS`,
  `SQLITE_OMIT_DEPRECATED`, `SQLITE_ENABLE_API_ARMOR`,
  `SQLITE_ENABLE_COLUMN_METADATA`, `SQLITE_ENABLE_DBSTAT_VTAB`,
  `SQLITE_ENABLE_RTREE`, `SQLITE_USE_URI` — no CHECK suppression. The run
  output confirms the constraint fires: `CHECK constraint failed: refs>0`.
- Checked whether `Exclude_Annotations` avoids the lease: it does not; the
  program copies a freshly annotated source with `Exclude_Annotations` and
  gets the same raise.
- Checked whether an unannotated source is affected: it is not; the control
  copy in the same program succeeds, which is why the maintained copy tests
  pass.
- Checked whether the destination is left unpublished: it is published — the
  program reads the copied annotation and heads the copied object
  successfully *after* the exception.

**Repro:** `sqlite/tests/repros/src/repro_sqlite_2.adb`. Fresh SQLite root;
creates a bucket; copies an unannotated source (control, must succeed); puts
`annotated-src`, attaches annotation `note`, and copies it, asserting that
`Copy_Object` neither raises nor returns a non-success status; then reads the
annotation and heads the destination to show the copy was committed; repeats
with `Exclude_Annotations` on a second freshly annotated source; and finally
copies the first source again to show the second attempt succeeds.

**Output** (`cd sqlite/tests/repros && ./run.sh repro_sqlite_2 300`, exit
status **1**):

```
  -- root /private/tmp/claude-501/repro-sqlite/annotation-copy-69126967-0
  ok: Create_Bucket succeeds
  ok: Put_Object plain-src succeeds
  -- control (no annotation): Copy_Object returned SUCCESS
  ok: control (no annotation): Copy_Object does not raise
  ok: control (no annotation): Copy_Object returns Success
  ok: Put_Object annotated-src succeeds
  -- Put_Object_Annotation on annotated-src SUCCESS size 24
  ok: Put_Object_Annotation on annotated-src succeeds
  -- subject (one annotation): Copy_Object raised FLYOLOGY.OBJECT_STORAGE.SQLITE.DATABASES.SQLITE_ERROR -- CHECK constraint failed: refs>0
  FAILED: subject (one annotation): Copy_Object does not raise
  FAILED: subject (one annotation): Copy_Object returns Success
  -- Get_Object_Annotation on the copy SUCCESS presence ANNOTATION_PRESENT bytes 24
  ok: Get_Object_Annotation on the copy succeeds
  ok: the copied annotation is present on the destination
  ok: the copied annotation payload round-trips
  -- Head_Object on the copy afterwards SUCCESS size 14
  ok: Put_Object excluded-src succeeds
  -- Put_Object_Annotation on excluded-src SUCCESS size 24
  ok: Put_Object_Annotation on excluded-src succeeds
  -- subject (EXCLUDE directive): Copy_Object raised FLYOLOGY.OBJECT_STORAGE.SQLITE.DATABASES.SQLITE_ERROR -- CHECK constraint failed: refs>0
  FAILED: subject (EXCLUDE directive): Copy_Object does not raise
  FAILED: subject (EXCLUDE directive): Copy_Object returns Success
  -- second copy of same source: Copy_Object returned SUCCESS
  ok: second copy of same source: Copy_Object does not raise
  ok: second copy of same source: Copy_Object returns Success
BUG REPRODUCED: 4 failed expectation(s)
```

**Description:** the temporary lease table that keeps a source annotation
payload alive across a copy declares `CHECK(refs>0)` but releases with
`SET refs=refs-1`, so the very first release of a lease taken at 1 violates
the constraint and `Step` raises `SQLite_Error`. Every `CopyObject` of an
annotated source is affected, in both directives, on the first copy of that
source in a process; the destination has already been committed at that
point, so the client gets 500 `InternalError` for a copy that actually
succeeded, and a retry against a versioning-enabled bucket publishes a second
destination generation. The failure is deterministic. Two side effects are
worth noting for the fix: the `DELETE ... WHERE refs=0` statement immediately
after the update is unreachable as written, and the stranded `refs=1` row
keeps `Delete_Payload_If_Unreferenced` (`catalogs.adb:9150-9166`, which
counts `annotation_copy_leases`) from ever reclaiming that annotation payload
until the process restarts. There is no SQLite annotation coverage at all
(see BACKEND-SQLITE-5), so no existing test asserts the wrong behaviour; the
memory and pure-files backends are covered by
`tests/src/object_storage_test_cases.adb:19555-19696`, driven at 19734 and
19743. A fix needs a maintainer decision on the intended lease lifecycle —
either drop the `CHECK` and keep the delete-at-zero, or make the release a
`DELETE ... WHERE refs=1` / `UPDATE ... WHERE refs>1` pair — and should also
clear `Annotation_Leases_Held` before the fallible call so the handler cannot
re-enter it.

---

### BACKEND-SQLITE-3: a failed lease release inside `Find_Selected_Object`'s handler leaks the catalog gate forever

**Verdict:** CONFIRMED. Both the mechanism and, more importantly, a
caller-reachable trigger that needs no filesystem interference at all.

**Severity:** P0 stands (discovery P0). The store stops answering every
operation, on every bucket, permanently, until the process is killed. The
answer to "is a cancelled or timed-out GET of an annotated object enough?" is
**no**: `Get_Object` uses the plain `Find_Selected_Object` overload
(`catalogs.adb:5688-5716`), which takes no leases and whose handler releases
the gate unconditionally. The exact caller-reachable sequence is:

> `Copy_Object` (the only caller of the lease-taking overload,
> `backends-sqlite.adb:2448-2451`) on a source generation that carries at
> least one annotation, where the `Open_Source` callback raises. `Open_Source`
> (`backends-sqlite.adb:2394-2416`) raises when the caller's token is
> cancelled, when the caller's deadline has passed, or when the source body
> file is missing, symlinked or mis-sized.

Cancellation and deadline are plain arguments of the public `Copy_Object`
profile, so an ordinary S3 `CopyObject` whose client aborts, or whose request
deadline expires while the request waits for the gate (the gate is an
unconditional protected entry, discovery observation O9, so that wait is
unbounded under contention), wedges the whole backend. `repro_sqlite_3b`
demonstrates exactly that with nothing but a caller-supplied deadline.

Verified by reading:

- `catalogs.adb:7349-7361`: the handler runs
  `Release_Annotation_Copy_Leases_Internal (Item, Annotations)` *before*
  `Item.Gate.Release`, so a raise in the release skips the unlock.
- `catalogs.adb:864-893`: that release raises whenever the update does not
  change exactly one row, and always when a lease at 1 hits `CHECK(refs>0)`
  (BACKEND-SQLITE-2). Independently of that constraint, any SQLite failure in
  the release has the same effect, because fallible work precedes the unlock.
- `catalogs.adb:918-928`: `Operation_Gate` is `entry Acquire when not Held`
  with a plain `procedure Release` — no owner tracking, no timeout, no
  controlled unlock.
- Every catalog operation begins with `Item.Gate.Acquire` (for example
  `3348`, `5701`, `5734`, `7331`, `9148`), so once `Held` stays `True` every
  later call blocks, including `Close`.
- `backends-sqlite.adb:2394-2416` (`Open_Source`) and `164-177`
  (`Check_Context`): the callback raises `Operation_Cancelled`,
  `Timeout_Error` or `Data_Error`.
- `catalogs.adb:7363-7379` (`Release_Annotation_Copy_Snapshot`) *does*
  protect the gate, which is why BACKEND-SQLITE-2's success-path failure does
  not leak it; only the handler at 7349 does.

Refutation attempts that failed:

- Checked whether `Get_Object`/`Head_Object` can reach the leaking handler:
  they cannot; they use the overload at `catalogs.adb:5688`, verified by
  grepping every `Find_Selected_Object` call site
  (`backends-sqlite.adb:2448, 2581, 2666`).
- Checked whether `Copy_Object` could release the gate itself: the gate is
  private to `Catalog` (`catalogs.ads` exposes no release), and `Copy_Object`
  only sets `Result := Backend_Unavailable` and returns normally.
- Checked for a controlled/finalized unlock or a timed entry: none exists.
- Checked whether re-opening the store recovers: it cannot from the same
  process, because `Close` also acquires the gate.

**Repro (deterministic mechanism):**
`sqlite/tests/repros/src/repro_sqlite_3.adb`. Fresh root; put `src`; record
the single payload file; attach one annotation; confirm `Head_Bucket` works;
remove the source body file so `Open_Source` raises `Data_Error` under the
gate; call `Copy_Object`; then probe `Head_Bucket` from a second task with a
bounded 5 s wait (a timed entry call on a protected `Completion` object).
The program prints the verdict and calls `GNAT.OS_Lib.OS_Exit (1)` on the
timeout rather than letting the blocked task hang the harness.

**Output** (`cd sqlite/tests/repros && ./run.sh repro_sqlite_3 120`, exit
status **1**):

```
  -- root /private/tmp/claude-501/repro-sqlite/gate-leak-68613704-0
  ok: Create_Bucket succeeds
  ok: Put_Object src succeeds
  ok: exactly one payload file before annotating
  ok: Put_Object_Annotation succeeds
  -- control Head_Bucket SUCCESS
  ok: control Head_Bucket succeeds
  -- removed the source body payload /private/tmp/claude-501/repro-sqlite/gate-leak-68613704-0/objects/e7fabf131183cb3117d2b99881f5cb43fb187faf80e83e1db1bb545a616a23b3.blob
  -- Copy_Object with a missing source body returned BACKEND_UNAVAILABLE
  -- probing the store from a second task (bounded 5 s wait)
  -- probe Head_Bucket did not return within 5 s: the catalog operation gate was never released
  FAILED: the store still serves Head_Bucket after a failed Copy_Object
BUG REPRODUCED: 1 failed expectation(s)
```

**Repro (caller-reachable, no tampering):**
`sqlite/tests/repros/src/repro_sqlite_3b.adb`. Same setup, but the source
carries 200 annotations purely to widen the interval between `Copy_Object`'s
entry `Check_Context` and the `Open_Source` callback, and the trigger is the
`Deadline` argument alone. The program scans the deadline upward in 3 µs
steps; attempts rejected at the entry check raise `Timeout_Error`, take no
leases and are harmless, so the scan is safe. It stops at the first attempt
that returns a `Status` (which means the callback raised under the gate) or
that completes the copy.

**Output** (`cd sqlite/tests/repros && ./run.sh repro_sqlite_3b 240`, exit
status **1**):

```
  -- root /private/tmp/claude-501/repro-sqlite/gate-leak-deadline-68747455-0
  ok: Create_Bucket succeeds
  ok: Put_Object src succeeds
  -- attached 200 annotations to src
  -- control Head_Bucket SUCCESS
  ok: control Head_Bucket succeeds
  -- CopyObject with a 6 us deadline returned BACKEND_UNAVAILABLE (the deadline expired inside the gate-held window)
  -- attempts rejected at the entry check: 1
  -- probing the store from a second task (bounded 5 s wait)
  -- probe Head_Bucket did not return within 5 s: the catalog operation gate was never released
  FAILED: the store still serves Head_Bucket after a CopyObject whose deadline expired
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** `Find_Selected_Object`'s exception handler
(`catalogs.adb:7349-7361`) performs the annotation-lease release before
releasing the operation gate. The release is fallible — and today always
fails for a lease at 1, per BACKEND-SQLITE-2 — so `Item.Gate.Release` is
skipped and `Held` remains `True` for the life of the process. Every
subsequent catalog call, on any bucket, blocks in the protected entry with no
deadline and no cancellation; an S3 server on this backend stops answering
every request and cannot even close the store. Anyone who issues a
`CopyObject` of an annotated object and cancels it, or whose deadline expires
while the request queues behind other work, hits this; the second repro
triggers it with nothing but a 6 µs deadline through the public `Backend`
interface, and both repros are deterministic. Two secondary effects are
visible in the runs: the timed-out `Copy_Object` reports `Backend_Unavailable`
instead of propagating `Timeout_Error`, because the SQLite exception replaced
the original one before `Copy_Object`'s
`when Operation_Cancelled | Timeout_Error => raise` handler could see it; and
the store is unrecoverable in-process. No existing test covers it — the
SQLite suite performs no annotation operation and no test asserts that the
store survives a failed `Copy_Object`. A fix needs the unlock to run first
(or under a controlled object) and, separately, the BACKEND-SQLITE-2 lease
repair; a maintainer decision is also needed on whether `Gate.Acquire` should
honour the caller's deadline (discovery observation O9), which is what makes
the timed-out-copy trigger easy to hit under load.

---

### BACKEND-SQLITE-4: `Delete_Bucket` reports `Backend_Unavailable` for a bucket whose keys are all delete markers

**Verdict:** CONFIRMED, with the memory backend as a passing control in the
same program.

**Severity:** P1 (discovery P1, unchanged). A defined storage status
(`Bucket_Not_Empty`) exists for exactly this state and the two other
backends return it; SQLite instead returns `Backend_Unavailable`, which the
S3 boundary maps to 503 `SlowDown`
(`src/flyology-object_storage-server-s3_applications.adb:1951-1954`) rather
than the 409 `BucketNotEmpty` at `1947-1950`. Wrong result on valid input via
a reachable path. Not P0: nothing is deleted (the transaction rolls back) and
no data is lost.

Verified by reading:

- `catalogs.adb:3352-3374`: the emptiness test is
  `EXISTS(... FROM buckets ...)`, `EXISTS(... FROM objects ...)`,
  `EXISTS(... FROM multipart_uploads ...)`. `object_versions` is not
  consulted.
- `catalogs.adb:387`: `object_versions` carries
  `FOREIGN KEY(bucket_name) REFERENCES buckets(name) ON DELETE RESTRICT`.
- `catalogs.adb:6271-6279` and `6317-6319`: publishing a delete marker
  removes the `objects` mirror row and returns early, so a marker-current key
  leaves no `objects` row for the `EXISTS` test to find.
- `backends-sqlite.adb:386-406`: the wrapper re-raises only
  `Operation_Cancelled` and `Timeout_Error`; everything else becomes
  `Result := Backend_Unavailable`.
- `src/flyology-object_storage.ads:21,45`: `Bucket_Not_Empty` is documented
  as "Bucket still contains objects".
- `src/flyology-object_storage-backends-files.adb:3846-3852`: the pure-files
  backend counts its `versions` directory and returns `Bucket_Not_Empty`.
- `src/flyology-object_storage-backends-memory.adb:578-600`: the memory
  backend scans its object table, which retains delete markers
  (`backends-memory.adb:1957`), and returns `Bucket_Not_Empty`.

Refutation attempts that failed:

- Looked for a path that removes `object_versions` rows when a key's current
  generation becomes a marker: there is none; `Refresh_Current_Mirror` only
  touches the mirrors.
- Checked whether `Delete_Bucket` leaves partial state: it runs inside
  `Begin_Transaction` with `Safe_Rollback` on the handler
  (`catalogs.adb:3385-3393`), so the defect is the reported status, not
  durability.
- Checked whether the memory backend agrees with SQLite (which would make
  this a cross-backend design choice rather than a SQLite defect): it does
  not — the control in the repro returns `Bucket_Not_Empty` for the identical
  call sequence.
- Checked the existing SQLite assertion at
  `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:7660-7663`: it
  asserts `Bucket_Not_Empty` only with a current *data* object, so the
  marker-only path is untested.

**Repro:** `sqlite/tests/repros/src/repro_sqlite_4.adb`. One class-wide
procedure runs the same sequence — `Create_Bucket`, `Put_Bucket_Versioning
(Versioning_Enabled)`, `Put_Object`, `Delete_Object` (publishes a marker),
`Head_Object` (shows the key is absent from the current view),
`Delete_Bucket` — first against `Repro_S3_Server.Store` (memory, the control)
and then against a SQLite store on a fresh root, asserting `Bucket_Not_Empty`
in both cases.

**Output** (`cd sqlite/tests/repros && ./run.sh repro_sqlite_4 120`, exit
status **1**):

```
  -- root /private/tmp/claude-501/repro-sqlite/delete-bucket-68794973-0
  ok: memory: Create_Bucket succeeds
  ok: memory: Put_Bucket_Versioning Enabled succeeds
  ok: memory: Put_Object succeeds
  -- memory: Delete_Object (publishes a delete marker) SUCCESS
  ok: memory: Delete_Object succeeds
  -- memory: Head_Object after the marker NOT_FOUND
  -- memory: Delete_Bucket BUCKET_NOT_EMPTY
  ok: memory: Delete_Bucket reports Bucket_Not_Empty (control)
  ok: sqlite: Create_Bucket succeeds
  ok: sqlite: Put_Bucket_Versioning Enabled succeeds
  ok: sqlite: Put_Object succeeds
  -- sqlite: Delete_Object (publishes a delete marker) SUCCESS
  ok: sqlite: Delete_Object succeeds
  -- sqlite: Head_Object after the marker NOT_FOUND
  -- sqlite: Delete_Bucket BACKEND_UNAVAILABLE
  FAILED: sqlite: Delete_Bucket reports Bucket_Not_Empty
BUG REPRODUCED: 1 failed expectation(s)
```

**Description:** `Catalogs.Delete_Bucket` decides emptiness from the
current-object mirror and the multipart table only, but `object_versions`
holds retained generations and restricts the bucket row with
`ON DELETE RESTRICT`. Any versioning-enabled (or suspended) bucket whose keys
have all been deleted through `DeleteObject` therefore has no mirror rows,
passes the emptiness test, and then trips the foreign key inside the
transaction; the SQLite error is rewrapped as `Backend_Unavailable` and the
server answers 503 `SlowDown`. Every client that enables versioning, deletes
its objects the ordinary way, and then tries to delete the bucket sees an
indefinite retry loop instead of a definitive 409 `BucketNotEmpty` telling it
to remove the versions first; the failure is deterministic. The memory and
pure-files backends both count retained generations, so the cross-backend
expectation is unambiguous and no maintainer decision is needed beyond adding
`EXISTS(SELECT 1 FROM object_versions WHERE bucket_name=?1)` to the emptiness
query. The existing SQLite `Bucket_Not_Empty` assertion at
`sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:7660-7663` does
not cover this path, and the versioning race test at `1503-1518` permanently
removes the generation before its `Delete_Bucket` cleanup, so it does not
either.

---

### BACKEND-SQLITE-5: the annotation qualification record claims SQLite corpus evidence that does not exist

**Verdict:** CONFIRMED, with one correction to the discovery's supporting
detail.

**Severity:** P2 (discovery P2, unchanged). Contract/qualification drift: the
document overstates the evidence, and the gap it hides is precisely where
BACKEND-SQLITE-2 and BACKEND-SQLITE-3 live.

**Repro:** none — this is a documentation finding, verified with `rg` and by
reading the cited sources, as the area brief allows.

Verified by reading:

- `docs/qualification/object-annotations-backend-server.md:26-27`: "Memory,
  pure-files, and SQLite implement the same interface." and `45-47`: "The
  maintained backend and server corpora exercise payload, checksum, version,
  list, missing, condition, and copy-directive behavior across the
  implementations."
- `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb`: zero matches
  for `Put_Object_Annotation`, `Get_Object_Annotation`,
  `Delete_Object_Annotation` or `List_Object_Annotations`; the only
  `annotation` matches are migration DDL fixtures (`551-963`, `1861-1872`)
  and `Empty_Vector` arguments (`3397-3398`, `3439-3440`).
- `tests/src/s3_implementation_corpus.adb`: zero matches for `annotation`.
  `tests/scripts/test-flyology-server.sh:39-41, 111-122` shows that this is
  the only corpus run against `s3_sqlite_server`.
- `docs/architecture/sqlite-backend.md` does not mention annotations at all.

Correction to the discovery: annotation behaviour *is* exercised against two
backends, not one. `tests/src/object_storage_test_cases.adb:19555-19696`
defines `Exercise_Object_Annotations` over `Backends.Backend'Class` — including
the COPY/EXCLUDE directive assertions at `19661-19675` — and it is driven
against the memory store at `19734` and the pure-files store at `19743`. The
substantive claim survives: it is never driven against a SQLite store,
because that suite lives in the root crate and the SQLite suite is a separate
crate that does not call it.

**Description:** the qualification record presents annotation behaviour as
corpus-verified "across the implementations" while naming SQLite as one of
them, but no SQLite-backed test performs any annotation operation, and the
only black-box corpus run against `s3_sqlite_server` has no annotation
coverage. A reader auditing the record would conclude that SQLite annotation
copy is exercised; BACKEND-SQLITE-2 and BACKEND-SQLITE-3 show that the first
`CopyObject` of any annotated SQLite object fails and can wedge the store.
The cheapest repair is to run the existing class-wide
`Exercise_Object_Annotations` against a SQLite store from the SQLite suite,
which would have caught both defects; if that is not wanted, the sentence at
`45-47` should name the implementations it actually covers.

---

## Assessment of the discovery's thirteen observations

I re-read each against the sources. None reaches P2 or above under the
rubric, so no new finding number was allocated. Corrections and additions:

- **O1** (`backends-sqlite.adb:2884-2886`) — CONFIRMED as an asymmetry:
  `Delete_Objects` calls `Delete_Payload_If_Unreferenced` without the
  per-payload `begin ... when others => null` used by
  `Delete_Selected_Object` (`2823-2831`), and also without the
  `Sync_Path (Objects_Path, Directory => True)` that path performs
  (`2831-2833`). Below the rubric: `Delete_Payload_If_Present`
  (`224-233`) swallows every filesystem error, so the only way to raise is a
  SQLite failure inside `Catalogs.Delete_Payload_If_Unreferenced`, and the
  `Backend_Unavailable` result is explicitly ambiguous by contract. Worth
  fixing for symmetry, not a defect I can demonstrate.
- **O2** (`catalogs.adb:8776-9040`) — CONFIRMED by reading:
  `Complete_Multipart_Upload` fills `Retired_Payloads` only from
  `Collect_Multipart_Payloads`, and never calls
  `Append_Version_Annotation_Payloads_Internal`, unlike `Put_Object`
  (`6066`, `6087`) and the delete paths (`6500`, `6554`). Annotation payload
  files of replaced generations are orphaned. Below the rubric: the catalog
  rows go away with the generation, and startup reclamation removes the
  files, so this is a bounded disk leak, not incorrectness.
- **O3** (`catalogs.adb:7981-7988, 8122-8218`) — accurate; scalability, not
  correctness. It does compound BACKEND-SQLITE-3, because a long listing is
  what makes another request's deadline expire while it waits for the gate.
- **O4** — accurate and out of area (the memory backend behaves the same).
- **O5** (`docs/architecture/sqlite-backend.md:20-23`) — CONFIRMED, and
  promoted into BACKEND-SQLITE-1 above as the documented invariant the code
  breaks, rather than left as free-standing drift.
- **O6** (`flyology_object_storage_sqlite_durability.c:35-38`) — the Windows
  `sync_path` really does open with `GENERIC_READ` only. I could not test it:
  `docs/architecture/sqlite-backend.md:159` names Linux and macOS as the
  CI-qualified targets. UNVERIFIABLE here; would need a Windows host.
- **O7**, **O8**, **O12** — accurate readings of narrow, externally triggered
  or practically impossible situations; below the rubric and not
  demonstrable in this harness.
- **O9** (`catalogs.adb:918-928`) — accurate: `Gate.Acquire` is an
  unconditional entry and ignores `Token`/`Deadline`. On its own it is
  latency; `repro_sqlite_3b` shows it is also the amplifier that makes
  BACKEND-SQLITE-3 easy to trigger under load, so a fix for the P0 should
  consider it.
- **O10**, **O11**, **O13** — accurate; policy value, diagnostics, and a
  correct-for-the-admitted-alphabet SQL detail respectively.
