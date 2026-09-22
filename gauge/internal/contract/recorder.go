package contract

import (
	"errors"
	"fmt"
	"math"
	"time"
)

// Terminal execution states — distinct from acceptance evidence.
const (
	TerminalCompleted = "completed"
	TerminalFailed    = "failed"
	TerminalCancelled = "cancelled"
	TerminalAbandoned = "abandoned"

	CostKnown     = "known"
	CostEstimated = "estimated"
	CostUnknown   = "unknown"

	AcceptanceAccepted = "accepted"
	AcceptanceRejected = "rejected"
	AcceptanceNone     = "none"
)

// AttemptRecord is the shared native/original-v3 recorder schema.
type AttemptRecord struct {
	SchemaVersion     int               `json:"schema_version"`
	ID                string            `json:"id"`
	TrialID           string            `json:"trial_id"`
	ProtocolID        string            `json:"protocol_id"`
	ProtocolDigest    string            `json:"protocol_digest"`
	ArmID             string            `json:"arm_id"`
	ArmKind           string            `json:"arm_kind"`
	TaskRootID        string            `json:"task_root_id"`
	AttemptID         string            `json:"attempt_id"`
	InvocationRef     string            `json:"invocation_ref"`
	ConfigRef         string            `json:"configuration_ref"`
	EnvironmentRef    string            `json:"environment_ref"`
	TerminalState     string            `json:"terminal_execution_state"`
	Acceptance        string            `json:"acceptance"`
	AcceptanceEvidence string           `json:"acceptance_evidence,omitempty"`
	CostKind          string            `json:"cost_kind"`
	CostAmount        *float64          `json:"cost_amount,omitempty"`
	CostUnit          string            `json:"cost_unit"`
	ResourceCoverage  []string          `json:"resource_coverage"`
	StartedAt         string            `json:"started_at"`
	EndedAt           string            `json:"ended_at"`
	Excluded          bool              `json:"excluded"`
	Censored          bool              `json:"censored"`
	ExclusionReason   string            `json:"exclusion_reason,omitempty"`
	Metadata          map[string]string `json:"metadata,omitempty"`
}

func (r AttemptRecord) Validate() error {
	if r.SchemaVersion != InstrumentSchemaVersion {
		return errors.New("unknown attempt schema version")
	}
	for _, pair := range []struct {
		label string
		id    string
		req   bool
	}{
		{"attempt_record", r.ID, true},
		{"trial", r.TrialID, true},
		{"protocol", r.ProtocolID, true},
		{"protocol_digest", r.ProtocolDigest, true},
		{"arm", r.ArmID, true},
		{"task_root", r.TaskRootID, true},
		{"attempt", r.AttemptID, true},
		{"invocation", r.InvocationRef, true},
		{"configuration", r.ConfigRef, true},
		{"environment", r.EnvironmentRef, true},
	} {
		if e := validateID(pair.label, pair.id, pair.req); e != nil {
			return e
		}
	}
	switch r.ArmKind {
	case ArmNative, ArmOriginalV3, ArmStructural, ArmManaged:
	default:
		return errors.New("unknown attempt arm kind")
	}
	switch r.TerminalState {
	case TerminalCompleted, TerminalFailed, TerminalCancelled, TerminalAbandoned:
	default:
		return errors.New("unknown terminal execution state")
	}
	switch r.Acceptance {
	case AcceptanceAccepted, AcceptanceRejected, AcceptanceNone:
	default:
		return errors.New("unknown acceptance state")
	}
	// Successful process termination alone is not acceptance.
	if r.TerminalState == TerminalCompleted && r.Acceptance == AcceptanceAccepted && r.AcceptanceEvidence == "" {
		return errors.New("acceptance requires independent evidence")
	}
	switch r.CostKind {
	case CostKnown, CostEstimated, CostUnknown:
	default:
		return errors.New("unknown cost kind")
	}
	if r.CostKind == CostKnown {
		if r.CostAmount == nil || math.IsNaN(*r.CostAmount) || math.IsInf(*r.CostAmount, 0) {
			return errors.New("known cost must be finite")
		}
	} else if r.CostAmount != nil && r.CostKind == CostUnknown {
		return errors.New("unknown cost must omit numeric value")
	}
	if r.CostUnit == "" {
		return errors.New("cost unit required")
	}
	if len(r.ResourceCoverage) == 0 {
		return errors.New("resource coverage required")
	}
	if r.StartedAt == "" || r.EndedAt == "" {
		return errors.New("attempt timestamps required")
	}
	if _, e := time.Parse(time.RFC3339, r.StartedAt); e != nil {
		return errors.New("invalid started_at")
	}
	if _, e := time.Parse(time.RFC3339, r.EndedAt); e != nil {
		return errors.New("invalid ended_at")
	}
	if e := ValidateMetadata(r.Metadata); e != nil {
		return e
	}
	return nil
}

