package contract

import (
	"errors"
	"fmt"
)

// CompilerSchemaVersion is the typed V4-13 compiler namespace version under schema 2.
const CompilerSchemaVersion = 1

// ExperimentalProfileID versions experimental method/worker profiles until roster
// charters are amended. Existing specialist refusals remain intact.
const ExperimentalProfileID = "gauge-experimental-compiler@0.1"

// Execution forms for method use (ARCHITECTURE §Expertise without mandatory topology).
const (
	FormEmbedded     = "embedded"
	FormConsultant   = "bounded_consultant"
	FormIsolatedWriter = "isolated_writer"
	FormVerification = "protected_verification"
)

// Boundary reasons that force a separately identified assignment.
const (
	BoundaryCompatible         = "compatible_inline"
	BoundaryVerification       = "verification"
	BoundaryIncompatibleAuth   = "incompatible_authority"
	BoundaryIsolatedWriter     = "isolated_writer"
	BoundaryContextSeparation  = "context_separation"
	BoundaryIndependentConsult = "independent_consultation"
	BoundaryExplicitUser       = "explicit_user_request"
)

// Method-use reporting classes — method use ≠ specialist invocation.
const (
	ReportMethodUse           = "method_use"
	ReportSpecialistInvocation = "specialist_invocation"
)

// Evidence classification for clean-context verification status.
const (
	EvidenceCleanContext     = "clean_context_verification"
	EvidenceContaminated     = "contaminated_context"
	EvidenceForkRename       = "fork_or_rename_not_fresh"
	EvidenceSameModelCheck   = "same_model_not_independent"
	EvidenceWithheldClean    = "clean_context_withheld"
)

// Role-rebinding outcomes.
const (
	RebindSafeQuiescent = "safe_quiescent"
	RebindRequireNew    = "require_new_restricted_execution"
	RebindPromptOnlyInsufficient = "prompt_only_revocation_insufficient"
)

// Unsafe rebinding triggers.
const (
	RebindTriggerInFlight       = "in_flight_action"
	RebindTriggerReusableOldCap = "reusable_old_capability"
	RebindTriggerUnsupported    = "unsupported_transition"
	RebindTriggerPromptOnly     = "prompt_only_revocation"
)

// AuthorityLayer names the five intersected capability sources (R03).
const (
	AuthLayerOperator       = "operator"
	AuthLayerTask           = "task"
	AuthLayerAssignment     = "assignment"
	AuthLayerSpecialist     = "specialist"
	AuthLayerHostEnforceable = "host_enforceable"
)

// WideningAttempt sources that must not escalate a child grant (R03).
const (
	WidenRoleCard       = "role_card"
	WidenModelMessage   = "model_message"
	WidenRepoConfig     = "repository_config"
	WidenPrivilegedParent = "privileged_parent"
)

// SkillContract binds versioned applicability / I/O / execution-form (R07).
type SkillContract struct {
	SchemaVersion   int      `json:"schema_version"`
	MethodID        string   `json:"method_id"`
	Version         string   `json:"version"`
	Applicability   []string `json:"applicability"`
	RequiredInputs  []string `json:"required_inputs"`
	OutputSchema    string   `json:"output_schema"`
	AllowedForms    []string `json:"allowed_forms"`
	MaxOutputBytes  int      `json:"max_output_bytes,omitempty"`
	DerivedFrom     string   `json:"derived_from,omitempty"` // e.g. ATLAS methodology — not an invocation
	ExperimentalProfile string `json:"experimental_profile,omitempty"`
}

func (c SkillContract) Validate() error {
	if c.SchemaVersion != CompilerSchemaVersion {
		return errors.New("unknown skill contract schema version")
	}
	if e := validateID("method", c.MethodID, true); e != nil {
		return e
	}
	if c.Version == "" {
		return errors.New("skill version required")
	}
	if c.OutputSchema == "" {
		return errors.New("output schema required")
	}
	if len(c.AllowedForms) == 0 {
		return errors.New("allowed forms required")
	}
	for _, f := range c.AllowedForms {
		switch f {
		case FormEmbedded, FormConsultant, FormIsolatedWriter, FormVerification:
		default:
			return fmt.Errorf("unknown execution form %q", f)
		}
	}
	return nil
}

