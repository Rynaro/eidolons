package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

// Ramza namespaces hold versioned lite/full/legacy method contracts and fixtures.
// They do not archive or relocate Rynaro/Ramza; producer artifacts may be fixture-simulated.
var ramzaBuckets = []string{
	"ramza_plans", "ramza_heuristics", "ramza_assumptions",
	"ramza_profiles", "ramza_consume_receipts", "ramza_events",
}

type ramzaReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeRamza(tx *bolt.Tx, id, kind string) error {
	for _, name := range ramzaBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "ramza_receipt", ramzaReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.RamzaSchemaVersion,
	})
}

func guardRamza(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("ramza_receipt"))
	missing := 0
	for _, name := range ramzaBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(ramzaBuckets) {
		// Pre-V4-16 schema 2 stores remain openable; ramza APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete ramza namespaces; call ramza-enable")
	}
	var receipt ramzaReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid ramza receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.RamzaSchemaVersion {
		return errors.New("unsupported ramza receipt")
	}
	return nil
}

func (s *Store) ramzaReady(tx *bolt.Tx) error {
	for _, name := range ramzaBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("ramza namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("ramza_receipt")) == nil {
		return errors.New("ramza namespaces required")
	}
	return nil
}

// EnsureRamzaNamespaces adds typed RAMZA method-contract buckets under schema 2.
func (s *Store) EnsureRamzaNamespaces() error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := guardBase(tx, "2"); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("ramza_receipt")); raw != nil {
			return guardRamza(tx)
		}
		if e := initializeRamza(tx, id, "ensure"); e != nil {
			return e
		}
		return guardRamza(tx)
	})
}

func (s *Store) appendRamzaEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	b := tx.Bucket([]byte("ramza_events"))
	if b == nil {
		return errors.New("ramza namespaces required")
	}
	seq, _ := b.NextSequence()
	payload := map[string]any{
		"seq": seq, "kind": kind, "subject": subject, "at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%020d/%s/%s", seq, kind, subject)
	return b.Put([]byte(key), raw)
}

func (s *Store) PutRamzaPlan(p contract.RamzaLitePlan) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("ramza_plans"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.RamzaLitePlan
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("ramza plan identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendRamzaEvent(tx, "plan", p.ID, p.RecordedAt, map[string]any{
			"method_version": p.MethodVersion,
			"ready":          p.ReadyForImplementation,
			"producer":       p.ProducerArtifactSource,
		})
	})
}

func (s *Store) UpdateRamzaPlan(p contract.RamzaLitePlan) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("ramza_plans"))
		if b.Get([]byte(p.ID)) == nil {
			return errors.New("unknown ramza plan")
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendRamzaEvent(tx, "plan_update", p.ID, p.RecordedAt, map[string]any{
			"ready": p.ReadyForImplementation,
		})
	})
}

func (s *Store) GetRamzaPlan(id string) (contract.RamzaLitePlan, error) {
	var p contract.RamzaLitePlan
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("ramza_plans")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown ramza plan")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutRamzaHeuristic(h contract.HeuristicPublication) error {
	if e := h.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("ramza_heuristics"))
		if prev := b.Get([]byte(h.ID)); prev != nil {
			var existing contract.HeuristicPublication
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, h) {
				return errors.New("ramza heuristic identity conflict")
			}
			return nil
		}
		if e := putJSON(b, h.ID, h); e != nil {
			return e
		}
		return s.appendRamzaEvent(tx, "heuristic", h.ID, h.RecordedAt, map[string]any{
			"state": h.State, "activated": h.Activated,
		})
	})
}

func (s *Store) GetRamzaHeuristic(id string) (contract.HeuristicPublication, error) {
	var h contract.HeuristicPublication
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("ramza_heuristics")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown ramza heuristic")
		}
		return contract.StrictJSON(raw, &h)
	})
	return h, e
}

func (s *Store) PutRamzaAssumption(a contract.PlanningAssumption) error {
	if e := a.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("ramza_assumptions"))
		if prev := b.Get([]byte(a.ID)); prev != nil {
			var existing contract.PlanningAssumption
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, a) {
				return errors.New("ramza assumption identity conflict")
			}
			return nil
		}
		if e := putJSON(b, a.ID, a); e != nil {
			return e
		}
		return s.appendRamzaEvent(tx, "assumption", a.ID, a.RecordedAt, map[string]any{
			"status": a.Status, "affects_acceptance": a.AffectsAcceptance,
		})
	})
}

func (s *Store) PutRamzaProfile(p contract.ProfilePackage) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("ramza_profiles"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.ProfilePackage
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("ramza profile identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendRamzaEvent(tx, "profile", p.ID, p.RecordedAt, map[string]any{
			"mode": p.Mode, "method_version": p.MethodVersion,
		})
	})
}

func (s *Store) GetRamzaProfile(id string) (contract.ProfilePackage, error) {
	var p contract.ProfilePackage
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("ramza_profiles")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown ramza profile")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutRamzaConsumeReceipt(id string, r contract.ConsumeDecisionResult) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.ramzaReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("ramza_consume_receipts"))
		if e := putJSON(b, id, r); e != nil {
			return e
		}
		return s.appendRamzaEvent(tx, "consume", id, "", map[string]any{
			"plan_id": r.PlanID, "reopened": r.Decision.Reopened,
			"duplicate_search": r.DuplicateSearchRequired,
		})
	})
}
