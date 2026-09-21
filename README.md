<p align="center"><img src="assets/eidolons.png" alt="Eidolons — a personal, portable team of AI agents" width="220"></p>

<h1 align="center">Eidolons</h1>

<p align="center"><em>A personal team for understanding, planning, building, and checking software.</em></p>

<!-- Release badges stay dynamic: the nexus and its members version independently. -->
<p align="center">
<a href="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml/badge.svg" alt="Roster Health"></a>
<a href="https://github.com/Rynaro/eidolons/releases"><img src="https://img.shields.io/github/v/release/Rynaro/eidolons?sort=semver&label=nexus&color=blue" alt="Nexus release"></a>
<a href="https://github.com/Rynaro/eidolons-eiis/releases"><img src="https://img.shields.io/github/v/release/Rynaro/eidolons-eiis?sort=semver&label=EIIS&color=blue" alt="EIIS release"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0"></a>
</p>

<p align="center">
<a href="#start-here">Start here</a> ·
<a href="#meet-the-team">The team</a> ·
<a href="#work-through-a-real-task">Workflow</a> ·
<a href="#new-in-v33-observe-and-preserve">What's new</a> ·
<a href="#go-deeper">For experts</a> ·
<a href="#evidence-you-can-inspect">Evidence</a>
</p>

Eidolons installs named AI specialists into your projects and connects them to your coding host. ATLAS explores the code, RAMZA writes the plan, Vivi implements it, and IDG documents the result. Other members handle difficult diagnoses, trade-offs, and small repairs.

The **nexus** is this repository and its `eidolons` CLI: it installs the team, maintains versions, computes routes, and wires host integrations. Your coding host supplies the model and execution environment. Adapters are available for Claude Code, Codex, GitHub Copilot, Cursor, and OpenCode; their hook and enforcement capabilities differ. Use an installed, authenticated host to run the agents; the CLI does not include a model subscription.

You can start with one scout and add members as the work grows. The names are inspired by Final Fantasy summons; each comes with its own methodology, role boundaries, and independently versioned repository.

## Start here

### 1. Install the CLI

