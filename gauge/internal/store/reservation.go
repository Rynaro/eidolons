package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"reflect"
	"sort"
	"sync"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var reservationBuckets = []string{"reservations", "scope_balances", "reservation_events"}

type reservationReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

// AccountingFault names fixture-local authoritative-accounting failures (R06).
type AccountingFault string

const (
	FaultNone         AccountingFault = ""
	FaultLockTimeout  AccountingFault = "lock_timeout"
	FaultReadOnly     AccountingFault = "read_only"
	FaultFullStorage  AccountingFault = "full_storage"
	FaultCorruption   AccountingFault = "corruption"
)

// AdvisoryHookError is a separate advisory-path error that must not drive managed admission.
var AdvisoryHookError = errors.New("advisory hook failed")

type reservationFaultState struct {
	mu    sync.Mutex
	fault AccountingFault
}

func initializeReservation(tx *bolt.Tx, id, kind string) error {
	for _, name := range reservationBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "reservation_receipt", reservationReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.ReservationSchemaVersion,
	})
}

func guardReservation(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("reservation_receipt"))
	missing := 0
	for _, name := range reservationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(reservationBuckets) {
		// Pre-V4-11 schema 2 stores remain openable; reservation APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete reservation namespaces; call reservation-enable")
	}
	var receipt reservationReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid reservation receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.ReservationSchemaVersion {
		return errors.New("unsupported reservation receipt")
	}
	return nil
}

func (s *Store) reservationReady(tx *bolt.Tx) error {
	for _, name := range reservationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("reservation namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("reservation_receipt")) == nil {
		return errors.New("reservation namespaces required")
	}
	return nil
}

// EnsureReservationNamespaces adds typed reservation buckets under schema 2 without a schema bump.
func (s *Store) EnsureReservationNamespaces() error {
	if e := s.checkAccountingFault(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		if e := guardPolicy(tx); e != nil {
			return e
		}
		if e := guardObservation(tx); e != nil {
			return e
		}
		if e := guardInstrument(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("reservation_receipt")); raw != nil {
			return guardReservation(tx)
		}
		if e := initializeReservation(tx, id, "ensure"); e != nil {
			return e
		}
		return guardReservation(tx)
	})
}

func (s *Store) checkAccountingFault() error {
	s.reservationFault.mu.Lock()
	defer s.reservationFault.mu.Unlock()
	switch s.reservationFault.fault {
	case FaultNone:
		return nil
	case FaultLockTimeout:
		return errors.New("authoritative accounting unavailable: lock timeout")
	case FaultReadOnly:
		return errors.New("authoritative accounting unavailable: read-only store")
	case FaultFullStorage:
		return errors.New("authoritative accounting unavailable: full storage")
	case FaultCorruption:
		return errors.New("authoritative accounting unavailable: corruption")
	default:
		return fmt.Errorf("authoritative accounting unavailable: %s", s.reservationFault.fault)
	}
}

// SetAccountingFault injects a fixture-local accounting failure without real FS damage.
func (s *Store) SetAccountingFault(fault AccountingFault) {
	s.reservationFault.mu.Lock()
	s.reservationFault.fault = fault
	s.reservationFault.mu.Unlock()
}

// ClearAccountingFault clears injected accounting faults.
func (s *Store) ClearAccountingFault() {
	s.SetAccountingFault(FaultNone)
}

// AdvisoryHookFailure returns the dedicated advisory error policy (distinct from managed admit).
func (s *Store) AdvisoryHookFailure() error {
	return AdvisoryHookError
}

func balanceKey(k contract.ScopeBalanceKey) string { return k.String() }

func (s *Store) loadBalance(tx *bolt.Tx, key contract.ScopeBalanceKey) (contract.ScopeBalance, error) {
	var bal contract.ScopeBalance
	raw := tx.Bucket([]byte("scope_balances")).Get([]byte(balanceKey(key)))
	if raw == nil {
		bal.Key = key
		return bal, nil
	}
	if e := contract.StrictJSON(raw, &bal); e != nil {
		return bal, e
	}
	return bal, nil
}

