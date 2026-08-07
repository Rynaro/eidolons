# FORGE rulings — crystalium-residual-eight-plan (post-Kupo-REJECT)

ruled_by: forge (standing in for the maintainer; autonomous, no escalation)
ruled_at: 2026-08-05
inputs: spec.md / spec.criteria.md / verification-plan.md (maker ramza), kupo-critique.md
(REJECT, 14 blocking), kb1-fts5-measurement.txt (settled: FTS5 implicit-AND confirmed by
execution), crystalium source at `b7f1a47` (re-read for every load-bearing claim below).
Anchor convention: `path:line` means at `b7f1a47`.

Standing constraints honoured throughout: the `bm25_search` fence (`retrieve.py:605-615`),
C-9 (no sub-1.0 precision dial), the AC-125 fixture freeze, and the §5 dispositions for
#47/#55 — none reopened, none silently reversed.

---

## Summary table

| id | one-line ruling |
|---|---|
| **D1** | Rebuild G-XL: all fillers match ALL query terms; separation by TF + doc length; gate asserts `target_rank == expected_blocked_rank` (exact N) plus sparse-arm-size and global-BM25-rank-0 liveness. "RED by construction" is DOWNGRADED to a measured precondition (recorded artifact gates W-45). S-3 gets a one-redesign bound, then the D9 ladder. |
| **D2** | Three conditional sites (`graph.py:225`, `:272`, `:302`) + two flag pass-throughs; `graph.py:266` deliberately unchanged (with proof obligation). Oracle needs three topologies (T1 depth-1 frontier-mates, T2 depth-2, T3 walk) so AC-350 and AC-351 are both falsifiable at depth 1. |
| **D3** | Option A is PINNED NOW, as W-45's design and W-44's precondition, with a mandatory three-case fetch shape (all-layers global / single-layer filtered / strict-subset global+backstop). The K-N12 starvation gate MUST be built, in W-45's `test_retrieve_layer_merge.py`, on a 2-layer-subset fixture. |
| **D4** | DROP AC-319/AC-320. Close #55 on items 1 (disposition) + 3 (eval note) + the G-WD fixture. The "re-run" premise was false; the identity property stands on the recorded structural argument; building the harness becomes a named precondition of any FUTURE combiner-arithmetic change, not of this campaign. |
| **D5** | Neither of the two offered options. VP-M1's probe lives in the NEW module `evals/floor_sensitivity_gate.py`, IMPORTS `_build_fixture` read-only, captures derived-arm MEMBERSHIP via a recording spy at the `graph_store` seam, and self-checks against `run_floor_probe`. `evals/fusion_gate.py` stays byte-untouched; no fence exception exists or is needed. |
| **D6** | #44 closes a REAL production defect. Production wires `recall_active_only=True` (`config.py:333` → `server.py:600`, `__main__.py:351`); the `False` at `retrieve.py:307` is a construction-site default that only evals/tests hit. The fixture pins `recall_active_only=True` as production parity, asserted by read-back off the instance; a negative-control node covers the flag-off path. |
| **D7** | Strict-xfail sentinel, shipped via a mandated two-commit W-44 shape: commit 1 = tests on the pre-fix base (AC-345 green, AC-346 red, recorded); commit 2 = fix + `xfail(strict=True)` on AC-345's node. On the tagged tree AC-345 = XFAIL (pass); XPASS = regression = suite RED. |
| **D8** | All 5 defective rows replaced with axis-distinct, RED-asserted perturbations (given per row below); count corrected to 5 for v2.0.2 plus a NEW 3-row v2.1.0 table; `checker-redcheck.json` must carry per gate the perturbation patch, command, tree SHA, non-zero exit, output tail, and restore proof — and each checker patch must mechanically differ from every maker patch in `red-evidence.txt`. |
| **D9** | The Unfailable-Gate Disposition ladder: verify the gate's own controls → ONE bounded redesign (premise measured before build) → then close by classified disposition (premise-refuted / unobservable-without-ground-truth / obsoleted-by-prior-fix). Never ship the fix the gate was to license, never ship a permanent strict-xfail as a substitute, never present the construct as a measurement. |

---

## D1 — G-XL fixture redesign (K-B1)

### RULING

Rebuild the G-XL fixture as follows; every element below is normative.

**Corpus (deterministic BM25 separation via term frequency + document length, never term
presence):**

- Query: 4 fresh nonce terms with zero lexical overlap with `fusion_gate.py`'s corpus,
  e.g. `_XL_QUERY = "quorvex blenthar mizzletine korvath"`.
- `episodic`: N = 3 fillers `ep1..ep3`. **Each filler contains all four query terms exactly
  once**, padded with unique non-query nonce tokens to strictly distinct document lengths
  (24, 32, 40 tokens). Distinct lengths ⇒ strict BM25 order among fillers, no ties.
- `semantic`: one `sem-target` whose summary is each query term repeated 3 times and nothing
  else (12 tokens). TF 3 vs 1 and dl 12 vs ≥24 make `sem-target` strictly the best BM25
  match per term and in total — a pure function of the corpus, deterministic in the pinned
  SQLite build, at every `PYTHONHASHSEED`.
- `k = 5` ⇒ `candidate_k = max(15, 10) = 15`. Assertions: `N + 1 < candidate_k` (truncation
  non-binding) and `k > N` (the blocked target is still inside the `[:k]` response window —
  Kupo's trace shows `filtered_ids[:k]` would otherwise evict it and the gate would measure
  eviction, not append order).
