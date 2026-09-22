package contract

import (
	"errors"
	"fmt"
)

// DispatchSchemaVersion is the typed V4-12 dispatch namespace version under schema 2.
const DispatchSchemaVersion = 1

// Exactly one fixture-qualified host/version/mode + legitimate billing path for V4-12.
const (
	QualifiedDispatchHost    = "codex-cli"
	QualifiedDispatchVersion = "0.154.0"
	QualifiedDispatchMode    = "local"
	QualifiedDispatchMethod  = "exec-sandbox-readonly"
	QualifiedDispatchBilling = "auth-sub-1"
	QualifiedDispatchTupleID = "tuple-v412-qualified"
)

// Dispatch intent lifecycle (durable before any native send).
const (
	IntentPendingCommit = "pending_commit"
	IntentCommitted     = "committed"
	IntentSent          = "sent"
	IntentAcked         = "acked"
	IntentUncertain     = "uncertain"
	IntentReconciled    = "reconciled"
	IntentRejected      = "rejected"
	IntentBlocked       = "blocked"
)

// Cancellation is nonterminal until native outcome is established.
const (
	CancelNone               = "none"
	CancelRequested          = "requested"
	CancelInterruptAccepted  = "interrupt_accepted"
	CancelConfirmedStopped   = "confirmed_stopped"
	CancelFinalReconciled    = "final_reconciled"
)

// Native execution outcome classes — transport terminal ≠ acceptance.
const (
	OutcomeUnknown           = "unknown"
	OutcomeRunning           = "running"
	OutcomeStopped           = "stopped"
	OutcomeFailed            = "failed"
	OutcomeTransportTerminal = "transport_terminal"
)

// Reconciliation / lookup results.
const (
	ReconcileResolved   = "resolved"
	ReconcileUnresolved = "unresolved"
	ReconcileUnsupported = "lookup_unsupported"
)

// Reconstruction kinds — portable reconstruction ≠ native-session continuity.
const (
	ReconstructionNone              = "none"
	ReconstructionPortable          = "portable_reconstructed"
	ReconstructionBlocked           = "reconstruction_blocked"
	ReconstructionNativeUnavailable = "native_session_unavailable"
)

// OperationID is the stable external operation identity for idempotency/reconciliation.
type OperationID string

func (id OperationID) Validate() error {
	return validateID("operation", string(id), true)
}

// DispatchAck records the observed native acknowledgement after send.
type DispatchAck struct {
	NativeSessionID string `json:"native_session_id,omitempty"`
	NativeRunID     string `json:"native_run_id,omitempty"`
	TransportState  string `json:"transport_state"`
	ObservedAt      string `json:"observed_at"`
	Accepted        bool   `json:"accepted"` // never set from transport-terminal alone
}

func (a DispatchAck) Validate() error {
	if a.ObservedAt == "" {
		return errors.New("ack observed_at required")
	}
	switch a.TransportState {
	case OutcomeRunning, OutcomeStopped, OutcomeFailed, OutcomeTransportTerminal, OutcomeUnknown:
	default:
		return errors.New("unknown ack transport state")
	}
	return nil
}

// CancelState tracks cancellation progress independently of final reconciliation.
type CancelState struct {
	State            string `json:"state"`
	RequestedAt      string `json:"requested_at,omitempty"`
	InterruptAckAt   string `json:"interrupt_ack_at,omitempty"`
	ConfirmedStopAt  string `json:"confirmed_stop_at,omitempty"`
	FinalReconciledAt string `json:"final_reconciled_at,omitempty"`
	ProcessAlive     bool   `json:"process_alive"`
	AckMissing       bool   `json:"ack_missing"`
	UsageDelayed     bool   `json:"usage_delayed"`
}

func (c CancelState) Validate() error {
	switch c.State {
	case CancelNone, CancelRequested, CancelInterruptAccepted, CancelConfirmedStopped, CancelFinalReconciled:
	default:
		return errors.New("unknown cancel state")
	}
	return nil
}

// IsTerminal reports whether cancellation has reached a confirmed native stop.
func (c CancelState) IsTerminal() bool {
	return c.State == CancelConfirmedStopped || c.State == CancelFinalReconciled
}

// RequestedSettings are operator/controller requested values (may be ignored by host).
type RequestedSettings struct {
	Model  string `json:"model,omitempty"`
	Effort string `json:"effort,omitempty"`
	Method string `json:"method"`
}

// ObservedSettings are what the host actually applied.
type ObservedSettings struct {
	Model  string `json:"model,omitempty"`
	Effort string `json:"effort,omitempty"`
	Method string `json:"method,omitempty"`
}

// NativeEvent separates requested settings from observed values (R03).
type NativeEvent struct {
	SchemaVersion    int               `json:"schema_version"`
	ID               string            `json:"id"`
	IntentID         string            `json:"intent_id"`
	OperationID      string            `json:"operation_id"`
	Sequence         int64             `json:"sequence"`
	Kind             string            `json:"kind"`
	Requested        RequestedSettings `json:"requested"`
	Observed         ObservedSettings  `json:"observed"`
	ChildUsageGap    bool              `json:"child_usage_gap"`
	DuplicateOf      string            `json:"duplicate_of,omitempty"`
	TransportTerminal bool             `json:"transport_terminal"`
	TerminalError    string            `json:"terminal_error,omitempty"`
	AcceptanceClaim  bool              `json:"acceptance_claim"` // must remain false from transport
	RecordedAt       string            `json:"recorded_at"`
}

