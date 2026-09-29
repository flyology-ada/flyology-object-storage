Title: Two servers can open one files root at once because Files.Open takes no lock, unlike SQLite.Open
Labels: bug
Refs: SERVER-EXE-3

## Summary

The executable offers one `FLYOLOGY_OBJECT_STORAGE_ROOT` variable for both persistent backends, and only one of them enforces the exclusive ownership the architecture document requires. `SQLite.Open` takes a non-blocking `flock` on a lock file in the root and refuses a second process with a named error; `Files.Open` takes no lock of any kind. A second server pointed at a live files root therefore starts, and its `Open` recursively deletes `<root>/tmp`, which is not a startup-only directory but the staging target the first, still running process uses for bucket creation, object publication, tag replacement and multipart completion.

## Problem

Commit `5fe6e3e`.

The SQLite backend acquires an exclusive root lock (`sqlite/src/flyology-object_storage-backends-sqlite.adb:107-118`):

```ada
   function Acquire_Root_Lock (Path : String) return System.Address is
      package CS renames Interfaces.C.Strings;
      Value  : CS.chars_ptr := CS.New_String (Path);
      Handle : System.Address;
   begin
      Handle := Acquire_Root_Lock_C (Value);
      CS.Free (Value);
      if Handle = System.Null_Address then
         raise Configuration_Error with
           "could not acquire exclusive SQLite backend root lock";
      end if;
      return Handle;
```

called from `Open` before anything is swept (`sqlite/src/flyology-object_storage-backends-sqlite.adb:301-305`):

```ada
         Result.Lock.Handle := Acquire_Root_Lock
           (Join (US.To_String (Full), Lock_Name));
         Catalogs.Open (Result.Catalog, Catalog_Path (Result));
         Clean_Directory (Result, Staging_Path (Result), False);
         Clean_Directory (Result, Objects_Path (Result), True);
```

`Files.Open` has no equivalent. Its whole body is `src/flyology-object_storage-backends-files.adb:3514-3573`, and the only guards are symlink and directory-kind checks before the sweep (`:3549-3564`):

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
```

The directory that sweep removes is the live staging area, not a startup-only scratch space (`src/flyology-object_storage-backends-files.adb:364-365`):

```ada
   function Temp_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "tmp"));
```

Ordinary operations stage inside it throughout the process lifetime: `Create_Bucket` at `:3606`, `Put_Bucket_Tags` at `:3902`, `Put_Object_Internal` at `:7102`, `Copy_Object` at `:7673`, `Put_Object_Tags` at `:9887`, `Put_Multipart_Part` at `:10884` and `Complete_Multipart_Upload` at `:11848`, among many more uses of `Temp_Path (Item)` in the same body. Retained multipart upload state is not in that tree, since uploads live under `buckets/<bucket>/multipart/` (`src/flyology-object_storage-backends-files.adb:402-403`), which the sweep does not touch. What a second `Open` can remove is a staged temporary that one of those publications is in the middle of writing, so the damage is bounded to transient staging.

The documents state exclusivity as a precondition on the operator and do not promise that the code enforces it. `docs/architecture/files-layout.md:3-4`:

```
The files backend requires exclusive ownership of its configured root by one
process.
```

`README.md:36` repeats it as a property of the backend, "for one process owning an exclusive storage root", and `docs/architecture/files-layout.md:85` treats a breach as the operator's:

```
concurrent external mutation violates the backend's exclusive-root contract.
```

So the files backend is not breaking a documented promise of enforcement. What makes this a defect is that the executable presents one variable for both persistent backends and enforces the precondition for exactly one of them, so the same operator mistake is refused with a named error on SQLite and silently accepted on files.

Nothing tests it: `server/tests/scripts/test.sh` never starts two servers on one root, so no existing test asserts the wrong behaviour and none has to change.

## What happens now

Spike: the program below starts one server on a fresh files root, places a sentinel file inside the live `<root>/tmp/`, starts a second server on the same root, and asserts that the second is refused or that the sentinel survives. The control repeats the identical two-process attempt on a SQLite root.

```sh
echo "sentinel: transient staging artefact of the live owning process" \
  >"$fstore/tmp/owner-staging.tmp"
