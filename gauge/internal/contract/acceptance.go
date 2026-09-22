package contract

import (
	"encoding/json"
	"errors"
	"fmt"
	"sort"
)

// AcceptanceSchemaVersion is the typed V4-14 acceptance namespace version under schema 2.
const AcceptanceSchemaVersion = 1

// Check outcomes — observation only; authored prose cannot invent these.
const (
	OutcomePass      = "pass"
	OutcomeFail      = "fail"
	OutcomeError     = "error"
	OutcomeCancelled = "cancelled"
	OutcomeSkipped   = "skipped"
)

// Verification grades separate execution integrity from acceptance adequacy.
const (
	GradeTrustedIntegrity   = "trusted_integrity"
	GradeUntrustedIntegrity = "untrusted_integrity"
	GradeAdequacyQualified  = "adequacy_qualified"
	GradeAdequacyWithheld   = "adequacy_withheld"
	GradeWithheld           = "withheld"
)

// Isolation modes — label/directory alone is never supported enforcement.
const (
	IsolationEnforced = "enforced_boundary"
	IsolationLabel    = "label_only"
	IsolationDirectory = "directory_without_enforcement"
	IsolationAbsent   = "absent"
)

// Application gate results.
const (
	ApplyAllowed           = "allowed"
	ApplyRequireRevalidate = "require_revalidation"
	ApplyDenied            = "denied"
)

// Definition blocker kinds (R10).
const (
	BlockerAmbiguousBrief       = "ambiguous_brief"
	BlockerAmbiguousOracle      = "ambiguous_oracle"
	BlockerMissingDiscriminator = "missing_behavioral_discriminator"
)

// CandidateContentEntry records one path contribution to a freeze digest.
type CandidateContentEntry struct {
	Path     string `json:"path"`
	Kind     string `json:"kind"` // tracked | untracked | config | mode | symlink
	Digest   string `json:"digest"`
	Mode     string `json:"mode,omitempty"`
	Symlink  string `json:"symlink_target,omitempty"`
}

// FrozenCandidate binds verification to an immutable content identity (R01).
type FrozenCandidate struct {
	SchemaVersion   int                     `json:"schema_version"`
	ID              string                  `json:"id"`
	RootID          string                  `json:"root_id"`
	AssignmentID    string                  `json:"assignment_id,omitempty"`
	WorkspaceRoot   string                  `json:"workspace_root"`
	Entries         []CandidateContentEntry `json:"entries"`
	ContentDigest   string                  `json:"content_digest"`
	AcceptanceID    string                  `json:"acceptance_id"`
	EnvironmentID   string                  `json:"environment_id"`
	FrozenAt        string                  `json:"frozen_at"`
	Exclusions      []string                `json:"exclusions,omitempty"` // build/temp only
}

func (c FrozenCandidate) Validate() error {
	if c.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown frozen candidate schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"candidate", c.ID}, {"root", c.RootID}, {"acceptance", c.AcceptanceID}, {"environment", c.EnvironmentID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if e := validateID("assignment", c.AssignmentID, false); e != nil {
		return e
	}
	if c.WorkspaceRoot == "" || c.ContentDigest == "" || c.FrozenAt == "" {
		return errors.New("frozen candidate incomplete")
	}
	if len(c.Entries) == 0 {
		return errors.New("frozen candidate requires content entries")
	}
	return nil
}

// ComputeContentDigest is the deterministic freeze identity over sorted entries.
func ComputeContentDigest(entries []CandidateContentEntry) string {
	sorted := append([]CandidateContentEntry(nil), entries...)
	sort.Slice(sorted, func(i, j int) bool {
		if sorted[i].Path != sorted[j].Path {
			return sorted[i].Path < sorted[j].Path
		}
		return sorted[i].Kind < sorted[j].Kind
	})
	raw, _ := json.Marshal(sorted)
	return Digest(raw)
}

