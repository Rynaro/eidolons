# Gauge: quota-efficient verified delivery

**Status: proposed implementation campaign; no augmentation is implemented by this plan.**

Prepared 2026-09-18. Nexus source baseline: `752194ef5ceaa8cee1f5995fd0d374888696d8fc` (main inspected on the preparation date). The preceding architecture review is the motivation, not a benchmark. Source-inspection findings must be reproduced before being treated as confirmed runtime failures.

## Outcome

Optimize the total resources required to produce an accepted, runnable result, not the price of an isolated model turn. Preserve task acceptance and authority boundaries while adapting coordination, exploration, model effort, and concurrency to available resources. One user brief may produce many useful internal tool calls; unnecessary requests for the user to restart already-authorized work are the waste to remove.

Gauge is nexus-owned policy, not another agent, mandatory MCP, or replacement coding harness. Conserve, Balanced, and Accelerate are candidate preferences, not proven operating points. They never grant permissions, relax acceptance, or guarantee a provider's external bill.

## Ordered campaign

| Order | Work packages | Plan | Exit evidence |
|---|---|---|---|
| 1 | G01–G03 | [Evidence and accounting foundations](01-foundations.md) | Journal recovery and current-candidate verification regressions pass; generated evidence is mechanically checked. |
| 2 | G04–G06 | [Persistent policy and observation](02-policy-and-observation.md) | Policy resolves reproducibly; IDs and signals reconcile; unsupported controls remain explicit; baseline and trial protocol are frozen. |
| 3 | G07–G10 | [One managed delivery path](03-managed-delivery.md) | One qualified host performs an authorized bounded task through a runnable slice and independent checks, without resetting its budget. |
| 4 | G11–G15 | [Methodology and ecosystem adaptation](04-methodology-and-ecosystem.md) | Leaner methods, routing, context, and interface changes remain individually switchable and preserve their safety/acceptance contracts. |
| 5 | G16–G18 | [Evaluation and controlled rollout](05-evaluation-and-rollout.md) | Held-out results support a declared scope of adoption; otherwise defaults remain unchanged and the result is reported honestly. |

[plan.yaml](plan.yaml) is the canonical assignment/dependency index. Phase documents own acceptance criteria. Do not copy their full text into tracking issues or alternative specifications. This folder is a campaign, not an ESL change folder: each implementation uses the target project's existing right-sizing/lifecycle process when applicable. Nothing here declares a change verified or archived.

The normal first assignment is **G01**. Advance only after predecessor acceptance is recorded. G11, G12, and G14 may proceed in separate repository/worktree lanes after G10; all other ordering follows the manifest. A phase gate requires every package in that phase. A requested assignment does not authorize the harness to implement its successors.

## Delegation

Read [HANDOFF.md](HANDOFF.md) and only the assigned package's phase section. Give the harness a work-package ID, target checkout, and explicit execution/verification allowance. It should inspect the named paths, reproduce the relevant failure, implement the smallest coherent change, run mechanical checks, and return a reviewable PR plus evidence. It must not re-audit the entire ecosystem or write another campaign plan.

For multi-repository integration, use one PR per repository and explicit tested producer/consumer versions. Publish a sibling contract or package before updating nexus pins. Publishing, merging, releases, deployments, external spend, and broad permission changes require separate authorization; this campaign is not that authorization.

## Invariants for every package

- Budget preference never overrides permissions, immutable acceptance, protected tests, user-requested deliverables, or a specialist's current charter. Charter changes require an explicit tested revision.
- Provider allowance, tokens, context occupancy, and estimated money are distinct quantities. Unknown telemetry is not zero and not unlimited. Observed, estimated, self-attested, and unsupported values remain distinguishable.
- All descendants, retries, checker calls, and resumptions inherit a root task's accounting. No fresh allowance through an agent/provider/context switch.
- An existing opt-out project retains current behavior. New behavioral paths remain opt-in until G18. Collectors may fail open; managed dispatch must not silently proceed when its required budget/authority guarantees are unavailable.
- Keep Bash 3.2 compatibility, stdout/stderr discipline, deterministic configuration, no config evaluation, idempotent installation, and host-owned settings preservation. Do not add a runtime dependency without a documented packaging/compatibility decision.
- Do not weaken a test to manufacture a pass, regenerate integrity over unexplained changed evidence, or claim independence from two different labels. Mechanical checks precede LLM review. Cosmetic/out-of-scope improvements do not reopen acceptance.

## Evidence, not paperwork

Use one authoritative machine record per implementation and generate volatile views from it. A passing local check is not a passing CI run; a parsed file is not a validated schema; an authenticated invocation is not proof of semantic correctness. Record actual commands, versions, exit statuses, candidate/criteria identities, and evidence references. Store logs outside the model's working conversation and avoid duplicating counts and hashes in prose.

An unavailable runtime, credential, CI runner, or independent checker is a named blocked check, never an implied pass. Tests described in this plan are planned tests, not execution results.

## Baseline and ownership

The source map below is a starting set, not an exhaustive read list. Re-pin current target SHAs when each assignment begins and reconcile only relevant drift.

| Concern | Starting evidence / owner |
|---|---|
| Experimental journal and completion projection | [ledger.sh at baseline](https://github.com/Rynaro/eidolons/blob/752194ef5ceaa8cee1f5995fd0d374888696d8fc/cli/src/ledger.sh) |
| Existing cost surfaces | [telemetry.sh](../../../cli/src/telemetry.sh), [trace.sh](../../../cli/src/trace.sh), [context.sh](../../../cli/src/context.sh), [context policy](../../../roster/context-policy.yaml) |
| Routing, discovery, and host boundaries | [EIDOLONS.md](../../../EIDOLONS.md), [chain templates](../../../methodology/cortex/chain-templates.md), [harness_hook.sh](../../../cli/src/harness_hook.sh), [README](../../../README.md) |
| Repeated evidence corrections | [archived verification record](https://github.com/Rynaro/eidolons/blob/752194ef5ceaa8cee1f5995fd0d374888696d8fc/.spectra/changes/archive/2026-08-09-chain-scout-debug-fix/verification.md) |
| Actual development gates | [Makefile](../../../Makefile), [CI workflow](../../../.github/workflows/ci.yml), [CLAUDE.md](../../../CLAUDE.md) |
| Methodology revisions | Rynaro/Ramza and Rynaro/Vivi first; other roster members only through the targeted adoption slices in G13. |
| Contract ownership | Rynaro/eidolons-eiis: packaging; Rynaro/eidolons-ecl: envelopes; Rynaro/eidolons-esl and Rynaro/tonberry: lifecycle; Rynaro/eidolons-ecm and Rynaro/atomos: context vocabulary and compose/verify. |
| Optional supporting integrations | Rynaro/Junction, Rynaro/atlas-aci, Rynaro/crystalium, Rynaro/GAMBIT, and Rynaro/magicite. No mandatory new server or frontend. |

Sibling paths named in phase documents were entrypoints examined in the preceding review, not a frozen multi-repository release set. Capture their actual commit and declared contract versions before changing them. Do not copy private client implementation details into this public campaign.

## Explicit non-goals

No model training, quota circumvention, credential scraping, subscription pooling, automatic paid overages, universal dollar/token/quota conversion, new cloud control plane, global renaming campaign, wholesale rewrite, or blanket removal of review. Greenfield remains a separately authorized charter/bootstrap decision; the first managed delivery pilot uses bounded brownfield work.
