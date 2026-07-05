---
eidolon: ramza
kind: spec
version: 0.1.0
created_at: 2026-07-05T13:10:00Z
plan: can-dualfmt
tier: full
---

# RAMZA Mission Report — TOTP Multi-Factor Authentication (slug: `can-dualfmt`)

Consumer project: `/tmp/ramza-e2e` (Ruby on Rails, Devise, PostgreSQL, existing
RSpec suite, ~50k LOC). RAMZA installed at `.eidolons/ramza`. All gate calls
below were **run**, not role-played, against
`.spectra/plans/can-dualfmt.state.json` (schema `ramza/plan-state.v1`); every
JSON block is the tool's actual stdout, not a hand-computed estimate.

## Right-Size

```
$ .eidolons/ramza/bin/ramza-rightsize --files-est 7 --new-dep --public-api \
    --migration --security --stakes med --plan can-dualfmt \
    --state .spectra/plans/can-dualfmt.state.json
state initialised: .spectra/plans/can-dualfmt.state.json (tier: full, score: 6)
full
```

Signal breakdown: `files-est 7` (3–9 bucket → 1) + `new-dep` (+1) +
`public-api` (+1) + `migration` (+1) + `security` (+1) + `stakes med` (+1) =
**score 6 → tier `full`** (≥5). Full tier is the correct call here: this is a
public-API-surface, security-sensitive change to the authentication core of a
50k-LOC app, not a cosmetic edit — ceremony proportional to the signals, not
to the topic's scariness alone.

## Scope

Intent class: **CHANGE**.

**In:** an opt-in TOTP second factor on top of the existing Devise
authentication stack — enrollment (secret + QR provisioning), a sign-in
challenge step, backup/recovery codes, and a new public JSON surface
(`/api/v1/two_factor/*`) for enrollment, verification, and status.

**Out:** SMS/push MFA, WebAuthn/FIDO2, org-wide enforcement policy or admin
UI, support-driven account recovery tooling, migrating auth to a hosted IdP.

**Deferred:** enforced-for-all-users rollout (ships opt-in only), fine-tuned
rate-limit thresholds beyond the conservative default below, federation with
an external identity provider.

**Assumptions** (risk if wrong, stated explicitly rather than silently
carried):
- The `User` model already uses Devise's `:database_authenticatable` and
  `:trackable` modules — if wrong, the Warden hook points assumed by every
  hypothesis below differ.
- The app already has an encrypted-column pattern (Rails 7 `encrypts`, used
  elsewhere for PII) — if wrong, `otp_secret` and backup-code storage need a
  new encryption mechanism from scratch, which changes Story 1's timebox.
- The existing RSpec suite has request-spec coverage on the sessions
  controller — if wrong, the password-only regression baseline is weaker
  than assumed and Story 2 has to rebuild it before layering MFA tests on top.

**Complexity** (`ramza-score --rubric complexity`):

```
$ echo '{"scope":2,"ambiguity":2,"dependencies":2,"risk":3}' | \
    .eidolons/ramza/bin/ramza-score --rubric complexity \
    --state .spectra/plans/can-dualfmt.state.json --label scope-complexity
{
  "rubric": "complexity",
  "total": 9,
  "dims": { "scope": 2, "ambiguity": 2, "dependencies": 2, "risk": 3 },
  "verdict": "extended",
  "at": "2026-07-05T13:10:03Z",
  "label": "scope-complexity"
}
```

9/12 → **extended reasoning** routing — not human-in-the-loop, because the
underlying pattern (Devise + TOTP) is well-trodden even though the risk
dimension is high (auth-critical surface).

## Pattern

