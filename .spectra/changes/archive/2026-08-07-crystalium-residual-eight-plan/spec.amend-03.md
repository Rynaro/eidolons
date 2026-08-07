---
eidolon: ramza
kind: spec-amendment
amendment_id: amend-03
version: 1.0.0
created_at: 2026-08-05
change_id: crystalium-residual-eight-plan
maker: ramza
checker: kupo
supersedes: spec.amend-02.md §2 (rule-(f) audit table), §3.2 (AC-357's control), §3.4 (licensing table), §4 (the AC-313/AC-359 licensing collision); spec.amend-01.md §A.4 item 3, §B.1 (W-45 ownership), §B.3.2, §B.3.4 (AC-348), §B.4.2 (the head-only call), §B.4.4 (.txt), §B.7.2 (probe naming), §B.7.4 (fixture phantoms)
amends_criteria_sha256: f385f39bbabb6ee7371afd8815ef2de0e18905a0048d2f4000813edf219b0d9f
criteria_sha256_after_amend: 50803a00359409ddc6765477f782af62a151228f247ad619db0144948a783c40
target_repo: /home/rynaro/workspace/oss/agents/crystalium
target_head: b7f1a47
---

# spec.amend-03 — `crystalium-residual-eight-plan`

**Supersedes named parts of `spec.amend-01.md` and `spec.amend-02.md`. Neither is rewritten.**
Chain: `spec.md` (frozen) -> `spec.amend-01.md` -> `spec.amend-02.md` -> **`spec.amend-03.md`**
(governs on conflict).

Trigger: Kupo's **second** pass (`CHANGE/kupo-critique-02.md`) returned
**ACCEPT-WITH-AMENDMENTS** — 13 of 14 original blocking findings genuinely discharged, **6 new
blocking defects (K-C1..K-C6) and 15 non-blocking (K-C-N1..K-C-N15) introduced by the
amendments themselves**, plus two FORGE-fidelity gaps and one not-discharged carry-over
(K-N14). Every one of the six lives in surface `amend-01`/`amend-02` wrote. That is the honest
shape of this pass: **the amendments' own new surface was the least-attacked surface in the
plan**, and the checker attacked it by execution.

**Gates run for this amendment** (P0-2): `ramza-ears-lint` on `spec.criteria.amend-03.md`;
`ramza-freeze --amend` chaining `f385f39b… -> <new>` (entry 4 in `state.amendments[]`).

**Measured during this pass, in the pinned container and on the host** (read-only; the target
tree was verified clean before and after, `git status --porcelain` empty both times):

| # | measurement | result |
|---|---|---|
| 1 | `inspect.getsource` sha256 of `_crystal` / `_build_fixture` / `run_floor_probe` | `6fa658f4…` / `66d3e9a7…` / `eeea6f2b…` — Kupo's three pins reproduce exactly |
| 2 | **docstring-stripped** body sha256 of `run_floor_probe` | **`9b371898fdfc1a46966234589fa5d6a9c41248a4496f36f6abbcaa96f4bb1519`** — identical on host py **3.14.6** and container py **3.12.13**, so the new pin is interpreter-stable |
| 3 | AC-313 part 2's new whole-file canonicalisation, against `b7f1a47` | identical today; **passes** the licensed rename + docstring edit; **rejects** an illicit `_build_fixture` edit hidden behind a trailing `# cross_layer` comment (K-C-N9's hole, closed) |
| 4 | AC-359's literals at both docstring sites | `#41`, `56c8510`, `pre-#41`, `untested`, `not been re-tested`, `cab9b73`, `graph.py:215-230` **ABSENT at both**; `live and measured` (module) and `does have a live` (`run_floor_probe`) **PRESENT** ⇒ the two-site AC-359 **fails today** and greens only on real work |
| 5 | `explain.fusion` key set (`retrieve.py:1085-1105`) | carries `n_sparse_cap`, `selectivity`, `w_sparse`, `n_sparse` (**resolved**) — and **no `raw_n_sparse`**, so K-C-N13's signal is not observable today (§10 mandates the additive field) |
| 6 | `retrieve.py:496-534, :597-598` | `sparse_ranking` is the dedup'd union of per-layer `bm25_search` calls; `cap = candidate_k * len(target_layers)`; `raw_n_sparse = len(sparse_ranking)` — coherent **only** under the per-layer loop Option A replaces |

Kupo's own three confirmations (`git` absent from the container; the shipped fixture's derived
union is `['Z']` at every floor; `fusion_gate.py @ 56c8510` vs `graph.py @ cab9b73`) are
**treated as settled and not re-derived**.

---

## 1. Findings ledger — amend-03

