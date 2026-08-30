#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT_DIR=${1:-"$PROJECT_DIR/obj/docs/api"}
if [ "$#" -gt 0 ]; then
  shift
fi
LOG_DIR="$PROJECT_DIR/obj/docs"
SOURCE_MANIFEST="$LOG_DIR/gnatdoc-sources.txt"
DIRECT_SOURCE_MANIFEST="$LOG_DIR/gprls-direct-sources.txt"
DIRECT_SOURCE_LOG="$LOG_DIR/gprls-direct-run.txt"
DIRECT_SOURCE_DIAGNOSTICS="$LOG_DIR/gprls-direct-stderr.txt"
DEPENDENCY_SOURCE_MANIFEST="$LOG_DIR/gprls-dependency-sources.txt"
DEPENDENCY_SOURCE_LOG="$LOG_DIR/gprls-dependency-run.txt"
DEPENDENCY_SOURCE_DIAGNOSTICS="$LOG_DIR/gprls-dependency-stderr.txt"
PUBLIC_BUILD_LOG="$LOG_DIR/public-api-build-run.txt"
PUBLIC_BUILD_CHECK_LOG="$LOG_DIR/public-api-build-check.txt"
SOURCE_NORMALIZATION_LOG="$LOG_DIR/gnatdoc-source-normalization.txt"
SOURCE_CHECK_LOG="$LOG_DIR/gnatdoc-source-check.txt"
PUBLIC_PROJECT="$PROJECT_DIR/tools/flyology_object_storage_public_api.gpr"
GNATDOC_BIN=$(command -v gnatdoc || true)

if [ -z "$GNATDOC_BIN" ]; then
  ALIRE_BIN=${ALIRE_INSTALL_PREFIX:-${ALIRE_HOME:-"$HOME/.alire"}}/bin
  GNATDOC_BIN="$ALIRE_BIN/gnatdoc"
  if [ ! -x "$GNATDOC_BIN" ]; then
    echo "gnatdoc was not found; install gnatdoc_bin=26.0.0 with Alire" >&2
    exit 127
  fi
fi

