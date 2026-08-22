#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
WORKFLOW=${1:-"$PROJECT_DIR/.github/workflows/ci.yml"}

fail() {
  echo "workflow policy: $*" >&2
  exit 1
}

test -f "$WORKFLOW" || fail "workflow file is missing: $WORKFLOW"

while IFS= read -r reference
do
  case "$reference" in
    ./*) ;;
    *@????????????????????????????????????????) ;;
    *) fail "GitHub Action is not pinned to a full commit: $reference" ;;
  esac
  revision=${reference##*@}
  if [[ "$reference" != ./* && ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
    fail "GitHub Action has a malformed commit pin: $reference"
  fi
done < <(
  sed -n -E \
    's/^[[:space:]]*uses:[[:space:]]*([^#[:space:]]+).*$/\1/p' \
    "$WORKFLOW"
)

CHECKOUTS=$(grep -Ec \
  'uses: actions/checkout@[0-9a-f]{40}([[:space:]]|$)' "$WORKFLOW")
NO_CREDENTIALS=$(grep -Ec \
  '^[[:space:]]+persist-credentials:[[:space:]]+false$' "$WORKFLOW")
if [ "$CHECKOUTS" -eq 0 ] || [ "$CHECKOUTS" -ne "$NO_CREDENTIALS" ]; then
  fail "every checkout must disable persisted credentials"
fi
if grep -Fq '${{ secrets.' "$WORKFLOW"; then
  fail "the pull-request workflow must not consume repository secrets"
fi
test "$(grep -Ec '^[[:space:]]+contents:[[:space:]]+read$' "$WORKFLOW")" = 1 || \
  fail "workflow must have one read-only contents permission"
test "$(grep -Fc 'run: alr install gnatdoc_bin=26.0.0' "$WORKFLOW")" = 1 || \
  fail "docs job must install exact gnatdoc_bin=26.0.0 once"

test "$(grep -Fc 'run: alr install gnatprove=16.1.0' "$WORKFLOW")" = 1 || \
  fail "proof job must install exact gnatprove=16.1.0 once"
test "$(grep -Fc "grep -Fxq 'FSF 16.1.0'" "$WORKFLOW")" = 1 || \
  fail "proof job must assert the exact GNATprove version"
test "$(grep -Fc 'run: ./tools/prove.sh' "$WORKFLOW")" = 1 || \
  fail "proof job must invoke tools/prove.sh once"
INSTALL_LINE=$(grep -nF 'run: alr install gnatprove=16.1.0' \
  "$WORKFLOW" | cut -d: -f1)
VERSION_LINE=$(grep -nF "grep -Fxq 'FSF 16.1.0'" \
  "$WORKFLOW" | cut -d: -f1)
PROOF_LINE=$(grep -nF 'run: ./tools/prove.sh' \
  "$WORKFLOW" | cut -d: -f1)
if [ "$INSTALL_LINE" -ge "$VERSION_LINE" ] || \
   [ "$VERSION_LINE" -ge "$PROOF_LINE" ]; then
  fail "proof tool install and version assertion must precede tools/prove.sh"
fi

echo "workflow policy: immutable actions, unprivileged checkout, exact proof tool"
