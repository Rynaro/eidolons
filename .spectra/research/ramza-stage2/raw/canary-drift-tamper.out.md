# RAMZA Canary: Frozen-Acceptance-Criteria Tamper Detection

**Scenario under test:** A plan's acceptance criteria were frozen at Assemble
with

```
ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md
```

Afterward, someone hand-edited `.spectra/plans/demo.acceptance.md` directly —
adding a new `THEN` clause to `AC-002` — **without** running
`ramza-freeze --amend --reason`.

Question: what does

```
ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md --verify
```

report? This was not answered from the tool's help text or from general
principle — it was reproduced end-to-end against the real `bin/ramza-freeze`
executable installed at `.eidolons/ramza/bin/ramza-freeze` in the consumer
project `/tmp/ramza-e2e`. Every command below, and every line of output
quoted, is copy-pasted from an actual terminal session, not paraphrased.

**Short answer up front:** the tool does **not** silently accept the edit.
`--verify` recomputes the SHA-256 of the current criteria file, compares it
against the `criteria_sha256` value locked into the state file at freeze
time, finds a mismatch, prints a `DRIFT:` report to stderr showing both
hashes plus a count of recorded amendments, and **exits 1**. There are
exactly two legitimate ways out: `ramza-freeze --amend --reason "<why>"`
(records the change with a reason and a hash-chain entry), or reverting the
file to match the frozen content. Nothing else clears the drift.

---

## How `ramza-freeze` actually works (read from source, not assumed)

`bin/ramza-freeze` is a small `set -eu` bash script with three modes
(`freeze` / `verify` / `amend`), gated by `--verify` / `--amend`. The
mechanism, read directly from the script:

```sh
HASH=$(sha256_of_file "$CRITERIA")
CUR=$(jq -r '.criteria_sha256 // empty' "$STATE")
...
verify)
  [ -n "$CUR" ] || deny "criteria were never frozen (nothing to verify against)"
  if [ "$HASH" = "$CUR" ]; then
    say "ok: criteria match frozen hash"
    exit 0
  fi
  printf 'DRIFT: criteria hash mismatch\n  frozen:  %s\n  current: %s\n' "$CUR" "$HASH" >&2
  AM=$(jq -r '.amendments | length' "$STATE")
  printf 'Criteria were edited after freeze without ramza-freeze --amend (%s recorded amendment(s)).\n' "$AM" >&2
  exit 1
  ;;
```

So on every `--verify` invocation the tool:
1. Recomputes `sha256(criteria file)` fresh, from the file's current bytes on
   disk — it never trusts a cached value.
2. Reads `criteria_sha256` back out of the state file — the value written by
   the original `ramza-freeze` (no `--verify`/`--amend`) call.
