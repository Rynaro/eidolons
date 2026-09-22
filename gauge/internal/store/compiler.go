package store

import (
	"encoding/json"
	"errors"
	"fmt"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var compilerBuckets = []string{
	"compiled_plans", "method_bindings", "assignment_splits", "consultant_receipts",
}

type compilerReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeCompiler(tx *bolt.Tx, id, kind string) error {
	for _, name := range compilerBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "compiler_receipt", compilerReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.CompilerSchemaVersion,
	})
}

func guardCompiler(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("compiler_receipt"))
	missing := 0
	for _, name := range compilerBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(compilerBuckets) {
		// Pre-V4-13 schema 2 stores remain openable; compiler APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete compiler namespaces; call compiler-enable")
	}
	var receipt compilerReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid compiler receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.CompilerSchemaVersion {
		return errors.New("unsupported compiler receipt")
	}
	return nil
}

func (s *Store) compilerReady(tx *bolt.Tx) error {
	for _, name := range compilerBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("compiler namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("compiler_receipt")) == nil {
		return errors.New("compiler namespaces required")
	}
	return nil
}

// EnsureCompilerNamespaces adds typed compiler buckets under schema 2 without a schema bump.
func (s *Store) EnsureCompilerNamespaces() error {
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
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("compiler_receipt")); raw != nil {
			return guardCompiler(tx)
		}
		if e := initializeCompiler(tx, id, "ensure"); e != nil {
			return e
		}
		return guardCompiler(tx)
	})
}

func (s *Store) appendCompilerEvent(tx *bolt.Tx, kind, planID, at string, detail any) error {
	// Events ride assignment_splits as an append-only journal keyed by time+kind.
	payload := map[string]any{
		"kind": kind, "plan_id": planID, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, planID)
	b := tx.Bucket([]byte("assignment_splits"))
	if b.Get([]byte(key)) != nil {
		key = key + "/" + contract.Digest(raw)[:12]
	}
	return b.Put([]byte(key), raw)
}

// PersistCompiledPlan durably records a compiled assignment plan.
func (s *Store) PersistCompiledPlan(plan contract.CompiledPlan) (contract.CompiledPlan, error) {
	if e := plan.Validate(); e != nil {
		return plan, e
	}
	err := s.db.Update(func(tx *bolt.Tx) error {
		if e := s.compilerReady(tx); e != nil {
			return e
		}
		if tx.Bucket([]byte("roots")).Get([]byte(plan.RootID)) == nil {
			return errors.New("unknown root")
		}
		if existing := tx.Bucket([]byte("compiled_plans")).Get([]byte(plan.ID)); existing != nil {
			var prev contract.CompiledPlan
			if e := contract.StrictJSON(existing, &prev); e != nil {
				return e
			}
			rawNew, _ := json.Marshal(plan)
			rawOld, _ := json.Marshal(prev)
			if string(rawNew) != string(rawOld) {
				return errors.New("compiled plan identity conflict")
			}
			plan = prev
			return nil
		}
		if e := putJSON(tx.Bucket([]byte("compiled_plans")), plan.ID, plan); e != nil {
			return e
		}
		for _, a := range plan.Assignments {
			for _, m := range a.Methods {
				key := plan.ID + "/" + m.ID
				if e := putJSON(tx.Bucket([]byte("method_bindings")), key, m); e != nil {
					return e
				}
			}
		}
		for _, w := range plan.WorkerStarts {
			key := plan.ID + "/" + w.AssignmentID
			if e := putJSON(tx.Bucket([]byte("assignment_splits")), key, w); e != nil {
				return e
			}
		}
		return s.appendCompilerEvent(tx, "plan_persisted", plan.ID, plan.CompiledAt, map[string]any{
			"assignments": len(plan.Assignments),
			"forced_fan_out": plan.ForcedFanOut,
			"status": plan.Status,
		})
	})
	return plan, err
}

// LoadCompiledPlan reads a persisted plan.
func (s *Store) LoadCompiledPlan(id string) (contract.CompiledPlan, error) {
	var plan contract.CompiledPlan
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.compilerReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("compiled_plans")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown compiled plan")
		}
		return contract.StrictJSON(raw, &plan)
	})
	return plan, err
}

// ListCompiledPlans returns plans for a root.
func (s *Store) ListCompiledPlans(rootID string) ([]contract.CompiledPlan, error) {
	var out []contract.CompiledPlan
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.compilerReady(tx); e != nil {
			return e
		}
		return tx.Bucket([]byte("compiled_plans")).ForEach(func(_, v []byte) error {
			var p contract.CompiledPlan
			if e := contract.StrictJSON(v, &p); e != nil {
				return e
			}
			if p.RootID == rootID {
				out = append(out, p)
			}
			return nil
		})
	})
	return out, err
}

// PersistConsultantReceipt records a consultant validation decision.
func (s *Store) PersistConsultantReceipt(v contract.ConsultantValidation, at string) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.compilerReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("consultant_receipts")), v.ResultID, v); e != nil {
			return e
		}
		return s.appendCompilerEvent(tx, "consultant_validated", v.ResultID, at, v)
	})
}

// LoadConsultantReceipt loads a prior consultant validation.
func (s *Store) LoadConsultantReceipt(resultID string) (contract.ConsultantValidation, error) {
	var v contract.ConsultantValidation
	err := s.db.View(func(tx *bolt.Tx) error {
		if e := s.compilerReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("consultant_receipts")).Get([]byte(resultID))
		if raw == nil {
			return errors.New("unknown consultant receipt")
		}
		return contract.StrictJSON(raw, &v)
	})
	return v, err
}

// PersistEvidenceClass records an evidence classification.
func (s *Store) PersistEvidenceClass(ev contract.EvidenceClass, at string) error {
	if e := ev.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.compilerReady(tx); e != nil {
			return e
		}
		key := "evidence/" + ev.InvocationID
		if e := putJSON(tx.Bucket([]byte("method_bindings")), key, ev); e != nil {
			return e
		}
		return s.appendCompilerEvent(tx, "evidence_classified", ev.InvocationID, at, ev)
	})
}
