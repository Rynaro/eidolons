package contract

import (
	"errors"
	"fmt"
)

// RamzaSchemaVersion is the typed V4-16 RAMZA method-contract namespace under schema 2.
const RamzaSchemaVersion = 1

// RamzaMethodContractID is the versioned consumer contract for Gauge-hosted RAMZA methods.
const RamzaMethodContractID = "gauge-ramza@1"

// Canonical sibling owner until accepted V4-10 relocation.
const RamzaCanonicalSourceOwner = "Rynaro/Ramza"

// Versioned method profiles — lite is amended; full/legacy preserve prior controls.
const (
	RamzaMethodLiteV2   = "ramza-lite@2"
	RamzaMethodFullV1   = "ramza-full@1"
	RamzaMethodLegacyV1 = "ramza-legacy@1"
)

// Planning modes.
const (
	RamzaModeLite   = "lite"
	RamzaModeFull   = "full"
	RamzaModeLegacy = "legacy"
)

// Unresolved decision kinds that can block implementation readiness (R02).
const (
	DecisionBehavior  = "behavior"
	DecisionAuthority = "authority"
	DecisionProduct   = "product"
	DecisionSecurity  = "security"
	DecisionMigration = "migration"
)

// Assumption statuses (R07).
const (
	AssumptionUnresolved    = "unresolved"
	AssumptionUserConfirmed = "user_confirmed"
)

// Rubric presentation labels (R04) — uncalibrated scores are heuristics, never probabilities.
const (
	RubricLabelHeuristic = "heuristic"
	RubricLabelCalibrated = "calibrated"
)

// HeuristicLifecycle captures activation / retirement bookkeeping (R06).
const (
	HeuristicStateInactive          = "inactive"
	HeuristicStateActive            = "active"
	HeuristicStateReevaluationQueued = "reevaluation_queued"
	HeuristicStateRetired           = "retired"
)

// ProducerArtifactSource records whether producer bytes came from the sibling or a fixture.
const (
	ProducerSourceSibling = "rynaro_ramza_checkout"
	ProducerSourceFixture = "fixture_simulated"
)

// UnresolvedDecision is information that changes required behavior or authority (R02).
type UnresolvedDecision struct {
	ID              string `json:"id"`
	Kind            string `json:"kind"`
	Detail          string `json:"detail"`
	AffectsBehavior bool   `json:"affects_behavior"`
	AffectsAuthority bool  `json:"affects_authority"`
	BlocksReady     bool   `json:"blocks_ready"`
}

func (d UnresolvedDecision) Validate() error {
	if e := validateID("unresolved_decision", d.ID, true); e != nil {
		return e
	}
	switch d.Kind {
	case DecisionBehavior, DecisionAuthority, DecisionProduct, DecisionSecurity, DecisionMigration:
	default:
		return fmt.Errorf("unknown unresolved decision kind %q", d.Kind)
	}
	if d.Detail == "" {
		return errors.New("unresolved decision detail required")
	}
	if (d.AffectsBehavior || d.AffectsAuthority) && !d.BlocksReady {
		return errors.New("behavior/authority unresolved decisions must block ready")
	}
	return nil
}

// SettledDecision is carried producer→consumer without forcing a duplicate search (R03).
type SettledDecision struct {
	ID                     string   `json:"id"`
	Choice                 string   `json:"choice"`
	InvalidationConditions []string `json:"invalidation_conditions"`
	EvidenceFingerprint    string   `json:"evidence_fingerprint"`
	Reopened               bool     `json:"reopened"`
	ReopenReason           string   `json:"reopen_reason,omitempty"`
	DuplicateSearchRequired bool    `json:"duplicate_search_required"`
}

func (d SettledDecision) Validate() error {
	if e := validateID("settled_decision", d.ID, true); e != nil {
		return e
	}
	if d.Choice == "" {
		return errors.New("settled decision choice required")
	}
	if len(d.InvalidationConditions) == 0 {
		return errors.New("settled decision requires invalidation conditions")
	}
	if d.EvidenceFingerprint == "" {
		return errors.New("settled decision evidence fingerprint required")
	}
	if !d.Reopened && d.DuplicateSearchRequired {
		return errors.New("settled decision must not require duplicate search")
	}
	if d.Reopened && d.ReopenReason == "" {
		return errors.New("reopened decision requires reopen reason")
	}
	return nil
}

