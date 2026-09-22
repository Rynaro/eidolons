# V4-02 — Legacy upgrade and user-change preservation

Assignment: V4-02 only. Authority: [revision-3 stage table](https://github.com/Rynaro/eidolons/blob/c581308f055a0e252013bf09f2a7b2e1426ff811/docs/campaigns/gauge/00-stabilization.md#v4-02) and [execution contract](https://github.com/Rynaro/eidolons/blob/c581308f055a0e252013bf09f2a7b2e1426ff811/docs/campaigns/gauge/HANDOFF.md). Read the planning branch without merging it.

Plan commit: `c581308f055a0e252013bf09f2a7b2e1426ff811`. Implementation base: `2e514f280f26a378811f0c9939928584546a35d0`, merged V4-01 (#599), whose 25 checks passed. V4-03 remains separate draft PR #600; it is not a prerequisite and is not imported here.

## Scope and acceptance

- R01/T01: repeated --check on v1.41.0 and a supported earlier legacy fixture must not create tracked dirtiness. Pin real fixture source revisions and distinguish reduced fixtures from whole installations.
- R02/T02: real .gitignore and source edits must stop destructive upgrade with exact user bytes preserved. Never blanket-ignore .gitignore or call managed drift genuine user modification.
- R03/T03: valid local, integrity-verified replacement upgrades affected legacy, v1.41.1 control, v2.20 and current v3 fixtures without --force or another integrity bypass.
- R04/T04: failures/interruptions at download, extraction, integrity and smoke boundaries retain a usable old tree/binary and user settings. Prove the intended gate, not an unrelated early exit.
- R05/T05: repeat an already completed upgrade without unintended settings changes, including dirty consumer workspaces and host settings.

Repair issue #566 with a small coherent change, retain strict V4-01 semantics and Bash 3.2 compatibility, and correct the existing CLI documentation about tracked .gitignore healing. Test local fixtures, not production installations. No V4-03 edits, successor packages, merge, release, deployment, paid trials, archive, new bypass, or broad runtime redesign. Do not claim that patching this repository retroactively replaces an installed legacy executable; document the tested invocation boundary honestly.

## Sizing and verification

Full tier, rubric 8/12: scope 2, ambiguity 1, dependencies 2, risk 3; estimated eight implementation/test/documentation files. Existing upgrade and exclusion boundaries are reused; no novel-architecture or real competing architecture decision is claimed, so optional deliberation is omitted.

Maker: vivi_v4_02; distinct checker: v4_02_review. One source writer at a time. Establish requirement-derived failing behavior before repair and use valid controls. Qualify the isolated Linux runner with a deliberately failing intermediate assertion; original host Bats under Bash 3.2 incorrectly passes that probe. Hosted Bats must use a qualified modern Bash; retain separate Bash 3.2 CLI syntax checking. Observe hosted Ubuntu/macOS CI separately. Tonberry 0.5.2 is locked with block enforcement; record real lifecycle operations before code. CRYSTALIUM MCP tools are unavailable: skip honestly, without direct memory access. Keep the main checkout and user's untracked work untouched.
