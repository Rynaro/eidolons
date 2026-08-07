# spec.criteria.amend-01 — `crystalium-residual-eight-plan`

**Amendment `amend-01` to the FROZEN criteria file.** `spec.criteria.md` is NOT edited; its
hash `eb0492ff1ac778499f89c8f4c70b1c919fbd9e3a83c83da630f022890da8908e` is the tamper-evidence
anchor. Where a criterion appears below with status **REPLACED / STRUCK / ADDED /
UNCHANGED-BUT-RE-ANCHORED**, this file governs. Criteria not listed stand as originally
written.

Companion: `spec.amend-01.md` (spec sections), `verification-plan.amend-01.md` (measurements,
red-check protocol, checklists).

---

## 0. Conventions (amended)

| shorthand | absolute path |
|---|---|
| MAIN | `/home/rynaro/workspace/oss/agents/crystalium` |
| CHANGE | `/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan` |
| NEXUS | `/home/rynaro/workspace/oss/agents/eidolons` |
| ART (host) | `MAIN/evals/results` — already gitignored at `b7f1a47` (`.gitignore`: `evals/results/*.json`; `evals/results/.gitkeep` is tracked) |
| ART (container) | `/app/evals/results` — the same directory, via docker-compose's `- .:/app` bind mount |

Carried forward from `spec.criteria.md` unchanged: container-only execution, `/app/.venv/bin/python`
inside containers, **never `bash -lc`** (NC-4), **never `2>/dev/null`** on a success check,
normative test-node names, "no absolute thresholds".

### 0.1 GLOBAL RULES — these bind every command in this file

**(a) K-B15 — no criterion pipes a gate's raw stdout into `jq`.**
The shipped evals write structlog to **stdout** ahead of their JSON (measured;
`kb15-stdout-contamination.md`), so `… | jq -e '<pred>'` fails with a parse error *regardless
of what the gate measured*. Two permitted forms, in order of preference:

1. **Artifact (preferred).** The gate module writes its result with
   `emit(result, '/app/evals/results/<name>.json')`; the criterion `jq`s the **file**.
   Every new gate module in this campaign exposes `run(...) -> dict` and
   `emit(result: dict, out: str) -> None` (overwrite, never append; `emit` prints nothing).
2. **`awk` extraction (only where a module is frozen and cannot gain `emit` — i.e.
   `evals/fusion_gate.py`, §3.1).** Pipe through `awk '/^\{/{f=1} f'` **first**, redirect to a
   file under ART, then `jq` the file.

**Every jq predicate opens with a parse/type guard** and the pass condition names three exits:
- **exit 0** = PASS.
- **exit 1** = the predicate is false → **a real red**.
- **exit 2 or 5** = jq could not parse the artifact → **capture failure, NOT a gate result.**
  Re-run the emit step. **Recording a 2/5 as a red is itself a finding.**

**(b) K-B14 — Wave-1 gate criteria use DIRECT IMPORT, never `-m evals <sub>`.**
`W-CLI` (which owns `evals/__main__.py`) is a *trailing* unit gated on all four gates, so a
`-m evals <new-gate>` criterion cannot run at the exit gate of the unit that produces it.
Form: `docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.X as m; m.emit(m.run(), '/app/evals/results/X.json')"`.
`-m evals` appears **only** in W-CLI's own exit gate (AC-325b) and for the **pre-existing**
`fusion-gate` / `retrieval-gate` subcommands, which are already registered at `b7f1a47`.

**(c) Never assert the negation of a failure value.** `VP-B4` proved `gate_pass: null` is a
**live value in this repo** (`retrieval-gate` under `CRYSTALIUM_SKIP_SLOW=1`), and
`jq -e '.gate_pass != false'` **exits 0 on null** — demonstrated during this pass. Every
predicate asserts the **positive**: `== true`, an exact number, or a type guard.

**(d) K-B3 / K-N17 — a 7-seed protocol spawns 7 PROCESSES.**
`PYTHONHASHSEED` is read by CPython before `main()` and cannot be re-seeded in a running
interpreter, so `--seeds 7` in one process samples **one** seed seven times. Form: six runs
`docker compose run --rm -e PYTHONHASHSEED=$s crystalium …` for `s` in `0 1 2 3 4 5`, and a
**seventh run that OMITS `-e` entirely** (`-e PYTHONHASHSEED=` sets it *empty*, which is not
*unset*). Aggregate the 7 artifacts with `jq -s`.

**(e) K-N19 — no `grep -c` whose pass condition is exit 1.**
Absence is asserted positively: either an in-process Python assertion (preferred — it also
proves the file exists) or `test "$(… | grep -cE '…' || true)" = "0"` with a separate
existence guard.

---

## 1. Wave 0

#### AC-301 — UNCHANGED
#### AC-302 — UNCHANGED
#### AC-303 — UNCHANGED

### AC-304 (ubiquitous) — REPLACED (K-N19)
*(was: `grep -c "pytest.mark.slow" …` — PASS = output `0`, i.e. exit 1)*

GIVEN the entrypoint smoke-test module
WHEN the module is inspected
THEN the system shall carry no `slow` marker on the entrypoint smoke test, and the module
shall exist.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import pathlib; p=pathlib.Path('mcp-server/tests/test_server_entrypoint.py'); assert p.is_file(), 'module missing'; s=p.read_text(); assert 'pytest.mark.slow' not in s, 'slow marker present'; print('ok')"
```
**PASS = exit 0 and the literal output `ok`.** A missing module now FAILS (the old form passed
on it).

### AC-305 (event-driven) — UNCHANGED-BUT-RE-ANCHORED (K-B16)
GIVEN a gate fixture with one pinned axis deliberately set to a binding value
WHEN the shared rig's liveness self-check runs
THEN the rig shall return verdict `"confounded"` and emit no numeric axes
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_corpus_rig.py::test_confounded_axis_returns_no_numbers -v` — PASS = exit 0.

Command unchanged; the **liveness form** is re-anchored. The rig's `"confounded"` liveness self-check must use the §A.3
form: `edge_count = len(graph.all_edges())` **and** `node_count = graph.node_count()`, with
`node_count` asserted `> 0`. **`all_edges() == 0` is `[] == 0` in Python and is always False**
(K-B16, `graph.py:320-326` returns a `list`); a zero from `all_edges()` alone is also
indistinguishable from a kuzu error (`graph.py:332`: *"Returns [] on error"*).

### AC-306 (ubiquitous) — REPLACED (K-B8)
*(was: `jq -e … CHANGE/fence-amend.json`, an artefact §2/§8 never produced)*

GIVEN the `bm25_search` status-predicate fence (`retrieve.py:605-615`, echoed at `:241-242`)
WHEN the fence-amend record is inspected
THEN the system shall record a machine-readable verdict of exactly `ALLOW` or `DENY`,
carrying the quoted ruling text and a decision timestamp.

VERIFY: run the command block below; PASS exactly as stated.
```
jq -e '(type == "object") and (.verdict == "ALLOW" or .verdict == "DENY") and (.ruling_quote | type == "string") and ((.ruling_quote | length) > 0) and (.decided_at | type == "string") and (.decided_by | type == "string")' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/fence-amend.json
```
**PASS = exit 0.** `DENY` triggers STOP **S-10** (#44 not closable as specified; re-file rather
than ship a half-fix). W-HOP emits this `.json` **and** a narrative `fence-amend.md` sibling;
the `.json` is normative.

---

## 2. Wave 1 — the four gates

### AC-310 (event-driven) — REPLACED (K-B1, K-B4; FORGE D1)
*(was: `… -m evals cross-layer-gate | jq -e '.target_rank != 0'` — passed on `null`, on `-1`,
on an empty fixture, and could not run before W-CLI)*

GIVEN the rebuilt cross-layer fixture — four nonce query terms
(`_XL_QUERY = "quorvex blenthar mizzletine korvath"`), three episodic fillers `ep1/ep2/ep3`
each containing **all four** terms exactly once at document lengths 24/32/40 tokens, one
`sem-target` in `semantic` carrying each term **three times** (12 tokens), `k = 5`,
`candidate_k = 15`, edgeless graph, empty dense stub, completion off
WHEN `Aetheryte.recall(scope, _XL_QUERY, k=5, layers=None, …)` runs on `b7f1a47`
THEN the gate shall report the semantic target at the exact fused rank the per-layer append
order predicts — `target_rank == expected_blocked_rank == corpus_per_layer == 3`.

