package controller

import (
	"errors"
	"fmt"
	"math"
	"strings"
	"time"

	"github.com/Rynaro/eidolons/gauge/internal/contract"
	"github.com/Rynaro/eidolons/gauge/internal/store"
)

func (s *Service) ensureContextStore() (*store.Store, error) {
	db, e := s.preferencesStore()
	if e != nil {
		return nil, e
	}
	if e = db.EnsureContextNamespaces(); e != nil {
		_ = db.Close()
		return nil, e
	}
	return db, nil
}

// EnsureContextNamespaces adds typed context-manager buckets under schema 2.
func (s *Service) EnsureContextNamespaces() error {
	db, e := s.ensureContextStore()
	if e != nil {
		return e
	}
	return db.Close()
}

// OpenContextSession creates a core-context session; optional adapter is out of scope.
func (s *Service) OpenContextSession(id, rootID string) (contract.ContextSession, error) {
	sess := contract.ContextSession{
		SchemaVersion:   contract.ContextSchemaVersion,
		ID:              id,
		RootID:          rootID,
		Slice:           contract.ContextSliceCore,
		OptionalAdapter: contract.OptionalAdapterOutOfScope,
		CreatedAt:       s.opts.Clock().UTC().Format(time.RFC3339),
	}
	if e := sess.Validate(); e != nil {
		return sess, e
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return sess, e
	}
	defer db.Close()
	return sess, db.PersistContextSession(sess)
}

// ReuseEvidence validates source/criteria/environment dependencies before reuse (R01).
func (s *Service) ReuseEvidence(req contract.EvidenceReuseRequest) (contract.EvidenceReuseResult, error) {
	if e := req.Validate(); e != nil {
		return contract.EvidenceReuseResult{}, e
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return contract.EvidenceReuseResult{}, e
	}
	defer db.Close()

	cand := req.Candidate
	if e := db.PersistEvidenceArtifact(cand); e != nil {
		return contract.EvidenceReuseResult{}, e
	}

	out := contract.EvidenceReuseResult{
		SchemaVersion: contract.ContextSchemaVersion,
		EvidenceID:    cand.ID,
	}

	// Unrelated control: reuse only with a proven dependency relation.
	if req.ControlEvidenceID != "" && req.ControlEvidenceID != cand.ID {
		if !req.ProvenDependency {
			out.Outcome = contract.EvidenceReuseInvalidated
			out.Reasons = []string{contract.InvalidateNoDependency}
			out.Reused = false
			return out, out.Validate()
		}
		out.Outcome = contract.EvidenceReuseUnrelated
		out.Reused = true
		return out, out.Validate()
	}

	var reasons []string
	if !cand.Present {
		reasons = append(reasons, contract.InvalidateMissingArtifact)
	}
	if req.CurrentSourceDigest != "" && req.CurrentSourceDigest != cand.SourceDigest {
		reasons = append(reasons, contract.InvalidateSourceMutated)
	}
	if req.CurrentCriteria != "" && req.CurrentCriteria != cand.CriteriaDigest {
		reasons = append(reasons, contract.InvalidateCriteriaChanged)
	}
	if len(req.CurrentEnv) > 0 && !contract.EnvDepsEqual(req.CurrentEnv, cand.EnvironmentDeps) {
		reasons = append(reasons, contract.InvalidateEnvChanged)
	}
	if len(reasons) > 0 {
		out.Outcome = contract.EvidenceReuseInvalidated
		out.Reasons = reasons
		out.Reused = false
		return out, out.Validate()
	}
	out.Outcome = contract.EvidenceReuseValid
	out.Reused = true
	return out, out.Validate()
}

