package controller

import (
	"errors"
	"sync"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
)

// NativeMethodCounters prove no native send precedes durable intent and cover every method.
type NativeMethodCounters struct {
	mu sync.Mutex
	Preflight      int
	Start          int
	Resume         int
	Events         int
	Interrupt      int
	Lookup         int
	Cleanup        int
	Reconstruction int
}

func NewNativeMethodCounters() *NativeMethodCounters {
	return &NativeMethodCounters{}
}

func (c *NativeMethodCounters) Snapshot() NativeMethodCounters {
	c.mu.Lock()
	defer c.mu.Unlock()
	return NativeMethodCounters{
		Preflight: c.Preflight, Start: c.Start, Resume: c.Resume, Events: c.Events,
		Interrupt: c.Interrupt, Lookup: c.Lookup, Cleanup: c.Cleanup, Reconstruction: c.Reconstruction,
	}
}

func (c *NativeMethodCounters) inc(field *int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	*field++
}

// NativeAdapter wraps preflight/start/resume/events/interrupt/lookup/cleanup without
// replacing the native model/tool loop. Richer than HostAdapter (kept for V4-09).
type NativeAdapter interface {
	Name() string
	QualifiedCapability() contract.CapabilityTuple
	EnforcedGranularity() string
	SupportsLookup() bool
	SupportsIdempotencyKey() bool
	SupportsReconstruction() bool
	Preflight(req NativePreflightRequest) (NativePreflightResult, error)
	Start(req NativeStartRequest) (NativeStartResult, error)
	Resume(req NativeResumeRequest) (NativeResumeResult, error)
	Events(req NativeEventsRequest) ([]contract.NativeEvent, error)
	Interrupt(req NativeInterruptRequest) (NativeInterruptResult, error)
	Lookup(operationID string) (NativeLookupResult, error)
	Cleanup(req NativeCleanupRequest) (NativeCleanupResult, error)
	Reconstruct(req NativeReconstructRequest) (contract.ReconstructionReport, error)
}

// Request / result types for the native adapter surface.

type NativePreflightRequest struct {
	Method               string
	RequestedGranularity string
	TupleID              string
	HostVersion          string
}

type NativePreflightResult struct {
	Allowed       bool
	RejectReasons []string
}

type NativeStartRequest struct {
	OperationID      string
	IdempotencyKey   string
	IntentID         string
	Method           string
	Requested        contract.RequestedSettings
	OwnershipSession string
	OwnershipProcess string
	OwnershipWorktree string
}

type NativeStartResult struct {
	NativeSessionID string
	NativeRunID     string
	TransportState  string
	EffectApplied   bool // remote effect occurred (even if ack later lost)
	Observed        contract.ObservedSettings
}

type NativeResumeRequest struct {
	OperationID string
	IntentID    string
}

type NativeResumeResult struct {
	TransportState string
	Found          bool
}

type NativeEventsRequest struct {
	IntentID    string
	OperationID string
}

type NativeInterruptRequest struct {
	IntentID         string
	OperationID      string
	OwnershipSession string
	OwnershipProcess string
}

type NativeInterruptResult struct {
	Accepted     bool
	ProcessAlive bool
	AckMissing   bool
	UsageDelayed bool
}

type NativeLookupResult struct {
	Found           bool
	Supported       bool
	NativeSessionID string
	NativeRunID     string
	TransportState  string
	EffectApplied   bool
}

type NativeCleanupRequest struct {
	OwnershipSession  string
	OwnershipProcess  string
	OwnershipWorktree string
	// Adjacent resources that MUST be preserved.
	AdjacentSessions  []string
	AdjacentProcesses []string
	AdjacentWorktrees []string
}

type NativeCleanupResult struct {
	CleanedSessions  []string
	CleanedProcesses []string
	CleanedWorktrees []string
	PreservedSessions  []string
	PreservedProcesses []string
	PreservedWorktrees []string
	PermissionBoundary string
	NetworkBoundary    string
}

