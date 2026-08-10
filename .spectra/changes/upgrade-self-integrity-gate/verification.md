# Verification — `upgrade-self-integrity-gate`

Maker: vivi. This is the maker's own verification record — it is evidence for
the checker (`vigil`), not a substitute for the checker's independent run.
Everything below was **run**, not reasoned about. Per AC-13, this file is the
**only** place the mutation set is enumerated or counted; nothing else in this
change restates the count.

**Revision 2 (adversary round, criteria frozen at
`c2f331de6e58dda1b14c22b6a7a084c7f6a02714e44cd592f39f1a0371fbd9d4`).** Round 1
was rejected by `vigil`, and an independent adversary then broke the gate
three ways, all against the shipped implementation: the vacuous-record class
(AC-21/AC-22), a fail-open enforcement read at the call site (AC-23), and a
suppressed upstream witness folded into the benign `absent` case (AC-25).
AC-24 (the exit-5 descriptions) was a checker finding carried over unfixed.
Round 1's own work (severity join, two-source design, rc-2/rc-3 arms, `set -u`
guarding, stdout/stderr split, the `(integrity: …)` suffix) is unchanged —
see `spec.md` §"What round 1 got right". Everything under "Revision 2" below
was run after round 1's sections, against the round-2 code, using the exact
same method (§Method, unchanged).

**Revision 3 (round 3, criteria frozen at
`b13b4c64106dab2d89dc81f0555a5793ab6b408dcac8cd4c1f8a899d150d1389` over
`acceptance-criteria.md`, chained from `c2f331de…`).** Round 2 was ACCEPTed
by `vigil`, then a concurrent adversary landed AC-26 (a reachable upstream
with no roster file was reported `network`/"upstream unreachable", a false
statement) and both independent verifiers separately flagged AC-27 (the
`case "$_verify_rc"` catch-all `*)` defaulted to `"verified"` for any
out-of-contract return code — proven live by forcing the function's one
`return 4` to `return 9`: exit 0, `(integrity: verified)`, swap completed).
Both are in code this change adds, so both belong to this change. Fixed:
`nexus_release_meta_upstream` (`cli/src/lib.sh`) now returns rc 0 (not rc 1)
when origin HEAD resolves but carries no `roster/index.yaml` — aligning that
sub-case with the other two "upstream reached, nothing usable" sub-cases,
which already classified `absent`; and `upgrade_self.sh`'s policy switch now
has an explicit `0)` arm and a `*)` that refuses (exit 5, naming the
unexpected code) instead of defaulting to verified. Two corrections carried
from the round-3 brief, both independently re-measured before being taken as
given: (1) the obvious AC-27 test mechanism (sed the fixture's `lib.sh`,
invoke through `$EIDOLONS_BIN`) does not work — `cli/eidolons`'s own
NEXUS-resolution probe falls back to the checkout when the fixture nexus
lacks `cli/src/upgrade.sh`, so the sed'd copy never executes; the working
mechanism seeds the fixture with the full `cli/` tree first (§Mutation table,
row 13). (2) The `die()`/subshell reachability claim in the prior revision of
this file was wrong — corrected below, with the counterfactual.

## Method

1. New tests were added to `cli/tests/upgrade_self.bats` (append-only — the
   existing 18 tests are byte-identical to `933f36b`).
2. **Discriminating-power check**: `cli/src/lib.sh` and `cli/src/upgrade_self.sh`
   were temporarily replaced with their exact `933f36b` content (`git show
   933f36b:<path>`), the *new* test file was run against that *old* code, the
   result was recorded, and the fixed files were restored from a saved copy
   (verified byte-identical via `diff` after restore, both times).
3. **Mutation table** (this section): each mutation was applied to the FIXED
   code as a single, isolated, hand-written edit (via `python3 -c` string
   replacement so the edit is exact and auditable), the full
   `upgrade_self.bats` suite was run, the RED set was recorded, and the file
   was restored from the saved-good copy and re-diffed to confirm an exact
   revert before the next mutation. Mutations were never combined or run
   concurrently.
4. `bats cli/tests/upgrade_self.bats`, `make lint`, `make schema`, and the
   full `make test` were run as the final gate, in that order, sequentially
   (never two bats invocations at once).

## Discriminating power — new tests against `933f36b` (pre-fix)

Ran `bats cli/tests/upgrade_self.bats` with the new test bodies but the OLD
(933f36b) `lib.sh` / `upgrade_self.sh` swapped in. Result: **16 of the 22 new
tests failed** (RED), 6 passed (AC-18, AC-11, and one of the two AC-15
sub-tests passed pre-fix — expected, see below).

