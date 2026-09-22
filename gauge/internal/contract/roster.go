package contract

import (
	"errors"
	"fmt"
)

// RosterSchemaVersion is the typed V4-18 roster-adoption namespace under schema 2.
const RosterSchemaVersion = 1

// RosterAdoptionContractID is the versioned consumer contract for need-based specialist adoption.
const RosterAdoptionContractID = "gauge-roster-adoption@1"

// RequiredAdoptionSlices are the declared required V4-18 profile registry entries.
// Named expertise / aliases / charters / ceilings are preserved — not a global rename.
var RequiredAdoptionSlices = []string{
	"ATLAS", "FORGE", "VIGIL", "IDG", "Kupo", "Gilgamesh", "SPECTRA", "APIVR-Delta", "nexus-adoption",
}

// Control classifications (R04) — rule vs heuristic vs rationale.
const (
	ControlClassRule      = "rule"
	ControlClassHeuristic = "heuristic"
	ControlClassRationale = "rationale"
)

// Benefit labels (R07) — unproven benefits never advertised as measured without V4-21 evidence.
const (
	BenefitMeasured      = "measured"
	BenefitExperimental  = "experimental"
	BenefitMaintenance   = "maintenance"
	BenefitUnproven      = "unproven"
	BenefitUntested      = "untested"
	BenefitNoWin         = "no_win"
	BenefitInconclusive  = "inconclusive"
)

// Assignment outcome forms — reuse V4-13 execution forms where applicable.
const (
	AdoptionEmbedded   = FormEmbedded
	AdoptionConsultant = FormConsultant
	AdoptionIsolated   = FormIsolatedWriter
	AdoptionVerify     = FormVerification
)

// Explicit request kinds that preserve separation (R02).
const (
	RequestNamedLegacySpecialist = "named_legacy_specialist"
	RequestSeparateATLASInspect  = "separate_atlas_inspection"
	RequestIndependentCritique   = "independent_critique"
	RequestRequiredDocumentation = "required_documentation"
	RequestReadOnlyIntent        = "read_only_intent"
)

// Task kinds that permit embedded methods when no separate boundary exists (R01).
const (
	TaskClearFix          = "clear_fix"
	TaskTargetedDiscovery = "targeted_discovery"
	TaskLitePlanning      = "lite_planning"
)

// Boundary reason kinds that must be recorded on separated assignments (R03).
const (
	AdoptBoundaryFORGEConsult     = "forge_consultation"
	AdoptBoundaryVIGILConsult     = "vigil_consultation"
	AdoptBoundaryIsolatedWriter   = BoundaryIsolatedWriter
	AdoptBoundaryChecker          = BoundaryVerification
	AdoptBoundaryExplicitUser     = BoundaryExplicitUser
	AdoptBoundaryContextSep       = BoundaryContextSeparation
	AdoptBoundaryIndependentTrack = BoundaryIndependentConsult
)

// SpecialistCeiling records a preserved charter ceiling (not weakened by adoption).
type SpecialistCeiling struct {
	ID          string `json:"id"`
	Description string `json:"description"`
	RefusalWeakened bool `json:"refusal_weakened"`
}

func (c SpecialistCeiling) Validate() error {
	if e := validateID("ceiling", c.ID, true); e != nil {
		return e
	}
	if c.Description == "" {
		return errors.New("ceiling description required")
	}
	if c.RefusalWeakened {
		return errors.New("adoption must not weaken specialist refusals")
	}
	return nil
}