3. Compares the two strings. Equal → `ok`, exit 0. Unequal → `DRIFT:` report
   to stderr with both hashes, plus how many `amendments` are already on
   record (so a reviewer can tell "was this an untracked edit, or did
   somebody amend and then edit again on top of that"), then **exit 1**.

The freeze/verify contract is also declared in the shipped template
(`templates/acceptance-criteria.md`, "Frozen at Assemble" section, written
independently of this run):

> "Editing the criteria after freeze without `ramza-freeze --amend --reason`
> makes a later `ramza-freeze --verify` fail — that hash mismatch IS the
> tamper signal, never a re-derivable 'looks different' judgment."

That is exactly what was reproduced below.

---

## Step-by-step reproduction (real commands, real output)

All commands run from `/tmp/ramza-e2e` with
`RAMZA_BIN=.eidolons/ramza/bin`. Scratch reproduction lives at
`.spectra/plans/demo.state.json` / `.spectra/plans/demo.acceptance.md`
inside that consumer project, per the mission's exact filenames.

### Step 1 — Right-size and initialize plan state (Assemble precursor)

```
$ .eidolons/ramza/bin/ramza-rightsize --files-est 4 --stakes med --plan demo --state .spectra/plans/demo.state.json
state initialised: .spectra/plans/demo.state.json (tier: lite, score: 2)
lite
exit=0
```

This produced a `ramza/plan-state.v1` file with `"criteria_sha256": null` —
nothing frozen yet.

### Step 2 — Author the acceptance criteria (EARS form)

`.spectra/plans/demo.acceptance.md` was written with two EARS blocks,
`AC-001` (event-driven) and `AC-002` (unwanted-behavior), matching the
template's closed grammar (`GIVEN`/`WHEN`/one `THEN`/`VERIFY:`). Lint
confirmed the file was well-formed before freezing:

```
$ .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/demo.acceptance.md
ok: 2 criteria pass EARS lint
lint exit=0
```

`AC-002` at this point read:

```
### AC-002 (unwanted-behavior)
GIVEN the demo service has no valid session token
WHEN a request arrives at /demo/secure
THEN the endpoint SHALL respond HTTP 401 with {"error":"unauthorized"}
VERIFY: test: spec/requests/demo_spec.rb#responds_unauthorized
```

### Step 3 — Freeze at Assemble exit

```
$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md
frozen: 14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b
14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b
freeze exit=0
```

State file afterward:

```json
{
  "criteria_sha256": "14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b",
  "criteria_frozen_at": "2026-07-05T02:04:24Z",
  "amendments": []
}
```

This equals `sha256sum .spectra/plans/demo.acceptance.md` computed
independently at the same moment — confirmed byte-for-byte:

```
$ sha256sum .spectra/plans/demo.acceptance.md
14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b  .spectra/plans/demo.acceptance.md
```

Sanity check — `--verify` immediately after freeze, before any edit, passes
clean:

```
$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md --verify
ok: criteria match frozen hash
verify(before) exit=0
```

### Step 4 — The tamper: hand-edit `AC-002` directly, bypassing `--amend`

A second `THEN` line was appended to `AC-002` with a plain file edit — no
`ramza-freeze --amend --reason` was run, exactly as the scenario specifies:

```
### AC-002 (unwanted-behavior)
GIVEN the demo service has no valid session token
WHEN a request arrives at /demo/secure
THEN the endpoint SHALL respond HTTP 401 with {"error":"unauthorized"}
THEN the endpoint SHALL log the unauthorized attempt with client IP and request path
VERIFY: test: spec/requests/demo_spec.rb#responds_unauthorized
```

(Note in passing: this particular hand-edit is *also* independently an EARS
violation — `ramza-ears-lint` rejects a block with more than one `THEN` line.
That is a separate, additional gate; it is not what `ramza-freeze --verify`
checks. `--verify` cares only about the frozen SHA-256 of the whole criteria
file, not about the file's grammar.)

New hash of the tampered file:

```
$ sha256sum .spectra/plans/demo.acceptance.md
65bd351a79c3adc95d51c972b48af909f9f84ab23979bafd1a34815f95767e43  .spectra/plans/demo.acceptance.md
```

State file's `criteria_sha256` is untouched (no amend was run):

```
$ jq -r '.criteria_sha256' .spectra/plans/demo.state.json
14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b
```

### Step 5 — Run the exact command from the mission

```
$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md --verify
```

**Real, unedited output (stderr):**

```
DRIFT: criteria hash mismatch
  frozen:  14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b
  current: 65bd351a79c3adc95d51c972b48af909f9f84ab23979bafd1a34815f95767e43
Criteria were edited after freeze without ramza-freeze --amend (0 recorded amendment(s)).
```

**Real exit code:** `1`

Confirmed directly:

```
$ echo $?
1
```

This is the tamper signal, exactly as designed: the tool does not evaluate
whether the edit to `AC-002` is "reasonable," "small," or "obviously an
improvement" — it has no mechanism for that kind of judgment call at all.
It compares two SHA-256 digests. `frozen` (recorded at Assemble,
`14116c22…`) and `current` (recomputed right now from the file on disk,
`65bd351a…`) differ, therefore the criteria drifted from what was frozen,
therefore `--verify` reports `DRIFT` and returns exit code 1 — a hard
failure any calling script or CI gate would see, not a warning. The
"`0 recorded amendment(s)`" clause is itself informative: it tells a
reviewer that this drift wasn't produced by a legitimate, logged amendment
that simply hasn't been re-verified yet — it is a raw, untracked edit with
zero paper trail.

---

## The two legitimate remediations (both reproduced)

`ramza-freeze`'s own usage text names exactly these two paths — there is no
third. Both were exercised for real, not asserted:

### Remediation 1 — Revert the hand-edit back to the frozen content

```
$ cp /tmp/ramza-s2/demo.acceptance.md.before-tamper .spectra/plans/demo.acceptance.md
$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md --verify
ok: criteria match frozen hash
exit=0
```

Restoring the exact frozen bytes makes the recomputed hash match
`criteria_sha256` again; `--verify` returns to `ok` / exit 0. This is correct
when the hand-edit to `AC-002` was accidental or premature and the frozen
criteria should stand as-is.

### Remediation 2 — `ramza-freeze --amend --reason "<why>"`

The tamper was re-applied to `AC-002` (the added `THEN` line), then amended
properly instead of frozen silently:

```
$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md --amend --reason "AC-002: added audit-logging THEN clause for unauthorized attempts"
amended: 14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b -> 65bd351a79c3adc95d51c972b48af909f9f84ab23979bafd1a34815f95767e43 (reason: AC-002: added audit-logging THEN clause for unauthorized attempts)
amend exit=0

$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/demo.state.json --criteria .spectra/plans/demo.acceptance.md --verify
ok: criteria match frozen hash
verify(after amend) exit=0
```

`--amend` requires `--reason` (the script hard-denies otherwise:
`--amend requires --reason (amendments are recorded, never silent)`), and it
appends a hash-chained record to the state file's `amendments` array rather
than overwriting history:

```json
[
  {
    "prev": "14116c221216fd547d91d5def4486d2cce9b2d974469b38afe4a5510fb6e303b",
    "new": "65bd351a79c3adc95d51c972b48af909f9f84ab23979bafd1a34815f95767e43",
    "reason": "AC-002: added audit-logging THEN clause for unauthorized attempts",
    "at": "2026-07-05T02:05:09Z"
  }
]
```

This is correct when the change to `AC-002` is a deliberate, wanted revision
to the acceptance criteria — it re-freezes the new content under
`criteria_sha256` *and* leaves a permanent, reasoned audit trail of exactly
what changed (`prev` hash → `new` hash) and why. Nothing is ever silently
re-frozen: the `prev`/`new` pair on every amendment record means a reviewer
can always answer "what did the criteria look like before, and what
justified the change," which is precisely the property freeze is designed to
protect (per `ramza-freeze`'s own header comment: "Freeze = tamper-EVIDENCE,
not immutability: `--amend` is a first-class, hash-chained, reasoned
operation").

---

## Summary — what the tooling does, stated plainly

1. `ramza-freeze` (no flags beyond `--state`/`--criteria`) hashes the
   criteria file with SHA-256 and stores it as `criteria_sha256` in the
   plan-state JSON at Assemble exit. It refuses to re-freeze
   (`deny: criteria already frozen`) if a hash is already present.
2. A direct hand-edit to the criteria file after freeze — such as adding a
   second `THEN` line to `AC-002` — changes the file's bytes and therefore
   its SHA-256, but does **not** touch `criteria_sha256` in the state file.
   The two values silently diverge on disk; nothing about the edit itself
   triggers any check.
3. `ramza-freeze --verify` is the only thing that surfaces this divergence.
   It recomputes the hash from the current file, compares it to the frozen
   value, and on mismatch prints `DRIFT: criteria hash mismatch` with both
   the `frozen:` and `current:` hashes plus a count of recorded amendments,
   to **stderr**, and returns **exit code 1**. It never returns 0 on a
   mismatch, and it has no "close enough" or fuzzy-diff behavior — it is a
   pure byte-hash equality check.
4. The only two ways to clear the drift are: (a) revert the file to the
   exact frozen content, restoring hash equality; or (b) run
   `ramza-freeze --amend --reason "<why>"`, which requires a non-empty
   reason, records a hash-chained `{prev, new, reason, at}` entry in
   `amendments`, and re-freezes the new content as the current
   `criteria_sha256`. There is no flag or code path that accepts the
   post-freeze edit to `AC-002` (or any criterion) without either reverting
   it or explicitly reasoned-amending it — the tool was read end-to-end
   (`bin/ramza-freeze`, all three modes) and no silent-accept branch exists.

Artifacts from this reproduction (for reference, not required reading):
`/tmp/ramza-e2e/.spectra/plans/demo.state.json`,
`/tmp/ramza-e2e/.spectra/plans/demo.acceptance.md`,
`/tmp/ramza-s2/demo.acceptance.md.before-tamper`,
`/tmp/ramza-s2/demo.state.json.after-drift`.