VERIFY: two steps): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.cross_layer_gate as m; m.emit(m.run(), '/app/evals/results/cross-layer-gate.json')"
```
```
jq -e '(type == "object") and (.target_rank | type == "number") and (.expected_blocked_rank | type == "number") and (.liveness.corpus_per_layer | type == "number") and (.expected_blocked_rank == .liveness.corpus_per_layer) and (.expected_blocked_rank == 3) and (.target_rank == .expected_blocked_rank)' /home/rynaro/workspace/oss/agents/crystalium/evals/results/cross-layer-gate.json
```
**PASS = exit 0.** Exit 1 with `target_rank == 0` **and AC-312 fully green** triggers STOP
**S-3** → **S-13** (one bounded redesign, then class (a) premise-refuted). Exit 1 with any
AC-312 conjunct red is a **fixture bug, not an S-3 event** (S-13 step 1). Exit 2/5 = capture
failure. *Verified during this amendment pass: this predicate returns exit 1 on
`target_rank: null` and on `target_rank: -1`.*

#### AC-311 — UNCHANGED
Retained verbatim, and **no longer vacuous**: under the old fixture an empty episodic arm
passed it for the wrong reason (K-B1); with all-terms fillers the episodic arm is provably
non-empty. Red still triggers STOP **S-4**.

### AC-312 (ubiquitous) — REPLACED (K-B4, K-N9, K-B16; FORGE D1)
*(was: three conjuncts read from `-m evals`; omitted the one assertion that catches K-B1)*

GIVEN the cross-layer gate
WHEN it emits its result object
THEN the system shall assert every pinned axis is non-binding, that the sparse arm is
live at exactly the expected size, and that the fixture's own BM25 premise holds — before
emitting any numeric axis.

VERIFY: reads the artifact emitted by AC-310 step 1 — run the command block below; PASS exactly as stated.
```
jq -e '(type == "object") and (.liveness | type == "object") and (.verdict == "measured") and (.liveness.edge_count == 0) and (.liveness.node_count == 4) and (.liveness.dense_arm_size == 0) and (.liveness.sparse_arm_size == (.liveness.corpus_per_layer + 1)) and (.liveness.corpus_per_layer < .liveness.candidate_k) and (.liveness.k > .liveness.corpus_per_layer) and (.liveness.global_bm25_rank0 == "sem-target")' /home/rynaro/workspace/oss/agents/crystalium/evals/results/cross-layer-gate.json
```
**PASS = exit 0.**
- `sparse_arm_size == corpus_per_layer + 1` (C-XL-2) is **the single assertion that catches
  K-B1's failure mode** — a filler silently not matching under FTS5 implicit-AND.
- `node_count == 4` with `edge_count == 0` distinguishes *edgeless* from *kuzu error*
  (K-B16); `all_edges()` returns `[]` on error (`graph.py:332`).
- `global_bm25_rank0` (C-XL-3) is the gate's own
  `relational.bm25_search(_XL_QUERY, layer_filter=None, k=60)` probe — a read-only use of the
  shared method, precedented at `fusion_gate.py:257-262`, **no fence contact**. It makes the
  RED **attributable**: global rank 0 + fused rank N can only be layer-append order.
- `dense_arm_size == 0` is now normative: **`spec.md:258-259`'s "neutral fixed list" variant is
  REVOKED** (K-N9, resolved by FORGE in AC-312's favour).
- Any conjunct red ⇒ the gate emits `verdict: "confounded"` and **no numeric axes** (R-CONF).

### AC-313 (event-driven) — REPLACED (K-N6)
*(was a `grep` filter chain whose PASS was "no output" — which a **deleted** `fusion_gate.py`
also produces, and which **fails** on the `cross-layer` hyphen docstring correction that is the
entire point of #52 item 2)*

GIVEN the `cross_layer` axis rename in `evals/fusion_gate.py`
WHEN the module is inspected
THEN `_build_fixture` shall be **byte-identical** to `b7f1a47`, and the only textual changes
shall be the four `cross_layer` key sites (`:257, :262, :266, :281`) and the module-docstring
sentence at `:104-106`.

VERIFY: two parts, both required): — run the command block(s) below; PASS exactly as stated.

(i) `_build_fixture` byte-identity — **cannot pass on a deleted module** (the import fails):
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import inspect, hashlib, evals.fusion_gate as m; h=hashlib.sha256(inspect.getsource(m._build_fixture).encode()).hexdigest(); assert h == '66d3e9a7ea3bb8b1830c5d5ea3de7c8f70afef7a098b4a38069677ef6d6b62d4', h; print('ok')"
```
**PASS = exit 0 and the literal output `ok`.** The expected hash was computed from the tree at
`b7f1a47` during the amendment pass. *(`run_arm`'s hash is deliberately NOT pinned — the rename
sites `:257/:262/:266` are inside it.)*

(ii) the change surface is confined:
```
cd /home/rynaro/workspace/oss/agents/crystalium && test "$(git diff b7f1a47 -- evals/fusion_gate.py | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | grep -civE 'cross_layer|cross-layer|sparse_arm_per_layer_probe' || true)" = "0"
```
**PASS = exit 0.** The filter now matches the **hyphen** form too, so correcting
`fusion_gate.py:104-106` (*"the cross-layer sparse-arm rank is reported per layer"*) is
permitted rather than a failure.

### AC-314 (event-driven) — UNCHANGED-BUT-RE-ANCHORED (rules (a), (b))
GIVEN a single-layer corpus of `M` crystals with `M > candidate_k`
WHEN the corpus-scaling gate runs on `b7f1a47`
THEN the planted ground-truth record shall be absent from the recalled ids
VERIFY: two steps — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.corpus_scaling_gate as m; m.emit(m.run(), '/app/evals/results/corpus-scaling-gate.json')"
```
```
jq -e '(type == "object") and (.planted_recovered == false) and (.liveness | type == "object") and (.liveness.corpus_size | type == "number") and (.liveness.candidate_k | type == "number") and (.liveness.corpus_size > .liveness.candidate_k) and (.liveness.sparse_arm_size == .liveness.candidate_k) and (.liveness.layers == ["episodic"]) and (.liveness.edge_count == 0) and (.liveness.node_count > 0)' /home/rynaro/workspace/oss/agents/crystalium/evals/results/corpus-scaling-gate.json
```
**PASS = exit 0.** `sparse_arm_size == candidate_k` **exactly** proves the fetch really was
censored (VP-M3); anything else means the gate is measuring something other than truncation.
`planted_recovered == false` is asserted positively — never `!= true`.

#### AC-315 — UNCHANGED (pytest node; RED triggers STOP S-7 → S-13)
### AC-316 (ubiquitous) — REPLACED (K-N10)
*(was: a **fresh process** import-and-assert, which cannot see the realistic failure — a gate
that monkeypatches `retrieve_mod.FETCH_WIDTH_FLOOR` and drops the `finally` restore, the exact
patch/restore dance at `fusion_gate.py:227-229, 264`)*

GIVEN the corpus-scaling gate
WHEN the gate has run **in the same process**
THEN `FETCH_WIDTH_FLOOR` shall still read 10 after the run.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import crystalium.aetheryte.retrieve as r; before = r.FETCH_WIDTH_FLOOR; assert before == 10, before; import evals.corpus_scaling_gate as m; m.run(); after = r.FETCH_WIDTH_FLOOR; assert after == 10, ('leaked monkeypatch', before, after); print('ok')"
```
**PASS = exit 0 and the literal output `ok`.** The same-process post-run read is what makes an
unrestored patch detectable. Anchor re-verified: `retrieve.py:52` is `FETCH_WIDTH_FLOOR: int = 10`.

### AC-317 (event-driven) — REPLACED (K-B3, rules (a)(b)(d))
*(was: one `-m evals weight-discrimination` invocation backing VP-M4's "3 weights × 7 seeds =
21 cells" — one process, one hash seed)*

GIVEN the weight-discriminating fixture
WHEN it is evaluated at `fusion_weight_derived ∈ {0.90, 0.95, 1.00}` across the 7-seed C-2
protocol (**7 spawned processes**)
THEN the gate shall produce at least two distinct outcomes across those three weights, and
the injected weight shall be confirmed by **read-back off the `Aetheryte` instance**.

VERIFY: three steps): — run the command block(s) below; PASS exactly as stated.
```
( cd /home/rynaro/workspace/oss/agents/crystalium && for s in 0 1 2 3 4 5; do docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run(seed_label='$s'), '/app/evals/results/wd-seed-$s.json')" || exit 1; done )
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run(seed_label='unset'), '/app/evals/results/wd-seed-unset.json')"
```
```
jq -s -e '(length == 7) and (all(.[]; (type == "object") and (.cells | type == "array") and ((.cells | length) == 3) and (all(.cells[]; (.weight_readback | type == "number") and (.weight_readback == .weight) and (.outcome | type == "string"))))) and (all(.[]; ([.cells[].outcome] | unique | length) >= 2))' /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-0.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-1.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-2.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-3.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-4.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-5.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-seed-unset.json
```
**PASS = exit 0** (7 seeds present, 3 cells each = the 21 cells VP-M4 requires, each cell's
weight confirmed off the instance, and >= 2 distinct outcomes **at every seed**).
`weight_readback` **must be read off the `Aetheryte` instance**, never off the kwargs dict the
fixture just wrote — that is a tautology and cannot fail. A single distinct outcome is the
degeneracy #55 reports.

