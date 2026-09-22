package contract

import (
	"errors"
	"fmt"
	"strings"
	"time"
)

// ContextSchemaVersion is the typed V4-19 context-manager namespace under schema 2.
const ContextSchemaVersion = 1

// ContextContractID is the versioned core-context contract.
const ContextContractID = "gauge-context@1"

// Slice / optional-adapter posture (matches GAMBIT: dropped, not deferred).
const (
	ContextSliceCore              = "core-context"
	OptionalAdapterOutOfScope     = "out_of_scope"
	OptionalAdapterName           = "one-justified-optional-adapter"
	FeatureIndexedAccess          = "indexed_information_access"
	FeatureRecursiveAccess        = "recursive_information_access"
	FeatureConditionAbsent        = "feature_condition_absent"
	ApplicabilityNA               = "not_applicable"
)

// Default pin IDs mirrored from roster/pins.yaml (ECM P1) — reused, not redeclared as authority.
var DefaultContextPins = []string{
	"cortex_routing_digest",
	"active_eidolon_refusal_table",
	"esl_enforcement_mode",
	"crystalium_trust_tier_map",
	"active_plan_step_and_criteria_sha256",
	"session_budget_and_compaction_count",
}

// Evidence reuse outcomes (R01).
const (
	EvidenceReuseValid      = "reuse_valid"
	EvidenceReuseInvalidated = "invalidated"
	EvidenceReuseUnrelated  = "unrelated_control"
)

// Invalidation reasons (R01).
const (
	InvalidateMissingArtifact = "missing_artifact"
	InvalidateSourceMutated   = "source_mutated"
	InvalidateCriteriaChanged = "criteria_changed"
	InvalidateEnvChanged      = "environment_changed"
	InvalidateNoDependency    = "no_proven_dependency"
)

// Navigation kinds (R10) — availability alone is never cited use.
const (
	NavDiscovery = "discovery"
	NavRetrieval = "retrieval"
	NavCitedUse  = "cited_use"
)

// Memory trust / availability (R04/R08/R09).
const (
	MemoryUnavailable = "unavailable"
	MemoryUntrusted   = "untrusted"
	MemoryScopedOK    = "scoped_ok"
	MemoryConflict    = "conflict"
	MemoryInvalidDeps = "invalid_dependencies"
	MemoryExpired     = "expired"
	MemorySuperseded  = "superseded"
	MemoryForeign     = "foreign_project"
	MemoryPoisoned    = "poisoned"
	MemoryStaleClaim  = "stale_test_claim"
	MemoryRecallFail  = "failed_recall"
)

// Batch permission outcomes (R05).
const (
	PermAllowed = "allowed"
	PermDenied  = "denied"
)

// Debounce outcomes (R06).
const (
	LifecycleSkippedDuplicate = "skipped_duplicate"
	LifecycleExecuted         = "executed"
)

// Overhead visibility (R07).
const (
	VisibilityHostVisible = "host_visible"
	VisibilitySourceFile  = "source_file"
	VisibilityEstimated   = "estimated_tokens"
	VisibilityUnsupported = "unsupported_visibility"
)

// EvidenceArtifact is reusable evidence bound to source/criteria/environment (R01).
type EvidenceArtifact struct {
	SchemaVersion    int      `json:"schema_version"`
	ID               string   `json:"id"`
	SourceRef        string   `json:"source_ref"`
	SourceDigest     string   `json:"source_digest"`
	CriteriaDigest   string   `json:"criteria_digest"`
	EnvironmentDeps  []string `json:"environment_deps"`
	ArtifactDigest   string   `json:"artifact_digest"`
	Present          bool     `json:"present"`
	DependencyOf     []string `json:"dependency_of,omitempty"` // proven dependency edges for unrelated controls
}

func (e EvidenceArtifact) Validate() error {
	if e.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown evidence schema version")
	}
	if e.ID == "" || e.SourceRef == "" || e.SourceDigest == "" || e.CriteriaDigest == "" || e.ArtifactDigest == "" {
		return errors.New("evidence requires id, source_ref, digests")
	}
	return nil
}

