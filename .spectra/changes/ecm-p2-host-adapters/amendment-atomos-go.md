# Amendment — Track H retired (atomos GO)

**Date:** 2026-07-07
**Change:** `ecm-p2-host-adapters`
**Authority:** maintainer decision (overrides the FORGE recommendation in
`docs/specs/ecm/decisions/atomos-go-no-go.md`; see that record's §0 override).

## What changed

RAMZA's frozen acceptance criteria (`acceptance-criteria.md`, SHA
`629b0f10200d9fba6e01c187b9a8af3961953042c2de7a63c4a5335c8573281f`) included a
**Track H** wiring the atomos *delete-at-P2-exit* tripwire, per FORGE's original
NO-GO-with-tripwire verdict:

- **AC-TW-1** — all wired hosts PASS `canary --context-handoff` via kernel+hooks ⇒
  the atomos P3 roadmap line is deleted.
- **AC-TW-2** — an injection-surface canary failure routes to a host plugin/shim,
  never to atomos.

The maintainer has since decided **atomos is a GO** — a committed P3 build (a
compose/verify executor MCP, tonberry-analog, fenced to brief composition +
pin/envelope verification). That decision **supersedes** Track H:

- **AC-TW-1 is RETIRED** — there is no atomos deletion; atomos builds in parallel at
  P3, *informed by* P2 field evidence, not gated by it.
- **AC-TW-2 is RETIRED** — atomos is no longer conditional on an injection-surface
  outcome; injection remains a host-surface concern (plugin/shim) *and* atomos ships
  regardless, fenced to compose/verify.

## Why the frozen SHA is preserved (not re-cut)

The freeze is a tamper-evidence anchor for the criteria RAMZA authored and Vivi
implements — **Tracks A–G (31 checks)**, which are entirely unaffected by this
decision (Track H was a P2-exit *gate procedure*, never code). Rather than re-cut the
SHA and lose the anchor for the implemented criteria, `acceptance-criteria.md` is kept
**byte-identical** and this file records the Track-H retirement as an amendment delta
— the ESL living-spec / amend-with-reason pattern. A checker verifies Tracks A–G
against the frozen SHA and treats AC-TW-1/AC-TW-2 as retired (no code to verify).

## Net effect on implementation

**None.** Vivi implements Tracks A–G exactly as specified. Track H produced no code
and no longer gates anything. The atomos build is a separate P3 campaign (a new
`Rynaro/atomos` MCP repo + image), scoped in `docs/specs/ecm/decisions/atomos-go-no-go.md`
§0.