### AC-318 (ubiquitous) — REPLACED (K-N1; FORGE D4)
*(was: `assert 'DP-1' in d and 'not' in d.lower()` — `'not'` matches "notes", "cannot", "note",
"annotation", so a paragraph reading *"DP-1(b) note: this module characterises the sub-1.0
band"* passed while asserting exactly what §5.2 forbids)*

GIVEN the weight-discrimination module
WHEN its docstring's first paragraph is read
THEN the system shall state, with a fixed literal sentinel, that the module's purpose is
the DP-1(b) re-check and **not** sub-1.0 band characterisation.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; d=(m.__doc__ or '').split(chr(10)+chr(10))[0]; assert 'DP-1' in d, d; assert 'NOT band characterisation' in d, d; print('ok')"
```
**PASS = exit 0 and the literal output `ok`.** The sentinel is case-sensitive and exact:
`NOT band characterisation`.

#### AC-319 — STRUCK (K-B6; FORGE D4)
The "§D2 bitwise identity harness" **does not exist** at `b7f1a47`: no `evals/d2_identity.py`,
no `d2-identity` subcommand (`evals/__main__.py:155-208`), and the only trace is prose at
`config.py:292-293` — a recorded *result*, not a re-runnable harness. "Re-run" was false; the
criterion was unexecutable and unassigned. **The harness is not built in this campaign.**
Replaced by the binding **forward obligation** in `spec.amend-01.md` §B.6.1 (any future change
to combiner arithmetic MUST build and run it as a precondition of that change), recorded in the
#55 closing comment and in `config.py`'s comment block.

#### AC-320 — STRUCK (K-B6; FORGE D4) — the 1-ULP red-check for a harness that is not built.

### AC-321 (event-driven) — REPLACED (K-B7; FORGE D5)
*(was: `jq -e 'has("floor10_derived") and has("floor1000_derived") and has("channel_live")'` —
a **shape** check on a file the maker writes, passing on fabricated values, demanding fields
`run_floor_probe` structurally cannot produce: `run_arm` returns only
`{"target_rank","retrieved","cross_layer"}` (`fusion_gate.py:266`) and never passes
`explain=True` (`:250-253`))*

GIVEN the post-#41 tree
WHEN the floor-channel probe runs across the 7-seed C-2 protocol, capturing **derived-arm
membership** via a recording proxy at the `graph_store` seam
THEN the recorded `channel_live` verdict shall be derivable from the per-seed evidence in
the same artifact.

VERIFY: run the command block below; PASS exactly as stated.
```
jq -e '(type == "object") and (.seeds | type == "array") and ((.seeds | length) == 7) and (all(.seeds[]; (.floor10_derived | type == "array") and (.floor1000_derived | type == "array") and (.self_check_ok == true))) and (.channel_live | type == "boolean") and (.channel_live == ([.seeds[] | .floor10_derived != .floor1000_derived] | any))' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/vp-m1-floor-channel.json
```
**PASS = exit 0.** A fabricated `channel_live` that disagrees with its own rows **fails** —
verified during this pass (flipping `channel_live` to `true` against identical rows returns
exit 1). `self_check_ok` is D5 step 5: the probe's own `{target_rank, retrieved}` must equal
`run_floor_probe(floor=floor, weighted=False)` on a fresh data dir, so a drift in
`fusion_gate`'s recall path invalidates the probe loudly instead of silently.
`channel_live == false` confirms `spec.md` §4 #48's prediction and routes to the new fixture;
`true` refutes it and the tie-break explanation is carried instead. **Either way the new fixture
is built** — this is a finding, not a failure.

**The existing `CHANGE/vp-m1-floor-channel.json` does NOT satisfy this criterion.** It is a
preliminary `retrieved`-only capture (`differ: false` at all 7 seeds, both arms). Per FORGE D5
it is a **one-sided proxy**: differing fused lists would *refute* channel-dead, but identical
fused lists do **not** *confirm* it — the derived memberships can differ while the fused surface
is masked by the id-ascending tie-break, which is exactly what `test_fusion_gate.py:60-73`
claims. It is preserved as `vp-m1-floor-channel.preliminary.json` and must not be cited as
confirmation.

### AC-322 (event-driven) — REPLACED (K-B3, rules (a)(c)(d))
*(was: `-m evals floor-sensitivity-gate --seeds 7 | jq …` — one process sampling one hash seed
seven times, whose disjointness predicate **passed vacuously on `floor10: []`**: `|[] − []| == |[]|`
is `0 == 0`, and an empty list is exactly what a broken fixture produces)*

GIVEN the new tie-break-neutral floor-sensitivity fixture with the edge-bearing competitor
at a dense rank between the two floors (inside `[:15]`, outside `[:10]`)
WHEN the target rank is measured at floor 10 and floor 1000 across the 7-seed C-2 protocol
(**7 spawned processes**)
THEN the two floors' target-rank distributions shall be disjoint and both non-empty.

VERIFY: three steps): — run the command block(s) below; PASS exactly as stated.
```
( cd /home/rynaro/workspace/oss/agents/crystalium && for s in 0 1 2 3 4 5; do docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.run_seed(seed_label='$s'), '/app/evals/results/floor-seed-$s.json')" || exit 1; done )
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.floor_sensitivity_gate as m; m.emit(m.run_seed(seed_label='unset'), '/app/evals/results/floor-seed-unset.json')"
```
```
jq -s -e '{seeds: .} | (.seeds | type == "array") and ((.seeds | length) == 7) and (all(.seeds[]; (.floor10_target_rank | type == "number") and (.floor1000_target_rank | type == "number") and (.floor10_target_rank >= 0) and (.floor1000_target_rank >= 0))) and (([.seeds[].floor10_target_rank] | unique) as $a | ([.seeds[].floor1000_target_rank] | unique) as $b | (($a | length) > 0) and (($b | length) > 0) and ((($a - $b) | length) == ($a | length)))' /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-0.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-1.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-2.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-3.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-4.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-5.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/floor-seed-unset.json
```
**PASS = exit 0.** The non-empty guards (`($a|length) > 0`, `($b|length) > 0`) and the
`>= 0` rank guards close the vacuous-pass hole — a rank of `-1` (the repo's absent sentinel,
`fusion_gate.py:255`) or an empty distribution now FAILS. *Verified during this pass: the
empty-list case returns exit 1 under this predicate and exit 0 under the original.*
Non-disjoint ⇒ STOP **S-5** → **S-13 class (c)**: **retire** AC-138/AC-139 with a mechanism
note; the issue comment says *retired*, not *discharged*. No permanent strict-xfail.

#### AC-323 — UNCHANGED (maker red-check: move the competitor inside both floors ⇒ AC-322 exit non-zero; revert)

### AC-324 (event-driven) — REPLACED (K-N7, K-N19)
*(was: `grep -c "xfail" …` PASS = output `0` (exit 1), plus `git diff b7f1a47 -- evals/fusion_gate.py`
"no output **for the W-G-FLOOR branch**" — unverifiable at the plan's own hop placement, since
post-merge that diff is non-empty **by design** from W-G-XL's mandated rename)*

GIVEN the floor-sensitivity ACs moved to their own fixture
WHEN the **W-G-FLOOR branch tip** is inspected (pre-merge, by explicit ref)
THEN `test_fusion_gate.py` shall carry no xfail marker and no empty
`TestFetchWidthFloorInflation` class, and `evals/fusion_gate.py` shall be byte-identical to
`b7f1a47` **on that branch**.

VERIFY: two parts, both run against the branch ref, not `HEAD`): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && test "$(git show feat/floor-sensitivity-gate-48:mcp-server/tests/test_fusion_gate.py | grep -cE 'xfail|TestFetchWidthFloorInflation' || true)" = "0"
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && test -z "$(git diff b7f1a47 feat/floor-sensitivity-gate-48 -- evals/fusion_gate.py)"
```
**PASS = exit 0 on both.** `git show <ref>:<path>` fails loudly if the ref or path is missing,
so neither part can pass vacuously on a deleted file. The class deletion is asserted alongside
the marker because deleting `:85-113` alone leaves an empty class body (`:42-83` is its
docstring).

#### AC-325 — UNCHANGED

### AC-325b (event-driven) — ADDED (K-B14, W-CLI's own exit gate)
GIVEN W-CLI's registration of the four new gates in `evals/__main__.py`
WHEN each new subcommand runs with `--out`
THEN each shall write a parseable JSON artifact.

VERIFY: run the command block below; PASS exactly as stated.
```
( cd /home/rynaro/workspace/oss/agents/crystalium && for g in cross-layer-gate corpus-scaling-gate weight-discrimination floor-sensitivity-gate; do docker compose run --rm crystalium /app/.venv/bin/python -m evals $g --out /app/evals/results/cli-$g.json || exit 1; done )
```
```
jq -s -e '(length == 4) and (all(.[]; type == "object"))' /home/rynaro/workspace/oss/agents/crystalium/evals/results/cli-cross-layer-gate.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/cli-corpus-scaling-gate.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/cli-weight-discrimination.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/cli-floor-sensitivity-gate.json
```
**PASS = exit 0 on both.** This is the **only** Wave-1 criterion that uses `-m evals` (rule (b)).
Also assert `evals/__main__.py` is the only file W-CLI touched (S-12's per-unit check).

---

## 3. Wave 1 exit — release v2.0.2

### AC-330 (event-driven) — REPLACED (K-N11)
*(was: `make test-ci` then `make test`)*

GIVEN every Wave-1 unit merged to the release branch
WHEN all three suite modes run
THEN all three shall be green.

VERIFY: three commands, all must exit 0): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && make test-ci
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && make test
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose build crystalium && docker run --rm -e CRYSTALIUM_SKIP_SLOW=1 crystalium:dev pytest tests/ -v --tb=short -p no:cacheprovider
```
**PASS = exit 0 on all three.** The third is the **literal CI invocation**
(`.github/workflows/ci.yml:39-44`) against the **baked** image; `make test-ci`
(`Makefile:35`) is a *bind-mount proxy* for it, not CI itself (K-N11) — same test set,
different source of truth, and this repo has two standing scars in that gap. Disagreement
between any two ⇒ STOP **S-9**. *Baseline for comparison (`baseline-verdict.md`):
`make test` = 998 passed / 2 skipped / 1 xfailed; `make test-ci` = 994 passed / 6 skipped /
1 xfailed. Differing **counts** are SKIP_SLOW converting slow tests to skips and are NOT S-9;
S-9 fires on differing **outcomes**.*

### AC-331 (ubiquitous) — REPLACED (K-N5)
*(was: `git diff --name-only` PASS = "empty **or** only comment-only diffs, each demonstrated by
`git diff -w -U0` showing no non-comment line" — `--name-only` emits filenames and cannot show
comment-ness; `-w -U0` is whitespace-ignoring zero-context, **not** a comment filter; and the
hatch **must** be used because W-DOC's `config.py` edit lives under `mcp-server/src/`)*

GIVEN the v2.0.2 batch
WHEN its diff against `v2.0.1` under `mcp-server/src/` is inspected
THEN the system shall show no non-comment, non-blank changed line, and shall touch no file
other than `config.py`.

VERIFY: three parts, all required): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && git rev-parse --verify v2.0.1^{commit}
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && test "$(git diff v2.0.1..HEAD --name-only -- mcp-server/src/ | grep -cvFx 'mcp-server/src/crystalium/config.py' || true)" = "0"
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && test "$(git diff v2.0.1..HEAD -U0 -- mcp-server/src/ | grep -E '^[+-]' | grep -vE '^(\+\+\+|---)' | sed -E 's/^[+-][[:space:]]*//' | grep -cvE '^(#|$)' || true)" = "0"
```
**PASS = exit 0 on all three.** Part 1 is the anti-vacuity guard: a missing `v2.0.1` ref would
otherwise make parts 2 and 3 pass on an empty diff. Part 3 is a genuine comment/blank filter
(strip the diff marker and leading whitespace; every surviving line must start `#` or be
empty). This is what makes the "zero production-code change" claim mechanical rather than an
eyeball.

### AC-332 (event-driven) — REPLACED (K-B9; FORGE D8)
*(was: `jq -e '[.gates[] | select(.independently_reproduced==true)] | length == 4'` — a boolean
a replayer writes identically, and a count of **4** that silently excluded the entrypoint gate
from the v2.0.2 batch's **five** red-checkable artifacts)*

GIVEN the v2.0.2 release candidate
WHEN the checker independently re-breaks each of the five artifacts with a perturbation
that differs from the maker's **axis**
THEN each shall go red under the checker's own perturbation, with the patch, command, tree
SHA, non-zero exit, output tail and restore proof recorded.

VERIFY: three parts): — run the command block(s) below; PASS exactly as stated.
```
jq -e '(type == "object") and (.gates | type == "array") and ((.gates | length) == 5) and (([.gates[].gate] | unique | length) == 5) and (([.gates[] | select((.perturbation_patch | type == "string") and ((.perturbation_patch | length) > 0) and (.command | type == "string") and (.tree_sha | type == "string") and (.axis | type == "string") and (.exit_code | type == "number") and (.exit_code != 0) and (.output_tail | type == "string") and (.restore.exit_code == 0))] | length) == 5)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/checker-redcheck.json
```
```
jq -e '(type == "object") and (([.gates[].gate] | sort) == ["corpus-scaling","cross-layer","entrypoint","floor-sensitivity","weight-discrimination"])' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/checker-redcheck.json
```
```
python3 -c "
import json
c = json.load(open('checker-redcheck.json'))['gates']
m = json.load(open('red-evidence.json'))['gates']
mp = {g['perturbation_patch'] for g in m}
dup = [g['gate'] for g in c if g['perturbation_patch'] in mp]
assert not dup, ('replayed maker patch', dup)
assert len(c) == 5, ('expected 5 checker rows', len(c))
print('ok', len(c))
"
```
**PASS = exit 0 on all three.** Part 1 rejects a boolean file outright — *verified during this
pass: a `{gate, independently_reproduced: true}` file returns exit 1, as does any file with one
`exit_code: 0` or only four gates.* Part 3 is D8's **anti-replay** step: an identical
`perturbation_patch` on both sides fails. `red-evidence.json` carries the same schema on the
maker side so the diff has structured input.
**Honest limit, stated:** a checker who fabricates outputs outright cannot be stopped by any
file format. The schema makes **replay detectable** (identical patch) and **fabrication
falsifiable on audit** (every recorded command re-runs against the recorded SHA). That is the
maximum a self-describing artifact can carry — and it is strictly more than a boolean.
**Reversal (D8):** if maker and checker independently converge on the same minimal patch, the
checker documents the collision and substitutes a second axis-distinct perturbation; the
requirement is **axis independence**, not patch-text novelty for its own sake.

### AC-333 (ubiquitous) — REPLACED (K-B12)
*(was: `ramza-gate status --state …` — PASS = "a critic record is present with
`author != checker`". Three defects, all confirmed by running the read-only command: `status`
prints `{plan, tier, phase, next, refine_cycles, skips, criteria_frozen}` and **never surfaces
the critic**; the state file **already** carries `{"author":"ramza","checker":"kupo"}` written
at plan time, so the AC passed **before v2.0.2 existed**; and `ramza-gate` writes a **single
`.critic` object** it overwrites, so there is no second slot)*

GIVEN the v2.0.2 release
WHEN the critic record for **that batch** is inspected
THEN the system shall record a critic whose identity differs from the author, **timestamped
after the batch's first unit merged**.

VERIFY: two parts, both required): — run the command block(s) below; PASS exactly as stated.
```
jq -e '(type == "object") and (.batch == "v2.0.2") and (.author | type == "string") and (.checker | type == "string") and (.author != .checker) and (.at | type == "string") and (.at > .batch_started_at) and (.artifacts_rebroken == 5)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/critic-v2.0.2.json
```
```
jq -e '(type == "object") and (.critic | type == "object") and (.critic.author != .critic.checker)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/plans/crystalium-residual-eight-plan.state.json
```
**PASS = exit 0 on both.** Part 1 is the per-batch record in CHANGE (the mechanism that makes
AC-362 possible at all); the `.at > .batch_started_at` binding is what stops the plan-time
critic entry from satisfying a release-time criterion. Part 2 reads the state file **directly**
— the observability defect in `ramza-gate status` is routed around, not asserted through.
`ramza-gate critic --author <maker> --checker <checker>` is still run (it is the recorded gate);
this criterion just does not depend on `status` to observe it.

