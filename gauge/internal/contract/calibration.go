package contract

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
)

// CalibrationSchemaVersion is the typed V4-22 calibration namespace version under schema 2.
const CalibrationSchemaVersion = 1

// Mechanism IDs ablated one at a time (workflow-ablations + routing-calibration).
const (
	MechLeanPlanning          = "lean_planning"
	MechMakerContinuity       = "maker_continuity"
	MechMethodFusionIsolation = "method_fusion_isolation"
	MechContextToolEconomy    = "context_tool_economy"
	MechParallelism           = "parallelism"
	MechModelEffortRouting    = "model_effort_routing"
	MechStructural            = "structural_consolidation"
)

// Package prerequisites for mechanism eligibility (plan.yaml conditional_mechanism_prerequisites).
const (
	PackageV416 = "V4-16"
	PackageV417 = "V4-17"
	PackageV418 = "V4-18"
	PackageV419 = "V4-19"
)

// Promotion / verdict labels (R04). Null/inconclusive never flips a default.
const (
	CalVerdictSupported    = "supported_benefit"
	CalVerdictNoWin        = "no_win"
	CalVerdictInconclusive = "inconclusive"
	CalVerdictRegression   = "quality_regression"
	CalVerdictIncomplete   = "incomplete_cost"
	CalVerdictNull         = "null_result"
)

const (
	CalPromotionUnpromoted = "unpromoted"
	CalPromotionPromoted   = "promoted"
	CalPromotionRolledBack = "rolled_back"
)

// Trial stop reasons (R05).
const (
	CalStopNone               = "none"
	CalStopOverspend          = "overspend"
	CalStopUnknownExposure    = "unknown_exposure"
	CalStopAuthorityViolation = "authority_violation"
	CalStopLateUsage          = "late_usage"
	CalStopSafetyBoundary     = "safety_boundary"
)

// Experience quality for adaptation proposals (R07).
const (
	ExpQualified   = "qualified"
	ExpFailed      = "failed"
	ExpStale       = "stale"
	ExpSelfAttested = "self_attested"
)

// Generalization labels (R08).
const (
	GenSameBatchAdaptation = "same_batch_adaptation"
	GenForwardQualified    = "forward_qualified"
	GenNotGeneralized      = "not_generalized"
)

// Offline proposal surface (R10) — fixture isolation only; never production self-mod.
const (
	OfflineSurfaceSkillConfig = "skill_configuration"
	OfflineSurfaceForbidden   = "forbidden_protected"
)

// MechanismPrerequisite returns the package gate for a mechanism, or "" if always fixture-eligible.
func MechanismPrerequisite(mechanism string) string {
	switch mechanism {
	case MechLeanPlanning:
		return PackageV416
	case MechMakerContinuity:
		return PackageV417
	case MechMethodFusionIsolation:
		return PackageV418
	case MechContextToolEconomy:
		return PackageV419
	case MechStructural:
		return PackageV410
	case MechParallelism, MechModelEffortRouting:
		return ""
	default:
		return ""
	}
}

func knownMechanism(m string) bool {
	switch m {
	case MechLeanPlanning, MechMakerContinuity, MechMethodFusionIsolation,
		MechContextToolEconomy, MechParallelism, MechModelEffortRouting, MechStructural:
		return true
	}
	return false
}

// CalibrationArm is one ablation arm under a fixed acceptance/authority baseline (R01).
type CalibrationArm struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	TrialID            string            `json:"trial_id"`
	MechanismID        string            `json:"mechanism_id"`
	ArmLabel           string            `json:"arm_label"`
	OracleDigest       string            `json:"oracle_digest"`
	PermissionDigest   string            `json:"permission_digest"`
	AcceptanceDigest   string            `json:"acceptance_digest"`
	AuthorityDigest    string            `json:"authority_digest"`
	ManifestDigest     string            `json:"manifest_digest"`
	WeakerAcceptance   bool              `json:"weaker_acceptance"`
	EligibilityStatus  string            `json:"eligibility_status"`
	EligibilityReason  string            `json:"eligibility_reason"`
	Pending            bool              `json:"pending"`
	FabricatedMetrics  int               `json:"fabricated_metrics"`
	MissingPackage     string            `json:"missing_package,omitempty"`
	Metadata           map[string]string `json:"metadata,omitempty"`
	RecordedAt         string            `json:"recorded_at"`
}

