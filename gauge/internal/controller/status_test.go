package controller

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

func statusService(t *testing.T) *Service {
	t.Helper()
	s := New(t.TempDir(), Options{Timeout: time.Second, Clock: func() time.Time {
		return time.Date(2026, 9, 22, 21, 0, 0, 0, time.UTC)
	}})
	if e := s.Init(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureDeliveryNamespaces(); e != nil {
		t.Fatal(e)
	}
	if e := s.EnsureStatusNamespaces(); e != nil {
		t.Fatal(e)
	}
	return s
}

func statusRoot(t *testing.T, s *Service, id string) {
	t.Helper()
	if e := s.InitRoot(id); e != nil {
		t.Fatal(e)
	}
}

func statusDelivery(loop, root, cand string) contract.DeliveryRunRequest {
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
		RecordedAt:          "2026-09-22T21:00:00Z",
	}
}

// TestV420T01 — delivery and verification states reported separately.
func TestV420T01(t *testing.T) {
	s := statusService(t)
	statusRoot(t, s, "root-t01")

	req := statusDelivery("loop-t01", "root-t01", "cand-t01")
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	proj, e := s.ProjectStatus(StatusProjectOptions{
		LoopID: loop.ID, ChecksPassed: true, Counters: &ObservationalCounters{},
	})
	if e != nil {
		t.Fatal(e)
	}
	if proj.DeliveryState != contract.DeliveryStateRunnable && proj.DeliveryState != contract.DeliveryStateImplemented {
		t.Fatalf("expected implemented/runnable delivery: %s", proj.DeliveryState)
	}
	if proj.VerificationState != contract.VerificationStateChecksPassed {
		t.Fatalf("expected checks_passed verification separate from delivery: %s", proj.VerificationState)
	}
	if proj.GreenBadgeMeans != "not_acceptance" {
		t.Fatalf("terminal/green badge must not equal acceptance: %+v", proj)
	}

	proj2, e := s.ProjectStatus(StatusProjectOptions{
		LoopID: loop.ID, ChecksPassed: true, ReviewPending: true, Counters: &ObservationalCounters{},
	})
	if e != nil {
		t.Fatal(e)
	}
	if proj2.VerificationState != contract.VerificationStateReviewPending {
		t.Fatalf("expected review_pending: %s", proj2.VerificationState)
	}
	proj3, e := s.ProjectStatus(StatusProjectOptions{
		LoopID: loop.ID, Released: true, Counters: &ObservationalCounters{},
	})
	if e != nil {
		t.Fatal(e)
	}
	if proj3.VerificationState != contract.VerificationStateReleased {
		t.Fatalf("expected released: %s", proj3.VerificationState)
	}

	if _, e := s.CancelDelivery(contract.DeliveryCancelRequest{
		SchemaVersion: contract.DeliverySchemaVersion,
		LoopID: loop.ID, RootID: "root-t01", Reason: "operator",
	}); e != nil {
		t.Fatal(e)
	}
	projC, e := s.ProjectStatus(StatusProjectOptions{LoopID: loop.ID, Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	if projC.DeliveryState != contract.DeliveryStateRunning {
		t.Fatalf("cancel ack must not show cancelled done: %s", projC.DeliveryState)
	}

	s2 := statusService(t)
	statusRoot(t, s2, "root-t01p")
	reqP := statusDelivery("loop-t01p", "root-t01p", "cand-t01p")
	reqP.ExhaustAfterSlice = true
	partial, e := s2.RunDeliveryLoop(reqP, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	projP, e := s2.ProjectStatus(StatusProjectOptions{LoopID: partial.ID, Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	if projP.DeliveryState != contract.DeliveryStatePartial {
		t.Fatalf("expected partial: %s", projP.DeliveryState)
	}

	s3 := statusService(t)
	statusRoot(t, s3, "root-t01b")
	reqB := statusDelivery("loop-t01b", "root-t01b", "cand-t01b")
	reqB.ExhaustBeforeVerification = true
	if _, e := s3.RunDeliveryLoop(reqB, nil, ""); e != nil {
		// may error with partial/blocked loop still persisted
	}
	projB, e := s3.ProjectStatus(StatusProjectOptions{LoopID: "loop-t01b", Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	if projB.DeliveryState != contract.DeliveryStateBlocked && projB.DeliveryState != contract.DeliveryStatePartial {
		t.Fatalf("expected blocked/partial: %s", projB.DeliveryState)
	}

	s4 := statusService(t)
	statusRoot(t, s4, "root-t01s")
	reqS := statusDelivery("loop-t01s", "root-t01s", "cand-t01s")
	loopS, e := s4.RunDeliveryLoop(reqS, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	db, e := s4.DeliveryStoreForTest()
	if e != nil {
		t.Fatal(e)
	}
	loopS.Limitation = &contract.CheckpointLimitation{Kind: "changed_criteria", Detail: "criteria changed"}
	if _, e := db.PersistDeliveryLoop(loopS); e != nil {
		t.Fatal(e)
	}
	db.Close()
	projS, e := s4.ProjectStatus(StatusProjectOptions{
		LoopID: loopS.ID, ChecksPassed: true, Counters: &ObservationalCounters{},
	})
	if e != nil {
		t.Fatal(e)
	}
	if projS.VerificationState != contract.VerificationStateStaleEvidence {
		t.Fatalf("stale evidence must override checks_passed: %s", projS.VerificationState)
	}
	if projS.OptionalGAMBIT != "out_of_scope" {
		t.Fatal("optional-GAMBIT must be out_of_scope")
	}
}

// TestV420T02 — methods, workers, context-separation; no fictional team.
func TestV420T02(t *testing.T) {
	s := statusService(t)
	statusRoot(t, s, "root-t02")
	req := statusDelivery("loop-t02", "root-t02", "cand-t02")
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}

	oneMaker := []contract.Assignment{{
		SchemaVersion: contract.CompilerSchemaVersion,
		ID: "asgn-maker", RootID: "root-t02", TaskID: "task-t02",
		WorkerID: "maker-1", MakerWorkerID: "maker-1", Continuing: true,
		Boundary: contract.BoundaryCompatible, AuthorityID: "auth-1", Status: "compiled",
		Methods: []contract.MethodUse{
			{ID: "mu-1", MethodID: "fix", MethodVersion: "1", ExecutionForm: contract.FormEmbedded,
				ReportClass: contract.ReportMethodUse, WorkerID: "maker-1",
				Contract: skill("fix", "1", []string{contract.FormEmbedded}, []string{"spec"}, "patch"),
				ProvidedInputs: []string{"spec"}, Status: "bound",
				Selection: contract.SelectionReason{RuleID: "R01", Kind: "continuing_maker", Detail: "inline"}},
			{ID: "mu-2", MethodID: "plan-lite", MethodVersion: "1", ExecutionForm: contract.FormEmbedded,
				ReportClass: contract.ReportMethodUse, WorkerID: "maker-1",
				Contract: func() contract.SkillContract {
					c := skill("plan-lite", "1", []string{contract.FormEmbedded}, []string{"spec"}, "plan")
					c.DerivedFrom = "RAMZA"
					return c
				}(), ProvidedInputs: []string{"spec"}, Status: "bound",
				Selection: contract.SelectionReason{RuleID: "R01", Kind: "method_use", Detail: "embedded"}},
		},
	}}
	proj, e := s.ProjectStatus(StatusProjectOptions{
		LoopID: loop.ID, Assignments: oneMaker, Counters: &ObservationalCounters{},
	})
	if e != nil {
		t.Fatal(e)
	}
	if proj.Participation.Pattern != contract.ParticipationOneMakerManyMethods {
		t.Fatalf("expected one_maker_many_methods: %+v", proj.Participation)
	}
	if proj.Participation.FictionalTeam {
		t.Fatal("fictional team forbidden")
	}
	if len(proj.Participation.Methods) != 2 || len(proj.Participation.Workers) != 1 {
		t.Fatalf("methods/workers: %+v", proj.Participation)
	}

	separated := []contract.Assignment{
		oneMaker[0],
		{
			SchemaVersion: contract.CompilerSchemaVersion,
			ID: "asgn-check", RootID: "root-t02", TaskID: "task-t02",
			WorkerID: "checker-1", MakerWorkerID: "maker-1", Continuing: false,
			Boundary: contract.BoundaryVerification, AuthorityID: "auth-check", Status: "compiled",
			Methods: []contract.MethodUse{{
				ID: "mu-c", MethodID: "verify", MethodVersion: "1",
				ExecutionForm: contract.FormVerification, ReportClass: contract.ReportSpecialistInvocation,
				WorkerID: "checker-1", InvocationID: "inv-check-1",
				Contract: skill("verify", "1", []string{contract.FormVerification}, []string{"spec"}, "report"),
				ProvidedInputs: []string{"spec"}, Status: "bound",
				Selection: contract.SelectionReason{RuleID: "R02", Kind: "specialist_invocation", Detail: "checker"},
			}},
		},
	}
	proj2, e := s.ProjectStatus(StatusProjectOptions{
		LoopID: loop.ID, Assignments: separated, Counters: &ObservationalCounters{},
	})
	if e != nil {
		t.Fatal(e)
	}
	if proj2.Participation.Pattern != contract.ParticipationSeparateSpecialistChecker {
		t.Fatalf("expected separate specialist/checker: %+v", proj2.Participation)
	}
	var sawSeparation bool
	for _, w := range proj2.Participation.Workers {
		if w.Role == "checker" && w.ContextSeparation && len(w.SeparationEvidence) > 0 {
			sawSeparation = true
		}
	}
	if !sawSeparation {
		t.Fatalf("context-separation evidence required: %+v", proj2.Participation.Workers)
	}
}

// TestV420T03 — unsupported/stale quota → plain-text; no invented %.
func TestV420T03(t *testing.T) {
	s := statusService(t)
	statusRoot(t, s, "root-t03")
	req := statusDelivery("loop-t03", "root-t03", "cand-t03")
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	cases := []contract.QuotaLimitation{
		{Kind: contract.QuotaUnknownBucket, PlainText: "provider bucket unknown; no percentage available", PercentageKnown: false},
		{Kind: contract.QuotaStale, PlainText: "quota snapshot stale; do not invent remaining percent", PercentageKnown: false},
		{Kind: contract.QuotaUnsupported, PlainText: "provider enforcement unsupported in this fixture", PercentageKnown: false},
		{Kind: contract.QuotaAdvisoryOnly, PlainText: "advisory-only mode; not controller-enforced", PercentageKnown: false, AdvisoryOnly: true},
		{Kind: contract.QuotaOutsideController, PlainText: "execution outside controller control", PercentageKnown: false, OutsideController: true},
	}
	for _, q := range cases {
		qq := q
		proj, e := s.ProjectStatus(StatusProjectOptions{
			LoopID: loop.ID, Quota: &qq, Counters: &ObservationalCounters{},
		})
		if e != nil {
			t.Fatalf("%s: %v", q.Kind, e)
		}
		if proj.QuotaLimitation == nil || proj.QuotaLimitation.PlainText == "" {
			t.Fatalf("%s missing plain text", q.Kind)
		}
		if proj.QuotaLimitation.PercentageKnown || proj.QuotaLimitation.Percentage != nil {
			t.Fatalf("%s invented percentage: %+v", q.Kind, proj.QuotaLimitation)
		}
	}
	bad := contract.QuotaLimitation{
		Kind: contract.QuotaUnknownBucket, PlainText: "x", PercentageKnown: false, Percentage: f64(42),
	}
	if e := bad.Validate(); e == nil {
		t.Fatal("unknown bucket must reject invented percentage")
	}
}

// TestV420T04 — policy inspect/preview dispatches no model work; preserves reservations.
func TestV420T04(t *testing.T) {
	s := statusService(t)
	statusRoot(t, s, "root-t04")

	counters := &ObservationalCounters{}
	insp, e := s.InspectPolicyObservational("root-t04", "", "please-escalate-to-model", counters)
	if e != nil {
		t.Fatal(e)
	}
	if insp.ModelCalls != 0 || insp.Dispatched || !insp.DeniedEscalation {
		t.Fatalf("inspect must deny escalation without dispatch: %+v", insp)
	}

	if e := s.EnsureReservationNamespaces(); e != nil {
		t.Fatal(e)
	}
	ceilings := []contract.Ceiling{
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "task", Limit: f64(100)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "project", Limit: f64(100)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "account", Limit: f64(100)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "window", Limit: f64(100)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "concurrency", Limit: f64(4)},
	}
	admit, e := s.AdmitReservation("root-t04", contract.AdmitRequest{
		ID: "res-t04", RootID: "root-t04", AssignmentID: "asg-t04", ProjectID: "project-t04",
		AccountPool: "shared-pool", WindowEpoch: "window-1", TaskID: "task-t04",
		HeadroomKind: contract.HeadroomImplementation, WorkKind: contract.WorkOptionalImplementation,
		Amount: 10, EstimateProvenance: contract.EstimateProvenance{Kind: contract.ProvenanceEstimate, Source: "fixture"},
		Resource: "tokens", Unit: "token", Pool: "shared-pool", PolicyID: "policy-fixture-1",
		Ceilings: ceilings, ConcurrencyIdentity: "shared-pool", ConcurrencyAmount: 1,
		ObservationUsable: true, RecordedAt: "2026-09-22T21:00:00Z",
	})
	if e != nil {
		t.Fatal(e)
	}
	if !admit.Admitted || admit.ReservationID == "" {
		t.Fatalf("admit failed: %+v", admit)
	}

	c2 := &ObservationalCounters{}
	prev, e := s.PreviewPolicyChange("root-t04", c2)
	if e != nil {
		t.Fatal(e)
	}
	if prev.ModelCalls != 0 || prev.Dispatched || !prev.Preview {
		t.Fatalf("preview must be observational: %+v", prev)
	}
	found := false
	for _, id := range prev.OutstandingReservations {
		if id == "res-t04" {
			found = true
		}
	}
	if !found {
		t.Fatalf("preview must preserve outstanding reservations: %+v", prev.OutstandingReservations)
	}
	m, _, w := c2.Snapshot()
	if m != 0 || w != 0 {
		t.Fatalf("preview must not write or call models: m=%d w=%d", m, w)
	}
}

// TestV420T05 — fixture client consumes same contract; no-GUI/no-color; unsupported clear error.
func TestV420T05(t *testing.T) {
	s := statusService(t)
	statusRoot(t, s, "root-t05")
	req := statusDelivery("loop-t05", "root-t05", "cand-t05")
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}
	proj, e := s.ProjectStatus(StatusProjectOptions{LoopID: loop.ID, Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	raw, e := json.Marshal(proj)
	if e != nil {
		t.Fatal(e)
	}

	ok, e := s.ConsumeStatusContract(contract.ClientConformanceRequest{
		SchemaVersion: contract.StatusSchemaVersion, ContractVersion: contract.StatusContractID,
		Modes: []string{contract.ClientModeNoGUI, contract.ClientModeNoColor}, ReadOnly: true,
	}, raw, &ObservationalCounters{})
	if e != nil {
		t.Fatal(e)
	}
	if !ok.Supported || !ok.NoGUI || !ok.NoColor || !ok.ConsumedProjection {
		t.Fatalf("fixture consumer must accept shared contract: %+v", ok)
	}
	if ok.OptionalGAMBIT != "out_of_scope" {
		t.Fatal("GAMBIT must remain out_of_scope (dropped; not used)")
	}
	if ok.ModelCalls != 0 {
		t.Fatalf("client conformance must not dispatch: %d", ok.ModelCalls)
	}

	bad, e := s.ConsumeStatusContract(contract.ClientConformanceRequest{
		SchemaVersion: contract.StatusSchemaVersion, ContractVersion: "gauge-status@99-future",
		Modes: []string{contract.ClientModeNoColor}, ReadOnly: true,
	}, nil, &ObservationalCounters{})
	if e != nil {
		t.Fatal(e)
	}
	if bad.Supported || bad.Error == "" || !strings.Contains(bad.Error, "unsupported") {
		t.Fatalf("unsupported contract needs clear error: %+v", bad)
	}
}

// TestV420T06 — cancellation distinguishes ack / confirmed stop / accounting reconciliation.
func TestV420T06(t *testing.T) {
	s := statusService(t)
	statusRoot(t, s, "root-t06")
	req := statusDelivery("loop-t06", "root-t06", "cand-t06")
	loop, e := s.RunDeliveryLoop(req, nil, "")
	if e != nil {
		t.Fatal(e)
	}

	ack := contract.CancelState{
		State: contract.CancelInterruptAccepted, RequestedAt: "2026-09-22T21:01:00Z",
		InterruptAckAt: "2026-09-22T21:01:01Z", ProcessAlive: true, UsageDelayed: true,
	}
	proj, e := s.ProjectStatus(StatusProjectOptions{LoopID: loop.ID, CancelState: &ack, Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	if proj.Cancellation == nil || proj.Cancellation.Stage != contract.CancelStageRequestAcknowledged {
		t.Fatalf("expected request ack stage: %+v", proj.Cancellation)
	}
	if !proj.Cancellation.ProcessAlive || !proj.Cancellation.LateUsage {
		t.Fatalf("process must continue after ack with late usage: %+v", proj.Cancellation)
	}
	if proj.Cancellation.PrematureDoneDisplayed || proj.Cancellation.PrematureRefundClaimed || proj.Cancellation.AccountingReconciled {
		t.Fatalf("no premature done/refund: %+v", proj.Cancellation)
	}

	stopped := contract.CancelState{
		State: contract.CancelConfirmedStopped, RequestedAt: "2026-09-22T21:01:00Z",
		InterruptAckAt: "2026-09-22T21:01:01Z", ConfirmedStopAt: "2026-09-22T21:02:00Z",
		ProcessAlive: false, UsageDelayed: true,
	}
	proj2, e := s.ProjectStatus(StatusProjectOptions{LoopID: loop.ID, CancelState: &stopped, Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	if !proj2.Cancellation.ConfirmedStop || proj2.Cancellation.AccountingReconciled {
		t.Fatalf("confirmed stop ≠ accounting reconciliation: %+v", proj2.Cancellation)
	}

	final := contract.CancelState{
		State: contract.CancelFinalReconciled, RequestedAt: "2026-09-22T21:01:00Z",
		InterruptAckAt: "2026-09-22T21:01:01Z", ConfirmedStopAt: "2026-09-22T21:02:00Z",
		FinalReconciledAt: "2026-09-22T21:03:00Z",
	}
	proj3, e := s.ProjectStatus(StatusProjectOptions{LoopID: loop.ID, CancelState: &final, Counters: &ObservationalCounters{}})
	if e != nil {
		t.Fatal(e)
	}
	if proj3.Cancellation.Stage != contract.CancelStageAccountingReconciled || !proj3.Cancellation.AccountingReconciled {
		t.Fatalf("expected accounting reconciliation: %+v", proj3.Cancellation)
	}
}

// TestV420T07 — unsupported contract rejects authority mutations; read-only diagnostic does not dispatch.
func TestV420T07(t *testing.T) {
	s := statusService(t)

	mut, e := s.ConsumeStatusContract(contract.ClientConformanceRequest{
		SchemaVersion: contract.StatusSchemaVersion, ContractVersion: "gauge-status@2-future",
		AuthorityMutation: true, ReadOnly: false,
	}, nil, &ObservationalCounters{})
	if e != nil {
		t.Fatal(e)
	}
	if mut.Supported || !mut.MutationRejected {
		t.Fatalf("future schema must reject authority mutations: %+v", mut)
	}
	if mut.Compatibility == nil || mut.Compatibility.AuthorityMutations != "rejected" {
		t.Fatalf("compatibility diagnostic required: %+v", mut.Compatibility)
	}
	if mut.Compatibility.DispatchedModelWork || mut.ModelCalls != 0 {
		t.Fatalf("must not dispatch: %+v", mut)
	}
	if !strings.Contains(mut.Compatibility.Detail, "guessed") {
		t.Fatalf("must retain explicit diagnostic: %s", mut.Compatibility.Detail)
	}

	roCounters := &ObservationalCounters{}
	ro, e := s.ConsumeStatusContract(contract.ClientConformanceRequest{
		SchemaVersion: contract.StatusSchemaVersion, ContractVersion: "gauge-status@2-future", ReadOnly: true,
	}, nil, roCounters)
	if e != nil {
		t.Fatal(e)
	}
	if ro.Supported || ro.ModelCalls != 0 || (ro.Compatibility != nil && ro.Compatibility.DispatchedModelWork) {
		t.Fatalf("read-only diagnostic must not dispatch: %+v", ro)
	}
	m, _, w := roCounters.Snapshot()
	if m != 0 || w != 0 {
		t.Fatalf("read-only path must not write or call models: m=%d w=%d", m, w)
	}
}
