---
eidolon: ramza
kind: spec-amendment
amendment_id: amend-01
version: 1.0.0
created_at: 2026-08-05
change_id: crystalium-residual-eight-plan
maker: ramza
checker: kupo
ruled_by: forge (D1..D9, forge-rulings.md, 2026-08-05)
supersedes: spec.md §0.3 (anchor only), §0.4 (NEW), §2 (deltas), §4 (#57 anchor, #52, #45, #44, #42, #55, #48), §6 (S-3, S-5, S-7, S-8, S-12, +S-13), §7, §8 (entry/exit deltas)
amends_criteria_sha256: eb0492ff1ac778499f89c8f4c70b1c919fbd9e3a83c83da630f022890da8908e
criteria_sha256_after_amend: 7e680dc63f87439dbfc2dec0220b8df51aa2b33fe776550a18b20f54cfeb05c9
target_repo: /home/rynaro/workspace/oss/agents/crystalium
target_head: b7f1a47
---

# spec.amend-01 — `crystalium-residual-eight-plan`

**This document supersedes named sections of `spec.md`. `spec.md` is FROZEN and is NOT
edited.** Where this amendment and `spec.md` disagree, this amendment governs. Where this
amendment is silent, `spec.md` stands unchanged.

Companion amendments: `spec.criteria.amend-01.md` (criteria), `verification-plan.amend-01.md`
(measurements, red-check protocol, checklists).

| field | value |
|---|---|
| amendment id | `amend-01` |
| supersedes | the sections listed in the front-matter `supersedes` key |
| frozen criteria hash amended | `eb0492ff1ac778499f89c8f4c70b1c919fbd9e3a83c83da630f022890da8908e` |
| maker | `ramza` |
| checker | `kupo` (verdict REJECT, 14 blocking + 21 non-blocking) |
| rulings | FORGE `D1`..`D9` — **binding, not relitigated** |
| target HEAD | `b7f1a47` (`b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc`, tree clean, re-verified) |
| criteria hash after amend | `7e680dc63f87439dbfc2dec0220b8df51aa2b33fe776550a18b20f54cfeb05c9` |

**Gates actually run for this amendment** (P0-2: gates are run, never role-played):

| gate | invocation | result |
|---|---|---|
| `ramza-freeze --amend` | `--state .spectra/plans/crystalium-residual-eight-plan.state.json --criteria .spectra/changes/crystalium-residual-eight-plan/spec.criteria.amend-01.md --amend --reason "amend-01: …"` | `eb0492ff… -> a40c0d42…`, then rev2 `a40c0d42… -> 7e680dc6…`; both hash-chained into `state.amendments[]` |
| `ramza-ears-lint` | `.spectra/changes/crystalium-residual-eight-plan/spec.criteria.amend-01.md` | **ok: 42 criteria pass EARS lint** (30 REPLACED + 7 RE-ANCHORED + 5 ADDED) |
| `ramza-lint --tier full` | `--plan .spectra/changes/crystalium-residual-eight-plan/spec.md --state …` | **ok: plan passes structural lint (tier: full)** |

Two amendment entries are recorded, not one, because the first pass failed `ramza-ears-lint`
and the fix was a block-shape conversion with **no semantic change to any criterion**. The
chain records what happened rather than a tidied version of it.

Anchor convention unchanged: `path:line` means **at `b7f1a47`**. **Every anchor in this
amendment was re-derived from the tree at `b7f1a47` during this revision pass**, not copied
from `spec.md`, from the critique, or from the rulings. Three anchor corrections are recorded
in §A below.

---

## 0. What changed, in one paragraph

Kupo's REJECT was correct on all 14 blocking findings; FORGE ruled on 9 of them and accepted
the remaining 5 as filed. Two further blocking defects were found **by execution, not review**
during this pass (K-B15 stdout contamination, K-B16 the `all_edges()` type error). The net
effect: the campaign's first gate is rebuilt on a measured BM25 separation instead of a false
term-presence premise; #45's Option A/B choice is decided (A) instead of deferred; #42's fix
surface triples from 2 sites to 5; #55 sheds an entire non-existent harness; the checker's own
gate stops being a boolean a replayer can write; and every `| jq` criterion in the plan is
re-plumbed through a durable artifact because the shipped gates write structlog to **stdout**.

---

## 1. FINDINGS LEDGER

Dispositions: **SUPERSEDED** (finding set aside without a ruling), **ACCEPTED-AS-FILED**
(Kupo's minimal fix adopted verbatim or refined), **RULED-BY-FORGE-Dn** (FORGE's ruling
governs; Kupo's finding upheld, Kupo's *prescription* may itself be superseded by FORGE's),
**REJECTED-WITH-REASON**.

**Counts: 39 rows covering 37 distinct findings** (16 blocking `K-B1..K-B16`, 21 non-blocking
`K-N1..K-N21`; `K-B13` is split into its three sub-findings (a)/(b)/(c)) —
**28 ACCEPTED-AS-FILED, 11 RULED-BY-FORGE-Dn, 0 SUPERSEDED, 0 REJECTED-WITH-REASON.**
`SUPERSEDED` and `REJECTED-WITH-REASON` are both zero, and that is the honest result rather
than a formality: **every finding was upheld.** Nine were ruled by FORGE (and in four of those
— K-B2, K-B5, K-B7, K-N9 — FORGE's remedy replaced Kupo's *prescription* while keeping the
*finding*); the rest were adopted as filed. See §1.3 for the rejection attempt and why it
failed.

### 1.1 Blocking

| id | disposition | where discharged |
|---|---|---|
| **K-B1** — G-XL fixture GREEN on `b7f1a47`; STOP S-3 fires at critical-path link 2 | **RULED-BY-FORGE-D1** (upheld; settled by execution in `kb1-fts5-measurement.txt`) | §B.2 (§4 #52 replacement): all-terms corpus + TF/doc-length separation; AC-310, AC-312, new C-XL-3; VP-M2 artifact gate |
| **K-B2** — #42 names 2 of 4 seed-exclusion sites; `exclude_seeds=False` is a no-op at depth 1 | **RULED-BY-FORGE-D2** (upheld; FORGE's 5-site threading supersedes Kupo's 4-site list, with `:266` deliberately unchanged under a proof obligation) | §B.5 (§4 #42 replacement): site/threading table + T1/T2/T3; AC-350, AC-351, new AC-354 |
| **K-B3** — `PYTHONHASHSEED` fixed at interpreter start; `--seeds 7` samples one seed; empty-array vacuous pass | **ACCEPTED-AS-FILED** (FORGE "Rulings that change the release plan" item 8) | Global rule **(d)** in `spec.criteria.amend-01.md`; AC-317, AC-322, AC-344; VP-M4/VP-M6 |
| **K-B4** — AC-310 passes on `null` and `-1`; AC-312 omits the one assertion that catches K-B1 | **RULED-BY-FORGE-D1** | §B.2; AC-310 (exact-rank + type guard), AC-312 (`sparse_arm_size`, `global_bm25_rank0`) |
| **K-B5** — AC-345 and AC-346 mutually exclusive on any single tree | **RULED-BY-FORGE-D7** (upheld; FORGE's two-commit + strict-xfail supersedes Kupo's either/or) | §B.4 (§4 #44 replacement); AC-345 |
| **K-B6** — the §D2 identity harness does not exist, has no subcommand, is owned by no unit | **RULED-BY-FORGE-D4** (upheld; harness DROPPED, not built) | §B.6 (§4 #55 replacement); AC-319 + AC-320 **STRUCK**; VP-M5 struck |
| **K-B7** — AC-321 demands fields VP-M1 cannot produce; `has()` is a shape check on a maker-written file | **RULED-BY-FORGE-D5** (upheld; FORGE chose *neither* of Kupo's two options) | §B.7 (§4 #48 replacement); VP-M1 rewrite; AC-321 (self-consistency predicate) |
| **K-B8** — AC-306/S-10 read `fence-amend.json`; §2/§8 produce `fence-amend.md` | **ACCEPTED-AS-FILED** (FORGE item 8) | §B.1 (§2 ownership delta): W-HOP emits **both**; AC-306 |
| **K-B9** — the checker perturbation table cannot discharge AC-332 for 5 of 7 rows; count is 4 not 5; AC-332 is a self-attestation | **RULED-BY-FORGE-D8** | `verification-plan.amend-01.md` §4 (two replacement tables + evidence schema + anti-replay); AC-332 (`length==5`, schema predicate), new **AC-365** |
| **K-B10** — AC-348 incompatible with #45 Option B, which §4 left undecided | **RULED-BY-FORGE-D3** (Option A **PINNED**, B deleted) | §B.3 (§4 #45 replacement); AC-348 (per-path call-count baseline) |
| **K-B11** — S-12 can never fire through `ramza-drift`; VP §5's invocation diffs the nexus, not crystalium | **ACCEPTED-AS-FILED** (FORGE item 8) | §C S-12 replacement (per-unit literal file-list check); `verification-plan.amend-01.md` §5 (`--repo` on every invocation) |
| **K-B12** — AC-333/AC-362 already satisfied, not observable from the named command, AC-362 unsatisfiable (single `.critic` object) | **ACCEPTED-AS-FILED** (FORGE item 8) | AC-333, AC-362 (state-file jq + timestamp binding + per-batch critic records in CHANGE) |
| **K-B13(a)** — `config.py` required by AC-370 but owned by no unit | **ACCEPTED-AS-FILED** (ownership hole FORGE did not separately close; Kupo's "new W-DOC" option adopted) | §B.1: new unit **W-DOC** owns `config.py` (comment block) in v2.0.2; W-42 owns it (flag) in v2.1.0 |
| **K-B13(b)** — #44's top-up is dead code unless `recall_active_only=True` | **RULED-BY-FORGE-D6** (upheld as a risk; **classification reversed** — it is a live production defect) | §B.4; AC-345/346/347/348 GIVEN clauses; new **AC-356** negative control |
| **K-B13(c)** — the censoring claim is verbatim correct and load-bearing | **ACCEPTED-AS-FILED** (confirmatory; no plan change, carried forward explicitly) | §B.3 (censoring semantics under Option A), §B.4 |
| **K-B14** — every gate criterion uses `python -m evals <gate>` but W-CLI is a trailing unit | **ACCEPTED-AS-FILED** (FORGE item 8) | Global rule **(b)**; every Wave-1 AC |
| **K-B15** — structlog writes to **stdout**, so every `\| jq` criterion fails with a parse error regardless of what the gate measured *(maker-found by execution; `kb15-stdout-contamination.md`)* | **ACCEPTED-AS-FILED** (self-filed) | §A.4 (artifact convention); global rule **(a)**; every jq criterion |
| **K-B16** — `GraphStore.all_edges()` returns a `list`, so the plan's `all_edges() == 0` assertion is `[] == 0` → **always False**; and it "Returns [] on error" (`graph.py:332`), so a zero is indistinguishable from a kuzu failure *(maker-found by derivation this pass; NOT in Kupo's critique)* | **ACCEPTED-AS-FILED** (self-filed) | §B.2 (liveness definition: `len(all_edges()) == 0` **and** `node_count() > 0`); AC-312 |

### 1.2 Non-blocking

| id | disposition | where discharged |
|---|---|---|
| **K-N1** — AC-318's `'not' in d.lower()` matches "notes"/"cannot"/"note" | **ACCEPTED-AS-FILED** (also mandated by FORGE D4's plan consequence) | AC-318: literal sentinel `NOT band characterisation` |
| **K-N2** — AC-373 asserts zero open issues repo-wide; the campaign *expects* new filings | **ACCEPTED-AS-FILED** | AC-373: per-issue `gh issue view`, plus the D9 class vocabulary |
| **K-N3** — AC-371 greps the wrong directories and the wrong string; the required note already exists at `config.py:311-312`; nobody owns `docs/` or a generic evals note | **ACCEPTED-AS-FILED** | AC-371 re-anchored + re-scoped to a *reachability* deliverable; §B.1 gives `evals/BENCH-NOTES.md` to **W-DOC** |
| **K-N4** — AC-370's grep is case-sensitive against `UNSUPPORTED` (`config.py:299`) | **ACCEPTED-AS-FILED** | AC-370: `grep -in` + positive content assertions |
| **K-N5** — AC-331's comment-only escape hatch is not mechanical, and *must* be used | **ACCEPTED-AS-FILED** | AC-331: `git diff -U0` piped through a mechanical comment/blank filter |
| **K-N6** — AC-313 passes vacuously if `fusion_gate.py` is deleted, and forbids the very docstring correction #52 item 2 is about (`cross-layer`, hyphen, `fusion_gate.py:104-106`) | **ACCEPTED-AS-FILED** | AC-313: existence guard + filter widened to the hyphen form + `_build_fixture` byte-hash assertion |
| **K-N7** — AC-324 (2nd half) and AC-341 are unverifiable at the plan's own hop placement; squash-merge makes AC-341 vacuous | **ACCEPTED-AS-FILED** (FORGE D7 folds the AC-341 half in explicitly) | AC-324 (pre-merge branch tip), AC-341 (pre-merge branch tip, named ref) |
| **K-N8** — W-G-XL's granted edit range is short by `fusion_gate.py:281` | **ACCEPTED-AS-FILED** | §B.1 ownership delta (`:257-266` **and** `:281`) |
| **K-N9** — AC-312 contradicts §4 #52's permitted "neutral fixed list" dense variant | **RULED-BY-FORGE-D1** — resolved **in AC-312's favour**; the neutral-list variant is **REVOKED** | §B.2 (dense stub returns `[]`, normative) |
| **K-N10** — AC-316 runs in a fresh process and cannot detect an unrestored monkeypatch | **ACCEPTED-AS-FILED** | AC-316: same-process post-run read of `retrieve_mod.FETCH_WIDTH_FLOOR` |
| **K-N11** — `Makefile:34` is the target label (recipe is `:35`); `make test-ci` is a *bind-mount* proxy for CI's *baked-image* invocation | **ACCEPTED-AS-FILED** | §A.1 anchor correction; §A.2 CI-parity note; AC-330/AC-360 gain the baked-image invocation |
| **K-N12** — no gate in the plan can detect Option A's strict-subset recall loss | **RULED-BY-FORGE-D3** (gate is **mandatory**) | §B.3; new **AC-355** (`test_subset_layer_recall_no_regression`) |
| **K-N13** — the Wave-0 entry baseline was never captured | **ACCEPTED-AS-FILED — DISCHARGED BY EXECUTION** | `baseline-verdict.md` (VP-B1..VP-B5 all green; S-6 does not fire) |
| **K-N14** — the ESL record is non-conformant (`acceptance_checks: []`, `has_code: false`, `status: proposed`, C3 missing `spec.yaml`) | **ACCEPTED-AS-FILED** | §D item 9 (ESL record obligations, incl. the honest cross-repo `has_code` note) |
| **K-N15** — AC-352 has no mechanical positive control | **ACCEPTED-AS-FILED** | AC-352 rewritten as a two-part VERIFY (base + `w_derived=100.0` positive control) |
| **K-N16** — AC-361/VP-M8 ignore the existing mechanical `compare_wire.py` | **ACCEPTED-AS-FILED** | AC-361 + `verification-plan.amend-01.md` VP-M8 |
| **K-N17** — no `$s` value means "unset"; `-e PYTHONHASHSEED=` sets it empty | **ACCEPTED-AS-FILED** (also mandated by FORGE D5's protocol clause) | Global rule **(d)**: the 7th run **omits `-e` entirely** |
| **K-N18** — AC-363 has no `cd`; the roster files live in the nexus | **ACCEPTED-AS-FILED** | AC-363: explicit nexus path |
| **K-N19** — AC-304/AC-324 use `grep -c` whose PASS is exit 1 | **ACCEPTED-AS-FILED** | Global rule **(e)**: absence checks become in-process positive assertions |
| **K-N20** — S-8 fires on the plan's own mandated GREEN controls (G-CORPUS's small-corpus check; G-WD/G-FLOOR precede no fix) | **ACCEPTED-AS-FILED** | §C S-8 replacement (scoped to a gate's *defect-asserting* node only) |
| **K-N21** — `test_server.py:159-178` straddles two tests | **ACCEPTED-AS-FILED** | §A.1 anchor correction (`:158-167` and `:170-…`) |

### 1.3 Rejections

**None. Zero of the 37 findings are rejected.** I attempted to break three of them against
source before accepting (K-N6's hyphen claim at `fusion_gate.py:104-106`, K-N9's dense-variant
contradiction, K-N19's `grep -c` exit semantics); each held. Kupo verified its anchors against
the tree and every one I re-derived matched. Where a Kupo *prescription* is not adopted, the
finding is still upheld and FORGE's remedy is recorded instead (K-B2, K-B5, K-B7, K-N9).

---

## A. Corrections and conventions that apply everywhere

### A.1 Anchor corrections (three; re-derived at `b7f1a47`)

| where | `spec.md` said | correct at `b7f1a47` |
|---|---|---|
| §0.3 (spec.md:88) | `Makefile:34` | `Makefile:35` is the recipe (`$(RUN) env CRYSTALIUM_SKIP_SLOW=1 pytest mcp-server/tests/ -v`); `:33` is the `## test-ci:` doc comment, `:34` the bare target label. **Substance unchanged.** |
| §4 #57 (spec.md:236) | `test_server.py:159-178` | `test_server.py:158-167` = `test_http_transport_builds_app`; `:170-…` = `test_http_smoke_initialize` (which additionally drives the real Streamable-HTTP request path via `TestClient`). **Substance unchanged and strengthened** — the recommended "what this does not cover" disposition is better supported than the plan claimed. |
| §2 (spec.md:159) | W-G-XL owns `fusion_gate.py:257-266` | the `cross_layer` key's consumers are `:257, :262, :266` **and `:281`** (`"cross_layer": weighted["cross_layer"],` inside `run()`). See §B.1. |

### A.2 `make test-ci` is a proxy for CI, not CI (K-N11)

`make test-ci` runs `docker compose run` against the **bind-mounted** tree
(`PYTHONPATH=/app/mcp-server/src:/app`, source = host checkout). `.github/workflows/ci.yml:39-44`
runs `docker run --rm -e CRYSTALIUM_SKIP_SLOW=1 crystalium:dev pytest tests/ -v` against the
**baked** image (`COPY mcp-server/tests ./tests`, `PYTHONPATH=/app/src:/app`). Same test set,
different source of truth — and this repo has two standing scars in exactly that gap
(`__version__`-from-METADATA, NC-6; "cached images hide dependency breaks").

**NC-3 is amended:** the release gates (AC-330, AC-360) now name **three** invocations —
`make test`, `make test-ci`, and the baked-image CI form after a fresh `docker compose build`.
This is a strengthening; nothing is removed.

### A.3 Liveness zeros must be distinguishable from errors (K-B16)

`GraphStore.all_edges()` (`graph.py:320-326`) returns `list[tuple[str,str,str]]` and its
docstring (`graph.py:332`) states *"Returns [] on any kuzu error."* Therefore:

- `all_edges() == 0` — the form written at `spec.md:75, :259, :283` — is `[] == 0` in Python,
  which is **always `False`**. Every gate written to that prose would fail its own liveness
  check on a correctly-edgeless graph.
- Even corrected to `len(all_edges()) == 0`, a zero is ambiguous between "edgeless" and "kuzu
  raised". **Normative form, everywhere in this campaign:**

  ```
  edge_count = len(graph.all_edges())        # 0 == edgeless OR error
  node_count = graph.node_count()            # graph.py:316-318, a real COUNT query
  assert node_count == <expected corpus size>   # proves the store is live and populated
  assert edge_count == 0                        # therefore genuinely edgeless
  ```
  Both values go into the result object's `liveness`. A gate that reports `edge_count == 0`
  with `node_count == 0` is `"confounded"`, not edgeless (R-CONF).

### A.4 Gate artifact convention — NEW §0.4 (K-B15)

**The shipped evals write structlog lines to `stdout`, ahead of their JSON.** Measured
2026-08-05 (`kb15-stdout-contamination.md`); only docker's own container chatter goes to
stderr. Consequence: `… python -m evals <gate> | jq -e '<pred>'` exits non-zero with
`jq: parse error` **regardless of what the gate measured**. For G-XL — a gate that is
*supposed* to be red — that is indistinguishable from success.

Normative convention, binding on every gate this campaign ships:

1. **Every new gate module exposes `run(...) -> dict` and `emit(result: dict, out: str) -> None`.**
   `emit` writes `json.dumps(result, indent=1, sort_keys=True)` to `out`, creating parent
   directories, **overwriting** (never appending). `emit` writes the file and nothing else —
   it does not print.
2. **The canonical artifact directory is `evals/results/`.** It already exists at `b7f1a47`
   (`evals/results/.gitkeep`) and `.gitignore` already carries `evals/results/*.json`.
   **No `.gitignore` edit is required and no ownership hole is created** — both verified at
   `b7f1a47`.
3. **Paths.** In-container `/app/evals/results/<name>.json` ⇔ host
   `MAIN/evals/results/<name>.json`, via docker-compose's `- .:/app` bind mount. Verified by
   execution during this pass: the container writes as uid 0, the host reads it, `jq -e`
   parses it, `git status` stays clean. Files are root-owned on the host; the container
   overwrites them freely, so no host-side `rm` is ever needed.
4. **Criteria read the file, never a pipe.** Where a pipe is unavoidable (a checker
   reproducing a run ad hoc), pipe through `awk '/^{/{f=1} f'` **first**, then `jq`.
5. **Every jq predicate opens with a parse/type guard** (`(type == "object") and …`), and
   the pass condition distinguishes three exits:
   - **exit 0** = PASS.
   - **exit 1** = the predicate is false → **this is a real red**.
   - **exit 2 or 5** = jq could not parse the artifact → **capture failure, NOT a gate
     result.** Re-run the emit step. Recording a 2/5 as a red is itself a finding.

---

## B. Replacement text for superseded `spec.md` sections

### B.1 §2 — work-unit ownership, DELTAS ONLY

`spec.md` §2's table stands except for the rows and additions below.

| unit | delta | why |
|---|---|---|
| **W-HOP** | owns `CHANGE/fence-amend.json` (machine-readable: `{verdict: "ALLOW"\|"DENY", ruling_quote, rationale, decided_at, decided_by}`) **and** `CHANGE/fence-amend.md` (narrative sibling). The `.json` is normative; the `.md` is the record. | K-B8 — AC-306 and S-10 both `jq` this file; a markdown file makes them unsatisfiable, so W-44's entry precondition was never mechanically establishable |
| **W-G-XL** | granted range corrected to `evals/fusion_gate.py` **`:257, :262, :266, :281`** (all four `cross_layer` key consumers) + the module-docstring sentence at `:104-106` + `mcp-server/tests/test_fusion_gate.py:31-39`. Nothing else in `fusion_gate.py` may change. | K-N8 (`:281` is inside `run()`; renaming without it breaks `run()`), K-N6 (the `:104-106` docstring says "cross-layer" with a hyphen — correcting it is the *point* of #52 item 2 and must be inside the grant, not drift) |
| **W-DOC** *(NEW unit, Wave 1, branch `docs/band-disposition-55`)* | EXCLUSIVELY owns `mcp-server/src/crystalium/config.py` **comment block `:289-312` only** (no field value, no new field) and `evals/BENCH-NOTES.md`. | K-B13(a) — `config.py` was required by AC-370 and §7 but owned by nobody; K-N3 — the eval-note deliverable (#55 item 3) was likewise unowned. One trivially-parallel unit closes both. |
| **W-G-WD** | scope **shrinks** to `evals/weight_discrimination.py` + `mcp-server/tests/test_weight_discrimination.py`. It does **not** own `evals/d2_identity.py` (which is not built — D4) and does **not** own `config.py` (W-DOC's). | FORGE D4 |
| **W-G-FLOOR** | additionally owns the VP-M1 probe **inside its own file** `evals/floor_sensitivity_gate.py` (function `vp_m1_probe`). `evals/fusion_gate.py` remains **UNTOUCHABLE** for this unit — the probe *imports* from it and never edits it. | FORGE D5 — importing is a read; §3.1 freezes the file's bytes, not its importability. No fence exception exists or is needed. |
| **W-42** | additionally owns `mcp-server/src/crystalium/config.py` for the **single new field** `recall_seed_derived_credit` — in **v2.1.0 only**. W-DOC's v2.0.2 comment edit and W-42's v2.1.0 field addition are wave-disjoint, so the file is never contended. | K-B13(a) second half (`Config.recall_seed_derived_credit` was also unowned) |
| **all gate units** | additionally own their gate's artifact **path** `evals/results/<gate>.json` (gitignored; not a tracked file, so it is not a diff surface) | §A.4 |

**Unchanged and carried forward intact:** the §2 principle that no unit but a release unit
touches `CHANGELOG.md` or a version string, and NC-6.

---

### B.2 §4 #52 — REPLACEMENT  ·  unit W-G-XL  ·  needs W-RIG  ·  v2.0.2

*(Supersedes `spec.md:249-284` in full. FORGE D1. Discharges K-B1, K-B4, K-N9, K-B16.)*

**Why the original is void.** `spec.md`'s fixture used "N weakly-matching crystals (one query
term each)". `relational.py:190-202`'s `_fts5_query` quotes every token and joins with a
space; FTS5 space-separated phrases are **implicit AND**. Measured in the pinned build
(sqlite 3.46.1, `kb1-fts5-measurement.txt`): a row carrying a strict subset of the query terms
**matches nothing at all**. The episodic arm would have been empty, `sparse_ranking ==
["sem-target"]`, `target_rank == 0` — the gate GREEN, STOP S-3 fired, critical path dead at
link 2. "RED by construction" was a false adjective.

#### B.2.1 Corpus (normative)

FTS5 indexes **`summary` only** (`relational.py:75`:
`CREATE VIRTUAL TABLE … crystals_fts USING fts5(summary, content='crystals', …)`). All
padding therefore lives in `summary`.

- **Query — four fresh nonce terms, zero lexical overlap with `fusion_gate.py`'s corpus:**
  `_XL_QUERY = "quorvex blenthar mizzletine korvath"`. (Overlap with `fusion_gate.py`'s
  `_QUERY = "plarnix threxil vandomere signature"` is nil by construction; separate data root,
  separate project scope.)
- **`episodic`: N = 3 fillers `ep1, ep2, ep3`.** **Each filler contains all four query terms
  exactly once**, padded with per-filler unique non-query nonce tokens to strictly distinct
  document lengths **24 / 32 / 40 tokens**.
- **`semantic`: one `sem-target`** whose summary is each query term repeated **3 times and
  nothing else** (12 tokens).
- Separation is **term frequency + document-length normalisation**, never term presence — the
  only two channels that exist under implicit-AND, both pure deterministic functions of the
  corpus, invariant to `PYTHONHASHSEED`.
- `procedural` and `execution` are empty (they contribute nothing to `sparse_ranking`).

**This separation is MEASURED, not derived.** Executed in the pinned build during this
amendment pass:

```
sem-target  -7.1351351351351354e-06     <- rank 0
ep1         -4.1904761904761911e-06
ep2         -3.7183098591549303e-06
ep3         -3.3417721518987344e-06
strict_total_order: True   sem_target_is_rank0: True   sqlite 3.46.1
```

`ORDER BY bm25(crystals_fts)` is ascending and FTS5's `bm25()` is negative, so best-first.
The order is a **strict total order** — no ties among fillers. This discharges D1's REVERSAL
CONDITION at the corpus level. It does **not** discharge VP-M2, which measures the *fused*
rank through `Aetheryte.recall`.

#### B.2.2 Widths and their assertions

| quantity | value | assertion the gate makes, in-gate |
|---|---|---|
| `k` (caller) | **5** | `k > corpus_per_layer` (5 > 3) — the blocked target must still be inside the `[:k]` response window. Kupo's trace shows `filtered_ids[:k]` (`retrieve.py:854`) would otherwise **evict** it and the gate would be measuring eviction, not append order. |
| `candidate_k` | **15** = `max(k*3, FETCH_WIDTH_FLOOR)` = `max(15, 10)` (`retrieve.py:503`, `:52`) | `corpus_per_layer < candidate_k` (3 < 15) and `N + 1 < candidate_k` (4 < 15) — truncation is **non-binding**, so `candidate_k` cannot be the cause (§0.2's deconfound rule) |
| `N` (`corpus_per_layer`) | **3** | `expected_blocked_rank == N == corpus_per_layer` |

#### B.2.3 Arms (normative; the "neutral fixed list" variant is REVOKED)

- **Dense stub returns `[]`.** `vector_store = MagicMock()`;
  `vector_store.embed.return_value = [0.1, 0.2, 0.3]` (mirrors `fusion_gate.py:224`, keeps the
  embed path exercised so `query_vec` is truthy at `retrieve.py:518`);
  `vector_store.dense_search.return_value = []` ⇒ `dense_ranking == []`.
  **`spec.md:258-259`'s permitted "or a neutral fixed list containing neither target nor a
  competitor" is REVOKED** — it contradicts AC-312's `dense_arm_size == 0` (K-N9, resolved by
  FORGE in AC-312's favour).
- **Graph: real `GraphStore`, edgeless.** Liveness per §A.3: `node_count() == 4` **and**
  `len(all_edges()) == 0`. Not `all_edges() == 0` (K-B16).
- **Completion off** (`completion=False`).
- **`recall_active_only=False`** — the corpus is single-status; the status axis belongs to
  W-44's fixture (§0.2 discipline). The value is read back **off the `Aetheryte` instance**,
  not off the kwargs dict.
- ⇒ the **sparse arm is the only voter**, by construction *and* by assertion.

#### B.2.4 The pre-fix expected state and the gate assertion

With one live arm, `weighted_rrf_merge_scored` (`retrieve.py:741-748`) produces the sparse
order verbatim (score `w_sparse/(60+rank)`, strictly monotone, no ties) — independently traced
by the checker. Per-layer append (`retrieve.py:521-530`, `_ALL_LAYERS` order
`["episodic","semantic","procedural","execution"]`, `retrieve.py:44`) therefore gives, at
`b7f1a47`:

```
sparse_ranking == ["ep1", "ep2", "ep3", "sem-target"]      target_rank == 3
```

The result object carries `expected_blocked_rank = N` (= `liveness.corpus_per_layer`) and the
gate asserts **`target_rank == expected_blocked_rank`**, not `!= 0`. This cannot pass on
`null`, cannot pass on the repo's absent-sentinel `-1` (`fusion_gate.py:255`), and cannot pass
on a partially-built fixture (K-B4 cured).

#### B.2.5 Controls — C-XL-1, C-XL-2, C-XL-3 (all three permanent test nodes)

- **C-XL-1 (single-layer control)** — `test_single_layer_control_is_rank_zero`. The same
  fixture with `layers=["semantic"]` puts `sem-target` at rank 0 **today**. Retained from
  `spec.md` **unchanged and no longer vacuous**: under the old fixture an empty episodic arm
  passed it for the wrong reason (K-B1); with all-terms fillers the episodic arm is provably
  non-empty, so C-XL-1 now discriminates. Red ⇒ STOP S-4.
- **C-XL-2 (arm liveness)** — promoted from prose into AC-312. The gate asserts, before
  emitting any numeric axis:
  `sparse_arm_size == corpus_per_layer + 1` (**the single assertion that catches K-B1's
  failure mode**: a filler silently not matching), `dense_arm_size == 0`, `edge_count == 0`,
  `node_count == 4`, `corpus_per_layer < candidate_k`, `k > corpus_per_layer`. Any deviation
  ⇒ verdict `"confounded"`, **never numbers** (R-CONF, `retrieval_gate.py:301-310` precedent).
- **C-XL-3 (global-premise probe) — NEW.** The gate calls
  `relational.bm25_search(_XL_QUERY, layer_filter=None, k=60)` directly and asserts
  `ids[0] == "sem-target"`, recording it as `liveness.global_bm25_rank0`. This is a *read-only*
  use of the shared method — `run_arm`'s cross-layer probe at `fusion_gate.py:257-262` is the
  exact in-repo precedent, and it makes **no fence contact** (no new parameter, no status
  predicate, no new public method). It converts the fixture's BM25 assumption from prose into
  an in-gate assertion, and it is what makes the RED **attributable**: global rank 0 + fused
  rank N can only be layer-append order.

#### B.2.6 "RED by construction" is STRUCK

The phrase is struck from the plan. It is replaced by:

> **RED expected by derivation, established by VP-M2 before W-45 may start.**

VP-M2 runs on `b7f1a47` and writes `CHANGE/vp-m2-gxl-red.json` =
`{tree_sha, target_rank, expected_blocked_rank, liveness{…}, sparse_ranking, verdict}`.
**W-45's entry precondition is the existence and content of that artifact**, not a claim in a
spec (FORGE "release plan" item 4). This is forced by the campaign's own epistemics: the
original claim was falsified by execution; a claim of that class must be an artifact, not an
adjective.

#### B.2.7 If VP-M2 shows GREEN anyway (S-3 ladder, per D1 → S-13)

1. **Any liveness assertion red ⇒ fixture bug, not an S-3 event.** Fix the fixture, re-measure.
   (This is precisely the state K-B1 predicted for the old fixture: C-XL-2 red.)
2. **Liveness fully green AND `target_rank == 0` ⇒** the append-order premise is false at the
   fused surface. **One** redesign cycle is authorised: instrument `sparse_ranking` directly,
   find where the order diverges from the premise, rebuild.
3. **Redesigned gate also green with green liveness ⇒ S-13 class (a): premise-refuted.**
   #45 closes *"not reproducible at `b7f1a47`, measurement attached"*. **W-45 is cancelled.**
   W-44 rebases onto the existing per-layer fetch with AC-348 restated per-layer (≤ 1 widened
   call per censored-and-dirty layer, ≤ `len(target_layers)` total; per-layer censoring
   recompute is well-defined as `raw_n_sparse_layer >= candidate_k`). W-42 is unaffected.
   v2.1.0 re-scopes to W-44 + W-42 — smaller, still shippable.

**Item 2 of #52 (the axis relabel) is unchanged from `spec.md`** except that the grant now
covers `fusion_gate.py:281` and the `:104-106` docstring sentence (§B.1).

---

### B.3 §4 #45 — REPLACEMENT  ·  unit W-45  ·  needs `vp-m2-gxl-red.json`  ·  v2.1.0

*(Supersedes `spec.md:287-320` in full. FORGE D3. Discharges K-B10, K-N12.)*

**Option A is PINNED. Option B is DELETED — not kept as a fallback.** `spec.md`'s "the plan
does not pre-decide" is superseded. Three independent grounds, any one sufficient:

1. AC-348 and #44's censoring recompute are only coherent against a **single identifiable
   fetch**. `cap = candidate_k * len(target_layers)` (`retrieve.py:597`) is an aggregate over
   layers, so "recompute against the widened fetch" is undefined for a per-layer loop (K-B10).
2. `bm25_search` returns `SELECT c.*` with **no score column** (`relational.py:520, 533`), and
   AC-349 freezes its signature and SQL. Option B's per-layer results therefore can **never**
   be merged in score space caller-side. B is not a weaker fix — it is **structurally
   incapable** of fixing the issue as filed ("a semantic hit with a far better BM25 score").
3. With the corrected G-XL fixture (§B.2), round-robin interleave puts `sem-target` at fused
   rank 1 (`[ep1, sem-target, ep2, ep3]`), so G-XL's post-fix assertion `target_rank == 0`
   stays **red** under B. `spec.md:308-309`'s sentence *"G-XL as specified goes green under B"*
   is **wrong for the corrected fixture and is struck**. Under B the campaign cannot close.

#### B.3.1 The normative three-case fetch shape

Sparse is shown; **dense mirrors it** via `dense_search(layer_filter=…)` (`vector.py:174-199`
supports `layer_filter=None`).

| case | shape |
|---|---|
| `target_layers == _ALL_LAYERS` (the default, `layers=None`) | **One** global call: `bm25_search(query, layer_filter=None, k=candidate_k * len(_ALL_LAYERS))`. Score-space by construction — `relational.py:531-541` orders globally by `bm25(crystals_fts)`. **No post-filter needed.** |
| `len(target_layers) == 1` | **One** filtered call: `bm25_search(query, layer_filter=layer, k=candidate_k)` — today's per-layer call, already score-space within the layer. **Byte-preserving** for the single-layer case. |
| strict subset, `len(target_layers) >= 2` | Global call (`k = candidate_k * len(_ALL_LAYERS)`) + post-filter to `target_layers`; **starvation backstop:** if the post-filtered count `< candidate_k * len(target_layers)` **AND** the global fetch was censored (raw row count `==` requested `k`), issue one `layer_filter=layer` call per target layer (`k=candidate_k`) and append rows not already present, **layer-major, AFTER the globally-ordered head**. |

**Why the backstop's ordering is score-correct.** Every tail row is BM25-worse than every head
row (it fell outside the global top-`4·candidate_k`), so the head/tail boundary is score-correct.
Only the tail's *internal* cross-layer order is rank-space, at RRF ranks where the contribution
difference is negligible. Bounded and deterministic: `<= 1 + len(target_layers)` calls.

**Why the backstop exists at all.** With `layer_filter=None` + post-filter, a **strict layer
subset** can recover *fewer* rows than today, because the global top-`N` may be dominated by
non-target layers (K-N12). That starvation is a real defect for explicit subsets — the user
*excluded* those layers, so global dominance by them is noise. For `layers=None` it is
*intended semantics*: nothing is excluded, score decides, which is exactly the issue's ask.

#### B.3.2 Censoring semantics under Option A (normative)

`resolve_sparse_weight` (`retrieve.py:229-262`) reads `cap` and `raw_n_sparse` as **properties
of the fetch actually performed** — the docstring says so verbatim at `retrieve.py:230-233`
(*"the CENSORING test … is a property of the FETCH"*), and `retrieve.py:256` is
`if raw_n_sparse == 0 or raw_n_sparse >= cap:`. Under Option A:

- **global paths** (`_ALL_LAYERS`, strict subset): `cap` = the global requested `k`
  (`candidate_k * len(_ALL_LAYERS)`); `raw_n_sparse` = the global raw row count.
- **single-layer path**: `cap = candidate_k`; `raw_n_sparse` = that call's row count.

VP-M7 records the pre/post `explain.fusion.{n_sparse_cap, selectivity, w_sparse}` delta **per
path**. #38's D3 selectivity boost is downstream of both, so the delta is *recorded*, never
discovered later.

**Reversal (FORGE D3):** if VP-M7 shows the D3 boost behaving pathologically under the global
cap (e.g. `selectivity` pinned to 0.0 because the global fetch is always censored), the **cap
semantics** reopen — and the remedy space is bounded to censoring-signal definitions, **never**
to reverting the score-space merge.

#### B.3.3 The K-N12 subset-starvation node — MANDATORY

Location: **W-45's own** `mcp-server/tests/test_retrieve_layer_merge.py` (no new unit, no
ownership change). **Node name is normative:**

```
test_subset_layer_recall_no_regression
```

Fixture:
- `E = 4 * candidate_k` episodic rows, all matching **all** query terms, all strictly better
  BM25 than the semantic rows (TF/document-length separation, §B.2.1's measured mechanism);
- `S = candidate_k` semantic rows including one planted target;
- query issued with **`layers=["semantic", "procedural"]`** — a **2-layer strict subset**. A
  1-layer subset never reaches the global path under §B.3.1 and therefore **cannot see the
  defect**;
- **dense arm pinned empty** (`dense_search.return_value = []`). *This pin is mine, not
  FORGE's: a `MagicMock` dense stub ignores `layer_filter`, so under a global+post-filter
  shape its returned ids would be post-filtered by layer and the node would confound the
  sparse backstop with dense-stub semantics. Pinning the dense arm empty keeps this node on
  one axis (§0.2 discipline).*

Assertions: the planted semantic target is recalled, **and** the sparse candidate set contains
`>= min(S, candidate_k)` semantic rows.

**It can fail on the defect it names:** RED on a naive global+post-filter implementation,
GREEN only when the backstop exists.

#### B.3.4 AC-348 retained at "<= 1", with a per-path baseline

The call-count spy asserts the **exact** fetch-shape baseline for the fixture's path
(1 for the default path, 1 for single-layer, `1 + backstop_count` for strict subsets) **and**
that the #44 top-up adds **at most one** call beyond it.

#### B.3.5 Oracle and red-checks (superseding `spec.md:314-319`)

- **Oracle.** G-XL flips RED→GREEN; the strict-xfail marker is removed **in the same commit**
  as the `retrieve.py` change; AC-125 7/7 unanimous over the C-2 seed protocol; both suite
  modes plus the baked-image CI form green; `test_subset_layer_recall_no_regression` green.
- **Maker red-check.** Revert the fetch-shape change only (keep the tests) ⇒ G-XL RED again;
  restore. Plus: move the semantic target into `episodic` on the fixed build ⇒ the gate must
  still measure *layer*, not record identity (`test_relocated_target_control`, AC-343).
- **Checker red-check (D8, axis-distinct):** inflate one episodic filler's TF above
  `sem-target` so it becomes the legitimate global BM25 best ⇒ AC-340 RED. This proves the
  gate tracks **score order through the global merge**, not target identity or layer label.

---

### B.4 §4 #44 — REPLACEMENT  ·  unit W-44  ·  needs W-HOP=ALLOW + W-45 (Option A shape)  ·  v2.1.0

*(Supersedes `spec.md:323-357` in full. FORGE D6 + D7. Discharges K-B5, K-B13(b), and carries
K-B13(c) forward explicitly.)*

#### B.4.1 Classification: #44 is a REAL PRODUCTION DEFECT at default deployment

Kupo's K-B13(b) was correct about the constructor and about the risk of copying the
fusion-gate template — and it changes the *fixture*, not the *classification*. The wiring
chain, re-read at `b7f1a47`:

```
config.py:333    recall_active_only: bool = True    # "W6 gate PASS + correctness"
config.py:437    recall_active_only=_env_bool("CRYSTALIUM_RECALL_ACTIVE_ONLY", True)
server.py:600    recall_active_only=config.recall_active_only,     (stdio + http entrypoint)
__main__.py:351  recall_active_only=config.recall_active_only,     (CLI entrypoint)
retrieve.py:307  recall_active_only: bool = False                  <- construction-site default
```

**Every shipped entrypoint passes the `Config` value, and the `Config` value is `True` by
default.** The `False` at `retrieve.py:307` binds only for *direct* construction — evals and
tests (`fusion_gate.py:243` sets it explicitly). Production runs the active-only path,
deprecated top-hits censor the fetch, and active hits starve **silently** — exactly the
issue's report: *"no error, no log line and no explain anomaly."*

The #44 closing comment and the v2.1.0 release notes **must name this chain**
(`config.py:333` → `server.py:600`) as the evidence that the defect is live at default
deployment. This strengthens the case for shipping v2.1.0; it does not weaken it.

#### B.4.2 Approach — bounded status-aware top-up, caller-side, fence-preserving (carried forward)

In `retrieve.py` only, after the sparse fetch: count candidates failing `_is_active`
(the predicate already defined caller-side at `retrieve.py:572-584`). If any are inactive
**and** the fetch was censored (`raw_n_sparse >= cap`), issue **at most one** additional
`bm25_search` at a widened `k` (`k_wide = min(cap + n_inactive_observed, HARD_TOPUP_CEILING)`),
merge preserving BM25 order, dedupe, then **recompute the censoring signal against the final
width**.

**K-B13(c), carried forward explicitly because it is load-bearing and the checker confirmed
it verbatim:** `retrieve.py:230-233` states the censoring test is *"a property of the FETCH"*,
and `retrieve.py:256` implements it as `raw_n_sparse == 0 or raw_n_sparse >= cap`. So after a
top-up, **both** `raw_n_sparse` and `cap` must refer to the widened fetch, or the boost is
decided against a fetch that no longer exists. The design is sound as written.

**Which call is widened, under Option A's three cases.** *FORGE did not rule this; it is my
normative choice, recorded here so an implementer does not silently invent a different one.*
The top-up widens **the global head call only** — on the default and strict-subset paths that
is the global `bm25_search(layer_filter=None, k=candidate_k * len(_ALL_LAYERS))`; on the
single-layer path it is that path's single filtered call. Rationale: the censoring signal is
defined against the fetch that produced `raw_n_sparse`, which is the head. The §B.3.1 backstop
is a *coverage* mechanism with its own trigger and is **not** re-issued by the top-up.
If AC-348 and AC-355 cannot both be satisfied under this choice, that is an S-13 event —
route it to the ladder, do **not** relax either gate.

This adds **no** parameter to `bm25_search`, **no** public storage method, and **no** status
predicate in SQL — the fence's letter and spirit both hold (`retrieve.py:605-615`,
`:241-242`). W-HOP records that the fence was *consulted and satisfied*. If the executor
instead prefers a `status_filter=` parameter on `bm25_search`, that **does** break the fence
and W-HOP must record an explicit amend **before any code**. `layers/episodic.py:319`, the
second consumer, is untouched either way.

Emit `explain.fusion.sparse_topup: {fired: bool, k_initial, k_final, n_inactive_observed}`,
**every field derived from the fetch actually performed** (the #36 F-V3 lesson: a counter
computed independently of the code it describes reported five drops that never happened).

#### B.4.3 The fixture pin — production parity, asserted at the instance (D6)

1. The W-44 fixture pins **`recall_active_only=True`** as *production parity*, not as an
   opt-in fudge.
2. The pin is asserted by reading the flag back **off the `Aetheryte` instance**:
   `assert aetheryte.recall_active_only is True`. **Never off the kwargs dict the fixture just
   wrote** — that is a tautology and cannot fail (VP-M4's rule, generalised).
3. AC-345/346/347/348's GIVEN clauses gain *"with `recall_active_only=True` (production
   parity, `config.py:333`)"*.
4. **A negative-control node ships: `test_topup_inert_when_active_only_off`** (new **AC-356**).
   Same corpus, `recall_active_only=False`, spy asserts **zero** additional `bm25_search` calls
   and `explain.fusion.sparse_topup.fired == false`. This documents the flag-off path as
   deliberately out of scope and prevents the top-up from firing where `_is_active` is
   vacuously `True` (`retrieve.py:573-574`).

**Reversal (D6):** if `Config.recall_active_only`'s default is ever flipped to `False` (or the
env default at `config.py:437` changes), the "production defect" classification reverts to
configuration-gated and the closing comment must be amended. If the negative control shows the
top-up firing with the flag off, the implementation gated it on the wrong predicate — **stop**,
it is in the fence's territory.

#### B.4.4 W-44 is a MANDATED TWO-COMMIT UNIT with a strict-xfail sentinel (D7)

`spec.md`'s AC-345/AC-346 were mutually exclusive on any single tree (K-B5), and the release
checklist demanded both green. Resolution:

- **Commit 1 — tests on the pre-fix base** (the branch base, i.e. post-W-45 merge). Adds
  `mcp-server/tests/test_sparse_status_topup.py` with **both** nodes and **no markers**. On
  that tree: `test_prefix_baseline_starves_active_hits` (AC-345) is **GREEN**;
  `test_topup_recovers_active_hits` (AC-346) is **RED**. The maker records both runs — command,
  tree SHA, exit code, output tail — to `CHANGE/ac345-prefix-evidence.txt`. **This is the
  pre-fix characterisation, pinned in git history where any checker can `git checkout <sha>`
  and re-run it** — independently re-derivable, not a maker-attested text file.
- **Commit 2 — the fix.** The `retrieve.py` top-up lands in the **same commit** as

  ```python
  @pytest.mark.xfail(
      strict=True,
      reason="pre-#44 starvation characterisation; XPASS = starvation regression (#44)",
  )
  ```

  added to AC-345's node. Post-fix the node's assertions fail ⇒ strict xfail ⇒ suite green.
  If the starvation ever returns, the node passes ⇒ XPASS ⇒ strict ⇒ **suite RED**. The
  sentinel is self-enforcing on every future tree — the `test_fusion_gate.py:85-103` precedent
  this repo already carries.

**Release-checklist convention:** *"AC-345 green = **XFAIL** on the tagged tree; **XPASS is
RED**."* This is annotated in `verification-plan.amend-01.md` §5.

**D9 step 4 is not violated:** D7's sentinel guards a **shipped** fix; it never stands in for
an unshippable one.

**Reversal (D7):** if the image's pytest changes strict-xfail semantics (XPASS-strict no
longer failing the suite), the sentinel is dead and AC-345 converts to an inverted assertion
node merged into AC-346, with the characterisation surviving only as the commit-1 artifact.
If squash-merge policy forbids two commits, the commit-1 evidence moves to a checker-re-run
protocol pinned to the **pre-merge branch SHA**; the XFAIL half is unaffected.

#### B.4.5 Oracle and red-checks

- **Oracle.** `test_sparse_status_topup.py`: a fixture with `cap` deprecated near-duplicates
  ranking above `cap - 1` active hits, `recall_active_only=True`. Pre-fix: active hits absent
  from `result.records` and `explain.fusion.selectivity == 0.0` (boost silently disabled).
  Post-fix: active hits present and `selectivity > 0.0`.
- **Maker red-checks.** (i) Delete the top-up call, keep the `explain.fusion.sparse_topup`
  counter ⇒ AC-346 RED. (ii) Set `HARD_TOPUP_CEILING = cap` (no widening possible) ⇒ RED.
- **Checker red-check (D8, axis-distinct — data, not code).** Deepen the deprecated stratum:
  add deprecated rows until even the widened `k_wide` fetch is fully deprecated-censored ⇒
  AC-346 RED, active hits unrecoverable **through the data**; and cross-check that
  `explain.fusion.sparse_topup` reports `fired: true` **with recovery absent** — the counter
  must describe the fetch, not the intention. The old row *"mark every fixture crystal
  active"* is **deleted**: under the D6 pin it merely disarms the fixture (AC-346 goes green),
  making no gate red.

---

### B.5 §4 #42 — REPLACEMENT  ·  unit W-42  ·  needs W-G-WD + W-44  ·  v2.1.0

*(Supersedes `spec.md:360-386` in full. FORGE D2. Discharges K-B2.)*

**Why the original is void.** `spec.md` named two sites (`graph.py:225`, `:302`). Both anchors
are correct; the **list is incomplete**. `graph.py:272` (`hop_ids -= original_seeds`, added by
#41, comment at `:257-263`) re-subtracts the seeds *after* `_neighbor_expand_one_hop` returns,
so dropping only the `:225` filter leaves seed exclusion **fully in force**. And
`decaying_walk` does no expansion of its own — it calls
`self.neighbor_expand(sorted(frontier), depth=1)` (`graph.py:305`), whose own `original_seeds`
at hop 1 **is** the walk's seed set, so `visited = set()` at `:302` changes nothing at hop 1.
On `spec.md`'s own depth-1 oracle the specified `exclude_seeds=False` was **byte-identical to
`True`**: AC-350 green under both, AC-351's red-check unable to go red.

#### B.5.1 Authoritative site list and threading (normative)

Parameter `exclude_seeds: bool = True` on `neighbor_expand` and `decaying_walk`.
Default `True` = today's behaviour byte-identically, so **Dream and every other consumer are
untouched by construction**.

| site (at `b7f1a47`) | current code | change |
|---|---|---|
| `graph.py:225` (in `_neighbor_expand_one_hop`) | `if neighbor_id not in seed_ids:` | Thread a **new parameter `exclude_input: bool = True`** on `_neighbor_expand_one_hop`; the filter applies only when it is `True`. |
| `graph.py:271` (call site in `neighbor_expand`) | `hop_ids = self._neighbor_expand_one_hop(frontier, rel_filter)` | pass `exclude_input=exclude_seeds` |
| `graph.py:272` | `hop_ids -= original_seeds` | `if exclude_seeds: hop_ids -= original_seeds` |
| `graph.py:302` (in `decaying_walk`) | `visited: set[str] = set(seed_ids)` | `visited = set(seed_ids) if exclude_seeds else set()` |
| `graph.py:305` (walk's inner call) | `self.neighbor_expand(sorted(frontier), depth=1)` | pass `exclude_seeds=exclude_seeds` through |
| **`graph.py:266`** (`visited = set(frontier)`) | — | **DELIBERATELY UNCHANGED under both flag values.** A ruled divergence from Kupo's four-site enumeration. |
| docstrings `graph.py:203`, `:247`, `:292` | *"excluding/excludes the seeds themselves"* | contract text updated to state the default **and** the opt-out |

**The `:266`-unchanged clause and its PROOF OBLIGATION.** `:266` controls *re-expansion*
(the `visited` set that prunes the next frontier), **not** *result membership* (`result_ids`,
`:264`/`:273`). Every seed is already expanded at hop 0 because the seeds **are** the initial
frontier, so conditioning `:266` on the flag would change nothing except adding redundant
re-expansion work. **This is a derivation, so it is not asserted in prose — T2 below is
designed to prove it**: a hop-2-discovered seed must appear in `result_ids` with `:266`
untouched.

#### B.5.2 Oracle — three topologies, ALL MANDATORY, all in `test_storage_graph.py`

A single fixture cannot attribute across three sites that bind on three different shapes
(§0.2's rule applied to this unit). Expected values below were traced against the source at
`b7f1a47` during this pass.

**T1 — depth 1, frontier-mates.** *Makes AC-350/AC-351 falsifiable at depth 1 — the exact
topology on which `spec.md`'s version was a no-op.* Seeds `{S1, S2}`; edges `S1→S2`, `S1→N1`.
`neighbor_expand(["S1","S2"], depth=1)`:

| flag | expected |
|---|---|
| `exclude_seeds=True` | `{"N1"}` — **byte-identical to `b7f1a47`** |
| `exclude_seeds=False` | `{"N1", "S2"}` |

Both `:225` and `:272` bind here; with the full threading the two branches now differ, so
**AC-351's default-flip red-check genuinely goes red**.

**T2 — depth 2.** *Exercises `:272` at hop 2 and discharges the `:266` proof obligation.*
Seeds `{S1, S2}`; edges `S1→M`, `M→S2`, `M→N2`. `neighbor_expand(["S1","S2"], depth=2)`:

| flag | expected |
|---|---|
| `exclude_seeds=True` | `{"M", "N2"}` |
| `exclude_seeds=False` | `{"M", "N2", "S2"}` — **S2 appears in results with `:266` untouched** |

**T3 — walk.** *Exercises `:302` and the `:305` pass-through.* Same graph as T2,
`decaying_walk(["S1","S2"], max_hops=2, decay=0.5)`:

| flag | expected |
|---|---|
| `exclude_seeds=True` | `{"M": 0.5, "N2": 0.25}` |
| `exclude_seeds=False` | `{"M": 0.5, "N2": 0.25, "S2": 0.25}` — S2 at its **true shortest-hop** distance |

**T3-variant (hop-1 seed credit).** Seeds `{S1, S2}`, single edge `S1→S2`,
`decaying_walk(max_hops=2, decay=0.5)`: `exclude_seeds=False` ⇒ `{"S2": 0.5}`;
`exclude_seeds=True` ⇒ `{}`.

- **AC-350** asserts True-branch byte-identity on **all three** topologies.
- **AC-351** (flip the default to `False`) must go RED — it now does, **on T1 alone**.
- **New AC-354** asserts the False-branch expected sets/weights **exactly as listed above**.

#### B.5.3 Retrieval opt-in

`retrieve.py`'s two call sites (W-42's existing grant) pass the flag from
`Config.recall_seed_derived_credit` (new field, owned by W-42 in v2.1.0 per §B.1). The field's
**default remains decided by the DP-1(b) re-check** (§6 S-1) — unchanged from `spec.md`.

#### B.5.4 Oracle layers 2 and 3, and red-checks

2. **DP-1(b) re-check on G-WD** (§3.4 — `deliberation.md §8`'s reversal fires on *"evidence
   that anomaly B's seed exclusion is removed (F-B)"*, and **#42 IS F-B**): a derived-only
   record must **not** outrank a record backed by two base arms (AC-352). AC-352 now ships
   with a **mechanical positive control** (K-N15): at `w_derived = 100.0` the same fixture
   **must** report `p1_recreated: true` (`config.py:296-298`'s stated ceiling). A fixture that
   cannot re-create P1 on demand cannot falsify its absence.
3. AC-125 7/7 unanimous; retrieval gate non-regressed; Dream suites green with
   `mcp-server/src/crystalium/dream/` byte-unchanged (AC-353).

- **Maker red-check.** Flip the `exclude_seeds` default to `False` ⇒ AC-350's byte-identity
  test RED on T1. If it stays green, the parameter is not wired to the behaviour it names.
- **Checker red-check (D8, axis-distinct — per-site wiring).** Sever **one** threading site
  only: make `graph.py:272`'s subtraction unconditional again (ignore the flag at that site)
  ⇒ **AC-354 RED on T1 and T2 while AC-350 stays GREEN**. The K-B2 dominant site is chosen
  deliberately: this converts Kupo's finding into the checker's sharpest instrument. *(The old
  row — "remove the `visited = set()` half only" — is deleted: it was self-inverting and could
  not go red at depth 1.)*

**STOP S-1 unchanged.** If a post-#41 multi-seed measurement shows relaxation regresses
multi-hop F1, or AC-352 shows P1 re-creation, **keep exclusion** and close #42 as *policy
affirmed, relaxation rejected with measurement* — a legitimate closure.

**Reversal (D2):** if T2 shows a hop-2-discovered seed **absent** under `exclude_seeds=False`
with the five listed changes applied, then `:266` (or the `:274` frontier arithmetic) is
load-bearing for membership after all — the `:266`-unchanged clause is overturned and the site
list reopens.

---

### B.6 §4 #55 — REPLACEMENT  ·  units W-G-WD (fixture) + W-DOC (disposition)  ·  v2.0.2

*(Supersedes `spec.md:431-467` items 2 and the item-2 red-check. FORGE D4. Discharges K-B6,
K-N1, K-N3.)*

#### B.6.1 Item 2 — the "§D2 identity harness re-run" is STRUCK and replaced by a forward obligation

The premise was **false**. At `b7f1a47` there is no `evals/d2_identity.py`, no `d2-identity`
subcommand in `evals/__main__.py:155-208`, and the only trace of the measurement is prose at
`config.py:292-293` — a **recorded result**, not a re-runnable harness. So "re-run" was not
cheap (a new module + CLI registration + an ownership row) and was never a refresh.

**AC-319 and AC-320 are STRUCK. The harness is NOT built in this campaign.**

**Binding forward obligation, replacing it:** any future change that touches combiner
arithmetic — `weighted_rrf_merge_scored`, the RRF constant, or the semantics of
`fusion_weight_*` — **MUST** build and run a d2-identity harness (20 in-process comparisons,
`max_abs_diff == 0.0` at `w = 1.0`, plus a 1-ULP perturbation red-check) **as a precondition
of that change**. Recorded in two places: the #55 closing comment, and one line inside
`config.py`'s comment block at `:289-312` (W-DOC's grant).

**Why this is not half-shipping #55:** the issue's core is item 1, whose disposition is
already ruled (§5.2 — band formally unsupported) and survives. Item 2 was scaffolding whose
premise dissolved. The identity property stands on the recorded structural argument FORGE
accepted — *W1-W4 and #42 change candidate generation and derived-arm contents, not combiner
arithmetic* — which this campaign does not disturb. Building a harness to verify a property
that no shipped change can affect is **a gate with no defect to fail on**: the campaign's own
named anti-pattern, inverted.

**Reversal (D4):** if W-42's DP-1(b) re-check (AC-352) or any Wave-2 gate produces a
fused-score anomaly attributable to combiner arithmetic rather than membership (a record's
fused score changing with **no** change in any arm's membership or ranks), the structural
argument is broken and this ruling **flips from DROP to BUILD-NOW before v2.1.0 tags**.

#### B.6.2 Item 3 — the eval note, re-scoped to a REACHABILITY deliverable

Kupo verified the required statement **already exists**, at `config.py:311-312`:

> *"NOTE for future sweeps: the FUSION gate cannot express weight sensitivity (target/Z at
> k=2); only the retrieval gate is informative."*

So "write the note" is already done and an AC that mandates writing it would be satisfied
before the campaign starts (the K-B12 defect class). The real gap is **reachability**: an eval
author running a weight sweep reads `evals/BENCH-NOTES.md`, not `config.py`. Item 3's
deliverable is therefore a **pointer line in `evals/BENCH-NOTES.md`** (W-DOC's grant) naming
the fusion gate as uninformative for weight sensitivity and citing `config.py:309-312`.
AC-371 accordingly asserts **both**: the `config.py` statement survives the campaign
(a non-regression assertion that a careless config edit *can* fail) **and** the `BENCH-NOTES.md`
pointer exists.

#### B.6.3 Item 1 — disposition UNCHANGED, and not reopened

`spec.md` §5.2 stands verbatim: **leave the sub-1.0 band formally unsupported.** The
config-comment line (W-DOC) states that values below 1.0 are legal, unsupported, and will
remain uncharacterised until a fixture with non-stipulated ground truth exists. C-9 holds:
no test, doc, CHANGELOG line, or gate output may present a sub-1.0 `fusion_weight_derived` as
a supported precision dial.

#### B.6.4 The W-G-WD fixture — unchanged, with AC-318's sentinel fixed

The weight-discriminating fixture is built exactly as `spec.md:436-447` describes (single
layer, `corpus < candidate_k`, real `GraphStore`, stub dense arm; `A` = derived-arm-only
phantom, `B` = one base-arm vote at known rank `r`; ordering decided by `w_derived/(60+r_A)`
vs `1/(60+r_B)`; **>= 2 distinct outcomes** across `w_derived ∈ {0.90, 0.95, 1.00}`).

**Its declared purpose is the #42 DP-1(b) re-check oracle, NOT band characterisation** — and
AC-318's check of that claim is fixed per K-N1: `'not' in d.lower()` matched *"notes"*,
*"cannot"*, *"annotation"*, so a first paragraph reading *"DP-1(b) note: this module
characterises the sub-1.0 band"* would have passed while asserting exactly what §5.2 forbids.
**The first docstring paragraph must contain the literal string `NOT band characterisation`**,
and AC-318 asserts that literal.

**Checker red-check (D8) — the G-WD gate previously had NO perturbation anywhere in the plan.**
Sever record `A`'s graph edge (A loses its only support) ⇒ AC-317's ">= 2 distinct outcomes"
fails: every weight produces the identical outcome, the exact degeneracy #55 reports.

---

### B.7 §4 #48 — REPLACEMENT  ·  unit W-G-FLOOR  ·  needs W-RIG  ·  v2.0.2

*(Supersedes `spec.md:389-427` where it describes VP-M1's mechanism, and
`verification-plan.md:50-72` in full. FORGE D5. Discharges K-B7.)*

#### B.7.1 The prediction, restated

Post-#41 the walk expands **ALL** seeds (`graph.py:215-230` loops every seed; `graph.py:305`
sorts the frontier). On the shipped fusion fixture, the edge-bearing nodes `N1/N2/N3` sit at
dense ranks 1-3 and are therefore inside **both** `[:10]` and `[:1000]`, so the derived arm's
*union* may be identical at both floors. **#41 may have removed the floor's only channel on
that topology**, which would make AC-139 as literally worded *less* obtainable, not more.

This is a derivation. **W-G-FLOOR's first task is to confirm or refute it (VP-M1).**

Note the tree carries the **opposite**, prior claim in prose — `fusion_gate.py:152-157` and
`test_fusion_gate.py:50-59` both assert the channel is *live and measured* at the derived
level while masked at the fused surface by `N1`'s id-ascending tie-break. Both can be true
simultaneously; only a **derived-membership** measurement decides `channel_live`.

#### B.7.2 The probe's location and construction (D5 — neither of Kupo's two options)

`spec.md`/`verification-plan.md` drove VP-M1 from `run_floor_probe(floor=…, weighted=False)`.
That symbol **exists** with exactly that keyword-only signature (`fusion_gate.py:290-292`),
but it returns `run_arm`'s dict — `{"target_rank", "retrieved", "cross_layer"}`
(`fusion_gate.py:266`) — with **no derived-arm field**, and `run_arm` never passes
`explain=True` (`fusion_gate.py:250-253`). `floor10_derived` / `floor1000_derived` were
unobtainable. Kupo's two escapes were (i) redefine on `retrieved`, or (ii) extend
`run_floor_probe`, which §3.1 forbids for this unit. **FORGE chose neither.**

**The probe lives in `evals/floor_sensitivity_gate.py` — W-G-FLOOR's own new file — as
`vp_m1_probe(*, floor: int) -> dict`.** `evals/fusion_gate.py` stays **byte-untouched**; no
fence exception exists or is needed. Normative construction:

1. `from evals.fusion_gate import _build_fixture, run_floor_probe` — **imports are reads, not
   edits**; §3.1's freeze governs the file's bytes and the AC-125 measurement, neither of which
   an import disturbs.
2. Build the stores and `Aetheryte` with **exactly** `run_arm`'s construction flags
   (`completion=True, completion_max_hops=1, completion_decay=0.5, recall_active_only=False,
   recall_relevance_primary=True`, weights from `Config` — `fusion_gate.py:232-249`) — copied
   once, then **bound by the self-check in (5)**.
3. **Wrap the real `GraphStore` in a thin recording proxy** that delegates every method and
   records the return values of `decaying_walk` and `neighbor_expand`. Pass the proxy to
   `Aetheryte`. `floorN_derived` := the **sorted union of ids the walk actually returned**.
   This is the membership the prediction is *about*, captured where it is produced, with zero
   re-implementation of `retrieve.py` internals and zero reliance on `explain` — which carries
   only `arm_sizes` (`retrieve.py:1098-1104`), i.e. **sizes, not membership**.
4. Apply the `FETCH_WIDTH_FLOOR` monkeypatch in `try/finally` (the `fusion_gate.py:227-229,
   264` pattern) so an exception cannot leak a patched module constant into the rest of the
   session (K-N10's failure mode).
5. **Self-check — binds the duplicate to the original.** The probe also calls
   `run_floor_probe(floor=floor, weighted=False)` on a **fresh data dir** and asserts its own
   `{target_rank, retrieved}` equals it. If `fusion_gate`'s recall path ever drifts, the probe
   **invalidates itself loudly** instead of silently measuring a divergent construction.

`channel_live := any(seed.floor10_derived != seed.floor1000_derived)` over the 7 spawned
seeds. AC-321 becomes a **self-consistency** check: the verdict must be derivable from the
per-seed rows recorded in the same file, so a fabricated `channel_live` that disagrees with its
own evidence **fails**.

**Reversal (D5):** if the recording proxy is shown to perturb the measurement (e.g. `Aetheryte`
type-checks its `graph_store`, or the proxy shifts hash iteration order), the seam capture is
invalid and the fallback is the `retrieved`-only redefinition **WITH its one-sidedness stated
in the artifact**: *"identical ⇒ no observable channel at the fused surface; derived-level
identity not instrumented."* If a future `explain` schema adds arm **membership**, the proxy is
retired in favour of `explain=True`.

#### B.7.3 A PRELIMINARY, ONE-SIDED VP-M1 has already been run — and it does NOT settle `channel_live`

`CHANGE/vp-m1-floor-channel.json` records a 7-seed `retrieved`-only capture already executed
by the maker: at every seed, both weighted and unweighted, `f10_retrieved == f1000_retrieved`
and `differ: false`.

**This is exactly the one-sided proxy FORGE describes. Stated explicitly:**

- Differing fused lists would **REFUTE** channel-dead. They did not differ, so nothing is
  refuted.
- **Identical fused lists do NOT CONFIRM channel-dead.** The derived memberships could differ
  while the fused surface is masked by weights or by the id-ascending tie-break — which is
  precisely what `test_fusion_gate.py:60-73` claims is happening on this fixture.
- Therefore the preliminary capture is **uninformative about `channel_live` as D5 defines it**
  (derived membership). It is retained as evidence of the *fused-surface* invariance only,
  and **must not be cited as confirmation of `spec.md` §4 #48's prediction.**
- The D5 probe (derived membership via the `graph_store` spy) still **must** be run, and its
  output supersedes this file under the name `CHANGE/vp-m1-floor-channel.json` (the
  preliminary is preserved as `CHANGE/vp-m1-floor-channel.preliminary.json`).

#### B.7.4 The new fixture, oracle and red-checks (carried forward from `spec.md`, unchanged)

The routing rule is unchanged: **`channel_live` either way, the new fixture gets built**; only
the carried-forward prose claim differs. New `evals/floor_sensitivity_gate.py` fixture:
ids renamed so every competitor sorts **after** `target` (tie-break-neutral — safe because
this is a **new file**, AC-125's fixture untouched, §3.1); the **edge-bearing** competitor
placed at dense rank ~12, i.e. **inside `[:15]` but outside `[:10]`**; the phantom, once
discovered, earns a derived vote sufficient to demote `target`. Move AC-138/AC-139 here (per
AC-139's own *"moved, not weakened"* escape hatch) and delete the strict-xfail block at
`test_fusion_gate.py:85-113` **together with its now-empty enclosing class
`TestFetchWidthFloorInflation` (`:42-83`)**.

- **Oracle.** `floor=10` and `floor=1000` produce **disjoint** target-rank distributions over
  the 7-seed C-2 protocol — **7 spawned processes**, never `--seeds 7` in one process
  (K-B3: `PYTHONHASHSEED` is read by CPython before `main()` and cannot be re-seeded in a
  running interpreter).
- **Maker red-checks.** (i) Move the edge-bearing competitor to dense rank 3 (inside both
  floors) ⇒ the divergence assertion RED. (ii) Run both probes at `floor=10` ⇒ RED.
- **Checker red-check (D8, axis-distinct — graph topology, not rank placement).** Delete the
  edge from the edge-bearing competitor to its phantom ⇒ AC-322's disjointness fails: no
  derived vote exists at either floor, both distributions collapse onto the same ranks.
  *(The old checker row — "run both probes at floor 1000" — is deleted: it was the maker's own
  perturbation with a different constant, a direct violation of the table's "must differ"
  rule.)*
- **STOP S-5 → S-13 class (c).** If no fixture makes the floor change the fused rank
  deterministically post-#41, AC-139 as worded is **unobtainable**: **retire** AC-138/AC-139
  with a mechanism note and close #48 as *retired*, not *discharged*. Do **not** ship a
  permanent strict-xfail and do **not** invent a fixture that only appears to work.

---

## C. §6 — Risks and STOP conditions: replacements and the new S-13

### C.1 NEW **S-13 — the Unfailable-Gate Disposition ladder** (FORGE D9, in full)

**Applied by the implementer autonomously, recorded in the change folder, no escalation.**
S-3, S-5, S-7 and S-8 all terminate here; this is their **common terminal action**.

1. **Audit the gate's own controls FIRST.** A green gate with a red or `"confounded"` liveness
   check is a broken **fixture**, not evidence about the defect — fix the fixture and
   re-measure. **Only a green gate with fully green liveness enters the ladder.** (This step
   exists because K-B1 demonstrated that the most likely cause of an unexpectedly-green gate
   is a broken fixture; burning the single redesign cycle on a fixture bug is waste.)
2. **ONE bounded redesign cycle.** A different fixture axis may be tried **once**, and its
   load-bearing premise **must be measured before the build** (the D1/VP-M2 pattern: the
   premise becomes a recorded artifact, never an adjective in the spec). The one-cycle bound
   is deliberate — unbounded redesign converges on a fixture *written to go red*, which is
   H-D (the campaign's rejected alternative) through the back door.
3. **If the redesigned gate still cannot go red, close the issue by CLASSIFIED disposition.**
   Three mutually exclusive classes; the closing comment **must name which**, with the
   measurement artifact attached:
   - **(a) premise-refuted** — the measurement shows the defect does not exist on the current
     tree. Close as *"not reproducible at `<sha>`, measurement attached."*
     *(§B.2.7 step 3 is this class, for #45.)*
   - **(b) unobservable-without-non-stipulated-ground-truth** — the defect may be real, but no
     synthetic fixture can adjudicate it because the fixture author stipulates the ground
     truth. Close **WONTFIX-with-rationale plus a reopen condition naming the production
     signal** that would decide it. *(The standing #47/#55 precedent, §5.1/§5.2 — reaffirmed,
     not modified.)*
   - **(c) obsoleted-by-prior-fix** — the mechanism the gate was built to measure was removed
     by an earlier change. **Retire** the criterion with a mechanism note. *(S-5's class for
     AC-138/AC-139. "Retired" and "discharged" remain **different closures**, and the issue
     comment must say which.)*
4. **Absolute prohibitions, regardless of class:**
   - **never ship the behaviour change the gate was meant to license** — a fix without a red
     gate is H-D re-committed;
   - **never leave a permanent strict-xfail as a disposition substitute** (S-5's rule,
     generalised). **D7's sentinel is not an exception**: it guards a *shipped* fix; it does
     not stand in for an unshippable one;
   - **never present the construct as a measurement** (S-11, generalised beyond #47/#55 to
     every gate);
   - **never quietly swap a failing perturbation for an easier one** (D8's reversal): a
     checker perturbation that does not flip its gate RED is *itself* a blocking finding
     against the gate, and routes here.
5. **The gate artifact merges only if its controls are falsifiable** — i.e. its liveness
   checks can be *shown* to fire (D8's G-XL row is the template). **A gate that can neither
   fail on its defect nor attribute through its controls is DELETED, not merged.** A
   permanently-green test is not neutral; it is camouflage for the next regression.

**Reversal (D9):** if production telemetry (a class-(b) reopen condition) later shows a defect
that a class-(a) closure declared not-reproducible, the closure was **wrong**: reopen, attach
both artifacts, and treat the original gate's green as a finding *about the gate*.

### C.2 Replacements to existing STOP rows

| id | superseded text | replacement |
|---|---|---|
| **S-3** | *"G-XL is green on `b7f1a47` → STOP, redesign"* | **Trigger:** `CHANGE/vp-m2-gxl-red.json` reports `target_rank != expected_blocked_rank` **with all liveness assertions green**. **Action:** enter **S-13**. Liveness red is *not* an S-3 event (S-13 step 1). Terminal branch = S-13 class (a): #45 closes premise-refuted, W-45 cancelled, v2.1.0 re-scopes to W-44 (per-layer AC-348 variant) + W-42. |
| **S-5** | *"No fixture makes `FETCH_WIDTH_FLOOR` change the fused rank deterministically post-#41 → retire AC-139"* | Unchanged in substance; **terminal action is now S-13 class (c)** — retire with a mechanism note, issue comment says *retired*, not *discharged*. No permanent strict-xfail. |
| **S-7** | *"G-CORPUS stays RED when the corpus is shrunk below `candidate_k` → STOP, WONTFIX #47"* | Unchanged in substance; **terminal action is now S-13**, and #47's WONTFIX is explicitly class (b) — WONTFIX-with-rationale **plus the named production reopen signal** (`explain.fusion` data from a real store showing the ceiling binding). |
| **S-8** | *"**Any** new gate passes on the pre-fix tree → It is not a gate."* | **VOID AS WORDED (K-N20)** — it fires on the plan's own mandated GREEN controls (G-CORPUS's small-corpus control *must* be green pre-fix; G-WD and G-FLOOR precede **no fix at all** and are characterisation instruments). **Replacement:** *"A gate's **defect-asserting node** — the single node named in that gate's AC as RED-on-`b7f1a47` (G-XL: AC-310; G-CORPUS: AC-314) — passes on the pre-fix tree ⇒ it is not a gate ⇒ **S-13**. This row does NOT apply to a gate's controls, to its negative controls, or to characterisation instruments that precede no fix (G-WD, G-FLOOR): for those, the falsifiability bar is D8's checker perturbation flipping them RED, not pre-fix redness."* |
| **S-12** | *"Any unit's diff touches a file another unit exclusively owns → DRIFT. `ramza-drift --amend` or revert."* | **MECHANISM REPLACED (K-B11).** `ramza-drift` checks a **single plan-level `declared_scope`**, and the union of all units' files *is* that scope — so every cross-unit overlap reports **clean**. Worse, `ramza-drift` defaults `REPO="."` and the state file lives in the **nexus**, so `verification-plan.md:175`'s invocation would diff the *nexus* against a *crystalium* tag: a convincing, silent zero. **Replacement:** (i) every `ramza-drift` invocation carries `--repo /home/rynaro/workspace/oss/agents/crystalium` (it retains value as a *plan-level* scope check); **and** (ii) per unit, `git diff --name-only <base>..<branch-tip>` must be a **subset of that unit's literal §2/§B.1 file list**, checked per unit and recorded. (ii) is the S-12 mechanism; (i) is a complement, not a substitute. |

**Unchanged rows:** S-1, S-2, S-4, S-6, S-9, S-10, S-11 stand exactly as written in `spec.md`
§6. S-1's trigger now additionally reads AC-352's **positive control** (K-N15): if the control
cannot produce `p1_recreated: true` at `w_derived = 100.0`, AC-352's `false` is not evidence and
S-1 cannot be cleared.

---

## D. §7 — Release-plan changes (FORGE's "Rulings that change the release plan", items 1-8, + K-N14)

1. **v2.0.2 contents SHRINK.** AC-319/AC-320 and the d2-identity harness are **out** (D4).
   #55 ships **items 1 + 3 + the G-WD fixture + the config comment** only. **No new code unit
   is added** — W-DOC is a comment/notes unit that absorbs two pre-existing ownership holes.
   The v2.0.2 contents line reads: *"W-ENTRY (#57), W-RIG, W-G-XL (#52, gate RED-as-strict-xfail
   + axis relabel), W-G-CORPUS (#47 gate), W-G-WD (#55 fixture), W-G-FLOOR (#48), W-CLI, W-DOC
   (#55 items 1+3 + config-comment disposition)."*
2. **v2.0.2's checker gate WIDENS.** AC-332 = **5** independently re-broken artifacts (not 4 —
   W-ENTRY plus the four gates), with D8's per-gate evidence schema and the **anti-replay diff
   step**. A boolean no longer satisfies it.
3. **v2.1.0 gains a precondition and a gate.** W-44 requires *"W-45 merged **with the Option A
   shape**"* (D3, replacing the bare "W-45 merged"); W-45 ships the K-N12 subset-starvation
   node (**AC-355**) and the three-case fetch shape; **AC-365** (the 3-row v2.1.0 checker
   table) joins the v2.1.0 checklist.
4. **W-45's start is ARTIFACT-GATED.** `CHANGE/vp-m2-gxl-red.json` measured on `b7f1a47`
   replaces *"RED by construction"* as the entry condition (D1). If it cannot be produced after
   **one** redesign, #45 closes **premise-refuted** (S-13 class (a)) and v2.1.0 re-scopes to
   W-44 (per-layer AC-348 variant) + W-42 — a smaller but still shippable minor.
5. **W-44 becomes a MANDATED TWO-COMMIT unit**, with the XFAIL sentinel convention annotated
   in the v2.1.0 checklist (D7): *"AC-345 green = XFAIL on the tagged tree; XPASS is RED."*
6. **#44's closure is RE-CLASSIFIED UPWARD**: it is a **production defect at default
   deployment** (`config.py:333` → `server.py:600`), and the release notes and issue comment
   must say so (D6). This strengthens the case for shipping v2.1.0.
7. **New S-13** (the disposition ladder) is the shared terminal action for S-3, S-5, S-7, S-8
   (D9). Wave 3's per-issue closure table gains the class vocabulary: **every** closing comment
   names one of *shipped* / *premise-refuted* / *unobservable-WONTFIX* / *retired*.
8. **Kupo's five un-ruled blocking findings are ACCEPTED as filed** with their minimal fixes,
   folded into this same revision pass: K-B3 (spawn-per-seed + non-empty guards), K-B8
   (`fence-amend.json` + `.md` sibling), K-B11 (`--repo` + per-unit literal file-list check),
   K-B12 (state-file jq + timestamp binding + per-batch critic records in CHANGE), K-B14
   (direct-import criteria for Wave-1 gates; `-m evals` **only** in W-CLI's own exit gate).
9. **NEW (K-N14) — the ESL record must be brought into conformance before the first tag.**
   `change.json` at plan time carried `acceptance_checks: []`, `has_code: false`,
   `status: "proposed"`, and `mcp__tonberry__verify` returned **C3 fail: `full: missing
   spec.yaml`**. Obligations: (i) `status` advances `proposed → in_progress → verified →
   archived` as the campaign moves (the ECM campaign's ESL record sat `in_progress` for five
   releases and the drift check that never ran found **real** drift behind 164 green tests —
   do not repeat it); (ii) `acceptance_checks` is populated from `spec.criteria.md` **plus**
   `spec.criteria.amend-01.md`, or the file explicitly references both by path and hash;
   (iii) `spec.yaml` is added to satisfy C3 at `full` tier; (iv) **`has_code` is set `true`**
   with an explicit note that the code lands in a **different repository**
   (`/home/rynaro/workspace/oss/agents/crystalium`, `target_repo` in the front-matter) — so
   the ESL code-state gates are run against **crystalium**, and if the tooling cannot do
   cross-repo, the skip is **recorded explicitly** rather than silently disabled by
   `has_code: false`.

**Unchanged in §7:** the v2.0.2 / v2.1.0 / #47 semver table; the `is_error`-class statement;
NC-2 (maker ≠ checker on **both** batches, and the v2.0.2 checker's mandate to *independently
re-break* every artifact); the roster/nexus 6-step bump procedure, including *the integrity PR
gets no CI* and *`eidolons mcp verify` exit 3 = INDETERMINATE, not a pass*, and the local
`.mcp.json` re-pin.

---

## E. §8 — Wave entry/exit deltas

| wave / unit | delta |
|---|---|
| **Wave 0 entry** | **SATISFIED** — `baseline-verdict.md` records VP-B1 `998 passed, 2 skipped, 1 xfailed`; VP-B2 `994 passed, 6 skipped, 1 xfailed`; VP-B3 7/7 `gate_pass: true`; VP-B4 as predicted; VP-B5 `b7f1a47`. S-6 does not fire. S-9 does not fire (counts differ, **outcomes** do not — that is SKIP_SLOW converting slow tests to skips, recorded so it is not later misread as drift). |
| **W-HOP exit** | emits **both** `fence-amend.json` (normative verdict) and `fence-amend.md` (narrative). DENY ⇒ S-10. |
| **W-G-XL exit** | **`CHANGE/vp-m2-gxl-red.json` written and passing AC-310 + AC-312**; C-XL-1 green; C-XL-3 (`global_bm25_rank0 == "sem-target"`) green; `fusion_gate.py` diff = the four key sites + the `:104-106` docstring sentence only, `_build_fixture` byte-identical (hash-asserted). |
| **W-G-FLOOR exit** | **VP-M1 with the D5 probe first** (7 spawned processes, derived membership via the `graph_store` spy, self-check against `run_floor_probe` green); then AC-322 disjointness over 7 spawns; `test_fusion_gate.py:42-113` (class + xfail block) deleted; `evals/fusion_gate.py` byte-untouched by this unit. |
| **W-DOC exit** *(new)* | AC-370 and AC-371 green; diff confined to `config.py:289-312` (comment block) and `evals/BENCH-NOTES.md`; AC-331's mechanical comment-only check passes on the `config.py` hunk. |
| **W-CLI exit** | `python -m evals <each-new-gate> --out <path>` writes a parseable artifact for each of the four gates; `evals/__main__.py` is the **only** file touched. This is the **only** place `-m evals` appears in a Wave-1 criterion (K-B14). |
| **W-45 entry** | `CHANGE/vp-m2-gxl-red.json` exists and passes (**replaces "G-XL RED, verified by the checker"**). |
| **W-44 entry** | W-45 merged **with the Option A shape**; W-HOP = ALLOW. **Two-commit unit** (D7). |
| **W-42 entry** | W-44 merged; G-WD available as the DP-1(b) oracle **and its positive control demonstrated** (`w_derived = 100.0` ⇒ `p1_recreated: true`). |
| **Wave 3** | every closing comment names an S-13 class: *shipped* / *premise-refuted* / *unobservable-WONTFIX* / *retired*. |

---

## F. What this amendment does NOT resolve

Stated plainly, because a plan that hides its open edges is the failure mode this campaign
exists to correct.

1. **Which call the #44 top-up widens under Option A's strict-subset path.** FORGE ruled the
   fetch shape (D3) and the top-up (D6/D7) separately and did not compose them. §B.4.2 makes
   a normative choice (widen the **head** only, never the backstop) with its reasoning. If
   AC-348 and AC-355 cannot both be satisfied under it, that is an **S-13** event — do not
   relax either gate.
2. **Whether the D3 strict-subset backstop's head/tail merge is materially correct.** FORGE
   rates it 82% and calls the tail-order imprecision *argued, not measured*. No gate in this
   plan measures tail order; AC-355 measures **coverage** only.
3. **Whether AC-322's disjointness is achievable at all post-#41.** Genuinely unknown. S-5 →
   S-13 class (c) is the ruled fallback; discovering it *is* a legitimate outcome for #48.
4. **`channel_live` itself.** The preliminary capture is one-sided and confirms nothing
   (§B.7.3). The D5 probe must still run.
5. **Whether the recording proxy perturbs the walk** (D5's own reversal condition). Not
   measurable until the probe exists.
6. **VP-M7's cap-semantics delta under Option A** — if the global cap pins `selectivity` to
   0.0 on realistic fixtures, D3's censoring clause reopens, bounded to signal definitions.
7. **Whether `has_code`/ESL code-state gates can run cross-repo at all** (§D item 9). If they
   cannot, the skip is recorded; it is not silently absorbed.

---

## G. Confidence

`ramza-score --rubric confidence` inputs are unchanged in shape; the substantive movement is:
**requirement_clarity rises** (the #45 A/B choice is now decided, #42's site list is complete,
#55 sheds an unbuildable item, and the G-XL separation mechanism is **measured** rather than
derived), while **decomposition_stability is flat** (W-DOC added, W-G-WD shrunk, W-44 split
into two commits). Two dispositions (#47, #55 item 1) remain recommendations that were already
ruled and are not reopened. The verdict stays **VALIDATE, not AUTO_PROCEED** — four
load-bearing measurements (VP-M2, VP-M1-with-spy, AC-322 disjointness, VP-M7's cap delta) are
still unexecuted, and this amendment's whole method is that an unexecuted claim is an artifact
obligation, not an adjective.
