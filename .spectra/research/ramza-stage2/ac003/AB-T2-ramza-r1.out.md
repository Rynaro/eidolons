---
eidolon: ramza
version: 0.1.0
kind: spec
status: ready-for-apivr
created_at: 2026-07-05T19:30:07Z
target_repos:
  - engineering/core-rails-monolith
stories_count: 5
validation_gates_count: 6
confidence: 0.835
---

# Account Soft-Delete (Recoverable Deletion)

> RAMZA full-tier plan. State file: `.spectra/plans/account-soft-delete.state.json`.
> Frozen acceptance criteria: `.spectra/plans/account-soft-delete.acceptance.md`
> (sha256 `9ca6d2e3f7d6e0808e8002d0536b8367b689d7dcee19943905d0afd3e6f52d4e`).
> ECL envelope: `.spectra/plans/account-soft-delete.envelope.json`.

## Scope

Intent class: CHANGE

In:
- A soft-delete (`deleted_at`) capability on `Account` itself: schema, default-scope
  hiding, an override of `destroy`/`destroy!` that preserves every existing callback,
  a `#restore!` path (admin-gated), and a hard-purge escape hatch for compliance
  erasure requests plus a retention-window purge job.
- Cascading the same soft-delete semantics to `Account`'s directly billing/identity-
  relevant first-order dependents (`subscriptions`, `users`, `api_keys`) so a
  restored Account is restored with the children a normal restore expects.
- Admin tooling: hiding soft-deleted accounts from the default list/detail views,
  a "Deleted accounts" filtered view, and a permission-gated Restore action.
- Reworking identity-bearing uniqueness constraints (email, slug) so a soft-deleted
  account's identity can be reused by a new signup.

Out:
- Soft-deleting `invoices` (`dependent: :destroy`, Finance-owned). Left unchanged
  in Phase 1 pending Finance's retention-policy sign-off — see AC-008 and Risks.
- Self-service (non-admin) restore. Phase 1 restore is an admin/console action only.
- Cross-account merge/dedupe workflows.
- Functional revocation semantics for soft-deleted `api_keys` beyond row visibility
  (i.e., whether a soft-deleted key must also be cryptographically/functionally
  revoked immediately, vs. simply hidden) — flagged to Security as an open decision
  in the Impact Assessment, not resolved by this spec.

Deferred:
- Extending cascade soft-delete to `invoices` (Phase 2, contingent on Finance).
- Self-service restore UI (Phase 2, contingent on product decision about who may
  see a "recently deleted" state on their own account).

Assumptions:
- No concrete target repository or existing `Account` model source was available
  to this planning session (this spec was authored without a codebase to grep).
  `target_repos` above and every call site in the Impact Assessment are
  **representative, not verified** against a real codebase — risk if wrong: the
  actual dependent-association graph, callback set, or admin controller names
  differ from what's assumed here. Mitigation: Story 1's first task is a mechanical
  call-site audit (grep for `\.destroy\b`, `dependent: :destroy`, `Account\.destroy_all`,
  and any DB-level `UNIQUE` constraint on Account identity columns) to reconcile
  this table with the real repository before implementation proceeds past Story 1.
- The application is a single mature Rails monolith with ActiveRecord/PostgreSQL
  (partial unique indexes assumed available) — risk if wrong: a MySQL backend
  lacks partial indexes, and AC-009's constraint-scoping must fall back to
  validation-layer-only enforcement (documented in Risks).
- "Other teams" own specific destroy callbacks/associations (Billing, Security,
  Finance, Data) as named in the Impact Assessment — risk if wrong: the real
  ownership map differs, but the *mechanism* (preserve callback firing order,
  identify per-association cascade decision) is unaffected by exactly who owns
  which callback.

Complexity (`ramza-score --rubric complexity`): 9/12 → extended.

## Approach

Override `Account#destroy`/`#destroy!` (via a shared `SoftDeletable` concern, not
a per-model reimplementation) so the standard ActiveRecord callback chain still
runs in full — `before_destroy`, the `dependent: :destroy` association callbacks,
`after_destroy`, `after_commit on: :destroy` — but the terminal persistence
operation becomes `update_column(:deleted_at, Time.current)` instead of a SQL
`DELETE`. This is the "override the verb, keep the callback contract" pattern
(the same shape as the `paranoia` gem, implemented in-house to avoid an external
dependency footprint on a core, widely-depended-on model). A `default_scope { where(deleted_at: nil) }`
hides soft-deleted rows from every normal query (including the existing admin
`#index`/`#show`, with zero code change there); `Account.with_deleted` /
`Account.only_deleted` provide the escape hatch for the admin "Deleted accounts"
view and for `#restore!`.

This means every *existing* call site that already calls `account.destroy`
(`Admin::AccountsController#destroy`, `Support::AccountClosureService`,
`Billing::DelinquentAccountSweeperJob`) needs **no code change** to start
producing recoverable deletes — the behavior change is transparent at the
call site and load-bearing at the model layer. See Impact Assessment for what
*does* need attention: two real landmines surface once you trace what
`dependent: :destroy` and DB-level uniqueness constraints actually do once the
terminal delete is replaced by an update.

**Landmine 1 — dependent children.** `dependent: :destroy` is itself implemented
as a `before_destroy` callback that iterates the association and calls `.destroy`
on each child. Because the override does not skip the callback chain, those
children callbacks *still fire and still hard-delete* unless the children also
become soft-deletable. A restored Account with no `users`/`subscriptions`/`api_keys`
is not a useful restore, so Phase 1 extends the `SoftDeletable` concern to those
three associations and changes their declaration from `dependent: :destroy` to
`dependent: false` plus an explicit same-transaction cascade in the concern
(AC-007). `invoices` is deliberately excluded from this cascade (AC-008) — Finance
owns the retention-policy question of whether historical invoices should survive
an account soft-delete, and this spec does not answer that on Finance's behalf.

