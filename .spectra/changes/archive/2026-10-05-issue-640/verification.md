# Issue 640 verification

Checker: ATLAS on explicitly pinned Sol 6. Maker: Vivi. Checker is identity-distinct; coordination context was shared, so no fresh-context or statistical-independence claim is made.

[DECISION] Supersede earlier local Bats receipts produced under macOS system Bash 3.2. That Bash version can fail to enforce some test assertions. The Makefile now requires Bash 4+ for test targets; the production CLI remains Bash 3 compatible.

Independent modern-Bash receipt: `PATH=/opt/homebrew/opt/bash/bin:/tmp/eidolons-640/venv/bin:$PATH bats cli/tests/model_host_policy.bats cli/tests/codex_hook_policy.bats cli/tests/add.bats cli/tests/upgrade.bats cli/tests/model_cli.bats` passed 110/110 (exit 0). This includes the corrected missing Codex descriptor assertion and manifest byte-preservation check. The Makefile guard rejects system Bash 3.2 with exit 2 and accepts Bash 5.3 with exit 0. Changed production shell sources pass `/bin/bash -n` under Bash 3.2. `git diff --check` passed.

The reviewed issue-640 paths cover conservative Codex model and effort fallback, explicit inheritance opt-in, add and upgrade preflight, host-specific lock provenance, unmanaged setting cleanup, malformed manifest rejection before hook writes, and conservative fail-closed hook responses. The local smoke invokes generated shims and the routing kernel without a model call. Codex 0.154.0 strict app-server config/read accepted generated subagent settings in an isolated fixture. A model-free thread/start experiment did not dispatch an untrusted hook.

[DISPUTED] The earlier archived `1944/1944` local result used Bash 3.2 and is superseded as verification evidence. A separate modern-Bash full attempt passed 1943/1944 Bats tests; one expected-color assertion failed under an inherited `NO_COLOR` environment setting. The targeted test passed with `NO_COLOR` unset. The final environment-neutral full run passed with Bash 5.3: 1,944/1,944 Bats tests, lint, schema validation, and token budget, exit 0. The log is `/tmp/eidolons-640/modern-neutral-make-check.log` (SHA-256 `29e770537cae8371b91c2948116741fe73b1e094c500e516ffe9a72167a27afc`).

[DECISION] The qualified full validation command is `env -u NO_COLOR PATH=/opt/homebrew/opt/bash/bin:/tmp/eidolons-640/venv/bin:$PATH make check PYTHON=/tmp/eidolons-640/venv/bin/python`; its exit status was 0. Hosted CI remains a separate merge gate.

[GAP] Live Codex host hook dispatch, project and exact-hook trust acceptance, and observed child inference model and effort remain unverified. Local direct-shim smoke and config parsing do not establish runtime qualification.

---

## Provenance

- **Scribe version**: IDG 1.8.1
- **Document type**: verification record
- **Generated**: 2026-10-05
- **Source artifacts**: `cli/tests/model_cli.bats`; `Makefile`; independent ATLAS modern-Bash 110-test receipt; `/tmp/eidolons-640/modern-neutral-make-check.log` (completed; exit 0 reported by test runner)
- **CHT scores**: C:4/5 H:5/5 T:5/5
- **Coverage**: Modern-Bash focused and full checks are complete; runtime host qualification remains separate.
- **Flags**: Runtime host qualification unavailable; hosted CI remains separate; no ECL sidecar for this document.
