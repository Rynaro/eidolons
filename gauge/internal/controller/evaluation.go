package controller

import (
	"errors"
	"sort"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureEvaluationStore() (*store.Store, error) {
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
	return db, nil
}

func (s *Service) EnsureEvaluationNamespaces() error {
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// StartEvaluationTrial registers an auditable trial bound to a frozen V4-09 protocol.
// Paid trials without allowance are rejected. Live remains blocked in fixture scope.
func (s *Service) StartEvaluationTrial(t contract.EvaluationTrial) (contract.EvaluationTrial, error) {
	t.SchemaVersion = contract.EvaluationSchemaVersion
	t.LiveBlocked = true
	if t.RecordedAt == "" {
		t.RecordedAt = s.nowRFC3339()
	}
	if t.PaidTrial && (!t.BillingAuthorized || t.AllowanceRef == "") {
		return t, errors.New("paid trial requires authorized billing allowance")
	}
	if e := t.Validate(); e != nil {
		return t, e
	}
	// Confirm protocol freeze exists via instrument store.
	idb, e := s.ensureInstrumentStore()
	if e != nil {
		return t, e
	}
	proto, e := idb.GetProtocol(t.ProtocolID)
	_ = idb.Close()
	if e != nil {
		return t, e
	}
	if proto.CanonicalDigest != t.ProtocolDigest {
		return t, errors.New("trial protocol digest mismatch")
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return t, e
	}
	defer db.Close()
	if e = db.PutEvaluationTrial(t); e != nil {
		return t, e
	}
	return db.GetEvaluationTrial(t.ID)
}

// RecordEvalArmIdentity records actual identities and exposes confounds (R01).
// Structural without V4-10 stays pending (not fabricated zeros).
func (s *Service) RecordEvalArmIdentity(a contract.EvalArmIdentity, availablePackages map[string]bool, pinned map[string]string) (contract.EvalArmIdentity, error) {
	a.SchemaVersion = contract.EvaluationSchemaVersion
	if a.RecordedAt == "" {
		a.RecordedAt = s.nowRFC3339()
	}
	kind, e := contract.MapEvalRoleToInstrumentArm(a.Role)
	if e != nil {
		return a, e
	}
	a.InstrumentArmKind = kind
	a.ModelMismatch = a.RequestedModel != a.ObservedModel
	a.FabricatedMetrics = 0

	switch a.Role {
	case contract.EvalRoleStructural:
		if !availablePackages[contract.PackageV410] {
			a.Pending = true
			a.EligibilityStatus = contract.EligibilityPending
			a.EligibilityReason = "structural arm requires V4-10; pending not zero"
		} else {
			a.Pending = false
			a.EligibilityStatus = contract.EligibilityEligible
			a.EligibilityReason = "package_present"
		}
	case contract.EvalRoleV4FixedModel:
		if !availablePackages[contract.PackageV415] {
			a.Pending = true
			a.EligibilityStatus = contract.EligibilityPending
			a.EligibilityReason = "v4_fixed_model requires V4-15"
		} else {
			a.Pending = false
			a.EligibilityStatus = contract.EligibilityEligible
			a.EligibilityReason = "fixture_v4_fixed_model"
		}
	case contract.EvalRoleNative:
		if a.ControlIdentity != contract.NativeControlIdentity {
			a.EligibilityStatus = contract.EligibilityIneligible
			a.EligibilityReason = "native control identity mismatch"
			a.Pending = false
		} else {
			a.EligibilityStatus = contract.EligibilityEligible
			a.EligibilityReason = "fixture_authorized_native_control"
			a.Pending = false
		}
	case contract.EvalRoleOriginalV3:
		if a.ControlIdentity != contract.OriginalV3ControlSHA {
			a.EligibilityStatus = contract.EligibilityIneligible
			a.EligibilityReason = "original_v3 control identity mismatch"
			a.Pending = false
		} else {
			a.EligibilityStatus = contract.EligibilityEligible
			a.EligibilityReason = "fixture_authorized_original_v3"
			a.Pending = false
		}
	}

	a.Confounds = contract.DetectArmConfounds(a, pinned)
	if len(a.PinnedControls) == 0 && len(pinned) > 0 {
		keys := make([]string, 0, len(pinned))
		for k := range pinned {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		a.PinnedControls = keys
	}
	if e := a.Validate(); e != nil {
		return a, e
	}
	// Mirror eligibility into V4-09 instrument first — same bbolt file cannot be opened twice.
	el := contract.ArmEligibility{
		SchemaVersion:      contract.InstrumentSchemaVersion,
		ID:                 "elig-eval-" + a.ID,
		TrialID:            a.TrialID,
		ProtocolID:         a.ProtocolID,
		ArmID:              a.ArmID,
		ArmKind:            a.InstrumentArmKind,
		Status:             a.EligibilityStatus,
		Reason:             a.EligibilityReason,
		FabricatedAttempts: 0,
		RecordedAt:         a.RecordedAt,
	}
	if a.Pending && a.Role == contract.EvalRoleStructural {
		el.MissingPackage = contract.PackageV410
	}
	if a.Pending && a.Role == contract.EvalRoleV4FixedModel {
		el.MissingPackage = contract.PackageV415
	}
	_ = s.RecordEligibility(el)
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return a, e
	}
	defer db.Close()
	if e = db.PutEvalArmIdentity(a); e != nil {
		return a, e
	}
	arms, e := db.ListEvalArmIdentities(a.TrialID)
	if e != nil {
		return a, e
	}
	for _, existing := range arms {
		if existing.ID == a.ID {
			return existing, nil
		}
	}
	return a, nil
}

// RecordEvalAttempt stores an evaluation attempt and refuses pending-arm fabricated zeros.
func (s *Service) RecordEvalAttempt(a contract.EvalAttempt, armPending bool) (contract.EvalAttempt, error) {
	if armPending {
		return a, errors.New("pending arm must not record fabricated attempt metrics")
	}
	if a.StartedAt == "" {
		a.StartedAt = s.nowRFC3339()
	}
	if a.EndedAt == "" {
		a.EndedAt = s.nowRFC3339()
	}
	if e := a.Validate(); e != nil {
		return a, e
	}
	// Record through V4-09 shared recorder first — same bbolt file cannot be opened twice.
	if _, e := s.RecordAttempt(a.AttemptRecord); e != nil {
		return a, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return a, e
	}
	defer db.Close()
	if e = db.PutEvalAttempt(a); e != nil {
		return a, e
	}
	return a, nil
}

// ComputeEvalCost summarizes cost per accepted task with complete-cost gate (R02).
func (s *Service) ComputeEvalCost(protocolID string) (contract.EvalCostSummary, error) {
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return contract.EvalCostSummary{}, e
	}
	defer db.Close()
	attempts, e := db.ListEvalAttempts(protocolID)
	if e != nil {
		return contract.EvalCostSummary{}, e
	}
	return contract.SummarizeEvalCost(attempts)
}

// RecordHoldoutBoundary enforces isolation and labels tuning failures as development (R03).
func (s *Service) RecordHoldoutBoundary(h contract.HoldoutBoundary) (contract.HoldoutBoundary, error) {
	h.SchemaVersion = contract.EvaluationSchemaVersion
	if h.RecordedAt == "" {
		h.RecordedAt = s.nowRFC3339()
	}
	h.Split = contract.EvalSplitHoldout
	h.Isolated = !h.MakerMemoryAccessible && !h.ReferencePatchesVisible && !h.PriorArtifactsVisible && len(h.CanaryTriggered) == 0
	if h.TuningFailureMaterial != "" && h.Isolated {
		// Tuning failures observed during development stay development material even if holdout-isolated later.
		h.TuningFailureMaterial = contract.EvalSplitDevelopment + ":" + h.TuningFailureMaterial
	}
	if e := h.Validate(); e != nil {
		return h, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return h, e
	}
	defer db.Close()
	if e = db.PutHoldoutBoundary(h); e != nil {
		return h, e
	}
	return db.GetHoldoutBoundary(h.ID)
}

// ClassifyPlumbingEvidence marks gold-patch/simulated-host as plumbing, not model capability (R04).
func (s *Service) ClassifyPlumbingEvidence(p contract.PlumbingEvidence) (contract.PlumbingEvidence, error) {
	p.SchemaVersion = contract.EvaluationSchemaVersion
	if p.RecordedAt == "" {
		p.RecordedAt = s.nowRFC3339()
	}
	if p.UsesGoldPatch || p.UsesSimulatedHost {
		if p.EvidenceClass == "" || p.EvidenceClass == contract.EvidenceClassModelCapability {
			p.EvidenceClass = contract.EvidenceClassPlumbing
		}
		if p.Discriminator == "" {
			p.Discriminator = contract.EvidenceClassSmoke
		}
	}
	if p.Discriminator == contract.EvidenceClassLive {
		if !p.CredentialsUsable {
			p.LiveBlocked = true
			if p.BlockedReason == "" {
				p.BlockedReason = "credentials_unavailable"
			}
		}
	} else {
		// Smoke stays non-live.
		p.LiveBlocked = true
		if p.BlockedReason == "" {
			p.BlockedReason = "smoke_not_live"
		}
	}
	if p.CredentialsPresent && !p.CredentialsUsable {
		p.LiveBlocked = true
		if p.BlockedReason == "" {
			p.BlockedReason = "credential_presence_not_usability"
		}
	}
	if e := p.Validate(); e != nil {
		return p, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return p, e
	}
	defer db.Close()
	if e = db.PutPlumbingEvidence(p); e != nil {
		return p, e
	}
	return db.GetPlumbingEvidence(p.ID)
}

// PublishEvalReport records metrics with uncertainty and independent recomputation (R05).
func (s *Service) PublishEvalReport(m contract.EvalReportMetrics) (contract.EvalReportMetrics, error) {
	m.SchemaVersion = contract.EvaluationSchemaVersion
	if m.RecordedAt == "" {
		m.RecordedAt = s.nowRFC3339()
	}
	m.SmallSample = m.SampleSize > 0 && m.SampleSize < 10
	if m.Uncertainty == "" {
		if m.CensoredCount > 0 {
			m.Uncertainty = "censored_observations"
		} else if m.SmallSample {
			m.Uncertainty = "small_sample"
		} else {
			m.Uncertainty = "none_declared"
		}
	}
	digest, e := contract.RecomputeReportMetricsDigest(m)
	if e != nil {
		return m, e
	}
	m.RecomputationDigest = digest
	m.IndependentRecomputable = true
	if e := m.Validate(); e != nil {
		return m, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return m, e
	}
	defer db.Close()
	if e = db.PutEvalReportMetrics(m); e != nil {
		return m, e
	}
	out, e := db.GetEvalReportMetrics(m.ID)
	if e != nil {
		return m, e
	}
	// Independent recomputation must match stored digest.
	again, e := contract.RecomputeReportMetricsDigest(out)
	if e != nil || again != out.RecomputationDigest {
		return out, errors.New("independent recomputation digest mismatch")
	}
	return out, nil
}

// AdmitEvaluationTask records requirement/oracle/exclusion status (R06).
func (s *Service) AdmitEvaluationTask(t contract.TaskAdmission) (contract.TaskAdmission, error) {
	t.SchemaVersion = contract.EvaluationSchemaVersion
	if t.RecordedAt == "" {
		t.RecordedAt = s.nowRFC3339()
	}
	if t.PostOutcomeExclusion {
		if t.ExclusionStatus == "" {
			t.ExclusionStatus = contract.ExclusionPostOutcome
		}
		if len(t.AuditTrail) == 0 {
			t.AuditTrail = []string{"post_outcome_exclusion_recorded:" + t.RecordedAt}
		}
		if t.SensitivityResults == nil {
			t.SensitivityResults = map[string]string{"with_exclusion": "retained", "without_exclusion": "sensitivity_pending"}
		}
		t.Admitted = false
	}
	validAdmit := (t.RequirementStatus == contract.ReqValid || t.RequirementStatus == contract.ReqSufficient) &&
		t.OracleQualification == contract.OracleQualified && t.ExclusionStatus == contract.ExclusionNone
	if !t.PostOutcomeExclusion {
		t.Admitted = validAdmit
	}
	if e := t.Validate(); e != nil {
		return t, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return t, e
	}
	defer db.Close()
	if e = db.PutTaskAdmission(t); e != nil {
		return t, e
	}
	return db.GetTaskAdmission(t.ID)
}

// FlagEnvironmentDrift records material protocol drift as confounded (R07).
func (s *Service) FlagEnvironmentDrift(d contract.EnvironmentDrift) (contract.EnvironmentDrift, error) {
	d.SchemaVersion = contract.EvaluationSchemaVersion
	if d.RecordedAt == "" {
		d.RecordedAt = s.nowRFC3339()
	}
	d.DiffLabels = contract.CollectEnvironmentDiffLabels(d)
	d.Material = len(d.DiffLabels) > 0
	d.Confounded = d.Material
	if d.Material {
		d.HiddenInAverages = false
	}
	if e := d.Validate(); e != nil {
		return d, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return d, e
	}
	defer db.Close()
	if e = db.PutEnvironmentDrift(d); e != nil {
		return d, e
	}
	return db.GetEnvironmentDrift(d.ID)
}

// DistinguishOutcomes separates candidate/selection/autonomous/reliability claims (R08).
func (s *Service) DistinguishOutcomes(o contract.OutcomeDistinction) (contract.OutcomeDistinction, error) {
	o.SchemaVersion = contract.EvaluationSchemaVersion
	if o.RecordedAt == "" {
		o.RecordedAt = s.nowRFC3339()
	}
	if o.PassingPatchInCancel || o.SuccessAmongFailures {
		o.IdenticalClaim = false
		if o.OperationalOutcome == "" {
			if o.PassingPatchInCancel {
				o.OperationalOutcome = contract.OutcomeCancelledWithPass
			} else {
				o.OperationalOutcome = contract.OutcomeSearchAmongFailures
			}
		}
	} else if o.OperationalOutcome == "" {
		switch {
		case o.AutonomousComplete:
			o.OperationalOutcome = contract.OutcomeAutonomousCompletion
		case o.SelectionSuccess:
			o.OperationalOutcome = contract.OutcomeSelectionSuccess
		case o.CandidateSuccess:
			o.OperationalOutcome = contract.OutcomeCandidateSuccess
		case o.RepeatedReliability != nil:
			o.OperationalOutcome = contract.OutcomeRepeatedRunReliability
		default:
			o.OperationalOutcome = "none"
		}
	}
	if e := o.Validate(); e != nil {
		return o, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return o, e
	}
	defer db.Close()
	if e = db.PutOutcomeDistinction(o); e != nil {
		return o, e
	}
	return db.GetOutcomeDistinction(o.ID)
}

// UpdatePromotionSet removes tuning-influenced material and gates forward access (R09).
func (s *Service) UpdatePromotionSet(p contract.PromotionSet) (contract.PromotionSet, error) {
	p.SchemaVersion = contract.EvaluationSchemaVersion
	if p.RecordedAt == "" {
		p.RecordedAt = s.nowRFC3339()
	}
	// Move holdout-influenced and playbook-adjusted material out of untouched.
	influenced := map[string]bool{}
	for _, m := range p.InfluencedByHoldout {
		influenced[m] = true
	}
	for _, m := range p.PlaybookAdjustments {
		influenced[m] = true
	}
	kept := []string{}
	for _, u := range p.UntouchedMembers {
		if influenced[u] {
			p.RemovedMembers = appendUnique(p.RemovedMembers, u)
			p.DevelopmentMembers = appendUnique(p.DevelopmentMembers, u)
			continue
		}
		kept = append(kept, u)
	}
	p.UntouchedMembers = kept
	for _, adj := range p.PlaybookAdjustments {
		p.DevelopmentMembers = appendUnique(p.DevelopmentMembers, adj)
	}
	if p.CandidateFrozen {
		if p.ForwardStatus == "" {
			p.ForwardStatus = "accessible_after_freeze"
		}
		p.ForwardAccessible = true
	} else {
		p.ForwardAccessible = false
		p.ForwardStatus = contract.PromotionInaccessible
	}
	if e := p.Validate(); e != nil {
		return p, e
	}
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return p, e
	}
	defer db.Close()
	if e = db.PutPromotionSet(p); e != nil {
		return p, e
	}
	return db.GetPromotionSet(p.ID)
}

