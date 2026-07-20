---
eidolon: ramza
kind: spec
version: 1.0.0
created_at: "2026-07-17"
change_id: mcp-identity-mount-host-path
esl_version: "1.1"
tier: full
maker: vivi
checker: kupo
status: proposed
issue: "Rynaro/eidolons#507"
---

# Spec: MCP identity-mount the host project root (tonberry + atomos)

> Decision-ready spec for an already-proposed, already-right-sized (`full`) change.
> The competing-approach trade-off (A vs B) was resolved in the proposal; this spec
> records the chosen fix, its scope boundaries, and the mechanically-verifiable
> acceptance checks that checker **kupo** will run. Plan artifact only — no code.

## Scope

### Context / the defect (root-caused in issue #507)

The two ECM/ESL executor MCPs — `tonberry` and `atomos` — are wired into a
consumer project via docker-run templates that **hard-code the container mount
destination to `/workspace`**:

- `cli/templates/mcp/tonberry.mcp.json.tmpl` and
  `cli/templates/mcp/atomos.mcp.json.tmpl` both render, verbatim:
  `"-v", "__PROJECT_ROOT__:/workspace:z", "-w", "/workspace"`.
- `__PROJECT_ROOT__` is substituted with the **host-absolute** project root by
  `_mcp_oci_render_and_merge` in `cli/src/lib_mcp.sh` (sed, `|` delimiter,
  global `g` flag; see lines 1068-1073).

Both `tonberry` and `atomos` expose `project_root` as a **per-call tool
argument**. A host-side MCP caller only knows its own host-absolute path, so it
passes that. The server resolves the argument inside the container's mount
namespace, where the project lives at `/workspace` and **not** at the host path.
Result: `ENOENT` / a silent `count: 0`.

