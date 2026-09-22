package contract

import (
	"errors"
	"path/filepath"
	"strings"
)

// ViviSchemaVersion is the typed V4-17 Vivi-modes namespace version under schema 2.
const ViviSchemaVersion = 1

// ViviModesContractID is the versioned method-mode contract identity.
const ViviModesContractID = "vivi-modes@1"

// Named opt-in workspace / proposal modes (R01, R02). Continuity is orthogonal (R03).
const (
	ViviModeProposalOnly       = "proposal_only"
	ViviModeCandidateWorkspace = "candidate_workspace"
)

// Context strategies (R06). Unsupported host compaction stays unknown, not completed.
const (
	ContextStrategyContinue         = "continue"
	ContextStrategyNativeCompaction = "native_compaction"
	ContextStrategyFreshWorker      = "fresh_worker"
)

// Context transition observation outcomes (R06).
const (
	ContextTransitionObserved = "observed"
	ContextTransitionUnknown  = "unknown"
	ContextTransitionFailed   = "failed"
)

// Authority / greenfield boundaries Vivi must return rather than evade (R05).
const (
	BoundaryNovelArchitecture = "novel_architecture"
	BoundaryPushDeploy        = "push_deploy"
	BoundaryExternalSpend     = "external_spend"
	BoundaryExpandedScope     = "expanded_scope"
	BoundaryGreenfield        = "greenfield"
	BoundaryPublication       = "publication"
)

// Verification evidence grades — only observed grades may be claimed (R04).
const (
	EvidenceGradeNone       = "none"
	EvidenceGradeFixture    = "fixture"
	EvidenceGradeSeparated  = "separated_checker"
	EvidenceGradeIndependent = "independent" // never granted by rename/fork alone
)

// Edit attempt outcomes within candidate-workspace mode (R01).
const (
	EditAccepted            = "accepted"
	EditRejectedUserTree    = "rejected_user_tree_escape"
	EditRejectedProtected   = "rejected_protected_criteria"
	EditRejectedUnrelated   = "rejected_unrelated_dirty"
	EditRejectedProposalOnly = "rejected_proposal_only"
	EditRejectedUnauthorized = "rejected_unauthorized_workspace"
)

// ViviModeSelection records a named opt-in mode with scoped authorization.
type ViviModeSelection struct {
	SchemaVersion         int               `json:"schema_version"`
	ID                    string            `json:"id"`
	SessionID             string            `json:"session_id"`
	Mode                  string            `json:"mode"`
	ContractVersion       string            `json:"contract_version"`
	AuthorizedWorkspace   string            `json:"authorized_workspace,omitempty"`
	ScopedAuthorization   bool              `json:"scoped_authorization"`
	UserTreeRoot          string            `json:"user_tree_root,omitempty"`
	ProtectedPaths        []string          `json:"protected_paths,omitempty"`
	PublicationAuthority  bool              `json:"publication_authority"` // Gauge never grants this
	Metadata              map[string]string `json:"metadata,omitempty"`
	RecordedAt            string            `json:"recorded_at"`
}

