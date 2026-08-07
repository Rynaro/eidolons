# Kupo critique 02 — amendments to crystalium-residual-eight-plan

checker: `kupo` (maker `ramza`, C4 satisfied) · second pass
target: `/home/rynaro/workspace/oss/agents/crystalium` @ `b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc` (tree verified clean before and after; READ-ONLY)
method: source read at `b7f1a47` + **executed** read-only probes (container used only to *measure*, never to edit; all writes went to `tempfile.mkdtemp()` inside the container; `evals/results/` still holds only `.gitkeep`).

## Verdict: ACCEPT-WITH-AMENDMENTS

The amendments are substantially better than the plan I rejected. I re-attacked the new
surface and **confirmed by execution** that the four criteria I broke hardest are now fixed:
AC-310 exits 1 on `null`, on `-1` and on `0`; AC-322 exits 1 on an empty distribution and on
the `-1` sentinel; AC-332 exits 1 on a boolean file; AC-321 exits 1 on a fabricated verdict and
on a seed set with 8 swapped out. D1's BM25 separation — the single most load-bearing new
premise, and the one that killed the first plan — **reproduces exactly** in the pinned build.
D2's four expected value sets trace correctly against `graph.py` line by line. 13 of my 14
blocking findings are genuinely discharged.

It is not ACCEPT because the new surface carries **6 new blocking defects**, and one of them is
the same species as K-B1: **AC-357 — the positive control on which the entire new rule-(f)
mechanism rests — cannot emit `true`.** I measured it: the derived-arm union on the shipped
fixture is `['Z']` at floor 2, floor 10 *and* floor 1000, because `_build_fixture` deliberately
points all three edge-bearing nodes at the same phantom. AC-357 is therefore permanently RED,
its RED is misrouted to "probe defect → fix the probe", and S-14 then forbids recording any
`channel_live` value at all. W-G-FLOOR cannot start.

Wave 0 is clear. W-G-XL's exit gate and W-G-FLOOR in its entirety are not.

---

## Discharge audit

`DISCHARGED` = the amended criterion would now fail on the defect the original could not
detect. `PARTIAL` = the finding is addressed but the criterion still cannot fail on some part
of it, or the fix introduced a new hole.

### Blocking (K-B1..K-B16)

