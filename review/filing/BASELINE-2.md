Title: The two s5cmd-driven CI jobs report success while the conformance script fails and reaches no server
Labels: bug
Refs: CLIENT-LOW-1

## Summary

Two workflow steps pipe a conformance script into `tee` under GitHub's default `bash -e` shell, which sets no `pipefail`, so the step takes `tee`'s exit status and a failing script can never fail the job. Independently, the servers those scripts start are reachable only on the host loopback, while the s5cmd oracle runs in a container reaching `host.docker.internal`, which on a Linux runner is the docker0 gateway and refuses the connection. In the scheduled run 34031107803 of 2026-09-06 all three affected jobs report success while their logs show the very first s5cmd call failing with `connection refused`. The s5cmd byte and deletion oracles that the repository presents as its stock-client evidence have therefore never run in CI.

## Problem

Commit `5fe6e3e`.

The black-box step (`.github/workflows/ci.yml:268-272`):

```yaml
      - name: Run digest-pinned s5cmd oracle against memory backend
        run: |
          mkdir -p obj/ci
          ./tests/scripts/test-flyology-server.sh memory \
            2>&1 | tee obj/ci/s3-smoke.log
```

and the reference-smoke step, matrixed over `rustfs` and `seaweedfs` (`.github/workflows/ci.yml:299-305`):

```yaml
      - name: Run bounded permissive-reference slice
        env:
          FLYOLOGY_S3_SERVER_RUNNER: ${{ github.workspace }}/tests/scripts/run-s3-server-slice.sh
        run: |
          mkdir -p obj/ci
          ./tests/scripts/test-${{ matrix.reference }}.sh \
            2>&1 | tee obj/ci/reference-${{ matrix.reference }}.log
```

`grep -n 'shell:\|pipefail' .github/workflows/ci.yml` prints nothing, so both steps run under GitHub's default `bash -e {0}`. Without `pipefail` a pipeline's status is its last command's, which is `tee`, and `tee` succeeds whenever it can write the log.

The second cause is the endpoint. The three reference servers are published on the host loopback only:

```sh
tests/scripts/test-minio.sh:26:  --publish "127.0.0.1::9000" \
tests/scripts/test-rustfs.sh:29:  --publish "127.0.0.1::9000" \
tests/scripts/test-seaweedfs.sh:34:  --publish "127.0.0.1::8333" \
```

and the Flyology test server binds loopback directly rather than publishing anything (`tests/src/s3_server_harness.adb:120-121`):

```ada
   Sockets.Bind_Socket
     (Listener, Sockets.Network_Endpoint (Sockets.Loopback_IPv4, Port));
```

The client, however, is a sibling container told to reach the host gateway (`tests/scripts/run-s3-server-slice.sh:59-66`):

```sh
s5cmd() {
  docker run --rm --add-host host.docker.internal:host-gateway \
    --volume "$PAYLOAD_ROOT:/data:ro" \
    --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
    --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
    --env AWS_REGION=us-east-1 \
    "$S5CMD_IMAGE" --retry-count 0 --endpoint-url "$ORACLE_ENDPOINT" "$@"
}
```

with the same `--add-host` in the full corpus runner (`tests/scripts/run-s3-implementation.sh:38-44`):

```sh
s5cmd() {
  docker run --rm --add-host host.docker.internal:host-gateway \
    --env "AWS_ACCESS_KEY_ID=$ACCESS_KEY" \
    --env "AWS_SECRET_ACCESS_KEY=$SECRET_KEY" \
    --env AWS_REGION=us-east-1 \
    "$S5CMD_IMAGE" --endpoint-url "$ORACLE_ENDPOINT" "$@"
}
```

and the endpoint passed to that runner is built on that name (`tests/scripts/test-flyology-server.sh:92-96`):

```sh
if ! env \
  FLYOLOGY_S3_IMPLEMENTATION="flyology-$BACKEND" \
  FLYOLOGY_S3_SERVER_REVISION="$SERVER_REVISION" \
  "$RUNNER" "http://host.docker.internal:$PORT" \
  "flyology-$BACKEND-slice-$$" "$ACCESS_KEY" "$SECRET_KEY"
```

On a Linux runner `host-gateway` is the docker0 address 172.17.0.1, which nothing is listening on, because the port was published to 127.0.0.1.

