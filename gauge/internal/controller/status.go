package controller

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureStatusStore() (*store.Store, error) {
	db, e := s.ensureDeliveryStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureStatusNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureStatusNamespaces adds typed status-projection buckets under schema 2.
func (s *Service) EnsureStatusNamespaces() error {
	db, e := s.ensureStatusStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// StatusProjectOptions controls how delivery/verification/participation are projected.
type StatusProjectOptions struct {
	LoopID            string
	RootID            string
	ChecksPassed      bool
	ReviewPending     bool
	Released          bool
	Assignments       []contract.Assignment
	Quota             *contract.QuotaLimitation
	CancelState       *contract.CancelState
	AttemptEscalation string
	Counters          *ObservationalCounters
}

// ProjectStatus builds an observational status view from canonical observations (R01–R07).
// It does not replace delivery.go; it projects InspectSnapshot + separate delivery/verification states.
func (s *Service) ProjectStatus(opts StatusProjectOptions) (contract.StatusProjection, error) {
	counters := opts.Counters
	if counters == nil {
		counters = &ObservationalCounters{}
	}

	proj := contract.StatusProjection{
		SchemaVersion:     contract.StatusSchemaVersion,
		ContractVersion:   contract.StatusContractID,
		LoopID:            opts.LoopID,
		RootID:            opts.RootID,
		GreenBadgeMeans:   "not_acceptance",
		ObservationalOnly: true,
		Slice:             "core-cli",
		OptionalGAMBIT:    "explicitly_deferred",
		Participation: contract.ParticipationView{
			SchemaVersion: contract.StatusSchemaVersion,
			ObservedOnly:  true,
			FictionalTeam: false,
			Pattern:       contract.ParticipationOneMakerManyMethods,
		},
	}
	if opts.AttemptEscalation != "" {
		proj.DeniedEscalation = true
	}

	var loop contract.DeliveryLoop
	loopID := opts.LoopID

	// Inspect closes its own store handle before we open status namespaces —
	// never hold two bbolt writers on the same controller DB.
	if loopID != "" {
		snap, e := s.InspectDelivery(loopID, counters)
		if e != nil {
			return proj, e
		}
		proj.Inspect = &snap
		if snap.RootID != "" {
			proj.RootID = snap.RootID
		}
		if snap.Status == contract.PhaseUnknown {
			proj.DeliveryState = contract.DeliveryStateUnknown
			proj.VerificationState = contract.VerificationStateNone
		}
	} else if opts.RootID != "" {
		loops, e := s.DeliveryStatus(opts.RootID)
		if e != nil {
			return proj, e
		}
		if len(loops) == 0 {
			proj.DeliveryState = contract.DeliveryStateUnknown
			proj.VerificationState = contract.VerificationStateNone
		} else {
			loop = loops[0]
			loopID = loop.ID
			proj.LoopID = loop.ID
			snap, e := s.InspectDelivery(loop.ID, counters)
			if e != nil {
				return proj, e
			}
			proj.Inspect = &snap
		}
	} else {
		return proj, errors.New("status project requires --loop or --root")
	}

	db, e := s.ensureStatusStore()
	if e != nil {
		return proj, e
	}
	defer db.Close()
	counters.FilesystemReads.Add(1)

	if loopID != "" && proj.DeliveryState == "" {
		loaded, ge := db.GetDeliveryLoop(loopID)
		if ge != nil {
			proj.DeliveryState = contract.DeliveryStateUnknown
			proj.VerificationState = contract.VerificationStateNone
		} else {
			loop = loaded
			proj.DeliveryState = contract.ProjectDeliveryState(loop)
			proj.VerificationState = contract.ProjectVerificationState(loop, opts.ChecksPassed, opts.ReviewPending, opts.Released)
			proj.Accepted = loop.Accepted
			if loop.Accepted {
				proj.TerminalBadge = "green_observable"
			}
		}
	} else if loop.ID != "" && proj.DeliveryState == "" {
		proj.DeliveryState = contract.ProjectDeliveryState(loop)
		proj.VerificationState = contract.ProjectVerificationState(loop, opts.ChecksPassed, opts.ReviewPending, opts.Released)
		proj.Accepted = loop.Accepted
	}

	if len(opts.Assignments) > 0 {
		proj.Participation = contract.ProjectParticipation(opts.Assignments)
	}

	if opts.Quota != nil {
		if e := opts.Quota.Validate(); e != nil {
			return proj, e
		}
		q := *opts.Quota
		proj.QuotaLimitation = &q
	}

	if opts.CancelState != nil {
		c := contract.ProjectCancellationFromDispatch(*opts.CancelState)
		proj.Cancellation = &c
	} else if loop.ID != "" && (loop.Status == contract.PhaseCancellationPending || loop.Phase == contract.PhaseCancellationPending) {
		c := contract.CancellationProjection{
			SchemaVersion:       contract.StatusSchemaVersion,
			Stage:               contract.CancelStageRequestAcknowledged,
			RequestAcknowledged: true,
			ProcessAlive:        true,
			LateUsage:           true,
			SourceCancelState:   contract.CancelInterruptAccepted,
		}
		proj.Cancellation = &c
	} else if loop.IntentID != "" {
		if intent, e := db.GetIntent(loop.IntentID); e == nil {
			c := contract.ProjectCancellationFromDispatch(intent.Cancel)
			proj.Cancellation = &c
		}
	}

	root := proj.RootID
	if root != "" {
		ids, e := db.ListOutstandingReservationIDs(root)
		if e == nil {
			proj.OutstandingReservations = ids
		}
	}

	proj.ModelCalls = int(counters.ModelCalls.Load())
	proj.FilesystemReads = int(counters.FilesystemReads.Load())
	proj.FilesystemWrites = int(counters.FilesystemWrites.Load())

	if e := proj.Validate(); e != nil {
		return proj, e
	}
	_ = db.PersistStatusProjection(proj)
	return proj, nil
}

// InspectPolicyObservational reads policy without dispatching model work (R04).
func (s *Service) InspectPolicyObservational(rootID, policyID, escalationAttempt string, counters *ObservationalCounters) (contract.PolicyInspectResult, error) {
	if counters == nil {
		counters = &ObservationalCounters{}
	}
	counters.FilesystemReads.Add(1)
	out := contract.PolicyInspectResult{
		SchemaVersion:   contract.StatusSchemaVersion,
		ContractVersion: contract.StatusContractID,
		RootID:          rootID,
		PolicyID:        policyID,
		Dispatched:      false,
		Preview:         false,
	}
	if escalationAttempt != "" {
		out.DeniedEscalation = true
		out.EscalationAttempt = escalationAttempt
		out.Detail = "escalation denied; policy inspect is observational"
	}

	db, e := s.ensureStatusStore()
	if e != nil {
		return out, e
	}
	if rootID != "" {
		ids, le := db.ListOutstandingReservationIDs(rootID)
		if le == nil {
			out.OutstandingReservations = ids
		}
	}
	_ = db.Close()
	if out.OutstandingReservations == nil {
		out.OutstandingReservations = []string{}
	}
	if policyID != "" {
		if _, e := s.ReadPolicy(rootID, policyID); e != nil {
			out.Detail = strings.TrimSpace(out.Detail + "; " + e.Error())
		}
	} else if rootID != "" {
		if _, e := s.ReadPolicyBinding(rootID); e != nil {
			out.Detail = strings.TrimSpace(out.Detail + "; " + e.Error())
		}
	}
	out.ModelCalls = int(counters.ModelCalls.Load())
	return out, out.Validate()
}

// PreviewPolicyChange is observational — preserves outstanding reservations; no model work (R04).
func (s *Service) PreviewPolicyChange(rootID string, counters *ObservationalCounters) (contract.PolicyInspectResult, error) {
	if counters == nil {
		counters = &ObservationalCounters{}
	}
	before, e := s.InspectPolicyObservational(rootID, "", "", counters)
	if e != nil {
		return before, e
	}
	before.Preview = true
	before.Detail = "preview preserves outstanding reservations; no refill; no live-evidence claim"
	before.OutstandingReservations = append([]string(nil), before.OutstandingReservations...)
	before.ModelCalls = int(counters.ModelCalls.Load())
	before.Dispatched = false
	return before, before.Validate()
}

// ConsumeStatusContract is the fixture optional-client consumer (R05/R07).
// GAMBIT itself is explicitly deferred; this proves contract conformance only.
func (s *Service) ConsumeStatusContract(req contract.ClientConformanceRequest, projectionJSON []byte, counters *ObservationalCounters) (contract.ClientConformanceResult, error) {
	if counters == nil {
		counters = &ObservationalCounters{}
	}
	if e := req.Validate(); e != nil {
		return contract.ClientConformanceResult{}, e
	}
	result := contract.ClientConformanceResult{
		SchemaVersion:   contract.StatusSchemaVersion,
		ContractVersion: req.ContractVersion,
		OptionalGAMBIT:  "explicitly_deferred",
		ModelCalls:      0,
	}
	for _, m := range req.Modes {
		switch m {
		case contract.ClientModeNoGUI:
			result.NoGUI = true
		case contract.ClientModeNoColor:
			result.NoColor = true
		}
	}

	if !contract.ContractSupported(req.ContractVersion) {
		result.Supported = false
		result.Error = "unsupported status contract version: " + req.ContractVersion
		diag := contract.CompatibilityDiagnostic{
			SchemaVersion:       contract.StatusSchemaVersion,
			PresentedContract:   req.ContractVersion,
			SupportedContracts:  append([]string(nil), contract.SupportedStatusContracts...),
			AuthorityMutations:  "rejected",
			ReadOnlyAllowed:     req.ReadOnly,
			DispatchedModelWork: false,
			Detail:              "future schema cannot be guessed into permission grants",
		}
		result.Compatibility = &diag
		if req.AuthorityMutation {
			result.MutationRejected = true
		} else if req.ReadOnly {
			result.MutationRejected = false
			counters.FilesystemReads.Add(1)
		} else {
			result.MutationRejected = true
		}
		result.ModelCalls = int(counters.ModelCalls.Load())
		db, e := s.ensureStatusStore()
		if e == nil {
			_ = db.PersistClientConformance("unsupported-"+req.ContractVersion, result)
			_ = db.Close()
		}
		return result, nil
	}

	result.Supported = true
	if req.AuthorityMutation {
		result.MutationRejected = true
		result.Error = "fixture client rejects authority-bearing mutations on status contract surface"
	}
	if len(projectionJSON) > 0 {
		var proj contract.StatusProjection
		if e := json.Unmarshal(projectionJSON, &proj); e != nil {
			return result, e
		}
		if proj.ContractVersion != "" && !contract.ContractSupported(proj.ContractVersion) {
			result.Supported = false
			result.Error = "projection contract unsupported"
			return result, nil
		}
		result.ConsumedProjection = true
		counters.FilesystemReads.Add(1)
	}
	result.ModelCalls = int(counters.ModelCalls.Load())
	db, e := s.ensureStatusStore()
	if e == nil {
		_ = db.PersistClientConformance("ok-"+req.ContractVersion, result)
		_ = db.Close()
	}
	return result, nil
}
