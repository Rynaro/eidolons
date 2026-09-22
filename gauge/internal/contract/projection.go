package contract

import "reflect"

type Requirement struct {
	ID       string `json:"id"`
	OracleID string `json:"oracle_id"`
}
type Candidate struct {
	Identity       map[string]string `json:"identity"`
	RequiredChecks []Requirement     `json:"required_checks,omitempty"`
}
type Observation struct {
	EventID             string            `json:"event_id"`
	Sequence            int               `json:"sequence"`
	Identity            map[string]string `json:"identity"`
	CheckID             string            `json:"check_id"`
	OracleID            string            `json:"oracle_id"`
	Outcome             string            `json:"outcome"`
	MakerInvocationID   string            `json:"maker_invocation_id"`
	CheckerInvocationID string            `json:"checker_invocation_id"`
}
type ProjectionInput struct {
	Candidate       Candidate         `json:"candidate"`
	Observations    []Observation     `json:"observations"`
	CurrentIdentity map[string]string `json:"current_identity"`
	Evidence        map[string]string `json:"evidence"`
}
type Grade struct {
	Status string `json:"status"`
}
type Acceptance struct {
	Status  string   `json:"status"`
	Reasons []string `json:"reasons"`
}
type Check struct {
	ID                  string  `json:"id"`
	OracleID            string  `json:"oracle_id"`
	EventID             *string `json:"event_id"`
	Outcome             string  `json:"outcome"`
	ArtifactIntegrity   string  `json:"artifact_integrity"`
	ExecutionProvenance string  `json:"execution_provenance"`
}
type Projection struct {
	CandidateStatus     Grade      `json:"candidate_status"`
	Checks              []Check    `json:"checks"`
	ArtifactIntegrity   Grade      `json:"artifact_integrity"`
	ExecutionProvenance Grade      `json:"execution_provenance"`
	AcceptanceStatus    Acceptance `json:"acceptance_status"`
}

// Project compares captured typed inputs. It is not a current filesystem
// snapshotter. Serialized labels cannot establish independent provenance.
func Project(p ProjectionInput) Projection {
	result := Projection{Checks: []Check{}, AcceptanceStatus: Acceptance{Status: "not-accepted", Reasons: []string{}}, ArtifactIntegrity: Grade{"unavailable"}, ExecutionProvenance: Grade{"unavailable"}, CandidateStatus: Grade{"unavailable"}}
	current := len(p.Candidate.Identity) > 0 && reflect.DeepEqual(p.Candidate.Identity, p.CurrentIdentity)
	if current {
		result.CandidateStatus.Status = "current"
	} else {
		if len(p.Candidate.Identity) > 0 {
			result.CandidateStatus.Status = "stale"
		}
		result.AcceptanceStatus.Reasons = append(result.AcceptanceStatus.Reasons, "candidate-unavailable-or-stale")
	}
	if len(p.Candidate.RequiredChecks) == 0 {
		result.AcceptanceStatus.Reasons = append(result.AcceptanceStatus.Reasons, "mandatory-check-set-empty")
	}
	for _, required := range p.Candidate.RequiredChecks {
		var latest *Observation
		for i := range p.Observations {
			o := &p.Observations[i]
			if reflect.DeepEqual(o.Identity, p.Candidate.Identity) && o.CheckID == required.ID && o.OracleID == required.OracleID && (latest == nil || o.Sequence > latest.Sequence) {
				latest = o
			}
		}
		c := Check{ID: required.ID, OracleID: required.OracleID, Outcome: "missing", ArtifactIntegrity: "unavailable", ExecutionProvenance: "unavailable"}
		if latest != nil {
			id := latest.EventID
			c.EventID = &id
			c.Outcome = latest.Outcome
			if c.Outcome == "" {
				c.Outcome = "unknown"
			}
			c.ExecutionProvenance = "self-attested"
			if grade, ok := p.Evidence[id]; ok {
				c.ArtifactIntegrity = grade
			}
		}
		result.Checks = append(result.Checks, c)
		if c.Outcome != "pass" {
			result.AcceptanceStatus.Reasons = append(result.AcceptanceStatus.Reasons, c.ID+":"+c.Outcome)
		}
		if c.ArtifactIntegrity != "verified" {
			result.AcceptanceStatus.Reasons = append(result.AcceptanceStatus.Reasons, c.ID+":evidence-"+c.ArtifactIntegrity)
		}
		result.AcceptanceStatus.Reasons = append(result.AcceptanceStatus.Reasons, c.ID+":unqualified-provenance")
	}
	if len(result.Checks) > 0 {
		result.ArtifactIntegrity.Status = "verified"
	}
	for _, c := range result.Checks {
		if c.EventID != nil {
			result.ExecutionProvenance.Status = "self-attested"
		}
	}
	for _, grade := range []string{"unavailable", "changed", "missing"} {
		for _, c := range result.Checks {
			if c.ArtifactIntegrity == grade {
				result.ArtifactIntegrity.Status = grade
			}
		}
	}
	return result
}
