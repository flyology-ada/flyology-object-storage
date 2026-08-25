#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ALR_BIN=$(dirname -- "$(command -v alr)")
PROVE="$ALR_BIN/gnatprove"
if [ ! -x "$PROVE" ]; then
  PROVE="${ALIRE_HOME:-${HOME}/.alire}/bin/gnatprove"
fi
if [ ! -x "$PROVE" ]; then
  echo "gnatprove was not found in the active Alire installation" >&2
  exit 127
fi
PROOF_UNITS=(
  flyology-object_storage.adb
  flyology-object_storage-s3-core.adb
  flyology-object_storage-s3-checksum_policy.adb
  flyology-object_storage-s3-checksum_crc.adb
  flyology-object_storage-s3-imf_dates.adb
  flyology-object_storage-s3-model.adb
  flyology-object_storage-s3-requests.adb
  flyology-object_storage-s3-sigv4_encoding.adb
  flyology-object_storage-s3-wire_core.adb
)
PROOF_PROJECT="tools/flyology_object_storage_proof.gpr"
PROOF_LOG_DIR="$PROJECT_DIR/obj/proof/logs"

run_prove() {
  #  Flyology is an indirect Alire dependency. Its exported root is the stable
  #  project location even when the shared build cache omits it from the
  #  indirect GPR search path.
  alr -n exec -- sh -c '
    GPR_PROJECT_PATH="${FLYOLOGY_ROOT}${GPR_PROJECT_PATH:+:$GPR_PROJECT_PATH}"
    export GPR_PROJECT_PATH
    exec "$@"
  ' sh "$PROVE" "$@"
}

cd "$PROJECT_DIR"
run_prove -P "$PROOF_PROJECT" --clean
mkdir -p "$PROOF_LOG_DIR"
run_prove -P "$PROOF_PROJECT" -j0 --level=0 \
  --output=oneline --output-header --warnings=error "$@" \
  -u "${PROOF_UNITS[@]}" 2>&1 \
  | tee "$PROOF_LOG_DIR/gnatprove-run.txt"
