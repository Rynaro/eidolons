package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"reflect"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	bolt "go.etcd.io/bbolt"
)

var releaseBuckets = []string{
	"release_migrations", "release_recoveries", "release_candidates",
	"release_authorizations", "release_retirements", "release_host_caps",
	"release_readiness", "release_rollbacks", "release_events",
}

type releaseReceipt struct {
	Version    int    `json:"schema_version"`
	Controller string `json:"controller"`
	Kind       string `json:"kind"`
	Typed      int    `json:"typed_version"`
}

func initializeRelease(tx *bolt.Tx, id, kind string) error {
	for _, name := range releaseBuckets {
		if _, e := tx.CreateBucketIfNotExists([]byte(name)); e != nil {
			return e
		}
	}
	return putJSON(tx.Bucket([]byte("meta")), "release_receipt", releaseReceipt{
		Version: 1, Controller: id, Kind: kind, Typed: contract.ReleaseSchemaVersion,
	})
}

func guardRelease(tx *bolt.Tx) error {
	meta := tx.Bucket([]byte("meta"))
	raw := meta.Get([]byte("release_receipt"))
	missing := 0
	for _, name := range releaseBuckets {
		if tx.Bucket([]byte(name)) == nil {
			missing++
		}
	}
	if raw == nil && missing == len(releaseBuckets) {
		// Pre-V4-23 schema 2 stores remain openable; release APIs ensure namespaces.
		return nil
	}
	if raw == nil || missing != 0 {
		return errors.New("incomplete release namespaces; call release-enable")
	}
	var receipt releaseReceipt
	if e := contract.StrictJSON(raw, &receipt); e != nil {
		return errors.New("invalid release receipt")
	}
	id := string(meta.Get([]byte("store_id")))
	if receipt.Version != 1 || receipt.Controller != id || receipt.Typed != contract.ReleaseSchemaVersion {
		return errors.New("unsupported release receipt")
	}
	return nil
}

func (s *Store) releaseReady(tx *bolt.Tx) error {
	for _, name := range releaseBuckets {
		if tx.Bucket([]byte(name)) == nil {
			return errors.New("release namespaces required")
		}
	}
	if tx.Bucket([]byte("meta")).Get([]byte("release_receipt")) == nil {
		return errors.New("release namespaces required")
	}
	return nil
}

// EnsureReleaseNamespaces adds typed release/migration buckets under schema 2 without a schema bump.
func (s *Store) EnsureReleaseNamespaces() error {
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
		if e := guardCalibration(tx); e != nil {
			return e
		}
		id := string(tx.Bucket([]byte("meta")).Get([]byte("store_id")))
		if raw := tx.Bucket([]byte("meta")).Get([]byte("release_receipt")); raw != nil {
			return guardRelease(tx)
		}
		if e := initializeRelease(tx, id, "ensure"); e != nil {
			return e
		}
		return guardRelease(tx)
	})
}

func (s *Store) appendReleaseEvent(tx *bolt.Tx, kind, subject, at string, detail any) error {
	payload := map[string]any{
		"kind": kind, "subject": subject, "recorded_at": at, "detail": detail,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return e
	}
	key := fmt.Sprintf("%s/%s/%s", at, kind, subject)
	return tx.Bucket([]byte("release_events")).Put([]byte(key), raw)
}

func putReleaseIdentity(tx *bolt.Tx, bucket, key string, v any) error {
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

func (s *Store) PutMigrationAttempt(m contract.MigrationAttempt) error {
	if e := m.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_migrations", m.ID, m); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "migration", m.ID, m.RecordedAt, map[string]any{
			"origin": m.Origin, "stage": m.Stage, "switched": m.ActiveSwitched, "rejected": m.Rejected,
		})
	})
}

func (s *Store) GetMigrationAttempt(id string) (contract.MigrationAttempt, error) {
	var m contract.MigrationAttempt
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_migrations")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown migration attempt")
		}
		return contract.StrictJSON(raw, &m)
	})
	return m, e
}

func (s *Store) PutMigrationRecovery(r contract.MigrationRecovery) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_recoveries", r.ID, r); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "recovery", r.ID, r.RecordedAt, map[string]any{
			"migration": r.MigrationID, "restored": r.PreviousInstallRestored,
		})
	})
}

