# Decision Record — atomos MCP: go / no-go

> **Author:** FORGE (Reasoner, methodology 1.10.0) · 2026-07-07
> **Decision ID:** OQ-E2 re-evaluation (successor to deliberation D2)
> **Decision type:** FEASIBILITY / scope
> **Requester:** orchestrator (ECM P2 gate)
> **Prior reasoning of record:** `.spectra/changes/archive/2026-07-07-ecm-context-kernel/deliberation.md` §D2 (OQ-E2), 90% conf.
> **requires_checker:** false (irreversibility scan below — zero matches)
> **[VERDICT]** **NO-GO on building atomos** — hold the roadmap line as **DEFER-WITH-TRIPWIRE**; let the pre-registered mechanical kill strike it at P2 exit. **Confidence: 88%.**
>
> **⇄ OVERRIDDEN 2026-07-07 — final status: GO.** The maintainer (decision authority) elected to **build atomos** (committed P3), superseding the NO-GO *recommendation* below. See **§0. Decision Override** immediately following. FORGE's analysis is retained verbatim as the considered feasibility record and the source of atomos's scope fence.

---

## 0. Decision Override — GO (maintainer, 2026-07-07)

**Final status: GO — atomos is a committed P3 build.** The maintainer (Rynaro), as
the decision authority, has elected to **build atomos**, superseding FORGE's NO-GO
*recommendation* recorded in §1–§5 below. This is a strategic/product call (MCP-surface
parity across the ecosystem and innovation headroom), and it stands above the
feasibility-scoped recommendation: a human decision overrides an advisory verdict.

FORGE's technical findings are **not** overturned — they remain true and become
atomos's binding **design constraints**:

- **Scope fence (unchanged from D2 / §5).** atomos is a **compose/verify executor
  MCP** — it composes the handoff brief and verifies pin sets / ECL envelopes as an
  MCP surface (a tonberry-analog for the context lifecycle). It **never** owns
  meter/policy/trigger, and it **never** performs context injection.
- **The honest caveat still holds.** atomos does **not** solve the cross-host
  injection-channel gap (§3 E2/E6) — nothing host-external can; injection is a
  host-surface property. atomos is built for MCP-surface consistency and an optional
  in-session compose/verify path, not to fix Cursor/OpenCode injection. The
  **kernel-verbs path stays canonical and always-available**; atomos is **additive**,
  never a replacement, and every host adapter (P2) ships on kernel+hooks regardless.
- **P2 is unaffected.** The former "delete atomos at P2 exit" tripwire is **retired**.
  atomos is now built in parallel at P3, *informed by* (not gated by) P2 field
  evidence. The §5 tripwire and reversal conditions below are superseded by this GO.

**Roadmap slot (P3):** a new `Rynaro/atomos` MCP repo + image (crystalium/tonberry
pattern), fenced to compose/verify, wired into the roster as the **5th sibling MCP**
(memory=crystalium · lifecycle=tonberry · bus=junction · read=atlas-aci ·
**context-compose/verify=atomos**). Verbs sketch: `compose-handoff` (build the brief +
ECL envelope from a plan/identifier manifest), `verify-pins` (post-op pin-survival
probe), `verify-envelope` (ECL integrity over a handoff artifact) — all pure
compose/verify, all mirrored by the existing `eidolons context` kernel verbs so the
MCP is an *alternate surface*, never the sole path.

FORGE's full NO-GO analysis is retained below verbatim — it is the source of
atomos's scope fence and the reasoning a future maintainer must read before ever
widening atomos past compose/verify.

---

## 1. Framed question

Should ECM build a dedicated **atomos MCP server** to own context-lifecycle
operations, or keep the **kernel-verbs + host-hook recipes** path that P1 shipped?

Specific, falsifiable form:

> Given (a) P1 shipped `eidolons context status|policy|externalize|handoff` as a
> pure bash 3.2 + jq kernel with a canary-green handoff round-trip on Claude Code,
> and (b) the D2 anti-scope fence that restricts any future atomos to
> **compose/verify execution only** (never meter/policy/trigger/injection), does
> the field evidence now available fire D2's kill criterion, demand building
> atomos, or leave the P3 conditional standing?

