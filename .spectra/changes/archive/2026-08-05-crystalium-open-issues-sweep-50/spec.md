# spec — `crystalium-open-issues-sweep-50`

| field | value |
|---|---|
| change_id | `crystalium-open-issues-sweep-50` |
| ESL tier | **full** (already right-sized upstream; NOT re-opened, NOT re-right-sized by this document) |
| maker | `vivi` |
| checker | `kupo` |
| target repo | `/home/rynaro/workspace/oss/agents/crystalium` |
| target HEAD | `56c8510` — *"fix(recall): weighted RRF fusion … (#38) (#49)"*, v1.10.0 |
| release | **v1.11.0** (minor: recall results change by design, per the 1.9.0/1.10.0 precedent) |
| planner | RAMZA (read-only; this document contains no code) |

## 0. Scope — frozen inputs, authority, anchor convention

Two inputs are **frozen** and are not re-litigated here:

1. **ATLAS scout report** (evidence-anchored at `56c8510`). Where the GitHub issue text and the
   scout disagree, **the scout wins** — the issue line numbers are stale by ~184 lines for
   `retrieve.py` and by 11 for `server.py` (scout §0). Every anchor below was **independently
   re-derived from `git show 56c8510:<path>`** while writing this spec; where re-derivation
   changed a number it is called out inline.
2. **FORGE triage** — the binding disposition, the work-unit decomposition, and three rulings.
   FIX_NOW = #41 (+N-1, +N-4), #43 (+N-5), #46, #47, N-2. Everything else is REPORT (§4).

Anchor convention: `path:line` always means **at `56c8510`**. `retrieve.py` always means
`mcp-server/src/crystalium/aetheryte/retrieve.py`. `graph.py` = `mcp-server/src/crystalium/storage/graph.py`.
`relational.py` = `mcp-server/src/crystalium/storage/relational.py`.

### 0.1 What this change is NOT

It is not a re-triage. It is not a 2.0.0 train. It is not a fix for #42/#44/#45/#48 (§4).
It does not touch `bm25_search`'s population semantics — see the FORGE ruling quoted in §3.2.

## 1. Approach — campaign shape and the isolation contract

Dependency order (FORGE, binding):

```
W0 → W1 → W1b → { W2 ∥ W3-code ∥ W4 } → W3-measurement → W5
```

**Isolation is a hard constraint, not a convenience.** Each code unit is implemented in its own
git worktree on its own branch, and **no two units may touch the same file**:

| unit | worktree | branch | EXCLUSIVELY owns |
|---|---|---|---|
| W0 / W0b | `/home/rynaro/workspace/oss/agents/crystalium` (main, clean, pre-fix) | `main` @ `56c8510` | **nothing** — measurement only, zero repo file changes |
| W1 | `../crystalium-w1-graph` | `fix/graph-neighbor-expand-41` | `mcp-server/src/crystalium/storage/graph.py`, `mcp-server/tests/test_storage_graph.py`, `mcp-server/tests/test_fusion_gate.py` (contingency only, §2.2.6) |
| W1b | main checkout, post-W1 merge | — | **nothing** — measurement only |
| W2 | `../crystalium-w2-retrieve` | `fix/retrieve-hoist-floor-46-47` | `mcp-server/src/crystalium/aetheryte/retrieve.py`, new `mcp-server/tests/test_retrieve_hoist_floor.py` |
| W3 | `../crystalium-w3-gate` | `fix/retrieval-gate-deconfound-43` | `evals/retrieval_gate.py`, `mcp-server/src/crystalium/config.py`, `mcp-server/src/crystalium/server.py`, `mcp-server/tests/test_retrieval_gate.py` |
| W4 | `../crystalium-w4-relational` | `fix/relational-recency-tiebreak` | `mcp-server/src/crystalium/storage/relational.py`, `mcp-server/tests/test_storage_relational.py` |
| W5 | main checkout (release branch) | release | `CHANGELOG.md`, `mcp-server/pyproject.toml:8`, `mcp-server/src/crystalium/__init__.py:8` (`_FALLBACK_VERSION`) |

W4's test file was an `[ASSUMPTION]` in the FORGE triage; it is now **resolved by the Makefile**:
`Makefile:39-44` names `mcp-server/tests/test_storage_relational.py` as the relational adapter file
that `make test-storage` runs.

**No unit but W5 may touch `CHANGELOG.md` or a version string.** The two version strings are
`mcp-server/pyproject.toml:8` (`version = "1.10.0"`) and `mcp-server/src/crystalium/__init__.py:8`
(`_FALLBACK_VERSION = "1.10.0"`); neither lives in a W1–W4 owned file, so the release unit has a
clean field.

### 1.1 Why per-worktree pytest may run in parallel

