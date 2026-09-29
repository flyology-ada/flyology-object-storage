Title: The annotation qualification record claims SQLite corpus evidence that no test produces
Labels: bug, documentation
Refs: BACKEND-SQLITE-2, BACKEND-SQLITE-3

## Summary

The object-annotation qualification record names SQLite among the implementations and then states that the maintained backend and server corpora exercise annotation behaviour, including copy-directive behaviour, "across the implementations". No SQLite-backed test performs any annotation operation, and the only black-box corpus run against the SQLite server has no annotation coverage at all. A reader auditing the record concludes that SQLite annotation copy is qualified, when in fact the first CopyObject of any annotated SQLite object fails and can leave the store answering nothing.

## Problem

Commit `5fe6e3e`. This is contract drift between a qualification document and the maintained tests, so there is no runtime reproduction; the evidence is the document text and the absence of any annotation call in the SQLite-backed suites.

The record names the three implementations (`docs/qualification/object-annotations-backend-server.md:26-27`):

```
Memory, pure-files, and SQLite implement the same interface. Pure-files keeps
annotation payloads in external files. SQLite schema version 23 records
```

and then states the coverage claim (`docs/qualification/object-annotations-backend-server.md:42-46`):

```
CopyObject applies the parsed annotation directive to actual destination
state: COPY preserves the selected source generation's annotations, while
EXCLUDE publishes none. The maintained backend and server corpora exercise
payload, checksum, version, list, missing, condition, and copy-directive
behavior across the implementations.
```

The SQLite suite calls no annotation operation:

```
$ rg -c "Put_Object_Annotation|Get_Object_Annotation|Delete_Object_Annotation|List_Object_Annotations" sqlite/tests/src/flyology_object_storage_sqlite_tests.adb
exit 1
```

`rg` exits 1 with no output, meaning zero matching lines. The only `annotation` matches in that file are migration fixtures such as the repeated `"DROP TABLE object_annotations;"` at `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb:551` through `:963`, the schema check at `:1861`, and empty annotation arguments passed to the catalog at `:3397-3398` and `:3439-3440`:

```ada
         Retired_Annotations, Result,
         Annotations => Catalogs.Annotation_Copy_Record_Vectors.Empty_Vector);
```

The black-box corpus has no annotation coverage either:

```
$ rg -ci annotation tests/src/s3_implementation_corpus.adb
exit 1
```

and that corpus is the only one run against the SQLite server. The script selects the SQLite server binary (`tests/scripts/test-flyology-server.sh:39-42`):

```
  sqlite)
    (cd "$PROJECT_DIR/sqlite/tests" && alr -n build)
    SERVER="$PROJECT_DIR/sqlite/tests/bin/s3_sqlite_server"
    ;;
```

and drives it with that corpus alone (`tests/scripts/test-flyology-server.sh:106-116`):

```
  FLYOLOGY_S3_IMPLEMENTATION="flyology-$BACKEND" \
    "$SCRIPT_DIR/run-s3-implementation.sh" \
    "http://127.0.0.1:$PORT" \
    "http://host.docker.internal:$PORT" \
    "flyology-$BACKEND-corpus-$$" "$ACCESS_KEY" "$SECRET_KEY" yes
  if [ "$BACKEND" = files ] || [ "$BACKEND" = sqlite ]; then
    RESTART_BUCKET="flyology-$BACKEND-restart-$$"
    TIMESTAMP=$(date -u +%Y%m%dT%H%M%SZ)
    FLYOLOGY_S3_IMPLEMENTATION="flyology-$BACKEND" \
      "$PROJECT_DIR/tests/bin/s3_implementation_corpus" \
      "http://127.0.0.1:$PORT" "$RESTART_BUCKET" "$TIMESTAMP" \
      restart-prepare
```

`run-s3-implementation.sh` invokes the same `./bin/s3_implementation_corpus` binary at `tests/scripts/run-s3-implementation.sh:51`, `:60` and `:94`.

