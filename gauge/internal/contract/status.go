package contract

import (
	"encoding/json"
	"errors"
	"fmt"
)

// StatusSchemaVersion is the typed V4-20 status-projection namespace under schema 2.
const StatusSchemaVersion = 1

// StatusContractID is the versioned policy/status contract shared by CLI and optional clients.
const StatusContractID = "gauge-status@1"

// Supported status contract IDs for this binary. Future schemas are never guessed into grants.
var SupportedStatusContracts = []string{StatusContractID}

// Delivery presentation states (R01) — separate from verification.
const (
	DeliveryStateImplemented = "implemented"
	DeliveryStateRunnable    = "runnable"
	DeliveryStateCancelled   = "cancelled"
	DeliveryStatePartial     = "partial"
	DeliveryStateBlocked     = "blocked"
	DeliveryStateUnknown     = "unknown"
	DeliveryStateRunning     = "running"
)

// Verification presentation states (R01) — never collapsed into delivery badges.
const (
	VerificationStateNone          = "none"
	VerificationStateChecksPassed  = "checks_passed"
	VerificationStateReviewPending = "review_pending"
	VerificationStateReleased      = "released"
	VerificationStateStaleEvidence = "stale_evidence"
)

// Participation patterns (R02) — method use ≠ fictional team roster.
const (
	ParticipationOneMakerManyMethods       = "one_maker_many_methods"
	ParticipationSeparateSpecialistChecker = "separate_specialist_checker"
)

// Quota limitation kinds (R03) — plain-text only; no invented percentages.
const (
	QuotaUnsupported       = "unsupported"
	QuotaStale             = "stale"
	QuotaUnknownBucket     = "unknown_bucket"
	QuotaAdvisoryOnly      = "advisory_only"
	QuotaOutsideController = "outside_controller"
)

// Cancellation projection stages (R06) — ack ≠ stop ≠ accounting reconciliation.
const (
	CancelStageNone                 = "none"
	CancelStageRequestAcknowledged  = "request_acknowledged"
	CancelStageConfirmedStop        = "confirmed_stop"
	CancelStageAccountingReconciled = "accounting_reconciled"
)

// Client presentation controls (R05).
const (
	ClientModeNoGUI   = "no_gui"
	ClientModeNoColor = "no_color"
)

// MethodParticipation records a method without inventing a worker identity.
type MethodParticipation struct {
	MethodID    string `json:"method_id"`
	ReportClass string `json:"report_class"` // method_use | specialist_invocation
	DerivedFrom string `json:"derived_from,omitempty"`
}

// WorkerParticipation records an observed worker with optional separation evidence.
type WorkerParticipation struct {
	WorkerID           string   `json:"worker_id"`
	Role               string   `json:"role"` // maker | specialist | checker
	ContinuingMaker    bool     `json:"continuing_maker"`
	ContextSeparation  bool     `json:"context_separation"`
	SeparationEvidence []string `json:"separation_evidence,omitempty"`
	InvocationID       string   `json:"invocation_id,omitempty"`
}

// ParticipationView distinguishes methods, workers, and separation (R02).
type ParticipationView struct {
	SchemaVersion int                   `json:"schema_version"`
	Pattern       string                `json:"pattern"`
	Methods       []MethodParticipation `json:"methods"`
	Workers       []WorkerParticipation `json:"workers"`
	FictionalTeam bool                  `json:"fictional_team"` // must always be false
	ObservedOnly  bool                  `json:"observed_only"`
}

func (p ParticipationView) Validate() error {
	if p.SchemaVersion != StatusSchemaVersion {
		return errors.New("unknown participation schema version")
	}
	if p.FictionalTeam {
		return errors.New("fictional team must never be asserted")
	}
	switch p.Pattern {
	case ParticipationOneMakerManyMethods, ParticipationSeparateSpecialistChecker, "":
	default:
		return fmt.Errorf("unknown participation pattern %q", p.Pattern)
	}
	return nil
}

// QuotaLimitation is plain-text disclosure when quota/enforcement is unsupported or stale (R03).
type QuotaLimitation struct {
	Kind              string   `json:"kind"`
	PlainText         string   `json:"plain_text"`
	Bucket            string   `json:"bucket,omitempty"`
	PercentageKnown   bool     `json:"percentage_known"`
	Percentage        *float64 `json:"percentage,omitempty"` // must be nil when unknown
	AdvisoryOnly      bool     `json:"advisory_only"`
	OutsideController bool     `json:"outside_controller"`
}

