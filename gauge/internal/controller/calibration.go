package controller

import (
	"errors"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureCalibrationStore() (*store.Store, error) {
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
	return db, nil
}

func (s *Service) EnsureCalibrationNamespaces() error {
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// StartCalibrationTrial registers a calibration trial that extends a V4-21 evaluation trial.
func (s *Service) StartCalibrationTrial(t contract.CalibrationTrial) (contract.CalibrationTrial, error) {
	t.SchemaVersion = contract.CalibrationSchemaVersion
	t.LiveBlocked = true
	if t.RecordedAt == "" {
		t.RecordedAt = s.nowRFC3339()
	}
	if len(t.Slices) == 0 {
		t.Slices = []string{"workflow-ablations", "routing-calibration"}
	}
	if t.PaidTrial && (!t.BillingAuthorized || t.AllowanceRef == "") {
		return t, errors.New("paid trial requires authorized billing allowance")
	}
	if e := t.Validate(); e != nil {
		return t, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return t, e
	}
	defer db.Close()
	if e = db.PutCalibrationTrial(t); e != nil {
		return t, e
	}
	return db.GetCalibrationTrial(t.ID)
}

// RecordCalibrationBaseline locks acceptance/authority digests for a mechanism comparison (R01).
func (s *Service) RecordCalibrationBaseline(b contract.CalibrationBaseline) (contract.CalibrationBaseline, error) {
	b.SchemaVersion = contract.CalibrationSchemaVersion
	if b.RecordedAt == "" {
		b.RecordedAt = s.nowRFC3339()
	}
	if e := b.Validate(); e != nil {
		return b, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return b, e
	}
	defer db.Close()
	if e = db.PutCalibrationBaseline(b); e != nil {
		return b, e
	}
	return db.GetCalibrationBaseline(b.ID)
}

// RecordCalibrationArm records one ablation arm; missing packages stay pending (not zeros).
func (s *Service) RecordCalibrationArm(a contract.CalibrationArm, availablePackages map[string]bool, baseline *contract.CalibrationBaseline) (contract.CalibrationArm, error) {
	a.SchemaVersion = contract.CalibrationSchemaVersion
	if a.RecordedAt == "" {
		a.RecordedAt = s.nowRFC3339()
	}
	a.FabricatedMetrics = 0
	pending, status, reason, missing := contract.ResolveMechanismEligibility(a.MechanismID, availablePackages)
	a.Pending = pending
	a.EligibilityStatus = status
	a.EligibilityReason = reason
	a.MissingPackage = missing

	if baseline != nil {
		ok, why := contract.CheckArmAgainstBaseline(*baseline, a)
		if !ok {
			a.WeakerAcceptance = true
			a.EligibilityStatus = contract.EligibilityIneligible
			a.EligibilityReason = why
			a.Pending = false
		}
	}
	if a.WeakerAcceptance && a.EligibilityStatus == contract.EligibilityEligible {
		a.EligibilityStatus = contract.EligibilityIneligible
		a.EligibilityReason = "weaker_acceptance_invalidates_improvement"
	}
	if e := a.Validate(); e != nil {
		return a, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return a, e
	}
	defer db.Close()
	if e = db.PutCalibrationArm(a); e != nil {
		return a, e
	}
	return db.GetCalibrationArm(a.ID)
}

// RecordCalibrationBatch enforces development/calibration-only tuning and freeze chronology (R02).
func (s *Service) RecordCalibrationBatch(b contract.CalibrationBatch) (contract.CalibrationBatch, error) {
	b.SchemaVersion = contract.CalibrationSchemaVersion
	if b.RecordedAt == "" {
		b.RecordedAt = s.nowRFC3339()
	}
	ok, reason := contract.FreezeBeforeHoldoutOK(b)
	if !ok || b.HoldoutDrivenTuning {
		b.Rejected = true
		if b.HoldoutDrivenTuning {
			b.RejectReason = "holdout_driven_tuning_prohibited"
		} else {
			b.RejectReason = reason
		}
	}
	if e := b.Validate(); e != nil {
		return b, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return b, e
	}
	defer db.Close()
	if e = db.PutCalibrationBatch(b); e != nil {
		return b, e
	}
	return db.GetCalibrationBatch(b.ID)
}

// PublishMechanismCostReport requires complete coordination/reconstruction costs for benefit claims (R03).
func (s *Service) PublishMechanismCostReport(r contract.MechanismCostReport) (contract.MechanismCostReport, error) {
	r.SchemaVersion = contract.CalibrationSchemaVersion
	if r.RecordedAt == "" {
		r.RecordedAt = s.nowRFC3339()
	}
	contract.CompleteMechanismCosts(&r)
	if e := r.Validate(); e != nil {
		return r, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return r, e
	}
	defer db.Close()
	if e = db.PutMechanismCostReport(r); e != nil {
		return r, e
	}
	return db.GetMechanismCostReport(r.ID)
}

// DecidePromotion leaves unsupported/null/inconclusive mechanisms unpromoted (R04).
func (s *Service) DecidePromotion(d contract.PromotionDecision) (contract.PromotionDecision, error) {
	d.SchemaVersion = contract.CalibrationSchemaVersion
	if d.RecordedAt == "" {
		d.RecordedAt = s.nowRFC3339()
	}
	contract.ApplyPromotionGate(&d)
	if e := d.Validate(); e != nil {
		return d, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return d, e
	}
	defer db.Close()
	if e = db.PutPromotionDecision(d); e != nil {
		return d, e
	}
	return db.GetPromotionDecision(d.ID)
}

// StopAtTrialBoundary stops further dispatch without self-authorized overage (R05).
func (s *Service) StopAtTrialBoundary(t contract.TrialBoundaryStop) (contract.TrialBoundaryStop, error) {
	t.SchemaVersion = contract.CalibrationSchemaVersion
	if t.RecordedAt == "" {
		t.RecordedAt = s.nowRFC3339()
	}
	contract.EvaluateTrialBoundary(&t)
	if e := t.Validate(); e != nil {
		return t, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return t, e
	}
	defer db.Close()
	if e = db.PutTrialBoundaryStop(t); e != nil {
		return t, e
	}
	return db.GetTrialBoundaryStop(t.ID)
}

// RecordStrategyDecision binds action to observed state, alternatives, policy, reason (R06).
func (s *Service) RecordStrategyDecision(d contract.StrategyDecision) (contract.StrategyDecision, error) {
	d.SchemaVersion = contract.CalibrationSchemaVersion
	if d.RecordedAt == "" {
		d.RecordedAt = s.nowRFC3339()
	}
	d.HiddenReasoning = false
	d.RegisteredOnly = true
	if e := d.Validate(); e != nil {
		return d, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return d, e
	}
	defer db.Close()
	if e = db.PutStrategyDecision(d); e != nil {
		return d, e
	}
	return db.GetStrategyDecision(d.ID)
}

// RecordAdaptationProposal versions experience-derived changes; bad experience cannot activate (R07).
func (s *Service) RecordAdaptationProposal(a contract.AdaptationRecord) (contract.AdaptationRecord, error) {
	a.SchemaVersion = contract.CalibrationSchemaVersion
	if a.RecordedAt == "" {
		a.RecordedAt = s.nowRFC3339()
	}
	contract.GateAdaptationExperience(&a)
	if e := a.Validate(); e != nil {
		return a, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return a, e
	}
	defer db.Close()
	if e = db.PutAdaptationRecord(a); e != nil {
		return a, e
	}
	return db.GetAdaptationRecord(a.ID)
}

// ReportGeneralization labels same-batch adaptation vs forward-qualified transfer (R08).
func (s *Service) ReportGeneralization(g contract.GeneralizationReport) (contract.GeneralizationReport, error) {
	g.SchemaVersion = contract.CalibrationSchemaVersion
	if g.RecordedAt == "" {
		g.RecordedAt = s.nowRFC3339()
	}
	contract.LabelGeneralization(&g)
	if g.MeasuredScope == "" {
		g.MeasuredScope = "undeclared"
	}
	if e := g.Validate(); e != nil {
		return g, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return g, e
	}
	defer db.Close()
	if e = db.PutGeneralizationReport(g); e != nil {
		return g, e
	}
	return db.GetGeneralizationReport(g.ID)
}

// RegisterPromotedStrategy binds model/harness/task scope and revalidation conditions (R09).
func (s *Service) RegisterPromotedStrategy(p contract.PromotedStrategyRegistry) (contract.PromotedStrategyRegistry, error) {
	p.SchemaVersion = contract.CalibrationSchemaVersion
	if p.RecordedAt == "" {
		p.RecordedAt = s.nowRFC3339()
	}
	if e := p.Validate(); e != nil {
		return p, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return p, e
	}
	defer db.Close()
	if e = db.PutPromotedStrategy(p); e != nil {
		return p, e
	}
	return db.GetPromotedStrategy(p.ID)
}

// RevalidatePromotedStrategy invalidates benefit claims on model/harness/task-distribution change (R09).
func (s *Service) RevalidatePromotedStrategy(id, observedModel, observedHarness, observedTaskScope string) (contract.PromotedStrategyRegistry, error) {
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return contract.PromotedStrategyRegistry{}, e
	}
	defer db.Close()
	p, e := db.GetPromotedStrategy(id)
	if e != nil {
		return p, e
	}
	contract.InvalidateOnDistributionChange(&p, observedModel, observedHarness, observedTaskScope)
	p.RecordedAt = s.nowRFC3339()
	if e := p.Validate(); e != nil {
		return p, e
	}
	if e = db.UpdatePromotedStrategy(p); e != nil {
		return p, e
	}
	return db.GetPromotedStrategy(p.ID)
}

// RecordOfflineAdaptationBoundary isolates offline proposals from production control (R10).
func (s *Service) RecordOfflineAdaptationBoundary(o contract.OfflineAdaptationBoundary) (contract.OfflineAdaptationBoundary, error) {
	o.SchemaVersion = contract.CalibrationSchemaVersion
	if o.RecordedAt == "" {
		o.RecordedAt = s.nowRFC3339()
	}
	contract.EnforceOfflineIsolation(&o)
	if e := o.Validate(); e != nil {
		return o, e
	}
	db, e := s.ensureCalibrationStore()
	if e != nil {
		return o, e
	}
	defer db.Close()
	if e = db.PutOfflineAdaptationBoundary(o); e != nil {
		return o, e
	}
	return db.GetOfflineAdaptationBoundary(o.ID)
}
