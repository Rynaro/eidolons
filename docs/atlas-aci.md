# `eidolons atlas aci` — opt-in atlas-aci MCP wiring

> **Status:** opt-in, project-local only. Not part of any preset, never
> invoked by `eidolons init` or `eidolons sync`. See
> [`specs/atlas-aci-artifacts/`](specs/atlas-aci-artifacts/) for
> the staged implementation artifacts.

[atlas-aci](https://github.com/Rynaro/atlas-aci) is a stdio MCP server
that exposes structural codebase intelligence (graph + symbol index)
to MCP-capable agent hosts. It is **infrastructure ATLAS benefits from**
— not an Eidolon peer, not in the nexus roster, not in any preset.

`eidolons atlas aci` is the single command that wires atlas-aci into a
consumer project's host environments. It ships from `Rynaro/ATLAS` as
`commands/aci.sh` per the Layer-2 ownership decision (D2 in the spec)
and is auto-surfaced by the nexus's per-Eidolon subcommand dispatcher
— no nexus-side dispatch code is involved.

---

## Prerequisites

The command verifies each of these before writing anything and exits
`5` with a copy-pasteable install hint if any are missing:

| Binary | Minimum | Install |
|---|---|---|
| `uv` | any | `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| `rg` (ripgrep) | any | `brew install ripgrep` / `apt-get install ripgrep` |
| `python3` | 3.11 | via `uv` or your OS package manager |
| `atlas-aci` | pinned SHA | `git clone https://github.com/Rynaro/atlas-aci && cd atlas-aci/mcp-server && uv sync && uv tool install .` |

The command does **not** auto-install atlas-aci. See §8 of the spec for
the rejected auto-install alternative (locked as D5 / v2 follow-up F3).

You also need ATLAS installed in the project: `./.eidolons/atlas/` with
a valid `install.manifest.json`. If ATLAS is absent the command exits
`3` and points at `eidolons sync`.

---

## Usage

```bash
eidolons atlas aci                          # --install (default)
eidolons atlas aci --install                # verify prereqs + index + write MCP config
eidolons atlas aci --dry-run                # list every path that would change
eidolons atlas aci --remove                 # remove atlas-aci entries from MCP config
eidolons atlas aci --host cursor            # restrict to one host (repeatable)
eidolons atlas aci --non-interactive        # fail on any prompt (for CI)
eidolons atlas aci --help                   # full help
```

### What `--install` does (in order)

1. Verify prereqs (`uv`, `rg`, Python ≥ 3.11, `atlas-aci` on PATH).
2. Confirm ATLAS is installed in the project (exit `3` if not).
3. Append `.atlas/` to `./.gitignore` (idempotent; created if absent).
4. Run `atlas-aci index --repo "$PWD" --langs ruby,python,javascript,typescript`.
   Skipped if `./.atlas/manifest.yaml` already exists.
5. For each MCP-capable host detected by `detect_hosts` (or supplied
   via `--host`), write the server config:
   - **Claude Code CLI** → `./.mcp.json`
   - **Cursor** → `./.cursor/mcp.json`
   - **GitHub Copilot custom agents** → YAML frontmatter inside
     `./.github/agents/*.agent.md` (skipped with an info log if no
     agent file exists — the command does not invent one).
   - **OpenAI Codex CLI** → `./.codex/config.toml` under the
     `[mcp_servers.atlas-aci]` table.

All writes go through atomic tmpfile + `mv`. Progress logs go to
stderr; stdout stays empty on success (dry-run is the exception:
stdout gets a `CREATE|MODIFY|REMOVE|INDEX`-prefixed path list).

### What `--remove` does

Deletes `mcpServers."atlas-aci"` from each JSON host file, the
list entry `name: atlas-aci` under `tools.mcp_servers` from each
Copilot agent file, and the `[mcp_servers.atlas-aci]` table from
`./.codex/config.toml`. Peer entries (`mcpServers.<other>`,
`name: <other>`, peer TOML tables including `[[mcp_servers]]`
arrays-of-tables) are preserved byte-for-byte. `.gitignore`
is left untouched; `.atlas/` is left on disk (user data).

---

## Scope boundaries (what this command will NOT do)

All of these are locked by the spec and are intentional:

- **No user-level Claude Desktop config.** `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) / `~/.config/claude/claude_desktop_config.json` (Linux) is Layer-3 territory (D3). A future nexus built-in will handle it.
- **No user-level Cursor config.** `~/.cursor/mcp.json` is out of scope; only the project-scoped `.cursor/mcp.json` is touched.
- **No user-level Codex config.** `~/.codex/config.toml` is out of scope — same Layer-3 deferral as Claude Desktop and user-Cursor (D3). Only the project-scoped `./.codex/config.toml` is touched.
- **No writes outside the consumer project's cwd.** Per Layer-2 (P4): the script can only write under `$PWD`. No `$HOME`, no `$EIDOLONS_HOME`.
- **No roster entry.** atlas-aci is not in `roster/index.yaml` and no preset bundles it (D4). This is enforced by the nexus test suite (T5).
- **No auto-install of atlas-aci.** Prereq-check only (D5).

---

## How the command reaches `aci.sh`

```
eidolons atlas aci --install
   │
   ▼
cli/eidolons (catch-all: 'atlas' matches roster_list_names)
   │
   ▼
cli/src/dispatch_eidolon.sh
   │  looks up:
   │    1. ./.eidolons/atlas/commands/aci.sh   (installed, preferred)
   │    2. ~/.eidolons/cache/atlas@<ver>/commands/aci.sh   (cache fallback)
   │
   ▼
bash aci.sh --install     (cwd = consumer project root)
```

Nothing in the nexus's dispatcher is specific to atlas-aci — the same
resolution path supports any `commands/<sub>.sh` that any Eidolon
ships.

---

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success (install, remove, or no-op) |
| 2 | Usage error (unknown flag, unknown `--host` value) |
| 3 | ATLAS not installed in this project |
| 4 | No MCP-capable host detected and `--host` not supplied |
| 5 | A prereq is missing (`uv`, `rg`, Python 3.11+, or `atlas-aci`) |
| 6 | `atlas-aci index` failed (no MCP config files are written in this case) |
| 1 | Unexpected runtime error |

---

## Idempotency contract

| Target | Primitive | Install | Remove |
|---|---|---|---|
| `.mcp.json` | object key `mcpServers."atlas-aci"` | `jq` merge | `jq` del |
| `.cursor/mcp.json` | object key `mcpServers."atlas-aci"` | `jq` merge | `jq` del |
| `.github/agents/*.agent.md` | list entry `name: atlas-aci` under `tools.mcp_servers` | `yq` merge | `yq` del |
| `.codex/config.toml` | TOML table heading `[mcp_servers.atlas-aci]` | `awk` slice/rewrite | `awk` slice/delete |
| `.gitignore` | line match on `.atlas/` | append-if-absent | no-op (removal leaves it) |
| `.atlas/` index | presence of `.atlas/manifest.yaml` | skip re-index if present | no-op (user data) |

Running `--install` twice produces a byte-identical result; running
`--install` → `--remove` → `--install` produces the same state as a
single `--install`.

---

## Related

- [`specs/atlas-aci-artifacts/`](specs/atlas-aci-artifacts/) — staged implementation artifacts (commands/aci.sh scaffold, test fixtures).
- [`architecture.md`](architecture.md) §Security model — the Layer-2 write boundary this command respects.
- [`cli-reference.md`](cli-reference.md) §Per-Eidolon subcommands — generic dispatch contract.
