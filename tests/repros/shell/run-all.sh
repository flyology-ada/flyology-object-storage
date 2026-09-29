#!/bin/sh
# Run every shell reproduction program in this directory and print one line
# per program: name, exit status, meaning.  Exit status of this script is 0
# when every program reproduced its finding (exit 1), 1 otherwise.
#   ./run-all.sh [timeout_seconds]
set -u
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
limit=${1:-300}
overall=0
for file in "$script_dir"/repro_*.sh; do
  name=$(basename "$file" .sh)
  if command -v timeout >/dev/null 2>&1; then
    timeout "$limit" "$file" >"$script_dir/../obj/run-$name.log" 2>&1
  else
    perl -e 'alarm shift; exec @ARGV' "$limit" "$file" >"$script_dir/../obj/run-$name.log" 2>&1
  fi
  status=$?
  case "$status" in
    0)   meaning="PASS (bug NOT reproduced)"; overall=1 ;;
    1)   meaning="BUG REPRODUCED" ;;
    124|142) meaning="TIMEOUT"; overall=1 ;;
    *)   meaning="CRASH/other"; overall=1 ;;
  esac
  printf '%-36s %3d  %s\n' "$name" "$status" "$meaning"
done
exit "$overall"
