package store

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

// Status namespaces hold observational client-conformance and preview receipts only.
// They never host a duplicated budget engine or authority grants.
var statusBuckets = []string{
	"status_projections", "status_client_receipts", "status_events",
}

type statusReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeStatus(tx *bolt.Tx, id, kind string) error {
	for _, name := range statusBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "status_receipt", statusReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.StatusSchemaVersion,
	})
}

func guardStatus(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("status_receipt"))
	missing := 0
	for _, name := range statusBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(statusBuckets) {
		// Pre-V4-20 schema 2 stores remain openable; status APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete status namespaces; call status-enable")
	}
	var receipt statusReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid status receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.StatusSchemaVersion {
		return errors.New("unsupported status receipt")
	}
	return nil
}

func (s *Store) statusReady(tx *bolt.Tx) error {
	for _, name := range statusBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("status namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("status_receipt")) == nil {
		return errors.New("status namespaces required")
	}
	return nil
}

// EnsureStatusNamespaces adds typed status-projection buckets under schema 2 without a schema bump.
func (s *Store) EnsureStatusNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("status_receipt")); raw != nil {
			return guardStatus(tx)
		}
		if e := initializeStatus(tx, id, "ensure"); e != nil {
			return e
		}
		return guardStatus(tx)
	})
}

func (s *Store) appendStatusEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	b := tx.Bucket([]byte("status_events"))
	if b == nil {
		return errors.New("status namespaces required")
	}
	seq, _ := b.NextSequence()
	payload := map[string]any{
		"seq": seq, "kind": kind, "subject": subject, "at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	return b.Put([]byte(fmt.Sprintf("%020d", seq)), raw)
}

// PersistStatusProjection stores an observational snapshot (never authority).
func (s *Store) PersistStatusProjection(p contract.StatusProjection) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.statusReady(tx); e != nil {
			return e
		}
		key := p.LoopID
		if key == "" {
			key = p.RootID
		}
		if key == "" {
			return errors.New("status projection requires loop_id or root_id")
		}
		if e := putJSON(tx.Bucket([]byte("status_projections")), key, p); e != nil {
			return e
		}
		return s.appendStatusEvent(tx, "status_projected", key, "", map[string]any{
			"delivery_state":     p.DeliveryState,
			"verification_state": p.VerificationState,
			"model_calls":        p.ModelCalls,
		})
	})
}

// GetStatusProjection loads a previously persisted observational snapshot.
func (s *Store) GetStatusProjection(key string) (contract.StatusProjection, error) {
	var out contract.StatusProjection
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.statusReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("status_projections")).Get([]byte(key))
		if raw == nil {
			return errors.New("status projection not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

// PersistClientConformance records fixture-consumer conformance (GAMBIT out of scope).
func (s *Store) PersistClientConformance(id string, r contract.ClientConformanceResult) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.statusReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("status_client_receipts")), id, r); e != nil {
			return e
		}
		return s.appendStatusEvent(tx, "client_conformance", id, "", map[string]any{
			"supported": r.Supported, "error": r.Error, "optional_gambit": r.OptionalGAMBIT,
		})
	})
}

// ListOutstandingReservationIDs returns reservation IDs still open for a root (for preview preservation).
func (s *Store) ListOutstandingReservationIDs(rootID string) ([]string, error) {
	res, e := s.ListReservations(rootID)
	if e != nil {
		return nil, e
	}
	var out []string
	for _, r := range res {
		switch r.Status {
		case contract.ReservationAdmitted, contract.ReservationUncertain:
			out = append(out, r.ID)
		}
	}
	return out, nil
}
