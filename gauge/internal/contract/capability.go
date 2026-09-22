package contract

import (
	"encoding/json"
	"errors"
	"fmt"
)

// InstrumentSchemaVersion is the typed V4-09 instrument namespace version.
const InstrumentSchemaVersion = 1

// OriginalV3ControlSHA is the pinned original-v3 control identity (v3.3.1).
const OriginalV3ControlSHA = "752194ef5ceaa8cee1f5995fd0d374888696d8fc"

// NativeControlIdentity labels the distinct untouched native control.
const NativeControlIdentity = "native-untouched-control"

// Evidence and qualification labels.
const (
	EvidenceVerified      = "verified"
	EvidenceUnverified    = "unverified"
	EvidenceDiscoveryOnly = "discovery_only"
	EvidenceAbsent        = "absent"

	EvidenceSourceFixture       = "fixture"
	EvidenceSourceHelpDiscovery = "help_discovery"
	EvidenceSourceRegistration  = "registration"
	EvidenceSourceLiveProbe     = "live_probe"

	LiveCriterionBlocked    = "blocked"
	LiveCriterionQualified  = "qualified"
	LiveCriterionNotClaimed = "not_claimed"

	GranularitySession = "session"
	GranularityTurn    = "turn"
	GranularityRequest = "request"
	GranularityTool    = "tool"
	GranularityProcess = "process"

	BoundarySandboxed  = "sandboxed"
	BoundaryPrivileged = "privileged"

	MaturityStable       = "stable"
	MaturityPreview      = "preview"
	MaturityExperimental = "experimental"

	BillingModeSubscription = "subscription"
	BillingModeAPI          = "api"
	BillingModeNone         = "none"

	QualificationFixtureOnly = "fixture_only"
	QualificationLiveBlocked = "live_blocked"
	QualificationInvalidated = "invalidated"
)

// CapabilityEvidence separates technical proof from discovery/registration labels.
type CapabilityEvidence struct {
	Cancellation    string `json:"cancellation"`
	ChildVisibility string `json:"child_visibility"`
	Enforcement     string `json:"enforcement"`
	Billing         string `json:"billing"`
	SourceKind      string `json:"source_kind"`
	LiveCriterion   string `json:"live_criterion"`
	DetailRef       string `json:"detail_ref,omitempty"`
}

func (e CapabilityEvidence) Validate() error {
	for _, pair := range []struct{ label, v string }{
		{"cancellation", e.Cancellation}, {"child_visibility", e.ChildVisibility},
		{"enforcement", e.Enforcement}, {"billing", e.Billing},
	} {
		switch pair.v {
		case EvidenceVerified, EvidenceUnverified, EvidenceDiscoveryOnly, EvidenceAbsent:
		default:
			return fmt.Errorf("unknown evidence grade for %s", pair.label)
		}
	}
	switch e.SourceKind {
	case EvidenceSourceFixture, EvidenceSourceHelpDiscovery, EvidenceSourceRegistration, EvidenceSourceLiveProbe:
	default:
		return errors.New("unknown evidence source kind")
	}
	switch e.LiveCriterion {
	case LiveCriterionBlocked, LiveCriterionQualified, LiveCriterionNotClaimed:
	default:
		return errors.New("unknown live criterion")
	}
	// Fake/discovery/registration evidence can never claim live qualification.
	if e.SourceKind != EvidenceSourceLiveProbe && e.LiveCriterion == LiveCriterionQualified {
		return errors.New("non-live evidence cannot claim live qualification")
	}
	return nil
}

// BillingPermission is explicit authorized spending — credentials are not allowance.
type BillingPermission struct {
	Mode            string `json:"mode"`
	Authorized      bool   `json:"authorized"`
	AuthorizationID string `json:"authorization_id,omitempty"`
	CredentialPresent bool `json:"credential_present"`
	AllowanceExhausted bool `json:"allowance_exhausted"`
}

func (b BillingPermission) Validate() error {
	switch b.Mode {
	case BillingModeSubscription, BillingModeAPI, BillingModeNone:
	default:
		return errors.New("unknown billing mode")
	}
	if b.Authorized && b.AuthorizationID == "" {
		return errors.New("authorized billing requires authorization identity")
	}
	if !b.Authorized && b.AuthorizationID != "" {
		return errors.New("authorization identity without authorized flag")
	}
	return nil
}

