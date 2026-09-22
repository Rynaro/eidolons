package contract

import (
	"crypto/rand"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"
)

// UsageObservation is a resource measurement, distinct from completion-check Observation.
const (
	ObservationSchemaVersion = 1

	SourceGradeObserved     = "observed"
	SourceGradeEstimated    = "estimated"
	SourceGradeSelfAttested = "self-attested"
	SourceGradeUnsupported  = "unsupported"
	SourceGradeStale        = "stale"
	SourceGradeUnknown      = "unknown"

	FreshnessFresh   = "fresh"
	FreshnessStale   = "stale"
	FreshnessUnknown = "unknown"

	KindDelta      = "delta"
	KindCumulative = "cumulative"
	KindPrefix     = "prefix"
	KindCorrection = "correction"

	ParentInclusive = "inclusive"
	ParentExclusive = "exclusive"
	ParentUnknown   = "unknown"

	DimInference   = "inference"
	DimTransfer    = "context_tool_transfer"
	DimEnvironment = "environment_work"
	DimElapsed     = "elapsed_time"
	DimHuman       = "human_intervention"

	CoverageKnown      = "known"
	CoverageUnknown    = "unknown"
	CoverageIncomplete = "incomplete"
	CoverageMissing    = "missing"
	CoverageLost       = "lost"

	TotalKnown        = "known"
	TotalUnknown      = "unknown_or_incomplete"
	TotalIncomplete   = "incomplete"
	TotalPending      = "pending"
	TotalInconsistent = "inconsistent"

	RoleDescendant = "descendant"
	RoleReviewer   = "reviewer"
	RoleRetry      = "retry"
	RoleSuccessor  = "successor"

	LineageTask        = "task"
	LineageAssignment  = "assignment"
	LineageInvocation  = "invocation"
	LineageConfig      = "configuration"
	LineagePolicy      = "policy"
	LineageCandidate   = "candidate"
	LineageIntent      = "intent"
	LineageCausalEvent = "causal-event"
	LineageRoute       = "route"
)

// StreamIdentity never merges epochs or units implicitly.
type StreamIdentity struct {
	Source         string `json:"source"`
	AdapterVersion string `json:"adapter_version"`
	AccountPool    string `json:"account_pool"`
	Dimension      string `json:"dimension"`
	Unit           string `json:"unit"`
	Scope          string `json:"scope"`
	CounterEpoch   string `json:"counter_epoch"`
}

func (s StreamIdentity) Key() string {
	b, _ := json.Marshal([]string{s.Source, s.AdapterVersion, s.AccountPool, s.Dimension, s.Unit, s.Scope, s.CounterEpoch})
	return string(b)
}

func (s StreamIdentity) Validate() error {
	for _, part := range []string{s.Source, s.AdapterVersion, s.AccountPool, s.Dimension, s.Unit, s.Scope, s.CounterEpoch} {
		if part == "" || len(part) > 256 {
			return errors.New("incomplete or oversized stream identity")
		}
	}
	return nil
}

// Typed metadata allowlist — no free-text escape hatch.
var allowedMetadataKeys = map[string]bool{
	"adapter": true, "collector": true, "host": true, "method": true,
	"model_ref": true, "pool_label": true, "unit_label": true, "note_ref": true,
}

func ValidateMetadata(m map[string]string) error {
	if m == nil {
		return nil
	}
	for k, v := range m {
		if !allowedMetadataKeys[k] {
			return fmt.Errorf("metadata key %q is not allowlisted", k)
		}
		if e := rejectPrivatePayload(k, v); e != nil {
			return e
		}
		if len(v) > 256 {
			return errors.New("metadata value exceeds bound")
		}
	}
	return nil
}

func rejectPrivatePayload(field, value string) error {
	lower := strings.ToLower(value)
	for _, canary := range []string{
		"credential", "password", "secret", "api_key", "authorization:",
		"-----begin", "raw transcript", "hidden reasoning", "tool_args=",
		"envdump=", "prompt=", "system prompt",
	} {
		if strings.Contains(lower, canary) {
			return fmt.Errorf("private payload refused in %s", field)
		}
	}
	return nil
}

