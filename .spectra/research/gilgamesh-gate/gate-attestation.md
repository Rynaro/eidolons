# Gate Attestation — ESL change `generalist-eidolon` (Gilgamesh) two-arm measurement gate

**Checker identity:** `gate-checker-opus-fresh` (fresh Opus context; independent).
**Date:** 2026-07-11.
**Repo:** `/home/rynaro/workspace/oss/agents/eidolons`.
**Gate record:** `.spectra/research/gilgamesh-gate/`.
**Authority:** This attestation is final for this gate. I audited mechanically and re-derived; I did not remediate.

---

## Maker ≠ Checker roll-call (AC-G05)

My identity `gate-checker-opus-fresh` is distinct from every maker/author in the record:

| Role | Identity | Distinct from me? |
|---|---|---|
| Spec maker | ramza | yes |
| Implementation maker | vivi | yes |
| Member builder | generalist-builder | yes |
| Gate author (grader/holdout) | gate-author-sonnet-fresh | yes |
| Labeler L1 | L1 | yes |
| Labeler L2 | L2 | yes |
| Adjudicator L3 | L3 | yes |
| Orchestrator | orchestrator | yes |

**AC-G05: PASS** — checker independence holds.

---

## §1 Freeze integrity — PASS (BLOCKING gate cleared)

- `sha256sum --check FREEZE.sha256` → **all OK**: `arm1-holdout.jsonl`, `arm2-corpus.jsonl`, `labeling-rubric.md`.
- `sha256sum --check LABELS-FREEZE.sha256` → **all OK**: `labels-final.jsonl`, `labels-L1.jsonl`, `labels-L2.jsonl`, `labels-L3-adjudication.jsonl`.
- `arm1-holdout.jsonl` hash re-checked directly = `9834732e…c90904` = frozen value. The FREEZE covers the missions **and** their `oracle_expected` blocks, so **no mission / oracle content changed across attempts 1→2→3**. Confirmed.
- Working-tree `M` markers on `arm1-results.jsonl` and `arm1-runs/**` are **expected**: these are measurement *outputs*, not frozen *inputs*. The freeze deliberately covers inputs (missions, corpus, rubric, labels) only.

**Ruling: no mismatch. Not blocking.**

---

## §2 Arm-2 (no-over-capture) — re-derived verdict: PASS

Corpus = 76 prompts: 30 strongly-matched + 20 near-threshold + 15 paraphrase + 11 p-class (sums to 76).

Router replay (`arm2-replay-official.jsonl`, 76 records) — **Gilgamesh fired 0 times across all 76 prompts** (41 empty selections, 35 specialist dispatches, zero `gilgamesh`). Recomputed per stratum:

| Stratum | n | Gilgamesh captures |
|---|---|---|
| strongly-matched | 30 | **0** (MUST=0 met) |
| near-threshold | 20 | **0** → 0.0% (bound 5%) |
| paraphrase | 15 | 0 |
| p-class | 11 | 0 |

- **Hard bar (MUST=0 over-capture on strongly-matched):** 0. **Met.**
- **Near-threshold non-inferiority:** 0/20 = 0.0% ≤ 5.0% bound. **Met.**

My recomputation reproduces `arm2-verdict.json` exactly. **Arm-2 = PASS.**

**Determinism / AC-G07 label-independence chain:**
- L1 and L2 independently labeled all 76 (`rubric_rule` cited on each). Recomputed **L1↔L2 agreement = 73/76** (matches the claim). The 3 disagreements are exactly `p-class-P3, P5, P7`.
- `labels-disagreements-for-L3.jsonl` lists those 3 with blind `candidate_1/candidate_2` (the L1/L2 labels) — **no reference to Gilgamesh's routing outcome**.
- L3 blind adjudication resolved all 3 with rubric-grounded reasoning (P3→vivi, P5→clarify, P7→generalist-fallthrough).
- `labels-final.jsonl` reconciles correctly: 73 records `provenance:"L1=L2"`, 3 records `provenance:"L3-adjudicated"` matching L3's decisions. (final differs from L1 on 2 ids — P3, P5 — because L3 happened to uphold L1's candidate on P7.)
- **Smoke (pre-freeze) vs official (post-freeze) replay: BYTE-IDENTICAL** — same SHA256 `51f4a674…e66b04` (`cmp` match). The router is mechanical and deterministic.

**AC-G07 intent ruling — SATISFIED.** The smoke replay predating the label freeze does **not** contaminate label independence, because: (a) labels are rubric-derived and blind (L1/L2 independent, L3 blind); (b) the measured outcome is deterministic and reproduced byte-identically after the freeze; and (c) the measured quantity — Gilgamesh fires — is **0**, so over-capture is 0 *independent of the labels*: no label tailoring could manufacture (or hide) a capture that never occurred. Best practice would freeze labels before generating even a smoke replay; the determinism + byte-identity fully mitigate the deviation for a v0.1 opt-in gate. **Noted as process hygiene, not a defect.**

---

## §3 Grader evolution v1→v4 — four fixes, all ACCEPT