// RubricScore presentation — score of 85 is neither 85% probability nor verification (R04).
type RubricScore struct {
	SchemaVersion           int      `json:"schema_version"`
	ID                      string   `json:"id"`
	Rubric                  string   `json:"rubric"`
	Score                   float64  `json:"score"`
	Label                   string   `json:"label"`
	IsProbability           bool     `json:"is_probability"`
	ProbabilityPercent      *float64 `json:"probability_percent,omitempty"`
	IndependentVerification bool     `json:"independent_verification"`
	Calibrated              bool     `json:"calibrated"`
	Detail                  string   `json:"detail,omitempty"`
}

func (r RubricScore) Validate() error {
	if r.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown rubric score schema version")
	}
	if e := validateID("rubric_score", r.ID, true); e != nil {
		return e
	}
	if r.Rubric == "" {
		return errors.New("rubric name required")
	}
	switch r.Label {
	case RubricLabelHeuristic, RubricLabelCalibrated:
	default:
		return fmt.Errorf("unknown rubric label %q", r.Label)
	}
	if !r.Calibrated && r.Label != RubricLabelHeuristic {
		return errors.New("uncalibrated rubric scores must be labeled heuristic")
	}
	if r.IsProbability {
		return errors.New("rubric scores must never be presented as probabilities")
	}
	if r.ProbabilityPercent != nil {
		return errors.New("probability_percent must be absent for rubric heuristics")
	}
	if r.IndependentVerification {
		return errors.New("uncalibrated rubric score is not independent verification")
	}
	return nil
}

// HeuristicPublication records activation, scope, and retirement (R06).
type HeuristicPublication struct {
	SchemaVersion            int      `json:"schema_version"`
	ID                       string   `json:"id"`
	Name                     string   `json:"name"`
	ActivationConditions     []string `json:"activation_conditions"`
	SupportedConfigScope     []string `json:"supported_configuration_scope"`
	RetirementTrigger        string   `json:"retirement_trigger"`
	State                    string   `json:"state"`
	Activated                bool     `json:"activated"`
	TaskMatched              bool     `json:"task_matched"`
	ModelOrHarnessChanged    bool     `json:"model_or_harness_changed"`
	UnqualifiedBenefitClaim  bool     `json:"unqualified_benefit_claim"`
	Detail                   string   `json:"detail,omitempty"`
	RecordedAt               string   `json:"recorded_at"`
}

func (h HeuristicPublication) Validate() error {
	if h.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown heuristic schema version")
	}
	if e := validateID("heuristic", h.ID, true); e != nil {
		return e
	}
	if h.Name == "" || h.RetirementTrigger == "" || h.RecordedAt == "" {
		return errors.New("heuristic name, retirement trigger, and recorded_at required")
	}
	if len(h.ActivationConditions) == 0 || len(h.SupportedConfigScope) == 0 {
		return errors.New("heuristic activation conditions and supported scope required")
	}
	switch h.State {
	case HeuristicStateInactive, HeuristicStateActive, HeuristicStateReevaluationQueued, HeuristicStateRetired:
	default:
		return fmt.Errorf("unknown heuristic state %q", h.State)
	}
	if !h.TaskMatched && h.Activated {
		return errors.New("irrelevant task must not activate heuristic")
	}
	if h.ModelOrHarnessChanged && h.State != HeuristicStateReevaluationQueued && h.State != HeuristicStateRetired {
		return errors.New("model/harness change must queue reevaluation or retire")
	}
	if h.UnqualifiedBenefitClaim {
		return errors.New("unqualified benefit claim is forbidden")
	}
	return nil
}

// PlanningAssumption stays unresolved unless the user explicitly confirms (R07).
type PlanningAssumption struct {
	SchemaVersion          int    `json:"schema_version"`
	ID                     string `json:"id"`
	Detail                 string `json:"detail"`
	Status                 string `json:"status"`
	AffectsAcceptance      bool   `json:"affects_acceptance"`
	ConvertedToRequirement bool   `json:"converted_to_requirement"`
	MissingAcceptanceExample bool `json:"missing_acceptance_example"`
	AmbiguousBehavior      bool   `json:"ambiguous_behavior"`
	RecordedAt             string `json:"recorded_at"`
}