case "$OUTPUT_DIR" in
  /*) ;;
  *)
    echo "GNATdoc output directory must be absolute: $OUTPUT_DIR" >&2
    exit 1
    ;;
esac
if [ -L "$OUTPUT_DIR" ] || { [ -e "$OUTPUT_DIR" ] && [ ! -d "$OUTPUT_DIR" ]; };
then
  echo "GNATdoc output must be a real directory: $OUTPUT_DIR" >&2
  exit 1
fi
if [ -d "$OUTPUT_DIR" ] &&
  [ -n "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit)" ]; then
  echo "GNATdoc output directory is not fresh and empty: $OUTPUT_DIR" >&2
  exit 1
fi
if [ "$#" -eq 0 ]; then
  echo "GNATdoc requires at least one selected S3 operation" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR" "$LOG_DIR"
cd "$PROJECT_DIR"
alr -n build
if ! alr -n exec -- gprbuild -P"$PUBLIC_PROJECT" -p -c \
  >"$PUBLIC_BUILD_LOG" 2>&1; then
  cat "$PUBLIC_BUILD_LOG" >&2
  exit 1
fi
if ! alr -n exec -- /bin/sh -c \
  'exec gprls -P"$1" -U -s >"$2" 2>"$3"' \
  public-api-gprls "$PUBLIC_PROJECT" "$DIRECT_SOURCE_MANIFEST" \
  "$DIRECT_SOURCE_DIAGNOSTICS" >"$DIRECT_SOURCE_LOG" 2>&1; then
  cat "$DIRECT_SOURCE_LOG" "$DIRECT_SOURCE_DIAGNOSTICS" >&2
  exit 1
fi
if [ ! -s "$DIRECT_SOURCE_MANIFEST" ] || \
  [ -s "$DIRECT_SOURCE_DIAGNOSTICS" ]; then
  cat "$DIRECT_SOURCE_LOG" "$DIRECT_SOURCE_DIAGNOSTICS" >&2
  echo "direct gprls did not produce a clean source stream" >&2
  exit 1
fi
if ! alr -n exec -- /bin/sh -c \
  'exec gprls -P"$1" -U -s -d >"$2" 2>"$3"' \
  public-api-gprls "$PUBLIC_PROJECT" "$DEPENDENCY_SOURCE_MANIFEST" \
  "$DEPENDENCY_SOURCE_DIAGNOSTICS" >"$DEPENDENCY_SOURCE_LOG" 2>&1; then
  cat "$DEPENDENCY_SOURCE_LOG" "$DEPENDENCY_SOURCE_DIAGNOSTICS" >&2
  exit 1
fi
if [ ! -s "$DEPENDENCY_SOURCE_MANIFEST" ] || \
  [ -s "$DEPENDENCY_SOURCE_DIAGNOSTICS" ]; then
  cat "$DEPENDENCY_SOURCE_LOG" "$DEPENDENCY_SOURCE_DIAGNOSTICS" >&2
  echo "dependency gprls did not produce a clean source stream" >&2
  exit 1
fi
if ! alr -n exec -- uv run --python 3.13 -- python \
  "$PROJECT_DIR/tools/gnatdoc_diagnostics.py" \
  --repository "$PROJECT_DIR" \
  --sources "$SOURCE_MANIFEST" \
  --direct-sources "$DIRECT_SOURCE_MANIFEST" \
  --dependency-sources "$DEPENDENCY_SOURCE_MANIFEST" \
  --public-project "$PUBLIC_PROJECT" \
  --normalize-sources-only >"$SOURCE_NORMALIZATION_LOG" 2>&1; then
  cat "$SOURCE_NORMALIZATION_LOG" >&2
  exit 1
fi
if ! alr -n exec -- uv run --python 3.13 -- python \
  "$PROJECT_DIR/tools/gnatdoc_diagnostics.py" \
  --repository "$PROJECT_DIR" \
  --sources "$SOURCE_MANIFEST" \
  --public-project "$PUBLIC_PROJECT" \
  --check-sources-only >"$SOURCE_CHECK_LOG" 2>&1; then
  cat "$SOURCE_CHECK_LOG" >&2
  exit 1
fi
if ! alr -n exec -- uv run --python 3.13 -- python \
  "$PROJECT_DIR/tools/gnatdoc_diagnostics.py" \
  --repository "$PROJECT_DIR" \
  --sources "$SOURCE_MANIFEST" \
  --public-project "$PUBLIC_PROJECT" \
  --log "$PUBLIC_BUILD_LOG" \
  --check-log-only >"$PUBLIC_BUILD_CHECK_LOG" 2>&1; then
  cat "$PUBLIC_BUILD_CHECK_LOG" >&2
  exit 1
fi
if ! alr -n exec -- "$GNATDOC_BIN" \
  --backend=html \
  --generate=public \
  --style=leading \
  --warnings \
  -P "$PUBLIC_PROJECT" \
  -O "$OUTPUT_DIR" >"$LOG_DIR/gnatdoc-run.txt" 2>&1; then
  cat "$LOG_DIR/gnatdoc-run.txt" >&2
  exit 1
fi
test -s "$OUTPUT_DIR/index.html"
if ! grep -R -Fq --include='*.html' \
  'Flyology.Object_Storage' "$OUTPUT_DIR"; then
  echo "GNATdoc output does not contain the object-storage API" >&2
  exit 1
fi
alr -n exec -- uv run --python 3.13 -- python \
  "$PROJECT_DIR/tools/gnatdoc_diagnostics.py" \
  --log "$LOG_DIR/gnatdoc-run.txt" \
  --repository "$PROJECT_DIR" \
  --sources "$SOURCE_MANIFEST" \
  --public-project "$PUBLIC_PROJECT" \
  --site "$OUTPUT_DIR" \
  --registry "$PROJECT_DIR/coverage/s3-operations.toml" \
  "$@"
echo "GNATdoc API reference: $OUTPUT_DIR/index.html"
