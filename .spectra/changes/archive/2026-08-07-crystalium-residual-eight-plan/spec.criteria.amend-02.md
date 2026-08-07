# spec.criteria.amend-02 — `crystalium-residual-eight-plan`

**Amendment `amend-02`.** Supersedes named criteria of `spec.criteria.amend-01.md`
(hash `7e680dc63f87439dbfc2dec0220b8df51aa2b33fe776550a18b20f54cfeb05c9`), which itself
amended the frozen `spec.criteria.md`. Neither earlier file is edited. Chain:
`spec.criteria.md` → `amend-01` → **`amend-02`** (governs on conflict).

Conventions and global rules **(a)-(e)** of `spec.criteria.amend-01.md` §0 carry forward
unchanged. **Global rule (f) is added below and has equal standing.**

---

## 0.1 NEW GLOBAL RULE (f) — positive-capability before a routing negative

> **(f)** Any measurement whose **negative** result would route a disposition MUST first be
> shown capable of producing a **positive**. A probe never demonstrated to emit `true` is not
> evidence when it emits `false`. The demonstration is a **named, shipped control** whose
> result is recorded **in the same artifact** as the measurement it licenses.

General form of K-N15 (which caught the AC-352 instance). Violations trigger **S-14**: the
result is *not evidence* — not carried, not cited, not entered into a closing comment. S-14 is
**not** an S-13 event: the gate is not unfailable, it is **unvalidated**.

Rule-(f) audit (full table in `spec.amend-02.md` §2): **VP-M1** had no control ⇒ **AC-357**;
**AC-322** had none ⇒ **AC-358** (instrument half only — the fixture half is non-circularly
unattainable and routes to S-5); AC-352, AC-310, AC-314, AC-317 already satisfied.

---

### AC-313 (event-driven) — REPLACED AGAIN (K-B18; supersedes amend-01's AC-313)

*(amend-01's version pinned `_build_fixture`'s source hash plus a text filter over the whole
diff. The filter forbids the `fusion_gate.py:72-92` docstring correction that K-B18 requires.)*

GIVEN the `cross_layer` axis rename and the #48 docstring correction in `evals/fusion_gate.py`
WHEN the module is inspected
THEN the AC-125 fixture's code shall be byte-identical to `b7f1a47` while the module docstring
remains free to carry the #48 correction
VERIFY: two parts, both required — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import inspect, hashlib, evals.fusion_gate as m
EXPECT = {
 '_crystal':        '6fa658f431c97b759824408cb5af0f3a98f851dd46c089607c649a39f1930ded',
 '_build_fixture':  '66d3e9a7ea3bb8b1830c5d5ea3de7c8f70afef7a098b4a38069677ef6d6b62d4',
 'run_floor_probe': 'eeea6f2b86c0f7bd2a647386ecd13f9077fec4fc94e5336f16b1721e3ad1f0d6',
}
for fn, want in EXPECT.items():
    got = hashlib.sha256(inspect.getsource(getattr(m, fn)).encode()).hexdigest()
    assert got == want, (fn, got, want)
assert m._FILLER_COUNT == 12, m._FILLER_COUNT
assert m._QUERY == 'plarnix threxil vandomere signature', m._QUERY
print('ok')
"
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import ast, difflib, subprocess, sys
old = subprocess.run(['git','show','b7f1a47:evals/fusion_gate.py'], capture_output=True, text=True, check=True).stdout
new = open('evals/fusion_gate.py').read()
def bodies(src):
    tree = ast.parse(src); lines = src.splitlines(True); out = {}
    for n in tree.body:
        if isinstance(n, ast.FunctionDef) and n.name in ('run_arm','run'):
            out[n.name] = ''.join(lines[n.lineno-1:n.end_lineno])
    return out
a, b = bodies(old), bodies(new)
assert set(a) == set(b) == {'run_arm','run'}, (sorted(a), sorted(b))
resid = []
for fn in ('run_arm','run'):
    for l in difflib.unified_diff(a[fn].splitlines(), b[fn].splitlines(), lineterm=''):
        if l[:1] in '+-' and not l.startswith(('+++','---')):
            if 'cross_layer' in l or 'cross-layer' in l or 'sparse_arm_per_layer_probe' in l:
                continue
            resid.append((fn, l))