| id | verdict | evidence |
|---|---|---|
| **K-B1** G-XL green on `b7f1a47` | **DISCHARGED** | §B.2.1's all-terms/TF-separation corpus. I **re-ran** the BM25 measurement in the pinned build (sqlite 3.46.1): global order `['sem-target','ep1','ep2','ep3']`, strict total order, `sem-target` at rank 0, ep1/ep2/ep3 scores identical to §B.2.1's recorded values to the digit. AC-312's `sparse_arm_size == corpus_per_layer + 1` and `global_bm25_rank0 == "sem-target"` are the two assertions that would have caught the original fixture. "RED by construction" struck and replaced by the `vp-m2-gxl-red.json` artifact obligation. |
| **K-B2** #42 names 2 of 4 sites | **DISCHARGED** | §B.5.1's five-site table matches D2 exactly. I hand-traced **all eight** expected values (T1/T2/T3/T3-variant × both flag branches) against `graph.py:200-315`; every one is correct, including the `:266` proof obligation — at T2 hop 2, `result_ids |= {S2,N2}` with `visited = set(frontier)` untouched, so S2 does appear in results. AC-351 now genuinely reddens on T1 alone. |
| **K-B3** `PYTHONHASHSEED` / vacuous empty pass | **DISCHARGED** | Global rule (d); AC-317, AC-322, AC-344 all spawn per seed with a 7th run omitting `-e`. **Executed:** the AC-322 predicate returns exit 1 on an all-null distribution and on rank `-1`, exit 0 on a genuinely disjoint one. |
| **K-B4** AC-310 passes on `null`/`-1` | **DISCHARGED** | **Executed:** `target_rank` = `null` → exit 1; `-1` → exit 1; `0` → exit 1; `3` → exit 0. The literal `expected_blocked_rank == 3` conjunct also defeats the self-consistent `(0,0)` pair the mandate asked me to try. |
| **K-B5** AC-345/AC-346 mutually exclusive | **PARTIAL** | D7's two-commit + strict-xfail mechanism is faithfully implemented and resolves the contradiction. But AC-345 part (ii)'s command exits 0 for a **PASS** as well as an **XFAIL**, so "reports XFAIL, not PASS" is an eyeball (K-C-N7); part (i) reads `ac345-prefix-evidence.json` while §B.4.4 mandates `.txt` (K-C-N4); and neither part restores the branch (K-C-N8). |
| **K-B6** the §D2 harness does not exist | **DISCHARGED** | AC-319/AC-320 struck, VP-M5 struck, ownership hole dissolved. The forward obligation is *mechanized*: AC-370 asserts `'combiner arithmetic' in low` — **verified ABSENT at `b7f1a47`** (the file says "combiner-arithmetic", hyphenated), so the criterion can fail today. |
| **K-B7** AC-321 demands unobtainable fields / `has()` shape check | **DISCHARGED as filed, superseded by K-B17/K-C3** | D5's `graph_store` spy captures the membership `explain` cannot. AC-321 is now a self-consistency predicate. **Executed:** the current `vp-m1-floor-channel.json` returns exit 1; a 14-row artifact with seed 8 swapped for 13 returns exit 1; a control reporting `false` returns exit 1. Residual: the `positive_control` conjunct is a bare boolean (K-C-N1), and the control cannot pass (K-C3). |
| **K-B8** AC-306 reads a file no unit produces | **DISCHARGED here, RECURS twice** | W-HOP now owns `fence-amend.json` + `.md` and AC-306 asserts the verdict, quote, timestamp and decider. But the same class reappears at AC-322 (`floor-7seed-aggregate.json`, K-C4) and AC-345 (`.txt` vs `.json`, K-C-N4). |
| **K-B9** perturbation table cannot discharge AC-332 | **DISCHARGED** | D8's two tables are transcribed faithfully; every replacement perturbation attacks a different *axis* and names the AC it must redden. **Executed:** the AC-332 predicate returns exit 1 on a `{gate, independently_reproduced: true}` boolean file. Count corrected to 5; AC-365 adds the 3-row v2.1.0 table with a per-row `asserted_ac` pin. Residual: AC-332 part 3 has no `cd` (K-C-N3). |
| **K-B10** AC-348 vs Option B | **DISCHARGED** | Option A pinned, B deleted, AC-348 given a per-path baseline table. The maker's own composition call is flagged and judged below. |
| **K-B11** S-12 / `ramza-drift` | **DISCHARGED** | Per-unit `comm -23` against a literal ownership file replaces the tool as the S-12 *mechanism*; `--repo` added to the plan-level invocation; and §6 explicitly de-licenses "ramza-drift verified per-unit ownership". |
| **K-B12** AC-333/AC-362 already satisfied / unsatisfiable | **DISCHARGED** | Per-batch `critic-v2.0.2.json` / `critic-v2.1.0.json` in CHANGE, `.at > .batch_started_at` timestamp binding, state file read directly rather than through `ramza-gate status`. |
| **K-B13(a)** `config.py` unowned | **DISCHARGED** | W-DOC owns `config.py:289-312` in v2.0.2, W-42 owns the new field in v2.1.0, wave-disjoint. |
| **K-B13(b)** #44 top-up dead at default | **DISCHARGED** | D6's reclassification, pin asserted by read-back **off the instance**, plus AC-356's negative control on the flag-off path. |
| **K-B13(c)** censoring claim correct | carried forward | §B.4.2 restates it verbatim with the anchors. |
| **K-B14** `-m evals` before W-CLI | **DISCHARGED** | Global rule (b); every Wave-1 gate criterion is a direct import; `-m evals` survives only in AC-325b (W-CLI's own exit gate) and for the pre-existing `fusion-gate`. |
| **K-B15** stdout contamination *(self-filed)* | **PARTIAL** | The artifact convention removes the parse-error false-red. It **introduces a stale-read false-green** (K-C6) — the more dangerous direction. |
| **K-B16** `all_edges() == 0` *(self-filed)* | **PARTIAL** | AC-312 asserts `node_count == 4` **and** `edge_count == 0`, which is right. But AC-305 — the shared rig's own liveness self-check, the place the wrong form would actually live — is UNCHANGED-BUT-RE-ANCHORED with the correct form stated **in prose only**; the criterion still cannot fail on `all_edges() == 0` (K-C-N12). |

### Non-blocking (K-N1..K-N21)

| id | verdict | evidence |
|---|---|---|
| K-N1 | **DISCHARGED** | Literal sentinel `NOT band characterisation`, case-exact. |
| K-N2 | **DISCHARGED** | Per-issue `gh issue view` with a positive `= "CLOSED"` compare, plus a mechanical `DISPOSITION:` class sentinel. |
| K-N3 | **DISCHARGED** | **Verified falsifiable today:** `evals/BENCH-NOTES.md` exists but contains none of `retrieval gate` / `fusion gate` / `config.py`, so AC-371 fails at `b7f1a47` and greens only on W-DOC's pointer. The `config.py` half is a real non-regression assertion (both literals PRESENT today). |
| K-N4 | **DISCHARGED** | **Verified:** `unsupported`, `uncharacterized`, `precision dial`, `fusion_weight_derived: float = 1.0` all PRESENT; `non-stipulated ground truth` and `combiner arithmetic` ABSENT ⇒ AC-370 can fail today. |
| K-N5 | **DISCHARGED** | AC-331 part 3 is a genuine comment/blank filter (strip marker + leading whitespace, every survivor must start `#` or be empty), with a `v2.0.1` ref guard as anti-vacuity. |
| K-N6 | superseded by AC-313 (amend-02) | see K-C1/K-C2/K-C-N9. |
| K-N7 | **DISCHARGED** | AC-324 and AC-341 both run against explicit branch refs, pre-merge, with positive counts. |
| K-N8 | **DISCHARGED** | Grant corrected to `:257, :262, :266, :281`. |
| K-N9 | **DISCHARGED** | Neutral-fixed-list variant revoked; `dense_arm_size == 0` normative. |
| K-N10 | **PARTIAL** | AC-316's same-process post-run read is the right mechanism, but nothing in §B.2/§4 #47 says the corpus-scaling gate patches `FETCH_WIDTH_FLOOR` at all (it varies `M`, not the floor) — so this control may guard a patch that never happens (K-C-N11). |
| K-N11 | **DISCHARGED** | AC-330/AC-360's third command is the **byte-identical** CI invocation; I diffed it against `.github/workflows/ci.yml:36-44` — `docker compose build crystalium` then `docker run --rm -e CRYSTALIUM_SKIP_SLOW=1 crystalium:dev pytest tests/ -v --tb=short -p no:cacheprovider`. Exact match. |
| K-N12 | **PARTIAL** | AC-355 exists and is normatively named, but gates the **sparse** arm only; D3 mandates the three-case shape for **both arms** (see FORGE fidelity, D3). |
| K-N13 | **DISCHARGED BY EXECUTION** | `baseline-verdict.md` records VP-B1..VP-B5, all green, with the two capture defects stated rather than smoothed. This is the best artifact in the folder. |
| K-N14 | **NOT-DISCHARGED (deferred, honestly)** | Recorded as an obligation in §D item 9 but not executed. I re-ran `mcp__tonberry__status`: still `status: proposed`, `acceptance_checks: []`, `has_code: false`, **C3 fail — `full: missing spec.yaml`**. Acceptable as a pre-tag obligation; not acceptable as "addressed". |
| K-N15 | **DISCHARGED and generalised** | AC-352 gains the `w_derived = 100.0` positive control — the one place rule (f) is applied in the correct direction on an attainable fixture (`config.py:296-298` states the ceiling). |
| K-N16 | **DISCHARGED** | `compare_wire.py` named and made the pass condition. |
| K-N17 | **DISCHARGED** | The 7th/14th run omits `-e` entirely, everywhere. |
| K-N18 | **DISCHARGED for AC-363, RECURS** | AC-363 gains the nexus `cd`; AC-332 part 3 does not have one (K-C-N3). |
| K-N19 | **DISCHARGED** | Rule (e); AC-304 is now an in-process existence+absence assertion that a missing module FAILS. |
| K-N20 | **DISCHARGED** | S-8 rescoped to a gate's *defect-asserting* node, explicitly excluding controls and characterisation instruments. |
| K-N21 | **DISCHARGED** | Anchor corrected in §A.1. |

---

## New blocking findings (defects introduced BY the amendments)

### K-C1 — AC-313 byte-freezes a **second copy** of the exact stale claim AC-359 exists to correct, and makes correcting it a criterion FAILURE.

AC-359 (amend-02) requires `fusion_gate.py`'s **module** docstring (`:72-92`) to be dated as
pre-#41. Its rationale, and `vp-m1-interpretation.md`'s own collateral finding, name **two**
sites:

> `evals/fusion_gate.py:72-92` **and `:296-311`** assert in prose that the floor channel is
> live and measured. That text predates #41. … that prose must be corrected or dated.
> — `vp-m1-interpretation.md:38-44` (the maker's own artifact)

`:297-311` is `run_floor_probe`'s **docstring**, and it carries the same claim in stronger form:

```
297    Corrected attribution (vigil F-V4 remediation; …): the floor DOES have a
298    live, measured channel on this fixture …
304    anomaly A's single-successful-seed cap makes the derived arms' outcome a
```

`amend-02` §4 drops that site, and AC-313 part 1 then **pins `run_floor_probe`'s
`inspect.getsource` hash** (`eeea6f2b…`, which I recomputed and confirmed). Since
`inspect.getsource` includes the docstring, correcting `:297-311` now **fails AC-313**.
AC-359 reads only `m.__doc__`, so it cannot see the contradiction either.

Net effect as specified: the campaign ships a file whose module docstring says *"pre-#41,
untested"* and whose function docstring 200 lines later says *"the floor DOES have a live,
measured channel … now measured rather than assumed"* — and the criteria mandate exactly that.

**Minimal fix.** Freeze `run_floor_probe`'s **body** (the two statements at `:312-313`) via the
same AST mechanism part 2 already uses, not its full source; and extend AC-359's assertions to
`run_floor_probe.__doc__`.

### K-C2 — AC-313 part 2 and AC-372 part 2 run `git` **inside the container, where git does not exist**. Both are false reds.

Both criteria execute `subprocess.run(['git', …], check=True)` inside
`docker compose run --rm crystalium /app/.venv/bin/python -c …`.

Measured:

```
$ docker compose run --rm crystalium /app/.venv/bin/python -c \
    "import shutil,sys; print('git_on_path:', shutil.which('git')); print('py:', sys.version.split()[0])"
git_on_path: None
py: 3.12.13
```

`Dockerfile:7` is `FROM python:3.12-slim`; the only package install is `curl ca-certificates`
(`Dockerfile:18`). `check=True` on a missing binary raises `FileNotFoundError` ⇒ non-zero exit
⇒ **RED for a reason unrelated to the defect** — and AC-313 is W-G-XL's freeze guard, AC-372 is
#47's disposition guard. Every *other* git-using criterion in the amendment (AC-324, AC-331,
AC-341, AC-353, AC-363) correctly runs on the **host**; these two are the exceptions.

**Minimal fix.** Run the `git show` / `git diff` on the host and pass the text in (or write it
to `evals/results/` first), keeping only the `ast`/`difflib` comparison in the container.

### K-C3 — AC-357's positive control **cannot emit `true`**. Measured. It is the K-B1 defect in the mechanism built to prevent K-B1.

AC-357's stated premise (`spec.criteria.amend-02.md:154-158`, `spec.amend-02.md:190-194`):

> `_build_fixture` places the only edge-bearing nodes `N1/N2/N3` at dense ranks 1-3 … so
> `dense_ranking[:2]` contains `N1, N2` and **excludes `N3`** … the walk's seed set differs in
> **membership by construction** … any seed reachable only via `N3` changes the derived union.

The seed-set half is correct — `fetch_width = max(k, FETCH_WIDTH_FLOOR)` (`retrieve.py:562`)
with `k=2` gives `[:2]`, `[:10]`, `[:1000]`. The **derived-union** half is false, because
`_build_fixture` gives all three edge-bearing nodes the **same** destination, deliberately:

```
evals/fusion_gate.py:172-175
    # All three competitors share the SAME edge target -- see module
    # docstring: this is what makes decaying_walk's hash-order frontier pick
    # robust (whichever of N1/N2/N3 it tries first still reaches Z).
    graph.add_edge("N1", "Z", "LINKS_TO"); ("N2","Z"); ("N3","Z")
```

There is **no node reachable only via `N3`**. Measured against the real `GraphStore` in the
pinned container, on the shipped fixture's topology:

```
floor=2    fetch_width=2    | n_seeds= 2 | neighbor_expand=['Z'] | decaying_walk={'Z':0.5} | DERIVED_UNION=['Z']
floor=10   fetch_width=10   | n_seeds=10 | neighbor_expand=['Z'] | decaying_walk={'Z':0.5} | DERIVED_UNION=['Z']
floor=1000 fetch_width=1000 | n_seeds=15 | neighbor_expand=['Z'] | decaying_walk={'Z':0.5} | DERIVED_UNION=['Z']
```

`floorN_derived` is defined as *"the sorted union of ids the walk actually returned"*
(`verification-plan.amend-01.md:97`). It is `['Z']` at every floor. Worse, this holds for
**every** floor pair: `fetch_width ≥ max(k,·) ≥ 2` always admits `N1`, so the union is always
`{Z}`.

Consequences, in order of severity:

1. **AC-357 is permanently RED on the shipped fixture** — a false red that burns a STOP.
2. `verification-plan.amend-02.md:74-77` routes that red to *"the probe is not instrumented …
   a probe defect (S-13 step 1) … fix the probe and re-run"*. The implementer will debug a
   correctly-instrumented probe. That is the **one-cycle redesign budget** spent on a
   misdiagnosis.
3. **S-14 then forbids recording any `channel_live` value** (`amend-02` §3.4: control red ⇒
   *"NOTHING. Probe defect. Not recordable."*). VP-M1 cannot produce evidence, AC-321 cannot be
   satisfied, and W-G-FLOOR's first task is unclosable.
4. The plan cannot fix this on the shipped fixture: giving `N3` a distinct phantom is a
   `_build_fixture` edit, which §3.1 and AC-313 byte-freeze.

**Minimal fix.** Move the control onto **W-G-FLOOR's own new fixture** (`floor_sensitivity_gate.py`,
which the unit owns and may design), constructed with *distinct* phantoms so the derived union
provably differs across the floor boundary — that is exactly what `spec.amend-01.md:920-927`
already specifies for the gate fixture. State plainly that the shipped fixture (variant 2)
**admits no positive control**, and that this is itself the strongest evidence for #48's class-(c)
retirement — a finding, recorded, not a probe defect.

