Title: Management route Concurrency and Rate_Per_Second policies are inert because no middleware is installed
Labels: bug
Refs: SERVER-EXE-1

## Summary

Five management routes declare `Concurrency` and `Rate_Per_Second` admission policy, but the router is served with no middleware, so the only readers of those fields are never instantiated and the values have no effect. Fifty simultaneous `POST /api/login` requests from one peer with a wrong password are all admitted and all run a full 600,000-iteration derivation: fifty answers of 401 over 50.35 s, and not one 429 or 503. The declared policy on that route is `Concurrency => 1, Rate_Per_Second => 2`, whose token bucket has a burst capacity equal to the rate, so at most two should have been admitted.

## Problem

Commit `5fe6e3e`.

The login route declares a bucket of two requests per second and a concurrency of one (`server/src/flyology_object_storage_server_runtime.adb:882-887`):

```ada
      State.Routes.Post
        ("/api/login", Login'Access, Name => "admin.login",
         Policy =>
           (Routing.Default_Route_Policy with delta
              Body_Handling => Apps.Buffer_Body, Max_Body => 256,
              Concurrency => 1, Rate_Per_Second => 2));
```

Four more routes carry the same kind of policy: `/api/buckets` GET with `Concurrency => 2, Rate_Per_Second => 4` (`:890-894`), `/api/objects` with the same pair (`:895-899`), `/api/buckets` POST with `Concurrency => 1, Rate_Per_Second => 2` (`:900-906`), `/api/buckets/delete` with the same pair (`:907-913`), and `/api/logout` with `Concurrency => 4, Rate_Per_Second => 4` (`:914-918`).

The management `Handle` serves the router directly (`server/src/flyology_object_storage_server_runtime.adb:847-850`):

```ada
         HTTP.Configure_Ingress_Budget (Client, State.Budget'Access);
         State.Routes.Serve
           (State.Application, Client, Peer, Timeout => 30.0,
            Header_Timeout => 5.0, Token => Cancellation);
```

`rg -n -i 'middleware|bulkhead|rate_limit' server/src/` matches nothing, so no toolkit layer is installed anywhere in the crate.

The library states that the policy fields are read by those layers and by nothing else (pinned flyology_http 0.1.3-dev, `flyology-http-server-routing.ads:81-89`):

```ada
   --  Route-local policy consumed incrementally by optional toolkit layers.
   --  A zero concurrency or rate value means unlimited. CORS_Policy is an
   --  application-defined bounded registry slot interpreted by CORS
   --  middleware; zero means no CORS policy.
   --  @field Body_Handling Request body handling
   --  @field Max_Body Maximum decoded body bytes
   --  @field Timeout Deadline narrowing in seconds; negative preserves it
   --  @field Concurrency Maximum active handlers; zero is unlimited
   --  @field Rate_Per_Second Per-client admission rate; zero is unlimited
```

The two layers that would consume them are shipped and unused. `flyology-http-server-middleware_rate_limits.ads:24-25`:

```ada
   --  Token-bucket middleware. Burst capacity equals the configured route
   --  requests-per-second rate. Rejection is 429 with Retry-After.
```

and `flyology-http-server-middleware_bulkheads.ads:20`:

```ada
   --  Nonblocking bulkhead middleware. Rejection is 503 with Retry-After.
```

Because the library calls the consuming layers optional, this is not a violation of a library contract, and `server/README.md` promises no rate limit. What is wrong is that the executable writes admission policy on five routes, never enforces it, and paces its own test as though the limit existed (`server/tests/scripts/test.sh:102-107`):

```sh
  code=$(admin_request POST "$base/api/login" "$body" "$headers" \
    -H "Origin: $base" \
    --data-binary 'username=admin&password=000000000000000000000000000000000000000000000000')
  test "$code" = 401
  sleep 1
```

No assertion in that script expects a 429 or a 503, and the `sleep 1` between mutating requests passes with or without a limiter, so no existing test asserts the wrong behaviour and none has to change.

## What happens now

Spike: the program below starts the built server on a temporary root with `env -i` and ephemeral ports, then fires fifty barrier-synchronised `POST /api/login` requests with a wrong 48-hex password from one peer, tallies the outcomes and any `Retry-After` headers, and asserts the behaviour the written policy implies, that some requests are rejected with 429 or 503 and that at most the declared burst of two is admitted. The control issues one wrong-password login on its own.

