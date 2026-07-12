# ecm-claude-statusline — Final-Fantasy HUD + ECM rung-1 telemetry feed

**Tier:** lite · **Maker:** opus-orchestrator · **Checker:** kupo · **has_code:** true

## Problem

`docs/specs/ecm/spec.md:266` (Claude Code, tier **T3**) promises:

> statusline JSON `context_window.used_percentage` → exact telemetry, no estimation

and `cli/src/context_status.sh:6,94-111` was purpose-built to consume that payload
(`--stdin` reads `.context_window.used_percentage`, `.transcript_path`, `.session_id`,
`.context_window.context_window_size`). Evidence C4 in
`.spectra/changes/archive/2026-07-07-ecm-context-kernel/evidence-host-facts.md:12`
records the field set as **CONFIRMED** against the official docs.

**But nothing ever writes the `statusLine` key.** `harness_install.sh` wires only
`UserPromptSubmit` + `SessionStart`. The rung-1 source is specced, built for, and
never connected. Observable consequence — this repo's live meter before the change:

```json
{ "utilization": null, "estimate_source": "unknown", "zone": "unknown" }
```

ECM's decision policy therefore resolves every rule to `continue` (the fail-open
floor). **The context kernel is running blind on its own flagship host**, silently
degraded to rung-3 rather than the rung-1 the spec claims.

## Decision

Ship `eidolons statusline render` — a Claude Code statusline command that:

1. **Feeds the meter (load-bearing).** Pipes its stdin payload straight into
   `eidolons context status --stdin`, promoting the meter from `estimate_source:
   unknown` → `host`. Measured at ~60 ms, inside the ECM CC3 ≤ 300 ms prompt-path
   budget. This is *implementing a frozen spec decision*, not opening a new one —
   hence `tradeoff_present: false` at the right-sizing gate.
2. **Renders a 2-row Final-Fantasy battle-window HUD (cosmetic).** Surfaces what
   makes Eidolons legible at a glance: the ECM context gauge coloured by **zone**
   (green → amber → red → critical), the active ESL quest, the dispatched Eidolon,
   gil (cost), and the party size.

Non-goals (deliberate, deferred to a follow-up **full**-tier change): harness
auto-wiring (`harness_install.sh` / `harness_remove.sh` removal parity, seam #11 of
`.spectra/scout/ecm-p2-host-surfaces.md`), `eidolons.lock` tier field, `doctor`
reporting. This change wires **this repo's** `.claude/settings.json` by hand.

## Scope

| File | Change |
|---|---|
| `cli/src/statusline.sh` | **new** — payload parse, meter feed, HUD render |
| `cli/eidolons` | register `statusline` subcommand + help text |
| `cli/tests/statusline.bats` | **new** — acceptance checks below |
| `CHANGELOG.md` | entry |
| `.claude/settings.json` | *(local wiring, not shipped)* |

## Design constraints

- **Fail-open, always exit 0.** A non-zero exit or empty stdout blanks the status
  line (docs). Every failure path degrades to a reduced HUD, never a blank one.
- **Never source `lib.sh`.** It runs on every assistant message; the renderer stays
  self-contained (`jq` + `git` only) to protect the latency budget.
- **Force colour.** `ui/theme.sh` gates ANSI on `[[ -t 2 ]]`, but Claude Code
  *captures* stdout — a TTY test would render the HUD permanently colourless.
  Emit ANSI unconditionally, honouring only `NO_COLOR`.
- **Cache git by `session_id`.** Per docs: `$$` changes every invocation and defeats
  the cache; `session_id` is stable per session. 5 s TTL.
- **Width-responsive via `$COLUMNS`.** `tput cols` cannot see the terminal from
  inside a statusline script; Claude Code exports `COLUMNS`. Degrade by dropping
  segments right-to-left.
- **Bash 3.2.** No `declare -A`, `${var,,}`, `readarray`, `&>>` (macOS system bash).

## v2 amendment — effects, MP, identity, DX (maker re-entry 2026-07-11)

Same surface, same tier (re-gated: 5 files / rubric 5 / no tradeoff → **lite**).
The v1 render was static; v2 makes it *react*. Design rule for every effect:
**self-decaying, no timers** — the statusline re-renders after each assistant
message, so an effect fires on the render where its trigger condition holds and
decays naturally on the next. State between renders lives in a session-keyed
sidecar (`eidolons-statusline-<sid>.state`, plain positional lines, same
no-shell-syntax rule as the cache).

