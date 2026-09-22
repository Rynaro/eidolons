// Package contract defines controller records, not a native reasoning harness.
package contract

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
)

// These identities have different meanings even when a harness reuses a label.
// Binding keeps their links explicit; no identity is derived from a process PID.
type Binding struct {
	Root        string `json:"root"`
	Assignment  string `json:"assignment"`
	Profile     string `json:"profile"`
	Method      string `json:"method"`
	Worker      string `json:"worker"`
	Invocation  string `json:"invocation"`
	Context     string `json:"context"`
	Authority   string `json:"authority"`
	Candidate   string `json:"candidate"`
	Receipt     string `json:"receipt"`
	Environment string `json:"environment"`
}

func (b Binding) Validate() error {
	for _, id := range []string{b.Root, b.Assignment, b.Profile, b.Method, b.Worker, b.Invocation, b.Context, b.Authority, b.Candidate, b.Receipt, b.Environment} {
		if id == "" {
			return errors.New("all distinct identity roles must be explicit")
		}
	}
	return nil
}

type Manifest struct {
	Version        int      `json:"schema_version"`
	RequestedModel string   `json:"requested_model"`
	ObservedModel  string   `json:"observed_model"`
	Harness        string   `json:"harness"`
	Adapter        string   `json:"adapter"`
	Methods        []string `json:"methods"`
	Environment    string   `json:"environment"`
	PolicyRefs     []string `json:"policy_refs"`
}

func (m Manifest) Identity() (string, error) {
	if m.Version != 1 || m.RequestedModel == "" || m.ObservedModel == "" || m.Harness == "" || m.Adapter == "" || m.Environment == "" || len(m.Methods) == 0 {
		return "", errors.New("invalid or unsupported execution manifest; observed unknown must be explicit")
	}
	for _, ref := range append(append([]string{}, m.Methods...), m.PolicyRefs...) {
		if ref == "" {
			return "", errors.New("empty manifest reference")
		}
	}
	data, err := json.Marshal(m)
	if err != nil {
		return "", err
	}
	return Digest(data), nil
}

func Digest(data []byte) string { sum := sha256.Sum256(data); return hex.EncodeToString(sum[:]) }

var runName = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

func ValidRoot(id string) bool { return id != "" && id != "." && id != ".." && runName.MatchString(id) }

type Root struct {
	ID         string   `json:"id"`
	Phase      string   `json:"phase"`
	Generation string   `json:"generation"`
	Inventory  string   `json:"inventory"`
	Legacy     bool     `json:"legacy"`
	Binding    Binding  `json:"binding"`
	Manifest   Manifest `json:"manifest"`
	PolicyRefs []string `json:"policy_refs"`
	Intents    []string `json:"intents"`
	Evidence   []string `json:"evidence"`
}

func (r Root) Validate() error {
	if !ValidRoot(r.ID) || (r.Phase != "staged" && r.Phase != "active") || r.Generation == "" || r.Inventory == "" {
		return errors.New("invalid or incomplete execution root")
	}
	return nil
}

type Record struct {
	ID     string          `json:"id"`
	Family string          `json:"family"`
	Kind   string          `json:"kind"`
	Body   json.RawMessage `json:"body"`
}

func (r Record) Validate() error {
	allowed := map[string]map[string]bool{"history": {"receipt": true, "event": true}, "context": {"context-reference": true}, "knowledge": {"note": true}, "policy": {"policy": true}}
	if r.ID == "" || !allowed[r.Family][r.Kind] || !json.Valid(r.Body) {
		return fmt.Errorf("invalid %s/%s record; state families cannot substitute for one another", r.Family, r.Kind)
	}
	return nil
}

type LegacyEvent struct {
	ID    string `json:"event_id"`
	Raw   []byte `json:"original_bytes"`
	Grade string `json:"evidence_grade"`
}

type FixtureInput struct {
	Outcome string `json:"outcome"`
}

func (f FixtureInput) Validate() error {
	switch f.Outcome {
	case "pass", "fail", "cancelled":
		return nil
	}
	return errors.New("fixture outcome must be pass, fail or cancelled")
}

type ObservationResult struct {
	Outcome       string `json:"outcome"`
	ObservedModel string `json:"observed_model"`
	ModelCalls    int    `json:"model_calls"`
}
type Receipt struct {
	ID            string `json:"id"`
	RootID        string `json:"root_id"`
	Outcome       string `json:"outcome"`
	ObservedModel string `json:"observed_model"`
	ModelCalls    int    `json:"model_calls"`
	Timestamp     string `json:"timestamp"`
	Grade         string `json:"evidence_grade"`
	Accepted      bool   `json:"accepted"`
	InputDigest   string `json:"input_digest"`
}
