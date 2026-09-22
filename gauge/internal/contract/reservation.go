package contract

import (
	"encoding/json"
	"errors"
	"fmt"
	"math"
)

// ReservationSchemaVersion is the typed reservation namespace version under schema 2.
const ReservationSchemaVersion = 1

// Exposure classification for reserved capacity (actual vs estimate vs unknown).
const (
	ExposureKnown      = "known"
	ExposureEstimated  = "estimated"
	ExposureUncertain  = "uncertain"
)

// HeadroomKind distinguishes protected verification/recovery from optional work.
const (
	HeadroomImplementation = "implementation"
	HeadroomVerification   = "verification"
	HeadroomRecovery       = "recovery"
	HeadroomIntegration    = "integration"
)

// WorkKind selects admission rules (optional vs protected vs child/retry).
const (
	WorkOptionalImplementation = "optional_implementation"
	WorkVerification           = "verification"
	WorkRecovery               = "recovery"
	WorkIntegration            = "integration"
	WorkChild                  = "child"
	WorkRetry                  = "retry"
)

// Reservation status values.
const (
	ReservationAdmitted    = "admitted"
	ReservationUncertain   = "uncertain"
	ReservationReconciled  = "reconciled"
	ReservationReleased    = "released"
	ReservationRejected    = "rejected"
)

// EstimateProvenance records how an admission amount was obtained.
const (
	ProvenanceEstimate        = "estimate"
	ProvenanceObserved        = "observed"
	ProvenanceAuthorizedBound = "authorized_bound"
	ProvenanceUnknown         = "unknown"
)

// EstimateProvenance is inspectable estimate origin — not a billing claim.
type EstimateProvenance struct {
	Kind   string `json:"kind"`
	Source string `json:"source,omitempty"`
}

func (p EstimateProvenance) Validate() error {
	switch p.Kind {
	case ProvenanceEstimate, ProvenanceObserved, ProvenanceAuthorizedBound, ProvenanceUnknown:
	default:
		return errors.New("unknown estimate provenance")
	}
	return nil
}

// ScopeBalanceKey identifies one local ceiling dimension for bookkeeping.
type ScopeBalanceKey struct {
	Scope    string `json:"scope"`
	Identity string `json:"identity"`
	Resource string `json:"resource"`
	Unit     string `json:"unit"`
	Pool     string `json:"pool"`
}

func (k ScopeBalanceKey) Validate() error {
	switch k.Scope {
	case "task", "project", "account", "window", "concurrency":
	default:
		return errors.New("unknown reservation scope")
	}
	for _, part := range []string{k.Identity, k.Resource, k.Unit, k.Pool} {
		if part == "" || len(part) > 256 {
			return errors.New("incomplete or oversized scope balance key")
		}
	}
	return nil
}

func (k ScopeBalanceKey) String() string {
	b, _ := json.Marshal([]string{k.Scope, k.Identity, k.Resource, k.Unit, k.Pool})
	return string(b)
}

// ScopeBalance is local reserved/consumed/uncertain exposure against a known ceiling.
type ScopeBalance struct {
	Key                    ScopeBalanceKey `json:"key"`
	Ceiling                *float64        `json:"ceiling"`
	Reserved               float64         `json:"reserved"`
	Consumed               float64         `json:"consumed"`
	Uncertain              float64         `json:"uncertain"`
	ProtectedVerification  float64         `json:"protected_verification"`
	ProtectedRecovery      float64         `json:"protected_recovery"`
	WindowEpoch            string          `json:"window_epoch,omitempty"`
	HardLimited            bool            `json:"hard_limited"`
	ObservationUsable      bool            `json:"observation_usable"`
	AuthorizedBound        *float64        `json:"authorized_bound,omitempty"`
	ExplicitBoundedMode    bool            `json:"explicit_bounded_mode"`
}