Counterfactual proof from the issue (tonberry#8):

| `project_root` argument passed | server sees | result |
|---|---|---|
| `<host-absolute path>` | path does not exist in container | count 0 (wrong) |
| `/workspace` | the bind mount | count 9 (right) |
| omitted | falls back to container `WorkingDir` (`/workspace`) | count 9 |

Confirmed reproduced for `tonberry` (Rynaro/tonberry#8); inferred identical for
`atomos` (Rynaro/atomos#4) — same template shape, same per-call `project_root`
contract.

### In scope

- `cli/templates/mcp/tonberry.mcp.json.tmpl` — mount + workdir edit.
- `cli/templates/mcp/atomos.mcp.json.tmpl` — mount + workdir edit.
- A **regression test** (bats) that renders both templates and asserts the
  identity-mount shape — designed to go RED on the old `/workspace` shape.
- `CHANGELOG.md` — one Unreleased entry.

### Out of scope (and why)

- **`cli/templates/mcp/atlas-aci.mcp.json.tmpl` — immune, leave it.** The
  atlas-aci server is launched with `serve --repo /repo` baked into the same
  template that owns the `__PROJECT_ROOT__:/repo:ro` mount. The nexus controls
  **both** the mount destination and the literal `/repo` argument; callers never
  supply a root. It is internally self-consistent. Editing it is scope creep.
- **The `assess` path in `cli/src/lib_mcp.sh` (`mcp_driver_oci_image_assess`,
  ~lines 247-252) — immune, leave it.** It runs
  `docker run ... -v ${project_root}:/workspace:ro -w /workspace ... assess /workspace`:
  the nexus controls both the mount **and** the literal `/workspace` positional
  argument it passes to the tool. Like atlas-aci, it is self-consistent; no
  external caller injects a path. Changing it is scope creep with real
  test-breakage risk (mcp_assess.bats stubs this invocation). **No `cli/src`
  change is required by this fix at all.**
- **No server-side change to `tonberry`/`atomos` in this change.** Any
  loud-error mitigation (e.g. a server that rejects a non-container path) is the
  respective upstream repo's concern (tonberry#8 may add one separately) and is
  independent of the nexus wiring fix.

### Assumptions (risk-if-wrong)

- A1. `_mcp_oci_render_and_merge` substitutes `__PROJECT_ROOT__` **globally**
  (sed `g`), so two occurrences in one template both resolve. Grounded: the
  atlas-aci template already uses `__PROJECT_ROOT__` twice (`:/repo:ro` and
  `/.atlas/memex:/memex`) and renders correctly today. **Risk if wrong:** the
  second occurrence (`-w __PROJECT_ROOT__`) would stay literal — caught by AC-2.
- A2. No test fixture or doc asserts the `/workspace` container path for
  tonberry/atomos. Grounded: a full-repo sweep found `/workspace` only in the
  two in-scope templates and the out-of-scope assess block; zero test
  assertions. **Risk if wrong:** a hidden green test would flip RED — surfaced,
  not hidden, by running the suite (AC-9).

## Approach — the chosen fix (Option A: identity-mount)

In **both** `tonberry.mcp.json.tmpl` and `atomos.mcp.json.tmpl`, change the mount
and workdir so the host path is identity-mapped into the container:

- Mount arg: `__PROJECT_ROOT__:/workspace:z`  ->  `__PROJECT_ROOT__:__PROJECT_ROOT__:z`
- Workdir arg: `/workspace`  ->  `__PROJECT_ROOT__`

After substitution, for a project at host path `P` the rendered args become
`-v P:P:z -w P`. The container's filesystem now exposes the project at the
**identical** absolute path the caller naturally supplies as `project_root`, so
the argument resolves transparently and the omitted-argument fallback (container
`WorkingDir`) also points at `P`. No server-side change; no `cli/src` change
(the global `__PROJECT_ROOT__` substitution already handles rendering).

**Residual trade-off (recorded, accepted).** Identity-mapping exposes the host
path structure inside the container, losing the `/workspace` opacity. This is
accepted because the only alternative that preserves opacity (Option B:
server-side host<->container path translation) is strictly more invasive — it
touches two other repos and requires the server to receive a mount table it is
not given. See **Rejected Alternatives**.

## Stories

### Story 1 — Identity-mount the tonberry template (P0, ~0.5d)
As a host MCP caller, I pass my host-absolute `project_root` to tonberry and the
tool operates on the real project instead of returning `count: 0`.
Action: in `cli/templates/mcp/tonberry.mcp.json.tmpl`, replace the `-v` value
`__PROJECT_ROOT__:/workspace:z` with `__PROJECT_ROOT__:__PROJECT_ROOT__:z` and
the `-w` value `/workspace` with `__PROJECT_ROOT__`. Nothing else in the file
changes (labels, cap-drop, security-opt, image ref, `serve` arg untouched).
Executor: any tier; output contract = a one-line-per-arg JSON template that still
`jq empty`-parses. Covered by AC-1, AC-2, AC-3.

### Story 2 — Identity-mount the atomos template (P0, ~0.5d)
Same edit, applied to `cli/templates/mcp/atomos.mcp.json.tmpl`. Covered by AC-4,
AC-5, AC-6.

### Story 3 — Regression test that fails on the old shape (P0, ~1d)
Add a bats test (e.g. a new block in `cli/tests/mcp_install.bats` or a dedicated
`cli/tests/mcp_mount_identity.bats`) that renders tonberry and atomos via the
real install path (`setup_fake_docker_for_oci`, then `mcp_install.sh <name>`) and
asserts the rendered `.mcp.json` args carry the identity-mount shape and no
`/workspace` token. The test MUST fail on the pre-fix template and pass on the
post-fix template (the teeth requirement). Covered by AC-1..AC-6 (this is the
mechanism that verifies them) plus the anti-regression AC-3/AC-6.

### Story 4 — Guard the immune surfaces + CHANGELOG (P1, ~0.5d)
Assert the atlas-aci template and the lib_mcp.sh assess path are unchanged
(AC-7, AC-8), confirm the existing MCP suite stays green and idempotent (AC-9),
confirm lint stays clean (AC-10), and add one CHANGELOG Unreleased entry.

## Acceptance Criteria

> EARS form. Each criterion is one atomic, mechanically checkable assertion.
> `<PROJECT_ROOT>` / `P` denotes the resolved host-absolute project root used at
> render time. These are the checks **kupo** verifies.

### AC-1 (event-driven)
GIVEN a project whose resolved host-absolute root is `P` and the tonberry install template
WHEN `eidolons mcp install tonberry` renders `.mcp.json`
THEN the docker `-v` bind value in `.mcpServers.tonberry.args` equals `P:P:z`
VERIFY: bats — render tonberry through `mcp_install.sh` under `setup_fake_docker_for_oci`; assert `jq -r '.mcpServers.tonberry.args | index("-v") as $i | .[$i+1]' .mcp.json` == `"$PWD:$PWD:z"`.

### AC-2 (event-driven)
GIVEN the same rendered tonberry `.mcp.json`
WHEN the workdir argument is read
THEN the docker `-w` value in `.mcpServers.tonberry.args` equals `P` (never the literal `/workspace`)
VERIFY: bats — assert `jq -r '.mcpServers.tonberry.args | index("-w") as $i | .[$i+1]' .mcp.json` == `"$PWD"`; this catches a non-global substitution that left `-w` literal.

### AC-3 (unwanted-behavior)
GIVEN the rendered tonberry `.mcpServers.tonberry.args` array
WHEN every arg string is scanned
THEN no arg contains the literal token `/workspace`
VERIFY: bats — `! jq -e '.mcpServers.tonberry.args[] | select(type=="string" and test("/workspace"))' .mcp.json`. Teeth: reverting the template to the `:/workspace:z` + `-w /workspace` shape turns this criterion RED (this is the check that would have caught #507).

### AC-4 (event-driven)
GIVEN a project whose resolved host-absolute root is `P` and the atomos install template
WHEN `eidolons mcp install atomos` renders `.mcp.json`
THEN the docker `-v` bind value in `.mcpServers.atomos.args` equals `P:P:z`
VERIFY: bats — assert `jq -r '.mcpServers.atomos.args | index("-v") as $i | .[$i+1]' .mcp.json` == `"$PWD:$PWD:z"`.

### AC-5 (event-driven)
GIVEN the same rendered atomos `.mcp.json`
WHEN the workdir argument is read
THEN the docker `-w` value in `.mcpServers.atomos.args` equals `P`
VERIFY: bats — assert `jq -r '.mcpServers.atomos.args | index("-w") as $i | .[$i+1]' .mcp.json` == `"$PWD"`.

### AC-6 (unwanted-behavior)
GIVEN the rendered atomos `.mcpServers.atomos.args` array
WHEN every arg string is scanned
THEN no arg contains the literal token `/workspace`
VERIFY: bats — `! jq -e '.mcpServers.atomos.args[] | select(type=="string" and test("/workspace"))' .mcp.json`. Teeth: the pre-fix atomos template makes this RED.

### AC-7 (ubiquitous)
GIVEN the change has been applied
THEN `cli/templates/mcp/atlas-aci.mcp.json.tmpl` still binds `__PROJECT_ROOT__:/repo:ro` and still passes `--repo /repo` (the immune, self-consistent surface is untouched)
VERIFY: grep — the template contains the exact strings `__PROJECT_ROOT__:/repo:ro` and `/repo`; `git diff --name-only <base>..<head>` does not list the atlas-aci template.

### AC-8 (ubiquitous)
GIVEN the change has been applied
THEN `cli/src/lib_mcp.sh` has zero modified lines (the `mcp_driver_oci_image_assess` block still uses `${project_root}:/workspace:ro`, `-w /workspace`, and the literal `assess /workspace`)
VERIFY: cmd — `git diff --name-only <base>..<head>` does not list `cli/src/lib_mcp.sh`; grep confirms the assess `-v`/`-w`/positional block is byte-identical.

### AC-9 (event-driven)
GIVEN tonberry (or atomos) already installed into a project at a fixed digest
WHEN `eidolons mcp install <name>` runs a second time with the same digest
THEN the resulting `.mcp.json` is byte-identical to the first run
VERIFY: bats — the existing MCP suite (`cli/tests/mcp_install.bats`, `cli/tests/mcp_wiring.bats`, `cli/tests/mcp_assess.bats`) stays green; a `diff` of `.mcp.json` after two installs is empty (idempotency invariant preserved).

### AC-10 (ubiquitous)
GIVEN the change touches only the two templates, a bats test, and CHANGELOG (no `cli/src/*.sh` edit)
THEN `make lint` (shellcheck `-x -S error` over `cli`) exits 0 and bash 3.2 compatibility is preserved
VERIFY: cmd — `make lint` exits 0; `git diff --name-only <base>..<head>` lists no `cli/src/*.sh` file (the render path is unchanged, so this is a guard, not a code review).

## Confidence

High. The fix is a two-token edit in each of two templates, on a code path whose
global `__PROJECT_ROOT__` substitution is already exercised twice by the
shipped atlas-aci template. The defect is counterfactually proven in #507, the
chosen approach is already selected, and the scope sweep found no contradicting
fixture. The only genuine uncertainty is the accepted host-path-exposure
trade-off, which is a design decision, not an implementation risk.

## Rejected Alternatives

### Option B — server-side host<->container path translation (rejected)
Keep the `/workspace` opaque mount and teach the `tonberry`/`atomos` servers to
translate an incoming host-absolute `project_root` into the container mount
point. **Rejected:** strictly more invasive — it requires changes in two other
repos (tonberry, atomos), and the server would need a host<->container mount
table it does not currently receive over the MCP transport. It also re-solves,
per-server, a problem the mount can solve once. Option A is a pure nexus-side
template fix with no cross-repo coordination.

### Option C — document "always pass /workspace" (rejected)
Leave the templates and tell callers to pass `project_root=/workspace`.
**Rejected:** it pushes a container-internal implementation detail onto every
host caller, contradicts the natural host-absolute path a caller already knows,
and is unenforceable — the silent `count: 0` failure mode remains one forgotten
argument away.

## Risks

- **R1 (P1) — host-path exposure inside the container.** Identity-mapping makes
  the host directory structure visible at its real path inside the sandbox.
  Accepted trade-off (see Approach); the container still runs `--cap-drop ALL
  --security-opt no-new-privileges`, and the bind is unchanged in scope (still
  the single project root, still `:z` SELinux-relabelled).
- **R2 (P2) — non-global substitution regression.** If a future refactor makes
  `__PROJECT_ROOT__` substitution non-global, `-w __PROJECT_ROOT__` would render
  literal. Mitigated by AC-2/AC-5, which assert the `-w` value equals the
  resolved path, not the placeholder.
- **R3 (P2) — scope creep into immune surfaces.** Touching the atlas-aci
  template or the assess path would break self-consistent, nexus-controlled
  invocations. Mitigated by AC-7/AC-8, which assert those surfaces are unchanged.
- **R4 (P2) — idempotency / harness re-prompt churn.** A malformed template edit
  could change canonical `.mcp.json` form on re-render. Mitigated by AC-9
  (byte-identical second render) and the existing no-op guard in
  `_mcp_merge_into_json_file`.