### K-C4 — AC-322's new part 1 reads an artifact **no step produces**. (K-B8 class, recurred.)

`spec.criteria.amend-02.md:135` jq's
`/app/…/evals/results/floor-7seed-aggregate.json`. Grepped across the whole change folder,
that filename appears **exactly once** — in the criterion that reads it. `amend-01`'s AC-322
slurps the seven per-seed files directly (`jq -s … floor-seed-0.json … floor-seed-unset.json`)
and never writes an aggregate; `amend-02` says the three commands are *"unchanged"*. So the
producing step does not exist and AC-322 is unsatisfiable as written.

**Minimal fix.** Add the aggregate-writing `jq -s` step (the VP-M1 §2.1 step 3 pattern), or
move `seed_set` / `seed_set_covers_divergent_point` / `divergent_point_known` into each
per-seed artifact and assert them in the existing slurp.

### K-C5 — AC-358 controls an instrument **AC-322 does not use**.

AC-358 tests `test_disjointness_classifier_both_branches` — *"the pure disjointness classifier
used by the floor-sensitivity gate"*. But AC-322's disjointness is computed **in jq**, over
`.floor10_target_rank` / `.floor1000_target_rank` read from the per-seed files
(`spec.criteria.amend-01.md:353`). No criterion reads a `disjoint` field from the module. So
the rule-(f) discharge for AC-322 controls a code path whose verdict nothing consumes: the
classifier could be perfect and the jq predicate wrong, or vice versa, with AC-358 green either
way.