func DecodeAttemptRecord(raw []byte) (AttemptRecord, error) {
	var r AttemptRecord
	if e := StrictJSON(raw, &r); e != nil {
		return r, e
	}
	return r, r.Validate()
}

// AttemptSummary is independent arithmetic over all attempts (failed/cancelled remain).
type AttemptSummary struct {
	AttemptCount          int      `json:"attempt_count"`
	KnownCompleteTotal    *float64 `json:"known_complete_total"`
	KnownCompleteKnown    bool     `json:"known_complete_known"`
	KnownSubtotal         float64  `json:"known_subtotal"`
	AcceptedDistinctRoots int      `json:"accepted_distinct_task_roots"`
	CostPerAccepted       *float64 `json:"cost_per_accepted_task"`
	RatioDefined          bool     `json:"ratio_defined"`
	RatioUnknown          bool     `json:"ratio_unknown"`
	TotalUnknown          bool     `json:"total_unknown"`
}

// SummarizeAttempts implements the independent recorder arithmetic (vectors K/Z/U).
func SummarizeAttempts(records []AttemptRecord) (AttemptSummary, error) {
	var sum AttemptSummary
	if len(records) == 0 {
		return sum, errors.New("no attempts")
	}
	unit := records[0].CostUnit
	accepted := map[string]bool{}
	var knownTotal float64
	allKnown := true
	hasUnknown := false
	for _, r := range records {
		if e := r.Validate(); e != nil {
			return sum, e
		}
		if r.CostUnit != unit {
			return sum, fmt.Errorf("incompatible cost unit %s vs %s", unit, r.CostUnit)
		}
		sum.AttemptCount++
		switch r.CostKind {
		case CostKnown:
			if r.CostAmount == nil {
				return sum, errors.New("known cost missing amount")
			}
			knownTotal += *r.CostAmount
			sum.KnownSubtotal += *r.CostAmount
		case CostEstimated:
			// Estimated stays distinct from known/unknown; never forms a known complete total.
			allKnown = false
		case CostUnknown:
			allKnown = false
			hasUnknown = true
		}
		if r.Acceptance == AcceptanceAccepted {
			accepted[r.TaskRootID] = true
		}
	}
	sum.AcceptedDistinctRoots = len(accepted)
	if allKnown && !hasUnknown {
		v := knownTotal
		sum.KnownCompleteTotal = &v
		sum.KnownCompleteKnown = true
		sum.TotalUnknown = false
	} else {
		sum.TotalUnknown = true
		sum.KnownCompleteKnown = false
	}
	if sum.AcceptedDistinctRoots == 0 {
		sum.RatioDefined = false
		sum.RatioUnknown = false
		return sum, nil
	}
	if sum.TotalUnknown {
		sum.RatioDefined = false
		sum.RatioUnknown = true
		return sum, nil
	}
	ratio := *sum.KnownCompleteTotal / float64(sum.AcceptedDistinctRoots)
	sum.CostPerAccepted = &ratio
	sum.RatioDefined = true
	return sum, nil
}

// WeightedGroup is one arm/stratum group for weighted ratio (vector W).
type WeightedGroup struct {
	Total         float64
	AcceptedRoots int
}

// WeightedRatio returns combined total/accepted — never the unweighted mean of group ratios.
func WeightedRatio(groups []WeightedGroup) (float64, error) {
	var total float64
	var accepted int
	for _, g := range groups {
		if g.AcceptedRoots < 0 || g.Total < 0 {
			return 0, errors.New("negative weighted group")
		}
		total += g.Total
		accepted += g.AcceptedRoots
	}
	if accepted == 0 {
		return 0, errors.New("weighted ratio undefined with zero accepted")
	}
	return total / float64(accepted), nil
}
