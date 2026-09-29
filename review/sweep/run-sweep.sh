#!/bin/sh
WT=/Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d
S=$WT/review/sweep
date -u +%Y-%m-%dT%H:%M:%SZ > "$S/START"
cd "$WT/tests/repros" && ./run-all.sh 300 > "$S/ada.log" 2>&1; echo "ada exit=$?" >> "$S/ada.log"
cd "$WT/sqlite/tests/repros" && ./run-all.sh 300 > "$S/sqlite.log" 2>&1; echo "sqlite exit=$?" >> "$S/sqlite.log"
cd "$WT/tests/repros/shell" && ./run-all.sh 300 > "$S/shell.log" 2>&1; echo "shell exit=$?" >> "$S/shell.log"
cd "$WT" && {
  python3 tests/repros/python/model_differential.py > "$S/python-model.log" 2>&1; echo "model_differential.py exit=$? (0 expected: no model finding)" > "$S/python.log"
  export AWS_ACCESS_KEY_ID=AKIDEXAMPLE AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY
  uv run --python 3.13 --with boto3 python3 tests/repros/python/checksum_boto3_probe.py > "$S/python-checksum.log" 2>&1; echo "checksum_boto3_probe.py exit=$? (1 expected: stock boto3 rejected)" >> "$S/python.log"
}
date -u +%Y-%m-%dT%H:%M:%SZ > "$S/DONE-all"