**Landmine 2 — identity uniqueness.** If `accounts.email`/`accounts.slug` carry a
plain (non-partial) DB-level `UNIQUE` constraint, hiding a soft-deleted row via
`default_scope` does **not** free that email/slug for reuse — the constraint
still fires at the database layer regardless of what ActiveRecord's default scope
hides. This directly undercuts `Billing::DelinquentAccountSweeperJob`'s implicit
assumption that closing a delinquent account frees up their billing email
immediately. Phase 1 converts the constraint to a Postgres partial unique index
(`WHERE deleted_at IS NULL`) plus a matching Rails validation scope (AC-009).

**Compliance boundary.** Soft-delete is retention, not erasure. A separate
`AccountPurgeJob` permanently deletes accounts whose `deleted_at` exceeds the
configured retention window (AC-010), and a permission-gated hard-purge escape
hatch lets an authorized compliance operator satisfy an immediate GDPR/CCPA
erasure request ahead of that window (AC-011, AC-014) — this is what earned this
plan its `--security` right-sizing flag.

## Impact Assessment — Existing Call Sites & Dependents

Representative call-site inventory (see Assumptions — reconcile against the real
repo in Story 1's audit task before implementation). "Action" is what this spec
requires; "No change required" means the override is transparent at that site.

| # | Call site / association | Owner | Current behavior | Behavior under this spec | Required action |
|---|---|---|---|---|---|
| 1 | `Admin::AccountsController#destroy` | Platform/Admin | `@account.destroy` → hard delete | Transparently becomes soft-delete | No code change; update UI copy from "Delete" to reflect recoverability |
| 2 | `Admin::AccountsController#index` / `#show` | Platform/Admin | `Account.all` / `Account.find` list all rows | Soft-deleted rows hidden automatically (`default_scope`) | Add "Deleted accounts" filtered view + Restore action (Story 3) |
| 3 | `Support::AccountClosureService#call` | Support / Trust & Safety | Calls `account.destroy` to close abusive accounts | Becomes a recoverable soft-delete | **Open decision:** confirm whether abuse-closed accounts should be restore-eligible at all, or need a `deletion_reason` that gates restore permission separately from AC-006's role check |
| 4 | `Billing::DelinquentAccountSweeperJob` | Billing | Scheduled job hard-deletes accounts unpaid >90d; implicitly assumes billing email is freed | Becomes soft-delete; email is freed only once AC-009 ships | Billing confirms immediate email-reuse-after-soft-delete is acceptable (assumed default: yes) |
| 5 | `before_destroy :revoke_active_sessions` | Security/Platform | Fires on hard destroy | Fires unchanged (AC-002) | No change required |
| 6 | `before_destroy :cancel_pending_invoices!` (may `throw(:abort)`) | Finance | Fires on hard destroy; can halt destroy | Fires unchanged; an abort still halts soft-delete exactly as it halts hard-delete today | No change required |
| 7 | `after_destroy :billing_system_deprovision` (external API call) | Billing | Fires after hard destroy | Fires unchanged at soft-delete time — **not automatically reversed on restore** | Billing confirms this is acceptable, or scopes a follow-up to re-provision on restore |
| 8 | `after_destroy :analytics_account_purge_event` (Kafka) | Data | Emits an irreversible "account deleted" event | Fires unchanged at soft-delete time | Data confirms downstream consumers tolerate a "deleted" event possibly followed by a restore |
| 9 | `after_commit on: :destroy :cache_bust_account` | Platform | Busts cache after hard destroy | Fires unchanged; harmless (cache miss re-reads, correctly excluded via `default_scope`) | No change required |
| 10 | `has_many :subscriptions, dependent: :destroy` | Billing | Cascades real delete | Must cascade soft-delete instead (AC-007) | Apply `SoftDeletable` to `Subscription`; change association declaration |
| 11 | `has_many :users, dependent: :destroy` | Platform/IAM | Cascades real delete | Must cascade soft-delete instead (AC-007) | Apply `SoftDeletable` to `User`; change association declaration |
| 12 | `has_many :api_keys, dependent: :destroy` | Security | Cascades real delete | Must cascade soft-delete instead (AC-007) — but see Out-of-scope note on functional revocation | **Open decision:** Security confirms whether a soft-deleted key must also be functionally revoked, not just hidden |
| 13 | `has_many :invoices, dependent: :destroy` | Finance | Cascades real delete | **Intentionally unchanged** in Phase 1 (AC-008) | Finance sign-off required before Phase 2 extends cascade |
| 14 | `has_many :audit_logs, dependent: :nullify` | Compliance | Nullifies FK on destroy; logs survive | Unchanged — no interaction with soft-delete | No change required |
| 15 | Test suite `Account.destroy_all` usage in CI cleanup | All teams (shared infra) | Truncates test DB state | Will soft-delete rows if any suite relies on model-level `destroy_all` rather than `DatabaseCleaner` truncation | Verify CI cleanup strategy; flag any model-level reliance |
| 16 | DB-level `UNIQUE` constraint on `accounts.email` / `accounts.slug` | Platform/DBA | Plain unique index | Still blocks reuse of a soft-deleted identity unless converted | Migrate to partial unique index `WHERE deleted_at IS NULL` (AC-009) |

## Stories

### Story 1: Recoverable deletion on Account

As a support engineer, I want destroying an Account to be recoverable, so that an
accidental or premature deletion doesn't cause permanent data loss.
Acceptance criteria owned: AC-001, AC-002, AC-003, AC-007, AC-012, AC-013.
Timebox: 5d.
Risk tag: P0.
Executor hint: frontier tier — goals, constraints, and acceptance criteria; the
`SoftDeletable` concern's design (override shape, transaction boundary) is a
judgment call best left unscripted for a strong executor. First task, regardless
of executor tier: run the call-site audit (grep `\.destroy\b`, `dependent: :destroy`,
`Account\.destroy_all`, DB unique constraints) and reconcile against the Impact
Assessment table above before writing the migration.

### Story 2: Preserve cross-team destroy-callback contracts

As an engineer on Billing, Security, or Data who owns a `before_destroy`/
`after_destroy` callback on Account, I want that callback to keep firing exactly
as it does today, so that my team's integration doesn't silently break when
soft-delete ships.
Acceptance criteria owned: AC-008 (the invoices-cascade boundary is the codified
form of this story's cross-team negotiation; rows 3, 4, 7, 8, 12 of the Impact
Assessment are this story's task list and are sign-off items, not separately
testable code behaviors).
Timebox: 2d engineering (circulate the Impact Assessment, capture each team's
sign-off or requested change in writing, adjust AC-008/Risks if a team requests
different behavior) — **plus** untracked elapsed wait time for Support, Billing,
Data, and Security to respond, which is not under this plan's control and is
deliberately not folded into the 2d engineering box (a fixed multi-team-response
timebox would misreport this story's actual code velocity).
Risk tag: P0.
Executor hint: mid tier — a named per-team checklist (Impact Assessment rows
5–14) is the action plan; each row's "Required action" is the task list.

### Story 3: Admin tooling — hide, filter, restore

As an admin-tool user, I want soft-deleted accounts hidden from the default list
but visible in a dedicated "Deleted accounts" view with a permission-gated
Restore action, so I don't accidentally interact with deleted accounts but can
still recover one when needed.
Acceptance criteria owned: AC-004, AC-005, AC-006, AC-014.
Timebox: 3d.
Risk tag: P1.
Executor hint: mid tier — file-level action plan: new `Admin::AccountsController`
action + route + view partial + `accounts:restore` permission check + `RestoreAudit` model.

### Story 4: Compliance retention window and hard-purge escape hatch

As a compliance operator, I want soft-deleted accounts to be permanently purged
after a retention window, and I want an immediate hard-purge action for erasure
requests, so that recoverable deletion never becomes an obstacle to honoring a
legal erasure obligation.
Acceptance criteria owned: AC-010, AC-011.
Timebox: 4d.
Risk tag: P0.
Executor hint: mid tier — explicit steps: `AccountPurgeJob` (scheduled, retention
window configurable), `Compliance::AccountPurgeService` (immediate, permission-gated),
alerting on job failure rate.

### Story 5: Identity-constraint rework for reuse-after-delete

As a signup/billing flow, I want a previously soft-deleted account's email/slug
to be reusable by a new account, so that closing a delinquent account actually
frees that identity the way it does today.
Acceptance criteria owned: AC-009.
Timebox: 2d.
Risk tag: P0.
Executor hint: mid tier — explicit migration steps: add partial unique index(es),
update model validation scope, backfill/verify no existing duplicate `deleted_at
IS NULL` rows before the constraint migration runs.

## Acceptance Criteria

Frozen via `ramza-freeze` (sha256 `9ca6d2e3f7d6e0808e8002d0536b8367b689d7dcee19943905d0afd3e6f52d4e`,
source file `.spectra/plans/account-soft-delete.acceptance.md`, verbatim reproduction below):

### AC-001 (event-driven)
GIVEN an existing, persisted Account
WHEN an authorized caller invokes `account.destroy` or `account.destroy!`
THEN the system SHALL set `deleted_at` to the current time and persist the account via UPDATE instead of deleting the row
VERIFY: test: spec/models/account_spec.rb#soft_deletes_on_destroy

### AC-002 (ubiquitous)
THEN the system SHALL run every existing `before_destroy` and `after_destroy` callback on Account, in the same order, when `destroy`/`destroy!` is invoked on a soft-deletable Account
VERIFY: test: spec/models/account_spec.rb#preserves_existing_destroy_callback_chain

### AC-003 (ubiquitous)
THEN the system SHALL exclude accounts with a non-null `deleted_at` from `Account.all` and every default query scope, including `Admin::AccountsController#index` and `#show`
VERIFY: test: spec/models/account_spec.rb#default_scope_excludes_soft_deleted

### AC-004 (event-driven)
GIVEN a soft-deleted account
WHEN an admin with the `accounts:restore` permission triggers Restore from the "Deleted accounts" view
THEN the system SHALL clear `deleted_at` on that account
VERIFY: test: spec/requests/admin/accounts_spec.rb#restore_clears_deleted_at

### AC-005 (event-driven)
GIVEN a soft-deleted account is restored
WHEN the restore action completes
THEN the system SHALL record a `RestoreAudit` entry naming the account, the acting admin, and the restore timestamp
VERIFY: test: spec/requests/admin/accounts_spec.rb#restore_writes_audit_entry

### AC-006 (unwanted-behavior)
IF a caller without the `accounts:restore` permission attempts to restore a soft-deleted account
THEN the system SHALL deny the request with HTTP 403
VERIFY: test: spec/requests/admin/accounts_spec.rb#denies_restore_without_permission

### AC-007 (event-driven)
GIVEN an Account has associated `subscriptions`, `users`, and `api_keys` records
WHEN the account is soft-deleted
THEN the system SHALL soft-delete each of those associated records within the same database transaction instead of hard-deleting them
VERIFY: test: spec/models/account_spec.rb#cascades_soft_delete_to_dependent_children

### AC-008 (unwanted-behavior)
IF an Account with un-cancelled `invoices` is soft-deleted
THEN the system SHALL leave the existing `invoices` `dependent: :destroy` behavior unchanged, hard-deleting invoices exactly as it does today
VERIFY: test: spec/models/account_spec.rb#invoices_cascade_unchanged_pending_finance_signoff

### AC-009 (ubiquitous)
THEN the system SHALL scope every identity-bearing uniqueness constraint on Account (email, slug) to exclude soft-deleted rows, so a new account may reuse a previously soft-deleted identity value
VERIFY: test: spec/models/account_spec.rb#uniqueness_excludes_soft_deleted

### AC-010 (event-driven)
GIVEN a soft-deleted account whose `deleted_at` is older than the configured retention window
WHEN the scheduled `AccountPurgeJob` runs
THEN the system SHALL permanently delete that account's row
VERIFY: test: spec/jobs/account_purge_job_spec.rb#purges_after_retention_window

### AC-011 (event-driven)
GIVEN a compliance erasure request for an account still within its retention window
WHEN an authorized compliance operator invokes the hard-purge escape hatch
THEN the system SHALL permanently delete that account's row immediately
VERIFY: test: spec/services/compliance/account_purge_service_spec.rb#immediate_purge_bypasses_retention_window

### AC-012 (unwanted-behavior)
IF `destroy` is invoked on an account that is already soft-deleted
THEN the system SHALL no-op without changing the existing `deleted_at` timestamp
VERIFY: test: spec/models/account_spec.rb#double_destroy_is_idempotent

### AC-013 (state-driven)
GIVEN the account is soft-deleted (`deleted_at` present)
THEN the system SHALL reject attempts to create new `subscriptions`, `users`, or `api_keys` for that account
VERIFY: test: spec/models/account_spec.rb#blocks_new_dependents_while_soft_deleted

### AC-014 (optional-feature)
GIVEN the `hard_purge_escape_hatch` permission is enabled for an operator's role
THEN the system SHALL expose the hard-purge action in the admin UI for that operator
VERIFY: test: spec/requests/admin/accounts_spec.rb#hard_purge_action_gated_by_permission

## Confidence

`ramza-score --rubric confidence`: 83.5% → VALIDATE (human reviews before proceeding).
Dims: pattern_match 88 (soft-delete-via-destroy-override is a heavily precedented
Rails pattern), requirement_clarity 74 (the deliverable was clear; the domain has
genuine open cross-team decisions — Finance/invoices, Billing/email-reuse,
Security/key-revocation — that this spec surfaces but cannot resolve unilaterally),
decomposition_stability 82, constraint_compliance 90.

## Rejected Alternatives

- **Adopt the `discard` gem verbatim** (`ramza-score --rubric explore` total 70.5,
  solid) — alignment 7, correctness 8, maintainability 7, performance 8,
  simplicity 7, risk 6, innovation 3. Rejected because `discard` deliberately does
  **not** override `destroy` — it adds a separate `discard!` method, so every
  existing call site (Admin destroy action, `Support::AccountClosureService`,
  the Billing sweeper) would need to be found and rewritten to call `discard!`
  instead of `destroy`, or accounts keep hard-deleting through the untouched
  `destroy` path. That call-site migration burden is exactly the kind of
  ceremony this mature app's blast radius makes risky, and it scored lower
  than the override approach primarily on `alignment` (7 vs. 9) for that reason,
  despite otherwise-comparable engineering quality. Its total (70.5) sits within
  ~4% of the winning hypothesis's 73.5 — the tie-break was `alignment`
  (preserving other teams' existing call-site behavior unmodified is the
  mission's central ask) plus zero added external dependency on a core, widely
  depended-on model.

- **Explicit `soft_delete!` method, `destroy` left untouched** (in-house,
  no gem) — total 69, **weak** (below the 70 solid floor; dropped, not reworked).
  alignment 6, correctness 8, maintainability 8, performance 8, simplicity 7,
  risk 6, innovation 2. Same call-site-migration problem as the `discard` gem
  (rejected above) without even the benefit of an externally maintained,
  community-tested implementation — every call site still needs discovery and
  rewrite, and any site missed keeps silently hard-deleting.

- **State-machine column + service object with manual `run_callbacks(:destroy)`,
  decoupled from AR's `destroy` entirely** — total 62, **weak** (dropped).
  alignment 8, correctness 6, maintainability 5, performance 7, simplicity 4,
  risk 4, innovation 8. Highest innovation score of the four, and it does
  sidestep overriding a core AR verb — but manually re-invoking the callback
  chain outside of `destroy`'s own transaction/error-handling machinery
  reimplements semantics ActiveRecord already gives for free (transaction
  wrapping, `:abort` throw handling from callbacks like
  `cancel_pending_invoices!`), and correctness/maintainability/simplicity all
  suffered for it. Genuinely distinct from the other three (not a strawman —
  it was the only hypothesis that didn't touch `destroy` at all), but the
  reimplementation risk was judged not worth the innovation.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| `dependent: :destroy` still hard-deletes children (subscriptions/users/api_keys) unless they too become soft-deletable — a restored Account with no children is not a useful restore | P0 | AC-007 cascades soft-delete to first-order dependents in the same transaction; `invoices` explicitly excluded pending Finance (AC-008) |
| DB-level unique constraints on email/slug still block reuse of a soft-deleted identity even though the row is hidden by `default_scope` | P0 | AC-009 converts to a Postgres partial unique index + matching validation scope; if the real backend is MySQL (Assumptions), fall back to validation-layer-only enforcement and flag the gap explicitly in code review |
| A dependent team's callback silently assumes the row is truly gone (e.g., a `COUNT(*)` that doesn't account for `default_scope`, or an external system expecting a terminal "deleted" state) | P1 | Impact Assessment rows 3, 4, 7, 8, 12 are explicit open decisions requiring sign-off from Support, Billing, Data, and Security before merge — tracked outside RAMZA's authority as a human coordination step |
| Retention/hard-purge job failure leaves PII indefinitely, undermining the compliance rationale for this spec | P0 | Alert on `AccountPurgeJob` failure rate; the hard-purge escape hatch (AC-011) is an operator-triggerable backstop independent of the scheduled job |
| Restoring an account does not reverse irreversible `after_destroy` side effects already fired (external billing deprovision call, Kafka analytics-purge event) | P1 | Documented per-callback in Impact Assessment rows 7–8; Restore UI must surface a warning that these side effects are not automatically undone |
| `default_scope` adds a `WHERE deleted_at IS NULL` to every Account query; unindexed, this degrades at scale on a "mature" (large) accounts table | P2 | Add an index on `deleted_at` (composite with identity columns where used in lookups) as part of the same migration; verify via `EXPLAIN` in code review |
| This spec's Impact Assessment is representative, not verified against a real repo (Assumptions) | P1 | Story 1's first task is the mechanical call-site audit that reconciles this table with reality before implementation proceeds |

---

## Audit trail

All commands below were run for real against the installed `.eidolons/ramza/bin/*`
tools in the project directory
`/home/rynaro/.claude/jobs/0e28f40c/tmp/ac003-wave2/proj-ramza-AB-T2-r1`.
Output is quoted verbatim (no paraphrase, no fabrication); the full state file
is reproduced at the end.

### RS — Right-size

```
$ bash .eidolons/ramza/bin/ramza-rightsize --files-est 10 --migration --security --stakes high \
    --plan account-soft-delete --state .spectra/plans/account-soft-delete.state.json
state initialised: .spectra/plans/account-soft-delete.state.json (tier: full, score: 6)
full
```

Score derivation (mechanical, per `ramza-rightsize --help`): files-est ≥10 → 2,
`--migration` → +1, `--security` → +1, `--stakes high` → +2 = **6 → full**.
`--security` was flagged because the spec includes a genuine compliance
boundary (retention window + GDPR/CCPA hard-purge escape hatch, AC-010/AC-011);
`--new-dep`/`--public-api`/`--novel` were deliberately left unset — no new
external dependency was committed to before Explore, and this isn't a public
API surface change or a novel technique.

### S — Scope

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to S
OK: RS -> S

$ echo '{"scope":2,"ambiguity":1,"dependencies":3,"risk":3}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric complexity --state .spectra/plans/account-soft-delete.state.json --label "scope-complexity"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "complexity",
  "total": 9,
  "dims": {
    "scope": 2,
    "ambiguity": 1,
    "dependencies": 3,
    "risk": 3
  },
  "verdict": "extended",
  "at": "2026-07-05T19:24:51Z",
  "label": "scope-complexity"
}
```

### P — Pattern

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to P
OK: S -> P
```

No `mcp__crystalium__*` tools were available in this environment (checked the
active tool list before proceeding). Per `agent.md`/`skills/methodology.md`,
"If `mcp__crystalium__*` tools are unavailable, skip silently — RAMZA is
EIIS-standalone-conformant." Pattern is judgment-only (no tool gate); the
override-destroy shape was recognized as the `paranoia`-gem-equivalent pattern
directly from domain knowledge of Rails soft-delete conventions, with the
`discard`-gem shape surfaced as the documented pattern alternative in Explore.

### E — Explore

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to E
OK: P -> E

$ echo '{"alignment":9,"correctness":8,"maintainability":6,"performance":7,"simplicity":8,"risk":6,"innovation":3}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/account-soft-delete.state.json --label "hyp-A-override-destroy"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore", "total": 73.5,
  "dims": {"alignment":9,"correctness":8,"maintainability":6,"performance":7,"simplicity":8,"risk":6,"innovation":3},
  "verdict": "solid", "at": "2026-07-05T19:25:12Z", "label": "hyp-A-override-destroy"
}

$ echo '{"alignment":6,"correctness":8,"maintainability":8,"performance":8,"simplicity":7,"risk":6,"innovation":2}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/account-soft-delete.state.json --label "hyp-B-explicit-method"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore", "total": 69,
  "dims": {"alignment":6,"correctness":8,"maintainability":8,"performance":8,"simplicity":7,"risk":6,"innovation":2},
  "verdict": "weak", "at": "2026-07-05T19:25:12Z", "label": "hyp-B-explicit-method"
}
(exit 1 — tool-enforced "weak" verdict; command chain halted here as designed,
 hyp-C and hyp-D re-run as separate calls below)

