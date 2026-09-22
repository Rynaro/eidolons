package contract

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"time"
)

// EvaluationSchemaVersion is the typed V4-21 evaluation namespace version under schema 2.
const EvaluationSchemaVersion = 1

// Evaluation comparison roles — extend V4-09 arms; do not replace them.
const (
	EvalRoleNative       = "native"
	EvalRoleOriginalV3   = "original_v3"
	EvalRoleV4FixedModel = "v4_fixed_model"
	EvalRoleStructural   = "structural"
)

// Task-split partitions stay separate (development / calibration / holdout / forward).
const (
	EvalSplitDevelopment  = "development"
	EvalSplitCalibration  = "calibration"
	EvalSplitHoldout      = "holdout"
	EvalSplitForward      = "forward"
	EvalSplitPromotion    = "promotion"
)

// Evidence classification for gold-patch / simulated-host runs (R04).
const (
	EvidenceClassPlumbing        = "plumbing"
	EvidenceClassModelCapability = "model_capability"
	EvidenceClassSmoke           = "smoke"
	EvidenceClassLive            = "live"
)

// Requirement / oracle / exclusion admission labels (R06).
const (
	ReqSufficient       = "sufficient"
	ReqUnderspecified   = "underspecified"
	ReqOverRestrictive  = "over_restrictive"
	ReqInadequateCover  = "inadequate_coverage"
	ReqValid            = "valid"

	OracleQualified   = "qualified"
	OracleUnqualified = "unqualified"
	OracleDefective   = "defective"

	ExclusionNone       = "none"
	ExclusionPreOutcome = "pre_outcome"
	ExclusionPostOutcome = "post_outcome"
	ExclusionDefectReview = "defect_review"
)

// Outcome distinctions for candidate search / reliability (R08).
const (
	OutcomeCandidateSuccess      = "candidate_success"
	OutcomeSelectionSuccess      = "selection_success"
	OutcomeAutonomousCompletion  = "autonomous_completion"
	OutcomeRepeatedRunReliability = "repeated_run_reliability"
	OutcomeCancelledWithPass     = "cancelled_run_passing_patch"
	OutcomeSearchAmongFailures   = "success_among_failed_candidates"
)

// Promotion / tuning influence (R09).
const (
	PromotionUntouched   = "untouched"
	PromotionDevelopment = "development"
	PromotionRemoved     = "removed_from_promotion"
	PromotionFrozen      = "candidate_frozen"
	PromotionInaccessible = "forward_inaccessible"
)