func (a CalibrationArm) Validate() error {
	if a.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown calibration arm schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"arm", a.ID}, {"trial", a.TrialID}, {"mechanism", a.MechanismID},
		{"oracle_digest", a.OracleDigest}, {"permission_digest", a.PermissionDigest},
		{"acceptance_digest", a.AcceptanceDigest}, {"authority_digest", a.AuthorityDigest},
		{"manifest_digest", a.ManifestDigest},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if !knownMechanism(a.MechanismID) {
		return errors.New("unknown calibration mechanism")
	}
	if a.ArmLabel == "" || a.EligibilityStatus == "" || a.EligibilityReason == "" || a.RecordedAt == "" {
		return errors.New("calibration arm fields incomplete")
	}
	if a.FabricatedMetrics != 0 {
		return errors.New("calibration arm must never fabricate metrics")
	}
	switch a.EligibilityStatus {
	case EligibilityEligible, EligibilityIneligible, EligibilityPending:
	default:
		return errors.New("unknown calibration eligibility status")
	}
	if a.WeakerAcceptance && a.EligibilityStatus == EligibilityEligible {
		return errors.New("weaker acceptance cannot remain eligible for improvement claim")
	}
	return ValidateMetadata(a.Metadata)
}

// ResolveMechanismEligibility marks missing prerequisite packages pending/ineligible, not zeros.
func ResolveMechanismEligibility(mechanism string, available map[string]bool) (pending bool, status, reason, missing string) {
	pkg := MechanismPrerequisite(mechanism)
	if pkg == "" {
		return false, EligibilityEligible, "fixture_mechanism_available", ""
	}
	if available[pkg] {
		return false, EligibilityEligible, "package_present:" + pkg, ""
	}
	return true, EligibilityPending, "mechanism requires " + pkg + "; pending not zero", pkg
}

// CalibrationBaseline holds mandatory acceptance/authority constants across arms (R01).
type CalibrationBaseline struct {
	SchemaVersion    int               `json:"schema_version"`
	ID               string            `json:"id"`
	TrialID          string            `json:"trial_id"`
	MechanismID      string            `json:"mechanism_id"`
	OracleDigest     string            `json:"oracle_digest"`
	PermissionDigest string            `json:"permission_digest"`
	AcceptanceDigest string            `json:"acceptance_digest"`
	AuthorityDigest  string            `json:"authority_digest"`
	ManifestDigest   string            `json:"manifest_digest"`
	ArmIDs           []string          `json:"arm_ids"`
	Invalidated      bool              `json:"invalidated"`
	InvalidReason    string            `json:"invalid_reason,omitempty"`
	Metadata         map[string]string `json:"metadata,omitempty"`
	RecordedAt       string            `json:"recorded_at"`
}

func (b CalibrationBaseline) Validate() error {
	if b.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown calibration baseline schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"baseline", b.ID}, {"trial", b.TrialID}, {"mechanism", b.MechanismID},
		{"oracle_digest", b.OracleDigest}, {"permission_digest", b.PermissionDigest},
		{"acceptance_digest", b.AcceptanceDigest}, {"authority_digest", b.AuthorityDigest},
		{"manifest_digest", b.ManifestDigest},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if !knownMechanism(b.MechanismID) || b.RecordedAt == "" {
		return errors.New("calibration baseline incomplete")
	}
	if b.Invalidated && b.InvalidReason == "" {
		return errors.New("invalidated baseline requires reason")
	}
	return ValidateMetadata(b.Metadata)
}

// CheckArmAgainstBaseline returns whether the arm weakens acceptance/authority (R01/T01).
func CheckArmAgainstBaseline(b CalibrationBaseline, a CalibrationArm) (ok bool, reason string) {
	if a.OracleDigest != b.OracleDigest || a.PermissionDigest != b.PermissionDigest ||
		a.AcceptanceDigest != b.AcceptanceDigest || a.AuthorityDigest != b.AuthorityDigest ||
		a.ManifestDigest != b.ManifestDigest {
		return false, "oracle/permission/acceptance/authority/manifest digest mismatch"
	}
	if a.WeakerAcceptance {
		return false, "weaker_acceptance_invalidates_improvement"
	}
	return true, "constant"
}

