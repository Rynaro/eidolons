# Migration guide — the v2.0 contract bumps

The v2.0 line shipped two additive contract revisions: **ECL 2.0 → 2.1** (the
hand-off wire format) and **EIIS 1.4 → 1.5** (the install contract). This
guide covers both. The specs themselves are canonical — this document is the
operational path, not a re-declaration.

**Who has to act:**

| You are… | Action |
|---|---|
| A **consumer project** (`eidolons.yaml` + installed members) | **Nothing.** Both bumps are opt-in and scoped by declared version. `eidolons upgrade` picks up member releases that adopt them. |
| A **shipped roster member** | **Already migrated.** All eight Eidolons adopted both contracts in the Wave-3 releases (2026-07-03) — this guide is their record. |
| A **new or third-party Eidolon** | Follow the steps below when you want the 2.1 / 1.5 guarantees. Staying on 2.0 / 1.4 remains fully conformant. |

---

## ECL 2.0 → 2.1 (envelopes)

Spec: [`Rynaro/eidolons-ecl`](https://github.com/Rynaro/eidolons-ecl) `spec/ecl-2.1.md` · Published 2026-07-03 (adoption gate met eight-fold)

**Nothing breaks.** Gates are driven per-envelope by `envelope_version`: v2.0
and v1.x envelopes verify **byte-identically** to before, forever. Declaring
`"2.1"` is the opt-in that activates the new MUSTs.

What `envelope_version: "2.1"` binds:

1. **S-3 promoted SHOULD → MUST**: the `ise` block (`assertion_grade`,
   `receiver_authorization`) is required at `trust_level: high`. A high-trust
   envelope without a typed trust grade no longer verifies.
2. **I-5 promoted SHOULD → MUST**: `hmac-sha256` integrity is required at
   `trust_level: high` (plain `sha256` stays fine at lower trust levels).
3. **New OPTIONAL `ise.verification` sub-block** (§6.5.8):
   `{ fresh_context: bool, checker: <eidolon-slug>, transcript_access:
   none|artifact-only }`. Optional to emit — but when present, its shape is
   MUST (gate S-4) and all three fields are required. ECL only shape-checks
   it; the *semantic* rule that `assertion_grade: "validated"` pairs with a
   fresh-context, different-`checker` verification is owned by **ESL C8**,
   not ECL (§6.5.8.3).

### Steps for an emitter

1. On every envelope you emit at `trust_level: high`, add the `ise` block
   (grade honestly: `validated` only behind a real external verifier —
   everything self-reviewed is `self-attested`) and switch the integrity tag
   to `hmac-sha256`. If you can't do either, lower the trust level instead —
   that is the honest move, not a downgrade.
2. Where a distinct checker verified the artifact in a fresh context, emit
   `ise.verification` so downstream readers get the claim as a field.
3. Flip `envelope_version` to `"2.1"`.
4. Verify: run the ECL conformance checker (bash 3.2, no dependencies) from
   the spec repo — it applies 2.1 gates to any envelope that declares 2.1,
   so you can migrate one performative at a time.

---

## EIIS 1.4 → 1.5 (install manifests)

Spec: [`Rynaro/eidolons-eiis`](https://github.com/Rynaro/eidolons-eiis) `spec/eiis-1.5.md` · Released 2026-07-02

**Nothing breaks.** v1.0–v1.4 Eidolons remain conformant unchanged; the new
MUSTs bind only when you declare `EIIS_VERSION = 1.5`. The bump closes one
real gap: host hook shims (a `SessionStart` / `UserPromptSubmit` script)
previously had **no home in the contract** — they couldn't be
inventory-tracked, swept on uninstall, or doctor-verified.

What `EIIS_VERSION = 1.5` binds:

1. **`files_written[].role: "hook"`** for shim files, which MUST live flat
   under `<target>/hooks/<name>.sh` (§1.9.7–§1.9.9 whitelist; no
   subdirectories, `.sh` only). Note the trap in the other direction: a
   **1.4**-declared Eidolon shipping a `hooks/` directory fails `I1` — the
   path isn't whitelisted before 1.5, so shipping hooks *requires* the bump.
2. **`hook_event`** on every `role: "hook"` entry — closed enum
   `session-start | prompt-submit | pre-tool | stop` (gate `I6`, which also
   enforces sweep symmetry: every file under `hooks/` must be
   manifest-declared).
3. **Shim ≠ registration** (§4.7): the shim file is `role: "hook"`; the
   host-config edit that wires it in (e.g. a `settings.json` entry) stays
   `role: "dispatch"` under the existing host-wiring/marker rules. Security
   model explicitly unchanged: installers still write only to the consumer
   project's cwd; hooks add no new write surface (§4.7.4). Hook *execution*
   semantics are a declared non-goal — EIIS governs presence/tracking/sweep
   only (§4.7.5).

### Steps for an installer author

1. Place hook shims flat under `<target>/hooks/`, `.sh` extension.
2. Declare each in the manifest with `role: "hook"` + its `hook_event`; keep
   the host-config registration entries as `role: "dispatch"`.
3. Bump `EIIS_VERSION` to `1.5`.
4. Verify: run the EIIS conformance checker; `I6` MUST-fails at ≥ 1.5 and
   warn-onlys at ≤ 1.4, so a staged rollout is safe.

The global warn→hard-fail promotion clock (§6.4) is **unchanged at
2027-04-24** — 1.5 adds rows to the existing table; it does not open a new
promotion window.

---

## Version compatibility at a glance

| Contract | Old declared version | Verifies under new checker? | New MUSTs apply? |
|---|---|---|---|
| ECL | `1.0`–`1.2`, `2.0` | Yes — byte-identical output | No |
| ECL | `2.1` | Yes | Yes (S-3, I-5, S-4-if-present) |
| EIIS | `1.0`–`1.4` | Yes (I6 warn-only) | No — but `hooks/` still fails `I1` |
| EIIS | `1.5` | Yes | Yes (I6; `hooks/` whitelisted) |

Both checkers are bash 3.2-compatible and dependency-free by contract — the
same floor as the `eidolons` CLI itself.