func validateID(label, id string, required bool) error {
	if id == "" {
		if required {
			return fmt.Errorf("missing %s identity", label)
		}
		return nil
	}
	if len(id) > 128 || !runName.MatchString(id) {
		return fmt.Errorf("invalid %s identity", label)
	}
	if e := rejectPrivatePayload(label, id); e != nil {
		return e
	}
	return nil
}

// UsageObservation records one consumption fact with provenance.
type UsageObservation struct {
	SchemaVersion     int               `json:"schema_version"`
	ID                string            `json:"id"`
	Revision          string            `json:"revision"`
	RootID            string            `json:"root_id"`
	TaskID            string            `json:"task_id"`
	AssignmentID      string            `json:"assignment_id"`
	InvocationID      string            `json:"invocation_id"`
	ConfigurationID   string            `json:"configuration_id"`
	PolicyID          string            `json:"policy_id,omitempty"`
	CandidateID       string            `json:"candidate_id,omitempty"`
	IntentID          string            `json:"intent_id,omitempty"`
	CausalEventID     string            `json:"causal_event_id,omitempty"`
	Stream            StreamIdentity    `json:"stream"`
	Kind              string            `json:"kind"`
	Amount            *float64          `json:"amount"`
	AmountKnown       bool              `json:"amount_known"`
	Unit              string            `json:"unit"`
	SourceGrade       string            `json:"source_grade"`
	ObservationTime   string            `json:"observation_time"`
	ReceiptTime       string            `json:"receipt_time"`
	Freshness         string            `json:"freshness"`
	CursorEnd         int               `json:"cursor_end,omitempty"`
	BaselineKnown     bool              `json:"baseline_known"`
	Baseline          *float64          `json:"baseline,omitempty"`
	CoveredVersions   []string          `json:"covered_versions,omitempty"`
	AdditiveContract  bool              `json:"additive_contract,omitempty"`
	ParentScope       string            `json:"parent_scope,omitempty"`
	ChildMembership   []string          `json:"child_membership,omitempty"`
	ParentObservation string            `json:"parent_observation,omitempty"`
	RequestedModel    string            `json:"requested_model,omitempty"`
	ObservedModel     string            `json:"observed_model,omitempty"`
	Metadata          map[string]string `json:"metadata,omitempty"`
	DetailRetained    bool              `json:"detail_retained"`
}