// SpecialistProfile is one fixture profile registry entry (required slices).
// Activation + I/O/execution-form contract + producer/consumer version checks.
type SpecialistProfile struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"` // slice key, e.g. ATLAS
	DisplayName         string            `json:"display_name"`
	Aliases             []string          `json:"aliases,omitempty"`
	Purpose             string            `json:"purpose"`
	CharterDigest       string            `json:"charter_digest"`
	Ceilings            []SpecialistCeiling `json:"ceilings"`
	ActivationConditions []string         `json:"activation_conditions"`
	Contract            SkillContract     `json:"contract"` // V4-13 skill I/O/form contract
	ProducerVersion     string            `json:"producer_version"`
	ConsumerVersion     string            `json:"consumer_version"`
	ReuseRAMZALite      bool              `json:"reuse_ramza_lite,omitempty"`
	ReuseViviModes      bool              `json:"reuse_vivi_modes,omitempty"`
	GlobalRename        bool              `json:"global_rename"`
	OptOutLegacy        bool              `json:"opt_out_legacy_available"`
	LiveBlocked         bool              `json:"live_blocked"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (p SpecialistProfile) Validate() error {
	if p.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown roster profile schema version")
	}
	if e := validateID("profile", p.ID, true); e != nil {
		return e
	}
	if p.DisplayName == "" || p.Purpose == "" || p.CharterDigest == "" || p.RecordedAt == "" {
		return errors.New("display_name, purpose, charter_digest, and recorded_at required")
	}
	if len(p.ActivationConditions) == 0 {
		return errors.New("activation conditions required")
	}
	if e := p.Contract.Validate(); e != nil {
		return fmt.Errorf("profile skill contract: %w", e)
	}
	if p.ProducerVersion == "" || p.ConsumerVersion == "" {
		return errors.New("producer_version and consumer_version required")
	}
	if p.GlobalRename {
		return errors.New("V4-18 must not perform a global rename of specialist identities")
	}
	if !p.OptOutLegacy {
		return errors.New("opt-out/legacy selection must remain available")
	}
	if !p.LiveBlocked {
		return errors.New("V4-18 fixture scope keeps live blocked")
	}
	if len(p.Ceilings) == 0 {
		return errors.New("at least one preserved ceiling required")
	}
	for _, c := range p.Ceilings {
		if e := c.Validate(); e != nil {
			return e
		}
	}
	for _, a := range p.Aliases {
		if e := validateID("alias", a, true); e != nil {
			return e
		}
	}
	return ValidateMetadata(p.Metadata)
}

// MethodologyControlRevision retains rule/heuristic/rationale classification (R04).
type MethodologyControlRevision struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	ProfileID           string            `json:"profile_id"`
	ControlName         string            `json:"control_name"`
	Classification      string            `json:"classification"` // rule | heuristic | rationale
	PriorVersion        string            `json:"prior_version"`
	ReplacementRef      string            `json:"replacement_reference"`
	ProtectedTestsRetained bool           `json:"protected_tests_retained"`
	OptionCountIsHeuristic bool           `json:"option_count_is_heuristic"`
	RationaleCertified  bool              `json:"rationale_certified"` // must stay false
	Detail              string            `json:"detail,omitempty"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (c MethodologyControlRevision) Validate() error {
	if c.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown control revision schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"control", c.ID}, {"profile", c.ProfileID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if c.ControlName == "" || c.PriorVersion == "" || c.ReplacementRef == "" || c.RecordedAt == "" {
		return errors.New("control_name, prior_version, replacement_reference, and recorded_at required")
	}
	switch c.Classification {
	case ControlClassRule, ControlClassHeuristic, ControlClassRationale:
	default:
		return fmt.Errorf("unknown control classification %q", c.Classification)
	}
	if !c.ProtectedTestsRetained {
		return errors.New("control diff must retain protected tests")
	}
	if c.Classification == ControlClassHeuristic && !c.OptionCountIsHeuristic && c.ControlName == "option_count" {
		return errors.New("option counts are heuristics")
	}
	if c.RationaleCertified {
		return errors.New("rationale must not be falsely certified")
	}
	return ValidateMetadata(c.Metadata)
}

// ProfileCompatibilityCheck validates exact producer/consumer versions (R05).
type ProfileCompatibilityCheck struct {
	SchemaVersion          int               `json:"schema_version"`
	ID                     string            `json:"id"`
	ProfileID              string            `json:"profile_id"`
	ProducerVersion        string            `json:"producer_version"`
	ConsumerVersion        string            `json:"consumer_version"`
	ExpectedProducer       string            `json:"expected_producer"`
	ExpectedConsumer       string            `json:"expected_consumer"`
	Compatible             bool              `json:"compatible"`
	DiscoveryParity        bool              `json:"discovery_parity"`
	InventedTags           bool              `json:"invented_tags"`
	ChangedPerformatives   bool              `json:"changed_performatives"`
	MandatoryExternalAgent bool              `json:"mandatory_external_agent_import"`
	RejectReasons          []string          `json:"reject_reasons,omitempty"`
	Metadata               map[string]string `json:"metadata,omitempty"`
	RecordedAt             string            `json:"recorded_at"`
}

