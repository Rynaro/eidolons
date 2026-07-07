---
Title: ECM portability fixes — SELinux tonberry template default + sha256sum test fallback
Version: 1.0.0
Date: 2026-07-07
Author: orchestrator (scribed; tonberry container writes SELinux-blocked this session)
tier: lite
Target: cli/templates/mcp/tonberry.mcp.json.tmpl, cli/tests/trace_reader.bats, cli/tests/verify_envelope.bats
---

# ECM portability fixes (LITE spec)

## Framing

Two independent, mechanical portability fixes surfaced by the ECM P1 campaign,
bundled as one lite change. Both make the toolchain work on a host class the
current code assumes away.

1. **SELinux tonberry template.** On an SELinux-*enforcing* host, an unlabeled
   Docker bind mount of a `user_home_t` repo tree lets a `container_t` process
   *read* the tree but silently fails every *write* with `EACCES`. The nexus
   tonberry template mounts the whole repo (`__PROJECT_ROOT__:/workspace`) and
   tonberry's job is to *write* the `.spectra/changes/` ESL lifecycle — so on
   such a host every `propose`/`transition`/`archive` fails while reads
   (`list`/`status`/`verify --dry`) succeed, a diagnostically nasty asymmetry
   that reads as a tonberry bug. Adding the `:z` shared-relabel option makes the
   container writes succeed.

2. **sha256sum-only hosts.** Two test helpers (`_mkhop`, `_mkenv`) called bare
   `shasum -a 256`. On a host that ships `sha256sum` but not `shasum` (the
   CI/dev sandbox), that emits an empty SHA and cascades into spurious
   integrity-mismatch failures across the ECL trace/envelope suites.

## Scope / non-goals

- IN: append `:z` to the tonberry template workspace mount; add the portable
  `{ shasum … 2>/dev/null || sha256sum …; }` fallback to the two bare-`shasum`
  test helpers.
- OUT: the crystalium template (its dedicated `$HOME/.crystalium/` data-dir
  mount is a different label class and is *proven working* — no speculative
  churn); atlas-aci (`:ro`, reads already work on SELinux); any CLI-source
  `shasum` call (all already carry a `sha256sum` fallback); the local
  `.mcp.json` (already fixed out-of-band this session).

## Design notes

- `:z` (shared) not `:Z` (private): the same repo tree is bind-mounted read-only
  by atlas-aci; a private MCS label would lock that peer out. `:z` relabels to a
  shared `container_file_t` type any container can use.
- `:z` is a no-op on Docker daemons without SELinux — safe as a template default
  for every consumer, not just SELinux hosts.
- Reported upstream: Rynaro/tonberry#3 (EACCES-hint UX + docs + this template
  default). This change is the nexus-side half of that cross-reference.

## Acceptance checks (EARS / GIVEN-WHEN-THEN)

**AC-1 — tonberry template carries the SELinux relabel default.**
GIVEN a consumer project renders `.mcp.json` from the nexus tonberry template,
WHEN `eidolons` substitutes `__PROJECT_ROOT__`,
THEN the workspace bind mount reads `<root>:/workspace:z`, restoring container
writes on SELinux-enforcing hosts and remaining inert elsewhere.
- verify_method: `grep ':/workspace:z' cli/templates/mcp/tonberry.mcp.json.tmpl`.

**AC-2 — the ECL trace/envelope tests pass without `shasum`.**
GIVEN a host with `sha256sum` present and `shasum` ABSENT,
WHEN `bats cli/tests/trace_reader.bats cli/tests/verify_envelope.bats` runs,
THEN all 22 tests pass (the `_mkhop`/`_mkenv` helpers fall back to `sha256sum`).
- verify_method: `command -v shasum` empty + `sha256sum` present, then the two
  bats files 22/22 (observed 2026-07-07).

## Notes for the executor

- Three localized edits; no bash 4 features; all shell stays 3.2-safe.
- The fallback brace group mirrors the existing `cli/src/sandbox.sh` idiom
  (`{ shasum -a 256 "$f" 2>/dev/null || sha256sum "$f"; } | awk '{print $1}'`).
