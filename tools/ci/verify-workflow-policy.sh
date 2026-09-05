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

test "$(grep -Fc 'uses: astral-sh/setup-uv@c771a70e6277c0a99b617c7a806ffedaca235ff9 # v9.0.0' "$WORKFLOW")" = 3 || \
  fail "integrity, test, and docs jobs must install exact setup-uv v9.0.0"
test "$(grep -Fc 'version: "0.11.28"' "$WORKFLOW")" = 3 || \
  fail "integrity, test, and docs jobs must install exact uv 0.11.28"

command -v ruby >/dev/null 2>&1 || fail "Ruby YAML parser is required"
ruby "$PROJECT_DIR/tools/ci/verify-test-model-workflow.rb" "$WORKFLOW"

test "$(grep -Ec '^  docs:$' "$WORKFLOW")" = 1 || \
  fail "workflow must contain exactly one docs job"
DOCS_BLOCK=$(awk '
  /^  docs:$/ { inside=1 }
  inside && /^  [[:alnum:]_-]+:$/ && $0 != "  docs:" { exit }
  inside { print }
' "$WORKFLOW")
test -n "$DOCS_BLOCK" || fail "docs job block is empty"
SETUP_UV='uses: astral-sh/setup-uv@c771a70e6277c0a99b617c7a806ffedaca235ff9 # v9.0.0'
test "$(printf '%s\n' "$DOCS_BLOCK" | grep -Fc "$SETUP_UV")" = 1 || \
  fail "docs job must install exact setup-uv v9.0.0 once"
test "$(printf '%s\n' "$DOCS_BLOCK" | grep -Fc 'version: "0.11.28"')" = 1 || \
  fail "docs job must install exact uv 0.11.28 once"
test "$(printf '%s\n' "$DOCS_BLOCK" | grep -Fc \
  'run: alr install gnatdoc_bin=26.0.0')" = 1 || \
  fail "docs job must install exact gnatdoc_bin=26.0.0 once"

DOCS_COMMAND='./tools/build-api-docs.sh "$PWD/obj/docs/api"'
test "$(printf '%s\n' "$DOCS_BLOCK" | grep -Fc "$DOCS_COMMAND")" = 1 || \
  fail "docs job must invoke the maintained GNATdoc wrapper once"
test "$(printf '%s\n' "$DOCS_BLOCK" | \
  grep -Fc -- '--operation ListBuckets')" = 1 || \
  fail "docs job must select the stable ListBuckets API once"
DOCS_UV_LINE=$(printf '%s\n' "$DOCS_BLOCK" | \
  grep -nF "$SETUP_UV" | cut -d: -f1)
DOCS_GNATDOC_LINE=$(printf '%s\n' "$DOCS_BLOCK" | \
  grep -nF 'run: alr install gnatdoc_bin=26.0.0' | cut -d: -f1)
DOCS_COMMAND_LINE=$(printf '%s\n' "$DOCS_BLOCK" | \
  grep -nF "$DOCS_COMMAND" | cut -d: -f1)
DOCS_OPERATION_LINE=$(printf '%s\n' "$DOCS_BLOCK" | \
  grep -nF -- '--operation ListBuckets' | cut -d: -f1)
if [ "$DOCS_UV_LINE" -ge "$DOCS_GNATDOC_LINE" ] || \
   [ "$DOCS_GNATDOC_LINE" -ge "$DOCS_COMMAND_LINE" ]; then
  fail "docs job tool installation must precede its wrapper invocation"
fi
if [ "$((DOCS_COMMAND_LINE + 1))" -ne "$DOCS_OPERATION_LINE" ]; then
  fail "docs job operation must immediately follow its wrapper invocation"
fi

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

echo "workflow policy: immutable actions, exact tools, pinned test model, documented API gate"
