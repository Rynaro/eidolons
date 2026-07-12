<p align="center"><img src="assets/eidolons.png" alt="Eidolons — a personal, portable team of AI agents" width="220"></p>

<h1 align="center">Eidolons</h1>

<p align="center"><em>A personal, portable team of AI agents. Named specialists that work alone when the task is sharp, in harmony when it's big — and travel with you from project to project, host to host.</em></p>

<!--
  Version badges below are DYNAMIC (shields.io github/v/release) — they track each
  repo's latest GitHub release automatically. Don't hardcode version numbers here;
  they update themselves when a repo cuts a release.
-->
<p align="center">
<a href="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml/badge.svg" alt="Roster Health"></a>
<a href="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0"></a>
<img src="https://img.shields.io/github/v/release/Rynaro/eidolons?sort=semver&label=nexus&color=blue" alt="nexus release">
<img src="https://img.shields.io/github/v/release/Rynaro/eidolons-eiis?sort=semver&label=EIIS&color=blue" alt="EIIS release">
<img src="https://img.shields.io/badge/integrity-strict-success" alt="Integrity: strict">
</p>

<p align="center">
<a href="#try-it-in-60-seconds">Try it</a> ·
<a href="#meet-the-team">Meet the team</a> ·
<a href="#see-it-route">See it route</a> ·
<a href="#does-it-actually-work">Proof</a> ·
<a href="#install">Install</a> ·
<a href="#when-eidolons-is-the-wrong-tool">When not to use it</a>
</p>

---

Most AI coding tools hand you one generalist: a single assistant that scouts, plans, builds, debugs, and documents — all at once, in one context window. It works, until the task gets big. Then the plan bleeds into the code, the code bleeds into the docs, and the assistant forgets why any of it happened.

Eidolons is a different shape. It's a **team**: nine named specialists across seven roles — scout, planner, coder, scriber, reasoner, debugger, executor — over a shared memory, each with sharp boundaries, installed into any project by one CLI.

And you don't have to remember to summon the right one. **The routing is mechanical, not hopeful.** On every prompt, a deterministic kernel — no LLM, no mood — reads what you asked and dispatches the right specialist, at the right model tier, into Claude Code, Codex, GitHub Copilot, Cursor, or OpenCode. That claim is measured, not asserted; the numbers (and their honest caveats) are [below](#does-it-actually-work).