// CalibrationBatch records development/calibration data use and freeze chronology (R02).
type CalibrationBatch struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	TrialID             string            `json:"trial_id"`
	Split               string            `json:"split"`
	ParameterSetID      string            `json:"parameter_set_id"`
	FrozenAt            string            `json:"frozen_at,omitempty"`
	HoldoutAccessedAt   string            `json:"holdout_accessed_at,omitempty"`
	ForwardAccessedAt   string            `json:"forward_accessed_at,omitempty"`
	HoldoutDrivenTuning bool              `json:"holdout_driven_tuning"`
	MemoryControlsOK    bool              `json:"memory_controls_ok"`
	Rejected            bool              `json:"rejected"`
	RejectReason        string            `json:"reject_reason,omitempty"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (b CalibrationBatch) Validate() error {
	if b.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown calibration batch schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"batch", b.ID}, {"trial", b.TrialID}, {"parameter_set", b.ParameterSetID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch b.Split {
	case EvalSplitDevelopment, EvalSplitCalibration, EvalSplitHoldout, EvalSplitForward:
	default:
		return errors.New("unknown calibration batch split")
	}
	if b.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	if b.HoldoutDrivenTuning && !b.Rejected {
		return errors.New("holdout-driven tuning must be rejected")
	}
	if b.Rejected && b.RejectReason == "" {
		return errors.New("rejected batch requires reason")
	}
	return ValidateMetadata(b.Metadata)
}

// FreezeBeforeHoldoutOK enforces freeze-before-holdout chronology (R02/T02).
func FreezeBeforeHoldoutOK(b CalibrationBatch) (ok bool, reason string) {
	if b.HoldoutDrivenTuning {
		return false, "holdout_driven_tuning_prohibited"
	}
	if b.Split == EvalSplitDevelopment || b.Split == EvalSplitCalibration {
		if b.HoldoutAccessedAt != "" && (b.FrozenAt == "" || b.HoldoutAccessedAt < b.FrozenAt) {
			return false, "holdout_accessed_before_freeze"
		}
		return true, "dev_calibration_ok"
	}
	if b.Split == EvalSplitHoldout || b.Split == EvalSplitForward {
		if b.FrozenAt == "" {
			return false, "parameters_must_freeze_before_holdout_forward"
		}
		if b.HoldoutAccessedAt != "" && b.HoldoutAccessedAt < b.FrozenAt {
			return false, "holdout_before_freeze"
		}
		if b.ForwardAccessedAt != "" && b.ForwardAccessedAt < b.FrozenAt {
			return false, "forward_before_freeze"
		}
	}
	return true, "chronology_ok"
}

// MechanismCostReport identifies the isolated mechanism and full coordination costs (R03).
type MechanismCostReport struct {
	SchemaVersion         int               `json:"schema_version"`
	ID                    string            `json:"id"`
	TrialID               string            `json:"trial_id"`
	MechanismID           string            `json:"mechanism_id"`
	ClaimBenefit          bool              `json:"claim_benefit"`
	CoordinationCost      *float64          `json:"coordination_cost"`
	ReconstructionCost    *float64          `json:"reconstruction_cost"`
	IntegrationCheckerCost *float64         `json:"integration_checker_cost"`
	RebuildCost           *float64          `json:"rebuild_cost"`
	WarmFresh             string            `json:"warm_fresh,omitempty"`
	StrongFirstEscalation string            `json:"strong_first_escalation,omitempty"`
	ParallelCandidates    bool              `json:"parallel_candidates"`
	CostsComplete         bool              `json:"costs_complete"`
	IncompleteReason      string            `json:"incomplete_reason,omitempty"`
	Metadata              map[string]string `json:"metadata,omitempty"`
	RecordedAt            string            `json:"recorded_at"`
}

func (r MechanismCostReport) Validate() error {
	if r.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown mechanism cost report schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"report", r.ID}, {"trial", r.TrialID}, {"mechanism", r.MechanismID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if !knownMechanism(r.MechanismID) || r.RecordedAt == "" {
		return errors.New("mechanism cost report incomplete")
	}
	if r.ClaimBenefit && !r.CostsComplete {
		return errors.New("benefit claim requires complete coordination and reconstruction costs")
	}
	if r.ClaimBenefit {
		if r.CoordinationCost == nil || r.ReconstructionCost == nil ||
			r.IntegrationCheckerCost == nil || r.RebuildCost == nil {
			return errors.New("benefit claim missing required cost fields")
		}
	}
	return ValidateMetadata(r.Metadata)
}

// CompleteMechanismCosts marks whether warm/fresh, escalation, and parallel costs are present (R03/T03).
func CompleteMechanismCosts(r *MechanismCostReport) {
	if r.CoordinationCost != nil && r.ReconstructionCost != nil &&
		r.IntegrationCheckerCost != nil && r.RebuildCost != nil {
		r.CostsComplete = true
		r.IncompleteReason = ""
		return
	}
	r.CostsComplete = false
	r.IncompleteReason = "missing_coordination_or_reconstruction_costs"
	if r.ClaimBenefit {
		r.ClaimBenefit = false
	}
}

// PromotionDecision records no-win / inconclusive / regression outcomes without default flip (R04).
type PromotionDecision struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	TrialID            string            `json:"trial_id"`
	MechanismID        string            `json:"mechanism_id"`
	Verdict            string            `json:"verdict"`
	PromotionStatus    string            `json:"promotion_status"`
	CherryPickedWinner bool              `json:"cherry_picked_winner"`
	DefaultFlip        bool              `json:"default_flip"`
	OracleChangedAfter bool              `json:"oracle_changed_after_outcome"`
	Rejected           bool              `json:"rejected"`
	RejectReason       string            `json:"reject_reason,omitempty"`
	Metadata           map[string]string `json:"metadata,omitempty"`
	RecordedAt         string            `json:"recorded_at"`
}

func (d PromotionDecision) Validate() error {
	if d.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown promotion decision schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"decision", d.ID}, {"trial", d.TrialID}, {"mechanism", d.MechanismID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch d.Verdict {
	case CalVerdictSupported, CalVerdictNoWin, CalVerdictInconclusive, CalVerdictRegression, CalVerdictIncomplete, CalVerdictNull:
	default:
		return errors.New("unknown promotion verdict")
	}
	switch d.PromotionStatus {
	case CalPromotionUnpromoted, CalPromotionPromoted, CalPromotionRolledBack:
	default:
		return errors.New("unknown promotion status")
	}
	if d.DefaultFlip {
		return errors.New("null/inconclusive must never flip a default")
	}
	if d.OracleChangedAfter {
		return errors.New("oracle/margin changes after outcomes are forbidden")
	}
	if d.CherryPickedWinner && !d.Rejected {
		return errors.New("cherry-picked winner summary is forbidden")
	}
	if d.Verdict != CalVerdictSupported && d.PromotionStatus == CalPromotionPromoted {
		return errors.New("unsupported verdict cannot promote")
	}
	if d.Rejected && d.RejectReason == "" {
		return errors.New("rejected promotion requires reason")
	}
	if d.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(d.Metadata)
}

// ApplyPromotionGate leaves unsupported mechanisms unpromoted (R04/T04).
func ApplyPromotionGate(d *PromotionDecision) {
	d.DefaultFlip = false
	d.OracleChangedAfter = false
	if d.CherryPickedWinner {
		d.Rejected = true
		d.RejectReason = "cherry_picked_winner_forbidden"
		d.PromotionStatus = CalPromotionUnpromoted
		return
	}
	switch d.Verdict {
	case CalVerdictSupported:
		if d.PromotionStatus == "" {
			d.PromotionStatus = CalPromotionPromoted
		}
	case CalVerdictNoWin, CalVerdictInconclusive, CalVerdictRegression, CalVerdictIncomplete, CalVerdictNull:
		d.PromotionStatus = CalPromotionUnpromoted
		d.Rejected = false
		if d.RejectReason == "" {
			d.RejectReason = "verdict:" + d.Verdict
		}
	}
}

// TrialBoundaryStop stops further dispatch at resource/safety boundaries (R05).
type TrialBoundaryStop struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	TrialID             string            `json:"trial_id"`
	StopReason          string            `json:"stop_reason"`
	Stopped             bool              `json:"stopped"`
	FurtherDispatchOK   bool              `json:"further_dispatch_ok"`
	SelfAuthorizedOverage bool            `json:"self_authorized_overage"`
	PartialDataRetained bool              `json:"partial_data_retained"`
	ExposureKnown       bool              `json:"exposure_known"`
	AuthorizedBudget    *float64          `json:"authorized_budget,omitempty"`
	ObservedSpend       *float64          `json:"observed_spend,omitempty"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (t TrialBoundaryStop) Validate() error {
	if t.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown trial boundary schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"boundary", t.ID}, {"trial", t.TrialID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch t.StopReason {
	case CalStopNone, CalStopOverspend, CalStopUnknownExposure, CalStopAuthorityViolation, CalStopLateUsage, CalStopSafetyBoundary:
	default:
		return errors.New("unknown trial stop reason")
	}
	if t.SelfAuthorizedOverage {
		return errors.New("self-authorized overage is forbidden")
	}
	if t.Stopped && t.FurtherDispatchOK {
		return errors.New("stopped trial cannot allow further dispatch")
	}
	if t.Stopped && !t.PartialDataRetained {
		return errors.New("stopped trial must retain partial data")
	}
	if t.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(t.Metadata)
}