assert not resid, resid
print('ok')
"
```
PASS = exit 0 and the literal output `ok` on both. Part 1 byte-freezes **three functions and
two constants** (strictly stronger than amend-01's single pin) and cannot pass on a deleted or
renamed module — the import fails. Part 2 bounds the rename surface to `run_arm` and `run`,
and is computed on **function bodies only**, so the module docstring is out of scope by
construction. `_FILLER_COUNT == 12` is vigil's F-V4 cardinality fix; moving it silently
removes the floor's tail.

---

### AC-321 (event-driven) — REPLACED AGAIN (K-B17; supersedes amend-01's AC-321)

*(amend-01's version required 7 rows. The C-2 set `{0-5, unset}` is a strict subset of the
AGREEING points recorded at `fusion_gate.py:88-89`; seed 8 — the sole divergent point — is not
in it, so a 7-row artifact returns `channel_live == false` whether the channel is live or
dead.)*

GIVEN the post-#41 tree and the D5 derived-membership probe
WHEN the floor-channel probe runs over the 14-point historical seed set with its positive
control
THEN the recorded `channel_live` shall be derivable from per-seed evidence gathered on a seed
set that provably contains the only known divergent point
VERIFY: run the command block below; PASS exactly as stated.
```
jq -e '(type == "object") and (.seeds | type == "array") and ((.seeds | length) == 14) and (([.seeds[].seed] | index("8")) != null) and (([.seeds[].seed] | index("unset")) != null) and (([.seeds[].seed] | unique | length) == 14) and (.seed_set_covers_divergent_point == true) and (all(.seeds[]; (.floor10_derived | type == "array") and (.floor1000_derived | type == "array") and (.self_check_ok == true))) and (.positive_control | type == "object") and (.positive_control.floor_low == 2) and (.positive_control.floor_high == 1000) and (.positive_control.channel_live == true) and (.channel_live | type == "boolean") and (.channel_live == ([.seeds[] | .floor10_derived != .floor1000_derived] | any))' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```
PASS = exit 0. The predicate cannot be discharged by a run whose seed set excludes seed 8
(`index("8") != null`), cannot be discharged without the positive control
(`positive_control.channel_live == true` — rule (f)), and cannot be discharged by a fabricated
verdict (`channel_live` must equal the disjunction over its own rows). `seed_set_covers_divergent_point`
is asserted **positively** as `true`, never as the negation of `false`.

`channel_live == false` here licenses only: *"no derived-membership difference observable at
14/14 sampled points on the shipped fixture (variant 2), post-#41"* — **not** "the channel is
dead". Variant (2) has never had a divergent seed identified; the seed-8 prior is imported from
variant (3), which was **reverted** (`fusion_gate.py:35-43`).

---

### AC-322 (event-driven) — AMENDED (K-B17; the amend-01 command stands)
GIVEN the new tie-break-neutral floor-sensitivity fixture measured over the 7-seed C-2 protocol
WHEN the aggregate artifact is inspected
THEN the artifact shall record its seed set and state that the set cannot see the only known divergent point
VERIFY: prepend the command block below to amend-01's AC-322 chain; PASS exactly as stated.

The three commands and the disjointness predicate of `spec.criteria.amend-01.md`'s AC-322 are
**unchanged**. Two additions:

1. The aggregate artifact records `seed_set: ["0","1","2","3","4","5","unset"]`,
   `seed_set_covers_divergent_point: false`, and `divergent_point_known: "8"`.
   **C-2 is the correct protocol here** — AC-322 measures the *new* between-floors fixture,
   whose whole design is to make the floor's effect deterministic at every seed, so a
   seed-lottery point is not what it is looking for. The statement exists so a reader cannot
   mistake AC-322's C-2 set for VP-M1's evidence set.
2. Prepend to the VERIFY chain:
```
jq -e '(type == "object") and (.seed_set | type == "array") and ((.seed_set | length) == 7) and (.seed_set_covers_divergent_point == false) and (.divergent_point_known == "8")' /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-7seed-aggregate.json
```
PASS = exit 0. Non-disjointness still triggers **S-5 ⇒ S-13 class (c)** — and per
`spec.amend-02.md` §3.5 that is now the **expected** outcome, not the exception.

---

### AC-357 (event-driven) — ADDED (global rule (f); K-B17)

GIVEN the D5 derived-membership probe in `evals/floor_sensitivity_gate.py`
WHEN the probe is run at `floor = 2` against `floor = 1000` on the shipped fixture
THEN the probe shall emit `channel_live == true`
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.vp_m1_control(floor_low=2, floor_high=1000, seed_label='0'), '/app/evals/results/m1-positive-control.json')"
```
```
jq -e '(type == "object") and (.floor_low == 2) and (.floor_high == 1000) and (.low_derived | type == "array") and (.high_derived | type == "array") and (.low_derived != .high_derived) and (.channel_live == true) and (.self_check_ok == true)' /home/rynaro/workspace/oss/agents/crystalium/evals/results/m1-positive-control.json
```
PASS = exit 0 on both. `_build_fixture` places the only edge-bearing nodes `N1/N2/N3` at dense
ranks 1-3 and `F1..F12` at 4-15 (`fusion_gate.py:55-61`), so `dense_ranking[:2]` contains
`N1, N2` and **excludes `N3`** while `[:1000]` admits all 15 — the walk's seed set differs in
**membership by construction**, independent of hash order, so this control runs at a single
seed.