func (a PlanningAssumption) Validate() error {
	if a.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown assumption schema version")
	}
	if e := validateID("assumption", a.ID, true); e != nil {
		return e
	}
	if a.Detail == "" || a.RecordedAt == "" {
		return errors.New("assumption detail and recorded_at required")
	}
	switch a.Status {
	case AssumptionUnresolved, AssumptionUserConfirmed:
	default:
		return fmt.Errorf("unknown assumption status %q", a.Status)
	}
	if a.Status == AssumptionUnresolved && a.ConvertedToRequirement {
		return errors.New("unresolved assumption must not convert into a user requirement")
	}
	if a.AffectsAcceptance && a.Status == AssumptionUnresolved && a.ConvertedToRequirement {
		return errors.New("acceptance-affecting unresolved assumption cannot become a requirement")
	}
	return nil
}

// ProfilePackage preserves declared controls for legacy/full modes (R05).
type ProfilePackage struct {
	SchemaVersion       int      `json:"schema_version"`
	ID                  string   `json:"id"`
	Mode                string   `json:"mode"`
	MethodVersion       string   `json:"method_version"`
	DeclaredControls    []string `json:"declared_controls"`
	CharterDigest       string   `json:"charter_digest"`
	PriorVersion        string   `json:"prior_version,omitempty"`
	CompatibleWithPrior bool     `json:"compatible_with_prior"`
	CharterChanged      bool     `json:"charter_changed"`
	AmendmentRequired   bool     `json:"amendment_required"`
	AmendmentVersion    string   `json:"amendment_version,omitempty"`
	StandaloneCompatible bool    `json:"standalone_compatible"`
	RecordedAt          string   `json:"recorded_at"`
}

func (p ProfilePackage) Validate() error {
	if p.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown profile package schema version")
	}
	if e := validateID("profile_package", p.ID, true); e != nil {
		return e
	}
	switch p.Mode {
	case RamzaModeLite, RamzaModeFull, RamzaModeLegacy:
	default:
		return fmt.Errorf("unknown ramza mode %q", p.Mode)
	}
	if p.MethodVersion == "" || p.CharterDigest == "" || p.RecordedAt == "" {
		return errors.New("profile method version, charter digest, and recorded_at required")
	}
	if len(p.DeclaredControls) == 0 {
		return errors.New("declared controls required")
	}
	if p.CharterChanged && !p.AmendmentRequired {
		return errors.New("changed charter requires a versioned amendment")
	}
	if p.AmendmentRequired && p.AmendmentVersion == "" {
		return errors.New("amendment_required needs amendment_version")
	}
	switch p.Mode {
	case RamzaModeFull:
		if p.MethodVersion != RamzaMethodFullV1 && !p.AmendmentRequired {
			return errors.New("full mode must preserve ramza-full@1 unless amended")
		}
	case RamzaModeLegacy:
		if p.MethodVersion != RamzaMethodLegacyV1 && !p.AmendmentRequired {
			return errors.New("legacy mode must preserve ramza-legacy@1 unless amended")
		}
	case RamzaModeLite:
		if p.MethodVersion != RamzaMethodLiteV2 && !p.AmendmentRequired {
			return errors.New("lite mode consumer contract is ramza-lite@2")
		}
	}
	return nil
}

