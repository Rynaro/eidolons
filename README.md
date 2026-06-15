<p align="center"><img src="assets/eidolons.png" alt="Eidolons — a personal, portable team of AI agents" width="220"></p>

# Eidolons

> A personal, portable team of AI agents. Each is a named specialist with its own methodology, identity, and boundaries. They work alone when the task is sharp; they work in harmony when the task is big; they travel together, from project to project, codebase to codebase, host to host.

Most AI coding tools ship a single generalist that tries to plan, scout, build, and document all at once — a ceiling that arrives fast. Eidolons is a different shape: eight independently-versioned specialists across seven roles, one CLI, drop into any project. You get sharp boundaries instead of one confused generalist — plan, build, document, debug, and reason with the right specialist for each phase, over a shared memory substrate that remembers across them.

And the routing is **mechanical, not hopeful**. Most multi-agent setups are a block of prose in `CLAUDE.md` the host model is free to ignore — so it does, unless you name an agent yourself. Eidolons installs real per-host hooks: at session start the harness injects the routing decision (computed by a deterministic, non-LLM kernel) and recalls prior memory, on every prompt, without you asking. The team travels with you across hosts — Claude Code, Codex, GitHub Copilot, Cursor, OpenCode — and degrades gracefully to documentary routing wherever a host's hooks aren't sound.

<p align="center">
<a href="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml/badge.svg" alt="Roster Health"></a>
<a href="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0"></a>
<img src="https://img.shields.io/badge/nexus-v1.37.0-blue" alt="nexus v1.37.0">
<img src="https://img.shields.io/badge/EIIS-v1.4-blue" alt="EIIS v1.4">
<img src="https://img.shields.io/badge/integrity-strict-success" alt="Integrity: strict">
</p>

---

## Try it in 60 seconds