// EvaluationReport aggregates arm identities, cost, and pending arms for a trial.
type EvaluationReport struct {
	Trial          contract.EvaluationTrial     `json:"trial"`
	ArmIdentities  []contract.EvalArmIdentity   `json:"arm_identities"`
	Cost           contract.EvalCostSummary     `json:"cost,omitempty"`
	PendingArms    []string                     `json:"pending_arms"`
	LiveBlocked    bool                         `json:"live_blocked"`
	PaidAuthorized bool                         `json:"paid_authorized"`
	GeneratedAt    string                       `json:"generated_at"`
}

func (s *Service) EvaluationReport(trialID string) (EvaluationReport, error) {
	var report EvaluationReport
	db, e := s.ensureEvaluationStore()
	if e != nil {
		return report, e
	}
	defer db.Close()
	trial, e := db.GetEvaluationTrial(trialID)
	if e != nil {
		return report, e
	}
	arms, e := db.ListEvalArmIdentities(trialID)
	if e != nil {
		return report, e
	}
	pending := []string{}
	for _, a := range arms {
		if a.Pending {
			pending = append(pending, a.ArmID)
		}
	}
	cost, _ := contract.SummarizeEvalCost(mustListAttempts(db, trial.ProtocolID))
	report = EvaluationReport{
		Trial:          trial,
		ArmIdentities:  arms,
		Cost:           cost,
		PendingArms:    pending,
		LiveBlocked:    true,
		PaidAuthorized: trial.BillingAuthorized && trial.AllowanceRef != "",
		GeneratedAt:    s.opts.Clock().UTC().Format(time.RFC3339),
	}
	return report, nil
}

func mustListAttempts(db *store.Store, protocolID string) []contract.EvalAttempt {
	out, e := db.ListEvalAttempts(protocolID)
	if e != nil {
		return nil
	}
	return out
}

func appendUnique(list []string, v string) []string {
	for _, x := range list {
		if x == v {
			return list
		}
	}
	return append(list, v)
}