func (c ProfileCompatibilityCheck) Validate() error {
	if c.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown compatibility schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"compat", c.ID}, {"profile", c.ProfileID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if c.ProducerVersion == "" || c.ConsumerVersion == "" || c.ExpectedProducer == "" || c.ExpectedConsumer == "" || c.RecordedAt == "" {
		return errors.New("producer/consumer versions and recorded_at required")
	}
	if c.InventedTags || c.ChangedPerformatives || c.MandatoryExternalAgent {
		if c.Compatible {
			return errors.New("invented tags, changed performatives, or mandatory external-agent imports cannot be compatible")
		}
	}
	if c.Compatible {
		if c.ProducerVersion != c.ExpectedProducer || c.ConsumerVersion != c.ExpectedConsumer {
			return errors.New("compatible claim requires exact producer and consumer version match")
		}
		if !c.DiscoveryParity {
			return errors.New("compatible claim requires discovery parity")
		}
		if len(c.RejectReasons) != 0 {
			return errors.New("compatible claim must not carry reject reasons")
		}
	}
	if !c.Compatible && len(c.RejectReasons) == 0 {
		return errors.New("incompatible result requires reject reasons")
	}
	return ValidateMetadata(c.Metadata)
}

// IsolationContractCheck validates bounded I/O for advertised isolated execution (R06).
type IsolationContractCheck struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	ProfileID          string            `json:"profile_id"`
	MethodID           string            `json:"method_id"`
	AdvertisedIsolated bool              `json:"advertised_isolated"`
	ExecutionForm      string            `json:"execution_form"`
	Contract           SkillContract     `json:"contract"`
	ProvidedInputs     []string          `json:"provided_inputs"`
	ResultBytes        int               `json:"result_bytes"`
	InlineOnlySkill    bool              `json:"inline_only_skill"`
	Accepted           bool              `json:"accepted"`
	RejectReasons      []string          `json:"reject_reasons,omitempty"`
	Metadata           map[string]string `json:"metadata,omitempty"`
	RecordedAt         string            `json:"recorded_at"`
}

func (c IsolationContractCheck) Validate() error {
	if c.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown isolation schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"isolation", c.ID}, {"profile", c.ProfileID}, {"method", c.MethodID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if c.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	switch c.ExecutionForm {
	case FormEmbedded, FormConsultant, FormIsolatedWriter, FormVerification:
	default:
		return errors.New("unknown execution form")
	}
	if e := c.Contract.Validate(); e != nil {
		return e
	}
	if c.Accepted && len(c.RejectReasons) != 0 {
		return errors.New("accepted isolation must not carry reject reasons")
	}
	if !c.Accepted && len(c.RejectReasons) == 0 {
		return errors.New("rejected isolation requires reject reasons")
	}
	return ValidateMetadata(c.Metadata)
}

// BenefitEvidenceLabel labels unproven specialist-strategy benefits (R07).
type BenefitEvidenceLabel struct {
	SchemaVersion            int               `json:"schema_version"`
	ID                       string            `json:"id"`
	ProfileID                string            `json:"profile_id"`
	Strategy                 string            `json:"strategy"`
	EvidenceClass            string            `json:"evidence_class"` // untested|no_win|inconclusive|experimental|maintenance|measured
	QualifyingComparative    bool              `json:"qualifying_comparative_evidence"`
	V421EvidenceRef          string            `json:"v4_21_evidence_ref,omitempty"`
	AdvertisedAsMeasured     bool              `json:"advertised_as_measured"`
	PerformanceGainClaimed   bool              `json:"performance_gain_claimed"`
	Label                    string            `json:"label"` // experimental | maintenance | unproven
	Detail                   string            `json:"detail,omitempty"`
	Metadata                 map[string]string `json:"metadata,omitempty"`
	RecordedAt               string            `json:"recorded_at"`
}