Evaluation, not commitment — this drops a read-only ATLAS into a throwaway folder:

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
cd /tmp && mkdir eidolons-demo && cd eidolons-demo
eidolons init --preset minimal --non-interactive
```

Explore, then `rm -rf /tmp/eidolons-demo` and walk away. For the full install flow, see [Install](#install) below.

---

## Meet the team

| Eidolon | What it does for you | When to reach for it | Repo | Latest |
|---------|---------------------|----------------------|------|--------|
| **ATLAS**<br><sub>A→T→L→A→S</sub> | Maps an unfamiliar codebase without writing a single line. Evidence-anchored findings, read-only by construction. | Auditing a new repo, onboarding, before any change. | [Rynaro/ATLAS](https://github.com/Rynaro/ATLAS) | 1.12.1 |
| **SPECTRA**<br><sub>S→P→E→C→T→R→A</sub> | Turns a scout report or rough idea into a decision-ready spec — scoring rubrics, validation gates, GIVEN/WHEN/THEN stories. | Planning a feature before you build it. | [Rynaro/SPECTRA](https://github.com/Rynaro/SPECTRA) | 4.9.1 |
| **Vivi**<br><sub>A→P→I→V→Δ/R</sub> | **The default coder.** Implements features in brownfield code — pattern-first, test-anchored, and loop-native: it drives a closed, bounded edit-run-test loop and gates on `pass^k` rather than declaring victory after one green run. | Shipping the change SPECTRA planned, on a loop-capable host. | [Rynaro/Vivi](https://github.com/Rynaro/Vivi) | 1.1.2 |
| **APIVR-Δ**<br><sub>A→P→I→V→Δ/R</sub> | The opt-in conservative coder — Vivi's predecessor and fallback for hosts where the closed loop isn't available. Same brownfield discipline, non-loop posture. Add explicitly with `eidolons add apivr`. | A loop-incompetent host, or when you want the conservative builder. | [Rynaro/APIVR-Delta](https://github.com/Rynaro/APIVR-Delta) | 3.7.1 |
| **IDG**<br><sub>I→D→G</sub> | Synthesizes documentation from sessions, specs, and deltas — provenance-first, with `[GAP]` / `[DISPUTED]` markers. | Chronicling what you (or the team) just built. | [Rynaro/IDG](https://github.com/Rynaro/IDG) | 1.8.1 |
| **FORGE**<br><sub>F→O→R→G→E</sub> | Deliberates on ambiguous trade-offs and novel problems. Names alternatives, surfaces assumptions, returns verdict + confidence. | Two patterns apply and the choice isn't obvious. | [Rynaro/FORGE](https://github.com/Rynaro/FORGE) | 1.9.1 |
| **VIGIL**<br><sub>V→I→G→I→L</sub> | Forensic debugger for failures resistant to normal repair. Reproduction-gated, counterfactual-verified, dependency-graph-ranked. | Flaky test, heisenbug, or a regression you can't explain. | [Rynaro/VIGIL](https://github.com/Rynaro/VIGIL) | 1.6.1 |
| **Kupo**<br><sub>K→U→P→O</sub> | Low-effort executor — heavier Eidolons delegate quick, localized, verifier-backed micro-tasks (rename, import fix, lockfile bump, lint autofix). Patches an ephemeral sandbox, proves it with a real verifier, and PROPOSEs a verified patch for the parent to commit (never writes the real tree). | Offloading trivial localized edits to keep a planner/coder session lean. | [Rynaro/Kupo](https://github.com/Rynaro/Kupo) | 1.1.1 |
| **CRYSTALIUM**<br><sub>recall→commit→consolidate→forget</sub> | Shared four-layer memory substrate (episodic / semantic / procedural / execution) every member writes to and recalls from. Tier-gated writes through one enforcement chokepoint, hybrid recall, Dream consolidation, principled forgetting. | Carrying context, decisions, and learned patterns across sessions and between members. | [Rynaro/crystalium](https://github.com/Rynaro/crystalium) | 1.4.0 |

Eight shipped agent specialists span seven capability classes — **scout, planner, coder, scriber, reasoner, debugger, executor** — with two coders: **Vivi** (the loop-native default) and **APIVR-Δ** (the opt-in conservative fallback). **Kupo** is the low-effort delegation target the others hand quick localized micro-tasks to (admitted on a behavioral additive-proof: a KEEP-cohort eval at pass^3 1.0). **CRYSTALIUM** is a different capability class — `memory`, the shared substrate underneath the roster rather than a pipeline stage. Versions and detailed handoff contracts live in [`roster/index.yaml`](roster/index.yaml) — the machine-readable source of truth.

---

## How they compose

The team has a default shape: ATLAS scouts, SPECTRA plans, **Vivi** builds, IDG chronicles. FORGE and VIGIL are lateral specialists — consultable at any stage, not always in-line. CRYSTALIUM sits underneath all of them — the shared memory substrate every member writes handoff artifacts into and recalls from, bidirectionally; not a pipeline stage. Each Eidolon's own methodology embeds the memory pipeline (recall at mission start → ingest its hand-off at trust tier T1 → trigger Dream consolidation at session end), so the team's memory is symbiotic by construction, not just by convention. Partial teams are first-class; bring just ATLAS to an audit, the full pipeline to a greenfield, or any slice that fits your project. See [`methodology/composition.md#partial-team-deployment`](methodology/composition.md#partial-team-deployment) for the full matrix and common configurations.

<details>
<summary>Canonical pipeline</summary>

```
ATLAS ───▶ SPECTRA ───▶  Vivi  ───▶ IDG
  scout      plan         build       chronicle
             ▲             │ ▲
             │             │ │
           FORGE ◀─── (ambiguity, trade-offs, novel problems)
                           │ │
                         VIGIL ◀─── (failure resisted repair; forensic attribution)
                           │
                         Kupo ◀─── (localized verifier-backed micro-tasks, PROPOSE-only)

  ╞══════════════════ CRYSTALIUM ══════════════════╡
   shared memory substrate — every member commits handoff
   artifacts and recalls them (bidirectional, not a stage)
```

</details>

