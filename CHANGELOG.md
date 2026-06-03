# Changelog

All notable changes to the **Eidolons nexus** are documented here. The nexus versions independently from individual Eidolons and from EIIS.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning follows [Semantic Versioning](https://semver.org/).

---

## [Unreleased]

## [1.20.0] — 2026-06-03

### Added

- **(verify-envelope) `eidolons verify-envelope <envelope.json>`** — the mechanical
  ECL hand-off integrity gate (roadmap #2). A deterministic, non-LLM SHA-256
  verifier (R3-09: a shasum compare, never a judging Eidolon): recomputes the
  payload hash and compares it to the envelope's integrity tag. Eidolon-agnostic —
  any receiver (or the orchestrator) runs the SAME gate, making verification
  **symmetric** instead of APIVR-only. Staged **warn|block** modes (default `warn`
  per the ECL v1.0 opt-in P0; flip via `EIDOLONS_ECL_VERIFY_MODE=block`); `block`
  enforces ECL §6.2.2 "receiver SHALL NOT process on integrity mismatch" (exit 3).
  Verdicts: pass/tamper/inconsistent/unverifiable/missing_payload/malformed; honors
  the parent-fills-SHA pattern (placeholder → unverifiable, never a hard fail);
  `--trace` appends a verify_pass/verify_fail JSONL event; `--json` for the verdict.
- **(run) `eidolons run --verify <envelope> [--verify-block]`** — wires the gate in
  as a **pre-step**: verify the incoming hand-off BEFORE routing. Block mode refuses
  to route a tampered hand-off (exit 3); warn mode records `incoming_verify` on the
  routing artifact and proceeds.

### Notes

- Reconciles gap **V3**: an envelope's `envelope_version: "2.0"` is the WIRE format,
  the ECL spec is at v1.0, and `artifact.schema_version` is the ARTIFACT schema —
  three distinct layers, not a contradiction. Tests: `cli/tests/verify_envelope.bats`
  (15). Follow-up (layer-2): distribute a thin symmetric verify-incoming skill that
  calls this verb to all 6 member repos, replacing apivr-verify-incoming's
  warn-only, LLM-interpreted check.

## [1.19.0] — 2026-06-03

### Added

- forge v1.7.0 published in the roster with release integrity metadata.
- idg v1.6.0 published in the roster with release integrity metadata.
- apivr v3.5.0 published in the roster with release integrity metadata.
- spectra v4.7.0 published in the roster with release integrity metadata.
- atlas v1.10.0 published in the roster with release integrity metadata.
- **(run) `eidolons run "<prompt>"`** — the mechanical routing kernel. Converts
  the cortex Dispatch Protocol (EIDOLONS.md Steps 1–5) from host-LLM-interpreted
  prose into a deterministic, table-driven decision over a new machine-readable
  `roster/routing.yaml` (sibling to `index.yaml`/`mcps.yaml`). No LLM, no eval
  (I-C2), bash 3.2 safe. Word-boundary trigger matching (so "map" never matches
  "flowmap", "patch" never "dispatch"); mechanically enforces refusal
  immutability (a named/top Eidolon that would refuse never dispatches — it
  reroutes to a capable peer), the τ thresholds, chain-template selection, and
  **TRANCE-never-default** (the trance tier requires a complexity flag AND a
  stakes flag, never automatic). Same prompt + same routing data ⇒ byte-identical
  artifact (I-C6). Flags: `--json`, `--explain`, `--surface-files/-modules N`,
  `--trance`, `--prior-failure`. This is the team's own D3 directive
  (mechanical-over-prompt) finally applied to the orchestration layer it most
  violated. Acceptance-anchored to `methodology/cortex/validation-gates.md`
  V1–V14 (`cli/tests/run.bats`, 16 tests). Adds `schemas/routing.schema.json`.
  Follow-ups (not in this change): generate the EIDOLONS.md descriptor table
  FROM `routing.yaml` + a `doctor --deep` drift-parity gate; richer NL classify.

## [1.18.0] — 2026-06-02

### Added

- **(mcp) `eidolons mcp use <name>@<ver>`** — switch an installed MCP to any
  catalogue-published version, up or down. Downgrades are allowed (it is the
  sanctioned "put me on exactly this version" verb). Requires an explicit
  `@<ver>`; delegates to `mcp install --force` after validation, so it rewrites
  both `eidolons.mcp.lock` and the `.mcp.json` wiring. No-op (byte-identical
  lockfile) when already on the target version.
- **(mcp) `eidolons mcp upgrade <name>@<ver>`** — the `upgrade` verb now accepts
  an explicit target version for a forward move. Downgrades are rejected and
  point the user at `eidolons mcp use`. Bare `upgrade [<name>|--all]` is
  unchanged (still chases catalogue `pins.stable`). `--all` combined with an
  explicit `@<ver>` is a usage error.
- **(mcp) `mcp_assert_version_published`** — both switch flows reject any version
  not published in `roster/mcps.yaml` under `versions.releases.<ver>`, with an
  actionable error that lists the published versions and points at a roster bump.
  This keeps the nexus the single source of `oci-digest` truth — no consumer can
  pin a version the catalogue has not blessed.
- **(roster) atlas-aci 0.2.3** — published in the MCP catalogue (multi-arch
  index digest pinned; `pins.stable`/`latest` advanced from 0.2.2). Adds Rust
  support. With this bump, `eidolons mcp use atlas-aci@0.2.3` switches a 0.2.2
  install to 0.2.3 in one command.

### Fixed

- **(mcp) `eidolons mcp use` dispatch** — the top-level `cli/eidolons` mcp
  sub-command allowlist now includes `use` (previously only the inner
  `cli/src/mcp.sh` dispatcher knew the verb, so `eidolons mcp use …` fell through
  to "Unknown mcp subcommand").

## [1.17.1] — 2026-06-02

### Added
- vigil v1.4.1 published in the roster with release integrity metadata.
- atlas v1.9.1 published in the roster with release integrity metadata.
- roster-health CI now runs each shipped Eidolon's `install.sh --non-interactive`
  against a temp target, gating the per-Eidolon `agent.md` ≤1000-token P0 budget
  (and the install-layout sweep) before a version can pass health checks. This
  closes the hole that let atlas v1.9.0 / vigil v1.4.0 ship an over-budget
  `agent.md` — `--help` and EIIS conformance never exercise that gate.

## [1.17.0] — 2026-06-02

### Added

- **(nexus) `eidolons nexus` command family** — three subcommands for the roster channel:
  - `eidolons nexus refresh [--quiet]` — force a path-restricted roster data refresh now.
  - `eidolons nexus channel [<ref>]` — get or set the roster channel (`main` | `stable` | `<tag>` | `<sha>` | `<branch>`). `stable` is a magic token that resolves to the latest release tag at fetch time.
  - `eidolons nexus status` — read-only split report: CLI version/ref (`.install_ref`) vs roster channel/effective ref/freshness (`.roster_ref`).
- **(nexus) Path-restricted `nexus_refresh`** — replaces `git reset --hard FETCH_HEAD` with a per-path checkout loop that updates ONLY the data layer (`roster/`, `EIDOLONS.md`, `methodology/cortex/`). CLI code (`cli/`, `schemas/`, `VERSION`) stays pinned at the installed tag, closing the "roster frozen at CLI tag" bug that caused `eidolons mcp install crystalium` to resolve against a stale 1.2.0 (amd64-only) catalogue on Apple Silicon even though `main` carried 1.2.1 (multi-arch).
- **(mcp) `nexus_refresh` wired into `mcp install` and `mcp upgrade`** — catalogue bumps on the roster channel are now picked up automatically before version/kind resolution.
- **(doctor) Roster-freshness probe** — new non-fatal section ("Roster freshness") in `eidolons doctor`: warns when the local cache is behind the channel (`eidolons nexus refresh` hint), passes when fresh, and skips informally when offline or in local-checkout mode. Never increments ERRORS.

### Changed

- **(nexus) `upgrade self` dirty-guard tolerates refresh-induced drift** — `_nexus_is_dirty` now excludes the three refresh-managed data paths (`roster`, `EIDOLONS.md`, `methodology/cortex`) via git pathspec negation (`:!<path>`). A previous `eidolons sync` (which refreshes the roster) no longer poisons the next `upgrade self` into requiring `--force`. Genuine CLI-code edits still trip the guard.
- **(install) `install.sh` writes a non-empty default `.roster_ref`** — was writing an empty file when `EIDOLONS_ROSTER_REF` was unset; now defaults to `main`.
- **(nexus) `.roster_ref` preserved across `upgrade self`** — the fresh `nexus.new` clone now receives a copy of the old `.roster_ref` before the atomic swap, so a frozen channel (e.g. `v1.5.0`) survives self-upgrades instead of being silently dropped.

### Notes

- The "CLI pinned / roster floats / SHAs still verified" model: the CLI version is controlled by `eidolons upgrade self` (`.install_ref`). Roster data tracks `.roster_ref` (default: `main`). Per-member integrity (commit/tree/archive SHA) is still verified at install/upgrade — floating the catalogue changes *which* pins are visible, never their verification. Users who need a frozen catalogue run `eidolons nexus channel stable` or `eidolons nexus channel <tag>`.

## [1.16.1] — 2026-06-02

### Added
- crystalium v1.2.1 published in the roster with release integrity metadata.

### Changed

- **(roster) crystalium re-pinned to 1.2.1 — multi-arch image.** The 1.2.0 GHCR image was `linux/amd64`-only, so `eidolons mcp install crystalium` failed on Apple Silicon (arm64) with "no matching manifest for linux/arm64/v8". crystalium v1.2.1 publishes a multi-arch index (amd64 + arm64); `roster/mcps.yaml` now pins `sha256:d8da22cb…` and `roster/index.yaml` tracks 1.2.1.

### Fixed

- **(mcp) `mcp pull`/`install` now surface docker's actual error on a failed pull.** Previously the driver discarded docker's stderr and printed a generic "registry outage / network / air-gap" message — which hid the real cause (e.g. a single-arch image with "no matching manifest for <arch>") and sent users down the wrong path. The failure now prints docker's reported error plus the host architecture.

## [1.16.0] — 2026-06-02

### Added

- **(mcp) Generic `eidolons mcp pull <name>` command** — catalogue-pin-driven OCI image fetch for any `kind=oci-image` MCP (atlas-aci, crystalium, future additions). Idempotent no-op when image is already present. Supports `--image-digest` override, `--build-locally` (gated to MCPs that declare `source.build`), and `--git-ref`. Replaces the atlas-aci-only pull path with a unified generic driver (`mcp_driver_oci_image_pull` in `lib_mcp.sh`).
- **(mcp) `eidolons mcp images` inventory command** — status table (and `--json` array) across all `oci-image` MCPs: NAME / IMAGE / PRESENT / LOCAL-digest / PINNED-digest / DRIFT / SIZE. Drift = LOCAL ≠ PINNED (catalogue is the authority). Docker absence surfaces as `(n/a)` cells; always exits 0. Junction (binary) is omitted.
- **(mcp) `--no-pull` flag on `install` and `upgrade`** — suppresses auto-pull for air-gap environments; absent image aborts with a name-aware message. Accepted and silently ignored for `kind=binary` (junction).
- **(mcp) Additive optional `source.build` block in `roster/mcps.yaml` and `schemas/mcp-catalogue.schema.json`** — presence gates `--build-locally`; atlas-aci declares it (buildable), crystalium does not (pull-only). `make schema` stays green (block is optional, no `required` change).

### Changed

- **(mcp) Auto-pull on `install` and `upgrade` for oci-image MCPs** — `eidolons mcp install crystalium` now auto-pulls the pinned image when missing, instead of aborting. Fixes the crystalium install pain point. Ordering invariant: auto-pull fires before `.mcp.json` wiring. atlas-aci install branch also honors auto-pull.
- **(mcp) `mcp_driver_oci_image_refresh` is now MCP-agnostic** — previously hardcoded to shell out to `mcp_atlas_aci_pull.sh`, which silently failed for `mcp refresh crystalium`. Now routes through `mcp_driver_oci_image_pull NAME --image-digest <locked>`. Fixes a latent crystalium refresh bug.
- **(mcp) `mcp_refresh.sh --image-digest` override now MCP-agnostic** — the `--image-digest` path in `mcp_refresh.sh` previously hardcoded `mcp_atlas_aci_pull.sh`; now routes through the generic pull driver.
- **(mcp) `eidolons mcp atlas-aci pull` alias re-pointed** (OQ-4) — previously forwarded to `mcp refresh atlas-aci` (lockfile-driven semantics); now forwards to `mcp pull atlas-aci` (catalogue-pin-driven semantics). One DEPRECATED line still emitted; `EIDOLONS_SUPPRESS_DEPRECATED=1` still suppresses it. Scripted callers relying on lockfile-driven semantics should migrate to `eidolons mcp refresh atlas-aci`.
- **(mcp) `mcp_atlas_aci_pull.sh` is now a thin wrapper** (OQ-1.A) — all pull logic consolidated in `mcp_driver_oci_image_pull` in `lib_mcp.sh`. The P0 `--build-locally` invariant and its source-grep guard (T9 Cases 8–9) are preserved; T9 Case 9 now greps `lib_mcp.sh`.

### Fixed

- **(mcp) Generic oci-image install no longer mis-brands its "image not present" error.** `eidolons mcp install crystalium` previously printed an Atlas-ACI-specific message pointing at `eidolons mcp atlas-aci pull`. The message is now name-aware with the correct `docker pull <image>:<version>` remediation; `atlas_aci_check_image` takes an optional caller-supplied message (default text unchanged for atlas-aci callers).
- **(mcp) `eidolons mcp install` is now genuinely idempotent for oci-image MCPs.** The lockfile no-op comparison is canonicalized (sorted object keys + sorted `hosts_wired`), so a repeat install preserves `installed_at` instead of re-stamping it. The lockfile writer sorts `hosts_wired` on write, which previously defeated the no-op against an insertion-order rebuild — latent across all oci-image MCPs, surfaced as a darwin-green / ubuntu-red idempotency test.

## [1.15.0] — 2026-06-02

### Added

- **(memory) CRYSTALIUM v1.2.0 — the mandatory shared-memory mainframe.** Promotes CRYSTALIUM from an opt-in MCP to the team's always-on memory substrate. Caller-identity unlock: a `CRYSTALIUM_CALLER_TIER=T1` env var (wired into the install template) makes Eidolon-originated MCP calls land at trust tier **T1** instead of the conservative T2 default — which previously *denied* `commit→semantic`, `plan_checkpoint`, `plan_replan`, and `execution` writes, leaving Dream consolidation with only thin episodic material. The **ECL `ingest` tool** is now the symbiotic write-spine (each hand-off envelope becomes a T1 memory record, provenance + MIN-trust preserved) and is added to the `roster/mcps.yaml` tool surface (8 tools). Cortex: the always-loaded `EIDOLONS.md` memory protocol is expanded (recall → ingest → commit → session_end + a T0/T1/T3 tier map), with a new on-demand `methodology/cortex/memory-protocol.md` deep table (full surface, layer×tier matrix, Dream triggers/knobs, plan checkpoints, skill admission, forgetting, ECL→ingest mapping) mirrored by `eidolons sync`. Roster pinned to `1.2.0` in both `roster/index.yaml` and `roster/mcps.yaml` (image digest `sha256:84d450ed…`), with a new `cli/src/check_roster_mcp_skew.sh` CI guard so the two files can never drift again, and a `cli/src/stage_mcp_digest.sh` helper that resolves + pins a published OCI index digest. Nexus PRs #210 / #211 / #212.
- **(memory) Team-wide memory pipelines — all six Eidolons embed the protocol in their own methodology.** The cortex mandate is now hardened per-member: every Eidolon's skill text drives `recall` at mission intake (`layers=[semantic, episodic, procedural]`) and `ingest` of its terminal ECL envelope at T1, then `session_end` (Dream trigger), with a graceful-skip contract that falls back to standalone behaviour when CRYSTALIUM is absent (EIIS conformance preserved). Per-cycle extensions: **FORGE** writes `plan_checkpoint`/`plan_replan` during deliberation; **VIGIL** commits corroborated debugging patterns to procedural/semantic in its Learn phase; **APIVR-Δ** uses the full tool surface (incl. `skill_invoke`) and **reconciles its existing local Reflexion store** (`agents/memories/*.md`) as a CRYSTALIUM-primary / local-fallback model — never writing both, with Dream replacing its manual consolidation. Members published in this campaign: **atlas 1.9.0, spectra 4.6.0, apivr 3.4.0, idg 1.5.0, forge 1.6.0, vigil 1.4.0** — each released through the nexus reusable template (attestation-verified) and intaked with full release-integrity metadata. Nexus PRs #213–#218.
- apivr v3.4.0 published in the roster with release integrity metadata.
- vigil v1.4.0 published in the roster with release integrity metadata.
- forge v1.6.0 published in the roster with release integrity metadata.
- idg v1.5.0 published in the roster with release integrity metadata.
- spectra v4.6.0 published in the roster with release integrity metadata.
- atlas v1.9.0 published in the roster with release integrity metadata.
- crystalium v1.2.0 published in the roster with release integrity metadata.

### Changed

- **(mcp) The `oci-image` install driver is now generic and multi-MCP-safe.** Previously hard-coded to atlas-aci, it `sed`-overwrote `.mcp.json` (clobbering sibling servers) and never substituted `__HOME__` — so `eidolons mcp install crystalium` could not coexist with atlas-aci. The driver now renders the catalogue-declared template (substituting `__HOME__`/`__PROJECT_SLUG__`/`__IMAGE_DIGEST__`) and **jq-merges** the server entry, preserving all sibling entries and staying byte-idempotent across re-runs. atlas-aci's fail-closed `--force` guard is retained but made entry-aware (refuses only when its own entry already exists; merges otherwise). Bash 3.2-safe.
- **(ci) Roster Intake's attestation signer-workflow is now member-declared.** The intake pinned `--signer-workflow` to the nexus reusable release template, which only matches source-installed Eidolons that release *through* it. OCI-distributed members (CRYSTALIUM) ship their own canonical release pipeline and sign with their own workflow identity; the intake now reads an optional `release.signer_workflow` from the member's roster entry (joined to `source.repo`) and falls back to the nexus template otherwise — a second legitimate trust anchor, not a relaxation.

## [1.14.0] — 2026-06-01

### Changed

- **(cortex) Delegation through the Eidolons pipeline is now the DEFAULT operating mode when the cortex is wired into a host.** `EIDOLONS.md` gains a new "Default operating mode — delegate by default" paragraph at the top of the `## Dispatch Protocol (always-loaded)` section: every non-trivial request routes through Steps 1–5 and the orchestrator delegates to Eidolon role(s) without implementing, speccing, or scouting directly; direct answers are reserved for trivial, conversational, or single-fact prompts only. The `CORTEX_BLOCK` injected into host docs by `cli/src/sync.sh` is updated to the same effect — the injected block now leads with a **Default operating mode** paragraph stating that routing through the pipeline is mandatory-unless-trivial, not opt-in. The `standard` tier remains the default tier; the TRANCE escalation tier is unchanged — still gated behind both a complexity flag and a stakes flag, never automatic. `cli/tests/cortex.bats` updated in lockstep: the inline CORTEX_BLOCK duplicate is byte-identical to the new `sync.sh` block, and a new assertion (`cortex: injection — block declares delegate-by-default operating mode`) locks the wording in regression.
- **(mcp) Junction wiring is now transport-only — `mcp__junction__*` is no longer injected into any agent's `tools:` allowlist.** Keystone reinterpretation of `grants_to_eidolons: all`: for junction it means transport-*eligibility* (the parent/orchestration layer may dispatch an Eidolon's emitted ECL envelope over the junction bus), not allowlist-*injection*. This keeps reasoning-only FORGE (`tools: none`) and read-only ATLAS/VIGIL role-pure while still routing their hand-offs through junction when present. Implemented via a new `wiring_mode: transport` catalogue field that makes `mcp_wiring_grant_targets` (`cli/src/lib_mcp_wiring.sh`) return zero agent-file targets for junction; `roster/mcps.yaml` `catalogue_version` 1.1 → 1.2 (additive). Contrast: atlas-aci remains an in-agent capability and is still patched into ATLAS's allowlist. Inverts `cli/tests/mcp_wiring.bats` W1.1–W1.3 (previously asserted injection). Decision rubrics + GIVEN/WHEN/THEN: `.spectra/plans/2026-06-01-agent-tools-junction-bus-spec.md`.
- **(docs) `atlas aci install` → `atlas aci wire` across every nexus-side consumer surface (ATLAS v1.8.0 rollout).** Flips `README.md`, `docs/atlas-aci.md`, `docs/cli-reference.md`, the frozen spec-traceability artefact under `docs/specs/atlas-aci-artifacts/`, and the 33 `run_aci --install` invocations across its bats helper suite. The `--container` and `--runtime` flag forms are replaced with the positional runtime (`atlas aci wire [docker|podman]`; absent = host mode). Decision rubrics and GIVEN/WHEN/THEN stories: `.spectra/plans/2026-05-27-atlas-aci-ux-fixes-spec.md` §5.1, §5.2. PR #199 (downstream of upstream `Rynaro/ATLAS#35`).
- **(test) `cli/tests/doctor.bats` D-T3.1–D-T3.5 + D-T-WIRE active.** PR #199 flipped D-T3.3's pinned-string assertion from `install` to `wire` and seeded `D-T-WIRE` as a skip-pending tracking marker. PR #201 re-introduced the UID/GID + bind-path probes (see Added below) and removed every skip in the family — the wire hint is now emitted live by the no-`-u` warn.

### Added

- **CRYSTALIUM — seventh roster member (shared memory substrate).** New entry in `roster/index.yaml` with `capability_class: memory`, methodology `CRYSTALIUM v1.0` (cycle `recall→commit→consolidate→forget`), source `Rynaro/CRYSTALIUM`, shipped version `1.0.0` with full release-integrity metadata (commit `459d222`, tree `77acbeb`, `github_attestation: true`). A four-layer memory substrate (`Episodic/Semantic/Procedural/Execution`) with tier-gated writes, hybrid recall, Dream consolidation, and principled forgetting; bidirectional hand-offs with all six pipeline members (`atlas, spectra, apivr, idg, forge, vigil`). PRs #203 / #204.
- **CRYSTALIUM MCP catalogue entry + nexus wiring.** New MCP in `roster/mcps.yaml` with `kind: oci-image`, `grants_to_eidolons: all`, exposing `mcp__crystalium__*` (`recall, commit, update, skill_invoke, plan_checkpoint, plan_replan, session_end`). Source image `ghcr.io/rynaro/crystalium` `0.1.0` (digest `sha256:f524654…`, released 2026-05-28); host-wiring template `cli/templates/mcp/crystalium.mcp.json.tmpl`. Wired into the nexus alongside the always-loaded `EIDOLONS.md` cortex memory protocol (append-only, `grants_to_eidolons: all`). PR #202.
- **Junction `.mcp.json` server registration — closes "junction ignored by default".** The `kind: binary` driver installed the junction binary but never wrote a `.mcp.json` server entry (no template existed), so the MCP server was never registered and `mcp__junction__*` tools never existed at runtime. New `cli/templates/mcp/junction.mcp.json.tmpl` (stdio server entry, `__HOME__`-style data-only substitution mirroring `atlas-aci.mcp.json.tmpl`) plus `_mcp_binary_merge_mcp_json` in `cli/src/lib_mcp.sh` — a `jq` merge-not-clobber that preserves a pre-existing atlas-aci entry and all sibling servers, is byte-idempotent across re-runs, gates registration on binary-present (never registers a server pointing at an absent binary), and is bash-3.2-safe. Wired on both the fresh-install and already-installed branches; uninstall removes the entry. Reaches every host vendor via project-level `.mcp.json` (no per-agent edits). New tests: `cli/tests/mcp_install.bats` T7-G2/G2b/G3/G3b/G3c and `cli/tests/mcp_wiring.bats` T7-G1/G4.
- **`methodology/cortex/handoff-graph.md` hand-off transport policy + ATLAS MCP-first convention.** When junction is registered, the parent dispatches emitted ECL envelopes over the junction bus; ECL on-disk envelopes remain the wire-format/fallback. ATLAS prefers `mcp__atlas_aci__*` for structural reads when atlas-aci is present (native `Read/Grep/Glob` fallback). Deep-reference table only — `EIDOLONS.md` (≤900-token always-loaded cortex) is untouched.
- **`wiring_mode` enum in `schemas/mcp-catalogue.schema.json`** (additive; `catalogue_version` 1.1 → 1.2). Value `transport` marks a bus-style MCP whose grant confers transport-eligibility rather than per-agent tool exposure.
- **atlas v1.8.0 in `roster/index.yaml` with full release-integrity metadata** (commit `c8ee194`, tree `8da807f`, archive `dbc353fb…`, github-attestation verified). Intaked via PR #198 from the `Release ATLAS v1.8.0` workflow_dispatch — no hand-tagging, no hand-edited integrity fields. Upstream diff: 19 files, +947/-263 (`commands/aci.sh` rewrite, four new bats files, mechanical sweep of nine existing test files).
- **`docs/specs/atlas-aci-artifacts/commands/aci.sh` wholesale-replaced with the merged ATLAS v1.8.0 source** so the frozen spec artefact tracks the live upstream. New `T-NX-WIRE-RT` test in `docs/specs/atlas-aci-artifacts/tests/operational.bats` asserts the positional runtime flows through the helper. PR #199.
- **`_mcp_driver_oci_uid_bind_probes` in `cli/src/lib_mcp.sh`** — UID/GID + bind-path probes that were lifted out of `doctor.sh` during the MCP-store migration. The no-`-u` warn line includes the `eidolons atlas aci wire` hint (ATLAS v1.8.0 rename). Reused by both `mcp_driver_oci_image_health` (via the MCP lockfile path) and the new doctor Check 7b. PR #201.
- **Doctor Check 7b** (`cli/src/doctor.sh`) — reads `.mcp.json` directly (independent of `eidolons.mcp.lock`) so probe coverage is reachable even when atlas-aci isn't tracked in the lockfile. `err`-level probe lines increment ERRORS (non-zero exit); `warn`-level lines print a yellow advisory without affecting exit code. PR #201.
- **`cli/tests/mcp_health.bats`** — five new tests cover the UID/bind probe surface end-to-end via `eidolons mcp health atlas-aci` (matching UID, mismatch, no-flag, missing bind path, absent `.mcp.json`). PR #201.
- vigil v1.3.2 published in the roster with release integrity metadata.
- forge v1.5.2 published in the roster with release integrity metadata.
- idg v1.4.2 published in the roster with release integrity metadata.
- apivr v3.3.1 published in the roster with release integrity metadata.
- spectra v4.5.2 published in the roster with release integrity metadata.
- atlas v1.7.2 published in the roster with release integrity metadata.

## [1.13.4] — 2026-05-27

### Fixed

- Backfill helper now also adds `.roster_ref` (and other sidecar files) to
  `.gitignore`. Pre-v1.11.0 installs no longer trip `eidolons upgrade
  self`'s dirty-tree check after backfill (was: needed --force; now: clean).
  `nexus_ensure_roster_ref` calls the new `nexus_ensure_gitignore_sidecar`
  helper for all four sidecars (`.install_date`, `.install_ref`,
  `.install_commit`, `.roster_ref`) — idempotent, no-op when entries
  already present.

## [1.13.3] — 2026-05-27

### Fixed

- Auto-backfill `.roster_ref` for installs predating v1.11.0. Users who
  upgraded into v1.11.0+ from older nexus (or ran `upgrade self` before
  v1.11.0 existed) didn't have the file on disk; `nexus_refresh()` fell
  back to `.install_ref` (the install tag) and the cache never tracked
  main. Now `nexus_refresh()` and `upgrade self` both ensure the file
  exists, defaulting to `main` (or `$EIDOLONS_ROSTER_REF` if set).

## [1.13.2] — 2026-05-27

### Fixed

- `eidolons canary --list` now distinguishes parseable missions (✓) from
  legacy-format files (⚠) and no-file (·). Summary line counts all three states.

## [1.13.1] - 2026-05-26

### Fixed

- `eidolons doctor --deep` methodology remedy message now points at real commands (was suggesting non-existent `--force` flag on `eidolons sync` and `eidolons add`). Corrected to `eidolons sync` (re-installs each member) and `eidolons remove <name> && eidolons add <name>`. Same invalid flag references scrubbed from dispatch-freshness error messages, `lib.sh` SPEC.md warning, `verify-release` help text and runtime footer, and `docs/cli-reference.md`.

## [1.13.0] - 2026-05-26

### Added

- **(feat) `eidolons canary` — Layer 3 methodology integrity (behavioral smoke).** New subcommand that bridges prompt-print → manual-run → validate-from-file for human-in-the-loop behavioral verification of installed Eidolons. Three modes: **prompt** (`eidolons canary <name>`) prints the canary mission prompt + expected output shape + validation criteria from `evals/canary-missions.md` in the per-version cache; **validate** (`eidolons canary <name> --validate <file>`) checks a saved LLM response against the mission's structured criteria (PASS/FAIL/INCONCLUSIVE per criterion); **list** (`eidolons canary --list`) scans the cache and reports which Eidolons have canary missions authored. Layer 3 of the three-layer integrity guarantee (Layer 1 = `doctor --deep` D4; Layer 2 = `verify-release`; Layer 3 = `canary`).
- **(feat) Validation DSL** — four verbs (`contain heading`, `contain phrase`, `mention paths`, `have token count between X and Y`) × two severities (`MUST` = FAIL on mismatch; `SHOULD` = INCONCLUSIVE on mismatch). Unrecognized criterion lines → INCONCLUSIVE (permissive while format settles across Eidolons). Missing `evals/canary-missions.md` → soft warn + exit 0 (not a failure).
- **(feat) `--mission <id>`, `--json`, `--list`, `--validate <file>` flags.** `--json` emits machine-readable output with `schema_version: "1.0"` on every emission. `--mission` selects a non-default mission by ID. Exit codes: 0 = success/INCONCLUSIVE-only; 1 = ≥1 FAIL criterion; 2 = misuse.
- **(test) `cli/tests/canary.bats` — 12 tests (CAN-1..CAN-12)** covering prompt mode, missing missions (soft), unknown name, all-PASS, MUST FAIL, SHOULD downgrade, empty file, mission selection, unknown mission ID, list mode, JSON schema, and unrecognized-criterion INCONCLUSIVE.

### Changed

- **`cli/eidolons` dispatcher** — adds `canary)` case after `verify-release`. One usage line added under `Commands:`.
- **`docs/cli-reference.md`** — new `canary` section documenting all three modes, flags, validation DSL grammar, and JSON schema.

### Notes

- No EIIS change. No per-Eidolon repo change. `evals/canary-missions.md` is convention-only for v1.13.0; promoted to EIIS contract after multi-Eidolon convergence.
- 5 of 6 Eidolons have authored canary missions; VIGIL missions are a follow-up (handled gracefully as soft-missing).
- vigil v1.3.1 published in the roster with release integrity metadata.

## [1.12.0] - 2026-05-26

### Added

- **(feat) `eidolons verify-release` — Layer 2 methodology integrity (functional re-derivation).** New subcommand that catches drift between a consumer's installed `.eidolons/<name>/` tree and what a fresh install of the pinned upstream version would produce today. For each Eidolon in `eidolons.lock`, runs its `install.sh` into a temp directory and SHA-256 diffs the trees. Reports OK / DIFFER / MISSING / EXTRA per file (`install.manifest.json` excluded — timestamp drift expected). Catches: local tampering after install, mid-install corruption that fooled `doctor --deep` D4, accidentally deleted files, and files added under `.eidolons/<name>/` that aren't part of the install. Layer 2 of the three-layer integrity guarantee (Layer 1 = `doctor --deep` D4 shipped v1.11.0; Layer 3 = `eidolons canary` scheduled v1.13.0).
- **(feat) `--eidolon NAME` (repeatable), `--strict`, `--no-fetch`, `--json` flags.** Default invocation verifies all members in lock and exits 0 even on drift (WARN-only). `--strict` exits 1 on any drift (CI gate). `--no-fetch` uses cache only (offline). `--json` emits machine-readable report.
- **(test) `cli/tests/verify_release.bats` — 12 tests (VR-1..VR-12)** covering OK, drift, missing, extra, single-eidolon scoping, `--strict` exit, `--no-fetch` cache miss, and `--json` schema shape.

### Changed

- **`cli/eidolons` dispatcher** — adds `verify-release` case alongside the existing `verify` case. The legacy `verify` subcommand (lock-vs-roster check) is unchanged.
- **`docs/cli-reference.md`** — new section documenting `verify-release`.

### Notes

- No EIIS change. No per-Eidolon repo change. No release-time artifact added. Layer 2 is implemented entirely in nexus by re-running existing per-Eidolon installers.
- spectra v4.5.1 published in the roster with release integrity metadata.
- idg v1.4.1 published in the roster with release integrity metadata.
- forge v1.5.1 published in the roster with release integrity metadata.
- atlas v1.7.1 published in the roster with release integrity metadata.
- vigil v1.3.0 published in the roster with release integrity metadata.
- spectra v4.5.0 published in the roster with release integrity metadata.
- idg v1.4.0 published in the roster with release integrity metadata.
- forge v1.5.0 published in the roster with release integrity metadata.
- atlas v1.7.0 published in the roster with release integrity metadata.
- apivr v3.3.0 published in the roster with release integrity metadata.
- vigil v1.2.1 published in the roster with release integrity metadata.
- spectra v4.4.1 published in the roster with release integrity metadata.
- idg v1.3.1 published in the roster with release integrity metadata.
- forge v1.4.1 published in the roster with release integrity metadata.
- atlas v1.6.1 published in the roster with release integrity metadata.
- apivr v3.2.1 published in the roster with release integrity metadata.
- vigil v1.2.0 published in the roster with release integrity metadata.
- spectra v4.4.0 published in the roster with release integrity metadata.
- idg v1.3.0 published in the roster with release integrity metadata.
- forge v1.4.0 published in the roster with release integrity metadata.
- atlas v1.6.0 published in the roster with release integrity metadata.
- apivr v3.2.0 published in the roster with release integrity metadata.

## [1.11.0] - 2026-05-26

### Added

- **(feat) `eidolons doctor --deep` — Layer 1 methodology integrity gates (D1..D6).** The `--deep` flag appends a new "Methodology integrity" section after the existing 14 fast checks. Six gates run per installed member: D1 — agent.md token budget (≤ 1000 tokens, wc-w × 4/3 heuristic); D2 — agent.md outbound link resolution; D3 — SPEC.md outbound link resolution (the gate that would have caught the v1.4 SPEC.md broken refs); D4 — manifest_sha256 content drift vs `eidolons.lock` (WARN-skip for legacy pre-1.4 entries); D5 — host-vendor agent body contract (must reference agent.md + SPEC.md, zero legacy `<UPPER>.md` refs); D6 — `.claude/skills/<n>-<basename>/SKILL.md` dual-write SHA parity. Checks are read-only and do not mutate `.eidolons/`; methodology fixes require `eidolons sync --force`. Bash 3.2 compatible.
- **(feat) `.roster_ref` sidecar — separate CLI self-pin from roster-refresh target (B1).** `cli/install.sh` now writes `.roster_ref` ← `${EIDOLONS_ROSTER_REF:-main}` alongside the existing `.install_ref`. `nexus_refresh()` reads `.roster_ref` via the new `nexus_roster_ref()` helper (fallback chain: `.roster_ref` → `.install_ref` → skip). This fix ensures `eidolons upgrade self` can rewrite `.install_ref` to a new version tag without corrupting the roster-refresh target.
- **(feat) `EIDOLONS_ROSTER_REF` env var.** Optional override on bootstrap that controls which branch/tag `nexus_refresh` tracks. Common values: `main` (default), a specific branch, or a long-lived tag for offline-pinned shops. Once written to `.roster_ref`, the file is the source of truth; re-running `install.sh` with a different value overwrites.
- **(feat) `nexus_roster_ref()` lib helper (B1 fallback).** New function in `cli/src/lib.sh` with resolution order: `$NEXUS/.roster_ref` → `$NEXUS/.install_ref` → empty string. The fallback preserves v1.10.0 behaviour for consumers who haven't re-bootstrapped through v1.11.0's `install.sh`.
- **(feat) `eidolons upgrade` calls `nexus_refresh` before member resolution (B2).** Inserted at the top of `cli/src/upgrade.sh` (after argument parsing, before helpers). Both mutating upgrade and `--check` now report freshly visible member versions instead of stale cached roster data. Skip-gating is internal to `nexus_refresh` (`EIDOLONS_NEXUS` / `EIDOLONS_SKIP_REFRESH`), so test fixtures and offline CI remain unaffected.
- **(test) `cli/tests/doctor_deep.bats` — 18 tests (DD-1..DD-18)** covering D1-D6 OK+FAIL paths, `--deep` flag parsing, ordering invariant (fast checks before methodology), and read-only gate (doctor does not mutate .eidolons/).
- **(test) `cli/tests/roster_ref.bats` — 9 tests (RR-1..RR-9)** covering install `.roster_ref` write (default + override), `nexus_roster_ref` fallback chain, `upgrade_self` invariant, `nexus_refresh` reads `.roster_ref`, and B2 upgrade/--check refresh.
- **(test) Extensions to `install.bats` (2), `upgrade_self.bats` (1), `cache_freshness.bats` (2)** for full B1 coverage.
- **(lib) Six `deep_check_*` helpers in `cli/src/lib.sh`** (`deep_check_agent_token_budget`, `deep_check_agent_links`, `deep_check_spec_links`, `deep_check_manifest_integrity`, `deep_check_host_agent_body`, `deep_check_skills_dual_write`) plus shared `_deep_check_outbound_links`. All bash 3.2 compatible.

### Changed

- **`nexus_refresh()` reads `.roster_ref` via `nexus_roster_ref()` (B1).** Previously read `.install_ref` directly via `nexus_install_ref()`. Fallback chain preserves exact v1.10.0 behaviour for consumers without `.roster_ref`.
- **`eidolons upgrade` auto-refreshes nexus cache before member resolution (B2).** Previously only `sync` and `init` called `nexus_refresh`; upgrade could report stale versions.
- **`upgrade_self.sh` `.gitignore` sidecar list extended to include `.roster_ref`.** The `.roster_ref` file is excluded from the nexus working tree so `git status` stays clean after install/upgrade.

### Fixed

- **B1: `.install_ref` conflation bug.** After `eidolons upgrade self` rewrote `.install_ref` to a new CLI tag (e.g. `v1.11.0`), subsequent `nexus_refresh` calls fetched that tag instead of `main`, causing consumers to never pick up new roster intakes until another `upgrade self`. Fixed by separating `.roster_ref` from `.install_ref`.
- **B2: `eidolons upgrade` stale-cache bug.** `eidolons upgrade --check` reported "all up-to-date" when the local cached roster was stale, even after a new Eidolon version was published. Fixed by calling `nexus_refresh` at the start of `upgrade.sh`.

## [1.10.0] - 2026-05-26

### Added

- **(feat) `nexus_refresh` — auto-refresh nexus cache on `sync` and `init` (Fix A).** `cli/src/sync.sh` and `cli/src/init.sh` now call `nexus_refresh` before any roster reads. The helper performs a `git fetch --depth 1 origin <ref>` + `reset --hard FETCH_HEAD` against the pinned ref recorded in `$NEXUS/.install_ref`, ensuring the local nexus cache reflects the latest published Eidolon versions without requiring an explicit `eidolons upgrade`. Network failures emit a `warn` and return 0 (non-fatal; stale cache is used). Implemented in `cli/src/lib.sh`. Bash 3.2 compatible.
- **(feat) `EIDOLONS_SKIP_REFRESH=1` opt-out.** Users who need offline-first or deterministic builds can set this env var to disable auto-refresh entirely. Useful in CI environments without outbound network access.
- **(feat) `EIDOLONS_NEXUS=<path>` continues to skip refresh (local-checkout dev pattern preserved).** When `EIDOLONS_NEXUS` is set to a non-empty value, `nexus_refresh` is a no-op — the local checkout is used as-is, enabling test isolation without network access.
- **(feat) Standard `^X.Y.Z` semver caret-range resolution (Fix B).** `cli/src/sync.sh` now resolves member version constraints through `resolve_version_constraint` (new helper in `cli/src/lib.sh`) instead of stripping the constraint prefix. Constraint forms: `^X.Y.Z` (>=base, <(X+1).0.0; `^0.Y.Z` locks minor per npm semantics), `~X.Y.Z` (>=base, <X.(Y+1).0), `=X.Y.Z` or bare `X.Y.Z` (exact pin). The resolver queries the roster's `versions.latest`, `versions.pins.stable`, and `versions.releases` to find the highest satisfying version. Missing roster entries fall back to stripping the operator prefix (legacy compat). Bash 3.2 compatible: no associative arrays, no mapfile.
- **(test) `cli/tests/cache_freshness.bats` — 17 tests (RF-1..7, sync-NEXUS, SC-1..9)** covering: EIDOLONS_NEXUS skip, EIDOLONS_SKIP_REFRESH skip, no-.git skip, absent-.install_ref skip, network-failure warn+0, local-fixture fetch+reset round-trip, empty-EIDOLONS_NEXUS does-not-block, sync integration guard, and all caret/tilde/exact resolver variants including the 0.x semver special-case.

### Changed

- **`eidolons sync` member version resolution.** Previously used naive prefix-stripping (`${version#^}`). Now calls `resolve_version_constraint` for semantic range resolution. Exact pins (`1.0.0`, `=1.0.0`) pass through unchanged; range constraints (`^X.Y.Z`, `~X.Y.Z`) resolve to the highest satisfying version in the roster. Enables seamless rollouts: when a new Eidolon version is published to the roster, `eidolons sync` picks it up automatically on next run without any manifest changes.

## [1.9.0] - 2026-05-25

### Added

- **(feat) Catalogue-driven MCP → Eidolon tool wiring.** Installing an MCP from `roster/mcps.yaml` now automatically grants its tool surface to the relevant installed Eidolons by patching the per-host agent files (`.claude/agents/<name>.md`, `.codex/agents/<name>.md`). Implemented in `cli/src/lib_mcp_wiring.sh` (~900 LOC, Bash 3.2). After `eidolons mcp install junction`, every installed Eidolon (including FORGE) can invoke `mcp__junction__*` tools without manual frontmatter edits. After `eidolons mcp install atlas-aci`, only ATLAS gets `mcp__atlas_aci__*`. (PR #148)
- **(feat) `mcps.yaml` catalogue fields `grants_to_eidolons` and `exposes_tools`.** Catalogue `catalogue_version` bumps `1.0` → `1.1` (additive, back-compat). `grants_to_eidolons` accepts `all` or `[<list>]`; `exposes_tools` declares both a `glob` (e.g. `mcp__junction__*`) and an explicit tool `list`. The schema (`schemas/mcp-catalogue.schema.json`) is updated to declare both as non-required properties — older catalogues remain valid.
- **(feat) Five lifecycle hooks for MCP wiring** — `eidolons mcp install`, `mcp uninstall`, `mcp refresh`, `mcp sync/upgrade`, and project `sync.sh`. The project-sync hook is the load-bearing one: per-Eidolon installers rewrite `.claude/agents/<name>.md` from a heredoc on every sync, so wiring re-applies *after* the member loop. `eidolons add` inherits the wiring re-application via its `exec sync.sh` tail call.
- **(feat) Frontmatter sentinel `x-eidolons-mcp-wired: [<names sorted>]`** in patched agent files. Used for byte-identity idempotency (repeat installs produce no diff) and reversible uninstall (removing the last MCP also removes the sentinel line entirely). Tracked end-to-end via `eidolons.mcp.lock` `hosts_wired[]`.
- **(feat) Per-host patching strategy.** Claude-code (`.claude/agents/*.md`) gets a CSV-append in the `tools:` frontmatter line, including the `tools: none` → `tools: mcp__<name>__*` replacement carve-out for FORGE. Codex (`.codex/agents/*.md`) gets a YAML block-sequence append. Opencode (`.opencode/agents/*.md` — `permission:` model) is a no-op stub for v1.9 (deferred to a follow-up). Cursor has no per-agent permission gate and is intentionally not touched.
- **(test) `cli/tests/mcp_wiring.bats` — 21 tests (W1.1–W10.1)** covering catalogue resolution, target Eidolon enumeration, per-host patch correctness, idempotency (no byte drift on repeat runs), reversibility (unpatch returns the file to its pre-patch SHA), the `tools: none` carve-out, lockfile `hosts_wired[]` round-trip, and the sync.sh re-application invariant.

### Changed

- **`roster/mcps.yaml`** — `junction` declares `grants_to_eidolons: all` and `exposes_tools.{glob, list}`; `atlas-aci` declares `grants_to_eidolons: [atlas]` and `exposes_tools.{glob, list}`. `related_eidolons[]` remains as an editorial hint with distinct semantics (informational vs. machine-driven wiring).

## [1.8.1] - 2026-05-25

### Fixed

- **(fix) `eidolons sync` universal marker-guard across closed vendor set.** The compose-pass marker-guard, previously hardcoded to `AGENTS.md`, now iterates the full closed vendor set (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`). Vendor files carrying substantive Eidolon content markers (excluding the round-3 `dispatch-pointer` block) are auto-added to `_compose_sources` and hoisted into `EIDOLONS.md`. Fixes the v1.8.0 regression where `CLAUDE.md` retained installer-written blocks under `pointer_targets=[AGENTS.md]` + `shared_dispatch=true` + `hosts.wire=[claude-code]`. (round 5)
- **(fix) `eidolons.lock` `composition.hoisted_from` reflects actual compose sources.** Previously a hardcoded `[CLAUDE.md, AGENTS.md]` literal regardless of input. Now derived from the actual `_compose_sources` list after the universal marker-guard runs. Empty (`[]`) when no sources processed. (round 5)
- **(fix) `EIDOLONS.md` preamble accuracy.** The on-disk preamble previously asserted that vendor files are pointer files. Updated wording: "Vendor files (`CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.github/copilot-instructions.md`) may serve as dispatch-pointer surfaces; pointer mapping is governed by `hosts.pointer_targets` in `eidolons.yaml`." (round 5)

### Changed

- **(BREAKING-LIKE, patch-axis) `eidolons init --multi-pointer` now defaults to ON in both interactive and non-interactive modes.** The interactive TTY prompt now defaults to `[Y/n]`. Non-interactive flows that hit AGENTS-precedence (`AGENTS.md` exists, `--shared-dispatch`, or `codex ∈ hosts.wire`) now derive `pointer_targets = AGENTS.md ∪ host-derived-wired-vendor-files` by default. **To preserve v1.8.0 AGENTS-only semantics, pass the new `--no-multi-pointer` flag explicitly.** This is a default flip on a bug-fix axis: v1.8.0's default-N value was the root cause of the `CLAUDE.md` regression. CI scripts that ran `eidolons init --non-interactive --shared-dispatch` and relied on `pointer_targets=[AGENTS.md]` only must add `--no-multi-pointer` to retain the prior behaviour. (round 5)

### Added

- **(feat) `eidolons init --no-multi-pointer` flag.** Explicit opt-out for the default-Y multi-pointer behaviour. When passed, `pointer_targets` stays `[AGENTS.md]` (under AGENTS-precedence). Mutually exclusive with `--multi-pointer` (exit code 2 if both passed). Wired vendor files outside `pointer_targets` still get their content hoisted by the universal marker-guard, but no dispatch-pointer is written to them — they become empty. Doctor Check 14 surfaces this "noisy opt-out" state. (round 5)
- **(feat) Doctor Check 14 — wired vendor file marker drift.** Warn-only by default; `die()` under `hosts.strict=true`. Fires when a vendor file in the closed set has non-dispatch-pointer Eidolon content markers AND its host is in `hosts.wire` AND the file is not in `hosts.pointer_targets`. Remedy text recommends `eidolons init --re-derive --multi-pointer` or `eidolons sync`. (round 5)

### Migration notes (v1.8.0 → v1.8.1)

1. Run `eidolons sync` once — the universal marker-guard hoists installer-written content from `CLAUDE.md`/`GEMINI.md`/`.github/copilot-instructions.md` into `EIDOLONS.md`. Vendor files outside `pointer_targets` lose their substantive markers (but do not yet get a dispatch-pointer).
2. Run `eidolons doctor` — Doctor Check 14 warns about the drift on each affected wired vendor file.
3. Run `eidolons init --re-derive` — updates `hosts.pointer_targets` to include wired vendor files (default-Y multi-pointer). All other manifest fields are preserved.
4. Run `eidolons sync` again — every vendor file in `pointer_targets` now gets a dispatch-pointer block; `EIDOLONS.md` content is unchanged (idempotent).

To preserve v1.8.0 AGENTS-only semantics, pass `--no-multi-pointer` on the `--re-derive` invocation. Doctor Check 14 will continue to warn (informational, not coercive); silence it by accepting the dispatch-pointer mirror or by adding the files to `pointer_targets` manually.

## [1.8.0] - 2026-05-25

### Added
- `eidolons init` now follows an **AGENTS-precedence** rule: if `AGENTS.md` exists on disk, `hosts.shared_dispatch=true`, or `codex ∈ hosts.wire`, `hosts.pointer_targets` is automatically set to `[AGENTS.md]`. Replaces v1.7.0's default-N exclusivity prompt with deterministic derivation. (#TBD round 4)
- New flag `eidolons init --re-derive` — migration tool that re-runs the pointer_targets derivation against an existing manifest, preserving every other field byte-for-byte. Use to upgrade v1.7.0 projects to round-4 semantics.
- New flag `eidolons init --pointer-targets=CSV` — explicit pointer_targets override (bypasses derivation). Warns when `AGENTS.md` exists on disk but isn't in the supplied set.
- New flag `eidolons init --multi-pointer` (also an interactive TTY-prompt fallback, default-N) — when AGENTS-precedence triggers, additionally wires host-derived vendor files (CLAUDE.md, GEMINI.md, etc.) as pointer targets alongside AGENTS.md.
- `eidolons sync` now emits a **sync drift warning** when `AGENTS.md` carries Eidolon content markers but isn't in the active `hosts.pointer_targets`. Remediation: `eidolons init --re-derive`.
- New P0 invariant + bats test `cli/tests/dispatch_pointer_flatness.bats` enforcing flat dispatch-pointer chains (every vendor file points only at `./EIDOLONS.md`; no vendor-to-vendor references).

### Changed
- `compose_eidolons_md` now hoists `AGENTS.md` content whenever `AGENTS.md` carries any Eidolon content marker block (excluding the round-3 `dispatch-pointer` block), regardless of `hosts.pointer_targets` membership. This auto-cleans installer-written AGENTS.md content from `shared_dispatch=true` projects even before the manifest catches up.
- Case-specific init messages now print when AGENTS-precedence triggers: Case A (codex wired) cites EIIS §4.1.0; Case B (non-codex precedence) explains that wired hosts read their primary file only with `--multi-pointer`.

### Migration notes (v1.7.0 → v1.8.0)
1. Run `eidolons sync` once — the marker-guard hoist auto-cleans installer-written `AGENTS.md` content into `EIDOLONS.md`. A loud `warn` line will explain the next step.
2. Run `eidolons init --re-derive` — updates `hosts.pointer_targets` to `[AGENTS.md]` (or per the precedence rule). All other manifest fields are preserved.
3. Run `eidolons sync` again — `AGENTS.md` becomes a thin dispatch-pointer to `./EIDOLONS.md`. The orphan dispatch-pointer block in `CLAUDE.md` (if any) is harmless and may be removed by hand.

### Removed
- The v1.7.0 default-N AGENTS-exclusivity prompt and the multi-vendor `ui_pick_vendors` path in `eidolons init`. Pointer-target selection is now deterministic via derivation + `--pointer-targets` / `--multi-pointer` flags.

## [1.7.0] - 2026-05-25

### Added

- **(feat) `hosts.pointer_targets` manifest field (R3-D4, D5, D12).** New optional array field in `eidolons.yaml` under `hosts.pointer_targets` listing the vendor files that receive the EIDOLONS `dispatch-pointer` block and cortex injection. When absent, defaults to the set derived from `hosts.wire` via the vendor→file mapping table (`claude-code→CLAUDE.md`, `codex/opencode→AGENTS.md`, `gemini→GEMINI.md`, `copilot→.github/copilot-instructions.md`, `cursor→none`). `eidolons init` in interactive mode drives this via a new AGENTS-exclusivity short-circuit + `ui_pick_vendors` multi-vendor picker. `--non-interactive` derives automatically from `hosts.wire`. Persisted to `eidolons.lock` in a new `hosts:` block.

- **(feat) AGENTS-first exclusivity short-circuit + `ui_pick_vendors` (R3-D2).** `eidolons init` in interactive mode detects vendor files on disk, offers an AGENTS.md-exclusivity prompt when `AGENTS.md` is present, then falls through to `ui_pick_vendors` for multi-vendor cases. Letter shortcuts: `c=CLAUDE.md`, `a=AGENTS.md`, `g=GEMINI.md`, `i=.github/copilot-instructions.md`, `A=all`; Enter accepts the host-derived default.

- **(feat) Doctor Check 13 — legacy `<name>-pointer` stub detection (R3-D10).** Warn-only scan of all pointer-target vendor files for `<!-- eidolon:<name>-pointer start -->` markers left by v1.6.0. Excludes the legitimate `dispatch-pointer` block. Remedy text: `eidolons sync`.

### Fixed

- **(fix) Pointer block consolidation — drop `<name>-pointer` stubs (R3-D1).** `compose_eidolons_md` no longer writes `<!-- eidolon:<name>-pointer -->` stubs back into vendor files. Instead, `remove_marker_block "${name}-pointer"` runs per Eidolon per source file during each compose pass, cleaning up v1.6.0-era stubs automatically. The `dispatch-pointer` block remains the sole `./EIDOLONS.md` reference per vendor file.

- **(fix) Newline hygiene in `upsert_marker_block` append mode (R3-D3).** Replaced unconditional `printf '\n%s\n'` with a `tail -c 2 | od -An -c` tail-byte sniffer: appends `\n\n` (empty tail), `\n` (single trailing newline), or nothing (already two trailing newlines). Prevents leading-blank accumulation on repeated appends.

- **(fix) One-time `awk` collapse pass cleans v1.6.0 leading-blank pollution (R3-D9).** `compose_eidolons_md` now calls `collapse_consecutive_blanks` (POSIX awk, `cmp -s` idempotency guard) after the per-member loop per source file, collapsing runs of 3+ newlines to a single blank line.

- **(fix) `apply_dispatch_pointers` driven by `pointer_targets` not constant (R3-D6).** `DISPATCH_POINTER_VENDORS` constant removed; the function now takes `pointer_targets_csv` as its first argument. `sync.sh` resolves this from the manifest (or derives from `hosts.wire`) and passes it explicitly. `AGENTS.md` is a first-class target when present in `pointer_targets`.

## [1.6.0] - 2026-05-24

### Fixed

- **(fix) `export EIDOLONS_VERSION` in dispatcher (R2B-1).** `cli/eidolons` now exports `EIDOLONS_VERSION` after the assignment so `exec`'d subcommand scripts (`init.sh`, `sync.sh`, `upgrade.sh`) read the real nexus version instead of hitting the `${EIDOLONS_VERSION:-1.0.0}` fallback. Fresh `eidolons init` now stamps `eidolons.yaml` and `eidolons.lock` with the actual installed version.

- **(fix) `chmod 0644` after every `mv "$tmp" "$dst"` site (R2B-3).** `cli/src/lib.sh::upsert_marker_block` (rewritten + created branches), `lib.sh::remove_marker_block`, `lib_eidolons_md.sh::compose_eidolons_md`, `sync.sh` LOCK_TMP path, and `sync.sh`/`upgrade.sh` `install.manifest.json` rewrite paths now restore the expected 0644 mode after the `mktemp` → `mv` pattern. `AGENTS.md` (append-only path) was already 0644; no change there.

### Added

- **(feat) `eidolons migrate-stamp` command (R2B-5).** New opt-in verb to rewrite stale version stamps in `eidolons.yaml` (line 2 header comment) and `eidolons.lock` (`eidolons_cli_version:` field) to match the current nexus VERSION. Idempotent; supports `--dry-run`. No git operations — user commits the result. Surfaced by Doctor Check 12.

- **(feat) `eidolons doctor` Check 12 — version-stamp drift detector (R2B-2).** Warns when `eidolons.lock`'s `eidolons_cli_version` (or `eidolons.yaml`'s header comment when the lockfile is absent) does not match the current nexus VERSION. Warn-only (exit code 0); remedy text points to `eidolons migrate-stamp`. Check 12 follows Check 11 (AGENTS.md drift, R2A).

### Chore

- **(chore) Bump `comm.envelope_version` to `"2.0"` across all 6 shipped Eidolons in `roster/index.yaml` (R2B-4).** Eliminates 6 `ECL version mismatch` warn lines per `eidolons sync` run. ECL 2.0 ratification at `Rynaro/eidolons-ecl` is a separate, ongoing concern; this commit documents the wire reality (all 6 Eidolons already ship `ECL_VERSION=2.0`).

- **(chore) Prune empty `.github/` directories after host-leakage path-pattern pass (R2B-6).** `host_prune_path_patterns` in `lib_host_prune.sh` now runs `find "$target" -type d -empty -delete` after the per-file prune loop. Removes empty `.eidolons/<name>/.github/` leftovers (e.g. `atlas`) that the file-only prune missed.

### Added (round 2 features — R2A)

- **(feat) Symmetric `AGENTS.md` hoist into `EIDOLONS.md` (R2A-1).** `compose_eidolons_md`
  now accepts a second arg `sources` (default: `./CLAUDE.md ./AGENTS.md`) and scans
  both files symmetrically. Per-Eidolon content blocks in `AGENTS.md` are hoisted into
  `EIDOLONS.md` and replaced with `<!-- eidolon:<name>-pointer -->` blocks, matching
  the pointer pattern already established for `CLAUDE.md` in v1.5.0. Both source files
  become thin pointer files; `EIDOLONS.md` is the single canonical content surface.
  Lockfile `composition.hoisted_from` updated to `[CLAUDE.md, AGENTS.md]`;
  `composition.agents_md_role` changed to `hoisted`. See SPEC-2026-05-24-INIT-ROUND2A §R2A-1.

- **(feat) Magical init UX — captured installer stdout + compressed banners (R2A-2).**
  New helper `run_installer_captured` in `lib.sh`: at default verbosity, each per-Eidolon
  `install.sh` runs with stdout+stderr captured to a tmpfile. On success the tmpfile is
  silently unlinked; on failure the last 20 lines are re-emitted to stderr prefixed
  `  [name] ` before `ui_failed_card`. Under `--verbose`, installer output passes through
  directly (legacy behaviour). Section banners `FETCH`, `INSTALL`, `LOCK`, `MIRROR`,
  `HOST-WIRE` are now suppressed at default tier (visible under `--verbose` only);
  `DETECT` and `PARTY ROSTER` remain as anchor banners at all tiers. Per-member progress
  lines `[N/M] name@ver — fetched` and `[N/M] name@ver — installing` are emitted before
  the ACQUIRED card. See SPEC-2026-05-24-INIT-ROUND2A §R2A-2.

- **(feat) `eidolons doctor` Check 11 — AGENTS.md drift detector (R2A-3).** Warns when
  `AGENTS.md` contains a substantive `<!-- eidolon:<name> start -->` block (without
  `-pointer` suffix) for any member in the lockfile — this indicates the compose pass
  has not yet run or the installer regressed. Also flags the stale
  `<!-- eidolon:eidolons-md-pointer -->` block from v1.5.0 that is no longer written
  by sync. Warn-only (exit code 0); remedy: `eidolons sync`. See SPEC-2026-05-24-INIT-ROUND2A §R2A-3.

### Removed

- **(breaking-internal) `apply_agents_md_pointer` retired.** The v1.5.0 helper that
  injected a supplementary `<!-- eidolon:eidolons-md-pointer -->` block into `AGENTS.md`
  is deleted. Under v1.6.0 each per-Eidolon block in `AGENTS.md` is hoisted by the
  symmetric compose pass and replaced with a per-member `<name>-pointer` block. Existing
  consumer projects with a leftover `eidolons-md-pointer` block are flagged by doctor
  Check 11; the block is never auto-removed.

## [1.5.0] - 2026-05-24

### Added

- **(feat) `EIDOLONS.md` as canonical content surface (Block 1).** `eidolons sync`
  now runs a composition pass that hoists per-Eidolon `<!-- eidolon:<name> start/end -->`
  blocks out of root `CLAUDE.md` into a new consumer-project-root `EIDOLONS.md`
  (the canonical composition surface). The source blocks in `CLAUDE.md` are replaced
  with thin `<!-- eidolon:<name>-pointer -->` blocks (distinct marker name, idempotency
  key). A short preamble is written to `EIDOLONS.md` on creation. `AGENTS.md` is
  intentionally excluded from the composition pass (Codex/opencode primary surface;
  EIIS v1.1 §4.1.0). New helper: `cli/src/lib_eidolons_md.sh` (`compose_eidolons_md`).
  See SPEC-2026-05-23-INIT-SANITY §B1.

- **(feat) Host-gated dispatch-pointer and cortex injection passes (Blocks 2+3).**
  `apply_dispatch_pointers` now accepts a `hosts_csv` argument and skips vendor files
  whose corresponding host is not in `hosts.wire`. Vendor→host mapping:
  `CLAUDE.md` → `claude-code`, `GEMINI.md` → `gemini`,
  `.github/copilot-instructions.md` → `copilot`. All dispatch-pointer bodies now
  redirect to `./EIDOLONS.md` instead of `./AGENTS.md`. The cortex injection loop in
  `sync.sh` similarly filters on `HOSTS_CSV`; `AGENTS.md` cortex injection is
  special-cased on `codex OR opencode` per EIIS v1.1 §4.1.0. `EIDOLONS_NO_GEMINI=1`
  is deprecated (v1.5.0: honor+warn; v1.6.0: remove — gemini is now host-gated).
  See SPEC-2026-05-23-INIT-SANITY §B2+B3.

- **(feat) `AGENTS.md` supplementary pointer + `eidolons doctor` Check 10 (Blocks 4+5).**
  `apply_agents_md_pointer` injects a `<!-- eidolon:eidolons-md-pointer -->` block into
  `AGENTS.md` after sync (only when `AGENTS.md` already exists; never creates it).
  New `doctor` Check 10 warns when `GEMINI.md` or `.github/copilot-instructions.md`
  exists but its corresponding host is not in `hosts.wire` (upgrade-from-v1.4.x
  leftover detection). Warn-only; no auto-delete.
  See SPEC-2026-05-23-INIT-SANITY §B4+B5.

- **(chore) `eidolons.lock` `composition:` block (Block 6).** `eidolons sync` now
  appends a top-level `composition:` block to `eidolons.lock` recording the
  composition target (`EIDOLONS.md`), hoist sources (`[CLAUDE.md]`), `AGENTS.md`
  role (`canonical-with-pointer`), and schema version (`1`). Additive; no lockfile
  schema version bump required. See SPEC-2026-05-23-INIT-SANITY §B6.

## [1.4.0] - 2026-05-23

### Added
- **(feat) FF-style level-up UX for `eidolons init` / `eidolons sync`.** Per-member output
  becomes an "ACQUIRED" character card (reuses `cli/src/ui/card.sh` primitives + sigils);
  six stage banners (DETECT, FETCH, INSTALL, MIRROR, LOCK, HOST-WIRE) group the formerly
  flat log noise; a final PARTY ROSTER card summarises the post-sync state from
  `eidolons.lock`. Failed installs emit a red `INSTALL FAILED` card and produce non-zero
  exit. New `--quiet`/`--verbose` flags + `EIDOLONS_QUIET`/`EIDOLONS_VERBOSE` env knobs
  on both `init` and `sync`. Idempotent reruns skip the ACQUIRED card (party roster still
  prints). Non-init commands (verify, doctor, upgrade, release, mcp) keep their legacy
  output — the verbosity tier defaults to `verbose` outside the init/sync paths.
  Plain-mode (`EIDOLONS_FANCY=0`) fallback preserved. See SPEC-2026-05-23-INIT-QOL §A2.
- **(feat) Dispatch-pointer marker block in vendor docs.** `eidolons sync` now
  upserts a `<!-- eidolon:dispatch-pointer start/end -->` block into
  `CLAUDE.md`, `GEMINI.md`, and `.github/copilot-instructions.md` regardless of
  the `hosts.shared_dispatch` setting. Each vendor file becomes a thin pointer
  to `./AGENTS.md` (the canonical source of truth) with vendor-specific
  phrasing — `## Eidolons` heading (polite to existing H1s) for Markdown
  vendors, plain prose for Copilot. The dispatch-pointer block coexists with
  the existing cortex block (different marker name, both idempotent). When a
  vendor file pre-exists with non-Eidolons content, one stderr `warn` line
  fires on first append; subsequent syncs rewrite in place silently. Opt-out
  via `EIDOLONS_NO_GEMINI=1` for projects that don't use Gemini. `eidolons
  remove <last>` cleans both the dispatch-pointer and cortex blocks across
  all four vendor surfaces. See SPEC-2026-05-23-INIT-QOL §A1.
- **(feat) `.gitignore` policy for `.eidolons/`.** `eidolons init` now upserts a
  marker-bounded block into the consumer project's `.gitignore` (under
  `# <!-- eidolon:gitignore start/end -->`) that ignores the bulky per-Eidolon
  artefacts under `.eidolons/<name>/` while allowlisting the nexus-owned
  `cortex/` and `harness/manifest.json`. A `full`-preset install previously
  committed ~24k LOC to VCS; the policy keeps only ~350 lines tracked. Recreatable
  content stays in `~/.eidolons/cache/` and is re-materialised by `eidolons sync`.
  Reuses the existing marker-block primitives — `upsert_marker_block` /
  `remove_marker_block` gained an optional 4th argument (`PREFIX`) so the same
  helper writes `# ` -prefixed marker lines into `.gitignore`. No-op when no
  `.git/` is present; one-time stderr migration hint when `.eidolons/` is already
  tracked (CLI never modifies the consumer's git index). `eidolons remove
  <last>` cleans the block. See SPEC-2026-05-23-INIT-QOL §I1.
- **(feat) Host-leakage prune for `.eidolons/<name>/`.** Several Eidolons today
  ignore the `--hosts` argument that `eidolons sync` forwards and write
  vendor-specific files (`hosts/cursor.md`, `hosts/copilot.md`,
  `.github/copilot-instructions.md`, `CLAUDE.md`, `AGENTS.md`) regardless of the
  user's host selection. The nexus now runs a defensive prune pass after each
  per-Eidolon installer completes, removing files for hosts that aren't in
  `hosts.wire`. Two paths: a cooperative **manifest-driven** pass that reads
  per-file `host` annotations from `install.manifest.json`, and a defensive
  **path-pattern** pass that targets a fixed table of well-known vendor files.
  AGENTS.md uses a multi-host rule (kept iff codex OR opencode is selected).
  New `--strict-hosts` / `--no-strict-hosts` flags on `eidolons init` and
  `eidolons sync`, persisted as `hosts.strict` in `eidolons.yaml`. When strict
  mode is on, the sync emits violations and exits non-zero if any vendor-pattern
  file is unannotated in `install.manifest.json` — pushes Eidolon authors toward
  the EIIS-soft-dep (FU-I2.1) for per-file `host` fields. Verbose
  (`EIDOLONS_VERBOSE=1`) prints one `info` line per pruned file. New module
  `cli/src/lib_host_prune.sh`. See SPEC-2026-05-23-INIT-QOL §I2.

### Fixed
- **(ci) `roster-health.yml` no longer fails on cross-repo `gh release download`.**
  The "Verify release integrity metadata" step used `gh release download
  --repo Rynaro/<EIDOLON>`, which the workflow's default `GITHUB_TOKEN`
  cannot satisfy (the token is scoped to the workflow's own repo). Result:
  every run that exercised an Eidolon with `provenance.github_attestation:
  true` returned `HTTP 401: Bad credentials`. The 2026-05-23 nightly cron
  on main was the first to surface it after a v1.1.3 publication; PRs
  inherited the same failure. Now uses `curl -fsSL` against the public
  release CDN URL, which needs no auth for public repos. The `gh
  attestation verify` call is kept (it validates against Sigstore's
  public transparency log and tolerates an unauthenticated token).

### Changed
- **(ci) `roster-health.yml` no longer triggers on `pull_request`.** Same-org
  PR branches push to this repo directly and already fire the `push`
  trigger with the canonical token. The `pull_request` trigger was firing
  a duplicate run on every PR with a restricted token, which both wasted
  CI minutes and surfaced `actions/checkout@v4` auth flakes (`fatal: could
  not read Username for 'https://github.com'`). Removing it eliminates
  the duplicate run and the flake surface. Re-add only if/when we accept
  fork contributions and re-architect the cross-repo verifier.

## [1.3.0] - 2026-05-20

### Added
- **`eidolons mcp` store (nexus v1.3.0).** Unified lifecycle manager for MCP
  servers. Introduces `eidolons mcp list|show|install|refresh|uninstall|upgrade|sync|health|run`.
  New closed catalogue at `roster/mcps.yaml` (atlas-aci + junction in v1.3).
  New sibling lockfile `eidolons.mcp.lock` (commit to VCS).
  Schemas at `schemas/mcp-catalogue.schema.json` and `schemas/mcp-lockfile.schema.json`.
  Driver protocol in `cli/src/lib_mcp.sh`; sub-dispatchers in `cli/src/mcp*.sh`.
  `eidolons doctor` MCP section rewritten to iterate `eidolons.mcp.lock`.
  `eidolons sync` surfaces MCP lockfile presence (warn-only; never installs per NG3).
  CI: `roster-health.yml` gains `parse-mcp-catalogue` and `mcp-catalogue-digest-reachable` jobs.

### Changed
- **`eidolons mcp atlas-aci` deprecated (removal: v3.0.0).** The verb still
  works but emits one `DEPRECATED:` line on stderr. Use `eidolons mcp install
  atlas-aci` instead. Suppress with `EIDOLONS_SUPPRESS_DEPRECATED=1`.
- **`eidolons harness <sub>` deprecated (removal: v3.0.0).** All harness
  subcommands delegate to the new `mcp_*.sh` drivers and emit a `DEPRECATED:`
  line. Use `eidolons mcp install|health|run|uninstall junction` instead.
- `cli/src/doctor.sh`: "MCP servers" section (Check 7) rewritten — iterates
  `eidolons.mcp.lock` and calls per-MCP health drivers. Legacy hard-coded
  atlas-aci probe removed and replaced by the generic driver call. New
  "MCP catalogue drift" section (Check 8) surfaces MCPs behind `pins.stable`.

### Notes
- **Junction test-suite perf landed 2026-05-20** at `Rynaro/Junction`
  (PR [#27](https://github.com/Rynaro/Junction/pull/27), commit `690bdd3`,
  unreleased on `main`). Battle-test follow-up that cuts the harness-developer
  feedback loop: `make check` cold ~16 s → ~14 s, warm ~5.3 s → **1.3 s**;
  `make lint-examples` 5-6 s → ~1 s; full `-race` stress
  (`-count=20 -parallel=8`) clean with no flakes. Changes: `t.Parallel()` on
  ~80 isolated tests + table subtests; channel-barrier replacing
  `time.Sleep` in `fanout_test.go`; dropped redundant `go vet` (golangci-lint
  already enables `govet`); consolidated `make lint-examples` from six
  `docker compose run` calls to one; CI gained
  `docker/build-push-action@v6` GitHub-Actions layer cache
  (`scope=dev`/`scope=release`) plus `actions/cache` for
  `.gocache`/`.gomodcache`. **Two latent production data races also fixed**
  by the parallelism work — `internal/plan/plan.go::getPlanSchema()` and
  `internal/envelope/validate.go::getSchema()` had unprotected lazy-init of
  compiled JSON schemas (now `sync.Once`-guarded); the MCP sampling path
  runs concurrent verifies and would have hit these eventually. No nexus
  code change is required; the next Junction release ships the fixes and
  the speedup automatically via the dynamic latest-release probe in
  `cli/src/harness.sh`.
- **Junction v0.2.0 released 2026-05-19** at `Rynaro/Junction` (tag `v0.2.0` at
  commit `c6537ca`,
  [release page](https://github.com/Rynaro/Junction/releases/tag/v0.2.0); four
  static binaries + SHA256SUMS + SLSA L3 provenance). Closes all three findings
  from the 2026-05-19 ECL MCP battle test (nexus thread
  `46aa005a-7b5a-4f93-8dd7-ebeb8450d555`): G1 `harness.run` now ingests
  `plan.json` (in-process `plan.Parse` + `dispatch.ChainExecutor`,
  `thread_id`/`trace_root` from the live plan struct, not stdout); G2 wires
  `ReasoningStep` so `junction mcp serve` drives the container two-phase loop
  via MCP `sampling/createMessage` — new `internal/reasoning/` package with
  `mcp-sampling`/`canned`/`shellout`/`noop` providers selected by
  `JUNCTION_REASONING_PROVIDER`; G3 honours `edge_origin: implicit` (terminal
  hand-offs like `idg → human` no longer require a roster contract). No
  nexus code change is required — `cli/src/harness.sh` already probes the
  GitHub latest-release; running `eidolons harness install` picks up v0.2.0
  automatically. To pin: `JUNCTION_VERSION=0.2.0 eidolons harness install`.

## [1.2.0] - 2026-05-15

### Added
- **F7: `eidolons harness install/up/verify/uninstall` subcommand family.** New
  nexus CLI surface for installing, starting, verifying, and removing the
  Junction harness binary. Resolves Friction-1/-2 from the Junction v0.1.0
  README walk where `eidolons harness install 0.1.0` previously surfaced
  `Unknown command: harness`. The harness binary itself ships from
  `Rynaro/Junction` releases and is cached at
  `~/.eidolons/cache/junction@<version>/junction`. Env vars: `JUNCTION_VERSION`,
  `JUNCTION_REF`, `JUNCTION_ALLOW_ROOT`. Marker section
  `<!-- eidolons:harness start/end -->` written to host environment files via
  `eidolons sync`.
- **F10-S2/S3: `bin/ecl-io-shim` + reusable image-publish job.** New bash shim
  that adapts Eidolon `commands/<verb>.sh` output to ECL v1.0 envelope shape
  (writes `envelope_version: "1.0"` and `payload.sha256`). The shim is
  baked into every Eidolon container image via the new
  `.github/workflows/eidolon-release-template.yml` `docker-image` job, which
  builds and pushes `ghcr.io/rynaro/<eidolon>:<version>` images alongside
  every `Release <Eidolon>` workflow run. Closes Junction round-6 gate G-S16.
- **ECL v1.0.0 integration.** Teach the nexus that the Eidolons Communication
  Layer exists. Adds `comm.envelope_version` (optional) to every roster entry
  and the lock schema so consumers can declare which ECL envelope version each
  Eidolon emits. `eidolons sync` now emits a `warn` when an installed Eidolon
  ships an `ECL_VERSION` file that disagrees with the roster's declared
  `comm.envelope_version`; absent `ECL_VERSION` is silent. Resolves the
  `[DISPUTED]` VIGIL lateral edges in `methodology/cortex/handoff-graph.md`.
  Adds a one-line pointer in `methodology/composition.md` directing readers
  to `Rynaro/eidolons-ecl/contracts/`. No breaking changes; idempotency of
  `eidolons sync` preserved.
- **`composition-drift` CI gate.** New GitHub Actions job pinned to
  `eidolons-ecl@v1.2.0` that fails CI if `methodology/composition.md`'s
  hand-off table drifts from the canonical YAML contracts upstream.
  Catches stale documentation before it ships to consumers.
- vigil v1.1.3 published in the roster with release integrity metadata.
- forge v1.3.3 published in the roster with release integrity metadata.
- idg v1.2.3 published in the roster with release integrity metadata.
- apivr v3.1.3 published in the roster with release integrity metadata.
- spectra v4.3.3 published in the roster with release integrity metadata.
- atlas v1.5.3 published in the roster with release integrity metadata.
- vigil v1.1.2 published in the roster with release integrity metadata.
- forge v1.3.2 published in the roster with release integrity metadata.
- idg v1.2.2 published in the roster with release integrity metadata.
- apivr v3.1.2 published in the roster with release integrity metadata.
- spectra v4.3.2 published in the roster with release integrity metadata.
- atlas v1.5.2 published in the roster with release integrity metadata.
- forge v1.3.1 published in the roster with release integrity metadata.
- idg v1.2.1 published in the roster with release integrity metadata.
- vigil v1.1.1 published in the roster with release integrity metadata.
- apivr v3.1.1 published in the roster with release integrity metadata.
- spectra v4.3.1 published in the roster with release integrity metadata.
- atlas v1.5.1 published in the roster with release integrity metadata.
- forge v1.3.0 published in the roster with release integrity metadata.
- idg v1.2.0 published in the roster with release integrity metadata.
- vigil v1.1.0 published in the roster with release integrity metadata.
- spectra v4.3.0 published in the roster with release integrity metadata.
- apivr v3.1.0 published in the roster with release integrity metadata.
- atlas v1.5.0 published in the roster with release integrity metadata.
- **ECL v1.0.0 integration.** Teach the nexus that the Eidolons Communication Layer exists.
  Adds `comm.envelope_version` (optional) to every roster entry and the lock schema so
  consumers can declare which ECL envelope version each Eidolon emits. `eidolons sync`
  now emits a `warn` when an installed Eidolon ships an `ECL_VERSION` file that disagrees
  with the roster's declared `comm.envelope_version`; absent `ECL_VERSION` is silent
  (live Eidolons may not yet ship the file). Resolves the `[DISPUTED]` VIGIL lateral
  edges in `methodology/cortex/handoff-graph.md` — those edges are roster-declared via
  `vigil.handoffs.lateral` and were never missing. Adds a one-line pointer in
  `methodology/composition.md` directing readers to the canonical machine-readable
  contracts at `Rynaro/eidolons-ecl/contracts/`. No breaking changes; all existing tests
  continue to pass; `eidolons sync` idempotency is preserved.

## [1.1.3] - 2026-05-06

### Added
- atlas v1.4.2 published in the roster with release integrity metadata.
  Ships the dual-layer `HOME=/tmp` fix for tree-sitter `$HOME`-relative
  EACCES on container hosts where the consumer overrides `-u` to match
  host file ownership (atlas-aci-home-env-fix-2026-05-06). Layer 1
  (atlas-aci v0.2.3 image) sets `ENV HOME=/tmp` in the production
  Dockerfile; Layer 2 (atlas v1.4.2) emits `-e HOME=/tmp` in every
  `docker run` argument array (`run_index_container`,
  `container_json_fragment`, `_copilot_command_array`, and
  `_codex_canonical_body_container`) as belt-and-braces against older
  pinned image digests. Without this roster bump, `eidolons upgrade
  --all` cannot see atlas v1.4.2 because the roster is pinned to the
  nexus tag.

## [1.1.2] - 2026-05-06

### Added
- **`eidolons doctor` — atlas-aci `.mcp.json` UID/GID + bind probes.** Two
  new defense-in-depth checks inside the existing atlas-aci health
  section. Probe A compares the `-u <uid>:<gid>` pin in
  `mcpServers["atlas-aci"].args` against the current user (err on
  mismatch, warn when no pin is present). Probe B verifies every
  `-v <host>:<container>` bind path exists and is readable (err
  otherwise). Catches the configuration drift that produces the same
  failure mode as a fresh-install bug after rsyncing a project to a
  different machine. Read-only; fail-soft on missing/malformed
  `.mcp.json`. Spec id `atlas-aci-container-uid-perm-fix-2026-05-05` (T3).
- atlas v1.4.1 published in the roster with release integrity metadata.
  Ships the SELinux `:Z` mount-relabel + silent-success guard for
  Fedora-class Docker hosts (atlas-aci-container-uid-perm-fix-2026-05-05
  T1/T2). Without this roster bump, `eidolons upgrade --all` cannot see
  atlas v1.4.1 because the roster is pinned to the nexus tag.

## [1.1.1] - 2026-05-05

### Fixed
- `.gitignore` now tracks the three install sidecar filenames
  (`.install_date`, `.install_ref`, `.install_commit`) that
  `cli/install.sh` and `cli/src/upgrade_self.sh` append to
  `$NEXUS_DIR/.gitignore` at install time. Without this, every fresh
  nexus install left the working tree dirty against upstream and tripped
  `eidolons upgrade self`'s clean-tree precondition, forcing users into
  `--force` (which also bypasses the integrity verification chain).
  Existing dirty installs heal automatically on the next `upgrade self`.

## [1.1.0] - 2026-05-05

### Added
- **`eidolons release <eidolon> <version>` — one-touch maintainer command.**
  Collapses the `Release <EIDOLON>` + `Roster Intake` workflow_dispatch
  chain into a single command. Validates SemVer, gh auth scope per repo,
  workflow file existence, and version precedence (rejects equals/downgrade
  without `--force`). Polls upstream for the tag, dispatches Roster Intake,
  polls for the resulting PR, prints final URLs. Flags: `--check` (dry-run,
  no dispatch), `--resume` (skip Release dispatch when tag exists),
  `--force`, `--auto-merge`, `--yes`, `--non-interactive`,
  `--release-timeout=N` (default 600s), `--intake-timeout=N` (default 300s).
  Exit codes: 0 success, 1 generic, 2 usage/validation, 4 network/timeout,
  5 dispatch failure. Bash 3.2 safe.
- **`eidolons doctor` — Pending Upgrades section.** New information-only
  section between the registry-reachability probe and the summary. Lists
  members where the roster's `versions.pins.stable` is ahead of the
  installed lock entry (within constraint), and flags pinned-out members
  separately. Does not increment `ERRORS`. Offline-degrades silently.
- **Roster Intake auto-merge.** Routine version bumps now open as
  ready-for-review and engage `gh pr merge --auto --squash`; GitHub holds
  the merge until required status checks pass on `main`. First-shipped
  transitions (`status == in_construction`) and bumps against an empty
  `versions.releases` stay DRAFT for explicit human review. The
  release-integrity contract is preserved — auto-merge only auto-clicks
  the merge button after attestation verification has already succeeded.
  See `docs/release-integrity.md` § "Auto-merge of routine roster bumps".

### Changed
- `cli/src/lib.sh` exposes `collect_member_upgrade_rows` and
  `nexus_status_label` as public helpers. `cli/src/upgrade.sh` delegates
  to the lib helpers (no behaviour change). Enables `cli/src/doctor.sh`
  to render the new Pending Upgrades section without duplicating logic.

### Fixed
- `with_timeout` in `cli/src/lib.sh` no longer holds an inherited
  command-substitution pipe open after the polled function returns early
  — the timer subshell now redirects stdout/stderr to `/dev/null`.
  Without this, `$(with_timeout N _poll)` blocked until the timer fired
  regardless of the polled function returning early.
- fix(mcp): doctor probes .atlas/memex/ writability; lib_mcp_atlas_aci.sh exposes pinned-ref accessor; reuse-already-loaded image is now an ATLAS-side contract (PR #2 in Rynaro/ATLAS).

### Added (atlas roster)
- atlas v1.4.0 published in the roster with release integrity metadata.
- **Nexus CLI self-versioning + `eidolons upgrade self`.**
  - `VERSION` file at the nexus root (initial content `1.0.0`) is now the single
    source of truth for the nexus version. `cli/eidolons` reads it via an inline
    `_read_nexus_version()` helper (fallback: `git describe --tags --abbrev=0`, then
    `0.0.0-dev`). The hardcoded `EIDOLONS_VERSION="1.0.0"` constant is replaced.
  - `eidolons --version` (and `eidolons version`, `-v`, `--version`) now prints a
    multi-line enriched block: version, commit SHA, install ref, install date, nexus
    path. `--quiet` / `-q` flag restores the single-line grep-compat form.
  - `eidolons upgrade self` — atomic, integrity-verified, rollback-safe nexus
    self-upgrade. Clones the target ref into `~/.eidolons/nexus.new/`, verifies commit
    + tree + archive SHA-256 against `nexus.versions.releases.<v>` in
    `roster/index.yaml`, runs a smoke test, then renames atomically
    (`nexus → nexus.prev`, `nexus.new → nexus`). Exit codes: 0 ok/no-op, 4 network
    error, 5 integrity mismatch, 6 smoke test failed, 7 no `nexus.prev` for rollback.
    Flags: `--ref`, `--check`, `--rollback`, `--force`, `--non-interactive`.
  - `nexus:` block added to `roster/index.yaml` with `versions.releases.1.0.0`
    integrity metadata (placeholders filled by the release workflow).
  - `.github/workflows/release-nexus.yml` — release workflow that tags, builds the
    archive, computes SHA-256, updates the `nexus.versions.releases.<v>` block in
    `roster/index.yaml`, commits the updated roster, and creates a GitHub Release.
  - `roster-health.yml` gains a `nexus-integrity` job that validates the latest nexus
    release block and skips gracefully when placeholders are still present (bootstrap
    window).
  - `cli/install.sh` writes `VERSION` (from `git describe` when absent) and sidecars
    `.install_date`, `.install_ref`, `.install_commit` into the cloned nexus after
    every fresh install. The sidecars are gitignored.
  - 15 new bats tests in `cli/tests/upgrade_self.bats` covering no-op, upgrade,
    rollback, dirty-tree guard, downgrade warning, integrity failure, smoke-test
    failure, `--check`, and first-install sidecar presence.
  - Versioning bump rules documented in `docs/architecture.md` §"Nexus CLI bump rules"
    and reproduced in `CHANGELOG.md` §"Versioning notes".
  - `docs/cli-reference.md` gains a dedicated `## eidolons upgrade self` section with
    flags, safety properties, and exit codes.
  - README gains a `### Updating` subsection and updated `## Recently shipped` entry.

### Fixed
- `eidolons init` / `eidolons sync` now auto-recover from stale or corrupt
  `~/.eidolons/cache/` entries by re-cloning once before failing. The
  strict integrity contract is preserved: a re-clone that still mismatches
  the roster is fatal with an explicit "upstream-truth mismatch" message.
  Affects all six shipped Eidolons (atlas, spectra, apivr, idg, forge, vigil).
  Root cause was `fetch_eidolon` reusing a cached clone without re-verification
  or recovery, causing fatal `commit mismatch` errors when a force-moved
  upstream tag had updated the roster commit after the initial cache was
  populated. Also handles interrupted clones and corrupt `.git` directories.
  Cache mismatch recovery is bounded to one retry.
- `eidolons doctor` now includes a `Cache hygiene` section (read-only) that
  walks `eidolons.lock` members and compares each `~/.eidolons/cache/` entry
  against the roster's recorded commit, reporting stale or corrupt entries
  with an actionable next-step.

### Added
- spectra v4.2.11 published in the roster with release integrity metadata.
- **`EIDOLONS.md` routing cortex at the repo root** (`.spectra/plans/eidolons-cortex-spec.md` §11.1). Always-loaded ≤900-token descriptor table + 5-step dispatch protocol + 8 chain templates + 6 TRANCE activation gates + 10 cortex invariants, marker-bounded `<!-- eidolon:cortex start --> … <!-- eidolon:cortex end -->`. Closes the routing gap from `.spectra/research/eidolons-cortex-foundation.md` §5: free-form natural-language prompts arriving through Claude Code / Cursor / OpenCode / Codex now have a semantic dispatch path; `cli/eidolons` deterministic string-match (`cli/src/dispatch_eidolon.sh`) is unchanged. Architecture is hierarchical-supervisor with two-stage hybrid dispatch (descriptor soft-match → confidence gate + TRANCE escalation) per spec §4.4 — single-router, cascade-by-strength, and MoA-as-default were rejected with cited reasons.
- **Deep cortex tables under `methodology/cortex/`** (spec §4 progressive disclosure, P3). Loaded on demand by a host that needs them: `handoff-graph.md` (canonical hand-off graph as the union of `roster/index.yaml` and `methodology/composition.md` edges with `edge_origin` labels per spec §7.1, resolving the foundation §4 dispute), `trance-matrix.md` (per-Eidolon TRANCE form, granted capabilities, refusal gates R1–R5, cost ceilings C1–C6), `validation-gates.md` (all 14 GIVEN/WHEN/THEN gates V1–V14 the cortex must satisfy). The README in that directory documents the load-order contract.
- **`eidolons sync` mirrors the cortex into the consumer project at `./.eidolons/cortex/EIDOLONS.md`** plus the deep tables (`trance-matrix.md`, `handoff-graph.md`, `validation-gates.md`, `README.md`) so the on-consumer progressive-disclosure pattern resolves correctly (`cli/src/sync.sh`; spec §11.1). Idempotent, dry-run-aware, bash 3.2 safe. Per-Eidolon installers continue to write only to cwd; the cortex is a nexus-level concern (`docs/architecture.md` Security model row "Nexus CLI").
- **Marker-bounded cortex pointer block injected into root `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md`** when `--shared-dispatch` is on (spec §11.1 inclusion requirement, I-C1). Pointer-only — keeps `EIDOLONS.md` the single source of truth, respects the ≤900-token I-C4 budget at the consumer surface, honours progressive disclosure (P3). Two new helpers in `cli/src/lib.sh` — `upsert_marker_block` and `remove_marker_block` — share the per-Eidolon installer's marker pattern and are reused for cortex teardown.
- **`eidolons remove` cortex cleanup** (`cli/src/remove.sh`): removes the cortex marker block from host docs and deletes `.eidolons/cortex/` on last-Eidolon removal; preserves the cortex when other Eidolons remain installed.
- **27 new bats tests in `cli/tests/cortex.bats`** covering mirror creation (file + deep tables), marker presence, idempotency on repeat sync, host-doc injection under shared-dispatch, no-injection under `--no-shared-dispatch`, capability-class language only (no vendor model names per `methodology/prime-directives.md:152-162`), presence of all V1–V14 gates in the deep table, and the removal-cleanup paths (last-Eidolon and others-remain). Suite stands at 225/225 pass.
- **Three-line "Cortex" section in `CLAUDE.md`** so codebase contributors find the artifact and the `eidolons sync` mirroring contract from the standard onboarding file.

### Changed
- **`cli/src/sync.sh`** gains a cortex-mirror step (idempotent; runs only when `EIDOLONS.md` exists at the nexus root). Behavior on consumer projects without `eidolons.yaml` is unchanged. The four design principles cited as load-bearing in the spec: routing-as-calibrated-classifier (RouteLLM ICLR 2025, dossier §2 #1), progressive disclosure of descriptors (Anthropic Skills, dossier §3.1), TRANCE = parallel fan-out + isolation + verifier wrapping rather than longer thinking (Anthropic multi-agent research-system + ACL 2025 "Revisiting o1", dossier §3.4 / §2 #18), and capability-class language only — never vendor model names — per D9.

### Fixed
- **GHCR-default pull + `--build-locally` escape hatch for `eidolons mcp atlas-aci pull`** (`.spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md` T6–T8). `DEFAULT_IMAGE_DIGEST` is now the registry-prefixed form `ghcr.io/rynaro/atlas-aci@sha256:<digest>`; the happy path runs `docker pull` against ghcr.io; the three-alternatives fallback block is demoted to the GHCR-failure path and lists `--build-locally` as alternative #1. The `--build-locally` flag (with optional `--git-ref REF`) builds the image from the upstream git source and is a **non-removable escape hatch** for air-gap and network-restricted environments.
- **Container-runtime security hardening** (`--cap-drop=ALL`, `--security-opt=no-new-privileges`) on the atlas-aci canonical body generated by `eidolons mcp atlas-aci`. Trivy-scan-gated (HIGH/CRITICAL) at publish time; read-only repo mount and dedicated UID 10001 are set in the upstream Dockerfile.
- **ghcr.io registry reachability probe in `eidolons doctor`** (T10). A non-fatal Check 7 performs an anonymous-token HEAD against the ghcr.io v2 manifests endpoint for the pinned digest. On success: `pass: atlas-aci image reachable on ghcr.io`. On 404/network error: `warn: atlas-aci image not reachable (offline? or pinned digest yanked? — try 'eidolons mcp atlas-aci pull --build-locally')`. The probe is skipped silently when `.mcp.json` is absent or has no atlas-aci entry; `curl` absence degrades gracefully.
- **Bootstrap pre-flight refusal** (T-H2): `eidolons mcp atlas-aci` (scaffold) and `eidolons mcp atlas-aci pull` both abort with an actionable error message if `DEFAULT_IMAGE_DIGEST` is still the all-zeros placeholder, preventing misconfigured `.mcp.json` from reaching users before the first real ghcr.io release.
- **P0 invariant test** asserting `--build-locally` cannot be silently removed (`cli/tests/mcp_atlas_aci_pull.bats` — test name includes the literal string `P0 invariant` to surface any removal PR in diffs; `INVARIANT (P0)` comment in `cli/src/mcp_atlas_aci_pull.sh`).
- feat(mcp): pre-flight image check + 'eidolons mcp atlas-aci pull' subcommand; doctor surfaces MCP image health.
- **fix(roster): publish ATLAS v1.3.0 (1.2.2 → 1.3.0).** Bumps ATLAS roster pin to v1.3.0 — the registry-prefixed canonical body for `eidolons atlas aci --container` (replaces the broken bare `atlas-aci@sha256:...` form which Docker resolved to docker.io/library/atlas-aci → 404), plus container-runtime security hardening (`--cap-drop=ALL`, `--security-opt=no-new-privileges`) on all four MCP emit paths (`.mcp.json`, `.cursor/mcp.json`, `.codex/config.toml`, `.github/agents/*.agent.md` Copilot bodies, and the one-time `run_index_container` invocation). Implements §T11 of `.spectra/plans/atlas-aci-ghcr-distribution-2026-05-01/spec.md`. Companion changes already on main: PR #55 (nexus GHCR-default + `--build-locally` escape hatch + doctor probe) and `ATLAS#20` (canonical body). Release-integrity metadata captured from `gh release view v1.3.0 -R Rynaro/ATLAS` (commit `7d9f3acf`, tree `9c377eac`, archive sha256 `7e015397…`); attestation produced by the canonical `eidolon-release-template.yml`.
- **ATLAS subagent silently bypassed the atlas-aci MCP server and used native Read/Grep instead (ATLAS roster pin 1.2.1 → 1.2.2).** After the [1.2.1 fix](https://github.com/Rynaro/ATLAS/pull/15), Claude Code connected to the atlas-aci MCP server cleanly and the seven indexed-graph tools (`view_file`, `list_dir`, `search_text`, `search_symbol`, `graph_query`, `test_dry_run`, `memex_read`) became visible at the project level — but the ATLAS subagent's `tools:` allowlist on line 5 of `.claude/agents/atlas.md` only permitted `Read, Grep, Glob, Bash(rg:*), Bash(git log:*), Bash(git show:*)`. Claude Code refused to expose any `mcp__atlas-aci__*` tool to the subagent, and the agent silently fell back to native Read+Grep. The expensive index sat idle. Fixed in [ATLAS#16](https://github.com/Rynaro/ATLAS/pull/16) — `eidolons atlas aci install` now also rewrites the `tools:` line to add all seven `mcp__atlas-aci__*` entries; `eidolons atlas aci remove` restores the BASE list. Six new bats tests (SUB-1..SUB-6) pin the install→remove cycle. The body of the subagent file and the rest of the frontmatter are untouched, so any user-customised description / handoff settings are preserved. Cursor and Codex don't gate MCP tools per-subagent the same way Claude Code does, so this only touches the Claude Code surface.

### Fixed
- **Claude Code emitted `Missing environment variables: workspaceFolder` on every project load (ATLAS roster pin 1.2.0 → 1.2.1).** The atlas-aci entry written into `.mcp.json` (and the cursor / codex / copilot equivalents) embedded the literal `${workspaceFolder}` placeholder for `--repo`, `--memex-root`, and the docker `-v` bind mount paths. Cursor / VSCode expand the placeholder natively, but Claude Code parses `${VAR}` as an env-var reference and so warned on every project load; the docker mount then dereferenced the literal string and the MCP server failed to attach. Fixed in [ATLAS#15](https://github.com/Rynaro/ATLAS/pull/15) — all four host body generators (`container_json_fragment`, `json_server_fragment`, `_copilot_command_array`, `_codex_canonical_body_container`) now bake the absolute project path (`$PWD` at install time) directly. Three new regression tests (ABS-1/ABS-2/ABS-3) pin the post-install body shape so the placeholder cannot silently come back. Trade-off: `.mcp.json` bodies are now machine-specific — re-run `eidolons atlas aci install` after relocating; gitignore in team workflows where each developer's path differs.

### Added
- **Ecosystem-normalized milestone.** All six shipped Eidolons (ATLAS, SPECTRA, APIVR-Δ, IDG, FORGE, VIGIL) now publish attestation-backed releases via the canonical `eidolon-release-template.yml`, with `versions.releases.<v>` populated in `roster/index.yaml` and verified end-to-end by `eidolons verify`. `integrity.enforcement` flipped from `warn` to `strict` — any consumer install with a commit/tree/archive checksum mismatch now aborts with exit 1 instead of warning.
- vigil v1.0.3 published in the roster with release integrity metadata.
- spectra v4.2.10 published in the roster with release integrity metadata.
- idg v1.1.5 published in the roster with release integrity metadata.
- forge v1.2.1 published in the roster with release integrity metadata.
- apivr v3.0.5 published in the roster with release integrity metadata.
- atlas v1.2.2 published in the roster with release integrity metadata.
- **Release integrity and automation.** Adds roster release metadata schema (`versions.releases`), install-time commit/tree/checksum verification, `eidolons verify`, lockfile integrity fields, release/roster-intake GitHub Actions, and docs for the warn-now/strict-later supply-chain model.
- **`eidolons atlas aci index` first-class re-index subcommand (ATLAS roster pin 1.1.1 → 1.2.0).** Refreshing the atlas-aci code graph previously required either re-running `--install` (which short-circuits on `.atlas/manifest.yaml` and effectively no-ops) or invoking `docker run --rm -v "$PWD":/repo atlas-aci:<ver> index --repo /repo --langs ...` by hand. The latter was a discoverability cliff for both humans and LLMs interacting with the nexus — nothing in `eidolons atlas aci --help` surfaced it. ATLAS [v1.2.0](https://github.com/Rynaro/ATLAS/pull/14) adds a positional `index` action (and `--index` flag form) that auto-detects host vs container mode (preferring host when `atlas-aci` is on PATH; falling back to `docker images :atlas-aci:<ATLAS_VERSION>` then podman; exit 5 with an actionable hint when neither is available). The action bypasses the install-side `.atlas/manifest.yaml` gate (T24) via a new `force` parameter on `run_index`, does NOT rebuild the image, does NOT touch MCP configs or `.gitignore`, and exposes nine new bats cases (IDX-1..IDX-9) covering positional/flag forms, mode auto-detect, prereq-missing exit, gate bypass, dry-run, override semantics, and action conflict.

### Fixed
- **`eidolons atlas aci --container` produced a broken image (ATLAS roster pin 1.1.0 → 1.1.1).** The image built fine but `atlas-aci index` failed at runtime with `ModuleNotFoundError: No module named 'tree_sitter_language_pack'`. Root cause was upstream of ATLAS: the `Rynaro/atlas-aci` production Dockerfile re-resolved transitive deps from PyPI via bare `pip install /tmp/*.whl` and ignored `mcp-server/uv.lock`. When `tree-sitter-language-pack 1.6.3` shipped a restructured wheel (only a `_native/` subpackage; no top-level `tree_sitter_language_pack` module), every fresh `--container` build silently produced an image that crashed on first index. Fixed in [atlas-aci#1](https://github.com/Rynaro/atlas-aci/pull/1) — pyproject constraint `<1.6.3` plus a lock-respecting Dockerfile (`uv export --frozen --no-dev` → `requirements.txt`, then wheel install with `--no-deps`). [ATLAS#12](https://github.com/Rynaro/ATLAS/pull/12) bumped `ATLAS_ACI_PIN`/`ATLAS_ACI_REF` to the merge SHA and tagged `v1.1.1`. This roster bump pulls that release in for everyone running `eidolons upgrade`.

### Added
- **`eidolons atlas aci --container` (container-runtime mode).** ATLAS v1.1.0 adds a second install path for the atlas-aci MCP server: `--container` builds the image locally via Docker or Podman (no GHCR pull; deferred to F1). Runtime selection follows D1 (always-prompt): interactively prompts docker/podman unless `--runtime <docker|podman>` is supplied explicitly; `--non-interactive` without `--runtime` exits non-zero (exit 9). Image is pinned by local sha256 digest captured after build (D3), so re-running against an unchanged image is a no-op. New flags: `--container` (switch), `--runtime <docker|podman>` (enum). New exit codes: 7 (runtime not on PATH), 8 (image build failed), 9 (non-interactive without --runtime). Bumps ATLAS roster pin to 1.1.0 (superseded by 1.1.1 above).
- **`eidolons upgrade` (full implementation, replaces v1.0 stub).** Two surfaces on a single command: `eidolons upgrade --check` is a read-only diff (nexus head vs latest tag on `Rynaro/eidolons`; per-member `eidolons.lock` versions vs `roster/index.yaml` `versions.latest`); `eidolons upgrade` applies member upgrades within `eidolons.yaml` constraints. Bare invocation is project-scoped (members in cwd); `--system` upgrades the nexus only; `--project` is the explicit form of the default and pairs with `--check` to narrow the report; `--all` runs both phases (equivalent to `--system --project`). Also adds `--json`, `--yes`, `--non-interactive`, `--dry-run`, plus positional member arg / comma-separated list. Respects `^/~/=` SemVer constraints (pure-bash `semver_satisfies` helper, no external deps); a latest exceeding the constraint surfaces as `pinned-out` rather than auto-editing the manifest. Network failures during the nexus probe degrade gracefully (10-second timeout via new `with_timeout` helper). Idempotent on repeat runs: lockfile mtime is preserved when no resolved version changed. Spec: `docs/specs/eidolons-upgrade/`.
- **OpenAI Codex** as a first-class supported host (PR #21). `detect_hosts` recognises `.codex/` (precedence) and `AGENTS.md` co-ownership; `eidolons sync` wires both root `AGENTS.md` and per-Eidolon `.codex/agents/<name>.md` subagent files; `--no-shared-dispatch` is overridden-with-warn when `codex` is in the host list.
- **`eidolons atlas aci` Codex MCP wiring.** ATLAS v1.0.6's `commands/aci.sh` registers the atlas-aci stdio MCP server in `./.codex/config.toml` under `[mcp_servers.atlas-aci]` via POSIX `awk` line-bounded TOML rewrite. Idempotent (install→install byte-identical; install→remove→install closure). `docs/atlas-aci.md` updated with the Codex bullet in the host list, the TOML row in the idempotency contract, and the user-level `~/.codex/config.toml` scope-boundary note.

### Changed
- **`eiis_required` bumped from `1.0` to `1.1`** — the roster now requires EIIS v1.1 (Codex addendum). All six shipped Eidolons publish EIIS-1.1-conformant releases.
- **`cli/src/lib.sh` `eiis_check`** delegates to the external checker at [`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis) when reachable; falls back to the inline file-existence check when offline. The standalone checker (cached at `~/.eidolons/cache/eiis@<version>/`) provides the full §1–§4 contract enforcement; the inline path remains for air-gapped installs.
- **`.github/workflows/roster-health.yml`** clones `Rynaro/eidolons-eiis` and runs the external `conformance/check.sh` against each shipped Eidolon, replacing the previous five-file existence smoke.
- **Roster pin bumps** (all six shipped Eidolons publish EIIS-1.1 + Codex support):
  - ATLAS: `1.0.3` → `1.0.6` (latest bump adds Codex MCP host wiring in `commands/aci.sh`)
  - SPECTRA: `4.2.8` → `4.2.9`
  - APIVR-Δ: `3.0.3` → `3.0.4`
  - IDG: `1.1.3` → `1.1.4`
  - VIGIL: `1.0.1` → `1.0.2`
  - FORGE: `1.1.1` → `1.2.0` (also closes drift items D-1, D-3, D-4 from the EIIS bootstrap audit)

### Added (initial nexus, retained)
- Initial nexus scaffold: roster registry, CLI, methodology aggregation, research library, examples.
- `eidolons` CLI with `init`, `add`, `sync`, `list`, `doctor`, `roster` commands.
- Stubs for `remove`, `upgrade` (full implementation in v1.1).
- JSON Schemas for `eidolons.yaml`, `eidolons.lock`, roster entries.
- Prime directives aggregated from project working notes.
- Composition doc with canonical pipeline and handoff contracts.
- Research library with starter BibTeX + production-patterns doc.
- Examples: greenfield, brownfield-rails, solo-atlas.
- GitHub Actions nightly roster health check.
- FORGE promoted to `shipped` in the roster (v1.1.1). Adds the lateral Reasoner to the `full` preset; first stable release with EIIS-1.0 conformant `install.sh`.
- VIGIL added to the roster as shipped (v1.0.1) — forensic debugger for code failures resistant to normal repair. Introduces a new `debugger` capability class in the roster schema. Added to the `full` preset and to every other Eidolon's lateral handoffs. New `diagnostics` preset (apivr + vigil + forge) for debug-focused work.
- `.claude/skills/add-eidolon/SKILL.md` — codifies the pattern for promoting a new Eidolon to the roster or bumping a version. Captures exploration checklist, roster entry template, CI matrix + documentation touchpoints, and verification steps.

### Depends on
- `Rynaro/eidolons-eiis` (separate repo, EIIS v1.1 standard — bumped from v1.0 in this release).
- Individual Eidolon repos: atlas, spectra, apivr, idg, forge, vigil.

---

## [1.0.0] — TBD

Initial release target. Release criteria:

- All five Eidolon repos EIIS-1.0 conformant and reachable.
- Nightly `roster-health` workflow green for 7 consecutive days.
- `eidolons init` and `sync` exercised end-to-end in at least one greenfield and one brownfield project.
- `remove` and `upgrade` commands fully implemented.
- Research library populated with ≥10 paper summaries under `research/papers/`.

---

## Versioning notes

- **Nexus version** bumps when the CLI, roster schema, or composition contracts change.
- **Individual Eidolon versions** are independent — bumping APIVR-Δ doesn't bump the nexus.
- **EIIS version** is independent — EIIS can bump to 1.1 without forcing a nexus bump.

### Nexus bump rules (from `docs/architecture.md`)

| Bump | Triggers |
|------|---------|
| **MAJOR** | Removing or renaming a built-in CLI subcommand; breaking-change to `eidolons.yaml` or `eidolons.lock` schema; breaking-change to `roster/index.yaml` shape when consumed by the CLI; raising minimum bash / git / jq / yq version; dropping a supported host wiring. |
| **MINOR** | Adding a new built-in subcommand or top-level flag; adding a new optional roster field or schema; adding a new host wiring; new methodology cortex layer; new MCP scaffold. |
| **PATCH** | Bug fix; doc-only change; roster bump for a shipped Eidolon (the most frequent change); internal refactor; CI tweak. |