---

## 4. Wave 2 — behaviour

### AC-340 (event-driven) — UNCHANGED-BUT-RE-ANCHORED (rules (a)(b)(c))
GIVEN W-45 merged with the Option A fetch shape
WHEN the cross-layer gate runs
THEN the semantic target shall be at fused rank 0
VERIFY: re-emit the artifact (AC-310 step 1), then run the command block below; PASS exactly as stated.
```
jq -e '(type == "object") and (.target_rank | type == "number") and (.target_rank == 0) and (.liveness.sparse_arm_size == (.liveness.corpus_per_layer + 1)) and (.liveness.global_bm25_rank0 == "sem-target")' /home/rynaro/workspace/oss/agents/crystalium/evals/results/cross-layer-gate.json
```
**PASS = exit 0.** The liveness conjuncts ride along so a post-fix green cannot come from a
broken fixture.

### AC-341 (ubiquitous) — REPLACED (K-N7; FORGE D7's fold-in)
*(was: `git show --stat HEAD` post-merge — under squash-merge `HEAD` touches everything and
passes vacuously; post-merge `HEAD` is not W-45's commit at all)*

GIVEN the ordering-fix commit on the **W-45 branch, pre-merge**
WHEN its file list is inspected by explicit ref
THEN the xfail-marker removal shall be in the **same commit** as the `retrieve.py` change.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && test "$(git show --name-only --format= fix/cross-layer-rank-blocking-45 | grep -cE '^(mcp-server/src/crystalium/aetheryte/retrieve\.py|mcp-server/tests/test_cross_layer_gate\.py)$' || true)" = "2"
```
**PASS = exit 0.** The branch ref is explicit and the count is asserted **positively at 2**, so
neither a squash nor a wrong `HEAD` can satisfy it. Run **before** the merge to the release
branch (`spec.md`'s hop placement puts the checker after the merge — that is where K-N7 bites).

#### AC-342, AC-343 — UNCHANGED

### AC-344 (event-driven) — UNCHANGED-BUT-RE-ANCHORED (rules (a)(c)(d); K-N17)
`evals/fusion_gate.py` is **frozen** (§3.1) and cannot gain `emit`, so this is rule (a)'s
`awk` fallback. `-m evals fusion-gate` is a **pre-existing** subcommand, so rule (b) does not
apply.

GIVEN the AC-125 fusion A/B run across the 7-seed C-2 protocol after each Wave-2 link
WHEN the seven per-seed artifacts are collected
THEN all seven runs shall report `gate_pass` exactly `true`
VERIFY: three steps — run the command blocks below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && for s in 0 1 2 3 4 5; do docker compose run --rm -e PYTHONHASHSEED=$s crystalium /app/.venv/bin/python -m evals fusion-gate | awk '/^\{/{f=1} f' > evals/results/fusion-seed-$s.json; done
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -m evals fusion-gate | awk '/^\{/{f=1} f' > evals/results/fusion-seed-unset.json
```
```
jq -s -e '(length == 7) and (all(.[]; (type == "object") and (.gate_pass == true) and (.weighted.target_rank == 0) and (.unweighted.target_rank | type == "number") and (.unweighted.target_rank != 0)))' /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-0.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-1.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-2.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-3.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-4.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-5.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/fusion-seed-unset.json
```
**PASS = exit 0.** The seventh run **omits `-e` entirely** (K-N17: `-e PYTHONHASHSEED=` sets it
*empty*, which is not *unset*). `.gate_pass == true` is asserted **positively** — `!= false`
passes on `null`, which VP-B4 proved is a live value in this repo. Any red ⇒ STOP **S-6**
(contingency six). Run after **each** Wave-2 link.

### AC-345 (event-driven) — REPLACED (K-B5; FORGE D7)
*(was: a shipped pytest node asserting pre-fix starvation, in a file W-44 itself creates, whose
PASS was "exit 0 **on the pre-fix tree**" — mutually exclusive with AC-346 on the tagged tree,
while the release checklist demanded both green)*

GIVEN a corpus whose top-`candidate_k` BM25 hits are all deprecated, with
`recall_active_only=True` (production parity, `config.py:333`)
WHEN recall runs on the pre-fix base and again on the released tree
THEN the pre-fix characterisation shall be recorded and re-derivable from git history, and
the node shall report **XFAIL** on the released tree.

VERIFY: two parts, both required): — run the command block(s) below; PASS exactly as stated.

