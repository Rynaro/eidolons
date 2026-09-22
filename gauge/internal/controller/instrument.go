package controller

import (
	"errors"
	"strings"
	"sync"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

// TransportCounters prove blocked paths never hit real transport (including API).
type TransportCounters struct {
	mu           sync.Mutex
	AllCalls     int
	APICalls     int
	FixtureCalls int
	AdapterCalls map[string]int
}

func NewTransportCounters() *TransportCounters {
	return &TransportCounters{AdapterCalls: map[string]int{}}
}

func (c *TransportCounters) Inc(adapter string, api bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.AllCalls++
	c.AdapterCalls[adapter]++
	if api {
		c.APICalls++
	} else if adapter == "fixture" {
		c.FixtureCalls++
	}
}

func (c *TransportCounters) Snapshot() (all, api, fixture int, by map[string]int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	by = map[string]int{}
	for k, v := range c.AdapterCalls {
		by[k] = v
	}
	return c.AllCalls, c.APICalls, c.FixtureCalls, by
}

// HostAdapter is the injectable transport boundary — tests use fakes only.
type HostAdapter interface {
	Name() string
	IsAPI() bool
	Dispatch(tupleID string) error
}

// FakeHostAdapter increments counters and never performs network I/O.
type FakeHostAdapter struct {
	AdapterName string
	API         bool
	Counters    *TransportCounters
	Fail        error
}

func (f *FakeHostAdapter) Name() string { return f.AdapterName }
func (f *FakeHostAdapter) IsAPI() bool  { return f.API }
func (f *FakeHostAdapter) Dispatch(tupleID string) error {
	if f.Counters != nil {
		f.Counters.Inc(f.AdapterName, f.API)
	}
	if f.Fail != nil {
		return f.Fail
	}
	if tupleID == "" {
		return errors.New("tuple required")
	}
	return nil
}

func (s *Service) ensureInstrumentStore() (*store.Store, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureObservationNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	if e = db.EnsureInstrumentNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

func (s *Service) EnsureInstrumentNamespaces() error {
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return e
	}
	return db.Close()
}

func (s *Service) nowRFC3339() string {
	return s.opts.Clock().UTC().Format(time.RFC3339)
}

// CatalogueCapability records a host/version/mode/method/... tuple.
func (s *Service) CatalogueCapability(t contract.CapabilityTuple) (contract.CapabilityTuple, error) {
	digest, e := t.IdentityDigest()
	if e != nil {
		return t, e
	}
	t.Digest = digest
	// Live criterion stays blocked without protected live probe + authorization.
	if t.Evidence.SourceKind != contract.EvidenceSourceLiveProbe {
		t.Evidence.LiveCriterion = contract.LiveCriterionBlocked
		if t.Qualification == "" {
			t.Qualification = contract.QualificationFixtureOnly
		}
		if t.Qualification == contract.QualificationLiveBlocked || t.Evidence.LiveCriterion == contract.LiveCriterionQualified {
			t.Qualification = contract.QualificationLiveBlocked
		}
	}
	if t.Qualification == "" {
		t.Qualification = contract.QualificationLiveBlocked
	}
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return t, e
	}
	defer db.Close()
	if _, e = db.PutCapability(t, s.nowRFC3339()); e != nil {
		return t, e
	}
	return db.GetCapability(t.ID)
}

