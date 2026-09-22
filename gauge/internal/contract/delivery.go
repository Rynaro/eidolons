package contract

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
)

// DeliverySchemaVersion is the typed V4-15 delivery namespace version under schema 2.
const DeliverySchemaVersion = 1

// Delivery loop phases. Process/session/env replacement is not a new budget root.
const (
	PhasePending                = "pending"
	PhaseAdmit                  = "admit"
	PhaseDispatch               = "dispatch"
	PhaseEdit                   = "edit"
	PhaseFreeze                 = "freeze"
	PhaseCheck                  = "check"
	PhaseCheckpoint             = "checkpoint"
	PhaseAccepted               = "accepted"
	PhasePartial                = "partial"
	PhaseBlocked                = "blocked"
	PhaseCancelled              = "cancelled"
	PhaseCancellationPending    = "cancellation_pending"
	PhaseRunning                = "running"
	PhaseUnknown                = "unknown"
	PhaseAwaitingReconciliation = "awaiting_reconciliation"
)

// FailureClass must be classified before recovery (ARCHITECTURE / HANDOFF).
const (
	FailureEnvironment = "environment"
	FailureSchema      = "schema"
	FailurePermission  = "permission"
	FailureProvider    = "provider"
	FailureTest        = "test"
	FailureCausal      = "causal"
	FailureAcceptance  = "acceptance"
)

// Intervention kinds — routine continue prompts are not recorded as progress.
const (
	InterventionRoutineContinue = "routine_continue_prompt"
	InterventionProductDecision = "consequential_product_decision"
	InterventionOperatorCancel  = "operator_cancel"
	InterventionResourceExhaust = "resource_exhaustion"
	InterventionRepeatStop      = "repeat_failure_stop"
	InterventionResumeReconcile = "resume_reconcile"
	InterventionCheckpointLimit = "checkpoint_limitation"
)

// Milestone kinds for runnable reporting (R02).
const (
	MilestoneStub            = "stub_scaffold"
	MilestoneProse           = "prose_completion"
	MilestoneFakeLog         = "fake_log"
	MilestoneGenuineBehavior = "genuine_behavior"
	MilestoneIntegration     = "genuine_integration"
)

// Next-action values exposed by inspect (R07).
const (
	NextContinueAuthorized   = "continue_authorized_phase"
	NextReconcileUncertainty = "reconcile_uncertainty"
	NextAwaitOperator        = "await_operator"
	NextStopPartial          = "stop_partial"
	NextStopBlocked          = "stop_blocked"
	NextAccepted             = "none_accepted"
	NextCancelPending        = "await_cancellation_outcome"
)

// DeliveryFault injects faults at dispatch/edit/check/checkpoint boundaries.
type DeliveryFault string

const (
	DeliveryFaultNone               DeliveryFault = ""
	DeliveryFaultBeforeDispatch     DeliveryFault = "before_dispatch"
	DeliveryFaultAfterDispatch      DeliveryFault = "after_dispatch"
	DeliveryFaultBeforeEdit         DeliveryFault = "before_edit"
	DeliveryFaultAfterEdit          DeliveryFault = "after_edit"
	DeliveryFaultBeforeFreeze       DeliveryFault = "before_freeze"
	DeliveryFaultAfterFreeze        DeliveryFault = "after_freeze"
	DeliveryFaultBeforeCheck        DeliveryFault = "before_check"
	DeliveryFaultAfterCheck         DeliveryFault = "after_check"
	DeliveryFaultBeforeCheckpoint   DeliveryFault = "before_checkpoint"
	DeliveryFaultAfterCheckpoint    DeliveryFault = "after_checkpoint"
	DeliveryFaultLostAckAfterEffect DeliveryFault = "lost_ack_after_effect"
)

