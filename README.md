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

---

Most AI coding tools ship a **single generalist** that plans, scouts, builds, and documents all at once — and hits a ceiling fast. Eidolons is a different shape: **eight independently-versioned specialists across seven roles**, one CLI, dropped into any project. You get sharp boundaries instead of one confused generalist — the right specialist for each phase, over a shared memory that carries context between them.

And the routing is **mechanical, not hopeful.** Most multi-agent setups are a paragraph in `CLAUDE.md` the model is free to ignore — so it does, until you name an agent yourself. Eidolons installs real per-host hooks: at session start a deterministic, non-LLM kernel computes the routing decision and injects it — plus recalled memory — into context, **on its own, every time.** The team travels across Claude Code, Codex, GitHub Copilot, Cursor, and OpenCode, and degrades gracefully to documentary routing wherever a host's hooks aren't sound.

The v2.0 line adds a deliberate design bet: **push the difficulty into the system so cheaper models win more often.** Routing carries a per-step model tier into every prompt; weak-host behavior is declared roster *data* (fanout shapes, conservative fallbacks, escalation contracts), not prose; the sandbox runs a run-cheap → verify → **escalate-on-verifier-failure** tier cascade with a default-on anti-tamper ratchet (a candidate that edits an existing test is rejected, mechanically); and every handoff envelope now carries a typed trust grade — `validated` is only emittable behind a real external verifier, and the implementer of a change is never its checker. The claim that this makes light-tier models beat bare standard-tier models is *instrumented, not yet measured* — see the eval matrix below.

## Try it in 60 seconds

