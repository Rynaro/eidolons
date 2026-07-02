# v2.0 Audit — Evals, Canaries, Model Management (2026-07-02)

> Fan-out audit agent report, verified against the working tree at nexus v1.46.1.
> Bottom line: **the current evals CANNOT prove the v2.0 thesis ("the system makes
> weaker models perform better").** One with/without instrument exists (compliance A/B),
> it measures routing compliance not task quality, ran at a single model, and its one
> live result failed its own gate (66.7% < 80%) — explicitly labelled a lower bound.

## (a) Eval suite inventory

| Suite | File | Cases | Judge | Proves | Does NOT prove |
|---|---|---|---|---|---|
| Routing | `evals/routing-suite.yaml` | 19 (15 public + 4 holdout) | Mechanical, deterministic kernel (`eval.sh:145-158`) | Kernel picks right Eidolon/tier vs ground truth | Anything about model quality ("cost=0 tokens (no model)") |
| Quality | `evals/quality-suite.yaml` | 6 (one per Eidolon) | Mechanical grep rubric, no LLM judge | Output *structurally conforms* to contract | Task-solving quality; model-blind |
| Compliance | `evals/compliance-suite.yaml` | 14 (12 routed + 2 controls) | Mechanical stream-parse for Task/Agent dispatch | A/B: harness injection vs prose-cortex delegation delta | Task quality; SessionStart-only floor |
| SWE smoke | `evals/swe-suite.yaml` | 2 | Mechanical test command | Harness orchestration works (gold_fix) | Capability ("HARNESS SELF-TEST") |
| Kupo KEEP | `evals/kupo-keep-suite.yaml` | 12 | Mechanical external verifier | With `--fix-hook`: resolved-rate | Smoke mode proves orchestration only |

Execution: `eval.sh` dispatches to `eval_quality.sh` / `eval_swe.sh` / `eval_compliance.sh`.
Only compliance has `--model` (default sonnet); only SWE/Kupo have `--fix-hook`.
**No harness computes a cross-model delta.** Results are ephemeral (stdout/`--json`,
mktemp workdirs rm -rf'd) — **no results store, no baselines, no regression history.**
Only persisted results: hand-authored snapshots in `.spectra/research/`.

## (b) What CANNOT be measured today

1. **v2.0 thesis unmeasurable.** No harness runs the same task-solving suite across two
   models and reports a delta. Compliance A/B: delegation only; single model; live run
   FAILED gate (ARM A correct_target_rate 66.7% < 80%, `compliance-eval-2026-06-12.md:9-16`);
   headless `claude -p` fires only SessionStart, not UserPromptSubmit — a floor from a
   crippled driver (`compliance-eval-2026-06-12.md:29-31`).
2. **No cross-model/tier comparison.** `model-profiles.yaml` defines light/standard/deep →
   haiku/sonnet/opus but no eval sweeps them. Cannot answer "haiku+system ≥ sonnet-bare".
3. **No bare-model control arm** in SWE/Kupo; no before/after system-level number.
4. **Quality eval is model-blind** — no record of producing model/host.
5. **Tiny synthetic N**: compliance 14 (k=2), Kupo 12 (k=3), SWE 2, Quality 6.
6. **`routing.yaml:62-63` cites a "weak-host adversarial suite"** (Vivi fanout pass^2 1.00
   vs APIVR-Δ 0.67) **whose artifacts are not in the repo** — assertion, not reproducible.
7. **CI never runs live evals** — only `--smoke`/fake-driver bats self-tests.

## (c) Model management — exists / enforced / advisory

Exists: vendor-neutral tier ladder (light<standard<deep); concrete models only in
`roster/model-profiles.yaml` (anthropic: haiku/sonnet/opus; openai: gpt-5-mini/gpt-5/gpt-5);
resolution precedence PIN → calibration → profile → roster `suggested_tier` → class default
(`lib_model_resolve.sh:26-33,159-172`); per-Eidolon tiers in `routing.yaml` (idg=light,
kupo=light, atlas/vivi/apivr=standard, spectra/forge/vigil=deep); `eidolons model` CLI;
pricing for opus+sonnet only.

Enforced (drift gates, not runtime): Doctor D9 (managed `model:` == lock effective_model,
fatal in --deep); Doctor D10 (conservative fallback coder present when a coder
`requires_host_tier`). One runtime effect: `run.sh:211-219` host-tier fallthrough changes
*routing* (winner → next coder), never the model.

Advisory: model wiring writes `model:` frontmatter at sync; host may ignore.
`run.sh` emits `model_tier`/`model_tier_per_step` in the routing artifact — informational.
"Weaker model OK" is encoded as config (`suggested_tier: light`, aci.yaml fanout
"intended_for: weak hosts", apivr `loop_native:false` benchmark-gated) — not measured.
Not shipped from the model-mgmt spec: EIIS contract change, opencode support,
google profile, `apivr_deep_promotion` (benchmark-gated data flip).

## (d) Already-internalized research claims (`research/`)

- Narrow tool surface > wide; read/write split; progressive disclosure (~900-token entry);
  handoff artifacts > messages; bounded loops (CorrectBench/Reflexion → 3-attempt caps).
- Anti-patterns avoided: generalist prompts, hidden cross-session state, tool explosion,
  prompt-level invariants, implicit handoffs.
- `production-patterns.md:135-137` self-flags the gap: quantitative comparisons vs nearest
  production analog = future work.
- Established results: compliance harness's demonstrable win is **consistency**
  (stability pass² 58.3% vs 16.7%, 3.5×; forge routing 100% vs 0%; no over-delegation on
  controls). Kupo KEEP: haiku 12×k=3 = 36/36 pass^3=1.000 → shipped v1.0.0 (additive/cost
  proof, not general-coder claim).

## (e) CI cadence

| Workflow | Cadence | Jobs |
|---|---|---|
| ci.yml | push/PR | lint, install-e2e (ubuntu+macos × yq), bats cli-tests, upgrade-self-roundtrip |
| roster-health.yml | nightly 03:00 UTC + roster/cli pushes | roster validate, MCP catalogue, EIIS conformance matrix |
| composition-drift.yml | composition.md pushes | drift vs pinned ECL |
| others | on demand | release/intake/art-lint |

**No workflow runs `eidolons eval` or `eidolons canary` live.** Eval code is exercised
only via bats smoke (eval_compliance.bats hard-forbids billed runs). The Kupo 36-agent
run has no committed workflow — manual one-off, results only in hand-authored markdown.

## Verdict

To support v2.0 you need: (1) a task-solving suite with a **(model × system-on/off)**
matrix; (2) a persisted baseline/scorecard store; (3) a real weak-model `--fix-hook` arm
vs bare-weak-model control. None exists yet. Model management is well-built but advisory.

## Companion session finding (orchestrator-verified)

`mcp__crystalium__crystalium_recall` against the project store (`~/.crystalium/eidolons`,
exists since 2026-06-24, 114KB index, runs/ populated) returns **zero records for every
query including bare "eidolons"** (scope `{project: eidolons}` and `{}`). Memory is wired
(`.mcp.json`, cortex mandates pre-flight) but the store is empty-or-unrecallable even in
the flagship project — the "memory preflight not fully mechanical" hypothesis is confirmed
from the consumption side too.