// AcceptancePackage names requested behavior, exclusions, oracle, environment,
// review obligations and required evidence (ARCHITECTURE §Acceptance).
type AcceptancePackage struct {
	SchemaVersion          int      `json:"schema_version"`
	ID                     string   `json:"id"`
	RequestedBehavior      string   `json:"requested_behavior"`
	Exclusions             []string `json:"exclusions,omitempty"`
	OracleOrigin           string   `json:"oracle_origin"`
	OracleVersion          string   `json:"oracle_version"`
	EnvironmentID          string   `json:"environment_id"`
	RequiredChecks         []string `json:"required_checks"`
	RequiresBehaviorGate   bool     `json:"requires_behavior_gate"`
	ReviewObligations      []string `json:"review_obligations,omitempty"`
	InvalidationDeps       []string `json:"invalidation_deps,omitempty"`
	BehavioralDiscriminator string  `json:"behavioral_discriminator,omitempty"`
	Qualified              bool     `json:"qualified"`
}

func (p AcceptancePackage) Validate() error {
	if p.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown acceptance package schema version")
	}
	if e := validateID("acceptance", p.ID, true); e != nil {
		return e
	}
	if e := validateID("environment", p.EnvironmentID, true); e != nil {
		return e
	}
	if p.RequestedBehavior == "" || p.OracleOrigin == "" || p.OracleVersion == "" {
		return errors.New("acceptance package incomplete")
	}
	if len(p.RequiredChecks) == 0 {
		return errors.New("acceptance package requires checks")
	}
	return nil
}

// EnvironmentIdentity binds the declared execution environment.
type EnvironmentIdentity struct {
	SchemaVersion int    `json:"schema_version"`
	ID            string `json:"id"`
	Kind          string `json:"kind"` // fixture | declared
	Label         string `json:"label"`
	Provenance    string `json:"provenance"` // present | absent
}

func (e EnvironmentIdentity) Validate() error {
	if e.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown environment schema version")
	}
	return validateID("environment", e.ID, true)
}

// IsolationCapability records whether required isolation/provenance is enforced (R04).
type IsolationCapability struct {
	Mode              string   `json:"mode"`
	Enforced          bool     `json:"enforced"`
	ProtectedPaths    []string `json:"protected_paths,omitempty"`
	AllowWritePaths   []string `json:"allow_write_paths,omitempty"`
	ContextProvenance string   `json:"context_provenance"` // present | absent
	Detail            string   `json:"detail,omitempty"`
}

// CheckInvocationProvenance records how a check was actually invoked (R03).
type CheckInvocationProvenance struct {
	RunnerID       string `json:"runner_id"`
	InvocationID   string `json:"invocation_id"`
	CandidateID    string `json:"candidate_id"`
	AcceptanceID   string `json:"acceptance_id"`
	EnvironmentID  string `json:"environment_id"`
	IsolationMode  string `json:"isolation_mode"`
	ObservedAt     string `json:"observed_at"`
	CommandDigest  string `json:"command_digest,omitempty"`
	AuthoredProse  string `json:"authored_prose,omitempty"` // never substitutes for Outcome
}

// CheckReceipt is the observed finish record for one check (R03).
type CheckReceipt struct {
	SchemaVersion int                       `json:"schema_version"`
	ID            string                    `json:"id"`
	CheckID       string                    `json:"check_id"`
	Outcome       string                    `json:"outcome"`
	Provenance    CheckInvocationProvenance `json:"provenance"`
	IntegrityGrade string                   `json:"integrity_grade"`
	Notes         []string                  `json:"notes,omitempty"`
}

func (r CheckReceipt) Validate() error {
	if r.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown check receipt schema version")
	}
	if e := validateID("receipt", r.ID, true); e != nil {
		return e
	}
	if e := validateID("check", r.CheckID, true); e != nil {
		return e
	}
	switch r.Outcome {
	case OutcomePass, OutcomeFail, OutcomeError, OutcomeCancelled, OutcomeSkipped:
	default:
		return fmt.Errorf("unknown check outcome %q", r.Outcome)
	}
	return nil
}

// VerificationGradeReport withholds trusted grade when isolation/provenance lacking (R04).
type VerificationGradeReport struct {
	IntegrityGrade string   `json:"integrity_grade"`
	AdequacyGrade  string   `json:"adequacy_grade"`
	Trusted        bool     `json:"trusted"`
	Reasons        []string `json:"reasons,omitempty"`
}

