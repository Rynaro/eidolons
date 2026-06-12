# Routing-compliance measurement — first live result (2026-06-12)

**Instrument:** `eidolons eval compliance` (PR #351), headline run `--arm both --k 2 --model sonnet`.
**Host:** Claude Code 2.1.175 headless (`claude -p`), 56 billed sessions (+3 de-risking captures).
**Scorecard:** `/tmp/headline-scorecard.json` (raw); summary below.

## Headline

| Metric | ARM A (harness wired) | ARM B (cortex pointer only) | Δ (A−B) |
|---|---|---|---|
| **correct_target_rate** (gate metric) | **66.7%** | 58.3% | **+8.3 pp** |
| delegation_rate | 66.7% | 66.7% | 0 |
| **stability (pass²)** | **58.3%** | 16.7% | **+41.7 pp** |
| control_pass_rate (no false dispatch) | 100% | 100% | 0 |

**GATE: FAIL** — ARM A 66.7% < 80%. Per the FORGE reversal condition (`DOSSIER-HARNESS-2026-06.md:106`) this nominally recommends escalating the default from inject to block — **but read the caveats below before acting; this is a lower bound, not the verdict.**

## What the harness demonstrably does

1. **Consistency is the signature win — pass² 58.3% vs 16.7% (3.5×).** Where both arms can route a class, ARM A routes it correctly on *both* k-runs far more often (scout 2/2 vs 1/2, scriber 2/2 vs 1/2, planner 2/2 vs 1/2, coder 2/2 vs 1/2). The injection makes routing markedly more *deterministic*, even where the mean is similar.
2. **Reasoner routing is the clean per-class win — forge 100% (2/2) vs 0% (0/2).** "Which approach, optimistic or pessimistic locking?" → ARM A reliably dispatched to FORGE; ARM B never did. This is the largest, cleanest single-class effect.
3. **No over-delegation.** Controls ("do the thing", "can you help") correctly drew zero dispatch in both arms (1.0). The harness does not cause spurious delegation.

## Where both arms fail (the ceiling on the mean lift)

- **Easy classes are already saturated without the harness:** scout (atlas) and scriber (idg) are 100% in *both* arms — the CLAUDE.md cortex pointer alone gets them. So the harness can't lift them; its gain is confined to the harder/ambiguous classes.
- **Three classes fail in both arms:** debugger (vigil — "stack trace, still failing after retry"), executor ("fix the typo in the config key"), and the planner→coder chain ("design and implement pagination"). The host did this work itself (`observed=[]`) rather than dispatching. These are tasks the model feels competent to just do.

## Caveats — why 66.7% is a floor, not the harness's true ceiling

1. **Headless mode under-exercises the harness.** `claude -p` fires only `SessionStart` hooks, **not** `UserPromptSubmit` (verified in the capture: the `-p` prompt is a launch arg, not an interactive submission). So this measures only the always-loaded SessionStart cortex-digest effect — **not** the per-prompt "Route: vivi — delegate" injection, which is the primary T3 mechanism and fires on every prompt in *interactive* Claude Code. The hard classes (debugger/executor/coder/chain) are exactly the ones a per-prompt nudge would most help. **The interactive number is expected to be materially higher.**
2. **Stub agents.** The fixture's Eidolon agents are stubs ("acknowledge and stop"); a real install ships full-methodology agents that may be more attractive dispatch targets for the borderline classes.
3. **2/56 sessions timed out** (the "spec out the caching layer" planner prompt) and were scored as non-dispatch — a small downward bias on the planner class.

## Recommendation

**Do not act on the gate's "escalate to block" on this number.** It is the SessionStart-only lower bound and it already shows a positive, consistency-dominated harness effect. Before any inject→block default flip, run the **interactive / per-prompt** measurement (build a driver that fires `UserPromptSubmit`, per the live-capture finding) — that measures the mechanism the dossier's 80% gate was actually written about. If the interactive number also lands below 80% on the hard classes, *then* the reversal discussion is warranted, likely scoped to specific classes (debugger/executor) rather than a blanket default flip.

## Instrument corrections forced by this run (committed alongside)

- **Fixture code surface.** The fixture was config-only; coding prompts were unanswerable ("there is no worker file") so the host never delegated. Added a deterministic `src/` service (router/worker/auth/pagination + config/deploy) so every codebase prompt is actionable. Caught by the live capture; the fake-driver smoke hid it.
- **Parser tool name.** Claude Code 2.1.175 names the dispatch tool **`Agent`**, not `Task` (the spec/research name). The parser matched only `Task` and missed every real dispatch. Now matches both. Caught only because a real stream showed `Agent(subagent_type=Explore)`.
- Both lessons are the [[feedback-capture-live-before-parsing]] class: smoke/fake fixtures pass vacuously; only a real stream reveals the host's actual shape.
