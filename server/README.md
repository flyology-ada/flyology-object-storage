# Flyology Object Storage Server

This independent executable crate runs the S3 application with the memory,
files, or SQLite backend. It consumes indexed `flyology_http=0.1.2`; only the
two sibling development crates are path-pinned inside this repository.

The server provides bounded S3 and management HTTP/1.1 listeners under a
dependency-ordered Flyology static supervisor. SIGTERM requests an orderly
stop, interrupts accepts and active connection handlers, and allows a
ten-second S3 drain. The management child depends on the S3 child, so an S3
generation failure restarts the workbench generation as well.

The management listener is always bound to `127.0.0.1`. Its browser workbench
uses the psqlbench example's compact instrument-panel structure without
copying its replication-specific complexity. The current vertical slice signs
in with the bootstrapped `admin` identity and reports the actual S3 address and
port, region, selected backend, authenticated session, and supervised service
relationship. It also presents a read-only, name-ordered bucket inventory from
an atomic backend snapshot, bounded to 256 visible entries with an explicit
truncation state. Administrators can create a validated bucket inline; the
request requires an exact loopback Origin and uses the backend's atomic create
primitive. They can also delete an empty bucket through an inline, two-step
confirmation. Deletion requires the same exact loopback Origin, uses the
backend's atomic delete primitive, and reports a non-empty bucket as a conflict
without changing it. Selecting a bucket opens a read-only object inventory
with exact 64-bit sizes and timestamps, byte-safe URL-encoded keys, and opaque
pagination capped at 64 objects per browser request. Object mutation remains
on the signed S3 endpoint rather than being implied by incomplete browser
controls. The five-second health poll updates runtime state without rebuilding
inventory controls, so keyboard focus and an inline delete confirmation remain
stable; explicit refresh and successful mutations reconcile the inventory.

The generated 192-bit administrator password is printed once to standard
error. Only a random 256-bit salt and PBKDF2-HMAC-SHA256 verifier are persisted
in an owner-owned mode-0600 regular file, atomically without replacing a file
created by a racing process. The 600,000-iteration work factor follows the
current [OWASP password-storage guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).
Existing credential files with broader permissions, symlinks, malformed
fields, or an unknown format stop startup.

Successful login creates a random 256-bit, memory-only session with a 12-hour
maximum lifetime. The cookie is `HttpOnly`, `SameSite=Strict`, path-scoped to
the management listener, and deliberately lacks `Secure` because this listener
is hard-bound to loopback HTTP. Host and Origin checks reject DNS-rebinding and
cross-origin requests; duplicate Cookie headers and duplicate session cookies
fail closed. The workbench assets are external for straightforward packaging
but their exact SHA-256 digests are compiled into the binary. Missing or
modified HTML, CSS, or JavaScript stops startup before either listener starts.

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
- `FLYOLOGY_ADMIN_PORT` defaults to `9001`; the address is always
  `127.0.0.1`, and `0` selects an ephemeral test port.
- `FLYOLOGY_ADMIN_CREDENTIALS_FILE` defaults to `admin.credentials` inside a
  persistent backend root, or `./flyology-admin.credentials` for memory.
- `FLYOLOGY_ADMIN_ASSET_ROOT` selects the integrity-pinned `index.html`,
  `app.css`, and `app.js` directory. By default the server finds `assets` from
  the crate directory or `server/assets` from the repository root.

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
backends, including independent service-level bucket listing immediately
after bucket creation. It also verifies invalid configuration, asset tamper
rejection, bootstrap and persisted login, same-origin and Host enforcement,
session cookie shape and revocation, byte-exact asset delivery, actual endpoint
status, authenticated empty and populated bucket inventories, and supervised
SIGTERM shutdown. Bucket creation tests cover missing/wrong Origin, invalid
names, success, duplicate conflict, and visibility through the inventory API.
Bucket deletion tests cover unauthenticated, missing/hostile-Origin, and wrong
media-type rejection, successful empty deletion, a repeated not-found
response, disappearance from inventory, and preservation of a non-empty bucket
after conflict. Object inventory tests cover authentication, missing and
duplicate parameters, invalid limits and continuation tokens, exact decimal
size transport, URL-safe arbitrary-key display, pagination, and missing
buckets.
