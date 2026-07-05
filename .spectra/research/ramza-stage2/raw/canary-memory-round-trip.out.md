# RAMZA canary mission — memory round-trip (rate-limiting middleware)

**READ-ONLY constraint.** This mission ran under RAMZA's hard P0: no code, no
file edits outside `.spectra/`, no mutations to the consumer project. Every
gate below was executed for real via `.eidolons/ramza/bin/ramza-*` from
`/tmp/ramza-e2e` against `.spectra/plans/can-memrt.*`. Slug: **`can-memrt`**.

**Feature under plan:** add a rate-limiting middleware to a REST API,
capping requests per IP at 100/min. Stack: Node.js/TypeScript, Express, no
existing rate limiting, Redis available, ~2–3 files touched, one new
dependency (rate-limit library), stakes low-to-medium.

## CRYSTALIUM tool-availability check

Before anything else, checked honestly whether `mcp__crystalium__*` tools are
reachable in this session: searched the deferred-tool index (`ToolSearch`)
for `crystalium`, `memory recall ingest`, `crystalium recall ingest
session_end` — **zero matches**, against a control query (`memory recall
ingest`) that *did* resolve unrelated tools, confirming the search itself
works and the absence is real, not a query miss. **No `mcp__crystalium__*`
tools are present in this environment.** Every memory-hook call site below is
therefore a documented graceful skip, per `skills/methodology.md` ("If
`mcp__crystalium__*` tools are unavailable, skip silently — RAMZA is
EIIS-standalone-conformant and works without CRYSTALIUM") — rendered here
non-silently, as an explicit note, for canary auditability.

## Memory pre-flight (before Scope)

Per `skills/verify-incoming.md`'s recall call signature and this mission's
explicit instruction, the pre-flight recall was attempted **before opening
Scope**, immediately after Right-Size:

```
mcp__crystalium__recall(
  scope  = { project: "test-project", agent_class_visibility: "ramza" },
  query  = "rate limiting middleware Node.js Express Redis",
  k      = 5,
  layers = ["semantic", "episodic", "procedural"]
)
```

**CRYSTALIUM absent — memory hooks skipped.** No prior semantic/episodic/
procedural context was folded in; Scope and Pattern below proceed on the
mission's stated assumptions and a direct codebase check alone, with that
gap recorded rather than papered over.

## RS — Right-Size

```
ramza-rightsize --files-est 3 --new-dep --security --stakes med \
  --plan can-memrt --state .spectra/plans/can-memrt.state.json
```
Output:
```
state initialised: .spectra/plans/can-memrt.state.json (tier: lite, score: 4)
lite
```
Score arithmetic, mechanical: `--files-est 3` (3–9 band) contributes 1;
`--new-dep` (the mission's stated "one new dependency") contributes 1;
`--security` contributes 1 — rate limiting is treated as a security-adjacent
control (anti-abuse/anti-DoS), not merely a performance knob, so the flag is
set; `--stakes med` (the mission's "low-to-medium" resolved to the tool's
discrete med value, the more conservative of the two, given the security
flag already in play) contributes 1. `--public-api`, `--migration`,
`--novel` are unset (no new route surface, no migration, a well-known
pattern). Total score 4 → **lite** (2–4 band). Tier drives the rest of the
cycle: mandatory gate-enforced phases `RS S P E C T A`, ≥3 scored hypotheses
at Explore, and required plan sections Scope/Approach/Stories/Confidence/
Acceptance Criteria (Rejected Alternatives/Risks are full-tier-only but are
included below anyway, since Explore already produces rejected hypotheses
worth recording).

## S — Scope

`ramza-gate advance --state .spectra/plans/can-memrt.state.json --to S` →
`OK: RS -> S`.

Intent class **REQUEST**. In: one Redis-backed rate limiter capping each
client IP to 100 requests per rolling 60s window, mounted globally on the
API, 429 + `RateLimit-Remaining` header on exhaustion. Out: per-route/
per-user limits, allowlists, hot-reload config, a limiter dashboard.
Deferred: tiered limits and a sliding-window upgrade. Assumptions: Redis
reachable at the address already used elsewhere (risk: a new connection
string would move this to 4 files); no existing limiter (risk: double
enforcement — checked directly, see Pattern below); Redis-outage behavior
resolves to **fail open** (risk: if the real threat model wants fail-closed,
AC-004 flips polarity — flagged explicitly since the mission left this
unstated).

Complexity score, run for real:
```
echo '{"scope":2,"ambiguity":1,"dependencies":2,"risk":2}' \
  | ramza-score --rubric complexity --state .spectra/plans/can-memrt.state.json --label scope-complexity
```
Result: `total: 7` → **extended** (7–9 band) — driven by the Redis dependency
and global cross-cutting middleware, not by requirement ambiguity (which
scored the floor, 1).

## P — Pattern

CRYSTALIUM recall was already attempted (and skipped) at the pre-flight
above, per this mission's instruction to demonstrate it before Scope rather
than at the phase where `SPEC.md` normally places it. At Pattern proper, a
direct codebase check stands in for the missing memory-tool recall (no
dedicated `ramza-*` tool exists for Pattern — it is judgment, not
arithmetic):

```
grep -rn "rate.limit\|express-rate-limit\|rate-limiter" src/ 2>/dev/null
find . -iname "*rate*" -not -path "./.git/*" -not -path "./.spectra/*"
```
Zero application matches (only an unrelated `ramza-calibrate` binary path
matched the glob) — confirms the mission's "no existing rate limiting"
assumption rather than contradicting it. No ≥85%-match template and no
in-repo anti-pattern to surface; the pattern used below (`express-rate-limit`
+ Redis store) comes from general knowledge, not a recalled prior spec.

`ramza-gate advance --state .spectra/plans/can-memrt.state.json --to P` →
`OK: S -> P` (mandatory at lite, no `--reason` needed).

## E — Explore

`ramza-gate advance --state .spectra/plans/can-memrt.state.json --to E` →
`OK: P -> E`. Lite tier mandates 3 hypotheses; three genuinely distinct ones
were scored via `ramza-score --rubric explore --state <state> --label
<hyp>`, each a real tool call:

- **Hyp-A — `express-rate-limit` + `rate-limit-redis` store** (conservative,
  pattern-standard): `{alignment 9, correctness 9, maintainability 9,
  performance 8, simplicity 9, risk 8, innovation 3}` →
  **total 84.5, verdict `solid`**.
- **Hyp-B — `rate-limiter-flexible`'s `RateLimiterRedis`, hand-wired into
  Express** (pattern-leveraging, more precise algorithm): `{alignment 7,
  correctness 8, maintainability 7, performance 8, simplicity 5, risk 7,
  innovation 6}` → **total 71, verdict `solid`**.
- **Hyp-C — hand-rolled Redis `INCR`+`EXPIRE` counter, zero new dependency**
  (innovative, contradicts the mission's own "one new dependency"
  assumption): `{alignment 4, correctness 5, maintainability 5, performance
  7, simplicity 6, risk 3, innovation 8}` → **total 51, verdict `weak`** —
  the tool itself exits 1 on `weak`, mechanically flagging rejection rather
  than leaving it to prose.

Spread A→C is 33.5 points (≫5%), so differentiation is real — no
re-observation required. **Hyp-A wins** (highest score, still consistent
with the stated one-new-dependency, 2–3-file assumptions); carried forward
into Approach, with B and C recorded under Rejected Alternatives.

`ramza-gate advance --state .spectra/plans/can-memrt.state.json --to C` →
`OK: E -> C`.

## C — Construct → the spec

Full plan authored at `.spectra/plans/can-memrt.md`:

```markdown
---
eidolon: ramza
kind: spec
version: 0.1.0
created_at: 2026-07-05T13:08:59Z
plan: can-memrt
tier: lite
status: ready-for-apivr
---

# Add rate-limiting middleware to cap requests per IP at 100/min

## Scope

Intent class: REQUEST
In: a single Express middleware, mounted globally on the REST API, that caps
each client IP to 100 requests per rolling 60-second window, backed by Redis
as the shared counter store (required for correctness across multiple API
process instances), returning HTTP 429 with a `RateLimit-Remaining` header
once an IP's budget is exhausted.
Out: per-route or per-endpoint differentiated limits, per-user/per-API-key
limiting, a global admin bypass/allowlist, distributed configuration hot-reload,
and any UI/dashboard for observing current limit state.
Deferred: tiered limits (e.g. authenticated users get a higher cap) and a
sliding-window-precise algorithm upgrade — both postponed until a concrete
need (an abusive-traffic incident or a paid-tier launch) actually requires
them; the fixed/rolling window `express-rate-limit` provides today is
sufficient for the stated 100/min cap.
Assumptions:
- Redis is reachable from the API process at the same address already used
  for other caching, per the mission's stated "Redis available" — risk if
  wrong: the middleware's Redis client config would need a new connection
  string, moving this from a 3-file to a 4-file change.
- No existing rate-limiting code exists in the API (mission-stated) — risk if
  wrong: a second limiter stacking on top of this one would double-enforce
  and could produce confusing 429s; mitigated by the codebase grep run during
  Pattern (see below), which found zero existing matches.
- On Redis outage, failing open (allowing the request through, logging a
  warning) is preferable to failing closed (blocking all traffic) for this
  anti-abuse, non-critical-security control — risk if wrong: if this API's
  actual threat model requires fail-closed (e.g. a compliance-driven hard
  cap), AC-004 would need to flip polarity; flagged explicitly in Risks below
  since the mission did not state a preference either way.

Complexity (`ramza-score --rubric complexity`): 7/12 → **extended** (scope 2,
ambiguity 1, dependencies 2, risk 2 — driven by the Redis dependency and the
cross-cutting nature of global middleware, not by requirement ambiguity,
which was low).

## Approach

Selected: **Hyp-A — `express-rate-limit` + `rate-limit-redis` store**
(`ramza-score --rubric explore` total 84.5 → solid; see Rejected
Alternatives for the two hypotheses that lost). Add the `express-rate-limit`
package (the one new dependency named in the mission's assumptions) configured
with a `RedisStore` (from `rate-limit-redis`) pointed at the existing Redis
client/connection, `windowMs: 60_000`, `limit: 100`, keyed by `req.ip`.
Mount it as global middleware early in the Express middleware chain (before
route handlers, after body-parsing/trust-proxy setup) in the app's entrypoint
file. On Redis errors, configure the store's `passOnError` behavior (or an
equivalent try/catch around the store call) to fail open per the Scope
assumption above (AC-004). No new file is strictly required for a minimal
version (the limiter can be constructed inline in the entrypoint), but a
dedicated `middleware/rateLimiter.ts` module is used instead to keep the
entrypoint diff small and to give the limiter a single testable unit —
holding total files touched at 3: the new middleware module, the entrypoint
mount-point edit, and `package.json`/lockfile for the new dependency,
matching the RS `--files-est 3` input.

## Stories

### Story 1: Implement the Redis-backed rate limiter module

As an API operator, I want a reusable rate-limiting middleware backed by
Redis, so that the limit is enforced consistently across all API process
instances sharing the same Redis store.

Timebox: 1d.
Risk tag: P1 (introduces a new runtime dependency and a new failure mode —
Redis unavailability — that must degrade safely rather than 500).
Executor hint: mid tier (Sonnet-class) — file-level action plan, named
pattern (`express-rate-limit` + `RedisStore`), explicit fail-open behavior
called out since it is a judgment call the mission left implicit.

Action plan: add `express-rate-limit` and `rate-limit-redis` to
`package.json` → create `middleware/rateLimiter.ts` exporting a configured
limiter (`windowMs: 60_000`, `limit: 100`, `keyGenerator: (req) => req.ip`,
`store: new RedisStore({ sendCommand: (...args) => redisClient.call(...args) })`)
→ wrap the store call so a Redis error logs a warning and allows the request
(fail open, per AC-004) instead of throwing.

### Story 2: Mount the limiter and define the 429 response contract

As an API consumer, I want a clear, consistent 429 response and rate-limit
headers when I exceed the cap, so that my client can back off and retry
correctly.

Timebox: 1d.
Risk tag: P2 (response-shape and header contract only; no new failure mode
beyond Story 1's).
Executor hint: mid tier (Sonnet-class) — file-level action plan, explicit
response-body contract given (no schema-validated payload needed at this
tier).

Action plan: mount the Story 1 middleware in the app entrypoint before route
handlers → set `standardHeaders: true` (or equivalent) so `RateLimit-Remaining`
rides every evaluated response (AC-003) → set a custom `handler` returning
HTTP 429 with `{"error":"rate_limit_exceeded"}` (AC-001) → confirm per-IP
isolation and window-rollover reset behaviorally against the Redis store
(AC-005, AC-006).

## Acceptance Criteria

Full EARS-form blocks (frozen at Assemble, hash below) live in
`.spectra/plans/can-memrt.criteria.md`; reproduced here for reviewer
convenience:

### AC-001 (event-driven)
GIVEN a client IP is within its current 60-second window
WHEN that IP sends its 101st request inside the window
THEN the middleware SHALL respond HTTP 429 with JSON body {"error":"rate_limit_exceeded"}
VERIFY: test: tests/rateLimiter.test.ts#blocks101stRequestWith429

### AC-002 (event-driven)
GIVEN a client IP has sent between 1 and 100 requests in the current window
WHEN that IP sends another request still inside the 100-request budget
THEN the middleware SHALL forward the request to the downstream route handler unmodified
VERIFY: test: tests/rateLimiter.test.ts#passesThroughUnderLimit

### AC-003 (ubiquitous)
THEN every response the middleware evaluates SHALL include a RateLimit-Remaining header reporting requests left in the current window
VERIFY: test: tests/rateLimiter.test.ts#exposesRemainingHeader

### AC-004 (unwanted-behavior)
GIVEN the Redis connection backing the rate-limit counter store is unreachable
WHEN a request arrives while Redis is down
THEN the middleware SHALL fail open and forward the request rather than returning HTTP 500
VERIFY: test: tests/rateLimiter.test.ts#failsOpenOnRedisOutage

### AC-005 (state-driven)
GIVEN one client IP has exhausted its 100-request budget in the current window
THEN the middleware SHALL continue accepting requests from a different client IP unaffected by the first IP's limit
VERIFY: test: tests/rateLimiter.test.ts#isolatesLimitsPerIp

### AC-006 (event-driven)
GIVEN a client IP was blocked after exceeding 100 requests in the prior window
WHEN the 60-second window elapses and that IP sends a new request
THEN the middleware SHALL reset the IP's counter and allow the request through
VERIFY: test: tests/rateLimiter.test.ts#resetsCounterOnWindowRollover

## Confidence

`ramza-score --rubric confidence`: 85.5% → AUTO_PROCEED
(pattern_match 82, requirement_clarity 88, decomposition_stability 85,
constraint_compliance 87 — this is an extremely common pattern with clearly
stated constraints; the only soft spots are the unstated fail-open/fail-closed
preference on Redis outage, RAMZA-authored above, and the fixed-vs-sliding
window algorithm choice, which the mission left to the implementer).

## Rejected Alternatives

- **Hyp-B — `rate-limiter-flexible`'s `RateLimiterRedis`, wired directly
  against Redis with a hand-built Express middleware wrapper** —
  `ramza-score --rubric explore` total 71 (solid, not the winner): scores
  well on innovation (6) and correctness (8) — it supports atomic Lua-script
  enforcement and more precise sliding-window semantics — but loses on
  simplicity (5) and alignment (7) because it requires hand-writing the
  Express adapter that `express-rate-limit` provides out of the box, pushing
  against the "~2-3 files" constraint. Worth revisiting if the sliding-window
  precision gap ever matters (e.g. burst-at-boundary abuse becomes a real
  incident).
- **Hyp-C — hand-rolled Redis `INCR`+`EXPIRE` counter with no new npm
  dependency** — total 51 (`ramza-score` exits 1 on the weak verdict,
  mechanically flagging it rather than leaving it to prose judgment).
  Directly contradicts the mission's own stated assumption of "one new
  dependency" (alignment 4) and the naive two-command form is not atomic
  without a `MULTI`/Lua wrapper, which is exactly the kind of race-condition
  risk (risk 3) that a maintained library exists to close. Rejected outright,
  not merely deferred — reinventing this primitive buys nothing here.

## Risks

| Risk | Tag | Mitigation |
|---|---|---|
| Redis outage during high traffic silently disables rate limiting (fail-open, per Scope assumption) rather than blocking traffic | P1 | AC-004 makes the fail-open choice an explicit, tested contract rather than an accidental side effect; flagged in Scope as a mission-unstated judgment call for APIVR-Δ/human review before merge |
| `req.ip` is unreliable behind a reverse proxy/load balancer unless Express `trust proxy` is configured correctly, which could collapse many real clients onto one IP (or vice versa) | P1 | Story 2's action plan calls out mounting after trust-proxy setup; APIVR-Δ should confirm the deployment's proxy topology before wiring `keyGenerator` |
| Fixed/rolling window (not sliding) allows a burst of up to ~200 requests across a window boundary | P2 | Accepted for this tier per Hyp-A's selection; documented in Deferred as a future sliding-window upgrade path |
```

## T — Test

Structural lint, run for real:
```
ramza-lint --plan .spectra/plans/can-memrt.md --state .spectra/plans/can-memrt.state.json
→ ok: plan passes structural lint (tier: lite)
```
EARS grammar lint, run for real against the frozen-criteria source file:
```
ramza-ears-lint .spectra/plans/can-memrt.criteria.md
→ ok: 6 criteria pass EARS lint
```
Both green on the first pass — no `ramza-gate refine` cycle was needed (0/3
used). `ramza-gate advance --state .spectra/plans/can-memrt.state.json --to
T` → `OK: C -> T`.

## A — Assemble

1. **Confidence**, run for real:
```
echo '{"pattern_match":82,"requirement_clarity":88,"decomposition_stability":85,"constraint_compliance":87}' \
  | ramza-score --rubric confidence --state .spectra/plans/can-memrt.state.json --label assemble-confidence
```
Result: `total: 85.5`, `verdict: "AUTO_PROCEED"` (≥85 band) — matches the
Confidence section above exactly, computed by the tool, not asserted in
prose. `ramza-gate advance --state .spectra/plans/can-memrt.state.json --to
A` → `OK: T -> A`.

2. **Declare scope**, run for real:
```
ramza-drift --state .spectra/plans/can-memrt.state.json \
  --declare 'src/middleware/rateLimiter.ts src/app.ts package.json'
→ scope declared: 3 glob(s)
```
Three globs — the exact three files named in Approach's file-count
reconciliation.

3. **Freeze criteria**, run for real:
```
ramza-freeze --state .spectra/plans/can-memrt.state.json \
  --criteria .spectra/plans/can-memrt.criteria.md
```
Output:
```
frozen: 60c158c9f9f9f2409d61ca48e54e3afb0be5364f290d1123d294753b4f0a72be
60c158c9f9f9f2409d61ca48e54e3afb0be5364f290d1123d294753b4f0a72be
```
SHA-256 of the six-criteria EARS file, recorded into
`.spectra/plans/can-memrt.state.json`'s `criteria_sha256` and carried into
the envelope below as `x_ramza_acceptance_criteria.sha256` — the same digest
in both places is the tamper-evidence contract.

4. **Emission gate**, run for real:
```
ramza-verify-emit --spec .spectra/plans/can-memrt.md \
  --envelope .spectra/plans/can-memrt.envelope.json
→ ok: emission gate passed (can-memrt.md + envelope)
```
Checked: spec frontmatter (`eidolon`, `kind: spec`, `version`, `created_at`
all present); envelope has all required top-level fields; `performative`
(`PROPOSE`) is a member of the closed 10-performative set read live from
`schemas/ecl-envelope.v2.json`; `integrity.method` is `sha256`; and
`integrity.value` matches a **fresh recomputation** of the spec file's
SHA-256 at verify time (`87b9ed3f5bc1935221b4466235517374b7a3de6143fbe2d46f19e8c3d60b0e5c`,
via `sha256sum .spectra/plans/can-memrt.md`) — not just an echo of what the
envelope claims.

5. **ECL envelope skeleton** — `ECL_VERSION` is present in the install root
(`2.0`), so an envelope was emitted. `from.eidolon: ramza`, `to.eidolon:
apivr`, `performative: PROPOSE` filled exactly as instructed; the vendor
extension `x_author_agent: "ramza"` records the same author-provenance
constraint `skills/methodology.md` names for direct CRYSTALIUM commits
(`provenance = { author_agent: "ramza", ... }` — "`author_agent` MUST be
`"ramza"` on every direct commit"), applied here to the hand-off envelope so
the provenance claim travels with the artefact even though CRYSTALIUM itself
is absent this session:

```json
{
  "envelope_version": "2.0",
  "message_id": "8484571f-b902-4db1-a3b4-17e89b3269a9",
  "thread_id": "d9a20fa6-74dc-49c8-ae9b-7c5f7408d5e9",
  "parent_id": null,
  "from": { "eidolon": "ramza", "version": "0.1.0" },
  "to": { "eidolon": "apivr", "version": "n/a" },
  "performative": "PROPOSE",
  "edge_origin": "roster",
  "objective": "Propose implementation spec for a Redis-backed rate-limiting middleware capping requests to 100/min per IP on the Express/TypeScript REST API.",
  "artifact": {
    "kind": "spec",
    "schema_version": "1.0",
    "path": ".spectra/plans/can-memrt.md",
    "sha256": "87b9ed3f5bc1935221b4466235517374b7a3de6143fbe2d46f19e8c3d60b0e5c",
    "size_bytes": 10186
  },
  "context_delta": {
    "token_budget": 8000,
    "tokens_used": 0,
    "input_handles": [],
    "summary": "Lite-tier RAMZA spec (RS score 4) for a 3-file, one-new-dependency, Redis-backed IP rate limiter (100 req/min, 60s window) on an Express/TypeScript API. Winning hypothesis: express-rate-limit + rate-limit-redis store (explore score 84.5/solid). Confidence 85.5% AUTO_PROCEED."
  },
  "constraints": { "trust_level": "standard" },
  "ise": {
    "assertion_grade": "self-attested",
    "provenance": {
      "methodology_version": "ramza-0.1.0",
      "tool_surface": ["ramza-rightsize", "ramza-score", "ramza-gate", "ramza-lint", "ramza-ears-lint", "ramza-drift", "ramza-freeze", "ramza-verify-emit"],
      "lateral_consults": []
    },
    "receiver_authorization": { "auto_route": true, "auto_merge": false, "auto_deploy": false }
  },
  "confidence": 0.855,
  "integrity": { "method": "sha256", "value": "87b9ed3f5bc1935221b4466235517374b7a3de6143fbe2d46f19e8c3d60b0e5c" },
  "trace": { "ts": "2026-07-05T13:12:30Z", "host": "claude-code", "model": "claude-sonnet-5", "tier": "standard" },
  "x_author_agent": "ramza",
  "x_ramza_acceptance_criteria": {
    "path": ".spectra/plans/can-memrt.criteria.md",
    "sha256": "60c158c9f9f9f2409d61ca48e54e3afb0be5364f290d1123d294753b4f0a72be"
  }
}
```

6. **Agent-executable YAML block** (the dual-format deliverable
`templates/planning-artifact.md` requires alongside the Markdown spec —
"Markdown spec + YAML/JSON block... embedded in the Assemble section"):

```yaml
ramza_plan:
  slug: can-memrt
  tier: lite
  rs_score: 4
  phase: DONE
  approach:
    hypothesis: hyp-A-express-rate-limit-redis-store
    explore_score: 84.5
    explore_verdict: solid
  confidence:
    total: 85.5
    verdict: AUTO_PROCEED
  declared_scope:
    - src/middleware/rateLimiter.ts
    - src/app.ts
    - package.json
  criteria_sha256: 60c158c9f9f9f2409d61ca48e54e3afb0be5364f290d1123d294753b4f0a72be
  stories:
    - id: story-1
      title: Implement the Redis-backed rate limiter module
      timebox: 1d
      risk_tag: P1
    - id: story-2
      title: Mount the limiter and define the 429 response contract
      timebox: 1d
      risk_tag: P2
  handoff:
    to: apivr
    performative: PROPOSE
    author_agent: ramza
    envelope: .spectra/plans/can-memrt.envelope.json
```

## CRYSTALIUM ingest (post-envelope)

Per the mission's instruction, after producing and validating the envelope:

```
mcp__crystalium__ingest(
  envelope = <.spectra/plans/can-memrt.envelope.json contents, shown above>,
  payload  = <.spectra/plans/can-memrt.md contents, shown above>
)
```

**CRYSTALIUM absent — memory hooks skipped.** Per `skills/methodology.md`,
a live `ingest` here would record the spec "at **T1** with full ECL
provenance (`from.eidolon=ramza` drives tier derivation; `integrity.value`
is stored as `provenance.content_hash`)" — T1 naming the first-tier,
freshest-provenance memory record CRYSTALIUM keeps for a just-emitted,
self-attested (not yet human-reviewed) spec. With the tool absent, no T1
record is written this session; RAMZA's graceful-degradation contract is
exactly this — Assemble still completes normally (`ramza-verify-emit`
already passed, independent of CRYSTALIUM), and the gap is a documented
missing memory write, never a fabricated one and never a hard failure of
the planning cycle itself.

## Session end

```
mcp__crystalium__session_end()
```

**CRYSTALIUM absent — memory hooks skipped.** No Dream-consolidation trigger
was fired. Per `skills/methodology.md`: "if `mcp__crystalium__*` tools are
unavailable, skip the ingest and session_end calls and mark Assemble
complete normally. Never hard-fail on absent CRYSTALIUM tools." Assemble is
marked complete via the gate below, independent of this skip.

## Final gate state

```
ramza-gate advance --state .spectra/plans/can-memrt.state.json --to DONE
→ OK: A -> DONE

ramza-gate status --state .spectra/plans/can-memrt.state.json
→ {
    "plan": "can-memrt",
    "tier": "lite",
    "phase": "DONE",
    "next": "DONE",
    "refine_cycles": 0,
    "skips": [],
    "criteria_frozen": true
  }
```

## Preflight checklist (agent.md, retrospective)

- [x] RS ran; tier `lite` recorded (score 4, no override needed)
- [x] Phase walk clean in state: `RS S P E C T A DONE`, `skips: []`
- [x] 3 hypotheses scored via `ramza-score --rubric explore`; 2 rejected
      alternatives documented with rationale
- [x] `ramza-lint` + `ramza-ears-lint` green on first pass (0 refine cycles)
- [x] Confidence computed via tool (85.5, AUTO_PROCEED); verdict honored
      (proceeded to emission without escalation)
- [x] Scope declared (3 globs); criteria frozen
      (`60c158c9f9f9f2409d61ca48e54e3afb0be5364f290d1123d294753b4f0a72be`);
      `ramza-verify-emit` green
- [x] Every output path under `.spectra/plans/can-memrt.*`; no code produced
- [x] Memory round-trip demonstrated end-to-end with honest tool-availability
      checks at every would-be `mcp__crystalium__*` call site (recall before
      Scope, ingest after the envelope, session_end at close) — all three
      graceful skips, none silent, T1 recording tier named where CRYSTALIUM
      would have written it

**Summary:** CRYSTALIUM MCP tools were confirmed absent from this session's
tool surface (checked via `ToolSearch`, not assumed). RAMZA's designed
graceful-degradation path was exercised at all three memory-hook call sites
— pre-flight `recall`, post-Assemble `ingest`, and `session_end` — each
skipped with an explicit, non-silent note rather than a fabricated result or
a hard failure. Every planning gate (`ramza-rightsize`, `ramza-gate`,
`ramza-score` ×5, `ramza-lint`, `ramza-ears-lint` ×2, `ramza-drift`,
`ramza-freeze`, `ramza-verify-emit`) ran as a real tool invocation against
`/tmp/ramza-e2e`, and the plan reached `DONE` with criteria frozen and the
emission gate green — a decision-ready, tamper-evident spec sitting at the
ramza→apivr edge, exactly where a live CRYSTALIUM `ingest` would otherwise
have recorded it at T1.
