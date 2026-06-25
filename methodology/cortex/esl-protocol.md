# Cortex Deep — ESL Escalation Protocol (RECORD → HONOR)

> Load this file when verifying a project's ESL changes, deciding the verify
> enforcement mode, or recording a project's escalation. See `EIDOLONS.md`
> §"ESL — Spec Lifecycle" for the always-loaded summary. See `README.md` for
> load-when guidance.

ESL ships its **computation** (`tonberry assess`) and its **lever**
(`tonberry verify --mode warn|block`). This protocol closes the two missing
hops — **RECORD** the enforcement decision durably, and **HONOR** it when
verifying — without resurrecting a spec-lifecycle verb family. Owner split
(FORGE verdict H5): the **nexus** owns the lock-write; the **orchestrator** owns
*when verify runs*. `esl-1.0.md` stays opt-in and untouched; `tonberry` never
writes `eidolons.mcp.lock`.

---

## RECORD — `eidolons mcp assess tonberry`

The nexus subcommand `eidolons mcp assess <name>` runs the MCP's one-shot
`assess` op against the project, reads back
`{signals, thresholds, tripped[], recommended_mode}`, and **the nexus** (never
tonberry) upserts the decision into that MCP's `eidolons.mcp.lock` entry:

```jsonc
{
  "name": "tonberry", "kind": "oci-image", /* …existing fields… */
  "enforcement": "advisory",            // "advisory" | "block" — the recorded mode
  "enforcement_signals": {              // the numbers that produced it (auditability)
    "change_count": 7, "repo_loc": 41000, "full_ratio": 0.22
  },
  "enforcement_thresholds": { "N": 10, "L": 50000, "R": 0.4 },
  "enforcement_assessed_at": "2026-06-25T00:00:00Z"
}
```

The lockfile is VCS-committed, so the escalation is auditable in a PR diff.

**When to run it (trigger):**

- **On `archive` / end-of-change** — the change-lifecycle rhythm; assess once
  the change set is complete so the recorded mode reflects the project's new
  size. *(Recommended default — no polling daemon.)*
- **Manually / on a cadence** — re-run after large growth, or before a release,
  to refresh `enforcement` when the project crosses a threshold.

`assess` does NOT fire on `eidolons sync`/`install` (those are wiring ops, not
policy decisions). An "advisory" result is a normal exit 0, not a failure.

**Graceful skip (ESL opt-in):** if tonberry is not installed, or its `assess`
op is unavailable, `mcp assess` warns and exits 0 with no lock write — the
project is never hard-failed.

**Idempotency carry-forward (load-bearing):** the catalogue-driven
`eidolons mcp install`/`refresh` entry-builders rebuild the lock entry and do
NOT know the `enforcement*` fields; `mcp_lock_upsert`'s no-op signature also
excludes them. The install/refresh path therefore **carries forward** any
pre-existing `enforcement*` before upsert (`mcp_lock_carry_enforcement`). A
re-install MUST NOT clear a recorded escalation. The `mcp assess` write itself
bypasses the no-op signature (`mcp_lock_set_enforcement`) so an
enforcement-only change always persists.

---

## HONOR — before `tonberry verify` on a project's changes

The verifying caller (orchestrator/cortex — the only actor holding both project
state and the tonberry grant) chooses the verify mode with a **two-layer
fallback**:

| Condition | Action |
|---|---|
| `enforcement: "block"` recorded in the tonberry lock entry | Pass `--mode block` to `tonberry verify`. |
| `enforcement: "advisory"` recorded | Pass `--mode warn` (advisory). |
| **Field absent** (never assessed) | Run a live `tonberry assess` and honor its `recommended_mode`. |
| **tonberry absent** (not installed) | Default **advisory** and proceed — never block on a missing tool. |

Read the recorded mode with:

```sh
jq -r '(.mcps // [])[] | select(.name=="tonberry") | .enforcement // empty' eidolons.mcp.lock
```

The recorded mode is sticky and cheap (no recompute); the live-assess fallback
keeps the honor hop correct when nothing has been recorded yet.

---

## Thresholds are tunable lock knobs (NOT baked constants)

The seed escalation thresholds are:

| Knob | Seed | Meaning |
|------|------|---------|
| `N` | 10 | change_count — number of tracked changes before escalating |
| `L` | 50000 | repo_loc — repository lines of code |
| `R` | 0.4 | full_ratio — share of `full`-sized changes |

These are recorded under `enforcement_thresholds` in the lock when an assessment
runs, so they travel with the project and can be tuned per-project. They are
**not** compiled into the nexus — the nexus records whatever thresholds
`tonberry assess` reports. Changing the policy is a tonberry/assess concern; the
nexus only persists and honors the result.

---

## Owner boundaries (anti-scope)

- **tonberry computes** `assess`; it never writes `eidolons.mcp.lock`.
- **nexus records** via `eidolons mcp assess` (the only writer of the
  `enforcement*` lock fields).
- **orchestrator honors** by reading the lock field and choosing `--mode`.

No new top-level `eidolons spec`/`esl` verb is introduced — the demand is the
record+honor slice, satisfied by one `mcp` subcommand plus this cortex protocol.
