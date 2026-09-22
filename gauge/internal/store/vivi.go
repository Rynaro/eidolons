package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var viviBuckets = []string{
	"vivi_sessions", "vivi_modes", "vivi_edits", "vivi_proposals",
	"vivi_applications", "vivi_continuity", "vivi_verifications",
	"vivi_boundaries", "vivi_context_strategies", "vivi_events",
}

type viviReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeVivi(tx *bolt.Tx, id, kind string) error {
	for _, name := range viviBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "vivi_receipt", viviReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.ViviSchemaVersion,
	})
}

func guardVivi(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("vivi_receipt"))
	missing := 0
	for _, name := range viviBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(viviBuckets) {
		// Pre-V4-17 schema 2 stores remain openable; vivi APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete vivi namespaces; call vivi-enable")
	}
	var receipt viviReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid vivi receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.ViviSchemaVersion {
		return errors.New("unsupported vivi receipt")
	}
	return nil
}

func (s *Store) viviReady(tx *bolt.Tx) error {
	for _, name := range viviBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("vivi namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("vivi_receipt")) == nil {
		return errors.New("vivi namespaces required")
	}
	return nil
}

// EnsureViviNamespaces adds typed Vivi mode buckets under schema 2 without a schema bump.
func (s *Store) EnsureViviNamespaces() error {
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
		if e := guardAcceptance(tx); e != nil {
			return e
		}
		if e := guardDelivery(tx); e != nil {
			return e
		}
		if e := guardEvaluation(tx); e != nil {
			return e
		}
		if e := guardStatus(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("vivi_receipt")); raw != nil {
			return guardVivi(tx)
		}
		if e := initializeVivi(tx, id, "ensure"); e != nil {
			return e
		}
		return guardVivi(tx)
	})
}

func (s *Store) appendViviEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "subject": subject, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, subject)
	return tx.Bucket([]byte("vivi_events")).Put([]byte(key), raw)
}

func (s *Store) PutViviSession(sess contract.ViviSession) error {
	if e := sess.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("vivi_sessions"))
		if prev := b.Get([]byte(sess.ID)); prev != nil {
			var existing contract.ViviSession
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, sess) {
				return errors.New("vivi session identity conflict")
			}
			return nil
		}
		if e := putJSON(b, sess.ID, sess); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_session", sess.ID, sess.RecordedAt, map[string]any{
			"root_budget_id": sess.RootBudgetID, "contract": sess.ContractVersion,
		})
	})
}

func (s *Store) GetViviSession(id string) (contract.ViviSession, error) {
	var out contract.ViviSession
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("vivi_sessions")).Get([]byte(id))
		if raw == nil {
			return errors.New("vivi session not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

func (s *Store) PutViviMode(m contract.ViviModeSelection) error {
	if e := m.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("vivi_sessions")).Get([]byte(m.SessionID)) == nil {
			return errors.New("vivi session required before mode selection")
		}
		b := tx.Bucket([]byte("vivi_modes"))
		if prev := b.Get([]byte(m.ID)); prev != nil {
			var existing contract.ViviModeSelection
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, m) {
				return errors.New("vivi mode identity conflict")
			}
			return nil
		}
		if e := putJSON(b, m.ID, m); e != nil {
			return e
		}
		// Bind active mode on session.
		raw := tx.Bucket([]byte("vivi_sessions")).Get([]byte(m.SessionID))
		var sess contract.ViviSession
		if e := contract.StrictJSON(raw, &sess); e != nil {
			return e
		}
		sess.ActiveModeID = m.ID
		if e := putJSON(tx.Bucket([]byte("vivi_sessions")), sess.ID, sess); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_mode", m.ID, m.RecordedAt, map[string]any{
			"mode": m.Mode, "session": m.SessionID,
		})
	})
}

func (s *Store) GetViviMode(id string) (contract.ViviModeSelection, error) {
	var out contract.ViviModeSelection
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("vivi_modes")).Get([]byte(id))
		if raw == nil {
			return errors.New("vivi mode not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

func (s *Store) PutViviEdit(a contract.ViviEditAttempt) error {
	if e := a.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("vivi_modes")).Get([]byte(a.ModeID)) == nil {
			return errors.New("vivi mode required before edit")
		}
		b := tx.Bucket([]byte("vivi_edits"))
		if prev := b.Get([]byte(a.ID)); prev != nil {
			var existing contract.ViviEditAttempt
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, a) {
				return errors.New("vivi edit identity conflict")
			}
			return nil
		}
		if e := putJSON(b, a.ID, a); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_edit", a.ID, a.RecordedAt, map[string]any{
			"outcome": a.Outcome, "applied_to_user": a.AppliedToUser,
		})
	})
}

func (s *Store) PutViviProposal(p contract.ViviProposal) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("vivi_modes")).Get([]byte(p.ModeID)) == nil {
			return errors.New("vivi mode required before proposal")
		}
		b := tx.Bucket([]byte("vivi_proposals"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.ViviProposal
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("vivi proposal identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_proposal", p.ID, p.RecordedAt, map[string]any{
			"diff_digest": p.DiffDigest, "applied": p.AppliedToUserTree,
		})
	})
}

