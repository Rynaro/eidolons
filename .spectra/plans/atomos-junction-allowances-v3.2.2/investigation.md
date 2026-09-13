# Investigation record — published v3.2.2

## Baseline and authority

- Requested operation: sync main, investigate and write specs only.
- Synchronized with `git fetch origin`, `git switch main`, `git merge --ff-only origin/main`.
- Local HEAD, origin/main and dereferenced v3.2.2 tag: `c195bd25fc9a3fea80fbc98e67cc6ffb7846fc71`; VERSION = 3.2.2.
- Relevant cli/src, roster, methodology and EIDOLONS.md files have no diff from the previously investigated fix/stability-hardening branch. Prior temporary-fixture reproductions therefore exercise the same implementation; they are not a fresh live-host test.
- Existing untracked `.atlas/` is unrelated and preserved. No application code or project configuration was changed during this specification task.

## Confirmed observations

1. **Atomos stale registration:** tracked `.mcp.json:82-101` uses `--user 1000:1000`, a Linux-only host path and container workdir `/workspace`. Here the source path does not exist and the user is 501:20. Current template uses identity mounting and the current UID/GID. This establishes local configuration drift, not proof about every consumer project.
2. **False healthy/static no-op:** on synchronized main, `EIDOLONS_NEXUS="$PWD" EIDOLONS_SKIP_REFRESH=1 bash cli/src/mcp_verify.sh atomos --json` returned an empty findings array and exit_code 0. In an isolated copy of the registration+lock with a manifest selecting Claude/Codex and atomos 0.2.0, `mcp sync` reported `atomos@0.2.0 already installed — no-op`. Codex config remained absent. `_mcp_runtime_is_current` reports current because it compares resource receipts, not launch argv; `_mcp_sync_config_present` accepts any one registration.
3. **Misleading UID diagnostic:** direct read-only `_mcp_driver_oci_uid_bind_probes atomos` warned about no -u pin, despite an existing --user pin, and correctly reported the missing mount. The parser at lib_mcp.sh:1655 only matches -u.
4. **Allowance reproduction:** EIIS v3 pointer renderer plus Crystalium wiring emits a sentinel but no tools field. A fixture with `tools: Read, Grep` and an existing Crystalium sentinel remains without its MCP glob. A valid `tools: [Read, Grep]` fixture becomes invalid YAML `tools: [Read, Grep], mcp__crystalium__*`. Missing tools in Claude means inheritance; this is lost explicit restriction/reporting, not universal inability to call tools.
5. **Atomos missing integration:** catalogue grants=[] and wiring_mode=transport; context handoff/externalize invoke kernel composers directly. No executor selector appears in the context schema. The local project has no eidolons.yaml, and harness_hook.sh:120-128 disables ECM when it is absent. Installing Atomos does not imply ECM is enabled. Upstream handlers implement four compose/verify operations; verification is advisory and externalize composition does not persist memory.
6. **Junction mismatch:** tracked binary path is Linux-only and not executable here. Catalogue declarations differ from the source registry at v0.4.0. The registry registers planFromPrompt/run/verify/inject; planFromPrompt is a permanent stub. Parent dispatch is prescribed in the handoff graph, but an automatic integration was not found in the inspected dispatch paths. The marker chooses the first cached version, yielding 0.2.0 versus project lock 0.4.0 in this checkout.

## Reproduction scope

Temporary fixtures from the preceding investigation: `/private/tmp/eidolons-atomos-audit.pGSKOJ` and `/private/tmp/eidolons-allowance-audit.Eouqhc`. They are disposable local evidence, not repository dependencies. To reproduce the Atomos check, copy only registration/lock into a temporary project, declare atomos 0.2.0 with Claude+Codex hosts, keep a nonexistent bind source and omit Codex configuration, then run sync and compare output plus files. To reproduce allowance checks, render a v3 agent and apply Crystalium grants to that adapter, a stale-sentinel fixture and an inline-tools-list fixture. Future regression tests belong to implementation, not this task.

No Docker containers were launched, project settings rewritten or upstream state changed. No tool availability in this session means no live MCP invocation, transport handshake, permission prompt or provider model result was validated. Static source registry parity is not live tools/list parity. The broader CI suite is not evidence that these missing integration cases work.

## Primary sources and policy distinctions

- [Atomos contract](https://github.com/Rynaro/atomos/blob/v0.2.0/README.md), [server](https://github.com/Rynaro/atomos/blob/v0.2.0/internal/server/server.go), [pin verifier](https://github.com/Rynaro/atomos/blob/v0.2.0/internal/verify/pins.go). The initial upstream inspection read main reporting 0.2.0; pinned source should be rechecked in implementation before a release contract test is frozen.
- [Pinned Junction registry](https://github.com/Rynaro/Junction/blob/v0.4.0/internal/mcp/tools.go) was read at the exact release ref, not inferred solely from the sibling checkout.
- [Claude subagent capabilities](https://code.claude.com/docs/en/sub-agents#control-subagent-capabilities): omitted tools inherits available tools. Named mcpServers references reuse the parent connection; inline definitions can create per-subagent connections.
- [Claude permission rules](https://code.claude.com/docs/en/permissions#mcp) and [project MCP approval](https://code.claude.com/docs/en/mcp#project-scope) are separate from exposure. Existing user/admin denies remain authoritative.
- Canonical local policy: roster/index.yaml security + roster/aci.yaml class restrictions. These do not define a complete host-specific tool-name map. Do not assume a package manifest capability field exists; normative EIIS schema verification remains open.

Design choices in specs.json/specs.md are proposals. In particular, opt-in context.executor, structured operation receipts and optional approval projection do not yet exist. They preserve Atomos's existing no-meter/no-policy/no-trigger/no-injection/no-persistence boundary.