func (e NativeEvent) Validate() error {
	if e.SchemaVersion != DispatchSchemaVersion {
		return errors.New("unknown native event schema version")
	}
	if err := validateID("event", e.ID, true); err != nil {
		return err
	}
	if err := validateID("intent", e.IntentID, true); err != nil {
		return err
	}
	if err := validateID("operation", e.OperationID, true); err != nil {
		return err
	}
	if e.Requested.Method == "" {
		return errors.New("requested method required")
	}
	if e.RecordedAt == "" {
		return errors.New("event recorded_at required")
	}
	if e.AcceptanceClaim {
		return errors.New("transport events cannot claim acceptance")
	}
	return nil
}

// ReconstructionReport states whether qualified reconstruction is possible without
// claiming native-session continuity (R09).
type ReconstructionReport struct {
	Kind                 string `json:"kind"`
	NativeSessionPresent bool   `json:"native_session_present"`
	PortableCheckpointOK bool   `json:"portable_checkpoint_ok"`
	ReconstructedInvocationID string `json:"reconstructed_invocation_id,omitempty"`
	ClaimsNativeContinuity bool `json:"claims_native_continuity"`
	Detail               string `json:"detail,omitempty"`
}

func (r ReconstructionReport) Validate() error {
	switch r.Kind {
	case ReconstructionNone, ReconstructionPortable, ReconstructionBlocked, ReconstructionNativeUnavailable:
	default:
		return errors.New("unknown reconstruction kind")
	}
	if r.ClaimsNativeContinuity {
		return errors.New("reconstruction must not claim native-session continuity")
	}
	if r.Kind == ReconstructionPortable && r.ReconstructedInvocationID == "" {
		return errors.New("portable reconstruction requires distinct invocation identity")
	}
	return nil
}

// DispatchIntent is the durable reservation+dispatch record committed before native send.
type DispatchIntent struct {
	SchemaVersion      int               `json:"schema_version"`
	ID                 string            `json:"id"`
	RootID             string            `json:"root_id"`
	ReservationID      string            `json:"reservation_id"`
	OperationID        string            `json:"operation_id"`
	IdempotencyKey     string            `json:"idempotency_key,omitempty"`
	TupleID            string            `json:"tuple_id"`
	Host               string            `json:"host"`
	InstalledVersion   string            `json:"installed_version"`
	Mode               string            `json:"mode"`
	Method             string            `json:"method"`
	RequestedGranularity string          `json:"requested_granularity"`
	Status             string            `json:"status"`
	Outcome            string            `json:"outcome"`
	Cancel             CancelState       `json:"cancel"`
	Ack                *DispatchAck      `json:"ack,omitempty"`
	Requested          RequestedSettings `json:"requested"`
	Observed           ObservedSettings  `json:"observed,omitempty"`
	OwnershipSessionID string            `json:"ownership_session_id"`
	OwnershipProcessID string            `json:"ownership_process_id"`
	OwnershipWorktree  string            `json:"ownership_worktree"`
	Reconstruction     *ReconstructionReport `json:"reconstruction,omitempty"`
	CommittedAt        string            `json:"committed_at"`
	SentAt             string            `json:"sent_at,omitempty"`
	AckedAt            string            `json:"acked_at,omitempty"`
	ReconciledAt       string            `json:"reconciled_at,omitempty"`
	RejectReasons      []string          `json:"reject_reasons,omitempty"`
}

func (d DispatchIntent) Validate() error {
	if d.SchemaVersion != DispatchSchemaVersion {
		return errors.New("unknown dispatch schema version")
	}
	for _, pair := range []struct{ label, v string }{
		{"intent", d.ID}, {"root", d.RootID}, {"reservation", d.ReservationID},
		{"operation", d.OperationID}, {"tuple", d.TupleID},
	} {
		if e := validateID(pair.label, pair.v, true); e != nil {
			return e
		}
	}
	if d.Host == "" || d.InstalledVersion == "" || d.Mode == "" || d.Method == "" {
		return errors.New("incomplete qualified host identity")
	}
	switch d.Status {
	case IntentPendingCommit, IntentCommitted, IntentSent, IntentAcked,
		IntentUncertain, IntentReconciled, IntentRejected, IntentBlocked:
	default:
		return errors.New("unknown intent status")
	}
	switch d.Outcome {
	case "", OutcomeUnknown, OutcomeRunning, OutcomeStopped, OutcomeFailed, OutcomeTransportTerminal:
	default:
		return errors.New("unknown intent outcome")
	}
	if e := d.Cancel.Validate(); e != nil {
		return e
	}
	if d.Ack != nil {
		if e := d.Ack.Validate(); e != nil {
			return e
		}
	}
	if d.Reconstruction != nil {
		if e := d.Reconstruction.Validate(); e != nil {
			return e
		}
	}
	if d.CommittedAt == "" && d.Status != IntentRejected && d.Status != IntentBlocked && d.Status != IntentPendingCommit {
		return errors.New("committed_at required for durable intents")
	}
	return nil
}