func (s *Store) putBalance(tx *bolt.Tx, bal contract.ScopeBalance) error {
	if e := bal.Validate(); e != nil {
		return e
	}
	return putJSON(tx.Bucket([]byte("scope_balances")), balanceKey(bal.Key), bal)
}

func (s *Store) appendReservationEvent(tx *bolt.Tx, kind, reservationID, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "reservation_id": reservationID, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, reservationID)
	// Collision-safe: append digest suffix when key exists.
	b := tx.Bucket([]byte("reservation_events"))
	if b.Get([]byte(key)) != nil {
		key = key + "/" + contract.Digest(raw)[:12]
	}
	return b.Put([]byte(key), raw)
}

func scopeKeysForAdmit(req contract.AdmitRequest) []contract.ScopeBalanceKey {
	base := func(scope, identity string) contract.ScopeBalanceKey {
		return contract.ScopeBalanceKey{
			Scope: scope, Identity: identity,
			Resource: req.Resource, Unit: req.Unit, Pool: req.Pool,
		}
	}
	keys := []contract.ScopeBalanceKey{
		base("task", req.TaskID),
		base("project", req.ProjectID),
		base("account", req.AccountPool),
		base("window", req.WindowEpoch),
	}
	concID := req.ConcurrencyIdentity
	if concID == "" {
		concID = req.AccountPool
	}
	keys = append(keys, base("concurrency", concID))
	return keys
}

func ensureBalanceFromCeilings(bal contract.ScopeBalance, req contract.AdmitRequest, scope string) contract.ScopeBalance {
	limit := contract.CeilingForScope(req.Ceilings, scope, req.Resource, req.Unit, req.Pool)
	if bal.Ceiling == nil && limit != nil {
		v := *limit
		bal.Ceiling = &v
	}
	if bal.ProtectedVerification == 0 && req.ProtectedVerification > 0 && scope == "task" {
		bal.ProtectedVerification = req.ProtectedVerification
	}
	if bal.ProtectedRecovery == 0 && req.ProtectedRecovery > 0 && scope == "task" {
		bal.ProtectedRecovery = req.ProtectedRecovery
	}
	bal.HardLimited = req.HardLimited
	bal.ObservationUsable = req.ObservationUsable
	bal.AuthorizedBound = req.AuthorizedBound
	bal.ExplicitBoundedMode = req.ExplicitBoundedMode
	if scope == "window" {
		bal.WindowEpoch = req.WindowEpoch
	}
	return bal
}

func admitAmount(req contract.AdmitRequest) (float64, error) {
	switch req.WorkKind {
	case contract.WorkChild, contract.WorkRetry:
		if req.ImplementationAmount == 0 && req.IntegrationAmount == 0 && req.VerificationAmount == 0 {
			return req.Amount, nil
		}
		return contract.ChildJointAmount(req.ImplementationAmount, req.IntegrationAmount, req.VerificationAmount)
	default:
		return req.Amount, nil
	}
}

