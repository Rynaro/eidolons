package controller

import (
	"errors"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureReleaseStore() (*store.Store, error) {
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
	if e = db.EnsureDeliveryNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureEvaluationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureContextNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureCalibrationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureReleaseNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

func (s *Service) EnsureReleaseNamespaces() error {
	db, e := s.ensureReleaseStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// AttemptMigration stages/verifies before switching; refuses force-integrity bypass (R01).
func (s *Service) AttemptMigration(m contract.MigrationAttempt) (contract.MigrationAttempt, error) {
	m.SchemaVersion = contract.ReleaseSchemaVersion
	if m.RecordedAt == "" {
		m.RecordedAt = s.nowRFC3339()
	}
	if m.FailurePoint == "" {
		m.FailurePoint = contract.MigFailNone
	}
	if m.Stage == "" {
		m.Stage = contract.MigStageStaging
	}
	m.ForceIntegrityBypass = false
	contract.StageAndVerifyMigration(&m)
	if e := m.Validate(); e != nil {
		return m, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return m, e
	}
	defer db.Close()
	if e = db.PutMigrationAttempt(m); e != nil {
		return m, e
	}
	return db.GetMigrationAttempt(m.ID)
}

// RecoverMigration restores previous installation and user state after failure (R02).
func (s *Service) RecoverMigration(migrationID string) (contract.MigrationRecovery, error) {
	db, e := s.ensureReleaseStore()
	if e != nil {
		return contract.MigrationRecovery{}, e
	}
	defer db.Close()
	m, e := db.GetMigrationAttempt(migrationID)
	if e != nil {
		return contract.MigrationRecovery{}, e
	}
	if m.FailurePoint == contract.MigFailNone && !m.Rejected {
		return contract.MigrationRecovery{}, errors.New("recovery requires a failed migration")
	}
	r := contract.RecoverFailedMigration(m)
	if r.RecordedAt == "" {
		r.RecordedAt = s.nowRFC3339()
	}
	if e := r.Validate(); e != nil {
		return r, e
	}
	if e = db.PutMigrationRecovery(r); e != nil {
		return r, e
	}
	return db.GetMigrationRecovery(r.ID)
}

// EvaluateReleaseCandidate requires deterministic checks and applicable live evidence (R03).
func (s *Service) EvaluateReleaseCandidate(c contract.ReleaseCandidate) (contract.ReleaseCandidate, error) {
	c.SchemaVersion = contract.ReleaseSchemaVersion
	if c.RecordedAt == "" {
		c.RecordedAt = s.nowRFC3339()
	}
	contract.EvaluateReleaseGate(&c)
	if e := c.Validate(); e != nil {
		return c, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return c, e
	}
	defer db.Close()
	if e = db.PutReleaseCandidate(c); e != nil {
		return c, e
	}
	return db.GetReleaseCandidate(c.ID)
}

// AuthorizePromotion refuses tag/merge/publication and leaves behavioral defaults unchanged (R04).
func (s *Service) AuthorizePromotion(p contract.PromotionAuthorization) (contract.PromotionAuthorization, error) {
	p.SchemaVersion = contract.ReleaseSchemaVersion
	if p.RecordedAt == "" {
		p.RecordedAt = s.nowRFC3339()
	}
	contract.GatePromotionAuthorization(&p)
	if e := p.Validate(); e != nil {
		return p, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return p, e
	}
	defer db.Close()
	if e = db.PutPromotionAuthorization(p); e != nil {
		return p, e
	}
	return db.GetPromotionAuthorization(p.ID)
}

// EvaluateRetirement blocks while unmigrated supported consumers remain (R05).
func (s *Service) EvaluateRetirement(r contract.RetirementRequest) (contract.RetirementRequest, error) {
	r.SchemaVersion = contract.ReleaseSchemaVersion
	if r.RecordedAt == "" {
		r.RecordedAt = s.nowRFC3339()
	}
	contract.EvaluateRetirementGate(&r)
	if e := r.Validate(); e != nil {
		return r, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return r, e
	}
	defer db.Close()
	if e = db.PutRetirementRequest(r); e != nil {
		return r, e
	}
	return db.GetRetirementRequest(r.ID)
}

// RegisterHostCapabilityQualification records catalogue qualification for a host version (R06).
func (s *Service) RegisterHostCapabilityQualification(h contract.HostCapabilityQualification) (contract.HostCapabilityQualification, error) {
	h.SchemaVersion = contract.ReleaseSchemaVersion
	if h.RecordedAt == "" {
		h.RecordedAt = s.nowRFC3339()
	}
	if e := h.Validate(); e != nil {
		return h, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return h, e
	}
	defer db.Close()
	if e = db.PutHostCapabilityQualification(h); e != nil {
		return h, e
	}
	return db.GetHostCapabilityQualification(h.ID)
}

// InvalidateHostCapabilityOnVersionChange stops managed claims until rechecked (R06).
func (s *Service) InvalidateHostCapabilityOnVersionChange(id, observedVersion string) (contract.HostCapabilityQualification, error) {
	db, e := s.ensureReleaseStore()
	if e != nil {
		return contract.HostCapabilityQualification{}, e
	}
	defer db.Close()
	h, e := db.GetHostCapabilityQualification(id)
	if e != nil {
		return h, e
	}
	h.ObservedHostVersion = observedVersion
	contract.InvalidateOnHostVersionChange(&h)
	h.RecordedAt = s.nowRFC3339()
	if e := h.Validate(); e != nil {
		return h, e
	}
	if e = db.UpdateHostCapabilityQualification(h); e != nil {
		return h, e
	}
	return db.GetHostCapabilityQualification(h.ID)
}

// ReportReleaseReadiness reports correctness, managed-op, and performance as separate decisions (R07).
func (s *Service) ReportReleaseReadiness(r contract.ReleaseReadinessReport) (contract.ReleaseReadinessReport, error) {
	r.SchemaVersion = contract.ReleaseSchemaVersion
	if r.RecordedAt == "" {
		r.RecordedAt = s.nowRFC3339()
	}
	contract.ComposeReadinessReport(&r)
	if e := r.Validate(); e != nil {
		return r, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return r, e
	}
	defer db.Close()
	if e = db.PutReleaseReadinessReport(r); e != nil {
		return r, e
	}
	return db.GetReleaseReadinessReport(r.ID)
}

// RollbackStrategyMethod retains lineage/evidence/obligations without stale authority (R08).
func (s *Service) RollbackStrategyMethod(r contract.StrategyMethodRollback) (contract.StrategyMethodRollback, error) {
	r.SchemaVersion = contract.ReleaseSchemaVersion
	if r.RecordedAt == "" {
		r.RecordedAt = s.nowRFC3339()
	}
	contract.ApplyStrategyRollback(&r)
	if e := r.Validate(); e != nil {
		return r, e
	}
	db, e := s.ensureReleaseStore()
	if e != nil {
		return r, e
	}
	defer db.Close()
	if e = db.PutStrategyMethodRollback(r); e != nil {
		return r, e
	}
	return db.GetStrategyMethodRollback(r.ID)
}
