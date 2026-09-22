package store

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var acceptanceBuckets = []string{
	"frozen_candidates", "acceptance_packages", "check_receipts",
	"oracle_qualifications", "owner_reviews", "definition_blockers", "protected_paths",
}

type acceptanceReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeAcceptance(tx *bolt.Tx, id, kind string) error {
	for _, name := range acceptanceBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "acceptance_receipt", acceptanceReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.AcceptanceSchemaVersion,
	})
}

func guardAcceptance(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("acceptance_receipt"))
	missing := 0
	for _, name := range acceptanceBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(acceptanceBuckets) {
		// Pre-V4-14 schema 2 stores remain openable; acceptance APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete acceptance namespaces; call acceptance-enable")
	}
	var receipt acceptanceReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid acceptance receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.AcceptanceSchemaVersion {
		return errors.New("unsupported acceptance receipt")
	}
	return nil
}

func (s *Store) acceptanceReady(tx *bolt.Tx) error {
	for _, name := range acceptanceBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("acceptance namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("acceptance_receipt")) == nil {
		return errors.New("acceptance namespaces required")
	}
	return nil
}

// EnsureAcceptanceNamespaces adds typed acceptance buckets under schema 2 without a schema bump.
func (s *Store) EnsureAcceptanceNamespaces() error {
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
		if e := guardReservation(tx); e != nil {
			return e
		}
		if e := guardDispatch(tx); e != nil {
			return e
		}
		if e := guardCompiler(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("acceptance_receipt")); raw != nil {
			return guardAcceptance(tx)
		}
		if e := initializeAcceptance(tx, id, "ensure"); e != nil {
			return e
		}
		return guardAcceptance(tx)
	})
}

func (s *Store) appendAcceptanceEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "subject": subject, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, subject)
	b := tx.Bucket([]byte("protected_paths"))
	if b.Get([]byte(key)) != nil {
		key = key + "/" + contract.Digest(raw)[:12]
	}
	return b.Put([]byte(key), raw)
}

// PersistFrozenCandidate stores an immutable freeze manifest.
func (s *Store) PersistFrozenCandidate(c contract.FrozenCandidate) (contract.FrozenCandidate, error) {
	if e := c.Validate(); e != nil {
		return c, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(c.RootID)) == nil {
			return errors.New("unknown root")
		}
		if existing := tx.Bucket([]byte("frozen_candidates")).Get([]byte(c.ID)); existing != nil {
			var prev contract.FrozenCandidate
			if e := contract.StrictJSON(existing, &prev); e != nil {
				return e
			}
			rawNew, _ := json.Marshal(c)
			rawOld, _ := json.Marshal(prev)
			if string(rawNew) != string(rawOld) {
				return errors.New("frozen candidate identity conflict")
			}
			c = prev
			return nil
		}
		if e := putJSON(tx.Bucket([]byte("frozen_candidates")), c.ID, c); e != nil {
			return e
		}
		return s.appendAcceptanceEvent(tx, "freeze", c.ID, c.FrozenAt, map[string]string{
			"content_digest": c.ContentDigest, "acceptance_id": c.AcceptanceID, "environment_id": c.EnvironmentID,
		})
	})
	return c, err
}

// GetFrozenCandidate loads a freeze by ID.
func (s *Store) GetFrozenCandidate(id string) (contract.FrozenCandidate, error) {
	var c contract.FrozenCandidate
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("frozen_candidates")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown frozen candidate")
		}
		return contract.StrictJSON(raw, &c)
	})
	return c, e
}

// PersistAcceptancePackage stores or updates an acceptance package definition.
func (s *Store) PersistAcceptancePackage(p contract.AcceptancePackage) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		return putJSON(tx.Bucket([]byte("acceptance_packages")), p.ID, p)
	})
}