func (m ViviModeSelection) Validate() error {
	if m.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi mode schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"mode_selection", m.ID}, {"session", m.SessionID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch m.Mode {
	case ViviModeProposalOnly, ViviModeCandidateWorkspace:
	default:
		return errors.New("unknown vivi mode; only named opt-in modes are supported")
	}
	if m.ContractVersion != ViviModesContractID {
		return errors.New("vivi contract version must be vivi-modes@1")
	}
	if m.PublicationAuthority {
		return errors.New("Gauge does not grant publication authority")
	}
	if m.Mode == ViviModeCandidateWorkspace {
		if !m.ScopedAuthorization {
			return errors.New("candidate-workspace mode requires scoped authorization")
		}
		if m.AuthorizedWorkspace == "" {
			return errors.New("candidate-workspace mode requires authorized_workspace")
		}
		if m.UserTreeRoot == "" {
			return errors.New("candidate-workspace mode requires user_tree_root")
		}
	}
	if m.RecordedAt == "" {
		return errors.New("mode recorded_at required")
	}
	if e := ValidateMetadata(m.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviEditAttempt records a scoped edit under candidate-workspace or proposal-only (R01/R02).
type ViviEditAttempt struct {
	SchemaVersion   int               `json:"schema_version"`
	ID              string            `json:"id"`
	SessionID       string            `json:"session_id"`
	ModeID          string            `json:"mode_id"`
	TargetPath      string            `json:"target_path"`
	RelativeToAuth  string            `json:"relative_to_authorized,omitempty"`
	Outcome         string            `json:"outcome"`
	AppliedToUser   bool              `json:"applied_to_user_tree"`
	DirtyUnrelated  bool              `json:"dirty_unrelated"`
	ContentDigest   string            `json:"content_digest,omitempty"`
	Metadata        map[string]string `json:"metadata,omitempty"`
	RecordedAt      string            `json:"recorded_at"`
}

func (a ViviEditAttempt) Validate() error {
	if a.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi edit schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"edit", a.ID}, {"session", a.SessionID}, {"mode", a.ModeID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if a.TargetPath == "" || a.Outcome == "" || a.RecordedAt == "" {
		return errors.New("edit target_path, outcome, and recorded_at required")
	}
	switch a.Outcome {
	case EditAccepted, EditRejectedUserTree, EditRejectedProtected, EditRejectedUnrelated,
		EditRejectedProposalOnly, EditRejectedUnauthorized:
	default:
		return errors.New("unknown vivi edit outcome")
	}
	if a.Outcome == EditAccepted && a.AppliedToUser {
		return errors.New("accepted candidate edit must not apply to user tree in V4-17 modes")
	}
	if a.Outcome != EditAccepted && a.AppliedToUser {
		return errors.New("rejected edit must not apply to user tree")
	}
	if e := ValidateMetadata(a.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviProposal is a candidate proposal that does not mutate the user tree (R02).
type ViviProposal struct {
	SchemaVersion       int               `json:"schema_version"`
	ID                  string            `json:"id"`
	SessionID           string            `json:"session_id"`
	ModeID              string            `json:"mode_id"`
	DiffDigest          string            `json:"diff_digest"`
	AppliedToUserTree   bool              `json:"applied_to_user_tree"`
	StandaloneCompatible bool             `json:"standalone_compatible"`
	ApplicationOpID     string            `json:"application_op_id,omitempty"` // separate parent-authorized apply
	Metadata            map[string]string `json:"metadata,omitempty"`
	RecordedAt          string            `json:"recorded_at"`
}

func (p ViviProposal) Validate() error {
	if p.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi proposal schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"proposal", p.ID}, {"session", p.SessionID}, {"mode", p.ModeID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if p.DiffDigest == "" || p.RecordedAt == "" {
		return errors.New("proposal diff_digest and recorded_at required")
	}
	if p.AppliedToUserTree {
		return errors.New("proposal-only mode must not apply to user tree")
	}
	if e := ValidateMetadata(p.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviProposalApplication is a separate parent-authorized apply operation (R02).
type ViviProposalApplication struct {
	SchemaVersion     int               `json:"schema_version"`
	ID                string            `json:"id"`
	SessionID         string            `json:"session_id"`
	ProposalID        string            `json:"proposal_id"`
	ParentAuthorized  bool              `json:"parent_authorized"`
	AppliedToUserTree bool              `json:"applied_to_user_tree"`
	RejectedReason    string            `json:"rejected_reason,omitempty"`
	Metadata          map[string]string `json:"metadata,omitempty"`
	RecordedAt        string            `json:"recorded_at"`
}

func (a ViviProposalApplication) Validate() error {
	if a.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi proposal application schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"application", a.ID}, {"session", a.SessionID}, {"proposal", a.ProposalID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if a.RecordedAt == "" {
		return errors.New("application recorded_at required")
	}
	if a.AppliedToUserTree && !a.ParentAuthorized {
		return errors.New("user-tree application requires parent authorization")
	}
	if e := ValidateMetadata(a.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviContinuityState retains decisions and failure history across repair attempts (R03).
// Context resets are recorded without resetting root accounting.
type ViviContinuityState struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	SessionID          string            `json:"session_id"`
	RootBudgetID       string            `json:"root_budget_id"`
	ContinuityMode     bool              `json:"continuity_mode"`
	Decisions          []string          `json:"decisions"`
	FailureHistory     []string          `json:"failure_history"`
	RepairAttempts     int               `json:"repair_attempts"`
	ContextResets      int               `json:"context_resets"`
	ResetEvents        []string          `json:"reset_events,omitempty"`
	AccountingPreserved bool             `json:"accounting_preserved"`
	WarmContext        bool              `json:"warm_context"`
	Metadata           map[string]string `json:"metadata,omitempty"`
	RecordedAt         string            `json:"recorded_at"`
}

func (c ViviContinuityState) Validate() error {
	if c.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi continuity schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"continuity", c.ID}, {"session", c.SessionID}, {"root_budget", c.RootBudgetID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if c.RecordedAt == "" {
		return errors.New("continuity recorded_at required")
	}
	if c.RepairAttempts < 0 || c.ContextResets < 0 {
		return errors.New("repair_attempts and context_resets must be non-negative")
	}
	if c.ContextResets > 0 && len(c.ResetEvents) == 0 {
		return errors.New("context resets must be recorded as events")
	}
	if c.ContextResets > 0 && !c.AccountingPreserved {
		return errors.New("context reset must preserve root accounting")
	}
	if c.ContinuityMode && c.WarmContext && len(c.Decisions) == 0 && len(c.FailureHistory) == 0 && c.RepairAttempts == 0 {
		return errors.New("warm continuity must retain decisions or failure history")
	}
	if e := ValidateMetadata(c.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviVerificationSubmission submits a candidate to the controller-managed boundary (R04).
// Maker rename/fork cannot mint independent evidence.
type ViviVerificationSubmission struct {
	SchemaVersion        int               `json:"schema_version"`
	ID                   string            `json:"id"`
	SessionID            string            `json:"session_id"`
	CandidateID          string            `json:"candidate_id"`
	MakerWorkerID        string            `json:"maker_worker_id"`
	CheckerWorkerID      string            `json:"checker_worker_id"`
	MakerRenamedAsChecker bool             `json:"maker_renamed_as_checker"`
	MakerForkedAsChecker  bool             `json:"maker_forked_as_checker"`
	ControllerManaged    bool              `json:"controller_managed"`
	EvidenceGrade        string            `json:"evidence_grade"`
	ObservedEvidenceGrade string           `json:"observed_evidence_grade"`
	Rejected             bool              `json:"rejected"`
	RejectedReason       string            `json:"rejected_reason,omitempty"`
	Metadata             map[string]string `json:"metadata,omitempty"`
	RecordedAt           string            `json:"recorded_at"`
}

func (v ViviVerificationSubmission) Validate() error {
	if v.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi verification schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"verification", v.ID}, {"session", v.SessionID}, {"candidate", v.CandidateID},
		{"maker", v.MakerWorkerID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if v.RecordedAt == "" {
		return errors.New("verification recorded_at required")
	}
	switch v.EvidenceGrade {
	case EvidenceGradeNone, EvidenceGradeFixture, EvidenceGradeSeparated, EvidenceGradeIndependent:
	default:
		return errors.New("unknown evidence grade")
	}
	switch v.ObservedEvidenceGrade {
	case EvidenceGradeNone, EvidenceGradeFixture, EvidenceGradeSeparated, EvidenceGradeIndependent:
	default:
		return errors.New("unknown observed evidence grade")
	}
	if v.MakerRenamedAsChecker || v.MakerForkedAsChecker {
		if !v.Rejected {
			return errors.New("maker rename/fork must fail independent verification")
		}
		if v.EvidenceGrade == EvidenceGradeIndependent {
			return errors.New("maker rename/fork cannot claim independent evidence")
		}
	}
	if v.EvidenceGrade == EvidenceGradeIndependent && v.ObservedEvidenceGrade != EvidenceGradeIndependent {
		return errors.New("independent grade requires actually observed independence")
	}
	if v.EvidenceGrade != EvidenceGradeNone && v.EvidenceGrade != v.ObservedEvidenceGrade && !v.Rejected {
		return errors.New("claimed evidence grade must not exceed observed grade")
	}
	if !v.ControllerManaged && !v.Rejected {
		return errors.New("accepted verification must be controller-managed")
	}
	if e := ValidateMetadata(v.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviBoundaryRefusal returns the applicable authority/greenfield boundary (R05).
type ViviBoundaryRefusal struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	SessionID          string            `json:"session_id"`
	Boundary           string            `json:"boundary"`
	TaskDescription    string            `json:"task_description"`
	MethodComposition  []string          `json:"method_composition,omitempty"`
	EvadedViaComposition bool            `json:"evaded_via_composition"`
	Refused            bool              `json:"refused"`
	Metadata           map[string]string `json:"metadata,omitempty"`
	RecordedAt         string            `json:"recorded_at"`
}

func (b ViviBoundaryRefusal) Validate() error {
	if b.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi boundary schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"boundary", b.ID}, {"session", b.SessionID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch b.Boundary {
	case BoundaryNovelArchitecture, BoundaryPushDeploy, BoundaryExternalSpend,
		BoundaryExpandedScope, BoundaryGreenfield, BoundaryPublication:
	default:
		return errors.New("unknown vivi authority boundary")
	}
	if b.TaskDescription == "" || b.RecordedAt == "" {
		return errors.New("boundary task_description and recorded_at required")
	}
	if b.EvadedViaComposition {
		return errors.New("method composition must not evade declared boundaries")
	}
	if !b.Refused {
		return errors.New("out-of-authority task must refuse with applicable boundary")
	}
	if e := ValidateMetadata(b.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviContextStrategyRecord binds strategy version to observed transition boundary (R06).
type ViviContextStrategyRecord struct {
	SchemaVersion        int               `json:"schema_version"`
	ID                   string            `json:"id"`
	SessionID            string            `json:"session_id"`
	Strategy             string            `json:"strategy"`
	StrategyVersion      string            `json:"strategy_version"`
	TransitionBoundary   string            `json:"transition_boundary"` // observed | unknown | failed
	HostCompactionSupport string           `json:"host_compaction_support"` // supported | unsupported | unknown
	ClaimedCompleted     bool              `json:"claimed_completed"`
	Metadata             map[string]string `json:"metadata,omitempty"`
	RecordedAt           string            `json:"recorded_at"`
}

func (c ViviContextStrategyRecord) Validate() error {
	if c.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi context strategy schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"context_strategy", c.ID}, {"session", c.SessionID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	switch c.Strategy {
	case ContextStrategyContinue, ContextStrategyNativeCompaction, ContextStrategyFreshWorker:
	default:
		return errors.New("unknown context strategy")
	}
	if c.StrategyVersion == "" || c.RecordedAt == "" {
		return errors.New("strategy_version and recorded_at required")
	}
	switch c.TransitionBoundary {
	case ContextTransitionObserved, ContextTransitionUnknown, ContextTransitionFailed:
	default:
		return errors.New("unknown context transition boundary")
	}
	switch c.HostCompactionSupport {
	case "supported", "unsupported", "unknown":
	default:
		return errors.New("host_compaction_support must be supported|unsupported|unknown")
	}
	if c.Strategy == ContextStrategyNativeCompaction && c.HostCompactionSupport == "unsupported" {
		if c.TransitionBoundary != ContextTransitionUnknown {
			return errors.New("unsupported host compaction must be unknown, not claimed completed")
		}
		if c.ClaimedCompleted {
			return errors.New("unsupported host compaction must not claim completed")
		}
	}
	if c.ClaimedCompleted && c.TransitionBoundary != ContextTransitionObserved {
		return errors.New("completed claim requires observed transition")
	}
	if e := ValidateMetadata(c.Metadata); e != nil {
		return e
	}
	return nil
}

// ViviSession is the top-level fixture session binding modes and continuity.
type ViviSession struct {
	SchemaVersion   int               `json:"schema_version"`
	ID              string            `json:"id"`
	RootBudgetID    string            `json:"root_budget_id"`
	ContractVersion string            `json:"contract_version"`
	ActiveModeID    string            `json:"active_mode_id,omitempty"`
	ContinuityID    string            `json:"continuity_id,omitempty"`
	LiveBlocked     bool              `json:"live_blocked"`
	Metadata        map[string]string `json:"metadata,omitempty"`
	RecordedAt      string            `json:"recorded_at"`
}

func (s ViviSession) Validate() error {
	if s.SchemaVersion != ViviSchemaVersion {
		return errors.New("unknown vivi session schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"session", s.ID}, {"root_budget", s.RootBudgetID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if s.ContractVersion != ViviModesContractID {
		return errors.New("session contract version must be vivi-modes@1")
	}
	if !s.LiveBlocked {
		return errors.New("V4-17 fixture scope keeps live blocked")
	}
	if s.RecordedAt == "" {
		return errors.New("session recorded_at required")
	}
	if e := ValidateMetadata(s.Metadata); e != nil {
		return e
	}
	return nil
}

// ClassifyCandidatePath decides whether a path is inside the authorized workspace (R01).
func ClassifyCandidatePath(userTree, authorizedWS, target string, protected []string) (outcome, rel string, err error) {
	if userTree == "" || authorizedWS == "" || target == "" {
		return "", "", errors.New("user tree, authorized workspace, and target required")
	}
	absUser, e := filepath.Abs(userTree)
	if e != nil {
		return "", "", e
	}
	absAuth, e := filepath.Abs(authorizedWS)
	if e != nil {
		return "", "", e
	}
	absTarget, e := filepath.Abs(target)
	if e != nil {
		return "", "", e
	}
	for _, p := range protected {
		absP, e := filepath.Abs(p)
		if e != nil {
			return "", "", e
		}
		if absTarget == absP || strings.HasPrefix(absTarget, absP+string(filepath.Separator)) {
			return EditRejectedProtected, "", nil
		}
	}
	rel, e = filepath.Rel(absAuth, absTarget)
	if e != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		// Outside authorized workspace — check if under user tree (escape) or unrelated.
		urel, ue := filepath.Rel(absUser, absTarget)
		if ue != nil || urel == ".." || strings.HasPrefix(urel, ".."+string(filepath.Separator)) {
			return EditRejectedUnrelated, "", nil
		}
		return EditRejectedUserTree, "", nil
	}
	return EditAccepted, rel, nil
}

// ClassifyTaskBoundary maps a task description to a declared refusal boundary (R05).
func ClassifyTaskBoundary(task string) (string, bool) {
	lower := strings.ToLower(task)
	switch {
	case strings.Contains(lower, "novel architecture") || strings.Contains(lower, "design from scratch") ||
		strings.Contains(lower, "greenfield"):
		if strings.Contains(lower, "greenfield") {
			return BoundaryGreenfield, true
		}
		return BoundaryNovelArchitecture, true
	case strings.Contains(lower, "push") || strings.Contains(lower, "deploy") || strings.Contains(lower, "release"):
		return BoundaryPushDeploy, true
	case strings.Contains(lower, "spend") || strings.Contains(lower, "billing") || strings.Contains(lower, "paid"):
		return BoundaryExternalSpend, true
	case strings.Contains(lower, "expand scope") || strings.Contains(lower, "expanded scope") ||
		strings.Contains(lower, "out of scope"):
		return BoundaryExpandedScope, true
	case strings.Contains(lower, "publish") || strings.Contains(lower, "publication"):
		return BoundaryPublication, true
	default:
		return "", false
	}
}

func DecodeViviModeSelection(raw []byte) (ViviModeSelection, error) {
	var m ViviModeSelection
	if e := StrictJSON(raw, &m); e != nil {
		return m, e
	}
	return m, m.Validate()
}

func DecodeViviProposal(raw []byte) (ViviProposal, error) {
	var p ViviProposal
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

func DecodeViviSession(raw []byte) (ViviSession, error) {
	var s ViviSession
	if e := StrictJSON(raw, &s); e != nil {
		return s, e
	}
	return s, s.Validate()
}

func DecodeViviContextStrategy(raw []byte) (ViviContextStrategyRecord, error) {
	var c ViviContextStrategyRecord
	if e := StrictJSON(raw, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}

func DecodeViviBoundaryRefusal(raw []byte) (ViviBoundaryRefusal, error) {
	var b ViviBoundaryRefusal
	if e := StrictJSON(raw, &b); e != nil {
		return b, e
	}
	return b, b.Validate()
}

func DecodeViviVerification(raw []byte) (ViviVerificationSubmission, error) {
	var v ViviVerificationSubmission
	if e := StrictJSON(raw, &v); e != nil {
		return v, e
	}
	return v, v.Validate()
}
