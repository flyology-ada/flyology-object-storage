#!/usr/bin/env python3
"""Fail closed on the Files supplied-ETag hashing boundary."""

from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
FILES_BODY = ROOT / "src" / "flyology-object_storage-backends-files.adb"


class Evidence_Error(RuntimeError):
    """One reviewed Files supplied-ETag invariant changed."""


def fail(message: str) -> None:
    raise Evidence_Error(message)


def source(path: Path) -> str:
    if not path.is_file() or path.is_symlink():
        fail(f"missing or unsafe source: {path}")
    raw = path.read_bytes()
    if b"\r" in raw:
        fail(f"noncanonical CR byte: {path}")
    return raw.decode("utf-8")


def require_once(text: str, fragment: str, label: str) -> None:
    count = text.count(fragment)
    if count != 1:
        fail(f"{label}: expected one occurrence, found {count}")


def unique_region(text: str, start: str, end: str, label: str) -> str:
    require_once(text, start, f"{label} start")
    first = text.index(start)
    last = text.find(end, first + len(start))
    if last < 0:
        fail(f"{label}: end boundary is missing")
    return text[first : last + len(end)]


WRITE_AND_HASH = """\
               SIO.Write (File, Buffer (Buffer'First .. Last));
               if Generate_ETag then
                  GNAT.MD5.Update (Hash, Buffer (Buffer'First .. Last));
               end if;
               if Options.Checksum.Algorithm /= No_Checksum then
                  Checksum_Engine.Update
                    (Direct_Hash, Buffer (Buffer'First .. Last));
               end if;"""


def verify(candidate: str) -> None:
    put = unique_region(
        candidate,
        "   procedure Put_Object_Internal\n",
        "   end Put_Object_Internal;",
        "Put_Object_Internal",
    )
    require_once(
        put,
        "Generate_ETag : constant Boolean := "
        "US.Length (Options.Entity_Tag) = 0;",
        "supplied ETag decision",
    )
    require_once(put, WRITE_AND_HASH, "body write and checksum ordering")
    require_once(
        put,
        "Info.Entity_Tag := US.To_Unbounded_String "
        "(GNAT.MD5.Digest (Hash));",
        "generated ETag digest",
    )
    if put.count("if Generate_ETag then") != 2:
        fail("complete-object ETag generation must have exactly two guards")
    if put.count("GNAT.MD5.Update") != 1:
        fail("complete-object body must have exactly one MD5 update")
    if put.count("Checksum_Engine.Update") != 1:
        fail("complete-object body must have exactly one checksum update")


def expect_rejected(original: str, candidate: str, label: str) -> None:
    if candidate == original:
        fail(f"negative did not change candidate: {label}")
    try:
        verify(candidate)
    except Evidence_Error:
        return
    fail(f"negative candidate was accepted: {label}")


def main() -> None:
    body = source(FILES_BODY)
    verify(body)

    unguarded = WRITE_AND_HASH.replace(
        "               if Generate_ETag then\n"
        "                  GNAT.MD5.Update",
        "               GNAT.MD5.Update",
        1,
    ).replace(
        "               end if;\n"
        "               if Options.Checksum.Algorithm",
        "               if Options.Checksum.Algorithm",
        1,
    )
    expect_rejected(
        body,
        body.replace(WRITE_AND_HASH, unguarded, 1),
        "unguarded supplied-ETag MD5 update",
    )

    inverted = WRITE_AND_HASH.replace(
        "if Generate_ETag then", "if not Generate_ETag then", 1
    )
    expect_rejected(
        body,
        body.replace(WRITE_AND_HASH, inverted, 1),
        "inverted generated-ETag guard",
    )

    checksum_guarded = WRITE_AND_HASH.replace(
        "               end if;\n"
        "               if Options.Checksum.Algorithm",
        "               if Options.Checksum.Algorithm",
        1,
    ).replace(
        "               end if;",
        "               end if;\n               end if;",
        1,
    )
    expect_rejected(
        body,
        body.replace(WRITE_AND_HASH, checksum_guarded, 1),
        "configured checksum nested under ETag generation",
    )

    print("Files supplied-ETag hashing evidence: OK")


if __name__ == "__main__":
    main()
