package contract

import (
	"encoding/json"
	"errors"
	"reflect"
)

// EligibilityStatus for comparison arms.
const (
	EligibilityEligible   = "eligible"
	EligibilityIneligible = "ineligible"
	EligibilityPending    = "pending"
)

// ArmEligibility records why an arm may or may not run — never fabricates attempts.
type ArmEligibility struct {
	SchemaVersion   int    `json:"schema_version"`
	ID              string `json:"id"`
	TrialID         string `json:"trial_id"`
	ProtocolID      string `json:"protocol_id"`
	ArmID           string `json:"arm_id"`
	ArmKind         string `json:"arm_kind"`
	Status          string `json:"status"`
	Reason          string `json:"reason"`
	MissingPackage  string `json:"missing_package,omitempty"`
	FabricatedAttempts int `json:"fabricated_attempts"`
	RecordedAt      string `json:"recorded_at"`
}

func (e ArmEligibility) Validate() error {
	if e.SchemaVersion != InstrumentSchemaVersion {
		return errors.New("unknown eligibility schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"eligibility", e.ID}, {"trial", e.TrialID}, {"protocol", e.ProtocolID}, {"arm", e.ArmID},
	} {
		if err := validateID(pair.label, pair.id, true); err != nil {
			return err
		}
	}
	switch e.ArmKind {
	case ArmNative, ArmOriginalV3, ArmStructural, ArmManaged:
	default:
		return errors.New("unknown eligibility arm kind")
	}
	switch e.Status {
	case EligibilityEligible, EligibilityIneligible, EligibilityPending:
	default:
		return errors.New("unknown eligibility status")
	}
	if e.Reason == "" {
		return errors.New("eligibility reason required")
	}
	if e.FabricatedAttempts != 0 {
		return errors.New("eligibility must never record fabricated attempts")
	}
	if e.RecordedAt == "" {
		return errors.New("eligibility recorded_at required")
	}
	return nil
}

// PreflightRequest asks whether a catalogue tuple may dispatch under fixture or live rules.
type PreflightRequest struct {
	TupleID              string   `json:"tuple_id"`
	RequiredCapabilities []string `json:"required_capabilities"`
	RequiredBillingMode  string   `json:"required_billing_mode"`
	LiveAdmission        bool     `json:"live_admission"`
	AuthorizeAPIFallback bool     `json:"authorize_api_fallback"`
}

// PreflightResult is fail-closed admission outcome.
type PreflightResult struct {
	Admitted           bool     `json:"admitted"`
	Scope              string   `json:"scope"`
	LiveCriterion      string   `json:"live_criterion"`
	RejectReasons      []string `json:"reject_reasons,omitempty"`
	TransportAllowed   bool     `json:"transport_allowed"`
	APITransportAllowed bool    `json:"api_transport_allowed"`
}

const (
	PreflightScopeFixture = "fixture"
	PreflightScopeLive    = "live"
)

// ExecutionRequest is the immutable route/prompt/tool/model decision surface for shadow equality.
type ExecutionRequest struct {
	RouteInputs        json.RawMessage   `json:"route_inputs"`
	Prompt             string            `json:"prompt"`
	Model              string            `json:"model"`
	Tools              []string          `json:"tools"`
	Settings           map[string]string `json:"settings"`
	BillingMode        string            `json:"billing_mode"`
	ExecutionDecisions []string          `json:"execution_decisions"`
	SelectedRoute      string            `json:"selected_route"`
}

func (r ExecutionRequest) Validate() error {
	if r.Prompt == "" || r.Model == "" || r.SelectedRoute == "" || r.BillingMode == "" {
		return errors.New("incomplete execution request")
	}
	if e := ValidateMetadata(r.Settings); e != nil {
		return e
	}
	return nil
}

func (r ExecutionRequest) CanonicalBytes() ([]byte, error) {
	if e := r.Validate(); e != nil {
		return nil, e
	}
	return json.Marshal(r)
}

// ShadowObservation is an observer artifact that must not alter execution decisions.
type ShadowObservation struct {
	SchemaVersion int               `json:"schema_version"`
	ID            string            `json:"id"`
	Enabled       bool              `json:"enabled"`
	RequestDigest string            `json:"request_digest"`
	ArtifactRef   string            `json:"artifact_ref,omitempty"`
	ObserverError string            `json:"observer_error,omitempty"`
	Metadata      map[string]string `json:"metadata,omitempty"`
	RecordedAt    string            `json:"recorded_at"`
}

func (s ShadowObservation) Validate() error {
	if s.SchemaVersion != InstrumentSchemaVersion {
		return errors.New("unknown shadow schema version")
	}
	if e := validateID("shadow", s.ID, true); e != nil {
		return e
	}
	if s.RequestDigest == "" || s.RecordedAt == "" {
		return errors.New("shadow request digest and recorded_at required")
	}
	if e := ValidateMetadata(s.Metadata); e != nil {
		return e
	}
	return nil
}

// OrderingEvent is append-only controller ordering (freeze before dispatch/outcome).
type OrderingEvent struct {
	Seq        int64  `json:"seq"`
	Kind       string `json:"kind"`
	Ref        string `json:"ref"`
	Digest     string `json:"digest,omitempty"`
	RecordedAt string `json:"recorded_at"`
}

const (
	OrderFreeze     = "freeze"
	OrderDispatch   = "dispatch"
	OrderOutcome    = "outcome"
	OrderEligibility = "eligibility"
	OrderCatalogue  = "catalogue"
)

func RequestsEqual(a, b ExecutionRequest) bool {
	return reflect.DeepEqual(a, b)
}
