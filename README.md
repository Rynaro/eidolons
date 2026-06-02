<p align="center"><img src="assets/eidolons.png" alt="Eidolons — a personal, portable team of AI agents" width="220"></p>

# Eidolons

> A personal, portable team of AI agents. Each is a named specialist with its own methodology, identity, and boundaries. They work alone when the task is sharp; they work in harmony when the task is big; they travel together, from project to project, codebase to codebase, host to host.

Most AI coding tools ship a single generalist that tries to plan, scout, build, and document all at once — a ceiling that arrives fast. Eidolons is a different shape: seven independently-versioned specialists, one CLI, drop into any project. You get sharp boundaries instead of one confused generalist — plan, build, document, debug, and reason with the right specialist for each phase, over a shared memory substrate that remembers across them. They travel with you across projects and hosts (Claude Code, Copilot, Cursor, OpenCode, Codex).

<p align="center">
<a href="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/roster-health.yml/badge.svg" alt="Roster Health"></a>
<a href="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml"><img src="https://github.com/Rynaro/eidolons/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-blue" alt="Apache-2.0"></a>
<img src="https://img.shields.io/badge/nexus-v1.13.4-blue" alt="nexus v1.13.4">
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
| **ATLAS**<br><sub>A→T→L→A→S</sub> | Maps an unfamiliar codebase without writing a single line. Evidence-anchored findings, read-only by construction. | Auditing a new repo, onboarding, before any change. | [Rynaro/ATLAS](https://github.com/Rynaro/ATLAS) | 1.9.0 |
| **SPECTRA**<br><sub>S→P→E→C→T→R→A</sub> | Turns a scout report or rough idea into a decision-ready spec — scoring rubrics, validation gates, GIVEN/WHEN/THEN stories. | Planning a feature before you build it. | [Rynaro/SPECTRA](https://github.com/Rynaro/SPECTRA) | 4.6.0 |
| **APIVR-Δ**<br><sub>A→P→I→V→Δ/R</sub> | Implements features in brownfield code — pattern-first, test-anchored, bounded failure-recovery loop. | Shipping the change SPECTRA planned. | [Rynaro/APIVR-Delta](https://github.com/Rynaro/APIVR-Delta) | 3.4.0 |
| **IDG**<br><sub>I→D→G</sub> | Synthesizes documentation from sessions, specs, and deltas — provenance-first, with `[GAP]` / `[DISPUTED]` markers. | Chronicling what you (or the team) just built. | [Rynaro/IDG](https://github.com/Rynaro/IDG) | 1.5.0 |
| **FORGE**<br><sub>F→O→R→G→E</sub> | Deliberates on ambiguous trade-offs and novel problems. Names alternatives, surfaces assumptions, returns verdict + confidence. | Two patterns apply and the choice isn't obvious. | [Rynaro/FORGE](https://github.com/Rynaro/FORGE) | 1.6.0 |
| **VIGIL**<br><sub>V→I→G→I→L</sub> | Forensic debugger for failures resistant to normal repair. Reproduction-gated, counterfactual-verified, dependency-graph-ranked. | Flaky test, heisenbug, or a regression you can't explain. | [Rynaro/VIGIL](https://github.com/Rynaro/VIGIL) | 1.4.0 |
| **CRYSTALIUM**<br><sub>recall→commit→consolidate→forget</sub> | Shared four-layer memory substrate (episodic / semantic / procedural / execution) every member writes to and recalls from. Tier-gated writes through one enforcement chokepoint, hybrid recall, Dream consolidation, principled forgetting. | Carrying context, decisions, and learned patterns across sessions and between members. | [Rynaro/crystalium](https://github.com/Rynaro/crystalium) | 1.2.0 |

The first six are agent specialists; **CRYSTALIUM** is a different capability class — `memory`, the shared substrate underneath the roster rather than a pipeline stage. Versions and detailed handoff contracts live in [`roster/index.yaml`](roster/index.yaml) — the machine-readable source of truth.

---

## How they compose

The team has a default shape: ATLAS scouts, SPECTRA plans, APIVR-Δ builds, IDG chronicles. FORGE and VIGIL are lateral specialists — consultable at any stage, not always in-line. CRYSTALIUM sits underneath all of them — the shared memory substrate every member writes handoff artifacts into and recalls from, bidirectionally; not a pipeline stage. Each Eidolon's own methodology now embeds the memory pipeline (recall at mission start → ingest its hand-off at trust tier T1 → trigger Dream consolidation at session end), so the team's memory is symbiotic by construction, not just by convention. Partial teams are first-class; bring just ATLAS to an audit, the full pipeline to a greenfield, or any slice that fits your project. See [`methodology/composition.md#partial-team-deployment`](methodology/composition.md#partial-team-deployment) for the full matrix and common configurations.

<details>
<summary>Canonical pipeline</summary>

```
ATLAS ───▶ SPECTRA ───▶ APIVR-Δ ───▶ IDG
  scout      plan         build        chronicle
             ▲              │ ▲
             │              │ │
           FORGE ◀─── (ambiguity, trade-offs, novel problems)
                            │ │
                          VIGIL ◀─── (failure resisted repair; forensic attribution)

  ╞══════════════════ CRYSTALIUM ══════════════════╡
   shared memory substrate — every member commits handoff
   artifacts and recalls them (bidirectional, not a stage)
```

</details>

Handoffs between members are structured artifacts written to disk — not free-form messages. See [`methodology/composition.md`](methodology/composition.md) for the handoff contract table and invariants.

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
eidolons init                    # interactive — choose members and preset
eidolons add forge               # add a single member later
eidolons sync                    # reconcile installed members to eidolons.yaml
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

To upgrade installed Eidolons (ATLAS, SPECTRA, etc.), use `eidolons upgrade` (no `self`) — see the CLI reference.

**MCP server scaffold (Atlas-ACI).** If you use the Atlas-ACI code-graph MCP server alongside ATLAS, run the nexus scaffold step once per project before starting the MCP server. It writes a per-project `.mcp.json` with the correct bind-mount paths and pre-creates `.atlas/memex/` so the sqlite codegraph DB has a writable host-side surface — skipping this step is the most common cause of `sqlite3.OperationalError: unable to open database file` on fresh clones.

```bash
eidolons mcp atlas-aci [--force] [--image-digest <sha256>]
```

If the image isn't on your host yet, run `eidolons mcp atlas-aci pull` first; the generator refuses to write `.mcp.json` until the image is loadable. Use `--skip-image-check` only in CI where the image is loaded after scaffolding. If `eidolons atlas aci wire` ever fails with the in-container index error, run `eidolons doctor` to diagnose; the most common cause is a missing or unwritable `.atlas/memex/` directory.

Note that `atlas-aci` is an external Python MCP package (a tool Eidolons consume); it is not an Eidolon and does not appear in `roster/index.yaml`. The `atlas` Eidolon (scout methodology) and the `atlas-aci` MCP server are distinct — see [`docs/architecture.md`](docs/architecture.md) for the boundary.

Commit `eidolons.lock` alongside `eidolons.yaml` — the lockfile pins resolved versions and integrity checksums (`commit`, `tree`, `archive_sha256`, `manifest_sha256`) for reproducible, tamper-evident installs. For the full flow, read [`docs/getting-started.md`](docs/getting-started.md).

---

## Verified releases

Every shipped Eidolon publishes attestation-backed releases through a canonical workflow ([`eidolon-release-template.yml`](.github/workflows/eidolon-release-template.yml)) hosted in this nexus. Each release records its commit, tree, and archive SHA-256 into `roster/index.yaml` via [`Roster Intake`](.github/workflows/roster-intake.yml), with GitHub artifact attestations bound to the canonical signer workflow.

`eidolons sync` and `eidolons verify` enforce that contract on the consumer side. Under the default `integrity.enforcement: strict` posture, any installed Eidolon whose commit/tree/archive checksum drifts from the roster's signed metadata aborts with exit 1 — same gate `Roster Health` runs nightly against every shipped Eidolon. Read the trust model end-to-end at [`docs/release-integrity.md`](docs/release-integrity.md).

**Nexus releases** use the same commit/tree/archive-SHA-256 model. Each `eidolons upgrade self` re-verifies the downloaded nexus against the `nexus.versions.releases.<v>` block in `roster/index.yaml` before swapping it in. The release workflow ([`.github/workflows/release-nexus.yml`](.github/workflows/release-nexus.yml)) produces these artefacts automatically on each `vX.Y.Z` tag.

**Auto-merge** of routine roster bumps. Roster bumps that pass attestation verification + required checks now auto-merge once Roster Intake opens the PR (via `gh pr merge --auto --squash`). First-shipped Eidolon transitions are held as DRAFT for manual review. Bad merges revert with `git revert <merge-sha>`; the next nightly `roster-health` re-validates. See `docs/release-integrity.md` § "Auto-merge of routine roster bumps".

---

## What's in this repo

| Area | What it contains |
|------|------------------|
| [`roster/`](roster/) | Machine-readable registry of every Eidolon, their versions, repos, handoff contracts |
| [`methodology/`](methodology/) | Aggregated [design principles](methodology/prime-directives.md), [composition contracts](methodology/composition.md), vocabulary |
| [`research/`](research/) | Papers, citations, production patterns, scientific backing |
| [`cli/`](cli/) | The `eidolons` command-line tool — installs and orchestrates the team |
| [`schemas/`](schemas/) | JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries |
| [`docs/`](docs/) | Getting started, architecture, CLI reference |
| [`examples/`](examples/) | Worked examples: greenfield, brownfield, solo-member, partial-team |

---

## Why a nexus

Each Eidolon is independently installable and independently versioned — that's a hard design invariant. The nexus exists because:

1. **Discovery.** Without a roster, nobody knows which Eidolons exist or how they relate.
2. **Composition.** The team is more than the sum of its members. Handoff contracts, pipeline conventions, and partial-team deployment patterns live here, not in any individual Eidolon's repo.
3. **Research.** The scientific backing for the whole program — papers, production precedents, evidence-to-design mappings — is a shared asset. Duplicating it across seven repos is wasteful and drifts.
4. **Installation orchestration.** A single `eidolons add atlas,spectra,apivr` is worth fifty lines of documentation explaining how to clone three repos and run three installers.
5. **Supply-chain integrity.** The release-integrity contract is a *shared* asset: one canonical signing workflow ([`eidolon-release-template.yml`](.github/workflows/eidolon-release-template.yml)) every Eidolon adopts, one ingestion path ([`Roster Intake`](.github/workflows/roster-intake.yml)) that verifies attestations, one consumer-side gate (`eidolons verify`) that enforces them. Seven independent repos with seven independent signing schemes would defeat the trust model.

Each Eidolon remains a first-class repo. This nexus is a coordinator, not an owner. The four-layer architecture (install standard → Eidolon repos → this nexus → consumer project) is documented in [`docs/architecture.md`](docs/architecture.md).

---

<!-- Curated highlights from CHANGELOG.md "Unreleased". Refresh on every release. -->
## Recently shipped

- **CRYSTALIUM v1.2.0 mainframe + team-wide memory pipelines (all six Eidolons).** Promotes CRYSTALIUM from an opt-in MCP to the always-on shared-memory substrate: a `CRYSTALIUM_CALLER_TIER=T1` unlock so Eidolon writes reach the semantic/execution layers (Dream consolidation included), ECL `ingest` as the symbiotic write-spine, a multi-MCP-safe `oci-image` install driver (jq-merge, no clobber), and an expanded always-loaded cortex memory mandate + `methodology/cortex/memory-protocol.md` deep table. Each Eidolon's methodology then embeds `recall → ingest(T1) → session_end` with a standalone fallback — **atlas 1.9.0, spectra 4.6.0, apivr 3.4.0, idg 1.5.0, forge 1.6.0, vigil 1.4.0** (APIVR-Δ also reconciles its local Reflexion store as CRYSTALIUM-primary / local-fallback). Campaign scope: [`.spectra/plans/2026-06-01-crystalium-per-eidolon-pipeline-campaign.md`](.spectra/plans/2026-06-01-crystalium-per-eidolon-pipeline-campaign.md); nexus PRs #210–#218.
- **ATLAS v1.8.0 — `atlas aci install` → `wire`, positional runtime, digest-aware index.** Hard rename of the `install` action to `wire` (no alias); `--container`/`--runtime` flags collapsed into a positional after the action (`eidolons atlas aci wire [docker|podman]`, absent = host mode). The `index` subcommand now probes `docker image inspect @sha256:…` first so images pulled via `eidolons mcp atlas-aci pull` (digest-pinned, no tag) are detected; the stale hardcoded `ATLAS_VERSION="1.4.2"` constant is substituted from `install.sh`'s `EIDOLON_VERSION` at install time. Exit-5 error text distinguishes "no image" from "image present but version mismatch" and points users at `wire` or `mcp atlas-aci pull` rather than the removed `install`. Decision rubrics: [`.spectra/plans/2026-05-27-atlas-aci-ux-fixes-spec.md`](.spectra/plans/2026-05-27-atlas-aci-ux-fixes-spec.md) (upstream PR `Rynaro/ATLAS#35`; nexus PRs #198, #199).
- **Three-layer methodology integrity guarantee (v1.11.0–v1.13.4).** Layer 1: `eidolons doctor --deep` performs six static gates (D1–D6) over installed members' manifests. Layer 2: `eidolons verify-release` re-derives each Eidolon's install tree and SHA-256 diffs against the cached version to catch tampering or drift. Layer 3: `eidolons canary` prints a behavioral mission prompt and validates saved LLM responses against a small DSL (`MUST`/`SHOULD`, structural assertions). See [`docs/cli-reference.md`](docs/cli-reference.md) and [`CHANGELOG.md`](CHANGELOG.md).
- **Unified MCP store — catalogue-driven tool wiring (v1.9.0).** `eidolons mcp {list,show,install,refresh,uninstall,upgrade,health}` replaces divergent subcommands. New `roster/mcps.yaml` catalogue + `eidolons.mcp.lock` lockfile. Installing an MCP grants its tool surface to relevant Eidolons automatically (e.g. `eidolons mcp install junction` enables `mcp__junction__*` tools for all members). See [`docs/mcp.md`](docs/mcp.md) and [`CHANGELOG.md`](CHANGELOG.md).
- **Install-layout normalization v1.4 across EIIS + all six Eidolons.** Strict canonical inventory whitelist; host-vendor agent ref contract; `ECL_VERSION` universal MUST. EIIS v1.4.0 + ATLAS/SPECTRA/APIVR-Δ/IDG/FORGE/VIGIL all on v1.4 releases. Closes 13 cross-cutting gaps surfaced by install-normalization rounds. See [`CHANGELOG.md`](CHANGELOG.md) and [`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis).
- **`eidolons init` AGENTS-precedence + multi-pointer dispatch (v1.7.0–v1.8.1).** Vendor-file pointer derivation is now deterministic; init detects `AGENTS.md`, `shared_dispatch=true`, or `codex` in wired hosts and routes the dispatch-pointer accordingly. Universal marker-guard hoists installer-written vendor content into `EIDOLONS.md`. `--multi-pointer` defaults ON (v1.8.1); Doctor Check 14 surfaces drift. See [`docs/cli-reference.md`](docs/cli-reference.md).
- **Auto-refresh nexus cache + standard semver caret ranges (v1.10.0).** `eidolons sync` now calls `nexus_refresh()` before reading the roster, and resolves `^X.Y.Z` constraints via standard semver ranges (was: naive prefix-strip). New Eidolon versions land in consumer projects on the next `sync` with no manifest edit. See [`CHANGELOG.md`](CHANGELOG.md).
- **Junction harness v0.2.0 shipped — two-phase orchestration.** Host-as-planner / harness-as-executor model with ECL envelopes, sidecar trace, ten closed performatives. MCP-sampling-based ReasoningStep for FORGE integration. Tooling via `eidolons mcp install junction`. See [`Rynaro/Junction`](https://github.com/Rynaro/Junction).
- **Nexus CLI self-versioning + atomic rollback (legacy evergreen).** `eidolons --version` reports version, commit SHA, install date, and source ref. `eidolons upgrade self` is atomic and rollback-safe: verifies integrity, runs a smoke test, renames atomically. Fallback to `eidolons upgrade self --rollback` to revert. See [`docs/getting-started.md`](docs/getting-started.md).

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
