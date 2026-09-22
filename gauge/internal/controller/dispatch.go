package controller

import (
	"errors"
	"fmt"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

// DispatchFault names crash/fault inject points between commit/send/ack.
type DispatchFault string

const (
	DispatchFaultNone            DispatchFault = ""
	DispatchFaultBeforeCommit    DispatchFault = "before_commit"
	DispatchFaultAfterCommit     DispatchFault = "after_commit_before_send"
	DispatchFaultAfterSend       DispatchFault = "after_send_before_ack"
	DispatchFaultAfterAck        DispatchFault = "after_ack"
	DispatchFaultCommitStoreFail DispatchFault = "commit_store_fail"
)

func (s *Service) ensureDispatchStore() (*store.Store, error) {
	db, e := s.ensureReservationStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureDispatchNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureDispatchNamespaces adds typed dispatch buckets under schema 2.
func (s *Service) EnsureDispatchNamespaces() error {
	db, e := s.ensureDispatchStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// DispatchStoreForTest opens the dispatch-ready store for fixture fault injection.
func (s *Service) DispatchStoreForTest() (*store.Store, error) {
	return s.ensureDispatchStore()
}

func rejectResult(reasons ...string) contract.AdmitDispatchResult {
	return contract.AdmitDispatchResult{Admitted: false, RejectReasons: reasons, NativeSent: false}
}

// AdmitAndDispatch performs managed dispatch:
// (1) preflight method/granularity (2) AdmitReservation (3) durable CommitIntent
// (4) native Start (5) RecordAck. A provider call is NOT made atomic by local storage.
// Fault injectors sit between each step. Live qualification stays blocked (V4-09).
// Holds the append lock once and calls store mutators directly (no nested Service locks).
func (s *Service) AdmitAndDispatch(rootID string, req contract.AdmitDispatchRequest, adapter NativeAdapter, fault DispatchFault) (contract.AdmitDispatchResult, error) {
	var result contract.AdmitDispatchResult
	req.RootID = rootID
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		return rejectResult(e.Error()), nil
	}
	if adapter == nil {
		return rejectResult("native_adapter_required"), nil
	}

	tuple := adapter.QualifiedCapability()

	// Method/granularity/version preflight before catalogue or reservation (R06/R08).
	pre, e := adapter.Preflight(NativePreflightRequest{
		Method: req.Method, RequestedGranularity: req.RequestedGranularity,
		TupleID: req.TupleID, HostVersion: tuple.InstalledVersion,
	})
	if e != nil {
		return rejectResult("preflight_error:" + e.Error()), nil
	}
	if !pre.Allowed {
		return rejectResult(pre.RejectReasons...), nil
	}
	if req.TupleID != tuple.ID {
		return rejectResult("tuple_not_qualified_fixture"), nil
	}
	if req.Method != tuple.Method && !methodQualified(adapter, req.Method) {
		return rejectResult("method_outside_qualified_set:" + req.Method), nil
	}

	// Catalogue only the single fixture-qualified path after preflight admits it.
	if _, e := s.CatalogueCapability(tuple); e != nil {
		return rejectResult("catalogue_failed:" + e.Error()), nil
	}

	release, e := s.lock(rootID, false)
	if e != nil {
		return rejectResult("append_lock_unavailable"), nil
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return rejectResult("active_claim_or_inventory_failed"), nil
	}

	if fault == DispatchFaultBeforeCommit {
		return rejectResult("fault_injected_before_commit"), nil
	}

	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return rejectResult("store_unavailable:" + e.Error()), nil
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		return rejectResult(e.Error()), nil
	}
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return rejectResult(e.Error()), nil
	}

	admitReq := req.Admit
	admitReq.RootID = rootID
	if admitReq.ID == "" {
		admitReq.ID = "res-" + req.IntentID
	}
	if admitReq.RecordedAt == "" {
		admitReq.RecordedAt = req.RecordedAt
	}
	admit, e := db.AdmitReservation(admitReq)
	if e != nil {
		return rejectResult("reservation_error:" + e.Error()), e
	}
	if !admit.Admitted {
		reasons := admit.RejectReasons
		if len(reasons) == 0 {
			reasons = []string{"reservation_rejected"}
		}
		return rejectResult(reasons...), nil
	}
	result.ReservationID = admit.ReservationID

	if fault == DispatchFaultCommitStoreFail {
		return rejectResult("fault_injected_commit_store_fail"), nil
	}

	intent := contract.DispatchIntent{
		SchemaVersion:        contract.DispatchSchemaVersion,
		ID:                   req.IntentID,
		RootID:               rootID,
		ReservationID:        admit.ReservationID,
		OperationID:          req.OperationID,
		IdempotencyKey:       req.IdempotencyKey,
		TupleID:              req.TupleID,
		Host:                 tuple.Host,
		InstalledVersion:     tuple.InstalledVersion,
		Mode:                 tuple.Mode,
		Method:               req.Method,
		RequestedGranularity: req.RequestedGranularity,
		Status:               contract.IntentCommitted,
		Outcome:              contract.OutcomeUnknown,
		Cancel:               contract.CancelState{State: contract.CancelNone},
		Requested:            req.Requested,
		OwnershipSessionID:   req.OwnershipSessionID,
		OwnershipProcessID:   req.OwnershipProcessID,
		OwnershipWorktree:    req.OwnershipWorktree,
		CommittedAt:          req.RecordedAt,
	}
	if intent.Requested.Method == "" {
		intent.Requested.Method = req.Method
	}

	// Durable dispatch intent BEFORE native send (R01).
	committed, e := db.CommitIntent(intent)
	if e != nil {
		return rejectResult("commit_intent_failed:" + e.Error()), nil
	}
	result.Intent = &committed
	result.Admitted = true

	// Idempotent/reconcile reuse: already-acked intents must not duplicate remote effect.
	if committed.Status == contract.IntentAcked || committed.Status == contract.IntentReconciled {
		result.NativeSent = false
		return result, nil
	}

	if fault == DispatchFaultAfterCommit {
		return result, fmt.Errorf("fault_injected_after_commit_before_send")
	}

	if req.LostNativeSession && committed.Reconstruction == nil {
		report, e := adapter.Reconstruct(NativeReconstructRequest{
			LostNativeSession:    true,
			PortableCheckpointID: req.PortableCheckpointID,
			OriginalInvocationID: req.OperationID,
		})
		if e != nil {
			return rejectResult("reconstruction_error:" + e.Error()), nil
		}
		if report.Kind == contract.ReconstructionBlocked || report.Kind == contract.ReconstructionNativeUnavailable {
			committed.Status = contract.IntentBlocked
			committed.Reconstruction = &report
			committed.RejectReasons = []string{report.Detail}
			_, _ = db.SetReconstruction(committed.ID, report)
			result.Intent = &committed
			result.Admitted = false
			result.RejectReasons = committed.RejectReasons
			return result, nil
		}
		updated, e := db.SetReconstruction(committed.ID, report)
		if e != nil {
			return rejectResult(e.Error()), nil
		}
		committed = updated
		result.Intent = &committed
	}

	startRes, e := adapter.Start(NativeStartRequest{
		OperationID: req.OperationID, IdempotencyKey: req.IdempotencyKey,
		IntentID: req.IntentID, Method: req.Method, Requested: intent.Requested,
		OwnershipSession: req.OwnershipSessionID, OwnershipProcess: req.OwnershipProcessID,
		OwnershipWorktree: req.OwnershipWorktree,
	})
	snap := adapterCounters(adapter)
	result.TransportCalls = snap.Start
	result.NativeSent = snap.Start > 0

	if e != nil {
		uncertain, markErr := db.MarkIntentUncertain(committed.ID, req.RecordedAt, e.Error())
		if markErr == nil {
			result.Intent = &uncertain
		}
		_, _ = db.MarkReservationUncertain(contract.MarkUncertainRequest{
			ReservationID: admit.ReservationID, RecordedAt: req.RecordedAt,
			Reason: contract.UncertainCrash,
		})
		return result, e
	}

	sent, e := db.MarkIntentSent(committed.ID, req.RecordedAt)
	if e != nil {
		return result, e
	}
	sent.Observed = startRes.Observed
	result.Intent = &sent
	result.NativeSent = true

	if fault == DispatchFaultAfterSend {
		uncertain, markErr := db.MarkIntentUncertain(sent.ID, req.RecordedAt, "crash_after_send_before_ack")
		if markErr == nil {
			result.Intent = &uncertain
		}
		_, _ = db.MarkReservationUncertain(contract.MarkUncertainRequest{
			ReservationID: admit.ReservationID, RecordedAt: req.RecordedAt,
			Reason: contract.UncertainCrash,
		})
		return result, fmt.Errorf("fault_injected_after_send_before_ack")
	}

	ack := contract.DispatchAck{
		NativeSessionID: startRes.NativeSessionID,
		NativeRunID:     startRes.NativeRunID,
		TransportState:  startRes.TransportState,
		ObservedAt:      req.RecordedAt,
		Accepted:        false,
	}
	acked, e := db.RecordAck(sent.ID, ack)
	if e != nil {
		uncertain, _ := db.MarkIntentUncertain(sent.ID, req.RecordedAt, e.Error())
		result.Intent = &uncertain
		_, _ = db.MarkReservationUncertain(contract.MarkUncertainRequest{
			ReservationID: admit.ReservationID, RecordedAt: req.RecordedAt,
			Reason: contract.UncertainMissingCallback,
		})
		return result, e
	}
	acked.Observed = startRes.Observed
	result.Intent = &acked

	if fault == DispatchFaultAfterAck {
		return result, fmt.Errorf("fault_injected_after_ack")
	}
	return result, nil
}

