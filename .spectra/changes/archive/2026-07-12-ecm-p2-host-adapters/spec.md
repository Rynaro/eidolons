---
Title: ECM P2 — Host-Adapter Recipes (context management beyond Claude Code)
Version: 1.0.0
Date: 2026-07-07
Author: RAMZA (planner) — scribed by orchestrator; Track H reconciled for atomos GO
tier: full
plan_id: ecm-p2-host-adapters
criteria_ref: acceptance-criteria.md
criteria_sha256: 629b0f10200d9fba6e01c187b9a8af3961953042c2de7a63c4a5335c8573281f
Target:
  - cli/src/harness_install.sh
  - cli/src/harness_hook.sh
  - cli/src/harness_remove.sh
  - cli/templates/harness/opencode-eidolons.js
  - schemas/eidolons.lock.schema.json
  - cli/tests/context.bats
  - cli/tests/harness.bats
---

# ECM P2 — Host-Adapter Recipes (FULL spec)

## Framing

ECM P1 shipped a fully host-agnostic context kernel (`context*.sh`: meter math,
P1–P7 policy table, externalize, handoff) and wired **exactly one** host — Claude
Code — through the harness (`harness_install.sh` recipes + `harness_hook.sh` output
dialect). P2 does **not** touch the kernel or the Claude recipe: it adds **per-host
adapter branches** so each of `{codex, opencode, copilot, cursor}` gets the *subset*
of the ECM ladder its injection channel actually permits — nothing more. The
load-bearing split is **host-agnostic core (reused untouched) vs. host-adapter
wiring (the only new surface)**. The posture is **asymmetric-by-honesty and
fail-open everywhere**: codex earns the full ladder (its channel mirrors Claude's),
opencode a system-prompt meter + compaction externalize, copilot a start-only static
pin/handoff digest, cursor a static documentary floor with an *explicit*
no-live-injection statement — and a host with a broken or absent channel still
installs a floor and exits 0. Fail-open is a P0, not a nicety.

## Right-size (mechanical gates — run, not asserted)

`ramza-rightsize` → **full** (score 6/9: files_touched 8 [+1]; --public-api lock
schema [+1]; --migration removal-parity fixes a P1 lock/settings gap [+1]; --novel
per-host channel divergence [+1]; --stakes high [+2]). `ramza-score --rubric
complexity` → **10/12 human_loop** (scope 3 + ambiguity 2 + dependencies 3 + risk 2).
`tradeoff_present = Y` — the same ECM intent maps to four materially different
enforcement tiers; pretending otherwise (e.g. claiming a live meter on cursor) would
be dishonest and break fail-open. `ramza-score --rubric confidence` → **84 VALIDATE**
(two open items: the codex auto-compact config key/units `[A-CODEX-CFG]`, and the
open independent-critic gate — maker≠checker bars the author from self-checking).

## Verified host injection-channel matrix (build ONLY on what is confirmed)

| host | reliable channel | granularity | ECM surface |
|---|---|---|---|
| **Codex** | `.codex/hooks.json` `hookSpecificOutput.additionalContext` at SessionStart/UserPromptSubmit/Pre+PostToolUse; knob `model_auto_compact_token_limit` | ALL | **full ladder** |
| **OpenCode** | plugin `experimental.chat.system.transform` (`output.system`) + `experimental.session.compacting` | start + per-prompt (system-prompt) | meter line + compaction externalize |
| **Copilot** | `.github/copilot-instructions.md` (re-read each request); hooks documented-but-broken (#1139, #2980) | start-only static | pin/handoff digest block |
| **Cursor** | `.cursor/rules/*.mdc` static; hook injection confirmed broken by Cursor's team | static only, no live injection | documentary floor + explicit limitation |

## Scope

**IN** — four host adapters (codex full · opencode meter+compaction · copilot
start-only static · cursor static floor); removal parity for every ECM write per host
(incl. the two P1 gaps: `compactThreshold` in `.claude/settings.json` and the
`context:` block in `eidolons.lock` are never stripped today); `eidolons.lock`
records effective per-host ECM tier + channel, schema extended additively; one ECM
behavior/parity test per host per wired channel.

**OUT** — any change to the Claude-Code recipe behavior (codex etc. are added
*alongside* the literal-`claude-code` gates; claude-code install output must stay
byte-identical, regression-guarded); inventing a channel a host does not expose (no
per-tool meter on opencode/cursor/copilot; no fabricated per-prompt inject on
cursor/copilot); kernel edits (`context*.sh` reused verbatim); editing the shipped
policy (`roster/context-policy.yaml`, `roster/pins.yaml` are *served*, never
modified); KV/serving-layer; re-declaring CRYSTALIUM layers or extending ECL's ten
performatives. **An MCP is explicitly ruled out for the injection problem** — an MCP
cannot manufacture an injection channel (`decisions/atomos-go-no-go.md`).

## Host-agnostic core / host-adapter split (design of record)

Reuse untouched (scout §3, §7): `context.sh`, `lib_context.sh`, `context_policy.sh`,
`context_externalize.sh`, and the bodies of `context_status.sh` / `context_handoff.sh`.
Host-neutral helpers reused as-is in `harness_hook.sh`: `_ecm_project_enabled`
(`:120-129`), `_ecm_pins_reminder` (`:134-140`), `_ecm_handoff_digest` (`:147-156`).
All P2 code lands in **`harness_install.sh`** (per-host recipe branches replacing the
literal-`"claude-code"` gates at seams 1/3), **`harness_hook.sh`** (host-set doc only
— the PostToolUse/UPS/SessionStart emitters already branch on `hook_mode`, not host,
so codex is served with zero body change), **`harness_remove.sh`**, the **opencode
plugin template**, the **lock schema**, and the **two bats files**.

## Tracks (acceptance criteria frozen in `acceptance-criteria.md`, SHA `629b0f10…`)

- **Track A — Codex (T3, full ladder)** — AC-CDX-1..7. Call the existing
  `_write_posttooluse_meter_shim "codex"` (body already `POSTTOOLUSE_HOST`-parameterized)
  wired at the seam-1 gate (`:669`); register PostToolUse in `.codex/hooks.json` via the
  wholesale jq-`-n` build (`:915-925`, flat `[{"command":…}]` schema); SessionStart
  pins/handoff + UserPromptSubmit meter line need **no new code** (`harness_hook.sh`
  already emits the codex dialect, gated on `hook_mode`); write
  `model_auto_compact_token_limit` **don't-clobber** to `.codex/config.toml` (grep-guarded
  append, `[A-CODEX-CFG]` warn on unverified key/units, mirroring `[ASSUMPTION A1]`).
- **Track B — OpenCode (T1, start + per-prompt)** — AC-OC-1..4. Extend
  `cli/templates/harness/opencode-eidolons.js`: `experimental.chat.system.transform`
  shells to `eidolons context status --json` (fail-open to the sidecar) and appends
  `Context: zone=… util=…` to `output.system`; start injection prepends the pin digest;
  `experimental.session.compacting` fires `eidolons context externalize`. Broaden the
  install trigger to copy the plugin when `context:` is on (today `--strict` only).
- **Track C — Copilot (T2, start-only static)** — AC-CP-1..4.
  `upsert_marker_block ".github/copilot-instructions.md" "ecm-context" "$body"`
  (`lib.sh:1219`), body = pin digest + handoff digest; **no live-meter claim** (honest
  static floor).
- **Track D — Cursor (T2 static floor)** — AC-CR-1..4. Write a dedicated
  `.cursor/rules/eidolons-context.mdc` (`alwaysApply: true`) whose marker block states
  the pins + the **static-only limitation explicitly**; a dedicated file keeps removal a
  clean `rm -f` and avoids entangling the sync-owned cortex `.mdc`.
- **Track E — Removal parity** — AC-RM-1..6. Extend `harness_remove.sh`: strip
  `compactThreshold` (P1 gap fix) and the `context:` lock block (P1 gap fix), the codex
  knob (when lock `managed=true`), the copilot marker block, the cursor `.mdc`;
  install→remove→install byte-identical. Don't-clobber-aware (strip managed writes only).
- **Track F — Fail-open invariant (P0)** — AC-FO-1..3. No reliable channel (cursor)
  still exits 0 with a floor; zone `unknown` ⇒ policy `continue` on every host;
  unwritable/invalid codex config ⇒ warn + exit 0, other hosts still wired.
- **Track G — Lock + schema (additive)** — AC-LK-1..3. `eidolons.lock.schema.json`
  `context` block gains `per_host` (host → `{tier, channel, ecm_features[]}`) and
  `codex_autocompact_managed` (boolean); the existing `context.host_tier` (max) is
  retained; both a P1 lock and a P2 lock validate.
- **Track H — atomos P2-exit tripwire** — **RETIRED (see amendment).** AC-TW-1/AC-TW-2
  are superseded by the maintainer's **atomos GO** decision (2026-07-07): atomos is a
  committed P3 build, not deleted at P2 exit. P2 field evidence *informs* atomos design;
  it does not gate it. See `amendment-atomos-go.md` and
  `docs/specs/ecm/decisions/atomos-go-no-go.md` §0. No code, no gate for this track.

## Drift fence

**files_allowed** (8 globs): `cli/src/harness_install.sh`, `cli/src/harness_hook.sh`,
`cli/src/harness_remove.sh`, `cli/templates/harness/opencode-eidolons.js`,
`schemas/eidolons.lock.schema.json`, `cli/tests/context.bats`, `cli/tests/harness.bats`.
(RAMZA's 8th glob `docs/specs/ecm/spec.md §8` was for the Track-H atomos-line delete —
**withdrawn** with Track H's retirement; the spec.md atomos flip was instead made by the
orchestrator under the atomos-GO decision, not this change.)

**files_forbidden** (any change = DRIFT): the agnostic kernel core (`context.sh`,
`lib_context.sh`, `context_policy.sh`, `context_externalize.sh`, `context_status.sh`,
`context_handoff.sh`); `roster/context-policy.yaml`, `roster/pins.yaml` (the shipped
policy the recipes SERVE); the claude-code recipe internals in `harness_install.sh`
(`_write_compact_threshold(claude)`, claude base-hooks JSON, `_SS_MATCHER`, the
claude-code PostToolUse behavior must stay byte-identical). Guard: a
`harness install --hosts claude-code` diff before/after P2 must be byte-identical.

## Notes for the executor (Vivi)

- **bash 3.2 only**: no `declare -A`, `${var,,}`/`${var^^}`, `readarray`/`mapfile`,
  `&>>`. The `sed -i '' … || sed -i …` dual form (`harness_install.sh:448-449`) is the
  portable in-place edit; copy it for any codex-config append.
- **stderr discipline**: `say/ok/info/warn/die` → stderr; helpers whose stdout is
  captured (managed-flag echoes) keep stdout clean.
- **marker-bounded idempotent writers**: copilot/cursor floors use
  `upsert_marker_block DST "ecm-context" BODY` (`lib.sh:1219`); removal uses
  `remove_marker_block DST "ecm-context"` (`lib.sh:1290`). Never hand-roll marker awk.
- **jq -cS idempotency**: every JSON writer compares `jq -cS .` before/after; codex
  PostToolUse folds into the existing wholesale build at `:915-925`, not a second write.
- **codex TOML don't-clobber**: no jq for TOML — `grep -q '^model_auto_compact_token_limit'`
  guard, append only if absent; echo a managed flag; `[A-CODEX-CFG]` warn on the
  path/units (mirror `[ASSUMPTION A1]` at `:908`).
- **exact seams (scout §7)**: codex at seam-1 `:669-674` and seam-3 `:853-864`; the
  PostToolUse shim writer is seam-2 `:422-451` (call for codex, don't fork it); codex
  hooks.json block `:902-940`; opencode plugin copy `:715-730`; lock `context:` writer
  `:1017-1055` (add `per_host`); removal strips `harness_remove.sh:80-128` (generic) +
  new neighbors and the lock `awk /^context:/` strip modeled on `:156-160`.
- **tests**: FINDING-031 — do NOT edit shared `helpers.bash`; add local seeds per file.
  Reuse `seed_manifest_ecm_on` / `seed_lock_with_context` / `setup_fake_eidolons_bin`
  (`context.bats:28-125`); codex parity template is `harness.bats:1655-1667`.
- **fail-open is P0-graded**: every new writer exits 0 on error and leaves other hosts
  wired (AC-FO-1..3).
- **primary premise to attack** (for the checker): `[A-CODEX-CFG]` — if the codex
  config file/key/units for `model_auto_compact_token_limit` is wrong, Track A piece 4 +
  AC-CDX-6/7 + AC-RM-3 shift, but the codex hook ladder (pieces 1–3, the headline win)
  is unaffected.
