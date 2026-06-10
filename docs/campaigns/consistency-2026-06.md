# Campaign: Version-Stamp Hygiene + Canonical Skill Template (2026-06-10)

Audit basis: 8 parallel repo audits + nexus pipeline audit + official Agent Skills spec research + ecosystem research + FORGE deliberation (D1–D4). Repos live as siblings at `../<NAME>`.

## Root cause (versions)

`eidolon-release-template.yml` tags whatever version is dispatched without verifying any in-tree stamp. Every repo accumulated stale stamps (SPECTRA 41, VIGIL 32, FORGE 30, IDG 29, APIVR ~35, Vivi ~30 inherited 3.x, ATLAS 9, Kupo 2). Nexus `EIDOLONS.md` member blocks are GENERATED from each member's `install.sh` `EIDOLON_VERSION` (hand-editing them is futile — fix upstream, then `eidolons sync`). Nexus README member table is hand-maintained and 2 versions stale.

## Decisions (FORGE-deliberated)

- **D1 (0.82): strip versions from doc/template footers** — keep `*NAME — Title*`. Version lives ONLY in 5 canonical homes: `install.sh` `EIDOLON_VERSION` (SSOT), `agent.md` + `AGENTS.md` frontmatter `version:`, `SPEC.md` header, README (one place), `CHANGELOG.md` entries.
- **D2 (0.78): spec-pure skill frontmatter** — top-level only `name`, `description` (+ `allowed-tools` where present today); `methodology`/`phase` move under `metadata:`; **drop `methodology_version` from skills entirely** (nothing reads it; it is a drift surface). `when_to_use` content folds into the description ("Use when …") and a `## When to use` body section.
- **D3 (0.74 + reversal exercised): ONE PR per repo** combining stamp sweep + skill normalization + functional fixes, released as ONE MINOR bump. (Portability spike passed: `wire_skill` strips frontmatter and re-injects extracted description for copilot/cursor; nexus reads only `description:`.)
- **D4 (0.80): nexus release-template stamp gate lands FIRST** + a shared `scripts/check-eidolon-stamps.sh` in the nexus (single copy, runbook-referenced; repos do NOT fork it).

## Canonical SKILL template (target 2 of the user request)

```markdown
---
name: <eidolon>-<skill>                  # kebab-case, matches .claude/skills/<name>/ vendor dir
description: <ONE physical line. Third person. WHAT it does + "Use when <triggers, multiple phrasings>." Optionally "Do NOT use for <adjacent cases>." ≤1024 chars.>
allowed-tools: <keep only where present today>
metadata:
  methodology: <NAME>
  phase: <phase-label, where applicable>
---

# <Skill Title>

<1–2 sentence purpose.>

## When to use
<trigger/load conditions + negative triggers — preserve existing trigger prose>

<EXISTING BODY SECTIONS PRESERVED VERBATIM — protocol, contracts, tables, P0s, exit gates.
Only structural normalization is allowed: ensure one H1 at top, H2 sections, no version strings.>

*<NAME> — <Skill Title>*        (footer optional, UNVERSIONED)
```

Hard rules:
1. **description is ONE physical line** (`extract_fm_field` is a line-matching awk; folded `>` blocks break copilot/cursor wiring).
2. **Methodology content is preserved verbatim** — this is a format migration, never a rewrite. Skill discovery names (`<eidolon>-<skill>`) do not change.
3. No release-version strings anywhere in a skill body. Markdown trace-event examples use the placeholder form `<name>@<version>` (e.g. `"to":"spectra@<version>"`).
4. Body stays < 500 lines where already under; do NOT split/restructure bodies in this campaign.
5. Tests asserting old frontmatter shapes are migrated in the same PR (FORGE has a test asserting NO frontmatter — invert it; SPECTRA/Vivi tests grep `methodology_version` — re-target to `name:`/`description:` presence).

## Stamp policy (target 1)

