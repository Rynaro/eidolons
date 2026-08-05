# verification-plan — `crystalium-open-issues-sweep-50`

Companion to `spec.md` and `spec.criteria.md`. Answers three questions: **who verifies what**,
**what may run at the same time**, and **what aborts the campaign**.

## 0. Roles

| role | agent | may do | may NOT do |
|---|---|---|---|
| maker | `vivi` | implement each unit in its own worktree; run per-unit pytest; author PR bodies | run or interpret an eval-gate measurement as its own verification of record; edit `spec.criteria.md` |
| checker | `kupo` | independently replay every VERIFY line in `spec.criteria.md`; accept/reject each unit; own the pre-tag verify hop (ESL P0-9) | write or fix code in any unit it checks |
| orchestrator | the session driving the campaign | own **all** eval-gate measurement runs (W0, W0b, W0c, W1b, W3-measurement); own merge order; own the STOP calls | implement code; edit criteria without `ramza-freeze --amend --reason` |
| planner | RAMZA | this document | anything else (read-only, P0-1) |

Maker≠checker is mechanical (AC-263). A criterion "verified" by the same agent that wrote the code
it guards is not verified.

## 1. Verification order

```
W0 ─ W0b ─ W0c(control) ─→ W1 ─→ W1b ─→ ┬─ W2 ──────────────┐
   (orchestrator, serial)   (vivi)  (orch)│  (vivi)           │
                                          ├─ W3-code (vivi)   ├─→ W3-measurement ─→ W5
                                          └─ W4 (vivi)        │      (orchestrator)   (vivi+kupo)
                                                              ┘
```

Hard sequencing rules, each with the reason it exists:

1. **W0/W0b/W0c strictly first, on a clean tree at `56c8510`.** A baseline captured after a code
   change is not a baseline. Enforced by AC-206 and by the `git_sha` tag on every record (AC-205).
2. **W0c's positive control before any DP-2 number is believed.** The sweep harness must be shown
   able to turn 0.90 red at the pre-fix SHA (AC-204) before its 1.00 result at the post-fix SHA
   (AC-226) means anything. Running the control at the pre-fix SHA is what keeps it independent of
   #41's own effect on the cliff.
3. **W1's red-check before W1's green run.** AC-210 runs the new tests against stashed pre-fix
   `graph.py`. Order matters: a checker who sees only the green run cannot tell a gate from a
   tautology, and the current suite is green on the bug (27 passed, scout-verified).
4. **W1b before W2's neutrality diff, before W3's measurement, before W5.** W1b produces
   `eval-after.json`, which is the reference record for AC-235 and the evidence W5's CHANGELOG must
   cite.
5. **W2 rebased onto post-W1 `main` before its byte-identity run** (AC-235 precondition). The
   worktree starts at `56c8510`; diffing a pre-W1 tree against a post-W1 record measures two
   changes at once.
6. **W3-measurement after W1 has landed** — the deconfounded numbers must be taken on a store whose
   multi-seed expansion is real, otherwise the new baseline inherits the defect it is meant to
   outlive.
7. **W5 strictly last, and blocked on the W1b artefacts existing.** The release exists to record
   the measurements; it cannot precede them.

## 2. Concurrency contract

### 2.1 MUST be serialized — every eval-gate measurement

`python -m evals fusion-gate`, `python -m evals fusion-gate --floor …`,
`python -m evals retrieval-gate`, and the DP-2 sweep harness run **one at a time, campaign-wide**,
and are owned by the orchestrator. Reasons, in order of severity:

- **Measurement validity.** The C-2 protocol (`mcp-server/tests/test_fusion_gate.py:70-73`) compares
  distributions across `PYTHONHASHSEED` values. Two gates competing for CPU produce timing-coupled
  runs whose comparability is unestablished; the campaign's whole evidentiary basis is differential.
- **Model contention.** The retrieval gate needs the sentence-transformers model
  (`retrieval_gate.py:84` → real `VectorStore`; `vector.py:93-96` loads/downloads on first use).
  Concurrent first-runs would each attempt the download. The 7-seed retrieval sweep is run in
  **one** container invocation so the model is fetched once.