$ echo '{"alignment":7,"correctness":8,"maintainability":7,"performance":8,"simplicity":7,"risk":6,"innovation":3}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/account-soft-delete.state.json --label "hyp-C-discard-gem"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore", "total": 70.5,
  "dims": {"alignment":7,"correctness":8,"maintainability":7,"performance":8,"simplicity":7,"risk":6,"innovation":3},
  "verdict": "solid", "at": "2026-07-05T19:25:22Z", "label": "hyp-C-discard-gem"
}

$ echo '{"alignment":8,"correctness":6,"maintainability":5,"performance":7,"simplicity":4,"risk":4,"innovation":8}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric explore --state .spectra/plans/account-soft-delete.state.json --label "hyp-D-service-object"
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "explore", "total": 62,
  "dims": {"alignment":8,"correctness":6,"maintainability":5,"performance":7,"simplicity":4,"risk":4,"innovation":8},
  "verdict": "weak", "at": "2026-07-05T19:25:27Z", "label": "hyp-D-service-object"
}
```

Result: 2 solid (hyp-A 73.5, hyp-C 70.5), 2 weak/dropped (hyp-B 69, hyp-D 62).
hyp-A (override `destroy`, in-house) selected as the winning Approach; the
other three carried forward as Rejected Alternatives (3, exceeding the "at
least one" requirement). hyp-A and hyp-C sit within ~4% of each other — see
"Rejected Alternatives" above for the explicit tie-break rationale
(alignment sub-score + zero new dependency), recorded rather than silently
picking the higher number.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to C
OK: E -> C
```