// EvidenceReuseRequest asks whether prior evidence may be reused under current deps (R01).
type EvidenceReuseRequest struct {
	SchemaVersion       int               `json:"schema_version"`
	SessionID           string            `json:"session_id"`
	RootID              string            `json:"root_id"`
	Candidate           EvidenceArtifact  `json:"candidate"`
	CurrentSourceDigest string            `json:"current_source_digest"`
	CurrentCriteria     string            `json:"current_criteria_digest"`
	CurrentEnv          []string          `json:"current_environment_deps"`
	ControlEvidenceID   string            `json:"control_evidence_id,omitempty"` // unrelated control seeking reuse
	ProvenDependency    bool              `json:"proven_dependency"`
}

func (r EvidenceReuseRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown evidence reuse schema version")
	}
	if e := validateID("session", r.SessionID, true); e != nil {
		return e
	}
	if e := validateID("root", r.RootID, true); e != nil {
		return e
	}
	return r.Candidate.Validate()
}

// EvidenceReuseResult records validation outcome (R01).
type EvidenceReuseResult struct {
	SchemaVersion int      `json:"schema_version"`
	Outcome       string   `json:"outcome"`
	Reasons       []string `json:"reasons,omitempty"`
	EvidenceID    string   `json:"evidence_id"`
	Reused        bool     `json:"reused"`
}

func (r EvidenceReuseResult) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown evidence reuse result schema version")
	}
	switch r.Outcome {
	case EvidenceReuseValid, EvidenceReuseInvalidated, EvidenceReuseUnrelated:
	default:
		return fmt.Errorf("unknown evidence reuse outcome %q", r.Outcome)
	}
	return nil
}

// PresentationRequest asks for a bounded excerpt of a tool result (R02).
type PresentationRequest struct {
	SchemaVersion     int    `json:"schema_version"`
	SessionID         string `json:"session_id"`
	RootID            string `json:"root_id"`
	EvidenceID        string `json:"evidence_id"`
	FullBody          string `json:"full_body"`
	PresentationBound int    `json:"presentation_bound"`
	DecisiveOffset    int    `json:"decisive_offset"` // where the decisive assertion starts
	Redacted          bool   `json:"redacted"`
	Deleted           bool   `json:"deleted"`
	Accessible        bool   `json:"accessible"`
}

func (r PresentationRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown presentation schema version")
	}
	if r.PresentationBound < 1 {
		return errors.New("presentation_bound must be positive")
	}
	if e := validateID("session", r.SessionID, true); e != nil {
		return e
	}
	return validateID("evidence", r.EvidenceID, true)
}

// BoundedPresentation returns a localized excerpt plus usable full reference (R02).
type BoundedPresentation struct {
	SchemaVersion       int    `json:"schema_version"`
	Excerpt             string `json:"excerpt"`
	FullReference       string `json:"full_reference"`
	DecisiveIncluded    bool   `json:"decisive_included"`
	Redacted            bool   `json:"redacted"`
	InaccessibleReported bool  `json:"inaccessible_reported"`
	Detail              string `json:"detail,omitempty"`
}

func (p BoundedPresentation) Validate() error {
	if p.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown bounded presentation schema version")
	}
	if p.FullReference == "" && !p.InaccessibleReported {
		return errors.New("full reference or inaccessible report required")
	}
	return nil
}

// ContextPin is a mandatory pin retained across succession (R03); IDs from roster/pins.yaml.
type ContextPin struct {
	ID    string `json:"id"`
	Value string `json:"value"`
}

// TaskObligation is an outstanding obligation retained across succession (R03).
type TaskObligation struct {
	ID     string `json:"id"`
	Kind   string `json:"kind"` // failure | budget | check | authority
	Detail string `json:"detail"`
}

// SuccessionRequest recovers context cold or warm (R03).
type SuccessionRequest struct {
	SchemaVersion    int              `json:"schema_version"`
	SessionID        string           `json:"session_id"`
	RootID           string           `json:"root_id"`
	Mode             string           `json:"mode"` // cold | warm
	Pins             []ContextPin     `json:"pins"`
	Obligations      []TaskObligation `json:"obligations"`
	FabricateHistory bool             `json:"fabricate_history"` // must be rejected
}