Read `evals/oracle-check.sh` (all four fixes documented in-file) + `arm1-runs-attempt2-fail/REGRADE-V4-NOTE.md`. Ruling per fix on the standard: *mechanical, uniform, never-stricter, information-preserving* vs *leniency that lets missing/wrong information pass*.

1. **Anchor trailing annotation** (`resolve_anchor`: take leading whitespace-delimited token when anchor-shaped) — **ACCEPT.** Parameter-expansion mechanical; guarded (`case *:[0-9]*`) so annotation-free values split exactly as before; the anchor still must resolve to a real, non-empty line. Verified live: `arm1-12` `EIDOLONS.md:22 (…annotation…)` resolves; `arm1-07` did **not** get rescued (its bad target still failed).
2. **Anchor line-range** (`path:START-END` validated at START) — **ACCEPT** (minor caveat noted). Never-stricter (ranges previously hard-failed the numeric guard); a range is a legitimate resolvable citation. Caveat: only START is validated, not END — a theoretical leniency, but in every observed case START is a genuine line the agent identified. Verified: `arm1-07` `EVIDENCE-test_count: …bats:38-252`, START 38 = a real `@test` line, legitimately resolves.
3. **VERIFY value first-token** (first whitespace token must equal expected) — **ACCEPT.** The token must *exactly* equal the expected verdict; annotation is additive explanation. Verified **non-lenient in the failing direction**: `arm1-08` reported `VERIFY-selfcheck: fail (…)` → first token `fail` ≠ `pass` → **correctly FAILED**. A wrong verdict cannot pass.
4. **Folded mission-verbatim labels** (accept `LABEL:` and `LABEL (hint):` equally) — **ACCEPT.** Regex-mechanical, uniform. The parenthetical is a value-*shape* hint copied verbatim from the frozen mission enumeration (`(path:line)`, `(pass/fail)`) carrying **zero answer content**; the real value follows the colon and is compared exactly. A wrong answer cannot hide in the parenthetical (empty post-colon → missing → FAIL). Verified in `arm1-01` / `arm1-12`.

All four are **never-stricter** (they can only turn some FAILs into PASSes) — yet attempt 2 re-graded under v4 was **still FAIL** (66.7/53.3/53.3), and attempt 3 under v4 is **FAIL** (53.3/60.0/53.3). **The leniency does not rescue the gate; it makes the FAIL more robust.** No fix rejected → no stricter re-grade required.

---

## §4 Attempt handling — re-derived

**Attempt 1 — DISCARDED (justified).** `arm1-runs-attempt1-discarded/`: all 45 `meta.jsonl` records `exit=1` (`secs≈7–8`); every preserved report contains only the provider string *"You've hit your monthly spend limit…"*. A billing outage is not a capability measurement in either direction. Discard is honest and correct.

**Attempt 2 — FAIL (re-derived).** Under grader v3: 8/5/6 = 53.3/33.3/40.0. Under grader v4: 10/8/8 = 66.7/53.3/53.3. Both FAIL vs 80% pass³. v4 flips only 2 cells in run1 (06, 12) — consistent with never-stricter, insufficient to clear.

**Attempt 3 — FAIL (official, agent v0.1.1, grader v4). Re-derived independently:**

| Run | Verified | Rate | ≥80%? |
|---|---|---|---|
| run1 | 8/15 | 53.3% | no |
| run2 | 9/15 | 60.0% | no |
| run3 | 8/15 | 53.3% | no |

Per-difficulty (across 3 runs, 15 cells each): **easy 11/15, medium 6/15, hard 8/15** — all reproduced exactly from `arm1-results.jsonl`. `pass_cubed = false`. **Every recomputed number matches `arm1-verdict.json`.**

**Independent spot re-grade (I ran `evals/oracle-check.sh` myself on 10 cells across runs/difficulties):**
`run1/arm1-01`=PASS, `run1/arm1-07`=FAIL, `run2/arm1-05`=PASS, `run2/arm1-09`=PASS, `run2/arm1-14`=PASS, `run3/arm1-06`=PASS, `run3/arm1-08`=FAIL, `run3/arm1-15`=FAIL, `run1/arm1-12`=PASS, `run1/arm1-13`=PASS — **all 10 match the recorded `verified` flags exactly.** Grading is reproducible by a third party.

**Attempt-3 integrity:** 45 reports, all `meta.jsonl` `exit=0`; **0 reports contain the billing string** — attempt 3 is clean of the attempt-1 outage.

---

## §5 Sample validity — failures real, passes real

