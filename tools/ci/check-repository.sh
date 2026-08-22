#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
MODEL=${1:-}
cd "$PROJECT_DIR"

fail() {
  echo "repository integrity: $*" >&2
  exit 1
}

HTTP_DECLARATIONS=$(git grep -h -E \
  '^[[:space:]]*flyology_http[[:space:]]*=' -- '*alire.toml' || true)
test -n "$HTTP_DECLARATIONS" || fail "flyology_http dependency is missing"
while IFS= read -r declaration
do
  if [ "$declaration" != 'flyology_http = "=0.1.2"' ]; then
    fail "every flyology_http declaration must be an indexed =0.1.2 dependency"
  fi
done <<<"$HTTP_DECLARATIONS"
echo "dependency policy: exact indexed flyology_http=0.1.2, no HTTP pin"

while IFS= read -r script
do
  test -x "$script" || fail "$script is not executable"
  bash -n "$script"
done < <(git ls-files '*.sh')
echo "shell scripts: executable and syntax-clean"

while IFS= read -r source
do
  python3 -c \
    'import ast, pathlib, sys; ast.parse(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"), filename=sys.argv[1])' \
    "$source"
done < <(git ls-files '*.py')
echo "Python sources: syntax-clean"

"$PROJECT_DIR/tools/ci/verify-workflow-policy.sh"
"$PROJECT_DIR/tools/ci/test-workflow-policy.sh"

LEFT=$(printf '%s%s' '<<<' '<<<<')
MIDDLE=$(printf '%s%s' '===' '====')
RIGHT=$(printf '%s%s' '>>>' '>>>>')
if git grep -n -E "^($LEFT|$MIDDLE|$RIGHT)" -- .; then
  fail "tracked conflict marker found"
fi
echo "conflict markers: none"

if [ -n "${CI_BASE_REF:-}" ] && \
   git show-ref --verify --quiet "refs/remotes/origin/$CI_BASE_REF"
then
  BASE=$(git merge-base HEAD "refs/remotes/origin/$CI_BASE_REF")
  git diff --check "$BASE"...HEAD
elif [ -n "${CI_BEFORE_SHA:-}" ] && \
     [ "$CI_BEFORE_SHA" != 0000000000000000000000000000000000000000 ] && \
     git cat-file -e "$CI_BEFORE_SHA^{commit}" 2>/dev/null
then
  git diff --check "$CI_BEFORE_SHA"...HEAD
else
  git show --check --format= HEAD
fi
echo "changed lines: whitespace-clean"

"$PROJECT_DIR/tools/ci/check-markdown-links.py"
"$PROJECT_DIR/tools/verify-coverage.sh"
"$PROJECT_DIR/tools/test-coverage-verifier.sh"

if [ -n "$MODEL" ]; then
  "$PROJECT_DIR/tools/verify-botocore-model.sh" "$MODEL"
else
  echo "botocore model: skipped (no model path supplied)"
fi

echo "repository integrity: OK"