type NativeReconstructRequest struct {
	LostNativeSession    bool
	PortableCheckpointID string
	OriginalInvocationID string
}

// FakeNativeAdapter is the single fixture-qualified host for V4-12. Zero real network.
type FakeNativeAdapter struct {
	Counters *NativeMethodCounters

	LookupEnabled          bool
	IdempotencyKeyEnabled  bool
	ReconstructionEnabled  bool
	EnforcedGranularityVal string
	Version                string
	QualifiedMethods       map[string]bool

	// Owned resource registry for cleanup isolation.
	mu            sync.Mutex
	ownedSessions map[string]bool
	ownedProcs    map[string]bool
	ownedTrees    map[string]bool
	effectsByOp   map[string]NativeStartResult
	startFail     error
	interruptFail error
	liveProcess   bool
}

// NewFakeNativeAdapter constructs the one qualified fixture host/version/mode.
func NewFakeNativeAdapter(counters *NativeMethodCounters) *FakeNativeAdapter {
	if counters == nil {
		counters = NewNativeMethodCounters()
	}
	return &FakeNativeAdapter{
		Counters:               counters,
		LookupEnabled:          true,
		IdempotencyKeyEnabled:  true,
		ReconstructionEnabled:  true,
		EnforcedGranularityVal: contract.GranularityRequest,
		Version:                contract.QualifiedDispatchVersion,
		QualifiedMethods: map[string]bool{
			contract.QualifiedDispatchMethod: true,
		},
		ownedSessions: map[string]bool{},
		ownedProcs:    map[string]bool{},
		ownedTrees:    map[string]bool{},
		effectsByOp:   map[string]NativeStartResult{},
		liveProcess:   true,
	}
}

func (f *FakeNativeAdapter) Name() string { return "fake-native-v412" }

func (f *FakeNativeAdapter) QualifiedCapability() contract.CapabilityTuple {
	return contract.CapabilityTuple{
		SchemaVersion: contract.InstrumentSchemaVersion, ID: contract.QualifiedDispatchTupleID,
		Host: contract.QualifiedDispatchHost, InstalledVersion: f.Version,
		IntegrationProtocol: "exec-jsonl@1", Mode: contract.QualifiedDispatchMode,
		Method: contract.QualifiedDispatchMethod, EffectivePermissions: "read-only",
		ExecutionBoundary: contract.BoundarySandboxed, Granularity: f.EnforcedGranularityVal,
		Maturity: contract.MaturityStable,
		Evidence: contract.CapabilityEvidence{
			Cancellation: contract.EvidenceVerified, ChildVisibility: contract.EvidenceVerified,
			Enforcement: contract.EvidenceVerified, Billing: contract.EvidenceVerified,
			SourceKind: contract.EvidenceSourceFixture, LiveCriterion: contract.LiveCriterionBlocked,
		},
		PermittedBilling: contract.BillingPermission{
			Mode: contract.BillingModeSubscription, Authorized: true,
			AuthorizationID: contract.QualifiedDispatchBilling,
			CredentialPresent: true, AllowanceExhausted: false,
		},
		Qualification: contract.QualificationFixtureOnly,
	}
}

func (f *FakeNativeAdapter) EnforcedGranularity() string { return f.EnforcedGranularityVal }
func (f *FakeNativeAdapter) SupportsLookup() bool        { return f.LookupEnabled }
func (f *FakeNativeAdapter) SupportsIdempotencyKey() bool {
	return f.IdempotencyKeyEnabled
}
func (f *FakeNativeAdapter) SupportsReconstruction() bool { return f.ReconstructionEnabled }