func (r SuccessionRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown succession schema version")
	}
	if r.Mode != "cold" && r.Mode != "warm" {
		return errors.New("succession mode must be cold or warm")
	}
	if r.FabricateHistory {
		return errors.New("fabricating unseen history is forbidden")
	}
	if e := validateID("session", r.SessionID, true); e != nil {
		return e
	}
	return validateID("root", r.RootID, true)
}

// SuccessionResult retains pins and obligations without inventing history (R03).
type SuccessionResult struct {
	SchemaVersion      int              `json:"schema_version"`
	Mode               string           `json:"mode"`
	RetainedPins       []ContextPin     `json:"retained_pins"`
	RetainedObligations []TaskObligation `json:"retained_obligations"`
	MissingMandatory   []string         `json:"missing_mandatory,omitempty"`
	FabricatedHistory  bool             `json:"fabricated_history"` // must stay false
}

func (r SuccessionResult) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown succession result schema version")
	}
	if r.FabricatedHistory {
		return errors.New("succession must not fabricate unseen history")
	}
	return nil
}

// MemoryItem binds provenance/scope/applicability/supersession (R08).
type MemoryItem struct {
	SchemaVersion   int      `json:"schema_version"`
	ID              string   `json:"id"`
	SourceProvenance string  `json:"source_provenance"`
	ProjectScope    string   `json:"project_scope"`
	Applicability   string   `json:"applicability"`
	Revision        string   `json:"revision"`
	ExpiresAt       string   `json:"expires_at,omitempty"` // RFC3339; empty = none
	SupersededBy    string   `json:"superseded_by,omitempty"`
	Deleted         bool     `json:"deleted"`
	Body            string   `json:"body"`
	Authoritative   bool     `json:"authoritative"` // must always be false — never operational truth
	CrystaliumTier  string   `json:"crystalium_tier,omitempty"` // optional knowledge label only
}

func (m MemoryItem) Validate() error {
	if m.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown memory item schema version")
	}
	if m.Authoritative {
		return errors.New("memory must never be authoritative execution evidence")
	}
	if m.ID == "" || m.SourceProvenance == "" || m.ProjectScope == "" || m.Applicability == "" || m.Revision == "" {
		return errors.New("memory requires provenance, scope, applicability, revision")
	}
	return nil
}

// MemoryRecallRequest exercises optional memory without promoting receipts (R04/R08/R09).
type MemoryRecallRequest struct {
	SchemaVersion   int          `json:"schema_version"`
	SessionID       string       `json:"session_id"`
	RootID          string       `json:"root_id"`
	ProjectScope    string       `json:"project_scope"`
	CurrentRevision string       `json:"current_revision"`
	Now             string       `json:"now,omitempty"`
	MCPAvailable    bool         `json:"mcp_available"`
	Items           []MemoryItem `json:"items"`
	PromoteReceipt  bool         `json:"promote_receipt"` // must be rejected
}

func (r MemoryRecallRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown memory recall schema version")
	}
	if r.PromoteReceipt {
		return errors.New("memory recall must not promote receipts")
	}
	for _, it := range r.Items {
		if e := it.Validate(); e != nil {
			return e
		}
	}
	return validateID("session", r.SessionID, true)
}

// MemoryRecallResult never treats memory as authoritative (R04/R08/R09).
type MemoryRecallResult struct {
	SchemaVersion      int      `json:"schema_version"`
	Status             string   `json:"status"`
	GuidancePresented  bool     `json:"guidance_presented"`
	ConflictPresented  bool     `json:"conflict_presented"`
	InvalidityPresented bool    `json:"invalidity_presented"`
	RetrievableIDs     []string `json:"retrievable_ids,omitempty"`
	RejectedIDs        []string `json:"rejected_ids,omitempty"`
	ReceiptPromoted    bool     `json:"receipt_promoted"` // must stay false
	AuthoritativeUse   bool     `json:"authoritative_use"` // must stay false
	Detail             string   `json:"detail,omitempty"`
	CrystaliumOperational bool  `json:"crystalium_operational"` // must stay false
}

