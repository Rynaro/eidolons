package controller

import (
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func evalService(t *testing.T) *Service {
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
	return s
}

func freezeEvalProtocol(t *testing.T, s *Service, id string, arms ...contract.ProtocolArm) contract.FrozenProtocol {
	t.Helper()
	if len(arms) == 0 {
		arms = []contract.ProtocolArm{
			matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
			matchedArm("v3", contract.ArmOriginalV3, contract.OriginalV3ControlSHA),
			matchedArm("v4", contract.ArmManaged, "v4-fixed-model-control"),
			matchedArm("structural", contract.ArmStructural, "structural-placeholder"),
		}
	}
	proto := syntheticProtocol(id, arms...)
	frozen, _, e := s.FreezeProtocol(proto)
	if e != nil {
		t.Fatal(e)
	}
	return frozen
}

func baseEvalArm(trial, protocol, digest, armID, role, control string) contract.EvalArmIdentity {
	return contract.EvalArmIdentity{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "armrec-" + armID, TrialID: trial, ProtocolID: protocol, ProtocolDigest: digest,
		ArmID: armID, Role: role,
		RequestedModel: "fixture-model@1", ObservedModel: "fixture-model@1",
		HarnessIdentity: "harness-fixture", PolicyIdentity: "policy-fixture",
		EnvironmentIdentity: "env-fixture", AcceptanceIdentity: "accept-fixture",
		BillingIdentity: "billing-none", ControlIdentity: control,
		Split: contract.EvalSplitHoldout,
		EligibilityStatus: contract.EligibilityEligible, EligibilityReason: "pending_fill",
		FabricatedMetrics: 0, RecordedAt: "2026-09-22T18:00:00Z",
	}
}

func evalAttempt(proto contract.FrozenProtocol, armID, kind, task, id, terminal, acceptance string, cost float64, opts func(*contract.EvalAttempt)) contract.EvalAttempt {
	base := baseAttempt(proto, armID, kind, task, id, terminal, acceptance, cost)
	a := contract.EvalAttempt{
		AttemptRecord: base,
		ExposureKnown: true,
		Split:         contract.EvalSplitHoldout,
		ZeroAcceptance: acceptance == contract.AcceptanceNone,
		Cancelled:     terminal == contract.TerminalCancelled,
		Abandoned:     terminal == contract.TerminalAbandoned,
	}
	if opts != nil {
		opts(&a)
	}
	return a
}

// TestV421T01 — requested-vs-observed model, mismatched arm, pinned controls; expose confounds.
func TestV421T01(t *testing.T) {
	s := evalService(t)
	proto := freezeEvalProtocol(t, s, "proto-t01")
	pkgs := map[string]bool{contract.PackageV415: true}
	pinned := map[string]string{
		"harness": "harness-fixture", "policy": "policy-fixture",
		"environment": "env-fixture", "acceptance": "accept-fixture",
		"billing": "billing-none", "control": contract.NativeControlIdentity, "model": "fixture-model@1",
	}

	ok := baseEvalArm("trial-t01", proto.ID, proto.CanonicalDigest, "native", contract.EvalRoleNative, contract.NativeControlIdentity)
	out, e := s.RecordEvalArmIdentity(ok, pkgs, pinned)
	if e != nil {
		t.Fatal(e)
	}
	if out.ModelMismatch || len(out.Confounds) != 0 {
		t.Fatalf("pinned match should have no confounds: %+v", out)
	}

	mismatch := baseEvalArm("trial-t01", proto.ID, proto.CanonicalDigest, "native-mm", contract.EvalRoleNative, contract.NativeControlIdentity)
	mismatch.ID = "armrec-native-mm"
	mismatch.RequestedModel = "requested-model@A"
	mismatch.ObservedModel = "observed-model@B"
	out, e = s.RecordEvalArmIdentity(mismatch, pkgs, pinned)
	if e != nil {
		t.Fatal(e)
	}
	if !out.ModelMismatch {
		t.Fatal("requested≠observed must set model_mismatch")
	}
	found := false
	for _, c := range out.Confounds {
		if c == "requested_vs_observed_model" || c == "pin_mismatch:model" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected model confounds, got %v", out.Confounds)
	}

	pinBad := baseEvalArm("trial-t01", proto.ID, proto.CanonicalDigest, "native-pin", contract.EvalRoleNative, contract.NativeControlIdentity)
	pinBad.ID = "armrec-native-pin"
	pinBad.HarnessIdentity = "harness-other"
	out, e = s.RecordEvalArmIdentity(pinBad, pkgs, pinned)
	if e != nil {
		t.Fatal(e)
	}
	pinFound := false
	for _, c := range out.Confounds {
		if c == "pin_mismatch:harness" {
			pinFound = true
		}
	}
	if !pinFound {
		t.Fatalf("expected harness pin mismatch: %v", out.Confounds)
	}

	// Structural without V4-10 stays pending — not fabricated zeros.
	st := baseEvalArm("trial-t01", proto.ID, proto.CanonicalDigest, "structural", contract.EvalRoleStructural, "structural-placeholder")
	st.Split = contract.EvalSplitDevelopment
	out, e = s.RecordEvalArmIdentity(st, pkgs, nil)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Pending || out.EligibilityStatus != contract.EligibilityPending || out.FabricatedMetrics != 0 {
		t.Fatalf("structural must stay pending not zero: %+v", out)
	}

	v3 := baseEvalArm("trial-t01", proto.ID, proto.CanonicalDigest, "v3", contract.EvalRoleOriginalV3, contract.OriginalV3ControlSHA)
	if _, e = s.RecordEvalArmIdentity(v3, pkgs, nil); e != nil {
		t.Fatal(e)
	}
	v4 := baseEvalArm("trial-t01", proto.ID, proto.CanonicalDigest, "v4", contract.EvalRoleV4FixedModel, "v4-fixed-model-control")
	if _, e = s.RecordEvalArmIdentity(v4, pkgs, nil); e != nil {
		t.Fatal(e)
	}
}

// TestV421T02 — failures/abandon/cancel/timeout/checking/zero acceptance; undefined≠zero; unknown blocks complete-cost.
func TestV421T02(t *testing.T) {
	s := evalService(t)
	proto := freezeEvalProtocol(t, s, "proto-t02",
		matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
	)

	// Vector Z-like: all failed/cancelled/abandoned → undefined ratio, not zero.
	for _, a := range []contract.EvalAttempt{
		evalAttempt(proto, "native", contract.ArmNative, "task-a", "a1", contract.TerminalFailed, contract.AcceptanceNone, 2, nil),
		evalAttempt(proto, "native", contract.ArmNative, "task-a", "a2", contract.TerminalCancelled, contract.AcceptanceNone, 1, func(a *contract.EvalAttempt) {
			a.Timeout = true
		}),
		evalAttempt(proto, "native", contract.ArmNative, "task-b", "b1", contract.TerminalAbandoned, contract.AcceptanceNone, 3, nil),
	} {
		if _, e := s.RecordEvalAttempt(a, false); e != nil {
			t.Fatal(e)
		}
	}
	sum, e := s.ComputeEvalCost(proto.ID)
	if e != nil {
		t.Fatal(e)
	}
	if sum.RatioDefined || sum.CostPerAccepted != nil || !sum.UndefinedRatioNotZero {
		t.Fatalf("undefined ratio must not be zero: %+v", sum)
	}
	if sum.CompleteCostClaim || len(sum.CompleteCostBlockedBy) == 0 {
		t.Fatalf("complete-cost must be blocked: %+v", sum)
	}
	if sum.TimeoutCount != 1 || sum.CancelledCount < 1 || sum.AbandonedCount < 1 {
		t.Fatalf("timeout/cancel/abandon counts: %+v", sum)
	}

	// Unknown exposure blocks complete-cost even with acceptances.
	s2 := evalService(t)
	proto2 := freezeEvalProtocol(t, s2, "proto-t02u",
		matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
	)
	unk := evalAttempt(proto2, "native", contract.ArmNative, "task-a", "u1", contract.TerminalCompleted, contract.AcceptanceAccepted, 4, func(a *contract.EvalAttempt) {
		a.CostKind = contract.CostUnknown
		a.CostAmount = nil
		a.ExposureKnown = false
		a.CheckingCostKind = contract.CostUnknown
	})
	if _, e := s2.RecordEvalAttempt(unk, false); e != nil {
		t.Fatal(e)
	}
	sum2, e := s2.ComputeEvalCost(proto2.ID)
	if e != nil {
		t.Fatal(e)
	}
	if sum2.CompleteCostClaim {
		t.Fatal("unknown exposure must block complete-cost claim")
	}
	blocked := map[string]bool{}
	for _, b := range sum2.CompleteCostBlockedBy {
		blocked[b] = true
	}
	if !blocked["unknown_exposure"] && !blocked["unknown_attempt_cost"] {
		t.Fatalf("expected unknown blockers: %v", sum2.CompleteCostBlockedBy)
	}

	// Pending arm must not fabricate metrics.
	pending := evalAttempt(proto2, "structural", contract.ArmStructural, "task-x", "p1", contract.TerminalFailed, contract.AcceptanceNone, 0, nil)
	if _, e := s2.RecordEvalAttempt(pending, true); e == nil {
		t.Fatal("pending arm fabricated attempt must reject")
	}
}

// TestV421T03 — holdout isolation; leakage canaries; tuning failures = development.
func TestV421T03(t *testing.T) {
	s := evalService(t)
	isolated := contract.HoldoutBoundary{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "hold-1", TrialID: "trial-h", TaskID: "task-h1",
		Split: contract.EvalSplitHoldout,
		LeakageCanaries: []string{"canary-answer-token", "canary-patch-digest"},
		Isolated: true, RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.RecordHoldoutBoundary(isolated)
	if e != nil || !out.Isolated {
		t.Fatalf("isolated holdout: %+v %v", out, e)
	}

	leaky := contract.HoldoutBoundary{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "hold-2", TrialID: "trial-h", TaskID: "task-h2",
		Split: contract.EvalSplitHoldout,
		MakerMemoryAccessible: true,
		LeakageCanaries: []string{"canary-answer-token"},
		CanaryTriggered: []string{"canary-answer-token"},
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordHoldoutBoundary(leaky)
	if e != nil {
		t.Fatal(e)
	}
	if out.Isolated {
		t.Fatal("maker memory + triggered canary must not be isolated")
	}

	tuning := contract.HoldoutBoundary{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "hold-3", TrialID: "trial-h", TaskID: "task-h3",
		Split: contract.EvalSplitHoldout,
		LeakageCanaries: []string{"canary-x"},
		Isolated: true,
		TuningFailureMaterial: "route-weight-tweak",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.RecordHoldoutBoundary(tuning)
	if e != nil {
		t.Fatal(e)
	}
	if out.TuningFailureMaterial == "" || out.TuningFailureMaterial[:len(contract.EvalSplitDevelopment)] != contract.EvalSplitDevelopment {
		t.Fatalf("tuning failure must become development material: %q", out.TuningFailureMaterial)
	}
}

// TestV421T04 — gold patch / simulated host = plumbing; smoke vs live; credentials blocked.
func TestV421T04(t *testing.T) {
	s := evalService(t)
	gold := contract.PlumbingEvidence{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "plumb-1", TrialID: "trial-p", RunID: "run-1",
		UsesGoldPatch: true, EvidenceClass: contract.EvidenceClassModelCapability,
		Discriminator: contract.EvidenceClassSmoke, RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.ClassifyPlumbingEvidence(gold)
	if e != nil {
		t.Fatal(e)
	}
	if out.EvidenceClass != contract.EvidenceClassPlumbing {
		t.Fatalf("gold patch must be plumbing, got %s", out.EvidenceClass)
	}
	if out.Discriminator != contract.EvidenceClassSmoke || !out.LiveBlocked {
		t.Fatalf("smoke discriminator must keep live blocked: %+v", out)
	}

	sim := contract.PlumbingEvidence{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "plumb-2", TrialID: "trial-p", RunID: "run-2",
		UsesSimulatedHost: true, Discriminator: contract.EvidenceClassSmoke,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.ClassifyPlumbingEvidence(sim)
	if e != nil || out.EvidenceClass != contract.EvidenceClassPlumbing {
		t.Fatalf("simulated host plumbing: %+v %v", out, e)
	}

	liveBlocked := contract.PlumbingEvidence{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "plumb-3", TrialID: "trial-p", RunID: "run-3",
		EvidenceClass: contract.EvidenceClassLive, Discriminator: contract.EvidenceClassLive,
		CredentialsPresent: true, CredentialsUsable: false,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.ClassifyPlumbingEvidence(liveBlocked)
	if e != nil || !out.LiveBlocked {
		t.Fatalf("unusable credentials must block live: %+v %v", out, e)
	}
}

// TestV421T05 — completion/latency/interventions/quality with uncertainty; recomputation; censored/small; delayed-rework.
func TestV421T05(t *testing.T) {
	s := evalService(t)
	comp := 0.5
	runLat := 1200.0
	totLat := 5000.0
	qual := 0.8
	m := contract.EvalReportMetrics{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "rep-1", TrialID: "trial-r", ProtocolID: "proto-r",
		CompletionRate: &comp, RunnableLatencyMS: &runLat, TotalLatencyMS: &totLat,
		Interventions: 2, InvalidAcceptance: 1, QualityReviewPass: &qual,
		SampleSize: 4, CensoredCount: 1,
		DelayedReworkWindow: "7d",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.PublishEvalReport(m)
	if e != nil {
		t.Fatal(e)
	}
	if !out.SmallSample || !out.IndependentRecomputable || out.RecomputationDigest == "" {
		t.Fatalf("report flags: %+v", out)
	}
	again, e := contract.RecomputeReportMetricsDigest(out)
	if e != nil || again != out.RecomputationDigest {
		t.Fatalf("independent recomputation mismatch: %s vs %s", again, out.RecomputationDigest)
	}
	if out.Uncertainty == "" || out.DelayedReworkWindow != "7d" {
		t.Fatalf("uncertainty/window: %+v", out)
	}
}

// TestV421T06 — underspecified/over-restrictive/inadequate vs valid; post-outcome exclusion audit+sensitivity.
func TestV421T06(t *testing.T) {
	s := evalService(t)
	valid := contract.TaskAdmission{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "adm-valid", TrialID: "trial-a", TaskID: "task-valid",
		RequirementStatus: contract.ReqValid, OracleQualification: contract.OracleQualified,
		ExclusionStatus: contract.ExclusionNone, AuditTrail: []string{"admit"},
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.AdmitEvaluationTask(valid)
	if e != nil || !out.Admitted {
		t.Fatalf("valid admit: %+v %v", out, e)
	}

	for _, status := range []string{contract.ReqUnderspecified, contract.ReqOverRestrictive, contract.ReqInadequateCover} {
		bad := contract.TaskAdmission{
			SchemaVersion: contract.EvaluationSchemaVersion,
			ID: "adm-" + status, TrialID: "trial-a", TaskID: "task-" + status,
			RequirementStatus: status, OracleQualification: contract.OracleQualified,
			ExclusionStatus: contract.ExclusionNone, AuditTrail: []string{"reject"},
			RecordedAt: "2026-09-22T18:00:00Z",
		}
		out, e = s.AdmitEvaluationTask(bad)
		if e != nil || out.Admitted {
			t.Fatalf("%s must not admit: %+v %v", status, out, e)
		}
	}

	post := contract.TaskAdmission{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "adm-post", TrialID: "trial-a", TaskID: "task-post",
		RequirementStatus: contract.ReqValid, OracleQualification: contract.OracleQualified,
		ExclusionStatus: contract.ExclusionPostOutcome, PostOutcomeExclusion: true,
		ExclusionReason: "oracle_defect_after_outcome",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.AdmitEvaluationTask(post)
	if e != nil {
		t.Fatal(e)
	}
	if out.Admitted || len(out.AuditTrail) == 0 || len(out.SensitivityResults) == 0 {
		t.Fatalf("post-outcome exclusion needs audit+sensitivity: %+v", out)
	}
}

// TestV421T07 — material env/permission drift → confounded; diffs not hidden in averages.
func TestV421T07(t *testing.T) {
	s := evalService(t)
	clean := contract.EnvironmentDrift{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "drift-0", TrialID: "trial-d", ProtocolID: "proto-d", ArmID: "arm-a",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.FlagEnvironmentDrift(clean)
	if e != nil || out.Confounded || out.Material {
		t.Fatalf("no diffs: %+v %v", out, e)
	}

	drift := contract.EnvironmentDrift{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "drift-1", TrialID: "trial-d", ProtocolID: "proto-d", ArmID: "arm-b",
		ResourceGuarantee: "cpu:2≠1", CeilingDiff: "tokens:lower",
		NetworkDiff: "egress-allowed", CacheDiff: "warm≠cold",
		TimeoutDiff: "60s≠30s", SandboxDiff: "privileged≠sandboxed",
		PermissionDiff: "write≠readonly",
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.FlagEnvironmentDrift(drift)
	if e != nil {
		t.Fatal(e)
	}
	if !out.Material || !out.Confounded || out.HiddenInAverages {
		t.Fatalf("material drift must confound and not hide: %+v", out)
	}
	if len(out.DiffLabels) < 6 {
		t.Fatalf("expected resource/ceiling/network/cache/timeout/sandbox/permission labels: %v", out.DiffLabels)
	}
}

// TestV421T08 — candidate vs selection vs autonomous vs reliability; cancelled pass ≠ identical.
func TestV421T08(t *testing.T) {
	s := evalService(t)
	rel := 0.75
	auto := contract.OutcomeDistinction{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "out-1", TrialID: "trial-o", RunID: "run-1",
		CandidateSuccess: true, SelectionSuccess: true, AutonomousComplete: true,
		RepeatedReliability: &rel,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.DistinguishOutcomes(auto)
	if e != nil {
		t.Fatal(e)
	}
	if out.OperationalOutcome != contract.OutcomeAutonomousCompletion {
		t.Fatalf("autonomous should win priority: %s", out.OperationalOutcome)
	}

	cancelPass := contract.OutcomeDistinction{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "out-2", TrialID: "trial-o", RunID: "run-2",
		CandidateSuccess: true, PassingPatchInCancel: true,
		IdenticalClaim: true, // controller must clear
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.DistinguishOutcomes(cancelPass)
	if e != nil {
		t.Fatal(e)
	}
	if out.IdenticalClaim || out.OperationalOutcome != contract.OutcomeCancelledWithPass {
		t.Fatalf("cancelled pass must not be identical operational outcome: %+v", out)
	}

	search := contract.OutcomeDistinction{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "out-3", TrialID: "trial-o", RunID: "run-3",
		CandidateSuccess: true, SuccessAmongFailures: true,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e = s.DistinguishOutcomes(search)
	if e != nil {
		t.Fatal(e)
	}
	if out.IdenticalClaim || out.OperationalOutcome != contract.OutcomeSearchAmongFailures {
		t.Fatalf("search success among failures distinct: %+v", out)
	}
}

// TestV421T09 — holdout-influenced material removed from untouched; forward inaccessible until frozen.
func TestV421T09(t *testing.T) {
	s := evalService(t)
	p := contract.PromotionSet{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "promo-1", TrialID: "trial-pr", CandidateID: "cand-1",
		UntouchedMembers: []string{"task-a", "task-b", "task-holdout-feedback"},
		InfluencedByHoldout: []string{"task-holdout-feedback"},
		PlaybookAdjustments: []string{"task-holdout-feedback"},
		CandidateFrozen: false,
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	out, e := s.UpdatePromotionSet(p)
	if e != nil {
		t.Fatal(e)
	}
	for _, u := range out.UntouchedMembers {
		if u == "task-holdout-feedback" {
			t.Fatal("holdout-influenced material must leave untouched set")
		}
	}
	foundDev := false
	for _, d := range out.DevelopmentMembers {
		if d == "task-holdout-feedback" {
			foundDev = true
		}
	}
	if !foundDev {
		t.Fatalf("playbook adjustment must be development: %+v", out)
	}
	if out.ForwardAccessible || out.ForwardStatus != contract.PromotionInaccessible {
		t.Fatalf("forward must stay inaccessible until frozen: %+v", out)
	}

	frozen := out
	frozen.ID = "promo-2"
	frozen.CandidateFrozen = true
	frozen.ForwardStatus = ""
	out2, e := s.UpdatePromotionSet(frozen)
	if e != nil {
		t.Fatal(e)
	}
	if !out2.ForwardAccessible || !out2.CandidateFrozen {
		t.Fatalf("after freeze forward may open: %+v", out2)
	}
}

// TestV421PaidTrialWithoutAllowance — no paid trial without allowance.
func TestV421PaidTrialWithoutAllowance(t *testing.T) {
	s := evalService(t)
	proto := freezeEvalProtocol(t, s, "proto-paid",
		matchedArm("native", contract.ArmNative, contract.NativeControlIdentity),
	)
	bad := contract.EvaluationTrial{
		SchemaVersion: contract.EvaluationSchemaVersion,
		ID: "trial-paid", ProtocolID: proto.ID, ProtocolDigest: proto.CanonicalDigest,
		PaidTrial: true, BillingAuthorized: false, LiveBlocked: true,
		ArmIDs: []string{"native"}, SplitsPresent: []string{contract.EvalSplitHoldout},
		RecordedAt: "2026-09-22T18:00:00Z",
	}
	if _, e := s.StartEvaluationTrial(bad); e == nil {
		t.Fatal("paid trial without allowance must reject")
	}
	ok := bad
	ok.ID = "trial-paid-ok"
	ok.BillingAuthorized = true
	ok.AllowanceRef = "allowance-fixture-1"
	if _, e := s.StartEvaluationTrial(ok); e != nil {
		t.Fatal(e)
	}
}