// GetAcceptancePackage loads an acceptance package.
func (s *Store) GetAcceptancePackage(id string) (contract.AcceptancePackage, error) {
	var p contract.AcceptancePackage
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("acceptance_packages")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown acceptance package")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

// PersistCheckReceipt records an observed check finish.
func (s *Store) PersistCheckReceipt(r contract.CheckReceipt) (contract.CheckReceipt, error) {
	if e := r.Validate(); e != nil {
		return r, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		if existing := tx.Bucket([]byte("check_receipts")).Get([]byte(r.ID)); existing != nil {
			var prev contract.CheckReceipt
			if e := contract.StrictJSON(existing, &prev); e != nil {
				return e
			}
			rawNew, _ := json.Marshal(r)
			rawOld, _ := json.Marshal(prev)
			if string(rawNew) != string(rawOld) {
				return errors.New("check receipt identity conflict")
			}
			r = prev
			return nil
		}
		if e := putJSON(tx.Bucket([]byte("check_receipts")), r.ID, r); e != nil {
			return e
		}
		return s.appendAcceptanceEvent(tx, "check", r.ID, r.Provenance.ObservedAt, map[string]string{
			"outcome": r.Outcome, "candidate_id": r.Provenance.CandidateID, "integrity": r.IntegrityGrade,
		})
	})
	return r, err
}

// ListCheckReceipts returns all check receipts (fixture-local).
func (s *Store) ListCheckReceipts() ([]contract.CheckReceipt, error) {
	var out []contract.CheckReceipt
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("check_receipts")).ForEach(func(_, v []byte) error {
			var r contract.CheckReceipt
			if e := contract.StrictJSON(v, &r); e != nil {
				return e
			}
			out = append(out, r)
			return nil
		})
	})
	return out, e
}

// PersistOracleQualification stores qualification evidence.
func (s *Store) PersistOracleQualification(q contract.OracleQualification) error {
	if e := q.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("oracle_qualifications")), q.ID, q); e != nil {
			return e
		}
		return s.appendAcceptanceEvent(tx, "qualify", q.ID, q.RecordedAt, map[string]any{
			"qualified": q.Qualified, "acceptance_id": q.AcceptanceID,
		})
	})
}

// PersistOwnerReview stores an acceptance-owner review record.
func (s *Store) PersistOwnerReview(r contract.AcceptanceOwnerReview) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("owner_reviews")), r.ID, r); e != nil {
			return e
		}
		return s.appendAcceptanceEvent(tx, "owner_review", r.ID, r.RecordedAt, map[string]any{
			"owner_approved": r.OwnerApproved, "invalidates": r.InvalidatesOld,
		})
	})
}

// PersistDefinitionBlocker records an acceptance-definition blocker.
func (s *Store) PersistDefinitionBlocker(b contract.DefinitionBlocker) error {
	if e := b.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		return putJSON(tx.Bucket([]byte("definition_blockers")), b.ID, b)
	})
}

// GetDefinitionBlocker loads a blocker by ID.
func (s *Store) GetDefinitionBlocker(id string) (contract.DefinitionBlocker, error) {
	var b contract.DefinitionBlocker
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("definition_blockers")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown definition blocker")
		}
		return contract.StrictJSON(raw, &b)
	})
	return b, e
}

// RecordProtectedPaths stores the protected path set for an isolation session.
func (s *Store) RecordProtectedPaths(sessionID string, paths []string) error {
	if e := validateStoreKey(sessionID); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		return putJSON(tx.Bucket([]byte("protected_paths")), "session/"+sessionID, map[string]any{
			"paths": paths,
		})
	})
}

func validateStoreKey(id string) error {
	if id == "" {
		return errors.New("missing session identity")
	}
	return nil
}

// ListFrozenCandidates returns all frozen candidates for a root (empty root = all).
func (s *Store) ListFrozenCandidates(rootID string) ([]contract.FrozenCandidate, error) {
	var out []contract.FrozenCandidate
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.acceptanceReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("frozen_candidates")).ForEach(func(_, v []byte) error {
			var c contract.FrozenCandidate
			if e := contract.StrictJSON(v, &c); e != nil {
				return e
			}
			if rootID == "" || c.RootID == rootID {
				out = append(out, c)
			}
			return nil
		})
	})
	return out, e
}