| Test | Pre-fix result | Why |
|---|---|---|
| AC-1 | RED (`status -eq 5` failed) | pre-fix code has no upstream source at all; the fixture's own `1.0.1` tag was force-moved mid-test (`Updated tag 'v1.0.1'` in the log) and old code still swapped it in |
| AC-2 | RED | old code prints "no release integrity metadata in roster — skipping verification", never "(integrity: verified)" |
| AC-3 | RED | same — stable channel routes through the same broken lookup |
| AC-4 | RED (`status -eq 5` failed) | old code's absent-metadata path is `return 0` unconditionally — no rc 4, no strict refusal |
| AC-5 | RED | no `(integrity: UNVERIFIED - ...)` token exists pre-fix |
| AC-6 | RED (`status -eq 0` failed) | `--allow-unverified` is not a recognized flag pre-fix — `bash "$EIDOLONS_BIN" upgrade self --force --allow-unverified` exits 1, "Unknown option" |
| AC-7a | RED | same — `--allow-unverified` unrecognized |
| AC-7b | RED | mismatch detection pre-fix reads the tag's OWN commit against `$ROSTER_FILE` only; the tampered-tag construction (real value only on the default branch, moved tag) is invisible to a single-source check, so pre-fix proceeds and swaps instead of refusing |
| AC-8a | RED | no `network` token exists pre-fix |
| AC-8b | RED | same |
| AC-9 | RED | no `placeholder`-vs-`absent` distinction in the summary pre-fix |
| AC-9b | RED | same |
| AC-16 | RED (`status -eq 5` failed) | pre-fix single-source read of `$ROSTER_FILE` finds nothing for the pushed version → `return 0` (compat skip), not a refusal |
| AC-16b | RED | same |
| AC-17 | RED | pre-fix non-tag branch prints exactly `"Non-tag ref 'master': commit SHA verified, tree/archive checks skipped."` — the literal false claim this change exists to remove |
| AC-12 | RED (`rc=4` expected, got abort) | `nexus_verify_release` pre-fix has no `NEXUS_VERIFY_STATUS` / rc-4 contract at all; the probe script's `|| rc=$?` pattern never sees a 4 |
| AC-15 (flag-set test) | RED | `--allow-unverified` is absent from the pre-fix header/`--help`/docs, so the header-vs-docs comm diff is non-empty |

Passed pre-fix (not discriminators for those specific assertions):

