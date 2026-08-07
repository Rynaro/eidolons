# verification-plan — `crystalium-residual-eight-plan`

Companion to `spec.md` / `spec.criteria.md`. This file is the **checker's** document: it says
what to measure, in what order, with what command, and what result means STOP.

MAIN = `/home/rynaro/workspace/oss/agents/crystalium`
CHANGE = `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan`

---

## 0. Execution rules (violating any of these invalidates the measurement)

1. **Container-only.** `docker compose run --rm crystalium …` from MAIN. Inside a container the
   interpreter is `/app/.venv/bin/python`. **Never `bash -lc`** — the login profile resets PATH
   to a dependency-free interpreter and has silently destroyed a whole baseline before.
2. **Never `2>/dev/null`** on a command whose success is being checked.
3. **Three suite modes, all distinct.** `make test-fast` (SKIP_SLOW + `-m "not slow"`),
   `make test` (no SKIP_SLOW, all selected), `make test-ci` (SKIP_SLOW **with slow selected**).
   CI is the third one. A `slow` mark does not protect CI; a test inheriting SKIP_SLOW can pass
   `test-fast` and fail `make test`. **Every release gate names `make test` AND `make test-ci`.**
4. **Never assert on `crystalium.__version__` from a bind-mounted dev container** — it derives
   from installed package METADATA and reports the image's version, not the source's.
5. **One worktree per unit; no two units share a file** (spec.md §2). A shared file is DRIFT.
6. **Seed protocol (C-2).** "7 seeds" = `PYTHONHASHSEED` ∈ {0,1,2,3,4,5} plus one unset run.
7. **Do not diff across a fixture change.** A baseline captured on fixture X is comparable only
   to a measurement on fixture X. This rule already has a scar (`eval-before` vs
   `eval-baseline-deconfounded`).

---

## 1. Baseline capture (before any unit)

| id | command | recorded to |
|---|---|---|
| VP-B1 | `cd MAIN && make test 2>&1 \| tail -5` | `CHANGE/baseline-suites.txt` |
| VP-B2 | `cd MAIN && make test-ci 2>&1 \| tail -5` | `CHANGE/baseline-suites.txt` |
| VP-B3 | 7 seeds × `docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -m evals fusion-gate` | `CHANGE/baseline-fusion-7seed.json` |
| VP-B4 | `docker compose run --rm crystalium /app/.venv/bin/python -m evals retrieval-gate` | `CHANGE/baseline-retrieval.json` |
| VP-B5 | `cd MAIN && git rev-parse HEAD` | must be `b7f1a47` |

**STOP if VP-B3 is not 7/7 `gate_pass: true`** — a red seed on the *shipped* build is a
shipped-build flake, not a baseline (S-6).
**Expect VP-B4 to report `verdict: "inconclusive"` under SKIP_SLOW** — that is the N-5 honesty
branch working, not a failure. Record which mode produced it.

---

## 2. Measurements, in order

### VP-M1 — the floor-channel prediction (runs FIRST in W-G-FLOOR, gates the whole unit)