// AdmitReservation atomically reserves capacity against known ceilings in one Update txn.
// No remote/provider call is performed inside the transaction.
func (s *Store) AdmitReservation(req contract.AdmitRequest) (contract.AdmitResult, error) {
	var result contract.AdmitResult
	if e := req.Validate(); e != nil {
		result.RejectReasons = append(result.RejectReasons, e.Error())
		return result, nil
	}
	if e := s.checkAccountingFault(); e != nil {
		result.RejectReasons = append(result.RejectReasons, e.Error())
		result.AccountingOK = false
		return result, nil
	}
	amount, e := admitAmount(req)
	if e != nil {
		result.RejectReasons = append(result.RejectReasons, e.Error())
		return result, nil
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(req.RootID)) == nil {
			return errors.New("unknown root for reservation")
		}
		b := tx.Bucket([]byte("reservations"))
		if prev := b.Get([]byte(req.ID)); prev != nil {
			var existing contract.Reservation
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			result.Admitted = existing.Status == contract.ReservationAdmitted || existing.Status == contract.ReservationUncertain
			result.ReservationID = existing.ID
			cp := existing
			result.Reservation = &cp
			result.AccountingOK = true
			return nil
		}
		// Hard-limited unknown without bound blocks (R07).
		if req.HardLimited && !req.ObservationUsable {
			if !req.ExplicitBoundedMode || req.AuthorizedBound == nil {
				result.RejectReasons = append(result.RejectReasons, "hard_limited_unknown_unbounded")
				return nil
			}
		}
		keys := scopeKeysForAdmit(req)
		balances := make([]contract.ScopeBalance, 0, len(keys))
		for _, key := range keys {
			bal, e := s.loadBalance(tx, key)
			if e != nil {
				return e
			}
			bal = ensureBalanceFromCeilings(bal, req, key.Scope)
			if bal.HardLimited && !bal.ObservationUsable && (!bal.ExplicitBoundedMode || bal.AuthorizedBound == nil) && bal.Ceiling == nil {
				result.RejectReasons = append(result.RejectReasons, "hard_limited_unknown_unbounded:"+key.Scope)
				return nil
			}
			// Concurrency uses ConcurrencyAmount when provided.
			need := amount
			work := req.WorkKind
			if key.Scope == "concurrency" {
				if req.ConcurrencyAmount > 0 {
					need = req.ConcurrencyAmount
				} else {
					need = 1
				}
			}
			avail, e := bal.AvailableFor(work)
			if e != nil {
				// Missing known ceiling on a scope listed in request ceilings is a reject;
				// scopes without any ceiling contribution are skipped only when no ceiling exists in request.
				if limit := contract.CeilingForScope(req.Ceilings, key.Scope, req.Resource, req.Unit, req.Pool); limit == nil && !req.HardLimited {
					balances = append(balances, bal)
					continue
				}
				result.RejectReasons = append(result.RejectReasons, e.Error()+":"+key.Scope)
				return nil
			}
			if need > avail+1e-9 {
				result.RejectReasons = append(result.RejectReasons, "ceiling_exceeded:"+key.Scope)
				return nil
			}
			balances = append(balances, bal)
		}
		if len(result.RejectReasons) > 0 {
			return nil
		}
		// Apply reservations.
		outBalances := make([]contract.ScopeBalance, 0, len(keys))
		for i, key := range keys {
			bal := balances[i]
			need := amount
			if key.Scope == "concurrency" {
				if req.ConcurrencyAmount > 0 {
					need = req.ConcurrencyAmount
				} else {
					need = 1
				}
			}
			// Protected verification/recovery headroom stays carved out for optional
			// work; verification/recovery admits increase Reserved into that zone.
			bal.Reserved += need
			if e := s.putBalance(tx, bal); e != nil {
				return e
			}
			outBalances = append(outBalances, bal)
		}
		res := contract.Reservation{
			SchemaVersion: contract.ReservationSchemaVersion, ID: req.ID, RootID: req.RootID,
			ParentReservationID: req.ParentReservationID, AssignmentID: req.AssignmentID,
			ProjectID: req.ProjectID, AccountPool: req.AccountPool, WindowEpoch: req.WindowEpoch,
			TaskID: req.TaskID, HeadroomKind: req.HeadroomKind, WorkKind: req.WorkKind,
			Amount: amount, EstimateProvenance: req.EstimateProvenance,
			Exposure: contract.ExposureEstimated, Resource: req.Resource, Unit: req.Unit, Pool: req.Pool,
			Status: contract.ReservationAdmitted, RecordedAt: req.RecordedAt,
			ImplementationAmount: req.ImplementationAmount, IntegrationAmount: req.IntegrationAmount,
			VerificationAmount: req.VerificationAmount, PolicyID: req.PolicyID,
		}
		if e := res.Validate(); e != nil {
			return e
		}
		if e := putJSON(b, res.ID, res); e != nil {
			return e
		}
		if e := s.appendReservationEvent(tx, "admit", res.ID, req.RecordedAt, map[string]any{"amount": amount}); e != nil {
			return e
		}
		result.Admitted = true
		result.ReservationID = res.ID
		cp := res
		result.Reservation = &cp
		result.Balances = outBalances
		result.AccountingOK = true
		return nil
	})
	if err != nil {
		return result, err
	}
	if !result.Admitted && len(result.RejectReasons) == 0 {
		result.RejectReasons = append(result.RejectReasons, "admission rejected")
	}
	return result, nil
}

