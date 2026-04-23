# Eidolons

> A personal, portable team of AI agents. Each is a named specialist with its own methodology, identity, and boundaries. They work alone when the task is sharp; they work in harmony when the task is big; they travel together, from project to project, codebase to codebase, host to host.

This is the **nexus** — the canonical place where the team is defined, inventoried, researched, and composed. It is not itself an Eidolon. It is the home they travel from.

---

## What's here

| Area | What it contains |
|------|------------------|
| [`roster/`](roster/) | Machine-readable registry of every Eidolon, their versions, repos, handoff contracts |
| [`methodology/`](methodology/) | Aggregated design principles, prime directives, composition contracts, vocabulary |
| [`research/`](research/) | Papers, citations, production patterns, scientific backing |
| [`cli/`](cli/) | The `eidolons` command-line tool — installs and orchestrates the team |
| [`schemas/`](schemas/) | JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries |
| [`docs/`](docs/) | Getting started, architecture, CLI reference |
| [`examples/`](examples/) | Worked examples: greenfield, brownfield, solo-member, partial-team |

---

## The roster

| Eidolon | Role | Methodology | Repo | Status |
|---------|------|-------------|------|--------|
| **ATLAS** | Explorer / Scout | `A→T→L→A→S` | [Rynaro/ATLAS](https://github.com/Rynaro/ATLAS) | shipped |
| **SPECTRA** | Planner | `S→P→E→C→T→R→A` | [Rynaro/SPECTRA](https://github.com/Rynaro/SPECTRA) | shipped |
| **APIVR-Δ** | Coder | `A→P→I→V→Δ/R` | [Rynaro/APIVR-Delta](https://github.com/Rynaro/APIVR-Delta) | shipped |
| **IDG** | Scriber / Chronicler | `I→D→G` | [Rynaro/IDG](https://github.com/Rynaro/IDG) | shipped |
| **FORGE** | Reasoner | `F→O→R→G→E` | [Rynaro/FORGE](https://github.com/Rynaro/FORGE) | shipped |

See [`methodology/composition.md`](methodology/composition.md) for the canonical pipeline and handoff contracts.

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
eidolons init                              # interactive
eidolons init --preset standard            # non-interactive
eidolons add forge                         # add a single member later
eidolons sync                              # reconcile to eidolons.yaml
eidolons doctor                            # health-check installs + host wiring
```

For the full flow, read [`docs/getting-started.md`](docs/getting-started.md).

---

## Why a nexus

Each Eidolon is independently installable and independently versioned — that's a hard design invariant. The nexus exists because:

1. **Discovery.** Without a roster, nobody knows which Eidolons exist or how they relate.
2. **Composition.** The team is more than the sum of its members. Handoff contracts, pipeline conventions, and partial-team deployment patterns live here, not in any individual Eidolon's repo.
3. **Research.** The scientific backing for the whole program — papers, production precedents, evidence-to-design mappings — is a shared asset. Duplicating it across five repos is wasteful and drifts.
4. **Installation orchestration.** A single `eidolons add atlas,spectra,apivr` is worth fifty lines of documentation explaining how to clone three repos and run three installers.

Each Eidolon remains a first-class repo. This nexus is a coordinator, not an owner.

---

## Relationship to EIIS

The **Eidolons Individual Install Standard** (`Rynaro/eidolons-eiis`) defines the contract every Eidolon repo satisfies — file layout, `install.sh` interface, manifest schema.

This nexus (`Rynaro/eidolons`) *depends* on EIIS. Every Eidolon listed in [`roster/index.yaml`](roster/index.yaml) must be EIIS-conformant; the CLI refuses to install non-conformant members.

They version independently. EIIS v1.x is the contract; eidolons v1.x is the orchestrator.

---

## License

Apache-2.0. See [LICENSE](LICENSE).