// ObligationRecord is a validated task obligation independent of generated summaries (R08).
type ObligationRecord struct {
	ID          string   `json:"id"`
	Kind        string   `json:"kind"` // required_check | failed_approach | source_ref | access_restriction
	Description string   `json:"description"`
	SourceRefs  []string `json:"source_refs,omitempty"`
	Validated   bool     `json:"validated"`
	Digest      string   `json:"digest,omitempty"`
}

func (o ObligationRecord) Validate() error {
	if e := validateID("obligation", o.ID, true); e != nil {
		return e
	}
	switch o.Kind {
	case "required_check", "failed_approach", "source_ref", "access_restriction":
	default:
		return errors.New("unknown obligation kind")
	}
	if o.Description == "" {
		return errors.New("obligation description required")
	}
	return nil
}

// InterventionRecord captures operator/system interventions (R01).
type InterventionRecord struct {
	SchemaVersion int    `json:"schema_version"`
	ID            string `json:"id"`
	LoopID        string `json:"loop_id"`
	Kind          string `json:"kind"`
	Phase         string `json:"phase"`
	Reason        string `json:"reason"`
	Routine       bool   `json:"routine"` // true ⇒ not progress; loop must not request these
	RecordedAt    string `json:"recorded_at"`
}

func (i InterventionRecord) Validate() error {
	if i.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown intervention schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"intervention", i.ID}, {"loop", i.LoopID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if i.Kind == "" || i.Phase == "" || i.Reason == "" || i.RecordedAt == "" {
		return errors.New("intervention incomplete")
	}
	return nil
}

// FailureSignature is stable across workers/context resets (R04).
type FailureSignature struct {
	Class   string `json:"class"`
	Code    string `json:"code"`
	Digest  string `json:"digest"`
	Count   int    `json:"count"`
	Stopped bool   `json:"stopped"`
}

func StableFailureDigest(class, code, detail string) string {
	sum := sha256.Sum256([]byte(class + "|" + code + "|" + detail))
	return hex.EncodeToString(sum[:16])
}

// CheckpointLimitation reports exact recovery limits without discarding valid artifacts (R06).
type CheckpointLimitation struct {
	Kind               string   `json:"kind"` // changed_criteria | tampered_payload | missing_native_history | memory_outage
	Detail             string   `json:"detail"`
	PreservedArtifacts []string `json:"preserved_artifacts,omitempty"`
}

// DeliveryCheckpoint is a portable recovery point (R05/R06).
type DeliveryCheckpoint struct {
	SchemaVersion       int                   `json:"schema_version"`
	ID                  string                `json:"id"`
	LoopID              string                `json:"loop_id"`
	RootID              string                `json:"root_id"`
	Phase               string                `json:"phase"`
	AuthorityDigest     string                `json:"authority_digest"`
	CandidateID         string                `json:"candidate_id,omitempty"`
	AcceptanceID        string                `json:"acceptance_id,omitempty"`
	OutstandingChecks   []string              `json:"outstanding_checks,omitempty"`
	ObligationDigests   []string              `json:"obligation_digests,omitempty"`
	ResourceExposure    map[string]float64    `json:"resource_exposure,omitempty"`
	PayloadDigest       string                `json:"payload_digest"`
	NativeSessionUsable bool                  `json:"native_session_usable"`
	CriteriaDigest      string                `json:"criteria_digest"`
	UnresolvedEffects   bool                  `json:"unresolved_effects"`
	Limitation          *CheckpointLimitation `json:"limitation,omitempty"`
	RecordedAt          string                `json:"recorded_at"`
	ValidLocalArtifacts []string              `json:"valid_local_artifacts,omitempty"`
}

func (c DeliveryCheckpoint) Validate() error {
	if c.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown checkpoint schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"checkpoint", c.ID}, {"loop", c.LoopID}, {"root", c.RootID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if c.Phase == "" || c.PayloadDigest == "" || c.RecordedAt == "" || c.AuthorityDigest == "" {
		return errors.New("checkpoint incomplete")
	}
	return nil
}