// Preflight evaluates required capabilities and authorized billing; fail-closed for live.
func (s *Service) Preflight(req contract.PreflightRequest, counters *TransportCounters) (contract.PreflightResult, error) {
	var result contract.PreflightResult
	result.LiveCriterion = contract.LiveCriterionBlocked
	result.Scope = contract.PreflightScopeFixture
	if req.LiveAdmission {
		result.Scope = contract.PreflightScopeLive
	}
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return result, e
	}
	defer db.Close()
	t, e := db.GetCapability(req.TupleID)
	if e != nil {
		result.RejectReasons = append(result.RejectReasons, "unknown_tuple")
		return result, nil
	}
	if t.Qualification == contract.QualificationInvalidated {
		result.RejectReasons = append(result.RejectReasons, "tuple_invalidated")
		return result, nil
	}
	required := req.RequiredCapabilities
	if len(required) == 0 {
		required = []string{"cancellation", "child_visibility", "enforcement", "billing"}
	}
	for _, cap := range required {
		grade := ""
		switch cap {
		case "cancellation":
			grade = t.Evidence.Cancellation
		case "child_visibility":
			grade = t.Evidence.ChildVisibility
		case "enforcement":
			grade = t.Evidence.Enforcement
		case "billing":
			grade = t.Evidence.Billing
		default:
			result.RejectReasons = append(result.RejectReasons, "unknown_required:"+cap)
			continue
		}
		if grade != contract.EvidenceVerified {
			result.RejectReasons = append(result.RejectReasons, "unverified:"+cap)
		}
	}
	billingMode := req.RequiredBillingMode
	if billingMode == "" {
		billingMode = t.PermittedBilling.Mode
	}
	if !t.PermittedBilling.Authorized || t.PermittedBilling.Mode != billingMode {
		result.RejectReasons = append(result.RejectReasons, "billing_not_authorized")
	}
	// Credential presence is never allowance; exhausted subscription never switches to API.
	if t.PermittedBilling.AllowanceExhausted && billingMode == contract.BillingModeSubscription {
		result.RejectReasons = append(result.RejectReasons, "subscription_exhausted")
		if req.AuthorizeAPIFallback || t.PermittedBilling.CredentialPresent {
			result.RejectReasons = append(result.RejectReasons, "api_fallback_refused")
		}
	}
	if req.LiveAdmission {
		result.RejectReasons = append(result.RejectReasons, "live_admission_blocked")
		if t.Evidence.LiveCriterion != contract.LiveCriterionQualified {
			result.RejectReasons = append(result.RejectReasons, "live_criterion_blocked")
		}
		if t.Evidence.SourceKind != contract.EvidenceSourceLiveProbe {
			result.RejectReasons = append(result.RejectReasons, "no_authorized_live_probe")
		}
	}
	if len(result.RejectReasons) > 0 {
		result.Admitted = false
		result.TransportAllowed = false
		result.APITransportAllowed = false
		return result, nil
	}
	// Fixture admission only when evidence is fixture-sourced and billing authorized.
	if t.Evidence.SourceKind != contract.EvidenceSourceFixture {
		result.RejectReasons = append(result.RejectReasons, "non_fixture_source")
		return result, nil
	}
	result.Admitted = true
	result.TransportAllowed = true
	result.APITransportAllowed = billingMode == contract.BillingModeAPI && t.PermittedBilling.Authorized
	result.LiveCriterion = t.Evidence.LiveCriterion
	_ = counters
	return result, nil
}

// DispatchFixture runs a fake adapter only after successful fixture preflight.
func (s *Service) DispatchFixture(req contract.PreflightRequest, adapter HostAdapter, counters *TransportCounters) (contract.PreflightResult, error) {
	result, e := s.Preflight(req, counters)
	if e != nil {
		return result, e
	}
	if !result.Admitted || !result.TransportAllowed {
		return result, errors.New("preflight rejected; transport not invoked")
	}
	if adapter == nil {
		return result, errors.New("adapter required")
	}
	if adapter.IsAPI() && !result.APITransportAllowed {
		return result, errors.New("API transport not allowed")
	}
	if e = adapter.Dispatch(req.TupleID); e != nil {
		return result, e
	}
	return result, nil
}

// FreezeProtocol persists an immutable protocol before any outcome/dispatch admission.
func (s *Service) FreezeProtocol(p contract.FrozenProtocol) (contract.FrozenProtocol, contract.OrderingEvent, error) {
	var ev contract.OrderingEvent
	digest, e := p.CanonicalHash()
	if e != nil {
		return p, ev, e
	}
	p.CanonicalDigest = digest
	// Caller timestamps / approved:true are insufficient; store ordering is authoritative.
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return p, ev, e
	}
	defer db.Close()
	ev, e = db.FreezeProtocol(p, s.nowRFC3339())
	if e != nil {
		return p, ev, e
	}
	out, e := db.GetProtocol(p.ID)
	return out, ev, e
}

// AdmitDispatch records dispatch only after a matching freeze exists in controller order.
func (s *Service) AdmitDispatch(protocolID, digest string) (contract.OrderingEvent, error) {
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return contract.OrderingEvent{}, e
	}
	defer db.Close()
	return db.RecordDispatch(protocolID, digest, s.nowRFC3339())
}

// RecordAttempt stores a shared native/v3 attempt under a frozen protocol.
func (s *Service) RecordAttempt(r contract.AttemptRecord) (contract.OrderingEvent, error) {
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return contract.OrderingEvent{}, e
	}
	defer db.Close()
	return db.PutAttempt(r, s.nowRFC3339())
}

// RecordEligibility stores an eligibility decision with zero fabricated attempts.
func (s *Service) RecordEligibility(el contract.ArmEligibility) error {
	el.FabricatedAttempts = 0
	if el.RecordedAt == "" {
		el.RecordedAt = s.nowRFC3339()
	}
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return e
	}
	defer db.Close()
	return db.PutEligibility(el)
}

