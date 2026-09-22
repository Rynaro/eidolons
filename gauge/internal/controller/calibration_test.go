package controller

import (
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func calService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 18, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureInstrumentNamespaces(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureEvaluationNamespaces(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureCalibrationNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func baseDigests() (oracle, perm, accept, auth, manifest string) {
	return "oracle-digest-a", "perm-digest-a", "accept-digest-a", "auth-digest-a", "manifest-digest-a"
}

func baseBaseline(trial, mech string) contract.CalibrationBaseline {
	o, p, a, au, m := baseDigests()
	return contract.CalibrationBaseline{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "base-" + mech, TrialID: trial, MechanismID: mech,
		OracleDigest: o, PermissionDigest: p, AcceptanceDigest: a,
		AuthorityDigest: au, ManifestDigest: m,
		ArmIDs: []string{"arm-on", "arm-off"},
		RecordedAt: "2026-09-22T18:00:00Z",
	}
}

func baseArm(trial, mech, label string) contract.CalibrationArm {
	o, p, a, au, m := baseDigests()
	return contract.CalibrationArm{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "arm-" + label, TrialID: trial, MechanismID: mech, ArmLabel: label,
		OracleDigest: o, PermissionDigest: p, AcceptanceDigest: a,
		AuthorityDigest: au, ManifestDigest: m,
		EligibilityStatus: contract.EligibilityEligible, EligibilityReason: "pending_fill",
		FabricatedMetrics: 0, RecordedAt: "2026-09-22T18:00:00Z",
	}
}

// TestV422T01 — oracle/permission digests constant; weaker acceptance invalidates improvement.
func TestV422T01(t *testing.T) {
	s := calService(t)
	pkgs := map[string]bool{contract.PackageV416: true}
	base, e := s.RecordCalibrationBaseline(baseBaseline("trial-t01", contract.MechLeanPlanning))
	if e != nil {
		t.Fatal(e)
	}
	on := baseArm("trial-t01", contract.MechLeanPlanning, "on")
	out, e := s.RecordCalibrationArm(on, pkgs, &base)
	if e != nil || out.EligibilityStatus != contract.EligibilityEligible {
		t.Fatalf("matched arm: %+v %v", out, e)
	}

	weak := baseArm("trial-t01", contract.MechLeanPlanning, "weak")
	weak.AcceptanceDigest = "accept-digest-weaker"
	out, e = s.RecordCalibrationArm(weak, pkgs, &base)
	if e != nil {
		t.Fatal(e)
	}
	if out.EligibilityStatus != contract.EligibilityIneligible || !out.WeakerAcceptance {
		t.Fatalf("weaker acceptance must invalidate: %+v", out)
	}

	// Missing V4-18 mechanism stays pending — not fabricated zeros.
	missing := baseArm("trial-t01", contract.MechMethodFusionIsolation, "fusion")
	out, e = s.RecordCalibrationArm(missing, pkgs, nil)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Pending || out.EligibilityStatus != contract.EligibilityPending || out.FabricatedMetrics != 0 {
		t.Fatalf("missing mechanism must stay pending not zero: %+v", out)
	}
}

// TestV422T02 — freeze-before-holdout; holdout-driven tuning rejected.
func TestV422T02(t *testing.T) {
	s := calService(t)
	ok := contract.CalibrationBatch{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "batch-1", TrialID: "trial-t02", Split: contract.EvalSplitCalibration,
		ParameterSetID: "params-1", FrozenAt: "2026-09-22T17:00:00Z",
		MemoryControlsOK: true, RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.RecordCalibrationBatch(ok)
	if e != nil || out.Rejected {
		t.Fatalf("calibration batch: %+v %v", out, e)
	}

	holdoutEarly := contract.CalibrationBatch{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "batch-2", TrialID: "trial-t02", Split: contract.EvalSplitHoldout,
		ParameterSetID: "params-2", HoldoutAccessedAt: "2026-09-22T16:00:00Z",
		// FrozenAt empty → reject
		MemoryControlsOK: true, RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordCalibrationBatch(holdoutEarly)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Rejected {
		t.Fatalf("holdout without prior freeze must reject: %+v", out)
	}

	tuned := contract.CalibrationBatch{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "batch-3", TrialID: "trial-t02", Split: contract.EvalSplitCalibration,
		ParameterSetID: "params-3", FrozenAt: "2026-09-22T17:00:00Z",
		HoldoutDrivenTuning: true, MemoryControlsOK: true,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordCalibrationBatch(tuned)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Rejected || out.RejectReason != "holdout_driven_tuning_prohibited" {
		t.Fatalf("holdout-driven tuning prohibited: %+v", out)
	}
}

// TestV422T03 — warm/fresh, escalation, parallel include coordination/checker/rebuild costs.
func TestV422T03(t *testing.T) {
	s := calService(t)
	coord, recon, integ, rebuild := 1.0, 2.0, 3.0, 4.0
	complete := contract.MechanismCostReport{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "cost-1", TrialID: "trial-t03", MechanismID: contract.MechParallelism,
		ClaimBenefit: true,
		CoordinationCost: &coord, ReconstructionCost: &recon,
		IntegrationCheckerCost: &integ, RebuildCost: &rebuild,
		WarmFresh: "warm", StrongFirstEscalation: "strong_first", ParallelCandidates: true,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.PublishMechanismCostReport(complete)
	if e != nil || !out.CostsComplete || !out.ClaimBenefit {
		t.Fatalf("complete costs: %+v %v", out, e)
	}

	incomplete := contract.MechanismCostReport{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "cost-2", TrialID: "trial-t03", MechanismID: contract.MechParallelism,
		ClaimBenefit: true, CoordinationCost: &coord,
		WarmFresh: "fresh", RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.PublishMechanismCostReport(incomplete)
	if e != nil {
		t.Fatal(e)
	}
	if out.ClaimBenefit || out.CostsComplete {
		t.Fatalf("incomplete costs cannot claim benefit: %+v", out)
	}
}

// TestV422T04 — no-win / inconclusive / regression / incomplete-cost stay unpromoted.
func TestV422T04(t *testing.T) {
	s := calService(t)
	for i, verdict := range []string{
		contract.CalVerdictNoWin, contract.CalVerdictInconclusive,
		contract.CalVerdictRegression, contract.CalVerdictIncomplete, contract.CalVerdictNull,
	} {
		d := contract.PromotionDecision{
			SchemaVersion: contract.CalibrationSchemaVersion,
			ID: "promo-" + verdict, TrialID: "trial-t04",
			MechanismID: contract.MechModelEffortRouting,
			Verdict: verdict, PromotionStatus: contract.CalPromotionPromoted, // controller clears
			RecordedAt: "2026-09-22T18:00:00Z",
		}
		out, e := s.DecidePromotion(d)
		if e != nil {
			t.Fatalf("%s: %v", verdict, e)
		}
		if out.PromotionStatus != contract.CalPromotionUnpromoted || out.DefaultFlip {
			t.Fatalf("%s must stay unpromoted without default flip: %+v", verdict, out)
		}
		_ = i
	}

	cherry := contract.PromotionDecision{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "promo-cherry", TrialID: "trial-t04",
		MechanismID: contract.MechModelEffortRouting,
		Verdict: contract.CalVerdictSupported, CherryPickedWinner: true,
		PromotionStatus: contract.CalPromotionPromoted,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.DecidePromotion(cherry)
	if e != nil {
		t.Fatal(e)
	}
	if out.PromotionStatus != contract.CalPromotionUnpromoted || !out.Rejected {
		t.Fatalf("cherry-picked winner forbidden: %+v", out)
	}
}

// TestV422T05 — overspend / unknown exposure / authority / late usage stop dispatch.
func TestV422T05(t *testing.T) {
	s := calService(t)
	budget, spend := 10.0, 12.0
	over := contract.TrialBoundaryStop{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "bound-1", TrialID: "trial-t05", StopReason: contract.CalStopNone,
		ExposureKnown: true, AuthorizedBudget: &budget, ObservedSpend: &spend,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.StopAtTrialBoundary(over)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Stopped || out.FurtherDispatchOK || out.SelfAuthorizedOverage || !out.PartialDataRetained {
		t.Fatalf("overspend must stop without self-overage: %+v", out)
	}

	for _, reason := range []string{
		contract.CalStopUnknownExposure, contract.CalStopAuthorityViolation, contract.CalStopLateUsage,
	} {
		b := contract.TrialBoundaryStop{
			SchemaVersion: contract.CalibrationSchemaVersion,
			ID: "bound-" + reason, TrialID: "trial-t05", StopReason: reason,
			ExposureKnown: reason != contract.CalStopUnknownExposure,
			RecordedAt: "2026-09-22T18:00:00Z",
		}
		out, e = s.StopAtTrialBoundary(b)
		if e != nil {
			t.Fatal(e)
		}
		if !out.Stopped || out.FurtherDispatchOK || !out.PartialDataRetained {
			t.Fatalf("%s must stop and retain partial: %+v", reason, out)
		}
	}
}

// TestV422T06 — same prompt after success vs failed verification; observation≠estimate; no hidden reason.
func TestV422T06(t *testing.T) {
	s := calService(t)
	success := contract.StrategyDecision{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "dec-1", TrialID: "trial-t06", PromptDigest: "prompt-same",
		ObservedState: "verification_passed", StateSource: "observation",
		SelectedAction: "continue_current", AllowedAlternatives: []string{"continue_current", "escalate"},
		PolicyVersion: "policy-v1", DecisionReason: "verification_ok",
		FixedPolicyControl: false, RegisteredOnly: true,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.RecordStrategyDecision(success)
	if e != nil || out.HiddenReasoning || out.StateSource != "observation" {
		t.Fatalf("success decision: %+v %v", out, e)
	}

	pressure := contract.StrategyDecision{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "dec-2", TrialID: "trial-t06", PromptDigest: "prompt-same",
		ObservedState: "context_pressure", StateSource: "observation",
		SelectedAction: "escalate", AllowedAlternatives: []string{"continue_current", "escalate", "compact"},
		PolicyVersion: "policy-v1", DecisionReason: "failed_verification_under_pressure",
		FixedPolicyControl: false, RegisteredOnly: true,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordStrategyDecision(pressure)
	if e != nil || out.SelectedAction == success.SelectedAction {
		t.Fatalf("pressure path must differ from success: %+v %v", out, e)
	}

	fixed := contract.StrategyDecision{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "dec-3", TrialID: "trial-t06", PromptDigest: "prompt-same",
		ObservedState: "any", StateSource: "estimate",
		SelectedAction: "continue_current", AllowedAlternatives: []string{"continue_current"},
		PolicyVersion: "policy-v1-fixed", DecisionReason: "fixed_policy_control",
		FixedPolicyControl: true, RegisteredOnly: true,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordStrategyDecision(fixed)
	if e != nil || !out.FixedPolicyControl || out.StateSource != "estimate" {
		t.Fatalf("fixed-policy control retains estimate label: %+v %v", out, e)
	}
}

// TestV422T07 — failed/stale/self-attested cannot become active; immutable diff inspectable.
func TestV422T07(t *testing.T) {
	s := calService(t)
	ok := contract.AdaptationRecord{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "adapt-1", TrialID: "trial-t07",
		ParentVersion: "strat-v1", ProposedVersion: "strat-v2", RollbackTarget: "strat-v1",
		EvidenceSources: []string{"batch-cal-1"}, AllowedScope: "routing_weights",
		ExperienceQuality: contract.ExpQualified, ImmutableDiff: "diff-sha-abc",
		ActiveRule: true, RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.RecordAdaptationProposal(ok)
	if e != nil || !out.ActiveRule || out.ImmutableDiff == "" {
		t.Fatalf("qualified adaptation: %+v %v", out, e)
	}

	for _, q := range []string{contract.ExpFailed, contract.ExpStale, contract.ExpSelfAttested} {
		bad := contract.AdaptationRecord{
			SchemaVersion: contract.CalibrationSchemaVersion,
			ID: "adapt-" + q, TrialID: "trial-t07",
			ParentVersion: "strat-v1", ProposedVersion: "strat-bad", RollbackTarget: "strat-v1",
			EvidenceSources: []string{"run-x"}, AllowedScope: "routing_weights",
			ExperienceQuality: q, ImmutableDiff: "diff-" + q,
			ActiveRule: true, RecordedAt: "2026-09-22T18:00:00Z",
		}
		out, e = s.RecordAdaptationProposal(bad)
		if e != nil {
			t.Fatal(e)
		}
		if out.ActiveRule || !out.Rejected {
			t.Fatalf("%s must not become active: %+v", q, out)
		}
	}
}

// TestV422T08 — same-batch = adaptation; forward frozen+compute-matched qualifies measured scope.
func TestV422T08(t *testing.T) {
	s := calService(t)
	same := contract.GeneralizationReport{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "gen-1", TrialID: "trial-t08", CandidateID: "cand-1",
		AdaptedOnBatchID: "batch-dev", SameBatchImproved: true,
		MeasuredScope: "batch_dev", RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.ReportGeneralization(same)
	if e != nil {
		t.Fatal(e)
	}
	if out.Label != contract.GenSameBatchAdaptation || out.ClaimsGeneralization {
		t.Fatalf("same-batch must be adaptation not generalization: %+v", out)
	}

	fwd := contract.GeneralizationReport{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "gen-2", TrialID: "trial-t08", CandidateID: "cand-1",
		AdaptedOnBatchID: "batch-dev", SameBatchImproved: true,
		ForwardTaskIDs: []string{"fwd-1", "fwd-2"}, ComputeMatchedControl: true,
		CandidateFrozen: true, MeasuredScope: "forward_pair",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.ReportGeneralization(fwd)
	if e != nil {
		t.Fatal(e)
	}
	if out.Label != contract.GenForwardQualified || !out.ClaimsGeneralization {
		t.Fatalf("frozen forward with matched control qualifies: %+v", out)
	}
}

// TestV422T09 — model/harness/task-distribution change invalidates; unrelated pin retains evidence.
func TestV422T09(t *testing.T) {
	s := calService(t)
	p := contract.PromotedStrategyRegistry{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "strat-1", TrialID: "trial-t09", StrategyVersion: "route-v3",
		SupportedModel: "fixture-model-1", SupportedHarness: "harness-a",
		TaskScope: "calibration-suite", RevalidationConditions: []string{"model", "harness", "task_scope"},
		BenefitClaimValid: true, PinnedConfigID: "pin-a",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.RegisterPromotedStrategy(p)
	if e != nil || !out.BenefitClaimValid {
		t.Fatalf("register: %+v %v", out, e)
	}

	changed, e := s.RevalidatePromotedStrategy(out.ID, "fixture-model-2", "harness-a", "calibration-suite")
	if e != nil {
		t.Fatal(e)
	}
	if changed.BenefitClaimValid || changed.InvalidationReason == "" {
		t.Fatalf("model change must invalidate: %+v", changed)
	}

	other := contract.PromotedStrategyRegistry{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "strat-2", TrialID: "trial-t09", StrategyVersion: "route-v3-other",
		SupportedModel: "other-model-1", SupportedHarness: "harness-b",
		TaskScope: "other-suite", RevalidationConditions: []string{"model"},
		BenefitClaimValid: true, PinnedConfigID: "pin-b",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	kept, e := s.RegisterPromotedStrategy(other)
	if e != nil || !kept.BenefitClaimValid {
		t.Fatalf("unrelated pinned config retains own evidence: %+v %v", kept, e)
	}
}

// TestV422T10 — offline proposals cannot alter oracle/permission/live controller; sandbox skill ok; no self-approve.
func TestV422T10(t *testing.T) {
	s := calService(t)

	// WHERE path: feature enabled, fixture isolation without production self-mod.
	forbid := contract.OfflineAdaptationBoundary{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "off-1", TrialID: "trial-t10", ExperimentEnabled: true,
		EditSurface: contract.OfflineSurfaceSkillConfig,
		TargetsPermissionGate: true, TargetsOracle: true, TargetsLiveController: true,
		SelfApprovedPromotion: true, // controller clears + rejects
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.RecordOfflineAdaptationBoundary(forbid)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Rejected || out.SelfApprovedPromotion || !out.SandboxOnly {
		t.Fatalf("protected surfaces must reject without self-approve: %+v", out)
	}

	allow := contract.OfflineAdaptationBoundary{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "off-2", TrialID: "trial-t10", ExperimentEnabled: true,
		EditSurface: contract.OfflineSurfaceSkillConfig,
		SandboxOnly: true, RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordOfflineAdaptationBoundary(allow)
	if e != nil || out.Rejected || !out.SandboxOnly || out.SelfApprovedPromotion {
		t.Fatalf("allowed skill config stays sandbox-only: %+v %v", out, e)
	}

	// Feature-absent path still records a boundary (WHERE clause completeness).
	absent := contract.OfflineAdaptationBoundary{
		SchemaVersion: contract.CalibrationSchemaVersion,
		ID: "off-3", TrialID: "trial-t10", ExperimentEnabled: false,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordOfflineAdaptationBoundary(absent)
	if e != nil || out.ExperimentEnabled {
		t.Fatalf("disabled experiment boundary: %+v %v", out, e)
	}
}