Annotation behaviour is exercised, but against two backends only. The class-wide exerciser is declared over `Backends.Backend'Class` (`tests/src/object_storage_test_cases.adb:19555-19557`):

```ada
   procedure Exercise_Object_Annotations
     (Store  : in out Flyology.Object_Storage.Backends.Backend'Class;
      Bucket : String)
```

its copy-directive assertions are at `tests/src/object_storage_test_cases.adb:19660-19675`, and it is driven twice (`tests/src/object_storage_test_cases.adb:19734` and `:19743`):

```ada
         Exercise_Object_Annotations (Store, "memory-annotation-bucket");
         Exercise_Object_Annotations (Store, "files-annotation-bucket");
```

against a memory store declared at `:19732` and a pure-files store opened at `:19740-19741`. It is never driven against a SQLite store, because it lives in the body of a root-crate suite that the separate SQLite suite does not call.

The backend's own architecture document does not fill the gap either:

```
$ rg -ci annotation docs/architecture/sqlite-backend.md
exit 1
```

## Failure scenario

A maintainer or auditor reads `docs/qualification/object-annotations-backend-server.md`. Line 26 tells them that memory, pure-files and SQLite implement the same interface, and lines 44 to 46 tell them that the maintained corpora exercise copy-directive behaviour across the implementations. They conclude that a CopyObject of an annotated object has been verified on the SQLite backend, and treat that path as qualified.

What the maintained tests actually run on SQLite is the SQLite suite, which never calls `Put_Object_Annotation` or any sibling, and the black-box corpus, which contains no annotation request. Nothing in either exercises an annotation operation against a SQLite store. The paths the record presents as covered are exactly the ones where the first CopyObject of an annotated source raises out of the backend, reported as {{ISSUE:BACKEND-SQLITE-2}}, and where the same failure inside the lookup's exception handler leaves the catalog gate held so the store stops answering every operation, reported as {{ISSUE:BACKEND-SQLITE-3}}.

## What should happen

The qualification record states the coverage that exists. Either the corpora exercise annotation behaviour against a SQLite store, so that "across the implementations" at `docs/qualification/object-annotations-backend-server.md:44-46` is accurate, or the sentence names the implementations it actually covers.

## Suggested treatment

Prefer closing the coverage gap over narrowing the claim, because the gap conceals two live defects. `sqlite/tests/flyology_object_storage_sqlite_tests.gpr:5` already puts `../../tests/src/` on the SQLite suite's source path:

```
   for Source_Dirs use ("src/", "config/", "../../tests/src/");
```

so the smallest change is to promote `Exercise_Object_Annotations` from the private body of `tests/src/object_storage_test_cases.adb:19555-19696` into the visible `Flyology.Object_Storage.Backends.Testing` package (`tests/src/flyology-object_storage-backends-testing.ads` and `.adb`), leave the two existing drivers in `tests/src/object_storage_test_cases.adb` at `:19734` and `:19743` calling it, and add a third driver in `sqlite/tests/src/flyology_object_storage_sqlite_tests.adb` against a SQLite store on a scratch root. That exerciser already asserts both copy directives at `tests/src/object_storage_test_cases.adb:19660-19675`, so it fails today on the first annotated copy.

The alternative, if annotation coverage is deliberately not wanted on this backend, is to rewrite the sentence at `docs/qualification/object-annotations-backend-server.md:44-46` to name the memory and pure-files implementations explicitly, and to say that the SQLite implementation is covered only by its own catalog tests. That leaves the defects unguarded but stops the record from overstating the evidence.

There is no program for this issue, and no existing test asserts the wrong behaviour.

## Severity

A qualification record overstates the evidence behind it: it presents annotation behaviour, including copy directives, as corpus-verified across three implementations when one of the three has no annotation coverage of any kind. Nothing misbehaves at run time because of this document, so the direct impact is on anyone auditing or relying on the record rather than on a running store. It matters because the uncovered path is where two reachable defects live, one of which stops the store answering. Not reproduced.