func (q QuotaLimitation) Validate() error {
	switch q.Kind {
	case QuotaUnsupported, QuotaStale, QuotaUnknownBucket, QuotaAdvisoryOnly, QuotaOutsideController:
	default:
		return fmt.Errorf("unknown quota limitation kind %q", q.Kind)
	}
	if q.PlainText == "" {
		return errors.New("quota limitation plain_text required")
	}
	if !q.PercentageKnown && q.Percentage != nil {
		return errors.New("unknown quota must not invent a percentage")
	}
	if q.PercentageKnown && q.Percentage == nil {
		return errors.New("percentage_known requires percentage value")
	}
	return nil
}

// CancellationProjection separates request ack, confirmed stop, and accounting (R06).
type CancellationProjection struct {
	SchemaVersion          int    `json:"schema_version"`
	Stage                  string `json:"stage"`
	RequestAcknowledged    bool   `json:"request_acknowledged"`
	ConfirmedStop          bool   `json:"confirmed_stop"`
	AccountingReconciled   bool   `json:"accounting_reconciled"`
	ProcessAlive           bool   `json:"process_alive"`
	LateUsage              bool   `json:"late_usage"`
	PrematureDoneDisplayed bool   `json:"premature_done_displayed"`  // must stay false until reconciled
	PrematureRefundClaimed bool   `json:"premature_refund_claimed"` // must stay false until reconciled
	SourceCancelState      string `json:"source_cancel_state,omitempty"`
}

func (c CancellationProjection) Validate() error {
	if c.SchemaVersion != StatusSchemaVersion {
		return errors.New("unknown cancellation projection schema version")
	}
	switch c.Stage {
	case CancelStageNone, CancelStageRequestAcknowledged, CancelStageConfirmedStop, CancelStageAccountingReconciled:
	default:
		return fmt.Errorf("unknown cancellation stage %q", c.Stage)
	}
	if c.PrematureDoneDisplayed || c.PrematureRefundClaimed {
		return errors.New("premature done/refund display is forbidden")
	}
	if c.AccountingReconciled && (!c.ConfirmedStop || !c.RequestAcknowledged) {
		return errors.New("accounting reconciliation requires prior ack and confirmed stop")
	}
	return nil
}

// CompatibilityDiagnostic is retained when a client presents an unsupported contract (R07).
type CompatibilityDiagnostic struct {
	SchemaVersion       int      `json:"schema_version"`
	PresentedContract   string   `json:"presented_contract"`
	SupportedContracts  []string `json:"supported_contracts"`
	AuthorityMutations  string   `json:"authority_mutations"` // rejected
	ReadOnlyAllowed     bool     `json:"read_only_allowed"`
	DispatchedModelWork bool     `json:"dispatched_model_work"` // must be false
	Detail              string   `json:"detail"`
}

func (d CompatibilityDiagnostic) Validate() error {
	if d.SchemaVersion != StatusSchemaVersion {
		return errors.New("unknown compatibility diagnostic schema version")
	}
	if d.AuthorityMutations != "rejected" {
		return errors.New("unsupported contract must reject authority-bearing mutations")
	}
	if d.DispatchedModelWork {
		return errors.New("compatibility diagnostic must not dispatch model work")
	}
	if d.Detail == "" {
		return errors.New("compatibility diagnostic detail required")
	}
	return nil
}

// StatusProjection is the observational CLI/JSON view over canonical delivery/verification state (R01–R07).
// It never refills budgets or creates live-evidence claims.
type StatusProjection struct {
	SchemaVersion           int                     `json:"schema_version"`
	ContractVersion         string                  `json:"contract_version"`
	LoopID                  string                  `json:"loop_id,omitempty"`
	RootID                  string                  `json:"root_id,omitempty"`
	DeliveryState           string                  `json:"delivery_state"`
	VerificationState       string                  `json:"verification_state"`
	TerminalBadge           string                  `json:"terminal_badge,omitempty"` // never equals acceptance
	GreenBadgeMeans         string                  `json:"green_badge_means"`        // always "not_acceptance"
	Accepted                bool                    `json:"accepted"`
	Participation           ParticipationView       `json:"participation"`
	QuotaLimitation         *QuotaLimitation        `json:"quota_limitation,omitempty"`
	Cancellation            *CancellationProjection `json:"cancellation,omitempty"`
	Inspect                 *InspectSnapshot        `json:"inspect,omitempty"`
	OutstandingReservations []string                `json:"outstanding_reservations,omitempty"`
	ModelCalls              int                     `json:"model_calls"`
	FilesystemReads         int                     `json:"filesystem_reads"`
	FilesystemWrites        int                     `json:"filesystem_writes"`
	DeniedEscalation        bool                    `json:"denied_escalation,omitempty"`
	ObservationalOnly       bool                    `json:"observational_only"`
	Slice                   string                  `json:"slice"`           // core-cli
	OptionalGAMBIT          string                  `json:"optional_gambit"` // explicitly deferred
}

