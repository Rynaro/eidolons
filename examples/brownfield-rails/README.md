# Example — Brownfield Rails Project

> Running Rails monolith, ~80k LOC, existing AGENTS.md for another workflow.
> You want to layer Eidolons on top without disrupting what's there.

## Scenario

An existing Rails app at a SaaS company. The team already has:

- `.github/copilot-instructions.md` with team coding conventions
- `CLAUDE.md` pointing at internal docs
- A workflow that uses generic AI assistance, not a structured team

You want to introduce the full Eidolons pipeline for new feature work, without breaking the existing conventions.

## Setup

```bash
cd ~/code/our-rails-app

# Peek first — this never writes anything
eidolons list --presets

# Non-interactive install, pipeline preset
eidolons init --preset pipeline --non-interactive
```

## What happens

The CLI detects:

- `CLAUDE.md` exists → wire Claude Code (will append sections)
- `.github/` exists → wire Copilot (will append to `copilot-instructions.md`, create root `AGENTS.md`)
- No `.cursor/`, no `.opencode/` → skip those hosts

For each member, the install:

1. Appends a section bounded by markers to `AGENTS.md`:

   ```markdown
   <!-- eidolon:atlas v1.0.0 start -->
   ## ATLAS — Scout
   (methodology rules)
   <!-- eidolon:atlas v1.0.0 end -->
   ```

2. Appends a pointer line to `CLAUDE.md`:

   ```markdown
   ## Eidolons
   - @agents/atlas/agent.md
   - @agents/spectra/agent.md
   - @agents/apivr/agent.md
   - @agents/idg/agent.md
   ```

3. Writes per-host dispatch only where the host is detected.

Your pre-existing content in `CLAUDE.md` and `copilot-instructions.md` is **preserved** — the Eidolons only add new sections below what's there.

## `eidolons.yaml`

```yaml
version: 1
hosts:
  wire: [claude-code, copilot]

members:
  - name: atlas
    version: "^1.0.0"
    source: github:Rynaro/ATLAS
  - name: spectra
    version: "^4.2.0"
    source: github:Rynaro/SPECTRA
  - name: apivr
    version: "^3.0.0"
    source: github:Rynaro/APIVR-Delta
  - name: idg
    version: "^1.1.0"
    source: github:Rynaro/IDG

composition:
  pipeline: [atlas, spectra, apivr, idg]
```

## Verify

```bash
eidolons doctor
```

Expected output:

```
▸ eidolons doctor — checking /home/you/code/our-rails-app

Manifest + lock
  ✓ eidolons.yaml present
  ✓ eidolons.lock present

Installed members
  ✓ atlas installed with valid manifest
  ✓ spectra installed with valid manifest
  ✓ apivr installed with valid manifest
  ✓ idg installed with valid manifest

Host wiring
  ✓ CLAUDE.md present (claude-code)
  ✓ Copilot dispatch present

✓ All checks passed.
```

## Use for a new feature

```
@atlas — map the current password-reset flow. Decision target: module list + the
OTP/token handling surface + test coverage map.

@spectra — given ATLAS's report, plan "add TOTP 2FA with backup codes" with
validation gates for PCI compliance.

@apivr — implement SPECTRA's spec.

@idg — chronicle the session and write the ADR for the 2FA decision.
```

## Rollback

If things don't work out:

```bash
# Remove an Eidolon (v1.1+)
eidolons remove atlas

# Or nuclear option — just revert
git checkout -- .
rm -rf agents/
```

Because everything's in git, rollback is cheap.