### C — Construct

Plan authored to `.spectra/plans/account-soft-delete.md` and acceptance
criteria to the sibling `.spectra/plans/account-soft-delete.acceptance.md`
(content above). EARS-lint iterated once before the file was considered draft-
complete — the first pass on the acceptance file caught 4 ubiquitous/optional-
feature blocks missing a literal `THEN` line:

```
$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/account-soft-delete.acceptance.md
AC-002: missing THEN
AC-003: missing THEN
AC-009: missing THEN
AC-014: missing THEN
exit: 1
```

Fixed (added the required `THEN` prefix to each ubiquitous/optional-feature
assertion line — the template's own worked examples show `THEN` is required
even for forms without a WHEN trigger), then re-run clean:

```
$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/account-soft-delete.acceptance.md
ok: 14 criteria pass EARS lint
exit: 0
```

### T — Test

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to T
OK: C -> T

$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/account-soft-delete.md --state .spectra/plans/account-soft-delete.state.json
ok: plan passes structural lint (tier: full)
lint exit: 0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/account-soft-delete.md
ok: 14 criteria pass EARS lint
ears exit: 0
```

**Independent critic (maker≠checker, mandatory at tier=full).** Exactly one
clean-context critic subagent was spawned (general-purpose Agent, no memory of
this authoring session) and given only the three artifacts named in
`skills/critic.md` §Inputs — the plan, the acceptance-criteria file, and the
state file — by absolute path, with instructions to run the mechanical checks
itself, score independently, and record the critic identities. Its full
return value, verbatim:

```
## Verdict