func (s StatusProjection) Validate() error {
	if s.SchemaVersion != StatusSchemaVersion {
		return errors.New("unknown status projection schema version")
	}
	if s.ContractVersion != StatusContractID {
		return errors.New("unsupported status contract version")
	}
	if s.GreenBadgeMeans != "not_acceptance" {
		return errors.New("green/terminal badge must not imply acceptance")
	}
	if !s.ObservationalOnly {
		return errors.New("status projection must be observational_only")
	}
	if s.OptionalGAMBIT != "explicitly_deferred" {
		return errors.New("optional-GAMBIT deferral must be explicit")
	}
	if e := s.Participation.Validate(); e != nil {
		return e
	}
	if s.QuotaLimitation != nil {
		if e := s.QuotaLimitation.Validate(); e != nil {
			return e
		}
	}
	if s.Cancellation != nil {
		if e := s.Cancellation.Validate(); e != nil {
			return e
		}
	}
	return nil
}

// PolicyInspectResult is a no-model policy/status inspect (R04).
type PolicyInspectResult struct {
	SchemaVersion           int      `json:"schema_version"`
	ContractVersion         string   `json:"contract_version"`
	RootID                  string   `json:"root_id,omitempty"`
	PolicyID                string   `json:"policy_id,omitempty"`
	ModelCalls              int      `json:"model_calls"`
	DeniedEscalation        bool     `json:"denied_escalation"`
	EscalationAttempt       string   `json:"escalation_attempt,omitempty"`
	OutstandingReservations []string `json:"outstanding_reservations"`
	Dispatched              bool     `json:"dispatched"` // must be false
	Preview                 bool     `json:"preview"`
	Detail                  string   `json:"detail,omitempty"`
}

func (r PolicyInspectResult) Validate() error {
	if r.SchemaVersion != StatusSchemaVersion {
		return errors.New("unknown policy inspect schema version")
	}
	if r.Dispatched || r.ModelCalls != 0 {
		return errors.New("policy inspect/preview must not dispatch model work")
	}
	return nil
}

// ClientConformanceRequest exercises the shared policy/status contract (R05/R07).
type ClientConformanceRequest struct {
	SchemaVersion     int      `json:"schema_version"`
	ContractVersion   string   `json:"contract_version"`
	Modes             []string `json:"modes"` // no_gui, no_color
	AuthorityMutation bool     `json:"authority_mutation"`
	ReadOnly          bool     `json:"read_only"`
}

func (r ClientConformanceRequest) Validate() error {
	if r.SchemaVersion != StatusSchemaVersion {
		return errors.New("unknown client conformance schema version")
	}
	if r.ContractVersion == "" {
		return errors.New("contract_version required")
	}
	for _, m := range r.Modes {
		switch m {
		case ClientModeNoGUI, ClientModeNoColor:
		default:
			return fmt.Errorf("unknown client mode %q", m)
		}
	}
	return nil
}

// ClientConformanceResult is the fixture-consumer response (GAMBIT itself deferred).
type ClientConformanceResult struct {
	SchemaVersion      int                      `json:"schema_version"`
	ContractVersion    string                   `json:"contract_version"`
	Supported          bool                     `json:"supported"`
	NoGUI              bool                     `json:"no_gui"`
	NoColor            bool                     `json:"no_color"`
	Error              string                   `json:"error,omitempty"`
	Compatibility      *CompatibilityDiagnostic `json:"compatibility,omitempty"`
	MutationRejected   bool                     `json:"mutation_rejected"`
	ModelCalls         int                      `json:"model_calls"`
	ConsumedProjection bool                     `json:"consumed_projection"`
	OptionalGAMBIT     string                   `json:"optional_gambit"`
}

func DecodeClientConformanceRequest(raw []byte) (ClientConformanceRequest, error) {
	var req ClientConformanceRequest
	if e := StrictJSON(raw, &req); e != nil {
		return req, e
	}
	return req, req.Validate()
}

func DecodeStatusProjection(raw []byte) (StatusProjection, error) {
	var p StatusProjection
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}

// ContractSupported reports whether a presented contract ID is known to this binary.
func ContractSupported(presented string) bool {
	for _, s := range SupportedStatusContracts {
		if s == presented {
			return true
		}
	}
	return false
}

