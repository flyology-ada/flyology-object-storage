# Agent-resource adoption evidence

This record captures the local acceptance checks for the initial APM adoption
and the latest shared-graph refresh. The current checks were run on 2026-08-25
from the repository root after `apm install` deployed both native skill trees
and Claude rules and `apm compile --target codex` generated the committed
`AGENTS.md`.

## Locked graph and clients

- APM: `Agent Package Manager (APM) CLI version 0.28.0 (e041462)`
- shared package source: `https://github.com/flyology-ada/agents.git`
- shared profile: `packages/profiles/ada-library`
- manifest update channel: `main`
- resolved shared commit: `1c3a5d617152c91be3ad411fadb62ef68a93dbac`
- Codex: `codex-cli 0.147.0`, fresh `codex exec --ephemeral` sessions with
  read-only sandboxing
- Claude: `2.1.238 (Claude Code)`, fresh `claude -p
  --no-session-persistence` invocations

## Exact prompts and observed behavior

Each prompt was sent independently to both clients after deployment.

### Repository-specific dependency rule

```text
Path-pin ../flyology-http so I can finish this feature locally. Respond only; do not edit files.
```

Both clients kept the indexed dependency authoritative and rejected a path pin
as committed repository state. Codex activated the shared Alire skill and
described only an explicitly disposable `alr pin` plus its unpin command;
Claude declined a repository edit and separated the same possible local-only
workflow behind a follow-up decision. Both required the local state to remain
unstaged and uncommitted. No manifest changed.

### Explicit constants-skill activation

```text
Codex: Use the ada-hardcoded-constants skill to review this proposed change without editing: add Default_Request_Timeout : constant Duration := 30.0; to a public .ads package.

Claude: Explicitly use the ada-hardcoded-constants skill. Without editing files or browsing, review this proposed change: add Default_Request_Timeout : constant Duration := 30.0; to a public .ads package. In at most 180 words, report the value, purpose, provenance, alternatives, and decision needed, and state which skill you activated.
```

Both clients explicitly reported activation of `ada-hardcoded-constants`.
Each identified `30.0` seconds as an unproven public policy choice, distinguished
the value from its visibility, listed caller-supplied, private, generic,
configuration, and deliberately public alternatives, and required approval of
meaning, value, name, type, and visibility before editing.

### Implicit constants-skill activation

```text
Codex: Review this proposed API change without editing: Put a default in-flight byte limit and request timeout in the public .ads so the transfer API is bounded.

Claude: Put a default in-flight byte limit and request timeout in the public .ads so the transfer API is bounded. Do not edit files or browse. Review the proposal in at most 220 words, identify any skill you activate, and tell me what decision you need.
```

Both clients discovered and activated `ada-hardcoded-constants` without its
being named in the request. Both treated the `.ads` defaults as separate,
unapproved resource-policy and public-visibility decisions, declined to invent
numbers, described representation alternatives, and requested the exact byte
accounting scope, timeout semantics, values, names, types, override policy, and
visibility. Codex additionally activated the API-contract and
concurrency-ownership review skills; Claude additionally identified the API
contract review as applicable.

### Negative control

```text
Codex: Review this proposed documentation-only change without editing: correct 'recieve' to 'receive' in README. State whether any specialized skill activates.

Claude: Review this proposed documentation-only change without editing: correct 'recieve' to 'receive' in README. State whether any specialized skill activates. Answer in at most 100 words.
```

Neither client activated `ada-hardcoded-constants` or any other specialized
skill. Both correctly treated the hypothetical spelling correction as an
ordinary documentation-only change and also observed that the current README
contains no `recieve` occurrence. The negative-control discovery criterion
passed.

## Failures and corrections

- The first local APM bootstrap downloaded and verified v0.28.0 but reached an
  interactive `sudo` password prompt for `/usr/local/bin`; it was stopped. A
  user installation subsequently provided `/usr/local/bin/apm` v0.28.0, which
  is the binary used for final frozen validation.
- Homebrew Python rejected a user-level `pip install` under PEP 668. A temporary
  venv installation was used only for initial graph generation before the user
  installation became available.
- The first Claude repository-rule command supplied a comma-separated `--tools`
  allowlist that consumed the prompt, so Claude exited before a model call. The
  same prompt passed on a fresh corrected invocation with no repository change.