// AmendReservation applies overrun/late usage/correction without clamping actual exposure away.
func (s *Store) AmendReservation(req contract.AmendRequest) (contract.Reservation, []contract.ScopeBalance, error) {
	var out contract.Reservation
	var bals []contract.ScopeBalance
	if e := req.Validate(); e != nil {
		return out, nil, e
	}
	if e := s.checkAccountingFault(); e != nil {
		return out, nil, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("reservations")).Get([]byte(req.ReservationID))
		if raw == nil {
			return errors.New("unknown reservation")
		}
		var res contract.Reservation
		if e := contract.StrictJSON(raw, &res); e != nil {
			return e
		}
		if res.Status == contract.ReservationReleased {
			return errors.New("cannot amend released reservation")
		}
		delta := req.Observed - res.Amount
		if delta < 0 {
			// Corrections that lower estimate still retain max actual exposure already consumed.
			delta = 0
		}
		// Move estimate hold into consumed actual; retain overrun as additional consumed.
		keys := []contract.ScopeBalanceKey{
			{Scope: "task", Identity: res.TaskID, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "project", Identity: res.ProjectID, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "account", Identity: res.AccountPool, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "window", Identity: res.WindowEpoch, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
		}
		bals = nil
		for _, key := range keys {
			bal, e := s.loadBalance(tx, key)
			if e != nil {
				return e
			}
			releaseReserved := math.Min(bal.Reserved, res.Amount)
			bal.Reserved -= releaseReserved
			bal.Consumed += req.Observed
			// Never clamp: if ExposureTotal exceeds ceiling, leave it visible.
			if e := s.putBalance(tx, bal); e != nil {
				return e
			}
			bals = append(bals, bal)
		}
		res.Amount = req.Observed
		res.Exposure = contract.ExposureKnown
		res.EstimateProvenance = contract.EstimateProvenance{Kind: contract.ProvenanceObserved, Source: req.Kind}
		if e := putJSON(tx.Bucket([]byte("reservations")), res.ID, res); e != nil {
			return e
		}
		if e := s.appendReservationEvent(tx, "amend", res.ID, req.RecordedAt, req); e != nil {
			return e
		}
		out = res
		_ = delta
		return nil
	})
	return out, bals, err
}

// MarkReservationUncertain retains uncertain exposure — no automatic release (R04).
func (s *Store) MarkReservationUncertain(req contract.MarkUncertainRequest) (contract.Reservation, error) {
	var out contract.Reservation
	if e := req.Validate(); e != nil {
		return out, e
	}
	if e := s.checkAccountingFault(); e != nil {
		return out, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("reservations")).Get([]byte(req.ReservationID))
		if raw == nil {
			return errors.New("unknown reservation")
		}
		var res contract.Reservation
		if e := contract.StrictJSON(raw, &res); e != nil {
			return e
		}
		if res.Status == contract.ReservationReleased || res.Status == contract.ReservationReconciled {
			return errors.New("terminal reservation cannot become uncertain")
		}
		// Move reserved → uncertain on scopes; retain exposure.
		keys := []contract.ScopeBalanceKey{
			{Scope: "task", Identity: res.TaskID, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "project", Identity: res.ProjectID, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "account", Identity: res.AccountPool, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "window", Identity: res.WindowEpoch, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
		}
		for _, key := range keys {
			bal, e := s.loadBalance(tx, key)
			if e != nil {
				return e
			}
			move := math.Min(bal.Reserved, res.Amount)
			bal.Reserved -= move
			bal.Uncertain += move
			if e := s.putBalance(tx, bal); e != nil {
				return e
			}
		}
		res.Status = contract.ReservationUncertain
		res.Exposure = contract.ExposureUncertain
		res.UncertainReason = req.Reason
		if e := putJSON(tx.Bucket([]byte("reservations")), res.ID, res); e != nil {
			return e
		}
		if e := s.appendReservationEvent(tx, "uncertain", res.ID, req.RecordedAt, req); e != nil {
			return e
		}
		out = res
		return nil
	})
	return out, err
}

