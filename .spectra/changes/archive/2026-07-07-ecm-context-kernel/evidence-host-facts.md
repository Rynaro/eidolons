# Evidence: Claude Code host-surface verification (2026-07-06)

> Probe: claude-code-guide agent against official docs (code.claude.com/docs —
> hooks.md, statusline.md, settings.md). Gates the ECM P1 spec freeze.
> Consumers: FORGE (OQ-E1..E4), RAMZA (P1 spec §host recipes).

| # | Claim (spec.md §5, T3 row) | Verdict | Mechanism |
|---|---|---|---|
| C1 | PreCompact hook (manual/auto matchers, pre-compaction inject) | **UNVERIFIED** — not in the documented hook-event set; docs mention "20+ additional events" without listing | Do NOT anchor P1 on PreCompact. Treat as enhancement probe [WATCH]. |
| C2 | SessionStart sources incl. post-compact | **CONFIRMED** — literal matchers `startup`, `resume`, `clear`, **`compact`**; output `additionalContext` (also `sessionTitle`, `watchPaths`, `reloadSkills`); no documented size cap | Pin re-injection + handoff recall anchor HERE. `compact` fires after compaction — pins re-enter immediately post-loss. |
| C3 | UserPromptSubmit inject + block | **CONFIRMED** — `hookSpecificOutput.additionalContext`; `decision: "block"`; default timeout 30 s | Meter digest + policy verdict injection anchor. |
| C4 | Statusline stdin JSON context telemetry | **CONFIRMED** — `context_window.total_input_tokens`, `.total_output_tokens`, `.context_window_size`, **`.used_percentage`**, `.remaining_percentage`, `.current_usage.{input_tokens,output_tokens,cache_creation_input_tokens,cache_read_input_tokens}`, `exceeds_200k_tokens`, `cost.*`, `rate_limits.*` | First-class meter source on Claude Code — **no estimation needed** (OQ-E1 input: host tier gives exact numbers; bytes/4 only for hosts without telemetry). |
| C5 | `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | **PARTIAL** — env var confirmed, percentage 0–100, overrides the `compactThreshold` setting; numeric default undocumented | `harness install` can set it to the RED boundary (75). Prefer writing `compactThreshold` in settings.json (marker/jq-merge) over exporting env. |
| C6 | PostToolUse as meter-refresh carrier | **PARTIAL** — fires per tool call, CAN return `additionalContext`; per-tool frequency = cost concern | Use for meter *refresh into sidecar* (cheap, no injection) and inject only on zone change. Statusline `refreshInterval` refreshes display, not context. |
| C7 | `transcript_path` in hook payloads | **CONFIRMED** — common field on all hook events (+ statusline) | Fallback byte-size estimation path exists everywhere hooks exist. |

## Corrections applied to the draft spec

1. **spec.md §5 T3 row**: "PreCompact → externalize + pin prep" is unanchored in
   current docs. Corrected anchor set: SessionStart(`compact`) for post-loss pin
   re-inject + handoff recall; UserPromptSubmit for meter/policy inject;
   PostToolUse for sidecar meter refresh (inject only on zone transition);
   statusline JSON as the exact-telemetry source.
2. **Externalize-before-compact timing**: without a confirmed pre-compaction
   hook, externalization cannot wait for a compaction signal — it must be
   *amber-zone-eager* (policy P5/P6 already do this: checkpoint while cheap).
   This retroactively strengthens the P6 design: externalize at amber IS the
   pre-compaction hook on hosts without one.
3. **OQ-E1 input**: Claude Code needs zero estimation (`used_percentage` is
   given). The bytes/4 question only concerns hosts without telemetry.
