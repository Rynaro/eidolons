# Example — Solo ATLAS

> Just the scout. Read-only audit of an unfamiliar codebase.

## Scenario

You've inherited a codebase. Unknown language mix, unclear architecture, no documentation. You want to understand it without changing anything.

You don't need planning. You don't need implementation. You don't need chronicles yet. You need a scout.

## Setup

```bash
cd ~/code/inherited-project
eidolons init --members atlas
```

Or explicitly:

```bash
eidolons init --preset minimal
```

## What gets installed

Just ATLAS. Minimal footprint:

```
inherited-project/
├── .github/                     (only if .github/ already existed)
├── agents/
│   └── atlas/                   ← ATLAS methodology + install.manifest.json
├── AGENTS.md                    ← ATLAS section only
├── CLAUDE.md                    ← pointer to atlas/agent.md
├── eidolons.yaml
└── eidolons.lock
```

## `eidolons.yaml`

```yaml
version: 1
hosts:
  wire: [claude-code]    # or whichever host you use

members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/atlas
```

## Use

ATLAS refuses write verbs — it will never edit, commit, or modify anything.

```
@atlas mission — I inherited this codebase. Map the top-level architecture.

Decision target: module inventory + entry points + test coverage surface +
a 5-finding prioritized list of "things a new engineer needs to know."

Constraint: no changes. This is reconnaissance only.
```

ATLAS runs its 5-phase cycle (`A→T→L→A→S`) and produces a `scout-report.md` with evidence-anchored findings.

## Adding a teammate later

When you're ready to plan changes:

```bash
eidolons add spectra
```

The new member installs alongside ATLAS. The scout report you already have becomes a valid upstream for SPECTRA — the handoff works immediately.

## Why solo

Partial-team deployment is a first-class configuration, not a degraded mode. ATLAS was designed to be useful on its own. The handoff contracts to SPECTRA and APIVR-Δ are optional outputs — ATLAS doesn't need them to work.

See [`../../methodology/composition.md`](../../methodology/composition.md) §3 for the full partial-deployment guide.