// EvalArmIdentity records actual model/harness/policy/environment/acceptance/billing (R01).
type EvalArmIdentity struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	TrialID             string            `json:"trial_id"`
	ProtocolID          string            `json:"protocol_id"`
	ProtocolDigest      string            `json:"protocol_digest"`
	ArmID               string            `json:"arm_id"`
	Role                string            `json:"role"`
	InstrumentArmKind   string            `json:"instrument_arm_kind"`
	RequestedModel      string            `json:"requested_model"`
	ObservedModel       string            `json:"observed_model"`
	HarnessIdentity     string            `json:"harness_identity"`
	PolicyIdentity      string            `json:"policy_identity"`
	EnvironmentIdentity string            `json:"environment_identity"`
	AcceptanceIdentity  string            `json:"acceptance_identity"`
	BillingIdentity     string            `json:"billing_identity"`
	ControlIdentity     string            `json:"control_identity"`
	PinnedControls      []string          `json:"pinned_controls"`
	ModelMismatch       bool              `json:"model_mismatch"`
	Confounds           []string          `json:"confounds,omitempty"`
	Split               string            `json:"split"`
	EligibilityStatus   string            `json:"eligibility_status"`
	EligibilityReason   string            `json:"eligibility_reason"`
	Pending             bool              `json:"pending"`
	FabricatedMetrics   int               `json:"fabricated_metrics"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (a EvalArmIdentity) Validate() error {
	if a.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown evaluation arm identity schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"arm_identity", a.ID}, {"trial", a.TrialID}, {"protocol", a.ProtocolID},
		{"protocol_digest", a.ProtocolDigest}, {"arm", a.ArmID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch a.Role {
	case EvalRoleNative, EvalRoleOriginalV3, EvalRoleV4FixedModel, EvalRoleStructural:
	default:
		return errors.New("unknown evaluation role")
	}
	if a.InstrumentArmKind == "" || a.RequestedModel == "" || a.ObservedModel == "" ||
		a.HarnessIdentity == "" || a.PolicyIdentity == "" || a.EnvironmentIdentity == "" ||
		a.AcceptanceIdentity == "" || a.BillingIdentity == "" || a.ControlIdentity == "" {
		return errors.New("evaluation arm identities incomplete")
	}
	if a.Role == EvalRoleOriginalV3 && a.ControlIdentity != OriginalV3ControlSHA {
		return errors.New("original_v3 evaluation arm must pin exact control SHA")
	}
	if a.Role == EvalRoleNative && a.ControlIdentity != NativeControlIdentity {
		return errors.New("native evaluation arm must use untouched native control identity")
	}
	switch a.Split {
	case EvalSplitDevelopment, EvalSplitCalibration, EvalSplitHoldout, EvalSplitForward, EvalSplitPromotion:
	default:
		return errors.New("unknown evaluation split")
	}
	if a.FabricatedMetrics != 0 {
		return errors.New("evaluation arm must never fabricate metrics")
	}
	if a.EligibilityStatus == "" || a.EligibilityReason == "" || a.RecordedAt == "" {
		return errors.New("eligibility status/reason and recorded_at required")
	}
	expectedMismatch := a.RequestedModel != a.ObservedModel
	if a.ModelMismatch != expectedMismatch {
		return errors.New("model_mismatch must reflect requested versus observed")
	}
	if e := ValidateMetadata(a.Metadata); e != nil {
		return e
	}
	return nil
}

// MapEvalRoleToInstrumentArm maps V4-21 comparison roles onto V4-09 arm kinds.
func MapEvalRoleToInstrumentArm(role string) (string, error) {
	switch role {
	case EvalRoleNative:
		return ArmNative, nil
	case EvalRoleOriginalV3:
		return ArmOriginalV3, nil
	case EvalRoleV4FixedModel:
		return ArmManaged, nil
	case EvalRoleStructural:
		return ArmStructural, nil
	default:
		return "", errors.New("unknown evaluation role")
	}
}

// EvalAttempt extends V4-09 attempts with checking/timeout/abandon exposure for cost (R02).
type EvalAttempt struct {
	AttemptRecord
	CheckingCostKind   string   `json:"checking_cost_kind,omitempty"`
	CheckingCostAmount *float64 `json:"checking_cost_amount,omitempty"`
	Timeout            bool     `json:"timeout"`
	Abandoned          bool     `json:"abandoned"`
	Cancelled          bool     `json:"cancelled"`
	ZeroAcceptance     bool     `json:"zero_acceptance"`
	ExposureKnown      bool     `json:"exposure_known"`
	Split              string   `json:"split"`
}

func (a EvalAttempt) Validate() error {
	if e := a.AttemptRecord.Validate(); e != nil {
		return e
	}
	switch a.Split {
	case EvalSplitDevelopment, EvalSplitCalibration, EvalSplitHoldout, EvalSplitForward, EvalSplitPromotion, "":
	default:
		return errors.New("unknown evaluation attempt split")
	}
	if a.CheckingCostKind != "" {
		switch a.CheckingCostKind {
		case CostKnown, CostEstimated, CostUnknown:
		default:
			return errors.New("unknown checking cost kind")
		}
		if a.CheckingCostKind == CostKnown {
			if a.CheckingCostAmount == nil || math.IsNaN(*a.CheckingCostAmount) || math.IsInf(*a.CheckingCostAmount, 0) {
				return errors.New("known checking cost must be finite")
			}
		}
		if a.CheckingCostKind == CostUnknown && a.CheckingCostAmount != nil {
			return errors.New("unknown checking cost must omit amount")
		}
	}
	return nil
}

// EvalCostSummary reuses K/Z/U/W patterns and blocks complete-cost claims on unknown exposure (R02).
type EvalCostSummary struct {
	AttemptSummary
	CheckingSubtotal       float64  `json:"checking_subtotal"`
	TimeoutCount           int      `json:"timeout_count"`
	AbandonedCount         int      `json:"abandoned_count"`
	CancelledCount         int      `json:"cancelled_count"`
	ZeroAcceptanceCount    int      `json:"zero_acceptance_count"`
	CompleteCostClaim      bool     `json:"complete_cost_claim"`
	CompleteCostBlockedBy  []string `json:"complete_cost_blocked_by,omitempty"`
	UndefinedRatioNotZero  bool     `json:"undefined_ratio_not_zero"`
}

// SummarizeEvalCost includes all attempted tasks; undefined ratio is never reported as zero.
func SummarizeEvalCost(attempts []EvalAttempt) (EvalCostSummary, error) {
	var out EvalCostSummary
	if len(attempts) == 0 {
		return out, errors.New("no evaluation attempts")
	}
	base := make([]AttemptRecord, 0, len(attempts))
	var checking float64
	checkingUnknown := false
	exposureUnknown := false
	for _, a := range attempts {
		if e := a.Validate(); e != nil {
			return out, e
		}
		base = append(base, a.AttemptRecord)
		if a.Timeout {
			out.TimeoutCount++
		}
		if a.Abandoned || a.TerminalState == TerminalAbandoned {
			out.AbandonedCount++
		}
		if a.Cancelled || a.TerminalState == TerminalCancelled {
			out.CancelledCount++
		}
		if a.ZeroAcceptance || a.Acceptance == AcceptanceNone {
			out.ZeroAcceptanceCount++
		}
		if !a.ExposureKnown {
			exposureUnknown = true
		}
		switch a.CheckingCostKind {
		case CostKnown:
			if a.CheckingCostAmount != nil {
				checking += *a.CheckingCostAmount
			}
		case CostEstimated, CostUnknown:
			checkingUnknown = true
		}
	}
	sum, e := SummarizeAttempts(base)
	if e != nil {
		return out, e
	}
	out.AttemptSummary = sum
	out.CheckingSubtotal = checking
	if sum.RatioDefined && sum.CostPerAccepted != nil && !checkingUnknown {
		adjusted := *sum.CostPerAccepted + checking/float64(sum.AcceptedDistinctRoots)
		out.CostPerAccepted = &adjusted
	}
	if !sum.RatioDefined {
		out.UndefinedRatioNotZero = true
		if sum.CostPerAccepted != nil && *sum.CostPerAccepted == 0 {
			return out, errors.New("undefined ratio must not be zero")
		}
	}
	blocked := []string{}
	if sum.TotalUnknown || sum.RatioUnknown {
		blocked = append(blocked, "unknown_attempt_cost")
	}
	if checkingUnknown {
		blocked = append(blocked, "unknown_checking_cost")
	}
	if exposureUnknown {
		blocked = append(blocked, "unknown_exposure")
	}
	if !sum.RatioDefined {
		blocked = append(blocked, "undefined_ratio")
	}
	out.CompleteCostBlockedBy = blocked
	out.CompleteCostClaim = len(blocked) == 0 && sum.RatioDefined && sum.KnownCompleteKnown
	return out, nil
}

// HoldoutBoundary isolates holdout answers from maker memory / patches / prior artifacts (R03).
type HoldoutBoundary struct {
	SchemaVersion          int      `json:"schema_version"`
	ID                     string   `json:"id"`
	TrialID                string   `json:"trial_id"`
	TaskID                 string   `json:"task_id"`
	Split                  string   `json:"split"`
	MakerMemoryAccessible  bool     `json:"maker_memory_accessible"`
	ReferencePatchesVisible bool    `json:"reference_patches_visible"`
	PriorArtifactsVisible  bool     `json:"prior_artifacts_visible"`
	LeakageCanaries        []string `json:"leakage_canaries"`
	CanaryTriggered        []string `json:"canary_triggered,omitempty"`
	Isolated               bool     `json:"isolated"`
	TuningFailureMaterial  string   `json:"tuning_failure_material,omitempty"`
	RecordedAt             string   `json:"recorded_at"`
}

func (h HoldoutBoundary) Validate() error {
	if h.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown holdout boundary schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"holdout", h.ID}, {"trial", h.TrialID}, {"task", h.TaskID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if h.Split != EvalSplitHoldout {
		return errors.New("holdout boundary requires holdout split")
	}
	if len(h.LeakageCanaries) == 0 {
		return errors.New("leakage canaries required")
	}
	isolated := !h.MakerMemoryAccessible && !h.ReferencePatchesVisible && !h.PriorArtifactsVisible && len(h.CanaryTriggered) == 0
	if h.Isolated != isolated {
		return errors.New("isolated flag must match accessibility and canary state")
	}
	if h.RecordedAt == "" {
		return errors.New("holdout recorded_at required")
	}
	return nil
}

// PlumbingEvidence classifies gold-patch / simulated-host runs (R04).
type PlumbingEvidence struct {
	SchemaVersion      int    `json:"schema_version"`
	ID                 string `json:"id"`
	TrialID            string `json:"trial_id"`
	RunID              string `json:"run_id"`
	UsesGoldPatch      bool   `json:"uses_gold_patch"`
	UsesSimulatedHost  bool   `json:"uses_simulated_host"`
	EvidenceClass      string `json:"evidence_class"`
	Discriminator      string `json:"discriminator"` // smoke | live
	CredentialsPresent bool   `json:"credentials_present"`
	CredentialsUsable  bool   `json:"credentials_usable"`
	LiveBlocked        bool   `json:"live_blocked"`
	BlockedReason      string `json:"blocked_reason,omitempty"`
	RecordedAt         string `json:"recorded_at"`
}

func (p PlumbingEvidence) Validate() error {
	if p.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown plumbing evidence schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"plumbing", p.ID}, {"trial", p.TrialID}, {"run", p.RunID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch p.EvidenceClass {
	case EvidenceClassPlumbing, EvidenceClassModelCapability, EvidenceClassSmoke, EvidenceClassLive:
	default:
		return errors.New("unknown evidence class")
	}
	if (p.UsesGoldPatch || p.UsesSimulatedHost) && p.EvidenceClass != EvidenceClassPlumbing && p.EvidenceClass != EvidenceClassSmoke {
		return errors.New("gold patch or simulated host must be plumbing or smoke evidence")
	}
	switch p.Discriminator {
	case EvidenceClassSmoke, EvidenceClassLive:
	default:
		return errors.New("discriminator must be smoke or live")
	}
	if p.Discriminator == EvidenceClassLive && (!p.CredentialsUsable || p.LiveBlocked) {
		// live claim blocked when credentials unavailable
		if !p.LiveBlocked {
			return errors.New("unavailable credentials must keep live blocked")
		}
	}
	if p.CredentialsPresent && !p.CredentialsUsable && !p.LiveBlocked {
		return errors.New("credential presence without usability must keep live blocked")
	}
	if p.RecordedAt == "" {
		return errors.New("plumbing recorded_at required")
	}
	return nil
}

// EvalReportMetrics covers completion/latency/interventions/quality with uncertainty (R05).
type EvalReportMetrics struct {
	SchemaVersion           int      `json:"schema_version"`
	ID                      string   `json:"id"`
	TrialID                 string   `json:"trial_id"`
	ProtocolID              string   `json:"protocol_id"`
	CompletionRate          *float64 `json:"completion_rate,omitempty"`
	RunnableLatencyMS       *float64 `json:"runnable_latency_ms,omitempty"`
	TotalLatencyMS          *float64 `json:"total_latency_ms,omitempty"`
	Interventions           int      `json:"interventions"`
	InvalidAcceptance       int      `json:"invalid_acceptance"`
	QualityReviewPass       *float64 `json:"quality_review_pass,omitempty"`
	Uncertainty             string   `json:"uncertainty"`
	SampleSize              int      `json:"sample_size"`
	CensoredCount           int      `json:"censored_count"`
	SmallSample             bool     `json:"small_sample"`
	DelayedReworkWindow     string   `json:"delayed_rework_window"`
	IndependentRecomputable bool     `json:"independent_recomputation"`
	RecomputationDigest     string   `json:"recomputation_digest,omitempty"`
	RecordedAt              string   `json:"recorded_at"`
}

func (m EvalReportMetrics) Validate() error {
	if m.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown report metrics schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"report", m.ID}, {"trial", m.TrialID}, {"protocol", m.ProtocolID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if m.Uncertainty == "" || m.DelayedReworkWindow == "" || m.RecordedAt == "" {
		return errors.New("uncertainty, delayed_rework_window, and recorded_at required")
	}
	if m.SampleSize < 0 || m.CensoredCount < 0 || m.CensoredCount > m.SampleSize {
		return errors.New("invalid sample/censored counts")
	}
	expectedSmall := m.SampleSize > 0 && m.SampleSize < 10
	if m.SmallSample != expectedSmall {
		return errors.New("small_sample must reflect sample_size < 10")
	}
	if m.IndependentRecomputable && m.RecomputationDigest == "" {
		return errors.New("independent recomputation requires digest")
	}
	return nil
}

// RecomputeReportMetricsDigest is the independent known-data recomputation surface (R05).
func RecomputeReportMetricsDigest(m EvalReportMetrics) (string, error) {
	payload := struct {
		Completion      *float64 `json:"completion_rate"`
		Runnable        *float64 `json:"runnable_latency_ms"`
		Total           *float64 `json:"total_latency_ms"`
		Interventions   int      `json:"interventions"`
		InvalidAccept   int      `json:"invalid_acceptance"`
		Quality         *float64 `json:"quality_review_pass"`
		SampleSize      int      `json:"sample_size"`
		Censored        int      `json:"censored_count"`
		DelayedRework   string   `json:"delayed_rework_window"`
	}{
		m.CompletionRate, m.RunnableLatencyMS, m.TotalLatencyMS, m.Interventions,
		m.InvalidAcceptance, m.QualityReviewPass, m.SampleSize, m.CensoredCount, m.DelayedReworkWindow,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return "", e
	}
	return Digest(raw), nil
}

// TaskAdmission records requirement sufficiency / oracle / exclusion status (R06).
type TaskAdmission struct {
	SchemaVersion          int               `json:"schema_version"`
	ID                     string            `json:"id"`
	TrialID                string            `json:"trial_id"`
	TaskID                 string            `json:"task_id"`
	RequirementStatus      string            `json:"requirement_status"`
	OracleQualification    string            `json:"oracle_qualification"`
	ExclusionStatus        string            `json:"exclusion_status"`
	ExclusionReason        string            `json:"exclusion_reason,omitempty"`
	PostOutcomeExclusion   bool              `json:"post_outcome_exclusion"`
	AuditTrail             []string          `json:"audit_trail"`
	SensitivityResults     map[string]string `json:"sensitivity_results,omitempty"`
	Admitted               bool              `json:"admitted"`
	RecordedAt             string            `json:"recorded_at"`
}

func (t TaskAdmission) Validate() error {
	if t.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown task admission schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"admission", t.ID}, {"trial", t.TrialID}, {"task", t.TaskID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch t.RequirementStatus {
	case ReqSufficient, ReqUnderspecified, ReqOverRestrictive, ReqInadequateCover, ReqValid:
	default:
		return errors.New("unknown requirement status")
	}
	switch t.OracleQualification {
	case OracleQualified, OracleUnqualified, OracleDefective:
	default:
		return errors.New("unknown oracle qualification")
	}
	switch t.ExclusionStatus {
	case ExclusionNone, ExclusionPreOutcome, ExclusionPostOutcome, ExclusionDefectReview:
	default:
		return errors.New("unknown exclusion status")
	}
	if t.PostOutcomeExclusion {
		if t.ExclusionStatus != ExclusionPostOutcome && t.ExclusionStatus != ExclusionDefectReview {
			return errors.New("post-outcome exclusion requires matching status")
		}
		if len(t.AuditTrail) == 0 {
			return errors.New("post-outcome exclusion requires audit trail")
		}
		if len(t.SensitivityResults) == 0 {
			return errors.New("post-outcome exclusion requires sensitivity results")
		}
	}
	validAdmit := t.RequirementStatus == ReqValid || t.RequirementStatus == ReqSufficient
	if t.Admitted && (!validAdmit || t.OracleQualification != OracleQualified || t.ExclusionStatus != ExclusionNone) {
		return errors.New("admitted tasks require valid/sufficient requirements, qualified oracle, no exclusion")
	}
	if t.RecordedAt == "" {
		return errors.New("admission recorded_at required")
	}
	return nil
}

// EnvironmentDrift flags material env/permission differences from frozen protocol (R07).
type EnvironmentDrift struct {
	SchemaVersion      int      `json:"schema_version"`
	ID                 string   `json:"id"`
	TrialID            string   `json:"trial_id"`
	ProtocolID         string   `json:"protocol_id"`
	ArmID              string   `json:"arm_id"`
	ResourceGuarantee  string   `json:"resource_guarantee_diff,omitempty"`
	CeilingDiff        string   `json:"ceiling_diff,omitempty"`
	NetworkDiff        string   `json:"network_diff,omitempty"`
	CacheDiff          string   `json:"cache_diff,omitempty"`
	TimeoutDiff        string   `json:"timeout_diff,omitempty"`
	SandboxDiff        string   `json:"sandbox_diff,omitempty"`
	PermissionDiff     string   `json:"permission_diff,omitempty"`
	Material           bool     `json:"material"`
	Confounded         bool     `json:"confounded"`
	HiddenInAverages   bool     `json:"hidden_in_averages"`
	DiffLabels         []string `json:"diff_labels,omitempty"`
	RecordedAt         string   `json:"recorded_at"`
}

func (d EnvironmentDrift) Validate() error {
	if d.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown environment drift schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"drift", d.ID}, {"trial", d.TrialID}, {"protocol", d.ProtocolID}, {"arm", d.ArmID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if d.Material != d.Confounded {
		return errors.New("material drift must set confounded")
	}
	if d.Material && d.HiddenInAverages {
		return errors.New("material drift must not be hidden in pooled averages")
	}
	if d.Material && len(d.DiffLabels) == 0 {
		return errors.New("material drift requires diff labels")
	}
	if d.RecordedAt == "" {
		return errors.New("drift recorded_at required")
	}
	return nil
}

// OutcomeDistinction separates candidate/selection/autonomous/reliability outcomes (R08).
type OutcomeDistinction struct {
	SchemaVersion       int    `json:"schema_version"`
	ID                  string `json:"id"`
	TrialID             string `json:"trial_id"`
	RunID               string `json:"run_id"`
	CandidateSuccess    bool   `json:"candidate_success"`
	SelectionSuccess    bool   `json:"selection_success"`
	AutonomousComplete  bool   `json:"autonomous_completion"`
	RepeatedReliability *float64 `json:"repeated_run_reliability,omitempty"`
	PassingPatchInCancel bool  `json:"passing_patch_in_cancelled_run"`
	SuccessAmongFailures bool  `json:"success_among_failed_candidates"`
	OperationalOutcome  string `json:"operational_outcome"`
	IdenticalClaim      bool   `json:"identical_operational_claim"`
	RecordedAt          string `json:"recorded_at"`
}

func (o OutcomeDistinction) Validate() error {
	if o.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown outcome distinction schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"outcome", o.ID}, {"trial", o.TrialID}, {"run", o.RunID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if o.OperationalOutcome == "" || o.RecordedAt == "" {
		return errors.New("operational_outcome and recorded_at required")
	}
	// Passing patch in cancelled run / success among failures are not identical operational outcomes.
	if (o.PassingPatchInCancel || o.SuccessAmongFailures) && o.IdenticalClaim {
		return errors.New("cancelled-pass or search-success must not claim identical operational outcome")
	}
	return nil
}

// PromotionSet tracks untouched promotion material and forward inaccessibility (R09).
type PromotionSet struct {
	SchemaVersion           int      `json:"schema_version"`
	ID                      string   `json:"id"`
	TrialID                 string   `json:"trial_id"`
	CandidateID             string   `json:"candidate_id"`
	UntouchedMembers        []string `json:"untouched_members"`
	RemovedMembers          []string `json:"removed_members"`
	DevelopmentMembers      []string `json:"development_members"`
	InfluencedByHoldout     []string `json:"influenced_by_holdout,omitempty"`
	PlaybookAdjustments     []string `json:"playbook_adjustments,omitempty"`
	CandidateFrozen         bool     `json:"candidate_frozen"`
	ForwardAccessible       bool     `json:"forward_accessible"`
	ForwardStatus           string   `json:"forward_status"`
	RecordedAt              string   `json:"recorded_at"`
}

func (p PromotionSet) Validate() error {
	if p.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown promotion set schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"promotion", p.ID}, {"trial", p.TrialID}, {"candidate", p.CandidateID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	// Material that influenced tuning must not remain in untouched set.
	removed := map[string]bool{}
	for _, m := range p.RemovedMembers {
		removed[m] = true
	}
	dev := map[string]bool{}
	for _, m := range p.DevelopmentMembers {
		dev[m] = true
	}
	for _, m := range p.InfluencedByHoldout {
		if !removed[m] && !dev[m] {
			return errors.New("holdout-influenced material must be removed or labeled development")
		}
		for _, u := range p.UntouchedMembers {
			if u == m {
				return errors.New("holdout-influenced material must not remain in untouched promotion set")
			}
		}
	}
	if len(p.PlaybookAdjustments) > 0 {
		for _, adj := range p.PlaybookAdjustments {
			if !dev[adj] && !removed[adj] {
				return errors.New("playbook/route adjustment from holdout must become development evidence")
			}
		}
	}
	if p.CandidateFrozen {
		if p.ForwardStatus != PromotionFrozen && p.ForwardStatus != "accessible_after_freeze" {
			return errors.New("frozen candidate requires frozen/accessible forward status")
		}
	} else {
		if p.ForwardAccessible {
			return errors.New("forward set must remain inaccessible until candidate is frozen")
		}
		if p.ForwardStatus != PromotionInaccessible {
			return errors.New("unfrozen candidate requires forward_inaccessible status")
		}
	}
	if p.RecordedAt == "" {
		return errors.New("promotion recorded_at required")
	}
	return nil
}

// EvaluationTrial is the top-level auditable evaluation record.
type EvaluationTrial struct {
	SchemaVersion     int               `json:"schema_version"`
	ID                string            `json:"id"`
	ProtocolID        string            `json:"protocol_id"`
	ProtocolDigest    string            `json:"protocol_digest"`
	BillingAuthorized bool              `json:"billing_authorized"`
	AllowanceRef      string            `json:"allowance_ref,omitempty"`
	PaidTrial         bool              `json:"paid_trial"`
	LiveBlocked       bool              `json:"live_blocked"`
	ArmIDs            []string          `json:"arm_ids"`
	PendingArms       []string          `json:"pending_arms,omitempty"`
	SplitsPresent     []string          `json:"splits_present"`
	Metadata          map[string]string `json:"metadata,omitempty"`
	RecordedAt        string            `json:"recorded_at"`
}

func (t EvaluationTrial) Validate() error {
	if t.SchemaVersion != EvaluationSchemaVersion {
		return errors.New("unknown evaluation trial schema version")
	}
	if e := validateID("trial", t.ID, true); e != nil {
		return e
	}
	if e := validateID("protocol", t.ProtocolID, true); e != nil {
		return e
	}
	if t.ProtocolDigest == "" || t.RecordedAt == "" {
		return errors.New("protocol digest and recorded_at required")
	}
	if t.PaidTrial && (!t.BillingAuthorized || t.AllowanceRef == "") {
		return errors.New("paid trial requires authorized billing and allowance ref")
	}
	if !t.LiveBlocked {
		return errors.New("V4-21 fixture scope keeps live blocked")
	}
	if len(t.ArmIDs) == 0 {
		return errors.New("trial requires arm ids")
	}
	if e := ValidateMetadata(t.Metadata); e != nil {
		return e
	}
	return nil
}

// DetectArmConfounds exposes requested/observed and pin mismatches (R01).
func DetectArmConfounds(a EvalArmIdentity, pinned map[string]string) []string {
	var confounds []string
	if a.ModelMismatch {
		confounds = append(confounds, "requested_vs_observed_model")
	}
	for key, want := range pinned {
		var got string
		switch key {
		case "harness":
			got = a.HarnessIdentity
		case "policy":
			got = a.PolicyIdentity
		case "environment":
			got = a.EnvironmentIdentity
		case "acceptance":
			got = a.AcceptanceIdentity
		case "billing":
			got = a.BillingIdentity
		case "control":
			got = a.ControlIdentity
		case "model":
			got = a.ObservedModel
		default:
			continue
		}
		if got != want {
			confounds = append(confounds, "pin_mismatch:"+key)
		}
	}
	sort.Strings(confounds)
	return confounds
}

// CollectEnvironmentDiffLabels lists material resource/permission diffs (R07).
func CollectEnvironmentDiffLabels(d EnvironmentDrift) []string {
	var labels []string
	add := func(label, v string) {
		if v != "" {
			labels = append(labels, label)
		}
	}
	add("resource", d.ResourceGuarantee)
	add("ceiling", d.CeilingDiff)
	add("network", d.NetworkDiff)
	add("cache", d.CacheDiff)
	add("timeout", d.TimeoutDiff)
	add("sandbox", d.SandboxDiff)
	add("permission", d.PermissionDiff)
	sort.Strings(labels)
	return labels
}

func DecodeEvalArmIdentity(raw []byte) (EvalArmIdentity, error) {
	var a EvalArmIdentity
	if e := StrictJSON(raw, &a); e != nil {
		return a, e
	}
	return a, a.Validate()
}

func DecodeEvaluationTrial(raw []byte) (EvaluationTrial, error) {
	var t EvaluationTrial
	if e := StrictJSON(raw, &t); e != nil {
		return t, e
	}
	return t, t.Validate()
}

func DecodeHoldoutBoundary(raw []byte) (HoldoutBoundary, error) {
	var h HoldoutBoundary
	if e := StrictJSON(raw, &h); e != nil {
		return h, e
	}
	return h, h.Validate()
}

func DecodePlumbingEvidence(raw []byte) (PlumbingEvidence, error) {
	var p PlumbingEvidence
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeTaskAdmission(raw []byte) (TaskAdmission, error) {
	var t TaskAdmission
	if e := StrictJSON(raw, &t); e != nil {
		return t, e
	}
	return t, t.Validate()
}

func DecodePromotionSet(raw []byte) (PromotionSet, error) {
	var p PromotionSet
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeOutcomeDistinction(raw []byte) (OutcomeDistinction, error) {
	var o OutcomeDistinction
	if e := StrictJSON(raw, &o); e != nil {
		return o, e
	}
	return o, o.Validate()
}

func DecodeEvalReportMetrics(raw []byte) (EvalReportMetrics, error) {
	var m EvalReportMetrics
	if e := StrictJSON(raw, &m); e != nil {
		return m, e
	}
	return m, m.Validate()
}

// ParseRFC3339 is a tiny helper for evaluation timestamps.
func ParseRFC3339(s string) error {
	if s == "" {
		return errors.New("timestamp required")
	}
	_, e := time.Parse(time.RFC3339, s)
	if e != nil {
		return fmt.Errorf("invalid timestamp: %w", e)
	}
	return nil
}
