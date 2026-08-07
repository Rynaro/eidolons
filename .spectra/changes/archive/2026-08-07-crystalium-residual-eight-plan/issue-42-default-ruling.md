# FORGE ruling — `Config.recall_seed_derived_credit` default and the #42 closure

ruled_by: forge (standing in for the maintainer; autonomous, no escalation)
ruled_at: 2026-08-06
inputs: forge-rulings.md (D2, D9), spec.amend-01.md §B.5 (#42) and spec.md §3.4/§6 S-1,
verification-plan.amend-01.md §S-1 (amended trigger list), spec.amend-02.md §2 (global
rule (f)/S-14), spec.criteria.amend-01/-03 AC-352, vp-w42-dp1-control.json,
vp-w42-dp1-recheck.json, red-evidence-w42.json, implementer report on the hub/spoke
substitute run (caller-verified: byte-identical `multihop_f1 == 0.3077` under both flag
values; the fixture contains **no seed-to-seed edge**). Prior FORGE verdict recalled from
memory: the post-#41 retrieval-gate sweep was **fully degenerate** (21/21 identical across
3 weights x 7 seeds, single F1 0.4615) — the standing eval corpus cannot discriminate
fusion-membership changes.
target: crystalium branch `fix/seed-exclusion-relax-42` @ `8a3dca6`. READ-ONLY ruling;
the flip itself is the implementer's one-line change.

Measured facts below are taken as given per the caller's verification; nothing in this
ruling re-derives them.

---

## RULING

1. **`Config.recall_seed_derived_credit` defaults to `False` for v2.1.0.** The relaxation
   ships as a fully-threaded, fully-tested **opt-in**. The implementer's shipped `True` is
   overruled; flip it (config default AND any env-override default — both lines, the
   `config.py:437` two-defaults precedent from D6).

2. **No fixture can discharge S-1's second trigger, and v2.1.0 does NOT block on one.**
   A seed-to-seed-edge fixture at the retrieve surface is trivially buildable and would
   prove the channel live end-to-end — an existence proof, which is not what (b) asks.
   Trigger (b) is a *direction-of-quality* claim ("relaxation regresses multi-hop F1"),
   and any synthetic fixture's relevance set is author-stipulated: whether promoting S2
   or demoting N2 is a "regression" is decided by the fixture author, not the system.
   That is stipulated ground truth — the #47/#55 species (S-11), D9 class (b). The
   standing real instrument is independently known degenerate (prior ruling, above).
   I rule under uncertainty, as required: **preserve behaviour, ship the mechanism.**

3. **#42 closes as a SPLIT (the #48 precedent), and the closing comment must name both
   halves:** **SHIPPED** (the 5-site threading, the T1/T2/T3(+variant) oracle, the opt-in
   flag, AC-352 with its control-first discipline) **+ policy-affirmed** (seed exclusion
   stays the default; the default-flip question is unobservable-without-non-stipulated-
   ground-truth, closed with a named reopen condition). Verbatim comment below.

4. **Nothing blocks the v2.1.0 tag.** The flip is one line plus the consequential checks
   in "v2.1.0 impact" below. Do not wait for a multi-hop measurement; do not build a
   stand-in fixture; do not cite the hub/spoke flat run as evidence anywhere.

---

## REASONING

Three genuinely distinct positions were deliberated:

- **H1 — default `False`, relaxation opt-in** (+ a D4-style forward obligation on any
  future flip). **ADOPTED.**
- **H2 — default `True`**, on the strength of AC-352 alone.
- **H3 — block v2.1.0** until a real (b)-class measurement exists, then decide.