// PresentBoundedEvidence returns a localized excerpt with a usable full reference (R02).
func (s *Service) PresentBoundedEvidence(req contract.PresentationRequest) (contract.BoundedPresentation, error) {
	if e := req.Validate(); e != nil {
		return contract.BoundedPresentation{}, e
	}
	out := contract.BoundedPresentation{
		SchemaVersion: contract.ContextSchemaVersion,
		Redacted:      req.Redacted,
	}
	if req.Deleted || !req.Accessible {
		out.InaccessibleReported = true
		out.FullReference = ""
		out.Excerpt = ""
		out.Detail = "permitted evidence reference inaccessible"
		out.DecisiveIncluded = false
		return out, out.Validate()
	}

	ref := "evidence://" + req.EvidenceID
	out.FullReference = ref

	body := req.FullBody
	if req.Redacted {
		body = "[redacted] " + body
	}
	bound := req.PresentationBound
	start := req.DecisiveOffset
	if start < 0 {
		start = 0
	}
	if start > len(body) {
		start = len(body)
	}
	end := start + bound
	if end > len(body) {
		end = len(body)
	}
	// Prefer a window that includes the decisive assertion; fall back to a head excerpt.
	if start+bound <= len(body) || start < len(body) {
		out.Excerpt = body[start:end]
		out.DecisiveIncluded = start <= req.DecisiveOffset && req.DecisiveOffset < end
	} else {
		if len(body) > bound {
			out.Excerpt = body[:bound]
		} else {
			out.Excerpt = body
		}
		out.DecisiveIncluded = req.DecisiveOffset < len(out.Excerpt)
	}
	// Tail-only presentation would miss a decisive assertion near the start of a long body.
	if req.DecisiveOffset >= 0 && req.DecisiveOffset < len(body) && !out.DecisiveIncluded {
		// Re-center on decisive content.
		end = req.DecisiveOffset + bound
		if end > len(body) {
			end = len(body)
		}
		start = end - bound
		if start < 0 {
			start = 0
		}
		out.Excerpt = body[start:end]
		out.DecisiveIncluded = true
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return out, e
	}
	defer db.Close()
	_ = db // presentation is observational; session already ensured
	return out, out.Validate()
}

// SucceedContext retains mandatory pins and outstanding obligations (R03).
func (s *Service) SucceedContext(req contract.SuccessionRequest) (contract.SuccessionResult, error) {
	if e := req.Validate(); e != nil {
		return contract.SuccessionResult{}, e
	}
	out := contract.SuccessionResult{
		SchemaVersion:       contract.ContextSchemaVersion,
		Mode:                req.Mode,
		RetainedPins:        append([]contract.ContextPin(nil), req.Pins...),
		RetainedObligations: append([]contract.TaskObligation(nil), req.Obligations...),
		FabricatedHistory:   false,
	}
	have := map[string]bool{}
	for _, p := range req.Pins {
		have[p.ID] = true
	}
	for _, id := range contract.DefaultContextPins {
		if !have[id] {
			out.MissingMandatory = append(out.MissingMandatory, id)
		}
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return out, e
	}
	defer db.Close()
	return out, out.Validate()
}