ok: plan passes structural lint (tier: full)
EXIT:0

ok: 14 criteria pass EARS lint
EXIT:0

{
  "rubric": "refine",
  "cycle": 1,
  "total": 3.4,
  "min": 3,
  "dims": {
    "clarity": 4,
    "completeness": 3,
    "actionability": 3,
    "efficiency": 4,
    "testability": 3
  },
  "verdict": "pass",
  "at": "2026-07-05T19:34:22Z"
}

OK: critic recorded (author: ramza-planner-session, checker: ramza-critic-agent)
EXIT:0

## Critique — account-soft-delete

**Verdict:** ramza-lint clean · ramza-ears-lint clean (14/14) · refine rubric: pass (total 3.4, cycle 1)

**Findings**
- clarity (4/5): Approach and Impact Assessment are precise and well-grounded, but AC-001's GIVEN clause introduces "an Account with no active holds" — "holds" is never defined or referenced anywhere else in Scope, Risks, or Approach, leaving a dangling undefined term in the plan's first acceptance criterion.
- completeness (3/5): AC-007, AC-008, AC-012, and AC-013 are never explicitly assigned to a Story in the Stories section — Story 1's prose ("Landmine 1") implies it owns the AC-007 cascade, but the mapping is inferred, not stated. AC-013 also drops `users` from the cascade-blocking rule despite AC-007 treating `subscriptions`/`users`/`api_keys` as a uniform cascade set, with no stated reason for the asymmetry.
- actionability (3/5): The Impact Assessment's per-row "Required action" column is genuinely decision-ready, but the missing AC↔Story traceability (see completeness) means an executor picking up Story 1 or Story 2 has to guess which acceptance criteria they're on the hook for.
- efficiency (4/5): Timeboxes are broadly proportionate to the extended complexity score (9/12), and the Rejected Alternatives section is appropriately concise without re-litigating settled ground. Story 2's 5-day box bundles cross-team sign-off elapsed time from four teams (Support, Billing, Data, Security) into a fixed timebox — optimistic given how many open decisions (rows 3, 4, 7, 8, 12) that story is gating on.
- testability (3/5): 13 of 14 criteria are concretely testable with named spec files. AC-001 is not, as written — a test author cannot construct a fixture for "no active holds" without a definition of what a hold is or how it's represented on the model. AC-013's omission of `users` also means the cascade-symmetric behavior for that association has no corresponding negative-path test.

