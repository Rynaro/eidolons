---
eidolon: ramza
kind: spec
version: 1.5.0
created_at: 2026-08-10
change_id: upgrade-self-integrity-gate
---

# upgrade-self-integrity-gate — the check that reads a file which cannot yet exist

**maker:** vivi · **checker:** vigil · **spec author:** ramza · **critic:** ramza-critic-561 · **tier:** full
**upstream issue:** https://github.com/Rynaro/eidolons/issues/561
**measured on:** `main` @ `933f36b` (VERSION 2.20.0)
**revision:** 1.5.0 — minimal amend, two criteria, nothing else re-litigated.
Two independent verifiers disagreed about AC-25 and **both were right about a
different layer**: the checker drove the *status values* and found the
status→message mapping correct; the adversary drove *reality* and found the
reality→status mapping wrong. **AC-26** — a *reachable* upstream whose default
branch carries no `roster/index.yaml` is classified `network` and disclosed as
`upstream unreachable`, a false statement about an upstream that answered.
**AC-27** — the policy switch's `*)` catch-all is a **fail-open default inside a
fail-closed change**; any unanticipated return code reads as `verified`
· 1.4.0 — adversary round: the **vacuous-record class** (a release
record that exists but compares nothing was classified `verified`, falsifying
this record's own fail-closed invariant), the `<`-sentinel's scope, the
fail-open enforcement read, the exit-5 descriptions, and the suppressed-witness
message — AC-21…AC-25 added, all measured against the shipped code
· 1.3.0 — post-rejection record amend: the evidence *variable value*
`skipped:non-tag` and the *summary display string* `UNVERIFIED - non-tag ref` are
separated everywhere and AC-17 is restated against the display string (the code
is correct and unchanged); AC-15's blindness to semantic drift and AC-19's
MET-as-frozen ruling recorded; the test-name/assertion residual added
· 1.2.0 — coordinator amend hop (doc surfaces in scope, AC-15 as a set, AC-19/AC-20, OQ-4 ruled)
· 1.1.0 — applies critic `ramza-critic-561` ACCEPT-WITH-CHANGES (B-1, B-2, B-3, N-1..N-7)

## Problem

`eidolons upgrade self` announces that it verifies release integrity, and its
refusal wiring is correct. On a normal forward upgrade the check **cannot run**.

Three facts compose:

| # | Fact | Evidence |
|---|---|---|
| 1 | `nexus_verify_release` reads the **currently installed** nexus's roster | `cli/src/lib.sh:1006` reads `$ROSTER_FILE`; `cli/src/lib.sh:13` defines it as `$NEXUS/roster/index.yaml` |
| 2 | A release's metadata is recorded **after** its tag | v2.20.0's tag points at `2cd2d09`; its metadata landed in `933f36b` (#560), a later commit |
| 3 | `upgrade_self.sh` never refreshes the roster | `nexus_refresh` appears only in comments (lines 81, 82, 94, 96, 122) |

So the metadata lookup misses, takes the fail-open early return
(`warn ... skipping verification; return 0`), and `upgrade_self.sh:285-299` —
which refuses correctly on rc 2 and rc 3 — never receives a failing code.
Observed live on 2.14.1 -> 2.20.0: exit 0, nothing cryptographically checked.

Fact 2 is not a race, it is a **construction**: no tag's tree can contain its
own commit/tree/archive hashes. Re-measured directly rather than assumed:

```
$ git clone --depth 1 --branch v2.20.0 https://github.com/Rynaro/eidolons /tmp/v220
$ git -C /tmp/v220 show HEAD:roster/index.yaml | yq '.nexus.versions.releases."2.20.0" // "ABSENT"'
ABSENT
```

The same holds for the **old install's** roster. Both candidate local sources
are structurally incapable of carrying the answer.

### The same defect on the sibling path

`_is_semver_tag` false takes the `else` branch at `upgrade_self.sh:299-301`,
which warns and completes the upgrade:

```
$ eidolons upgrade self --ref master --force      # measured on the bats fixture
⚠ Non-tag ref 'master': commit SHA verified, tree/archive checks skipped.
✓ Upgraded nexus 1.0.0 -> master
$ echo $?
0
```

**"commit SHA verified" is false** — nothing on that branch verifies a commit
SHA. A message that reads like verification when none happened is the defect
in #561, and `--ref <branch>` is documented in both the header block and
`--help`, so this is live in production. It is in scope here. Fixing it on the
tag path while leaving it standing on the sibling path is not defensible.

(Note also that `TARGET_VERSION` is `_strip_v "$TARGET_REF"`, so the summary
literally reads `-> master`.)

## Scope

**In.** The absent-entry branch of `nexus_verify_release`, the metadata
*source* it reads, the policy `upgrade_self.sh` applies to a non-verification,
**and the non-tag branch's status and wording**. A new `--allow-unverified`
flag. The terminal summary line.
Added at revision 1.4.0, all measured against the shipped implementation:
the **vacuous-record class** in `_nexus_release_source_status` (a record with
no comparable field must never classify `verified` — AC-21), the **scope of the
`<`-sentinel** across all three fields rather than `commit` alone (AC-22), the
**enforcement read at the `upgrade_self.sh` call site** made fail-closed
(AC-23), the **exit-5 descriptions** on all three surfaces (AC-24), and the
**disclosure of a suppressed upstream witness** in the refusal message and
summary reason (AC-25).

**Out.** Everything in *Anti-scope* below.

## Approach

### The only source that can hold the answer

The upstream **default branch**. `nexus_clone_to_sibling` (`cli/src/lib.sh:938`)
clones with `origin` set to `${EIDOLONS_REPO:-https://github.com/Rynaro/eidolons}`,
so the freshly cloned `$NEXUS_NEW` already has a remote pointing at the right
place. Measured end-to-end against the real repository and against a `file://`
fixture remote:

```
git -C "$NEXUS_NEW" fetch --depth 1 origin HEAD
git -C "$NEXUS_NEW" show FETCH_HEAD:roster/index.yaml
```

For real v2.20.0 this yields `commit 2cd2d098...`, `tree 85a3c084...`,
`archive_sha256 2bcafa31...`, and all three match a fresh clone of the tag
byte-for-byte. **The upgrade that produced this issue would have printed
`integrity: verified` under this change.**

`origin HEAD` — not `origin main` — is load-bearing, and this is measurable
rather than stylistic. GitHub advertises the symref
(`git ls-remote --symref ... HEAD` -> `ref: refs/heads/main`), so `HEAD` resolves
upstream. The bats fixture remote is created by `git init` with
`init.defaultBranch` unset, so **its** default branch is `master`, and
`fetch --depth 1 origin main` exits 128 against it. A `main` hardcode works in
production and is dead in the harness — the failure mode this repo keeps
shipping. There is no `main` fallback and **no environment override**: the ref
is literally `HEAD`. An undocumented knob that redirects *where trust comes
from* is not a knob this path should have, and `EIDOLONS_REPO` already covers
fork and test redirection.

### Every source that has an opinion must agree

Two sources are consulted: `upstream` (above) and `installed` (`$ROSTER_FILE`,
today's source). For each source that yields a record, every non-empty
non-placeholder field must match the payload. Any disagreement is a mismatch.

This is **monotone**: adding a source can only make verification stricter,
never looser. Two consequences carry the design.

1. The installed roster is the *more independent* witness — it was fetched at
   an earlier time, so it detects "the tag moved since I last synced", which a
   single upstream read cannot.
2. A stale or locally-tampered roster can only ever cause a refusal, never a
   pass. Fail-closed.

> **FALSIFIED AS SHIPPED, and restored by AC-21/AC-22 (revision 1.4.0).**
> Consequence 2 is false against the implementation now in the tree, and it was
> falsified by an independent adversary and then re-measured here by executing
> the shipped helper directly. `_nexus_release_source_status`
> (`cli/src/lib.sh:1040-1089`) **skips** each field comparison when the expected
> value is empty (`:1060`, `:1065-1066`, `:1075-1076`) and then falls through to
> `echo "verified"` (`:1088`). A release record that **exists but carries
> nothing comparable is therefore classified as a positive verification.**
> Measured, all four returning `verified`: `{tag, released_at}` only; all three
> fields present but empty; a non-object scalar; and `commit` absent while
> `tree`/`archive_sha256` hold `<`-sentinels (the sentinel *classification* is
> keyed on `.commit` alone at `:1056`, while the other two are silently skipped).
> `{tag, released_at}` is **schema-legal** — `schemas/roster.schema.json:41`
> requires only `tag` and `released_at`.
> Both directions land. Upstream + a moved tag installs a backdoored payload at
> `✓ (integrity: verified)`, exit 0. **The same shape written into the
> *installed* roster — one file write, no hash knowledge, no origin control —
> turns a `strict` refusal into `✓ (integrity: verified:local-only)`, exit 0.**
> The critic's B-1 severity rule does close the neighbouring `commit: "<x"`
> route (confirmed: it refuses); the class around it stayed open, because every
> criterion in revisions ≤ 1.3.0 built records that *had* hashes. AC-16b
> reaches the placeholder and never builds a record with missing hash fields.
> **A monotonicity argument protects you only from sources that disagree; it
> says nothing about a source that agrees vacuously.** That is the gap: the
> record reasoned about *conflict* between sources and never about *emptiness*
> within one.

A source-vs-source disagreement needs no third code path: the payload can match
at most one of them, so at least one comparison fails and both expected values
are printed.

### Severity-dominant outcome selection

Sources can disagree about **which kind of no-evidence** they hold, and the
policy table gives those tokens opposite outcomes under `strict`. The selector
is therefore part of the contract, not an implementation detail:

```
mismatch  >  corrupt  >  absent  >  network  >  placeholder
```

The most severe outcome reported by **any** source wins. Two reasons, both
measured rather than argued:

- **It is a live input, not a corner.** After `push_fixture_tag "1.0.1"` the
  fixture's upstream roster holds `<filled-by-release-workflow>` for `1.0.1`
  while the installed roster holds no entry at all — measured. Without a
  selector, `strict` gives exit 0 or exit 5 for that state depending on an
  unwritten rule, and AC-4 and AC-9 contradict each other.
- **It closes a local-write downgrade.** An actor with only local file write —
  strictly weaker than origin control, which this change explicitly does not
  defend against — cannot forge a hash, but can write `commit: "<x"` into the
  installed roster. Under a placeholder-dominant rule that converts a `strict`
  refusal into a completed upgrade. Under severity-dominance the other source's
  `absent` (or its real value) dominates, and the refusal stands.

### Facts in the helper, policy at the call site

`nexus_verify_release` classifies evidence; `upgrade_self.sh` decides what to do
about it. This mirrors `verify.sh:68` and `doctor.sh:230`, which both consult
`integrity_enforcement_mode` at their own call sites.

Return codes (`0/2/3` keep today's meaning; `4` is new):

| rc | meaning |
|---|---|
| 0 | verified — some source supplied a real value and every source agreed |
| 2 | mismatch |
| 3 | corrupt clone (HEAD unresolvable) |
| 4 | no evidence — see `NEXUS_VERIFY_STATUS` for which kind |

Detail rides a **variable**, `NEXUS_VERIFY_STATUS`, not stdout. The current
caller does not capture stdout (`nexus_verify_release "$V" "$D" || _verify_rc=$?`),
so anything echoed would land raw in the user's terminal.

#### Three names, kept apart

One outcome is named at three layers. Merging any two of them is how a
criterion ends up asserting a string the implementation never emits — which is
exactly what happened to AC-17 in revisions ≤ 1.2.0 of this record.

| Layer | Name | Written by | Values |
|---|---|---|---|
| **evidence** | `NEXUS_VERIFY_STATUS` — a *variable value* | `nexus_verify_release`, and nothing else | closed set of **seven**: `verified` · `verified:local-only` · `absent` · `placeholder` · `network` · `mismatch` · `corrupt` |
| **outcome** | `skipped:non-tag` — an *outcome label*, this record's vocabulary only | nobody | not a value of any variable and **not a string the implementation contains**: `grep -rn 'skipped:non-tag' cli/src/` returns nothing, by design. It names the `—` row of the policy table below |
| **display** | the *summary string* (`INTEGRITY_TOKEN` in the implementation) | the call site in `upgrade_self.sh` | `verified` · `verified:local-only` · `UNVERIFIED - <evidence>` · `UNVERIFIED - non-tag ref` |

Only the display layer is observable on the terminal line, so only the display
layer may be asserted there. A criterion that puts an evidence value or an
outcome label on the summary line is asserting something no user ever sees and
no test can read.

On the `else` branch `nexus_verify_release` is never called, so
`NEXUS_VERIFY_STATUS` is **never assigned** there. That is not an omission, it
is the mechanism: **every read of the variable must be
`${NEXUS_VERIFY_STATUS:-}`** precisely because the variable is genuinely unset
on that path. `set -euo pipefail` is on at line 24, so an unguarded expansion
aborts with `unbound variable` immediately before the summary — turning a
cosmetic gap into a crash — and AC-18 exists to prove the caller survives it.

> **Withdrawn (revision 1.3.0).** Revisions ≤ 1.2.0 said "`skipped:non-tag` is
> set on the `else` branch" one line above the sentence requiring every read to
> tolerate it being unset. Both cannot hold. Assigning a classifier's output
> token from the branch that never runs the classifier is a caller forging a
> classifier result, and it would make **AC-18 unfailable** — a caller cannot
> be shown to survive an unset variable if the variable is always set. The
> label stays as a policy-table row name; the assignment is withdrawn; the
> variable's closed set is **seven**, not eight.

### Policy table

| rc | evidence value (rc 0–4) / outcome label (—) | `strict` | `warn` | `--allow-unverified` |
|---|---|---|---|---|
| 0 | `verified`, `verified:local-only` | proceed | proceed | (no effect) |
| 2 | `mismatch` | **refuse, exit 5** | **refuse, exit 5** | **still refuses** |
| 3 | `corrupt` | **refuse, exit 5** | **refuse, exit 5** | **still refuses** |
| 4 | `absent` | **refuse, exit 5** | warn + proceed | proceed |
| 4 | `network` | **refuse, exit 5** | warn + proceed | proceed |
| 4 | `placeholder` | warn + proceed | warn + proceed | (no effect) |
| — | `skipped:non-tag` — label only; the summary shows `UNVERIFIED - non-tag ref` | warn + proceed | warn + proceed | (no effect) |

Selected by the severity rule above when sources disagree. Every refusal
removes `$NEXUS_NEW` before exiting, including the rc-4 `strict` refusals —
identical to the rc-2 and rc-3 paths at `upgrade_self.sh:290` and `:296`.

The escape hatch relaxes only the **no-evidence** rows. A detected mismatch is
unconditional — otherwise the flag is not an escape hatch, it is an off switch,
and the gate cannot fail on the defect it names.

`network` (the upstream fetch failed after the clone succeeded) is a distinct
token, never folded into `absent`. Under `warn` it is not worse than today —
today the same situation upgrades silently.

`skipped:non-tag` proceeds under both modes: `--ref <branch|sha>` is an explicit
user opt-in and there is no release record to verify against by construction.
What changes is that it stops **claiming** a verification and starts carrying an
explicit outcome, displayed as `UNVERIFIED - non-tag ref` on the summary line.
The label is how this record refers to that row; the display string is what a
test can observe, and AC-17 asserts the display string.

### An unverified upgrade must not read like a verified one

The terminal line carries the outcome:

```
Upgraded nexus 2.14.1 -> 2.20.0 (integrity: verified)
Upgraded nexus 2.14.1 -> 2.20.0 (integrity: UNVERIFIED - absent)
Upgraded nexus 1.0.0 -> master  (integrity: UNVERIFIED - non-tag ref)
```

One grep, on every path that completes an upgrade — which is what makes the NO
NEW SILENT SUCCESS invariant satisfiable rather than aspirational.

The non-tag warning is **rewritten**, not merely supplemented. It must not
assert that anything was verified; "commit SHA verified" is replaced by a
statement that no release record exists for a non-tag ref and nothing was
checked.

### Shape

- `cli/src/lib.sh` — new `nexus_release_meta_upstream VERSION CLONE_DIR`
  (stdout: the release-metadata JSON object or nothing; stderr: all logging;
  rc 0 = source consulted, rc 1 = source unavailable). Rework
  `nexus_verify_release` into the two-source classifier with the severity rule.
  Both run under `set -euo pipefail`: guard the "print only if non-empty" tail
  with an `if`, not `[ -n "$x" ] && printf`.
  **Revision 1.4.0 — `_nexus_release_source_status` must count what it
  compared.** Track whether any field was actually compared, and classify on
  that count rather than falling through: no comparable field ⇒ `absent`;
  fields present but all `<`-sentinels ⇒ `placeholder` (in **any** of the three
  fields, not `commit` alone); at least one real field compared and matching ⇒
  `verified`. `echo "verified"` must not be reachable from a record that
  compared nothing. Guard the non-object shape too — `jq -r '.commit // empty'`
  on a scalar errors to stderr and yields the empty string, which today lands
  on the same fall-through.
- `cli/src/upgrade_self.sh` — `--allow-unverified` in the `case` parser, the
  policy table at line ~285, the `skipped:non-tag` row on the `else` branch
  (corrected wording + the display string `UNVERIFIED - non-tag ref`; the
  evidence variable is **not** assigned there — see "Three names, kept apart"),
  `${NEXUS_VERIFY_STATUS:-}` at every read, the summary display string, and
  **both** copies of the flag/exit-code documentation (the header comment and
  the `--help` heredoc). Exit 5's *description* in both copies must state that
  5 now also covers "integrity could not be verified, refused under `strict`" —
  the code 5 was already listed, so nothing that compares code **sets** can see
  this (AC-15); it is a description, not a member. **AC-24 is now the gate for
  it**, because this bullet asked for it once already and prose did not carry.
  **Revision 1.4.0 also adds the fail-closed enforcement read (AC-23) HERE, at
  the call site** — trim + `tr '[:upper:]' '[:lower:]'` the environment value,
  accept only `strict`/`warn`, treat everything else (including empty) as
  `strict`; and when the variable is unset, independently confirm `$ROSTER_FILE`
  parses, using `strict` when it does not. `integrity_enforcement_mode` itself
  is **not** touched: it echoes the environment value verbatim (`lib.sh:213-215`)
  and returns the literal `warn` when the roster is unreadable, which is
  indistinguishable at the call site from a roster that says `warn` — hence the
  independent parse check rather than a smarter read of its output. And the
  rc-4 refusal message must name a suppressed upstream witness (AC-25).
- `cli/tests/upgrade_self.bats` — new tests; existing tests unmodified.
- `docs/cli-reference.md` — step 4's metadata source (it names the installed
  roster today, the exact defect this change fixes), the severity rule beside
  its placeholder parenthetical, `--allow-unverified` in the usage block and
  the flag table, exit 5 on absent in the exit-code table (the **third** copy
  of that table — its row 5 reads "Integrity verification failed", which is a
  *description*, and describing a refusal-for-lack-of-evidence as a failed
  check is the same species of false claim this change exists to remove), and
  the two `integrity-verified` claims at lines 769 and 789.
- `README.md` — line 292's `integrity-verified` claim, which is false on
  `933f36b` and true only with this change.
- bash 3.2 throughout: no `declare -A` (a fixed two-element source list and a
  `case` suffice), no `${var,,}` (compare `integrity_enforcement_mode` output
  to `strict` exactly, as `verify.sh` does), no `readarray`, no `&>>`.

## Rejected Alternatives

**A — call `nexus_refresh` before verifying (the issue's remedy 1, score 54).**
Rejected on two independent grounds, either of which is fatal.
*Untestable:* `nexus_refresh` returns 0 immediately when `EIDOLONS_NEXUS` is
set (`cli/src/lib.sh:887`), and `cli/tests/helpers.bash:32` plus
`upgrade_self.bats:121` set it for every test. A fix built on it is inert in the
entire harness — an unfailable gate in a repo whose signature defect is
unfailable gates. *Wrong for a whole channel:* `nexus_refresh` follows
`.roster_ref`, and `stable` is a magic token resolved by `nexus_latest_tag` to
the latest **tag** — whose roster, by construction, still lacks the target's own
metadata. For `stable` users remedy A silently does nothing.

**B — upstream source replaces the installed one (score 74).** Correct on the
reported defect and simpler. Rejected on **monotonicity alone**: dropping a
source can only weaken verification, and the installed roster is the only
witness that predates the current fetch, so it is the only one that can notice
a tag that moved since the last sync.

> An earlier revision of this section rejected B on the ground that it would
> "delete a live guard" by shadowing S6's tamper. **That was false and is
> withdrawn** — S6 never reaches the verification path at all (see the residual
> below), so it stays green under B either way. The monotonicity argument is
> the whole of B's rejection.

**D — reorder the release workflow so a tag carries its own metadata (score 66).**
Genuinely addresses the root construction, and is impossible as stated: the
archive hash is computed *over* the tree that would have to contain it. Any
approximation (detached sidecar, post-tag amend) is a release-process change,
out of scope per the issue, and would not help the installs that already exist.

**C — all-sources-must-agree (score 81.5).** Selected.

## Stories

**S-1 (2d) — metadata source.** `nexus_release_meta_upstream` + the two-source
classifier + the severity rule + `NEXUS_VERIFY_STATUS`. Executor tier:
Sonnet-class or above; the stdout/stderr split and the `set -e` interaction are
the two places this goes wrong quietly. Output contract: `make lint` clean,
`nexus_verify_release` writes nothing to stdout.

**S-2 (1d) — policy, flag, non-tag path.** `--allow-unverified`, the policy
table, the `skipped:non-tag` row with corrected wording and the display string
`UNVERIFIED - non-tag ref`, `${NEXUS_VERIFY_STATUS:-}` guards, the summary
display string, both documentation copies. Output contract:
`--help` exits 0 and names the flag.

**S-3 (3d) — tests.** The fixture-remote scenarios in
`acceptance-criteria.md`, plus the mutation table in `verification.md`.
Highest-value work in the change and the reason the timebox is not smaller:
every new assertion must be shown to fail before it is trusted.

## Risks

| ID | Risk | Tag | Mitigation |
|---|---|---|---|
| R-1 | A corrected metadata record makes an old install's cached value disagree, refusing a legitimate upgrade | P1 | Message names both sources and their values. **`eidolons sync` does NOT clear it for a `stable`-channel install** — a correction lands on `main`, while `nexus_refresh` resolves `stable` to the latest *tag*, so the stale value survives until a new tag is cut. On that channel `--allow-unverified` is the only unblock. Base rate is zero across 20+ releases; documented post-ship, not gated pre-implementation |
| R-2 | `strict` is the shipped default (`roster/index.yaml:13`), so this change turns a warning into a refusal for every user during the release-day window | P0 | Deliberate, per the maintainer's decision; the flag and the env override are both stated in the refusal message |
| R-3 | The metadata fetch adds a network round-trip to every tagged upgrade | P2 | `--depth 1` single-ref fetch into an already-open clone; it runs after the clone, so it cannot make an offline upgrade newly impossible |
| R-4 | `git fetch` into `$NEXUS_NEW` leaves `FETCH_HEAD` and extra objects in the swapped-in nexus | P2 | Both live under `.git/`, so `_nexus_is_dirty`'s porcelain check is unaffected; assert it |
| R-6 | AC-23 normalises enforcement at the upgrade call site while `verify.sh`/`doctor.sh` keep the fail-open read, so two commands can disagree about what `EIDOLONS_INTEGRITY_ENFORCEMENT=STRICT` means | P1 | Deliberate, and the alternative is worse: changing the shared helper reaches the frozen member-integrity path. Recorded in anti-scope with a filed follow-up, so the divergence is a decision with an owner rather than an accident |
| R-5 | Both sources come from the same origin, so this does not defend against a compromised GitHub | P1 | Stated, not claimed away — it defends against drift, corruption, a moved tag, and (via the severity rule) a local-file downgrade. Overclaiming here would itself be a gate that cannot fail |

## Acceptance Criteria

Normative in `acceptance-criteria.md`; machine-readable in `spec.yaml`'s
`acceptance_checks`; mutation evidence in `verification.md`. **Deliberately not
restated here** — the criteria in this family have diverged across four files
before, and a restatement is a copy that rots.

## Confidence

`ramza-score --rubric confidence` -> **83.75 / VALIDATE** (pattern_match 85,
requirement_clarity 90, decomposition_stability 75, constraint_compliance 85).
Independently critiqued by `ramza-critic-561` (refine cycle 1: clarity 4,
completeness 3, actionability 4, efficiency 4, testability 3 -> 3.6, pass),
verdict ACCEPT-WITH-CHANGES, applied in this revision.

## Anti-scope

- **The placeholder sentinel is not repurposed.** `<`-prefixed values keep
  their skip semantics under *both* enforcement modes. They only become
  distinguishable from a verification in the summary. The skip is safe because
  the severity rule prevents a placeholder from masking another source's
  `absent` — **not** because a placeholder is inherently harmless.
- **The integrity source is not configurable.** No environment variable
  redirects which ref the expected metadata is read from; it is `origin HEAD`.
  `EIDOLONS_REPO` already covers fork and test redirection.
- No change to the per-Eidolon member integrity path: `verify.sh`,
  `doctor.sh`, `release_metadata_for`, `release_integrity_status`,
  `_verify_release_integrity_internal`.
- No change to the release workflow ordering (see rejected alternative D).
- No change to `nexus_refresh`'s own contract, and no call to it from
  `upgrade_self.sh`.
- No roster data changes, and **no change to `schemas/roster.schema.json`**.
  Requiring `commit`/`tree`/`archive_sha256` there is filed as a follow-up and
  deliberately not done here: nothing validates the **installed** roster against
  the schema at read time, so a schema change would close nothing on the AC-21
  local-write path while looking like a fix. The read-time classifier is the
  load-bearing repair.
- **`integrity_enforcement_mode` itself is not changed.** AC-23 normalises at
  the `upgrade_self.sh` call site only. The same fail-open read remains on
  `verify.sh:68` and `doctor.sh:230`, which is the frozen member-integrity path;
  that is filed as a follow-up. The asymmetry is deliberate and recorded rather
  than silently created.
- No new exit code. `5` (INTEGRITY_ERROR) covers every refusal.
- `CHANGELOG.md`'s historical entry (line 1764) repeats the `integrity-verified`
  claim and the flag/exit lists. It is **frozen release history** describing
  what v1.x shipped, not a live promise, and is not rewritten to satisfy a gate
  added afterwards — the same exclusion `check_change_specs.sh` makes for
  `archive/`. Recorded so the exclusion is a decision, not an oversight.

## Residual — disclosed

- **`upgrade_self.bats` S6 never reaches the verification path.** Measured, not
  inferred: `upgrade self` without `--force` exits **1** at the dirty-tree
  guard, `nexus_verify_release` is never called, and the string `integrity`
  appears **0 times** in its output. With `--force` the same fixture reaches
  exit 5 with `commit mismatch: got ec554775..., expected 0000000...`.
  The cause is **not** that the fixture's copied CLI scripts differ from the
  cloned ones — `git status --porcelain -- cli` is empty, they are
  byte-identical. The cause is that `upgrade self` **makes the tree dirty
  itself**: `nexus_ensure_roster_ref` at `upgrade_self.sh:84-86` creates
  `$NEXUS/.gitignore`, which is untracked (`?? .gitignore`), and the guard at
  line 180 then fires on a file the command just wrote. Fixing S6, and that
  self-inflicted dirty state, are both out of scope; AC-11 adds the missing
  assertion with `--force` rather than editing a test AC-10 requires to stay
  passing.
  Sharper edge, and why this is a residual rather than a shrug:
  **`docs/cli-reference.md:31` already documents this exact failure as fixed** —
  "Without this heal, a freshly-backfilled `.roster_ref` caused `eidolons
  upgrade self`'s dirty-tree check to refuse the upgrade until `--force` was
  passed" — while the heal is precisely what leaves the tree dirty, by creating
  an untracked `.gitignore`. A documented fix that does not fix **retires the
  search** for the bug. That is how S6 sat vacuous while three artifacts
  described it correctly.
- **Both `S4: respects_ref_flag_for_*` tests are vacuous.** Measured:
  `--ref main` and `--ref <sha>` both exit **1** at `Failed to clone` — the
  fixture remote's default branch is `master`, and `nexus_clone_to_sibling`
  passes `--branch "$tag"`, which cannot take a raw SHA. Both tests assert only
  `status -ne 5`, so they pass without ever exercising the non-tag path. This
  is why the non-tag defect (B-3) survived: its only tests could not see it.
- **A test whose NAME came from the criterion and whose ASSERTION came from
  the code.** `cli/tests/upgrade_self.bats:823` is named
  `AC-17: non-tag ref completes with skipped:non-tag summary, no false
  verification claim` and asserts
  `[[ "$output" == *"(integrity: UNVERIFIED - non-tag ref)"* ]]`. Each half was
  faithful to a different source: the assertion to the code, the name to the
  frozen criterion — and the criterion and the code disagreed. So the suite
  printed `ok 33 AC-17: … skipped:non-tag summary` on every run: **a green line
  that reads as confirmation of a claim nothing checked**, for a string that
  appears nowhere under `cli/src/`. Nothing was broken and nothing was red; the
  divergence was reported as a pass.
  This is the archived `benchmarks-written-from-the-impl` species with the
  disagreement moved *inside a single passing test*. There, an eval's inputs
  were drawn from the implementation, so the suite could not fail; here, one
  test's label and its predicate were drawn from two different sources, so the
  suite could not surface the contradiction it was straddling — it was
  simultaneously the evidence for the criterion and the evidence against it,
  and only the half a machine reads was ever checked. A test name is the one
  string in a suite that humans read as the claim under test and that no tool
  reads as anything at all: it has no verifier, so it is where a stale claim
  survives a green run indefinitely.
  **Mechanical rule, cheap enough to keep:** when a criterion names a literal
  that a test asserts, (a) the criterion must name a string the implementation
  can emit, and (b) the test's name must contain the literal its body asserts.
  A test whose name and assertion diverge is not a cosmetic defect — it is the
  visible end of a gate that has quietly changed what it guards.
- **The non-tag outcome (`skipped:non-tag`, displayed as
  `UNVERIFIED - non-tag ref`) proceeds even under `strict`** — RULED, OQ-4 closed.
  A non-tag ref is an
  explicit `--ref` opt-in with no release record by construction, and refusing
  it would break the documented `--ref <branch>` workflow. Recorded as a
  deliberate trade; the token makes it visible rather than silent.
- **One unexplained `cannot fetch upstream default branch`.** In roughly 40
  adversary runs against a `file://` fixture remote, a single run reported the
  upstream fetch as failed with no attributable cause, and `--allow-unverified`
  then installed the payload. Six fresh fixtures could not reproduce it.
  **Recorded as unexplained rather than dismissed**: a one-in-forty
  intermittent on the exact edge where the gate degrades to the operator's
  judgement is the least acceptable place for an unknown, and "could not
  reproduce" is not "did not happen". If it is real, its effect is to convert
  the strongest witness into `network` at random — AC-25 makes that state
  legible, which is the only mitigation this change offers for it.
- **`nexus_clone_to_sibling` echoes the `nexus.new` path raw to stdout on every
  upgrade** (`lib.sh:946`; the call at `upgrade_self.sh:281` redirects only
  stderr). Pre-existing and documented in that helper's own contract; AC-12
  scopes stdout purity to `nexus_verify_release` alone. Not repaired here —
  recorded so the next reader does not discover it as a regression of this
  change.
- **`--check` gains nothing.** It never clones, so it has no payload to verify
  and still cannot tell a user whether an upgrade would be verifiable.
- **CORRECTION, revision 1.5.0 — `verification.md` calls `yaml_to_json`'s
  `die()`/subshell path unreachable. It is not, and the guard is right.**
  `verification.md` is the maker's artifact and this correction is recorded here
  so it is not lost. Two routes were **executed**, not argued:
  (1) `_YAML_TO_JSON_BACKEND` is `export`ed and memoised — `lib.sh` resolves the
  backend only when the variable is empty (`[[ -z "${_YAML_TO_JSON_BACKEND:-}" ]]
  && _resolve_yaml_to_json_backend`), so an inherited `_YAML_TO_JSON_BACKEND=none`
  skips resolution entirely and `yaml_to_json` falls to its `none|*)` arm;
  (2) a `PATH` carrying coreutils but neither `yq` nor `python3` resolves
  `BACKEND=none` at source time. Both reach `die`. Measured with the subshell,
  the mode resolves `strict` and the caller survives ("reported unparseable,
  caller ALIVE"); measured without it, the script terminates at exit 1 with no
  output at all. **The implementation is correct and verified — only the record's
  claim of unreachability is wrong**, which is the same failure mode this record
  has now paid for three times: an artifact asserting something about the code
  that nobody executed. Worth noting the naive version of route (2) does *not*
  work — an empty `PATH` breaks `lib.sh` at line 15 (`mkdir` not found) before the
  backend is ever resolved, so the route must keep coreutils on `PATH`. A
  reachability claim is only as good as the probe that produced it.
- **rc-3's corrupt-clone detection is weaker than it reads, and is not repaired
  here.** `actual_commit="$(git -C "$clone_dir" rev-parse HEAD 2>/dev/null || echo "")"`
  followed by `[[ -z "$actual_commit" ]]`. Measured: on an initialized-but-empty
  repository `git rev-parse HEAD` exits **128** *and prints the literal string
  `HEAD` on stdout*, so the command substitution captures `HEAD`, `actual_commit`
  is non-empty, and the corrupt branch never fires. **Byte-identical to
  `main:cli/src/lib.sh:998` and to the frozen member path at `main:cli/src/lib.sh:307`**
  (both verified against `git show main:`), so it is neither introduced nor
  worsened by this change; it is fail-closed under `strict` (the run continues to
  the metadata comparison, which finds nothing and refuses) and unreachable via
  `nexus_clone_to_sibling`, which fails the clone outright rather than leaving an
  empty repo behind. Recorded, not fixed — repairing it would reach into the
  frozen member-integrity path this record's anti-scope protects.