Per repo, target version = next MINOR. Sweep rules:
- `install.sh` `EIDOLON_VERSION` → target. agent.md/AGENTS.md frontmatter `version:` → target. SPEC.md header → target. README single version mention/badge → target. CHANGELOG: backfill missing released entries (promote stale `[Unreleased]` blocks to the version that actually shipped them) + add `[<target>]` entry for this PR.
- `methodology_version` in agent.md/AGENTS.md: keep each repo's documented semantics (ATLAS & VIGIL freeze at "1.0" by documented design; repos that track release set it to target).
- Doc/template/host-file footers: strip the version (D1).
- JSON envelope templates/fixtures + test helper defaults + schema `$id` URLs → target version (real values, schema-safe; the gate + check script watch them).
- examples/install.manifest.json (or evals/fixtures/): version → target; add missing skill entries (EIIS I5).
- **OUT OF SCOPE (ecosystem-coordinated V3 item, do NOT touch):** every ECL 1.0-vs-2.0 item — `ECL_VERSION_VAL` in install.sh, `ECL_VERSION` files, "targets ECL v1.0" prose, ECL section headings, Kupo's vendored envelope-schema pattern, envelope_version values. Leave verbatim.

## Per-repo briefs (branch `fix/consistency-<target>` off origin/main; repos are DIRTY on feature branches — use a fresh `git worktree`)

