# Bug reproduction programs

Each `src/repro_<id>.adb` demonstrates one finding from the correctness
review. A program asserts the CORRECT behavior, so on the current sources it
prints `BUG REPRODUCED` and exits 1; after a fix it prints `PASS` and exits 0.
A hang is reported as exit 124 by the `timeout` wrapper; exit 2 is a build
failure.

```sh
cd tests/repros
./run.sh repro_<id>          # build one program and run it (60 s limit)
./run.sh repro_<id> 10       # custom time limit in seconds
./run-all.sh                 # every program, one line each
```

`src/repro_support.ad?` provides `Check`/`Note`/`Finish` and raw HTTP
response helpers. `src/repro_s3_server.ad?` provides an in-process S3
application over the memory backend with SigV4-signed raw requests, a
loopback listener for real sockets, and direct access to the backend store.
Programs that need the files backend create a directory under the scratch
area and open `Flyology.Object_Storage.Backends.Files` on it; programs that
need a real third-party server say so in their header and are run with the
Docker scripts under `tests/scripts/`.

`run.sh` serializes builds with a lock directory so concurrent agents can
share the object directory and the Alire cache safely.
