package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"sort"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var evaluationBuckets = []string{
	"evaluation_trials", "evaluation_arm_identities", "evaluation_holdouts",
	"evaluation_plumbing", "evaluation_admissions", "evaluation_drifts",
	"evaluation_outcomes", "evaluation_reports", "evaluation_promotions",
	"evaluation_attempts", "evaluation_events",
}

type evaluationReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeEvaluation(tx *bolt.Tx, id, kind string) error {
	for _, name := range evaluationBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "evaluation_receipt", evaluationReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.EvaluationSchemaVersion,
	})
}

func guardEvaluation(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("evaluation_receipt"))
	missing := 0
	for _, name := range evaluationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(evaluationBuckets) {
		// Pre-V4-21 schema 2 stores remain openable; evaluation APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete evaluation namespaces; call evaluation-enable")
	}
	var receipt evaluationReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid evaluation receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.EvaluationSchemaVersion {
		return errors.New("unsupported evaluation receipt")
	}
	return nil
}

func (s *Store) evaluationReady(tx *bolt.Tx) error {
	for _, name := range evaluationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("evaluation namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("evaluation_receipt")) == nil {
		return errors.New("evaluation namespaces required")
	}
	return nil
}

// EnsureEvaluationNamespaces adds typed evaluation buckets under schema 2 without a schema bump.
func (s *Store) EnsureEvaluationNamespaces() error {
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
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("evaluation_receipt")); raw != nil {
			return guardEvaluation(tx)
		}
		if e := initializeEvaluation(tx, id, "ensure"); e != nil {
			return e
		}
		return guardEvaluation(tx)
	})
}

func (s *Store) appendEvaluationEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "subject": subject, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, subject)
	return tx.Bucket([]byte("evaluation_events")).Put([]byte(key), raw)
}

func (s *Store) PutEvaluationTrial(t contract.EvaluationTrial) error {
	if e := t.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_trials"))
		if prev := b.Get([]byte(t.ID)); prev != nil {
			var existing contract.EvaluationTrial
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, t) {
				return errors.New("evaluation trial identity conflict")
			}
			return nil
		}
		if e := putJSON(b, t.ID, t); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "trial", t.ID, t.RecordedAt, map[string]string{
			"protocol": t.ProtocolID, "digest": t.ProtocolDigest,
		})
	})
}

func (s *Store) GetEvaluationTrial(id string) (contract.EvaluationTrial, error) {
	var t contract.EvaluationTrial
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_trials")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown evaluation trial")
		}
		return contract.StrictJSON(raw, &t)
	})
	return t, e
}

func (s *Store) PutEvalArmIdentity(a contract.EvalArmIdentity) error {
	if e := a.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		key := a.TrialID + "/" + a.ArmID + "/" + a.ID
		b := tx.Bucket([]byte("evaluation_arm_identities"))
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.EvalArmIdentity
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, a) {
				return errors.New("evaluation arm identity conflict")
			}
			return nil
		}
		if e := putJSON(b, key, a); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "arm_identity", key, a.RecordedAt, map[string]any{
			"role": a.Role, "pending": a.Pending, "confounds": a.Confounds,
		})
	})
}

func (s *Store) ListEvalArmIdentities(trialID string) ([]contract.EvalArmIdentity, error) {
	var out []contract.EvalArmIdentity
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		prefix := trialID + "/"
		return tx.Bucket([]byte("evaluation_arm_identities")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var a contract.EvalArmIdentity
			if e := contract.StrictJSON(v, &a); e != nil {
				return e
			}
			out = append(out, a)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}

func (s *Store) PutHoldoutBoundary(h contract.HoldoutBoundary) error {
	if e := h.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_holdouts"))
		if prev := b.Get([]byte(h.ID)); prev != nil {
			var existing contract.HoldoutBoundary
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, h) {
				return errors.New("holdout boundary identity conflict")
			}
			return nil
		}
		if e := putJSON(b, h.ID, h); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "holdout", h.ID, h.RecordedAt, map[string]any{
			"isolated": h.Isolated, "canaries": h.CanaryTriggered,
		})
	})
}

func (s *Store) GetHoldoutBoundary(id string) (contract.HoldoutBoundary, error) {
	var h contract.HoldoutBoundary
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_holdouts")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown holdout boundary")
		}
		return contract.StrictJSON(raw, &h)
	})
	return h, e
}

func (s *Store) PutPlumbingEvidence(p contract.PlumbingEvidence) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_plumbing"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.PlumbingEvidence
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("plumbing evidence identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "plumbing", p.ID, p.RecordedAt, map[string]any{
			"class": p.EvidenceClass, "live_blocked": p.LiveBlocked,
		})
	})
}

func (s *Store) GetPlumbingEvidence(id string) (contract.PlumbingEvidence, error) {
	var p contract.PlumbingEvidence
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_plumbing")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown plumbing evidence")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutTaskAdmission(t contract.TaskAdmission) error {
	if e := t.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_admissions"))
		if prev := b.Get([]byte(t.ID)); prev != nil {
			var existing contract.TaskAdmission
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, t) {
				return errors.New("task admission identity conflict")
			}
			return nil
		}
		if e := putJSON(b, t.ID, t); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "admission", t.ID, t.RecordedAt, map[string]any{
			"admitted": t.Admitted, "requirement": t.RequirementStatus,
		})
	})
}

