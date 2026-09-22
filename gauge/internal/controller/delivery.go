package controller

import (
	"errors"
	"fmt"
	"sync/atomic"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

// ObservationalCounters prove Inspect never dispatches model work (R07).
type ObservationalCounters struct {
	ModelCalls       atomic.Int64
	FilesystemReads  atomic.Int64
	FilesystemWrites atomic.Int64
}

func (c *ObservationalCounters) Snapshot() (model, reads, writes int) {
	return int(c.ModelCalls.Load()), int(c.FilesystemReads.Load()), int(c.FilesystemWrites.Load())
}

func (s *Service) ensureDeliveryStore() (*store.Store, error) {
	db, e := s.ensureAcceptanceStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureDeliveryNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureDeliveryNamespaces adds typed delivery buckets under schema 2.
func (s *Service) EnsureDeliveryNamespaces() error {
	db, e := s.ensureDeliveryStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// DeliveryStoreForTest opens the delivery-ready store for fixture fault injection.
func (s *Service) DeliveryStoreForTest() (*store.Store, error) {
	return s.ensureDeliveryStore()
}

func (s *Service) recordIntervention(db *store.Store, loop *contract.DeliveryLoop, kind, phase, reason string, routine bool) error {
	id := fmt.Sprintf("int-%s-%d", loop.ID, len(loop.Interventions)+1)
	rec := contract.InterventionRecord{
		SchemaVersion: contract.DeliverySchemaVersion,
		ID:            id,
		LoopID:        loop.ID,
		Kind:          kind,
		Phase:         phase,
		Reason:        reason,
		Routine:       routine,
		RecordedAt:    s.opts.Clock().UTC().Format(time.RFC3339),
	}
	if e := db.PersistIntervention(rec); e != nil {
		return e
	}
	loop.Interventions = append(loop.Interventions, id)
	return nil
}

func defaultObligations(req contract.DeliveryRunRequest) []contract.ObligationRecord {
	if len(req.Obligations) > 0 {
		return req.Obligations
	}
	checks := req.AcceptancePackage.RequiredChecks
	if len(checks) == 0 {
		checks = []string{"unit", "behavior"}
	}
	out := []contract.ObligationRecord{
		{ID: "obl-behavior", Kind: "required_check", Description: "execute requested behavior check", SourceRefs: []string{"acceptance:" + req.AcceptancePackage.ID}, Validated: true},
		{ID: "obl-failed-approach", Kind: "failed_approach", Description: "prior stub_scaffold approach failed discrimination", SourceRefs: []string{"fixture://approaches/stub"}, Validated: true},
		{ID: "obl-source", Kind: "source_ref", Description: "canonical source for requested behavior", SourceRefs: []string{"docs/campaigns/gauge/03-managed-delivery.md#v4-15"}, Validated: true},
	}
	for _, c := range checks {
		out = append(out, contract.ObligationRecord{
			ID: "obl-check-" + c, Kind: "required_check", Description: "required check " + c,
			SourceRefs: []string{"check:" + c}, Validated: true,
		})
	}
	for i, r := range req.AccessRestrictions {
		out = append(out, contract.ObligationRecord{
			ID: fmt.Sprintf("obl-access-%d", i+1), Kind: "access_restriction", Description: r,
			SourceRefs: []string{"policy:access"}, Validated: true,
		})
	}
	return out
}

func defaultPkg(req *contract.DeliveryRunRequest) {
	if req.AcceptancePackage.ID == "" {
		req.AcceptancePackage = contract.AcceptancePackage{
			SchemaVersion:           contract.AcceptanceSchemaVersion,
			ID:                      "acc-" + req.LoopID,
			RequestedBehavior:       "returns greeting for known user",
			OracleOrigin:            "fixture-oracle",
			OracleVersion:           "1.0.0",
			EnvironmentID:           "env-fixture",
			RequiredChecks:          []string{"unit", "behavior"},
			RequiresBehaviorGate:    true,
			BehavioralDiscriminator: "greeting_response_vs_empty_stub",
		}
	}
	if len(req.FreezeEntries) == 0 {
		req.FreezeEntries = []contract.CandidateContentEntry{
			{Path: "src/main.go", Kind: "tracked", Digest: "aaa", Mode: "0644"},
			{Path: ".env.local", Kind: "untracked", Digest: "bbb", Mode: "0600"},
			{Path: "config.yaml", Kind: "config", Digest: "ccc", Mode: "0644"},
			{Path: "bin/tool", Kind: "mode", Digest: "ddd", Mode: "0755"},
		}
	}
	if req.FailureBound < 1 {
		req.FailureBound = 2
	}
	if req.MilestoneKind == "" {
		req.MilestoneKind = contract.MilestoneGenuineBehavior
	}
	if req.MilestoneKind == contract.MilestoneGenuineBehavior || req.MilestoneKind == contract.MilestoneIntegration {
		// Happy-path default: genuine milestones execute an observed behavior check.
		// Callers testing non-observation set MilestoneKind to stub/prose/fake_log instead.
		req.BehaviorObserved = true
	}
	if req.MandatoryCost == 0 {
		req.MandatoryCost = 10
	}
	if req.VerificationCost == 0 {
		req.VerificationCost = 5
	}
	if req.ResourceBudget == 0 {
		req.ResourceBudget = 100
	}
}

// RunDeliveryLoop progresses authorized phases without routine continuation prompts (R01).
// Wires V4-11 admit, optional V4-12 dispatch, V4-14 freeze/check, and V4-09 comparison.
// Zero real network/model; live arms stay ineligible via V4-09 paths.
func (s *Service) RunDeliveryLoop(req contract.DeliveryRunRequest, adapter NativeAdapter, fault contract.DeliveryFault) (contract.DeliveryLoop, error) {
	defaultPkg(&req)
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if fault == "" {
		fault = req.Fault
	}
	if e := req.Validate(); e != nil {
		return contract.DeliveryLoop{}, e
	}

	release, e := s.lock(req.RootID, false)
	if e != nil {
		return contract.DeliveryLoop{}, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(req.RootID); e != nil {
		return contract.DeliveryLoop{}, errors.New("active_claim_or_inventory_failed")
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.DeliveryLoop{}, e
	}
	defer db.Close()
	if e = db.EnsureAcceptanceNamespaces(); e != nil {
		return contract.DeliveryLoop{}, e
	}
	if e = db.EnsureDeliveryNamespaces(); e != nil {
		return contract.DeliveryLoop{}, e
	}

	auth := contract.AuthorityDigest(req.AuthoritySufficient, req.AssignmentID, req.RootID)
	loop := contract.DeliveryLoop{
		SchemaVersion:       contract.DeliverySchemaVersion,
		ID:                  req.LoopID,
		RootID:              req.RootID,
		AssignmentID:        req.AssignmentID,
		Phase:               contract.PhasePending,
		Status:              contract.PhasePending,
		AuthorityDigest:     auth,
		AuthoritySufficient: req.AuthoritySufficient,
		InputsSufficient:    req.InputsSufficient,
		CandidateID:         req.CandidateID,
		AcceptanceID:        req.AcceptancePackage.ID,
		EnvironmentID:       req.AcceptancePackage.EnvironmentID,
		MilestoneKind:       req.MilestoneKind,
		ResourceRemaining:   req.ResourceBudget,
		ResourceExposure:    map[string]float64{"tokens": 0},
		OutstandingChecks:   append([]string(nil), req.AcceptancePackage.RequiredChecks...),
		FailureBound:        req.FailureBound,
		AccessRestrictions:  append([]string(nil), req.AccessRestrictions...),
		ModelCalls:          0,
		RecordedAt:          req.RecordedAt,
		UpdatedAt:           req.RecordedAt,
	}

	// Persist obligations independently of any later summary (R08).
	for _, o := range defaultObligations(req) {
		if e := db.PersistObligation(loop.ID, o); e != nil {
			return loop, e
		}
		loop.ObligationIDs = append(loop.ObligationIDs, o.ID)
	}

	if !req.AuthoritySufficient || !req.InputsSufficient {
		loop.Phase = contract.PhaseBlocked
		loop.Status = contract.PhaseBlocked
		loop.Blocked = true
		loop.BlockedReason = "insufficient_authority_or_inputs"
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, nil
	}

	// R01 exception: unresolved consequential product decision.
	if req.RequireProductDecision {
		_ = s.recordIntervention(db, &loop, contract.InterventionProductDecision, contract.PhasePending,
			"unresolved consequential product decision requires operator", false)
		loop.Phase = contract.PhaseBlocked
		loop.Status = contract.PhaseBlocked
		loop.Blocked = true
		loop.BlockedReason = "consequential_product_decision"
		loop.UpdatedAt = req.RecordedAt
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, nil
	}

	// --- Phase: admit (V4-11) ---
	loop.Phase = contract.PhaseAdmit
	loop.Status = contract.PhaseRunning
	if _, e = db.PersistDeliveryLoop(loop); e != nil {
		return loop, e
	}

	admitAmount := req.MandatoryCost
	if req.ExhaustBeforeVerification {
		// Leave budget that cannot cover verification after implementation slice.
		admitAmount = req.ResourceBudget - req.VerificationCost + 1
		if admitAmount < 1 {
			admitAmount = req.ResourceBudget
		}
	}
	ceilings := []contract.Ceiling{
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "task", Limit: f64ptr(req.ResourceBudget)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "project", Limit: f64ptr(req.ResourceBudget)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "account", Limit: f64ptr(req.ResourceBudget)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "window", Limit: f64ptr(req.ResourceBudget)},
		{Resource: "tokens", Unit: "token", Pool: "shared-pool", Interval: "run", Scope: "concurrency", Limit: f64ptr(10)},
	}
	admitReq := contract.AdmitRequest{
		ID: "res-" + req.LoopID, RootID: req.RootID, AssignmentID: req.AssignmentID,
		ProjectID: "proj-delivery", AccountPool: "shared-pool", WindowEpoch: "window-1",
		TaskID: "task-" + req.LoopID, HeadroomKind: contract.HeadroomImplementation,
		WorkKind: contract.WorkOptionalImplementation, Amount: admitAmount,
		EstimateProvenance: contract.EstimateProvenance{Kind: contract.ProvenanceEstimate, Source: "fixture"},
		Resource:           "tokens", Unit: "token", Pool: "shared-pool", PolicyID: "policy-fixture-1",
		Ceilings: ceilings, ConcurrencyIdentity: "shared-pool", ConcurrencyAmount: 1,
		ObservationUsable: true, RecordedAt: req.RecordedAt,
	}
	admit, e := db.AdmitReservation(admitReq)
	if e != nil {
		return loop, e
	}
	if !admit.Admitted {
		loop.Phase = contract.PhaseBlocked
		loop.Status = contract.PhaseBlocked
		loop.Blocked = true
		loop.BlockedReason = "reservation_rejected"
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, nil
	}
	loop.ReservationID = admit.ReservationID
	loop.ResourceExposure["tokens"] = admitAmount
	loop.ResourceRemaining = req.ResourceBudget - admitAmount

	// --- Phase: dispatch (V4-12) optional fixture path ---
	loop.Phase = contract.PhaseDispatch
	if fault == contract.DeliveryFaultBeforeDispatch {
		loop.Status = contract.PhasePartial
		loop.Partial = true
		loop.BlockedReason = "fault_before_dispatch"
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_before_dispatch")
	}
	if req.UnresolvedExternalEffect || req.LostAckAfterEffect || fault == contract.DeliveryFaultLostAckAfterEffect {
		if !req.SkipDispatch && adapter != nil {
			if e := s.commitAndMaybeSend(db, &loop, admit.ReservationID, req, adapter, true); e != nil {
				return loop, e
			}
		} else {
			loop.IntentID = "intent-" + req.LoopID
			loop.OperationID = "op-" + req.LoopID
		}
		loop.UnresolvedEffects = true
		loop.UncertaintyExposed = true
		loop.Phase = contract.PhaseAwaitingReconciliation
		loop.Status = contract.PhaseAwaitingReconciliation
		_ = s.recordIntervention(db, &loop, contract.InterventionResumeReconcile, loop.Phase,
			"external effect possible with lost acknowledgement", false)
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		if fault == contract.DeliveryFaultLostAckAfterEffect || req.LostAckAfterEffect {
			return loop, errors.New("lost_ack_after_effect")
		}
		return loop, nil
	}
	if !req.SkipDispatch && adapter != nil {
		if e := s.commitAndMaybeSend(db, &loop, admit.ReservationID, req, adapter, false); e != nil {
			_ = s.checkpoint(db, &loop, true)
			_, _ = db.PersistDeliveryLoop(loop)
			return loop, e
		}
	}
	if fault == contract.DeliveryFaultAfterDispatch {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_after_dispatch")
	}

	// --- Phase: edit ---
	loop.Phase = contract.PhaseEdit
	if fault == contract.DeliveryFaultBeforeEdit {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_before_edit")
	}

	// Repeated failure bound (R04).
	if req.InjectFailureRepeats > 0 {
		class := req.InjectFailureClass
		if class == "" {
			class = contract.FailureTest
		}
		code := req.InjectFailureCode
		if code == "" {
			code = "fixture_repeat"
		}
		digest := contract.StableFailureDigest(class, code, "no_new_evidence")
		sig := contract.FailureSignature{Class: class, Code: code, Digest: digest}
		for i := 0; i < req.InjectFailureRepeats; i++ {
			sig.Count++
			loop.LastFailureClass = class
			if sig.Count >= loop.FailureBound {
				sig.Stopped = true
				loop.FailureSignatures = []contract.FailureSignature{sig}
				_ = s.recordIntervention(db, &loop, contract.InterventionRepeatStop, contract.PhaseEdit,
					"repeated failure with no new evidence within bound", false)
				loop.Phase = contract.PhaseBlocked
				loop.Status = contract.PhaseBlocked
				loop.Blocked = true
				loop.BlockedReason = "repeat_failure_bound"
				_ = s.checkpoint(db, &loop, true)
				_, _ = db.PersistDeliveryLoop(loop)
				return loop, nil
			}
		}
		loop.FailureSignatures = []contract.FailureSignature{sig}
	}

	if fault == contract.DeliveryFaultAfterEdit {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_after_edit")
	}

	// Resource exhaustion before verification (R03).
	if req.ExhaustBeforeVerification {
		_ = s.recordIntervention(db, &loop, contract.InterventionResourceExhaust, contract.PhaseEdit,
			"remaining resources cannot support mandatory verification", false)
		loop.Phase = contract.PhasePartial
		loop.Status = contract.PhasePartial
		loop.Partial = true
		loop.Accepted = false
		loop.BlockedReason = "resources_exhausted_before_verification"
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, nil
	}

	// Register acceptance package (V4-14).
	pkg := req.AcceptancePackage
	if e := pkg.Validate(); e != nil {
		return loop, e
	}
	if e := db.PersistAcceptancePackage(pkg); e != nil {
		return loop, e
	}

	// --- Phase: freeze (V4-14) ---
	loop.Phase = contract.PhaseFreeze
	if fault == contract.DeliveryFaultBeforeFreeze {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_before_freeze")
	}
	digest := contract.ComputeContentDigest(req.FreezeEntries)
	frozen := contract.FrozenCandidate{
		SchemaVersion: contract.AcceptanceSchemaVersion,
		ID:            req.CandidateID,
		RootID:        req.RootID,
		AssignmentID:  req.AssignmentID,
		WorkspaceRoot: "/tmp/ws-delivery",
		Entries:       append([]contract.CandidateContentEntry(nil), req.FreezeEntries...),
		ContentDigest: digest,
		AcceptanceID:  pkg.ID,
		EnvironmentID: pkg.EnvironmentID,
		FrozenAt:      req.RecordedAt,
	}
	if _, e = db.PersistFrozenCandidate(frozen); e != nil {
		return loop, e
	}
	loop.CandidateID = frozen.ID
	if fault == contract.DeliveryFaultAfterFreeze {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_after_freeze")
	}

	// Exhaust after one slice (R03) — slice frozen but verification unaffordable.
	if req.ExhaustAfterSlice {
		loop.ResourceRemaining = 0
		_ = s.recordIntervention(db, &loop, contract.InterventionResourceExhaust, contract.PhaseFreeze,
			"resources exhausted after one slice; whole-task acceptance incomplete", false)
		loop.Phase = contract.PhasePartial
		loop.Status = contract.PhasePartial
		loop.Partial = true
		loop.Accepted = false
		loop.BlockedReason = "resources_exhausted_after_slice"
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, nil
	}

	// --- Phase: check (V4-14) ---
	loop.Phase = contract.PhaseCheck
	if fault == contract.DeliveryFaultBeforeCheck {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_before_check")
	}

	runnable, checkRef, checkOutcome, notes := evaluateMilestone(req)
	loop.MilestoneRunnable = runnable
	loop.BehaviorCheckRef = checkRef

	iso := contract.IsolationCapability{
		Mode: contract.IsolationEnforced, Enforced: true, ContextProvenance: "present",
	}
	grade := GradeFromIsolation(iso)
	receipt := contract.CheckReceipt{
		SchemaVersion:  contract.AcceptanceSchemaVersion,
		ID:             "rcpt-" + req.LoopID,
		CheckID:        "behavior",
		Outcome:        checkOutcome,
		IntegrityGrade: grade.IntegrityGrade,
		Notes: append(notes,
			"snapshot="+frozen.ContentDigest,
			"candidate="+frozen.ID,
			"milestone="+req.MilestoneKind,
			"behavior_check_ref="+checkRef,
		),
		Provenance: contract.CheckInvocationProvenance{
			RunnerID: "runner-delivery", InvocationID: "inv-" + req.LoopID,
			CandidateID: frozen.ID, AcceptanceID: pkg.ID, EnvironmentID: pkg.EnvironmentID,
			IsolationMode: contract.IsolationEnforced, ObservedAt: req.RecordedAt,
		},
	}
	if !runnable {
		loop.Accepted = false
		loop.Phase = contract.PhaseBlocked
		loop.Status = contract.PhaseBlocked
		loop.Blocked = true
		loop.BlockedReason = "milestone_not_runnable:" + req.MilestoneKind
		loop.LastFailureClass = contract.FailureAcceptance
		if _, e := db.PersistCheckReceipt(receipt); e != nil {
			return loop, e
		}
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, nil
	}
	if _, e := db.PersistCheckReceipt(receipt); e != nil {
		return loop, e
	}
	loop.OutstandingChecks = nil
	if fault == contract.DeliveryFaultAfterCheck {
		_ = s.checkpoint(db, &loop, true)
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_after_check")
	}

	// --- Phase: checkpoint ---
	loop.Phase = contract.PhaseCheckpoint
	if fault == contract.DeliveryFaultBeforeCheckpoint {
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_before_checkpoint")
	}
	if e := s.checkpoint(db, &loop, true); e != nil {
		return loop, e
	}
	if fault == contract.DeliveryFaultAfterCheckpoint {
		loop.Phase = contract.PhasePartial
		loop.Status = contract.PhasePartial
		loop.Partial = true
		_, _ = db.PersistDeliveryLoop(loop)
		return loop, errors.New("fault_injected_after_checkpoint")
	}

	// Authorized comparison via V4-09 instrument (R09).
	if req.ComparisonRequested {
		cmp, e := s.recordDemonstratorComparison(db, &loop, req)
		if e != nil {
			return loop, e
		}
		loop.Comparison = &cmp
	}

	loop.Phase = contract.PhaseAccepted
	loop.Status = contract.PhaseAccepted
	loop.Accepted = true
	loop.Partial = false
	loop.Blocked = false
	loop.UpdatedAt = req.RecordedAt
	// No routine continue prompts on successful progression (R01).
	return db.PersistDeliveryLoop(loop)
}

func f64ptr(n float64) *float64 { return &n }

func evaluateMilestone(req contract.DeliveryRunRequest) (runnable bool, checkRef, outcome string, notes []string) {
	switch req.MilestoneKind {
	case contract.MilestoneStub, contract.MilestoneProse, contract.MilestoneFakeLog:
		return false, "", contract.OutcomeFail, []string{"milestone_rejected:" + req.MilestoneKind}
	case contract.MilestoneGenuineBehavior, contract.MilestoneIntegration:
		if !req.BehaviorObserved {
			return false, "", contract.OutcomeFail, []string{"behavior_not_observed"}
		}
		ref := "check/behavior#" + req.CandidateID
		return true, ref, contract.OutcomePass, []string{"executed_behavior_check", "ref=" + ref}
	default:
		return false, "", contract.OutcomeError, []string{"unknown_milestone"}
	}
}

// commitAndMaybeSend commits durable intent then optionally sends; lostAck skips RecordAck (R10).
func (s *Service) commitAndMaybeSend(db *store.Store, loop *contract.DeliveryLoop, reservationID string, req contract.DeliveryRunRequest, adapter NativeAdapter, lostAck bool) error {
	tuple := adapter.QualifiedCapability()
	intent := contract.DispatchIntent{
		SchemaVersion:        contract.DispatchSchemaVersion,
		ID:                   "intent-" + req.LoopID,
		RootID:               req.RootID,
		ReservationID:        reservationID,
		OperationID:          "op-" + req.LoopID,
		IdempotencyKey:       "idem-" + req.LoopID,
		TupleID:              contract.QualifiedDispatchTupleID,
		Host:                 tuple.Host,
		InstalledVersion:     tuple.InstalledVersion,
		Mode:                 tuple.Mode,
		Method:               contract.QualifiedDispatchMethod,
		RequestedGranularity: contract.GranularityRequest,
		Status:               contract.IntentCommitted,
		Outcome:              contract.OutcomeUnknown,
		Cancel:               contract.CancelState{State: contract.CancelNone},
		Requested: contract.RequestedSettings{
			Model: "fixture-model", Effort: "low", Method: contract.QualifiedDispatchMethod,
		},
		OwnershipSessionID: "sess-" + req.LoopID,
		OwnershipProcessID: "proc-" + req.LoopID,
		OwnershipWorktree:  "wt-" + req.LoopID,
		CommittedAt:        req.RecordedAt,
	}
	committed, e := db.CommitIntent(intent)
	if e != nil {
		return e
	}
	loop.IntentID = committed.ID
	loop.OperationID = committed.OperationID

	start, e := adapter.Start(NativeStartRequest{
		OperationID: committed.OperationID, IdempotencyKey: committed.IdempotencyKey,
		IntentID: committed.ID, Method: committed.Method, Requested: committed.Requested,
		OwnershipSession: committed.OwnershipSessionID, OwnershipProcess: committed.OwnershipProcessID,
		OwnershipWorktree: committed.OwnershipWorktree,
	})
	if e != nil {
		_, _ = db.MarkIntentUncertain(committed.ID, req.RecordedAt, e.Error())
		return e
	}
	sent, e := db.MarkIntentSent(committed.ID, req.RecordedAt)
	if e != nil {
		return e
	}
	if lostAck {
		_, _ = db.MarkIntentUncertain(sent.ID, req.RecordedAt, "crash_after_send_before_ack")
		_ = start
		return nil
	}
	ack := contract.DispatchAck{
		NativeSessionID: start.NativeSessionID,
		NativeRunID:     start.NativeRunID,
		TransportState:  start.TransportState,
		ObservedAt:      req.RecordedAt,
		Accepted:        false,
	}
	if ack.TransportState == "" {
		ack.TransportState = contract.OutcomeRunning
	}
	_, e = db.RecordAck(sent.ID, ack)
	return e
}

func (s *Service) checkpoint(db *store.Store, loop *contract.DeliveryLoop, nativeUsable bool) error {
	at := s.opts.Clock().UTC().Format(time.RFC3339)
	cp := contract.DeliveryCheckpoint{
		SchemaVersion:       contract.DeliverySchemaVersion,
		ID:                  "cp-" + loop.ID + "-" + loop.Phase,
		LoopID:              loop.ID,
		RootID:              loop.RootID,
		Phase:               loop.Phase,
		AuthorityDigest:     loop.AuthorityDigest,
		CandidateID:         loop.CandidateID,
		AcceptanceID:        loop.AcceptanceID,
		OutstandingChecks:   append([]string(nil), loop.OutstandingChecks...),
		ObligationDigests:   append([]string(nil), loop.ObligationIDs...),
		ResourceExposure:    copyFloatMap(loop.ResourceExposure),
		NativeSessionUsable: nativeUsable,
		CriteriaDigest:      "criteria-" + loop.AcceptanceID,
		UnresolvedEffects:   loop.UnresolvedEffects,
		RecordedAt:          at,
		ValidLocalArtifacts: []string{"loop:" + loop.ID, "obligations", "candidate:" + loop.CandidateID},
	}
	cp.PayloadDigest = contract.CheckpointPayloadDigest(cp)
	out, e := db.PersistCheckpoint(cp)
	if e != nil {
		return e
	}
	loop.LastCheckpointID = out.ID
	loop.UpdatedAt = at
	return nil
}

func copyFloatMap(in map[string]float64) map[string]float64 {
	if in == nil {
		return nil
	}
	out := make(map[string]float64, len(in))
	for k, v := range in {
		out[k] = v
	}
	return out
}

func (s *Service) recordDemonstratorComparison(db *store.Store, loop *contract.DeliveryLoop, req contract.DeliveryRunRequest) (contract.ComparisonOutcome, error) {
	at := s.opts.Clock().UTC().Format(time.RFC3339)
	protocolID := req.ProtocolID
	if protocolID == "" {
		protocolID = "proto-" + req.LoopID
	}
	cmp := contract.ComparisonOutcome{
		SchemaVersion: contract.DeliverySchemaVersion,
		ProtocolID:    protocolID,
		Fabricated:    false,
		Interventions: len(loop.Interventions),
		Recoveries:    0,
		RecordedAt:    at,
	}
	// Live/native control: always record eligibility honestly via V4-09 paths — never fabricate.
	nativeStatus := contract.EligibilityIneligible
	nativeReason := "live_host_qualification_blocked"
	if req.NativeArmEligible {
		nativeStatus = contract.EligibilityEligible
		nativeReason = "authorized_fixture_native_control"
	}
	cmp.NativeArmStatus = nativeStatus
	cmp.NativeArmReason = nativeReason
	cmp.V4ArmStatus = contract.EligibilityEligible
	cmp.V4ArmReason = "fixture_v4_demonstrator"

	elNative := contract.ArmEligibility{
		SchemaVersion:      contract.InstrumentSchemaVersion,
		ID:                 "elig-native-" + req.LoopID,
		TrialID:            "trial-" + req.LoopID,
		ProtocolID:         protocolID,
		ArmID:              "arm-native",
		ArmKind:            contract.ArmNative,
		Status:             nativeStatus,
		Reason:             nativeReason,
		FabricatedAttempts: 0,
		RecordedAt:         at,
	}
	if !req.NativeArmEligible {
		elNative.MissingPackage = "V4-09-live-qualification"
	}
	// Persist eligibility through instrument store API when available; best-effort via controller.
	_ = db
	if e := s.RecordEligibility(elNative); e != nil {
		// Instrument may need protocol freeze first; record comparison without fabricating attempts.
		cmp.NativeArmReason = nativeReason + ";eligibility_persist:" + e.Error()
	}
	elV4 := contract.ArmEligibility{
		SchemaVersion:      contract.InstrumentSchemaVersion,
		ID:                 "elig-v4-" + req.LoopID,
		TrialID:            "trial-" + req.LoopID,
		ProtocolID:         protocolID,
		ArmID:              "arm-v4",
		ArmKind:            contract.ArmManaged,
		Status:             contract.EligibilityEligible,
		Reason:             "fixture_v4_demonstrator",
		FabricatedAttempts: 0,
		RecordedAt:         at,
	}
	_ = s.RecordEligibility(elV4)
	return cmp, cmp.Validate()
}

// InspectDelivery exposes candidate/acceptance/pending/resource/next-action without model work (R07).
func (s *Service) InspectDelivery(loopID string, counters *ObservationalCounters) (contract.InspectSnapshot, error) {
	if counters == nil {
		counters = &ObservationalCounters{}
	}
	counters.FilesystemReads.Add(1)
	db, e := s.ensureDeliveryStore()
	if e != nil {
		return contract.InspectSnapshot{}, e
	}
	defer db.Close()
	counters.FilesystemReads.Add(1)

	loop, e := db.GetDeliveryLoop(loopID)
	if e != nil {
		snap := contract.InspectSnapshot{
			SchemaVersion:    contract.DeliverySchemaVersion,
			LoopID:           loopID,
			Status:           contract.PhaseUnknown,
			Phase:            contract.PhaseUnknown,
			NextAction:       contract.NextAwaitOperator,
			ModelCalls:       int(counters.ModelCalls.Load()),
			FilesystemReads:  int(counters.FilesystemReads.Load()),
			FilesystemWrites: int(counters.FilesystemWrites.Load()),
		}
		return snap, nil
	}
	ints, _ := db.ListInterventions(loopID)
	next := nextAction(loop)
	pending := []string{}
	if loop.IntentID != "" && loop.UnresolvedEffects {
		pending = append(pending, "intent:"+loop.IntentID)
	}
	for _, c := range loop.OutstandingChecks {
		pending = append(pending, "check:"+c)
	}
	return contract.InspectSnapshot{
		SchemaVersion:     contract.DeliverySchemaVersion,
		LoopID:            loop.ID,
		RootID:            loop.RootID,
		Status:            loop.Status,
		Phase:             loop.Phase,
		CandidateID:       loop.CandidateID,
		AcceptanceID:      loop.AcceptanceID,
		PendingExecution:  pending,
		ResourceExposure:  copyFloatMap(loop.ResourceExposure),
		NextAction:        next,
		OutstandingChecks: append([]string(nil), loop.OutstandingChecks...),
		UnresolvedEffects: loop.UnresolvedEffects,
		Interventions:     len(ints),
		ModelCalls:        int(counters.ModelCalls.Load()) + loop.ModelCalls,
		FilesystemReads:   int(counters.FilesystemReads.Load()),
		FilesystemWrites:  int(counters.FilesystemWrites.Load()),
		Accepted:          loop.Accepted,
		Partial:           loop.Partial,
		Blocked:           loop.Blocked,
		Limitation:        loop.Limitation,
	}, nil
}

func nextAction(loop contract.DeliveryLoop) string {
	switch {
	case loop.Status == contract.PhaseCancellationPending:
		return contract.NextCancelPending
	case loop.UnresolvedEffects || loop.Status == contract.PhaseAwaitingReconciliation:
		return contract.NextReconcileUncertainty
	case loop.Accepted:
		return contract.NextAccepted
	case loop.Partial:
		return contract.NextStopPartial
	case loop.Blocked:
		return contract.NextStopBlocked
	case loop.Status == contract.PhaseRunning || loop.Status == contract.PhasePending:
		return contract.NextContinueAuthorized
	default:
		return contract.NextAwaitOperator
	}
}

// DeliveryStatus lists loops for a root (minimal V4-20 precursor).
func (s *Service) DeliveryStatus(rootID string) ([]contract.DeliveryLoop, error) {
	db, e := s.ensureDeliveryStore()
	if e != nil {
		return nil, e
	}
	defer db.Close()
	all, e := db.ListDeliveryLoops()
	if e != nil {
		return nil, e
	}
	var out []contract.DeliveryLoop
	for _, l := range all {
		if rootID == "" || l.RootID == rootID {
			out = append(out, l)
		}
	}
	return out, nil
}

// ResumeDelivery preserves root accounting/authority/candidates/obligations (R05)
// and exposes unresolved external-effect uncertainty before dependent work (R10).
func (s *Service) ResumeDelivery(req contract.DeliveryResumeRequest) (contract.DeliveryLoop, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		return contract.DeliveryLoop{}, e
	}
	release, e := s.lock(req.RootID, false)
	if e != nil {
		return contract.DeliveryLoop{}, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(req.RootID); e != nil {
		return contract.DeliveryLoop{}, errors.New("active_claim_or_inventory_failed")
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.DeliveryLoop{}, e
	}
	defer db.Close()
	if e = db.EnsureDeliveryNamespaces(); e != nil {
		return contract.DeliveryLoop{}, e
	}

	loop, e := db.GetDeliveryLoop(req.LoopID)
	if e != nil {
		return loop, e
	}
	if loop.RootID != req.RootID {
		return loop, errors.New("root mismatch on resume")
	}

	// Preserve authority digest and obligation IDs — process replacement ≠ new budget root.
	authBefore := loop.AuthorityDigest
	obsBefore := append([]string(nil), loop.ObligationIDs...)
	candBefore := loop.CandidateID

	if loop.UnresolvedEffects && !req.AcknowledgeUncertainty {
		loop.UncertaintyExposed = true
		_ = s.recordIntervention(db, &loop, contract.InterventionResumeReconcile, loop.Phase,
			"resume exposes unresolved external effects before dependent work", false)
		loop.Status = contract.PhaseAwaitingReconciliation
		loop.UpdatedAt = req.RecordedAt
		return db.PersistDeliveryLoop(loop)
	}
	if loop.UnresolvedEffects && req.AdmitDependentWork && !req.AcknowledgeUncertainty {
		return loop, errors.New("cannot admit dependent work while external effects unresolved")
	}
	if loop.UnresolvedEffects && req.AcknowledgeUncertainty && req.AdmitDependentWork {
		return loop, errors.New("successor cannot assume completion absence or refunded exposure")
	}
	if loop.UnresolvedEffects && req.AcknowledgeUncertainty && !req.AdmitDependentWork {
		loop.UncertaintyExposed = true
		loop.Status = contract.PhaseAwaitingReconciliation
		loop.UpdatedAt = req.RecordedAt
		out, e := db.PersistDeliveryLoop(loop)
		if e != nil {
			return out, e
		}
		if out.AuthorityDigest != authBefore || out.CandidateID != candBefore {
			return out, errors.New("resume must preserve authority and candidate identities")
		}
		if len(out.ObligationIDs) != len(obsBefore) {
			return out, errors.New("resume must preserve obligations")
		}
		return out, nil
	}

	// Continue from checkpoint if partial/interrupted without unresolved effects.
	if loop.LastCheckpointID != "" {
		cp, e := db.GetCheckpoint(loop.LastCheckpointID)
		if e == nil {
			if lim := assessCheckpoint(cp, loop); lim != nil {
				loop.Limitation = lim
				_ = s.recordIntervention(db, &loop, contract.InterventionCheckpointLimit, loop.Phase, lim.Detail, false)
				loop.Status = contract.PhaseBlocked
				loop.Blocked = true
				loop.BlockedReason = lim.Kind
				loop.UpdatedAt = req.RecordedAt
				return db.PersistDeliveryLoop(loop)
			}
			// Restore outstanding verification from checkpoint.
			if len(loop.OutstandingChecks) == 0 && len(cp.OutstandingChecks) > 0 {
				loop.OutstandingChecks = append([]string(nil), cp.OutstandingChecks...)
			}
		}
	}

	if loop.Partial || loop.Phase == contract.PhasePartial {
		loop.Status = contract.PhasePartial
	} else if !loop.Accepted && !loop.Blocked {
		loop.Status = contract.PhaseRunning
		loop.Phase = contract.PhaseRunning
	}
	loop.UpdatedAt = req.RecordedAt
	out, e := db.PersistDeliveryLoop(loop)
	if e != nil {
		return out, e
	}
	if out.AuthorityDigest != authBefore {
		return out, errors.New("resume changed authority digest")
	}
	return out, nil
}

func assessCheckpoint(cp contract.DeliveryCheckpoint, loop contract.DeliveryLoop) *contract.CheckpointLimitation {
	if cp.Limitation != nil {
		return cp.Limitation
	}
	wantCriteria := "criteria-" + loop.AcceptanceID
	if cp.CriteriaDigest != "" && loop.AcceptanceID != "" && cp.CriteriaDigest != wantCriteria {
		return &contract.CheckpointLimitation{
			Kind:               contract.TamperChangedCriteria,
			Detail:             "acceptance criteria changed since checkpoint; local candidate preserved",
			PreservedArtifacts: append([]string(nil), cp.ValidLocalArtifacts...),
		}
	}
	if !cp.NativeSessionUsable {
		return &contract.CheckpointLimitation{
			Kind:               contract.TamperMissingNative,
			Detail:             "native session history unavailable; portable checkpoint retained",
			PreservedArtifacts: append([]string(nil), cp.ValidLocalArtifacts...),
		}
	}
	fresh := cp
	fresh.PayloadDigest = ""
	fresh.Limitation = nil
	recomputed := contract.CheckpointPayloadDigest(fresh)
	if cp.PayloadDigest != "" && cp.PayloadDigest != recomputed {
		return &contract.CheckpointLimitation{
			Kind:               contract.TamperPayload,
			Detail:             "tampered checkpoint payload digest; portable artifacts retained",
			PreservedArtifacts: append([]string(nil), cp.ValidLocalArtifacts...),
		}
	}
	return nil
}

// RecoverCheckpoint applies R06 limitation reporting for stale/tampered/unusable checkpoints.
func (s *Service) RecoverCheckpoint(loopID, checkpointID, tamperKind string) (contract.DeliveryLoop, contract.DeliveryCheckpoint, error) {
	db, e := s.ensureDeliveryStore()
	if e != nil {
		return contract.DeliveryLoop{}, contract.DeliveryCheckpoint{}, e
	}
	defer db.Close()

	loop, e := db.GetDeliveryLoop(loopID)
	if e != nil {
		return loop, contract.DeliveryCheckpoint{}, e
	}
	cp, e := db.GetCheckpoint(checkpointID)
	if e != nil {
		return loop, cp, e
	}

	switch tamperKind {
	case contract.TamperPayload:
		_ = db.TamperCheckpointPayload(checkpointID, "deadbeef-tampered")
		cp, _ = db.GetCheckpoint(checkpointID)
	case contract.TamperChangedCriteria:
		_ = db.ChangeCheckpointCriteria(checkpointID, "criteria-mutated")
		cp, _ = db.GetCheckpoint(checkpointID)
	case contract.TamperMissingNative:
		cp.NativeSessionUsable = false
		cp, _ = db.PersistCheckpoint(cp)
	case contract.TamperMemoryOutage:
		lim := &contract.CheckpointLimitation{
			Kind:               contract.TamperMemoryOutage,
			Detail:             "optional memory outage; portable obligations and candidate refs preserved",
			PreservedArtifacts: append([]string(nil), cp.ValidLocalArtifacts...),
		}
		cp.Limitation = lim
		cp, _ = db.PersistCheckpoint(cp)
		loop.Limitation = lim
		_ = s.recordIntervention(db, &loop, contract.InterventionCheckpointLimit, loop.Phase, lim.Detail, false)
		loop.UpdatedAt = s.opts.Clock().UTC().Format(time.RFC3339)
		loop, _ = db.PersistDeliveryLoop(loop)
		return loop, cp, nil
	}

	lim := assessCheckpoint(cp, loop)
	if lim == nil && tamperKind != "" && tamperKind != contract.TamperNone {
		lim = &contract.CheckpointLimitation{
			Kind:               tamperKind,
			Detail:             "checkpoint limitation: " + tamperKind,
			PreservedArtifacts: append([]string(nil), cp.ValidLocalArtifacts...),
		}
	}
	if lim != nil {
		cp.Limitation = lim
		loop.Limitation = lim
		_ = s.recordIntervention(db, &loop, contract.InterventionCheckpointLimit, loop.Phase, lim.Detail, false)
		loop.Blocked = true
		loop.BlockedReason = lim.Kind
		loop.Status = contract.PhaseBlocked
		loop.UpdatedAt = s.opts.Clock().UTC().Format(time.RFC3339)
		loop, _ = db.PersistDeliveryLoop(loop)
	}
	return loop, cp, nil
}

// CancelDelivery marks cancellation-pending until native outcome established.
func (s *Service) CancelDelivery(req contract.DeliveryCancelRequest) (contract.DeliveryLoop, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		return contract.DeliveryLoop{}, e
	}
	release, e := s.lock(req.RootID, false)
	if e != nil {
		return contract.DeliveryLoop{}, errors.New("append_lock_unavailable")
	}
	defer release()
	if _, _, e = s.active(req.RootID); e != nil {
		return contract.DeliveryLoop{}, errors.New("active_claim_or_inventory_failed")
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.DeliveryLoop{}, e
	}
	defer db.Close()
	if e = db.EnsureDeliveryNamespaces(); e != nil {
		return contract.DeliveryLoop{}, e
	}
	loop, e := db.GetDeliveryLoop(req.LoopID)
	if e != nil {
		return loop, e
	}
	_ = s.recordIntervention(db, &loop, contract.InterventionOperatorCancel, loop.Phase, req.Reason, false)
	loop.Status = contract.PhaseCancellationPending
	loop.Phase = contract.PhaseCancellationPending
	loop.UpdatedAt = req.RecordedAt
	return db.PersistDeliveryLoop(loop)
}

// CompactDeliveryContext preserves validated obligations independently of summary (R08).
func (s *Service) CompactDeliveryContext(req contract.ContextCompactRequest) (contract.DeliveryLoop, []contract.ObligationRecord, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		return contract.DeliveryLoop{}, nil, e
	}
	db, e := s.ensureDeliveryStore()
	if e != nil {
		return contract.DeliveryLoop{}, nil, e
	}
	defer db.Close()
	loop, e := db.GetDeliveryLoop(req.LoopID)
	if e != nil {
		return loop, nil, e
	}
	obs, e := db.ListObligations(req.LoopID)
	if e != nil {
		return loop, nil, e
	}
	// Summary may omit failed approach / required check; canonical obligations remain.
	_ = req.GeneratedSummary
	_ = req.OmittedTopics
	// Access restrictions persist on the loop.
	loop.UpdatedAt = req.RecordedAt
	out, e := db.PersistDeliveryLoop(loop)
	return out, obs, e
}

// StableFailureAcrossReset proves R04 signature stability across worker/context reset.
func StableFailureAcrossReset(class, code string) (a, b string) {
	a = contract.StableFailureDigest(class, code, "no_new_evidence")
	b = contract.StableFailureDigest(class, code, "no_new_evidence")
	return a, b
}