| Repo | Target | Notable beyond the generic sweep |
|---|---|---|
| ATLAS | 1.12.0 | CHANGELOG promote [Unreleased]→[1.11.0] + add [1.12.0]; examples/install.manifest.json 1.7.2→target + add scatter/rescout/verify-incoming entries; SPEC.md:405 ECL prose = OUT OF SCOPE; skills already near-canonical: move methodology/phase under metadata, drop methodology_version, fold when_to_use into description + "## When to use", add missing H1s (scatter, verify-incoming) |
| SPECTRA | 4.9.0 | README badge says v4.2 + footer 4.7.0; catalog.md examples spectra_version 4.2.0; templates/spec.envelope.json 4.3.0; tools/lib/core.sh SPECTRA_VERSION="4.2.8"; tools/assets/methodology/* stranded at 4.2.x (sync from docs/spectra-methodology or stamp-strip); tests/verify-incoming.bats:56 greps methodology_version "4.7" — retarget; CHANGELOG add [4.8.0] + [4.9.0] |
| APIVR-Delta | 3.7.0 | SUPERSEDES open PR #22 (covered only SPEC/AGENTS/install.sh/install.bats; close it with a comment after the new PR merges). Full sweep incl. README title "v3.0", agent.md "Cycle (v3.0)", templates+inbound fixtures 3.1.0, helpers.bash default 3.1.0, schemas $id v3.1.0, CHANGELOG backfill [3.6.0]. CONTENT FIX in scope: SPEC.md §8 + CLAUDE.md + skills/context-engineering.md still describe verify-incoming as "opt-in, warn-only" — actual skill is BLOCKING; fix the posture prose (do not touch ECL version numbers in same sentences) |
| Vivi | 1.1.0 | **FUNCTIONAL BUG: install.sh never wires skills/loop-native.md** — add wire_skill/add_fw/add_skill + manifest entries (EIIS I5). Inherited 3.x stamps: agent.md "Cycle (v0.1)", AGENTS.md "Cycle (v3.0)", skills/methodology.md H1+footer "v3.0", verify-incoming "vivi@3.4" traces, schemas $id v3.1.0, templates/fixtures 3.1.0, helpers.bash 3.1.0, examples manifest 3.3.0, tests greping 3.4/3.1.0, docs/PAPER.md "Vivi v3.0" identity |
| IDG | 1.8.0 | Footers span 1.0.0/1.6.0; templates' provenance blocks hardcode "Scribe version: 1.0.0" → make `<version>` placeholder (they are output templates) or strip; skills/composition.md:51 "IDG v1.2.0 compatibility range" GAP-template; hosts/claude-code.md example 1.1.0; verify-incoming "idg@1.1" traces → `idg@<version>`; evals/fixtures manifest 1.4.0 + missing 2 skills; CHANGELOG promote [Unreleased]→[1.7.0] + add [1.8.0]. Skills have NO frontmatter → add canonical frontmatter (names: idg-composition, idg-verification, idg-section-parallel, idg-verify-incoming — match current vendor dirs) |
| FORGE | 1.9.0 | install.sh:5 comment v1.6.0; root SKILL.md footer; 5 templates ×2 stamps each; schemas/reasoning-report.envelope.json from.version 1.3.0; committed .claude/agents/forge.md stale 1.5.0 (regenerate/update); examples manifest 1.5.0 + missing 2 skills; CHANGELOG promote→[1.8.0] + add [1.9.0]. Skills have NO frontmatter + bats test ASSERTS no frontmatter → add canonical frontmatter (forge-framing, forge-deliberation, forge-verification, forge-self-consistency, forge-verify-incoming) and INVERT the test |
| VIGIL | 1.6.0 | install.sh 1.4.0 vs agent.md 1.4.1 split; footers span 1.0.1/1.1.0/1.2.0/1.4.1 across README/CLAUDE/hosts/templates; duplicate footer verified-patch.md; TWO [Unreleased] blocks in CHANGELOG (promote top→[1.5.0], annotate orphan); examples manifest 1.3.0 + missing eiis_version/comm/verify-incoming entries; traces vigil@1.1.0/vigil@1.0 → `vigil@<version>`. Skills rich-frontmatter → metadata: migration, drop methodology_version (keep agent.md methodology_version "1.0" frozen-by-design) |
| Kupo | 1.1.0 | README footer "v0.1.0 — in_construction"; CHANGELOG add [1.0.0] backfill + [1.1.0]; traces kupo@1.0 → `kupo@<version>`; schemas/install.manifest.v1.json $id v1.0.0 → v1.4 EIIS URL (EIIS-version housekeeping, allowed; the ECL envelope-schema pattern stays untouched). Skills have NO frontmatter → add canonical (kupo-keep-or-kick, kupo-patch-verify, kupo-verify-incoming) |

Generic per-repo executor checklist: branch in fresh worktree → stamp sweep (grep `[0-9]\+\.[0-9]\+\.[0-9]\+` exhaustively; classify vs policy; skip ECL items) → skill normalization → migrate tests → `bats tests/` green → `shellcheck -S error install.sh` → commit (Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>; never override git email) → push → `gh pr create`.

## Nexus PR (lands FIRST)

1. `eidolon-release-template.yml`: pre-tag gate step — assert `install.sh` contains `EIDOLON_VERSION="<inputs.version>"` (tolerate `readonly` prefix) AND `CHANGELOG.md` contains `## [<inputs.version>]`. Clear failure messages. bash 3.2-safe, yq-validate the workflow after editing (block-scalar trap).
2. `scripts/check-eidolon-stamps.sh <eidolon-dir> <version>`: same checks + agent.md/AGENTS.md/SPEC.md frontmatter/header greps; runnable against any member checkout pre-dispatch.
3. README member table → atlas 1.11.0, spectra 4.8.0, apivr 3.6.0, idg 1.7.0, forge 1.8.0, vigil 1.5.0 (current truth; bumped again at intake).
4. (Defer: doctor check for EIDOLONS.md blocks vs lock — recorded as follow-up.)

## Release & intake (after PRs merge)

Per repo, SEQUENTIALLY: dispatch `Release <NAME>` with target version (never hand-tag) → manually merge intake/roster PRs (auto-merge silently fails) → roster `versions.latest`/`pins.stable` + `methodology.version` refresh (spectra roster methodology.version "4.2" → align with repo semantics). Then in any consumer (incl. nexus repo): `eidolons upgrade`/`sync` to refresh `.eidolons/`, `.claude/skills/`, and the EIDOLONS.md generated blocks. Intake wget-yq flake: just re-dispatch.

## Deferred (recorded, not in this campaign)

- ECL spec-v1.0-vs-wire-2.0 naming — ecosystem-coordinated.
- doctor gate: EIDOLONS.md block version vs eidolons.lock; agent.md version vs lock.
- roster-health check that `methodology.version` is fresh.
- tests/aci.bats atlas-aci pinned-tag staleness (separate tool track).

---

## Outcome (postscript, 2026-06-10)

Shipped end-to-end the same day. Nexus PR #311 (stamp gate + `scripts/check-eidolon-stamps.sh` + README refresh) and all 8 member PRs merged; releases cut through the new gate: ATLAS 1.12.0, SPECTRA 4.9.0, APIVR-Δ 3.7.0, Vivi 1.1.0 (+1.1.1 clearing the doctor D11 advisory with SPEC invariant I-11), IDG 1.8.0, FORGE 1.9.0, VIGIL 1.6.0, Kupo 1.1.0; intakes #312–#319, #322. Nexus v1.33.0 cut (#320) with roster `methodology.version` refreshed (SPECTRA 4.9, IDG 1.8, FORGE 1.9).

Incident: VIGIL's first v1.6.0 dispatch failed EIIS M14 — its vendored `install.manifest.v1.json` schema (`additionalProperties: false`) rejected the `eiis_version`/`comm` keys its own installer emits; exposed when the example fixture was made truthful. Fixed in VIGIL #19. Lesson recorded under Deferred: vendored-EIIS-schema-vs-installer pairing is unverified ecosystem-wide.