- **`arm1-08` (all runs):** run2 = wholesale omission (ANSWER-row_count, ANSWER-matches_seventeen, VERIFY-selfcheck, EVIDENCE-row_count, PROPOSAL, PROPOSAL-TARGET all **missing**); run1 & run3 = `VERIFY-selfcheck: fail` (agent blocked from executing the script) + evidence anchor out-of-range. **Real failures.**
- **`arm1-07` run1 (anchor failure):** ANSWER=22 correct, VERIFY=pass, but `PROPOSAL-TARGET: …/fixtures.tsv:19` points **past EOF** (file has 18 lines; line 19 empty). Correctly failed. **Real.** (Its `EVIDENCE-test_count: …bats:38-252` range anchor legitimately resolved via fix #2.)
- **`arm1-01` run1 (pass):** ANSWER-enum_count=9 — verified against the live schema: line 11 of `schemas/roster-entry.schema.json` holds exactly 9 enum values; anchor resolves. **Real pass, info present and correct.**
- **`arm1-12` run1 (pass):** all four answers (831/850/831/19) match the oracle; anchors resolve; exercises fix #4 + fix #1 legitimately. **Real pass.**

Passes correspond to present-and-correct information; failures correspond to missing/wrong/unresolvable/blocked information. Sample valid.

---

## §6 Anti-p-hacking / margin-ordering — SATISFIED (with a noted caveat)

Git history:
- `acceptance-criteria.md` committed **08:05** (`77277d3`), before any measurement, froze the **structure**: pass³ (3/3 runs ≥ floor X%), N≥K stratified easy/medium/hard, Arm-2 **hard MUST=0** over-capture on strongly-matched, near-threshold ≤ a frozen bound. X, K, bound were human-owned OQ-1 placeholders.
- `change.json` P4 amendment committed **12:55** (`fe989bd`) **resolved the numerics**: X=80%, K=12/N=15, near-threshold bound ≤5% (user-delegated).
- Arm-1 attempt-3 (the **decisive** measurement) created **14:35** — **after** the 12:55 numeric commit. The 80% floor provably predates it.
- Arm-2 replay files created ~**10:41** — the numeric soft bound (5%) was committed later (12:55), bundled with the Arm-2 result.

**Ruling: anti-p-hacking property holds.** The one imperfection — Arm-2's *soft* 5% bound was committed contemporaneously with (not strictly before) the Arm-2 replay — is **immaterial**, because: (a) the Arm-2 **hard** bar (MUST=0) was frozen pre-measurement at 08:05 and is the strictest possible value; (b) the Arm-2 result is a clean **0 fires**, which clears any positive bound and the MUST=0 regardless of labels; (c) the Arm-1 floor (80%) predates its decisive run **and** is set *stricter* than the observed 53% — producing a FAIL, the opposite of gaming toward a pass. The record's phrase "frozen before any gate measurement" is literally exact for the structure and Arm-1's floor; for Arm-2's numeric soft bound it is contemporaneous — flagged as process hygiene, not a defect.

---

## Key observation for the humans

A meaningful fraction of Arm-1 failures trace to a **sandbox tool-approval gate that blocked `bash scripts/*.sh` execution** ("This command requires approval," no approver in-session). Gilgamesh's frozen Bash allowlist permits `eidolons sandbox / make / bats / rspec / jest / pytest / go test / shellcheck / shasum / wc` but **not** generic project-script execution — yet several holdout missions require running scripts like `scripts/dispatch-predicate-selfcheck.sh` and `scripts/token-budget-check.sh` to satisfy their VERIFY step. Gilgamesh split between two behaviors: honestly reporting `VERIFY=fail` (→ correctly graded FAIL) and reconstructing the script's algorithm from read-only primitives to report `pass` (→ graded PASS). This run-to-run inconsistency is itself why pass³ is the right discipline. **The mechanical FAIL is correct and attested; but the humans should weigh whether these are true capability limits of a bounded-authority worker or an allowlist/mission-scoping artifact before deciding remediation vs re-scoping.**

---

## ═══ ATTESTED VERDICT ═══

- **GATE: FAIL.**
- **Arm-2: PASS** (0 Gilgamesh fires / 76; strongly-matched over-capture = 0 = MUST bar; near-threshold 0/20 = 0.0% ≤ 5%; label chain blind & reconciled; smoke≡official byte-identical).
- **Arm-1: FAIL** (attempt 3, agent v0.1.1, grader v4: 53.3 / 60.0 / 53.3 vs frozen 80% pass³; independently re-derived; 10/10 spot re-grades match).
- **Grader fixes:** #1 anchor-annotation **ACCEPT**, #2 line-range **ACCEPT**, #3 VERIFY-first-token **ACCEPT**, #4 folded-labels **ACCEPT** (all never-stricter; none rejected; no stricter re-grade triggered).
- **Freeze integrity:** intact (both manifests check clean; holdout+oracle unchanged across attempts).
- **Anti-p-hacking:** satisfied (structure + Arm-1 floor pre-frozen; Arm-2 immaterial by construction).
- **Maker ≠ checker:** enforced; my identity distinct from all makers/authors/labelers/orchestrator.
- **Per AC-G06:** two arms did not both pass → roster `status` **must remain `in_construction`**; the `shipped` flip is **BLOCKED**. Verified: `roster/index.yaml` gilgamesh entry reads `status: in_construction`; the change is not in a `verified` state.

*Attested by `gate-checker-opus-fresh` — independent gate checker. This attestation is final for this gate.*