**If this control reports `false`, the probe is not instrumented and is not measuring derived
membership at all.** That is a **probe defect** (S-13 step 1), not a finding about the floor:
fix the probe and re-run. **No `channel_live == false` from an uncontrolled probe may be
recorded, carried, or cited (S-14).** This control's result is copied into
`vp-m1-floor-channel.json`'s `positive_control` object, which **AC-321 asserts**.

---

### AC-358 (event-driven) — ADDED (global rule (f); AC-322's instrument half)

GIVEN the pure disjointness classifier used by the floor-sensitivity gate
WHEN it is exercised on synthetic rank lists with no I/O
THEN it shall reach both branches and reject the empty-input case
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_floor_sensitivity_gate.py::test_disjointness_classifier_both_branches -v
```
PASS = exit 0. Node name is **normative**. The classifier is pure — no I/O, every branch
reachable from in-memory inputs (the `retrieval_gate.py:91-114` precedent). The node asserts
at minimum: `([0,0], [2,2]) ⇒ disjoint == true`; `([0,1], [1,2]) ⇒ disjoint == false`;
`([], []) ⇒ disjoint == false` (the K-B3 vacuity case, where `|[] − []| == |[]|` is `0 == 0`).

**Honest limit, recorded rather than papered over:** this discharges rule (f) for the
**instrument**, not for the **fixture**. Whether *any* fixture makes the floor change the fused
rank deterministically post-#41 is the open empirical question; a fixture-level positive
control would be circular (it *is* the gate passing), and inventing one would be **S-11**. Its
absence is exactly **S-5's trigger** and routes to **S-13 class (c)**.

---

### AC-359 (ubiquitous) — ADDED (K-B18)

GIVEN `evals/fusion_gate.py`'s module docstring at `:72-92`
WHEN the shipped source is read on the post-#41 tree
THEN the floor-channel liveness claim shall be dated as pre-#41 and identified as untested
since
VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import evals.fusion_gate as m
d = (m.__doc__ or '')
low = d.lower()
assert 'live and measured' in low, 'the superseded claim was DELETED; it must be dated, not erased'
assert '#41' in d, 'no reference to crystalium#41'
assert '56c8510' in d or 'pre-#41' in low, 'not dated as pre-#41 (config.py:304-308 pattern)'
assert 'single-seed cap' in low, 'does not name the mechanism #41 removed'
assert 'not been re-tested' in low or 'untested' in low, 'does not state it is untested post-#41'
print('ok')
"
```
PASS = exit 0 and the literal output `ok`.

The first assertion is deliberate: the superseded claim must be **dated, not deleted**. The
docstring states *"the failures are kept in this docstring on purpose: each one taught
something the final shape depends on"* (`fusion_gate.py:14-16`), and erasing a superseded claim
destroys the same record §3.1 exists to protect. The `config.py:304-308` precedent
(*"HISTORICAL (pre-#41 tree, 56c8510)"*) is the required form.

**Ownership:** the bytes belong to **W-G-XL**, whose module-docstring grant is extended from
`:104-106` to `:72-92` **and** `:104-106` (`spec.amend-02.md` §4). **W-G-FLOOR touches
`evals/fusion_gate.py` not at all** — FORGE D5's byte-untouched clause holds — but the
**claim** is #48's and is cited in its closing comment. AC-313's restructured freeze permits
this edit while byte-freezing three functions and two constants.

---

## Status index delta

| status | criteria |
|---|---|
| **REPLACED AGAIN** (2) | AC-313, AC-321 |
| **AMENDED** (1) | AC-322 |
| **ADDED** (3) | AC-357, AC-358, AC-359 |

`amend-01` left 52 criteria in force. `amend-02` replaces 2, amends 1, adds 3 ⇒ **55 criteria**
in force after `amend-02`.