On macOS or Linux, have `git`, `bash`, `curl`, and `jq` available, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
eidolons --version --quiet
```

The installer places the CLI in `~/.local/bin/eidolons`, caches the nexus in `~/.eidolons/nexus`, and downloads the pinned `yq` binary if needed. Follow its PATH hint if your shell cannot find `eidolons`. The bootstrap defaults to `main`; set `EIDOLONS_REF` to a release tag for a pinned install.

Already installed? Use `eidolons upgrade self` to update.

### 2. Add a team to your project

Run this from the project root:

```bash
eidolons init --preset pipeline
eidolons harness install
eidolons doctor
eidolons harness check
```

Choose your host when prompted. The `pipeline` preset installs ATLAS, RAMZA, Vivi, and IDG. The **harness** connects routing instructions to the host's supported hooks. Open a new host session after wiring.

For a small, non-interactive trial, explicitly select your host:

```bash
mkdir eidolons-demo
cd eidolons-demo
eidolons init --preset minimal --hosts claude-code --non-interactive --no-mcp
eidolons harness install
```

Replace `claude-code` with your host identifier. `minimal` installs only ATLAS; `--no-mcp` skips the optional CRYSTALIUM setup offer.

### 3. Ask for something concrete

In your coding host's conversation:

> ATLAS, map how authentication works in this repository. Cite the entry points, important dependencies, and existing tests. Keep this read-only.

For a larger task:

> Plan and build a rate limiter for the public API. Preserve the existing response format, add regression tests, and have a separate checker review the change.

To inspect the route yourself:

```bash
eidolons run "plan and build a rate limiter for the public API" --json
```

Selected fields from the route:

```json
{
  "decision": "chain",
  "selected": ["ramza", "vivi"],
  "model_tier_per_step": ["deep", "standard"],
  "tier": "standard"
}
```

**`eidolons run` computes a routing decision.** It does not launch agents or edit your code. The wired host receives that decision and carries out delegation through its own execution tools.

[Getting started](docs/getting-started.md) · [All CLI commands](docs/cli-reference.md) · [Install smoke test](docs/smoke-test.md)

## Meet the team

| Member | Bring them in when you need… |
|---|---|
| **[ATLAS](https://github.com/Rynaro/ATLAS)** · scout | A map of unfamiliar code, with evidence and references. |
| **[RAMZA](https://github.com/Rynaro/Ramza)** · default planner | A scoped specification, acceptance criteria, and a verification plan. |
| **[Vivi](https://github.com/Rynaro/Vivi)** · default coder | Implementation through an edit, test, and repair loop. |
| **[IDG](https://github.com/Rynaro/IDG)** · scriber | Documentation, an ADR, or a runbook that preserves decisions and uncertainty. |
| **[FORGE](https://github.com/Rynaro/FORGE)** · reasoner | A decision between competing approaches, with explicit trade-offs. |
| **[VIGIL](https://github.com/Rynaro/VIGIL)** · debugger | A reproducible diagnosis when a failure resists repair. |
| **[Kupo](https://github.com/Rynaro/Kupo)** · executor | A bounded micro-task and a checked patch proposal. |
| **[Gilgamesh](https://github.com/Rynaro/Gilgamesh)** · generalist | A bounded, actionable task that has no matching specialist. |
| **[SPECTRA](https://github.com/Rynaro/SPECTRA)** · opt-in planner | The alternative prose-based planning methodology. |
| **[APIVR-Δ](https://github.com/Rynaro/APIVR-Delta)** · opt-in coder | The conservative implementation methodology. |

[CRYSTALIUM](https://github.com/Rynaro/crystalium) is the optional shared memory service, installed separately through the MCP catalogue.

| Starting point | Preset | Members |
|---|---|---|
| Understand a repository | `minimal` | ATLAS |
| Deliver a scoped feature | `pipeline` | ATLAS, RAMZA, Vivi, IDG |
| Plan and implement | `plan-and-build` | RAMZA, Vivi |
| Add diagnosis and decision support | `full` | Pipeline + FORGE, VIGIL, Kupo, Gilgamesh |

```bash
eidolons list --presets
eidolons add vigil,forge
eidolons roster vigil
```

The [roster](roster/index.yaml) defines members, releases, and presets. `full` uses one default planner and coder; add SPECTRA or APIVR-Δ explicitly if you want them.

## Work through a real task

A useful prompt gives the team four things: an outcome, a bounded area, constraints to preserve, and evidence that will count as success.

> Fix duplicate job execution in the queue worker. Keep the public API unchanged. First reproduce the failure, then implement the smallest fix. Finish with the regression test result and a separate review of retry behavior.

Use the phases the task needs:

| Phase | Expected handoff |
|---|---|
| **Explore — ATLAS** | Relevant files, call paths, tests, and unresolved questions. |
| **Decide or plan — FORGE / RAMZA** | Chosen approach, scope, acceptance criteria, and exclusions. |
| **Build — Vivi** | A reviewable diff and recorded test results. |
| **Check — a separate reviewer; VIGIL for failures** | Findings tied to the diff and acceptance criteria. |
| **Document — IDG** | Updated usage, decisions, and operational notes. |

Keep diagnosis and implementation separate when you want review first: “Diagnose this failure and propose a fix; stop before implementation.” For implementation requests, state the allowed changes and the stopping condition.

The router uses deterministic rules from [`roster/routing.yaml`](roster/routing.yaml), without model calls. A selected chain can still be wrong or unavailable in your project. Inspect `selected`, `clarification_request`, and assumptions; confirm the host actually used the intended members.

## New in v3.3: observe and preserve

The v3.3 commands add local receipts and checkpoint primitives. They make more of the workflow inspectable, with the current implementation boundaries below.

### Inspect configuration and route intent

```bash
eidolons readiness --json
eidolons readiness --live --json
eidolons run "audit the loader; do not implement changes" --json
```

Readiness writes `.eidolons/.readiness/receipt.json`, recording manifest/lock digests, discovery locations, and check outcomes. In this version, `--live` runs harness registration and syntax checks for supported hosts; it does **not** launch a real model session. Enforcement fields reflect lock declarations, and host versions remain unknown.

Routing JSON now includes `route_contract` and `semantic_decision_digest`. The contract exposes operation sets inferred from prompt text and labels enforcement as advisory. Treat it as routing metadata: the host must apply the actual task permissions.

### Save state before a long-session handoff

Create a `task-state.json` file with the fields the checkpoint command requires:

```json
{
  "constraints": ["Keep the public API unchanged"],
  "anchors": ["src/queue.ts:42"],
  "decisions": ["Use an idempotency key for each job"],
  "failed_approaches": ["A process-local lock does not cover multiple workers"],
  "open_variables": ["Which store owns key expiration?"],
  "pending_checks": ["Repeat the duplicate-delivery regression test"],
  "lineage": ["queue-repair"]
}
```

Replace the example paths and decisions with your task's actual state, then:

```bash
eidolons context checkpoint create --payload task-state.json --run-id queue-repair --json
```

The receipt returns a `checkpoint_id`. Copy that value into the recovery command:

```bash
eidolons context checkpoint recover --id <checkpoint_id> --json
```

Recovery checks the payload digest and required-field presence, then returns the saved JSON. Review it against the current source before continuing. Payload and receipt files live under `.eidolons/.context/checkpoints/`; local atomic renames do not constitute remote backup. Use a fresh ID for each checkpoint.

<details>
<summary><strong>Experimental interfaces: ledger, capsules, recall, policy, and ACP</strong></summary>

These commands are available for local experimentation. They are not a completed cross-host execution or calibration system.

| Interface | Current behavior | Boundary |
|---|---|---|
| `EIDOLONS_LEDGER=1 eidolons run …` | Records a planned route; `eidolons ledger status --run-id <semantic_decision_digest> --json` reads its summary. | Matching route digests reuse a run ID. Dispatch and checker observations require explicit recording; checker labels are not authenticated proof. |
| `eidolons augment capsule export` / `preview` | Writes and inspects a small manifest with optional checkpoint and ledger references. | No import/resume execution, blob transfer, or source-revision validation. Preview is not a complete compatibility or secrets audit. |
| `eidolons augment recall add` / `list` / `invalidate` | Stores local notes marked untrusted; selects up to five active records within 1,200 estimated tokens. | Separate from CRYSTALIUM; selection favors short records rather than semantic relevance. Invalidation targets an individual record. |
| `eidolons augment evidence` | An initial observation-report interface. | Replay grading and comparative evaluation remain incomplete; use the existing `eval` commands for supported evaluations. |
| `eidolons augment policy` | Checks declared parameter categories and emits candidate metadata labeled shadow-only. | Does not run a shadow router, validate a full policy diff, or promote a policy. |
| `eidolons augment acp` | Emits a local version/capability receipt. | No negotiated editor session, prompt execution, cancellation, or session loading. It is not an ACP bridge. |

Inspect the [implementation](cli/src/augment.sh), [ledger](cli/src/ledger.sh), and [schemas](schemas/) before integrating these primitives into automation.

</details>

## Go deeper

### Understand what the host enforces

```bash
eidolons harness status
eidolons harness check
eidolons canary --all-hosts
```

Host integration has distinct layers: discovering an agent, injecting a route, choosing a model, and restricting tools. Success at one layer does not establish the others.

The harness is advisory by default. Its optional `eidolons harness install --strict` mode has host-specific boundaries: Claude Code supports delegate-or-deny and protected paths; Codex uses protected-path checks. Consult [harness architecture](docs/architecture.md) and the [host dossier](DOSSIER-HARNESS-2026-06.md) before depending on strict enforcement.

When atlas-aci is configured, incremental code-graph refresh is **on by default**. Set `harness.atlas_sync.enabled: false` in `eidolons.yaml` to disable it.

### Allocate models by role

```bash
eidolons model list
eidolons model show --json
eidolons model use ramza@deep --dry-run
```

The tier ladder is `light < standard < deep`. Profiles map tiers to concrete models; inspect the resolved assignments before changing them. Remove `--dry-run` to apply an override.

Routing `tier: standard|trance` describes the orchestration mode; `model_tier_per_step` describes each member's requested model tier. They are different controls. Neither is evidence of which model the host actually ran. [Model profiles](roster/model-profiles.yaml) · [TRANCE rules](methodology/cortex/trance-matrix.md)

### Connect memory, lifecycle, and context

```bash
eidolons mcp list
eidolons mcp install crystalium
eidolons memory preflight --explain
```

MCP servers are optional tools with their own runtime requirements. CRYSTALIUM provides shared memory; Tonberry supports the specification lifecycle; Atomos provides context operations. Inspect a server with `eidolons mcp show <name>` before installing it.

Four contracts organize the system:

| Contract | Responsibility |
|---|---|
| [EIIS](https://github.com/Rynaro/eidolons-eiis) | Member packaging, canonical files, and host discovery adapters. |
| [ECL](https://github.com/Rynaro/eidolons-ecl) | Structured handoff envelopes, artifact references, and integrity metadata. |
| [ESL](https://github.com/Rynaro/eidolons-esl) | Specification stages, verification, and drift checks. |
| [ECM](https://github.com/Rynaro/eidolons-ecm) | Context measurement, policy, externalization, and session handoffs. |

ECM is enabled through the project's `context:` configuration. Use `eidolons context status` and `eidolons context policy` to inspect its meter and decision. Missing telemetry may leave estimates unknown. [Context protocol](methodology/cortex/context-protocol.md) · [Memory protocol](methodology/cortex/memory-protocol.md)

For Claude Code, the Final Fantasy statusline displays context occupancy, spend, branch, and active work. With ECM enabled, `eidolons harness install` can wire it while preserving an existing user-owned statusline. Inspect the connection with `eidolons statusline doctor`.

### Measure evidence and cost separately

```bash
eidolons telemetry enable
eidolons telemetry report --json
eidolons trace verify path/to/handoff.envelope.json --block --json
```

Telemetry capture is opt-in. Reports distinguish host-derived usage from estimates; check the source before comparing costs. A valid artifact digest establishes byte integrity. It does not establish correctness or an independent review. Use explicit acceptance criteria and a separate checker for those conclusions.

## Evidence you can inspect

Run the deterministic routing benchmark without a model API key:

```bash
eidolons eval routing --suite public --validate-suite
eidolons eval routing --suite public
```

This measures agreement with the [labelled routing suite](evals/routing-suite.yaml). It does not measure whether a host follows a route or whether an agent solves the task.

The repository also provides `eval compliance`, `eval quality`, `eval swe`, and `eval baseline` for delegation behavior, artifact quality, coding outcomes, and regressions. Read the [scorecard guide](evals/results/README.md) before interpreting [stored results](evals/results/): smoke runs exercise the harness with reference fixes, and small or saturated cohorts do not establish broad model superiority. Live host evaluations can incur model costs.

Start with your own representative tasks. Keep the model, total budget, expected results, and checker criteria fixed when comparing approaches; retain failures and timeouts in the comparison.

## Maintain your installation

| Task | Command |
|---|---|
| Inspect installed members | `eidolons list` |
| Reconcile project members with the manifest | `eidolons sync` |
| Inspect CLI pin and roster channel | `eidolons nexus status` |
| Check for a CLI update | `eidolons upgrade self --check` |
| Upgrade the CLI | `eidolons upgrade self` |
| Restore the previous CLI installation | `eidolons upgrade self --rollback` |
| Verify installed member integrity | `eidolons verify` |
| Inspect MCP health | `eidolons mcp health --all` |

CLI upgrades are atomic and integrity-verified when release evidence is available; read the reported integrity outcome. The prior installation is retained for rollback. The roster channel can advance independently of the CLI version.

Commit `eidolons.yaml` and `eidolons.lock` so project intent and resolved member versions can be reviewed together. Review generated host-file changes before committing them. Local receipts and session state under `.eidolons/` may be gitignored; inspect the project's ignore rules before relying on Git to preserve a checkpoint.

Release metadata records commit, tree, and archive hashes in the [roster](roster/index.yaml). Consumer checks compare against that metadata; the [release integrity guide](docs/release-integrity.md) explains the trust boundary. [Changelog](CHANGELOG.md) · [Migration guide](MIGRATION.md)

## How the pieces fit

In EIIS v3, installed member instructions live under `.eidolons/<agent>/`:

```text
your-project/
├── eidolons.yaml                  Team and host configuration
├── eidolons.lock                  Resolved versions and install receipts
├── EIDOLONS.md                    Routing and composition entrypoint
├── AGENTS.md / CLAUDE.md          Discovery pointers, as configured
└── .eidolons/
    └── <agent>/
        ├── PERSONA.md            Role and operating instructions
        ├── SPEC.md               Normative member specification
        └── skills/
            └── <methodology>/
                └── SKILL.md      Methodology and colocated resources
