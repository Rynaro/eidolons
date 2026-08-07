# Campaign-wide finding — the worktree exit gate is 2 tests weaker than the main checkout

Found by the W-ENTRY implementer, independently verified by the orchestrator 2026-08-05.
Applies to EVERY unit in this campaign, because the plan mandates one worktree per unit.

## The gap

`mcp-server/tests/test_roundtrip_handoff.py:34`:
```python
pytestmark = pytest.mark.skipif(
    not _fixtures_dir().exists(), reason="roster fixtures not mounted"
)
```
Its fixtures live at `.eidolons/apivr/templates/inbound/*.envelope.fixture.json`, and
`.eidolons/` is **gitignored** (`.gitignore:32`, reinforced at `:48`). Git worktrees
materialise only TRACKED content, so the directory is present in the main checkout and
**absent in every worktree**. Verified:

```
MAIN     -> .eidolons/apivr/templates/inbound/{reasoning-report,root-cause-report,scout-report}.envelope.fixture.json
WORKTREE -> No such file or directory
```

## Consequence — and why it matters more than it looks

The two tests **SKIP**, they do not fail. A worktree suite therefore reports GREEN while
running two fewer tests than the baseline it is being compared against. Reconciled exactly
on W-ENTRY:

| suite | main @ b7f1a47 | ZERO-UNIT worktree | delta |
|---|---|---|---|
| `make test`    | 998 passed / 2 skipped | **996 passed / 4 skipped** | -2 passed, +2 skipped |
| `make test-ci` | 994 passed / 6 skipped | **992 passed / 8 skipped** | -2 passed, +2 skipped |

**THE ZERO-UNIT WORKTREE BASELINE IS 996 / 992.** Confirmed twice by execution:
W-ENTRY (+1 test) -> 997 / 993; W-RIG (+36 tests) -> 1032 / 1028. Both reconcile exactly
(`996+1`, `996+36`, `992+1`, `992+36`).

**Orchestrator error, corrected here:** an earlier relay of this finding stated the worktree
baseline as 997/993. That was W-ENTRY's result INCLUDING its own new test, not the zero-unit
baseline. The W-RIG implementer did not take the relayed number on trust — it re-verified
against repo state and let the actual runs arbitrate, which is how the off-by-one surfaced.
Recorded because a wrong baseline propagated by authority is exactly the failure this
campaign keeps finding in other forms.

**"`make test` green in a worktree" does not establish "`make test` green in the checkout
that gets tagged."** This is the same species as the campaign's other findings: a check that
passes while covering less than it appears to. It is low-risk here (both tests were green at
baseline, and no unit touches the ECL handoff path), but it is unrecorded coverage loss and
would have been rediscovered per-unit as a mystery arithmetic drift.

## Binding rules for the rest of the campaign

1. **Every unit reporting an exit gate from a worktree MUST use the worktree-adjusted
   baseline** (997 / 993 plus its own new tests), not the main-checkout baseline
   (998 / 994). A unit reporting a shortfall against 998/994 as a regression is
   misreading THIS gap, not finding a defect.
2. **The v2.0.2 and v2.1.0 RELEASE gates MUST run in a checkout where those fixtures exist**
   — i.e. the main checkout, or a worktree with `.eidolons/apivr/templates/inbound/`
   materialised. A release tagged on worktree-only evidence has 2 untested tests. Add to
   both release checklists.
3. The skip reason is `"roster fixtures not mounted"`, which is accurate but easy to scroll
   past. Any unit seeing an unexpected passed/skipped count must reconcile the arithmetic
   BEFORE reporting a regression.

## Not fixed here, deliberately

Materialising the fixtures in worktrees is outside every unit's declared ownership (§2), and
`.eidolons/` is gitignored by design (it is `eidolons sync` output, not source). Recording the
gap and pinning the release gate to a fixture-bearing checkout is the correct-cost fix.
Filing a repo-side improvement (make the skip loud, or vendor the fixtures) is a legitimate
follow-up issue but is NOT in this campaign's scope and must not be smuggled into a unit.
