# RenameObject negative-capability profile

RenameObject is covered only for the maintained local server's authenticated
general-purpose-bucket rejection boundary. The operation remains
`Not_Exposed`: there is no public Low_Level or Objects request, synchronous
wrapper, composable operation, Finish path, response decoder, or client
GNATdoc claim.

The private server recognizes only exact bodyless `PUT ?renameObject` forms,
including the modeled `x-id=RenameObject` association.
It requires one nonempty, text-safe `x-amz-rename-source` that names an object
in the destination bucket and carries no source query. Every modeled source
and destination condition is singleton and syntactically valid. An optional
client token is singleton, nonempty, and text-safe.

These checks establish request syntax only. Conditions are never evaluated,
the client token is never generated, persisted, or bound to parameters, and
the route implements no operation-specific token length limit or
`IdempotencyParameterMismatch` behavior. The pinned model's token shape has no
bound or pattern, so this profile does not turn documentation prose into a
public or private policy constant.

After authentication and request validation, the route consults only the
existing shared `Head_Bucket` capability. A missing bucket remains
`NoSuchBucket`. Every existing maintained bucket is a general-purpose bucket
and returns `NotImplemented`. The route does not inspect source or destination
objects and never reports success, calls Copy_Object or Delete_Object, or
mutates backend state.

This boundary does not claim directory-bucket persistence or sessions, an
atomic move, overwrite behavior, condition results, source or destination
existence results, token idempotency, automatic replay, causal reconciliation,
access-point routing, or external-provider interoperability. A later object
observation cannot establish that a lost RenameObject request caused state.

Qualification remains conditional on every command in the single
`rename_object` lane succeeding. The dedicated preparation verifier pins the
negative-capability source boundary, the generated-model verifier pins the
wire inventory, and the maintained root test and repository gates retain the
shared backend and signed server evidence.