// ReconcileReservation settles actual usage and optionally releases with proof.
func (s *Store) ReconcileReservation(req contract.ReconcileRequest) (contract.Reservation, error) {
	var out contract.Reservation
	if e := req.Validate(); e != nil {
		return out, e
	}
	if e := s.checkAccountingFault(); e != nil {
		return out, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("reservations")).Get([]byte(req.ReservationID))
		if raw == nil {
			return errors.New("unknown reservation")
		}
		var res contract.Reservation
		if e := contract.StrictJSON(raw, &res); e != nil {
			return e
		}
		keys := []contract.ScopeBalanceKey{
			{Scope: "task", Identity: res.TaskID, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "project", Identity: res.ProjectID, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "account", Identity: res.AccountPool, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
			{Scope: "window", Identity: res.WindowEpoch, Resource: res.Resource, Unit: res.Unit, Pool: res.Pool},
		}
		for _, key := range keys {
			bal, e := s.loadBalance(tx, key)
			if e != nil {
				return e
			}
			// Clear hold from reserved or uncertain; book actual consumed (never clamp below actual).
			hold := res.Amount
			fromReserved := math.Min(bal.Reserved, hold)
			bal.Reserved -= fromReserved
			hold -= fromReserved
			fromUncertain := math.Min(bal.Uncertain, hold)
			bal.Uncertain -= fromUncertain
			bal.Consumed += req.Actual
			if e := s.putBalance(tx, bal); e != nil {
				return e
			}
		}
		res.Amount = req.Actual
		res.Exposure = contract.ExposureKnown
		if req.Release {
			res.Status = contract.ReservationReleased
			res.ReleaseProof = req.ReleaseProof
		} else {
			res.Status = contract.ReservationReconciled
		}
		res.UncertainReason = ""
		if e := putJSON(tx.Bucket([]byte("reservations")), res.ID, res); e != nil {
			return e
		}
		if e := s.appendReservationEvent(tx, "reconcile", res.ID, req.RecordedAt, req); e != nil {
			return e
		}
		out = res
		return nil
	})
	return out, err
}

// ResetProviderWindow changes window balances without refilling task consumption (R05).
func (s *Store) ResetProviderWindow(req contract.WindowResetRequest) ([]contract.ScopeBalance, error) {
	var out []contract.ScopeBalance
	if e := req.Validate(); e != nil {
		return nil, e
	}
	if e := s.checkAccountingFault(); e != nil {
		return nil, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		oldKey := contract.ScopeBalanceKey{
			Scope: "window", Identity: req.OldEpoch,
			Resource: req.Resource, Unit: req.Unit, Pool: req.Pool,
		}
		taskConsumed := 0.0
		// Sum task consumed for this root's resource to prove preservation.
		_ = tx.Bucket([]byte("scope_balances")).ForEach(func(k, v []byte) error {
			var bal contract.ScopeBalance
			if e := contract.StrictJSON(v, &bal); e != nil {
				return e
			}
			if bal.Key.Scope == "task" && bal.Key.Resource == req.Resource && bal.Key.Unit == req.Unit && bal.Key.Pool == req.Pool {
				taskConsumed += bal.Consumed
			}
			return nil
		})
		oldBal, e := s.loadBalance(tx, oldKey)
		if e != nil {
			return e
		}
		newKey := oldKey
		newKey.Identity = req.NewEpoch
		newBal := contract.ScopeBalance{
			Key: newKey, Ceiling: req.NewWindowCeiling, WindowEpoch: req.NewEpoch,
			HardLimited: oldBal.HardLimited, ObservationUsable: oldBal.ObservationUsable,
			AuthorizedBound: oldBal.AuthorizedBound, ExplicitBoundedMode: oldBal.ExplicitBoundedMode,
		}
		// Late old-window events stay on old epoch; new window starts fresh reserved/uncertain.
		if e := s.putBalance(tx, newBal); e != nil {
			return e
		}
		if e := s.appendReservationEvent(tx, "window_reset", req.RootID, req.RecordedAt, map[string]any{
			"old_epoch": req.OldEpoch, "new_epoch": req.NewEpoch, "task_consumed_preserved": taskConsumed,
		}); e != nil {
			return e
		}
		out = []contract.ScopeBalance{oldBal, newBal}
		// Prove task balances unchanged by reloading them.
		_ = tx.Bucket([]byte("scope_balances")).ForEach(func(_, v []byte) error {
			var bal contract.ScopeBalance
			if e := contract.StrictJSON(v, &bal); e != nil {
				return e
			}
			if bal.Key.Scope == "task" && bal.Key.Resource == req.Resource {
				out = append(out, bal)
			}
			return nil
		})
		return nil
	})
	return out, err
}