// CapabilityTuple is the exact host qualification identity (not a brand).
type CapabilityTuple struct {
	SchemaVersion         int                 `json:"schema_version"`
	ID                    string              `json:"id"`
	Host                  string              `json:"host"`
	InstalledVersion      string              `json:"installed_version"`
	IntegrationProtocol   string              `json:"integration_protocol_version"`
	Mode                  string              `json:"mode"`
	Method                string              `json:"method"`
	EffectivePermissions  string              `json:"effective_permissions"`
	ExecutionBoundary     string              `json:"execution_boundary"`
	Granularity           string              `json:"granularity"`
	Maturity              string              `json:"maturity"`
	Evidence              CapabilityEvidence  `json:"evidence"`
	PermittedBilling      BillingPermission   `json:"permitted_billing"`
	Qualification         string              `json:"qualification"`
	Digest                string              `json:"digest,omitempty"`
}

func (t CapabilityTuple) Validate() error {
	if t.SchemaVersion != InstrumentSchemaVersion {
		return errors.New("unknown capability schema version")
	}
	if e := validateID("capability", t.ID, true); e != nil {
		return e
	}
	for _, pair := range []struct{ label, v string }{
		{"host", t.Host}, {"installed_version", t.InstalledVersion},
		{"integration_protocol_version", t.IntegrationProtocol},
		{"mode", t.Mode}, {"method", t.Method},
		{"effective_permissions", t.EffectivePermissions},
	} {
		if pair.v == "" || len(pair.v) > 256 {
			return fmt.Errorf("incomplete or oversized %s", pair.label)
		}
		if e := rejectPrivatePayload(pair.label, pair.v); e != nil {
			return e
		}
	}
	switch t.ExecutionBoundary {
	case BoundarySandboxed, BoundaryPrivileged:
	default:
		return errors.New("unknown execution boundary")
	}
	switch t.Granularity {
	case GranularitySession, GranularityTurn, GranularityRequest, GranularityTool, GranularityProcess:
	default:
		return errors.New("unknown control granularity")
	}
	switch t.Maturity {
	case MaturityStable, MaturityPreview, MaturityExperimental:
	default:
		return errors.New("unknown support maturity")
	}
	if e := t.Evidence.Validate(); e != nil {
		return e
	}
	if e := t.PermittedBilling.Validate(); e != nil {
		return e
	}
	switch t.Qualification {
	case QualificationFixtureOnly, QualificationLiveBlocked, QualificationInvalidated:
	default:
		return errors.New("unknown qualification state")
	}
	// Help/registration discovery alone cannot establish execution/hard-cap evidence.
	if t.Evidence.SourceKind == EvidenceSourceHelpDiscovery || t.Evidence.SourceKind == EvidenceSourceRegistration {
		if t.Evidence.Cancellation == EvidenceVerified || t.Evidence.ChildVisibility == EvidenceVerified ||
			t.Evidence.Enforcement == EvidenceVerified {
			return errors.New("discovery/registration cannot establish verified execution evidence")
		}
	}
	return nil
}

// IdentityDigest covers the immutable tuple fields used for drift detection.
func (t CapabilityTuple) IdentityDigest() (string, error) {
	if e := t.Validate(); e != nil {
		return "", e
	}
	payload := struct {
		Host                 string             `json:"host"`
		InstalledVersion     string             `json:"installed_version"`
		IntegrationProtocol  string             `json:"integration_protocol_version"`
		Mode                 string             `json:"mode"`
		Method               string             `json:"method"`
		EffectivePermissions string             `json:"effective_permissions"`
		ExecutionBoundary    string             `json:"execution_boundary"`
		Granularity          string             `json:"granularity"`
		Maturity             string             `json:"maturity"`
		Evidence             CapabilityEvidence `json:"evidence"`
		PermittedBilling     BillingPermission  `json:"permitted_billing"`
	}{
		t.Host, t.InstalledVersion, t.IntegrationProtocol, t.Mode, t.Method,
		t.EffectivePermissions, t.ExecutionBoundary, t.Granularity, t.Maturity,
		t.Evidence, t.PermittedBilling,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return "", e
	}
	return Digest(raw), nil
}

func DecodeCapabilityTuple(raw []byte) (CapabilityTuple, error) {
	var t CapabilityTuple
	if e := StrictJSON(raw, &t); e != nil {
		return t, e
	}
	return t, t.Validate()
}