// RecallMemory continues without treating optional memory as authoritative (R04/R08/R09).
func (s *Service) RecallMemory(req contract.MemoryRecallRequest) (contract.MemoryRecallResult, error) {
	if e := req.Validate(); e != nil {
		return contract.MemoryRecallResult{}, e
	}
	out := contract.MemoryRecallResult{
		SchemaVersion:         contract.ContextSchemaVersion,
		ReceiptPromoted:       false,
		AuthoritativeUse:      false,
		CrystaliumOperational: false,
	}
	if !req.MCPAvailable {
		out.Status = contract.MemoryUnavailable
		out.Detail = "optional memory MCP unavailable; delivery continues without memory authority"
		out.GuidancePresented = false
		return out, out.Validate()
	}

	now := req.Now
	if now == "" {
		now = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	nowT, _ := contract.ParseRFC3339OrEmpty(now)

	db, e := s.ensureContextStore()
	if e != nil {
		return out, e
	}
	defer db.Close()

	var conflicts []string
	var invalids []string
	bodies := map[string][]string{} // applicability key → bodies

	for _, it := range req.Items {
		if e := db.PersistMemoryItem(it); e != nil {
			return out, e
		}
		reject := ""
		switch {
		case it.Deleted:
			reject = contract.MemorySuperseded
		case it.SupersededBy != "":
			reject = contract.MemorySuperseded
		case it.ProjectScope != "" && req.ProjectScope != "" && it.ProjectScope != req.ProjectScope:
			reject = contract.MemoryForeign
		case strings.Contains(strings.ToLower(it.Body), "poison"):
			reject = contract.MemoryPoisoned
		case strings.Contains(strings.ToLower(it.Applicability), "stale_test"):
			reject = contract.MemoryStaleClaim
		case it.ExpiresAt != "":
			exp, pe := contract.ParseRFC3339OrEmpty(it.ExpiresAt)
			if pe == nil && !exp.IsZero() && !nowT.IsZero() && !exp.After(nowT) {
				reject = contract.MemoryExpired
			}
		case req.CurrentRevision != "" && it.Revision != "" && it.Revision != req.CurrentRevision:
			reject = contract.MemoryInvalidDeps
		}
		if reject != "" {
			out.RejectedIDs = append(out.RejectedIDs, it.ID)
			invalids = append(invalids, reject)
			continue
		}
		out.RetrievableIDs = append(out.RetrievableIDs, it.ID)
		key := it.Applicability
		bodies[key] = append(bodies[key], it.Body)
	}

	for _, list := range bodies {
		uniq := map[string]bool{}
		for _, b := range list {
			uniq[b] = true
		}
		if len(uniq) > 1 {
			conflicts = append(conflicts, "applicability_conflict")
		}
	}

	switch {
	case len(out.RetrievableIDs) == 0 && len(out.RejectedIDs) > 0:
		out.Status = contract.MemoryUntrusted
		out.InvalidityPresented = true
		out.GuidancePresented = false
		out.Detail = "no trusted scoped memory; " + strings.Join(uniqueStrings(invalids), ",")
	case len(conflicts) > 0:
		out.Status = contract.MemoryConflict
		out.ConflictPresented = true
		out.GuidancePresented = false // conflict must be presented before guidance use
		out.Detail = "conflicting memories presented; no silent newest-text-wins"
	case len(invalids) > 0 && len(out.RetrievableIDs) > 0:
		out.Status = contract.MemoryInvalidDeps
		out.InvalidityPresented = true
		out.GuidancePresented = false
		out.Detail = "invalid dependencies presented before guidance"
	case len(out.RetrievableIDs) == 0:
		out.Status = contract.MemoryRecallFail
		out.Detail = "failed recall; continue without memory authority"
	default:
		out.Status = contract.MemoryScopedOK
		out.GuidancePresented = true
		out.Detail = "scoped memory retrievable without granting authority"
	}
	return out, out.Validate()
}

func uniqueStrings(in []string) []string {
	seen := map[string]bool{}
	var out []string
	for _, s := range in {
		if seen[s] {
			continue
		}
		seen[s] = true
		out = append(out, s)
	}
	return out
}

// EnforceBatchTools applies the same operation permissions as individual calls (R05).
func (s *Service) EnforceBatchTools(req contract.BatchToolRequest) (contract.BatchToolResult, error) {
	if e := req.Validate(); e != nil {
		return contract.BatchToolResult{}, e
	}
	out := contract.BatchToolResult{
		SchemaVersion: contract.ContextSchemaVersion,
		Bounded:       true,
	}
	for _, op := range req.Ops {
		oc := contract.ToolOpOutcome{OpID: op.OpID}
		perm := op.Permission
		if perm == "" {
			perm = "allow:" + op.Kind + "." + op.Target
		}
		if contract.RestrictionDenies(req.AccessRestrictions, perm) ||
			contract.RestrictionDenies(req.AccessRestrictions, "deny:"+strings.TrimPrefix(strings.TrimPrefix(perm, "allow:"), "deny:")) {
			oc.Result = contract.PermDenied
			oc.Reason = "denied at qualified enforcement boundary"
			if req.ViaCodeWrapper {
				oc.Reason = "generic code wrapper cannot bypass deny"
			}
		} else {
			oc.Result = contract.PermAllowed
		}
		out.Outcomes = append(out.Outcomes, oc)
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return out, e
	}
	defer db.Close()
	return out, out.Validate()
}

// TriggerLifecycle applies configured debounce/hysteresis without universal thresholds (R06).
func (s *Service) TriggerLifecycle(req contract.LifecycleTriggerRequest) (contract.LifecycleTriggerResult, error) {
	if e := req.Validate(); e != nil {
		return contract.LifecycleTriggerResult{}, e
	}
	out := contract.LifecycleTriggerResult{SchemaVersion: contract.ContextSchemaVersion}

	now := req.Now
	if now == "" {
		now = s.opts.Clock().UTC().Format(time.RFC3339)
	}
	nowT, ne := contract.ParseRFC3339OrEmpty(now)
	lastT, le := contract.ParseRFC3339OrEmpty(req.LastTriggerAt)

	// Unchanged state fingerprint within debounce window → skip.
	if req.LastDigest != "" && req.LastDigest == req.TriggerDigest && ne == nil && le == nil && !lastT.IsZero() {
		elapsed := nowT.Sub(lastT)
		if req.DebounceWindowMS > 0 && elapsed >= 0 && elapsed <= time.Duration(req.DebounceWindowMS)*time.Millisecond {
			out.Outcome = contract.LifecycleSkippedDuplicate
			out.Detail = "unchanged trigger digest within configured debounce window"
			return out, out.Validate()
		}
	}

	// Threshold oscillation within hysteresis band → skip duplicate lifecycle work.
	if req.HysteresisBand > 0 && req.LastDigest == req.TriggerDigest {
		delta := math.Abs(req.ZoneUtilization - req.LastZone)
		if delta <= req.HysteresisBand {
			out.Outcome = contract.LifecycleSkippedDuplicate
			out.Detail = "zone oscillation within configured hysteresis band"
			return out, out.Validate()
		}
	}

	out.Outcome = contract.LifecycleExecuted
	out.Detail = "lifecycle work executed for changed or outside-band trigger"
	db, e := s.ensureContextStore()
	if e != nil {
		return out, e
	}
	defer db.Close()
	return out, out.Validate()
}

// MeasureOverhead distinguishes host-visible payload from source-file and labeled estimates (R07).
func (s *Service) MeasureOverhead(req contract.OverheadRequest) (contract.OverheadReport, error) {
	if e := req.Validate(); e != nil {
		return contract.OverheadReport{}, e
	}
	out := contract.OverheadReport{
		SchemaVersion: contract.ContextSchemaVersion,
		Samples:       append([]contract.OverheadSample(nil), req.Samples...),
		Conflated:     false,
	}
	estimatesLabeled := true
	for _, sample := range req.Samples {
		switch sample.Kind {
		case contract.VisibilityHostVisible:
			out.HostVisibleBytes += sample.Bytes
		case contract.VisibilitySourceFile:
			out.SourceFileBytes += sample.Bytes
		case contract.VisibilityEstimated:
			out.EstimatedTokens += sample.EstimatedTokens
			if !sample.EstimateLabeled || sample.Label == "" {
				estimatesLabeled = false
			}
		case contract.VisibilityUnsupported:
			out.UnsupportedNoted = true
		default:
			return out, fmt.Errorf("unknown overhead sample kind %q", sample.Kind)
		}
	}
	out.EstimatesLabeled = estimatesLabeled || out.EstimatedTokens == 0
	if out.EstimatedTokens > 0 && !out.EstimatesLabeled {
		return out, errors.New("estimated tokens must be labeled")
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return out, e
	}
	defer db.Close()
	if e := db.PersistOverheadReport(req.SessionID, out); e != nil {
		return out, e
	}
	return out, out.Validate()
}

// RecordNavigation distinguishes discovery, retrieval, and cited use (R10).
func (s *Service) RecordNavigation(ev contract.NavigationEvent) (contract.NavigationRecord, error) {
	if e := ev.Validate(); e != nil {
		return contract.NavigationRecord{}, e
	}
	rec := contract.NavigationRecord{
		SchemaVersion: contract.ContextSchemaVersion,
		EvidenceID:    ev.EvidenceID,
		Kind:          ev.Kind,
		CountedAsUse:  ev.Kind == contract.NavCitedUse && ev.Cited && !ev.ReachableOnly,
	}
	switch ev.Kind {
	case contract.NavDiscovery:
		rec.Detail = "reachable reference discovered; not counted as use"
	case contract.NavRetrieval:
		if ev.Truncated {
			rec.Detail = "truncated decisive fragment retrieved; not inferred comprehension"
		} else if ev.Opened {
			rec.Detail = "evidence opened/retrieved; not counted as cited use"
		} else {
			rec.Detail = "retrieval recorded without open"
		}
	case contract.NavCitedUse:
		rec.Detail = "cited source recorded as use"
	}
	if e := rec.Validate(); e != nil {
		return rec, e
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return rec, e
	}
	defer db.Close()
	return rec, db.PersistNavigationRecord(rec)
}

// RecordFeatureNA records R11/R12 as N/A when indexed/recursive features are absent.
func (s *Service) RecordFeatureNA(requirementID, testID, feature string) (contract.FeatureApplicability, error) {
	f := contract.FeatureApplicability{
		SchemaVersion:   contract.ContextSchemaVersion,
		Feature:         feature,
		Condition:       contract.FeatureConditionAbsent,
		Applicability:   contract.ApplicabilityNA,
		OptionalAdapter: contract.OptionalAdapterOutOfScope,
		RequirementID:   requirementID,
		TestID:          testID,
		Detail:          "one-justified-optional-adapter out of scope (dropped; not used); do not invent indexing/recursion",
		InventedIndex:   false,
		InventedRecurse: false,
	}
	if e := f.Validate(); e != nil {
		return f, e
	}
	db, e := s.ensureContextStore()
	if e != nil {
		return f, e
	}
	defer db.Close()
	return f, db.PersistFeatureApplicability(f)
}
