# Scout report — ECM P1 kernel/harness integration surface

**Mission:** where/how do ECM P1 surfaces (`eidolons context status|policy|externalize|handoff`, meter.json, policy-log.jsonl, hook recipes, crystalium handoff convention — `docs/specs/ecm/spec.md` + `policy.yaml`) integrate into the existing nexus kernel.
**Downstream:** → RAMZA (P1 implementation spec), → FORGE (OQ-E1..E4 deliberation).
**Tier:** standard, read-only, medium breadth.

---

## 1. CLI verb wiring

- FINDING-001: `cli/eidolons` is a thin dispatcher: `case "$cmd" in ... esac` execs the matching `cli/src/<verb>.sh` (cli/eidolons:180-186, 330-341).
- FINDING-002: Two dispatch shapes coexist. (a) **Inline case**: `harness` and `memory` peel their sub-token inside `cli/eidolons` itself and exec directly (cli/eidolons:198-245 harness; 299-308 memory) — `cli/src/harness.sh` is legacy/dead code for the old Junction harness, not referenced by `cli/eidolons` at all (confirmed via grep: only self-refs + stale `.claude/worktrees/*` copies). (b) **Two-tier sub-dispatcher**: `mcp)` case execs `cli/src/mcp.sh "$mcp_sub" "$@"` (cli/eidolons:262-297), and `mcp.sh` itself does a second `case "$subcmd"` dispatching to one file per verb, `cli/src/mcp_<verb>.sh` (mcp.sh:47-79), with its own `--help` usage block (mcp.sh:16-45).
- FINDING-003: For `context status|policy|externalize|handoff` (4 sub-subcommands, each with non-trivial logic — a jq policy-evaluation program is ~170 lines in the routing analog), the **mcp.sh two-tier model is the best precedent**: add a `context)` case in `cli/eidolons` execing `cli/src/context.sh "$@"`, and `context.sh` internally dispatches to `context_status.sh` / `context_policy.sh` / `context_externalize.sh` / `context_handoff.sh` (mirrors mcp.sh:50-63). `memory.sh`'s single-file-with-inline-case (memory.sh:23-24,58-66) is the fallback model only if the verb count stays small.
- FINDING-004: Universal script header convention: `set -euo pipefail`; `SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`; `. "$SELF_DIR/lib.sh"` (mcp.sh:11-14, harness_install.sh:17-20, memory.sh:16-21, run.sh:14-17). Arg parsing: `while [[ $# -gt 0 ]]; do case "$1" in --flag) VAR=...; shift;; -h|--help) usage; exit 0;; *) die "Unknown option: $1";; esac; done` (harness_install.sh:74-86; memory.sh:230-267).
- FINDING-005: Bash 3.2 discipline is declared verbatim in every file header ("no declare -A, no `${var,,}`/`^^`, no readarray/mapfile, no `&>>`") — must be copied into new `context*.sh` files (mcp.sh:7-8, memory.sh:14, harness_install.sh:16).

## 2. Hook recipes