**Prescriptions**
1. AC-001 — Either define "active holds" (what field/state it maps to, e.g. a legal-hold flag) somewhere in Scope/Approach, or remove the qualifying GIVEN clause if no such concept exists in this system.
2. AC-013 — Add `users` to the blocked-creation list (`account.users.create` while soft-deleted) to match AC-007's uniform treatment of the three cascade associations, or add a one-line rationale in Risks/Approach for why `users` is intentionally excluded.
3. Stories section — Add an explicit AC-to-Story mapping (e.g., a small table or inline "(AC-007, AC-008, AC-012)" tags per story) so AC-007, AC-008, AC-012, and AC-013 each have a named owning story instead of being inferable only from Approach prose.
4. Story 2 — Split the fixed elapsed-time assumption out of the 5d code timebox: timebox the engineering checklist work separately from the cross-team sign-off wait, since sign-off latency across four teams is not under this plan's control and conflating the two risks misreporting story velocity.
```

**Disposition of the critique.** Verdict was **pass** (3.4/5, all dims ≥3,
cycle 1) — the tier=full gate requirement (a recorded critic before Assemble)
was satisfied by this session alone; `ramza-gate critic` recorded
`author: ramza-planner-session`, `checker: ramza-critic-agent` (mechanically
distinct identities, confirmed in the state file below). All four
prescriptions were nonetheless genuine and cheap, so they were applied
directly as pre-Assemble polish rather than reworked through a formal
`ramza-gate refine` cycle: a second scored cycle would have had to be either
(a) self-scored by the author, which breaks maker≠checker for the refine
rubric itself, or (b) run by a second critic session, which the task
constraints cap at exactly one. Applied fixes:

1. AC-001's `GIVEN` changed from "an Account with no active holds" (undefined
   term) to "an existing, persisted Account".
2. AC-013 now blocks new `subscriptions`, `users`, **and** `api_keys` (added
   `users`, matching AC-007's uniform three-association cascade set).
3. Each Story now carries an explicit "Acceptance criteria owned:" line
   (Story 1: AC-001/002/003/007/012/013; Story 2: AC-008; Story 3:
   AC-004/005/006/014; Story 4: AC-010/011; Story 5: AC-009).
4. Story 2's timebox split into "2d engineering" (the checklist/sign-off-
   capture work itself) plus explicitly-called-out untracked elapsed wait time
   for the four teams' responses, instead of one fixed 5d box conflating both.

Re-verified clean after the edits:

```
$ bash .eidolons/ramza/bin/ramza-lint --plan .spectra/plans/account-soft-delete.md --state .spectra/plans/account-soft-delete.state.json
ok: plan passes structural lint (tier: full)
lint exit: 0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/account-soft-delete.md
ok: 14 criteria pass EARS lint
ears(plan) exit: 0

