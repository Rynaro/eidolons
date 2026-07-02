# v2.0 Audit — Nexus Harness Mechanization (v1.46.1, 2026-07-02)

> Fan-out audit agent report vs `DOSSIER-HARNESS-2026-06.md` roadmap.
> Headline: the dossier roadmap is substantially **built**. Kernel, harness verb family,
> memory preflight, five host static surfaces, strict tier, ECL/trace/telemetry spine all
> exist with heavy bats coverage. Load-bearing gaps: (a) per-step model-tier computed but
> never injected into any host; (b) Codex read-surfaces are unverified assumptions;
> (c) several claimed tiers rest on vendor-broken behavior; (d) memory post-flight is prose.

## Roadmap status

P0: G10 Codex `.toml` (sync.sh:440-453, [ASSUMPTION A2] shape), G3/G8 Copilot
`.agent.md` (sync.sh:456-472), CLAUDE.md lexical gate fixed (sync.sh:707-709 —
"delegate by default") — ALL IMPLEMENTED.

P1: `harness install|remove|status` IMPLEMENTED (cli/eidolons:198-240;
harness_install.sh jq -cS canonical merges; lock-recorded :780-850).
`run --hook` IMPLEMENTED for claude-code + codex (harness_hook.sh:186-247, fail-open :252).
Claude Code adapter IMPLEMENTED (UPS + SessionStart shims :122-195; matcher self-heal
:407-436). Codex adapter PARTIAL — hooks.json is [ASSUMPTION A1] (:744-746), unverified.
`memory preflight` IMPLEMENTED via **docker exec** transform of .mcp.json args
(memory.sh:169-227), gated on .mcp.json+lock (:117-129), TTL 900s, 8s timeout, fail-open;
wired into SessionStart (harness_hook.sh:147-166).

P2: Cursor .mdc IMPLEMENTED (sync.sh:745-802, dual-written with AGENTS.md).
Cursor strict REFUSED by design (hooks broken ≤2.4.7; harness_install.sh:582-585).
Copilot hooks PARTIAL — sessionStart-only (:718-738); per-prompt inject impossible
upstream (copilot-cli#1139).

P3: OpenCode plugin IMPLEMENTED advisory (templates/harness/opencode-eidolons.js);
`opencode.json` permission.task hand-off graph IMPLEMENTED from roster downstream
(sync.sh:804-916). Strict tier IMPLEMENTED tiered: claude-code=block, codex=globs-only,
opencode=advisory, cursor=refused. doctor --deep D12 effective-tier report IMPLEMENTED
(doctor.sh:979-984). **Per-host canary MISSING** — canary.sh is per-Eidolon behavioral,
not per-host tier.

Compliance A/B instrument (FORGE 80% reversal gate) IMPLEMENTED
(eval_compliance.sh, runbook in .spectra/harness-mechanization/).

## Effective tier per host (mechanical reality)

| Host | Claimed | Reality |
|---|---|---|
| claude-code | T3 | **Genuine T3** — inject + block real and tested |
| codex | T3 | **T1–T2** — hook schema unverified, toml stub, delegate-or-deny refused |
| copilot | T2 | T2-floor — static prose reliable; sessionStart may drop (#2142) |
| cursor | T2 | T2 static-only (alwaysApply .mdc + AGENTS.md) |
| opencode | T1 | T1 — permission.task graph is the one sound block; plugin advisory (#5894) |

Degradation to T0 documentary holds everywhere (fail-open shims/memory/hooks).

## Model-tier routing

Static expression exists end-to-end (routing.yaml tiers: idg/kupo=light,
atlas/vivi/apivr=standard, spectra/forge/vigil=deep; model-profiles.yaml;
lib_model_resolve.sh precedence PIN→calibration→profile→roster→class default).
Wired ONLY as claude-code `.claude/agents/*.md` frontmatter (lib_model_wiring.sh:240-298).
**Codex model wiring is dead** — writes `.md` Codex ignores; the `.toml` has no model field.
**`model_tier_per_step` computed by kernel (run.sh:256-277) but harness_hook.sh never
injects it** — zero grep hits. TRANCE "lead=deep, workers=light" (EIDOLONS.md:78) has no
code path.

## Mechanical guarantees already in place

Deterministic routing (run.sh:172-307); refusal rerouting (:240-247); tau abstain 0.6
(:271-289); TRANCE gated (:226-229); ECL SHA-256 verify-block exit 3 (verify_envelope.sh:
199-203, run.sh:130-141); idempotent jq -cS host writes; fail-open everywhere; bounded
memory preflight; strict delegate-or-deny + protected-globs (claude-code) with CLI refusal
of known-buggy surfaces; model drift doctor D9; lockfile source of truth; D12 tier report;
ESL forcing-function inject (harness_hook.sh:36-105,168-239, opt-in via tonberry presence).

## Documentary-only today

- model_tier_per_step (computed, never injected)
- Codex per-agent model tier; Codex hooks schema ([A1]); Codex T3 overall
- Memory **post-flight** (commit/ingest after work) — cortex prose only; only pre-flight
  recall is mechanized
- Copilot per-prompt routing (impossible upstream)
- TRANCE model-tier upgrade

## Defects noted

1. `harness status` reads `.harness.settings_json_patched` / `.codex_hooks_json_patched`
   which installer never writes → always `false` (harness_status.sh:57-58). Misleading.
2. `cli/src/harness.sh` (old Junction manager) is dead code — dispatcher never routes to it.
3. `telemetry.sh:8-13` header claims rollup/report are stubs though report bats suites
   exist — verify maturity before relying on it for gate economics.

## Bats coverage

harness 85, run 27, model_resolve 26, doctor_deep 24, memory 16, verify_envelope 15,
telemetry_capture 14, canary 14, model_wiring 11, trace 10, esl_forcing 6 — every
P0–P3 surface covered except the missing per-host canary.

## Companion finding — the lost v2 Go plan (orchestrator-verified)

Crystalium (project store) holds a 2026-06-24 TRANCE plan checkpoint
(`plan: eidolons-v2-go-migration`, chain ATLAS→FORGE(G2 N=3)→SPECTRA(G3)→IDG(G5),
complexity 10/12, 16 acceptance criteria, phases P0–P6 all pending) whose status field
says "artifacts at .spectra/plans/eidolons-v2/" — **that directory has zero git history
on any branch; the artifacts were never committed and are lost.** Only the crystalium
digest (idg, 2026-06-24: "strangler-fig data-engine → eidolons-core Go binary; shell keeps
bootstrap+dispatcher+effectful runners; v2.0 product-major, consumer contract unchanged")
survives. Two lessons: (1) plan artifacts must be committed, not working-tree-only;
(2) crystalium recall could NOT surface these crystals for queries containing "eidolons"
or "Go migration" — summaries are terse (`plan_checkpoint:08234787`), embedding_ref is
null for all 9 crystals, so hybrid recall degrades to BM25 over near-empty summaries and
returns nothing. Recall quality is a v2.0 workstream, not just wiring.