Both causes are visible in the scheduled run 34031107803 of 2026-09-06, on `main`, triggered by schedule. The `Reference smoke (rustfs)` job log records the first s5cmd call:

```
2026-09-06T11:45:26.6251385Z ERROR "mb s3://flyology-rustfs-corpus-2326": RequestError: send request failed caused by: Put "http://host.docker.internal:32768/flyology-rustfs-corpus-2326": dial tcp 172.17.0.1:32768: connect: connection refused
```

and the `S3 black-box smoke (memory + s5cmd)` job log records the same failure and the script's own diagnosis:

```
2026-09-06T12:06:21.3598338Z ERROR "mb s3://flyology-memory-slice-2648": RequestError: send request failed caused by: Put "http://host.docker.internal:37319/flyology-memory-slice-2648": dial tcp 172.17.0.1:37319: connect: connection refused
2026-09-06T12:06:21.4264723Z PORT 37319
2026-09-06T12:06:21.4266741Z Flyology memory endpoint runner failed
```

`Flyology memory endpoint runner failed` is the message the script prints immediately before `exit 1` (`tests/scripts/test-flyology-server.sh:97-101`):

```sh
then
  cat "$SERVER_LOG" >&2
  echo "Flyology $BACKEND endpoint runner failed" >&2
  exit 1
fi
```

`gh run view 34031107803` nonetheless reports every one of the three jobs as passing:

```
✓ main CI · 34031107803
Triggered via schedule about 18 hours ago
...
✓ Reference smoke (rustfs) in 15s (ID 101480737338)
✓ Reference smoke (seaweedfs) in 19s (ID 101480737386)
✓ S3 black-box smoke (memory + s5cmd) in 8m33s (ID 101482308887)
```

The 15 and 19 second durations are the whole reference jobs, image pull included, against a nominal 30-minute budget.

The claim the jobs are supposed to support is published (`docs/qualification/continuous-integration.md:25-28`):

```
Every pull request and push also runs the digest-pinned, MIT-licensed s5cmd
black-box corpus against the memory server. A scheduled lane runs a bounded
copy of the same wire slice against the digest-pinned Apache-2.0 RustFS and
SeaweedFS references.
```

Neither of those runs has happened on a Linux runner. Nothing in the repository tests the workflow for this. The maintained static workflow checker `tools/ci/verify-workflow-policy.sh`, run from `tools/ci/check-repository.sh:41-42` with its negative-oracle suite `tools/ci/test-workflow-policy.sh`, asserts action pinning, credential persistence, secret use and exact tool versions, and has no rule about piped steps or step-status propagation.

There is a second consequence, which the masked jobs would have surfaced. Run on macOS, where Docker forwards the loopback publication so the corpus does reach the server, `tests/scripts/test-minio.sh`, `test-rustfs.sh` and `test-seaweedfs.sh` all fail at the same point, the corpus's third HeadObject case (`tests/src/s3_implementation_corpus.adb:1144-1157`):

```ada
         declare
            Parameters : Low_Level.Head_Object_Parameters;
         begin
            Parameters.Version_ID := US.To_Unbounded_String ("null");
            Parameters.Request_Payer := US.To_Unbounded_String ("requester");
            Parameters.Checksum_Mode := True;
```

with `raised FLYOLOGY.OBJECT_STORAGE.CLIENT.LOW_LEVEL.INVALID_RESPONSE : HeadObject response does not match prepared request`. That is a client-side defect, reported separately as {{ISSUE:CLIENT-LOW-1}}, and it is not caused by the workflow. It is relevant here because it is a real, reproducible third-party interop failure that the scheduled reference jobs are meant to catch and did not, since they never reached a server and could not have failed if they had.

## What happens now

Spike: the shell program below runs the workflow step's verbatim shape around a script that exits 1, first under GitHub's default `bash -e` and then, as a control, under `bash -eo pipefail`; asks Docker what `--publish 127.0.0.1::9000` actually binds; and greps the workflow for `shell:` or `pipefail`. It asserts the correct behaviour, that a step written the way the workflow writes it fails when the script fails.

