Title: Any FLYOLOGY_OBJECT_STORAGE_ROOT is opened as a store, deleting its pre-existing tmp and staging content
Labels: bug
Refs: SERVER-EXE-5

## Summary

The executable checks only that `FLYOLOGY_OBJECT_STORAGE_ROOT` is non-empty and passes it straight to `Files.Open` or `SQLite.Open`, both of which treat the directory as a store they already own. The files backend recursively deletes a pre-existing `<root>/tmp` tree, and the SQLite backend deletes every ordinary file under `<root>/staging` and every ordinary file under `<root>/objects` that the freshly created catalog does not reference. Neither `Open` looks for any marker distinguishing a store from an arbitrary directory, and no layout marker is defined anywhere. An operator who mistypes the root loses that content silently and irreversibly, while the server prints `READY` and serves normally.

## Problem

Commit `5fe6e3e`.

The executable's only check on the root is that it is not empty (`server/src/flyology_object_storage_server_configuration.adb:42-46`):

```ada
      if Result.Backend /= Memory and then Root'Length = 0 then
         raise Constraint_Error with
           "FLYOLOGY_OBJECT_STORAGE_ROOT is required for " & Backend_Name;
      end if;
      Result.Storage_Root := To_Unbounded_String (Root);
```

and the value goes straight to the backend (`server/src/flyology_object_storage_server.adb:64-68`):

```ada
      when Configuration.Files =>
         declare
            Store : Flyology.Object_Storage.Backends.Files.Store :=
              Flyology.Object_Storage.Backends.Files.Open
                (US.To_String (Settings.Storage_Root));
```

with the same shape for SQLite (`server/src/flyology_object_storage_server.adb:78-82`).

`Files.Open` deletes a pre-existing `tmp` tree after checking only that it is not a symlink and is a directory (`src/flyology-object_storage-backends-files.adb:3549-3564`):

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

`Validate_Tree_Symlink_Free` raises only for a depth above 64, a symlink, a missing or non-directory path, or an entry that is neither a directory nor an ordinary file (`src/flyology-object_storage-backends-files.adb:296-301,315-323`), so a tree of ordinary files and directories passes the check and is then deleted. The swept directory is exactly the store's staging area (`src/flyology-object_storage-backends-files.adb:364-365`):

```ada
   function Temp_Path (Item : Store) return String is
     (Join (Root_Directory (Item), "tmp"));
```

`SQLite.Open` sweeps two directories of its own (`sqlite/src/flyology-object_storage-backends-sqlite.adb:301-305`):

```ada
         Result.Lock.Handle := Acquire_Root_Lock
           (Join (US.To_String (Full), Lock_Name));
         Catalogs.Open (Result.Catalog, Catalog_Path (Result));
         Clean_Directory (Result, Staging_Path (Result), False);
         Clean_Directory (Result, Objects_Path (Result), True);
```

and `Clean_Directory` deletes every entry that a brand-new catalog does not reference (`sqlite/src/flyology-object_storage-backends-sqlite.adb:264-270`):

```ada
            if not Check_References
              or else not Is_Payload_Name (Name)
              or else not Catalogs.Payload_Referenced (Item.Catalog, Name)
            then
               Ada.Directories.Delete_File
                 (Ada.Directories.Full_Name (Directory_Entry));
            end if;
```

There is no layout marker for either backend to check. `docs/architecture/files-layout.md` states the precondition on the operator at `:3-4`:

```
The files backend requires exclusive ownership of its configured root by one
process.
```

and at `:65-67` says what opening does with it:

```
bucket directories are staged beneath `tmp/` and atomically renamed into the
namespace; opening the exclusively owned root removes interrupted staging
artifacts before accepting work.
```

Grepping that document for `marker`, `.flyology`, `layout file` or `sentinel` returns nothing: it defines no on-disk artifact that `Open` could require before treating a directory as its own. The SQLite root's `catalog.sqlite3` and `.flyology-object-storage.lock` are created by `Open`, not required by it, so they are not a marker either. The variable's documentation carries no precondition at all (`server/README.md:64`):

```
- `FLYOLOGY_OBJECT_STORAGE_ROOT` is mandatory for files and SQLite.
```

No existing test covers it. `server/tests/scripts/test.sh:458-471` always points each backend at a fresh `$RUN_ROOT/<backend>-store`, so no test opens a store on a directory that already holds unrelated content, and none has to change.

## What happens now

Spike, at the backend: the program below creates a scratch directory containing `tmp/keep.txt`, `tmp/nested/deep.txt` and `notes/readme.txt`, runs a control on a dedicated empty root by opening it and creating a bucket, then calls `Files.Open` on the foreign directory and asserts that `Open` either raised `Configuration_Error` or left the sentinels in place.

```ada
      declare
         Store : Files.Store := Files.Open (Foreign);
         pragma Unreferenced (Store);
      begin
         Note ("Files.Open (foreign root) returned normally");
      end;
   exception
      when Error : Files.Configuration_Error =>
         Refused := True;
...
   Check (Refused or else Ada.Directories.Exists (Keep),
          "Files.Open either refuses a root that is not a store or leaves " &
          "<root>/tmp/keep.txt in place");
```

Output, exit status 1, with the scratch directory names elided:

```
  -- foreign root = <scratch directory>
  --   before: tmp/keep.txt exists        = TRUE
  --   before: tmp/nested/deep.txt exists = TRUE
  --   before: notes/readme.txt exists    = TRUE
  -- control: dedicated empty root <scratch directory>
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

Spike, through the documented variable: a second program starts the built server itself with `FLYOLOGY_OBJECT_STORAGE_ROOT` pointed at prepared foreign directories, once for each persistent backend, waits for both `READY` lines, stops the server, and compares the directory listings.

```sh
  env -i PATH="$PATH" \
    FLYOLOGY_ADMIN_ASSET_ROOT="$assets" \
    FLYOLOGY_OBJECT_STORAGE_BACKEND="$backend" \
    FLYOLOGY_OBJECT_STORAGE_ROOT="$store" \
```

Output, exit status 1, with the scratch directory names elided:

```
  -- files root <scratch>/files-root before:
       ./notes/readme.txt
       ./tmp/keep.txt
       ./tmp/nested/deep.txt
  -- files server reached READY:
       READY s3 http://127.0.0.1:59782 backend=files
       READY admin http://127.0.0.1:59783/
  -- files root after:
       ./notes/readme.txt
  FAILED: files: the server refuses a root that is not a store, or leaves tmp/keep.txt in place
  FAILED: files: ... and leaves tmp/nested/deep.txt in place
  ok: control: files: a sibling directory the store does not use survives
  -- sqlite root <scratch>/sqlite-root before:
       ./notes/readme.txt
       ./objects/keep.txt
       ./staging/keep.txt
  -- sqlite server reached READY:
       READY s3 http://127.0.0.1:59789 backend=sqlite
       READY admin http://127.0.0.1:59790/
  -- sqlite root after:
       ./.flyology-object-storage.lock
       ./catalog.sqlite3
       ./notes/readme.txt
  FAILED: sqlite: the server refuses a root that is not a store, or leaves objects/keep.txt in place
  FAILED: sqlite: ... and leaves staging/keep.txt in place
  ok: control: sqlite: a sibling directory the store does not use survives
BUG REPRODUCED: 4 failed expectation(s)
```

The `notes/readme.txt` control survives both backends. That is what makes the loss hard to notice: the sweep is confined to the store's own directory names, so an operator inspecting the rest of the root sees nothing missing.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

Opening a directory that has never been a store must either be refused with a named error, or must leave that directory's existing content in place. `docs/architecture/files-layout.md:3-4` states exclusive ownership as a precondition and `:65-67` describes the sweep as something done to an exclusively owned root, but nothing in the code establishes that the root at hand is one, and `server/README.md:64` documents the variable without the precondition.

## Suggested treatment

The fix needs a maintainer decision, both on where it sits and on whether it introduces a new on-disk artifact, which is a new externally visible precondition under the "Decision authority" section of `AGENTS.md`:

- Define a layout marker file. The first `Open` of an empty or absent root writes it, and every later `Open` requires it before treating the directory as a store, refusing with `Configuration_Error` otherwise. This is a new on-disk artifact, a new name in the root, and a new failure mode for a store created by an earlier version, which will not carry the marker.
- Refuse a root that already holds entries the layout does not define, so a directory containing `notes/` or an unexpected `tmp/` is rejected without any new artifact. This changes what `Open` accepts for existing deployments whose roots hold operator files beside the store.
- Validate the root in the executable before opening it, leaving both backends unchanged. This protects the documented variable but leaves a library caller with the same behaviour.

The choice also decides which layer changes. The destructive code is the backends' `Open` (`src/flyology-object_storage-backends-files.adb:3549-3564` and `sqlite/src/flyology-object_storage-backends-sqlite.adb:301-305`), while the reachable path from one documented, unvalidated variable is the executable's (`server/src/flyology_object_storage_server_configuration.adb:42-46` and `server/src/flyology_object_storage_server.adb:64-68,78-82`). A related asymmetry in the same two `Open` procedures is reported as {{ISSUE:SERVER-EXE-5}}.

The regression test belongs in two places. For the executable, add a case to `server/tests/scripts/test.sh` beside the per-backend loop at `:458-471` that points a files root at a directory holding `tmp/keep.txt` and a SQLite root at one holding `objects/keep.txt` and `staging/keep.txt`, and asserts that the server either fails to start or leaves those files in place. For the backend, `tests/src/files_open_probe.adb` already exists as the black-box opener used by `tests/scripts/test.sh:16-25` for the symlinked-staging case; a foreign-root case belongs beside it, asserting the same expectation directly against `Files.Open`. The spikes are the tests.

## Severity

An operator who mistypes the root, `/var` for `/var/lib/flyology`, a home directory that already has a `tmp`, or a checkout with a scratch area, loses that content with no diagnostic and no way to recover it, and the server reports itself ready. The data destroyed is never the store's own acknowledged writes, and it needs a root that is not a dedicated directory, which is an operator mistake rather than ordinary use. On macOS `/tmp` and `/var` are themselves symlinks, so a root spelled that way is refused by the root check at `src/flyology-object_storage-backends-files.adb:3526-3527` and a Linux deployment is the exposed case for those two names; the reproduction above uses ordinary directories instead, and the defect does not depend on the platform. Deterministic.