// EvaluateTrialBoundary decides stop for overspend/unknown/authority/late usage (R05/T05).
func EvaluateTrialBoundary(t *TrialBoundaryStop) {
	t.SelfAuthorizedOverage = false
	switch t.StopReason {
	case CalStopOverspend, CalStopUnknownExposure, CalStopAuthorityViolation, CalStopLateUsage, CalStopSafetyBoundary:
		t.Stopped = true
		t.FurtherDispatchOK = false
		t.PartialDataRetained = true
	case CalStopNone:
		t.Stopped = false
		t.FurtherDispatchOK = true
	}
	if !t.ExposureKnown && t.StopReason == CalStopNone {
		t.StopReason = CalStopUnknownExposure
		t.Stopped = true
		t.FurtherDispatchOK = false
		t.PartialDataRetained = true
	}
	if t.AuthorizedBudget != nil && t.ObservedSpend != nil && *t.ObservedSpend > *t.AuthorizedBudget {
		t.StopReason = CalStopOverspend
		t.Stopped = true
		t.FurtherDispatchOK = false
		t.PartialDataRetained = true
	}
}

// StrategyDecision binds selected action to state, alternatives, policy, reason (R06).
type StrategyDecision struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	TrialID            string            `json:"trial_id"`
	PromptDigest       string            `json:"prompt_digest"`
	ObservedState      string            `json:"observed_state"`
	StateSource        string            `json:"state_source"` // observation | estimate
	SelectedAction     string            `json:"selected_action"`
	AllowedAlternatives []string         `json:"allowed_alternatives"`
	PolicyVersion      string            `json:"policy_version"`
	DecisionReason     string            `json:"decision_reason"`
	HiddenReasoning    bool              `json:"hidden_reasoning"`
	FixedPolicyControl bool              `json:"fixed_policy_control"`
	RegisteredOnly     bool              `json:"registered_only"`
	Rejected           bool              `json:"rejected"`
	RejectReason       string            `json:"reject_reason,omitempty"`
	Metadata           map[string]string `json:"metadata,omitempty"`
	RecordedAt         string            `json:"recorded_at"`
}

