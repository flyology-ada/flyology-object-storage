# Bug reproduction programs (SQLite backend)

Same conventions as `tests/repros/README.md`: each `src/repro_sqlite_<n>.adb`
asserts the CORRECT behaviour, prints `BUG REPRODUCED` and exits 1 on the
current sources, `PASS` and exit 0 after a fix, 124 on a hang, 2 on a build
failure. This crate depends on both `flyology_object_storage` (pinned to the
repository root) and `flyology_object_storage_sqlite` (pinned to `sqlite/`),
and shares the root harness's support units and build lock.

```sh
cd sqlite/tests/repros
./run.sh repro_sqlite_<n>       # build and run one program
./run-all.sh                    # every program, one line each
```
