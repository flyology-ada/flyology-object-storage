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
canonical fixed-length base64 checksums. Its authoritative level-0 report is
`obj/proof/gnatprove/gnatprove.out`: 405/405 checks proved, zero justified,
zero unproved, and zero `Assume` statements. XML/Ada SAX orchestration remains
outside SPARK; attacker-controlled scalar decisions are delegated to the
proved wire core. The manifest also includes the bounded request-target
classifier, semantic SigV4 timestamp validation, RFC byte-range parser, and
the shared atomic whole/bounded/open/suffix range resolver. Automatic
multipart planning uses the same proved core for part-size validity,
overflow-safe ceiling division, the 10,000-part ceiling, and the 50 TiB object
bound.
