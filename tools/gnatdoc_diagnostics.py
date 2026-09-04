#!/usr/bin/env python3
"""Fail-closed ownership classification for project diagnostics."""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile
import tomllib
from html.parser import HTMLParser
from pathlib import Path


DIAGNOSTIC = re.compile(
    r"^(?P<source>.+\.(?:adb|ads)):(?P<line>[1-9][0-9]*):"
    r"(?P<column>[1-9][0-9]*): "
    r"(?P<severity>warning|error): (?P<message>\S.*)$"
)
EXPECTED_PUBLIC_SOURCE_COUNT = 42


class Diagnostic_Error(RuntimeError):
    """A diagnostic cannot be accepted by the documentation gate."""


class _Page_Parser(HTMLParser):
    """Extract one GNATdoc unit heading and documented entity sections."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.unit_parts: list[str] = []
        self.sections: list[tuple[str, str]] = []
        self._in_unit = False
        self._in_entity = False
        self._in_comment = False
        self._in_tags = False
        self._entity_parts: list[str] = []
        self._comment_parts: list[str] = []
        self._entity = ""

    def _finish_entity(self) -> None:
        if self._entity:
            self.sections.append(
                (
                    self._entity,
                    " ".join(" ".join(self._comment_parts).split()),
                )
            )
        self._entity = ""
        self._entity_parts = []
        self._comment_parts = []
        self._in_comment = False
        self._in_tags = False

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        del attrs
        if tag == "h1":
            self._in_unit = True
        elif tag == "h4":
            self._finish_entity()
            self._in_entity = True
        elif tag == "p" and self._entity and not self._in_tags:
            self._in_comment = True
        elif tag == "h5":
            self._in_comment = False
            self._in_tags = True

    def handle_endtag(self, tag: str) -> None:
        if tag == "h1":
            self._in_unit = False
        elif tag == "h4":
            self._in_entity = False
            self._entity = " ".join(" ".join(self._entity_parts).split())
        elif tag == "p":
            self._in_comment = False

    def handle_data(self, data: str) -> None:
        if self._in_unit:
            self.unit_parts.append(data)
        elif self._in_entity:
            self._entity_parts.append(data)
        elif self._in_comment:
            self._comment_parts.append(data)

    def close(self) -> None:
        super().close()
        self._finish_entity()

    @property
    def unit(self) -> str:
        return " ".join(" ".join(self.unit_parts).split())


def _same_file(left: Path, right: Path) -> bool:
    """Return whether two existing path spellings identify the same file."""
    try:
        return left.samefile(right)
    except OSError:
        return False


def _is_within(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return any(
            _same_file(candidate, root)
            for candidate in (path, *path.parents)
        )
    else:
        return True


def _source_index(manifest: Path) -> tuple[set[Path], dict[str, set[Path]]]:
    sources: set[Path] = set()
    index: dict[str, set[Path]] = {}
    for number, raw_line in enumerate(
        manifest.read_text(encoding="utf-8", errors="strict").splitlines(), 1
    ):
        value = raw_line.strip()
        if not value:
            raise Diagnostic_Error(
                f"project source manifest line {number} is blank"
            )
        if raw_line != value:
            raise Diagnostic_Error(
                "project source manifest line "
                f"{number} has surrounding whitespace"
            )
        source = Path(value)
        if not source.is_absolute():
            raise Diagnostic_Error(
                f"project source manifest line {number} is not absolute: "
                f"{value}"
            )
        try:
            resolved = source.resolve(strict=True)
        except OSError as error:
            raise Diagnostic_Error(
                f"project source manifest line {number} is invalid: "
                f"{value}: {error}"
            ) from error
        if not resolved.is_file():
            raise Diagnostic_Error(
                "project source manifest line "
                f"{number} is not a regular file: {value}"
            )
        if resolved.suffix not in (".ads", ".adb"):
            raise Diagnostic_Error(
                f"project source manifest line {number} is not Ada source: "
                f"{value}"
            )
        if resolved in sources:
            raise Diagnostic_Error(
                f"project source manifest line {number} is duplicated: "
                f"{value}"
            )
        sources.add(resolved)
        index.setdefault(resolved.name, set()).add(resolved)
    if not sources:
        raise Diagnostic_Error("project source manifest is empty")
    return sources, index


def _dependency_source_index(
    manifest: Path,
) -> tuple[set[Path], dict[str, set[Path]], int]:
    """Parse the exact indented source grammar emitted by ``gprls -d``."""
    sources: set[Path] = set()
    index: dict[str, set[Path]] = {}
    lines = manifest.read_text(
        encoding="utf-8", errors="strict"
    ).splitlines()
    if not lines:
        raise Diagnostic_Error("dependency source manifest is empty")
    for number, raw_line in enumerate(lines, 1):
        match = re.fullmatch(r"(?:   |      )(/.*\.(?:ads|adb))", raw_line)
        if match is None:
            raise Diagnostic_Error(
                "dependency source manifest line "
                f"{number} has invalid gprls -d syntax: {raw_line!r}"
            )
        value = match.group(1)
        source = Path(value)
        try:
            resolved = source.resolve(strict=True)
        except OSError as error:
            raise Diagnostic_Error(
                "dependency source manifest line "
                f"{number} is invalid: {value}: {error}"
            ) from error
        if source != resolved:
            raise Diagnostic_Error(
                "dependency source manifest line "
                f"{number} is not canonical: {value}"
            )
        if not resolved.is_file():
            raise Diagnostic_Error(
                "dependency source manifest line "
                f"{number} is not a regular file: {value}"
            )
        sources.add(resolved)
        index.setdefault(resolved.name, set()).add(resolved)
    return sources, index, len(lines)


def _reject_ambiguous_basenames(
    index: dict[str, set[Path]], context: str
) -> None:
    ambiguous = sorted(
        name for name, paths in index.items() if len(paths) != 1
    )
    if ambiguous:
        raise Diagnostic_Error(
            f"{context} source basename is ambiguous: {ambiguous[0]}"
        )


def normalize_source_manifests(
    direct_manifest: Path,
    dependency_manifest: Path,
    output_manifest: Path,
    repository: Path,
    public_project: Path,
    expected_public_source_count: int = EXPECTED_PUBLIC_SOURCE_COUNT,
) -> tuple[int, int, int, int, int]:
    """Transactionally form the exact active public-documentation closure."""
    check_source_manifest(
        direct_manifest,
        repository,
        public_project,
        expected_public_source_count,
    )
    direct_sources, _ = _source_index(direct_manifest)
    dependency_sources, _, dependency_rows = _dependency_source_index(
        dependency_manifest
    )
    missing_dependency_sources = sorted(
        direct_sources - dependency_sources
    )
    if missing_dependency_sources:
        raise Diagnostic_Error(
            "dependency source closure is missing a direct source: "
            + str(missing_dependency_sources[0])
        )
    sources = direct_sources | dependency_sources
    index: dict[str, set[Path]] = {}
    for source in sources:
        index.setdefault(source.name, set()).add(source)
    _reject_ambiguous_basenames(index, "project")

    direct_path = direct_manifest.resolve(strict=True)
    dependency_path = dependency_manifest.resolve(strict=True)
    if output_manifest.is_symlink():
        raise Diagnostic_Error(
            "canonical source manifest must not be a symbolic link"
        )
    output_parent = output_manifest.parent.resolve(strict=True)
    if not output_parent.is_dir():
        raise Diagnostic_Error(
            f"source manifest parent is not a directory: {output_parent}"
        )
    output_path = output_parent / output_manifest.name
    if output_path in (direct_path, dependency_path):
        raise Diagnostic_Error(
            "canonical source manifest must differ from both raw inputs"
        )
    if output_manifest.exists() and not output_manifest.is_file():
        raise Diagnostic_Error(
            "canonical source manifest is not a regular file: "
            f"{output_manifest}"
        )
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=output_parent,
            prefix=f".{output_manifest.name}.",
            delete=False,
        ) as temporary:
            temporary_path = Path(temporary.name)
            temporary.write(
                "".join(
                    f"{source}\n" for source in sorted(sources, key=str)
                )
            )
        public_sources, dependency_sources_count = check_source_manifest(
            temporary_path,
            repository,
            public_project,
            expected_public_source_count,
        )
        os.replace(temporary_path, output_path)
        temporary_path = None
        return (
            public_sources,
            dependency_sources_count,
            len(direct_sources),
            dependency_rows,
            len(dependency_sources),
        )
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)


def _public_project_sources(
    public_project: Path, repository: Path
) -> set[Path]:
    """Return the exact repository specs owned by the public-doc project."""
    repository = repository.resolve()
    try:
        project = public_project.resolve(strict=True)
    except OSError as error:
        raise Diagnostic_Error(
            f"public documentation project is invalid: {public_project}: "
            f"{error}"
        ) from error
    if not _is_within(project, repository):
        raise Diagnostic_Error(
            "public documentation project is outside the repository: "
            f"{project}"
        )
    text = project.read_text(encoding="utf-8", errors="strict")
    blocks = re.findall(
        r"\bfor\s+Source_Files\s+use\s*\((.*?)\);",
        text,
        flags=re.DOTALL | re.IGNORECASE,
    )
    if len(blocks) != 1:
        raise Diagnostic_Error(
            "public documentation project must declare one Source_Files "
            "list"
        )
    names = re.findall(r'"([^"]+)"', blocks[0])
    if not names:
        raise Diagnostic_Error(
            "public documentation project Source_Files list is empty"
        )
    if len(names) != len(set(names)):
        raise Diagnostic_Error(
            "public documentation project Source_Files list is duplicated"
        )
    invalid = [
        name
        for name in names
        if Path(name).name != name or Path(name).suffix != ".ads"
    ]
    if invalid:
        raise Diagnostic_Error(
            "public documentation project contains a non-spec source: "
            + invalid[0]
        )
    expected: set[Path] = set()
    for name in names:
        source = repository / "src" / name
        try:
            expected.add(source.resolve(strict=True))
        except OSError as error:
            raise Diagnostic_Error(
                f"public documentation source is invalid: {source}: {error}"
            ) from error
    return expected


def check_source_manifest(
    manifest: Path,
    repository: Path,
    public_project: Path,
    expected_public_source_count: int = EXPECTED_PUBLIC_SOURCE_COUNT,
) -> tuple[int, int]:
    """Require the exact public specs plus only external dependencies."""
    repository = repository.resolve()
    sources, _ = _source_index(manifest)
    expected = _public_project_sources(public_project, repository)
    if len(expected) != expected_public_source_count:
        raise Diagnostic_Error(
            "public documentation project source count differs: "
            f"expected {expected_public_source_count}; got {len(expected)}"
        )
    repository_sources = {
        source for source in sources if _is_within(source, repository)
    }
    missing = sorted(
        expected_source
        for expected_source in expected
        if not any(
            _same_file(expected_source, source)
            for source in repository_sources
        )
    )
    extra = sorted(
        source
        for source in repository_sources
        if not any(
            _same_file(source, expected_source)
            for expected_source in expected
        )
    )
    if missing:
        raise Diagnostic_Error(
            "public project source manifest is missing: " + str(missing[0])
        )
    if extra:
        raise Diagnostic_Error(
            "public project source manifest has an unexpected repository "
            "source: "
            + str(extra[0])
        )
    return len(expected), len(sources - repository_sources)


def check_diagnostics(
    log: Path,
    repository: Path,
    source_manifest: Path,
) -> int:
    """Return the number of path-resolved dependency warnings."""
    repository = repository.resolve()
    sources, index = _source_index(source_manifest)
    dependency_warnings = 0

    for number, raw_line in enumerate(
        log.read_text(encoding="utf-8", errors="strict").splitlines(), 1
    ):
        diagnostic_text = raw_line.casefold()
        if (
            "warning:" not in diagnostic_text
            and "error:" not in diagnostic_text
        ):
            continue
        match = DIAGNOSTIC.fullmatch(raw_line)
        if match is None:
            raise Diagnostic_Error(
                f"unclassified project diagnostic at log line "
                f"{number}: "
                f"{raw_line}"
            )
        severity = match.group("severity")
        if severity == "error":
            raise Diagnostic_Error(
                f"project error at log line {number}: {raw_line}"
            )

        source = Path(match.group("source"))
        candidates: set[Path]
        if source.is_absolute() or source.parent != Path("."):
            candidate = (
                source.resolve()
                if source.is_absolute()
                else (repository / source).resolve()
            )
            candidates = {candidate} if candidate in sources else set()
        else:
            candidates = index.get(source.name, set())
        if not candidates:
            raise Diagnostic_Error(
                f"project warning source is not in the active source "
                f"search paths "
                f"at log line {number}: {source}"
            )
        if len(candidates) != 1:
            raise Diagnostic_Error(
                f"project warning source is ambiguous at log line "
                f"{number}: "
                f"{source}"
            )
        if any(_is_within(candidate, repository) for candidate in candidates):
            raise Diagnostic_Error(
                f"repository-owned project warning at log line "
                f"{number}: "
                f"{raw_line}"
            )
        dependency_warnings += 1

    return dependency_warnings


def _selected_apis(
    registry_path: Path, operations: list[str]
) -> list[tuple[str, str, str]]:
    if not operations:
        raise Diagnostic_Error("documentation operation selection is empty")
    duplicates = sorted(
        name for name in set(operations) if operations.count(name) > 1
    )
    if duplicates:
        raise Diagnostic_Error(
            "documentation operation is duplicated: " + ", ".join(duplicates)
        )
    try:
        raw = tomllib.loads(registry_path.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as error:
        raise Diagnostic_Error(
            f"operation registry TOML is invalid: {error}"
        ) from error
    operation_rows = raw.get("operation")
    if not isinstance(operation_rows, list):
        raise Diagnostic_Error("registry operation table is missing")
    entries: dict[str, dict[str, object]] = {}
    for entry in operation_rows:
        if not isinstance(entry, dict) or not isinstance(
            entry.get("name"), str
        ):
            raise Diagnostic_Error("registry operation entry is malformed")
        name = entry["name"]
        if name in entries:
            raise Diagnostic_Error(f"registry operation is duplicated: {name}")
        entries[name] = entry
    missing = sorted(set(operations) - set(entries))
    if missing:
        raise Diagnostic_Error(
            "unknown documentation operation: " + ", ".join(missing)
        )
    result: list[tuple[str, str, str]] = []
    identities: set[tuple[str, str]] = set()
    for operation in operations:
        entry = entries[operation]
        provider = entry.get("public_provider")
        public_name = entry.get("public_name")
        if not isinstance(provider, str) or not provider:
            raise Diagnostic_Error(
                f"documentation provider is missing for {operation}"
            )
        if not isinstance(public_name, str) or not public_name:
            raise Diagnostic_Error(
                f"documentation public name is missing for {operation}"
            )
        identity = (provider.casefold(), public_name.casefold())
        if identity in identities:
            raise Diagnostic_Error(
                "selected public API is ambiguous: "
                f"{provider}.{public_name}"
            )
        identities.add(identity)
        result.append((operation, provider, public_name))
    return result


def _source_comments(
    repository: Path,
    source_manifest: Path,
    provider: str,
    public_name: str,
) -> list[str]:
    sources, _ = _source_index(source_manifest)
    filename = provider.casefold().replace(".", "-") + ".ads"
    candidates = [
        path
        for path in sources
        if path.name.casefold() == filename
        and _is_within(path, repository.resolve())
    ]
    if len(candidates) != 1:
        raise Diagnostic_Error(
            f"public provider source is missing or ambiguous: {provider}"
        )
    lines = candidates[0].read_text(
        encoding="utf-8", errors="strict"
    ).splitlines()
    declaration = re.compile(
        r"^\s+(?:function|procedure)\s+"
        + re.escape(public_name)
        + r"\b",
        re.IGNORECASE,
    )
    comments: list[str] = []
    for index, line in enumerate(lines):
        if line.strip().casefold() == "private":
            break
        if declaration.match(line) is None:
            continue
        comment_lines: list[str] = []
        cursor = index - 1
        while cursor >= 0 and re.match(r"^\s*--", lines[cursor]):
            comment_lines.append(re.sub(r"^\s*--\s?", "", lines[cursor]))
            cursor -= 1
        ordered = list(reversed(comment_lines))
        prose_lines: list[str] = []
        for comment_line in ordered:
            if comment_line.lstrip().startswith("@"):
                break
            prose_lines.append(comment_line)
        comment = " ".join(" ".join(prose_lines).split())
        if not comment:
            raise Diagnostic_Error(
                f"public API lacks adjacent source prose: "
                f"{provider}.{public_name}"
            )
        comments.append(comment)
    if not comments:
        raise Diagnostic_Error(
            f"public API declaration is missing: {provider}.{public_name}"
        )
    normalized = {"".join(comment.split()).casefold() for comment in comments}
    if len(normalized) != len(comments):
        raise Diagnostic_Error(
            f"public API overload comments are ambiguous: "
            f"{provider}.{public_name}"
        )
    return comments


def check_selected_apis(
    site: Path,
    registry_path: Path,
    operations: list[str],
    repository: Path,
    source_manifest: Path,
) -> int:
    """Require fresh GNATdoc entity sections with adjacent documentation."""
    selected = _selected_apis(registry_path, operations)
    if site.is_symlink() or not site.is_dir():
        raise Diagnostic_Error("documentation site is not a directory")
    index = site / "index.html"
    if not index.is_file() or index.stat().st_size == 0:
        raise Diagnostic_Error("documentation site index.html is missing")
    pages: dict[str, list[_Page_Parser]] = {}
    html_paths = sorted(site.rglob("*.html"))
    if not html_paths:
        raise Diagnostic_Error("documentation site contains no HTML")
    symlinks = [path for path in site.rglob("*") if path.is_symlink()]
    if symlinks:
        raise Diagnostic_Error(
            f"documentation site contains a symlink: {symlinks[0]}"
        )
    for path in html_paths:
        parser = _Page_Parser()
        parser.feed(path.read_text(encoding="utf-8", errors="strict"))
        parser.close()
        if parser.unit:
            pages.setdefault(parser.unit, []).append(parser)
    for operation, provider, public_name in selected:
        provider_pages = [
            page
            for unit, unit_pages in pages.items()
            if unit.casefold() == provider.casefold()
            for page in unit_pages
        ]
        if len(provider_pages) != 1:
            raise Diagnostic_Error(
                f"documentation provider page is missing or ambiguous for "
                f"{operation}: {provider}"
            )
        sections = [
            comment
            for name, comment in provider_pages[0].sections
            if name.casefold() == public_name.casefold()
        ]
        if not sections:
            raise Diagnostic_Error(
                f"documentation API is missing for {operation}: {public_name}"
            )
        if any(not comment for comment in sections):
            raise Diagnostic_Error(
                f"documentation API lacks an adjacent comment for "
                f"{operation}: {public_name}"
            )
        source_comments = _source_comments(
            repository, source_manifest, provider, public_name
        )
        if len(sections) != len(source_comments):
            raise Diagnostic_Error(
                f"documentation API overload count differs for {operation}: "
                f"{public_name}"
            )
        html_comments = [
            "".join(comment.split()).casefold() for comment in sections
        ]
        matches: list[int] = []
        for comment in source_comments:
            expected = "".join(comment.split()).casefold()
            candidates = [
                index
                for index, actual in enumerate(html_comments)
                if expected == actual
            ]
            if len(candidates) != 1:
                raise Diagnostic_Error(
                    f"documentation API comment is missing or ambiguous for "
                    f"{operation}: {public_name}"
                )
            matches.append(candidates[0])
        if len(set(matches)) != len(matches):
            raise Diagnostic_Error(
                f"documentation API comment matching is not one-to-one for "
                f"{operation}: {public_name}"
            )
    return len(selected)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", required=True, type=Path)
    parser.add_argument("--sources", required=True, type=Path)
    parser.add_argument("--public-project", required=True, type=Path)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--normalize-sources-only", action="store_true")
    modes.add_argument("--check-sources-only", action="store_true")
    modes.add_argument("--check-log-only", action="store_true")
    parser.add_argument("--direct-sources", type=Path)
    parser.add_argument("--dependency-sources", type=Path)
    parser.add_argument("--log", type=Path)
    parser.add_argument("--site", type=Path)
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--operation", action="append")
    args = parser.parse_args()
    try:
        if args.normalize_sources_only:
            if (
                args.direct_sources is None
                or args.dependency_sources is None
                or args.log is not None
                or args.site is not None
                or args.registry is not None
                or args.operation
            ):
                raise Diagnostic_Error(
                    "source normalization arguments are invalid"
                )
            (
                public_sources,
                dependency_sources,
                direct_sources,
                dependency_rows,
                dependency_unique,
            ) = normalize_source_manifests(
                args.direct_sources,
                args.dependency_sources,
                args.sources,
                args.repository,
                args.public_project,
            )
            print(
                "GNATdoc source closure: "
                f"{direct_sources} direct sources; "
                f"{dependency_rows} dependency rows; "
                f"{dependency_unique} unique dependency-closure sources; "
                f"{public_sources} repository public specs; "
                f"{dependency_sources} dependency sources"
            )
            return 0
        if (
            args.direct_sources is not None
            or args.dependency_sources is not None
        ):
            raise Diagnostic_Error(
                "raw source manifests require source normalization mode"
            )
        public_sources, dependency_sources = check_source_manifest(
            args.sources, args.repository, args.public_project
        )
        if args.check_sources_only:
            print(
                "GNATdoc source manifest: "
                f"{public_sources} repository public specs; "
                f"{dependency_sources} dependency sources"
            )
            return 0
        if args.check_log_only:
            if (
                args.log is None
                or args.site is not None
                or args.registry is not None
                or args.operation
            ):
                raise Diagnostic_Error(
                    "documentation log-only validation arguments are "
                    "invalid"
                )
            dependency_warnings = check_diagnostics(
                args.log, args.repository, args.sources
            )
            print(
                "Documentation materialization diagnostics: "
                f"{dependency_warnings} dependency warnings classified by "
                "source path; 0 repository warnings; 0 errors"
            )
            return 0
        if (
            args.log is None
            or args.site is None
            or args.registry is None
            or not args.operation
        ):
            raise Diagnostic_Error(
                "complete GNATdoc validation arguments are required"
            )
        dependency_warnings = check_diagnostics(
            args.log, args.repository, args.sources
        )
        api_count = check_selected_apis(
            args.site,
            args.registry,
            args.operation,
            args.repository,
            args.sources,
        )
    except (
        Diagnostic_Error,
        OSError,
        UnicodeError,
        tomllib.TOMLDecodeError,
    ) as error:
        print(f"GNATdoc diagnostic gate failed: {error}", file=sys.stderr)
        return 1
    print(
        "GNATdoc diagnostics: "
        f"{dependency_warnings} dependency warnings classified by "
        "source path; "
        "0 repository warnings; 0 errors; "
        f"{api_count} selected APIs documented; "
        f"{public_sources} repository public specs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
