# verification-plan.amend-02 — `crystalium-residual-eight-plan`

**Amendment `amend-02`.** Supersedes named sections of `verification-plan.amend-01.md`.
Neither `verification-plan.md` nor `amend-01` is edited. Chain:
`verification-plan.md` → `amend-01` → **`amend-02`** (governs on conflict).

MAIN = `/home/rynaro/workspace/oss/agents/crystalium`
CHANGE = `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan`

---

## 0. Execution rules — adds rule 11

Rules 1-10 (`verification-plan.md` §0 + `amend-01` §0) stand. Added:

**11. Positive-capability before a routing negative (global rule (f)).** Any measurement whose
**negative** would route a disposition MUST first be shown capable of emitting a **positive**,
via a named shipped control whose result is recorded **in the same artifact**. A `false` from
an uncontrolled probe is **not evidence**: not carried, not cited, not entered into a closing
comment (**S-14**). *This rule exists because VP-M1 as originally specified was **guaranteed**
to return `channel_live == false` — see §2.0.*

---

## 2.0 WHY VP-M1 IS BEING REWRITTEN A SECOND TIME (K-B17)

`amend-01` §B.7.3 demoted the preliminary VP-M1 result as a **one-sided proxy** (FORGE D5's
grounds). That was correct and **insufficient**. The deeper defect is that **the mandated
protocol had no failure mode.** Three orthogonal blindnesses, all quoted from the shipped
fixture's own docstring at `b7f1a47`:

1. **The seed set excludes the only divergent point.** `fusion_gate.py:85-92`: the channel
   evidence is *"14 sample points (PYTHONHASHSEED 0-12 and unset) … exactly ONE point diverges
   (**seed 8** …) while **all 13 other sampled points (0-7, 9-12, unset) agree**"*. C-2 is
   `{0-5, unset}` — a **strict subset of the agreeing set**. A 7-point C-2 run returns `false`
   whether the channel is live or dead.
2. **The shipped fixture pins the fused rank against the signal.** `fusion_gate.py:65-70`:
   `N1` is *"ALWAYS tied with `target` at `1/61`"* and the id-ascending tiebreak means `target`
   *"never reaches rank 0 there **regardless of anything the derived arms do**"* — engineered
   deliberately so AC-125 stays unanimous. **FORGE D5's `graph_store` spy fixes this and only
   this.**
3. **The evidence and the probe target are different fixtures.** The 14-seed measurement ran on
   variant **(3)**, *"tried and measured, **then reverted**"* for regressing AC-125 7/7 → ~2/7
   (`fusion_gate.py:35-43`); `_build_fixture` ships variant **(2)** (`:45-46`).

**Collateral, git-dated this pass:** `fusion_gate.py:80-81`'s *"The floor's channel is LIVE and
MEASURED"* rests on *"anomaly A's single-seed cap aborts the walk there"* (`:79`) — the exact
mechanism **#41 removed**. `evals/fusion_gate.py` last changed at `56c8510` (**2026-08-03**);
`storage/graph.py` last changed at `cab9b73`, the #41 sweep (**2026-08-04**). The claim was
written **the day before #41 landed** and **has not been touched since**. Nothing on the
post-#41 tree has re-tested it. See `spec.amend-02.md` §1.4 and **AC-359**.

---

## 2.1 VP-M1 — PROTOCOL REPLACED (supersedes `amend-01` §2.3)

The probe construction of `amend-01` §2.2 (D5's recording proxy at the `graph_store` seam, the
`run_floor_probe` self-check, the `try/finally` monkeypatch, `fusion_gate.py` byte-untouched)
**stands unchanged**. What changes is the **seed set** and the **control**.

### Step 1 — the positive control FIRST (AC-357; rule (f) / rule 11)

```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_control(floor_low=2, floor_high=1000, seed_label='0'), '/app/evals/results/m1-positive-control.json')"
```
```
jq -e '(type == "object") and (.floor_low == 2) and (.floor_high == 1000) and (.low_derived != .high_derived) and (.channel_live == true) and (.self_check_ok == true)' /home/rynaro/workspace/oss/agents/crystalium/evals/results/m1-positive-control.json
```
**PASS = exit 0.** `_build_fixture` puts the only edge-bearing nodes `N1/N2/N3` at dense ranks
1-3 and `F1..F12` at 4-15 (`fusion_gate.py:55-61`), so `[:2]` holds `N1, N2` and **excludes
`N3`** while `[:1000]` admits all 15 — the seed set differs in **membership by construction**,
independent of hash order. One seed suffices.