**Minimal fix.** Either have `run_seed`/the aggregate emit the classifier's `disjoint` verdict
and have AC-322 assert **that** (so AC-358 controls the real instrument), or write AC-358
against the jq predicate itself (feed it the three synthetic pairs — I did exactly this while
checking K-B3, and it takes one shell line).

### K-C6 — the K-B15 remedy has **no freshness guarantee**: a crashed gate leaves the previous run's artifact and the criterion passes on it.

The fix for K-B15 moved every gate criterion from `… | jq` (which cannot be stale) onto
`emit(result, '/app/evals/results/<name>.json')` + `jq <file>`. Nothing binds the file to the
run:

- `emit` is *"overwrite, never append"* (§A.4 item 1) — but only when it runs at all. If
  `m.run()` raises, the **previous** artifact survives untouched.
- No artifact carries a run timestamp, run id or nonce. `vp-m2-gxl-red.json`'s schema
  (`verification-plan.amend-01.md:208-222`) has `tree_sha` — self-reported by the gate, not a
  freshness token.
- `evals/results/*.json` is gitignored (`.gitignore:29`; `evals/results/.gitkeep` is the only
  tracked entry — both verified), so `git status` **stays clean** on a stale artifact. §A.4
  item 3 records that as a feature, and adds: *"no host-side `rm` is ever needed."* That
  sentence institutionalises the stale read.
- AC-310, AC-314, AC-317, AC-322, AC-352 state **"PASS = exit 0"** after their command blocks
  in a way that names only the `jq`'s exit. AC-325b and AC-313 say "on both"; the gate criteria
  do not.
- The seeded loops carry `|| exit 1`, so a mid-loop failure aborts — leaving seeds already
  written from **this** run and the remainder stale from a **previous** one, which `jq -s` then
  slurps into a 7-row (or 14-row) artifact that satisfies the length guard.

This is a **false-green** on the critical path: `vp-m2-gxl-red.json` is W-45's entry gate.

**Minimal fix (any one).** (i) Each `run()` result carries `run_id` (uuid4) and the criterion
is a single `set -e` command that emits then greps its own id back; (ii) mandate
`rm -f evals/results/<name>.json` before every emit and assert the file's existence is new;
(iii) make each gate criterion one shell statement — `… python -c "…emit…" && jq -e … <file>` —
so the emit's exit is load-bearing. (iii) is one character of change per criterion.

---

## New non-blocking findings

**K-C-N1 — AC-321's `positive_control` conjunct is a bare boolean.** Executed: an artifact whose
`positive_control` is `{floor_low:2, floor_high:1000, channel_live:true}` — no `low_derived`,
no `high_derived`, no `self_check_ok` — returns **exit 0**. AC-357 asserts the substance, but
nothing binds AC-357's artifact to the object AC-321 reads except the maker's `--slurpfile`.
That is the *"a boolean a replayer writes identically"* shape AC-332 was rewritten to remove.
Fix: add `(.positive_control.low_derived != .positive_control.high_derived) and
(.positive_control.self_check_ok == true)` to AC-321.

