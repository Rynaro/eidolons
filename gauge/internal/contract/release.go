package contract

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
)

// ReleaseSchemaVersion is the typed V4-23 release/migration namespace version under schema 2.
const ReleaseSchemaVersion = 1

// Supported migration fixture origins (R01/T01).
const (
	MigOriginFresh         = "fresh"
	MigOriginPreV1411      = "pre_v1_41_1"
	MigOriginV220          = "v2_20"
	MigOriginV331          = "v3_3_1"
	MigOriginDirty         = "dirty"
	MigOriginInterrupted   = "interrupted"
	MigOriginLegacyGeneric = "legacy"
)

// Migration stage machine: stage → verify → switch (R01).
const (
	MigStageStaging  = "staging"
	MigStageVerify   = "verify"
	MigStageSwitch   = "switch"
	MigStageComplete = "complete"
	MigStageFailed   = "failed"
	MigStageRolledBack = "rolled_back"
)

// Failure points for recovery fixtures (R02).
const (
	MigFailNone    = "none"
	MigFailStaging = "staging"
	MigFailSwitch  = "switch"
	MigFailSmoke   = "smoke"
)

// Release candidate kinds (R03).
const (
	ReleaseKindDocsOnly     = "docs_only"
	ReleaseKindCodeBehavior = "code_behavior"
)

// Separate readiness decisions (R07) — never a composite green badge.
const (
	DecisionPass    = "pass"
	DecisionFail    = "fail"
	DecisionBlocked = "blocked"
	DecisionNull    = "null"
	DecisionNA      = "not_applicable"
)

// Authorization / promotion outcomes (R04).
const (
	AuthBlockedInsufficientEvidence = "insufficient_promotion_evidence"
	AuthBlockedMissingApproval      = "missing_approval"
	AuthBlockedPreparedReportOnly   = "prepared_report_does_not_authorize"
	AuthExplicitOperator            = "explicit_operator_authorization"
)

// Capability areas invalidated by host version drift (R06).
const (
	CapAreaCancellation = "cancellation"
	CapAreaUsage        = "usage"
	CapAreaToolBoundary = "tool_boundary"
)

// knownMigrationOrigin reports whether origin is a supported fixture class.
func knownMigrationOrigin(o string) bool {
	switch o {
	case MigOriginFresh, MigOriginPreV1411, MigOriginV220, MigOriginV331,
		MigOriginDirty, MigOriginInterrupted, MigOriginLegacyGeneric:
		return true
	}
	return false
}