// EvaluateArmEligibility marks structural/managed arms pending when packages absent.
func (s *Service) EvaluateArmEligibility(trialID, protocolID string, arm contract.ProtocolArm, availablePackages map[string]bool) (contract.ArmEligibility, error) {
	el := contract.ArmEligibility{
		SchemaVersion: contract.InstrumentSchemaVersion,
		ID:            "elig-" + arm.ID,
		TrialID:       trialID,
		ProtocolID:    protocolID,
		ArmID:         arm.ID,
		ArmKind:       arm.Kind,
		FabricatedAttempts: 0,
		RecordedAt:    s.nowRFC3339(),
	}
	switch arm.Kind {
	case contract.ArmStructural:
		if !availablePackages[contract.PackageV410] {
			el.Status = contract.EligibilityIneligible
			el.Reason = "structural arm requires V4-10"
			el.MissingPackage = contract.PackageV410
			return el, s.RecordEligibility(el)
		}
	case contract.ArmManaged:
		if !availablePackages[contract.PackageV415] {
			el.Status = contract.EligibilityIneligible
			el.Reason = "managed arm requires V4-15"
			el.MissingPackage = contract.PackageV415
			return el, s.RecordEligibility(el)
		}
	case contract.ArmNative, contract.ArmOriginalV3:
		if arm.Kind == contract.ArmOriginalV3 && arm.ControlIdentity != contract.OriginalV3ControlSHA {
			el.Status = contract.EligibilityIneligible
			el.Reason = "original_v3 control identity mismatch"
			return el, s.RecordEligibility(el)
		}
		if arm.Kind == contract.ArmNative && arm.ControlIdentity != contract.NativeControlIdentity {
			el.Status = contract.EligibilityIneligible
			el.Reason = "native control identity mismatch"
			return el, s.RecordEligibility(el)
		}
		el.Status = contract.EligibilityEligible
		el.Reason = "fixture_authorized_control"
		return el, s.RecordEligibility(el)
	default:
		return el, errors.New("unknown arm kind")
	}
	el.Status = contract.EligibilityEligible
	el.Reason = "package_present"
	return el, s.RecordEligibility(el)
}

// ShadowObserve records observer artifacts without mutating the execution request.
func (s *Service) ShadowObserve(enabled bool, req contract.ExecutionRequest, observe func(contract.ExecutionRequest) (contract.ShadowObservation, error)) (contract.ExecutionRequest, contract.ShadowObservation, error) {
	var empty contract.ShadowObservation
	if e := req.Validate(); e != nil {
		return req, empty, e
	}
	raw, e := req.CanonicalBytes()
	if e != nil {
		return req, empty, e
	}
	digest := contract.Digest(raw)
	outReq := req // byte-identical decisions; only observation artifacts may differ
	if !enabled {
		obs := contract.ShadowObservation{
			SchemaVersion: contract.InstrumentSchemaVersion,
			ID:            "shadow-off-" + digest[:16],
			Enabled:       false,
			RequestDigest: digest,
			RecordedAt:    s.nowRFC3339(),
		}
		return outReq, obs, nil
	}
	if observe == nil {
		obs := contract.ShadowObservation{
			SchemaVersion: contract.InstrumentSchemaVersion,
			ID:            "shadow-on-" + digest[:16],
			Enabled:       true,
			RequestDigest: digest,
			ArtifactRef:   "shadow-artifact",
			RecordedAt:    s.nowRFC3339(),
		}
		db, e := s.ensureInstrumentStore()
		if e != nil {
			return outReq, obs, e
		}
		defer db.Close()
		if e = db.PutShadow(obs); e != nil {
			return outReq, obs, e
		}
		return outReq, obs, nil
	}
	obs, e := observe(req)
	if e != nil {
		// Observer failure cannot reroute or change billing.
		failObs := contract.ShadowObservation{
			SchemaVersion: contract.InstrumentSchemaVersion,
			ID:            "shadow-err-" + digest[:16],
			Enabled:       true,
			RequestDigest: digest,
			ObserverError: e.Error(),
			RecordedAt:    s.nowRFC3339(),
		}
		db, err := s.ensureInstrumentStore()
		if err != nil {
			return outReq, failObs, nil
		}
		defer db.Close()
		_ = db.PutShadow(failObs)
		return outReq, failObs, nil
	}
	obs.Enabled = true
	obs.RequestDigest = digest
	if obs.RecordedAt == "" {
		obs.RecordedAt = s.nowRFC3339()
	}
	if obs.SchemaVersion == 0 {
		obs.SchemaVersion = contract.InstrumentSchemaVersion
	}
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return outReq, obs, e
	}
	defer db.Close()
	if e = db.PutShadow(obs); e != nil {
		return outReq, obs, e
	}
	return outReq, obs, nil
}

