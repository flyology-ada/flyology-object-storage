#!/usr/bin/env python3
"""Assemble review/TRIAGE_FOR_CODEX.md from TRIAGE_HEADER.md and TRIAGE_LAYERS.draft.md.
Renumbers the '<n>. **' list entries sequentially across all layers, fills {{ISSUE_COUNT}} from
file_issues.py's ORDER, and writes the out-of-scope section. {{ISSUE:ID}} and {{ISSUE_RANGE}} are
left for `file_issues.py --resolve`."""
import re, pathlib, sys
REVIEW = pathlib.Path(__file__).resolve().parent
header = (REVIEW / "TRIAGE_HEADER.md").read_text()
layers = (REVIEW / "TRIAGE_LAYERS.draft.md").read_text()
order_text = (REVIEW / "filing" / "file_issues.py").read_text()
order = re.findall(r'"([A-Z0-9-]+-[0-9]+b?)"', order_text.split("ORDER = [")[1].split("]")[0])
count = len(order)
words = {38: "Thirty-eight", 39: "Thirty-nine", 40: "Forty", 41: "Forty-one", 42: "Forty-two",
         43: "Forty-three", 44: "Forty-four", 45: "Forty-five", 46: "Forty-six", 47: "Forty-seven",
         48: "Forty-eight", 49: "Forty-nine", 50: "Fifty", 51: "Fifty-one", 52: "Fifty-two",
         53: "Fifty-three", 54: "Fifty-four", 55: "Fifty-five", 56: "Fifty-six", 57: "Fifty-seven",
         58: "Fifty-eight", 59: "Fifty-nine", 60: "Sixty", 61: "Sixty-one", 62: "Sixty-two"}
# Split the layers draft into the model-first block and the layered lists.
mf_marker = "{{MODEL_FIRST_ITEMS}}\n"
lay_marker = "{{LAYERS}}\n"
model_first = layers.split(mf_marker)[1].split(lay_marker)[0].strip("\n")
layered = layers.split(lay_marker)[1]
# Renumber list entries sequentially.
n = 0
out_lines = []
for line in layered.splitlines():
    m = re.match(r"^(\d+)\. (\*\*.*)$", line)
    if m:
        n += 1
        line = f"{n}. {m.group(2)}"
    out_lines.append(line)
layered = "\n".join(out_lines)
out_of_scope = (
    "No issue or pull request was open on flyology-ada/flyology-object-storage when these were filed\n"
    "(the last merged pull request is #12). The observations listed under \"Observations not counted\"\n"
    "in each area of the review record are not issues: documented policy values, unreachable code, and\n"
    "candidates that verification refuted. The `_probe` programs in the reproduction harness pass on\n"
    "the current sources and exist only to show that a suspected defect is absent. Two documented\n"
    "limitations were deliberately left unfiled and are the maintainer's call: `+` in `x-amz-tagging`\n"
    "(the crate keeps the literal plus where MinIO decodes it to a space; `tagging.ads:27-30`) and\n"
    "presigned URLs (documented as not claimed).")
doc = header.replace("{{MODEL_FIRST_ITEMS}}", model_first).replace("{{LAYERS}}", layered.strip("\n"))
doc = doc.replace("{{OUT_OF_SCOPE}}", out_of_scope)
doc = doc.replace("{{ISSUE_COUNT}}", words.get(count, str(count)))
target = REVIEW / "TRIAGE_FOR_CODEX.md"
target.write_text(doc)
print(f"wrote {target}: {count} issues in ORDER, {n} list entries, {doc.count('{{ISSUE:')} placeholders")