- Dense stub returns `[]` — the "neutral fixed list" variant permitted by spec.md §4 #52 is
  **revoked** (it contradicts AC-312's `dense_arm_size==0`; K-N9 resolved in AC-312's
  favour). Graph edgeless, completion off, `recall_active_only=False` (single-status corpus;
  the status axis belongs to W-44's fixture, §0.2 discipline).

**Gate assertion (replaces AC-310's `!= 0`):** pre-fix expected state is exactly
`sparse_ranking == [ep1, ep2, ep3, sem-target]` (per-layer append, `retrieve.py:521-530`,
episodic before semantic in `_ALL_LAYERS`), and with one live arm the fused order is the
sparse order verbatim (Kupo's traced mandate item (b)). Therefore:

- the result object carries `expected_blocked_rank = N` (= `liveness.corpus_per_layer`);
- AC-310 becomes `jq -e '(.target_rank|type=="number") and .target_rank == .expected_blocked_rank'`.
  This cannot pass on `null`, on `-1` (absent), or on a partially-built fixture (K-B4 cured).

**Liveness (C-XL-2, promoted from prose into AC-312):**

- `.liveness.sparse_arm_size == (.liveness.corpus_per_layer + 1)` — the single assertion
  that catches K-B1's failure mode (a filler silently not matching);
- `.liveness.edge_count == 0`, `.liveness.dense_arm_size == 0`,
  `.liveness.corpus_per_layer < .liveness.candidate_k`, `.liveness.k > .liveness.corpus_per_layer`;
- **new C-XL-3 (global-premise probe):** the fixture calls
  `relational.bm25_search(_XL_QUERY, layer_filter=None, k=60)` directly (read-only use of the
  shared method — the `run_arm` cross-layer probe at `fusion_gate.py:257-262` is the exact
  precedent, no fence contact) and asserts `ids[0] == "sem-target"`. This converts the
  fixture's BM25 assumption from prose into an in-gate assertion and makes the RED cause
  attributable: global rank 0 + fused rank N can only be layer-append order.

**"RED by construction" is downgraded to a measured precondition.** The phrase is struck
from spec.md. VP-M2 must run on `b7f1a47` and record
`CHANGE/vp-m2-gxl-red.json` = `{target_rank, expected_blocked_rank, liveness, tree_sha}`
with all liveness green and `target_rank == expected_blocked_rank`. **W-45's entry
precondition becomes the existence and content of that artifact**, not a claim in the spec.

**If the measurement shows GREEN anyway (S-3):**

1. If any liveness assertion is red → that is a fixture bug, not an S-3 event. Fix the
   fixture. (This is the state K-B1 predicted for the old fixture: C-XL-2 red.)
2. If liveness is fully green AND `target_rank == 0` → the append-order premise is false at
   the fused surface. **One** redesign cycle is authorised (instrument `sparse_ranking`
   directly, find where the order diverges from the premise, rebuild).
3. If the redesigned gate is also green with green liveness → apply D9 class (a): #45 closes
   **premise-refuted at `b7f1a47`, measurement attached**. W-45 is cancelled. W-44 rebases
   onto the existing per-layer fetch with AC-348 restated per-layer (≤ 1 widened call per
   censored-and-dirty layer, ≤ `len(target_layers)` total; per-layer censoring recompute is
   well-defined: `raw_n_sparse_layer >= candidate_k`). W-42 is unaffected.

### REASONING

The settled FTS5 measurement kills term-presence separation outright. TF and document
length are the only separation channels that exist under implicit-AND, both are
deterministic pure functions of the corpus, and the shipped `fusion_gate` corpus is the
in-repo precedent that partial matching must not be relied on. The exact-rank assertion is
strictly stronger than `!= 0` and closes both null-pass modes K-B4 found. C-XL-3 is what
makes the gate attribute rather than merely detect — the §0.2 discipline applied to this
gate's own premise. Downgrading "RED by construction" is forced by the campaign's own
epistemics: the claim was already falsified once by execution; a claim of that class must
be an artifact, not an adjective. The S-3 residual risk is assessed low — the per-layer
append is source-verified at `retrieve.py:521-530` and Kupo independently traced that with
one live arm nothing downstream reorders — but low is not zero, and the ladder makes the
terminal case actionable without a follow-up question.

### REVERSAL CONDITION

If the pinned SQLite build's BM25 ordering is shown NOT to rank the high-TF/short-doc
target above all fillers (VP-M2's C-XL-3 probe red on `b7f1a47`), the separation mechanism
is wrong and this fixture design reverts to FORGE with the probe output. If a future
crystalium change replaces FTS5 implicit-AND with OR-semantics tokenisation, the
all-terms-match constraint becomes unnecessary (but never harmful) and may be relaxed.

### PLAN CONSEQUENCE

- W-G-XL: fixture rebuilt as above; `expected_blocked_rank` added to the result object;
  C-XL-3 added.
- AC-310 rewritten (exact-rank + type guard). AC-312 gains `sparse_arm_size` and
  `global_bm25_rank0` conjuncts. AC-311 (single-layer control) retained unchanged — with the
  corrected fixture it is no longer vacuous, because the episodic arm is provably non-empty.
- VP-M2 now writes `CHANGE/vp-m2-gxl-red.json`; W-45's §8 entry precondition cites it.
- spec.md §4 #52: "RED by construction" struck; replaced with "RED expected by derivation,
  established by VP-M2 before W-45 may start".

---

## D2 — #42's full fix scope (K-B2)

### RULING

The authoritative site list and threading (parameter `exclude_seeds: bool = True` on
`neighbor_expand` and `decaying_walk`):

| site | change |
|---|---|
| `graph.py:225` (`if neighbor_id not in seed_ids` in `_neighbor_expand_one_hop`) | Thread a new parameter `exclude_input: bool = True` on `_neighbor_expand_one_hop`; the filter applies only when it is True. |
| `graph.py:271` (call site) | `neighbor_expand` passes `exclude_input=exclude_seeds`. |
| `graph.py:272` (`hop_ids -= original_seeds`) | Becomes `if exclude_seeds: hop_ids -= original_seeds`. |
| `graph.py:302` (`visited = set(seed_ids)` in `decaying_walk`) | Becomes `visited = set(seed_ids) if exclude_seeds else set()`. |
| `graph.py:305` (walk's inner call) | `decaying_walk` passes `exclude_seeds=exclude_seeds` through to its inner `neighbor_expand`. |
| `graph.py:266` (`visited = set(frontier)`) | **Deliberately unchanged, under both flag values** — a ruled divergence from Kupo's four-site enumeration, see reasoning. Carries a proof obligation: the T2 test below must show a hop-2-discovered seed appears in results without :266 changing. |
| docstrings `graph.py:203, :247, :292` | "excludes the seeds themselves" contract text updated to state the default and the opt-out. |

**Oracle fixture — three topologies, all mandatory, all in `test_storage_graph.py`:**

- **T1 (depth 1, frontier-mates — makes AC-350/AC-351 falsifiable at depth 1):**
  seeds `{S1, S2}`, edges `S1→S2`, `S1→N1`. `neighbor_expand(depth=1)`:
  True → `{N1}` (byte-identical to `b7f1a47`); False → `{N1, S2}`.
  This is the topology on which the old spec's `exclude_seeds=False` was a no-op (both
  `:225` and `:272` bind here); with the full threading it now differs, so AC-351's
  default-flip red-check genuinely goes red.
- **T2 (depth 2):** seeds `{S1, S2}`, edges `S1→M`, `M→S2`, `M→N2`. `neighbor_expand(depth=2)`:
  True → `{M, N2}`; False → `{M, N2, S2}` (exercises `:272` at hop 2 and discharges the
  `:266` proof obligation — S2 appears in results with `:266` untouched).
- **T3 (walk):** same graph as T2, `decaying_walk(max_hops=2, decay=0.5)`:
  True → `{M: 0.5, N2: 0.25}`; False → `{M: 0.5, N2: 0.25, S2: 0.25}` (exercises `:302` and
  the `:305` pass-through; S2's weight is its true shortest-hop distance). Plus the T1
  variant (seeds `{S1,S2}`, edge `S1→S2`): False → `S2: 0.5` (hop-1 seed credit).

AC-350 asserts True-branch byte-identity on **all three** topologies. AC-351 (flip the
default) must go red — it now does, on T1 alone. A new AC (AC-354) asserts the False-branch
expected sets/weights exactly as listed.

`retrieve.py`'s two call sites (W-42's existing grant) pass the flag from
`Config.recall_seed_derived_credit`; the flag's default remains decided by the DP-1(b)
re-check (§6 S-1), unchanged.

### REASONING

Read at `b7f1a47`: `:225` filters the one-hop *input set* (this is precisely what blocks
seed-to-seed discovery when both are in the frontier); `:272` re-subtracts *original* seeds
at every hop (the #41 addition, comment at `:257-263`); `:302` is the walk-level exclusion
that binds at depth ≥ 2 because the walk's inner `neighbor_expand([X], depth=1)` call has
`original_seeds = {X}`, not the walk's seeds. Those three sites, plus the two pass-throughs,
are the complete behaviour surface. `:266` is different in kind: it controls
*re-expansion*, not *result membership*, and every seed is already expanded at hop 0
(seeds ARE the initial frontier), so conditioning it on the flag would change nothing
except adding redundant re-expansion work — but this claim is exactly the kind that must be
proven, hence T2's proof obligation rather than an assertion in prose. The three-topology
oracle exists because each site binds on a different shape: a single fixture cannot
attribute (§0.2's own rule applied to this unit).

### REVERSAL CONDITION

If T2 shows a hop-2-discovered seed *absent* under `exclude_seeds=False` with the five
listed changes applied, then `:266` (or the `:274` frontier arithmetic) is load-bearing for
membership after all — the ruling's `:266`-unchanged clause is overturned and the site list
reopens. If Dream or any other `neighbor_expand` consumer is found passing seeds where the
True-default is not byte-preserving, S-1 territory: stop and re-measure.

### PLAN CONSEQUENCE

- spec.md §4 #42 rewritten with the site/threading table and the three topologies.
- AC-350/AC-351 re-anchored to T1/T2/T3; new AC-354 (False-branch expected sets).
- The checker perturbation row for #42 is replaced (see D8): sever the `:272`
  conditionality only → AC-354 must go red while AC-350 stays green.
- W-42's diff surface unchanged (`graph.py`, `test_storage_graph.py`, `retrieve.py` call
  sites) — no ownership-table change needed.

---

## D3 — #45 Option A vs B, decided now (K-B10, K-N12)

### RULING

**Option A is pinned, now, as W-45's selected design and as a hard precondition of W-44.**
Option B is rejected and removed from the spec (not "kept as fallback").

The mandatory fetch shape (both arms, sparse shown; dense mirrors it):

| case | shape |
|---|---|
| `target_layers == _ALL_LAYERS` (the default, `layers=None`) | **One** global call: `bm25_search(query, layer_filter=None, k=candidate_k * len(_ALL_LAYERS))`. Score-space by construction (`relational.py:531-541` orders globally by `bm25(crystals_fts)`). No post-filter needed. |
| `len(target_layers) == 1` | **One** filtered call: `bm25_search(query, layer_filter=layer, k=candidate_k)` — today's per-layer call, already score-space within the layer. Byte-preserving for the single-layer case. |
| strict subset, `len ≥ 2` | Global call (`k = candidate_k * len(_ALL_LAYERS)`) + post-filter to `target_layers`; **starvation backstop:** if the post-filtered count `< candidate_k * len(target_layers)` AND the global fetch was censored (raw row count == requested k), issue one `layer_filter=layer` call per target layer (`k=candidate_k`) and append rows not already present, layer-major, AFTER the globally-ordered head. Head is score-space (fixes #45); tail is coverage (closes K-N12). Every tail row is BM25-worse than every head row (it fell outside the global top-4N), so head/tail order is score-correct; only the tail's internal cross-layer order is rank-space, at RRF ranks where the contribution difference is negligible. Bounded: ≤ 1 + `len(target_layers)` calls, deterministic. |

Censoring semantics under Option A (`resolve_sparse_weight`, `retrieve.py:229-262`): `cap`
and `raw_n_sparse` refer to **the fetch actually performed** — the global k and the global
raw row count on the global paths, the filtered k/count on the single-layer path. This is
the same "property of the fetch" principle the code already states at `retrieve.py:230-237`;
VP-M7 records the pre/post `explain.fusion.{n_sparse_cap, selectivity, w_sparse}` delta.

**The K-N12 gate MUST be built.** Location: W-45's own `mcp-server/tests/test_retrieve_layer_merge.py`
(no new unit, no ownership change), node name normative:
`test_subset_layer_recall_no_regression`. Fixture: `E = 4 * candidate_k` episodic rows, all
matching all query terms, all strictly better BM25 than `S = candidate_k` semantic rows
(TF/length separation per D1's mechanism); query with `layers=["semantic", "procedural"]`
(a **2-layer strict subset** — a 1-layer subset never reaches the global path under the
shape above and cannot see the defect). Assert: the planted semantic target is recalled,
and the sparse candidate set contains ≥ `min(S, candidate_k)` semantic rows. This gate is
RED on a naive global+post-filter implementation and GREEN only when the backstop exists —
it can fail on the defect it names.

**AC-348 is retained at "≤ 1"** with its baseline defined: the spy asserts the exact
fetch-shape call count for the fixture's path (1 for default, 1 for single-layer,
1 + backstop count for strict subsets) and that the **#44 top-up adds at most one** call
beyond it.

### REASONING

Three independent grounds force A, any one sufficient. (1) AC-348 and #44's censoring
recompute are only coherent against a single identifiable fetch — Kupo's K-B10, confirmed
against `retrieve.py:597`'s aggregate cap. (2) `bm25_search` returns `SELECT c.*` with no
score column, and AC-349 freezes signature and SQL — so Option B's per-layer results can
NEVER be merged in score space caller-side; B is not a weaker fix, it is structurally
incapable of fixing the issue as filed ("a semantic hit with a far better BM25 score").
(3) With D1's corrected fixture, round-robin interleave puts `sem-target` at fused rank 1
(`[ep1, sem-target, ep2, ep3]`), so G-XL's post-fix assertion (`target_rank == 0`) stays
red under B — spec.md §4's claim that "G-XL as specified goes green under B" is simply
wrong for the corrected fixture; under B the campaign cannot close. The three-case shape
exists because K-N12's starvation is real for explicit layer subsets (the user excluded
layers; global dominance by excluded layers is noise, not signal) but is *intended
semantics* for `layers=None` (nothing is excluded; score decides — that is the issue's
ask). The backstop is fence-clean: existing signature, existing filters, bounded calls.

### REVERSAL CONDITION

If VP-M7's pre/post explain diff shows the D3 selectivity boost (#38) behaving
pathologically under the global cap (e.g. `selectivity` pinned to 0.0 on realistic
fixtures because the global fetch is always censored), the cap semantics — not the merge —
reopen, and the remedy space is bounded to censoring-signal definitions, never to reverting
the score-space merge. If `test_subset_layer_recall_no_regression` cannot be made green
without violating the `bm25_search` fence, W-45 stops and returns to FORGE with the
failing construction.

### PLAN CONSEQUENCE

- spec.md §4 #45: Option B deleted; the three-case shape written in as normative; the
  erroneous "goes green under B" sentence removed.
- §1 dependency graph: W-44's entry precondition becomes "W-45 merged **with the Option A
  shape**"; §8 Wave 2 table updated.
- W-45 gains the K-N12 node (normative name above); AC list gains AC-355 for it.
- AC-348's VERIFY gains the per-path baseline call-count assertion.
- VP-M7 explicitly records cap-semantics deltas per path.

---

## D4 — #55 item 2, the nonexistent §D2 identity harness (K-B6)

### RULING

**Drop AC-319 and AC-320. Do not build the harness in this campaign.** #55 closes on:
item 1's disposition (band formally unsupported — already ruled, §5.2, binding), item 3
(the which-gate-is-informative eval note), the G-WD fixture (as the DP-1(b) instrument),
and the config-comment line. The closure comment must state plainly: *"item 2's 're-run'
premise was false — no runnable harness exists; the recorded result at `config.py:292-293`
stands on the structural argument FORGE accepted (W1-W4 and #42 change candidate
generation and derived-arm contents, not combiner arithmetic), which survives every change
this campaign ships."*

**A binding forward obligation replaces the harness:** any future change that touches
combiner arithmetic — `weighted_rrf_merge_scored`, the RRF constant, or the semantics of
`fusion_weight_*` — MUST build and run a d2-identity harness (20 in-process comparisons,
`max_abs_diff == 0.0` at `w=1.0`, 1-ULP perturbation red-check) as a precondition of that
change. This obligation is recorded in the #55 closing comment and as one line in the
config comment block at `config.py:292-312`.

### REASONING

The issue's own justification for item 2 was "cheap refresh, not a blocker". Both halves
are now false: it is not cheap (a new eval module + CLI registration + ownership row), and
it was never a refresh (nothing exists to re-run). What remains is the question of whether
the identity property needs re-evidence — and the recorded FORGE position already answered
that on structural grounds which this campaign does not disturb: #42 changes which records
*enter* the derived arm, not what the combiner *does* with them; #45 changes candidate
*order and membership*, not arithmetic. Building a harness to verify a property that no
shipped change can affect is a gate with no defect to fail on — the campaign's own named
anti-pattern, inverted. The forward obligation preserves the reversal condition (a
non-zero diff) exactly where it can first become non-zero: the first future change to the
arithmetic itself. This is not half-shipping #55: the issue's core is item 1, whose
disposition is already ruled and survives; item 2 was scaffolding whose premise dissolved.

### REVERSAL CONDITION

If W-42's DP-1(b) re-check (AC-352) or any Wave-2 gate produces a fused-score anomaly
attributable to combiner arithmetic rather than membership (e.g. a record's fused score
changing with no change in any arm's membership or ranks), the structural argument is
broken and the harness must be built before v2.1.0 tags — this ruling flips from DROP to
BUILD-NOW.

### PLAN CONSEQUENCE

- AC-319/AC-320 struck from spec.criteria.md; VP-M5 struck from verification-plan.md.
- spec.md §4 #55 item 2 rewritten as the forward obligation; §7's v2.0.2 contents line
  updated ("#55 items 1+3 + config-comment disposition").
- K-B6's ownership hole dissolves (no `evals/d2_identity.py`, no CLI registration, no
  unassigned unit).
- W-G-WD's scope shrinks to the fixture + AC-317/AC-318 (with AC-318's sentinel fixed per
  K-N1: assert the literal string `NOT band characterisation` in the first docstring
  paragraph).

---

## D5 — VP-M1's measurable shape (K-B7)

### RULING

Neither offered option. **The probe lives in the new module `evals/floor_sensitivity_gate.py`
(W-G-FLOOR's own file), imports the frozen fixture read-only, and captures derived-arm
membership at the `graph_store` seam.** `evals/fusion_gate.py` is not edited by anyone but
W-G-XL's key rename; no fence exception exists.

Normative construction of `vp_m1_probe(*, floor: int) -> dict`:

1. `from evals.fusion_gate import _build_fixture, run_floor_probe` — imports are reads, not
   edits; the §3.1 freeze governs the file's bytes, not its importability.
2. Build the stores and `Aetheryte` with **exactly** `run_arm`'s construction flags
   (`completion=True, completion_max_hops=1, completion_decay=0.5, recall_active_only=False,
   recall_relevance_primary=True`, weights from `Config`) — copied once, then bound by the
   self-check in (5).
3. Wrap the real `GraphStore` in a thin recording proxy (delegates every method; records the
   return values of `decaying_walk` and `neighbor_expand`). Pass the proxy to `Aetheryte`.
   `floorN_derived` := the sorted union of ids the walk actually returned. This is the
   membership the prediction is *about*, captured where it is produced, with zero
   re-implementation of retrieve internals and zero reliance on `explain` (which carries
   only `arm_sizes` — sizes, not membership, `retrieve.py:1098-1104`).
4. Apply the `FETCH_WIDTH_FLOOR` monkeypatch in `try/finally` (the `fusion_gate.py:227-229,
   264` pattern).
5. **Self-check (binds the duplicate to the original):** the probe also calls
   `run_floor_probe(floor=floor, weighted=False)` on a fresh data dir and asserts its own
   `{target_rank, retrieved}` equals it. If `fusion_gate`'s recall path ever drifts, the
   probe invalidates itself loudly instead of measuring a divergent construction.

**Protocol (K-B3 applied):** 7 spawned processes
(`docker compose run --rm -e PYTHONHASHSEED=$s …` for 0-5, 7th run omitting `-e` entirely
per K-N17), each emitting one JSON line; the loop aggregates into
`CHANGE/vp-m1-floor-channel.json`:
`{seeds: [{seed, floor10_derived, floor1000_derived, floor10_retrieved, floor1000_retrieved}...], channel_live}`
with `channel_live := any(seed.floor10_derived != seed.floor1000_derived)`.

**AC-321 rewritten** from a shape check to a consistency check on recorded data:
`jq -e '(.seeds|length == 7) and (.channel_live == ([.seeds[] | .floor10_derived != .floor1000_derived] | any))'`
— the verdict must be *derivable from* the recorded per-seed evidence in the same file; a
fabricated `channel_live` that disagrees with its own rows fails.

### REASONING

The two offered options were both defective: `retrieved`-only redefinition is a one-sided
proxy (differing fused lists prove the channel live; identical fused lists do NOT prove the
derived memberships identical — the channel could be live but masked by weights or
tie-breaks, and carrying "channel dead" forward on a proxy that cannot see the channel is
the campaign's named defect class). The fence exception was unnecessary the moment the
probe is allowed to *import* — the freeze protects the fixture's bytes and the AC-125
measurement, neither of which an import disturbs. The spy at the `graph_store` seam is the
only capture point that observes the true derived membership without re-implementing
`retrieve.py` internals (drift risk) and without touching `explain` (insufficient). The
self-check converts the one real risk of duplication — silent divergence from `run_arm`'s
construction — into a loud failure.

### REVERSAL CONDITION

If the recording proxy is shown to perturb the measurement (e.g. `Aetheryte` type-checks
its `graph_store` or the proxy changes hash iteration order in a way that shifts the walk),
the seam capture is invalid and the fallback is the `retrieved`-only redefinition WITH the
one-sidedness stated in the artifact ("identical ⇒ no observable channel at the fused
surface; derived-level identity not instrumented"). If a future `explain` schema adds arm
*membership*, the proxy is retired in favour of `explain=True`.

### PLAN CONSEQUENCE

- verification-plan.md VP-M1 rewritten (probe location, spy, self-check, 7-spawn loop,
  aggregate schema). AC-321 rewritten as above.
- K-B7's contradiction dissolves: `evals/fusion_gate.py` untouched, §2 unchanged, no fence
  exception recorded anywhere.
- W-G-FLOOR's ownership row is already correct (it owns `floor_sensitivity_gate.py`); the
  probe is part of that file.
- The routing rule stands unchanged: `channel_live` either way, the new fixture gets built;
  only the carried-forward prose claim differs (VP-M1's original either/or, retained).

---

## D6 — #44's dead-code precondition (K-B13b)

### RULING

**#44 closes a real production defect. Say so plainly, because it is true:** the production
entrypoints construct `Aetheryte` with `recall_active_only=config.recall_active_only`
(`server.py:600`, `__main__.py:351`) and `Config` defaults it to **True**
(`config.py:333`, env override `CRYSTALIUM_RECALL_ACTIVE_ONLY` default True at
`config.py:437`). The `False` default at `retrieve.py:307` binds only for direct
construction — evals and tests. The issue's claim ("no error, no log line and no explain
anomaly" in production) is consistent with the shipped wiring: production runs the
active-only path, deprecated top-hits censor the fetch, and active hits starve silently.

Consequences, all mandatory:

1. **The W-44 fixture pins `recall_active_only=True` as production parity** — not as an
   opt-in fudge. The pin is asserted by reading the flag back **off the `Aetheryte`
   instance** (`assert aetheryte.recall_active_only is True`), per VP-M4's tautology rule —
   never off the kwargs dict the fixture just wrote.
2. AC-345/AC-346/AC-347/AC-348's GIVEN clauses gain "with `recall_active_only=True`
   (production parity, `config.py:333`)".
3. **A negative-control node ships:** `test_topup_inert_when_active_only_off` — same
   corpus, `recall_active_only=False`, spy asserts **zero** additional `bm25_search` calls
   and `explain.fusion.sparse_topup.fired == false`. This documents the flag-off path as
   deliberately out of scope and prevents the top-up from firing where `_is_active` is
   vacuously True.
4. The #44 issue-closing comment names the production wiring chain
   (`config.py:333` → `server.py:600`) as the evidence that the defect is live at default
   deployment.

### REASONING

Kupo's finding was correct for what it examined (the constructor default and the
fusion-gate template both use False) and its risk was real: a fixture copied from the
template would have tested dead code. But the classification question — production defect
vs configuration-gated — is settled by the wiring, not the constructor: every shipped
entrypoint passes the Config value, and the Config value is True by default and was
deliberately flipped ON at W6 ("gate PASS + correctness", `config.py:333`,
`evals/BENCH-NOTES.md`). The scope therefore does NOT expand to "the default path" — the
production default path IS the active-only path. What the ruling adds is the discipline
that keeps this from regressing into K-B13(b): the pin asserted at the instance, and the
negative control that makes the flag-off inertness a tested property instead of an
accident.

### REVERSAL CONDITION

If `Config.recall_active_only`'s default is ever flipped to False (or the env default at
`config.py:437` changes), #44's "production defect" classification reverts to
configuration-gated and the closing comment must be amended. If the negative control shows
the top-up firing with the flag off, the implementation gated the top-up on the wrong
predicate — stop, it is touching the fence's territory.

### PLAN CONSEQUENCE

- spec.md §4 #44: fixture description gains the pin + instance read-back; approach text
  gains the production-wiring citation.
- spec.criteria.md: AC-345/346/347/348 amended per (2); new AC-356 for the negative
  control.
- verification-plan.md §4: the #44 checker row is replaced (D8) — the old "mark every
  crystal active" no-op is deleted.
- The D8 perturbation for #44 (deepened deprecated stratum) runs under the same pin.

---

## D7 — AC-345/AC-346 mutual exclusivity (K-B5)

### RULING

**Strict-xfail sentinel, delivered through a mandated two-commit W-44 shape.** Mechanism:

1. **Commit 1 (tests on the pre-fix base):** W-44's first commit adds
   `test_sparse_status_topup.py` with both nodes and **no markers**, on the branch base
   (post-W-45 merge). On that tree: `test_prefix_baseline_starves_active_hits` (AC-345) is
   GREEN, `test_topup_recovers_active_hits` (AC-346) is RED. The maker records both runs —
   commands, tree SHA, exits — to `CHANGE/ac345-prefix-evidence.txt`. This is the pre-fix
   characterisation, pinned in git history where any checker can `git checkout` and re-run
   it.
2. **Commit 2 (the fix):** the `retrieve.py` top-up lands in the same commit as
   `@pytest.mark.xfail(strict=True, reason="pre-#44 starvation characterisation; XPASS = starvation regression (#44)")`
   added to AC-345's node. Post-fix: the node's assertions fail → strict xfail → suite
   green. If the starvation ever returns, the node passes → XPASS → strict → **suite RED**.
   The sentinel is self-enforcing on every future tree, exactly the `test_fusion_gate.py:85-103`
   precedent the repo already carries for G-XL's pattern.

**AC-345's VERIFY is rewritten in two parts:** (i) `CHANGE/ac345-prefix-evidence.txt`
exists and records exit 0 for the node at the commit-1 SHA (checker re-runs it at that SHA
— it is a plain `git checkout`); (ii) on the release tree,
`pytest …::test_prefix_baseline_starves_active_hits -v` reports **XFAIL** (not PASS, not
FAIL). The v2.1.0 checklist line "AC-340..AC-353 green" gains the annotation: *"AC-345
green = XFAIL on the tagged tree; XPASS is RED."*

### REASONING

The recorded-artifact-only option leaves nothing on the shipped tree that fails when the
starvation regresses — a characterisation that evaporates at tag time. A plain xfail
(non-strict) can rot silently. Strict xfail is the only mechanism of the three that is
simultaneously: green on the tagged tree (satisfying the release checklist), a permanent
regression tripwire (XPASS fails the suite), and precedented in this exact repo. The
two-commit shape exists because a strict-xfail node alone proves nothing about the pre-fix
tree — the commit-1 green run is what makes AC-345 a real characterisation rather than a
marker that was born expected-to-fail; putting it in git history makes it independently
re-derivable rather than a maker-attested text file.

### REVERSAL CONDITION

If the pytest version in the image changes strict-xfail semantics (XPASS-strict not
failing the suite), the sentinel is dead and AC-345 must convert to an inverted assertion
node (assert recovery, i.e. merge into AC-346) with the characterisation surviving only as
the commit-1 artifact. If W-44 cannot be delivered as two commits (e.g. squash-merge policy
on the target repo), the commit-1 evidence moves to a checker-re-run protocol pinned to the
pre-merge branch SHA — the XFAIL sentinel half of the ruling is unaffected.

### PLAN CONSEQUENCE

- spec.md §4 #44 and §8 Wave 2: W-44 is explicitly a two-commit unit; exit gate gains the
  XFAIL-state check.
- AC-345 rewritten as above; v2.1.0 checklist annotated.
- verification-plan.md §5: "AC-340..AC-353 green" footnoted with the XFAIL convention.
- K-N7's squash-merge caveat applies: AC-341's same-commit check must run on the W-44
  branch (pre-merge), not on post-merge HEAD — fold that correction in here.

---

## D8 — the checker-side perturbation table (K-B9)

### RULING

**Replacement table — v2.0.2 batch (5 rows; each checker perturbation differs from the
maker's AXIS and is asserted to flip the named gate to RED):**

| gate | maker's axis | checker's perturbation (replacement) | axis | asserted RED |
|---|---|---|---|---|
| entrypoint (#57) | process startup (NameError crash) | Neutralize tool registration in `server.py` (empty tool table); handshake completes, process stays alive, `tools/list` returns `[]` | handshake **content** vs process liveness | `test_serve_stdio_handshake` RED on the non-empty-tool-list assertion, with the process demonstrably alive (no traceback in stderr) |
| cross-layer G-XL (#52) | layer placement / append order | Remove ONE query term from ONE episodic filler's summary (make it a strict-subset matcher under implicit-AND) | term-coverage / **arm liveness** — the K-B1 axis | C-XL-2's `sparse_arm_size == N+1` liveness assertion fails → pytest node RED / eval verdict `"confounded"` → AC-312's jq exits non-zero. This is the direct proof that the guard added in response to K-B1 can fire. |
| corpus-scaling G-CORPUS (#47) | corpus size M vs `candidate_k` (both maker checks move that one inequality) | Boost the planted record's BM25 (append the query terms twice more to its summary) so it enters the top-`candidate_k` | the plant's **score-rank vs the truncation boundary** (data), not the boundary itself | AC-314's `jq -e '.planted_recovered == false'` exits non-zero (record now recovered) — proves the gate measures "plant beyond the fetch window", not "plant is unfindable" |
| weight-discrimination G-WD (#55) | none existed (K-B9 row 6 was cross-labelled) | Sever record A's graph edge (A loses its only support) | **derived-arm membership** topology | AC-317's "≥2 distinct outcomes across w ∈ {0.90, 0.95, 1.00}" fails — every weight produces the identical outcome, the exact degeneracy #55 reports |
| floor-sensitivity G-FLOOR (#48) | edge-bearing competitor's dense rank; floor constants | Delete the edge from the edge-bearing competitor to its phantom | **graph topology** vs dense-rank placement | AC-322's disjointness fails — no derived vote exists at either floor, both distributions collapse onto the same ranks |

**New v2.1.0 table (3 rows — the old table conflated the two batches):**

| gate | maker's axis | checker's perturbation | asserted RED |
|---|---|---|---|
| layer merge W-45 (#45) | code revert of the `retrieve.py` hunk (AC-342) | Inflate one episodic filler's TF above `sem-target` (make it the legitimate global BM25 best) | AC-340 (`target_rank == 0`) RED — proves the gate tracks score order through the global merge, not target identity or layer label |
| status top-up W-44 (#44) | code presence (delete call, keep counter) and code constant (`HARD_TOPUP_CEILING = cap`) | Deepen the deprecated stratum: add deprecated rows until even the widened `k_wide` fetch is fully deprecated-censored | AC-346 RED — active hits unrecoverable through the data, not the code; also cross-checks that `explain.fusion.sparse_topup` reports `fired: true` with recovery absent (the counter must describe the fetch, not the intention) |
| seed exclusion W-42 (#42) | default flip (AC-351) | Sever ONE threading site only: make `graph.py:272`'s subtraction unconditional again (ignore the flag at that site) | AC-354 (False-branch expected sets) RED on T1 and T2 while AC-350 (True-branch byte-identity) stays GREEN — per-site wiring proven, the K-B2 dominant site chosen deliberately |

**Counts:** AC-332 becomes `length == 5` against `CHANGE/checker-redcheck.json` (v2.0.2:
entrypoint + four gates). New **AC-365**: `CHANGE/checker-redcheck-v2.1.0.json`,
`length == 3`, wired into the v2.1.0 checklist next to AC-362.

**Evidence schema (both files) — a boolean is no longer acceptable.** Per gate:

```json
{
  "gate": "...", "unit": "...", "axis": "...",
  "perturbation_patch": "<unified diff, verbatim>",
  "command": "<the exact command run>",
  "tree_sha": "<RC sha the perturbation was applied on>",
  "exit_code": <non-zero>,
  "output_tail": "<last 20 lines, captured>",
  "restore": { "command": "...", "exit_code": 0 }
}
```

**Anti-replay mechanism:** the release checklist gains a step — diff each
`perturbation_patch` against every patch in the maker's `red-evidence.txt`; **any identical
patch fails AC-332/AC-365**. AC-332's jq additionally requires
`[.gates[] | select(.perturbation_patch != null and .exit_code != 0)] | length == 5`, so
the file cannot be satisfied by booleans. Honest limit, stated: a checker who fabricates
outputs outright cannot be prevented by any file format; the schema makes replay
*detectable* (identical patch) and fabrication *falsifiable on audit* (every recorded
command re-runs against the recorded SHA). That is the maximum a self-describing artifact
can carry, and it is a real improvement over a boolean that a replayer writes identically.

### REASONING

The replacement discipline is uniform: each checker perturbation attacks a *different
mechanism* than the maker's (data vs code, topology vs placement, content vs liveness) and
each is asserted to flip a named AC to a non-zero exit — the two properties K-B9 found
missing in 5 of 7 rows. Three rows deserve note. The G-XL row is chosen to fire the
specific guard this revision added for K-B1 — a gate hardened in response to a finding
must be shown hardened, not assumed. The #44 row replaces a no-op (under D6's pin, "mark
everything active" merely disarms the fixture) with a data-side recovery-impossible case
that also stress-tests the explain counter's honesty — the #36 F-V3 lesson applied from
the data side, complementing the maker's code-side check. The #42 row is only possible at
all because D2 threads all sites; it converts K-B2 from a defect into the checker's
sharpest instrument.

### REVERSAL CONDITION

Per row: if a listed perturbation fails to flip its gate RED on the RC tree, that is
itself a blocking finding against the gate (the gate cannot fail on that axis) and routes
to D9 — the row is not quietly swapped for an easier one. If the anti-replay diff step
produces false positives (maker and checker independently converge on the same minimal
patch), the checker documents the collision and substitutes a second axis-distinct
perturbation; the requirement is axis independence, not patch-text novelty for its own
sake.

### PLAN CONSEQUENCE

- verification-plan.md §4's table replaced wholesale by the two tables above.
- AC-332 rewritten (`length == 5`, schema predicate, anti-replay step); AC-365 added.
- `red-evidence.txt` gains the same schema (maker side), so the patch-diff step has
  structured input on both sides.
- The v2.0.2 and v2.1.0 release checklists each gain the anti-replay diff step.

---

## D9 — disposition when a gate still cannot fail on its defect

### RULING — the Unfailable-Gate Disposition ladder

Applied by the implementer autonomously, recorded in the change folder, no escalation:

1. **Audit the gate's own controls first.** A green gate with a red/confounded liveness
   check is a broken *fixture*, not evidence about the defect — fix the fixture and
   re-measure. Only a green gate with fully green liveness enters the ladder.
2. **One bounded redesign cycle.** A different fixture axis may be tried ONCE, and its
   load-bearing premise must be *measured before the build* (the D1/VP-M2 pattern: the
   premise becomes a recorded artifact, never an adjective in the spec).
3. **If the redesigned gate still cannot go red, close the issue by classified
   disposition** — three mutually exclusive classes, and the closing comment must name
   which, with the measurement artifact attached:
   - **(a) premise-refuted** — the measurement shows the defect does not exist on the
     current tree. Close as *"not reproducible at `<sha>`, measurement attached"*.
     (The D1 terminal branch for #45 is this class.)
   - **(b) unobservable-without-non-stipulated-ground-truth** — the defect may be real
     but no synthetic fixture can adjudicate it, because the fixture author stipulates the
     ground truth. Close **WONTFIX-with-rationale plus a reopen condition naming the
     production signal** that would decide it. (This is the standing #47/#55 precedent,
     §5.1/§5.2 — reaffirmed, not modified.)
   - **(c) obsoleted-by-prior-fix** — the mechanism the gate was built to measure was
     removed by an earlier change. **Retire** the criterion with a mechanism note.
     (This is S-5's class for AC-138/AC-139; "retired" and "discharged" remain distinct
     closures per verification-plan §6, and the issue comment must say which.)
4. **Absolute prohibitions, regardless of class:** never ship the behaviour change the
   gate was meant to license (a fix without a red gate is H-D, the campaign's rejected
   alternative, re-committed); never leave a permanent strict-xfail as a disposition
   substitute (S-5's own rule, generalised — D7's sentinel is not an exception: it guards
   a *shipped* fix, it does not stand in for an unshippable one); never present the
   construct as a measurement (S-11, generalised beyond #47/#55 to every gate).
5. **The gate artifact itself** merges only if its controls are falsifiable (its liveness
   checks can be shown to fire — D8's G-XL row is the template). A gate that can neither
   fail on its defect nor attribute through its controls is **deleted, not merged** — a
   permanently-green test is not neutral; it is camouflage for the next regression.

### REASONING

The ladder generalises what the plan already does well in three separate places (S-3's
redesign, S-5's retire-with-note, §5.1/§5.2's WONTFIX-with-reopen) into one rule with the
classes made explicit and exclusive — because the recurring failure in this repo is not
missing honesty but *unclassified* honesty: "closed" covering discharged, retired, refuted
and abandoned alike, which is how half-work gets declared victory. Step 1 exists because
K-B1 demonstrated the most likely cause of an unexpectedly-green gate is a broken fixture,
and burning the single redesign cycle on a fixture bug would be waste. The one-cycle bound
is the campaign's own bounded-deliberation discipline applied to fixtures: unbounded
redesign converges on a fixture *written to go red*, which is H-D through the back door.

### REVERSAL CONDITION

If production telemetry (the reopen conditions of class (b)) later shows a defect that a
class-(a) closure declared not-reproducible, the closure was wrong: reopen the issue,
attach both artifacts, and treat the original gate's green as a finding about the gate.
The ladder itself is superseded only by a future FORGE ruling with new evidence classes.

### PLAN CONSEQUENCE

- spec.md §6 gains the ladder as **S-13** (referenced by S-3, S-5, S-7, S-8 as their
  common terminal action).
- Wave 3's per-issue closure table (§8) gains the class vocabulary: every closing comment
  names shipped / refuted / unobservable-WONTFIX / retired.
- AC-373's per-issue check (as corrected per K-N2) verifies the closing comment names one
  of the four classes.

---

## Rulings that change the release plan

1. **v2.0.2 contents shrink:** AC-319/AC-320 and the d2-identity harness are out (D4);
   #55 ships items 1+3 + fixture + config comment only. No new unit is added.
2. **v2.0.2 checker gate widens:** AC-332 = 5 independently re-broken artifacts (not 4),
   with the evidence schema and the anti-replay diff step (D8).
3. **v2.1.0 gains a precondition and a gate:** W-44 requires "W-45 merged with the Option
   A shape" (D3); W-45 ships the K-N12 subset-starvation node (AC-355) and the three-case
   fetch shape; AC-365 (3-row checker table) joins the v2.1.0 checklist (D8).
4. **W-45's start is artifact-gated:** `CHANGE/vp-m2-gxl-red.json` on `b7f1a47` replaces
   "RED by construction" as the entry condition (D1). If it cannot be produced after one
   redesign, #45 closes premise-refuted and v2.1.0 re-scopes to W-44 (per-layer AC-348
   variant) + W-42 (D1 terminal branch) — a smaller but still shippable minor.
5. **W-44 becomes a mandated two-commit unit** with the XFAIL sentinel convention
   annotated in the v2.1.0 checklist (D7).
6. **The #44 closure is re-classified upward:** it is a production defect at default
   deployment (`config.py:333` → `server.py:600`), and the release notes / issue comment
   must say so — this strengthens, not weakens, the case for shipping v2.1.0 (D6).
7. **New S-13** (the disposition ladder) becomes the shared terminal action for S-3, S-5,
   S-7, S-8 (D9).
8. Kupo's remaining blocking findings not separately ruled here are ACCEPTED as filed with
   their minimal fixes: K-B3 (spawn-per-seed + non-empty-array guards), K-B8
   (`fence-amend.json` + `.md` sibling), K-B11 (`--repo` flag + per-unit literal file-list
   check replacing the drift tool for S-12), K-B12 (state-file jq + timestamp binding +
   per-batch critic records in the change folder), K-B14 (direct-import criteria for
   Wave-1 gates; `-m evals` only in W-CLI's own exit gate). None of them conflicts with
   any ruling above; the maker folds them in the same revision pass.

---

## Confidence and what I could not settle without measurement

**Confidence: 87% overall.** Highest-confidence rulings: D4, D6, D7, D8, D9 (evidence is
source-verified and closed-form; D6's production wiring is three lines of read source).
D2 at 85% — the `:266`-unchanged clause is a derivation with a designed proof obligation
(T2), which is the honest shape for it. D3 at 82% — Option A's pin is forced by three
independent grounds, but the strict-subset backstop's head/tail merge is a design whose
tail-order imprecision is argued, not measured. D1 at 85% — the TF/doc-length separation
is a property of BM25's closed form, but it runs on a pinned SQLite build and must be
confirmed by VP-M2 before anything downstream moves.

**What requires measurement before it is final, and what each outcome implies:**

1. **VP-M2 on the rebuilt G-XL fixture at `b7f1a47`** (D1). Expected:
   `target_rank == 3 == expected_blocked_rank`, all liveness green ⇒ W-45 unblocked.
   `C-XL-3 red` (target not global BM25 best) ⇒ the separation mechanism is wrong;
   fixture returns to FORGE with the probe output. `Green with green liveness` ⇒ D1's
   S-3 ladder, terminal branch re-scopes v2.1.0 as stated.
2. **VP-M1 with the D5 probe** (7 spawns, membership via spy). `channel_live == false` ⇒
   spec §4 #48's prediction confirmed, carry it; `true` ⇒ prediction refuted, carry the
   tie-break explanation instead — either way the new fixture gets built; only prose
   changes.
3. **The G-FLOOR disjointness itself (AC-322 corrected per K-B3)** — whether the
   between-floors fixture produces disjoint distributions at all 7 seeds is a genuine
   unknown post-#41; S-5's retire-with-note (D9 class (c)) is the ruled fallback.
4. **VP-M7's cap-semantics delta under Option A** — if the global cap pins `selectivity`
   to 0.0 on realistic fixtures, D3's censoring-semantics clause reopens (bounded to
   signal definitions, never to reverting the merge).
5. **The AC-125 7/7 baseline (VP-B3) and both suite modes at `b7f1a47` (VP-B1/B2)** were
   never captured (K-N13) and remain the first commands of Wave 0. A red anything there
   halts the campaign before any of these rulings applies — they all assume a green
   baseline.

Nothing else in this ruling set depends on an unexecuted measurement.

*FORGE. All nine decided; no escalations; every ruling actionable as written.*
