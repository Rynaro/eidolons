# Working Vocabulary

> Terms used across the Eidolons team. Defined once here, used consistently everywhere.

---

## The team

| Term | Meaning |
|------|---------|
| **Eidolon** | A single-responsibility AI agent in the team, with entry point, skills, templates, rationale, installer |
| **The Eidolons / the team** | The composed roster of all current members |
| **Member** | Synonym for Eidolon; emphasizes the personal / team framing |
| **Roster** | The canonical registry of all Eidolons — lives in `roster/index.yaml` |
| **Capability class** | Role taxonomy: Scout, Planner, Coder, Scriber, Reasoner (and future additions) |

---

## Per-Eidolon architecture

| Term | Meaning |
|------|---------|
| **Methodology** | The named phase cycle belonging to a specific Eidolon (ATLAS, SPECTRA, APIVR-Δ, IDG) |
| **Cycle** | The Eidolon's phase sequence (e.g. `A→T→L→A→S`) |
| **Entry point** | The always-loaded `agent.md` with identity + cycle + rules (~900 tokens) |
| **Skill** | On-demand Markdown with phase-specific methodology (`skills/<phase>/SKILL.md`) |
| **Template** | On-demand Markdown with an output skeleton (`templates/<artifact>.md`) |
| **Working set** | Total tokens loaded at any moment: entry + active skill + active template |
| **Gate** | A structured verification step with explicit pass/fail criteria |
| **P0 rules** | Non-negotiable rules in the entry point — never overridden |

---

## Composition

| Term | Meaning |
|------|---------|
| **Handoff** | A structured artifact passed between Eidolons in a pipeline |
| **Handoff contract** | The schema + content requirements for a specific handoff (e.g. ATLAS → SPECTRA) |
| **Pipeline** | The canonical left-to-right sequence: ATLAS → SPECTRA → APIVR-Δ → IDG |
| **Consultation** | Lateral handoff to FORGE for reasoning, not part of the linear pipeline |
| **Partial-team deployment** | Installing a subset of members (e.g. just ATLAS + IDG) |
| **Preset** | A named bundle of members (`minimal`, `pipeline`, `full`, etc.) |
| **Standalone** | An Eidolon that works without any teammates installed |

---

## Installation & hosting

| Term | Meaning |
|------|---------|
| **Nexus** | This repo (`Rynaro/eidolons`). The team's coordination point — roster, CLI, methodology, research |
| **EIIS** | Eidolons Individual Install Standard. Contract every Eidolon repo satisfies |
| **Consumer project** | The project a user is installing Eidolons *into* |
| **Host** | The environment an Eidolon runs in: Claude Code, Cursor, Copilot, OpenCode, raw API |
| **Host wiring** | Per-host dispatch files (`CLAUDE.md`, `.cursor/rules/*`, etc.) that make the Eidolon discoverable |
| **Manifest** | `eidolons.yaml` — per-project declaration of which members you want |
| **Lock** | `eidolons.lock` — resolved exact versions of installed members |
| **Install manifest** | `install.manifest.json` — per-Eidolon record of what was installed in a consumer project |

---

## Output quality

| Term | Meaning |
|------|---------|
| **Provenance** | Metadata trail from output claim → source artifact |
| **Evidence anchor** | A citation format pinning a claim to its source (e.g. `path:line_start-line_end + H\|M\|L`) |
| **Confidence tier** | High / Medium / Low marker on evidence-anchored claims |
| **Structural marker** | Inline annotation: `[DECISION]`, `[ACTION]`, `[DISPUTED]`, `[GAP]`, `[FINDING-NNN]`, `[ROOT-CAUSE]`, `[SYMPTOM]`, `[BLOCKED]` |
| **Gated output** | Output that has passed a structured verification step |
| **Bounded revision** | A revision budget with a fixed upper limit (e.g. 1 pass for prose, up to 3 for code) |

---

## Design & evidence

| Term | Meaning |
|------|---------|
| **Mechanical invariant** | A rule enforced by the harness (tool allowlist, path guard) rather than by prompt |
| **Layered loading** | The progressive-disclosure architecture where entry → skill → template load on demand |
| **Canary mission** | Evaluation scenario used to verify an Eidolon still works after changes |
| **Design rationale** | The traceability document mapping research findings to design decisions |
| **Prime directive** | One of the ten non-negotiables (D1–D10) |

---

## Versioning

| Term | Meaning |
|------|---------|
| **Methodology version** | SemVer of the *methodology* itself (e.g. APIVR-Δ v3.0 refers to the methodology, not the repo tag) |
| **Eidolon version** | SemVer of the *package* — may bump without a methodology change (e.g. doc fixes) |
| **EIIS version** | SemVer of the install standard — versioned independently from any Eidolon |
| **Registry version** | Version of the roster schema (`roster/index.yaml`) |
| **Manifest version** | Version of `eidolons.yaml` schema |

---

## When in doubt

Use the term from this vocabulary. If a new concept needs a term, propose it here first — the vocabulary is updated, then the docs that use it are updated.

Consistent vocabulary is a first-class deliverable. Inconsistent terms across five repos create real cognitive load for anyone reading across them.