// SelectionReason records inspectable compiler decisions (fallible; not correctness).
type SelectionReason struct {
	RuleID  string `json:"rule_id"`
	Kind    string `json:"kind"`
	Detail  string `json:"detail"`
	Profile string `json:"profile,omitempty"`
}

// MethodUse is an embedded or isolated method binding within an assignment.
type MethodUse struct {
	ID              string         `json:"id"`
	MethodID        string         `json:"method_id"`
	MethodVersion   string         `json:"method_version"`
	ExecutionForm   string         `json:"execution_form"`
	ReportClass     string         `json:"report_class"` // method_use vs specialist_invocation
	WorkerID        string         `json:"worker_id"`
	InvocationID    string         `json:"invocation_id,omitempty"` // only when separately invoked
	Contract        SkillContract  `json:"contract"`
	ProvidedInputs  []string       `json:"provided_inputs"`
	Selection       SelectionReason `json:"selection"`
	Status          string         `json:"status"` // bound | rejected
	RejectReasons   []string       `json:"reject_reasons,omitempty"`
}

func (m MethodUse) Validate() error {
	if e := validateID("method_use", m.ID, true); e != nil {
		return e
	}
	if e := validateID("method", m.MethodID, true); e != nil {
		return e
	}
	if e := validateID("worker", m.WorkerID, true); e != nil {
		return e
	}
	switch m.ExecutionForm {
	case FormEmbedded, FormConsultant, FormIsolatedWriter, FormVerification:
	default:
		return errors.New("unknown method execution form")
	}
	switch m.ReportClass {
	case ReportMethodUse, ReportSpecialistInvocation:
	default:
		return errors.New("unknown method report class")
	}
	if m.ReportClass == ReportSpecialistInvocation && m.InvocationID == "" {
		return errors.New("specialist invocation requires invocation identity")
	}
	if m.ReportClass == ReportMethodUse && m.InvocationID != "" {
		// Embedded method use may still carry a local step id, but must not
		// claim a separate specialist invocation identity in status.
	}
	return m.Contract.Validate()
}

// WorkerStart records a separately identified assignment/worker with reason.
type WorkerStart struct {
	AssignmentID string          `json:"assignment_id"`
	WorkerID     string          `json:"worker_id"`
	Boundary     string          `json:"boundary_reason"`
	Selection    SelectionReason `json:"selection"`
	AuthorityID  string          `json:"authority_id,omitempty"`
	WorkspaceID  string          `json:"workspace_id,omitempty"`
}

func (w WorkerStart) Validate() error {
	if e := validateID("assignment", w.AssignmentID, true); e != nil {
		return e
	}
	if e := validateID("worker", w.WorkerID, true); e != nil {
		return e
	}
	switch w.Boundary {
	case BoundaryVerification, BoundaryIncompatibleAuth, BoundaryIsolatedWriter,
		BoundaryContextSeparation, BoundaryIndependentConsult, BoundaryExplicitUser:
	default:
		return fmt.Errorf("unknown or missing boundary reason %q", w.Boundary)
	}
	return nil
}

// Assignment is one compiled unit of work under a continuing or separated worker.
type Assignment struct {
	SchemaVersion int           `json:"schema_version"`
	ID            string        `json:"id"`
	RootID        string        `json:"root_id"`
	TaskID        string        `json:"task_id"`
	WorkerID      string        `json:"worker_id"`
	MakerWorkerID string        `json:"maker_worker_id"`
	Continuing    bool          `json:"continuing_maker"`
	Boundary      string        `json:"boundary_reason"`
	AuthorityID   string        `json:"authority_id"`
	Methods       []MethodUse   `json:"methods"`
	Selection     SelectionReason `json:"selection"`
	Status        string        `json:"status"` // compiled | rejected | admitted
	RejectReasons []string      `json:"reject_reasons,omitempty"`
}

