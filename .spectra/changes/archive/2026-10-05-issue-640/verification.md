# Issue 640 verification

Checker: ATLAS on explicitly pinned Sol 6. Maker: Vivi. Checker is identity-distinct; coordination context was shared, so no fresh-context or statistical-independence claim is made.

Final independent review: PASS. Command: `bats cli/tests/model_host_policy.bats cli/tests/codex_hook_policy.bats cli/tests/add.bats cli/tests/upgrade.bats` — 74/74 passed, exit 0. `git diff --check` passed.

Confirmed automatic conservative Codex model+effort fallback and explicit inheritance opt-in; candidate preflight for add; upgrade preflight and reapplication; host-specific lock provenance; owned-setting cleanup for unmanaged Codex/Claude/Cursor; malformed manifest rejection before hook writes; dependency-free fail-closed response and blocking on empty routing output for nonempty prompts.

The local smoke invokes generated shims and the real routing kernel without a model call. Codex 0.154.0 strict app-server config/read accepted generated subagent settings in an isolated trusted fixture. A separate model-free thread/start experiment did not dispatch an untrusted hook. Live host hook dispatch, project/exact-hook trust acceptance, and observed child inference model/effort are not verified. Status and documentation preserve these distinctions.

Full-suite and hosted CI results are separate release gates and will be recorded after completion.

Final fixture correction: the shared fake installer now preserves existing descriptors; only the upgrade regression explicitly replaces them. Independent checker reviewed the change and reran the existing Codex stub preservation test (1/1 passed). Production code was unchanged.

Final `make check` passed (exit 0): 1,944/1,944 Bats tests, lint, schema validation, and cortex token budget. Hosted CI remains a separate merge gate.