func (o UsageObservation) Validate() error {
	if o.SchemaVersion != ObservationSchemaVersion {
		return errors.New("unknown observation schema version")
	}
	if e := validateID("observation", o.ID, true); e != nil {
		return e
	}
	if e := validateID("revision", o.Revision, true); e != nil {
		return e
	}
	if e := validateID("root", o.RootID, true); e != nil {
		return e
	}
	for _, pair := range []struct{ label, id string }{
		{"task", o.TaskID}, {"assignment", o.AssignmentID}, {"invocation", o.InvocationID},
		{"configuration", o.ConfigurationID},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	for _, pair := range []struct{ label, id string }{
		{"policy", o.PolicyID}, {"candidate", o.CandidateID}, {"intent", o.IntentID}, {"causal-event", o.CausalEventID},
		{"parent-observation", o.ParentObservation},
	} {
		if e := validateID(pair.label, pair.id, false); e != nil {
			return e
		}
	}
	if e := o.Stream.Validate(); e != nil {
		return e
	}
	if o.Unit == "" || o.Unit != o.Stream.Unit {
		return errors.New("observation unit must match stream unit")
	}
	switch o.Kind {
	case KindDelta, KindCumulative, KindPrefix, KindCorrection:
	default:
		return errors.New("unknown observation kind")
	}
	switch o.SourceGrade {
	case SourceGradeObserved, SourceGradeEstimated, SourceGradeSelfAttested, SourceGradeUnsupported, SourceGradeStale, SourceGradeUnknown:
	default:
		return errors.New("unknown source grade")
	}
	switch o.Freshness {
	case FreshnessFresh, FreshnessStale, FreshnessUnknown:
	default:
		return errors.New("unknown freshness")
	}
	if o.ObservationTime == "" || o.ReceiptTime == "" {
		return errors.New("observation and receipt times required")
	}
	if _, e := time.Parse(time.RFC3339, o.ObservationTime); e != nil {
		return errors.New("invalid observation_time")
	}
	if _, e := time.Parse(time.RFC3339, o.ReceiptTime); e != nil {
		return errors.New("invalid receipt_time")
	}
	if o.AmountKnown {
		if o.Amount == nil || math.IsNaN(*o.Amount) || math.IsInf(*o.Amount, 0) {
			return errors.New("known amount must be finite")
		}
	} else if o.Amount != nil {
		return errors.New("unknown amount must omit numeric value")
	}
	if o.ParentScope != "" {
		switch o.ParentScope {
		case ParentInclusive, ParentExclusive, ParentUnknown:
		default:
			return errors.New("unknown parent scope")
		}
	}
	if e := ValidateMetadata(o.Metadata); e != nil {
		return e
	}
	for _, field := range []struct{ label, value string }{
		{"requested_model", o.RequestedModel}, {"observed_model", o.ObservedModel},
	} {
		if field.value != "" {
			if e := rejectPrivatePayload(field.label, field.value); e != nil {
				return e
			}
		}
	}
	return nil
}

// UsageCorrection replaces one observation revision; both are preserved.
type UsageCorrection struct {
	SchemaVersion    int            `json:"schema_version"`
	ID               string         `json:"id"`
	RootID           string         `json:"root_id"`
	TargetID         string         `json:"target_id"`
	TargetRevision   string         `json:"target_revision"`
	ReplacementRev   string         `json:"replacement_revision"`
	Stream           StreamIdentity `json:"stream"`
	OldAmount        float64        `json:"old_amount"`
	NewAmount        float64        `json:"new_amount"`
	AdditiveContract bool           `json:"additive_contract"`
	CoveredInPrefix  bool           `json:"covered_in_prefix"`
	CoveredVersions  []string       `json:"covered_versions,omitempty"`
	ObservationTime  string         `json:"observation_time"`
	ReceiptTime      string         `json:"receipt_time"`
}

func (c UsageCorrection) Validate() error {
	if c.SchemaVersion != ObservationSchemaVersion {
		return errors.New("unknown correction schema version")
	}
	for _, pair := range []struct{ label, id string }{
		{"correction", c.ID}, {"root", c.RootID}, {"target", c.TargetID},
		{"target_revision", c.TargetRevision}, {"replacement_revision", c.ReplacementRev},
	} {
		if e := validateID(pair.label, pair.id, true); e != nil {
			return e
		}
	}
	if c.ID == c.TargetID {
		return errors.New("correction cannot self-reference target observation")
	}
	if e := c.Stream.Validate(); e != nil {
		return e
	}
	for _, n := range []float64{c.OldAmount, c.NewAmount} {
		if math.IsNaN(n) || math.IsInf(n, 0) {
			return errors.New("correction amounts must be finite")
		}
	}
	if c.ObservationTime == "" || c.ReceiptTime == "" {
		return errors.New("correction times required")
	}
	return nil
}

// LineageEdge binds descendant/reviewer/retry/successor to an original root.
type LineageEdge struct {
	SchemaVersion int    `json:"schema_version"`
	ID            string `json:"id"`
	RootID        string `json:"root_id"`
	Role          string `json:"role"`
	ChildID       string `json:"child_id"`
	ParentRef     string `json:"parent_ref,omitempty"`
	AssignmentID  string `json:"assignment_id,omitempty"`
	InvocationID  string `json:"invocation_id,omitempty"`
	ConfigID      string `json:"configuration_id,omitempty"`
	PolicyID      string `json:"policy_id,omitempty"`
	CandidateID   string `json:"candidate_id,omitempty"`
	IntentID      string `json:"intent_id,omitempty"`
	CausalEventID string `json:"causal_event_id,omitempty"`
	RouteDigest   string `json:"route_digest,omitempty"`
	CreatedAt     string `json:"created_at"`
}

func (e LineageEdge) Validate() error {
	if e.SchemaVersion != ObservationSchemaVersion {
		return errors.New("unknown lineage schema version")
	}
	if err := validateID("lineage", e.ID, true); err != nil {
		return err
	}
	if err := validateID("root", e.RootID, true); err != nil {
		return err
	}
	if err := validateID("child", e.ChildID, true); err != nil {
		return err
	}
	switch e.Role {
	case RoleDescendant, RoleReviewer, RoleRetry, RoleSuccessor, LineageRoute, LineageTask,
		LineageAssignment, LineageInvocation, LineageConfig, LineagePolicy,
		LineageCandidate, LineageIntent, LineageCausalEvent:
	default:
		return errors.New("unknown lineage role")
	}
	if e.CreatedAt == "" {
		return errors.New("lineage created_at required")
	}
	return nil
}

// TaskStartResult separates execution root from route digest.
type TaskStartResult struct {
	RootID      string `json:"root_id"`
	TaskID      string `json:"task_id"`
	RouteDigest string `json:"route_digest"`
	Assignment  string `json:"assignment_id"`
	Invocation  string `json:"invocation_id"`
	ConfigID    string `json:"configuration_id"`
}

// CoverageDimension is always present in summaries, even when missing.
type CoverageDimension struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	Detail string `json:"detail,omitempty"`
}