// DriftCapability invalidates an affected tuple when identity fields change.
func (s *Service) DriftCapability(oldID string, updated contract.CapabilityTuple) error {
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return e
	}
	defer db.Close()
	existing, e := db.GetCapability(oldID)
	if e != nil {
		return e
	}
	oldDigest, e := existing.IdentityDigest()
	if e != nil {
		return e
	}
	updated.ID = oldID
	newDigest, e := updated.IdentityDigest()
	if e != nil {
		return e
	}
	if oldDigest == newDigest {
		return nil
	}
	return db.InvalidateCapability(oldID, s.nowRFC3339())
}

// InstrumentReport summarizes attempts and eligibility for a protocol.
type InstrumentReport struct {
	ProtocolID   string                      `json:"protocol_id"`
	Digest       string                      `json:"protocol_digest"`
	Synthetic    bool                        `json:"synthetic"`
	LiveBlocked  bool                        `json:"live_blocked"`
	Attempts     []contract.AttemptRecord    `json:"attempts"`
	Eligibility  []contract.ArmEligibility   `json:"eligibility"`
	Summary      contract.AttemptSummary     `json:"summary,omitempty"`
	Ordering     []contract.OrderingEvent    `json:"ordering"`
	Comparability map[string]string          `json:"comparability,omitempty"`
}

func (s *Service) InstrumentReport(protocolID string) (InstrumentReport, error) {
	var report InstrumentReport
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return report, e
	}
	defer db.Close()
	proto, e := db.GetProtocol(protocolID)
	if e != nil {
		return report, e
	}
	attempts, e := db.ListAttempts(protocolID, "")
	if e != nil {
		return report, e
	}
	elig, e := db.ListEligibility(protocolID)
	if e != nil {
		return report, e
	}
	ordering, e := db.ListOrdering()
	if e != nil {
		return report, e
	}
	report = InstrumentReport{
		ProtocolID:  protocolID,
		Digest:      proto.CanonicalDigest,
		Synthetic:   proto.Synthetic,
		LiveBlocked: true, // live qualification intentionally blocked in V4-09 fixture scope
		Attempts:    attempts,
		Eligibility: elig,
		Ordering:    ordering,
		Comparability: map[string]string{},
	}
	if len(attempts) > 0 {
		sum, e := contract.SummarizeAttempts(attempts)
		if e == nil {
			report.Summary = sum
		}
	}
	for i := 0; i < len(proto.Arms); i++ {
		for j := i + 1; j < len(proto.Arms); j++ {
			ok, reason := contract.EnvironmentComparable(proto.Arms[i], proto.Arms[j])
			key := proto.Arms[i].ID + ":" + proto.Arms[j].ID
			if ok {
				report.Comparability[key] = reason
			} else {
				report.Comparability[key] = reason
			}
		}
	}
	return report, nil
}

// LiveStatus reports the live criterion for a catalogue entry without promoting it.
func (s *Service) LiveStatus(tupleID string) (string, []string, error) {
	db, e := s.ensureInstrumentStore()
	if e != nil {
		return "", nil, e
	}
	defer db.Close()
	t, e := db.GetCapability(tupleID)
	if e != nil {
		return "", nil, e
	}
	missing := []string{}
	if t.Evidence.SourceKind != contract.EvidenceSourceLiveProbe {
		missing = append(missing, "authorized_live_probe")
	}
	if t.Evidence.LiveCriterion != contract.LiveCriterionQualified {
		missing = append(missing, "live_criterion")
	}
	if !t.PermittedBilling.Authorized {
		missing = append(missing, "billing_authorization")
	}
	status := t.Evidence.LiveCriterion
	if status == "" {
		status = contract.LiveCriterionBlocked
	}
	if len(missing) > 0 {
		status = contract.LiveCriterionBlocked
	}
	return status, missing, nil
}

func siblingMethodDistinct(a, b contract.CapabilityTuple) bool {
	return a.Method != b.Method || a.ExecutionBoundary != b.ExecutionBoundary ||
		a.EffectivePermissions != b.EffectivePermissions
}

// AssertSiblingIsolation documents that qualifying one method never grants a sibling.
func AssertSiblingIsolation(qualified, sibling contract.CapabilityTuple) error {
	if !siblingMethodDistinct(qualified, sibling) {
		return errors.New("sibling must differ in method/boundary/permissions")
	}
	if sibling.Qualification == contract.QualificationInvalidated {
		return nil
	}
	if qualified.Qualification == contract.QualificationFixtureOnly &&
		sibling.Evidence.Cancellation != contract.EvidenceVerified {
		return nil
	}
	if strings.Contains(sibling.Method, qualified.Method) && sibling.Evidence.Enforcement == contract.EvidenceVerified &&
		qualified.ExecutionBoundary == contract.BoundarySandboxed && sibling.ExecutionBoundary == contract.BoundaryPrivileged {
		return errors.New("sandboxed qualification must not verify privileged sibling")
	}
	return nil
}