// InspectSnapshot is observational — never dispatches model work (R07).
type InspectSnapshot struct {
	SchemaVersion     int                   `json:"schema_version"`
	LoopID            string                `json:"loop_id"`
	RootID            string                `json:"root_id"`
	Status            string                `json:"status"`
	Phase             string                `json:"phase"`
	CandidateID       string                `json:"candidate_id,omitempty"`
	AcceptanceID      string                `json:"acceptance_id,omitempty"`
	PendingExecution  []string              `json:"pending_execution,omitempty"`
	ResourceExposure  map[string]float64    `json:"resource_exposure,omitempty"`
	NextAction        string                `json:"next_action"`
	OutstandingChecks []string              `json:"outstanding_checks,omitempty"`
	UnresolvedEffects bool                  `json:"unresolved_effects"`
	Interventions     int                   `json:"interventions"`
	ModelCalls        int                   `json:"model_calls"`
	FilesystemReads   int                   `json:"filesystem_reads"`
	FilesystemWrites  int                   `json:"filesystem_writes"`
	Accepted          bool                  `json:"accepted"`
	Partial           bool                  `json:"partial"`
	Blocked           bool                  `json:"blocked"`
	Limitation        *CheckpointLimitation `json:"limitation,omitempty"`
}

// ComparisonOutcome records native-control and v4 arms via V4-09 (R09).
type ComparisonOutcome struct {
	SchemaVersion   int    `json:"schema_version"`
	ProtocolID      string `json:"protocol_id"`
	NativeArmStatus string `json:"native_arm_status"` // eligible | ineligible | pending | missing
	NativeArmReason string `json:"native_arm_reason,omitempty"`
	V4ArmStatus     string `json:"v4_arm_status"`
	V4ArmReason     string `json:"v4_arm_reason,omitempty"`
	Fabricated      bool   `json:"fabricated"` // must always be false
	Interventions   int    `json:"interventions"`
	Recoveries      int    `json:"recoveries"`
	RecordedAt      string `json:"recorded_at"`
}

func (c ComparisonOutcome) Validate() error {
	if c.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown comparison schema version")
	}
	if e := validateID("protocol", c.ProtocolID, true); e != nil {
		return e
	}
	if c.Fabricated {
		return errors.New("comparison must never fabricate arms")
	}
	if c.RecordedAt == "" {
		return errors.New("comparison recorded_at required")
	}
	return nil
}

// DeliveryLoop is the durable demonstrator state machine (R01–R10).
type DeliveryLoop struct {
	SchemaVersion       int                   `json:"schema_version"`
	ID                  string                `json:"id"`
	RootID              string                `json:"root_id"`
	AssignmentID        string                `json:"assignment_id"`
	Phase               string                `json:"phase"`
	Status              string                `json:"status"`
	AuthorityDigest     string                `json:"authority_digest"`
	AuthoritySufficient bool                  `json:"authority_sufficient"`
	InputsSufficient    bool                  `json:"inputs_sufficient"`
	CandidateID         string                `json:"candidate_id,omitempty"`
	AcceptanceID        string                `json:"acceptance_id,omitempty"`
	EnvironmentID       string                `json:"environment_id,omitempty"`
	ReservationID       string                `json:"reservation_id,omitempty"`
	IntentID            string                `json:"intent_id,omitempty"`
	OperationID         string                `json:"operation_id,omitempty"`
	MilestoneKind       string                `json:"milestone_kind,omitempty"`
	MilestoneRunnable   bool                  `json:"milestone_runnable"`
	BehaviorCheckRef    string                `json:"behavior_check_ref,omitempty"`
	ResourceRemaining   float64               `json:"resource_remaining"`
	ResourceExposure    map[string]float64    `json:"resource_exposure,omitempty"`
	OutstandingChecks   []string              `json:"outstanding_checks,omitempty"`
	ObligationIDs       []string              `json:"obligation_ids,omitempty"`
	FailureSignatures   []FailureSignature    `json:"failure_signatures,omitempty"`
	FailureBound        int                   `json:"failure_bound"`
	Interventions       []string              `json:"intervention_ids,omitempty"`
	LastCheckpointID    string                `json:"last_checkpoint_id,omitempty"`
	UnresolvedEffects   bool                  `json:"unresolved_effects"`
	UncertaintyExposed  bool                  `json:"uncertainty_exposed"`
	Accepted            bool                  `json:"accepted"`
	Partial             bool                  `json:"partial"`
	Blocked             bool                  `json:"blocked"`
	BlockedReason       string                `json:"blocked_reason,omitempty"`
	LastFailureClass    string                `json:"last_failure_class,omitempty"`
	Comparison          *ComparisonOutcome    `json:"comparison,omitempty"`
	Limitation          *CheckpointLimitation `json:"limitation,omitempty"`
	AccessRestrictions  []string              `json:"access_restrictions,omitempty"`
	ModelCalls          int                   `json:"model_calls"`
	RecordedAt          string                `json:"recorded_at"`
	UpdatedAt           string                `json:"updated_at"`
}

