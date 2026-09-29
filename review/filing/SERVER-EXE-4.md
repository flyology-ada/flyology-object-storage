Title: A failed start prints only the outcome name, discarding the supervisor's child, endpoint and exception
Labels: bug
Refs: none

## Summary

When a child generation terminates with an exception, the supervisor hands back the child's identity and a bounded termination summary carrying the exception name and up to 512 characters of message, but the executable prints only `Result.Outcome'Image`. A management listener that cannot bind therefore produces exactly one line, `object-storage server stopped: STARTUP_FAILED`, and the exception never reaches GNAT's unhandled-exception reporter either. A port already in use, a permission problem, an `FLYOLOGY_S3_PORT` equal to `FLYOLOGY_ADMIN_PORT` and an exhausted restart budget all read the same, and the S3 child's earlier `READY` line makes the output look like a healthy start followed by an unexplained failure.

## Problem

Commit `5fe6e3e`.

The report discards every field but the outcome (`server/src/flyology_object_storage_server_runtime.adb:1074-1081`):

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

`Result.Child`, `Result.Generation` and `Result.Termination` are never read, although the pinned flyology 0.1.1-dev release fills all of them (`flyology-supervision.ads:436-442`):

```ada
   type Supervisor_Result is record
      Outcome     : Supervisor_Outcome := Shutdown_Completed;
      Child       : Child_Id := Child_Id'First;
      Generation  : Supervision.Generation := Supervision.Generation'First;
      Termination : Termination_Summary;
      Incident    : Incident_Context := No_Incident;
   end record;
```

and the summary retains the exception name and message (`flyology-supervision.ads:177-191`):

```ada
   type Termination_Summary is record
      Kind           : Termination_Kind := No_Termination;
      Exception_Id   : Ada.Exceptions.Exception_Id :=
        Ada.Exceptions.Null_Id;
      Exception_Name_Length : Supervision.Exception_Name_Length := 0;
      Exception_Name_Truncated : Boolean := False;
      Exception_Name : String (1 .. Maximum_Exception_Name_Length) :=
        (others => ' ');
      Task_Id        : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Null_Task_Id;
      Message_Length : Diagnostic_Length := 0;
      Message_Truncated : Boolean := False;
      Message        : String (1 .. Maximum_Diagnostic_Length) :=
        (others => ' ');
   end record;
```

with `Maximum_Diagnostic_Length` of 512 (`flyology-supervision.ads:150`).

The management listener's bind has no handler, so `Socket_Error` escapes the generation and is what the supervisor classifies (`server/src/flyology_object_storage_server_runtime.adb:922-925`):

```ada
      Sockets.Bind_Socket
        (Listener, Sockets.Network_Endpoint
           (Sockets.Loopback_IPv4, Configuration.Admin_Port));
      Sockets.Listen_Socket (Listener, Length => 64);
```

The exception does not reach the main procedure's handler either, because `Runtime` catches everything and returns normally (`server/src/flyology_object_storage_server_runtime.adb:1082-1089`), and the supervisor outcome path never raises. The contrast is visible in the same executable: a failure before the supervisor starts does name its cause (`server/src/flyology_object_storage_server.adb:92-98`):

```ada
exception
   when Error : others =>
      Admin_Credentials.Wipe (Password);
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "object-storage server startup failed: " &
         Ada.Exceptions.Exception_Information (Error));
      raise;
```

Nothing catches the conflict earlier, because `Configuration.Load` validates neither port availability nor an S3 port equal to the management port (`server/src/flyology_object_storage_server_configuration.adb:67-70`):

```ada
      Result.S3_Port := Flyology.IO.Sockets.Port'Value
        (Environment ("FLYOLOGY_S3_PORT", "9000"));
      Result.Admin_Port := Flyology.IO.Sockets.Port'Value
        (Environment ("FLYOLOGY_ADMIN_PORT", "9001"));
```

so the supervisor is the first place the conflict is observed.

No existing test asserts the wrong behaviour. `expect_startup_failure` checks only that the process exits non-zero (`server/tests/scripts/test.sh:343-353`):

```sh
expect_startup_failure() {
  local name=$1
  shift
  if env -i PATH="$PATH" \
    FLYOLOGY_ADMIN_CREDENTIALS_FILE="$RUN_ROOT/$name-admin.credentials" \
    "$@" "$SERVER" >"$RUN_ROOT/$name.log" 2>&1
  then
    echo "server unexpectedly accepted invalid configuration: $name" >&2
    exit 1
  fi
}
```

and every case it drives fails before the supervisor starts, in the path that does print `Exception_Information`. Nothing provokes a child-generation failure, so nothing has to change.

## What happens now

Spike: the program below holds a loopback port with a `python3` listener, starts the built executable with `FLYOLOGY_ADMIN_PORT` set to that port, captures stdout and stderr, and asserts that the failure diagnostic names at least one of the failing child, the endpoint it tried to bind, or the exception. It scopes the assertion to the failure report itself, because the `BOOTSTRAP ADMIN` banner and the credentials path are printed on every run and say nothing about the failure.

```sh
diagnostics=$(sed -n '/object-storage server stopped:/,$p' "$work/err")
...
if printf '%s' "$diagnostics" | grep -qi 'admin\|management\|workbench\|child'; then
  named_child=0
