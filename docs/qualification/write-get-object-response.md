# WriteGetObjectResponse dispatcher profile

WriteGetObjectResponse is implemented as a public server provider boundary.
There is no Low_Level or Objects client request, composable client operation,
synchronous client wrapper, Finish path, or client response decoder. A caller
supplies `Object_Lambda_Responses.Provider` to the server application and owns
the actual execution machinery.

The private server recognizes only exact `POST /WriteGetObjectResponse` with no
query. It requires secure HTTPS with the exact `UNSIGNED-PAYLOAD` SigV4 payload
marker. The signed `x-amz-request-route` and `x-amz-request-token` headers must
each occur once and carry a nonempty text-safe value. The Host must begin with
the exact route followed by a dot, preserving the pinned Object Lambda host
prefix relationship without inventing endpoint discovery or rewriting.

Authentication precedes route, header, payload-policy, and body diagnostics.
The server validates every modeled forwarded response control, preserves
case-fold-unique user metadata in physical order, enforces checksum one-of and
decoded-length rules, and lends the non-rewindable body source to exactly one
synchronous provider call. Field identity is structurally typed; field values
remain exact validated text rather than Ada scalar values.

The provider owns token authenticity, expiry, route binding, atomic single-use
consumption, pending GetObject lookup, backpressure, and final delivery. The
library adds no token store, scheduler, detached task, resource policy, or
automatic replay. Borrowed route, token, principal, response, cancellation,
deadline, and body values may not escape the synchronous call.

Backend coverage is supplied by this caller-owned response-delivery provider,
not by the bucket or object persistence backend. `Delivered` is accepted only
after the provider consumes the entire body and means that the complete
response reached the pending caller. `Invalid_Token` maps to ValidationError.
The provider may return `Invalid_Token` only before token consumption,
pending-response admission, and any body read; a later token rejection maps to
InternalError. Provider exceptions, unread `Delivered`, and `Delivery_Failed`
also map to InternalError without replay. Cancellation and timeout propagate.
After possible admission, their delivery outcome remains provider-reconciled
unknown.

After `Delivery_Failed`, only the caller provider has token and pending-response
state from which to reconcile. The library has no independent observation that
can prove completion or causation, upgrade certainty, or authorize replay.
Directory-bucket and access-point endpoint discovery and external AWS Object
Lambda interoperability are not qualified.

Qualification remains conditional on every command in the single
`write_get_object_response` lane succeeding. The dedicated source verifier pins
the dispatcher and ownership boundary, the model verifier pins the 46-member
request inventory, and the maintained corpus, coverage, GNATdoc, and repository
gates retain the implementation evidence.
