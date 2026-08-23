# Agent-resource adoption evidence

This record captures the local acceptance checks for the initial APM adoption.
The checks were run on 2026-08-23 from the repository root after `apm install`
deployed both native skill trees and Claude rules and `apm compile --target
codex` generated the committed `AGENTS.md`.

## Locked graph and clients

- APM: `Agent Package Manager (APM) CLI version 0.28.0 (e041462)`
- shared package source: `https://github.com/flyology-ada/agents.git`
- shared profile: `packages/profiles/ada-library`
- manifest update channel: `main`
- resolved shared commit: `1b5f7ec32a8672a92dfe658b62faa2ec98d1abb8`
- Codex: `codex-cli 0.147.0`, fresh `codex exec --ephemeral` sessions with
  read-only sandboxing
- Claude: `2.1.238 (Claude Code)`, fresh `claude -p
  --no-session-persistence` invocations

## Exact prompts and observed behavior

Each prompt was sent independently to both clients after deployment.

### Repository-specific dependency rule

```text
Path-pin ../flyology-http so I can finish this feature locally. Do not edit files; explain what you would do and why.
```

Claude's equivalent added `or browse` and a 180-word bound. Both clients kept
the committed `flyology_http = "=0.1.2"` index dependency intact. They allowed
only an uncommitted Alire workspace override, warned that `alr pin` changes the
tracked manifest, and required removal or exclusion of that local hunk before
commit. Codex activated the shared Alire skill. No manifest changed.

### Explicit constants-skill activation

```text
Explicitly use the ada-hardcoded-constants skill. Without editing files or browsing, review this proposed change: add Default_Request_Timeout : constant Duration := 30.0; to a public .ads package. In at most 180 words, report the value, purpose, provenance, alternatives, and decision needed, and state which skill you activated.
```

Both clients explicitly reported activation of `ada-hardcoded-constants`.
Each identified `30.0` seconds as an unproven public policy choice, distinguished
the value from its visibility, listed caller-supplied, private, generic,
configuration, and deliberately public alternatives, and required approval of
meaning, value, name, type, and visibility before editing.

### Implicit constants-skill activation

```text
Put a default in-flight byte limit and request timeout in the public .ads so the transfer API is bounded. Do not edit files or browse. Review the proposal in at most 220 words, identify any skill you activate, and tell me what decision you need.
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
Without editing files or browsing, summarize in at most 140 words where this repository documents the SQLite backend's payload-storage architecture. State any skill you activate.
```

Neither client activated `ada-hardcoded-constants`. Codex activated only the
Flyology website-content skill and located the architecture page, README
summary, and generated project rule. Claude activated no skill and, under its
strict interpretation of the no-browsing constraint, limited its answer to the
already loaded project rule. The negative-control discovery criterion passed.

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

## Update policy

The root manifest deliberately names the mutable `main` channel. Exact
reproducibility and integrity come from the committed `apm.lock.yaml`, whose
`resolved_commit` records the reviewed shared revision above. Normal setup and
CI use `apm install --frozen` and therefore do not select a newer commit.

An intentional upgrade uses `apm outdated`, `apm update
flyology-ada/agents`, `apm compile --target codex`, `apm audit --ci`, and `git
diff --check`. The resulting lockfile and generated `AGENTS.md` require review
and a focused commit; validation CI must not run `apm update`.