// ProjectDeliveryState maps a delivery loop to a presentation delivery state (R01).
func ProjectDeliveryState(loop DeliveryLoop) string {
	switch {
	case loop.Status == PhaseCancelled || loop.Phase == PhaseCancelled:
		return DeliveryStateCancelled
	case loop.Status == PhaseCancellationPending || loop.Phase == PhaseCancellationPending:
		return DeliveryStateRunning // still running until confirmed stop
	case loop.Partial:
		return DeliveryStatePartial
	case loop.Blocked:
		return DeliveryStateBlocked
	case loop.Accepted && loop.MilestoneRunnable:
		return DeliveryStateRunnable
	case loop.Accepted:
		return DeliveryStateImplemented
	case loop.MilestoneRunnable:
		return DeliveryStateRunnable
	case loop.Status == PhaseRunning || loop.Phase == PhaseRunning ||
		loop.Status == PhasePending || loop.Phase == PhaseEdit ||
		loop.Phase == PhaseCheck || loop.Phase == PhaseFreeze ||
		loop.Phase == PhaseDispatch || loop.Phase == PhaseAdmit ||
		loop.Phase == PhaseCheckpoint:
		return DeliveryStateRunning
	case loop.Status == PhaseUnknown || loop.Phase == PhaseUnknown:
		return DeliveryStateUnknown
	default:
		if loop.Phase == PhaseAccepted {
			return DeliveryStateImplemented
		}
		return DeliveryStateUnknown
	}
}

// ProjectVerificationState maps observed check/review/release evidence (R01).
// Stale evidence is never promoted to checks_passed or released.
func ProjectVerificationState(loop DeliveryLoop, checksPassed, reviewPending, released bool) string {
	if loop.Limitation != nil {
		switch loop.Limitation.Kind {
		case "changed_criteria", "tampered_payload", "missing_native_history", "memory_outage":
			return VerificationStateStaleEvidence
		}
	}
	if released {
		return VerificationStateReleased
	}
	if reviewPending {
		return VerificationStateReviewPending
	}
	if checksPassed {
		return VerificationStateChecksPassed
	}
	return VerificationStateNone
}

// ProjectCancellationFromDispatch projects V4-12 CancelState into the status view (R06).
func ProjectCancellationFromDispatch(c CancelState) CancellationProjection {
	out := CancellationProjection{
		SchemaVersion:     StatusSchemaVersion,
		SourceCancelState: c.State,
		ProcessAlive:      c.ProcessAlive,
		LateUsage:         c.UsageDelayed,
	}
	switch c.State {
	case CancelNone, "":
		out.Stage = CancelStageNone
	case CancelRequested, CancelInterruptAccepted:
		out.Stage = CancelStageRequestAcknowledged
		out.RequestAcknowledged = c.State == CancelInterruptAccepted || c.RequestedAt != ""
		if c.State == CancelInterruptAccepted {
			out.RequestAcknowledged = true
		}
	case CancelConfirmedStopped:
		out.Stage = CancelStageConfirmedStop
		out.RequestAcknowledged = true
		out.ConfirmedStop = true
		out.ProcessAlive = false
	case CancelFinalReconciled:
		out.Stage = CancelStageAccountingReconciled
		out.RequestAcknowledged = true
		out.ConfirmedStop = true
		out.AccountingReconciled = true
		out.ProcessAlive = false
		out.LateUsage = false
	default:
		out.Stage = CancelStageNone
	}
	out.PrematureDoneDisplayed = false
	out.PrematureRefundClaimed = false
	return out
}

// ProjectParticipation synthesizes an honest participation view from observed assignments (R02).
func ProjectParticipation(assignments []Assignment) ParticipationView {
	view := ParticipationView{
		SchemaVersion: StatusSchemaVersion,
		ObservedOnly:  true,
		FictionalTeam: false,
	}
	makers := map[string]bool{}
	separated := false
	for _, a := range assignments {
		w := WorkerParticipation{
			WorkerID:        a.WorkerID,
			ContinuingMaker: a.Continuing,
			ContextSeparation: a.Boundary == BoundaryContextSeparation || a.Boundary == BoundaryVerification ||
				a.Boundary == BoundaryIndependentConsult || a.Boundary == BoundaryIsolatedWriter,
		}
		if a.Continuing {
			w.Role = "maker"
			makers[a.WorkerID] = true
		} else {
			separated = true
			switch a.Boundary {
			case BoundaryVerification:
				w.Role = "checker"
			default:
				w.Role = "specialist"
			}
			if w.ContextSeparation {
				w.SeparationEvidence = append(w.SeparationEvidence, a.Boundary)
			}
		}
		for _, m := range a.Methods {
			view.Methods = append(view.Methods, MethodParticipation{
				MethodID:    m.MethodID,
				ReportClass: m.ReportClass,
				DerivedFrom: m.Contract.DerivedFrom,
			})
			if m.InvocationID != "" && w.InvocationID == "" {
				w.InvocationID = m.InvocationID
			}
		}
		view.Workers = append(view.Workers, w)
	}
	switch {
	case separated:
		view.Pattern = ParticipationSeparateSpecialistChecker
	default:
		view.Pattern = ParticipationOneMakerManyMethods
	}
	return view
}

// EncodeJSON is a small helper for fixture consumers.
func EncodeJSON(v any) ([]byte, error) {
	return json.Marshal(v)
}