func (d StrategyDecision) Validate() error {
	if d.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown strategy decision schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"decision", d.ID}, {"trial", d.TrialID}, {"prompt", d.PromptDigest},
		{"policy_version", d.PolicyVersion},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if d.ObservedState == "" || d.SelectedAction == "" || d.DecisionReason == "" || d.RecordedAt == "" {
		return errors.New("strategy decision incomplete")
	}
	switch d.StateSource {
	case "observation", "estimate":
	default:
		return errors.New("state_source must be observation or estimate")
	}
	if d.HiddenReasoning {
		return errors.New("hidden reasoning is forbidden")
	}
	if !d.RegisteredOnly {
		return errors.New("strategy decisions may select only registered strategies")
	}
	if len(d.AllowedAlternatives) == 0 {
		return errors.New("allowed alternatives required")
	}
	found := false
	for _, a := range d.AllowedAlternatives {
		if a == d.SelectedAction {
			found = true
			break
		}
	}
	if !found {
		return errors.New("selected action must be in allowed alternatives")
	}
	if d.Rejected && d.RejectReason == "" {
		return errors.New("rejected decision requires reason")
	}
	return ValidateMetadata(d.Metadata)
}

// AdaptationRecord versions experience-derived method changes (R07).
type AdaptationRecord struct {
	SchemaVersion   int               `json:"schema_version"`
	ID              string            `json:"id"`
	TrialID         string            `json:"trial_id"`
	ParentVersion   string            `json:"parent_version"`
	ProposedVersion string            `json:"proposed_version"`
	RollbackTarget  string            `json:"rollback_target"`
	EvidenceSources []string          `json:"evidence_sources"`
	AllowedScope    string            `json:"allowed_scope"`
	ExperienceQuality string          `json:"experience_quality"`
	ImmutableDiff   string            `json:"immutable_diff"`
	ActiveRule      bool              `json:"active_rule"`
	Rejected        bool              `json:"rejected"`
	RejectReason    string            `json:"reject_reason,omitempty"`
	Metadata        map[string]string `json:"metadata,omitempty"`
	RecordedAt      string            `json:"recorded_at"`
}

