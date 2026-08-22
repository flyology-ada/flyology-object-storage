# Flyology Object Storage Server

This independent executable crate runs the S3 application with the memory,
files, or SQLite backend. It consumes indexed `flyology_http=0.1.2`; only the
two sibling development crates are path-pinned inside this repository.

The first server slice provides a bounded HTTP/1.1 listener under a Flyology
static supervisor. SIGTERM requests an orderly stop, interrupts accepts and
active connection handlers, and allows a ten-second drain. It also bootstraps
an `admin` identity on first start. The management listener and browser
workbench are the next slices; until they land this binary exposes only the S3
endpoint.

The generated 192-bit administrator password is printed once to standard
error. Only a random 256-bit salt and PBKDF2-HMAC-SHA256 verifier are persisted
in an owner-owned mode-0600 regular file, atomically without replacing a file
created by a racing process. The 600,000-iteration work factor follows the
current [OWASP password-storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
Existing credential files with broader permissions, symlinks, malformed
fields, or an unknown format stop startup.

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
- `FLYOLOGY_ADMIN_CREDENTIALS_FILE` defaults to `admin.credentials` inside a
  persistent backend root, or `./flyology-admin.credentials` for memory.

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