Evaluation, not commitment — this drops a read-only ATLAS into a throwaway folder:

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
cd /tmp && mkdir eidolons-demo && cd eidolons-demo
eidolons init --preset minimal --non-interactive
```

Explore, then `rm -rf /tmp/eidolons-demo` and walk away. Full flow in [Install](#install).

## Does it actually work?

Two questions, both measured against a **bare host running the same model** — no hand-waving.

**1. Does wiring in the team change what the host actually does?** `eidolons eval compliance` runs one prompt suite through a headless host twice — once with the harness wired, once with only the prose cortex (≈ a bare host) — and scores how it routes.

| Routing &nbsp;<sub>(Claude Code · k=2 · 56 sessions)</sub> | Prose only | With Eidolons |
|---|:---:|:---:|
| **Stability** — picks the right specialist on *both* runs | 16.7% | **58.3%** &nbsp;<sub>(3.5×)</sub> |
| Routes *"which approach?"* → the reasoner | 0% | **100%** |
| Correct target overall | 58.3% | 66.7% |
| False delegation on control prompts | 0% | 0% |

The signature win is **consistency** — the injection makes routing far more deterministic. (These numbers are a SessionStart-only *lower bound*: the headless driver available in June didn't fire per-prompt hooks. That floor is now closable — current `claude -p` fires `UserPromptSubmit`, verified at $0 via a dead-endpoint probe, and the instrument ships a `--driver claude-headless-ups` mode that certifies `ups_fired` per run. A re-measurement with the primary mechanism ON is pending. Honest writeup: [`.spectra/research/compliance-eval-2026-06-12.md`](.spectra/research/compliance-eval-2026-06-12.md).)

**2. Does the specialist shape beat one generalist pass?** On an adversarial-hard coding suite (budget-matched, k=2) — measured in [Vivi's own repo](https://github.com/Rynaro/Vivi) — **Vivi's** parallel-candidate shape lands every fix where a single pass lands two-thirds:

| Hard-task fix quality &nbsp;<sub>(pass², resolved on both runs)</sub> | Single pass | Vivi (fanout) |
|---|:---:|:---:|
| Adversarial-hard suite | 0.67 | **1.00** |

Zero reward-hacks in 63 holdout-gated runs. And **Kupo**, the executor the team delegates micro-tasks to, earned its roster seat on a behavioral additive-proof — **36/36 tasks, pass³ 1.00**.

**Don't trust our numbers — reproduce the floor yourself.** The behavioral evals above are billed and model-dependent, but the *routing decision* underneath them is a deterministic, non-LLM kernel — so we ship it as a benchmark anyone can run cold, with **no API key, no billing, and ~0 tokens**:

```bash
eidolons eval routing --suite public      # 15 labelled tasks across 12 routing categories
```

It grades the kernel's output against Eidolons-authored ground truth ([`evals/routing-suite.yaml`](evals/routing-suite.yaml)); because the kernel is deterministic, `pass^k == pass^1` and you'll get the exact same result we do. (`--validate-suite` self-tests the suite; `--json` for machine output.) This is the reproducible floor the billed evals build on — verify it, then weigh the rest.

**3. Does the system make cheaper models win?** This is v2.0's headline question, and we ship the instrument rather than the assertion: `eidolons eval swe --matrix evals/arms/h-win.json --suite-file evals/kupo-keep-suite.yaml` runs the same task cohort through two arms — a light-tier model wrapped in the system's discipline vs a standard-tier model with a bare prompt — and writes schema'd scorecards plus a pairwise flip table to [`evals/results/`](evals/results/), with `eidolons eval baseline` as the regression tracker (exit 5 on any regression). The honest comparison is pinned as data in [`evals/arms/h-win.json`](evals/arms/h-win.json); the hook prompts are versioned artifacts. **No measured number is published here yet** — smoke scorecards are plumbing-validation only and are marked as such in the data.

These are early, small-N signals, framed honestly in the research digests and [`CHANGELOG.md`](CHANGELOG.md) — not marketing.

## Meet the team

| Eidolon | What it does | Reach for it when… | Latest |
|---|---|---|:---:|
| **[ATLAS](https://github.com/Rynaro/ATLAS)** <sub>scout</sub> | Maps an unfamiliar codebase without writing a line. Evidence-anchored, read-only by construction. | Auditing a new repo, onboarding, before any change. | ![](https://img.shields.io/github/v/release/Rynaro/ATLAS?sort=semver&label=&color=blue) |
| **[SPECTRA](https://github.com/Rynaro/SPECTRA)** <sub>planner</sub> | Turns a rough idea or scout report into a decision-ready spec — rubrics, gates, GIVEN/WHEN/THEN. | Planning a feature before you build it. | ![](https://img.shields.io/github/v/release/Rynaro/SPECTRA?sort=semver&label=&color=blue) |
| **[Vivi](https://github.com/Rynaro/Vivi)** <sub>coder · default</sub> | **The default coder.** Brownfield, pattern-first, test-anchored — drives a closed edit-run-test loop and gates on `pass^k` instead of one green run. | Shipping the change SPECTRA planned, on a loop-capable host. | ![](https://img.shields.io/github/v/release/Rynaro/Vivi?sort=semver&label=&color=blue) |
| **[APIVR-Δ](https://github.com/Rynaro/APIVR-Delta)** <sub>coder · fallback</sub> | Vivi's conservative predecessor, for hosts without the closed loop. Same discipline, non-loop posture — add with `eidolons add apivr`. | A loop-incompetent host, or a cautious builder. | ![](https://img.shields.io/github/v/release/Rynaro/APIVR-Delta?sort=semver&label=&color=blue) |
| **[IDG](https://github.com/Rynaro/IDG)** <sub>scriber</sub> | Synthesizes docs from sessions, specs, and deltas — provenance-first, with `[GAP]`/`[DISPUTED]` markers. | Chronicling what you just built. | ![](https://img.shields.io/github/v/release/Rynaro/IDG?sort=semver&label=&color=blue) |
| **[FORGE](https://github.com/Rynaro/FORGE)** <sub>reasoner</sub> | Deliberates on ambiguous trade-offs. Names alternatives, surfaces assumptions, returns a verdict + confidence. | Two patterns apply and the choice isn't obvious. | ![](https://img.shields.io/github/v/release/Rynaro/FORGE?sort=semver&label=&color=blue) |
| **[VIGIL](https://github.com/Rynaro/VIGIL)** <sub>debugger</sub> | Forensic debugger for failures that resist normal repair. Reproduction-gated, counterfactual-verified. | A flaky test, heisenbug, or unexplained regression. | ![](https://img.shields.io/github/v/release/Rynaro/VIGIL?sort=semver&label=&color=blue) |
| **[Kupo](https://github.com/Rynaro/Kupo)** <sub>executor</sub> | Low-effort delegate target. Patches an ephemeral sandbox, proves it with a real verifier, and *proposes* the patch back — never writes the real tree. | Offloading trivial localized edits to keep a session lean. | ![](https://img.shields.io/github/v/release/Rynaro/Kupo?sort=semver&label=&color=blue) |
| **[CRYSTALIUM](https://github.com/Rynaro/crystalium)** <sub>memory</sub> | The shared four-layer memory substrate every member writes to and recalls from — tier-gated writes, hybrid recall, Dream consolidation, principled forgetting. | Carrying context and learned patterns across sessions and members. | ![](https://img.shields.io/github/v/release/Rynaro/crystalium?sort=semver&label=&color=blue) |

> Eight shipped specialists across seven capability classes — **scout, planner, coder, scriber, reasoner, debugger, executor** — plus **CRYSTALIUM**, the `memory` substrate underneath them all. Versions and handoff contracts live in [`roster/index.yaml`](roster/index.yaml), the machine-readable source of truth.

## How they compose

The team has a default shape: **ATLAS** scouts, **SPECTRA** plans, **Vivi** builds, **IDG** chronicles. **FORGE** and **VIGIL** are lateral specialists — consultable at any stage. **CRYSTALIUM** sits underneath all of them, the shared memory every member writes handoffs into and recalls from. Partial teams are first-class: bring just ATLAS to an audit, or the full pipeline to a greenfield.

<details>
<summary>Canonical pipeline</summary>

```
ATLAS ───▶ SPECTRA ───▶  Vivi  ───▶ IDG
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

