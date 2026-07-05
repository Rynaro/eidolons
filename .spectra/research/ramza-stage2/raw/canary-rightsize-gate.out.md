# RAMZA canary: rightsize-gated rename plan

## Narrative

Ran the real RAMZA gate chain from `/tmp/ramza-e2e` against `.eidolons/ramza/bin`.

`ramza-rightsize --files-est 1 --stakes low --plan rename-getuserdata --state .spectra/plans/rename-getuserdata/rename-getuserdata.state.json` printed:

```
state initialised: .spectra/plans/rename-getuserdata/rename-getuserdata.state.json (tier: trivial, score: 0)
trivial
```

Score 0 (files-est 1 ⇒ 0, no flags, stakes low ⇒ 0) ⇒ **tier trivial**. Per RAMZA's tier table, trivial mandates only **RS → S → C → A**; Pattern and Explore are not tier-mandatory at trivial (this is a tier omission, not a `--reason`-requiring skip), and neither is Test beyond the mechanical `ramza-lint` check baked into A.

Executed via real tool calls, in order:
- `ramza-gate advance --to S` → `OK: RS -> S`
- `ramza-score --rubric complexity` on `{scope:1,ambiguity:1,dependencies:1,risk:1}` → total 4, verdict `standard`
- `ramza-gate advance --to C` → `OK: S -> C` (no `--reason` required — P/E aren't mandatory for this tier)
- Authored the plan artefact below
- `ramza-gate advance --to A` → `OK: C -> A`
- `ramza-score --rubric confidence` → total 97.5, verdict `AUTO_PROCEED`
- `ramza-freeze --criteria <acceptance-criteria-slice>` → `frozen: e893304c870034e356dfece4c5636e4a6cb985e790f2309296bcdf1fd79b3c0d`
- `ramza-drift --declare 'src/**/*'` → `scope declared: 1 glob(s)`
- `ramza-gate advance --to DONE` → `OK: A -> DONE`

Final `ramza-gate status`: `{"phase":"DONE","tier":"trivial","refine_cycles":0,"skips":[],"criteria_frozen":true}`.

## Plan artefact (`rename-getuserdata.plan.md`)

```markdown
# Plan: Rename `getUserData` → `fetchUserProfile`

## Scope

- Single file, single module. Rename the function `getUserData` to
  `fetchUserProfile` and update its 3 call sites, all within the same file.
- No new dependency, no public API surface change, no migration, no
  security implications. Tier: **trivial** (RS score 0 — files-est 1 ⇒ 0,
  no flags set, stakes low ⇒ 0; 0 <= 1 ⇒ trivial).
- Out of scope: any cross-file/cross-module references, export renames,
  changelog/versioning, or test-file updates beyond the same module if a
  co-located test calls the function directly.

## Approach

1. Locate the function definition `getUserData` in the target file.
2. Rename the definition to `fetchUserProfile` in place (signature and body
   untouched — name change only).
3. Update all 3 in-module call sites to reference `fetchUserProfile`.
4. Grep the file (not the repo) to confirm zero remaining references to
   `getUserData` and exactly 4 occurrences of `fetchUserProfile` (1
   definition + 3 call sites).
5. No refactor of call-site arguments, no behavior change — this is a pure
   identifier rename.

## Acceptance Criteria

- WHEN the file is searched for `getUserData`, THEN zero matches remain.
- WHEN the file is searched for `fetchUserProfile`, THEN exactly 4 matches
  are found (1 definition + 3 call sites).
- WHEN the file's existing test/build step (if any) is run, THEN it passes
  unchanged (no behavior, signature, or return-type change).
- WHEN the diff is reviewed, THEN it touches only the single target file
  declared in scope.
```

(34 lines, well under the 120-line trivial budget; only `## Scope`, `## Approach`, `## Acceptance Criteria` present.)

## Lint statement

Ran `ramza-lint --plan .spectra/plans/rename-getuserdata/rename-getuserdata.plan.md --tier trivial` for real; output:

```
ok: plan passes structural lint (tier: trivial)
```

Exit code 0. The plan passes lint at `--tier trivial` specifically because it carries exactly the three trivial-required sections (Scope, Approach, Acceptance Criteria) and no more, and stays at 34 lines (< 120). It would **not** pass a `lite` or `full` invocation as-is, since those tiers additionally require `## Stories` and `## Confidence` (full also `## Rejected Alternatives` and `## Risks`) — which are deliberately omitted here because the rightsize score (0) never crossed into lite/full territory.