// RamzaLitePlan is the minimal actionable lite contract (R01–R07 consumer surface).
// Method use inside a maker is not an independent planner or critique.
type RamzaLitePlan struct {
	SchemaVersion              int                   `json:"schema_version"`
	ContractVersion            string                `json:"contract_version"`
	ID                         string                `json:"id"`
	RootID                     string                `json:"root_id,omitempty"`
	TaskID                     string                `json:"task_id"`
	Mode                       string                `json:"mode"`
	MethodVersion              string                `json:"method_version"`
	Outcome                    string                `json:"outcome"`
	Exclusions                 []string              `json:"exclusions"`
	Criteria                   []string              `json:"criteria"`
	Verifier                   string                `json:"verifier"`
	ChosenApproach             string                `json:"chosen_approach"`
	MaterialRisks              []string              `json:"material_risks"`
	ForcedOptionCount          int                   `json:"forced_option_count"`
	InventedAlternatives       []string              `json:"invented_alternatives"`
	ReadyForImplementation     bool                  `json:"ready_for_implementation"`
	UnresolvedDecisions        []UnresolvedDecision  `json:"unresolved_decisions,omitempty"`
	SettledDecisions           []SettledDecision     `json:"settled_decisions,omitempty"`
	Assumptions                []PlanningAssumption  `json:"assumptions,omitempty"`
	RubricScores               []RubricScore         `json:"rubric_scores,omitempty"`
	FileCount                  int                   `json:"file_count,omitempty"`
	FileCountSetsRisk          bool                  `json:"file_count_sets_risk"`
	EmbeddedInMaker            bool                  `json:"embedded_in_maker"`
	IndependentPlannerClaim    bool                  `json:"independent_planner_claim"`
	IndependentCritiqueClaim   bool                  `json:"independent_critique_claim"`
	DefaultFlip                bool                  `json:"default_flip"`
	SourceOwner                string                `json:"source_owner"`
	CanonicalSiblingPreserved  bool                  `json:"canonical_sibling_preserved"`
	ProducerArtifactSource     string                `json:"producer_artifact_source"`
	ProducerArtifactRef        string                `json:"producer_artifact_ref,omitempty"`
	ConsumerCarryComplete      bool                  `json:"consumer_carry_complete"`
	RecordedAt                 string                `json:"recorded_at"`
	Metadata                   map[string]string     `json:"metadata,omitempty"`
}

func (p RamzaLitePlan) Validate() error {
	if p.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown ramza plan schema version")
	}
	if p.ContractVersion != RamzaMethodContractID {
		return errors.New("unknown ramza method contract version")
	}
	for _, pair := range []struct{ label, id string }{
		{"plan", p.ID}, {"task", p.TaskID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if e := validateID("root", p.RootID, false); e != nil {
		return e
	}
	if p.Mode != RamzaModeLite {
		return errors.New("RamzaLitePlan requires lite mode")
	}
	if p.MethodVersion != RamzaMethodLiteV2 {
		return errors.New("lite consumer contract must be ramza-lite@2")
	}
	if p.Outcome == "" || p.Verifier == "" || p.ChosenApproach == "" || p.RecordedAt == "" {
		return errors.New("outcome, verifier, chosen approach, and recorded_at required")
	}
	if len(p.Exclusions) == 0 || len(p.Criteria) == 0 || len(p.MaterialRisks) == 0 {
		return errors.New("exclusions, criteria, and material risks required")
	}
	if p.ForcedOptionCount != 0 {
		return errors.New("lite plan must not force an option count")
	}
	if len(p.InventedAlternatives) != 0 {
		return errors.New("clear conventional lite task must not invent mandatory alternatives")
	}
	if p.FileCountSetsRisk {
		return errors.New("file count must not set risk")
	}
	if p.IndependentPlannerClaim || p.IndependentCritiqueClaim {
		return errors.New("method use inside a maker is not an independent planner or critique")
	}
	if p.DefaultFlip {
		return errors.New("default flip is forbidden")
	}
	if p.SourceOwner != RamzaCanonicalSourceOwner {
		return errors.New("primary owner Rynaro/Ramza remains canonical until accepted V4-10")
	}
	if !p.CanonicalSiblingPreserved {
		return errors.New("canonical sibling must remain preserved (no archive/move in V4-16)")
	}
	switch p.ProducerArtifactSource {
	case ProducerSourceSibling, ProducerSourceFixture:
	default:
		return fmt.Errorf("unknown producer artifact source %q", p.ProducerArtifactSource)
	}
	if p.ReadyForImplementation {
		for _, d := range p.UnresolvedDecisions {
			if d.BlocksReady || d.AffectsBehavior || d.AffectsAuthority {
				return errors.New("plan cannot be ready while behavior/authority decisions are unresolved")
			}
		}
		for _, a := range p.Assumptions {
			if a.AffectsAcceptance && a.Status == AssumptionUnresolved {
				return errors.New("plan cannot be ready with acceptance-affecting unresolved assumptions")
			}
		}
	}
	for _, d := range p.UnresolvedDecisions {
		if e := d.Validate(); e != nil {
			return e
		}
	}
	for _, d := range p.SettledDecisions {
		if e := d.Validate(); e != nil {
			return e
		}
	}
	for _, a := range p.Assumptions {
		if e := a.Validate(); e != nil {
			return e
		}
	}
	for _, r := range p.RubricScores {
		if e := r.Validate(); e != nil {
			return e
		}
	}
	return ValidateMetadata(p.Metadata)
}

// ConsumeDecisionRequest carries settled decisions into the maker without duplicate search (R03).
type ConsumeDecisionRequest struct {
	SchemaVersion       int              `json:"schema_version"`
	PlanID              string           `json:"plan_id"`
	DecisionID          string           `json:"decision_id"`
	CurrentEvidenceFP   string           `json:"current_evidence_fingerprint"`
	ChangedEvidence     bool             `json:"changed_evidence"`
	ChangedCondition    string           `json:"changed_condition,omitempty"`
}

func (r ConsumeDecisionRequest) Validate() error {
	if r.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown consume decision schema version")
	}
	if e := validateID("plan", r.PlanID, true); e != nil {
		return e
	}
	if e := validateID("decision", r.DecisionID, true); e != nil {
		return e
	}
	if r.CurrentEvidenceFP == "" {
		return errors.New("current evidence fingerprint required")
	}
	if r.ChangedEvidence && r.ChangedCondition == "" {
		return errors.New("changed evidence requires the matching invalidation condition")
	}
	return nil
}