func (b ScopeBalance) Validate() error {
	if e := b.Key.Validate(); e != nil {
		return e
	}
	for _, n := range []float64{b.Reserved, b.Consumed, b.Uncertain, b.ProtectedVerification, b.ProtectedRecovery} {
		if math.IsNaN(n) || math.IsInf(n, 0) || n < 0 {
			return errors.New("scope balance amounts must be finite and nonnegative")
		}
	}
	if b.Ceiling != nil && (math.IsNaN(*b.Ceiling) || math.IsInf(*b.Ceiling, 0) || *b.Ceiling < 0) {
		return errors.New("ceiling must be finite and nonnegative")
	}
	if b.AuthorizedBound != nil && (math.IsNaN(*b.AuthorizedBound) || math.IsInf(*b.AuthorizedBound, 0) || *b.AuthorizedBound < 0) {
		return errors.New("authorized bound must be finite and nonnegative")
	}
	return nil
}

// EffectiveCeiling returns the usable local ceiling, preferring authorized bound when set under explicit bounded mode.
func (b ScopeBalance) EffectiveCeiling() (*float64, error) {
	if b.Ceiling != nil {
		return b.Ceiling, nil
	}
	if b.ExplicitBoundedMode && b.AuthorizedBound != nil {
		return b.AuthorizedBound, nil
	}
	if b.HardLimited {
		return nil, errors.New("hard-limited dimension lacks usable observation or authorized bound")
	}
	return nil, nil
}

// AvailableFor reports remaining capacity for a work kind, protecting verification/recovery headroom.
func (b ScopeBalance) AvailableFor(workKind string) (float64, error) {
	ceil, e := b.EffectiveCeiling()
	if e != nil {
		return 0, e
	}
	if ceil == nil {
		// No known local ceiling on this scope — admission must not invent a grant.
		return 0, errors.New("no known local ceiling for scope")
	}
	used := b.Reserved + b.Consumed + b.Uncertain
	switch workKind {
	case WorkOptionalImplementation, WorkChild, WorkRetry, WorkIntegration:
		used += b.ProtectedVerification + b.ProtectedRecovery
	case WorkVerification:
		// Verification may consume its designated reserve; do not double-count protection.
	case WorkRecovery:
		// Recovery may consume its designated reserve.
	default:
		return 0, errors.New("unknown work kind for availability")
	}
	avail := *ceil - used
	if avail < 0 {
		return 0, nil
	}
	return avail, nil
}

// ExposureTotal is the non-clamped exposure that must remain visible (consumed + reserved + uncertain).
func (b ScopeBalance) ExposureTotal() float64 {
	return b.Reserved + b.Consumed + b.Uncertain
}

// Reservation is a durable local admission hold before any external dispatch.
type Reservation struct {
	SchemaVersion         int                `json:"schema_version"`
	ID                    string             `json:"id"`
	RootID                string             `json:"root_id"`
	ParentReservationID   string             `json:"parent_reservation_id,omitempty"`
	AssignmentID          string             `json:"assignment_id"`
	ProjectID             string             `json:"project_id"`
	AccountPool           string             `json:"account_pool"`
	WindowEpoch           string             `json:"window_epoch"`
	TaskID                string             `json:"task_id"`
	HeadroomKind          string             `json:"headroom_kind"`
	WorkKind              string             `json:"work_kind"`
	Amount                float64            `json:"amount"`
	EstimateProvenance    EstimateProvenance `json:"estimate_provenance"`
	Exposure              string             `json:"exposure"`
	Resource              string             `json:"resource"`
	Unit                  string             `json:"unit"`
	Pool                  string             `json:"pool"`
	Status                string             `json:"status"`
	ImplementationAmount  float64            `json:"implementation_amount,omitempty"`
	IntegrationAmount     float64            `json:"integration_amount,omitempty"`
	VerificationAmount    float64            `json:"verification_amount,omitempty"`
	PolicyID              string             `json:"policy_id,omitempty"`
	RecordedAt            string             `json:"recorded_at"`
	UncertainReason       string             `json:"uncertain_reason,omitempty"`
	ReleaseProof          string             `json:"release_proof,omitempty"`
}