func methodQualified(adapter NativeAdapter, method string) bool {
	if fake, ok := adapter.(*FakeNativeAdapter); ok {
		return fake.QualifiedMethods[method]
	}
	return method == adapter.QualifiedCapability().Method
}

func adapterCounters(adapter NativeAdapter) NativeMethodCounters {
	if fake, ok := adapter.(*FakeNativeAdapter); ok {
		return fake.Counters.Snapshot()
	}
	return NativeMethodCounters{}
}

// CancelDispatch requests cancellation; state stays nonterminal until native outcome (R04).
func (s *Service) CancelDispatch(rootID string, req contract.CancelDispatchRequest, adapter NativeAdapter) (contract.DispatchIntent, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.DispatchIntent{}, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.DispatchIntent{}, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.DispatchIntent{}, e
	}
	defer db.Close()
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return contract.DispatchIntent{}, e
	}
	intent, e := db.CancelRequest(req.IntentID, req.RecordedAt)
	if e != nil {
		return intent, e
	}
	if intent.RootID != rootID {
		return intent, errors.New("intent root mismatch")
	}
	if adapter == nil {
		return intent, nil
	}
	ir, e := adapter.Interrupt(NativeInterruptRequest{
		IntentID: intent.ID, OperationID: intent.OperationID,
		OwnershipSession: intent.OwnershipSessionID, OwnershipProcess: intent.OwnershipProcessID,
	})
	if e != nil {
		intent.Cancel.AckMissing = true
		return intent, nil
	}
	if ir.Accepted {
		return db.RecordInterruptAccepted(intent.ID, req.RecordedAt, ir.ProcessAlive, ir.AckMissing, ir.UsageDelayed)
	}
	return intent, nil
}

