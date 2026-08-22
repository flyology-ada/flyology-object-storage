# SPARK assurance boundary

SPARK is a release gate for deterministic object-storage logic. The target is
at least 90% of non-I/O decision logic in SPARK-enabled units, with 100% of
generated checks proved and no high-confidence findings. This includes:

- S3 name, key, header, range, pagination, and size validation;
- SigV4 canonicalization and signing inputs;
- multipart and versioning state transitions;
- filesystem key encoding and record arithmetic;
- transfer scheduling limits and result aggregation.

HTTP sockets, filesystem syscalls, SQLite C calls, cryptographic library calls,
and Flyology tasking are narrow non-SPARK adapters. Their SPARK-facing
contracts carry bounds and state guarantees; they require black-box,
fault-injection, and sanitizer tests.

Every proof run records its invocation header. CI starts with level 0 and
warnings as errors, then publishes GNATprove statistics. A release requires
all checks in SPARK-enabled units to prove. No Assume, False_Positive
annotation, imported ghost axiom, or body-level SPARK_Mode Off is accepted as
a proof fix.

The current forced manifest covers domain validation, the exhaustive pinned
116-operation/718-shape S3 model descriptor, S3 range/multipart rules, SigV4
byte canonicalization, bounded decimal/size/boolean wire scalars, and
canonical fixed-length base64 checksums. The latest manifest-wide result is
recorded in `proof-status.md`; the bucket-versioning scoped result below is
retained as targeted evidence. XML/Ada SAX orchestration remains
outside SPARK; attacker-controlled scalar decisions are delegated to the
proved wire core. The manifest also includes the bounded request-target
classifier, semantic SigV4 timestamp validation, RFC byte-range parser, and
the shared atomic whole/bounded/open/suffix range resolver. Automatic
multipart planning uses the same proved core for part-size validity,
overflow-safe ceiling division, the 10,000-part ceiling, and the 50 TiB object
bound.

Bucket-versioning independent-field merge is implemented in the SPARK-enabled
domain unit and reused by the memory and files backends. Its postcondition
states the exact preservation rule for each Unconfigured update field; the
unit corpus also exhausts all 81 current/update enum combinations. The
final exact scoped report proves 2/2 checks for the merge, including its
functional postcondition and termination. The subsequent eight-unit widening
proves 595/595 checks with warnings as errors and no justified, unproved, or
assumed checks. SQLite uses an equivalent single-statement `CASE` update under
its serialized catalog gate and is checked through merge, reopen, and
migration tests. Exact commands and historical domain-unit evidence are
recorded in `proof-status.md` and the qualification report.