| Test | Pre-fix result | Why it's expected |
|---|---|---|
| AC-18 | green | pre-fix code never references `NEXUS_VERIFY_STATUS` on the non-tag branch at all, so there is nothing to crash on `set -u` — this criterion only proves the absence of a crash, and both versions are crash-free (regression-guard shape) |
| AC-11 | green | pre-fix `nexus_verify_release` already compares the installed roster's commit/tree against the actual clone and already returns 2 on a wrong value — this is explicitly a regression guard in the spec, not a discriminator |
| AC-15 (exit-code-set test) | green | the exit-code set (0/1/2/4/5/6/7) is unchanged by this fix — no new exit code was introduced (anti-scope), so this sub-test is a regression guard, not a discriminator |
| AC-19, AC-20 | green | these are direct `grep`/content assertions against the CURRENT WORKING TREE's `docs/cli-reference.md` and `README.md`, not against `933f36b`'s docs — restoring only `lib.sh`/`upgrade_self.sh` to 933f36b does not revert the doc edits, so these two report on doc content regardless of which code is in place. Doc discriminating power was verified separately, by inspection: `docs/cli-reference.md` step 4 at `933f36b` reads "match `nexus.versions.releases.<v>` in `roster/index.yaml`" (grep-confirmed absent from the current tree, see AC-19's own negative assertion), and the three `integrity-verified` claims are unchanged text either way (the code fix is what makes them stop being false, not a text edit — see the AC-20 note below) |
| AC-3's `nexus_refresh` grep | green (both) | this is a static grep against `cli/src/upgrade_self.sh` for a call site that never existed even before this change — it is the issue's own probe, kept as a standing assertion, not something this change adds |

This is **broader** discriminating power than `spec.yaml`'s own
`discriminating_power` block claims (AC-1, AC-2, AC-3, AC-16, AC-17, AC-19,
AC-20). The extra RED rows (AC-4 through AC-9, AC-12, one AC-15 sub-test) are
not sold as evidence beyond what they show: they confirm the flag, the rc-4
contract, and the network/placeholder tokens are all genuinely new surface,
not refactored old surface — additional confirmation, not a contradiction of
the frozen record (the frozen `discriminating_power` list is a minimum claim,
not an exhaustive one — nothing in `spec.yaml` says these others must stay
green pre-fix).

## Discriminating power — round-2 tests against the round-1 (pre-round-2) implementation

`spec.yaml:discriminating_power` (revision 1.4.0) names AC-21, AC-22, AC-23,
AC-25 as failing against the CURRENT (round-1) implementation, and AC-24 as
failing both pre-fix and today. Confirmed by direct measurement — not
inferred — by running each new AC-21..AC-25 assertion against
`_nexus_release_source_status` / `upgrade_self.sh` exactly as they shipped at
the start of this round (i.e. the code the round-1 verification section above
describes as "40/40 green"), before any round-2 edit landed:

| Test | Result against round-1 code | Why |
|---|---|---|
| AC-21 (four-shapes, direct) | RED — `a`, `b`, `c1`, `c2` all echoed `verified` instead of `absent`; `d` echoed `verified` instead of `placeholder` | `_nexus_release_source_status` skipped every empty/absent field comparison and fell through to the unconditional `echo "verified"` (round-1 `lib.sh:1088`) |
| AC-21 (upstream vacuous record, end-to-end) | RED — exited 0 with `(integrity: verified)`, not exit 5 | the `{tag, released_at}`-only record satisfied the round-1 fall-through; the backdoor-installation shape from `spec.md`'s `vacuous_record_class` section |
| AC-21 (local-write escalation) | RED — exited 0 with `(integrity: verified:local-only)`, not exit 5 | one file write with no hash knowledge converted a `strict` refusal into a completed upgrade — the exact finding `spec.md` states falsified the record's own MONOTONE invariant |
| AC-22 | RED — `tree_archive_sentinel` echoed `verified` (expected `placeholder`) | round-1's sentinel check (`case "$expected_commit" in "<"*) echo "placeholder"`, `lib.sh:1056-1058`) keyed the placeholder classification on `expected_commit` alone; the other two fields' sentinels were silently skipped as "empty" |
| AC-23 (case/whitespace/bogus/empty) | RED — every one of `STRICT`/`Strict`/`" strict"`/`bogus`/`""` completed the upgrade at exit 0 instead of refusing | round-1's call site compared `integrity_enforcement_mode()`'s output to the literal string `"strict"` with no normalisation |
| AC-23 (unparseable roster) | RED — completed at exit 0 (fell open to the roster's real `warn` setting, since the fixture roster IS parseable when not deliberately corrupted; re-measured with the roster corrupted as the test does — round-1's direct `integrity_enforcement_mode()` call returns the literal string `"warn"` for an unreadable roster, indistinguishable from a roster that says `warn`) | round-1 never added the independent `$ROSTER_FILE`-parses check AC-23 clause (ii) requires |
| AC-24 | RED (as `spec.yaml` states it must be — fails pre-fix **and** against round-1) | all three surfaces still read `INTEGRITY_ERROR` / `integrity check failed` / `Integrity verification failed`, none containing "refused under strict" |
| AC-25 (strict) | RED — refusal line read `(absent)`, not `(absent, upstream unreachable)` | round-1 never exposed which individual source reported `network`; the call site could only see the final severity-selected token |
| AC-25 (warn / summary reason) | RED — summary read `(integrity: UNVERIFIED - absent)`, not `... - absent, upstream unreachable)` | same cause |

All nine assertions were RED against the round-1 code and are green against
the round-2 code (§`bats cli/tests/upgrade_self.bats` below) — the
round-2 fix is genuinely discriminating, not a restatement.

## Discriminating power — round-3 tests against the round-2 (pre-round-3) implementation

The five new AC-26/AC-27 tests were run against the exact round-2 code (saved
as `/tmp/prefix_check/{lib.sh,upgrade_self.sh}`, `diff`-confirmed identical to
the round-2 working tree before any round-3 edit landed), swapped into
`cli/src/`, `bats --filter "AC-26|AC-27" cli/tests/upgrade_self.bats` run,
result recorded, then the round-3-fixed files restored and re-`diff`ed to
confirm an exact restore (full-suite green afterward, see §`bats
cli/tests/upgrade_self.bats` below):

| Test | Result against round-2 code | Why |
|---|---|---|
| AC-26 (strict, no "unreachable") | RED — refusal line read `(absent, upstream unreachable)`, not `(absent)`; `[[ "$output" != *"unreachable"* ]]` failed | `nexus_release_meta_upstream` returned rc 1 for the "roster file absent at FETCH_HEAD" cause, indistinguishable at the call site from a genuine fetch failure |
| AC-26 (warn, no "unreachable") | RED — summary read `(integrity: UNVERIFIED - absent, upstream unreachable)`, not `... - absent)` | same cause |
| AC-26 (control — genuine unreachability) | green (both before and after) | this scenario breaks `git fetch` itself (broken HEAD symref); untouched by the fix, as the criterion requires |
| AC-27 (out-of-contract rc refuses) | RED — `[ "$status" -eq 5 ]` failed (exited 0) | the round-2 `case "$_verify_rc"` had no `0)` arm; `*)` matched rc 9 and set `INTEGRITY_TOKEN="verified"` unconditionally, exactly the checker's `return 4` → `return 9` construction |
| AC-27 (control — real rc=4 path) | green (both before and after) | the legitimate no-evidence branch is unaffected by adding an explicit `0)` arm and narrowing `*)` |

All three positive assertions (two AC-26, one AC-27) were RED against the
round-2 code and are green against the round-3 code (§`bats
cli/tests/upgrade_self.bats` below); both controls stayed green throughout —
the round-3 fix is genuinely discriminating, not a restatement.

## Mutation table (AC-13)

Thirteen mutations: the six from round 1, five from round 2, plus two new
rows matching the round-3 load-bearing list `spec.yaml:AC-13` names at
revision 1.5.0 — stated at behaviour level so the row survives any
implementation shape: the reachable-but-recordless upstream folded back into
`network` (AC-26), and the `*)` arm restored to a `verified` default (AC-27).
Each was applied alone to the FIXED (round-3) code, run, and reverted before
the next. Baseline (no mutation, fixed code): **55/55 green** — 18
pre-existing + 22 round-1 + 10 round-2 + 5 round-3. All thirteen mutations
are confirmed **RED** with that same baseline green, using the real bats
fixture (not a mock).

Mutations 1-6 were **re-run against the round-2 tree** rather than carried
over as a claim from round 1's own record. Their RED sets are **broader**
than round 1 recorded, not merely repeated: rows 1, 3, 4 and 5 also flip one
or more of the round-2 AC-21/AC-23/AC-25 tests, because those new tests share
fixture state and message text with the round-1 assertions the mutations
already broke — e.g. mutation 1 (`origin main`) makes every upstream fetch
fail, so AC-25's suppressed-witness disclosure now legitimately fires on
scenarios that used to read plain `(absent)`, which breaks the round-1 tests
that assert the old exact-match text. This is a **discovery**, not a
regression: it means the round-2 additions are not siloed from round-1
coverage, and a checker re-running these mutations should expect the wider
sets below, not row 1's original round-1 table (which is superseded by this
one).

