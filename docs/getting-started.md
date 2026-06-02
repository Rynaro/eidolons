# Getting Started with Eidolons

> Bring a personal, portable team of AI agents into any project — empty or running.

This guide takes you from **nothing installed** to **a working project with Eidolons** in about five minutes.

---

## 1. Install the CLI (once per machine)

```bash
curl -sSL https://raw.githubusercontent.com/Rynaro/eidolons/main/cli/install.sh | bash
```

This does three things:

1. Clones the nexus (this repo) to `~/.eidolons/nexus`.
2. Symlinks the `eidolons` CLI into `~/.local/bin/eidolons`.
3. Prints a `PATH` hint if `~/.local/bin` isn't on your PATH already.

Verify:

```bash
eidolons --version
eidolons list --available
```

If you see the roster, you're ready.

**Requirements.** `git`, `bash`, `jq`. `yq` recommended but optional.

---

## 2. Pick a scenario

### A. Greenfield — a brand-new project

```bash
mkdir my-new-thing && cd my-new-thing
eidolons init --preset pipeline
```

This creates:

```
my-new-thing/
├── eidolons.yaml            # your team manifest
├── eidolons.lock            # resolved versions (commit this too)
├── .eidolons/               # installed members (hidden to avoid collisions)
│   ├── atlas/
│   ├── spectra/
│   ├── apivr/
│   └── idg/
├── AGENTS.md                # open-standard entry for Copilot/Cursor/OpenCode
├── CLAUDE.md                # Claude Code entry
├── .github/
│   └── copilot-instructions.md
├── .cursor/rules/           # one MDC per Eidolon
├── .opencode/agents/        # one agent file per Eidolon
└── .codex/agents/           # one subagent file per Eidolon (OpenAI Codex)
```

Commit everything — including `eidolons.lock` — so teammates get the same versions.

### B. Brownfield — an existing project

```bash
cd ~/projects/existing-rails-app
eidolons init --preset standard
```

The CLI detects existing hosts (`.github/`, `CLAUDE.md`, `.cursor/`, `.opencode/`, `AGENTS.md`, `.codex/`) and only wires the ones that are in use. It **appends** to existing `AGENTS.md` / `CLAUDE.md` rather than overwriting them — your existing rules stay intact. `AGENTS.md` is co-owned by Copilot and Codex; `.codex/` is the definitive Codex-only signal.

### C. Individual member — one Eidolon, targeted

```bash
cd ~/projects/some-app
eidolons init --members atlas       # scout-only, read-only exploration
# later:
eidolons add spectra                # add the planner
```

### D. Non-interactive — for CI and scripts

```bash
eidolons init --preset minimal --non-interactive
```

Fails fast on any prompt. Use `--preset` or `--members` to provide all required inputs up front.

---

## 3. Understand what's on disk

| File | Who writes it | Commit? |
|------|---------------|---------|
| `eidolons.yaml` | You (via CLI or by hand) | ✅ yes |
| `eidolons.lock` | `eidolons sync` | ✅ yes |
| `.eidolons/<n>/` | Each Eidolon's `install.sh` | ✅ yes |
| `AGENTS.md` | Each Eidolon appends its section | ✅ yes |
| `CLAUDE.md` | Each Eidolon appends a pointer line | ✅ yes |
| `.cursor/rules/<n>.mdc` | Per-Eidolon | ✅ yes |
| `.opencode/agents/<n>.md` | Per-Eidolon | ✅ yes |
| `.codex/agents/<n>.md` | Per-Eidolon (Codex subagent) | ✅ yes |

Rule of thumb: if the CLI wrote it, commit it.

---

## 4. Using the team

Once installed, your AI coding host (Claude Code, Copilot, Cursor, etc.) auto-discovers the Eidolons via the dispatch files. In Claude Code you might open the chat and say:

```
@atlas map the authentication flow in this repo
```

ATLAS responds under its own methodology (`A→T→L→A→S`), bounded to read-only operations, and hands off to SPECTRA or APIVR-Δ when the task shifts from exploration to planning or building.

Each host has its own invocation conventions — see each Eidolon's `hosts/<host>.md` for specifics.

---

## 5. Day-two operations

| Task | Command |
|------|---------|
| Add a member | `eidolons add forge` |
| Remove a member | `eidolons remove forge` (v1.1) |
| Update to latest within constraints | `eidolons sync` |
| Force a roster data refresh | `eidolons nexus refresh` |
| Inspect CLI vs roster channel split | `eidolons nexus status` |
| Freeze roster to latest release | `eidolons nexus channel stable` |
| Health check the install | `eidolons doctor` |
| Fix broken install | `eidolons doctor --fix` |
| See what's installed | `eidolons list` |
| Browse available members | `eidolons list --available` |
| See a member's details | `eidolons roster atlas` |

---

## 5b. Roster freshness and channels

By default the roster catalogue (which Eidolon versions are visible, which MCP
`pins.stable` are current) tracks the `main` branch of the nexus repo. This is
independent of the CLI version pin (`.install_ref`):

- **CLI code** is pinned at the installed tag — updated only by `eidolons upgrade self`.
- **Roster data** (`roster/`, `EIDOLONS.md`, `methodology/cortex/`) floats at
  `.roster_ref` — updated by `nexus_refresh` which runs automatically on
  `sync`, `init`, `upgrade`, `mcp install`, and `mcp upgrade`.

Per-member integrity (commit/tree/archive SHA) is **still verified** at install
and upgrade time. Floating the catalogue only changes which pins are visible —
never their on-disk verification.

**To see the current split:**
```bash
eidolons nexus status
```

**To freeze the catalogue to the latest stable release** (useful for
reproducible builds or air-gap environments):
```bash
eidolons nexus channel stable   # magic: resolves to latest release tag at refresh time
eidolons nexus channel v1.16.0  # explicit tag freeze
```

**To return to tracking `main`:**
```bash
eidolons nexus channel main
```

**To disable all auto-refresh** (fully offline / deterministic CI):
```bash
export EIDOLONS_SKIP_REFRESH=1
```

---

## 6. Troubleshooting

**"`eidolons: command not found`"** → `~/.local/bin` isn't on your PATH. Add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc.

**"`Eidolon 'X' not found in roster`"** → Your roster cache may be stale. Run `eidolons nexus refresh` to update it. Or run `eidolons nexus status` to see if you are behind the channel.

**"`EIIS-conformance warning`"** → The Eidolon's repo is missing required files per the install standard. It'll usually still install, but `eidolons doctor` will flag the gap. File an issue on the specific Eidolon's repo.

**Host wiring seems wrong** → `eidolons doctor` pinpoints which file is off. Most problems are solved by `eidolons sync`.

---

## Next reading

- [`architecture.md`](architecture.md) — how nexus, CLI, and per-Eidolon repos fit together
- [`cli-reference.md`](cli-reference.md) — full CLI reference
- [`../methodology/composition.md`](../methodology/composition.md) — the canonical pipeline
- [`../methodology/prime-directives.md`](../methodology/prime-directives.md) — D1–D10 invariants