func (b BenefitEvidenceLabel) Validate() error {
	if b.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown benefit label schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"benefit", b.ID}, {"profile", b.ProfileID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if b.Strategy == "" || b.RecordedAt == "" {
		return errors.New("strategy and recorded_at required")
	}
	switch b.EvidenceClass {
	case BenefitUntested, BenefitNoWin, BenefitInconclusive, BenefitExperimental,
		BenefitMaintenance, BenefitMeasured, BenefitUnproven:
	default:
		return fmt.Errorf("unknown evidence class %q", b.EvidenceClass)
	}
	switch b.Label {
	case BenefitExperimental, BenefitMaintenance, BenefitUnproven, BenefitMeasured:
	default:
		return fmt.Errorf("unknown benefit label %q", b.Label)
	}
	if !b.QualifyingComparative || b.EvidenceClass != BenefitMeasured {
		if b.AdvertisedAsMeasured || b.PerformanceGainClaimed || b.Label == BenefitMeasured {
			return errors.New("unproven/untested/no-win/inconclusive must not be advertised as measured improvements")
		}
		if b.Label != BenefitExperimental && b.Label != BenefitMaintenance && b.Label != BenefitUnproven {
			return errors.New("lacking comparative evidence must label experimental, maintenance, or unproven")
		}
	}
	if b.Label == BenefitMeasured && b.V421EvidenceRef == "" {
		return errors.New("measured benefit requires V4-21 evidence reference")
	}
	return ValidateMetadata(b.Metadata)
}

// RosterRouteRequest asks need-based routing for a task (R01–R03).
type RosterRouteRequest struct {
	SchemaVersion          int      `json:"schema_version"`
	ID                     string   `json:"id"`
	TaskKind               string   `json:"task_kind"`
	ProfileID              string   `json:"profile_id"`
	RequiresExpertise      bool     `json:"requires_expertise"`
	SeparateBoundaryNeeded bool     `json:"separate_boundary_needed"`
	ExplicitRequestKind    string   `json:"explicit_request_kind,omitempty"`
	BoundaryReason         string   `json:"boundary_reason,omitempty"`
	PreferredForm          string   `json:"preferred_form,omitempty"`
	Deliverables           []string `json:"deliverables,omitempty"`
	RecordedAt             string   `json:"recorded_at"`
}

func (r RosterRouteRequest) Validate() error {
	if r.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown route request schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"route", r.ID}, {"profile", r.ProfileID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if r.TaskKind == "" || r.RecordedAt == "" {
		return errors.New("task_kind and recorded_at required")
	}
	if r.ExplicitRequestKind != "" {
		switch r.ExplicitRequestKind {
		case RequestNamedLegacySpecialist, RequestSeparateATLASInspect, RequestIndependentCritique,
			RequestRequiredDocumentation, RequestReadOnlyIntent:
		default:
			return fmt.Errorf("unknown explicit request kind %q", r.ExplicitRequestKind)
		}
	}
	return nil
}

// RosterRouteAssignment is the recorded routing decision (R01–R03).
type RosterRouteAssignment struct {
	SchemaVersion          int               `json:"schema_version"`
	ID                     string            `json:"id"`
	RequestID              string            `json:"request_id"`
	ProfileID              string            `json:"profile_id"`
	ExecutionForm          string            `json:"execution_form"`
	ReportClass            string            `json:"report_class"`
	ContinuingMaker        bool              `json:"continuing_maker"`
	SeparatedWorker        bool              `json:"separated_worker"`
	BoundaryReason         string            `json:"boundary_reason,omitempty"`
	BoundaryReasonRecorded bool              `json:"boundary_reason_recorded"`
	EmbeddedSubstituted    bool              `json:"embedded_substituted_for_independent"` // must stay false when independent requested
	UnnecessaryWorkers     int               `json:"unnecessary_workers"`
	DeliverablesPreserved  bool              `json:"deliverables_preserved"`
	Selection              SelectionReason   `json:"selection"`
	RejectReasons          []string          `json:"reject_reasons,omitempty"`
	Metadata               map[string]string `json:"metadata,omitempty"`
	RecordedAt             string            `json:"recorded_at"`
}