func (s *Store) GetViviProposal(id string) (contract.ViviProposal, error) {
	var out contract.ViviProposal
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("vivi_proposals")).Get([]byte(id))
		if raw == nil {
			return errors.New("vivi proposal not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

func (s *Store) PutViviApplication(a contract.ViviProposalApplication) error {
	if e := a.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("vivi_proposals")).Get([]byte(a.ProposalID)) == nil {
			return errors.New("vivi proposal required before application")
		}
		b := tx.Bucket([]byte("vivi_applications"))
		if prev := b.Get([]byte(a.ID)); prev != nil {
			var existing contract.ViviProposalApplication
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, a) {
				return errors.New("vivi application identity conflict")
			}
			return nil
		}
		if e := putJSON(b, a.ID, a); e != nil {
			return e
		}
		// Link application op on proposal without mutating applied_to_user_tree on the proposal itself.
		raw := tx.Bucket([]byte("vivi_proposals")).Get([]byte(a.ProposalID))
		var prop contract.ViviProposal
		if e := contract.StrictJSON(raw, &prop); e != nil {
			return e
		}
		prop.ApplicationOpID = a.ID
		if e := putJSON(tx.Bucket([]byte("vivi_proposals")), prop.ID, prop); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_application", a.ID, a.RecordedAt, map[string]any{
			"proposal": a.ProposalID, "parent_authorized": a.ParentAuthorized, "applied": a.AppliedToUserTree,
		})
	})
}

func (s *Store) PutViviContinuity(c contract.ViviContinuityState) error {
	if e := c.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("vivi_sessions")).Get([]byte(c.SessionID)) == nil {
			return errors.New("vivi session required before continuity")
		}
		b := tx.Bucket([]byte("vivi_continuity"))
		if e := putJSON(b, c.ID, c); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("vivi_sessions")).Get([]byte(c.SessionID))
		var sess contract.ViviSession
		if e := contract.StrictJSON(raw, &sess); e != nil {
			return e
		}
		sess.ContinuityID = c.ID
		if e := putJSON(tx.Bucket([]byte("vivi_sessions")), sess.ID, sess); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_continuity", c.ID, c.RecordedAt, map[string]any{
			"repairs": c.RepairAttempts, "resets": c.ContextResets, "accounting": c.AccountingPreserved,
		})
	})
}

func (s *Store) GetViviContinuity(id string) (contract.ViviContinuityState, error) {
	var out contract.ViviContinuityState
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("vivi_continuity")).Get([]byte(id))
		if raw == nil {
			return errors.New("vivi continuity not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}

func (s *Store) PutViviVerification(v contract.ViviVerificationSubmission) error {
	if e := v.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("vivi_verifications"))
		if prev := b.Get([]byte(v.ID)); prev != nil {
			var existing contract.ViviVerificationSubmission
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, v) {
				return errors.New("vivi verification identity conflict")
			}
			return nil
		}
		if e := putJSON(b, v.ID, v); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_verification", v.ID, v.RecordedAt, map[string]any{
			"grade": v.EvidenceGrade, "observed": v.ObservedEvidenceGrade, "rejected": v.Rejected,
		})
	})
}

func (s *Store) PutViviBoundary(b contract.ViviBoundaryRefusal) error {
	if e := b.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		bucket := tx.Bucket([]byte("vivi_boundaries"))
		if prev := bucket.Get([]byte(b.ID)); prev != nil {
			var existing contract.ViviBoundaryRefusal
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, b) {
				return errors.New("vivi boundary identity conflict")
			}
			return nil
		}
		if e := putJSON(bucket, b.ID, b); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_boundary", b.ID, b.RecordedAt, map[string]any{
			"boundary": b.Boundary, "refused": b.Refused,
		})
	})
}

func (s *Store) PutViviContextStrategy(c contract.ViviContextStrategyRecord) error {
	if e := c.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("vivi_context_strategies"))
		if prev := b.Get([]byte(c.ID)); prev != nil {
			var existing contract.ViviContextStrategyRecord
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, c) {
				return errors.New("vivi context strategy identity conflict")
			}
			return nil
		}
		if e := putJSON(b, c.ID, c); e != nil {
			return e
		}
		return s.appendViviEvent(tx, "vivi_context_strategy", c.ID, c.RecordedAt, map[string]any{
			"strategy": c.Strategy, "version": c.StrategyVersion, "transition": c.TransitionBoundary,
		})
	})
}

func (s *Store) GetViviContextStrategy(id string) (contract.ViviContextStrategyRecord, error) {
	var out contract.ViviContextStrategyRecord
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.viviReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("vivi_context_strategies")).Get([]byte(id))
		if raw == nil {
			return errors.New("vivi context strategy not found")
		}
		return contract.StrictJSON(raw, &out)
	})
	return out, e
}
