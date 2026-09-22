package controller

import (
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func ramzaService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 22, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureRamzaNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func baseLitePlan(id string) contract.RamzaLitePlan {
	return contract.RamzaLitePlan{
		SchemaVersion:   contract.RamzaSchemaVersion,
		ContractVersion: contract.RamzaMethodContractID,
		ID:              id,
		TaskID:          "task-" + id,
		Mode:            contract.RamzaModeLite,
		MethodVersion:   contract.RamzaMethodLiteV2,
		Outcome:         "ship reversible documentation typo fix",
		Exclusions:      []string{"no API change", "no schema migration"},
		Criteria:        []string{"typo corrected", "existing tests green"},
		Verifier:        "make test-file F=cli/tests/init.bats",
		ChosenApproach:  "edit the single markdown line in place",
		MaterialRisks:   []string{"docs drift if upstream copy diverges"},
		ForcedOptionCount: 0,
		InventedAlternatives: []string{},
		EmbeddedInMaker: true,
		SourceOwner: contract.RamzaCanonicalSourceOwner,
		CanonicalSiblingPreserved: true,
		FileCount: 1,
		FileCountSetsRisk: false,
		RecordedAt: "2026-09-22T22:00:00Z",
	}
}

// TestV416T01 — minimal actionable contract; no forced option count / invented alternatives.
func TestV416T01(t *testing.T) {
	s := ramzaService(t)
	plan, e := s.PlanLite(baseLitePlan("plan-t01"))
	if e != nil {
		t.Fatal(e)
	}
	if plan.Outcome == "" || plan.Verifier == "" || plan.ChosenApproach == "" {
		t.Fatalf("missing required fields: %+v", plan)
	}
	if len(plan.Exclusions) == 0 || len(plan.Criteria) == 0 || len(plan.MaterialRisks) == 0 {
		t.Fatalf("exclusions/criteria/risks required: %+v", plan)
	}
	if plan.ForcedOptionCount != 0 || len(plan.InventedAlternatives) != 0 {
		t.Fatal("must not force option count or invent alternatives")
	}
	if plan.IndependentPlannerClaim || plan.IndependentCritiqueClaim || plan.DefaultFlip {
		t.Fatal("embedded method must not claim independent planner/critique or default flip")
	}
	if plan.ProducerArtifactSource != contract.ProducerSourceFixture &&
		plan.ProducerArtifactSource != contract.ProducerSourceSibling {
		t.Fatalf("producer source required: %s", plan.ProducerArtifactSource)
	}
	if plan.SourceOwner != contract.RamzaCanonicalSourceOwner || !plan.CanonicalSiblingPreserved {
		t.Fatal("Rynaro/Ramza remains canonical; sibling preserved")
	}

	bad := baseLitePlan("plan-t01-bad")
	bad.InventedAlternatives = []string{"rewrite the docs site", "add a hierarchy of options"}
	if _, e := s.PlanLite(bad); e == nil {
		t.Fatal("invented alternatives must be rejected")
	}
	bad2 := baseLitePlan("plan-t01-bad2")
	bad2.ForcedOptionCount = 3
	if _, e := s.PlanLite(bad2); e == nil {
		t.Fatal("forced option count must be rejected")
	}
}

// TestV416T02 — unresolved behavior/authority blocks ready; file count ≠ risk.
func TestV416T02(t *testing.T) {
	s := ramzaService(t)

	// One-file security change still exposes authority decision.
	sec := baseLitePlan("plan-t02-sec")
	sec.Outcome = "tighten one authz check"
	sec.FileCount = 1
	sec.MaterialRisks = []string{"privilege boundary change; small diff is not low risk"}
	plan, e := s.PlanLite(sec)
	if e != nil {
		t.Fatal(e)
	}
	plan, e = s.AttachUnresolvedDecision(plan.ID, contract.UnresolvedDecision{
		ID: "ud-auth", Kind: contract.DecisionAuthority,
		Detail: "whether service account may write secrets", AffectsAuthority: true, BlocksReady: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if _, e := s.MarkPlanReady(plan.ID); e == nil {
		t.Fatal("authority unresolved must block ready")
	}

	// Migration with unresolved behavior.
	mig := baseLitePlan("plan-t02-mig")
	mig.Outcome = "migrate settings key"
	mig.FileCount = 12
	mig.MaterialRisks = []string{"data rewrite on upgrade"}
	plan2, e := s.PlanLite(mig)
	if e != nil {
		t.Fatal(e)
	}
	plan2, e = s.AttachUnresolvedDecision(plan2.ID, contract.UnresolvedDecision{
		ID: "ud-beh", Kind: contract.DecisionBehavior,
		Detail: "whether old keys remain readable", AffectsBehavior: true, BlocksReady: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if _, e := s.MarkPlanReady(plan2.ID); e == nil {
		t.Fatal("behavior unresolved must block ready")
	}

	// Ambiguous product choice.
	prod := baseLitePlan("plan-t02-prod")
	prod.Outcome = "choose default sort order"
	plan3, e := s.PlanLite(prod)
	if e != nil {
		t.Fatal(e)
	}
	plan3, e = s.AttachUnresolvedDecision(plan3.ID, contract.UnresolvedDecision{
		ID: "ud-prod", Kind: contract.DecisionProduct,
		Detail: "ascending vs recently-used default", AffectsBehavior: true, BlocksReady: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if _, e := s.MarkPlanReady(plan3.ID); e == nil {
		t.Fatal("product choice affecting behavior must block ready")
	}

	// Positive control: resolve then ready; file count still does not set risk.
	if _, e := s.ResolveUnresolved(plan.ID, "ud-auth"); e != nil {
		t.Fatal(e)
	}
	ready, e := s.MarkPlanReady(plan.ID)
	if e != nil {
		t.Fatal(e)
	}
	if !ready.ReadyForImplementation || ready.FileCountSetsRisk {
		t.Fatalf("ready without file-count risk: %+v", ready)
	}
}

// TestV416T03 — producer/consumer carry; changed evidence reopens only relevant choice.
func TestV416T03(t *testing.T) {
	s := ramzaService(t)
	plan, e := s.PlanLite(baseLitePlan("plan-t03"))
	if e != nil {
		t.Fatal(e)
	}
	plan, e = s.AttachSettledDecision(plan.ID, contract.SettledDecision{
		ID: "dec-approach", Choice: "in-place edit",
		InvalidationConditions: []string{"acceptance_criteria_changed", "security_boundary_changed"},
		EvidenceFingerprint: "ev-1",
	})
	if e != nil {
		t.Fatal(e)
	}

	carried, e := s.ConsumeSettledDecision(contract.ConsumeDecisionRequest{
		SchemaVersion: contract.RamzaSchemaVersion,
		PlanID: plan.ID, DecisionID: "dec-approach",
		CurrentEvidenceFP: "ev-1",
	})
	if e != nil {
		t.Fatal(e)
	}
	if carried.DuplicateSearchRequired || carried.Decision.Reopened || !carried.ConsumerCarryComplete {
		t.Fatalf("settled carry must not require duplicate search: %+v", carried)
	}

	reopen, e := s.ConsumeSettledDecision(contract.ConsumeDecisionRequest{
		SchemaVersion: contract.RamzaSchemaVersion,
		PlanID: plan.ID, DecisionID: "dec-approach",
		CurrentEvidenceFP: "ev-2", ChangedEvidence: true,
		ChangedCondition: "acceptance_criteria_changed",
	})
	if e != nil {
		t.Fatal(e)
	}
	if !reopen.Decision.Reopened || !reopen.ReopenedOnlyRelevant || !reopen.DuplicateSearchRequired {
		t.Fatalf("changed evidence must reopen only relevant choice: %+v", reopen)
	}
	if reopen.Decision.ReopenReason != "acceptance_criteria_changed" {
		t.Fatalf("reopen reason: %s", reopen.Decision.ReopenReason)
	}
}

// TestV416T04 — score 85 is heuristic, not probability or verification.
func TestV416T04(t *testing.T) {
	s := ramzaService(t)
	plan, e := s.PlanLite(baseLitePlan("plan-t04"))
	if e != nil {
		t.Fatal(e)
	}
	score, e := s.PresentRubricScore(plan.ID, contract.RubricScore{
		ID: "rub-conf", Rubric: "confidence", Score: 85,
	})
	if e != nil {
		t.Fatal(e)
	}
	if score.Label != contract.RubricLabelHeuristic {
		t.Fatalf("expected heuristic label: %s", score.Label)
	}
	if score.IsProbability || score.ProbabilityPercent != nil {
		t.Fatal("85 must not become 85% probability")
	}
	if score.IndependentVerification {
		t.Fatal("rubric score is not independent verification")
	}

	pct := 85.0
	if _, e := s.PresentRubricScore(plan.ID, contract.RubricScore{
		ID: "rub-bad", Rubric: "confidence", Score: 85,
		Label: contract.RubricLabelHeuristic, IsProbability: true, ProbabilityPercent: &pct,
	}); e == nil {
		t.Fatal("probability presentation must be rejected")
	}
}

// TestV416T05 — full/legacy preserve controls; charter change needs versioned amendment.
func TestV416T05(t *testing.T) {
	s := ramzaService(t)

	full, e := s.SelectProfilePackage(contract.ProfilePackage{
		ID: "prof-full", Mode: contract.RamzaModeFull,
		DeclaredControls: []string{"mandatory_alternatives", "hierarchy", "full_risk_matrix"},
		CharterDigest: "full-charter-v1",
	})
	if e != nil {
		t.Fatal(e)
	}
	if full.MethodVersion != contract.RamzaMethodFullV1 || !full.StandaloneCompatible {
		t.Fatalf("full profile preserved: %+v", full)
	}

	legacy, e := s.SelectProfilePackage(contract.ProfilePackage{
		ID: "prof-legacy", Mode: contract.RamzaModeLegacy,
		DeclaredControls: []string{"legacy_gate_order", "prior_section_set"},
		CharterDigest: "legacy-charter-v1", PriorVersion: contract.RamzaMethodLegacyV1,
	})
	if e != nil {
		t.Fatal(e)
	}
	if legacy.MethodVersion != contract.RamzaMethodLegacyV1 || !legacy.CompatibleWithPrior {
		t.Fatalf("legacy compatibility: %+v", legacy)
	}

	if _, e := s.SelectProfilePackage(contract.ProfilePackage{
		ID: "prof-lite-amend", Mode: contract.RamzaModeLite,
		DeclaredControls: []string{"outcome", "criteria", "verifier"},
		CharterDigest: "lite-charter-v2", PriorVersion: "ramza-lite@1",
		CharterChanged: true,
	}); e == nil {
		t.Fatal("changed charter without amendment version must fail")
	}

	amended, e := s.SelectProfilePackage(contract.ProfilePackage{
		ID: "prof-lite-ok", Mode: contract.RamzaModeLite,
		DeclaredControls: []string{"outcome", "criteria", "verifier"},
		CharterDigest: "lite-charter-v2", PriorVersion: "ramza-lite@1",
		CharterChanged: true, AmendmentRequired: true, AmendmentVersion: "lite-amend-2026-09",
	})
	if e != nil {
		t.Fatal(e)
	}
	if amended.MethodVersion != contract.RamzaMethodLiteV2 || !amended.AmendmentRequired {
		t.Fatalf("versioned amendment required: %+v", amended)
	}
}

// TestV416T06 — heuristic activation/retirement; irrelevant task skips; harness change queues reevaluation.
func TestV416T06(t *testing.T) {
	s := ramzaService(t)

	skip, e := s.PublishHeuristic(contract.HeuristicPublication{
		ID: "heur-skip", Name: "skip-invented-alternatives",
		ActivationConditions: []string{"clear_conventional_lite", "reversible_docs"},
		SupportedConfigScope: []string{"ramza-lite@2", "embedded_maker"},
		RetirementTrigger: "model_or_harness_identity_change",
		TaskMatched: false,
	})
	if e != nil {
		t.Fatal(e)
	}
	if skip.Activated || skip.State != contract.HeuristicStateInactive {
		t.Fatalf("irrelevant task must not activate: %+v", skip)
	}

	active, e := s.PublishHeuristic(contract.HeuristicPublication{
		ID: "heur-active", Name: "skip-invented-alternatives",
		ActivationConditions: []string{"clear_conventional_lite"},
		SupportedConfigScope: []string{"ramza-lite@2"},
		RetirementTrigger: "model_or_harness_identity_change",
		TaskMatched: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if !active.Activated || active.State != contract.HeuristicStateActive {
		t.Fatalf("matching task should activate: %+v", active)
	}

	queued, e := s.PublishHeuristic(contract.HeuristicPublication{
		ID: "heur-reval", Name: "skip-invented-alternatives",
		ActivationConditions: []string{"clear_conventional_lite"},
		SupportedConfigScope: []string{"ramza-lite@2"},
		RetirementTrigger: "model_or_harness_identity_change",
		TaskMatched: true, ModelOrHarnessChanged: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if queued.State != contract.HeuristicStateReevaluationQueued || queued.UnqualifiedBenefitClaim {
		t.Fatalf("harness change queues reevaluation without benefit claim: %+v", queued)
	}
}

// TestV416T07 — unsupported assumptions stay unresolved; user-confirmed is positive control.
func TestV416T07(t *testing.T) {
	s := ramzaService(t)
	plan, e := s.PlanLite(baseLitePlan("plan-t07"))
	if e != nil {
		t.Fatal(e)
	}

	unresolved, e := s.RecordAssumption(plan.ID, contract.PlanningAssumption{
		ID: "as-amb", Detail: "ambiguous retry behavior on partial write",
		Status: contract.AssumptionUnresolved, AffectsAcceptance: true,
		AmbiguousBehavior: true, MissingAcceptanceExample: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if unresolved.ConvertedToRequirement || unresolved.Status != contract.AssumptionUnresolved {
		t.Fatalf("must stay unresolved: %+v", unresolved)
	}
	shown, e := s.ShowRamzaPlan(plan.ID)
	if e != nil {
		t.Fatal(e)
	}
	found := false
	for _, a := range shown.Assumptions {
		if a.ID == "as-amb" && a.AmbiguousBehavior && a.MissingAcceptanceExample {
			found = true
		}
	}
	if !found {
		t.Fatal("ambiguous behavior and missing acceptance example must remain visible")
	}
	if _, e := s.MarkPlanReady(plan.ID); e == nil || !strings.Contains(e.Error(), "assumption") {
		t.Fatalf("acceptance-affecting unresolved assumption must block ready: %v", e)
	}

	confirmed, e := s.RecordAssumption(plan.ID, contract.PlanningAssumption{
		ID: "as-ok", Detail: "user confirmed overwrite-on-conflict behavior",
		Status: contract.AssumptionUserConfirmed, AffectsAcceptance: true,
	})
	if e != nil {
		t.Fatal(e)
	}
	if confirmed.Status != contract.AssumptionUserConfirmed {
		t.Fatal("user-confirmed is the positive control")
	}

	// Clear blocking assumption by resolving status via replacement record on same id is not allowed
	// (identity conflict). Instead mark ready only after removing effect: re-plan without it.
	s2 := ramzaService(t)
	clean, e := s2.PlanLite(baseLitePlan("plan-t07b"))
	if e != nil {
		t.Fatal(e)
	}
	if _, e := s2.RecordAssumption(clean.ID, contract.PlanningAssumption{
		ID: "as-ok2", Detail: "user confirmed overwrite-on-conflict behavior",
		Status: contract.AssumptionUserConfirmed, AffectsAcceptance: true,
	}); e != nil {
		t.Fatal(e)
	}
	ready, e := s2.MarkPlanReady(clean.ID)
	if e != nil {
		t.Fatal(e)
	}
	if !ready.ReadyForImplementation {
		t.Fatal("user-confirmed assumption allows ready")
	}
}