func (r MemoryRecallResult) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown memory recall result schema version")
	}
	if r.ReceiptPromoted || r.AuthoritativeUse || r.CrystaliumOperational {
		return errors.New("memory must not promote receipts or become operational truth")
	}
	return nil
}

// ToolOp is one operation inside a batch or wrapper (R05).
type ToolOp struct {
	OpID       string `json:"op_id"`
	Kind       string `json:"kind"` // tool | network | filesystem
	Target     string `json:"target"`
	Permission string `json:"permission"` // e.g. deny:secrets.write or allow:fs.read
}

// BatchToolRequest enforces identical permissions for programmatic/batched calls (R05).
type BatchToolRequest struct {
	SchemaVersion      int      `json:"schema_version"`
	SessionID          string   `json:"session_id"`
	RootID             string   `json:"root_id"`
	AccessRestrictions []string `json:"access_restrictions"`
	Ops                []ToolOp `json:"ops"`
	ViaCodeWrapper     bool     `json:"via_code_wrapper"`
}

func (r BatchToolRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown batch tool schema version")
	}
	if len(r.Ops) == 0 {
		return errors.New("batch requires at least one op")
	}
	return validateID("session", r.SessionID, true)
}

// BatchToolResult reports per-op enforcement at the qualified boundary (R05).
type BatchToolResult struct {
	SchemaVersion int               `json:"schema_version"`
	Outcomes      []ToolOpOutcome   `json:"outcomes"`
	Bounded       bool              `json:"bounded"`
}

// ToolOpOutcome is one op's allow/deny decision.
type ToolOpOutcome struct {
	OpID   string `json:"op_id"`
	Result string `json:"result"` // allowed | denied
	Reason string `json:"reason,omitempty"`
}

func (r BatchToolResult) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown batch tool result schema version")
	}
	if !r.Bounded {
		return errors.New("batch enforcement must remain bounded")
	}
	return nil
}

// LifecycleTriggerRequest models repeated context hooks (R06).
type LifecycleTriggerRequest struct {
	SchemaVersion    int     `json:"schema_version"`
	SessionID        string  `json:"session_id"`
	RootID           string  `json:"root_id"`
	TriggerDigest    string  `json:"trigger_digest"` // state fingerprint
	ZoneUtilization  float64 `json:"zone_utilization"`
	DebounceWindowMS int     `json:"debounce_window_ms"`
	HysteresisBand   float64 `json:"hysteresis_band"`
	LastTriggerAt    string  `json:"last_trigger_at,omitempty"`
	LastDigest       string  `json:"last_digest,omitempty"`
	LastZone         float64 `json:"last_zone,omitempty"`
	Now              string  `json:"now,omitempty"`
}

func (r LifecycleTriggerRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown lifecycle trigger schema version")
	}
	if r.DebounceWindowMS < 0 || r.HysteresisBand < 0 {
		return errors.New("debounce/hysteresis must be non-negative")
	}
	if r.TriggerDigest == "" {
		return errors.New("trigger_digest required")
	}
	return validateID("session", r.SessionID, true)
}

// LifecycleTriggerResult avoids duplicate work under configured debounce/hysteresis (R06).
type LifecycleTriggerResult struct {
	SchemaVersion int    `json:"schema_version"`
	Outcome       string `json:"outcome"`
	Detail        string `json:"detail,omitempty"`
}

func (r LifecycleTriggerResult) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown lifecycle trigger result schema version")
	}
	switch r.Outcome {
	case LifecycleSkippedDuplicate, LifecycleExecuted:
	default:
		return fmt.Errorf("unknown lifecycle outcome %q", r.Outcome)
	}
	return nil
}

// OverheadSample distinguishes payload kinds (R07).
type OverheadSample struct {
	Kind              string `json:"kind"` // host_visible | source_file | estimated_tokens | unsupported_visibility
	Bytes             int64  `json:"bytes,omitempty"`
	EstimatedTokens   int64  `json:"estimated_tokens,omitempty"`
	EstimateLabeled   bool   `json:"estimate_labeled"`
	Label             string `json:"label,omitempty"`
	HiddenWrapper     bool   `json:"hidden_wrapper,omitempty"`
	EagerToolSchema   bool   `json:"eager_tool_schema,omitempty"`
	DeferredToolSchema bool  `json:"deferred_tool_schema,omitempty"`
	RepeatedSkillDesc bool   `json:"repeated_skill_description,omitempty"`
}