// ConfirmDispatchStopped records confirmed native stop (still ≠ final reconciliation).
func (s *Service) ConfirmDispatchStopped(rootID, intentID, at string) (contract.DispatchIntent, error) {
	if at == "" {
		at = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.DispatchIntent{}, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.DispatchIntent{}, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.DispatchIntent{}, e
	}
	defer db.Close()
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return contract.DispatchIntent{}, e
	}
	return db.ConfirmCancelStopped(intentID, at)
}

// ReconcileDispatch reconciles existing intent before any redispatch (R02).
func (s *Service) ReconcileDispatch(rootID string, req contract.ReconcileDispatchRequest, adapter NativeAdapter) (contract.ReconcileDispatchResult, error) {
	var out contract.ReconcileDispatchResult
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return out, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return out, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return out, e
	}
	defer db.Close()
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return out, e
	}
	intent, e := db.GetIntent(req.IntentID)
	if e != nil {
		return out, e
	}
	if intent.RootID != rootID {
		return out, errors.New("intent root mismatch")
	}

	if adapter == nil || !adapter.SupportsLookup() {
		updated, e := db.ReconcileIntent(intent.ID, req.RecordedAt, contract.ReconcileUnsupported,
			"lookup_unsupported_remains_unknown", nil)
		if e != nil {
			return out, e
		}
		out.Status = contract.ReconcileUnsupported
		out.Intent = &updated
		out.Redispatched = false
		out.Detail = "unsupported lookup remains unknown; no automatic retry"
		return out, nil
	}

	lookup, e := adapter.Lookup(intent.OperationID)
	if e != nil {
		return out, e
	}
	if !lookup.Supported {
		updated, e := db.ReconcileIntent(intent.ID, req.RecordedAt, contract.ReconcileUnsupported,
			"lookup_unsupported", nil)
		if e != nil {
			return out, e
		}
		out.Status = contract.ReconcileUnsupported
		out.Intent = &updated
		out.Redispatched = false
		return out, nil
	}
	if !lookup.Found {
		updated, e := db.ReconcileIntent(intent.ID, req.RecordedAt, contract.ReconcileUnresolved,
			"operation_not_found", nil)
		if e != nil {
			return out, e
		}
		out.Status = contract.ReconcileUnresolved
		out.Intent = &updated
		out.Redispatched = false
		return out, nil
	}

	_, _ = db.ReconcileReservation(contract.ReconcileRequest{
		ReservationID: intent.ReservationID, RecordedAt: req.RecordedAt,
		Actual: 0, Release: false,
	})
	updated, e := db.ReconcileIntent(intent.ID, req.RecordedAt, contract.ReconcileResolved,
		"lookup_resolved:"+lookup.TransportState, nil)
	if e != nil {
		return out, e
	}
	out.Status = contract.ReconcileResolved
	out.Intent = &updated
	out.Redispatched = false
	if req.AllowRedispatch {
		out.Detail = "resolved; redispatch requires a new operator request with same operation identity"
	}
	return out, nil
}