| # | Mutation | Where | Tests that went RED | Tests that stayed green |
|---|---|---|---|---|
| 1 | `origin HEAD` → `origin main` in `nexus_release_meta_upstream` | `cli/src/lib.sh` (`git -C "$clone_dir" fetch --depth 1 origin HEAD` → `... origin main`) | AC-1, AC-2, AC-3, AC-5, AC-6, AC-7a, AC-7b, AC-9, AC-9b, AC-16, AC-16b, AC-23 (WARN-control) (12) | AC-4, AC-8a, AC-8b, AC-17, AC-18, AC-11, AC-12, AC-15×2, AC-19, AC-20, AC-21×3, AC-22, AC-23 (trim/lowercase, unparseable-roster), AC-24, AC-25×2 + all 18 baseline (38 total) |
| 2 | `--allow-unverified` widened to swallow rc 2 (mismatch) | `cli/src/upgrade_self.sh` (the `2)` case arm: added `if [[ "$ALLOW_UNVERIFIED" == true ]]; then …proceed… else …refuse… fi` instead of unconditional refusal) | AC-7a (1) | everything else, including AC-7b (the `EIDOLONS_INTEGRITY_ENFORCEMENT=warn` arm of the same escape-hatch-cannot-disable-the-gate criterion) — confirms the two arms of AC-7 are independently load-bearing, not redundant (49 total) |
| 3 | `strict` treating no-evidence as `warn` | `cli/src/upgrade_self.sh` (`"$_mode" == "strict"` → `"$_mode" == "MUTATED-strict"`, i.e. the strict branch becomes unreachable) | AC-4, AC-8b, AC-16, AC-16b, AC-21 (upstream vacuous, local-write escalation), AC-23 (trim/lowercase, unparseable-roster), AC-25 (strict) (9) | AC-1, AC-2, AC-3, AC-5, AC-6, AC-7a, AC-7b, AC-8a, AC-9, AC-9b, AC-17, AC-18, AC-21 (four-shapes direct), AC-22, AC-23 (WARN-control), AC-25 (warn/summary) + regression guards (41 total) |
| 4 | placeholder-dominant instead of severity-dominant selection | `cli/src/lib.sh` (the no-evidence join in `nexus_verify_release`: reordered to check `placeholder` first, `absent` last) | AC-8a, AC-8b, AC-16, AC-16b, AC-23 (trim/lowercase, WARN-control, unparseable-roster), AC-25×2 (9) | AC-1–AC-9 (non-severity rows), AC-17, AC-18, AC-21×3, AC-22 + regression guards (41 total) |
| 5 | the `(integrity: …)` summary suffix removed | `cli/src/upgrade_self.sh` (final `ok "Upgraded nexus … (integrity: …)"` → `ok "Upgraded nexus …"`, no suffix) | AC-2, AC-3, AC-5, AC-6, AC-8a, AC-9, AC-9b, AC-17, AC-23 (WARN-control), AC-25 (warn/summary) (10) | AC-1, AC-4, AC-7a, AC-7b, AC-8b, AC-16, AC-16b, AC-18, AC-21×3, AC-22, AC-23 (trim/lowercase, unparseable-roster), AC-24, AC-25 (strict) (these assert exit code / stderr text, not the summary token) + regression guards (40 total) |
| 6 | the non-tag token removed (reverted to the pre-fix false claim) | `cli/src/upgrade_self.sh` (`else` branch: `warn "Non-tag ref '$TARGET_REF': no release record exists…"` + `INTEGRITY_TOKEN=…` → `warn "Non-tag ref '$TARGET_REF': commit SHA verified, tree/archive checks skipped."`, no token) | AC-17 (1) | AC-18 (asserts only "no crash" + "Upgraded nexus" — narrower than AC-17 by design, so it correctly stays green even though the wording regressed) + everything else (49 total) |
| 7 | AC-21: the comparison counter removed so an empty record falls through to `verified` again | `cli/src/lib.sh` (`_nexus_release_source_status`'s final `if [[ "$compared" -eq 1 ]]; then echo "verified"` → `if true; then echo "verified"`, i.e. the fall-through is restored unconditionally) | AC-8a, AC-8b, AC-9, AC-9b, AC-16, AC-16b, AC-12, AC-21×3, AC-22, AC-23 (trim/lowercase, WARN-control, unparseable-roster) (14) | AC-1–AC-7 (real-value paths, unaffected), AC-17, AC-18, AC-24, AC-25×2 + regression guards (36 total) |
| 8 | AC-22: the sentinel check narrowed back to `.commit` alone | `cli/src/lib.sh` (the `tree`/`archive_sha256` `case` arms' `"<"*) saw_sentinel=1 ;;` → `"<"*) : ;;`, i.e. their sentinels are silently absorbed as if empty, the way `commit`'s WAS the only field checked pre-fix) | AC-21 (four-shapes direct — shape (d), tree/archive-only sentinels, now classifies `absent` instead of `placeholder`), AC-22 (2) | everything else (48 total) |
| 9 | AC-23: the call-site enforcement normalisation removed | `cli/src/upgrade_self.sh` (`_mode="$(_upgrade_self_enforcement_mode)"` → `_mode="$(integrity_enforcement_mode)"`, the direct pre-round-2 call with no trim/lowercase/parse-check) | AC-23 (trim/lowercase, unparseable-roster) (2) | AC-23 (WARN-control — "WARN" and "strict" are both non-matches against the exact `"strict"` compare either way, so this control test cannot discriminate this specific mutation; documented, not a gap) + everything else (48 total) |
| 10 | AC-24: the exit-5 description reverted | `docs/cli-reference.md` (the exit-code table's row 5, `\| 5 \| Integrity verification failed, or no evidence and refused under strict \|` → `\| 5 \| Integrity verification failed \|`, i.e. one of the three pinned surfaces reverted) | AC-24 (1) | everything else, including the header block and `--help` heredoc surfaces AC-24 also checks (they were not mutated in this row, confirming AC-24's assertion is genuinely per-surface, not satisfied by any-of) (49 total) |
| 11 | AC-25: the suppressed-witness disclosure removed | `cli/src/upgrade_self.sh` (the `_reason` computation's `if [[ "$_reason" == "absent" ]] && { …network check… }; then _reason="absent, upstream unreachable"; fi` block deleted, `_reason` reverts to the bare `"${_verify_status:-absent}"`) | AC-25×2 (2) | everything else, including AC-16/AC-16b (whose scenarios never involve a `network` source, so the disclosure logic was never reachable for them — the mutation is isolated to exactly the case AC-25 names) (48 total) |
| 12 | AC-26: the reachable-but-recordless upstream folded back into `network` | `cli/src/lib.sh` (`nexus_release_meta_upstream`'s "no roster/index.yaml at FETCH_HEAD" branch: `return 0` → `return 1`, i.e. the same rc as the genuine-fetch-failure branch above it — the exact pre-fix collapse) | AC-26 (strict, no "unreachable"), AC-26 (warn, no "unreachable") (2) | AC-26 (control — genuine unreachability, unaffected since its `git fetch` itself still fails at rc 1) + everything else, including all 10 round-2 tests and all 22 round-1 tests (53 total) |
| 13 | AC-27: the `*)` arm restored to a `verified` default | `cli/src/upgrade_self.sh` (the explicit `0)` arm merged back into `*)`, i.e. `case "$_verify_rc" in 2) … 3) … 4) … *) INTEGRITY_TOKEN="verified" ;; esac` — the exact pre-fix shape, reproduced from the checker's own construction: `return 4` → `return 9` inside a fixture copy of `lib.sh` reached via the full-cli-tree fixture (§AC-27 fixture helper in `upgrade_self.bats`) | AC-27 (out-of-contract rc refuses) (1) | AC-27 (control — real rc=4 path, unaffected: rc 4 still matches the `4)` arm, which this mutation does not touch) + everything else (54 total) |

Each row's edit was verified applied (`grep`/`diff` against the intended
string before running bats) and verified reverted (`diff` against the saved
fixed-state copy, exact match — `sha256sum` matched the pristine fixed-state
copy after every single revert, checked explicitly, not assumed) before
moving to the next row — the exact concern AC-13's evidence text raises ("a
mutation harness that silently no-ops reports every mutation as caught").
Rows 12 and 13 were additionally isolated to a SINGLE file each (row 12 never
touches `upgrade_self.sh`; row 13 never touches `lib.sh`), confirmed by
`sha256sum` on the untouched file before and after — the round-2 rows above
already established this discipline, and rows 12/13 follow it rather than
relaxing it now that only two files are in scope.

### What this table does not claim

- It does not claim these are the ONLY mutations that would go RED — only
  that the thirteen load-bearing rows `spec.yaml:AC-13` explicitly names (six
  round-1, five round-2, two round-3) are covered.
- Mutation 6 leaves AC-18 green by design (AC-18's own scope is narrower:
  "does not crash", not "carries the right token") — this is not a gap in
  mutation 6, it is AC-17 and AC-18 doing two different jobs, as the frozen
  criteria describe.
- Mutation 9's AC-23 "WARN-control" test does not discriminate that specific
  mutation (see the row's own note) — it is a control for the case-folding
  behaviour generally (rows 3, 4, 5, 7 above all flip it), not for the
  call-site-normalisation removal specifically, since an un-normalised
  literal-string compare against `"strict"` happens to treat `"WARN"` the
  same way a correctly-normalised compare does (both proceed). Recorded
  rather than left implicit.
- No mutation was attempted against the doc-content criteria (AC-19, AC-20)
  or the mechanical set-diff (AC-15) beyond what the discriminating-power
  section above already shows — those are direct content assertions against
  the current tree, and "mutating" them would mean re-breaking the docs by
  hand, which is exactly what the discriminating-power run against `933f36b`
  already demonstrates for AC-19 (the wrong-source sentence is confirmed
  present in `933f36b`'s copy of the file via the AC-19 test's own negative
  grep, run against the current tree where that sentence is confirmed absent).

## `bats cli/tests/upgrade_self.bats`

Final run, fixed code, no mutations: **55/55 passed** (18 pre-existing +
22 round-1 + 10 round-2 + 5 round-3). Exit code 0 (`echo $?` immediately
after the `bats` invocation; `grep -c '^ok'` = 55, `grep -n '^not ok'` =
empty, both against the captured TAP output). Ran standalone (no concurrent
bats invocation in the same window).

## `make lint`

`shellcheck -x -S error` over `cli/*.sh` (`cli/src/lib.sh`,
`cli/src/upgrade_self.sh` included, both edited this round). Exit code 0. No
findings.

## `make schema`

`check_roster_mcp_skew` and `check_change_specs` (which parses this change's
own `spec.yaml`) both pass. Exit code 0.

## `make test` (full suite)

`bats --jobs 8 --no-parallelize-within-files cli/tests/` (Makefile default
`JOBS=8`). **1760/1760 passed** (1755 round-2 total + 5 round-3 new tests;
the round-2 record below reports 1755, which was correct for that revision —
round 3 recounts rather than restating it). Exit code checked via `echo $?`
immediately after the `make` invocation; `grep -c '^ok '` = 1760, `grep -n
'not ok'` = empty, against the captured TAP output — the standing lesson in
this repo that `cmd | tail` reports tail's exit code, not cmd's. Ran
standalone (no concurrent bats invocation in the same window), and
sequentially after `bats cli/tests/upgrade_self.bats` and `make
lint`/`make schema` (never two bats suites at once, per this round's own
obligations).

Round-2 record (for continuity, unchanged from that revision): `bats --jobs 4
--no-parallelize-within-files cli/tests/`. **1755/1755 passed.** Exit code 0
(checked twice independently — once via `echo $?` immediately after the
`make` invocation, once via a non-piped `echo $? > file` redirect run in the
background — both reported `0`). Ran standalone both times.

Round-1 record (for continuity, unchanged from that revision): `bats --jobs 4
--no-parallelize-within-files cli/tests/`. **1745/1745 passed.** Exit code 0
(checked via `echo $?` immediately after the `make` invocation completed —
not inferred from a piped `tail`). Ran once, standalone (no concurrent bats
invocation in the same window).

## Correction — the `die()`/subshell path IS reachable

The prior revision of this file called `_upgrade_self_enforcement_mode`'s
clause (ii) `die()`/subshell guard unreachable (the "Round 2" bullet under
§What was NOT verified below, now corrected to "Round 3" in place).
**That was wrong.** The guard is reachable via two independent
constructions, both reproduced end to end against the real fixture harness
(non-tag-record fixture: `EIDOLONS_HOME`/`EIDOLONS_NEXUS`/`EIDOLONS_REPO`
pointed at an isolated `file://` remote, `EIDOLONS_INTEGRITY_ENFORCEMENT`
unset so clause (ii) is the code path taken, a target version with no
release metadata on either source so the rc-4 no-evidence branch calls
`_upgrade_self_enforcement_mode` at all):

1. **`_YAML_TO_JSON_BACKEND=none` exported.** `_YAML_TO_JSON_BACKEND` is
   exported and memoised at `cli/src/lib.sh:111,113` (`[[ -z
   "${_YAML_TO_JSON_BACKEND:-}" ]] && _resolve_yaml_to_json_backend`) — it is
   injectable from the environment of the process that sources `lib.sh`.
   Run: `env _YAML_TO_JSON_BACKEND=none EIDOLONS_HOME=… EIDOLONS_NEXUS=…
   EIDOLONS_REPO=… bash "$EIDOLONS_BIN" upgrade self --ref v2.0.0 --force`
   (normal `PATH`, `yq` and `python3` both present and ignored because the
   memoised value short-circuits `_resolve_yaml_to_json_backend`). Actual
   output: `⚠ nexus@2.0.0 has no verifiable release integrity metadata
   (installed=absent upstream=absent)` then `nexus@2.0.0 release integrity
   could not be verified (absent). Refusing to swap under strict
   enforcement. The previous nexus is intact.`, exit **5**.
2. **A `PATH` that resolves `yq` and `python3` to nothing.** A `PATH`
   carrying neither `yq` nor `python3` (but retaining coreutils/git/jq/bash —
   **not an empty `PATH`**: an empty `PATH` fails at `lib.sh:15`'s `mkdir -p
   "$CACHE_DIR"` before `_resolve_yaml_to_json_backend` is even reached,
   which is a different, uninteresting crash and not this guard) causes
   `_resolve_yaml_to_json_backend` to resolve `_YAML_TO_JSON_BACKEND=none` at
   SOURCE TIME (neither `command -v yq` nor `command -v python3` succeed).
   Constructed via a symlink farm mirroring `/usr/bin` minus
   `python3`/`python3.*`/`python` (`~/.local/bin`, where this sandbox's `yq`
   lives, excluded from `PATH` entirely). Run: `env PATH=<farm> HOME=…
   EIDOLONS_HOME=… EIDOLONS_NEXUS=… EIDOLONS_REPO=… bash "$EIDOLONS_BIN"
   upgrade self --ref v2.0.0 --force`. Actual output: byte-identical shape to
   construction 1 — the same warn line, the same refusal text, exit **5**.

Both constructions reach `yaml_to_json`'s `die` branch inside the
parenthesised subshell (`if ! ( yaml_to_json "$ROSTER_FILE" >/dev/null 2>&1
); then echo "strict"; return 0; fi`). With the subshell (the shipped code),
`die()`'s `exit 1` is confined to the subshell, `_upgrade_self_enforcement_mode`
returns `"strict"` normally, and the run continues to a correct, graceful
refusal.

**Counterfactual, to show the guard is load-bearing and not incidental:** the
same parens were removed in a scratch copy (`if ! yaml_to_json "$ROSTER_FILE"
>/dev/null 2>&1; then …`) and construction 1 re-run against it, invoking the
scratch `upgrade_self.sh` directly. Actual output: the run proceeds normally
through cloning and the no-evidence warn (`⚠ nexus@2.0.0 has no verifiable
release integrity metadata (installed=absent upstream=absent)`), then
terminates at exit **1** with **no refusal message, no "Refusing to swap"
line, and no cleanup** — `$EIDOLONS_HOME/nexus.new` was left on disk,
confirmed present by `ls` after the crash (the graceful path always `rm -rf
"$NEXUS_NEW"` before exiting; this crash exits from inside `die()` itself,
before the caller's cleanup can run). `die()`'s own message is swallowed by
the surrounding `>/dev/null 2>&1` in both the guarded and unguarded case (the
redirection, not the parens, controls that) — the difference the parens make
is entirely about SCOPE: subshell-confined `exit 1` vs. whole-script `exit
1`. This is the exact failure mode the guard's own comment
(`_upgrade_self_enforcement_mode`, "an unparenthesised call here would take
the whole script down with it") describes, now demonstrated rather than
merely asserted.

**Conclusion: the guard is correct and now verified — only this file's
previous claim of unreachability was wrong.** Both reproductions are ad hoc
(§What was NOT verified, Round 3 bullet), not a committed bats regression
test.

## What was NOT verified

- **The macOS `cli-tests` CI job** was not run — this sandbox is Linux only.
  bash 3.2 compatibility was checked by construction (no `declare -A`, no
  `${var,,}`/`${var^^}`, no `readarray`/`mapfile`, no `&>>`, no process
  substitution outside of the new AC-15 bats test itself — `<(...)` is used
  in the TEST, which runs under the bats/GNU-bash test harness, not inside
  `cli/src/lib.sh` or `cli/src/upgrade_self.sh`, so it carries no bash-3.2
  obligation) and confirmed via `shellcheck -S error` (which flags several
  bash-4-only constructs), but the actual `bash --version 3.2` execution
  path was not exercised.
- **Real-network behaviour against `https://github.com/Rynaro/eidolons`**
  (i.e. `origin HEAD` against the genuine upstream repo) was not
  re-executed as part of this change — it is cited in `spec.md`'s own
  `measurements` section as independently re-measured by the plan's author
  before this change was frozen, and this maker's job is to implement
  against the frozen record, not re-derive it. The bats fixture remote
  (`file://` non-bare repo) exercises the identical git plumbing
  (`fetch --depth 1 origin HEAD` + `show FETCH_HEAD:path`) against a real,
  local git server, which is what makes the mechanism testable at all per
  the frozen spec's own `TESTABILITY IS PART OF THE FIX` invariant.
- **A live `strict`-mode run against the real roster's real
  `integrity.enforcement: strict`** end-to-end through the actual
  `~/.eidolons` install path was not performed (that would mutate this
  machine's real installed nexus). AC-4/AC-6/AC-8b/AC-9b/AC-16/AC-16b cover
  `strict` behaviour via `EIDOLONS_INTEGRITY_ENFORCEMENT=strict` against the
  isolated bats fixture, which is the same override mechanism
  `integrity_enforcement_mode()` uses in production.
- **`--allow-unverified` combined with a genuinely absent installed roster
  file** (no `roster/index.yaml` at all, vs. an empty `releases` map) was not
  separately tested — `yaml_to_json` on a missing file already dies via the
  existing `ROSTER_FILE` contract shared with every other command, and this
  change does not alter that path; not exercised as a distinct scenario here
  because it is out of this change's scope (the roster file's own existence
  is a pre-existing invariant of the whole CLI, not something this change
  introduces or touches).
- **Round 3.** `_upgrade_self_enforcement_mode`'s clause (ii) "no yq and no
  python3+yaml" sub-case (`yaml_to_json`'s own last-resort `die()`) is now
  confirmed reachable end to end — see §"Correction — the `die()`/subshell
  path IS reachable" above. AC-23's unparseable-roster scenario
  covers a *different* sub-clause (corrupts the roster's content, so
  `yaml_to_json` exits non-zero because the YAML is invalid, not because no
  parser exists); it is not a substitute for this one. What is genuinely NOT
  in this change's bats suite: neither construction below is wired into a
  permanent, committed `upgrade_self.bats` test — both were reproduced as
  standalone, ad hoc reproductions against the real fixture harness (recorded
  below with their actual output) rather than as a new regression test, so a
  future edit to this path would not be caught automatically by `make test`.
- **Round 2.** The `EIDOLONS_INTEGRITY_ENFORCEMENT` set-but-empty case
  (`export EIDOLONS_INTEGRITY_ENFORCEMENT=""`) is covered by the AC-23 loop
  test (the `""` value in its `for val in ...` list) and confirmed to refuse
  — but was not separately isolated from the "unset" case with an explicit
  `${VAR+x}`-vs-`${VAR:-}` unit probe at the shell level (only end-to-end,
  through the CLI). The distinction is documented in
  `_upgrade_self_enforcement_mode`'s own comment; the end-to-end test is
  sufficient to prove the *observable* behaviour (refuse) but does not by
  itself prove *which* branch of the function was taken.
