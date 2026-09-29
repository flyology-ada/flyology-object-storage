#!/usr/bin/env python3
"""Assemble FINDINGS.md from review/FINDINGS_HEADER.md and review/consolidation/<AREA>.md.

Each consolidation file has, in order: index-table rows (lines starting with "| " whose first
cell is a finding ID), one totals row (first cell is the AREA name), the area section (from the
first "## " heading), and two appendix blocks headed "Coverage evidence" and "Observations not
counted" (as "## ..." or "### ..." or bold lines). This script is tolerant of small format
differences: it classifies table rows by their first cell and splits the appendix blocks by
heading text.
"""
import re, sys, pathlib, subprocess, datetime

ROOT = pathlib.Path(__file__).resolve().parents[1]
REVIEW = ROOT / "review"
CONS = REVIEW / "consolidation"
ORDER = ["WIRE", "SIGV4", "SERVER", "CHECKSUM", "BACKEND-MEMORY", "BACKEND-FILES",
         "BACKEND-SQLITE", "CLIENT-LOW", "CLIENT-OBJECTS", "CLIENT-BUCKETS", "TRANSFERS",
         "S3-DOMAIN-A", "S3-DOMAIN-B", "SERVER-EXE", "MODEL", "BASELINE"]
ID_RE = re.compile(r"^\| ([A-Z0-9]+(?:-[A-Z0-9]+)*-[0-9]+b?) \|")

def split(text: str, area: str):
    """Consolidation files use fixed labels:
    '# <AREA> consolidation block', '## Index rows', '## Totals row', '## Area section',
    '## <AREA>: <title>', '## Coverage evidence: <AREA>', '## Observations not counted: <AREA>'."""
    lines = text.splitlines()
    def find(label):
        for i, line in enumerate(lines):
            if line.strip() == label or line.strip().startswith(label):
                return i
        return None
    i_index = find("## Index rows"); i_tot = find("## Totals row"); i_sec = find("## Area section")
    i_cov = find("## Coverage evidence"); i_obs = find("## Observations not counted")
    index_rows, totals_row = [], None
    if i_index is not None and i_tot is not None:
        for line in lines[i_index + 1:i_tot]:
            if ID_RE.match(line):
                index_rows.append(line.rstrip())
    if i_tot is not None:
        stop = i_sec if i_sec is not None else len(lines)
        for line in lines[i_tot + 1:stop]:
            if line.startswith(f"| {area} |"):
                totals_row = line.rstrip()
    sec_start = (i_sec + 1) if i_sec is not None else 0
    sec_end = i_cov if i_cov is not None else (i_obs if i_obs is not None else len(lines))
    section = "\n".join(lines[sec_start:sec_end]).strip("\n")
    cov = obs = ""
    if i_cov is not None:
        cov_end = i_obs if (i_obs is not None and i_obs > i_cov) else len(lines)
        cov = "\n".join(lines[i_cov + 1:cov_end]).strip("\n")
    if i_obs is not None:
        obs_end = i_cov if (i_cov is not None and i_cov > i_obs) else len(lines)
        obs = "\n".join(lines[i_obs + 1:obs_end]).strip("\n")
    return index_rows, totals_row, section, cov, obs