// OverheadRequest measures context overhead (R07).
type OverheadRequest struct {
	SchemaVersion int              `json:"schema_version"`
	SessionID     string           `json:"session_id"`
	RootID        string           `json:"root_id"`
	Samples       []OverheadSample `json:"samples"`
}

func (r OverheadRequest) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown overhead schema version")
	}
	if len(r.Samples) == 0 {
		return errors.New("overhead requires samples")
	}
	return validateID("session", r.SessionID, true)
}

// OverheadReport separates host-visible from source-file and labeled estimates (R07).
type OverheadReport struct {
	SchemaVersion      int              `json:"schema_version"`
	HostVisibleBytes   int64            `json:"host_visible_bytes"`
	SourceFileBytes    int64            `json:"source_file_bytes"`
	EstimatedTokens    int64            `json:"estimated_tokens"`
	EstimatesLabeled   bool             `json:"estimates_labeled"`
	UnsupportedNoted   bool             `json:"unsupported_noted"`
	Samples            []OverheadSample `json:"samples"`
	Conflated          bool             `json:"conflated"` // must stay false
}

func (r OverheadReport) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown overhead report schema version")
	}
	if r.Conflated {
		return errors.New("overhead must not conflate host-visible with source-file or estimates")
	}
	if r.EstimatedTokens > 0 && !r.EstimatesLabeled {
		return errors.New("estimated tokens must be labeled")
	}
	return nil
}

// NavigationEvent records discovery/retrieval/cited use without inferring comprehension (R10).
type NavigationEvent struct {
	SchemaVersion int    `json:"schema_version"`
	SessionID     string `json:"session_id"`
	RootID        string `json:"root_id"`
	EvidenceID    string `json:"evidence_id"`
	Kind          string `json:"kind"` // discovery | retrieval | cited_use
	Opened        bool   `json:"opened"`
	Truncated     bool   `json:"truncated"`
	Cited         bool   `json:"cited"`
	ReachableOnly bool   `json:"reachable_only"`
}

func (e NavigationEvent) Validate() error {
	if e.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown navigation schema version")
	}
	switch e.Kind {
	case NavDiscovery, NavRetrieval, NavCitedUse:
	default:
		return fmt.Errorf("unknown navigation kind %q", e.Kind)
	}
	if e.Kind == NavCitedUse && !e.Cited {
		return errors.New("cited_use requires cited=true")
	}
	if e.ReachableOnly && e.Kind == NavCitedUse {
		return errors.New("availability alone is not cited use")
	}
	return validateID("session", e.SessionID, true)
}

// NavigationRecord is the stored classification (R10).
type NavigationRecord struct {
	SchemaVersion int    `json:"schema_version"`
	EvidenceID    string `json:"evidence_id"`
	Kind          string `json:"kind"`
	CountedAsUse  bool   `json:"counted_as_use"`
	Detail        string `json:"detail,omitempty"`
}

func (r NavigationRecord) Validate() error {
	if r.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown navigation record schema version")
	}
	if r.Kind != NavCitedUse && r.CountedAsUse {
		return errors.New("only cited_use may count as use")
	}
	return nil
}

// FeatureApplicability records WHERE-clause N/A when optional adapter features are absent (R11/R12).
type FeatureApplicability struct {
	SchemaVersion   int    `json:"schema_version"`
	Feature         string `json:"feature"`
	Condition       string `json:"condition"` // feature_condition_absent
	Applicability   string `json:"applicability"` // not_applicable
	OptionalAdapter string `json:"optional_adapter"` // out_of_scope
	RequirementID   string `json:"requirement_id"`
	TestID          string `json:"test_id"`
	Detail          string `json:"detail"`
	InventedIndex   bool   `json:"invented_index"`   // must stay false
	InventedRecurse bool   `json:"invented_recurse"` // must stay false
}