Handoffs between members are structured artifacts written to disk — not free-form messages. See [`methodology/composition.md`](methodology/composition.md) for the handoff contract table and invariants.

---

## Mechanical routing — the harness

A descriptor table in a prose file can only *suggest* delegation; the host model decides whether to listen, and usually it doesn't until you name an Eidolon yourself. Eidolons closes that gap with a per-host **harness** built on three pieces that already work standalone:

- **A deterministic routing kernel.** `eidolons run "<prompt>" --json` classifies a prompt against [`roster/routing.yaml`](roster/routing.yaml) — no LLM, fully reproducible — and emits which Eidolon(s) handle it, at what tier, in what chain.
- **Per-host hook adapters.** `eidolons harness install` wires that kernel into each host's own lifecycle hooks (Claude Code & Codex `settings.json` / `hooks.json`; Copilot `.github/hooks`; Cursor static rules; OpenCode permission gates). At session start the harness injects the routing artifact and a memory digest as context — **the host doesn't have to remember to delegate; the routing arrives on its own.**
- **Graceful degradation.** Routing is **injected by default** (advisory-mechanical); an opt-in `--strict` tier adds tool-boundary *blocking* on hosts whose blocking surfaces are verified sound. Where a host's hooks are buggy or absent, the harness silently falls back to documentary routing — never worse than prose, often much better.

```bash
eidolons harness install            # wire routing + memory injection into the detected hosts
eidolons harness install --strict   # opt-in: add tool-boundary delegate-or-deny where sound
eidolons harness status             # per-host effective enforcement tier
```

**Self-healing settings (v1.42.0).** The Claude Code SessionStart hook is wired with a `startup|resume|clear|compact` matcher so the cortex is re-injected after auto-compaction (a `startup`-only matcher silently stops working mid-session). `eidolons sync` now **self-heals** a stale `startup`-only matcher in `.claude/settings.json` in place — only ever touching the Eidolons-owned entry, never a foreign hook. So the upgrade path is simply:

```bash
eidolons upgrade self   # upgrade to the latest stable nexus
eidolons sync           # heals the SessionStart matcher in place (no --force dance)
```

The heal is on by default and idempotent (a second `sync` is a no-op). Pass `--no-heal` to `eidolons sync` (or `eidolons harness install`) to opt out. `eidolons harness install --force` also heals its own entry now (the merge is an upsert, not append-if-absent — this supersedes the v1.41.2 manual-edit advice).

