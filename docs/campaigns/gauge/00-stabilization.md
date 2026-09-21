# Stage 0 — Stabilize the shipped product

Repair current trust and upgrade defects before adding architecture. No Go dependency or paid model run is needed for this stage.

Read [HANDOFF.md](HANDOFF.md) and [ARCHITECTURE.md](ARCHITECTURE.md). [plan.yaml](plan.yaml) owns package identities, dependencies and source routing. Each table below owns its EARS requirements; verification entries are planned cases, not executed results. Assign one package, and one named slice where applicable.

<a id="v4-01"></a>

## V4-01 — Fail-closed integrity policy on the shipped kernel

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** none. Stage gates also apply.

**Starting points:** `cli/src/lib.sh`, `cli/src/verify.sh`, `cli/src/doctor.sh`, `cli/src/upgrade_self.sh`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Reproduce issue #562 against the assigned revision and patch the shared policy reader plus affected callers. Keep this a current-version correctness fix, not a Go rewrite. Normalize case and surrounding whitespace, then validate a closed mode set. An explicitly authorized advisory mode remains distinct from an unreadable policy. Do not disable optional memory on an unrelated telemetry error.

**Implementation sequence.** Reproduce the four reported inputs through real consumers. Repair the common reader and propagation. Add focused shell regressions and exercise the actual PR workflow.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-01-R01 | WHEN a supported integrity mode is supplied with different case or surrounding whitespace, the integrity reader SHALL return its canonical mode. | **V4-01-T01:** Exercise strict, STRICT, Strict, padded strict, and explicit warn through reader and consumers; compare canonical output. |
| V4-01-R02 | IF an integrity mode is outside the supported set, THEN the kernel SHALL reject the protected operation before accepting an unverified artifact. | **V4-01-T02:** Use bogus, empty explicit override, and wrong-type values; assert nonzero outcome and no install/accept side effect. |
| V4-01-R03 | IF configured integrity policy cannot be parsed or its required parser is unavailable, THEN the kernel SHALL return an integrity-policy error. | **V4-01-T03:** Invalid YAML, missing parser, and broken pipeline fixtures; prove the protected consumer is reached and rejects. |
| V4-01-R04 | WHILE strict integrity policy is effective, the kernel SHALL reject artifacts without valid required integrity evidence. | **V4-01-T04:** Valid artifact control; missing, malformed, and mismatched evidence; instrument the verification gate rather than relying on any early failure. |
| V4-01-R05 | WHEN an integrity-policy check fails, the CLI SHALL identify the failed policy source without disclosing secrets. | **V4-01-T05:** Capture stderr/stdout and secret-like input; JSON/data stdout remains parseable and no secret value is emitted. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Retain strict rejection on failed policy reads; do not roll back into a permissive fallback. No new feature or release is authorized.

---

<a id="v4-02"></a>

## V4-02 — Repair legacy upgrade and preserve real user changes

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-01`. Stage gates also apply.

**Starting points:** `cli/src/upgrade_self.sh`, `cli/src/lib.sh`, `docs/cli-reference.md`, `cli/tests/`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Address #566 for installations at v1.41.0 or earlier, not only v2/v3. Evaluate genuine user dirtiness before managed healing or keep managed exclusions out of tracked files. Preserve integrity checks independently of force/recovery behavior. Use local fixtures and verified archives; no live production upgrade.

**Implementation sequence.** Construct affected and unaffected installations. Repair ordering/exclusion handling without ignoring genuine .gitignore edits. Test repeat check/upgrade, interrupted staging, and user-data preservation.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-02-R01 | WHEN upgrade inspection runs on an affected clean legacy installation, the updater SHALL avoid creating tracked-file dirtiness. | **V4-02-T01:** Use v1.41.0 and a supported earlier fixture; compare tracked files before/after repeated --check operations. |
| V4-02-R02 | IF genuine user modifications would be overwritten, THEN the updater SHALL stop with a preservation diagnostic. | **V4-02-T02:** Modify .gitignore and a source file separately; assert the changed bytes survive and are not misclassified as managed healing. |
| V4-02-R03 | WHEN a validated replacement is ready for an authorized legacy upgrade, the updater SHALL complete the supported upgrade without a force bypass. | **V4-02-T03:** Test affected legacy, v1.41.1 control, v2.20, and current v3 fixtures against a local verified target. |
| V4-02-R04 | IF staging or replacement validation fails, THEN the updater SHALL retain a usable previous installation. | **V4-02-T04:** Inject interrupted download/extraction, integrity failure, and smoke failure; verify the previous binary/tree and user settings. |
| V4-02-R05 | WHEN a previously completed upgrade is repeated, the updater SHALL produce no unintended configuration changes. | **V4-02-T05:** Second-run comparison plus dirty consumer workspace and host settings preservation. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Keep the old installation intact until replacement validation succeeds. Never recommend an integrity-bypassing force flag as the normal migration.

---

<a id="v4-03"></a>

## V4-03 — Validate authored and published records before release

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-01`. Stage gates also apply.

**Starting points:** `schemas/roster.schema.json`, `roster/index.yaml`, `roster/mcps.yaml`, `Makefile`, `.github/workflows/ci.yml`, `.github/workflows/release-nexus.yml`. Resolve symbolic/new paths in the actual checkout; they are not claims those interfaces already exist.

**Scope and decisions.** Coordinate #563/#564: distinguish source/draft validation from publishable integrity records. Do not classify an open issue as a reproduced defect automatically. Recheck #205/#465 through current generated wiring: current source already contains hyphenated atlas-aci names and UID:GID placeholders; old installation drift is a distinct case. Do not perform a broad catalog cleanup.

**Implementation sequence.** Add negative fixtures for duplicate keys and incomplete published records. Wire real schema validation to local and PR/release entrypoints. Characterize wiring round trips and fix only reproduced current defects.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-03-R01 | IF an authored registry contains duplicate mapping keys, THEN the registry validator SHALL reject it before last-wins resolution. | **V4-03-T01:** Duplicate top-level and nested YAML/JSON keys, equal-valued duplicates, and valid controls; exercise every supported parsing boundary in this scope. |
| V4-03-R02 | IF a publishable release record lacks valid commit, tree, or archive digest fields, THEN the publication gate SHALL reject that record. | **V4-03-T02:** Omitted/short/nonhex hashes and draft placeholders fail publication; an explicitly draft-only fixture does not become publishable. |
| V4-03-R03 | WHEN local validation and PR validation process the same invalid registry, the validation entrypoints SHALL report equivalent blocking results. | **V4-03-T03:** Run the shared gate via Makefile and the real workflow; a workflow edit alone is not CI evidence. |
| V4-03-R04 | WHEN host wiring is regenerated for a supported MCP definition, the wiring generator SHALL preserve the declared tool identifiers and runtime arguments. | **V4-03-T04:** Assert hyphenated atlas-aci tool names, invoking UID:GID rather than hardcoded 1000, spaced paths, identity mounts, and repeat-generation behavior. |
| V4-03-R05 | IF installed wiring differs from its current generated definition, THEN diagnostics SHALL identify the drift without overwriting user-owned settings. | **V4-03-T05:** Old underscore grant and missing-UID fixtures plus user-owned configuration controls; verify preview and explicit repair path. |

**Exit.** Map every requirement above to observed evidence or a named blocker. Read HANDOFF.md for mechanical, independent, CI and live-evidence distinctions. Unavailable mandatory evidence prevents acceptance; a fixture-only candidate can be ready for review without claiming live qualification.

**Stop and rollback.** Do not rewrite historical release evidence or accept placeholder hashes in publishable records. Keep existing consumers until replacements are proven.

---