func (a AdaptationRecord) Validate() error {
	if a.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown adaptation record schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"adaptation", a.ID}, {"trial", a.TrialID}, {"parent", a.ParentVersion},
		{"proposed", a.ProposedVersion}, {"rollback", a.RollbackTarget},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if len(a.EvidenceSources) == 0 || a.AllowedScope == "" || a.ImmutableDiff == "" || a.RecordedAt == "" {
		return errors.New("adaptation record incomplete")
	}
	switch a.ExperienceQuality {
	case ExpQualified, ExpFailed, ExpStale, ExpSelfAttested:
	default:
		return errors.New("unknown experience quality")
	}
	if a.ExperienceQuality != ExpQualified && a.ActiveRule {
		return errors.New("failed/stale/self-attested experience cannot become an active rule")
	}
	if a.Rejected && a.RejectReason == "" {
		return errors.New("rejected adaptation requires reason")
	}
	return ValidateMetadata(a.Metadata)
}

// GateAdaptationExperience blocks silent activation of bad experience (R07/T07).
func GateAdaptationExperience(a *AdaptationRecord) {
	if a.ExperienceQuality != ExpQualified {
		a.ActiveRule = false
		a.Rejected = true
		if a.RejectReason == "" {
			a.RejectReason = "experience_quality:" + a.ExperienceQuality
		}
	}
}