def main():
    header = (REVIEW / "FINDINGS_HEADER.md").read_text()
    issue_para = (REVIEW / "ISSUE_PARAGRAPH.md").read_text().strip() if (REVIEW / "ISSUE_PARAGRAPH.md").exists() else \
        "The confirmed findings below are being filed as GitHub issues on flyology-ada/flyology-object-storage; the finding-to-issue mapping will be in `review/ISSUES.md`, and the Codex triage brief in `review/TRIAGE_FOR_CODEX.md`."
    header = header.replace("{{ISSUE_PARAGRAPH}}", issue_para)
    parts = {}
    missing = []
    for area in ORDER:
        f = CONS / f"{area}.md"
        if not f.exists():
            missing.append(area); continue
        parts[area] = split(f.read_text(), area)
    out = [header.rstrip("\n"), ""]
    # Totals
    out += ["## Totals", "", "| Area | P0 | P1 | P2 | Confirmed | Duplicates / partial |", "| --- | --- | --- | --- | --- | --- |"]
    tp0 = tp1 = tp2 = tc = 0
    for area in ORDER:
        if area not in parts: 
            out.append(f"| {area} | (pending) | | | | |"); continue
        row = parts[area][1]
        if row:
            out.append(row)
            cells = [c.strip() for c in row.strip("|").split("|")]
            try:
                tp0 += int(cells[1]); tp1 += int(cells[2]); tp2 += int(cells[3]); tc += int(cells[4])
            except (ValueError, IndexError):
                pass
    out.append(f"| **Total** | **{tp0}** | **{tp1}** | **{tp2}** | **{tc}** | see the area rows |")
    out += ["", "Duplicates are not counted as findings. A partially confirmed finding is counted once.", ""]
    # Index
    out += ["## Index of findings", "", "| ID | Sev | Title | Primary location | Repro |", "| --- | --- | --- | --- | --- |"]
    for area in ORDER:
        if area in parts:
            out += parts[area][0]
    out.append("")
    # Sections
    for area in ORDER:
        if area in parts:
            out += [parts[area][2], ""]
    # Appendices
    out += ["## Appendix A: coverage evidence per area", ""]
    for area in ORDER:
        if area in parts and parts[area][3]:
            out += [f"### {area}", "", parts[area][3], ""]
    out += ["## Appendix B: observations not counted", ""]
    for area in ORDER:
        if area in parts and parts[area][4]:
            out += [f"### {area}", "", parts[area][4], ""]
    # Sweep summary
    sweep = REVIEW / "sweep"
    def summarize(log, label):
        f = sweep / log
        if not f.exists():
            return f"- {label}: not run."
        rows = [l for l in f.read_text().splitlines() if l.startswith("repro_")]
        rep = sum(1 for l in rows if "BUG REPRODUCED" in l)
        other = [l.split()[0] + " (" + l.split("  ")[-1].strip() + ")" for l in rows if "BUG REPRODUCED" not in l]
        return f"- {label}: {rep} of {len(rows)} programs printed `BUG REPRODUCED`" + (f"; others: {', '.join(other)}." if other else ".")
    out += ["## Clean sweep", "",
            "Every reproduction program was run once more in one uninterrupted sweep after all",
            "verification and drafting work had finished (logs under `review/sweep/`):", "",
            summarize("ada.log", "`tests/repros` (Ada)"),
            summarize("sqlite.log", "`sqlite/tests/repros` (Ada, SQLite backend)"),
            summarize("shell.log", "`tests/repros/shell` (shell programs)"),
            ""]
    py = sweep / "python.log"
    if py.exists():
        out += ["Python probes:", "", "```", py.read_text().strip(), "```", ""]
    # Artifacts
    out += ["## Appendix C: artifacts", ""]
    out += ["Discovery-phase candidate counts are in `review/discovery-totals.md`.", ""]
    def listing(pattern, base):
        return sorted(str(p.relative_to(ROOT)) for p in base.glob(pattern))
    out += ["Reports (`review/`):", ""]
    for p in sorted(REVIEW.glob("discovery-*.md")) + sorted(REVIEW.glob("verification-*.md")) + [REVIEW/"baseline-notes.md", REVIEW/"baseline-rustfs.md", REVIEW/"discovery-totals.md"]:
        if p.exists(): out.append(f"- `{p.relative_to(ROOT)}`")
    out += ["", "Reproduction programs (`tests/repros`):", ""]
    for p in sorted((ROOT/"tests/repros/src").glob("repro_*.adb")):
        out.append(f"- `{p.relative_to(ROOT)}`")
    for p in sorted((ROOT/"tests/repros/shell").glob("*.sh")) + sorted((ROOT/"tests/repros/python").glob("*.py")):
        out.append(f"- `{p.relative_to(ROOT)}`")
    out += ["", "Reproduction programs (`sqlite/tests/repros`):", ""]
    for p in sorted((ROOT/"sqlite/tests/repros/src").glob("repro_*.adb")):
        out.append(f"- `{p.relative_to(ROOT)}`")
    out.append("")
    if missing:
        out += [f"Areas not yet consolidated at assembly time: {', '.join(missing)}.", ""]
    target = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "FINDINGS.md"
    target.write_text("\n".join(out))
    print(f"wrote {target} ({len(out)} lines); totals P0={tp0} P1={tp1} P2={tp2} confirmed={tc}; missing={missing}")

if __name__ == "__main__":
    main()