*(And yes — they're named after Final Fantasy summons. You call; they arrive already knowing the job.)*

## Try it in 60 seconds

Evaluation, not commitment — this drops a read-only ATLAS into a throwaway folder:

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
cd /tmp && mkdir eidolons-demo && cd eidolons-demo
eidolons init --preset minimal --non-interactive
```

Explore, then `rm -rf /tmp/eidolons-demo` and walk away. Full flow in [Install](#install).

## Meet the team

| Eidolon | Class | In one line | Latest |
|---|---|---|:---:|
| **[ATLAS](https://github.com/Rynaro/ATLAS)** | scout | Maps unfamiliar codebases, evidence-anchored, read-only by construction. | ![](https://img.shields.io/github/v/release/Rynaro/ATLAS?sort=semver&label=&color=blue) |
| **[RAMZA](https://github.com/Rynaro/Ramza)** | planner · default | Decision-ready specs whose gates are enforced by code — rubric arithmetic, criteria freeze, plan-vs-diff drift, maker≠checker. | ![](https://img.shields.io/github/v/release/Rynaro/Ramza?sort=semver&label=&color=blue) |
| **[SPECTRA](https://github.com/Rynaro/SPECTRA)** | planner · fallback | RAMZA's prose-methodology predecessor; conservative, opt-in (`eidolons add spectra`). | ![](https://img.shields.io/github/v/release/Rynaro/SPECTRA?sort=semver&label=&color=blue) |
| **[Vivi](https://github.com/Rynaro/Vivi)** | coder · default | Loop-native builder — drives a closed edit-run-test loop and ships only what survives `pass^k`. | ![](https://img.shields.io/github/v/release/Rynaro/Vivi?sort=semver&label=&color=blue) |
| **[APIVR-Δ](https://github.com/Rynaro/APIVR-Delta)** | coder · fallback | Vivi's non-loop predecessor for loop-incompetent hosts; opt-in (`eidolons add apivr`). | ![](https://img.shields.io/github/v/release/Rynaro/APIVR-Delta?sort=semver&label=&color=blue) |
| **[IDG](https://github.com/Rynaro/IDG)** | scriber | Provenance-first documentation, with `[GAP]`/`[DISPUTED]` markers instead of confident guesses. | ![](https://img.shields.io/github/v/release/Rynaro/IDG?sort=semver&label=&color=blue) |
| **[FORGE](https://github.com/Rynaro/FORGE)** | reasoner | Deliberates ambiguous trade-offs; returns a verdict with named alternatives and a confidence tier. | ![](https://img.shields.io/github/v/release/Rynaro/FORGE?sort=semver&label=&color=blue) |
| **[VIGIL](https://github.com/Rynaro/VIGIL)** | debugger | Forensic root cause for failures that resist repair — reproduction-gated, counterfactual-verified. | ![](https://img.shields.io/github/v/release/Rynaro/VIGIL?sort=semver&label=&color=blue) |
| **[Kupo](https://github.com/Rynaro/Kupo)** | executor | Micro-task delegate — proves patches in an ephemeral sandbox and *proposes* them; never writes your tree. | ![](https://img.shields.io/github/v/release/Rynaro/Kupo?sort=semver&label=&color=blue) |
| **Gilgamesh** | generalist | Specialist-preferring fallthrough worker — dispatched only when no specialist matches and a mechanical predicate confirms the ask is bounded and actionable; sandbox-first, PROPOSE-only. | `1.0.0` · shipped |
| **[CRYSTALIUM](https://github.com/Rynaro/crystalium)** | memory | The shared four-layer memory substrate every member writes to and recalls from. | ![](https://img.shields.io/github/v/release/Rynaro/crystalium?sort=semver&label=&color=blue) |

Each Eidolon is its own repo, independently versioned and installable; the roster's machine-readable source of truth is [`roster/index.yaml`](roster/index.yaml). Partial teams are first-class — bring only ATLAS to an audit, or the whole pipeline to a greenfield.

## See it route

The routing kernel is a real program, not a prompt. Ask it something and it answers in JSON — which specialists, in what order, at what model tier:

```console
$ eidolons run "plan and build a rate limiter for the public API" --json
{
  "decision": "chain",
  "selected": ["ramza", "vivi"],
  "chain": [
    { "eidolon": "ramza", "role": "planner", "template": "ship-fast" },
    { "eidolon": "vivi",  "role": "coder",   "template": "ship-fast" }
  ],
  "model_tier_per_step": ["deep", "standard"],
  "degraded_mode_per_step": [null, "fanout"],
  "confidence": 0.8,
  "tier": "standard"
}
```

<sup>Output lightly trimmed. The kernel is deterministic — run the same prompt and you get byte-identical routing, with zero tokens billed.</sup>

With the [harness](#mechanical-routing--the-harness) installed, this happens on its own: a host hook fires on every prompt, the kernel computes the route, and the decision — plus recalled project memory — is injected into context before the model starts thinking. A debugging prompt lands on VIGIL at deep tier; a rename lands on Kupo; a vague one gets a clarification request instead of a wrong guess.

## How the team composes

```
ATLAS ───▶  RAMZA  ───▶  Vivi  ───▶ IDG
  scout      plan         build       chronicle
             ▲             │ ▲
           FORGE ◀── (ambiguity, trade-offs, novel problems)
                           │ │
                         VIGIL ◀── (failure resisted repair; forensic attribution)
                           │
                         Kupo ◀── (localized verifier-backed micro-tasks, PROPOSE-only)

  ╞════════════════ CRYSTALIUM ════════════════╡
   shared memory — every member commits handoff
   artifacts and recalls them (bidirectional)
```

Handoffs are structured artifacts on disk, not vibes in a context window. Every one carries an [ECL 2.1](https://github.com/Rynaro/eidolons-ecl) envelope with a SHA-256 integrity tag and a typed **trust grade**: `validated` can only be emitted behind a real external verifier — everything self-reviewed says so, and downstream members read the difference from a field, not from prose. And since v2.0, **maker ≠ checker holds across every shipped member**: the implementer of a change never verifies it; a distinct checker does, in a fresh context. Contract tables and the partial-team matrix live in [`methodology/composition.md`](methodology/composition.md).

## Does it actually work?

Start with the part you can verify without trusting us — or paying anyone. The routing decision is deterministic, so it ships as a benchmark that runs cold, with **no API key and ~0 tokens**:

```bash
eidolons eval routing --suite public   # 15 labelled tasks across 12 routing categories
```

It grades the kernel against committed ground truth ([`evals/routing-suite.yaml`](evals/routing-suite.yaml)); because nothing is random, you get the exact result we do. That's the floor. Above it sit four billed, model-dependent measurements — each with its data committed in-repo:

| Question | Headline result | The catch |
|---|---|---|
| Does wiring the team in change what the host does? | Bare host: **0%** delegation, ever. Wired: **41.7%** correct-specialist, zero false dispatch. | That's a floor (timed-out sessions score as failures) — and it fails our own 80% gate, the committed evidence the advisory→blocking escalation gets argued from. |
| Does the specialist shape beat one generalist pass? | Vivi's fanout: **pass² 1.00 vs 0.67** on adversarial-hard fixes; Kupo: **36/36 runs** (12 tasks · k=3), **pass³ 1.00** on its additive-proof. | Small suites; zero reward-hacks observed across 63 holdout-gated runs. |
| Do cheaper models win inside the system? | **haiku + system 12/12 = sonnet + bare 12/12** (pass³ 1.00) — a tie at ~⅓ the per-token price. | Both arms saturated the cohort: that demonstrates non-inferiority, not superiority. |
| Does mechanizing the planner's gates cost quality? | RAMZA **6/6 = SPECTRA 6/6** (pre-registered A/B, 0 MUST fails in 24 runs) at **~51% of the words**. | Saturated again — the tie is the claim, "wins more" isn't. |

These are early, small-N signals, and the committed scorecards say so in the data — that's deliberate. Full methodology, per-question tables, and the instrument bugs we caught before accepting any number:

<details>
<summary><strong>1 · Routing compliance — mechanical injection vs prose</strong> (Claude Code · sonnet · k=2 · 56 sessions)</summary>

`eidolons eval compliance` runs one prompt suite through a headless host twice — once with the harness wired, once with only the prose cortex — and scores how it routes. July 2026 measurement, with the per-prompt injection **certified live in-stream** (`--driver claude-headless-ups` records hook events; a $0 dead-endpoint probe independently confirmed the injection fires):

| Routing | Prose only | With Eidolons |
|---|:---:|:---:|
| Ever delegates to a specialist | **0%** | **41.7%** |
| Delegates to the *correct* specialist | 0% | **41.7%** |
| False delegation on control prompts | 0% | 0% |

The bare arm **never delegated once** across 24 routed sessions — whatever routing a prose file suggests, the model ignores it until you name an Eidolon by hand. The entire effect is the mechanical injection. Scorecard: [`evals/results/`](evals/results/); the superseded June SessionStart-only measurement is kept at [`.spectra/research/compliance-eval-2026-06-12.md`](.spectra/research/compliance-eval-2026-06-12.md).

</details>

<details>
<summary><strong>2 · Specialist shape vs one generalist pass</strong> (budget-matched · k=2)</summary>

On an adversarial-hard coding suite measured in [Vivi's own repo](https://github.com/Rynaro/Vivi), Vivi's parallel-candidate shape landed every fix where a single pass landed two-thirds:

| Hard-task fix quality (pass², resolved on both runs) | Single pass | Vivi (fanout) |
|---|:---:|:---:|
| Adversarial-hard suite | 0.67 | **1.00** |

Kupo, the executor the team delegates micro-tasks to, earned its roster seat on a behavioral additive-proof — 12 tasks at k=3, 36/36 runs resolved, pass³ 1.00.

</details>

<details>
<summary><strong>3 · H-WIN — a light model inside the system vs a stronger model bare</strong> (12 fix-the-bug tasks · k=3 · sandboxed, verifier-gated)</summary>

v2.0's headline bet: **push the difficulty into the system so cheaper models win more often**. The comparison is pinned as data in [`evals/arms/h-win.json`](evals/arms/h-win.json) and deliberately cross-tier:

| Arm | resolved | pass³ |
|---|:---:|:---:|
| **haiku** + system discipline (`keep-system.sh`) | 12/12 | **1.00** |
| **sonnet** + bare prompt (`keep-bare.sh`, control) | 12/12 | **1.00** |

An exact tie at roughly ⅓ the per-token price for the system arm — the tier drop was free on this cohort. Every scorecard, the pairwise flip table, and the full disclosure — including the **four instrument bugs caught adversarially before accepting any number** (a fake-green verifier path among them) — are committed in [`evals/results/`](evals/results/). `eidolons eval baseline` tracks regressions from here (exit 5 on any).

</details>

<details>
<summary><strong>4 · RAMZA vs SPECTRA — the pre-registered planner A/B</strong> (6 tasks incl. 2 holdout · k=2 · mechanical grading)</summary>

The flip that made RAMZA the default planner was gated on an A/B whose protocol and holdout were frozen at a commit *before* any run — same Sonnet executor on both arms, blind to the rubrics. Data: [`.spectra/research/ramza-stage2/ramza-planner-ab.json`](.spectra/research/ramza-stage2/ramza-planner-ab.json):

| Planner A/B (pass²) | tasks pass² | mean words / spec |
|---|:---:|:---:|
| **RAMZA** (mechanized gates) | **6/6** | **5,059** |
| SPECTRA (prose methodology, control) | 6/6 | 9,897 |

Every RAMZA spec ships a machine-verifiable gate audit trail where SPECTRA self-reports its cycle. One holdout run's own maker≠checker critic caught and closed a real criteria-desync live, before the plan was called done — the methodology catching its flagship failure class in the act. Adjudication: [`AC-003-ADJUDICATION.md`](.spectra/research/ramza-stage2/AC-003-ADJUDICATION.md).

</details>

## Mechanical routing — the harness

A descriptor table in a prose file can only *suggest* delegation; the host decides whether to listen, and measurably it doesn't (question 1 above). The harness closes that gap — a decision backed by a research synthesis of **112 adversarially-verified capability rows across 18 agents** ([`DOSSIER-HARNESS-2026-06.md`](DOSSIER-HARNESS-2026-06.md)):

- **A deterministic routing kernel.** `eidolons run "<prompt>" --json` classifies against [`roster/routing.yaml`](roster/routing.yaml) — no LLM, fully reproducible — and emits who handles it, at what tier, in what chain.
- **Per-host hook adapters.** `eidolons harness install` wires the kernel into each host's own lifecycle hooks; the route and a memory digest arrive in context on their own, every prompt — including per-step model tiers (`model tiers: atlas=standard → ramza=deep → …`) so cheap models land on cheap steps.
- **Graceful degradation.** Advisory-mechanical by default; where a host's hooks are absent or buggy, it silently falls back to documentary routing — never worse than prose.

```bash
eidolons harness install            # wire routing + memory injection into detected hosts
eidolons harness install --strict   # opt-in: block main-loop edits; only delegated subagents write
eidolons harness status             # per-host effective enforcement tier
```

<details>
<summary>Operational details — memory preflight, canaries, per-host soundness</summary>

With CRYSTALIUM installed, the session-start hook also runs `eidolons memory preflight` — a one-shot, fail-open recall that injects prior project memory, including `[skill/…]`-tagged verified procedures a weak orchestrator can invoke instead of re-deriving; `--explain` diagnoses a silent-empty store. `eidolons canary --all-hosts` verifies each host's effective tier against the lockfile, and `--strict`'s delegate-or-deny soundness is graded per host in [`DOSSIER-HARNESS-2026-06.md`](DOSSIER-HARNESS-2026-06.md) and [`docs/architecture.md`](docs/architecture.md) § "Harness Layer".

With atlas-aci wired, the harness also keeps its code-graph fresh on its own: every SessionStart and UserPromptSubmit fires a detached, deduplicated, incremental `atlas-aci index --since` reindex against the exact image digest pinned in `.mcp.json`, using `--pull=never` so it can never block a turn on an image pull (it relies on the image already being local, since `serve` runs from that same digest) — so mid-session edits are visible to `callers_of` / `search_symbol` within about one turn — **on by default**, at the cost of one cheap detached container spin per turn (deduped to at most one in flight per project); disable it with `harness.atlas_sync.enabled: false` in `eidolons.yaml`. It mounts the hook's cwd, which every wired host (Claude Code, Codex, Copilot) sets to the project root; in an unusual nested-workspace where a *different* project root happens to be cwd and is *also* atlas-aci-wired, it reindexes that one instead — a documented bound, not a bug.

</details>

## The lifecycle and the context economy

Routing decides *who* works. Two younger contracts govern *how the work moves* and *how the session spends its attention* — both opt-in, both mechanical rather than discretionary.

**ESL — the spec lifecycle.** Non-trivial changes run through a right-sized, auditable lifecycle instead of a one-shot prompt: a mechanical gate classifies every change by observable signals (`trivial` → Kupo direct, no ceremony · `lite` → one-page spec · `full` → the whole cycle), maker≠checker is enforced on the hand-off envelope, and a drift-check re-derives the change against its living spec before archive. Advisory by default, it escalates to a blocking `MUST` once a project crosses mechanical size thresholds, recorded auditably in the lock. The specialists you already have *are* the lifecycle — RAMZA specifies, Vivi implements, VIGIL owns the failure path, IDG archives. The official runtime is **[tonberry](https://github.com/Rynaro/tonberry)**, a ~13 MB distroless Go MCP whose `verify` is byte-identical to a zero-dependency bash 3.2 checker, so the rich runtime and the minimal reference can never drift.

**ECM — the context economy** *(new in the v2.2–v2.3 line)*. Long sessions die of context exhaustion, usually at the worst moment. ECM gives the session a deterministic meter and a zone ladder (amber 0.50 / red 0.75 / critical 0.90) with a table-driven policy — first-match rules, never model discretion — that fires context operations autonomously: externalize to memory, prune, compact, or hand off to a fresh session with a structured brief that travels as an ECL envelope. A pin set survives every lossy operation, externalize-before-compact rides CRYSTALIUM, and everything fails open. Kernel verbs: `eidolons context status|policy|externalize|handoff`; deep table: [`methodology/cortex/context-protocol.md`](methodology/cortex/context-protocol.md).

### The statusline — ECM's rung-1 telemetry feed

Claude Code can display a real-time HUD while you work. The statusline is a two-row Final-Fantasy-themed battle window — cosmetic on the surface, but its *actual job* is load-bearing: it pipes exact context-window telemetry from the host into `eidolons context status --stdin`, promoting ECM from blind-estimation (`estimate_source: unknown`) to precise host telemetry (`estimate_source: host`). Without it, ECM runs on a heuristic and every policy rule fails open. With it, the meter sees the truth.

The cosmetics are a wink; the mapping is real. Every FF term is checkable:

```
╭─⟪ Fable 5 · Sage ✦ ⟫─ eidolons · main ────────────────── $0.31 · +42/-3 ─╮
╰─ ◈ ▰▰▱▱▱▱▱▱▱▱ 18% ↑2 GREEN · kupo · ▸ ecm-statusline ─ MP ▰▰▰▰▰ 92% ─╯
```

| Area | FF term | What it measures |
|------|---------|------------------|
| **Job & Class** | Fable 5 · Sage | `model.display_name` and the model tier mapped to FF jobs (Haiku→Ninja, Sonnet→Bard, Opus→Summoner, Fable→Sage). |
| **Project** | eidolons | The project name (basename of cwd), shown in bold. |
| **Branch & Dirty** | main | Git branch name; `*N` appends the count of dirty files. |
| **Gil** | $0.31 | Session spend so far (`cost.total_cost_usd`), rendered in gold. |
| **EXP** | +42/-3 | Lines added/removed (`cost.total_lines_added`, `total_lines_removed`) — yellow diff stats. |
| **Limit Gauge** | ◈ ▰▰▱▱▱▱▱▱▱▱ 18% | HP = context-window utilization (`context_window.used_percentage`), coloured by ECM zone: green <50%, amber <75%, red <90%, critical ≥90%. Decays left-to-right as the session runs. |
| **Delta** | ↑2 | Damage number: the % change since the last render. Pops in amber on increase, green on decrease; self-decays. |
| **Zone** | GREEN / AMBER / RED / CRITICAL | The ECM zone label, coloured and flashed (reverse video) when it changes — these are not decorative, they are the thresholds (0.50 / 0.75 / 0.90) that fire real context operations. At critical, the label pulses by second-parity if you've set `"refreshInterval": 2`. |
| **Party/Agent** | kupo | Either the dispatched Eidolon name (when one holds the row) in its class colour, or the party size (e.g. `party 8`) when idle. A live agent outranks the roster count. |
| **Quest** | ▸ ecm-statusline | The active ESL change ID (first in-progress, else proposed), with a one-render `✓ COMPLETE!` fanfare when it verifies. |
| **MP** | ▰▰▰▰▰ 92% | The 5-hour rate-limit budget (`rate_limits.five_hour.used_percentage`), shown as remaining; drains as you cast. Colours: cyan → amber (>50% used) → red (>75% used). |

Wire it in `.claude/settings.json`:

```json
{ "statusLine": { "type": "command",
                  "command": "eidolons statusline render",
                  "padding": 0,
                  "refreshInterval": 2 } }
```

`eidolons harness install` wires this for you when ECM is on — and **it will not clobber a `statusLine` you already have**: a foreign one is left byte-unchanged and recorded as unmanaged, so `eidolons remove` never touches it either. Your prompt is yours. `refreshInterval: 2` is optional — with it, the critical pulse animates while the session idles; without it, the pulse blinks per message. To verify the wiring and check the meter, run `eidolons statusline doctor`.

Four sibling contracts, one seam each — every Eidolon satisfies the first, and the rest are opt-in:

| Contract | Governs | Spec |
|---|---|---|
| **EIIS** | how a member installs | [`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis) |
| **ECL** | how members talk — envelopes, integrity tags, trust grades | [`Rynaro/eidolons-ecl`](https://github.com/Rynaro/eidolons-ecl) |
| **ESL** | how a change moves — right-sized lifecycle, maker≠checker | [`Rynaro/eidolons-esl`](https://github.com/Rynaro/eidolons-esl) |
| **ECM** | how a session spends context — meter, zones, handoff briefs | [`Rynaro/eidolons-ecm`](https://github.com/Rynaro/eidolons-ecm) |

The MCP servers behind them — CRYSTALIUM memory, the tonberry ESL runtime, the atomos ECM executor, and friends — are one catalogue away:

```bash
eidolons mcp list               # the full catalogue (5 servers)
eidolons mcp install tonberry   # ESL lifecycle runtime
eidolons mcp install atomos     # ECM compose/verify executor
```

## Install

One-time, global:

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
```

This installs the `eidolons` CLI to `~/.local/bin/eidolons` and caches the nexus at `~/.eidolons/nexus`.

Per project — empty folders or running codebases:

```bash
cd <any-project>
eidolons init                # interactive — choose members and preset (offers CRYSTALIUM memory)
eidolons harness install     # wire mechanical routing + memory injection into your hosts
eidolons sync                # reconcile installed members to eidolons.yaml
eidolons verify              # re-check installed Eidolons against the roster's signed metadata
```

Keep the nexus current with `eidolons upgrade self` (atomic, integrity-verified, with `--check` and `--rollback`). Commit `eidolons.lock` alongside `eidolons.yaml` for reproducible, tamper-evident installs. Full walkthrough: [`docs/getting-started.md`](docs/getting-started.md); end-to-end verification: [`docs/smoke-test.md`](docs/smoke-test.md); every command: [`docs/cli-reference.md`](docs/cli-reference.md).

## When Eidolons is the wrong tool

Honest scoping beats a benchmark. Skip Eidolons when:

- **You want one assistant and zero ceremony.** A bare host is genuinely good at small, single-phase tasks; the team's edge shows up when work spans phases and sessions.
- **Your workflow requires npm/pip/brew packaging.** The `curl | bash` + git flow is a deliberate design choice ([why](docs/architecture.md)) — if that's a dealbreaker, it won't stop being one.
- **Your host exposes no hook surface and you need enforcement.** Without hooks, routing degrades to documentary — honest, but only as good as the model's obedience.
- **The project is a throwaway script.** The right-sizing gate would route everything to Kupo anyway; the roster is overhead there.

## Verified releases

Every shipped Eidolon publishes attestation-backed releases through one canonical workflow ([`eidolon-release-template.yml`](.github/workflows/eidolon-release-template.yml)); each release records its commit, tree, and archive SHA-256 into [`roster/index.yaml`](roster/index.yaml). Under the default `integrity.enforcement: strict` posture, `eidolons sync` and `eidolons verify` abort if any installed member's checksum drifts from the signed metadata — the same gate `Roster Health` runs nightly. Trust model: [`docs/release-integrity.md`](docs/release-integrity.md); contract-version bumps are additive and opt-in, covered in [`MIGRATION.md`](MIGRATION.md).

## What's in this repo

| Area | What it contains |
|------|------------------|
| [`roster/`](roster/) | Machine-readable registry of every Eidolon — versions, repos, handoffs; the routing table ([`routing.yaml`](roster/routing.yaml)) and MCP catalogue ([`mcps.yaml`](roster/mcps.yaml)) |
| [`methodology/`](methodology/) | [Design principles](methodology/prime-directives.md), [composition contracts](methodology/composition.md), the routing [cortex](methodology/cortex/) |
| [`research/`](research/) | Papers, citations, production patterns — the evidence base ([index](research/INDEX.md)) |
| [`evals/`](evals/) | Suites, arms, hooks, and committed scorecards ([`results/`](evals/results/)) |
| [`cli/`](cli/) | The `eidolons` command-line tool — installs, wires, and orchestrates the team |
| [`schemas/`](schemas/) | JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries, eval suites |
| [`docs/`](docs/) | Getting started, architecture, CLI reference, MCP store, release integrity, ADRs |
| [`examples/`](examples/) | Worked examples: greenfield, brownfield, solo-member, partial-team |
| [`MANIFESTO.md`](MANIFESTO.md) | Why the project exists — the four commitments, and what we refuse to build |

<details>
<summary><strong>Why a nexus, when each Eidolon is independently installable?</strong></summary>

Each Eidolon is its own first-class repo, independently versioned — that's a hard invariant. The nexus is a coordinator, not an owner. It exists for what no single Eidolon can hold:

1. **Discovery** — without a roster, nobody knows which Eidolons exist or how they relate.
2. **Composition** — handoff contracts, pipeline conventions, the routing kernel, and partial-team patterns are shared assets.
3. **Research** — the scientific backing for the whole program lives in one place instead of drifting across repos.
4. **Wiring** — one `eidolons add atlas,ramza,vivi` beats fifty lines of clone-and-install docs, and `eidolons harness install` reaches hosts no individual Eidolon could.
5. **Supply-chain integrity** — one canonical signing workflow, one ingestion path, one consumer-side gate. Independent signing schemes would defeat the trust model.

The four-layer architecture (install standard → Eidolon repos → this nexus → consumer project) is documented in [`docs/architecture.md`](docs/architecture.md). The install contract every Eidolon satisfies is the **Eidolons Individual Install Standard** ([`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis)) — versioned independently; the CLI refuses to install non-conformant members.

</details>

## Contributing

Per-Eidolon bugs and features belong in that Eidolon's repo (an ATLAS finding → [Rynaro/ATLAS](https://github.com/Rynaro/ATLAS)). CLI bugs, roster issues, and composition-contract changes belong here. Install-standard questions belong in [Rynaro/eidolons-eiis](https://github.com/Rynaro/eidolons-eiis). Unsure which layer owns a concern? [`docs/architecture.md`](docs/architecture.md) maps the four layers and their responsibilities.

## License

Apache-2.0. See [LICENSE](LICENSE).

---

<p align="center"><em>When the question is hard and the context is big, you don't want one confused assistant. You want a team.</em><br>— <a href="MANIFESTO.md">the Manifesto</a></p>