...
if printf '%s' "$diagnostics" | grep -q ":$busy"; then
  named_endpoint=0
...
if printf '%s' "$diagnostics" | grep -qi 'socket_error\|address already in use\|EADDRINUSE\|exception'; then
  named_exception=0
```

Output, exit status 1, with the scratch credentials path elided:

```
  -- another process holds 127.0.0.1:59950 (a port already in use is the common operator mistake)
  -- server exit status: 1
  -- stdout:
       READY s3 http://127.0.0.1:59957 backend=memory
  -- stderr:
       BOOTSTRAP ADMIN username=admin password=f84f1a225733d287b624d0f727bb3b21091afc80b516bf26
       Store this password now; it will not be shown again. credentials=<scratch>/admin.credentials
       object-storage server stopped: STARTUP_FAILED
  -- failure diagnostic under test:
       object-storage server stopped: STARTUP_FAILED
  ok: control: a management bind failure gives a non-zero exit status
  ok: control: the executable reports that the server stopped
  -- diagnostic names the failing child: no
  -- diagnostic names the endpoint 127.0.0.1:59950: no
  -- diagnostic names the exception: no
  FAILED: the startup-failure diagnostic names the failing child, the endpoint, or the exception
  -- control (pre-supervisor failure, bad backend name), stderr:
       raised CONSTRAINT_ERROR : FLYOLOGY_OBJECT_STORAGE_BACKEND must be memory, files, or sqlite
  ok: control: a configuration failure before the supervisor names its cause
BUG REPRODUCED: 1 failed expectation(s)
```

The password shown in that capture belongs to a throwaway server on a temporary root and is not a live credential. The controls establish both halves of the gap: the failure is detected, since the exit status is 1 and the stopped line is printed, and the executable is capable of naming a cause, since a configuration failure before the supervisor prints the exception text. The S3 child had already announced `READY s3 http://127.0.0.1:59957`, so the operator sees a listener come up and then an unexplained stop.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

A failed start must name what failed. The supervisor already hands back the failing child, the generation and a bounded summary with the exception name and up to 512 characters of message (`flyology-supervision.ads:177-191,436-442`), so the operator diagnostic should distinguish a busy port from a permission problem, an asset failure or an exhausted restart budget.

## Suggested treatment

Extend the report at `server/src/flyology_object_storage_server_runtime.adb:1074-1081` to print `Result.Child`, `Result.Generation` and the retained termination text beside the outcome, using the summary's accessors so the fixed-length storage is trimmed to its meaningful prefix. Something of the shape

```ada
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "object-storage server stopped: " & Result.Outcome'Image &
         " child=" & Result.Child'Image &
         " generation=" & Result.Generation'Image &
         " exception=" &
           Flyology.Supervision.Exception_Name_Text (Result.Termination) &
         " message=" &
           Flyology.Supervision.Message_Text (Result.Termination));
```

closes the defect without changing any interface value: the fields already exist, the two accessors that trim the fixed-length storage are already published at `flyology-supervision.ads:197-205`, and the executable already writes to standard error on this path. Two smaller choices are worth settling while making it. Whether the child identifiers are printed as their enumeral image or mapped to the names the `READY` lines use, `s3` and `admin`, is a presentation choice. Whether the same detail is printed for `Recovery_Exhausted` and `Failure_Escalated`, which take the identical path, is the other; printing it for every non-`Shutdown_Completed` outcome is the simplest and matches the existing condition.

The regression test belongs in `server/tests/scripts/test.sh`, beside `expect_startup_failure` at `:343-353`. The new case has to provoke a failure inside a child generation rather than before the supervisor, which the existing cases do not: hold a loopback port, start the server with `FLYOLOGY_ADMIN_PORT` set to it, and assert that stderr names the failing child, the endpoint, or the exception, in addition to the non-zero exit the existing helper checks. The spike is the test.

## Severity

Every distinct startup failure inside a child generation is reported as one enumeral, so an operator has no way to tell a busy port from a permission problem or an exhausted restart budget, and the preceding `READY s3` line points at the wrong listener. A port already in use is a common operator mistake, not an unusual input, and it is reached with the default configuration on a host where something else already holds port 9001. No data is wrong and nothing is unsafe: the process fails closed with a non-zero exit status. Deterministic.