func (s *Store) GetMigrationRecovery(id string) (contract.MigrationRecovery, error) {
	var r contract.MigrationRecovery
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_recoveries")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown migration recovery")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}

func (s *Store) PutReleaseCandidate(c contract.ReleaseCandidate) error {
	if e := c.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_candidates", c.ID, c); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "candidate", c.ID, c.RecordedAt, map[string]any{
			"kind": c.Kind, "passed": c.GatePassed,
		})
	})
}

func (s *Store) GetReleaseCandidate(id string) (contract.ReleaseCandidate, error) {
	var c contract.ReleaseCandidate
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_candidates")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown release candidate")
		}
		return contract.StrictJSON(raw, &c)
	})
	return c, e
}

func (s *Store) PutPromotionAuthorization(p contract.PromotionAuthorization) error {
	if e := p.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_authorizations", p.ID, p); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "authorization", p.ID, p.RecordedAt, map[string]any{
			"block": p.BlockReason, "defaults_changed": p.BehavioralDefaultsChanged,
		})
	})
}

func (s *Store) GetPromotionAuthorization(id string) (contract.PromotionAuthorization, error) {
	var p contract.PromotionAuthorization
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_authorizations")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown promotion authorization")
		}
		return contract.StrictJSON(raw, &p)
	})
	return p, e
}

func (s *Store) PutRetirementRequest(r contract.RetirementRequest) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_retirements", r.ID, r); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "retirement", r.ID, r.RecordedAt, map[string]any{
			"blocked": r.RetirementBlocked, "reason": r.BlockReason,
		})
	})
}

func (s *Store) GetRetirementRequest(id string) (contract.RetirementRequest, error) {
	var r contract.RetirementRequest
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_retirements")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown retirement request")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}

func (s *Store) PutHostCapabilityQualification(h contract.HostCapabilityQualification) error {
	if e := h.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_host_caps", h.ID, h); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "host_cap", h.ID, h.RecordedAt, map[string]any{
			"valid": h.QualificationValid, "recheck": h.RecheckRequired,
		})
	})
}

func (s *Store) UpdateHostCapabilityQualification(h contract.HostCapabilityQualification) error {
	if e := h.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putJSON(tx.Bucket([]byte("release_host_caps")), h.ID, h); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "host_cap_invalidate", h.ID, h.RecordedAt, map[string]any{
			"valid": h.QualificationValid, "reason": h.InvalidationReason,
		})
	})
}

func (s *Store) GetHostCapabilityQualification(id string) (contract.HostCapabilityQualification, error) {
	var h contract.HostCapabilityQualification
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_host_caps")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown host capability qualification")
		}
		return contract.StrictJSON(raw, &h)
	})
	return h, e
}

func (s *Store) PutReleaseReadinessReport(r contract.ReleaseReadinessReport) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_readiness", r.ID, r); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "readiness", r.ID, r.RecordedAt, map[string]any{
			"correctness": r.CorrectnessDecision,
			"managed":     r.ManagedOperationDecision,
			"performance": r.PerformancePromotionDecision,
		})
	})
}

func (s *Store) GetReleaseReadinessReport(id string) (contract.ReleaseReadinessReport, error) {
	var r contract.ReleaseReadinessReport
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_readiness")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown release readiness report")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}

func (s *Store) PutStrategyMethodRollback(r contract.StrategyMethodRollback) error {
	if e := r.Validate(); e != nil {
		return e
	}
	return s.db.Update(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		if e := putReleaseIdentity(tx, "release_rollbacks", r.ID, r); e != nil {
			return e
		}
		return s.appendReleaseEvent(tx, "rollback", r.ID, r.RecordedAt, map[string]any{
			"target": r.RollbackTarget, "lineage": r.TaskLineageRetained,
		})
	})
}

func (s *Store) GetStrategyMethodRollback(id string) (contract.StrategyMethodRollback, error) {
	var r contract.StrategyMethodRollback
	e := s.db.View(func(tx *bolt.Tx) error {
		if e := s.releaseReady(tx); e != nil {
			return e
		}
		raw := tx.Bucket([]byte("release_rollbacks")).Get([]byte(id))
		if raw == nil {
			return errors.New("unknown strategy method rollback")
		}
		return contract.StrictJSON(raw, &r)
	})
	return r, e
}