- **Cost.** Each retrieval-gate `run()` is 4 arms × 31 commits (`retrieval_gate.py:88-102`), each
  commit embedding at `episodic.py:252`. Seven seeds is 868 commits. Serializing is also the cheap
  option.

### 2.2 MAY run in parallel — per-worktree pytest

`make test-fast`, `make test-storage`, and targeted `pytest` node runs may run concurrently across
**different worktrees**, because each worktree is a distinct Docker Compose project:

- `docker-compose.yml` declares **no top-level `name:`** (services start at `docker-compose.yml:11`)
  and the repo tracks **no `.env`**, so Compose derives the project name from the directory
  basename — `crystalium-w1-graph`, `crystalium-w2-retrieve`, and so on.
- Each project therefore gets its **own** `crystalium_data` volume (declared at
  `docker-compose.yml:47-49`, mounted at `:33`) and its **own** `.:/app` bind mount (`:24`,
  resolved relative to that worktree's compose file). No shared SQLite, LanceDB, Kuzu, or blob state.

**Two carve-outs.**

- **Never two runs inside the same worktree.** Within one project the volume *is* shared; a second
  concurrent suite clobbers fixture state and produces phantom failures that are green in isolation.
- **Build once, before any parallel phase.** All five projects resolve the same image tag
  `crystalium:dev` (`docker-compose.yml:21`). If the image is absent, concurrent
  `docker compose run` invocations each trigger a build of the same tag. Confirm the image exists
  (`docker image inspect crystalium:dev`) or run `make build` **alone** first. `make build` never
  runs concurrently with anything.

### 2.3 Merge order

`W1 → W2 → W3 → W4` (W2/W3/W4 in any order among themselves; they are disjoint). Each merge is
followed by a single `make test-fast` on `main` before the next merge, so a cross-unit interaction
is attributed to the merge that introduced it rather than discovered at release.

## 3. STOP conditions

A STOP halts the campaign at the current unit and returns to FORGE with the recorded evidence. No
STOP may be "worked around" by editing a criterion — criteria edits require
`ramza-freeze --amend --reason` and are otherwise tamper evidence.

| id | condition | detected by | why it is fatal |
|---|---|---|---|
| **VP-S1** | Any of the seven baseline fusion seeds is red on the **shipped** build at `56c8510` | AC-201 | The shipped build is flaky before any change; every downstream differential would be measured against noise. Return to FORGE — this is a v1.10.0 finding, not a #41 finding. |
| **VP-S2** | W1's new ≥2-seed tests **pass** on pre-fix `graph.py` | AC-210 | The tests are not gates. Shipping them would leave the suite exactly as blind as it is today (27 passed on the bug). Halt and rediagnose the fixture. |
| **VP-S3** | AC-125 is not 7/7 unanimous post-fix | AC-221 | AC-136 contingency class (#38's frozen six). The shipped `recall_weighted_fusion` default is implicated; that call belongs to FORGE. |
| **VP-S4** | The DP-2 sweep goes **red at `fusion_weight_derived = 1.00`** | AC-226 | 1.00 is the only value carrying the §D2 bitwise identity property (`config.py:243-245`) and it is the shipped default. STOP **before** any `config.py` edit. |
| **VP-S5** | The DP-2 harness reports 0.90 **green** at the pre-fix SHA | AC-204 | The harness is not reaching the code — `Config` is a plain `@dataclass` (`config.py:82`) and `evals/fusion_gate.py:213` bypasses `Config.from_env`, so a naive patch silently no-ops. Every sweep number is void, including a reassuring one. |
| **VP-S6** | Two branches' changed-file sets intersect | AC-270 | The isolation contract is the campaign's only defence against attributing one unit's regression to another. A breach invalidates every per-unit verdict taken so far. |
| **VP-S7** | A number from the deconfounded gate is diffed against `eval-before.json` / `eval-after.json` | review of `verification.md` | Baselines are gate-version-scoped. `eval-baseline-deconfounded.json` runs a different fixture (2 edges vs up to ~150); a cross-fixture delta is uninterpretable and would look like a real effect. |
| **VP-S8** | The retrieval-gate model is unobtainable in-container | AC-202 (W0) or AC-247 (W3) | Pre-ruled by FORGE: W1's code may merge, but **v1.11.0 does not ship**. The campaign halts at W4 and reports the block on #41 rather than tagging an unverified fix. `CRYSTALIUM_SKIP_SLOW` is **not** a fallback — it produces a dense-armless run (N-5). |
| **VP-S9** | W2's fusion output is not byte-identical to the reference record | AC-235 | #46/#47 are specified as behaviour-neutral. A delta means one of them is not, and the neutrality argument in `spec.md` §2.4.4 is wrong — that is a finding, not a patch target. |
| **VP-S10** | `resolve_verdict` cannot emit `"confounded"` on forced-confounded input | AC-242 | The deconfound's self-check would be a gate that cannot fail on the defect it names — the exact failure #43 is about, reproduced one layer up. |
| **VP-S11** | `CHANGELOG.md` or a version string is modified on any branch but W5's | AC-272 | Release metadata written by a code unit cannot be reviewed as a release; it also guarantees a merge conflict that gets resolved under time pressure at tag time. |

**Not a STOP, but a mandatory finding** (routed to FORGE with seed-level data, campaign continues):
residual cross-seed variance on the post-fix fusion gate (AC-228); a 0.90/0.95 DP-2 cell that
departs from `config.py:238-243`'s recorded cliff (AC-227); a `strict=True` XPASS on
`test_fusion_gate.py:104-113` (§2.2.6 of `spec.md`, pre-ruled as a measured AC-139 GREEN).

## 4. Evidence ledger

Every artefact lands in this change folder
(`/home/rynaro/workspace/oss/agents/eidolons/.spectra/changes/crystalium-open-issues-sweep-50/`),
mirroring the #36 precedent at `.spectra/changes/archive/2026-08-03-crystalium-recall-starvation-36/`.
The crystalium repo's `evals/results/` stays empty — baselines are campaign artefacts, not repo state.

| artefact | produced by | consumed by |
|---|---|---|
| `eval-before.json` | W0 + W0b | AC-201/202/203/205, AC-220/224/225 |
| `dp2-control-prefix.json` | W0c | AC-204 (harness validity) |
| `red-evidence.txt` | W1 (AC-210), appended by W2 (AC-233) and W4 (AC-250) | the checker's proof that the new gates can fail |
| `eval-after.json` | W1b | AC-220..AC-228, W5's CHANGELOG |
| `dp2-sweep-postfix.json` | W1b | AC-226, AC-227 |
| `eval-baseline-deconfounded.json` | W3-measurement | AC-247, AC-248, and future #42/#44/#45 campaigns |
| `verification.md` | kupo | the ESL verify envelope |

## 5. Checker's independent replay

`kupo` accepts a unit only after replaying its VERIFY lines **without** reusing the maker's outputs:

1. Re-run every VERIFY command from `spec.criteria.md` verbatim, from a clean shell, using absolute
   paths (each line is self-contained by design).
2. For the three red-checked criteria (AC-210, AC-233, AC-250), re-derive the redness rather than
   reading `red-evidence.txt`: revert the implementation hunk, observe the failure, restore.
3. Confirm the criteria file is unmodified since freeze:
   `./.eidolons/ramza/bin/ramza-freeze --state <state> --criteria .spectra/changes/crystalium-open-issues-sweep-50/spec.criteria.md --verify` — DRIFT means criteria were edited without a recorded amendment.
4. Confirm scope: `./.eidolons/ramza/bin/ramza-drift --state <state> --range 56c8510..<merged-head>`
   — any changed file outside the declared union of the §1 ownership table is drift, to be amended
   with a reason or flagged.
5. Record each verdict in `verification.md` against the criterion id, including the observed value,
   not merely "pass". A criterion whose observed value is not recorded has not been checked.