func (l DeliveryLoop) Validate() error {
	if l.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown delivery loop schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"loop", l.ID}, {"root", l.RootID}, {"assignment", l.AssignmentID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if l.Phase == "" || l.Status == "" || l.AuthorityDigest == "" || l.RecordedAt == "" {
		return errors.New("delivery loop incomplete")
	}
	if l.FailureBound < 1 {
		return errors.New("failure_bound must be >= 1")
	}
	return nil
}

// DeliveryRunRequest configures one bounded fixture delivery (zero real network/model).
type DeliveryRunRequest struct {
	SchemaVersion             int                     `json:"schema_version"`
	LoopID                    string                  `json:"loop_id"`
	RootID                    string                  `json:"root_id"`
	AssignmentID              string                  `json:"assignment_id"`
	AuthoritySufficient       bool                    `json:"authority_sufficient"`
	InputsSufficient          bool                    `json:"inputs_sufficient"`
	RequireProductDecision    bool                    `json:"require_product_decision"`
	MilestoneKind             string                  `json:"milestone_kind"`
	ResourceBudget            float64                 `json:"resource_budget"`
	MandatoryCost             float64                 `json:"mandatory_cost"`
	VerificationCost          float64                 `json:"verification_cost"`
	ExhaustBeforeVerification bool                    `json:"exhaust_before_verification"`
	ExhaustAfterSlice         bool                    `json:"exhaust_after_slice"`
	FailureBound              int                     `json:"failure_bound"`
	InjectFailureClass        string                  `json:"inject_failure_class,omitempty"`
	InjectFailureCode         string                  `json:"inject_failure_code,omitempty"`
	InjectFailureRepeats      int                     `json:"inject_failure_repeats,omitempty"`
	Fault                     DeliveryFault           `json:"fault,omitempty"`
	UnresolvedExternalEffect  bool                    `json:"unresolved_external_effect"`
	LostAckAfterEffect        bool                    `json:"lost_ack_after_effect"`
	CandidateID               string                  `json:"candidate_id"`
	AcceptancePackage         AcceptancePackage       `json:"acceptance_package"`
	FreezeEntries             []CandidateContentEntry `json:"freeze_entries"`
	BehaviorObserved          bool                    `json:"behavior_observed"`
	ComparisonRequested       bool                    `json:"comparison_requested"`
	ProtocolID                string                  `json:"protocol_id,omitempty"`
	NativeArmEligible         bool                    `json:"native_arm_eligible"`
	Obligations               []ObligationRecord      `json:"obligations,omitempty"`
	AccessRestrictions        []string                `json:"access_restrictions,omitempty"`
	SkipDispatch              bool                    `json:"skip_dispatch"` // fixture-only path without native send
	RecordedAt                string                  `json:"recorded_at,omitempty"`
}