// RecordDispatchEvent records observed values separately from requested settings (R03).
func (s *Service) RecordDispatchEvent(rootID string, ev contract.NativeEvent) (contract.NativeEvent, error) {
	if ev.RecordedAt == "" {
		ev.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return ev, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return ev, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return ev, e
	}
	defer db.Close()
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return ev, e
	}
	return db.RecordEvent(ev)
}

// CleanupDispatch removes only owned resources (R05).
func (s *Service) CleanupDispatch(rootID, intentID string, adapter NativeAdapter, adjacentSessions, adjacentProcs, adjacentTrees []string) (NativeCleanupResult, error) {
	var empty NativeCleanupResult
	release, e := s.lock(rootID, false)
	if e != nil {
		return empty, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return empty, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return empty, e
	}
	defer db.Close()
	intent, e := db.GetIntent(intentID)
	if e != nil {
		return empty, e
	}
	if intent.RootID != rootID {
		return empty, errors.New("intent root mismatch")
	}
	if adapter == nil {
		return empty, errors.New("adapter required")
	}
	return adapter.Cleanup(NativeCleanupRequest{
		OwnershipSession: intent.OwnershipSessionID, OwnershipProcess: intent.OwnershipProcessID,
		OwnershipWorktree: intent.OwnershipWorktree,
		AdjacentSessions: adjacentSessions, AdjacentProcesses: adjacentProcs, AdjacentWorktrees: adjacentTrees,
	})
}

// DispatchStatus returns intents for a root.
func (s *Service) DispatchStatus(rootID string) ([]contract.DispatchIntent, error) {
	if _, _, e := s.active(rootID); e != nil {
		return nil, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return nil, e
	}
	defer db.Close()
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return nil, e
	}
	return db.ListIntents(rootID)
}

// DispatchEvents returns native events for an intent.
func (s *Service) DispatchEvents(rootID, intentID string) ([]contract.NativeEvent, error) {
	if _, _, e := s.active(rootID); e != nil {
		return nil, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return nil, e
	}
	defer db.Close()
	if e = db.EnsureDispatchNamespaces(); e != nil {
		return nil, e
	}
	intent, e := db.GetIntent(intentID)
	if e != nil {
		return nil, e
	}
	if intent.RootID != rootID {
		return nil, errors.New("intent root mismatch")
	}
	return db.ListNativeEvents(intentID)
}

// ReplayDispatch reuses original operation identity for supported idempotency (R07).
func (s *Service) ReplayDispatch(rootID string, req contract.AdmitDispatchRequest, adapter NativeAdapter) (contract.AdmitDispatchResult, error) {
	if adapter == nil {
		return rejectResult("native_adapter_required"), nil
	}
	if !adapter.SupportsIdempotencyKey() && !adapter.SupportsLookup() {
		return contract.AdmitDispatchResult{
			Admitted: false, RejectReasons: []string{"no_lookup_or_idempotency_key_support"},
			NativeSent: false,
		}, nil
	}
	return s.AdmitAndDispatch(rootID, req, adapter, DispatchFaultNone)
}
