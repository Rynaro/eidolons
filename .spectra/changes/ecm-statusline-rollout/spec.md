# ecm-statusline-rollout — wire the statusLine key into `harness install`

**Tier:** lite · **Maker:** vivi · **Checker:** kupo · **has_code:** true

## Problem

`.spectra/changes/archive/2026-07-12-ecm-claude-statusline/spec.md` shipped
`eidolons statusline render` (`cli/src/statusline.sh`, nexus v2.7.0) and
explicitly deferred harness auto-wiring as a non-goal: *"This change wires
this repo's `.claude/settings.json` by hand."* That follow-up never landed.

`grep -rn 'statusLine' cli/src/harness_install.sh` returns zero matches —
`harness install` wires only `UserPromptSubmit` + `SessionStart` (+ ECM's
`PostToolUse` / `compactThreshold`). No consumer project gets the statusline;
the maintainer has it hand-wired locally, hardcoding an absolute path that is
machine-local, not the shipped shape.

This matters beyond cosmetics: the statusline is ECM's **rung-1 telemetry
feed**. Claude Code hands a statusline command a stdin payload carrying
`context_window.used_percentage` — exact context telemetry, no estimation —
and `context status --stdin` (`cli/src/context_status.sh`) was purpose-built
to consume exactly that. Without the wiring, the meter sits at
`estimate_source: unknown`, `zone: unknown`, and every rule in the ECM
decision policy (`roster/context-policy.yaml`) resolves to the fail-open
`continue` floor. The kernel runs blind on its own flagship host.

## Decision

Wire `statusLine` into `.claude/settings.json` from `harness install`, for
the **claude-code** host, gated on the same ECM opt-in (`context:` block in
`eidolons.yaml`) as `compactThreshold`. Follow the existing don't-clobber
precedent (`_write_compact_threshold`, `harness_install.sh:501-531`) exactly
— no new mechanism:

- **Write.** `{"type":"command","command":"eidolons statusline render",
  "padding":0,"refreshInterval":2}` — the command is the **installed CLI on
  PATH**, never an absolute path. `refreshInterval: 2` is deliberate: it
  makes the critical-zone pulse (`statusline.sh`'s self-decaying effects)
  blink while the session idles.
- **Don't-clobber.** A pre-existing `statusLine` whose `.command` is not
  ours is left byte-unchanged; `eidolons.lock` records
  `context.statusline_managed: false`. Only what we wrote is ours to manage.
- **Removal parity.** `harness remove` strips the `statusLine` key only when
  `statusline_managed` is `true` in the lock (same discipline as the
  `compactThreshold` strip, AC-RM-1's sibling).
- **Lock schema.** `schemas/eidolons.lock.schema.json` gains
  `context.statusline_managed` (boolean), alongside
  `compactthreshold_managed` / `codex_autocompact_managed`.

## Scope

| File | Change |
|---|---|
| `cli/src/harness_install.sh` | new `_write_status_line` writer (mirrors `_write_compact_threshold`); call site alongside the compactThreshold call; record `statusline_managed` in the `context:` lock block |
| `cli/src/harness_remove.sh` | read `statusline_managed` up front (alongside the existing managed-flag reads); strip `statusLine` when managed |
| `schemas/eidolons.lock.schema.json` | add `context.statusline_managed: boolean` |
| `cli/tests/harness.bats` | new AC-SL-1..6 tests |
| `CHANGELOG.md` | entry |

## Non-goals

- Codex/copilot/cursor/opencode statusline analogues — Claude Code is the
  only host with a `statusLine` settings key; no other host in
  `harness_install.sh`'s supported set exposes an equivalent surface.
- Any change to `cli/src/statusline.sh` itself, `cli/src/context*.sh`,
  `cli/src/lib_context.sh`, or `roster/context-policy.yaml` / `roster/pins.yaml`
  (kernel/policy fence — out of scope by the task boundary).
- `README.md` (IDG owns that section in parallel).

## Design constraints

- **bash 3.2** (macOS system bash) — no `declare -A`, `${var,,}`,
  `readarray`/`mapfile`, `&>>`.
- **Fail-open (ECM P0).** A malformed/absent `settings.json` warns and
  continues; never blocks install.
- **Idempotency.** A second `harness install` run leaves `.claude/settings.json`
  byte-identical (repo-wide hard invariant).
- `.claude/settings.json` is JSON — no marker-bounded blocks; the
  `statusline_managed` lock flag is the don't-clobber mechanism, same as
  `compactthreshold_managed`.

## Acceptance checks

| id | check |
|---|---|
| AC-SL-1 | ECM on + claude-code wired ⇒ `.claude/settings.json` `.statusLine.command` is exactly `eidolons statusline render`, and the lock records `context.statusline_managed: true`. |
| AC-SL-2 | Don't-clobber: a foreign pre-existing `statusLine` (e.g. `starship prompt`) is left **byte-unchanged** (sha256 before/after) by install; lock records `context.statusline_managed: false`. |
| AC-SL-3 | Idempotency: two consecutive `harness install` runs leave `.claude/settings.json` byte-identical. |
| AC-SL-4 | Remove (managed): `statusline_managed: true` ⇒ `harness remove` deletes the `statusLine` key; sibling keys (hooks, other top-level keys) survive intact. |
| AC-SL-5 | Remove (foreign): `statusline_managed: false` ⇒ `harness remove` leaves the foreign `statusLine` byte-unchanged (sha256 before/after). |
| AC-SL-6 | The load-bearing check: feeding `cli/src/statusline.sh` a realistic Claude Code stdin payload carrying `context_window.used_percentage` promotes the meter to `estimate_source: host` (not `unknown`) — proof the wiring closes ECM's rung-1 gap, not just that a key was written. |