**Defense in depth: `--strict`.** The default tier injects routing as *advisory* context — the host can still ignore it. For a hard backstop, `eidolons harness install --strict` adds a `PreToolUse` **delegate-or-deny** tier that mechanically *blocks* main-loop edits (so direct edits from the top-level loop are denied; only delegated subagents may write), plus protected-glob denials in all contexts. Soundness is per-host: **claude-code** gets full delegate-or-deny + protected-globs; **codex** gets protected-globs only (its `PreToolUse` exposes no `agent_id`, so main-loop vs subagent can't be distinguished); **opencode** gets an advisory plugin only (the `tool.execute.before` block is unsound, #5894); **cursor** is refused (out of scope). Use `--strict` when you want delegation enforced, not merely suggested.

**Memory pre-flight is mechanical too.** When CRYSTALIUM is installed, the session-start hook runs `eidolons memory preflight` — a one-shot, out-of-band recall that injects prior project memory into context, fail-open and bounded. Memory becomes a harness guarantee, not something the model has to think to ask for.

The whole design — what each vendor's hooks can actually *force* versus merely suggest, and the per-host enforcement ladder — is written up in [`DOSSIER-HARNESS-2026-06.md`](DOSSIER-HARNESS-2026-06.md) and [`docs/architecture.md`](docs/architecture.md) § "Harness Layer". And it's *measured*: [`eidolons eval compliance`](docs/cli-reference.md) runs an A/B (harness-wired vs prose-only) instrument that reports whether the injection actually changes the host's delegation behaviour.

---

## Install

One-time, global:

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
```

This installs the `eidolons` CLI to `~/.local/bin/eidolons` and caches the nexus at `~/.eidolons/nexus`.

Per project — works on empty folders or running projects:

```bash
cd <any-project>
eidolons init                    # interactive — choose members and preset (offers CRYSTALIUM memory)
eidolons add forge               # add a single member later
eidolons sync                    # reconcile installed members to eidolons.yaml
eidolons harness install         # wire mechanical routing + memory injection into your hosts
eidolons verify                  # re-check installed Eidolons against the roster's signed metadata
```

### Updating

Keep the nexus itself up to date with:

```bash
eidolons upgrade self            # upgrade to latest stable nexus release
eidolons upgrade self --check    # read-only: see what would change, no writes
eidolons upgrade self --rollback # revert to the previous install (nexus.prev)
```

`upgrade self` is atomic and rollback-safe: it clones the new version alongside your current install, verifies integrity (commit SHA, tree SHA, archive SHA-256 from `roster/index.yaml`), runs a smoke test, then renames atomically. On any failure before the rename, the candidate is discarded and your current install is untouched. The previous install is retained as `~/.eidolons/nexus.prev` for one-step rollback.

To upgrade installed Eidolons (ATLAS, SPECTRA, Vivi, …), use `eidolons upgrade` (no `self`) — see the CLI reference.

### MCP servers & memory

MCP servers are a separate catalogue ([`roster/mcps.yaml`](roster/mcps.yaml)) managed through one unified verb surface:

```bash
eidolons mcp list                       # what's available
eidolons mcp install crystalium         # the shared memory substrate (recommended)
eidolons mcp install atlas-aci          # the code-graph MCP server used alongside ATLAS
eidolons mcp install junction           # the ECL transport bus for inter-Eidolon hand-offs
```

Installing an MCP wires it correctly per host (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`, `opencode.json`) and, for tool-granting servers, injects its tool surface into the relevant Eidolons' allowlists. `atlas-aci` and `crystalium` are external packages Eidolons *consume* — they are not Eidolons and the `atlas` Eidolon (scout methodology) is distinct from the `atlas-aci` MCP server; see [`docs/mcp.md`](docs/mcp.md) and [`docs/architecture.md`](docs/architecture.md).

Commit `eidolons.lock` alongside `eidolons.yaml` — the lockfile pins resolved versions and integrity checksums (`commit`, `tree`, `archive_sha256`, `manifest_sha256`) for reproducible, tamper-evident installs. For the full flow, read [`docs/getting-started.md`](docs/getting-started.md).

---

## Verified releases

Every shipped Eidolon publishes attestation-backed releases through a canonical workflow ([`eidolon-release-template.yml`](.github/workflows/eidolon-release-template.yml)) hosted in this nexus. Each release records its commit, tree, and archive SHA-256 into `roster/index.yaml` via [`Roster Intake`](.github/workflows/roster-intake.yml), with GitHub artifact attestations bound to the canonical signer workflow.

`eidolons sync` and `eidolons verify` enforce that contract on the consumer side. Under the default `integrity.enforcement: strict` posture, any installed Eidolon whose commit/tree/archive checksum drifts from the roster's signed metadata aborts with exit 1 — the same gate `Roster Health` runs nightly against every shipped Eidolon. Read the trust model end-to-end at [`docs/release-integrity.md`](docs/release-integrity.md).

**Nexus releases** use the same commit/tree/archive-SHA-256 model. Each `eidolons upgrade self` re-verifies the downloaded nexus against the `nexus.versions.releases.<v>` block in `roster/index.yaml` before swapping it in. The release workflow ([`.github/workflows/release-nexus.yml`](.github/workflows/release-nexus.yml)) produces these artefacts automatically on each `vX.Y.Z` tag.