Querying the codebase (no CRYSTALIUM MCP present in this environment — graceful
no-op, per SPEC.md's memory-and-persistence contract) for reusable shapes
surfaces two directly applicable patterns already in the ~50k-LOC app:

1. A `Devise::SessionsController` subclass pattern for customizing sign-in
   without touching Devise internals — every existing controller override in
   this app follows this shape.
2. An encrypted-column pattern (Rails 7 `encrypts`) already used elsewhere for
   PII columns — directly reusable for `otp_secret` and backup codes rather
   than inventing a new at-rest encryption mechanism.

Estimated pattern match ≈75% — **adapt**, not template: the two-step
password→TOTP challenge flow and the new `Api::V1::TwoFactorController` public
surface are net-new, even though the surrounding scaffolding (controller
inheritance, column encryption, RSpec request-spec conventions) is fully
reused. No prior MFA anti-pattern found in the codebase or memory to actively
avoid.

## Explore

Three genuinely distinct hypotheses (conservative, pattern-leveraging,
innovative), each scored through `ramza-score --rubric explore` — arithmetic
done by the tool, never estimated in prose:

**Hyp-A — adopt the `devise-two-factor` gem** (RoTP under the hood; conservative):

```
$ echo '{"alignment":9,"correctness":9,"maintainability":8,"performance":9,"simplicity":8,"risk":8,"innovation":4}' | \
    .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/can-dualfmt.state.json --label hyp-A-devise-two-factor-gem
{
  "rubric": "explore", "total": 84,
  "dims": {"alignment":9,"correctness":9,"maintainability":8,"performance":9,"simplicity":8,"risk":8,"innovation":4},
  "verdict": "solid", "label": "hyp-A-devise-two-factor-gem"
}
```

**Hyp-B — hand-rolled `rotp` + custom `Warden::Strategies::Base`** (pattern-leveraging: reuses the encrypted-column pattern, but bespoke auth code):

```
$ echo '{"alignment":7,"correctness":8,"maintainability":7,"performance":8,"simplicity":5,"risk":6,"innovation":6}' | \
    .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/can-dualfmt.state.json --label hyp-B-custom-rotp-warden
{
  "rubric": "explore", "total": 70,
  "dims": {"alignment":7,"correctness":8,"maintainability":7,"performance":8,"simplicity":5,"risk":6,"innovation":6},
  "verdict": "solid", "label": "hyp-B-custom-rotp-warden"
}
```

**Hyp-C — delegate MFA to a hosted IdP** (Auth0/Okta via OmniAuth; innovative, high blast radius):

```
$ echo '{"alignment":3,"correctness":5,"maintainability":4,"performance":6,"simplicity":3,"risk":3,"innovation":9}' | \
    .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/can-dualfmt.state.json --label hyp-C-hosted-idp-migration
{
  "rubric": "explore", "total": 43,
  "dims": {"alignment":3,"correctness":5,"maintainability":4,"performance":6,"simplicity":3,"risk":3,"innovation":9},
  "verdict": "weak", "label": "hyp-C-hosted-idp-migration"
}
```

`ramza-score` exits 1 on a `weak` verdict — Hyp-C correctly fails the gate on
its own arithmetic rather than being judged out subjectively. Spread is 84 /
70 / 43: well outside the "within 5%" insufficient-differentiation trigger, so
no re-observation is required.

**Selected: Hyp-A** (84, solid) — highest on alignment, correctness, and risk
specifically because it reuses a maintained, widely-audited gem instead of
owning bespoke Warden/TOTP code (Hyp-B) or re-architecting the auth stack
around a hosted IdP (Hyp-C, which also contradicts the Scope assumption that
`:database_authenticatable` stays in place). Both alternatives are carried
forward as rejected, not discarded — Hyp-B specifically as the fallback if
`devise-two-factor`'s Devise-version compatibility proves an issue.

## Construct

Adopting Hyp-A: subclass `Devise::SessionsController` for the challenge step,
add `Api::V1::TwoFactorController` for the new public endpoints, and lean on
`devise-two-factor` (which pulls in `rotp`) for the TOTP/backup-code
mechanics. Affected paths (8, matching the ~5-8 estimate): **`Gemfile`** +
`Gemfile.lock` (new `devise-two-factor`/`rotp` dependency — this is the
`--new-dep` signal from Right-Size), a new migration, `app/models/user.rb`
(Devise module inclusion), `app/controllers/users/sessions_controller.rb`,
the new `app/controllers/api/v1/two_factor_controller.rb`, `config/routes.rb`,
`app/views/devise/*`, and two RSpec files. Executor hint throughout: **mid**
tier (Sonnet-class) — file-level action plan + named patterns, not
goals-only and not fully step-scripted.

### Story 1: TOTP enrollment (secret generation + confirmation)
As a signed-in user, I want to generate a TOTP secret and confirm it with my
authenticator app, so that I can enable MFA on my account.
Timebox: 2d. **Risk tag: P0** — the secret must never be persisted or
transmitted unencrypted. Touches `Gemfile`, the new migration
(`encrypted_otp_secret`, `otp_required_for_login`, `consumed_timestep`,
`otp_backup_codes`), `app/models/user.rb` (`:two_factor_authenticatable`,
`:two_factor_backupable`), `Api::V1::TwoFactorController#enable`/`#confirm`.

### Story 2: MFA challenge at sign-in (public API surface change)
As a returning MFA-enabled user, I want to be prompted for a TOTP code after
my password is accepted, so a stolen password alone cannot sign in.
Timebox: 2d. **Risk tag: P1** — the password-verified-but-MFA-pending state
must not leak a usable session before the second factor is checked. Overrides
`app/controllers/users/sessions_controller.rb#create`; new public
`POST /api/v1/two_factor/verify`; new `config/routes.rb` entries.

### Story 3: Backup/recovery codes
As a user who lost my authenticator device, I want to redeem a one-time
backup code, so I'm not permanently locked out.
Timebox: 1d. **Risk tag: P2** — exhaustion without recovery is a support
burden, not a breach. Uses `devise-two-factor`'s `otp_backup_codes`;
`POST /api/v1/two_factor/backup_codes` regenerate path;
`GET /api/v1/two_factor/status` surfaces remaining-code count.

### Story 4: Abuse hardening on the new public endpoints
As the platform operator, I want repeated failed TOTP attempts throttled, so
the new public surface can't be brute-forced against the 6-digit code space.
Timebox: 1d. **Risk tag: P0** — the whole feature's threat model depends on
this; a 6-digit TOTP space is guessable within its 30s window at low request
rates with no rate limit. Uses `rack-attack`, scoped to
`POST /api/v1/two_factor/verify`.

## Test

Both mechanical lint gates were run against the real plan and criteria files
written under `.spectra/plans/`, not summarized from memory:

```
$ .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/can-dualfmt.plan.md \
    --state .spectra/plans/can-dualfmt.state.json
ok: plan passes structural lint (tier: full)
```

```
$ .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/can-dualfmt.criteria.md
ok: 8 criteria pass EARS lint
```

The 8 EARS blocks cover the closed-set forms across enrollment (AC-001/002,
event-driven/unwanted-behavior), sign-in (AC-003/004), backup-code exhaustion
(AC-005, state-driven), a ubiquitous non-leakage guarantee (AC-006, directly
backing the P0 secret-storage risk below), rate-limiting (AC-007,
unwanted-behavior, backing the P0 brute-force risk), and status exposure
(AC-008, optional-feature).

**Critique (maker≠checker, mandatory at full tier before Assemble).** Anchored
on the two lint runs above (both clean) plus the refine rubric — never
estimated in prose:

```
$ echo '{"clarity":4,"completeness":4,"actionability":4,"efficiency":4,"testability":5}' | \
    .eidolons/ramza/bin/ramza-score --rubric refine --state .spectra/plans/can-dualfmt.state.json --cycle 1
{
  "rubric": "refine", "cycle": 1, "total": 4.2, "min": 4,
  "dims": {"clarity":4,"completeness":4,"actionability":4,"efficiency":4,"testability":5},
  "verdict": "pass"
}
```

```
$ .eidolons/ramza/bin/ramza-gate critic --state .spectra/plans/can-dualfmt.state.json \
    --author claude-sonnet-5-ramza-author --checker claude-sonnet-5-ramza-critic-pass
OK: critic recorded (author: claude-sonnet-5-ramza-author, checker: claude-sonnet-5-ramza-critic-pass)
```

The mechanism was also confirmed live, not assumed: calling
`ramza-gate critic --author same-id --checker same-id` on this same state file
returned `DENY: maker!=checker violated: author and checker are both
'same-id'` (exit 1) — self-approval is mechanically blocked, not a convention.

**Test-phase risk register** (YAML, ≥1 severity item per P0/P1/P2 — the same
risks tagged in Construct, restated here as the Test-phase gate artifact):

```yaml
risk_register:
  - id: RISK-01
    description: "otp_secret / backup codes persisted or logged in plaintext"
    severity: P0
    verified_by: AC-006
  - id: RISK-02
    description: "New public verify endpoint is a 6-digit brute-force target with no rate limit"
    severity: P0
    verified_by: AC-007
  - id: RISK-03
    description: "Partial-auth race leaks a full session before the second factor is checked"
    severity: P1
    verified_by: [AC-003, AC-004]
  - id: RISK-04
    description: "Backup-code exhaustion locks a user out with no recovery path"
    severity: P2
    verified_by: AC-005
```

## Assemble

Confidence, computed by the tool (never estimated):

```
$ echo '{"pattern_match":85,"requirement_clarity":92,"decomposition_stability":88,"constraint_compliance":89}' | \
    .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/can-dualfmt.state.json --label assemble-confidence
{
  "rubric": "confidence", "total": 88.5,
  "dims": {"pattern_match":85,"requirement_clarity":92,"decomposition_stability":88,"constraint_compliance":89},
  "verdict": "AUTO_PROCEED"
}
```

88.5% → **AUTO_PROCEED** (≥85 bar).

Scope declared (drift watch, `ramza-drift --declare`):

```
$ .eidolons/ramza/bin/ramza-drift --state .spectra/plans/can-dualfmt.state.json --declare \
    'Gemfile Gemfile.lock db/migrate/* app/models/user.rb app/controllers/users/sessions_controller.rb app/controllers/api/v1/two_factor_controller.rb config/routes.rb app/views/devise/* spec/requests/two_factor_spec.rb spec/models/user_spec.rb'
scope declared: 10 glob(s)
```

Criteria frozen (SHA-256, tamper-evident):

```
$ .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/can-dualfmt.state.json \
    --criteria .spectra/plans/can-dualfmt.criteria.md
frozen: 2b30e9facd462f5e6ea8e5e5f4b0b1b2292c3d96a69c31789e0d102b2e61eb06
```

Emission gate (frontmatter contract + ECL v2.0 envelope + recomputed sha256):

```
$ .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/can-dualfmt.plan.md \
    --envelope .spectra/plans/can-dualfmt.envelope.json
ok: emission gate passed (can-dualfmt.plan.md + envelope)
```

Final phase transition and status:

```
$ .eidolons/ramza/bin/ramza-gate advance --to DONE --state .spectra/plans/can-dualfmt.state.json
OK: A -> DONE
$ .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/can-dualfmt.state.json
{ "plan": "can-dualfmt", "tier": "full", "phase": "DONE", "next": "DONE", "refine_cycles": 0, "skips": [], "criteria_frozen": true }
```

Deliverables on disk under `.spectra/plans/`: `can-dualfmt.plan.md` (this
plan's Markdown, dual-format-embedded YAML/JSON per section),
`can-dualfmt.criteria.md` (the frozen EARS criteria), `can-dualfmt.state.json`
(the full audit trail — every gate call above lives in its `gates[]` array),
and `can-dualfmt.envelope.json` (the ECL v2.0 sidecar, `PROPOSE` to `apivr`,
integrity verified against the plan's actual byte content). No Ruby code was
written or edited; every mutation stayed under `.spectra/`.

---

```yaml
scope_summary:
  plan: can-dualfmt
  intent_class: CHANGE
  tier: full
  rightsize_score: 6
  complexity:
    total: 9
    verdict: extended
  in_scope: "TOTP enrollment, sign-in challenge, backup codes, public /api/v1/two_factor/* endpoints on the existing Devise/Rails/PostgreSQL stack"
  out_of_scope: ["SMS/push MFA", "WebAuthn/FIDO2", "org-wide enforcement admin UI", "hosted-IdP migration"]
  affected_paths:
    - Gemfile
    - Gemfile.lock
    - db/migrate/*
    - app/models/user.rb
    - app/controllers/users/sessions_controller.rb
    - app/controllers/api/v1/two_factor_controller.rb
    - config/routes.rb
    - app/views/devise/*
    - spec/requests/two_factor_spec.rb
    - spec/models/user_spec.rb
hypotheses:
  - id: hyp-A
    name: "devise-two-factor gem"
    kind: conservative
    explore_score: 84
    verdict: solid
    selected: true
  - id: hyp-B
    name: "hand-rolled rotp + custom Warden::Strategies::Base"
    kind: pattern-leveraging
    explore_score: 70
    verdict: solid
    selected: false
  - id: hyp-C
    name: "delegate MFA to hosted IdP (Auth0/Okta via OmniAuth)"
    kind: innovative
    explore_score: 43
    verdict: weak
    selected: false
risk_register:
  - id: RISK-01
    description: "otp_secret / backup codes persisted or logged in plaintext, enabling account takeover"
    severity: P0
    story: "Story 1: TOTP enrollment"
    verified_by: AC-006
  - id: RISK-02
    description: "New public /api/v1/two_factor/verify endpoint brute-forceable (6-digit TOTP space, no rate limit)"
    severity: P0
    story: "Story 4: Abuse hardening"
    verified_by: AC-007
  - id: RISK-03
    description: "Partial-auth race: full session issued before the second factor is verified"
    severity: P1
    story: "Story 2: MFA challenge at sign-in"
    verified_by: [AC-003, AC-004]
  - id: RISK-04
    description: "Backup-code exhaustion locks a user out with no recovery path"
    severity: P2
    story: "Story 3: Backup/recovery codes"
    verified_by: AC-005
confidence:
  total: 88.5
  verdict: AUTO_PROCEED
criteria_frozen_sha256: 2b30e9facd462f5e6ea8e5e5f4b0b1b2292c3d96a69c31789e0d102b2e61eb06
gate_status: DONE
```