(i) the commit-1 characterisation, re-run by the checker at the recorded SHA:
```
cd /home/rynaro/workspace/oss/agents/crystalium && git checkout $(jq -r '.commit1_sha' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/ac345-prefix-evidence.json) && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_prefix_baseline_starves_active_hits -v
```
**PASS = exit 0** at that SHA (the node is **unmarked** there and genuinely green).

(ii) the sentinel on the release tree:
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_prefix_baseline_starves_active_hits -v -rxX
```
**PASS = exit 0 with the node reported `XFAIL`.** **Not PASS, not FAIL: `XFAIL`.** The marker is
`@pytest.mark.xfail(strict=True, reason="pre-#44 starvation characterisation; XPASS = starvation regression (#44)")`,
landed in the **same commit** as the `retrieve.py` fix. **XPASS ⇒ strict ⇒ suite RED** — the
sentinel is self-enforcing on every future tree (`test_fusion_gate.py:85-103` precedent).
**Checklist convention:** *"AC-345 green = XFAIL on the tagged tree; XPASS is RED."*

### AC-346 (event-driven) — UNCHANGED-BUT-RE-ANCHORED (FORGE D6)
GIVEN the deprecated-top-hits corpus on the post-#44 build, with `recall_active_only=True` (production parity, `config.py:333`)
WHEN recall runs
THEN the active hits shall be present in `result.records`
VERIFY: `cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_topup_recovers_active_hits -v` — PASS = exit 0.

The GIVEN clause gains *"with `recall_active_only=True` (production parity, `config.py:333` →
`server.py:600`, `__main__.py:351`)"*, and the fixture asserts the pin by **read-back off the
`Aetheryte` instance** (`assert aetheryte.recall_active_only is True`) — never off the kwargs
dict it just wrote. Command unchanged.

### AC-347 (unwanted-behavior) — UNCHANGED-BUT-RE-ANCHORED (same GIVEN-clause pin as AC-346)
GIVEN the status-aware top-up with `recall_active_only=True` (production parity, `config.py:333`)
WHEN the top-up call is deleted while its `explain.fusion.sparse_topup` counter is left in place
THEN AC-346 shall go red
VERIFY: delete the call, keep the counter, re-run AC-346's command, confirm exit non-zero, then restore — PASS = exit non-zero before restore and exit 0 after. A counter that stays truthful after its code is removed is the #36 F-V3 defect.

### AC-348 (ubiquitous) — REPLACED (K-B10; FORGE D3)
*(was: *"at most one additional `bm25_search` per recall"* with no baseline — incoherent under
Option B's surviving per-layer loop, and Option B was left undecided)*

GIVEN the status-aware top-up on a build shipping **Option A's three-case fetch shape**,
with `recall_active_only=True`
WHEN a recall runs on the dirty-and-censored path
THEN the total `bm25_search` call count shall equal the path's fetch-shape baseline plus at
most one.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_at_most_one_extra_query -v
```
**PASS = exit 0.** The node asserts, **by call count on a spy** (never by reading the source),
the **exact** per-path baseline and the top-up's increment:

| path | fetch-shape baseline | with top-up |
|---|---|---|
| `layers=None` (all four) | 1 (global) | `<= 2` |
| `len(target_layers) == 1` | 1 (filtered) | `<= 2` |
| strict subset, `len >= 2` | `1 + backstop_count` (`backstop_count ∈ {0} ∪ {len(target_layers)}`) | baseline `+ <= 1` |

The top-up widens the **global head call only**; the §B.3.1 starvation backstop is a separate
coverage mechanism with its own trigger and is **not** re-issued by the top-up. *(This
composition of D3 and D6/D7 is a maker decision — FORGE ruled the two mechanisms separately and
did not compose them. If AC-348 and AC-355 cannot both be satisfied under it, that is an S-13
event: route it to the ladder, do **not** relax either gate.)*