func (f FeatureApplicability) Validate() error {
	if f.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown feature applicability schema version")
	}
	if f.Condition != FeatureConditionAbsent || f.Applicability != ApplicabilityNA {
		return errors.New("R11/R12 require feature_condition_absent / not_applicable")
	}
	if f.OptionalAdapter != OptionalAdapterOutOfScope {
		return errors.New("optional adapter must be out_of_scope (dropped; not used)")
	}
	if f.InventedIndex || f.InventedRecurse {
		return errors.New("must not invent indexing or recursion")
	}
	switch f.Feature {
	case FeatureIndexedAccess, FeatureRecursiveAccess:
	default:
		return fmt.Errorf("unknown feature %q", f.Feature)
	}
	return nil
}

// ContextSession is the durable session envelope for core-context.
type ContextSession struct {
	SchemaVersion   int    `json:"schema_version"`
	ID              string `json:"id"`
	RootID          string `json:"root_id"`
	Slice           string `json:"slice"`
	OptionalAdapter string `json:"optional_adapter"`
	CreatedAt       string `json:"created_at,omitempty"`
}

func (s ContextSession) Validate() error {
	if s.SchemaVersion != ContextSchemaVersion {
		return errors.New("unknown context session schema version")
	}
	if s.Slice != ContextSliceCore {
		return errors.New("only core-context slice is implemented")
	}
	if s.OptionalAdapter != OptionalAdapterOutOfScope {
		return errors.New("optional adapter must be out_of_scope")
	}
	return validateID("session", s.ID, true)
}

// Decode helpers for CLI JSON.

func DecodeEvidenceReuseRequest(raw []byte) (EvidenceReuseRequest, error) {
	var r EvidenceReuseRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodePresentationRequest(raw []byte) (PresentationRequest, error) {
	var r PresentationRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeSuccessionRequest(raw []byte) (SuccessionRequest, error) {
	var r SuccessionRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeMemoryRecallRequest(raw []byte) (MemoryRecallRequest, error) {
	var r MemoryRecallRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeBatchToolRequest(raw []byte) (BatchToolRequest, error) {
	var r BatchToolRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeLifecycleTriggerRequest(raw []byte) (LifecycleTriggerRequest, error) {
	var r LifecycleTriggerRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeOverheadRequest(raw []byte) (OverheadRequest, error) {
	var r OverheadRequest
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

func DecodeNavigationEvent(raw []byte) (NavigationEvent, error) {
	var r NavigationEvent
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// EnvDepsEqual compares environment dependency sets without order sensitivity.
func EnvDepsEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	counts := map[string]int{}
	for _, x := range a {
		counts[x]++
	}
	for _, x := range b {
		counts[x]--
		if counts[x] < 0 {
			return false
		}
	}
	return true
}

// RestrictionDenies reports whether access_restrictions deny the given permission target.
func RestrictionDenies(restrictions []string, perm string) bool {
	perm = strings.TrimSpace(perm)
	for _, r := range restrictions {
		r = strings.TrimSpace(r)
		if r == perm {
			return strings.HasPrefix(r, "deny:")
		}
		if strings.HasPrefix(r, "deny:") && (r == perm || strings.HasPrefix(perm, r) || strings.HasPrefix(r, "deny:"+strings.TrimPrefix(perm, "allow:"))) {
			denied := strings.TrimPrefix(r, "deny:")
			target := strings.TrimPrefix(perm, "allow:")
			target = strings.TrimPrefix(target, "deny:")
			if denied == target || strings.HasPrefix(target, denied) || strings.HasPrefix(denied, target) {
				return true
			}
		}
	}
	// Also match deny:X against op permission allow:X or bare X
	for _, r := range restrictions {
		if !strings.HasPrefix(r, "deny:") {
			continue
		}
		denied := strings.TrimPrefix(r, "deny:")
		cand := strings.TrimPrefix(strings.TrimPrefix(perm, "allow:"), "deny:")
		if denied == cand {
			return true
		}
	}
	return false
}

// ParseRFC3339OrEmpty parses timestamps used by memory expiry / debounce.
func ParseRFC3339OrEmpty(s string) (time.Time, error) {
	if s == "" {
		return time.Time{}, nil
	}
	return time.Parse(time.RFC3339, s)
}