func (r Reservation) Validate() error {
	if r.SchemaVersion != ReservationSchemaVersion {
		return errors.New("unknown reservation schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"reservation", r.ID}, {"root", r.RootID}, {"assignment", r.AssignmentID},
		{"project", r.ProjectID}, {"account_pool", r.AccountPool}, {"task", r.TaskID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if e := validateID("parent_reservation", r.ParentReservationID, false); e != nil {
		return e
	}
	if r.WindowEpoch == "" || len(r.WindowEpoch) > 256 {
		return errors.New("window epoch required")
	}
	switch r.HeadroomKind {
	case HeadroomImplementation, HeadroomVerification, HeadroomRecovery, HeadroomIntegration:
	default:
		return errors.New("unknown headroom kind")
	}
	switch r.WorkKind {
	case WorkOptionalImplementation, WorkVerification, WorkRecovery, WorkIntegration, WorkChild, WorkRetry:
	default:
		return errors.New("unknown work kind")
	}
	if math.IsNaN(r.Amount) || math.IsInf(r.Amount, 0) || r.Amount < 0 {
		return errors.New("reservation amount must be finite and nonnegative")
	}
	if e := r.EstimateProvenance.Validate(); e != nil {
		return e
	}
	switch r.Exposure {
	case ExposureKnown, ExposureEstimated, ExposureUncertain:
	default:
		return errors.New("unknown exposure classification")
	}
	if r.Resource == "" || r.Unit == "" || r.Pool == "" {
		return errors.New("incomplete reservation resource dimensions")
	}
	switch r.Status {
	case ReservationAdmitted, ReservationUncertain, ReservationReconciled, ReservationReleased, ReservationRejected:
	default:
		return errors.New("unknown reservation status")
	}
	if r.RecordedAt == "" {
		return errors.New("reservation recorded_at required")
	}
	return nil
}

// AdmitRequest is a local-only admission request; never embeds a provider call.
type AdmitRequest struct {
	ID                   string             `json:"id"`
	RootID               string             `json:"root_id"`
	ParentReservationID  string             `json:"parent_reservation_id,omitempty"`
	AssignmentID         string             `json:"assignment_id"`
	ProjectID            string             `json:"project_id"`
	AccountPool          string             `json:"account_pool"`
	WindowEpoch          string             `json:"window_epoch"`
	TaskID               string             `json:"task_id"`
	HeadroomKind         string             `json:"headroom_kind"`
	WorkKind             string             `json:"work_kind"`
	Amount               float64            `json:"amount"`
	EstimateProvenance   EstimateProvenance `json:"estimate_provenance"`
	Resource             string             `json:"resource"`
	Unit                 string             `json:"unit"`
	Pool                 string             `json:"pool"`
	PolicyID             string             `json:"policy_id"`
	Ceilings             []Ceiling          `json:"ceilings"`
	ProtectedVerification float64           `json:"protected_verification"`
	ProtectedRecovery    float64            `json:"protected_recovery"`
	ImplementationAmount float64            `json:"implementation_amount,omitempty"`
	IntegrationAmount    float64            `json:"integration_amount,omitempty"`
	VerificationAmount   float64            `json:"verification_amount,omitempty"`
	HardLimited          bool               `json:"hard_limited"`
	ObservationUsable    bool               `json:"observation_usable"`
	AuthorizedBound      *float64           `json:"authorized_bound,omitempty"`
	ExplicitBoundedMode  bool               `json:"explicit_bounded_mode"`
	ConcurrencyIdentity  string             `json:"concurrency_identity,omitempty"`
	ConcurrencyAmount    float64            `json:"concurrency_amount,omitempty"`
	RecordedAt           string             `json:"recorded_at"`
}

func (r AdmitRequest) Validate() error {
	tmp := Reservation{
		SchemaVersion: ReservationSchemaVersion, ID: r.ID, RootID: r.RootID,
		ParentReservationID: r.ParentReservationID, AssignmentID: r.AssignmentID,
		ProjectID: r.ProjectID, AccountPool: r.AccountPool, WindowEpoch: r.WindowEpoch,
		TaskID: r.TaskID, HeadroomKind: r.HeadroomKind, WorkKind: r.WorkKind,
		Amount: r.Amount, EstimateProvenance: r.EstimateProvenance,
		Exposure: ExposureEstimated, Resource: r.Resource, Unit: r.Unit, Pool: r.Pool,
		Status: ReservationAdmitted, RecordedAt: r.RecordedAt,
		ImplementationAmount: r.ImplementationAmount, IntegrationAmount: r.IntegrationAmount,
		VerificationAmount: r.VerificationAmount, PolicyID: r.PolicyID,
	}
	if e := tmp.Validate(); e != nil {
		return e
	}
	if r.PolicyID == "" {
		return errors.New("admit requires active policy identity")
	}
	for _, c := range r.Ceilings {
		if e := c.Validate(); e != nil {
			return e
		}
	}
	for _, n := range []float64{r.ProtectedVerification, r.ProtectedRecovery, r.ConcurrencyAmount} {
		if math.IsNaN(n) || math.IsInf(n, 0) || n < 0 {
			return errors.New("protected/concurrency amounts must be finite and nonnegative")
		}
	}
	if r.HardLimited && !r.ObservationUsable && r.AuthorizedBound == nil {
		return errors.New("hard-limited dimension lacks usable observation or authorized bound")
	}
	if r.HardLimited && !r.ObservationUsable && r.AuthorizedBound != nil && !r.ExplicitBoundedMode {
		return errors.New("authorized bound requires explicit bounded mode")
	}
	return nil
}

// AdmitResult is the local admission outcome with scoped balances.
type AdmitResult struct {
	Admitted       bool           `json:"admitted"`
	ReservationID  string         `json:"reservation_id,omitempty"`
	RejectReasons  []string       `json:"reject_reasons,omitempty"`
	Reservation    *Reservation   `json:"reservation,omitempty"`
	Balances       []ScopeBalance `json:"balances,omitempty"`
	AccountingOK   bool           `json:"accounting_ok"`
}

// AmendRequest updates reserved exposure from observed consumption without clamping away overrun.
type AmendRequest struct {
	ReservationID string  `json:"reservation_id"`
	Observed      float64 `json:"observed"`
	Kind          string  `json:"kind"` // overrun | late_usage | correction
	RecordedAt    string  `json:"recorded_at"`
}

const (
	AmendOverrun    = "overrun"
	AmendLateUsage  = "late_usage"
	AmendCorrection = "correction"
)

func (a AmendRequest) Validate() error {
	if e := validateID("reservation", a.ReservationID, true); e != nil {
		return e
	}
	if math.IsNaN(a.Observed) || math.IsInf(a.Observed, 0) || a.Observed < 0 {
		return errors.New("observed amount must be finite and nonnegative")
	}
	switch a.Kind {
	case AmendOverrun, AmendLateUsage, AmendCorrection:
	default:
		return errors.New("unknown amend kind")
	}
	if a.RecordedAt == "" {
		return errors.New("amend recorded_at required")
	}
	return nil
}

// MarkUncertainRequest retains uncertain exposure after ambiguous dispatch outcomes.
type MarkUncertainRequest struct {
	ReservationID string `json:"reservation_id"`
	Reason        string `json:"reason"` // crash | timeout | missing_callback | cancellation_after_send
	RecordedAt    string `json:"recorded_at"`
}

const (
	UncertainCrash                 = "crash"
	UncertainTimeout               = "timeout"
	UncertainMissingCallback       = "missing_callback"
	UncertainCancellationAfterSend = "cancellation_after_send"
)

func (m MarkUncertainRequest) Validate() error {
	if e := validateID("reservation", m.ReservationID, true); e != nil {
		return e
	}
	switch m.Reason {
	case UncertainCrash, UncertainTimeout, UncertainMissingCallback, UncertainCancellationAfterSend:
	default:
		return errors.New("unknown uncertain reason")
	}
	if m.RecordedAt == "" {
		return errors.New("uncertain recorded_at required")
	}
	return nil
}

// ReconcileRequest settles or proves release of a reservation after explicit reconciliation.
type ReconcileRequest struct {
	ReservationID string  `json:"reservation_id"`
	Actual        float64 `json:"actual"`
	Release       bool    `json:"release"`
	ReleaseProof  string  `json:"release_proof,omitempty"`
	RecordedAt    string  `json:"recorded_at"`
}

func (r ReconcileRequest) Validate() error {
	if e := validateID("reservation", r.ReservationID, true); e != nil {
		return e
	}
	if math.IsNaN(r.Actual) || math.IsInf(r.Actual, 0) || r.Actual < 0 {
		return errors.New("reconcile actual must be finite and nonnegative")
	}
	if r.Release && r.ReleaseProof == "" {
		return errors.New("release requires explicit proof")
	}
	if r.RecordedAt == "" {
		return errors.New("reconcile recorded_at required")
	}
	return nil
}

// WindowResetRequest changes provider window accounting without refilling task budget.
type WindowResetRequest struct {
	RootID       string `json:"root_id"`
	Resource     string `json:"resource"`
	Unit         string `json:"unit"`
	Pool         string `json:"pool"`
	OldEpoch     string `json:"old_epoch"`
	NewEpoch     string `json:"new_epoch"`
	NewWindowCeiling *float64 `json:"new_window_ceiling,omitempty"`
	RecordedAt   string `json:"recorded_at"`
}

func (w WindowResetRequest) Validate() error {
	if e := validateID("root", w.RootID, true); e != nil {
		return e
	}
	if w.Resource == "" || w.Unit == "" || w.Pool == "" || w.OldEpoch == "" || w.NewEpoch == "" {
		return errors.New("incomplete window reset")
	}
	if w.OldEpoch == w.NewEpoch {
		return errors.New("window reset requires a new epoch")
	}
	if w.RecordedAt == "" {
		return errors.New("window reset recorded_at required")
	}
	return nil
}

// DecodeAdmitRequest strict-decodes an admit request.
func DecodeAdmitRequest(raw []byte) (AdmitRequest, error) {
	var r AdmitRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// CeilingForScope returns the intersecting known ceiling for a scope, or nil if absent.
func CeilingForScope(ceilings []Ceiling, scope, resource, unit, pool string) *float64 {
	var found *float64
	for i := range ceilings {
		c := ceilings[i]
		if c.Scope != scope || c.Resource != resource || c.Unit != unit || c.Pool != pool {
			continue
		}
		if c.Limit == nil {
			continue
		}
		if found == nil || *c.Limit < *found {
			v := *c.Limit
			found = &v
		}
	}
	return found
}

// ChildJointAmount is implementation + integration + required verification under a parent.
func ChildJointAmount(implementation, integration, verification float64) (float64, error) {
	for _, n := range []float64{implementation, integration, verification} {
		if math.IsNaN(n) || math.IsInf(n, 0) || n < 0 {
			return 0, errors.New("child amounts must be finite and nonnegative")
		}
	}
	return implementation + integration + verification, nil
}

// FormatReject joins reject reasons for diagnostics.
func FormatReject(reasons []string) string {
	if len(reasons) == 0 {
		return "admission rejected"
	}
	b, _ := json.Marshal(reasons)
	return fmt.Sprintf("admission rejected: %s", string(b))
}