// GeneralizationReport separates same-batch adaptation from forward transfer (R08).
type GeneralizationReport struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	TrialID             string            `json:"trial_id"`
	CandidateID         string            `json:"candidate_id"`
	AdaptedOnBatchID    string            `json:"adapted_on_batch_id"`
	SameBatchImproved   bool              `json:"same_batch_improved"`
	Label               string            `json:"label"`
	ForwardTaskIDs      []string          `json:"forward_task_ids"`
	ComputeMatchedControl bool            `json:"compute_matched_control"`
	CandidateFrozen     bool              `json:"candidate_frozen"`
	MeasuredScope       string            `json:"measured_scope"`
	ClaimsGeneralization bool             `json:"claims_generalization"`
	Rejected            bool              `json:"rejected"`
	RejectReason        string            `json:"reject_reason,omitempty"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (g GeneralizationReport) Validate() error {
	if g.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown generalization report schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"report", g.ID}, {"trial", g.TrialID}, {"candidate", g.CandidateID},
		{"batch", g.AdaptedOnBatchID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch g.Label {
	case GenSameBatchAdaptation, GenForwardQualified, GenNotGeneralized:
	default:
		return errors.New("unknown generalization label")
	}
	if g.SameBatchImproved && g.ClaimsGeneralization &&
		(g.Label != GenForwardQualified || !g.CandidateFrozen || !g.ComputeMatchedControl || len(g.ForwardTaskIDs) == 0) {
		return errors.New("same-batch improvement cannot claim generalization without forward evidence")
	}
	if g.ClaimsGeneralization && (g.Label != GenForwardQualified || !g.CandidateFrozen || !g.ComputeMatchedControl || len(g.ForwardTaskIDs) == 0) {
		return errors.New("generalization requires frozen candidate, forward tasks, and compute-matched control")
	}
	if g.RecordedAt == "" || g.MeasuredScope == "" {
		return errors.New("generalization report incomplete")
	}
	if g.Rejected && g.RejectReason == "" {
		return errors.New("rejected generalization requires reason")
	}
	return ValidateMetadata(g.Metadata)
}

// LabelGeneralization applies R08/T08 rules.
func LabelGeneralization(g *GeneralizationReport) {
	if g.SameBatchImproved && !g.CandidateFrozen {
		g.Label = GenSameBatchAdaptation
		g.ClaimsGeneralization = false
		return
	}
	if g.CandidateFrozen && g.ComputeMatchedControl && len(g.ForwardTaskIDs) > 0 {
		g.Label = GenForwardQualified
		g.ClaimsGeneralization = true
		if g.MeasuredScope == "" {
			g.MeasuredScope = "forward_tasks_measured"
		}
		return
	}
	g.Label = GenNotGeneralized
	g.ClaimsGeneralization = false
}

// PromotedStrategyRegistry binds supported model/harness/task scope and revalidation (R09).
type PromotedStrategyRegistry struct {
	SchemaVersion         int               `json:"schema_version"`
	ID                    string            `json:"id"`
	TrialID               string            `json:"trial_id"`
	StrategyVersion       string            `json:"strategy_version"`
	SupportedModel        string            `json:"supported_model"`
	SupportedHarness      string            `json:"supported_harness"`
	TaskScope             string            `json:"task_scope"`
	RevalidationConditions []string         `json:"revalidation_conditions"`
	BenefitClaimValid     bool              `json:"benefit_claim_valid"`
	InvalidationReason    string            `json:"invalidation_reason,omitempty"`
	PinnedConfigID        string            `json:"pinned_config_id"`
	Metadata              map[string]string `json:"metadata,omitempty"`
	RecordedAt            string            `json:"recorded_at"`
}

func (p PromotedStrategyRegistry) Validate() error {
	if p.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown promoted strategy schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"registry", p.ID}, {"trial", p.TrialID}, {"strategy", p.StrategyVersion},
		{"model", p.SupportedModel}, {"harness", p.SupportedHarness},
		{"task_scope", p.TaskScope}, {"pinned_config", p.PinnedConfigID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if len(p.RevalidationConditions) == 0 || p.RecordedAt == "" {
		return errors.New("promoted strategy incomplete")
	}
	return ValidateMetadata(p.Metadata)
}

// InvalidateOnDistributionChange clears benefit claims when model/harness/task-distribution changes (R09/T09).
func InvalidateOnDistributionChange(p *PromotedStrategyRegistry, observedModel, observedHarness, observedTaskScope string) {
	reasons := []string{}
	if observedModel != "" && observedModel != p.SupportedModel {
		reasons = append(reasons, "model_changed")
	}
	if observedHarness != "" && observedHarness != p.SupportedHarness {
		reasons = append(reasons, "harness_changed")
	}
	if observedTaskScope != "" && observedTaskScope != p.TaskScope {
		reasons = append(reasons, "task_distribution_changed")
	}
	if len(reasons) > 0 {
		p.BenefitClaimValid = false
		sort.Strings(reasons)
		p.InvalidationReason = fmt.Sprintf("%v", reasons)
	}
}

// OfflineAdaptationBoundary isolates proposals from active policy/production/oracle (R10).
type OfflineAdaptationBoundary struct {
	SchemaVersion          int               `json:"schema_version"`
	ID                     string            `json:"id"`
	TrialID                string            `json:"trial_id"`
	ExperimentEnabled      bool              `json:"experiment_enabled"`
	EditSurface            string            `json:"edit_surface"`
	TargetsActivePolicy    bool              `json:"targets_active_policy"`
	TargetsPermissionGate  bool              `json:"targets_permission_gate"`
	TargetsOracle          bool              `json:"targets_oracle"`
	TargetsLiveController  bool              `json:"targets_live_controller"`
	SandboxOnly            bool              `json:"sandbox_only"`
	SelfApprovedPromotion  bool              `json:"self_approved_promotion"`
	OperatorApprovalRef    string            `json:"operator_approval_ref,omitempty"`
	Rejected               bool              `json:"rejected"`
	RejectReason           string            `json:"reject_reason,omitempty"`
	Metadata               map[string]string `json:"metadata,omitempty"`
	RecordedAt             string            `json:"recorded_at"`
}

func (o OfflineAdaptationBoundary) Validate() error {
	if o.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown offline adaptation boundary schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"boundary", o.ID}, {"trial", o.TrialID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if o.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	if !o.ExperimentEnabled {
		// Feature absent path — still a valid recorded boundary (WHERE clause).
		return ValidateMetadata(o.Metadata)
	}
	switch o.EditSurface {
	case OfflineSurfaceSkillConfig, OfflineSurfaceForbidden:
	default:
		return errors.New("unknown offline edit surface")
	}
	if o.SelfApprovedPromotion {
		return errors.New("self-approved promotion is forbidden")
	}
	if (o.TargetsActivePolicy || o.TargetsPermissionGate || o.TargetsOracle || o.TargetsLiveController) && !o.Rejected {
		return errors.New("protected-target proposal must be rejected")
	}
	if o.EditSurface == OfflineSurfaceSkillConfig && !o.SandboxOnly {
		return errors.New("allowed skill/configuration proposal must remain sandbox-only")
	}
	if o.Rejected && o.RejectReason == "" {
		return errors.New("rejected offline proposal requires reason")
	}
	return ValidateMetadata(o.Metadata)
}

// EnforceOfflineIsolation applies R10/T10 gates without enabling production self-mod.
func EnforceOfflineIsolation(o *OfflineAdaptationBoundary) {
	o.SelfApprovedPromotion = false
	if !o.ExperimentEnabled {
		return
	}
	if o.TargetsActivePolicy || o.TargetsPermissionGate || o.TargetsOracle || o.TargetsLiveController {
		o.Rejected = true
		o.EditSurface = OfflineSurfaceForbidden
		o.SandboxOnly = true
		if o.RejectReason == "" {
			o.RejectReason = "protected_surface_isolated"
		}
		return
	}
	if o.EditSurface == OfflineSurfaceSkillConfig {
		o.SandboxOnly = true
		o.Rejected = false
	}
}

// CalibrationTrial is the top-level auditable calibration record extending V4-21 evaluation.
type CalibrationTrial struct {
	SchemaVersion     int               `json:"schema_version"`
	ID                string            `json:"id"`
	EvaluationTrialID string            `json:"evaluation_trial_id"`
	ProtocolID        string            `json:"protocol_id"`
	ProtocolDigest    string            `json:"protocol_digest"`
	MechanismIDs      []string          `json:"mechanism_ids"`
	Slices            []string          `json:"slices"`
	LiveBlocked       bool              `json:"live_blocked"`
	PaidTrial         bool              `json:"paid_trial"`
	BillingAuthorized bool              `json:"billing_authorized"`
	AllowanceRef      string            `json:"allowance_ref,omitempty"`
	Metadata          map[string]string `json:"metadata,omitempty"`
	RecordedAt        string            `json:"recorded_at"`
}

func (t CalibrationTrial) Validate() error {
	if t.SchemaVersion != CalibrationSchemaVersion {
		return errors.New("unknown calibration trial schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"trial", t.ID}, {"evaluation_trial", t.EvaluationTrialID},
		{"protocol", t.ProtocolID}, {"protocol_digest", t.ProtocolDigest},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if len(t.MechanismIDs) == 0 || t.RecordedAt == "" {
		return errors.New("calibration trial incomplete")
	}
	for _, m := range t.MechanismIDs {
		if !knownMechanism(m) {
			return fmt.Errorf("unknown mechanism %q", m)
		}
	}
	if t.PaidTrial && (!t.BillingAuthorized || t.AllowanceRef == "") {
		return errors.New("paid calibration trial requires authorized billing allowance")
	}
	if !t.LiveBlocked {
		return errors.New("calibration live must remain blocked in fixture scope")
	}
	return ValidateMetadata(t.Metadata)
}

// Decode helpers.

func DecodeCalibrationTrial(raw []byte) (CalibrationTrial, error) {
	var t CalibrationTrial
	if e := StrictJSON(raw, &t); e != nil {
		return t, e
	}
	return t, t.Validate()
}

func DecodeCalibrationArm(raw []byte) (CalibrationArm, error) {
	var a CalibrationArm
	if e := StrictJSON(raw, &a); e != nil {
		return a, e
	}
	return a, a.Validate()
}

func DecodeCalibrationBaseline(raw []byte) (CalibrationBaseline, error) {
	var b CalibrationBaseline
	if e := StrictJSON(raw, &b); e != nil {
		return b, e
	}
	return b, b.Validate()
}

func DecodeCalibrationBatch(raw []byte) (CalibrationBatch, error) {
	var b CalibrationBatch
	if e := StrictJSON(raw, &b); e != nil {
		return b, e
	}
	return b, b.Validate()
}

func DecodeMechanismCostReport(raw []byte) (MechanismCostReport, error) {
	var r MechanismCostReport
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodePromotionDecision(raw []byte) (PromotionDecision, error) {
	var d PromotionDecision
	if e := StrictJSON(raw, &d); e != nil {
		return d, e
	}
	return d, d.Validate()
}

func DecodeTrialBoundaryStop(raw []byte) (TrialBoundaryStop, error) {
	var t TrialBoundaryStop
	if e := StrictJSON(raw, &t); e != nil {
		return t, e
	}
	return t, t.Validate()
}

func DecodeStrategyDecision(raw []byte) (StrategyDecision, error) {
	var d StrategyDecision
	if e := StrictJSON(raw, &d); e != nil {
		return d, e
	}
	return d, d.Validate()
}

func DecodeAdaptationRecord(raw []byte) (AdaptationRecord, error) {
	var a AdaptationRecord
	if e := StrictJSON(raw, &a); e != nil {
		return a, e
	}
	return a, a.Validate()
}

func DecodeGeneralizationReport(raw []byte) (GeneralizationReport, error) {
	var g GeneralizationReport
	if e := StrictJSON(raw, &g); e != nil {
		return g, e
	}
	return g, g.Validate()
}

func DecodePromotedStrategyRegistry(raw []byte) (PromotedStrategyRegistry, error) {
	var p PromotedStrategyRegistry
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeOfflineAdaptationBoundary(raw []byte) (OfflineAdaptationBoundary, error) {
	var o OfflineAdaptationBoundary
	if e := StrictJSON(raw, &o); e != nil {
		return o, e
	}
	return o, o.Validate()
}

// Ensure unused import hygiene for encoding/json in helpers that only use StrictJSON.
var _ = json.Marshal
