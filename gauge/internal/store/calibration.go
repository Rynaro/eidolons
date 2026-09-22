package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var calibrationBuckets = []string{
	"calibration_trials", "calibration_baselines", "calibration_arms",
	"calibration_batches", "calibration_costs", "calibration_promotions",
	"calibration_boundaries", "calibration_decisions", "calibration_adaptations",
	"calibration_generalizations", "calibration_strategies", "calibration_offline",
	"calibration_events",
}

type calibrationReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeCalibration(tx *bolt.Tx, id, kind string) error {
	for _, name := range calibrationBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "calibration_receipt", calibrationReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.CalibrationSchemaVersion,
	})
}

func guardCalibration(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("calibration_receipt"))
	missing := 0
	for _, name := range calibrationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(calibrationBuckets) {
		// Pre-V4-22 schema 2 stores remain openable; calibration APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete calibration namespaces; call calibration-enable")
	}
	var receipt calibrationReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid calibration receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.CalibrationSchemaVersion {
		return errors.New("unsupported calibration receipt")
	}
	return nil
}

func (s *Store) calibrationReady(tx *bolt.Tx) error {
	for _, name := range calibrationBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("calibration namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("calibration_receipt")) == nil {
		return errors.New("calibration namespaces required")
	}
	return nil
}

// EnsureCalibrationNamespaces adds typed calibration buckets under schema 2 without a schema bump.
func (s *Store) EnsureCalibrationNamespaces() error {
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
		if e := guardContext(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("calibration_receipt")); raw != nil {
			return guardCalibration(tx)
		}
		if e := initializeCalibration(tx, id, "ensure"); e != nil {
			return e
		}
		return guardCalibration(tx)
	})
}

func (s *Store) appendCalibrationEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "subject": subject, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, subject)
	return tx.Bucket([]byte("calibration_events")).Put([]byte(key), raw)
}

func putCalibIdentity(tx *bolt.Tx, bucket, key string, v any) error {
	b := tx.Bucket([]byte(bucket))
	if prev := b.Get([]byte(key)); prev != nil {
		next, e := json.Marshal(v)
		if e != nil {
			return e
		}
		var prevObj, nextObj any
		if e := json.Unmarshal(prev, &prevObj); e != nil {
			return e
		}
		if e := json.Unmarshal(next, &nextObj); e != nil {
			return e
		}
		if !reflect.DeepEqual(prevObj, nextObj) {
			return errors.New(bucket + " identity conflict")
		}
		return nil
	}
	return putJSON(b, key, v)
}

func (s *Store) PutCalibrationTrial(t contract.CalibrationTrial) error {
	if e := t.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_trials", t.ID, t); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "trial", t.ID, t.RecordedAt, map[string]any{
			"evaluation_trial": t.EvaluationTrialID, "mechanisms": t.MechanismIDs,
		})
	})
}

func (s *Store) GetCalibrationTrial(id string) (contract.CalibrationTrial, error) {
	var t contract.CalibrationTrial
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_trials")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown calibration trial")
		}
		return contract.StrictJSON(raw, &t)
	})
	return t, e
}

func (s *Store) PutCalibrationBaseline(b contract.CalibrationBaseline) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := b.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_baselines", b.ID, b); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "baseline", b.ID, b.RecordedAt, map[string]any{
			"mechanism": b.MechanismID, "invalidated": b.Invalidated,
		})
	})
}

func (s *Store) GetCalibrationBaseline(id string) (contract.CalibrationBaseline, error) {
	var b contract.CalibrationBaseline
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_baselines")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown calibration baseline")
		}
		return contract.StrictJSON(raw, &b)
	})
	return b, e
}

func (s *Store) PutCalibrationArm(a contract.CalibrationArm) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := a.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_arms", a.ID, a); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "arm", a.ID, a.RecordedAt, map[string]any{
			"mechanism": a.MechanismID, "pending": a.Pending, "status": a.EligibilityStatus,
		})
	})
}

func (s *Store) GetCalibrationArm(id string) (contract.CalibrationArm, error) {
	var a contract.CalibrationArm
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_arms")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown calibration arm")
		}
		return contract.StrictJSON(raw, &a)
	})
	return a, e
}

func (s *Store) PutCalibrationBatch(b contract.CalibrationBatch) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := b.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_batches", b.ID, b); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "batch", b.ID, b.RecordedAt, map[string]any{
			"split": b.Split, "rejected": b.Rejected,
		})
	})
}

func (s *Store) GetCalibrationBatch(id string) (contract.CalibrationBatch, error) {
	var b contract.CalibrationBatch
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_batches")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown calibration batch")
		}
		return contract.StrictJSON(raw, &b)
	})
	return b, e
}

