# Research-to-requirements record — September 21, 2026

## Interpretation and provenance

This is a bounded design synthesis of the preceding 30-source conceptual research and a targeted recheck of the primary sources below. It is not an exhaustive literature review, an independent reproduction, or measured Eidolons performance. The stage tables are the only requirement-text authority. This record explains choices; it does not add unnumbered acceptance obligations.

Evidence categories remain separate: a published specification describes an interface; an engineering account reports its author's system; a research experiment supports results under its tested conditions. None establishes that an installed host implements a feature or that Eidolons inherits a reported improvement. Exact runtime versions, permissions, billing eligibility and support maturity are checked in V4-09/V4-12, not frozen by a research URL.

## Evidence-to-design map

| Source, version inspected | Supported mechanism and limitation | Eidolons design decision / requirement links |
|---|---|---|
| [Alistair Mavin: EARS](https://alistairmavin.com/ears/) · accessed 2026-09-21 | Condition/trigger/system/response patterns improve requirements structure. EARS permits multiple responses and is not a test runner. | Preserve EARS; one SHALL per row is this campaign's convention. HANDOFF.md separates authored/planned/executed evidence. |
| [Anthropic: Managed Agents architecture](https://www.anthropic.com/engineering/managed-agents) · accessed 2026-09-21 | Durable session, harness and sandbox can be separated. First-party architecture account, not a comparative superiority test. | Separate task/process/context/environment continuity: V4-06-R07–R09; V4-12-R09; V4-15-R05/R08. |
| [LangGraph functional API](https://docs.langchain.com/oss/python/langgraph/functional-api) · accessed 2026-09-21 | Checkpoints support replay; unfinished side effects may execute again and need idempotency/reconciliation. Documentation, not our conformance evidence. | Preserve durable intents and uncertain effects: V4-12-R01/R02/R07; V4-15-R10. No mandatory LangGraph dependency. |
| [SkillsBench](https://arxiv.org/abs/2602.12670) · v4, 2026-06-14 | Curated procedural skills help in tested settings; task, skill and harness selection constrain generalization. | Version method activation and applicability, not a universal skill-benefit claim: V4-16-R06; V4-18-R06/R07; V4-22-R09. |
| [Subagents vs Agent Skills](https://arxiv.org/abs/2609.09233) · v1, 2026-09-07 | Isolated skill execution can reduce parent context pressure when the interface is suitable; communication overhead remains. Preliminary research. | Treat skill and worker as distinct choices: V4-13-R01/R02/R07/R08; V4-18-R06; V4-22-R03. |
| [Google: science of scaling agent systems](https://research.google/blog/towards-a-science-of-scaling-agent-systems-when-and-why-agent-systems-work/) · accessed 2026-09-21 | Coordination value depends on task structure; parallel and sequential work behave differently. Not a coding-agent-count prescription. | Require a reason for extra execution and account integration: V4-11-R08; V4-13-R02/R09; V4-22-R03. |
| [Recursive Language Models](https://arxiv.org/abs/2512.24601) · v3, 2026-05-11 | External programmable context permits selective inspection/recursion; cost, navigation and evaluation limitations remain. | Make information access bounded and accountable, not mandatory recursion: V4-19-R02/R10/R11/R12. |
| [Anthropic: code execution with MCP](https://www.anthropic.com/engineering/code-execution-with-mcp) · accessed 2026-09-21 | On-demand interfaces and programmatic filtering can reduce model-context traffic. Illustrative savings are not universal. | Actual payload measurement and unchanged permissions for batches: V4-19-R05/R07/R11. |
| [MemoryArena](https://arxiv.org/abs/2602.16313) · v2, 2026-09-17 | Tests memory-guided action across tasks, not recall alone. The abstract/version were rechecked; v2 supersedes the earlier research record's v1 reference. | Evaluate scoped memory through relevant behavior; reject stale/foreign claims: V4-19-R04/R08/R09; V4-21-R03. |
| [Agentic Context Engineering](https://arxiv.org/abs/2510.04618) · v3, 2026-03-29 | Incremental context/playbook curation is an adaptation mechanism; reflection quality and noisy feedback constrain it. | Version source-linked proposals and revalidate applicability: V4-19-R08/R09; V4-22-R07/R09/R10. No automatic policy promotion. |
| [HarnessDev](https://arxiv.org/abs/2609.01437) · v1, 2026-09-01 | Harness creation/evolution results are domain-dependent; reported evolution is unstable with partial transfer. Abstract/version rechecked. | Offline evolution remains optional; separate batch adaptation from future transfer: V4-22-R07–R10. |
| [CaMeL](https://arxiv.org/abs/2503.18813) · v2, 2025-06-24 | Capability/control/data-flow enforcement is a scoped defense, not a universal semantic-injection solution. | Keep authority outside retrieved/model text and enforce actual boundaries: V4-07-R03/R07/R08; V4-12-R08; V4-14-R02; V4-19-R05. |
| [Anthropic: demystifying agent evaluations](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) · accessed 2026-09-21 | Grader design, outcome definitions and repeated-trial metrics affect interpretation. Engineering guidance, not Eidolons results. | Oracle qualification, known-outcome controls and separate selection/reliability metrics: V4-14-R07–R10; V4-21-R05–R09. |
| [MCP specification](https://modelcontextprotocol.io/specification/2026-07-28) · 2026-07-28 | Describes tool/resource/prompt exchange. Specification support does not establish installed-host compatibility or authority. | Pin interface/method/version and fail closed on unsupported controls: V4-09-R01/R08/R09; V4-12-R06/R08. |
| [Agent Client Protocol](https://agentclientprotocol.com/get-started/introduction) · accessed 2026-09-21 | Coding-agent/client interoperability boundary, not general runtime semantic equivalence. | Preserve exact consumer contracts: V4-10-R04; V4-20-R05/R07. No obligatory ACP migration. |
| [A2A task lifecycle](https://a2a-protocol.org/latest/topics/life-of-a-task/) · accessed 2026-09-21 | Client acceptance of returned artifacts remains separate from protocol task completion. | Do not promote transport completion to acceptance: V4-05-R07; V4-20-R01. No obligatory A2A migration. |

## Synthesis decisions, not claims taken verbatim from research

**Proof before broad migration.** Deliver an early recorder in V4-09 and observable demonstrator in V4-15; run V4-21 before broad adoption. This is our sequencing decision, not a benchmark conclusion. Preservation of original/control arms and truthful pending arms makes it possible to find no advantage.

**Stable authority, adaptive methods.** Memory, models and consultants may propose changes. Trusted field authorization, protected acceptance and active controller logic are not self-editable by the task worker. Offline adaptation is a separately bounded optional mechanism; it must not become a prerequisite for starting v4.

**Acceptance integrity and adequacy are different.** A protected checker can faithfully execute inadequate tests. The design therefore calls for representative acceptable and defective candidates, observable application behavior, and an explicit blocker for ambiguous acceptance—not a claim of exhaustive correctness.

**Measure the trajectory.** Keep compatible resource units, provenance and unknown coverage visible. Include failures, checker work, reconstruction, indexes, integration, cancellation/recovery and human interventions when applicable. Lower per-call price or lower context size alone is not a demonstrated delivery improvement.

**Retain falsifiability.** Compare strong feasible controls under predeclared constraints. Treat model/harness/environment differences as confounds unless isolated; preserve untouched evaluation data; report no-win/inconclusive findings without changing defaults. A correctness benefit and a performance benefit are separate possible outcomes.

## Deferred or rejected extrapolations

No universal superiority claim for native or custom harnesses, isolated or inline skills, continuing or fresh context, strong-first or escalating models. No benchmark percentage becomes a preset threshold. No unlimited-context promise, automatic truth from memory, protocol-implied trust, self-authorized evolutionary deployment, or gold-patch smoke counted as model capability.

The research motivates controlled experiments within the authored campaign. Additional models, orchestration frameworks, managed vendor APIs, indexes, recursive runtimes and optional memory systems require a justified scope decision rather than automatic inclusion.
