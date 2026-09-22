package controller

import (
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func delService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 20, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureDeliveryNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func delRoot(t *testing.T, s *Service, id string) {
	t.Helper()
	if e := s.InitRoot(id); e != nil {
		t.Fatal(e)
	}
}

func baseDelivery(loop, root, cand string) contract.DeliveryRunRequest {
	return contract.DeliveryRunRequest{
		SchemaVersion:       contract.DeliverySchemaVersion,
		LoopID:              loop,
		RootID:              root,
		AssignmentID:        "asg-" + loop,
		AuthoritySufficient: true,
		InputsSufficient:    true,
		CandidateID:         cand,
		MilestoneKind:       contract.MilestoneGenuineBehavior,
		ResourceBudget:      100,
		MandatoryCost:       10,
		VerificationCost:    5,
		FailureBound:        2,
		SkipDispatch:        true,
		AccessRestrictions:  []string{"deny:secrets.write"},
		RecordedAt:          "2026-09-22T20:00:00Z",
	}
}

// TestV415T01 — bounded assignment progresses without routine continuation prompts.
func TestV415T01(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t01")

	loop, e := s.RunDeliveryLoop(baseDelivery("loop-t01", "root-t01", "cand-t01"), nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if !loop.Accepted || loop.Phase != contract.PhaseAccepted {
		t.Fatalf("expected accepted progression: %+v", loop)
	}
	// No routine continue interventions.
	db, e := s.DeliveryStoreForTest()
	if e != nil {
		t.Fatal(e)
	}
	defer db.Close()
	ints, e := db.ListInterventions(loop.ID)
	if e != nil {
		t.Fatal(e)
	}
	for _, i := range ints {
		if i.Routine || i.Kind == contract.InterventionRoutineContinue {
			t.Fatalf("routine continue prompt recorded: %+v", i)
		}
	}

	// Unresolved consequential product decision remains an exception.
	s2 := delService(t)
	delRoot(t, s2, "root-t01b")
	req := baseDelivery("loop-t01b", "root-t01b", "cand-t01b")
	req.RequireProductDecision = true
	blocked, e := s2.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if !blocked.Blocked || blocked.BlockedReason != "consequential_product_decision" {
		t.Fatalf("expected product-decision block: %+v", blocked)
	}
	db2, _ := s2.DeliveryStoreForTest()
	defer db2.Close()
	ints2, _ := db2.ListInterventions(blocked.ID)
	found := false
	for _, i := range ints2 {
		if i.Kind == contract.InterventionProductDecision && !i.Routine {
			found = true
		}
	}
	if !found {
		t.Fatal("expected recorded product-decision intervention")
	}
}

// TestV415T02 — runnable milestone references executed behavior check; stubs fail.
func TestV415T02(t *testing.T) {
	for _, kind := range []string{
		contract.MilestoneStub, contract.MilestoneProse, contract.MilestoneFakeLog,
	} {
		s := delService(t)
		delRoot(t, s, "root-"+kind)
		req := baseDelivery("loop-"+kind, "root-"+kind, "cand-"+kind)
		req.MilestoneKind = kind
		loop, e := s.RunDeliveryLoop(req, nil, "")
		if e != nil {
			t.Fatal(e)
		}
		if loop.Accepted || loop.MilestoneRunnable {
			t.Fatalf("%s must not be runnable/accepted: %+v", kind, loop)
		}
		if !loop.Blocked || !strings.Contains(loop.BlockedReason, "milestone_not_runnable") {
			t.Fatalf("%s expected milestone block: %+v", kind, loop)
		}
	}

	for _, kind := range []string{contract.MilestoneGenuineBehavior, contract.MilestoneIntegration} {
		s := delService(t)
		delRoot(t, s, "root-ok-"+kind)
		req := baseDelivery("loop-ok-"+kind, "root-ok-"+kind, "cand-ok-"+kind)
		req.MilestoneKind = kind
		loop, e := s.RunDeliveryLoop(req, nil, "")
		if e != nil {
			t.Fatal(e)
		}
		if !loop.Accepted || !loop.MilestoneRunnable {
			t.Fatalf("%s must pass: %+v", kind, loop)
		}
		if loop.BehaviorCheckRef == "" || !strings.Contains(loop.BehaviorCheckRef, "check/behavior") {
			t.Fatalf("%s missing executed behavior check ref: %q", kind, loop.BehaviorCheckRef)
		}
	}
}

// TestV415T03 — resource exhaustion yields nonaccepted partial/blocked.
func TestV415T03(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t03a")
	req := baseDelivery("loop-t03a", "root-t03a", "cand-t03a")
	req.ExhaustBeforeVerification = true
	req.ResourceBudget = 20
	req.VerificationCost = 10
	req.MandatoryCost = 15
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if loop.Accepted || !loop.Partial {
		t.Fatalf("exhaust before verification must be nonaccepted partial: %+v", loop)
	}
	if loop.BlockedReason != "resources_exhausted_before_verification" {
		t.Fatalf("unexpected reason: %s", loop.BlockedReason)
	}

	s2 := delService(t)
	delRoot(t, s2, "root-t03b")
	req2 := baseDelivery("loop-t03b", "root-t03b", "cand-t03b")
	req2.ExhaustAfterSlice = true
	loop2, e := s2.RunDeliveryLoop(req2, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if loop2.Accepted || !loop2.Partial {
		t.Fatalf("exhaust after slice must be nonaccepted partial: %+v", loop2)
	}
	if loop2.CandidateID == "" {
		t.Fatal("partial must preserve candidate identity")
	}
	if loop2.BlockedReason != "resources_exhausted_after_slice" {
		t.Fatalf("unexpected reason: %s", loop2.BlockedReason)
	}
}

// TestV415T04 — repeated failure with no new evidence stops; signature stable across resets.
func TestV415T04(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t04")
	req := baseDelivery("loop-t04", "root-t04", "cand-t04")
	req.InjectFailureClass = contract.FailureTest
	req.InjectFailureCode = "fixture_repeat"
	req.InjectFailureRepeats = 3
	req.FailureBound = 2
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if !loop.Blocked || loop.BlockedReason != "repeat_failure_bound" {
		t.Fatalf("expected repeat-failure stop: %+v", loop)
	}
	if len(loop.FailureSignatures) != 1 || !loop.FailureSignatures[0].Stopped {
		t.Fatalf("expected stopped signature: %+v", loop.FailureSignatures)
	}
	a, b := StableFailureAcrossReset(contract.FailureTest, "fixture_repeat")
	if a != b || a == "" {
		t.Fatalf("signature must be stable across worker/context reset: %q vs %q", a, b)
	}
	if loop.FailureSignatures[0].Digest != a {
		t.Fatalf("loop digest %q != stable %q", loop.FailureSignatures[0].Digest, a)
	}
}

// TestV415T05 — resume preserves root accounting, authority, candidates, outstanding verification.
func TestV415T05(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t05")
	req := baseDelivery("loop-t05", "root-t05", "cand-t05")
	loop, e := s.RunDeliveryLoop(req, nil, contract.DeliveryFaultBeforeCheck)
	if e == nil || !strings.Contains(e.Error(), "before_check") {
		t.Fatalf("expected before_check fault, got %v", e)
	}
	if loop.LastCheckpointID == "" {
		t.Fatal("interrupt must checkpoint")
	}
	auth := loop.AuthorityDigest
	cand := loop.CandidateID
	obs := append([]string(nil), loop.ObligationIDs...)
	outstanding := append([]string(nil), loop.OutstandingChecks...)

	resumed, e := s.ResumeDelivery(contract.DeliveryResumeRequest{
		SchemaVersion: contract.DeliverySchemaVersion,
		LoopID:        loop.ID, RootID: "root-t05",
	})
	if e != nil {
		t.Fatal(e)
	}
	if resumed.AuthorityDigest != auth {
		t.Fatalf("authority digest changed: %s -> %s", auth, resumed.AuthorityDigest)
	}
	if resumed.CandidateID != cand {
		t.Fatalf("candidate changed: %s -> %s", cand, resumed.CandidateID)
	}
	if len(resumed.ObligationIDs) != len(obs) {
		t.Fatalf("obligations not preserved: %v vs %v", resumed.ObligationIDs, obs)
	}
	if len(outstanding) > 0 && len(resumed.OutstandingChecks) == 0 {
		t.Fatal("outstanding verification must remain")
	}

	// Interrupt points: before/after send/edit/freeze/check/checkpoint.
	points := []contract.DeliveryFault{
		contract.DeliveryFaultBeforeDispatch,
		contract.DeliveryFaultAfterEdit,
		contract.DeliveryFaultBeforeFreeze,
		contract.DeliveryFaultAfterFreeze,
		contract.DeliveryFaultBeforeCheckpoint,
	}
	for i, fault := range points {
		s2 := delService(t)
		root := "root-t05-" + string(rune('a'+i))
		delRoot(t, s2, root)
		r := baseDelivery("loop-t05-"+string(rune('a'+i)), root, "cand-t05-"+string(rune('a'+i)))
		_, e := s2.RunDeliveryLoop(r, nil, fault)
		if e == nil {
			t.Fatalf("expected fault at %s", fault)
		}
	}
}

// TestV415T06 — stale/tampered/unusable checkpoint reports exact limitation; preserves artifacts.
func TestV415T06(t *testing.T) {
	cases := []string{
		contract.TamperChangedCriteria,
		contract.TamperPayload,
		contract.TamperMissingNative,
		contract.TamperMemoryOutage,
	}
	for _, kind := range cases {
		s := delService(t)
		delRoot(t, s, "root-"+kind)
		req := baseDelivery("loop-"+kind, "root-"+kind, "cand-"+kind)
		loop, e := s.RunDeliveryLoop(req, nil, "")
		if e != nil {
			t.Fatal(e)
		}
		if loop.LastCheckpointID == "" {
			t.Fatal("expected checkpoint")
		}
		out, cp, e := s.RecoverCheckpoint(loop.ID, loop.LastCheckpointID, kind)
		if e != nil {
			t.Fatal(e)
		}
		if out.Limitation == nil || out.Limitation.Kind != kind {
			t.Fatalf("%s: expected limitation kind, got %+v", kind, out.Limitation)
		}
		if len(out.Limitation.PreservedArtifacts) == 0 && len(cp.ValidLocalArtifacts) == 0 {
			t.Fatalf("%s: must preserve valid local/portable artifacts", kind)
		}
		// Candidate / obligations still present.
		if out.CandidateID == "" && loop.CandidateID != "" {
			t.Fatalf("%s discarded candidate", kind)
		}
		db, _ := s.DeliveryStoreForTest()
		obs, _ := db.ListObligations(loop.ID)
		db.Close()
		if len(obs) == 0 {
			t.Fatalf("%s discarded obligations", kind)
		}
	}
}

// TestV415T07 — inspect is observational; covers unknown/running/cancel-pending/partial.
func TestV415T07(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t07")
	counters := &ObservationalCounters{}

	unknown, e := s.InspectDelivery("missing-loop", counters)
	if e != nil {
		t.Fatal(e)
	}
	if unknown.Status != contract.PhaseUnknown {
		t.Fatalf("expected unknown: %+v", unknown)
	}
	if unknown.ModelCalls != 0 {
		t.Fatalf("inspect must not dispatch model work: model_calls=%d", unknown.ModelCalls)
	}

	req := baseDelivery("loop-t07", "root-t07", "cand-t07")
	loop, e := s.RunDeliveryLoop(req, nil, contract.DeliveryFaultBeforeCheck)
	if e == nil {
		t.Fatal("expected fault")
	}
	_ = loop
	snap, e := s.InspectDelivery("loop-t07", counters)
	if e != nil {
		t.Fatal(e)
	}
	if snap.CandidateID == "" || snap.AcceptanceID == "" {
		t.Fatalf("inspect must expose candidate/acceptance: %+v", snap)
	}
	if snap.NextAction == "" {
		t.Fatal("next-action required")
	}
	if snap.ModelCalls != 0 {
		t.Fatalf("observational inspect model_calls=%d", snap.ModelCalls)
	}
	readsBefore := snap.FilesystemReads

	// Cancellation-pending.
	cancelled, e := s.CancelDelivery(contract.DeliveryCancelRequest{
		SchemaVersion: contract.DeliverySchemaVersion,
		LoopID:        "loop-t07", RootID: "root-t07", Reason: "operator_stop",
	})
	if e != nil {
		t.Fatal(e)
	}
	if cancelled.Status != contract.PhaseCancellationPending {
		t.Fatalf("expected cancellation_pending: %+v", cancelled)
	}
	snap2, _ := s.InspectDelivery("loop-t07", counters)
	if snap2.NextAction != contract.NextCancelPending {
		t.Fatalf("expected cancel-pending next action: %+v", snap2)
	}
	if snap2.FilesystemReads <= readsBefore {
		t.Fatal("filesystem read counter must prove observational reads")
	}

	// Partial.
	s2 := delService(t)
	delRoot(t, s2, "root-t07p")
	req2 := baseDelivery("loop-t07p", "root-t07p", "cand-t07p")
	req2.ExhaustAfterSlice = true
	partial, e := s2.RunDeliveryLoop(req2, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	c2 := &ObservationalCounters{}
	snap3, e := s2.InspectDelivery(partial.ID, c2)
	if e != nil {
		t.Fatal(e)
	}
	if !snap3.Partial || snap3.NextAction != contract.NextStopPartial {
		t.Fatalf("expected partial inspect: %+v", snap3)
	}
	m, _, w := c2.Snapshot()
	if m != 0 || w != 0 {
		t.Fatalf("inspect must not write or call models: model=%d writes=%d", m, w)
	}
}

// TestV415T08 — context compact preserves obligations/source refs independently of summary.
func TestV415T08(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t08")
	req := baseDelivery("loop-t08", "root-t08", "cand-t08")
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	_, obs, e := s.CompactDeliveryContext(contract.ContextCompactRequest{
		SchemaVersion:    contract.DeliverySchemaVersion,
		LoopID:           loop.ID,
		RootID:           "root-t08",
		GeneratedSummary: "everything went fine", // omits failed approach + required check
		OmittedTopics:    []string{"failed_approach", "required_check"},
	})
	if e != nil {
		t.Fatal(e)
	}
	hasFailed := false
	hasCheck := false
	hasAccess := false
	hasSource := false
	for _, o := range obs {
		switch o.Kind {
		case "failed_approach":
			hasFailed = true
		case "required_check":
			hasCheck = true
		case "access_restriction":
			hasAccess = true
		case "source_ref":
			hasSource = true
			if len(o.SourceRefs) == 0 {
				t.Fatal("source refs must remain reopenable")
			}
		}
	}
	if !hasFailed || !hasCheck {
		t.Fatalf("canonical obligations must retain failed approach and required check: %+v", obs)
	}
	if !hasAccess || !hasSource {
		t.Fatalf("access restrictions and source refs must persist: %+v", obs)
	}
	if len(loop.AccessRestrictions) == 0 {
		t.Fatal("loop access restrictions must persist")
	}
}

// TestV415T09 — authorized comparison records native/v4 via V4-09; never fabricates.
func TestV415T09(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t09")
	req := baseDelivery("loop-t09", "root-t09", "cand-t09")
	req.ComparisonRequested = true
	req.ProtocolID = "proto-t09"
	req.NativeArmEligible = false // live ineligible via V4-09 paths
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	if loop.Comparison == nil {
		t.Fatal("expected comparison outcome")
	}
	if loop.Comparison.Fabricated {
		t.Fatal("must never fabricate arms")
	}
	if loop.Comparison.NativeArmStatus != contract.EligibilityIneligible {
		t.Fatalf("missing/ineligible live arm must be explicit: %+v", loop.Comparison)
	}
	if loop.Comparison.NativeArmReason == "" {
		t.Fatal("ineligible native arm needs reason")
	}
	if loop.Comparison.V4ArmStatus != contract.EligibilityEligible {
		t.Fatalf("v4 fixture arm should be eligible: %+v", loop.Comparison)
	}
}

// TestV415T10 — unresolved external effects block dependent work on resume.
func TestV415T10(t *testing.T) {
	s := delService(t)
	delRoot(t, s, "root-t10")
	counters := NewNativeMethodCounters()
	adapter := NewFakeNativeAdapter(counters)
	req := baseDelivery("loop-t10", "root-t10", "cand-t10")
	req.SkipDispatch = false
	req.LostAckAfterEffect = true
	loop, e := s.RunDeliveryLoop(req, adapter, contract.DeliveryFaultLostAckAfterEffect)
	if e == nil || !strings.Contains(e.Error(), "lost_ack") {
		t.Fatalf("expected lost_ack error, got %v", e)
	}
	if !loop.UnresolvedEffects || !loop.UncertaintyExposed {
		t.Fatalf("must expose unresolved effects: %+v", loop)
	}
	if counters.Snapshot().Start < 1 {
		t.Fatal("effect must have been sent before lost ack")
	}

	// Resume without acknowledging uncertainty.
	resumed, e := s.ResumeDelivery(contract.DeliveryResumeRequest{
		SchemaVersion: contract.DeliverySchemaVersion,
		LoopID:        loop.ID, RootID: "root-t10",
		AcknowledgeUncertainty: false,
		AdmitDependentWork:     false,
	})
	if e != nil {
		t.Fatal(e)
	}
	if resumed.Status != contract.PhaseAwaitingReconciliation || !resumed.UncertaintyExposed {
		t.Fatalf("resume must expose uncertainty: %+v", resumed)
	}

	// Successor cannot assume completion/absence/refunded exposure.
	_, e = s.ResumeDelivery(contract.DeliveryResumeRequest{
		SchemaVersion: contract.DeliverySchemaVersion,
		LoopID:        loop.ID, RootID: "root-t10",
		AcknowledgeUncertainty: true,
		AdmitDependentWork:     true,
	})
	if e == nil || !strings.Contains(e.Error(), "cannot assume") {
		t.Fatalf("dependent work must be rejected: %v", e)
	}

	snap, e := s.InspectDelivery(loop.ID, &ObservationalCounters{})
	if e != nil {
		t.Fatal(e)
	}
	if snap.NextAction != contract.NextReconcileUncertainty {
		t.Fatalf("inspect next-action should require reconcile: %+v", snap)
	}
}