// UsageSummary is a qualified projection — never invents zero/unlimited.
type UsageSummary struct {
	RootID             string              `json:"root_id"`
	Stream             StreamIdentity      `json:"stream"`
	State              string              `json:"state"`
	Total              *float64            `json:"total"`
	TotalKnown         bool                `json:"total_known"`
	HistoricalSnapshot *float64            `json:"historical_snapshot,omitempty"`
	ChildBreakdown     *float64            `json:"child_breakdown,omitempty"`
	PendingTargets     []string            `json:"pending_targets,omitempty"`
	RuleVersion        string              `json:"rule_version"`
	Coverage           []CoverageDimension `json:"coverage"`
	RequestedModel     string              `json:"requested_model,omitempty"`
	ObservedModel      string              `json:"observed_model,omitempty"`
	CostState          string              `json:"cost_state,omitempty"`
	CostAmount         *string             `json:"cost_amount,omitempty"`
	AllowanceState     string              `json:"allowance_state,omitempty"`
	Observations       []string            `json:"observation_ids"`
	Corrections        []string            `json:"correction_ids"`
}

func DefaultCoverage() []CoverageDimension {
	return []CoverageDimension{
		{Name: DimInference, Status: CoverageMissing},
		{Name: DimTransfer, Status: CoverageMissing},
		{Name: DimEnvironment, Status: CoverageMissing},
		{Name: DimElapsed, Status: CoverageMissing},
		{Name: DimHuman, Status: CoverageMissing},
	}
}

// UsageExport is allowlisted managed inspection — never raw legacy bytes.
type UsageExport struct {
	RootID       string             `json:"root_id"`
	RouteDigest  string             `json:"route_digest,omitempty"`
	Lineage      []LineageEdge      `json:"lineage"`
	Observations []UsageObservation `json:"observations"`
	Corrections  []UsageCorrection  `json:"corrections"`
	Summaries    []UsageSummary     `json:"summaries"`
}

// NewUUID allocates a fresh RFC 4122 variant UUID (v4).
func NewUUID() string {
	var b [16]byte
	if _, e := rand.Read(b[:]); e != nil {
		panic("uuid entropy unavailable")
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

func DecodeUsageObservation(raw []byte) (UsageObservation, error) {
	var o UsageObservation
	if e := StrictJSON(raw, &o); e != nil {
		return o, e
	}
	return o, o.Validate()
}

func DecodeUsageCorrection(raw []byte) (UsageCorrection, error) {
	var c UsageCorrection
	if e := StrictJSON(raw, &c); e != nil {
		return c, e
	}
	return c, c.Validate()
}

func DecodeLineageEdge(raw []byte) (LineageEdge, error) {
	var e LineageEdge
	if err := StrictJSON(raw, &e); err != nil {
		return e, err
	}
	return e, e.Validate()
}

func SortedObservationIDs(xs []string) []string {
	out := append([]string(nil), xs...)
	sort.Strings(out)
	return out
}