**Success criteria.** The verdict (i) quotes and applies D2's exact kill
criterion; (ii) states whether it fires; (iii) resolves to GO / NO-GO /
DEFER-WITH-TRIPWIRE; (iv) names the single signal that flips it; (v) is
actionable by the P2/P3 gate without re-opening the frozen ECM roadmap
speculatively.

### Hard constraints carried from ECM P0 / D2 (each eliminates options)

| ID | Constraint | Source |
|----|-----------|--------|
| CC-A | Anything on the meter/policy/trigger/**injection** path must be **harness-injected**, never model-requested. An MCP is model-requested by definition. | E3 survey F6 (A/B-tier, measured Letta/MemGPT failure class); D2 |
| CC-B | Fail-open, advisory-first; never block on memory/telemetry failure. | ECM P0-9 |
| CC-C | Anti-scope: ECM never re-declares CRYSTALIUM (persistence) or ECL (transport). atomos, if built, is fenced to compose/verify only. | ECM P0-7; D2 |
| CC-D | Kernel verbs stay bash 3.2 + jq, ≤300 ms prompt path. | ECM P0-8 |
| CC-E | The build/kill call is made by evidence the spec itself scheduled (P2-exit canary), not ahead of it. | D2 H1-rejection rationale |

---

## 2. The kill criterion (quoted verbatim)

From `deliberation.md` §D2 merged verdict:

> **[VERDICT] H2 — kernel-verbs+hooks are the complete and canonical v1.0
> implementation; atomos remains a P3 conditional with its anti-scope fence
> written into the spec now (compose/verify executor only — never
> meter/policy/trigger/injection) and a pre-registered kill criterion: if all
> wired hosts pass the handoff round-trip canary via kernel+hooks alone at P2
> exit, atomos is deleted from the roadmap.** P1 builds nothing atomos-related.

The two governing reversal conditions (verbatim):

> **[REVERSAL-CONDITION]** (convergent, T1+T2): all-hosts canary PASS via
> kernel+hooks at P2 exit → delete atomos (H1 fires then, mechanically).
>
> **[REVERSAL-CONDITION]** (convergent, T2+T3): a verified host gap in brief
> composition/ingestion → atomos green-lit, scope-fenced to compose/verify.

So there are exactly two live triggers, and they point opposite directions:
- **KILL trigger:** all wired hosts pass the round-trip canary via kernel+hooks
  alone, evaluated **at P2 exit**.
- **BUILD trigger (the only GO path):** a **verified host gap in brief
  composition/ingestion** — i.e. a gap inside atomos's *legal fence*
  (compose/verify), not anywhere else.

---

## 3. Evidence ledger

| ID | Evidence | Relevance | Reliability |
|----|----------|-----------|-------------|
| E1 | P1 shipped: kernel verbs + Claude Code (T3) hooks; deterministic P1–P7 table; fail-open; crystalium-mediated externalize; ECL-enveloped handoff; canary round-trip **PASS** (AC-4) with `contains_tool_origin:true` regression **PASS** (AC-9) on crystalium 1.8.0. Kernel proved sufficient on the one fully-wired host with **no MCP**. | KILL-arm, direct | **H** — shipped + checker-verdict GO (`checker-verdict.md`); AC-4/AC-9 canary confirmed against published image (MEMORY: nexus v2.2.0 canary PASS) |
| E2 | New P2 scout finding: extending ECM to Codex/Copilot/Cursor/OpenCode is blocked **not by where the logic lives** but by the fact that hosts expose radically different — or absent — context-**injection channels** (session-start-only, per-tool, or none at all on Cursor/OpenCode). An MCP does **not** create an injection channel where the host provides none. | Reframes both triggers | **M** — scout finding, task-summarized; raw scout not read here (see [GAP-1]) — but consistent with E4 host-facts (Cursor "no prompt-block ever", OpenCode T1 documentary-only) |
| E3 | Survey F6 (A/B-tier, internally measured): anything on trigger/meter/injection must be harness-injected; a model-requested memory/context surface **is** the measured failure mode (Letta/MemGPT class). | Anchors CC-A | **H** — measured, cited in D2 as the strongest single finding |
| E4 | Host enforcement ladder (spec §5): Cursor T2 "no prompt-block ever (known bug)"; OpenCode T1 "AGENTS.md documentary thresholds"; Claude Code PreCompact **not** in the documented hook set (verified 2026-07-06). The host injection surface is the binding constraint per host, already recorded pre-atomos-question. | Corroborates E2 | **H** — `evidence-host-facts.md`, first-party-doc verified |
| E5 | Sibling-MCP bar: crystalium (memory), tonberry (ESL lifecycle), junction (bus), atlas-aci (read surface) each own a **distinct persistent capability with its own state/surface**. ECM's state is ephemeral, harness-local sidecars (meter.json, TTL execution checkpoints, policy-log.jsonl); persistence is **delegated to crystalium**, transport to ECL. | Sibling-bar test | **H** — established ecosystem facts (CLAUDE.md; sibling specs) |
| E6 | Architectural fact: `eidolons context handoff` is a single host-agnostic bash verb. Brief composition + ECL envelope + `crystalium_ingest` are **local computation identical on every host**; only *delivery/injection* of the resulting digest varies per host. | Kills the GO path (see §4) | **H** — P1 spec §Story S-E; scout FINDING-015 (recall/inject is the host-variable leg, compose is not) |
| E7 | CRYSTALIUM recall: ECM design + P1 maker/checker episodic crystals (T1, unverified). | Context only | **M** — consistent with E1, no new facts |

**Separation of confirmed from speculative:**
- **Confirmed:** kernel sufficient on Claude Code (E1); compose/verify is
  host-agnostic local bash (E6); ECM state is ephemeral and delegates
  persistence (E5); model-requested context surface is a measured failure mode
  (E3).
- **Speculative / unresolved:** the P2-exit canary result for the *other four
  hosts* does not exist yet — P2 has not exited (MEMORY: "P2/P3 not started";
  E2 is early P2 recon). The literal KILL trigger's "at P2 exit / all wired
  hosts" condition is therefore **not yet mechanically satisfied**. `[GAP-1]`
  the raw P2 scout was summarized, not read in this deliberation.

---

## 4. Reasoning

### 4.1 Strongest case FOR atomos (H3 — build it)

The tonberry precedent argues for pattern uniformity: ESL got a lifecycle MCP,
so context-lifecycle "deserves" one too, and a compose/verify executor could
centralize brief composition and envelope verification. If a weak-hook host
(Copilot-class) proved unable to compose/ingest the handoff brief through the
kernel, an in-session executor could carry that leg.

**Why it does not hold.** This case requires the **BUILD trigger** to fire — a
*verified host gap in brief composition/ingestion*. Three independent facts
foreclose it:
1. **E6 (host-agnostic compose).** The kernel's compose/verify is local bash+jq
   that runs identically on every host. There is no host where the kernel can
   run at all but its compose/verify leg specifically fails while an MCP's
   compose/verify would succeed — the computation is the same bytes. For atomos
   to be *needed*, a host would have to (a) be unable to execute the kernel's
   local compose yet (b) able to invoke a model-requested MCP and (c) have its
   deficit be in compose/verify, not injection. That intersection is empty.
2. **CC-A / E3.** An MCP is model-requested; the F6 finding makes a
   model-requested context surface the *measured* failure mode. Committing to
   atomos builds the failure mode into the roadmap.
3. **E5 sibling-bar.** ECM holds no distinct persistent capability of its own —
   it delegates persistence to crystalium and transport to ECL, and its live
   state is ephemeral sidecars. It fails the bar the four existing sibling MCPs
   meet. It is harness-local logic, not a service.

### 4.2 Strongest case AGAINST atomos (H1/H2 — do not build)

P1 is the existence proof: the kernel path shipped, passed its round-trip canary
(including the tool-origin quarantine regression AC-9), and needed no MCP on the
one fully-wired host (E1). The KILL-arm of the criterion has **fired on Claude
Code**.

The decisive new evidence is E2, which resolves the *build* trigger against
atomos in a way D2 could not yet see: the cross-host blocker is the **host's
context-injection channel**, which is **explicitly outside atomos's legal fence**
(CC-C: never injection) **and cannot be created by any MCP** (an MCP delivers
its output *through* an injection channel; it cannot manufacture one where the
host exposes none — E2, E4). So the only gap that will materialize at P2 —
injection-surface gaps on Cursor/OpenCode/Copilot — is a gap atomos is both
*forbidden* to address and *incapable* of addressing. The BUILD trigger's
subject (a compose/verify gap) is not what P2 will surface.

### 4.3 Counterfactual — what would have to be true for GO

Atomos would become the right call only if a host emerged that: provides a
working per-prompt/per-tool injection channel (so a model-requested surface can
be reached at all), can invoke an MCP, **and** demonstrably cannot execute the
kernel's local bash compose/verify — with the failing leg being *composition or
envelope verification*, not metering, policy, triggering, or injection. Given
E6 (compose is host-agnostic local computation) this counterfactual is
near-empty: the only genuinely host-variable leg is injection, which is fenced
out. No evidence in the ledger points toward it; E2/E4 point directly away.

### 4.4 Adversarial self-tests

- **Inversion** (assume NO-GO is wrong): find one host where kernel compose
  fails but MCP compose succeeds → none exists; compose is the same local bytes
  everywhere (E6). NO-GO survives.
- **Boundary** (worst host — Cursor/OpenCode, no per-prompt channel): does
  atomos help? No — with no injection channel, a model-requested surface has no
  delivery path; MCP or kernel, the output cannot land (E2/E4). Boundary
  *strengthens* NO-GO.
- **Pre-mortem** (how NO-GO hurts): we hard-delete the fence, then a real
  compose/verify gap appears, and re-opening a frozen sibling-spec roadmap
  costs an ESL cycle + loses the tidy mechanical delete D2 designed. **This is
  exactly why the verdict is NO-GO-on-build with DEFER-on-deletion, not
  delete-now** — the fence stays, the mechanical trigger does the striking.
- **Dependency:** the verdict leans on E2 (injection is the blocker — M-tier)
  and E6 (compose is host-agnostic — H-tier). If E2 is wrong and the true P2
  blocker turns out to be compose/verify, the verdict flips — that is the
  tripwire (§5).

### 4.5 Does the kill criterion fire?

- **BUILD trigger:** **does not fire, and is now foreclosed.** No verified
  compose/verify host gap exists; E2 shows the actual gap is injection-surface,
  outside atomos's fence and beyond any MCP's reach.
- **KILL trigger:** **fired on Claude Code; not yet mechanically complete.** Its
  literal condition is "*all* wired hosts pass *at P2 exit*." Only 1 of 5+
  target hosts is canary-green and P2 has not exited (E1 confirmed;
  other-host canaries do not exist yet). Claiming a full mechanical kill *now*
  would overclaim the trigger.

The honest reading: the evidence has removed every path to GO, but the clean,
evidence-complete moment to *formally strike* the roadmap line is the
pre-registered mechanical trigger at P2 exit. The build decision is settled now;
the bookkeeping should ride the trigger D2 already designed.

---

## 5. Gate result and verdict

**[VERDICT] NO-GO on building atomos.** Structure the roadmap line as a
**DEFER-WITH-TRIPWIRE**: keep the D2 anti-scope fence in the spec, build nothing
atomos-related, and let the pre-registered mechanical kill (all-hosts round-trip
canary PASS via kernel+hooks at P2 exit) formally delete the P3 line. The new
P2 evidence (E2) additionally justifies **sharpening the surviving tripwire** so
that injection-surface gaps — which will dominate P2 — can never be
mis-attributed as an atomos green-light.

- **Confidence: 88%** (Evidence 88 — KILL-arm H-anchored and shipped, BUILD-arm
  foreclosure rests on M-tier E2 pending the raw scout; Logic 92; Constraint
  coverage 90; Sensitivity 82 — one live sensitivity, the [GAP-1] scout re-read).
  Strengthens D2's 90% direction; the small drop reflects E2's M-tier and the
  literal-trigger nuance, not new doubt about the build call.

### The single tripwire that flips this to GO

> A **verified host gap in brief *composition or envelope verification*** — a
> host that (a) exposes a working injection channel and can invoke an MCP, yet
> (b) cannot execute the kernel's local bash compose/verify leg specifically —
> distinct from any metering, policy, triggering, or **injection-surface** gap.
> An injection-channel gap (Cursor/OpenCode-class) is **explicitly not** this
> tripwire: it green-lights a host plugin/shim conversation (H4 below), never
> atomos.

Absent that tripwire, the mechanical kill stands: **at P2 exit, if every wired
host passes the round-trip canary via kernel+hooks alone, strike the atomos line
from `spec.md` §8 P3 via an ESL change.** If some host *fails* the canary for
injection-surface reasons (the expected E2 outcome), that failure still does not
build atomos — it routes to H4.

### Rejected alternatives

- **H3 — build atomos at P3 (GO):** rejected. Requires the BUILD trigger, which
  is foreclosed by E6 (compose is host-agnostic) and E2 (real gap is injection,
  outside the fence) and contraindicated by CC-A/E3 (model-requested surface =
  measured failure mode) and E5 (fails the sibling-MCP bar).
- **H1-immediate — hard-delete the fence now (aggressive NO-GO):** rejected as
  premature. P2 has not exited; only 1 host is canary-green (CC-E). Deleting now
  overclaims the literal trigger and discards the clean mechanical delete D2
  designed, for no gain — a no-build hold already prevents the speculative
  building H2 was guarding against. (Pre-mortem §4.4.)
- **H4 — re-scope the real need to a non-MCP artifact:** *retained as the
  correct destination for injection-surface gaps*, not as an atomos variant. If
  a host genuinely cannot inject, the answer is a host **plugin/shim** (e.g. the
  OpenCode plugin-shim meter already noted in spec §5), which lives on the host
  injection surface — never a model-requested MCP. This reinforces NO-GO on
  atomos specifically.

### Reversal conditions

- **[REVERSAL-CONDITION]** The §5 tripwire fires (a compose/verify-specific host
  gap, not injection) → re-open OQ-E2 with atomos scope-fenced to compose/verify.
- **[REVERSAL-CONDITION]** The raw P2 scout ([GAP-1]), when read, contradicts E2
  and shows the cross-host blocker is in fact compose/ingestion rather than the
  injection surface → downgrade this verdict and re-run against the corrected
  premise.
- **[REVERSAL-CONDITION]** All-hosts P2-exit canary PASS → the mechanical kill
  fires; this DEFER collapses to a formal delete (the intended terminal state).

### Checker-handoff scan

Recommended actions = (i) do not build atomos, (ii) keep the fence, (iii) let a
mechanical ESL spec-text edit strike the line at P2 exit. Scanned against the
five irreversibility triggers (deploy/release; destructive data migration;
security-boundary change; external spend; public communication): **zero
matches.** **requires_checker: false** (consistent with D2's record).

### Handoffs

- **→ RAMZA / ECM P2 gate:** carry the sharpened tripwire and the mechanical
  delete-at-P2-exit instruction into the P2 plan; wire the "all-hosts canary
  PASS ⇒ strike atomos" check into the P2-exit gate.
- **→ ATLAS:** re-read/confirm the raw P2 scout to lift E2 from M to H and close
  [GAP-1]; probe per-host injection-channel presence (Cursor/OpenCode
  especially) so injection-gap-vs-compose-gap is distinguishable at P2 exit.
- **→ human:** none required (confidence ≥85%, no [DISPUTED], requires_checker
  false).

---

## Provenance

- **Decision type:** FEASIBILITY / scope · **Depth:** Standard (2 passes,
  single-trace; below the G2 stakes bar — reversible spec-text bookkeeping)
- **Hypotheses evaluated:** 4 (H1 delete-now / H2 defer-with-tripwire / H3 build
  / H4 non-MCP re-scope)
- **Evidence sources:** 7 (5 H, 2 M) · **Markers:** 1 GAP, 3 REVERSAL-CONDITION
- **Confidence anchor:** 4-factor composite (Evidence 88 · Logic 92 ·
  Constraints 90 · Sensitivity 82) = 88%
- **ise.assertion_grade:** self-attested · **requires_checker:** false
- **Supersedes:** does not invalidate D2 — **confirms and sharpens** it
  (D2 90% → this 88%, same direction, tripwire tightened for the injection-gap
  case D2 could not yet see)
- **Author:** FORGE (Reasoner, methodology 1.10.0) · 2026-07-07 · ECM P2 gate