</details>

Handoffs are structured artifacts written to disk, not free-form messages — every one carries an [ECL 2.1](https://github.com/Rynaro/eidolons-ecl) sidecar envelope with a SHA-256 integrity tag and a typed **trust grade**: `validated` is only emittable when a real external verifier passed (Vivi's pass^k gate, Kupo's named verifier, VIGIL's counterfactual flip); everything self-reviewed says so (`self-attested`), and a downstream member can read the difference from a field instead of judging it from prose. Since v2.0, **maker ≠ checker holds across all eight members** — the implementer of a change never advances it to `verified`; a distinct checker does, in a fresh context ([ESL 1.1 C8](https://github.com/Rynaro/eidolons-esl)). See [`methodology/composition.md`](methodology/composition.md) for the contract table and partial-team matrix.

## Mechanical routing — the harness

A descriptor table in a prose file can only *suggest* delegation; the host decides whether to listen, and usually it doesn't until you name an Eidolon yourself. The decision to build a mechanical harness wasn't a hunch — it's backed by a research synthesis of **112 adversarially-verified capability rows across 18 agents** ([`DOSSIER-HARNESS-2026-06.md`](DOSSIER-HARNESS-2026-06.md)). The **harness** closes that gap with three pieces:

- **A deterministic routing kernel.** `eidolons run "<prompt>" --json` classifies a prompt against [`roster/routing.yaml`](roster/routing.yaml) — no LLM, fully reproducible — and emits which Eidolon(s) handle it, at what tier, in what chain.
- **Per-host hook adapters.** `eidolons harness install` wires that kernel into each host's own lifecycle hooks. At session start the routing artifact and a memory digest are injected as context — **the host doesn't have to remember to delegate; the routing arrives on its own.**
- **Graceful degradation.** Routing is injected by default (advisory-mechanical). Where a host's hooks are absent or buggy, it silently falls back to documentary routing — never worse than prose.

```bash
eidolons harness install            # wire routing + memory injection into detected hosts
eidolons harness install --strict   # opt-in: add tool-boundary delegate-or-deny where sound
eidolons harness status             # per-host effective enforcement tier
```

For a hard backstop, `--strict` adds a `PreToolUse` **delegate-or-deny** tier that mechanically blocks direct main-loop edits (only delegated subagents may write), with soundness graded per host. Per-prompt injection also carries the kernel's **model tiers** (`model tiers: atlas=standard → spectra=deep → …`) so the host can put cheap models on cheap steps. When CRYSTALIUM is installed, the session-start hook also runs `eidolons memory preflight` — a one-shot recall that injects prior project memory (including `[skill/…]`-tagged verified procedures a weak orchestrator can invoke instead of re-deriving), fail-open and bounded; `--explain` diagnoses a silent-empty store, and `eidolons canary --all-hosts` verifies the effective tier per host against the lockfile. The full per-host capability matrix is in [`DOSSIER-HARNESS-2026-06.md`](DOSSIER-HARNESS-2026-06.md) and [`docs/architecture.md`](docs/architecture.md) § "Harness Layer".

## Spec-Driven lifecycle — ESL

Routing decides *who* works. **ESL** — the Eidolons Spec Lifecycle — decides *how a change moves*, so non-trivial work runs through a right-sized, auditable lifecycle instead of a one-shot prompt. It isn't a second framework bolted on: the specialists you already have **are** the lifecycle — SPECTRA specifies, FORGE deliberates, Vivi implements, Kupo/VIGIL verify, IDG archives — and ESL is the thin grammar that sequences them, change by change, on disk under `.spectra/changes/`. Each Eidolon ships its own lifecycle hop; the cortex orchestrates the rest.

It's built deliberately against [the documented failure modes of spec-driven development](https://github.com/Rynaro/eidolons-esl/blob/main/docs/rationale.md) — over-specification, instruction bloat, spec-as-waterfall, "spec" as a throwaway prompt:

- **A mechanical right-sizing gate** classifies every change by observable signals — `trivial` → Kupo direct (no ceremony), `lite` → one-page spec, `full` → the whole lifecycle. You can't over-specify a one-line fix.
- **maker ≠ checker, enforced** — the implementer and the verifier are mechanically distinct identities, checked on the hand-off envelope. A change cannot self-verify.
- **Drift-check before archive** re-derives the change against its living spec, catching implementation that outran the intent.
- **Opt-in, then mechanically forced** — advisory by default (`SHOULD` open a change first); escalates to *blocking* (`MUST`) once the project crosses mechanical size thresholds (change-count / repo-LOC / full-spec ratio), recorded auditably in the lock. With tonberry installed, the harness **injects an ESL reminder at every session start and on every non-trivial routed prompt** — not left to memory. Trivial work is always exempt; install auto-assesses (skip with `EIDOLONS_SKIP_AUTO_ASSESS=1`).

The official implementation is **[tonberry](https://github.com/Rynaro/tonberry)** — a thin (~13 MB, distroless) Go MCP whose `verify` is **byte-identical** to a zero-dependency `bash 3.2` conformance checker, so the rich runtime and the minimal reference can never drift. Install it with `eidolons mcp install tonberry`; the contract it implements is **[`Rynaro/eidolons-esl`](https://github.com/Rynaro/eidolons-esl)**. ESL is opt-in — absent the MCP, the Eidolons route and build exactly as before. Once installed, the surfacing is **mechanical** — injected at session start every time, not (yet) a hard edit-time block.

## Install

One-time, global:

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
```

This installs the `eidolons` CLI to `~/.local/bin/eidolons` and caches the nexus at `~/.eidolons/nexus`.

Per project — empty folders or running projects:

```bash
cd <any-project>
eidolons init                # interactive — choose members and preset (offers CRYSTALIUM memory)
eidolons add forge           # add a single member later
eidolons sync                # reconcile installed members to eidolons.yaml
eidolons harness install     # wire mechanical routing + memory injection into your hosts
eidolons verify              # re-check installed Eidolons against the roster's signed metadata
```

Keep the nexus current with `eidolons upgrade self` (atomic, integrity-verified, with `--check` and `--rollback`); upgrade installed Eidolons with `eidolons upgrade`. MCP servers — CRYSTALIUM memory and the tonberry ESL runtime — are a separate catalogue managed through `eidolons mcp {list,install,upgrade,…}`. Commit `eidolons.lock` alongside `eidolons.yaml` for reproducible, tamper-evident installs. Full walkthrough: [`docs/getting-started.md`](docs/getting-started.md).

## Verified releases

Every shipped Eidolon publishes attestation-backed releases through one canonical workflow ([`eidolon-release-template.yml`](.github/workflows/eidolon-release-template.yml)) hosted here. Each release records its commit, tree, and archive SHA-256 into `roster/index.yaml` via [Roster Intake](.github/workflows/roster-intake.yml). Under the default `integrity.enforcement: strict` posture, `eidolons sync` and `eidolons verify` abort with exit 1 if any installed Eidolon's checksum drifts from the signed metadata — the same gate `Roster Health` runs nightly. Nexus releases use the same model. Read the trust model at [`docs/release-integrity.md`](docs/release-integrity.md).

## What's in this repo

| Area | What it contains |
|------|------------------|
| [`roster/`](roster/) | Machine-readable registry of every Eidolon — versions, repos, handoffs; the routing table ([`routing.yaml`](roster/routing.yaml)) and MCP catalogue ([`mcps.yaml`](roster/mcps.yaml)) |
| [`methodology/`](methodology/) | [Design principles](methodology/prime-directives.md), [composition contracts](methodology/composition.md), the routing [cortex](methodology/cortex/), vocabulary |
| [`research/`](research/) | Papers, citations, production patterns, scientific backing |
| [`cli/`](cli/) | The `eidolons` command-line tool — installs, wires, and orchestrates the team |
| [`schemas/`](schemas/) | JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries, eval suites |
| [`docs/`](docs/) | Getting started, architecture, CLI reference, MCP store, model management, release integrity |
| [`examples/`](examples/) | Worked examples: greenfield, brownfield, solo-member, partial-team |

<details>
<summary><strong>Why a nexus, when each Eidolon is independently installable?</strong></summary>

Each Eidolon is its own first-class repo, independently versioned — that's a hard invariant. The nexus is a coordinator, not an owner. It exists for what no single Eidolon can hold:

1. **Discovery** — without a roster, nobody knows which Eidolons exist or how they relate.
2. **Composition** — handoff contracts, pipeline conventions, the routing kernel, and partial-team patterns are shared assets.
3. **Research** — the scientific backing for the whole program lives in one place instead of drifting across repos.
4. **Wiring** — one `eidolons add atlas,spectra,vivi` beats fifty lines of clone-and-install docs, and `eidolons harness install` reaches hosts no individual Eidolon could.
5. **Supply-chain integrity** — one canonical signing workflow, one ingestion path, one consumer-side gate. Independent signing schemes would defeat the trust model.

The four-layer architecture (install standard → Eidolon repos → this nexus → consumer project) is documented in [`docs/architecture.md`](docs/architecture.md). The install contract every Eidolon satisfies is the **Eidolons Individual Install Standard** ([`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis)) — versioned independently; the CLI refuses to install non-conformant members.

</details>

## Contributing

Per-Eidolon bugs and features belong in that Eidolon's repo (an ATLAS finding → [Rynaro/ATLAS](https://github.com/Rynaro/ATLAS)). CLI bugs, roster issues, and composition-contract changes belong here. Install-standard questions belong in [Rynaro/eidolons-eiis](https://github.com/Rynaro/eidolons-eiis). Unsure which layer owns a concern? [`docs/architecture.md`](docs/architecture.md) maps the four layers and their responsibilities.

## License

Apache-2.0. See [LICENSE](LICENSE).