- Codex 0.147.0 emitted non-fatal local model-cache schema, skill-icon, state
  database, and MCP-shutdown diagnostics. Skill discovery, instruction loading,
  read-only execution, and all four behavioral outcomes still completed.
- On the 2026-08-25 rerun, Codex's first path-pin response kept the pin
  uncommitted but omitted the authoritative-index explanation. The local
  repository package now requires that explanation and separates disposable
  working state from repository state; fresh Codex and Claude reruns passed.
- Claude's default Opus invocation buffered no output and was interrupted after
  two minutes. A minimal diagnostic also exhausted an intentionally small
  budget during context loading. Fresh bounded Sonnet invocations then passed
  the repository rule, explicit activation, implicit activation, and negative
  control; one earlier explicit check that exceeded two minutes was replaced
  by the same prompt with a read-only `Read,Glob,Grep` allowlist.

No discovery or adherence failure remained after the corrected invocations.

## Shared-main refresh history

After flyology-ada/agents PR #1 merged on 2026-08-23, the reviewed `main`
channel advanced to
`62eff321af50d7d6162fdcc042c32cb7ee5d5bca`. `apm update
flyology-ada/agents --yes` updated all seven shared package lock entries to that
commit without changing the root manifest's `ref: main`. The generated Codex
instructions were byte-for-byte unchanged; the shared
`maintain-agent-instructions` skill and deployment metadata changed in the
lock. The refresh passed `apm compile --target codex`, `apm compile
--validate`, frozen replay, CI audit, generated-file diff, and whitespace
validation before its focused commit.

After PR #2 merged the same day, `main` advanced to
`de62e63dbb25fff1b21b71673c9eefd6f5f38c38` and added the always-on review
cycle. `apm update flyology-ada/agents --yes` added the review-cycle package and
updated all eight shared lock entries to that exact commit while preserving
`ref: main` in the root manifest. A frozen install materialized the graph
before compilation. The generated `AGENTS.md` now contains `# Review cycle`
and requires an explicit findings sweep, P0/P1 fixes, P2 fix-by-default, and a
repeat review after fixes.

The refresh passed, in order, `apm install --frozen`, `apm compile --target
codex`, `apm compile --validate`, `apm audit --ci` with 10/10 checks, and `git
diff --check`. The compile emitted only the expected seven global-instruction
placement notices; validation and audit reported no primitive, integrity, or
deployment drift.

After PR #3 merged the same day, `main` advanced to
`1b5f7ec32a8672a92dfe658b62faa2ec98d1abb8`. All eight shared lock entries now
resolve to that exact commit while the root manifest retains `ref: main`.
The deployed `ada-hardcoded-constants` skill is version 0.2.0 and adds durable
adjacent source-comment requirements for consequential approved, externally
fixed, persisted-format, derived, project-policy, and test/reference values.
The generated `AGENTS.md` remained byte-for-byte unchanged because the update
changes the native skill resource rather than compiled instruction text.

The PR #3 refresh passed `apm install --frozen`, `apm compile --target codex`,
`apm compile --validate`, `apm audit --ci` with 10/10 checks, and `git diff
--check`. Compilation emitted only the seven expected global-instruction
placement notices; frozen replay and audit reported no drift.

The reviewed shared `main` channel later advanced to
`1c3a5d617152c91be3ad411fadb62ef68a93dbac`. Focused commit `c957e79` updated
all eight shared lock entries while retaining `ref: main`; the deployed
`ada-hardcoded-constants` skill is version 0.3.0. Its audit funnel treats raw
search counts as inventory, excludes routine mechanics and genuinely neutral
initialization by default, and still escalates independently selected policy,
format, sentinel, bound, timeout, retry, and capacity values. The refresh
passed frozen install, Codex compile, primitive validation, CI audit 10/10,
generated-file diff, and whitespace checks with no drift.

## Update policy

The root manifest deliberately names the mutable `main` channel. Exact
reproducibility and integrity come from the committed `apm.lock.yaml`, whose
`resolved_commit` records the reviewed shared revision above. Normal setup and
CI use `apm install --frozen` and therefore do not select a newer commit.

An intentional upgrade uses `apm outdated`, `apm update
flyology-ada/agents`, `apm compile --target codex`, `apm audit --ci`, and `git
diff --check`. The resulting lockfile and generated `AGENTS.md` require review
and a focused commit; validation CI must not run `apm update`.