...
p2=$(launch files "$fstore" "$work/f2.cred" "$work/f2.log"); pids="$pids $p2"
if settle "$work/f2.log" "$p2"; then f2_started=0; else f2_started=1; fi
...
check "$([ $f2_started -ne 0 ] && echo 0 || echo 1)" \
  "files: a second server is refused a root a live server already owns"
check "$survived" \
  "files: ... or at least leaves the live root's tmp/ contents in place"
```

Output, exit status 1, with the scratch directory names elided:

```
  -- server 1 owns <scratch>/files-root:
       READY s3 http://127.0.0.1:60041 backend=files
       READY admin http://127.0.0.1:60042/
  -- placed <scratch>/files-root/tmp/owner-staging.tmp while server 1 is live
  -- server 2 on the same root:
       READY s3 http://127.0.0.1:60048 backend=files
       READY admin http://127.0.0.1:60049/
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

The sentinel stands in for the first process's transient staging artifacts and is created by the program. What the run demonstrates is that a second process empties a directory a live process owns, and that the first process keeps running unaware. It does not demonstrate destruction of a real in-flight staging file, which needs a timing race that was not attempted.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

The same operator mistake should have the same outcome for both persistent backends the executable offers. A second process pointed at a files root that a live process already owns should be refused with a named error, as `sqlite/src/flyology-object_storage-backends-sqlite.adb:107-118` refuses it, rather than starting and emptying the first process's staging directory.

## Suggested treatment

The smallest fix is to give `Files.Open` the lock the SQLite backend already has: take `flock(LOCK_EX | LOCK_NB)` on a lock file in the root at the start of `src/flyology-object_storage-backends-files.adb:3514-3573`, before the `tmp` sweep at `:3549-3564`, and raise `Configuration_Error` with a named message when it cannot be acquired. The C helper the SQLite backend imports and the `Root_Lock` finalization that releases the handle are both already written, so this is a small change in mechanism.

It still needs a maintainer decision, because it puts a new artifact and a new failure mode into the files layout under the "Decision authority" section of `AGENTS.md`:

- A lock file inside the root, matching `.flyology-object-storage.lock` for SQLite. It adds a name in the root that `docs/architecture/files-layout.md` has to describe, and it makes the files backend fail to open on filesystems without working advisory locks, where it opens today.
- A lock file outside the root, chosen by the caller or the executable. This keeps the layout unchanged, at the cost of a new configuration surface and of a lock that does not travel with the store.
- No lock, and instead a refusal to sweep `<root>/tmp` when it is not empty, so a live process's staging is never removed by a second opener. This is weaker: two processes would still write to one root.

The choice interacts with the layout marker discussed in {{ISSUE:SERVER-EXE-3}}, since a marker file and a lock file could be the same artifact or two different ones, and both change what an `Open` requires of a directory.

The regression test belongs in `server/tests/scripts/test.sh`, which already starts a server per backend at `:458-471`: a case that starts a second server on the same files root while the first is live and asserts that it is refused, mirroring the SQLite control the reproduction above already passes. At the backend level, `tests/src/files_open_probe.adb` is the existing black-box opener, used by `tests/scripts/test.sh:16-25` for the symlinked-staging case; a second-opener case belongs beside it, asserting that a second `Files.Open` on a root an open `Store` still holds raises `Configuration_Error`. The spike is the test.

## Severity

A second server pointed at a live files root starts silently and empties the running process's staging directory, which is reached by an overlapping restart, a misconfigured supervisor unit, or an operator starting a second instance on a different port. The missing refusal is deterministic and so is the emptying. The harm beyond that is narrower: the destroyed data is transient staging rather than acknowledged writes, multipart upload state under `buckets/<bucket>/multipart/` is not touched, and losing a staged record that the first process is mid-way through publishing needs a timing race that was not demonstrated. The same mistake on a SQLite root is already refused with a named error. Files backend only.