$ bash .eidolons/ramza/bin/ramza-ears-lint .spectra/plans/account-soft-delete.acceptance.md
ok: 14 criteria pass EARS lint
ears(acceptance) exit: 0

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/account-soft-delete.state.json
{
  "plan": "account-soft-delete",
  "tier": "full",
  "phase": "T",
  "next": "A",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": false
}
```

`refine_cycles: 0` — the critic's pass verdict meant no gate-tracked Refine
cycle was required; the four fixes above were incorporated as direct T-phase
polish before the Assemble transition, not as a counted cycle.

### A — Assemble

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to A
OK: T -> A

$ echo '{"pattern_match":88,"requirement_clarity":74,"decomposition_stability":82,"constraint_compliance":90}' \
  | bash .eidolons/ramza/bin/ramza-score --rubric confidence --state .spectra/plans/account-soft-delete.state.json
calibration log appended: .spectra/plans/ramza-calibration.jsonl
{
  "rubric": "confidence", "total": 83.5,
  "dims": {"pattern_match":88,"requirement_clarity":74,"decomposition_stability":82,"constraint_compliance":90},
  "verdict": "VALIDATE", "at": "2026-07-05T19:36:49Z"
}

$ bash .eidolons/ramza/bin/ramza-drift --state .spectra/plans/account-soft-delete.state.json \
    --declare 'app/models/account.rb app/models/concerns/soft_deletable.rb app/models/subscription.rb app/models/user.rb app/models/api_key.rb app/controllers/admin/accounts_controller.rb app/views/admin/accounts/* app/jobs/account_purge_job.rb app/services/compliance/account_purge_service.rb app/models/restore_audit.rb db/migrate/* spec/models/account_spec.rb spec/requests/admin/accounts_spec.rb spec/jobs/account_purge_job_spec.rb spec/services/compliance/account_purge_service_spec.rb config/permissions.rb'
scope declared: 16 glob(s)

$ bash .eidolons/ramza/bin/ramza-freeze --state .spectra/plans/account-soft-delete.state.json --criteria .spectra/plans/account-soft-delete.acceptance.md
frozen: 9ca6d2e3f7d6e0808e8002d0536b8367b689d7dcee19943905d0afd3e6f52d4e
9ca6d2e3f7d6e0808e8002d0536b8367b689d7dcee19943905d0afd3e6f52d4e

$ bash .eidolons/ramza/bin/ramza-verify-emit --spec .spectra/plans/account-soft-delete.md --envelope .spectra/plans/account-soft-delete.envelope.json
ok: emission gate passed (account-soft-delete.md + envelope)
verify-emit exit: 0
```

ECL envelope emitted (ECL_VERSION=2.0 present in the install root) at
`.spectra/plans/account-soft-delete.envelope.json`: `performative: PROPOSE`,
`from.eidolon: ramza`, `to.eidolon: apivr`, `edge_origin: roster`,
`artifact.sha256`/`integrity.value` both
`e1a0905d00063ecf0bba76df2ecd7cf052403cd7f5b84161d0cf9ec8148f4f7d` (sha256 of
the final `account-soft-delete.md` bytes, 24613 bytes), `ise.assertion_grade:
self-attested`, `x_ramza_acceptance_criteria.sha256` matching the freeze hash
above — all confirmed by the `verify-emit` pass, not asserted independently.

```
$ bash .eidolons/ramza/bin/ramza-gate advance --state .spectra/plans/account-soft-delete.state.json --to DONE
OK: A -> DONE

$ bash .eidolons/ramza/bin/ramza-gate status --state .spectra/plans/account-soft-delete.state.json
{
  "plan": "account-soft-delete",
  "tier": "full",
  "phase": "DONE",
  "next": "DONE",
  "refine_cycles": 0,
  "skips": [],
  "criteria_frozen": true
}

$ bash .eidolons/ramza/bin/ramza-adherence --state .spectra/plans/account-soft-delete.state.json
{
  "plan_phase": 1,
  "plan_order": 1,
  "plan_fidelity": null,
  "composite": 1,
  "inputs": {
    "tier": "full",
    "phases_done": ["RS","S","P","E","C","T","A","DONE"],
    "refine_cycles": 0,
    "skips": 0,
    "drift_range": null
  },
  "at": "2026-07-05T19:37:45Z"
}
```