1. **MP gauge** (row 2, right). `rate_limits.five_hour.used_percentage` was
   parsed in v1 and never rendered. FF mapping: context = HP/limit gauge,
   rate-limit = **MP** — remaining, so it drains as you cast. Absent when the
   payload has no `rate_limits` (API-key users see no empty socket).
2. **Delta popup**. `↑n`/`↓n` beside the context % when it moved since the last
   render of the same session — damage numbers off the gauge. Absent on the
   first render (no prior state).
3. **Zone-transition flash**. Reverse-video zone label on exactly the render
   where the zone changed; normal on the next. At `critical` the label pulses
   (reverse on even seconds) — with `"refreshInterval": 2` wired it blinks like
   the FF low-HP alarm; without it, it still alternates per message.
4. **Quest-complete fanfare**. When the tracked quest transitions
   `in_progress → verified` between renders, one render shows
   `✓ <quest> COMPLETE!` in place of the quest segment, then decays.
5. **Job titles**. `model.id` → FF job, dim, inside the job brackets at wide
   widths: fable→Sage, opus→Summoner, sonnet→Bard, haiku→Ninja.
6. **Party colours**. `agent.name` matching a roster capability class renders in
   its class colour (kupo = moogle pink, vigil = red, vivi = blue, …) — the
   sigil identity system carried into the one-line format.
7. **OVERFLOW marker**. `exceeds_200k_tokens: true` → red `OVERFLOW` on row 2.
8. **DX verbs**: `eidolons statusline demo` (renders a canned five-frame session
   arc — green → amber flash → dispatch → red → critical pulse — then prints the
   settings.json wiring snippet) and `eidolons statusline doctor` (**read-only**
   environment check: jq/git presence, settings.json wiring, meter freshness +
   estimate_source, one timed render vs the CC3 budget).

Non-goals unchanged (harness auto-wiring stays the follow-up full-tier change).

## Acceptance checks

| id | check |
|---|---|
| AC-SL-1 | Given a payload with `context_window.used_percentage`, the meter is written with `estimate_source: "host"` and the correct `zone` (rung-1 promotion). |
| AC-SL-2 | Renders exactly 2 lines on stdout, and exits 0. |
| AC-SL-3 | Zone colour tracks the ladder: `<50` green, `≥50` amber, `≥75` red, `≥90` critical. |
| AC-SL-4 | Fail-open: empty stdin / malformed JSON / absent `jq` / absent git repo still exits 0 with non-empty stdout. |
| AC-SL-5 | `NO_COLOR=1` emits zero ANSI escape sequences. |
| AC-SL-6 | Renders within the ECM CC3 budget (≤ 300 ms). |
| AC-SL-7 | Bash 3.2 compatible — no `declare -A`, `${var,,}`, `readarray`, `mapfile`, `&>>`. |
| AC-SL-8 | Narrow terminal (`COLUMNS=60`) does not wrap: no emitted line exceeds `$COLUMNS` display width. |
| AC-SL-9 | A payload with `rate_limits.five_hour.used_percentage` renders an MP gauge showing *remaining*; a payload without `rate_limits` renders no MP segment. |
| AC-SL-10 | Second render of the same session with a different `used_percentage` shows a `↑n`/`↓n` delta; the first render shows none. |
| AC-SL-11 | A zone transition renders the zone label in reverse video exactly once — present on the transition render, absent on the following same-zone render; suppressed entirely under `NO_COLOR`. |
| AC-SL-12 | When the tracked quest state observed by the renderer goes `in_progress → verified` between renders, the next render shows `COMPLETE` once, then decays. |
| AC-SL-13 | `statusline demo` exits 0 and emits ≥5 HUD frames plus the `statusLine` wiring snippet; `statusline doctor` exits 0 and leaves `.claude/settings.json` byte-identical (read-only). |
| AC-SL-14 | `agent.name` = a roster member renders with that class's ANSI colour; `model.id` containing fable/opus/sonnet/haiku renders its job title at `COLUMNS≥100`. |
| AC-SL-15 | All v1 invariants hold with v2 segments live: width discipline at 40..120 (MP + delta + fanfare included), fail-open with an unwritable state file, `NO_COLOR` still emits zero ANSI. |
