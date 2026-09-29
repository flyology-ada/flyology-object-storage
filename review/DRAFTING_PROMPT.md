# Issue-drafting brief (shared by every area)

You are drafting GitHub issue bodies for confirmed findings of a correctness
review of the Ada crate `flyology_object_storage`, at commit `5fe6e3e`
(origin/main). Worktree, absolute paths only:

    /Users/yrashk/Projects/flyology-ada/flyology-object-storage/.claude/worktrees/flyology-object-storage-review-b1846d

## Hard rules

- Do not modify, create or delete any tracked file. The only files you write
  are `review/filing/<ID>.md`, one per finding you are assigned. Never run
  `alr` or `gprbuild` directly, never run the repository test scripts, never
  `git stash`, never commit.
- Read `review/filing/STYLE.md` in full before writing anything. It is the
  contract: file format (Title / Labels / Refs header, then `## Summary`),
  section order, title rules, the Problem section's first line
  `Commit \`5fe6e3e\`.`, the host line, the prose rules (plain, exact,
  unhedged; short sentences; no em-dashes; no exclamation marks; no "we").
  The five reference bodies at its end set the register; read them.
- No mention anywhere of the review, reviewers, verifiers, agents, AI,
  Claude, Fable, Opus, the scratchpad, `FINDINGS.md`, the `review/`
  directory, the harness directories (`tests/repros`, `sqlite/tests/repros`),
  the support units (`Repro_Support`, `Repro_S3_Server`), `run-all.sh`, or
  discovery and verification reports. The program is "the spike" or "the
  program below". Internal IDs (`WIRE-1` and the like) must not appear in a
  title or body; refer to another finding only with the placeholder
  `{{ISSUE:<ID>}}` and list that ID in the `Refs:` header line.
- Refer to repository rules by `AGENTS.md` section name ("Decision
  authority", "Ada interface values", "Flyology Object Storage agent guide",
  and so on), never by a `.claude/...` path.

## Inputs for your area

- `review/consolidation/<AREA>.md` (what was confirmed, with severities,
  locations, notes on duplicates, decisions and tests asserting the wrong
  behaviour), `review/verification-<AREA>.md` (the evidence and the program
  descriptions), `review/discovery-<AREA>.md` (further location detail).
- The programs under `tests/repros/src/repro_<area>_<n>.adb` (or the shell
  and python paths named in the consolidation), the pinned model
  `review/baseline/service-2.json`, the documents under `docs/`.

## Per body

1. Re-run the finding's program for fresh output:
   `cd /…/tests/repros && ./run.sh repro_<area>_<n> 120` (or
   `sqlite/tests/repros/run.sh` for SQLite programs; shell programs run
   directly; python probes as their header says). Paste the verbatim output
   into "What happens now", trimming repeated lines but never editing
   numbers. Record the exit status.
2. Verify every `file:line` you cite with `sed -n` at the current worktree
   (which is commit `5fe6e3e`), and quote the exact lines in fenced `ada`
   (or `c`, `python`, `sql`, `yaml`) blocks with the location in backticks
   before each quote. Never cite a line you did not print.
3. Cite the authority the fix rests on: the `.ads` contract sentence, the
   README or `docs/compatibility/s3.md` or `docs/qualification/*.md` sentence
   (quote it), the pinned botocore model (name the shape and member, and
   quote the JSON with python3), the AWS S3 API Reference or SigV4 document
   by page and section only when the model cannot answer (say "from memory"
   there is not allowed in an issue; instead phrase it as what the document
   states, only when you are certain, and otherwise omit the claim), or the
   real-server behaviour observed (server name and release, exact request
   and response, as recorded in the verification report).
4. Say why the existing tests do not catch it, with `file:line` when a test
   asserts the wrong behaviour and must change.
5. `## Suggested treatment`: the smallest fix, concrete enough to start from;
   where the fix adds a public constant, variant, parameter, default, or
   changes an outcome type or documented policy, write "This needs a
   maintainer decision:" and list the options without choosing (the
   "Decision authority" and "Ada interface values" sections of `AGENTS.md`).
   Say where the regression test belongs (the existing suite file) and that
   the spike is the test.
6. `## Severity`: prose only, no P-labels; impact, who hits it and how,
   determinism; end with `Deterministic.`, `Deterministic; not reproduced
   against a live server.`, `Not reproduced.`, or a qualifier such as
   `Files backend only.` or `SQLite backend only.` or `macOS only.`
7. Labels: `bug`; add `documentation` only for pure contract drift.
8. Duplicates: a finding marked "duplicate of X" in the consolidation gets no
   file; fold its extra evidence (site, program, stock-client capture) into
   X's body as an additional site or "What happens now" paragraph.
9. Cross-references: `{{ISSUE:<ID>}}` in the body and the ID in `Refs:`.

## Validation

When you finish, run
`python3 /…/review/filing/file_issues.py --dry-run` and fix every
`INVALID` line that concerns your files (the script's ORDER list may not yet
contain your IDs, in which case it reports them as missing; that is not
yours to fix). Your final chat message: one line per body (ID, title, label,
exit status of the spike) and any validator complaint you could not resolve.
