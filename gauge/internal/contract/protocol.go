package contract

import (
	"encoding/json"
	"errors"
	"fmt"
)

// Arm kinds for the early comparison instrument.
const (
	ArmNative     = "native"
	ArmOriginalV3 = "original_v3"
	ArmStructural = "structural"
	ArmManaged    = "managed"
)

// PackageGate records prerequisite package availability for arm eligibility.
const (
	PackageV410 = "V4-10"
	PackageV415 = "V4-15"
)

// ProtocolArm is one frozen comparison arm with baseline and environment identity.
type ProtocolArm struct {
	ID                 string            `json:"id"`
	Kind               string            `json:"kind"`
	ControlIdentity    string            `json:"control_identity"`
	BaselineManifest   string            `json:"baseline_manifest_digest"`
	OutcomeDefinition  string            `json:"outcome_definition"`
	AcceptanceDefinition string          `json:"acceptance_definition"`
	ResourceCoverage   []string          `json:"resource_coverage"`
	CPUGuarantee       string            `json:"cpu_guarantee"`
	MemoryGuarantee    string            `json:"memory_guarantee"`
	NetworkGuarantee   string            `json:"network_guarantee"`
	Dependencies       string            `json:"dependencies"`
	CacheState         string            `json:"cache_state"`
	Timeout            string            `json:"timeout"`
	TaskSplit          string            `json:"task_split"`
	TaskStratum        string            `json:"task_stratum"`
	EvaluatorOwner     string            `json:"evaluator_owner"`
	HoldoutOwner       string            `json:"holdout_owner"`
	Exclusions         string            `json:"exclusions"`
	Stratification     string            `json:"stratification,omitempty"`
	Metadata           map[string]string `json:"metadata,omitempty"`
}

func (a ProtocolArm) Validate() error {
	if e := validateID("arm", a.ID, true); e != nil {
		return e
	}
	switch a.Kind {
	case ArmNative, ArmOriginalV3, ArmStructural, ArmManaged:
	default:
		return errors.New("unknown arm kind")
	}
	if a.ControlIdentity == "" {
		return errors.New("arm control identity required")
	}
	switch a.Kind {
	case ArmOriginalV3:
		if a.ControlIdentity != OriginalV3ControlSHA {
			return errors.New("original_v3 arm must pin exact control SHA")
		}
	case ArmNative:
		if a.ControlIdentity != NativeControlIdentity {
			return errors.New("native arm must use untouched native control identity")
		}
	}
	for _, pair := range []struct{ label, v string }{
		{"baseline_manifest_digest", a.BaselineManifest},
		{"outcome_definition", a.OutcomeDefinition},
		{"acceptance_definition", a.AcceptanceDefinition},
		{"cpu_guarantee", a.CPUGuarantee},
		{"memory_guarantee", a.MemoryGuarantee},
		{"network_guarantee", a.NetworkGuarantee},
		{"dependencies", a.Dependencies},
		{"cache_state", a.CacheState},
		{"timeout", a.Timeout},
		{"task_split", a.TaskSplit},
		{"task_stratum", a.TaskStratum},
		{"evaluator_owner", a.EvaluatorOwner},
		{"holdout_owner", a.HoldoutOwner},
		{"exclusions", a.Exclusions},
	} {
		if pair.v == "" {
			return fmt.Errorf("arm %s required", pair.label)
		}
	}
	if len(a.ResourceCoverage) == 0 {
		return errors.New("arm resource coverage required")
	}
	if e := ValidateMetadata(a.Metadata); e != nil {
		return e
	}
	return nil
}

// FrozenProtocol is the immutable comparison protocol (synthetic fixture or live).
type FrozenProtocol struct {
	SchemaVersion        int           `json:"schema_version"`
	ID                   string        `json:"id"`
	ProtocolVersion      string        `json:"protocol_version"`
	Synthetic            bool          `json:"synthetic"`
	Arms                 []ProtocolArm `json:"arms"`
	TaskManifestDigest   string        `json:"task_manifest_digest"`
	ReferencedManifests  []string      `json:"referenced_manifests"`
	Margins              string        `json:"margins"`
	SampleAllocation     string        `json:"sample_allocation"`
	StoppingRules        string        `json:"stopping_rules"`
	StatisticalRules     string        `json:"statistical_rules"`
	BillingMode          string        `json:"billing_mode"`
	AllowanceAuthRef     string        `json:"allowance_authorization_ref"`
	OperatorAuthRef      string        `json:"operator_authorization_ref"`
	CanonicalDigest      string        `json:"canonical_digest,omitempty"`
	CallerTimestamp      string        `json:"caller_timestamp,omitempty"`
	ApprovedFlag         bool          `json:"approved,omitempty"`
}