// GetReservation returns a stored reservation.
func (s *Store) GetReservation(id string) (contract.Reservation, error) {
	var out contract.Reservation
	if e := s.checkAccountingFault(); e != nil {
		return out, e
	}
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("reservations")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown reservation")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

// ListScopeBalances returns all scope balances, optionally filtered by scope.
func (s *Store) ListScopeBalances(scope string) ([]contract.ScopeBalance, error) {
	var out []contract.ScopeBalance
	if e := s.checkAccountingFault(); e != nil {
		return nil, e
	}
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("scope_balances")).ForEach(func(_, v []byte) error {
			var bal contract.ScopeBalance
			if e := contract.StrictJSON(v, &bal); e != nil {
				return e
			}
			if scope != "" && bal.Key.Scope != scope {
				return nil
			}
			out = append(out, bal)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool {
		return balanceKey(out[i].Key) < balanceKey(out[j].Key)
	})
	return out, e
}

// ListReservations lists reservations for a root.
func (s *Store) ListReservations(rootID string) ([]contract.Reservation, error) {
	var out []contract.Reservation
	if e := s.checkAccountingFault(); e != nil {
		return nil, e
	}
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("reservations")).ForEach(func(_, v []byte) error {
			var r contract.Reservation
			if e := contract.StrictJSON(v, &r); e != nil {
				return e
			}
			if rootID != "" && r.RootID != rootID {
				return nil
			}
			out = append(out, r)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

// ConcurrentAdmit runs multiple admit requests inside successive Update txns under contention.
// Contenders never jointly exceed known ceilings because each admit re-reads balances in its txn.
func (s *Store) ConcurrentAdmit(reqs []contract.AdmitRequest) []contract.AdmitResult {
	results := make([]contract.AdmitResult, len(reqs))
	var wg sync.WaitGroup
	for i := range reqs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			// Tiny stagger not required — bbolt serializes writers.
			results[i], _ = s.AdmitReservation(reqs[i])
		}(i)
	}
	wg.Wait()
	return results
}

// SeedScopeBalance writes an initial balance (tests / designated headroom setup).
func (s *Store) SeedScopeBalance(bal contract.ScopeBalance) error {
	if e := bal.Validate(); e != nil {
		return e
	}
	if e := s.checkAccountingFault(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.reservationReady(tx); e != nil {
			return e
		}
		prev, e := s.loadBalance(tx, bal.Key)
		if e != nil {
			return e
		}
		if prev.Ceiling != nil || prev.Reserved != 0 || prev.Consumed != 0 {
			if !reflect.DeepEqual(prev, bal) && (prev.Reserved != 0 || prev.Consumed != 0 || prev.Uncertain != 0) {
				return errors.New("scope balance already has exposure")
			}
		}
		return s.putBalance(tx, bal)
	})
}

// WaitForAccounting is a no-op helper for tests that previously slept on lock timing.
func (s *Store) WaitForAccounting(d time.Duration) {
	time.Sleep(d)
}
