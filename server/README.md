# Flyology Object Storage Server

This independent executable crate runs the S3 application with the memory,
files, or SQLite backend. It consumes indexed `flyology_http=0.1.2`; only the
two sibling development crates are path-pinned inside this repository.

The first server slice provides a bounded HTTP/1.1 listener under a Flyology
static supervisor. SIGTERM requests an orderly stop, interrupts accepts and
active connection handlers, and allows a ten-second drain. The management
listener, bootstrapped administrator identity, and browser workbench are the
next slices; until they land this binary exposes only the S3 endpoint.

Required environment:

- `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` configure the current S3
  principal; `AWS_SESSION_TOKEN` is optional.
- `FLYOLOGY_OBJECT_STORAGE_BACKEND` is `memory`, `files` (default), or
  `sqlite`.
- `FLYOLOGY_OBJECT_STORAGE_ROOT` is mandatory for files and SQLite.

Optional environment:

- `AWS_REGION` defaults to `us-east-1`.
- `FLYOLOGY_S3_BIND` defaults to the safe loopback address `127.0.0.1`.
- `FLYOLOGY_S3_PORT` defaults to `9000`; use `0` for an ephemeral test port.
- `FLYOLOGY_S3_CAPACITY` defaults to 128 concurrent connection handlers.

Build and run:

```sh
cd server
alr -n build
FLYOLOGY_OBJECT_STORAGE_BACKEND=files \
FLYOLOGY_OBJECT_STORAGE_ROOT=/srv/flyology-objects \
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... \
  ./bin/flyology_object_storage_server
```

`alr test` runs the same digest-pinned s5cmd black-box slice against all three
backends and verifies invalid configuration plus supervised SIGTERM shutdown.
