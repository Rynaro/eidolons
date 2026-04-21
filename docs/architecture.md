# Eidolons Architecture

> How the nexus, EIIS, individual Eidolon repos, and consumer projects compose.

---

## The three layers

```
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 1 — STANDARD (Rynaro/eidolons-eiis)                           │
│                                                                      │
│   Defines what every Eidolon repo must contain and expose.          │
│   - install.sh CLI contract                                         │
│   - install.manifest.json schema                                    │
│   - Required file layout                                            │
│   - Host wiring requirements                                        │
│                                                                      │
│   Vendor-neutral. Versioned independently. Does not ship agents.    │
└─────────────────────────────────────────────────────────────────────┘
         ▲
         │ each Eidolon repo declares conformance (EIIS_VERSION file)
         │
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 2 — EIDOLONS (5 × individual repos)                           │
│                                                                      │
│   Rynaro/ATLAS    Rynaro/SPECTRA   Rynaro/APIVR-Delta               │
│   Rynaro/IDG      Rynaro/FORGE     ...                              │
│                                                                      │
│   Each is:                                                          │
│   - EIIS-conformant                                                 │
│   - Independently installable via its own install.sh                │
│   - Independently versioned                                         │
│   - Self-contained (works without teammates)                        │
└─────────────────────────────────────────────────────────────────────┘
         ▲
         │ nexus registers each Eidolon in roster/index.yaml
         │
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 3 — NEXUS (this repo: Rynaro/eidolons)                        │
│                                                                      │
│   The team's home.                                                  │
│   - roster/index.yaml        — who's in the team, where they live   │
│   - cli/eidolons             — the command-line orchestrator        │
│   - methodology/             — composition rules, prime directives  │
│   - research/                — papers, evidence base                │
│                                                                      │
│   Depends on EIIS (Layer 1). Does not embed Eidolon code (Layer 2). │
└─────────────────────────────────────────────────────────────────────┘
         │
         │ CLI reads roster, fetches Eidolon repos, runs their install.sh
         ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Layer 4 — CONSUMER PROJECT (your code)                              │
│                                                                      │
│   eidolons.yaml              — which members you want               │
│   eidolons.lock              — exact resolved versions              │
│   agents/<member>/           — installed per Eidolon                │
│   AGENTS.md / CLAUDE.md / .cursor/ / .opencode/                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Why four layers.** Each has a single reason to change:

- **EIIS** changes when the install contract evolves.
- **Eidolon repos** change when a methodology evolves.
- **Nexus** changes when the team's composition or the CLI evolves.
- **Consumer project** changes when you add/remove/upgrade members.

A change in one layer doesn't force changes in the others — as long as the contract between layers (EIIS for 1↔2, roster schema for 2↔3, `eidolons.yaml` schema for 3↔4) stays stable.

---

## Install flow — step by step

What `eidolons init --preset pipeline` actually does in a brownfield project:

```
1. Read roster/index.yaml from $EIDOLONS_HOME/nexus/
   └─ Resolve "pipeline" preset → [atlas, spectra, apivr, idg]

2. Detect hosts in cwd
   └─ Finds: .github/, CLAUDE.md, .cursor/
   └─ Hosts to wire: claude-code, copilot, cursor

3. Write eidolons.yaml with:
   - version: 1
   - hosts.wire: [claude-code, copilot, cursor]
   - members: [atlas@^1.0.0, spectra@^4.2.0, apivr@^3.0.0, idg@^1.1.0]

4. For each member:
   a. Fetch repo to ~/.eidolons/cache/<n>@<version>/
      (depth-1 git clone, pinned to latest matching tag)
   b. EIIS sanity check (agent.md, install.sh, AGENTS.md exist)
   c. Run: bash <cache>/install.sh \
             --target ./agents/<n> \
             --hosts claude-code,copilot,cursor \
             --non-interactive \
             --force
   d. Each install.sh:
      - Copies methodology files into ./agents/<n>/
      - Appends to root AGENTS.md (bounded by markers)
      - Appends to CLAUDE.md (pointer line)
      - Creates .cursor/rules/<n>.mdc if cursor is wired
      - Emits ./agents/<n>/install.manifest.json
   e. Nexus reads the manifest, records resolved version + commit SHA