```sh
printf '#!/bin/sh\necho "Flyology memory endpoint runner failed" >&2\nexit 1\n' >"$script"
...
# 1. The workflow step, verbatim shape, under GitHub's default shell.
bash -e -c "$script 2>&1 | tee /dev/null" >/dev/null 2>&1
...
# 2. Control: the same step with pipefail (what 'shell: bash' would give).
bash -eo pipefail -c "$script 2>&1 | tee /dev/null" >/dev/null 2>&1
...
cid=$(docker run --detach --rm --publish 127.0.0.1::9000 alpine:3 sleep 30 2>/dev/null || true)
mapping=$(docker port "$cid" 9000/tcp 2>/dev/null || true)
```

Output, exit status 1:

```
  -- default shell 'bash -e', script exits 1 through '| tee': step status 0
  FAILED: a failing conformance script fails the CI step as written (bash -e, pipe to tee)
  -- control 'bash -eo pipefail': step status 1
  ok: control: with pipefail the same step fails
  -- docker port for '--publish 127.0.0.1::9000': 127.0.0.1:32803
  -- the published port is bound to the host loopback only
  FAILED: ci.yml sets 'shell: bash' or pipefail for the piped steps
BUG REPRODUCED: 2 failed expectation(s)
```

A script that exits 1 through `| tee` gives the step status 0 under the default shell and status 1 with `pipefail`, and the publication is bound to 127.0.0.1 only, which is what the docker0 gateway address in the CI logs cannot reach.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire. The published-port demonstration used the local Docker daemon; the jobs it describes run on `ubuntu-latest`.

## What should happen

A failing conformance script must fail its CI step, and the s5cmd container must be able to reach the server it is pointed at on a Linux runner, so that the black-box corpus and the reference slice actually execute the runs `docs/qualification/continuous-integration.md:25-28` says they execute.

## Suggested treatment

Two independent changes are needed, and fixing only the first turns the jobs red without making them meaningful, since the endpoint would still be unreachable.

For the step status, add `shell: bash` to the two steps at `.github/workflows/ci.yml:268-272` and `:299-305`; GitHub runs that shell as `bash --noprofile --norc -eo pipefail {0}`, so the pipeline takes the script's status. Adding `set -o pipefail` as the first line of each `run:` block has the same effect and is a smaller diff.

For the endpoint, the address is a maintainer decision, because each option changes what the runner exposes and to whom:

- Publish the reference servers on all interfaces instead of `127.0.0.1` (`tests/scripts/test-minio.sh:26`, `test-rustfs.sh:29`, `test-seaweedfs.sh:34`) and bind the Flyology harness beyond `Loopback_IPv4` (`tests/src/s3_server_harness.adb:120-121`), so the docker0 gateway address the client already uses resolves to a listening socket. This exposes the test server on the runner's other interfaces for the life of the job.
- Run the s5cmd container with `--network host` instead of `--add-host host.docker.internal:host-gateway` (`tests/scripts/run-s3-server-slice.sh:60`, `tests/scripts/run-s3-implementation.sh:39`) and point it at `127.0.0.1`, keeping the loopback publication. Host networking behaves differently on macOS, so the local and CI paths would diverge.
- Put the server and the client on the same user-defined Docker network and address the server by container name. This does not work for the Flyology harness, which is a host process rather than a container.

The regression test belongs in the maintained workflow checker `tools/ci/verify-workflow-policy.sh`, with its rejection fixture in `tools/ci/test-workflow-policy.sh`, both already run by `tools/ci/check-repository.sh:41-42`. The rule to add is that a `run:` block containing a pipeline must be accompanied by `shell: bash` or by `set -o pipefail`, with a mutation fixture that strips it and must be rejected. The spike is the test for the step-status half; the endpoint half is only observable in a job that actually runs, so its evidence is the first passing `mb s3://...` in the job log. No existing check asserts the wrong behaviour, so nothing has to change.

## Severity

The repository's own interop gate cannot fail. Three scheduled jobs report success on runs in which the conformance script demonstrably failed at its first request, so a maintainer reading a green run is told something untrue, and no interop regression on the s5cmd byte, deletion or restart routes can be caught in CI. It is not a latent risk: it has already hidden a real third-party failure, the one reported as {{ISSUE:CLIENT-LOW-1}}, which reproduces on every one of the three reference servers. Both causes are static and reproduce on every Linux runner, and the black-box step also runs on every pull request and push, not only on the schedule. Deterministic.