// OracleTrial is one qualification trial on a known-outcome candidate (R07).
type OracleTrial struct {
	CandidateLabel string `json:"candidate_label"` // valid | stub | missing_edge | regression
	Expected       string `json:"expected"`        // pass | fail
	Observed       string `json:"observed"`
	Discriminates  bool   `json:"discriminates"`
}

// OracleQualification records coverage on acceptable and defective candidates (R07).
type OracleQualification struct {
	SchemaVersion   int           `json:"schema_version"`
	ID              string        `json:"id"`
	AcceptanceID    string        `json:"acceptance_id"`
	Trials          []OracleTrial `json:"trials"`
	Qualified       bool          `json:"qualified"`
	FailReasons     []string      `json:"fail_reasons,omitempty"`
	RecordedAt      string        `json:"recorded_at"`
}

func (q OracleQualification) Validate() error {
	if q.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown oracle qualification schema version")
	}
	if e := validateID("qualification", q.ID, true); e != nil {
		return e
	}
	if e := validateID("acceptance", q.AcceptanceID, true); e != nil {
		return e
	}
	return nil
}

// AcceptanceOwnerReview records authorized review of maker test/def changes (R08).
type AcceptanceOwnerReview struct {
	SchemaVersion  int      `json:"schema_version"`
	ID             string   `json:"id"`
	AcceptanceID   string   `json:"acceptance_id"`
	OwnerID        string   `json:"owner_id"`
	ChangeKind     string   `json:"change_kind"` // deletion | relaxed_assertion | legitimate_expectation
	MakerApproved  bool     `json:"maker_approved"`
	OwnerApproved  bool     `json:"owner_approved"`
	InvalidatesOld bool     `json:"invalidates_old_evidence"`
	Detail         string   `json:"detail,omitempty"`
	RecordedAt     string   `json:"recorded_at"`
}

func (r AcceptanceOwnerReview) Validate() error {
	if r.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown owner review schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"review", r.ID}, {"acceptance", r.AcceptanceID}, {"owner", r.OwnerID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	return nil
}

// DefinitionBlocker reports criteria that cannot distinguish requested vs incomplete (R10).
type DefinitionBlocker struct {
	SchemaVersion int    `json:"schema_version"`
	ID            string `json:"id"`
	AcceptanceID  string `json:"acceptance_id"`
	Kind          string `json:"kind"`
	Detail        string `json:"detail"`
	RecordedAt    string `json:"recorded_at"`
}

func (b DefinitionBlocker) Validate() error {
	if b.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown definition blocker schema version")
	}
	if e := validateID("blocker", b.ID, true); e != nil {
		return e
	}
	if e := validateID("acceptance", b.AcceptanceID, true); e != nil {
		return e
	}
	switch b.Kind {
	case BlockerAmbiguousBrief, BlockerAmbiguousOracle, BlockerMissingDiscriminator:
	default:
		return fmt.Errorf("unknown blocker kind %q", b.Kind)
	}
	return nil
}

// ApplicationDecision gates candidate application against the live target base (R05).
type ApplicationDecision struct {
	Status            string   `json:"status"`
	CandidateID       string   `json:"candidate_id"`
	FrozenBaseDigest  string   `json:"frozen_base_digest"`
	CurrentBaseDigest string   `json:"current_base_digest"`
	Reasons           []string `json:"reasons,omitempty"`
}

// HumanAcceptanceReport preserves distinct integrity/provenance/acceptance (R06).
type HumanAcceptanceReport struct {
	SchemaVersion       int            `json:"schema_version"`
	CandidateID         string         `json:"candidate_id"`
	ContentDigest       string         `json:"content_digest"`
	ArtifactIntegrity   Grade          `json:"artifact_integrity"`
	ExecutionProvenance Grade          `json:"execution_provenance"`
	AcceptanceStatus    Acceptance     `json:"acceptance_status"`
	Checks              []Check        `json:"checks"`
	AuthorAuthenticated bool           `json:"author_authenticated"`
	SemanticCorrectness string         `json:"semantic_correctness"` // never claimed from digest alone
	Notes               []string       `json:"notes,omitempty"`
	Canonical           map[string]any `json:"canonical,omitempty"`
}