```python
results, lock, gate = [], threading.Lock(), threading.Barrier(count)

def one():
    gate.wait()
    t0 = time.monotonic()
    try:
        c = http.client.HTTPConnection("127.0.0.1", port, timeout=600)
        c.request("POST", "/api/login", body=body,
                  headers={"Host": host, "Origin": f"http://{host}",
                           "Content-Type": "application/x-www-form-urlencoded",
                           "Content-Length": str(len(body))})
        r = c.getresponse(); r.read()
        retry = r.getheader("Retry-After")
        outcome = str(r.status) + (f" Retry-After={retry}" if retry else "")
```

Output, exit status 1:

```
  -- management port 59476; declared policy on /api/login is Concurrency => 1, Rate_Per_Second => 2
  -- 50 simultaneous POST /api/login with a wrong 48-hex password:
      50 x 401
     wall=50.35s min=1.00s median=26.34s max=50.35s
  -- fully processed by a handler (200/401): 50; rejected by a limiter (429/503): 0
  FAILED: a per-client rate limit or bulkhead rejects some of 50 simultaneous logins with 429/503
  -- burst capacity of the declared policy is 2; observed admissions: 50 (wall 50.35s)
  FAILED: a simultaneous burst from one peer admits at most the declared burst of 2
  -- control: one wrong-password login on its own: 401 {"authenticated":false}
  ok: control: a single wrong-password login is answered 401
BUG REPRODUCED: 2 failed expectation(s)
```

All fifty requests are outstanding at once, because the barrier releases them together, and all fifty are run to completion by a handler. The burst is not merely absorbed quickly: it costs 50.35 s of wall time, since each admitted request pays a full derivation on the single event loop, which is the separate defect reported as {{ISSUE:SERVER-EXE-1}}. The minimum latency of 1.00 s is one derivation, so the serialisation is the loop rather than a limiter.

Host: macOS 26.6.2, arm64, GNAT 16.1.0 via Alire.

## What should happen

Either the declared policy is enforced, so a burst from one peer is answered 429 with `Retry-After` or 503 as `flyology-http-server-middleware_rate_limits.ads:24-25` and `flyology-http-server-middleware_bulkheads.ads:20` document, or the routes stop declaring policy that nothing reads. A route that records `Concurrency => 1` and admits fifty concurrent handlers describes a protection the server does not have.

## Suggested treatment

Installing the shipped layers is the smaller change, and it needs a maintainer decision, because both take externally visible resource choices as generic formals under the "Decision authority" section of `AGENTS.md`:

- Instantiate `Middleware_Rate_Limits` over the router's own typed middleware package (`flyology-http-server-routing.ads:36-37`) and register it with `Add_Middleware` (`flyology-http-server-routing.ads:331`) where the routes are registered, so it is in place before `State.Routes.Serve` runs at `server/src/flyology_object_storage_server_runtime.adb:847-850`. Its `Client_Key` formal decides what identifies a client, direct peer address or a trusted-proxy header, and its `Capacity` formal bounds the retained attacker-controlled keys. Both are new policy for a listener that is always bound to loopback.
- Instantiate `Middleware_Bulkheads` as well if the `Concurrency` values are to take effect. Its `Global_Limit` and `Route_Capacity` formals are two more new bounds, and a global limit interacts with the listener's own 32 handler slots.
- Alternatively, drop the `Concurrency` and `Rate_Per_Second` fields from the five route registrations, so the source stops describing an admission bound that does not exist. This closes the discrepancy without adding a limit, and it leaves the login path with no bound at all, which matters because of {{ISSUE:SERVER-EXE-1}}.

The regression test belongs in `server/tests/scripts/test.sh`. If a limiter is installed, the case should fire a simultaneous burst of logins from one peer and assert that at least one response is 429 or 503 and carries `Retry-After`, and that the number fully processed does not exceed the declared burst. The spike is the test. If instead the fields are removed, the assertion is that no route registration carries a `Concurrency` or `Rate_Per_Second` value while no middleware is installed.

## Severity

The management listener has no admission bound of any kind, so any local process that can reach the loopback port can keep fifty full password derivations running, while the route registrations say a burst of two is the limit. On its own the effect is a discrepancy between the written policy and the behaviour, since the listener is loopback-only, the password is 192 bits and brute force stays infeasible. It matters because it is what leaves the expensive login path of {{ISSUE:SERVER-EXE-1}} unbounded, turning a one-second stall into one that lasts as long as an attacker keeps posting. The `Concurrency => 1` intended to serialise bucket creation and deletion is equally absent, although the backends' own atomic primitives keep those operations safe. Deterministic.