func (a RosterRouteAssignment) Validate() error {
	if a.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown route assignment schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"assignment", a.ID}, {"request", a.RequestID}, {"profile", a.ProfileID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch a.ExecutionForm {
	case FormEmbedded, FormConsultant, FormIsolatedWriter, FormVerification:
	default:
		return errors.New("unknown execution form")
	}
	switch a.ReportClass {
	case ReportMethodUse, ReportSpecialistInvocation:
	default:
		return errors.New("unknown report class")
	}
	if a.SeparatedWorker && !a.BoundaryReasonRecorded {
		return errors.New("separated assignment must record boundary reason")
	}
	if a.SeparatedWorker && a.BoundaryReason == "" {
		return errors.New("separated assignment requires non-empty boundary reason")
	}
	if a.ContinuingMaker && a.SeparatedWorker {
		return errors.New("assignment cannot be both continuing maker and separated worker")
	}
	if a.EmbeddedSubstituted {
		return errors.New("embedded method must not silently substitute for requested independent invocation")
	}
	if a.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(a.Metadata)
}

// RosterAdoptionRegistry is the top-level fixture registry receipt.
type RosterAdoptionRegistry struct {
	SchemaVersion   int               `json:"schema_version"`
	ID              string            `json:"id"`
	ContractVersion string            `json:"contract_version"`
	ProfileIDs      []string          `json:"profile_ids"`
	RequiredCovered bool              `json:"required_slices_covered"`
	LiveBlocked     bool              `json:"live_blocked"`
	Metadata        map[string]string `json:"metadata,omitempty"`
	RecordedAt      string            `json:"recorded_at"`
}

func (r RosterAdoptionRegistry) Validate() error {
	if r.SchemaVersion != RosterSchemaVersion {
		return errors.New("unknown roster registry schema version")
	}
	if e := validateID("registry", r.ID, true); e != nil {
		return e
	}
	if r.ContractVersion != RosterAdoptionContractID {
		return errors.New("registry contract version must be gauge-roster-adoption@1")
	}
	if !r.RequiredCovered {
		return errors.New("required adoption slices must be covered")
	}
	if !r.LiveBlocked {
		return errors.New("V4-18 fixture scope keeps live blocked")
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	have := map[string]bool{}
	for _, id := range r.ProfileIDs {
		have[id] = true
	}
	for _, need := range RequiredAdoptionSlices {
		if !have[need] {
			return fmt.Errorf("missing required adoption slice %q", need)
		}
	}
	return ValidateMetadata(r.Metadata)
}

// FixtureSkill builds a V4-13 SkillContract for a roster profile method.
func FixtureSkill(method, version string, forms, inputs []string, out string) SkillContract {
	return SkillContract{
		SchemaVersion:       CompilerSchemaVersion,
		MethodID:            method,
		Version:             version,
		Applicability:       []string{"fixture", "roster-adoption"},
		RequiredInputs:      inputs,
		OutputSchema:        out,
		AllowedForms:        forms,
		MaxOutputBytes:      8192,
		ExperimentalProfile: ExperimentalProfileID,
	}
}

// Decode helpers.

func DecodeSpecialistProfile(raw []byte) (SpecialistProfile, error) {
	var p SpecialistProfile
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeRosterRouteRequest(raw []byte) (RosterRouteRequest, error) {
	var r RosterRouteRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeMethodologyControlRevision(raw []byte) (MethodologyControlRevision, error) {
	var c MethodologyControlRevision
	if e := StrictJSON(raw, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}

func DecodeProfileCompatibilityCheck(raw []byte) (ProfileCompatibilityCheck, error) {
	var c ProfileCompatibilityCheck
	if e := StrictJSON(raw, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}

func DecodeIsolationContractCheck(raw []byte) (IsolationContractCheck, error) {
	var c IsolationContractCheck
	if e := StrictJSON(raw, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}

func DecodeBenefitEvidenceLabel(raw []byte) (BenefitEvidenceLabel, error) {
	var b BenefitEvidenceLabel
	if e := StrictJSON(raw, &b); e != nil {
		return b, e
	}
	return b, b.Validate()
}
