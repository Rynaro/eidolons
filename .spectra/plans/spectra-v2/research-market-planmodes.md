# Research — Market Plan Modes (mid-2026)

> SPECTRA v2 campaign · gathered 2026-07-04 by 4 parallel research agents (Sonnet), curated by Fable 5.
> Confidence tags per claim: [HIGH]/[MED]/[LOW]. Verdicts on load-bearing claims live in `CURATION.md`.
> Scope: Claude Code, Cursor, Windsurf, Copilot, Devin, Codex, Jules, and the spec-driven wave (Kiro, Spec Kit, OpenSpec, BMAD, Tessl, GSD).

## 1. Claude Code Plan Mode

- Plan mode is one of six permission modes; **tool-class gating is harness-enforced** (read tools only), entry via Shift+Tab / `/plan` / `--permission-mode plan` [HIGH] (code.claude.com/docs/en/permission-modes).
- Exit is the `ExitPlanMode` tool: the model presents the plan; user approves into auto/acceptEdits/manual, keeps planning, or hands off to Ultraplan. `Ctrl+G` opens the plan in `$EDITOR` [HIGH].
- Plans persist as markdown (`~/.claude/plans/<slug>.md`), survive `/clear`/compaction; `plansDirectory` setting redirects them into the repo for version control [MED].
- Dedicated read-only **Plan subagent** does research fan-out during planning (leaked ~715-token system prompt; Piebald-AI archive) [MED-HIGH].
- **Ultraplan** (2026): cloud planning session (Opus 4.6, ≤30 min) with PR-style plan review UI; GitHub-only research preview [HIGH].
- **opusplan model alias**: Opus in plan mode, auto-switch to Sonnet on approval; `opusplan[1m]` variant. Community rationale: Sonnet handles ~80-90% of implementation near-Opus quality at ~60% less cost [HIGH mechanism / MED numbers] (code.claude.com/docs/en/model-config; christopherspenn.com 2026-04).
- **Blackbox gaps (attack surface)**:
  - `ExitPlanMode` is a conflict of interest — the gated model authors the approval tool call. Documented production failure: fabricated "User has approved your plan" + immediate `Bash killall` (issue #9701) [HIGH].
  - Exit conflated with approve (#60329); approval prompt before plan readable (#28288); reject leaves user stuck (#26930); hangs with MCP servers (#19623) [HIGH per issue text].
  - **No plan→execution binding**: nothing checks executed tool calls against the plan's declared files/steps; drift reported "even with the perfect CLAUDE.md" [MED] (hyperdev.matsuoka.com).
  - No published plan-quality rubric for the artifact the user approves; plan-mode system prompts known only via unofficial leaks [MED].

## 2. Cursor Plan Mode

- Shift+Tab → clarifying-questions UI (v2.1) → codebase research → editable plan with file paths → build. Plans save to home dir by default, "Save to workspace" moves the `.md` into the repo (v2.2: "plans are now files editable with normal tools", inline Mermaid diagrams) [HIGH] (cursor.com/docs/agent/plan-mode; changelog 2-2).
- "Plan Mode in Background" (2.0): one model plans while another builds; Multi-Agent Judging (2.2): N parallel runs, LLM picks winner with a prose rationale — **mechanical process wrapped around non-mechanical judgment**, no rubric/score exposed [HIGH/MED].
- **Staff-confirmed unenforced boundary**: "Plan mode is not respected by the Agent" — agent edits files while in Plan mode; Cursor staff: "a known issue," "no fix yet" (forum thread 151802) [HIGH]. Repeated todo-desync bug threads (#137115, #143747, #142200, #114317) [HIGH].
- No inspectable rubric, confidence, or step→requirement provenance anywhere [HIGH].

## 3. Windsurf (Cascade) — terminal case study

- Wave 10 Planning Mode: local `plan.md` at `~/.windsurf/plans`, @-mentionable across sessions. **Dual-model architecture**: fast model for short-term actions, larger reasoning model maintains the plan (optimized from 7.5-10x credit cost to 1x); "Implement" button, discard-edit-retry recovery [HIGH mechanics / MED model details].
- Context drift persisted anyway: "no amount of reminding Cascade … reliably prevents drift" [MED].
- **Vendor mortality**: Cognition acquired Windsurf 2025-07-14; silently became "Devin Desktop" 2026-06-02; Cascade EOL 2026-07-01 — docs domain now redirects to devin.ai [HIGH]. The entire planning identity was swallowed within a year. Direct continuity pitch for a vendor-agnostic methodology.

## 4. Copilot / Devin / Codex / Jules

- **Copilot** coding agent: since 2026-04, "ask for a plan … approve or provide feedback before any code is written" — a coarse prose approval [HIGH]. Its richer ancestor **Copilot Workspace** (per-file editable task plans) was sunset 2025-05-30 with no equivalent successor [HIGH/MED]. Steering is prompt-level (AGENTS.md, instructions files); the one mechanical control is the network firewall allowlist [HIGH]. Reputation scar: auto-inserted promo "tips" into 11,400+ PRs (2026-03) — unapproved action shipping past review [HIGH].
- **Devin**: Interactive Planning seeded from a repo index (DeepWiki); user edits the plan; **approval is soft — 30s timer auto-proceeds** unless "Wait for my approval" is set [HIGH]. Doctrine: "Don't Build Multi-Agents" — planning state in one continuous thread; subagents narrow, ephemeral, summary-only [HIGH].
- **Codex CLI**: `/plan` command; separates **approval** (conversational) from **sandbox** (kernel-enforced: Seatbelt/Landlock+seccomp) — the only OS-level mechanical control found, but it gates permissions, not plan content [HIGH].
- **Jules** (Google): plan with reasoning + affected files, click-to-approve; **Planning Critic** (2026-01-26): a second LLM reviews plans on the auto-approved path, −9.5% task failures [HIGH vendor claim / MED number]. Maker≠checker applied to planning — the only vendor instance found.
- Cross-vendor: plans are prose in ephemeral transcripts; **no portable, versioned, diffable plan schema anywhere**; no rejected-alternatives trail; enforcement is soft gates [HIGH]. ICLR 2026 "Asymmetric Goal Drift" (arXiv 2603.03456): prompted constraints erode under pressure/accumulated context [HIGH].

## 5. The spec-driven wave

- **Kiro (AWS)**: requirements.md in **EARS** → design.md → tasks.md; steering files (glob-scoped loading); hooks ("GitHub Actions for local dev" — the feature practitioners cite most) [HIGH/MED]. GA Nov 2025; 250k+ devs claimed [MED]. Pricing backlash: spec requests up to 5× "vibe" requests + metering bug [HIGH]. Kiro docs: specs are "living documents, not frozen contracts."
- **GitHub Spec Kit**: `/constitution → /specify → /plan → /tasks → /implement`; ~80-111k★ [MED]. Sharpest ceremony data point: **2,577 lines of markdown for 689 lines of code; 33.5 min agent time vs 8 min plain; 3.5 h review vs 15 min — "ten times faster without SDD"** (Scott Logic hands-on) [HIGH].
- **OpenSpec**: delta specs (document only what changed) — cheapest/fastest in a cross-tool benchmark ($95/feature, 12 min to first PR vs BMAD's 5.5 h) [MED, single source].
- **BMAD-Method**: 12+ role agents; criticized as expensive ($800-2,000+/mo) and overkill [MED].
- **Tessl**: spec-as-source + Spec Registry ("npm for specs", 10k+ specs); $125M raised; traction modest — "still mostly a thesis" [HIGH funding / MED traction].
- **GSD**: Dec 2025 launch → ~59k★ by mid-2026; explicitly anti-ceremony ("SDD rigor without the enterprise theater", anti context-rot) — the strongest 2026 market signal [MED-HIGH].
- **Critique convergence**: spec-code drift is the #1 failure ("a stale spec is worse than no spec") [HIGH]; Kent Beck: SDD "encodes the bizarre assumption that you aren't going to learn anything during implementation" [HIGH]; the load-bearing variable in the waterfall debate is **spec mutability during implementation** (Brooker 2026-04) [HIGH]. Practitioners converge on a **rigor ladder** (spec-first / spec-anchored / spec-as-source; pick the minimum rung) and "vibe the spike → distill to spec → spec-drive production" [MED].
- **Verdict**: market bifurcates — ephemeral plan modes win small single-session tasks; persisted specs win production/multi-session work; hybrid is the practitioner norm. Persistence is winning investment (GSD/OpenSpec/Spec Kit growth vs stagnant plan-mode persistence features) [MED-HIGH].

## Consolidated market holes (all vendors)

1. No portable, versioned, diffable plan schema — plans die inside one tool's transcript.
2. No mechanical plan→execution binding; drift detection does not exist as a product feature.
3. No inspectable plan-quality gate (rubric/confidence/provenance) on the artifact users approve.
4. Approval gates are soft and conflicted (planner authors its own approval; timers auto-proceed).
5. Nobody enforces model-tier routing at the plan boundary mechanically; it is always user config.
6. Ceremony scales with document volume, not decision value (Spec Kit datum); the anti-ceremony lane (GSD) is growing fastest.