**K-C-N2 — the rule-(f) audit table has a direction error.** `spec.amend-02.md:151` marks
AC-317 *satisfied* because *"D8's checker perturbation (sever A's edge) collapses it"*. That
perturbation demonstrates the instrument can produce the **negative** (1 outcome). Rule (f)
demands a demonstration of the **positive** (≥ 2 outcomes). The same inversion appears on the
AC-310 and AC-314 rows. The consequence for AC-317 is real: if it returns `< 2 distinct
outcomes`, nothing distinguishes *"the weights don't discriminate"* (the #55 finding) from
*"my fixture is degenerate"*. A non-circular control exists and the plan already uses its
pattern at AC-352 — run the same fixture at `w_derived ∈ {0.5, 1.0, 100.0}` and require ≥ 2
outcomes; a 200× swing producing one outcome indicts the fixture, not the weights.

**K-C-N3 — AC-332 part 3 has no `cd`.** It opens `checker-redcheck.json` and `red-evidence.json`
by bare relative name under a file-wide convention that commands run from MAIN. AC-365 part 2
carries `cd …/crystalium-residual-eight-plan &&`; AC-332 part 3 does not. Exactly K-N18.

**K-C-N4 — `ac345-prefix-evidence` is `.txt` in the spec and `.json` in the criterion.**
`spec.amend-01.md:591` mandates the maker write `CHANGE/ac345-prefix-evidence.txt`;
`spec.criteria.amend-01.md:602` runs `jq -r '.commit1_sha' … ac345-prefix-evidence.json`, and
the checklist (`verification-plan.amend-01.md:394`) says `.json`. Follow the spec and the
criterion cannot run; the `git checkout $( … )` then receives an empty argument.

**K-C-N5 — three names for one probe, only one of them defined.** FORGE D5 and `spec.amend-01.md`
§B.1/§B.7.2 define `vp_m1_probe(*, floor: int) -> dict` normatively. The commands call
`vp_m1_seed(seed_label=…)` (amend-01 §2.3, amend-02 §2.1) and `vp_m1_control(floor_low,
floor_high, seed_label)` (AC-357). Neither has a defined construction or return schema, and
`vp_m1_probe` — the ruled name — is invoked by nothing.

**K-C-N6 — AC-317's `weight_readback == .weight` cannot detect the tautology it forbids.** Both
fields are emitted by the module the maker writes; a module that assigns
`weight_readback = weight` passes. The rule ("read it off the `Aetheryte` instance") is prose.
Contrast AC-346, where the equivalent pin is `assert aetheryte.recall_active_only is True`
**inside the test body** — that one is real.

**K-C-N7 — AC-345 part (ii) exits 0 on PASS as well as XFAIL.** `pytest … -v -rxX` returns 0 for
both. The stated PASS condition (*"Not PASS, not FAIL: XFAIL"*) is an eyeball on the summary.
In composition it is nearly tight (marker-absent + fix-present reddens AC-346), but as an
individual criterion it is not mechanical. Fix: assert on the summary line (`-q --tb=no -rX`
plus a `grep -q '1 xfailed'`).

**K-C-N8 — AC-345(i) and AC-361 `git checkout` MAIN with no restore and no dirty-tree guard,**
and AC-345(ii) has no checkout back to the release tree. Run in the stated order, part (ii)
executes at the commit-1 SHA where the node is unmarked and green.

**K-C-N9 — AC-313 part 2's residual filter is substring-based over whole diff lines.** Any added
line containing the literal `cross_layer`, `cross-layer` or `sparse_arm_per_layer_probe` —
including in a trailing comment — is exempted from the body diff. It is a narrower version of
the K-N6 weakness, moved inside the function.

**K-C-N10 — `vp-m2-gxl-red.json`'s `sparse_ranking` has no specified provenance.** `explain`
carries `arm_sizes` (sizes, not membership) — the amendment says so itself at §B.7.2. So the
gate must obtain `sparse_ranking` either by a spy or by re-issuing `bm25_search` per layer. The
second is a re-implementation that can diverge from what `recall` actually did — the precise
risk D5's self-check was invented to close, not applied here.

**K-C-N11 — AC-316 may control a patch that never happens.** Nothing in §B.2 or §4 #47 says the
corpus-scaling gate monkeypatches `FETCH_WIDTH_FLOOR`; it varies `M`. If it does not patch, the
criterion is permanently green and cannot fail on the defect it names.

**K-C-N12 — AC-305 still cannot fail on K-B16's defect.** The §A.3 form (`len(all_edges()) == 0`
**and** `node_count() > 0`) is stated in prose and asserted only in AC-312, on the G-XL
artifact. The **shared rig**, which is where the wrong form would live, is checked by an
unchanged pytest node.

**K-C-N13 — §B.3.2's `raw_n_sparse` is not what the code computes.** `retrieve.py:598` is
`raw_n_sparse = len(sparse_ranking)` and `:597` is `cap = candidate_k * len(target_layers)`. On
Option A's strict-subset path, `sparse_ranking` holds **post-filtered head + backstop tail**,
not *"the global raw row count"* the amendment declares. The censoring test
`raw_n_sparse >= cap` therefore changes meaning on subset queries (a post-filtered count
compared against a global cap ⇒ effectively never censored ⇒ the #38 selectivity boost silently
disabled there). VP-M7 *records* the delta; no criterion asserts it.

**K-C-N14 — AC-350 omits the T3-variant's True branch.** §B.5.2 states `exclude_seeds=True ⇒ {}`
for the T3-variant; AC-350 collects three cases (T1/T2/T3), AC-354 four. The variant's
True-branch value is in no criterion.

**K-C-N15 — the ESL record is still non-conformant right now.** Re-checked this pass via
`mcp__tonberry__status`: `status: proposed`, `acceptance_checks: []`, `has_code: false`,
**C3 fail — `full: missing spec.yaml`**. Correctly recorded as a pre-tag obligation (§D item 9),
but it is not addressed, and the ECM precedent in this repo's own memory is a record that sat
`in_progress` for five releases behind 164 green tests.

---

## FORGE-ruling fidelity

