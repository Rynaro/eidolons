# Kupo critique — crystalium-residual-eight-plan

checker: `kupo` (maker `ramza`, C4 satisfied)
target: `/home/rynaro/workspace/oss/agents/crystalium` @ `b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc` (clean tree, verified)
method: read-only source verification, no container, no edits.

## Verdict: REJECT

Not because the plan is bad — the dependency analysis, the `retrieve.py`
contention finding, the §0.2 deconfound split and the §5 honesty section are
genuinely good and I could confirm most of them against source. It is REJECT
because **the critical path's first gate is GREEN on `b7f1a47` as specified**
(K-B1), which fires the plan's own STOP S-3 before any code is written, and
because **the checker-side perturbation table that AC-332 rests on cannot
discharge AC-332 for 5 of its 7 rows** (K-B9) — i.e. the mechanism this plan
invented to stop "gates that cannot fail" is itself a gate that cannot fail.

14 blocking findings, 21 non-blocking.

---

## Blocking findings (must fix before any code)

### K-B1 — G-XL's fixture is GREEN on `b7f1a47` as specified. The critical path halts at STOP S-3.

**Plan says** (spec.md:253-264, §4 #52):
> `episodic`: N weakly-matching crystals (**one query term each**) … `semantic`: one
> `sem-target` matching **every** query term … Today: `sparse_ranking == [ep1…epN,
> sem-target]` (per-layer append, `retrieve.py:521-530`), so `sem-target` fuses at
> rank N. **RED by construction.**

**Source says** (`mcp-server/src/crystalium/storage/relational.py:190-202`):
```python
def _fts5_query(raw: str) -> str | None:
    """... We extract word tokens and quote each as a literal term
    (implicit-AND across terms, preserving the prior multi-word semantics)."""
    toks = _FTS5_TOKEN.findall(raw or "")
    if not toks:
        return None
    return " ".join(f'"{t}"' for t in toks)
```
`bm25_search` passes that straight to `WHERE crystals_fts MATCH ?`
(`relational.py:513, 523, 536`). FTS5 space-separated phrases are **implicit
AND**, as the repo's own docstring states. A crystal carrying **one** of four
query terms therefore **does not match at all**.

**Consequence.** With the fixture as written, `bm25_search(query,
layer_filter="episodic", k=candidate_k)` returns **zero** rows.
`sparse_ranking == ["sem-target"]`. Dense arm empty, graph edgeless, completion
off ⇒ `weighted_rrf_merge_scored` (`retrieve.py:741-748`) sees exactly one
non-empty arm ⇒ `fused_ids == ["sem-target"]` ⇒ `records[0].id == "sem-target"`
⇒ **`target_rank == 0` ⇒ AC-310 RED ⇒ STOP S-3** ("The gate does not measure
the defect. STOP, redesign — do not proceed to W-45"). The 5-link critical path
`W-RIG → W-G-XL → W-45 → W-44 → W-42` (spec.md:125-128) dies at link 2.

Worse: **C-XL-1 (the single-layer control) passes for the wrong reason** in that
state — an empty episodic arm also puts `sem-target` at rank 0 under
`layers=["semantic"]`. So S-4 does not fire either. Only C-XL-2's
`len(sparse_ranking) == N+1` catches it, and that assertion exists in prose only
(see K-B4).

**Minimal fix.** Every episodic filler must match **all** query terms; the rank
separation must come from BM25 document-length normalisation / term frequency,
not from term *presence*. The shipped `fusion_gate` fixture is the precedent:
`_QUERY = "plarnix threxil vandomere signature"` and every non-target crystal has
**no** lexical overlap at all (`evals/fusion_gate.py:121, 161-170`) — that
fixture deliberately avoids partial matching because partial matching does not
exist here. Then re-derive the "RED by construction" claim, because it is now a
BM25-ordering claim, not a term-count claim, and it needs measurement.

---

### K-B2 — #42 names 2 of 4 seed-exclusion sites. `exclude_seeds=False` as specified is a no-op at depth 1 — exactly the case the oracle uses.

**Plan says** (spec.md:365-368, §4 #42):
> When `False`: `_neighbor_expand_one_hop` drops the `if neighbor_id not in
> seed_ids` filter (`graph.py:225`) and `decaying_walk` seeds `visited = set()`
> instead of `set(seed_ids)` (`graph.py:302`)

Both anchors are **correct**. The list is **incomplete**. `graph.py:255-278`:
```python
255        original_seeds = set(seed_ids)
...
264        result_ids: set[str] = set()
265        frontier = list(dict.fromkeys(seed_ids))
266        visited = set(frontier)
...
271            hop_ids = self._neighbor_expand_one_hop(frontier, rel_filter)
272            hop_ids -= original_seeds
```
Line **272** re-subtracts the seeds *after* `_neighbor_expand_one_hop` returns.
It was introduced by #41 and the comment at `graph.py:257-263` says so
explicitly: *"keeps the original seeds excluded at every hop, not just the
first"*. Dropping only the `:225` filter leaves seed exclusion **fully in
force**.

`decaying_walk` is worse: it does not do its own expansion, it calls
`self.neighbor_expand(sorted(frontier), depth=1)` (`graph.py:305`). At hop 1
`frontier == seed_ids`, so that call's own `original_seeds` **is** the walk's
seed set and line 272 removes them regardless of `visited`. Setting
`visited = set()` at `:302` changes nothing at hop 1.

**Consequence.** The plan's oracle (spec.md:373-375) is *"a fixture where a seed
is reachable from another seed"* — a **depth-1** relation. On that fixture the
specified `exclude_seeds=False` implementation is byte-identical to
`exclude_seeds=True`. AC-350 stays green under both, AC-351's red-check
("flip the default → AC-350 must go RED") **fails to go red**, and the
verification-plan §4 checker row for #42 ("remove the `visited = set()` half
only — the `decaying_walk` half … must go red independently") **cannot go red
at all**.

**Minimal fix.** Enumerate all four sites — `graph.py:225` (the one-hop filter),
`graph.py:266` (`visited = set(frontier)`), `graph.py:272`
(`hop_ids -= original_seeds`), `graph.py:302` (`visited = set(seed_ids)`) — and
note `_neighbor_expand_one_hop` needs the parameter too (§4 only adds it to
`neighbor_expand` and `decaying_walk`). Then re-check that
`exclude_seeds=True` is still byte-identical.

---

### K-B3 — AC-322 / AC-317 / VP-M4 cannot realise the C-2 seed protocol. `PYTHONHASHSEED` is fixed at interpreter startup.

**Criteria say** (spec.criteria.md:20-21):
> **Seed protocol (C-2).** "7 seeds" always means `PYTHONHASHSEED` in `0 1 2 3 4 5`
> plus one run with the variable unset.

**AC-322's command** (spec.criteria.md:142):
```
docker compose run --rm crystalium /app/.venv/bin/python -m evals floor-sensitivity-gate --seeds 7 | jq -e '...'
```
One process. `PYTHONHASHSEED` is read by CPython **before** `main()` and cannot
be re-seeded from inside a running interpreter. A single `--seeds 7` invocation
samples **one** hash seed seven times. Every other seed-protocol command in this
plan gets this right by spawning per seed — VP-B3 (`verification-plan.md:37`),
AC-344 (`spec.criteria.md:220`), VP-M1 (`verification-plan.md:58-63`) all use
`docker compose run --rm -e PYTHONHASHSEED=$s`. AC-322 is the exception and it is
the **primary oracle for #48** with STOP S-5 hanging off it.

Same defect in VP-M4 (`verification-plan.md:91`): *"3 weights × 7 seeds = 21
cells"* driven from AC-317's single `-m evals weight-discrimination` invocation
(spec.criteria.md:113).

**Second defect in the same AC — the jq passes vacuously on an empty list.**
```
([.floor10[]]|unique) as $a | ([.floor1000[]]|unique) as $b | ([$a[]] - [$b[]] | length) == ($a|length)
```
The subtraction direction and symmetry are **correct** — `|$a − $b| == |$a|` iff
`$a ∩ $b = ∅`, and since both are `unique`d this is genuine disjointness. But
when `$a == []` it evaluates `0 == 0` ⇒ **true** ⇒ exit 0. A gate that emits
`floor10: []` (fixture failed to build, target never retrieved, exception
swallowed) **passes AC-322**. A missing key errors out (jq cannot iterate null),
so only the empty-array case is silent — which is exactly the failure mode a
broken fixture produces.

**Minimal fix.** Drive AC-322 from a shell loop over `-e PYTHONHASHSEED=$s`
exactly like AC-344, aggregate the 7 JSON outputs, and add
`and ($a|length) > 0 and ($b|length) > 0` to the predicate.

---

### K-B4 — AC-310 (the critical-path gate) passes on `null` and on `-1`; AC-312's liveness omits the one assertion that would catch K-B1.

**AC-310** (spec.criteria.md:71): `jq -e '.target_rank != 0'`.

The repo's own convention for "target absent" is `-1`
(`evals/fusion_gate.py:255`: `target_rank = retrieved.index(target_id) if
target_id in retrieved else -1`). `jq -e '-1 != 0'` → exit 0. And
`jq -e 'null != 0'` → **also exit 0**. So AC-310 passes when:
- the layer-append defect is present (intended), **or**
- the fixture never inserted `sem-target`, **or**
- `recall` returned zero records, **or**
- the gate emits `target_rank: null` because it crashed and defaulted.

It cannot distinguish the defect from a broken fixture. This is the change
folder's named recurring defect (spec.md:675, NC-1: *"Two prior ACs exited 0
comparing `null` to `null`"*) reproduced in the campaign's most load-bearing
criterion.

**AC-312** (spec.criteria.md:83) checks
`.liveness.edge_count==0 and .liveness.corpus_per_layer < .liveness.candidate_k
and .liveness.dense_arm_size==0`. spec.md:282-283 (C-XL-2) additionally demands
`len(sparse_ranking) == N+1`. **That assertion is in prose only and appears in
no acceptance criterion.** It is the single assertion that catches K-B1.

**Minimal fix.** `jq -e '.target_rank > 0'` (or `== .expected_blocked_rank`), and
add `.liveness.sparse_arm_size == (.liveness.corpus_per_layer + 1)` to AC-312.

---

### K-B5 — AC-345 and AC-346 are mutually exclusive on any single tree, yet VP §5 requires both green.

- **AC-345** (spec.criteria.md:226): `pytest …::test_prefix_baseline_starves_active_hits`
  — *"PASS = exit 0 **on the pre-fix tree**"*.
- **AC-346** (spec.criteria.md:232): `pytest …::test_topup_recovers_active_hits`
  — the same file, post-fix.

Both nodes live in `mcp-server/tests/test_sparse_status_topup.py`, which §2
(spec.md:165) assigns exclusively to **W-44 — the unit that ships the fix**. So
the file only exists on a post-fix tree, where `test_prefix_baseline_starves_active_hits`
asserts starvation that no longer happens ⇒ RED.

`verification-plan.md:184` then says: *"v2.1.0 (behaviour) — [ ] AC-340..AC-353
green"*. AC-345 and AC-346 cannot both be green on the tree that gets tagged.
No xfail, no marker, no "delete after" instruction is given.

**Minimal fix.** Make AC-345 a *characterisation captured before W-44 lands*
(a recorded artefact like `red-evidence.txt`, not a shipped pytest node), or ship
it as `@pytest.mark.xfail(strict=True)` post-fix with an explicit reason.

---

### K-B6 — AC-319/AC-320's "§D2 bitwise identity harness" does not exist, has no CLI subcommand, and is owned by no unit.

**Plan says** (spec.md:455-457, §4 #55 item 2):
> **item 2:** **re-run** the §D2 bitwise identity harness (20 in-process
> comparisons) on the current tree … a **cheap refresh, not a blocker**.

**AC-319** (spec.criteria.md:125): `python -m evals d2-identity | jq -e '.comparisons==20 and .max_abs_diff==0'`.

Source at `b7f1a47`:
- `ls evals/` → no `d2_identity.py` (modules present: ablation, ab_memory_onoff,
  dedup_gate, dream_gate, evb_gate, fixture_repo, forgetting_gate, fusion_gate,
  metrics, missions, poisoning_gate, poisoning_resistance, prefetch_gate,
  retrieval_gate, selective_forgetting).
- `evals/__main__.py` subparsers (lines 155-206): canary, ab, axes, forget,
  evb-gate, dream-gate, forgetting-gate, retrieval-gate, fusion-gate, dedup-gate,
  prefetch-gate, poisoning-gate. **No `d2-identity`.**
- The only trace of the measurement is prose: `config.py:292-293`
  *"bitwise: 20/20 in-process comparisons, exact 0.0 score diff, measured on the
  #38 tree"* — a **recorded result**, not a re-runnable harness.

So "re-run" is false; it must be **built**. §2's ownership table (spec.md:155-167)
assigns no unit `evals/d2_identity.py`, and W-CLI owns `evals/__main__.py` but is
scheduled *after* W-G-WD, so W-G-WD cannot register the subcommand it needs.
AC-319 and AC-320 are unexecutable and unassigned; §7 nonetheless ships "#55
items 2+3" in v2.0.2.

**Minimal fix.** Either add `evals/d2_identity.py` to W-G-WD's exclusive
ownership and re-scope item 2 from "cheap refresh" to "new harness", or drop
AC-319/AC-320 and close #55 on items 1+3 alone.

---

### K-B7 — AC-321 demands fields VP-M1's own command cannot produce, and is a pure shape check on a file the maker writes.

**AC-321** (spec.criteria.md:136):
```
jq -e 'has("floor10_derived") and has("floor1000_derived") and has("channel_live")' CHANGE/vp-m1-floor-channel.json
```
**VP-M1's command** (verification-plan.md:58-63) calls
`run_floor_probe(floor=…, weighted=False)`.

`run_floor_probe` **does exist with that signature** — `evals/fusion_gate.py:290-292`,
keyword-only (`*, floor: int, weighted: bool, data_root: str = …`), and VP-M1
passes them as keywords. That part of the plan is correct.

But it returns `run_arm(...)`'s dict, and `run_arm` returns exactly
(`evals/fusion_gate.py:266`):
```python
return {"target_rank": target_rank, "retrieved": retrieved, "cross_layer": cross_layer}
```
There is **no derived-arm field**. `run_arm` never passes `explain=True` to
`recall` (`fusion_gate.py:250-253`), so `explain.fusion.arm_sizes.derived`
(`retrieve.py:1098-1104`) is never surfaced. `floor10_derived` /
`floor1000_derived` are unobtainable from the named measurement.

Separately: `has(...)` is a **shape** predicate. AC-321 passes if the three keys
exist with any values — including fabricated ones. It cannot fail on the
measurement being wrong. VP-M1 is described as *gating the whole W-G-FLOOR unit*
(verification-plan.md:50).

**Minimal fix.** Either drop to `channel_live` derived from the `retrieved` lists
the probe actually returns (and rename the AC's fields accordingly), or extend
`run_floor_probe` — which then makes `evals/fusion_gate.py` a W-G-FLOOR edit,
which §2 (spec.md:162) declares **UNTOUCHABLE** for that unit. Pick one; as
written the two documents contradict.

---

### K-B8 — AC-306 and S-10 read `fence-amend.json`; §2 and §8 produce `fence-amend.md`.

- spec.md:158 (§2 ownership): W-HOP owns `…/fence-amend.md`.
- spec.md:631 (§8 Wave 0): *"`fence-amend.md` records ALLOW or DENY"*.
- spec.criteria.md:61 (AC-306): `jq -e '.verdict=="ALLOW" or …' CHANGE/fence-amend.json`.
- verification-plan.md:135 (S-10): `fence-amend.json.verdict == "DENY"`.

`jq` on a markdown file errors (exit 2/5). AC-306 is unsatisfiable by the artefact
the plan's own work unit produces, and W-44's entry precondition (spec.md:655,
"W-HOP = ALLOW") is therefore never mechanically established.

**Minimal fix.** Make W-HOP emit `fence-amend.json` (machine-readable verdict)
with a `.md` narrative sibling, and say so in §2 and §8.

---

### K-B9 — the checker-side perturbation table cannot discharge AC-332 for 5 of its 7 rows.

`verification-plan.md:141-163` is the mechanism that makes NC-2/AC-332 real
(*"a red-evidence file the checker did not reproduce is a claim, not evidence"*,
spec.md:597-598). As the CHECKER I am the consumer of this table. It does not work.

| row | verification-plan.md line | defect |
|---|---|---|
| cross-layer (#52) | :155 | The maker's cell is *"assert on today's build (red by construction)"* — **not a perturbation at all**. The checker's cell says *"move `sem-target` into `procedural` — rank must still be non-zero"*, i.e. it is designed to keep the gate **RED**. AC-332 requires *"each gate shall go red under the checker's own perturbation"*; a perturbation that preserves red proves nothing about the gate's ability to go green. It is also a duplicate of AC-343's maker-authored `test_relocated_target_control`. **`_ALL_LAYERS` order is `["episodic","semantic","procedural","execution"]` (`retrieve.py:44`), so moving the target from `semantic` to `procedural` moves it *later* in the append order — the outcome is unchanged by construction.** |
| corpus-scaling (#47) | :156 | Maker: *"shrink the corpus"*. Checker: *"raise `k` so `candidate_k > M`"*. `candidate_k = max(k*3, FETCH_WIDTH_FLOOR)` (`retrieve.py:503`). Both move the **same single inequality** `M vs candidate_k`, one from each side. This is the maker's test with the algebra transposed, not an independent perturbation. |
| floor-sensitivity (#48) | :158 | Checker: *"run both probes at floor 1000"*. spec.md:422 gives the maker's second red-check as *"Second: run both probes at `floor=10` → RED."* **Same perturbation, different constant.** Direct violation of the table's own "must differ" rule. |
| status top-up (#44) | :159 | Checker: *"mark every fixture crystal active — the top-up must not fire"*. If nothing is inactive there is no starvation, so AC-346 is **green**, not red. This row makes no gate red; it is a negative control mislabelled as a red-check. |
| seed exclusion (#42) | :160 | Blocked by **K-B2**: `decaying_walk` delegates seed exclusion to `neighbor_expand` (`graph.py:305` → `:272`), so *"remove the `visited = set()` half only"* cannot flip the byte-identity test at depth 1. The wording is also self-inverting — under `exclude_seeds=False` the code *sets* `visited = set()`; "removing" it restores today's behaviour, which is byte-identical ⇒ green. |
| weight-discrimination (#55) | :157 | Cross-labelled: the maker's cell (1-ULP) belongs to **item 2's D2 harness** (AC-320), the checker's cell (`w_derived = 100.0`) tests **AC-352's `p1_recreated`**. Neither is a red-check on the G-WD gate itself (AC-317), which is given **no** perturbation anywhere in the plan. |
| entrypoint (#57) | :154 | Works, but is strictly **weaker** than the maker's: renaming the `serve` subcommand kills the subprocess, which a liveness-only test would also catch. It cannot validate that the handshake is genuinely parsed — the property AC-303 exists to protect. |

**And the count is wrong.** AC-332 (spec.criteria.md:181) asserts
`length == 4`. The v2.0.2 batch (spec.md:584) contains **five** red-checkable
artefacts — W-ENTRY plus the four gates — and the table has five v2.0.2 rows.
`length == 4` silently excludes the entrypoint gate from the mechanical count.

**Separately, AC-332 is a self-attestation.** It reads
`CHANGE/checker-redcheck.json` for `independently_reproduced: true`. A checker
who replayed `red-evidence.txt` writes the identical file. The AC cannot fail on
the defect it names.

**Minimal fix.** Replace 5 rows with perturbations that (i) differ from the
maker's *axis*, not its constant, and (ii) are asserted to flip the gate to RED.
Change `length == 4` to `length == 5`. Require `checker-redcheck.json` to carry,
per gate, the **command run and its captured non-zero exit** rather than a
boolean.

---

### K-B10 — AC-348 ("≤1 extra `bm25_search` per recall") is incompatible with #45 Option B, which §4 leaves undecided.

The sparse fetch is inside a **per-layer** loop (`retrieve.py:521-530`):
```python
for layer in target_layers:
    bm25_hits = self.relational.bm25_search(query, layer_filter=layer, k=candidate_k)
```
Under **Option B** (spec.md:305-306: *"Keep the per-layer loop, interleave …"*)
that loop survives. A status-aware top-up at a widened `k` would then need **one
extra call per layer** (or one `layer_filter=None` call plus a post-filter, which
is Option A by another name). AC-348 (spec.criteria.md:243) asserts *"at most one
additional `bm25_search` per recall … by call count on a spy"* ⇒ **RED under
Option B**.

Only Option A collapses the fetch to a single global call and makes AC-348
coherent. §4 explicitly declines to pre-decide (spec.md:289-290: *"the plan does
not pre-decide"*), and W-44's entry precondition (spec.md:655) is only "W-45
merged" — it does not require Option A. The censoring recompute described at
spec.md:331-334 has the same problem: `cap = candidate_k * len(target_layers)`
(`retrieve.py:597`) is an aggregate over layers, so "recompute against the
widened fetch" is only well-defined for a single global fetch.

**Minimal fix.** Make Option A a **precondition** of W-44 and say so in the
dependency graph, or state the per-layer variant of AC-348
(`≤ len(target_layers)` extra calls) and accept that #44's cost bound weakens.

---

### K-B11 — S-12 can never fire through the tool it names, and VP §5's invocation would diff the wrong repository.

**S-12** (spec.md:576): *"Any unit's diff touches a file another unit exclusively
owns (§2) → DRIFT. `ramza-drift --amend --reason` or revert."*
**verification-plan.md:137**: *"`ramza-drift --range <base>..<head>` reports a file
outside the unit's declared ownership"*.

`ramza-drift --help` (`.eidolons/ramza/bin/ramza-drift`):
> `ramza-drift --state FILE --declare 'GLOB [GLOB...]'` … *"Scope entries are
> shell globs matched against repo-relative paths … The check exits 1 and
> reports every changed file **not covered by the declared scope**"*

It checks against **one plan-level `declared_scope`**, not per-unit exclusivity.
The frozen scope in `.spectra/plans/crystalium-residual-eight-plan.state.json` is:
```
retrieve.py, graph.py, config.py, mcp-server/tests/*, evals/*,
CHANGELOG.md, pyproject.toml, __init__.py, .spectra/changes/…/*
```
Every §2 ownership violation — W-G-FLOOR touching `evals/fusion_gate.py`,
W-45 touching `evals/__main__.py`, W-42 touching `mcp-server/tests/test_fusion_gate.py`
— lands **inside** that scope and reports clean. The union of all units' files *is*
the plan scope; a cross-unit overlap is structurally invisible to this tool.

**Second, concrete defect.** `ramza-drift` defaults `REPO="."` (line 30 of the
script). `verification-plan.md:175` writes
`ramza-drift --state … --range v2.0.1..HEAD` with **no `--repo`**, and the state
file lives in the *nexus*. That command diffs the **nexus**, not crystalium, and
`v2.0.1` is a crystalium tag. It will either error on an unknown ref or report a
clean nexus diff — a convincing, silent zero.

**Minimal fix.** Add `--repo /home/rynaro/workspace/oss/agents/crystalium` to
every `ramza-drift` invocation, and replace S-12's mechanism with a per-unit
check: the branch diff's file list must be a subset of that unit's §2 row (a
plain `git diff --name-only <base>..<head>` compared against a literal list).

---

### K-B12 — AC-333/AC-362 are already satisfied, are not observable from the command they name, and AC-362 is unsatisfiable by the shipped tool.

**AC-333** (spec.criteria.md:187):
`./.eidolons/ramza/bin/ramza-gate status --state …state.json` — *"PASS = a critic
record is present with `author != checker`"*.

Three defects, all verified by running the read-only command:

1. **`status` does not print the critic.** Actual output:
   `{plan, tier, phase, next, refine_cycles, skips, criteria_frozen}`. The critic
   exists in the state file but the named command never surfaces it. The stated
   PASS condition is not observable from the stated VERIFY command.
2. **It already passes, today, before any code.** The state file carries
   `"critic": {"author": "ramza", "checker": "kupo", "at": "2026-08-05T21:35:30Z"}`
   — written by the maker at plan time. AC-333 says *"GIVEN the v2.0.2 release …
   THEN the system shall record a critic whose identity differs from the author"*.
   It is satisfied before v2.0.2 exists. Cannot fail on the defect it names.
3. **AC-362 is unsatisfiable.** It requires *"a **second** critic record"*.
   `ramza-gate` writes (line 164):
   `write_state '.critic = {author: $a, checker: $c, at: $at}'` — a **single
   object, overwritten**. Recording the v2.1.0 critic destroys the v2.0.2 one.
   There is no `critics[]` array.

**Minimal fix.** VERIFY with `jq -e '.critic.author != .critic.checker'` on the
state file directly, timestamp-bind it (`.critic.at > <v2.0.2 tag date>`), and
for AC-362 either store the two critic records in the change folder
(`checker-redcheck.json` already exists as a per-batch artefact) or accept one
record per batch with an explicit re-record step.

---

### K-B13 — `config.py` is required by AC-370 but owned by no unit; and #44's top-up is dead code unless `recall_active_only=True`, a pin no criterion states.

**(a) Ownership hole.** AC-370 (spec.criteria.md:316) requires an edit to
`mcp-server/src/crystalium/config.py`, and §7 (spec.md:584) puts *"config-comment
disposition"* in the v2.0.2 batch. §2's ownership table (spec.md:155-167) assigns
`config.py` to **no unit**. The frozen `declared_scope` *does* include it, so
drift stays green — meaning nobody owns it and nothing notices. §4 #42
(spec.md:369) also anticipates a new `Config.recall_seed_derived_credit`, also
unowned.

**(b) The #44 top-up cannot fire at default config.** §4 #44 (spec.md:326-327):
> count candidates failing `_is_active` (the predicate already defined at
> `retrieve.py:572-584`)

The anchor is **correct** — `_is_active` is defined at `retrieve.py:572-584`,
caller-side, exactly as claimed. But its first two lines are:
```python
572            def _is_active(crystal: dict[str, Any]) -> bool:
573                if not self.recall_active_only:
574                    return True
```
and `recall_active_only: bool = False` is the constructor default
(`retrieve.py:307`). With the flag off, `_is_active` is **unconditionally True**,
`n_inactive_observed == 0`, and the top-up **never fires**. The whole of #44 is
conditional on `recall_active_only=True`.

That pin appears **nowhere**: not in §0.2's deconfound table (spec.md:74-78), not
in §4 #44's fixture description, not in AC-345/346/347/348, and not in the shipped
`fusion_gate` template the rig is copied from — which sets
`recall_active_only=False` explicitly (`evals/fusion_gate.py:243`).
The checker perturbation for this gate (*"mark every fixture crystal active"*,
verification-plan.md:159) is a **no-op** under the default, which is one reason
that row cannot go red (K-B9).

**(c) The censoring claim is right, and that is load-bearing.** §4 #44's
statement that the censoring test is *"a property of the fetch actually
performed"* (`retrieve.py:229-237`) is **verbatim correct** — `retrieve.py:230-233`
says exactly that, and `retrieve.py:256` is `if raw_n_sparse == 0 or raw_n_sparse
>= cap:`. So the "recompute against the widened fetch" reasoning is coherent.
The design is sound; only the flag pin is missing.

**Minimal fix.** Assign `config.py` to a unit (a new W-DOC, or W-REL-A). Add
`recall_active_only=True` as an asserted pin in the #44 fixture and in AC-345/346.

---

### K-B14 — every gate criterion runs `python -m evals <gate>`, but W-CLI (which owns `evals/__main__.py`) is a **trailing** unit gated on all four gates.

**spec.md:136-138 (§1):**
> each gate module is self-contained and is driven from its pytest wrapper by
> **direct import** (the `test_fusion_gate.py:18` precedent). CLI registration is
> one trailing unit, **W-CLI**, which owns `evals/__main__.py` exclusively.

**spec.md:644 (§8 Wave 1):** `W-CLI | entry precondition: **all four above**`.

But AC-310, AC-312, AC-314, AC-317, AC-319, AC-322 (spec.criteria.md:71, 83, 95,
113, 125, 142) are all `/app/.venv/bin/python -m evals <gate-name>` commands, and
they are the **exit gates of the units that precede W-CLI** (spec.md:640-643).
Those commands cannot run when their own unit's exit gate fires. VP-M2/M3/M4/M6
(verification-plan.md:74-103) have the same problem.

The `test_fusion_gate.py:18` precedent the plan cites is **correct**
(`from evals.fusion_gate import run, run_floor_probe`) — but the criteria did not
follow it.

**Minimal fix.** Express the Wave-1 gate criteria as `python -c "import
evals.cross_layer_gate as m; print(json.dumps(m.run()))" | jq …`, and keep the
`-m evals …` form only for W-CLI's own exit gate (spec.md:644).

---

## Non-blocking findings

**K-N1 — AC-318's docstring assertion is trivially satisfiable.**
`spec.criteria.md:119`: `assert 'DP-1' in d and 'not' in d.lower()`.
`'not' in d.lower()` matches **"notes", "nothing", "notably", "cannot", "note",
"annotation"**. A first paragraph reading *"DP-1(b) note: this module
characterises the sub-1.0 band"* passes while asserting precisely what §5.2
forbids. The AC cannot fail on the defect it names. Fix: assert a fixed
sentinel string, e.g. `'NOT band characterisation' in d`.

**K-N2 — AC-373 does not check the eight target issues.**
`spec.criteria.md:333`: `gh issue list --state open --limit 30 --json number | jq -e 'length == 0'`
asserts **zero open issues repo-wide**. It goes red for any unrelated issue
filed during the campaign — and this plan *expects* new filings (§5's
*"re-file against the fence itself"* for #44 under S-10; §5.1's WONTFIX reopen
note; the #41 follow-up family). It also caps at `--limit 30`. Fix:
`gh issue view <N> --json state` per target, or
`jq -e '[.[].number] - [42,44,45,47,48,52,55,57] | length == ([.[].number]|length)'`.

**K-N3 — AC-371 greps the wrong directories and the wrong string.**
`spec.criteria.md:322`: `grep -rn "retrieval gate" docs/ evals/`. Verified: exits
**1** today. The required statement already exists — at `config.py:311-312`:
> *"NOTE for future sweeps: the FUSION gate cannot express weight sensitivity
> (target/Z at k=2); only the retrieval gate is informative."*
— which is outside the grep's scope. Meanwhile the grep matches **any** line
containing "retrieval gate" for any reason, while the PASS condition is about
*"naming the fusion gate as uninformative"*. It can pass with the required
statement absent. And no unit owns `docs/` or a generic evals note.

**K-N4 — AC-370's grep is case-sensitive against an uppercase source.**
`grep -n "unsupported" config.py` → exit **1** today; the file says
`UNSUPPORTED` (`config.py:299`). So the AC forces a *new* lowercase line
restating what `config.py:296-312` already says at length. The anchor
`config.py:296-312` cited in spec.md:541 is **correct** and its content matches
the plan's claim.

**K-N5 — AC-331's escape hatch is not mechanical and is load-bearing.**
`spec.criteria.md:175`: `git diff v2.0.1..HEAD --name-only -- mcp-server/src/` —
*"PASS = output is empty **or** contains only comment-only diffs, each
demonstrated by `git diff -w -U0` showing no non-comment line."*
`--name-only` emits filenames; it cannot show comment-ness. `git diff -w -U0` is
whitespace-ignoring zero-context — **not** a comment filter. And the hatch *must*
be used, because AC-370 mandates a `config.py` edit under `mcp-server/src/`. So
the v2.0.2 "zero production-code change" claim rests on a human eyeball.

**K-N6 — AC-313's filter has a vacuous-pass mode and forbids the correction #52 is about.**
`spec.criteria.md:89`. The pipeline's exit status is the last `grep`'s, and *no
output* is the PASS condition — so a **deleted or renamed** `evals/fusion_gate.py`
also produces no output and passes. Separately, the filter drops lines matching
`cross_layer`, but `fusion_gate.py:104-106`'s module docstring says
*"the **cross-layer** sparse-arm rank is reported per layer"* (hyphen, not
underscore) — correcting that misleading sentence, which is the entire point of
#52 item 2, would surface as unfiltered diff output and **fail AC-313**.

**K-N7 — AC-324 (2nd half) and AC-341 are unverifiable at this plan's own hop placement.**
spec.md:601 puts the checker hop *"after the last unit of a batch merges to a
release branch"*. AC-324 (spec.criteria.md:153) says
`git diff b7f1a47 -- evals/fusion_gate.py` — *"PASS = no output **for the
W-G-FLOOR branch**"*; post-merge that diff is non-empty by design (W-G-XL's
mandated rename). AC-341 (spec.criteria.md:203) says `git show --stat HEAD` must
touch both `retrieve.py` and `test_cross_layer_gate.py`; post-merge `HEAD` is not
W-45's commit, and under a squash merge `HEAD` touches everything and passes
vacuously.

**K-N8 — §2's declared edit ranges for the `cross_layer` rename are short by one site.**
spec.md:159 grants W-G-XL `evals/fusion_gate.py:257-266` +
`test_fusion_gate.py:31-39`. Verified consumers of the key:
`fusion_gate.py:257, 262, 266, **281**` and `test_fusion_gate.py:35-39`
(line 31 is the `def`). **Line 281** (`"cross_layer": weighted["cross_layer"],`
inside `run()`) is outside the granted range — renaming without it breaks
`run()`; renaming with it is an S-12 fence breach as written.

**K-N9 — AC-312 contradicts §4 #52's own permitted fixture variant.**
spec.md:258-259 permits the dense stub to return *"`[]` (**or a neutral fixed
list** containing neither target nor a competitor)"*. AC-312
(spec.criteria.md:83) asserts `.liveness.dense_arm_size==0`, which the second
variant fails.

**K-N10 — AC-316 cannot detect the defect it names.**
`spec.criteria.md:107` runs `python -c "from … import FETCH_WIDTH_FLOOR; assert
FETCH_WIDTH_FLOOR==10"` in a **fresh process**. The realistic failure is a gate
that monkeypatches `retrieve_mod.FETCH_WIDTH_FLOOR` and forgets to restore it —
the shipped `fusion_gate.py:227-229, 264` does exactly this patch/restore dance in
a `try/finally`. A gate that drops the `finally` still passes AC-316. Anchor
verified: `retrieve.py:52` is `FETCH_WIDTH_FLOOR: int = 10`.

**K-N11 — `Makefile:34` is the target label, and `make test-ci` is not mechanically CI.**
spec.md:88 cites `Makefile:34`. Line 33 is the `## test-ci:` doc comment, line 34
is the bare target label `test-ci:`, line 35 is the recipe. Off by one either way.
The substantive claim **holds**: `Makefile:35` is
`$(RUN) env CRYSTALIUM_SKIP_SLOW=1 pytest mcp-server/tests/ -v` (SKIP_SLOW with
slow still selected), and `.github/workflows/ci.yml:39-44` runs
`docker run --rm -e CRYSTALIUM_SKIP_SLOW=1 crystalium:dev pytest tests/ -v` — no
`-m "not slow"`. But they are **not the same invocation**: CI uses `docker run` on
the **baked** image (`PYTHONPATH=/app/src:/app`, `COPY mcp-server/tests ./tests`),
`make test-ci` uses `docker compose run` with a **bind mount** that shadows
`/app` (`PYTHONPATH=/app/mcp-server/src:/app`). Same test set, different source
of truth. Given this repo's memory of `__version__`-from-METADATA (NC-6) and
"cached images hide dependency breaks", worth stating rather than implying
equivalence.

**K-N12 — no gate in this plan can detect Option A's real regression.**
§4 #45 Option A (spec.md:294-299) is verified feasible: `bm25_search` accepts
`layer_filter=None` and orders globally by `bm25(crystals_fts)`
(`relational.py:495-499, 530-541` — anchor `531-541` **correct**), and
`dense_search(layer_filter=None)` is likewise supported
(`vector.py:174-179, 199-200` — anchor `174-199` **correct**). The unstated risk:
with `layer_filter=None` + post-filter, a **strict layer subset** can recover
*fewer* rows than today, because the global top-`N` may be dominated by
non-target layers. §4 frames this only as *"`cap` … change meaning"*. G-XL uses
`layers=None` and G-CORPUS uses a single-layer store — **neither can see it**.
A `layers=["semantic"]` query against an episodic-heavy corpus is the missing gate.

**K-N13 — the baseline the plan requires as its Wave-0 entry precondition was never captured.**
`CHANGE/baseline-suites.txt` is 5 lines: the VP-B5 HEAD hash and an empty
`### VP-B1 make test` header. `baseline-fusion-7seed.json` and
`baseline-retrieval.json` (VP-B3/VP-B4, verification-plan.md:37-38) **do not
exist**. spec.md:622 makes *"`make test` and `make test-ci` both green at
baseline (captured)"* the Wave-0 entry gate, and verification-plan.md:41 makes
7/7 `gate_pass` a STOP. Neither has an input.

**K-N14 — the ESL record itself is non-conformant.**
`change.json`: `"acceptance_checks": []` (49 criteria live only in a sibling
markdown), `"has_code": false` (this is a code campaign; the ESL code-state
gates will skip), `"status": "proposed"`. `mcp__tonberry__verify` → **C3 fail:
`full: missing spec.yaml`**.

**K-N15 — AC-352 has no mechanical positive control.**
`spec.criteria.md:266` reads `.p1_recreated == false` from a field the maker's own
module computes. A degenerate fixture reports `false` and passes. The positive
control that would make it falsifiable (`w_derived = 100.0` ⇒ `p1_recreated:
true`, per `config.py:296-298`) exists **only** in the verification-plan's
suggestion table, not as an AC. STOP S-1 hangs off AC-352.

**K-N16 — AC-361/VP-M8 ignore a tool that already exists.**
`.spectra/changes/archive/2026-08-05-crystalium-mcp-sdk-2x-39/` contains
`golden_wire.py`, `golden-wire-v1.11.0.json` **and `compare_wire.py`**. VP-M8
(verification-plan.md:112-118) names only `golden_wire.py` and then asks for a
human-judged `diff` (*"differences confined to `result.content` payload
ordering"*) — non-mechanical. `compare_wire.py` is never mentioned.

**K-N17 — AC-344's "unset" seed has no defined command form.**
`spec.criteria.md:220`: *"for `s` in `0 1 2 3 4 5` and unset —
`docker compose run --rm -e PYTHONHASHSEED=$s …`"*. There is no `$s` value that
means "unset"; `-e PYTHONHASHSEED=` sets it empty, which is not the same thing.
The 7th run must **omit `-e` entirely**. Same in VP-B3.

**K-N18 — AC-363 has no `cd`.** `spec.criteria.md:300`:
`git show --stat HEAD -- roster/mcps.yaml roster/index.yaml`. Those files live in
the **nexus**; the criteria's stated convention (line 13) is *"Every command runs
as `docker compose run --rm crystalium …` from MAIN"*. Every other nexus-side
command in the file carries an explicit path (AC-364 does). This one does not.

**K-N19 — AC-304 and AC-324 use `grep -c` whose PASS condition is exit 1.**
`grep -c pattern file` exits **1** when the count is 0. Both ACs state
*"PASS = output `0`"*, so they are technically self-consistent — but they
contradict the file's own convention (line 17: *"'PASS' means exit `0` unless
stated"*) and will read as failures under any `set -e` harness. Use
`test "$(grep -c … || true)" = 0`.

**K-N20 — S-8 is either vacuous or spurious for half the gates.**
spec.md:572: *"**Any** new gate passes on the pre-fix tree → It is not a gate."*
G-WD and G-FLOOR have **no fix** they precede — they are characterisation
instruments, and G-CORPUS's own red-check (spec.md:489) *requires* it to go
**GREEN** at small corpus on the pre-fix tree. As worded S-8 fires on the
plan's own mandated controls.

**K-N21 — minor anchor drift, substance intact.**
`test_server.py:159-178` (spec.md:236) straddles two tests —
`test_http_transport_builds_app` (158-168) and `test_http_smoke_initialize`
(170-…). The claim (*"`build_http_app` ASGI covers app construction … the
uncovered surface is `uvicorn` startup + port binding"*) is **accurate**;
`test_http_smoke_initialize` even exercises the Streamable-HTTP request path via
`TestClient`, which strengthens the plan's recommended disposition.

---

## Anchors verified correct

Opened and read at `b7f1a47`; each says what the plan claims:

| anchor | plan's claim | verdict |
|---|---|---|
| `retrieve.py:521-548` | single loop, per-layer fetch + `candidate_k` truncation | **correct** (`for layer in target_layers:` → `bm25_search(layer_filter=layer, k=candidate_k)` + `dense_search(...)`). Nit: it iterates `target_layers`, which equals `_ALL_LAYERS` only when `layers` is falsy (`:492`). |
| `retrieve.py:521-530` | per-layer sparse append | **correct** |
| `retrieve.py:605-615` | the FORGE `bm25_search` ruling, verbatim | **correct** — `:611-612` *"never a status predicate on the shared `bm25_search`"*, `:614-615` *"no new public storage method, per FORGE's ruling"* |
| `retrieve.py:241-242` | the fence echoed | **correct** — *"`bm25_search` applies no status predicate (shared method, never filtered)"* |
| `retrieve.py:229-237` | censoring test is a property of the fetch | **correct**, near-verbatim |
| `retrieve.py:256` | `raw_n_sparse >= cap` | **correct** |
| `retrieve.py:572-584` | `_is_active` already caller-side | **correct** (but see K-B13(b)) |
| `retrieve.py:597` | `cap = candidate_k * len(target_layers)` | **correct** |
| `retrieve.py:52` | `FETCH_WIDTH_FLOOR == 10` | **correct** |
| `graph.py:225` | `if neighbor_id not in seed_ids` | **correct** (but incomplete — K-B2) |
| `graph.py:302` | `visited = set(seed_ids)` | **correct** (but incomplete — K-B2) |
| `graph.py:215-230` | post-#41 all-seed loop | **correct** — `for seed_id in seed_ids:` … `return result_ids` |
| `graph.py:305` | sorted frontier | **correct** — `neighbor_expand(sorted(frontier), depth=1)` |
| `relational.py:531-541` | global BM25 ordering, `layer_filter=None` | **correct** |
| `vector.py:174-199` | `dense_search(layer_filter=None)` supported | **correct** |
| `evals/fusion_gate.py:223-225` | real stores + deterministic `MagicMock` vector arm | **correct** |
| `evals/fusion_gate.py:257-266` | the `cross_layer` block | **correct** but short by line 281 (K-N8) |
| `test_fusion_gate.py:18` | direct-import precedent | **correct** |
| `test_fusion_gate.py:31-39` | the AC-126 axis test | **correct** (body is 35-39) |
| `test_fusion_gate.py:60-73` | "the residual blocker is the tie-break" | **correct** |
| `test_fusion_gate.py:61-64` | AC-125 regressed 7/7 → ~2/7 on the renamed variant | **correct**, near-verbatim |
| `test_fusion_gate.py:85-113` / `:85-103` | the strict-xfail block | **correct** (decorator 85-103, test 104-113) |
| `retrieval_gate.py:91-114` | pure verdict classifier, every branch in-memory | **correct** |
| `retrieval_gate.py:117-137` | SKIP_SLOW ⇒ embed probe fails | **correct** |
| `retrieval_gate.py:261-278` | ⇒ `verdict: "inconclusive"`, all axes `None` | **correct** |
| `retrieval_gate.py:301-310` | `confounded` ⇒ never numbers | **correct** |
| `config.py:296-312` | the sub-1.0 band already fully documented | **correct**, and stronger than the plan claims (`:309-312` already carries the C-9 reaffirmation *and* AC-371's required "only the retrieval gate is informative" note) |
| `layers/episodic.py:319` | second `bm25_search` consumer | **correct** |
| `Makefile:34` | CI mode = SKIP_SLOW + slow selected | **substance correct**, anchor off by one (K-N11) |
| `test_server.py:159-178` | `build_http_app` coverage | **substance correct**, range straddles two tests (K-N21) |
| `evals/fusion_gate.py::run_floor_probe` | importable as `run_floor_probe(floor=…, weighted=…)` | **EXISTS**, keyword-only at `:290-292`; VP-M1's call form is valid. The blocker is the *return shape*, not the symbol (K-B7). |

**Mandate item (b) — resolved in the plan's favour, then defeated by K-B1.**
I traced the full path. With `dense_ranking == []`, an edgeless graph and
completion off, `weighted_rrf_merge_scored` (`retrieve.py:741-748`) sees exactly
one non-empty arm, so `fused_ids` **is** `sparse_ranking` verbatim
(score `w_sparse/(60+rank)`, strictly monotone, no ties). Nothing downstream
rescues the target: `context_match` is off (`:764`), the reranker is dead code
(`:781-786`), the scope/status filter is order-preserving (`:823-833`), and
`filtered_ids[:k]` (`:854`) would in fact **evict** the semantic target entirely
at small `k`. So *if the fixture produced the claimed `sparse_ranking`*, the gate
would be RED exactly as §4 #52 says. It does not produce it — see K-B1.

---

## Claims I could NOT verify by reading

| claim | what would settle it |
|---|---|
| That FTS5's implicit-AND holds in the pinned SQLite build (K-B1 rests on `relational.py:196-197`'s own docstring, not on execution) | `docker compose run --rm crystalium /app/.venv/bin/python -c "import sqlite3; c=sqlite3.connect(':memory:'); c.execute('CREATE VIRTUAL TABLE t USING fts5(s)'); c.execute('INSERT INTO t VALUES (?)', ('alpha only',)); print(c.execute('SELECT count(*) FROM t WHERE t MATCH ?', ('\"alpha\" \"beta\"',)).fetchone())"` — expect `(0,)` |
| VP-M1's prediction (`channel_live`) — that #41 removed the floor's channel on the shipped fixture | the 7×`-e PYTHONHASHSEED` loop at `verification-plan.md:58-63`. Note the tree still carries the **opposite**, pre-#41 claim in prose: `fusion_gate.py:72-92` and `:296-311` both assert the channel is *live and measured*. One of the two is stale; only measurement decides. |
| Whether AC-125 is 7/7 unanimous on `b7f1a47` today (S-6's baseline) | VP-B3, never captured (K-N13) |
| Whether `make test` / `make test-ci` are green at `b7f1a47` | VP-B1/VP-B2, never captured (K-N13) |
| Whether Option A's subset-layer recall loss is material on a realistic corpus (K-N12) | a `layers=["semantic"]` probe against an episodic-heavy store, pre/post Option A |
| Whether the entrypoint subprocess handshake is deterministic in-container within a timebox (§4 #57's HTTP disposition) | build the node and run it 20× under `make test-ci` |
| Actual red/green of any proposed gate | none of them exist yet; all are constructions I could only check for internal coherence |

---

*Kupo. Checker verdict: REJECT — return to maker. K-B1, K-B2, K-B9 and K-B14 are*
*plan-level design defects, not wording; the rest are criteria that pass while*
*the thing they name is broken. The §2 ownership table, the §0.2 deconfound*
*split, the `retrieve.py` serialisation finding and §5's two honest non-closures*
*survive review intact and should be carried forward unchanged.*