func (s *Store) PutMechanismCostReport(r contract.MechanismCostReport) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := r.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_costs", r.ID, r); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "cost", r.ID, r.RecordedAt, map[string]any{
			"mechanism": r.MechanismID, "complete": r.CostsComplete,
		})
	})
}

func (s *Store) GetMechanismCostReport(id string) (contract.MechanismCostReport, error) {
	var r contract.MechanismCostReport
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_costs")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown mechanism cost report")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}

func (s *Store) PutPromotionDecision(d contract.PromotionDecision) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := d.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_promotions", d.ID, d); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "promotion", d.ID, d.RecordedAt, map[string]any{
			"verdict": d.Verdict, "status": d.PromotionStatus,
		})
	})
}

func (s *Store) GetPromotionDecision(id string) (contract.PromotionDecision, error) {
	var d contract.PromotionDecision
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_promotions")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown promotion decision")
		}
		return contract.StrictJSON(raw, &d)
	})
	return d, e
}

func (s *Store) PutTrialBoundaryStop(t contract.TrialBoundaryStop) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := t.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_boundaries", t.ID, t); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "boundary", t.ID, t.RecordedAt, map[string]any{
			"stopped": t.Stopped, "reason": t.StopReason,
		})
	})
}

func (s *Store) GetTrialBoundaryStop(id string) (contract.TrialBoundaryStop, error) {
	var t contract.TrialBoundaryStop
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_boundaries")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown trial boundary")
		}
		return contract.StrictJSON(raw, &t)
	})
	return t, e
}

func (s *Store) PutStrategyDecision(d contract.StrategyDecision) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := d.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_decisions", d.ID, d); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "decision", d.ID, d.RecordedAt, map[string]any{
			"action": d.SelectedAction, "policy": d.PolicyVersion,
		})
	})
}

func (s *Store) GetStrategyDecision(id string) (contract.StrategyDecision, error) {
	var d contract.StrategyDecision
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_decisions")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown strategy decision")
		}
		return contract.StrictJSON(raw, &d)
	})
	return d, e
}

func (s *Store) PutAdaptationRecord(a contract.AdaptationRecord) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := a.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_adaptations", a.ID, a); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "adaptation", a.ID, a.RecordedAt, map[string]any{
			"quality": a.ExperienceQuality, "active": a.ActiveRule, "rejected": a.Rejected,
		})
	})
}

func (s *Store) GetAdaptationRecord(id string) (contract.AdaptationRecord, error) {
	var a contract.AdaptationRecord
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_adaptations")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown adaptation record")
		}
		return contract.StrictJSON(raw, &a)
	})
	return a, e
}

func (s *Store) PutGeneralizationReport(g contract.GeneralizationReport) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := g.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_generalizations", g.ID, g); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "generalization", g.ID, g.RecordedAt, map[string]any{
			"label": g.Label, "claims": g.ClaimsGeneralization,
		})
	})
}

func (s *Store) GetGeneralizationReport(id string) (contract.GeneralizationReport, error) {
	var g contract.GeneralizationReport
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_generalizations")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown generalization report")
		}
		return contract.StrictJSON(raw, &g)
	})
	return g, e
}

func (s *Store) PutPromotedStrategy(p contract.PromotedStrategyRegistry) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := p.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_strategies", p.ID, p); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "strategy", p.ID, p.RecordedAt, map[string]any{
			"version": p.StrategyVersion, "valid": p.BenefitClaimValid,
		})
	})
}

// UpdatePromotedStrategy overwrites a registry entry after revalidation invalidation (R09).
func (s *Store) UpdatePromotedStrategy(p contract.PromotedStrategyRegistry) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("calibration_strategies")), p.ID, p); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "strategy_revalidate", p.ID, p.RecordedAt, map[string]any{
			"valid": p.BenefitClaimValid, "reason": p.InvalidationReason,
		})
	})
}

func (s *Store) GetPromotedStrategy(id string) (contract.PromotedStrategyRegistry, error) {
	var p contract.PromotedStrategyRegistry
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_strategies")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown promoted strategy")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutOfflineAdaptationBoundary(o contract.OfflineAdaptationBoundary) error {
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		if e := o.Validate(); e != nil {
			return e
		}
		if e := putCalibIdentity(tx, "calibration_offline", o.ID, o); e != nil {
			return e
		}
		return s.appendCalibrationEvent(tx, "offline", o.ID, o.RecordedAt, map[string]any{
			"enabled": o.ExperimentEnabled, "rejected": o.Rejected, "sandbox": o.SandboxOnly,
		})
	})
}

func (s *Store) GetOfflineAdaptationBoundary(id string) (contract.OfflineAdaptationBoundary, error) {
	var o contract.OfflineAdaptationBoundary
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.calibrationReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("calibration_offline")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown offline adaptation boundary")
		}
		return contract.StrictJSON(raw, &o)
	})
	return o, e
}