**Auto-merge** of routine roster bumps. Roster bumps that pass attestation verification + required checks auto-merge once Roster Intake opens the PR (via `gh pr merge --auto --squash`). First-shipped Eidolon transitions are held as DRAFT for manual review. Bad merges revert with `git revert <merge-sha>`; the next nightly `roster-health` re-validates. See `docs/release-integrity.md` § "Auto-merge of routine roster bumps".

---

## What's in this repo

| Area | What it contains |
|------|------------------|
| [`roster/`](roster/) | Machine-readable registry of every Eidolon, their versions, repos, handoff contracts; the routing table ([`routing.yaml`](roster/routing.yaml)) and MCP catalogue ([`mcps.yaml`](roster/mcps.yaml)) |
| [`methodology/`](methodology/) | Aggregated [design principles](methodology/prime-directives.md), [composition contracts](methodology/composition.md), the routing [cortex](methodology/cortex/), vocabulary |
| [`research/`](research/) | Papers, citations, production patterns, scientific backing |
| [`cli/`](cli/) | The `eidolons` command-line tool — installs, wires, and orchestrates the team |
| [`schemas/`](schemas/) | JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries, eval suites |
| [`docs/`](docs/) | Getting started, architecture, CLI reference, MCP store, model management, release integrity |
| [`examples/`](examples/) | Worked examples: greenfield, brownfield, solo-member, partial-team |

---

## Why a nexus

Each Eidolon is independently installable and independently versioned — that's a hard design invariant. The nexus exists because:

1. **Discovery.** Without a roster, nobody knows which Eidolons exist or how they relate.
2. **Composition.** The team is more than the sum of its members. Handoff contracts, pipeline conventions, the routing kernel, and partial-team deployment patterns live here, not in any individual Eidolon's repo.
3. **Research.** The scientific backing for the whole program — papers, production precedents, evidence-to-design mappings — is a shared asset. Duplicating it across many repos is wasteful and drifts.
4. **Installation & wiring orchestration.** A single `eidolons add atlas,spectra,vivi` is worth fifty lines of documentation explaining how to clone repos and run installers — and `eidolons harness install` wires routing into hosts no individual Eidolon could reach.
5. **Supply-chain integrity.** The release-integrity contract is a *shared* asset: one canonical signing workflow ([`eidolon-release-template.yml`](.github/workflows/eidolon-release-template.yml)) every Eidolon adopts, one ingestion path ([`Roster Intake`](.github/workflows/roster-intake.yml)) that verifies attestations, one consumer-side gate (`eidolons verify`) that enforces them. Independent repos with independent signing schemes would defeat the trust model.

Each Eidolon remains a first-class repo. This nexus is a coordinator, not an owner. The four-layer architecture (install standard → Eidolon repos → this nexus → consumer project) is documented in [`docs/architecture.md`](docs/architecture.md).

---

<!-- Curated highlights from CHANGELOG.md. Refresh on every release. -->
## Recently shipped

