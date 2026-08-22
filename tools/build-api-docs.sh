#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR=${1:-"$PROJECT_DIR/obj/docs/api"}
LOG_DIR="$PROJECT_DIR/obj/docs"
GNATDOC_BIN=$(command -v gnatdoc || true)

if [ -z "$GNATDOC_BIN" ]; then
  GNATDOC_BIN=${ALIRE_INSTALL_PREFIX:-${ALIRE_HOME:-"$HOME/.alire"}}/bin/gnatdoc
  if [ ! -x "$GNATDOC_BIN" ]; then
    echo "gnatdoc was not found; install gnatdoc_bin=26.0.0 with Alire" >&2
    exit 127
  fi
fi

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
cd "$PROJECT_DIR"
alr -n build
alr -n exec -- "$GNATDOC_BIN" \
  --backend=html \
  --generate=public \
  --style=leading \
  --warnings \
  -P flyology_object_storage.gpr \
  -O "$OUTPUT_DIR" 2>&1 | tee "$LOG_DIR/gnatdoc-run.txt"
test -s "$OUTPUT_DIR/index.html"
if grep -Eiq '(^|[[:space:]])error:' "$LOG_DIR/gnatdoc-run.txt"; then
  echo "GNATdoc reported an error diagnostic" >&2
  exit 1
fi
if ! grep -R -Fq --include='*.html' \
  'Flyology.Object_Storage' "$OUTPUT_DIR"; then
  echo "GNATdoc output does not contain the object-storage API" >&2
  exit 1
fi
echo "GNATdoc API reference: $OUTPUT_DIR/index.html"