func (f *FakeNativeAdapter) Preflight(req NativePreflightRequest) (NativePreflightResult, error) {
	f.Counters.inc(&f.Counters.Preflight)
	var r NativePreflightResult
	if f.Version != contract.QualifiedDispatchVersion {
		r.RejectReasons = append(r.RejectReasons, "version_drift")
	}
	if !f.QualifiedMethods[req.Method] {
		r.RejectReasons = append(r.RejectReasons, "method_outside_qualified_set:"+req.Method)
	}
	// Cannot enforce required control at requested granularity → reject (R06).
	if req.RequestedGranularity != "" && req.RequestedGranularity != f.EnforcedGranularityVal {
		// Turn-only adapter cannot satisfy request-level limits without a different operator request.
		r.RejectReasons = append(r.RejectReasons, "granularity_unsupported:"+req.RequestedGranularity+
			":enforced="+f.EnforcedGranularityVal)
	}
	if len(r.RejectReasons) > 0 {
		r.Allowed = false
		return r, nil
	}
	r.Allowed = true
	return r, nil
}

func (f *FakeNativeAdapter) Start(req NativeStartRequest) (NativeStartResult, error) {
	f.Counters.inc(&f.Counters.Start)
	if f.startFail != nil {
		return NativeStartResult{}, f.startFail
	}
	if !f.QualifiedMethods[req.Method] {
		return NativeStartResult{}, errors.New("method_outside_qualified_set")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	// Idempotent reuse of original operation identity (R07).
	if prev, ok := f.effectsByOp[req.OperationID]; ok {
		return prev, nil
	}
	if f.IdempotencyKeyEnabled && req.IdempotencyKey != "" {
		for _, prev := range f.effectsByOp {
			if prev.NativeRunID == "run-"+req.IdempotencyKey {
				return prev, nil
			}
		}
	}
	observed := contract.ObservedSettings{
		// Host may ignore requested model/effort — recorded separately (R03).
		Model:  "fixture-observed-model",
		Effort: "fixture-observed-effort",
		Method: req.Method,
	}
	res := NativeStartResult{
		NativeSessionID: "ns-" + req.OwnershipSession,
		NativeRunID:     "run-" + req.OperationID,
		TransportState:  contract.OutcomeRunning,
		EffectApplied:   true,
		Observed:        observed,
	}
	if f.IdempotencyKeyEnabled && req.IdempotencyKey != "" {
		res.NativeRunID = "run-" + req.IdempotencyKey
	}
	f.effectsByOp[req.OperationID] = res
	f.ownedSessions[req.OwnershipSession] = true
	f.ownedProcs[req.OwnershipProcess] = true
	f.ownedTrees[req.OwnershipWorktree] = true
	f.liveProcess = true
	return res, nil
}

func (f *FakeNativeAdapter) Resume(req NativeResumeRequest) (NativeResumeResult, error) {
	f.Counters.inc(&f.Counters.Resume)
	f.mu.Lock()
	defer f.mu.Unlock()
	prev, ok := f.effectsByOp[req.OperationID]
	if !ok {
		return NativeResumeResult{Found: false, TransportState: contract.OutcomeUnknown}, nil
	}
	return NativeResumeResult{Found: true, TransportState: prev.TransportState}, nil
}

func (f *FakeNativeAdapter) Events(req NativeEventsRequest) ([]contract.NativeEvent, error) {
	f.Counters.inc(&f.Counters.Events)
	_ = req
	return nil, nil // controller synthesizes recorded events; adapter may stream later
}

func (f *FakeNativeAdapter) Interrupt(req NativeInterruptRequest) (NativeInterruptResult, error) {
	f.Counters.inc(&f.Counters.Interrupt)
	if f.interruptFail != nil {
		return NativeInterruptResult{}, f.interruptFail
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	alive := f.liveProcess
	return NativeInterruptResult{
		Accepted:     true,
		ProcessAlive: alive,
		AckMissing:   false,
		UsageDelayed: true, // delayed usage is a common nonterminal case
	}, nil
}

func (f *FakeNativeAdapter) Lookup(operationID string) (NativeLookupResult, error) {
	f.Counters.inc(&f.Counters.Lookup)
	if !f.LookupEnabled {
		return NativeLookupResult{Supported: false, Found: false}, nil
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	prev, ok := f.effectsByOp[operationID]
	if !ok {
		return NativeLookupResult{Supported: true, Found: false}, nil
	}
	return NativeLookupResult{
		Supported: true, Found: true,
		NativeSessionID: prev.NativeSessionID, NativeRunID: prev.NativeRunID,
		TransportState: prev.TransportState, EffectApplied: prev.EffectApplied,
	}, nil
}

func (f *FakeNativeAdapter) Cleanup(req NativeCleanupRequest) (NativeCleanupResult, error) {
	f.Counters.inc(&f.Counters.Cleanup)
	f.mu.Lock()
	defer f.mu.Unlock()
	res := NativeCleanupResult{
		PermissionBoundary: "ownership-id-only",
		NetworkBoundary:    "none-local-fixture",
	}
	if f.ownedSessions[req.OwnershipSession] {
		res.CleanedSessions = append(res.CleanedSessions, req.OwnershipSession)
		delete(f.ownedSessions, req.OwnershipSession)
	}
	if f.ownedProcs[req.OwnershipProcess] {
		res.CleanedProcesses = append(res.CleanedProcesses, req.OwnershipProcess)
		delete(f.ownedProcs, req.OwnershipProcess)
	}
	if f.ownedTrees[req.OwnershipWorktree] {
		res.CleanedWorktrees = append(res.CleanedWorktrees, req.OwnershipWorktree)
		delete(f.ownedTrees, req.OwnershipWorktree)
	}
	for _, s := range req.AdjacentSessions {
		if f.ownedSessions[s] {
			return res, errors.New("refusing to clean adjacent owned-looking session without match")
		}
		res.PreservedSessions = append(res.PreservedSessions, s)
	}
	for _, p := range req.AdjacentProcesses {
		if f.ownedProcs[p] {
			return res, errors.New("refusing to clean adjacent process")
		}
		res.PreservedProcesses = append(res.PreservedProcesses, p)
	}
	for _, w := range req.AdjacentWorktrees {
		if f.ownedTrees[w] {
			return res, errors.New("refusing to clean adjacent worktree")
		}
		res.PreservedWorktrees = append(res.PreservedWorktrees, w)
	}
	f.liveProcess = false
	return res, nil
}

func (f *FakeNativeAdapter) Reconstruct(req NativeReconstructRequest) (contract.ReconstructionReport, error) {
	f.Counters.inc(&f.Counters.Reconstruction)
	if !f.ReconstructionEnabled {
		return contract.ReconstructionReport{
			Kind:                   contract.ReconstructionBlocked,
			NativeSessionPresent:   !req.LostNativeSession,
			PortableCheckpointOK:   req.PortableCheckpointID != "",
			ClaimsNativeContinuity: false,
			Detail:                 "reconstruction_support_missing",
		}, nil
	}
	if req.LostNativeSession && req.PortableCheckpointID != "" {
		return contract.ReconstructionReport{
			Kind:                      contract.ReconstructionPortable,
			NativeSessionPresent:      false,
			PortableCheckpointOK:      true,
			ReconstructedInvocationID: "recon-" + req.PortableCheckpointID,
			ClaimsNativeContinuity:    false,
			Detail:                    "portable_checkpoint_reconstructed",
		}, nil
	}
	if req.LostNativeSession {
		return contract.ReconstructionReport{
			Kind:                   contract.ReconstructionNativeUnavailable,
			NativeSessionPresent:   false,
			PortableCheckpointOK:   false,
			ClaimsNativeContinuity: false,
			Detail:                 "native_session_history_unavailable",
		}, nil
	}
	return contract.ReconstructionReport{
		Kind:                   contract.ReconstructionNone,
		NativeSessionPresent:   true,
		ClaimsNativeContinuity: false,
	}, nil
}

// SetLiveProcess controls whether interrupt sees a live process (tests).
func (f *FakeNativeAdapter) SetLiveProcess(alive bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.liveProcess = alive
}

// SetStartFail injects a start failure after counters increment.
func (f *FakeNativeAdapter) SetStartFail(err error) { f.startFail = err }

// EffectCount returns how many distinct remote effects were applied (idempotency check).
func (f *FakeNativeAdapter) EffectCount() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.effectsByOp)
}
