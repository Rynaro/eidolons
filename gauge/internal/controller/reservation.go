package controller

import (
	"errors"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureReservationStore() (*store.Store, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureObservationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureInstrumentNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureReservationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureReservationNamespaces adds typed reservation buckets under schema 2.
func (s *Service) EnsureReservationNamespaces() error {
	db, e := s.ensureReservationStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// AdmitReservation performs local atomic admission under append lock + active checks.
// No provider/network call occurs inside the store transaction.
func (s *Service) AdmitReservation(rootID string, req contract.AdmitRequest) (contract.AdmitResult, error) {
	var result contract.AdmitResult
	req.RootID = rootID
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	if e := req.Validate(); e != nil {
		result.RejectReasons = append(result.RejectReasons, e.Error())
		return result, nil
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		result.RejectReasons = append(result.RejectReasons, "append_lock_unavailable")
		result.AccountingOK = false
		return result, nil
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		result.RejectReasons = append(result.RejectReasons, "active_claim_or_inventory_failed")
		result.AccountingOK = false
		return result, nil
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		result.RejectReasons = append(result.RejectReasons, "authoritative accounting unavailable: "+e.Error())
		result.AccountingOK = false
		return result, nil
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		result.RejectReasons = append(result.RejectReasons, e.Error())
		result.AccountingOK = false
		return result, nil
	}
	return db.AdmitReservation(req)
}

// AmendReservation records overrun/late usage/correction without clamping exposure.
func (s *Service) AmendReservation(rootID string, req contract.AmendRequest) (contract.Reservation, []contract.ScopeBalance, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.Reservation{}, nil, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.Reservation{}, nil, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.Reservation{}, nil, e
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		return contract.Reservation{}, nil, e
	}
	res, bals, e := db.AmendReservation(req)
	if e != nil {
		return res, bals, e
	}
	if res.RootID != rootID {
		return res, bals, errors.New("reservation root mismatch")
	}
	return res, bals, nil
}

// MarkReservationUncertain retains uncertain exposure (no automatic release).
func (s *Service) MarkReservationUncertain(rootID string, req contract.MarkUncertainRequest) (contract.Reservation, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.Reservation{}, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.Reservation{}, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.Reservation{}, e
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		return contract.Reservation{}, e
	}
	res, e := db.MarkReservationUncertain(req)
	if e != nil {
		return res, e
	}
	if res.RootID != rootID {
		return res, errors.New("reservation root mismatch")
	}
	return res, nil
}

// ReconcileReservation settles exposure; release requires explicit proof.
func (s *Service) ReconcileReservation(rootID string, req contract.ReconcileRequest) (contract.Reservation, error) {
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return contract.Reservation{}, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return contract.Reservation{}, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return contract.Reservation{}, e
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		return contract.Reservation{}, e
	}
	res, e := db.ReconcileReservation(req)
	if e != nil {
		return res, e
	}
	if res.RootID != rootID {
		return res, errors.New("reservation root mismatch")
	}
	return res, nil
}

// ResetProviderWindow updates provider window balances without refilling task budget.
func (s *Service) ResetProviderWindow(rootID string, req contract.WindowResetRequest) ([]contract.ScopeBalance, error) {
	req.RootID = rootID
	if req.RecordedAt == "" {
		req.RecordedAt = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	release, e := s.lock(rootID, false)
	if e != nil {
		return nil, e
	}
	defer release()
	if _, _, e = s.active(rootID); e != nil {
		return nil, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return nil, e
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		return nil, e
	}
	return db.ResetProviderWindow(req)
}

// ReservationStatus returns reservations and balances for a root.
func (s *Service) ReservationStatus(rootID string) ([]contract.Reservation, []contract.ScopeBalance, error) {
	if _, _, e := s.active(rootID); e != nil {
		return nil, nil, e
	}
	db, e := store.Open(s.storePath(), s.opts.Timeout)
	if e != nil {
		return nil, nil, e
	}
	defer db.Close()
	if e = db.EnsureReservationNamespaces(); e != nil {
		return nil, nil, e
	}
	res, e := db.ListReservations(rootID)
	if e != nil {
		return nil, nil, e
	}
	bals, e := db.ListScopeBalances("")
	return res, bals, e
}

// ReservationStoreForTest opens the reservation-ready store for fixture fault injection.
func (s *Service) ReservationStoreForTest() (*store.Store, error) {
	return s.ensureReservationStore()
}