func (a Assignment) Validate() error {
	if a.SchemaVersion != CompilerSchemaVersion {
		return errors.New("unknown assignment schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"assignment", a.ID}, {"root", a.RootID}, {"task", a.TaskID},
		{"worker", a.WorkerID}, {"maker_worker", a.MakerWorkerID}, {"authority", a.AuthorityID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	switch a.Boundary {
	case BoundaryCompatible, BoundaryVerification, BoundaryIncompatibleAuth,
		BoundaryIsolatedWriter, BoundaryContextSeparation, BoundaryIndependentConsult,
		BoundaryExplicitUser:
	default:
		return fmt.Errorf("unknown assignment boundary %q", a.Boundary)
	}
	if a.Continuing && a.Boundary != BoundaryCompatible {
		return errors.New("continuing maker requires compatible_inline boundary")
	}
	if !a.Continuing && a.Boundary == BoundaryCompatible {
		return errors.New("separated assignment requires non-compatible boundary reason")
	}
	for _, m := range a.Methods {
		if e := m.Validate(); e != nil {
			return e
		}
	}
	return nil
}

// CapabilitySet is an explicit allow/deny grant used in authority intersection.
// Nil Allowed means unrestricted at that layer; empty Allowed means allow-nothing.
type CapabilitySet struct {
	Allowed []string `json:"allowed,omitzero"`
	Denied  []string `json:"denied,omitempty"`
}

func (c CapabilitySet) Validate() error {
	for _, xs := range [][]string{c.Allowed, c.Denied} {
		for _, x := range xs {
			if x == "" {
				return errors.New("empty capability token")
			}
		}
	}
	return nil
}

// AuthorityLayers holds the five intersected sources (R03).
type AuthorityLayers struct {
	Operator        CapabilitySet `json:"operator"`
	Task            CapabilitySet `json:"task"`
	Assignment      CapabilitySet `json:"assignment"`
	Specialist      CapabilitySet `json:"specialist"`
	HostEnforceable CapabilitySet `json:"host_enforceable"`
}

func (a AuthorityLayers) Validate() error {
	for _, c := range []CapabilitySet{a.Operator, a.Task, a.Assignment, a.Specialist, a.HostEnforceable} {
		if e := c.Validate(); e != nil {
			return e
		}
	}
	return nil
}

// EffectiveAuthority is the resolved intersection with provenance.
type EffectiveAuthority struct {
	SchemaVersion int               `json:"schema_version"`
	ID            string            `json:"id"`
	Permissions   []string          `json:"permissions"`
	Denied        []string          `json:"denied"`
	Layers        AuthorityLayers   `json:"layers"`
	Provenance    []SelectionReason `json:"provenance"`
	WideningDenied []string         `json:"widening_denied,omitempty"`
}

func (e EffectiveAuthority) Validate() error {
	if e.SchemaVersion != CompilerSchemaVersion {
		return errors.New("unknown effective authority schema version")
	}
	return validateID("authority", e.ID, true)
}

// ConsultantResult is a bounded consultant return value (R08).
type ConsultantResult struct {
	SchemaVersion  int    `json:"schema_version"`
	ID             string `json:"id"`
	TaskID         string `json:"task_id"`
	CandidateID    string `json:"candidate_id"`
	AssignmentID   string `json:"assignment_id"`
	ArtifactRef    string `json:"artifact_ref,omitempty"`
	OutputSchema   string `json:"output_schema"`
	PayloadBytes   int    `json:"payload_bytes"`
	TranscriptDump bool   `json:"transcript_dump"`
	Malformed      bool   `json:"malformed"`
}

func (c ConsultantResult) Validate() error {
	if c.SchemaVersion != CompilerSchemaVersion {
		return errors.New("unknown consultant result schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"result", c.ID}, {"task", c.TaskID}, {"candidate", c.CandidateID}, {"assignment", c.AssignmentID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if c.OutputSchema == "" {
		return errors.New("consultant output schema required")
	}
	if c.PayloadBytes < 0 {
		return errors.New("payload bytes must be nonnegative")
	}
	return nil
}

// ConsultantValidation is the maker-use admission decision for a consultant result.
type ConsultantValidation struct {
	Accepted      bool     `json:"accepted"`
	ResultID      string   `json:"result_id"`
	RejectReasons []string `json:"reject_reasons,omitempty"`
	ArtifactRef   string   `json:"artifact_ref,omitempty"`
}

// EvidenceClass records whether clean-context verification status is withheld (R05).
type EvidenceClass struct {
	SchemaVersion        int    `json:"schema_version"`
	InvocationID         string `json:"invocation_id"`
	Class                string `json:"class"`
	CleanContextStatus   string `json:"clean_context_status"` // granted | withheld
	InheritsMakerContext bool   `json:"inherits_maker_context"`
	PrivilegedInfo       bool   `json:"privileged_info"`
	SameModelAsMaker     bool   `json:"same_model_as_maker"`
	ForkOrRename         bool   `json:"fork_or_rename"`
	Selection            SelectionReason `json:"selection"`
}

func (e EvidenceClass) Validate() error {
	if e.SchemaVersion != CompilerSchemaVersion {
		return errors.New("unknown evidence class schema version")
	}
	if e := validateID("invocation", e.InvocationID, true); e != nil {
		return e
	}
	switch e.Class {
	case EvidenceCleanContext, EvidenceContaminated, EvidenceForkRename,
		EvidenceSameModelCheck, EvidenceWithheldClean:
	default:
		return errors.New("unknown evidence class")
	}
	switch e.CleanContextStatus {
	case "granted", "withheld":
	default:
		return errors.New("unknown clean context status")
	}
	return nil
}

// WriterProposal describes concurrent writer admission inputs (R09).
type WriterProposal struct {
	WorkerID           string   `json:"worker_id"`
	WorkspaceID        string   `json:"workspace_id"`
	MutablePaths       []string `json:"mutable_paths"`
	SharedMutable      bool     `json:"shared_mutable"`
	IsolatedWorkspace  bool     `json:"isolated_workspace"`
}

func (w WriterProposal) Validate() error {
	if e := validateID("worker", w.WorkerID, true); e != nil {
		return e
	}
	if e := validateID("workspace", w.WorkspaceID, true); e != nil {
		return e
	}
	return nil
}

// ConcurrentWritersRequest admits concurrent writers under isolation + integration owner.
type ConcurrentWritersRequest struct {
	RootID                 string           `json:"root_id"`
	TaskID                 string           `json:"task_id"`
	CandidateID            string           `json:"candidate_id"`
	Writers                []WriterProposal `json:"writers"`
	IntegrationOwnerID     string           `json:"integration_owner_id"`
	IntegrationReserved    bool             `json:"integration_reserved"`
	CheckReserved          bool             `json:"check_reserved"`
	MergeRequiresRevalidate bool            `json:"merge_requires_revalidate"`
	RecordedAt             string           `json:"recorded_at"`
}

func (r ConcurrentWritersRequest) Validate() error {
	if e := validateID("root", r.RootID, true); e != nil {
		return e
	}
	if e := validateID("task", r.TaskID, true); e != nil {
		return e
	}
	if e := validateID("candidate", r.CandidateID, true); e != nil {
		return e
	}
	if len(r.Writers) < 2 {
		return errors.New("concurrent writers require at least two proposals")
	}
	for _, w := range r.Writers {
		if e := w.Validate(); e != nil {
			return e
		}
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return nil
}

// ConcurrentWritersResult is the scheduler admission decision.
type ConcurrentWritersResult struct {
	Admitted              bool     `json:"admitted"`
	RejectReasons         []string `json:"reject_reasons,omitempty"`
	IntegrationOwnerID    string   `json:"integration_owner_id,omitempty"`
	MergeRevalidates      bool     `json:"merge_revalidates_candidate"`
	WorkspaceIDs          []string `json:"workspace_ids,omitempty"`
}

// MethodRequest is one requested method application in a compile.
type MethodRequest struct {
	UseID          string   `json:"use_id"`
	MethodID       string   `json:"method_id"`
	Contract       SkillContract `json:"contract"`
	ExecutionForm  string   `json:"execution_form"`
	ProvidedInputs []string `json:"provided_inputs"`
	// ExpectedOutputSchema, when set, must match Contract.OutputSchema or reject.
	ExpectedOutputSchema string `json:"expected_output_schema,omitempty"`
	// ForceBoundary, when set, requires separation even if form is embedded.
	ForceBoundary  string   `json:"force_boundary,omitempty"`
	RequireIndependent bool `json:"require_independent_consultation"`
}

// CompileRequest drives assignment compilation without mandatory agent chains.
type CompileRequest struct {
	PlanID            string           `json:"plan_id"`
	RootID            string           `json:"root_id"`
	TaskID            string           `json:"task_id"`
	MakerWorkerID     string           `json:"maker_worker_id"`
	Authority         AuthorityLayers  `json:"authority"`
	AuthorityID       string           `json:"authority_id"`
	Methods           []MethodRequest  `json:"methods"`
	// WideningAttempts are non-grant sources that must not escalate (R03).
	WideningAttempts  []string         `json:"widening_attempts,omitempty"`
	ExperimentalProfile string         `json:"experimental_profile,omitempty"`
	RecordedAt        string           `json:"recorded_at"`
}

func (r CompileRequest) Validate() error {
	for _, pair := range []struct{ label, v string }{
		{"plan", r.PlanID}, {"root", r.RootID}, {"task", r.TaskID},
		{"maker_worker", r.MakerWorkerID}, {"authority", r.AuthorityID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if e := r.Authority.Validate(); e != nil {
		return e
	}
	if len(r.Methods) == 0 {
		return errors.New("at least one method required")
	}
	for _, m := range r.Methods {
		if e := validateID("method_use", m.UseID, true); e != nil {
			return e
		}
		if e := m.Contract.Validate(); e != nil {
			return e
		}
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return nil
}

// CompiledPlan is the durable compiler output.
type CompiledPlan struct {
	SchemaVersion     int              `json:"schema_version"`
	ID                string           `json:"id"`
	RootID            string           `json:"root_id"`
	TaskID            string           `json:"task_id"`
	MakerWorkerID     string           `json:"maker_worker_id"`
	Assignments       []Assignment     `json:"assignments"`
	WorkerStarts      []WorkerStart    `json:"worker_starts,omitempty"`
	EffectiveAuth     EffectiveAuthority `json:"effective_authority"`
	ForcedFanOut      bool             `json:"forced_fan_out"`
	SelectionReasons  []SelectionReason `json:"selection_reasons"`
	ExperimentalProfile string         `json:"experimental_profile"`
	Status            string           `json:"status"` // compiled | rejected
	RejectReasons     []string         `json:"reject_reasons,omitempty"`
	CompiledAt        string           `json:"compiled_at"`
}

func (p CompiledPlan) Validate() error {
	if p.SchemaVersion != CompilerSchemaVersion {
		return errors.New("unknown compiled plan schema version")
	}
	if e := validateID("plan", p.ID, true); e != nil {
		return e
	}
	if e := validateID("root", p.RootID, true); e != nil {
		return e
	}
	for _, a := range p.Assignments {
		if e := a.Validate(); e != nil {
			return e
		}
	}
	for _, w := range p.WorkerStarts {
		if e := w.Validate(); e != nil {
			return e
		}
	}
	return p.EffectiveAuth.Validate()
}

// CompileResult is the controller response for CompileAssignments.
type CompileResult struct {
	Compiled bool          `json:"compiled"`
	Plan     *CompiledPlan `json:"plan,omitempty"`
	RejectReasons []string `json:"reject_reasons,omitempty"`
}

// RoleRebindRequest evaluates whether role rebinding can safely revoke prior caps (R04).
type RoleRebindRequest struct {
	RootID              string   `json:"root_id"`
	WorkerID            string   `json:"worker_id"`
	InFlightAction      bool     `json:"in_flight_action"`
	ReusableOldCapability bool   `json:"reusable_old_capability"`
	UnsupportedTransition bool   `json:"unsupported_transition"`
	PromptOnlyRevocation bool    `json:"prompt_only_revocation"`
	TargetPermissions   []string `json:"target_permissions"`
	RecordedAt          string   `json:"recorded_at"`
}

func (r RoleRebindRequest) Validate() error {
	if e := validateID("root", r.RootID, true); e != nil {
		return e
	}
	if e := validateID("worker", r.WorkerID, true); e != nil {
		return e
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return nil
}

// RoleRebindResult reports whether a new restricted execution is required.
type RoleRebindResult struct {
	Outcome       string   `json:"outcome"`
	Triggers      []string `json:"triggers,omitempty"`
	RequireNew    bool     `json:"require_new_restricted_execution"`
	Detail        string   `json:"detail,omitempty"`
}

// ClassifyEvidenceRequest drives clean-context evidence classification (R05).
type ClassifyEvidenceRequest struct {
	InvocationID         string `json:"invocation_id"`
	InheritsMakerContext bool   `json:"inherits_maker_context"`
	PrivilegedInfo       bool   `json:"privileged_info"`
	SameModelAsMaker     bool   `json:"same_model_as_maker"`
	ForkOrRename         bool   `json:"fork_or_rename"`
	GenuinelyFresh       bool   `json:"genuinely_fresh"`
	RecordedAt           string `json:"recorded_at"`
}

func (r ClassifyEvidenceRequest) Validate() error {
	if e := validateID("invocation", r.InvocationID, true); e != nil {
		return e
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return nil
}

// ValidateConsultantRequest wraps a result plus the expected bound contract.
type ValidateConsultantRequest struct {
	Result           ConsultantResult `json:"result"`
	ExpectedTaskID   string           `json:"expected_task_id"`
	ExpectedCandidate string          `json:"expected_candidate_id"`
	ExpectedSchema   string           `json:"expected_output_schema"`
	MaxOutputBytes   int              `json:"max_output_bytes"`
	RecordedAt       string           `json:"recorded_at"`
}

func (r ValidateConsultantRequest) Validate() error {
	if e := r.Result.Validate(); e != nil {
		return e
	}
	if e := validateID("expected_task", r.ExpectedTaskID, true); e != nil {
		return e
	}
	if e := validateID("expected_candidate", r.ExpectedCandidate, true); e != nil {
		return e
	}
	if r.ExpectedSchema == "" {
		return errors.New("expected output schema required")
	}
	if r.MaxOutputBytes <= 0 {
		return errors.New("max output bytes must be positive")
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return nil
}

// DecodeCompileRequest strict-decodes a compile request.
func DecodeCompileRequest(raw []byte) (CompileRequest, error) {
	var r CompileRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// DecodeValidateConsultantRequest strict-decodes a consultant validation request.
func DecodeValidateConsultantRequest(raw []byte) (ValidateConsultantRequest, error) {
	var r ValidateConsultantRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// DecodeConcurrentWritersRequest strict-decodes a concurrent-writers request.
func DecodeConcurrentWritersRequest(raw []byte) (ConcurrentWritersRequest, error) {
	var r ConcurrentWritersRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// DecodeRoleRebindRequest strict-decodes a role-rebind request.
func DecodeRoleRebindRequest(raw []byte) (RoleRebindRequest, error) {
	var r RoleRebindRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// DecodeClassifyEvidenceRequest strict-decodes an evidence classification request.
func DecodeClassifyEvidenceRequest(raw []byte) (ClassifyEvidenceRequest, error) {
	var r ClassifyEvidenceRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// IntersectCapabilitySets intersects allow-lists and unions denies.
// Nil Allowed is unrestricted; empty Allowed allows nothing.
func IntersectCapabilitySets(layers ...CapabilitySet) (CapabilitySet, error) {
	out := CapabilitySet{Allowed: nil, Denied: nil}
	first := true
	for _, layer := range layers {
		if e := layer.Validate(); e != nil {
			return out, e
		}
		out.Denied = append(out.Denied, layer.Denied...)
		if first {
			if layer.Allowed != nil {
				out.Allowed = SortedSet(layer.Allowed)
			}
			first = false
			continue
		}
		if out.Allowed == nil && layer.Allowed == nil {
			continue
		}
		if out.Allowed == nil {
			out.Allowed = SortedSet(layer.Allowed)
			continue
		}
		if layer.Allowed == nil {
			continue
		}
		keep := map[string]bool{}
		for _, x := range layer.Allowed {
			keep[x] = true
		}
		next := []string{}
		for _, x := range out.Allowed {
			if keep[x] {
				next = append(next, x)
			}
		}
		out.Allowed = SortedSet(next)
	}
	out.Denied = SortedSet(out.Denied)
	// Remove denied from allowed when both are explicit.
	if out.Allowed != nil && len(out.Denied) > 0 {
		deny := map[string]bool{}
		for _, d := range out.Denied {
			deny[d] = true
		}
		kept := []string{}
		for _, a := range out.Allowed {
			if !deny[a] {
				kept = append(kept, a)
			}
		}
		out.Allowed = SortedSet(kept)
	}
	return out, nil
}