// MigrationAttempt stages and verifies a replacement before switching active install (R01).
type MigrationAttempt struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	Origin              string            `json:"origin"`
	Authorized          bool              `json:"authorized"`
	AuthorizationRef    string            `json:"authorization_ref,omitempty"`
	Stage               string            `json:"stage"`
	StagedVerified      bool              `json:"staged_verified"`
	ActiveSwitched      bool              `json:"active_switched"`
	ForceIntegrityBypass bool             `json:"force_integrity_bypass"`
	PreviousInstallID   string            `json:"previous_install_id"`
	StagedInstallID     string            `json:"staged_install_id"`
	ActiveInstallID     string            `json:"active_install_id"`
	FailurePoint        string            `json:"failure_point"`
	UserStatePreserved  bool              `json:"user_state_preserved"`
	SessionsPreserved   bool              `json:"sessions_preserved"`
	SettingsPreserved   bool              `json:"settings_preserved"`
	CandidatesPreserved bool              `json:"candidates_preserved"`
	EvidencePreserved   bool              `json:"evidence_preserved"`
	PendingReservations []string          `json:"pending_reservations,omitempty"`
	Rejected            bool              `json:"rejected"`
	RejectReason        string            `json:"reject_reason,omitempty"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (m MigrationAttempt) Validate() error {
	if m.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown migration attempt schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"migration", m.ID}, {"previous_install", m.PreviousInstallID},
		{"staged_install", m.StagedInstallID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if !knownMigrationOrigin(m.Origin) {
		return errors.New("unknown migration origin fixture")
	}
	switch m.Stage {
	case MigStageStaging, MigStageVerify, MigStageSwitch, MigStageComplete, MigStageFailed, MigStageRolledBack:
	default:
		return errors.New("unknown migration stage")
	}
	switch m.FailurePoint {
	case MigFailNone, MigFailStaging, MigFailSwitch, MigFailSmoke:
	default:
		return errors.New("unknown migration failure point")
	}
	if m.ForceIntegrityBypass {
		return errors.New("force-integrity bypass is forbidden")
	}
	if m.Authorized && m.AuthorizationRef == "" {
		return errors.New("authorized migration requires authorization_ref")
	}
	if m.ActiveSwitched && !m.StagedVerified {
		return errors.New("active switch requires prior staged verification")
	}
	if m.ActiveSwitched && m.ActiveInstallID != m.StagedInstallID {
		return errors.New("active install must equal staged install after switch")
	}
	if !m.ActiveSwitched && m.ActiveInstallID != "" && m.ActiveInstallID != m.PreviousInstallID {
		return errors.New("without switch, active install must remain previous")
	}
	if m.Rejected && m.RejectReason == "" {
		return errors.New("rejected migration requires reason")
	}
	if m.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(m.Metadata)
}

// StageAndVerifyMigration advances stage→verify→switch only when authorized and verified (R01/T01).
func StageAndVerifyMigration(m *MigrationAttempt) {
	m.ForceIntegrityBypass = false
	if !m.Authorized {
		m.Rejected = true
		m.RejectReason = "migration_not_authorized"
		m.Stage = MigStageFailed
		m.StagedVerified = false
		m.ActiveSwitched = false
		m.ActiveInstallID = m.PreviousInstallID
		return
	}
	switch m.FailurePoint {
	case MigFailStaging:
		m.Stage = MigStageFailed
		m.StagedVerified = false
		m.ActiveSwitched = false
		m.ActiveInstallID = m.PreviousInstallID
		m.Rejected = true
		m.RejectReason = "staging_failure"
		preserveMigrationUserState(m)
		return
	case MigFailSwitch, MigFailSmoke:
		m.Stage = MigStageVerify
		m.StagedVerified = true
		m.ActiveSwitched = false
		m.ActiveInstallID = m.PreviousInstallID
		m.Rejected = true
		if m.FailurePoint == MigFailSwitch {
			m.RejectReason = "switch_failure"
		} else {
			m.RejectReason = "smoke_failure"
		}
		preserveMigrationUserState(m)
		return
	}
	// Happy path: stage → verify → switch.
	m.Stage = MigStageComplete
	m.StagedVerified = true
	m.ActiveSwitched = true
	m.ActiveInstallID = m.StagedInstallID
	m.Rejected = false
	m.RejectReason = ""
	preserveMigrationUserState(m)
}

func preserveMigrationUserState(m *MigrationAttempt) {
	m.UserStatePreserved = true
	m.SessionsPreserved = true
	m.SettingsPreserved = true
	m.CandidatesPreserved = true
	m.EvidencePreserved = true
}

// MigrationRecovery restores previous installation after failed migration/post-switch (R02).
type MigrationRecovery struct {
	SchemaVersion         int               `json:"schema_version"`
	ID                    string            `json:"id"`
	MigrationID           string            `json:"migration_id"`
	FailurePoint          string            `json:"failure_point"`
	PreviousInstallRestored bool            `json:"previous_install_restored"`
	ActiveInstallID       string            `json:"active_install_id"`
	PreviousInstallID     string            `json:"previous_install_id"`
	UserStatePreserved    bool              `json:"user_state_preserved"`
	SessionsPreserved     bool              `json:"sessions_preserved"`
	PendingReservations   []string          `json:"pending_reservations"`
	NativeSessions        []string          `json:"native_sessions"`
	RepeatMigrationSafe   bool              `json:"repeat_migration_safe"`
	UsablePrevious        bool              `json:"usable_previous"`
	Metadata              map[string]string `json:"metadata,omitempty"`
	RecordedAt            string            `json:"recorded_at"`
}

func (r MigrationRecovery) Validate() error {
	if r.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown migration recovery schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"recovery", r.ID}, {"migration", r.MigrationID},
		{"previous_install", r.PreviousInstallID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch r.FailurePoint {
	case MigFailStaging, MigFailSwitch, MigFailSmoke:
	default:
		return errors.New("recovery requires a failure point")
	}
	if !r.PreviousInstallRestored || !r.UsablePrevious {
		return errors.New("recovery must restore usable previous installation")
	}
	if r.ActiveInstallID != r.PreviousInstallID {
		return errors.New("recovered active install must equal previous")
	}
	if !r.UserStatePreserved || !r.SessionsPreserved {
		return errors.New("recovery must preserve user state and sessions")
	}
	if !r.RepeatMigrationSafe {
		return errors.New("repeat migration must remain safe after recovery")
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(r.Metadata)
}

// RecoverFailedMigration builds a recovery that preserves previous install + user state (R02/T02).
func RecoverFailedMigration(m MigrationAttempt) MigrationRecovery {
	preserveMigrationUserState(&m)
	return MigrationRecovery{
		SchemaVersion:           ReleaseSchemaVersion,
		ID:                      "recover-" + m.ID,
		MigrationID:             m.ID,
		FailurePoint:            m.FailurePoint,
		PreviousInstallRestored: true,
		ActiveInstallID:         m.PreviousInstallID,
		PreviousInstallID:       m.PreviousInstallID,
		UserStatePreserved:      true,
		SessionsPreserved:       true,
		PendingReservations:     append([]string{}, m.PendingReservations...),
		NativeSessions:          []string{"native-session-1"},
		RepeatMigrationSafe:     true,
		UsablePrevious:          true,
		RecordedAt:              m.RecordedAt,
	}
}

// ReleaseCandidate evaluates deterministic checks + applicable authorized live evidence (R03).
type ReleaseCandidate struct {
	SchemaVersion            int               `json:"schema_version"`
	ID                       string            `json:"id"`
	Kind                     string            `json:"kind"`
	DeclaredDeterministicOK  bool              `json:"declared_deterministic_ok"`
	DeterministicChecks      []string          `json:"deterministic_checks"`
	LiveEvidenceRequired     bool              `json:"live_evidence_required"`
	LiveEvidenceAuthorized   bool              `json:"live_evidence_authorized"`
	LiveEvidencePresent      bool              `json:"live_evidence_present"`
	SmokeSucceeded           bool              `json:"smoke_succeeded"`
	SmokeSubstitutesLive     bool              `json:"smoke_substitutes_live"`
	GatePassed               bool              `json:"gate_passed"`
	RejectReason             string            `json:"reject_reason,omitempty"`
	Metadata                 map[string]string `json:"metadata,omitempty"`
	RecordedAt               string            `json:"recorded_at"`
}

func (c ReleaseCandidate) Validate() error {
	if c.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown release candidate schema version")
	}
	if e := validateID("candidate", c.ID, true); e != nil {
		return e
	}
	switch c.Kind {
	case ReleaseKindDocsOnly, ReleaseKindCodeBehavior:
	default:
		return errors.New("unknown release candidate kind")
	}
	if len(c.DeterministicChecks) == 0 {
		return errors.New("declared deterministic checks required")
	}
	if c.SmokeSubstitutesLive {
		return errors.New("smoke must not substitute missing live evidence")
	}
	if c.Kind == ReleaseKindCodeBehavior && c.LiveEvidenceRequired && !c.LiveEvidencePresent && c.GatePassed {
		return errors.New("code/behavior gate cannot pass without required live evidence")
	}
	if c.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(c.Metadata)
}

// EvaluateReleaseGate applies R03/T03: docs-only vs code/behavior; smoke ≠ live evidence.
func EvaluateReleaseGate(c *ReleaseCandidate) {
	c.SmokeSubstitutesLive = false
	if !c.DeclaredDeterministicOK || len(c.DeterministicChecks) == 0 {
		c.GatePassed = false
		c.RejectReason = "deterministic_checks_incomplete"
		return
	}
	switch c.Kind {
	case ReleaseKindDocsOnly:
		// Docs-only: deterministic checks suffice; live not required.
		c.LiveEvidenceRequired = false
		c.GatePassed = true
		c.RejectReason = ""
		return
	case ReleaseKindCodeBehavior:
		c.LiveEvidenceRequired = true
		if !c.LiveEvidenceAuthorized || !c.LiveEvidencePresent {
			c.GatePassed = false
			if c.SmokeSucceeded {
				c.RejectReason = "smoke_success_does_not_replace_live_evidence"
			} else {
				c.RejectReason = "missing_authorized_live_evidence"
			}
			return
		}
		c.GatePassed = true
		c.RejectReason = ""
	}
}

// PromotionAuthorization refuses tag/merge/publication without evidence + approval (R04).
type PromotionAuthorization struct {
	SchemaVersion          int               `json:"schema_version"`
	ID                     string            `json:"id"`
	CandidateID            string            `json:"candidate_id"`
	EvidenceSufficient     bool              `json:"evidence_sufficient"`
	OperatorApprovalPresent bool             `json:"operator_approval_present"`
	ApprovalRef            string            `json:"approval_ref,omitempty"`
	PreparedReportReady    bool              `json:"prepared_report_ready"`
	BehavioralDefaultsChanged bool           `json:"behavioral_defaults_changed"`
	TagAuthorized          bool              `json:"tag_authorized"`
	MergeAuthorized        bool              `json:"merge_authorized"`
	PublicationAuthorized  bool              `json:"publication_authorized"`
	BlockReason            string            `json:"block_reason,omitempty"`
	Metadata               map[string]string `json:"metadata,omitempty"`
	RecordedAt             string            `json:"recorded_at"`
}

func (p PromotionAuthorization) Validate() error {
	if p.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown promotion authorization schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"authorization", p.ID}, {"candidate", p.CandidateID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if p.TagAuthorized || p.MergeAuthorized || p.PublicationAuthorized {
		return errors.New("fixture gate must never authorize tag, merge, or publication")
	}
	if p.BehavioralDefaultsChanged {
		return errors.New("insufficient evidence must leave behavioral defaults unchanged")
	}
	if p.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(p.Metadata)
}

// GatePromotionAuthorization leaves defaults unchanged and blocks tag/merge/publication (R04/T04).
func GatePromotionAuthorization(p *PromotionAuthorization) {
	p.TagAuthorized = false
	p.MergeAuthorized = false
	p.PublicationAuthorized = false
	p.BehavioralDefaultsChanged = false
	if !p.EvidenceSufficient {
		p.BlockReason = AuthBlockedInsufficientEvidence
		return
	}
	if !p.OperatorApprovalPresent || p.ApprovalRef == "" {
		p.BlockReason = AuthBlockedMissingApproval
		return
	}
	// Even with evidence+approval recorded in fixtures, prepared report alone never
	// authorizes real tag/merge/publication — this package only records the refusal.
	if p.PreparedReportReady {
		p.BlockReason = AuthBlockedPreparedReportOnly
		return
	}
	p.BlockReason = AuthBlockedPreparedReportOnly
}

// RetirementRequest blocks archive while unmigrated supported consumers remain (R05).
type RetirementRequest struct {
	SchemaVersion            int               `json:"schema_version"`
	ID                       string            `json:"id"`
	ComponentID              string            `json:"component_id"`
	UnmigratedConsumers      []string          `json:"unmigrated_consumers"`
	ReplacementTested        bool              `json:"replacement_tested"`
	InventoryEvidence        bool              `json:"inventory_evidence"`
	LicenseEvidence          bool              `json:"license_evidence"`
	HistoryEvidence          bool              `json:"history_evidence"`
	SupportEvidence          bool              `json:"support_evidence"`
	RollbackEvidence         bool              `json:"rollback_evidence"`
	ExplicitArchiveAuth      bool              `json:"explicit_archive_authorization"`
	ArchiveAuthorizationRef  string            `json:"archive_authorization_ref,omitempty"`
	RetirementBlocked        bool              `json:"retirement_blocked"`
	BlockReason              string            `json:"block_reason,omitempty"`
	Metadata                 map[string]string `json:"metadata,omitempty"`
	RecordedAt               string            `json:"recorded_at"`
}

func (r RetirementRequest) Validate() error {
	if r.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown retirement request schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"retirement", r.ID}, {"component", r.ComponentID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if len(r.UnmigratedConsumers) > 0 && !r.RetirementBlocked {
		return errors.New("unmigrated supported consumer must block retirement")
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(r.Metadata)
}

// EvaluateRetirementGate blocks when unmigrated consumers or evidence/auth missing (R05/T05).
func EvaluateRetirementGate(r *RetirementRequest) {
	if len(r.UnmigratedConsumers) > 0 {
		r.RetirementBlocked = true
		sort.Strings(r.UnmigratedConsumers)
		r.BlockReason = "unmigrated_supported_consumer"
		return
	}
	if !r.ReplacementTested || !r.InventoryEvidence || !r.LicenseEvidence ||
		!r.HistoryEvidence || !r.SupportEvidence || !r.RollbackEvidence {
		r.RetirementBlocked = true
		r.BlockReason = "incomplete_retirement_evidence"
		return
	}
	if !r.ExplicitArchiveAuth || r.ArchiveAuthorizationRef == "" {
		r.RetirementBlocked = true
		r.BlockReason = "missing_explicit_archive_authorization"
		return
	}
	// Even with complete evidence, this package never performs archival — only records readiness.
	r.RetirementBlocked = true
	r.BlockReason = "archival_not_authorized_by_planning_package"
}

// HostCapabilityQualification tracks catalogue qualification vs host version (R06).
type HostCapabilityQualification struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	HostID              string            `json:"host_id"`
	QualifiedHostVersion string           `json:"qualified_host_version"`
	ObservedHostVersion string            `json:"observed_host_version"`
	CapabilityAreas     []string          `json:"capability_areas"`
	QualificationValid  bool              `json:"qualification_valid"`
	ManagedClaimsActive bool              `json:"managed_claims_active"`
	InvalidationReason  string            `json:"invalidation_reason,omitempty"`
	RecheckRequired     bool              `json:"recheck_required"`
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (h HostCapabilityQualification) Validate() error {
	if h.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown host capability qualification schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"qualification", h.ID}, {"host", h.HostID},
		{"qualified_version", h.QualifiedHostVersion},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if len(h.CapabilityAreas) == 0 || h.RecordedAt == "" {
		return errors.New("host capability qualification incomplete")
	}
	for _, a := range h.CapabilityAreas {
		switch a {
		case CapAreaCancellation, CapAreaUsage, CapAreaToolBoundary:
		default:
			return fmt.Errorf("unknown capability area %q", a)
		}
	}
	if !h.QualificationValid && h.ManagedClaimsActive {
		return errors.New("invalidated qualification cannot keep managed claims active")
	}
	return ValidateMetadata(h.Metadata)
}

// InvalidateOnHostVersionChange clears affected managed claims until rechecked (R06/T06).
func InvalidateOnHostVersionChange(h *HostCapabilityQualification) {
	if h.ObservedHostVersion == "" || h.ObservedHostVersion == h.QualifiedHostVersion {
		return
	}
	h.QualificationValid = false
	h.ManagedClaimsActive = false
	h.RecheckRequired = true
	h.InvalidationReason = "host_version_changed:" + h.QualifiedHostVersion + "→" + h.ObservedHostVersion
}

// ReleaseReadinessReport separates correctness / managed-op / performance (R07).
type ReleaseReadinessReport struct {
	SchemaVersion              int               `json:"schema_version"`
	ID                         string            `json:"id"`
	CandidateID                string            `json:"candidate_id"`
	CorrectnessDecision        string            `json:"correctness_decision"`
	ManagedOperationDecision   string            `json:"managed_operation_decision"`
	PerformancePromotionDecision string          `json:"performance_promotion_decision"`
	CompositeGreenBadge        bool              `json:"composite_green_badge"`
	GovernanceOnlyLabel        bool              `json:"governance_only_label"`
	MeasuredSpeedCostSuperiority bool            `json:"measured_speed_cost_superiority"`
	DeferredExperiments        []string          `json:"deferred_experiments,omitempty"`
	ImplementedBreaksOnly      bool              `json:"implemented_breaks_only"`
	Metadata                   map[string]string `json:"metadata,omitempty"`
	RecordedAt                 string            `json:"recorded_at"`
}

func (r ReleaseReadinessReport) Validate() error {
	if r.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown release readiness report schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"report", r.ID}, {"candidate", r.CandidateID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	for _, pair := range []struct{ label, v string }{
		{"correctness", r.CorrectnessDecision},
		{"managed_operation", r.ManagedOperationDecision},
		{"performance", r.PerformancePromotionDecision},
	} {
		switch pair.v {
		case DecisionPass, DecisionFail, DecisionBlocked, DecisionNull, DecisionNA:
		default:
			return fmt.Errorf("unknown %s decision", pair.label)
		}
	}
	if r.CompositeGreenBadge {
		return errors.New("composite green badge is forbidden")
	}
	if r.GovernanceOnlyLabel && r.MeasuredSpeedCostSuperiority {
		return errors.New("governance-only improvement cannot claim measured speed/cost superiority")
	}
	if !r.ImplementedBreaksOnly {
		return errors.New("readiness must cover only actually implemented breaks")
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return ValidateMetadata(r.Metadata)
}

// ComposeReadinessReport forces separate decisions and forbids composite green (R07/T07).
func ComposeReadinessReport(r *ReleaseReadinessReport) {
	r.CompositeGreenBadge = false
	r.ImplementedBreaksOnly = true
	if r.GovernanceOnlyLabel {
		r.MeasuredSpeedCostSuperiority = false
	}
	// Null/blocked performance or managed-op must not be concealed by correctness pass.
	if r.CorrectnessDecision == DecisionPass &&
		(r.ManagedOperationDecision == DecisionBlocked || r.PerformancePromotionDecision == DecisionNull) {
		r.CompositeGreenBadge = false
	}
}

// StrategyMethodRollback retains lineage/evidence/obligations under still-authorized contract (R08).
type StrategyMethodRollback struct {
	SchemaVersion          int               `json:"schema_version"`
	ID                     string            `json:"id"`
	StrategyVersion        string            `json:"strategy_version"`
	RollbackTarget         string            `json:"rollback_target"`
	TaskLineageRetained    bool              `json:"task_lineage_retained"`
	EvidenceHistoryRetained bool             `json:"evidence_history_retained"`
	OutstandingObligations []string          `json:"outstanding_obligations"`
	ActiveCandidateID      string            `json:"active_candidate_id,omitempty"`
	PendingCancellation    bool              `json:"pending_cancellation"`
	UnknownUsage           bool              `json:"unknown_usage"`
	LaterFailureRecorded   bool              `json:"later_failure_recorded"`
	StaleAcceptance        bool              `json:"stale_acceptance"`
	BudgetRefilled         bool              `json:"budget_refilled"`
	WiderAuthorityGranted  bool              `json:"wider_authority_granted"`
	StillAuthorizedContract string           `json:"still_authorized_contract"`
	Rejected               bool              `json:"rejected"`
	RejectReason           string            `json:"reject_reason,omitempty"`
	Metadata               map[string]string `json:"metadata,omitempty"`
	RecordedAt             string            `json:"recorded_at"`
}

func (s StrategyMethodRollback) Validate() error {
	if s.SchemaVersion != ReleaseSchemaVersion {
		return errors.New("unknown strategy method rollback schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"rollback", s.ID}, {"strategy", s.StrategyVersion}, {"target", s.RollbackTarget},
		{"contract", s.StillAuthorizedContract},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if !s.TaskLineageRetained || !s.EvidenceHistoryRetained {
		return errors.New("rollback must retain task lineage and evidence history")
	}
	if len(s.OutstandingObligations) == 0 {
		return errors.New("outstanding obligations under still-authorized contract required")
	}
	if s.StaleAcceptance || s.BudgetRefilled || s.WiderAuthorityGranted {
		return errors.New("rollback must not grant stale acceptance, budget refill, or wider authority")
	}
	if s.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	if s.Rejected && s.RejectReason == "" {
		return errors.New("rejected rollback requires reason")
	}
	return ValidateMetadata(s.Metadata)
}

// ApplyStrategyRollback enforces R08/T08 retention without stale authority expansion.
func ApplyStrategyRollback(s *StrategyMethodRollback) {
	s.TaskLineageRetained = true
	s.EvidenceHistoryRetained = true
	s.StaleAcceptance = false
	s.BudgetRefilled = false
	s.WiderAuthorityGranted = false
	if s.ActiveCandidateID != "" || s.PendingCancellation || s.UnknownUsage {
		if len(s.OutstandingObligations) == 0 {
			s.OutstandingObligations = []string{"retain_active_candidate", "resolve_pending_cancellation", "account_unknown_usage"}
		}
	}
	if s.LaterFailureRecorded {
		s.Rejected = false // later failure is recorded under retained evidence, not a rollback reject
	}
}

// Decode helpers.

func DecodeMigrationAttempt(raw []byte) (MigrationAttempt, error) {
	var m MigrationAttempt
	if e := StrictJSON(raw, &m); e != nil {
		return m, e
	}
	return m, m.Validate()
}

func DecodeMigrationRecovery(raw []byte) (MigrationRecovery, error) {
	var r MigrationRecovery
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeReleaseCandidate(raw []byte) (ReleaseCandidate, error) {
	var c ReleaseCandidate
	if e := StrictJSON(raw, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}

func DecodePromotionAuthorization(raw []byte) (PromotionAuthorization, error) {
	var p PromotionAuthorization
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeRetirementRequest(raw []byte) (RetirementRequest, error) {
	var r RetirementRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeHostCapabilityQualification(raw []byte) (HostCapabilityQualification, error) {
	var h HostCapabilityQualification
	if e := StrictJSON(raw, &h); e != nil {
		return h, e
	}
	return h, h.Validate()
}

func DecodeReleaseReadinessReport(raw []byte) (ReleaseReadinessReport, error) {
	var r ReleaseReadinessReport
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeStrategyMethodRollback(raw []byte) (StrategyMethodRollback, error) {
	var s StrategyMethodRollback
	if e := StrictJSON(raw, &s); e != nil {
		return s, e
	}
	return s, s.Validate()
}

var _ = json.Marshal