```

Host adapters expose these canonical instructions in the format each host understands. Keep customizations aligned with the canonical files; copied instructions drift. [EIIS v3 integration](docs/eiis-3.0.md) · [Architecture](docs/architecture.md)

| Explore | Start with |
|---|---|
| CLI usage and examples | [CLI reference](docs/cli-reference.md), [examples](examples/) |
| Routing and composition | [Cortex](methodology/cortex/), [composition](methodology/composition.md) |
| Available members and tools | [Roster](roster/index.yaml), [MCP catalogue](roster/mcps.yaml) |
| Implementation and contracts | [CLI source](cli/src/), [JSON schemas](schemas/) |
| Experiments and supporting research | [Evaluations](evals/), [research index](research/INDEX.md) |
| Design commitments | [Manifesto](MANIFESTO.md), [prime directives](methodology/prime-directives.md) |

## When to keep it simple

A single assistant may be enough for a short, disposable task. Eidolons is most useful when work benefits from distinct phases, reusable methods, and continuity across sessions. Start with the smallest useful team.

If your host has no suitable hook or tool-control surface, expect documentary guidance rather than enforced delegation. The experimental continuity commands are not yet a substitute for a tested cross-host resume workflow.

## Contributing

CLI, roster, and composition issues belong here. Member-specific bugs belong in the member's repository; installation-contract changes belong in [EIIS](https://github.com/Rynaro/eidolons-eiis). Include the host, CLI version, reproduction steps, and relevant command output when reporting a problem.

For registry changes, run `make schema`. Its shared validator requires Python 3
and PyYAML; use a virtual environment if PyYAML is not already available:

```bash
python3 -m venv /tmp/eidolons-schema-venv
. /tmp/eidolons-schema-venv/bin/activate
python -m pip install 'PyYAML==6.0.2'
make schema
```

The gate rejects duplicate authored YAML/JSON keys and incomplete integrity
metadata for advertised `latest`/`stable` releases. Historical records remain
readable; explicitly selected publication records must pass the same gate.
PR, roster-health, nexus-release, and intake workflows use
[`scripts/validate-registry.py`](scripts/validate-registry.py). Intake validates
the raw release manifest before normalization. The reusable member-release
producer remains unchanged. See the [V4-03 receipt](docs/campaigns/gauge/receipts/V4-03.md)
for the executed checks and their limits.

<!-- IDG provenance: V4-03 handoff; scripts/validate-registry.py; receipt above. -->

## License

Apache-2.0. See [LICENSE](LICENSE).