func (p FrozenProtocol) Validate() error {
	if p.SchemaVersion != InstrumentSchemaVersion {
		return errors.New("unknown protocol schema version")
	}
	if e := validateID("protocol", p.ID, true); e != nil {
		return e
	}
	if p.ProtocolVersion == "" {
		return errors.New("protocol version required")
	}
	if len(p.Arms) == 0 {
		return errors.New("protocol requires at least one arm")
	}
	seen := map[string]bool{}
	for _, arm := range p.Arms {
		if e := arm.Validate(); e != nil {
			return e
		}
		if seen[arm.ID] {
			return errors.New("duplicate arm identity")
		}
		seen[arm.ID] = true
	}
	for _, pair := range []struct{ label, v string }{
		{"task_manifest_digest", p.TaskManifestDigest},
		{"margins", p.Margins},
		{"sample_allocation", p.SampleAllocation},
		{"stopping_rules", p.StoppingRules},
		{"statistical_rules", p.StatisticalRules},
		{"billing_mode", p.BillingMode},
	} {
		if pair.v == "" {
			return fmt.Errorf("%s required", pair.label)
		}
	}
	if len(p.ReferencedManifests) == 0 {
		return errors.New("referenced manifests required for canonical hash")
	}
	// approved:true / nonempty JSON / caller timestamps are insufficient alone.
	_ = p.ApprovedFlag
	_ = p.CallerTimestamp
	return nil
}

// CanonicalHash includes the immutable field set and referenced manifest digests.
func (p FrozenProtocol) CanonicalHash() (string, error) {
	if e := p.Validate(); e != nil {
		return "", e
	}
	payload := struct {
		ProtocolVersion     string        `json:"protocol_version"`
		Synthetic           bool          `json:"synthetic"`
		Arms                []ProtocolArm `json:"arms"`
		TaskManifestDigest  string        `json:"task_manifest_digest"`
		ReferencedManifests []string      `json:"referenced_manifests"`
		Margins             string        `json:"margins"`
		SampleAllocation    string        `json:"sample_allocation"`
		StoppingRules       string        `json:"stopping_rules"`
		StatisticalRules    string        `json:"statistical_rules"`
		BillingMode         string        `json:"billing_mode"`
		AllowanceAuthRef    string        `json:"allowance_authorization_ref"`
		OperatorAuthRef     string        `json:"operator_authorization_ref"`
	}{
		p.ProtocolVersion, p.Synthetic, p.Arms, p.TaskManifestDigest, p.ReferencedManifests,
		p.Margins, p.SampleAllocation, p.StoppingRules, p.StatisticalRules, p.BillingMode,
		p.AllowanceAuthRef, p.OperatorAuthRef,
	}
	raw, e := json.Marshal(payload)
	if e != nil {
		return "", e
	}
	return Digest(raw), nil
}

// EnvironmentComparable reports whether two arms may be pooled without stratification.
func EnvironmentComparable(a, b ProtocolArm) (bool, string) {
	checks := []struct {
		label string
		av, bv string
	}{
		{"cpu", a.CPUGuarantee, b.CPUGuarantee},
		{"memory", a.MemoryGuarantee, b.MemoryGuarantee},
		{"network", a.NetworkGuarantee, b.NetworkGuarantee},
		{"dependencies", a.Dependencies, b.Dependencies},
		{"cache", a.CacheState, b.CacheState},
		{"timeout", a.Timeout, b.Timeout},
		{"task_split", a.TaskSplit, b.TaskSplit},
		{"task_stratum", a.TaskStratum, b.TaskStratum},
		{"outcome", a.OutcomeDefinition, b.OutcomeDefinition},
		{"acceptance", a.AcceptanceDefinition, b.AcceptanceDefinition},
		{"evaluator", a.EvaluatorOwner, b.EvaluatorOwner},
		{"holdout", a.HoldoutOwner, b.HoldoutOwner},
	}
	for _, c := range checks {
		if c.av != c.bv {
			if a.Stratification != "" && a.Stratification == b.Stratification {
				return true, "predeclared_stratification:" + a.Stratification
			}
			return false, "mismatch:" + c.label
		}
	}
	if !sameCoverage(a.ResourceCoverage, b.ResourceCoverage) {
		if a.Stratification != "" && a.Stratification == b.Stratification {
			return true, "predeclared_stratification:" + a.Stratification
		}
		return false, "mismatch:resource_coverage"
	}
	return true, "matched"
}

func sameCoverage(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func DecodeFrozenProtocol(raw []byte) (FrozenProtocol, error) {
	var p FrozenProtocol
	if e := StrictJSON(raw, &p); e != nil {
		return p, e
	}
	return p, p.Validate()
}
