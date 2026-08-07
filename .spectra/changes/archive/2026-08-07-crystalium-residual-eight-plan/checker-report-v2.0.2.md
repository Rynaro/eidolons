# Checker report — crystalium v2.0.2 (AC-332, AC-330, AC-331, AC-382)

checker: kupo (maker: ramza) | tree: `release/v2.0.2` @ `80b4248af326331869a69311914682b2c8b1b450`
worktree: isolated checker worktree (`wt-checker` compose project), container-only, `git` used on HOST only.

## AC-332 — independent re-break of all five (+1 optional) red-checkable artifacts

Full evidence, verbatim patches, commands, exit codes, and output tails: `checker-redcheck.json`
(6 entries — the 5 mandated + G-FLOOR as the optional sixth). Summary:

| # | gate | axis (mine) | exit | restore |
|---|---|---|---|---|
| 1 | entrypoint (#57) | Neutralize tool REGISTRATION content in `server.py`'s `_list_tools` (empty table). Handshake completes, process exits 0, no stderr traceback — fails purely on `tools/list` content. | 1 | green (1 passed) |
| 2 | rig (W-RIG) | Rule-(g) artifact-freshness: `emit()`'s direct-subscript `os.environ[...]` replaced with a silent `.get(..., "unknown")` fallback. | 1 | green (36 passed) |
| 3 | cross-layer G-XL (#52) | C-XL-3 global-BM25-premise attack: `ep1` rewritten to `sem-target`'s own TF construction (term x3, no padding) — membership/liveness counts untouched, only global BM25 rank-0 ownership flips. | 1 | green (6 passed, 1 xfailed) |
| 4 | corpus-scaling G-CORPUS (#47) | Corpus-SIZE attack: `_LARGE_NOISE_COUNT` 59→20 (corpus 21 < candidate_k 30), directly falsifying the "M > candidate_k" premise AC-314's own worked example states. | 1 | green (3 passed) |
| 5 | weight-discrimination G-WD (#55) | Base-arm-rank attack: leader's TF de-loaded 3x→1x + padding, so B outranks leader; A's graph edge is untouched (`graph_liveness` stays green, only `base_known_rank` flips). | 1 | green (9 passed) |
| 6 (optional) | floor-sensitivity G-FLOOR (#48) | Floor-CONSTANT attack: `run_seed`'s `floor_high` default 1000→11, so both floors land in the same undiscovered-phantom regime (`zzedgecomp` sits at dense rank 11). | 1 | green (20 passed) |

Every perturbation was verified, via a direct byte-normalized diff against all 12 patches across
the six `red-evidence-*.json` files, to be **non-identical** to every maker patch on file
(`OK` for all 6 in the anti-replay check).

### A finding beyond the mandate: FORGE's own D8 ruling table contains replay traps

D8 (`forge-rulings.md`) proposes a "checker's perturbation (replacement)" for each of the five
v2.0.2 rows. Cross-checking D8's literal suggested text against the maker's own
`red-evidence-*.json` files found that **three of five D8 rows are not independent at all — they
are verbatim (or near-verbatim, same mechanism) restatements of the maker's own already-executed
red-check**, which would fail D8's own anti-replay diff step if used as literally written:

- **G-XL row**: D8 suggests "remove ONE query term from ONE episodic filler's summary" —
  this is *exactly* maker RC-1/RC-2's own axis, byte-for-byte the same lever
  (`red-evidence-wgxl.json`, `terms = _XL_QUERY_TERMS[:-1] if label == "ep1"`).
- **G-WD row**: D8 suggests "sever record A's graph edge (A loses its only support)" — this is
  *exactly* the maker's only axis on file (`red-evidence-wgwd.json`, the ONLY red-check present).
- **G-FLOOR row**: D8 suggests "delete the edge from the edge-bearing competitor to its phantom" —
  this is *exactly* maker RC-3, already on file (`red-evidence-wgfloor.json`, third entry,
  `edges=[]`).
- The G-CORPUS row ("boost the planted record's BM25 by repeating query terms twice more") is not
  byte-identical to maker RC-2 but is the **same mechanism** (edit the planted record's own
  summary/TF) — not a genuinely third axis.

Only the **entrypoint row** (D8's "neutralize tool registration") is a genuinely independent
axis as written. This matches the orchestrator's own warning that the D8 table "had 5 defective
rows once already, and one row was found unbuildable (K-C3)" — I found a *different* species of
defect in the *same* table: three of its five "checker replacement" rows would themselves fail
the anti-replay check D8 mandates, had they been used verbatim. I did not use them; I used the
task's own alternate "suggested independent axis" hints (which conveniently already diverge from
D8's literal text for exactly the three compromised rows), and independently designed and
empirically verified each perturbation before committing to it (see `xl_probe*.py`, `wd_probe.py`
in scratch). **This should be reported back to FORGE / recorded against D8** — the ruling's
counts and mechanism ("axis-distinct, RED-asserted") are correct in spirit, but three of its five
literal replacement rows need re-derivation before they could ever be handed to a checker as-is.

## AC-330 — `make test` / `make test-ci` parity

Both run independently, sequentially confirmed after a first concurrent attempt showed real (not
corrupted) progress under CPU contention — both containers were verified actively computing
(`docker stats`, 400–1000% CPU) rather than deadlocked, and both completed with numbers matching
the task's own stated expectation exactly:

```
make test     -> 1071 passed, 4 skipped, 1 xfailed, 31 warnings in 984.53s   EXIT=0
make test-ci  -> 1067 passed, 8 skipped, 1 xfailed, 31 warnings in 545.31s   EXIT=0
```

Modes agree (the 4-test delta is exactly the `CRYSTALIUM_SKIP_SLOW=1` skip set; xfailed count
identical) — **no S-9 disagreement.** GREEN.

## AC-331 — `mcp-server/src/` diff is comment-only

```
git diff b7f1a47..HEAD --name-only -- mcp-server/src/
  -> mcp-server/src/crystalium/config.py   (only file)

git diff -w -U0 b7f1a47..HEAD -- mcp-server/src/crystalium/config.py
  -> 14 lines added, 0 removed, every added line starts with `#` (comment-only)
```
GREEN — matches CAMPAIGN-STATE.md's claim exactly, independently re-verified on the host.

## AC-382 — node-collection sweep (orchestrator-authored; extra scrutiny applied)

Ran the VERIFY script verbatim (adapted `MAIN` to this checker's own isolated worktree, same
tree SHA):

- Step 1 (effective node extraction + dedupe): 20 effective nodes — matches
  `spec.criteria.amend-04.md`'s own stated count exactly.
- Step 2 (one collection run, `< /dev/null`, never a per-node loop — avoids RC-2's stdin-eating
  defect by construction): 1076 nodes collected — matches exactly.
- Step 3 (set-difference + manifest classification): 11 missing, all 11 present in
  `wave-manifest-pending.txt` → **0 BLOCKERs**. 9 COLLECTS + 11 PENDING = 20. Matches the
  amendment's documented measurement (`ff4fb5d`) exactly, reproduced independently on `80b4248`.

**Additional scrutiny (per the "treat orchestrator-authored criteria with MORE suspicion"
instruction):** inspected the dedupe step's own failure mode — it keys on `(file, terminal
function name)` and keeps the higher-`::`-count (more qualified) form when a key collides. A
latent risk in this design is that TWO GENUINELY DIFFERENT tests (different classes, same
terminal function name, same file) could silently collide under one key, hiding a real second
broken selector. Checked the raw (pre-dedupe) 27-line node list for this: every one of the 7
colliding keys is the same test referenced twice (bare form + class-qualified form from a
superseding amendment) — no case of two *distinct* tests colliding was found in the current
input. I did not find a fourth defect in AC-382 on this measurement; it passed cleanly and its
sweep logic held up under the scrutiny I could apply in the time available. This is a *reported
absence of a finding*, not a certification that no further defect exists.

GREEN.

## VERDICT: **APPROVE** for tagging v2.0.2

All 5 mandated red-checkable artifacts (+1 optional) were independently re-broken on axes that
are (a) empirically verified to differ from every maker patch on file (anti-replay diff, all 6
`OK`), and (b) each failed precisely on the property its control names — not incidental
collateral (entrypoint: content vs liveness; rig: artifact-freshness vs edge-count-unwrap vs
R-CONF; G-XL: global-BM25 premise vs term-membership; G-CORPUS: corpus-size boundary vs
planted-record text; G-WD: base-arm rank vs derived-arm topology; G-FLOOR: floor constants vs
topology/placement/control-validity). Every perturbation was restored and reconfirmed green.
AC-330/AC-331/AC-382 all independently reproduce the maker's/orchestrator's claimed numbers
exactly, with no S-9 mode disagreement and no hidden AC-382 defect found under extra scrutiny.

The one substantive caveat is the D8 replay-trap finding above: it is a defect in FORGE's
ruling document, not in the shipped code or gates, and does not change the verdict — but it
should be corrected in `forge-rulings.md` before D8 is cited as a template for the v2.1.0
checker table (which shares the same table structure and is due the same scrutiny).

## Note on AC-332's literal jq predicate vs the 6th (optional) entry

D8 states AC-332's jq check as `[.gates[] | select(.perturbation_patch != null and
.exit_code != 0) ] | length == 5` (strict equality). This task's own instructions asked for
"at least 5" entries and explicitly invited G-FLOOR as an optional sixth "if budget allows."
`checker-redcheck.json` as written has **6** qualifying entries (all `perturbation_patch != null`,
all `exit_code != 0`), which would fail a literal `== 5` predicate even though it satisfies (and
exceeds) the AC-332 intent. Flagging this for whoever runs the literal conformance check: either
(a) relax the predicate to `>= 5`, or (b) drop the optional G-FLOOR entry before running the
literal check. I did not silently drop it myself — the extra artifact is real, independently
reproduced evidence and I'd rather surface the schema tension than discard verified work.