// ConsumeDecisionResult is the consumer-side carry receipt.
type ConsumeDecisionResult struct {
	SchemaVersion           int             `json:"schema_version"`
	PlanID                  string          `json:"plan_id"`
	Decision                SettledDecision `json:"decision"`
	DuplicateSearchRequired bool            `json:"duplicate_search_required"`
	ReopenedOnlyRelevant    bool            `json:"reopened_only_relevant"`
	ConsumerCarryComplete   bool            `json:"consumer_carry_complete"`
}

func (r ConsumeDecisionResult) Validate() error {
	if r.SchemaVersion != RamzaSchemaVersion {
		return errors.New("unknown consume result schema version")
	}
	if e := validateID("plan", r.PlanID, true); e != nil {
		return e
	}
	if e := r.Decision.Validate(); e != nil {
		return e
	}
	if r.Decision.Reopened && !r.ReopenedOnlyRelevant {
		return errors.New("changed evidence must reopen only the relevant choice")
	}
	if !r.Decision.Reopened && r.DuplicateSearchRequired {
		return errors.New("settled decision must not require duplicate search")
	}
	return nil
}

// MarkReadyRequest asks to mark a lite plan ready for implementation (R02).
type MarkReadyRequest struct {
	SchemaVersion int    `json:"schema_version"`
	PlanID        string `json:"plan_id"`
}

// Decode helpers for strict CLI JSON.

func DecodeRamzaLitePlan(raw []byte) (RamzaLitePlan, error) {
	var p RamzaLitePlan
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeRubricScore(raw []byte) (RubricScore, error) {
	var r RubricScore
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeHeuristicPublication(raw []byte) (HeuristicPublication, error) {
	var h HeuristicPublication
	if e := StrictJSON(raw, &h); e != nil {
		return h, e
	}
	return h, h.Validate()
}

func DecodePlanningAssumption(raw []byte) (PlanningAssumption, error) {
	var a PlanningAssumption
	if e := StrictJSON(raw, &a); e != nil {
		return a, e
	}
	return a, a.Validate()
}

func DecodeProfilePackage(raw []byte) (ProfilePackage, error) {
	var p ProfilePackage
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeConsumeDecisionRequest(raw []byte) (ConsumeDecisionRequest, error) {
	var r ConsumeDecisionRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// SimulateProducerArtifact returns a fixture producer reference when Ramza checkout is absent.
func SimulateProducerArtifact(planID string) (source, ref string) {
	return ProducerSourceFixture, "fixture://ramza-lite@2/" + planID
}
