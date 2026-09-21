# Stage 0 — Stabilize the shipped product

Repair current integrity, legacy-upgrade, and publication/wiring defects. No Go dependency or paid model run is required.

Read [HANDOFF.md](HANDOFF.md) and the relevant [ARCHITECTURE.md](ARCHITECTURE.md) boundaries. [plan.yaml](plan.yaml) owns dependencies and source routing; these tables own requirement text. [RESEARCH.md](RESEARCH.md) explains the evidence-to-design mapping without adding hidden obligations.

**Common exit for every package:** map every applicable Rxx to its planned Txx and actual observed evidence. Exercise relevant rejection paths and the intended gate. Mark unavailable required evidence blocked; mark optional cases not applicable only with their feature/scope condition recorded. Authored requirements, authored tests, executed fixtures, observed CI, and live-host qualification are distinct. A fixture-only candidate can be ready for review without a live-managed claim. See HANDOFF.md for receipts and acceptance.

---

<a id="v4-01"></a>

## V4-01 — Fail-closed integrity policy on the shipped kernel

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** none.

**Starting points:** `cli/src/lib.sh`, `cli/src/verify.sh`, `cli/src/doctor.sh`, `cli/src/upgrade_self.sh`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Reproduce #562 against the assigned revision. Repair the shared policy reader and consumers, not the runtime architecture. Normalize case and surrounding whitespace before validating the closed mode set. Explicit advisory mode is not an unreadable policy. An unrelated telemetry error does not disable optional memory.

**Implementation sequence.** Reproduce reported inputs through real consumers; repair common parsing and propagation; add focused shell regressions and inspect the actual PR workflow.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-01-R01 | WHEN a supported integrity mode is supplied with different case or surrounding whitespace, the integrity reader SHALL return its canonical mode. | **V4-01-T01:** Exercise strict, STRICT, Strict, padded strict, and explicit warn through reader and consumers; compare canonical output. |
| V4-01-R02 | IF an integrity mode is outside the supported set, THEN the kernel SHALL reject the protected operation before accepting an unverified artifact. | **V4-01-T02:** Use bogus, empty explicit override, and wrong-type values; assert rejection and no install or acceptance side effect. |
| V4-01-R03 | IF configured integrity policy cannot be parsed or its required parser is unavailable, THEN the kernel SHALL return an integrity-policy error. | **V4-01-T03:** Invalid YAML, absent parser, broken pipeline, and valid control; prove the protected consumer reaches the intended gate. |
| V4-01-R04 | WHILE strict integrity policy is effective, the kernel SHALL reject artifacts without valid required integrity evidence. | **V4-01-T04:** Valid control versus missing, malformed, and mismatched evidence; instrument the verification gate, not any unrelated early failure. |
| V4-01-R05 | WHEN an integrity-policy check fails, the CLI SHALL identify the failed policy source without disclosing secrets. | **V4-01-T05:** Capture stdout/stderr with secret canaries; data stdout remains parseable and secret values remain absent. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Retain strict rejection after policy-read failures. No new feature, bypass, or release is authorized.

---

<a id="v4-02"></a>