#### AC-349 — UNCHANGED (`bm25_search` signature and SQL frozen; non-empty diff without an
ALLOW in `fence-amend.json` is NC-5 tamper evidence)

### AC-350 (event-driven) — REPLACED (K-B2; FORGE D2)
*(was: one node on "a fixture where a seed is reachable from another seed" — a **depth-1**
relation, on which `spec.md`'s two-site `exclude_seeds=False` was byte-identical to `True`, so
the criterion could not discriminate and AC-351 could not go red)*

GIVEN `exclude_seeds=True` (the default)
WHEN `neighbor_expand` and `decaying_walk` run on **all three** topologies T1, T2 and T3
THEN the returned sets and weights shall be byte-identical to `b7f1a47`.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py -v -k "exclude_seeds_default_is_byte_identical"
```
**PASS = exit 0**, with **three** parametrised cases collected (T1, T2, T3). Expected
True-branch values (traced against `b7f1a47` during this pass):

| topology | graph | call | expected |
|---|---|---|---|
| **T1** | seeds `{S1,S2}`; `S1→S2`, `S1→N1` | `neighbor_expand(["S1","S2"], depth=1)` | `{"N1"}` |
| **T2** | seeds `{S1,S2}`; `S1→M`, `M→S2`, `M→N2` | `neighbor_expand(["S1","S2"], depth=2)` | `{"M","N2"}` |
| **T3** | same as T2 | `decaying_walk(["S1","S2"], max_hops=2, decay=0.5)` | `{"M":0.5,"N2":0.25}` |

### AC-351 (unwanted-behavior) — REPLACED (K-B2; FORGE D2)
*(was: "flip the default to False ⇒ AC-350 must go red" — it could not, at depth 1)*

GIVEN the five-site `exclude_seeds` threading of FORGE D2
WHEN the `exclude_seeds` default is flipped to `False`
THEN AC-350 shall go red on T1 alone
VERIFY: flip the default in `graph.py`'s `neighbor_expand` signature, then run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py -v -k "exclude_seeds_default_is_byte_identical and T1"
```
**PASS = exit NON-ZERO** (this is a red-check), then restore and re-run AC-350 green.
This is falsifiable only because D2 threads **all five** sites: `graph.py:225` (via a new
`exclude_input` parameter on `_neighbor_expand_one_hop`), the `:271` call site, `:272`
(`if exclude_seeds: hop_ids -= original_seeds`), `:302`
(`visited = set(seed_ids) if exclude_seeds else set()`), and the `:305` pass-through.
With `spec.md`'s two sites, `:272` alone kept exclusion **fully in force** and this red-check
could not fire.

### AC-352 (event-driven) — REPLACED (K-N15)
*(was: `jq -e '.p1_recreated == false'` on a field the maker's own module computes — a
degenerate fixture reports `false` and passes; STOP S-1 hangs off it)*

GIVEN seed exclusion relaxed on the retrieval path
WHEN the DP-1(b) re-check runs on the weight-discriminating fixture
THEN no derived-only record shall outrank a record backed by two base arms — **and the same
fixture shall demonstrably re-create P1 on demand.**

VERIFY: two parts, both required): — run the command block(s) below; PASS exactly as stated.

(i) the re-check:
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run_dp1_recheck(), '/app/evals/results/wd-dp1-recheck.json')"
```
```
jq -e '(type == "object") and (.p1_recreated == false) and (.w_derived == 1.0) and (.derived_only_rank | type == "number") and (.two_base_arm_rank | type == "number") and (.derived_only_rank > .two_base_arm_rank)' /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-dp1-recheck.json
```

(ii) the **positive control** — the same fixture must be able to say `true`:
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "import evals.weight_discrimination as m; m.emit(m.run_dp1_recheck(w_derived=100.0), '/app/evals/results/wd-dp1-control.json')"
```
```
jq -e '(type == "object") and (.p1_recreated == true) and (.w_derived == 100.0) and (.derived_only_rank < .two_base_arm_rank)' /home/rynaro/workspace/oss/agents/crystalium/evals/results/wd-dp1-control.json
```
**PASS = exit 0 on both.** Part (ii) is `config.py:296-298`'s stated ceiling (*"Values ABOVE
1.0 re-create P1: a derived-only record at w/61 can outrank a record backed by two base arms"*)
used as a **mechanical positive control**. **A fixture that cannot re-create P1 on demand
cannot falsify its absence** — without (ii), part (i)'s `false` is not evidence and **STOP S-1
cannot be cleared**. Part (i) `true` triggers **S-1**: keep exclusion, close #42
policy-affirmed with the measurement.

### AC-353 (state-driven) — REPLACED (positive-guard hardening; rule (c))
*(was: pytest green plus `git diff … -- mcp-server/src/crystalium/dream/` "no output" — the
second half passes vacuously if the path is mistyped or the range is bad)*

GIVEN seed exclusion relaxed on the retrieval path
WHEN the Dream suites run
THEN the system shall leave the Dream consolidation path unaffected.

VERIFY: three parts, all required): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_dream_worker.py mcp-server/tests/test_dream_gate.py mcp-server/tests/test_dream_scheduler.py -v
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && test "$(git ls-tree -r --name-only b7f1a47 -- mcp-server/src/crystalium/dream/ | wc -l)" -gt "0"
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && test -z "$(git diff b7f1a47..HEAD -- mcp-server/src/crystalium/dream/)"
```
**PASS = exit 0 on all three.** Part 2 proves the path exists at the base ref, so part 3's
emptiness is meaningful rather than a typo. Dream is untouched **by construction** —
`exclude_seeds` defaults to `True`, which is today's behaviour byte-identically (AC-350).

### AC-354 (event-driven) — ADDED (FORGE D2)

GIVEN `exclude_seeds=False` (the opt-in relaxation)
WHEN `neighbor_expand` and `decaying_walk` run on T1, T2, T3 and the T3-variant
THEN the returned sets and weights shall be exactly as enumerated, including a seed
credited at its **true shortest-hop** distance.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_storage_graph.py -v -k "exclude_seeds_false_expected_sets"
```
**PASS = exit 0**, with **four** parametrised cases collected. Expected False-branch values
(traced against `b7f1a47` during this pass):

| topology | call | expected |
|---|---|---|
| **T1** seeds `{S1,S2}`; `S1→S2`, `S1→N1` | `neighbor_expand(["S1","S2"], depth=1, exclude_seeds=False)` | `{"N1","S2"}` |
| **T2** seeds `{S1,S2}`; `S1→M`, `M→S2`, `M→N2` | `neighbor_expand(["S1","S2"], depth=2, exclude_seeds=False)` | `{"M","N2","S2"}` |
| **T3** same graph as T2 | `decaying_walk(["S1","S2"], max_hops=2, decay=0.5, exclude_seeds=False)` | `{"M":0.5,"N2":0.25,"S2":0.25}` |
| **T3-variant** seeds `{S1,S2}`; single edge `S1→S2` | `decaying_walk(["S1","S2"], max_hops=2, decay=0.5, exclude_seeds=False)` | `{"S2":0.5}` |

**T2 additionally discharges the `graph.py:266` PROOF OBLIGATION**: `visited = set(frontier)` is
deliberately left unchanged under both flag values, on the derivation that it controls
*re-expansion*, not *result membership*. T2's `S2` is discovered at hop 2 and must appear in
`result_ids` **with `:266` untouched**. **Reversal (D2):** if T2 shows `S2` absent, `:266` (or
the `:274` frontier arithmetic) is load-bearing for membership after all — the
`:266`-unchanged clause is overturned and the site list reopens.

### AC-355 (event-driven) — ADDED (K-N12; FORGE D3)