- FINDING-006: `harness_install.sh` writes host shims to `.eidolons/harness/hooks/<host>-<event>.sh` via `_write_shim` (SessionStart/UserPromptSubmit, harness_install.sh:120-195), `_write_pretooluse_shim` (strict PreToolUse, :200-324), `_write_stop_shim` (telemetry Stop, :329-358). **No PreCompact shim writer exists today** — zero references to "PreCompact" anywhere in `cli/` (confirmed by repo-wide grep; only hits are in `docs/specs/ecm/spec.md` and the survey doc). GAP-001.
- FINDING-007: `.claude/settings.json` merge is an idempotent surgical-append jq idiom, reused per event: read file → `_existing_canonical=$(jq -cS .)` → build `_merged` (append-if-command-absent per `.hooks.<Event>` array, upsert-in-place for SessionStart's matcher) → compare canonical forms → write only on diff (harness_install.sh:634-701 UPS/SessionStart/PreToolUse; :360-399 `_register_stop_in_settings` for Stop). This exact idiom is the template for a new `.hooks.PreCompact` branch.
- FINDING-008: SessionStart **already covers the post-compact source** — `_SS_MATCHER="startup|resume|clear|compact"` is the single-source-of-truth regex (harness_install.sh:24-27,401-436 self-heal `_heal_session_start_matcher`). So ECM's "SessionStart (incl. post-compact) → pin re-inject + handoff recall" needs no new hook *registration*, only extending the existing shim's *payload* (see FINDING-010).
- FINDING-009: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` (spec.md's proposed RED-boundary override) has **zero references** in the codebase — mechanism (env var vs. settings.json field) is unresolved. GAP-002.
- FINDING-010: `eidolons run --hook <host>` (run.sh) has two modes: `--session-start` (run.sh:87-93, no prompt) and `--stdin` (run.sh:95-112, extracts `.prompt`), both delegating to `harness_hook.sh`. Its `_main()` (harness_hook.sh:109-274) emits exactly `{"hookSpecificOutput":{"hookEventName":"<Event>","additionalContext":"<str>"}}` for both SessionStart (cortex digest + `## Prior project memory (CRYSTALIUM recall)` block from `eidolons memory preflight`, harness_hook.sh:147-167, + optional ESL block :169-184) and UserPromptSubmit (routing summary, :194-267). Wrapped in `_main 2>/dev/null || true` (:277) — fail-open, any error ⇒ empty stdout. This string-append composition (bounded `head -c 4000`) is the exact template for adding a `## Context policy` block (meter zone + verdict) to the same SessionStart payload, or a PreCompact analog.

## 3. Memory pre-flight

- FINDING-011: `eidolons memory preflight` (memory.sh) is a bounded one-shot crystalium recall, **out-of-MCP-session** (docker exec, not the live MCP tool), gated by `memory_probe_gated_in` = BOTH `.mcp.json` `mcpServers.crystalium` present (lib_memory_probe.sh:28-32) AND `eidolons.mcp.lock` has `"name: crystalium"` (lib_memory_probe.sh:36-40).
- FINDING-012: Invocation built by transforming `.mcp.json`'s crystalium `serve` args: strip `-i`, strip `--name <val>`, replace trailing `serve` with a caller-supplied recall string (`memory_probe_build_docker_script`, lib_memory_probe.sh:85-119); default recall args `recall --query ... --scope-project ... --k 5 --format json --layers semantic,episodic,procedural` (memory.sh:360) — `execution` layer explicitly excluded ("not a session-start artifact").
- FINDING-013: Timeout: prefers `timeout "${TIMEOUT}s"`, falls back to a bash-3.2 background-watcher (spawn+sleep+kill -TERM+reap) when the `timeout` binary is absent (memory.sh:381-397); default 8s (`EIDOLONS_MEMORY_PREFLIGHT_TIMEOUT`), TTL cache 900s at `.eidolons/harness/cache/preflight.json` (`EIDOLONS_MEMORY_PREFLIGHT_TTL`, memory.sh:224-226,319).
- FINDING-014: Output contract: stdout IS the digest (`[layer/tier] summary` lines, `[skill/tier]` for procedural, `head -c 1500`, memory.sh:424-426); any failure (gate/docker/JSON/zero-records) ⇒ empty stdout, exit 0 always (memory.sh:281-431 throughout).
- FINDING-015: **Directly reusable for ECM's handoff-recall** — `--query` override already exists (memory.sh:117,232-233) and is already the SessionStart injection path (harness_hook.sh:151-167). ECM's successor-session recall can be a new `eidolons memory preflight --query "<session_handoff query>"` call layered into the same shim call site — no new docker plumbing. GAP-004: which crystalium layer/topic_key filtering `session_handoff` records actually need (current call excludes `execution`) is unresolved — a FORGE/RAMZA decision (adjacent to OQ-E3/E4).

## 4. Table-driven config (routing.yaml pattern)

- FINDING-016: `run.sh` loads `roster/routing.yaml` once via `yaml_to_json` (run.sh:143) then applies ONE large `jq` heredoc program (`ROUTE_JQ`, run.sh:172-343, ~170 lines, `read -r -d '' ROUTE_JQ <<'JQ' ... JQ`) via `jq --arg ... --argjson ... "$ROUTE_JQ"` (run.sh:345-348) — all conditional logic lives inside jq operating on the parsed tree; no shell-side per-row branching.
- FINDING-017: `policy.yaml`'s `rules:` list (7 first-match-wins rows) is structurally simpler than routing.yaml's multi-stage pipeline — `context_policy.sh` should copy run.sh's *overall shape* (`yaml_to_json` → single named jq heredoc → apply), reading `meter.json` as the `$ctx` argjson analogous to `$CTX_JSON` (run.sh:163-169), not routing.yaml's chain/tier internals.
- FINDING-018: Bash-3.2-safe idioms confirmed: `[[ ]]` is fine (bash builtin, not banned); banned constructs are specifically `declare -A`, `${var,,}`/`${var^^}`, `readarray`/`mapfile`, `&>>` (per every file header + CLAUDE.md).

## 5. Lock recording

- FINDING-019: `harness_install.sh` writes/updates the `harness:` top-level key in `eidolons.lock` via **awk block-strip + regenerate** (not yq, to preserve surrounding formatting): `awk '/^harness:/{skip=1;next} skip&&/^[^[:space:]]/{skip=0} !skip{print}'` strips old block, new block text appended, no-op-checked before write (harness_install.sh:826-849).
- FINDING-020: Confirmed on-disk shape from this repo's own dogfooded `eidolons.lock` (repo root, lines 87-93):
  ```yaml
  harness:
    schema_version: 1
    hosts_wired:
      - claude-code
    shim_paths:
      - .eidolons/harness/hooks/claude-code-UserPromptSubmit.sh
      - .eidolons/harness/hooks/claude-code-SessionStart.sh
  ```
  plus optional `strict:`/`strict_modes:`/`protect:` (harness_install.sh:796-820). A parallel `context:` key (ECM version, effective host tier, resolved thresholds — spec.md §7) should reuse this exact awk-strip-and-regenerate idiom keyed on `/^context:/`.
- FINDING-021: `schemas/eidolons.lock.schema.json` and `schemas/eidolons.yaml.schema.json` exist and are validated by `make schema` — GAP-003: whether they currently even cover `harness:` was not checked in this scout (time-boxed); RAMZA must verify schema coverage before adding `context:`.
- FINDING-022: The dogfooded `eidolons.yaml` (repo root, lines 1-33) has no `context:` block today — confirms ECM's proposed block is purely additive/opt-in, same class as the existing `hosts:` block.

## 6. Telemetry overlap

- FINDING-023: `cli/src/telemetry.sh` is a **different concern and storage tier**: opt-in per-turn audited API-spend telemetry stored at `$EIDOLONS_HOME/telemetry/<project-slug>/<date>.jsonl` — nexus-cache-scoped, cross-project (telemetry.sh:73-74), not the consumer-project-local `.eidolons/.context/meter.json` ECM needs. No `utilization`/`zone`/`window_tokens` concept exists there.
- FINDING-024: The reusable *pattern*, not code, is the zero-logic Stop shim + `_register_stop_in_settings` wiring (harness_install.sh:329-358,363-399) — but ECM's policy.yaml fires on UserPromptSubmit/SessionStart/PreCompact only, not Stop, so this is a wiring-style precedent only, not a direct dependency.
- FINDING-025: `_telemetry_dispatch_stamp` in run.sh (run.sh:363-449) is similarly nexus-cache-scoped (`${EIDOLONS_HOME}/telemetry/.dispatch/`), gated on `EIDOLONS_TELEMETRY=1` or dir presence — not a meter.json reuse candidate.

## 7. Sidecar conventions

- FINDING-026: `.eidolons/harness/{hooks/,cache/}` is the existing precedent for a nested runtime dot-dir under `.eidolons/` (harness_install.sh:22 `HARNESS_SHIM_DIR=".eidolons/harness/hooks"`; memory.sh:319 cache file). Creation idiom: `mkdir -p "$DIR"` (harness_install.sh:481), fail-soft variant `mkdir -p "$DIR" 2>/dev/null || true` for best-effort writes (memory.sh:436).
- FINDING-027: Consumer `.gitignore` blanket-excludes `/.eidolons/*` except `!/.eidolons/cortex/` and `!/.eidolons/harness/manifest.json` (root `.gitignore:72-79`), generated by `apply_eidolons_gitignore` (lib.sh:1663-1700) via the generic `upsert_marker_block` helper, called ONCE from `init.sh:479` (not from sync). **A new `.eidolons/.context/` dir needs zero gitignore changes** — it's covered by the existing blanket rule automatically. (Confirmed this exact block is itself currently uncommitted in this checkout — `git diff .gitignore` shows it pending; this nexus repo dogfoods its own `init`/`sync`.)
- FINDING-028: No existing `.trace/`-under-`.eidolons/` or canonical-envelope-sidecar-writer convention was found — `trace.sh`/`verify_envelope.sh`/`sandbox.sh` (the only "ecl-envelope"/".envelope.json" hits) *consume* envelope paths passed as CLI args; none *write* a canonical sidecar location. ECM's `.eidolons/.context/handoff-<ts>.md` + `ecl-envelope.json` pair is a genuinely new on-disk convention — closest analog is the harness shim dir's flat-file-per-name layout.
- FINDING-029: stderr discipline is absolute: all say/ok/info/warn/die → stderr (lib.sh:75-88); stdout reserved for machine output only ("stdout IS the digest and nothing else", memory.sh:10-11). Any new `context status`/`context policy --json` verb must preserve this split exactly.

## 8. Test conventions

- FINDING-030: `cli/tests/helpers.bash` `setup()`/`teardown()` export `EIDOLONS_NEXUS=$EIDOLONS_ROOT`, a per-test `EIDOLONS_HOME=$BATS_TEST_TMPDIR/eidolons-home`, and `cd` into a fresh `$BATS_TEST_TMPDIR/project` (helpers.bash:28-40); every test file starts with `load helpers`.
- FINDING-031: `seed_manifest`/`seed_lock` (helpers.bash:47-72) provide minimal fixtures; `harness.bats` extends locally with its own `seed_lock_with_harness` (harness.bats:24-53) rather than editing shared helpers — a `context.bats` suite should add its own local `seed_lock_with_context` following this precedent.
- FINDING-032: `harness.bats` has 94 `@test` cases, `memory.bats` 23, organized under `# ─── R<N>: <name> ───` comment headers mapping to spec requirement IDs (harness.bats:78) — a `context.bats` suite should adopt the same per-P-rule (P1-P7) / R-id block convention once RAMZA assigns requirement IDs.
- FINDING-033: `make test` runs `bats --jobs N --no-parallelize-within-files` (CLAUDE.md) — files run concurrently, tests within a file sequentially; each test's isolated `$BATS_TEST_TMPDIR` means a new `context.bats` needs no special contention handling, mirroring harness.bats/memory.bats today.
- FINDING-034: Fail-open shim testing technique: "write a minimal shim pointing at a nonexistent path; execute it; assert exit 0 and empty stdout" (harness.bats:16) — reuse directly to validate a new PreCompact shim's fail-open contract.

---

## Gaps

- GAP-001: Claude Code's live PreCompact hook payload/behavior is unverified in-repo (spec.md itself flags `[VERIFY — ATLAS probe before P1 freeze]`, spec.md:266); needs an out-of-repo/runtime probe, not resolvable from static code alone.
- GAP-002: `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` mechanism (env var vs settings field) is undetermined — zero code references.
- GAP-003: Whether `schemas/eidolons.lock.schema.json` / `eidolons.yaml.schema.json` currently cover the existing `harness:` key was not verified (not read, time-boxed) — check before adding `context:`.
- GAP-004: Which crystalium layer/topic_key filter targets `session_handoff` records, and whether memory.sh's hardcoded `--layers semantic,episodic,procedural` needs to change, is unresolved (adjacent to OQ-E3/E4).
- GAP-005: No prior ATLAS scout-report on this exact harness surface exists in crystalium memory (recall returned only the ECM design summary, not a prior code-level scout) — this report is the first; no baseline to delta against.

## Handoffs

→ **RAMZA**: model `context status|policy|externalize|handoff` on the `mcp.sh` two-tier dispatcher (FINDING-002/003); model `context_policy.sh`'s evaluation on `run.sh`'s single-jq-heredoc shape reading `meter.json` as `$ctx` (FINDING-016/017); reuse `eidolons memory preflight --query` verbatim for handoff-recall, no new docker plumbing (FINDING-015, pending GAP-004); add a PreCompact shim-writer + settings.json jq-merge branch mirroring the existing UPS/SessionStart merge, and extend the SessionStart shim payload (already post-compact-aware) with a context-policy block (FINDING-006/008/010); add a `context:` lock key via the same awk-strip-regenerate idiom as `harness:` (FINDING-019/020) plus schema updates (GAP-003); no `.gitignore` changes needed for `.eidolons/.context/` (FINDING-027); new `context.bats` should follow harness.bats's local-helper + R-id-block conventions (FINDING-030-034).
→ **FORGE**: close GAP-001 (PreCompact payload) and GAP-002 (autocompact override mechanism) before P1 freeze, per spec.md's own [VERIFY] flags; resolve GAP-004 (session_handoff targeting) as part of OQ-E3/E4.
→ **human**: none required — surface is decision-ready for P1 kernel wiring.

## Telemetry

phase: L | tool_calls: ~24 | probes: read/view/grep only | confidence: H on all 8 sub-questions except hook-payload verification (GAP-001, out-of-repo) | fold_ratio: n/a (single-pass scout, no sub-agent scatter — surface was serial/small enough per mission's "medium breadth" framing)
