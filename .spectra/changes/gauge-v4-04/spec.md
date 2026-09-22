# V4-04 — Journal ordering and legacy evidence floor

Assigned by the user as part of autonomous remaining V4-0X implementation. This change covers V4-04 only. Pinned authority: revision3 plan commit `c581308f055a0e252013bf09f2a7b2e1426ff811`, docs/campaigns/gauge/01-foundations.md#v4-04, HANDOFF.md and ARCHITECTURE.md. The planning branch remains separate.

Implementation base: `1a4697e2101f5c588dcf3632c6823e7b73c86d58`. V4-01 merged #599; approved V4-02 #601 merged `23c78d67762cc28d01c62fbbaf68bc254e99a1e4`; approved V4-03 #600 merged the base above after integration head `fb7bd926e2269af63949c4c5eb66663b4aee4e6a` passed all25 hosted checks (CI35676708950, RosterHealth35676705038). No source implementation begins before this prerequisite acceptance.

## Scope and requirement anchors

- R01/T01: append120 events and independently verify unique numeric sequence and predecessor/digest links across9/10 and99/100.
- R02/T02: synchronized distinct caller identities retained exactlyonce; identical identity/content retries idempotent and conflicting content rejected. Optional --event-id retains generated identity defaults.
- R03/T03: interruptions before/after publication and during ownership classify incomplete state, preserve published events and bound lock waits. Ambiguous/dead/unknown/missing ownership is recovery-required, never automatically stolen.
- R04/T04: unknown-run inspection explicitly reports unknown with no new run, home/cache or other durable files.
- R05/T05: malformedJSON, brokenchain, duplicate sequence, unsupportedversion and badselfdigest withhold successful projection; valid legacy control remains readable and unchanged. Append refuses an invalid published prefix.

Use dedicated cli/tests/journal_conformance.bats with named V4-04 T01..T05 anchors and language-neutral cli/tests/fixtures/journal/ canonical-byte/digest controls reusable by V4-06. Tests authored, tests executed, observed hostedCI and live/filesystem qualification remain separate claims. ATLAS baseline defects recorded before implementation in /private/tmp/gauge-v4-04-probe.py and .log; independent conformance tests need valid controls and isolated defects.

## Bounded design

FORGE decision in decision.md selects Bash mkdir ownership over Python supervision/helper alternatives to retain current CLI dependencies. Exclusive ownership encloses open existence checks, whole published-prefix validation, identity/content comparison, allocation, predecessor selection and publication. Keep jq -cS payload bytes INCLUDING trailing newline for schema1.0 digests, excluding event_digest. Never rewrite oldevents or replace an already published event. Owner cleanup must be scoped and occur only after potential publishing children finish. No recursive removal of contested lock paths. SIGKILL can leave a recovery-required lock; safe manual recovery requires established quiescence.

Retain Bash3.2 wrappers and run.sh optional failure-suppressed instrumentation. Fix eager cache creation only through a narrow ledger read-only initialization path. Completion semantics belong to V4-05; Go controller, budgets and automatic lock reclamation are outside scope. Claim only tested local filesystem/platform behavior, not networkFS or power-loss durability.

## Lifecycle and verification

Full tier,8/12 (scope2, ambiguity2, dependencies1, risk3), estimated7 implementation/test/docs files; real lock tradeoff deliberated separately before in_progress. Maker vivi_v4_core; distinct fresh checker v4_04_review. One repository writer at a time. User authorizes actual edits; no release/deployment/paid modeltrials/archive or additional PR merge inferred from the specific approval of#600/#601. New packages will be reviewable separately/stacked as appropriate.

Tonberry0.5.2 locked block enforcement. CRYSTALIUM tools unavailable, skipped without direct memory writes. Qualified local runner eidolons-v4-03-qualified:local (Bash5.2/Bats1.11.1); host Bash3.2 Bats can false-pass intermediate [[ failures, so no hostBats certification. Direct Bash3.2 probes use explicit exits; hostedCI includes negative qualification and Bash3.2 syntaxcheck. Observe all required checks before final readiness.