func (s *Store) GetTaskAdmission(id string) (contract.TaskAdmission, error) {
	var t contract.TaskAdmission
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_admissions")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown task admission")
		}
		return contract.StrictJSON(raw, &t)
	})
	return t, e
}

func (s *Store) PutEnvironmentDrift(d contract.EnvironmentDrift) error {
	if e := d.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_drifts"))
		if prev := b.Get([]byte(d.ID)); prev != nil {
			var existing contract.EnvironmentDrift
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, d) {
				return errors.New("environment drift identity conflict")
			}
			return nil
		}
		if e := putJSON(b, d.ID, d); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "drift", d.ID, d.RecordedAt, map[string]any{
			"confounded": d.Confounded, "labels": d.DiffLabels,
		})
	})
}

func (s *Store) GetEnvironmentDrift(id string) (contract.EnvironmentDrift, error) {
	var d contract.EnvironmentDrift
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_drifts")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown environment drift")
		}
		return contract.StrictJSON(raw, &d)
	})
	return d, e
}

func (s *Store) PutOutcomeDistinction(o contract.OutcomeDistinction) error {
	if e := o.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_outcomes"))
		if prev := b.Get([]byte(o.ID)); prev != nil {
			var existing contract.OutcomeDistinction
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, o) {
				return errors.New("outcome distinction identity conflict")
			}
			return nil
		}
		if e := putJSON(b, o.ID, o); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "outcome", o.ID, o.RecordedAt, map[string]any{
			"operational": o.OperationalOutcome, "identical_claim": o.IdenticalClaim,
		})
	})
}

func (s *Store) GetOutcomeDistinction(id string) (contract.OutcomeDistinction, error) {
	var o contract.OutcomeDistinction
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_outcomes")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown outcome distinction")
		}
		return contract.StrictJSON(raw, &o)
	})
	return o, e
}

func (s *Store) PutEvalReportMetrics(m contract.EvalReportMetrics) error {
	if e := m.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_reports"))
		if prev := b.Get([]byte(m.ID)); prev != nil {
			var existing contract.EvalReportMetrics
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, m) {
				return errors.New("evaluation report identity conflict")
			}
			return nil
		}
		if e := putJSON(b, m.ID, m); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "report", m.ID, m.RecordedAt, map[string]any{
			"sample": m.SampleSize, "small": m.SmallSample,
		})
	})
}

func (s *Store) GetEvalReportMetrics(id string) (contract.EvalReportMetrics, error) {
	var m contract.EvalReportMetrics
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_reports")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown evaluation report")
		}
		return contract.StrictJSON(raw, &m)
	})
	return m, e
}

func (s *Store) PutPromotionSet(p contract.PromotionSet) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		b := tx.Bucket([]byte("evaluation_promotions"))
		if prev := b.Get([]byte(p.ID)); prev != nil {
			var existing contract.PromotionSet
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, p) {
				return errors.New("promotion set identity conflict")
			}
			return nil
		}
		if e := putJSON(b, p.ID, p); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "promotion", p.ID, p.RecordedAt, map[string]any{
			"frozen": p.CandidateFrozen, "forward": p.ForwardStatus,
		})
	})
}

func (s *Store) GetPromotionSet(id string) (contract.PromotionSet, error) {
	var p contract.PromotionSet
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("evaluation_promotions")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown promotion set")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutEvalAttempt(a contract.EvalAttempt) error {
	if e := a.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		key := a.ProtocolID + "/" + a.ArmID + "/" + a.ID
		b := tx.Bucket([]byte("evaluation_attempts"))
		if prev := b.Get([]byte(key)); prev != nil {
			var existing contract.EvalAttempt
			if e := contract.StrictJSON(prev, &existing); e != nil {
				return e
			}
			if !reflect.DeepEqual(existing, a) {
				return errors.New("evaluation attempt identity conflict")
			}
			return nil
		}
		if e := putJSON(b, key, a); e != nil {
			return e
		}
		return s.appendEvaluationEvent(tx, "attempt", key, a.EndedAt, map[string]any{
			"terminal": a.TerminalState, "acceptance": a.Acceptance, "split": a.Split,
		})
	})
}

func (s *Store) ListEvalAttempts(protocolID string) ([]contract.EvalAttempt, error) {
	var out []contract.EvalAttempt
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.evaluationReady(tx); e != nil {
			return e
		}
		prefix := protocolID + "/"
		return tx.Bucket([]byte("evaluation_attempts")).ForEach(func(k, v []byte) error {
			if !hasPrefix(string(k), prefix) {
				return nil
			}
			var a contract.EvalAttempt
			if e := contract.StrictJSON(v, &a); e != nil {
				return e
			}
			out = append(out, a)
			return nil
		})
	})
	sort.Slice(out, func(i, j int) bool { return out[i].ID < out[j].ID })
	return out, e
}