- **Mechanical routing across all five hosts (v1.36.0) + mechanical memory pre-flight (v1.37.0).** The harness campaign turns documentary routing into installed behaviour: `eidolons run --hook <host>` feeds the deterministic kernel into per-host lifecycle hooks; `eidolons harness install|remove|status` wires Claude Code, Codex, GitHub Copilot, Cursor, and OpenCode to inject the routing artifact (and, with CRYSTALIUM, a recalled-memory digest) at session start — degrading to prose where a host's hooks aren't sound, with an opt-in `--strict` tool-boundary tier. GAP-2 adds `eidolons memory preflight`, a one-shot out-of-band CRYSTALIUM recall (CRYSTALIUM **v1.4.0** ships the `recall` CLI it consumes). Full design + per-host capability matrix: [`DOSSIER-HARNESS-2026-06.md`](DOSSIER-HARNESS-2026-06.md).
- **`eidolons eval compliance` — does the injection actually work?** An A/B instrument that runs a prompt suite through a headless host in two arms (harness-wired vs prose-cortex-only), parses the stream for dispatches, and scores against live kernel ground truth — reporting correct-routing rate, consistency (`pass^k`), the harness delta, and a gate verdict. CI runs only the free fake-driver path; live measurement is supervised. See [`docs/cli-reference.md`](docs/cli-reference.md).
- **Vivi — the loop-native default coder (v1.32.0).** A new FF-named Eidolon inherits APIVR-Δ's spine and becomes the default coder, driving a closed, bounded edit-run-test loop (`eidolons sandbox loop`) that gates on `pass^k` and refuses to game the tests. APIVR-Δ is retained as the opt-in conservative fallback (`eidolons add apivr`). The succession shipped on a *measured* outcome, not a documentary one.
- **`eidolons model` — vendor-neutral model management (v1.31.0).** Every Eidolon/class gets a criteria-chosen *suggested* and *default* model on a `light < standard < deep` tier ladder, user-calibratable per project. Vendor model strings are quarantined to `roster/model-profiles.yaml` (the cortex stays vendor-free); ships **anthropic** + **openai** profiles. `eidolons model {list,show,use,profile,reset}` plus a guided picker write the concrete `model:` into host agent frontmatter, with a `doctor --deep` D9 drift gate. See [`docs/model.md`](docs/model.md).
- **Kupo — the low-effort executor (v1.0.0+).** An 8th capability class: a small PROPOSE-only sandbox worker the heavier Eidolons delegate quick localized micro-tasks to. Admitted on a behavioral additive-proof (KEEP-cohort eval, pass^3 1.0) and a new `eidolons sandbox apply` harness applier.
- **CRYSTALIUM mainframe + team-wide memory pipelines.** CRYSTALIUM is the always-on shared-memory substrate: a `CRYSTALIUM_CALLER_TIER=T1` unlock so Eidolon writes reach the semantic/execution layers (Dream consolidation included), ECL `ingest` as the symbiotic write-spine, and every Eidolon's methodology embedding `recall → ingest(T1) → session_end` with a standalone fallback. See [`methodology/cortex/memory-protocol.md`](methodology/cortex/memory-protocol.md).
- **Unified MCP store (v1.9.0+).** `eidolons mcp {list,show,install,refresh,uninstall,upgrade,health,use,pull,images}` over a `roster/mcps.yaml` catalogue + `eidolons.mcp.lock` lockfile; per-host wiring for `.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`, and `opencode.json`. See [`docs/mcp.md`](docs/mcp.md).
- **Three-layer methodology integrity guarantee.** `eidolons doctor --deep` (static gates over installed manifests), `eidolons verify-release` (re-derives each Eidolon's install tree and SHA-256-diffs it), and `eidolons canary` (behavioral mission prompts validated against a small DSL). See [`docs/cli-reference.md`](docs/cli-reference.md).

See [`CHANGELOG.md`](CHANGELOG.md) for the full history.

---

## Relationship to EIIS

The **Eidolons Individual Install Standard** (`Rynaro/eidolons-eiis`) defines the contract every Eidolon repo satisfies — file layout, `install.sh` interface, manifest schema.

This nexus (`Rynaro/eidolons`) *depends* on EIIS. Every Eidolon listed in [`roster/index.yaml`](roster/index.yaml) must be EIIS-conformant; the CLI refuses to install non-conformant members.

They version independently. EIIS v1.x is the contract; eidolons v1.x is the orchestrator.

---

## Contributing

Per-Eidolon bugs and feature requests belong in that Eidolon's repo (e.g. an ATLAS finding goes to [Rynaro/ATLAS](https://github.com/Rynaro/ATLAS), not here). CLI bugs, roster issues, and composition-contract changes belong in this repo ([Rynaro/eidolons](https://github.com/Rynaro/eidolons)). Questions about the install standard itself belong in [Rynaro/eidolons-eiis](https://github.com/Rynaro/eidolons-eiis). If you're unsure which layer owns a concern, [`docs/architecture.md`](docs/architecture.md) maps the four layers and their responsibilities.

---

## License

Apache-2.0. See [LICENSE](LICENSE).