spec.md §4 (#48) predicts that #41's all-seed expansion **removed** `FETCH_WIDTH_FLOOR`'s only
channel on the existing fusion fixture (N1/N2/N3 sit at dense ranks 1-3 and are inside both
`[:10]` and `[:1000]`, so the derived-arm union is identical at both floors). This is a
derivation and must be measured before anything is built on it.

```
for s in 0 1 2 3 4 5 unset; do
  docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -c \
    "import json; from evals.fusion_gate import run_floor_probe; \
     print(json.dumps({'f10': run_floor_probe(floor=10, weighted=False), \
                       'f1000': run_floor_probe(floor=1000, weighted=False)}))"
done
```
Record to `CHANGE/vp-m1-floor-channel.json` with `channel_live` = "the two floors' retrieved
lists differ at ≥1 seed".

- `channel_live == false` → prediction **confirmed**; proceed to build the new fixture with the
  edge-bearing competitor between the floors (spec.md §4).
- `channel_live == true` → prediction **refuted**; record it, and note that the residual blocker
  is the tie-break, exactly as `test_fusion_gate.py:60-73` claims. Proceed to the same new
  fixture — the design is right either way — but do **not** carry the refuted claim forward.

### VP-M2 — cross-layer gate redness (W-G-XL)

```
docker compose run --rm crystalium /app/.venv/bin/python -m evals cross-layer-gate
docker compose run --rm crystalium pytest mcp-server/tests/test_cross_layer_gate.py -v
```
Pass = `target_rank != 0` on `b7f1a47` (AC-310) **and** the single-layer control at rank 0
(AC-311) **and** the liveness object shows all pinned axes non-binding (AC-312).

### VP-M3 — corpus-scaling gate redness + small-corpus control (W-G-CORPUS)

AC-314 red at `M > candidate_k`; AC-315 green at `M < candidate_k`. Record `candidate_k`,
`M`, and `len(sparse_ranking)` in the result object — if `len(sparse_ranking) != candidate_k`
the fetch was **not** censored and the gate is measuring something else.

### VP-M4 — weight discrimination (W-G-WD)

3 weights × 7 seeds = 21 cells, recorded whole, no verdict asserted on the sub-1.0 cells.
Injection point is `Aetheryte.__init__`, and the value **must be read back off the instance** —
reading it back off the kwarg dict you just wrote is a tautology and cannot fail. Pass =
≥2 distinct outcomes across the three weights (AC-317).

### VP-M5 — §D2 identity refresh (W-G-WD)

20 in-process comparisons, `max_abs_diff == 0.0` (AC-319), plus the 1-ULP perturbation
red-check (AC-320).

### VP-M6 — floor sensitivity, 7 seeds, disjointness (W-G-FLOOR)

AC-322 disjoint distributions; AC-323 red-check.

### VP-M7 — Wave-2 differentials

After **each** Wave-2 link, re-run VP-B3 (AC-344, 7/7) and record
`explain.fusion.{n_sparse_cap, selectivity, w_sparse, arm_sizes}` on the cross-layer fixture
pre and post. #45 Option A changes `cap`'s meaning when `layers` is a strict subset; that
delta must be *recorded*, not discovered later.

### VP-M8 — wire non-regression (before tagging v2.1.0)

Run `golden_wire.py` from
`/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/archive/2026-08-05-crystalium-mcp-sdk-2x-39/`
against v2.0.1 and against the v2.1.0 candidate; diff. Pass = differences confined to
`result.content` payload ordering; **no** change to tool names, `inputSchema`, or `isError`
(AC-361).

---

## 3. STOP conditions (identical ids to spec.md §6)

| id | trigger (mechanical) | action |
|---|---|---|
| **S-1** | AC-352 returns `p1_recreated: true`, or a post-#41 multi-seed run shows relaxation regressing multi-hop F1 | keep seed exclusion; close #42 policy-affirmed **with the measurement**; do not ship |
| **S-2** | any gate red at `fusion_weight_derived = 1.00` | STOP before any `config.py` edit (AC-136 contingency) |
| **S-3** | AC-310 returns `target_rank == 0` on `b7f1a47` | the gate does not measure #45; redesign; do not proceed to W-45 |
| **S-4** | AC-311 red on `b7f1a47` | fixture's BM25 assumption wrong; gate red for the wrong reason |
| **S-5** | AC-322 cannot be made disjoint at any fixture shape | AC-139 unobtainable → **retire** with mechanism note; no permanent strict-xfail |
| **S-6** | AC-344 not 7/7 after any unit | contingency six |
| **S-7** | AC-315 red (small corpus still loses the planted record) | gate not measuring truncation; WONTFIX #47 |
| **S-8** | any new gate green on the pre-fix tree | it is not a gate |
| **S-9** | `make test` and `make test-ci` disagree | third mode is a release gate |
| **S-10** | `fence-amend.json.verdict == "DENY"` | #44 not closable as specified; re-file |
| **S-11** | a proposal to close #47 or #55 by presenting a construct as a measurement | spec.md §5.1 / §5.2 |
| **S-12** | `ramza-drift --range <base>..<head>` reports a file outside the unit's declared ownership | DRIFT: `ramza-freeze --amend --reason` or revert |

---

## 4. Red-check protocol (NC-1) — and how the checker discharges it

For **every** new gate, the maker records in `CHANGE/red-evidence.txt`:
`(gate, perturbation applied, command, observed exit/output, restored-and-green confirmation)`.

**The checker does NOT replay that file.** The checker applies **their own, different**
perturbation to each gate and confirms red, then records
`CHANGE/checker-redcheck.json` with `independently_reproduced: true` per gate (AC-332).

Suggested checker-side perturbations (deliberately *not* the maker's):

| gate | maker's perturbation (spec.md §4) | checker's, must differ |
|---|---|---|
| entrypoint (#57) | `NameError` in `run_stdio` | rename the module's `serve` subcommand in `__main__.py` so argparse rejects it |
| cross-layer (#52) | assert on today's build (red by construction) | move `sem-target` into `procedural` — rank must still be non-zero, and the single-layer control must still pass |
| corpus-scaling (#47) | shrink the corpus | raise `k` so `candidate_k > M` — must go green |
| weight-discrimination (#55) | 1-ULP weight perturbation | set `w_derived = 100.0` — must re-create P1 (the `dp2-control-note.md` positive control) |
| floor-sensitivity (#48) | move the edge-bearing competitor inside both floors | run both probes at floor 1000 — disjointness must fail |
| status top-up (#44) | delete the call, keep the counter | mark every fixture crystal active — the top-up must not fire |
| seed exclusion (#42) | flip the default | remove the `visited = set()` half only — the `decaying_walk` half of the byte-identity test must go red independently of the `neighbor_expand` half |

**Rule:** a red-check that the checker could not reproduce with an independent perturbation is
a claim, not evidence, and the gate does not count as verified.

---

## 5. Release checklists

### v2.0.2 (gates only)
- [ ] AC-301..AC-325 green
- [ ] AC-330 (both suite modes)
- [ ] AC-331 (no production-behaviour diff)
- [ ] AC-332 (checker re-broke all four gates independently)
- [ ] AC-333 (`ramza-gate critic --author <maker> --checker <checker>`)
- [ ] `ramza-drift --state … --range v2.0.1..HEAD` clean against §2's ownership table
- [ ] tag `v2.0.2`; ghcr image built + pushed (tags un-prefixed)
- [ ] index digest pulled **from the ghcr registry**, not from a local build
- [ ] roster PR bumps **both** `roster/mcps.yaml` and `roster/index.yaml` in one commit (AC-363)
- [ ] nexus integrity PR: `archive_sha256` = raw tar **with prefix**, verified by hand (**this PR gets no CI**)
- [ ] `eidolons mcp verify` exit 0 (AC-364). **Exit 3 = INDETERMINATE, not a pass**
- [ ] local `.mcp.json` re-pinned (routinely forgotten; currently 1.9.0 while the roster is ahead)

### v2.1.0 (behaviour)
- [ ] AC-340..AC-353 green
- [ ] AC-360 (both suite modes)
- [ ] AC-361 (VP-M8 wire diff)
- [ ] AC-362 (second, distinct critic)
- [ ] CHANGELOG entry states plainly that recall **result order and membership change**
- [ ] the same roster/nexus checklist as above

---

## 6. What this plan does NOT license

- Any claim that retrieval **quality** improved. Every gate here is a *falsifiability*
  instrument on a stipulated fixture; none of them measures quality on real corpora.
- Any claim that the sub-1.0 `fusion_weight_derived` band is characterised (C-9, spec.md §5.2).
- Any claim that a `candidate_k` scaling law is validated (spec.md §5.1).
- Any claim that #48's AC-139 was *discharged* if it was in fact *retired* (S-5) — retired and
  discharged are different closures and the issue comment must say which.
- Any edit to `evals/fusion_gate.py::_build_fixture`, to `bm25_search`, or to
  `layers/episodic.py:319` (NC-5).