| id | disposition | where discharged |
|---|---|---|
| **K-C1** — AC-313 byte-freezes `run_floor_probe`'s docstring, which carries a **second copy** of the stale pre-#41 claim AC-359 mandates correcting; the same amendment both mandates and forbids the edit | **ACCEPTED-AS-FILED** | §3; AC-313 (docstring-stripped body pin + whole-file canonical identity), AC-359 (**both** sites) |
| **K-C2** — AC-313 part 2 and AC-372 part 2 run `git` **inside the container**, where `shutil.which('git')` is `None`; `check=True` ⇒ guaranteed false red | **ACCEPTED-AS-FILED** | §4; AC-313 part 2 and AC-372 part 2 moved to the host |
| **K-C3** — AC-357's positive control cannot emit `true` on the shipped fixture (all three competitors share one phantom); its red is misrouted to "probe defect", and S-14 then forbids recording any `channel_live` | **ACCEPTED-AS-FILED, and the finding is STRONGER than filed** | §5; AC-357 rebuilt on W-G-FLOOR's own distinct-phantom fixture; AC-374 mechanises the structural finding; the routing table now has **three** branches, not two |
| **K-C4** — AC-322 part 1 reads `floor-7seed-aggregate.json`, which no step produces (K-B8's class, recurred) | **ACCEPTED-AS-FILED** | §6; the aggregate is produced by a named module symbol and renamed `floor-seed-aggregate.json` |
| **K-C5** — AC-358 controls a classifier AC-322 does not use (AC-322 computes disjointness in jq) | **ACCEPTED-AS-FILED** | §6; the aggregate **calls** `classify_disjoint`, AC-322 asserts the classifier's verdict **and** an independent jq recomputation, and requires them to agree |
| **K-C6** — the K-B15 remedy has no freshness guarantee: a gate that crashes before `emit` leaves the previous run's artifact, `git status` stays clean, and §A.4 item 3 says "no host-side `rm` is ever needed" | **ACCEPTED-AS-FILED — the most dangerous of the six** | §2 **global rule (g)** (delete-before-run + `&&` chain + run nonce + tree sha, asserted against the invoking run); §A.4 item 3's last sentence is **STRUCK**; **S-15** added |
| K-C-N1 .. K-C-N15 | all **ACCEPTED-AS-FILED** | §8 (per-finding table) |
| **K-N14 / K-C-N15** — the ESL record is still `status: proposed`, `acceptance_checks: []`, `has_code: false`, C3 fail `full: missing spec.yaml` | **ACCEPTED-AS-FILED; no longer deferred** | §11; **AC-380** |
| **FORGE D3 dense half** — D3 mandates the three-case shape for *both* arms; AC-355 pins the dense arm empty, so the dense half ships **ungated** | **ACCEPTED-AS-FILED** | §9.1; **AC-378** (dense mirror node) + a recorded fallback carrying D3's reversal condition |
| **maker's normative call (#44 top-up widens the head only)** — sound, but near-inert exactly where it matters (the strict-subset path) and **unmeasured** | **ACCEPTED-AS-FILED, then PARTIALLY OVERRULED BY FORGE (post-dispatch)** | §9.2 as amended by **§15**; **AC-379** is now FORGE's mandated node |
| **F-1 (late, coordinator)** — AC-306's field names (`ruling_quote`/`decided_at`/`decided_by`) do not exist in the `fence-amend.json` FORGE actually wrote (`ruling_text_quoted`/`ruled_at`/`ruled_by`); the criterion exits 1 on the real artifact | **NOT-DISCHARGED at first check; ACCEPTED-AS-FILED and fixed** | §16.1; AC-306 REPLACED and strengthened |
| **F-2 (late, maker-found during the §16.1 sweep)** — `red-evidence-wentry.json` is a top-level **array** named per-unit; AC-332 part 3 does `json.load(...)['gates']` and raises `TypeError` on it | **ACCEPTED-AS-FILED** | §16.2; shard convention + mandatory consolidation step; AC-332 REPLACED |
| **F-3 (late, FORGE)** — head-only composition ships `sparse_topup.fired: true` with structurally absent recovery on the strict-subset path (the #36 F-V3 defect as designed behaviour) | **RULED-BY-FORGE (fence-amend, composition_ruling)** | §15; per-fetch widen rule, AC-348 path-scoped, **AC-379** mandated, W-45 scope extended |

Running totals after `amend-03`: **64 distinct findings** (26 blocking `K-B1..K-B18` + `K-C1..K-C6`
+ `F-1`/`F-2`, 38 non-blocking `K-N1..K-N22` + `K-C-N1..K-C-N15` + `F-3`) — **52 ACCEPTED-AS-FILED,
12 RULED-BY-FORGE, 0 SUPERSEDED, 0 REJECTED-WITH-REASON.**

**Honest note on the discharge audit:** `F-1` means **AC-306 was NOT-DISCHARGED at first check.**
`amend-01` §B.1 gave W-HOP the artifact and declared K-B8 closed; the artifact then arrived with
different key names and AC-306 exited 1 on it. K-B8's species — *a criterion naming a field no
step produces* — has now recurred **four** times (AC-306 here, AC-322's aggregate at K-C4,
AC-345's `.txt`/`.json` at K-C-N4, and AC-332's `red-evidence` shape at F-2). §16.3 states the
structural cause and the standing rule that replaces case-by-case patching.

---

## 2. TWO NEW GLOBAL RULES — standing equal to (a)-(f)

### 2.1 Rule (g) — ARTIFACT FRESHNESS (K-C6)

> **(g) No criterion may read a gate artifact it did not just cause to be written.**
> Every artifact-producing command block is **one `&&` chain** that (1) deletes the artifact,
> (2) mints a run nonce and reads the tree sha **on the host**, (3) runs the emit with both
> passed in as environment, and (4) `jq`s the file with the nonce and tree sha **asserted
> against the invoking run**. A gate that crashes before `emit` therefore leaves **no** file,
> and a file left by any earlier run **fails the nonce compare**.

Mechanics, binding on every gate module and every criterion in this campaign:

1. **`emit` stamps provenance it cannot invent.** `emit(result, out)` adds
   `run_nonce = os.environ["CRYSTALIUM_GATE_NONCE"]` and
   `tree_sha = os.environ["CRYSTALIUM_TREE_SHA"]` to the emitted object, by **direct
   subscript** — a missing variable raises `KeyError` and the emit fails loudly. **No default,
   no `.get`, no fallback.** (Fail-open here would reintroduce exactly the hole this rule
   closes; this repo's own "fail-open hides dead kernels" scar is the precedent.)
2. **`tree_sha` is passed IN, never self-derived.** `git` does not exist in the container
   (K-C2). The host computes it once per chain.
3. **Canonical single-artifact form:**
   ```
   cd MAIN && NONCE="$(python3 -c 'import uuid; print(uuid.uuid4())')" && TREE="$(git rev-parse HEAD)" && rm -f evals/results/<name>.json && docker compose run --rm -e CRYSTALIUM_GATE_NONCE="$NONCE" -e CRYSTALIUM_TREE_SHA="$TREE" crystalium /app/.venv/bin/python -c "import evals.<mod> as m; m.emit(m.run(), '/app/evals/results/<name>.json')" && jq -e --arg n "$NONCE" --arg t "$TREE" '(type == "object") and (.run_nonce == $n) and (.tree_sha == $t) and <predicate>' evals/results/<name>.json
   ```
   The `&&` between the emit and the `jq` is Kupo's fix (iii): **the emit's exit becomes
   load-bearing**. The `rm -f` is fix (ii). The nonce is fix (i). All three, not one.
4. **Seeded loops: one nonce for the whole family.** `rm -f` globs the whole family
   (`evals/results/<family>-*.json`) before the loop; every spawn in the loop carries the
   **same** `CRYSTALIUM_GATE_NONCE`; the aggregate asserts `all(.seeds[]; .run_nonce == $n)`.
   A mid-loop abort therefore cannot be papered over by seeds left from an earlier run — the
   exact hole Kupo names, closed at the row level rather than the file level.
5. **The aggregate is itself an emitted artifact** carrying the same nonce, and is produced by
   a named module symbol (never by an ad-hoc `jq -s` whose provenance nothing checks).
6. **`spec.amend-01.md` §A.4 item 3's final sentence — *"so no host-side `rm` is ever
   needed"* — is STRUCK.** It institutionalised the stale read. Replacement text:
   *"Files are root-owned on the host; the container overwrites them freely. A host-side
   `rm -f` before every emit is MANDATORY (rule (g)); if it fails, the chain fails."*
7. **Exit-code vocabulary (rule (a)) is unchanged and extended by one:** a `jq` exit 1 whose
   **only** failing conjunct is `.run_nonce` or `.tree_sha` is a **STALE READ** (S-15), not a
   gate result. The triage command is mandatory before any such red is recorded.

### 2.2 Rule (h) — DETACHED-CHECKOUT HYGIENE (K-C-N8)

> **(h) Any criterion that checks out a ref other than the tree it was invoked on MUST
> (i) refuse to run on a dirty tree, (ii) record the original ref before moving,
> (iii) restore it unconditionally — including on failure — and (iv) assert the restore
> happened before reporting PASS.**

Canonical form:
```
cd MAIN && test -z "$(git status --porcelain)" && ORIG="$(git rev-parse HEAD)" && git checkout --detach <sha> && <command> ; RC=$? ; git checkout --detach "$ORIG" && test "$(git rev-parse HEAD)" = "$ORIG" && test "$RC" = "0"
```
The `;` before `RC=$?` is deliberate: the restore runs **whether or not the command
succeeded**. A criterion that leaves the tree at a foreign ref poisons every criterion after
it — and AC-345 part (ii), which the plan runs immediately afterwards, was the concrete
casualty Kupo found.

Applies to: **AC-345 (i) and (ii), AC-361**, and any red-check that moves the tree.

---

## 3. K-C1 — the freeze/correct collision, resolved so the licensing is COHERENT

The defect, stated exactly: `amend-02` §4 mandated correcting the pre-#41 claim, pinned
`inspect.getsource(run_floor_probe)` — **which includes the docstring** — and read only
`m.__doc__` in AC-359. Net effect as specified: AC-359 corrects one copy of the claim, AC-313
fails if you correct the other, and the campaign ships a file that contradicts itself 200 lines
apart. **A single amendment may not both mandate and forbid the same edit.**

**Resolution — freeze what no criterion is licensed to change; assert content where one is.**

| symbol | frozen form | sha256 | may it change? |
|---|---|---|---|
| `_crystal` | **full source** (`inspect.getsource`) | `6fa658f431c97b759824408cb5af0f3a98f851dd46c089607c649a39f1930ded` | **no** |
| `_build_fixture` | **full source** | `66d3e9a7ea3bb8b1830c5d5ea3de7c8f70afef7a098b4a38069677ef6d6b62d4` | **no** |
| `run_floor_probe` | **body only** — the leading docstring statement removed by AST | **`9b371898fdfc1a46966234589fa5d6a9c41248a4496f36f6abbcaa96f4bb1519`** | **body no; docstring YES** (AC-359 mandates it) |
| `_FILLER_COUNT` | value | `12` | **no** (vigil F-V4's cardinality fix) |
| `_QUERY` | value | `'plarnix threxil vandomere signature'` | **no** |
| module docstring | — | — | **yes** — the #48 correction (AC-359) |
| everything else in the file | **whole-file canonical identity** (AC-313 part 2) | — | only the `cross_layer` -> `sparse_arm_per_layer_probe` rename |

`run_floor_probe`'s body is two statements
(`os.makedirs(...)` / `return run_arm(...)`); the docstring-stripped hash was **computed and
cross-checked on two interpreters** during this pass (host 3.14.6, container 3.12.13 — byte
identical), so the pin does not smuggle in an interpreter dependency.

**AC-313 part 2 is rebuilt as a whole-file canonical-identity check** rather than a line
filter (this also discharges K-C-N9). Canonicalisation, applied to **both** the `b7f1a47` blob
and the working tree:

1. replace the module docstring with the literal token `<<MODULE_DOCSTRING>>`;
2. replace `run_floor_probe`'s docstring with `<<RUN_FLOOR_PROBE_DOCSTRING>>`;
3. rewrite `sparse_arm_per_layer_probe` -> `cross_layer` (the rename's inverse);
4. require the two results to be **byte-identical**.

The only changes that survive canonicalisation are the two licensed docstrings and the
licensed rename. **Everything else — including a one-character edit hidden on a line that
happens to contain the word `cross_layer`, which `amend-02`'s substring filter exempted —
fails.** Verified by execution this pass (measurement 3 above).

**AC-359 covers BOTH sites**, `m.__doc__` and `m.run_floor_probe.__doc__`, with identical
assertions, and each site must retain its own superseded claim (dated, never deleted). The
mechanism-name assertion accepts either spelling the tree actually uses (`single-seed cap` in
the module docstring, `single-successful-seed cap` in `run_floor_probe`'s) — verified present
at both today, so that conjunct is a genuine anti-deletion guard rather than a new demand.

**Ownership is unchanged:** W-G-XL owns the bytes of both docstrings (its grant is extended
from `:72-92` + `:104-106` to *"the module docstring and `run_floor_probe`'s docstring"*);
W-G-FLOOR owns the **claim** and cites it in #48's closing comment; W-G-FLOOR's diff still
contains **no `evals/fusion_gate.py` hunk at all** (FORGE D5's byte-untouched clause holds).

---

## 4. K-C2 — `git` runs on the HOST, everywhere, without exception

`Dockerfile:7` is `FROM python:3.12-slim`; the only package install is `curl ca-certificates`.
Kupo measured `shutil.which('git') -> None`. `subprocess.run([...], check=True)` on a missing
binary raises `FileNotFoundError` ⇒ non-zero exit ⇒ **RED for a reason unrelated to the
defect**, on W-G-XL's freeze guard (AC-313) and on #47's disposition guard (AC-372).

**Normative, campaign-wide:** *no criterion runs `git` inside a container.* Every other
git-using criterion in this plan (AC-324, AC-331, AC-341, AC-353, AC-363) already runs on the
host; these two were the exceptions and are corrected. Both become **host `python3` +
stdlib-only** commands (`ast`, `difflib`, `subprocess`) that import nothing from the package,
so the container-only rule (which exists to pin the *package's* runtime) is not weakened. Where
a criterion needs both — a container-side runtime read and a host-side git read — it is split
into two parts, as AC-313 now is.

---

## 5. K-C3 — #48 REFRAMED: the floor's derived-membership channel is STRUCTURALLY absent, and that is EVIDENCE

`CHANGE/issue-48-mechanism-note.md` (independently verified) establishes something **stronger
than `amend-02` assumed**, and it changes what the plan is allowed to conclude.

### 5.1 The mechanism (supersedes `amend-02` §3.5's probabilistic framing)

`evals/fusion_gate.py:172-177` gives `N1`, `N2` and `N3` the **same** destination `Z`,
deliberately. `retrieve.py:562` is `fetch_width = max(k, FETCH_WIDTH_FLOOR)`, and `N1` is
deterministically `dense_ranking[0]`. Therefore **every floor >= 1 seeds `N1`**, and the derived
union is `{Z}` at every floor — measured `['Z']` at floors 2, 10 and 1000.

The pre-#41 channel was **not a membership channel. It was an ABORT channel**: anomaly A's
single-successful-seed cap expanded exactly one seed, so the outcome turned on whether
hash-order picked an edge-bearing competitor (`{Z: 0.5}`) or an edgeless filler (`{}`, walk
aborts). The floor changed the slice contents and therefore the odds of that pick — which is
why the divergence was **one seed out of fourteen**, not a systematic difference. **#41 deleted
the mechanism** (`graph.py:215-230` loops every seed; `:305` sorts the frontier), so no lottery
remains and no membership channel ever existed to replace it.

**Consequence:** `spec.md` §4 #48's prediction is confirmed **structurally and
deterministically**, not probabilistically. There is **no seed and no `PYTHONHASHSEED`** at
which the shipped fixture can exhibit the channel post-#41. `amend-02` §3.5's *"most likely
outcome"* is superseded by *"the only possible outcome on this fixture, by construction"*.

### 5.2 The positive control moves to W-G-FLOOR's own fixture (AC-357, REPLACED AGAIN)

`amend-02` §3.2's control (`floor=2` vs `floor=1000` on the **shipped** fixture) is
**unbuildable** — Kupo measured `DERIVED_UNION=['Z']` at both — and `_build_fixture` is
byte-frozen, so it cannot be repaired there. Per Kupo, the control moves to the fixture
W-G-FLOOR **owns and may design**, in `evals/floor_sensitivity_gate.py`:

**Normative control-fixture construction — DISTINCT PHANTOMS PER COMPETITOR.**
`c1 -> z1`, `c2 -> z2`, `c3 -> z3` (ids renamed so every competitor sorts **after** `target`,
per `amend-01` §B.7.4's tie-break-neutrality, which is safe because this is a new file).
`c1` sits at dense rank 1 and `c2`, `c3` outside the low floor's slice. Then
`dense_ranking[:2]` reaches only `z1` while `[:1000]` reaches `{z1, z2, z3}`: **the derived
union differs across the floor boundary by construction**, independent of hash order, which is
exactly the property the shipped fixture lacks. `amend-01` §B.7.4's *"the phantom, once
discovered, earns a derived vote sufficient to demote `target`"* is retained and extended:
**one phantom per edge-bearing competitor, never a shared one.**

The control asserts, on that fixture: `low_derived` non-empty, `high_derived` a **proper
superset** of `low_derived`, `channel_live == true`, and `self_check_ok` on both halves. It
additionally asserts the fixture's own premise **read off the graph at runtime** — the phantom
targets are distinct and number at least 3 — so the control cannot be run against a
same-phantom fixture and silently mean nothing.

### 5.3 The routing fix — THREE branches, not two (this is the part that burned the STOP)

`verification-plan.amend-02.md` §2.1 routed **every** red to *"the probe is not instrumented …
a probe defect (S-13 step 1) … fix the probe and re-run"*, and S-14 then forbade recording any
`channel_live`. On the shipped fixture that sends the implementer to debug a
correctly-instrumented probe and spends the one-cycle redesign budget on a misdiagnosis.
**Replacement routing table (supersedes `amend-02` §3.4 and `verification-plan.amend-02.md`
§2.3):**

| observation | class | licensed action |
|---|---|---|
| **AC-357 RED on W-G-FLOOR's own distinct-phantom fixture** | **PROBE OR FIXTURE DEFECT** | S-13 step 1. The instrument cannot see a difference that exists by construction. Fix and re-run. **No `channel_live` recordable** (S-14). |
| **AC-357 GREEN, and the shipped fixture shows no floor difference** (AC-374 green, AC-321 `channel_live == false`) | **EVIDENCE — the structural finding** | This is `issue-48-mechanism-note.md`'s result, **not** a probe defect. Record it, cite the note, route to **S-5 -> S-13 class (c)**: retire AC-138/AC-139 with the mechanism note; close #48 **retired**, not discharged. |
| **AC-357 GREEN, and the shipped fixture DOES show a floor difference** (`channel_live == true`) | **REFUTATION** | `spec.md` §4 #48's prediction and `issue-48-mechanism-note.md` are both wrong; the note is corrected, not quietly dropped, and the tie-break explanation is carried instead. |
| AC-357 absent | **UNVALIDATED** | S-14. Not evidence. |

**The middle row is the one `amend-02` could not express, and it is the expected outcome.**

### 5.4 The structural finding is MECHANISED, not asserted in prose (new AC-374)

A mechanism note that only a human reads is the same species of artifact as the pre-#41 claim
this campaign exists to correct. **AC-374** makes it machine-checked: a module symbol builds
`_build_fixture`'s stores (imported, never edited), reads the **actual edge set off the
graph**, and captures the derived union at floors {2, 10, 1000} in one process. It asserts
`distinct_phantom_count == 1`, three edge sources `["N1","N2","N3"]`, and one distinct derived
union across all three floors.

AC-374 is green today and reddens the moment the shipped fixture gains distinct phantoms — at
which point #48's framing must be redone rather than inherited. That is the whole point: the
claim now has an owner that fails.

### 5.5 Rule (f) for VP-M1 — what the control does and does NOT discharge

Stated plainly, because the split is the honest part:

- **Instrument half — DISCHARGED.** The same probe symbol, the same code path and the same
  comparison emit `true` on the distinct-phantom fixture. A `false` from it is therefore a
  statement about the *fixture*, not about the instrument.
- **Fixture half — NOT DISCHARGEABLE, and proven so.** No control can make the shipped fixture
  emit `true`: `{Z}` at every floor is a theorem about its topology. `amend-02` §3.6 recorded
  this shape for AC-322 as an open empirical question; for VP-M1 it is now **closed by
  proof**, which is a stronger statement and a better outcome — the impossibility is the
  evidence.

`S-14` is amended accordingly: a `channel_live == false` is not evidence when the **instrument**
is uncontrolled; it **is** evidence when the instrument is controlled and the fixture is
provably incapable, provided the proof is the artifact AC-374 emits.

---

## 6. K-C4 and K-C5 — the aggregate exists, and the classifier is the instrument AC-322 actually uses

**K-C4.** `floor-7seed-aggregate.json` had exactly one mention in the whole change folder: the
criterion that reads it. Two corrections:

1. the artifact is renamed **`floor-seed-aggregate.json`** (the seed count belongs in the file,
   not in the filename — `amend-02` hard-coded `7` into a name a 14-seed run would falsify);
2. it is **produced by a named module symbol**, `aggregate_seeds(seed_labels: list[str]) -> dict`,
   which reads the per-seed artifacts, verifies each row's `run_nonce` (rule (g)), and emits
   under rule (g)'s chain. `amend-02`'s bare *"the three commands are unchanged"* is superseded:
   the chain is now **four** commands (loop, unset run, aggregate, assert).

**K-C5.** AC-358 tested a *"pure disjointness classifier"* that AC-322 never consulted — AC-322
computed disjointness in `jq`. A control on an unused instrument is decoration; worse, the two
could disagree silently in either direction. **Both computations now ship and must agree:**

- `aggregate_seeds` calls **`classify_disjoint(low_ranks, high_ranks) -> dict`** — the pure,
  I/O-free classifier AC-358 tests (`retrieval_gate.py:91-114`'s precedent) — and writes
  `classifier: {symbol: "classify_disjoint", disjoint: <bool>, low_set: [...], high_set: [...]}`;
- **AC-322 asserts three things**: `classifier.disjoint == true` (the gate), a jq recomputation
  of disjointness from the per-seed rows, and **`classifier.disjoint == <the jq
  recomputation>`** (the cross-check).

Their **disagreement** is a distinct class from their agreeing on `false`, and the criterion
says so: disagreement is an **instrument defect** (S-13 step 1), never an S-5 event. A mandatory
triage command prints which conjunct failed, so the two are never conflated at the point where
the disposition is chosen.

---

## 7. K-C6 — why this one was the most dangerous

Recorded rather than fixed-and-forgotten, because the reasoning generalises. The `amend-01`
K-B15 remedy traded a **false red** (a parse error, loud) for a **false green** (a stale read,
silent) and did not notice, because both were evaluated against the same question — *"does the
criterion parse the gate's output?"* — instead of *"what does this criterion do when the gate
does not run?"*. The gitignore that made the artifacts convenient is the same gitignore that
made a stale one invisible to `git status`, and the amendment recorded that as a **feature**.

`vp-m2-gxl-red.json` is W-45's entry gate. Under the un-amended convention, a G-XL run that
crashed after an edit would have left the *previous, green* artifact in place and W-45 would
have started on it. Rule (g) is written as a **global rule** rather than five criterion patches
precisely because the convention is what the units copy — and the unit that copies it has not
been written yet.

---

## 8. Non-blocking findings — dispositions

| id | disposition |
|---|---|
| **K-C-N1** AC-321's `positive_control` is a bare boolean (exit 0 on a fabricated control with no derived arrays) | **FIXED.** AC-321 now asserts the control's **substance**: both derived arrays present and non-empty, `low != high`, `low ⊂ high`, `self_check_ok` on both halves, the distinct-phantom premise, and the control's `run_nonce` equal to the invoking run's. |
| **K-C-N2** the rule-(f) audit table has a **direction error** on AC-317 (the cited control produces the negative), and the same inversion on the AC-310 and AC-314 rows | **FIXED, and the rule is sharpened.** §8.1 rewrites the table with explicit *what routes* / *required opposite* / *control form* columns, and adds **AC-375** — the wide-band responsiveness control (`w_derived ∈ {0.5, 1.0, 100.0}`, >= 2 distinct outcomes). A 200x weight swing producing one outcome indicts the fixture, not the weights. |
| **K-C-N3** AC-332 part 3 has no `cd` (K-N18 recurring) | **FIXED, and swept.** AC-332 part 3 gains the `cd`; **every** command block in `spec.criteria.amend-01/02/03.md` was swept mechanically this pass for bare relative paths — AC-332 part 3 was the only remaining instance. Convention restated: **every path in every command block is absolute, or the block opens with `cd <absolute>`.** |
| **K-C-N4** `ac345-prefix-evidence` is `.txt` in the spec and `.json` in the criterion | **FIXED.** `.json` is normative (the criterion `jq`s `.commit1_sha`); `spec.amend-01.md` §B.4.4's `.txt` is **struck**. Schema pinned in §8.2. |
| **K-C-N5** three names for one probe (`vp_m1_probe` / `vp_m1_seed` / `vp_m1_control`), only the first defined, none invoked | **FIXED.** ONE probe symbol — FORGE D5's ruled `vp_m1_probe` — and exactly ONE caller, `vp_m1_pair`. `vp_m1_seed` and `vp_m1_control` are **deleted from the plan**. §8.3 states the two bounded signature extensions and why a pair-caller is unavoidable. |
| **K-C-N6** AC-317's `weight_readback == .weight` cannot detect the tautology it forbids | **FIXED.** **AC-376** puts the pin where AC-346 puts its equivalent — **inside a test body**, reading `fusion_weight_derived` off an `Aetheryte` the test built itself via the module's `build_aetheryte(w_derived=…)` factory. The prose rule becomes a node. |
| **K-C-N7** AC-345 part (ii) exits 0 on PASS as well as XFAIL | **FIXED.** `-q --tb=no -rX` plus a positive `grep -qE '[0-9]+ xfailed'` and a rule-(e)-shaped `passed`-count-is-zero guard. |
| **K-C-N8** AC-345(i)/AC-361 checkout with no restore and no dirty-tree guard | **FIXED** by **global rule (h)** (§2.2), applied to AC-345 (i) and (ii) and AC-361. |
| **K-C-N9** AC-313 part 2's residual filter is substring-based over whole diff lines | **FIXED** by §3's whole-file canonicalisation — no filter, no exemption, byte-identity after two docstring redactions and the rename's inverse. Verified this pass to reject an edit hidden behind a `cross_layer` comment. |
| **K-C-N10** `vp-m2-gxl-red.json`'s `sparse_ranking` has no specified provenance | **FIXED.** §8.4: it comes from a **recording spy on `relational.bm25_search`** (D5's own pattern, reused), never from a re-issued query, and carries a self-check binding `len(spy_union) == explain.fusion.arm_sizes.sparse`. Asserted by AC-312. |
| **K-C-N11** AC-316 may control a patch that never happens | **FIXED.** Recorded normatively: **the corpus-scaling gate does NOT patch `FETCH_WIDTH_FLOOR`** (it varies `M`), so a leak guard there is vacuous. AC-316 is **re-pointed** at `floor_sensitivity_gate.vp_m1_probe`, which does patch it (`try/finally`, `amend-01` §B.7.2 step 4), and gains an anti-vacuity conjunct: the probe must report the patched value **read back during the run**. |
| **K-C-N12** AC-305 still cannot fail on K-B16's defect | **FIXED.** AC-305 gains **two** normative nodes, of which the second is the one that discriminates: `test_liveness_measured_on_populated_edgeless_graph` — a rig written `all_edges() == 0` (always `False`) can never conclude "edgeless" and therefore cannot report `verdict == "measured"`. |
| **K-C-N13** §B.3.2's `raw_n_sparse` is not what `retrieve.py:598` computes | **FIXED, with a correction to the finding's stated direction.** §10 re-derives it and adds **AC-377**. |
| **K-C-N14** AC-350 omits the T3-variant's True branch | **FIXED.** AC-350 collects **four** cases; the T3-variant True branch (`{}`) is asserted **with** the §A.3 liveness form (`node_count() == 2`, `len(all_edges()) == 1`) so an empty result from a dead store cannot pass for an empty result from correct exclusion. |
| **K-C-N15** the ESL record is non-conformant right now | **FIXED** — §11, **AC-380**. |

### 8.1 Rule-(f) audit table — REPLACED (supersedes `amend-02` §2)

Rule (f) is restated with its two admissible forms, because the direction error came from
collapsing them:

> **Form 1 (opposite-demonstration).** A named control shows the instrument emitting the
> outcome **opposite** to the one that routes a disposition.
> **Form 2 (responsiveness).** The same instrument emits **>= 2 distinct outcomes** across a
> controlled variation of a known input. Admissible only where Form 1 would be circular
> (i.e. where the opposite outcome *is* the gate passing).

| measurement | outcome that ROUTES | required opposite | control | form | status |
|---|---|---|---|---|---|
| **VP-M1 `channel_live == false`** | #48's carried claim + fixture design | `channel_live == true` | **AC-357** on the distinct-phantom fixture (**not** the shipped one — it is provably incapable, and AC-374 proves it) | 1 | **CLOSED at the instrument; provably unattainable at the fixture (§5.5)** |
| **AC-322 `disjoint == false`** | S-5 -> D9 class (c) | `disjoint == true` | **AC-358** on `classify_disjoint`, now the instrument AC-322 consumes (K-C5) | 1 (instrument) | **CLOSED at the instrument; fixture half is S-5's trigger** |
| **AC-317 `< 2 distinct outcomes`** | #55 degeneracy finding | **>= 2 distinct outcomes on a wide band** | **AC-375** (`w_derived ∈ {0.5, 1.0, 100.0}`) — *`amend-02` cited D8's edge-severing perturbation, which demonstrates the **negative**; that was a direction error* | 2 | **CLOSED by AC-375** |
| **AC-310 `target_rank == 0` with green liveness** | S-3 -> D9 class (a), cancel W-45 | the instrument must be shown able to report a rank **other than** the one it reports | **C-XL-2** (D8's checker perturbation: inflate a filler's TF ⇒ a different rank) — *not C-XL-1, which demonstrates rank 0, the routing value* | 2 | **CLOSED, control re-designated** |
| **AC-314 `planted_recovered == false`** | S-8 -> S-13 | `planted_recovered == true` | **AC-315** (small-corpus control recovers the plant) — direction is correct as filed; the `amend-02` row merely mislabelled the measurement column | 1 | **satisfied** |
| AC-352 `p1_recreated == false` | S-1, keep seed exclusion | `p1_recreated == true` | `w_derived = 100.0` in-fixture control (`config.py:296-298`) | 1 | satisfied (`amend-01`, K-N15) |
| **AC-379 `topup_recovered == 0` on the subset path** | *"the top-up is near-inert here"* | a recovery > 0 | **AC-379 case (b)** — target-layer-dominated corpus | 1 | **CLOSED by AC-379 (§9.2)** |
| **AC-377 `selectivity == 0.0`** | D3's censoring-semantics reversal | `selectivity > 0.0` | **AC-377 case (ii)** — uncensored global fetch on the same subset path | 1 | **CLOSED by AC-377 (§10)** |

### 8.2 `ac345-prefix-evidence.json` — schema pinned (K-C-N4)

`.txt` is struck. W-44 writes `CHANGE/ac345-prefix-evidence.json`:
`{commit1_sha, commit2_sha, node, recorded_at, recorded_by, prefix_summary}` — all strings,
`commit1_sha`/`commit2_sha` full 40-char SHAs. AC-345 (i) `jq -r '.commit1_sha'`s it under
rule (h), and fails on an empty or absent value rather than passing an empty argument to
`git checkout`.

### 8.3 One probe, one caller (K-C-N5)

**Deleted from the plan:** `vp_m1_seed`, `vp_m1_control`. **Normative surface in
`evals/floor_sensitivity_gate.py`:**

- `vp_m1_probe(*, floor: int, fixture: str = "shipped") -> dict` — FORGE D5's ruled symbol and
  signature, extended by **one keyword with a default**, so every D5-era call is unchanged.
  Returns `{floor, floor_applied_readback, derived, retrieved, target_rank, self_check_ok,
  fixture, fixture_phantom_targets}`. `derived` is the sorted union the walk actually returned,
  captured at the `graph_store` seam (D5); `floor_applied_readback` is
  `retrieve.FETCH_WIDTH_FLOOR` read **inside** the patched region (AC-316's anti-vacuity).
- `vp_m1_pair(*, seed_label: str, floor_low: int, floor_high: int, fixture: str) -> dict` —
  the **only** caller. Calls `vp_m1_probe` twice **in one process** and returns
  `{seed, floor_low, floor_high, fixture, fixture_phantom_targets, low: <probe dict>,
  high: <probe dict>, channel_live, probe_symbol: "vp_m1_probe", probe_calls: 2}`.

**Why a pair-caller is unavoidable (maker's call, flagged):** the two floors of a seed row must
be compared **within one process**. With `PYTHONHASHSEED` *unset* — mandatory under rule (d) —
hash randomisation differs per process, so a cross-process pair for the `unset` row would
compare two different randomisations and is not a measurement at all. Two spawns per seed is
therefore unsound, not merely expensive. This is a bounded extension of D5, recorded here
rather than absorbed silently.

Every emitted row carries `probe_symbol` and `probe_calls`, and AC-321/AC-357 assert them —
so "the control ran the same probe" is checked, not assumed.

### 8.4 `vp-m2-gxl-red.json` — `sparse_ranking` provenance (K-C-N10)

`explain` carries `arm_sizes` (sizes, not membership), so the gate must obtain the membership
some other way. **Normative:** a **recording spy on `relational.bm25_search`** — the same
recording-proxy pattern FORGE D5 mandates at the `graph_store` seam — capturing returned ids in
call order and de-duplicating in first-seen order, exactly as `retrieve.py:527-530` does.
**Re-issuing `bm25_search` after the fact is FORBIDDEN**: it is a re-implementation that can
diverge from what `recall` actually did, which is the precise risk D5's self-check exists to
close. Binding self-check, asserted by AC-312:
`len(sparse_ranking) == explain.fusion.arm_sizes.sparse`.

---

## 9. FORGE-ruling fidelity gaps

### 9.1 D3's dense half ships GATED (AC-378), with a recorded fallback

FORGE D3 mandates the three-case fetch shape for **both arms** — *"sparse shown; dense mirrors
it"* (`forge-rulings.md` §D3). `amend-01` §B.3.3 pins the dense arm **empty** in AC-355's
fixture on single-axis grounds (a `MagicMock` ignores `layer_filter`, so post-filtering it would
confound the sparse measurement). **Kupo is right that the rationale is sound and the response
was wrong:** the correct answer is a **second node**, not dropped coverage.

**New AC-378 — `test_subset_layer_dense_mirror_no_regression`**, in W-45's own
`test_retrieve_layer_merge.py`. The dense stub is a `side_effect` callable that **honours
`layer_filter`** (returns only rows of the requested layer; returns the global ordering when
`layer_filter is None`) — `vector.py:174-199` supports `layer_filter=None`, so the stub mirrors
the real contract rather than inventing one. Assertions mirror AC-355 on `dense_ranking`. It is
**RED on a naive global+post-filter dense implementation and GREEN only when the dense backstop
exists**. AC-355 keeps its empty-dense pin unchanged, so neither node confounds the other:
**two nodes, one axis each.**

**Fallback, recorded rather than discovered later.** If the `side_effect` stub cannot express
the contract without a real vector store, W-45 **records the dense half as ungated** in the #45
closing comment, naming **D3's reversal condition verbatim** — *"If
`test_subset_layer_recall_no_regression` cannot be made green without violating the
`bm25_search` fence, W-45 stops and returns to FORGE with the failing construction"* — and
returns to FORGE with the failing construction rather than shipping the ruling half-implemented
in silence. **S-13 step 5 governs the artifact either way:** a dense node that cannot fail is
deleted, not merged.

### 9.2 The #44 top-up's subset-path efficacy — SUPERSEDED BY §15

*(This section was written before FORGE ruled the W-HOP fence. It is retained for the audit
trail; **§15 governs.** What changed: Kupo judged the maker's head-only call *sound but
unmeasured*; FORGE reviewed the same question on the fence hop and **partially overruled it** —
upheld on the default and single-layer paths, overruled as the exclusive rule on the
strict-subset path. The gap Kupo identified is real and is now closed by a **ruled** node rather
than a maker-invented one.)*

Original text, superseded: the maker's normative call — *"#44's top-up widens the global head
call only, never the backstop"* — was recorded as standing, with a new maker-designed
characterisation node (`test_topup_subset_path_efficacy_characterised`) measuring its
near-inertness on the subset path. **That node is withdrawn** in favour of FORGE's mandated
`test_subset_status_topup_recovers_active_hits` (§15.3), which is strictly stronger: it does not
*characterise* the inertness, it **fails on it**.

## 10. §B.3.2 REPLACED — censoring semantics under Option A, re-derived (K-C-N13)

`amend-01` §B.3.2 declared: *"global paths (`_ALL_LAYERS`, strict subset): `cap` = the global
requested `k`; `raw_n_sparse` = the global raw row count."* **What the code computes is
different**, and W-45 must be told to change it rather than assumed to.

**What the code does at `b7f1a47`** (re-read this pass):
`sparse_ranking` is built by the per-layer loop at `:521-530` (dedup'd union, `k=candidate_k`
per layer); `:597` is `cap = candidate_k * len(target_layers)`; `:598` is
`raw_n_sparse = len(sparse_ranking)`; `:256` is `if raw_n_sparse == 0 or raw_n_sparse >= cap`.
Under **today's** per-layer loop these are coherent: `cap` is exactly the maximum
`sparse_ranking` could reach.

**Under Option A's strict-subset path they are not.** `sparse_ranking` becomes *post-filtered
head + backstop tail*, which is **not the fetch that produced the censoring signal**:

- leaving `:597` and `:598` as-is compares a post-filter-attrited count against a target-layer
  cap — the censoring verdict is then decided by **how much the post-filter dropped**, not by
  whether the fetch was truncated;
- changing `:597` to the global requested `k` while leaving `:598` alone (the reading Kupo
  describes) compares a post-filtered count (typically `<= candidate_k * len(target_layers)`)
  against `candidate_k * len(_ALL_LAYERS)` — which it can essentially never reach.

**Correction to the finding's stated direction** (the mechanism, not the conclusion): the
second case does not silently *disable the boost* — `:256-259` sets `selectivity = 0.0` **when
censored**, so a censoring test that never fires leaves the **ratio branch always live**. The
defect is therefore that the **censoring GUARD becomes inert** and the #38 selectivity boost is
applied to a fetch that **was** globally censored — precisely what C-7/DP-9 forbids
(`retrieve.py:230-237`). The finding is real and blocking; its direction is inverted, and it
matters because the two failure modes have opposite symptoms in `explain`.

**Normative replacement (W-45 owns it):**

1. **The censoring signal is a property of the fetch that produced the head.** W-45 captures,
   on the global paths, the row count the global `bm25_search` returned **before any
   post-filtering** (`n_sparse_signal`) and that call's requested `k`
   (`cap_signal = candidate_k * len(_ALL_LAYERS)`), and passes **those** to
   `resolve_sparse_weight` as `raw_n_sparse` and `cap`.
2. **Backstop rows never enter the censoring signal.** They come from different fetches. They
   do enter `sparse_ranking` for ranking, and they do enter `resolved_n_sparse` / `n_scoped`,
   whose population parity (DP-9) is unchanged.
3. **Single-layer path unchanged**: `cap = candidate_k`, signal = that call's row count.
   Byte-preserving.
4. **W-45 adds two additive `explain.fusion` fields** so the signal is observable at all:
   `raw_n_sparse` (the value actually passed to `resolve_sparse_weight`) and
   `sparse_fetch_shape ∈ {"global", "single-layer", "global+backstop"}`. Measured this pass:
   `explain.fusion` carries `n_sparse_cap`, `selectivity`, `w_sparse` and a **resolved**
   `n_sparse` — but no raw count, so K-C-N13 is currently **unobservable from outside**.
   Additive fields only; v2.1.0 is already a minor carrying additive `explain.fusion.sparse_topup`.

**New AC-377 asserts it, in both directions** (§8.1, rule (f) Form 1):
(i) a **censored** global fetch on a 2-layer subset ⇒ `selectivity == 0.0`, `w_sparse == 1.0`,
`n_sparse_cap == candidate_k * 4`, `raw_n_sparse == candidate_k * 4`,
`sparse_fetch_shape == "global+backstop"`; (ii) an **uncensored** one on the same path ⇒
`selectivity > 0.0` and `w_sparse > 1.0`. VP-M7 continues to *record* the per-path delta;
**AC-377 is the criterion that can fail on it**, which VP-M7 alone could not.

D3's reversal condition is carried unchanged: if the boost behaves pathologically under the
global cap, **cap semantics reopen — never the score-space merge.**

---

## 11. K-N14 — the ESL record itself (not deferred any further)

Re-measured by Kupo this pass via `mcp__tonberry__status`: `status: proposed`,
`acceptance_checks: []`, `has_code: false`, **C3 fail — `full: missing spec.yaml`**,
`drift_checked: false`. `amend-01` §D item 9 recorded it as a pre-tag obligation; Kupo
correctly refused to score that as "addressed". This repo's own precedent is decisive: the ECM
record sat `in_progress` for five releases behind 164 green tests, and the drift check that
never ran found **real** drift.

**Correct values, stated rather than gestured at:**

| field | now | correct, and when |
|---|---|---|
| `status` | `proposed` | **`in_progress`** at Wave 0 start; **`verified`** when the v2.1.0 exit gate closes with maker != checker recorded; **`archived`** after the last issue is closed. Never skipped forward. |
| `acceptance_checks` | `[]` | the **62** criteria in force after `amend-03`, each `{id, verify_method}` — the shape used by every archived `full`-tier record in this repo. |
| `spec.yaml` | **missing** (C3 fail) | **added**, the machine-readable companion the `full` tier requires: `change_id`, `esl_version: "1.1"`, `tier: full`, `revision: 4`, `maker`, `checker`, the amendment chain, `criteria_sha256`, `acceptance_checks`, `touchpoints.external`, and the STOP/reversal table. `spec_ref` continues to point at `spec.md` (the frozen head of the chain). |
| `has_code` | `false` | **stays `false`, and the reason is RECORDED, not absorbed.** |

**The cross-repo gating question, answered explicitly.** The change record lives in the
**nexus** (`/home/rynaro/workspace/oss/agents/eidolons`); every line of code it plans lands in
**crystalium** (`/home/rynaro/workspace/oss/agents/crystalium`), a different repository. ESL's
code-state gates (`has_code`, `drift_checked` against a declared scope) evaluate the repo the
record is in. They therefore **cannot observe this change's code at all**.

`has_code: false` is *literally accurate* for the nexus and *materially misleading* if left
bare — it reads as "no code", not "code, elsewhere, unobservable from here". **A false value
that happens to be true for the wrong reason is exactly the shape this campaign exists to
remove.** The skip is therefore recorded as a first-class artifact:

**`CHANGE/esl-cross-repo-skip.json`** (W-HOP owns it, Wave 0):
```json
{
  "record_repo": "/home/rynaro/workspace/oss/agents/eidolons",
  "code_repo":   "/home/rynaro/workspace/oss/agents/crystalium",
  "code_base_ref": "b7f1a477b4a0bda2c2ecd7c3383d036e316c5abc",
  "code_branches": ["feat/*-52", "feat/*-48", "feat/*-55", "feat/*-45", "feat/*-44", "feat/*-42"],
  "has_code_in_record_repo": false,
  "skipped_checks": [
    {"check": "C3.code_state", "reason": "code lands in crystalium; ESL code-state gates evaluate the record's own repo and cannot observe it", "compensating_control": "AC-353 / AC-363 / AC-324 run git against the crystalium tree directly, per-unit, on explicit branch refs"},
    {"check": "drift.declared_scope", "reason": "same", "compensating_control": "S-12's per-unit `comm -23` against the literal ownership file, run in crystalium (`ramza-drift --repo`)"}
  ],
  "recorded_at": "<ISO-8601>",
  "recorded_by": "ramza"
}
```

The skip is **declared with its compensating control**, so a reader can tell a gate that was
*not applicable* from a gate that was *not run*. **AC-380** asserts all of it, and is red today.

---

## 12. STOP-table deltas

| id | delta |
|---|---|
| **S-5** | Trigger unchanged. **Amended:** S-5's evidence may now include the **structural** finding (§5.1) — on the shipped fixture the derived union is floor-invariant **by topology**, not by sampling. A `channel_live == false` from a probe whose **instrument** control (AC-357, on the distinct-phantom fixture) is green **is** admissible evidence, provided AC-374's structural artifact accompanies it. `amend-02`'s *"most likely outcome"* is superseded by *"the only possible outcome on this fixture"*. |
| **S-13** | Unchanged. §5.3's three-branch routing determines **whether** step 1 (probe defect) is entered at all — the misrouting Kupo found spent the one-cycle budget before the ladder was reached. |
| **S-14** | **Amended.** A routing negative is unvalidated when its **instrument** is uncontrolled. It is **validated** when the instrument is controlled and the fixture is provably incapable of the positive, **provided that impossibility is itself an emitted artifact** (AC-374). Rule (f)'s Form-1/Form-2 split (§8.1) governs which control is required. |
| **NEW S-15 — STALE ARTIFACT** | **Trigger:** any criterion's `jq` fails **only** on `.run_nonce` or `.tree_sha`, or an artifact is read that the invoking chain did not write. **Action:** the result is **not a gate result** — not a red, not a green. Re-run the full rule-(g) chain. **Recording a stale read as a red is itself a finding**, symmetrically with rule (a)'s exit-2/5 clause. Not an S-13 event: the gate is not unfailable, it was **not run**. |

---

## 13. Criteria and verification-plan deltas produced by this amendment

Full text in `spec.criteria.amend-03.md` and `verification-plan.amend-03.md`:

- **REPLACED AGAIN (3):** AC-313 (K-C1/K-C2/K-C-N9), AC-321 (K-C-N1/rule (g)/one probe name),
  AC-357 (K-C3 — distinct-phantom fixture, three-branch routing).
- **REPLACED (9):** AC-305 (K-C-N12), AC-316 (K-C-N11), AC-322 (K-C4/K-C5), AC-345
  (K-C-N4/N7/N8), AC-350 (K-C-N14), AC-358 (K-C5), AC-359 (K-C1 — both sites), AC-361
  (K-C-N8), AC-372 (K-C2).
- **AMENDED (6):** AC-310, AC-312 (K-C-N10), AC-314, AC-317, AC-332 (K-C-N3), AC-352 — all six
  re-plumbed onto rule (g)'s chain; AC-312 gains the spy-provenance conjunct.
- **ADDED (7):** AC-374 (structural finding, mechanised), AC-375 (K-C-N2 wide-band control),
  AC-376 (K-C-N6 instance readback), AC-377 (K-C-N13 censoring signal), AC-378 (D3 dense
  mirror), AC-379 (#44 subset-path efficacy), AC-380 (ESL record).
- **Global rules (g) and (h)** added; `amend-01` §A.4 item 3 amended.
- **§B.3.2** replaced (§10); **§B.7.2/§B.7.4** amended (§5.2, §8.3); **§B.4.4** `.txt` struck.
- **STOP table:** S-5 and S-14 amended, **S-15** added.
- **Checklists:** v2.0.2 gains AC-374/375/376/380 and the rule-(g)/(h) audit lines; v2.1.0
  gains AC-377/378/379.

**55 criteria in force after `amend-02`; `amend-03` replaces 12, amends 6, adds 7 ⇒ 62 in
force.**

---

## 14. What this amendment does NOT resolve

Carried forward from `amend-01` §F and `amend-02` §5, plus:

1. **Whether the distinct-phantom control fixture behaves as derived.** The construction is
   sound on the post-#41 walk semantics (`graph.py:215-230`, `:305`) and the arithmetic is
   Kupo's own measurement inverted — but **it has not been executed**, because building it is
   W-G-FLOOR's work and this is a plan. AC-357 is the gate; if it is red on its own fixture,
   §5.3's first row applies and the redesign budget is spent on the right thing.
2. **AC-322's fixture half remains non-circularly uncontrollable.** Unchanged from `amend-02`
   §3.6 and correct as recorded.
3. **AC-379 case (b)'s magnitude is unmeasured.** It asserts `> 0`, not a number — a threshold
   would be an invented absolute (§0's "no absolute thresholds").
4. **Four load-bearing measurements are still unexecuted** (VP-M2, VP-M1-with-spy, AC-322
   disjointness, VP-M7's cap delta). Unchanged from both prior passes, and the verdict stays at
   **VALIDATE**, not AUTO_PROCEED.
5. **Whether `explain.fusion.raw_n_sparse` and `sparse_fetch_shape` are the right names.**
   They are additive and W-45 owns them; a rename before merge is not drift.

---

## 15. LATE INPUT — FORGE's W-HOP fence ruling (post-dispatch). GOVERNS over §9.2 and `amend-01` §B.4.2

`CHANGE/fence-amend.json` + `fence-amend.md` were written and validated **after this amendment
was dispatched**. The verdict is **ALLOW**: **S-10 does not fire**, and W-44's entry
precondition is satisfied on that gate. The ruling also decides a question this plan had left as
a maker's call, and decides it **against** the plan in part.

### 15.1 The composition ruling — head-only is UPHELD in part, OVERRULED in part

| path | ruling |
|---|---|
| default (`layers=None`) | **UPHELD.** One fetch, so head-only and locus-widening coincide. `amend-01` §B.4.2 stands **verbatim**. |
| single-layer | **UPHELD**, same reason. |
| **strict subset (`len(target_layers) >= 2`)** | **OVERRULED as the exclusive rule.** |

**Normative replacement rule (supersedes `amend-01` §B.4.2 on the subset path only):**

> **The top-up widens each fetch that is INDIVIDUALLY censored-and-dirty — head and/or
> per-layer backstop — at most once per fetch, and never a widen decided by another fetch's
> signal.**

That is **K-B13(c) applied per fetch**: the censoring test is a property of *the fetch*
(`retrieve.py:230-233`), so a per-fetch remedy is the same principle, not a departure from it —
the very ground on which Kupo judged head-only sound.

**Why head-only fails on the subset path** (FORGE's reason, recorded because it is the sharper
form of Kupo's point): the starvation **locus** is a deprecated-censored *per-layer backstop*
call, and head-only never widens it — a wider global head returns mostly excluded-layer rows the
post-filter discards. Head-only would therefore ship
`explain.fusion.sparse_topup.fired: true` while recovery is **structurally absent**. That is the
**#36 F-V3 counter-honesty defect** — a counter that stays truthful about work that produced
nothing — **this time as designed behaviour**, which is worse than as a bug.

The censoring signal feeding `resolve_sparse_weight` **remains the head's**, recomputed **only
when the head itself widens**. Backstop widens are coverage appendages and never touch the
signal. §10's re-derivation is unchanged and is now **confirmed by ruling**.

### 15.2 AC-348 becomes PATH-SCOPED (an open amendment of FORGE's own D3)

D3's *"<= 1 extra call"* was written before the per-fetch rule existed. Restated in D1's
terminal-branch shape — **each path an exact, separately-stated budget, never one number with a
caveat**:

| path | fetch-shape baseline (§B.3.1) | top-up budget | total `bm25_search` calls |
|---|---|---|---|
| default (`_ALL_LAYERS`) | 1 (global) | **<= 1** | **<= 2** |
| single-layer | 1 (filtered) | **<= 1** | **<= 2** |
| **strict subset, `L = len(target_layers)`** | `1 + backstop_count` (`backstop_count <= L`) | **<= 1 + L** | **<= 2 + L + backstop_count**, and `<= 2 + 2L` |

**This is an amendment of a binding FORGE ruling and is labelled as such**, on FORGE's own
instruction. The `<= 1` clause is **not relaxed** — it is *retained unchanged on the two paths
it was written for* and *replaced by an exact per-path bound on the path it cannot express*.
**Relaxing AC-348 or AC-355 to fit the implementation is explicitly forbidden** (§15.3's
fallback).

### 15.3 The MANDATED node — AC-379 (id assigned here, as the ruling requires)

FORGE states plainly that **as the plan stood, the strict-subset composition had no criterion
that could fail on it**: AC-346/AC-347 are default-path, AC-355 measures layer coverage, AC-348
counts calls only. **Until this node is assigned an id and green-checked into the plan, that
composition is UNMEASURED.** The id is assigned here.

**AC-379 — node name normative: `test_subset_status_topup_recovers_active_hits`**, in W-44's
`mcp-server/tests/test_sparse_status_topup.py`. Fixture regime, verbatim from the ruling: the
**K-N12 regime** — an excluded-layer-dominated **censored head**, a target-layer **backstop call
that is deprecated-censored above a planted active target**, `recall_active_only=True`.
**RED under head-only; GREEN only with the backstop-locus widen.**

The maker-designed `test_topup_subset_path_efficacy_characterised` (§9.2's original) is
**withdrawn** — it characterised the inertness; this one **fails on it**. Its
counter-honesty half survives as **AC-379 part 2**, because the ruling itself demands F-V3
discipline (*"every field derived from the fetches actually performed"*), and because a green
discriminating node with a lying counter is exactly the composition #36 was about.

**Part 2 asserts the counter against the calls, using only fields the ruling authorises:**
`explain.fusion.sparse_topup = {fired, widened_fetches: [{fetch, k_initial, k_final,
n_inactive_observed}]}` must match the **spy's observed `bm25_search` call sequence** exactly —
one `widened_fetches` entry per observed widened call, same locus, same `k_final`, with
`k_final == min(k_initial + n_inactive_observed, HARD_TOPUP_CEILING)` and
`fired == ((widened_fetches | length) > 0)`. **No invented field**: an earlier draft of this
criterion asserted a `recovered_in_target_layers` counter that the ruling does not authorise;
it is struck.

**Ruled fallback, recorded and not softened.** If the fixture cannot discriminate,
route to **S-13 with explicit subset-path SUPPRESSION** — the top-up is documented as inert on
strict subsets, with a follow-up filing. **Never ship the subset-path behaviour unmeasured, and
never relax AC-348 or AC-355 to fit.**

### 15.4 W-45's scope GROWS — per-fetch raw counts, captured where the fetches happen

The top-up's trigger is per-fetch (*"that fetch was censored (its raw row count >= its OWN
requested k) AND >= 1 row of its contribution fails `_is_active`"*), and
**`len(sparse_ranking)` is NOT the head's raw count on the subset path** (§10, K-C-N13, now
confirmed by ruling). **W-45 implements the capture; W-44 reads it.**

**`amend-01` §B.1's ownership table gains a W-45 delta:**

| unit | delta | why |
|---|---|---|
| **W-45** | additionally owns the **per-fetch raw-count capture** in `retrieve.py`: for every `bm25_search` call the recall path issues (global head and each per-layer backstop), the **row count that call returned** and the **`k` it requested**, recorded at the call site, plus the two additive `explain.fusion` fields (`raw_n_sparse`, `sparse_fetch_shape`) of §10 and a per-fetch `explain.fusion.fetches[]` array carrying `{fetch, k_requested, n_returned}`. | FORGE fence-amend `composition_ruling`; K-C-N13. The signal cannot be reconstructed after the fact from `sparse_ranking`, and reconstructing it is the K-C-N10 re-implementation risk in a second place. |

W-44 **reads** those counts and **never recomputes** them — a second derivation would be a
second definition, the exact defect the fence's single-`_is_active` clause exists to prevent.

### 15.5 The NINE breach conditions — verbatim, and binding

**Each requires a FRESH W-HOP before any code.** Reproduced exactly as ruled:

1. Any parameter added to `bm25_search` (`status_filter`, `include_inactive`, or any other), or any change to its SQL or signature — AC-349 red; W-HOP re-hop required BEFORE any code
2. Any new public method on `RelationalStore` or any storage class (status-aware search, widened-search helper, count variant)
3. Any status or temporal predicate entering SQL anywhere on the read path, including a "temporary" `WHERE status='active'`
4. A second status predicate, or any duplication/divergence of `_is_active`'s logic
5. Any edit to `layers/episodic.py:319` or to its call's semantics
6. Editing, weakening, or deleting the fence comment at `retrieve.py:605-615` or the echo at `retrieve.py:241-242`
7. More than one widen per fetch, any loop-until-clean refetching, or a widen of one fetch decided by a DIFFERENT fetch's censoring signal
8. The top-up issuing any additional `bm25_search` call when `recall_active_only` is False
9. The censoring recompute reading anything other than the fetch actually performed

**Mechanical coverage** — which criterion can fail on which breach, so this list is a gate and
not a wall poster:

| breach | criterion that reddens |
|---|---|
| 1 | **AC-349** (signature + SQL freeze, red-check live) |
| 2 | **AC-381** (new — no new public storage method, asserted by AST over the storage package's diff) |
| 3, 4 | **AC-381** parts 2 and 3 (no SQL status/temporal predicate added; exactly one `_is_active` definition) |
| 5 | **AC-381** part 4 (`layers/episodic.py` byte-identical) |
| 6 | **AC-381** part 5 (both fence comments byte-identical, extracted by anchor) |
| 7 | **AC-379** part 2 (`widened_fetches` must match the spy's call sequence: a second widen of one fetch, or a loop, appears as an extra entry or an unmatched call) + **AC-348**'s per-path exact bound |
| 8 | **AC-356** (flag-off inertness: zero additional `bm25_search` calls) |
| 9 | **AC-377** (§10 — the censoring signal is the fetch actually performed, both directions) |

**AC-381 is ADDED by this section** (the fence-breach guard). Without it, six of the nine
conditions had no mechanical detector at all — they were prose in an artifact the plan `jq`s for
a *verdict word*. A fence whose breaches are undetectable is the "gates are where defects hide"
pattern applied to a ruling.

### 15.6 What the fence ALLOW does NOT license

- It does not license **AC-306** to stay as written (§16.1) — the ALLOW is only observable
  through a criterion that can read the artifact.
- It does not license the **dense** half of D3 (§9.1 stands unchanged; **AC-378** is the answer).
- It does not license skipping the **reversal condition**: if the only green path for W-44
  requires a `bm25_search` parameter, a SQL change, a new storage method, or an unbounded
  refetch loop, **this ALLOW is void, S-10 fires, and #44 is re-filed rather than half-fixed**.
  Independently, if `Config.recall_active_only`'s default ever flips to `False`
  (`config.py:333`, or the env default at `config.py:437`), **D6's production-defect
  classification reverts to configuration-gated** — the fence verdict is unaffected. Both are
  carried into the release checklists.

---

## 16. LATE INPUT — artifact-shape reconciliation, and the standing rule that replaces it

### 16.1 AC-306 does not discharge against the artifact FORGE wrote (F-1)

Measured this pass, on the real file:

```
jq -e '… (.ruling_quote | type == "string") …' fence-amend.json   ->  false, EXIT=1
```

`amend-01`'s AC-306 asserts `ruling_quote` / `decided_at` / `decided_by`. The artifact ships
`ruling_text_quoted` / `ruled_at` / `ruled_by`. The `.verdict` conjunct matches; only the three
names fail.

**Decision (mine, as criteria owner): align the CRITERION to the artifact, and strengthen it
while doing so.** Grounds, stated so the choice is auditable rather than convenient:

1. AC-306 is a **shape check on a record the plan itself commissions**, not a gate on a defect
   in the target system. There is no behaviour whose absence it detects. Neither name is more
   correct; the artifact's names are, if anything, more precise (`ruling_text_quoted` says the
   string is a **quotation**, which is the property that matters).
2. Aligning it is therefore **not** "writing the gate to pass" — the discriminating question is
   *"does the amended criterion still fail on the failure it exists to catch?"*, and it does:
   a missing verdict, an empty quote, an absent decision timestamp, or an ALLOW with **no
   breach conditions** all still redden it.
3. The opposite choice — mandating a re-emit — would cost a FORGE round-trip to rename three
   keys in a record that is already correct, and would leave the *plan* as the thing that
   dictated a spelling. That is ceremony.

**AC-306 REPLACED, and made load-bearing.** It now additionally asserts what W-44 actually
depends on: `authorised_changes` and `breach_conditions` are **non-empty arrays**, and
`reversal_condition` and `composition_ruling` are **non-empty strings**. An `ALLOW` with an
empty `breach_conditions` array is a fence with no teeth and now **fails**. Verified this pass:
the amended predicate exits **0** on the shipped artifact, and the un-amended one exits **1**.

### 16.2 `red-evidence` is a per-unit ARRAY, and AC-332 part 3 crashes on it (F-2, maker-found)

Found during the sweep §16.1 mandated. `CHANGE/red-evidence-wentry.json` exists, written by the
W-ENTRY implementer. Measured:

- it is a **top-level array** of 2 entries, **not** `{gates: [...]}`;
- its per-entry schema is **exactly** the one this plan specified — `gate, axis,
  perturbation_patch, command, tree_sha, exit_code, output_tail, restore{command, exit_code}` —
  and it **validates** against AC-332's schema predicate (exit 0, verified);
- both entries name the **same** gate (`test_serve_stdio_handshake`) on two different axes,
  which is correct and good;
- **AC-332 part 3's `json.load(open('red-evidence.json'))['gates']` raises
  `TypeError: list indices must be integers or slices, not str`** on it, and the file it names
  does not exist at all.

**Reconciliation — the shards are the source of truth; the consolidated file is derived.**

1. **Normative shard convention:** maker-side red evidence is written **per unit** as
   `CHANGE/red-evidence-<unitslug>.json`, a **top-level array** of entries with the eight-key
   schema above. `red-evidence-wentry.json` is conformant as written and needs **no change** —
   the implementer got it right; the plan had not said it.
2. **Mandatory consolidation step** (per batch, before AC-332 runs), owned by the release unit:
   ```
   cd CHANGE && jq -s '{batch: "v2.0.2", gates: add}' red-evidence-w*.json > red-evidence.json
   ```
   The glob matches every shard and **cannot match the output** (`red-evidence.json` has no
   `-w`). Verified this pass: it produces `{gates: [...]}` with 2 rows, 1 distinct gate, from
   the single shard present today.
3. **AC-332 gains a part 0** that validates **every shard** against the eight-key schema and
   asserts `(.gates | length)` in the consolidated file **equals the sum of the shard lengths**
   — so a shard cannot be silently dropped from the anti-replay input, which would make the
   anti-replay check pass by having nothing to compare against.
4. Row counts: AC-332's `(.gates | length) == 5` applies to **`checker-redcheck.json`** (five
   gates, one checker perturbation each) and is unchanged. The **maker** side is deliberately
   unconstrained in row count — more axes are better — and is constrained only in **shape**.

### 16.3 The standing rule — K-B8's species has now recurred FOUR times

AC-306 (F-1), AC-322's aggregate (K-C4), AC-345's `.txt`/`.json` (K-C-N4) and AC-332's
`red-evidence` shape (F-2) are **one defect**: *a criterion that names an artifact, a filename
or a field that no step actually produces.* Patching them one at a time has now failed three
times in a row, so the patch is replaced by a rule.

> **Global rule (i) — PRODUCER-NAMED ARTIFACT CONTRACTS.** Every criterion that reads a file it
> did not just produce (rule (g)) MUST name, in the criterion text, **(1) the producing step,
> (2) the exact filename, and (3) the exact key names it asserts.** A criterion whose producer
> is "the maker" or "W-<unit>" without a named step or command is **not admissible**. When an
> artifact already exists on disk, the criterion is written **against the shipped keys**, and
> the check that it discharges is **run before the criterion is frozen**, not after.

**Producer audit — every `CHANGE/*.json` a criterion reads.** Done mechanically this pass; the
first three rows are the ones that were wrong.

| artifact | producer (named step) | keys asserted | status |
|---|---|---|---|
| `fence-amend.json` | W-HOP / **FORGE ruling, already written** | `verdict`, `ruling_text_quoted`, `ruled_at`, `ruled_by`, `authorised_changes`, `breach_conditions`, `reversal_condition`, `composition_ruling` | **FIXED (F-1)** — verified exit 0 against the shipped file |
| `red-evidence-<unit>.json` (shards) + `red-evidence.json` (consolidated) | per-unit maker red-check + **§16.2's `jq -s` consolidation step** | shard: 8 keys, top-level array; consolidated: `{batch, gates[]}` | **FIXED (F-2)** — shard verified exit 0 against the schema |
| `floor-seed-aggregate.json` | **`aggregate_seeds()`** in `evals/floor_sensitivity_gate.py`, rule-(g) chain | `run_nonce`, `tree_sha`, `seeds[]`, `seed_set`, `seed_set_covers_divergent_point`, `divergent_point_known`, `classifier{symbol,disjoint,low_set,high_set}` | **FIXED (K-C4/K-C5)** |
| `ac345-prefix-evidence.json` | W-44 commit-1 characterisation step (§8.2) | `commit1_sha`, `commit2_sha`, `node`, `recorded_at`, `recorded_by`, `prefix_summary` | **FIXED (K-C-N4)** — `.txt` struck |
| `vp-m1-floor-channel.json` | **`vp_m1_pair()` x14 + `aggregate_seeds`-shaped emit**, VP-M1 step 3 | `run_nonce`, `seeds[].{seed,low,high,run_nonce}`, `positive_control`, `channel_live`, `seed_set*` | **FIXED (K-C-N1/K-C-N5/rule (g))** — schema restated in VP §2.2 |
| `m1-positive-control.json` | **`vp_m1_pair(fixture='distinct_phantom')`**, VP-M1 step 1 | `low.derived`, `high.derived`, `channel_live`, `self_check_ok`, `fixture_phantom_targets`, `probe_symbol` | **NEW, specified with its producer** |
| `m1-shipped-fixture-topology.json` | **`shipped_fixture_topology()`**, AC-374 | `edge_sources`, `phantom_targets`, `distinct_phantom_count`, `derived_union_by_floor` | **NEW, specified with its producer** |
| `vp-m2-gxl-red.json` | `cross_layer_gate.run()` + the `cp` in VP §3.2 | `tree_sha`, `verdict`, `target_rank`, `expected_blocked_rank`, `sparse_ranking`, `liveness{…}` | **provenance FIXED (K-C-N10)**; `sparse_ranking` now spy-sourced |
| `checker-redcheck.json` / `checker-redcheck-v2.1.0.json` | the **checker's** red-check pass, per batch | `gates[].{gate,axis,perturbation_patch,command,tree_sha,exit_code,output_tail,restore}` | unchanged; same 8-key schema as the shards, so one schema governs both sides |
| `critic-v2.0.2.json` / `critic-v2.1.0.json` | the per-batch critic step (AC-333/AC-362) | `batch`, `author`, `checker`, `at`, `batch_started_at`, `artifacts_rebroken` | unchanged |
| `esl-cross-repo-skip.json` | **W-HOP, Wave 0** (§11) | `record_repo`, `code_repo`, `code_base_ref`, `has_code_in_record_repo`, `skipped_checks[]` | **NEW, specified with its producer** |

### 16.4 Self-attack — two defects found in THIS amendment's own surface, before freeze

Every new `jq` predicate in `spec.criteria.amend-03.md` was executed against positive and
negative fixtures during this pass (AC-306, AC-310+312, AC-317, AC-321, AC-322, AC-332, AC-357,
AC-374, AC-375, AC-380 — 44 cases, all behaving as specified, including the AC-322 triage
correctly separating `{classifier:true, recomputed:false}` from `{false, false}`). Two defects
in my own new surface were found that way and fixed before freeze:

1. **AC-332 part 0 could not fail on a bad shard.** `jq -e 'pred' a.json b.json` evaluates the
   filter **per input** and exits on the **last** output's truth value. Measured: a **bad** shard
   followed by a good one exits **0**. Fixed to `jq -s -e 'all(.[]; …)'`, and the constraint is
   lifted into rule (g) so no future criterion repeats it.
2. **AC-321 referenced `$CRYSTALIUM_GATE_NONCE`, a variable no chain exports.** The chains assign
   a shell-local `NONCE`. As written, `--arg n ""` would have compared an empty string against a
   uuid and reddened **every** run — a false red in the criterion that gates W-G-FLOOR's first
   task. Fixed, and rule (g) now states that a nonce covers **one measurement, not one command**,
   which is what makes `.positive_control.run_nonce == $n` satisfiable at all.

Recorded rather than silently corrected: the checker's finding was that *the amendments' own new
surface was the least-attacked surface in the plan*. Both defects are that finding, reproduced —
and both were in criteria written to fix it.

### 16.5 No rogue amend-03 artifacts

Checked as instructed: the change folder contains exactly one `amend-03` file at the time of
this section — `spec.amend-03.md`, written by this instance. No file authored by another RAMZA
instance was found, and nothing was merged from one.

---

## 17. Criteria delta — SUPERSEDES §13's index

§13's counts predate §15 and §16. Final delta for `amend-03`:

- **REPLACED AGAIN (3):** AC-313, AC-321, AC-357.
- **REPLACED (12):** AC-305, AC-306 **(F-1)**, AC-316, AC-322, AC-332 **(F-2)**, AC-345,
  AC-348 **(§15.2, path-scoped)**, AC-350, AC-358, AC-359, AC-361, AC-372.
- **AMENDED (6):** AC-310, AC-312, AC-314, AC-317, AC-352, AC-356 (§15.5 breach-8 cross-ref).
- **ADDED (8):** AC-374, AC-375, AC-376, AC-377, AC-378, **AC-379 (FORGE-mandated node)**,
  AC-380, **AC-381 (fence-breach guard)**.
- **Global rules (g), (h) and (i)** added.

**55 in force after `amend-02`; `amend-03` replaces 15, amends 6, adds 8 ⇒ 63 criteria in
force.**