`docker-compose.yml` declares **no top-level `name:`** (services begin at `docker-compose.yml:11`)
and the repo tracks **no `.env`**. Docker Compose therefore derives the project name from the
directory basename, so each worktree is a *distinct compose project* with its own
`<dir>_crystalium_data` volume (declared `crystalium_data` at `docker-compose.yml:47-49`, mounted
at `:33`) and its own `.:/app` bind mount (`:24`, relative to the compose file, i.e. that
worktree's tree). Concurrent `pytest` across worktrees is therefore state-isolated.

**One shared resource remains:** the image tag `crystalium:dev` (`docker-compose.yml:21`). If the
image is absent, two concurrent `docker compose run` invocations will both trigger a build of the
same tag. The image MUST be confirmed present (or built once) **before** any parallel phase, and
`make build` MUST NOT run concurrently with anything.

**Eval-gate measurement runs are NEVER parallel** — see `verification-plan.md` §2.

## 2. The units

### 2.1 W0 / W0b — baseline capture (no repo file changes)

**Problem.** The re-baseline that `#41` requires has no baseline to diff against.
`CHANGELOG.md:104-108` mandates it in the repo's own words:

> "follow-up **F-A = #41** … tracks the store-side fix and the re-baseline it requires — #41's own
> text mandates re-running #38's AC-124/AC-125/AC-133 against a re-baselined `eval-before.json`
> once it lands, because repairing membership changes arm composition."

The scout searched crystalium exhaustively: **no `eval-before.json`, no `eval-after.json`** exist
in the target repo (`evals/results/` holds only `.gitkeep`). The only precedent artefacts live in
this nexus at `.spectra/changes/archive/2026-08-03-crystalium-recall-starvation-36/`, and the #38
archive (`.spectra/changes/archive/2026-08-04-crystalium-rrf-fusion-38/`) has a `red-evidence.txt`
but **no `eval-before.json`**. FORGE Decision 3 assigns its production to W0.

**Change contract.** W0 produces `eval-before.json` **in this change folder**
(`.spectra/changes/crystalium-open-issues-sweep-50/eval-before.json`), an array of records
`{seed, git_sha: "56c8510", gate, cmd, output}` over the C-2 multi-run protocol
(`PYTHONHASHSEED` ∈ {0,1,2,3,4,5} plus unset = 7 runs), on **both** gate shapes:

- **fusion shape** (model-free — the dense arm is a `MagicMock`, `evals/fusion_gate.py:223-225`):
  `python -m evals fusion-gate` (`run()`, `fusion_gate.py:269-287`).
- **retrieval shape** (needs the sentence-transformers model; MUST NOT run under
  `CRYSTALIUM_SKIP_SLOW`): `python -m evals retrieval-gate` (`retrieval_gate.py:138-175`).

Output shape is confirmed mechanically: `evals/__main__.py:216` is
`json.dump(out, sys.stdout, indent=2, default=str)` — every subcommand prints its dict as JSON on
stdout. (This resolves FORGE `[ASSUMPTION] 3`.)

**W0b — the capture gap FORGE's script leaves open.** The triage script captures only
`--floor 10 --reverted` and `--floor 1000 --reverted`. AC-138's frozen VERIFY line
(#38 `spec.criteria.md:295`, sha `e644052e…`) reads:

> "`python -m evals fusion-gate` with the fetch-width floor overridden to 1000, target rank
> unchanged at 0"

— that is the **weighted** arm (`--floor 1000` *without* `--reverted`; `evals/__main__.py:98-99`
passes `weighted=not args.reverted`). A reverted-only capture cannot evaluate AC-138. **W0b**
therefore extends the capture with `--floor 10` and `--floor 1000` on the **weighted** arm, same
7-seed protocol, same pre-fix SHA, appended to the same `eval-before.json`. W0b may run in the
main checkout at any time **before W1 merges**.

**W0c — the DP-2 sweep harness positive control.** The DP-2 re-check (§2.3) sweeps
`fusion_weight_derived ∈ {0.90, 0.95, 1.00}`. FORGE recorded the mechanism as an `[ASSUMPTION]`.
It is now resolved, and the obvious mechanism does **not** work:

- `CRYSTALIUM_FUSION_WEIGHT_DERIVED` exists (`config.py:369`) but **only inside
  `Config.from_env()`** (`config.py:318`). `evals/fusion_gate.py:213` constructs
  `Config(data_dir=…, recall_weighted_fusion=…, rate_limit_per_minute=…)` **directly**, so the
  env var never reaches the gate.
- `Config` is a plain `@dataclass` (`config.py:82-83`). Assigning
  `Config.fusion_weight_derived = 0.95` after class creation does **not** change the default baked
  into the generated `__init__`. A naive monkeypatch silently no-ops.

The sweep therefore runs through a throwaway in-container script (never a repo file) that replaces
`crystalium.config.Config` with a subclass whose `__init__` injects the swept value — and it MUST
carry a **positive control**: at the pre-fix SHA the harness must reproduce the recorded
measurement at `config.py:238-243`:

> "MEASURED cliff (deliberation.md DP-2, real fusion-gate runs, 7 hash seeds): **0.90 fails the
> gate deterministically**; 0.95 is a FLAKE … 1.00 passed 7/7 runs"

If the harness reports 0.90 as **green** at `56c8510`, the harness is broken, not the code — the
sweep is void and the campaign STOPs. Running the control at the pre-fix SHA (main checkout,
before W1 merges) is what makes the control independent of #41's effect on the cliff.

**Invariants W0 must not break.**
- **Zero repo file changes.** The tree at `56c8510` must be clean before and after; scripts live in
  the container's `/tmp` or in this change folder. (`git status --porcelain` empty.)
- **Single runs are not comparable** — `test_fusion_gate.py:70-73` records the 7-run protocol as
  the measurement contract. Every downstream comparison is distribution-wise (median / unanimity).
- **No fixture contamination across seeds.** Confirmed safe: `fusion_gate.py:211-212` and
  `retrieval_gate.py:77` both uniquify the per-arm data dir with a `uuid.uuid4().hex[:8]` tag, so
  repeated runs inside one container accumulate directories but never share a store.

**Non-goals for W0.** No config edit, no code edit, no `evals/results/` write (baselines are
campaign artefacts in the nexus, per the #36 precedent).

### 2.2 W1 — GraphStore cursor + pattern repair (#41, N-1, N-4)

#### 2.2.1 Problem, anchored

`graph.py:232-253` — the exception boundary sits **outside** the seed loop:

```
232        try:
233            for seed_id in seed_ids:
…
245                result = conn.execute(query, {"seed": seed_id})
246                while True:
247                    row = result.get_next()
248                    if row is None:
249                        break
250                    neighbor_id = row[0]
251                    if neighbor_id not in seed_ids:
252                        result_ids.add(neighbor_id)
253        except Exception as exc:
```

The kuzu driver (0.11.3, scout container-measured) **raises** `RuntimeError: No more tuples in
QueryResult` at cursor exhaustion and never returns `None`, so `graph.py:248` is a dead branch and
the raise from seed 1 unwinds past the `for` at `:233`. Seeds 2..N are never queried.

The repo already knows the correct idiom — `graph.py:185-186`:

> "Verify both nodes exist; use has_next() before get_next() to avoid 'No more tuples'
> RuntimeError when the query returns 0 rows."

used at `graph.py:191` (`if not result.has_next():`).

**Severity is worse than the issue states** (scout measurement, and this is the clause where the
scout corrects the issue text): when the *first* seed has no out-edges, `neighbor_expand` returns
the **empty set** even though later seeds have neighbours — measured `expand([e0,s1,s2]) = []`.
The behaviour is not "explores one seed"; it is "aborts at the first cursor exhaustion, whatever
that seed yielded".

Blast radius (every real call site):
- `retrieve.py:660-662` — production recall, `seed_ids = prelim[:fetch_width]` (`:653`) or
  `dense_ranking[:fetch_width]` (`:655`) with `fetch_width = max(k, FETCH_WIDTH_FLOOR)` (`:558`),
  i.e. **up to 10 seeds, 1 explored**.
- `dream/worker.py:599` — production Dream clustering, up to 20 ids (`worker.py:592-595`).
- `graph.py:278` — `decaying_walk` passes `list(frontier)`, a `set` (`:276`), so the surviving seed
  is chosen by per-process hash randomisation. The docstring at `graph.py:269-270` ("Reuses the
  **reliable** depth-1 neighbor_expand") is currently false.

**N-1** — `all_edges` (`graph.py:333-336`) uses the same dead `is None` idiom. It returns complete
results today only because its `try` is *per-rel-type inside* the outer loop (`:326` try / `:338`
except / `:340` continue), so each rel's rows are appended before that rel's own raise. Two
consequences: one spurious `all_edges_rel_error` warning per rel type on **every healthy call**
(`:339`), and correctness one refactor away from breaking.

**N-4** — depth ≥ 2 is broken by construction. `graph.py:229-230` builds
`hops = "-[{rel}]->()"` repeated `depth` times, then `graph.py:235` does
`pattern.replace('()', '(b:Crystal)')`, which rewrites **every** `()`, producing
`(a)-[]->(b:Crystal)-[]->(b:Crystal)` — both hops bound to the same variable, matching only
self-loops. Latent: every production call site passes `depth=1`, which takes the separate
shorthand branch at `graph.py:239-244`.

**The test suite structurally cannot fail on any of this.** `test_storage_graph.py:70, 84, 89, 94,
102` pass `["n-seed"]`, `["rf-a"]`, `[]`, `["isolated"]`, `["rf-test"]` — every one single-seed.
Every other `neighbor_expand` reference in the suite is a `MagicMock`. The scout verified
`pytest test_storage_graph.py test_completion.py -q` → **27 passed** on the buggy code.

#### 2.2.2 Change contract

1. **`neighbor_expand`**: replace the `while True: row = result.get_next(); if row is None: break`
   loop with the repo's own `has_next()`-guarded idiom (`graph.py:185-192`); move the exception
   boundary **inside** the per-seed loop so one failing seed cannot abort the remainder, and log the
   failing seed rather than the whole `seed_ids` list.
2. **`all_edges`** (`graph.py:333-336`): same idiom; the healthy path emits **no**
   `all_edges_rel_error`. Returned edge tuples are unchanged.
3. **depth > 1**: replace the chained-pattern construction (`graph.py:229-230, 235`) with iterative
   depth-1 frontier expansion, yielding the docstring's "up to *depth* hops" semantics
   (`graph.py:206`).
4. **`decaying_walk`** (`graph.py:278`): iterate a deterministic order (`sorted(frontier)`), making
   the `graph.py:269-270` docstring true again.

#### 2.2.3 Invariants W1 must not break (quoted from the code)

- **Seed exclusion stays.** `graph.py:251` `if neighbor_id not in seed_ids:` and `graph.py:275`
  `visited: set[str] = set(seed_ids)` are **#42 territory — REPORT, not FIX_NOW**. W1 must not
  relax them. The public contract at `graph.py:215` — *"Set of crystal IDs reachable from seeds
  (excludes the seeds themselves)"* — must hold at **every** depth, including the new iterative
  depth > 1 path (the original `seed_ids` are excluded at every hop, not just hop 1).
- **Signature stability.** `neighbor_expand(self, seed_ids, depth=1, rel_filter=None) -> set[str]`
  (`graph.py:200-205`) is unchanged. No new keyword may be added in this change — FORGE's #42
  ruling reserves `exclude_seeds: bool = True` / `include_seeds: bool = False` for the *later*
  campaign, and adding them here would ship half of a REPORT item.
- **Validation preserved.** `graph.py:223-224` (`raise ValueError(f"Invalid rel_filter: …")`) and
  `graph.py:217-218` (empty seeds → `set()`) keep their exact behaviour; both are pinned by
  `test_storage_graph.py:88-102`.
- **Defensive contract preserved.** `neighbor_expand` still returns a (possibly partial) set rather
  than raising; `all_edges` still returns `[]` on a whole-store error (`graph.py:341-343`).
  `retrieve.py:659-680` and `dream/worker.py:598-599` both wrap the call in their own `try`.
- **Retrieval-side ordering determinism is already handled downstream** and must not be duplicated
  or removed: `retrieve.py:663-672` sorts `neighbour_ids` explicitly, with the comment
  *"`neighbor_expand` returns a `set[str]` whose iteration order is per-process hash-randomised
  (P3); `sorted()` replaces that with a deterministic total order."*

#### 2.2.4 The non-negotiable red-check

FORGE: *"If the new tests do NOT fail on pre-fix code, the tests are not gates — STOP."* This is
the campaign's own instance of the recorded lesson that a gate which cannot fail on the defect it
names is not a gate. The mechanics are fixed in `spec.criteria.md` AC-210 and the evidence file is
`red-evidence.txt` in this change folder (precedent: the #36 and #38 archives both carry one).

#### 2.2.5 A correction to FORGE's test phrasing

FORGE lists "multi-seed expansion equals per-seed union". As literally written that is **false**
while `graph.py:251`'s seed exclusion stands: `neighbor_expand([a])` may return `b` when `a→b`,
whereas `neighbor_expand([a,b])` excludes `b`. The correct, always-true form — and the one the
criterion asserts — is:

```
neighbor_expand(S) == ( ⋃_{s ∈ S} neighbor_expand([s]) ) − set(S)
```

#### 2.2.6 Strict-xfail contingency (sole reason W1 may touch `test_fusion_gate.py`)

`test_fusion_gate.py:85-113` carries `@pytest.mark.xfail(..., strict=True)` on
`test_reverted_build_rank_changes_with_floor`. The repo's own recorded measurement
(`test_fusion_gate.py:79-82`, echoed at `:98-99`) predicts it will **not** flip:

> "Landing crystalium#41 (F-A) will NOT by itself flip this xfail — the blocker here is a
> deliberate reliability trade-off, not anomaly A alone."

If it XPASSes, `strict=True` turns `make test` red. Pre-ruled: that is a **measured AC-139 GREEN** —
W1 removes the marker, records the measurement, and #48's ruling becomes moot. W1 may make *no
other* edit to that file.

#### 2.2.7 Non-goals for W1

#42 (seed exclusion), #45 (layer-major ordering), #48 (the AC-138/139 fixture). W1 must not add the
`exclude_seeds`/`include_seeds` parameters, must not touch `retrieve.py`, and must not modify the
AC-125 fixture in `evals/fusion_gate.py` — `test_fusion_gate.py:61-64` records that the tie-free
variant was built, measured, and reverted because it regressed AC-125 from 7/7 to ~2/7 unanimous.

### 2.3 W1b — re-baseline and the mandated re-runs (measurement only)

**Problem.** `#41` changes *membership*, not merely ordering, in the derived arms. Every fusion
figure in the v1.10.0 evidence trail was measured on a one-seed expansion (`CHANGELOG.md:96-108`).
The three #38 criteria that touch those arms must be re-evaluated.

**Change contract.** Repeat W0/W0b's exact protocol at post-W1 `HEAD` → `eval-after.json` in this
change folder. Evaluate against the **frozen** #38 `spec.criteria.md`
(sha `e644052e868db47b49c7daedba904e9f53b67d401c81bde0b5e2887ffcb2fded`), whose VERIFY lines are
reproduced verbatim in `spec.criteria.md` §W1b of this change. Zero repo file changes.

**The confounded-baseline argument (load-bearing — state it, do not soften it).**
`eval-before.json`'s retrieval-gate half is captured on the gate **as it exists**, i.e. **knowingly
confounded** (#43, §2.5). That is not a defect of the baseline:

- AC-124 and AC-133 are **differentials**. Both sides of the differential run the *same* fixture,
  the *same* arm-construction, the *same* `link_cooccurrence` wiring; the **only** variable between
  `eval-before.json` and `eval-after.json` is `graph.py`. A confound that is held constant across
  both sides cannot manufacture or mask a #41-attributable delta.
- What the confounded gate cannot support is an **absolute** claim — e.g. "completion is earned ON
  because F1 rises 0.12→0.18" (`config.py:199`). That claim is exactly what #43 invalidates, and it
  is W3's problem, not W1b's.
- **Baselines are gate-version-scoped.** Once W3 lands, `eval-before.json`/`eval-after.json` are
  **not** comparable to anything the deconfounded gate produces. W3 opens a **new series** with
  `eval-baseline-deconfounded.json`. Diffing across the fixture change is forbidden and is a STOP
  condition in `verification-plan.md` §3.

**DP-2 default re-check.** 7-seed sweep at `fusion_weight_derived ∈ {0.90, 0.95, 1.00}` using the
W0c harness (with its positive control). `config.py:238-252` attributes the 0.95 flake to *"the
OPEN anomaly-A bug in `neighbor_expand` (crystalium#38 follow-up F-A; NOT fixed by this change)"* —
this change *is* that fix, so the sweep is the direct test of that attribution. **Any red at
1.00 → STOP and return to FORGE before any config edit** (`config.py:253` is not W1b-owned in any
case; `config.py` belongs to W3).

**Expected shape, recorded as a finding either way.** Post-fix the distributions should be
(near-)degenerate across seeds — membership is now deterministic and ordering was already sorted
(`retrieve.py:672`). Residual cross-seed variance on the fusion gate is a **new finding** and must
be reported, not smoothed.

**Non-goals for W1b.** No code. No config flip. No CHANGELOG line (W5 owns it).

### 2.4 W2 — `retrieve.py` micro-repairs (#46, #47)

#### 2.4.1 Problem, anchored (the scout's line numbers, not the issue's)

**#46.** `retrieve.py:524` — `query_vec = self.vector_store.embed(query)` sits inside
`for layer in target_layers:` (`retrieve.py:510`), wrapped in `try/except` at `:523-526`. The sole
argument is the bare `query` string: no `layer`, no per-layer parameter — loop-invariant. With
`layers=None` → `_ALL_LAYERS` (`retrieve.py:45`, four entries) → four calls per recall.

**The scout corrects the issue's severity claim, and this spec follows the scout:** `vector.py:55`
holds `self._embed_cache: dict[str, list[float]] = {}` and `vector.py:115-116` short-circuits
(`if text in self._embed_cache: return self._embed_cache[text]`), so calls 2–4 are dict lookups,
not model encodes. This is a **cosmetic micro-optimisation, not a 4× latency win**, and it must be
sized and CHANGELOG'd as such. The one real (small) exception: under `CRYSTALIUM_SKIP_SLOW=1`,
`vector.py:88-92` raises on **every** call and the cache is never populated (`vector.py:118` is
never reached), so today there are four raise/catch/`log.warning("embed_skipped")` cycles per
recall.

**#47.** `retrieve.py:508` — `candidate_k = max(k * 3, 10)`. The literal `10` is the same number as
`FETCH_WIDTH_FLOOR` (`retrieve.py:53`) but is **not linked to it in code**. The coupling is
asserted in prose only, at `retrieve.py:49-50`:

> "Matches the existing candidate_k floor (max(k*3, 10), below) and the shipped default k"

Changing `FETCH_WIDTH_FLOOR` therefore does **not** change `candidate_k`, so `fetch_width`
(`retrieve.py:558`) can silently exceed the per-layer fetch depth with no test failing.
`evals/fusion_gate.py:227-229` proves the state is reachable: it sets the floor to 1000 while
`candidate_k` stays 30.

#### 2.4.2 Change contract

1. Hoist `self.vector_store.embed(query)` from `retrieve.py:524` to between `:508` and `:510`, so
   it is evaluated **once** per recall.
2. `candidate_k = max(k * 3, FETCH_WIDTH_FLOOR)` at `retrieve.py:508` — a no-op at the shipped
   `FETCH_WIDTH_FLOOR = 10`.

#### 2.4.3 Invariants W2 must not break

- **`dense_got_vector` semantics.** Declared at `retrieve.py:506` with the comment *"v1.6 explain:
  did ANY layer's embed() call return a usable vector?"*, set at `:529`, surfaced in `explain`. With
  one hoisted call the "ANY layer" quantifier degenerates; the flag must be assigned **once** from
  the hoisted result and keep its `explain` contract.
- **`query_vec` re-initialisation.** `retrieve.py:522` re-initialises `query_vec: list[float] = []`
  per layer. Hoisting makes one shared value. This is behaviourally identical (the call is
  deterministic and cached) but it *is* a real semantic change and must be stated in the PR body.
- **`embed_skipped` log shape.** `retrieve.py:526` currently emits
  `log.warning("embed_skipped", layer=layer, error=str(exc))`. The `layer` field has **no hoisted
  equivalent**; it becomes `layers=list(target_layers)` (or is dropped). Verified: **no test or eval
  in the repo asserts on `embed_skipped`** (`git grep` over `mcp-server/tests` and `evals` returns
  nothing), so no existing file transfers into W2's ownership. If that changes, the asserting file
  transfers to W2 and must be listed in the PR.
- **`explain.fusion` key set is frozen.** `retrieve.py:1081-1101` builds the dict;
  `test_fusion_weighting.py:499` asserts the key list including `"fetch_width"` and `"candidate_k"`.
  W2 changes the *value* source of `candidate_k`, never the key set. `test_fusion_weighting.py` is
  **not** W2-owned and must remain untouched and green.
- **`FETCH_WIDTH_FLOOR` is a module global.** `evals/fusion_gate.py:227-229` mutates it and restores
  it in a `finally` at `:264`. W2's new floor-link test MUST use `monkeypatch.setattr` (auto-restore)
  — a leaked mutation poisons every later test in the same pytest process.
- **`resolve_sparse_weight`'s censoring contract (C-7).** `retrieve.py:633-637`:
  *"the CENSORING test below reads `raw_n_sparse` — the UNFILTERED fetch length — never
  `n_sparse_resolved`."* `cap = candidate_k * len(target_layers)` (`retrieve.py:593`) is an input to
  that test (`:257` `if raw_n_sparse == 0 or raw_n_sparse >= cap:`). Changing `candidate_k`'s
  *source* must not change its *value* at shipped defaults.

#### 2.4.4 Two corrections to FORGE's neutrality argument (follow this spec, not the triage line)

FORGE justifies #47's neutrality as *"the floor probes run `weighted=False`, skipping the
`cap`-consuming branch"*. That reasoning is **incomplete**:

- `candidate_k` is *also* the per-layer fetch depth at `retrieve.py:513` and `:531`, in **both**
  the weighted and unweighted branches. Under `--floor 1000`, W2's change raises `candidate_k` from
  30 to 1000 on **every** probe, reverted or not.
- `cap` at `retrieve.py:593` is computed unconditionally; only its *consumer* (`:638-641`) is inside
  `if self._weighted:` (`:599`).

Neutrality on the fusion fixture actually rests on two different facts, which the criterion
**measures** rather than assumes: the fixture holds 18 rows total (`fusion_gate.py:160-173`:
target, target-sem, N1-N3, Z, plus `_FILLER_COUNT = 12`), so a 30-row and a 1000-row BM25 fetch
return the same rows; and the dense arm is a `MagicMock` with a fixed 15-id return
(`fusion_gate.py:223-225, 192`) that ignores `k` entirely.

**Second correction — the comparison target.** FORGE's oracle diffs W2's seed-0 run against
"W1b's seed-0 record". The W2 worktree sits at `56c8510`, i.e. **pre-W1**. Diffing a pre-W1 tree
against a post-W1 record measures W1 *and* W2 at once and cannot prove W2 neutral. The rule this
spec imposes: **a neutrality diff is valid only between two trees that differ solely by the unit
under test.** Concretely, `fix/retrieve-hoist-floor-46-47` is rebased onto the merged post-W1 main
before the byte-identity run, and the comparison record is `eval-after.json`'s seed-0 fusion
record. (Rebasing does not violate file isolation: W2 *carries* W1's `graph.py`, it never edits it.)

#### 2.4.5 Non-goals for W2

#44 (`bm25_search` status predicate) and #45 (layer-major ordering) both live in this file and are
**REPORT**. W2 must not add a status predicate, must not reorder the per-layer append loop
(`retrieve.py:510-544`), and must not touch `retrieve.py:605-611`'s ruling block.

### 2.5 W3 — retrieval-gate deconfound (#43, N-5)

#### 2.5.1 Problem, anchored

`evals/retrieval_gate.py:10-14` claims:

> "Honest ablation (D6.4-i): completion flips on only if its arm lifts multi-hop F1 over flat;
> context_match flips on only if it lifts the context-relevant rank. **Edges are seeded in EVERY
> arm, so the only variable is whether the recall walk / re-rank runs — isolating the faculty, not
> the fixture.**"

It is false. `retrieval_gate.py:78` passes the arm variable into `Config` as
`recall_completion=completion`; `_build_components(cfg)` is called at `retrieval_gate.py:84`; and
`server.py:533` and `server.py:546` both read `link_cooccurrence=config.recall_completion`
(the issue text cites 522/535 — **off by 11**; the scout's numbers win, and I re-derived both).
`episodic.py:267` calls `self._link_cooccurrence(...)` on every commit; `episodic.py:92-106`
early-returns at `:95` when the flag is off, and otherwise adds up to `cooccurrence_limit`
(default **5**, `episodic.py:58`) `LINKS_TO` edges per commit.

The fixture commits **31** crystals (`retrieval_gate.py:88-102`: hub + 2 spokes + 2 noise + 24
distractors + 2 context). Therefore:

| arm | `recall_completion` | edges in the graph |
|---|---|---|
| `flat` (F,F), `ctx` (F,T) | False | **2** — only the explicit `hub→spoke1→spoke2` chain (`retrieval_gate.py:107-110`) |
| `comp` (T,F), `both` (T,T) | True | 2 **+ up to ~150 co-occurrence `LINKS_TO` edges** |

The graph topology differs by two orders of magnitude between arms. The measured `completion` lift
cited as the earned-ON justification for a **shipped default** at `config.py:199` —
*"EARNED ON (T2) … (retrieval_gate F1 0.12→0.18, recall 0.67→1.0)"* — cannot distinguish
"the walk ran" from "there were ~75× more edges to walk".

**Second half — the `_T0` total tie.** `retrieval_gate.py:26` fixes
`_T0 = datetime(2026, 1, 1, 12, 0, 0, tzinfo=timezone.utc)` and `:61` stamps it as `created_at` in
**every** commit's provenance; `relational.py:356` writes
`crystal.get("provenance", {}).get("created_at", now)` into the DB column. So all 31 rows share one
timestamp, and `relational.py:648-652`'s `ORDER BY created_at DESC LIMIT ?` is a **total tie** with
no `id ASC` tiebreak — contrast `relational.py:919` (`ORDER BY created_at DESC, id ASC`), which has
one — and no index on `created_at` (`relational.py:90-93` indexes layer/tier/status/importance
only). Which 5 crystals get linked is an implementation artefact of SQLite's scan+sort plan.

**N-5.** Under `CRYSTALIUM_SKIP_SLOW=1`, `vector.py:88-92` raises on every `_load_model`, so
`episodic.py:252`'s `embed` fails, `if vec:` at `:253` skips the upsert, and the corpus has **no
dense vectors in any arm**. The gate still emits F1/rank numbers that measure BM25+graph only, in a
gate whose axes are defined against hybrid recall. The gate already has one honesty fallback — the
null-graph-stub branch at `retrieval_gate.py:168-170` — and the embeddings-unavailable case has
none.

#### 2.5.2 Change contract

1. New `Config.link_cooccurrence: bool | None = None` — `None` means "follow `recall_completion`",
   i.e. today's wiring, so the default is behaviour-neutral. `server.py:533` and `server.py:546`
   resolve it. The field carries a `CRYSTALIUM_LINK_COOCCURRENCE` entry in `Config.from_env`
   (`config.py:318-…`) to match the file's own convention — every other field has one.
2. The fixture pins `link_cooccurrence=False` in **every** arm, so the only edges are the explicit
   `hub→spoke1→spoke2` chain (`retrieval_gate.py:107-110`) and the `:10-14` isolation claim becomes
   true.
3. Strictly-increasing `created_at` per commit (kills the `_T0` total tie at `:26`/`:61`).
4. **Isolation self-check:** post-commit edge count must equal **2** in all four arms, else the run
   emits verdict `"confounded"`. A gate must be able to fail.
5. **N-5 honesty path:** embeddings unavailable → verdict `"inconclusive"` with a reason, and
   **never numbers**.
6. The `:10-14` docstring is corrected to describe what the gate now actually does.

#### 2.5.3 Invariants W3 must not break

- **The one-decorator/two-transport invariant.** `server.py:713-717`:
  > "Transport-agnostic: shared verbatim by both run_stdio and run_http (D2, v0.2). … Components
  > (_build_components) and the @server.call_tool dispatch are reused as-is across transports."

  W3 edits `server.py` **only** at the two `link_cooccurrence=` wiring lines (`:533`, `:546`, both
  inside `_build_components`). It must not touch `_build_server` (`server.py:710-722`), the
  `@server.list_tools()`/`@server.call_tool()` decorators (`:744-749`), or the stdio/HTTP paths.
  Related and equally untouchable: `server.py:718-722`'s explicit `version=__version__` —
  *"Without it, mcp.server.lowlevel.Server.create_initialization_options() falls back to the
  installed `mcp` SDK package's own version for serverInfo."* This is #39's territory (REPORT).
- **The P1 guard on `fusion_weight_derived`.** `config.py:246-252`:
  > "Values BELOW 1.0 remain LEGAL config (AC-127 must stay trivially satisfiable, no
  > validator/clamp) but are OUTSIDE the documented/supported band … Values ABOVE 1.0 re-create P1
  > (a derived-only record at w/61 can then outrank a two-base-arm record at 2/61). No test, doc, or
  > CHANGELOG line may present a sub-1.0 value as a supported 'precision dial'."

  W3 owns `config.py` and therefore must preserve this block verbatim: no validator, no clamp, no
  default change, and no new prose presenting a sub-1.0 value as supported.
- **`recall_completion` stays `True` this campaign.** Both honesty branches (below) land W3; neither
  flips a shipped default inside a bugfix train.
- **The null-graph-stub fallback stays.** `retrieval_gate.py:157` (`graph_ok = flat["graph_ok"] and
  comp["graph_ok"]`) and the `:168-170` INCONCLUSIVE branch are preserved; N-5's verdict is a
  *second* honesty branch, not a replacement.
- **The gate's output keys stay a superset of today's.** `eval-before.json` records
  `axes.multihop_f1`, `axes.context_rank`, `graph_ok`, `completion_pass`, `context_pass`,
  `gate_pass`, `verdict` (`retrieval_gate.py:162-174`). Renaming or dropping any of them orphans the
  #36 precedent artefacts and this campaign's own baseline.

#### 2.5.4 Two consequences FORGE's plan implies but does not spell out

**(a) The shipped pytest guard may go red, and that is the point.** `test_retrieval_gate.py:19-25`
asserts `f1["completion"] > f1["flat"]` and `r["completion_pass"] is True`; both existing tests are
`@pytest.mark.slow` (`:18`, `:28`). Removing ~150 co-occurrence edges from the `comp`/`both` arms
may legitimately remove the lift. `test_retrieval_gate.py` is W3-owned, so W3 must **decide** that
assertion's new form on the record. FORGE's pre-ruled honesty branches apply to the test exactly as
they apply to the `config.py:199` comment:
- lift **survives** the deconfound → update `config.py:199` with the new figures; the test's
  assertion stands.
- lift does **not** survive → strip the earned-ON claim from `config.py:199`; the test is rewritten
  to assert the *measured* relationship (never a fabricated pass); the default stays `True` this
  campaign; a release-coupled default-flip issue is filed. **W3 lands either way.**

**(b) `make test-fast` cannot verify the N-5 path as FORGE words it.** `Makefile:31` runs
`env CRYSTALIUM_SKIP_SLOW=1 pytest … -m "not slow"`, and **both** existing tests in
`test_retrieval_gate.py` carry `@pytest.mark.slow`, so `make test-fast` currently collects **zero**
tests from that file. For the oracle to mean anything the new N-5 test must (i) be **unmarked**, so
`-m "not slow"` collects it, and (ii) set `CRYSTALIUM_SKIP_SLOW` **itself** (e.g.
`monkeypatch.setenv`) rather than inheriting it from the Makefile — otherwise it asserts
"inconclusive" under `make test-fast` and fails under `make test`, where the variable is absent.

#### 2.5.5 Non-goals for W3

W3 does not flip `recall_completion`, does not fix #42/#44/#45, does not build the cross-layer gate
(N-3, `#45`'s precondition), and does not touch `evals/fusion_gate.py` or `test_fusion_gate.py`.
Its final deliverable is `eval-baseline-deconfounded.json` in this change folder — the baseline the
**future** #42/#44/#45 campaigns diff against, and which is **not** comparable to
`eval-before.json`/`eval-after.json`.

### 2.6 W4 — relational recency determinism (N-2)

#### 2.6.1 Problem, anchored

`relational.py:640-656`, query at `:648-652`:

```
648                rows = conn.execute(
649                    "SELECT id FROM crystals "
650                    "WHERE json_extract(scope, '$.project') = ? AND status='active' AND id != ? "
651                    "ORDER BY created_at DESC LIMIT ?",
652                    (project, exclude_id, limit),
653                ).fetchall()
```

1. **No tiebreak.** The same file's other recency query orders `created_at DESC, id ASC`
   (`relational.py:919`). With tied timestamps — bulk imports, or a fixture that stamps one
   constant `created_at` (exactly what `retrieval_gate.py:26/61` does for all 31 rows) — *which*
   crystals receive co-occurrence `LINKS_TO` edges is an artefact of SQLite's scan order. Graph
   topology becomes nondeterministic in precisely the store the derived recall arms walk.
2. **No index.** `relational.py:90-93` indexes `layer`, `trust_tier`, `status`, `importance` —
   not `created_at`. This query runs on **every** episodic and semantic commit whenever
   `link_cooccurrence` is on, which is the production default via
   `link_cooccurrence=config.recall_completion` (`server.py:533`, `:546`) with
   `recall_completion: bool = True` (`config.py:199`). Call sites: `episodic.py:101-103` and
   `semantic.py` (`_link_cooccurrence` at `semantic.py:145`, invoked at `semantic.py:380`).

#### 2.6.2 Change contract

1. `ORDER BY created_at DESC, id ASC` in `recent_crystal_ids` (`relational.py:651`) — adopting the
   idiom already used at `relational.py:919`.
2. `CREATE INDEX IF NOT EXISTS idx_crystals_created_at ON crystals(created_at);` beside
   `relational.py:90-93`.

#### 2.6.3 Invariants W4 must not break

- **Behaviour is preserved for distinct timestamps.** The tiebreak only decides ties; a store with
  distinct `created_at` values returns exactly today's order.
- **The existing predicate set is untouched:** `json_extract(scope, '$.project') = ?`,
  `status='active'`, `id != ?`, `LIMIT ?` (`relational.py:650-651`). W4 adds an ORDER BY term and
  an index — nothing else. In particular W4 must not "improve" `status='active'` here; that
  predicate is correct and unrelated to #44.
- **The defensive contract stays.** `relational.py:646/655-656` — *"Returns [] on any error / no
  project."*
- **Schema idempotency.** The DDL block (`relational.py:50-93`) is executed on every store open;
  the new index must use `IF NOT EXISTS` so an existing database migrates in place with no
  migration script and no second execution path.
- **No change to `bm25_search`** (`relational.py:493-541`) — that is #44, REPORT.

#### 2.6.4 Non-goals for W4

#44. W4 must not add a status predicate to `bm25_search`, must not add a new public storage method,
and must not touch `relational.py:919`'s existing query.

### 2.7 W5 — release (strictly last)

**Change contract.** Version → **1.11.0** in exactly two places
(`mcp-server/pyproject.toml:8`, `mcp-server/src/crystalium/__init__.py:8`), plus a `CHANGELOG.md`
entry. W5 is the **sole** owner of `CHANGELOG.md`.

The CHANGELOG entry must discharge the mandate at `CHANGELOG.md:105-108` explicitly: name the
re-baseline, link `eval-before.json` and `eval-after.json`, and record the AC-124 / AC-125 / AC-133
outcomes plus the DP-2 re-check result. It must also **retire or amend** the three "Known
limitations" bullets that this change makes stale or partially stale
(`CHANGELOG.md:96-108` for #41, `:109-120` for the floor, `:121-125` for cross-layer — the last of
which stays open and must remain accurate).

**Sizing discipline for the entry.** #46 is described as what the scout measured it to be — a
cosmetic hoist absorbed by `vector.py:55/115-116`'s cache — not as a latency win. #47 is described
as closing a silent-invariant break, a no-op at the shipped default.

`requires_checker: true`. This ships a public release, so the ESL maker≠checker verify hop
(maker `vivi`, checker `kupo`) is mandatory **before** the tag. Follow-through outside crystalium:
the nexus roster bump is **dual-rostered** (`roster/mcps.yaml` + `roster/index.yaml`, skew-guarded)
and requires a ghcr digest probe before the pin lands.

**Non-goals for W5.** No code change of any kind. If a defect surfaces during release verification,
it goes back to its owning unit's branch — W5 never patches.

## 3. Cross-cutting invariants

### 3.1 Verification environment

Container-only. `mcp-server/pyproject.toml:2-4` forbids host `uv sync`; `kuzu` is not installed on
the host (scout-verified); `Makefile:1-3` — *"Host-visible commands only. All Python tooling runs
INSIDE Docker."* Every VERIFY line in `spec.criteria.md` is a container command.

### 3.2 The `bm25_search` fence (quoted, and unbroken by this change)

`retrieve.py:605-611` records the prior FORGE ruling verbatim:

> "C-8(ii)/(iii): the population is resolved ONCE here, as a PURE-PYTHON filter over the crystal
> dicts already in hand (`bm25_search` returns full rows) — **never a status predicate on the shared
> `bm25_search`**, and no extra I/O beyond the one bounded aggregate below (DP-3, 'the existing
> bounded aggregate', `count_for_export`; **no new public storage method, per FORGE's ruling**)."

echoed at `retrieve.py:241-243`: *"`bm25_search` applies no status predicate (shared method, never
filtered)."* FORGE's #44 ruling **AFFIRMS this as scoped** and pre-authorises a *parameterised*
future shape — which is a later campaign's work. **No unit in this change may add a status
predicate to `bm25_search` or add a public storage method.** The second production consumer,
`episodic.py:324` (`bm25_recall`), is likewise untouched.

### 3.3 Measurement protocol

- Seven runs per figure: `PYTHONHASHSEED` ∈ {0,1,2,3,4,5} plus unset (`test_fusion_gate.py:70-73`).
- Comparisons are **distribution-wise** — medians and unanimity. A single run is never evidence.
- `context_rank` is lower-is-better and a `None` baseline (crystal absent from the result) is
  treated as the **worst** value, per the frozen AC-133 text.
- Every captured record carries `{seed, git_sha, gate, cmd}`.

### 3.4 Baseline series (do not cross the streams)

| artefact | gate shape | produced by | comparable to |
|---|---|---|---|
| `eval-before.json` | fusion + retrieval, **confounded** retrieval fixture | W0/W0b @ `56c8510` | `eval-after.json` only |
| `eval-after.json` | same fixtures, post-W1 | W1b | `eval-before.json` only |
| `eval-baseline-deconfounded.json` | retrieval, **deconfounded** fixture | W3-measurement | future campaigns only |

Diffing across a fixture change is forbidden (STOP condition VP-S7).

## 4. Non-goals — the REPORT set

These are **out of scope for this change** and are already being posted as issue comments. No unit
may partially implement any of them; a diff that touches their surface is drift, not scope creep.

| item | why it is out | the fence it must not cross |
|---|---|---|
| **#35** tool rename (2.0.0) | MAJOR breaking rename; manifest (`server.py:172-416`, nine dotted names) and the flat exact-string dispatch chain (`server.py:748-871`, terminal `UNKNOWN_TOOL` at `:855-860`) are linked by nothing; every roster consumer hardcodes the double-prefixed host names | no rename of any manifest `"name"` or dispatch string |
| **#39** `mcp` SDK 2.x | pin is `mcp>=1.2.0,<2` (`mcp-server/pyproject.toml:19`); the 2.x API delta is not inspectable offline | pin unchanged; `server.py:710-722`, `:744-749`, `:906`, `:914-968` untouched |
| **#42** seed exclusion | FORGE RULED *relax*, but conditionally and **after** #41 and #43; it fires DP-1(b)'s recorded reversal condition and is unmeasurable while expansion is first-seed-only | `graph.py:251` and `graph.py:275` unchanged; no `exclude_seeds`/`include_seeds` parameter added |
| **#44** `bm25_search` status-blind | reverses a scoped FORGE ruling; needs an AC-142 amend via `ramza-freeze --amend --reason` | §3.2 |
| **#45** layer-major ordering | its named precondition (a genuine cross-layer gate, N-3) does not exist; the current `cross_layer` axis (`evals/fusion_gate.py:257-262`) bypasses `Aetheryte.recall` and is pinned at 0/0 by the fixture (`test_fusion_gate.py:38-39`). **The scout corrects #45's own filing here: #38 landed a label, not evidence** (`fusion_gate.py:104-106` says DP-5 deferred the fix) | `retrieve.py:510-544` append order unchanged |
| **#48** AC-138/139 unfalsifiable | RULED: **move** the ACs to a dedicated floor-sensitivity fixture post-#41; the AC-125 fixture is untouchable (measured 7/7 → ~2/7 regression, `test_fusion_gate.py:61-64`) | `evals/fusion_gate.py` untouched; `test_fusion_gate.py` touched **only** under the §2.2.6 XPASS contingency |
| **N-3** information-free `cross_layer` axis | filed as #45's precondition | `evals/fusion_gate.py:257-262` untouched |

## 5. Corrections this spec makes to its own frozen inputs

Recorded so a checker can see they were deliberate, not drift. Each is argued at the section cited.

| # | correction | §|
|---|---|---|
| S-1 | FORGE's W0 capture set omits the **weighted** floor probes AC-138's frozen VERIFY line requires → **W0b** added | 2.1 |
| S-2 | FORGE's DP-2 sweep `[ASSUMPTION]` resolved **and inverted**: the env var exists (`config.py:369`) but never reaches the gate (`fusion_gate.py:213` bypasses `from_env`), and `Config` is a plain `@dataclass` (`config.py:82`) so a post-hoc class-attribute patch silently no-ops → subclass mechanism + mandatory 0.90 positive control | 2.1 |
| S-3 | FORGE's "multi-seed expansion equals per-seed union" is false while `graph.py:251` stands → corrected identity | 2.2.5 |
| S-4 | FORGE's #47 neutrality argument is incomplete (`candidate_k` also drives the per-layer fetch at `retrieve.py:513/531`; `cap` at `:593` is unconditional) → neutrality rests on fixture size + the mocked dense arm, and is **measured** | 2.4.4 |
| S-5 | FORGE's W2 neutrality diff compares across two changes (W2's worktree is pre-W1) → rebase-then-diff rule | 2.4.4 |
| S-6 | FORGE's W3 `make test-fast` oracle is vacuous as worded (both existing tests are `@pytest.mark.slow`; `Makefile:31` filters them out) → the N-5 test must be unmarked and set the env var itself | 2.5.4(b) |
| S-7 | FORGE's W3 does not name the consequence for `test_retrieval_gate.py:19-25`, the pytest guard on the `recall_completion` default → the honesty branches bind the **test** as well as the comment | 2.5.4(a) |
| S-8 | FORGE `[ASSUMPTION] 1` (W4 test filename) resolved: `mcp-server/tests/test_storage_relational.py` (`Makefile:39-44`) | 1 |
| S-9 | FORGE `[ASSUMPTION] 3` (evals print JSON to stdout) confirmed: `evals/__main__.py:216` | 2.1 |

## 6. Risks — register (STOP conditions live in `verification-plan.md` §3)

| risk | anchor | mitigation |
|---|---|---|
| Retrieval-gate model unobtainable in-container | `retrieval_gate.py:84` → real `VectorStore`; `vector.py:88-96` downloads on first use | pre-ruled: W1 code may merge, **v1.11.0 does not ship**; campaign halts at W4 and reports the block on #41 |
| Shipped build red at baseline | `eval-before.json` fusion records | STOP; a red seed pre-fix is a shipped-build flake, back to FORGE |
| `fusion_weight_derived = 1.00` red post-fix | `config.py:243-245` (bitwise identity property) | STOP before any config edit; AC-136 contingency class |
| W1's new tests green on pre-fix code | §2.2.4 | STOP; the tests are not gates |
| W3's deconfound removes the completion lift | §2.5.4(a) | pre-ruled honesty branches; W3 lands either way; default stays `True` |
| Strict xfail XPASSes, `make test` red | `test_fusion_gate.py:85-113` | pre-ruled: measured AC-139 GREEN, W1 removes the marker |
| Two units touch one file | §1 | mechanical pairwise-intersection check (AC-270) |
| Concurrent implicit image build races on `crystalium:dev` | `docker-compose.yml:21` | build once before any parallel phase |

## 7. Acceptance Criteria

The 56 numbered criteria live in `spec.criteria.md` in this folder, in GIVEN/WHEN/THEN form with a
mechanical VERIFY line each. Index by unit:

| unit | criteria |
|---|---|
| W0 / W0b / W0c | AC-201 … AC-206 |
| W1 | AC-210 … AC-219 |
| W1b | AC-220 … AC-229 |
| W2 | AC-230 … AC-236 |
| W3 | AC-240 … AC-249 |
| W4 | AC-250 … AC-254 |
| W5 | AC-260 … AC-263 |
| campaign-wide | AC-270 … AC-273 |

The three **red-checked** criteria — a new test that must be shown failing on pre-fix code before it
is trusted — are **AC-210** (#41's ≥2-seed tests), **AC-233** (#47's floor link) and **AC-250**
(N-2's tiebreak). They are the campaign's answer to "nothing checks the checker".

## 8. Stories

| id | unit | owner | output contract | criteria | gate |
|---|---|---|---|---|---|
| S-0 | W0 + W0b + W0c | orchestrator | `eval-before.json`, `dp2-control-prefix.json`; target tree untouched | AC-201..206 | 7 fusion seeds green; 0.90 control red |
| S-1 | W1 | vivi | `graph.py` + `test_storage_graph.py` on `fix/graph-neighbor-expand-41`; `red-evidence.txt` | AC-210..219 | red-check first, then green suite |
| S-2 | W1b | orchestrator | `eval-after.json`, `dp2-sweep-postfix.json` | AC-220..229 | AC-124/125/133 differentials + DP-2 at 1.00 |
| S-3 | W2 | vivi | `retrieve.py` + `test_retrieve_hoist_floor.py` on `fix/retrieve-hoist-floor-46-47` | AC-230..236 | byte-identical fusion result after rebase |
| S-4 | W3-code | vivi | `retrieval_gate.py`, `config.py`, `server.py`, `test_retrieval_gate.py` on `fix/retrieval-gate-deconfound-43` | AC-240..246, AC-249 | self-check can emit `"confounded"`; SKIP_SLOW ⇒ `"inconclusive"` |
| S-5 | W3-measurement | orchestrator | `eval-baseline-deconfounded.json`; the honesty branch taken, recorded | AC-247, AC-248 | verdict ≠ `"confounded"` on 7 seeds |
| S-6 | W4 | vivi | `relational.py` + `test_storage_relational.py` on `fix/relational-recency-tiebreak` | AC-250..254 | tie determinism red-checked |
| S-7 | W5 | vivi (maker), kupo (checker) | `CHANGELOG.md`, two version strings, tag v1.11.0 | AC-260..263 | full `make test` green; maker≠checker hop |

S-3, S-4 and S-6 may be implemented concurrently (disjoint files); their *verification* obeys
`verification-plan.md` §2.

## 9. Rejected Alternatives

Campaign-shape alternatives (H1 maximal / H2 minimal) were explored and rejected by FORGE; they are
not re-litigated. These are the **spec-level** choices this document made, with what was rejected:

1. **Block the campaign on the missing AC-138 capture** — rejected in favour of **W0b**, a cheap
   model-free supplementary capture at the same pre-fix SHA. Blocking would have traded a five-minute
   run for a campaign halt.
2. **Drive the DP-2 sweep with `CRYSTALIUM_FUSION_WEIGHT_DERIVED`** — rejected: the variable exists
   (`config.py:369`) but only inside `Config.from_env`, and `evals/fusion_gate.py:213` constructs
   `Config(...)` directly, so it never reaches the gate. Also rejected: post-hoc class-attribute
   assignment, which silently no-ops on a `@dataclass` (`config.py:82`). Chosen: a subclass wrapper
   plus a **positive control** that must reproduce the recorded 0.90 cliff.
3. **Verify the N-5 honesty path through `make test-fast` alone, as FORGE worded it** — rejected:
   both existing tests in `test_retrieval_gate.py` are `@pytest.mark.slow` (`:18`, `:28`) and
   `Makefile:31` filters them out, so the oracle would be vacuous. Chosen: a pure
   `resolve_verdict(...)` seam whose tests are unmarked and set the env var themselves.
4. **Diff W2's neutrality run against `eval-before.json`** (i.e. leave W2 on `56c8510`) — rejected:
   it would prove neutrality against a tree W2 will never ship on. Chosen: rebase onto post-W1
   `main`, diff against `eval-after.json`, with the ancestry check as an explicit precondition.
5. **Fold #42's `exclude_seeds`/`include_seeds` parameters into W1 while the file is open** —
   rejected: FORGE's #42 ruling is conditional on #41 *and* #43 landing first and fires DP-1(b)'s
   recorded reversal condition. Adding the parameters here would ship half a REPORT item and
   contaminate the mandated differential with a second behaviour change.
6. **Let W1 also re-baseline** (fold W1b into W1) — rejected: the maker would then be measuring its
   own fix. W1b is orchestrator-owned measurement against frozen #38 VERIFY lines.

## 10. Confidence

**82/100.** The mechanical parts are strong: every anchor was re-derived at `56c8510`, all three of
FORGE's `[ASSUMPTION]`s are now resolved from the repo (two of them *against* the assumed answer),
and every criterion reduces to a command with an exit condition. Confidence is held below 90 by
three genuine unknowns, none of which a planner can close from a read-only seat:

- **W0's numbers do not exist.** Every baseline-dependent criterion is written as a differential;
  if the shipped build turns out to be flaky pre-fix (VP-S1), the campaign's evidentiary basis
  changes shape.
- **W3's outcome is genuinely open.** Removing ~150 co-occurrence edges may or may not preserve the
  completion lift. Both branches are pre-ruled, but the branch that strips the earned-ON claim
  ripples into a shipped default and a shipped test.
- **The retrieval-gate model dependency** is an environment fact outside the campaign's control
  (VP-S8), and it gates the release rather than the code.

## 11. Gate record

| gate | command | result |
|---|---|---|
| EARS lint | `./.eidolons/ramza/bin/ramza-ears-lint .spectra/changes/crystalium-open-issues-sweep-50/spec.criteria.md` | **PASS** — 56 criteria |
| structural lint | `./.eidolons/ramza/bin/ramza-lint --plan <this file> --tier full` | **PASS** (after §7–§10 were added; the first run DENYed on five missing sections and the sections were written, not the heading faked) |
| right-size | *not run* | The change was already opened at tier `full` (`change.json`); re-running the gate was explicitly out of scope for this hop. |
| criteria freeze | `./.eidolons/ramza/bin/ramza-freeze --state .spectra/plans/crystalium-open-issues-sweep-50.state.json --criteria .spectra/changes/crystalium-open-issues-sweep-50/spec.criteria.md` | **FROZEN** `28b0b50949e9ae3ac09f3cf884d9ac42c4ba942d51ab88c247c0125d76750048`; any later edit without `--amend --reason` is tamper evidence |
| critic gate | *not run in this hop* | maker≠checker for the **plan** is `ramza-gate critic`; the ESL change's maker/checker (`vivi`/`kupo`) govern the **code**. A planner critique hop is available if the campaign wants one before W1 starts. |