| ruling | verdict | evidence |
|---|---|---|
| **D1** (G-XL rebuild) | **faithful, and strengthened by measurement** | Corpus values (3 fillers at 24/32/40, `sem-target` 4×3=12 tokens), `k=5`, `candidate_k=15`, dense `[]`, `expected_blocked_rank = N`, C-XL-1/2/3 — all transcribed exactly. §B.2.1's recorded BM25 scores **reproduce**: I got `sem-target -7.135e-06 < ep1 -4.190e-06 < ep2 -3.718e-06 < ep3 -3.342e-06`, strict total order, rank 0, sqlite 3.46.1. D1's reversal condition is discharged at the corpus level, exactly as claimed, and explicitly **not** at the fused level. |
| **D2** (five sites, three topologies) | **faithful** | Site table matches line for line, including `:266` unchanged with T2 as the proof obligation. I traced all eight expected values against `graph.py:200-315`; all correct. The checker perturbation (sever `:272` only ⇒ AC-354 red on T1+T2, AC-350 green) is correctly derived and is genuinely the sharpest instrument available. |
| **D3** (Option A, three cases, K-N12 gate) | **faithful on shape; WEAKER on coverage** | The three-case table and the backstop condition (post-filtered count `< candidate_k·len(target_layers)` **AND** the global fetch censored) are transcribed exactly, and `test_subset_layer_recall_no_regression` is normatively named on a 2-layer subset. **But D3 mandates the shape for "both arms, sparse shown; dense mirrors it"**, and AC-355 pins the dense arm empty. The dense half of the mandated fetch shape ships with **no gate at all**. The maker's rationale (a `MagicMock` ignores `layer_filter`, so post-filtering it would confound) is sound as single-axis discipline — the correct response is a **second** node with a `side_effect` stub that honours `layer_filter`, not dropped coverage. |
| **D4** (drop the D2 harness) | **faithful** | Struck cleanly, forward obligation recorded in two places and mechanized in AC-370. |
| **D5** (probe location + spy + self-check) | **faithful in construction; diverged in protocol (a strengthening); defeated by K-C3** | `fusion_gate.py` byte-untouched by W-G-FLOOR ✓ (AC-324 part 2 asserts it on the branch ref); import-not-edit ✓; `try/finally` ✓; `run_floor_probe` self-check ✓ and asserted per row by AC-321. amend-02's 14-seed protocol supersedes D5's 7 and is a genuine improvement grounded in `fusion_gate.py:85-92` (verified verbatim: 14 points, seed 8 the sole divergence, C-2 ⊂ the agreeing set). The added control is where it breaks (K-C3). |
| **D6** (#44 is a production defect) | **faithful** | Wiring chain cited, pin asserted at the instance, AC-356 negative control shipped, reversal condition carried. |
| **D7** (two-commit + strict xfail) | **faithful on mechanism; weaker on verification** | Both commits mandated, sentinel text verbatim, checklist convention annotated. The XFAIL state is not mechanically asserted (K-C-N7) and the evidence file's name is inconsistent (K-C-N4). |
| **D8** (perturbation tables + schema + anti-replay) | **faithful** | Both tables, all ten rows, the per-gate evidence schema and the anti-replay diff transcribed exactly; counts corrected to 5 and 3; AC-365 adds `asserted_ac` pinning, which is *stronger* than D8 asked. Verified: the schema predicate rejects a boolean file. |
| **D9** (S-13 ladder) | **faithful** | §C.1 reproduces all five steps and the three exclusive classes; AC-373 mechanizes the class vocabulary with a literal `DISPOSITION:` sentinel. |

**The maker's own normative call (§F item 1 / §B.4.2): the #44 top-up widens the global head
call only, never the backstop.** Judged **sound as a call, but weak exactly where it matters,
and unmeasured.** Sound: the censoring signal is defined against the fetch that produced
`raw_n_sparse`, which is the head, so widening anything else would decide the boost against a
fetch that did not produce the signal — the same `retrieve.py:230-233` principle K-B13(c)
confirmed. Weak: on the strict-subset path, the head is the *global* call, and K-N12's premise
is precisely that the global top is dominated by **excluded** layers — so widening the head by
`n_inactive_observed` recovers mostly rows that the post-filter then discards. The top-up is
therefore expected to be near-inert on the subset path, and **no criterion measures its
efficacy there**: AC-346/AC-347 run on the #44 corpus, AC-355 measures coverage with the top-up
out of scope, AC-348 measures only call counts. The call should stand; a subset-path efficacy
assertion should be added to `test_sparse_status_topup.py`.

---

## Composition gaps: blocks-Wave-0 vs does-not-block

| gap (maker's list, §F) | blocks Wave 0? | assessment |
|---|---|---|
| **#44 top-up vs Option A backstop composition** | **No** — Wave 2 (W-44/W-45) | Call-count-wise AC-348 and AC-355 compose cleanly (baseline `1 + backstop_count`, top-up `+ ≤ 1`). The real gap is efficacy, not counts (above). Add one assertion; do not relax either gate, as the maker says. |
| **Dense-arm gap in AC-355** | **No** — Wave 2 | Real, and a divergence from D3, not just an omission. Needs a second node before W-45 merges, not before it starts. |
| **Backstop head/tail merge argued not measured** | **No** — Wave 2 | FORGE rated D3 at 82% for this reason and the maker carried it forward honestly. AC-355 measures coverage; tail order is unmeasured. Acceptable: the failure mode is rank-space imprecision at high RRF ranks, not lost records. |
| **AC-322's achievability** | **No for Wave 0; YES for W-G-FLOOR** | Compounded by K-C3/K-C4/K-C5. The plan is right that non-disjointness is the expected outcome and that class-(c) retirement is a legitimate closure. It is wrong that the instrument half is controlled (K-C5) and that the artifact exists (K-C4). |
| **Whether D5's recording proxy perturbs the walk** | **No** | Genuinely unmeasurable until the probe exists; the reversal condition is stated. Note that K-C3 makes the question moot until the control is rebuilt. |
| **Cross-repo ESL gating (`has_code` / code-state gates)** | **No** | The nexus record holds the plan; the code lands in crystalium. Verified today: C3 fails, `has_code: false`. The obligation to record the skip explicitly rather than absorb it silently is the right disposition. Must be closed before the first tag, not before Wave 0. |

---

## Coverage per issue — what can still FAIL

| issue | criteria that can fail on the defect | verdict |
|---|---|---|
| **#42** | AC-350 (T1/T2/T3 byte-identity), AC-351 (default flip ⇒ RED on T1), **AC-354** (False-branch exact sets + `:266` proof obligation), AC-352 (i)+(ii) with a working positive control, AC-353 | **Strong.** The only issue whose oracle I could fully verify by tracing; every expected value is right. |
| **#44** | AC-345 (commit-1 characterisation, re-derivable from git), AC-346, AC-347 (counter-honesty), AC-348 (per-path spy), **AC-356** (flag-off inertness) | **Strong**, modulo K-C-N7's non-mechanical XFAIL assertion. |
| **#45** | AC-340 (`target_rank == 0` + liveness riding along), AC-341, AC-342, **AC-355** (subset starvation), AC-349 (fence) | **Strong on sparse, absent on dense** (D3 fidelity note). |
| **#47** | AC-314 (`planted_recovered == false` with `sparse_arm_size == candidate_k` proving censorship), AC-315 (small-corpus control **must** be green), D8's checker perturbation (boost the plant's BM25 ⇒ AC-314 red) | **Adequate.** The gate can fail on "plant beyond the fetch window" and its control distinguishes that from "plant unfindable". The *closure* is a ruled WONTFIX (class (b)); AC-372 passes trivially when `candidate_k` is untouched, which is correct for a disposition guard but is not a gate. |
| **#48** | AC-321 (14 rows, seed 8, self-consistency), AC-322 (disjointness, non-empty + `>= 0` guards), AC-323, **AC-359** (docstring dating) | **Weakened, and blocked.** AC-359 is genuinely falsifiable — I checked the current module docstring: `#41` ABSENT, `56c8510` ABSENT, `pre-#41` ABSENT, `not been re-tested`/`untested` ABSENT, while `live and measured` and `single-seed cap` are PRESENT. So AC-359 fails today and greens only on real work. But AC-357 is unattainable (K-C3), AC-322's part 1 reads a nonexistent file (K-C4), and AC-358 controls the wrong instrument (K-C5). **#48 currently has no runnable path to any closure, including its own expected retirement.** |
| **#52** | AC-310 (exact rank, verified to reject `null`/`-1`/`0`), AC-312 (six liveness conjuncts incl. the K-B1 catcher and C-XL-3), AC-311, AC-313, AC-343 | **Strong** — the best-gated issue in the plan. AC-313 needs K-C1/K-C2 fixed to be runnable. |
| **#55** | AC-317 (≥2 distinct outcomes), AC-318 (literal sentinel), **AC-370** (verified: 2 of 6 assertions fail today), **AC-371** (verified: `BENCH-NOTES.md` lacks all three required strings), AC-352 | **Adequate after the striking.** Losing AC-319/AC-320 cost nothing — they were unexecutable. AC-370 and AC-371 are red at `b7f1a47` and green only after W-DOC does work; that is a real gate. AC-317's negative is uncontrolled (K-C-N2). |
| **#57** | AC-301, AC-302, AC-303 (handshake content), AC-304 (module exists **and** carries no `slow` marker — the replaced form fails on a missing module, the old one passed) | **Adequate**, and D8's replacement perturbation (empty tool table, process alive) is a genuine improvement on the old one. |

**Nothing is being closed by construction.** Every issue retains at least one criterion that
can fail on its own defect — except **#48**, which retains falsifiable criteria that cannot
currently be *run*.

---

## What I verified by running

| # | command (abridged) | output | conclusion |
|---|---|---|---|
| 1 | `inspect.getsource` sha256 of `_crystal`, `_build_fixture`, `run_floor_probe`, **inside the container** | `6fa658f4…`, `66d3e9a7…`, `eeea6f2b…` | **All three AC-313 hashes are correct at `b7f1a47`.** Cross-checked on host py3.14 and container py3.12.13 — identical, so the pin is interpreter-stable. `_FILLER_COUNT == 12` and `_QUERY` confirmed. |
| 2 | `shutil.which('git')` in the container | `None` (py 3.12.13) | **K-C2** — AC-313 part 2 and AC-372 part 2 are false reds. |
| 3 | Real `GraphStore` with `_build_fixture`'s topology; `neighbor_expand` + `decaying_walk` at seed slices `[:2]`, `[:10]`, `[:1000]` | `DERIVED_UNION=['Z']` in all three cases | **K-C3** — AC-357 cannot emit `true`. Also independently corroborates #48's channel-dead prediction at the derived level. |
| 4 | `RelationalStore` + D1's corpus; `bm25_search(layer_filter=None, k=60)` and raw `bm25()` scores | `['sem-target','ep1','ep2','ep3']`; `-7.135e-06 / -4.190e-06 / -3.718e-06 / -3.342e-06`; sqlite 3.46.1 | **§B.2.1 reproduces.** D1's separation mechanism is real; strict total order, `sem-target` at global rank 0. |
| 5 | AC-310's predicate against `target_rank` ∈ {`null`, `-1`, `0`, `3`} | exit 1, 1, 1, 0 | **K-B4 discharged.** The `(0,0)` self-consistent pair is rejected by the literal `== 3`. |
| 6 | AC-322's predicate against all-`null`, all-`-1`, and a disjoint distribution | exit 1, 1, 0 | **K-B3's vacuous pass closed.** |
| 7 | AC-332 part 1 against `{gate, independently_reproduced: true}` × 5 | exit 1 | **Boolean file rejected.** |
| 8 | AC-321 (amend-02) against the existing `vp-m1-floor-channel.json`; a control-`false` artifact; a 14-row artifact with seed 8 swapped for 13; a control with no derived arrays | exit 1, 1, 1, **0** | Seed-8 and self-consistency guards work; **the control conjunct is a bare boolean (K-C-N1)**. |
| 9 | `config.py` literal audit for AC-370/AC-371 | `unsupported`/`uncharacterized`/`precision dial`/`fusion_weight_derived: float = 1.0`/`fusion gate cannot express`/`only the retrieval gate is informative` PRESENT; `non-stipulated ground truth`, `combiner arithmetic` ABSENT | Both criteria **can fail today** ⇒ real gates for W-DOC. |
| 10 | `BENCH-NOTES.md` audit | exists; `retrieval gate`, `fusion gate`, `config.py` all ABSENT | AC-371 part (ii) is a real deliverable, not a pre-satisfied one. |
| 11 | `fusion_gate.__doc__` audit for AC-359 | `live and measured` + `single-seed cap` PRESENT; `#41`, `56c8510`, `pre-#41`, `untested`, `not been re-tested` ABSENT | AC-359 **fails at `b7f1a47`** and is a genuine gate. |
| 12 | `.github/workflows/ci.yml:36-44` vs AC-330 command 3 | byte-identical | K-N11 discharged faithfully. |
| 13 | `.gitignore:29` + `git ls-files evals/results` + `ls evals/results` | `evals/results/*.json` ignored; only `.gitkeep` tracked; directory currently empty | **K-C6** — stale artifacts are invisible to `git status`. |
| 14 | `mcp__tonberry__status` on the change | `status: proposed`, `drift_checked: false`, **C3 fail: `full: missing spec.yaml`** | K-N14 still open. |
| 15 | `grep -rn floor-7seed-aggregate` across the change folder | 1 hit — the criterion that reads it | **K-C4.** |
| 16 | `git status --porcelain` in crystalium, before and after | empty both times | Target repo untouched. |

Hand-traced (not executed, but derived line by line against source and stated as such): D2's
eight expected values across T1/T2/T3/T3-variant, against `graph.py:200-234` (`_neighbor_expand_one_hop`),
`:255-278` (`neighbor_expand`), `:281-313` (`decaying_walk`).

---

## Residual risk if we start Wave 0 now

1. **Low.** Wave 0's three units (W-HOP, W-ENTRY, W-RIG) have no dependency on any defective
   criterion. Their entry gate — the baseline — is captured and green, and I re-verified the
   two suite modes' agreement claim against `ci.yml`.
2. **The stale-artifact hole (K-C6) is latent, not immediate.** It bites the first time a gate
   is re-run after an edit that breaks it. Fixing it costs one `&&` per criterion and should be
   done before the first gate module exists, because the convention is what units will copy.
3. **W-G-FLOOR is the campaign's weak leg and now knows it.** amend-02 §4 states plainly that
   #48's most likely terminal state is class-(c) retirement. My measurement (probe 3) is
   independent evidence for that: on the shipped fixture the derived union is floor-invariant.
   The risk is not that #48 retires — that is a legitimate closure — but that the current
   criteria route the *correct* answer into a "probe defect" loop.
4. **The `run_floor_probe` docstring freeze (K-C1) will otherwise ship a self-contradicting
   file.** Cheap to fix now, embarrassing to discover at tag time.
5. **Two rulings ship weaker than written** (D3's dense arm, D7's XFAIL assertion). Neither is
   fatal; both should be closed before their unit merges, not before it starts.
6. **Unchanged from pass 1:** four load-bearing measurements (VP-M2, VP-M1-with-spy, AC-322
   disjointness, VP-M7's cap delta) are still unexecuted. The maker says so in §G and holds the
   verdict at VALIDATE rather than AUTO_PROCEED. That is the right posture.

---

## Cleared to start / blocked

**CLEARED (start now):**

- **W-HOP** — AC-306 is satisfiable by the artifact W-HOP now owns (`fence-amend.json` +
  `.md` sibling).
- **W-ENTRY** (#57) — AC-301..AC-304 sound; AC-304's replacement fails on a missing module.
- **W-RIG** — with the K-C-N12 note: put the §A.3 liveness form (`len(all_edges()) == 0` **and**
  `node_count() > 0`) into the rig's own asserted contract, not only into AC-312.
- **W-DOC** — AC-370 and AC-371 verified red at `b7f1a47`; the unit has real, gated work.
- **W-G-CORPUS** — AC-314/AC-315 sound. Apply the K-C6 fix to its criteria before writing them;
  resolve K-C-N11 (state whether the gate patches `FETCH_WIDTH_FLOOR` at all).
- **W-G-WD** — AC-317/AC-318/AC-352 sound. AC-352's control is the plan's best rule-(f)
  instance. Add K-C-N2's wide-band control before AC-317's negative is allowed to route.

**BLOCKED until amended:**

- **W-G-XL** — may build the fixture, **may not close its exit gate**: AC-313 is unrunnable
  (K-C2) and self-contradictory with AC-359 (K-C1). Both fixes are mechanical.
- **W-G-FLOOR** — **fully blocked.** AC-357 cannot pass (K-C3), AC-322 part 1 reads a file
  nothing writes (K-C4), AC-358 controls an unused instrument (K-C5). Rebuild the positive
  control on W-G-FLOOR's own fixture with distinct phantoms, add the aggregate step, and point
  AC-322 at the classifier AC-358 tests.
- **W-45** — its entry artifact `vp-m2-gxl-red.json` is produced by W-G-XL and read under the
  K-C6 stale-read hole. Unblocked as soon as W-G-XL is.
- **W-CLI, W-44, W-42** — downstream, unaffected by these findings.

---

*Kupo. Checker verdict: ACCEPT-WITH-AMENDMENTS. The amendments did the work — 13 of 14 blocking*
*findings are genuinely discharged and I broke four of the new predicates myself to confirm it.*
*Six new blocking defects live entirely in newly-written surface, and one of them — AC-357 —*
*is the campaign's own named defect class reproduced inside the mechanism built to prevent it.*
*Measure the control before you trust the negative it licenses; on the shipped fixture the*
*control cannot be built at all, and that is the finding.*