**H2 fails on the campaign's own epistemics.** S-1 has two triggers; (a) is cleared by a
real, control-first measurement (`w_derived=100.0` ⇒ `p1_recreated: true` demonstrating
the instrument, then `w_derived=1.0` ⇒ `false`, derived-only rank 1 > two-base-arm
rank 0 — vp-w42-dp1-control.json / vp-w42-dp1-recheck.json at `8a3dca6`). But (b) was
never measured: the substituted hub/spoke fixture has no seed-to-seed edge, so its
byte-identical output under both flag values is **a negative from an instrument that
cannot produce a positive** — precisely what global rule (f)/S-14 exists to reject, and
the same species as VP-M1's powerless 7-seed protocol earlier in this campaign. Shipping
`True` would change recall MEMBERSHIP for every consumer while presenting that construct
as the missing measurement — the C-9-adjacent discipline this campaign has refused twice
(#47, #55). D1's own maxim governs: a claim of this class must be an artifact, not an
adjective. "Relaxation is safe at every consumer" currently has no artifact. The wider
precedent agrees: in the #38 campaign three dense-arm models were all wrong and only
real-stack measurement settled DP-1; derivations about fusion behaviour do not
generalise without measurement.

**The cost asymmetry is decisive and one-directional.** `exclude_seeds=True` is
byte-identical to `b7f1a47` by construction and by test (AC-350, all topologies), so a
`False` default costs every consumer exactly nothing. The reversal costs are not
symmetric: `False`→`True` later is a one-line minor-release change with a measurement
attached; `True`→`False` after a discovered regression means every consumer ran altered
recall membership in the interim — and because CRYSTALIUM is a bi-temporal memory store,
crystals committed from that altered recalled context are permanent downstream artifacts.
P0 rule 4: irreversible-leaning advice requires the higher evidence bar, and the bar is
not met.

**"Default False reads as not answering #42" is rejected.** The issue asks whether the
exclusion is policy or accident. Flipping the default does not answer that question;
classifying does. The closure states: the exclusion originated as an unexamined
implementation property of #41, and is now explicit, documented, tested policy — with a
shipped, fully-characterised opt-out and a recorded decision trail. That is a complete
answer, and it is the honest one available today.

**H3 fails the bounded-deliberation discipline.** The only honest (b)-instrument is
non-stipulated ground truth (production traces or a real-corpus eval), which does not
exist on a release schedule. Holding a release train hostage to an unobtainable
measurement, while a zero-cost behaviour-preserving default exists, is the inverse of
the D9 one-cycle bound. H3 also buys nothing H1 does not: H1 ships the identical
mechanism and leaves the identical flip available the day the measurement exists.

**Plan-text check:** spec.md:369 says the default is "decided by the DP-1 re-check,
§6 S-1", but S-1 only ever specifies the keep-exclusion branch; nothing in any revision
mandates `True` on AC-352 clearing. This ruling resolves that silence; it contradicts no
binding text. No AC pins the config default, so the flip breaks no criterion.

---

## REVERSAL CONDITION

- **Flip to `True` becomes licensed** the day a multi-hop relevance measurement on
  **non-stipulated ground truth** — production recall traces, or a real-corpus eval whose
  relevance judgments are not authored by the fixture builder — shows relaxation
  non-regressing (or superior) on multi-hop F1 with `recall_seed_derived_credit` on vs
  off. The flip then ships in a minor release with the measurement attached to the
  reopened #42. Any flip WITHOUT that measurement re-commits H-D and is prohibited
  (forward obligation, D4 pattern — recorded in the closing comment and in the
  `config.py` comment block).
- **This ruling is overturned in the other direction** (exclusion itself reopens as a
  defect) if a P1-family anomaly is measured in production that seed-credit demonstrably
  cures, or if a consumer is found whose correctness (not preference) depends on
  seed-derived credit — either reopens #42 with the artifact attached.
- If AC-352's module is found to inherit the Config default rather than pinning the flag
  in-fixture, the recorded artifacts' meaning is default-coupled and both parts re-run
  after the flip (see impact item 2).

---

## The verbatim #42 closing comment

> **Closed: SHIPPED (mechanism, opt-in) — seed-exclusion default AFFIRMED as policy.
> `Config.recall_seed_derived_credit` defaults to `False`.**
>
> This issue asked whether the graph arm's seed exclusion is policy or accident. Answer:
> it originated as an unexamined implementation property of #41 (`hop_ids -=
> original_seeds` plus the one-hop input filter), and it is now explicit, tested policy
> with a shipped opt-out.
>
> **Shipped** (evidence recorded at `8a3dca6`):
> - `exclude_seeds: bool = True` threaded through all five behaviour sites of
>   `neighbor_expand` / `decaying_walk` (`graph.py:225/:271/:272/:302/:305`; `:266`
>   deliberately unchanged — its proof obligation discharged by the T2 topology, where a
>   hop-2-discovered seed reaches results with `:266` untouched).
> - `exclude_seeds=True` byte-identical to `b7f1a47` on every topology (AC-350);
>   False-branch semantics exactly characterised (AC-354: T1/T2/T3 + variant); per-site
>   wiring proven by an axis-distinct checker perturbation (severing `:272` alone reddens
>   AC-354 on T1/T2 while AC-350 stays green).
> - Retrieval opt-in via `Config.recall_seed_derived_credit`, default **`False`** —
>   today's behaviour for every consumer, including Dream, by construction.
>
> **Measured** (DP-1(b) re-check, AC-352, positive control run FIRST): at
> `w_derived=100.0` the instrument re-creates P1 on demand (`p1_recreated: true`,
> derived-only rank 0 < two-base-arm rank 1); at the shipped `w_derived=1.0`, no P1
> re-creation (`p1_recreated: false`, derived-only rank 1 > two-base-arm rank 0).
> Artifacts: `vp-w42-dp1-control.json`, `vp-w42-dp1-recheck.json`.
>
> **Not measured, stated plainly:** S-1's second trigger — a post-#41 multi-seed
> measurement of relaxation's effect on multi-hop F1 — has no honest instrument today.
> The standing retrieval-gate fixture contains no seed-to-seed edge; it returned
> byte-identical F1 under both flag values, which is a negative from an instrument that
> cannot produce a positive and is not admitted as evidence (campaign rule (f)). No
> synthetic fixture can discharge it: multi-hop F1 against author-stipulated relevance is
> stipulated ground truth (the same species already ruled unobservable for #47 and #55).
> A recall-membership change for every consumer will not ship on that basis.
>
> **Reopen condition (the deciding signal, named):** a multi-hop relevance measurement on
> non-stipulated ground truth — production recall traces or a real-corpus eval —
> comparing `recall_seed_derived_credit` on vs off. Non-regressing ⇒ the default may flip
> to `True` in a minor release with that measurement attached here. Regressing ⇒ record
> it here; the policy stands. **Forward obligation:** any PR flipping this default MUST
> attach that measurement as a precondition; a flip without it is prohibited.

---

## v2.1.0 impact

**The tag is NOT blocked.** Required before it, all bounded:

1. **The one-line flip** on `fix/seed-exclusion-relax-42`: `recall_seed_derived_credit`
   default `True` → `False` — in BOTH places if an env override exists (`Config` field
   and the `_env_bool` default; the `config.py:333`/`:437` two-defaults precedent).
2. **Pin check on AC-352's module:** confirm `run_dp1_recheck` sets the relaxation flag
   explicitly in-fixture (its GIVEN is "seed exclusion relaxed") rather than inheriting
   the Config default. If it inherits, pin it and re-run AC-352 (i)+(ii) once on the
   flipped tree. The recorded artifacts remain valid either way for `8a3dca6`; the
   v2.1.0 checker hop re-verifies at the RC SHA regardless.
3. **Re-run the W-42 exit gates on the flipped tree** (AC-350/351/354, AC-352 both
   parts, AC-353 Dream-untouched, both suite modes + baked-image form). All expected
   green — no criterion pins the config default.
4. **`config.py` comment block** (W-42's grant): one line stating the default, the
   rationale (S-1(b) unmeasured; the substitute instrument had no power to see the
   regression it stood in for), and the reopen condition + forward obligation.
5. **Post the closing comment above on #42** at closure time (Wave-3 discipline: after
   the v2.1.0 checker hop passes, not before). The flip must land BEFORE that checker
   hop so all checker evidence is recorded on the final tree.
6. **Recommended, non-blocking:** if W-42's suite lacks a fused-surface wiring test
   (T1's topology through `Aetheryte.recall`, flag on vs off, asserting the membership
   delta), add one in the flip commit — it guards the opt-in path a consumer who sets
   `True` will rely on. This is an existence/wiring proof and must not be described as
   an F1 measurement.

**Prohibited:** citing the hub/spoke flat run (`multihop_f1 0.3077` both branches) as
evidence for or against relaxation in any release note, CHANGELOG line, or the closing
comment beyond the "not measured" statement above.

---

## Confidence

**91%.** The default ruling is overdetermined: rule (f) rejects the only evidence that
could license `True`; the reversal-cost asymmetry is one-directional on a bi-temporal
store; the `False` default is measured byte-identical (AC-350) so it costs nothing; and
the campaign's own precedent (D1's artifact-not-adjective, the #38 dense-arm lesson, the
degenerate post-#41 sweep) uniformly favours preserving behaviour absent measurement.
Residual 9%: the possibility that a real-corpus measurement would have shown relaxation
strictly superior, making `False` a bounded, recoverable delay — accepted as the cheaper
error. The flip and closure land through the standing v2.1.0 checker hop, which serves
as the required checker for this release-gating verdict.

*FORGE. Ruled decisively; no escalation; reversal conditions named.*