`plan_phase: 1` (every mandatory full-tier phase entered, zero silent skips),
`plan_order: 1` (no refine-cycle penalty — 0 cycles used against a cap of 3),
`plan_fidelity: null` (no execution has happened yet against the declared
scope — expected pre-handoff, per `ramza-adherence`'s own definition),
composite `1` (geometric mean of the available components). CRYSTALIUM
`ingest`/`session_end` calls were skipped: no `mcp__crystalium__*` tools were
present in this environment, and both are documented graceful no-ops when
absent.

### Final state file (`.spectra/plans/account-soft-delete.state.json`)

```json
{
  "schema": "ramza/plan-state.v1",
  "plan": "account-soft-delete",
  "created_at": "2026-07-05T19:24:33Z",
  "tier": "full",
  "phase": "DONE",
  "phases_done": ["RS", "S", "P", "E", "C", "T", "A", "DONE"],
  "rightsize": {
    "score": 6,
    "computed_tier": "full",
    "inputs": {
      "files_est": 10, "new_dep": false, "public_api": false,
      "migration": true, "security": true, "novel": false, "stakes": "high"
    }
  },
  "refine_cycles": 0,
  "skips": [],
  "gates": [
    {"rubric":"complexity","total":9,"dims":{"scope":2,"ambiguity":1,"dependencies":3,"risk":3},"verdict":"extended","at":"2026-07-05T19:24:51Z","label":"scope-complexity"},
    {"rubric":"explore","total":73.5,"dims":{"alignment":9,"correctness":8,"maintainability":6,"performance":7,"simplicity":8,"risk":6,"innovation":3},"verdict":"solid","at":"2026-07-05T19:25:12Z","label":"hyp-A-override-destroy"},
    {"rubric":"explore","total":69,"dims":{"alignment":6,"correctness":8,"maintainability":8,"performance":8,"simplicity":7,"risk":6,"innovation":2},"verdict":"weak","at":"2026-07-05T19:25:12Z","label":"hyp-B-explicit-method"},
    {"rubric":"explore","total":70.5,"dims":{"alignment":7,"correctness":8,"maintainability":7,"performance":8,"simplicity":7,"risk":6,"innovation":3},"verdict":"solid","at":"2026-07-05T19:25:22Z","label":"hyp-C-discard-gem"},
    {"rubric":"explore","total":62,"dims":{"alignment":8,"correctness":6,"maintainability":5,"performance":7,"simplicity":4,"risk":4,"innovation":8},"verdict":"weak","at":"2026-07-05T19:25:27Z","label":"hyp-D-service-object"},
    {"rubric":"refine","cycle":1,"total":3.4,"min":3,"dims":{"clarity":4,"completeness":3,"actionability":3,"efficiency":4,"testability":3},"verdict":"pass","at":"2026-07-05T19:34:22Z"},
    {"rubric":"confidence","total":83.5,"dims":{"pattern_match":88,"requirement_clarity":74,"decomposition_stability":82,"constraint_compliance":90},"verdict":"VALIDATE","at":"2026-07-05T19:36:49Z"}
  ],
  "amendments": [],
  "declared_scope": [
    "app/models/account.rb","app/models/concerns/soft_deletable.rb","app/models/subscription.rb",
    "app/models/user.rb","app/models/api_key.rb","app/controllers/admin/accounts_controller.rb",
    "app/views/admin/accounts/*","app/jobs/account_purge_job.rb",
    "app/services/compliance/account_purge_service.rb","app/models/restore_audit.rb","db/migrate/*",
    "spec/models/account_spec.rb","spec/requests/admin/accounts_spec.rb",
    "spec/jobs/account_purge_job_spec.rb","spec/services/compliance/account_purge_service_spec.rb",
    "config/permissions.rb"
  ],
  "criteria_sha256": "9ca6d2e3f7d6e0808e8002d0536b8367b689d7dcee19943905d0afd3e6f52d4e",
  "critic": {"author": "ramza-planner-session", "checker": "ramza-critic-agent", "at": "2026-07-05T19:34:32Z"},
  "scope_declared_at": "2026-07-05T19:36:57Z",
  "criteria_frozen_at": "2026-07-05T19:37:03Z",
  "adherence_reports": [
    {"plan_phase":1,"plan_order":1,"plan_fidelity":null,"composite":1,
     "inputs":{"tier":"full","phases_done":["RS","S","P","E","C","T","A","DONE"],"refine_cycles":0,"skips":0,"drift_range":null},
     "at":"2026-07-05T19:37:45Z"}
  ]
}
```

### Preflight checklist (per `docs/methodology/SPEC.md`)

- [x] RS ran; tier recorded (full, score 6, no override needed)
- [x] Phase walk clean in state (`ramza-gate status` — RS→S→P→E→C→T→A→DONE, zero unexplained skips)
- [x] Hypotheses scored via tool (4 scored: 2 solid, 2 weak); rejected alternatives documented (3)
- [x] `ramza-lint` + `ramza-ears-lint` green (plan and acceptance file both)
- [x] Full tier: critic recorded (author `ramza-planner-session` ≠ checker `ramza-critic-agent`)
- [x] Confidence computed via tool (83.5% → VALIDATE); verdict honored (this spec is presented for human validation, not auto-proceed)
- [x] Scope declared (16 globs); criteria frozen (sha256 above); `ramza-verify-emit` green
- [x] Every output path under `.spectra/`; no code produced