## V4-02 — Repair legacy upgrade and preserve real user changes

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-01`.

**Starting points:** `cli/src/upgrade_self.sh`, `cli/src/lib.sh`, `docs/cli-reference.md`, `cli/tests/`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Address #566 for affected v1.41.0-or-earlier installations, not only v2/v3. Detect genuine dirtiness before managed healing, or keep managed exclusions outside tracked files. Preserve integrity regardless of recovery options. Use local fixtures and verified archives, not production installations.

**Implementation sequence.** Construct affected and unaffected installations; repair ordering without ignoring genuine .gitignore changes; test repeat checks, interrupted staging, and data preservation.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-02-R01 | WHEN upgrade inspection runs on an affected clean legacy installation, the updater SHALL avoid creating tracked-file dirtiness. | **V4-02-T01:** Use v1.41.0 and a supported earlier fixture; compare tracked files before and after repeated --check. |
| V4-02-R02 | IF genuine user modifications would be overwritten, THEN the updater SHALL stop with a preservation diagnostic. | **V4-02-T02:** Modify .gitignore and a source file separately; preserve exact changed bytes and distinguish them from managed healing. |
| V4-02-R03 | WHEN a validated replacement is ready for an authorized legacy upgrade, the updater SHALL complete the supported upgrade without a force bypass. | **V4-02-T03:** Test affected legacy, v1.41.1 control, v2.20, and current v3 fixtures against a local verified target. |
| V4-02-R04 | IF staging or replacement validation fails, THEN the updater SHALL retain a usable previous installation. | **V4-02-T04:** Interrupt download/extraction, integrity, and smoke stages; verify the old tree/binary and user settings. |
| V4-02-R05 | WHEN a previously completed upgrade is repeated, the updater SHALL produce no unintended configuration changes. | **V4-02-T05:** Compare second-run outputs and state, including dirty consumer workspaces and host settings. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Keep the previous installation until replacement validation succeeds. Do not use an integrity-bypassing force flag as migration policy.

---

<a id="v4-03"></a>

## V4-03 — Validate authored and published records before release

**Default source owner:** `Rynaro/eidolons`. **Prerequisites:** `V4-01`.

**Starting points:** `schemas/roster.schema.json`, `roster/index.yaml`, `roster/mcps.yaml`, `Makefile`, `.github/workflows/ci.yml`, `.github/workflows/release-nexus.yml`. Locate actual paths in the pinned checkout; proposed interfaces are not claims of existing code.

**Scope and decisions.** Coordinate #563/#564 without assuming every record is defective. Distinguish authored/draft records from publishable integrity metadata. Recheck #205/#465 through current generated wiring: source already contains hyphenated atlas-aci names and UID:GID placeholders; installed drift is a different defect. Avoid broad catalog cleanup.

**Implementation sequence.** Add duplicate-key and incomplete-publication negative fixtures; exercise the shared local/PR/release gate; characterize wiring round trips and repair only reproduced defects.

| ID | EARS requirement | Planned verification |
|---|---|---|
| V4-03-R01 | IF an authored registry contains duplicate mapping keys, THEN the registry validator SHALL reject it before last-wins resolution. | **V4-03-T01:** Duplicate top-level/nested YAML and JSON keys, equal-valued duplicates, and valid controls through supported parsing boundaries. |
| V4-03-R02 | IF a publishable release record lacks valid commit, tree, or archive digest fields, THEN the publication gate SHALL reject that record. | **V4-03-T02:** Omitted, short, nonhex, and placeholder digests fail publication; draft-only permission does not make them publishable. |
| V4-03-R03 | WHEN local validation and PR validation process the same invalid registry, the validation entrypoints SHALL report equivalent blocking results. | **V4-03-T03:** Invoke the shared gate through Makefile and actual workflow; editing a workflow alone is not observed CI evidence. |
| V4-03-R04 | WHEN host wiring is regenerated for a supported MCP definition, the wiring generator SHALL preserve the declared tool identifiers and runtime arguments. | **V4-03-T04:** Assert hyphenated atlas-aci names, invoking UID:GID instead of hardcoded 1000, spaced paths, identity mounts, and repeat generation. |
| V4-03-R05 | IF installed wiring differs from its current generated definition, THEN diagnostics SHALL identify the drift without overwriting user-owned settings. | **V4-03-T05:** Old underscore grants and missing-UID fixtures plus user-owned controls; verify preview and explicit repair. |

**Exit.** Apply the common exit above and the package scope; missing required live evidence blocks its live claim, not disclosure of completed fixture work.

**Stop and rollback.** Do not rewrite historical release evidence or publish placeholder hashes. Preserve existing consumers until replacements are proven.