// AdmitDispatchRequest drives managed dispatch: reserve → commit intent → send → ack.
type AdmitDispatchRequest struct {
	IntentID             string            `json:"intent_id"`
	RootID               string            `json:"root_id"`
	OperationID          string            `json:"operation_id"`
	IdempotencyKey       string            `json:"idempotency_key,omitempty"`
	TupleID              string            `json:"tuple_id"`
	Method               string            `json:"method"`
	RequestedGranularity string            `json:"requested_granularity"`
	Requested            RequestedSettings `json:"requested"`
	Admit                AdmitRequest      `json:"admit"`
	OwnershipSessionID   string            `json:"ownership_session_id"`
	OwnershipProcessID   string            `json:"ownership_process_id"`
	OwnershipWorktree    string            `json:"ownership_worktree"`
	PortableCheckpointID string            `json:"portable_checkpoint_id,omitempty"`
	LostNativeSession    bool              `json:"lost_native_session"`
	RecordedAt           string            `json:"recorded_at"`
}

func (r AdmitDispatchRequest) Validate() error {
	if e := validateID("intent", r.IntentID, true); e != nil {
		return e
	}
	if e := validateID("root", r.RootID, true); e != nil {
		return e
	}
	if e := validateID("operation", r.OperationID, true); e != nil {
		return e
	}
	if e := validateID("tuple", r.TupleID, true); e != nil {
		return e
	}
	if r.Method == "" {
		return errors.New("method required")
	}
	switch r.RequestedGranularity {
	case GranularitySession, GranularityTurn, GranularityRequest, GranularityTool, GranularityProcess:
	default:
		return fmt.Errorf("unknown requested granularity %q", r.RequestedGranularity)
	}
	if r.OwnershipSessionID == "" || r.OwnershipProcessID == "" || r.OwnershipWorktree == "" {
		return errors.New("ownership identifiers required")
	}
	if r.RecordedAt == "" {
		return errors.New("recorded_at required")
	}
	return nil
}

// AdmitDispatchResult is the managed-dispatch outcome (fixture transport only).
type AdmitDispatchResult struct {
	Admitted       bool            `json:"admitted"`
	Intent         *DispatchIntent `json:"intent,omitempty"`
	ReservationID  string          `json:"reservation_id,omitempty"`
	RejectReasons  []string        `json:"reject_reasons,omitempty"`
	NativeSent     bool            `json:"native_sent"`
	TransportCalls int             `json:"transport_calls"`
}

// CancelDispatchRequest requests cancellation without asserting confirmed stop.
type CancelDispatchRequest struct {
	IntentID   string `json:"intent_id"`
	RootID     string `json:"root_id"`
	RecordedAt string `json:"recorded_at"`
}

// ReconcileDispatchRequest settles ambiguous outcomes before any redispatch.
type ReconcileDispatchRequest struct {
	IntentID   string `json:"intent_id"`
	RootID     string `json:"root_id"`
	RecordedAt string `json:"recorded_at"`
	AllowRedispatch bool `json:"allow_redispatch"`
}

// ReconcileDispatchResult reports reconciliation without blind replay.
type ReconcileDispatchResult struct {
	Status        string          `json:"status"`
	Intent        *DispatchIntent `json:"intent,omitempty"`
	Redispatched  bool            `json:"redispatched"`
	Detail        string          `json:"detail,omitempty"`
}

// DecodeAdmitDispatchRequest strict-decodes a dispatch admit request.
func DecodeAdmitDispatchRequest(raw []byte) (AdmitDispatchRequest, error) {
	var r AdmitDispatchRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// DecodeCancelDispatchRequest strict-decodes a cancel request.
func DecodeCancelDispatchRequest(raw []byte) (CancelDispatchRequest, error) {
	var r CancelDispatchRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	if e := validateID("intent", r.IntentID, true); e != nil {
		return r, e
	}
	if e := validateID("root", r.RootID, true); e != nil {
		return r, e
	}
	if r.RecordedAt == "" {
		return r, errors.New("recorded_at required")
	}
	return r, nil
}

// DecodeReconcileDispatchRequest strict-decodes a reconcile request.
func DecodeReconcileDispatchRequest(raw []byte) (ReconcileDispatchRequest, error) {
	var r ReconcileDispatchRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	if e := validateID("intent", r.IntentID, true); e != nil {
		return r, e
	}
	if e := validateID("root", r.RootID, true); e != nil {
		return r, e
	}
	if r.RecordedAt == "" {
		return r, errors.New("recorded_at required")
	}
	return r, nil
}

// DecodeNativeEvent strict-decodes a native event.
func DecodeNativeEvent(raw []byte) (NativeEvent, error) {
	var e NativeEvent
	if err := StrictJSON(raw, &e); err != nil {
		return e, err
	}
	return e, e.Validate()
}