// FreezeRequest is the CLI/controller input to freeze a candidate.
type FreezeRequest struct {
	SchemaVersion int                     `json:"schema_version"`
	CandidateID   string                  `json:"candidate_id"`
	RootID        string                  `json:"root_id"`
	AssignmentID  string                  `json:"assignment_id,omitempty"`
	WorkspaceRoot string                  `json:"workspace_root"`
	Entries       []CandidateContentEntry `json:"entries"`
	AcceptanceID  string                  `json:"acceptance_id"`
	EnvironmentID string                  `json:"environment_id"`
	Exclusions    []string                `json:"exclusions,omitempty"`
	BaseDigest    string                  `json:"base_digest,omitempty"`
	RecordedAt    string                  `json:"recorded_at,omitempty"`
}

func (r FreezeRequest) Validate() error {
	if r.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown freeze request schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"candidate", r.CandidateID}, {"root", r.RootID}, {"acceptance", r.AcceptanceID}, {"environment", r.EnvironmentID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if r.WorkspaceRoot == "" || len(r.Entries) == 0 {
		return errors.New("freeze request incomplete")
	}
	return nil
}

// RunCheckRequest starts/finishes a bound verification check.
type RunCheckRequest struct {
	SchemaVersion  int    `json:"schema_version"`
	ReceiptID      string `json:"receipt_id"`
	CheckID        string `json:"check_id"`
	CandidateID    string `json:"candidate_id"`
	AcceptanceID   string `json:"acceptance_id"`
	EnvironmentID  string `json:"environment_id"`
	RunnerID       string `json:"runner_id"`
	InvocationID   string `json:"invocation_id"`
	ObservedOutcome string `json:"observed_outcome"`
	AuthoredProse  string `json:"authored_prose,omitempty"`
	IsolationMode  string `json:"isolation_mode"`
	CommandDigest  string `json:"command_digest,omitempty"`
	BehaviorObserved bool `json:"behavior_observed"`
	RecordedAt     string `json:"recorded_at,omitempty"`
}

func (r RunCheckRequest) Validate() error {
	if r.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown run-check request schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"receipt", r.ReceiptID}, {"check", r.CheckID}, {"candidate", r.CandidateID},
		{"acceptance", r.AcceptanceID}, {"environment", r.EnvironmentID},
		{"runner", r.RunnerID}, {"invocation", r.InvocationID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	return nil
}

// QualifyRequest asks the verifier to qualify an acceptance package (R07).
type QualifyRequest struct {
	SchemaVersion int           `json:"schema_version"`
	ID            string        `json:"id"`
	AcceptanceID  string        `json:"acceptance_id"`
	Trials        []OracleTrial `json:"trials"`
	RecordedAt    string        `json:"recorded_at,omitempty"`
}

func (r QualifyRequest) Validate() error {
	if r.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown qualify request schema version")
	}
	if e := validateID("qualification", r.ID, true); e != nil {
		return e
	}
	if e := validateID("acceptance", r.AcceptanceID, true); e != nil {
		return e
	}
	if len(r.Trials) == 0 {
		return errors.New("qualification requires trials")
	}
	return nil
}

// ApplyRequest asks whether a frozen candidate may be applied to the target base (R05).
type ApplyRequest struct {
	SchemaVersion     int    `json:"schema_version"`
	CandidateID       string `json:"candidate_id"`
	CurrentBaseDigest string `json:"current_base_digest"`
	TargetDirty       bool   `json:"target_dirty"`
	HasConflicts      bool   `json:"has_conflicts"`
}

func (r ApplyRequest) Validate() error {
	if r.SchemaVersion != AcceptanceSchemaVersion {
		return errors.New("unknown apply request schema version")
	}
	return validateID("candidate", r.CandidateID, true)
}

// Decode helpers.
func DecodeFreezeRequest(raw []byte) (FreezeRequest, error) {
	var r FreezeRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeRunCheckRequest(raw []byte) (RunCheckRequest, error) {
	var r RunCheckRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeQualifyRequest(raw []byte) (QualifyRequest, error) {
	var r QualifyRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeApplyRequest(raw []byte) (ApplyRequest, error) {
	var r ApplyRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeAcceptancePackage(raw []byte) (AcceptancePackage, error) {
	var p AcceptancePackage
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeOwnerReview(raw []byte) (AcceptanceOwnerReview, error) {
	var r AcceptanceOwnerReview
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}