func (r DeliveryRunRequest) Validate() error {
	if r.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown delivery run schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"loop", r.LoopID}, {"root", r.RootID}, {"assignment", r.AssignmentID}, {"candidate", r.CandidateID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if r.FailureBound < 1 {
		r.FailureBound = 2
	}
	if r.ResourceBudget < 0 || r.MandatoryCost < 0 {
		return errors.New("resource amounts must be non-negative")
	}
	return nil
}

// DeliveryResumeRequest continues after interrupt with uncertainty reconciliation (R05/R10).
type DeliveryResumeRequest struct {
	SchemaVersion          int    `json:"schema_version"`
	LoopID                 string `json:"loop_id"`
	RootID                 string `json:"root_id"`
	AcknowledgeUncertainty bool   `json:"acknowledge_uncertainty"`
	AdmitDependentWork     bool   `json:"admit_dependent_work"`
	RecordedAt             string `json:"recorded_at,omitempty"`
}

func (r DeliveryResumeRequest) Validate() error {
	if r.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown resume schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"loop", r.LoopID}, {"root", r.RootID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	return nil
}

// DeliveryCancelRequest requests cancellation (nonterminal until native outcome).
type DeliveryCancelRequest struct {
	SchemaVersion int    `json:"schema_version"`
	LoopID        string `json:"loop_id"`
	RootID        string `json:"root_id"`
	Reason        string `json:"reason"`
	RecordedAt    string `json:"recorded_at,omitempty"`
}

func (r DeliveryCancelRequest) Validate() error {
	if r.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown cancel schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"loop", r.LoopID}, {"root", r.RootID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if r.Reason == "" {
		return errors.New("cancel reason required")
	}
	return nil
}

// ContextCompactRequest replaces working context while preserving obligations (R08).
type ContextCompactRequest struct {
	SchemaVersion    int      `json:"schema_version"`
	LoopID           string   `json:"loop_id"`
	RootID           string   `json:"root_id"`
	GeneratedSummary string   `json:"generated_summary"`
	OmittedTopics    []string `json:"omitted_topics,omitempty"`
	RecordedAt       string   `json:"recorded_at,omitempty"`
}

func (r ContextCompactRequest) Validate() error {
	if r.SchemaVersion != DeliverySchemaVersion {
		return errors.New("unknown compact schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"loop", r.LoopID}, {"root", r.RootID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	return nil
}

// CheckpointTamperKind selects R06 limitation scenarios.
const (
	TamperNone            = ""
	TamperChangedCriteria = "changed_criteria"
	TamperPayload         = "tampered_payload"
	TamperMissingNative   = "missing_native_history"
	TamperMemoryOutage    = "memory_outage"
)

// AuthorityDigest computes a stable authority identity for resume continuity.
func AuthorityDigest(sufficient bool, assignment, root string) string {
	raw := fmt.Sprintf("auth|%v|%s|%s", sufficient, assignment, root)
	sum := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(sum[:16])
}

// CheckpointPayloadDigest hashes portable checkpoint contents.
func CheckpointPayloadDigest(c DeliveryCheckpoint) string {
	cp := c
	cp.PayloadDigest = ""
	cp.Limitation = nil
	raw, _ := json.Marshal(cp)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}

// Decode helpers for CLI JSON.

func DecodeDeliveryRunRequest(raw []byte) (DeliveryRunRequest, error) {
	var r DeliveryRunRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	if r.FailureBound < 1 {
		r.FailureBound = 2
	}
	return r, r.Validate()
}

func DecodeDeliveryResumeRequest(raw []byte) (DeliveryResumeRequest, error) {
	var r DeliveryResumeRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeDeliveryCancelRequest(raw []byte) (DeliveryCancelRequest, error) {
	var r DeliveryCancelRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeContextCompactRequest(raw []byte) (ContextCompactRequest, error) {
	var r ContextCompactRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}