5. Write eidolons.lock with resolved state

6. Print summary + next-step hints
```

**Critical property — idempotency.** Re-running `sync` after the initial install produces an identical result unless the roster or manifest changes. Each per-Eidolon `install.sh` must also be idempotent; this is enforced by EIIS.

**Critical property — composability.** Multiple Eidolons all writing to the same `AGENTS.md` must coexist. Each one appends a named section bounded by markers like `<!-- eidolon:atlas start -->` / `<!-- eidolon:atlas end -->` so the nexus (or `eidolons remove`) can find and remove its own section later.

---

## Why not a monorepo

Every Eidolon currently has its own public repo (atlas, SPECTRA, apivr, idg, forge). A monorepo would:

- ✗ Break existing `git subtree` installs that consumers already use for ATLAS
- ✗ Couple release cadence across five distinct products
- ✗ Inflate CI time (every commit triggers every Eidolon's test suite)
- ✗ Make external contribution harder (contributors have to clone everything)
- ✓ Simplify "install the whole team" slightly — but the CLI handles this already

The distributed model with a registry (`roster/index.yaml`) is strictly better for this team's structure.

---

## Why not a package manager (npm / pip / brew)

Three reasons:

1. **Package managers impose a runtime.** Requiring Node or Python just to install a bash-and-markdown agent is a bad trade. The `curl | bash` pattern keeps the dependency surface at `git + bash + jq`.
2. **Agent content isn't a "package" in the classical sense.** Each Eidolon is a composition of instructions, not a library. Semver applies at the methodology-version level, but the artifacts are mostly text.
3. **Future-proofing.** If we later decide to publish to a package manager, the CLI abstracts the fetch step — we swap the implementation of `fetch_eidolon()` and nothing downstream changes.

---

## Security model

Every layer has a narrow privilege:

| Layer | Reads | Writes | Network |
|-------|-------|--------|---------|
| EIIS | n/a | n/a | n/a |
| Eidolon repo | ✗ | ✗ | ✗ |
| Nexus CLI | Consumer cwd, `$EIDOLONS_HOME` | `$EIDOLONS_HOME`, cwd | Yes (git clone) |
| Per-Eidolon `install.sh` | Consumer cwd | Consumer cwd only | No |
| Installed Eidolon | Per-Eidolon declaration in roster | Per-Eidolon declaration | Per-Eidolon declaration |

**Explicit limits.** The CLI never executes code from a consumer project's `eidolons.yaml`. It reads, resolves, and delegates — `yaml → jq query → bash exec` with no evaluation. Eidolon repos are trusted at install time (they're on your roster); untrusted sources require a manual override.

---

## Versioning

| Artifact | Versioning scheme | Breaking-change policy |
|----------|-------------------|-----------------------|
| EIIS | SemVer | Major bump requires migration guide |
| Each Eidolon methodology | Independent SemVer | Breaking change → methodology major bump |
| Each Eidolon repo | SemVer (git tags) | Tags map to registry `versions.latest` |
| `eidolons` CLI | SemVer | CLI minor bump tolerates old rosters |
| `roster/index.yaml` | `registry_version` field | Breaking schema change → new registry version |
| `eidolons.yaml` | `version: N` field | Breaking schema change → bump version |

A consumer project pins nothing implicitly. Versions are pinned in `eidolons.yaml` (constraints) and `eidolons.lock` (resolved exact).

---

## Related

- [`../README.md`](../README.md) — nexus front door
- [`getting-started.md`](getting-started.md) — install walkthrough
- [`cli-reference.md`](cli-reference.md) — every CLI command
- [`../methodology/composition.md`](../methodology/composition.md) — the pipeline, handoff contracts, partial-team deployment
- `Rynaro/eidolons-eiis` — the install standard (separate repo)
