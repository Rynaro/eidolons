# V4-03 — registry publication and wiring validation

Assignment: V4-03 only. Canonical requirement text is the [revision-3 stage table](https://github.com/Rynaro/eidolons/blob/c581308f055a0e252013bf09f2a7b2e1426ff811/docs/campaigns/gauge/00-stabilization.md#v4-03). The unmerged planning branch is read without merging it.

Base: `2e514f280f26a378811f0c9939928584546a35d0`. V4-01 prerequisite was merged as PR #599 after all 25 checks passed, including Ubuntu/macOS CLI suites and block-mode Tonberry conformance. No V4-02 prerequisite exists.

## Scope and acceptance

R01/T01: reject duplicate top-level/nested YAML and JSON keys, including equal-valued duplicates, before last-wins resolution.
R02/T02: publication rejects missing, short, nonhex, or placeholder commit/tree/archive digests; authored/draft permission is not publication permission.
R03/T03: local, PR, and release entrypoints use the same blocking gate. Observe actual PR CI separately from fixture checks; no release dispatch is authorized.
R04/T04: characterize generated hyphenated tool identifiers, invoking UID:GID, spaced paths, identity mounts, and repeat rendering. Repair only reproduced defects.
R05/T05: diagnose installed underscore grants/missing UID or other declared-definition drift without silently overwriting user settings; exercise preview and explicit repair.

Keep Bash 3.2 legacy compatibility, preserve historical release evidence and unrelated user configuration, and avoid broad roster cleanup. No successor packages, source relocation, merge, release, deploy, paid trial, or archive. Publication schemas must distinguish draft input from publishable evidence rather than rewriting history to manufacture a passing baseline.

## Sizing and verification

Complexity 8/12: scope 2 (validation plus wiring), ambiguity 1 (assigned EARS), dependencies 2 (local/CI/release and host generators), risk 3 (publication/integrity). Estimated 15 touched implementation/test/documentation files. Full tier; implementation choices reuse existing boundaries, with no novel-architecture deliberation claimed.

One maker (`vivi_v4_03`), a bounded read-only wiring scout, and a distinct checker (`v4_03_review`). Use the Linux Docker runner, first proving a failed intermediate assertion is detected. The original host Bats/Bash setup missed assertions during V4-01; its green output is not acceptance evidence. Tests must discriminate real gate failures with valid controls and preserve evidence of baseline failures. Record test execution, observed hosted CI, conformance, review context, and any unavailable live evidence separately. Tonberry uses the locked block mode. CRYSTALIUM MCP tools are unavailable; do not fabricate memory operations.