GIVEN Option A's three-case fetch shape and a corpus of `E = 4 * candidate_k` episodic rows
all strictly better in BM25 than `S = candidate_k` semantic rows
WHEN recall runs with `layers=["semantic", "procedural"]` — a **2-layer strict subset**
THEN the planted semantic target shall be recalled and the sparse candidate set shall
contain at least `min(S, candidate_k)` semantic rows.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_retrieve_layer_merge.py::test_subset_layer_recall_no_regression -v
```
**PASS = exit 0.** Node name is **normative**. This is the gate for Option A's real regression:
with `layer_filter=None` + post-filter, the global top-`N` can be dominated by **excluded**
layers and a strict subset recovers *fewer* rows than today. It is **RED on a naive
global+post-filter implementation and GREEN only when the §B.3.1 starvation backstop exists** —
it can fail on the defect it names. A **1-layer** subset never reaches the global path under
the three-case shape and therefore cannot see the defect; the 2-layer minimum is normative.
The **dense arm is pinned empty** in this fixture (`dense_search.return_value = []`) so the
node measures the sparse backstop on one axis — a `MagicMock` dense stub ignores
`layer_filter`, and letting it be post-filtered would confound the measurement (§0.2).

### AC-356 (event-driven) — ADDED (FORGE D6)

GIVEN the same #44 corpus with `recall_active_only=False`
WHEN recall runs
THEN the top-up shall be inert: zero additional `bm25_search` calls and
`explain.fusion.sparse_topup.fired == false`.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium pytest mcp-server/tests/test_sparse_status_topup.py::test_topup_inert_when_active_only_off -v
```
**PASS = exit 0.** Node name is **normative**. `_is_active` returns unconditionally `True`
when the flag is off (`retrieve.py:573-574`), so `n_inactive_observed == 0` and nothing may
fire. This documents the flag-off path as **deliberately out of scope** and prevents the top-up
from firing where the predicate is vacuous. **Reversal (D6):** if this control shows the top-up
firing with the flag off, the implementation gated it on the wrong predicate — **stop**, it is
in the fence's territory.

---

## 5. Wave 2 exit — release v2.1.0

### AC-360 (event-driven) — REPLACED (K-N11)
GIVEN all three Wave-2 links merged to the v2.1.0 release branch
WHEN all three suite modes run
THEN all three shall be green
VERIFY: the identical three-command form as AC-330 (`make test-ci`, `make test`, and the baked-image CI invocation after `docker compose build crystalium`), run on the v2.1.0 RC — PASS = exit 0 on all three. Disagreement in **outcome** triggers STOP S-9; differing **counts** do not.

### AC-361 (ubiquitous) — REPLACED (K-N16)
*(was: *"capture the wire … `diff` the two captures — PASS = differences confined to
`result.content` payload ordering"* — a human-judged diff, while a **mechanical** comparator
already exists in the same archive directory and was never mentioned)*

GIVEN the v2.1.0 release
WHEN the wire is captured before and after and compared with the archived comparator
THEN the system shall show no breaking client-visible change.

VERIFY: three steps): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && git checkout v2.0.1 && docker compose run --rm -v /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/archive/2026-08-05-crystalium-mcp-sdk-2x-39:/wire crystalium /app/.venv/bin/python /wire/golden_wire.py /app/evals/results/wire-v2.0.1.json
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && git checkout <v2.1.0-rc-ref> && docker compose run --rm -v /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/archive/2026-08-05-crystalium-mcp-sdk-2x-39:/wire crystalium /app/.venv/bin/python /wire/golden_wire.py /app/evals/results/wire-v2.1.0.json
```
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/archive/2026-08-05-crystalium-mcp-sdk-2x-39 && python3 compare_wire.py /home/rynaro/workspace/oss/agents/crystalium/evals/results/wire-v2.0.1.json /home/rynaro/workspace/oss/agents/crystalium/evals/results/wire-v2.1.0.json
```
**PASS = exit 0 on the comparator** (*"exit 0 = identical modulo the documented exclusions;
exit 1 = regression"*). `compare_wire.py` compares tool names, descriptions, `inputSchema`,
capabilities, `protocolVersion`, **`isError` on every path**, error payload text and record
shapes **verbatim**, excluding only `serverInfo.version` and the volatile record keys
(`id`, `created_at`, …) whose **presence is still asserted**. NC-6 is thereby honoured
mechanically: `__version__` derives from installed package **METADATA** and a dev capture
reports the *image's* version — the comparator already excludes exactly that value.

### AC-362 (ubiquitous) — REPLACED (K-B12)
*(was: *"a **second** critic record"* from `ramza-gate status` — the tool writes a **single
`.critic` object it overwrites** (`ramza-gate` line 164:
`write_state '.critic = {author: $a, checker: $c, at: $at}'`), so recording the v2.1.0 critic
**destroys** the v2.0.2 one. There is no `critics[]` array. The criterion was unsatisfiable by
the shipped tool.)*

GIVEN the v2.1.0 release
WHEN the critic records for **both** batches are inspected
THEN the system shall show two distinct per-batch records, each with `author != checker`,
ordered in time.

VERIFY: two parts, both required): — run the command block(s) below; PASS exactly as stated.
```
jq -e '(type == "object") and (.batch == "v2.1.0") and (.author != .checker) and (.at | type == "string") and (.artifacts_rebroken == 3)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/critic-v2.1.0.json
```
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && jq -s -e '(length == 2) and (all(.[]; .author != .checker)) and (([.[].batch] | sort) == ["v2.0.2","v2.1.0"]) and (.[0].at < .[1].at)' critic-v2.0.2.json critic-v2.1.0.json
```
**PASS = exit 0 on both.** Two files, one per batch, in the change folder — the only shape the
shipped tool's single-slot `.critic` permits without loss. `ramza-gate critic` is still run per
batch (it is the recorded gate), and its overwrite is expected and harmless because the durable
record lives here.

### AC-363 (event-driven) — REPLACED (K-N18)
*(was: `git show --stat HEAD -- roster/mcps.yaml roster/index.yaml` with **no `cd`**, under a
file-wide convention that every command runs from **MAIN** — those files live in the **nexus**)*

GIVEN each crystalium tag
WHEN the roster is bumped
THEN both roster files shall move in the **same** commit.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/eidolons && test "$(git show --name-only --format= HEAD | grep -cE '^roster/(mcps|index)\.yaml$' || true)" = "2"
```
**PASS = exit 0.** crystalium is **dual-rostered and skew-guarded**; a one-file bump fails the
guard. The count is asserted **positively at 2**. The explicit nexus `cd` is what K-N18
required — every other nexus-side command in the criteria file already carried one.

### AC-364 (event-driven) — UNCHANGED-BUT-RE-ANCHORED
GIVEN the published image digest pinned in the lock
WHEN the lock is verified
THEN `eidolons mcp verify` shall report a definite pass
VERIFY: `cd /home/rynaro/workspace/oss/agents/eidolons && ./cli/eidolons mcp verify` — PASS = exit 0 ONLY.

Command unchanged (`cd /home/rynaro/workspace/oss/agents/eidolons && ./cli/eidolons mcp verify`).
Re-stated because it is routinely misread: **PASS = exit 0 only. Exit 3 is INDETERMINATE, not
a pass.** *"A lock entry is a RECEIPT, not an ORDER."* Add the local `.mcp.json` re-pin as a
separate checklist line (routinely forgotten; this repo's `.mcp.json` has repeatedly trailed
the roster).

### AC-365 (event-driven) — ADDED (FORGE D8)

GIVEN the v2.1.0 release candidate
WHEN the checker independently re-breaks each of the **three** Wave-2 artifacts with an
axis-distinct perturbation
THEN each shall go red, recorded under the same evidence schema as AC-332.

VERIFY: three parts): — run the command block(s) below; PASS exactly as stated.
```
jq -e '(type == "object") and (.gates | type == "array") and ((.gates | length) == 3) and (([.gates[].gate] | sort) == ["layer-merge","seed-exclusion","status-topup"]) and (([.gates[] | select((.perturbation_patch | type == "string") and ((.perturbation_patch | length) > 0) and (.command | type == "string") and (.tree_sha | type == "string") and (.axis | type == "string") and (.exit_code | type == "number") and (.exit_code != 0) and (.output_tail | type == "string") and (.restore.exit_code == 0))] | length) == 3)' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/checker-redcheck-v2.1.0.json
```
```
cd /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan && python3 -c "
import json
c = json.load(open('checker-redcheck-v2.1.0.json'))['gates']
m = json.load(open('red-evidence-v2.1.0.json'))['gates']
mp = {g['perturbation_patch'] for g in m}
dup = [g['gate'] for g in c if g['perturbation_patch'] in mp]
assert not dup, ('replayed maker patch', dup)
print('ok', len(c))
"
```
```
jq -e '(type == "object") and (all(.gates[]; .asserted_ac | type == "string")) and (([.gates[].asserted_ac] | sort) == ["AC-340","AC-346","AC-354"])' /home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-residual-eight-plan/checker-redcheck-v2.1.0.json
```
**PASS = exit 0 on all three.** The third part pins each row to the **named AC it must flip
RED**, so a perturbation that reddens *something* does not satisfy a row that names a specific
criterion. The three perturbations are in `verification-plan.amend-01.md` §4's v2.1.0 table.

