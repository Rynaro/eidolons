# Kupo eval — results (P5 ship-gate, first pass)

> Instrument: `evals/kupo-keep-suite.yaml` (7 KEEP-cohort tasks) · `cli/tests/kupo_eval.bats`.
> Run: 2026-06-08. Status: **preliminary — Kupo stays `in_construction`.**

## 1. Orchestration proof (smoke mode — deterministic, gold_fix)
`eidolons eval swe --suite-file evals/kupo-keep-suite.yaml` → **7/7 resolved, resolved_rate=1.0.**
Proves the harness end-to-end (setup → red → fuzzy-apply → green → diff-not-apply) over Kupo-shaped tasks. Not a capability number (gold fixes, no model).

## 2. Behavioral run (the real number — haiku model + the real applier)
7 haiku-tier agents, one per task, each running the full K→U→P→O loop: gather → emit a `kupo-edit-proposal` → apply via **`eidolons sandbox apply`** (the harness-owned fuzzy applier) → external verifier. k=1.

| Task (KEEP class) | Result |
|---|---|
| keep-import-path-fix (import/path) | ✅ RESOLVED |
| keep-rename-call-consistency (rename) | ✅ RESOLVED |
| keep-lockfile-pin-bump (lockfile) | ❌ UNRESOLVED |
| keep-config-key-edit (config) | ✅ RESOLVED |
| keep-one-line-arithmetic (one-line fix) | ✅ RESOLVED |
| keep-grep-replace-multi (grep-replace) | ✅ RESOLVED |
| keep-json-syntax-fix (lint/syntax) | ✅ RESOLVED |

**resolved-rate = 6/7 = 0.857** — **>> the ~0.20 Haiku→Opus cost-ratio gate.** On this cohort Kupo is **provisionally net-additive** (the additive-proof holds by a wide margin).

## 3. The one miss — a real, fixable finding (NOT task difficulty)
The lockfile-bump agent **hallucinated that `eidolons sandbox apply` does not exist** ("only check/run/loop in v1.28.1") and **abstained** on a trivially-in-scope task — despite 6 sibling agents using that exact applier successfully and it carrying 8 passing unit tests (`patch_applier.bats`). This is a textbook small-model failure the frontier research predicted (incorrect abstention / distrusting the harness), the inverse of "models almost never abstain."

**Fix (Kupo repo, next):** firm up `agent.md` / `patch-verify.md` to assert *the harness applier is real — invoke `eidolons sandbox apply`; never abandon a KEEP task because you doubt a tool exists; if an apply fails, retry with tighter anchors, don't ESCALATE on a tool-existence assumption.* Ship as Kupo v0.1.1.

## 4. Honest scope / what this is NOT
- **N=7, k=1, synthetic tasks I authored** (not held-out). This is a *preliminary* behavioral signal, not a benchmark. Per the research, thresholds must be re-derived on a real task distribution before the shipped flip.
- No `pass^k` yet (k=1) — flakiness unmeasured.

## 5. Verdict & path to `shipped`
**Strongly positive preliminary signal (0.857 ≫ 0.20), but stay `in_construction`.** To flip → `shipped` / v1.0.0:
1. Land the `agent.md` applier-trust fix (§3) → Kupo v0.1.1, re-pin roster.
2. Expand the cohort (more KEEP classes, real/held-out instances) + run **k≥3** for pass^k.
3. Re-confirm resolved-rate ≥ cost-ratio on the larger cohort → flip status, contribute canonical `contracts/*.yaml` to `eidolons-ecl`.

This is the first time a roster Eidolon has a *behavioral* (not documentary) additive number — exactly the "measure before trust" gate the frontier dossier demanded.
