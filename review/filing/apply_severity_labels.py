#!/usr/bin/env python3
"""Add the P0/P1/P2 label to every filed issue, from review/ISSUES.json and the FINDINGS.md index."""
import json, re, subprocess, sys, time, pathlib
REVIEW = pathlib.Path(__file__).resolve().parents[1]
ROOT = REVIEW.parent
REPO = "flyology-ada/flyology-object-storage"
mapping = json.loads((REVIEW / "ISSUES.json").read_text())
index = {}
for line in (ROOT / "FINDINGS.md").read_text().splitlines():
    m = re.match(r"^\| ([A-Z0-9-]+-[0-9]+b?) \| (P[012]) \|", line)
    if m:
        index[m.group(1)] = m.group(2)
done = 0
for fid, entry in mapping.items():
    sev = index.get(fid)
    if not sev:
        print(f"no severity for {fid}", file=sys.stderr); continue
    for attempt in range(3):
        r = subprocess.run(["gh", "issue", "edit", "--repo", REPO, str(entry["number"]), "--add-label", sev],
                           capture_output=True, text=True)
        if r.returncode == 0:
            break
        print(f"retry {fid} #{entry['number']}: {r.stderr.strip()[:120]}", file=sys.stderr); time.sleep(30)
    else:
        print(f"FAILED {fid}", file=sys.stderr); continue
    done += 1
    print(f"#{entry['number']} {fid} {sev}", flush=True)
    time.sleep(2)
print(f"labelled {done} of {len(mapping)}")