**Red or absent ⇒ STOP.** The probe is not instrumented. That is a **probe defect** (S-13
step 1), not a finding about the floor. **Do not run step 2, and do not record any
`channel_live` value** (S-14).

### Step 2 — 14 spawned processes (was 7)

```
( cd /home/rynaro/workspace/oss/agents/crystalium && for s in 0 1 2 3 4 5 6 7 8 9 10 11 12; do docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_seed(seed_label='$s'), '/app/evals/results/m1-seed-$s.json')" || exit 1; done )
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_seed(seed_label='unset'), '/app/evals/results/m1-seed-unset.json')"
```

The 14th run **omits `-e` entirely** (rule (d) / K-N17). **`PYTHONHASHSEED` 0-12 + unset is the
tree's own evidence set** (`fusion_gate.py:85-86`) and is chosen because it is the only set
**provably containing the divergent point**. **C-2 (`0-5` + unset) remains correct and
unchanged everywhere else** — AC-344, AC-317, AC-322. Only the floor-*channel* question changes
protocol; the two questions have different failure modes and the tree records why.

**A smaller set is permissible only if it provably contains seed 8**, with the justification in
the artifact. `{0-5, 8, unset}` (8 points) is the minimum defensible reduction. **Any run on
fewer than 14 points must record `seed_set_covers_divergent_point: false` and
`divergent_point_known: "8"`** — such a run is a smoke test, never evidence.

### Step 3 — aggregate

```
cd /home/rynaro/workspace/oss/agents/crystalium && jq -s --slurpfile ctl evals/results/m1-positive-control.json '{seeds: ., channel_live: (any(.[]; .floor10_derived != .floor1000_derived)), seed_set: [.[].seed], seed_set_covers_divergent_point: (([.[].seed] | index("8")) != null), divergent_point_known: "8", positive_control: $ctl[0]}' evals/results/m1-seed-0.json evals/results/m1-seed-1.json evals/results/m1-seed-2.json evals/results/m1-seed-3.json evals/results/m1-seed-4.json evals/results/m1-seed-5.json evals/results/m1-seed-6.json evals/results/m1-seed-7.json evals/results/m1-seed-8.json evals/results/m1-seed-9.json evals/results/m1-seed-10.json evals/results/m1-seed-11.json evals/results/m1-seed-12.json evals/results/m1-seed-unset.json > /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```

Then **AC-321** (`spec.criteria.amend-02.md`) is the gate on that file.

### 2.2 Aggregate schema (supersedes `amend-01` §2.4)

```json
{
  "seeds": [ { "seed": "0", "floor10_derived": ["..."], "floor1000_derived": ["..."],
               "floor10_retrieved": ["..."], "floor1000_retrieved": ["..."],
               "floor10_target_rank": 0, "floor1000_target_rank": 0, "self_check_ok": true } ],
  "seed_set": ["0","1","2","3","4","5","6","7","8","9","10","11","12","unset"],
  "seed_set_covers_divergent_point": true,
  "divergent_point_known": "8",
  "positive_control": { "floor_low": 2, "floor_high": 1000,
                        "low_derived": ["..."], "high_derived": ["..."],
                        "channel_live": true, "self_check_ok": true },
  "channel_live": false
}
```

### 2.3 What VP-M1 may and may not license (NEW — supersedes `amend-01` §2.7's routing note)

| result | licensed conclusion |
|---|---|
| `channel_live == true`, 14 pts, control green | the channel is live at the derived level **on the shipped fixture (variant 2)** post-#41. `spec.md` §4 #48's prediction is **refuted**; carry the tie-break explanation instead. |
| `channel_live == false`, 14 pts, control green | *"No derived-membership difference observable at 14/14 sampled points on the shipped fixture (variant 2), post-#41."* **NOT "the channel is dead"** — variant (2) has never had a divergent seed identified, so an unsampled point cannot be excluded. Record with the sampled set attached. |
| `channel_live == false`, control red or absent | **NOTHING.** Probe defect. Not recordable (**S-14**). |
| any result on `< 14` points | smoke test only; `seed_set_covers_divergent_point: false` must be in the artifact. |

**The routing rule is unchanged: the new between-floors fixture gets built either way.**

### 2.4 The preliminary capture — status unchanged, cause upgraded

`amend-01` §2.6 demoted `CHANGE/vp-m1-floor-channel.json`'s preliminary `retrieved`-only
capture to `vp-m1-floor-channel.preliminary.json`. That stands. The **cause** is upgraded: it
was not merely a one-sided proxy — it ran the **C-2 protocol**, which is *provably blind to the
only divergent point*, on the **wrong quantity** (`retrieved`, which the fixture pins). It
confirms nothing about `channel_live` **by construction, twice over**.

