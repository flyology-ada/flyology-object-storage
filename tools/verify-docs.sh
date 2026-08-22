#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR=${GNATDOC_OUTPUT_DIR:-"$PROJECT_DIR/obj/gnatdoc/html"}
LOG=${GNATDOC_LOG:-"$PROJECT_DIR/gnatdoc-run.txt"}

command -v gnatdoc >/dev/null
command -v python3 >/dev/null

python3 - "$PROJECT_DIR" <<'PY'
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import unquote

root = Path(sys.argv[1]).resolve()
documents = [root / "README.md", root / "PRODUCT.md"]
documents.extend(sorted((root / "docs").rglob("*.md")))
broken = []

for document in documents:
    if not document.is_file() or document.stat().st_size == 0:
        broken.append(f"{document.relative_to(root)}: missing or empty")
        continue
    text = document.read_text(encoding="utf-8")
    for match in re.finditer(r"(?<!!)\[[^]]*\]\(([^)]+)\)", text):
        target = match.group(1).strip()
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        target = target.split("#", 1)[0]
        if not target or re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", target):
            continue
        candidate = (document.parent / unquote(target)).resolve()
        try:
            candidate.relative_to(root)
        except ValueError:
            broken.append(
                f"{document.relative_to(root)}: link escapes repository: {target}"
            )
            continue
        ignored = subprocess.run(
            ["git", "-C", str(root), "check-ignore", "-q", "--", str(candidate)],
            check=False,
        ).returncode == 0
        if ignored:
            continue
        if not candidate.exists():
            broken.append(
                f"{document.relative_to(root)}: missing link target: {target}"
            )

if broken:
    print("\n".join(broken), file=sys.stderr)
    raise SystemExit(1)

print(f"documentation links: {len(documents)} Markdown files OK")
PY

mkdir -p "$OUTPUT_DIR"
cd "$PROJECT_DIR"
alr -n update
alr -n build
alr -n exec -- gnatdoc \
  --backend=html \
  --generate=public \
  --style=leading \
  --warnings \
  -P flyology_object_storage.gpr \
  -O "$OUTPUT_DIR" 2>&1 | tee "$LOG"

test -s "$OUTPUT_DIR/index.html"
if grep -Eiq '(^|[^[:alpha:]])error:' "$LOG"; then
  echo "GNATdoc reported an error" >&2
  exit 1
fi

echo "GNATdoc public HTML: $OUTPUT_DIR/index.html"