---

## 6. Wave 3 — disposition

### AC-370 (ubiquitous) — REPLACED (K-N4, K-N5)
*(was: `grep -n "unsupported" config.py` — **case-sensitive** against `UNSUPPORTED` at
`config.py:299`, so it exits 1 today and forces a *new lowercase line* restating what
`config.py:296-312` already says at length)*

GIVEN the sub-1.0 `fusion_weight_derived` band
WHEN `config.py`'s comment block is read
THEN the system shall record the band as formally **unsupported** (not characterised), name
the reopen condition, carry the D4 forward obligation, and present no sub-1.0 value as a
supported dial (C-9).

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import pathlib
s = pathlib.Path('mcp-server/src/crystalium/config.py').read_text()
low = s.lower()
assert 'unsupported' in low, 'no unsupported statement'
assert 'uncharacterized' in low or 'uncharacterised' in low, 'no uncharacterised statement'
assert 'non-stipulated ground truth' in low, 'no reopen condition naming non-stipulated ground truth'
assert 'combiner arithmetic' in low, 'no D4 forward obligation'
assert 'fusion_weight_derived: float = 1.0' in s, 'default moved away from 1.0'
assert 'precision dial' in low, 'C-9 reaffirmation absent'
print('ok')
"
```
**PASS = exit 0 and the literal output `ok`.** Case-insensitive on the prose, **case-exact on
the default value** — the criterion doubles as a guard that the comment edit did not move
`fusion_weight_derived` off 1.0 (which would be an **S-2** event). The existing text at
`config.py:296-312` already satisfies the first, second and last assertions; W-DOC adds the
reopen condition and the forward-obligation line.

### AC-371 (ubiquitous) — REPLACED (K-N3)
*(was: `grep -rn "retrieval gate" docs/ evals/` — exits **1** today; the required statement
**already exists**, at `config.py:311-312`, outside the grep's scope; and the grep matched any
line containing the phrase for any reason while the PASS condition was about *naming the
fusion gate as uninformative*, so it could pass with the required statement absent)*

GIVEN a future weight sweep
WHEN the eval notes are read
THEN the statement that the **fusion** gate cannot express weight sensitivity and only the
**retrieval** gate is informative shall (i) survive this campaign in `config.py` and (ii) be
**reachable from `evals/`**, where a sweep author actually reads.

VERIFY: run the command block below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import pathlib
cfg = pathlib.Path('mcp-server/src/crystalium/config.py').read_text().lower()
assert 'fusion gate cannot express' in cfg, 'config.py note lost'
assert 'only the retrieval gate is informative' in cfg, 'config.py note lost'
notes = pathlib.Path('evals/BENCH-NOTES.md')
assert notes.is_file(), 'BENCH-NOTES.md missing'
n = notes.read_text().lower()
assert 'retrieval gate' in n and 'fusion gate' in n, 'no pointer in BENCH-NOTES.md'
assert 'weight' in n, 'pointer does not name weight sensitivity'
assert 'config.py' in n, 'pointer does not cite the canonical statement'
print('ok')
"
```
**PASS = exit 0 and the literal output `ok`.** (i) is a **non-regression** assertion that a
careless `config.py` edit genuinely can fail. (ii) is #55 item 3's actual deliverable — a
pointer line in `evals/BENCH-NOTES.md` (W-DOC's grant), because an eval author running a sweep
reads `evals/`, not `config.py`.

### AC-372 (unwanted-behavior) — REPLACED (positive-guard hardening)
*(was: `git diff … | grep -A3 candidate_k` — PASS = *"either no change, or a change accompanied
by a comment…"*, which is not mechanically decidable from that pipeline and passes on an empty
diff for any reason including a bad ref)*

**IF** `candidate_k` is changed without a recorded response curve
THEN the change shall carry an explicit unsupported-claim fence in its comment.

VERIFY: two parts): — run the command block(s) below; PASS exactly as stated.
```
cd /home/rynaro/workspace/oss/agents/crystalium && git rev-parse --verify b7f1a47^{commit}
```
```
cd /home/rynaro/workspace/oss/agents/crystalium && docker compose run --rm crystalium /app/.venv/bin/python -c "
import subprocess, sys
d = subprocess.run(['git','diff','b7f1a47..HEAD','--','mcp-server/src/crystalium/aetheryte/retrieve.py'], capture_output=True, text=True, check=True).stdout
lines = [l for l in d.splitlines() if l[:1] in '+-' and not l.startswith(('+++','---'))]
touched = [l for l in lines if 'candidate_k' in l and l.startswith('+')]
if not touched:
    print('ok: candidate_k untouched'); sys.exit(0)
assert 'no shipped measurement validates' in d.lower(), 'candidate_k changed without the unsupported-claim fence'
print('ok: candidate_k changed WITH fence')
"
```
**PASS = exit 0 on both, with one of the two literal `ok:` outputs.** Part 1 is the
anti-vacuity guard. **The recommended disposition remains WONTFIX-with-rationale (§5.1) —
S-13 class (b), WONTFIX plus a reopen condition naming the production signal
(`explain.fusion` data from a real store showing the ceiling binding).** Shipping a scaling
constant and declaring #47 closed is what v1.11.0 did and is why the issue is open a second
time. STOP **S-11** otherwise.

### AC-373 (ubiquitous) — REPLACED (K-N2; FORGE D9)
*(was: `gh issue list --state open --limit 30 --json number | jq -e 'length == 0'` — asserts
**zero open issues repo-wide**, goes red for any unrelated issue, caps at 30, and this campaign
*expects* new filings: §5's "re-file against the fence itself" under S-10, §5.1's WONTFIX
reopen note, and the #41 follow-up family #41-#48)*

GIVEN the eight target issues
WHEN each is queried individually
THEN each shall be closed with a closing comment naming exactly one S-13 disposition class.

VERIFY: two parts): — run the command block(s) below; PASS exactly as stated.
```
( cd /home/rynaro/workspace/oss/agents/crystalium && for n in 42 44 45 47 48 52 55 57; do st=$(gh issue view $n --json state --jq .state) || exit 1; test "$st" = "CLOSED" || { echo "issue $n is $st, not CLOSED"; exit 1; }; echo "issue $n CLOSED"; done )
```
```
( cd /home/rynaro/workspace/oss/agents/crystalium && for n in 42 44 45 47 48 52 55 57; do gh issue view $n --json comments --jq '[.comments[].body] | join(" ")' | grep -qE 'DISPOSITION: (shipped|premise-refuted|unobservable-WONTFIX|retired)' || { echo "issue $n: no DISPOSITION class"; exit 1; }; done )
```
**PASS = exit 0 on both**, printing `issue <N> CLOSED` eight times. The state is compared
**positively** to the literal `CLOSED`: a `--jq 'select(...)'` form would emit nothing and exit
**0** for an OPEN issue, which is the same vacuous-pass shape this amendment exists to remove. Only the **eight target issues**
are queried, so unrelated filings during the campaign do not redden it. The `DISPOSITION:`
sentinel is D9's class vocabulary made mechanical — **"closed" must not cover discharged,
retired, refuted and abandoned alike**, which is how half-work gets declared victory.
*Retired ≠ discharged* (#48 under S-5), and *WONTFIX-with-rationale* carries a named reopen
signal (#47, #55).

---

## 7. Status index

| status | criteria |
|---|---|
| **REPLACED** (14) | AC-304, AC-306, AC-310, AC-312, AC-313, AC-316, AC-317, AC-318, AC-321, AC-322, AC-324, AC-330, AC-331, AC-332 |
| **REPLACED** (cont., 13) | AC-333, AC-341, AC-345, AC-348, AC-350, AC-351, AC-352, AC-353, AC-360, AC-361, AC-362, AC-363, AC-370 |
| **REPLACED** (cont., 3) | AC-371, AC-372, AC-373 |
| **STRUCK** (2) | AC-319, AC-320 |
| **ADDED** (5) | AC-325b, AC-354, AC-355, AC-356, AC-365 |
| **UNCHANGED-BUT-RE-ANCHORED** (7) | AC-305, AC-314, AC-340, AC-344, AC-346, AC-347, AC-364 |
| **UNCHANGED** (10) | AC-301, AC-302, AC-303, AC-311, AC-315, AC-323, AC-325, AC-342, AC-343, AC-349 |

30 REPLACED + 2 STRUCK + 7 RE-ANCHORED + 10 UNCHANGED = **49**, the original count, fully
accounted for. Struck 2, added 5 ⇒ **52 criteria** in force after `amend-01`.