---

## 3. STOP table — deltas

| id | delta |
|---|---|
| **S-5** | Trigger unchanged. **Added:** a `channel_live == false` from a VP-M1 whose positive control (AC-357) is red or absent does **not** contribute to S-5's evidence — it is a probe defect. **And: S-5 is now the EXPECTED outcome for #48, not the exception** (see §4). |
| **S-14** | **NEW.** *Trigger:* a measurement whose negative would route a disposition is run, or its result recorded, **without** the rule-(f) positive-capability control. *Action:* the result is **not evidence** — not carried, not cited, not in any closing comment. Build the control, re-run. **Not an S-13 event**: the gate is not unfailable, it is **unvalidated**. |

---

## 4. #48's raised probability of retirement — stated, not discovered later

The tree's only evidence that `FETCH_WIDTH_FLOOR` has a live channel is:
(i) **pre-#41** (git-dated: `56c8510` 2026-08-03 vs `cab9b73` 2026-08-04);
(ii) measured on a **reverted** fixture variant (3);
(iii) grounded in **anomaly A's single-seed cap** — the mechanism **#41 deleted**
(`graph.py:215-230` now loops every seed; `:305` sorts the frontier).

⇒ **The most likely outcome of a correctly-instrumented VP-M1 is `channel_live == false` for a
real reason**, and of AC-322 non-disjointness ⇒ **S-5 ⇒ S-13 class (c): retire AC-138/AC-139
with a mechanism note; close #48 as *retired*, not *discharged*.**

That is a legitimate closure. It is **not** licence to weaken AC-322, to hunt for a fixture
until one goes green (S-13 step 2's **one**-cycle bound), or to leave a permanent strict-xfail
(S-13 step 4). **S-13 step 5 still governs the artifact**: if the fixture cannot be built with
falsifiable controls, the gate is **deleted, not merged** — a permanently-green test is
camouflage for the next regression.

**This makes #48 less closable than `amend-01` implied. Recorded here rather than encountered
mid-Wave-1.**

---

## 5. Release-checklist deltas (v2.0.2)

Add to `verification-plan.amend-01.md` §5.1, before the AC-330 line:

- [ ] **AC-357** — VP-M1's positive control green (`floor=2` vs `floor=1000` ⇒
      `channel_live == true`) **BEFORE** any VP-M1 measurement is recorded (rule (f) / S-14)
- [ ] **AC-321** — `vp-m1-floor-channel.json` carries **14** seed rows, the literal seed `"8"`,
      `seed_set_covers_divergent_point: true`, and the positive control
- [ ] **AC-358** — the disjointness classifier's both-branches unit test green
      (`test_disjointness_classifier_both_branches`)
- [ ] **AC-359** — `fusion_gate.py:72-92`'s liveness claim **dated** as pre-#41 (not deleted),
      naming the removed single-seed-cap mechanism and its untested status
- [ ] **AC-313** — the restructured freeze: three source hashes (`_crystal`, `_build_fixture`,
      `run_floor_probe`) + `_FILLER_COUNT == 12` + `_QUERY`, and the rename surface bounded to
      `run_arm`/`run` on function bodies only
- [ ] **Rule-(f) audit recorded:** every routing negative in the batch has a named
      positive-capability control, or is explicitly routed to a classified closure
      (`spec.amend-02.md` §2's table)
- [ ] **W-G-XL's grant** covers `fusion_gate.py` `:72-92` **and** `:104-106` (docstring only);
      **W-G-FLOOR's diff contains no `evals/fusion_gate.py` hunk at all** — check it in the
      per-unit S-12 `comm` step, not by reading

---

## 6. What this plan does NOT license — additions

`verification-plan.md` §6 + `amend-01` §6 stand. Added:

- Any claim that VP-M1's `channel_live == false` means **the channel is dead**. It means *no
  difference was observable at the sampled points on variant (2)* — and variant (2) has never
  had a divergent seed identified at all.
- Any use of a `channel_live` value produced **without** AC-357's positive control (S-14).
- Any transfer of the **seed-8** evidence, or of the *"channel is LIVE and MEASURED"* claim, to
  the **shipped** fixture: both come from the **reverted** variant (3), pre-#41.
- Any claim that **C-2** is the right protocol for the floor-channel question. It is the right
  protocol for AC-125 unanimity and **provably blind** here (`fusion_gate.py:88-89`).
